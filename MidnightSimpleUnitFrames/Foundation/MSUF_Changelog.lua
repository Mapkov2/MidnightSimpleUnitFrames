-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.72",
    previousVersion = "5.71",
    rangeLabel = "5.71 -> 5.72",
    entries = {
        {
            version = "5.72",
            date = "2026-07-17",
            sections = {
                {
                    title = "Profile Import",
                    bullets = {
                        "Added a dedicated load-on-demand converter for UnhaltedUnitFrames 12.1 profile strings that writes only native MSUF 5.7 profile settings.",
                        "Added best-effort translation for unit, group, aura, castbar, indicator, color, texture, alpha, range, text, and geometry settings where MSUF has a native equivalent.",
                        "Added an explicit import warning, transactional profile handling, conversion reports, and protection against importing into the active profile while UnhaltedUnitFrames is loaded.",
                    },
                },
                {
                    title = "Import Fidelity",
                    bullets = {
                        "Preserved compact Target of Target name and health text, including combined FontStrings, health value modes, positions, font sizes, separators, and dynamic UUF color prefixes.",
                        "Improved imported per-frame foreground, background, absorb, and heal-absorb texture resolution without adding converter work to normal runtime hot paths.",
                        "Added regression coverage for decoding, native-only output, profile integration, geometry, text, castbars, abbreviations, alpha, and range-fade behavior.",
                    },
                },
            },
        },
        {
            version = "5.71",
            date = "2026-07-11",
            sections = {
                {
                    title = "Hotfix",
                    bullets = {
                        "Fixed repeated ADDON_ACTION_FORBIDDEN errors on Warrior login caused by the Whirlwind tracker registering COMBAT_LOG_EVENT_UNFILTERED while Class Resource was disabled.",
                        "Restored the lightweight 5.6 spellcast-driven Whirlwind generator tracking and removed the global combat-log listener.",
                        "Bound Whirlwind tracker events only while the Warrior Class Resource is active and cleanly unbound them when the feature is disabled.",
                    },
                },
            },
        },
        {
            version = "5.70",
            date = "2026-07-08",
            sections = {
                {
                    title = "Patch Highlights",
                    bullets = {
                        "Moved the MSUF2 navigation rail into the 6.0-style layout while keeping the 5.x feature set intact.",
                        "Added optional navigation rail icons for existing profiles, with icons disabled by default for fresh profiles.",
                        "Added smooth menu scrolling with a Misc option to disable it.",
                        "Added scope-aware Frame Outline strata and frame-level offset controls for unit frames and group frames.",
                    },
                },
                {
                    title = "Bug Fixes",
                    bullets = {
                        "Fixed Group Frame Outline geometry so secure-header refreshes cannot reset the outline to the inner bar bounds.",
                        "Fixed Group Frame Outline live refresh so opening or using the options menu no longer requires a reload to apply the outline correctly.",
                        "Fixed Group Frame mouseover, target, and focus highlight strata so selected or hover borders no longer draw over Blizzard panels while aggro and dispel highlights keep their priority.",
                        "Fixed Unit Auras scope override clipping in compact layouts.",
                        "Fixed Class Resource menu clipping issues in compact layouts.",
                        "Fixed navigation rail icon positioning after closing and reopening the menu.",
                        "Restored scope controls on Unit Frames and Group Frames pages after the nav rail layout update.",
                        "Fixed Warrior Whirlwind cleave stacks so the bar only appears after a valid Improved Whirlwind target hit.",
                        "Fixed the GCD castbar path for current WoW cooldown APIs.",
                    },
                },
                {
                    title = "General Changes",
                    bullets = {
                        "Replaced the menu logo with the current MSUF logo.",
                        "Added a WoW 12.1 compatibility warning for MSUF 5.x stable builds that points users to the current CurseForge Beta.",
                        "Kept the new outline strata, frame-level, smooth-scroll, icon, and layout apply work on cold menu paths.",
                        "Kept combat and castbar fixes event-driven and cache-aware without adding constant polling.",
                    },
                },
            },
        },
        {
            version = "5.60",
            date = "2026-06-19",
            sections = {
                {
                    title = "Fixes",
                    bullets = {
                        "Removed the obsolete Important aura filter after WoW 12.0.7.",
                        "Added new aura filters for unit and group frames: Cancelable, Not Cancelable, Raid in Combat, Crowd Control, Big Defensive, External Defensive, and Player Dispellable.",
                        "Fixed group-frame right-click unit menus so the context menu opens directly in instanced combat without needing a prior left-click target selection.",
                    },
                },
            },
        },
        {
            version = "5.59",
            date = "2026-06-13",
            sections = {
                {
                    title = "WoW 12.0.7 Fixes",
                    bullets = {
                        "Fixed compound unit event routing for Target of Target and Focus Target so targettarget and focustarget updates keep health, power, name, and dependent visuals current even when client-specific RegisterUnitEvent filtering falls back to broader unit events.",
                        "Fixed Interrupt Ready box and border repaint caching so secret RGBA values from cooldown color evaluation are never compared in Lua, preventing rare _kickReadyFillR taint errors during target, focus, or boss castbar updates.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
