-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "EE3102C27FCA47B1989F052C0D3220103EFFD5DDC2CF4D5428E8D86081B14D91",
    currentVersion = "6.151",
    historyFromVersion = "6.15-beta6",
    previousVersion = "6.15-beta6",
    rangeLabel = "6.15-beta6 -> 6.151",
    entries = {
        {
            version = "6.151",
            date = "2026-09-06",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Highlight borders work reliably again on rounded frames and respect the configured border thickness.",
                            link = {
                                pageKey = "opt_bars",
                                query = "rounded frame texture",
                                label = "Rounded frame texture",
                                sectionId = "bars_rounded",
                                controlId = "menu2.opt.bars.global.rounded.rounded.frames.enabled",
                                settingKey = "bars.roundedFramesEnabled",
                            },
                        },
                    },
                },
                {
                    title = "Fixes",
                    bullets = {
                        "Restored rounded highlight startup and layering, including support for border thickness up to 30.",
                        "Dispel and Purge borders now apply their configured thickness on all frame shapes and refresh immediately after Menu changes.",
                        "Group Frame highlight detection keeps working when Aura icons are disabled, and Any dispel type also works on enemy units.",
                    },
                },
            },
        },
        {
            version = "6.15",
            date = "2026-09-05",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Absorbs and heal prediction can stay visible when the health bar is faded into the background. Enable Keep Absorbs + Prediction Visible per Unit Frame or for Party and Raid Frames to keep these overlays at full opacity independently from the health fill.",
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
                            text = "Raid and Mythic Raid role sorting can span the entire raid. Enable Sort roles across entire raid under Group Layout > Sorting to order tanks, healers, and damage dealers across the whole raid instead of within each raid group.",
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
                        "The Boss Preview displays incoming heals, absorbs, heal absorbs, and absorb text so prediction settings can be reviewed without a live boss.",
                        "The Assistant understands plain-language requests about a specific Unit Frame and resolves questions, hide commands, movement directions, and opacity controls against the named frame and control.",
                        "Retired pre-6.0 profile conversion and import controls. Existing MSUF 6.x profiles and 6.x Wago imports remain supported; older or unversioned stored profiles are archived instead of entering the active profile list.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Health gradients, texture changes, prediction refreshes, Group Range Fade, and the Boss Preview preserve the configured health and prediction opacity.",
                        "Detached Player Power bars attached or width-synced to Class Resources retain their position and width when shapeshifting hides the Class Resource bar.",
                        "Text on detached bar controls Power-text placement independently from Show power text.",
                        "Class Resource previews keep responding to movement and position controls after Menu lifecycle cancellation.",
                        "Interrupted Aura refreshes recover instead of leaving Aura displays empty or later refreshes stuck as pending.",
                        "Cleanse and Purge borders use the same Frame Outline layer as their preview, and Unit Frame dispel borders follow Blizzard's assist rules.",
                        "Group Frame dead and offline backgrounds follow the unit's current state without delayed health-background updates.",
                        "Preserved raid groups use one roster snapshot for sorting and layout, preventing the filled and displayed grids from disagreeing when more subgroups are present than the configured column limit.",
                        "Assistant requests for Out of range opacity, Texture Layer opacity, and Portrait opacity update their own controls.",
                        "Reduced repeated work and temporary allocations in health gradients, dynamic backgrounds, protected text, Aura fallback scans, and Range Fade timers while preserving their update behavior.",
                    },
                },
            },
        },
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
