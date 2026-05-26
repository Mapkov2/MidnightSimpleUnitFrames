# MSUF 6.0 Hot/Warm/Cold Path Audit

Scope: compare the proven 5.52 runtime shape against the current 6.0 rewrite and identify what must stay hot, what is warm, and what belongs in cold paths.

## Definitions

- Hotpath: high-frequency events or frame ticks. Examples: `UNIT_HEALTH`, `UNIT_POWER_UPDATE`, `UNIT_POWER_FREQUENT`, `UNIT_AURA`, active castbar/class-power ticks.
- Warmpath: gameplay changes that happen often enough to matter but not every frame. Examples: target/focus swap, boss engage, roster/unit target changes, entering world, delayed dirty flushes.
- Coldpath: profile/config/menu/edit/import/layout/build work. This may do DB reads, table building, font/texture/anchor work, but should not run from hot events.

Hotpath rules:

- No `MSUF_DB` or menu/model reads.
- No config compilation.
- No frame creation or layout rebuild.
- No broad `RefreshAll` unless it is explicitly a cold/manual operation.
- No duplicate aura scans.
- No generic all-element loops for health/power if a direct specialized path is possible.

## 5.52 Baseline

5.52 is still faster because its expensive work is already split aggressively:

- `Core/MSUF_UnitframeCore.lua` keeps DB bootstrap and migration out of runtime hot paths.
- `UFCore_RefreshSettingsCache` builds file-scope hot settings once, then hot handlers read cached locals.
- `ComputeElementMask` and `RefreshUnitEvents` diff event registration per frame, so disabled features do not receive events.
- `UNIT_HEALTH` and power events use direct dispatch instead of walking every element.
- `_HealthValueFast` reads health/max, updates the bar, and only updates text/color when that feature is enabled.
- Power handling is split between player frequent updates and non-player normal updates.
- Cold or expensive work is marked dirty and flushed through a budgeted queue.
- GroupFrames already use frame caches, event masks, lean health/power handlers, coalesced text flushes, and aura burst budgeting.
- ClassPower caches DB-derived config and only runs central ticks for modes that actually need ticking.

The important lesson is not that 5.52 has fewer features. It is that health/power/aura events are narrow and direct, while config, menu, layout, and preview work are outside the hot loop.

## 6.0 Current Hotpath

These are currently hot in 6.0 and must remain extremely small:

- `UnitFrames/Core/MSUF_UF_Core.lua`
  - `DispatchFrameEvent`
  - per-frame `OnEvent`
  - element event-owner lookup
  - element `Update` calls
- `UnitFrames/Core/Elements/MSUF_UF_Elements_BarsText.lua`
  - `Health.Update`
  - `Power.Update`
  - `Text.Update` when bound to health/power/name events
- `UnitFrames/Core/Elements/MSUF_UF_Elements_Visuals.lua`
  - `Alpha.Update` for target range events when target range fade is enabled
  - `Borders.Update` for `UNIT_AURA` and threat events
  - `Auras.Update` when `UNIT_AURA` enters the Auras3 bridge
  - `Status.Update` for raid target and leader changes
- `Auras3/MSUF_Auras3_UnitFrames.lua`
  - aura scan/filter/render for unit aura changes
- `UnitFrames/Core/Group/MSUF_UF_Group_AuraCache.lua`
  - single group aura snapshot per unit aura event
- `UnitFrames/Core/Group/MSUF_UF_Group_Visuals.lua`
  - group visual overlays remain event-driven for group frames
- `UnitFrames/Core/Group/MSUF_UF_Group_Auras.lua`
  - aura lanes consume the shared snapshot instead of scanning again
- `UnitFrames/Core/Group/MSUF_UF_Group_Runtime.lua`
  - secure header scans and child attachment must stay outside unit-event hotpaths
- `ClassPower/MSUF_CP_Controller.lua`
  - active class-power ticks and active power/aura events
- `Castbars/MSUF_Castbars_Core.lua`
  - active cast/channel ticks and cast event handling

Risk in current 6.0:

- UnitFrames health/power still go through a generic element dispatch loop.
- `ForceUpdate` still updates all enabled elements for a frame.
- `Text.Update` is event-aware, but formatting and mode branching are still inside the event path.
- Health/power color and background apply logic can still be reached from hot events.
- Auras3 can still pull config resolution/render behavior into gameplay refreshes if not cached tightly.
- Edit-mode refresh hooks must not run as part of gameplay aura refresh.

## 6.0 Current Warmpath

These are acceptable during target/focus/boss swaps or explicit refreshes, but must not be triggered repeatedly from health/power/aura:

- `UnitFrames/Core/MSUF_UF_Core.lua`
  - `UF.ForceUpdate`
  - `ForceUnits`
  - `DriverOnEvent`
  - `UF.RefreshElements`
  - `UF.RefreshVisuals`
  - `UF.NotifyConfigChanged`
- `UnitFrames/Core/MSUF_UF_Factory.lua`
  - `Factory.Apply(unit)`
  - `ApplyFrame`
  - `ApplyElements`
- `Auras3/MSUF_Auras3_UnitFrames.lua`
  - `A3.RefreshAll`
  - unit refresh requests after target/focus/boss changes
- `GroupFrames/MSUF_GroupFrames_Render.lua`
  - visual refresh and frame rebuild orchestration
- `ClassPower/MSUF_CP_Controller.lua`
  - full refresh, layout, and cache invalidation
- `Castbars/MSUF_Castbars_Core.lua`
  - castbar visual refresh and backend switching
- `Menu2/MSUF_Menu2_Bindings.lua`
  - config-change notification and UI-triggered apply

Warm path danger zones:

- `UF.ForceUpdate` is too broad for target/focus swaps if it calls every enabled element.
- Castbar refresh should not call full UF updates for targettarget unless the unit relationship actually changed.
- `A3.RefreshAll` must stay gameplay-only when called by gameplay; edit/menu preview must be gated separately.
- GroupFrame visual refresh must rely on cached frame config and avoid fresh DB walks.

## 6.0 Current Coldpath

These belong in coldpath and should be allowed to do heavier work:

- `UnitFrames/Core/MSUF_UF_Config.lua`
  - DB/profile compatibility
  - unit spec compilation
  - default merging
  - old-profile migration normalization
- `UnitFrames/Core/MSUF_UF_Factory.lua`
  - frame creation
  - secure click attribute setup
  - initial element creation
  - anchor/layout apply
- Element `Apply` methods
  - textures
  - fonts
  - font flags
  - anchors
  - sizes
  - static colors
  - static border pieces
- Blizzard frame visibility handler
  - hidden parent setup
  - unregister/hide/reparent
  - combat-deferred protected reparenting
- Auras3 menu/edit/model code
  - preview
  - editing
  - import/export
  - options model
- GroupFrame full rebuilds
- profile import/export and migrations

Coldpath danger zones:

- Cold modules may register hooks into warm/hot functions, but they must be gated by edit/menu state.
- Preview code must never run because of a normal `UNIT_AURA`, target swap, health, or power event.
- Config resolution must produce runtime specs consumed by frames; hot code should not discover config shape.

## What Must Move Colder In 6.0

1. Replace generic health/power dispatch with direct specialized dispatch.
   - `UNIT_HEALTH` should call the health fast path directly.
   - Power events should call the power fast path directly.
   - Text should only be called from those paths when visible text actually depends on that value.

2. Split text runtime into compiled text specs.
   - Compile mode, delimiter, percent/current/max behavior, font handles, and enabled flags in cold config.
   - Hot text update should only receive numbers and set the final string if it changed.

3. Move static health/power color work out of hot updates.
   - Static class/power/dark/custom colors should be cached on the frame.
   - Hot color calculation should only run for truly dynamic modes: gradient, reaction, threat, or NPC-type color.

4. Move background application out of health/power hot updates.
   - Texture and static background color are cold.
   - Hot background changes are only valid when explicitly tied to dynamic health/power color matching.

5. Replace broad `ForceUpdate` use with dirty masks.
   - Target swap should refresh identity, health, power, aura, and status for the affected unit.
   - It should not update castbar, classpower, portrait, borders, and all text unless those masks require it.

6. Gate Auras3 edit-mode refresh.
   - `A3.RefreshAll` used by gameplay must not trigger edit preview/model refresh unless edit mode or menu preview is active.

7. Cache Auras3 unit config.
   - Aura render must consume a compiled unit aura spec.
   - `EnsureDB` and config shape resolution belong to config invalidation, not aura rendering.

8. Keep border aura consumers attached to the aura state.
   - Borders should not scan auras independently.
   - Static border is cold.
   - Dispel/purge/priority border only runs when aura state changes and that feature is enabled.

9. Narrow castbar-to-unitframe coupling.
   - Castbar visual refresh should not call full `UF.ForceUpdate`.
   - If ToT visuals need refresh, update only the specific targettarget/focustarget identity or visibility state.

10. Keep GroupFrame DB reads inside frame cache rebuild.
    - GroupFrame hot render must continue using cached frame state and event masks.
    - Any remaining render-time DB read should be treated as a bug unless the function is cold/manual.

11. Keep ClassPower layout cold.
    - Runtime class-power ticks should update values only.
    - Size, anchors, texture, font, and unitframe bridge layout belong to cold refresh.

12. Make `RefreshAll` names honest.
    - Full refresh functions should be cold/manual only.
    - Gameplay code should call unit-specific or element-specific refresh functions.

## Practical Priority

Highest impact first:

1. Direct health/power dispatch in the new UF core.
2. Compiled text fast paths for health and power text.
3. Auras3 gameplay refresh separated from edit/menu preview refresh.
4. Remove static color/background work from health/power events.
5. Replace broad `ForceUpdate` calls on target/focus/boss changes with dirty masks.
6. Audit castbar refresh calls that currently wake UnitFrames unnecessarily.

This is the performance gap versus 5.52: 6.0 has fewer files and less code, but its hot handlers are still too generic. The rewrite only wins once the hot paths are as direct as 5.52 while keeping the new code structure and cold compiled specs.

## 2026-05 Cache Pass Result

The current 6.0 UnitFrames runtime now has the same important shape as the fast 5.52 paths:

- Health, power, name, aura, threat, range, and portrait events use direct dispatch instead of a broad all-element loop.
- Runtime refreshes use reason masks, so font, alpha, border, power-layout, and castbar sync updates do not wake unrelated elements.
- Health and power return their already-read values to Text, so text does not read `UnitHealth` / `UnitPower` again on normal updates.
- Health/power max values are cached between max-change events.
- StatusBar values, font strings, alpha, border color, aura icon texture, aura stack text, aura button size, aura mouse state, and aura hide ranges are now set only when changed.
- Auras3 runtime config is cached by runtime generation; DB/profile reads stay in config resolution, not aura rendering.
- Empty `UNIT_AURA` payloads return before runtime dispatch.
- Auras3 edit preview refresh is gated behind active edit mode.
- Auras3 unitframe ownership avoids duplicate global target/focus/boss refresh events when the UF driver owns runtime refresh.
- Border dispel state is aggregated from the Auras3 debuff lane and consumed by Borders, instead of scanning aura state again on every `UNIT_AURA`.
- Range alpha no longer does a separate `UnitExists` call before `UnitInRange`; the secret-safe range result drives the alpha directly.
- ClassPower runtime ticking is centralized and throttled to 30 Hz, only while a mode actually needs animation.
- ClassPower disabled-state is now hard-gated: no resource-type resolve, no structural/spec/vehicle events after startup, no central tick, no Warrior Whirlwind eventframe, no Balance Druid prediction eventframe, and no texture/font refresh work when Class Resources and Alt Mana are off.
- Gameplay range/FirstDance ticks are gated and throttled so they do not run as idle background work.

Remaining honest limits from static analysis:

- Auras still must do full scans on true full updates, target/focus swaps, boss activation, or config invalidation. That cost is necessary unless visible aura behavior changes.
- Dynamic health colors still need unit state/class/reaction/classification reads on non-health events or gradient modes. Moving more out would break old profile behavior.
- Secret values cannot be safely compared or cached in every case. Those paths deliberately fall back to direct `SetValue` / formatted text work.
- Castbars and ClassPower are still separate legacy runtimes. Their active cast/channel/timer modes can only be judged accurately with Perfy top functions.
- GroupFrames have not moved to the new backbone yet; they already have their own 5.52-style caches, but they are still a separate system.

At this point the single UnitFrame code-side cache work is near the practical static-analysis limit. Further wins should be driven by an in-game Perfy trace, because guessing beyond this point risks changing visuals or profile compatibility more than it improves CPU.

## 2026-05 Text/Prediction/Castbar Pass

- HP bar values still update immediately on every health event.
- HP text rendering is throttled to 100ms by default through compiled `frame.MSUFSpec.text.healthThrottle`; skipped health text updates keep the latest pending value and flush by timer.
- Text apply work is stamped: fonts, text colors, layers, anchors, frame levels, and show states only write when changed.
- Powerbar layout apply work is stamped, including detached/embed mode, size, offset, and frame level.
- Health `SetReverseFill` is stamped.
- Heal prediction, damage absorb, and heal absorb are now their own `Prediction` element, not part of `Health`.
- `Prediction` registers only prediction/absorb/max-health/connection events. It does not register `UNIT_HEALTH`, so normal health changes do not read prediction APIs.
- The castbar manager now has low/high buckets. Timer-driven normal casts run through a 100ms ticker bucket with no per-frame `OnUpdate`; empower and manual `SetValue` fallback paths stay high-frequency.

Remaining honest limits:

- Absorb/heal prediction visuals are intentionally conservative in the new single-UF element. More exact 5.52-style edge-follow anchoring can be added later, but it should stay inside `Prediction`, not `Health`.
- Normal timer-driven castbars trade up to 100ms text/safety latency for lower active-cast CPU. Empower/manual fallback remains smooth.
