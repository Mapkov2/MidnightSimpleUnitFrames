[CmdletBinding()]
param(
    [string]$LuaCommand = "lua",
    [string]$BaselineSourceRoot,
    [string]$OptimizationBaselineSourceRoot,
    [string]$ReportDirectory
)

$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$lua = Get-Command $LuaCommand -ErrorAction Stop
if ([string]::IsNullOrWhiteSpace($ReportDirectory)) {
    $ReportDirectory = Join-Path $repositoryRoot "_local_workflows/auras3-refactor"
}
$null = New-Item -ItemType Directory -Force -Path $ReportDirectory
$candidateTrace = Join-Path $ReportDirectory "native-candidate.operations"
$baselineTrace = Join-Path $ReportDirectory "native-baseline.operations"
$driver = Join-Path $PSScriptRoot "auras3_test_driver.lua"
$nativeTest = Join-Path $PSScriptRoot "auras3_owner_sharing_smoke.lua"
$aliasTest = Join-Path $PSScriptRoot "auras3_alias_catalog_smoke.lua"
$oldSourceRoot = $env:MSUF_AURAS3_TEST_SOURCE_ROOT
$oldTracePath = $env:MSUF_AURAS3_TEST_TRACE_PATH
$oldVisualTrace = $env:MSUF_AURAS3_VISUAL_TRACE
$oldWorkTrace = $env:MSUF_AURAS3_WORK_TRACE
Push-Location $repositoryRoot
try {
    Remove-Item Env:\MSUF_AURAS3_TEST_SOURCE_ROOT -ErrorAction SilentlyContinue
    & $lua.Source (Join-Path $PSScriptRoot "auras3_refactor_contract_smoke.lua") $repositoryRoot
    if ($LASTEXITCODE -ne 0) { throw "Auras3 XML/factory contracts failed." }
    & $lua.Source (Join-Path $PSScriptRoot "aura_icon_style_gate_smoke.lua") $repositoryRoot
    if ($LASTEXITCODE -ne 0) { throw "Auras3 icon-style gate lifecycle failed." }

    foreach ($test in @("auras3_filter_compile_smoke.lua", "auras3_scope_cache_smoke.lua", "auras3_preview_read_context_smoke.lua", "auras3_group_indicator_compile_smoke.lua")) {
        & $lua.Source (Join-Path $PSScriptRoot $test) $repositoryRoot
        if ($LASTEXITCODE -ne 0) { throw "Auras3 optimization contract failed: $test" }
    }

    $env:MSUF_AURAS3_TEST_TRACE_PATH = $candidateTrace
    $candidateVisual = Join-Path $ReportDirectory "visual-candidate.txt"
    $candidateWork = Join-Path $ReportDirectory "work-candidate.txt"
    $env:MSUF_AURAS3_VISUAL_TRACE = $candidateVisual
    $env:MSUF_AURAS3_WORK_TRACE = $candidateWork
    & $lua.Source $driver $nativeTest $repositoryRoot
    if ($LASTEXITCODE -ne 0) { throw "Auras3 candidate native contracts failed." }
    & $lua.Source $aliasTest $repositoryRoot
    if ($LASTEXITCODE -ne 0) { throw "Auras3 candidate alias contracts failed." }
    & $lua.Source $driver (Join-Path $PSScriptRoot "auras3_alias_native_smoke.lua") $repositoryRoot
    if ($LASTEXITCODE -ne 0) { throw "Auras3 native custom alias contracts failed." }
    if (-not [string]::IsNullOrWhiteSpace($BaselineSourceRoot)) {
        $env:MSUF_AURAS3_TEST_SOURCE_ROOT = (Resolve-Path -LiteralPath $BaselineSourceRoot).Path
        $env:MSUF_AURAS3_TEST_TRACE_PATH = $baselineTrace
        $baselineVisual = Join-Path $ReportDirectory "visual-baseline.txt"
        $baselineWork = Join-Path $ReportDirectory "work-baseline.txt"
        $env:MSUF_AURAS3_VISUAL_TRACE = $baselineVisual
        $env:MSUF_AURAS3_WORK_TRACE = $baselineWork
        & $lua.Source $driver $nativeTest $repositoryRoot
        if ($LASTEXITCODE -ne 0) { throw "Auras3 frozen baseline native contracts failed." }
        # Owner/slot sharing intentionally removes native calls. Compare actual
        # per-visual selections, geometry, alpha, layers and native input instead.
        $candidateHash = (Get-FileHash -LiteralPath $candidateVisual -Algorithm SHA256).Hash
        $baselineHash = (Get-FileHash -LiteralPath $baselineVisual -Algorithm SHA256).Hash
        if ($candidateHash -ne $baselineHash) {
            throw "Auras3 visual/selection contracts differ. Inspect $candidateVisual and $baselineVisual."
        }
        $before = [System.IO.File]::ReadAllLines($baselineWork)
        $after = [System.IO.File]::ReadAllLines($candidateWork)
        if ($before.Length -ne $after.Length) { throw "Owner work scenario count changed." }
        for ($i = 0; $i -lt $before.Length; $i++) {
            $left, $right = $before[$i].Split('|'), $after[$i].Split('|')
            if ($left[0] -ne $right[0] -or [int]$right[1] -gt [int]$left[1]) { throw "Native owner work increased: $($before[$i]) -> $($after[$i])" }
            if ($left.Length -eq 5 -and [int]$right[2] -gt [int]$left[2]) { throw "Native slot work increased: $($left[0])" }
            $firstFeature = if ($left.Length -eq 5) { 3 } else { 2 }
            for ($j = $firstFeature; $j -lt $left.Length; $j++) {
                if ($left[$j] -ne $right[$j]) { throw "Displayed feature count changed: $($left[0])" }
            }
        }
        Write-Host "PASS: baseline/candidate visual contracts match ($candidateHash); native owner/slot work did not increase."
        if (Test-Path -LiteralPath (Join-Path $BaselineSourceRoot "MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_Schema.lua")) {
            & $lua.Source (Join-Path $PSScriptRoot "auras3_schema_equivalence_smoke.lua") $repositoryRoot $BaselineSourceRoot
            if ($LASTEXITCODE -ne 0) { throw "Auras3 schema comparison failed." }
        }
    }
    # These fixtures assert improvements introduced before owner sharing. Their
    # denominator must explicitly be the earlier, pre-optimization snapshot.
    if (-not [string]::IsNullOrWhiteSpace($OptimizationBaselineSourceRoot)) {
        Remove-Item Env:\MSUF_AURAS3_TEST_SOURCE_ROOT -ErrorAction SilentlyContinue
        foreach ($test in @("auras3_filter_compile_smoke.lua", "auras3_scope_cache_smoke.lua", "auras3_group_indicator_compile_smoke.lua")) {
            & $lua.Source (Join-Path $PSScriptRoot $test) $repositoryRoot $OptimizationBaselineSourceRoot
            if ($LASTEXITCODE -ne 0) { throw "Auras3 earlier optimization comparison failed: $test" }
        }
    }
} finally {
    $env:MSUF_AURAS3_TEST_SOURCE_ROOT = $oldSourceRoot
    $env:MSUF_AURAS3_TEST_TRACE_PATH = $oldTracePath
    $env:MSUF_AURAS3_VISUAL_TRACE = $oldVisualTrace
    $env:MSUF_AURAS3_WORK_TRACE = $oldWorkTrace
    Pop-Location
}
