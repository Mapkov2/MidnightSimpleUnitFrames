-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "D038F94ED173B15A7E18310D1566D9F90BAD0E2A742CEA9719CF702885B2FA17",
    currentVersion = "6.09-Beta4",
    historyFromVersion = "6.09-Beta1",
    previousVersion = "6.09-Beta3",
    rangeLabel = "6.09-Beta3 -> 6.09-Beta4",
    entries = {
        {
            version = "6.09-Beta4",
            date = "2026-08-17",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Hardened the combat aura scanner against Blizzard's instanced-content restrictions: scans now detect encounter, Mythic+, and PvP lockdowns, show a clear notice pointing to the curated presets, and resume automatically instead of erroring.",
                            link = {
                                pageKey = "uf_target",
                                query = "blacklist",
                                label = "Combat scan",
                                sectionId = "auras",
                                controlId = "menu2.uf_target.auras.unit-workspace.lane.buff.layout.visible",
                                settingKey = "auras3.target.buff.visible",
                            },
                        },
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed hard \"Auras cannot be accessed\" errors when the aura scanner ran during encounters, Mythic+, or PvP matches.",
                        "Open-world combat scanning keeps capturing readable auras; auras Blizzard hides are counted as hidden instead of failing the scan.",
                    },
                },
            },
        },
        {
            version = "6.09-Beta3",
            date = "2026-08-17",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Added a combat aura scanner to the Unitframe blacklist workspace: one click closes the menu, keeps capturing every blockable aura with its icon until combat ends, then reopens the menu with the collected list.",
                            link = {
                                pageKey = "uf_target",
                                query = "blacklist",
                                label = "Combat scan",
                                sectionId = "auras",
                                controlId = "menu2.uf_target.auras.unit-workspace.lane.buff.layout.visible",
                                settingKey = "auras3.target.buff.visible",
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
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Extended the Maximum duration filter to every aura lane on unit and group frames, including Buffs, Tracked Buffs, and External Defensives.",
                        "Added a live Active auras on this frame dropdown to the blacklist with one-click blocking, a Rescan button, and a session capture list; scans run only on click.",
                        "Manual blacklist entries are now verified against the live unit: when your cast's Spell ID differs from the aura's actual ID, MSUF warns and offers to block the real aura ID instead.",
                        "Reworked pandemic-window Full-Frame effects for tracked DoTs to bind to the visible aura buttons themselves, including portrait mode.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Scan results state how many auras Blizzard hides as secret; hidden auras cannot be identified or blocked by any addon, so everything blockable is always captured.",
                        "Blacklist scanning stays fully click-driven: an open menu never scans on its own and nothing was added to combat hotpaths.",
                    },
                },
            },
        },
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
