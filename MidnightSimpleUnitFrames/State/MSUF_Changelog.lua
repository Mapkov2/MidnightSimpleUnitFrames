-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "A54FD9B288FEC0520DE41905191AFC8E62BA928175BA728EBD24AA00488D61C5",
    currentVersion = "6.508",
    historyFromVersion = "6.505",
    previousVersion = "6.505",
    rangeLabel = "6.505 -> 6.508",
    entries = {
        {
            version = "6.508",
            date = "2026-11-05",
            sections = {
                {
                    title = "Improvements",
                    bullets = {
                        {
                            text = "Expanded the WoW Forever MP5/mana-regeneration tracker with a moving glow inside the mana bar or separate timer bars. Track the five-second rule and mana-return ticks, adjust marker width and glow, and preview the same display in the options menu. Both indicators are enabled once by default on Forever; later manual choices are preserved.",
                            linkless = true,
                        },
                        {
                            text = "Added optional native Castbar artwork, a dark cast-name panel and the bundled MSUF Castbar fill texture. Artwork appears in live castbars, Edit Mode and menu previews, with immediate preview updates when settings change.",
                            link = {
                                pageKey = "opt_castbar",
                                query = "castbar artwork",
                                label = "Castbar artwork",
                                sectionId = "castbar_textures",
                                controlId = "menu2.opt.castbar.global.textures.castbar.artwork.enabled",
                                settingKey = "general.castbarArtworkEnabled",
                            },
                        },
                        {
                            text = "Improved search discovery for MP5, the five-second rule and mana-regeneration display settings.",
                            linkless = true,
                        },
                    },
                },
                {
                    title = "Bug Fixes",
                    bullets = {
                        {
                            text = "Fixed Power text size controls in Class Resources when the Player frame uses text-slot overrides. Both menus now edit the same selected slot and keep font inheritance, previews, Copy and Reset consistent.",
                            linkless = true,
                        },
                        {
                            text = "Fixed malformed or truncated compressed profile imports raising a Lua error instead of being rejected safely.",
                            linkless = true,
                        },
                        {
                            text = "Improved the readability and refresh behavior of selected menu navigation entries.",
                            linkless = true,
                        },
                        {
                            text = "Added host-page compatibility for Suite Gameplay controls and preserved legacy castbar fill paths when moving artwork settings into native MSUF.",
                            linkless = true,
                        },
                    },
                },
            },
        },
        {
            version = "6.507",
            date = "2026-11-04",
            sections = {
                {
                    title = "Bug Fixes",
                    bullets = {
                        {
                            text = "Fixed health bars on Pet Target, Target of Target, and Focus Target jumping to unrelated units' health. Each frame now follows its own target and honors Smooth Fill and Chunked Health Loss.",
                            linkless = true,
                        },
                        {
                            text = "Fixed the first damage step in the Unitframe preview losing its Chunked Health Loss trail after a sample health gain.",
                            link = {
                                pageKey = "uf_targettarget",
                                query = "chunked health loss",
                                label = "Chunked health loss",
                                sectionId = "frame_basics",
                                controlId = "menu2.uf_targettarget.unit.basics.chunked_fill",
                                settingKey = "targettarget.chunkedFill",
                            },
                        },
                    },
                },
            },
        },
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
