[CmdletBinding()]
param(
    [string]$ChangelogPath = "CHANGELOG.md",
    [string]$OutputPath = "MidnightSimpleUnitFrames/State/MSUF_Changelog.lua",
    [string]$Version,
    [string]$PreviousVersion,
    [string]$DashboardChangelogPath,
    [string]$DashboardReleaseDate,
    [int]$ReleaseCount = 4,
    [string]$FullHistoryFromVersion = "6.02",
    [string]$FullOutputPath,
    [switch]$RequireCurrentHighlightLinks,
    # Write nothing; fail when a payload differs from what this run would
    # generate (line endings aside). The Classic gate runs this mode.
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))

function Resolve-RepoPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $candidate = $Path
    if (-not [System.IO.Path]::IsPathRooted($candidate)) {
        $candidate = Join-Path $RepoRoot $candidate
    }

    $full = [System.IO.Path]::GetFullPath($candidate)
    $root = $RepoRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $comparison = [System.StringComparison]::OrdinalIgnoreCase

    if (-not (
        $full.Equals($root, $comparison) -or
        $full.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar, $comparison) -or
        $full.StartsWith($root + [System.IO.Path]::AltDirectorySeparatorChar, $comparison)
    )) {
        throw "Refusing to use a path outside the repository: $full"
    }

    return $full
}

function Normalize-VersionKey {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    $v = $Value.Trim()
    $v = $v -replace '^refs/tags/', ''
    $v = $v -replace '^v(?=\d)', ''
    if ($v -match '^(?<base>\d+(?:\.\d+)*)(?:[\s._-]*(?<channel>alpha|beta|preview|rc|pre)[\s._-]*(?<number>\d+(?:\.\d+)*))?\s*$') {
        $base = (($Matches["base"] -split '\.') | ForEach-Object { [int]$_ }) -join "x"
        if ([string]::IsNullOrWhiteSpace($Matches["channel"])) { return $base }
        $number = ""
        if (-not [string]::IsNullOrWhiteSpace($Matches["number"])) {
            $number = (($Matches["number"] -split '\.') | ForEach-Object { [int]$_ }) -join "x"
        }
        return ($base + $Matches["channel"].ToLowerInvariant() + $number)
    }
    return ($v.ToLowerInvariant() -replace '[^a-z0-9]+', '')
}

function Get-PrereleaseFallbackKey {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    $v = $Value.Trim()
    $v = $v -replace '^refs/tags/', ''
    $v = $v -replace '^v(?=\d)', ''
    if ($v -match '^(?<base>\d+(?:\.\d+)*)(?:[\s._-]*(?<channel>alpha|beta|preview|rc|pre)[\s._-]*(?<number>\d+)\.\d+(?:\.\d+)*)\s*$') {
        $base = (($Matches["base"] -split '\.') | ForEach-Object { [int]$_ }) -join "."
        return Normalize-VersionKey ($base + " " + $Matches["channel"] + " " + $Matches["number"])
    }
    return ""
}

function Convert-ToAsciiText {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) { return "" }
    $text = $Value
    $text = $text -replace '\*\*', ''
    $text = $text -replace '`', ''
    $text = $text -replace '\s+', ' '
    $text = $text.Replace([string][char]0x2013, "-")
    $text = $text.Replace([string][char]0x2014, "-")
    $text = $text.Replace([string][char]0x2192, "->")
    $text = $text.Replace([string][char]0x00D7, "x")
    $text = $text.Replace([string][char]0x2018, "'")
    $text = $text.Replace([string][char]0x2019, "'")
    $text = $text.Replace([string][char]0x201C, '"')
    $text = $text.Replace([string][char]0x201D, '"')

    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $text.ToCharArray()) {
        $code = [int][char]$ch
        if ($code -ge 32 -and $code -le 126) {
            [void]$sb.Append($ch)
        } elseif ($code -eq 9) {
            [void]$sb.Append(" ")
        }
    }
    return ($sb.ToString() -replace '\s+', ' ').Trim()
}

function Convert-ToLuaString {
    param([AllowNull()][string]$Value)

    $text = Convert-ToAsciiText $Value
    $text = $text.Replace('\', '\\').Replace('"', '\"')
    return '"' + $text + '"'
}

function ConvertFrom-MenuLinkComment {
    param(
        [Parameter(Mandatory = $true)][string]$Json,
        [Parameter(Mandatory = $true)][string]$SourceLine
    )

    try {
        $value = $Json | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Invalid msuf-menu-link JSON at $sourceName line ${SourceLine}: $($_.Exception.Message)"
    }

    $pageKeyProperty = $value.PSObject.Properties["pageKey"]
    $queryProperty = $value.PSObject.Properties["query"]
    $labelProperty = $value.PSObject.Properties["label"]
    $sectionIdProperty = $value.PSObject.Properties["sectionId"]
    $controlIdProperty = $value.PSObject.Properties["controlId"]
    $settingKeyProperty = $value.PSObject.Properties["settingKey"]
    $prepareKindProperty = $value.PSObject.Properties["prepareKind"]
    $prepareValueProperty = $value.PSObject.Properties["prepareValue"]
    $semanticIdProperty = $value.PSObject.Properties["semanticId"]
    $pageKey = Convert-ToAsciiText $(if ($pageKeyProperty) { $pageKeyProperty.Value } else { "" })
    $query = Convert-ToAsciiText $(if ($queryProperty) { $queryProperty.Value } else { "" })
    $label = Convert-ToAsciiText $(if ($labelProperty) { $labelProperty.Value } else { "" })
    $sectionId = Convert-ToAsciiText $(if ($sectionIdProperty) { $sectionIdProperty.Value } else { "" })
    $controlId = Convert-ToAsciiText $(if ($controlIdProperty) { $controlIdProperty.Value } else { "" })
    $settingKey = Convert-ToAsciiText $(if ($settingKeyProperty) { $settingKeyProperty.Value } else { "" })
    $prepareKind = Convert-ToAsciiText $(if ($prepareKindProperty) { $prepareKindProperty.Value } else { "" })
    $prepareValue = Convert-ToAsciiText $(if ($prepareValueProperty) { $prepareValueProperty.Value } else { "" })
    $semanticId = Convert-ToAsciiText $(if ($semanticIdProperty) { $semanticIdProperty.Value } else { "" })
    if ($pageKey -notmatch '^[a-z0-9_]+$') {
        throw "Invalid msuf-menu-link pageKey '$pageKey' at $sourceName line $SourceLine."
    }
    if ([string]::IsNullOrWhiteSpace($query) -or [string]::IsNullOrWhiteSpace($label)) {
        throw "msuf-menu-link requires non-empty query and label values at $sourceName line $SourceLine."
    }
    if ($sectionId -notmatch '^[A-Za-z0-9_.-]+$') {
        throw "Invalid msuf-menu-link sectionId '$sectionId' at $sourceName line $SourceLine."
    }
    if ($controlId -notmatch '^menu2\.[A-Za-z0-9_.-]+$') {
        throw "Invalid msuf-menu-link controlId '$controlId' at $sourceName line $SourceLine."
    }
    if ($settingKey -notmatch '^[A-Za-z0-9_.-]+$') {
        throw "Invalid msuf-menu-link settingKey '$settingKey' at $sourceName line $SourceLine."
    }
    if ([string]::IsNullOrWhiteSpace($prepareKind) -ne [string]::IsNullOrWhiteSpace($prepareValue)) {
        throw "msuf-menu-link prepareKind and prepareValue must either both be set or both be omitted at $sourceName line $SourceLine."
    }
    if (-not [string]::IsNullOrWhiteSpace($prepareKind) -and $prepareKind -notmatch '^[A-Za-z][A-Za-z0-9_.-]*$') {
        throw "Invalid msuf-menu-link prepareKind '$prepareKind' at $sourceName line $SourceLine."
    }
    if (-not [string]::IsNullOrWhiteSpace($semanticId) -and $semanticId -notmatch '^[A-Za-z0-9_.:/@-]+$') {
        throw "Invalid msuf-menu-link semanticId '$semanticId' at $sourceName line $SourceLine."
    }

    return [pscustomobject][ordered]@{
        pageKey = $pageKey
        query = $query
        label = $label
        sectionId = $sectionId
        controlId = $controlId
        settingKey = $settingKey
        prepareKind = $prepareKind
        prepareValue = $prepareValue
        semanticId = $semanticId
    }
}

function New-ChangelogBullet {
    param([AllowNull()][string]$Text)

    return [pscustomobject][ordered]@{
        text = Convert-ToAsciiText $Text
        link = $null
        linkless = $false
    }
}

if ($ReleaseCount -lt 1) { $ReleaseCount = 1 }

$sourcePath = if ([string]::IsNullOrWhiteSpace($DashboardChangelogPath)) {
    $ChangelogPath
} else {
    $DashboardChangelogPath
}
$changelogFullPath = Resolve-RepoPath -Path $sourcePath
$outputFullPath = Resolve-RepoPath -Path $OutputPath
if (-not (Test-Path -LiteralPath $changelogFullPath)) {
    throw "Changelog file not found: $changelogFullPath"
}

$lines = Get-Content -LiteralPath $changelogFullPath -Encoding UTF8
$sourceName = [System.IO.Path]::GetFileName($changelogFullPath)
$sourceText = [System.IO.File]::ReadAllText($changelogFullPath).Replace("`r`n", "`n").Replace("`r", "`n")
$sourceHash = [System.Security.Cryptography.SHA256]::Create()
try {
    $sourceSha256 = ([System.BitConverter]::ToString(
        $sourceHash.ComputeHash(([System.Text.UTF8Encoding]::new($false)).GetBytes($sourceText))
    )).Replace('-', '')
} finally {
    $sourceHash.Dispose()
}
$releases = New-Object System.Collections.Generic.List[object]
$release = $null
$section = $null
$lastBulletIndex = -1

if (-not [string]::IsNullOrWhiteSpace($DashboardChangelogPath)) {
    if ([string]::IsNullOrWhiteSpace($Version)) {
        throw "-Version is required with -DashboardChangelogPath."
    }
    $release = [ordered]@{
        version = Convert-ToAsciiText $Version
        date = Convert-ToAsciiText $DashboardReleaseDate
        sections = New-Object System.Collections.Generic.List[object]
    }
    $releases.Add([pscustomobject]$release)

    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        $line = $lines[$lineIndex]
        if ($line -match '^##\s+11\s+Highlights\s*$') {
            $section = [ordered]@{
                title = "6.01 Highlights"
                bullets = New-Object System.Collections.Generic.List[object]
            }
            $release.sections.Add([pscustomobject]$section)
            continue
        }

        if ($line -match '^##\s+(.+?)\s*$') {
            $section = [ordered]@{
                title = Convert-ToAsciiText $Matches[1]
                bullets = New-Object System.Collections.Generic.List[object]
            }
            $release.sections.Add([pscustomobject]$section)
            continue
        }

        if ($line -match '^###\s+') { continue }
        if ($null -eq $section) { continue }

        if ($line -match '^\s*\d+\.\s+(.+?)\s*$' -or $line -match '^\s*-\s+(.+?)\s*$') {
            $section.bullets.Add((New-ChangelogBullet $Matches[1]))
            $lastBulletIndex = $section.bullets.Count - 1
            continue
        }

        if ($line -match '^\s*<!--\s*msuf-menu-link:\s*none\s*-->\s*$') {
            if ($lastBulletIndex -lt 0) {
                throw "msuf-menu-link: none has no preceding changelog bullet at $sourceName line $($lineIndex + 1)."
            }
            if ($null -ne $section.bullets[$lastBulletIndex].link) {
                throw "Changelog bullet cannot have both a menu route and msuf-menu-link: none at $sourceName line $($lineIndex + 1)."
            }
            $section.bullets[$lastBulletIndex].linkless = $true
            continue
        }

        if ($line -match '^\s*<!--\s*msuf-menu-link:\s*(\{.+\})\s*-->\s*$') {
            if ($lastBulletIndex -lt 0) {
                throw "msuf-menu-link has no preceding changelog bullet at $sourceName line $($lineIndex + 1)."
            }
            if ($section.bullets[$lastBulletIndex].linkless) {
                throw "Changelog bullet cannot have both msuf-menu-link: none and a menu route at $sourceName line $($lineIndex + 1)."
            }
            $section.bullets[$lastBulletIndex].link = ConvertFrom-MenuLinkComment $Matches[1] ($lineIndex + 1)
        }
    }
} else {
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        $line = $lines[$lineIndex]
        if ($line -match '^##\s+(.+?)(?:\s+-\s+([0-9]{4}-[0-9]{2}-[0-9]{2}))?\s*$') {
            $release = [ordered]@{
                version = Convert-ToAsciiText $Matches[1]
                date = Convert-ToAsciiText $Matches[2]
                sections = New-Object System.Collections.Generic.List[object]
            }
            $releases.Add([pscustomobject]$release)
            $section = $null
            $lastBulletIndex = -1
            continue
        }

        if ($null -eq $release) { continue }

        if ($line -match '^###\s+(.+?)\s*$') {
            $section = [ordered]@{
                title = Convert-ToAsciiText $Matches[1]
                bullets = New-Object System.Collections.Generic.List[object]
            }
            $release.sections.Add([pscustomobject]$section)
            $lastBulletIndex = -1
            continue
        }

        if ($null -eq $section) { continue }

        if ($line -match '^\s*-\s+(.+?)\s*$') {
            $section.bullets.Add((New-ChangelogBullet $Matches[1]))
            $lastBulletIndex = $section.bullets.Count - 1
            continue
        }

        if ($line -match '^\s*<!--\s*msuf-menu-link:\s*none\s*-->\s*$') {
            if ($lastBulletIndex -lt 0) {
                throw "msuf-menu-link: none has no preceding changelog bullet at $sourceName line $($lineIndex + 1)."
            }
            if ($null -ne $section.bullets[$lastBulletIndex].link) {
                throw "Changelog bullet cannot have both a menu route and msuf-menu-link: none at $sourceName line $($lineIndex + 1)."
            }
            $section.bullets[$lastBulletIndex].linkless = $true
            continue
        }

        if ($line -match '^\s*<!--\s*msuf-menu-link:\s*(\{.+\})\s*-->\s*$') {
            if ($lastBulletIndex -lt 0) {
                throw "msuf-menu-link has no preceding changelog bullet at $sourceName line $($lineIndex + 1)."
            }
            if ($section.bullets[$lastBulletIndex].linkless) {
                throw "Changelog bullet cannot have both msuf-menu-link: none and a menu route at $sourceName line $($lineIndex + 1)."
            }
            $section.bullets[$lastBulletIndex].link = ConvertFrom-MenuLinkComment $Matches[1] ($lineIndex + 1)
            continue
        }

        if ($lastBulletIndex -ge 0 -and $line -match '^\s{2,}(.+?)\s*$') {
            $continued = Convert-ToAsciiText $Matches[1]
            if (-not [string]::IsNullOrWhiteSpace($continued)) {
                $section.bullets[$lastBulletIndex].text = ($section.bullets[$lastBulletIndex].text + " " + $continued).Trim()
            }
        }
    }
}

if ($releases.Count -eq 0) {
    throw "No release sections found in $changelogFullPath"
}

$startIndex = 0
$versionKey = Normalize-VersionKey $Version
if ($versionKey -ne "") {
    $foundVersion = $false
    for ($i = 0; $i -lt $releases.Count; $i++) {
        if ((Normalize-VersionKey $releases[$i].version) -eq $versionKey) {
            $startIndex = $i
            $foundVersion = $true
            break
        }
    }
    if (-not $foundVersion) {
        $fallbackKey = Get-PrereleaseFallbackKey $Version
        if ($fallbackKey -ne "") {
            for ($i = 0; $i -lt $releases.Count; $i++) {
                if ((Normalize-VersionKey $releases[$i].version) -eq $fallbackKey) {
                    $startIndex = $i
                    break
                }
            }
        }
    }
}

$selected = @()
for ($i = $startIndex; $i -lt $releases.Count -and $selected.Count -lt $ReleaseCount; $i++) {
    $selected += $releases[$i]
}

if ($RequireCurrentHighlightLinks) {
    $currentEntry = $releases[$startIndex]
    foreach ($currentSection in $currentEntry.sections) {
        if ("$($currentSection.title)" -notmatch '(?i)^highlights$') { continue }
        foreach ($currentBullet in $currentSection.bullets) {
            if ($null -eq $currentBullet.link -and -not $currentBullet.linkless) {
                throw "Current release '$($currentEntry.version)' has an unlinked Highlights bullet: $($currentBullet.text)"
            }
        }
    }
}

function Write-ChangelogLua {
    param(
        [Parameter(Mandatory = $true)][object[]]$Entries,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $true)][string]$PublicName,
        [AllowNull()][string]$PreviousVersionOverride
    )

    if ($Entries.Count -eq 0) { throw "Cannot generate an empty changelog payload." }
    $currentVersion = $Entries[0].version
    $currentVersionIsPrerelease = $currentVersion -match '(?i)(alpha|beta|preview|rc|pre)'
    $previousVersionValue = if (-not [string]::IsNullOrWhiteSpace($PreviousVersionOverride)) {
        Convert-ToAsciiText $PreviousVersionOverride
    } elseif ($currentVersionIsPrerelease -and $Entries.Count -gt 1) {
        $Entries[1].version
    } elseif ($Entries.Count -gt 1) {
        $Entries[$Entries.Count - 1].version
    } else {
        ""
    }
    $rangeLabel = if (-not [string]::IsNullOrWhiteSpace($previousVersionValue)) {
        "$previousVersionValue -> $currentVersion"
    } else {
        $currentVersion
    }

    $out = New-Object System.Collections.Generic.List[string]
    $out.Add("-- Auto-generated from $sourceName by tools/update-addon-changelog.ps1.")
    $out.Add("-- Edit $sourceName, then regenerate this file before packaging.")
    $out.Add("local _, ns = ...")
    $out.Add("ns = ns or {}")
    $out.Add("local ExportPublic = ns.ExportPublic or function(name, value)")
    $out.Add("    _G[name] = value")
    $out.Add("    return value")
    $out.Add("end")
    $out.Add("")
    $out.Add("local data = {")
    $out.Add("    sourceSha256 = $(Convert-ToLuaString $sourceSha256),")
    $out.Add("    currentVersion = $(Convert-ToLuaString $currentVersion),")
    $out.Add("    historyFromVersion = $(Convert-ToLuaString $Entries[$Entries.Count - 1].version),")
    $out.Add("    previousVersion = $(Convert-ToLuaString $previousVersionValue),")
    $out.Add("    rangeLabel = $(Convert-ToLuaString $rangeLabel),")
    $out.Add("    entries = {")

    foreach ($entry in $Entries) {
        $out.Add("        {")
        $out.Add("            version = $(Convert-ToLuaString $entry.version),")
        $out.Add("            date = $(Convert-ToLuaString $entry.date),")
        $out.Add("            sections = {")
        foreach ($s in $entry.sections) {
            if ($s.bullets.Count -eq 0) { continue }
            $out.Add("                {")
            $out.Add("                    title = $(Convert-ToLuaString $s.title),")
            $out.Add("                    bullets = {")
            foreach ($bullet in $s.bullets) {
                if ($null -eq $bullet -or [string]::IsNullOrWhiteSpace($bullet.text)) { continue }
                if ($null -eq $bullet.link) {
                    if ($bullet.linkless) {
                        $out.Add("                        {")
                        $out.Add("                            text = $(Convert-ToLuaString $bullet.text),")
                        $out.Add("                            linkless = true,")
                        $out.Add("                        },")
                        continue
                    }
                    $out.Add("                        $(Convert-ToLuaString $bullet.text),")
                    continue
                }
                $out.Add("                        {")
                $out.Add("                            text = $(Convert-ToLuaString $bullet.text),")
                $out.Add("                            link = {")
                $out.Add("                                pageKey = $(Convert-ToLuaString $bullet.link.pageKey),")
                $out.Add("                                query = $(Convert-ToLuaString $bullet.link.query),")
                $out.Add("                                label = $(Convert-ToLuaString $bullet.link.label),")
                $out.Add("                                sectionId = $(Convert-ToLuaString $bullet.link.sectionId),")
                $out.Add("                                controlId = $(Convert-ToLuaString $bullet.link.controlId),")
                $out.Add("                                settingKey = $(Convert-ToLuaString $bullet.link.settingKey),")
                if (-not [string]::IsNullOrWhiteSpace($bullet.link.prepareKind)) {
                    $out.Add("                                prepareKind = $(Convert-ToLuaString $bullet.link.prepareKind),")
                    $out.Add("                                prepareValue = $(Convert-ToLuaString $bullet.link.prepareValue),")
                }
                if (-not [string]::IsNullOrWhiteSpace($bullet.link.semanticId)) {
                    $out.Add("                                semanticId = $(Convert-ToLuaString $bullet.link.semanticId),")
                }
                $out.Add("                            },")
                $out.Add("                        },")
            }
            $out.Add("                    },")
            $out.Add("                },")
        }
        $out.Add("            },")
        $out.Add("        },")
    }

    $out.Add("    },")
    $out.Add("}")
    $out.Add("")
    $out.Add("ns.$PublicName = data")
    $out.Add("ExportPublic(`"$PublicName`", data)")

    if ($Check) {
        $current = $null
        if (Test-Path -LiteralPath $DestinationPath -PathType Leaf) {
            $current = [System.IO.File]::ReadAllText($DestinationPath).Replace("`r`n", "`n")
        }
        if ($current -cne (($out -join "`n") + "`n")) { $script:StalePayloads.Add($DestinationPath) }
        return
    }

    $dir = Split-Path -Path $DestinationPath -Parent
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($DestinationPath, (($out -join [Environment]::NewLine) + [Environment]::NewLine), $utf8NoBom)
    Write-Host "Generated $DestinationPath from $changelogFullPath"
}

$script:StalePayloads = New-Object System.Collections.Generic.List[string]
Write-ChangelogLua -Entries $selected -DestinationPath $outputFullPath -PublicName "MSUF_Changelog" `
    -PreviousVersionOverride $PreviousVersion

$defaultOutputPath = Resolve-RepoPath -Path "MidnightSimpleUnitFrames/State/MSUF_Changelog.lua"
$effectiveFullOutputPath = $FullOutputPath
if ([string]::IsNullOrWhiteSpace($effectiveFullOutputPath) -and
    $outputFullPath.Equals($defaultOutputPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    $effectiveFullOutputPath = "MidnightSimpleUnitFrames_Options/State/MSUF_ChangelogFull.lua"
}
if (-not [string]::IsNullOrWhiteSpace($effectiveFullOutputPath)) {
    $fullOutput = Resolve-RepoPath -Path $effectiveFullOutputPath
    $fullEndIndex = $releases.Count - 1
    if (-not [string]::IsNullOrWhiteSpace($FullHistoryFromVersion)) {
        $historyFloorKey = Normalize-VersionKey $FullHistoryFromVersion
        $historyFloorFound = $false
        for ($i = $startIndex; $i -lt $releases.Count; $i++) {
            if ((Normalize-VersionKey $releases[$i].version) -eq $historyFloorKey) {
                $fullEndIndex = $i
                $historyFloorFound = $true
                break
            }
        }
        if (-not $historyFloorFound) {
            throw "Full changelog history floor '$FullHistoryFromVersion' was not found after '$($releases[$startIndex].version)'."
        }
    }
    $allSelected = @()
    for ($i = $startIndex; $i -le $fullEndIndex; $i++) { $allSelected += $releases[$i] }
    Write-ChangelogLua -Entries $allSelected -DestinationPath $fullOutput -PublicName "MSUF_FullChangelog" `
        -PreviousVersionOverride $PreviousVersion
}

if ($Check) {
    if ($script:StalePayloads.Count -gt 0) {
        throw "Changelog payloads are stale against ${sourceName}: $($script:StalePayloads -join ', '). Regenerate them with tools/update-addon-changelog.ps1$(if ($Version) { ' -Version ' + $Version })."
    }
    Write-Host "Changelog payloads: current with $sourceName ($($releases[$startIndex].version))"
}
