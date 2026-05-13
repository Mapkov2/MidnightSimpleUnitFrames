# Midnight Simple Unit Frames - Profiler

Drop-in profiler for MSUF performance investigations.

Normal use:

```text
/run C_AddOns.LoadAddOn("MidnightSimpleUnitFrames_Profiler")
/msufprof start full
# reproduce the issue
/reload
```

The reload finalizes and stores the full aggregate report in:

```text
WTF/Account/<account>/SavedVariables/MidnightSimpleUnitFrames_Profiler.lua
```

Useful commands:

```text
/msufprof start full
/msufprof stop
/msufprof report
/msufprof top total 30
/msufprof top self 30
/msufprof worst 30
/msufprof peaks 20
/msufprof export
/msufprof reload
/msufprof clear
```

Startup profiling:

1. Load the profiler once and run `/msufprof arm full`.
2. Keep `MidnightSimpleUnitFrames_Profiler` in the AddOns folder.
3. Temporarily remove or comment `## LoadOnDemand: 1` in the profiler TOC.
4. Keep `MidnightSimpleUnitFrames_Profiler` listed as an optional dependency in the main MSUF TOC.
5. Log in, run the test, then `/reload`.
6. Run `/msufprof disarm` when startup profiling is done.

For production, disable or delete the `MidnightSimpleUnitFrames_Profiler` folder. If the profiler addon is not loaded, MSUF has no profiler hooks, wrappers, or hot-path checks.
