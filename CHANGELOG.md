# Changelog

## 5.3 Beta 4 - 2026-05-17

### Highlights

- Added Focus Target frame support across unit settings, edit mode, menu previews, copy targets, text options, icons, and runtime refreshes.
- Further cleaned up Menu2 with refined cards, navigation, search, switch states, dashboard behavior, and input readability.
- Added Rounded Frames with per-surface controls for unit frames, group frames, bars, highlights, overlays, absorbs, and indicators.
- Prepared 5.3 Beta 4 as the release-ready beta validation build. This is not the stable 5.3 release.

### Performance

<!-- MSUF-AUTO-CHANGELOG:Performance:START -->
- Optimized range fade alpha repair.
- Reduced redundant HP text rendering when fast-path inputs have not changed.
- Reduced repeated group-frame health color and alpha work when the visual state is unchanged.
<!-- MSUF-AUTO-CHANGELOG:Performance:END -->

### Bugfixes

<!-- MSUF-AUTO-CHANGELOG:Bugfixes:START -->
- Fixed unit preview refresh upvalues.
- Fixed dashboard support clipping.
- Fixed menu clipping and improved input readability.
- Fixed collapsed Menu2 text badge visibility.
- Fixed group HP reverse order runtime behavior.
<!-- MSUF-AUTO-CHANGELOG:Bugfixes:END -->

### Changes / Improvements

<!-- MSUF-AUTO-CHANGELOG:Changes-Improvements:START -->
- Added heal prediction anchor modes.
- Polished Menu2 navigation submenu colors.
- Completed runtime locale coverage for the 5.3 beta line.
<!-- MSUF-AUTO-CHANGELOG:Changes-Improvements:END -->

### Release / Tooling

<!-- MSUF-AUTO-CHANGELOG:Release-Tooling:START -->
- Kept 5.3 on the beta channel for Beta 4 release-ready validation.
- Updated Perfy workflow notes for current repo-based instrumentation.
<!-- MSUF-AUTO-CHANGELOG:Release-Tooling:END -->

## 5.3 Beta 3 - 2026-05-17

### Highlights

- Added Focus Target frame support across unit settings, edit mode, menu previews, copy targets, text options, icons, and runtime refreshes.
- Restored the Menu2 dashboard preview and scroll behavior to the stable 5.3 Beta 2 layout.

### Bugfixes

- Fixed Menu2 text badges so they hide while cards are collapsed.
- Restored the Menu2 dashboard preview and scroll behavior to the 5.3 Beta 2 layout.

### Changes / Improvements

- Clarified unit frame alpha controls and matched them to the group frame layout.
- Bundled all 5.3 Beta changelog entries in the dashboard changelog.

## 5.3 Beta 2 - 2026-05-17

### Performance
- Defaulted rounded frame texture off so the feature has no active runtime callbacks while disabled.
- Reduced unnecessary group frame header rescans during rebuild and layout bursts.
- Reduced redundant castbar re-layout work when width-source geometry has not changed.

### Bugfixes
- Fixed rounded frame texture re-enable behavior after the module manager disables the feature.
- Fixed rounded frame integration for unit and group frame borders, power bars, mouseover highlights, dispel overlays, absorb bars, and indicators.
- Fixed group frame rounded visuals so mouseover and highlight state use the rounded edge instead of square overlays.

### Changes / Improvements
- Added Rounded Texture controls under Global Style > Bars with per-surface toggles, search coverage, localization, preview support, and a reload prompt.
- Added rounded mask media for the live unit/group frames and Menu2 preview.

## 5.3 Beta 1 - 2026-05-17

### Performance
- Improved performance for bar background rendering, text updates, and interrupt-ready handling.
- Added backend compatibility hardening across MSUF modules.
- Refactored core systems including font registration and recolor handling.

### Bugfixes
- Fixed detached unit frame outline border not working correctly.
- Fixed player aura helpful classification.
- Fixed Menu2 card enable states.
- Improved dynamic strata handling in Menu2.
- Defaulted tooltips back to Blizzard-controlled behavior for better compatibility.
- Fixed and refined raid group menu behavior.

### Changes / Improvements
- Added redesigned Menu2 card layout across unit, group, aura, indicator, bar, and advanced pages.
- Added more Menu2 cards and refined menu structure.
- Added new Menu2 search module and improved search/guidance text.
- Improved guidance for aura buff overrides.
- Improved guidance for name shortening overrides.
- Refined Menu2 switches and range fade controls.
- Added improved on/off switch visuals.
- Added raid group number display next to unit names.
- Updated localization/runtime locale handling.
- Added new UI/media assets for switches and rounded/superellipse visuals.

### Internal / Release
- Restricted the release workflow and privatized the release launcher.
- Removed old local publish helper scripts and release helper docs.

## 5.2 - 2026-05-16
