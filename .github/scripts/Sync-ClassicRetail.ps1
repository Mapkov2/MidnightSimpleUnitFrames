[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RetailRoot,
    [Parameter(Mandatory = $true)][string]$ClassicRoot,
    [switch]$NoPush
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$targets = @(
    @{ Folder = "MidnightSimpleUnitFrames"; Base = "MidnightSimpleUnitFrames" },
    @{ Folder = "MidnightSimpleUnitFrames_Options"; Base = "MidnightSimpleUnitFrames_Options" },
    @{ Folder = "MidnightSimpleUnitFrames_Assistant"; Base = "MidnightSimpleUnitFrames_Assistant" }
)

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & git -C $Repository @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($exitCode -ne 0) {
        throw "git -C '$Repository' $($Arguments -join ' ') failed:`n$($output -join "`n")"
    }
    return (($output | Out-String).Trim())
}

function Get-GitLines {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $value = Invoke-Git -Repository $Repository -Arguments $Arguments
    if ([string]::IsNullOrWhiteSpace($value)) { return @() }
    return @($value -split "`r?`n")
}

function Convert-RetailPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $normalized = $RelativePath.Replace('\', '/')
    foreach ($target in $targets) {
        if ($normalized -eq "$($target.Folder)/$($target.Base).toc") {
            return "$($target.Folder)/$($target.Base)_Mainline.toc"
        }
    }
    return $normalized
}

function Resolve-ChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $parentFull = [IO.Path]::GetFullPath($Parent).TrimEnd('\', '/')
    $childFull = [IO.Path]::GetFullPath((Join-Path $parentFull $RelativePath))
    if (-not $childFull.StartsWith($parentFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escaped repository root: $childFull"
    }
    return $childFull
}

$RetailRoot = [IO.Path]::GetFullPath($RetailRoot).TrimEnd('\', '/')
$ClassicRoot = [IO.Path]::GetFullPath($ClassicRoot).TrimEnd('\', '/')

$retailTop = (Invoke-Git -Repository $RetailRoot -Arguments @("rev-parse", "--show-toplevel")).Replace('\', '/')
$classicTop = (Invoke-Git -Repository $ClassicRoot -Arguments @("rev-parse", "--show-toplevel")).Replace('\', '/')
if ($retailTop -ne $RetailRoot.Replace('\', '/')) { throw "RetailRoot is not a Git root: $RetailRoot" }
if ($classicTop -ne $ClassicRoot.Replace('\', '/')) { throw "ClassicRoot is not a Git root: $ClassicRoot" }
if ((Invoke-Git -Repository $ClassicRoot -Arguments @("branch", "--show-current")) -ne "classic") {
    throw "Classic checkout must be on branch 'classic'."
}
if (@(Get-GitLines -Repository $ClassicRoot -Arguments @("status", "--porcelain", "--untracked-files=all")).Count -ne 0) {
    throw "Classic checkout is dirty before synchronization."
}

$retailCommit = Invoke-Git -Repository $RetailRoot -Arguments @("rev-parse", "HEAD")
$retailShort = Invoke-Git -Repository $RetailRoot -Arguments @("rev-parse", "--short=8", "HEAD")
$classicHistory = Invoke-Git -Repository $ClassicRoot -Arguments @("log", "-100", "--format=%B%x00")
$baselineMatch = [regex]::Match($classicHistory, '(?im)^Retail-Source:\s*([0-9a-f]{40})\s*$')
if (-not $baselineMatch.Success) {
    throw "Classic history has no Retail-Source baseline; refusing stateless deletion sync."
}
$baselineCommit = $baselineMatch.Groups[1].Value.ToLowerInvariant()

& git -C $RetailRoot cat-file -e "$baselineCommit`^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Retail baseline $baselineCommit is unavailable in the Retail checkout."
}

$treeArguments = @(
    "ls-tree", "-r", "--name-only", $retailCommit, "--",
    $targets[0].Folder, $targets[1].Folder, $targets[2].Folder
)
$currentRetailPaths = @(Get-GitLines -Repository $RetailRoot -Arguments $treeArguments)
$currentMappedPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($relativePath in $currentRetailPaths) {
    [void]$currentMappedPaths.Add((Convert-RetailPath $relativePath))
}

$baselineTreeArguments = @(
    "ls-tree", "-r", "--name-only", $baselineCommit, "--",
    $targets[0].Folder, $targets[1].Folder, $targets[2].Folder
)
foreach ($previousPath in @(Get-GitLines -Repository $RetailRoot -Arguments $baselineTreeArguments)) {
    $mappedPrevious = Convert-RetailPath $previousPath
    if (-not $currentMappedPaths.Contains($mappedPrevious)) {
        $deletePath = Resolve-ChildPath -Parent $ClassicRoot -RelativePath $mappedPrevious
        if (Test-Path -LiteralPath $deletePath -PathType Leaf) {
            Remove-Item -LiteralPath $deletePath -Force
            Write-Host "Removed deleted Retail file: $mappedPrevious"
        }
    }
}

foreach ($relativePath in $currentRetailPaths) {
    $sourcePath = Resolve-ChildPath -Parent $RetailRoot -RelativePath $relativePath
    $mappedPath = Convert-RetailPath $relativePath
    $destinationPath = Resolve-ChildPath -Parent $ClassicRoot -RelativePath $mappedPath
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destinationPath) | Out-Null
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
}

$fileCount = 0
$tocCount = 0
foreach ($relativePath in $currentRetailPaths) {
    $sourcePath = Resolve-ChildPath -Parent $RetailRoot -RelativePath $relativePath
    $mappedPath = Convert-RetailPath $relativePath
    $destinationPath = Resolve-ChildPath -Parent $ClassicRoot -RelativePath $mappedPath
    if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
        throw "Canonical Retail file is missing after sync: $mappedPath"
    }
    if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash) {
        throw "Canonical Retail file differs after sync: $mappedPath"
    }
    if ($relativePath.EndsWith('.toc', [StringComparison]::OrdinalIgnoreCase)) {
        $tocCount++
    } else {
        $fileCount++
    }
}
if ($tocCount -ne 3) { throw "Expected exactly three Retail TOCs, found $tocCount." }
Write-Host "Canonical Retail parity passed: $fileCount files plus 3 Mainline TOCs match $retailCommit byte-for-byte."

$gatePath = Join-Path $ClassicRoot "tools/test-classic-prototype.ps1"
if (-not (Test-Path -LiteralPath $gatePath -PathType Leaf)) { throw "Classic gate is missing: $gatePath" }
$powerShellHost = (Get-Process -Id $PID).Path
Push-Location $ClassicRoot
try {
    & $powerShellHost -NoLogo -NoProfile -File $gatePath -RetailReferenceRoot $RetailRoot
    $gateExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
if ($gateExitCode -ne 0) { throw "Classic gate failed with exit code $gateExitCode." }

$diffCheck = & git -C $ClassicRoot diff --check 2>&1
if ($LASTEXITCODE -ne 0) { throw "git diff --check failed:`n$($diffCheck -join "`n")" }

[void](Invoke-Git -Repository $ClassicRoot -Arguments @(
    "add", "-A", "--", $targets[0].Folder, $targets[1].Folder, $targets[2].Folder
))
$stagedPaths = @(Get-GitLines -Repository $ClassicRoot -Arguments @("diff", "--cached", "--name-only"))
if ($stagedPaths.Count -eq 0) {
    Write-Host "No addon changes required; Classic already mirrors Retail $retailCommit."
    exit 0
}

foreach ($stagedPath in $stagedPaths) {
    $allowed = $false
    foreach ($target in $targets) {
        if ($stagedPath -eq $target.Folder -or $stagedPath.StartsWith($target.Folder + '/', [StringComparison]::Ordinal)) {
            $allowed = $true
            break
        }
    }
    if (-not $allowed) { throw "Refusing staged path outside addon roots: $stagedPath" }
}

$cachedCheck = & git -C $ClassicRoot diff --cached --check 2>&1
if ($LASTEXITCODE -ne 0) { throw "git diff --cached --check failed:`n$($cachedCheck -join "`n")" }

[void](Invoke-Git -Repository $ClassicRoot -Arguments @("config", "user.name", "github-actions[bot]"))
[void](Invoke-Git -Repository $ClassicRoot -Arguments @("config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com"))
[void](Invoke-Git -Repository $ClassicRoot -Arguments @(
    "commit", "-m", "sync(classic): mirror Retail main $retailShort",
    "-m", "Mirror canonical Retail files and Mainline TOCs byte-for-byte from main.`n`nRetail-Source: $retailCommit"
))

if ($NoPush) {
    Write-Host "Classic sync commit created; push skipped by -NoPush."
    exit 0
}

[void](Invoke-Git -Repository $ClassicRoot -Arguments @("push", "origin", "HEAD:classic"))
$remoteClassic = Invoke-Git -Repository $ClassicRoot -Arguments @("ls-remote", "origin", "refs/heads/classic")
$remoteHash = ($remoteClassic -split '\s+')[0]
$localHash = Invoke-Git -Repository $ClassicRoot -Arguments @("rev-parse", "HEAD")
if ($remoteHash -ne $localHash) { throw "Push verification failed: local HEAD differs from origin/classic." }
Write-Host "Sync complete: Classic $localHash mirrors Retail $retailCommit."
