param(
    [string]$Owner = "C7",
    [string]$Lua = "C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe",
    [string]$Python = "C:\Users\Marco\AppData\Local\Programs\Python\Python312-32\python.exe",
    [string]$FastCheck = "C:\tmp\m7\d\fast-check.ps1",
    [string]$Slot = "C:\tmp\m7\lua-slot.ps1",
    [string]$LogDirectory = "C:\tmp\m7\d\reports"
)
# Compact offline release contracts. The frozen gate is never invoked.
# Fast-check owns its slot; the suite acquires it immediately afterwards.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$luaCompiler = Join-Path (Split-Path -Parent $Lua) "luac.exe"
foreach ($file in @($Lua, $luaCompiler, $Python, $FastCheck, $Slot)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing release-check dependency: $file" }
}
[void][IO.Directory]::CreateDirectory($LogDirectory)
$log = Join-Path $LogDirectory ("release-check-{0}-{1}.log" -f $Owner, (Get-Date -Format "yyyyMMdd-HHmmss"))
$utf8 = New-Object Text.UTF8Encoding($false)
$nl = [Environment]::NewLine
[IO.File]::WriteAllText($log, "release-check $Owner$nl", $utf8)
$oldPath = $env:PATH
$env:PATH = (Split-Path -Parent $Python) + ";" + $env:PATH
$summary = New-Object 'System.Collections.Generic.List[string]'
$failed = 0
$wall = [Diagnostics.Stopwatch]::StartNew()
$slotTime = 0.0
function Invoke-Check([string]$Name, [string]$Executable, [string[]]$Arguments) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = (& $Executable @Arguments 2>&1 | Out-String)
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    [IO.File]::AppendAllText($log, "=== $Name ($code, $($timer.Elapsed.TotalSeconds.ToString('F2')) s)$nl$output$nl", $utf8)
    return @{ Ok = ($code -eq 0); Text = $output; Seconds = $timer.Elapsed.TotalSeconds }
}
function Contract([string]$Name, [object[]]$Runs) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $bad = New-Object 'System.Collections.Generic.List[string]'
    foreach ($run in $Runs) {
        $result = Invoke-Check "$Name/$($run.Label)" $run.Exe $run.Args
        if (-not $result.Ok) { $bad.Add($run.Label) }
    }
    $status = if ($bad.Count -eq 0) { "PASS" } else { $script:failed++; "FAIL" }
    $detail = if ($bad.Count) { "; failed: " + ($bad -join ", ") } else { "" }
    $line = "{0} {1}: {2} runs, {3:F1} s{4}" -f $status, $Name, $Runs.Count, $timer.Elapsed.TotalSeconds, $detail
    $script:summary.Add($line)
    Write-Output $line
}
function LuaRun([string]$Smoke, [string]$Flavor, [string]$Mode = "") {
    $arguments = @("$root/tools/tests/$Smoke", "$root/", $Flavor)
    if ($Mode) { $arguments += $Mode }
    return @{ Label = "$Smoke/$Flavor"; Exe = $Lua; Args = $arguments }
}
Push-Location $root
try {
    Contract "generated lists" @(
        @{ Label = "module-manifest"; Exe = $Python; Args = @("tools/generate_module_manifest.py", "--check") }
    )
    if ($failed) {
        Write-Output "release-check: $failed failed; generated lists are stale or invalid; log $log"
        exit 1
    }
    $fast = Invoke-Check "fast-check" "powershell" @("-NoProfile", "-File", $FastCheck, "-Owner", $Owner)
    $fastOk = $fast.Ok -and $fast.Text -match "fast-check: 0 failed,"
    if (-not $fastOk) { $failed++ }
    if ($fast.Text -match "fast-check: \d+ failed, ([\d.,]+) s,") {
        $slotTime += [double]::Parse($Matches[1].Replace(",", ""), [Globalization.CultureInfo]::InvariantCulture)
    } else { $slotTime += $fast.Seconds }
    $line = "{0} fast-check: {1:F1} s" -f $(if ($fastOk) { "PASS" } else { "FAIL" }), $fast.Seconds
    $summary.Add($line)
    Write-Output $line
    & powershell -NoProfile -File $Slot -Acquire -Owner $Owner -What "compact release contracts" -Holder $PID | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Lua slot acquisition failed" }
    $suiteTime = [Diagnostics.Stopwatch]::StartNew()
    try {
        Contract "profiles" @(
            (LuaRun "release_profiles_smoke.lua" "Mainline"),
            (LuaRun "release_profiles_smoke.lua" "Vanilla"),
            (LuaRun "release_profiles_smoke.lua" "Forever"),
            (LuaRun "release_profiles_smoke.lua" "Mists")
        )
        Contract "apply path" @(
            (LuaRun "release_apply_smoke.lua" "Mainline"),
            (LuaRun "release_apply_smoke.lua" "Vanilla")
        )
        Contract "menu" @(
            (LuaRun "release_menu_smoke.lua" "Mainline"),
            (LuaRun "release_menu_smoke.lua" "Vanilla"),
            (LuaRun "release_menu_smoke.lua" "TBC"),
            (LuaRun "release_menu_smoke.lua" "Mists"),
            (LuaRun "release_menu_smoke.lua" "Forever")
        )
        Contract "review fixes" @(
            (LuaRun "profile_newer_revision_backup_smoke.lua" "Mainline"),
            (LuaRun "profile_newer_revision_backup_smoke.lua" "Vanilla"),
            (LuaRun "profile_newer_revision_backup_smoke.lua" "TBC"),
            (LuaRun "profile_newer_revision_backup_smoke.lua" "Mists"),
            (LuaRun "profile_newer_revision_backup_smoke.lua" "Forever"),
            (LuaRun "text_drain_writer_recovery_smoke.lua" "Mainline")
        )
        Contract "C12 regressions" @(
            (LuaRun "menu_page_rebuild_leak_smoke.lua" "Mainline"),
            (LuaRun "menu_page_rebuild_leak_smoke.lua" "Vanilla"),
            (LuaRun "search_cold_metadata_smoke.lua" "Mainline"),
            (LuaRun "search_cold_metadata_smoke.lua" "Vanilla"),
            (LuaRun "guided_tour_restore_retention_smoke.lua" "Mainline"),
            (LuaRun "group_preview_configured_glow_smoke.lua" "Mainline"),
            (LuaRun "group_preview_configured_glow_smoke.lua" "Vanilla"),
            (LuaRun "group_preview_configured_glow_smoke.lua" "Forever")
        )
        Contract "namespace" @(
            @{ Label = "mutation-proof"; Exe = $Python; Args = @("tools/tests/flip_check_smoke.py", "--luac", $luaCompiler) },
            @{ Label = "flip"; Exe = $Python; Args = @("tools/flip_check.py", $root, "--luac", $luaCompiler) }
        )
        Contract "group preview" @(
            (LuaRun "group_preview_scene_lifecycle_smoke.lua" "Mainline" "release"),
            (LuaRun "group_preview_scene_lifecycle_smoke.lua" "Vanilla" "release"),
            (LuaRun "group_preview_scene_lifecycle_smoke.lua" "Forever" "release"),
            (LuaRun "group_preview_combat_restore_smoke.lua" "Mainline"),
            (LuaRun "group_preview_combat_restore_smoke.lua" "Forever")
        )
        Contract "Edit Mode" @(
            (LuaRun "release_apply_smoke.lua" "Mainline" "edit"),
            (LuaRun "release_apply_smoke.lua" "Vanilla" "edit"),
            (LuaRun "editmode_core_history_smoke.lua" "Mainline"),
            (LuaRun "editmode_core_history_smoke.lua" "Vanilla")
        )
    } finally {
        $slotTime += $suiteTime.Elapsed.TotalSeconds
        & powershell -NoProfile -File $Slot -Release -Owner $Owner | Out-Null
    }
} finally {
    Pop-Location
    $env:PATH = $oldPath
}
if ($slotTime -ge 300) { $failed++; Write-Output "FAIL time budget: must be under 300 s inside the Lua slot" }
$final = "release-check: {0} failed; {1:F1} s inside Lua slots; {2:F1} s elapsed; log {3}" -f $failed, $slotTime, $wall.Elapsed.TotalSeconds, $log
[IO.File]::AppendAllText($log, ($summary -join $nl) + "$nl$final$nl", $utf8)
Write-Output $final
if ($failed) { exit 1 }
exit 0
