-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "33518938FA04080D54F21B1A0AC7C55A5B7C02C2C02C97F143DB0828CAAE2B42",
    currentVersion = "6.5-alpha14",
    historyFromVersion = "6.5-alpha11",
    previousVersion = "6.5-alpha13",
    rangeLabel = "6.5-alpha13 -> 6.5-alpha14",
    entries = {
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
                    title = "Fixes",
                    bullets = {
                        "Restored rounded highlight startup and layering, including border thickness up to 30.",
                        "Native Dispel and Purge borders apply their configured thickness on all frame shapes and refresh immediately after Menu changes.",
                        "Group Frame highlight detection continues working when Aura icons are disabled.",
                        "Any dispel type highlights can detect typed harmful Auras on enemy units.",
                    },
                },
            },
        },
        {
            version = "6.5-alpha11",
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
                    title = "Changes",
                    bullets = {
                        "Synchronized the complete Retail 6.15-beta7 performance set into the unified Alpha package.",
                        "The Mainline flavor keeps its Retail 12.1.5 native Aura, scheduler, tooltip-caster, and pixel-rounding paths. Arena Frames and the Vanilla 1.15.9, TBC 2.5.6, and Mists 5.5.4 flavors remain included.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Health gradients reuse bounded native scalar curves for their RGB channels, avoid per-update ColorMixin allocation, and keep constant channels out of the native evaluation path.",
                        "Group health updates avoid a repeated dynamic-background refresh and an empty color handoff after the background has already been painted.",
                        "Dynamic health backgrounds cache stable alpha inputs and known cache keys, use the native secret-value predicate when available, and forward protected colors directly to their supported rendering sink.",
                        "Protected current, maximum, and percentage text modes use compiled single-value writers instead of the general multi-value formatter.",
                        "Unresolved Aura fallback scans avoid resynchronizing an unchanged active-work state while later discovery, owner reactivation, and unregister cleanup remain intact.",
                        "Group death-background updates skip cache probes that cannot be reused outside an active frame dispatch while retaining fresh native death and resurrection checks.",
                        "Range Fade keeps an earlier timer when its logical deadline moves later, reducing timer replacement churn without moving range checks or alpha changes forward.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
