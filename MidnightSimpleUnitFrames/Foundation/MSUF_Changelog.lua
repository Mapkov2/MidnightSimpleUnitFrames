-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.2-beta7",
    previousVersion = "5.2 Beta 6",
    rangeLabel = "5.2 Beta 6 -> 5.2-beta7",
    entries = {
        {
            version = "5.2-beta7",
            date = "2026-05-16",
            sections = {
                {
                    title = "Performance",
                    bullets = {
                        "Fixed buff auras not updating in certain edge cases.",
                        "Added more text positioning options for unit and group frames.",
                        "Improved text container movement controls.",
                        "Potential fix for bug with boss frame debuffs.",
                        "Performance in interrupt module.",
                        "Restored old behavior for auras.",
                    },
                },
                {
                    title = "Bugfixes",
                    bullets = {
                        "Added support for spell indicators and Blizzard rendering at the same time.",
                        "Stopped tracking long raid buffs in Group Frames.",
                        "Improved Group Frame aura filtering so long raid buffs are no longer tracked incorrectly.",
                        "Fixed Group Frame mouseover behavior.",
                        "Fixed some stuff with pinned preview.",
                        "Pinned now fixed.",
                        "Added option to show either or different role icons in group.",
                    },
                },
                {
                    title = "Changes / Improvements",
                    bullets = {
                        "Added class-colored bar background support across unit and group frames.",
                        "Improved tooltip compatibility with other addons.",
                        "Made click-casting on unit frames more robust.",
                        "Added the new rested logo.",
                        "Cleaned up menu test mode when leaving the menu.",
                        "Reverted back to just showing the state of a window enable disable warning.",
                        "Mini refactor of group frame effects file.",
                        "Title clean up.",
                        "Improved new rested logo.",
                    },
                },
            },
        },
        {
            version = "5.2 Beta 6",
            date = "2026-05-16",
            sections = {
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
