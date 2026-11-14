# MSUF 7.0 Preliminary Full Changelog

**6.511 → 7.0 Beta 6 · November 9, 2026**

- Baseline is 6.511 (`ffb3ca48d`). Target is 7.0 Beta 6 (`3a480dcfe`). [6.511 release](https://github.com/Mapkov2/MidnightSimpleUnitFrames/releases/tag/v6.511) · [Beta 6 release](https://github.com/Mapkov2/MidnightSimpleUnitFrames/releases/tag/classic-v7.0-beta6)
- Supported clients are Midnight (Retail), WoW Forever, Classic Era, Burning Crusade Anniversary, and Mists of Pandaria Classic. Options vary by client. [Client matrix](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/tools/classic-client-matrix.tsv)

## 1. Features and fixes

### Icon Skins

- Added an Icon Skins gallery with live previews for frames, shadows, rings, and gloss.
- Set a shared skin or override it per supported area. Choose Custom to use your manual appearance settings.
- Added a round variant with inner and outer shading.
- Skins work on auras and supported castbar and tracker icons. Compatible Suite modules can use them on cooldown and action bar icons. [Icon Skins](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/docs/ICON_SKINS.md)

### Profiles

- Save, inspect, and restore named restore points.
- See what changed and whether a setting comes from the profile or a variant. [Profile workbench](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/MidnightSimpleUnitFrames/State/MSUF_ProfileWorkbench.lua)
- Review profile imports and choose which incoming changes to apply.
- Undo and redo several edits in order, including nested settings and changes to individual scopes. Supported Suite settings can be included in history and restores.
- Record frame positions and relative UI scale in a profile variant. Set width and aspect-ratio conditions for when it applies. [Display rules](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/MidnightSimpleUnitFrames/State/MSUF_ProfileWorkbenchTools.lua)

### Edit Mode

- Added placement controls for Priority Frames and Gameplay positions. Typed coordinates and dragging have separate undo steps. [Edit Mode changes](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/docs/EDITMODE_ENGINE_DELTA.md)

### Menu, search, and previews

- The Dashboard adapts to window width. It includes Quick Setup, Suite Setup, search, recovery, and display scaling.
- Updated window resizing, window controls, and dropdown scrolling.
- Search covers more settings and dropdown choices. Results can open the matching tab, section, or subview.
- Added a busy indicator to search suggestions and results.
- Added animations for navigation, tabs, collapsible sections, and opening Edit Mode. Reduced motion also applies to the search indicator.
- Mute window and navigation sounds under **Misc**. [Beta changelog](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/CHANGELOG.md)
- Unit frames, group frames, castbars, and class resources use live rendering rules in their previews. This covers health and power loss, auras, status indicators, portraits, cast feedback, alternative mana, and detached resource bars. Hunter samples use the resource for their client. [Preview rendering](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/docs/PREVIEW_RUNTIME_RULES.md)
- **Colors** offers palettes for deuteranopia, protanopia, and tritanopia. These cover castbar, threat, and NPC colors and group dispel symbols.
- **Why is this hidden?** shows the settings and filters for selected aura lanes.
- The compact tint editor flags backgrounds with saved opacity of 0%. [Color and visibility tools](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/MidnightSimpleUnitFrames/State/MSUF_ProfileWorkbenchTools.lua)

### Unit frames, auras, castbars, and resources

- **Fonts.** Preview full names, abbreviations, and length limits. Each unit frame can override the shared format. Compatible Suite builds can add a **Nameplates** scope. [Beta changelog](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/CHANGELOG.md)
- **Party and Raid on Retail and Forever.** Frames update when membership changes during open-world combat, including the first Party invite while solo. Names and status text refresh for the new member. Protected layout changes apply after combat. [Beta 4 group changes](https://github.com/Mapkov2/MidnightSimpleUnitFrames/commit/b95219ca4dff5c599ef5acbb716a2b9b9d2973de)
- **Auras.** Brought back the native aura container changes tested in the 6.504 betas and reverted before 6.505. Containers can be reused or rebuilt if they stop updating. Unit buff lanes and dispel detection are handled separately. [Aura container runtime](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_Containers.lua)
- **Castbar transitions.** Improved cast-to-channel transitions, empower endings, and interrupt or cancellation feedback.
- **Castbar state.** Improved GCD spell tracking, restored range fade on released Focus castbars, and fixed cleanup for disabled Boss and Arena castbars. [Castbar changes](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/CHANGELOG.md)
- **Retail and Forever resource marks.** Under **Class Resources → Extras**, set a mark to the minimum cost of a learned spell by ID, link, or name. Costs refresh outside combat. [Resource marks](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/README.md)

### WoW Forever

| Area | Change since 6.511 |
| --- | --- |
| Character profiles | Profile assignment uses the full character identity, so characters with the same first name and different surnames can have separate assignments. Frame name display options already shipped in 6.50. |
| Eating and Drinking | Optional status text for Player, Target, Focus, Party, and Raid. Each scope starts off and has its own layout. Combined auras show “Drinking.” The text clears when the aura ends or its data is restricted. |
| Swing Timer | Updated cast and swing tracking. If native melee range is unavailable, both hands share one target check every 200 ms while needed. Duel interaction distance approximates weapon reach. |
| Portraits | Elite decoration follows the current target. The automatic dragon clears on players and when player classification is restricted. Readable NPC classifications can still show their configured decoration. |

[Forever changes in the beta changelog](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/CHANGELOG.md) · [Swing Timer code](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/MidnightSimpleUnitFrames/Game/Forever/SwingTimer.lua) · [Blizzard's Forever Swing Timer](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_SwingTimer/Blizzard_SwingTimer.lua)

## 2. Backend changes

### Profile storage and migration

- Save one profile store. Clear the separate `MSUF_DB` reference at logout so the active profile is saved once.
- V3 skips eligible default values at logout across 6,622 defined paths and fills them in on load. Matching defaults can follow future default changes.
- Keep explicit overrides such as `false`, `0`, and empty strings. Keep unknown keys.
- Keep the V1 and V2 readers and export schema 600.
- Validate saved masks and referenced tables before loading. Verify that compacted profiles can be rebuilt before saving. Save in full if compaction fails or the profile is ineligible.
- Keep a pre-upgrade account backup up to 8 MiB. Rejected or newer-format profiles share a separate 2 MiB recovery budget.
- Use `/msuf recovery list` to list recovery entries and storage use. Use `/msuf restorebackup` to start account profile and assignment recovery.
- Split defaults, repair, migration, binding, import, projection, and snapshots into separate modules.
- Repair media paths when handling profiles. Settle variants and sync before the final save. [Profile storage](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/docs/PROFILE_STORAGE.md) · [Recovery budget](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/docs/profile-recovery-budget.md)

### Menu and previews

- Controls that write to profiles declare their ID, profile path, scope, and how to apply the change.
- Generate simple setters from those declarations. Keep custom handlers for specialized controls.
- Use shared bindings for history, copy, reset, and refresh. Apply each change through the relevant system, such as unit frames, auras, or resources.
- Keep failed geometry, width, and frame updates queued for retry. [Menu control schema](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/docs/MENU_CONTROL_SCHEMA.md)
- Keep preview samples separate from live units. Use the same renderers for both.
- Use shared preview requests to start, pause, and clean up scenes. [Preview requests](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/docs/PREVIEW_REQUESTS.md)
- Use a smaller search index. Build FAQ and alias data on demand. Reuse pages and controls when switching scopes or slots where possible. [Search memory](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/docs/search-memory-budget.md)
- Split window controls, theme, page entry, and the preview dock. MapkoSkin and Suite handle their own skin integrations. [Skin integration](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/docs/MENU_SKIN_BRIDGE.md)

### Runtime and startup

- Split the unit-frame code for status, indicators, text and update queues, prediction, spawning, anchors, and width. Share text formatting and some rendering with group frames.
- Refresh names, colors, and status when a different member takes over the same unit token. [Unit-frame code](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/docs/uf-responsibility-split.md) · [Shared text formatting](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/docs/UNITFRAME_TEXT_CONTRACT.md)
- Separate group header settings, layout, and overlays. Prepare a hidden Party slot for the first open-world combat invite. Use native headers for member assignments and apply queued protected layout changes after combat. [Group runtime](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Runtime.lua)
- Split Auras3 host API, configuration signatures, identity changes, and world transitions.
- Share the skin renderer across both aura backends. Suite can compile, draw, and measure skins through a versioned API. Apply shared style changes made during combat together. [Icon skin API](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/docs/ICON_SKINS.md) · [Host API](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/MidnightSimpleUnitFrames/Runtime/MSUF_HostAPI.lua)
- Share one drag handler across Edit Mode frame types. Restore session and layout state on cancel or combat entry. Ignore late Gameplay drag releases after cancellation. [Edit Mode runtime](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/docs/EDITMODE_ENGINE_DELTA.md)
- Separate castbar settings and interrupt readiness from rendering. Split class resource construction, layout, and display modes. Optional Player HP uses the unit-frame engine. Timers with fixed deadlines share the scheduler. [Castbars](https://github.com/Mapkov2/MidnightSimpleUnitFrames/tree/classic-v7.0-beta6/MidnightSimpleUnitFrames/Castbars) · [Class resources](https://github.com/Mapkov2/MidnightSimpleUnitFrames/tree/classic-v7.0-beta6/MidnightSimpleUnitFrames/ClassPower) · [Scheduler](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/MidnightSimpleUnitFrames/Kernel/MSUF_Scheduler.lua)
- Load Options on demand, along with the compact in-game changelog. TOC conditions load the required language files and aura alias data at login. Other languages load from the bundled Locales addon when needed.
- Record file load order for all five clients in a generated lockfile. Generate the list of required compatibility globals. [6.511 TOC](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/v6.511/MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_Mainline.toc) · [7.0 TOC](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_Mainline.toc) · [Load order](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/tools/load-graph.lock)

## 3. Performance and testing

- Skip repeat aura alpha, portrait, and interrupt readiness writes when the display state is unchanged. [Runtime changes](https://github.com/Mapkov2/MidnightSimpleUnitFrames/commit/27a05e03f)
- Reuse widgets and previews where possible. Retry a failed unit update without rebuilding all unit settings. Run the Forever swing range fallback only while needed. [Menu changes](https://github.com/Mapkov2/MidnightSimpleUnitFrames/commit/768914da6) · [Unit update retries](https://github.com/Mapkov2/MidnightSimpleUnitFrames/commit/733f9d195)
- One offline Forever profile sample used **195,663 bytes** in full and **23,984 bytes** in V3, or **12.3%** of the full save size. Runtime profiles are still loaded as complete tables. [Profile storage measurements](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/docs/PROFILE_STORAGE.md#c11-byte-measurements-2026-10-24)
- Release checks cover client boot, historical profiles, decoder output, menu declarations, search targets, preview lifecycle, and missing or incorrectly loaded providers. The checks pin runtime versions and Blizzard sources. A separate audit tracks current Blizzard branch tips. [Release check](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/tools/release-check.md) · [Offline evidence](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/docs/RELEASE_EVIDENCE.md)
- Beta 6 records **17,419** profile-writing control declarations across the five client graphs. Shared controls count per client. [Schema report](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/tools/menu_schema_coverage_receipt.json)
- **16 targeted Beta 6 offline runs passed.** Coverage included profile migration and position adoption on all five clients, the workbench and roster updates on Retail and Forever, and Forever portraits and swing timers. Roster tests include the first Party invite and Raid membership changes. Migration fixtures include profiles through 6.510.
- Full release checks, live rendering, combat and taint behavior, and comparative in-game performance require separate validation.

## 4. Upgrading and returning to 6.5

- 7.0 carries over full 6.5x profiles and character assignments. Explicit choices such as disabled Forever mana regeneration indicators are kept.
- On first use of an upgraded layout, 7.0 waits for UI scale to settle before adopting the screen-height reference. Anchors and offsets are kept. [Upgrade behavior](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/docs/PROFILE_STORAGE.md#first-upgrade-from-65)

**Returning to 6.5**

1. Run `/msuf compatsave` in 7.0.
2. Log out or run `/reload` while still on 7.0. This saves all profiles in full, including inactive ones.
3. Install 6.5 after the save.

A profile that has never been active in 7.0 may move on first load in 6.5. The older version can read the screen-height reference before applying the final UI scale. [Downgrade steps and position limitation](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/docs/PROFILE_STORAGE.md#compatibility-and-downgrade-boundaries)

## 5. Already in stable 6.5x

| Version | Changes |
| --- | --- |
| 6.50 | Shared Core across clients, Arena Frames on supported clients, Pet Target and pet auras, Slanted Frames, texture layers, and more group layouts. |
| 6.501–6.503 | Fixes for delayed group names, boss resources, Raid membership, old group filters, resets, preview sorting, channels, and empower transitions. |
| 6.505–6.506 | Right-click focus in combat for supported Boss and Arena frames, class and NPC texture colors, Health and Power Chunks in previews, larger detached power bars, Forever Paladin blessing priorities, Spell Lock after Grimoire of Sacrifice, and late cast-stop fixes. |
| 6.507–6.509 | Correct health on dependent target frames, Forever mana regeneration and the five-second rule, optional castbar artwork and dark name panel, safer compressed imports, and drag position fixes. |
| 6.510–6.511 | Group health gradients and backgrounds, draggable Forever Swing Timers with layer previews, MapkoSkin preset, opacity in the compact picker, PvP flag updates, and optional open-world faction badges for Target and Focus. |

[Stable 6.5x changelog](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/v6.511/CHANGELOG.md)

## 6. Beta timeline

| Build | Changes |
| --- | --- |
| Beta 1 · Nov 7 | Icon Skins, profile workbench and import review, display variants, menu and preview changes, full 6.5x profile migration. |
| Beta 2 · Nov 8 | Menu sounds, round shadow preset, migration and position fixes, Dashboard and Forever fixes. Includes the 6.511 PvP changes. |
| Beta 3 · Nov 9 | Eating and Drinking status on Forever. |
| Beta 4 · Nov 9 | Party and Raid updates during open-world combat on Retail and Forever. |
| Beta 5 · Nov 9 | Shared melee range fallback for both hands on Forever. |
| Beta 6 · Nov 9 | Automatic elite portrait decoration fix on Forever when player classification is restricted. |

[Tagged beta changelog](https://github.com/Mapkov2/MidnightSimpleUnitFrames/blob/classic-v7.0-beta6/CHANGELOG.md)
