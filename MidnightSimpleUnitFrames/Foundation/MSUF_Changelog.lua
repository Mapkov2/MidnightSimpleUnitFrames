-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.2 Beta 6",
    previousVersion = "5.2 Beta 5",
    rangeLabel = "5.2 Beta 5 -> 5.2 Beta 6",
    entries = {
        {
            version = "5.2 Beta 6",
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
                    },
                },
            },
        },
        {
            version = "5.2 Beta 5",
            date = "2026-05-16",
            sections = {
                {
                    title = "Performance",
                    bullets = {
                        "Improved overall addon performance and behavior.",
                        "Improved combat-aware update handling across auras, power bars, borders, castbars, portraits, status indicators, unit frames, and group frames.",
                        "Reduced unnecessary refresh work during combat, menu preview updates, aura rendering, and group frame effects.",
                        "Improved aura and reminder behavior.",
                        "Improved Group Frame range fade and highlight behavior.",
                        "Improved menu and dashboard performance.",
                        "Improved coalescing behavior in menus and related systems.",
                        "Improved pass-through behavior.",
                        "Improved preview update behavior for unit frames, group frames, and castbars so menu changes feel smoother.",
                        "Improved spell indicator performance and gating between specs.",
                        "Restored and polished the Class Power one-click installer flow.",
                        "Improved text positioning options for unit frames and group frames.",
                        "Improved text container movement controls.",
                    },
                },
                {
                    title = "Bugfixes",
                    bullets = {
                        "Fixed additional Midnight beta combat restrictions by avoiding unsafe updates while combat lockdown is active.",
                        "Fixed buff auras not updating in certain edge cases.",
                        "Fixed several group frame, aura preview, and menu issues that could cause inconsistent previews or stale UI state.",
                        "Fixed Group Frame mouseover behavior.",
                        "Improved aura reminder, border, castbar, status icon, and interrupt-ready handling for safer beta behavior.",
                        "Made click-casting on unit frames more reliable.",
                        "Improved tooltip compatibility with other addons, including TipTac.",
                        "Stopped long raid buffs from being tracked incorrectly in Group Frames.",
                        "Cleaned up menu test mode when leaving the menu.",
                        "Reverted the window enable/disable warning to only show the current window state.",
                    },
                },
                {
                    title = "Changes / Improvements",
                    bullets = {
                        "Improved Group Frame and Unit Frame menu previews.",
                        "Made Group Frame previews pinnable to make scrolling easier.",
                        "Added a clearer UX for moving text containers together or individually.",
                        "Added more text options and better text preview behavior.",
                        "Added support for moving three text containers via X and Y positioning.",
                        "Made it possible to use spell indicators and Blizzard rendering at the same time.",
                        "Massively improved spell indicators, including restored Power Infusion tracking.",
                        "Added Blessing of Freedom support.",
                        "Added class-colored bar background support across unit frames and group frames.",
                        "Added the new Rested symbol / logo for both Classic and Midnight-style rested indicators.",
                        "Improved unit frame and group frame previews so layout, colors, castbars, and aura changes are easier to verify before applying.",
                        "Improved advanced color, global, profile, group layout, group aura, group indicator, and unit settings pages.",
                        "Improved the menu and dashboard experience with clearer, more user-friendly behavior.",
                        "Improved Class Power setup and brought back the one-click installer.",
                        "Improved group frame rendering, spell indicators, aura previews, and range/highlight behavior.",
                        "Improved castbar preview behavior, boss castbar preview text, and castbar anchoring.",
                        "Improved Edit Mode mover and popup behavior.",
                        "Updated bundled changelog support so the in-game dashboard can show the 5.2 Beta notes.",
                        "Prepared the addon for the 5.2 Beta release.",
                    },
                },
                {
                    title = "Release / Tooling",
                    bullets = {
                        "Updated the release notes shown in the in-game dashboard.",
                        "Improved release tooling and changelog generation.",
                        "Added changelog support for the 5.2 Beta release.",
                        "Updated release helper documentation.",
                    },
                },
                {
                    title = "Documentation",
                    bullets = {
                        "Updated documentation and release notes.",
                        "Added performance workflow documentation.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
