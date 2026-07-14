param(
    [string]$RepoRoot,
    [string]$Lua51,
    [string[]]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-ExecutablePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Candidate
    )

    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        return $null
    }

    if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
        return (Resolve-Path -LiteralPath $Candidate).Path
    }

    $command = Get-Command $Candidate -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        return $command.Source
    }

    return $null
}

function Get-LuaVersionText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Executable
    )

    # PUC Lua writes its version banner to stderr. PowerShell 5 promotes native
    # stderr to an ErrorRecord when ErrorActionPreference is Stop, even on exit 0.
    $oldErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = @(& $Executable -v 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }
    if ($exitCode -ne 0) {
        return $null
    }

    return (($output | ForEach-Object { [string]$_ }) -join " ").Trim()
}

function Resolve-Lua51Path {
    param(
        [string]$Override
    )

    $requested = $Override
    $requestedBy = "-Lua51"
    if ([string]::IsNullOrWhiteSpace($requested) -and -not [string]::IsNullOrWhiteSpace($env:MSUF_LUA51)) {
        $requested = $env:MSUF_LUA51
        $requestedBy = "MSUF_LUA51"
    }

    if (-not [string]::IsNullOrWhiteSpace($requested)) {
        $resolved = Resolve-ExecutablePath -Candidate $requested
        if (-not $resolved) {
            throw "$requestedBy points to '$requested', but that Lua executable could not be found."
        }

        $version = Get-LuaVersionText -Executable $resolved
        if (-not $version -or $version -notmatch '(?i)\bLua\s+5\.1(?:\.|\s|$)') {
            if (-not $version) { $version = "version probe failed" }
            throw "$requestedBy resolved to '$resolved', but it is not Lua 5.1 ($version). Lua 5.2+ does not enforce WoW's 60-upvalue limit."
        }

        return [pscustomobject]@{
            Path = $resolved
            Version = $version
        }
    }

    $rejected = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in @("lua51", "lua5.1", "lua")) {
        $resolved = Resolve-ExecutablePath -Candidate $candidate
        if (-not $resolved) {
            continue
        }

        $version = Get-LuaVersionText -Executable $resolved
        if ($version -and $version -match '(?i)\bLua\s+5\.1(?:\.|\s|$)') {
            return [pscustomobject]@{
                Path = $resolved
                Version = $version
            }
        }

        if (-not $version) { $version = "version probe failed" }
        $rejected.Add("$resolved ($version)")
    }

    $details = if ($rejected.Count -gt 0) {
        " Rejected non-5.1 interpreter(s): " + ($rejected -join "; ") + "."
    } else {
        ""
    }
    throw (
        "A real Lua 5.1 interpreter is required for the WoW loadability gate." +
        " Pass -Lua51 <path>, set MSUF_LUA51, or put lua51/lua5.1 on PATH." +
        " Lua 5.4 syntax checks cannot detect WoW's 60-upvalue, 200-local, and expression-complexity compiler limits." +
        $details
    )
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $gitOutput = @(& git -C $scriptDir rev-parse --show-toplevel 2>$null)
    $gitExitCode = $LASTEXITCODE
    $gitRoot = if ($gitOutput.Count -gt 0) { [string]$gitOutput[0] } else { $null }
    if ($gitExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($gitRoot)) {
        throw "Could not discover the repository root with git. Pass -RepoRoot explicitly."
    }
    $RepoRoot = $gitRoot
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

if (-not $SourceRoot -or $SourceRoot.Count -eq 0) {
    $SourceRoot = @(
        "MidnightSimpleUnitFrames",
        "MidnightSimpleUnitFrames_Assistant",
        "MidnightCooldownManager",
        "MidnightCooldownManager_Options"
    )
}

$resolvedRoots = New-Object System.Collections.Generic.List[string]
foreach ($root in $SourceRoot) {
    $candidate = $root
    if (-not [IO.Path]::IsPathRooted($candidate)) {
        $candidate = Join-Path $RepoRoot $candidate
    }

    if (Test-Path -LiteralPath $candidate -PathType Container) {
        $resolvedRoots.Add((Resolve-Path -LiteralPath $candidate).Path)
    } elseif ($PSBoundParameters.ContainsKey("SourceRoot")) {
        throw "Source root '$candidate' does not exist or is not a directory."
    }
}

if ($resolvedRoots.Count -eq 0) {
    throw "No addon source roots were found below '$RepoRoot'."
}

$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$luaFiles = New-Object System.Collections.Generic.List[string]
foreach ($root in $resolvedRoots) {
    foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File -Filter "*.lua") {
        if ($seen.Add($file.FullName)) {
            $luaFiles.Add($file.FullName)
        }
    }
}

$sortedFiles = @($luaFiles | Sort-Object)
if ($sortedFiles.Count -eq 0) {
    throw "No Lua files were found in: $($resolvedRoots -join ', ')"
}

$lua = Resolve-Lua51Path -Override $Lua51
$tempDir = Join-Path ([IO.Path]::GetTempPath()) ("msuf-wow-lua51-gate-" + [Guid]::NewGuid().ToString("N"))
$manifestPath = Join-Path $tempDir "files.txt"
$driverPath = Join-Path $tempDir "compile.lua"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$driver = @'
local manifest_path = assert(arg and arg[1], "missing file manifest")
local manifest = assert(io.open(manifest_path, "rb"))
local failures = {}
local compiled = 0
local bom_count = 0

for path in manifest:lines() do
    path = string.gsub(path, "\r$", "")
    if path ~= "" then
        local handle, open_error = io.open(path, "rb")
        if not handle then
            failures[#failures + 1] = path .. ": " .. tostring(open_error)
        else
            local source = handle:read("*a")
            handle:close()

            if string.sub(source, 1, 3) == "\239\187\191" then
                source = string.sub(source, 4)
                bom_count = bom_count + 1
            end

            local chunk, compile_error = loadstring(source, "@" .. path)
            if chunk then
                compiled = compiled + 1
            else
                failures[#failures + 1] = tostring(compile_error)
            end
        end
    end
end
manifest:close()

if #failures > 0 then
    io.write("WoW Lua 5.1 loadability: ", compiled, " passed, ", #failures, " failed\n")
    for index = 1, #failures do
        io.write("FAIL ", failures[index], "\n")
    end
    os.exit(1)
end

io.write("WoW Lua 5.1 loadability: ", compiled, " files passed (", bom_count, " UTF-8 BOMs stripped)\n")
'@

try {
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    [IO.File]::WriteAllLines($manifestPath, $sortedFiles, $utf8NoBom)
    [IO.File]::WriteAllText($driverPath, $driver, $utf8NoBom)

    Write-Host "WoW compiler: $($lua.Version) [$($lua.Path)]"
    $output = @(& $lua.Path $driverPath $manifestPath 2>&1)
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) {
        Write-Host ([string]$line)
    }

    if ($exitCode -ne 0) {
        throw "WoW Lua 5.1 rejected one or more addon files. Fix every FAIL entry before release."
    }
} finally {
    if (Test-Path -LiteralPath $tempDir) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force
    }
}
