# Changelog

## 5.58 - 2026-06-08

### Fixes

- Fixed missing-health text formatting for imported profiles with secret health values.

## 5.57 - 2026-06-04

### Edge Case Fixes

- Fixed a rare health-bar smoothing edge case where preserved HP color could leave a transparent strip while the bar was shrinking.
- Improved Blizzard party-frame fallback behavior when MSUF group frames are disabled, including arena and login/zone-change cases where Blizzard frames could be missing or briefly ghosted while solo.
- Hardened gameplay font application so profiles that reference missing SharedMedia or disabled addon fonts fall back safely instead of producing font asset errors.
- Refreshed group-frame range fade after instance, roster, and combat transitions so players who join or zone into an instance out of combat no longer stay faded as out of range until combat or `/reload`.
- Improved the missing buff scan for rare readable-aura edge cases.

### Compatibility and Safety

- Added a clear WoW 12.1 compatibility warning for MSUF 5.x users, with localized popup and chat messaging that points users to the current Alpha/Beta build for WoW 12.1.
- Kept secret-aura handling conservative while improving missing buff detection.

### Performance Notes

- Kept the new range recovery finite and event-driven instead of adding constant polling.
- Kept the missing buff scan on the existing cached aura path where possible.
- Kept the new font and Blizzard-frame safeguards on cold apply/login paths.

## 5.54 - 2026-05-27

### Critical Fixes

- Fixed Blizzard-rendered group-frame private auras reusing a stale Blizzard settings-change handler after instance or roster transitions.
- Fixed group-frame absorb and heal-absorb overlays drawing over the normal frame outline on party and raid frames.

## 5.53 - 2026-05-26

### Critical Fixes

- Fixed target, focus, and boss frame alpha/background recovery after combat so frames no longer need a target swap or reload to restore missing backgrounds.
- Fixed post-combat range fade handling so combat end restores cached alpha/background state instead of running an expensive range scan or full alpha refresh.
- Fixed group-frame range fade incorrectly fading the player/self frame by treating the player token and matching player GUID as always in range.
- Fixed stale absorb, shield, and heal-absorb overlays that could stay visible after the target no longer had an active absorb or heal absorb.
- Fixed group-frame secure-button recovery after login, reload, and party/raid changes so blank party or raid frames are reconciled without requiring `/reload`.
- Fixed CDM/custom-anchor login timing so unit frames keep their cached screen position until Blizzard EditMode or the configured anchor is available, instead of saving wrong UIParent offsets.
- Added a legacy no-op anchor for old Blizzard EditMode layouts that still reference `EssentialCooldownViewer_MSA_Container`, preventing repeated CDM SetPoint warnings after removing the old MSA dependency.

### Menu and Preview Fixes

- Fixed Buff Reminders checkboxes so the full label row is clickable again.
- Fixed Global Ignore List checkboxes and the per-unit override toggle so their click areas match the visible controls.
- Fixed Unit Auras scope/override clipping in compact or scaled menu layouts.
- Fixed Group Frame Aura Display Mode clipping by making the Blizzard aura routing and layering controls responsive in narrow menu layouts.
- Added a castbar size label to the Unit Frame preview so castbar width and height are visible while editing.

### Performance and Stability

- Kept alpha/range fixes cached and event-driven, avoiding broad post-combat frame sweeps.
- Kept absorb and heal-absorb cleanup on the existing prediction update paths with secret-safe positive-value checks.
- Improved post-login group-frame recovery through delayed live-frame reconciliation without adding constant polling.
- Kept late anchor recovery event-driven with a short, finite retry window only for profiles that actually use CDM, custom, or unit-frame anchors.

## 5.52 - 2026-05-23

### Critical Fixes

- Fixed the Dashboard `Edit frames` button so it no longer calls private Menu2 core helpers that are not visible from the dashboard module.
- Restored the dashboard Edit Mode toggle path while keeping the existing combat-lock handling and menu frame priority refresh.

## 5.51 - 2026-05-22

### Critical Fixes

- Fixed a critical edge case where selected debuff dispel-type filters could hide unrelated debuffs globally instead of only narrowing the dispellable-debuff exception.
- Fixed Aura Filters menu checkbox hitboxes and labels so the dispel and include toggles are easier to click and only active when they affect the current filter setup.

## 5.5 - 2026-05-22

### Highlights

- Reworked the Castbar Menu with dedicated live previews for Player, Target, Focus, and Boss castbars, including normal casts, channels, empowered casts, interrupt states, latency, spark, glow, icons, spell text, and cast time.
- Reworked the Unit Auras setup page around a clearer first-pass workflow with Essentials, Scope, presets, view modes, visible-unit toggles, reset actions, and a live aura preview.
- Fully reworked Dispel / Debuff Overlay and border highlights for Unit Frames and Group Frames around one visible Highlight Priority model.
- Added persistent Menu2 memory so the menu remembers opened cards, selected tabs, pinned previews, page state, color picker choices, and other recent selections.
- Added per-indicator icon pack selection for Unit Frame and Group Frame status indicators, including bundled UX Pro icons and support for external replacement packs.

### Menu2 and UX

- Improved Menu2 search so it also works as an ask-style field for questions like where to move frames, change fonts, adjust inline text colors, or disable group frames.
- Added broader English and German search handling, better direct-control ranking, and a first-use Search / Ask intro popover.
- Improved compact menu layouts for scaled or narrow UI setups so sliders, switches, edit boxes, previews, and layout toggles clamp cleanly instead of overlapping.
- Fixed a Menu2 preview helper load error caused by ambiguous Lua function-call syntax when creating rounded masks.
- Improved Group Frame disable/search wording so party and raid frame questions point directly to the `Use MSUF group frames` switch and Blizzard fallback dropdown.

### Castbars

- Rebuilt the Global Castbars page around a more accurate preview surface that follows runtime sizing, per-unit match-width behavior, fill direction, channel ticks, empower stages, latency, spark, glow, icon visibility, spell text, cast time, and interrupt shake.
- Added per-castbar time format controls for Player, Target, Focus, and Boss castbars.
- Improved castbar preview fidelity so menu previews line up with runtime width, height, text placement, icon placement, and cast-time rendering more closely.
- Split Boss Castbar preview/edit-mode behavior away from runtime boss cast handling.
- Reduced idle work in the castbar and interrupt-ready paths through tighter event gating, cached checks, and safer apply scheduling.

### Unit Frames and Group Frames

- Added Group Frame Blizzard fallback mode for layouts that should let Blizzard own the secure group frame path.
- Fixed Group Frame disabled fallback ownership so Blizzard only takes over when all MSUF group-frame scopes are off, while active MSUF party, raid, or mythic raid scopes keep Blizzard group frames hidden.
- Added status icon Advanced tabs with extended offsets, layer controls, reset actions, test mode, and preview actions.
- Added Group Frame options to hide name text while units are dead or offline.
- Moved heal prediction controls into the Bars pages and improved Group Frame heal prediction and absorb test rendering.
- Added a global Bar Outline Color for Unit Frames and Group Frames while keeping aggro, purge, dispel, and other indicator colors independent.
- Improved Unit Frame and Group Frame outline rendering so detached, active, preview, live, and pixel-snapped borders use consistent outside-outline behavior.
- Added configurable Target-of-Target inline text color modes: Auto, ToT Name Color, Target Name Color, NPC / Type Color, and Default Font Color.
- Improved Group Frame HP text handling, including reverse-order HP text, stable centered HP text, and font outline updates.
- Fixed Group Frames Buffs & Debuffs text-option layout so cooldown and stack text controls can expand instead of being clipped.

### Dispel, Debuff Overlay, and Highlights

- Rebuilt Unit Frame and Group Frame dispel priority around one visible Highlight Priority order: Dispel, Aggro, Purge, Boss Target, Target, and Focus.
- Migrated legacy Magic, Curse, Disease, Poison, and Bleed custom sorting into the single Dispel visual lane.
- Kept Dispel Border and Dispel Overlay independently configurable while sharing the same resolved debuff winner.
- Improved Any Debuff, Any Dispel Type, typed color mode, typed priority order, and Bleed handling so the highest-priority debuff is selected consistently.
- Added renderer-independent Group Frame dispel highlights so priority visuals still work when Blizzard owns aura icons.
- Improved cleanup for reused Group Frames so stale dispel, debuff, status, highlight, and aura state cannot leak into newly assigned units.

### Auras and Performance

- Improved Auras2 performance by caching dispel metadata, tracking structural aura changes, and avoiding repeated filter/sort work when aura structure and configuration are unchanged.
- Reduced Auras2 event and render overhead when unit aura modules are disabled, including stronger cleanup of inactive containers and private aura state.
- Improved handling for stealable buffs when mine-only, important-buff, and merged buff filters are active.
- Improved aura delta handling so priority-based dispel visuals rescan only when relevant aura data can change.
- Fixed Unit Frame range alpha background bleed and kept Sated aura threshold filters fresh after aura rule changes.
- Fixed a Range Fade protected-call warning by keeping the `CheckInteractDistance` fallback out of combat while preserving spell-based range checks and out-of-combat fallback behavior.

### Stability and Fixes

- Restored the previous MSUF keybind synchronization behavior and removed the newer account-wide `SaveBindings` / `LoadBindings` path to avoid a reload-only keyboard input edge case.
- Added `/msuf inputdebug` to help diagnose rare keyboard focus or input-capture issues.
- Reset keyboard input propagation when MSUF edit-mode popups, HUD panels, and picker overlays hide.
- Refreshed runtime systems after profile switch, reset, import, and external profile overwrite so frames, auras, class power, powerbar embeds, and portrait decorations update without stale state.
- Improved Class Power hidden-anchor handling and powerbar embed anchoring when class power is disabled or hidden.
- Improved portrait decoration layout recovery when portrait containers are rebuilt or their anchor points change.
- Reduced idle work in castbar, interrupt-ready, aura, range-fade, gameplay apply, target-swap, and boss castbar runtime paths.

### Localization and Internals

- Added German labels for the new Target-of-Target inline color options.
- Expanded localization coverage for Menu2 search, Castbar, Group Frame, and changelog strings.
- Split several large runtime and Menu2 files into focused modules for search data, dropdown helpers, preview helpers, widgets, dashboard, Group Frame effects, Auras2, Target-of-Target inline text, frame previews, totem previews, Class Power, and Boss Castbar previews.
- Updated release tooling so release packages and changelogs are generated more consistently.

## 5.41 - 2026-05-21

### Patch Release

- Restored the 5.32 MSUF keybind synchronization behavior and removed the new account-wide `SaveBindings` / `LoadBindings` path to avoid a reload-only keyboard input edge case where movement could become unresponsive until the game client was restarted.
- Added `/msuf inputdebug` to print movement bindings, keyboard focus, MSUF edit state, and visible keyboard-enabled frames when diagnosing rare input-capture issues.
- Reset keyboard input propagation when MSUF edit-mode popups, HUD panels, and picker overlays hide, so ESC-handled overlays cannot leave stale keyboard capture state behind.
- Improved Auras2 handling for stealable buffs when mine-only, important-buff, and merged buff filters are active.
- Refreshed runtime systems after profile switch, reset, import, and external profile overwrite so unit frames, auras, class power, powerbar embeds, and portrait decorations update without stale state.
- Hardened Group Frame unit-slot cleanup during roster changes so stale debuff, dispel, status, highlight, and displayed-aura state cannot bleed into the next unit assigned to the same secure button.
- Improved Class Power hidden-anchor handling and powerbar embed anchoring when class power is disabled or hidden.
- Improved portrait decoration layout recovery when portrait containers are rebuilt or their anchor points change.

## 5.4 - 2026-05-21

### Highlights

- Reworked the Castbar Menu with a dedicated live preview for Player, Target, Focus, and Boss castbars, including normal casts, channels, empowered casts, and interrupt preview states.
- Added persistent Menu2 memory so the menu remembers what you last opened or selected across rebuilds and reopening.
- Fully reworked Dispel / Debuff Overlay and border highlights for Unit Frames and Group Frames around one visible Highlight Priority model.

### Castbars

- Rebuilt the Global Castbars page around a more accurate preview surface that follows runtime sizing, per-unit match-width behavior, fill direction, channel ticks, empower stages, latency, spark, glow, icon visibility, spell text, cast time, and interrupt shake.
- Added per-castbar time format controls for Player, Target, Focus, and Boss castbars.
- Improved castbar preview fidelity for Player, Target, Focus, and Boss so menu previews line up with runtime width, height, text placement, icon placement, and cast-time rendering more closely.
- Split Boss Castbar preview/edit-mode behavior away from runtime boss cast handling.
- Reduced idle work in the castbar and interrupt-ready paths through tighter event gating, cached checks, and safer apply scheduling.

### Menu2 and UX

- Menu2 now persists accordion/card open states, pinned previews, dashboard panels, page selectors, tabs, selected scopes, color pickers, profile import/export choices, and other last-clicked menu state.
- Improved Menu2 search so the search field also works as an "ask" field for location-style questions such as where to move frames, change fonts, or adjust inline text colors.
- Added broader English and German question handling, better direct-control ranking, a first-use Search / Ask intro popover, and localized search coverage improvements.
- Reduced menu search and navigation overhead by cancelling unused background indexing, rebuilding search records only when needed, and skipping redundant title, subtitle, status-bar, navigation, and result refreshes.
- Improved compact menu layouts for scaled or narrow UI setups so sliders, switches, edit boxes, gameplay controls, group previews, and layout toggles clamp cleanly instead of overlapping.
- Added live party and raid previews while editing Group Frame bar settings without taking over the normal Edit Mode group preview state.
- Made MSUF keybinds account-wide and cleaned up quick setup styling for Class Bar actions.

### Dispel, Debuff Overlay, and Highlights

- Rebuilt Unit Frame and Group Frame dispel priority around one visible Highlight Priority order: Dispel, Aggro, Purge, Boss Target, Target, and Focus.
- Collapsed legacy Magic, Curse, Disease, Poison, and Bleed custom sorting into the single Dispel visual lane and migrated old overlay/debuff priority settings across saved profiles.
- Kept Dispel Border and Dispel Overlay independently enabled and configured while sharing the same resolved debuff winner, so border-only, overlay-only, and combined setups behave consistently.
- Improved Any Debuff, Any Dispel Type, typed color mode, typed priority order, and Bleed handling so the highest-priority debuff is selected consistently.
- Added renderer-independent Group Frame dispel highlights so MSUF can still draw priority visuals when Blizzard owns aura icons, while custom aura rendering uses the same priority path.
- Added separate effect layers for highlight borders, dispel overlays, and debuff stripes so active visual lanes stack predictably.
- Reduced redundant border, glow, overlay, color, reverse-fill, and status-bar updates with settings, aura-version, priority-signature, color-revision, and unit-guid cache guards.
- Improved cleanup for retired or reused Group Frames so stale dispel/debuff visuals cannot leak into newly assigned units.

### Unit Frames and Group Frames

- Added per-indicator icon pack selection for Unit Frame and Group Frame status indicators.
- Added status icon Advanced tabs with extended offsets, layer controls, reset actions, test mode, and preview actions.
- Added bundled UX Pro status icons and support for external `Interface\Icons` replacement packs.
- Improved status icon texture resolution across aura previews, aura rendering, healer buffs, spell indicators, focus kick icons, and dropdown previews.
- Added a separate Show Cooldown Swipe control for icon-style Group Frame Spell Indicators.
- Added Group Frame options to hide name text while units are dead or offline.
- Moved heal prediction controls into the Bars pages and improved Group Frame heal prediction / absorb test rendering.
- Added a global Bar Outline Color for Unit Frames and Group Frames while keeping aggro, purge, dispel, and other indicator colors independent.
- Improved Unit Frame and Group Frame outline rendering so detached, active, preview, live, and pixel-snapped borders use consistent outside-outline behavior.
- Added configurable Target-of-Target inline text color modes: Auto, ToT Name Color, Target Name Color, NPC / Type Color, and Default Font Color.
- Improved Target preview rendering and runtime Target-of-Target inline color resolution for class colors, target-name colors, NPC reaction colors, NPC type colors, and default font colors.
- Added Group Frame Blizzard fallback mode for layouts that should let Blizzard own the secure group frame path.
- Improved Group Frame HP text handling, including reverse-order HP text, stable centered HP text, and font outline updates when face and size stay unchanged.
- Fixed Unit Frame range alpha background bleed and kept Sated aura threshold filters fresh after aura rule changes.

### Auras and Performance

- Improved Auras2 performance by caching dispel metadata, tracking structural aura changes with epochs, and avoiding repeated filter/sort work when aura structure and configuration are unchanged.
- Reduced Auras2 event and render overhead when the feature or all unit aura modules are disabled, including harder cleanup of inactive containers and private aura state.
- Improved aura delta handling for added, updated, and removed debuffs so priority-based dispel visuals rescan only when relevant aura data can change.
- Improved range-fade stability and cost by repairing unchanged layered alpha less often while still clearing stale fade state when range becomes unknown.
- Refined low-risk runtime paths for aura commits, target-swap visuals, gameplay apply scheduling, crosshair target callbacks, and boss castbar event registration.

### Localization

- Added German labels for the new Target-of-Target inline color options.
- Expanded runtime localization coverage for the new Menu2 search, Castbar, Group Frame, and changelog strings.

### Under the Hood

- Refactored the Group Frame effects runtime into focused modules for text, aura effects, range/threat, events, cleanup, highlights, status/offline handling, frame cache, and tooltip/mouseover behavior.
- Refactored Auras2 into clearer cache, collection, icon, layout, Masque, cooldown-text, render, reminder, event, and edit-mode responsibilities.
- Split Target-of-Target inline widget logic into `Core/MSUF_UFCore_ToTInline.lua`.
- Split preview/test-mode frame behavior into `Core/MSUF_FramePreview.lua`.
- Split Blizzard Totem Preview handling into `Features/MSUF_Gameplay_TotemPreview.lua`.
- Split ClassPower alternate mana and Balance Druid prediction into dedicated modules.
- Split Boss Castbar preview handling into `MidnightSimpleUnitFrames_Castbars/Modules/BossCastbars_Preview.lua`.
- Preserved public Group Frame APIs and diagnostic wrappers while moving hot-path work behind smaller internal modules.
- Updated release tooling and Perfy documentation so temporary instrumented builds stay separate from normal release packages.

## 5.32 - 2026-05-18

### Patch Release

- Fixed a group-frame Spell Indicators crash when linked aura rules, such as Restoration Druid Symbiotic Relationship, checked the scan ownership cache before it was in local scope.
- Bundled the 5.31 and 5.3 release notes with this hotfix so the in-game changelog keeps the full recent release context.

## 5.31 - 2026-05-18

### Patch Release

- Fixed a critical group-frame Preserve HP color crash in Midnight when background frame colors are returned as secret numbers.
- Reverted the delayed range-fade alpha repair performance optimization so layered range alpha is repaired immediately again while range state is unchanged.
- Bundled the full 5.3 release notes with this patch release so the in-game changelog still includes the complete 5.3 release.

## 5.3 - 2026-05-18

### Highlights

- Added Focus Target as a new unit frame with its own settings, Edit Mode mover, Menu2 preview, copy targets, text options, status icons, and secure runtime refresh.
- Added Rounded Frames through Global Style > Bars > Rounded Texture, with separate controls for unit frames, group frames, power bars, and mouseover highlights.
- Reworked Dispel Border / Glow so it can be useful for every class, including classes without a defensive dispel.
- Continued the Menu2 redesign with cleaner cards, better navigation, stronger search coverage, and clearer profile/menu workflows.

### Focus Target

- Added a dedicated Focus Target frame that appears when Focus is enabled and your focus has a target.
- Integrated Focus Target into unit-frame defaults, secure show/hide state, live refreshes, Edit Mode, preview rendering, copy/apply actions, import/export handling, alpha controls, text settings, portraits, and indicators.
- Kept Focus Target lightweight by default: it has health/name support like other unit frames, while power is off by default and castbars/auras remain out of scope for this frame.
- Added Focus Target help/search text and menu safeguards so the frame clearly explains when Focus must be enabled first.

### Rounded Frames

- Added rounded mask media and runtime support for unit frames, group frames, health bars, power bars, detached power bars, absorbs, overlays, highlights, and preview samples.
- Added a master Rounded Texture switch plus per-surface toggles for Unit frames, Group frames, Power bars, and Mouseover highlights.
- Integrated rounded edges with active borders, mouseover highlights, dispel highlights, aggro/target/focus highlights, group-frame overlays, and layer ordering so rounded frames no longer fall back to square highlight visuals.
- Added preview, search coverage, localization, reload guidance, and safe rebuild behavior for rounded frame texture changes.
- Rounded Frames stay disabled by default and avoid their runtime path while disabled.

### Dispel Border / Glow

- Added Dispel Border detection modes: Dispellable by me, Any dispel-type debuff, and Any debuff.
- Dispel Border / Glow can now support all classes: healers can keep class-aware dispel detection, while non-dispel classes can still highlight debuff types or any debuff without losing the debuff list.
- Added MSUF Dispel Border / Glow for Blizzard aura mode, so Blizzard can keep rendering aura icons while MSUF still draws the configured dispel border and glow.
- Added scope-aware group-frame behavior for dispel colors, glow options, scan state, and highlight priority, so party/raid scopes can keep the correct visual rules.
- Improved dispel color resolution, secret-safe aura scanning, debuff filtering, and highlight cache behavior for Magic, Curse, Poison, Disease, and generic debuff states.

### Menu2

- Expanded the card-based layout across unit frames, group frames, auras, indicators, bars, colors, gameplay, profiles, class power, and advanced pages.
- Improved the dashboard preview, collapsed text badges, clipping behavior, input readability, submenu colors, scroll behavior, dynamic strata handling, and card enable states.
- Added a larger search module with better guidance for auras, name shortening, rounded frames, Focus Target, Unit Auras, Blizzard aura modes, and profile workflows.
- Refined switches, range fade controls, profile UX, FAQ text, and warnings around Blizzard-managed buffs/debuffs.

### Other Improvements

- Added heal prediction anchor modes.
- Added more status icon anchor options.
- Added player aggro border support.
- Added a global Preserve HP color sync option for unit-frame Bar Background Tint and improved Dark Mode missing-health background handling.
- Added raid group number display next to unit names.
- Improved Unit Auras debuff filters, including Include dispellable debuffs and the Magic, Curse, Poison, and Disease toggles.
- Defaulted tooltips back to Blizzard-controlled behavior for better compatibility.

### Performance and Stability

- Improved bar background rendering, text update paths, interrupt-ready handling, range fade alpha repair, and castbar width-source layout checks.
- Reduced unnecessary group-frame header rescans and repeated group health color/alpha work.
- Hardened backend namespace compatibility and imported media handling.
- Fixed detached unit-frame outline borders, player aura helpful classification, group HP reverse order, aura tooltip hover sizing, menu preview refreshes, dashboard support clipping, and layer ordering consistency.

### Localization

- Completed direct locale coverage for enUS, enGB, deDE, frFR, esES, esMX, itIT, koKR, ptBR, ruRU, zhCN, and zhTW.
- Moved locale coverage into real locale files and updated runtime localization coverage for the 5.3 feature set.

## 5.2 - 2026-05-16
