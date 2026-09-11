-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "62FE041A8481D7F337B4454A52AAD7007C973C2FC81848558B92060275B1AF3E",
    currentVersion = "6.16",
    historyFromVersion = "6.14",
    previousVersion = "6.151",
    rangeLabel = "6.151 -> 6.16",
    entries = {
        {
            version = "6.16",
            date = "2026-09-10",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Every settings section now carries its on/off switch, a one-line summary and a \"...\" menu on its header. Turn a feature on or off without expanding it, read its current values at a glance, and reset or copy a single section to another frame.",
                            linkless = true,
                        },
                        {
                            text = "Name, health and power text can each appear only on mouseover, with independent fade-in and fade-out durations.",
                            link = {
                                pageKey = "uf_player",
                                query = "only show on mouseover",
                                label = "Only show on mouseover",
                                sectionId = "text",
                                controlId = "menu2.uf_player.unit.text.name.mouseover",
                                settingKey = "player.nameTextMouseover",
                            },
                        },
                        {
                            text = "Unit Frames can appear only while their unit is injured. Show only below 100% health keeps a frame transparent at full health while your other hide rules still apply.",
                            link = {
                                pageKey = "uf_player",
                                query = "show only below 100 health",
                                label = "Show only below 100% health",
                                sectionId = "load_conditions",
                                controlId = "menu2.uf_player.unit.load_condition.loadcondshowwheninjured",
                                settingKey = "player.loadCondShowWhenInjured",
                            },
                        },
                        {
                            text = "Boss target highlights support arrows, paired markers, diamonds, crosses and borders. Position markers directly in the preview and optionally require several boss frames.",
                            link = {
                                pageKey = "uf_boss",
                                query = "boss target highlight",
                                label = "Highlight style",
                                sectionId = "boss_target_highlight",
                                controlId = "menu2.uf_boss.unit.boss_target_highlight.style",
                                settingKey = "general.bossTargetHighlightStyle",
                            },
                        },
                        {
                            text = "Portraits can be clickable, enabled separately for each Unit Frame.",
                            link = {
                                pageKey = "uf_player",
                                query = "clickable portrait",
                                label = "Clickable Portrait",
                                sectionId = "portrait",
                                controlId = "menu2.uf_player.unit.portrait.portraitclickable",
                                settingKey = "player.portraitClickable",
                                prepareKind = "unitPortraitTab",
                                prepareValue = "general",
                            },
                        },
                        {
                            text = "Class Resources track Sweeping Strikes natively.",
                            link = {
                                pageKey = "classpower",
                                query = "sweeping strikes",
                                label = "Sweeping Strikes Tracker",
                                sectionId = "classpower_behavior",
                                controlId = "menu2.classpower.advanced.behavior.sweeping",
                                settingKey = "bars.showSweepingStrikes",
                            },
                        },
                        {
                            text = "Every menu string is now translated in all twelve locales. German, both Spanish variants, French, Italian, Korean, Brazilian Portuguese, Russian and both Chinese variants no longer fall back to English.",
                            linkless = true,
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Options menus read brighter: taller section headers with an accent border when open or hovered, the same accent outline on every clickable surface you hover - unit tabs, pills, buttons, dropdowns and the section \"...\" menus - a higher floor for the smallest fonts, and a clearly visible active page in the navigation.",
                        "Switching a frame or a group scope off now dims only its setting sections. The frame picker, the unit selector and the preview stay usable, and Frame Basics is labelled as disabled.",
                        "Unit and Party/Raid pages open with a title naming the frame or scope they edit and an Enable switch for it.",
                        "Previews open on the neutral Studio background instead of the Silvermoon scene, and the Guides layer starts hidden.",
                        "Class-colored power bars were added to the contextual color controls.",
                        "The Auras3 backend was rebuilt into explicit native runtime, Menu, Edit Mode and Spell Indicator modules, with no change to how your auras behave or to Blizzard-owned aura tracking.",
                        "Custom Aura spell names now use prebuilt locale-specific alias catalogs instead of a live aura-name resolver, including current localized and hotfixed spell groups.",
                        "Assistant command coverage, scoped requests, follow-up handling and exact setting navigation were expanded, and the Assistant control catalog and menu search index were rebuilt for the new settings.",
                        "The interrupt-ready indicator counts every interrupt you have, not just your main kick. Paladins with Avenger's Shield and Warriors with Disrupting Shout read as ready as soon as either one is off cooldown.",
                        "Demon Hunter Devourer Soul Fragment bars are divided into their fragments again, and Separator and Pip gap shape that division across their whole range.",
                        "The Arcane Surge / Arcane Soul countdown row and its Class Resources toggle were removed. Whirlwind and Sweeping Strikes tracking are unchanged.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Health gradients, backgrounds and prediction do less repeated work during combat: fresh health samples are reused, client-specific update paths are chosen once instead of on every health event, and current, maximum and percentage text use specialized writers that still honour live number-format changes.",
                        "Absorb-only prediction uses specialized update paths for static and follow-health anchors, including glow and full-health stripe options, while keeping identity, disable and recovery handling.",
                        "Group text updates reuse health values already sampled for the bars, and zoning into a new area rebuilds raid headers once instead of twice, so group frames stop stalling right after a loading screen.",
                        "With the Castbar border indicator style the ready colour no longer reverts to the normal border colour when the border is rebuilt or recoloured, and Balance Druid, Survival Hunter and Demonology Warlock track their own interrupt again instead of a spell they cannot cast.",
                        "Target Range Fade forwards protected in-range results through Blizzard's native boolean-alpha path and keeps its spell-range fallback, and missing-health background masking during Range Fade was corrected so the configured background stays visible.",
                        "A Guides layer that was switched off no longer comes back lit every time a preview is rebuilt, and the Class Resources and docked unit previews render the Devourer resource the way it appears in game.",
                        "Aura icon style controls re-apply their master-toggle gates on every Appearance page, so Debuffs, Player Defensives and Dots no longer keep a stale enabled state.",
                        "Pixel snapping no longer rounds a one-pixel divider below a pixel, which could remove the fragment division entirely at some interface scales.",
                        "Injured-only visibility uses a secret-safe native health curve and stable visual parents, so bars, predictions, borders, textures, portraits, cast indicators and Class Resources hide together without changing the clickable secure frame.",
                        "Aura identity checks and castbar colour ownership avoid redundant temporary allocations, and scheduler callback errors keep the original callback stack while still isolating failures.",
                        "Party frame backgrounds no longer get stuck faded in instanced combat. Restricted combat applies Range Fade through a native path that skipped the bookkeeping the normal path checks, so a health bar, its background or a prediction bar could keep its out-of-range opacity after coming back into range.",
                        "Fixed clipping in Aura cooldown and Texture Layer options, and improved Unit Status previews in the menu.",
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
        {
            version = "6.14",
            date = "2026-08-30",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Health-bar backgrounds can now fill the full bar or only missing health. The background can be colored independently with Custom tint, Match health bar, Class color, or Health gradient, with matching Unit Frame, Group Frame, and preview rendering.",
                            link = {
                                pageKey = "opt_colors",
                                query = "background fill missing health only",
                                label = "Background Fill",
                                sectionId = "colors_background",
                                controlId = "menu2.opt.colors.advanced.background.fill.mode",
                                settingKey = "general.barBgFillMode",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added Full bar and Missing health only background-fill modes plus independent health-background color sources, while migrating existing profiles without changing their current appearance.",
                        "The Assistant now routes Aura content and filter requests to the Unit or Group Frame that owns them, exposes the See New Features destination directly, and presents ambiguous controls with readable menu breadcrumbs instead of internal identifiers.",
                        "Unit Frame tooltips react immediately when their configured modifier key is pressed or released while the frame remains hovered.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Player Castbar interrupt feedback survives the client event order where the cast stops before the interrupted result arrives, without reviving stale casts.",
                        "State Tint controls appear and disappear immediately when their master toggles change instead of requiring the Colors page to be reopened.",
                        "Assistant queues, history, undo, pending choices, workflows, and deferred callbacks are now isolated to the profile that created them, preventing stale work from crossing a profile switch or surviving beyond its conversational context.",
                        "Immediate and deferred Assistant mutations now share the same failure-recovery path so partial work rolls back consistently.",
                        "General Aura guidance no longer competes with frame-local Aura owners, and question-shaped duration-filter requests retain their safe executable choices.",
                        "Aura-name fallback updates skip redundant unit-scan setup when no unresolved additions can benefit from it.",
                        "Opening Unit Frame Power settings no longer errors while building the detached-bar Text on detached bar control.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
