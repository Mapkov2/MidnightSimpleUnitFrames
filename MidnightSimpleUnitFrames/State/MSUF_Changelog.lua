-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "F051B7C939A313794B97374ADF913F21BB8754A5CBC3D1F099112CE99A19C1DF",
    currentVersion = "6.506",
    historyFromVersion = "6.502",
    previousVersion = "6.502",
    rangeLabel = "6.502 -> 6.506",
    entries = {
        {
            version = "6.506",
            date = "2026-11-03",
            sections = {
                {
                    title = "Improvements",
                    bullets = {
                        {
                            text = "Expanded detached power-bar dimensions to widths of 10-800 and heights of 2-800, with matching vertical and reversed preview fills.",
                            link = {
                                pageKey = "classpower",
                                query = "detached power width",
                                label = "Power width",
                                sectionId = "classpower_detached_power",
                                controlId = "menu2.classpower.advanced.detached.power.layout.width",
                                settingKey = "player.detachedPowerBarWidth",
                                prepareKind = "classPowerWorkspace",
                                prepareValue = "power",
                            },
                        },
                        {
                            text = "On WoW Forever, choose preferred Paladin blessings by class and role in group Buff coverage.",
                            linkless = true,
                        },
                        {
                            text = "On WoW Forever, the five-second mana-rule indicator is enabled by default. The one-time update preserves later deliberate changes, and the setting is easier to find in search.",
                            linkless = true,
                        },
                        {
                            text = "Added support for preset-controlled combat-timer retention and padded minutes.",
                            linkless = true,
                        },
                    },
                },
                {
                    title = "Bug Fixes",
                    bullets = {
                        {
                            text = "Fixed Warlock Spell Lock readiness staying red after sacrificing a Felhunter with Grimoire of Sacrifice. Readiness follows the granted player spell and switches back when the Felhunter is summoned again.",
                            link = {
                                pageKey = "opt_castbar",
                                query = "show on target castbar",
                                label = "Show on Target castbar",
                                sectionId = "castbar_interrupt_ready",
                                controlId = "menu2.opt.castbar.global.interrupt.ready.kick.ready.show.target",
                                settingKey = "general.kickReadyShowTarget",
                            },
                        },
                        {
                            text = "Fixed normal player casts disappearing after a late stop event from an earlier cast.",
                            linkless = true,
                        },
                        {
                            text = "Fixed synchronization of older saved profile groups that have no exclusion list.",
                            linkless = true,
                        },
                        {
                            text = "Preserve explicit unit and group health-background colors during texture and palette refreshes.",
                            linkless = true,
                        },
                        {
                            text = "Fixed dropdown middle-texture anchoring, color-shortcut artwork and overlapping text in selected-unitframe profile exports.",
                            linkless = true,
                        },
                        {
                            text = "Specific Paladin-blessing checks now hide while WoW Forever aura data is restricted.",
                            linkless = true,
                        },
                    },
                },
            },
        },
        {
            version = "6.505",
            date = "2026-10-31",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Added \"Right-click focus in combat\" to Boss Frames and Arena Frames under General > Frame Basics. When enabled, right-clicking a frame sets that unit as your focus during combat and opens its context menu outside combat. Each frame type has its own toggle, disabled by default.",
                            link = {
                                pageKey = "uf_boss",
                                query = "right click focus combat",
                                label = "Right-click focus in combat",
                                sectionId = "frame_basics",
                                controlId = "menu2.uf_boss.unit.basics.right_click_focus_in_combat",
                                settingKey = "boss.rightClickFocusInCombat",
                            },
                        },
                        {
                            text = "Texture layers have a new \"Class color / NPC type\" color mode: players use their class color and NPCs their NPC type color, independent of the health bar color.",
                            link = {
                                pageKey = "uf_player",
                                query = "texture layer color mode",
                                label = "Color mode",
                                sectionId = "texture_layer",
                                controlId = "menu2.uf_player.unit.texture_layer.colormode",
                                settingKey = "player.texLayerColorMode",
                                prepareKind = "unitTextureLayer",
                                prepareValue = "1_setup",
                            },
                        },
                    },
                },
                {
                    title = "Bug Fixes",
                    bullets = {
                        {
                            text = "Fixed Health Chunks in animated unit and group previews: health loss now shows the same fading chunks as the live frames, including their colors, opacity and rounded shapes.",
                            link = {
                                pageKey = "uf_player",
                                query = "chunked health loss",
                                label = "Chunked health loss",
                                sectionId = "frame_basics",
                                controlId = "menu2.uf_player.unit.basics.chunked_fill",
                                settingKey = "player.chunkedFill",
                            },
                        },
                        {
                            text = "Fixed Power Chunks in animated unit and group previews, including detached power bars: spent power now leaves the correct fading chunks, and stopping or hiding the preview clears them.",
                            link = {
                                pageKey = "uf_player",
                                query = "chunked power loss",
                                label = "Chunked power loss",
                                sectionId = "power_bar",
                                controlId = "menu2.uf_player.unit.power.powerchunkedfill",
                                settingKey = "player.powerChunkedFill",
                            },
                        },
                        {
                            text = "Fixed raid frames keeping OFFLINE, dead or AFK status, raid markers or range fading from the previous member after members swapped raid groups out of combat.",
                            linkless = true,
                        },
                        {
                            text = "Searching the options for a word such as \"pandemic\" now lists the options containing that word before related matches.",
                            linkless = true,
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        {
                            text = "The group name strip color is now edited through the section's ::: button, like other colors.",
                            linkless = true,
                        },
                    },
                },
            },
        },
        {
            version = "6.503",
            date = "2026-10-17",
            sections = {
                {
                    title = "Bug Fixes",
                    bullets = {
                        {
                            text = "Fixed extra or doubled stage markers on Evoker Empower castbars after a channeled spell, including Fire Breath and Eternity Surge.",
                            linkless = true,
                        },
                        {
                            text = "Restored the player castbar channel-selection behavior from before 6.502.",
                            linkless = true,
                        },
                        {
                            text = "Fixed raid and Mythic raid frames showing only groups 1-3 with profiles carried over from older versions. Old profile strings import correctly again without a page reset.",
                            linkless = true,
                        },
                        {
                            text = "Removed the group selection repair prompt after profile imports; it is no longer needed.",
                            linkless = true,
                        },
                        {
                            text = "The group frame preview now follows the sort settings, including sort mode, role order and class priority.",
                            linkless = true,
                        },
                        {
                            text = "Dragging a class in the class priority list now inserts it at the drop position instead of swapping it with the class there.",
                            link = {
                                pageKey = "gf_layout",
                                query = "class priority sorting",
                                label = "Use class priority",
                                sectionId = "sorting",
                                controlId = "menu2.gf_layout.group.field.sortclasspriority",
                                settingKey = "gf_raid.sortClassPriority",
                                prepareKind = "groupScope",
                                prepareValue = "raid",
                            },
                        },
                        {
                            text = "Arena party frames sorted by class priority within roles now update when a teammate's name arrives late.",
                            linkless = true,
                        },
                    },
                },
            },
        },
        {
            version = "6.502",
            date = "2026-10-15",
            sections = {
                {
                    title = "Bug Fixes",
                    bullets = {
                        {
                            text = "Raid slots and layouts now stay stable during combat, keeping displayed names and click targets aligned. Pending roster and layout changes are applied after combat.",
                            linkless = true,
                        },
                        {
                            text = "Raid and Mythic Raid frames now refresh their member state when roster assignments change, including during combat, instead of retaining the previous occupant's name, class color or status.",
                            linkless = true,
                        },
                        {
                            text = "Group Frame Reset Page now restores the complete factory configuration, including raid layout limits, aura settings and profile overrides, so old filters cannot leave groups hidden after a reset.",
                            link = {
                                pageKey = "gf_layout",
                                query = "raid frame width layout",
                                label = "Group Frame settings",
                                sectionId = "scaling",
                                controlId = "menu2.gf_layout.group.field.width",
                                settingKey = "gf_raid.width",
                                prepareKind = "groupScope",
                                prepareValue = "raid",
                            },
                        },
                        {
                            text = "Imports of old profiles preserve their existing group selection and offer one optional repair for ambiguous legacy filters. The repair changes only the affected filters and preserves explicit exclusions and profile variants.",
                            linkless = true,
                        },
                        {
                            text = "Group aura edits made through Copy To, preview icon movement or a partial aura-settings import now activate the custom renderer when required. Reading settings no longer changes the renderer.",
                            linkless = true,
                        },
                        {
                            text = "Player castbars now select an active channel when a channel starts while the outgoing cast is still reported, preventing the old cast from masking the channel.",
                            linkless = true,
                        },
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
