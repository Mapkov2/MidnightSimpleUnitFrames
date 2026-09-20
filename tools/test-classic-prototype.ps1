[CmdletBinding()]
param(
    [string]$RetailReferenceRoot = "",
    [switch]$SelfContained,
    [switch]$AllowMissingTools,
    [switch]$ListSmokes,
    [string]$Only = "",
    [switch]$FailFast,
    [int]$Jobs = 0,
    [switch]$RequireNoSkippedSteps
)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "../.github/scripts/ClassicGate.Common.psm1") -Force
# -SelfContained is the CI subset: everything that needs neither a Retail
# checkout nor the Blizzard UI source mirror. It never replaces the full gate.
if ($SelfContained -and -not [string]::IsNullOrWhiteSpace($RetailReferenceRoot)) {
    throw "-SelfContained validates without a Retail reference; do not combine it with -RetailReferenceRoot"
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

function Invoke-GateGitWithInput {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$InputLines
    )
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $exitCode = 0
    try {
        $output = @($InputLines | & git @Arguments 2>&1 | ForEach-Object { [string]$_ })
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
        smoke the inventory check has not seen.
    #>
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Plan)

    foreach ($item in $Plan) {
        foreach ($argument in $item.Arguments) {
            $text = [string]$argument
            if ($text -notmatch $smokeFilePattern) { continue }
            $full = if ([IO.Path]::IsPathRooted($text)) { [IO.Path]::GetFullPath($text) } else { [IO.Path]::GetFullPath((Join-Path $rootFull $text)) }
            if (-not $full.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Gate smoke lies outside the repository: $text"
            }
            [void]$ranSmokes.Add($full.Substring($rootFull.Length + 1).Replace([char]92, [char]47))
        }
    }
    if ($Plan.Count -eq 0) { return }

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
$classicDirectoryPattern = '(' + ((@("Classic") + $classicSuffixes | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')'

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
    # Retail's sync workflow runs this gate in CI, where the mirror never exists.
    if ($AllowMissingTools -or $env:GITHUB_ACTIONS -eq "true") {
        $skippedSteps.Add("Blizzard UI source audit (no mirror at _local_workflows/references/wow-ui-source)")
    } else {
        throw "Blizzard UI source mirror is missing at _local_workflows/references/wow-ui-source; pass -AllowMissingTools only for a run that may skip the source audit"
    }
}

# The Retail reference is named, never guessed. A sibling auto-detect used to
# pick up whatever Retail working tree happened to sit next to this clone, so a
# full run could silently certify against the owner's live, dirty checkout.
# It is resolved here, ahead of the smoke manifest, because the Retail-shared
# runtime smokes take it as their baseline through the {retailRoot/} token.
$retailReferenceRootFull = $null
if ($SelfContained) {
    # The combination with -RetailReferenceRoot was already rejected above.
} elseif ([string]::IsNullOrWhiteSpace($RetailReferenceRoot)) {
    throw @"
A full Classic gate run needs -RetailReferenceRoot <path to a clean Retail clone>.
Make one and point the gate at it:
    git clone --no-hardlinks <Retail remote or local repository> C:\tmp\msuf-classic-ref
    git -C C:\tmp\msuf-classic-ref checkout <the Retail commit this release syncs from>
    tools\test-classic-prototype.ps1 -RetailReferenceRoot C:\tmp\msuf-classic-ref
The checkout must be clean and must be the Git repository root. Use -SelfContained
for the CI subset, which needs no Retail reference at all.
"@
} else {
    $retailReferenceRootFull = [IO.Path]::GetFullPath($RetailReferenceRoot).TrimEnd('\', '/')
    $referenceToc = Join-Path $retailReferenceRootFull "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames.toc"
    if (-not (Test-Path -LiteralPath $referenceToc -PathType Leaf)) {
        throw "Retail reference checkout is missing its core TOC: $referenceToc"
    }
}
$retailReferenceLabel = if ($retailReferenceRootFull) {
    "working tree at $retailReferenceRootFull"
} else {
    "no Retail reference (self-contained run)"
}
# {retailRoot/} resolves to "-" without a Retail reference. The Retail-shared
# runtime smokes read that sentinel as "no baseline" and say so on stdout, so a
# self-contained run never reads as if the comparison had happened.
$retailReferenceRootForward = if ($retailReferenceRootFull) { $retailReferenceRootFull -replace '\\', '/' } else { "-" }

# tools/classic-gate-smokes.tsv is the smoke list: one row per smoke, expanded
# over the client matrix by the Matrix column. Consecutive rows that name the
# same matrix run as one loop, which is how two smokes stay interleaved per
# flavor. Tokens: {root} the repository root as git prints it, {root/} the same
# with forward slashes, {retailRoot/} the Retail reference root with forward
# slashes (or "-" when there is none), {flavor} and {clientToken} the matrix
# row, {codec} the codec axis, {p/:<repo path>} an absolute forward-slash path.
$smokeManifestRelative = "tools/classic-gate-smokes.tsv"
$smokeManifestPath = Join-Path $root $smokeManifestRelative
if (-not (Test-Path -LiteralPath $smokeManifestPath -PathType Leaf)) {
    throw "Classic gate smoke manifest is missing: $smokeManifestRelative"
}
Assert-TrackedFile -RelativePath $smokeManifestRelative -Label "Classic gate smoke manifest"
$smokeRows = @(Import-Csv -LiteralPath $smokeManifestPath -Delimiter "`t")
if ($smokeRows.Count -eq 0) { throw "Classic gate smoke manifest is empty: $smokeManifestRelative" }
$smokeManifestColumns = @("Matrix", "Runner", "Smoke", "Arguments", "Label")
$actualSmokeColumns = @($smokeRows[0].PSObject.Properties | ForEach-Object { $_.Name })
if (($actualSmokeColumns -join "`t") -cne ($smokeManifestColumns -join "`t")) {
    throw "Classic gate smoke manifest columns must be exactly: $($smokeManifestColumns -join ', ')"
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
    $expanded = $Text.Replace("{retailRoot/}", $retailReferenceRootForward)
    $expanded = $expanded.Replace("{root/}", ($root -replace '\\', '/')).Replace("{root}", $root)
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
# The Retail-shared runtime smokes replay the Classic override and its Retail
# base side by side. Without a Retail reference they still run every
# self-contained assertion, but the comparison half cannot happen, so it is
# reported as a skipped step rather than left to a line of smoke output.
$retailBaselineRows = @($smokeRows | Where-Object { $_.Arguments -clike "*{retailRoot/}*" })
if ($retailBaselineRows.Count -gt 0 -and -not $retailReferenceRootFull) {
    $skippedSteps.Add("Retail baseline comparison in $($retailBaselineRows.Count) Retail-shared runtime smokes (no Retail reference)")
}
if (-not [string]::IsNullOrWhiteSpace($Only)) {
    # A narrowed run must never read as a pass, so the inventory check below is
    # recorded as skipped instead of silently accepting the smokes that sat out.
    $smokePlan = [Collections.Generic.List[object]]@($smokePlan | Where-Object { $_.Smoke -match $Only -or $_.Label -match $Only })
    if ($smokePlan.Count -eq 0) { throw "-Only '$Only' matches none of the $smokePlanTotal smoke invocations" }
    $skippedSteps.Add("Smoke inventory and $($smokePlanTotal - $smokePlan.Count) smoke invocations (-Only '$Only')")
}

# Python smokes need no Lua. With lua present they run in the smoke phase
# below, in one pool with the Lua smokes, so the slow git-driven ones (the
# override-rebase and Retail source resolver smokes) overlap with it instead of
# adding a wait of their own. Without lua that phase never runs, so they run here.
if (-not $lua) {
    Invoke-GateSmoke -Plan @($smokePlan | Where-Object { $_.Runner -ceq "python" })
}
& python (Join-Path $root ".github/quality/error_paths.py")
if ($LASTEXITCODE -ne 0) { throw "Classic error visibility contract failed" }

$targets = @(
    @{ Folder = "MidnightSimpleUnitFrames"; Base = "MidnightSimpleUnitFrames" },
    @{ Folder = "MidnightSimpleUnitFrames_Options"; Base = "MidnightSimpleUnitFrames_Options" },
    @{ Folder = "MidnightSimpleUnitFrames_Assistant"; Base = "MidnightSimpleUnitFrames_Assistant" }
)
$clients = $clientMatrix
$expectedVersion = (Get-Content -LiteralPath (Join-Path $root "VERSION") -Raw).Trim()
& (Join-Path $root ".github/scripts/assert-classic-6-5-release-line.ps1") `
    -RepositoryRoot $root -ReleaseVersion $expectedVersion

# Writing addon-owned fallbacks into Blizzard's C_* namespace taints the table
# and can surface later as ADDON_ACTION_FORBIDDEN at UseAction(). Compatibility
# adapters must stay below MSUF.Compat instead.
$taintWritePattern = '(?m)^\s*(?:_G\.)?C_[A-Za-z0-9_]+\.[A-Za-z0-9_]+\s*=(?!=)'
foreach ($target in $targets) {
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root $target.Folder) -Recurse -Filter "*.lua" -File) {
        $source = Get-Content -LiteralPath $file.FullName -Raw
        if ($source -match $taintWritePattern) {
            throw "Blizzard C_* namespace mutation is forbidden: $($file.FullName)"
        }
    }
}

# One walker, in .github/scripts/ClassicGate.Common.psm1, resolves every TOC and
# XML load graph in this gate. $seenXml is shared across TOCs so a manifest that
# several clients include is parsed once and counted once.
$seenXml = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

foreach ($target in $targets) {
    $folder = Join-Path $root $target.Folder
    $unsuffixed = Join-Path $folder ($target.Base + ".toc")
    if (Test-Path -LiteralPath $unsuffixed) {
        throw "Unsuffixed TOC should not coexist with client TOCs: $unsuffixed"
    }

    $versions = @{}
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
        # conditioned Version lines: Retail's for the standard game type and this
        # release's for every other one. Only the "standard" token is used; it
        # exists on every client. Classic TOCs carry one plain line.
        $versionLines = @($content | Where-Object { $_ -match '^## Version:' })
        if ($client.Suffix -eq "Mainline") {
            $standardLines = @($versionLines | Where-Object { $_ -match '^## Version:\s*(\S+)\s+\[AllowLoadGameType standard\]\s*$' })
            $otherLines = @($versionLines | Where-Object { $_ -match '^## Version:\s*(\S+)\s+\[ExcludeLoadGameType standard\]\s*$' })
            if ($versionLines.Count -ne 2 -or $standardLines.Count -ne 1 -or $otherLines.Count -ne 1) {
                throw "$tocName needs exactly '## Version: <Retail> [AllowLoadGameType standard]' and '## Version: <release> [ExcludeLoadGameType standard]'"
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
        $expectedClientVersion = $expectedVersion
        if ($client.Suffix -eq "Mainline" -and $retailReferenceRootFull) {
            $referenceToc = Join-Path $retailReferenceRootFull ($target.Folder + "/" + $target.Base + ".toc")
            $referenceVersionLine = Get-Content -LiteralPath $referenceToc |
                Where-Object { $_ -match '^## Version:' } |
                Select-Object -First 1
            $expectedClientVersion = ($referenceVersionLine -replace '^## Version:\s*', '').Trim()
        }
        # Mainline carries the Retail version, which only a Retail reference can supply.
        if (($client.IsClassic -ceq "true" -or $retailReferenceRootFull) -and $versions[$client.Suffix] -ne $expectedClientVersion) {
            throw "$tocName has version '$($versions[$client.Suffix])', expected '$expectedClientVersion'"
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
        if ($client.Suffix -eq "Mainline" -and $retailReferenceRootFull) {
            $referenceMetadata = @(Get-Content -LiteralPath $referenceToc | Where-Object { $_ -match '^## ' } |
                ForEach-Object {
                    if ($_ -match '^## Interface:') { $interfaceLine } else { $_ }
                })
            # X-MSUF-Version-Forever and the non-standard Version line are this repo's
            # own; Retail has no Forever client. The standard Version line compares
            # without its condition.
            $currentMetadata = @($content | Where-Object {
                $_ -match '^## ' -and $_ -notmatch '^## X-MSUF-Version-Forever:' -and
                $_ -notmatch '^## Version:.*\[ExcludeLoadGameType standard\]\s*$'
            } | ForEach-Object { $_ -replace '^(## Version:\s*\S+)\s+\[AllowLoadGameType standard\]\s*$', '$1' })
            if ($referenceMetadata.Count -ne $currentMetadata.Count -or
                @(Compare-Object $referenceMetadata $currentMetadata).Count -ne 0) {
                throw "$tocName metadata differs from Retail"
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
# the synchronized Retail runtime directly so STOP/INTERRUPTED ordering fixes
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
# Retail startup time.
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
    -Pattern 'HardHideFrame\(_G\.PartyFrame\)' -Requirement "hide the PartyFrame owner"
Assert-GateSourceContract -Source $groupOwnershipSource -RelativePath $groupOwnershipRelative `
    -Pattern 'HardHideFrame\(_G\.CompactRaidFrameContainer\)' -Requirement "hide the CompactRaidFrameContainer owner"
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
    -Pattern 'manager\.toggleButton\s+or\s+_G\.CompactRaidFrameManagerToggleButton' `
    -Requirement "keep the legacy Raid Manager toggle-button hook"

$elementsRoot = Join-Path $root "MidnightSimpleUnitFrames/UnitFrames/Embeds/MSUF_UFCore"
$gameRoot = Join-Path $root "MidnightSimpleUnitFrames/Game"
$classicSharedElementsPath = Join-Path $gameRoot "Classic/UnitFrames/MSUF_UFCore_Elements.xml"
$retailSharedElementsPath = Join-Path $elementsRoot "MSUF_UFCore_Elements.xml"
$auraCorePath = [IO.Path]::GetFullPath((Join-Path $root "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_IconShape.lua"))
$retailSharedLoadOrder = @((Get-MsufLoadGraph -Path $retailSharedElementsPath -Duplicates Repeat).LuaPaths)
$auraCoreIndex = [Array]::IndexOf($retailSharedLoadOrder, $auraCorePath)
if ($auraCoreIndex -lt 0) {
    throw "Retail element manifest no longer loads the shared Auras3 icon definitions"
}
$classicSharedLoadOrder = @((Get-MsufLoadGraph -Path $classicSharedElementsPath -Duplicates Repeat).LuaPaths)
if ($classicSharedLoadOrder.Count -ne ($auraCoreIndex + 1)) {
    throw "Classic shared element manifest must match the Retail prefix through shared Auras3 icon definitions"
}
for ($index = 0; $index -le $auraCoreIndex; $index++) {
    if ($classicSharedLoadOrder[$index] -ne $retailSharedLoadOrder[$index]) {
        throw "Classic shared element load order differs from Retail before Auras3 backend selection at index $index"
    }
}

$classicAuraBackendPath = [IO.Path]::GetFullPath((Join-Path $root "MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua"))
$classicAuraCompilePath = [IO.Path]::GetFullPath((Join-Path $root "MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_Compile.lua"))
$forbiddenRetailAuraPaths = @(
    "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_DotData.lua",
    "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_DefensiveData.lua",
    "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_AuraNameResolver.lua",
    "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_SpellIndicators.lua",
    "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua"
) | ForEach-Object { [IO.Path]::GetFullPath((Join-Path $root $_)) }
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
    foreach ($forbiddenPath in $forbiddenRetailAuraPaths) {
        if ([Array]::IndexOf($classicLoadOrder, $forbiddenPath) -ge 0) {
            throw "$classicManifestRelative transitively loads Retail aura runtime: $forbiddenPath"
        }
    }
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

function Test-AddonRelativePath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    foreach ($target in $targets) {
        if ($RelativePath.StartsWith($target.Folder + '/', [StringComparison]::Ordinal)) {
            return $true
        }
    }
    return $false
}

function Assert-NormalizedAddonPath {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or
        $RelativePath -cne $RelativePath.Trim() -or
        $RelativePath.Contains([char]92) -or
        $RelativePath.StartsWith('/') -or
        $RelativePath.EndsWith('/') -or
        $RelativePath.Contains('//') -or
        $RelativePath.IndexOfAny([char[]](0..31)) -ge 0 -or
        $RelativePath -match '(^|/)[.][.]?(?:/|$)' -or
        -not (Test-AddonRelativePath -RelativePath $RelativePath)) {
        throw "$Label is not a normalized path below an addon root: $RelativePath"
    }
}

function Assert-OrdinalPathOrder {
    param(
        # Empty is allowed: a manifest may legitimately hold no rows, as the
        # owned-shadow manifest does since the last shadow was collapsed.
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

function Convert-RetailPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    foreach ($target in $targets) {
        if ($RelativePath -ceq ($target.Folder + "/" + $target.Base + ".toc")) {
            return $target.Folder + "/" + $target.Base + "_Mainline.toc"
        }
    }
    return $RelativePath
}

$addonFolders = @($targets | ForEach-Object { $_.Folder })
$trackedAddonPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$trackedAddonPathResult = Invoke-GateGit -Arguments (@("-C", $root, "ls-files", "--") + $addonFolders)
if ($trackedAddonPathResult.ExitCode -ne 0) {
    throw "Unable to enumerate tracked Classic addon files: $($trackedAddonPathResult.Lines -join ', ')"
}
$trackedAddonPathLines = $trackedAddonPathResult.Lines
foreach ($trackedPath in $trackedAddonPathLines) {
    [void]$trackedAddonPaths.Add($trackedPath.Replace([char]92, [char]47))
}

$ownershipManifestRelative = "tools/classic-owned-addon-paths.txt"
$ownershipManifestPath = Join-Path $root $ownershipManifestRelative
if (-not (Test-Path -LiteralPath $ownershipManifestPath -PathType Leaf)) {
    throw "Classic ownership manifest is missing: $ownershipManifestRelative"
}
Assert-TrackedFile -RelativePath $ownershipManifestRelative -Label "Classic ownership manifest"
$ownedAddonPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$ownedAddonPathCase = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
$ownershipLines = [string[]][IO.File]::ReadAllLines($ownershipManifestPath)
if ($ownershipLines.Count -eq 0) { throw "Classic ownership manifest is empty" }
foreach ($ownedPath in $ownershipLines) {
    Assert-NormalizedAddonPath -RelativePath $ownedPath -Label "Classic ownership entry"
    if ($ownedAddonPathCase.ContainsKey($ownedPath)) {
        throw "Duplicate or case-colliding Classic ownership path: $($ownedAddonPathCase[$ownedPath]) versus $ownedPath"
    }
    if (-not $trackedAddonPaths.Contains($ownedPath)) {
        throw "Classic ownership entry must name a tracked addon file: $ownedPath"
    }
    $ownedFullPath = [IO.Path]::GetFullPath((Join-Path $root $ownedPath))
    if (-not (Test-Path -LiteralPath $ownedFullPath -PathType Leaf)) {
        throw "Classic-owned addon file is missing: $ownedPath"
    }
    $ownedAddonPathCase.Add($ownedPath, $ownedPath)
    [void]$ownedAddonPaths.Add($ownedPath)
}
Assert-OrdinalPathOrder -Paths $ownershipLines -Label "Classic ownership manifest"

$overrideManifestRelative = "tools/classic-retail-overrides.tsv"
$overrideManifestPath = Join-Path $root $overrideManifestRelative
if (-not (Test-Path -LiteralPath $overrideManifestPath -PathType Leaf)) {
    throw "Classic Retail override manifest is missing: $overrideManifestRelative"
}
Assert-TrackedFile -RelativePath $overrideManifestRelative -Label "Classic Retail override manifest"
$overrideBaseBlobs = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
$overridePathCase = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
$overrideLines = [string[]][IO.File]::ReadAllLines($overrideManifestPath)
if ($overrideLines.Count -eq 0) { throw "Classic Retail override manifest is empty" }
$overridePathsInOrder = [Collections.Generic.List[string]]::new()
foreach ($overrideLine in $overrideLines) {
    $fields = $overrideLine.Split([char]9)
    if ($fields.Count -ne 2) {
        throw "Classic Retail override entry must be path<TAB>Retail-base-blob: $overrideLine"
    }
    $overridePath = $fields[0]
    $baseBlob = $fields[1]
    Assert-NormalizedAddonPath -RelativePath $overridePath -Label "Classic Retail override entry"
    if ($baseBlob -cnotmatch '^[0-9a-f]{40}$') {
        throw "Classic Retail override base must be a lowercase SHA-1 Git blob: $overrideLine"
    }
    if ($overridePathCase.ContainsKey($overridePath)) {
        throw "Duplicate or case-colliding Classic Retail override path: $($overridePathCase[$overridePath]) versus $overridePath"
    }
    if ($ownedAddonPathCase.ContainsKey($overridePath)) {
        throw "Classic ownership and Retail override manifests must be disjoint: $overridePath"
    }
    if (-not $trackedAddonPaths.Contains($overridePath)) {
        throw "Classic Retail override entry must name a tracked addon file: $overridePath"
    }
    $overrideFullPath = [IO.Path]::GetFullPath((Join-Path $root $overridePath))
    if (-not (Test-Path -LiteralPath $overrideFullPath -PathType Leaf)) {
        throw "Classic Retail override file is missing: $overridePath"
    }
    $overridePathCase.Add($overridePath, $overridePath)
    $overrideBaseBlobs.Add($overridePath, $baseBlob)
    $overridePathsInOrder.Add($overridePath)
}
Assert-OrdinalPathOrder -Paths $overridePathsInOrder.ToArray() -Label "Classic Retail override manifest"

# O files that are whole-file shadows of a Retail file record that Retail
# counterpart and the Retail blob the shadow was last reconciled with. A
# malformed manifest fails here; drift against current Retail is reported in
# the reference block below.
$shadowManifestRelative = "tools/classic-owned-shadows.tsv"
$shadowManifestPath = Join-Path $root $shadowManifestRelative
if (-not (Test-Path -LiteralPath $shadowManifestPath -PathType Leaf)) {
    throw "Classic owned-shadow manifest is missing: $shadowManifestRelative"
}
Assert-TrackedFile -RelativePath $shadowManifestRelative -Label "Classic owned-shadow manifest"
$shadowBaseBlobs = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
$shadowRetailPaths = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
$shadowPathCase = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
# An empty manifest is the target state: the last shadow, the Classic Defaults
# file, was collapsed into State/MSUF_Defaults.lua on 2026-09-20. The rules
# below still run, so a shadow added later is validated the same way.
$shadowLines = [string[]][IO.File]::ReadAllLines($shadowManifestPath)
$shadowPathsInOrder = [Collections.Generic.List[string]]::new()
foreach ($shadowLine in $shadowLines) {
    $fields = $shadowLine.Split([char]9)
    if ($fields.Count -ne 3) {
        throw "Classic owned-shadow entry must be owned-path<TAB>Retail-path<TAB>Retail-base-blob: $shadowLine"
    }
    $shadowPath = $fields[0]
    $shadowRetailPath = $fields[1]
    $shadowBlob = $fields[2]
    Assert-NormalizedAddonPath -RelativePath $shadowPath -Label "Classic owned-shadow entry"
    Assert-NormalizedAddonPath -RelativePath $shadowRetailPath -Label "Classic owned-shadow Retail counterpart"
    if (-not $ownedAddonPaths.Contains($shadowPath)) {
        throw "Classic owned-shadow entry must be a declared Classic-owned path: $shadowPath"
    }
    if ($ownedAddonPathCase.ContainsKey($shadowRetailPath)) {
        throw "Classic owned-shadow Retail counterpart cannot itself be Classic-owned: $shadowRetailPath"
    }
    if ($shadowBlob -cnotmatch '^[0-9a-f]{40}$') {
        throw "Classic owned-shadow base must be a lowercase SHA-1 Git blob: $shadowLine"
    }
    if ($shadowPathCase.ContainsKey($shadowPath)) {
        throw "Duplicate or case-colliding Classic owned-shadow path: $($shadowPathCase[$shadowPath]) versus $shadowPath"
    }
    $shadowPathCase.Add($shadowPath, $shadowPath)
    $shadowBaseBlobs.Add($shadowPath, $shadowBlob)
    $shadowRetailPaths.Add($shadowPath, $shadowRetailPath)
    $shadowPathsInOrder.Add($shadowPath)
}
Assert-OrdinalPathOrder -Paths $shadowPathsInOrder.ToArray() -Label "Classic owned-shadow manifest"

if ($overrideBaseBlobs.Count -gt 0 -and -not $retailReferenceRootFull -and -not $SelfContained) {
    throw "Retail overrides require -RetailReferenceRoot so their recorded base blobs can be checked against current Retail Git HEAD"
}
if ($SelfContained) {
    $skippedSteps.Add("Retail parity, override base and owned-shadow drift checks (self-contained run)")
}

if ($retailReferenceRootFull) {
    $retailMappedPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $retailMappedSources = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    $retailMappedBlobs = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    $retailMappedPathOrder = [Collections.Generic.List[string]]::new()
    $retailExactCount = 0
    $retailOverrideCount = 0
    $retailOverrideDifferenceCount = 0
    $retailExactTocCount = 0
    $retailOverrideTocCount = 0

    $referenceGitRootResult = Invoke-GateGit -Arguments @("-C", $retailReferenceRootFull, "rev-parse", "--show-toplevel")
    if ($referenceGitRootResult.ExitCode -ne 0) { throw "Retail reference is not a Git checkout: $retailReferenceRootFull" }
    $referenceGitRootFull = [IO.Path]::GetFullPath(($referenceGitRootResult.Lines -join "").Trim()).TrimEnd([char]92, [char]47)
    $pathComparison = if ([IO.Path]::DirectorySeparatorChar -eq [char]92) {
        [StringComparison]::OrdinalIgnoreCase
    } else {
        [StringComparison]::Ordinal
    }
    if (-not $referenceGitRootFull.Equals($retailReferenceRootFull, $pathComparison)) {
        throw "RetailReferenceRoot must be the Git repository root: $retailReferenceRootFull"
    }
    $retailStatusResult = Invoke-GateGit -Arguments @("-C", $retailReferenceRootFull, "status", "--porcelain", "--untracked-files=all")
    if ($retailStatusResult.ExitCode -ne 0) { throw "Unable to inspect Retail reference status" }
    if ($retailStatusResult.Lines.Count -ne 0) {
        throw "Retail reference checkout must be clean so its load graph and Git HEAD describe the same source; git status reports: $($retailStatusResult.Lines -join ', ')"
    }

    $retailTreeResult = Invoke-GateGit -Arguments (@("-C", $retailReferenceRootFull, "ls-tree", "-r", "HEAD", "--") + $addonFolders)
    if ($retailTreeResult.ExitCode -ne 0) {
        throw "Unable to enumerate tracked Retail addon files: $($retailTreeResult.Lines -join ', ')"
    }
    $retailTreeLines = $retailTreeResult.Lines
    $retailMappedPathCase = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    $retailTocSources = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($treeLine in $retailTreeLines) {
        if ($treeLine -notmatch '^(\d+)\s+blob\s+([0-9a-f]+)\t(.+)$') {
            throw "Unexpected Retail Git tree entry: $treeLine"
        }
        if ($Matches[1] -cne '100644') {
            throw "Retail addon tree may contain only regular non-executable files: $treeLine"
        }
        $retailBlob = $Matches[2].ToLowerInvariant()
        $relativePath = $Matches[3].Replace([char]92, [char]47)
        Assert-NormalizedAddonPath -RelativePath $relativePath -Label "Retail Git tree entry"
        $candidateRelativePath = Convert-RetailPath -RelativePath $relativePath
        if ($retailMappedPathCase.ContainsKey($candidateRelativePath)) {
            throw "Retail mapping collision: $($retailMappedPathCase[$candidateRelativePath]) versus $relativePath at $candidateRelativePath"
        }
        $retailMappedPathCase.Add($candidateRelativePath, $relativePath)
        [void]$retailMappedPaths.Add($candidateRelativePath)
        $retailMappedSources.Add($candidateRelativePath, $relativePath)
        $retailMappedBlobs.Add($candidateRelativePath, $retailBlob)
        $retailMappedPathOrder.Add($candidateRelativePath)
        if ($relativePath.EndsWith('.toc', [StringComparison]::OrdinalIgnoreCase)) {
            [void]$retailTocSources.Add($relativePath)
        }
        $candidatePath = Join-Path $root $candidateRelativePath
        if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
            throw "Mapped Retail file is missing from Classic repository: $candidateRelativePath"
        }
    }

    $expectedRetailTocs = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($target in $targets) {
        [void]$expectedRetailTocs.Add($target.Folder + "/" + $target.Base + ".toc")
    }
    if (-not $retailTocSources.SetEquals($expectedRetailTocs)) {
        throw "Retail tree must contain exactly the three unsuffixed addon TOCs; found: $($retailTocSources -join ', ')"
    }

    foreach ($overridePath in $overrideBaseBlobs.Keys) {
        if (-not $retailMappedPaths.Contains($overridePath)) {
            throw "Classic Retail override path is not a mapped current Retail path: $overridePath"
        }
        $currentRetailBlob = $retailMappedBlobs[$overridePath]
        if ($currentRetailBlob -cne $overrideBaseBlobs[$overridePath]) {
            throw "Retail base changed for Classic override $overridePath`: recorded=$($overrideBaseBlobs[$overridePath]) current=$currentRetailBlob; manually rebase and review the override before updating the manifest"
        }
    }

    # Owned-shadow drift is report-only: Retail's sync workflow runs this gate,
    # and a hard failure would block every sync that touches a shadowed file.
    # The recorded blobs were taken on 2026-09-14 from Retail-Source ace807b7.
    # They mark where drift tracking starts; they do not certify that Retail
    # changes made before that commit were already ported into the shadows.
    $shadowDriftLines = [Collections.Generic.List[string]]::new()
    foreach ($shadowPath in $shadowPathsInOrder) {
        $shadowRetailPath = $shadowRetailPaths[$shadowPath]
        if (-not $retailMappedBlobs.ContainsKey($shadowRetailPath)) {
            $shadowDriftLines.Add("$shadowPath`: Retail counterpart $shadowRetailPath no longer exists; review the removal and update $shadowManifestRelative")
        } elseif ($retailMappedBlobs[$shadowRetailPath] -cne $shadowBaseBlobs[$shadowPath]) {
            $shadowDriftLines.Add("$shadowPath`: Retail counterpart $shadowRetailPath changed (recorded=$($shadowBaseBlobs[$shadowPath]) current=$($retailMappedBlobs[$shadowRetailPath])); port or consciously reject the delta, then update the recorded blob")
        }
    }

    $candidateBlobResult = Invoke-GateGitWithInput -Arguments @("-C", $root, "hash-object", "--stdin-paths") `
        -InputLines $retailMappedPathOrder.ToArray()
    $candidateBlobLines = $candidateBlobResult.Lines
    if ($candidateBlobResult.ExitCode -ne 0 -or $candidateBlobLines.Count -ne $retailMappedPathOrder.Count) {
        throw "Unable to hash every mapped Classic candidate: expected=$($retailMappedPathOrder.Count) actual=$($candidateBlobLines.Count); git said: $($candidateBlobLines -join ', ')"
    }
    for ($index = 0; $index -lt $retailMappedPathOrder.Count; $index++) {
        $candidateRelativePath = $retailMappedPathOrder[$index]
        $candidateBlob = $candidateBlobLines[$index].Trim().ToLowerInvariant()
        $retailBlob = $retailMappedBlobs[$candidateRelativePath]
        $isToc = $retailMappedSources[$candidateRelativePath].EndsWith('.toc', [StringComparison]::OrdinalIgnoreCase)
        if ($overrideBaseBlobs.ContainsKey($candidateRelativePath)) {
            $retailOverrideCount++
            if ($isToc) { $retailOverrideTocCount++ }
            if ($candidateBlob -cne $retailBlob) { $retailOverrideDifferenceCount++ }
        } else {
            if ($candidateBlob -cne $retailBlob) {
                throw "Mapped Retail path differs without an explicit Classic override: $candidateRelativePath"
            }
            $retailExactCount++
            if ($isToc) { $retailExactTocCount++ }
        }
    }
    foreach ($ownedPath in $ownedAddonPaths) {
        foreach ($retailPath in $retailMappedPaths) {
            if ($ownedPath.Equals($retailPath, [StringComparison]::OrdinalIgnoreCase) -or
                $ownedPath.StartsWith($retailPath + '/', [StringComparison]::OrdinalIgnoreCase) -or
                $retailPath.StartsWith($ownedPath + '/', [StringComparison]::OrdinalIgnoreCase)) {
                throw "Retail path collides with Classic ownership: $retailPath versus $ownedPath"
            }
        }
    }
    $expectedAddonPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($path in $retailMappedPaths) { [void]$expectedAddonPaths.Add($path) }
    foreach ($path in $ownedAddonPaths) { [void]$expectedAddonPaths.Add($path) }
    $actualAddonPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $actualAddonPathCase = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    $versionableResult = Invoke-GateGit -Arguments (@("-C", $root, "ls-files", "--cached", "--others", "--exclude-standard", "--") + $addonFolders)
    if ($versionableResult.ExitCode -ne 0) {
        throw "Unable to enumerate versionable Classic addon files: $($versionableResult.Lines -join ', ')"
    }
    $versionableAddonPaths = $versionableResult.Lines
    foreach ($relative in $versionableAddonPaths) {
        $relative = $relative.Replace([char]92, [char]47)
        Assert-NormalizedAddonPath -RelativePath $relative -Label "Classic addon inventory entry"
        if ($actualAddonPathCase.ContainsKey($relative)) {
            throw "Case-colliding Classic addon inventory paths: $($actualAddonPathCase[$relative]) versus $relative"
        }
        $fullPath = [IO.Path]::GetFullPath((Join-Path $root $relative))
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            $actualAddonPathCase.Add($relative, $relative)
            [void]$actualAddonPaths.Add($relative)
        }
    }
    if (-not $actualAddonPaths.SetEquals($expectedAddonPaths)) {
        $missing = [string[]]@($expectedAddonPaths | Where-Object { -not $actualAddonPaths.Contains($_) })
        $unexpected = [string[]]@($actualAddonPaths | Where-Object { -not $expectedAddonPaths.Contains($_) })
        [Array]::Sort($missing, [StringComparer]::Ordinal)
        [Array]::Sort($unexpected, [StringComparer]::Ordinal)
        throw "Classic addon inventory must equal mapped Retail union explicit Classic ownership. Missing=[$($missing -join ', ')] Unexpected=[$($unexpected -join ', ')]"
    }
    Write-Host "Retail exact paths: $retailExactCount mapped paths ($retailExactTocCount Mainline TOCs) match current Retail Git blobs byte-for-byte"
    Write-Host "Retail override paths: $retailOverrideCount mapped paths ($retailOverrideTocCount Mainline TOCs) are pinned to current Retail base blobs; $retailOverrideDifferenceCount currently differ"
    Write-Host "Classic-owned paths: $($ownedAddonPaths.Count) additive tracked files are declared"
    Write-Host "Classic-owned shadows: $($shadowBaseBlobs.Count) tracked; $($shadowDriftLines.Count) Retail counterparts changed since the recorded base"
    foreach ($shadowDriftLine in $shadowDriftLines) {
        Write-Host "    $shadowDriftLine"
    }
    Write-Host "Classic addon inventory: $($actualAddonPaths.Count) paths equal mapped Retail $($retailMappedPaths.Count) union owned $($ownedAddonPaths.Count)"
}

# Retail's load graph must never enter a Classic/Vanilla/Mists/TBC implementation
# directory. This is the mechanical 0.0-overhead gate: a Classic adapter that
# is merely guarded at runtime still fails because loading/parsing it on
# Mainline would already consume startup CPU and memory.
$mainlineTocPath = Join-Path $root "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_Mainline.toc"
$mainlineLoaded = @((Get-MsufLoadGraph -Path $mainlineTocPath -Duplicates Skip).AllPaths)
foreach ($path in $mainlineLoaded) {
    if ($path -match ('[\\/]Game[\\/]' + $classicDirectoryPattern + '[\\/]')) {
        throw "Retail zero-overhead violation: Mainline transitively loads $path"
    }
}

# Strong Mainline gate: preserve every Retail Lua path in order, permit content
# differences only for reviewed P entries, and permit additional Lua loads only
# for the declared shared/Arena additions in O. Client compatibility trees remain
# unreachable from Mainline.
function Get-CurrentLuaLoadPaths {
    param([Parameter(Mandatory = $true)][string]$TocPath)
    return [string[]]@((Get-MsufLoadGraph -Path $TocPath -Duplicates Skip).LuaPaths)
}

# One git process hashes every Lua file of a load graph. Per-file hash-object
# calls cost about 36 s of process start-up on a full run.
function Get-GitBlobHashes {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Paths,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if ($Paths.Count -eq 0) { return [string[]]@() }
    $hashed = Invoke-GateGitWithInput -Arguments @("-C", $root, "hash-object", "--stdin-paths") -InputLines $Paths
    if ($hashed.ExitCode -ne 0 -or $hashed.Lines.Count -ne $Paths.Count) {
        throw "Unable to hash the $Label load graph: expected=$($Paths.Count) actual=$($hashed.Lines.Count); git said: $($hashed.Lines -join ', ')"
    }
    return [string[]]@($hashed.Lines | ForEach-Object { $_.Trim() })
}

$retailParityTargets = @(
    @{
        Label = "Core"
        Reference = "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames.toc"
        Current = "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_Mainline.toc"
    },
    @{
        Label = "Options"
        Reference = "MidnightSimpleUnitFrames_Options/MidnightSimpleUnitFrames_Options.toc"
        Current = "MidnightSimpleUnitFrames_Options/MidnightSimpleUnitFrames_Options_Mainline.toc"
    },
    @{
        Label = "Assistant"
        Reference = "MidnightSimpleUnitFrames_Assistant/MidnightSimpleUnitFrames_Assistant.toc"
        Current = "MidnightSimpleUnitFrames_Assistant/MidnightSimpleUnitFrames_Assistant_Mainline.toc"
    }
)
$mainlineOwnedLuaExtras = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($extraPath in @(
    "MidnightSimpleUnitFrames/Game/Shared/Initialize.lua",
    "MidnightSimpleUnitFrames/Game/Shared/UnitFrames/MSUF_UF_PetHappiness.lua",
    "MidnightSimpleUnitFrames/Game/Shared/UnitFrames/MSUF_UF_ThreatText.lua",
    "MidnightSimpleUnitFrames/Game/Shared/ClassPower/MSUF_CP_TargetCombo.lua",
    "MidnightSimpleUnitFrames/Game/Forever/UnitFrames/MSUF_UF_CharacterNames.lua",
    "MidnightSimpleUnitFrames/Game/Forever/ClassPower.lua",
    "MidnightSimpleUnitFrames/State/MSUF_AuraDefaults.lua",
    "MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_Shell.lua",
    "MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_Bars.lua",
    "MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_Units.lua",
    "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_IconShape.lua",
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_ColorPicker.lua",
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme_Forever.lua",
    "MidnightSimpleUnitFrames/Castbars/MSUF_ArenaCastbars.lua",
    "MidnightSimpleUnitFrames/Castbars/MSUF_ArenaCastbars_Preview.lua",
    "MidnightSimpleUnitFrames/Features/Gameplay/MSUF_Feature_ArenaMatch.lua",
    "MidnightSimpleUnitFrames/Features/Gameplay/MSUF_Feature_ArenaTrinkets.lua",
    "MidnightSimpleUnitFrames/Game/Forever/Auras/AliasData/MSUF_Auras3_AliasData_Common.lua",
    "MidnightSimpleUnitFrames/Game/Forever/Auras/AliasData/MSUF_Auras3_AliasData_deDE.lua",
    "MidnightSimpleUnitFrames/Game/Forever/Auras/AliasData/MSUF_Auras3_AliasData_enUS.lua",
    "MidnightSimpleUnitFrames/Game/Forever/Auras/AliasData/MSUF_Auras3_AliasData_esES.lua",
    "MidnightSimpleUnitFrames/Game/Forever/Auras/AliasData/MSUF_Auras3_AliasData_esMX.lua",
    "MidnightSimpleUnitFrames/Game/Forever/Auras/AliasData/MSUF_Auras3_AliasData_frFR.lua",
    "MidnightSimpleUnitFrames/Game/Forever/Auras/AliasData/MSUF_Auras3_AliasData_itIT.lua",
    "MidnightSimpleUnitFrames/Game/Forever/Auras/AliasData/MSUF_Auras3_AliasData_koKR.lua",
    "MidnightSimpleUnitFrames/Game/Forever/Auras/AliasData/MSUF_Auras3_AliasData_ptBR.lua",
    "MidnightSimpleUnitFrames/Game/Forever/Auras/AliasData/MSUF_Auras3_AliasData_ruRU.lua",
    "MidnightSimpleUnitFrames/Game/Forever/Auras/AliasData/MSUF_Auras3_AliasData_zhCN.lua",
    "MidnightSimpleUnitFrames/Game/Forever/Auras/AliasData/MSUF_Auras3_AliasData_zhTW.lua",
    "MidnightSimpleUnitFrames/Game/Forever/Auras/MSUF_Auras3_ForeverData.lua"
)) {
    if (-not $ownedAddonPaths.Contains($extraPath)) {
        throw "Mainline shared/Arena addition must be declared in Classic ownership: $extraPath"
    }
    if ($overrideBaseBlobs.ContainsKey($extraPath)) {
        throw "Mainline shared/Arena addition cannot also be a Retail override: $extraPath"
    }
    [void]$mainlineOwnedLuaExtras.Add($extraPath)
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

$currentRetailHashCount = 0
$mainlineExactLuaCount = 0
$mainlineOverrideLuaCount = 0
$actualMainlineOwnedLuaExtras = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($parityTarget in $retailParityTargets) {
    $currentPaths = Get-CurrentLuaLoadPaths (Join-Path $root $parityTarget.Current)
    $currentRelativePaths = [Collections.Generic.List[string]]::new()
    foreach ($currentPath in $currentPaths) {
        $currentRelative = Get-RepositoryRelativePath -RepositoryFull $rootFull -FullPath $currentPath -Label "$($parityTarget.Label) Mainline path"
        if ($currentRelative -match ('(^|/)Game/' + $classicDirectoryPattern + '/') -or $currentRelative -match '_Classic[.]lua$') {
            throw "$($parityTarget.Label) Mainline loads a Classic-only blob: $currentRelative"
        }
        $currentRelativePaths.Add($currentRelative)
    }
    # Without a Retail reference there is nothing to compare the Mainline load
    # order against; the Classic-only blob check above still ran.
    if ($SelfContained) { continue }

    # A full run always has a named Retail reference: -RetailReferenceRoot is
    # required, so there is no HEAD fallback to compare against any more.
    # One walk produced the paths; one git process hashes them in the same
    # order and fails when it returns fewer blobs than the graph has files.
    $currentHashes = Get-GitBlobHashes -Paths $currentPaths -Label "$($parityTarget.Label) Mainline"
    $referencePaths = Get-CurrentLuaLoadPaths (Join-Path $retailReferenceRootFull $parityTarget.Reference)
    $referenceRelativePaths = [Collections.Generic.List[string]]::new()
    foreach ($referencePath in $referencePaths) {
        $referenceRelative = Get-RepositoryRelativePath -RepositoryFull $retailReferenceRootFull -FullPath $referencePath -Label "$($parityTarget.Label) Retail reference path"
        if (-not $retailMappedBlobs.ContainsKey($referenceRelative)) {
            throw "$($parityTarget.Label) Retail load path is outside the mapped Retail inventory: $referenceRelative"
        }
        $referenceRelativePaths.Add($referenceRelative)
    }

    $currentIndex = 0
    for ($referenceIndex = 0; $referenceIndex -lt $referenceRelativePaths.Count; $referenceIndex++) {
        $referenceRelative = $referenceRelativePaths[$referenceIndex]
        while ($currentIndex -lt $currentRelativePaths.Count -and
            $currentRelativePaths[$currentIndex] -cne $referenceRelative) {
            $extraPath = $currentRelativePaths[$currentIndex]
            if (-not $mainlineOwnedLuaExtras.Contains($extraPath)) {
                throw "$($parityTarget.Label) Mainline inserted or reordered an undeclared Lua path before Retail index $referenceIndex`: $extraPath"
            }
            if (-not $actualMainlineOwnedLuaExtras.Add($extraPath)) {
                throw "Mainline shared/Arena addition is loaded more than once across addon TOCs: $extraPath"
            }
            $currentIndex++
        }
        if ($currentIndex -ge $currentRelativePaths.Count) {
            throw "$($parityTarget.Label) Mainline omitted Retail Lua path at index $referenceIndex`: $referenceRelative"
        }
        $currentBlob = $currentHashes[$currentIndex].Trim().ToLowerInvariant()
        $referenceBlob = $retailMappedBlobs[$referenceRelative]
        if ($currentBlob -cne $referenceBlob -and -not $overrideBaseBlobs.ContainsKey($referenceRelative)) {
            throw "$($parityTarget.Label) Mainline Lua blob differs without a P override at Retail index $referenceIndex`: $referenceRelative"
        }
        if ($overrideBaseBlobs.ContainsKey($referenceRelative)) {
            $mainlineOverrideLuaCount++
        } else {
            $mainlineExactLuaCount++
        }
        $currentIndex++
    }
    while ($currentIndex -lt $currentRelativePaths.Count) {
        $extraPath = $currentRelativePaths[$currentIndex]
        if (-not $mainlineOwnedLuaExtras.Contains($extraPath)) {
            throw "$($parityTarget.Label) Mainline appends an undeclared Lua path: $extraPath"
        }
        if (-not $actualMainlineOwnedLuaExtras.Add($extraPath)) {
            throw "Mainline shared/Arena addition is loaded more than once across addon TOCs: $extraPath"
        }
        $currentIndex++
    }
    $currentRetailHashCount += $referenceRelativePaths.Count
}
if (-not $SelfContained -and -not $actualMainlineOwnedLuaExtras.SetEquals($mainlineOwnedLuaExtras)) {
    $missingMainlineOwned = [string[]]@($mainlineOwnedLuaExtras | Where-Object { -not $actualMainlineOwnedLuaExtras.Contains($_) })
    [Array]::Sort($missingMainlineOwned, [StringComparer]::Ordinal)
    throw "Mainline must load exactly the declared shared/Arena additions; missing=[$($missingMainlineOwned -join ', ')]"
}

# Flavor load coverage. Every Lua file the Mainline core and Options TOCs load
# must, on each Classic flavor in the client matrix, be loaded, be replaced by a
# loaded owned shadow (tools/classic-owned-shadows.tsv), or be excluded with a
# reason in tools/classic-flavor-load-exclusions.tsv. A Lua file Retail adds to
# a manifest Classic copies therefore cannot go missing on Classic unnoticed.
# Every exclusion row must still be needed. The Assistant addon is not covered.
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
$shadowsByRetailPath = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
foreach ($shadowPath in $shadowPathsInOrder) {
    $shadowRetailPath = $shadowRetailPaths[$shadowPath]
    if (-not $shadowsByRetailPath.ContainsKey($shadowRetailPath)) {
        $shadowsByRetailPath.Add($shadowRetailPath, [Collections.Generic.List[string]]::new())
    }
    $shadowsByRetailPath[$shadowRetailPath].Add($shadowPath)
}

$flavorExclusionLines = [string[]][IO.File]::ReadAllLines($flavorExclusionPath)
if ($flavorExclusionLines.Count -eq 0 -or $flavorExclusionLines[0] -cne "RetailPath`tFlavors`tReason") {
    throw "Classic flavor load exclusion manifest must start with the header RetailPath<TAB>Flavors<TAB>Reason"
}
$flavorExclusions = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
$flavorExclusionPathCase = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
$flavorExclusionPathsInOrder = [Collections.Generic.List[string]]::new()
for ($lineIndex = 1; $lineIndex -lt $flavorExclusionLines.Count; $lineIndex++) {
    $exclusionLine = $flavorExclusionLines[$lineIndex]
    $fields = $exclusionLine.Split([char]9)
    if ($fields.Count -ne 3) {
        throw "Classic flavor load exclusion must be RetailPath<TAB>Flavors<TAB>Reason: $exclusionLine"
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
$coverageReplacedCount = 0
$coverageExcludedCount = 0
foreach ($classicSuffix in $classicSuffixes) {
    $flavorLoaded = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($coveragePath in @(Get-FlavorLuaLoadPaths -Suffix $classicSuffix)) { [void]$flavorLoaded.Add($coveragePath) }
    foreach ($coveragePath in $mainlineCoveragePaths) {
        $isLoaded = $flavorLoaded.Contains($coveragePath)
        $isReplaced = $false
        if ($shadowsByRetailPath.ContainsKey($coveragePath)) {
            foreach ($shadowPath in $shadowsByRetailPath[$coveragePath]) {
                if ($flavorLoaded.Contains($shadowPath)) { $isReplaced = $true }
            }
        }
        $isExcluded = $flavorExclusions.ContainsKey($coveragePath) -and $flavorExclusions[$coveragePath].Contains($classicSuffix)
        if (($isLoaded -or $isReplaced) -and $isExcluded) {
            $coverageState = if ($isLoaded) { 'loads' } else { 'replaces' }
            throw "Stale Classic flavor load exclusion: $classicSuffix $coverageState $coveragePath; drop $classicSuffix from its row in $flavorExclusionRelative"
        }
        if ($isLoaded) {
            $coverageLoadedCount++
        } elseif ($isReplaced) {
            $coverageReplacedCount++
        } elseif ($isExcluded) {
            $coverageExcludedCount++
        } else {
            throw "Classic flavor load coverage: $classicSuffix neither loads nor replaces Mainline Lua $coveragePath; load it from the $classicSuffix manifests, declare its owned shadow in $shadowManifestRelative, or add a row with a reason to $flavorExclusionRelative"
        }
    }
}
Write-Host "Classic flavor load coverage: $($mainlineCoveragePaths.Count) Mainline Lua paths x $($classicSuffixes.Count) flavors; $coverageLoadedCount loaded, $coverageReplacedCount replaced, $coverageExcludedCount excluded with reason"

$classicAuraPath = Join-Path $root "MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua"
$classicAuraSource = Get-Content -LiteralPath $classicAuraPath -Raw
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

# Lua 5.1 compiles at most 200 locals and 60 upvalues per function. The gate
# holds every file this repository writes or overrides to 190 main-chunk locals
# and 56 upvalues, so a file reports before it reaches the ceiling rather than
# after a sync makes it uncompilable. Files already over the rule are listed
# below with a reason and are pinned to the value they have today.
$luaLocalBudget = 190
$luaUpvalueBudget = 56
$luaBudgetExceptions = [ordered]@{
    "MidnightSimpleUnitFrames/Shell/UI/EditMode/MSUF_EditMode_HUD.lua" = @{
        Locals = 4; Upvalues = 60
        Reason = "Retail override at Lua 5.1's 60-upvalue ceiling; the headroom is Retail's to reclaim, and this repository must not diverge further"
    }
    "MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_Assistant.lua" = @{
        Locals = 200; Upvalues = 30
        Reason = "Retail override at Lua 5.1's 200-local ceiling; splitting it belongs to the Retail Assistant, not to a Classic override"
    }
    "MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantParser.lua" = @{
        Locals = 196; Upvalues = 27
        Reason = "Retail override 4 locals below the ceiling; the split belongs to the Retail Assistant"
    }
    "MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantParser_Registry.lua" = @{
        Locals = 200; Upvalues = 16
        Reason = "Retail override at Lua 5.1's 200-local ceiling; the split belongs to the Retail Assistant"
    }
}

# luac takes a file list, so the syntax check and the budget listing each cost
# one process per argument-length chunk instead of one process per file.
function Invoke-LuacBatch {
    param(
        [Parameter(Mandatory = $true)][string]$LuacPath,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Files,
        [switch]$Listing
    )
    $stats = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
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
        $options = @("-p")
        if ($Listing) { $options = @("-l", "-p") }
        $startInfo.Arguments = (@($options) + @($chunk | ForEach-Object { '"' + $_ + '"' })) -join ' '
        $process = [Diagnostics.Process]::Start($startInfo)
        $currentFile = $null
        while ($null -ne ($line = $process.StandardOutput.ReadLine())) {
            if (-not $Listing) { continue }
            if ($line.StartsWith("main <", [StringComparison]::Ordinal)) {
                # luac wraps several files in a synthetic "(luac)" main chunk.
                $close = $line.IndexOf(":0,0>", [StringComparison]::Ordinal)
                $candidate = if ($close -gt 6) { $line.Substring(6, $close - 6) } else { "" }
                $currentFile = if ($candidate -ceq "(luac)" -or $candidate -ceq "") { $null } else { $candidate }
                if ($currentFile) { $stats[$currentFile] = [pscustomobject]@{ MainLocals = -1; MaxUpvalues = 0 } }
                continue
            }
            if ($null -eq $currentFile) { continue }
            if ($line -match '^(\d+)\+? params, (\d+) slots, (\d+) upvalues, (\d+) locals') {
                $entry = $stats[$currentFile]
                if ($entry.MainLocals -lt 0) { $entry.MainLocals = [int]$Matches[4] }
                if ([int]$Matches[3] -gt $entry.MaxUpvalues) { $entry.MaxUpvalues = [int]$Matches[3] }
            }
        }
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            return [pscustomobject]@{ ExitCode = $process.ExitCode; Error = $stderr.Trim(); Chunk = [string[]]@($chunk); Stats = $stats }
        }
    }
    return [pscustomobject]@{ ExitCode = 0; Error = ""; Chunk = [string[]]@(); Stats = $stats }
}

# $luac and $lua were resolved and version-checked by the tool preflight; a
# missing tool was either fatal there or recorded as a skipped step.
if ($luac) {
    $luaFiles = foreach ($target in $targets) {
        Get-ChildItem -LiteralPath (Join-Path $root $target.Folder) -Recurse -Filter "*.lua" -File
    }
    $syntax = Invoke-LuacBatch -LuacPath $luac.Source -Files ([string[]]@($luaFiles | ForEach-Object { $_.FullName }))
    if ($syntax.ExitCode -ne 0) {
        # Name the file: re-run the failing chunk one file at a time.
        foreach ($file in $syntax.Chunk) {
            $single = Invoke-LuacBatch -LuacPath $luac.Source -Files @($file)
            if ($single.ExitCode -ne 0) { throw "Lua 5.1 syntax failed: $file`n$($single.Error)" }
        }
        throw "Lua 5.1 syntax failed in a batch that no single file reproduces: $($syntax.Error)"
    }
    Write-Host "Lua 5.1 syntax: $($luaFiles.Count) files passed"

    $budgetRelativePaths = [string[]]@(
        @($ownedAddonPaths) + @($overrideBaseBlobs.Keys) |
            Where-Object { $_.EndsWith(".lua", [StringComparison]::OrdinalIgnoreCase) } |
            Sort-Object -Unique
    )
    $budgetFullPaths = [string[]]@($budgetRelativePaths | ForEach-Object { [IO.Path]::GetFullPath((Join-Path $root $_)) })
    $budget = Invoke-LuacBatch -LuacPath $luac.Source -Files $budgetFullPaths -Listing
    if ($budget.ExitCode -ne 0) {
        throw "Lua 5.1 budget listing failed: $($budget.Error)"
    }
    foreach ($exceptionPath in $luaBudgetExceptions.Keys) {
        if ([Array]::IndexOf($budgetRelativePaths, $exceptionPath) -lt 0) {
            throw "Lua 5.1 budget exception names no Classic-owned or override Lua file: $exceptionPath"
        }
    }
    $budgetMeasured = [Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $budgetRelativePaths.Count; $index++) {
        $relativePath = $budgetRelativePaths[$index]
        if (-not $budget.Stats.ContainsKey($budgetFullPaths[$index])) {
            throw "Lua 5.1 budget: main-chunk header not found for $relativePath"
        }
        $measured = $budget.Stats[$budgetFullPaths[$index]]
        if ($measured.MainLocals -lt 0) {
            throw "Lua 5.1 budget: main-chunk header not found for $relativePath"
        }
        $localCeiling = $luaLocalBudget
        $upvalueCeiling = $luaUpvalueBudget
        $exception = $null
        if ($luaBudgetExceptions.Contains($relativePath)) {
            $exception = $luaBudgetExceptions[$relativePath]
            $localCeiling = [Math]::Max($luaLocalBudget, [int]$exception.Locals)
            $upvalueCeiling = [Math]::Max($luaUpvalueBudget, [int]$exception.Upvalues)
        }
        if ($measured.MainLocals -gt $localCeiling) {
            $why = if ($exception) { " (recorded exception: $($exception.Reason))" } else { "" }
            throw "Lua 5.1 local budget exceeded: $relativePath has $($measured.MainLocals) main-chunk locals; budget $localCeiling of Lua's 200$why"
        }
        if ($measured.MaxUpvalues -gt $upvalueCeiling) {
            $why = if ($exception) { " (recorded exception: $($exception.Reason))" } else { "" }
            throw "Lua 5.1 upvalue budget exceeded: $relativePath has a function with $($measured.MaxUpvalues) upvalues; budget $upvalueCeiling of Lua's 60$why"
        }
        $budgetMeasured.Add([pscustomobject]@{
            Path = $relativePath
            MainLocals = $measured.MainLocals
            MaxUpvalues = $measured.MaxUpvalues
            IsException = [bool]$exception
        })
    }
    Write-Host "Lua 5.1 budgets: $($budgetRelativePaths.Count) Classic-owned and override files within $luaLocalBudget main-chunk locals and $luaUpvalueBudget upvalues; $($luaBudgetExceptions.Count) recorded exceptions"
    foreach ($offender in @($budgetMeasured | Sort-Object -Property MainLocals -Descending | Select-Object -First 5)) {
        $mark = if ($offender.IsException) { " [exception]" } else { "" }
        Write-Host "    locals  $($offender.MainLocals)/$luaLocalBudget $($offender.Path)$mark"
    }
    foreach ($offender in @($budgetMeasured | Sort-Object -Property MaxUpvalues -Descending | Select-Object -First 5)) {
        $mark = if ($offender.IsException) { " [exception]" } else { "" }
        Write-Host "    upvals  $($offender.MaxUpvalues)/$luaUpvalueBudget $($offender.Path)$mark"
    }
}

if ($lua) {
    # tools/classic-gate-smokes.tsv is the list; the plan above expanded it
    # over the client matrix. Its python rows run here too (see the error-path
    # check above). Invoke-GateSmoke records every smoke file it is about to
    # start, so the inventory check below still sees each one.
    $luaSmokeStopwatch = [Diagnostics.Stopwatch]::StartNew()
    Invoke-GateSmoke -Plan @($smokePlan)
    $luaSmokeStopwatch.Stop()
    if (-not $ListSmokes) {
        $invariant = [Globalization.CultureInfo]::InvariantCulture
        Write-Host ("Classic gate smokes: $($gateSmokeTimings.Count) invocations in " +
            $luaSmokeStopwatch.Elapsed.TotalSeconds.ToString("0.0", $invariant) +
            " s wall clock on $gateSmokeJobs worker(s); slowest:")
        foreach ($slowSmoke in @($gateSmokeTimings | Sort-Object -Property Seconds -Descending | Select-Object -First 10)) {
            Write-Host ("    " + $slowSmoke.Seconds.ToString("0.00", $invariant).PadLeft(6) + " s  " + $slowSmoke.Name)
        }
    }
}

# Every tracked smoke either ran through Invoke-GateSmoke above or is retired
# with a recorded reason, so no smoke silently rots.
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
    if ($ranSmokes.Contains($retiredSmoke)) {
        throw "Retired smoke still runs in the Classic gate: $retiredSmoke"
    }
}
foreach ($ranSmoke in $ranSmokes) {
    if (-not $trackedSmokes.Contains($ranSmoke)) {
        throw "The Classic gate ran an untracked smoke; track it with git add -f: $ranSmoke"
    }
}
# Without lua no Lua smoke ran; the preflight already recorded that skip. With
# -Only the run deliberately holds smokes back and records that as a skipped
# step, so the completeness half of the inventory cannot apply.
if ($lua -and [string]::IsNullOrWhiteSpace($Only)) {
    $unrunSmokes = [string[]]@($trackedSmokes | Where-Object { -not $ranSmokes.Contains($_) -and -not $retiredSmokes.Contains($_) })
    if ($unrunSmokes.Count -gt 0) {
        throw "Tracked smokes neither ran in the Classic gate nor are listed as retired: $($unrunSmokes -join ', ')"
    }
}
Write-Host "Smoke inventory: $($trackedSmokes.Count) tracked smokes; $($ranSmokes.Count) ran; $($retiredSmokes.Count) retired with a recorded reason"

if (-not $SelfContained -and $uiMirrorPresent) {
    & (Join-Path $root "tools/audit-classic-ui-source.ps1")
    if ($LASTEXITCODE -ne 0) { throw "Blizzard Classic source contract audit failed" }
}

Write-Host "Client TOCs: $($targets.Count * $clientMatrix.Count) manifests passed ($($clientSuffixes -join ', '))"
Write-Host "XML load graph: $($seenXml.Count) manifests resolved"
Write-Host "Mainline exact Lua: $mainlineExactLuaCount Retail paths retain order and Git blobs"
Write-Host "Mainline override Lua: $mainlineOverrideLuaCount Retail paths retain order with reviewed P blobs"
if (-not $SelfContained) {
    Write-Host "Mainline owned Lua: $($actualMainlineOwnedLuaExtras.Count) of $($mainlineOwnedLuaExtras.Count) declared O shared/Arena additions loaded; no Game/Classic load"
}
Write-Host "Retail zero-overhead load graph: $($mainlineLoaded.Count) core files, $currentRetailHashCount Retail Lua paths across Core/Options/Assistant validated against $retailReferenceLabel"
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
# A full run in CI has nothing to skip: the Retail reference and the Blizzard
# mirror are both cloned by the job. -RequireNoSkippedSteps makes that explicit,
# so a clone that lands in the wrong place cannot leave a green gate that quietly
# dropped the source audit or the Retail parity comparison. It runs after the
# smoke report so a broken smoke is still named first.
if ($RequireNoSkippedSteps -and $skippedSteps.Count -gt 0) {
    Pop-Location
    throw "The Classic gate skipped $($skippedSteps.Count) step(s) while -RequireNoSkippedSteps was set: $($skippedSteps -join '; ')"
}
Pop-Location
