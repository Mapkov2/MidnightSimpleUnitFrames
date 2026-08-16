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
$assistantManifestName = "MSUF_AssistantRuntime.xml"
$assistantScriptCount = 326
$assistantOrderSha256 = "BEB30AD29FBB59BC56848EEDDA00B7D8F746277128BFA3677FC543BF1953E13D"
$optionsAddonName = "MidnightSimpleUnitFrames_Options"
$changelogHistoryFloor = "6.02"

function Normalize-AssistantReference {
    param([Parameter(Mandatory = $true)][string]$Path)
    return $Path.Trim().Replace('\', '/')
}

function Get-AssistantReferenceHash {
    param([Parameter(Mandatory = $true)][string[]]$References)

    $payload = (@($References | ForEach-Object { Normalize-AssistantReference $_ }) -join "`n")
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($payload)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
    } finally {
        $sha.Dispose()
    }
}

function Get-AssistantManifestReferences {
    param([Parameter(Mandatory = $true)][string]$ManifestText)

    return @([regex]::Matches($ManifestText, '<Script\s+file="([^"]+)"') | ForEach-Object {
        Normalize-AssistantReference $_.Groups[1].Value
    })
}

function Assert-AssistantDirectoryContract {
    param([Parameter(Mandatory = $true)][string]$AssistantRoot)

    $root = [System.IO.Path]::GetFullPath($AssistantRoot)
    $tocPath = Join-Path $root "MidnightSimpleUnitFrames_Assistant.toc"
    $manifestPath = Join-Path $root $assistantManifestName
    foreach ($path in @($tocPath, $manifestPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Assistant V1 companion contract is missing: $path"
        }
    }

    $toc = Get-Content -LiteralPath $tocPath -Raw
    foreach ($marker in @('## LoadOnDemand: 1', '## Dependencies: MidnightSimpleUnitFrames')) {
        if ($toc.IndexOf($marker, [System.StringComparison]::Ordinal) -lt 0) {
            throw "Assistant companion TOC is missing required marker: $marker"
        }
    }
    if ($toc -match '(?:\.\.[\\/])') { throw "Assistant companion TOC must load only its local manifest." }
    $tocPayload = @($toc -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object {
        $_ -and -not $_.StartsWith('##') -and -not $_.StartsWith('#')
    })
    if (($tocPayload -join "`n") -ne $assistantManifestName) {
        throw "Assistant companion TOC must load exactly '$assistantManifestName'. Got: $($tocPayload -join ', ')"
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw
    $refs = Get-AssistantManifestReferences -ManifestText $manifest
    if ($refs.Count -ne $assistantScriptCount) {
        throw "Assistant V1 manifest must contain exactly $assistantScriptCount scripts; found $($refs.Count)."
    }
    if (($refs | Sort-Object -Unique).Count -ne $refs.Count) {
        throw "Assistant V1 manifest contains duplicate script references."
    }
    $hash = Get-AssistantReferenceHash -References $refs
    if ($hash -ne $assistantOrderSha256) {
        throw "Assistant V1 manifest inventory/load-order hash mismatch. Expected $assistantOrderSha256, got $hash."
    }

    $prefix = $root.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    foreach ($ref in $refs) {
        if ($ref -notmatch '(?i)\.lua$' -or $ref -match '(^|/)\.\.(/|$)' -or [System.IO.Path]::IsPathRooted($ref)) {
            throw "Unsafe or non-Lua Assistant manifest reference: $ref"
        }
        $full = [System.IO.Path]::GetFullPath((Join-Path $root ($ref.Replace('/', [System.IO.Path]::DirectorySeparatorChar))))
        if (-not $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Assistant manifest reference escapes the companion: $ref"
        }
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
            throw "Assistant manifest references a missing runtime file: $ref"
        }
    }

    $actual = @(Get-ChildItem -LiteralPath $root -File -Force -Recurse | ForEach-Object {
        $_.FullName.Substring($prefix.Length).Replace('\', '/')
    } | Sort-Object)
    $expected = @(@("MidnightSimpleUnitFrames_Assistant.toc", $assistantManifestName) + @($refs) | Sort-Object)
    if (($actual -join "`n") -ne ($expected -join "`n")) {
        $unexpected = @($actual | Where-Object { $_ -notin $expected })
        $missing = @($expected | Where-Object { $_ -notin $actual })
        throw "Assistant companion inventory mismatch. Unexpected: [$($unexpected -join ', ')]. Missing: [$($missing -join ', ')]."
    }
    return $refs
}

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

function Get-Menu2SourceSha256 {
    param([Parameter(Mandatory = $true)][string]$OptionsRoot)

    $sourceRoot = [System.IO.Path]::GetFullPath((Join-Path $OptionsRoot "Shell\Menu2"))
    $generatedPath = [System.IO.Path]::GetFullPath((Join-Path $sourceRoot "Search\MSUF_Menu2_Search_StaticIndex_Data.lua"))
    $files = @(Get-ChildItem -LiteralPath $sourceRoot -File -Recurse | Where-Object {
        ($_.Extension -ieq ".lua" -or $_.Extension -ieq ".xml") -and
        [System.IO.Path]::GetFullPath($_.FullName) -ine $generatedPath
    })
    [System.Array]::Sort($files, [System.Comparison[object]]{
        param($left, $right)
        $leftRelative = $left.FullName.Substring($sourceRoot.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
        $rightRelative = $right.FullName.Substring($sourceRoot.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
        return [System.StringComparer]::Ordinal.Compare($leftRelative, $rightRelative)
    })
    $hash = [System.Security.Cryptography.IncrementalHash]::CreateHash(
        [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    try {
        foreach ($file in $files) {
            $relative = $file.FullName.Substring($sourceRoot.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
            $hash.AppendData($utf8.GetBytes($relative))
            $hash.AppendData([byte[]](0))
            $content = [System.IO.File]::ReadAllText($file.FullName).Replace("`r`n", "`n").Replace("`r", "`n")
            $hash.AppendData($utf8.GetBytes($content))
            $hash.AppendData([byte[]](0))
        }
        return ([System.BitConverter]::ToString($hash.GetHashAndReset())).Replace('-', '')
    } finally {
        $hash.Dispose()
    }
}

function Get-StaticSearchIdentity {
    param(
        [Parameter(Mandatory = $true)][string]$PageKey,
        [Parameter(Mandatory = $true)][string]$ControlId
    )

    $separator = [string][char]31
    $encodedControlId = $ControlId.Replace('%', '%25').Replace($separator, '%1F').Replace('.', '%2E')
    return "id$separator$PageKey$separator$encodedControlId"
}

function Get-JsonStringProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return "" }
    return ([string]$property.Value).Trim()
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

    Write-Host "Installed the validated core and LoD Assistant companion into $AddOnsRoot"
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
    "MidnightSimpleUnitFrames_Assistant",
    $optionsAddonName
)
$tocRelativePaths = @(
    "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames.toc",
    "MidnightSimpleUnitFrames_Assistant/MidnightSimpleUnitFrames_Assistant.toc",
    "$optionsAddonName/$optionsAddonName.toc"
)
$requiredSourcePaths = @(
    "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames.toc",
    "MidnightSimpleUnitFrames/Locales/deDE.lua",
    "MidnightSimpleUnitFrames_Assistant/MidnightSimpleUnitFrames_Assistant.toc",
    "MidnightSimpleUnitFrames_Assistant/$assistantManifestName",
    "$optionsAddonName/$optionsAddonName.toc",
    "$optionsAddonName/State/MSUF_ChangelogFull.lua",
    "$optionsAddonName/Shell/Menu2/MSUF_Menu2.xml"
)

foreach ($relativePath in $requiredSourcePaths) {
    $sourcePath = Join-Path $repoRoot ($relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Required release source is missing: $relativePath"
    }
}
$assistantSourceRoot = Join-Path $repoRoot "MidnightSimpleUnitFrames_Assistant"
$assistantManifestRefs = @(Assert-AssistantDirectoryContract -AssistantRoot $assistantSourceRoot)
$optionsSourceRoot = Join-Path $repoRoot $optionsAddonName
$optionsTocPayload = @(Assert-OptionsDirectoryContract -OptionsRoot $optionsSourceRoot)
$coreMenuRoot = Join-Path $repoRoot "MidnightSimpleUnitFrames\Shell\Menu2"
if (Test-Path -LiteralPath $coreMenuRoot) {
    throw "Menu2 must be physically owned by the Options companion; core tree found: $coreMenuRoot"
}
$sourceMenuRoot = Join-Path $optionsSourceRoot "Shell\Menu2"
foreach ($forbiddenCorePath in @(
    (Join-Path $sourceMenuRoot "Assistant"),
    (Join-Path $sourceMenuRoot "MSUF_Menu2_AssistantRuntime.xml"),
    (Join-Path $sourceMenuRoot "MSUF_Menu2_AssistantDialogLocale.lua"),
    (Join-Path $sourceMenuRoot "MSUF_Menu2_AssistantDialogLocale_Data.lua")
)) {
    if (Test-Path -LiteralPath $forbiddenCorePath) {
        throw "Assistant V1 must be owned only by the companion; core artifact found: $forbiddenCorePath"
    }
}

$sourceV2Artifacts = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot "MidnightSimpleUnitFrames"), $assistantSourceRoot, $optionsSourceRoot -Recurse -Force |
    Where-Object { $_.Name -match '(?i)AssistantV2' })
if ($sourceV2Artifacts.Count -gt 0) {
    throw "Assistant V2 runtime artifacts are forbidden: $($sourceV2Artifacts.FullName -join ', ')"
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

# Assistant V1 is physically owned by the LoadOnDemand companion. Any copy
# below the core addon would silently defeat that ownership contract.
$explicitExclusions = @(
    "MidnightSimpleUnitFrames/.codex-remote-attachments",
    "MidnightSimpleUnitFrames/docs",
    "MidnightSimpleUnitFrames/scripts",
    "MidnightSimpleUnitFrames/tools",
    "MidnightSimpleUnitFrames/.gitignore",
    "MidnightSimpleUnitFrames/luac.out",
    "MidnightSimpleUnitFrames/MSUF_PerfyHook.lua",
    "MidnightSimpleUnitFrames/Shell/Menu2",
    "$optionsAddonName/Shell/Menu2/Assistant",
    "$optionsAddonName/Shell/Menu2/MSUF_Menu2_AssistantRuntime.xml",
    "$optionsAddonName/Shell/Menu2/MSUF_Menu2_AssistantDialogLocale.lua",
    "$optionsAddonName/Shell/Menu2/MSUF_Menu2_AssistantDialogLocale_Data.lua"
)
foreach ($relativePath in $explicitExclusions) {
    Remove-StagedItem -StageRoot $stagePath -Path (Join-Path $stagePath ($relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)))
}

$localDirectoryNames = @(
    ".codex-remote-attachments",
    ".agents",
    ".codex",
    ".git",
    ".github",
    ".idea",
    ".vscode",
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
    ($localDirectoryNames -contains $_.Name) -or ($_.Name -match '(?i)^graphify(?:[-_.].*)?$')
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

# Exact changelog navigation is tied to the real controls built by Menu2. The
# generated index records each control's page, containing section, and supported
# preparation hooks. Its source hash makes stale control contracts impossible to
# package after any Menu2 Lua/XML change.
$stagedOptionsRoot = Join-Path $stagePath $optionsAddonName
$stagedStaticIndexPath = Join-Path $stagedOptionsRoot "Shell\Menu2\Search\MSUF_Menu2_Search_StaticIndex_Data.lua"
if (-not (Test-Path -LiteralPath $stagedStaticIndexPath -PathType Leaf)) {
    throw "Release package is missing the Menu2 static control index: $stagedStaticIndexPath"
}
$staticIndexSourceHash = Get-Menu2SourceSha256 -OptionsRoot $stagedOptionsRoot
$staticIndexContent = Get-Content -LiteralPath $stagedStaticIndexPath -Raw
if ($staticIndexContent.IndexOf("Search.StaticIndexSourceSha256 = `"$staticIndexSourceHash`"", [System.StringComparison]::Ordinal) -lt 0) {
    throw "Menu2 static control index is stale. Regenerate it after the latest Menu2 changes before pushing the release."
}
$staticRowsByIdentity = @{}
foreach ($staticLine in ($staticIndexContent -split '\r?\n')) {
    $fields = @($staticLine -split "`t", 12)
    if ($fields.Count -ne 12 -or -not $fields[7].StartsWith("id$([char]31)", [System.StringComparison]::Ordinal)) {
        continue
    }
    if ($staticRowsByIdentity.ContainsKey($fields[7])) {
        throw "Menu2 static control index contains duplicate exact identity: $($fields[7])"
    }
    $staticRowsByIdentity[$fields[7]] = [pscustomobject]@{
        PageKey = $fields[0]
        SettingKey = $fields[3]
        SectionId = $fields[8]
        PrepareKinds = $fields[9]
        PrepareContracts = $fields[10]
    }
}

# A release push is allowed only when the committed compact and full changelog
# payloads were regenerated from this exact CHANGELOG.md. The local generator
# records the source hash in both files; CI stays independent from local tools.
$changelogSourcePath = Join-Path $repoRoot "CHANGELOG.md"
$changelogText = [System.IO.File]::ReadAllText($changelogSourcePath).Replace("`r`n", "`n").Replace("`r", "`n")
$changelogHash = [System.Security.Cryptography.SHA256]::Create()
try {
    $changelogSourceHash = ([System.BitConverter]::ToString(
        $changelogHash.ComputeHash(([System.Text.UTF8Encoding]::new($false)).GetBytes($changelogText))
    )).Replace('-', '')
} finally {
    $changelogHash.Dispose()
}
$stagedChangelogPaths = @(
    (Join-Path $stagePath "MidnightSimpleUnitFrames/State/MSUF_Changelog.lua"),
    (Join-Path $stagePath "$optionsAddonName/State/MSUF_ChangelogFull.lua")
)
foreach ($stagedChangelogPath in $stagedChangelogPaths) {
    $payload = Get-Content -LiteralPath $stagedChangelogPath -Raw
    if ($payload.IndexOf("sourceSha256 = `"$changelogSourceHash`"", [System.StringComparison]::Ordinal) -lt 0) {
        throw "Bundled changelog is stale: $stagedChangelogPath. Regenerate it from CHANGELOG.md before pushing the release."
    }
}
$stagedFullChangelogPayload = Get-Content -LiteralPath $stagedChangelogPaths[1] -Raw
if ($stagedFullChangelogPayload.IndexOf("historyFromVersion = `"$changelogHistoryFloor`"", [System.StringComparison]::Ordinal) -lt 0) {
    throw "Bundled full changelog must contain only releases from $changelogHistoryFloor through the current release."
}

# Every bullet in the current release's Highlights section must carry the
# invisible JSON route consumed by See New Features. This keeps the visible
# platform changelog clean while making the highlight sentence itself a direct
# Menu2 hyperlink.
$changelogLines = Get-Content -LiteralPath $changelogSourcePath -Encoding UTF8
$currentReleaseStart = -1
for ($lineIndex = 0; $lineIndex -lt $changelogLines.Count; $lineIndex++) {
    if ($changelogLines[$lineIndex] -match '^##\s+(.+?)(?:\s+-\s+[0-9]{4}-[0-9]{2}-[0-9]{2})?\s*$' -and
        (Normalize-ReleaseVersion $Matches[1]) -eq $release) {
        $currentReleaseStart = $lineIndex
        break
    }
}
if ($currentReleaseStart -lt 0) {
    throw "CHANGELOG.md has no release section matching '$release'."
}
$inHighlights = $false
for ($lineIndex = $currentReleaseStart + 1; $lineIndex -lt $changelogLines.Count; $lineIndex++) {
    $line = $changelogLines[$lineIndex]
    if ($line -match '^##\s+') { break }
    if ($line -match '^###\s+(.+?)\s*$') {
        $inHighlights = $Matches[1] -match '(?i)^Highlights$'
        continue
    }
    if (-not $inHighlights -or $line -notmatch '^\s*-\s+(.+?)\s*$') { continue }
    $bulletText = $Matches[1]
    $nextLine = if (($lineIndex + 1) -lt $changelogLines.Count) { $changelogLines[$lineIndex + 1] } else { "" }
    if ($nextLine -notmatch '^\s*<!--\s*msuf-menu-link:\s*(\{.+\})\s*-->\s*$') {
        throw "Current Highlights bullet has no msuf-menu-link metadata: $bulletText"
    }
    try {
        $menuLink = $Matches[1] | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Current Highlights bullet has invalid msuf-menu-link JSON near CHANGELOG.md line $($lineIndex + 2): $($_.Exception.Message)"
    }
    $pageKey = Get-JsonStringProperty -Object $menuLink -Name "pageKey"
    $query = Get-JsonStringProperty -Object $menuLink -Name "query"
    $label = Get-JsonStringProperty -Object $menuLink -Name "label"
    $sectionId = Get-JsonStringProperty -Object $menuLink -Name "sectionId"
    $controlId = Get-JsonStringProperty -Object $menuLink -Name "controlId"
    $settingKey = Get-JsonStringProperty -Object $menuLink -Name "settingKey"
    $prepareKind = Get-JsonStringProperty -Object $menuLink -Name "prepareKind"
    $prepareValue = Get-JsonStringProperty -Object $menuLink -Name "prepareValue"
    if ([string]::IsNullOrWhiteSpace($pageKey) -or
        [string]::IsNullOrWhiteSpace($query) -or
        [string]::IsNullOrWhiteSpace($label) -or
        [string]::IsNullOrWhiteSpace($sectionId) -or
        [string]::IsNullOrWhiteSpace($controlId) -or
        [string]::IsNullOrWhiteSpace($settingKey)) {
        throw "Current Highlights msuf-menu-link requires pageKey, query, label, sectionId, controlId, and settingKey near CHANGELOG.md line $($lineIndex + 2)."
    }
    if ($pageKey -notmatch '^[A-Za-z0-9_.-]+$' -or
        $sectionId -notmatch '^[A-Za-z0-9_.-]+$' -or
        $controlId -notmatch '^menu2\.[A-Za-z0-9_.-]+$' -or
        $settingKey -notmatch '^[A-Za-z0-9_.-]+$') {
        throw "Current Highlights msuf-menu-link has an invalid exact target identifier near CHANGELOG.md line $($lineIndex + 2)."
    }
    if ([string]::IsNullOrWhiteSpace($prepareKind) -ne [string]::IsNullOrWhiteSpace($prepareValue)) {
        throw "Current Highlights msuf-menu-link must provide prepareKind and prepareValue together near CHANGELOG.md line $($lineIndex + 2)."
    }
    if (-not [string]::IsNullOrWhiteSpace($prepareKind) -and $prepareKind -notmatch '^[A-Za-z0-9_.-]+$') {
        throw "Current Highlights msuf-menu-link has an invalid prepareKind near CHANGELOG.md line $($lineIndex + 2)."
    }

    $identity = Get-StaticSearchIdentity -PageKey $pageKey -ControlId $controlId
    $staticRow = $staticRowsByIdentity[$identity]
    if ($null -eq $staticRow) {
        throw "Current Highlights exact control does not exist on page '$pageKey': $controlId"
    }
    if ($staticRow.SectionId -cne $sectionId) {
        throw "Current Highlights section mismatch for '$controlId': changelog '$sectionId', runtime '$($staticRow.SectionId)'."
    }
    if ($staticRow.SettingKey -and $staticRow.SettingKey -cne $settingKey) {
        throw "Current Highlights setting mismatch for '$controlId': changelog '$settingKey', runtime '$($staticRow.SettingKey)'."
    }
    if (-not $staticRow.SettingKey -and [string]::IsNullOrWhiteSpace($prepareKind)) {
        throw "Current Highlights dynamic control '$controlId' requires an explicit prepareKind/prepareValue contract."
    }
    if (-not [string]::IsNullOrWhiteSpace($prepareKind)) {
        $supportedPrepareKinds = @($staticRow.PrepareKinds -split ',' | Where-Object { $_ })
        if ($prepareKind -cnotin $supportedPrepareKinds) {
            throw "Current Highlights prepareKind '$prepareKind' is not supported by runtime control '$controlId'."
        }
        $expectedPrepareContract = "$prepareKind=$prepareValue=$settingKey"
        $supportedPrepareContracts = @($staticRow.PrepareContracts -split '\|' | Where-Object { $_ })
        if ($expectedPrepareContract -cnotin $supportedPrepareContracts) {
            throw "Current Highlights subcategory contract '$expectedPrepareContract' is not supported by runtime control '$controlId'."
        }
    }
}

$stagedAssistantRoot = Join-Path $stagePath "MidnightSimpleUnitFrames_Assistant"
$stagedManifestRefs = @(Assert-AssistantDirectoryContract -AssistantRoot $stagedAssistantRoot)
if (($stagedManifestRefs -join "`n") -ne ($assistantManifestRefs -join "`n")) {
    throw "Staged Assistant V1 manifest differs from the validated source manifest."
}
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
    throw "Release stage TOCs do not match the three-addon contract. Expected [$($expectedTocRelativePaths -join ', ')], got [$($actualTocRelativePaths -join ', ')]."
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
    $requiredZipEntries = @($requiredSourcePaths) + @($assistantManifestRefs | ForEach-Object {
        "MidnightSimpleUnitFrames_Assistant/$_"
    })
    foreach ($requiredEntry in $requiredZipEntries) {
        if ($entries -notcontains $requiredEntry) {
            throw "Release zip is missing required path: $requiredEntry"
        }
    }

    $topLevelDirectories = @($entries | ForEach-Object { ($_ -split '/', 2)[0] } | Where-Object { $_ } | Sort-Object -Unique)
    if (($topLevelDirectories -join "`n") -ne (@($addonNames | Sort-Object) -join "`n")) {
        throw "Release zip contains unexpected top-level paths: $($topLevelDirectories -join ', ')"
    }

    $forbiddenEntry = $entries | Where-Object {
        ($_ -match '(?i)(^|/)(?:\.codex-remote-attachments|\.agents|\.codex|\.git|\.github|\.idea|\.vscode|docs|scripts|tools|_local_workflows|graphify(?:[-_.][^/]*)?|__pycache__|_?backups)(?:/|$)') -or
        ($_ -match '(?i)(^|/)MSUF_Perfy(?:Hook|FPS)?\.lua$') -or
        ($_ -match '(?i)(^|/)[^/]*AssistantV2[^/]*(?:/|$)') -or
        ($_ -match '(?i)^MidnightSimpleUnitFrames/Shell/Menu2(?:/|$)') -or
        ($_ -match "(?i)^$([regex]::Escape($optionsAddonName))/Shell/Menu2/Assistant/") -or
        ($_ -match "(?i)^$([regex]::Escape($optionsAddonName))/Shell/Menu2/MSUF_Menu2_Assistant(?:Runtime\.xml|DialogLocale(?:_Data)?\.lua)$") -or
        ($_ -match '(?i)(?:^|/)(?:\.DS_Store|\.gitignore|\.pkgmeta|Thumbs\.db|desktop\.ini|luac\.out|graph\.json|GRAPH_REPORT\.md|\.graphify.*|.*\.(?:html?|md)|.*\.py[co])$')
    } | Select-Object -First 1
    if ($forbiddenEntry) {
        throw "Release zip contains a forbidden core-owned Menu2, Options-owned Assistant runtime, V2, profiling, Graphify, backup, documentation, mockup, or local-only path: $forbiddenEntry"
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

    $assistantToc = Read-ZipEntryText -Zip $zip -EntryName "MidnightSimpleUnitFrames_Assistant/MidnightSimpleUnitFrames_Assistant.toc"
    foreach ($requiredMarker in @(
        '## LoadOnDemand: 1',
        '## Dependencies: MidnightSimpleUnitFrames'
    )) {
        if ($assistantToc.IndexOf($requiredMarker, [System.StringComparison]::Ordinal) -lt 0) {
            throw "Assistant companion TOC is missing required LoD marker: $requiredMarker"
        }
    }
    $assistantTocPayload = @($assistantToc -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object {
        $_ -and -not $_.StartsWith('##') -and -not $_.StartsWith('#')
    })
    if (($assistantTocPayload -join "`n") -ne $assistantManifestName) {
        throw "Assistant companion TOC must load exactly its local $assistantManifestName. Got: $($assistantTocPayload -join ', ')"
    }

    $assistantXml = Read-ZipEntryText -Zip $zip -EntryName "MidnightSimpleUnitFrames_Assistant/$assistantManifestName"
    $scriptRefs = @(Get-AssistantManifestReferences -ManifestText $assistantXml)
    if ($scriptRefs.Count -ne $assistantScriptCount -or (Get-AssistantReferenceHash -References $scriptRefs) -ne $assistantOrderSha256) {
        throw "Packaged Assistant V1 manifest inventory/load order differs from the validated $assistantScriptCount-script contract."
    }
    if (($scriptRefs -join "`n") -ne ($assistantManifestRefs -join "`n")) {
        throw "Packaged Assistant V1 manifest differs from the validated source manifest."
    }

    $assistantFiles = @($entries | Where-Object {
        $_.StartsWith('MidnightSimpleUnitFrames_Assistant/', [System.StringComparison]::Ordinal) -and -not $_.EndsWith('/')
    } | ForEach-Object { $_.Substring('MidnightSimpleUnitFrames_Assistant/'.Length) } | Sort-Object)
    $expectedAssistantFiles = @(@("MidnightSimpleUnitFrames_Assistant.toc", $assistantManifestName) + @($assistantManifestRefs) | Sort-Object)
    if (($assistantFiles -join "`n") -ne ($expectedAssistantFiles -join "`n")) {
        throw "Assistant companion inventory differs from its exact V1 manifest contract. Got: $($assistantFiles -join ', ')"
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

Write-Host "Validated ${zipPath}: three addons, three stamped TOCs, Options LoD ownership, exact $assistantScriptCount-script Assistant V1 LoD manifest, and no core Menu2/Assistant/V2/Graphify/backup/local artifacts."
Write-Output $zipPath
