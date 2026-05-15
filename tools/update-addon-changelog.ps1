[CmdletBinding()]
param(
    [string]$ChangelogPath = "CHANGELOG.md",
    [string]$OutputPath = "MidnightSimpleUnitFrames/Foundation/MSUF_Changelog.lua",
    [string]$Version,
    [int]$ReleaseCount = 2
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
    return ($v.ToLowerInvariant() -replace '[^a-z0-9]+', '')
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

if ($ReleaseCount -lt 1) { $ReleaseCount = 1 }

$changelogFullPath = Resolve-RepoPath -Path $ChangelogPath
$outputFullPath = Resolve-RepoPath -Path $OutputPath
if (-not (Test-Path -LiteralPath $changelogFullPath)) {
    throw "Changelog file not found: $changelogFullPath"
}

$lines = Get-Content -LiteralPath $changelogFullPath
$releases = New-Object System.Collections.Generic.List[object]
$release = $null
$section = $null
$lastBulletIndex = -1

foreach ($line in $lines) {
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
            bullets = New-Object System.Collections.Generic.List[string]
        }
        $release.sections.Add([pscustomobject]$section)
        $lastBulletIndex = -1
        continue
    }

    if ($null -eq $section) { continue }

    if ($line -match '^\s*-\s+(.+?)\s*$') {
        $section.bullets.Add((Convert-ToAsciiText $Matches[1]))
        $lastBulletIndex = $section.bullets.Count - 1
        continue
    }

    if ($lastBulletIndex -ge 0 -and $line -match '^\s{2,}(.+?)\s*$') {
        $continued = Convert-ToAsciiText $Matches[1]
        if (-not [string]::IsNullOrWhiteSpace($continued)) {
            $section.bullets[$lastBulletIndex] = ($section.bullets[$lastBulletIndex] + " " + $continued).Trim()
        }
    }
}

if ($releases.Count -eq 0) {
    throw "No release sections found in $changelogFullPath"
}

$startIndex = 0
$versionKey = Normalize-VersionKey $Version
if ($versionKey -ne "") {
    for ($i = 0; $i -lt $releases.Count; $i++) {
        if ((Normalize-VersionKey $releases[$i].version) -eq $versionKey) {
            $startIndex = $i
            break
        }
    }
}

$selected = @()
for ($i = $startIndex; $i -lt $releases.Count -and $selected.Count -lt $ReleaseCount; $i++) {
    $selected += $releases[$i]
}

$currentVersion = $selected[0].version
$previousVersion = if ($selected.Count -gt 1) { $selected[1].version } else { "" }
$rangeLabel = if (-not [string]::IsNullOrWhiteSpace($previousVersion)) {
    "$previousVersion -> $currentVersion"
} else {
    $currentVersion
}

$out = New-Object System.Collections.Generic.List[string]
$out.Add("-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.")
$out.Add("-- Edit CHANGELOG.md, then regenerate this file before packaging.")
$out.Add("local _, ns = ...")
$out.Add("ns = ns or {}")
$out.Add("")
$out.Add("local data = {")
$out.Add("    currentVersion = $(Convert-ToLuaString $currentVersion),")
$out.Add("    previousVersion = $(Convert-ToLuaString $previousVersion),")
$out.Add("    rangeLabel = $(Convert-ToLuaString $rangeLabel),")
$out.Add("    entries = {")

foreach ($entry in $selected) {
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
            if ([string]::IsNullOrWhiteSpace($bullet)) { continue }
            $out.Add("                        $(Convert-ToLuaString $bullet),")
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
$out.Add("ns.MSUF_Changelog = data")
$out.Add("_G.MSUF_Changelog = data")

$dir = Split-Path -Path $outputFullPath -Parent
if (-not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($outputFullPath, (($out -join [Environment]::NewLine) + [Environment]::NewLine), $utf8NoBom)
Write-Host "Generated $outputFullPath from $changelogFullPath"
