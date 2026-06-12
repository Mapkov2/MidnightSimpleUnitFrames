# MSUF Group Frame Click Spike Dev Handoff

Date: 2026-06-13

## Short Version

Left-clicking an MSUF group frame is not expensive because of the group frame bar itself. The click changes the current target, and that wakes MSUF's normal unit-frame runtime through `UF.driver`.

The latest important finding is that the active `target` frame can bring the spike back up to roughly `1-2ms`, and `Portrait` update is part of that cost. With the target frame disabled, the remaining group-click spike is much lower. With the target frame enabled and portrait active, the click path becomes expensive again.

The next dev should focus on the target-frame identity visual path, especially `Portrait.Update` / `SetPortraitTexture`, not click-cast, hover, tooltip, or secure button creation.

## Current Click Path

```text
left click group frame
-> Blizzard secure target action
-> PLAYER_TARGET_CHANGED / UNIT_TARGET
-> MSUF.UF.driver
-> target identity fast update
-> deferred target visual update
-> target portrait update
-> targettarget/focustarget dependent updates if enabled
```

This is the main difference from oUF in the tested setup. oUF's group click path was effectively clean because it did not fan out into the same centralized MSUF target/ToT runtime work.

## Confirmed Non-Causes

These were tested and ruled out as the main remaining spike source:

- Blizzard secure click pipeline
- bare secure unit button
- click-cast / Clique registration
- group child `OnEvent`
- mouse highlight
- tooltip scripts
- `OnEnter` / `OnLeave`
- per-group-child Lua click handlers

Useful diagnostic state after cleanup:

```text
MSUF GF scripts OE=0 OA=10 EN=0 LV=0 MD=0 MU=0 CL=10
MSUF GF flags ... hook=0 hover=0 tooltip=NEVER
```

Interpretation:

- `OE=0`: group children do not own event dispatch.
- `EN=0 LV=0`: no mouse enter/leave scripts.
- `hook=0 hover=0 tooltip=NEVER`: hover and tooltip paths are not the cost.
- `CL=10`: secure click behavior still exists, which is expected.

## Important New Finding: Portrait

When the target frame is enabled, clicking group frames can spike back to `1-2ms`. This was initially mistaken for a regression in the runtime deferral work, but the confounder was that the target frame was active.

The target frame active runtime dump showed many enabled elements, including `Portrait`:

```text
MSUF UF runtime target:21/on/
Auras,Borders,Castbars,CombatIndicator,EliteIndicator,Health,HealthText,
InlineToT,LeaderIndicator,LoadConditions,NameText,Portrait,Power,PowerText,
Prediction,RaidMarkerIndicator,RangeFade,StatusIndicators,StatusTextIndicator,Text
```

`Portrait` is in the target identity visual path:

```lua
local RUNTIME_VISUAL_UPDATE_KEYS = {
  "_msufUpdateInlineToT",
  "_msufUpdatePortrait",
  ...
}
```

Relevant files:

- `Engine/MSUF_UF_Runtime.lua`
- `Engine/MSUF_UF_Dispatch.lua`
- `Engine/Elements/MSUF_UF_Elements_Portrait.lua`

Relevant portrait behavior:

- `Portrait.Update` runs for `MSUF_UNIT_IDENTITY_VISUAL`.
- Non-class portraits eventually call `ApplyUnitPortrait`.
- `ApplyUnitPortrait` calls Blizzard `SetPortraitTexture(texture, unit, true)`.
- Some portrait events are queued through `QueuePortraitUpdate`, but class portraits apply immediately.
- Border/layout work may also run if `PortraitBorderNeedsUpdate(event, p)` returns true.

## Changes Already Made

### Group Frames

`Engine/Group/MSUF_UF_Group_Adapter.lua`

- Click-cast registration is conditional.
- Group frames attach with `ownEvents = false`.
- Tooltip scripts are only installed when tooltip mode is not `NEVER`.
- Hover scripts are only installed when hover highlight is enabled.
- Default clicks use normal secure button click registration unless click-cast needs broader registration.

`Engine/MSUF_UF_Core.lua`

- `UF.AttachFrame` now respects `ownEvents = false`.
- Direct event registration checks `_msufCoreOwnEvents`.

### Disabled Feature Gating

`Engine/Group/MSUF_UF_Group_Config.lua`

- Group range fade requires `conf.rangeFadeEnabled == true`.
- Group status icon/text modules now require explicit `true`.
- Status runtime no longer silently compiles in from nil/default values.

`Engine/Group/MSUF_UF_Group_Config_Indicators.lua`

- Group corner indicators require `conf.ciEnabled == true`.

Menu/assistant defaults were also aligned so nil displays as off.

### Normal Unit Runtime Skip

`Engine/MSUF_UF_Factory.lua`

- Disabled unit frames are detached/stopped instead of fully applied and hidden.

`Engine/MSUF_UF_Runtime.lua`

- `RuntimeFrame(unit)` ignores disabled specs and empty active element tables.

`Engine/MSUF_UF_Dispatch.lua`

- `FrameRuntimeUpdate` returns early for disabled specs or empty active element tables.

## Current Runtime Patch State

The bad experiment was **not kept**:

- The separate dependent-unit `C_Timer.After(0.03/0.08/0.12)` phase scheduler was removed.
- Do not reintroduce that patch blindly. It made the measurement harder to reason about and was tested while the target frame was accidentally active.

The current runtime mitigation is different:

`Engine/MSUF_UF_Runtime.lua`

- Pending identity work is processed one phase per `OnUpdate` instead of as one large burst.
- Target/focus/ToT visual work is chunked in groups of four visual functions.
- Target/focus aura rebuilds are coalesced with `AURA_IDENTITY_WINDOW = 0.05`.

Current constants/state:

```lua
local VISUAL_PHASE_CHUNK_SIZE = 4
local visualPhaseOrder = { "target", "focus", "targettarget", "focustarget" }
local AURA_IDENTITY_WINDOW = 0.05
```

This is intended to reduce single-frame spikes, especially when the target frame has many visual elements enabled.

## Why Portrait Is Suspicious

`Portrait.Update` is not just a cheap visibility toggle. Depending on config and event, it can:

- clear the current portrait texture
- clear cached portrait GUID
- call `SetPortraitTexture`
- queue a later portrait flush
- relayout portrait border
- resolve class portrait media
- apply class portrait immediately

The expensive part is likely the actual portrait texture refresh and/or layout/border work on identity visual changes.

Key functions:

```lua
Portrait.Update(frame, event, unit)
QueuePortraitUpdate(frame)
FlushQueuedPortraits()
ApplyUnitPortrait(texture, unit, frame)
LayoutPortraitBorder(...)
```

## Recommended Next Tests

Use `/reload` between profile changes.

1. Target frame off, group frames stripped:

```text
Expected: low group-click cost.
```

2. Target frame on, portrait off:

```text
Expected: spike should be much lower than target frame with portrait on.
```

3. Target frame on, portrait on with class portrait:

```text
Checks class portrait path. This avoids SetPortraitTexture but still runs portrait code.
```

4. Target frame on, portrait on with normal 2D portrait:

```text
Checks SetPortraitTexture path.
```

5. Target frame on, portrait on, portrait border off:

```text
Separates texture refresh cost from border/layout cost.
```

## Diagnostic To Add Next

Add a temporary deep profile mode that wraps the target frame runtime functions directly:

```lua
frame._msufUpdateLoadConditions
frame._msufUpdateHealth
frame._msufUpdatePower
frame._msufUpdateNameText
frame._msufUpdatePortrait
frame._msufUpdatePrediction
frame._msufUpdateBorders
frame._msufUpdateAuras
```

For this issue, the key wrapper is:

```lua
target._msufUpdatePortrait
```

The report should print:

```text
unit | function | reason | total ms | count | max ms
```

This will prove whether the remaining visible spike is `Portrait.Update`, `SetPortraitTexture`, portrait border layout, or another target visual function.

## Candidate Fixes

### Best Low-Risk Fix

Keep target bars/name responsive, but never run portrait texture refresh in the same click tick.

Suggested behavior:

```text
MSUF_UNIT_IDENTITY_FAST:
  LoadConditions, Health, Power, Name

MSUF_UNIT_IDENTITY_VISUAL:
  lightweight visual updates

Portrait texture refresh:
  queued/coalesced, one frame later or 50ms later
```

The portrait holder can remain visible with the old texture until the queued refresh completes.

### Better Portrait-Specific Fix

Inside `Portrait.Update`:

- For `MSUF_UNIT_IDENTITY_VISUAL` and `MSUF_UNIT_IDENTITY_SOFT_VISUAL`, always queue non-class portrait refresh.
- Avoid `ClearPortraitTexture(texture)` on identity visual unless the old texture is provably wrong and visible artifact is worse than the CPU spike.
- Skip `LayoutPortraitBorder` on identity visual if border color/layout inputs did not change.
- Keep a per-frame queued flag so target spam coalesces to one portrait refresh.

### Optional Architectural Fix

Move portrait out of the general target visual runtime list and give it its own deferrable lane:

```lua
target fast lane: health/power/name
target visual lane: status/prediction/borders/etc.
target portrait lane: queued/coalesced texture refresh
target aura lane: queued/coalesced aura rebuild
```

This makes future regressions easier to isolate.

## Current Expected Active Group Frame

When everything optional is off, group active elements should be close to:

```text
Health
Borders
```

or just:

```text
Health
```

These should not appear unless explicitly enabled:

```text
GroupCornerIndicators
GroupStatusRuntime
StatusIndicators
GroupRangeFade
GroupVisuals target/focus pieces
```

## Important Notes For The Next Dev

- Target frame off is not the same as Target of Target off.
- A group click changes `target`, so any enabled `target`, `targettarget`, `focus`, or `focustarget` runtime can be billed near the click.
- The group frame itself can be clean while the global `UF.driver` still records CPU caused by the target change.
- Portrait was the newest confirmed contributor when target frame was enabled.
- Do not spend more time on click-cast or hover unless diagnostics show scripts/hooks came back.

## Local Verification

The Lua syntax check passed after the current runtime changes:

```text
syntax ok
```
