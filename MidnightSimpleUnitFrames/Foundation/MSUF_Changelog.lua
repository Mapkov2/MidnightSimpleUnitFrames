-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.2",
    previousVersion = "",
    rangeLabel = "5.2",
    entries = {
        {
            version = "5.2",
            date = "2026-05-16",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added pinned preview support for the Group/Unitframe Menu.",
                        "Massive improvement to the Dashboard.",
                        "Full rework of all spell indicators, including restored Power Infusion (PI) tracking.",
                        "Added option to turn off or choose specific role icons.",
                    },
                },
                {
                    title = "Performance",
                    bullets = {
                        "Improved interrupt module performance.",
                        "Improved spell indicator performance and spec gating.",
                        "Improved menu, dashboard, and preview performance.",
                        "Reduced unnecessary refresh work during combat, menu preview updates, aura rendering, and group frame effects.",
                        "Improved combat-aware update handling across auras, power bars, borders, castbars, portraits, status indicators, unit frames, and group frames.",
                    },
                },
                {
                    title = "Bugfixes",
                    bullets = {
                        "Fixed buff auras not updating in certain edge cases.",
                        "Fixed Power Infusion (PI) tracking for spell indicators.",
                        "Fixed boss frame debuffs not updating correctly in certain cases.",
                        "Fixed Group Frame aura filtering so long raid buffs are no longer tracked incorrectly.",
                        "Fixed Group Frame mouseover behavior.",
                        "Fixed pinned preview behavior in the Group/Unitframe Menu.",
                        "Fixed a critical Lua error with Group Frame effects.",
                        "Fixed several preview issues that could cause stale or inconsistent UI state.",
                        "Fixed additional Midnight beta combat restrictions by avoiding unsafe updates while combat lockdown is active.",
                        "Fixed aura reminder, border, castbar, status icon, and interrupt-ready handling issues during beta testing.",
                    },
                },
                {
                    title = "Changes / Improvements",
                    bullets = {
                        "Added support for spell indicators and Blizzard rendering at the same time.",
                        "Fully reworked all spell indicators.",
                        "Added Blessing of Freedom support to spell indicators.",
                        "Added class-colored bar background support across unit and group frames.",
                        "Added more text positioning options for unit and group frames.",
                        "Added support for moving three text containers via X and Y positioning.",
                        "Improved text container movement controls.",
                        "Added a clearer UX for moving text containers together or individually.",
                        "Added more text options and better text preview behavior.",
                        "Improved Group Frame and Unit Frame menu previews.",
                        "Added pinned preview support to make Group/Unitframe menu scrolling easier.",
                        "Massively improved the Dashboard experience with clearer, more user-friendly behavior.",
                        "Added option to show all, none, or selected role icons in Group Frames.",
                        "Added toggle to hide advanced settings.",
                        "Stopped tracking long raid buffs in Group Frames.",
                        "Restored old aura behavior.",
                        "Improved tooltip compatibility with other addons, including TipTac.",
                        "Made click-casting on unit frames more robust.",
                        "Improved unit frame and group frame previews so layout, colors, castbars, and aura changes are easier to verify before applying.",
                        "Improved advanced color, global, profile, group layout, group aura, group indicator, and unit settings pages.",
                        "Restored and polished the Class Power one-click installer flow.",
                        "Improved group frame rendering, spell indicators, aura previews, and range/highlight behavior.",
                        "Improved castbar preview behavior, boss castbar preview text, and castbar anchoring.",
                        "Improved Edit Mode mover and popup behavior.",
                        "Cleaned up menu test mode when leaving the menu.",
                        "Reverted the window enable/disable warning to only show the current window state.",
                        "Added the new rested logo.",
                        "Improved the new rested logo.",
                        "Updated bundled changelog support so the in-game dashboard can show the 5.2 notes.",
                        "Made sure to translate the new dashboard.",
                        "Cleaned up titles.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
