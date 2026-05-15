# Changelog

## 5.1 Beta 4 - 2026-05-15

### Performance
- **Dispel / purge outline event gating**: Aura outline updates now only register and queue when the
  current player can actually friendly-dispel or purge. Friendly dispel and purge capability are cached
  per player class/race and refreshed on login.
- **Dispel / purge aura filtering**: Incremental `UNIT_AURA` updates now skip queue work when the
  changed aura data cannot affect the active friendly-dispel or purge outline state.
- **Aura2 incremental updates**: Empty `UNIT_AURA` payloads are ignored early, while valid
  incremental aura deltas are processed through the cached aura update path instead of forcing a full
  invalidation scan during coalesced update bursts.
- **Group Frame cache build**: Blizzard aura type flags are resolved in one pass and stored in the
  per-frame cache, avoiding repeated renderer/type checks during frame cache rebuilds.
- **Group Frame highlight cache**: Highlight border values and colors are pre-resolved from group and
  general settings during cache build instead of re-running fallback lookups in hot paths.
- **Group Frame status text cache**: AFK, DND, dead, and ghost visibility flags are now cached per
  frame and reused by status text updates.
- **Group Frame range fade refresh**: Range fade resyncs are now queued through one delayed refresh
  for relevant spell, talent, spec, trait, world-entry, and combat-state events instead of running
  extra out-of-combat polling work.
- **Power text renderer**: Power text now reads and formats only the values required by the selected
  display mode. Raw/component diff guards also include mode, separator, and split settings to avoid
  stale skips after option changes.
- **Health percent text**: HP percent text clearing now happens only when needed and uses the
  precomputed text-spec requirement instead of repeatedly resolving the percent mode in hot paths.
- **Interrupt Ready colors**: Ready, cooldown, and outline colors now reuse cached `ColorMixin`
  objects per configured RGBA value instead of allocating new color objects during refreshes.
- **Aura2 reminders**: Reminder scans now ignore disabled or irrelevant provider classes before aura
  lookup work, and prefer cached player aura data before falling back to direct API scans.
- **Hover highlight hide hook**: Unitframe highlight cleanup avoids redundant `Hide()` calls when the
  highlight is already hidden.
- **Unit Frame heal prediction**: Heal prediction now uses the same incoming-heal overlay path across
  Unit Frames, supports non-player Unit Frames, and hides early when the feature is disabled.

<!-- MSUF-AUTO-CHANGELOG:Performance:START -->
- **Unit Text, General**: Hp text performance update (3e6bb7e; Core/MSUF_Text.lua, MidnightSimpleUnitFrames.lua).
- **Core Runtime**: Range fade performance update for dead/ghost (70e9233; Core/MSUF_RangeFade.lua).
- **Unit Auras, Group Frames**: Aura performance update (1a71199; Auras2/MSUF_A2_Reminder.lua, GroupFrames/MSUF_GF_Effects.lua).
- **Unit Auras, Core Runtime**: Performance update (5e6023e; Auras2/MSUF_A2_Core.lua, Auras2/MSUF_A2_Render.lua, Core/MSUF_RangeFade.lua +1 more).
- **Borders / Outlines**: Updated border and outline behavior (working tree; MSUF_Borders.lua).
- **Borders / Outlines, Group Frames**: Performance fixes (9efb3ae; Core/MSUF_Borders.lua, GroupFrames/MSUF_GF_Auras.lua, GroupFrames/MSUF_GF_Effects.lua).
- **Borders / Outlines, Group Frames, General**: Performance and click casting changes (b15ea1f; Core/MSUF_Borders.lua, GroupFrames/MSUF_GF_Core.lua, GroupFrames/MSUF_GF_Effects.lua +1 more).
- **Core Runtime**: More performance (7f9d951; Core/MSUF_ColorsCore.lua).
- **Unit Auras**: Better reminder performance (a02be1e; Auras2/MSUF_A2_Reminder.lua).
- **Borders / Outlines**: Bugfix for performance (c0369cf; Core/MSUF_Borders.lua).
- **Interrupt Ready**: Performance for interrupt ready (cb53217; Modules/MSUF_InterruptReady.lua).
- **Unit Auras, Group Frames**: Aura performance (f3019b1; Auras2/MSUF_A2_Events.lua, GroupFrames/MSUF_GF_Effects.lua).
- **Unit Auras, Unit Text, Group Frames**: Performance stuff and bugfixes for highlight border (0fedb27; Auras2/MSUF_A2_Events.lua, Core/MSUF_Text.lua, GroupFrames/MSUF_GF_AuraPreview.lua +4 more).
- **Menu / Dashboard**: Updated menu, dashboard, or live apply behavior (working tree; MSUF_Menu2_GlobalBars.lua).
- **Menu / Dashboard**: Updated menu, dashboard, or live apply behavior (working tree; MSUF_Menu2_Global.lua).
- **Group Frames**: Updated Group Frame effects, range fade, or highlight behavior (working tree; MSUF_GF_Effects.lua).
- **Menu / Dashboard**: Updated menu, dashboard, or live apply behavior (working tree; MSUF_Menu2_GroupAuras.lua).
- **Menu / Dashboard**: Updated menu, dashboard, or live apply behavior (working tree; MSUF_Menu2_Group.lua).
- **Bars / Power Bars**: Updated bar and power bar behavior (working tree; MSUF_Bars.lua).
- **Core Runtime**: Updated core runtime behavior (working tree; MSUF_UnitframeCore.lua).
- **General**: Updated addon behavior (working tree; MidnightSimpleUnitFrames.lua).
- **Core Runtime**: Updated core runtime behavior (working tree; MSUF_TextureRuntime.lua).
- **Menu / Dashboard**: Updated menu, dashboard, or live apply behavior (working tree; MSUF_Menu2_Theme.lua).
<!-- MSUF-AUTO-CHANGELOG:Performance:END -->

### Bugfixes
- Fixed friendly dispel / purge capability detection using the correct class and race tokens, so aura
  outline event gating no longer misdetects player capabilities.
- Fixed profile exports falling back to raw Lua table strings when a dirty runtime profile contains
  non-serializable transient values. Normal successful exports keep the existing `MSUF3:` format.
- Fixed Clique / Blizzard click-casting registration for Group Frames. Frames are registered after
  tooltip `OnEnter` / `OnLeave` scripts are installed so Clique can wrap the final handlers.
- Fixed preview Group Frames being added to the click-casting registry.
- Fixed detached power bar outline mode. Detached power bars now use a dedicated outline path and no
  longer depend on the normal embedded power bar border logic.
- Fixed Group Frame highlight and outline resolution for the newer aggro/dispel outline mode settings,
  including global settings and per-group overrides.
- Fixed Group Frame aura preview fallback settings for aggro and target highlight indicators so the
  preview matches runtime behavior more closely.
- Fixed Global Bars live apply for Group Frames by rebuilding the frame cache before refreshing
  borders and highlight state.
- Fixed the dashboard MSUF UI scale Apply button so the scale is applied live immediately.
- Fixed global MSUF scale collection so Group Frames are only included when their own scale mode is
  `manual` or `auto`.
- Fixed Group Frame Dispel Glow continuing to show when the selected Group Frame scope uses Blizzard's
  native aura renderer.
- Fixed highlight preview toggles so aggro, dispel, purge, and boss-target border tests respect the
  current Bars scope and disabled outline modes.
- Restored combat-safe Group Frame range-fade alpha targeting while keeping the visual bar group as
  the out-of-combat alpha target.

<!-- MSUF-AUTO-CHANGELOG:Bugfixes:START -->
- **Group Frames, Menu / Dashboard, General**: Bugfixes to bars menu highlight border (bd147d2; GroupFrames/MSUF_GF_AuraPreview.lua, GroupFrames/MSUF_GF_Core.lua, GroupFrames/MSUF_GF_DB.lua +4 more).
- **Group Frames**: Clique casting fix (35e8576; GroupFrames/MSUF_GF_Core.lua, GroupFrames/MSUF_GF_Effects.lua).
- **Bars / Power Bars, Borders / Outlines**: FIXED outline mode for detached powerbar (4056b81; Core/MSUF_Bars.lua, Core/MSUF_Borders.lua).
- **Menu / Dashboard**: Fixed live apply button for unitframe scaling (ae83a6a; Menu2/MSUF_Menu2_Core.lua, Menu2/MSUF_Menu2_Support.lua).
- **Core Runtime, Foundation, Profiles**: Harden fallbacks for missing textures (ce914b2; Core/MSUF_Castbars.lua, Foundation/MSUF_Libs.lua, Foundation/MSUF_Profiles.lua +1 more).
<!-- MSUF-AUTO-CHANGELOG:Bugfixes:END -->

### Changes / Improvements
- Dashboard Wago Profiles now shows the bundled changelog from the previous release to the current
  build in a readable, collapsible in-game release notes panel, including beta builds.

<!-- MSUF-AUTO-CHANGELOG:Changes-Improvements:START -->
- **Group Frames**: This should out of combat range check (63794c0; GroupFrames/MSUF_GF_Core.lua).
- **Core Runtime, Group Frames**: RANGE fade (4d8d353; Core/MSUF_RangeFade.lua, GroupFrames/MSUF_GF_Effects.lua).
- **General**: Better coloring in addon folder (2c11245; MidnightSimpleUnitFrames_Castbars/MidnightSimpleUnitFrames_Castbars.toc).
- **Menu / Dashboard**: Better group frame preview highlight (2ecceff; Menu2/Pages/MSUF_Menu2_GroupPreview.lua).
- **Unit Text**: Only render the powertext that your actually using (9c199d2; Core/MSUF_Text.lua).
- **Group Frames**: Better range check (7c33fe4; GroupFrames/MSUF_GF_Effects.lua).
- **Foundation**: Changelog stuff (b8c1a80; Foundation/MSUF_Libs.lua).
<!-- MSUF-AUTO-CHANGELOG:Changes-Improvements:END -->

### Release / Tooling
- Added the release helper scripts/UI for preparing release notes, package builds, GitHub releases,
  Wago updates, and CurseForge publishing from one workflow.
- Added `tools/MSUF-AutoChangelog.ps1` / `.cmd` to refresh managed changelog blocks from commits and
  current working-tree changes, with optional in-game changelog regeneration.
- Added `tools/update-addon-changelog.ps1` to generate the bundled in-game changelog data from
  `CHANGELOG.md`.
- CurseForge publishing now uses `BigWigsMods/packager` directly from the release workflow.
- Release channel resolution now maps alpha/beta/prerelease tags to the correct Wago stability and
  CurseForge release type.
- CurseForge API secrets can be provided as either `CF_API_KEY` or `CURSEFORGE`.
- Release zips now use the full addon name (`MidnightSimpleUnitFrames<version>.zip`) instead of the
  short `MSUF-<version>.zip` name.
- Fixed the release workflow tag trigger and helper tag push behavior for beta release tags.

### Documentation
- Added `docs/PERFY_WORKFLOW.md` with the current Perfy trace workflow, validation rules, and known
  instrumentation pitfalls for future performance passes.

## 5.1 Beta 3 - 2026-05-14

### Performance (Stage 1 micro-optimizations)
- **`UFCore_FlushTask`**: `Core._flushSettingsCacheSerial` is now set each flush tick, activating the
  per-flush-cycle fast path in `UFCore_GetSettingsCache`. Previously the fast path was dead code
  (serial never set), so every `GetSettingsCache()` call re-ran 4 table-ref comparisons.
- **Health color gradient hot path**: `enableHealthGradient` is now snapped into file-scope locals
  during `UFCore_RefreshSettingsCache`. `_HealthValueFast` and `Elements.Health.Update` read one
  precomputed boolean instead of calling a per-frame DB/cache resolver.
- **`GF.QueueGroupBorderRefresh`**: Pre-built stable closures per `kind` (created once on first call).
  Switched primary dispatch to `MSUF_ScheduleOnce` (key-based dedup). Eliminates one new closure
  allocation + `GF._groupBorderRefreshQueued` table write per `GROUP_ROSTER_UPDATE` burst call.
- **Health color gradient checks**: `UFCore_RefreshFrameInvariantFlags` and
  `UFCore_RefreshHealthBarColorFast` also use the file-scope snapshot, so all UFCore gradient-color
  gates avoid per-frame DB resolution.
- **`TargetUnitInFriendlySpellsRange`**: `InCombatLockdown()` hoisted to function entry;
  eliminates the redundant `not InCombatLockdown or` nil-check pattern at both usage sites.

### Bugfixes
- **`MSUF_Alpha.lua` - secret-value arithmetic crash** (3111x spam): `GetAlpha()` and
  `GetStatusBarColor()` return secret values when WoW execution is tainted. The alpha diff
  functions (`_AlphaNearlyEqual`, `MSUF_Alpha_SetFlat`, `MSUF_Alpha_ApplyLayered`) and four
  EditMode minimum-alpha comparisons all performed arithmetic/comparison on these values,
  crashing with "attempt to perform arithmetic on a secret number value". All sites now use
  `issecretvalue` guards before arithmetic; on secret input the functions fall through to
  `SetAlpha` (safe conservative re-apply) rather than attempting comparison.

### New Features
- Group Frame aura renderer split: Blizzard/native or MSUF custom.
- Per-type Blizzard routing for buffs, debuffs, dispels, defensives, and private auras.
- Blizzard aura controls: icon size, limits, organization, cooldown text, strata, frame level, and private-aura layer fix.
- Group Frame aura preview with custom layers plus locked Blizzard/native layer.
- Custom defensive aura group controls for placement, size, growth, spacing, cooldown, and stacks.
- Page-level reset support across menus.
- Release tooling for GitHub, Wago, CurseForge, package builds, and manual publishing.

### Changes / Improvements
- Disabled Group Frames now stop their MSUF feature work and hand control back to Blizzard frames.
- Menu and Edit Mode actions are combat-gated with a clear combat-lock message.
- Blizzard aura containers skip unnecessary rebuilds during cheap aura updates.
- Group Frame aura, healer buff, group number, effects, and render paths were tightened for lower overhead.
- Range fade and target range checks are more performant.
- Aura2 reminder/range refresh behavior does less idle work.
- Group Frame preview better matches custom aura text, cooldown, stack, dispel, private, and Blizzard aura paths.
- Group Frame preview font rendering improved.
- Locale coverage updated for all 5.1 Beta 1 Group Aura / Blizzard Renderer strings.
- CurseForge release flow now uses auto-packaging with fixed package roots.
- Release publishing workflow hardened.

### Removed
- Removed experimental external `DR %` before Beta 1.

### Bugfixes
- Fixed Scheduler sparse queue errors (`table index is nil`).
- Fixed Group Frame raid marker taint from secret-value comparisons.
- Fixed disabled Group Frames still running feature updates.
- Fixed protected menu/edit operations being possible in combat.
- Fixed Blizzard/native aura preview implying draggable custom placement.
- Fixed Group Frame menu/Edit Mode preview hiding real raid/mythic raid frames after closing.
- Fixed Group Frame range fade being skipped by runtime gating.
- Fixed health color gradient toggle also enabling the HP bar overlay gradient.
- Fixed Group Frame border/highlight preview behavior.
- Fixed Absorb Bar Test Mode.
- Fixed permanent buff toggle behavior.
- Fixed release package metadata/workflow issues.
