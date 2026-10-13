[CmdletBinding()]
param(
    [string]$RetailReferenceRoot = "",
    [switch]$SelfContained,
    [switch]$AllowMissingTools,
    [switch]$ListSmokes,
    [string]$Only = "",
    [switch]$FailFast,
    [int]$Jobs = 0,
    [switch]$RequireNoSkippedSteps,
    [string[]]$SkipTier = @(),
    [string]$Shard = "",
    [string]$TimingsOut = ""
)

# -SkipTier names smoke tiers (the Tier column of tools/classic-gate-smokes.tsv) that this run
# leaves out; it prints one SKIPPED line per tier. The default runs every tier. CI skips the
# slow "nightly" tier on a push and runs it in the nightly workflow.
# -Shard k/n runs only the k-th of n slices of the smoke plan (what is left after -Only and
# -SkipTier), so n CI jobs can share one push-tier run. Shard 1 also runs the static checks; the
# other shards run smokes only. Every shard must be given the same -Only and -SkipTier.
# -TimingsOut <file> writes the seconds each invocation took, the format of
# tools/classic-gate-weights.tsv, which the shard split reads.
$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "../.github/scripts/ClassicGate.Common.psm1") -Force
# -SelfContained is the CI subset: everything except the Blizzard UI source audit, which
# needs the local mirror. It never replaces the full gate.
if (-not [string]::IsNullOrWhiteSpace($RetailReferenceRoot)) {
    # 7.0 is an independent repository: nothing compares against a Retail checkout any more.
    Write-Host "DEPRECATED: -RetailReferenceRoot is ignored; the gate needs no Retail reference."
}
$auraTestDriver = Join-Path $PSScriptRoot "../.github/scripts/auras3_test_driver.lua"
$root = (git rev-parse --show-toplevel).Trim()
$rootFull = [IO.Path]::GetFullPath($root).TrimEnd('\', '/')
Push-Location -LiteralPath $root
$skippedSteps = [Collections.Generic.List[string]]::new()

# PowerShell 5.1 turns a native command's stderr into a NativeCommandError as
# soon as it is merged into the output stream, and $ErrorActionPreference =
# "Stop" makes that terminating, so the curated message after the call could
# never be reached. Every git call whose failure the gate reports itself runs
# through these helpers instead.
function Invoke-GateGit {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $exitCode = 0
    try {
        $output = @(& git @Arguments 2>&1 | ForEach-Object { [string]$_ })
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Lines = [string[]]@($output) }
}

function Invoke-GateNative {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $exitCode = 0
    try {
        $output = @(& $Command @Arguments 2>&1 | ForEach-Object { [string]$_ })
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Lines = [string[]]@($output) }
}

function Assert-TrackedFile {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $tracked = Invoke-GateGit -Arguments @("-C", $root, "ls-files", "--error-unmatch", "--", $RelativePath)
    if ($tracked.ExitCode -ne 0) {
        throw "$Label must be tracked: $RelativePath"
    }
}

# Every smoke the gate starts goes through Invoke-GateSmoke, which records the
# smoke file before running the command. The inventory check near the end
# compares that record with the tracked smokes, so a smoke named only in a
# comment or an unused list never counts as covered.
$smokeFilePattern = '(?:_smoke\.(?:lua|py)|_contract\.lua)$'
$ranSmokes = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$deferredSmokes = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$listedSmokeCount = 0
$gateSmokeFailures = [Collections.Generic.List[object]]::new()
$gateSmokeTimings = [Collections.Generic.List[object]]::new()
$gateSmokeScript = {
    param([string]$Command, [string[]]$SmokeArguments, [string]$WorkingDirectory)
    Set-Location -LiteralPath $WorkingDirectory
    $ErrorActionPreference = "Continue"
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $output = @(& $Command @SmokeArguments 2>&1 | ForEach-Object { [string]$_ })
    $exitCode = $LASTEXITCODE
    $stopwatch.Stop()
    return [pscustomobject]@{ ExitCode = $exitCode; Output = [string[]]@($output); Seconds = $stopwatch.Elapsed.TotalSeconds }
}
function Invoke-GateSmoke {
    <#
        Records every smoke file a planned invocation names, then runs the plan.
        Recording and running live in the same function so nothing can start a
        smoke the inventory check has not seen. -Defer records the plan as
        deferred to a skipped tier and runs nothing; the inventory check counts
        a smoke that only a skipped tier covers as accounted for, never as unrun.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Plan,
        [switch]$Defer
    )

    # Assigned in two steps: an if-expression would unroll the set into its items.
    $recorded = $ranSmokes
    if ($Defer) { $recorded = $deferredSmokes }
    foreach ($item in $Plan) {
        foreach ($argument in $item.Arguments) {
            $text = [string]$argument
            if ($text -notmatch $smokeFilePattern) { continue }
            $full = if ([IO.Path]::IsPathRooted($text)) { [IO.Path]::GetFullPath($text) } else { [IO.Path]::GetFullPath((Join-Path $rootFull $text)) }
            if (-not $full.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Gate smoke lies outside the repository: $text"
            }
            [void]$recorded.Add($full.Substring($rootFull.Length + 1).Replace([char]92, [char]47))
        }
    }
    if ($Plan.Count -eq 0 -or $Defer) { return }

    # -ListSmokes prints every invocation the gate would make, fully expanded,
    # instead of running it: the listing and the run read the same plan.
    if ($ListSmokes) {
        foreach ($item in $Plan) {
            $script:listedSmokeCount++
            $parts = @([string]$item.Command) + @($item.Arguments | ForEach-Object { [string]$_ })
            [Console]::Out.WriteLine(("LISTSMOKE {0:D3} | {1} :: {2}" -f $script:listedSmokeCount, ($parts -join " | "), $item.Label))
        }
        return
    }

    $results = New-Object 'object[]' $Plan.Count
    if ($gateSmokeJobs -le 1) {
        for ($index = 0; $index -lt $Plan.Count; $index++) {
            $results[$index] = & $gateSmokeScript $Plan[$index].Command $Plan[$index].Arguments $root
            if ($FailFast -and $results[$index].ExitCode -ne 0) {
                foreach ($line in $results[$index].Output) { Write-Host $line }
                throw $Plan[$index].Label
            }
        }
    } else {
        # PowerShell 5.1 has no ForEach-Object -Parallel; a runspace pool is the
        # in-process equivalent. Smokes only read the working tree, so they are
        # safe to overlap. Results are collected by plan index, so the printed
        # output and the failure order stay the order of the manifest.
        $pool = [runspacefactory]::CreateRunspacePool(1, $gateSmokeJobs)
        $pool.Open()
        $handles = New-Object 'object[]' $Plan.Count
        try {
            for ($index = 0; $index -lt $Plan.Count; $index++) {
                $shell = [powershell]::Create()
                $shell.RunspacePool = $pool
                [void]$shell.AddScript($gateSmokeScript).AddArgument($Plan[$index].Command).AddArgument($Plan[$index].Arguments).AddArgument($root)
                $handles[$index] = [pscustomobject]@{ Shell = $shell; Async = $shell.BeginInvoke() }
            }
            for ($index = 0; $index -lt $Plan.Count; $index++) {
                $results[$index] = @($handles[$index].Shell.EndInvoke($handles[$index].Async))[0]
            }
        } finally {
            foreach ($handle in $handles) { if ($handle) { $handle.Shell.Dispose() } }
            $pool.Close()
            $pool.Dispose()
        }
    }

    for ($index = 0; $index -lt $Plan.Count; $index++) {
        $item = $Plan[$index]
        $result = $results[$index]
        foreach ($line in $result.Output) { Write-Host $line }
        $gateSmokeTimings.Add([pscustomobject]@{ Name = $item.Name; Seconds = $result.Seconds })
        if ($result.ExitCode -ne 0) {
            if ($FailFast) { throw $item.Label }
            $gateSmokeFailures.Add([pscustomobject]@{
                Label = $item.Label
                Command = "$($item.Command) $($item.Arguments -join ' ')"
                ExitCode = $result.ExitCode
                Output = $result.Output
            })
        }
    }
}

# tools/classic-client-matrix.tsv is the single list of supported clients.
# Every client loop, interface check and summary count below reads it.
$clientMatrixRelative = "tools/classic-client-matrix.tsv"
$clientMatrixPath = Join-Path $root $clientMatrixRelative
$clientMatrix = @(Import-MsufClientMatrix -Path $clientMatrixPath -Label $clientMatrixRelative `
    -EmptyMessage "Client matrix has no clients: $clientMatrixRelative")
Assert-MsufClientMatrix -Matrix $clientMatrix -Label "Client matrix"
$clientSuffixes = @($clientMatrix | ForEach-Object { $_.Suffix })
$classicSuffixes = @($clientMatrix | Where-Object { $_.IsClassic -ceq "true" } | ForEach-Object { $_.Suffix })

# Tool preflight runs before any expensive step. A missing tool fails the gate
# unless -AllowMissingTools is passed; every step that is then skipped is
# reported as a SKIPPED line at the end, so a partial run never reads as a pass.
$luac = Get-Command luac -ErrorAction SilentlyContinue
if ($luac) {
    $luacVersion = (& $luac.Source -v | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $luacVersion -notmatch '^Lua 5\.1(?:\.\d+)?\s') {
        throw "luac must be Lua 5.1: $($luac.Source) reports '$luacVersion'"
    }
} elseif ($AllowMissingTools) {
    $skippedSteps.Add("Lua 5.1 syntax check (luac not found)")
} else {
    throw "luac (Lua 5.1) is required on PATH for the Lua 5.1 syntax check; pass -AllowMissingTools only for a structure-only run"
}
$lua = Get-Command lua -ErrorAction SilentlyContinue
if ($lua) {
    $luaVersion = (& $lua.Source -e "io.write(_VERSION)" | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $luaVersion -cne "Lua 5.1") {
        throw "lua must be Lua 5.1: $($lua.Source) reports '$luaVersion'"
    }
} elseif ($AllowMissingTools) {
    $skippedSteps.Add("Lua behavioural smokes (lua not found)")
} else {
    throw "lua (Lua 5.1) is required on PATH for the behavioural smokes; pass -AllowMissingTools only for a structure-only run"
}
$uiMirror = Join-Path $root "_local_workflows/references/wow-ui-source/.git"
$uiMirrorPresent = Test-Path -LiteralPath $uiMirror -PathType Container
if ($SelfContained) {
    # The mirror is a local reference checkout; a self-contained run never needs it.
    $skippedSteps.Add("Blizzard UI source audit (self-contained run)")
} elseif (-not $uiMirrorPresent) {
    # Without the local mirror (a plain CI runner) the audit cannot run.
    if ($AllowMissingTools -or $env:GITHUB_ACTIONS -eq "true") {
        $skippedSteps.Add("Blizzard UI source audit (no mirror at _local_workflows/references/wow-ui-source)")
    } else {
        throw "Blizzard UI source mirror is missing at _local_workflows/references/wow-ui-source; pass -AllowMissingTools only for a run that may skip the source audit"
    }
}

# tools/classic-gate-smokes.tsv is the smoke list: one row per smoke, expanded
# over the client matrix by the Matrix column. Consecutive rows that name the
# same matrix run as one loop, which is how two smokes stay interleaved per
# flavor. Tokens: {root} the repository root as git prints it, {root/} the same
# with forward slashes, {flavor} and {clientToken} the matrix row, {codec} the
# codec axis, {p/:<repo path>} an absolute forward-slash path.
$smokeManifestRelative = "tools/classic-gate-smokes.tsv"
$smokeManifestPath = Join-Path $root $smokeManifestRelative
if (-not (Test-Path -LiteralPath $smokeManifestPath -PathType Leaf)) {
    throw "Classic gate smoke manifest is missing: $smokeManifestRelative"
}
Assert-TrackedFile -RelativePath $smokeManifestRelative -Label "Classic gate smoke manifest"
$smokeRows = @(Import-Csv -LiteralPath $smokeManifestPath -Delimiter "`t")
if ($smokeRows.Count -eq 0) { throw "Classic gate smoke manifest is empty: $smokeManifestRelative" }
$smokeManifestColumns = @("Matrix", "Runner", "Smoke", "Arguments", "Label", "Tier")
$actualSmokeColumns = @($smokeRows[0].PSObject.Properties | ForEach-Object { $_.Name })
if (($actualSmokeColumns -join "`t") -cne ($smokeManifestColumns -join "`t")) {
    throw "Classic gate smoke manifest columns must be exactly: $($smokeManifestColumns -join ', ')"
}
# Tier is the last column and a row may leave it out: a smoke without one is in the push tier, which
# every push and pull request runs. The nightly tier holds the slowest smokes; -SkipTier leaves a
# tier out of a run and the local default runs them all.
$smokeTiers = @("push", "nightly")
foreach ($tierName in $SkipTier) {
    if ($smokeTiers -cnotcontains $tierName) {
        throw "-SkipTier names an unknown smoke tier '$tierName'; the tiers are: $($smokeTiers -join ', ')"
    }
}
$shardIndex = 0
$shardCount = 0
if (-not [string]::IsNullOrWhiteSpace($Shard)) {
    if ($Shard -cnotmatch '^(?<index>[1-9][0-9]*)/(?<count>[1-9][0-9]*)$' -or [int]$Matches["index"] -gt [int]$Matches["count"]) {
        throw "-Shard must read <k>/<n> with 1 <= k <= n, for example 2/6; got '$Shard'"
    }
    $shardIndex = [int]$Matches["index"]
    $shardCount = [int]$Matches["count"]
}
$smokeCodecModes = @("raise", "nil")
$gateSmokeJobs = if ($Jobs -gt 0) { $Jobs } else { [Math]::Max(1, [Math]::Min(8, [Environment]::ProcessorCount)) }

function Resolve-GateSmokeMatrix {
    param([Parameter(Mandatory = $true)][string]$Name)
    if ($Name -ceq "-") { return @(@{}) }
    if ($Name -ceq "tokenclients") {
        # Every X-MSUF-Client token in the matrix must place its flavor on its own.
        return @($clientMatrix | Where-Object { $_.ClientToken -cne "" } |
            ForEach-Object { @{ flavor = $_.Suffix; clientToken = $_.ClientToken } })
    }
    if ($Name -cnotmatch '^(?<base>clients|classics)(?:\+(?<extra>[A-Za-z0-9,]+))?(?<codecs>\*codecs)?$') {
        throw "Classic gate smoke manifest names an unknown matrix: $Name"
    }
    $flavors = @($classicSuffixes)
    if ($Matches["base"] -ceq "clients") { $flavors = @($clientSuffixes) }
    if ($Matches.ContainsKey("extra")) { $flavors = @($flavors) + @($Matches["extra"].Split(',')) }
    $withCodecs = $Matches.ContainsKey("codecs")
    $contexts = [Collections.Generic.List[hashtable]]::new()
    foreach ($flavor in $flavors) {
        if ($withCodecs) {
            foreach ($codec in $smokeCodecModes) { $contexts.Add(@{ flavor = $flavor; codec = $codec }) }
        } else {
            $contexts.Add(@{ flavor = $flavor })
        }
    }
    return $contexts.ToArray()
}

function Expand-GateSmokeToken {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][hashtable]$Context
    )
    $expanded = $Text.Replace("{root/}", ($root -replace '\\', '/')).Replace("{root}", $root)
    foreach ($key in @($Context.Keys)) { $expanded = $expanded.Replace("{$key}", [string]$Context[$key]) }
    $expanded = [regex]::Replace($expanded, '\{p/:([^}]+)\}', { param($match) (Join-Path $root $match.Groups[1].Value) -replace '\\', '/' })
    if ($expanded -match '\{[A-Za-z][^}]*\}') {
        throw "Classic gate smoke manifest leaves a token unresolved: $Text"
    }
    return $expanded
}

function New-GateSmokeItem {
    param(
        [Parameter(Mandatory = $true)][object]$Row,
        [Parameter(Mandatory = $true)][hashtable]$Context
    )
    if ([string]::IsNullOrWhiteSpace($Row.Smoke) -or $Row.Smoke -cne $Row.Smoke.Trim() -or $Row.Smoke.Contains([char]92)) {
        throw "Classic gate smoke manifest needs a trimmed forward-slash smoke path: '$($Row.Smoke)'"
    }
    if ($Row.Smoke -notmatch $smokeFilePattern) {
        throw "Classic gate smoke manifest names a file that is not a smoke: $($Row.Smoke)"
    }
    if ([string]::IsNullOrWhiteSpace($Row.Label) -or $Row.Label -cne $Row.Label.Trim()) {
        throw "Classic gate smoke manifest needs a trimmed failure label: $($Row.Smoke)"
    }
    $leading = @()
    switch -CaseSensitive ($Row.Runner) {
        "python" { $command = "python" }
        "lua" { $command = if ($lua) { $lua.Source } else { "" } }
        "lua+driver" {
            $command = if ($lua) { $lua.Source } else { "" }
            $leading = @($auraTestDriver)
        }
        default { throw "Classic gate smoke manifest names an unknown runner '$($Row.Runner)': $($Row.Smoke)" }
    }
    $tier = if ([string]::IsNullOrEmpty($Row.Tier)) { "push" } else { [string]$Row.Tier }
    if ($smokeTiers -cnotcontains $tier) {
        throw "Classic gate smoke manifest names an unknown tier '$tier' ($($smokeTiers -join ', ')): $($Row.Smoke)"
    }
    $arguments = @($leading) + @([string](Join-Path $root $Row.Smoke))
    foreach ($token in @(($Row.Arguments -split '\s+') | Where-Object { $_ })) {
        $arguments += (Expand-GateSmokeToken -Text $token -Context $Context)
    }
    # The name is what the timing report shows: the smoke plus the arguments
    # that tell its matrix variants apart, with the repository paths left out.
    $variant = @($arguments | Select-Object -Skip ($leading.Count + 1) |
        Where-Object { $_ -notmatch '[\\/]' })
    return [pscustomobject]@{
        Runner = $Row.Runner
        Smoke = $Row.Smoke
        Tier = $tier
        Name = (@($Row.Smoke) + $variant) -join ' '
        Command = $command
        Arguments = [string[]]@($arguments)
        Label = (Expand-GateSmokeToken -Text $Row.Label -Context $Context)
    }
}

$smokePlan = [Collections.Generic.List[object]]::new()
$smokeRowIndex = 0
while ($smokeRowIndex -lt $smokeRows.Count) {
    $matrixName = $smokeRows[$smokeRowIndex].Matrix
    $matrixGroup = [Collections.Generic.List[object]]::new()
    while ($smokeRowIndex -lt $smokeRows.Count -and $smokeRows[$smokeRowIndex].Matrix -ceq $matrixName) {
        $matrixGroup.Add($smokeRows[$smokeRowIndex])
        $smokeRowIndex++
        if ($matrixName -ceq "-") { break }
    }
    foreach ($smokeContext in (Resolve-GateSmokeMatrix -Name $matrixName)) {
        foreach ($smokeRow in $matrixGroup) {
            $smokePlan.Add((New-GateSmokeItem -Row $smokeRow -Context $smokeContext))
        }
    }
}
$smokePlanTotal = $smokePlan.Count
if (-not [string]::IsNullOrWhiteSpace($Only)) {
    # A narrowed run must never read as a pass, so the inventory check below is
    # recorded as skipped instead of silently accepting the smokes that sat out.
    $smokePlan = [Collections.Generic.List[object]]@($smokePlan | Where-Object { $_.Smoke -match $Only -or $_.Label -match $Only })
    if ($smokePlan.Count -eq 0) { throw "-Only '$Only' matches none of the $smokePlanTotal smoke invocations" }
    $skippedSteps.Add("Smoke inventory and $($smokePlanTotal - $smokePlan.Count) smoke invocations (-Only '$Only')")
}
# A skipped tier is one SKIPPED line naming the tier and how many invocations it holds, so a push
# run never reads as the full gate. Its smokes stay in the inventory as deferred, not as unrun.
foreach ($tierName in @($SkipTier | Select-Object -Unique)) {
    $deferredPlan = @($smokePlan | Where-Object { $_.Tier -ceq $tierName })
    Invoke-GateSmoke -Plan $deferredPlan -Defer
    $skippedSteps.Add("Smoke tier '$tierName' ($($deferredPlan.Count) smoke invocations, -SkipTier $tierName)")
    $smokePlan = [Collections.Generic.List[object]]@($smokePlan | Where-Object { $_.Tier -cne $tierName })
}
if ($smokePlan.Count -eq 0) { throw "-SkipTier leaves none of the $smokePlanTotal smoke invocations to run" }

# -Shard k/n splits what is left of the plan into n slices of about equal weight, longest first:
# each invocation goes to the shard with the least weight so far. The weight is the seconds the
# invocation took in an earlier run (tools/classic-gate-weights.tsv, written by -TimingsOut); one
# the table does not know weighs the median known one. Ties break by plan order, so every shard
# computes the same split from the same commit. Shard 1 also runs the static checks, so it starts
# with a share of the plan's weight (about 50 s of a two-core runner against the push tier's
# smoke time, 4%) and gets that much less smoke work.
$shardFirstShare = 0.04
function Get-GateSmokeShardAssignment {
    param(
        [Parameter(Mandatory = $true)][object[]]$Plan,
        [Parameter(Mandatory = $true)][int]$Count,
        [Parameter(Mandatory = $true)][string]$WeightsPath
    )
    $invariant = [Globalization.CultureInfo]::InvariantCulture
    $known = @{}
    foreach ($row in @(Import-Csv -LiteralPath $WeightsPath -Delimiter "`t")) {
        $seconds = 0.0
        if ([double]::TryParse([string]$row.Seconds, [Globalization.NumberStyles]::Float, $invariant, [ref]$seconds) -and $seconds -gt 0) {
            $known[[string]$row.Name] = $seconds
        }
    }
    if ($known.Count -eq 0) { throw "Classic gate shard weights hold no timing: $WeightsPath" }
    $sorted = [double[]]@($known.Values)
    [Array]::Sort($sorted)
    $median = $sorted[[int][Math]::Floor(($sorted.Count - 1) / 2)]
    $weight = New-Object 'double[]' $Plan.Count
    $total = 0.0
    for ($index = 0; $index -lt $Plan.Count; $index++) {
        $weight[$index] = $median
        if ($known.ContainsKey($Plan[$index].Name)) { $weight[$index] = $known[$Plan[$index].Name] }
        $total += $weight[$index]
    }
    $load = New-Object 'double[]' $Count
    $load[0] = $shardFirstShare * $total
    $order = @(0..($Plan.Count - 1) | Sort-Object -Property @{ Expression = { -$weight[$_] } }, @{ Expression = { $_ } })
    $shardOf = New-Object 'int[]' $Plan.Count
    foreach ($index in $order) {
        $lightest = 0
        for ($candidate = 1; $candidate -lt $Count; $candidate++) {
            if ($load[$candidate] -lt $load[$lightest]) { $lightest = $candidate }
        }
        $shardOf[$index] = $lightest
        $load[$lightest] += $weight[$index]
    }
    return [pscustomobject]@{ ShardOf = $shardOf; Weight = $weight; Total = $total }
}

if ($shardCount -gt 1) {
    $weightsRelative = "tools/classic-gate-weights.tsv"
    Assert-TrackedFile -RelativePath $weightsRelative -Label "Classic gate shard weights"
    $split = Get-GateSmokeShardAssignment -Plan @($smokePlan) -Count $shardCount -WeightsPath (Join-Path $root $weightsRelative)
    $ownPlan = [Collections.Generic.List[object]]::new()
    $otherPlan = [Collections.Generic.List[object]]::new()
    $ownWeight = 0.0
    for ($planIndex = 0; $planIndex -lt $smokePlan.Count; $planIndex++) {
        if ($split.ShardOf[$planIndex] -eq $shardIndex - 1) {
            $ownPlan.Add($smokePlan[$planIndex])
            $ownWeight += $split.Weight[$planIndex]
        } else {
            $otherPlan.Add($smokePlan[$planIndex])
        }
    }
    if ($ownPlan.Count -eq 0) { throw "Smoke shard $Shard holds none of the $($smokePlan.Count) smoke invocations; use fewer shards" }
    # The other shards' smokes stay in the inventory as deferred, not as unrun.
    Invoke-GateSmoke -Plan @($otherPlan) -Defer
    $shardShare = [Math]::Round(100 * $ownWeight / $split.Total)
    $shardNote = "shards 2-$shardCount run the rest"
    if ($shardIndex -gt 1) { $shardNote = "the static checks run in shard 1/$shardCount" }
    $skippedSteps.Add("Smoke shard $Shard ($($ownPlan.Count) of $($smokePlan.Count) smoke invocations, $shardShare% of their weight; $shardNote)")
    if ($ListSmokes) { Write-Host "LISTSHARD $Shard | $($ownPlan.Count) invocations | $shardShare% of the weight" }
    $smokePlan = $ownPlan
}

# -ListSmokes prints the plan and stops: the static checks below add nothing to a listing.
if ($ListSmokes) {
    Invoke-GateSmoke -Plan @($smokePlan)
    Pop-Location
    return
}

# The smoke phase, the inventory and the closing report are functions so a shard that only runs
# smokes (shard 2 and up) can run them without the static checks between here and the original
# call sites.
function Invoke-GateSmokePhase {
    if (-not $lua) { return }
    # tools/classic-gate-smokes.tsv is the list; the plan above expanded it
    # over the client matrix. Its python rows run here too (see the error-path
    # check below). Invoke-GateSmoke records every smoke file it is about to
    # start, so the inventory check still sees each one.
    $luaSmokeStopwatch = [Diagnostics.Stopwatch]::StartNew()
    Invoke-GateSmoke -Plan @($smokePlan)
    $luaSmokeStopwatch.Stop()
    $invariant = [Globalization.CultureInfo]::InvariantCulture
    $smokeSeconds = ($gateSmokeTimings | Measure-Object -Property Seconds -Sum).Sum
    Write-Host ("Classic gate smokes: $($gateSmokeTimings.Count) invocations in " +
        $luaSmokeStopwatch.Elapsed.TotalSeconds.ToString("0.0", $invariant) +
        " s wall clock on $gateSmokeJobs worker(s), " + ([double]$smokeSeconds).ToString("0", $invariant) +
        " s of smoke time in all; slowest:")
    foreach ($slowSmoke in @($gateSmokeTimings | Sort-Object -Property Seconds -Descending | Select-Object -First 10)) {
        Write-Host ("    " + $slowSmoke.Seconds.ToString("0.00", $invariant).PadLeft(6) + " s  " + $slowSmoke.Name)
    }
    if (-not [string]::IsNullOrWhiteSpace($TimingsOut)) {
        $slowestOf = @{}
        foreach ($timing in $gateSmokeTimings) {
            if (-not $slowestOf.ContainsKey($timing.Name) -or $timing.Seconds -gt $slowestOf[$timing.Name]) {
                $slowestOf[$timing.Name] = $timing.Seconds
            }
        }
        $timingNames = [string[]]@($slowestOf.Keys)
        [Array]::Sort($timingNames, [StringComparer]::Ordinal)
        $timingLines = @("Name`tSeconds") + @($timingNames | ForEach-Object { "$_`t" + ([double]$slowestOf[$_]).ToString("0.00", $invariant) })
        $timingsPath = if ([IO.Path]::IsPathRooted($TimingsOut)) { $TimingsOut } else { Join-Path $root $TimingsOut }
        [IO.File]::WriteAllText($timingsPath, (($timingLines -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))
    }
}

# Every tracked smoke either ran through Invoke-GateSmoke above or is retired
# with a recorded reason, so no smoke silently rots.
function Assert-GateSmokeInventory {
    $retiredSmokes = [ordered]@{
        ".github/scripts/mapkoskin_menu_integration_contract.lua" = "runs only under the external tests/MapkoSkin/run.lua harness, which this repository does not contain"
        ".github/scripts/prediction_data_writer_parity_smoke.lua" = "compares against an immutable pre-refactor source root in arg[2]; a self-comparison fails by design"
    }
    $trackedSmokes = [Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    $trackedToolingResult = Invoke-GateGit -Arguments @("-C", $root, "ls-files", "--", "tools", ".github")
    if ($trackedToolingResult.ExitCode -ne 0) { throw "Unable to enumerate tracked smokes: $($trackedToolingResult.Lines -join ', ')" }
    $trackedToolingPaths = $trackedToolingResult.Lines
    foreach ($trackedToolingPath in $trackedToolingPaths) {
        $trackedToolingPath = $trackedToolingPath.Replace([char]92, [char]47)
        if ($trackedToolingPath -match $smokeFilePattern) { [void]$trackedSmokes.Add($trackedToolingPath) }
    }
    foreach ($retiredSmoke in $retiredSmokes.Keys) {
        if (-not $trackedSmokes.Contains($retiredSmoke)) {
            throw "Retired smoke entry names no tracked smoke: $retiredSmoke"
        }
        if ($ranSmokes.Contains($retiredSmoke) -or $deferredSmokes.Contains($retiredSmoke)) {
            throw "Retired smoke still runs in the Classic gate: $retiredSmoke"
        }
    }
    foreach ($ranSmoke in @($ranSmokes) + @($deferredSmokes)) {
        if (-not $trackedSmokes.Contains($ranSmoke)) {
            throw "The Classic gate ran an untracked smoke; track it with git add -f: $ranSmoke"
        }
    }
    # Without lua no Lua smoke ran; the preflight already recorded that skip. With
    # -Only the run deliberately holds smokes back and records that as a skipped
    # step, so the completeness half of the inventory cannot apply.
    if ($lua -and [string]::IsNullOrWhiteSpace($Only)) {
        # A smoke only a skipped tier or another shard covers is deferred: a SKIPPED line names it.
        $unrunSmokes = [string[]]@($trackedSmokes | Where-Object {
            -not $ranSmokes.Contains($_) -and -not $deferredSmokes.Contains($_) -and -not $retiredSmokes.Contains($_) })
        if ($unrunSmokes.Count -gt 0) {
            throw "Tracked smokes neither ran in the Classic gate nor are listed as retired: $($unrunSmokes -join ', ')"
        }
    }
    $deferredOnlyCount = @($deferredSmokes | Where-Object { -not $ranSmokes.Contains($_) }).Count
    $deferredNote = if ($deferredOnlyCount -gt 0) { "; $deferredOnlyCount deferred to a skipped tier or shard" } else { "" }
    Write-Host "Smoke inventory: $($trackedSmokes.Count) tracked smokes; $($ranSmokes.Count) ran$deferredNote; $($retiredSmokes.Count) retired with a recorded reason"
}

function Complete-GateRun {
    foreach ($skippedStep in $skippedSteps) {
        Write-Host "SKIPPED: $skippedStep"
    }
    # The smoke phase collects instead of aborting, so one run names every broken
    # smoke. Structural checks above still stop at the first failure, because each
    # one assumes what the previous ones proved. -FailFast restores the old abort.
    if ($gateSmokeFailures.Count -gt 0) {
        Write-Host "Failed smokes: $($gateSmokeFailures.Count) of $($smokePlan.Count) invocations"
        foreach ($failure in $gateSmokeFailures) {
            Write-Host "FAILED: $($failure.Label) (exit $($failure.ExitCode))"
            Write-Host "    $($failure.Command)"
            foreach ($line in $failure.Output) { Write-Host "    | $line" }
        }
        Pop-Location
        throw "Classic gate smokes failed: $($gateSmokeFailures.Count) of $($smokePlan.Count) invocations"
    }
    # A full run in CI has nothing to skip: the job clones the Blizzard mirror.
    # -RequireNoSkippedSteps makes that explicit, so a clone that lands in the wrong
    # place cannot leave a green gate that quietly dropped the source audit. It runs
    # after the smoke report so a broken smoke is still named first.
    if ($RequireNoSkippedSteps -and $skippedSteps.Count -gt 0) {
        Pop-Location
        throw "The Classic gate skipped $($skippedSteps.Count) step(s) while -RequireNoSkippedSteps was set: $($skippedSteps -join '; ')"
    }
    Pop-Location
}

if ($shardIndex -gt 1) {
    if (-not $lua) { throw "Smoke shard $Shard needs lua to run its smokes" }
    Invoke-GateSmokePhase
    Assert-GateSmokeInventory
    Complete-GateRun
    return
}

# Python smokes need no Lua. With lua present they run in the smoke phase
# below, in one pool with the Lua smokes, so the slow git-driven ones overlap
# with it instead of adding a wait of their own. Without lua that phase never
# runs, so they run here.
if (-not $lua) {
    Invoke-GateSmoke -Plan @($smokePlan | Where-Object { $_.Runner -ceq "python" })
}
& python (Join-Path $root ".github/quality/error_paths.py")
if ($LASTEXITCODE -ne 0) { throw "Classic error visibility contract failed" }

$targets = @(
    @{ Folder = "MidnightSimpleUnitFrames"; Base = "MidnightSimpleUnitFrames" },
    @{ Folder = "MidnightSimpleUnitFrames_Options"; Base = "MidnightSimpleUnitFrames_Options" }
)
# tools/classic-addon-tombstones.txt names the addons this tree retired and the
# files of the shipped addons that retired with them. The manifest is proven
# against git and the load graph once every TOC has been walked.
$addonTombstoneRelative = "tools/classic-addon-tombstones.txt"
Assert-TrackedFile -RelativePath $addonTombstoneRelative -Label "Classic addon tombstone manifest"
$addonTombstones = Import-MsufAddonTombstones -Path (Join-Path $root $addonTombstoneRelative) `
    -ShippedAddons ([string[]]@($targets | ForEach-Object { $_.Folder }))
# Scans read the files git versions, never a folder walk, so ignored local
# files (luac.out, local scripts) cannot make a local run differ from CI.
$versionableAddonLua = [string[]]@(Get-MsufVersionableFiles -Root $root `
    -Folders ([string[]]@($targets | ForEach-Object { $_.Folder })) -Extension @(".lua"))
$clients = $clientMatrix
$expectedVersion = (Get-Content -LiteralPath (Join-Path $root "VERSION") -Raw).Trim()
& (Join-Path $root ".github/scripts/assert-classic-release-line.ps1") `
    -RepositoryRoot $root -ReleaseVersion $expectedVersion
# The release line proves the two changelog payloads' version and source hash;
# the tracked generator's check mode proves their whole content, so a hand
# edit or a stale regeneration fails here instead of at release time.
Assert-TrackedFile -RelativePath "tools/update-addon-changelog.ps1" -Label "Changelog payload generator"
$changelogVersion = & (Join-Path $root ".github/scripts/resolve-classic-changelog-version.ps1") `
    -RepositoryRoot $root -ReleaseVersion $expectedVersion
& (Join-Path $root "tools/update-addon-changelog.ps1") -Version $changelogVersion -Check

# Writing addon-owned fallbacks into Blizzard's C_* namespace taints the table
# and can surface later as ADDON_ACTION_FORBIDDEN at UseAction(). Compatibility
# adapters must stay below MSUF.Compat instead.
$taintWritePattern = '(?m)^\s*(?:_G\.)?C_[A-Za-z0-9_]+\.[A-Za-z0-9_]+\s*=(?!=)'
foreach ($luaRelative in $versionableAddonLua) {
    $source = [IO.File]::ReadAllText((Join-Path $root $luaRelative))
    if ($source -match $taintWritePattern) {
        throw "Blizzard C_* namespace mutation is forbidden: $luaRelative"
    }
}

# One walker, in .github/scripts/ClassicGate.Common.psm1, resolves every TOC and
# XML load graph in this gate. $seenXml is shared across TOCs so a manifest that
# several clients include is parsed once and counted once.
$seenXml = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

# tools/classic-toc-identity.tsv pins the TOC metadata lines that carry profile and release identity
# or that code reads back at runtime. The comparison between the clients below only proves they
# agree; the pin proves a field cannot disappear from every client at once.
$tocIdentityRelative = "tools/classic-toc-identity.tsv"
Assert-TrackedFile -RelativePath $tocIdentityRelative -Label "TOC identity manifest"
$tocIdentityRows = Import-MsufTocIdentity -Path (Join-Path $root $tocIdentityRelative) `
    -Addons ([string[]]@($targets | ForEach-Object { $_.Base }))

foreach ($target in $targets) {
    $folder = Join-Path $root $target.Folder
    $unsuffixed = Join-Path $folder ($target.Base + ".toc")
    if (Test-Path -LiteralPath $unsuffixed) {
        throw "Unsuffixed TOC should not coexist with client TOCs: $unsuffixed"
    }

    $versions = @{}
    $referenceMetadata = $null
    $referenceMetadataToc = $null
    foreach ($client in $clients) {
        $tocName = "{0}_{1}.toc" -f $target.Base, $client.Suffix
        $tocPath = Join-Path $folder $tocName
        if (-not (Test-Path -LiteralPath $tocPath -PathType Leaf)) {
            throw "Missing TOC: $tocPath"
        }

        $content = Get-Content -LiteralPath $tocPath
        $interfaceLine = $content | Where-Object { $_ -match '^## Interface:' } | Select-Object -First 1
        $actualInterface = ($interfaceLine -replace '^## Interface:\s*', '').Trim()
        $actualInterfaceSet = ConvertTo-MsufInterfaceSet -Value $actualInterface -Label $tocName
        $expectedInterfaceSet = ConvertTo-MsufInterfaceSet -Value $client.Interfaces -Label "Client matrix $($client.Suffix)"
        if (($actualInterfaceSet -join ',') -cne ($expectedInterfaceSet -join ',')) {
            throw "$tocName has interfaces '$actualInterface', expected the client matrix set '$($client.Interfaces)'"
        }
        $clientTokenLines = @($content | Where-Object { $_ -match '^## X-MSUF-Client:' })
        $actualClientToken = if ($clientTokenLines.Count -gt 0) { ($clientTokenLines[0] -replace '^## X-MSUF-Client:\s*', '').Trim() } else { "" }
        if ($clientTokenLines.Count -gt 1 -or $actualClientToken -cne $client.ClientToken) {
            throw "$tocName declares X-MSUF-Client '$actualClientToken', expected '$($client.ClientToken)'"
        }

        # A Mainline TOC is read by Midnight and by WoW Forever, so it carries two
        # conditioned Version lines: one for the standard game type and one for
        # every other. Since 6.50 both carry this release's VERSION; the pair stays
        # so a client line can diverge again without changing the TOC shape. Only
        # the "standard" token is used; it exists on every client. Classic TOCs
        # carry one plain line.
        $versionLines = @($content | Where-Object { $_ -match '^## Version:' })
        if ($client.Suffix -eq "Mainline") {
            $standardLines = @($versionLines | Where-Object { $_ -match '^## Version:\s*(\S+)\s+\[AllowLoadGameType standard\]\s*$' })
            $otherLines = @($versionLines | Where-Object { $_ -match '^## Version:\s*(\S+)\s+\[ExcludeLoadGameType standard\]\s*$' })
            if ($versionLines.Count -ne 2 -or $standardLines.Count -ne 1 -or $otherLines.Count -ne 1) {
                throw "$tocName needs exactly '## Version: <release> [AllowLoadGameType standard]' and '## Version: <release> [ExcludeLoadGameType standard]'"
            }
            $versionLine = $standardLines[0] -replace '\s+\[AllowLoadGameType standard\]\s*$', ''
            $otherVersion = ($otherLines[0] -replace '^## Version:\s*', '' -replace '\s+\[ExcludeLoadGameType standard\]\s*$', '').Trim()
            if ($otherVersion -cne $expectedVersion) {
                throw "$tocName declares version '$otherVersion' outside the standard game type, expected VERSION '$expectedVersion'"
            }
        } else {
            if ($versionLines.Count -ne 1 -or $versionLines[0] -match '\[') {
                throw "$tocName needs exactly one plain Version line"
            }
            $versionLine = $versionLines[0]
        }
        $versions[$client.Suffix] = ($versionLine -replace '^## Version:\s*', '').Trim()
        # Owner decision 2026-10-09: every client, Midnight included, runs this
        # release's version, so the standard-game-type line follows VERSION too.
        if ($versions[$client.Suffix] -ne $expectedVersion) {
            throw "$tocName has version '$($versions[$client.Suffix])', expected VERSION '$expectedVersion'"
        }
        # WoW Forever shares the Mainline TOCs but follows the Classic release line:
        # the core TOC names its version in X-MSUF-Version-Forever (Client.AddonVersion).
        $foreverVersionLines = @($content | Where-Object { $_ -match '^## X-MSUF-Version-Forever:' })
        $expectsForeverVersion = $client.Suffix -eq "Mainline" -and $target.Base -ceq "MidnightSimpleUnitFrames"
        if ($expectsForeverVersion) {
            $foreverVersion = if ($foreverVersionLines.Count -eq 1) { ($foreverVersionLines[0] -replace '^## X-MSUF-Version-Forever:\s*', '').Trim() } else { "" }
            if ($foreverVersion -cne $expectedVersion) {
                throw "$tocName declares X-MSUF-Version-Forever '$foreverVersion', expected VERSION '$expectedVersion'"
            }
        } elseif ($foreverVersionLines.Count -ne 0) {
            throw "$tocName must not declare X-MSUF-Version-Forever; only the core Mainline TOC does"
        }
        # TOC metadata that carries profile and release identity, or that code reads back at
        # runtime, must be the same on every client of an addon. Only the fields that name the
        # client or its packaging differ.
        $sharedMetadata = @($content | Where-Object {
            $_ -match '^## ' -and $_ -notmatch '^## (?:Interface|Title|Notes|Category|Version|X-MSUF-Version-Forever|OptionalDeps|X-MSUF-Client):'
        })
        if ($null -eq $referenceMetadata) {
            $referenceMetadata = $sharedMetadata
            $referenceMetadataToc = $tocName
        } elseif (@(Compare-Object -CaseSensitive $referenceMetadata $sharedMetadata).Count -ne 0) {
            throw "$tocName metadata differs from $referenceMetadataToc beyond the per-client fields (Interface, Title, Notes, Category, Version, OptionalDeps, X-MSUF-Client)"
        }
        Assert-MsufTocIdentity -TocName $tocName -Addon $target.Base -Content ([string[]]@($content)) -Rows $tocIdentityRows
        if ($target.Base -ceq "MidnightSimpleUnitFrames") {
            # Dropping an optional dependency changes the load order against that addon.
            $optionalDepsLines = @($content | Where-Object { $_ -match '^## OptionalDeps:' })
            $optionalDeps = @()
            if ($optionalDepsLines.Count -eq 1) {
                $optionalDeps = @(($optionalDepsLines[0] -replace '^## OptionalDeps:\s*', '').Split(',') | ForEach-Object { $_.Trim() })
            }
            $requiredDeps = @('LibSharedMedia-3.0', 'Clique', 'WagoAnalytics', 'MapkoSkin')
            if ($client.Suffix -ceq "Mainline") {
                $requiredDeps += @('Blizzard_AuraContainer', 'Blizzard_PingUI', 'EllesmereUI', 'Grid2', 'Details')
            }
            $missingDeps = @($requiredDeps | Where-Object { $optionalDeps -cnotcontains $_ })
            if ($optionalDepsLines.Count -ne 1 -or $missingDeps.Count -gt 0) {
                throw "$tocName must keep a single OptionalDeps line that still names: $($missingDeps -join ', ')"
            }
        }

        foreach ($entry in (Get-MsufTocEntries -Path $tocPath)) {
            $entryPath = [IO.Path]::GetFullPath((Join-Path $folder $entry.Trim()))
            if (-not (Test-Path -LiteralPath $entryPath -PathType Leaf)) {
                throw "Missing TOC entry: $tocPath -> $entry"
            }
            if ([IO.Path]::GetExtension($entryPath) -ieq ".xml") {
                [void](Get-MsufLoadGraph -Path $entryPath -Duplicates Skip -RequireFiles -VisitedXml $seenXml)
            }
        }
    }

}

# Every file any shipped TOC reaches, over the union of its locale and game
# type branches. The tombstone proof and the unreached-Lua check read it.
$shippedLoadedPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($target in $targets) {
    foreach ($client in $clients) {
        $shippedToc = Join-Path (Join-Path $root $target.Folder) ("{0}_{1}.toc" -f $target.Base, $client.Suffix)
        foreach ($loadedPath in (Get-MsufLoadGraph -Path $shippedToc -Duplicates Skip).AllPaths) {
            [void]$shippedLoadedPaths.Add($loadedPath)
        }
    }
}
Assert-MsufAddonTombstones -Root $root -Tombstones $addonTombstones -LoadedPaths ([string[]]@($shippedLoadedPaths))
Write-Host "Addon tombstones: $($addonTombstones.Addons.Count) retired addons untracked and without a TOC; $($addonTombstones.Paths.Count) retired paths untracked and unloaded"

# Source contracts below pin one condition per call, so a failure names the
# condition that broke and the file it broke in instead of the group it sits in.
function Assert-GateSourceContract {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Source,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Requirement,
        [switch]$Forbidden
    )
    if (($Source -match $Pattern) -ne [bool]$Forbidden) { return }
    $verb = if ($Forbidden) { "must not" } else { "must" }
    throw "$RelativePath $verb $Requirement (source pattern: $Pattern)"
}

# Player castbar event handling is client-neutral. Classic flavors must load
# the shared Castbars runtime directly so STOP/INTERRUPTED ordering fixes
# cannot drift in an unreviewed duplicate again.
foreach ($flavor in $classicSuffixes) {
    $coreFlavorTocRelative = "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_$flavor.toc"
    $coreFlavorEntries = @(Get-Content -LiteralPath (Join-Path $root $coreFlavorTocRelative))
    if ([Array]::IndexOf($coreFlavorEntries, "Castbars\MSUF_PlayerCastbarRuntime.lua") -lt 0) {
        throw "$coreFlavorTocRelative must load the synchronized Castbars\MSUF_PlayerCastbarRuntime.lua"
    }
    if ($coreFlavorEntries -match 'Game\\Classic\\Castbars\\MSUF_PlayerCastbarRuntime[.]lua') {
        throw "$coreFlavorTocRelative still loads the stale Classic player-castbar duplicate Game\Classic\Castbars\MSUF_PlayerCastbarRuntime.lua"
    }
}
if (Test-Path -LiteralPath (Join-Path $root "MidnightSimpleUnitFrames/Game/Classic/Castbars/MSUF_PlayerCastbarRuntime.lua")) {
    throw "Classic player-castbar duplicate must remain retired: MidnightSimpleUnitFrames/Game/Classic/Castbars/MSUF_PlayerCastbarRuntime.lua"
}

# Client initialization publishes MSUF.Client, so it loads before the Kernel
# bootstrap in every TOC family, not only in the one that was asserted first.
# Mainline has no Classic initializer at all: loading one would already cost
# Midnight start-up time.
foreach ($client in $clientMatrix) {
    $coreTocRelative = "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_$($client.Suffix).toc"
    $coreEntries = @(Get-Content -LiteralPath (Join-Path $root $coreTocRelative))
    $sharedIndex = [Array]::IndexOf($coreEntries, "Game\Shared\Initialize.lua")
    $classicIndex = [Array]::IndexOf($coreEntries, "Game\Classic\Initialize.lua")
    $bootstrapIndex = [Array]::IndexOf($coreEntries, "Kernel\MSUF_Bootstrap.lua")
    if ($sharedIndex -lt 0) {
        throw "$coreTocRelative must load Game\Shared\Initialize.lua"
    }
    if ($bootstrapIndex -lt 0) {
        throw "$coreTocRelative must load Kernel\MSUF_Bootstrap.lua"
    }
    if ($sharedIndex -gt $bootstrapIndex) {
        throw "$coreTocRelative must load Game\Shared\Initialize.lua before Kernel\MSUF_Bootstrap.lua"
    }
    if ($client.IsClassic -ceq "true") {
        if ($classicIndex -lt 0) {
            throw "$coreTocRelative must load Game\Classic\Initialize.lua"
        }
        if ($sharedIndex -gt $classicIndex) {
            throw "$coreTocRelative must load Game\Shared\Initialize.lua before Game\Classic\Initialize.lua"
        }
        if ($classicIndex -gt $bootstrapIndex) {
            throw "$coreTocRelative must load Game\Classic\Initialize.lua before Kernel\MSUF_Bootstrap.lua"
        }
    } elseif ($classicIndex -ge 0) {
        throw "$coreTocRelative must not load Game\Classic\Initialize.lua; Mainline stays free of the Classic initializer"
    }
}

$groupOwnershipRelative = "MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Blizzard.lua"
$groupOwnershipSource = Get-Content -LiteralPath (Join-Path $root $groupOwnershipRelative) -Raw
Assert-GateSourceContract -Source $groupOwnershipSource -RelativePath $groupOwnershipRelative `
    -Pattern 'HideFrame\(_G\.PartyFrame\)' -Requirement "hide the PartyFrame owner"
Assert-GateSourceContract -Source $groupOwnershipSource -RelativePath $groupOwnershipRelative `
    -Pattern 'HideFrame\(_G\.CompactRaidFrameContainer\)' -Requirement "hide the CompactRaidFrameContainer owner"
Assert-GateSourceContract -Source $groupOwnershipSource -RelativePath $groupOwnershipRelative -Forbidden `
    -Pattern 'PartyMemberFramePool\s*,\s*function' -Requirement "hook the PartyMemberFramePool members; only their owner is hidden"
Assert-GateSourceContract -Source $groupOwnershipSource -RelativePath $groupOwnershipRelative -Forbidden `
    -Pattern 'memberUnitFrames\s*,\s*function' -Requirement "hook memberUnitFrames; only their owner is hidden"
Assert-GateSourceContract -Source $groupOwnershipSource -RelativePath $groupOwnershipRelative `
    -Pattern 'function GF\.RestoreBlizzardGroupFrames\(\)[\s\S]*?return false' `
    -Requirement "keep the Blizzard CompactUnitFrame ownership handoff reload-only (RestoreBlizzardGroupFrames returns false)"
Assert-GateSourceContract -Source $groupOwnershipSource -RelativePath $groupOwnershipRelative `
    -Pattern 'raidManagerMode' -Requirement "keep the RC4 Raid Manager visibility mode"
Assert-GateSourceContract -Source $groupOwnershipSource -RelativePath $groupOwnershipRelative `
    -Pattern 'key\s*=\s*"toggleButton",\s*global\s*=\s*"CompactRaidFrameManagerToggleButton"' `
    -Requirement "keep the legacy Raid Manager toggle-button hook"

$elementsRoot = Join-Path $root "MidnightSimpleUnitFrames/UnitFrames/Embeds/MSUF_UFCore"
$gameRoot = Join-Path $root "MidnightSimpleUnitFrames/Game"
$classicSharedElementsPath = Join-Path $gameRoot "Classic/UnitFrames/MSUF_UFCore_Elements.xml"
$mainlineSharedElementsPath = Join-Path $elementsRoot "MSUF_UFCore_Elements.xml"
$auraCorePath = [IO.Path]::GetFullPath((Join-Path $root "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_IconShape.lua"))
$mainlineSharedLoadOrder = @((Get-MsufLoadGraph -Path $mainlineSharedElementsPath -Duplicates Repeat).LuaPaths)
$auraCoreIndex = [Array]::IndexOf($mainlineSharedLoadOrder, $auraCorePath)
if ($auraCoreIndex -lt 0) {
    throw "Mainline element manifest no longer loads the shared Auras3 icon definitions"
}
$classicSharedLoadOrder = @((Get-MsufLoadGraph -Path $classicSharedElementsPath -Duplicates Repeat).LuaPaths)
if ($classicSharedLoadOrder.Count -ne ($auraCoreIndex + 1)) {
    throw "Classic shared element manifest must match the Mainline prefix through shared Auras3 icon definitions"
}
for ($index = 0; $index -le $auraCoreIndex; $index++) {
    if ($classicSharedLoadOrder[$index] -ne $mainlineSharedLoadOrder[$index]) {
        throw "Classic shared element load order differs from Mainline before Auras3 backend selection at index $index"
    }
}

$classicAuraBackendPath = [IO.Path]::GetFullPath((Join-Path $root "MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua"))
$classicAuraCompilePath = [IO.Path]::GetFullPath((Join-Path $root "MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_Compile.lua"))
$classicAuraManifestContracts = @(
    @{ Pattern = '\.\.\\Classic\\Auras\\MSUF_Auras3_Features\.lua'; Requirement = "select the Classic aura feature compiler ..\Classic\Auras\MSUF_Auras3_Features.lua" },
    @{ Pattern = '\.\.\\Classic\\Auras\\MSUF_Auras3_Visuals\.lua'; Requirement = "select the Classic aura visuals ..\Classic\Auras\MSUF_Auras3_Visuals.lua" },
    @{ Pattern = '\.\.\\Classic\\Auras\\MSUF_Auras3_Compile\.lua'; Requirement = "select the Classic aura compiler ..\Classic\Auras\MSUF_Auras3_Compile.lua" },
    @{ Pattern = '\.\.\\Classic\\Auras\\MSUF_Auras3_UnitFrames\.lua'; Requirement = "select the Classic aura backend ..\Classic\Auras\MSUF_Auras3_UnitFrames.lua" },
    @{ Pattern = '\.\.\\Classic\\UnitFrames\\MSUF_UFCore_Elements\.xml'; Requirement = "select the Classic shared element manifest ..\Classic\UnitFrames\MSUF_UFCore_Elements.xml" },
    @{ Pattern = 'Auras\\MSUF_Auras3_DotData\.lua'; Requirement = "load the shared Auras3 DoT data" },
    @{ Pattern = 'Auras\\MSUF_Auras3_DefensiveData\.lua'; Requirement = "load the shared Auras3 defensive data" },
    @{ Pattern = 'AuraNameResolver'; Forbidden = $true; Requirement = "load the Retail aura name resolver" },
    @{ Pattern = 'Mainline\\Auras'; Forbidden = $true; Requirement = "load anything from the Mainline aura tree" }
)
foreach ($flavor in $classicSuffixes) {
    $classicManifestRelative = "MidnightSimpleUnitFrames/Game/$flavor/UnitFrames.xml"
    $classicManifestPath = Join-Path $gameRoot "$flavor/UnitFrames.xml"
    $classicAurasPath = Join-Path $gameRoot "$flavor/Auras.xml"
    $classicElements = (Get-Content -LiteralPath $classicManifestPath -Raw) +
        (Get-Content -LiteralPath $classicAurasPath -Raw)
    foreach ($contract in $classicAuraManifestContracts) {
        Assert-GateSourceContract -Source $classicElements -RelativePath $classicManifestRelative `
            -Pattern $contract.Pattern -Requirement $contract.Requirement -Forbidden:($contract.ContainsKey("Forbidden"))
    }
    # Walk the TOC so prefix, locale catalogs and aura continuation are checked together.
    $classicTocPath = Join-Path $root "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_$flavor.toc"
    $classicLoadOrder = @((Get-MsufLoadGraph -Path $classicTocPath -Duplicates Repeat).LuaPaths)
    $classicAuraBackendIndex = [Array]::IndexOf($classicLoadOrder, $classicAuraBackendPath)
    $classicAuraCoreIndex = [Array]::IndexOf($classicLoadOrder, $auraCorePath)
    if ($classicAuraBackendIndex -lt 0) {
        throw "$classicManifestRelative must load the Classic aura backend: $classicAuraBackendPath"
    }
    if ($classicAuraCoreIndex -lt 0) {
        throw "$classicManifestRelative must load the Auras3 icon core: $auraCorePath"
    }
    if ($classicAuraCoreIndex -gt $classicAuraBackendIndex) {
        throw "$classicManifestRelative must load the Auras3 icon core before the Classic aura backend"
    }
    # The backend imports its config compiler through A3._ClassicCompile at load time.
    $classicAuraCompileIndex = [Array]::IndexOf($classicLoadOrder, $classicAuraCompilePath)
    if ($classicAuraCompileIndex -lt 0) {
        throw "$classicManifestRelative must load the Classic aura compiler: $classicAuraCompilePath"
    }
    if ($classicAuraCompileIndex -gt $classicAuraBackendIndex) {
        throw "$classicManifestRelative must load the Classic aura compiler before the Classic aura backend"
    }
    $groupManifestRelative = "MidnightSimpleUnitFrames/Game/$flavor/UnitFrames/GroupFrames.xml"
    $groupElements = Get-Content -LiteralPath (Join-Path $gameRoot "$flavor/UnitFrames/GroupFrames.xml") -Raw
    Assert-GateSourceContract -Source $groupElements -RelativePath $groupManifestRelative `
        -Pattern 'Group\\MSUF_UF_Group_SpellIndicators_Data\.lua' `
        -Requirement "select its Classic group spell-indicator data Group\MSUF_UF_Group_SpellIndicators_Data.lua"
    Assert-GateSourceContract -Source $groupElements -RelativePath $groupManifestRelative `
        -Pattern 'Classic\\UnitFrames\\Group\\MSUF_UF_Group_SpellIndicators_Data_Base\.lua' `
        -Requirement "select the Classic spell-indicator base data Classic\UnitFrames\Group\MSUF_UF_Group_SpellIndicators_Data_Base.lua"
    Assert-GateSourceContract -Source $groupElements -RelativePath $groupManifestRelative -Forbidden `
        -Pattern 'Mainline\\UnitFrames\\Group' -Requirement "load anything from the Mainline group tree"
}

function Assert-NormalizedAddonPath {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not (Test-MsufNormalizedAddonPath -RelativePath $RelativePath -AddonFolders ([string[]]@($targets | ForEach-Object { $_.Folder })))) {
        throw "$Label is not a normalized path below an addon root: $RelativePath"
    }
}

function Assert-OrdinalPathOrder {
    param(
        # Empty is allowed: a manifest may legitimately hold no rows.
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Paths,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $sorted = [string[]]$Paths.Clone()
    [Array]::Sort($sorted, [StringComparer]::Ordinal)
    for ($index = 0; $index -lt $Paths.Count; $index++) {
        if ($Paths[$index] -cne $sorted[$index]) {
            throw "$Label must use ordinal path sorting"
        }
    }
}

$addonFolders = @($targets | ForEach-Object { $_.Folder })
$trackedAddonPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$trackedAddonPathResult = Invoke-GateGit -Arguments (@("-C", $root, "-c", "core.quotepath=off", "ls-files", "--") + $addonFolders)
if ($trackedAddonPathResult.ExitCode -ne 0) {
    throw "Unable to enumerate tracked Classic addon files: $($trackedAddonPathResult.Lines -join ', ')"
}
$trackedAddonPathLines = $trackedAddonPathResult.Lines
foreach ($trackedPath in $trackedAddonPathLines) {
    [void]$trackedAddonPaths.Add($trackedPath.Replace([char]92, [char]47))
}

function Get-CurrentLuaLoadPaths {
    param([Parameter(Mandatory = $true)][string]$TocPath)
    return [string[]]@((Get-MsufLoadGraph -Path $TocPath -Duplicates Skip).LuaPaths)
}

function Get-RepositoryRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryFull,
        [Parameter(Mandatory = $true)][string]$FullPath,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $resolved = [IO.Path]::GetFullPath($FullPath)
    $comparison = if ([IO.Path]::DirectorySeparatorChar -eq [char]92) {
        [StringComparison]::OrdinalIgnoreCase
    } else {
        [StringComparison]::Ordinal
    }
    $prefix = $RepositoryFull.TrimEnd([char]92, [char]47) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix, $comparison)) {
        throw "$Label escaped its repository root: $resolved"
    }
    return $resolved.Substring($prefix.Length).Replace([char]92, [char]47)
}

# tools/load-graph.lock lists the ordered Lua files each client loads. tools/load-graph.lua
# regenerates it, and its --check mode proves the lock current and holds the load-graph
# invariants: Mainline and Forever load no Classic-only code, Classic loads no Retail aura
# runtime, no client loads a file twice. The generator reads the manifests with
# tools/tests/client_manifest.lua; this gate reads them with Get-MsufLoadGraph, so the two
# readers are held to the same answer here.
$loadGraphLockRelative = "tools/load-graph.lock"
$loadGraphToolRelative = "tools/load-graph.lua"
Assert-TrackedFile -RelativePath $loadGraphLockRelative -Label "Load-graph lock"
Assert-TrackedFile -RelativePath $loadGraphToolRelative -Label "Load-graph lock generator"
if ($lua) {
    $loadGraphCheck = Invoke-GateNative -Command $lua.Source -Arguments @($loadGraphToolRelative, "--check")
    if ($loadGraphCheck.ExitCode -ne 0) { throw ($loadGraphCheck.Lines -join "`n") }
    Write-Host ($loadGraphCheck.Lines -join "`n")
}
$loadGraphViews = [Collections.Generic.List[hashtable]]::new()
foreach ($loadGraphClient in $clientMatrix) {
    $loadGraphGameType = if ($loadGraphClient.IsClassic -ceq "true") { "" } else { "standard" }
    $loadGraphViews.Add(@{ View = $loadGraphClient.Suffix; Flavor = $loadGraphClient.Suffix; GameType = $loadGraphGameType })
    if ($loadGraphClient.IsClassic -cne "true") {
        # WoW Forever reads the Mainline TOCs; only the game type tells it apart.
        $loadGraphViews.Add(@{ View = "Forever"; Flavor = $loadGraphClient.Suffix; GameType = "camelot" })
    }
}
$lockSections = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
$lockSection = $null
foreach ($lockLine in ([IO.File]::ReadAllText((Join-Path $root $loadGraphLockRelative)) -split "`r?`n")) {
    if ($lockLine -match '^@ (\S+) (\S+) \(\d+ files\)$') {
        $lockSection = [Collections.Generic.List[string]]::new()
        $lockSections.Add("$($Matches[1]) $($Matches[2])", $lockSection)
    } elseif ($lockLine.Length -gt 0 -and -not $lockLine.StartsWith('#')) {
        if ($null -eq $lockSection) { throw "$loadGraphLockRelative has a path before its first section header: $lockLine" }
        $lockSection.Add($lockLine)
    }
}
if ($lockSections.Count -ne $loadGraphViews.Count * $targets.Count) {
    throw "$loadGraphLockRelative has $($lockSections.Count) sections, expected $($loadGraphViews.Count * $targets.Count); regenerate it: lua tools/load-graph.lua --write"
}
foreach ($loadGraphView in $loadGraphViews) {
    foreach ($target in $targets) {
        $sectionName = "$($loadGraphView.View) $($target.Folder)"
        if (-not $lockSections.ContainsKey($sectionName)) { throw "$loadGraphLockRelative has no section '$sectionName'; regenerate it: lua tools/load-graph.lua --write" }
        $graphToc = Join-Path (Join-Path $root $target.Folder) ("{0}_{1}.toc" -f $target.Base, $loadGraphView.Flavor)
        $graphPaths = @((Get-MsufLoadGraph -Path $graphToc -Duplicates Repeat -GameType $loadGraphView.GameType).LuaPaths |
            ForEach-Object { Get-RepositoryRelativePath -RepositoryFull $rootFull -FullPath $_ -Label "$sectionName load path" })
        $lockedPaths = $lockSections[$sectionName]
        for ($index = 0; $index -lt [Math]::Max($graphPaths.Count, $lockedPaths.Count); $index++) {
            $graphPath = if ($index -lt $graphPaths.Count) { $graphPaths[$index] } else { "<end>" }
            $lockedPath = if ($index -lt $lockedPaths.Count) { $lockedPaths[$index] } else { "<end>" }
            if ($graphPath -cne $lockedPath) {
                throw "$loadGraphLockRelative disagrees with the gate's TOC walk for '$sectionName' at position $($index + 1): lock '$lockedPath', walk '$graphPath'; regenerate it: lua tools/load-graph.lua --write"
            }
        }
    }
}
if (-not $lua) { $skippedSteps.Add("Load-graph lock invariants (lua not found)") }
Write-Host "Load graph: $($lockSections.Count) lock sections ($($loadGraphViews.Count) clients x $($targets.Count) addons) match the gate's TOC walk"

# The packager ships the addon folders as they are, so a scratch script, log or
# backup left below them would ship. Every file git versions there (or would
# version) is one of the shippable types, has a normalized path, and shares its
# name with no other file once case is ignored (WoW resolves file names without case).
$versionableAddonFiles = @(Get-MsufVersionableFiles -Root $root -Folders $addonFolders)
Assert-MsufAddonPaths -AddonFolders $addonFolders `
    -Paths ([string[]]@(@($trackedAddonPathLines) + $versionableAddonFiles | Sort-Object -Unique -CaseSensitive))
$shippableExtensions = @(".lua", ".xml", ".toc", ".tga", ".png", ".blp", ".ttf", ".otf", ".md")
$strayAddonFiles = @($versionableAddonFiles | Where-Object {
    [IO.Path]::GetFileName($_) -cne ".gitignore" -and $shippableExtensions -cnotcontains [IO.Path]::GetExtension($_).ToLowerInvariant()
})
if ($strayAddonFiles.Count -gt 0) {
    throw "Addon folders hold files that are not a shippable type ($($shippableExtensions -join ' ')); move them out of the addon folders or extend `$shippableExtensions in tools/test-classic-prototype.ps1: $($strayAddonFiles -join ', ')"
}

# Every versioned addon Lua file is loaded by a shipped TOC, so no dead payload
# ships and no edit lands in a file that never runs. The exceptions are listed
# with a kind and a reason in tools/classic-unloaded-addon-lua.tsv: a developer
# diagnostic no TOC loads ('diagnostic'), or a file the owner keeps unloaded on
# purpose ('retained', citing the decision). The pixel layout coverage smoke
# skips the same files. Rules: Assert-MsufUnloadedAddonLua.
$unloadedLuaRelative = "tools/classic-unloaded-addon-lua.tsv"
Assert-TrackedFile -RelativePath $unloadedLuaRelative -Label "Classic unloaded addon Lua manifest"
$unloadedLua = Assert-MsufUnloadedAddonLua -Root $root -ManifestPath (Join-Path $root $unloadedLuaRelative) `
    -VersionableLua $versionableAddonLua -LoadedPaths ([string[]]@($shippedLoadedPaths)) `
    -TrackedPaths ([string[]]@($trackedAddonPaths))
Write-Host "Unloaded addon Lua: every versioned addon Lua file is loaded by a shipped TOC except $($unloadedLua.Diagnostics) listed diagnostic(s) and $($unloadedLua.Retained) retained file(s)"

# Flavor load coverage. Every Lua file the Mainline core and Options TOCs load
# must, on each Classic flavor in the client matrix, be loaded or be excluded with
# a reason in tools/classic-flavor-load-exclusions.tsv. A Lua file added to a
# manifest Classic copies therefore cannot go missing on Classic unnoticed.
# Every exclusion row must still be needed.
$flavorExclusionRelative = "tools/classic-flavor-load-exclusions.tsv"
$flavorExclusionPath = Join-Path $root $flavorExclusionRelative
if (-not (Test-Path -LiteralPath $flavorExclusionPath -PathType Leaf)) {
    throw "Classic flavor load exclusion manifest is missing: $flavorExclusionRelative"
}
Assert-TrackedFile -RelativePath $flavorExclusionRelative -Label "Classic flavor load exclusion manifest"
$coverageAddons = @("MidnightSimpleUnitFrames", "MidnightSimpleUnitFrames_Options")
function Get-FlavorLuaLoadPaths {
    param([Parameter(Mandatory = $true)][string]$Suffix)
    $paths = [Collections.Generic.List[string]]::new()
    foreach ($addon in $coverageAddons) {
        $tocPath = Join-Path $root "$addon/$($addon)_$Suffix.toc"
        foreach ($loadPath in @(Get-CurrentLuaLoadPaths -TocPath $tocPath)) {
            $paths.Add((Get-RepositoryRelativePath -RepositoryFull $rootFull -FullPath $loadPath -Label "$Suffix $addon load path"))
        }
    }
    return $paths.ToArray()
}
$mainlineCoveragePaths = @(Get-FlavorLuaLoadPaths -Suffix "Mainline")
$mainlineCoverageSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($coveragePath in $mainlineCoveragePaths) { [void]$mainlineCoverageSet.Add($coveragePath) }

$flavorExclusionLines = [string[]][IO.File]::ReadAllLines($flavorExclusionPath)
if ($flavorExclusionLines.Count -eq 0 -or $flavorExclusionLines[0] -cne "MainlinePath`tFlavors`tReason") {
    throw "Classic flavor load exclusion manifest must start with the header MainlinePath<TAB>Flavors<TAB>Reason"
}
$flavorExclusions = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
$flavorExclusionPathCase = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
$flavorExclusionPathsInOrder = [Collections.Generic.List[string]]::new()
for ($lineIndex = 1; $lineIndex -lt $flavorExclusionLines.Count; $lineIndex++) {
    $exclusionLine = $flavorExclusionLines[$lineIndex]
    $fields = $exclusionLine.Split([char]9)
    if ($fields.Count -ne 3) {
        throw "Classic flavor load exclusion must be MainlinePath<TAB>Flavors<TAB>Reason: $exclusionLine"
    }
    $exclusionPath = $fields[0]
    Assert-NormalizedAddonPath -RelativePath $exclusionPath -Label "Classic flavor load exclusion"
    if (@($coverageAddons | Where-Object { $exclusionPath.StartsWith($_ + '/', [StringComparison]::Ordinal) }).Count -eq 0) {
        throw "Classic flavor load exclusions cover only the core and Options addons: $exclusionPath"
    }
    if ($flavorExclusionPathCase.ContainsKey($exclusionPath)) {
        throw "Duplicate or case-colliding Classic flavor load exclusion: $($flavorExclusionPathCase[$exclusionPath]) versus $exclusionPath"
    }
    $excludedFlavors = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    if ($fields[1] -ceq "*") {
        foreach ($classicSuffix in $classicSuffixes) { [void]$excludedFlavors.Add($classicSuffix) }
    } else {
        foreach ($classicSuffix in $fields[1].Split(',')) {
            if ([Array]::IndexOf($classicSuffixes, $classicSuffix) -lt 0 -or -not $excludedFlavors.Add($classicSuffix)) {
                throw "Classic flavor load exclusion names an unknown or repeated Classic flavor '$classicSuffix': $exclusionLine"
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($fields[2]) -or $fields[2] -cne $fields[2].Trim()) {
        throw "Classic flavor load exclusion needs a trimmed reason: $exclusionLine"
    }
    if (-not $mainlineCoverageSet.Contains($exclusionPath)) {
        throw "Stale Classic flavor load exclusion: Mainline no longer loads $exclusionPath; remove its row from $flavorExclusionRelative"
    }
    $flavorExclusionPathCase.Add($exclusionPath, $exclusionPath)
    $flavorExclusions.Add($exclusionPath, $excludedFlavors)
    $flavorExclusionPathsInOrder.Add($exclusionPath)
}
if ($flavorExclusionPathsInOrder.Count -gt 0) {
    Assert-OrdinalPathOrder -Paths $flavorExclusionPathsInOrder.ToArray() -Label "Classic flavor load exclusion manifest"
}

$coverageLoadedCount = 0
$coverageExcludedCount = 0
foreach ($classicSuffix in $classicSuffixes) {
    $flavorLoaded = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($coveragePath in @(Get-FlavorLuaLoadPaths -Suffix $classicSuffix)) { [void]$flavorLoaded.Add($coveragePath) }
    foreach ($coveragePath in $mainlineCoveragePaths) {
        $isLoaded = $flavorLoaded.Contains($coveragePath)
        $isExcluded = $flavorExclusions.ContainsKey($coveragePath) -and $flavorExclusions[$coveragePath].Contains($classicSuffix)
        if ($isLoaded -and $isExcluded) {
            throw "Stale Classic flavor load exclusion: $classicSuffix loads $coveragePath; drop $classicSuffix from its row in $flavorExclusionRelative"
        }
        if ($isLoaded) {
            $coverageLoadedCount++
        } elseif ($isExcluded) {
            $coverageExcludedCount++
        } else {
            throw "Classic flavor load coverage: $classicSuffix does not load Mainline Lua $coveragePath; load it from the $classicSuffix manifests or add a row with a reason to $flavorExclusionRelative"
        }
    }
}
Write-Host "Classic flavor load coverage: $($mainlineCoveragePaths.Count) Mainline Lua paths x $($classicSuffixes.Count) flavors; $coverageLoadedCount loaded, $coverageExcludedCount excluded with reason"

# The unit-frame aura backend is split by cohesion; its contracts hold for the set.
$classicAuraSource = (@("Buttons", "Filters", "FrameVisuals", "Lanes", "UnitFrames", "Requests") | ForEach-Object {
    Get-Content -LiteralPath (Join-Path $root "MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_$_.lua") -Raw
}) -join "`n"
foreach ($requiredContract in @('Client.IsClassic', 'AuraUtil.ForEachAura', 'C_UnitAuras.GetAuraSlots', 'events = { "UNIT_AURA" }')) {
    if ($classicAuraSource.IndexOf($requiredContract) -lt 0) {
        throw "Classic aura backend is missing contract: $requiredContract"
    }
}
if ($classicAuraSource -match 'CustomAuraContainerTemplate|AURA_CONTAINER_ADDON') {
    throw "Classic aura backend must not depend on Blizzard_AuraContainer"
}
$classicAuraCompileSource = Get-Content -LiteralPath $classicAuraCompilePath -Raw
if ($classicAuraCompileSource -match 'CustomAuraContainerTemplate|AURA_CONTAINER_ADDON') {
    throw "Classic aura compiler must not depend on Blizzard_AuraContainer"
}

# Lua 5.1 compiles at most 200 locals, 60 upvalues and 250 stack slots per
# function. tools/quality_ratchet.py (run below as quality_ratchet_gate_smoke.py)
# is the only authority for those limits and their margins; this script
# only proves that every Lua file compiles.

# luac takes a file list, so the syntax check costs one process per
# argument-length chunk instead of one process per file.
function Invoke-LuacBatch {
    param(
        [Parameter(Mandatory = $true)][string]$LuacPath,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Files
    )
    $chunks = [Collections.Generic.List[object]]::new()
    $currentChunk = [Collections.Generic.List[string]]::new()
    $currentLength = 0
    foreach ($file in $Files) {
        if ($currentLength + $file.Length + 3 -gt 24000 -and $currentChunk.Count -gt 0) {
            $chunks.Add($currentChunk.ToArray())
            $currentChunk = [Collections.Generic.List[string]]::new()
            $currentLength = 0
        }
        $currentChunk.Add($file)
        $currentLength += $file.Length + 3
    }
    if ($currentChunk.Count -gt 0) { $chunks.Add($currentChunk.ToArray()) }

    foreach ($chunk in $chunks) {
        $startInfo = New-Object Diagnostics.ProcessStartInfo
        $startInfo.FileName = $LuacPath
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.Arguments = (@("-p") + @($chunk | ForEach-Object { '"' + $_ + '"' })) -join ' '
        $process = [Diagnostics.Process]::Start($startInfo)
        $null = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            return [pscustomobject]@{ ExitCode = $process.ExitCode; Error = $stderr.Trim(); Chunk = [string[]]@($chunk) }
        }
    }
    return [pscustomobject]@{ ExitCode = 0; Error = ""; Chunk = [string[]]@() }
}

# $luac and $lua were resolved and version-checked by the tool preflight; a
# missing tool was either fatal there or recorded as a skipped step.
if ($luac) {
    # The files git versions, read once near the top: ignored local copies
    # (luac.out, scripts under an addon's tools/ or docs/) are not the product.
    $luaFiles = [string[]]@($versionableAddonLua | ForEach-Object { [IO.Path]::GetFullPath((Join-Path $root $_)) })
    $syntax = Invoke-LuacBatch -LuacPath $luac.Source -Files $luaFiles
    if ($syntax.ExitCode -ne 0) {
        # Name the file: re-run the failing chunk one file at a time.
        foreach ($file in $syntax.Chunk) {
            $single = Invoke-LuacBatch -LuacPath $luac.Source -Files @($file)
            if ($single.ExitCode -ne 0) { throw "Lua 5.1 syntax failed: $file`n$($single.Error)" }
        }
        throw "Lua 5.1 syntax failed in a batch that no single file reproduces: $($syntax.Error)"
    }
    Write-Host "Lua 5.1 syntax: $($luaFiles.Count) files passed"
}

Invoke-GateSmokePhase
Assert-GateSmokeInventory

if (-not $SelfContained -and $uiMirrorPresent) {
    & (Join-Path $root "tools/audit-classic-ui-source.ps1")
    if ($LASTEXITCODE -ne 0) { throw "Blizzard Classic source contract audit failed" }
}

Write-Host "Client TOCs: $($targets.Count * $clientMatrix.Count) manifests passed ($($clientSuffixes -join ', '))"
Write-Host "XML load graph: $($seenXml.Count) manifests resolved"
Complete-GateRun
