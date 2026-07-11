param(
  [string]$AddonName = "MidnightSimpleUnitFrames",
  [string]$SourceRoot = "",
  [string]$PerfyRef = "main",
  [string]$PerfyZip = "",
  [string]$PerfySource = "",
  [string]$LuaLanguageServer = "",
  [string]$OutputDir = "dist/perfy",
  [string]$WorkDir = "dist/perfy-work",
  [bool]$InstrumentAllLua = $true,
  [switch]$KeepStage
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Join-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }

  return [System.IO.Path]::GetFullPath((Join-Path $script:RepoRoot $Path))
}

function Resolve-Executable {
  param([AllowNull()][AllowEmptyString()][string]$Value)

  if (-not [string]::IsNullOrWhiteSpace($Value)) {
    if (Test-Path -LiteralPath $Value) {
      return (Resolve-Path -LiteralPath $Value).Path
    }

    $command = Get-Command $Value -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
      return $command.Source
    }
  }

  return $null
}

function Get-LuaLanguageServerRoot {
  param([Parameter(Mandatory = $true)][string]$Executable)

  $binDir = Split-Path -Parent (Resolve-Path -LiteralPath $Executable).Path
  $candidates = @(
    (Split-Path -Parent $binDir),
    $binDir
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath (Join-Path $candidate "script/log.lua")) {
      return $candidate
    }
  }

  throw "Could not find LuaLS runtime root for '$Executable'. Expected script/log.lua next to the LuaLS install."
}

function Get-FirstNonEmptyLine {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return ""
  }

  $line = Get-Content -LiteralPath $Path | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
  if ($line) {
    return $line.Trim()
  }

  return ""
}

function Get-TocVersion {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return ""
  }

  $content = Get-Content -LiteralPath $Path -Raw
  $match = [regex]::Match($content, "(?m)^##\s+Version:\s*(.+?)\s*$")
  if ($match.Success) {
    return $match.Groups[1].Value.Trim()
  }

  return ""
}

function Expand-PerfyArchive {
  param(
    [Parameter(Mandatory = $true)][string]$ZipPath,
    [Parameter(Mandatory = $true)][string]$Destination
  )

  if (Test-Path -LiteralPath $Destination) {
    Remove-Item -LiteralPath $Destination -Recurse -Force
  }

  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  Expand-Archive -LiteralPath $ZipPath -DestinationPath $Destination -Force

  $candidates = @((Get-Item -LiteralPath $Destination))
  $candidates += Get-ChildItem -LiteralPath $Destination -Directory -Recurse
  $perfyRoot = $candidates | Where-Object {
    (Test-Path -LiteralPath (Join-Path $_.FullName "Instrumentation/Main.lua")) -and
    (Test-Path -LiteralPath (Join-Path $_.FullName "AddOn/!!!Perfy.toc"))
  } | Select-Object -First 1

  if (-not $perfyRoot) {
    throw "Could not find Perfy source in '$ZipPath'. Expected Instrumentation/Main.lua and AddOn/!!!Perfy.toc."
  }

  return $perfyRoot.FullName
}

function Get-PerfyRoot {
  param(
    [Parameter(Mandatory = $true)][string]$DepsDir,
    [Parameter(Mandatory = $true)][string]$PerfyRef,
    [string]$PerfyZip,
    [string]$PerfySource
  )

  if (-not [string]::IsNullOrWhiteSpace($PerfySource)) {
    $sourceRoot = (Resolve-Path -LiteralPath $PerfySource).Path
    if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot "Instrumentation/Main.lua"))) {
      throw "PerfySource '$sourceRoot' does not contain Instrumentation/Main.lua."
    }
    if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot "AddOn/!!!Perfy.toc"))) {
      throw "PerfySource '$sourceRoot' does not contain AddOn/!!!Perfy.toc."
    }
    return $sourceRoot
  }

  if (-not [string]::IsNullOrWhiteSpace($PerfyZip)) {
    $zipPath = (Resolve-Path -LiteralPath $PerfyZip).Path
  } else {
    New-Item -ItemType Directory -Force -Path $DepsDir | Out-Null
    $zipPath = Join-Path $DepsDir ("Perfy-{0}.zip" -f (($PerfyRef -replace '[\\/:*?""<>|]', '-') -replace '\s+', '-'))
    $uri = "https://github.com/emmericp/Perfy/archive/$PerfyRef.zip"
    Write-Host "Downloading Perfy from $uri"
    Invoke-WebRequest -Uri $uri -OutFile $zipPath -Headers @{ "User-Agent" = "MSUF-Perfy-Workflow" }
  }

  return Expand-PerfyArchive -ZipPath $zipPath -Destination (Join-Path $DepsDir "perfy-source")
}

function Repair-PerfyForCurrentLuaLs {
  param([Parameter(Mandatory = $true)][string]$PerfyRoot)

  $tocHandler = Join-Path $PerfyRoot "Instrumentation/TocHandler.lua"
  $lines = @(Get-Content -LiteralPath $tocHandler)
  $changed = $false
  $patched = New-Object System.Collections.Generic.List[string]

  foreach ($line in $lines) {
    if ($line -match '^(\s*)for ref in (xml:gmatch\(.*\)) do\s*$') {
      $patched.Add("$($Matches[1])for rawRef in $($Matches[2]) do")
      $patched.Add("$($Matches[1])`tlocal ref = rawRef")
      $changed = $true
    } else {
      $patched.Add($line)
    }
  }

  if ($changed) {
    [System.IO.File]::WriteAllText($tocHandler, (($patched -join [Environment]::NewLine) + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
    Write-Host "Applied LuaLS compatibility patch to Perfy TocHandler.lua in staging."
  }
}

function Patch-PerfyInstrumentorForWowLimits {
  param([Parameter(Mandatory = $true)][string]$PerfyRoot)

  $instrumentPath = Join-Path $PerfyRoot "Instrumentation/Instrument.lua"
  if (-not (Test-Path -LiteralPath $instrumentPath)) {
    throw "Perfy Instrument.lua not found: $instrumentPath"
  }

  $content = Get-Content -LiteralPath $instrumentPath -Raw
  $localCacheInjection = 'injections[#injections + 1] = {pos = 0, text = perfyTag .. " local Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough = Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough;" .. perfyEnterFile}'
  $globalSafeInjection = 'injections[#injections + 1] = {pos = 0, text = perfyTag .. perfyEnterFile}'

  if ($content.Contains($localCacheInjection)) {
    $content = $content.Replace($localCacheInjection, $globalSafeInjection)
    [System.IO.File]::WriteAllText($instrumentPath, $content, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Patched Perfy Instrument.lua to avoid injected local Perfy upvalues for WoW Lua limits."
  } elseif ($content.Contains($globalSafeInjection)) {
    Write-Host "Perfy Instrument.lua already uses WoW-safe global Perfy calls."
  } else {
    throw "Could not patch Perfy Instrument.lua. Expected local cache injection was not found."
  }
}

function Set-PerfyInterfaceVersion {
  param(
    [Parameter(Mandatory = $true)][string]$PerfyAddonDir,
    [Parameter(Mandatory = $true)][string]$InterfaceVersion
  )

  $tocPath = Join-Path $PerfyAddonDir "!!!Perfy.toc"
  if (-not (Test-Path -LiteralPath $tocPath)) {
    throw "Perfy TOC not found: $tocPath"
  }

  $content = Get-Content -LiteralPath $tocPath -Raw
  if ($content -match "(?m)^##\s+Interface:\s*\d+\s*$") {
    $content = [regex]::Replace($content, "(?m)^##\s+Interface:\s*\d+\s*$", "## Interface: $InterfaceVersion", 1)
  } else {
    $content = "## Interface: $InterfaceVersion" + [Environment]::NewLine + $content
  }
  [System.IO.File]::WriteAllText($tocPath, $content, [System.Text.UTF8Encoding]::new($false))
  Write-Host "Set Perfy TOC interface to $InterfaceVersion in staging."
}

function Add-MSUFPerfyFpsSampler {
  param([Parameter(Mandatory = $true)][string]$PerfyAddonDir)

  $luaPath = Join-Path $PerfyAddonDir "MSUF_PerfyFPS.lua"
  $tocPath = Join-Path $PerfyAddonDir "!!!Perfy.toc"
  if (-not (Test-Path -LiteralPath $tocPath)) {
    throw "Perfy TOC not found: $tocPath"
  }

  $sampler = @'
-- MSUF Perfy FPS sampler. Generated by Build-PerfyPackage.ps1.
-- Lives in !!!Perfy only; the MSUF source tree is not instrumented or changed.
local Perfy_Running = _G.Perfy_Running
local Perfy_Trace = _G.Perfy_Trace
local Perfy_GetTime = _G.Perfy_GetTime or _G.GetTimePreciseSec or _G.GetTime
local GetFramerate = _G.GetFramerate
local CreateFrame = _G.CreateFrame
local C_Timer = _G.C_Timer

if not (Perfy_Running and Perfy_Trace and Perfy_GetTime and GetFramerate and CreateFrame) then
    return
end

local LABEL = "MSUF.PerfyFPS"
local interval = tonumber(_G.MSUF_PERFY_FPS_INTERVAL) or 1.0
if interval < 0.25 then interval = 0.25 end
if interval > 5.0 then interval = 5.0 end

local format = string.format
local frame = CreateFrame("Frame")
frame:Hide()

local windowElapsed, windowFrames, windowWorst, windowBest = 0, 0, 0, nil
local totalElapsed, totalFrames, totalWorst = 0, 0, 0
local apiSum, apiMin, apiMax, apiSamples = 0, nil, nil, 0

local function Reset()
    windowElapsed, windowFrames, windowWorst, windowBest = 0, 0, 0, nil
    totalElapsed, totalFrames, totalWorst = 0, 0, 0
    apiSum, apiMin, apiMax, apiSamples = 0, nil, nil, 0
end

local function Running()
    return Perfy_Running and Perfy_Running()
end

local function Mark(kind)
    if not Running() then return end
    local api = tonumber(GetFramerate()) or 0
    apiSum = apiSum + api
    apiSamples = apiSamples + 1
    apiMin = apiMin and math.min(apiMin, api) or api
    apiMax = apiMax and math.max(apiMax, api) or api

    local frameAvg = windowElapsed > 0 and (windowFrames / windowElapsed) or api
    local totalAvg = totalElapsed > 0 and (totalFrames / totalElapsed) or api
    local apiAvg = apiSamples > 0 and (apiSum / apiSamples) or api
    local worstMs = (windowWorst or 0) * 1000
    local totalWorstMs = (totalWorst or 0) * 1000
    local bestMs = (windowBest or 0) * 1000

    Perfy_Trace(Perfy_GetTime(), "Mark", LABEL, format(
        "kind=%s;fps=%.1f;frameAvg=%.1f;totalAvg=%.1f;worstMs=%.2f;totalWorstMs=%.2f;bestMs=%.2f;frames=%d;apiAvg=%.1f;apiMin=%.1f;apiMax=%.1f",
        tostring(kind or "sample"),
        api,
        frameAvg,
        totalAvg,
        worstMs,
        totalWorstMs,
        bestMs,
        windowFrames,
        apiAvg,
        apiMin or api,
        apiMax or api
    ))
end

local function ResetWindow()
    windowElapsed, windowFrames, windowWorst, windowBest = 0, 0, 0, nil
end

frame:SetScript("OnUpdate", function(_, elapsed)
    if not Running() then
        frame:Hide()
        return
    end
    elapsed = tonumber(elapsed) or 0
    if elapsed <= 0 then return end
    windowElapsed = windowElapsed + elapsed
    windowFrames = windowFrames + 1
    if elapsed > windowWorst then windowWorst = elapsed end
    if not windowBest or elapsed < windowBest then windowBest = elapsed end
    totalElapsed = totalElapsed + elapsed
    totalFrames = totalFrames + 1
    if elapsed > totalWorst then totalWorst = elapsed end
    if windowElapsed >= interval then
        Mark("sample")
        ResetWindow()
    end
end)

local function StartSampling()
    Reset()
    Mark("start")
    frame:Show()
end

local function StopSampling()
    if frame:IsShown() then
        Mark("stop")
        frame:Hide()
    end
end

local originalStart = _G.Perfy_Start
if type(originalStart) == "function" then
    _G.Perfy_Start = function(...)
        local result = originalStart(...)
        if Running() then StartSampling() end
        return result
    end
end

local originalStop = _G.Perfy_Stop
if type(originalStop) == "function" then
    _G.Perfy_Stop = function(...)
        StopSampling()
        return originalStop(...)
    end
end

local originalClear = _G.Perfy_Clear
if type(originalClear) == "function" then
    _G.Perfy_Clear = function(...)
        StopSampling()
        return originalClear(...)
    end
end

if C_Timer and C_Timer.After then
    C_Timer.After(0, function()
        if Running() then StartSampling() end
    end)
elseif Running() then
    StartSampling()
end
'@
  [System.IO.File]::WriteAllText($luaPath, ($sampler + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))

  $toc = Get-Content -LiteralPath $tocPath -Raw
  if ($toc -notmatch "(?m)^MSUF_PerfyFPS\.lua\s*$") {
    if ($toc -match "(?m)^Perfy\.lua\s*$") {
      $toc = [regex]::Replace($toc, "(?m)^Perfy\.lua\s*$", "Perfy.lua$([Environment]::NewLine)MSUF_PerfyFPS.lua", 1)
    } else {
      $toc = $toc.TrimEnd() + [Environment]::NewLine + "MSUF_PerfyFPS.lua" + [Environment]::NewLine
    }
    [System.IO.File]::WriteAllText($tocPath, $toc, [System.Text.UTF8Encoding]::new($false))
  }

  Write-Host "Added MSUF Perfy FPS sampler to staging."
}

function Test-PerfyInstrumentedFile {
  param([Parameter(Mandatory = $true)][string]$Path)

  $firstLine = Get-Content -LiteralPath $Path -TotalCount 1 -ErrorAction Stop
  return ([string]$firstLine).StartsWith("--[[Perfy has instrumented this file]]", [System.StringComparison]::Ordinal)
}

function Invoke-PerfyInstrumentation {
  param(
    [Parameter(Mandatory = $true)][string]$LuaLanguageServer,
    [Parameter(Mandatory = $true)][string]$LuaLanguageServerRoot,
    [Parameter(Mandatory = $true)][string]$PerfyMain,
    [Parameter(Mandatory = $true)][string[]]$InputFiles
  )

  if ($InputFiles.Count -eq 0) {
    return
  }

  $perfyMainArg = $PerfyMain -replace '\\', '/'
  $inputFileArgs = @($InputFiles | ForEach-Object { $_ -replace '\\', '/' })

  Push-Location -LiteralPath $LuaLanguageServerRoot
  try {
    $commandOutput = & $LuaLanguageServer $perfyMainArg @inputFileArgs 2>&1
    $exitCode = $LASTEXITCODE
  } finally {
    Pop-Location
  }
  foreach ($line in $commandOutput) {
    Write-Host $line
  }

  if ($exitCode -ne 0) {
    throw "Perfy instrumentation failed with exit code $exitCode."
  }
}

$script:ScriptRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../.."))
$script:RepoRoot = if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
  $script:ScriptRepoRoot
} else {
  [System.IO.Path]::GetFullPath($SourceRoot)
}
$addonSource = Join-RepoPath $AddonName
$tocSource = Join-Path $addonSource "$AddonName.toc"
$assistantAddonSource = Join-RepoPath "${AddonName}_Assistant"
$assistantTocSource = Join-Path $assistantAddonSource "${AddonName}_Assistant.toc"
$localeAddonSource = Join-RepoPath "${AddonName}_Locales"
$localeTocSource = Join-Path $localeAddonSource "${AddonName}_Locales.toc"

if (-not (Test-Path -LiteralPath $addonSource)) {
  throw "Addon folder not found: $addonSource"
}
if (-not (Test-Path -LiteralPath $tocSource)) {
  throw "Addon TOC not found: $tocSource"
}
$hasAssistantAddon = Test-Path -LiteralPath $assistantTocSource -PathType Leaf
$hasLocaleAddon = Test-Path -LiteralPath $localeTocSource -PathType Leaf

$resolvedLls = Resolve-Executable $LuaLanguageServer
if (-not $resolvedLls) {
  $resolvedLls = Resolve-Executable $env:LUALS_BIN
}
if (-not $resolvedLls) {
  $resolvedLls = Resolve-Executable $env:LUA_LANGUAGE_SERVER
}
if (-not $resolvedLls) {
  $resolvedLls = Resolve-Executable "lua-language-server"
}
if (-not $resolvedLls) {
  throw "lua-language-server was not found. Pass -LuaLanguageServer, set LUALS_BIN, or add it to PATH."
}
$resolvedLlsRoot = Get-LuaLanguageServerRoot $resolvedLls

$outputRoot = Join-RepoPath $OutputDir
$workRoot = Join-RepoPath $WorkDir
$depsDir = Join-Path $workRoot "_deps"
$stageRoot = Join-Path $workRoot "AddOns"
$stagedAddon = Join-Path $stageRoot $AddonName
$stagedToc = Join-Path $stagedAddon "$AddonName.toc"

if (Test-Path -LiteralPath $workRoot) {
  Remove-Item -LiteralPath $workRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null

$perfyRoot = Get-PerfyRoot -DepsDir $depsDir -PerfyRef $PerfyRef -PerfyZip $PerfyZip -PerfySource $PerfySource
Repair-PerfyForCurrentLuaLs $perfyRoot
Patch-PerfyInstrumentorForWowLimits $perfyRoot
$perfyMain = Join-Path $perfyRoot "Instrumentation/Main.lua"
$perfyAddonSource = Join-Path $perfyRoot "AddOn"

Write-Host "Copying $AddonName to staging folder $stagedAddon"
Copy-Item -LiteralPath $addonSource -Destination $stageRoot -Recurse -Force
if ($hasAssistantAddon) {
  Copy-Item -LiteralPath $assistantAddonSource -Destination $stageRoot -Recurse -Force
}
if ($hasLocaleAddon) {
  Copy-Item -LiteralPath $localeAddonSource -Destination $stageRoot -Recurse -Force
}

foreach ($relativePath in @("docs", "scripts", "tools", "MSUF_PerfyHook.lua", ".gitignore")) {
  $fullPath = Join-Path $stagedAddon $relativePath
  if (Test-Path -LiteralPath $fullPath) {
    Remove-Item -LiteralPath $fullPath -Recurse -Force
  }
}

foreach ($localDirectoryName in @(
  ".codex-remote-attachments",
  "docs",
  "scripts",
  "tools",
  "_local_workflows",
  "graphify-out",
  "__pycache__"
)) {
  Get-ChildItem -LiteralPath $stagedAddon -Directory -Force -Recurse -Filter $localDirectoryName |
    ForEach-Object {
      Remove-Item -LiteralPath $_.FullName -Recurse -Force
    }
}

$perfyAddonTarget = Join-Path $stageRoot "!!!Perfy"
Write-Host "Adding Perfy AddOn as $perfyAddonTarget"
Copy-Item -LiteralPath $perfyAddonSource -Destination $perfyAddonTarget -Recurse -Force
Set-PerfyInterfaceVersion -PerfyAddonDir $perfyAddonTarget -InterfaceVersion "120000"
Add-MSUFPerfyFpsSampler -PerfyAddonDir $perfyAddonTarget

Write-Host "Instrumenting TOC/XML reachable Lua files with Perfy"
$stagedAssistantToc = Join-Path $stageRoot "${AddonName}_Assistant/${AddonName}_Assistant.toc"
$entryTocs = @($stagedToc)
if ($hasAssistantAddon) { $entryTocs += $stagedAssistantToc }
Invoke-PerfyInstrumentation -LuaLanguageServer $resolvedLls -LuaLanguageServerRoot $resolvedLlsRoot -PerfyMain $perfyMain -InputFiles $entryTocs

$allLuaFiles = @(Get-ChildItem -LiteralPath $stagedAddon -Filter "*.lua" -Recurse -File | Sort-Object FullName)
if ($InstrumentAllLua) {
  $remainingLuaFiles = @($allLuaFiles | Where-Object { -not (Test-PerfyInstrumentedFile $_.FullName) })
  if ($remainingLuaFiles.Count -gt 0) {
    Write-Host "Instrumenting $($remainingLuaFiles.Count) additional Lua files not reached from TOC/XML"
    $batchSize = 25
    for ($offset = 0; $offset -lt $remainingLuaFiles.Count; $offset += $batchSize) {
      $batch = @($remainingLuaFiles | Select-Object -Skip $offset -First $batchSize)
      Invoke-PerfyInstrumentation -LuaLanguageServer $resolvedLls -LuaLanguageServerRoot $resolvedLlsRoot -PerfyMain $perfyMain -InputFiles @($batch.FullName)
    }
  } else {
    Write-Host "All Lua files were already reached from TOC/XML."
  }
}

Get-ChildItem -LiteralPath $stagedAddon -Recurse -File -Force |
  Where-Object { $_.Name -eq "luac.out" -or $_.Extension -in @(".pyc", ".pyo") } |
  ForEach-Object {
    Remove-Item -LiteralPath $_.FullName -Force
  }

$notInstrumented = @($allLuaFiles | Where-Object { -not (Test-PerfyInstrumentedFile $_.FullName) })
if ($InstrumentAllLua -and $notInstrumented.Count -gt 0) {
  $sample = ($notInstrumented | Select-Object -First 20 | ForEach-Object { $_.FullName }) -join [Environment]::NewLine
  throw "Perfy did not instrument $($notInstrumented.Count) Lua files. First files:`n$sample"
}

$localPerfyCacheHits = @(Select-String -LiteralPath $allLuaFiles.FullName -SimpleMatch "local Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough" -ErrorAction SilentlyContinue)
if ($localPerfyCacheHits.Count -gt 0) {
  $sample = ($localPerfyCacheHits | Select-Object -First 20 | ForEach-Object { "$($_.Path):$($_.LineNumber)" }) -join [Environment]::NewLine
  throw "Perfy injected local trace caches into $($localPerfyCacheHits.Count) locations. This can exceed WoW Lua's 60-upvalue limit. First hits:`n$sample"
}

$version = Get-FirstNonEmptyLine (Join-RepoPath "VERSION")
if ([string]::IsNullOrWhiteSpace($version)) {
  $version = Get-TocVersion $tocSource
}
if ([string]::IsNullOrWhiteSpace($version)) {
  $version = "dev"
}
$safeVersion = $version -replace '^refs/tags/', ''
$safeVersion = $safeVersion -replace '^v(?=\d)', ''
$safeVersion = ($safeVersion -replace '[\\/:*?""<>|]+', '-') -replace '\s+', '-'

$zipPath = Join-Path $outputRoot "$AddonName-Perfy-$safeVersion.zip"
if (Test-Path -LiteralPath $zipPath) {
  Remove-Item -LiteralPath $zipPath -Force
}

$packageItems = @(Get-ChildItem -LiteralPath $stageRoot)
Compress-Archive -LiteralPath $packageItems.FullName -DestinationPath $zipPath -Force

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $zipPath).Path)
try {
  $entries = @($zip.Entries | ForEach-Object { $_.FullName -replace '\\', '/' })
  if (-not ($entries -contains "!!!Perfy/!!!Perfy.toc")) {
    throw "Package verification failed: !!!Perfy/!!!Perfy.toc is missing."
  }
  if (-not ($entries -contains "$AddonName/$AddonName.toc")) {
    throw "Package verification failed: $AddonName/$AddonName.toc is missing."
  }
  if ($hasLocaleAddon -and -not ($entries -contains "${AddonName}_Locales/${AddonName}_Locales.toc")) {
    throw "Package verification failed: ${AddonName}_Locales/${AddonName}_Locales.toc is missing."
  }
  if ($hasAssistantAddon -and -not ($entries -contains "${AddonName}_Assistant/${AddonName}_Assistant.toc")) {
    throw "Package verification failed: ${AddonName}_Assistant/${AddonName}_Assistant.toc is missing."
  }
  $badEntry = $entries | Where-Object {
    ($_ -match '(^|/)(?:\.codex-remote-attachments|docs|scripts|tools|_local_workflows|graphify-out|__pycache__)(?:/|$)') -or
    ($_ -match '(?i)(^|/)(?:luac\.out|[^/]+\.py[co])$')
  } | Select-Object -First 1
  if ($badEntry) {
    throw "Package verification failed: local-only path is present: $badEntry"
  }
} finally {
  $zip.Dispose()
}

$traceCallCount = (Select-String -LiteralPath $allLuaFiles.FullName -SimpleMatch "Perfy_Trace" | Measure-Object).Count
$summaryPath = Join-Path $outputRoot "$AddonName-Perfy-$safeVersion.txt"
@(
  "Addon: $AddonName",
  "Version: $version",
  "PerfyRef: $PerfyRef",
  "PerfyRoot: $perfyRoot",
  "LuaLanguageServer: $resolvedLls",
  "LuaLanguageServerRoot: $resolvedLlsRoot",
  "InstrumentAllLua: $InstrumentAllLua",
  "InstrumentedLuaFiles: $($allLuaFiles.Count)",
  "PerfyTraceReferences: $traceCallCount",
  "LocalPerfyCacheHits: $($localPerfyCacheHits.Count)",
  "WoWSafeGlobalPerfyCalls: true",
  "Zip: $zipPath"
) | Set-Content -LiteralPath $summaryPath -Encoding utf8

if (-not $KeepStage) {
  Remove-Item -LiteralPath $workRoot -Recurse -Force
}

if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_OUTPUT)) {
  "zip_path=$zipPath" | Out-File -LiteralPath $env:GITHUB_OUTPUT -Append -Encoding utf8
  "summary_path=$summaryPath" | Out-File -LiteralPath $env:GITHUB_OUTPUT -Append -Encoding utf8
}

Write-Host "Created $zipPath"
Write-Host "Instrumented $($allLuaFiles.Count) Lua files with $traceCallCount Perfy trace references."
