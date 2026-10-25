param(
    [string]$Owner = "release-check",
    [string]$Lua, [string]$Luac, [string]$Python,
    [string]$Slot = $env:MSUF_LUA_SLOT,
    [string]$LogDirectory,
    [switch]$ParallelContracts = $true,
    [switch]$ProfilesOnly,
    [switch]$Reproducible
)
# Compact offline release contracts. The frozen gate is never invoked.
# Fast-check owns its slot; the suite acquires it immediately afterwards.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'check-common.ps1')
Initialize-CheckTools $Lua $Luac $Python
if ($Reproducible) {
    $pins = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'check-pins.json') -Raw | ConvertFrom-Json
    if ([string]$PSVersionTable.PSVersion -ne $pins.powershell) { throw "Reproducible mode requires PowerShell $($pins.powershell)" }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $pythonVersion = (& $Python --version 2>&1 | Out-String).Trim()
        $luaVersion = & $Lua -v 2>&1 | Out-String
        $luacVersion = & $Luac -v 2>&1 | Out-String
    } finally { $ErrorActionPreference = $previous }
    if ($pythonVersion -ne "Python $($pins.python)" -or $luaVersion -notmatch ([regex]::Escape("Lua $($pins.lua) ")) -or
        $luacVersion -notmatch ([regex]::Escape("Lua $($pins.lua) "))) { throw 'Reproducible mode requires tools/check-pins.json tool versions' }
    $mirror = Join-Path $root '_local_workflows/references/wow-ui-source'
    foreach ($pin in $pins.blizzard.PSObject.Properties) {
        $actual = & git -C $mirror rev-parse --verify $pin.Name
        if ($LASTEXITCODE -ne 0 -or $actual -ne $pin.Value) { throw "Blizzard source pin mismatch: $($pin.Name)" }
        Write-Output "source $($pin.Name) $actual"
    }
}
$luaCompiler = $Luac
$FastCheck = Join-Path $PSScriptRoot 'fast-check.ps1'
if (-not $LogDirectory) { $LogDirectory = Join-Path $root 'dist/checks' }
$revision = Get-CheckRevision $root
Write-Output $revision
[void][IO.Directory]::CreateDirectory($LogDirectory)
$log = Join-Path $LogDirectory ("release-check-{0}-{1}.log" -f $Owner, (Get-Date -Format "yyyyMMdd-HHmmss"))
$utf8 = New-Object Text.UTF8Encoding($false)
$nl = [Environment]::NewLine
[IO.File]::WriteAllText($log, "release-check $Owner; $revision$nl", $utf8)
$oldPath = $env:PATH
$env:PATH = (Split-Path -Parent $Python) + [IO.Path]::PathSeparator + $env:PATH
$summary = New-Object 'System.Collections.Generic.List[string]'
$failed = 0
$wall = [Diagnostics.Stopwatch]::StartNew()
$slotTime = 0.0
$projectionTime = 0.0
$suiteSlotHeld = $false
$contractJobs = @()
$contractQueue = $null
function Invoke-Check([string]$Name, [string]$Executable, [string[]]$Arguments) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = (& $Executable @Arguments 2>&1 | Out-String)
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    [IO.File]::AppendAllText($log, "=== $Name ($code, $($timer.Elapsed.TotalSeconds.ToString('F2')) s)$nl$output$nl", $utf8)
    return @{ Ok = ($code -eq 0); Text = $output; Seconds = $timer.Elapsed.TotalSeconds }
}
function Contract([string]$Name, [object[]]$Runs) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $bad = New-Object 'System.Collections.Generic.List[string]'
    foreach ($run in $Runs) {
        $result = Invoke-Check "$Name/$($run.Label)" $run.Exe $run.Args
        if (-not $result.Ok) { $bad.Add($run.Label) }
    }
    $status = if ($bad.Count -eq 0) { "PASS" } else { $script:failed++; "FAIL" }
    $detail = if ($bad.Count) { "; failed: " + ($bad -join ", ") } else { "" }
    $line = "{0} {1}: {2} runs, {3:F1} s{4}" -f $status, $Name, $Runs.Count, $timer.Elapsed.TotalSeconds, $detail
    $script:summary.Add($line)
    Write-Output $line
}
function Get-MenuControlCounts {
    if (-not $script:MenuControlCounts) {
        # Read the validated projection's five counts once, without turning the
        # full 75 MB declaration graph into nested PowerShell objects.
        $code = @'
import json, sys
with open(sys.argv[1], encoding='utf-8-sig') as source:
    clients = json.load(source)['clients']
counts = {}
for name, client in clients.items():
    ids = client['initialControlIds']
    if not isinstance(ids, list) or not ids:
        raise ValueError('Missing initial control IDs for ' + name)
    counts[name] = len(ids)
print(json.dumps(counts))
'@
        $text = & $Python -c $code (Join-Path $root 'tools/menu_schema_coverage.json') 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "Cannot read menu control counts: $text" }
        $script:MenuControlCounts = $text | ConvertFrom-Json
    }
    return $script:MenuControlCounts
}
function Order-ContractRuns([object[]]$Runs) {
    # Lead with long independent jobs, avoiding a late namespace tail after
    # other workers drain. Every run retains its original inventory ID.
    return $Runs | Sort-Object @{ Expression = {
        if ($_.Phase -eq 'setter parity') { 0 }
        elseif ($_.Label -eq 'flip') { 1 }
        else { 2 }
    } }, @{ Expression = { $_.Id } }
}
function LuaRun([string]$Smoke, [string]$Flavor, [string]$Mode = "") {
    $arguments = @("$root/tools/tests/$Smoke", "$root/", $Flavor)
    if ($Mode) { $arguments += $Mode }
    if ($Smoke -eq 'release_menu_smoke.lua') {
        $count = (Get-MenuControlCounts).$Flavor
        if (-not $count) { throw "Missing schema projection for $Flavor" }
        $arguments += [string]$count
    }
    return @{ Label = "$Smoke/$Flavor"; Exe = $Lua; Args = $arguments }
}
$testInventory = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'release-test-inventory.json') -Raw | ConvertFrom-Json
function Get-InventoryRuns([string]$Phase) {
    $runs = @()
    foreach ($entry in @($testInventory.runs | Where-Object { $_.phase -eq $Phase })) {
        $flavors = if ($entry.clients) { @($entry.clients) } else { @('') }
        foreach ($flavor in $flavors) {
            $arguments = @((Join-Path $root $entry.test))
            $tail = if ($null -ne $entry.arguments) { @($entry.arguments) }
                elseif ($flavor) { @('{root}', '{client}') } else { @('{root}') }
            foreach ($value in $tail) {
                $arguments += ([string]$value).Replace('{root}', "$root/").Replace('{client}', $flavor).Replace('{lua}', $Lua).Replace('{luac}', $Luac)
            }
            if ($entry.test -eq 'tools/tests/release_menu_smoke.lua') {
                $count = (Get-MenuControlCounts).$flavor
                if (-not $count) { throw "Missing schema projection for $flavor" }
                $arguments += [string]$count
            }
            $exe = if ($entry.test.EndsWith('.py')) { $Python } else { $Lua }
            $runs += @{ Label = "$($entry.test)/$flavor/$($entry.arguments -join ' ')"; Exe = $exe; Args = $arguments; Client = $flavor }
        }
    }
    return $runs
}
function New-ProfileRuns {
    $runs = @(
        @{ Label = 'sparse-v2'; Exe = $Lua; Args = @('tools/defaults_schema_generate.lua', "$root/", '--check') },
        @{ Label = 'sparse-v3'; Exe = $Lua; Args = @('tools/defaults_schema_generate.lua', "$root/", '--check', '--sparse-v3') }
    )
    return $runs + @(Get-InventoryRuns 'profiles')
}
# A bounded shared queue: at most six Lua processes. Each
# setter replay keeps its single menu world for scalar, reset and compound cases.
function Start-ContractWorker([string]$Name, [object[]]$Runs, [string]$QueuePath = '', [long]$Epoch = 0) {
    $job = Start-Job -ArgumentList $root, $Slot, "$Owner-$Name", $Name, @($Runs), $QueuePath, $Epoch -ScriptBlock {
        param($root, $slot, $owner, $name, $runs, $queue, $epoch)
        . (Join-Path $root 'tools/check-common.ps1')
        $script:PowerShell = (Get-Process -Id $PID).Path
        $receipts = New-Object 'System.Collections.Generic.List[object]'
        $held = $false
        if (-not $epoch) { $epoch = [Diagnostics.Stopwatch]::GetTimestamp() }
        $frequency = [double][Diagnostics.Stopwatch]::Frequency
        try {
            Enter-CheckSlot $slot $owner "MSUF-Compact-Checks-$name"
            $held = $true
            Push-Location $root
            $position, $claim = 0, $null
            if ($queue) { $claim = New-Object Threading.Mutex($false, ('MSUF-Contract-Queue-' + [IO.Path]::GetFileName($queue))) }
            while ($true) {
                if ($claim) {
                    try { [void]$claim.WaitOne() } catch [Threading.AbandonedMutexException] { }
                    try {
                        $index = [int][IO.File]::ReadAllText($queue)
                        if ($index -lt 0 -or $index -gt $runs.Count) { throw 'Invalid contract queue cursor' }
                        if ($index -lt $runs.Count) { [IO.File]::WriteAllText($queue, [string]($index + 1)) }
                    } finally { $claim.ReleaseMutex() }
                } else { $index = $position; $position++ }
                if ($index -ge $runs.Count) { break }
                $run = $runs[$index]
                $started = ([Diagnostics.Stopwatch]::GetTimestamp() - $epoch) / $frequency
                $ErrorActionPreference = 'Continue'
                $LASTEXITCODE = 1
                $executable, $arguments = $run.Exe, $run.Args
                $output = & $executable @arguments 2>&1 | Out-String
                $code = $LASTEXITCODE
                $ok = $code -eq 0
                if ($run.Phase -eq 'setter parity') {
                    $completion = '(?m)^PASS schema setters ' + [regex]::Escape($run.Client) + ':'
                    $writes = '(?m)^PASS compound/temporary write contracts ' + [regex]::Escape($run.Client) + ':'
                    $ok = $ok -and [regex]::Matches($output, $completion).Count -eq 1 -and
                        [regex]::Matches($output, $writes).Count -eq 1
                }
                $receipts.Add([pscustomobject]@{ Id = $run.Id; Phase = $run.Phase; Label = $run.Label;
                    Ok = $ok; Code = $code; Text = $output; Started = $started; Finished = ([Diagnostics.Stopwatch]::GetTimestamp() - $epoch) / $frequency })
            }
        } finally {
            if ($claim) { $claim.Dispose() }
            if ($held) { Pop-Location; Exit-CheckSlot $slot $owner }
        }
        [pscustomobject]@{ Name = $name; Receipts = $receipts.ToArray() }
    }
    return @{ Job = $job; Name = $Name; Runs = $Runs }
}
if ($ProfilesOnly) {
    Push-Location $root
    Enter-CheckSlot $Slot $Owner 'MSUF-Compact-Checks-Profiles'
    try { Contract 'profiles' (New-ProfileRuns) }
    finally { Exit-CheckSlot $Slot $Owner; Pop-Location }
    [IO.File]::AppendAllText($log, ($summary -join $nl) + $nl, $utf8)
    Write-Output "profile-worker-log: $log"
    exit $failed
}

Push-Location $root
try {
    if ($Reproducible) {
        Contract "pinned Blizzard source contracts" @(
            @{ Label = "source-audit"; Exe = $PowerShell; Args = @("-NoProfile", "-File", "tools/audit-classic-ui-source.ps1") }
        )
    }
    Contract "generated lists" @(
        @{ Label = "module-manifest"; Exe = $Python; Args = @("tools/generate_module_manifest.py", "--check") },
        @{ Label = "test-inventory"; Exe = $Python; Args = @("tools/release_test_inventory.py", "--check") },
        @{ Label = "global-keep"; Exe = $Python; Args = @("tools/gen_global_keep.py", "--check") }
    )
    Contract 'generator regressions' @(Get-InventoryRuns 'generated')
    if ($failed) {
        Write-Output "release-check: $failed failed; generated lists are stale or invalid; log $log"
        exit 1
    }
    # Projection preparation may rebuild every workspace on a clean checkout.
    # Report that work separately from the bounded behaviour-contract suite.
    Enter-CheckSlot $Slot $Owner
    $projectionTimer = [Diagnostics.Stopwatch]::StartNew()
    try {
        Contract 'schema projection' @(
            @{ Label = 'current-or-regenerate'; Exe = $Python; Args = @('tools/menu_schema_coverage.py', '--ensure', '--lua', $Lua) }
        )
    } finally {
        $projectionTime = $projectionTimer.Elapsed.TotalSeconds
        Exit-CheckSlot $Slot $Owner
    }
    Contract 'scorecard' @(
        @{ Label = 'current source and projection'; Exe = $Python; Args = @('tools/scorecard.py') }
    )
    # A stale projection or scorecard still fails the final receipt. Continue
    # independent contracts so concurrent product work cannot hide their results.
    $fastArguments = @('-NoProfile', '-File', $FastCheck, '-Owner', $Owner, '-Lua', $Lua, '-Luac', $Luac,
        '-Python', $Python, '-LogDirectory', $LogDirectory)
    if ($Slot) { $fastArguments += @('-Slot', $Slot) }
    $fast = Invoke-Check "fast-check" $PowerShell $fastArguments
    $fastOk = $fast.Ok -and $fast.Text -match "fast-check: 0 failed,"
    if (-not $fastOk) { $failed++ }
    if ($fast.Text -match "fast-check: \d+ failed, ([\d.,]+) s,") {
        $slotTime += [double]::Parse($Matches[1].Replace(",", ""), [Globalization.CultureInfo]::InvariantCulture)
    } else { $slotTime += $fast.Seconds }
    $line = "{0} fast-check: {1:F1} s" -f $(if ($fastOk) { "PASS" } else { "FAIL" }), $fast.Seconds
    $summary.Add($line)
    Write-Output $line
    Enter-CheckSlot $Slot $Owner
    $suiteSlotHeld = $true
    $suiteTime = [Diagnostics.Stopwatch]::StartNew()
    try {
        $phaseNames = @('setter parity', 'profiles', 'runtime robustness', 'menu', 'apply path', 'namespace', 'group preview', 'Edit Mode')
        $phases = @{
            'setter parity' = @(Get-InventoryRuns 'setters')
            'profiles' = @(New-ProfileRuns)
            'runtime robustness' = @(Get-InventoryRuns 'runtime')
            'menu' = @(Get-InventoryRuns 'menu')
            'apply path' = @(Get-InventoryRuns 'apply')
            'namespace' = @(Get-InventoryRuns 'namespace') + @(
                @{ Label = 'flip'; Exe = $Python; Args = @('tools/flip_check.py', $root, '--luac', $luaCompiler, '--lua', $Lua) })
            'group preview' = @(Get-InventoryRuns 'group preview')
            'Edit Mode' = @(Get-InventoryRuns 'edit')
        }
        if ($ParallelContracts) {
            $allRuns = @()
            foreach ($phase in $phaseNames) {
                foreach ($run in $phases[$phase]) {
                    $run.Phase, $run.Id = $phase, $allRuns.Count
                    $allRuns += $run
                }
            }
            # External schedulers own capacity. Release the parent's slot before
            # the workers acquire theirs, including with a capacity-one scheduler.
            if ($Slot) { Exit-CheckSlot $Slot $Owner; $suiteSlotHeld = $false }
            $allRuns = @(Order-ContractRuns $allRuns)
            $contractQueue = "$log.queue"
            [IO.File]::WriteAllText($contractQueue, '0')
            # Five independent setter worlds lead the queue. A free worker can
            # immediately run another client's contracts instead of idling
            # behind that client's setter. The six workers share one cursor.
            $epoch = [Diagnostics.Stopwatch]::GetTimestamp()
            foreach ($number in 1..6) {
                $contractJobs += (Start-ContractWorker "worker-$number" $allRuns $contractQueue $epoch)
            }
            $receipts = @()
            foreach ($worker in $contractJobs) {
                $result = @($worker.Job | Wait-Job | Receive-Job | Where-Object { $_.PSObject.Properties['Receipts'] })
                if ($result.Count -ne 1 -or $result[0].Name -cne $worker.Name) {
                    throw "Incomplete contract worker receipt: $($worker.Name)"
                }
                $receipts += @($result[0].Receipts)
                $worker.Job | Remove-Job -Force
            }
            $contractJobs = @()
            $expectedIds = @($allRuns | ForEach-Object { $_.Id } | Sort-Object)
            $actualIds = @($receipts | ForEach-Object { $_.Id } | Sort-Object)
            if ($receipts.Count -ne $allRuns.Count -or (Compare-Object $expectedIds $actualIds)) {
                throw 'Contract worker inventory changed: missing, duplicate or unknown run ID'
            }
            Remove-Item -LiteralPath $contractQueue -Force
            $contractQueue = $null
            foreach ($phase in $phaseNames) {
                $items = @($receipts | Where-Object { $_.Phase -eq $phase })
                $bad = @($items | Where-Object { -not $_.Ok })
                foreach ($item in $items) {
                    [IO.File]::AppendAllText($log, "=== $phase/$($item.Label) ($($item.Code), $(( $item.Finished - $item.Started ).ToString('F2')) s)$nl$($item.Text)$nl", $utf8)
                }
                $status = if ($bad.Count) { $failed++; 'FAIL' } else { 'PASS' }
                $detail = if ($bad.Count) { '; failed: ' + (($bad | ForEach-Object { $_.Label }) -join ', ') } else { '' }
                $first = ($items | Measure-Object -Property Started -Minimum).Minimum
                $last = ($items | Measure-Object -Property Finished -Maximum).Maximum
                $line = "{0} {1}: {2} runs, {3:F1} s{4}" -f $status, $phase, $items.Count, ($last - $first), $detail
                $summary.Add($line); Write-Output $line
            }
        } else {
            foreach ($phase in $phaseNames) { Contract $phase $phases[$phase] }
        }
    } finally {
        if ($Slot -and $suiteSlotHeld) { Exit-CheckSlot $Slot $Owner; $suiteSlotHeld = $false }
    }
    Contract 'final freshness' @(
        @{ Label = 'unchanged product/projection inputs'; Exe = $Python; Args = @('tools/menu_schema_coverage.py', '--check') }
    )
    if ($suiteSlotHeld) { Exit-CheckSlot $Slot $Owner; $suiteSlotHeld = $false }
    $slotTime += $suiteTime.Elapsed.TotalSeconds
} finally {
    try {
        foreach ($worker in $contractJobs) {
            if ($worker.Job.State -notin @('Completed', 'Failed', 'Stopped')) { $worker.Job | Stop-Job }
            $worker.Job | Remove-Job -Force -ErrorAction SilentlyContinue
        }
        if ($contractQueue) { Remove-Item -LiteralPath $contractQueue -Force -ErrorAction SilentlyContinue }
    } finally {
        try { if ($suiteSlotHeld) { Exit-CheckSlot $Slot $Owner } }
        finally { Pop-Location; $env:PATH = $oldPath }
    }
}
if ($slotTime -ge 300) { $failed++; Write-Output "FAIL time budget: must be under 300 s inside the Lua slot" }
$final = "release-check: {0} failed; {1:F1} s contract slots; {2:F1} s projection preparation; {3:F1} s elapsed; log {4}" -f $failed, $slotTime, $projectionTime, $wall.Elapsed.TotalSeconds, $log
[IO.File]::AppendAllText($log, ($summary -join $nl) + "$nl$final$nl", $utf8)
Write-Output $final
if ($failed) { exit 1 }
exit 0
