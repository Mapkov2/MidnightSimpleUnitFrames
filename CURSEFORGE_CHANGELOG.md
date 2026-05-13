# Midnight Simple Unit Frames 5.0

## Highlights

- Rebuilt the MSUF options menu into a next-generation version of the existing menu experience.
- The menu keeps the familiar MSUF identity, but now feels more modern, polished, faster, and easier to navigate.
- Added a new dashboard, improved page structure, better search, smoother scrolling, window resizing, minimize/maximize controls, and Windows-style edge snapping.
- Added full Undo / Redo support for menu changes, including buttons, sliders, toggles, dropdowns, color controls, copy actions, reset actions, and preview edits.
- Added direct MSUF Edit Mode access from the menu for both Group Frames and Unit Frames.
- Added the same advanced preview system for Unit Frames that Group Frames already use, making layout, text, portraits, castbars, and positioning much easier to adjust directly from the menu.
- Added full localization for every WoW-supported locale:
  `enUS`, `enGB`, `deDE`, `esES`, `esMX`, `frFR`, `itIT`, `koKR`, `ptBR`, `ruRU`, `zhCN`, `zhTW`.

## Menu & Options

- Replaced the old options stack with the new modular Menu2 system.
- Added new dedicated pages for Unit Frames, Group Frames, Global Style, Fonts, Bars, Castbars, Gameplay, Class Power, Profiles, Layout, Auras, Indicators, and previews.
- Added a searchable menu with aliases, fuzzy matching, typo handling, and built-in FAQ-style navigation help.
- Added better profile management, Wago profile access, import/export tools, and recovery/reset actions.
- Added menu window controls for resizing, minimizing, maximizing/restoring, closing, saved window size, and edge snapping.
- Improved menu scaling, UI scale handling, scroll behavior, and layout consistency.
- Improved clipping and spacing across advanced, class power, castbar, group, unit, and font pages.
- Added `/rl` as a Reload UI shortcut.

## Unit Frames

- Added a new Unit Frame preview workflow based on the Group Frame preview system.
- Unit Frame layout, text, portraits, castbars, alpha behavior, status icons, and positioning can now be previewed and adjusted more comfortably from the menu.
- Added direct MSUF Edit Mode access from Unit Frame pages.
- Improved Unit Frame name shortening and truncation behavior.
- Improved portrait controls, including Blizzard class portrait support.
- Improved font, text, power bar, castbar, and status icon controls.
- Improved mouseover highlight behavior so borders stay attached correctly and no longer overlap text incorrectly.

## Group Frames

- Improved Group Frame range checking with a safer `UnitInRange` based path.
- Improved Group Frame menu structure with dedicated pages for Layout, Health & Text, Buffs & Debuffs, Indicators, and Preview.
- Improved Group Frame preview behavior and editing workflow.
- Improved Group Frame font handling and name truncation.
- Improved Group Frame mouseover highlight behavior.
- Improved Group Frame aura configuration, private aura handling, healer buffs, indicators, and layout controls.
- Removed obsolete Group Frame bridge code.

## Edit Mode

- Added menu-driven Edit Mode access for Unit Frames and Group Frames.
- Improved Edit Mode anchoring and frame positioning behavior.
- Added improved snap handling with visual guide lines while dragging.
- Added grid toggle support in the Edit Mode HUD.
- Improved Edit Mode help text, guided tour behavior, tooltips, and visual feedback.
- Improved Undo / Redo buttons in Edit Mode with new history icons.
- Improved tracking of drag, nudge, popup, castbar, aura, and unit-frame position changes.

## Localization

- Added full Menu2 localization coverage for all supported WoW languages.
- Moved runtime localization to a colder path for better performance.
- Added locale audit tooling to make missing translations easier to catch.
- Localized more menu labels, buttons, chat messages, tooltip text, help text, and recovery messages.

## Bug Fixes

- Fixed an edge case where auras could remain visible after they had expired.
- Fixed Blizzard class portrait mode when used together with class-colored portrait styling.
- Fixed Blizzard class portrait atlas coordinates so class icons no longer crop or distort incorrectly.
- Fixed private aura handling and Blizzard private aura anchor issues.
- Fixed mouseover highlight edge cases where borders could float, overlap text, or attach incorrectly.
- Fixed long-standing font menu issues.
- Fixed castbar spell name shortening behavior.
- Fixed several menu snapping, clipping, and layout edge cases.
- Fixed Edit Mode guided tour fallback behavior so raw locale keys are no longer shown.
- Fixed safer drag-stop handling for gameplay elements such as Combat Enter/Leave text.

## Improvements

- Improved font resolution, SharedMedia fallback handling, and safe font application.
- Added per-scope font controls for shared, unit-frame, and group-frame fonts.
- Improved Castbar preview handling and castbar load paths.
- Improved Gameplay options and their integration into the new menu.
- Improved Focus Interrupt Tracker preview handling.
- Improved Elite / Rare icon refresh behavior.
- Improved Addon Compartment and Minimap Button behavior.
- Improved UI scale, MSUF scale, and menu scale handling.
- Improved reset and recovery flows for profiles and positions.
- Updated TOC/interface support for current WoW versions.

## Cleanup

- Removed the old options system from the TOC.
- Removed old options files and legacy slash/search menu files.
- Removed unused presets.
- Removed obsolete bridge code.
- Removed temporary profiler files.
