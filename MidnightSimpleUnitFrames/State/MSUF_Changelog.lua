-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-Beta14",
    previousVersion = "6.0-Beta13",
    rangeLabel = "6.0-Beta13 -> 6.0-Beta14",
    entries = {
        {
            version = "6.0-Beta14",
            date = "2026-07-13",
            sections = {
                {
                    title = "Changes",
                    bullets = {
                        "Coalesced and interned core runtime update paths to reduce duplicate work.",
                        "Added compact/abbreviated HP values and full-value HP formatting support where relevant.",
                        "Stabilized group layout behavior with adaptive roster scaling and improved group runtime refresh ordering.",
                        "Added configurable aura lane sorting, filtering, and improved aura growth/local budget handling.",
                        "Improved class text and group text settings to keep health formatting and preview states in sync.",
                        "Expanded assistant setting routes, guided actions, and conversational workflow behavior.",
                        "Improved assistant diagnostics and control routing to match current menu pages and workflows.",
                        "Refreshed release/tooling inventories and updated runtime release metadata handling.",
                        "Wired HP abbreviation into group text runtime specs and kept runtime specs aligned with feature changes.",
                        "Interned group lifecycle work plans and tightened status updates for gone-state and lifecycle transitions.",
                        "Scaled castbar lifecycle and hotpath handling to active casts only for lower per-frame overhead.",
                        "Compiled ClassPower mode runtime state and improved aurawork layout stability in active runtime paths.",
                        "Optimized frequent color pathups with font/color fast paths.",
                        "Reduced redundant visibility, metadata, and power-cached update work in hot paths.",
                        "Streamlined prediction geometry caching and dependent-unit routing.",
                        "Fixed player profile refresh to correctly apply alpha state.",
                        "Refreshed menu theme/history feedback and exact setting-control resolution flow.",
                        "Restored event-driven profile lifecycle behavior for target-sound handling.",
                        "Updated Menu2 runtime and onboarding UX: first-load plus guided-tour states and pages.",
                        "Expanded and cleaned Menu2 page/preview/runtime navigation for onboarding and grouped workflows.",
                        "Updated smoke tests (including hotpath/coldpath coverage) and hardened release helper scripts.",
                        "Extended Menu2/runtime coverage for new UI/locale paths and connected frame, aura, castbar, chat, EventBus, edit-mode, and range-fade behavior.",
                        "Fixed Auras3 positioning after zone transitions so Auras3 layout remains correct after entering a new zone.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta13",
            date = "2026-07-12",
            sections = {
                {
                    title = "Changes",
                    bullets = {
                        "Stabilized Class Power textures, detached power shapes, and targeted unit-frame refreshes.",
                        "Improved class portrait fallbacks for transient and new Blizzard class tokens.",
                        "Smoothed Menu2 visuals, scrolling, menu fonts, and Assistant startup behavior.",
                        "Expanded Assistant parsing, setting navigation, and exact control routing.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta12",
            date = "2026-07-11",
            sections = {
                {
                    title = "Changes",
                    bullets = {
                        "Moved the Assistant back into an optional load-on-demand companion addon to reduce normal MSUF startup and idle overhead.",
                        "Expanded Menu2 and Assistant control coverage, exact setting navigation, search routing, and undo handling.",
                        "Stabilized Edit Mode plus unit, group, aura, spell-effect, and Class Power preview refreshes and layering.",
                        "Added per-resource slot colors and full-resource colors for segmented Class Power displays.",
                        "Reduced duplicate aura work and allocations in large group-frame previews.",
                        "Hardened the two-addon release package and its static validation.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta11",
            date = "2026-07-11",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "One self-contained addon: The Assistant runtime and every locale are again shipped from the main MSUF addon. Installation and release packages no longer depend on separate companion folders.",
                        "Auras, indicators, and previews: Aura styling now reaches Custom 1-3 containers, previews follow configured growth directions, and spell indicators can use animated icon glow as well as full-frame visual effects.",
                        "More reliable group frames: Group health, prediction, status, connection, roster, and combat state refreshes now share a consistent lifecycle, including AI-controlled party members.",
                    },
                },
                {
                    title = "Packaging And Locales",
                    bullets = {
                        "Folded the former Load-on-Demand Assistant and non-English locale companion addons back into the primary MSUF TOC. Inactive locale files still return immediately, so only the active language dictionary remains resident.",
                        "Simplified release, CurseForge, and Perfy package staging to ship and validate one addon folder and TOC.",
                        "Updated static validation for the unified package layout and removed obsolete companion-addon package metadata.",
                    },
                },
                {
                    title = "Aura Designer, Spell Indicators, And Menu2",
                    bullets = {
                        "Added a container selector to Aura Styling for Buffs, Debuffs, and Custom 1-3 containers. Custom-container styling is stored per unit-frame scope and now has a dedicated preview configuration.",
                        "Improved Aura and Group Aura previews: configured growth direction, spacing, rows/columns, duration bars, borders, timers, and custom-container spell icons are represented more faithfully.",
                        "Added animated glow for icon spell indicators, strengthened full-frame effect cleanup, and avoid duplicate geometry/visual passes while aura slots refresh.",
                        "Refined group aura controls, compact group-style navigation, control catalog metadata, menus, navigation, widgets, themes, and preview lifecycle behavior.",
                    },
                },
                {
                    title = "Assistant",
                    bullets = {
                        "Made result follow-ups fail closed: a pronoun or ordinal from a search result cannot mutate a setting until the result is explicitly selected or explained.",
                        "Improved guided setup, pending-result selection, no-change action handling, undo/history behavior, diagnostics, parser coverage, aura blacklist/filter actions, and setting-graph routing.",
                        "Expanded Assistant knowledge and control registrations for the updated aura, group-frame, text, and visual settings.",
                    },
                },
                {
                    title = "Unit, Group, Castbar, And Resource Runtime",
                    bullets = {
                        "Added detailed-health handling for AI-controlled group members and shared that authoritative health state with prediction, status, and gone/offline visual updates.",
                        "Tightened prediction calculator reuse to a single core dispatch, added group lifecycle refresh events, and split health/connection fast paths from full prediction refreshes.",
                        "Improved group runtime combat-state publication, post-roster frame-state refreshes, range fading, frame visuals, previews, text formatting/runtime, portrait/power/status elements, and core refresh coordination.",
                        "Refined focus interrupt/kick presentation and Class Power controller/mode behavior; updated fonts and Edit Mode movers to keep live frames and previews aligned.",
                    },
                },
                {
                    title = "What To Test First",
                    bullets = {
                        "Start MSUF with a non-English client and open Menu2 and the Assistant; confirm both work directly from the single installed addon folder.",
                        "Configure Custom 1-3 aura styling, directional aura growth, spell-indicator icon glow, and full-frame effects in unit and group previews.",
                        "Test AI party members, roster changes, reconnects, combat transitions, range fading, health/prediction bars, and group status overlays.",
                        "In the Assistant, search for a setting, then try a pronoun/ordinal follow-up before and after selecting a result; only an explicit selection may change a setting.",
                    },
                },
                {
                    title = "Optional Assistant Runtime",
                    bullets = {
                        "Moved the local MSUF Assistant into its own load-on-demand companion addon. The parser, setting graph, knowledge data, and indexes stay unloaded until the Assistant dashboard is opened from Menu2.",
                        "Added a lightweight Menu2 bridge, so normal menu search remains available while the Assistant has zero idle CPU and memory cost outside an active Assistant session. Opening the dashboard now loads and shows the Assistant directly, without a separate start button.",
                        "Improved Assistant request routing, undo/redo, queued work, context handling, diagnostics, and the settings registry; added German/English presentation handling for Assistant dialogs.",
                    },
                },
                {
                    title = "Menu, Search, And Previews",
                    bullets = {
                        "Reworked Menu2 control registration around a shared control catalog and streamlined page/runtime loading.",
                        "Improved pinned and embedded preview ownership so refreshes survive transient visibility changes while navigating or rebuilding menu pages.",
                        "Refined group and unit preview rendering, draggable text/handle behavior, control enablement, search descriptions, and dashboard navigation.",
                    },
                },
                {
                    title = "Unit, Group, And Class Resources",
                    bullets = {
                        "Expanded group-frame configuration and runtime refresh handling for layout, visual layers, borders, text placement, status state, and range fading.",
                        "Improved Class Power controller and mode handling, including Balance Druid resource behavior and more faithful menu previews.",
                        "Updated unit-frame formatting, layers, rounded-frame effects, fonts, textures, and color application paths to keep live frames and previews in sync.",
                    },
                },
                {
                    title = "Aura Filtering",
                    bullets = {
                        "Added an optional Hide permanent auras filter for unit-frame, custom-container, group-frame, and spell-indicator aura candidates.",
                        "Kept blacklist state and its menu/Assistant controls synchronized across the relevant unit and group aura scopes.",
                    },
                },
                {
                    title = "Packaging And Validation",
                    bullets = {
                        "Added the Assistant companion addon to release and Perfy staging, with matching interface/version contract checks.",
                        "Hardened package cleanup and verification to exclude local workflow, graph, cache, and compiled-artifact directories.",
                    },
                },
                {
                    title = "What To Test First",
                    bullets = {
                        "Open Menu2 normally, use regular search, then start the Assistant and verify its dashboard, request handling, undo/redo, and combat-disabled state.",
                        "Navigate quickly between pages and pinned previews; confirm unit and group preview refreshes and drag handles remain responsive.",
                        "Test group layouts, status/text/border settings, range fading, and Class Power previews across relevant specs.",
                        "Toggle Hide permanent auras for unit, custom, and group aura lanes and confirm permanent effects are excluded while timed effects remain.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
