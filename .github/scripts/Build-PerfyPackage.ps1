param(
  [string]$AddonName = "MidnightSimpleUnitFrames",
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

$script:RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../.."))
$addonSource = Join-RepoPath $AddonName
$tocSource = Join-Path $addonSource "$AddonName.toc"

if (-not (Test-Path -LiteralPath $addonSource)) {
  throw "Addon folder not found: $addonSource"
}
if (-not (Test-Path -LiteralPath $tocSource)) {
  throw "Addon TOC not found: $tocSource"
}

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
$perfyMain = Join-Path $perfyRoot "Instrumentation/Main.lua"
$perfyAddonSource = Join-Path $perfyRoot "AddOn"

Write-Host "Copying $AddonName to staging folder $stagedAddon"
Copy-Item -LiteralPath $addonSource -Destination $stageRoot -Recurse -Force

foreach ($relativePath in @("docs", "scripts", "MSUF_PerfyHook.lua", ".gitignore")) {
  $fullPath = Join-Path $stagedAddon $relativePath
  if (Test-Path -LiteralPath $fullPath) {
    Remove-Item -LiteralPath $fullPath -Recurse -Force
  }
}

$perfyAddonTarget = Join-Path $stageRoot "!!!Perfy"
Write-Host "Adding Perfy AddOn as $perfyAddonTarget"
Copy-Item -LiteralPath $perfyAddonSource -Destination $perfyAddonTarget -Recurse -Force
Set-PerfyInterfaceVersion -PerfyAddonDir $perfyAddonTarget -InterfaceVersion "120000"

Write-Host "Instrumenting TOC/XML reachable Lua files with Perfy"
Invoke-PerfyInstrumentation -LuaLanguageServer $resolvedLls -LuaLanguageServerRoot $resolvedLlsRoot -PerfyMain $perfyMain -InputFiles @($stagedToc)

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

$notInstrumented = @($allLuaFiles | Where-Object { -not (Test-PerfyInstrumentedFile $_.FullName) })
if ($InstrumentAllLua -and $notInstrumented.Count -gt 0) {
  $sample = ($notInstrumented | Select-Object -First 20 | ForEach-Object { $_.FullName }) -join [Environment]::NewLine
  throw "Perfy did not instrument $($notInstrumented.Count) Lua files. First files:`n$sample"
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
