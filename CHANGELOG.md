# Changelog

## 5.2 Beta 2 - 2026-05-16

### Performance

<!-- MSUF-AUTO-CHANGELOG:Performance:START -->
- **Core Runtime**: Updated core runtime behavior (working tree; MSUF_FontRuntime.lua).
- **Unit Text**: Updated unit text rendering (working tree; MSUF_Text.lua).
- **General**: Updated addon behavior (working tree; MSUF_EM2_Popups.lua).
- **Foundation**: Updated addon behavior (working tree; MSUF_Defaults.lua).
- **Menu / Dashboard**: Updated menu, dashboard, or live apply behavior (working tree; MSUF_Menu2_Global.lua).
- **Menu / Dashboard**: Updated menu, dashboard, or live apply behavior (working tree; MSUF_Menu2_GroupPreview.lua).
- **Menu / Dashboard**: Updated menu, dashboard, or live apply behavior (working tree; MSUF_Menu2_UnitPreview.lua).
- **Menu / Dashboard**: Updated menu, dashboard, or live apply behavior (working tree; MSUF_Menu2_UnitSections.lua).
- **General**: Updated addon behavior (working tree; MidnightSimpleUnitFrames.lua).
- **Group Frames**: Updated Group Frame behavior (working tree; MSUF_GF_DB.lua).
<!-- MSUF-AUTO-CHANGELOG:Performance:END -->

### Bugfixes

<!-- MSUF-AUTO-CHANGELOG:Bugfixes:START -->
- **Unit Auras**: Fixed buff auras not updating in certain edge cases (6f0fd9f; Auras2/MSUF_A2_Core.lua).
- **Menu / Dashboard**: Updated menu, dashboard, or live apply behavior (working tree; MSUF_Menu2_AdvancedClassPower.lua).
- **Menu / Dashboard**: Updated menu, dashboard, or live apply behavior (working tree; MSUF_Menu2_Unit.lua).
- **Menu / Dashboard**: Updated menu, dashboard, or live apply behavior (working tree; MSUF_Menu2_GroupIndicators.lua).
- **Group Frames**: Updated Group Frame behavior (working tree; MSUF_GF_SpellIndicators_Data.lua).
<!-- MSUF-AUTO-CHANGELOG:Bugfixes:END -->

### Changes / Improvements

<!-- MSUF-AUTO-CHANGELOG:Changes-Improvements:START -->
- **Core Runtime**: Updated core runtime behavior (working tree; MSUF_Alpha.lua).
- **Menu / Dashboard**: Way better preview for GF UF menu (5b792da; Menu2/Pages/MSUF_Menu2_UnitPreview.lua, Menu2/Pages/MSUF_Menu2_UnitSections.lua).
- **Core Runtime, Unit Text, General**: More text options and better text preview (2dd1510; Core/MSUF_Alpha.lua, Core/MSUF_FontRuntime.lua, Core/MSUF_Text.lua +9 more).
<!-- MSUF-AUTO-CHANGELOG:Changes-Improvements:END -->

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
