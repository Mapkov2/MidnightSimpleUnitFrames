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
# A line this script does not know verifies nothing, so it fails instead of
# reporting "skipped": a mistyped version would otherwise pass every TOC,
# contract and changelog check below without reading a single file. When the
# Classic release line moves past 6.5, retarget this script deliberately.
# 6.502 ships the fixes tested in its beta and the raid combat layout repair.
# 6.50 is the stable release of the 6.5 line (two-digit minor, so it never
# collides with 6.05 and ranks above 6.20). 6.501 and 6.502 are its maintenance releases.
if ($normalizedVersion -notmatch '(?i)^6\.5[-.]?(?:alpha|beta)\d*(?:[-.]|$)' -and $normalizedVersion -cnotin @('6.50', '6.501', '6.502') -and $normalizedVersion -cnotmatch '^6\.502-beta[1-9][0-9]*$') {
    throw "Classic release-line contract covers 6.5 alpha/beta and stable 6.50/6.501/6.502 and 6.502 betas only and cannot verify '$ReleaseVersion'. Fix the release version, or retarget this script when the Classic release line moves."
}

$sourceVersion = [IO.File]::ReadAllText((Join-Path $RepositoryRoot "VERSION")).Trim()
if ($sourceVersion -ne $normalizedVersion) {
    throw "Classic VERSION '$sourceVersion' does not match release '$normalizedVersion'."
}

$addons = @(
    "MidnightSimpleUnitFrames",
    "MidnightSimpleUnitFrames_Options"
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
            throw "Classic 6.5 has the wrong $flavor interface set (expected $($client.Interfaces)): $tocPath"
        }
        if ($client.IsClassic -cne "true") {
            # Since 6.50 Midnight runs this release's version as well (owner decision
            # 2026-10-09); WoW Forever reads the same TOC and takes the version from
            # the core TOC's Forever field.
            if ($toc -notmatch "(?m)^## Version: $([regex]::Escape($normalizedVersion)) \[AllowLoadGameType standard\]\s*$") {
                throw "Classic 6.5 has a stale standard game type version: $tocPath"
            }
            if ($addon -ceq "MidnightSimpleUnitFrames" -and
                $toc -notmatch "(?m)^## X-MSUF-Version-Forever: $([regex]::Escape($normalizedVersion))\s*$") {
                throw "Classic 6.5 has a stale WoW Forever version (X-MSUF-Version-Forever): $tocPath"
            }
            if ($toc -notmatch "(?m)^## Version: $([regex]::Escape($normalizedVersion)) \[ExcludeLoadGameType standard\]\s*$") {
                throw "Classic 6.5 has a stale non-standard game type version: $tocPath"
            }
            continue
        }
        if ($toc -notmatch "(?m)^## Version: $([regex]::Escape($normalizedVersion))\s*$") {
            throw "Classic 6.5 has a stale $flavor version: $tocPath"
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
    "MidnightSimpleUnitFrames/State/MSUF_Changelog.lua",
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

Write-Host "Classic 6.5 release-line contract: PASS ($normalizedVersion; changelog $changelogVersion)"
