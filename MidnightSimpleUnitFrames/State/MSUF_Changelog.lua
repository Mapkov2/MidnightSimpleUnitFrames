-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-Beta9",
    previousVersion = "6.0-Beta8",
    rangeLabel = "6.0-Beta8 -> 6.0-Beta9",
    entries = {
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
