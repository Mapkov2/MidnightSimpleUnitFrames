[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ZipPath,

    [string]$Version,
    [string]$ReleaseName,
    [string]$TocPath = "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames.toc",
    [string]$ChangelogPath = "CHANGELOG.md",
    [string]$ProjectId,
    [string]$ApiToken = $env:WAGO_API_TOKEN,
    [string]$Stability = $env:WAGO_STABILITY,
    [string]$RetailPatch = $env:WAGO_RETAIL_PATCH,
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

function Convert-RetailInterfaceToPatch {
    param([Parameter(Mandatory = $true)][int]$Interface)

    if ($Interface -lt 100000) {
        throw "Retail interface value must be six digits. Got: $Interface"
    }

    $major = [math]::Floor($Interface / 10000)
    $minor = [math]::Floor(($Interface % 10000) / 100)
    $patch = $Interface % 100

    return "$major.$minor.$patch"
}

function Get-Stability {
    param(
        [Parameter(Mandatory = $true)][string]$ReleaseVersion,
        [Parameter(Mandatory = $true)][bool]$IsPrerelease
    )

    if ($ReleaseVersion -match '(?i)alpha') {
        return "alpha"
    }

    if ($IsPrerelease) {
        return "beta"
    }

    if ($ReleaseVersion -match '(?i)(beta|rc|pre)') {
        return "beta"
    }

    return "stable"
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = Get-DefaultVersion
}

$releaseVersion = Normalize-Version -RawVersion $Version
if ([string]::IsNullOrWhiteSpace($ReleaseName)) {
    $ReleaseName = $releaseVersion
} else {
    $ReleaseName = ($ReleaseName -replace "`r?`n", " ").Trim()
}
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
    $ProjectId = Get-TocField -Content $tocContent -Name "X-Wago-ID"
}

if ([string]::IsNullOrWhiteSpace($ProjectId)) {
    throw "No Wago project id found. Set ProjectId or add ## X-Wago-ID to the TOC."
}

if ([string]::IsNullOrWhiteSpace($RetailPatch)) {
    $interfaceField = Get-TocField -Content $tocContent -Name "Interface"
    if ([string]::IsNullOrWhiteSpace($interfaceField)) {
        throw "No Interface field found in TOC. Set WAGO_RETAIL_PATCH explicitly."
    }

    $interfaces = $interfaceField -split ',' |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match '^\d+$' } |
        ForEach-Object { [int]$_ }

    if (-not $interfaces) {
        throw "No numeric retail interface found in TOC. Set WAGO_RETAIL_PATCH explicitly."
    }

    $RetailPatch = Convert-RetailInterfaceToPatch -Interface (($interfaces | Measure-Object -Maximum).Maximum)
}

if ([string]::IsNullOrWhiteSpace($Stability)) {
    $Stability = Get-Stability -ReleaseVersion $releaseVersion -IsPrerelease $Prerelease.IsPresent
}

if ($Stability -notin @("stable", "beta", "alpha")) {
    throw "Invalid Wago stability '$Stability'. Use stable, beta, or alpha."
}

$changelog = Get-Content -LiteralPath $changelogFullPath -Raw
$metadata = [ordered]@{
    label = $ReleaseName
    stability = $Stability
    changelog = $changelog
    supported_retail_patch = $RetailPatch
} | ConvertTo-Json -Depth 5 -Compress

if ($DryRun) {
    Write-Host "Prepared Wago upload for project $ProjectId as $ReleaseName / $releaseVersion ($Stability, retail $RetailPatch)."
    return
}

if ([string]::IsNullOrWhiteSpace($ApiToken)) {
    throw "WAGO_API_TOKEN is missing. Add it as a GitHub Actions repository secret."
}

$headers = @{
    Authorization = "Bearer $ApiToken"
    Accept = "application/json"
}

$uri = "https://addons.wago.io/api/projects/$ProjectId/version"
$form = @{
    metadata = $metadata
    file = Get-Item -LiteralPath $zipFullPath
}

Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Form $form | Out-Null
Write-Host "Uploaded $zipFullPath to Wago project $ProjectId as $ReleaseName / $releaseVersion ($Stability, retail $RetailPatch)."
