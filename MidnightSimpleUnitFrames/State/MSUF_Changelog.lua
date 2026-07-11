-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-Beta12",
    previousVersion = "6.0-Beta11",
    rangeLabel = "6.0-Beta11 -> 6.0-Beta12",
    entries = {
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
        {
            version = "6.0-Beta10",
            date = "2026-07-10",
            sections = {
                {
                    title = "Unit Frame Auras - Blacklists And Whitelists",
                    bullets = {
                        "Buff and Debuff blacklists are frame-specific: add exact SpellIDs manually or from a preset, review the prepared entries, and click an entry to remove it.",
                        "Custom Aura containers use their own exact SpellID whitelist, so only the spells you add enter that custom container.",
                        "Blacklists and Custom-Aura whitelists stay local to the selected Unit Frame even when its normal Blizzard filter tokens inherit the Shared configuration.",
                        "Aura setting changes now recompile the affected Unit Frame and refresh its preview immediately; configured aura-lane offsets are also preserved in the preview.",
                    },
                },
                {
                    title = "Group Frame Auras - Blacklists And Whitelists",
                    bullets = {
                        "Party, Raid, and Mythic Raid aura lanes now use focused Layout, Filters, and Blacklist workspaces.",
                        "Group Buff and Debuff lanes support category blacklists plus exact SpellID blacklists; add individual spells or complete preset groups, see the active list with icons, and click an entry to remove it.",
                        "Native Blizzard filter tokens remain available per group lane. Tracked helpful auras use exact SpellID include filters where Blizzard supports them.",
                        "Private-aura controls were removed from the group-aura UI and Assistant because they are no longer part of the supported group-frame configuration.",
                    },
                },
                {
                    title = "Power Bars And Class Resources",
                    bullets = {
                        "Player Power, Class Resources, and Alternative Mana gain independently configurable native smooth fill using Blizzard StatusBar interpolation.",
                        "Player Power uses frequent power events for responsive updates, while restricted values remain in Blizzard's native StatusBar path.",
                        "Detached Player Power can use Bar, Round, Crystal, or Orb shapes with configurable borders; texture, background, gradient, and tint updates preserve the selected shape.",
                        "Class Resource previews now match live cooldown-based width modes.",
                    },
                },
                {
                    title = "Runtime, Castbars, And Previews",
                    bullets = {
                        "Target and Focus castbars clear stale casts before the replacement update is queued, preventing the old unit's cast from remaining visible during a swap.",
                        "Target-of-target and focus-target identity work is coalesced after target-change event bursts.",
                        "Player portraits now force a native refresh when entering or leaving a vehicle, even though the player GUID itself does not change.",
                        "Pinned menu previews use a simpler canvas host, and group/unit aura controls retain their scroll position during workspace rebuilds.",
                    },
                },
                {
                    title = "What To Test First",
                    bullets = {
                        "Unit-frame Buff and Debuff blacklists: manual SpellIDs, preset additions, removals, Shared-filter inheritance, and preview updates.",
                        "Custom Unit Aura whitelist containers with exact SpellIDs and native filter toggles.",
                        "Party, Raid, and Mythic Raid Buff/Debuff blacklists: category switches, exact SpellIDs, presets, and the active entry list.",
                        "Detached Player Power shapes, borders, colors, smooth fill, and texture changes; Class Resource and Alternative Mana smooth fill.",
                        "Rapid target/focus changes, target-of-target/focus-target updates, and pinned menu previews.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta9",
            date = "2026-07-09",
            sections = {
                {
                    title = "Runtime Fixes",
                    bullets = {
                        "Fixed target portrait refreshes so portrait textures and model state recover more reliably after target, configuration, and preview changes.",
                        "Fixed self-heal prediction calculation paths so player-driven incoming-heal prediction no longer double-counts or drops the local contribution in test scenarios.",
                        "Fixed absorb prediction refresh behavior for menu test mode and forced prediction updates, including absorb, heal-absorb, over-absorb, and prediction visibility state.",
                    },
                },
                {
                    title = "Auras3 And Load Order",
                    bullets = {
                        "Embedded the Auras3 runtime directly into UFCore element loading so aura hooks initialize with the unit-frame backend instead of relying on a separate TOC runtime include.",
                        "Tightened Auras3 edit-mode and performance-trace guards around UFCore frame resolution.",
                    },
                },
                {
                    title = "Menu2 And Previews",
                    bullets = {
                        "Fixed unit preview refresh paths for portrait, absorb, and heal-prediction states after option changes.",
                        "Moved group-frame color controls into the advanced colors page and cleaned up the group bars page so group color settings are easier to find.",
                        "Improved Assistant and menu routing for preview, group layout, group indicators, and color-related requests.",
                    },
                },
                {
                    title = "Release Workflow",
                    bullets = {
                        "Fixed annotated tag parsing for publish-target: curseforge so CurseForge-only beta releases do not accidentally publish to other destinations.",
                    },
                },
                {
                    title = "What To Test First",
                    bullets = {
                        "Target portrait changes after target swaps, /reload, preview toggles, and portrait option changes.",
                        "Absorb, heal-absorb, over-absorb, and incoming-heal previews from the menu test controls.",
                        "Group-frame color settings under Advanced Colors and the removed duplicate controls from Group Bars.",
                        "Auras3 buff and debuff lanes after login and after switching edit/preview modes.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
