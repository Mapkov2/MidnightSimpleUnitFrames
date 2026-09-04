-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "D55CAF7AC6118F8FFB3469BD4028A68D2CB65222FC072DA32AE27F9E01F6DDE4",
    currentVersion = "6.15-beta5",
    historyFromVersion = "6.15-beta2",
    previousVersion = "6.15-beta4",
    rangeLabel = "6.15-beta4 -> 6.15-beta5",
    entries = {
        {
            version = "6.15-beta5",
            date = "2026-09-04",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Auras are visible and recover reliably again in the Retail 12.1 Beta. Open Player Auras at Buffs > Layout to review the visible Aura lane.",
                            link = {
                                pageKey = "uf_player",
                                query = "player buff aura layout visible",
                                label = "Player Auras",
                                sectionId = "auras",
                                controlId = "menu2.uf_player.auras.unit-workspace.container-selector",
                                settingKey = "auras3.player.buff.visible",
                                prepareKind = "unitAuraWorkspace",
                                prepareValue = "buff_layout",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "The CurseForge Beta is explicitly published for Retail 12.1.0 while the source retains guarded compatibility with the newer 12.1.5 native contracts.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Aura recovery remains inside its factory-owned runtime and retains the native 12.1 hook contracts across refreshes, preventing Aura displays from staying empty after an interrupted update.",
                        "Class Resource previews can schedule refreshes again after Menu lifecycle cancellation, so their movement and position controls continue to update after settings changes.",
                        "Extended the Aura and Menu interaction smokes for both fixes.",
                    },
                },
            },
        },
        {
            version = "6.15-beta4",
            date = "2026-09-04",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Retail Aura displays recover instead of remaining disabled when a full refresh exceeds the Lua execution budget.",
                            linkless = true,
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Retired the complete pre-6.0 profile conversion path and its legacy import controls. Every MSUF 6.x schema-600 profile and the 6.x Wago envelope remain supported; older or unversioned stored profiles are archived instead of being normalized into the active profile list.",
                        "Added the Retail 12.1.5 Aura, castbar, scheduling, tooltip-caster and native pixel-rounding contracts while retaining explicit TOC compatibility with Retail 12.0.7 and 12.1.0.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Full Aura refreshes batch identity-event topology once and arm their next-frame recovery before synchronous work, so a script ran too long abort cannot leave every later Aura refresh permanently latched as pending.",
                        "Shared next-frame and delayed-signal scheduling replace repeated one-shot timer allocation on supported clients, with the existing timer fallback retained for Retail 12.0.7 and 12.1.0.",
                    },
                },
            },
        },
        {
            version = "6.15-beta3",
            date = "2026-09-03",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "The Assistant now understands requests that name one unit frame and then describe the result. \"Show the PvP flag on my target frame\", \"put the portrait on the left of my player frame\" or \"the name on my player frame is too small\" resolve against that frame's own controls instead of the frame's master toggle or a single matching word.",
                            linkless = true,
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Questions about one control of one unit frame are answered with that control - its page, what it does and its current value - instead of a page-level overview. \"Don't show raid markers on my player frame\" is read as a hide command, and \"upwards\"/\"downwards\" now reach the movement lanes.",
                        "Out of range opacity, Texture Layer opacity and Portrait opacity are no longer written to the health bar's opacity.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Aura owners that cannot be visible for the current unit stop parsing every UNIT_AURA update: the native registration is dropped while the owner is ineligible and Blizzard's own reparse restores it, and the spell-name resolver only listens per unit while an active owner still has names to resolve.",
                        "Cleanse and Purge borders draw in the Frame Outline layer band at the Borders highlight detail, so the live border lands exactly where the Cleanse test border draws.",
                        "Unit Frame dispel borders follow Blizzard's own assist check and only appear on units you can dispel; the Purge marker and \"cast by me\" sensors keep their previous behaviour, and exact-ID group aura lanes drop a native owner per unit on 12.1.",
                        "The dead and offline health background now follows secret health values on Group Frames instead of lagging behind the real state.",
                        "Preserved raid groups take one authoritative roster snapshot per header setup instead of one per block, and the number of laid-out blocks follows the roster so a raid using more subgroups than the configured column limit no longer fills a different grid than it draws.",
                    },
                },
            },
        },
        {
            version = "6.15-beta2",
            date = "2026-09-02",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Raid and Mythic Raid role sorting can now span the entire raid. Enable Sort roles across entire raid under Frames > Party/Raid Frames > Layout > Sorting to order tanks, healers, and damage dealers across the whole raid instead of within each raid group, including with Preserve raid groups.",
                            linkless = true,
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added Sort roles across entire raid to Raid and Mythic Raid sorting with defaults, profile copy, locales, search, and Assistant support. By Role with Preserve raid groups and Group + Role follow the raid-wide order; Party is unaffected.",
                        "The Boss Preview now renders incoming heal, absorb, and heal-absorb bars plus the absorb text so prediction settings can be judged without a live boss.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Raid role sorting stays fully out of combat: the raid-wide order is rebuilt only when roles or the roster change outside combat, and Blizzard's secure header applies it natively.",
                        "Tidied the Group Layout Sorting card so the Sort Mode dropdown and its toggles sit evenly inside the card.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
