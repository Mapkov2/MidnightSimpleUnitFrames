-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "AE16E384F6C62CF6E88E825C3AE29822ECCA15F37173E0D2BF667A360AFAF6DD",
    currentVersion = "6.16-beta2",
    historyFromVersion = "6.15",
    previousVersion = "6.16-beta1",
    rangeLabel = "6.16-beta1 -> 6.16-beta2",
    entries = {
        {
            version = "6.16-beta2",
            date = "2026-09-08",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Health gradients, backgrounds, and prediction updates do less repeated work during combat. Existing colors, text formats, prediction options, and update behavior are preserved.",
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
                        "Health and background rendering reuse fresh health samples and choose client-specific update paths once instead of on every health event.",
                        "Absorb-only prediction uses specialized update paths for static and follow-health anchors, including glow and full-health stripe options, while retaining identity, disable, and recovery handling.",
                        "Current, maximum, and percentage text use specialized writers and preserve live number-format changes. Group text updates reuse health values already sampled for the bars.",
                        "Castbar interrupt-ready colors reuse configured colors for public values and retain Blizzard's native handling for protected values.",
                        "Aura identity checks avoid temporary owner tables and repeated access checks. Castbar color ownership avoids redundant temporary allocations.",
                        "Corrected missing-health background masking during Range Fade so the configured background and out-of-range appearance remain visible.",
                        "Fixed clipping in Aura cooldown and Texture Layer options, and improved Unit Status previews in the Menu.",
                    },
                },
            },
        },
        {
            version = "6.16-beta1",
            date = "2026-09-06",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Unit Frames can now appear only while their unit is injured. Enable Show only below 100% health under Unit > Load Conditions to keep a frame transparent at full health while preserving the other configured hide rules.",
                            link = {
                                pageKey = "uf_player",
                                query = "show only below 100 health",
                                label = "Show only below 100% health",
                                sectionId = "load_conditions",
                                controlId = "menu2.uf_player.unit.load_condition.loadcondshowwheninjured",
                                settingKey = "player.loadCondShowWhenInjured",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Rebuilt the Auras3 backend into explicit native runtime, Menu, Edit Mode, and Spell Indicator modules while preserving its public behavior and Blizzard-owned Aura tracking.",
                        "Custom Aura spell names now use prebuilt locale-specific alias catalogs instead of a live Aura-name resolver, including current localized and hotfixed spell groups.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Target Range Fade now forwards protected in-range results through Blizzard's native boolean-alpha path and retains its spell-range fallback when the native check is unavailable.",
                        "Health gradients, dynamic backgrounds, and protected health and power text reuse already-read values and specialized writers to reduce duplicate work on frequent unit events.",
                        "Injured-only visibility uses a secret-safe native health curve and stable visual parents so health bars, predictions, borders, textures, portraits, cast indicators, and Class Resources hide together without changing the clickable secure frame.",
                        "Scheduler callback errors now retain the original callback stack while continuing to isolate failures and drain queued work.",
                    },
                },
            },
        },
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
