# Midnight Simple Unit Frames - 5.0 Beta 3

## Added

- Added the new Menu2 options system and loaded it from the main addon TOC.
- Added `Menu2/MSUF_Menu2_Support.lua`.
- Added `Menu2/Pages/MSUF_Menu2_UnitPreview.lua` by moving the old unit preview options page into Menu2.
- Added a Menu2 dashboard with Quick Navigation, Active Profile, UI Scale, Wago Profiles, and Advanced recovery sections.
- Added Menu2 window controls for resizing, minimizing, maximizing/restoring, closing, saved window size, and edge snapping.
- Added a Menu2 search page with searchable controls, aliases, fuzzy matching, typo handling, and FAQ entries.
- Added Menu2 undo/redo history support with sessions, checkpoints, transactions, undo/redo stacks, and history buttons.
- Added undo/redo icon assets:
  - `Media/msuf_history_undo_red.png`
  - `Media/msuf_history_redo_green.png`
- Added `/rl` as a Reload UI slash command.
- Added a locale audit script at `tools/audit-locales.ps1`.
- Added Menu2 localization entries for deDE, esES, esMX, frFR, itIT, koKR, ptBR, ruRU, zhCN, and zhTW.
- Added an Edit Mode grid on/off setting with `Grid.GetEnabled`, `Grid.SetEnabled`, and `Grid.ToggleEnabled`.
- Added left-click grid toggling to the Edit Mode HUD grid control.
- Added `editModeGridEnabled = true` to Edit Mode defaults.

## Changed

- Updated the main addon TOC version from `5.0 Beta 2` to `5.0 Beta 3`.
- Updated the Castbars TOC interface list to include `120000`, `120001`, `120005`, and `120007`.
- Replaced the old options file stack in the main TOC with Menu2 page files.
- Updated the font menu to use the shared font resolver/safe font application path.
- Updated internal font defaults and font path resolution in `MidnightSimpleUnitFrames.lua`, `Foundation/MSUF_Libs.lua`, and group-frame font handling.
- Added per-scope font controls in the Menu2 Fonts page for shared, unit, and group-frame font settings.
- Updated Menu2 scaling helpers for MSUF frame scale, global UI scale, menu scale, and Blizzard UI scale restore/disable handling.
- Updated the Edit Mode HUD help/tour text and fallback handling.
- Updated Edit Mode undo/redo HUD buttons to use the new icon assets.
- Updated gameplay positioning code to create Menu2 history checkpoints/transactions for moved gameplay elements, including Combat Enter/Leave text, TotemFrame preview, and The First Dance tracker.
- Updated the Menu2 Unit Auras layout controls to use wider columns and reduce clipping.
- Updated several Menu2 labels/buttons to use localization via `M.Tr`.
- Updated Edit Mode grid rendering with safer canvas size fallback, resize rebuilds, dynamic visibility, shadow textures, and delayed rebuild after showing the grid.
- Changed the Edit Mode grid frame strata from `BACKGROUND` to `LOW`.
- Changed the default Edit Mode background opacity from `0.5` to `0.75`.
- Updated the Edit Mode grid HUD tooltip/help text to mention click-to-toggle.
- Added enabled/disabled coloring to the Edit Mode grid HUD control.
- Updated the anchor picker overlay with a styled top instruction panel, outlined instruction text, and clearer CTRL/no-frame warning messages.

## Fixed

- Fixed class portrait atlas texture coordinates for non-Rondo class portraits by preserving existing atlas texcoords.
- Fixed Edit Mode guided tour/help fallback behavior so raw locale keys are not shown.
- Fixed Menu2 clipping/layout issues in advanced, class power, castbar, group, and unit pages.
- Fixed safer drag-stop handling for Combat Enter/Leave text position saving.

## Removed

- Removed the old standalone search/slash menu files from the main TOC:
  - `Features/MSUF_Search.lua`
  - `Features/MidnightSimpleUnitFrames_SlashMenu.lua`
- Removed the old options file stack from the main TOC.
- Removed `Foundation/MSUF_Presets.lua`.
