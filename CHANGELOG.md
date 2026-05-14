# Changelog

## 5.1 Beta 2 - 2026-05-14

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
- **`MSUF_Alpha.lua` — secret-value arithmetic crash** (3111× spam): `GetAlpha()` and
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
