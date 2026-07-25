[CmdletBinding()]
param(
    [string]$RepositoryRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function ConvertTo-Sha256Hex {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '')
    } finally {
        $sha.Dispose()
    }
}

function Get-NormalizedTextFileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $raw = [System.IO.File]::ReadAllBytes($Path)
    $normalized = [System.IO.MemoryStream]::new($raw.Length)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        for ($index = 0; $index -lt $raw.Length; $index++) {
            if ($raw[$index] -eq 13) {
                # Git may materialize the same text blob as LF or CRLF depending
                # on checkout platform/config. Canonicalize both (and lone CR)
                # to LF without decoding or otherwise changing file bytes.
                $normalized.WriteByte(10)
                if ($index + 1 -lt $raw.Length -and $raw[$index + 1] -eq 10) {
                    $index++
                }
            } else {
                $normalized.WriteByte($raw[$index])
            }
        }
        $normalized.Position = 0
        return ([System.BitConverter]::ToString($sha.ComputeHash($normalized))).Replace('-', '')
    } finally {
        $normalized.Dispose()
        $sha.Dispose()
    }
}

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Join-Path $PSScriptRoot ".."
}
$repoRoot = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar)

$addonRoots = @(
    "MidnightSimpleUnitFrames",
    "MidnightSimpleUnitFrames_Assistant"
)
$pathByRelative = [System.Collections.Generic.Dictionary[string, string]]::new(
    [System.StringComparer]::Ordinal)

foreach ($addonRoot in $addonRoots) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $addonRoot) -PathType Container)) {
        throw "Graphify source root is missing: $addonRoot"
    }
}

# Match the future release closure: tracked files plus non-ignored new files
# that can be added to the same commit. Local ignored audit helpers must never
# make a Graphify inventory impossible to reproduce from a clean checkout.
$relativeCandidates = @(& git -C $repoRoot ls-files --cached --others --exclude-standard -- @addonRoots)
if ($LASTEXITCODE -ne 0) {
    throw "Could not enumerate the Git-owned Graphify source closure."
}
foreach ($candidate in $relativeCandidates) {
    $relative = ([string]$candidate).Replace('\', '/')
    $extension = [System.IO.Path]::GetExtension($relative)
    if (-not ($extension.Equals(".lua", [System.StringComparison]::OrdinalIgnoreCase) -or
        $extension.Equals(".xml", [System.StringComparison]::OrdinalIgnoreCase) -or
        $extension.Equals(".toc", [System.StringComparison]::OrdinalIgnoreCase))) {
        continue
    }
    $path = Join-Path $repoRoot $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    if ($pathByRelative.ContainsKey($relative)) {
        throw "Duplicate Graphify source-manifest path: $relative"
    }
    $pathByRelative.Add($relative, $path)
}

$relativePaths = @($pathByRelative.Keys)
[System.Array]::Sort($relativePaths, [System.StringComparer]::Ordinal)
if ($relativePaths.Count -eq 0) {
    throw "Graphify source manifest is empty."
}

# v2 is an ordinal list of
# `relative/path<TAB>LF_NORMALIZED_TEXT_FILE_SHA256<LF>` rows. Paths, manifest
# newlines, and source newlines are canonical so Windows and Unix checkouts of
# the same Git blobs certify the same source snapshot.
$manifestRows = [System.Collections.Generic.List[string]]::new()
foreach ($relative in $relativePaths) {
    $manifestRows.Add(("{0}`t{1}" -f $relative, (Get-NormalizedTextFileSha256 -Path $pathByRelative[$relative])))
}
$manifestText = [string]::Join("`n", $manifestRows.ToArray()) + "`n"
$manifestBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($manifestText)

[pscustomobject]@{
    schemaVersion = 2
    manifestFormat = "msuf-addon-source-sha256-v2"
    algorithm = "SHA256"
    manifestSha256 = ConvertTo-Sha256Hex -Bytes $manifestBytes
    fileCount = $relativePaths.Count
}
