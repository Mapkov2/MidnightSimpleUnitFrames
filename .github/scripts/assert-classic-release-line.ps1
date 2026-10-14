[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [string]$ReleaseVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "ClassicGate.Common.psm1") -Force

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
} else {
    $RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
}
if ([string]::IsNullOrWhiteSpace($ReleaseVersion)) {
    $ReleaseVersion = [IO.File]::ReadAllText((Join-Path $RepositoryRoot "VERSION")).Trim()
}

$normalizedVersion = $ReleaseVersion.Trim() -replace '^refs/tags/', '' -replace '^v(?=\d)', ''
# The release line is whatever VERSION says. A version this script cannot read
# verifies nothing, so a malformed one fails instead of reporting "skipped": it
# would otherwise pass every TOC, contract and changelog check below without
# reading a single file. The shared channel resolver, which the packager and the
# publishing workflows also use, owns the format (stable <major>.<minor>,
# <major>.<minor>-alpha<N>, <major>.<minor>-beta<N>); this script adds the two
# rules the version check relies on. The minor is a decimal fraction, so a stable
# release spells it with two digits (a one-digit minor would collide with the
# zero-padded one in the integer minor that older clients compare), and a
# prerelease names its release line as <major>.<minor>.
$sourceVersion = [IO.File]::ReadAllText((Join-Path $RepositoryRoot "VERSION")).Trim()
if ($sourceVersion -ne $normalizedVersion) {
    throw "Classic VERSION '$sourceVersion' does not match release '$normalizedVersion'."
}
$releaseChannel = & (Join-Path $PSScriptRoot "resolve_classic_release_channel.ps1") -Tag $normalizedVersion
if ($releaseChannel.Channel -ceq "release") {
    if ($releaseChannel.Base -cnotmatch '^(?:0|[1-9][0-9]*)\.[0-9]{2}$') {
        throw "A stable release spells its minor with two digits (for example 7.00), got '$normalizedVersion'."
    }
} elseif ($releaseChannel.Base -cnotmatch '^(?:0|[1-9][0-9]*)\.[0-9]+$') {
    throw "A prerelease names its release line as <major>.<minor> (for example 7.0-beta1), got '$normalizedVersion'."
}

$addons = @(
    "MidnightSimpleUnitFrames",
    "MidnightSimpleUnitFrames_Options",
    "MidnightSimpleUnitFrames_Locales"
)
$clientMatrixPath = Join-Path $RepositoryRoot "tools/classic-client-matrix.tsv"
$clientMatrix = @(Import-MsufClientMatrix -Path $clientMatrixPath `
    -EmptyMessage "Client matrix names no clients: $clientMatrixPath")
# Get-InterfaceSetKey now lives in ClassicGate.Common.psm1.
Set-Alias -Name Get-InterfaceSetKey -Value Get-MsufInterfaceSetKey
foreach ($addon in $addons) {
    foreach ($client in $clientMatrix) {
        $flavor = $client.Suffix
        $tocPath = Join-Path $RepositoryRoot "$addon/${addon}_${flavor}.toc"
        $toc = [IO.File]::ReadAllText($tocPath)
        $interfaceFields = [regex]::Matches($toc, '(?m)^## Interface:\s*(.+?)\s*$')
        if ($interfaceFields.Count -ne 1 -or
            (Get-InterfaceSetKey -Value $interfaceFields[0].Groups[1].Value) -cne (Get-InterfaceSetKey -Value $client.Interfaces)) {
            throw "Release $normalizedVersion has the wrong $flavor interface set (expected $($client.Interfaces)): $tocPath"
        }
        if ($client.IsClassic -cne "true") {
            # Midnight runs this release's version as well (owner decision
            # 2026-10-09); WoW Forever reads the same TOC and takes the version from
            # the core TOC's Forever field.
            if ($toc -notmatch "(?m)^## Version: $([regex]::Escape($normalizedVersion)) \[AllowLoadGameType standard\]\s*$") {
                throw "Release $normalizedVersion has a stale standard game type version: $tocPath"
            }
            if ($addon -ceq "MidnightSimpleUnitFrames" -and
                $toc -notmatch "(?m)^## X-MSUF-Version-Forever: $([regex]::Escape($normalizedVersion))\s*$") {
                throw "Release $normalizedVersion has a stale WoW Forever version (X-MSUF-Version-Forever): $tocPath"
            }
            if ($toc -notmatch "(?m)^## Version: $([regex]::Escape($normalizedVersion)) \[ExcludeLoadGameType standard\]\s*$") {
                throw "Release $normalizedVersion has a stale non-standard game type version: $tocPath"
            }
            continue
        }
        if ($toc -notmatch "(?m)^## Version: $([regex]::Escape($normalizedVersion))\s*$") {
            throw "Release $normalizedVersion has a stale $flavor version: $tocPath"
        }
    }
}

$requiredFragments = [ordered]@{
    "MidnightSimpleUnitFrames/Kernel/MSUF_Scheduler.lua" = "CreateTimedSignalCallbackMap"
    "MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua" = "SetRoundLayoutToNearestPixel"
    "MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_NativeContract.lua" = "SetEditModePreviewEnabled"
    "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_SpellIndicators_Effects.lua" = "AddPandemicActiveAnimation"
    "MidnightSimpleUnitFrames/Runtime/MSUF_TooltipSpellIDs.lua" = "tooltipShowAuraCasterNames"
}
foreach ($relativePath in $requiredFragments.Keys) {
    $content = [IO.File]::ReadAllText((Join-Path $RepositoryRoot $relativePath))
    if ($content.IndexOf($requiredFragments[$relativePath], [StringComparison]::Ordinal) -lt 0) {
        throw "Release $normalizedVersion lost its 12.1.5 contract '$($requiredFragments[$relativePath])': $relativePath"
    }
}

$coreMainline = [IO.File]::ReadAllText((Join-Path $RepositoryRoot "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_Mainline.toc"))
foreach ($arenaEntry in @(
    "Features\Gameplay\MSUF_Feature_ArenaMatch.lua",
    "Features\Gameplay\MSUF_Feature_ArenaTrinkets.lua",
    "Castbars\MSUF_ArenaCastbars.lua",
    "Castbars\MSUF_ArenaCastbars_Preview.lua"
)) {
    if ($coreMainline.IndexOf($arenaEntry, [StringComparison]::Ordinal) -lt 0) {
        throw "Release $normalizedVersion Mainline lost Arena load entry: $arenaEntry"
    }
}

$changelogPath = Join-Path $RepositoryRoot "CHANGELOG.md"
$changelogVersion = & (Join-Path $PSScriptRoot "resolve-classic-changelog-version.ps1") `
    -RepositoryRoot $RepositoryRoot -ReleaseVersion $normalizedVersion
$sourceText = [IO.File]::ReadAllText($changelogPath).Replace("`r`n", "`n").Replace("`r", "`n")
if ($sourceText -notmatch "(?m)^## $([regex]::Escape($changelogVersion))\s+-\s+") {
    throw "CHANGELOG.md has no selected Classic release section for $changelogVersion."
}
$sha = [Security.Cryptography.SHA256]::Create()
try {
    $sourceSha256 = ([BitConverter]::ToString($sha.ComputeHash(
        ([Text.UTF8Encoding]::new($false)).GetBytes($sourceText)
    ))).Replace('-', '')
} finally {
    $sha.Dispose()
}
foreach ($relativePath in @(
    "MidnightSimpleUnitFrames_Options/State/MSUF_Changelog.lua",
    "MidnightSimpleUnitFrames_Options/State/MSUF_ChangelogFull.lua"
)) {
    $payload = [IO.File]::ReadAllText((Join-Path $RepositoryRoot $relativePath))
    if ($payload -notmatch "currentVersion = `"$([regex]::Escape($changelogVersion))`"") {
        throw "Generated Classic changelog has a stale currentVersion: $relativePath"
    }
    if ($payload -notmatch "sourceSha256 = `"$sourceSha256`"") {
        throw "Generated Classic changelog does not match CHANGELOG.md: $relativePath"
    }
}

Write-Host "Classic release-line contract: PASS ($normalizedVersion; changelog $changelogVersion)"
