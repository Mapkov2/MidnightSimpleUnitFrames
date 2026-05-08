# Changelog

## 4.3 - 2026-05-08

Based on Git commits from 2026-05-07 (`f2ee5f6` through `64eab74`) and 2026-05-08 (`97028a1` through `744e202`).
This release includes the changes from `4.21 Beta - 2026-05-07` plus the 4.3 updates from 2026-05-08.

### Short Version

- Castbars can now match different width sources more flexibly.
- Group Frames, Auras, Castbars, and several visual options should update more efficiently.
- Group Frame aura cooldowns are easier to configure, with separate controls for cooldown text and cooldown swipe.
- Several issues with timers, transparency, aura updates, previews, and reset behavior were fixed.

### Added

- Castbars now have a per-unit width source setting.
  - Available sources are manual width, the matching MSUF unit frame, the Essential Cooldown Row, or the Utility Cooldown Bar.
  - This works for Player, Target, Focus, and Boss castbars.
- Castbar Edit Mode now has a new `Width source` selector.
- Group Frame Auras now have a separate option for cooldown swipe.
  - Cooldown swipe and cooldown text can be enabled or disabled independently.
- New Group Frame Aura cooldown style: the cooldown swipe can darken as the cooldown runs down.
- Existing Group Frame Aura profiles are migrated automatically to the new cooldown swipe options.
- Global styling helpers for sliders and small buttons were added, making the Options menu and slash menu more consistent.

### Changed

- Large performance pass across Auras 2.0, Group Frames, Castbars, Combat Crosshair, Interrupt Ready, and Unitframe visuals.
- Auras 2.0 now batches quick aura changes instead of fully re-rendering every single change immediately.
- Aura icons are updated more selectively: pure timer, stack, or aura updates only touch the affected icons.
- Group Frames now update names, colors, health text, power text, and status layouts only when the displayed state actually changes.
- Group Frame roster updates use a more stable GUID-based mapping and avoid unnecessary button updates.
- Group Frame auras cache frequently used filter and max-value settings to make repeated aura updates cheaper.
- Blizzard aura containers in Group Frames are no longer rebuilt for small aura updates when they are already active.
- Dispel and purge highlights still react quickly, but process aura bursts in a more controlled way.
- Focus and Boss Range Fade events are registered more tightly per unit.
- Castbar safety checks now use a lower-frequency ticker and avoid unnecessary health events on Target and Focus castbars.
- Boss castbar previews no longer do hidden refresh work during combat. If needed, one refresh is replayed after combat.
- Combat Crosshair now uses a ticker for range coloring instead of a permanent `OnUpdate`.
- Interrupt Ready now reacts only to relevant castbars and relevant cooldown events.
- Portrait and Portrait Decoration sync now use more centralized refresh functions and stable callbacks.
- Group Frame power bars now use the central MSUF power color resolver, keeping them consistent with the addon's color settings.
- Target-of-target swap recoloring is now triggered by the Unitframe Core and no longer needs a second event owner.
- Gameplay, Color, and Load Condition updates are coalesced more reliably, especially while dragging sliders or during rapid state changes.
- `Reset Positions` now explains more clearly what will be reset in the active profile.
- Fresh install defaults were updated.
- TOC versions were bumped to 4.3.

### Fixed

- HP transparency: fixed an edge case where health bar textures could keep the wrong alpha after certain visual updates.
- Layered alpha is now reapplied cleanly after relevant visual updates.
- Rune cooldown timers now calculate elapsed time correctly using `GetTime() - start`.
- Rune timers are clamped properly and clear their text reliably when a rune is ready or empty.
- Boss Frame healer-buff highlighting now includes `forceOwnBuffHighlight` in the cache key.
- Private Aura options were cleaned up.
  - Private Auras are only active for player slots.
  - Old target Private Aura defaults and options were removed.
- Fresh install defaults now set `bars.showAltMana` to `false`.
- Gameplay sliders for melee spell input and crosshair settings fit better inside the Settings panel.
- Slider styling is applied more reliably, even when the style helper loads later.
- Auras 2.0 now removes stale cooldown and aura references when hiding unused icons.
- Group Frame aura cooldown swipe and cooldown text can be disabled without leaving stale timer or swipe visuals behind.
- Auras 2.0 correctly handles cases where Blizzard reports an aura as updated even though it has already expired.
- Group Frame Auras safely fall back to the full update path when an updated aura has already expired.
- Castbar width sources no longer overwrite manual widths while an external width source is active.
- Castbar previews now use the same width logic as real castbars.
- Target, Focus, and Boss castbar icons now respect their own icon sizes more reliably.
- Scroll arrows in the Edit Mode popup now point in the correct direction.
- Castbar options layout was cleaned up after the old player-only width source setting moved into the new per-castbar selector.
