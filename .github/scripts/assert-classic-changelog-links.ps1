# Same exact control/hash contracts as the Retail release builder.
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$RepositoryRoot,
      [Parameter(Mandatory = $true)][string]$ReleaseVersion)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = [IO.Path]::GetFullPath($RepositoryRoot)
$stagePath = $repoRoot
$optionsAddonName = "MidnightSimpleUnitFrames_Options"
$changelogHistoryFloor = "6.02"
$release = $ReleaseVersion
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

# Every bullet in the current release's Highlights section must explicitly
# choose a route policy: either the invisible JSON route consumed by See New
# Features, or `msuf-menu-link: none` for an informational highlight that has
# no owning Menu2 control. Unmarked bullets still fail closed.
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
        throw "Current Highlights bullet has no explicit msuf-menu-link route policy: $bulletText"
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

Write-Host "Classic exact changelog routes and source hashes: PASS ($release)"
