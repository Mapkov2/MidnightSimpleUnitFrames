-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.3 Beta 3",
    previousVersion = "5.3 Beta 1",
    rangeLabel = "5.3 Beta 1 -> 5.3 Beta 3",
    entries = {
        {
            version = "5.3 Beta 3",
            date = "2026-05-17",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added Focus Target frame support across unit settings, edit mode, menu previews, copy targets, text options, icons, and runtime refreshes.",
                        "Added Rounded Frames with per-surface controls for unit frames, group frames, bars, highlights, overlays, absorbs, and indicators.",
                        "Bundled all 5.3 Beta changelog entries in the dashboard changelog.",
                        "Restored the Menu2 dashboard preview and scroll behavior to the stable 5.3 Beta 2 layout.",
                    },
                },
                {
                    title = "Performance",
                    bullets = {
                        "Improved bar background, unit text, and Interrupt Ready performance.",
                        "Defaulted rounded frame texture off so the feature has no active runtime callbacks while disabled.",
                        "Reduced unnecessary group frame header rescans during rebuild and layout bursts.",
                        "Reduced redundant castbar re-layout work when width-source geometry has not changed.",
                        "Improved performance for bar background rendering, text updates, and interrupt-ready handling.",
                        "Added backend compatibility hardening across MSUF modules.",
                        "Refactored core systems including font registration and recolor handling.",
                    },
                },
                {
                    title = "Bugfixes",
                    bullets = {
                        "Fixed unit frame detach outline border not working.",
                        "Improved tooltip compatibility with other addons.",
                        "Fixed player aura helpful classification.",
                        "Fixed Menu2 card enable states.",
                        "Improved Menu2 dynamic strata handling.",
                        "Add menu scroll edge bounce.",
                        "Remove menu scroll bounce.",
                        "Restored the Menu2 dashboard preview and scroll behavior to the 5.3 Beta 2 layout.",
                        "Fixed rounded frame texture re-enable behavior after the module manager disables the feature.",
                        "Fixed rounded frame integration for unit and group frame borders, power bars, mouseover highlights, dispel overlays, absorb bars, and indicators.",
                        "Fixed group frame rounded visuals so mouseover and highlight state use the rounded edge instead of square overlays.",
                        "Fixed detached unit frame outline border not working correctly.",
                        "Improved dynamic strata handling in Menu2.",
                        "Defaulted tooltips back to Blizzard-controlled behavior for better compatibility.",
                        "Fixed and refined raid group menu behavior.",
                    },
                },
                {
                    title = "Changes / Improvements",
                    bullets = {
                        "Updated runtime localization coverage.",
                        "Improved on/off switch visuals and added raid group numbers beside unit names.",
                        "Added and refined the Menu2 search module.",
                        "Added core swap recolor runtime support.",
                        "Added centralized font registry support for the unit frame runtime.",
                        "Hardened MSUF backend namespace compatibility across modules.",
                        "Refined Menu2 switches and range fade controls.",
                        "Improved Menu2 search guidance for name shortening overrides.",
                        "Redesigned Menu2 cards across settings pages.",
                        "Improved Menu2 search guidance for aura buff overrides.",
                        "Added more Menu2 cards to group and unit sections.",
                        "Fixed Group Frame mouseover behavior.",
                        "Menu2: hide text badges when collapsed.",
                        "Improved Menu2 switch controls and visual states.",
                        "Redesigned Menu2 cards and expanded card-based settings sections.",
                        "Added Rounded Texture controls under Global Style > Bars with per-surface toggles, search coverage, localization, preview support, and a reload prompt.",
                        "Added rounded mask media for the live unit/group frames and Menu2 preview.",
                        "Added redesigned Menu2 card layout across unit, group, aura, indicator, bar, and advanced pages.",
                        "Added more Menu2 cards and refined menu structure.",
                        "Added new Menu2 search module and improved search/guidance text.",
                        "Improved guidance for aura buff overrides.",
                        "Improved guidance for name shortening overrides.",
                        "Added improved on/off switch visuals.",
                        "Added raid group number display next to unit names.",
                        "Updated localization/runtime locale handling.",
                        "Added new UI/media assets for switches and rounded/superellipse visuals.",
                        "Restricted the release workflow and privatized the release launcher.",
                        "Removed old local publish helper scripts and release helper docs.",
                        "Added class-colored bar background support across unit and group frames.",
                    },
                },
                {
                    title = "Release / Tooling",
                    bullets = {
                        "Improved release changelog tooling and dashboard changelog output.",
                    },
                },
            },
        },
        {
            version = "5.3 Beta 2",
            date = "2026-05-17",
            sections = {
                {
                    title = "Performance",
                    bullets = {
                        "Defaulted rounded frame texture off so the feature has no active runtime callbacks while disabled.",
                        "Reduced unnecessary group frame header rescans during rebuild and layout bursts.",
                        "Reduced redundant castbar re-layout work when width-source geometry has not changed.",
                    },
                },
                {
                    title = "Bugfixes",
                    bullets = {
                        "Fixed rounded frame texture re-enable behavior after the module manager disables the feature.",
                        "Fixed rounded frame integration for unit and group frame borders, power bars, mouseover highlights, dispel overlays, absorb bars, and indicators.",
                        "Fixed group frame rounded visuals so mouseover and highlight state use the rounded edge instead of square overlays.",
                    },
                },
                {
                    title = "Changes / Improvements",
                    bullets = {
                        "Added Rounded Texture controls under Global Style > Bars with per-surface toggles, search coverage, localization, preview support, and a reload prompt.",
                        "Added rounded mask media for the live unit/group frames and Menu2 preview.",
                    },
                },
            },
        },
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
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
