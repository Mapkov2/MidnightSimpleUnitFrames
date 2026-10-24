# Shared, portable tool resolution and serial execution for the compact checks.
function Resolve-CheckTool([string]$Explicit, [string]$EnvironmentName, [string[]]$Names) {
    $requested = $Explicit
    if (-not $requested) { $requested = [Environment]::GetEnvironmentVariable($EnvironmentName) }
    $candidates = @()
    if ($requested) { $candidates += $requested }
    else {
        foreach ($name in $Names) { $candidates += (Join-Path $PSScriptRoot "lua51/$name") }
        $candidates += $Names
    }
    foreach ($candidate in $candidates) {
        # Windows' App Execution Aliases (WindowsApps\python3.exe) are Store stubs, not interpreters.
        $command = Get-Command $candidate -CommandType Application -ErrorAction SilentlyContinue |
            Where-Object { $_.Source -notmatch '\\WindowsApps\\' } | Select-Object -First 1
        if ($command) { return $command.Source }
    }
    throw "Missing tool ($($Names -join ', ')). Bundle it in tools/lua51, put it on PATH, or set $EnvironmentName. Requested: $requested"
}
function Initialize-CheckTools([string]$Lua, [string]$Luac, [string]$Python) {
    $script:Lua = Resolve-CheckTool $Lua 'MSUF_LUA' @('lua5.1', 'lua.exe', 'lua')
    if (-not $Luac) {
        foreach ($name in @('luac5.1', 'luac.exe', 'luac')) {
            $sibling = Join-Path (Split-Path -Parent $script:Lua) $name
            if (Test-Path -LiteralPath $sibling -PathType Leaf) { $Luac = $sibling; break }
        }
    }
    $script:Luac = Resolve-CheckTool $Luac 'MSUF_LUAC' @('luac5.1', 'luac.exe', 'luac')
    $script:Python = Resolve-CheckTool $Python 'MSUF_PYTHON' @('python3', 'python.exe', 'python')
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
    foreach ($tool in @($script:Lua, $script:Luac)) {
        $version = & $tool -v 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0 -or $version -notmatch 'Lua 5\.1\.') { throw "Lua 5.1 required: $tool ($version)" }
    }
    $version = & $script:Python --version 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $version -notmatch 'Python 3\.(1[2-9]|[2-9][0-9])\.') { throw "Python 3.12+ required: $version" }
    } finally { $ErrorActionPreference = $previous }
    $script:PowerShell = (Get-Process -Id $PID).Path
}
function Enter-CheckSlot([string]$Slot, [string]$Owner, [string]$MutexName = 'MSUF-Compact-Checks') {
    if ($Slot) {
        & $script:PowerShell -NoProfile -File $Slot -Acquire -Owner $Owner -What 'compact checks' -Holder $PID | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'Lua slot acquisition failed' }
    } else {
        $script:CheckMutex = New-Object Threading.Mutex($false, $MutexName)
        Write-Host 'Waiting for compact-check slot...'
        try { [void]$script:CheckMutex.WaitOne() } catch [Threading.AbandonedMutexException] { }
    }
}
function Exit-CheckSlot([string]$Slot, [string]$Owner) {
    if ($Slot) { & $script:PowerShell -NoProfile -File $Slot -Release -Owner $Owner | Out-Host }
    elseif ($script:CheckMutex) { $script:CheckMutex.ReleaseMutex(); $script:CheckMutex.Dispose() }
}
function Get-CheckRevision([string]$Root) {
    $revision = & git -C $Root rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { throw "Cannot identify checked commit in $Root" }
    $dirty = @(& git -c core.excludesFile= -C $Root status --porcelain --untracked-files=no)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot identify working-tree state' }
    return "commit $revision; tracked working-tree changes: $($dirty.Count)"
}
