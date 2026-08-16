-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "7E2C3BBD8F6C69D4F7B4BFF349ABDF4DA052DA0E9817C747974DB8EA8414EC0C",
    currentVersion = "6.08",
    historyFromVersion = "6.07",
    previousVersion = "6.07",
    rangeLabel = "6.07 -> 6.08",
    entries = {
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
        {
            version = "6.08-Beta1",
            date = "2026-08-15",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added an optional Slug font rendering mode for clearer, more consistent text across Unit and Group Frames.",
                        "Added configurable AFK timers to Unit and Group Frame status text.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Group Frame absorb overlays ignoring the configured opacity.",
                        "Fixed aura icon zoom scaling when a debuff border is active.",
                    },
                },
            },
        },
        {
            version = "6.07",
            date = "2026-08-15",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Expanded Texture Layers into three independently configurable, HP-reactive decoration slots with shared gradients, threshold colors, opacity rules, target/combat conditions, presets, and runtime-faithful previews.",
                        "Added League of Legends-style Health and Power loss feedback for Unit and Group Frames. Bars update immediately while a configurable trailing chunk shows recently lost Health or spent Power without polling.",
                        "Added profile-wide controls for Blizzard's Player Buff Frame and normal Debuff icons while keeping Private Auras and Deadly Debuff warnings available.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added direct Edit Mode popup controls for Custom Aura 1-4, Dots on Target, and Player Defensive Buffs, including position, size, spacing, reset, undo, Boss synchronization, and Menu focus.",
                        "Restored Spell Indicator bars with Blizzard's native aura-duration StatusBar, configurable growth direction, smoothing, timer text, geometry, color, alpha, and layer.",
                        "Increased the Menu Back and Forward buttons for easier navigation.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Group Aura lanes and Spell Indicators remaining visible for offline, phased, distant-map, or different-instance members. Presence updates remain coalesced and event-driven.",
                        "Fixed Unit Aura preview handles requiring a second click before their X/Y controls appeared after switching lanes. The first click now survives the settings-page rebuild.",
                        "Fixed Target of Target identity and color events being routed through the Target frame without unit filtering. Updates now listen only to targettarget, and foreign unit events can no longer recolor the Target health bar.",
                        "Fixed Texture Layer controls writing to the wrong slot and protected HP-driven alpha values being cached or compared from Lua.",
                        "Fixed Spell Indicator icon, bar, glow, and full-frame effect ownership, opacity, cleanup, preview parity, and layer ordering.",
                        "Fixed Level, Race, Class, and other name-relative status text drifting away from shortened or repositioned Unit Frame names.",
                        "Fixed stale Player portraits, Unit Aura settings writing to the wrong lane, and Objective Tracker state leaking through MSUF's Edit Mode bridge.",
                        "Fixed Class Resource preview text handles becoming trapped behind higher-layer bar visuals.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
