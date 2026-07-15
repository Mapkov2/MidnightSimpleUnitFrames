## Castbars Module Map

Load order is defined in `MidnightSimpleUnitFrames.toc`; keep exported `_G.MSUF_*`
names stable unless every caller is updated.

### Shared runtime and style

- `MSUF_Castbars_Backend.lua` resolves MSUF/Blizzard/hidden backend state and keeps legacy enable flags in sync.
- `MSUF_Castbars_Bridge.lua` bridges castbar settings into the UnitFrames module lifecycle and Blizzard player castbar suppression.
- `MSUF_CastbarEngine.lua` converts WoW casting/channel APIs into the canonical cast state and enabled-only subscriber stream.
- `MSUF_CastbarRuntime.lua` applies active, interrupted, and stopped cast states to frames.
- `MSUF_CastbarStyle.lua` owns castbar outline and time-text layout helpers.
- `MSUF_CastbarUtils.lua` contains shared color, reverse-fill, glow, shake, text-shortening, and empower cleanup helpers.
- `MSUF_CastbarVisuals.lua` refreshes boss castbar visuals after the main visual refresh has run.

### Frame creation and anchoring

- `MSUF_CastbarFrames.lua` builds real and preview frame elements.
- `MSUF_CastbarAnchors.lua` computes desired sizes, width sources, and player/target/focus/boss reanchors.
- `MSUF_CastbarPreviewEdit.lua` handles edit-mode drag, resize, nudge, and popup integration for previews.
- `MSUF_CastbarPreviews.lua` creates and positions player/target/focus preview castbars.
- `MSUF_BossCastbars_Preview.lua` creates and positions boss preview castbars.

### Player, target, focus, boss behavior

- `MSUF_Castbars.lua` creates and manages the player castbar.
- `MSUF_PlayerCastbarRuntime.lua` handles player-specific cast events, latency, vehicles, and interrupt feedback.
- `MSUF_CastbarDriver.lua` handles target/focus castbar event registration and state transitions.
- `MSUF_BossCastbars.lua` creates boss castbars and applies boss event/layout behavior.
- `MSUF_CastbarEmpower.lua` handles Evoker empower stages, ticks, blink, and stage colors.
- `MSUF_CastbarChannelTicks.lua` handles player channel tick markers.

### Interrupt and focus tools

- `MSUF_InterruptReady.lua` colors the interrupt-ready indicator on target/focus/boss castbars.
- `MSUF_FocusKick_StateDriver.lua` routes focus cast state into the focus kick tracker.
- `MSUF_FocusKickIcon.lua` creates and updates the detached focus interrupt tracker.
