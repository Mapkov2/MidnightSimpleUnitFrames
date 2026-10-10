[CmdletBinding()]
param(
    [string]$OutputDirectory = "dist",
    [string]$RetailReferenceRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = (git rev-parse --show-toplevel).Trim()
if (-not $root) { throw "Repository root could not be resolved." }

$validationArgs = @{}
if (-not [string]::IsNullOrWhiteSpace($RetailReferenceRoot)) {
    $validationArgs.RetailReferenceRoot = $RetailReferenceRoot
}
& (Join-Path $root "tools/test-classic-prototype.ps1") @validationArgs
if ($LASTEXITCODE -ne 0) { throw "Classic prototype validation failed." }

$version = (Get-Content -LiteralPath (Join-Path $root "VERSION") -Raw).Trim()
if (-not $version) { throw "VERSION is empty." }

# One packager: the tracked CI builder stages only git-tracked files, strips
# docs/tools/luac.out and validates the zip, so a local build equals a CI build.
$releaseBuilder = Join-Path $root ".github/scripts/build_classic_release_package.ps1"
$builderOutput = @(& $releaseBuilder -ReleaseVersion ("classic-v" + $version) -OutputDirectory $OutputDirectory)
if ($builderOutput.Count -eq 0) { throw "Classic release builder returned no package path." }
$zip = [string]$builderOutput[-1]
if (-not (Test-Path -LiteralPath $zip -PathType Leaf)) {
    throw "Classic release builder did not produce its package: $zip"
}

Write-Host $zip
