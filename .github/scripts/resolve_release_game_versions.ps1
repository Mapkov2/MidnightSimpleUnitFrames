[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ClientMatrixPath,
    # Game version names the publishing site knows. Empty when the list could not be read.
    [string[]]$AvailableNames = @()
)

# Turns the CurseForgeVersions column of the client matrix into the game version
# names of one upload, Retail client first, then Classic clients from the oldest
# game generation up.
#
# A matrix entry is an exact name ("12.1.5") or a prefix ending in "*" ("1.6*").
# A prefix follows a client whose patches move without a TOC change: it resolves
# to the newest available name that starts with it, so a new WoW Forever patch
# needs no edit here. With no available list, exact names pass through unchanged
# and prefixes are dropped; with a list, names the site does not know are dropped
# with a warning instead of failing the upload.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$clientMatrix = @(Import-Csv -LiteralPath $ClientMatrixPath -Delimiter "`t")
if ($clientMatrix.Count -eq 0) { throw "$ClientMatrixPath names no clients." }

$versionClients = @($clientMatrix | Sort-Object -Property @(
    @{ Expression = { $_.IsClassic -ceq "true" } },
    @{ Expression = { @(([string]$_.Interfaces -split ',') | ForEach-Object { [int]$_.Trim() } | Sort-Object)[0] } }
))
$wanted = @(
    foreach ($client in $versionClients) {
        foreach ($entry in ([string]$client.CurseForgeVersions -split ',')) { $entry.Trim() }
    }
)
if ($wanted.Count -eq 0 -or @($wanted | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
    throw "$ClientMatrixPath must give every client at least one game version and no blank names. Got: [$($wanted -join ', ')]"
}

function ConvertTo-VersionKey {
    param([Parameter(Mandatory = $true)][string]$Name)
    $parts = @($Name -split '\.' | ForEach-Object { if ($_ -match '^\d+$') { [int]$_ } else { 0 } })
    return ($parts | ForEach-Object { '{0:D6}' -f $_ }) -join '.'
}

$available = @($AvailableNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() } | Sort-Object -Unique)
$resolved = [System.Collections.Generic.List[string]]::new()
foreach ($entry in $wanted) {
    if ($entry.EndsWith("*")) {
        $prefix = $entry.TrimEnd("*")
        $candidates = @($available | Where-Object { $_.StartsWith($prefix, [StringComparison]::Ordinal) -and $_ -match '^\d+(\.\d+)+$' })
        if ($candidates.Count -eq 0) {
            Write-Host "::warning::No available game version starts with '$prefix'; the upload carries none for it."
            continue
        }
        $name = @($candidates | Sort-Object -Property @{ Expression = { ConvertTo-VersionKey -Name $_ } })[-1]
        Write-Host "Game version '$entry' resolved to $name."
    } else {
        $name = $entry
        if ($available.Count -gt 0 -and $available -cnotcontains $name) {
            Write-Host "::warning::Game version '$name' is not available on the publishing site; the upload skips it."
            continue
        }
    }
    if (-not $resolved.Contains($name)) { $resolved.Add($name) }
}
if ($resolved.Count -eq 0) { throw "No game version of [$($wanted -join ', ')] is available." }
return [string[]]$resolved.ToArray()
