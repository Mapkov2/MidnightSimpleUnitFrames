-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.60",
    previousVersion = "5.54",
    rangeLabel = "5.54 -> 5.60",
    entries = {
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
        {
            version = "5.54",
            date = "2026-05-27",
            sections = {
                {
                    title = "Critical Fixes",
                    bullets = {
                        "Fixed Blizzard-rendered group-frame private auras reusing a stale Blizzard settings-change handler after instance or roster transitions.",
                        "Fixed group-frame absorb and heal-absorb overlays drawing over the normal frame outline on party and raid frames.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
