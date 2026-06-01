# Midnight Simple Unit Frames Changelog

## 6.0 Preview 2 - 2026-06-01

### Preview Channel
- Local preview package for the second 6.0 Menu2/Edit Mode test build.
- Version metadata is prepared as `6.0-preview2` for local install testing.
- This remains a preview-only build and is not a stable public release.

### Menu2 Architecture
- Split the large Unit Frame page into focused lazy-loaded sections for text, range fade, alpha, and frame visuals.
- Split group-frame preview rendering, handles, rounded masks, text focus, zoom, pan, and specs into dedicated Menu2 modules.
- Added shared Menu2 theme tokens and control gates so dense settings pages can share consistent enabled, disabled, locked, and preview-only states.
- Added group specs and advanced aura specs modules so repeated dropdown, texture, and aura option data is maintained in one place.
- Reworked Menu2 XML load order for the new page, preview, search, and theme modules.

### Search And Guidance
- Rebuilt Menu2 search around smaller keyword, alias, routing, and FAQ catalog modules.
- Added FAQ search coverage for common setup, layout, unit, group, aura, visibility, and troubleshooting questions.
- Reduced the large generated search data surface by moving reusable query text and routing behavior into focused files.

### Preview And Interaction
- Added reusable zoom and pan helpers for unit and group previews.
- Moved unit-preview runtime and rendering work out of the view shell so preview refreshes are easier to reason about.
- Added dedicated group-preview handle rendering and text-focus helpers for clearer direct manipulation.
- Improved live preview/status rendering for selected unit-frame and group-frame controls.

### Edit Mode
- Split Edit Mode popup scale, castbar, and aura popup behavior into dedicated modules.
- Reworked the tooltip edit popup to use the Menu2 visual style, larger action layout, draggable placement, and shared popup scaling.
- Refined Edit Mode HUD, focus, layout, and mover behavior around the slimmer popup model.
- Kept edit popups closer to the same visual and interaction language as Menu2.

### Runtime And Defaults
- Added the unit-frame range-fade runtime element and defaulted range fade settings for supported unit frames.
- Removed old dispel overlay/state load paths that no longer match the paused 6.0 aura backend.
- Removed the old Auras3 group-filtering runtime path while keeping the remaining menu/model surfaces.
- Cleaned group indicator, status, visual, spell-registry, metadata, and preview paths around the current 6.0 runtime shape.
- Updated unit-frame alpha, border, prediction, text, metadata, config, and dispatch paths for the new range/visual split.

### Visual Assets And Docs
- Added Menu2 HIG and checkbox preview mockups under `docs/`.
- Added checkbox edge/fill media assets used by the updated Menu2 checkbox treatment.
- Refreshed the minimap icon asset for the preview package.

### Fixes
- Fixed range-fade defaults so existing profiles receive the expected per-unit fallback values.
- Fixed tooltip edit popup placement and resizing behavior for the new Edit Mode popup style.
- Fixed Menu2 preview module boundaries so rendering helpers can be reused without rebuilding full page shells.
- Fixed stale load references to removed aura and dispel runtime files.

## 6.0 Preview 1 - 2026-05-31

### Preview Channel
- Local preview package for 6.0 Menu2/Edit Mode testing.
- This build is not a public release and is not published to GitHub, CurseForge, or Wago.
- Version metadata is prepared as `6.0-preview1` for local install testing.

### Menu2 Design System
- Added a shared Menu2/Edit Mode visual language for buttons, pills, steppers, sliders, section headers, popups, and inspector surfaces.
- Added shared material tokens for shell, rail, host, card, popup, focus, guide, and warning layers.
- Added calmer glass-style popup and card materials with controlled gradients, softer borders, and more consistent depth.
- Added subtle gradient treatment to high-value controls and active states while keeping inactive surfaces quiet.
- Unified widget spacing, compact control sizing, hitboxes, hover states, disabled states, and active-state rendering.
- Reworked checkbox/toggle visuals so they read cleaner against the dark Menu2 surface and do not overpower labels.
- Reduced strong border noise across dense settings pages and moved emphasis to active, hovered, and focused controls.
- Removed redundant left-nav explanatory tooltips; retained tooltips only where they explain hidden, dangerous, or non-obvious behavior.

### Menu2 Focus, Motion, And Feedback
- Added a reusable dropdown focus veil so open dropdowns keep attention on the active choice while the rest of the menu subtly recedes.
- Added smoother dropdown fade behavior and fixed close-state flicker from the global dropdown focus handling.
- Added a shared motion layer for short, purposeful transitions: dropdown fade, accordion open/close, popup fade/scale, control hover, and command feedback.
- Added Menu2 header inline feedback for commands, avoiding unnecessary chat spam and interruptive popups.
- Added inline feedback for page reset, group reset, copy actions, copy category selection, profile export/import, edit-mode toggles, layout changes, undo, redo, session reset, and combat-locked actions.
- Added command failure feedback for captured Menu2 actions.
- Added safer menu-state migration so old auto-opened text sections from earlier Edit Mode focus requests do not keep reopening.

### Progressive Disclosure
- Reworked large Unit Frame and Group Frame sections so common controls appear first and advanced geometry or detail controls stay behind collapsible sections.
- Reduced closed-section clutter by hiding most badges unless the section is open or the badge is decision-critical.
- Reworked Group Frame layout setup around direct geometry controls.
- Removed the redundant extra Layout Intent section.
- Renamed advanced layout details to Geometry so users can tune exact size/spacing when needed.
- Kept status summaries near active/open sections instead of showing every setting as a permanent pill.

### Menu2 Preview And Direct Manipulation
- Connected Menu2 controls to preview/edit focus for unit frame text, power bars, castbars, frame layout, and group-frame layers.
- Hovering relevant Menu2 controls can now highlight the matching preview element instead of forcing users to guess which setting affects which visual part.
- Selecting or editing text slots keeps the preview focus aligned with Name, HP Text, Power Text, left/center/right slots, and related position controls.
- Slider and stepper changes refresh the preview immediately where the runtime supports live preview updates.
- Copy and reset actions now provide visible confirmation in the Menu2 status bar.
- Fixed Menu2 focus requests so browsing pages while Edit Mode is active no longer forces the Text section open unless the user explicitly targeted text from Edit Mode.

### Edit Mode UX
- Reconnected Edit Mode with Unit Frame and Group Frame previews so dummy previews and real edit handles use the same selection and positioning state.
- Restored group-frame dummy previews for party, raid, and mythic raid scopes, including behavior when the player is in a real raid group.
- Reworked Edit Mode popups into the Menu2 visual style with shared popup materials, steppers, pills, copy-to actions, reset placement, and close buttons.
- Added a compact inspector-style popup for active frames with X/Y/Width/Height steppers and cleaner actions.
- Added Copy To support for position and size in the Edit Mode popup.
- Kept detached powerbar editing available in the Edit Mode popup while removing redundant Name/HP/Power text editing from the popup.
- Added popup parity between unit frames and group frames so both use the same visual language and interaction model.
- Reworked tooltip edit preview handling so tooltip positioning can be adjusted through a small popup instead of relying only on old drag text.
- Removed loud selection highlighting from Edit Mode and replaced it with calmer focus/dimming behavior where appropriate.
- Kept snap highlight behavior but removed/trimmed unstable snap-guide positioning that caused jitter or visual misalignment.
- Stabilized the Edit Mode inspector so it no longer jumps around while the user is working.

### Group Frame Menu And Preview
- Reworked Group Frame top controls to reduce redundancy between scope selection and geometry details.
- Added clearer scope switching feedback for Party, Raid, and Mythic Raid without adding explanatory tooltips.
- Improved Group Frame preview/dummy anchoring so preview blocks match live frame positioning more closely.
- Fixed raid-frame anchor positioning issues where the raid dummy preview could align differently from the live frame anchor.
- Added preview/live parity work for raid and party layouts, including correct behavior while already inside a real raid group.
- Kept group-frame geometry in its own section so size, spacing, growth, and columns stay easy to tune.
- Cleaned closed Group Frame section headers so they show title and important state only, reducing badge clutter.

### Unit Frame Menu
- Reworked Unit Frame top actions for consistent Copy To and Edit Mode behavior.
- Added unit-frame copy feedback for selected target and category changes.
- Added Edit Mode on/off feedback from unit-frame pages.
- Improved live text-slot preview focus for Name, HP, and Power text controls.
- Fixed mismatches between the blue dummy overlay and the real unit-frame preview for selected preview elements.
- Removed range-fade controls from per-unit transparency pages after the 6.0 runtime cleanup moved away from that per-unit UI path.

### Performance And Runtime Tweaks
- Continued reducing hot-path work in the 6.0 Unit Frame Core by moving more behavior into compiled specs and targeted dirty masks.
- Reduced disabled-feature overhead so inactive text, visual, indicator, aura, range, and status systems avoid unnecessary event and refresh work.
- Trimmed repeated frame updates in text, prediction, health, power, status, group, and castbar preview paths.
- Split large unit-frame runtime responsibilities into smaller element modules to keep hot updates focused and easier to maintain.
- Removed unused bundled runtime libraries from the packaged addon path where the rewritten 6.0 runtime no longer depends on them.
- Reduced group-frame preview/live refresh amplification by using scope-aware refreshes and preserving dirty-mask intent through public shims.
- Reduced menu rebuild churn by preserving persistent menu state and closing auto-focused sections only when focus was not explicitly requested.
- Added wider use of direct references and guarded calls instead of repeated global/table lookups on frequent paths.
- Improved combat-lock feedback and deferred apply handling so blocked actions return quickly and explain the state inline.
- Kept preview-only work out of live runtime paths where possible, especially for group-frame and unit-frame edit previews.

### Fixes
- Fixed dropdown focus animation closing with a dark/light/dark flicker.
- Fixed group-frame raid preview positioning where the dummy preview anchor did not match the live raid-frame anchor.
- Fixed Text sections reopening automatically while navigating Menu2 during Edit Mode.
- Fixed Edit Mode snap-guide instability that caused visible shaking during drag.
- Fixed Edit Mode popup layout and removed old popup paths that no longer matched the Menu2 style.
- Fixed copy/reset/edit actions that previously changed state without clear UI confirmation.

## 6.0 Alpha 4 - 2026-05-29

### Runtime Kernel
- Added compiled per-frame hot-event states for health, power, connection, aura, and prediction/absorb dispatch.
- Stored direct update function references for hot and generic event lists, reducing repeated element table and update-key lookups during frame events.
- Added a generic hot-event tail so future elements registered to hot events still run without requiring switch edits.
- Reused unit identity/state reads within a single dispatch token to avoid duplicate UnitExists/UnitIsConnected/UnitIsPlayer style calls when multiple elements handle the same event.
- Fixed combined unit/unitless event owner tracking so `both` registrations stay unitless-capable through unregister/rebuild paths.

## 6.0 Alpha 3 - 2026-05-29

### Aura Backend Pause
- Removed the live 6.0 Auras3 runtime while Blizzard's Midnight aura refactor is still in flux.
- Removed custom unit-frame aura rendering, group aura cache snapshots, group custom aura lanes, Blizzard/private aura anchoring, and aura cooldown text runtime management.
- Kept Auras3 profile data, menu surfaces, edit-mode handles, and unit/group preview configuration so user settings can survive until a new supported backend is ready.
- Group aura-dependent spell indicators, custom corner aura indicators, dispel overlays, and dispel aura borders no longer register live aura runtime work while the backend is disabled.

## 6.0 Alpha 2 - 2026-05-27

### Release Channel
- Alpha-only release for CurseForge and Wago.
- Wago stability must be `alpha`; this build is not stable.
- CurseForge release type must be `alpha`.
- The 6.0 line is still a complete backend rewrite from the 5.54/5.x runtime stack, with group frames, unit frame core, Auras3, and castbar integration running through the new backend.

### Backend Rewrite Follow-Up
- Folded the separate castbar addon tree into the core addon package so the 6.0 backend ships as one coordinated addon instead of a split runtime.
- Kept the castbar runtime, boss castbar preview, channel ticks, empower handling, focus kick state, and player castbar bridge in the core package load order.
- Trimmed unit frame hot paths in health, prediction, text formatting, group aura cache, core dispatch, and frame factory code.
- Reduced disabled-feature overhead further after Alpha 1, especially around group aura cache scans and repeated unit-frame update paths.
- Added `MSUF_UF_DispelState` as the shared state resolver for dispel overlays, glow, border, and group-frame visual consumers.

### Fixes
- Fixed absorb, heal prediction, and heal absorb placement so bars use safer resolved anchors and avoid secret-value comparison failures.
- Restored scoped dispel glow and aggro border behavior for the rewritten visual backend.
- Fixed group frame visual config paths for dispel borders, glow, and indicator consumers.
- Optimized 2D portrait refresh so portrait visuals avoid unnecessary rebuild work when the visual state did not change.
- Fixed texture/runtime handling used by bars and prediction previews after the backend rewrite.

### Group Frame Preview
- Added the same preview controls used by Unit Frame Preview: zoom buttons, `Fit`, `1:1`, `Ctrl + mouse wheel` zoom, and canvas panning.
- Added `Ctrl + left-drag`, right-drag, and middle-drag panning for the group preview canvas.
- Kept handle dragging stable while the preview refreshes by freezing preview scale during drag.
- Updated preview hints and tooltips so zoom, pan, arrow nudging, Shift nudging, and Ctrl nudging are visible in the UI.

### Menu And Aura Editing
- Split Auras3 options into scoped menu sections instead of one overloaded page.
- Updated menu search data and search indexing for the new aura and group-frame sections.
- Improved group aura menu bindings for the rewritten group backend.

### Known Alpha Notes
- This is still an alpha build. Test profile migration, group frame layout, castbars, aura rendering, dispel overlays, aggro borders, prediction bars, click-casting, Clique, and Wago/CurseForge channel handling.
- The release tag for this build is `6.0-alpha2`; alpha tags are expected to publish to Wago as `alpha`, never `stable`.

## 6.0 Alpha 1 - 2026-05-27

### Release Channel
- Published as the first 6.0 alpha build.
- This build is intentionally an alpha because it replaces large runtime systems from 5.53 with the new UnitFrame Core, Auras3, and rewritten Group Frame backend.
- GitHub Actions now derives the release channel from the tag name. Tags containing `alpha` resolve to Wago `alpha` and CurseForge `alpha`.
- The release workflow now has a hard alpha-channel assertion so alpha tags fail the workflow instead of silently publishing as beta or release.
- Local Wago and CurseForge publish scripts now also resolve alpha tags to alpha when run outside GitHub Actions.

### 6.0 Backend Rewrite
- Replaced the old 5.53 standalone runtime-heavy unit frame architecture with the shared `UnitFrames/Core` runtime.
- Added a central element registration model for health, power, text, prediction, alpha, borders, status, auras, class power, castbar bridges, and group-frame-specific elements.
- Added per-frame active-element tracking so disabled elements do not register events and do not execute in combat hot paths.
- Added a compiled spec model that converts profile/menu configuration into runtime specs consumed by shared core elements.
- Added scoped apply masks so small menu changes can refresh only the affected runtime elements.
- Added dirty masks for geometry, visuals, fonts, colors, borders, layout, and auras.
- Reduced broad refresh behavior from the 5.53 group frame stack by routing updates through targeted masks where possible.
- Added cached group-frame compiled specs per scope, with per-button patching only for unit-specific fields.
- Added explicit cold-path behavior for disabled group features so inactive text, indicators, overlays, and aura systems do not stay active during combat.
- Added group-frame name cold-path handling: group names are updated out of combat and kept fixed during combat.
- Added static health-color cold-path handling so class color, custom color, dark mode, and other static colors do not re-run on every health event.
- Kept gradient health coloring dynamic only when the selected mode requires runtime health-based color changes.
- Added direct group-frame range fade event handling without a ticker.
- Group range fade now uses only the required WoW events: `UNIT_PHASE`, `UNIT_IN_RANGE_UPDATE`, `UNIT_CTR_OPTIONS`, and `UNIT_OTHER_PARTY_CHANGED`.
- Removed the old multi-timer group header scan ladder and replaced it with immediate scan plus one delayed fallback.
- Added header-child attribute hook handling so secure header unit assignment is detected reliably after dungeon/zone roster changes.
- Fixed party/raid visibility separation so party frames do not duplicate raid frames in a 5-player party, and raid frames only show when actually in raid.
- Added stronger zone/dungeon roster recovery through `PLAYER_ENTERING_WORLD`, roster updates, difficulty changes, and zone changes.
- Added out-of-combat deferred group runtime rebuild handling for secure-frame-safe behavior.
- Kept secure header layout changes out of combat.

### Auras3 Runtime
- Replaced Auras2 with Auras3 for unit frame and group frame custom aura rendering.
- Added shared Auras3 runtime for player, target, focus, boss, and group frames.
- Added Auras3 lane-based custom buff, debuff, and defensive/external rendering.
- Added aura runtime config generation so menu changes invalidate cached aura layout only when needed.
- Added reusable aura slot buffers instead of allocating fresh slot tables for every scan.
- Added UNIT_AURA delta handling for added, updated, and removed aura instance IDs.
- Kept full aura scan fallback for full updates or unknown delta payloads.
- Added native Blizzard aura routing for group frames.
- Blizzard-rendered group aura blocks are now eventless on the addon side and are only applied/refreshed when configuration or layout changes.
- Added per-aura lane filtering with support for Blizzard API filters, blacklist categories, custom lane limits, and defensive aura routing.
- Added custom aura cooldown text and stack text support through shared Auras3 logic.
- Added secret-safe cooldown duration handling by passing duration objects directly to Blizzard cooldown APIs.
- Removed all `pcall` usage from Auras3 runtime, cooldown text, Masque registration, and Auras3 menu refresh callbacks.
- Auras3 now uses guarded direct calls instead of defensive `pcall` wrappers.
- Masque integration for group custom aura icons is still supported without `pcall`.
- Added cooldown text color bucket support with safer handling for secret values.
- Added Auras3 edit-mode integration and live preview support.
- Added group preview awareness for custom aura handles and Blizzard-locked aura blocks.

### Group Frame Rewrite
- Replaced the 5.53 `GroupFrames/MSUF_GF_*` runtime stack with a smaller backend built on `UnitFrames/Core/Group`.
- Added group-frame config compiler that maps old profile keys to shared core specs.
- Added group-frame adapter for secure header children and UF core attachment.
- Added group-frame header manager for party, raid, and mythic raid scopes.
- Added group-frame runtime manager for rebuilds, visibility, dirty refreshes, name updates, combat deferral, and Blizzard ownership.
- Added group-frame Blizzard ownership module for party and raid fallback behavior.
- Added group-frame aura cache module with reusable per-frame snapshots.
- Added group-frame aura cache incremental update support.
- Added group-frame aura snapshot maps by spell ID and aura name for fast indicator lookup.
- Added aura snapshot source maps for player-cast helpful and harmful auras.
- Added group visuals module for target/focus highlights, health fade, dispel overlay, debuff stripe, and border aura state.
- Added group status module for range fade and status runtime events.
- Added group indicators module for corner indicators and spell indicators.
- Added group Auras3/Blizzard aura bridge module.
- Added private aura bridge for group frames.
- Added spell registry and spell-indicator data under the new group core.
- Added group frame scan tracking without writing unsafe data to secure child userdata.
- Added group frame untracking cleanup for retired header children.
- Added click-casting support for group frames.
- Group frames now register into Blizzard `_G.ClickCastFrames` when the scope toggle is enabled.
- Group frames now register with Clique when Clique is available and the game is out of combat.
- Added `Layout > General > Click casting / Clique` toggle.
- Click-casting is enabled by default for group scopes.
- Click-casting registration refreshes after combat lockdown ends.
- Disabling click-casting for a scope unregisters those frames from ClickCastFrames and Clique where possible.

### Group Frame Performance
- Added true cold-path behavior for disabled group features.
- Disabled raid markers, role icons, status icons, spell indicators, corner indicators, overlays, aura lanes, power text, HP text, and name text do not keep hot event handlers active.
- Group names do not update during combat.
- Static health colors do not update on every health event.
- Spell indicators compile only the active player spec.
- Spell indicators skip the item loop when no watched IDs or names exist in the aura snapshot.
- Group aura cache registers for `UNIT_AURA` only when an enabled feature needs it.
- Custom Auras3 lanes use incremental updates where possible.
- Blizzard-rendered group auras have no addon-side UNIT_AURA loop.
- Group range fade does not use tickers.
- Group frame refresh functions now preserve kind/mask information across public global shims.
- Font changes refresh font/text elements only.
- Border changes refresh border and dependent visual elements only.
- Aura changes refresh aura-related elements only.
- Visual changes avoid forcing full button re-apply where a dirty mask is sufficient.
- Compiled group specs are cached by scope and invalidated on config/profile/menu changes.
- Per-frame spec patching only updates the fields that vary by unit: unit token, key, role, and effective power height.
- Removed large 5.53-style scan amplification for common hot events.

### Group Frame Frontend
- Added redesigned group frame menu pages split by task: layout, bars/text, indicators/status, auras, and preview.
- Added scope selector for Party, Raid, and Mythic Raid.
- Added scope reset and copy controls.
- Added live group frame preview with layer handles.
- Added locked Blizzard aura preview block to show native aura placement without pretending it can be dragged.
- Added preview layer toggles for buffs, debuffs, externals, Blizzard, status, spell indicators, private auras, cooldown/stack text, and text.
- Added preview drag handles for custom layer positions.
- Added keyboard nudge behavior for selected preview handles.
- Added `Show Preview` section.
- Added `General`, `Layout`, `Sorting`, `Frame Scaling`, `Transparency`, `Anchoring`, and `Tooltip` sections.
- Added `Health Colors`, `Bars`, `Power Bar`, `Text`, `Dispel Overlay`, `Debuff Stripe`, and `Range Fade` sections.
- Added `Indicators`, `Status Icons`, `Spell Indicators`, and `Corner Indicators` sections.
- Added group aura configuration for Buffs, Debuffs, Defensives, and Private Auras.
- Added Auras3 group aura display controls for Blizzard/custom renderer routing.
- Added per-aura-type Blizzard routing toggles for buffs, debuffs, dispels, defensives, and private auras.
- Added Blizzard aura icon size, organization, strata, frame-level offset, cooldown text, dispel highlight, and private aura layering options.
- Added custom aura lane controls for icon count, size, growth, wrap, spacing, offsets, cooldown text, and stack text.
- Added aura blacklist/filter UI paths through the Auras3 menu model.
- Added spell indicator editor with per-spec spell lists, placement controls, effect controls, cooldown text, and drag sorting.
- Added corner indicator editor with custom spell ID support.
- Added better section state hints when scopes are disabled or features are inactive.

### Unit Frame Core
- Added shared unit frame factory/core stack for player, target, focus, pet, target-of-target, boss, and group frames.
- Added shared health element with group-aware static color optimization.
- Added shared power element.
- Added shared text runtime for name, health, power, and layout handling.
- Added shared prediction element for incoming heals, absorbs, and heal absorbs.
- Added shared visual elements for alpha, borders, portraits, and auras.
- Added status indicator elements under the shared core.
- Added bridges for castbars and class power.
- Added load-condition support through shared element logic.
- Added global event dispatch tables and runtime update pathways for shared UF elements.
- Added direct handling for secret values in prediction logic without `pcall`.
- Fixed secret-number comparison errors in prediction by avoiding Lua-side comparisons where values can be secret.

### Menu2 / Frontend Rewrite
- Added Menu2 pages for the new UnitFrame Core and group frame workflow.
- Added redesigned global pages for bars, fonts, colors, castbars, misc, profiles, and support.
- Added shared widget helpers for dense settings pages.
- Added search data and search indexing for new menu pages.
- Added preview helpers for unit and group frame previews.
- Added group-frame frontend bindings to backend refresh masks.
- Added profile-aware menu writes so scope changes invalidate only the needed runtime parts.
- Added frontend gates so disabled scopes show clear state and activation controls.
- Added copy/reset controls for group frame categories.
- Added integrated MSUF Edit Mode entry points from group pages.

### Castbars
- Added 6.0 castbar backend integration path.
- Castbar code is now routed through the new core/bridge structure.
- Added global castbar menu integration in Menu2.
- Added castbar texture and visual settings through global menu pages.
- Kept castbars as a separate addon folder where the source layout requires it.

### Blizzard Integration
- Added Blizzard group-frame ownership handling for the new group runtime.
- Added fallback mode behavior for when MSUF group frame scopes are disabled.
- Added support for restoring Blizzard frames when MSUF does not own a group scope.
- Added native Blizzard aura rendering support for group frames.
- Added C-side Blizzard aura routing so MSUF can leave selected aura categories to Blizzard.
- Added private aura layer handling for Blizzard-rendered private auras.

### Profile And Migration
- Preserved 5.53 group-frame default keys where possible.
- Added migration paths for group aura settings and spell indicator defaults.
- Added legacy power text compatibility for old `showPower` usage.
- Added absorb/heal absorb migration so global settings can take over unless a scope explicitly overrides them.
- Added aura migration for old filter fields into the newer filter token and blacklist-category model.
- Added spell indicator seeding path for role/spec layouts.
- Preserved party, raid, and mythic raid scope separation.
- Preserved old status icon style keys and Midnight icon pack support.
- Preserved tooltip mode and modifier settings.
- Preserved old scale-at-group-size settings.

### Known Alpha Notes
- This is a large backend rewrite and should be tested as alpha.
- Standalone legacy HealerBuffs runtime/editor is replaced by Spell Indicators rather than ported as a separate system.
- Rounded group texture runtime is intentionally not part of this alpha backend.
- In-game testing should focus on party/raid roster changes, dungeon zoning, click-casting/Clique, Blizzard aura routing, Auras3 custom lanes, private auras, and profile migration from 5.53.
- Wago and CurseForge publish as alpha when built from the `6.0-alpha1` tag or another tag containing `alpha`.
