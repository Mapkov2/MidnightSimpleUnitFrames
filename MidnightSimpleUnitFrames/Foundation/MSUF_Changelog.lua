-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.2 Beta 4",
    previousVersion = "5.2 Beta 3",
    rangeLabel = "5.2 Beta 3 -> 5.2 Beta 4",
    entries = {
        {
            version = "5.2 Beta 4",
            date = "2026-05-16",
            sections = {
                {
                    title = "Performance",
                    bullets = {
                        "Group Frames, Menu / Dashboard: Massive rework of spell indicators now performant and gated between speces (9443f77; GroupFrames/MSUF_GF_Effects.lua, GroupFrames/MSUF_GF_SpellIndicators.lua, Menu2/Pages/MSUF_Menu2_GroupIndicators.lua).",
                        "Improved combat-aware update handling across auras, power bars, borders, castbars, portraits, status indicators, unit frames, and group frames.",
                        "Reduced unnecessary refresh work during combat, menu preview updates, aura rendering, and group frame effects.",
                        "Improved preview update behavior for unit frames, group frames, and castbars so menu changes feel smoother.",
                        "Restored and polished the one-click installer flow.",
                        "Fixed buff auras not updating in certain edge cases.",
                        "Added more text positioning options for unit and group frames.",
                        "Improved text container movement controls.",
                    },
                },
                {
                    title = "Bugfixes",
                    bullets = {
                        "Unit Auras: Fixed buff auras not updating in certain edge cases (6f0fd9f; Auras2/MSUF_A2_Core.lua).",
                        "Fixed several group frame, aura preview, and menu issues that could cause inconsistent previews or stale UI state.",
                        "Fixed additional Midnight beta combat restrictions by avoiding unsafe updates while combat lockdown is active.",
                        "Improved aura reminder, border, castbar, status icon, and interrupt-ready handling for safer beta behavior.",
                        "Made click-casting on unit frames more reliable.",
                        "Added support for spell indicators and Blizzard rendering at the same time.",
                        "Stopped tracking long raid buffs in Group Frames.",
                        "Improved Group Frame aura filtering so long raid buffs are no longer tracked incorrectly.",
                        "Fixed Group Frame mouseover behavior.",
                    },
                },
                {
                    title = "Changes / Improvements",
                    bullets = {
                        "# Changelog",
                        "## Performance",
                        "Improved overall addon performance and behavior.",
                        "Improved aura and reminder behavior.",
                        "Improved Group Frame range fade and highlight behavior.",
                        "Improved menu and dashboard performance.",
                        "Improved coalescing behavior in menus and related systems.",
                        "Improved pass-through behavior.",
                        "## Bugfixes",
                        "Fixed additional Midnight beta combat restrictions by avoiding unsafe updates while combat lockdown is active.",
                        "Fixed issues affecting general addon behavior.",
                        "Fixed Group Frame mouseover behavior.",
                        "Improved tooltip compatibility with other addons.",
                        "Made click-casting on unit frames more robust.",
                        "Cleaned up menu test mode when leaving the menu.",
                        "## Changes / Improvements",
                        "Improved Group Frame and Unit Frame menu previews.",
                        "Added a clearer UX for moving text containers together or individually.",
                        "Made it possible to use spell indicators and Blizzard rendering at the same time.",
                        "Improved Spell Indicator behavior, including restored Power Infusion tracking.",
                        "Improved Blessing of Freedom handling.",
                        "Added class-colored bar background support across unit frames and group frames.",
                        "Improved the new Rested symbol / logo for both Classic and Midnight-style rested indicators.",
                        "Improved the menu and dashboard experience with clearer, more user-friendly behavior.",
                        "Improved Class Power setup and brought back the one-click installer.",
                        "Improved castbar preview behavior, boss castbar preview text, and castbar anchoring.",
                        "Improved Edit Mode mover and popup behavior.",
                        "Made the Group Frame preview pinnable to make scrolling easier.",
                        "Reverted the window enable/disable warning to only show the current window state.",
                        "Prepared the addon for the 5.2 Beta 1 release.",
                        "## Release / Tooling",
                        "Updated the release notes shown in the in-game dashboard.",
                        "Improved release tooling and changelog generation.",
                        "## Documentation",
                        "Updated documentation and release notes.",
                        "Menu / Dashboard: Way better preview for GF UF menu (5b792da; Menu2/Pages/MSUF_Menu2_UnitPreview.lua, Menu2/Pages/MSUF_Menu2_UnitSections.lua).",
                        "Menu / Dashboard: More clearer container movement of text in ux . Together or individuell (dd30ddd; Menu2/Pages/MSUF_Menu2_GroupBars.lua, Menu2/Pages/MSUF_Menu2_GroupPreview.lua, Menu2/Pages/MSUF_Menu2_UnitPreview.lua +1 more).",
                        "Group Frames: Made it possible to use spell indicator and blizzard rendering at the same time (b1dd6b3; GroupFrames/MSUF_GF_SpellIndicators.lua).",
                        "Group Frames, Menu / Dashboard: Added blessing of freedom (a707802; GroupFrames/MSUF_GF_SpellIndicators_Data.lua, Menu2/Pages/MSUF_Menu2_GroupPreview.lua).",
                        "Menu / Dashboard: Made it possible that group preview is pinned so scrolling is way easier (b594bdc; Menu2/MSUF_Menu2_Widgets.lua, Menu2/Pages/MSUF_Menu2_GroupPreview.lua, Menu2/Pages/MSUF_Menu2_UnitSections.lua).",
                        "Group Frames: Massively improved spell indicator. For exmaple PI tracking is back (a3724e7; GroupFrames/MSUF_GF_Effects.lua, GroupFrames/MSUF_GF_SpellIndicators.lua, GroupFrames/MSUF_GF_SpellIndicators_Data.lua).",
                        "Menu / Dashboard: Some stuff (ec459a1; Menu2/MSUF_Menu2_Widgets.lua, Menu2/Pages/MSUF_Menu2_GroupPreview.lua, Menu2/Pages/MSUF_Menu2_UnitSections.lua).",
                        "Unit Auras, Core Runtime: Added better tooltip support for other addons. Ex. TipTac (084598a; Auras2/MSUF_A2_Core.lua, Core/MSUF_ChatAndTooltips.lua, MidnightSimpleUnitFrames.lua).",
                        "Foundation, Group Frames, Menu / Dashboard: Added coalescence and some other menu stuff (6642696; Foundation/MSUF_Defaults.lua, GroupFrames/MSUF_GF_Auras.lua, GroupFrames/MSUF_GF_Effects.lua +3 more).",
                        "Group Frames: Better pass through (40ed3a9; GroupFrames/MSUF_GF_Auras.lua).",
                        "Added the new Rested symbol for both Classic and Midnight-style rested indicators.",
                        "Improved unit frame and group frame previews so layout, colors, castbars, and aura changes are easier to verify before applying.",
                        "Improved advanced color, global, profile, group layout, group aura, group indicator, and unit settings pages.",
                        "Improved group frame rendering, spell indicators, aura previews, and range/highlight behavior.",
                        "Updated bundled changelog support so the in-game dashboard can show the 5.2 Beta 1 notes.",
                        "Added class-colored bar background support across unit and group frames.",
                        "Added the new rested logo.",
                        "Reverted back to just showing the state of a window enable disable warning.",
                    },
                },
                {
                    title = "Release / Tooling",
                    bullets = {
                        "Release / Tooling, Core Runtime, Unit Text: More text options and better text preview (2dd1510; CHANGELOG.md, Core/MSUF_Alpha.lua, Core/MSUF_FontRuntime.lua +13 more).",
                        "Release / Tooling, Foundation, Group Frames: Way more text options for unitframe and groupframe. Can move now 3 container via x und y (b915bee; CHANGELOG.md, Foundation/MSUF_Changelog.lua, Foundation/MSUF_Defaults.lua +7 more).",
                        "Release / Tooling, Menu / Dashboard: Made pinning possible (4095725; CHANGELOG.md, Foundation/MSUF_Changelog.lua, Menu2/MSUF_Menu2_Widgets.lua +2 more).",
                        "Release / Tooling: Changelog for beta 2 (56fc05f; CHANGELOG.md, Foundation/MSUF_Changelog.lua, docs/RELEASE_HELPER.md +1 more).",
                    },
                },
                {
                    title = "Documentation",
                    bullets = {
                        "Performance workflow.",
                    },
                },
            },
        },
        {
            version = "5.2 Beta 3",
            date = "2026-05-16",
            sections = {
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
