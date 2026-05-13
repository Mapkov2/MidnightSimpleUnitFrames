# Midnight Simple Unit Frames - 5.0 Beta 3

Verified from the local Git commits made in the last ~12 hours on May 13, 2026, plus the current working-tree changes in Edit Mode and defaults files.

## Added

- Added the new Menu2 options system and loaded it from the main TOC.
- Added `Menu2/MSUF_Menu2_Support.lua`.
- Added `Menu2/Pages/MSUF_Menu2_UnitPreview.lua` by moving the old unit preview options page into Menu2.
- Added a Menu2 dashboard page with Quick Navigation, Active Profile, UI Scale, Wago Profiles, and Advanced recovery sections.
- Added Menu2 window controls for resizing, minimizing, maximizing/restoring, closing, saved window size, and edge snapping.
- Added a Menu2 search page with registered searchable controls, aliases, fuzzy matching, typo handling, and FAQ entries.
- Added Menu2 undo/redo history support with history sessions, checkpoints, transactions, undo/redo stacks, and history buttons.
- Added undo/redo icon assets:
  - `Media/msuf_history_undo_red.png`
  - `Media/msuf_history_redo_green.png`
- Added `/rl` as a Reload UI slash command.
- Added a locale audit script at `tools/audit-locales.ps1`.
- Added Menu2 localization entries for:
  - deDE, esES, esMX, frFR, itIT, koKR, ptBR, ruRU, zhCN, zhTW

## Changed

- Updated the main addon TOC version from `5.0 Beta 2` to `5.0 Beta 3`.
- Updated the Castbars TOC interface line to include `120000`, `120001`, `120005`, and `120007`.
- Removed the old options files from the main TOC and now load the Menu2 page files instead.
- Removed the old standalone search/slash menu files from the main TOC:
  - `Features/MSUF_Search.lua`
  - `Features/MidnightSimpleUnitFrames_SlashMenu.lua`
- Removed `Foundation/MSUF_Presets.lua`.
- Updated the font menu to use the shared font resolver/safe font application path.
- Updated internal font defaults and font path resolution in `MidnightSimpleUnitFrames.lua`, `Foundation/MSUF_Libs.lua`, and group-frame font handling.
- Added per-scope font controls in the Menu2 Fonts page for shared, unit, and group-frame font settings.
- Updated Menu2 scaling helpers for MSUF frame scale, global UI scale, menu scale, and Blizzard UI scale restore/disable handling.
- Updated the Edit Mode HUD help/tour text and fallback handling.
- Updated Edit Mode undo/redo HUD buttons to use the new icon assets.
- Updated gameplay positioning code to create Menu2 history checkpoints/transactions for moved gameplay elements, including Combat Enter/Leave text, TotemFrame preview, and The First Dance tracker.
- Updated the Menu2 Unit Auras layout controls to use wider columns and reduce clipping.
- Updated several Menu2 labels/buttons to use localization via `M.Tr`.

## Fixed

- Fixed class portrait atlas texture coordinates for non-Rondo class portraits by preserving existing atlas texcoords.
- Fixed Edit Mode guided tour/help fallback behavior so raw locale keys are not shown.
- Fixed Menu2 clipping/layout issues in the changed pages from commit `b0a56e5`.
- Fixed safer drag-stop handling for Combat Enter/Leave text position saving.

## Current Working Tree Changes

- Updated Edit Mode grid rendering in `EditMode2/MSUF_EM2_Layout.lua`:
  - added safer canvas size fallback,
  - rebuilt grid lines on size changes,
  - adjusted grid/crosshair visibility based on background opacity,
  - added shadow textures for grid lines, center crosshair, and center pips,
  - changed the grid frame strata from `BACKGROUND` to `LOW`,
  - refreshed grid lines after changing background opacity,
  - added `Grid.GetEnabled`, `Grid.SetEnabled`, and `Grid.ToggleEnabled`.
- Updated the Edit Mode HUD in `EditMode2/MSUF_EM2_HUD.lua`:
  - added left-click toggling for the grid control,
  - updated the grid tooltip/help text to mention click-to-toggle,
  - added visual enabled/disabled coloring for the grid control.
- Updated the anchor picker overlay in `EditMode2/MSUF_EM2_Movers.lua`:
  - added a top panel behind the anchor picker instructions,
  - moved the instruction text into that panel,
  - changed the instruction text styling to use outlined font text,
  - updated the CTRL-required and no-named-frame warning messages.
- Updated Edit Mode defaults in `Foundation/MSUF_Defaults.lua`:
  - added `editModeGridEnabled = true`,
  - changed default `editModeBgAlpha` from `0.5` to `0.75`.
