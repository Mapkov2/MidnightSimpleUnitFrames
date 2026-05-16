-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.2 Beta 2",
    previousVersion = "5.2 Beta",
    rangeLabel = "5.2 Beta -> 5.2 Beta 2",
    entries = {
        {
            version = "5.2 Beta 2",
            date = "2026-05-16",
            sections = {
                {
                    title = "Performance",
                    bullets = {
                        "Core Runtime: Updated core runtime behavior (working tree; MSUF_FontRuntime.lua).",
                        "Unit Text: Updated unit text rendering (working tree; MSUF_Text.lua).",
                        "General: Updated addon behavior (working tree; MSUF_EM2_Popups.lua).",
                        "Foundation: Updated addon behavior (working tree; MSUF_Defaults.lua).",
                        "Menu / Dashboard: Updated menu, dashboard, or live apply behavior (working tree; MSUF_Menu2_Global.lua).",
                        "Menu / Dashboard: Updated menu, dashboard, or live apply behavior (working tree; MSUF_Menu2_GroupPreview.lua).",
                        "Menu / Dashboard: Updated menu, dashboard, or live apply behavior (working tree; MSUF_Menu2_UnitPreview.lua).",
                        "Menu / Dashboard: Updated menu, dashboard, or live apply behavior (working tree; MSUF_Menu2_UnitSections.lua).",
                        "General: Updated addon behavior (working tree; MidnightSimpleUnitFrames.lua).",
                        "Group Frames: Updated Group Frame behavior (working tree; MSUF_GF_DB.lua).",
                        "Group Frames, Menu / Dashboard: Massive rework of spell indicators now performant and gated between speces (9443f77; GroupFrames/MSUF_GF_Effects.lua, GroupFrames/MSUF_GF_SpellIndicators.lua, Menu2/Pages/MSUF_Menu2_GroupIndicators.lua).",
                        "Menu / Dashboard: Updated menu, dashboard, or live apply behavior (working tree; MSUF_Menu2_Widgets.lua).",
                    },
                },
                {
                    title = "Bugfixes",
                    bullets = {
                        "Unit Auras: Fixed buff auras not updating in certain edge cases (6f0fd9f; Auras2/MSUF_A2_Core.lua).",
                        "Menu / Dashboard: Updated menu, dashboard, or live apply behavior (working tree; MSUF_Menu2_AdvancedClassPower.lua).",
                        "Menu / Dashboard: Updated menu, dashboard, or live apply behavior (working tree; MSUF_Menu2_Unit.lua).",
                        "Menu / Dashboard: Updated menu, dashboard, or live apply behavior (working tree; MSUF_Menu2_GroupIndicators.lua).",
                        "Group Frames: Updated Group Frame behavior (working tree; MSUF_GF_SpellIndicators_Data.lua).",
                    },
                },
                {
                    title = "Changes / Improvements",
                    bullets = {
                        "Core Runtime: Updated core runtime behavior (working tree; MSUF_Alpha.lua).",
                        "Menu / Dashboard: Way better preview for GF UF menu (5b792da; Menu2/Pages/MSUF_Menu2_UnitPreview.lua, Menu2/Pages/MSUF_Menu2_UnitSections.lua).",
                        "Core Runtime, Unit Text, General: More text options and better text preview (2dd1510; Core/MSUF_Alpha.lua, Core/MSUF_FontRuntime.lua, Core/MSUF_Text.lua +9 more).",
                        "Foundation, Group Frames, Menu / Dashboard: Way more text options for unitframe and groupframe. Can move now 3 container via x und y (b915bee; Foundation/MSUF_Defaults.lua, GroupFrames/MSUF_GF_DB.lua, GroupFrames/MSUF_GF_Render.lua +5 more).",
                        "Menu / Dashboard: More clearer container movement of text in ux . Together or individuell (dd30ddd; Menu2/Pages/MSUF_Menu2_GroupBars.lua, Menu2/Pages/MSUF_Menu2_GroupPreview.lua, Menu2/Pages/MSUF_Menu2_UnitPreview.lua +1 more).",
                        "Group Frames: Made it possible to use spell indicator and blizzard rendering at the same time (b1dd6b3; GroupFrames/MSUF_GF_SpellIndicators.lua).",
                        "Group Frames, Menu / Dashboard: Added blessing of freedom (a707802; GroupFrames/MSUF_GF_SpellIndicators_Data.lua, Menu2/Pages/MSUF_Menu2_GroupPreview.lua).",
                        "Menu / Dashboard: Made it possible that group preview is pinned so scrolling is way easier (b594bdc; Menu2/MSUF_Menu2_Widgets.lua, Menu2/Pages/MSUF_Menu2_GroupPreview.lua, Menu2/Pages/MSUF_Menu2_UnitSections.lua).",
                        "Group Frames: Massively improved spell indicator. For exmaple PI tracking is back (a3724e7; GroupFrames/MSUF_GF_Effects.lua, GroupFrames/MSUF_GF_SpellIndicators.lua, GroupFrames/MSUF_GF_SpellIndicators_Data.lua).",
                        "Menu / Dashboard: Some stuff (ec459a1; Menu2/MSUF_Menu2_Widgets.lua, Menu2/Pages/MSUF_Menu2_GroupPreview.lua, Menu2/Pages/MSUF_Menu2_UnitSections.lua).",
                    },
                },
            },
        },
        {
            version = "5.2 Beta",
            date = "2026-05-16",
            sections = {
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
