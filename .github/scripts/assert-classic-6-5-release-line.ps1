[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [string]$ReleaseVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
} else {
    $RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
}
if ([string]::IsNullOrWhiteSpace($ReleaseVersion)) {
    $ReleaseVersion = [IO.File]::ReadAllText((Join-Path $RepositoryRoot "VERSION")).Trim()
}

$normalizedVersion = $ReleaseVersion.Trim() -replace '^refs/tags/', '' -replace '^v(?=\d)', ''
if ($normalizedVersion -notmatch '(?i)^6\.5[-.]?alpha\d*(?:[-.]|$)') {
    Write-Host "Classic 6.5 release-line contract: skipped for $ReleaseVersion"
    return
}

$sourceVersion = [IO.File]::ReadAllText((Join-Path $RepositoryRoot "VERSION")).Trim()
if ($sourceVersion -ne $normalizedVersion) {
    throw "Classic VERSION '$sourceVersion' does not match release '$normalizedVersion'."
}

$addons = @(
    "MidnightSimpleUnitFrames",
    "MidnightSimpleUnitFrames_Options",
    "MidnightSimpleUnitFrames_Assistant"
)
$classicInterfaces = [ordered]@{
    Vanilla = "11509"
    TBC = "20506"
    Mists = "50504"
}
foreach ($addon in $addons) {
    $mainlineToc = Join-Path $RepositoryRoot "$addon/${addon}_Mainline.toc"
    $mainline = [IO.File]::ReadAllText($mainlineToc)
    if ($mainline -notmatch '(?m)^## Interface: 120007, 120100, 120105\s*$') {
        throw "Classic 6.5 Mainline must declare Retail 12.0.7, 12.1.0 and 12.1.5: $mainlineToc"
    }
    foreach ($flavor in $classicInterfaces.Keys) {
        $tocPath = Join-Path $RepositoryRoot "$addon/${addon}_${flavor}.toc"
        $toc = [IO.File]::ReadAllText($tocPath)
        if ($toc -notmatch "(?m)^## Interface: $([regex]::Escape($classicInterfaces[$flavor]))\s*$") {
            throw "Classic 6.5 has the wrong $flavor interface: $tocPath"
        }
        if ($toc -notmatch "(?m)^## Version: $([regex]::Escape($normalizedVersion))\s*$") {
            throw "Classic 6.5 has a stale $flavor version: $tocPath"
        }
    }
}

$requiredFragments = [ordered]@{
    "MidnightSimpleUnitFrames/Kernel/MSUF_Scheduler.lua" = "CreateTimedSignalCallbackMap"
    "MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua" = "SetRoundLayoutToNearestPixel"
    "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua" = "SetEditModePreviewEnabled"
    "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_SpellIndicators.lua" = "AddPandemicActiveAnimation"
    "MidnightSimpleUnitFrames/Runtime/MSUF_TooltipSpellIDs.lua" = "tooltipShowAuraCasterNames"
}
foreach ($relativePath in $requiredFragments.Keys) {
    $content = [IO.File]::ReadAllText((Join-Path $RepositoryRoot $relativePath))
    if ($content.IndexOf($requiredFragments[$relativePath], [StringComparison]::Ordinal) -lt 0) {
        throw "Classic 6.5 lost its 12.1.5 contract '$($requiredFragments[$relativePath])': $relativePath"
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
        throw "Classic 6.5 Mainline lost Arena load entry: $arenaEntry"
    }
}

$changelogPath = Join-Path $RepositoryRoot "CHANGELOG.md"
$sourceText = [IO.File]::ReadAllText($changelogPath).Replace("`r`n", "`n").Replace("`r", "`n")
if ($sourceText -notmatch "(?m)^## $([regex]::Escape($normalizedVersion))\s+-\s+") {
    throw "CHANGELOG.md has no current Classic release section for $normalizedVersion."
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
    "MidnightSimpleUnitFrames/State/MSUF_Changelog.lua",
    "MidnightSimpleUnitFrames/Game/Classic/State/MSUF_Changelog.lua",
    "MidnightSimpleUnitFrames_Options/State/MSUF_ChangelogFull.lua"
)) {
    $payload = [IO.File]::ReadAllText((Join-Path $RepositoryRoot $relativePath))
    if ($payload -notmatch "currentVersion = `"$([regex]::Escape($normalizedVersion))`"") {
        throw "Generated Classic changelog has a stale currentVersion: $relativePath"
    }
    if ($payload -notmatch "sourceSha256 = `"$sourceSha256`"") {
        throw "Generated Classic changelog does not match CHANGELOG.md: $relativePath"
    }
}

Write-Host "Classic 6.5 release-line contract: PASS ($normalizedVersion)"
