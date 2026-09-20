[CmdletBinding()]
param(
    [string]$RetailReferenceRoot = "",
    [switch]$SelfContained,
    [switch]$AllowMissingTools,
    [switch]$ListSmokes,
    [string]$Only = "",
    [switch]$FailFast,
    [int]$Jobs = 0,
    [switch]$RequireNoSkippedSteps,
    [string]$LuaPath = "",
    [string]$LuacPath = "",
    [string]$PythonPath = ""
)

# One command runs the Classic gate: it finds Lua 5.1, luac 5.1 and Python,
# prints the versions it is about to use, refuses with a remediation message
# when one is missing or the wrong version, and forwards everything else to
# tools/test-classic-prototype.ps1.
#
# Parameters win over MSUF_LUA / MSUF_LUAC / MSUF_PYTHON, which win over PATH.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# PowerShell 5.1 encodes what it pipes to a native process with the console
# code page. On a UTF-8 console that means a BOM in front of the first line,
# which git reads as part of a path and `git hash-object --stdin-paths` then
# fails on. Setting the console encodings here fixes it for this process and
# every child, without a chcp wrapper. A redirected console has no encoding to
# set, so the assignment is allowed to fail.
$bomlessUtf8 = New-Object Text.UTF8Encoding $false
try { [Console]::InputEncoding = $bomlessUtf8 } catch { }
try { [Console]::OutputEncoding = $bomlessUtf8 } catch { }

function Resolve-GateTool {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Explicit,
        [Parameter(Mandatory = $true)][string]$EnvironmentName,
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string[]]$VersionArguments,
        [Parameter(Mandatory = $true)][string]$VersionPattern,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Remediation
    )

    $source = ""
    $origin = ""
    if (-not [string]::IsNullOrWhiteSpace($Explicit)) {
        $source = $Explicit
        $origin = "parameter"
    } elseif (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($EnvironmentName))) {
        $source = [Environment]::GetEnvironmentVariable($EnvironmentName)
        $origin = "`$env:$EnvironmentName"
    } else {
        $found = Get-Command $Command -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $source = $found.Source
            $origin = "PATH"
        }
    }
    if ([string]::IsNullOrWhiteSpace($source)) {
        throw "$Name was not found. $Remediation"
    }
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        $resolved = Get-Command $source -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $resolved) { throw "$Name is not an executable file: $source. $Remediation" }
        $source = $resolved.Source
    }

    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $exitCode = 0
    try {
        $reported = @(& $source @VersionArguments 2>&1 | ForEach-Object { [string]$_ }) -join " "
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    $reported = $reported.Trim()
    if ($exitCode -ne 0 -or $reported -notmatch $VersionPattern) {
        throw "$Name must be $Expected, but $source ($origin) reports '$reported'. $Remediation"
    }
    Write-Host ("{0,-6} {1}  ({2}, from {3})" -f $Name, $reported, $source, $origin)
    return $source
}

$luaRemediation = "Point the gate at a Lua 5.1 interpreter with -LuaPath, set `$env:MSUF_LUA, or put one first on PATH. Lua 5.4 cannot run these smokes: they use unpack() and loadstring()."
$luacRemediation = "Point the gate at the Lua 5.1 compiler with -LuacPath, set `$env:MSUF_LUAC, or put one first on PATH. luac 5.1 sits next to the lua 5.1 binary."
$pythonRemediation = "Point the gate at a Python 3 interpreter with -PythonPath, set `$env:MSUF_PYTHON, or put one first on PATH. On Windows a bare 'python' can be the Store alias stub, which exits without running anything."

$luaSource = Resolve-GateTool -Name "lua" -Explicit $LuaPath -EnvironmentName "MSUF_LUA" -Command "lua" `
    -VersionArguments @("-e", "io.write(_VERSION)") -VersionPattern '^Lua 5\.1$' -Expected "Lua 5.1" -Remediation $luaRemediation
$luacSource = Resolve-GateTool -Name "luac" -Explicit $LuacPath -EnvironmentName "MSUF_LUAC" -Command "luac" `
    -VersionArguments @("-v") -VersionPattern '^Lua 5\.1(?:\.\d+)?\s' -Expected "Lua 5.1" -Remediation $luacRemediation
$pythonSource = Resolve-GateTool -Name "python" -Explicit $PythonPath -EnvironmentName "MSUF_PYTHON" -Command "python" `
    -VersionArguments @("--version") -VersionPattern '^Python 3\.' -Expected "Python 3" -Remediation $pythonRemediation

# The gate resolves lua, luac and python from PATH, so the resolved directories
# go first on PATH for this process only.
$toolDirectories = @($luaSource, $luacSource, $pythonSource) | ForEach-Object { Split-Path -Parent $_ } | Select-Object -Unique
$env:PATH = (@($toolDirectories) + @($env:PATH)) -join [IO.Path]::PathSeparator

$gate = Join-Path $PSScriptRoot "test-classic-prototype.ps1"
if (-not (Test-Path -LiteralPath $gate -PathType Leaf)) {
    throw "The Classic gate is missing next to this wrapper: $gate"
}
$forwarded = @{}
if (-not [string]::IsNullOrWhiteSpace($RetailReferenceRoot)) { $forwarded["RetailReferenceRoot"] = $RetailReferenceRoot }
if ($SelfContained) { $forwarded["SelfContained"] = $true }
if ($AllowMissingTools) { $forwarded["AllowMissingTools"] = $true }
if ($ListSmokes) { $forwarded["ListSmokes"] = $true }
if (-not [string]::IsNullOrWhiteSpace($Only)) { $forwarded["Only"] = $Only }
if ($FailFast) { $forwarded["FailFast"] = $true }
if ($Jobs -gt 0) { $forwarded["Jobs"] = $Jobs }
if ($RequireNoSkippedSteps) { $forwarded["RequireNoSkippedSteps"] = $true }

# The gate is not written against Set-StrictMode, and a wrapper must not change
# how it behaves, so strict mode ends here.
Set-StrictMode -Off
& $gate @forwarded
