[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [Parameter(Mandatory = $true)][string]$ReleaseVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# An owner-requested hotfix may retain its previous beta's exact changelog.
# Reuse is explicit per release; normal releases still require their own notes.
$path = Join-Path $RepositoryRoot "tools/classic-changelog-reuse.tsv"
if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $ReleaseVersion }
$seen = @{}
$resolved = $ReleaseVersion
foreach ($row in @(Import-Csv -LiteralPath $path -Delimiter "`t")) {
    $source = [regex]::Match($row.ReleaseVersion, '^(?<base>\d+(?:\.\d+)*)-beta(?<number>\d+)$')
    $notes = [regex]::Match($row.ChangelogVersion, '^(?<base>\d+(?:\.\d+)*)-beta(?<number>\d+)$')
    if (-not $source.Success -or -not $notes.Success -or
        $source.Groups['base'].Value -cne $notes.Groups['base'].Value -or
        [int]$notes.Groups['number'].Value -ge [int]$source.Groups['number'].Value) {
        throw "Changelog reuse must name an earlier beta of the same release line: $($row.ReleaseVersion)."
    }
    if ($seen.ContainsKey($row.ReleaseVersion)) { throw "Duplicate changelog reuse: $($row.ReleaseVersion)." }
    $seen[$row.ReleaseVersion] = $true
    if ($row.ReleaseVersion -ceq $ReleaseVersion) { $resolved = $row.ChangelogVersion }
}
if ($resolved -cne $ReleaseVersion) {
    $text = [IO.File]::ReadAllText((Join-Path $RepositoryRoot "CHANGELOG.md"))
    if ($text -match "(?m)^## $([regex]::Escape($ReleaseVersion))\s+-\s+") {
        throw "Changelog reuse would override authored notes for $ReleaseVersion."
    }
}
return $resolved
