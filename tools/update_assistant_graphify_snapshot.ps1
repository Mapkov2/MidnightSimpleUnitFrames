[CmdletBinding()]
param(
    [ValidateRange(0, 128)]
    [int]$MaxWorkers = 0,

    [switch]$KeepStaging
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-OneSourceSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot
    )

    $result = @(& $ScriptPath -RepositoryRoot $RepositoryRoot)
    if ($result.Count -ne 1) {
        throw "Graphify source snapshot calculator returned $($result.Count) objects; expected exactly one."
    }
    return $result[0]
}

function Assert-SameSourceSnapshot {
    param(
        [Parameter(Mandatory = $true)]$Before,
        [Parameter(Mandatory = $true)]$After
    )

    foreach ($property in @("schemaVersion", "manifestFormat", "algorithm", "manifestSha256", "fileCount")) {
        if ($Before.$property -ne $After.$property) {
            throw "Addon source changed while Graphify was rebuilding ($property before='$($Before.$property)' after='$($After.$property)'). The graph snapshot was not certified."
        }
    }
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..")).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar)
$sourceSnapshotScript = Join-Path $PSScriptRoot "assistant_graphify_source_snapshot.ps1"
$updateScript = Join-Path $repoRoot "_local_workflows\scripts\update_msuf_graph.ps1"
$graphPath = Join-Path $repoRoot "graphify-out\graph.json"
$sidecarPath = Join-Path $repoRoot "graphify-out\.msuf-assistant-source-snapshot.json"

foreach ($required in @($sourceSnapshotScript, $updateScript)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required Graphify snapshot script is missing: $required"
    }
}

$beforeSource = Get-OneSourceSnapshot -ScriptPath $sourceSnapshotScript -RepositoryRoot $repoRoot
$beforeGraph = if (Test-Path -LiteralPath $graphPath -PathType Leaf) {
    $item = Get-Item -LiteralPath $graphPath
    [pscustomobject]@{
        Length = $item.Length
        CreationTimeUtcTicks = $item.CreationTimeUtc.Ticks
        LastWriteTimeUtcTicks = $item.LastWriteTimeUtc.Ticks
    }
} else {
    $null
}

# A failed or interrupted refresh must not leave an old certification beside a
# newly promoted or restored graph.
if (Test-Path -LiteralPath $sidecarPath -PathType Leaf) {
    Remove-Item -LiteralPath $sidecarPath -Force
}

$startedAtUtc = [System.DateTime]::UtcNow
$updateArguments = @{}
if ($MaxWorkers -gt 0) { $updateArguments.MaxWorkers = $MaxWorkers }
if ($KeepStaging) { $updateArguments.KeepStaging = $true }
& $updateScript @updateArguments

if (-not (Test-Path -LiteralPath $graphPath -PathType Leaf)) {
    throw "Graphify updater completed without producing '$graphPath'."
}
$afterGraph = Get-Item -LiteralPath $graphPath
if ($afterGraph.Length -le 0) {
    throw "Graphify updater produced an empty graph: '$graphPath'."
}
$graphWasRebuilt = $null -eq $beforeGraph -or
    $afterGraph.LastWriteTimeUtc.Ticks -ne $beforeGraph.LastWriteTimeUtcTicks -or
    $afterGraph.CreationTimeUtc.Ticks -ne $beforeGraph.CreationTimeUtcTicks -or
    $afterGraph.Length -ne $beforeGraph.Length
if (-not $graphWasRebuilt -or $afterGraph.LastWriteTimeUtc -lt $startedAtUtc.AddSeconds(-2)) {
    throw "Graphify updater did not leave evidence that '$graphPath' was rebuilt during this invocation."
}

$afterSource = Get-OneSourceSnapshot -ScriptPath $sourceSnapshotScript -RepositoryRoot $repoRoot
Assert-SameSourceSnapshot -Before $beforeSource -After $afterSource

$sidecar = [ordered]@{
    schemaVersion = [int]$afterSource.schemaVersion
    manifestFormat = [string]$afterSource.manifestFormat
    algorithm = [string]$afterSource.algorithm
    manifestSha256 = [string]$afterSource.manifestSha256
    fileCount = [int]$afterSource.fileCount
}
$json = $sidecar | ConvertTo-Json
$temporaryPath = $sidecarPath + "." + [System.Guid]::NewGuid().ToString("N") + ".tmp"
try {
    [System.IO.File]::WriteAllText(
        $temporaryPath,
        $json + "`n",
        [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $sidecarPath -Force
} finally {
    if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
        Remove-Item -LiteralPath $temporaryPath -Force
    }
}

Write-Host ("Assistant Graphify source snapshot certified: {0} files, SHA256 {1}" -f
    $afterSource.fileCount, $afterSource.manifestSha256)
Write-Output $graphPath
