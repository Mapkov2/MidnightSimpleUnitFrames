-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "754B6C29C3FAB34FD5EA950840341C8FD811526B5248F385368FDC38BC1965B3",
    currentVersion = "6.509",
    historyFromVersion = "6.506",
    previousVersion = "6.506",
    rangeLabel = "6.506 -> 6.509",
    entries = {
        {
            version = "6.509",
            date = "2026-11-06",
            sections = {
                {
                    title = "Unit frame positioning",
                    bullets = {
                        {
                            text = "Fixed drag and runtime layout using different anchors in Suite profiles, and preserved visible positions across UI scaling and screen-edge clamping.",
                            link = {
                                pageKey = "opt_misc",
                                query = "show blizzard frames in msuf edit mode",
                                label = "Show Blizzard frames in MSUF Edit Mode",
                                sectionId = "misc_external_edit_mode",
                                controlId = "menu2.opt.misc.global.setting.blizzard.edit.mode.integration",
                                settingKey = "general.blizzardEditModeIntegration",
                            },
                        },
                        {
                            text = "Fixed drag completion saving offsets against an outdated anchor when a provider appears, changes, or loses its position. Mouse release, closing Edit Mode during a drag, and external Edit Mode shells now preserve the final visible position in the current anchor space.",
                            linkless = true,
                        },
                        {
                            text = "Fixed unfinished X/Y popup edits overwriting a later mouse drag. Typed edits and dragging retain separate Undo steps.",
                            linkless = true,
                        },
                    },
                },
            },
        },
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
