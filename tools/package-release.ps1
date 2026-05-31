[CmdletBinding()]
param(
    [string]$Version,
    [string]$OutputDir = "dist",
    [switch]$KeepStaging
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))

function Resolve-InRepoPath {
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

function Get-DefaultVersion {
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_REF_NAME)) {
        return $env:GITHUB_REF_NAME
    }

    $versionFile = Join-Path $RepoRoot "VERSION"
    if (Test-Path -LiteralPath $versionFile) {
        $line = Get-Content -LiteralPath $versionFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            return $line
        }
    }

    return $null
}

function Normalize-Version {
    param([Parameter(Mandatory = $true)][string]$RawVersion)

    $value = $RawVersion.Trim()
    $value = $value -replace '^refs/tags/', ''
    $value = $value -replace '^v(?=\d)', ''
    if ($value -match '^(?<base>\d+(?:\.\d+)*)(?:[\s._-]*(?<channel>alpha|beta|preview|rc|pre)[\s._-]*(?<number>\d+(?:\.\d+)*))?\s*$') {
        $base = (($Matches["base"] -split '\.') | ForEach-Object { [int]$_ }) -join "."
        if ([string]::IsNullOrWhiteSpace($Matches["channel"])) { return $base }
        $number = ""
        if (-not [string]::IsNullOrWhiteSpace($Matches["number"])) {
            $number = (($Matches["number"] -split '\.') | ForEach-Object { [int]$_ }) -join "."
        }
        return ($base + "-" + $Matches["channel"].ToLowerInvariant() + $number)
    }

    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Version cannot be empty."
    }

    return $value
}

function Set-TocVersion {
    param(
        [Parameter(Mandatory = $true)][string]$TocPath,
        [Parameter(Mandatory = $true)][string]$TocVersion
    )

    $content = Get-Content -LiteralPath $TocPath -Raw
    if ($content -notmatch '(?m)^## Version:') {
        throw "No TOC version line found in $TocPath"
    }

    $content = [regex]::Replace($content, '(?m)^## Version:.*$', "## Version: $TocVersion", 1)
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($TocPath, $content, $utf8NoBom)
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = Get-DefaultVersion
}

$releaseVersion = Normalize-Version -RawVersion $Version
$fileVersion = $releaseVersion -replace '[\\/:*?"<>|]', '-'
$outputPath = Resolve-InRepoPath -Path $OutputDir
$stagePath = Join-Path $outputPath "package"

New-Item -ItemType Directory -Force -Path $outputPath | Out-Null

if (Test-Path -LiteralPath $stagePath) {
    Remove-Item -LiteralPath $stagePath -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $stagePath | Out-Null

Copy-Item -LiteralPath (Join-Path $RepoRoot "MidnightSimpleUnitFrames") -Destination $stagePath -Recurse -Force

$perfyHookPath = Join-Path $stagePath "MidnightSimpleUnitFrames/MSUF_PerfyHook.lua"
if (Test-Path -LiteralPath $perfyHookPath) {
    Remove-Item -LiteralPath $perfyHookPath -Force
}

$changelogGenerator = Join-Path $RepoRoot "tools/update-addon-changelog.ps1"
if (Test-Path -LiteralPath $changelogGenerator) {
    & $changelogGenerator `
        -Version $releaseVersion `
        -OutputPath (Join-Path $stagePath "MidnightSimpleUnitFrames/Foundation/MSUF_Changelog.lua")
}

Set-TocVersion -TocPath (Join-Path $stagePath "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames.toc") -TocVersion $releaseVersion

$zipPath = Join-Path $outputPath "MidnightSimpleUnitFrames$fileVersion.zip"
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

$packageItems = Get-ChildItem -LiteralPath $stagePath
if (-not $packageItems) {
    throw "No files staged for packaging."
}

$packageItems | Compress-Archive -DestinationPath $zipPath -Force

if (-not $KeepStaging) {
    Remove-Item -LiteralPath $stagePath -Recurse -Force
}

Write-Host "Created $zipPath with TOC version $releaseVersion"
