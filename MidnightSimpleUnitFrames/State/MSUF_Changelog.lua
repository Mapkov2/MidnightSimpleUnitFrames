-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "2DEAB0E75FCB11F9EDF602B097DA2CF814E32AE80D4068F883F4B3EA1BC8A17A",
    currentVersion = "6.15-beta7",
    historyFromVersion = "6.15-beta4",
    previousVersion = "6.15-beta6",
    rangeLabel = "6.15-beta6 -> 6.15-beta7",
    entries = {
        {
            version = "6.15-beta7",
            date = "2026-09-05",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Busy group combat now spends less time updating health gradients, dynamic backgrounds, protected text, Aura fallback state, and Range Fade timers. Existing colors, status transitions, unresolved-Aura discovery, and range sampling behavior are preserved.",
                            link = {
                                pageKey = "opt_colors",
                                query = "health gradient",
                                label = "Health Gradient",
                                sectionId = "colors_appearance",
                                controlId = "menu2.opt.colors.advanced.appearance.gradient.enabled",
                                settingKey = "general.enableHealthGradient",
                            },
                        },
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Health gradients now reuse bounded native scalar curves for their RGB channels, avoid per-update ColorMixin allocation, and keep constant channels out of the native evaluation path.",
                        "Group health updates no longer repeat an already completed dynamic-background refresh or enter an empty color handoff after the background has been painted.",
                        "Dynamic health backgrounds cache stable alpha inputs and known cache keys, use the native secret-value predicate when available, and forward protected colors directly to their supported rendering sink.",
                        "Protected current, maximum, and percentage text modes now use compiled single-value writers instead of the general multi-value formatter.",
                        "Unresolved Aura fallback scans no longer resynchronize an unchanged active-work state, while later Aura discovery, owner reactivation, and unregister cleanup remain intact.",
                        "Group death-background updates skip cache probes that cannot be reused outside an active frame dispatch while retaining fresh native death and resurrection checks.",
                        "Range Fade keeps an earlier timer when its logical deadline moves later, reducing timer replacement churn without moving range checks or alpha changes forward.",
                    },
                },
            },
        },
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
