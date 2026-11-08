-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "79F5B238A00C6D9EE2E9D05B3D8FC3B2F6CABA3C1EEE52A3085F8CAD889C478F",
    currentVersion = "6.511",
    historyFromVersion = "6.508",
    previousVersion = "6.508",
    rangeLabel = "6.508 -> 6.511",
    entries = {
        {
            version = "6.511",
            date = "2026-11-08",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Open-world faction badges. On Retail and WoW Forever, Target and Focus can optionally show the faction symbol for unflagged players in the open world, including on PvE realms. The option is off by default.",
                            link = {
                                pageKey = "uf_target",
                                query = "faction symbol without pvp flag",
                                label = "Faction Symbol Without PvP Flag",
                                sectionId = "status_icons",
                                controlId = "menu2.uf_target.unit.status.pvp.open_world_faction",
                                settingKey = "target.pvpIndicatorShowOpenWorldFaction",
                                prepareKind = "unitStatus",
                                prepareValue = "statusPvp",
                            },
                        },
                    },
                },
                {
                    title = "Bug Fixes",
                    bullets = {
                        {
                            text = "PvP icons refresh on flag changes without a reload. Target and Focus follow their own PvP flag, and on Retail the Player icon clears when War Mode is turned off.",
                            linkless = true,
                        },
                    },
                },
            },
        },
        {
            version = "6.510",
            date = "2026-11-07",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Party, Raid and Mythic Raid frames can each use their own health gradient and bar background. Configure the gradient stops, background color mode and whether the background fills the bar or only shows missing health.",
                            linkless = true,
                        },
                        {
                            text = "WoW Forever swing timers now show draggable bars in Edit Mode. The options preview lets you inspect individual layers, jump to their settings, and see the out-of-range color and opacity for each weapon slot.",
                            linkless = true,
                        },
                        {
                            text = "Menu appearance presets now apply to the MSUF menu when MapkoSkin is installed. Pick MapkoSkin from the same list to switch back to its look.",
                            link = {
                                pageKey = "opt_misc",
                                query = "menu appearance preset",
                                label = "Menu appearance preset",
                                sectionId = "misc_menu_behavior",
                                controlId = "menu2.opt.misc.global.setting.menu.appearance.preset",
                                settingKey = "general.menuAppearancePreset",
                            },
                        },
                    },
                },
                {
                    title = "Fixes and polish",
                    bullets = {
                        {
                            text = "Fixed health bars retaining the old texture after switching away from the Blizzard preset.",
                            linkless = true,
                        },
                        {
                            text = "Choosing the global health bar color mode now clears preset overrides on individual unit frames, so the chosen mode takes effect immediately.",
                            link = {
                                pageKey = "opt_colors",
                                query = "bar mode",
                                label = "Bar mode",
                                sectionId = "colors_appearance",
                                controlId = "menu2.opt.colors.advanced.appearance.bar.mode",
                                settingKey = "general.barMode",
                            },
                        },
                        {
                            text = "The compact color picker now shows opacity for colors that support it, so you can restore a tint saved at 0% opacity.",
                            linkless = true,
                        },
                        {
                            text = "Improved the Class Resources preview for alternative mana and player health colors. Refined selected tabs, sidebar markers and window buttons, and made section actions appear when you hover over or focus the header.",
                            linkless = true,
                        },
                    },
                },
            },
        },
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
