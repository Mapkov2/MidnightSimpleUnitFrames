param(
    [string]$Owner = 'fast-check', [string]$Lua, [string]$Luac, [string]$Python,
    [string]$Slot = $env:MSUF_LUA_SLOT, [string]$LogDirectory
)
# Portable safety net; release-check is the CI entry point and owns the full inventory.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'check-common.ps1')
Initialize-CheckTools $Lua $Luac $Python
if (-not $LogDirectory) { $LogDirectory = Join-Path $root 'dist/checks' }
[void][IO.Directory]::CreateDirectory($LogDirectory)
$log = Join-Path $LogDirectory ("fast-check-{0}.log" -f ($Owner -replace '[^a-zA-Z0-9_-]', '_'))
$utf8 = New-Object Text.UTF8Encoding($false)
$revision = Get-CheckRevision $root
[IO.File]::WriteAllText($log, "fast-check $Owner; $revision`n", $utf8)
Write-Output $revision
$start = Get-Date
$results = New-Object 'System.Collections.Generic.List[string]'
$fail = 0
function Step([string]$Name, [scriptblock]$Body) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = & $Body 2>&1 | Out-String; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $previous }
    if ($code -ne 0) { $script:fail++ }
    [IO.File]::AppendAllText($log, "=== $Name ($code)`n$output`n", $utf8)
    $script:results.Add(("{0} {1}" -f $(if ($code -eq 0) { 'PASS' } else { 'FAIL' }), $Name))
}
Enter-CheckSlot $Slot $Owner
$start = Get-Date
Push-Location $root
try {
    Step 'syntax and load order' { & $Python tools/check_ready.py --root $root --luac $Luac }
    foreach ($flavor in @('Mainline', 'Vanilla', 'TBC', 'Mists', 'Forever')) {
        Step "boot:$flavor" { & $Lua tools/tests/client_boot_smoke.lua "$root/" $flavor }
        Step "sparse-persist:$flavor" { & $Lua tools/tests/profile_sparse_persistence_smoke.lua "$root/" $flavor }
        Step "sparse-transfer:$flavor" { & $Lua tools/tests/profile_sparse_client_transfer_smoke.lua "$root/" $flavor }
    }
    Step 'sparse-legacy-markers' { & $Lua tools/tests/profile_sparse_backward_migration_smoke.lua "$root/" }
    Step 'ratchet' { & $Python tools/quality_ratchet.py --check --luac $Luac }
} finally { Pop-Location; Exit-CheckSlot $Slot $Owner }
$results | ForEach-Object { $_ }
"fast-check: $fail failed, {0:N0} s, details in $log" -f ((Get-Date) - $start).TotalSeconds
exit $fail
