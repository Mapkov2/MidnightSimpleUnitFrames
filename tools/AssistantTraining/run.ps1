param(
    [string]$Root,
    [string]$Out,
    [string]$Lua51,
    [ValidateRange(0, [int]::MaxValue)]
    [int]$GeneratedLimit = 0,
    [switch]$SeedOnly,
    [switch]$StrictLoad,
    [switch]$FailSlow,
    [double]$SlowMs = 8
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..\..")
$addonRoot = Join-Path $repoRoot.Path "MidnightSimpleUnitFrames_Assistant"
if (Test-Path (Join-Path $repoRoot.Path "MSUF_AssistantRuntime.xml")) { $addonRoot = $repoRoot.Path }

if (-not $Root -or $Root.Trim() -eq "") {
    $Root = $addonRoot
}

if (-not $Out -or $Out.Trim() -eq "") {
    $Out = Join-Path $scriptDir "out"
}

New-Item -ItemType Directory -Force -Path $Out | Out-Null

$wowLua51Gate = Join-Path $repoRoot.Path "tools\test-wow-lua51-loadability.ps1"
& $wowLua51Gate -RepoRoot $repoRoot.Path -Lua51 $Lua51

$lua = Get-Command lua -ErrorAction SilentlyContinue
if (-not $lua) {
    throw "The Lua interpreter was not found on PATH. Install lua (luac alone cannot execute this gate) or add it to PATH."
}

$argsList = @(
    (Join-Path $repoRoot.Path "tools\lua51_bom_runner.lua"),
    (Join-Path $scriptDir "runner.lua"),
    "--root", $Root,
    "--out", $Out,
    "--generated-limit", [string]$GeneratedLimit,
    "--slow-ms", [string]$SlowMs,
    "--strict-load"
)

if ($SeedOnly) {
    $argsList += "--seed-only"
}
if ($FailSlow) {
    $argsList += "--fail-slow"
}

& $lua.Source @argsList
exit $LASTEXITCODE
