# Midnight Simple Unit Frames - 5.0 Beta 2

CurseForge changelog for May 13, 2026.

## Highlights

- Major font and media stability pass across unit frames, castbars, auras, group frames, status text and previews.
- New safer font application system with better internal Blizzard font handling and stronger fallbacks.
- Menu2 received many usability improvements, including live font previews, better refresh handling and cleaner settings pages.
- Boss unit frame preview now works directly from the Menu2 Boss page.
- Range Fade can now affect either the full frame or only the health bar.
- Unit and group previews are more accurate, with real portrait icons, better level indicator handling and safer font rendering.

## Fonts and Media

- Added a centralized safe font setter used across the addon.
- Font application now verifies that a font was actually applied.
- Added stronger fallback behavior when a font cannot be loaded.
- Improved internal font detection for Friz Quadrata, Arial Narrow, Morpheus and Skurri.
- Added better support for locale-specific Blizzard font paths.
- Added FontObject fallback support for Blizzard font objects.
- Added safer font path normalization and comparison.
- Added Expressway aliases for older and alternate MSUF font names.
- Improved handling for bundled Expressway fonts overriding internal-looking font paths.
- Added visual font cache prewarming to reduce first-use font detection issues.
- Font visual cache prewarming now avoids combat lockdown and retries later if needed.
- Font resolution avoids unsafe probing during combat lockdown.
- Added a debug probe for font troubleshooting.
- Internal MSUF fonts are no longer accidentally resolved through LibSharedMedia.
- Castbars, aura text, group frame text, status text and previews now use safe font application.
- Updated the bundled LibSharedMedia-3.0 file.
- Updated LibSharedMedia metadata and CurseForge project reference.
- Improved LibSharedMedia media list updates.
- Improved media path validation.
- Updated handling for the `None` sound entry.

## Unit Frames

- Added a dedicated runtime state for Boss unit frame preview.
- Boss frames can now be previewed from the Menu2 Boss page without enabling normal Edit Mode.
- Boss preview respects combat lockdown and resyncs after combat.
- Boss preview forces preview frames visible, fully opaque and interactive while active.
- Disabled Boss frames can still be shown for the Menu2 Boss page preview.
- Visibility drivers now remember the currently applied driver.
- Reduced redundant visibility-driver reapplication.
- Boss test mode now updates level indicator, portrait and castbar preview more reliably.
- Boss level text now respects the `showLevelIndicator` setting.
- Level indicator layout is reapplied after relevant Boss test updates.
- Boss portrait preview now uses fitting fallback artwork.
- Class portrait Boss preview uses Death Knight class preview data.
- Non-class Boss portrait preview uses a Boss icon fallback.

## Range Fade and Alpha

- Added a new Range Fade target mode: full frame or health bar only.
- Health-bar-only fade keeps text fully readable.
- Health-bar-only fade uses the layered alpha system.
- Edit Mode previews are protected from becoming too transparent.
- Fast Range Fade updates now support the health-bar-only mode.
- Target, Focus and Boss now share the new Range Fade layer selector in Menu2.
- Boss child Range Fade options only enable when Boss Range Fade is enabled.

## Castbars

- Castbar fonts now use the safe font system.
- Castbars prefer global font-key resolution before LibSharedMedia fallback.
- Internal fonts are preferred over LibSharedMedia fonts where appropriate.
- Improved fallback behavior for castbar fonts.
- Reworked the Global Castbars Menu2 layout.
- Textures, outline, empowered casts, name shortening, Focus Kick and Interrupt Ready settings are more compact.
- Spell name shortening now uses a clear On/Off button.
- Name shortening detail controls enable only when the feature is active.
- Empowered cast blink time enables only when empowered blinking is enabled.
- Interrupt Ready settings now enable and disable their controls based on active targets and auto-size state.
- Focus Kick settings are arranged more tightly.

## Auras

- Aura stack text now uses safe font application.
- Aura cooldown text now uses safe font application.
- Aura count initialization now uses the global font key.
- Auras2 global font refresh applies fonts more consistently.
- Auras2 Edit Mode cooldown previews now use safe fonts.
- Group frame aura cooldowns now use safe fonts.
- Group frame aura stack text now uses safe fonts.

## Group Frames

- Group frame names now use safe font application.
- Group frame health text now uses safe font application.
- Group frame power text now uses safe font application.
- Group frame status text now uses safe font application.
- Group frame render text now uses safe fonts.
- Group frame status-state effects now use safe fonts.
- Group Number display now falls back to the global font key.
- Group Number display now uses safe fonts.
- Added Expressway font aliases to group frame font normalization.
- Group Preview now uses safe fonts.
- Group Preview title now uses the accent color.
- Group Bars health color swatch now reflects the active bar mode.
- Group Bars color swatch is editable only when the current mode has one editable color.
- Added clearer hints for Global, Class Color and Health Gradient group bar modes.

## Menu2 Core

- Added a shared Menu2 refresh mechanism for active pages.
- Dropdowns now re-read their current values during refresh.
- Color buttons refresh immediately after color changes.
- Dashboard Edit Mode button now shows `On`, `Off` or `Off (Combat)`.
- Dashboard Edit Mode button now handles combat lock correctly.
- Menu2 now listens for Edit Mode state changes and updates the dashboard button.
- Menu2 syncs Boss preview when pages change.
- Boss preview is disabled when the Menu2 window closes.
- Boss preview is enabled again when the Boss page is shown.
- Menu page versions were bumped where layouts changed.

## Menu2 Fonts

- Font dropdown rows can now preview fonts by font key.
- Dropdown font previews resolve paths through the same safe font logic as the addon.
- Dropdown labels store and restore their default font.
- Global Fonts page now has a live preview string.
- The live font preview uses the selected font, size, outline and color.
- Font selection now handles global and scoped overrides more cleanly.
- LibSharedMedia font names are normalized better and duplicate entries are avoided.

## Menu2 Colors

- Advanced Colors page was reorganized for a tighter layout.
- Class color grid now uses dynamic column widths.
- Color swatches support custom label and button widths.
- Reset/action buttons now refresh the page after use.
- Bar Background Tint now has a clearer explanation.
- Bar Background controls were repositioned.
- Bar Colors were split into overlay controls and border/matching controls.
- Aggro Border and Purge Border colors are grouped more clearly.
- Power Bar Background matching label is clearer.
- Reset Bar Colors now refreshes the view immediately.

## Menu2 Class Resources

- Class Resources quick actions were moved into the header.
- `MSUF Edit Mode` now changes to `Exit Edit Mode` while Edit Mode is active.
- Added a direct button to the Colors page.
- Removed the old separate Quick Actions block.

## Menu2 Unit Pages and Previews

- Unit page preview title now uses the accent color.
- Boss unit page now automatically activates Boss preview.
- Boss preview is disabled when leaving the Boss page.
- Boss preview cleanup is delayed safely if combat is active.
- Unit Preview now uses real portrait icons instead of colored blocks with initials.
- Player, Target, TargetTarget, Focus, Boss and Pet previews now have dedicated portrait icons.
- Level indicator preview can now be smaller.
- Level indicator preview now sizes itself to the text instead of a fixed square.
- Level indicator preview aligns better beside the unit name.
- Preview handles now adapt to text width and height.

## Status and Text

- Status indicator text now uses safe font application.
- Boss test level text now respects `showLevelIndicator`.
- Text layouts refresh more reliably during Boss test updates.

## Classic Options Pages

- Classic Boss preview sync now understands the new Menu2 Boss page preview.
- Boss preview can now be active through Menu2 even when classic Edit Mode did not start it.
- Combat checks for Boss preview were consolidated.
- Classic options now use the new Boss preview state when available.

## Technical Stability

- Added more protected font and UI calls.
- Added more fallbacks for missing or late-created frames.
- Preview sync now retries shortly after activation to catch frames created later.
- More UI state is cached to avoid repeating the same work unnecessarily.
- Menu controls update enabled and disabled states more consistently.
- Font, preview and visibility code is more centralized and less fragile.

## Changed Areas

- Auras2
- Core
- Foundation
- GroupFrames
- LibSharedMedia-3.0
- Menu2
- Options
- Main runtime file
