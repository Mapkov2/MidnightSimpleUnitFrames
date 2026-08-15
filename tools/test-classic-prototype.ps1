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
foreach ($flavor in @("Vanilla", "Mists", "TBC")) {
    $classicElements = Get-Content -LiteralPath (Join-Path $gameRoot "$flavor/UnitFrames.xml") -Raw
    if ($classicElements -notmatch '\.\.\\Classic\\Auras\\MSUF_Auras3_Features\.lua' -or
        $classicElements -notmatch '\.\.\\Classic\\Auras\\MSUF_Auras3_Visuals\.lua' -or
        $classicElements -notmatch '\.\.\\Classic\\Auras\\MSUF_Auras3_UnitFrames\.lua' -or
        $classicElements -notmatch 'Auras\\MSUF_Auras3_DotData\.lua' -or
        $classicElements -notmatch 'Auras\\MSUF_Auras3_DefensiveData\.lua' -or
        $classicElements -match 'AuraNameResolver' -or
        $classicElements -match 'Mainline\\Auras') {
        throw "$flavor element manifest must select only the Classic aura backend"
    }
    $groupElements = Get-Content -LiteralPath (Join-Path $gameRoot "$flavor/UnitFrames/GroupFrames.xml") -Raw
    if ($groupElements -notmatch 'Group\\MSUF_UF_Group_SpellIndicators_Data\.lua' -or
        $groupElements -notmatch 'Classic\\UnitFrames\\Group\\MSUF_UF_Group_SpellIndicators_Data_Base\.lua' -or
        $groupElements -match 'Mainline\\UnitFrames\\Group') {
        throw "$flavor group manifest must select only its Classic spell-indicator data"
    }
}

if ($retailReferenceRootFull) {
    $retailCanonicalCount = 0
    foreach ($target in $targets) {
        $referenceFolder = Join-Path $retailReferenceRootFull $target.Folder
        foreach ($referenceFile in Get-ChildItem -LiteralPath $referenceFolder -Recurse -File) {
            $relativePath = $referenceFile.FullName.Substring($retailReferenceRootFull.Length).TrimStart('\', '/').Replace('\', '/')
            if ($relativePath -eq ($target.Folder + "/" + $target.Base + ".toc")) { continue }
            $candidatePath = Join-Path $root $relativePath
            if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
                throw "Canonical Retail file is missing from Classic repository: $relativePath"
            }
            $referenceHash = (Get-FileHash -LiteralPath $referenceFile.FullName -Algorithm SHA256).Hash
            $candidateHash = (Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash
            if ($referenceHash -ne $candidateHash) {
                throw "Canonical Retail file differs in Classic repository: $relativePath"
            }
            $retailCanonicalCount++
        }
        $referenceToc = Join-Path $referenceFolder ($target.Base + ".toc")
        $candidateToc = Join-Path (Join-Path $root $target.Folder) ($target.Base + "_Mainline.toc")
        if ((Get-FileHash -LiteralPath $referenceToc -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath $candidateToc -Algorithm SHA256).Hash) {
            throw "$($target.Base)_Mainline.toc is not byte-identical to Retail"
        }
    }
    Write-Host "Canonical Retail source parity: $retailCanonicalCount files plus 3 Mainline TOCs match byte-for-byte"
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

# Strong Retail parity gate: resolve the current adjacent Retail TOCs (or HEAD
# when that checkout is unavailable) and the new Mainline TOCs in load order,
# then compare every Lua blob. Relocated files are allowed; extra code, omitted
# code, or a changed shared module is not. This makes the "zero Retail overhead"
# claim mechanical rather than relying only on client guards.
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
$currentRetailHashCount = 0
foreach ($parityTarget in $retailParityTargets) {
    $referenceHashes = if ($retailReferenceRootFull) {
        Get-CurrentLuaLoadHashes (Join-Path $retailReferenceRootFull $parityTarget.Reference)
    } else {
        Get-HeadLuaLoadHashes $parityTarget.Reference
    }
    $currentHashes = Get-CurrentLuaLoadHashes (Join-Path $root $parityTarget.Current)
    $currentPaths = Get-CurrentLuaLoadPaths (Join-Path $root $parityTarget.Current)
    if ($referenceHashes.Count -ne $currentHashes.Count) {
        throw "$($parityTarget.Label) Mainline Lua load count changed: reference=$($referenceHashes.Count), prototype=$($currentHashes.Count)"
    }
    for ($index = 0; $index -lt $referenceHashes.Count; $index++) {
        $currentRelative = $currentPaths[$index].Substring($rootFull.Length).TrimStart('\', '/').Replace('\', '/')
        if ($currentRelative -match '(^|/)Game/Classic/' -or $currentRelative -match '_Classic\.lua$') {
            throw "$($parityTarget.Label) Mainline loads a Classic-only blob: $currentRelative"
        }
        if ($referenceHashes[$index] -ne $currentHashes[$index]) {
            throw "$($parityTarget.Label) Mainline Lua load sequence/content changed at index $index ($currentRelative)"
        }
    }
    $currentRetailHashCount += $currentHashes.Count
}
# Classic-only features live behind the Vanilla/Mists/TBC manifests. Mainline
# has no parity allowlist: every loaded Lua blob must match Retail exactly.
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
    $castbarOwnershipSmoke = Join-Path $root "tools/castbar_refresh_ownership_smoke.lua"
    & $lua.Source $castbarOwnershipSmoke
    if ($LASTEXITCODE -ne 0) { throw "Shared castbar refresh ownership smoke failed" }
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
Write-Host "Retail zero-overhead load graph: $($mainlineLoaded.Count) core files, $currentRetailHashCount Lua blobs across Core/Options/Assistant match $retailReferenceLabel"
