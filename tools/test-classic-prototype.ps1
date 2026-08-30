[CmdletBinding()]
param(
    [string]$RetailReferenceRoot = ""
)

$ErrorActionPreference = "Stop"
$root = (git rev-parse --show-toplevel).Trim()
$rootFull = [IO.Path]::GetFullPath($root).TrimEnd('\', '/')

$retailReferenceRootFull = $null
if ([string]::IsNullOrWhiteSpace($RetailReferenceRoot)) {
    $candidate = Join-Path (Split-Path -Parent $rootFull) "MidnightSimpleUnitFrames"
    $candidateToc = Join-Path $candidate "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames.toc"
    if (Test-Path -LiteralPath $candidateToc -PathType Leaf) {
        $retailReferenceRootFull = [IO.Path]::GetFullPath($candidate).TrimEnd('\', '/')
    }
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
    "repository HEAD"
}

function Get-RetailReferenceHash {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    if ($retailReferenceRootFull) {
        $full = [IO.Path]::GetFullPath((Join-Path $retailReferenceRootFull $RelativePath))
        if (-not $full.StartsWith($retailReferenceRootFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Retail reference path escaped its checkout: $RelativePath"
        }
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
            throw "Retail reference file is missing: $full"
        }
        return (git -C $root hash-object $full).Trim()
    }
    return (git -C $root rev-parse ("HEAD:" + $RelativePath.Replace('\', '/'))).Trim()
}

$targets = @(
    @{ Folder = "MidnightSimpleUnitFrames"; Base = "MidnightSimpleUnitFrames" },
    @{ Folder = "MidnightSimpleUnitFrames_Options"; Base = "MidnightSimpleUnitFrames_Options" },
    @{ Folder = "MidnightSimpleUnitFrames_Assistant"; Base = "MidnightSimpleUnitFrames_Assistant" }
)
$clients = @(
    @{ Suffix = "Mainline"; Interface = "120007, 120100" },
    @{ Suffix = "Vanilla"; Interface = "11509" },
    @{ Suffix = "Mists"; Interface = "50504" },
    @{ Suffix = "TBC"; Interface = "20506" }
)
$expectedVersion = (Get-Content -LiteralPath (Join-Path $root "VERSION") -Raw).Trim()

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

$seenXml = @{}
function Test-XmlManifest {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path)
    if ($seenXml[$fullPath]) { return }
    $seenXml[$fullPath] = $true

    [xml]$document = Get-Content -LiteralPath $fullPath -Raw
    $nodes = $document.SelectNodes("//*[local-name()='Script' or local-name()='Include']")
    foreach ($node in $nodes) {
        $reference = $node.GetAttribute("file")
        if ([string]::IsNullOrWhiteSpace($reference)) { continue }
        $child = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $fullPath) $reference))
        if (-not (Test-Path -LiteralPath $child -PathType Leaf)) {
            throw "Missing XML manifest reference: $fullPath -> $reference"
        }
        if ([IO.Path]::GetExtension($child) -ieq ".xml") {
            Test-XmlManifest -Path $child
        }
    }
}

function Get-XmlLuaLoadPaths {
    param([Parameter(Mandatory = $true)][string]$Path)

    $paths = [Collections.Generic.List[string]]::new()
    $active = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    function Add-XmlLuaLoadPath {
        param([Parameter(Mandatory = $true)][string]$CurrentPath)

        $full = [IO.Path]::GetFullPath($CurrentPath)
        if (-not $active.Add($full)) {
            throw "XML include cycle detected at $full"
        }
        [xml]$document = Get-Content -LiteralPath $full -Raw
        foreach ($node in $document.SelectNodes("//*[local-name()='Script' or local-name()='Include']")) {
            $reference = $node.GetAttribute("file")
            if ([string]::IsNullOrWhiteSpace($reference)) { continue }
            $child = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $full) $reference))
            $extension = [IO.Path]::GetExtension($child)
            if ($extension -ieq ".xml") {
                Add-XmlLuaLoadPath -CurrentPath $child
            } elseif ($extension -ieq ".lua") {
                $paths.Add($child)
            }
        }
        [void]$active.Remove($full)
    }

    Add-XmlLuaLoadPath -CurrentPath $Path
    return $paths.ToArray()
}

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
        if ($actualInterface -ne $client.Interface) {
            throw "$tocName has interface '$actualInterface', expected '$($client.Interface)'"
        }

        $versionLine = $content | Where-Object { $_ -match '^## Version:' } | Select-Object -First 1
        $versions[$client.Suffix] = ($versionLine -replace '^## Version:\s*', '').Trim()
        $expectedClientVersion = $expectedVersion
        if ($client.Suffix -eq "Mainline" -and $retailReferenceRootFull) {
            $referenceToc = Join-Path $retailReferenceRootFull ($target.Folder + "/" + $target.Base + ".toc")
            $referenceVersionLine = Get-Content -LiteralPath $referenceToc |
                Where-Object { $_ -match '^## Version:' } |
                Select-Object -First 1
            $expectedClientVersion = ($referenceVersionLine -replace '^## Version:\s*', '').Trim()
        }
        if ($versions[$client.Suffix] -ne $expectedClientVersion) {
            throw "$tocName has version '$($versions[$client.Suffix])', expected '$expectedClientVersion'"
        }
        if ($client.Suffix -eq "Mainline" -and $retailReferenceRootFull) {
            $referenceMetadata = @(Get-Content -LiteralPath $referenceToc | Where-Object { $_ -match '^## ' })
            $currentMetadata = @($content | Where-Object { $_ -match '^## ' })
            if ($referenceMetadata.Count -ne $currentMetadata.Count -or
                @(Compare-Object $referenceMetadata $currentMetadata).Count -ne 0) {
                throw "$tocName metadata differs from Retail"
            }
        }

        foreach ($entry in ($content | Where-Object { $_ -and $_ -notmatch '^\s*#' })) {
            $entryPath = [IO.Path]::GetFullPath((Join-Path $folder $entry.Trim()))
            if (-not (Test-Path -LiteralPath $entryPath -PathType Leaf)) {
                throw "Missing TOC entry: $tocPath -> $entry"
            }
            if ([IO.Path]::GetExtension($entryPath) -ieq ".xml") {
                Test-XmlManifest -Path $entryPath
            }
        }
    }

}

$coreMists = Get-Content -LiteralPath (Join-Path $root "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_Mists.toc")
$compatIndex = [Array]::IndexOf($coreMists, "Game\Shared\Initialize.lua")
$classicCompatIndex = [Array]::IndexOf($coreMists, "Game\Classic\Initialize.lua")
$bootstrapIndex = [Array]::IndexOf($coreMists, "Kernel\MSUF_Bootstrap.lua")
if ($compatIndex -lt 0 -or $classicCompatIndex -lt 0 -or $bootstrapIndex -lt 0 `
    -or $compatIndex -gt $classicCompatIndex -or $classicCompatIndex -gt $bootstrapIndex) {
    throw "Shared and Classic client initialization must load before Kernel/MSUF_Bootstrap.lua"
}

$groupOwnershipPath = Join-Path $root "MidnightSimpleUnitFrames/Game/Classic/UnitFrames/Group/MSUF_UF_Group_Blizzard.lua"
$groupOwnershipSource = Get-Content -LiteralPath $groupOwnershipPath -Raw
if ($groupOwnershipSource -notmatch 'CompactRaidFrameManager_UpdateShown\(manager\)') {
    throw "Classic CompactRaidFrameManager refresh must receive its manager self argument"
}
if ($groupOwnershipSource -notmatch 'raidManagerMode' -or
    $groupOwnershipSource -notmatch 'manager\.toggleButton\s+or\s+_G\.CompactRaidFrameManagerToggleButton') {
    throw "Classic Raid Manager visibility must retain the RC4 mode and legacy toggle-button hook"
}

$elementsRoot = Join-Path $root "MidnightSimpleUnitFrames/UnitFrames/Embeds/MSUF_UFCore"
$gameRoot = Join-Path $root "MidnightSimpleUnitFrames/Game"
$classicSharedElementsPath = Join-Path $gameRoot "Classic/UnitFrames/MSUF_UFCore_Elements.xml"
$retailSharedElementsPath = Join-Path $elementsRoot "MSUF_UFCore_Elements.xml"
$auraCorePath = [IO.Path]::GetFullPath((Join-Path $root "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Core.lua"))
$retailSharedLoadOrder = @(Get-XmlLuaLoadPaths -Path $retailSharedElementsPath)
$auraCoreIndex = [Array]::IndexOf($retailSharedLoadOrder, $auraCorePath)
if ($auraCoreIndex -lt 0) {
    throw "Retail element manifest no longer loads the shared Auras3 core"
}
$classicSharedLoadOrder = @(Get-XmlLuaLoadPaths -Path $classicSharedElementsPath)
if ($classicSharedLoadOrder.Count -ne ($auraCoreIndex + 1)) {
    throw "Classic shared element manifest must match the Retail prefix through Auras3 core"
}
for ($index = 0; $index -le $auraCoreIndex; $index++) {
    if ($classicSharedLoadOrder[$index] -ne $retailSharedLoadOrder[$index]) {
        throw "Classic shared element load order differs from Retail before Auras3 backend selection at index $index"
    }
}

$classicAuraBackendPath = [IO.Path]::GetFullPath((Join-Path $root "MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua"))
$forbiddenRetailAuraPaths = @(
    "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_DotData.lua",
    "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_DefensiveData.lua",
    "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_AuraNameResolver.lua",
    "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_SpellIndicators.lua",
    "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua"
) | ForEach-Object { [IO.Path]::GetFullPath((Join-Path $root $_)) }
foreach ($flavor in @("Vanilla", "Mists", "TBC")) {
    $classicManifestPath = Join-Path $gameRoot "$flavor/UnitFrames.xml"
    $classicElements = Get-Content -LiteralPath $classicManifestPath -Raw
    if ($classicElements -notmatch '\.\.\\Classic\\Auras\\MSUF_Auras3_Features\.lua' -or
        $classicElements -notmatch '\.\.\\Classic\\Auras\\MSUF_Auras3_Visuals\.lua' -or
        $classicElements -notmatch '\.\.\\Classic\\Auras\\MSUF_Auras3_UnitFrames\.lua' -or
        $classicElements -notmatch '\.\.\\Classic\\UnitFrames\\MSUF_UFCore_Elements\.xml' -or
        $classicElements -notmatch 'Auras\\MSUF_Auras3_DotData\.lua' -or
        $classicElements -notmatch 'Auras\\MSUF_Auras3_DefensiveData\.lua' -or
        $classicElements -match 'AuraNameResolver' -or
        $classicElements -match 'Mainline\\Auras') {
        throw "$flavor element manifest must select only the Classic aura backend"
    }
    $classicLoadOrder = @(Get-XmlLuaLoadPaths -Path $classicManifestPath)
    foreach ($forbiddenPath in $forbiddenRetailAuraPaths) {
        if ([Array]::IndexOf($classicLoadOrder, $forbiddenPath) -ge 0) {
            throw "$flavor transitively loads Retail aura runtime: $forbiddenPath"
        }
    }
    $classicAuraBackendIndex = [Array]::IndexOf($classicLoadOrder, $classicAuraBackendPath)
    $classicAuraCoreIndex = [Array]::IndexOf($classicLoadOrder, $auraCorePath)
    if ($classicAuraBackendIndex -lt 0 -or $classicAuraCoreIndex -lt 0 -or
        $classicAuraCoreIndex -gt $classicAuraBackendIndex) {
        throw "$flavor must load Auras3 core before the Classic aura backend"
    }
    $groupElements = Get-Content -LiteralPath (Join-Path $gameRoot "$flavor/UnitFrames/GroupFrames.xml") -Raw
    if ($groupElements -notmatch 'Group\\MSUF_UF_Group_SpellIndicators_Data\.lua' -or
        $groupElements -notmatch 'Classic\\UnitFrames\\Group\\MSUF_UF_Group_SpellIndicators_Data_Base\.lua' -or
        $groupElements -match 'Mainline\\UnitFrames\\Group') {
        throw "$flavor group manifest must select only its Classic spell-indicator data"
    }
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

function Assert-TrackedFile {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Label
    )
    & git -C $root ls-files --error-unmatch -- $RelativePath 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "$Label must be tracked: $RelativePath"
    }
}

function Assert-OrdinalPathOrder {
    param(
        [Parameter(Mandatory = $true)][string[]]$Paths,
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
$trackedAddonPathLines = @(& git -C $root ls-files -- @addonFolders 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "Unable to enumerate tracked Classic addon files: $($trackedAddonPathLines -join ', ')"
}
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

if ($overrideBaseBlobs.Count -gt 0 -and -not $retailReferenceRootFull) {
    throw "Retail overrides require -RetailReferenceRoot so their recorded base blobs can be checked against current Retail Git HEAD"
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

    $referenceGitRoot = (& git -C $retailReferenceRootFull rev-parse --show-toplevel 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Retail reference is not a Git checkout: $retailReferenceRootFull" }
    $referenceGitRootFull = [IO.Path]::GetFullPath($referenceGitRoot).TrimEnd([char]92, [char]47)
    $pathComparison = if ([IO.Path]::DirectorySeparatorChar -eq [char]92) {
        [StringComparison]::OrdinalIgnoreCase
    } else {
        [StringComparison]::Ordinal
    }
    if (-not $referenceGitRootFull.Equals($retailReferenceRootFull, $pathComparison)) {
        throw "RetailReferenceRoot must be the Git repository root: $retailReferenceRootFull"
    }
    $retailStatus = @(& git -C $retailReferenceRootFull status --porcelain --untracked-files=all 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Unable to inspect Retail reference status" }
    if ($retailStatus.Count -ne 0) {
        throw "Retail reference checkout must be clean so its load graph and Git HEAD describe the same source"
    }

    $retailTreeLines = @(& git -C $retailReferenceRootFull ls-tree -r HEAD -- @addonFolders 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to enumerate tracked Retail addon files: $($retailTreeLines -join ', ')"
    }
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

    $candidateBlobLines = @($retailMappedPathOrder.ToArray() | & git -C $root hash-object --stdin-paths 2>&1)
    if ($LASTEXITCODE -ne 0 -or $candidateBlobLines.Count -ne $retailMappedPathOrder.Count) {
        throw "Unable to hash every mapped Classic candidate: expected=$($retailMappedPathOrder.Count) actual=$($candidateBlobLines.Count)"
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
    $versionableAddonPaths = @(& git -C $root ls-files --cached --others --exclude-standard -- @addonFolders 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to enumerate versionable Classic addon files: $($versionableAddonPaths -join ', ')"
    }
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
    Write-Host "Classic addon inventory: $($actualAddonPaths.Count) paths equal mapped Retail $($retailMappedPaths.Count) union owned $($ownedAddonPaths.Count)"
}

# Retail's load graph must never enter a Classic/Vanilla/Mists/TBC implementation
# directory. This is the mechanical 0.0-overhead gate: a Classic adapter that
# is merely guarded at runtime still fails because loading/parsing it on
# Mainline would already consume startup CPU and memory.
$mainlineLoaded = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
function Add-MainlineLoadPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $mainlineLoaded.Add($full)) { return }
    if ([IO.Path]::GetExtension($full) -ine ".xml") { return }
    [xml]$doc = Get-Content -LiteralPath $full -Raw
    foreach ($node in $doc.SelectNodes("//*[local-name()='Script' or local-name()='Include']")) {
        $reference = $node.GetAttribute("file")
        if (-not [string]::IsNullOrWhiteSpace($reference)) {
            Add-MainlineLoadPath ([IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $full) $reference)))
        }
    }
}
$mainlineTocPath = Join-Path $root "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_Mainline.toc"
foreach ($entry in (Get-Content -LiteralPath $mainlineTocPath | Where-Object { $_ -and $_ -notmatch '^\s*#' })) {
    Add-MainlineLoadPath ([IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $mainlineTocPath) $entry.Trim())))
}
foreach ($path in $mainlineLoaded) {
    if ($path -match '[\\/]Game[\\/](Classic|Vanilla|Mists|TBC)[\\/]') {
        throw "Retail zero-overhead violation: Mainline transitively loads $path"
    }
}

# Strong Mainline gate: preserve every Retail Lua path in order, permit content
# differences only for reviewed P entries, and permit additional Lua loads only
# for the four explicit Arena files in O. Client compatibility trees remain
# unreachable from Mainline.
function Get-CurrentLuaLoadHashes {
    param([Parameter(Mandatory = $true)][string]$TocPath)
    $hashes = [Collections.Generic.List[string]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    function Add-CurrentEntry([string]$Path) {
        $full = [IO.Path]::GetFullPath($Path)
        if (-not $seen.Add($full)) { return }
        $extension = [IO.Path]::GetExtension($full)
        if ($extension -ieq ".xml") {
            [xml]$doc = Get-Content -LiteralPath $full -Raw
            foreach ($node in $doc.SelectNodes("//*[local-name()='Script' or local-name()='Include']")) {
                $reference = $node.GetAttribute("file")
                if ($reference) {
                    Add-CurrentEntry ([IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $full) $reference)))
                }
            }
        } elseif ($extension -ieq ".lua") {
            $hashes.Add((git -C $root hash-object $full).Trim())
        }
    }
    foreach ($entry in Get-Content -LiteralPath $TocPath) {
        if ($entry -and $entry -notmatch '^\s*#') {
            Add-CurrentEntry (Join-Path (Split-Path -Parent $TocPath) $entry.Trim())
        }
    }
    return $hashes.ToArray()
}

function Get-CurrentLuaLoadPaths {
    param([Parameter(Mandatory = $true)][string]$TocPath)
    $paths = [Collections.Generic.List[string]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    function Add-CurrentPath([string]$Path) {
        $full = [IO.Path]::GetFullPath($Path)
        if (-not $seen.Add($full)) { return }
        $extension = [IO.Path]::GetExtension($full)
        if ($extension -ieq ".xml") {
            [xml]$doc = Get-Content -LiteralPath $full -Raw
            foreach ($node in $doc.SelectNodes("//*[local-name()='Script' or local-name()='Include']")) {
                $reference = $node.GetAttribute("file")
                if ($reference) {
                    Add-CurrentPath ([IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $full) $reference)))
                }
            }
        } elseif ($extension -ieq ".lua") {
            $paths.Add($full)
        }
    }
    foreach ($entry in Get-Content -LiteralPath $TocPath) {
        if ($entry -and $entry -notmatch '^\s*#') {
            Add-CurrentPath (Join-Path (Split-Path -Parent $TocPath) $entry.Trim())
        }
    }
    return $paths.ToArray()
}

function Get-HeadLuaLoadHashes {
    param([Parameter(Mandatory = $true)][string]$TocRelativePath)
    $hashes = [Collections.Generic.List[string]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    function Add-HeadEntry([string]$RelativePath) {
        $relative = $RelativePath.Replace('\', '/')
        if (-not $seen.Add($relative)) { return }
        $extension = [IO.Path]::GetExtension($relative)
        if ($extension -ieq ".xml") {
            $raw = (git -C $root show ("HEAD:" + $relative)) -join "`n"
            if ($LASTEXITCODE -ne 0) { throw "Cannot read HEAD:$relative" }
            [xml]$doc = $raw
            $parent = Split-Path -Parent (Join-Path $root $relative)
            foreach ($node in $doc.SelectNodes("//*[local-name()='Script' or local-name()='Include']")) {
                $reference = $node.GetAttribute("file")
                if ($reference) {
                    $childFull = [IO.Path]::GetFullPath((Join-Path $parent $reference))
                    if (-not $childFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
                        throw "HEAD XML reference escaped repository root: $relative -> $reference"
                    }
                    $childRelative = $childFull.Substring($rootFull.Length).TrimStart('\', '/').Replace('\', '/')
                    Add-HeadEntry $childRelative
                }
            }
        } elseif ($extension -ieq ".lua") {
            $hashes.Add((git -C $root rev-parse ("HEAD:" + $relative)).Trim())
        }
    }
    $tocRaw = (git -C $root show ("HEAD:" + $TocRelativePath)) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "Cannot read HEAD:$TocRelativePath" }
    $tocParent = Split-Path -Parent $TocRelativePath
    foreach ($entry in ($tocRaw -split "`n")) {
        if ($entry -and $entry -notmatch '^\s*#') {
            Add-HeadEntry ((Join-Path $tocParent $entry.Trim()).Replace('\', '/'))
        }
    }
    return $hashes.ToArray()
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
    "MidnightSimpleUnitFrames/Castbars/MSUF_ArenaCastbars.lua",
    "MidnightSimpleUnitFrames/Castbars/MSUF_ArenaCastbars_Preview.lua",
    "MidnightSimpleUnitFrames/Features/Gameplay/MSUF_Feature_ArenaMatch.lua",
    "MidnightSimpleUnitFrames/Features/Gameplay/MSUF_Feature_ArenaTrinkets.lua"
)) {
    if (-not $ownedAddonPaths.Contains($extraPath)) {
        throw "Mainline Arena addition must be declared in Classic ownership: $extraPath"
    }
    if ($overrideBaseBlobs.ContainsKey($extraPath)) {
        throw "Mainline Arena addition cannot also be a Retail override: $extraPath"
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
    $currentHashes = Get-CurrentLuaLoadHashes (Join-Path $root $parityTarget.Current)
    $currentPaths = Get-CurrentLuaLoadPaths (Join-Path $root $parityTarget.Current)
    if ($currentHashes.Count -ne $currentPaths.Count) {
        throw "$($parityTarget.Label) Mainline Lua hash/path inventory is inconsistent"
    }
    $currentRelativePaths = [Collections.Generic.List[string]]::new()
    foreach ($currentPath in $currentPaths) {
        $currentRelative = Get-RepositoryRelativePath -RepositoryFull $rootFull -FullPath $currentPath -Label "$($parityTarget.Label) Mainline path"
        if ($currentRelative -match '(^|/)Game/(Classic|Vanilla|Mists|TBC)/' -or $currentRelative -match '_Classic[.]lua$') {
            throw "$($parityTarget.Label) Mainline loads a Classic-only blob: $currentRelative"
        }
        $currentRelativePaths.Add($currentRelative)
    }

    if ($retailReferenceRootFull) {
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
                    throw "Mainline Arena addition is loaded more than once across addon TOCs: $extraPath"
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
                throw "Mainline Arena addition is loaded more than once across addon TOCs: $extraPath"
            }
            $currentIndex++
        }
        $currentRetailHashCount += $referenceRelativePaths.Count
    } else {
        $referenceHashes = Get-HeadLuaLoadHashes $parityTarget.Reference
        if ($referenceHashes.Count -ne $currentHashes.Count) {
            throw "$($parityTarget.Label) Mainline Lua load count changed: reference=$($referenceHashes.Count), prototype=$($currentHashes.Count)"
        }
        for ($index = 0; $index -lt $referenceHashes.Count; $index++) {
            if ($referenceHashes[$index] -ne $currentHashes[$index]) {
                throw "$($parityTarget.Label) Mainline Lua load sequence/content changed at index $index ($($currentRelativePaths[$index]))"
            }
        }
        $mainlineExactLuaCount += $referenceHashes.Count
        $currentRetailHashCount += $referenceHashes.Count
    }
}
if (-not $actualMainlineOwnedLuaExtras.SetEquals($mainlineOwnedLuaExtras)) {
    $missingMainlineOwned = [string[]]@($mainlineOwnedLuaExtras | Where-Object { -not $actualMainlineOwnedLuaExtras.Contains($_) })
    [Array]::Sort($missingMainlineOwned, [StringComparer]::Ordinal)
    throw "Mainline must load exactly the four declared Arena additions; missing=[$($missingMainlineOwned -join ', ')]"
}
# Other Classic-only features remain behind the Vanilla/Mists/TBC manifests.
$textureRuntimePath = Join-Path $root "MidnightSimpleUnitFrames/Game/Classic/UnitFrames/Effects/MSUF_UF_TextureLayer.lua"
$textureOptionsPath = Join-Path $root "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitTextureLayer_Classic.lua"
$textureDefaultsPath = Join-Path $root "MidnightSimpleUnitFrames/Game/Classic/State/MSUF_Defaults.lua"
$textureManifestPath = Join-Path $root "MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_AutoCoverage_Manifest_Classic.lua"
$textureSearchPath = Join-Path $root "MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_StaticIndex_Data_Classic.lua"
$textureRuntime = Get-Content -LiteralPath $textureRuntimePath -Raw
$textureOptions = Get-Content -LiteralPath $textureOptionsPath -Raw
$textureDefaults = Get-Content -LiteralPath $textureDefaultsPath -Raw
$textureManifest = Get-Content -LiteralPath $textureManifestPath -Raw
$textureSearch = Get-Content -LiteralPath $textureSearchPath -Raw
foreach ($contract in @(
    'ResolveLayerSize', 'ResolveLayerOffsets', 'ApplyLayerLayout',
    'ResolveEdgeSoftness', 'ApplySoftEdgeMask', 'SourceMode'
)) {
    if ($textureRuntime.IndexOf($contract, [StringComparison]::Ordinal) -lt 0) {
        throw "Expanded texture runtime contract is missing: $contract"
    }
}
if ($textureRuntime -match '\bfeatherCount\b' -and $textureRuntime -notmatch '(?m)^\s*local\s+featherCount\s*=') {
    throw "Classic texture runtime reads featherCount without a local declaration"
}
if ($textureRuntime -match 'OnUpdate|C_Timer|NewTicker|NewTimer') {
    throw "Expanded texture runtime must remain apply/event-driven with zero polling"
}
foreach ($contract in @(
    'TEXLAYER_SOURCE_MODES', 'TEXLAYER_SIZE_MODES', 'TEXLAYER_EDGE_ATTACH',
    'texLayerLinkGeometry', 'texLayerLinkSize', 'Edge softness',
    'TEXLAYER_LOOK_BASES', 'TEXLAYER_LOOK_MOODS', 'TEXLAYER_MODULAR_LOOKS', 'TEXLAYER_CLASS_LOOKS'
)) {
    if ($textureOptions.IndexOf($contract, [StringComparison]::Ordinal) -lt 0) {
        throw "Expanded texture options contract is missing: $contract"
    }
}
foreach ($defaultContract in @('SourceMode', 'ResponsiveSize', 'SizeMode', 'EdgeAttach', 'EdgeSoftness')) {
    if ($textureDefaults.IndexOf($defaultContract, [StringComparison]::Ordinal) -lt 0) {
        throw "Expanded texture default is missing: $defaultContract"
    }
}
foreach ($generatedContract in @('texLayerSourceMode', 'texLayerSizeMode', 'texLayerEdgeAttach', 'texLayerEdgeSoftness')) {
    if ($textureManifest.IndexOf($generatedContract, [StringComparison]::Ordinal) -lt 0) {
        throw "Expanded texture generated manifest is missing: $generatedContract"
    }
}
foreach ($searchContract in @('layered_look', 'source_mode', 'edgesoftness')) {
    if ($textureSearch.IndexOf($searchContract, [StringComparison]::Ordinal) -lt 0) {
        throw "Expanded texture search index is missing: $searchContract"
    }
}
$assetRoot = Join-Path $root "MidnightSimpleUnitFrames/Media/TextureLayers"
$textureAssets = @(Get-ChildItem -LiteralPath $assetRoot -Filter "*.png" -File)
if ($textureAssets.Count -ne 50) {
    throw "Expanded texture asset inventory changed: expected=50 actual=$($textureAssets.Count)"
}
$referencedAssets = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($match in [regex]::Matches($textureOptions, 'file\s*=\s*"([^"]+\.png)"')) {
    [void]$referencedAssets.Add($match.Groups[1].Value)
}
if ($referencedAssets.Count -ne 50) {
    throw "Expanded texture catalog must reference exactly 50 unique assets"
}
foreach ($asset in $textureAssets) {
    if (-not $referencedAssets.Contains($asset.Name)) {
        throw "Expanded texture asset is not reachable from the catalog: $($asset.Name)"
    }
}

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

$luac = Get-Command luac -ErrorAction SilentlyContinue
if ($luac) {
    $luaFiles = foreach ($target in $targets) {
        Get-ChildItem -LiteralPath (Join-Path $root $target.Folder) -Recurse -Filter "*.lua" -File
    }
    foreach ($file in $luaFiles) {
        & $luac.Source -p $file.FullName
        if ($LASTEXITCODE -ne 0) { throw "Lua 5.1 syntax failed: $($file.FullName)" }
    }
    Write-Host "Lua 5.1 syntax: $($luaFiles.Count) files passed"
} else {
    Write-Warning "luac not found; Lua 5.1 syntax check skipped"
}

$lua = Get-Command lua -ErrorAction SilentlyContinue
if ($lua) {
    $smoke = Join-Path $root "tools/tests/classic_client_bootstrap_smoke.lua"
    foreach ($flavor in @("Vanilla", "Mists", "TBC")) {
        & $lua.Source $smoke $flavor ($root -replace '\\', '/')
        if ($LASTEXITCODE -ne 0) { throw "Client bootstrap smoke failed: $flavor" }
    }
    $classicProfilePolicySmoke = Join-Path $root "tools/tests/classic_profile_60_only_smoke.lua"
    & $lua.Source $classicProfilePolicySmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic 6.0-only profile policy smoke failed" }
    $classResourceSmoke = Join-Path $root "tools/tests/classic_class_resources_smoke.lua"
    & $lua.Source $classResourceSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic class-resource ownership smoke failed" }
    $classPowerProviderSmoke = Join-Path $root "tools/tests/classic_classpower_provider_smoke.lua"
    & $lua.Source $classPowerProviderSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Client ClassPower provider smoke failed" }
    $classicCastbarSmoke = Join-Path $root "tools/tests/classic_castbar_engine_smoke.lua"
    & $lua.Source $classicCastbarSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic castbar engine smoke failed" }
    $classicCastbarVisualSmoke = Join-Path $root "tools/tests/classic_castbar_visual_compat_smoke.lua"
    & $lua.Source $classicCastbarVisualSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic castbar visual compatibility smoke failed" }
    $castbarOwnershipSmoke = Join-Path $root "tools/castbar_refresh_ownership_smoke.lua"
    & $lua.Source $castbarOwnershipSmoke
    if ($LASTEXITCODE -ne 0) { throw "Shared castbar refresh ownership smoke failed" }
    $auraFontFanoutSmoke = Join-Path $root "tools/aura_font_fanout_smoke.lua"
    & $lua.Source $auraFontFanoutSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Shared aura font fanout smoke failed" }
    foreach ($arenaSmoke in @(
        "tools/arena_unit_scope_smoke.lua",
        "tools/arena_prep_visibility_smoke.lua",
        "tools/arena_secret_class_color_smoke.lua",
        "tools/arena_trinket_tracking_smoke.lua",
        "tools/arena_interrupt_ready_smoke.lua",
        ".github/scripts/arena_assistant_scope_smoke.lua",
        ".github/scripts/arena_postbase_integration_smoke.lua",
        ".github/scripts/arena_restoration_gaps_smoke.lua"
    )) {
        & $lua.Source (Join-Path $root $arenaSmoke)
        if ($LASTEXITCODE -ne 0) { throw "Arena frame regression smoke failed: $arenaSmoke" }
    }
    $nicknameProviderSmoke = Join-Path $root "tools/nickname_provider_api_smoke.lua"
    & $lua.Source $nicknameProviderSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic nickname provider API smoke failed" }
    $eliteClassificationSmoke = Join-Path $root ".github/scripts/tests/elite_indicator_classification_smoke.lua"
    & $lua.Source $eliteClassificationSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Elite indicator classification smoke failed" }
    foreach ($v604Smoke in @(
        "tools/aura_big_defensive_filter_smoke.lua",
        "tools/aura_group_slot_layer_smoke.lua",
        "tools/group_preview_roster_handoff_smoke.lua",
        "tools/unit_name_anchor_reflow_smoke.lua"
    )) {
        & $lua.Source (Join-Path $root $v604Smoke)
        if ($LASTEXITCODE -ne 0) { throw "v6.04 parity smoke failed: $v604Smoke" }
    }
    $classicPredictionSmoke = Join-Path $root "tools/tests/classic_prediction_contract_smoke.lua"
    & $lua.Source $classicPredictionSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic prediction contract smoke failed" }
    $classicAuraSmoke = Join-Path $root "tools/tests/classic_aura_backend_smoke.lua"
    & $lua.Source $classicAuraSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic aura backend smoke failed" }
    $classicAuraMenuFilterSmoke = Join-Path $root "tools/tests/classic_aura_menu_filters_smoke.lua"
    & $lua.Source $classicAuraMenuFilterSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic Aura menu filter smoke failed" }
    $classicAuraFeatureSmoke = Join-Path $root "tools/tests/classic_aura_features_smoke.lua"
    & $lua.Source $classicAuraFeatureSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic aura feature compiler smoke failed" }
    $classicGroupDataSmoke = Join-Path $root "tools/tests/classic_group_indicator_data_smoke.lua"
    & $lua.Source $classicGroupDataSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic group indicator data smoke failed" }
    $classicRaidManagerSmoke = Join-Path $root "tools/tests/classic_raid_manager_mode_smoke.lua"
    & $lua.Source $classicRaidManagerSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic Raid Manager mode smoke failed" }
    $classicPetHappinessSmoke = Join-Path $root "tools/tests/classic_pet_happiness_smoke.lua"
    & $lua.Source $classicPetHappinessSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic Pet Happiness smoke failed" }
    $classicEditModeSmoke = Join-Path $root "tools/tests/classic_editmode_smoke.lua"
    & $lua.Source $classicEditModeSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic Edit Mode smoke failed" }
    $classicMenuParitySmoke = Join-Path $root "tools/tests/classic_menu_retail_parity_smoke.lua"
    & $lua.Source $classicMenuParitySmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic Menu2 Retail parity smoke failed" }
    $classicAuraRenderSmoke = Join-Path $root "tools/tests/classic_aura_render_smoke.lua"
    $classicAuraBackend = Join-Path $root "MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua"
    $classicAuraFeatures = Join-Path $root "MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_Features.lua"
    $classicAuraVisuals = Join-Path $root "MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_Visuals.lua"
    $classicAuraCore = Join-Path $root "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Core.lua"
    & $lua.Source $classicAuraRenderSmoke ($root -replace '\\', '/') `
        ($classicAuraBackend -replace '\\', '/') ($classicAuraFeatures -replace '\\', '/') `
        ($classicAuraCore -replace '\\', '/') ($classicAuraVisuals -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic aura live-render smoke failed" }
} else {
    Write-Warning "lua not found; client bootstrap smoke skipped"
}

$uiMirror = Join-Path $root "_local_workflows/references/wow-ui-source/.git"
if (Test-Path -LiteralPath $uiMirror -PathType Container) {
    & (Join-Path $root "tools/audit-classic-ui-source.ps1")
    if ($LASTEXITCODE -ne 0) { throw "Blizzard Classic source contract audit failed" }
} else {
    Write-Warning "Blizzard UI source mirror missing; source contract audit skipped"
}

Write-Host "Client TOCs: 12 manifests passed (Mainline, Vanilla, Mists, TBC)"
Write-Host "XML load graph: $($seenXml.Count) manifests resolved"
Write-Host "Mainline exact Lua: $mainlineExactLuaCount Retail paths retain order and Git blobs"
Write-Host "Mainline override Lua: $mainlineOverrideLuaCount Retail paths retain order with reviewed P blobs"
Write-Host "Mainline owned Lua: $($actualMainlineOwnedLuaExtras.Count) declared O Arena additions; no Game/Classic load"
Write-Host "Retail zero-overhead load graph: $($mainlineLoaded.Count) core files, $currentRetailHashCount Retail Lua paths across Core/Options/Assistant validated against $retailReferenceLabel"
