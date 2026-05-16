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
