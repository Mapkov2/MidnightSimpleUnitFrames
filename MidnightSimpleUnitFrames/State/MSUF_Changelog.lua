-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "C81247EC347FA612DEBADBC6518D63C09345CDBC38AEDAE933E8935A501DD429",
    currentVersion = "6.5-beta11",
    historyFromVersion = "6.5-beta8",
    previousVersion = "6.5-beta10",
    rangeLabel = "6.5-beta10 -> 6.5-beta11",
    entries = {
        {
            version = "6.5-beta11",
            date = "2026-09-29",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Choose Slanted bar shapes across your frames. Enable Slanted bars under Global > Slanted, then choose where they appear on unit frames, group frames, power bars, castbars, class resources, and mouseover.",
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
                            text = "Switch between Slanted and Rounded while keeping saved frame styles. The Rounded master switch restores Rounded when Slanted is off, including after profile imports and in previews.",
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
                    title = "Changes",
                    bullets = {
                        "Slanted shape controls cover frame scopes, power bars, castbars, class resources, and mouseover, with matching menu previews.",
                        "Hidden unit frames suspend their event routes until shown again.",
                        "When installed, MSUF Suite text follows full global font changes.",
                    },
                },
                {
                    title = "Fixes",
                    bullets = {
                        "Imported Slanted frame styles follow the active Rounded fallback when Slanted is disabled.",
                        "Status badges and level numbers stay within native overlay sublevel limits for imported high layer values.",
                        "Menu section switch labels toggle their feature.",
                    },
                },
            },
        },
        {
            version = "6.5-beta10",
            date = "2026-09-27",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Add a Pet Target frame. Enable it under Pet Target > Basics, then place it in Edit Mode.",
                            link = {
                                pageKey = "uf_pettarget",
                                query = "pet target",
                                label = "Pet Target",
                                sectionId = "frame_basics",
                                controlId = "menu2.uf_pettarget.unit.basics.enabled",
                                settingKey = "pettarget.enabled",
                            },
                        },
                        {
                            text = "Move Class Resources in Edit Mode even while their resource is inactive. Combo Points keep an editable position outside Cat Form, and the drag area remains visible in the preview.",
                            link = {
                                pageKey = "classpower",
                                query = "class resource offset x",
                                label = "Class Resource X offset",
                                sectionId = "classpower_display",
                                controlId = "menu2.classpower.advanced.layout.x",
                                settingKey = "bars.classPowerOffsetX",
                            },
                        },
                        {
                            text = "Place a detached Power bar together with Class Resources or on its own. Its Edit Mode mover and width, height, and position controls work independently of the Class Resource settings.",
                            link = {
                                pageKey = "classpower",
                                query = "detached power x",
                                label = "Detached Power X offset",
                                sectionId = "classpower_detached_power",
                                controlId = "menu2.classpower.advanced.detached.power.layout.x",
                                settingKey = "player.detachedPowerBarOffsetX",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Pet Target has its own runtime frame, defaults, menu controls, and preview on supported clients.",
                        "Class Resources and detached Power bars can be moved separately; an Energy bar anchored to Combo Points continues to follow them.",
                        "The Mainline core and Options addons use the MSUF category in the addon list.",
                    },
                },
                {
                    title = "Fixes",
                    bullets = {
                        "Edit Mode retains movers for temporarily hidden Class Resources and detached Power bars, including an inactive Druid resource.",
                        "Profile scale and menu dropdown alignment are preserved across UI updates.",
                    },
                },
            },
        },
        {
            version = "6.5-beta9",
            date = "2026-09-25",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Show pet buffs and debuffs on the Pet frame. Configure the pet aura lanes under Pet > Auras.",
                            link = {
                                pageKey = "uf_pet",
                                query = "pet buff visible",
                                label = "Pet buff visibility",
                                sectionId = "auras",
                                controlId = "menu2.uf_pet.auras.unit-workspace.lane.buff.layout.visible",
                                settingKey = "auras3.pet.buff.visible",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "WoW Forever's supplied factory profile has its own updated unit-frame defaults. Existing saved profiles remain unchanged.",
                        "The Pet frame includes Classic-specific aura and XP controls. Pet XP appears only when the client supplies pet XP data.",
                    },
                },
            },
        },
        {
            version = "6.5-beta8",
            date = "2026-09-25",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Choose the new Midnight Dark menu appearance. It adds a darker palette to the existing menu layouts while keeping Classic Glass and Midnight available on every supported client.",
                            link = {
                                pageKey = "opt_misc",
                                query = "menu appearance preset",
                                label = "Menu appearance preset",
                                sectionId = "misc_menu_behavior",
                                controlId = "menu2.opt.misc.global.setting.menu.appearance.preset",
                                settingKey = "general.menuAppearancePreset",
                            },
                        },
                        {
                            text = "Align Class Resource with the MSUF Suite Essential cooldown row. When you approve the Suite anchor while class power placement is still at its defaults, the resource bar follows the row and uses its width; you can adjust Width mode under Class Resource.",
                            link = {
                                pageKey = "classpower",
                                query = "width mode",
                                label = "Width mode",
                                sectionId = "classpower_display",
                                controlId = "menu2.classpower.advanced.layout.width.mode",
                                settingKey = "bars.classPowerWidthMode",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "WoW Forever starts fresh profiles and resets from its own factory layout. Existing saved profiles keep their settings; factory health fills use 80% opacity.",
                        "Updated for WoW Forever beta build 1.60.1.70009: pet happiness uses Blizzard's three atlases when available, and group frames use secure initialization snippets after Blizzard's load-order repair.",
                        "Rebuilt the WoW Forever SpellName aura-alias catalog from all eleven 70009 locale exports and revalidated the curated aura IDs.",
                        "Classic Era, TBC and Mists aura filters match readable aura names when a spell rank or cast ID differs from the aura ID. Their generated alias catalogs are no longer loaded or packaged.",
                        "MSUF Suite can join full-profile and module export/import, profile lifecycle changes, Undo/Redo history and the Essential cooldown anchor when installed.",
                        "Added an opt-in all-healers incoming-heal prediction setting. The previous player-only prediction remains the default.",
                        "Blizzard Micro Menu and Bags settings expose horizontal and vertical orientation where the client provides those controls.",
                    },
                },
                {
                    title = "Fixes",
                    bullets = {
                        "WoW Forever's Raid Manager remains visible while opened by gamepad and closes with the panel.",
                        "Missing-health background coloring no longer shows a full reversed health bar at 100% health.",
                        "Hiding Blizzard's TargetFrame also stops the Forever ComboFrame from updating its hidden display.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
