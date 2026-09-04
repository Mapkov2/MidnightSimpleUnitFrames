[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseVersion,

    [string]$OutputDirectory = "dist"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$expectedProjectId = "1384660"
$addonNames = @(
    "MidnightSimpleUnitFrames",
    "MidnightSimpleUnitFrames_Options",
    "MidnightSimpleUnitFrames_Assistant"
)
$flavors = @("Mainline", "Vanilla", "Mists", "TBC")
$classicFlavors = @("Vanilla", "Mists", "TBC")
$classicInterfaces = [ordered]@{
    Vanilla = "11509"
    TBC = "20506"
    Mists = "50504"
}

function Normalize-ClassicReleaseVersion {
    param([Parameter(Mandatory = $true)][string]$Value)

    $candidate = $Value.Trim() -replace '^refs/tags/', ''
    if ($candidate -notmatch '^classic-v(?<base>\d+(?:\.\d+)*)-alpha(?<number>\d+)$') {
        throw "Classic release version must use 'classic-v<version>-alpha<number>'. Got: $Value"
    }

    $base = (($Matches["base"] -split '\.') | ForEach-Object { [int]$_ }) -join "."
    $number = [int]$Matches["number"]
    return "$base-alpha$number"
}

function Normalize-VersionKey {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    $candidate = $Value.Trim()
    $candidate = $candidate -replace '^refs/tags/', ''
    $candidate = $candidate -replace '(?i)^classic[\s._-]*', ''
    $candidate = $candidate -replace '^v(?=\d)', ''
    if ($candidate -match '^(?<base>\d+(?:\.\d+)*)(?:[\s._-]*(?<channel>alpha|a)[\s._-]*(?<number>\d+))\s*$') {
        $base = (($Matches["base"] -split '\.') | ForEach-Object { [int]$_ }) -join "."
        return "$base-alpha$([int]$Matches["number"])"
    }
    return $candidate.ToLowerInvariant()
}

function Resolve-RepoOutputPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $candidate = if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $repoRoot $Path }
    $full = [IO.Path]::GetFullPath($candidate)
    $root = $repoRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $prefix = $root + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Release output must remain inside the repository. Got: $full"
    }
    return $full
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$FullName
    )

    $prefix = $Root.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $FullName.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the package stage: $FullName"
    }
    return $FullName.Substring($prefix.Length).Replace('\', '/')
}

function Get-TocField {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $matches = [regex]::Matches($Content, "(?m)^##\s+$([regex]::Escape($Name)):\s*(.+?)\s*$")
    if ($matches.Count -ne 1) {
        throw "Expected exactly one '$Name' field in TOC content; found $($matches.Count)."
    }
    return $matches[0].Groups[1].Value.Trim()
}

function Set-StagedTocVersion {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Version
    )

    $content = [IO.File]::ReadAllText($Path)
    $pattern = [regex]::new('(?m)^##\s*Version:\s*[^\r\n]*')
    if ($pattern.Matches($content).Count -ne 1) {
        throw "Expected exactly one Version field in staged TOC: $Path"
    }
    $updated = $pattern.Replace($content, "## Version: $Version", 1)
    [IO.File]::WriteAllText($Path, $updated, [Text.UTF8Encoding]::new($false))
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Test-ForbiddenArtifactPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $normalized = $RelativePath.Replace('\', '/').Trim('/')
    if (-not $normalized) { return $false }

    $segments = @($normalized -split '/')
    $forbiddenDirectories = @(
        ".git", ".github", ".agents", ".codex", ".idea", ".vscode",
        "_local_workflows", "graphify-out", "docs", "doc", "test", "tests",
        "tools", "scripts", "__pycache__", "_backups", "backups"
    )
    foreach ($segment in $segments) {
        if ($forbiddenDirectories -contains $segment.ToLowerInvariant()) { return $true }
    }

    $leaf = $segments[-1]
    if ($leaf -match '(?i)^(?:\.DS_Store|\.gitignore|\.gitattributes|\.pkgmeta|Thumbs\.db|desktop\.ini|luac\.out|graph\.json|GRAPH_REPORT\.md)$') {
        return $true
    }
    if ($leaf -match '(?i)\.(?:md|markdown|html?|py|pyc|pyo|ps1|psm1|psd1)$') { return $true }
    if ($leaf -match '(?i)(?:^|[-_.])(?:test|tests|smoke|spec|perfy|graphify)(?:[-_.]|$)') { return $true }
    return $false
}

function Remove-ForbiddenStageArtifacts {
    param([Parameter(Mandatory = $true)][string]$StageRoot)

    $directories = @(Get-ChildItem -LiteralPath $StageRoot -Directory -Force -Recurse | Sort-Object { $_.FullName.Length } -Descending)
    foreach ($directory in $directories) {
        $relative = Get-RelativePath -Root $StageRoot -FullName $directory.FullName
        if (Test-ForbiddenArtifactPath -RelativePath $relative) {
            Remove-Item -LiteralPath $directory.FullName -Recurse -Force
        }
    }

    $files = @(Get-ChildItem -LiteralPath $StageRoot -File -Force -Recurse)
    foreach ($file in $files) {
        $relative = Get-RelativePath -Root $StageRoot -FullName $file.FullName
        if (Test-ForbiddenArtifactPath -RelativePath $relative) {
            Remove-Item -LiteralPath $file.FullName -Force
        }
    }

    $remaining = @(Get-ChildItem -LiteralPath $StageRoot -File -Force -Recurse | ForEach-Object {
        Get-RelativePath -Root $StageRoot -FullName $_.FullName
    } | Where-Object { Test-ForbiddenArtifactPath -RelativePath $_ })
    if ($remaining.Count -gt 0) {
        throw "Forbidden local, documentation, test, Graphify, or Perfy artifacts remain in package stage: $($remaining -join ', ')"
    }
}

function Get-ChangelogSection {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Version
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "CHANGELOG.md is missing: $Path"
    }
    $lines = [regex]::Split([IO.File]::ReadAllText($Path), '\r?\n')
    $wanted = Normalize-VersionKey $Version
    $start = -1
    $end = $lines.Count
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -notmatch '^##\s+(.+?)\s*$') { continue }
        $heading = ($Matches[1] -replace '\s+-\s+\d{4}-\d{2}-\d{2}\s*$', '').Trim()
        if ((Normalize-VersionKey $heading) -ne $wanted) { continue }
        $start = $index
        for ($next = $index + 1; $next -lt $lines.Count; $next++) {
            if ($lines[$next] -match '^##\s+') {
                $end = $next
                break
            }
        }
        break
    }
    if ($start -lt 0) {
        throw "Could not find a CHANGELOG.md section matching Classic release '$Version'."
    }
    return [string[]]$lines[$start..($end - 1)]
}

function Convert-ChangelogSectionToHtml {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    $html = [Collections.Generic.List[string]]::new()
    $inList = $false
    function Encode-Inline([string]$Value) {
        $encoded = [Net.WebUtility]::HtmlEncode($Value.Trim())
        $encoded = [regex]::Replace($encoded, '\*\*(.+?)\*\*', '<strong>$1</strong>')
        $encoded = [regex]::Replace($encoded, '`([^`]+)`', '<code>$1</code>')
        return $encoded
    }

    foreach ($line in $Lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^<!--.*-->$') { continue }
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            if ($inList) {
                $html.Add('</ul>')
                $inList = $false
            }
            continue
        }
        if ($trimmed -match '^##\s+(.+?)\s*$') {
            if ($inList) {
                $html.Add('</ul>')
                $inList = $false
            }
            $html.Add('<h2>' + (Encode-Inline $Matches[1]) + '</h2>')
            continue
        }
        if ($trimmed -match '^###\s+(.+?)\s*$') {
            if ($inList) {
                $html.Add('</ul>')
                $inList = $false
            }
            $html.Add('<h3>' + (Encode-Inline $Matches[1]) + '</h3>')
            continue
        }
        if ($trimmed -match '^-\s+(.+?)\s*$') {
            if (-not $inList) {
                $html.Add('<ul>')
                $inList = $true
            }
            $html.Add('<li>' + (Encode-Inline $Matches[1]) + '</li>')
            continue
        }
        if ($inList) {
            $html.Add('</ul>')
            $inList = $false
        }
        $html.Add('<p>' + (Encode-Inline $trimmed) + '</p>')
    }
    if ($inList) {
        $html.Add('</ul>')
    }
    return (($html -join [Environment]::NewLine).TrimEnd() + [Environment]::NewLine)
}

function Read-ZipEntryText {
    param(
        [Parameter(Mandatory = $true)]$Archive,
        [Parameter(Mandatory = $true)][string]$EntryName
    )

    $entry = $Archive.Entries | Where-Object { $_.FullName.Replace('\', '/') -eq $EntryName } | Select-Object -First 1
    if (-not $entry) { throw "Release zip is missing required entry: $EntryName" }
    $stream = $entry.Open()
    try {
        $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $true)
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally {
        $stream.Dispose()
    }
}

function Get-ZipEntrySha256 {
    param(
        [Parameter(Mandatory = $true)]$Archive,
        [Parameter(Mandatory = $true)][string]$EntryName
    )

    $entry = $Archive.Entries | Where-Object { $_.FullName.Replace('\', '/') -eq $EntryName } | Select-Object -First 1
    if (-not $entry) { throw "Release zip is missing required entry: $EntryName" }
    $stream = $entry.Open()
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '')
        } finally {
            $sha.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

$release = Normalize-ClassicReleaseVersion $ReleaseVersion
$sourceVersion = [IO.File]::ReadAllText((Join-Path $repoRoot 'VERSION')).Trim()
if ($sourceVersion -ne $release) {
    throw "VERSION '$sourceVersion' does not match Classic release '$release'."
}
& (Join-Path $PSScriptRoot "assert-classic-6-5-release-line.ps1") `
    -RepositoryRoot $repoRoot -ReleaseVersion $release
$outputRoot = Resolve-RepoOutputPath $OutputDirectory
$expectedTocRelativePaths = @(
    foreach ($addon in $addonNames) {
        foreach ($flavor in $flavors) {
            "$addon/${addon}_$flavor.toc"
        }
    }
)

$sourceTocFiles = @(
    foreach ($addon in $addonNames) {
        $addonRoot = Join-Path $repoRoot $addon
        if (-not (Test-Path -LiteralPath $addonRoot -PathType Container)) {
            throw "Required addon directory is missing: $addonRoot"
        }
        Get-ChildItem -LiteralPath $addonRoot -Filter '*.toc' -File -Recurse
    }
)
$sourceTocRelativePaths = @($sourceTocFiles | ForEach-Object {
    $_.FullName.Substring($repoRoot.TrimEnd('\', '/').Length + 1).Replace('\', '/')
} | Sort-Object)
if (($sourceTocRelativePaths -join "`n") -ne (($expectedTocRelativePaths | Sort-Object) -join "`n")) {
    throw "Classic source must contain exactly 12 suffixed TOCs. Expected [$($expectedTocRelativePaths -join ', ')], got [$($sourceTocRelativePaths -join ', ')]."
}

$mainlineSourceHashes = @{}
$mainlineSourceVersions = @{}
foreach ($addon in $addonNames) {
    foreach ($flavor in $flavors) {
        $relative = "$addon/${addon}_$flavor.toc"
        $path = Join-Path $repoRoot ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
        $content = [IO.File]::ReadAllText($path)
        $null = Get-TocField -Content $content -Name 'Interface'
        $actualVersion = Get-TocField -Content $content -Name 'Version'
        if ($classicInterfaces.Contains($flavor)) {
            $actualInterface = Get-TocField -Content $content -Name 'Interface'
            if ($actualInterface -ne $classicInterfaces[$flavor]) {
                throw "$relative has Interface '$actualInterface'; expected '$($classicInterfaces[$flavor])'."
            }
            if ($actualVersion -ne $release) {
                throw "$relative has Version '$actualVersion'; expected Classic release '$release'."
            }
        }
        if ($flavor -eq 'Mainline') {
            $mainlineSourceHashes[$relative] = Get-Sha256 $path
            $mainlineSourceVersions[$relative] = $actualVersion
        }
    }
}

foreach ($flavor in $classicFlavors) {
    $relative = "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_$flavor.toc"
    $content = [IO.File]::ReadAllText((Join-Path $repoRoot ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))))
    $projectId = Get-TocField -Content $content -Name 'X-Curse-Project-ID'
    if ($projectId -ne $expectedProjectId) {
        throw "$relative has CurseForge project '$projectId'; expected '$expectedProjectId'."
    }
}

$changelogSection = Get-ChangelogSection -Path (Join-Path $repoRoot 'CHANGELOG.md') -Version $release
$releaseNotesMarkdown = (($changelogSection -join [Environment]::NewLine).TrimEnd() + [Environment]::NewLine)
$releaseNotesHtml = Convert-ChangelogSectionToHtml -Lines $changelogSection
if ([string]::IsNullOrWhiteSpace($releaseNotesHtml)) {
    throw "Generated CurseForge HTML changelog is empty for $release."
}

$trackedAddonPaths = @(& git -C $repoRoot ls-files -- @addonNames 2>&1)
if ($LASTEXITCODE -ne 0 -or $trackedAddonPaths.Count -eq 0) {
    throw "Could not enumerate tracked Classic addon files: $($trackedAddonPaths -join ', ')"
}
$trackedAddonPaths = @($trackedAddonPaths | ForEach-Object { $_.Replace('\', '/') } | Sort-Object -Unique)
foreach ($relative in $trackedAddonPaths) {
    if (-not ($addonNames | Where-Object { $relative.StartsWith("$_/", [StringComparison]::Ordinal) })) {
        throw "Tracked package path is outside the three addon roots: $relative"
    }
    $sourcePath = Join-Path $repoRoot ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Tracked package source is missing or not a file: $relative"
    }
}

$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$stageRoot = [IO.Path]::GetFullPath((Join-Path $tempBase ("msuf-classic-release-" + [guid]::NewGuid().ToString('N'))))
if (-not $stageRoot.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe temporary Classic package path: $stageRoot"
}

New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$zipPath = Join-Path $outputRoot "MSUF-$release-Mainline-Vanilla-Mists-TBC.zip"
$releaseNotesMarkdownPath = Join-Path $outputRoot 'RELEASE_NOTES_CLASSIC.md'
$releaseNotesHtmlPath = Join-Path $outputRoot 'RELEASE_NOTES_CLASSIC_CF.html'

try {
    New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null
    foreach ($relative in $trackedAddonPaths) {
        $relativePlatform = $relative.Replace('/', [IO.Path]::DirectorySeparatorChar)
        $sourcePath = Join-Path $repoRoot $relativePlatform
        $destinationPath = Join-Path $stageRoot $relativePlatform
        $destinationDirectory = Split-Path -Parent $destinationPath
        New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
    }

    Remove-ForbiddenStageArtifacts -StageRoot $stageRoot

    foreach ($addon in $addonNames) {
        foreach ($flavor in $classicFlavors) {
            $relative = "$addon/${addon}_$flavor.toc"
            $tocPath = Join-Path $stageRoot ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
            Set-StagedTocVersion -Path $tocPath -Version $release
        }
    }

    foreach ($relative in $mainlineSourceHashes.Keys) {
        $stagedPath = Join-Path $stageRoot ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
        $stagedHash = Get-Sha256 $stagedPath
        if ($stagedHash -ne $mainlineSourceHashes[$relative]) {
            throw "Mainline TOC changed while staging Classic release: $relative"
        }
    }

    $stagedTocs = @(Get-ChildItem -LiteralPath $stageRoot -Filter '*.toc' -File -Recurse | ForEach-Object {
        Get-RelativePath -Root $stageRoot -FullName $_.FullName
    } | Sort-Object)
    if (($stagedTocs -join "`n") -ne (($expectedTocRelativePaths | Sort-Object) -join "`n")) {
        throw "Classic package stage must contain exactly the expected 12 suffixed TOCs."
    }

    [IO.File]::WriteAllText($releaseNotesMarkdownPath, $releaseNotesMarkdown, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($releaseNotesHtmlPath, $releaseNotesHtml, [Text.UTF8Encoding]::new($false))

    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    Get-ChildItem -LiteralPath $stageRoot | Compress-Archive -DestinationPath $zipPath -CompressionLevel Optimal -Force

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $entryNames = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
        $fileEntryNames = @($archive.Entries | Where-Object { -not $_.FullName.EndsWith('/') } | ForEach-Object { $_.FullName.Replace('\', '/') })
        $topLevels = @($entryNames | ForEach-Object { ($_ -split '/', 2)[0] } | Where-Object { $_ } | Sort-Object -Unique)
        if (($topLevels -join "`n") -ne (($addonNames | Sort-Object) -join "`n")) {
            throw "Release zip top-level directories differ. Expected [$($addonNames -join ', ')], got [$($topLevels -join ', ')]."
        }

        $zipTocs = @($fileEntryNames | Where-Object { $_ -match '(?i)\.toc$' } | Sort-Object)
        if (($zipTocs -join "`n") -ne (($expectedTocRelativePaths | Sort-Object) -join "`n")) {
            throw "Release zip must contain exactly the expected 12 suffixed TOCs. Got [$($zipTocs -join ', ')]."
        }

        $forbiddenEntries = @($fileEntryNames | Where-Object { Test-ForbiddenArtifactPath -RelativePath $_ })
        if ($forbiddenEntries.Count -gt 0) {
            throw "Release zip contains forbidden local, documentation, test, Graphify, or Perfy artifacts: $($forbiddenEntries -join ', ')"
        }

        foreach ($addon in $addonNames) {
            foreach ($flavor in $flavors) {
                $relative = "$addon/${addon}_$flavor.toc"
                $content = Read-ZipEntryText -Archive $archive -EntryName $relative
                $actualVersion = Get-TocField -Content $content -Name 'Version'
                if ($flavor -eq 'Mainline') {
                    if ($actualVersion -ne $mainlineSourceVersions[$relative]) {
                        throw "Mainline TOC version changed in release zip: $relative ($actualVersion)."
                    }
                    $archiveHash = Get-ZipEntrySha256 -Archive $archive -EntryName $relative
                    if ($archiveHash -ne $mainlineSourceHashes[$relative]) {
                        throw "Mainline TOC bytes changed in release zip: $relative"
                    }
                } elseif ($actualVersion -ne $release) {
                    throw "Classic TOC version mismatch in release zip: $relative has '$actualVersion', expected '$release'."
                }
            }
        }

        foreach ($flavor in $classicFlavors) {
            $relative = "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_$flavor.toc"
            $content = Read-ZipEntryText -Archive $archive -EntryName $relative
            $projectId = Get-TocField -Content $content -Name 'X-Curse-Project-ID'
            if ($projectId -ne $expectedProjectId) {
                throw "Packaged Core Classic TOC has unexpected CurseForge project ID: $relative -> $projectId"
            }
        }
    } finally {
        $archive.Dispose()
    }
} finally {
    if (Test-Path -LiteralPath $stageRoot) {
        $resolvedStage = [IO.Path]::GetFullPath($stageRoot)
        if (-not $resolvedStage.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove unsafe temporary path: $resolvedStage"
        }
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force
    }
}

$zipHash = Get-Sha256 $zipPath
Write-Host "Classic release package validated: $zipPath"
Write-Host "Classic release version: $release"
Write-Host "Classic TOCs stamped: 9 (Vanilla, TBC, Mists); Mainline TOCs unchanged: 3"
Write-Host "CurseForge project: $expectedProjectId"
Write-Host "Classic TOC interfaces: $($classicInterfaces.Values -join ', ')"
Write-Host "SHA-256: $zipHash"
Write-Output $zipPath
