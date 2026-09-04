-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "D4E06F289AA22B2D84CF10D096A3B96107DAAE09336C38C48D2354E1CE75F2D3",
    currentVersion = "6.15-beta6",
    historyFromVersion = "6.15-beta3",
    previousVersion = "6.14",
    rangeLabel = "6.14 -> 6.15-beta6",
    entries = {
        {
            version = "6.15-beta6",
            date = "2026-09-04",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Absorbs and heal prediction can now stay visible when the health bar is faded into the background. Enable Keep Absorbs + Prediction Visible per Unit Frame or for Party and Raid Frames to keep these overlays at full opacity independently from the health fill.",
                            link = {
                                pageKey = "uf_player",
                                query = "keep absorbs prediction visible",
                                label = "Keep Absorbs + Prediction Visible",
                                sectionId = "transparency",
                                controlId = "menu2.uf_player.unit.transparency.alpha_exclude_prediction_bars",
                                settingKey = "player.alphaExcludePredictionBars",
                            },
                        },
                        {
                            text = "Raid and Mythic Raid role sorting can now span the entire raid. Enable Sort roles across entire raid under Group Layout > Sorting to order tanks, healers, and damage dealers across the whole raid instead of within each raid group.",
                            link = {
                                pageKey = "gf_layout",
                                query = "sort roles across entire raid",
                                label = "Sort roles across entire raid",
                                sectionId = "sorting",
                                controlId = "menu2.gf_layout.group.field.sortrolesacrossraid",
                                settingKey = "gf_raid.sortRolesAcrossRaid",
                                prepareKind = "groupScope",
                                prepareValue = "raid",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added Keep Absorbs + Prediction Visible to Unit Frames and Party/Raid Frames, including profile copy, defaults, previews, search, and Assistant support.",
                        "Added Sort roles across entire raid for Raid and Mythic Raid Frames, including defaults, profile copy, locales, search, and Assistant support. Role sorting can now span the full raid with Preserve raid groups or Group + Role, while Party remains unchanged.",
                        "The Boss Preview now displays incoming heals, absorbs, heal absorbs, and absorb text so prediction settings can be reviewed without a live boss.",
                        "The Assistant now understands plain-language requests about a specific Unit Frame and resolves questions, hide commands, movement directions, and opacity controls against the named frame and control.",
                        "Retired pre-6.0 profile conversion and import controls. Existing MSUF 6.x profiles and 6.x Wago imports remain supported; older or unversioned stored profiles are archived instead of entering the active profile list.",
                        "See New Features can now open the exact Player Aura workspace used by the current Aura highlight.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Health gradients, texture changes, prediction refreshes, Group Range Fade, and the Boss Preview now preserve the configured health and prediction opacity instead of resetting prediction fills to full or faded health opacity.",
                        "Assistant requests for Out of range opacity, Texture Layer opacity, and Portrait opacity now update their own controls instead of changing health-bar opacity.",
                        "Detached Player Power bars attached or width-synced to Class Resources retain their controller-managed anchor while the Class Resource bar is hidden, preventing position and width jumps after shapeshifting.",
                        "Text on detached bar now controls only Power-text placement. It no longer appears disabled merely because Power text is hidden and no longer enables Show power text by itself.",
                        "Aura owners that cannot be visible for the current unit stop parsing UNIT_AURA; their native registration and unresolved-name work resume only when the owner becomes eligible again.",
                        "Cleanse and Purge borders now use the same Frame Outline layer as their preview, Unit Frame dispel borders follow Blizzard's assist rules, and Purge, cast-by-me, and Retail exact-ID Group Aura ownership retain their intended behavior.",
                        "Group Frame dead and offline backgrounds now follow secret health updates without lagging behind the unit's real state.",
                        "Preserved raid groups build and sort one authoritative roster snapshot per secure-header setup. Their rendered block count now follows the same roster, preventing the filled and displayed grids from disagreeing when more subgroups are present than the configured column limit.",
                        "The Group Layout Sorting card now aligns its Sort Mode dropdown and dependent toggles consistently.",
                        "Interrupted full Aura refreshes arm their recovery before synchronous work and can no longer leave later refreshes stuck as pending after a Lua execution-budget abort.",
                        "Aura recovery remains inside the native factory runtime and preserves the Retail 12.1 hook contracts across refreshes, preventing Aura displays from remaining empty after an interrupted update.",
                        "Class Resource previews can schedule refreshes again after Menu lifecycle cancellation, so movement and position controls continue updating after settings changes.",
                    },
                },
            },
        },
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
                        "The CurseForge Beta is explicitly published for Retail 12.1.0.",
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
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Full Aura refreshes batch identity-event topology once and arm their next-frame recovery before synchronous work, so a script ran too long abort cannot leave every later Aura refresh permanently latched as pending.",
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
