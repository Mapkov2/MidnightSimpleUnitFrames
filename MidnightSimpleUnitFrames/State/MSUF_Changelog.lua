-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "E0C7AF7D420015E44CE75216631175825A1692A1C4081CC1129B4DAFAB591526",
    currentVersion = "6.16-beta4",
    historyFromVersion = "6.16-beta1",
    previousVersion = "6.16-beta3",
    rangeLabel = "6.16-beta3 -> 6.16-beta4",
    entries = {
        {
            version = "6.16-beta4",
            date = "2026-09-09",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Demon Hunter Devourer Soul Fragment bars are divided into their fragments again. Separator and Pip gap act on the bar once more, while its fill keeps following the real fragment maximum.",
                            link = {
                                pageKey = "classpower",
                                query = "separator",
                                label = "Separator",
                                sectionId = "classpower_visuals",
                                controlId = "menu2.classpower.advanced.style.pips.separator",
                                settingKey = "bars.classPowerTickWidth",
                            },
                        },
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "The Class Resources preview and the docked unit preview now render the Devourer resource the way it appears in game.",
                        "Aura icon style controls re-apply their master-toggle gates on every Appearance page instead of only on Buffs, so Debuffs, Player Defensives and Dots no longer keep a stale enabled state.",
                    },
                },
            },
        },
        {
            version = "6.16-beta3",
            date = "2026-09-09",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Name, health, and power text can each appear only on mouseover, with independent fade-in and fade-out durations. Configure each text element under Unit > Text.",
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
                            text = "Boss target highlights now support arrows, paired markers, diamonds, crosses, and borders. Position markers directly in the preview and optionally require multiple boss frames.",
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
                            text = "Portraits can now be clickable. Enable the option separately for each Unit Frame.",
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
                            text = "Class Resources now include native Sweeping Strikes tracking and an Arcane Surge / Arcane Soul timer.",
                            link = {
                                pageKey = "classpower",
                                query = "arcane soul",
                                label = "Arcane Surge / Soul Timer",
                                sectionId = "classpower_behavior",
                                controlId = "menu2.classpower.advanced.behavior.arcane.soul",
                                settingKey = "bars.showArcaneSoul",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Completed translations for the new Menu controls and descriptions across all supported languages.",
                        "Added class-colored power bars to the contextual color controls.",
                        "Expanded Assistant command coverage, scoped requests, follow-up handling, and exact setting navigation.",
                        "Updated the Menu search index and Assistant control catalog for the new settings.",
                    },
                },
            },
        },
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
