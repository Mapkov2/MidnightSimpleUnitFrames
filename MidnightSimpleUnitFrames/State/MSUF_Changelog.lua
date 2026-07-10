-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-Beta11",
    previousVersion = "6.0-Beta10",
    rangeLabel = "6.0-Beta10 -> 6.0-Beta11",
    entries = {
        {
            version = "6.0-Beta11",
            date = "2026-07-10",
            sections = {
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
        {
            version = "6.0-Beta8",
            date = "2026-07-09",
            sections = {
                {
                    title = "Group Auras And Spell Indicators",
                    bullets = {
                        "Expanded group-frame tracked aura support so spell-indicator selections can drive tracked buff lanes more reliably.",
                        "Added multi-ID and alias-aware custom aura tracking for spell indicators, including linked aura IDs and custom spell lists.",
                        "Added custom corner indicator aura tracking backed by exact SpellID lists and native AuraContainer filters.",
                        "Added frame-strata support for group aura lanes and spell indicators so tracked buffs, custom indicators, and previews layer more predictably.",
                        "Improved spell-indicator cooldown text sizing and preview rendering for icon, square, bar, and number placements.",
                    },
                },
                {
                    title = "Class Power And Aura Tracking",
                    bullets = {
                        "Reworked ClassPower aura tracking for WoW 12.1 so aura-driven resources update from incremental UNIT_AURA data and full aura scans when needed.",
                        "Fixed Balance Druid Eclipse, Celestial Alignment, and Incarnation tracking for color and Astral Power prediction.",
                        "Improved aura-driven ClassPower modes such as Maelstrom Weapon, Tip of the Spear, Icicles, Demon Hunter soul-fragment states, and Ebon Might.",
                        "Added a short cast-led correction window for Tip of the Spear stacks while Blizzard aura state catches up.",
                    },
                },
                {
                    title = "Health, Absorbs, And Frame State",
                    bullets = {
                        "Fixed absorb and over-absorb layering by syncing prediction bars to safe frame strata and ignoring secret-backed strata values.",
                        "Hardened health, gradient, NPC-type, class-color, and power-color paths against invalid or secret unit tokens.",
                        "Improved dead, offline, and missing-unit health state handling so colors and bars recover cleanly after identity changes.",
                        "Improved CooldownViewer anchoring checks so unavailable or legacy cooldown frames do not force bad late-anchor behavior.",
                    },
                },
                {
                    title = "Group Frames, Range Fade, And Previews",
                    bullets = {
                        "Fixed group range fade and offline alpha updates with an event-driven range driver for active visible party and raid units.",
                        "Updated range/offline registration after group-frame identity changes, hide/show transitions, and combat-deferred settle passes.",
                        "Fixed group preview text dragging so name, health text, and power text handles update cleanly while moving.",
                        "Improved group page previews so live group frames are preserved when they already cover the selected party or raid scope.",
                        "Removed targeted-spell cooldown text from live, preview, and test paths.",
                    },
                },
                {
                    title = "Menu2 And Assistant",
                    bullets = {
                        "Updated Group Indicators and Group Auras controls for custom aura tracking, strata/layer handling, and tracked-buff previews.",
                        "Improved Assistant routing for group aura lanes, spell indicators, text dragging, frame ordering, and health/status settings.",
                        "Tightened group status registry coverage and menu search wiring for the updated indicator and aura paths.",
                    },
                },
                {
                    title = "What To Test First",
                    bullets = {
                        "Party and raid tracked buffs from spell-indicator selections, especially custom multi-ID entries and linked aura IDs.",
                        "Custom corner indicators with exact SpellID lists and helpful/harmful filter choices.",
                        "Range fade and offline alpha after roster changes, party-to-raid conversion, hide/show, combat, and /reload.",
                        "Absorb, heal-absorb, and over-absorb bars with normal, reverse, clamp, and follow modes.",
                        "Balance Druid Eclipse colors and aura-driven ClassPower resources on specs that use aura stacks or timers.",
                        "Group preview dragging for name, health text, power text, aura, and spell-indicator handles.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
