# Changelog

## 5.2 Beta 6 - 2026-05-16

### Performance

<!-- MSUF-AUTO-CHANGELOG:Performance:START -->
- Fixed buff auras not updating in certain edge cases.
- Added more text positioning options for unit and group frames.
- Improved text container movement controls.
- Potential fix for bug with boss frame debuffs.
- Performance in interrupt module.
<!-- MSUF-AUTO-CHANGELOG:Performance:END -->

### Bugfixes

<!-- MSUF-AUTO-CHANGELOG:Bugfixes:START -->
- Added support for spell indicators and Blizzard rendering at the same time.
- Stopped tracking long raid buffs in Group Frames.
- Improved Group Frame aura filtering so long raid buffs are no longer tracked incorrectly.
- Fixed Group Frame mouseover behavior.
- Fixed some stuff with pinned preview.
- Pinned now fixed.
<!-- MSUF-AUTO-CHANGELOG:Bugfixes:END -->

### Changes / Improvements

<!-- MSUF-AUTO-CHANGELOG:Changes-Improvements:START -->
- Added class-colored bar background support across unit and group frames.
- Improved tooltip compatibility with other addons.
- Made click-casting on unit frames more robust.
- Added the new rested logo.
- Cleaned up menu test mode when leaving the menu.
- Reverted back to just showing the state of a window enable disable warning.
- Mini refactor of group frame effects file.
- Title clean up.
<!-- MSUF-AUTO-CHANGELOG:Changes-Improvements:END -->

## 5.2 Beta 5 - 2026-05-16

### Performance

- Improved overall addon performance and behavior.
- Improved combat-aware update handling across auras, power bars, borders, castbars, portraits, status indicators, unit frames, and group frames.
- Reduced unnecessary refresh work during combat, menu preview updates, aura rendering, and group frame effects.
- Improved aura and reminder behavior.
- Improved Group Frame range fade and highlight behavior.
- Improved menu and dashboard performance.
- Improved coalescing behavior in menus and related systems.
- Improved pass-through behavior.
- Improved preview update behavior for unit frames, group frames, and castbars so menu changes feel smoother.
- Improved spell indicator performance and gating between specs.
- Restored and polished the Class Power one-click installer flow.
- Improved text positioning options for unit frames and group frames.
- Improved text container movement controls.

### Bugfixes

- Fixed additional Midnight beta combat restrictions by avoiding unsafe updates while combat lockdown is active.
- Fixed buff auras not updating in certain edge cases.
- Fixed several group frame, aura preview, and menu issues that could cause inconsistent previews or stale UI state.
- Fixed Group Frame mouseover behavior.
- Improved aura reminder, border, castbar, status icon, and interrupt-ready handling for safer beta behavior.
- Made click-casting on unit frames more reliable.
- Improved tooltip compatibility with other addons, including TipTac.
- Stopped long raid buffs from being tracked incorrectly in Group Frames.
- Cleaned up menu test mode when leaving the menu.
- Reverted the window enable/disable warning to only show the current window state.

### Changes / Improvements

- Improved Group Frame and Unit Frame menu previews.
- Made Group Frame previews pinnable to make scrolling easier.
- Added a clearer UX for moving text containers together or individually.
- Added more text options and better text preview behavior.
- Added support for moving three text containers via X and Y positioning.
- Made it possible to use spell indicators and Blizzard rendering at the same time.
- Massively improved spell indicators, including restored Power Infusion tracking.
- Added Blessing of Freedom support.
- Added class-colored bar background support across unit frames and group frames.
- Added the new Rested symbol / logo for both Classic and Midnight-style rested indicators.
- Improved unit frame and group frame previews so layout, colors, castbars, and aura changes are easier to verify before applying.
- Improved advanced color, global, profile, group layout, group aura, group indicator, and unit settings pages.
- Improved the menu and dashboard experience with clearer, more user-friendly behavior.
- Improved Class Power setup and brought back the one-click installer.
- Improved group frame rendering, spell indicators, aura previews, and range/highlight behavior.
- Improved castbar preview behavior, boss castbar preview text, and castbar anchoring.
- Improved Edit Mode mover and popup behavior.
- Updated bundled changelog support so the in-game dashboard can show the 5.2 Beta notes.
- Prepared the addon for the 5.2 Beta release.

### Release / Tooling

- Updated the release notes shown in the in-game dashboard.
- Improved release tooling and changelog generation.
- Added changelog support for the 5.2 Beta release.
- Updated release helper documentation.

### Documentation

- Updated documentation and release notes.
- Added performance workflow documentation.

## 5.2 Beta 4 - 2026-05-16

### Performance

- Improved overall addon performance and behavior.
- Improved combat-aware update handling across auras, power bars, borders, castbars, portraits, status indicators, unit frames, and group frames.
- Reduced unnecessary refresh work during combat, menu preview updates, aura rendering, and group frame effects.
- Improved aura and reminder behavior.
- Improved Group Frame range fade and highlight behavior.
- Improved menu and dashboard performance.
- Improved coalescing behavior in menus and related systems.
- Improved pass-through behavior.
- Improved preview update behavior for unit frames, group frames, and castbars so menu changes feel smoother.
- Improved spell indicator performance and gating between specs.
- Restored and polished the Class Power one-click installer flow.
- Improved text positioning options for unit frames and group frames.
- Improved text container movement controls.

### Bugfixes

- Fixed additional Midnight beta combat restrictions by avoiding unsafe updates while combat lockdown is active.
- Fixed buff auras not updating in certain edge cases.
- Fixed several group frame, aura preview, and menu issues that could cause inconsistent previews or stale UI state.
- Fixed Group Frame mouseover behavior.
- Improved aura reminder, border, castbar, status icon, and interrupt-ready handling for safer beta behavior.
- Made click-casting on unit frames more reliable.
- Improved tooltip compatibility with other addons, including TipTac.
- Stopped long raid buffs from being tracked incorrectly in Group Frames.
- Cleaned up menu test mode when leaving the menu.
- Reverted the window enable/disable warning to only show the current window state.

### Changes / Improvements

- Improved Group Frame and Unit Frame menu previews.
- Made Group Frame previews pinnable to make scrolling easier.
- Added a clearer UX for moving text containers together or individually.
- Added more text options and better text preview behavior.
- Added support for moving three text containers via X and Y positioning.
- Made it possible to use spell indicators and Blizzard rendering at the same time.
- Massively improved spell indicators, including restored Power Infusion tracking.
- Added Blessing of Freedom support.
- Added class-colored bar background support across unit frames and group frames.
- Added the new Rested symbol / logo for both Classic and Midnight-style rested indicators.
- Improved unit frame and group frame previews so layout, colors, castbars, and aura changes are easier to verify before applying.
- Improved advanced color, global, profile, group layout, group aura, group indicator, and unit settings pages.
- Improved the menu and dashboard experience with clearer, more user-friendly behavior.
- Improved Class Power setup and brought back the one-click installer.
- Improved group frame rendering, spell indicators, aura previews, and range/highlight behavior.
- Improved castbar preview behavior, boss castbar preview text, and castbar anchoring.
- Improved Edit Mode mover and popup behavior.
- Updated bundled changelog support so the in-game dashboard can show the 5.2 Beta notes.
- Prepared the addon for the 5.2 Beta release.

### Release / Tooling

- Updated the release notes shown in the in-game dashboard.
- Improved release tooling and changelog generation.
- Added changelog support for the 5.2 Beta release.
- Updated release helper documentation.

### Documentation

- Updated documentation and release notes.
- Added performance workflow documentation.

## 5.1 Beta 4 - 2026-05-16

## 5.2 Beta 4 - 2026-05-16

### Performance

- Improved overall addon performance and behavior.
- Improved combat-aware update handling across auras, power bars, borders, castbars, portraits, status indicators, unit frames, and group frames.
- Reduced unnecessary refresh work during combat, menu preview updates, aura rendering, and group frame effects.
- Improved aura and reminder behavior.
- Improved Group Frame range fade and highlight behavior.
- Improved menu and dashboard performance.
- Improved coalescing behavior in menus and related systems.
- Improved pass-through behavior.
- Improved preview update behavior for unit frames, group frames, and castbars so menu changes feel smoother.
- Improved spell indicator performance and gating between specs.
- Restored and polished the Class Power one-click installer flow.
- Improved text positioning options for unit frames and group frames.
- Improved text container movement controls.

### Bugfixes

- Fixed additional Midnight beta combat restrictions by avoiding unsafe updates while combat lockdown is active.
- Fixed buff auras not updating in certain edge cases.
- Fixed several group frame, aura preview, and menu issues that could cause inconsistent previews or stale UI state.
- Fixed Group Frame mouseover behavior.
- Improved aura reminder, border, castbar, status icon, and interrupt-ready handling for safer beta behavior.
- Made click-casting on unit frames more reliable.
- Improved tooltip compatibility with other addons, including TipTac.
- Stopped long raid buffs from being tracked incorrectly in Group Frames.
- Cleaned up menu test mode when leaving the menu.
- Reverted the window enable/disable warning to only show the current window state.

### Changes / Improvements

- Improved Group Frame and Unit Frame menu previews.
- Made Group Frame previews pinnable to make scrolling easier.
- Added a clearer UX for moving text containers together or individually.
- Added more text options and better text preview behavior.
- Added support for moving three text containers via X and Y positioning.
- Made it possible to use spell indicators and Blizzard rendering at the same time.
- Massively improved spell indicators, including restored Power Infusion tracking.
- Added Blessing of Freedom support.
- Added class-colored bar background support across unit frames and group frames.
- Added the new Rested symbol / logo for both Classic and Midnight-style rested indicators.
- Improved unit frame and group frame previews so layout, colors, castbars, and aura changes are easier to verify before applying.
- Improved advanced color, global, profile, group layout, group aura, group indicator, and unit settings pages.
- Improved the menu and dashboard experience with clearer, more user-friendly behavior.
- Improved Class Power setup and brought back the one-click installer.
- Improved group frame rendering, spell indicators, aura previews, and range/highlight behavior.
- Improved castbar preview behavior, boss castbar preview text, and castbar anchoring.
- Improved Edit Mode mover and popup behavior.
- Updated bundled changelog support so the in-game dashboard can show the 5.2 Beta notes.
- Prepared the addon for the 5.2 Beta release.

### Release / Tooling

- Updated the release notes shown in the in-game dashboard.
- Improved release tooling and changelog generation.
- Added changelog support for the 5.2 Beta release.
- Updated release helper documentation.

### Documentation

- Updated documentation and release notes.
- Added performance workflow documentation.

## 5.2 Beta 3 - 2026-05-16

## 5.2 Beta 2 - 2026-05-16

### Performance

- Group Frames, Menu / Dashboard: Massive rework of spell indicators now performant and gated between speces (9443f77; GroupFrames/MSUF_GF_Effects.lua, GroupFrames/MSUF_GF_SpellIndicators.lua, Menu2/Pages/MSUF_Menu2_GroupIndicators.lua).

### Bugfixes

- Unit Auras: Fixed buff auras not updating in certain edge cases (6f0fd9f; Auras2/MSUF_A2_Core.lua).

### Changes / Improvements

- Menu / Dashboard: Way better preview for GF UF menu (5b792da; Menu2/Pages/MSUF_Menu2_UnitPreview.lua, Menu2/Pages/MSUF_Menu2_UnitSections.lua).
- Menu / Dashboard: More clearer container movement of text in ux . Together or individuell (dd30ddd; Menu2/Pages/MSUF_Menu2_GroupBars.lua, Menu2/Pages/MSUF_Menu2_GroupPreview.lua, Menu2/Pages/MSUF_Menu2_UnitPreview.lua +1 more).
- Group Frames: Made it possible to use spell indicator and blizzard rendering at the same time (b1dd6b3; GroupFrames/MSUF_GF_SpellIndicators.lua).
- Group Frames, Menu / Dashboard: Added blessing of freedom (a707802; GroupFrames/MSUF_GF_SpellIndicators_Data.lua, Menu2/Pages/MSUF_Menu2_GroupPreview.lua).
- Menu / Dashboard: Made it possible that group preview is pinned so scrolling is way easier (b594bdc; Menu2/MSUF_Menu2_Widgets.lua, Menu2/Pages/MSUF_Menu2_GroupPreview.lua, Menu2/Pages/MSUF_Menu2_UnitSections.lua).
- Group Frames: Massively improved spell indicator. For exmaple PI tracking is back (a3724e7; GroupFrames/MSUF_GF_Effects.lua, GroupFrames/MSUF_GF_SpellIndicators.lua, GroupFrames/MSUF_GF_SpellIndicators_Data.lua).
- Menu / Dashboard: Some stuff (ec459a1; Menu2/MSUF_Menu2_Widgets.lua, Menu2/Pages/MSUF_Menu2_GroupPreview.lua, Menu2/Pages/MSUF_Menu2_UnitSections.lua).
- Unit Auras, Core Runtime: Added better tooltip support for other addons. Ex. TipTac (084598a; Auras2/MSUF_A2_Core.lua, Core/MSUF_ChatAndTooltips.lua, MidnightSimpleUnitFrames.lua).
- Foundation, Group Frames, Menu / Dashboard: Added coalescence and some other menu stuff (6642696; Foundation/MSUF_Defaults.lua, GroupFrames/MSUF_GF_Auras.lua, GroupFrames/MSUF_GF_Effects.lua +3 more).
- Group Frames: Better pass through (40ed3a9; GroupFrames/MSUF_GF_Auras.lua).

### Release / Tooling

- Release / Tooling, Core Runtime, Unit Text: More text options and better text preview (2dd1510; CHANGELOG.md, Core/MSUF_Alpha.lua, Core/MSUF_FontRuntime.lua +13 more).
- Release / Tooling, Foundation, Group Frames: Way more text options for unitframe and groupframe. Can move now 3 container via x und y (b915bee; CHANGELOG.md, Foundation/MSUF_Changelog.lua, Foundation/MSUF_Defaults.lua +7 more).
- Release / Tooling, Menu / Dashboard: Made pinning possible (4095725; CHANGELOG.md, Foundation/MSUF_Changelog.lua, Menu2/MSUF_Menu2_Widgets.lua +2 more).
- Release / Tooling: Changelog for beta 2 (56fc05f; CHANGELOG.md, Foundation/MSUF_Changelog.lua, docs/RELEASE_HELPER.md +1 more).

## 5.2 Beta - 2026-05-16

## 5.2 Beta 1 - 2026-05-15

### Performance

- Improved combat-aware update handling across auras, power bars, borders, castbars, portraits, status indicators, unit frames, and group frames.
- Reduced unnecessary refresh work during combat, menu preview updates, aura rendering, and group frame effects.
- Improved preview update behavior for unit frames, group frames, and castbars so menu changes feel smoother.
- Restored and polished the one-click installer flow.

### Bugfixes

- Fixed several group frame, aura preview, and menu issues that could cause inconsistent previews or stale UI state.
- Fixed additional Midnight beta combat restrictions by avoiding unsafe updates while combat lockdown is active.
- Improved aura reminder, border, castbar, status icon, and interrupt-ready handling for safer beta behavior.
- Made click-casting on unit frames more reliable.

### Changes / Improvements

- Added class-colored bar background support across unit frames and group frames.
- Added the new Rested symbol for both Classic and Midnight-style rested indicators.
- Improved the menu and dashboard experience with clearer, more user-friendly behavior.
- Improved unit frame and group frame previews so layout, colors, castbars, and aura changes are easier to verify before applying.
- Improved advanced color, global, profile, group layout, group aura, group indicator, and unit settings pages.
- Improved Class Power setup and brought back the one-click installer.
- Improved group frame rendering, spell indicators, aura previews, and range/highlight behavior.
- Improved castbar preview behavior, boss castbar preview text, and castbar anchoring.
- Improved Edit Mode mover and popup behavior.
- Updated bundled changelog support so the in-game dashboard can show the 5.2 Beta 1 notes.
- Prepared the addon for the 5.2 Beta 1 release.
