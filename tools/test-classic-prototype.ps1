[CmdletBinding()]
param(
    [string]$RetailReferenceRoot = "",
    [switch]$SelfContained,
    [switch]$AllowMissingTools
)

$ErrorActionPreference = "Stop"
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

# Every smoke the gate starts goes through Invoke-GateSmoke, which records the
# smoke file before running the command. The inventory check near the end
# compares that record with the tracked smokes, so a smoke named only in a
# comment or an unused list never counts as covered.
$smokeFilePattern = '(?:_smoke\.(?:lua|py)|_contract\.lua)$'
$ranSmokes = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
function Invoke-GateSmoke {
    $command = $args[0]
    $arguments = @($args | Select-Object -Skip 1)
    foreach ($argument in $arguments) {
        $text = [string]$argument
        if ($text -notmatch $smokeFilePattern) { continue }
        $full = if ([IO.Path]::IsPathRooted($text)) { [IO.Path]::GetFullPath($text) } else { [IO.Path]::GetFullPath((Join-Path $rootFull $text)) }
        if (-not $full.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Gate smoke lies outside the repository: $text"
        }
        [void]$ranSmokes.Add($full.Substring($rootFull.Length + 1).Replace([char]92, [char]47))
    }
    & $command @arguments
}

function ConvertTo-InterfaceSet {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $set = [Collections.Generic.SortedSet[int]]::new()
    foreach ($item in @($Value -split ',' | ForEach-Object { $_.Trim() })) {
        if ($item -notmatch '^[1-9][0-9]*$') { throw "$Label has a malformed interface list: '$Value'" }
        if (-not $set.Add([int]$item)) { throw "$Label repeats interface $item" }
    }
    return [int[]]@($set)
}

# tools/classic-client-matrix.tsv is the single list of supported clients.
# Every client loop, interface check and summary count below reads it.
$clientMatrixRelative = "tools/classic-client-matrix.tsv"
$clientMatrixPath = Join-Path $root $clientMatrixRelative
if (-not (Test-Path -LiteralPath $clientMatrixPath -PathType Leaf)) { throw "Client matrix is missing: $clientMatrixRelative" }
$clientMatrix = @(Import-Csv -LiteralPath $clientMatrixPath -Delimiter "`t")
$clientMatrixColumns = @("Suffix", "Interfaces", "ClientToken", "ProjectGlobal", "GameType", "MirrorBranch", "CurseForgeVersions", "IsClassic")
if ($clientMatrix.Count -eq 0) { throw "Client matrix has no clients: $clientMatrixRelative" }
$actualMatrixColumns = @($clientMatrix[0].PSObject.Properties | ForEach-Object { $_.Name })
if (($actualMatrixColumns -join "`t") -cne ($clientMatrixColumns -join "`t")) {
    throw "Client matrix columns must be exactly: $($clientMatrixColumns -join ', ')"
}
$clientSuffixSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($client in $clientMatrix) {
    if ($client.Suffix -cnotmatch '^[A-Z][A-Za-z0-9]*$' -or -not $clientSuffixSet.Add($client.Suffix)) {
        throw "Client matrix suffix is malformed or duplicated: '$($client.Suffix)'"
    }
    if ($client.IsClassic -cne "true" -and $client.IsClassic -cne "false") {
        throw "Client matrix IsClassic must be true or false: $($client.Suffix)"
    }
    [void](ConvertTo-InterfaceSet -Value $client.Interfaces -Label "Client matrix $($client.Suffix)")
    if (($client.IsClassic -ceq "true") -ne ($client.ClientToken -cne "")) {
        throw "Client matrix $($client.Suffix): Classic clients need an X-MSUF-Client token and Mainline must not declare one"
    }
    if ($client.ProjectGlobal -cnotmatch '^WOW_PROJECT_[A-Z_]+$' -or $client.GameType -cnotmatch '^[a-z]+$' -or
        $client.MirrorBranch -cnotmatch '^upstream/[a-z0-9_]+$' -or [string]::IsNullOrWhiteSpace($client.CurseForgeVersions)) {
        throw "Client matrix row is incomplete: $($client.Suffix)"
    }
}
$mainlineMatrixClients = @($clientMatrix | Where-Object { $_.IsClassic -ceq "false" })
if ($mainlineMatrixClients.Count -ne 1 -or $mainlineMatrixClients[0].Suffix -cne "Mainline") {
    throw "Client matrix must contain exactly one non-Classic client, named Mainline"
}
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

Invoke-GateSmoke python (Join-Path $root ".github/scripts/classic_refactor_load_order_smoke.py")
if ($LASTEXITCODE -ne 0) { throw "Classic refactor load-order contract failed" }
& python (Join-Path $root ".github/quality/error_paths.py")
if ($LASTEXITCODE -ne 0) { throw "Classic error visibility contract failed" }

$retailReferenceRootFull = $null
if ($SelfContained) {
    # No sibling auto-detection: a self-contained run must not pick up a Retail checkout.
} elseif ([string]::IsNullOrWhiteSpace($RetailReferenceRoot)) {
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
} elseif ($SelfContained) {
    "no Retail reference (self-contained run)"
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
        $actualInterfaceSet = ConvertTo-InterfaceSet -Value $actualInterface -Label $tocName
        $expectedInterfaceSet = ConvertTo-InterfaceSet -Value $client.Interfaces -Label "Client matrix $($client.Suffix)"
        if (($actualInterfaceSet -join ',') -cne ($expectedInterfaceSet -join ',')) {
            throw "$tocName has interfaces '$actualInterface', expected the client matrix set '$($client.Interfaces)'"
        }
        $clientTokenLines = @($content | Where-Object { $_ -match '^## X-MSUF-Client:' })
        $actualClientToken = if ($clientTokenLines.Count -gt 0) { ($clientTokenLines[0] -replace '^## X-MSUF-Client:\s*', '').Trim() } else { "" }
        if ($clientTokenLines.Count -gt 1 -or $actualClientToken -cne $client.ClientToken) {
            throw "$tocName declares X-MSUF-Client '$actualClientToken', expected '$($client.ClientToken)'"
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
        # Mainline carries the Retail version, which only a Retail reference can supply.
        if (($client.IsClassic -ceq "true" -or $retailReferenceRootFull) -and $versions[$client.Suffix] -ne $expectedClientVersion) {
            throw "$tocName has version '$($versions[$client.Suffix])', expected '$expectedClientVersion'"
        }
        if ($client.Suffix -eq "Mainline" -and $retailReferenceRootFull) {
            $referenceMetadata = @(Get-Content -LiteralPath $referenceToc | Where-Object { $_ -match '^## ' } |
                ForEach-Object {
                    if ($_ -match '^## Interface:') { $interfaceLine } else { $_ }
                })
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

# Player castbar event handling is client-neutral. Classic flavors must load
# the synchronized Retail runtime directly so STOP/INTERRUPTED ordering fixes
# cannot drift in an unreviewed duplicate again.
foreach ($flavor in $classicSuffixes) {
    $coreFlavorToc = Join-Path $root "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_$flavor.toc"
    $coreFlavorEntries = @(Get-Content -LiteralPath $coreFlavorToc)
    if ([Array]::IndexOf($coreFlavorEntries, "Castbars\MSUF_PlayerCastbarRuntime.lua") -lt 0) {
        throw "$flavor must load the synchronized Castbars/MSUF_PlayerCastbarRuntime.lua"
    }
    if ($coreFlavorEntries -match 'Game\\Classic\\Castbars\\MSUF_PlayerCastbarRuntime[.]lua') {
        throw "$flavor still loads the stale Classic player-castbar duplicate"
    }
}
if (Test-Path -LiteralPath (Join-Path $root "MidnightSimpleUnitFrames/Game/Classic/Castbars/MSUF_PlayerCastbarRuntime.lua")) {
    throw "Classic player-castbar duplicate must remain retired"
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
if ($groupOwnershipSource -notmatch 'HardHideFrame\(_G\.PartyFrame\)' -or
    $groupOwnershipSource -notmatch 'HardHideFrame\(_G\.CompactRaidFrameContainer\)' -or
    $groupOwnershipSource -match 'PartyMemberFramePool\s*,\s*function' -or
    $groupOwnershipSource -match 'memberUnitFrames\s*,\s*function') {
    throw "Classic Blizzard ownership must hide only PartyFrame and CompactRaidFrameContainer owners"
}
if ($groupOwnershipSource -notmatch 'function GF\.RestoreBlizzardGroupFrames\(\)[\s\S]*?return false') {
    throw "Classic Blizzard CompactUnitFrame ownership handoff must remain reload-only"
}
if ($groupOwnershipSource -notmatch 'raidManagerMode' -or
    $groupOwnershipSource -notmatch 'manager\.toggleButton\s+or\s+_G\.CompactRaidFrameManagerToggleButton') {
    throw "Classic Raid Manager visibility must retain the RC4 mode and legacy toggle-button hook"
}

$elementsRoot = Join-Path $root "MidnightSimpleUnitFrames/UnitFrames/Embeds/MSUF_UFCore"
$gameRoot = Join-Path $root "MidnightSimpleUnitFrames/Game"
$classicSharedElementsPath = Join-Path $gameRoot "Classic/UnitFrames/MSUF_UFCore_Elements.xml"
$retailSharedElementsPath = Join-Path $elementsRoot "MSUF_UFCore_Elements.xml"
$auraCorePath = [IO.Path]::GetFullPath((Join-Path $root "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_IconShape.lua"))
$retailSharedLoadOrder = @(Get-XmlLuaLoadPaths -Path $retailSharedElementsPath)
$auraCoreIndex = [Array]::IndexOf($retailSharedLoadOrder, $auraCorePath)
if ($auraCoreIndex -lt 0) {
    throw "Retail element manifest no longer loads the shared Auras3 icon definitions"
}
$classicSharedLoadOrder = @(Get-XmlLuaLoadPaths -Path $classicSharedElementsPath)
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
foreach ($flavor in $classicSuffixes) {
    $classicManifestPath = Join-Path $gameRoot "$flavor/UnitFrames.xml"
    $classicElements = Get-Content -LiteralPath $classicManifestPath -Raw
    if ($classicElements -notmatch '\.\.\\Classic\\Auras\\MSUF_Auras3_Features\.lua' -or
        $classicElements -notmatch '\.\.\\Classic\\Auras\\MSUF_Auras3_Visuals\.lua' -or
        $classicElements -notmatch '\.\.\\Classic\\Auras\\MSUF_Auras3_Compile\.lua' -or
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
    # The backend imports its config compiler through A3._ClassicCompile at load time.
    $classicAuraCompileIndex = [Array]::IndexOf($classicLoadOrder, $classicAuraCompilePath)
    if ($classicAuraCompileIndex -lt 0 -or $classicAuraCompileIndex -gt $classicAuraBackendIndex) {
        throw "$flavor must load the Classic aura compiler before the Classic aura backend"
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
$shadowLines = [string[]][IO.File]::ReadAllLines($shadowManifestPath)
if ($shadowLines.Count -eq 0) { throw "Classic owned-shadow manifest is empty" }
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
    if ($path -match ('[\\/]Game[\\/]' + $classicDirectoryPattern + '[\\/]')) {
        throw "Retail zero-overhead violation: Mainline transitively loads $path"
    }
}

# Strong Mainline gate: preserve every Retail Lua path in order, permit content
# differences only for reviewed P entries, and permit additional Lua loads only
# for the declared shared/Arena additions in O. Client compatibility trees remain
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
    "MidnightSimpleUnitFrames/Game/Shared/Initialize.lua",
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
    $currentHashes = Get-CurrentLuaLoadHashes (Join-Path $root $parityTarget.Current)
    $currentPaths = Get-CurrentLuaLoadPaths (Join-Path $root $parityTarget.Current)
    if ($currentHashes.Count -ne $currentPaths.Count) {
        throw "$($parityTarget.Label) Mainline Lua hash/path inventory is inconsistent"
    }
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

# $luac and $lua were resolved and version-checked by the tool preflight; a
# missing tool was either fatal there or recorded as a skipped step.
if ($luac) {
    $luaFiles = foreach ($target in $targets) {
        Get-ChildItem -LiteralPath (Join-Path $root $target.Folder) -Recurse -Filter "*.lua" -File
    }
    foreach ($file in $luaFiles) {
        & $luac.Source -p $file.FullName
        if ($LASTEXITCODE -ne 0) { throw "Lua 5.1 syntax failed: $($file.FullName)" }
    }
    Write-Host "Lua 5.1 syntax: $($luaFiles.Count) files passed"

    # Lua 5.1 allows at most 200 locals in one function. These files were split
    # to get away from that ceiling; each budget keeps room before a file drifts
    # back to it. The main-chunk header of `luac -l` carries the local count.
    $classicLocalBudgets = [ordered]@{
        "MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua" = 175
        "MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_Compile.lua" = 120
        "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_Classic.lua" = 180
    }
    foreach ($budgetPath in $classicLocalBudgets.Keys) {
        $budgetListing = @(& $luac.Source -l -p (Join-Path $root $budgetPath))
        if ($LASTEXITCODE -ne 0) { throw "Lua 5.1 local budget listing failed: $budgetPath" }
        $mainHeader = $budgetListing | Where-Object { $_ -match '^0\+ params, \d+ slots, \d+ upvalues, \d+ locals' } | Select-Object -First 1
        if (-not $mainHeader -or $mainHeader -notmatch '^0\+ params, \d+ slots, \d+ upvalues, (\d+) locals') {
            throw "Lua 5.1 local budget: main-chunk header not found for $budgetPath"
        }
        $mainLocals = [int]$Matches[1]
        if ($mainLocals -gt $classicLocalBudgets[$budgetPath]) {
            throw "Lua 5.1 local budget exceeded: $budgetPath has $mainLocals main-chunk locals; budget $($classicLocalBudgets[$budgetPath])"
        }
        Write-Host "Lua 5.1 local budget: $budgetPath $mainLocals/$($classicLocalBudgets[$budgetPath])"
    }
}

if ($lua) {
    # The Glass menu skin belongs to WoW Forever only: every shipped client keeps
    # the stock menu, and the "Forever" runs simulate the hour-0 client fact.
    foreach ($flavor in @($clientSuffixes) + @("FutureVanilla", "Forever")) {
        Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/classic_menu_atlas_smoke.lua") $root $flavor
        if ($LASTEXITCODE -ne 0) { throw "Menu skin smoke failed: $flavor" }
    }
    Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/classic_menu_atlas_smoke.lua") $root "Forever" "tinted"
    if ($LASTEXITCODE -ne 0) { throw "Forever menu skin custom-tint smoke failed" }
    Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/classic_menu_atlas_smoke.lua") $root "Forever" "midnight"
    if ($LASTEXITCODE -ne 0) { throw "Forever Midnight appearance preset smoke failed" }
    $smoke = Join-Path $root "tools/tests/classic_client_bootstrap_smoke.lua"
    foreach ($flavor in @($clientSuffixes) + @("FutureTaggedVanilla", "FutureProjectVanilla", "UnknownUntagged")) {
        Invoke-GateSmoke $lua.Source $auraTestDriver $smoke $flavor ($root -replace '\\', '/')
        if ($LASTEXITCODE -ne 0) { throw "Client bootstrap smoke failed: $flavor" }
    }
    # Each X-MSUF-Client token in the client matrix must place its flavor on its
    # own, under a project ID no client knows; the smoke reads the token from arg[3].
    foreach ($client in @($clientMatrix | Where-Object { $_.ClientToken -cne "" })) {
        Invoke-GateSmoke $lua.Source $auraTestDriver $smoke ("TagOnly" + $client.Suffix) ($root -replace '\\', '/') $client.ClientToken
        if ($LASTEXITCODE -ne 0) { throw "Client bootstrap tag-only smoke failed: $($client.Suffix)" }
    }
    # Plain Lua on purpose: the aura test driver stubs issecretvalue, which would
    # hide the missing secret-value API case this smoke pins.
    Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/classic_client_detection_smoke.lua") ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Client detection smoke failed" }
    Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/client_info_command_smoke.lua") ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Client info command smoke failed" }
    Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/classic_project_id_reads_smoke.lua") ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Project ID read inventory smoke failed" }
    Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/classic_texture_layer_highlight_smoke.lua") ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Texture layer highlight smoke failed" }
    # WoW Forever (Mainline build, Client.IsForever) behaviour contracts.
    Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/forever_combo_frame_hider_smoke.lua") $root
    if ($LASTEXITCODE -ne 0) { throw "WoW Forever ComboFrame hider smoke failed" }
    Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/aura_header_container_round_layout_smoke.lua") $root
    if ($LASTEXITCODE -ne 0) { throw "Aura header container round-layout smoke failed" }
    Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/mainline_classpower_forever_routing_smoke.lua") $root
    if ($LASTEXITCODE -ne 0) { throw "Mainline ClassPower Forever routing smoke failed" }
    Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/forever_shell_project_gates_smoke.lua") ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Forever shell project gates smoke failed" }
    Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/forever_castbar_client_data_smoke.lua") $root
    if ($LASTEXITCODE -ne 0) { throw "Forever castbar client data smoke failed" }
    Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/forever_aura_data_smoke.lua") ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "WoW Forever aura data smoke failed" }
    Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/forever_group_frames_smoke.lua") $root
    if ($LASTEXITCODE -ne 0) { throw "Forever group frames smoke failed" }
    Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/forever_arena_zero_smoke.lua") ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Forever arena-zero Mainline smoke failed" }
    Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/forever_factory_profile_smoke.lua") $root
    if ($LASTEXITCODE -ne 0) { throw "Forever factory profile CBOR smoke failed" }
    Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/forever_profile_import_persist_smoke.lua") $root
    if ($LASTEXITCODE -ne 0) { throw "Forever profile persist smoke failed" }
    foreach ($flavor in @($clientSuffixes) + @("Forever")) {
        Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/forever_spec_profile_smoke.lua") $root $flavor
        if ($LASTEXITCODE -ne 0) { throw "Forever spec profile smoke failed: $flavor" }
    }
    Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/classic_scheduler_contract_smoke.lua") $root
    if ($LASTEXITCODE -ne 0) { throw "Scheduler contract regression failed" }
    foreach ($flavor in $clientSuffixes) {
        Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/classic_shared_definitions_smoke.lua") $root $flavor
        if ($LASTEXITCODE -ne 0) { throw "Shared aura definitions failed: $flavor" }
    }
    $classicProfilePolicySmoke = Join-Path $root "tools/tests/classic_profile_60_only_smoke.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $classicProfilePolicySmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic 6.0-only profile policy smoke failed" }
    $classicProfileCrossFlavorSmoke = Join-Path $root "tools/tests/classic_profile_cross_flavor_smoke.lua"
    foreach ($flavor in $clientSuffixes) {
        Invoke-GateSmoke $lua.Source $auraTestDriver $classicProfileCrossFlavorSmoke $flavor ($root -replace '\\', '/')
        if ($LASTEXITCODE -ne 0) { throw "Cross-flavor profile smoke failed: $flavor" }
    }
    $classicProfileImportTxnSmoke = Join-Path $root "tools/tests/classic_profile_import_transaction_smoke.lua"
    foreach ($flavor in $clientSuffixes) {
        foreach ($codecMode in @("raise", "nil")) {
            Invoke-GateSmoke $lua.Source $auraTestDriver $classicProfileImportTxnSmoke $flavor $codecMode ($root -replace '\\', '/')
            if ($LASTEXITCODE -ne 0) { throw "Profile import transaction smoke failed: $flavor $codecMode" }
        }
    }
    $classResourceSmoke = Join-Path $root "tools/tests/classic_class_resources_smoke.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $classResourceSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic class-resource ownership smoke failed" }
    Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/classic_texture_layer_contract_smoke.lua") $root
    if ($LASTEXITCODE -ne 0) { throw "Texture Layer menu contract failed" }
    Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/classic_font_return_smoke.lua") $root
    if ($LASTEXITCODE -ne 0) { throw "Classic font return contract failed" }
    Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/classic_defaults_refactor_smoke.lua") $root
    if ($LASTEXITCODE -ne 0) { throw "Classic split defaults contract failed" }
    Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/classic_arena_five_slot_smoke.lua") $root
    if ($LASTEXITCODE -ne 0) { throw "Classic arena five-slot contract failed" }
    Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/classic_arena_legacy_hider_smoke.lua") $root
    if ($LASTEXITCODE -ne 0) { throw "Classic legacy arena hider smoke failed" }
    $classPowerProviderSmoke = Join-Path $root "tools/tests/classic_classpower_provider_smoke.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $classPowerProviderSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Client ClassPower provider smoke failed" }
    foreach ($flavor in $classicSuffixes) {
        Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/classic_classpower_runtime_smoke.lua") $root $flavor
        if ($LASTEXITCODE -ne 0) { throw "Classic ClassPower runtime contract failed: $flavor" }
        Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/classic_classpower_enabled_smoke.lua") $root $flavor
        if ($LASTEXITCODE -ne 0) { throw "Classic ClassPower enabled routes failed: $flavor" }
    }
    Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/mainline_classpower_ooc_autohide_smoke.lua") $root
    if ($LASTEXITCODE -ne 0) { throw "Mainline ClassPower OOC auto-hide smoke failed" }
    $classicCastbarSmoke = Join-Path $root "tools/tests/classic_castbar_engine_smoke.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $classicCastbarSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic castbar engine smoke failed" }
    Invoke-GateSmoke $lua.Source $auraTestDriver (Join-Path $root "tools/tests/classic_transition_regression_smoke.lua") $root
    if ($LASTEXITCODE -ne 0) { throw "Classic transition regression failed" }
    $classicGroupRuntimeEventGateSmoke = Join-Path $root "tools/tests/classic_group_runtime_event_gate_smoke.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $classicGroupRuntimeEventGateSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic group runtime event gate smoke failed" }
    $classicCastbarVisualSmoke = Join-Path $root "tools/tests/classic_castbar_visual_compat_smoke.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $classicCastbarVisualSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic castbar visual compatibility smoke failed" }
    $classicCastbarLuaFillSmoke = Join-Path $root "tools/tests/classic_castbar_lua_fill_smoke.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $classicCastbarLuaFillSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic castbar Lua fill smoke failed" }
    $ptr1215RuntimeSmoke = Join-Path $root ".github/scripts/ptr_12_1_5_runtime_smoke.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $ptr1215RuntimeSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "PTR 12.1.5 runtime smoke failed" }
    $retail1210FallbackSmoke = Join-Path $root ".github/scripts/retail_12_1_0_fallback_smoke.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $retail1210FallbackSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Retail 12.1.0 fallback smoke failed" }
    $roundedHighlightSmoke = Join-Path $root ".github/scripts/rounded_border_highlight_smoke.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $roundedHighlightSmoke
    if ($LASTEXITCODE -ne 0) { throw "Rounded border highlight startup smoke failed" }
    Invoke-GateSmoke $lua.Source $auraTestDriver $roundedHighlightSmoke --startup-disabled
    if ($LASTEXITCODE -ne 0) { throw "Rounded border highlight enable smoke failed" }
    Invoke-GateSmoke $lua.Source $auraTestDriver (Join-Path $root ".github/scripts/rounded_forbidden_mask_owner_smoke.lua")
    if ($LASTEXITCODE -ne 0) { throw "Rounded native aura ownership smoke failed" }
    $castbarOwnershipSmoke = Join-Path $root "tools/castbar_refresh_ownership_smoke.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $castbarOwnershipSmoke
    if ($LASTEXITCODE -ne 0) { throw "Shared castbar refresh ownership smoke failed" }
    $auraFontFanoutSmoke = Join-Path $root "tools/aura_font_fanout_smoke.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $auraFontFanoutSmoke ($root -replace '\\', '/')
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
        Invoke-GateSmoke $lua.Source $auraTestDriver (Join-Path $root $arenaSmoke)
        if ($LASTEXITCODE -ne 0) { throw "Arena frame regression smoke failed: $arenaSmoke" }
    }
    $nicknameProviderSmoke = Join-Path $root "tools/nickname_provider_api_smoke.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $nicknameProviderSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic nickname provider API smoke failed" }
    $eliteClassificationSmoke = Join-Path $root ".github/scripts/tests/elite_indicator_classification_smoke.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $eliteClassificationSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Elite indicator classification smoke failed" }
    # Retail-shared smokes cover code Classic loads unchanged. They run through
    # the driver with the repository root only. The health, text and castbar-tint
    # parity smokes also accept a pre-refactor source root in arg[2]; that mode
    # asserts strictly less Lua work than the baseline, so it fits only a one-off
    # refactor review. No standing baseline exists: the Retail reference fails
    # those asserts by design, because identical code does equal work.
    foreach ($retailSharedSmoke in @(
        "tools/addon_interop_guard_smoke.lua",
        "tools/slash_command_registry_smoke.lua",
        ".github/scripts/health_background_sample_parity_smoke.lua",
        ".github/scripts/health_runtime_equivalence_smoke.lua",
        ".github/scripts/text_runtime_value_parity_smoke.lua",
        ".github/scripts/castbar_tint_parity_smoke.lua"
    )) {
        Invoke-GateSmoke $lua.Source $auraTestDriver (Join-Path $root $retailSharedSmoke) ($root -replace '\\', '/')
        if ($LASTEXITCODE -ne 0) { throw "Retail-shared runtime smoke failed: $retailSharedSmoke" }
    }
    foreach ($v604Smoke in @(
        "tools/aura_big_defensive_filter_smoke.lua",
        "tools/aura_group_slot_layer_smoke.lua",
        "tools/group_preview_roster_handoff_smoke.lua",
        "tools/unit_name_anchor_reflow_smoke.lua"
    )) {
        Invoke-GateSmoke $lua.Source $auraTestDriver (Join-Path $root $v604Smoke)
        if ($LASTEXITCODE -ne 0) { throw "v6.04 parity smoke failed: $v604Smoke" }
    }
    foreach ($clientVisualSmoke in @("classic_unit_availability_smoke.lua", "classic_portrait_gold_smoke.lua", "classic_minimap_click_smoke.lua")) {
        Invoke-GateSmoke $lua.Source $auraTestDriver (Join-Path $root ("tools/tests/" + $clientVisualSmoke))
        if ($LASTEXITCODE -ne 0) { throw "Classic unit/portrait regression failed: $clientVisualSmoke" }
    }
    $classicPredictionSmoke = Join-Path $root "tools/tests/classic_prediction_contract_smoke.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $classicPredictionSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic prediction contract smoke failed" }
    $classicAuraSmoke = Join-Path $root "tools/tests/classic_aura_backend_smoke.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $classicAuraSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic aura backend smoke failed" }
    $classicDispelSymbolSmoke = Join-Path $root "tools/tests/classic_dispel_symbol_chain_smoke.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $classicDispelSymbolSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic dispel symbol chain smoke failed" }
    $classicAuraMenuFilterSmoke = Join-Path $root "tools/tests/classic_aura_menu_filters_smoke.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $classicAuraMenuFilterSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic Aura menu filter smoke failed" }
    $classicAuraFeatureSmoke = Join-Path $root "tools/tests/classic_aura_features_smoke.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $classicAuraFeatureSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic aura feature compiler smoke failed" }
    $classicAuraCompileFilterSmoke = Join-Path $root "tools/tests/classic_aura_compile_filter_smoke.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $classicAuraCompileFilterSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic aura compile filter smoke failed" }
    $classicAuraAliasSmoke = Join-Path $root "tools/tests/classic_aura_alias_catalog_smoke.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $classicAuraAliasSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic aura alias catalog smoke failed" }
    $classicGroupDataSmoke = Join-Path $root "tools/tests/classic_group_indicator_data_smoke.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $classicGroupDataSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic group indicator data smoke failed" }
    $classicRaidManagerSmoke = Join-Path $root "tools/tests/classic_raid_manager_mode_smoke.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $classicRaidManagerSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic Raid Manager mode smoke failed" }
    $classicPetHappinessSmoke = Join-Path $root "tools/tests/classic_pet_happiness_smoke.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $classicPetHappinessSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic Pet Happiness smoke failed" }
    $classicRangeFadeSmoke = Join-Path $root "tools/tests/classic_range_fade_smoke.lua"
    Invoke-GateSmoke $lua.Source $classicRangeFadeSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic range fade smoke failed" }
    foreach ($flavor in $clientSuffixes) {
        Invoke-GateSmoke $lua.Source (Join-Path $root "tools/tests/classic_optional_integrations_smoke.lua") $root $flavor
        if ($LASTEXITCODE -ne 0) { throw "Optional integration contract failed: $flavor" }
    }
    $classicEditModeSmoke = Join-Path $root "tools/tests/classic_editmode_smoke.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $classicEditModeSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic Edit Mode smoke failed" }
    $arenaEditModeExitSmoke = Join-Path $root "tools/tests/arena_editmode_exit_restore_smoke.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $arenaEditModeExitSmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Arena Edit Mode exit restore smoke failed" }
    $classicMenuParitySmoke = Join-Path $root "tools/tests/classic_menu_retail_parity_smoke.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $classicMenuParitySmoke ($root -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic Menu2 Retail parity smoke failed" }
    $classicAuraRenderSmoke = Join-Path $root "tools/tests/classic_aura_render_smoke.lua"
    $classicAuraBackend = Join-Path $root "MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua"
    $classicAuraFeatures = Join-Path $root "MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_Features.lua"
    $classicAuraVisuals = Join-Path $root "MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_Visuals.lua"
    $classicAuraCore = Join-Path $root "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Core.lua"
    Invoke-GateSmoke $lua.Source $auraTestDriver $classicAuraRenderSmoke ($root -replace '\\', '/') `
        ($classicAuraBackend -replace '\\', '/') ($classicAuraFeatures -replace '\\', '/') `
        ($classicAuraCore -replace '\\', '/') ($classicAuraVisuals -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Classic aura live-render smoke failed" }
}

# Every tracked smoke either ran through Invoke-GateSmoke above or is retired
# with a recorded reason, so no smoke silently rots.
$retiredSmokes = [ordered]@{
    ".github/scripts/mapkoskin_menu_integration_contract.lua" = "runs only under the external tests/MapkoSkin/run.lua harness, which this repository does not contain"
    ".github/scripts/prediction_data_writer_parity_smoke.lua" = "compares against an immutable pre-refactor source root in arg[2]; a self-comparison fails by design"
}
$trackedSmokes = [Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
$trackedToolingPaths = @(& git -C $root ls-files -- tools .github 2>&1)
if ($LASTEXITCODE -ne 0) { throw "Unable to enumerate tracked smokes: $($trackedToolingPaths -join ', ')" }
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
# Without lua no Lua smoke ran; the preflight already recorded that skip.
if ($lua) {
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
Pop-Location
