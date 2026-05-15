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
            date = "2026-05-15",
            sections = {
                {
                    title = "Performance",
                    bullets = {
                        "Unit Auras: Updated Aura2 event, reminder, or aura handling (working tree; MSUF_A2_Reminder.lua).",
                        "Group Frames: Updated Group Frame effects, range fade, or highlight behavior (working tree; MSUF_GF_Effects.lua).",
                        "Group Frames: Updated Group Frame behavior (working tree; MSUF_GF_Render.lua).",
                        "Interrupt Ready: Updated Interrupt Ready behavior (working tree; MSUF_InterruptReady.lua).",
                        "Unit Auras: Updated Aura2 event, reminder, or aura handling (working tree; MSUF_A2_Render.lua).",
                        "Core Runtime: Updated core runtime behavior (working tree; MSUF_Alpha.lua).",
                        "Foundation: Updated addon behavior (working tree; MSUF_Libs.lua).",
                        "Group Frames: Updated Group Frame effects, range fade, or highlight behavior (working tree; MSUF_GF_Effects.lua).",
                        "Group Frames: Updated Group Frame behavior (working tree; MSUF_GF_SpellIndicators.lua).",
                        "Group Frames: Updated Group Frame behavior (working tree; MSUF_GF_SpellIndicators_Data.lua).",
                        "Menu / Dashboard: Updated menu, dashboard, or live apply behavior (working tree; MSUF_Menu2_Bindings.lua).",
                        "Menu / Dashboard: Updated menu, dashboard, or live apply behavior (working tree; MSUF_Menu2_Theme.lua).",
                        "Menu / Dashboard: Updated menu, dashboard, or live apply behavior (working tree; MSUF_Menu2_Widgets.lua).",
                        "Menu / Dashboard: Updated menu, dashboard, or live apply behavior (working tree; MSUF_Menu2_UnitPreview.lua).",
                        "Menu / Dashboard: Updated menu, dashboard, or live apply behavior (working tree; MSUF_Menu2_UnitSections.lua).",
                        "General: Updated addon behavior (working tree; MidnightSimpleUnitFrames.lua).",
                        "Interrupt Ready: Updated Interrupt Ready behavior (working tree; MSUF_InterruptReady.lua).",
                    },
                },
                {
                    title = "Changes / Improvements",
                    bullets = {
                        "Core Runtime, Foundation, Group Frames: Class color background (3c023d2; Core/MSUF_BarBackgroundRuntime.lua, Core/MSUF_ColorsCore.lua, Core/MSUF_UnitframeCore.lua +2 more).",
                        "Menu / Dashboard: Some user friendly stuff (f4430da; Menu2/MSUF_Menu2_Core.lua, Menu2/MSUF_Menu2_Support.lua, Menu2/Pages/MSUF_Menu2_Advanced.lua +9 more).",
                        "Core Runtime, Foundation, Group Frames: Class color background (3c023d2; Core/MSUF_BarBackgroundRuntime.lua, Core/MSUF_ColorsCore.lua, Core/MSUF_UnitframeCore.lua +2 more).",
                        "Menu / Dashboard: Some user friendly stuff (f4430da; Menu2/MSUF_Menu2_Core.lua, Menu2/MSUF_Menu2_Support.lua, Menu2/Pages/MSUF_Menu2_Advanced.lua +9 more).",
                        "Unit Auras, Bars / Power Bars, Borders / Outlines: Better combat gating for (37613f2; Auras2/MSUF_A2_Reminder.lua, Core/MSUF_Bars.lua, Core/MSUF_Borders.lua +19 more).",
                        "Unit Auras, Bars / Power Bars, Core Runtime: More combat gating (1b3592f; Auras2/MSUF_A2_Render.lua, Core/MSUF_Bars.lua, Core/MSUF_Castbars.lua +11 more).",
                        "Menu / Dashboard, General: Better preview for GF/ UF in the menu (94a019a; Menu2/Pages/MSUF_Menu2_AdvancedColors.lua, Menu2/Pages/MSUF_Menu2_GroupPreview.lua, MidnightSimpleUnitFrames_Castbars/Castbars/MSUF_CastbarPreviews.lua +1 more).",
                        "General: Updated addon behavior (working tree; MSUF_Media.lua).",
                    },
                },
                {
                    title = "Bugfixes",
                    bullets = {
                        "General: Updated addon behavior (working tree; MSUF_Media.lua).",
                        "Menu / Dashboard: Updated menu, dashboard, or live apply behavior (working tree; MSUF_Menu2_GroupLayout.lua).",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
