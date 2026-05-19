# Changelog

## 5.4 Beta 6 - 2026-05-20

### Beta Release

- Reworked Unit Frame and Group Frame dispel priority resolution so Magic, Curse, Disease, Poison, Bleed, generic dispel, aggro, purge, and boss-target lanes stay independent instead of collapsing to the first matching type.
- Kept Dispel Border and Dispel Overlay as separate visual lanes with their own trigger, priority, color, and refresh state so live option changes no longer reuse a stale border winner for the overlay.
- Added settings-serial, aura-version, priority-signature, color-revision, and unit-guid cache guards around dispel scans so repeated refreshes are cheaper without keeping stale aura colors or stale priority winners.
- Improved Any Debuff and Any Dispel Type handling so typed color mode and typed priority order can still select the correct highest-priority debuff, including Bleed.
- Added Bleed support to the group-frame dispel color curve for the currently observed Bleed ids.
- Improved Dispel Overlay behavior when Blizzard/native aura rendering is enabled: Blizzard can still own the aura icon/border path while MSUF keeps the health-bar overlay active.
- Reduced redundant glow, overlay, color, reverse-fill, and status-bar updates for Unit Frame and Group Frame dispel visuals while keeping secret-value handling safe.
- Improved aura delta handling for added, updated, and removed debuffs so priority-based dispel visuals rescan only when the tracked winner or priority-relevant data can change.
- Added Perfy workflow documentation for temporary instrumented test zips, including the rule that `MSUF_PerfyHook.lua` stays out of normal beta releases.
- Note: the Dispel system is still work in progress and will continue to be tuned in upcoming beta builds.

## 5.4 Beta 5 - 2026-05-19

### Beta Release

- Refactored the Group Frame effects runtime into clear internal modules instead of keeping text, aura effects, range/threat, events, cleanup, highlights, status/offline handling, frame cache, and tooltip/mouseover behavior in one large file.
- Refactored Auras2 into clearer cache, collection, icon, layout, Masque, cooldown-text, render, reminder, event, and edit-mode responsibilities instead of concentrating aura state, icon reuse, filtering, layout, and rendering in the core/render files.
- Added `Auras2/MSUF_A2_Cache.lua` for aura cache ownership, full scans, delta updates, invalidation, and aura table pooling.
- Added `Auras2/MSUF_A2_Collect.lua` for zero-allocation helpful/harmful aura collection paths and sorted/unsorted list preparation.
- Added `Auras2/MSUF_A2_Icons.lua` for icon pool ownership, acquire/release behavior, stack/timer/pandemic application, and icon cleanup.
- Added `Auras2/MSUF_A2_Layout.lua` for aura icon positioning, row/column layout, and hide-unused behavior.
- Kept `Auras2/MSUF_A2_Masque.lua` and `Auras2/MSUF_A2_CooldownText.lua` as dedicated render subsystems so Masque skinning and cooldown text updates stay out of the main aura render orchestration.
- Refactored `Auras2/MSUF_A2_Render.lua` around render orchestration, shared buff/debuff commit handling, icon commit/layout boundaries, and preview/runtime separation.
- Refactored `Core/MSUF_UnitframeCore.lua` by moving Target-of-Target inline widget logic into `Core/MSUF_UFCore_ToTInline.lua`, while keeping public runtime behavior and wrappers compatible.
- Refactored the main frame backbone by moving preview/test-mode frame behavior into `Core/MSUF_FramePreview.lua`, keeping `MidnightSimpleUnitFrames.lua` focused more on public orchestration and real runtime frame setup.
- Refactored Gameplay support by moving Blizzard Totem Preview handling into `Features/MSUF_Gameplay_TotemPreview.lua`, while keeping one public `ns.MSUF_RequestGameplayApply` path and apply coalescing.
- Refactored ClassPower specialty logic by moving alternate mana handling into `ClassPower/MSUF_CP_AltMana.lua` and Balance Druid prediction into `ClassPower/MSUF_CP_BalanceDruid.lua`, leaving the controller closer to orchestration.
- Refactored Boss Castbar preview handling into `MidnightSimpleUnitFrames_Castbars/Modules/BossCastbars_Preview.lua`, separating edit-mode/fake-cast preview behavior from runtime boss cast handling.
- Reduced `GroupFrames/MSUF_GF_Effects.lua` to the Health, Power, overlay, and visual-dispatch orchestration path, making the remaining hot-path code easier to review and safer to profile.
- Added `GroupFrames/MSUF_GF_Text.lua` for compiled text-slot handling, text dirty queues, and text retire cleanup.
- Added `GroupFrames/MSUF_GF_AuraEffects.lua` for `UNIT_AURA` dispatch, dispel scanning, dispel overlay/glow, debuff stripe handling, and aura-effect refresh state.
- Added `GroupFrames/MSUF_GF_RangeThreat.lua` for range fade, layered alpha handling, threat state, and the related lightweight event dispatch.
- Added `GroupFrames/MSUF_GF_Events.lua` for unit-event masks, global event registration, event lifecycle, and roster/target/focus event routing.
- Added `GroupFrames/MSUF_GF_Highlight.lua` for highlight configuration resolution, border styling, quick border updates, and target indicator rendering.
- Added `GroupFrames/MSUF_GF_StatusOffline.lua` for AFK, DND, Dead, Ghost, and delayed offline-hide state handling.
- Added `GroupFrames/MSUF_GF_FrameCache.lua` for cold-path per-frame configuration caching, event-bit calculation, and cache invalidation triggers.
- Added `GroupFrames/MSUF_GF_TooltipMouseover.lua` for mouseover highlight styling, tooltip throttling, and Group Frame init hooks.
- Added `GroupFrames/MSUF_GF_Cleanup.lua` so retired or hidden Group Frames release tooltip, text, aura, range, and offline-hide state through one cleanup entry point.
- Preserved existing Group Frame public APIs and diagnostic wrappers, including update, aura, highlight, status, target, overlay, and frame-cache entry points.
- Fixed a Group Frame target indicator risk by moving its secret-safe `UnitIsUnit` boolean normalization into the new highlight module instead of relying on a missing local helper.
- Kept the Group Frame aura hot path conservative: no extra aura scans, no extra `UnitAura` or `C_UnitAuras` calls, no broader unit-event registration, and no new timer or `OnUpdate` loop.
- Kept the frame-cache split on the cold apply/refresh path so cache construction is easier to maintain without adding work to frequent Health, Power, Aura, or Range events.
- Updated the TOC load order so highlight, status, aura-effect, and range/threat helpers bind before the hot-path effects orchestrator, while the cold frame cache still loads after the shared effects exports it needs.
- Verified the refactor with `luac -p` across project-owned Lua files and `git diff --check`.

## 5.4 Beta 3 - 2026-05-19

### Beta Release

- Added status icon Advanced tabs for Unit Frame and Group Frame status indicators, including extended offsets, layer controls, reset, test mode, and preview actions.
- Added status icon pack discovery from addon `Icons` folders and bundled the `UX Pro` status icon pack under `MidnightSimpleUnitFrames\Icons\UXPro`.
- Added support for external `Interface\Icons` replacement packs by resolving accessible spell and aura FileDataIDs back to icon paths before rendering.
- Fixed Group Frame status icon menu clipping around the Placement layer controls.
- Improved status icon texture handling across aura previews, aura rendering, healer buffs, spell indicators, focus kick icons, and dropdown previews so replacement packs are used consistently.
- Improved Group Frame heal prediction and absorb test mode so Bars test rendering updates overlay bars without unnecessary live prediction reads while out of combat.
- Refactored low-risk runtime paths for aura commits, target-swap visuals, gameplay apply scheduling, crosshair target callbacks, and boss castbar event registration.

## 5.4 Beta 2 - 2026-05-19

### Beta Release

- Added per-indicator icon pack selection for Unit Frame and Group Frame status indicators.
- Added Group Frame options to hide name text while units are dead or offline.
- Moved heal prediction controls into the Bars pages so Unit Frame and Group Frame bar configuration is grouped consistently.
- Added a global Bar Outline Color for Unit Frames and Group Frames while keeping aggro, purge, dispel, and other indicator colors independent.
- Improved Unit Frame bar outlines so detached, active, and pixel-snapped outline borders render consistently.
- Improved Group Frame bar outline rendering so preview and live frames use the same outside-outline behavior as Unit Frames.
- Fixed Unit Frame range alpha background bleed when layered alpha state changes.
- Fixed Sated aura threshold filters so aura rule changes stay fresh.
- Fixed a Group Frame preview upvalue warning.

## 5.4 Beta - 2026-05-18

### Beta Release

- Added persistent Menu2 memory so accordion/card open states, pinned previews, dashboard panels, page selectors, scopes, color selectors, and profile import/export choices survive menu rebuilds and reopening.
- Improved Auras2 performance by caching dispel metadata, tracking structural aura changes with epochs, and avoiding repeated filter/sort work when aura structure and configuration are unchanged.
- Reduced Auras2 event/render overhead when the feature or all unit aura modules are disabled, including harder cleanup of inactive containers and private aura state.
- Improved range-fade stability and cost by repairing unchanged layered alpha less often while still clearing stale fade state when range becomes unknown.
- Expanded Menu2 search coverage for toggle-style questions such as enable, disable, show, hide, turn on, and turn off.

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
