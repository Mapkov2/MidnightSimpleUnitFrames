# Perfy Workflow For MSUF

This file documents the working MSUF Perfy workflow for future Codex runs.
The goal is to create a test zip that covers the real addon package, install
that zip in WoW, capture `!!!Perfy.lua`, then use the trace to make targeted
performance changes.

## Rules

- Build Perfy packages as zips in `C:\Users\Marco\Downloads`.
- Do not add permanent Perfy packaging scripts to the repo.
- Do not use repo `.ps1` files for Perfy packaging.
- Use the already working Perfy zip as the base package:
  `C:\Users\Marco\Downloads\MSUF_Perfy_Instrumented_fixed.zip`
- Keep the addon shape identical to a real install: include
  `MidnightSimpleUnitFrames` and `MidnightSimpleUnitFrames_Castbars`.
- Validate every generated Perfy zip by extracting it and running `luac -p`
  over all Lua files before giving it to Marco.
- Never ship a zip with unbalanced Perfy enter/leave instrumentation.

## Current Known Good Base

The current base zip is:

```text
C:\Users\Marco\Downloads\MSUF_Perfy_Instrumented_fixed.zip
```

It contains:

- `MidnightSimpleUnitFrames\MSUF_PerfyHook.lua`
- `MidnightSimpleUnitFrames\MidnightSimpleUnitFrames.toc` with
  `MSUF_PerfyHook.lua`
- Core addon files
- Castbars addon files

Known important fix in that base:

- Do not instrument `_msuf_probeNum` in
  `MidnightSimpleUnitFrames_Castbars/Castbars/MSUF_CastbarDriver.lua`.
  That helper intentionally errors inside `pcall`, so instrumenting it creates
  enter/leave imbalance.

## Core File Changes Required For A Trace

There are two different kinds of changes needed to make a trace possible:

1. Package-level core changes in the extracted zip.
2. Function-level instrumentation in the Lua files being measured.

These changes belong in the temporary Perfy build, not as permanent repo
packaging files.

### TOC Changes

The core addon TOC must load the hook file and must allow Perfy to load first.
In the generated zip, verify:

```text
MidnightSimpleUnitFrames\MidnightSimpleUnitFrames.toc
```

contains:

```text
## OptionalDeps: Masque, LibSharedMedia-3.0, Clique, WagoAnalytics, Perfy
MSUF_PerfyHook.lua
```

`MSUF_PerfyHook.lua` should be loaded late enough that MSUF has already created
the globals/frames the hook wraps:

```text
_G.MSUF_NS
_G._MSUF_UFCore_FrameOnEvent
_G._MSUF_UFCore_FlushFrame
_G.MSUF_GF_Dispatch_OnGlobalEvent
ns.MSUF_EventBus
ns.MSUF_Auras2
```

Do not put `MSUF_PerfyHook.lua` before the core systems it wraps. A missing
target is not fatal, but it means that part of the trace is blind.

The Castbars addon does not need its own hook file for the current workflow.
Castbar coverage comes from direct function instrumentation in the Castbars Lua
files inside the generated zip.

### Hook File

The generated zip must contain:

```text
MidnightSimpleUnitFrames\MSUF_PerfyHook.lua
```

The hook file must be safe when Perfy is not loaded:

```lua
if not _G.Perfy_Trace then return end
```

After that, it localizes:

```lua
local Perfy_Trace = _G.Perfy_Trace
local Perfy_GetTime = _G.Perfy_GetTime
```

It wraps semantic dispatch points that are hard to understand from raw function
entries alone:

```text
EventBus:Dispatch
UFCore:FrameOnEvent
UFCore:FlushTask
A2:FullScan
A2:OnUnitAura
GF:UpdateButton
GF:GlobalEvent
```

It also exports small manual helpers:

```lua
_G.MSUF_PerfyEnter = function(label, extra)
    Perfy_Trace(Perfy_GetTime(), "Enter", label, extra)
end

_G.MSUF_PerfyLeave = function(label, extra)
    Perfy_Trace(Perfy_GetTime(), "Leave", label, extra)
end
```

### Direct Core Lua Instrumentation

Direct instrumentation is what gives per-function self time and inclusive time.
It is applied to the extracted temp build files, for example:

```text
MidnightSimpleUnitFrames/Core/MSUF_Borders.lua
MidnightSimpleUnitFrames/GroupFrames/MSUF_GF_Auras.lua
MidnightSimpleUnitFrames/GroupFrames/MSUF_GF_Effects.lua
```

Every instrumented function must get:

```lua
Perfy_Trace(Perfy_GetTime(),"Enter","path/file.lua:line:functionName");
```

immediately after the function starts, and:

```lua
Perfy_Trace(Perfy_GetTime(),"Leave","path/file.lua:line:functionName");
```

before every exit path.

Core files often have early returns, one-line branch returns, and functions
assigned to globals. These are the important patterns:

```lua
local function Named()
    Perfy_Trace(Perfy_GetTime(),"Enter","file.lua:10:Named");
    if not ready then
        Perfy_Trace(Perfy_GetTime(),"Leave","file.lua:10:Named");
        return
    end
    Perfy_Trace(Perfy_GetTime(),"Leave","file.lua:10:Named");
end
```

```lua
_G.SomeAPI = function(arg)
    Perfy_Trace(Perfy_GetTime(),"Enter","file.lua:20:_G.SomeAPI");
    if arg then
        Perfy_Trace(Perfy_GetTime(),"Leave","file.lua:20:_G.SomeAPI");
        return true
    end
    Perfy_Trace(Perfy_GetTime(),"Leave","file.lua:20:_G.SomeAPI");
    return false
end
```

For one-line return branches, split the branch so the `Leave` is inside the
branch:

```lua
if cached then
    Perfy_Trace(Perfy_GetTime(),"Leave","file.lua:30:Cached");
    return cached
end
```

Never emit this:

```lua
return cached
Perfy_Trace(Perfy_GetTime(),"Leave","file.lua:30:Cached");
```

That is the exact class of bug that created the old:

```text
'end' expected ... near 'Perfy_Trace'
```

error.

### Special Core Cases To Avoid

- Do not instrument intentionally throwing probe helpers that are called inside
  `pcall`.
- Do not instrument functions if the instrumenter cannot prove the matching
  function `end`.
- Be careful with one-line anonymous callbacks such as
  `function(...) DoThing(...) end`; skip them unless the instrumenter supports
  them safely.
- Keep labels stable and include file path, original line, and function name.
  This makes before/after trace comparison possible.
- Instrumented Lua files require Perfy to be installed and loaded. The hook file
  is safe without Perfy, but direct `Perfy_Trace(...)` calls are not.

## Build A New Perfy Test Zip

1. Start from the working base zip, not from scratch.

2. Extract it to a temporary Downloads folder, for example:

```text
C:\Users\Marco\Downloads\MSUF_PerfyBuild_YYYYMMDD_HHMMSS
```

3. Overlay changed repo files into the extracted addon tree.

Use repo paths as the source and the extracted zip paths as the destination.
Example for changed files:

```text
MidnightSimpleUnitFrames/Core/MSUF_Borders.lua
MidnightSimpleUnitFrames/GroupFrames/MSUF_GF_Auras.lua
MidnightSimpleUnitFrames/GroupFrames/MSUF_GF_Effects.lua
```

4. Instrument the overlaid Lua files in the temporary build folder.

Use a temporary inline script or one-off command. Do not save a Perfy packaging
script into the repo.

5. Validate syntax:

```powershell
$luaFiles = Get-ChildItem -LiteralPath $buildRoot -Recurse -Filter '*.lua'
foreach ($file in $luaFiles) {
    luac -p $file.FullName
    if ($LASTEXITCODE -ne 0) { throw "luac failed: $($file.FullName)" }
}
```

Expected result after the current base:

```text
luac ok: 141 files
```

6. Compress both top-level addon folders:

```text
MidnightSimpleUnitFrames
MidnightSimpleUnitFrames_Castbars
```

Recommended output name:

```text
C:\Users\Marco\Downloads\MSUF_Perfy_Instrumented_<change-name>.zip
```

7. Verify the finished zip contains these entries:

```text
MidnightSimpleUnitFrames\MidnightSimpleUnitFrames.toc
MidnightSimpleUnitFrames\MSUF_PerfyHook.lua
MidnightSimpleUnitFrames_Castbars\MidnightSimpleUnitFrames_Castbars.toc
```

8. Delete temporary build folders after the final zip is valid.

## Instrumentation Rules

The common broken zip symptom is:

```text
'end' expected ... near 'Perfy_Trace'
```

This happens when the instrumenter emits a `Leave` trace after a terminal
`return`, leaving unreachable Lua before the function `end`.

Use these rules:

- Insert `Enter` immediately after a multi-line function declaration.
- Insert `Leave` immediately before each standalone `return`.
- For one-line branches like `if x then return y end`, put `Leave` inside the
  branch before the `return`.
- Insert `Leave` before the function `end` only if the function does not end
  with a terminal standalone `return`.
- Do not treat single-line anonymous callback functions as normal multi-line
  functions unless the instrumenter can parse them safely.
- After instrumentation, always run `luac -p` over all Lua files.

Good pattern:

```lua
local function Example()
    Perfy_Trace(Perfy_GetTime(),"Enter","file.lua:1:Example");
    if cached ~= nil then
        Perfy_Trace(Perfy_GetTime(),"Leave","file.lua:1:Example");
        return cached
    end
    Perfy_Trace(Perfy_GetTime(),"Leave","file.lua:1:Example");
    return value
end
```

Bad pattern:

```lua
local function Example()
    Perfy_Trace(Perfy_GetTime(),"Enter","file.lua:1:Example");
    return value
Perfy_Trace(Perfy_GetTime(),"Leave","file.lua:1:Example");
end
```

## Capture A Trace

Marco installs the generated zip in WoW and captures the trace with Perfy.
The SavedVariables file is usually here:

```text
e:\World of Warcraft\_retail_\WTF\Account\1108323981#1\SavedVariables\!!!Perfy.lua
```

For performance comparisons, use a similar scenario and duration when possible.
The last useful baseline was a 60 second world boss trace.

## Analyze A Trace

1. Read `!!!Perfy.lua`.

2. Parse:

- `Trace`
- `FunctionNames`
- `PerfyStart`
- `PerfyStop`
- `Enter`
- `Leave`
- `OnEvent`
- `CoroutineResume`
- `CoroutineYield`

3. Reconstruct an enter/leave stack.

Reject or distrust the trace if:

- enter/leave mismatches are non-zero
- stack has entries remaining at stop
- a single intentionally throwing helper was instrumented

4. Compute:

- calls
- self time
- inclusive time
- max inclusive call
- roots
- module totals
- parent/child relationships

5. Prioritize realistic fixes:

- remove whole hot paths with safe capability gates
- cache cold-path config resolution
- avoid repeated `_G.MSUF_DB` table walks in frame cache builds
- avoid aura scans when the rendered feature cannot be visible
- keep behavior identical for unknown APIs or edge classes by falling back to
  old behavior

## Baseline From 60s World Boss Trace

Useful old trace numbers:

```text
Trace entries: 1,393,402
Duration: 60.0520323s
Enter: 169,521
Leave: 169,521
Mismatches: 0
Remaining stack: 0
Measured MSUF self time: 0.7986846s
Inclusive sum: 3.1421893s
```

Top old hotspots:

```text
GroupFrames/MSUF_GF_Core.lua ScanRaidHeaders spike
Auras2/MSUF_A2_Render.lua FlushDriverOnUpdate
Core/MSUF_Borders.lua FlushDispelAuraUnits
Core/MSUF_Borders.lua HasDispellableDebuff
GroupFrames/MSUF_GF_Effects.lua HLVal
GroupFrames/MSUF_GF_Auras.lua GF.IsBlizzardAuraTypeEnabled
Castbars/MSUF_Castbars.lua ManagerOnUpdate
```

## Current Perf Fix 1 Test Zip

The first zip after the Dispel/GroupFrames cache fixes was:

```text
C:\Users\Marco\Downloads\MSUF_Perfy_Instrumented_perf_fix1.zip
```

It was validated with:

```text
luac ok: 141 files
```

Expected things to check in the next trace:

- `Core/MSUF_Borders.lua:885:HasDispellableDebuff` should disappear or drop
  hard on DK/Rogue/Warrior when purge outline is not active.
- `Core/MSUF_Borders.lua FlushDispelAuraUnits` should disappear or drop hard
  on those classes when purge outline is not active.
- `GroupFrames/MSUF_GF_Effects.lua HLVal` should drop inside
  `GF.BuildFrameCache`.
- `GroupFrames/MSUF_GF_Auras.lua GF.IsBlizzardAuraTypeEnabled` should drop
  inside `GF.BuildFrameCache`.
