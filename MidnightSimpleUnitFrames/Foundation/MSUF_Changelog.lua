-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.59",
    previousVersion = "5.53",
    rangeLabel = "5.53 -> 5.59",
    entries = {
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
        {
            version = "5.53",
            date = "2026-05-26",
            sections = {
                {
                    title = "Critical Fixes",
                    bullets = {
                        "Fixed target, focus, and boss frame alpha/background recovery after combat so frames no longer need a target swap or reload to restore missing backgrounds.",
                        "Fixed post-combat range fade handling so combat end restores cached alpha/background state instead of running an expensive range scan or full alpha refresh.",
                        "Fixed group-frame range fade incorrectly fading the player/self frame by treating the player token and matching player GUID as always in range.",
                        "Fixed stale absorb, shield, and heal-absorb overlays that could stay visible after the target no longer had an active absorb or heal absorb.",
                        "Fixed group-frame secure-button recovery after login, reload, and party/raid changes so blank party or raid frames are reconciled without requiring /reload.",
                        "Fixed CDM/custom-anchor login timing so unit frames keep their cached screen position until Blizzard EditMode or the configured anchor is available, instead of saving wrong UIParent offsets.",
                        "Added a legacy no-op anchor for old Blizzard EditMode layouts that still reference EssentialCooldownViewer_MSA_Container, preventing repeated CDM SetPoint warnings after removing the old MSA dependency.",
                    },
                },
                {
                    title = "Menu and Preview Fixes",
                    bullets = {
                        "Fixed Buff Reminders checkboxes so the full label row is clickable again.",
                        "Fixed Global Ignore List checkboxes and the per-unit override toggle so their click areas match the visible controls.",
                        "Fixed Unit Auras scope/override clipping in compact or scaled menu layouts.",
                        "Fixed Group Frame Aura Display Mode clipping by making the Blizzard aura routing and layering controls responsive in narrow menu layouts.",
                        "Added a castbar size label to the Unit Frame preview so castbar width and height are visible while editing.",
                    },
                },
                {
                    title = "Performance and Stability",
                    bullets = {
                        "Kept alpha/range fixes cached and event-driven, avoiding broad post-combat frame sweeps.",
                        "Kept absorb and heal-absorb cleanup on the existing prediction update paths with secret-safe positive-value checks.",
                        "Improved post-login group-frame recovery through delayed live-frame reconciliation without adding constant polling.",
                        "Kept late anchor recovery event-driven with a short, finite retry window only for profiles that actually use CDM, custom, or unit-frame anchors.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
