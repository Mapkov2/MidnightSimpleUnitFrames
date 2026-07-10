-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-Beta10",
    previousVersion = "6.0-Beta9",
    rangeLabel = "6.0-Beta9 -> 6.0-Beta10",
    entries = {
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
