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

function Get-RawFileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read)
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '')
    } finally {
        $stream.Dispose()
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
    $fullAddonRoot = Join-Path $repoRoot $addonRoot
    if (-not (Test-Path -LiteralPath $fullAddonRoot -PathType Container)) {
        throw "Graphify source root is missing: $addonRoot"
    }
    foreach ($path in [System.IO.Directory]::GetFiles(
        $fullAddonRoot, "*", [System.IO.SearchOption]::AllDirectories)) {
        $extension = [System.IO.Path]::GetExtension($path)
        if (-not ($extension.Equals(".lua", [System.StringComparison]::OrdinalIgnoreCase) -or
            $extension.Equals(".xml", [System.StringComparison]::OrdinalIgnoreCase) -or
            $extension.Equals(".toc", [System.StringComparison]::OrdinalIgnoreCase))) {
            continue
        }
        $relative = $path.Substring($repoRoot.Length).TrimStart(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar).Replace('\', '/')
        if ($pathByRelative.ContainsKey($relative)) {
            throw "Duplicate Graphify source-manifest path: $relative"
        }
        $pathByRelative.Add($relative, $path)
    }
}

$relativePaths = @($pathByRelative.Keys)
[System.Array]::Sort($relativePaths, [System.StringComparer]::Ordinal)
if ($relativePaths.Count -eq 0) {
    throw "Graphify source manifest is empty."
}

# v1 is an ordinal list of `relative/path<TAB>RAW_FILE_SHA256<LF>` rows.
# Both the path separator and final LF are explicit so locale, filesystem
# enumeration order, and Windows newline settings cannot change the digest.
$manifestRows = [System.Collections.Generic.List[string]]::new()
foreach ($relative in $relativePaths) {
    $manifestRows.Add(("{0}`t{1}" -f $relative, (Get-RawFileSha256 -Path $pathByRelative[$relative])))
}
$manifestText = [string]::Join("`n", $manifestRows.ToArray()) + "`n"
$manifestBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($manifestText)

[pscustomobject]@{
    schemaVersion = 1
    manifestFormat = "msuf-addon-source-sha256-v1"
    algorithm = "SHA256"
    manifestSha256 = ConvertTo-Sha256Hex -Bytes $manifestBytes
    fileCount = $relativePaths.Count
}
