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
$profileJob = $null
$setterJobs = @()
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
function LuaRun([string]$Smoke, [string]$Flavor, [string]$Mode = "") {
    $arguments = @("$root/tools/tests/$Smoke", "$root/", $Flavor)
    if ($Mode) { $arguments += $Mode }
    if ($Smoke -eq 'release_menu_smoke.lua') {
        if (-not $script:MenuProjection) {
            $script:MenuProjection = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'menu_schema_coverage.json') -Raw | ConvertFrom-Json
        }
        $ids = $script:MenuProjection.clients.$Flavor.initialControlIds
        if (-not $ids) { throw "Missing schema projection for $Flavor" }
        $arguments += [string]$ids.Count
    }
    return @{ Label = "$Smoke/$Flavor"; Exe = $Lua; Args = $arguments }
}
function New-ProfileRuns {
    $runs = @(
        @{ Label = 'sparse-v2'; Exe = $Lua; Args = @('tools/defaults_schema_generate.lua', "$root/", '--check') },
        @{ Label = 'sparse-v3'; Exe = $Lua; Args = @('tools/defaults_schema_generate.lua', "$root/", '--check', '--sparse-v3') },
        @{ Label = 'size-malformed-rollback-inheritance'; Exe = $Lua; Args = @('tools/tests/profile_sparse_size_smoke.lua', "$root/") }
    )
    foreach ($flavor in @('Mainline', 'Vanilla', 'TBC', 'Mists', 'Forever')) {
        foreach ($smoke in @('release_profiles_smoke.lua', 'profile_decoder_quarantine_smoke.lua',
            'profile_backup_history_smoke.lua', 'profile_alias_corpus_bytes_smoke.lua',
            'profile_ensure_recovery_budget_smoke.lua', 'profile_rollback_compat_smoke.lua',
            'profile_rollback_backup_smoke.lua', 'profile_rollback_guards_smoke.lua', 'profile_newer_revision_backup_smoke.lua')) {
            $runs += (LuaRun $smoke $flavor)
        }
    }
    return $runs
}
function Start-SetterWorker([string]$flavor) {
    $ready = "$log.setters.$flavor.ready"
    $job = Start-Job -ArgumentList $root, $Lua, $Slot, "$Owner-setter-$flavor", $flavor, $ready -ScriptBlock {
        param($root, $lua, $slot, $owner, $flavor, $ready)
        . (Join-Path $root 'tools/check-common.ps1')
        $script:PowerShell = (Get-Process -Id $PID).Path
        $held, $code, $output = $false, 1, ''
        $timer = [Diagnostics.Stopwatch]::StartNew()
        try {
            Enter-CheckSlot $slot $owner "MSUF-Compact-Checks-Setters-$flavor"
            $held = $true
            [IO.File]::WriteAllText($ready, [string]$PID)
            $ErrorActionPreference = 'Continue'
            $LASTEXITCODE = 1
            $output = & $lua "$root/tools/tests/menu_schema_setter_parity.lua" "$root/" $flavor 2>&1 | Out-String
            $code = $LASTEXITCODE
        } catch { $output = "setter worker error: $_" }
        finally { if ($held) { Exit-CheckSlot $slot $owner } }
        [pscustomobject]@{ Flavor = $flavor; Code = $code; Text = $output; Seconds = $timer.Elapsed.TotalSeconds }
    }
    return @{ Job = $job; Flavor = $flavor; Ready = $ready }
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
        @{ Label = "schema-projection-proof"; Exe = $Python; Args = @("tools/tests/menu_schema_coverage_smoke.py") }
    )
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
        $clients = @('Mainline', 'Vanilla', 'TBC', 'Mists', 'Forever')
        $profileRuns = New-ProfileRuns
        $menuRuns = @(
            @{ Label = 'schema-projection-proof'; Exe = $Python; Args = @('tools/tests/menu_schema_coverage_smoke.py') },
            @{ Label = 'shared-widget-declarations'; Exe = $Lua; Args = @('tools/tests/menu_schema_capture_smoke.lua', "$root/") },
            @{ Label = 'schema-setter-contract'; Exe = $Lua; Args = @('tools/tests/menu_schema_setter_contract.lua', "$root/") },
            @{ Label = 'scanner'; Exe = $Lua; Args = @('tools/tests/menu_scanner_lifecycle.lua', "$root/") },
            @{ Label = 'crosshair'; Exe = $Lua; Args = @('tools/tests/menu_crosshair_geometry.lua', "$root/") }
        )
        $runtimeRuns = @()
        # These isolated writer/builder tests take the repository root only.
        foreach ($smoke in @('castbar_pubsub_mutation.lua', 'classpower_playerhp_max_cache.lua',
            'classpower_builder_contracts.lua', 'castbar_empower_reuse.lua', 'modules_enabled_boundary.lua',
            'uf_prediction_writer_recovery.lua', 'uf_late_anchor_writer_recovery.lua')) {
            $runtimeRuns += @{ Label = $smoke; Exe = $Lua; Args = @("$root/tools/tests/$smoke", "$root/") }
        }
        foreach ($flavor in $clients) {
            foreach ($smoke in @('release_menu_smoke.lua', 'menu_changelog_reopen.lua', 'search_entrypoint_slices.lua',
                'menu_schema_reused_declarations_smoke.lua')) {
                $menuRuns += (LuaRun $smoke $flavor)
            }
        }
        # Both index families, across every supported text locale.
        foreach ($flavor in @('Mainline', 'Vanilla')) {
            foreach ($locale in @('enUS', 'enGB', 'deDE', 'esES', 'esMX', 'frFR', 'itIT', 'koKR', 'ptBR', 'ruRU', 'zhCN', 'zhTW')) {
                $menuRuns += @{ Label = "search_static_heap.lua/$flavor/$locale"; Exe = $Lua;
                    Args = @('tools/tests/search_static_heap.lua', "$root/", $flavor, '--check', $locale) }
            }
        }
        $runtimeRuns += (LuaRun 'text_drain_writer_recovery_smoke.lua' 'Mainline')
        $menuRuns += @(
            (LuaRun 'menu_page_rebuild_leak_smoke.lua' 'Mainline'),
            (LuaRun 'menu_page_rebuild_leak_smoke.lua' 'Vanilla'),
            (LuaRun 'search_cold_metadata_smoke.lua' 'Mainline'),
            (LuaRun 'search_cold_metadata_smoke.lua' 'Vanilla'),
            (LuaRun 'guided_tour_restore_retention_smoke.lua' 'Mainline')
        )
        $profileJob = $null
        if ($ParallelContracts) {
            $profileJob = Start-Job -ArgumentList $PowerShell, $PSCommandPath, "$Owner-profiles", $Lua, $Luac, $Python, $Slot, $LogDirectory -ScriptBlock {
                param($ps, $runner, $owner, $lua, $luac, $python, $slot, $logs)
                $workerArgs = @('-NoProfile', '-File', $runner, '-ProfilesOnly', '-Owner', $owner,
                    '-Lua', $lua, '-Luac', $luac, '-Python', $python, '-LogDirectory', $logs)
                if ($slot) { $workerArgs += @('-Slot', $slot) }
                $output = & $ps @workerArgs 2>&1 | Out-String
                [pscustomobject]@{ Code = $LASTEXITCODE; Text = $output }
            }
            $setterTimer = [Diagnostics.Stopwatch]::StartNew()
            foreach ($flavor in $clients) {
                if ($Slot -or $flavor -ne 'TBC') { $setterJobs += (Start-SetterWorker $flavor) }
            }
            # Each client owns its scheduler slot. Release the parent's slot
            # while clients enter, including on a capacity-one scheduler.
            if ($Slot) {
                Exit-CheckSlot $Slot $Owner; $suiteSlotHeld = $false
                do {
                    $waiting = @($setterJobs | Where-Object {
                        -not (Test-Path -LiteralPath $_.Ready) -and $_.Job.State -notin @('Completed', 'Failed', 'Stopped')
                    })
                    if ($waiting.Count) { Start-Sleep -Milliseconds 100 }
                } while ($waiting.Count)
                Enter-CheckSlot $Slot $Owner; $suiteSlotHeld = $true
            }
        } else {
            Contract 'profiles' $profileRuns
            $setterRuns = @($clients | ForEach-Object { LuaRun 'menu_schema_setter_parity.lua' $_ })
            Contract 'setter parity' $setterRuns
        }
        Contract 'runtime robustness' $runtimeRuns
        Contract 'menu' $menuRuns
        if ($ParallelContracts -and -not $Slot) {
            # Four setters, profiles and main occupy at most six Lua lanes.
            # Start the fifth while main is idle, then resume after a worker ends.
            $setterJobs += (Start-SetterWorker 'TBC')
            $activeWorkers = @($setterJobs | ForEach-Object { $_.Job }) + @($profileJob)
            $activeWorkers | Wait-Job -Any | Out-Null
        }
        Contract "apply path" @(
            (LuaRun "release_apply_smoke.lua" "Mainline"),
            (LuaRun "release_apply_smoke.lua" "Vanilla"),
            (LuaRun "release_apply_smoke.lua" "TBC"),
            (LuaRun "release_apply_smoke.lua" "Mists"),
            (LuaRun "release_apply_smoke.lua" "Forever")
        )
        $namespaceRuns = @(
            @{ Label = "mutation-proof"; Exe = $Python; Args = @("tools/tests/flip_check_smoke.py", "--luac", $luaCompiler, "--lua", $Lua) },
            @{ Label = "flip"; Exe = $Python; Args = @("tools/flip_check.py", $root, "--luac", $luaCompiler, "--lua", $Lua) }
        )
        foreach ($flavor in $clients) { $namespaceRuns += (LuaRun 'flip_check_exports.lua' $flavor) }
        Contract 'namespace' $namespaceRuns
        Contract "group preview" @(
            (LuaRun "group_preview_scene_lifecycle_smoke.lua" "Mainline" "release"),
            (LuaRun "group_preview_scene_lifecycle_smoke.lua" "Vanilla" "release"),
            (LuaRun "group_preview_scene_lifecycle_smoke.lua" "Forever" "release"),
            (LuaRun "group_preview_combat_restore_smoke.lua" "Mainline"),
            (LuaRun "group_preview_combat_restore_smoke.lua" "Forever"),
            (LuaRun 'group_preview_configured_glow_smoke.lua' 'Mainline'),
            (LuaRun 'group_preview_configured_glow_smoke.lua' 'Vanilla'),
            (LuaRun 'group_preview_configured_glow_smoke.lua' 'Forever')
        )
        Contract "Edit Mode" @(
            (LuaRun "release_apply_smoke.lua" "Mainline" "edit"),
            (LuaRun "release_apply_smoke.lua" "Vanilla" "edit"),
            (LuaRun "release_apply_smoke.lua" "TBC" "edit"),
            (LuaRun "release_apply_smoke.lua" "Mists" "edit"),
            (LuaRun "release_apply_smoke.lua" "Forever" "edit"),
            (LuaRun "editmode_core_history_smoke.lua" "Mainline"),
            (LuaRun "editmode_core_history_smoke.lua" "Vanilla"),
            (LuaRun "editmode_core_history_smoke.lua" "TBC"),
            (LuaRun "editmode_core_history_smoke.lua" "Mists"),
            (LuaRun "editmode_core_history_smoke.lua" "Forever")
        )
    } finally {
        # External capacity-one schedulers need this release before the join.
        # The default global mutex must still exclude another compact runner.
        if ($Slot) { Exit-CheckSlot $Slot $Owner; $suiteSlotHeld = $false }
    }
    if ($profileJob) {
        try {
            $result = $profileJob | Wait-Job | Receive-Job
            if ($result.Text -match 'profile-worker-log: ([^\r\n]+)') {
                $workerLog = $Matches[1].Trim()
                [IO.File]::AppendAllText($log, [IO.File]::ReadAllText($workerLog), $utf8)
            }
            $line = @($result.Text -split "`r?`n" | Where-Object { $_ -match '^(PASS|FAIL) profiles:' })
            if ($result.Code -ne 0 -or $line.Count -ne 1) { $failed++ }
            if ($line.Count -ne 1) { $line = @('FAIL profiles: worker did not return a complete contract receipt') }
            $summary.Add($line[0]); Write-Output $line[0]
        } catch {
            $failed++
            $line = 'FAIL profiles: worker failed before a complete contract receipt'
            $summary.Add($line); Write-Output $line
            [IO.File]::AppendAllText($log, "profile worker error: $_$nl", $utf8)
        } finally { $profileJob | Remove-Job -Force; $profileJob = $null }
    }
    if ($setterJobs.Count) {
        $badSetters = New-Object 'System.Collections.Generic.List[string]'
        foreach ($worker in $setterJobs) {
            try {
                $result = @($worker.Job | Wait-Job | Receive-Job | Where-Object { $_.PSObject.Properties['Flavor'] })
                if ($result.Count -ne 1) { throw 'worker did not return one complete receipt' }
                $item = $result[0]
                [IO.File]::AppendAllText($log,
                    "=== setter parity/$($item.Flavor) ($($item.Code), $($item.Seconds.ToString('F2')) s)$nl$($item.Text)$nl", $utf8)
                $completion = '(?m)^PASS schema setters ' + [regex]::Escape($worker.Flavor) + ':'
                if ($item.Code -ne 0 -or $item.Flavor -cne $worker.Flavor -or
                    [regex]::Matches($item.Text, $completion).Count -ne 1) { $badSetters.Add($worker.Flavor) }
            } catch {
                $badSetters.Add($worker.Flavor)
                [IO.File]::AppendAllText($log, "setter worker $($worker.Flavor) error: $_$nl", $utf8)
            } finally {
                $worker.Job | Remove-Job -Force
                Remove-Item -LiteralPath $worker.Ready -Force -ErrorAction SilentlyContinue
            }
        }
        $setterJobs = @()
        $status = if ($badSetters.Count) { $failed++; 'FAIL' } else { 'PASS' }
        $detail = if ($badSetters.Count) { '; failed: ' + ($badSetters -join ', ') } else { '' }
        $line = "{0} setter parity: 5 runs, {1:F1} s{2}" -f $status, $setterTimer.Elapsed.TotalSeconds, $detail
        $summary.Add($line); Write-Output $line
    }
    Contract 'final freshness' @(
        @{ Label = 'unchanged product/projection inputs'; Exe = $Python; Args = @('tools/menu_schema_coverage.py', '--check') }
    )
    if ($suiteSlotHeld) { Exit-CheckSlot $Slot $Owner; $suiteSlotHeld = $false }
    $slotTime += $suiteTime.Elapsed.TotalSeconds
} finally {
    try {
        if ($profileJob) {
            try { $profileJob | Wait-Job | Receive-Job | Out-Null }
            catch { [IO.File]::AppendAllText($log, "profile cleanup error: $_$nl", $utf8) }
            finally { $profileJob | Remove-Job -Force -ErrorAction SilentlyContinue }
        }
        foreach ($worker in $setterJobs) {
            try { $worker.Job | Wait-Job | Receive-Job | Out-Null }
            catch { [IO.File]::AppendAllText($log, "setter cleanup $($worker.Flavor) error: $_$nl", $utf8) }
            finally {
                $worker.Job | Remove-Job -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $worker.Ready -Force -ErrorAction SilentlyContinue
            }
        }
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
