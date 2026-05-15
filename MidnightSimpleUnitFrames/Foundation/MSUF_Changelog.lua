-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.2 Beta 1",
    previousVersion = "",
    rangeLabel = "5.2 Beta 1",
    entries = {
        {
            version = "5.2 Beta 1",
            date = "2026-05-15",
            sections = {
                {
                    title = "Performance",
                    bullets = {
                        "General, Menu / Dashboard: Added back one click installer and tried to make it more pixel perfect (9941279; ClassPower/MSUF_CP_Core.lua, Menu2/Pages/MSUF_Menu2_AdvancedClassPower.lua).",
                    },
                },
                {
                    title = "Bugfixes",
                    bullets = {
                        "General, Group Frames, Menu / Dashboard: Merging some fixes (6fdc22f; ClassPower/MSUF_CP_Core.lua, GroupFrames/MSUF_GF_AuraPreview.lua, Menu2/MSUF_Menu2_Core.lua +5 more).",
                    },
                },
                {
                    title = "Changes / Improvements",
                    bullets = {
                        "Menu / Dashboard: Some user friendly stuff (f4430da; Menu2/MSUF_Menu2_Core.lua, Menu2/MSUF_Menu2_Support.lua, Menu2/Pages/MSUF_Menu2_Advanced.lua +9 more).",
                        "Menu / Dashboard, General: Better preview for GF/ UF in the menu (94a019a; Menu2/Pages/MSUF_Menu2_AdvancedColors.lua, Menu2/Pages/MSUF_Menu2_GroupPreview.lua, MidnightSimpleUnitFrames_Castbars/Castbars/MSUF_CastbarPreviews.lua +1 more).",
                        "Core Runtime: Robuster click casting on unitframe (afbcf82; MidnightSimpleUnitFrames.lua).",
                        "General, Menu / Dashboard: New rested logo (41caf6e; Media/Symbols/Rested/rested_sleep_zzzz_classic_64.tga, Media/Symbols/Rested/rested_sleep_zzzz_midnight_64.tga, Menu2/Pages/MSUF_Menu2_Unit.lua).",
                    },
                },
                {
                    title = "Release / Tooling",
                    bullets = {
                        "Core Runtime, Release / Tooling, Foundation: Class color background (3c023d2; Core/MSUF_BarBackgroundRuntime.lua, Core/MSUF_ColorsCore.lua, Core/MSUF_UnitframeCore.lua +3 more).",
                        "Release / Tooling: Release helper update (869a330; Foundation/MSUF_Changelog.lua, docs/RELEASE_HELPER.md, tools/MSUF-AutoChangelog.cmd +2 more).",
                        "Unit Auras, Bars / Power Bars, Borders / Outlines: Better combat gating for (37613f2; Auras2/MSUF_A2_Reminder.lua, Core/MSUF_Bars.lua, Core/MSUF_Borders.lua +20 more).",
                        "Release / Tooling: Stuff (a9b8adc; CHANGELOG.md, Foundation/MSUF_Changelog.lua, docs/RELEASE_HELPER.md +2 more).",
                        "Release / Tooling, Unit Auras, Bars / Power Bars: More combat gating (1b3592f; CHANGELOG.md, Auras2/MSUF_A2_Render.lua, Core/MSUF_Bars.lua +15 more).",
                        "Release / Tooling, Unit Auras, Core Runtime: Lots of updates (105d2db; CHANGELOG.md, Auras2/MSUF_A2_Render.lua, Core/MSUF_Alpha.lua +18 more).",
                        "Release / Tooling: Performance workflow (e7afdc5; docs/PERFY_WORKFLOW.md).",
                        "Release / Tooling, Core Runtime: Ready for 5.2 beta 1 (7459ba1; CHANGELOG.md, Foundation/MSUF_Changelog.lua, MidnightSimpleUnitFrames.lua).",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
