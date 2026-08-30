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
$ownershipManifestRelative = "tools/classic-owned-addon-paths.txt"
$overrideManifestRelative = "tools/classic-retail-overrides.tsv"
$fileSystemPathComparison = if ([IO.Path]::DirectorySeparatorChar -eq '\') {
    [StringComparison]::OrdinalIgnoreCase
} else {
    [StringComparison]::Ordinal
}

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

function Test-GitAncestor {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$Ancestor,
        [Parameter(Mandatory = $true)][string]$Descendant
    )

    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & git -C $Repository merge-base --is-ancestor $Ancestor $Descendant 2>$null
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($exitCode -eq 0) { return $true }
    if ($exitCode -eq 1) { return $false }
    throw "Unable to test whether Retail baseline $Ancestor is an ancestor of $Descendant."
}

function Convert-RetailPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $normalized = $RelativePath.Replace('\', '/')
    foreach ($target in $targets) {
        if ($normalized -ceq "$($target.Folder)/$($target.Base).toc") {
            return "$($target.Folder)/$($target.Base)_Mainline.toc"
        }
    }
    return $normalized
}

function Test-AddonPath {
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
        $RelativePath.Contains('\') -or
        $RelativePath.StartsWith('/') -or
        $RelativePath.EndsWith('/') -or
        $RelativePath.Contains('//') -or
        $RelativePath -match '(^|/)\.\.?(?:/|$)' -or
        -not (Test-AddonPath $RelativePath)) {
        throw "$Label is not a normalized file path below an addon root: $RelativePath"
    }
}

function Resolve-ChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $parentFull = [IO.Path]::GetFullPath($Parent).TrimEnd('\', '/')
    $childFull = [IO.Path]::GetFullPath((Join-Path $parentFull $RelativePath))
    if (-not $childFull.StartsWith($parentFull + [IO.Path]::DirectorySeparatorChar, $fileSystemPathComparison)) {
        throw "Path escaped repository root: $childFull"
    }
    return $childFull
}

function Get-TreeBlobMap {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$Commit
    )

    $arguments = @(
        "ls-tree", "-r", $Commit, "--",
        $targets[0].Folder, $targets[1].Folder, $targets[2].Folder
    )
    $result = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    $caseMap = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($line in @(Get-GitLines -Repository $Repository -Arguments $arguments)) {
        if ($line -notmatch '^(\d+)\s+blob\s+([0-9a-f]+)\t(.+)$') {
            throw "Unexpected Git tree entry at $Commit`: $line"
        }
        $mode = $Matches[1]
        $blob = $Matches[2].ToLowerInvariant()
        $path = $Matches[3].Replace('\', '/')
        if ($mode -cne "100644") {
            throw "Addon trees may contain only regular non-executable files; found mode $mode at $Commit`:$path"
        }
        Assert-NormalizedAddonPath -RelativePath $path -Label "Git tree entry"
        if ($caseMap.ContainsKey($path)) {
            throw "Case-insensitive addon path collision at $Commit`: $($caseMap[$path]) versus $path"
        }
        $caseMap.Add($path, $path)
        $result.Add($path, $blob)
    }
    return $result
}

function Get-RetailTreeState {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$Commit
    )

    $sourceBlobs = Get-TreeBlobMap -Repository $Repository -Commit $Commit
    $mappedBlobs = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    $mappedSources = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    $mappedCase = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    $tocSources = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

    foreach ($sourcePath in $sourceBlobs.Keys) {
        $mappedPath = Convert-RetailPath $sourcePath
        Assert-NormalizedAddonPath -RelativePath $mappedPath -Label "Mapped Retail path"
        if ($mappedCase.ContainsKey($mappedPath)) {
            throw "Retail path mapping is not injective at $Commit`: $($mappedCase[$mappedPath]) and $sourcePath both map to $mappedPath"
        }
        $mappedCase.Add($mappedPath, $sourcePath)
        $mappedBlobs.Add($mappedPath, $sourceBlobs[$sourcePath])
        $mappedSources.Add($mappedPath, $sourcePath)
        if ($sourcePath.EndsWith('.toc', [StringComparison]::OrdinalIgnoreCase)) {
            [void]$tocSources.Add($sourcePath)
        }
    }

    $expectedTocs = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($target in $targets) {
        [void]$expectedTocs.Add("$($target.Folder)/$($target.Base).toc")
    }
    if (-not $tocSources.SetEquals($expectedTocs)) {
        throw "Retail tree $Commit must contain exactly the three expected unsuffixed Retail TOCs; found: $($tocSources -join ', ')"
    }

    return [pscustomobject]@{
        SourceBlobs = $sourceBlobs
        MappedBlobs = $mappedBlobs
        MappedSources = $mappedSources
    }
}

function Read-OwnershipManifest {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][Collections.Generic.Dictionary[string, string]]$ClassicTree
    )

    $manifestPath = Resolve-ChildPath -Parent $Repository -RelativePath $ownershipManifestRelative
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Classic ownership manifest is missing: $ownershipManifestRelative"
    }
    [void](Invoke-Git -Repository $Repository -Arguments @("ls-files", "--error-unmatch", "--", $ownershipManifestRelative))

    $lines = @([IO.File]::ReadAllLines($manifestPath))
    if ($lines.Count -eq 0) { throw "Classic ownership manifest is empty: $ownershipManifestRelative" }

    $owned = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $ownedCase = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $lines) {
        Assert-NormalizedAddonPath -RelativePath $path -Label "Classic ownership entry"
        if ($ownedCase.ContainsKey($path)) {
            throw "Duplicate or case-colliding Classic ownership entry: $($ownedCase[$path]) versus $path"
        }
        if (-not $ClassicTree.ContainsKey($path)) {
            throw "Classic ownership entry is not a tracked file in Classic HEAD: $path"
        }
        $ownedCase.Add($path, $path)
        [void]$owned.Add($path)
    }

    $sorted = [string[]]$lines.Clone()
    [Array]::Sort($sorted, [StringComparer]::Ordinal)
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -cne $sorted[$index]) {
            throw "Classic ownership manifest must be sorted with ordinal path ordering."
        }
    }
    return ,$owned
}

function Read-OverrideManifest {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][Collections.Generic.Dictionary[string, string]]$ClassicTree,
        [Parameter(Mandatory = $true)][Collections.Generic.Dictionary[string, string]]$CurrentRetailBlobs
    )

    $manifestPath = Resolve-ChildPath -Parent $Repository -RelativePath $overrideManifestRelative
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Classic Retail-override manifest is missing: $overrideManifestRelative"
    }
    [void](Invoke-Git -Repository $Repository -Arguments @("ls-files", "--error-unmatch", "--", $overrideManifestRelative))

    $lines = @([IO.File]::ReadAllLines($manifestPath))
    $overrides = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    $overrideCase = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    $expectedBlobLength = 0
    foreach ($blob in $CurrentRetailBlobs.Values) {
        $expectedBlobLength = $blob.Length
        break
    }
    if ($expectedBlobLength -eq 0) {
        throw "Current Retail addon tree is empty; cannot validate Classic Retail overrides."
    }

    foreach ($line in $lines) {
        if ([regex]::Matches($line, "`t").Count -ne 1) {
            throw "Classic Retail-override entry must contain exactly one TAB: $line"
        }
        $separator = $line.IndexOf("`t", [StringComparison]::Ordinal)
        $path = $line.Substring(0, $separator)
        $baseBlob = $line.Substring($separator + 1)
        Assert-NormalizedAddonPath -RelativePath $path -Label "Classic Retail-override entry"
        if ($baseBlob.Length -ne $expectedBlobLength -or $baseBlob -cnotmatch '^[0-9a-f]+$') {
            throw "Classic Retail-override base blob must be a lower-case Git object ID: $line"
        }
        if ($overrideCase.ContainsKey($path)) {
            throw "Duplicate or case-colliding Classic Retail-override entry: $($overrideCase[$path]) versus $path"
        }
        if (-not $ClassicTree.ContainsKey($path)) {
            throw "Classic Retail-override entry is not a tracked file in Classic HEAD: $path"
        }
        if (-not $CurrentRetailBlobs.ContainsKey($path)) {
            throw "Classic Retail-override entry is not an exact current Retail path: $path"
        }
        if ($CurrentRetailBlobs[$path] -cne $baseBlob) {
            throw "Retail changed a Classic override since its recorded base: $path (recorded $baseBlob, current $($CurrentRetailBlobs[$path]))"
        }
        $overrideCase.Add($path, $path)
        $overrides.Add($path, $baseBlob)
    }

    $sorted = [string[]]$lines.Clone()
    [Array]::Sort($sorted, [StringComparer]::Ordinal)
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -cne $sorted[$index]) {
            throw "Classic Retail-override manifest must be sorted with ordinal path ordering."
        }
    }
    return ,$overrides
}

function Test-PathCollision {
    param(
        [Parameter(Mandatory = $true)][string]$Left,
        [Parameter(Mandatory = $true)][string]$Right
    )

    return $Left.Equals($Right, [StringComparison]::OrdinalIgnoreCase) -or
        $Left.StartsWith($Right + '/', [StringComparison]::OrdinalIgnoreCase) -or
        $Right.StartsWith($Left + '/', [StringComparison]::OrdinalIgnoreCase)
}

function Get-FileHashes {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][Collections.Generic.HashSet[string]]$Paths
    )

    $hashes = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    foreach ($path in $Paths) {
        $fullPath = Resolve-ChildPath -Parent $Repository -RelativePath $path
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw "Protected Classic file is missing from the working tree: $path"
        }
        $hashes.Add($path, (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash)
    }
    return $hashes
}

function Assert-FileHashes {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][Collections.Generic.Dictionary[string, string]]$Expected,
        [Parameter(Mandatory = $true)][string]$Phase
    )

    foreach ($path in $Expected.Keys) {
        $fullPath = Resolve-ChildPath -Parent $Repository -RelativePath $path
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw "Protected Classic file disappeared $Phase`: $path"
        }
        $actual = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash
        if ($actual -cne $Expected[$path]) {
            throw "Protected Classic file changed $Phase`: $path"
        }
    }
}

function Assert-CanonicalParity {
    param(
        [Parameter(Mandatory = $true)][string]$RetailRepository,
        [Parameter(Mandatory = $true)][string]$ClassicRepository,
        [Parameter(Mandatory = $true)]$RetailState,
        [Parameter(Mandatory = $true)][Collections.Generic.Dictionary[string, string]]$OverridePaths,
        [Parameter(Mandatory = $true)][string]$Phase
    )

    $fileCount = 0
    $tocCount = 0
    foreach ($mappedPath in $RetailState.MappedSources.Keys) {
        if ($OverridePaths.ContainsKey($mappedPath)) { continue }
        $sourcePath = Resolve-ChildPath -Parent $RetailRepository -RelativePath $RetailState.MappedSources[$mappedPath]
        $destinationPath = Resolve-ChildPath -Parent $ClassicRepository -RelativePath $mappedPath
        if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
            throw "Canonical Retail file is missing $Phase`: $mappedPath"
        }
        if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -cne
            (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash) {
            throw "Canonical Retail file differs $Phase`: $mappedPath"
        }
        if ($RetailState.MappedSources[$mappedPath].EndsWith('.toc', [StringComparison]::OrdinalIgnoreCase)) {
            $tocCount++
        } else {
            $fileCount++
        }
    }
    Write-Host "Canonical Retail parity $Phase`: $fileCount files plus $tocCount Mainline TOCs match byte-for-byte; $($OverridePaths.Count) explicit Classic overrides were excluded."
}

$RetailRoot = [IO.Path]::GetFullPath($RetailRoot).TrimEnd('\', '/')
$ClassicRoot = [IO.Path]::GetFullPath($ClassicRoot).TrimEnd('\', '/')

$retailTop = (Invoke-Git -Repository $RetailRoot -Arguments @("rev-parse", "--show-toplevel")).Replace('\', '/')
$classicTop = (Invoke-Git -Repository $ClassicRoot -Arguments @("rev-parse", "--show-toplevel")).Replace('\', '/')
if (-not $retailTop.Equals($RetailRoot.Replace('\', '/'), $fileSystemPathComparison)) { throw "RetailRoot is not a Git root: $RetailRoot" }
if (-not $classicTop.Equals($ClassicRoot.Replace('\', '/'), $fileSystemPathComparison)) { throw "ClassicRoot is not a Git root: $ClassicRoot" }
if ((Invoke-Git -Repository $ClassicRoot -Arguments @("branch", "--show-current")) -cne "classic") {
    throw "Classic checkout must be on branch 'classic'."
}
if (@(Get-GitLines -Repository $RetailRoot -Arguments @("status", "--porcelain", "--untracked-files=all")).Count -ne 0) {
    throw "Retail checkout is dirty before synchronization."
}
if (@(Get-GitLines -Repository $ClassicRoot -Arguments @("status", "--porcelain", "--untracked-files=all")).Count -ne 0) {
    throw "Classic checkout is dirty before synchronization."
}

$retailCommit = Invoke-Git -Repository $RetailRoot -Arguments @("rev-parse", "HEAD")
$retailShort = Invoke-Git -Repository $RetailRoot -Arguments @("rev-parse", "--short=8", "HEAD")
if (-not $NoPush) {
    $originMain = Invoke-Git -Repository $RetailRoot -Arguments @("rev-parse", "--verify", "refs/remotes/origin/main")
    if ($originMain -cne $retailCommit) {
        throw "Push-capable sync requires Retail HEAD to equal origin/main exactly: HEAD=$retailCommit origin/main=$originMain"
    }
}
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
if (-not (Test-GitAncestor -Repository $RetailRoot -Ancestor $baselineCommit -Descendant $retailCommit)) {
    throw "Retail baseline $baselineCommit is not an ancestor of current Retail $retailCommit; refusing a stale or divergent sync."
}

$baselineState = Get-RetailTreeState -Repository $RetailRoot -Commit $baselineCommit
$currentState = Get-RetailTreeState -Repository $RetailRoot -Commit $retailCommit
$classicTree = Get-TreeBlobMap -Repository $ClassicRoot -Commit "HEAD"
$ownedPaths = Read-OwnershipManifest -Repository $ClassicRoot -ClassicTree $classicTree
$overridePaths = Read-OverrideManifest -Repository $ClassicRoot -ClassicTree $classicTree `
    -CurrentRetailBlobs $currentState.MappedBlobs

# O is additive Classic ownership and P is the explicit Classic override set.
# The two manifests may not overlap structurally or by case.
foreach ($ownedPath in $ownedPaths) {
    foreach ($overridePath in $overridePaths.Keys) {
        if (Test-PathCollision -Left $ownedPath -Right $overridePath) {
            throw "Classic ownership and Retail-override manifests collide: $ownedPath versus $overridePath"
        }
    }
}

# Additive ownership is never a Retail parity exception. Any exact, case-only,
# or file/directory collision with current Retail requires an explicit refactor.
foreach ($ownedPath in $ownedPaths) {
    foreach ($retailPath in $currentState.MappedBlobs.Keys) {
        if (Test-PathCollision -Left $ownedPath -Right $retailPath) {
            throw "Current Retail path collides with Classic ownership: $retailPath versus $ownedPath"
        }
    }
}

# P must overlap current Retail only at its exact, case-sensitive file path.
# Read-OverrideManifest already proved that exact membership and base-blob
# equality; this loop rejects any additional structural collision explicitly.
foreach ($overridePath in $overridePaths.Keys) {
    foreach ($retailPath in $currentState.MappedBlobs.Keys) {
        if ($retailPath -ceq $overridePath) { continue }
        if (Test-PathCollision -Left $overridePath -Right $retailPath) {
            throw "Classic Retail override collides structurally with current Retail: $overridePath versus $retailPath"
        }
    }
}

# A path introduced by Retail since the recorded baseline must not silently
# claim an existing Classic path, even if somebody forgot to register that path.
foreach ($retailPath in $currentState.MappedBlobs.Keys) {
    if ($baselineState.MappedBlobs.ContainsKey($retailPath)) { continue }
    if ($overridePaths.ContainsKey($retailPath)) { continue }
    foreach ($classicPath in $classicTree.Keys) {
        if ($baselineState.MappedBlobs.ContainsKey($classicPath)) { continue }
        if (Test-PathCollision -Left $retailPath -Right $classicPath) {
            throw "New Retail path collides with a pre-existing Classic path: $retailPath versus $classicPath"
        }
    }
}

# Every additive Classic file must be declared. Conversely, every declaration
# must resolve to a tracked Classic file (checked while reading the manifest).
foreach ($classicPath in $classicTree.Keys) {
    if (-not $baselineState.MappedBlobs.ContainsKey($classicPath) -and
        -not $currentState.MappedBlobs.ContainsKey($classicPath) -and
        -not $ownedPaths.Contains($classicPath)) {
        throw "Tracked Classic addon path is neither Retail-owned nor declared Classic-owned: $classicPath"
    }
}

# Prove the previous sync boundary before any mutation. A Classic-only commit is
# never allowed to edit or delete a Retail-owned baseline blob behind the sync's
# back; that is the exact failure mode that previously erased Classic fixes.
foreach ($mappedPath in $baselineState.MappedBlobs.Keys) {
    if ($ownedPaths.Contains($mappedPath) -or $overridePaths.ContainsKey($mappedPath)) { continue }
    if (-not $classicTree.ContainsKey($mappedPath)) {
        throw "Classic deleted a Retail-owned baseline path outside declared Classic protection: $mappedPath"
    }
    if ($classicTree[$mappedPath] -cne $baselineState.MappedBlobs[$mappedPath]) {
        throw "Classic modified a Retail-owned baseline path outside declared Classic protection: $mappedPath"
    }
}

$deletedPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($mappedPath in $baselineState.MappedBlobs.Keys) {
    if (-not $currentState.MappedBlobs.ContainsKey($mappedPath) -and
        -not $ownedPaths.Contains($mappedPath) -and
        -not $overridePaths.ContainsKey($mappedPath)) {
        [void]$deletedPaths.Add($mappedPath)
    }
}

$mirroredPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($mappedPath in $currentState.MappedBlobs.Keys) {
    if (-not $overridePaths.ContainsKey($mappedPath)) { [void]$mirroredPaths.Add($mappedPath) }
}
$preservedPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($ownedPath in $ownedPaths) { [void]$preservedPaths.Add($ownedPath) }
foreach ($overridePath in $overridePaths.Keys) { [void]$preservedPaths.Add($overridePath) }

# Validate file/directory transitions before deleting or copying anything. A
# current Retail file may replace a directory only when every leaf below that
# directory is a verified baseline deletion and no reparse point is involved.
foreach ($mappedPath in $mirroredPaths) {
    $destinationPath = Resolve-ChildPath -Parent $ClassicRoot -RelativePath $mappedPath
    if (-not (Test-Path -LiteralPath $destinationPath -PathType Container)) { continue }
    foreach ($item in @(Get-ChildItem -LiteralPath $destinationPath -Force -Recurse)) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Retail file would replace a Classic directory containing a reparse point: $mappedPath"
        }
        if ($item.PSIsContainer) { continue }
        $relativeLeaf = $item.FullName.Substring($ClassicRoot.Length + 1).Replace('\', '/')
        if (-not $deletedPaths.Contains($relativeLeaf)) {
            throw "Retail file would replace a Classic directory containing a non-deleted file: $mappedPath versus $relativeLeaf"
        }
    }
}

$gatePath = Join-Path $ClassicRoot "tools/test-classic-prototype.ps1"
if (-not (Test-Path -LiteralPath $gatePath -PathType Leaf)) { throw "Classic gate is missing: $gatePath" }
$powerShellHost = (Get-Process -Id $PID).Path
if ([string]::IsNullOrWhiteSpace($powerShellHost) -or -not (Test-Path -LiteralPath $powerShellHost -PathType Leaf)) {
    throw "Unable to resolve the PowerShell host for Classic validation."
}
foreach ($mappedPath in $mirroredPaths) {
    $sourcePath = Resolve-ChildPath -Parent $RetailRoot -RelativePath $currentState.MappedSources[$mappedPath]
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Tracked Retail source file is missing from the working tree before synchronization: $($currentState.MappedSources[$mappedPath])"
    }
}

$preservedHashes = Get-FileHashes -Repository $ClassicRoot -Paths $preservedPaths
foreach ($mappedPath in $deletedPaths) {
    $deletePath = Resolve-ChildPath -Parent $ClassicRoot -RelativePath $mappedPath
    if (Test-Path -LiteralPath $deletePath -PathType Leaf) {
        Remove-Item -LiteralPath $deletePath -Force
        Write-Host "Removed deleted Retail file: $mappedPath"
    }
}

foreach ($mappedPath in $mirroredPaths) {
    $sourcePath = Resolve-ChildPath -Parent $RetailRoot -RelativePath $currentState.MappedSources[$mappedPath]
    $destinationPath = Resolve-ChildPath -Parent $ClassicRoot -RelativePath $mappedPath
    if (Test-Path -LiteralPath $destinationPath -PathType Container) {
        $nestedDirectories = @(Get-ChildItem -LiteralPath $destinationPath -Force -Recurse -Directory |
            Sort-Object { $_.FullName.Length } -Descending)
        foreach ($directory in $nestedDirectories) {
            Remove-Item -LiteralPath $directory.FullName -Force
        }
        Remove-Item -LiteralPath $destinationPath -Force
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destinationPath) | Out-Null
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
}

Assert-FileHashes -Repository $ClassicRoot -Expected $preservedHashes -Phase "during Retail copy"
Assert-CanonicalParity -RetailRepository $RetailRoot -ClassicRepository $ClassicRoot -RetailState $currentState `
    -OverridePaths $overridePaths -Phase "after sync"

Push-Location $ClassicRoot
try {
    & $powerShellHost -NoLogo -NoProfile -File $gatePath -RetailReferenceRoot $RetailRoot
    $gateExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
if ($gateExitCode -ne 0) { throw "Classic gate failed with exit code $gateExitCode." }

Assert-FileHashes -Repository $ClassicRoot -Expected $preservedHashes -Phase "during Classic validation"
Assert-CanonicalParity -RetailRepository $RetailRoot -ClassicRepository $ClassicRoot -RetailState $currentState `
    -OverridePaths $overridePaths -Phase "after Classic validation"
[void](Invoke-Git -Repository $ClassicRoot -Arguments @("diff", "--check"))

# Validate the working-tree mutation set before touching the index. This also
# catches mode-only changes to O or P and gate mutations outside the addon sync.
$workingTrackedPaths = @(Get-GitLines -Repository $ClassicRoot -Arguments @("diff", "--name-only"))
foreach ($workingPath in $workingTrackedPaths) {
    if ($preservedPaths.Contains($workingPath)) {
        throw "Refusing working-tree mutation of a protected Classic path: $workingPath"
    }
    if (-not $mirroredPaths.Contains($workingPath) -and -not $deletedPaths.Contains($workingPath)) {
        throw "Refusing working-tree path outside the computed Retail mutation set: $workingPath"
    }
}
$workingUntrackedPaths = @(Get-GitLines -Repository $ClassicRoot -Arguments @("ls-files", "--others", "--exclude-standard"))
foreach ($workingPath in $workingUntrackedPaths) {
    if (-not $mirroredPaths.Contains($workingPath)) {
        throw "Refusing untracked path outside the computed Retail mutation set: $workingPath"
    }
}

[void](Invoke-Git -Repository $ClassicRoot -Arguments @(
    "add", "-A", "--", $targets[0].Folder, $targets[1].Folder, $targets[2].Folder
))
$stagedPaths = @(Get-GitLines -Repository $ClassicRoot -Arguments @("diff", "--cached", "--name-only"))
foreach ($stagedPath in $stagedPaths) {
    if ($preservedPaths.Contains($stagedPath)) {
        throw "Refusing staged mutation of a protected Classic path: $stagedPath"
    }
    if (-not $mirroredPaths.Contains($stagedPath) -and -not $deletedPaths.Contains($stagedPath)) {
        throw "Refusing staged path outside the computed Retail mutation set: $stagedPath"
    }
}

foreach ($mappedPath in $mirroredPaths) {
    $indexBlob = Invoke-Git -Repository $ClassicRoot -Arguments @("rev-parse", "--verify", ":$mappedPath")
    if ($indexBlob -cne $currentState.MappedBlobs[$mappedPath]) {
        throw "Canonical Retail index blob differs after staging: $mappedPath"
    }
}
foreach ($preservedPath in $preservedPaths) {
    $indexBlob = Invoke-Git -Repository $ClassicRoot -Arguments @("rev-parse", "--verify", ":$preservedPath")
    if ($indexBlob -cne $classicTree[$preservedPath]) {
        throw "Protected Classic index blob differs after staging: $preservedPath"
    }
}

$unstagedPaths = @(Get-GitLines -Repository $ClassicRoot -Arguments @("diff", "--name-only"))
if ($unstagedPaths.Count -ne 0) {
    throw "Classic validation left unstaged tracked changes: $($unstagedPaths -join ', ')"
}
$untrackedPaths = @(Get-GitLines -Repository $ClassicRoot -Arguments @("ls-files", "--others", "--exclude-standard"))
if ($untrackedPaths.Count -ne 0) {
    throw "Classic validation left untracked files: $($untrackedPaths -join ', ')"
}

$expectedFinalPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($path in $currentState.MappedBlobs.Keys) { [void]$expectedFinalPaths.Add($path) }
foreach ($path in $ownedPaths) { [void]$expectedFinalPaths.Add($path) }
$indexedFinalPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($path in @(Get-GitLines -Repository $ClassicRoot -Arguments @(
    "ls-files", "--", $targets[0].Folder, $targets[1].Folder, $targets[2].Folder
))) {
    [void]$indexedFinalPaths.Add($path.Replace('\', '/'))
}
if (-not $indexedFinalPaths.SetEquals($expectedFinalPaths)) {
    $missing = @($expectedFinalPaths | Where-Object { -not $indexedFinalPaths.Contains($_) })
    $unexpected = @($indexedFinalPaths | Where-Object { -not $expectedFinalPaths.Contains($_) })
    throw "Final Classic addon inventory differs from Retail plus declared ownership. Missing=[$($missing -join ', ')] Unexpected=[$($unexpected -join ', ')]"
}

if ($stagedPaths.Count -eq 0) {
    Write-Host "No addon changes required; $($mirroredPaths.Count) Retail paths already match $retailCommit, $($overridePaths.Count) explicit Classic overrides and $($ownedPaths.Count) additive Classic-owned files are preserved."
    exit 0
}

[void](Invoke-Git -Repository $ClassicRoot -Arguments @("diff", "--cached", "--check"))

[void](Invoke-Git -Repository $ClassicRoot -Arguments @("config", "user.name", "github-actions[bot]"))
[void](Invoke-Git -Repository $ClassicRoot -Arguments @("config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com"))
[void](Invoke-Git -Repository $ClassicRoot -Arguments @(
    "commit", "-m", "sync(classic): mirror Retail main $retailShort",
    "-m", "Mirror canonical Retail files and Mainline TOCs byte-for-byte from main while preserving additive Classic ownership and explicit Classic Retail overrides.`n`nRetail-Source: $retailCommit"
))

if ($NoPush) {
    Write-Host "Classic sync commit created; push skipped by -NoPush."
    exit 0
}

[void](Invoke-Git -Repository $ClassicRoot -Arguments @("push", "origin", "HEAD:classic"))
$remoteClassic = Invoke-Git -Repository $ClassicRoot -Arguments @("ls-remote", "origin", "refs/heads/classic")
$remoteHash = ($remoteClassic -split '\s+')[0]
$localHash = Invoke-Git -Repository $ClassicRoot -Arguments @("rev-parse", "HEAD")
if ($remoteHash -cne $localHash) { throw "Push verification failed: local HEAD differs from origin/classic." }
Write-Host "Sync complete: Classic $localHash mirrors $($mirroredPaths.Count) Retail paths from $retailCommit while preserving $($overridePaths.Count) explicit Classic overrides and $($ownedPaths.Count) additive Classic-owned files."
