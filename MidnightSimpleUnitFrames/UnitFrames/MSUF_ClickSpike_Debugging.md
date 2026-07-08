# MSUF Unitframe Click Spike Debugging

Date: 2026-07-07

Scope: MSUF unitframe click CPU spikes on PTR. Focus is the core/backend and
the click path for player and group frames. Auras are intentionally out of
scope.

## Problem

Clicking MSUF unitframes still creates a large CPU peak in the WoW addon
profiler. The typical reported peak is around 5-8 ms when clicking the player
frame with no existing target, and around 1 ms or more on repeated/group clicks.

## Current Confirmed Result

After the latest shell split, `/msufinspect player` shows:

- Visual frame: `MSUF_player`
- Secure click shell: `MSUF_playerClick`
- `MSUF_player` has no click attributes and no clickcast registration.
- `MSUF_playerClick` is protected and has:
  - `unit=player`
  - `type1=target`
  - `*type1=target`
  - `*type2=click`
  - `ping=true`

`/msufpeak 10` after the shell split still reports:

```text
7.608ms | MidnightSimpleUnitFrames | focus=MSUF_playerClick
```

This means the spike follows the minimal secure click shell. The old combined
visual/runtime frame was not the only cause.

## Important Evidence

### Target frame is not the cause

The target frame was disabled during testing. Clicking MSUF player/group frames
still caused the same spike.

### Healthbar movement is not the original cause

The click spike existed before reconnecting the live HP bar update path.
After HP was connected, general performance got worse, but the first-click spike
already existed.

### Lua wrapper probes did not see 5-8 ms

`/msufclickcore` and targeted wrapper probes repeatedly showed small MSUF Lua
entries, often around 0.03-0.15 ms per entry. This did not explain the in-game
profiler peak.

The missing time is therefore not normal visible Lua element work. It is either:

- native secure click/attribute work billed to the addon that owns the clicked
  frame, or
- hidden/global work that is attributed to MSUF because the clicked secure frame
  belongs to MSUF.

### Addon profiler confirms the MSUF bucket

`/msufpeak` samples `C_AddOnProfiler.GetAddOnMetric(addon, LastTime)` and stores
the mouse focus at peak. After removing expensive attribute reads from the
sampler, the result still showed:

```text
7.587ms | MidnightSimpleUnitFrames | focus=MSUF_player
```

After the click-shell split:

```text
7.608ms | MidnightSimpleUnitFrames | focus=MSUF_playerClick
```

This confirms the current spike is tied to the MSUF-owned secure click frame.

## Compared Addons

### UnhaltedUnitFrames

Observed architecture:

- Frames use simple secure click setup:
  - `RegisterForClicks("AnyUp")`
  - `*type1=target`
  - `*type2=togglemenu`
  - `RegisterUnitWatch`

Comparison frames do not reproduce the large MSUF click peak in user testing.

## Changes Already Made

### Target-swap/runtime path

Target swap performance was improved and user confirmed it returned to good
performance. This path should be preserved.

### Removed dispatch core

The old dispatch-driven backend was replaced with a smaller direct event core.
The dispatch file was removed/emptied in prior work.

### Direct event frame core

Core now has direct frame event paths:

- `FrameOnEvent`
- direct compiled event functions per frame/event
- `RunLeanIdentity`
- `FrameRuntimeUpdate`
- no hot dispatcher indirection for normal events

### State driver reduction

Existence-only visibility was moved to `RegisterUnitWatch` instead of stacking a
secure `RegisterStateDriver("visibility")` and improved target swap cost.

### Native secure templates

Single unit buttons were changed to:

```lua
SecureUnitButtonTemplate, PingableUnitFrameTemplate
```

Group header children were changed to:

```lua
SecureUnitButtonTemplate, SecureHandlerStateTemplate,
SecureHandlerEnterLeaveTemplate, PingableUnitFrameTemplate
```

### Native ping support

Added native ping receiver setup:

- `PingableType_UnitFrameMixin`
- `ping-receiver=true`
- `GetTargetPingGUID`

This did not fix the click spike.

### Explicit type1

MSUF now sets both:

```lua
type1 = target
*type1 = target
```

### Secure right-click menu proxy

Right-click menu now routes through a secure proxy:

```lua
*type2 = click
*clickbutton2 = proxy
```

### ClickCast registration minimized

ClickCastFrames registration was reduced to direct table registration with no
extra Clique wrapping work in the core path.

### Tooltip hooks removed

Temporary tooltip hooks introduced during testing caused hover spikes. They were
removed. Current inspect output shows no OnEnter/OnLeave on the player frame
tree.

### Visual/click shell split

Latest architecture:

- `MSUF_player` is a normal visual/event frame.
- `MSUF_playerClick` is the protected secure click shell.
- Group header children keep the protected secure shell, while MSUF elements are
  placed on a normal visual child.
- LoadConditions/UnitWatch are routed to the shell.
- Runtime/event/Health/Text pipeline is routed to the visual frame.

Result: spike still occurs, now with `focus=MSUF_playerClick`.

## What Has Been Ruled Out

Ruled out or strongly unlikely:

- Target frame creation.
- Target frame refresh.
- HP bar live update as the original root cause.
- Normal Lua element update cost.
- Text format runtime as the primary first-click cause.
- Tooltip hooks on MSUF frames.
- Missing `PingableUnitFrameTemplate`.
- Missing direct `type1=target`.
- Combined visual/runtime frame as the sole cause.

## Current Best Explanation

The current strongest explanation is:

The native secure click action on an MSUF-owned protected unit button is being
billed to `MidnightSimpleUnitFrames` by `C_AddOnProfiler`, and for MSUF-owned
buttons this native/protected path is far more expensive than the visible Lua
work.

After the shell split, the spike follows `MSUF_playerClick`, a minimal protected
button. This makes the remaining issue either:

1. The secure shell still has an attribute/registration difference that triggers
   expensive native work.
2. AddonProfiler billing is harsher for MSUF because MSUF owns the clicked
   secure button directly.
3. A third-party click binding / Blizzard click binding path treats MSUF frames
   differently because of ClickCastFrames membership or secure attributes.

## Next Debug Steps

The next useful tests should be surgical. More broad rewrites are not likely to
help until this remaining secure-shell delta is isolated.

### Test 1: no ClickCastFrames for shell

Temporarily do not register `MSUF_playerClick` and group shells in
`ClickCastFrames`.

Expected result:

- If the spike disappears or drops sharply, the culprit is Blizzard/Clique click
  binding integration on MSUF frames.
- If unchanged, ClickCastFrames is not the cause.

### Test 2: no right-click proxy on left-click measurement

Temporarily remove `*type2=click` and `*clickbutton2` from the shell.

Expected result:

- If left-click spike changes, the secure action resolver scans right-click
  clickbutton attributes even on left click.
- If unchanged, right-click menu proxy is not involved.

### Test 3: shell without Pingable

Temporarily remove `PingableUnitFrameTemplate`, `ping-receiver`, and
`GetTargetPingGUID` from the shell.

Expected result:

- If the spike drops, PTR ping receiver path is the hidden cost.
- If unchanged, ping is not involved.

### Test 4: pure secure shell in MSUF runtime, not in UF tables

Spawn a permanent `MSUF_NakedPlayerClick` in the actual loaded addon, not the
debug probe file, with only:

```lua
unit=player
type1=target
*type1=target
RegisterForClicks("AnyUp")
RegisterUnitWatch
```

Compare `/msufpeak` against `MSUF_playerClick`.

Expected result:

- If naked shell is cheap but `MSUF_playerClick` spikes, one of the extra
  attributes/registrations on the shell is the cause.
- If naked shell also spikes, the MSUF addon bucket/native secure ownership is
  the cause.

### Test 5: separate micro-addon owner

Create a tiny separate addon, for example `MSUF_ClickCore`, whose only job is to
spawn the protected click shells. MSUF would parent visual frames to those
shells but not own/create the secure buttons.

Expected result:

- If MSUF peak disappears and `MSUF_ClickCore` receives the small/native cost,
  addon-bucket ownership is a major reason the profiler result looks better.
- If the total user-visible spike remains high, there is still a real native
  path cost independent of bucket ownership.

## Key Commands Used

Inspect current frame:

```lua
/msufinspect player
```

Profiler bucket sampling:

```lua
/msufpeak 10
```

Function wrapper sampling:

```lua
/msufclickcore 8
/msufclickall 8
```

Probe buttons:

```lua
/msufclickcore buttons
```

## Current State Before Hard Reset

The core is now much closer to a direct event backend for normal
runtime work. Target swap performance is good. The remaining blocker is not the
ordinary update path; it is the protected click shell path for MSUF-owned secure
unit buttons.

The next implementation should not be another broad backend rewrite. It should
isolate the secure shell cost by toggling ClickCastFrames, menu proxy, ping, and
finally ownership via a separate micro-addon.

## Hard Reset Baseline Implemented

Date: 2026-07-07

Changed files:

- `Engine/MSUF_UF_Factory.lua`
- `Engine/Group/MSUF_UF_Group_Adapter.lua`
- `Engine/Group/MSUF_UF_Group_Headers.lua`
- `Engine/Elements/MSUF_UF_Elements_LoadConditions.lua`

Singleframes now use the actual unitframe as the protected button again:

```lua
MSUF_player = SecureUnitButtonTemplate
unit = player
type1 = nil
*type1 = target
type2 = nil
*type2 = togglemenu
*clickbutton2 = nil
ping-receiver = nil
RegisterForClicks("AnyUp")
RegisterUnitWatch(MSUF_player)
```

Removed from the active Singleframe core path:

- `MSUF_playerClick` / visual-shell split
- `PingableUnitFrameTemplate`
- `ping-receiver`
- secure menu proxy button
- `*type2=click`
- ClickCastFrames registration
- custom `MSUF_PetBattleFrameHider` parent

Group header children were also reduced to the same minimal click attributes.
The visual unitframe is now the secure header child itself, not a separate child
frame below it.

Expected inspect result after `/reload`:

- `/msufinspect player` should not print a `clickShell=` line.
- `attrs` should show `unit=player`, `*type1=target`, `type1=nil`,
  `*type2=togglemenu`, `*clickbutton2=nil`, `ping=nil`.
- `/msufpeak 10` should be retested by clicking MSUF player and party frames.

If the 5-7ms spike is gone, the removed shell/proxy/ping/header-child model was
the cause. If the spike remains on `MSUF_player`, the next isolation step is a
separate micro-addon owner for only the secure button, because the active MSUF
click path is now already the minimal direct path.

## Prototype Probe Matrix

Date: 2026-07-07

Created standalone addon:

- `MSUF_ClickPrototype`

It contains eventless or minimal secure buttons:

- A: insecure/no secure action
- B: `SecureUnitButtonTemplate`, no target action
- C: `SecureUnitButtonTemplate`, `unit=player`, `*type1=target`
- D: C + `RegisterUnitWatch`
- E: C + direct `type1=target`
- F: C + `RegisterForClicks("LeftButtonUp")`
- G: template variant with `SecureUnitButtonTemplate, PingableUnitFrameTemplate`,
  `PetBattleFrameHider`, `toggleForVehicle`
- H: attempted `SecureActionButtonTemplate` target action, did not target on PTR
- I: explicit clone with Pingable template, PetBattleFrameHider, UnitWatch,
  ClickCastFrames, UnitFrame_OnEnter/OnLeave, OnShow, OnAttributeChanged,
  PEW/vehicle events
- J: real spawned player frame when an external frame runtime is loaded

Observed from user:

- C/D/E/F/G all spike.
- A/B do not.
- H is invalid because it does not target.

Current implication:

The shared cost is the native `SecureUnitButtonTemplate` target action, not
MSUF bars/text/runtime. This must still be compared with the exact same external
profiler.

## External Perf Lab

Created standalone addon:

- `MSUF_PerfLab`

Commands:

```lua
/plabpeak 10
/plabpeak 10 all
/plabclicktrace 10
/plabmouse
/plabinspect player
/plabinspect POUF_RealOUF
```

Purpose:

Measure `MidnightSimpleUnitFrames`, prototype addons, comparison addons, and the
profiler itself from outside the MSUF addon bucket. The previous `/msufpeak`
command is useful but runs inside MSUF and can contaminate the MSUF addon bucket.

`/plabclicktrace` temporarily installs `PreClick`/`PostClick` scripts on known
prototype, MSUF, and comparison frames and restores the original scripts after
the sample window. It measures the elapsed time between PreClick and PostClick for the
actual clicked frame, which helps determine whether the cost is inside the
native secure click path rather than a later event/addon bucket.
