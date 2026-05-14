[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ZipPath,

    [string]$Version,
    [string]$TocPath = "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames.toc",
    [string]$ChangelogPath = "CHANGELOG.md",
    [string]$ProjectId = $env:CF_PROJECT_ID,
    [string]$GameVersionIds = $env:CF_GAME_VERSION_IDS,
    [string]$ApiToken = $env:CF_API_KEY,
    [string]$ReleaseType = $env:CF_RELEASE_TYPE,
    [string]$ApiBaseUrl = $env:CF_API_BASE_URL,
    [switch]$Prerelease,
    [switch]$DryRun
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

function Normalize-Version {
    param([Parameter(Mandatory = $true)][string]$RawVersion)

    $value = $RawVersion.Trim()
    $value = $value -replace '^refs/tags/', ''
    $value = $value -replace '^v(?=\d)', ''

    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Version cannot be empty."
    }

    return $value
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

function Get-TocField {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $match = [regex]::Match($Content, "(?m)^##\s+$([regex]::Escape($Name)):\s*(.+?)\s*$")
    if ($match.Success) {
        return $match.Groups[1].Value.Trim()
    }

    return $null
}

function Get-CurseForgeReleaseType {
    param(
        [Parameter(Mandatory = $true)][string]$ReleaseVersion,
        [Parameter(Mandatory = $true)][bool]$IsPrerelease
    )

    if ($IsPrerelease) {
        return "beta"
    }

    if ($ReleaseVersion -match '(?i)(alpha|beta|rc|pre)') {
        return "beta"
    }

    return "release"
}

function Convert-GameVersionIds {
    param([Parameter(Mandatory = $true)][string]$RawIds)

    $ids = $RawIds -split '[,;\s]+' |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object {
            $value = 0
            if (-not [int]::TryParse($_.Trim(), [ref]$value)) {
                throw "Invalid CurseForge game version id '$($_)'. Use numeric ids separated by commas."
            }

            $value
        }

    if (-not $ids) {
        throw "No CurseForge game version ids provided."
    }

    return @($ids)
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = Get-DefaultVersion
}

$releaseVersion = Normalize-Version -RawVersion $Version
$zipFullPath = Resolve-InRepoPath -Path $ZipPath
$tocFullPath = Resolve-InRepoPath -Path $TocPath
$changelogFullPath = Resolve-InRepoPath -Path $ChangelogPath

if (-not (Test-Path -LiteralPath $zipFullPath)) {
    throw "Release zip not found: $zipFullPath"
}

if (-not (Test-Path -LiteralPath $tocFullPath)) {
    throw "TOC file not found: $tocFullPath"
}

if (-not (Test-Path -LiteralPath $changelogFullPath)) {
    throw "Changelog file not found: $changelogFullPath"
}

$tocContent = Get-Content -LiteralPath $tocFullPath -Raw

if ([string]::IsNullOrWhiteSpace($ProjectId)) {
    $ProjectId = Get-TocField -Content $tocContent -Name "X-Curse-Project-ID"
}

if ([string]::IsNullOrWhiteSpace($ProjectId)) {
    throw "CF_PROJECT_ID is missing. Add it as a GitHub Actions repository variable or add ## X-Curse-Project-ID to the TOC."
}

if ($ProjectId -notmatch '^\d+$') {
    throw "CurseForge project id must be numeric. Got: $ProjectId"
}

if ([string]::IsNullOrWhiteSpace($GameVersionIds)) {
    throw "CF_GAME_VERSION_IDS is missing. Add numeric CurseForge game version ids as a repository variable, separated by commas."
}

if ([string]::IsNullOrWhiteSpace($ReleaseType)) {
    $ReleaseType = Get-CurseForgeReleaseType -ReleaseVersion $releaseVersion -IsPrerelease $Prerelease.IsPresent
}

if ($ReleaseType -notin @("release", "beta", "alpha")) {
    throw "Invalid CurseForge release type '$ReleaseType'. Use release, beta, or alpha."
}

if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
    $ApiBaseUrl = "https://wow.curseforge.com"
}

$ApiBaseUrl = $ApiBaseUrl.TrimEnd("/")
$changelog = Get-Content -LiteralPath $changelogFullPath -Raw
$metadata = [ordered]@{
    changelog = $changelog
    changelogType = "markdown"
    displayName = "MSUF $releaseVersion"
    gameVersions = Convert-GameVersionIds -RawIds $GameVersionIds
    releaseType = $ReleaseType
} | ConvertTo-Json -Depth 5 -Compress

if ($DryRun) {
    Write-Host "Prepared CurseForge upload for project $ProjectId as $releaseVersion ($ReleaseType, game versions: $GameVersionIds)."
    return
}

if ([string]::IsNullOrWhiteSpace($ApiToken)) {
    throw "CF_API_KEY is missing. Add it as a GitHub Actions repository secret."
}

$headers = @{
    "X-Api-Token" = $ApiToken
    Accept = "application/json"
}

$uri = "$ApiBaseUrl/api/projects/$ProjectId/upload-file"
$form = @{
    metadata = $metadata
    file = Get-Item -LiteralPath $zipFullPath
}

Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Form $form | Out-Null
Write-Host "Uploaded $zipFullPath to CurseForge project $ProjectId as $releaseVersion ($ReleaseType)."
