# UF responsibility split

The unit-frame engine files that sat at Lua's 200-local / 60-upvalue ceilings are split by
responsibility. Moved bodies keep their statements, argument order, return arity and upvalue
captures; the split is a pure move plus a handful of extractions. No profile default, saved
value, route, element identity or native call order changes.

Baseline: the 7.0-main commit before this change.

## Owners

Each owner is a factory file under `UnitFrames/Engine/`. It is loaded before its coordinator in
every client graph (all five Core sections of `tools/load-graph.lock`) and publishes one function
under `MSUF.UFModuleFactories`.

| Owner | Responsibility and invariant | Coordinator |
| --- | --- | --- |
| `Status_Regions` | Layer holders, adoption, region setters, font/color/layout caches; existing cache fields and native mutation order | `Elements_Status` |
| `Status_Indicators` | Icon art selection, raid/leader, elite, gone/AFK, combat/resting/resurrection/PvP painters; secret checks precede inspection | `Elements_Status` |
| `Status_GroupRuntime` | Ready-check hide queue, role power visibility, summon/phase and raid group numbers; one timer, unchanged dirty gates | `Elements_Status` |
| `Status_Level` | Native/fallback medallion and difficulty/identity text; same native grading, Classic fallback and preview tier | `Elements_Status` |
| `Text_SlotCompile` | Slot reuse, health/absorb/power needs and compiled drain selection; interned writer identities preserved | `Text_Format` |
| `Text_Drain` | Double queue, 250 ms combat window, attachment/visibility checks; never retains secret event payloads | `Text_Runtime` |
| `Text_Name` | Name resolver cell, inline resolver, UTF-8 truncation and cached painting; one resolver and one preview name path | `Text_Runtime` |
| `Factory_Spawn` | Secure attributes, click/tooltip/ping hooks, frame construction and application; optimized shared closures stay shared | `Factory` |
| `Factory_Anchors` | Named anchors, cycle detection, shared proxy ownership and screen-position policy; combat freeze/thaw stays in the coordinator | `Factory` |
| `Factory_CooldownWidth` | Width mode/source masks, configuration and anchor-routing helpers; scheduler, observer identities and regen replay stay in `Factory` | `Factory` |
| `Prediction_Glow` | Over-absorb holder construction and positioning | `Elements_Prediction` |

## Binding model

A provider is `function(deps...) ... return exports end`. The coordinator calls it once at load
with the local functions and tables the moved bodies used to capture, so every moved body keeps
reading the same upvalues. Consumers fetch the provider with `RequireFactory(key)`, which asserts
the registry and the provider shape and names both the consumer file and the provider key.
`type` is passed in, never re-read, so an optional-callable guard keeps the original captured
binding. Moved bodies keep reading `_G` directly, so late providers still resolve at call time.
A provider takes only the dependencies its body uses.

Budget-sensitive code stays in the coordinator: the over-absorb painter, the Boss number
updater, optional-callable probes, the `SetFont`/power-role/icon-resolver compatibility
bodies, the badge compatibility body (it keeps the original `Client` nil guard), and the
cooldown-width scheduler. Moving them through an adapter measurably added instructions.

## Extracted functions

Functions that exceeded 225 lines now sit below it, and no new function exceeds 150 lines.

| Function | Now |
| --- | --- |
| `Text.Apply` (Text_Layout) | tail moved to `PositionConfiguredText`; the cold layout pass keeps one call |
| `UpdatePowerRuntime` (Text_Runtime) | slot delivery moved to `WritePowerValueSlots`, which carries `UpdateTextSlotsSecret`'s power-slot loop inline so the event path pays no extra call |
| `CompileSecretWriter` (Text_Format) | the current/percent writers moved to `CompileCurrentPercentWriter` |
| `CompileTextRuntime` (Text_Format) | health, power and slot assembly live in `Text_SlotCompile`; the former `CompileThreeTextSlots` and `CompileHealthTextSlots` helpers are inlined into the power and health phases |
| `EnsureOverAbsorbGlow`, `PositionOverAbsorbGlow` | moved to `Prediction_Glow` |

Longer explanatory comments moved verbatim into `uf-responsibility-notes.md`: the split adds
about 24 KB of provider scaffolding, and `startup_locale_manifest_smoke` caps the bytes loaded at
startup (Mainline sat 12.8 KB under its limit). Short contract comments remain beside the code.

## Evidence

`tools/fixtures/costs/*.tsv` pin the exact numbers of the parent commit (VM instructions, addon-attributed
native calls, hook-free heap minimum in KiB). Heap rows are the highest minimum observed on that
tree. A candidate may only match or beat them; none of these caps was raised.

| Smoke | Proves |
| --- | --- |
| `uf_required_split_providers_smoke` | all five graphs boot; omitting or replacing any provider fails at load and names consumer and provider |
| `callable_boundary_*_smoke` | 83 exported operations per client: VM, native calls, heap, plus mutants that must fail the heap check |
| `responsibility_route_*_smoke` | 1,121 event, public and configuration routes per client, each in a fresh world |
| `responsibility_adapter_*_smoke` | 67 routes through every changed or extracted function |
| `prediction_*`, `boss_number_*`, `external_anchor_*`, `late_cooldown_anchor_*` | exported costs and late-binding contracts of the retained coordinator bodies |
| `text_resolver_type_capture_smoke`, `uf_level_badge_client_binding_smoke` | captured `type` and late `Client` binding |

`tools/tests/responsibility_route_native_order.lua <root> <client> [harness]` prints the ordered
frame calls with arguments for every route. Run it on the parent and on the candidate and diff
the two outputs.

Offline evidence does not cover live rendering, combat, taint, native CPU or GPU cost.
