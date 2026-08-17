-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "FDE14528EDCAA61AD6F09D0A6FF6E8682987E3D3105B26284CB65DCE31F9F4A8",
    currentVersion = "6.09",
    historyFromVersion = "6.08-Beta1",
    previousVersion = "6.08",
    rangeLabel = "6.08 -> 6.09",
    entries = {
        {
            version = "6.09",
            date = "2026-08-17",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Added dynamic Custom Priority ordering for Dots on target and Custom 1-3 aura containers, keeping the configured spell order compact and stable as tracked auras appear or expire.",
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
                        {
                            text = "Added a combat aura scanner to the Unitframe blacklist workspace: one click closes the menu, keeps capturing every blockable aura with its icon until combat ends, then reopens the menu with the collected list, ready to block.",
                            link = {
                                pageKey = "uf_target",
                                query = "target debuff blacklist",
                                label = "Combat scan",
                                sectionId = "auras",
                                controlId = "menu2.uf_target.auras.unit-workspace.container-selector",
                                settingKey = "auras3.target.debuff.blacklist.hidePermanent",
                                prepareKind = "unitAuraWorkspace",
                                prepareValue = "debuff_blacklist",
                            },
                        },
                        {
                            text = "Manual blacklist entries are now verified by Spell ID against the live unit: when your cast's ID differs from the aura's actual ID, MSUF warns and offers to block the real aura ID instead.",
                            link = {
                                pageKey = "uf_target",
                                query = "target debuff blacklist",
                                label = "Blacklist",
                                sectionId = "auras",
                                controlId = "menu2.uf_target.auras.unit-workspace.container-selector",
                                settingKey = "auras3.target.debuff.blacklist.hidePermanent",
                                prepareKind = "unitAuraWorkspace",
                                prepareValue = "debuff_blacklist",
                            },
                        },
                        {
                            text = "Added an optional Show spell IDs in aura tooltips toggle that keeps the native 12.1 tooltip option enabled across logins.",
                            link = {
                                pageKey = "opt_misc",
                                query = "spell ids",
                                label = "Aura tooltip spell IDs",
                                sectionId = "misc_tooltips",
                                controlId = "menu2.opt.misc.global.setting.tooltip.show.aura.spell.ids",
                                settingKey = "general.tooltipShowAuraSpellIDs",
                            },
                        },
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
                        "Moved aura ordering out of Style into dedicated, scope-aware Ordering workspaces for Unit Frames, Group Frames, custom aura containers, and external defensives, with draggable priority rows that snap to their new slot.",
                        "Added a live Active auras on this frame dropdown to the blacklist with one-click blocking, a Rescan button, and a session capture list; scans run only on click.",
                        "Extended the Maximum duration filter to every aura lane on unit and group frames, including Buffs, Tracked Buffs, and External Defensives.",
                        "Reworked pandemic-window Full-Frame effects for tracked DoTs to bind to the visible aura buttons themselves, including portrait mode.",
                        "Replaced Aura list scrollbars with the consistent MSUF scrollbar style and exposed Ordering options directly without a redundant accordion.",
                        "Added Blizzard's NEW badge to the See New Features button, shown until the bundled release notes have been opened.",
                        "Added Deathstalker's Mark for Rogues and Atmospheric Exposure for Druids to the tracked target-effect presets, and corrected the Balance Druid presets for Moonfire (164812), Sunfire (164815), and Atmospheric Exposure (430589).",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed the combat timer not being movable while its position was unlocked.",
                        "Added a tooltip to the combat timer's Lock position toggle explaining how positioning works.",
                        "Fixed the Combat Enter/Leave text vanishing after every combat transition while unlocked; it now stays visible as its movable handle.",
                        "Fixed gameplay mover offsets drifting when the moved element was anchored to a scaled frame, and dragging a mover now repaints its X/Y sliders live.",
                        "Scanning respects Blizzard's instanced-content restrictions: encounter, Mythic+, and PvP lockdowns show a clear notice pointing to the curated presets and resume automatically instead of erroring.",
                        "Scan results state how many auras Blizzard hides as secret; hidden auras cannot be identified or blocked by any addon, so everything blockable is always captured.",
                        "Fixed Edit Mode arrow-key nudging for Custom 1-4 aura containers, including shared boss-frame positioning.",
                        "Fixed Spell Indicator controls from an inactive display type remaining visible after selection or preview changes.",
                        "Kept Custom Priority ordering and blacklist scanning fully event- and click-driven: no polling, no recurring OnUpdate work, and nothing added to combat hotpaths.",
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
