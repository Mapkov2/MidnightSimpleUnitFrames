[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [string]$ReleaseVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
} else {
    $RepositoryRoot = [System.IO.Path]::GetFullPath($RepositoryRoot)
}
if ([string]::IsNullOrWhiteSpace($ReleaseVersion)) {
    $ReleaseVersion = (Get-Content -LiteralPath (Join-Path $RepositoryRoot "VERSION") -Raw).Trim()
}

$normalizedVersion = $ReleaseVersion.Trim() -replace '^refs/tags/', '' -replace '(?i)^MSUF[\s._-]*', '' -replace '^v(?=\d)', ''
if ($normalizedVersion -notmatch '^6\.(?:1\d?|2\d?)(?:[-.]|$)') {
    Write-Host "Retail 12.1 release-line contract: skipped for $ReleaseVersion"
    return
}

$addonRoots = @(
    "MidnightSimpleUnitFrames",
    "MidnightSimpleUnitFrames_Assistant",
    "MidnightSimpleUnitFrames_Options"
)
$scanFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
foreach ($relativeRoot in $addonRoots) {
    $root = Join-Path $RepositoryRoot $relativeRoot
    foreach ($file in Get-ChildItem -LiteralPath $root -File -Recurse) {
        if ($file.Extension -in @(".lua", ".xml", ".toc")) { $scanFiles.Add($file) }
    }
}
$scanFiles.Add((Get-Item -LiteralPath (Join-Path $RepositoryRoot "CHANGELOG.md")))

$forbiddenFragments = @(
    "120105",
    "12.1.5",
    "CreateTimedSignalCallbackMap",
    "MSUF_ScheduleAfter",
    "MSUF_CancelScheduled",
    "SetRoundLayoutToNearestPixel",
    "SetEditModePreviewEnabled",
    "AddPandemicActiveAnimation",
    "ClearPandemicRegions",
    "tooltipShowAuraCasterNames"
)
$violations = [System.Collections.Generic.List[string]]::new()
foreach ($file in $scanFiles) {
    $content = [System.IO.File]::ReadAllText($file.FullName)
    foreach ($fragment in $forbiddenFragments) {
        if ($content.IndexOf($fragment, [System.StringComparison]::Ordinal) -ge 0) {
            $relative = $file.FullName.Substring($RepositoryRoot.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
            $violations.Add("$relative -> $fragment")
        }
    }
}
if ($violations.Count -gt 0) {
    throw "Retail $ReleaseVersion is assigned to WoW 12.1 but contains future-client contracts:`n$($violations -join [Environment]::NewLine)"
}

foreach ($relativeRoot in $addonRoots) {
    $tocPath = Join-Path (Join-Path $RepositoryRoot $relativeRoot) ($relativeRoot + ".toc")
    $toc = [System.IO.File]::ReadAllText($tocPath)
    if ($toc -notmatch '(?m)^## Interface: 120007, 120100\s*$') {
        throw "Retail $ReleaseVersion must declare exactly Interface 120007 and 120100: $tocPath"
    }
}

Write-Host "Retail 12.1 release-line contract: PASS ($ReleaseVersion)"
