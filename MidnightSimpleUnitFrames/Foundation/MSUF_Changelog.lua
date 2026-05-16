-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.2 Beta 3",
    previousVersion = "5.2 Beta 2",
    rangeLabel = "5.2 Beta 2 -> 5.2 Beta 3",
    entries = {
        {
            version = "5.2 Beta 3",
            date = "2026-05-16",
            sections = {
                {
                    title = "Performance",
                    bullets = {
                        "Improved performance for Group Frames.",
                        "Improved performance for menu and dashboard.",
                    },
                },
                {
                    title = "Changes / Improvements",
                    bullets = {
                        "Improved Not tracking long raidbuffs anymore in group frames.",
                        "Improved Turn off test mode if you leave main menu.",
                    },
                },
            },
        },
        {
            version = "5.2 Beta 2",
            date = "2026-05-16",
            sections = {
                {
                    title = "Performance",
                    bullets = {
                        "Group Frames, Menu / Dashboard: Massive rework of spell indicators now performant and gated between speces (9443f77; GroupFrames/MSUF_GF_Effects.lua, GroupFrames/MSUF_GF_SpellIndicators.lua, Menu2/Pages/MSUF_Menu2_GroupIndicators.lua).",
                    },
                },
                {
                    title = "Bugfixes",
                    bullets = {
                        "Unit Auras: Fixed buff auras not updating in certain edge cases (6f0fd9f; Auras2/MSUF_A2_Core.lua).",
                    },
                },
                {
                    title = "Changes / Improvements",
                    bullets = {
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
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
