-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-Beta6",
    previousVersion = "6.0-Beta5",
    rangeLabel = "6.0-Beta5 -> 6.0-Beta6",
    entries = {
        {
            version = "6.0-Beta6",
            date = "2026-07-06",
            sections = {
                {
                    title = "Bug Fixes",
                    bullets = {
                        "Fixed auras not refreshing on target and focus swaps, which could leave the previous unit's buffs and debuffs showing on the new unit.",
                        "Restored the proven forced aura refresh on every target/focus identity change so the native aura container always reparses for the new unit instead of skipping the rebuild when the applied config looked unchanged.",
                    },
                },
                {
                    title = "Performance Highlights",
                    bullets = {
                        "Added a direct frame event path for RegisterUnitEvent-owned frames so hot unit events run their prebuilt handler immediately instead of going through the broad event router, removing the redundant re-derivation of which frame an event belonged to.",
                        "Added an Ellesmere-style value hot path that bakes the exact health and power work into one closure per frame and event, so value ticks skip the generic runner layer.",
                        "Added a percent-only health path for single frames (target, focus, boss, pet) that uses one UnitHealthPercent call and skips UnitHealth, UnitHealthMax, and store bookkeeping, so a boss target taking sustained damage costs far less per health tick.",
                        "Added direct group-frame health and power dispatch for frequent value updates.",
                    },
                },
                {
                    title = "Runtime Optimizations",
                    bullets = {
                        "Single-frame health color is now re-resolved only on identity, flag, and faction changes and deduplicated on plain health ticks, so target swaps stay correct without per-tick color work.",
                        "Removed a legacy value-handler baker that a profiling session proved never produced a real health or power handler in practice; value events still run correctly through the unified path.",
                        "Added distinct profiling labels for the direct event path so /msufprof shows whether the lean dispatch actually ran.",
                    },
                },
                {
                    title = "What To Test First",
                    bullets = {
                        "Rapid target and focus swapping, including quick swaps with multiple visible buff and debuff lanes, to confirm auras always update for the new unit.",
                        "Target-of-target and focus-target aura and health behavior.",
                        "Boss, target, focus, and pet health under sustained damage, and health bar color on target swaps between players, NPCs, and different reactions.",
                        "Frequent group health and power changes in party and raid layouts.",
                        "/msufprof fast-path, lean-event, and identity diagnostic output.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta5",
            date = "2026-07-05",
            sections = {
                {
                    title = "Performance Highlights",
                    bullets = {
                        "Added lean Target, Focus, and target-of-target identity refreshes that use prebaked element update lists instead of the full runtime wrapper path.",
                        "Added lean per-unit event dispatch for hot unit events so filtered unit trackers can call compiled frame handlers directly.",
                        "Added direct group-frame health dispatch to reduce overhead on frequent health updates.",
                        "Retired inactive group-frame runtime work when party, raid, or mythic raid frames are disabled or not active for the current roster state.",
                    },
                },
                {
                    title = "Runtime Optimizations",
                    bullets = {
                        "Reduced target/focus swap cost by skipping redundant visibility rebuilds and avoiding unnecessary player-only or NPC-only status API checks.",
                        "Reduced group-frame background event work by unregistering name, roster, and Blizzard fallback listeners when group runtime is inactive.",
                        "Tightened targeted-spell refreshes so party-only state is not recalculated for unrelated group-frame updates.",
                        "Added profiling diagnostics for identity refreshes and fast-path dispatch verification.",
                    },
                },
                {
                    title = "What To Test First",
                    bullets = {
                        "Rapid target and focus swapping, including target-of-target and focus-target frames.",
                        "Frequent group health changes in party and raid layouts.",
                        "Enabling, disabling, and switching Party/Raid/Mythic Raid frames, including solo and inactive roster states.",
                        "/msufprof fast-path, detail, and identity diagnostic output.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta4",
            date = "2026-07-05",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Refreshed the Menu2 visual shell with stronger contrast, updated panel textures, clearer navigation states, and improved window controls.",
                        "Added MSUF menu font selection.",
                        "Added per-slot percent-symbol controls for unit-frame, group-frame, and Class Resource text.",
                        "Improved unit and group previews so visible layers, pinned previews, zoom, and snap behavior are more reliable.",
                        "Improved fresh-install and profile-reset handling so the bundled factory profile is applied more consistently.",
                    },
                },
                {
                    title = "Menu And Preview",
                    bullets = {
                        "Updated Menu2 panel, rail, popup, status, and navigation textures.",
                        "Improved Menu2 window snapping, minimize/restore handling, close cleanup, and combat-entry cleanup.",
                        "Improved pinned preview stability when switching pages or closing the menu.",
                        "Improved unit preview fitting for text, status icons, portrait, power, castbar, auras, and class-resource layers.",
                        "Improved group preview layer controls, hover hints, disabled-layer visuals, and restore placement.",
                        "Reset preview zoom and pan when non-guide layers are toggled so changed layers stay visible.",
                        "Reduced menu and Assistant warmup work during normal menu use.",
                    },
                },
                {
                    title = "Unit Frames And Text",
                    bullets = {
                        "Added per-slot percent-symbol visibility for health and power text.",
                        "Added menu and Assistant support for the new percent-symbol text controls.",
                        "Improved NPC type coloring for health bars, name text, and inline target-of-target names.",
                        "Updated NPC type colors when unit classification changes.",
                        "Improved safe handling for protected/secret unit values in color and text logic.",
                        "Reduced redundant unit-frame identity, power text, and aura identity refresh work.",
                    },
                },
                {
                    title = "Group Frames And Edit Mode",
                    bullets = {
                        "Improved Party Targeted Spell Indicator performance.",
                        "Improved group-frame preview and Edit Mode placement for large party, raid, and mythic raid layouts.",
                        "Kept group-frame preview anchors clamped to screen bounds without forcing large layouts into bad positions.",
                        "Fixed mover and popup geometry issues in Edit Mode.",
                        "Stopped motion previews and menu preview interactions more cleanly when combat starts.",
                    },
                },
                {
                    title = "Assistant And Recovery",
                    bullets = {
                        "Added a frame recovery workflow for restoring hidden or misplaced frames.",
                        "Improved Assistant handling for percent-symbol visibility requests.",
                        "Improved Assistant setting search, exact aliases, follow-up parsing, and dashboard/changelog answers.",
                        "Improved Assistant-facing labels and setting registry coverage for text and group-frame options.",
                    },
                },
                {
                    title = "Profiles And Defaults",
                    bullets = {
                        "Improved fresh-install detection when early startup modules already created small bootstrap database buckets.",
                        "Preserved exported factory-profile values while filling only missing structural defaults.",
                        "Initialized the active profile before Menu2, gameplay settings, and previews read MSUF_DB.",
                        "Refreshed preview runtime specs after profile swaps or resets so previews do not use stale profile data.",
                    },
                },
                {
                    title = "What To Test First",
                    bullets = {
                        "Menu2 window controls, snapping, minimize/restore, and close behavior.",
                        "Menu font selection and the refreshed Menu2 styling.",
                        "Unit-frame, group-frame, and Class Resource percent-symbol toggles.",
                        "NPC type colors on target, focus, boss, and target-of-target text.",
                        "Group-frame preview placement with large party, raid, and mythic raid layouts.",
                        "Frame recovery workflow from the Assistant.",
                        "Fresh install, profile reset, and profile swap behavior.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta3",
            date = "2026-07-03",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added selectable status icon packs for unit and group frames.",
                        "Added per-indicator custom icon overrides and live icon previews.",
                        "Added the first Assistant context-engine pass for smarter follow-up commands.",
                        "Restored Wago-compatible profile exports with embedded full MSUF6 data.",
                        "Added an MSUF button to the Blizzard Escape/Game Menu.",
                    },
                },
                {
                    title = "Status Icons And Indicators",
                    bullets = {
                        "Added bundled icon styles: Classic, Midnight, UX Pro, Glossy Orbs, Dark Emboss, Glass Panels, Neon Outline, Ring Symbols, Dots, Shapes, Diamonds, and Squares.",
                        "Added external icon-pack support through public registration, addon metadata, and SharedMedia.",
                        "Added style/custom-icon support for role, leader, assist, raid marker, ready check, summon, resurrection, PvP, phase, combat/resting, and elite indicators.",
                        "Added Midnight-style switching and icon-pack filtering by supported indicator type.",
                        "Added icon preview strips and custom icon asset dropdowns.",
                        "Updated live unit-frame and group-frame status rendering to use the new icon resolver.",
                    },
                },
                {
                    title = "Menu And Preview Improvements",
                    bullets = {
                        "Added a Game Menu MSUF entry with addon icon.",
                        "Added the showGameMenuButton default.",
                        "Added smoother Menu2 scrolling for pages and dropdowns.",
                        "Replaced the preview gear glyph with a drawn settings icon.",
                        "Added Menu2 auto-height helpers.",
                        "Added /msufmenucheck for read-only menu consistency checks.",
                        "Unified live and preview layer constants for unit-frame and group-frame text, status, portrait, power, targeted-spell, and preview-overlay stacking.",
                        "Added on-demand live-vs-preview layer diagnostics for unit and group previews without combat-time event, timer, or update overhead.",
                        "Aligned unit and group preview mock text layering with runtime text-layer specs for closer 1:1 visual previews.",
                    },
                },
                {
                    title = "Assistant And Search",
                    bullets = {
                        "Split large parser phrase tables into _Data.lua modules.",
                        "Added generated fallback coverage for scalar DB settings.",
                        "Added /msufcoverage reports, stubs, manifest export, smoke tracking, and gate checks.",
                        "Added no-op escalation for relative nudges like \"more to the right\".",
                        "Added continuation follow-ups for partially repeated subjects like \"now move target leader up\".",
                        "Added context scoring for recent unit/category/text-area matches.",
                        "De-prioritized generated fallbacks during ambiguous matches.",
                        "Prioritized long exact aliases before broad fast paths.",
                        "Improved generated labels and aliases.",
                        "Improved coverage/audit detection for three-segment scoped keys.",
                        "Improved AutoCoverage labels for acronym boundaries.",
                        "Added small synonym expansion for generated Assistant aliases.",
                        "Added minimum-token exact-alias parsing.",
                        "Added an early priority pass for long exact aliases.",
                    },
                },
                {
                    title = "Profiles And Imports",
                    bullets = {
                        "Added MSUF3-prefixed compact export support for Wago.",
                        "Added normalized Wago compatibility payloads.",
                        "Embedded full msuf6 snapshots in exported strings.",
                        "Prefer embedded full MSUF6 data on import when available.",
                        "Normalized aura and group-frame payloads for Wago compatibility.",
                    },
                },
                {
                    title = "Release And Publishing",
                    bullets = {
                        "Fixed compact prerelease tags like MSUF_6.0B3 so Wago and CurseForge publish them as beta instead of stable/release.",
                        "Added MSUF_* tag support to the release workflow and normalized compact A/B tags to addon versions like 6.0-alpha3 and 6.0-beta3.",
                        "Updated the release version marker to 6.0-beta3.",
                    },
                },
                {
                    title = "Class Resources And Power Text",
                    bullets = {
                        "Added left/center/right slot controls for detached Player Power text.",
                        "Added per-slot value modes, delimiter, size, global offsets, per-slot offsets, and text layer.",
                        "Cleared stale hpPowerTextOverride state when detached power text changes.",
                        "Bumped the Class Resources page version.",
                    },
                },
                {
                    title = "Auras, Castbars, And Runtime Fixes",
                    bullets = {
                        "Added localized minute suffixes for aura duration text.",
                        "Fixed sub-second decimal aura timer display.",
                        "Reduced redundant boss castbar and castbar visual updates.",
                        "Reduced redundant Interrupt Ready visual updates.",
                        "Improved explicit non-interruptible Interrupt Ready colors.",
                        "Added Player health lifecycle events for dead/alive/ghost updates.",
                        "Improved target/focus portrait refresh handling.",
                    },
                },
                {
                    title = "What To Test First",
                    bullets = {
                        "Status icon packs and Midnight variants.",
                        "Custom icon overrides and live previews.",
                        "External icon packs via SharedMedia and addon metadata.",
                        "Unit-frame and group-frame preview layering compared with the matching live frames.",
                        "Assistant follow-ups, exact option names, /msufcoverage, and /msufcoverage gate.",
                        "Wago export/import and full MSUF import from the same string.",
                        "Detached Player Power text slots and offsets.",
                        "Aura duration text around sub-second and minute-long timers.",
                        "Castbar updates, Interrupt Ready visuals, portraits, and Player dead/ghost health refresh.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
