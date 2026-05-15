# Changelog

## 5.1 - 2026-05-15

### Highlights
- Group Frames now support Blizzard/native aura rendering or MSUF custom aura rendering per aura type.
- Group Frame Blizzard aura rendering now has full controls for icon size, limits, organization,
  cooldown text, strata, frame level, and private aura handling.
- Custom defensive aura groups now have placement, size, growth, spacing, cooldown, and stack
  controls.
- Target-of-Target inline text now supports expanded separator options, including a custom separator
  field with preview support.
- Wago Profiles now includes a readable in-game release notes panel.

### Group Frames And Auras
- Added per-type Blizzard routing for buffs, debuffs, dispels, defensives, and private auras.
- Added a locked Blizzard/native preview layer so the preview reflects the selected aura renderer.
- Improved Group Frame aura preview fidelity for custom aura text, cooldowns, stacks, dispel
  indicators, private auras, Blizzard/native auras, fonts, and highlight layers.
- Disabled Group Frames now stop their MSUF feature work and hand control back to Blizzard frames.
- Blizzard aura containers skip unnecessary rebuilds during cheap aura updates.
- Group Frame range fade and target range checks were tightened and made more consistent.
- Group Frame aggro, dispel, purge, and boss-target highlight behavior now respects the active scope
  and outline settings more reliably.

### Unit Frames And Text
- Unit Frame heal prediction now uses the same incoming-heal overlay path across Unit Frames,
  supports non-player Unit Frames, and hides correctly when disabled.
- Power text now reads and formats only the values required by the selected display mode.
- Health percent text now clears only when needed and avoids repeated percent-mode lookups.
- Target-of-Target inline text now supports custom separators with shared sanitization and UTF-8
  length limits.
- Unit Frame preview now supports the new Target-of-Target inline separator options.

### Menus And Preview
- Added page-level reset support across menus.
- Menu and Edit Mode actions are now combat-gated with clearer combat-lock messages.
- Reset and clear actions now have clearer instructions.
- Global Bars and MSUF scale changes now apply live more reliably.
- Group Frame preview behavior was improved for aura placement, text, cooldowns, stacks, borders,
  highlights, and Blizzard/native renderer states.
- Locale coverage was updated for the 5.1 Group Aura and Blizzard Renderer options.

### Performance
- Aura2 incremental updates now ignore empty or irrelevant `UNIT_AURA` payloads instead of forcing
  full scans.
- Friendly dispel and purge outline updates now only register and queue when the current character
  can actually use those effects.
- Friendly dispel and purge capability is cached per player class/race and refreshed on login.
- Group Frame aura renderer/type data is cached during frame cache builds instead of being resolved
  repeatedly.
- Group Frame highlight values, colors, AFK/DND/dead/ghost status flags, range fade, and target range
  paths do less repeated settings work.
- Group Frame range fade refreshes are batched through delayed refreshes for relevant spell, talent,
  spec, trait, world-entry, and combat-state events.
- Unit Frame power text, health percent text, and Target-of-Target inline text avoid repeated mode
  and separator resolution in hot paths.
- Interrupt Ready colors reuse cached color objects instead of allocating new ones during refreshes.
- Aura2 reminder scans skip disabled or irrelevant provider classes earlier and prefer cached player
  aura data.
- Hover highlight cleanup avoids redundant `Hide()` calls when the highlight is already hidden.

### Bugfixes
- Fixed secret-value taint crashes in alpha handling.
- Fixed Group Frame raid marker taint from secret-value comparisons.
- Fixed profile exports falling back to raw Lua table strings for dirty runtime profiles.
- Fixed Scheduler sparse queue errors.
- Fixed Clique / Blizzard click-casting registration for Group Frames.
- Fixed preview Group Frames being added to the click-casting registry.
- Fixed disabled Group Frames still running feature updates.
- Fixed protected menu and Edit Mode operations being possible in combat.
- Fixed Group Frame menu/Edit Mode preview hiding real raid or mythic raid frames after closing.
- Fixed Blizzard/native aura preview implying draggable custom placement.
- Fixed Group Frame range fade being skipped by runtime gating.
- Fixed Group Frame range fade alpha targeting in combat-safe paths.
- Fixed Group Frame Dispel Glow still showing when Blizzard's native aura renderer is selected.
- Fixed Group Frame aura preview fallback settings for aggro and target highlight indicators.
- Fixed Group Frame highlight and outline resolution for aggro/dispel outline settings, including
  global settings and per-group overrides.
- Fixed Group Frame border and highlight preview behavior.
- Fixed highlight preview toggles for aggro, dispel, purge, and boss-target tests.
- Fixed Global Bars live apply for Group Frames by rebuilding the frame cache before refreshing
  borders and highlight state.
- Fixed the dashboard MSUF UI scale Apply button not applying immediately.
- Fixed global MSUF scale collection including Group Frames with unsupported scale modes.
- Fixed detached power bar outline mode.
- Fixed health color gradient toggle also enabling the HP bar overlay gradient.
- Fixed Absorb Bar Test Mode.
- Fixed permanent buff toggle behavior.
- Fixed Unit Frame heal prediction across Unit Frames and disabled states.
