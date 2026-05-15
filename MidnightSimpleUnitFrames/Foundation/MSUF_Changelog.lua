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
                        "Bars / Power Bars: Updated bar and power bar behavior (working tree; MSUF_Bars.lua).",
                        "Core Runtime: Updated core runtime behavior (working tree; MSUF_Castbars.lua).",
                        "General: Updated addon behavior (working tree; MSUF_EM2_Core.lua).",
                        "General: Updated addon behavior (working tree; MSUF_EM2_Movers.lua).",
                        "General: Updated addon behavior (working tree; MSUF_EM2_Popups.lua).",
                        "Group Frames: Updated Group Frame behavior (working tree; MSUF_GF_Core.lua).",
                        "Group Frames: Updated Group Frame behavior (working tree; MSUF_GF_EM2.lua).",
                        "Group Frames: Updated Group Frame effects, range fade, or highlight behavior (working tree; MSUF_GF_Effects.lua).",
                        "Menu / Dashboard: Updated menu, dashboard, or live apply behavior (working tree; MSUF_Menu2_UnitPreview.lua).",
                        "General: Updated addon behavior (working tree; MidnightSimpleUnitFrames.lua).",
                        "General: Updated addon behavior (working tree; MSUF_CastbarPreviewEdit.lua).",
                        "General: Updated addon behavior (working tree; MSUF_CastbarPreviews.lua).",
                        "General: Updated addon behavior (working tree; MidnightSimpleUnitFrames_BossCastbars.lua).",
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
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
