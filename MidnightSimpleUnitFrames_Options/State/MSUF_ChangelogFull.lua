-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "E31573BD88A506983F51D4A8560B26958425A983E87BACD28AD19B010CB66DFA",
    currentVersion = "6.50",
    historyFromVersion = "6.02",
    previousVersion = "6.02",
    rangeLabel = "6.02 -> 6.50",
    entries = {
        {
            version = "6.50",
            date = "2026-10-09",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "MSUF 6.50 completes the 6.5 line. It brings 104 new features and changes, 103 bug fixes and 20 performance improvements, including Arena Frames, Pet Target, Slanted Frames and Cosmetic Texture Layers. On WoW 12.1.5 the login greeting sums this up; turn it off under Global > Misc > Show welcome message.",
                            link = {
                                pageKey = "opt_misc",
                                query = "show welcome message",
                                label = "Show welcome message",
                                sectionId = "misc_startup",
                                controlId = "menu2.opt.misc.global.setting.show.welcome.message",
                                settingKey = "general.showWelcomeMessage",
                            },
                        },
                        {
                            text = "Arena Frames: dedicated opponent frames with their own castbars, auras, settings and Edit Mode movers, including preparation, stealth and trinket states. Midnight supports three opponents; TBC and Mists support five.",
                            link = {
                                pageKey = "uf_arena",
                                query = "arena frames enable",
                                label = "Arena Frames",
                                sectionId = "frame_basics",
                                controlId = "menu2.uf_arena.unit.basics.enabled",
                                settingKey = "arena.enabled",
                            },
                        },
                        {
                            text = "Pet Target: a separate frame for your pet's target, with independent styling, settings, preview and placement.",
                            link = {
                                pageKey = "uf_pettarget",
                                query = "pet target enable",
                                label = "Pet Target",
                                sectionId = "frame_basics",
                                controlId = "menu2.uf_pettarget.unit.basics.enabled",
                                settingKey = "pettarget.enabled",
                            },
                        },
                        {
                            text = "Pet Auras: configurable buff and debuff lanes directly on the Pet frame, plus client-supported Pet XP and Pet Happiness.",
                            link = {
                                pageKey = "uf_pet",
                                query = "pet buff aura visible",
                                label = "Pet buff visibility",
                                sectionId = "auras",
                                controlId = "menu2.uf_pet.auras.unit-workspace.lane.buff.layout.visible",
                                settingKey = "auras3.pet.buff.visible",
                            },
                        },
                        {
                            text = "Slanted Frames: angular shapes for supported Unit and Group Frames, Power bars, castbars and Class Resources. True Outline and Texture borders now follow both Slanted and Rounded edges, keep the selected outline color, and each frame scope can use its own cut direction.",
                            link = {
                                pageKey = "opt_bars",
                                query = "enable slanted bars",
                                label = "Enable slanted bars",
                                sectionId = "bars_slanted",
                                controlId = "menu2.opt.bars.global.slanted.enabled",
                                settingKey = "bars.slantedBarsEnabled",
                            },
                        },
                        {
                            text = "Cosmetic Texture Layering: decorate each Unit Frame with up to three independent texture layers. Choose textures or supported Blizzard artwork and adjust placement, size, opacity, colors, crop and mirroring, with matching previews.",
                            link = {
                                pageKey = "uf_player",
                                query = "enable texture layer",
                                label = "Enable Texture Layer",
                                sectionId = "texture_layer",
                                controlId = "menu2.uf_player.unit.texture_layer.enabled",
                                settingKey = "player.texLayerEnabled",
                                prepareKind = "unitTextureLayer",
                                prepareValue = "1_setup",
                            },
                        },
                        {
                            text = "Unified client support: one source for Midnight, Classic Era, TBC, Mists and WoW Forever, with client-appropriate settings and runtime behavior.",
                            linkless = true,
                        },
                    },
                },
                {
                    title = "Group layouts and organisation",
                    bullets = {
                        {
                            text = "Name strips: give group names a separate strip above the health bar, with adjustable height, color and opacity.",
                            link = {
                                pageKey = "gf_layout",
                                query = "name strip above health bar",
                                label = "Show names on a strip above the health bar",
                                sectionId = "name_bar",
                                controlId = "menu2.gf_layout.group.field.namebarenabled",
                                settingKey = "gf_party.nameBarEnabled",
                                prepareKind = "groupScope",
                                prepareValue = "party",
                            },
                        },
                        {
                            text = "Member target frames: display group members' targets in a separate block, with independent position and dimensions and an option to include your own target.",
                            link = {
                                pageKey = "gf_layout",
                                query = "member target frames",
                                label = "Member targets",
                                sectionId = "party_targets",
                                controlId = "menu2.gf_layout.group.field.targetsenabled",
                                settingKey = "gf_party.targetsEnabled",
                                prepareKind = "groupScope",
                                prepareValue = "party",
                            },
                        },
                        {
                            text = "Group Pet frames: use a separate pet block with its own position, dimensions, columns, text size and pet-count limit.",
                            link = {
                                pageKey = "gf_layout",
                                query = "group pet frames",
                                label = "Pet frames",
                                sectionId = "group_pets",
                                controlId = "menu2.gf_layout.group.field.petsenabled",
                                settingKey = "gf_raid.petsEnabled",
                                prepareKind = "groupScope",
                                prepareValue = "raid",
                            },
                        },
                        {
                            text = "Healer mana rows: show a separate mana row for members with the assigned Healer role, with independent placement, size, amount text and text color.",
                            link = {
                                pageKey = "gf_layout",
                                query = "healer mana bars",
                                label = "Healer mana bars",
                                sectionId = "healer_mana",
                                controlId = "menu2.gf_layout.group.field.healermanaenabled",
                                settingKey = "gf_raid.healerManaEnabled",
                                prepareKind = "groupScope",
                                prepareValue = "raid",
                            },
                        },
                        {
                            text = "Allied boss frames: display dedicated friendly-boss frames on clients with boss units, optionally restricted to players with the assigned Healer role.",
                            link = {
                                pageKey = "gf_layout",
                                query = "allied boss frames",
                                label = "Allied boss frames",
                                sectionId = "friendly_bosses",
                                controlId = "menu2.gf_layout.group.field.friendlybossenabled",
                                settingKey = "gf_party.friendlyBossEnabled",
                                prepareKind = "groupScope",
                                prepareValue = "party",
                            },
                        },
                        {
                            text = "Raid-size layouts: choose manual or group-size scaling and separate width, height, growth, scale and optional position for 1-10, 11-20, 21-25 and 26+ players. Base dimensions remain the fallback.",
                            link = {
                                pageKey = "gf_layout",
                                query = "raid size overrides",
                                label = "Use raid size overrides",
                                sectionId = "scaling",
                                controlId = "menu2.gf_layout.group.field.layouttiersenabled",
                                settingKey = "gf_raid.layoutTiersEnabled",
                                prepareKind = "groupScope",
                                prepareValue = "raid",
                            },
                        },
                        {
                            text = "Scale related visuals: indicators, aura icons and tracked buffs can independently scale with frame dimensions. Hidden groups can be excluded from the size calculation.",
                            link = {
                                pageKey = "gf_layout",
                                query = "scale indicators with frame dimensions",
                                label = "Scale indicators with frame dimensions",
                                sectionId = "scaling",
                                controlId = "menu2.gf_layout.group.field.autoscaleindicatorsonresize",
                                settingKey = "gf_raid.autoScaleIndicatorsOnResize",
                                prepareKind = "groupScope",
                                prepareValue = "raid",
                            },
                        },
                        {
                            text = "Class priority sorting: drag classes into a preferred order within the configured group and role order. Eligible raid role layouts can sort names alphabetically within roles.",
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
                            text = "Raid-wide role sorting: the unified line includes sorting tanks, healers and damage dealers across the whole raid, including supported preserved-group layouts.",
                            link = {
                                pageKey = "gf_layout",
                                query = "sort roles across entire raid",
                                label = "Sort roles across entire raid",
                                sectionId = "sorting",
                                controlId = "menu2.gf_layout.group.field.sortrolesacrossraid",
                                settingKey = "gf_raid.sortRolesAcrossRaid",
                                prepareKind = "groupScope",
                                prepareValue = "raid",
                            },
                        },
                        {
                            text = "Small-raid organisation: use Party layout for raids of up to five players, center solo layouts, collapse empty preserved groups and hide groups 5-8 in supported Mythic raids.",
                            link = {
                                pageKey = "gf_layout",
                                query = "party layout small raids",
                                label = "Use Party layout for raids up to 5 players",
                                sectionId = "layout_advanced",
                                controlId = "menu2.gf_layout.group.field.smallraidasparty",
                                settingKey = "gf_party.smallRaidAsParty",
                                prepareKind = "groupScope",
                                prepareValue = "party",
                            },
                        },
                        {
                            text = "Header switches: Name strip, Member targets, Pet frames, Allied boss frames, Healer mana bars and Forever Buff coverage can be toggled while their accordion is closed.",
                            link = {
                                pageKey = "gf_layout",
                                query = "healer mana bars",
                                label = "Healer mana bars",
                                sectionId = "healer_mana",
                                controlId = "menu2.gf_layout.group.field.healermanaenabled",
                                settingKey = "gf_raid.healerManaEnabled",
                                prepareKind = "groupScope",
                                prepareValue = "raid",
                            },
                        },
                        {
                            text = "Healer mana colors: text color lives under Colors > Group > Healer mana bars and remains available through the section's three-dot shortcut. Existing values are retained, and edits follow the shared Party, Raid and Mythic Raid color behavior.",
                            link = {
                                pageKey = "opt_colors",
                                query = "healer mana text color",
                                label = "Healer mana text color",
                                sectionId = "colors_group_frames_healer_mana",
                                controlId = "menu2.opt.colors.advanced.group.frame.healer.mana.text.color",
                                settingKey = "gf_party.healerManaTextR",
                            },
                        },
                        {
                            text = "Threat percentage: Classic Era, TBC and Forever can show Threat % on supported Target, Focus, Boss, Party and Raid frames; 100% means you have aggro. Group values use your current target. Placement, size, background and low/medium/high colors are adjustable. Party starts enabled in the supplied defaults; Raid is opt-in.",
                            link = {
                                pageKey = "uf_target",
                                query = "target threat percent",
                                label = "Threat %",
                                sectionId = "status_icons",
                                controlId = "menu2.uf_target.unit.status.selected.enabled",
                                settingKey = "target.showThreatIndicator",
                                prepareKind = "unitStatus",
                                prepareValue = "statusThreat",
                            },
                        },
                        {
                            text = "Group level text: Party and Raid can show optional level text with difficulty coloring; it starts disabled.",
                            link = {
                                pageKey = "gf_indicators",
                                query = "group level text",
                                label = "Level Text",
                                sectionId = "sicons",
                                controlId = "menu2.gf_indicators.group.status.selected.enabled",
                                settingKey = "gf_party.levelText",
                                prepareKind = "groupStatus",
                                prepareValue = "party_levelText",
                            },
                        },
                    },
                },
                {
                    title = "Unit frames and status information",
                    bullets = {
                        {
                            text = "Pet Target: a complete independent Unit Frame with its own controls, defaults, preview and placement.",
                            link = {
                                pageKey = "uf_pettarget",
                                query = "pet target enable",
                                label = "Pet Target",
                                sectionId = "frame_basics",
                                controlId = "menu2.uf_pettarget.unit.basics.enabled",
                                settingKey = "pettarget.enabled",
                            },
                        },
                        {
                            text = "Pet information: configurable buffs and debuffs, client-gated XP and Pet Happiness. Forever uses Blizzard's three happiness atlases when available.",
                            link = {
                                pageKey = "uf_pet",
                                query = "pet happiness",
                                label = "Pet Happiness",
                                sectionId = "status_icons",
                                controlId = "menu2.uf_pet.unit.status.selected.enabled",
                                settingKey = "pet.showPetHappinessIndicator",
                                prepareKind = "unitStatus",
                                prepareValue = "statusPetHappiness",
                            },
                        },
                        {
                            text = "Difficulty-colored levels: configurable red, orange, white, green and gray bands identify relative difficulty, including unknown levels. Existing per-frame level colors are retained where already selected.",
                            link = {
                                pageKey = "uf_target",
                                query = "level difficulty colors",
                                label = "Level Difficulty Colors",
                                sectionId = "status_icons",
                                controlId = "menu2.uf_target.unit.status.level.difficulty_color",
                                settingKey = "target.levelIndicatorDifficultyColor",
                            },
                        },
                        {
                            text = "Round level badge: an optional gold-rimmed badge follows the level indicator's position, size and layer, using native artwork or a bundled fallback.",
                            link = {
                                pageKey = "uf_player",
                                query = "round level badge",
                                label = "Round Level Badge",
                                sectionId = "status_icons",
                                controlId = "menu2.uf_player.unit.status.level.forever_badge",
                                settingKey = "player.levelIndicatorForeverBadge",
                                prepareKind = "unitStatus",
                                prepareValue = "level",
                            },
                        },
                        {
                            text = "Tagged mobs: optionally gray names and applicable health-bar colors for mobs tagged by another player.",
                            link = {
                                pageKey = "opt_colors",
                                query = "gray out mobs tagged by others",
                                label = "Gray out mobs tagged by others",
                                sectionId = "colors_unit",
                                controlId = "menu2.opt.colors.advanced.npc.tap.denied.gray",
                                settingKey = "general.tapDeniedGray",
                            },
                        },
                        {
                            text = "Classic load conditions: expose No target and Out of combat and no target where supported.",
                            link = {
                                pageKey = "uf_player",
                                query = "hide no target load condition",
                                label = "No target",
                                sectionId = "load_conditions",
                                controlId = "menu2.uf_player.unit.load_condition.loadcondhidenotarget",
                                settingKey = "player.loadCondHideNoTarget",
                            },
                        },
                        {
                            text = "Forever names: choose full character name, first name or surname through the Fonts page where the name is readable.",
                            link = {
                                pageKey = "opt_fonts",
                                query = "character names first name surname",
                                label = "Character names (all frames)",
                                sectionId = "fonts_name_shortening",
                                controlId = "menu2.opt.fonts.global.name.shortening.character.name.parts",
                                settingKey = "general.characterNameParts",
                            },
                        },
                        {
                            text = "Incoming-heal prediction: supported Classic clients can opt into prediction from all healers; player-only prediction remains the default.",
                            link = {
                                pageKey = "opt_bars",
                                query = "include healing from others",
                                label = "Include healing from others",
                                sectionId = "bars_absorb",
                                controlId = "menu2.opt.bars.global.absorb.heal.prediction.all.healers",
                                settingKey = "general.healPredAllHealers",
                                prepareKind = "barsScope",
                                prepareValue = "shared",
                            },
                        },
                        {
                            text = "Health and prediction appearance: the unified line includes independent Full bar or Missing health only backgrounds, configurable color sources and Keep Absorbs + Prediction Visible.",
                            link = {
                                pageKey = "opt_colors",
                                query = "background fill missing health only",
                                label = "Background Fill",
                                sectionId = "colors_background",
                                controlId = "menu2.opt.colors.advanced.background.fill.mode",
                                settingKey = "general.barBgFillMode",
                            },
                        },
                        {
                            text = "Text visibility: the unified line retains independent Name, Health and Power mouseover visibility with fade timing, and injured-only Unit Frame visibility.",
                            link = {
                                pageKey = "uf_player",
                                query = "name text mouseover",
                                label = "Only show on mouseover",
                                sectionId = "text",
                                controlId = "menu2.uf_player.unit.text.name.mouseover",
                                settingKey = "player.nameTextMouseover",
                            },
                        },
                    },
                },
                {
                    title = "Shapes, borders, portraits and artwork",
                    bullets = {
                        {
                            text = "Slanted scopes: configure Unit Frames, Group Frames, Power bars, castbars, Class Resources and mouseover surfaces with matching previews.",
                            link = {
                                pageKey = "opt_bars",
                                query = "slanted unit frames",
                                label = "Unit frames",
                                sectionId = "bars_slanted",
                                controlId = "menu2.opt.bars.global.slanted.units",
                                settingKey = "bars.slantedUnitFrames",
                            },
                        },
                        {
                            text = "Rounded fallback: turning off Slanted restores the active Rounded fallback without discarding saved frame styles, including imported profiles.",
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
                            text = "Styled shaped borders: True Outline and Texture borders follow rounded corners and slanted edges on Unit and Group Frames, with matching style, color and thickness in previews. Configure them under Bars > Frame Outline.",
                            link = {
                                pageKey = "opt_bars",
                                query = "frame outline style",
                                label = "Outline style",
                                sectionId = "bars_outline",
                                controlId = "menu2.opt.bars.global.outline.texture",
                                settingKey = "bars.barOutlineTexture",
                                prepareKind = "barsScope",
                                prepareValue = "shared",
                            },
                        },
                        {
                            text = "Frame-shape controls: configure shapes through Bars and Group Layout. The duplicate shape picker in each unit's Frame Basics section has been removed.",
                            link = {
                                pageKey = "gf_layout",
                                query = "group frame bar shape",
                                label = "Frame bar shape",
                                sectionId = "general",
                                controlId = "menu2.gf_layout.group.basics.frame_bar_shape",
                                settingKey = "gf_party.frameBarShape",
                                prepareKind = "groupScope",
                                prepareValue = "party",
                            },
                        },
                        {
                            text = "Per-frame cut direction: Slanted Unit, Group and castbar scopes can follow the shared cut direction or use their own. Bars, castbar and group previews show the chosen cut.",
                            link = {
                                pageKey = "opt_bars",
                                query = "cut direction",
                                label = "Cut direction",
                                sectionId = "bars_slanted",
                                controlId = "menu2.opt.bars.global.slanted.direction",
                                settingKey = "bars.slantedBarDirection",
                            },
                        },
                        {
                            text = "Outline colors across shapes: Texture and True Outline borders use the selected outline color on square, rounded and slanted frames, while active highlights keep their own colors. Set the shared color under Colors > Bar & Prediction Colors > Bar Outline Color.",
                            link = {
                                pageKey = "opt_colors",
                                query = "bar outline color",
                                label = "Bar Outline Color",
                                sectionId = "colors_bar_colors",
                                controlId = "menu2.opt.colors.advanced.bar.outline.color",
                                settingKey = "general.barOutlineColor",
                            },
                        },
                        {
                            text = "Texture Layer strata: layers always draw at their Unit Frame's strata. The ineffective strata choice was replaced by an explanation in the layer settings.",
                            link = {
                                pageKey = "uf_player",
                                query = "texture layer layer",
                                label = "Layer (0-30)",
                                sectionId = "texture_layer",
                                controlId = "menu2.uf_player.unit.texture_layer.level",
                                settingKey = "player.texLayerLevel",
                                prepareKind = "unitTextureLayer",
                                prepareValue = "1_advanced",
                            },
                        },
                        {
                            text = "Cosmetic Texture Layers: up to three decoration slots per Unit Frame, with independent textures, geometry, opacity and layering. Crop, mirror, class-color and health-gradient options support decorative accents, with optional target/combat conditions and matching previews.",
                            link = {
                                pageKey = "uf_player",
                                query = "enable texture layer",
                                label = "Enable Texture Layer",
                                sectionId = "texture_layer",
                                controlId = "menu2.uf_player.unit.texture_layer.enabled",
                                settingKey = "player.texLayerEnabled",
                                prepareKind = "unitTextureLayer",
                                prepareValue = "1_setup",
                            },
                        },
                        {
                            text = "Portrait dragons: Blizzard-style portraits offer elite, rare and boss decorations, with additional placement, size and layering choices.",
                            link = {
                                pageKey = "uf_target",
                                query = "elite rare dragon portrait",
                                label = "Elite and rare dragon",
                                sectionId = "portrait",
                                controlId = "menu2.uf_target.unit.portrait.portraitblizzardelite",
                                settingKey = "target.portraitBlizzardElite",
                                prepareKind = "unitPortraitTab",
                                prepareValue = "border",
                            },
                        },
                        {
                            text = "Portrait connector and rim: add the bottom-right gold connector and suppress a duplicate standalone rim when complete Blizzard frame artwork already includes one.",
                            link = {
                                pageKey = "uf_player",
                                query = "portrait gold corner connector",
                                label = "Gold corner connector",
                                sectionId = "portrait",
                                controlId = "menu2.uf_player.unit.portrait.portraitblizzardcorner",
                                settingKey = "player.portraitBlizzardCorner",
                                prepareKind = "unitPortraitTab",
                                prepareValue = "border",
                            },
                        },
                        {
                            text = "Portrait adjustments: zoom, left-to-right flip, inset-shadow strength and corner direction, with matching per-unit previews.",
                            link = {
                                pageKey = "uf_player",
                                query = "portrait zoom",
                                label = "Portrait zoom",
                                sectionId = "portrait",
                                controlId = "menu2.uf_player.unit.portrait.portraitzoom",
                                settingKey = "player.portraitZoom",
                            },
                        },
                        {
                            text = "Temporary portrait preview: preview classification artwork on the live portrait; closing the section or entering combat restores the real unit classification.",
                            linkless = true,
                        },
                        {
                            text = "Native atlas Texture Layers: use Blizzard atlases with matching runtime and preview crops and an ordinary texture fallback when the atlas is unavailable.",
                            linkless = true,
                        },
                        {
                            text = "Native status artwork: leader, assistant and combat indicators use matching native art where available and texture fallbacks on older clients.",
                            link = {
                                pageKey = "uf_player",
                                query = "leader indicator",
                                label = "Leader",
                                sectionId = "status_icons",
                                controlId = "menu2.uf_player.unit.status.selected.enabled",
                                settingKey = "player.showLeaderIcon",
                                prepareKind = "unitStatus",
                                prepareValue = "leader",
                            },
                        },
                        {
                            text = "Menu appearances: Classic Glass, Midnight and Midnight Dark are available across supported clients.",
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
                    title = "Class Resources and Additional Resources",
                    bullets = {
                        {
                            text = "Independent Edit Mode movers: move Class Resources and detached Player Power together or separately. Inactive resources, including Druid Combo Points outside Cat Form, retain an editable mover.",
                            link = {
                                pageKey = "classpower",
                                query = "class resource x offset",
                                label = "Class Resource X offset",
                                sectionId = "classpower_display",
                                controlId = "menu2.classpower.advanced.layout.x",
                                settingKey = "bars.classPowerOffsetX",
                            },
                        },
                        {
                            text = "Detached Power geometry: independent width, height and position controls; Energy bars anchored to Combo Points continue to follow them.",
                            link = {
                                pageKey = "classpower",
                                query = "detached power width",
                                label = "Power width",
                                sectionId = "classpower_detached_power",
                                controlId = "menu2.classpower.advanced.detached.power.layout.width",
                                settingKey = "player.detachedPowerBarWidth",
                            },
                        },
                        {
                            text = "Full Player-frame width: Class Resources using Player frame width span the full frame.",
                            link = {
                                pageKey = "classpower",
                                query = "class resource width mode",
                                label = "Width mode",
                                sectionId = "classpower_display",
                                controlId = "menu2.classpower.advanced.layout.width.mode",
                                settingKey = "bars.classPowerWidthMode",
                            },
                        },
                        {
                            text = "Resource workspace: direct resource selection, scoped controls, Copy To, Quick Setup and reset actions in one shared workspace.",
                            linkless = true,
                        },
                        {
                            text = "Dedicated helper controls: Additional Resources have their own sections, color shortcuts and runtime-rendered previews.",
                            linkless = true,
                        },
                        {
                            text = "Marks and thresholds: place absolute or percentage marks on Player Power, Class Resource or Alternative Mana; restrict by power type, choose width and color, and change color above or below a threshold.",
                            link = {
                                pageKey = "classpower",
                                query = "add resource mark",
                                label = "Add resource mark",
                                sectionId = "classpower_resource_marks",
                                controlId = "menu2.classpower.advanced.resource.extras.marks.add",
                                settingKey = "bars.resourceMarks",
                            },
                        },
                        {
                            text = "Mana spend preview: show upcoming mana costs. Supported clients also provide regeneration-pause and mana-return helpers.",
                            link = {
                                pageKey = "classpower",
                                query = "mana spend preview",
                                label = "Mana spend preview",
                                sectionId = "classpower_resource_extras",
                                controlId = "menu2.classpower.advanced.resource.extras.mana.upcoming.cost",
                                settingKey = "bars.manaUpcomingCost",
                            },
                        },
                        {
                            text = "Midnight resource helpers: Ignore Pain duration and Arcane window timing, with shared geometry and separate colors.",
                            link = {
                                pageKey = "classpower",
                                query = "ignore pain duration",
                                label = "Ignore Pain duration",
                                sectionId = "classpower_resource_pain",
                                controlId = "menu2.classpower.advanced.resource.extras.show.ignore.pain",
                                settingKey = "bars.showIgnorePain",
                            },
                        },
                        {
                            text = "Arcane timing modes: seconds, global cooldowns or both, with adjustable countdown visibility, warning timing and phase colors.",
                            link = {
                                pageKey = "classpower",
                                query = "arcane window text",
                                label = "Arcane window text",
                                sectionId = "classpower_resource_arcane",
                                controlId = "menu2.classpower.advanced.resource.extras.arcane.window.text",
                                settingKey = "bars.arcaneWindowText",
                            },
                        },
                        {
                            text = "Out-of-combat hiding: optionally hide Player Power together with Class Resource when Hide out of combat is enabled. Edit Mode keeps both visible for placement.",
                            link = {
                                pageKey = "classpower",
                                query = "hide player power with class resource",
                                label = "Hide player power with Class Resource",
                                sectionId = "classpower_visibility",
                                controlId = "menu2.classpower.advanced.visibility.sync.player.power.ooc",
                                settingKey = "bars.classPowerSyncPlayerPowerOOC",
                            },
                        },
                        {
                            text = "Explicit Mana and Alternative Mana: client-specific resource selection, placement and text settings remain available alongside the main class resource.",
                            link = {
                                pageKey = "classpower",
                                query = "mana automatic displayed resource",
                                label = "Displayed resource",
                                sectionId = "classpower_detached_power",
                                controlId = "menu2.classpower.advanced.detached.power.layout.resource.source",
                                settingKey = "player.playerPowerSource",
                            },
                        },
                        {
                            text = "Additional resource colors: helper colors are available under Colors > Additional resource colors.",
                            link = {
                                pageKey = "opt_colors",
                                query = "additional resource colors",
                                label = "Mana spend preview",
                                sectionId = "colors_resource_extras",
                                controlId = "menu2.colors.advanced.resource.extras.mana.cost.color",
                                settingKey = "bars.manaCostColor",
                            },
                        },
                    },
                },
                {
                    title = "Auras and castbars",
                    bullets = {
                        {
                            text = "Pet aura lanes: configure Pet buffs and debuffs independently on the Pet page.",
                            link = {
                                pageKey = "uf_pet",
                                query = "pet buff aura visible",
                                label = "Pet buff visibility",
                                sectionId = "auras",
                                controlId = "menu2.uf_pet.auras.unit-workspace.lane.buff.layout.visible",
                                settingKey = "auras3.pet.buff.visible",
                            },
                        },
                        {
                            text = "Rank-aware Classic matching: Era, TBC and Mists can match readable aura names when spell ranks or cast IDs differ from the visible aura ID. Their generated alias catalogs are no longer loaded or packaged.",
                            linkless = true,
                        },
                        {
                            text = "Forever aura aliases: rebuilt the localized spell-name catalog from all eleven build-70009 locale exports and revalidated the curated aura IDs.",
                            linkless = true,
                        },
                        {
                            text = "Aura workspaces: the unified line includes scope-specific ordering and filtering, the curated MSUF Highlights Group Buff filter, custom-priority containers and combat collection in the blacklist workspace.",
                            link = {
                                pageKey = "gf_auras",
                                query = "msuf highlights buff filter",
                                label = "MSUF Highlights",
                                sectionId = "auras",
                                controlId = "menu2.gf_auras.auras.group-workspace.lane.buff.tool-selector",
                                settingKey = "gf_party.auras.buff.filterToken",
                                prepareKind = "groupAuraWorkspace",
                                prepareValue = "party_buff_filters",
                            },
                        },
                        {
                            text = "Native Mainline tooltip options: aura caster names and spell IDs follow client availability.",
                            link = {
                                pageKey = "opt_misc",
                                query = "aura tooltip caster names",
                                label = "Show caster names in aura tooltips",
                                sectionId = "misc_tooltips",
                                controlId = "menu2.opt.misc.global.setting.tooltip.show.aura.caster.names",
                                settingKey = "general.tooltipShowAuraCasterNames",
                            },
                        },
                        {
                            text = "Independent GCD bar: supported clients can position it separately, with size, opacity, time and spell display, idle-background and combat-only options.",
                            link = {
                                pageKey = "opt_castbar",
                                query = "place gcd bar separately",
                                label = "Place GCD bar separately",
                                sectionId = "castbar_gcd",
                                controlId = "menu2.opt.castbar.global.gcd.gcd.bar.detached",
                                settingKey = "general.gcdBarDetached",
                            },
                        },
                        {
                            text = "Final channel tick: add a final-tick accent to supported spell-specific Player castbar markers.",
                            link = {
                                pageKey = "opt_castbar",
                                query = "highlight last channel tick",
                                label = "Highlight last channel tick",
                                sectionId = "castbar_behavior",
                                controlId = "menu2.opt.castbar.global.behavior.castbar.accent.last.tick",
                                settingKey = "general.castbarAccentLastTick",
                            },
                        },
                        {
                            text = "Classic channel data: Era and Forever use rank-specific channel information, with up to fifteen ticks where supported. TBC and Mists retain their existing tables.",
                            link = {
                                pageKey = "opt_castbar",
                                query = "channel tick markers",
                                label = "Spell-specific channel tick markers",
                                sectionId = "castbar_behavior",
                                controlId = "menu2.opt.castbar.global.behavior.castbar.show.channel.ticks",
                                settingKey = "general.castbarShowChannelTicks",
                            },
                        },
                        {
                            text = "Arena castbar configuration: icon, spell-name and cast-time options apply to supported opponent frames, including all five TBC and Mists slots.",
                            link = {
                                pageKey = "uf_arena",
                                query = "arena castbar icon",
                                label = "Arena castbar icon",
                                sectionId = "castbar",
                                controlId = "menu2.uf_arena.unit.castbar.feature.msuf2_castbar_icon",
                                settingKey = "general.showArenaCastIcon",
                            },
                        },
                        {
                            text = "Arena PvP trinket: the enemy PvP trinket has its own Arena page section with show, size, side, offset and layer settings. It appears in the Arena page preview and MSUF Edit Mode, and the arena frame's Edit Mode popup adjusts it directly.",
                            link = {
                                pageKey = "uf_arena",
                                query = "show pvp trinket",
                                label = "Show PvP trinket",
                                sectionId = "pvp_trinket",
                                controlId = "menu2.uf_arena.unit.trinket.show",
                                settingKey = "arena.showTrinket",
                            },
                        },
                        {
                            text = "Focus Kick: the unified line includes the option to retain the Focus castbar beside the compact interrupt icon.",
                            link = {
                                pageKey = "opt_castbar",
                                query = "show castbar with focus kick icon",
                                label = "Show castbar with Focus Kick icon",
                                sectionId = "castbar_focus_kick",
                                controlId = "menu2.opt.castbar.global.focus.kick.focus.kick.show.castbar",
                                settingKey = "general.focusKickShowCastbar",
                            },
                        },
                        {
                            text = "Interrupt readiness: tracks only interrupts the character has learned, including Demonology's Axe Toss through Command Demon. Spells of another specialization and missing pets no longer count as a ready interrupt.",
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
                            text = "Corner Show when missing: corner indicators set to Show when missing light up while the aura is missing on Classic clients. Retail and WoW Forever explain why the choice is unavailable there and keep the saved setting.",
                            link = {
                                pageKey = "gf_indicators",
                                query = "corner indicator show when missing",
                                label = "When",
                                sectionId = "ci",
                                controlId = "menu2.gf_indicators.group.corner.editor.mode",
                                settingKey = "gf_party.ciCustomTL.mode",
                                prepareKind = "groupCornerSlot",
                                prepareValue = "party_TL",
                            },
                        },
                    },
                },
                {
                    title = "WoW Forever Swing Timers and buff coverage",
                    bullets = {
                        {
                            text = "Main Hand, Off Hand and Ranged timers: separate appearance and text controls, fill direction, elapsed or remaining time, custom labels and saved placement.",
                            link = {
                                pageKey = "swingtimers",
                                query = "swing timer module",
                                label = "Enable Swing Timer module",
                                sectionId = "swing_module",
                                controlId = "menu2.swingtimers.swing.enabled",
                                settingKey = "swingTimers.enabled",
                            },
                        },
                        {
                            text = "Swing helpers: an off-hand lane inside the main-hand bar, queued-attack cues and reach warnings.",
                            link = {
                                pageKey = "swingtimers",
                                query = "off-hand lane main-hand bar",
                                label = "Show the off-hand timer as a lane in the main-hand bar",
                                sectionId = "swing_main",
                                controlId = "menu2.swingtimers.swing.main.offhand.lane",
                                settingKey = "swingTimers.main.offhandLane",
                            },
                        },
                        {
                            text = "Swing preview and transfer: embedded menu preview, drag placement and category-based Copy To. Disabling the module restores Blizzard's previous swing-bar visibility.",
                            link = {
                                pageKey = "swingtimers",
                                query = "swing timer module",
                                label = "Enable Swing Timer module",
                                sectionId = "swing_module",
                                controlId = "menu2.swingtimers.swing.enabled",
                                settingKey = "swingTimers.enabled",
                            },
                        },
                        {
                            text = "Group buff coverage: check selected Mark of the Wild, Thorns, Arcane Intellect, Paladin blessings, Fortitude and Divine Spirit buffs against available group providers.",
                            link = {
                                pageKey = "gf_layout",
                                query = "buff coverage icons",
                                label = "Show buff coverage icons",
                                sectionId = "buff_coverage",
                                controlId = "menu2.gf_layout.group.field.buffcoverageenabled",
                                settingKey = "gf_party.buffCoverageEnabled",
                                prepareKind = "groupScope",
                                prepareValue = "party",
                            },
                        },
                        {
                            text = "Buff reminder rules: optional glow, tank-only Thorns and mana-user rules for Intellect and Spirit.",
                            link = {
                                pageKey = "gf_layout",
                                query = "buff coverage glow missing icons",
                                label = "Glow missing icons",
                                sectionId = "buff_coverage",
                                controlId = "menu2.gf_layout.group.field.buffcoverageglow",
                                settingKey = "gf_party.buffCoverageGlow",
                                prepareKind = "groupScope",
                                prepareValue = "party",
                            },
                        },
                        {
                            text = "Restricted-state visibility: coverage icons hide in restricted states by default. The optional combat-display mode retains known coverage where fresh aura data is unavailable.",
                            link = {
                                pageKey = "gf_layout",
                                query = "buff coverage keep showing during combat",
                                label = "Keep showing during combat",
                                sectionId = "buff_coverage",
                                controlId = "menu2.gf_layout.group.field.buffcoveragecombat",
                                settingKey = "gf_party.buffCoverageCombat",
                                prepareKind = "groupScope",
                                prepareValue = "party",
                            },
                        },
                    },
                },
                {
                    title = "Profiles and transfer",
                    bullets = {
                        {
                            text = "Profile variants: override selected settings and layouts for specializations, locations or a hotkey while retaining the base profile. Variants have recording controls, conditions, priority, field selection and import/export.",
                            linkless = true,
                        },
                        {
                            text = "Selected Unit Frame export and import: transfer supported Player, Target, Target of Target, Pet, Focus, Focus Target, Boss and Arena selections. Each selection carries its own settings, auras and castbar.",
                            linkless = true,
                        },
                        {
                            text = "Scoped imports: apply selected frames to the current or a new profile while preserving other frames and shared settings. Inherited appearance follows the receiving profile.",
                            linkless = true,
                        },
                        {
                            text = "Selection validation: empty selections, unsupported frames and settings outside the selected scope are rejected. Full-profile and category transfers retain their formats.",
                            linkless = true,
                        },
                        {
                            text = "Client-aware defaults: fresh installs, new profiles and resets use the factory layout, with revised power bars, separate Alternative Mana placement, compact raid geometry and updated text/aura positions.",
                            linkless = true,
                        },
                        {
                            text = "Factory visual settings: updated Slug font rendering, Focus/Target-of-Target placement and Pet transparency. Factory castbars fill left to right, the cleanse border uses Dispellable by group, and Target buffs/debuffs share one line. Existing profiles retain their chosen settings.",
                            linkless = true,
                        },
                        {
                            text = "Forever factory layout: a dedicated client layout with revised Unit Frame defaults and 80% health-fill opacity.",
                            linkless = true,
                        },
                        {
                            text = "Section Copy To: includes supported portrait connector, rim, level badge, atlas, text mouseover, clickable portrait, chunked fill and prediction-opacity settings. Unavailable destinations are marked or filtered.",
                            linkless = true,
                        },
                        {
                            text = "Supported profile formats: the unified line retains MSUF 6.x profiles and their supported Wago envelope. Pre-6.0 conversion and its import controls were retired during the alpha series.",
                            linkless = true,
                        },
                    },
                },
                {
                    title = "Menu, search and controller controls",
                    bullets = {
                        {
                            text = "Section headers provide their feature switch, summary and three-dot actions for reset and Copy To.",
                            linkless = true,
                        },
                        {
                            text = "Disabled frame scopes dim their settings while keeping frame selection and previews usable.",
                            linkless = true,
                        },
                        {
                            text = "Clearer navigation, section labels, help text and explanations for unavailable controls; menu clicks and hover use consistent accent styling.",
                            linkless = true,
                        },
                        {
                            text = "Search follows client capabilities and preserves field edits.",
                            linkless = true,
                        },
                        {
                            text = "Conversational search: natural task phrasing in English and German, such as \"make my target health numbers bigger\", routes to the matching page or setting.",
                            linkless = true,
                        },
                        {
                            text = "Search greeting: the Dashboard search card greets you by name for the time of day: morning, midday, afternoon, evening or night.",
                            linkless = true,
                        },
                        {
                            text = "Updated menu and Edit Mode labels, prompts, tooltips, status text, history, chat messages and placeholders across all twelve supported locales.",
                            link = {
                                pageKey = "opt_misc",
                                query = "menu language",
                                label = "Menu language",
                                sectionId = "misc_language",
                                controlId = "menu2.opt.misc.global.language.selection",
                                settingKey = "general.menuLocale",
                            },
                        },
                        {
                            text = "Typed HEX colors commit on Enter through the shared color-picker apply path.",
                            linkless = true,
                        },
                        {
                            text = "Blizzard Micro Menu and Bags controls expose horizontal and vertical orientation where the client provides it.",
                            link = {
                                pageKey = "opt_misc",
                                query = "blizzard frames msuf edit mode",
                                label = "Show Blizzard frames in MSUF Edit Mode",
                                sectionId = "misc_external_edit_mode",
                                controlId = "menu2.opt.misc.global.setting.blizzard.edit.mode.integration",
                                settingKey = "general.blizzardEditModeIntegration",
                            },
                        },
                        {
                            text = "Blizzard Damage Meter appearance settings changed in MSUF Edit Mode are saved and apply after a UI reload; width and height still apply at once.",
                            link = {
                                pageKey = "opt_misc",
                                query = "blizzard frames msuf edit mode",
                                label = "Show Blizzard frames in MSUF Edit Mode",
                                sectionId = "misc_external_edit_mode",
                                controlId = "menu2.opt.misc.global.setting.blizzard.edit.mode.integration",
                                settingKey = "general.blizzardEditModeIntegration",
                            },
                        },
                        {
                            text = "Compatible MSUF Suite windows integrate with MSUF profiles, fonts, anchors, menu controls and controller navigation. External Edit Mode elements can open their settings popup centered.",
                            linkless = true,
                        },
                        {
                            text = "Forever controller controls cover D-pad focus, confirm/cancel, dropdowns, anchors, search and switching MSUF windows.",
                            linkless = true,
                        },
                        {
                            text = "The on-screen keyboard supports text and exact numeric entry. Controller actions include slider adjustment, preview and Edit Mode nudges, and supported Undo/Redo.",
                            linkless = true,
                        },
                        {
                            text = "Localized button hints, focus highlights and haptic feedback accompany supported controller actions. Navigation releases input in combat and while Blizzard panels own it.",
                            linkless = true,
                        },
                    },
                },
                {
                    title = "Client Support & Packaging",
                    bullets = {
                        {
                            text = "Supported client paths: Midnight 12.0.7/12.1.0/12.1.5, Classic Era 1.15.9, TBC 2.5.6, Mists 5.5.4 and WoW Forever 1.60.1 through the Mainline manifest and Interface 16001.",
                            linkless = true,
                        },
                        {
                            text = "The package contains the core addon and load-on-demand Options addon.",
                            linkless = true,
                        },
                        {
                            text = "The in-game Assistant is retired and no longer shipped. Its saved chat data is removed once and excluded from profile transfers. For a manual update, remove any old MidnightSimpleUnitFrames_Assistant folder from Interface/AddOns.",
                            linkless = true,
                        },
                        {
                            text = "WoW Forever is detected through its client marker, including the dedicated project identifier present in build 70170. Unknown clients retain a guarded fallback.",
                            linkless = true,
                        },
                        {
                            text = "Every client runs version 6.50: Midnight, WoW Forever, Classic Era, TBC and Mists. /msuf clientinfo reports the detected client and addon version for bug reports.",
                            linkless = true,
                        },
                        {
                            text = "Menus and search hide unavailable controls, including unsupported Arena Frames, Empowered Casts, pet information and Cooldown Manager anchors. Forever group choices are limited to Party and Raid.",
                            linkless = true,
                        },
                        {
                            text = "Retail 12.1.5 uses the supported native aura, scheduling and pixel-rounding paths; older Mainline versions retain their compatible fallbacks.",
                            linkless = true,
                        },
                        {
                            text = "Validated against Blizzard's 12.1.5 interface source (build 70077) and WoW Forever build 70291, including the reworked Forever combo point frame.",
                            linkless = true,
                        },
                        {
                            text = "Mainline core and Options appear in the MSUF category in the AddOn list; version labels follow the current game type.",
                            linkless = true,
                        },
                        {
                            text = "Added Forever game-version targeting and Wago publishing support to the release pipeline, with expanded startup, menu-index, locale and package validation.",
                            linkless = true,
                        },
                        {
                            text = "The Forever menu title follows the detected client. Classic Glass, initially Forever-specific, is available alongside Midnight and Midnight Dark across supported clients.",
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
                    title = "Bug Fixes - Group frames and secure layouts",
                    bullets = {
                        "Fixed group layout changes at combat entry, preserved layout capacity and role ordering for members joining during combat, and returned previewed groups to their live headers.",
                        "Fixed small-raid Party layouts, class-priority identity reads, filters, extra-block names and housing visibility, including consistent dead/offline backgrounds.",
                        "Newly created group and Pet buttons retain click handling and pixel alignment in combat.",
                        "Member target frames refresh when compound unit tokens receive no native unit event.",
                        "Healer mana rows and allied boss frames repaint when a unit token is reassigned; healer mana text receives its font before its first update.",
                        "Raid Manager expanded state survives settings reapplication. Hidden mode leaves its toggles click-through; Forever's gamepad-opened manager stays visible with its panel and closes with it.",
                        "Classic and Forever members without an assigned role retain their power bar when enabled for any role, while explicit role filters still apply.",
                        "Fixed roster-slot aura rebinding, preserved subgroup geometry, configured columns, role sorting and world-entry refreshes in the unified client line.",
                        "Fixed disappearing Forever Party, Raid and Priority frames during secure group setup. Updated initialization follows Blizzard's repaired load order.",
                        "Saved negative-heal-absorb overrides remain consistent across group layouts and logins. Group sorting, previews and Edit Mode use the same layout settings.",
                        "Party and Raid bar and background textures chosen on the Bars page apply after Copy To. Turning Custom settings off or resetting the scope returns the frames to the shared texture.",
                    },
                },
                {
                    title = "Bug Fixes - Auras and indicators",
                    bullets = {
                        "Removed the baked-in Blizzard icon border (#159): runtime icons, reminders and menu/Edit Mode previews share a minimum crop while preserving stronger configured zoom.",
                        "Classic aura lanes honor all nine anchors, the menu layer range, Player-first sorting and the correct Pet overrides.",
                        "Combat-only filters refresh at the combat transition; AUTO dispel symbols follow the frame's strata.",
                        "Custom auras compile on supported Classic Arena Frames. Classic Edit Mode retains click forwarding and avoids rewiring sealed native aura buttons.",
                        "Fixed aura refreshes after profile switches, resets, imports, specialization changes and roster-slot changes.",
                        "Fixed Friendly, Enemy and Both conditions on Classic cleanse borders, permanent-aura rules, faction updates and sorting agreement between lanes and custom containers.",
                        "Era dispel scans retain the HARMFUL|RAID filter. Untouched sparse factory aura layouts from Alpha 18 through Beta 3 are repaired while customized aura owners are preserved.",
                        "Filtered-out auras can reappear. Failed or interrupted full refreshes recover instead of leaving later updates stuck or half-merged.",
                        "Shaped dispel borders use the actual debuff color. Missing Classic atlases use bundled symbol artwork, and disabled symbols clear immediately.",
                        "Classic menus hide unsupported Pandemic-only options and show correct client-specific search entries.",
                        "Aura icons allow clicks through to their unit frame.",
                        "Rounded highlight borders retain their thickness and state; group highlight detection remains available when aura icons are disabled.",
                        "Classic Custom Priority containers sort by the dragged priority order, and turning off a group lane's cooldown text no longer removes its cooldown swipe.",
                        "Classic blacklist presets hide every rank of their spells, and the Purge border lights from real aura data.",
                        "Custom containers set to Only mine no longer hide other casters' copies from the regular buff and debuff lanes.",
                        "Custom Priority containers apply their filters and Max icons, and binding an item to a tracked Buff Reminder spell applies immediately.",
                        "The aura Name Overlay follows target, focus and roster changes; while auras are restricted it updates once the restriction ends.",
                        "Entering combat with the Boss or Arena page open removes the preview aura icons and restores the real boss and arena auras.",
                    },
                },
                {
                    title = "Bug Fixes - Class Resources, power and status",
                    bullets = {
                        "Class Resource settings apply after saved profiles load and stay synchronized with variants and page resets.",
                        "Fixed explicit Mana selection and Alternative Mana overlap; classes without a mana pool no longer inherit an unusable Alternative Mana bar.",
                        "Class resources refresh after death and resurrection. Mists Monk Chi updates after settings changes.",
                        "Resource maxima trigger required layout changes; Stagger colors, Ironfur and aura-count visibility repaint correctly.",
                        "Mists Burning Embers use the unmodified maximum; Affliction shards use the supported spell gate. Midnight Affliction/Demonology prediction receives cast events.",
                        "Mists Death Knight runes use their rune-type colors unless an explicit override is selected. Combo Points and aura-based resources refresh correctly.",
                        "Eclipse respects its text mode and removes auras that end early. Player Power regains its color after Eclipse.",
                        "Alternative Mana returns after Edit Mode, and disabling the secondary Player HP module hides its bar.",
                        "Resource marks use the displayed resource's range, remain above pips and handle restricted power percentages through the supported native path.",
                        "Hidden Class Resources and detached Power keep their Edit Mode movers; attached bars retain their maintained anchor while the visible resource is inactive.",
                        "AFK timers resume after combat, and death state updates on direct health ticks.",
                        "Unit tooltips display available AFK/DND flags. Inline target-of-target text follows the visible edge of the name glyphs.",
                        "Native managed class-resource bars retain Blizzard lifecycle handling while their visuals are concealed. Totem takeover restores only the frame-position flag owned by MSUF.",
                        "Mists Balance Eclipse colors apply. Mists specialization profiles, per-spec crosshair spells, the Monk totem preview and specialization tooltips read the client's specialization.",
                        "Class Resources > Reset selected also resets Additional Resource settings whose sections were never opened.",
                        "The AFK Timer works without AFK Text. Power text with maximum values and frame transparency stay error-free when the client restricts those values.",
                    },
                },
                {
                    title = "Bug Fixes - Castbars and Arena Frames",
                    bullets = {
                        "Arena bars honor Show icon, Spell name and Cast time, with corrected time-text positioning in runtime and previews.",
                        "Castbar movers follow bars after they move, and font updates preserve cast-target class colors.",
                        "Interrupt feedback follows the displayed cast, including late interruption events and successive rapid interrupts.",
                        "The Interrupt Ready indicator considers all available interrupts with client-appropriate spell lists. Classic has a cooldown fallback, and the ready border retains its color after rebuilding.",
                        "Castbar fill direction and countdown mode work together.",
                        "TBC and Mists width matching and portrait previews include all five Arena opponents. Their castbars retain a native event frame when the shared event bus declines a subscription, and all three text regions clear their font cache after a font change.",
                        "Arena power text refreshes when a slot binds to a different opponent, including Solo Shuffle rounds.",
                        "Arena and Boss bars share consistent frame lifecycle handling, restore native text when needed and refresh outlines and cooldown state.",
                        "Native managed castbars retain Blizzard lifecycle handling while MSUF conceals their visuals.",
                        "Restricted cast, duration, swing, aura, health and power values follow supported native formatting and rendering paths.",
                        "Target and focus changes clear the previous cast's not-interruptible tint, and the castbar glow no longer repaints non-interruptible casts.",
                        "Interrupted player channels show their Interrupted feedback; the Focus interrupt tracker shows its kick confirmation and repaints with the Unavailable cast fill style.",
                        "Talented Disintegrate shows all channel ticks. Castbar glow stays inside rounded and slanted castbars, and castbars and the totem preview handle restricted frame strata.",
                        "Handing the player castbar back to Blizzard no longer leaves Blizzard's castbar tainted.",
                    },
                },
                {
                    title = "Bug Fixes - Shapes, portraits and prediction",
                    bullets = {
                        "Rounded borders and masks retain the selected shape; imported Slanted styles use the current Rounded fallback when Slanted is disabled.",
                        "Styled shaped borders and previews retain matching style, color and thickness.",
                        "Fixed portrait rim/mask alignment, direction, zoom, foreground opacity and layering after native refreshes. Atlas artwork retains its full image and flip direction.",
                        "Status badges and level numbers remain within native overlay limits for imported high layer values. Disabling Level also removes its fallback badge ring.",
                        "Missing-health backgrounds no longer show a fully reversed bar at full health; rounded health backgrounds retain their intended opacity in instanced combat.",
                        "Global font and texture changes preserve frame opacity and update affected text. Protected prediction values retain their over-absorb glow.",
                        "Unit frames recover after instance or housing visibility changes, resume event routes and refresh stance text. Portrait variants update without a reload.",
                        "Previews retain their layer choices, fit dropdown chips inside their panels and keep Class Resource geometry aligned with the live bar.",
                        "Fixed black Forever preview backgrounds, with scene fallbacks on other clients. Classic previews render power gradients and the Class Resource text layer; Mists Boss previews include the boss-target marker.",
                        "Font previews and the related default-setting inconsistencies are corrected.",
                        "Scoped outline colors enable their override even when the color matches the shared value. The Basics section reset also clears an older per-frame shape.",
                        "Unit previews place detached castbars correctly and translate their placeholder names.",
                    },
                },
                {
                    title = "Bug Fixes - Profiles, imports and resets",
                    bullets = {
                        "Malformed imports are staged and validated before profile creation or switching and cannot overwrite the active profile.",
                        "Oversized compressed imports are rejected before inflation. Forever factory profiles decode their compressed CBOR format correctly.",
                        "Missing imported fonts fall back safely, and imports validate fonts through the font registry. Incomplete startup font values no longer abort the menu or Edit Mode.",
                        "First login and profile resets apply the factory profile instead of code defaults, including Focus Target.",
                        "/msuf reset restores factory dimensions, positions, layout and text visibility. /msuf profile <name> saves the current settings.",
                        "Imports preserve dispel-migration stamps and supported numeric spell IDs; variants retain the resource-extra keys needed to represent removals.",
                        "A Blizzard Edit Mode snapshot is imported only when its import option is selected.",
                        "Selected-frame aura imports avoid full-profile resets and repair defaults on a private copy before applying the selected settings.",
                        "Profile deletion reassigns characters to Default or the alphabetically first remaining profile, rather than depending on table order.",
                        "Profile names remain as typed. Scale history, dropdown alignment and page refreshes remain consistent across profile changes. Copy To preserves supported font, texture, gradient and status settings.",
                        "Page resets retain Undo. Edit Mode Cancel and Undo cannot write an earlier profile's edits into a newly selected profile; history remains bounded for large profiles.",
                        "New/reset Forever profiles follow the intended disabled global-scale default while preserving explicitly enabled settings, including changes made immediately after reset.",
                        "Profile switches re-apply gameplay overlays, unit tooltip visibility and highlights, and keep aura tooltip options that MSUF did not set.",
                        "Upgrades keep per-frame dispel overlay and symbol options that were turned off. Archived pre-6.0 profiles with the same name are kept under numbered names.",
                        "Unit Frame imports no longer replace Gameplay and Color settings, and Selected Unit Frame transfers no longer carry the shared Cast Target Name Color.",
                        "/msuf default confirm resets the profile named in its warning, and a color picker left open across a profile switch no longer writes into the new profile.",
                    },
                },
                {
                    title = "Bug Fixes - Menu, search, Edit Mode and integrations",
                    bullets = {
                        "Fixed exact-search targets, Unicode normalization, field-edit preservation and refreshes of visible pages without rebuilding unaffected pages.",
                        "Fixed Class Resource card containment, left-aligned titles, spacing and preview fit on narrow windows, plus Group Anchor/class-priority wrapped text and Portrait/Healer mana spacing.",
                        "Section switch labels toggle their feature; disabled frame scopes keep navigation and previews usable.",
                        "Edit Mode Cancel discards unfinished text edits before restoration. Supported drag positions survive combat interruptions, and history commits defer safely through combat entry.",
                        "Configuration and focus-preview keyboard input stop at combat entry. ConsolePort Game Menu movement and resizing wait until combat ends.",
                        "Fixed preview lifecycle and animation behavior, including resource movement staying within Edit Mode and shared runtime/preview geometry.",
                        "Cooldown Manager anchors are offered and applied only when supported; imported unsupported anchors fall back to the normal global anchor.",
                        "Hiding Blizzard's TargetFrame also stops the hidden Forever ComboFrame from updating.",
                        "Fixed repeated Forever welcome/tour prompts and analytics initialization writing to the wrong global.",
                        "Corrected malformed Classic AddOn-list title colors that displayed a stray letter. Pet Happiness is labeled correctly on every supported client.",
                        "Unknown clients no longer offer unsupported Arena Frames; the guarded Mainline diagnostic requests /msuf clientinfo where needed.",
                        "Edit Mode Cancel All restores setter-driven options such as the minimap icon and frame scale. Selecting another element closes the aura popup so nudges move the selected element.",
                        "Search results for out-of-combat fading open the matching tab. Classic Era no longer offers a Focus anchor for the Combat Timer or group layouts, and controls without Blizzard counterparts explain why.",
                        "The Combat Timer starts on the first second of combat. The combat crosshair follows the personal nameplate and keeps its centered anchor when the nameplate height is restricted.",
                        "Unit tooltips show the faction in the client's language. WoW Forever's Gamepad UI no longer opens a hidden buff bar, and changing Damage Meter settings no longer leaves Blizzard's meter tainted.",
                        "Guided Setup hints, aura filter labels, Ready Check, Crowd Control and Russian terms are translated in every supported language; counts in the Priority and Layer overviews use whole translated sentences.",
                    },
                },
                {
                    title = "Performance",
                    bullets = {
                        "Hidden Unit Frames suspend their event routes until shown again.",
                        "Unrelated power events skip resource-text work; thresholds share a resource read, and Mists rune types refresh on their native event.",
                        "Aura sorting runs only when the selected sort mode and changed timing require it. Icon layout and shaped dispel geometry are reapplied only when their inputs change.",
                        "Aura containers are reused after retirement. Compatible group-aura previews share compiled configuration across rows.",
                        "Styled borders reuse textures and layout. Combat color updates avoid rebuilding border geometry.",
                        "Changing the Frame Outline style refreshes only the affected borders, and border event updates reuse prepared artwork.",
                        "Aura font changes reuse existing aura containers, and Classic Only mine lanes compact stale arrival entries.",
                        "Closed menu sections defer controls and decoration. Repeated header layout and owned-button skin work reuse existing state.",
                        "Cold search indexes build in short menu-task slices; exact searches retain synchronous results and prepare required lazy sections.",
                        "Options, aura workspaces and search reuse existing page state. Color previews avoid duplicate render requests and preserve staged construction.",
                        "Aura-resource and cast-expiry paths avoid per-event closures; shared aura countdown drivers stop when idle.",
                        "Arena castbar geometry is checked per style change, and the Mists trinket fallback stays off unrelated combat logs.",
                        "Completed pixel-layout setup is reused. Zoning avoids duplicate raid-header rebuilds.",
                        "Native Mainline scheduling coalesces keyed delayed work where supported; older clients keep compatible event-driven timer fallbacks.",
                        "Health gradients, backgrounds, protected text, prediction and aura-name fallback paths include the shared runtime's sample reuse, cached writers and bounded refresh work.",
                        "Version information is read once at load instead of on each display or analytics pass.",
                        "Shared client, defaults, aura, castbar and group owners reduce duplicated implementations while retaining client-specific behavior.",
                        "Opening Options from the Game Menu shares the keybind's deferred first-load boundary, reducing first-open script-time pressure.",
                        "Shared target-based Combo Point handling covers Classic and Forever; client defaults, Class Resources and previews use consolidated owners.",
                        "Preview animation, factory-profile decoding and search avoid repeated work.",
                    },
                },
            },
        },
        {
            version = "6.16-beta1",
            date = "2026-09-06",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Unit Frames can now appear only while their unit is injured. Enable Show only below 100% health under Unit > Load Conditions to keep a frame transparent at full health while preserving the other configured hide rules.",
                            link = {
                                pageKey = "uf_player",
                                query = "show only below 100 health",
                                label = "Show only below 100% health",
                                sectionId = "load_conditions",
                                controlId = "menu2.uf_player.unit.load_condition.loadcondshowwheninjured",
                                settingKey = "player.loadCondShowWhenInjured",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Rebuilt the Auras3 backend into explicit native runtime, Menu, Edit Mode, and Spell Indicator modules while preserving its public behavior and Blizzard-owned Aura tracking.",
                        "Custom Aura spell names now use prebuilt locale-specific alias catalogs instead of a live Aura-name resolver, including current localized and hotfixed spell groups.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Target Range Fade now forwards protected in-range results through Blizzard's native boolean-alpha path and retains its spell-range fallback when the native check is unavailable.",
                        "Health gradients, dynamic backgrounds, and protected health and power text reuse already-read values and specialized writers to reduce duplicate work on frequent unit events.",
                        "Injured-only visibility uses a secret-safe native health curve and stable visual parents so health bars, predictions, borders, textures, portraits, cast indicators, and Class Resources hide together without changing the clickable secure frame.",
                        "Scheduler callback errors now retain the original callback stack while continuing to isolate failures and drain queued work.",
                    },
                },
            },
        },
        {
            version = "6.151",
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
                    },
                },
                {
                    title = "Fixes",
                    bullets = {
                        "Restored rounded highlight startup and layering, including support for border thickness up to 30.",
                        "Dispel and Purge borders now apply their configured thickness on all frame shapes and refresh immediately after Menu changes.",
                        "Group Frame highlight detection keeps working when Aura icons are disabled, and Any dispel type also works on enemy units.",
                    },
                },
            },
        },
        {
            version = "6.15",
            date = "2026-09-05",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Absorbs and heal prediction can stay visible when the health bar is faded into the background. Enable Keep Absorbs + Prediction Visible per Unit Frame or for Party and Raid Frames to keep these overlays at full opacity independently from the health fill.",
                            link = {
                                pageKey = "uf_player",
                                query = "keep absorbs prediction visible",
                                label = "Keep Absorbs + Prediction Visible",
                                sectionId = "transparency",
                                controlId = "menu2.uf_player.unit.transparency.alpha_exclude_prediction_bars",
                                settingKey = "player.alphaExcludePredictionBars",
                            },
                        },
                        {
                            text = "Raid and Mythic Raid role sorting can span the entire raid. Enable Sort roles across entire raid under Group Layout > Sorting to order tanks, healers, and damage dealers across the whole raid instead of within each raid group.",
                            link = {
                                pageKey = "gf_layout",
                                query = "sort roles across entire raid",
                                label = "Sort roles across entire raid",
                                sectionId = "sorting",
                                controlId = "menu2.gf_layout.group.field.sortrolesacrossraid",
                                settingKey = "gf_raid.sortRolesAcrossRaid",
                                prepareKind = "groupScope",
                                prepareValue = "raid",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "The Boss Preview displays incoming heals, absorbs, heal absorbs, and absorb text so prediction settings can be reviewed without a live boss.",
                        "The Assistant understands plain-language requests about a specific Unit Frame and resolves questions, hide commands, movement directions, and opacity controls against the named frame and control.",
                        "Retired pre-6.0 profile conversion and import controls. Existing MSUF 6.x profiles and 6.x Wago imports remain supported; older or unversioned stored profiles are archived instead of entering the active profile list.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Health gradients, texture changes, prediction refreshes, Group Range Fade, and the Boss Preview preserve the configured health and prediction opacity.",
                        "Detached Player Power bars attached or width-synced to Class Resources retain their position and width when shapeshifting hides the Class Resource bar.",
                        "Text on detached bar controls Power-text placement independently from Show power text.",
                        "Class Resource previews keep responding to movement and position controls after Menu lifecycle cancellation.",
                        "Interrupted Aura refreshes recover instead of leaving Aura displays empty or later refreshes stuck as pending.",
                        "Cleanse and Purge borders use the same Frame Outline layer as their preview, and Unit Frame dispel borders follow Blizzard's assist rules.",
                        "Group Frame dead and offline backgrounds follow the unit's current state without delayed health-background updates.",
                        "Preserved raid groups use one roster snapshot for sorting and layout, preventing the filled and displayed grids from disagreeing when more subgroups are present than the configured column limit.",
                        "Assistant requests for Out of range opacity, Texture Layer opacity, and Portrait opacity update their own controls.",
                        "Reduced repeated work and temporary allocations in health gradients, dynamic backgrounds, protected text, Aura fallback scans, and Range Fade timers while preserving their update behavior.",
                    },
                },
            },
        },
        {
            version = "6.15-beta7",
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
                    title = "Fixes & Performance",
                    bullets = {
                        "Health gradients now reuse bounded native scalar curves for their RGB channels, avoid per-update ColorMixin allocation, and keep constant channels out of the native evaluation path.",
                        "Group health updates no longer repeat an already completed dynamic-background refresh or enter an empty color handoff after the background has been painted.",
                        "Dynamic health backgrounds cache stable alpha inputs and known cache keys, use the native secret-value predicate when available, and forward protected colors directly to their supported rendering sink.",
                        "Protected current, maximum, and percentage text modes now use compiled single-value writers instead of the general multi-value formatter.",
                        "Unresolved Aura fallback scans no longer resynchronize an unchanged active-work state, while later Aura discovery, owner reactivation, and unregister cleanup remain intact.",
                        "Group death-background updates skip cache probes that cannot be reused outside an active frame dispatch while retaining fresh native death and resurrection checks.",
                        "Range Fade keeps an earlier timer when its logical deadline moves later, reducing timer replacement churn without moving range checks or alpha changes forward.",
                    },
                },
            },
        },
        {
            version = "6.15-beta6",
            date = "2026-09-04",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Absorbs and heal prediction can now stay visible when the health bar is faded into the background. Enable Keep Absorbs + Prediction Visible per Unit Frame or for Party and Raid Frames to keep these overlays at full opacity independently from the health fill.",
                            link = {
                                pageKey = "uf_player",
                                query = "keep absorbs prediction visible",
                                label = "Keep Absorbs + Prediction Visible",
                                sectionId = "transparency",
                                controlId = "menu2.uf_player.unit.transparency.alpha_exclude_prediction_bars",
                                settingKey = "player.alphaExcludePredictionBars",
                            },
                        },
                        {
                            text = "Raid and Mythic Raid role sorting can now span the entire raid. Enable Sort roles across entire raid under Group Layout > Sorting to order tanks, healers, and damage dealers across the whole raid instead of within each raid group.",
                            link = {
                                pageKey = "gf_layout",
                                query = "sort roles across entire raid",
                                label = "Sort roles across entire raid",
                                sectionId = "sorting",
                                controlId = "menu2.gf_layout.group.field.sortrolesacrossraid",
                                settingKey = "gf_raid.sortRolesAcrossRaid",
                                prepareKind = "groupScope",
                                prepareValue = "raid",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added Keep Absorbs + Prediction Visible to Unit Frames and Party/Raid Frames, including profile copy, defaults, previews, search, and Assistant support.",
                        "Added Sort roles across entire raid for Raid and Mythic Raid Frames, including defaults, profile copy, locales, search, and Assistant support. Role sorting can now span the full raid with Preserve raid groups or Group + Role, while Party remains unchanged.",
                        "The Boss Preview now displays incoming heals, absorbs, heal absorbs, and absorb text so prediction settings can be reviewed without a live boss.",
                        "The Assistant now understands plain-language requests about a specific Unit Frame and resolves questions, hide commands, movement directions, and opacity controls against the named frame and control.",
                        "Retired pre-6.0 profile conversion and import controls. Existing MSUF 6.x profiles and 6.x Wago imports remain supported; older or unversioned stored profiles are archived instead of entering the active profile list.",
                        "See New Features can now open the exact Player Aura workspace used by the current Aura highlight.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Health gradients, texture changes, prediction refreshes, Group Range Fade, and the Boss Preview now preserve the configured health and prediction opacity instead of resetting prediction fills to full or faded health opacity.",
                        "Assistant requests for Out of range opacity, Texture Layer opacity, and Portrait opacity now update their own controls instead of changing health-bar opacity.",
                        "Detached Player Power bars attached or width-synced to Class Resources retain their controller-managed anchor while the Class Resource bar is hidden, preventing position and width jumps after shapeshifting.",
                        "Text on detached bar now controls only Power-text placement. It no longer appears disabled merely because Power text is hidden and no longer enables Show power text by itself.",
                        "Aura owners that cannot be visible for the current unit stop parsing UNIT_AURA; their native registration and unresolved-name work resume only when the owner becomes eligible again.",
                        "Cleanse and Purge borders now use the same Frame Outline layer as their preview, Unit Frame dispel borders follow Blizzard's assist rules, and Purge, cast-by-me, and Retail exact-ID Group Aura ownership retain their intended behavior.",
                        "Group Frame dead and offline backgrounds now follow secret health updates without lagging behind the unit's real state.",
                        "Preserved raid groups build and sort one authoritative roster snapshot per secure-header setup. Their rendered block count now follows the same roster, preventing the filled and displayed grids from disagreeing when more subgroups are present than the configured column limit.",
                        "The Group Layout Sorting card now aligns its Sort Mode dropdown and dependent toggles consistently.",
                        "Interrupted full Aura refreshes arm their recovery before synchronous work and can no longer leave later refreshes stuck as pending after a Lua execution-budget abort.",
                        "Aura recovery remains inside the native factory runtime and preserves the Retail 12.1 hook contracts across refreshes, preventing Aura displays from remaining empty after an interrupted update.",
                        "Class Resource previews can schedule refreshes again after Menu lifecycle cancellation, so movement and position controls continue updating after settings changes.",
                    },
                },
            },
        },
        {
            version = "6.15-beta5",
            date = "2026-09-04",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Auras are visible and recover reliably again in the Retail 12.1 Beta. Open Player Auras at Buffs > Layout to review the visible Aura lane.",
                            link = {
                                pageKey = "uf_player",
                                query = "player buff aura layout visible",
                                label = "Player Auras",
                                sectionId = "auras",
                                controlId = "menu2.uf_player.auras.unit-workspace.container-selector",
                                settingKey = "auras3.player.buff.visible",
                                prepareKind = "unitAuraWorkspace",
                                prepareValue = "buff_layout",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "The CurseForge Beta is explicitly published for Retail 12.1.0.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Aura recovery remains inside its factory-owned runtime and retains the native 12.1 hook contracts across refreshes, preventing Aura displays from staying empty after an interrupted update.",
                        "Class Resource previews can schedule refreshes again after Menu lifecycle cancellation, so their movement and position controls continue to update after settings changes.",
                        "Extended the Aura and Menu interaction smokes for both fixes.",
                    },
                },
            },
        },
        {
            version = "6.15-beta4",
            date = "2026-09-04",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Retail Aura displays recover instead of remaining disabled when a full refresh exceeds the Lua execution budget.",
                            linkless = true,
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Retired the complete pre-6.0 profile conversion path and its legacy import controls. Every MSUF 6.x schema-600 profile and the 6.x Wago envelope remain supported; older or unversioned stored profiles are archived instead of being normalized into the active profile list.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Full Aura refreshes batch identity-event topology once and arm their next-frame recovery before synchronous work, so a script ran too long abort cannot leave every later Aura refresh permanently latched as pending.",
                    },
                },
            },
        },
        {
            version = "6.15-beta3",
            date = "2026-09-03",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "The Assistant now understands requests that name one unit frame and then describe the result. \"Show the PvP flag on my target frame\", \"put the portrait on the left of my player frame\" or \"the name on my player frame is too small\" resolve against that frame's own controls instead of the frame's master toggle or a single matching word.",
                            linkless = true,
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Questions about one control of one unit frame are answered with that control - its page, what it does and its current value - instead of a page-level overview. \"Don't show raid markers on my player frame\" is read as a hide command, and \"upwards\"/\"downwards\" now reach the movement lanes.",
                        "Out of range opacity, Texture Layer opacity and Portrait opacity are no longer written to the health bar's opacity.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Aura owners that cannot be visible for the current unit stop parsing every UNIT_AURA update: the native registration is dropped while the owner is ineligible and Blizzard's own reparse restores it, and the spell-name resolver only listens per unit while an active owner still has names to resolve.",
                        "Cleanse and Purge borders draw in the Frame Outline layer band at the Borders highlight detail, so the live border lands exactly where the Cleanse test border draws.",
                        "Unit Frame dispel borders follow Blizzard's own assist check and only appear on units you can dispel; the Purge marker and \"cast by me\" sensors keep their previous behaviour, and exact-ID group aura lanes drop a native owner per unit on 12.1.",
                        "The dead and offline health background now follows secret health values on Group Frames instead of lagging behind the real state.",
                        "Preserved raid groups take one authoritative roster snapshot per header setup instead of one per block, and the number of laid-out blocks follows the roster so a raid using more subgroups than the configured column limit no longer fills a different grid than it draws.",
                    },
                },
            },
        },
        {
            version = "6.15-beta2",
            date = "2026-09-02",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Raid and Mythic Raid role sorting can now span the entire raid. Enable Sort roles across entire raid under Frames > Party/Raid Frames > Layout > Sorting to order tanks, healers, and damage dealers across the whole raid instead of within each raid group, including with Preserve raid groups.",
                            linkless = true,
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added Sort roles across entire raid to Raid and Mythic Raid sorting with defaults, profile copy, locales, search, and Assistant support. By Role with Preserve raid groups and Group + Role follow the raid-wide order; Party is unaffected.",
                        "The Boss Preview now renders incoming heal, absorb, and heal-absorb bars plus the absorb text so prediction settings can be judged without a live boss.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Raid role sorting stays fully out of combat: the raid-wide order is rebuilt only when roles or the roster change outside combat, and Blizzard's secure header applies it natively.",
                        "Tidied the Group Layout Sorting card so the Sort Mode dropdown and its toggles sit evenly inside the card.",
                    },
                },
            },
        },
        {
            version = "6.15-beta1",
            date = "2026-09-01",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Absorbs and heal prediction can now stay visible when Unit Frame health opacity is reduced. Enable Keep Absorbs + Prediction Visible per frame to preserve these overlays independently from the health fill.",
                            link = {
                                pageKey = "uf_player",
                                query = "keep absorbs prediction visible",
                                label = "Keep Absorbs + Prediction Visible",
                                sectionId = "transparency",
                                controlId = "menu2.uf_player.unit.transparency.alpha_exclude_prediction_bars",
                                settingKey = "player.alphaExcludePredictionBars",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added the matching Keep Absorbs + Prediction Visible option for Party and Raid Frames, including profile copy, defaults, previews, search, and Assistant support.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Health gradients, texture changes, prediction refreshes, Group Range Fade, and the Boss Preview now preserve the configured health and prediction opacity instead of resetting fills to full opacity.",
                        "Detached Player Power bars attached or width-synced to Class Resources keep using the controller-maintained hidden anchor, preventing width or position jumps when shapeshifting hides the visible Class Resource bar.",
                    },
                },
            },
        },
        {
            version = "6.14",
            date = "2026-08-30",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Health-bar backgrounds can now fill the full bar or only missing health. The background can be colored independently with Custom tint, Match health bar, Class color, or Health gradient, with matching Unit Frame, Group Frame, and preview rendering.",
                            link = {
                                pageKey = "opt_colors",
                                query = "background fill missing health only",
                                label = "Background Fill",
                                sectionId = "colors_background",
                                controlId = "menu2.opt.colors.advanced.background.fill.mode",
                                settingKey = "general.barBgFillMode",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added Full bar and Missing health only background-fill modes plus independent health-background color sources, while migrating existing profiles without changing their current appearance.",
                        "The Assistant now routes Aura content and filter requests to the Unit or Group Frame that owns them, exposes the See New Features destination directly, and presents ambiguous controls with readable menu breadcrumbs instead of internal identifiers.",
                        "Unit Frame tooltips react immediately when their configured modifier key is pressed or released while the frame remains hovered.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Player Castbar interrupt feedback survives the client event order where the cast stops before the interrupted result arrives, without reviving stale casts.",
                        "State Tint controls appear and disappear immediately when their master toggles change instead of requiring the Colors page to be reopened.",
                        "Assistant queues, history, undo, pending choices, workflows, and deferred callbacks are now isolated to the profile that created them, preventing stale work from crossing a profile switch or surviving beyond its conversational context.",
                        "Immediate and deferred Assistant mutations now share the same failure-recovery path so partial work rolls back consistently.",
                        "General Aura guidance no longer competes with frame-local Aura owners, and question-shaped duration-filter requests retain their safe executable choices.",
                        "Aura-name fallback updates skip redundant unit-scan setup when no unresolved additions can benefit from it.",
                        "Opening Unit Frame Power settings no longer errors while building the detached-bar Text on detached bar control.",
                    },
                },
            },
        },
        {
            version = "6.13",
            date = "2026-08-28",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Party and Raid Frames now have a curated MSUF Highlights Buff filter. It shows 122 important offensive, support, defensive, and healer cooldowns from every group member, including short player effects such as Shadow Dance and shared states such as Shroud, while leaving common rotational buffs out. New and Factory-reset profiles use it by default; existing profiles keep their current filter and can opt in.",
                            link = {
                                pageKey = "gf_auras",
                                query = "msuf highlights buff filter",
                                label = "MSUF Highlights",
                                sectionId = "auras",
                                controlId = "menu2.gf_auras.auras.group-workspace.lane.buff.tool-selector",
                                settingKey = "gf_party.auras.buff.filterToken",
                                prepareKind = "groupAuraWorkspace",
                                prepareValue = "party_buff_filters",
                            },
                        },
                        {
                            text = "Focus Kick can now stay visible beside the Focus castbar. The new option keeps the compact interrupt icon while restoring the matching Focus castbar and its normal cast ownership.",
                            link = {
                                pageKey = "opt_castbar",
                                query = "show castbar with focus kick icon",
                                label = "Show castbar with Focus Kick icon",
                                sectionId = "castbar_focus_kick",
                                controlId = "menu2.opt.castbar.global.focus.kick.focus.kick.show.castbar",
                                settingKey = "general.focusKickShowCastbar",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "MSUF Highlights uses one shared immutable catalog and Blizzard's native exact-ID candidate filtering, with no MiniAuras dependency, polling, or recurring roster scans.",
                        "The Assistant now understands German negative determiners, colloquial removal requests, and double negatives, can switch all supported MSUF or Blizzard Unit Frames globally, and retries zero-result setting searches with registered synonyms.",
                        "Assistant Aura actions accept enchant-related inputs and route Aura filter and blacklist requests more precisely.",
                        "Exact Assistant searches recognize registry aliases and complete portrait-control labels.",
                        "Typed HEX colors in the compact color picker now commit on Enter through the same apply path as the visual picker.",
                        "Removed the experimental built-in Rogue APEX developer helper and its retired settings, menu controls, Assistant registrations, and generated metadata.",
                        "The Group Frame preview roster now includes B3NZII.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "The Player Castbar now ignores interrupted or failed terminal events when no real cast is active, preventing false \"Interrupted\" flashes during rapid instant-cast spam while preserving normal cast, channel, vehicle, and Empower feedback.",
                        "Focus interrupt and cast trackers reinitialize after the active profile and frames become available during startup.",
                        "Focus Kick castbar state follows the icon lifecycle and clears stale Focus cast ownership when the combined display is disabled.",
                        "Party Frames now honor the configured Units per column and Max columns values instead of forcing a single secure column, including future combat-safe secure-header capacity.",
                        "Live Party, Raid, and Mythic Group Frame blocks clamp their actual rendered footprint across scale and anchor combinations without rewriting SavedVariables; Edit Mode and previews keep the configured point semantics, and unavailable protected geometry fails closed.",
                        "Party-style Arena Group Frames fail open to Blizzard's secure roster while the Arena or Shuffle roster is temporarily incomplete instead of publishing an unusable partial name list.",
                        "Group Range Fade re-queries the bound member on native range events in PvP instances and refreshes its event route when the instance context changes.",
                        "Unit Range Fade reuses unchanged poll sets across movement and identity edges instead of rebuilding or duplicating scheduler work.",
                        "Player Power current-value text retains its resolved resource identity through form, vehicle, and explicit Mana handoffs.",
                        "The Player Resting indicator refreshes when its frame becomes visible after a hidden zoning transition, without adding polling or permanent update work.",
                        "Aura-name fallback scans coalesce to one pending unit scan and skip update-only or removal-only events that cannot resolve a new alias.",
                        "Heal-prediction stripes use a specialized full-health path and avoid redundant secret checks and overflow work.",
                        "Assistant ambiguity handling fails closed for conflicting colors, cross-frame wording, contradictory movement, partial compound commands, and misleading numbers in control labels instead of applying unrelated settings.",
                        "Exact setting, location, and purpose questions outrank generic concept guidance so profile-copy, Aura, status-indicator, castbar, and frame-specific requests reach their precise owner.",
                        "Safe Assistant questions preserve their original polarity and capability intent across page-context routing instead of becoming setting changes.",
                        "Full portrait control wording resolves to the intended Unit or Group Frame portrait control.",
                        "Read-only Assistant definition, location, relationship, and diagnostic requests stay off broad mutation indexes, while explicit numeric movement remains on bounded routes.",
                        "Assistant clarification choices survive repeated classification instead of being lost through a cached provisional read-only result.",
                        "The Assistant's unloaded-Menu Group copy path now mirrors the native chunked health and power fill fields while excluding anchor and migration-only state.",
                        "Exact-ID group buffs remain available on follower-dungeon Party NPCs under Blizzard's Retail group-member identity contract instead of being hidden by the old assist gate.",
                        "Durationless curated states such as Shroud recipient membership bypass generic Hide Permanent and Maximum Duration restrictions, while every other Group Aura filter keeps the saved restrictions.",
                        "Exact-ID candidate filters are installed before any broad native filter transition, avoiding an intermediate unrestricted Helpful-aura refresh.",
                    },
                },
            },
        },
        {
            version = "6.12",
            date = "2026-08-23",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Boss Range Fade can now update up to 20 times per second. The new Boss update-rate slider keeps the adaptive standard cadence at zero or continuously checks visible Boss Frames from 1 through 20 updates per second.",
                            link = {
                                pageKey = "uf_boss",
                                query = "boss range update rate",
                                label = "Updates per second",
                                sectionId = "range_fade",
                                controlId = "menu2.uf_boss.unit.range_fade.update_rate",
                                settingKey = "boss.rangeFadeUpdateRate",
                            },
                        },
                        {
                            text = "Class Resources can now keep Player Power Automatic or explicitly display Mana. The new Displayed resource dropdown preserves the existing class/spec behavior in Automatic mode, while Mana keeps the Player power surface on its Mana pool whenever the character has one.",
                            link = {
                                pageKey = "classpower",
                                query = "mana automatic displayed resource",
                                label = "Displayed resource",
                                sectionId = "classpower_detached_power",
                                controlId = "menu2.classpower.advanced.detached.power.layout.resource.source",
                                settingKey = "player.playerPowerSource",
                            },
                        },
                        {
                            text = "Class Resource text can now show Current, Maximum, or Current / Maximum. The new Resource text selector keeps Automatic as the untouched resource-specific default, while explicit modes change only the central resource value.",
                            link = {
                                pageKey = "classpower",
                                query = "class resource text mode",
                                label = "Resource text",
                                sectionId = "classpower_visuals",
                                controlId = "menu2.classpower.advanced.style.text.mode",
                                settingKey = "bars.classPowerTextMode",
                            },
                        },
                        {
                            text = "MiniAuras and MiniCC now work with MSUF Party and Raid Frames again. The event-driven frame provider refreshes only when the authoritative Group Frame registry changes, without polling the roster or frame list.",
                            linkless = true,
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added Automatic, Current, Maximum, and Current / Maximum formats for the central Class Resource value. Rune timers, Ebon Might duration, and the Ironfur stack counter retain their native formats; previews and the Assistant mirror the selected mode.",
                        "The Player Power resource selector is shared between Player Power and Class Resources, follows vehicle-resource handoffs, and is supported by previews, reset/undo history, search, and the Assistant.",
                        "Preserve Raid Groups now creates a separate secure header for each physical raid subgroup, retaining empty subgroup geometry and the selected Index, Name, or Role sorting inside each group. Scanning, Edit Mode bounds, visibility, and runtime layout cover every active subgroup header.",
                        "Retired unused legacy Class Resource text-format fields from existing profiles and generated fallback metadata.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "One-icon aura lanes now use Blizzard's one-frame AuraSlot primitive instead of allocating a ten-frame AuraGroup pool; weapon-enchant and custom-priority lanes keep their specialized group behavior.",
                        "Aura identity-event topology changes are batched across secure Group Frame header scans, resolved aura-name registrations survive unchanged layout refreshes, and redundant native full-aura refreshes were removed.",
                        "Target name and health text now resolve protected PvP class tokens through Blizzard's native class-color object without comparing or caching secret-backed RGB values.",
                        "Standard Boss Range Fade retains its adaptive 0.75/2-second checks, while a custom rate accelerates only visible Boss Frames through the existing scheduler. Custom rates are visually distinguished and show a once-per-menu-session performance warning.",
                        "Boss encounter lifecycle bursts now coalesce Unit Frame identity, AuraContainer identity, and Range Fade reconciliation into next-frame refreshes instead of repeating synchronous work for every Boss token.",
                        "Group threat-role changes refresh only the affected border and corner-indicator domains, and Group Adapter header scans retain their standalone single-header fallback.",
                        "Rounded native dispel-overlay masks are fully configured before Blizzard takes ownership and are recreated through the cold Auras3 refresh path after rounded-frame setting or media changes.",
                        "The global Castbar preview canvas is taller so below-bar text, thick outlines, and vertical icon offsets are no longer clipped.",
                        "The GCD indicator now rejects protected or otherwise non-plain spell IDs before lookup instead of allowing them into Lua table indexing.",
                        "Explicit Player Mana ownership no longer creates a duplicate Alternative Mana bar, survives vehicle and module lifecycle transitions, and keeps live bars, text, colors, Class Resource previews, and Unit Frame previews on the same displayed resource.",
                        "Class Resource, Player HP, Alternative Mana, detached-power width, and power-text controls now refresh their dependent enabled states immediately after changes, resets, undo, or Assistant application.",
                        "Gameplay configuration caching now follows the active profile table, and a failed gameplay apply can no longer leave later apply requests permanently blocked.",
                        "See New Features now reports the correct compact and full-history version ranges for 6.11.",
                    },
                },
            },
        },
        {
            version = "6.11",
            date = "2026-08-21",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Expanded Buff Tracking is back for Custom 1-3 aura containers. Every whitelisted spell keeps a fixed slot, missing buffs show as dimmed placeholders, and the same slots can securely cast spells or use bound items when clicked.",
                            link = {
                                pageKey = "uf_player",
                                query = "buff reminder fixed slots",
                                label = "Buff Reminder",
                                sectionId = "auras",
                                controlId = "menu2.uf_player.auras.unit-workspace.container-selector",
                                settingKey = "auras3.player.custom1.placed.reminderEnabled",
                                prepareKind = "unitAuraWorkspace",
                                prepareValue = "custom1_reminder",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Buff Reminder accepts Spell IDs, spell links, item links, and separate tracked-spell/item-action pairs. Player reminders can also track Main Hand and Off Hand temporary enchants, filter out spells the current character cannot apply, and pin shared consumables with Always show.",
                        "Main Hand and Off Hand enchant reminders now show their remaining time and a shaped cooldown swipe. A configurable 5-240 minute duration keeps the swipe proportional after login or reload, while the native duration binding updates without polling.",
                        "Reminder slots follow whitelist order, preserve their positions as auras appear or expire, and keep their secure click bindings fixed outside combat without polling or recurring aura reads.",
                        "Localized the complete Buff Reminder setup, whitelist actions, weapon-enchant controls, status text, and tooltips across all 12 supported locales.",
                        "The Assistant can now execute explicit multi-control requests clause by clause, including comma-separated and shared-scope commands, while continuing to fail closed for questions, planning requests, incomplete values, and ambiguous fragments.",
                        "Menu pages, accordion sections, and Back/Forward navigation now switch immediately without transition fades or a recurring discovery pulse.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Friendly Target Range Fade becoming inaccurate in instanced combat when Blizzard temporarily stops returning a fresh range result. MSUF now keeps the last authoritative result until a native range event or a real target change supplies a replacement, without adding polling, timers, or an open-world fallback path.",
                        "Castbars reuse unchanged manager topology and boss-frame geometry validation, resolve cast activity once per update, and share the player's plain interrupt-cooldown status across same-frame Target, Focus, and Boss refreshes.",
                        "Player-first role-sorted Party Frames now wait for a complete Arena roster before publishing their secure name list and refresh on Arena match-state and unit-name transitions; the additional listeners remain disabled in PvE.",
                        "The Assistant no longer mistakes player-count ranges inside Group Frame scale labels (such as 1-10 Players) for a requested value when none was supplied.",
                        "Fixed Elemental Shamans seeing Maelstrom on both resource bars. While Maelstrom owns the Class Resource row, the Player power bar now consistently displays Mana across fill, current value, maximum, percentage, text color, and event filtering; disabling that row or entering a vehicle restores the primary resource.",
                        "Applied the same resource-ownership transition to Shadow Priest Mana/Insanity and cleared both overrides when the Class Resource module shuts down.",
                        "Made third-party cooldown-viewer and external-frame anchoring safe when 12.1 returns protected geometry. MSUF validates foreign frames once, shares one stable proxy between Unit Frames, and freezes that proxy at the combat edge instead of repeatedly touching every consumer.",
                        "Boss castbars now prewarm at most one hidden bar per rendered frame when an encounter starts, avoiding one large synchronous layout burst while retaining authoritative validation when a real cast begins.",
                        "Aura-name fallback scans are coalesced to one frame and permanently retire each resolved alias until the container configuration changes, removing repeated name lookups from unrelated full aura updates.",
                        "Aura menu search now opens the Filters tool correctly for Player Defensives and Target Dots instead of falling back to Setup.",
                        "Rounded Unit Frames no longer read the protected parent of Blizzard-owned dispel-overlay textures; the safe owner is captured before the region becomes forbidden and reused when masks are applied.",
                        "Group Frame previews keep their generated character names when ordinary player-unit events refresh the dummy frames outside Edit Mode.",
                    },
                },
            },
        },
        {
            version = "6.1",
            date = "2026-08-19",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "The Raid Group indicator now has its own Size slider in Status icons, on every frame that can show it. It used to render at the frame's name font size with no way to change it; an untouched profile keeps that size, so nothing moves until you drag the slider.",
                            link = {
                                pageKey = "uf_player",
                                query = "raid group size",
                                label = "Size",
                                sectionId = "status_icons",
                                controlId = "menu2.uf_player.unit.status.selected.size",
                                settingKey = "player.raidGroupNameSize",
                                prepareKind = "unitStatus",
                                prepareValue = "raidgroupname",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Separated the Augmentation Evoker resources: Ebon Might now renders on the Player power bar, Essence is an ordinary Class Resource, and Mana moves to Alternative Mana. The Ebon Might bar takes its height, position, texture, background, border and text from the Player Power settings; only its fill colour still comes from the Ebon Might colour entry.",
                        "Class Resource width, offsets, pixel snapping and cooldown anchoring finally apply to an Augmentation Evoker's Essence bar; it used to silently copy the power bar's width and anchor and ignore those settings.",
                        "Turning the Player Power bar off now also turns off the Ebon Might display instead of leaving an empty bar behind.",
                        "Ebon Might's bar and duration text follow live setting changes instead of freezing at the values they had when the native aura slot was first created.",
                        "Added a Power width slider to the Class Resources > Player Power card, where Width mode \"Manual\" previously had no width to set. Dragging it releases *Sync width to Class Resource*, because that sync outranks an explicit width.",
                        "Switching the Active profile now offers a UI reload: frames re-apply at once, but settings that are only read at load time otherwise keep the old profile's values until the next reload.",
                        "The group preview LAYERS chips now apply to the preview frames drawn on screen as well as to the preview box in the menu, and Shift-click solo shows only that one element on them.",
                        "Cooldown and stack numbers on the preview's aura icons follow the CD/Stack chip, and the chip is greyed out when no enabled aura lane prints a timer or stack count.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Power text on the Target, Focus, Pet and Boss frames follows the unit you are actually on again. With *Colour power text by type* enabled the colour was resolved once and then kept across every target change, so a Focus or Rage target could stay on the previous target's colour, or sit on Mana blue for the rest of the session (#125). Frames with the power bar switched off were affected the most, because they had no bar to take fresh resource data from.",
                        "Power text no longer falls back to the Mana colour when a unit reports no resource at all. It renders the configured text colour instead, which is what those slots show with colour by power type switched off.",
                        "Boss frames no longer freeze at the range fade they happened to have when the pull started. Boss units have no range event of their own, so the periodic check behind *Enable Range Fade* now keeps running in combat instead of stopping at the encounter start.",
                        "The range fade check now retires completely once nothing is left to sample. Only units MSUF has no range event for keep the timer running, so a state without such a unit costs nothing while idle instead of waking up every 0.75 to 2 seconds.",
                        "The Assistant can see and set the Power width slider again. Its generated control schema had not been rebuilt since the slider landed, so the one control added this cycle was missing from everything the Assistant can reach by name.",
                        "The Assistant can now drive the Active auras on this frame dropdown in the blacklist workspace. It was the only control in that section it could not see, so a live scan could be started and blocked by hand but not by request.",
                        "Aura name resolution compiles its alias list once per container instead of rebuilding an iterator on every event, which is the hot path whenever the client falls back to a full aura update in a raid.",
                        "The over-absorb glow decides once per render pass whether the absorb value is protected, instead of re-checking it at every branch that writes to the bar.",
                        "Fixed a spell indicator's health-bar highlight covering the player name and the aura icons on live Group Frames, while the menu preview drew the same effect correctly underneath (#123). The effect rode along whenever its native aura container was re-levelled, so opening the settings or changing zone could flip the order either way; it now keeps the Layer it was configured with.",
                        "Full-Frame effect previews in the Group preview and in Edit Mode now paint through the same renderer the frames use, so Glow shows its real halo instead of four flat edges and Pulse animates with its live opacity.",
                        "Changing a spell indicator's Display as shape now re-gates that section right away; controls belonging to the previous shape, such as Icon Effect, could stay visible until an unrelated click refreshed the page.",
                        "Colour changes on the Colors page now repaint the Resources strip in the preview immediately instead of leaving it on the previous colours until the tab was rebuilt.",
                        "Fixed a raid frame block not staying where it was placed in Edit Mode: the saved position was converted between two internal formats with mismatched roster counts and drifted by up to 162 pixels, and a click that never moved could permanently lock the conversion out.",
                        "Long castbar spell names are now shortened with a visible ellipsis that respects the bar width instead of being clipped by the renderer at an unpredictable spot (#121); a 23-character name could previously disappear completely under a 25-character limit, because the client cuts a bounded line at a glyph-dependent position.",
                        "Turning off a castbar's cast time hands those pixels back to the spell name instead of leaving the gap reserved, so names truncate far less often.",
                        "Fixed an Augmentation Evoker's player health bar shrinking by the extra composite height, and the power bar showing frozen Mana numbers under the Ebon Might duration text.",
                        "If the UI starts in combat and the native aura container cannot be created, an Augmentation Evoker's power bar falls back to a normal Mana bar and retries after combat instead of showing an empty bar.",
                        "The raid preview shows the correct group number on each preview frame instead of numbering members 1-5 within every group.",
                        "The power colour swatch on the Global Fonts page shows an Augmentation Evoker's real power token instead of a hard-coded Essence colour.",
                        "The castbar name shortening no longer builds a cache key string on every text write.",
                    },
                },
            },
        },
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
        {
            version = "6.06",
            date = "2026-08-13",
            sections = {
                {
                    title = "Changes",
                    bullets = {
                        "Added a Non-Player Auras Debuff filter for Unit and Group Frames, including Menu, profile import, diagnostics, and Assistant support. It keeps encounter and environment Debuffs while excluding effects caused by players or player pets.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed an edge case where Player, Target, Boss, and other Unit Frame health text remained hidden after importing profiles with a conflicting obsolete visibility value. Current profile settings now always win, while legacy-only profiles retain their previous behavior without profile rewrites or recurring runtime work.",
                        "Fixed the MSUF Game Menu button using mismatched dimensions and styling. It now follows the active Game Menu button template, size, font, and EllesmereUI skin without stretching.",
                    },
                },
            },
        },
        {
            version = "6.05",
            date = "2026-08-13",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Reworked Augmentation Evoker resources into one coherent Player Power surface: segmented Essence remains visible while Ebon Might uses its own native duration row. Runtime, embedded and detached layouts, rounded styling, text layers, Menu previews, search, and the Assistant now share the same geometry and ownership.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added Unit Frame load conditions for No target and Out of combat and no target, including Copy To, search, diagnostics, and Assistant control.",
                        "Added a dedicated Class Resource text layer so resource numbers, Rune times, and Ebon Might duration text can be ordered independently from the resource bar and normal Player Power text.",
                        "Added a delayed warning with a direct settings shortcut when Unit Frames are configured to follow Essential Cooldowns but no supported Blizzard or third-party cooldown anchor is active.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Spell Icon Full-Frame Effects ignoring their configured element layer. Effects now use a frame-local surface so their 0-30 layer orders correctly against bars, text, and other Unit Frame elements.",
                        "Fixed helpful and hostile Group Aura owners retaining invalid exact-ID assignments after assistability, roster-presence, or instance transitions. Updates remain event-driven and fail closed without polling or restricted Aura reads.",
                        "Fixed Interrupt Ready colors and Focus Kick state becoming stale when a protected cooldown completed. MSUF now uses Blizzard's native duration completion callback with a one-shot fallback and ignores unrelated cooldown events.",
                        "Fixed Group Range Fade briefly treating members from another instance or phase as in range after portal and party-presence transitions.",
                        "Fixed Castbars jumping when switching between Unit Frame anchoring and independent Edit Mode placement.",
                        "Fixed later canonical Aura profile revisions being mistaken for legacy data eligible for the original Aura reset.",
                        "Refreshed cached Menu pages when reopening MSUF, made exported profile strings immediately selectable for copying, and exposed the HEX value in the compact color picker.",
                        "Improved Assistant handling for direct control wording, target-aware visibility requests, outline sizing, background textures, and maximum-health-loss textures.",
                    },
                },
            },
        },
        {
            version = "6.04",
            date = "2026-08-13",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Reworked Unit Frame Auras around explicit lane ownership. Every Buff and Debuff lane now owns its exact layout, filtering, text, effect, and visibility settings, while icon appearance remains global by Aura type. Existing profiles retain their visible setup, and runtime, Menu, Edit Mode, search, and the Assistant now use the same ownership model.",
                        "Added a profile-specific option to disable Northern Sky Raid Tools nicknames on MSUF frames without changing NSRT or its settings. The integration remains enabled by default and can also be controlled through the Assistant.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Reduced recurring work on frequent Health and Texture Layer events. Health prediction and text followers now skip already-pending updates, while dynamic Texture Layers refresh only affected slots, use color-only updates where possible, and reuse their runtime objects.",
                        "Fixed the Elite Indicator missing from Unit Frame previews. Elite, Rare Elite, Rare, and Boss classifications now use their matching Blizzard icons in runtime and previews while sharing one position, size, and layer.",
                        "Fixed identity-dependent Aura displays becoming stale after taxi transitions and helpful Group auras remaining visible when their caster identity could no longer be verified out of range. The existing range and lifecycle events now refresh them without polling.",
                        "Fixed sorted or filtered Raid headers temporarily omitting roster members when unit-name data lagged behind the authoritative Raid roster. MSUF now waits for a complete name list and otherwise falls back to Blizzard's native roster path.",
                        "Fixed Tracked Buffs silently inheriting the normal Buff container's sort method and direction instead of using their own ordering.",
                        "Fixed Group Frame preview borders not repainting immediately, and fixed rounded borders overwriting active Aggro or Dispel test colors after the preview refresh.",
                        "Kept reload-required popups above the MSUF options window and expanded Unit Frame Basics sections so their controls no longer clip.",
                        "Improved the disabled Options-module error so it tells the user to enable MSUF Options in Blizzard's AddOns menu.",
                    },
                },
            },
        },
        {
            version = "6.03",
            date = "2026-08-12",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Track any group buff from any specialization. Group Frame Spell Icons now provide a shared All Specs workspace, so entries such as Feint can be configured once and remain active across every character specialization.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Multi-Spec now exposes all 40 Retail specializations. Custom Aura IDs can also be added to an individual specialization, allowing a Holy Priest configuration, for example, to track Feint (1966) on another group member while Only show my casts is disabled.",
                        "Added a curated, class-wide Big Defensive Spell-ID filter for friendly Unit and Group Frames, with Blizzard's native classification as the restricted-data fallback. Aura classification choices are now mutually exclusive while Only mine and Also include nameplate-only remain explicit modifiers, and Menu, search, and the Assistant share the same contract.",
                        "Added direct Assistant control and cold-path diagnostics for Unit Frame Buff and Debuff Full-Frame Effects. Menu and Assistant now share the same effect choices without polling or reading protected native Aura visibility.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Target of Target and Focus Target health bars and names losing class colors when WoW protects dependent-unit class data in combat. Protected colors now flow directly through Blizzard-native color sinks without polling or persistent secret-value caches.",
                        "Fixed Health and Power gradients missing or differing in Unit and Group previews. Embedded, detached, and rounded Power previews now reuse the same gradient composition as runtime rendering.",
                        "Fixed Level, Race, and Class text in Unit Frame previews using the default preview font instead of the selected unit font.",
                        "Made Cleanse Border changes request the required UI reload.",
                        "Kept the Player Castbar provider selectable in the Bars menu.",
                        "Fixed native Aura containers triggering a forbidden EventRegistrations error during Unit Frame aura setup.",
                        "Improved the ownership handoff between MSUF and Blizzard Party/Raid frames. Provider and fallback changes now return frames reliably through Blizzard's own lifecycle and request the required UI reload.",
                        "Fixed Clique and other click-cast providers losing their Unit Frame bindings after profile or configuration updates. MSUF now preserves provider-owned secure click attributes after the initial fallback setup.",
                        "Isolated Group Spell Indicator preview positions from live saved positions.",
                        "Restored continuous Devourer class-resource updates and removed obsolete partial-update ownership from the resource pipeline.",
                        "Fixed Icicles showing an Aura icon over Class Resources or retaining incorrect stack counts. Icicles now refreshes the exact player Aura on each Aura change, while protected Icicle and Maelstrom Weapon counts fill their pips through Blizzard's native StatusBar clamping without Lua comparisons.",
                        "Fixed Tip of the Spear showing incorrect stacks after current Survival Hunter spenders and Takedown with Twin Fangs. Stack tracking now also expires correctly without protected Aura reads.",
                        "Fixed native Auras, Spell Indicators, and Aura-based Class Resources becoming stale or retaining incorrect durations after cinematics and entering the world. Lifecycle refreshes are now coalesced and event-driven without polling.",
                        "Refreshed Unit Frame names immediately after anchor changes.",
                        "Restored live Group frames correctly after preview roster handoffs.",
                        "Honored configured Aura layers for fixed Group slots.",
                        "Fixed the animated Resting symbol trying to use an unavailable Blizzard atlas; unsupported clients now fall back safely.",
                        "Fixed Unit Frame Edit Mode quick actions applying stale compiled settings after size, position, reset, copy, or detached Power changes.",
                    },
                },
            },
        },
        {
            version = "6.02",
            date = "2026-08-11",
            sections = {
                {
                    title = "WoW 12.1 Release Highlights",
                    bullets = {
                        "Split Unit Preview Buffs and Debuffs into independent layers with correct handle-to-menu routing, and expanded the frame-local Debuff blacklist presets.",
                        "Added Blizzard-native Ebon Might duration text plus safe, independently configurable Alternative Mana width geometry across runtime, previews, search, and the Assistant.",
                        "Made Blizzard's animated Resting symbol part of the fresh default profile while preserving existing profile choices and live Resting state.",
                        "Reworked the upgrade-highlight tour around real Back/Forward navigation and added Assistant commands that can restart a skipped or completed tour.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed nickname-provider fallback refreshes so updated names reach the correct Unit and Group Frames without broad polling.",
                        "Guarded secret Player Health values before Class Resource logic can inspect them in combat.",
                        "Fixed Texture Layer target refreshes, rounded clipping, true-outline geometry, rounded preview edges, and Castbar preview text positions after live setting changes.",
                    },
                },
            },
        },
    },
}

ns.MSUF_FullChangelog = data
ExportPublic("MSUF_FullChangelog", data)
