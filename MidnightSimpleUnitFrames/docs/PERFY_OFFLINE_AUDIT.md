# Perfy Workflow Tool

`tools/perfy_audit.py` builds Perfy-instrumented MSUF test zips and analyzes
Perfy SavedVariables exports outside Codex. It is the standalone version of the
manual Perfy workflow used during performance work.

## Desktop UI

Start the small native UI from the repo root:

```powershell
python tools\perfy_audit_ui.py
```

The UI uses only Python's standard library. It can:

- build a focused UnitFrames Perfy zip into Downloads;
- switch the instrumentation scope to Castbars, ClassPower, or all first-party Lua;
- analyze `!!!Perfy.lua` and write a text report;
- open the report or Downloads folder directly.

## Build A Perfy Zip

Build a UnitFrames-focused Perfy package from the current repo:

```powershell
python tools\perfy_audit.py build --scope UnitFrames
```

Output defaults to Downloads:

```text
%USERPROFILE%\Downloads\MSUF_Perfy_Instrumented_UnitFrames_YYYYMMDD_HHMMSS.zip
%USERPROFILE%\Downloads\MSUF_Perfy_Instrumented_latest.zip
```

Build all first-party addon Lua files instead of just UnitFrames:

```powershell
python tools\perfy_audit.py build --all
```

Build multiple focused scopes:

```powershell
python tools\perfy_audit.py build --scope UnitFrames --scope Castbars --scope ClassPower
```

The build command:

- copies the current repo addon to a temporary Downloads staging folder;
- writes `MSUF_PerfyHook.lua` only into the staging copy;
- patches only the staging `.toc` with `OptionalDeps: ... Perfy` and the hook;
- statically instruments selected Lua files with balanced `UFStatic:*` labels;
- rejects a generated zip if any static label has an Enter with no matching
  Leave injection site;
- validates the generated addon with `luac -p`;
- creates the final zip and removes the staging folder unless `--keep-stage` is used.

## Analyze A Trace

```powershell
python tools\perfy_audit.py analyze `
  "e:\World of Warcraft\_retail_\WTF\Account\1108323981#1\SavedVariables\!!!Perfy.lua" `
  --out "$env:USERPROFILE\Downloads\MSUF_Perfy_Offline_Report.txt"
```

If the default Marco SavedVariables path exists, this shorter command also
works:

```powershell
python tools\perfy_audit.py analyze --out "$env:USERPROFILE\Downloads\MSUF_Perfy_Offline_Report.txt"
```

For compatibility, the old short analyze form still works:

```powershell
python tools\perfy_audit.py <path-to-!!!Perfy.lua> --out "$env:USERPROFILE\Downloads\MSUF_Perfy_Offline_Report.txt"
```

## Useful Options

```powershell
python tools\perfy_audit.py analyze <path-to-!!!Perfy.lua> --top 50
python tools\perfy_audit.py analyze <path-to-!!!Perfy.lua> --scope UnitFrames
python tools\perfy_audit.py analyze <path-to-!!!Perfy.lua> --no-coverage
python tools\perfy_audit.py analyze <path-to-!!!Perfy.lua> --include "UFStatic:UnitFrames/Engine|Element:|UF6:"
python tools\perfy_audit.py build --name MSUF_Perfy_Custom.zip
python tools\perfy_audit.py build --no-static
python tools\perfy_audit.py build --keep-stage
```

## What The Tool Does

Build side:

- Generates Perfy-ready zips from the current working tree.
- Keeps Perfy hook files and instrumentation out of the normal addon folder.
- Instruments functions directly, including early returns, with guarded
  `_G.MSUF_PerfyEnter` / `_G.MSUF_PerfyLeave` calls.
- Adds semantic labels such as `UF6:DispatchFrameEvent`, `UF6:UpdateRuntime`,
  and `Element:<name>.Update` through the generated hook.
- Filters vendor `Libs` out of direct instrumentation.

Analyze side:

- Parses `FunctionNames`, `EventNames`, and `Trace` from `!!!Perfy.lua`.
- Handles Perfy's separate event-id and function-id namespaces.
- Reconstructs balanced `Enter` / `Leave` spans.
- Resyncs at top-level event boundaries so an old broken trace cannot keep a
  stale function open across unrelated events.
- Computes calls, self time, inclusive time, max inclusive time, and module totals.
- Reports `OnEvent`/extra payload counts so event fanout is visible.
- Filters non-MSUF labels out of hotspot rankings by default.
- Reports Perfy recorder overhead separately instead of assigning it to MSUF.
- Scans the source tree and lists functions not observed as `UFStatic` labels in
  the current trace.

## Important Interpretation Rules

- The coverage section means "observed in this trace", not necessarily "missing
  from the generated Perfy zip".
- A clean trace should have `mismatches=0`, `orphanLeaves=0`, `openStack=0`, and
  `resyncs=0`. If not, the report can still identify broad hotspots, but exact
  parent/child attribution should be treated carefully.
- Coroutine and non-MSUF records are noise for MSUF CPU unless they happen inside
  a first-party MSUF span.
- Secret helper cost should be reduced by lowering caller count. Do not remove
  secret checks from paths that can receive protected values.
- The report is for prioritization. Fixes should still be verified in game with
  a fresh trace.
