-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "0A78E7677086F39F24262D3322941A9B507312007249E3C7AA3263DD073A5D95",
    currentVersion = "6.5-beta12",
    historyFromVersion = "6.5-beta9",
    previousVersion = "6.5-beta11",
    rangeLabel = "6.5-beta11 -> 6.5-beta12",
    entries = {
        {
            version = "6.5-beta12",
            date = "2026-10-01",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Customize Swing Timers on WoW Forever. Configure Main Hand, Off Hand and Ranged bars, their appearance and text, then preview and drag them to a saved profile position.",
                            link = {
                                pageKey = "swingtimers",
                                query = "enable swing timer module",
                                label = "Enable Swing Timer module",
                                sectionId = "swing_module",
                                controlId = "menu2.swingtimers.swing.enabled",
                                settingKey = "swingTimers.enabled",
                            },
                        },
                        {
                            text = "Hide Player Power together with Class Resource outside combat. Enable the new option under Class Resource > Auto-Hide alongside Hide out of combat; Edit Mode keeps both visible for placement.",
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
                            text = "Place the GCD bar independently on supported clients. Global > Castbars offers a separate GCD bar with its own size, position, opacity, time and spell display, plus idle-background and combat-only options.",
                            link = {
                                pageKey = "opt_castbar",
                                query = "place gcd bar separately",
                                label = "Place GCD bar separately",
                                sectionId = "castbar_gcd",
                                controlId = "menu2.opt.castbar.global.gcd.gcd.bar.detached",
                                settingKey = "general.gcdBarDetached",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "WoW Forever group frames can mark missing class buffs, with optional glow and a Thorns-only-on-tanks rule. Icons hide during combat and other restricted states by default; Keep showing during combat retains known buff coverage where fresh aura data is unavailable.",
                        "Forever Swing Timers support separate hand settings, an off-hand lane within the main-hand bar, queued-attack cues and custom labels, reach warnings, fill direction and elapsed or remaining time. Disabling the module restores Blizzard's previous swing-bar visibility.",
                        "Class Resource extras include configurable Arcane window time in seconds, global cooldowns or both, warning timing and phase colors on supported clients.",
                        "Menu navigation, section labels, control help and disabled-setting explanations are clearer. Search respects the active client and improves discovery of MSUF Suite settings when Suite is installed.",
                        "Updated translations across the twelve supported locales.",
                        "The in-game Assistant is retired and no longer included. Its saved chat data is removed once and excluded from profile transfers. After a manual update, delete the old MidnightSimpleUnitFrames_Assistant folder from Interface/AddOns.",
                    },
                },
                {
                    title = "Fixes",
                    bullets = {
                        "Malformed profile imports no longer overwrite the active profile. Applying a profile only imports a Blizzard Edit Mode snapshot when that import option was selected.",
                        "Unit frames recover after instance or housing visibility changes, resume their suspended event routes, and refresh stance text after being shown again. Portrait variants update without requiring a reload.",
                        "Aura layouts refresh after profile switches, resets, imports and specialization changes. Aura icons allow clicks through to their unit frame; countdown bars share one driver that stops when idle.",
                        "Resource marks handle secret power percentages and remain above resource pips. Castbar fill direction and countdown mode work together, and Classic Interrupt Ready has a cooldown fallback.",
                        "Party target frames refresh when their compound unit tokens receive no native unit event. Healer mana text receives its font before its first update, and group sorting, previews and Edit Mode use consistent layout settings.",
                        "Page resets work across supported clients and retain Undo. Edit Mode Cancel and Undo cannot write an earlier profile's edits into a newly selected profile.",
                        "Menu text fields retain edits, resource movement stays inside Edit Mode, and Class Resource previews fit the available space. Preview animation, factory-profile decoding and search avoid repeated work.",
                    },
                },
            },
        },
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
