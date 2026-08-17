-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "CA1CFB852340DA9E52434F28D35487EB1F1AEE7551FD95019EEF9D12EB599559",
    currentVersion = "6.09-Beta2",
    historyFromVersion = "6.08-Beta2",
    previousVersion = "6.09-Beta1",
    rangeLabel = "6.09-Beta1 -> 6.09-Beta2",
    entries = {
        {
            version = "6.09-Beta2",
            date = "2026-08-17",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Added an optional Boss Number status indicator so boss frames can show their encounter index directly on the frame.",
                            link = {
                                pageKey = "uf_boss",
                                query = "boss number",
                                label = "Boss Number",
                                sectionId = "status_icons",
                                controlId = "menu2.uf_boss.unit.status.selected.enabled",
                                settingKey = "boss.showBossNumberIndicator",
                                prepareKind = "unitStatus",
                                prepareValue = "bossNumber",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Extended dynamic Custom Priority runtime ordering to Custom 1-3 aura containers as well as Dots on target.",
                        "Made tracked DoT and custom-aura rows draggable across their full free row area, with the row following the cursor and snapping to its new priority slot.",
                        "Replaced Aura list scrollbars with the consistent MSUF scrollbar style and exposed Ordering options directly without a redundant accordion.",
                        "Corrected the Balance Druid presets for Moonfire (164812), Sunfire (164815), and Atmospheric Exposure (430589).",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Edit Mode arrow-key nudging for Custom 1-4 aura containers, including shared boss-frame positioning.",
                        "Kept custom priority ordering event-driven without polling or recurring runtime work.",
                    },
                },
            },
        },
        {
            version = "6.09-Beta1",
            date = "2026-08-17",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Added dynamic Custom Priority ordering for Dots on target, keeping the configured spell order compact and stable as tracked DoTs appear or expire.",
                            link = {
                                pageKey = "uf_target",
                                query = "dots on target custom priority",
                                label = "Custom Priority",
                                sectionId = "auras",
                                controlId = "menu2.uf_target.auras.unit-workspace.container-selector",
                                settingKey = "auras3.target.custom4.placed.sortMethod",
                                prepareKind = "unitAuraWorkspace",
                                prepareValue = "custom4_behavior",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Moved aura ordering out of Style into dedicated, scope-aware Ordering workspaces for Unit Frames, Group Frames, custom aura containers, and external defensives.",
                        "Added priority reordering controls to the tracked DoT list and kept inactive entries gap-free at runtime.",
                        "Added Deathstalker's Mark for Rogues and Atmospheric Exposure for Druids to the tracked target-effect presets.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Spell Indicator controls from an inactive display type remaining visible after selection or preview changes.",
                        "Kept Custom Priority event-driven through native aura groups without polling or recurring OnUpdate work.",
                    },
                },
            },
        },
        {
            version = "6.08",
            date = "2026-08-16",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Added optional profile-wide custom colors for Magic, Curse, Disease, Poison, and Bleed across Unit and Group Frame dispel visuals while preserving Blizzard's native defaults whenever no override is enabled.",
                            link = {
                                pageKey = "opt_colors",
                                query = "magic dispel color",
                                label = "Magic color",
                                sectionId = "colors_auras",
                                controlId = "menu2.opt.colors.advanced.auras.dispel.magic.color",
                                settingKey = "general.dispelTypeColorOverrides.Magic",
                            },
                        },
                        {
                            text = "Added an optional, class-colored interrupter name beside the castbar's interrupted state.",
                            link = {
                                pageKey = "uf_target",
                                query = "show interrupter name",
                                label = "Show interrupter name",
                                sectionId = "castbar",
                                controlId = "menu2.uf_target.unit.castbar.show_interrupt_source",
                                settingKey = "target.showInterruptSource",
                                prepareKind = "unitCastbarTab",
                                prepareValue = "general",
                            },
                        },
                        {
                            text = "Added configurable AFK timers to Unit and Group Frame status text.",
                            link = {
                                pageKey = "uf_player",
                                query = "afk timer",
                                label = "AFK Timer",
                                sectionId = "status_icons",
                                controlId = "menu2.uf_player.unit.status.selected.enabled",
                                settingKey = "player.statusAFKTimerEnabled",
                                prepareKind = "unitStatus",
                                prepareValue = "statusAFKTimer",
                            },
                        },
                        {
                            text = "Added an optional Player Frame Stance text indicator for warrior stances, paladin auras, druid forms, and other native stance-bar forms.",
                            link = {
                                pageKey = "uf_player",
                                query = "stance",
                                label = "Stance",
                                sectionId = "status_icons",
                                controlId = "menu2.uf_player.unit.status.selected.enabled",
                                settingKey = "player.showStanceIndicator",
                                prepareKind = "unitStatus",
                                prepareValue = "stance",
                            },
                        },
                        {
                            text = "Added explicit Uniform and Width & height portrait sizing modes for Unit and Group Frames while preserving existing portrait geometry during migration.",
                            link = {
                                pageKey = "uf_player",
                                query = "portrait size mode",
                                label = "Size mode",
                                sectionId = "portrait",
                                controlId = "menu2.uf_player.unit.portrait.portraitsizemode",
                                settingKey = "player.portraitSizeMode",
                                prepareKind = "unitPortraitTab",
                                prepareValue = "geometry",
                            },
                        },
                        {
                            text = "Added configurable edge softness for circular, rounded, and diamond portraits, with matching Unit Frame, Group Frame, and preview rendering.",
                            link = {
                                pageKey = "uf_player",
                                query = "portrait edge softness",
                                label = "Portrait edge softness",
                                sectionId = "portrait",
                                controlId = "menu2.uf_player.unit.portrait.portraitedgesoftness",
                                settingKey = "player.portraitEdgeSoftness",
                                prepareKind = "unitPortraitTab",
                                prepareValue = "border",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added an optional Slug font rendering mode for clearer, more consistent text across Unit Frames, Group Frames, Castbars, Class Resources, and other MSUF text.",
                        "Applied custom Dispel colors consistently to Unit Dispel Overlays, Group Dispel Overlays, Dispel Highlight Borders, MSUF Dispel symbols, Edit Mode, and every matching Menu preview.",
                        "Added ::: color shortcuts to Unit Dispel Overlay, Group Dispel Overlay, and Highlight Borders for direct access to the matching global Dispel colors.",
                        "Kept original Blizzard and MSUF Dispel artwork for default colors; tint-neutral MSUF symbol assets are selected only for Dispel types with an active custom override.",
                        "Replaced the toolbar's New Task action with a dedicated See New Features changelog page. Highlighted feature sentences now link directly to their exact MSUF Menu controls and subcategories.",
                        "Localized the new Dispel colors, AFK timer, stance, portrait sizing, portrait edge-softness, and related controls across all 12 supported locales.",
                        "Updated Assistant registrations, profile behavior, copy/reset handling, search routing, generated coverage data, and static search data for the new controls.",
                        "Added daily GitHub synchronization from Retail main to the Classic repository, clearer sync-failure reporting, and required versioned Classic validation.",
                        "Added manual release-channel recovery support to the GitHub release workflow.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Updated Spell Indicator filters in place through Blizzard's public AuraSlot setter, avoiding unnecessary restricted AuraButton and container rebuilds when only a friendly/hostile filter changes.",
                        "Fixed custom MSUF Dispel symbols becoming black or incorrectly multiplied after recoloring. Custom overrides now use tint-neutral, alpha-identical companions, while unchanged colors continue using the original assets.",
                        "Fixed Group Frame absorb overlays ignoring the configured opacity.",
                        "Fixed aura icon zoom scaling when a Debuff border is active, including runtime and preview rendering.",
                        "Fixed the Castbar General tab height after adding the interrupter-name option.",
                        "Changed Target and Focus castbar identity refreshes from deferred callbacks to direct synchronous updates.",
                        "Cleared the castbar driver's unused OnUpdate script once during construction instead of repeating the native transition on target swaps.",
                        "Fixed player Unit Frames showing the fallback blue or another incorrect health color for identity-restricted PvP targets by routing every player class through Blizzard's native secret-safe class-color pipeline.",
                        "Fixed restricted Race and Class status text showing a unit name or blank value by using Blizzard's stable identity return directly when localized identity text is protected.",
                        "Streamlined Unit Frame identity refreshes across bars, portraits, status text, regular text, and range fading so unchanged identity state avoids redundant work.",
                        "Skipped player-only nickname-provider APIs for NPC units while retaining supported NPC nickname sources.",
                        "Fixed Arena Group Frames using Raid instead of Party configuration across runtime, Blizzard-frame ownership, Edit Mode, and previews.",
                        "Fixed exact-ID aura indicators mixing friendly and hostile filters after switching targets.",
                        "Limited PvP indicator runtime to Arenas, Battlegrounds, and War Mode, removing unrelated faction and PvP-timer event traffic outside those modes.",
                    },
                },
            },
        },
        {
            version = "6.08-Beta2",
            date = "2026-08-15",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Added an optional, class-colored interrupter name beside the castbar's interrupted state.",
                            link = {
                                pageKey = "uf_target",
                                query = "show interrupter name",
                                label = "Show interrupter name",
                                sectionId = "castbar",
                                controlId = "menu2.uf_target.unit.castbar.show_interrupt_source",
                                settingKey = "target.showInterruptSource",
                                prepareKind = "unitCastbarTab",
                                prepareValue = "general",
                            },
                        },
                        {
                            text = "Added an optional Player Frame Stance text indicator for warrior stances, paladin auras, druid forms, and other native stance-bar forms.",
                            link = {
                                pageKey = "uf_player",
                                query = "stance",
                                label = "Stance",
                                sectionId = "status_icons",
                                controlId = "menu2.uf_player.unit.status.selected.enabled",
                                settingKey = "player.showStanceIndicator",
                                prepareKind = "unitStatus",
                                prepareValue = "stance",
                            },
                        },
                        {
                            text = "Added explicit Uniform and Width & height portrait sizing modes for Unit and Group Frames while preserving existing portrait geometry during migration.",
                            link = {
                                pageKey = "uf_player",
                                query = "portrait size mode",
                                label = "Size mode",
                                sectionId = "portrait",
                                controlId = "menu2.uf_player.unit.portrait.portraitsizemode",
                                settingKey = "player.portraitSizeMode",
                                prepareKind = "unitPortraitTab",
                                prepareValue = "geometry",
                            },
                        },
                        {
                            text = "Added configurable edge softness for circular, rounded, and diamond portraits, with matching Unit Frame, Group Frame, and preview rendering.",
                            link = {
                                pageKey = "uf_player",
                                query = "portrait edge softness",
                                label = "Portrait edge softness",
                                sectionId = "portrait",
                                controlId = "menu2.uf_player.unit.portrait.portraitedgesoftness",
                                settingKey = "player.portraitEdgeSoftness",
                                prepareKind = "unitPortraitTab",
                                prepareValue = "border",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Replaced the toolbar's New Task action with a dedicated See New Features changelog page whose highlighted change sentences link directly to their matching MSUF menu settings.",
                        "Localized the new stance, portrait sizing, and portrait edge-softness controls across all 12 supported locales.",
                        "Updated Assistant registrations, generated coverage data, search routing, and static search data for the new status and portrait controls.",
                        "Corrected the bundled release history so features added after Beta 1 are listed under Beta 2 instead of the already-published Beta 1 package.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed the Castbar General tab height after adding the interrupter-name option.",
                        "Changed Target and Focus castbar identity refreshes from deferred callbacks to direct synchronous updates.",
                        "Cleared the castbar driver's unused OnUpdate script once during construction instead of repeating the native transition on target swaps.",
                        "Fixed player Unit Frames showing the fallback blue or another incorrect health color for identity-restricted PvP targets by routing every player class through Blizzard's native secret-safe class-color pipeline.",
                        "Streamlined Unit Frame identity refreshes across bars, portraits, status text, regular text, and range fading so unchanged identity state avoids redundant work.",
                        "Skipped player-only nickname-provider APIs for NPC units while retaining supported NPC nickname sources.",
                        "Fixed Arena Group Frames using raid instead of party configuration, including runtime, Blizzard-frame ownership, Edit Mode, and previews.",
                        "Fixed exact-ID aura indicators mixing friendly and hostile filters after switching targets.",
                        "Limited PvP indicator runtime to arenas, battlegrounds, and War Mode, removing unrelated faction and PvP-timer event traffic outside those modes.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
