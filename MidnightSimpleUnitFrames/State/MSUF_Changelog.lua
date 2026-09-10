-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "E71877574CEFC47C642E2890A8676244B56E7229FE0D2ADD922476F1E7B75877",
    currentVersion = "6.5-alpha15",
    historyFromVersion = "6.5-alpha12",
    previousVersion = "6.5-alpha14",
    rangeLabel = "6.5-alpha14 -> 6.5-alpha15",
    entries = {
        {
            version = "6.5-alpha15",
            date = "2026-09-09",
            sections = {
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Dispel symbols now render on every Classic client. Clients without the 12.1 debuff atlases fell through to a blank texture and drew nothing; they now fall back to MSUF's own symbol art. A dispel type whose color you overrode is repainted the way it already is on Retail.",
                        "The Cooldown Manager anchor is resolved from what the client can actually provide. Clients without a Cooldown Manager no longer show the login warning that could never be satisfied, and the anchor switch is hidden instead of offered; your stored preference is kept, so the profile still works on a client that has one.",
                        "An imported profile that anchors Unit Frames to Essential Cooldowns no longer scatters them on a client without that frame; those frames fall back to the normal global anchor.",
                        "The Aggro border works on a fresh profile. Bars advertised it as On while the frames still treated it as Off, so it only lit up after toggling the dropdown off and on.",
                        "The Dispel Border hint no longer asks you to enable Aura sensors for Focus, Boss, or Arena frames on clients that do not have them.",
                        "Turning a Dispel Symbol off now clears it. It could stay frozen on the frame until the next reload.",
                    },
                },
            },
        },
        {
            version = "6.5-alpha14",
            date = "2026-09-08",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Health gradients, backgrounds, and prediction updates include the latest Retail performance improvements. Existing colors, text formats, prediction options, and Arena support are preserved.",
                            link = {
                                pageKey = "classpower",
                                query = "pip gap",
                                label = "Pip gap",
                                sectionId = "classpower_visuals",
                                controlId = "menu2.classpower.advanced.style.pips.gap",
                                settingKey = "bars.classPowerGap",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Includes Retail 6.16-beta2 with specialized health, absorb prediction, text, and castbar color updates.",
                        "Includes client-specific localized Aura spell-name catalogs for Vanilla, TBC, and Mists. Name matching covers spell ranks and spells whose cast and Aura use different IDs.",
                        "Retains the Mainline, Vanilla, TBC, and Mists client variants and their existing Arena and Classic-specific behavior.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Health backgrounds reuse fresh samples, absorb-only prediction avoids unused update paths, and common text formats avoid repeated format selection.",
                        "Castbar interrupt-ready colors reuse configured colors for public values while preserving native protected-value handling and Arena settings.",
                        "Classic unit choices and interrupt-ready spell lists now follow the active client's capabilities. TBC specialization detection uses the dominant talent tree.",
                        "Classic menus and previews include injured-only visibility, friendly/enemy debuff-border scope, and chunked Power fill controls.",
                        "Classic dispel symbols, portrait masks, and Edit Mode arrows handle unavailable client atlases. Legacy Blizzard Arena frames are hidden when MSUF owns those frames.",
                    },
                },
            },
        },
        {
            version = "6.5-alpha13",
            date = "2026-09-08",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Interrupted cast feedback clears again after rapidly starting and interrupting another cast. The configured feedback duration is preserved.",
                            link = {
                                pageKey = "opt_castbar",
                                query = "interrupt display duration",
                                label = "Interrupt display duration (sec)",
                                sectionId = "castbar_behavior",
                                controlId = "menu2.opt.castbar.global.behavior.castbar.interrupt.feedback.duration",
                                settingKey = "general.castbarInterruptFeedbackDuration",
                            },
                        },
                        {
                            text = "Health rendering and text updates include the latest Retail refactors. Health gradients, backgrounds, and percentage text share sampled values and avoid redundant work.",
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
                    title = "Changes",
                    bullets = {
                        "Includes the complete Retail 6.16-beta1 update and the subsequent performance passes through Retail commit 0e2bb191.",
                        "Auras3 now uses separate runtime, configuration, Menu, Edit Mode, and Spell Indicator modules. Existing Arena behavior and Classic-specific Aura backends are preserved.",
                        "Includes the localized Aura alias catalogs, injured-only Unit Frame visibility, Target Range Fade fixes, visual parenting, and updated Assistant controls.",
                        "Includes subsequent health-background, group-health percentage, text-drain, Aura identity, castbar ownership, Texture Layer, Aura menu, and status-preview fixes.",
                        "Retains Mainline 12.0.7/12.1.0/12.1.5, Vanilla 1.15.9, TBC 2.5.6, and Mists 5.5.4 support.",
                    },
                },
                {
                    title = "Fixes",
                    bullets = {
                        "Raid and Party Frames refresh their current health and status when entering the world, including after accepting a summon with unchanged raid slots. This addresses frames remaining black until a reload or later unit event.",
                        "Cancelling pending player interrupt feedback clears its pending state, allowing the next interruption to hide normally.",
                        "The Classic delayed scheduler uses the refactored callback error handler while retaining keyed cancellation and replacement.",
                        "Classic Aura Edit Mode and Menu load the new shared factories in their required order.",
                    },
                },
            },
        },
        {
            version = "6.5-alpha12",
            date = "2026-09-06",
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
                            text = "Class Resources now include native Sweeping Strikes tracking.",
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
                            text = "MSUF menus and Edit Mode can follow your MapkoSkin appearance. The Use MapkoSkin for MSUF menus option connects compatible MapkoSkin installations to MSUF menu styling.",
                            link = {
                                pageKey = "opt_misc",
                                query = "use mapkoskin for msuf menus",
                                label = "Use MapkoSkin for MSUF menus",
                                sectionId = "misc_mapkoskin",
                                controlId = "menu2.opt.misc.global.setting.mapko.skin.menus",
                                settingKey = "general.mapkoSkinMenus",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Includes the complete Retail 6.15 and 6.151 feature and fix set, including the earlier prediction-opacity, raid-sorting, Assistant, and performance improvements.",
                        "MapkoSkin menu integration is available across the Mainline, Vanilla, TBC, and Mists flavors, with its own searchable toggle.",
                        "The Mainline flavor retains Retail 12.1.5 support and Arena Frames. Vanilla 1.15.9, TBC 2.5.6, and Mists 5.5.4 compatibility remains included.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Restored rounded highlight startup and layering, including border thickness up to 30.",
                        "Native Dispel and Purge borders apply their configured thickness on all frame shapes and refresh immediately after Menu changes.",
                        "Group Frame highlight detection continues working when Aura icons are disabled.",
                        "Any dispel type highlights can detect typed harmful Auras on enemy units.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
