# Midnight Simple Unit Frames Changelog

## 6.0-Beta12 - 2026-07-11

### Changes

- Moved the Assistant back into an optional load-on-demand companion addon to reduce normal MSUF startup and idle overhead.
- Expanded Menu2 and Assistant control coverage, exact setting navigation, search routing, and undo handling.
- Stabilized Edit Mode plus unit, group, aura, spell-effect, and Class Power preview refreshes and layering.
- Added per-resource slot colors and full-resource colors for segmented Class Power displays.
- Reduced duplicate aura work and allocations in large group-frame previews.
- Hardened the two-addon release package and its static validation.

## 6.0-Beta11 - 2026-07-11

### Highlights
- **One self-contained addon:** The Assistant runtime and every locale are again shipped from the main MSUF addon. Installation and release packages no longer depend on separate companion folders.
- **Auras, indicators, and previews:** Aura styling now reaches Custom 1-3 containers, previews follow configured growth directions, and spell indicators can use animated icon glow as well as full-frame visual effects.
- **More reliable group frames:** Group health, prediction, status, connection, roster, and combat state refreshes now share a consistent lifecycle, including AI-controlled party members.

### Packaging And Locales
- Folded the former Load-on-Demand Assistant and non-English locale companion addons back into the primary MSUF TOC. Inactive locale files still return immediately, so only the active language dictionary remains resident.
- Simplified release, CurseForge, and Perfy package staging to ship and validate one addon folder and TOC.
- Updated static validation for the unified package layout and removed obsolete companion-addon package metadata.

### Aura Designer, Spell Indicators, And Menu2
- Added a container selector to Aura Styling for Buffs, Debuffs, and Custom 1-3 containers. Custom-container styling is stored per unit-frame scope and now has a dedicated preview configuration.
- Improved Aura and Group Aura previews: configured growth direction, spacing, rows/columns, duration bars, borders, timers, and custom-container spell icons are represented more faithfully.
- Added animated glow for icon spell indicators, strengthened full-frame effect cleanup, and avoid duplicate geometry/visual passes while aura slots refresh.
- Refined group aura controls, compact group-style navigation, control catalog metadata, menus, navigation, widgets, themes, and preview lifecycle behavior.

### Assistant
- Made result follow-ups fail closed: a pronoun or ordinal from a search result cannot mutate a setting until the result is explicitly selected or explained.
- Improved guided setup, pending-result selection, no-change action handling, undo/history behavior, diagnostics, parser coverage, aura blacklist/filter actions, and setting-graph routing.
- Expanded Assistant knowledge and control registrations for the updated aura, group-frame, text, and visual settings.

### Unit, Group, Castbar, And Resource Runtime
- Added detailed-health handling for AI-controlled group members and shared that authoritative health state with prediction, status, and gone/offline visual updates.
- Tightened prediction calculator reuse to a single core dispatch, added group lifecycle refresh events, and split health/connection fast paths from full prediction refreshes.
- Improved group runtime combat-state publication, post-roster frame-state refreshes, range fading, frame visuals, previews, text formatting/runtime, portrait/power/status elements, and core refresh coordination.
- Refined focus interrupt/kick presentation and Class Power controller/mode behavior; updated fonts and Edit Mode movers to keep live frames and previews aligned.

### What To Test First
- Start MSUF with a non-English client and open Menu2 and the Assistant; confirm both work directly from the single installed addon folder.
- Configure Custom 1-3 aura styling, directional aura growth, spell-indicator icon glow, and full-frame effects in unit and group previews.
- Test AI party members, roster changes, reconnects, combat transitions, range fading, health/prediction bars, and group status overlays.
- In the Assistant, search for a setting, then try a pronoun/ordinal follow-up before and after selecting a result; only an explicit selection may change a setting.

### Earlier Beta 11 Changes

### Optional Assistant Runtime
- Moved the local MSUF Assistant into its own load-on-demand companion addon. The parser, setting graph, knowledge data, and indexes stay unloaded until the Assistant dashboard is opened from Menu2.
- Added a lightweight Menu2 bridge, so normal menu search remains available while the Assistant has zero idle CPU and memory cost outside an active Assistant session. Opening the dashboard now loads and shows the Assistant directly, without a separate start button.
- Improved Assistant request routing, undo/redo, queued work, context handling, diagnostics, and the settings registry; added German/English presentation handling for Assistant dialogs.

### Menu, Search, And Previews
- Reworked Menu2 control registration around a shared control catalog and streamlined page/runtime loading.
- Improved pinned and embedded preview ownership so refreshes survive transient visibility changes while navigating or rebuilding menu pages.
- Refined group and unit preview rendering, draggable text/handle behavior, control enablement, search descriptions, and dashboard navigation.

### Unit, Group, And Class Resources
- Expanded group-frame configuration and runtime refresh handling for layout, visual layers, borders, text placement, status state, and range fading.
- Improved Class Power controller and mode handling, including Balance Druid resource behavior and more faithful menu previews.
- Updated unit-frame formatting, layers, rounded-frame effects, fonts, textures, and color application paths to keep live frames and previews in sync.

### Aura Filtering
- Added an optional **Hide permanent auras** filter for unit-frame, custom-container, group-frame, and spell-indicator aura candidates.
- Kept blacklist state and its menu/Assistant controls synchronized across the relevant unit and group aura scopes.

### Packaging And Validation
- Added the Assistant companion addon to release and Perfy staging, with matching interface/version contract checks.
- Hardened package cleanup and verification to exclude local workflow, graph, cache, and compiled-artifact directories.

### What To Test First
- Open Menu2 normally, use regular search, then start the Assistant and verify its dashboard, request handling, undo/redo, and combat-disabled state.
- Navigate quickly between pages and pinned previews; confirm unit and group preview refreshes and drag handles remain responsive.
- Test group layouts, status/text/border settings, range fading, and Class Power previews across relevant specs.
- Toggle **Hide permanent auras** for unit, custom, and group aura lanes and confirm permanent effects are excluded while timed effects remain.

## 6.0-Beta10 - 2026-07-10

### Unit Frame Auras - Blacklists And Whitelists
- Buff and Debuff blacklists are frame-specific: add exact SpellIDs manually or from a preset, review the prepared entries, and click an entry to remove it.
- Custom Aura containers use their own exact SpellID whitelist, so only the spells you add enter that custom container.
- Blacklists and Custom-Aura whitelists stay local to the selected Unit Frame even when its normal Blizzard filter tokens inherit the Shared configuration.
- Aura setting changes now recompile the affected Unit Frame and refresh its preview immediately; configured aura-lane offsets are also preserved in the preview.

### Group Frame Auras - Blacklists And Whitelists
- Party, Raid, and Mythic Raid aura lanes now use focused Layout, Filters, and Blacklist workspaces.
- Group Buff and Debuff lanes support category blacklists plus exact SpellID blacklists; add individual spells or complete preset groups, see the active list with icons, and click an entry to remove it.
- Native Blizzard filter tokens remain available per group lane. Tracked helpful auras use exact SpellID include filters where Blizzard supports them.
- Private-aura controls were removed from the group-aura UI and Assistant because they are no longer part of the supported group-frame configuration.

### Power Bars And Class Resources
- Player Power, Class Resources, and Alternative Mana gain independently configurable native smooth fill using Blizzard StatusBar interpolation.
- Player Power uses frequent power events for responsive updates, while restricted values remain in Blizzard's native StatusBar path.
- Detached Player Power can use Bar, Round, Crystal, or Orb shapes with configurable borders; texture, background, gradient, and tint updates preserve the selected shape.
- Class Resource previews now match live cooldown-based width modes.

### Runtime, Castbars, And Previews
- Target and Focus castbars clear stale casts before the replacement update is queued, preventing the old unit's cast from remaining visible during a swap.
- Target-of-target and focus-target identity work is coalesced after target-change event bursts.
- Player portraits now force a native refresh when entering or leaving a vehicle, even though the player GUID itself does not change.
- Pinned menu previews use a simpler canvas host, and group/unit aura controls retain their scroll position during workspace rebuilds.

### What To Test First
- Unit-frame Buff and Debuff blacklists: manual SpellIDs, preset additions, removals, Shared-filter inheritance, and preview updates.
- Custom Unit Aura whitelist containers with exact SpellIDs and native filter toggles.
- Party, Raid, and Mythic Raid Buff/Debuff blacklists: category switches, exact SpellIDs, presets, and the active entry list.
- Detached Player Power shapes, borders, colors, smooth fill, and texture changes; Class Resource and Alternative Mana smooth fill.
- Rapid target/focus changes, target-of-target/focus-target updates, and pinned menu previews.

## 6.0-Beta9 - 2026-07-09

### Runtime Fixes
- Fixed target portrait refreshes so portrait textures and model state recover more reliably after target, configuration, and preview changes.
- Fixed self-heal prediction calculation paths so player-driven incoming-heal prediction no longer double-counts or drops the local contribution in test scenarios.
- Fixed absorb prediction refresh behavior for menu test mode and forced prediction updates, including absorb, heal-absorb, over-absorb, and prediction visibility state.

### Auras3 And Load Order
- Embedded the Auras3 runtime directly into UFCore element loading so aura hooks initialize with the unit-frame backend instead of relying on a separate TOC runtime include.
- Tightened Auras3 edit-mode and performance-trace guards around UFCore frame resolution.

### Menu2 And Previews
- Fixed unit preview refresh paths for portrait, absorb, and heal-prediction states after option changes.
- Moved group-frame color controls into the advanced colors page and cleaned up the group bars page so group color settings are easier to find.
- Improved Assistant and menu routing for preview, group layout, group indicators, and color-related requests.

### Release Workflow
- Fixed annotated tag parsing for `publish-target: curseforge` so CurseForge-only beta releases do not accidentally publish to other destinations.

### What To Test First
- Target portrait changes after target swaps, `/reload`, preview toggles, and portrait option changes.
- Absorb, heal-absorb, over-absorb, and incoming-heal previews from the menu test controls.
- Group-frame color settings under Advanced Colors and the removed duplicate controls from Group Bars.
- Auras3 buff and debuff lanes after login and after switching edit/preview modes.

## 6.0-Beta8 - 2026-07-09

### Group Auras And Spell Indicators
- Expanded group-frame tracked aura support so spell-indicator selections can drive tracked buff lanes more reliably.
- Added multi-ID and alias-aware custom aura tracking for spell indicators, including linked aura IDs and custom spell lists.
- Added custom corner indicator aura tracking backed by exact SpellID lists and native AuraContainer filters.
- Added frame-strata support for group aura lanes and spell indicators so tracked buffs, custom indicators, and previews layer more predictably.
- Improved spell-indicator cooldown text sizing and preview rendering for icon, square, bar, and number placements.

### Class Power And Aura Tracking
- Reworked ClassPower aura tracking for WoW 12.1 so aura-driven resources update from incremental `UNIT_AURA` data and full aura scans when needed.
- Fixed Balance Druid Eclipse, Celestial Alignment, and Incarnation tracking for color and Astral Power prediction.
- Improved aura-driven ClassPower modes such as Maelstrom Weapon, Tip of the Spear, Icicles, Demon Hunter soul-fragment states, and Ebon Might.
- Added a short cast-led correction window for Tip of the Spear stacks while Blizzard aura state catches up.

### Health, Absorbs, And Frame State
- Fixed absorb and over-absorb layering by syncing prediction bars to safe frame strata and ignoring secret-backed strata values.
- Hardened health, gradient, NPC-type, class-color, and power-color paths against invalid or secret unit tokens.
- Improved dead, offline, and missing-unit health state handling so colors and bars recover cleanly after identity changes.
- Improved CooldownViewer anchoring checks so unavailable or legacy cooldown frames do not force bad late-anchor behavior.

### Group Frames, Range Fade, And Previews
- Fixed group range fade and offline alpha updates with an event-driven range driver for active visible party and raid units.
- Updated range/offline registration after group-frame identity changes, hide/show transitions, and combat-deferred settle passes.
- Fixed group preview text dragging so name, health text, and power text handles update cleanly while moving.
- Improved group page previews so live group frames are preserved when they already cover the selected party or raid scope.
- Removed targeted-spell cooldown text from live, preview, and test paths.

### Menu2 And Assistant
- Updated Group Indicators and Group Auras controls for custom aura tracking, strata/layer handling, and tracked-buff previews.
- Improved Assistant routing for group aura lanes, spell indicators, text dragging, frame ordering, and health/status settings.
- Tightened group status registry coverage and menu search wiring for the updated indicator and aura paths.

### What To Test First
- Party and raid tracked buffs from spell-indicator selections, especially custom multi-ID entries and linked aura IDs.
- Custom corner indicators with exact SpellID lists and helpful/harmful filter choices.
- Range fade and offline alpha after roster changes, party-to-raid conversion, hide/show, combat, and `/reload`.
- Absorb, heal-absorb, and over-absorb bars with normal, reverse, clamp, and follow modes.
- Balance Druid Eclipse colors and aura-driven ClassPower resources on specs that use aura stacks or timers.
- Group preview dragging for name, health text, power text, aura, and spell-indicator handles.

## 6.0-Beta7 - 2026-07-09

### UFCore Rewrite
- Moved the unit-frame backend behind the embedded `MSUF_UFCore` loader and removed the old broad dispatch module from the main runtime path.
- Reworked unit-frame, group-frame, health, power, text, border, status, load-condition, and factory runtime code around direct Core-owned frame APIs.
- Updated the TOC and XML load order so UFCore owns unit-frame elements, factory setup, and group-frame runtime loading.
- Preserved compatibility bridges for existing feature modules while routing live frame lookup through `MSUF.UF` and `MSUF.GF`.

### Performance And Runtime
- Routed hot unit events through direct frame handlers instead of the old broad dispatch path.
- Reduced normal menu and Assistant apply work by targeting UFCore scopes and dirty masks instead of forcing broad full-frame updates.
- Added opt-in Auras3 performance tracing with `/msufa3trace` tooling for focused aura profiling.
- Added diagnostics and rewrite notes for UFCore connection audits, click-spike tracing, and coldpath/hotpath migration checks.
- Kept click and secure-frame diagnostics out of the default hotpath unless explicitly invoked.

### Auras
- Core feature restored: the Aura Designer is usable again, including healer-focused aura and spell-indicator setup.
- Reconnected Auras3 to UFCore frame resolution and scoped apply paths for unit, target, focus, boss, pet, and group lanes.
- Added separate tooltip controls for buff and debuff lanes.
- Improved target/focus aura refresh behavior and native aura-container rebuild handling.
- Added tracked group-buff lane support backed by spell-indicator data.
- Added Auras3 spell-indicator runtime support for 12.1 CustomAuraContainer aura slots.
- Improved aura include/exclude spell-ID filtering, candidate signatures, and native filter handling.

### Group Frames And Spell Indicators
- Restored spell-indicator data load order for group frames inside the UFCore group embed.
- Added tracked-buff compilation from selected spell-indicator specs and enabled spell-indicator-driven tracked aura lanes.
- Improved group aura defaults, lane configuration, tooltip behavior, and external defensive filtering.
- Updated group indicator Assistant actions, page wiring, and search routing for the new tracked aura/spell-indicator paths.
- Improved group preview rendering for aura lanes, spell-indicator placements, and handle interactions.

### Menu2, Assistant, And Search
- Updated Menu2 apply service, bindings, pages, and Assistant registries to use scoped UFCore apply routes.
- Improved Assistant aura parsing, aura group-lane routing, and dashboard/status selector coverage.
- Added menu controls for frame-border strata and exposed the matching Global Bars control.
- Updated Menu2 aura, group aura, group indicator, and global bar pages for the new Aura3 and group tracked-buff options.
- Improved Menu2 search keywords, FAQ routing, and support text for the new aura and spell-indicator workflows.
- Added and localized new user-facing labels for the spell-indicator and tooltip reset flows.

### Castbars, Class Power, And Integrations
- Connected castbars, boss castbars, player castbar runtime, class power, and gameplay hooks to UFCore-first frame lookup.
- Updated previews and edit-mode interactions for castbars, class power, auras, group frames, and unit frames.
- Kept castbar and class-power live event paths external and direct while refreshing visuals through UFCore callbacks.
- Updated third-party anchor integration and runtime color/font/texture helpers for the UFCore rewrite.

### Visuals And Previews
- Updated Edit Mode movers, popups, HUD, and layout handling for UFCore-backed frames.
- Updated unit and group previews to resolve live frames through UFCore and render updated aura, castbar, class-power, text, and group layers.
- Replaced frame-border level-offset behavior with frame-border strata selection for more predictable overlay layering.
- Improved rounded-frame, border, highlight, alpha, portrait, and status element integration with scoped UFCore refreshes.

### What To Test First
- Rapid target and focus swaps with buffs, debuffs, tracked buffs, tooltips, and cooldown text enabled.
- Party, raid, and mythic raid group auras, especially spell-indicator tracked buffs and external defensive filters.
- Group indicator setup, Assistant commands for spell indicators, and Menu2 search routing for aura/group-aura settings.
- Frame-border strata on unit and group frames across normal UI, previews, and Edit Mode.
- Castbar, class power, rounded-frame, and third-party-anchor behavior after profile swaps and `/reload`.
- `/msufa3trace`, `/msufclickcore`, and UFCore diagnostics only when explicitly testing performance.

## 6.0-Beta6 - 2026-07-06

### Bug Fixes
- Fixed auras not refreshing on target and focus swaps, which could leave the previous unit's buffs and debuffs showing on the new unit.
- Restored the proven forced aura refresh on every target/focus identity change so the native aura container always reparses for the new unit instead of skipping the rebuild when the applied config looked unchanged.

### Performance Highlights
- Added a direct frame event path for RegisterUnitEvent-owned frames so hot unit events run their prebuilt handler immediately instead of going through the broad event router, removing the redundant re-derivation of which frame an event belonged to.
- Added an Ellesmere-style value hot path that bakes the exact health and power work into one closure per frame and event, so value ticks skip the generic runner layer.
- Added a percent-only health path for single frames (target, focus, boss, pet) that uses one UnitHealthPercent call and skips UnitHealth, UnitHealthMax, and store bookkeeping, so a boss target taking sustained damage costs far less per health tick.
- Added direct group-frame health and power dispatch for frequent value updates.

### Runtime Optimizations
- Single-frame health color is now re-resolved only on identity, flag, and faction changes and deduplicated on plain health ticks, so target swaps stay correct without per-tick color work.
- Removed a legacy value-handler baker that a profiling session proved never produced a real health or power handler in practice; value events still run correctly through the unified path.
- Added distinct profiling labels for the direct event path so `/msufprof` shows whether the lean dispatch actually ran.

### What To Test First
- Rapid target and focus swapping, including quick swaps with multiple visible buff and debuff lanes, to confirm auras always update for the new unit.
- Target-of-target and focus-target aura and health behavior.
- Boss, target, focus, and pet health under sustained damage, and health bar color on target swaps between players, NPCs, and different reactions.
- Frequent group health and power changes in party and raid layouts.
- `/msufprof` fast-path, lean-event, and identity diagnostic output.

## 6.0-Beta5 - 2026-07-05

### Performance Highlights
- Added lean Target, Focus, and target-of-target identity refreshes that use prebaked element update lists instead of the full runtime wrapper path.
- Added lean per-unit event dispatch for hot unit events so filtered unit trackers can call compiled frame handlers directly.
- Added direct group-frame health dispatch to reduce overhead on frequent health updates.
- Retired inactive group-frame runtime work when party, raid, or mythic raid frames are disabled or not active for the current roster state.

### Runtime Optimizations
- Reduced target/focus swap cost by skipping redundant visibility rebuilds and avoiding unnecessary player-only or NPC-only status API checks.
- Reduced group-frame background event work by unregistering name, roster, and Blizzard fallback listeners when group runtime is inactive.
- Tightened targeted-spell refreshes so party-only state is not recalculated for unrelated group-frame updates.
- Added profiling diagnostics for identity refreshes and fast-path dispatch verification.

### What To Test First
- Rapid target and focus swapping, including target-of-target and focus-target frames.
- Frequent group health changes in party and raid layouts.
- Enabling, disabling, and switching Party/Raid/Mythic Raid frames, including solo and inactive roster states.
- `/msufprof` fast-path, detail, and identity diagnostic output.

## 6.0-Beta4 - 2026-07-05

### Highlights
- Refreshed the Menu2 visual shell with stronger contrast, updated panel textures, clearer navigation states, and improved window controls.
- Added MSUF menu font selection.
- Added per-slot percent-symbol controls for unit-frame, group-frame, and Class Resource text.
- Improved unit and group previews so visible layers, pinned previews, zoom, and snap behavior are more reliable.
- Improved fresh-install and profile-reset handling so the bundled factory profile is applied more consistently.

### Menu And Preview
- Updated Menu2 panel, rail, popup, status, and navigation textures.
- Improved Menu2 window snapping, minimize/restore handling, close cleanup, and combat-entry cleanup.
- Improved pinned preview stability when switching pages or closing the menu.
- Improved unit preview fitting for text, status icons, portrait, power, castbar, auras, and class-resource layers.
- Improved group preview layer controls, hover hints, disabled-layer visuals, and restore placement.
- Reset preview zoom and pan when non-guide layers are toggled so changed layers stay visible.
- Reduced menu and Assistant warmup work during normal menu use.

### Unit Frames And Text
- Added per-slot percent-symbol visibility for health and power text.
- Added menu and Assistant support for the new percent-symbol text controls.
- Improved NPC type coloring for health bars, name text, and inline target-of-target names.
- Updated NPC type colors when unit classification changes.
- Improved safe handling for protected/secret unit values in color and text logic.
- Reduced redundant unit-frame identity, power text, and aura identity refresh work.

### Group Frames And Edit Mode
- Improved Party Targeted Spell Indicator performance.
- Improved group-frame preview and Edit Mode placement for large party, raid, and mythic raid layouts.
- Kept group-frame preview anchors clamped to screen bounds without forcing large layouts into bad positions.
- Fixed mover and popup geometry issues in Edit Mode.
- Stopped motion previews and menu preview interactions more cleanly when combat starts.

### Assistant And Recovery
- Added a frame recovery workflow for restoring hidden or misplaced frames.
- Improved Assistant handling for percent-symbol visibility requests.
- Improved Assistant setting search, exact aliases, follow-up parsing, and dashboard/changelog answers.
- Improved Assistant-facing labels and setting registry coverage for text and group-frame options.

### Profiles And Defaults
- Improved fresh-install detection when early startup modules already created small bootstrap database buckets.
- Preserved exported factory-profile values while filling only missing structural defaults.
- Initialized the active profile before Menu2, gameplay settings, and previews read `MSUF_DB`.
- Refreshed preview runtime specs after profile swaps or resets so previews do not use stale profile data.

### What To Test First
- Menu2 window controls, snapping, minimize/restore, and close behavior.
- Menu font selection and the refreshed Menu2 styling.
- Unit-frame, group-frame, and Class Resource percent-symbol toggles.
- NPC type colors on target, focus, boss, and target-of-target text.
- Group-frame preview placement with large party, raid, and mythic raid layouts.
- Frame recovery workflow from the Assistant.
- Fresh install, profile reset, and profile swap behavior.

## 6.0-Beta3 - 2026-07-03

### Highlights
- Added selectable status icon packs for unit and group frames.
- Added per-indicator custom icon overrides and live icon previews.
- Added the first Assistant context-engine pass for smarter follow-up commands.
- Restored Wago-compatible profile exports with embedded full MSUF6 data.
- Added an MSUF button to the Blizzard Escape/Game Menu.

### Status Icons And Indicators
- Added bundled icon styles: Classic, Midnight, UX Pro, Glossy Orbs, Dark Emboss, Glass Panels, Neon Outline, Ring Symbols, Dots, Shapes, Diamonds, and Squares.
- Added external icon-pack support through public registration, addon metadata, and SharedMedia.
- Added style/custom-icon support for role, leader, assist, raid marker, ready check, summon, resurrection, PvP, phase, combat/resting, and elite indicators.
- Added Midnight-style switching and icon-pack filtering by supported indicator type.
- Added icon preview strips and custom icon asset dropdowns.
- Updated live unit-frame and group-frame status rendering to use the new icon resolver.

### Menu And Preview Improvements
- Added a Game Menu MSUF entry with addon icon.
- Added the `showGameMenuButton` default.
- Added smoother Menu2 scrolling for pages and dropdowns.
- Replaced the preview gear glyph with a drawn settings icon.
- Added Menu2 auto-height helpers.
- Added `/msufmenucheck` for read-only menu consistency checks.
- Unified live and preview layer constants for unit-frame and group-frame text, status, portrait, power, targeted-spell, and preview-overlay stacking.
- Added on-demand live-vs-preview layer diagnostics for unit and group previews without combat-time event, timer, or update overhead.
- Aligned unit and group preview mock text layering with runtime text-layer specs for closer 1:1 visual previews.

### Assistant And Search
- Split large parser phrase tables into `_Data.lua` modules.
- Added generated fallback coverage for scalar DB settings.
- Added `/msufcoverage` reports, stubs, manifest export, smoke tracking, and gate checks.
- Added no-op escalation for relative nudges like "more to the right".
- Added continuation follow-ups for partially repeated subjects like "now move target leader up".
- Added context scoring for recent unit/category/text-area matches.
- De-prioritized generated fallbacks during ambiguous matches.
- Prioritized long exact aliases before broad fast paths.
- Improved generated labels and aliases.
- Improved coverage/audit detection for three-segment scoped keys.
- Improved AutoCoverage labels for acronym boundaries.
- Added small synonym expansion for generated Assistant aliases.
- Added minimum-token exact-alias parsing.
- Added an early priority pass for long exact aliases.

### Profiles And Imports
- Added MSUF3-prefixed compact export support for Wago.
- Added normalized Wago compatibility payloads.
- Embedded full `msuf6` snapshots in exported strings.
- Prefer embedded full MSUF6 data on import when available.
- Normalized aura and group-frame payloads for Wago compatibility.

### Release And Publishing
- Fixed compact prerelease tags like `MSUF_6.0B3` so Wago and CurseForge publish them as beta instead of stable/release.
- Added `MSUF_*` tag support to the release workflow and normalized compact A/B tags to addon versions like `6.0-alpha3` and `6.0-beta3`.
- Updated the release version marker to `6.0-beta3`.

### Class Resources And Power Text
- Added left/center/right slot controls for detached Player Power text.
- Added per-slot value modes, delimiter, size, global offsets, per-slot offsets, and text layer.
- Cleared stale `hpPowerTextOverride` state when detached power text changes.
- Bumped the Class Resources page version.

### Auras, Castbars, And Runtime Fixes
- Added localized minute suffixes for aura duration text.
- Fixed sub-second decimal aura timer display.
- Reduced redundant boss castbar and castbar visual updates.
- Reduced redundant Interrupt Ready visual updates.
- Improved explicit non-interruptible Interrupt Ready colors.
- Added Player health lifecycle events for dead/alive/ghost updates.
- Improved target/focus portrait refresh handling.

### What To Test First
- Status icon packs and Midnight variants.
- Custom icon overrides and live previews.
- External icon packs via SharedMedia and addon metadata.
- Unit-frame and group-frame preview layering compared with the matching live frames.
- Assistant follow-ups, exact option names, `/msufcoverage`, and `/msufcoverage gate`.
- Wago export/import and full MSUF import from the same string.
- Detached Player Power text slots and offsets.
- Aura duration text around sub-second and minute-long timers.
- Castbar updates, Interrupt Ready visuals, portraits, and Player dead/ghost health refresh.

## 6.0-Beta2 - 2026-07-03

### Highlights
- Better previews: quick settings access, context controls, gear buttons, and improved preview handle behavior.
- Better visuals: 2D portrait zoom, resource-bar opacity, live power alpha, and optional over-absorb glow.
- Better stability: castbar border fixes, class-power reload fixes, faster Assistant routing, and less redundant runtime work.

### Menu And Preview Improvements
- Quick settings access from unit, group, and class-resource preview handles.
- New preview-handle context controls and gear buttons.
- Improved moving, nudging, zooming, panning, and fit behavior in previews.
- Fixed preview checkbox/text sync issues.
- Refined group preview controls and native group preview behavior.

### Unit Frames, Bars, And Visuals
- Added 2D portrait zoom.
- Added separate resource-bar foreground/background opacity.
- Added live power-bar alpha support.
- Added optional over-absorb overlay/glow.
- Fixed live HP percent formatting.
- Reduced redundant unit-frame and portrait refresh work.

### Castbars And Class Resources
- Fixed long-standing castbar border/layout inset issues.
- Fixed boss castbar border/layout inset handling.
- Reduced redundant castbar text/time updates.
- Stabilized detached class-power and Player Power anchors.
- Fixed class power placement after `/reload` in combat.

### Assistant And Search
- More Assistant coverage for frame settings, geometry/text, auras, castbars, global bars, colors, transparency, portrait zoom, over-absorb, and group-frame actions.
- Faster Assistant routing and cancellable work.
- Better followups, exact aliases, media resolution, and changelog/dashboard answers.
- Added Assistant coverage documentation.

### Edit Mode, Popups, And Diagnostics
- Fixed Edit Mode popups letting clicks pass through.
- Added debug position diagnostics.
- Added runtime localization fallbacks for new menu/search strings.

### What To Test First
- Preview gear/context shortcuts.
- 2D portrait zoom on all unit frames.
- Health/resource opacity on live frames.
- Absorb and over-absorb display.
- Castbar borders, including boss castbars.
- Class resources and detached Player Power after `/reload`.

## 6.0-Beta1 - 2026-07-01

### Short Version
- 6.0-Beta1 is the real upgrade path from 5.60 to 6.0, not a small follow-up patch.
- It is built for WoW 12.1. If you are still using 5.60, export your profiles before trying this beta.
- All Alpha 1-8 changes are included here, plus the final Beta1 fixes and polish.
- The addon should still feel like MSUF, but a lot underneath it has been replaced so it can work properly on the 12.1 client.

### What You Will Notice First
- Auras are the biggest change. Buffs and debuffs now use the WoW 12.1 native aura system instead of the old 5.60 aura renderer.
- Group frames should feel more complete and more consistent, especially in parties and raids.
- Class resources and Player power bars have more visual styles, better previews, and more layout control.
- The settings menu is more useful. The new Assistant can find settings, apply many changes, handle followups, run checks, and undo changes it made.
- Castbars are now part of the main 6.0 setup instead of feeling like a separate older layer.
- Profile import/export is more forgiving, especially when older strings, missing fonts, missing textures, or alpha profiles are involved.

### New Compared To 5.60
- Auras3 replaces Auras2 for live aura display on WoW 12.1.
- Aura duration bars can now be shown under buff and debuff icons.
- Aura cooldown swipe direction can be normal or reversed.
- Aura lanes can be moved more directly in Edit Mode.
- Buff and debuff lanes have clearer Shared/Custom style controls, cooldown text placement, stack text placement, native filters, and preview support.
- Native dispel detection is wired into the new aura path.
- Party Targeted Spell Indicators can show enemy nameplate casts on the party member being targeted.
- MSUF4 profile strings are now supported, while older MSUF2/MSUF3 strings are still handled as fallback imports.
- Northern Sky Raid Tools nicknames can be used for unit-frame names.
- External anchor support was added, including Skiron cooldown anchors.
- New class-resource and power-bar shapes were added: circle, diamond, hex, round, crystal, and orb-style options.
- Class Resources now has shape presets such as Classic Bar, Clean Dots, Gems, Hex Pips, and Compact.
- The detached Player Power bar can now follow class-resource styling or use its own bar, round, crystal, or orb style.
- An optional extra Player HP bar can be shown near class resources or Player Power, with its own text, size, color, texture, and shape options.
- The in-game changelog can be opened from MSUF after updating.

### Reworked From 5.60
- Unit frames were rebuilt for 6.0: health, power, text, alpha, range fade, status icons, prediction bars, borders, and load conditions now use the new engine.
- Group frames were rebuilt instead of patched on top of the old 5.60 group system. Party, Raid, and Mythic Raid now share the same newer frame logic.
- Castbars existed in 5.60, but 6.0 integrates Player, Target, Focus, Boss, Focus Kick, and Interrupt Ready into the main addon flow with better previews and cleaner ownership.
- Class Resources were expanded with better class/spec previews, shape media, smoother resource presentation, detached power-bar controls, and the optional Player HP bridge.
- Menu2 was already present in 5.60, but 6.0 turns it into a fuller settings shell with navigation, previews, search, Assistant support, bug report tools, and better window handling.
- Edit Mode moved from the old EditMode2 path to the new 6.0 Edit Mode, including aura handles, cast/aura popups, popup scaling, and the new logo intro.
- Gameplay helpers were reorganized and hardened around combat, reloads, target sound, totem preview, and related helper settings.

### Auras In Plain English
- 5.60 displayed auras with MSUF's own older scanner and renderer. 6.0 lets Blizzard's 12.1 aura system do the live tracking and lets MSUF control how those auras look.
- This should make target swaps, focus swaps, group updates, and combat aura updates more reliable on the new client.
- You get more visible controls for each aura lane: size, spacing, growth direction, cooldown text, stack text, duration bars, filters, and tooltip behavior.
- Existing blacklist data is kept, but old Auras2 filtering may not match perfectly because the new system uses Blizzard's native 12.1 filter strings.

### Group Frames
- Party, Raid, and Mythic Raid are now handled by the same 6.0 group-frame system.
- Party Targeted Spell Indicators are the main new gameplay feature here: in dungeon content, a party frame can show when an enemy cast is aimed at that player.
- Group auras now use the new Auras3 path, including native dispel support and better preview behavior.
- Status indicators, spell indicators, range fade, health fade, offline/dead visuals, role filters, threat/aggro visuals, and text handling were cleaned up into one more predictable setup.
- Beta1 also adds more visibility/load conditions, including housing cases, and more control over which roles show aggro borders.

### Class Resources And Power Bars
- Class resources are no longer just the old rectangular class bar style. You can use bar, dot, gem, hex, compact, round, crystal, and orb-like looks depending on the resource or attached power bar.
- The Class Resources page now has better previews for real class/spec cases such as runes, combo points, soul shards, essence, holy power, chi, insanity, maelstrom, stagger, and similar resource styles.
- Shape presets make it faster to switch between classic bars, clean dots, gem-style pips, hex pips, and compact resource displays.
- Detached Player Power can sync with class resources or use its own style, size, texture, outline, text, and placement.
- The optional Player HP bar can sit above or below class resources or Player Power, and can follow the Player Power style if you want a matched resource cluster.
- Power-bar and class-resource previews were improved so changes are easier to judge before leaving the settings menu.

### Profiles And Migration
- 6.0 tries to migrate 5.60 profiles automatically, but this is a major version jump. Export first.
- Old profile strings, missing media, older alpha data, and some external imports should recover better instead of failing the whole import.
- MSUF4 is the new profile string format for 6.0.
- Older MSUF2/MSUF3 profile strings are still attempted through fallback import paths.
- Imported profiles can be applied to the current profile or brought in as a new profile, depending on the workflow.

### From Alpha 1 To Beta1
- Alpha 1 opened the 6.0 branch with the new foundation, previews, castbar work, class-resource work, profile import/export, group-frame work, and the first Auras3 version.
- Alpha 2 moved live aura display to Blizzard's native 12.1 AuraContainer system.
- Alpha 3 improved aura timer colors, Assistant context, geometry followups, castbar controls, class-resource previews, and preview routing.
- Alpha 4 improved Shared aura styling, per-unit aura text overrides, cooldown text anchors, aura previews, and boss preview refresh.
- Alpha 5 added reverse cooldown swipe and fixed important castbar preview/runtime issues.
- Alpha 6 added Party Targeted Spell Indicators, NSRT nicknames, MSUF4 profile strings, class-resource shapes, stronger import handling, and the in-game changelog.
- Alpha 7 added the Edit Mode logo intro and prepared the CurseForge-only alpha release path.
- Alpha 8 added aura dragging, menu performance work, combat performance work, and more Assistant coverage for group and bar settings.
- Beta1 stabilizes all of that for wider 5.60 -> 6.0 testing.

### Beta1 Polish
- Aura duration bars and native dispel sensors are now connected through live frames, previews, defaults, menus, and the Assistant.
- The Assistant understands more aura, group-frame, bar, overlay, load-condition, and followup requests.
- Castbar width mode, castbar text, Interrupt Ready refresh, and class-bar quick setup issues were fixed.
- Group-frame layout, group status refresh, menu keyboard handling, unit-frame prediction updates, and font checks were tightened up.
- Local development files, stale bytecode output, and release packaging were cleaned up for the beta build.

### What To Test First
- Import or copy a 5.60 profile, then check Player, Target, Focus, Boss, Target of Target, Focus Target, Party, Raid, and Mythic Raid.
- Test auras on WoW 12.1: target swaps, focus swaps, party/raid conversion, dispellable debuffs, duration bars, cooldown text, stack text, aura dragging, and filters.
- Test Party Targeted Spell Indicators in 5-player content with enemy nameplates enabled.
- Test Class Resources on several classes/specs, especially shape presets, detached Player Power, the optional Player HP bar, and preview switching.
- Test castbars for normal casts, channels, empower casts, Boss casts, Focus Kick, Interrupt Ready, and Blizzard/MSUF player castbar ownership.
- Test profile strings, missing font/texture fallback, NSRT nicknames, external anchors, Edit Mode, and /reload after combat.


## 6.0-alpha8 - 2026-06-30

### Highlights
- Added draggable Auras3 edit handles so aura lanes can be moved more directly in Edit Mode.
- Improved Menu2 and combat hot-path performance before the Beta cut.
- Expanded Assistant coverage for group-frame and bar controls.
- Prepared the MSUF_6.0A8 package as the last alpha before Beta1.

### Auras, Menu, And Performance
- Improved aura movement, aura edit-mode state, target/focus aura refresh, and range fade related refresh behavior.
- Reduced menu preview rebuild work and tightened several Menu2 window/page refresh paths.
- Improved combat performance across runtime update paths that were too noisy during alpha testing.
- Updated group bar/page controls and related Assistant routing so more group-frame settings can be found and changed naturally.

## 6.0-alpha7 - 2026-06-30

### Highlights
- Added the MSUF Edit Mode Logo Wake intro using the high-resolution MSUF logo asset.
- Added a CurseForge-only release path so Alpha 7 can be published without also uploading to Wago.

### Edit Mode
- Updated the logo intro so the logo fades in smoothly, gets a brief cyan wake glow, then lets the ring trace run once and close.
- Kept the intro animation scoped to the Edit Mode opening sequence; its `OnUpdate` is removed again when the intro stops.

### Release And Notes
- Release name: MSUF_6.0A7.
- Bumped VERSION and addon metadata to 6.0-alpha7.
- This tag is intentionally an alpha build; use `6.0-alpha7` as the publish tag.
- Alpha 7 is intended for CurseForge-only publishing.

### Alpha Testing Notes
- This is an alpha build for the 6.0 branch. Export important profiles before testing.
- Please test opening and leaving Edit Mode repeatedly and verify the logo intro does not continue running after Edit Mode closes.
- Please test opening Edit Mode shortly before/after combat to confirm no combat overhead or lingering animation state.

## 6.0-alpha6 - 2026-06-29

### Highlights
- Added party targeted spell indicators that can show enemy nameplate casts on the targeted party frame, with icon stack, placement, timer text, and time-based text color controls.
- Added optional Northern Sky Raid Tools nickname integration for unit-frame display names.
- Improved profile import/export and migration handling, including the new MSUF4 compact profile format and better fallback decoding for older MSUF2/MSUF3 profile strings.
- Added the bundled in-game changelog prompt so users can open release notes from the dashboard after updating.

### Group Frames And Indicators
- Added party-only targeted spell tracking for enemy casts, including cast/channel pickup, retarget verification, cooldown text, and per-party-frame icon placement.
- Added Targeted Spells controls to Group Indicators with enable mode, icon size/count/layer, anchor/growth, offsets, cooldown text, and timer color thresholds.
- Updated group-frame defaults and configuration so targeted spell settings are carried by the party profile scope.
- Improved group preview rendering for targeted spell/status indicator placement and native preview refreshes.

### Profiles, Imports, And Defaults
- Added MSUF4 profile export strings while keeping import compatibility for MSUF3 and legacy MSUF2 variants.
- Improved compact profile decoding by trying Blizzard decompression, direct CBOR, and LibDeflate-backed fallbacks where available.
- Added profile translation and normalization for older 6.0 alpha profile layouts, including aura geometry, text/name shortening aliases, status indicator fields, and group-frame scope fields.
- Hardened profile runtime apply calls so one apply error is captured instead of breaking the whole profile operation.

### Menu, Assistant, And Integrations
- Added NSRT nickname resolver support with combat-safe refresh behavior and cache updates when NSRT nickname data changes.
- Expanded Assistant parsing and registry coverage for aura style/filter commands, group aura lane geometry, targeted spell controls, global bar settings, and base global options.
- Improved dashboard and nav-rail behavior, including hover scale defaults and typewriter/changelog handling.
- Clarified Global Bars texture inheritance: unit scopes keep Shared textures while group-frame scopes can override textures and gradients.
- Temporarily disabled dispel/purge border controls for 12.1 PTR until native AuraContainer exposes the needed detection path again.

### Fonts, Text, And Visuals
- Improved font path probing and safe font fallback resolution for missing or unavailable fonts.
- Updated text layout/status paths to handle layer frames, status fonts, name shortening, and profile-translated text fields more consistently.
- Refined castbar, class power, aura popup, group preview, and Edit Mode HUD rendering details.
- Updated superellipse media assets used by the rounded frame visuals.

### Release And Notes
- Release name: MSUF_6.0A6.
- Bumped VERSION and addon metadata to 6.0-alpha6.
- Regenerated the in-game dashboard changelog data for Alpha 6.
- Hardened the release workflow and Wago upload step so alpha metadata, alpha tags, and A-style alpha release names cannot be uploaded to Wago as stable/release.
- This tag is intentionally an alpha build; use `6.0-alpha6` as the publish tag so Wago receives `stability = alpha`, CurseForge receives an alpha release type, and GitHub marks the release as prerelease.

### Alpha Testing Notes
- This is an alpha build for the 6.0 branch. Export important profiles before testing.
- Please test Targeted Spells in 5-player party content with enemy nameplates enabled, especially casts that retarget or channel.
- Please test importing older Alpha 2 through Alpha 5 profile strings, especially profiles with custom aura positions, fonts, textures, and group-frame text settings.
- Please test NSRT nickname display with NSRT global nicknames enabled and disabled.

## 6.0-alpha5 - 2026-06-28

### Highlights
- Added reverse cooldown swipe options for aura icons, including defaults, profile export normalization, previews, and Assistant/menu registry coverage.
- Improved Aura Style and Aura Filters menu scope handling with clearer shared-vs-custom override controls for unit frames and group frames.
- Fixed castbar channel and empowered preview/runtime behavior after the Alpha 4 castbar pass.
- Fixed castbar previews so player/target/focus/boss preview refreshes and Blizzard player castbar suppression behave more reliably.

### Aura Menu And Assistant
- Added cooldown swipe direction controls for unit and group aura lanes.
- Updated shared aura previews to distinguish normal and reverse swipe samples instead of grouping them only by icon size.
- Added shared/custom override bars for aura style and filter pages so inherited settings are easier to see and reset.
- Expanded Assistant coverage for aura style/filter settings and group aura lane controls.

### Castbars
- Hardened castbar preview refreshes and removed fragile preview driver state.
- Fixed channel and empowered castbar preview updates, including stage blink handling and safer color/option lookups.
- Stopped writing addon-owned suppression fields onto Blizzard castbar frames; MSUF now suppresses Blizzard player castbar events directly when MSUF owns the player castbar.
- Removed unsafe SetOnUpdateMode calls from castbar runtime paths.

### Release And Notes
- Release name: MSUF_6.0A5.
- Bumped VERSION and addon metadata to 6.0-alpha5.
- Regenerated the in-game dashboard changelog data for Alpha 5.
- This tag is intentionally an alpha build; the release workflow maps alpha tags to Wago alpha stability, CurseForge alpha release type, and GitHub prerelease.

### Alpha Testing Notes
- This is an alpha build for the 6.0 branch. Export important profiles before testing.
- Please test aura cooldown swipe direction on player, target, focus, boss, party, and raid frames.
- Please test normal casts, channels, empowered casts, castbar previews, and switching between Blizzard and MSUF player castbar ownership.

## 6.0-alpha4 - 2026-06-27

### Highlights
- Release name: MSUF_6.0A4.
- Aura style editing now separates shared layout inheritance from per-unit text style overrides, so individual frames can adjust aura text without cloning all aura layout data.
- Unit, group, and shared aura previews now show cooldown and stack text placement more accurately, including per-lane cooldown anchors.
- Assistant followups and aura registries now cover more natural language commands for aura lanes, unit aura settings, and text-area adjustments.
- Boss frame previews refresh more reliably outside encounters, including when reopening the unit-frame page.

### Aura Style And Preview
- Added cooldown text anchor support for shared, buff, and debuff aura lanes in the Auras3 model, edit-mode preview path, live unit-frame compiler, and Auras menu controls.
- Added sparse visual override normalization so inherited aura layout keys are not treated as per-unit style overrides unless the scope actually customizes text or style behavior.
- Rebuilt unit and group aura style controls into focused preview, text feature, stack-count, cooldown text, and behavior sections.
- Shared aura previews now group frame samples by actual configured icon size and label the affected frame group instead of showing one generic preview.
- Added scope-aware cooldown timer formatting so Shared, unit, and group aura styles can choose below how many remaining seconds decimal text is shown; live aura text still uses Blizzard's C-side DurationTextBinding/NumericRuleFormatter path.
- Group aura style controls now expose cooldown and stack text anchors, offsets, dynamic scaling, tooltip, sorting, and player-aura preference in collapsible sections.

### Assistant And Menu
- Improved followup parsing for bare exact-number edits such as "set to 12" and for applying the previous HP/name/power text adjustment to another text area.
- Expanded aura assistant registry coverage for cooldown text anchors, lane style values, use-shared-style behavior, and unit aura lane commands.
- Added larger change/reload guidance for assistant-driven changes that may need a UI reload.
- Refined assistant context handling from the previous local commit, including no-match resolution, geometry followups, edit-mode previews, and registry exact aliases.
- Updated the Boss frame preview copy and refresh logic so previewed boss frames are not left hidden after menu navigation.

### Release And Notes
- Bumped addon metadata from 6.0-alpha3 to 6.0-alpha4 and VERSION from 6.0-alpha2 to 6.0-alpha4.
- Regenerated the in-game changelog data from this changelog for the A4 package.
- Kept the existing release automation path compatible with alpha publishing by using the 6.0-alpha4 publish tag and MSUF_6.0A4 as the release name.

## 6.0 Alpha 3 - 2026-06-27

### Highlights
- Added timer-based aura color work after Alpha 2.
- Improved assistant context, geometry followups, exact alias handling, edit-mode controls, and preview routing.
- Updated castbar, aura, and assistant release notes after the Alpha 3 packaging pass.

### Notes
- Alpha 3 was an interim alpha build on the 6.0 branch before the A4 aura style and assistant followup pass.

## 6.0 Alpha 2 - 2026-06-27

### Highlights
- New Aura Container System: MSUF now uses WoW 12.1's native AuraContainer and AuraButton system for live aura display instead of the older custom aura scanner/render path from Alpha 1.
- Buffs, debuffs, and important defensive/external auras are handled as separate native aura lanes, so aura updates should feel smoother and more reliable during target swaps, group changes, and combat.
- Unit frames, party frames, raid frames, and mythic raid frames now share the same Auras3 foundation, with Blizzard doing the heavy aura tracking and MSUF focusing on layout and styling.
- Aura containers allocate only the configured number of icons, which keeps the system predictable and avoids unnecessary preloading spikes.

### Aura Settings And Filtering
- Added clearer aura controls for unit frames and group frames, including separate styling for buffs and debuffs.
- Added native group aura filter choices such as raid buffs, raid debuffs, dispellable debuffs, crowd control, external defensives, and big defensives.
- Added optional debuff type visuals: off, colored border, or colored border with a type symbol.
- Cooldown swipe, cooldown text, stack count, tooltip behavior, size, spacing, growth direction, and text placement can now be adjusted per aura lane.
- Existing legacy blacklist data is kept, but exact SpellID-style filtering is limited in this alpha because the new native AuraContainer path exposes Blizzard filter strings rather than MSUF's old custom predicate system.

### Menu And Assistant Improvements
- The Auras page was rebuilt around scope and lane workflows, making it easier to edit Shared, Player, Target, Focus, Boss, Party, and Raid aura behavior.
- The Assistant gained much broader coverage for auras, group auras, castbars, class resources, unit frames, profiles, dashboard actions, and troubleshooting.
- Search and dashboard routing now expose more setup tasks directly, so common configuration areas are easier to find.
- Many large Assistant registry files were split into smaller pieces to reduce load risk and make future changes easier to maintain.

### Unit Frames, Castbars, And Class Resources
- Unit frame refresh paths received more targeted updates for visuals, text, alpha, range fade, status indicators, and aura-related state.
- Castbar runtime code received cleanup across player, target, focus, boss, channel ticks, empower casts, focus kick, and Interrupt Ready paths.
- Class resource handling received follow-up fixes around Player HP integration, preview behavior, alternate mana, and balance druid state.
- Group frame visuals, status handling, spell indicators, and preview paths received additional Alpha 2 cleanup.

### Performance And Stability
- Removed much of the Alpha 1 custom aura scan/diff/render work from the live display path.
- Aura refreshes now lean on Blizzard's native incremental aura updates, while MSUF coalesces expensive layout/configuration changes.
- Target and focus aura swaps are refreshed more deliberately so stale aura displays are less likely after changing targets.
- Several runtime paths were simplified so errors surface during alpha testing instead of being hidden by broad fallback wrappers.
- Added local smoke and quality checks for Assistant parsing, group status runtime behavior, namespace safety, spell indicator data, and general addon quality gates.

### Alpha Testing Notes
- This is still an alpha build. Export important profiles before testing.
- Please test auras on player, target, focus, boss, party, raid, and mythic raid frames.
- Please test target switching, focus switching, entering/leaving groups, raid conversion, combat lockdown, dispel visuals, stack counts, cooldown text, and tooltip behavior.
- If an old aura blacklist or exact spell filter no longer behaves like Alpha 1, report it with the spell name, SpellID, unit frame, and aura lane.

## 6.0 Alpha 1 - 2026-06-24

### Alpha 1 Baseline
- First public 6.0 alpha package for the rewritten MSUF 6.x core.
- Introduced the rebuilt Menu2 configuration UI, expanded previews, integrated castbars, class resource updates, group-frame runtime work, profile import/export work, and the first Auras3 alpha path.
- This build is the comparison baseline used for the Alpha 2 notes above.
