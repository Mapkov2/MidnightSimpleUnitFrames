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
if ($normalizedVersion -notmatch '(?i)^6\.5[-.]?(?:alpha|beta)\d*(?:[-.]|$)') {
    throw "Classic release-line contract covers 6.5 alpha/beta only and cannot verify '$ReleaseVersion'. Fix the release version, or retarget this script when the Classic release line moves."
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
            # Mainline keeps Retail's "## Version"; WoW Forever reads the same TOC and
            # takes this release's version from the core TOC's Forever field.
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
