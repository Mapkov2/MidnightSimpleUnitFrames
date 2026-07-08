-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.70",
    previousVersion = "5.60",
    rangeLabel = "5.60 -> 5.70",
    entries = {
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
        {
            version = "5.58",
            date = "2026-06-08",
            sections = {
                {
                    title = "Fixes",
                    bullets = {
                        "Fixed missing-health text formatting for imported profiles with secret health values.",
                    },
                },
            },
        },
        {
            version = "5.57",
            date = "2026-06-04",
            sections = {
                {
                    title = "Edge Case Fixes",
                    bullets = {
                        "Fixed a rare health-bar smoothing edge case where preserved HP color could leave a transparent strip while the bar was shrinking.",
                        "Improved Blizzard party-frame fallback behavior when MSUF group frames are disabled, including arena and login/zone-change cases where Blizzard frames could be missing or briefly ghosted while solo.",
                        "Hardened gameplay font application so profiles that reference missing SharedMedia or disabled addon fonts fall back safely instead of producing font asset errors.",
                        "Refreshed group-frame range fade after instance, roster, and combat transitions so players who join or zone into an instance out of combat no longer stay faded as out of range until combat or /reload.",
                        "Improved the missing buff scan for rare readable-aura edge cases.",
                    },
                },
                {
                    title = "Compatibility and Safety",
                    bullets = {
                        "Added a clear WoW 12.1 compatibility warning for MSUF 5.x users, with localized popup and chat messaging that points users to the current Alpha/Beta build for WoW 12.1.",
                        "Kept secret-aura handling conservative while improving missing buff detection.",
                    },
                },
                {
                    title = "Performance Notes",
                    bullets = {
                        "Kept the new range recovery finite and event-driven instead of adding constant polling.",
                        "Kept the missing buff scan on the existing cached aura path where possible.",
                        "Kept the new font and Blizzard-frame safeguards on cold apply/login paths.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
