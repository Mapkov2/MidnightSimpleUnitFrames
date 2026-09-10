-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "8AF6299FF2FE00EDFC06500DFFACBA3E0533D3D5E0B7BDBF0296DEA91AA7C4A4",
    currentVersion = "6.16-beta6",
    historyFromVersion = "6.16-beta3",
    previousVersion = "6.16-beta5",
    rangeLabel = "6.16-beta5 -> 6.16-beta6",
    entries = {
        {
            version = "6.16-beta6",
            date = "2026-09-10",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Every settings section now carries its on/off switch, a one-line summary and a \"...\" menu on its header. Turn a feature on or off without expanding it, read its current values at a glance, and reset or copy just that section.",
                            linkless = true,
                        },
                        {
                            text = "The interrupt-ready indicator counts every interrupt you have, not just your main kick. Paladins with Avenger's Shield and Warriors with Disrupting Shout read as ready as soon as either one is off cooldown.",
                            link = {
                                pageKey = "opt_castbar",
                                query = "castbar border",
                                label = "Castbar border",
                                sectionId = "castbar_interrupt_ready",
                                controlId = "menu2.opt.castbar.global.interrupt.ready.kick.ready.style",
                                settingKey = "general.kickReadyStyle",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Options menus read brighter: taller section headers with an accent border when open or hovered, a higher floor for the smallest fonts, and a clearly visible active page in the navigation.",
                        "Switching a frame or a group scope off now dims only its setting sections. The frame picker, the unit selector and the preview stay usable, and Frame Basics is labelled as disabled.",
                        "Unit and Party/Raid pages open with a title naming the frame or scope they edit and an Enable switch for it.",
                        "Previews open on the neutral Studio background instead of the Silvermoon scene, and the Guides layer starts hidden.",
                        "The Arcane Surge / Arcane Soul countdown row and its Class Resources toggle were removed. Whirlwind and Sweeping Strikes tracking are unchanged.",
                        "German clients now see translated text for the new frame workspace header and the section actions popup.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "With the Castbar border indicator style the ready colour no longer reverts to the normal border colour when the border is rebuilt or recoloured.",
                        "Balance Druid, Survival Hunter and Demonology Warlock track their own interrupt again instead of a spell they cannot cast.",
                        "A Guides layer that was switched off no longer comes back lit every time a preview is rebuilt.",
                        "Zoning into a new area rebuilds raid headers once instead of twice, so group frames stop stalling right after a loading screen.",
                        "The 6.16 beta 3 entry in See New Features no longer links to the removed Arcane Surge / Soul toggle.",
                    },
                },
            },
        },
        {
            version = "6.16-beta5",
            date = "2026-09-09",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Separator and Pip gap shape the Demon Hunter Devourer bar across their whole range. The dividers share the space the fragments do not need, so every step of the sliders changes the bar instead of settling on one width.",
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
                    title = "Fixes & Performance",
                    bullets = {
                        "Pixel snapping no longer rounds a one-pixel divider below a pixel, which could remove the fragment division entirely at some interface scales.",
                    },
                },
            },
        },
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
