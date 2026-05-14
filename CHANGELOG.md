# Changelog

## 5.1 Beta 2 - 2026-05-14

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
- Fixed Group Frame border/highlight preview behavior.
- Fixed Absorb Bar Test Mode.
- Fixed permanent buff toggle behavior.
- Fixed release package metadata/workflow issues.
