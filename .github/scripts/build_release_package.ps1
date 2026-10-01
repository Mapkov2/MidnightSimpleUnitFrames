[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseVersion,

    [string]$OutputDirectory = "dist",

    [string]$PtrAddOnsPath,

    [switch]$KeepStage
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
Import-Module (Join-Path $PSScriptRoot "ClassicGate.Common.psm1") -Force
$optionsAddonName = "MidnightSimpleUnitFrames_Options"
function Assert-OptionsDirectoryContract {
    param([Parameter(Mandatory = $true)][string]$OptionsRoot)

    $root = [System.IO.Path]::GetFullPath($OptionsRoot)
    $tocPath = Join-Path $root "$optionsAddonName.toc"
    $menuRoot = Join-Path $root "Shell\Menu2"
    if (-not (Test-Path -LiteralPath $tocPath -PathType Leaf)) {
        throw "Options companion TOC is missing: $tocPath"
    }
    if (-not (Test-Path -LiteralPath $menuRoot -PathType Container)) {
        throw "Options companion is missing its physical Shell/Menu2 tree: $menuRoot"
    }

    $toc = Get-Content -LiteralPath $tocPath -Raw
    foreach ($marker in @('## LoadOnDemand: 1', '## Dependencies: MidnightSimpleUnitFrames')) {
        if ($toc.IndexOf($marker, [System.StringComparison]::Ordinal) -lt 0) {
            throw "Options companion TOC is missing required marker: $marker"
        }
    }
    if ($toc -match '(?im)^##\s*SavedVariables(?:PerCharacter)?\s*:') {
        throw "Options companion must not own SavedVariables; persistence remains core-owned."
    }
    if ($toc -match '(?:\.\.[\\/])') {
        throw "Options companion TOC must load only files owned by the Options addon."
    }

    $payload = @($toc -split '\r?\n' | ForEach-Object { $_.Trim().Replace('\', '/') } | Where-Object {
        $_ -and -not $_.StartsWith('##') -and -not $_.StartsWith('#')
    })
    if ($payload.Count -eq 0) {
        throw "Options companion TOC has no Lua/XML payload."
    }

    $prefix = $root.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    foreach ($ref in $payload) {
        if ($ref -notmatch '(?i)\.(?:lua|xml)$' -or $ref -match '(^|/)\.\.(/|$)' -or [System.IO.Path]::IsPathRooted($ref)) {
            throw "Unsafe or non-Lua/XML Options TOC reference: $ref"
        }
        $full = [System.IO.Path]::GetFullPath((Join-Path $root ($ref.Replace('/', [System.IO.Path]::DirectorySeparatorChar))))
        if (-not $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Options TOC reference escapes the companion: $ref"
        }
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
            throw "Options TOC references a missing file: $ref"
        }
    }
    return $payload
}

function Normalize-ReleaseVersion {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    $normalized = $Value.Trim()
    $normalized = $normalized -replace '^refs/tags/', ''
    $normalized = $normalized -replace '(?i)^MSUF[\s._-]*', ''
    $normalized = $normalized -replace '^v(?=\d)', ''
    if ($normalized -match '^(?<base>\d+(?:\.\d+)*)(?:[\s._-]*(?<channel>alpha|beta|preview|rc|pre|a|b)[\s._-]*(?<number>\d+(?:\.\d+)*))?\s*$') {
        $authoredBase = $Matches["base"]
        $base = (($Matches["base"] -split '\.') | ForEach-Object { [int]$_ }) -join "."
        # Stable-looking release tags are also the user-facing AddOn version.
        # Preserve authored zero padding (for example 6.01) while prerelease
        # tags retain the established normalized channel contract.
        if ([string]::IsNullOrWhiteSpace($Matches["channel"])) { return $authoredBase }
        $channel = $Matches["channel"].ToLowerInvariant()
        if ($channel -eq "a") { $channel = "alpha" }
        if ($channel -eq "b") { $channel = "beta" }
        $number = ""
        if (-not [string]::IsNullOrWhiteSpace($Matches["number"])) {
            $number = (($Matches["number"] -split '\.') | ForEach-Object { [int]$_ }) -join "."
        }
        return ($base + "-" + $channel + $number)
    }
    return $normalized
}

function Assert-WithinRepo {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $rootPrefix = $repoRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Description must remain inside the repository. Got: $fullPath"
    }
    return $fullPath
}

function Get-StagedRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$StageRoot,
        [Parameter(Mandatory = $true)][string]$FullName
    )

    $prefix = $StageRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $FullName.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the package stage: $FullName"
    }
    return $FullName.Substring($prefix.Length).Replace('\', '/')
}

function Remove-StagedItem {
    param(
        [Parameter(Mandatory = $true)][string]$StageRoot,
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) { return }
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $stagePrefix = $StageRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($stagePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a path outside the package stage: $fullPath"
    }
    Remove-Item -LiteralPath $fullPath -Recurse -Force
}

function Resolve-PtrAddOnsRoot {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $leaf = Split-Path -Leaf $fullPath
    $parentLeaf = Split-Path -Leaf (Split-Path -Parent $fullPath)
    if ($leaf -ne "AddOns" -or $parentLeaf -ne "Interface") {
        throw "PTR target must be an Interface\AddOns directory. Got: $fullPath"
    }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        throw "PTR Interface\AddOns directory does not exist: $fullPath"
    }
    return $fullPath
}

function Install-StageToPtr {
    param(
        [Parameter(Mandatory = $true)][string]$StageRoot,
        [Parameter(Mandatory = $true)][string]$AddOnsRoot,
        [Parameter(Mandatory = $true)][string[]]$AddonNames
    )

    $transactionRoot = Join-Path $AddOnsRoot (".msuf-stage-" + [System.Guid]::NewGuid().ToString("N"))
    $newRoot = Join-Path $transactionRoot "new"
    $oldRoot = Join-Path $transactionRoot "old"
    New-Item -ItemType Directory -Force -Path $newRoot, $oldRoot | Out-Null
    $installed = New-Object System.Collections.Generic.List[string]
    try {
        foreach ($addonName in $AddonNames) {
            Copy-Item -LiteralPath (Join-Path $StageRoot $addonName) -Destination $newRoot -Recurse -Force
            $stagedToc = Join-Path (Join-Path $newRoot $addonName) ($addonName + ".toc")
            if (-not (Test-Path -LiteralPath $stagedToc -PathType Leaf)) {
                throw "PTR transaction is missing staged TOC: $stagedToc"
            }
        }

        foreach ($addonName in $AddonNames) {
            $destination = Join-Path $AddOnsRoot $addonName
            $oldDestination = Join-Path $oldRoot $addonName
            if (Test-Path -LiteralPath $destination) {
                Move-Item -LiteralPath $destination -Destination $oldDestination
            }
            Move-Item -LiteralPath (Join-Path $newRoot $addonName) -Destination $destination
            $installed.Add($addonName)
        }
    } catch {
        for ($index = $installed.Count - 1; $index -ge 0; $index--) {
            $addonName = $installed[$index]
            $destination = Join-Path $AddOnsRoot $addonName
            if (Test-Path -LiteralPath $destination) {
                Remove-StagedItem -StageRoot $AddOnsRoot -Path $destination
            }
        }
        foreach ($addonName in $AddonNames) {
            $oldDestination = Join-Path $oldRoot $addonName
            $destination = Join-Path $AddOnsRoot $addonName
            if (Test-Path -LiteralPath $oldDestination) {
                Move-Item -LiteralPath $oldDestination -Destination $destination
            }
        }
        throw
    } finally {
        if (Test-Path -LiteralPath $transactionRoot) {
            Remove-StagedItem -StageRoot $AddOnsRoot -Path $transactionRoot
        }
    }

    Write-Host "Installed the validated core and Options addons into $AddOnsRoot"
}

function Read-ZipEntryText {
    param(
        [Parameter(Mandatory = $true)]$Zip,
        [Parameter(Mandatory = $true)][string]$EntryName
    )

    $entry = $Zip.Entries | Where-Object {
        $_.FullName.Replace('\', '/') -eq $EntryName
    } | Select-Object -First 1
    if (-not $entry) { throw "Release zip is missing required path: $EntryName" }
    $stream = $entry.Open()
    try {
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true)
        try {
            return $reader.ReadToEnd()
        } finally {
            $reader.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

$release = Normalize-ReleaseVersion $ReleaseVersion
if ([string]::IsNullOrWhiteSpace($release)) {
    throw "Release version cannot be empty."
}

$addonNames = @(
    "MidnightSimpleUnitFrames",
    $optionsAddonName
)
$tocRelativePaths = @(
    "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames.toc",
    "$optionsAddonName/$optionsAddonName.toc"
)
$requiredSourcePaths = @(
    "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames.toc",
    "MidnightSimpleUnitFrames/Locales/deDE.lua",
    "$optionsAddonName/$optionsAddonName.toc",
    "$optionsAddonName/Shell/Menu2/MSUF_Menu2.xml"
)
foreach ($relativePath in $requiredSourcePaths) {
    $sourcePath = Join-Path $repoRoot ($relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Required release source is missing: $relativePath"
    }
}
# tools/classic-addon-tombstones.txt names the retired addons and the retired
# files of the shipped ones; git, not a folder test, decides what is present.
$tombstones = Import-MsufAddonTombstones -Path (Join-Path $repoRoot "tools/classic-addon-tombstones.txt") -ShippedAddons $addonNames
$sourceLoadedPaths = @(foreach ($relativePath in $tocRelativePaths) {
    (Get-MsufLoadGraph -Path (Join-Path $repoRoot $relativePath) -Duplicates Skip).AllPaths
})
Assert-MsufAddonTombstones -Root $repoRoot -Tombstones $tombstones -LoadedPaths ([string[]]$sourceLoadedPaths)
$optionsSourceRoot = Join-Path $repoRoot $optionsAddonName
$optionsTocPayload = @(Assert-OptionsDirectoryContract -OptionsRoot $optionsSourceRoot)
$coreMenuRoot = Join-Path $repoRoot "MidnightSimpleUnitFrames\Shell\Menu2"
if (Test-Path -LiteralPath $coreMenuRoot) {
    throw "Menu2 must be physically owned by the Options companion; core tree found: $coreMenuRoot"
}
function Test-RetiredReference {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    foreach ($addon in $tombstones.Addons) {
        if ($Text.IndexOf($addon, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $addon }
    }
    foreach ($retiredPath in $tombstones.Paths) {
        $leaf = [System.IO.Path]::GetFileName($retiredPath)
        if ($Text.IndexOf($leaf, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $retiredPath }
    }
    return $null
}
$menuXml = Get-Content -LiteralPath (Join-Path $optionsSourceRoot "Shell\Menu2\MSUF_Menu2.xml") -Raw
$retiredReference = Test-RetiredReference -Text $menuXml
if ($retiredReference) {
    throw "Options Menu2 still names a retired addon or file: $retiredReference"
}
$outputPath = Assert-WithinRepo (Join-Path $repoRoot $OutputDirectory) "Output directory"
$stagePath = Assert-WithinRepo (Join-Path $outputPath "package") "Package stage"
New-Item -ItemType Directory -Force -Path $outputPath | Out-Null
if (Test-Path -LiteralPath $stagePath) {
    Remove-StagedItem -StageRoot $outputPath -Path $stagePath
}
New-Item -ItemType Directory -Force -Path $stagePath | Out-Null

foreach ($addonName in $addonNames) {
    Copy-Item -LiteralPath (Join-Path $repoRoot $addonName) -Destination $stagePath -Recurse -Force
}

# Keep local files out of the addon package.
$explicitExclusions = @(
    "MidnightSimpleUnitFrames/docs",
    "MidnightSimpleUnitFrames/scripts",
    "MidnightSimpleUnitFrames/tools",
    "MidnightSimpleUnitFrames/.gitignore",
    "MidnightSimpleUnitFrames/luac.out",
    "MidnightSimpleUnitFrames/MSUF_PerfyHook.lua",
    "MidnightSimpleUnitFrames/Shell/Menu2"
)
foreach ($relativePath in $explicitExclusions) {
    Remove-StagedItem -StageRoot $stagePath -Path (Join-Path $stagePath ($relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)))
}

# Hidden folders (version control, editor and tool state) never ship, whatever
# tool created them; the named ones are local work folders.
$localDirectoryNames = @(
    "_local_workflows",
    "graphify-out",
    "__pycache__",
    "_backups",
    "backups",
    "docs",
    "scripts",
    "tools"
)
$localDirectories = @(Get-ChildItem -LiteralPath $stagePath -Directory -Force -Recurse | Where-Object {
    $_.Name.StartsWith('.') -or ($localDirectoryNames -contains $_.Name) -or ($_.Name -match '(?i)^graphify(?:[-_.].*)?$')
} | Sort-Object { $_.FullName.Length } -Descending)
foreach ($directory in $localDirectories) {
    Remove-StagedItem -StageRoot $stagePath -Path $directory.FullName
}

$localFiles = @(Get-ChildItem -LiteralPath $stagePath -File -Force -Recurse | Where-Object {
    $_.Name -match '(?i)^(?:\.DS_Store|\.gitignore|\.pkgmeta|Thumbs\.db|desktop\.ini|luac\.out|graph\.json|GRAPH_REPORT\.md|\.graphify.*|.*\.(?:html?|md)|.*\.py[co])$'
})
foreach ($file in $localFiles) {
    Remove-StagedItem -StageRoot $stagePath -Path $file.FullName
}

$stagedOptionsRoot = Join-Path $stagePath $optionsAddonName
$stagedOptionsTocPayload = @(Assert-OptionsDirectoryContract -OptionsRoot $stagedOptionsRoot)
if (($stagedOptionsTocPayload -join "`n") -ne ($optionsTocPayload -join "`n")) {
    throw "Staged Options TOC payload differs from the validated source TOC."
}

$actualTocPaths = @(Get-ChildItem -LiteralPath $stagePath -Filter "*.toc" -File -Recurse)
$actualTocRelativePaths = @($actualTocPaths | ForEach-Object {
    Get-StagedRelativePath -StageRoot $stagePath -FullName $_.FullName
} | Sort-Object)
$expectedTocRelativePaths = @($tocRelativePaths | Sort-Object)
if (($actualTocRelativePaths -join "`n") -ne ($expectedTocRelativePaths -join "`n")) {
    throw "Release stage TOCs do not match the two-addon contract. Expected [$($expectedTocRelativePaths -join ', ')], got [$($actualTocRelativePaths -join ', ')]."
}

$versionPattern = New-Object System.Text.RegularExpressions.Regex('(?m)^##\s*Version:\s*.*$')
foreach ($relativePath in $tocRelativePaths) {
    $tocPath = Join-Path $stagePath ($relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
    $tocContent = Get-Content -LiteralPath $tocPath -Raw
    if (-not $versionPattern.IsMatch($tocContent)) {
        throw "No TOC version line found in $relativePath."
    }
    $tocContent = $versionPattern.Replace($tocContent, "## Version: $release", 1)
    [System.IO.File]::WriteAllText($tocPath, $tocContent, (New-Object System.Text.UTF8Encoding($false)))
}

$fileVersion = $release -replace '[\\/:*?"<>|]', '-'
$zipPath = Assert-WithinRepo (Join-Path $outputPath "MidnightSimpleUnitFrames$fileVersion.zip") "Release zip"
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

Get-ChildItem -LiteralPath $stagePath | Compress-Archive -DestinationPath $zipPath -Force

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $entries = @($zip.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
    $requiredZipEntries = @($requiredSourcePaths)
    foreach ($requiredEntry in $requiredZipEntries) {
        if ($entries -notcontains $requiredEntry) {
            throw "Release zip is missing required path: $requiredEntry"
        }
    }

    $topLevelDirectories = @($entries | ForEach-Object { ($_ -split '/', 2)[0] } | Where-Object { $_ } | Sort-Object -Unique)
    if (($topLevelDirectories -join "`n") -ne (@($addonNames | Sort-Object) -join "`n")) {
        throw "Release zip contains unexpected top-level paths: $($topLevelDirectories -join ', ')"
    }
    $retiredEntry = $entries | Where-Object {
        $entry = $_
        @($tombstones.Addons | Where-Object { $entry.StartsWith($_ + '/', [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0 -or
            @($tombstones.Paths | Where-Object { $entry -ieq $_ }).Count -gt 0
    } | Select-Object -First 1
    if ($retiredEntry) {
        throw "Release zip contains a retired addon or file: $retiredEntry"
    }

    $forbiddenEntry = $entries | Where-Object {
        ($_ -match '(?i)(^|/)(?:\.[^/]+|docs|scripts|tools|_local_workflows|graphify(?:[-_.][^/]*)?|__pycache__|_?backups)(?:/|$)') -or
        ($_ -match '(?i)(^|/)MSUF_Perfy(?:Hook|FPS)?\.lua$') -or
        ($_ -match '(?i)^MidnightSimpleUnitFrames/Shell/Menu2(?:/|$)') -or
        ($_ -match '(?i)(?:^|/)(?:\.DS_Store|\.gitignore|\.pkgmeta|Thumbs\.db|desktop\.ini|luac\.out|graph\.json|GRAPH_REPORT\.md|\.graphify.*|.*\.(?:html?|md)|.*\.py[co])$')
    } | Select-Object -First 1
    if ($forbiddenEntry) {
        throw "Release zip contains a forbidden profiling, Graphify, backup, documentation, mockup, or local-only path: $forbiddenEntry"
    }

    foreach ($tocEntry in $tocRelativePaths) {
        $tocContent = Read-ZipEntryText -Zip $zip -EntryName $tocEntry
        $tocVersionMatch = [regex]::Match($tocContent, '(?m)^##\s*Version:\s*(.+?)\s*$')
        if (-not $tocVersionMatch.Success -or $tocVersionMatch.Groups[1].Value.Trim() -ne $release) {
            throw "Packaged TOC version mismatch in $tocEntry. Expected '$release'."
        }
    }

    $optionsToc = Read-ZipEntryText -Zip $zip -EntryName "$optionsAddonName/$optionsAddonName.toc"
    foreach ($requiredMarker in @(
        '## LoadOnDemand: 1',
        '## Dependencies: MidnightSimpleUnitFrames'
    )) {
        if ($optionsToc.IndexOf($requiredMarker, [System.StringComparison]::Ordinal) -lt 0) {
            throw "Options companion TOC is missing required LoD marker: $requiredMarker"
        }
    }
    if ($optionsToc -match '(?im)^##\s*SavedVariables(?:PerCharacter)?\s*:') {
        throw "Packaged Options companion must not own SavedVariables."
    }
    if ($optionsToc -match '(?:\.\.[\\/])') {
        throw "Packaged Options TOC must load only files owned by the Options addon."
    }
    $packagedOptionsTocPayload = @($optionsToc -split '\r?\n' | ForEach-Object { $_.Trim().Replace('\', '/') } | Where-Object {
        $_ -and -not $_.StartsWith('##') -and -not $_.StartsWith('#')
    })
    if (($packagedOptionsTocPayload -join "`n") -ne ($optionsTocPayload -join "`n")) {
        throw "Packaged Options TOC payload differs from the validated source TOC."
    }
    $packagedMenuXml = Read-ZipEntryText -Zip $zip -EntryName "$optionsAddonName/Shell/Menu2/MSUF_Menu2.xml"
    $retiredReference = Test-RetiredReference -Text $packagedMenuXml
    if ($retiredReference) {
        throw "Packaged Options menu still names a retired addon or file: $retiredReference"
    }

} finally {
    $zip.Dispose()
}

if (-not [string]::IsNullOrWhiteSpace($PtrAddOnsPath)) {
    $ptrRoot = Resolve-PtrAddOnsRoot -Path $PtrAddOnsPath
    Install-StageToPtr -StageRoot $stagePath -AddOnsRoot $ptrRoot -AddonNames $addonNames
}

if (-not $KeepStage) {
    Remove-StagedItem -StageRoot $outputPath -Path $stagePath
}

Write-Host "Validated ${zipPath}: two addons, two stamped TOCs, Options LoD ownership, and no retired addon, retired file or local artifact."
Write-Output $zipPath
