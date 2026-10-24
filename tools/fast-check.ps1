param([string]$Owner = "fast-check")
# 10/10 plan safety net (owner 2026-10-24): replaces the frozen 2101-run gate during the refactor.
# 1. compile every shipped Mainline file + static load order on all clients (ready_check.sh)
# 2. real TOC boot of every client (zero chunk failures, reviewed globals)
# 3. profile safety: sparse persistence + client transfer per client, legacy marker retention
# 4. quality ratchet (static)
# Runs inside the shared Lua slot (owner CPU rule). Exit 0 = all green.
$ErrorActionPreference = "Continue"
$root = "C:/MSUF Beta Branch/MidnightSimpleUnitFrames-7.0"
$lua = "C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe"
$bash = "C:\Program Files\Git\bin\bash.exe"
$log = "C:\tmp\m7\d\fast-check-$Owner.log"
$start = Get-Date
& powershell -NoProfile -File "C:\tmp\m7\lua-slot.ps1" -Acquire -Owner $Owner -What "fast-check" -Holder $PID | Out-Null
$results = New-Object System.Collections.Generic.List[string]
$fail = 0
function Step([string]$name, [scriptblock]$body) {
    $out = & $body 2>&1 | Out-String
    $ok = ($LASTEXITCODE -eq 0)
    if ($name -eq "ready") { $ok = $ok -and ($out -match "0 with syntax errors") -and ($out -match "TOTAL ERRORS 0") }
    if (-not $ok) { $script:fail++; Add-Content -Path $log -Value "=== FAIL $name`n$out" -Encoding utf8 }
    $script:results.Add(("{0} {1}" -f ($(if ($ok) { "PASS" } else { "FAIL" }), $name)))
}
Set-Content -Path $log -Value "fast-check $Owner $(Get-Date -Format s)" -Encoding utf8
Push-Location $root
try {
    Step "ready" { & $bash -c "bash /c/tmp/m7/d/ready_check.sh" }
    foreach ($flavor in @("Mainline", "Vanilla", "TBC", "Mists", "Forever")) {
        Step "boot:$flavor" { & $lua "tools/tests/client_boot_smoke.lua" "$root/" $flavor }
        Step "sparse-persist:$flavor" { & $lua "tools/tests/profile_sparse_persistence_smoke.lua" "$root/" $flavor }
        Step "sparse-transfer:$flavor" { & $lua "tools/tests/profile_sparse_client_transfer_smoke.lua" "$root/" $flavor }
    }
    Step "sparse-legacy-markers" { & $lua "tools/tests/profile_sparse_backward_migration_smoke.lua" "$root/" }
    Step "ratchet" { & python "tools/quality_ratchet.py" --check }
} finally {
    Pop-Location
    & powershell -NoProfile -File "C:\tmp\m7\lua-slot.ps1" -Release -Owner $Owner | Out-Null
}
$results | ForEach-Object { $_ }
"fast-check: $fail failed, {0:N0} s, details in $log" -f ((Get-Date) - $start).TotalSeconds
exit $fail
