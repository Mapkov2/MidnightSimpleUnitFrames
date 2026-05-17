-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.3 Beta 1",
    previousVersion = "5.2",
    rangeLabel = "5.2 -> 5.3 Beta 1",
    entries = {
        {
            version = "5.3 Beta 1",
            date = "2026-05-17",
            sections = {
                {
                    title = "Performance",
                    bullets = {
                        "Improved performance for bar background rendering, text updates, and interrupt-ready handling.",
                        "Added backend compatibility hardening across MSUF modules.",
                        "Refactored core systems including font registration and recolor handling.",
                    },
                },
                {
                    title = "Bugfixes",
                    bullets = {
                        "Fixed detached unit frame outline border not working correctly.",
                        "Fixed player aura helpful classification.",
                        "Fixed Menu2 card enable states.",
                        "Improved dynamic strata handling in Menu2.",
                        "Defaulted tooltips back to Blizzard-controlled behavior for better compatibility.",
                        "Fixed and refined raid group menu behavior.",
                    },
                },
                {
                    title = "Changes / Improvements",
                    bullets = {
                        "Added redesigned Menu2 card layout across unit, group, aura, indicator, bar, and advanced pages.",
                        "Added more Menu2 cards and refined menu structure.",
                        "Added new Menu2 search module and improved search/guidance text.",
                        "Improved guidance for aura buff overrides.",
                        "Improved guidance for name shortening overrides.",
                        "Refined Menu2 switches and range fade controls.",
                        "Added improved on/off switch visuals.",
                        "Added raid group number display next to unit names.",
                        "Updated localization/runtime locale handling.",
                        "Added new UI/media assets for switches and rounded/superellipse visuals.",
                    },
                },
                {
                    title = "Internal / Release",
                    bullets = {
                        "Restricted the release workflow and privatized the release launcher.",
                        "Removed old local publish helper scripts and release helper docs.",
                    },
                },
            },
        },
        {
            version = "5.2",
            date = "2026-05-16",
            sections = {
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
