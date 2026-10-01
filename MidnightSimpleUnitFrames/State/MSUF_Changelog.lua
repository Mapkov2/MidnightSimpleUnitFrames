-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "AC24A538D5C23FD4B9B364E4FCFFD890D0276F9B9ABCE400056B195F9DBC2ADA",
    currentVersion = "6.5-beta13",
    historyFromVersion = "6.5-beta10",
    previousVersion = "6.5-beta12",
    rangeLabel = "6.5-beta12 -> 6.5-beta13",
    entries = {
        {
            version = "6.5-beta13",
            date = "2026-10-02",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Toggle additional group features directly from their accordion headers. Name strip, Member targets, Pet frames, Allied boss frames, Healer mana bars and Forever Buff coverage keep their master switch available while the section is closed.",
                            link = {
                                pageKey = "gf_layout",
                                query = "enable",
                                label = "Enable",
                                sectionId = "healer_mana",
                                controlId = "menu2.gf_layout.group.field.healermanaenabled",
                                settingKey = "gf_raid.healerManaEnabled",
                                prepareKind = "groupScope",
                                prepareValue = "raid",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Healer mana Text color is now under Colors > Group > Healer mana bars and remains accessible through the section's three-dot color menu. Existing saved values are retained; color edits follow the shared Party, Raid and Mythic Raid group-color behavior.",
                        "Updated menu and Edit Mode translations across all twelve supported locales.",
                        "Classic aura rendering, group configuration and castbar frame pools have clearer shared ownership while retaining their existing controls.",
                    },
                },
                {
                    title = "Fixes",
                    bullets = {
                        "Group headers handle combat transitions, roster changes and small raids more consistently. Group layout, class priority, indicators and previews refresh through their shared owners.",
                        "Classic aura filters, icon rendering and event updates remain consistent across profile and specialization changes.",
                        "Arena and boss castbars share frame lifecycle handling, restore native text when needed and keep outline and cooldown state current.",
                        "Mists Death Knight runes follow their rune type colors when no explicit rune color override is selected. Combo points and aura-based class resources update their displayed values correctly.",
                        "Profile normalization retains supported numeric spell IDs, profile changes refresh visible menu pages, and Undo history stays bounded for large profiles.",
                        "Global font and texture changes retain frame opacity and refresh the affected text. Unit tooltips display available AFK and DND flags, and portrait atlas artwork keeps its full image and flip direction.",
                        "Edit Mode Cancel discards unfinished text edits before restoring settings. Combat interruptions preserve supported drag positions, and movement history uses translated labels.",
                        "Menu search normalizes Unicode input, retains edits and avoids rebuilding unaffected pages. Menu previews reuse their presentation state.",
                        "Group Anchor and class priority sections size their wrapped text correctly. Portrait controls and the Healer mana section use the corrected spacing.",
                        "Opening Options from the Game Menu shares the deferred cold-load boundary with the keybind, reducing first-open script-time pressure.",
                    },
                },
            },
        },
        {
            version = "6.5-beta12",
            date = "2026-10-01",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Give group names their own strip above the health bar. Group Layout > Name strip offers a separate name area with adjustable height, color and opacity.",
                            link = {
                                pageKey = "gf_layout",
                                query = "show names on a strip above the health bar",
                                label = "Show names on a strip above the health bar",
                                sectionId = "name_bar",
                                controlId = "menu2.gf_layout.group.field.namebarenabled",
                                settingKey = "gf_party.nameBarEnabled",
                                prepareKind = "groupScope",
                                prepareValue = "party",
                            },
                        },
                        {
                            text = "Add frames for your group members' targets. Position and size the additional target frames under Group Layout > Member targets, with an option to include your own target.",
                            link = {
                                pageKey = "gf_layout",
                                query = "enable",
                                label = "Enable",
                                sectionId = "party_targets",
                                controlId = "menu2.gf_layout.group.field.targetsenabled",
                                settingKey = "gf_party.targetsEnabled",
                                prepareKind = "groupScope",
                                prepareValue = "party",
                            },
                        },
                        {
                            text = "Show your group's pets in their own frame block. Group Layout > Pet frames has separate dimensions, position, columns, text size and a pet-count limit.",
                            link = {
                                pageKey = "gf_layout",
                                query = "enable",
                                label = "Enable",
                                sectionId = "group_pets",
                                controlId = "menu2.gf_layout.group.field.petsenabled",
                                settingKey = "gf_raid.petsEnabled",
                                prepareKind = "groupScope",
                                prepareValue = "raid",
                            },
                        },
                        {
                            text = "Keep healer mana visible in a separate row. Group Layout > Healer mana bars provides its own size, position and text controls; members must have the Healer role assigned.",
                            link = {
                                pageKey = "gf_layout",
                                query = "enable",
                                label = "Enable",
                                sectionId = "healer_mana",
                                controlId = "menu2.gf_layout.group.field.healermanaenabled",
                                settingKey = "gf_raid.healerManaEnabled",
                                prepareKind = "groupScope",
                                prepareValue = "raid",
                            },
                        },
                        {
                            text = "Show dedicated frames for allied bosses on clients with boss units. Enable Allied boss frames under Group Layout, with optional healer-only visibility based on your assigned group role.",
                            link = {
                                pageKey = "gf_layout",
                                query = "enable",
                                label = "Enable",
                                sectionId = "friendly_bosses",
                                controlId = "menu2.gf_layout.group.field.friendlybossenabled",
                                settingKey = "gf_party.friendlyBossEnabled",
                                prepareKind = "groupScope",
                                prepareValue = "party",
                            },
                        },
                        {
                            text = "Adapt group frames to the raid size. Size & Scaling offers manual or group-size scaling plus separate width, height, growth and optional position for 1-10, 11-20, 21-25 and 26+ players. Hidden groups can be excluded from the size calculation.",
                            link = {
                                pageKey = "gf_layout",
                                query = "use raid size overrides",
                                label = "Use raid size overrides",
                                sectionId = "scaling",
                                controlId = "menu2.gf_layout.group.field.layouttiersenabled",
                                settingKey = "gf_raid.layoutTiersEnabled",
                                prepareKind = "groupScope",
                                prepareValue = "raid",
                            },
                        },
                        {
                            text = "Let auras and indicators follow resized group frames. Indicators, aura icons and tracked buffs each have their own option to scale with frame dimensions.",
                            link = {
                                pageKey = "gf_layout",
                                query = "scale auras with frame dimensions",
                                label = "Scale auras with frame dimensions",
                                sectionId = "scaling",
                                controlId = "menu2.gf_layout.group.field.autoscaleaurasonresize",
                                settingKey = "gf_raid.autoScaleAurasOnResize",
                                prepareKind = "groupScope",
                                prepareValue = "raid",
                            },
                        },
                        {
                            text = "Choose a class priority for group sorting. Drag classes into your preferred order within the current group and role order; eligible raid role layouts also support alphabetical names within roles.",
                            link = {
                                pageKey = "gf_layout",
                                query = "use class priority",
                                label = "Use class priority",
                                sectionId = "sorting",
                                controlId = "menu2.gf_layout.group.field.sortclasspriority",
                                settingKey = "gf_raid.sortClassPriority",
                                prepareKind = "groupScope",
                                prepareValue = "raid",
                            },
                        },
                        {
                            text = "Use Party layout for small raids and tidy empty group space. New organization rules cover raids of up to five players, solo centering, collapsing empty preserved raid groups and hiding groups 5-8 in supported Mythic raids.",
                            link = {
                                pageKey = "gf_layout",
                                query = "use party layout for raids up to 5 players",
                                label = "Use Party layout for raids up to 5 players",
                                sectionId = "layout_advanced",
                                controlId = "menu2.gf_layout.group.field.smallraidasparty",
                                settingKey = "gf_party.smallRaidAsParty",
                                prepareKind = "groupScope",
                                prepareValue = "party",
                            },
                        },
                        {
                            text = "Check group buff coverage on WoW Forever. Mark missing class buffs, add optional glow and limit Thorns reminders to tanks. Icons hide in restricted states by default; the combat-display option retains known coverage where fresh aura data is unavailable.",
                            link = {
                                pageKey = "gf_layout",
                                query = "show buff coverage icons",
                                label = "Show buff coverage icons",
                                sectionId = "buff_coverage",
                                controlId = "menu2.gf_layout.group.field.buffcoverageenabled",
                                settingKey = "gf_party.buffCoverageEnabled",
                                prepareKind = "groupScope",
                                prepareValue = "party",
                            },
                        },
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
                        {
                            text = "Add resource helpers for your client and class. Preview upcoming mana costs; supported clients also offer regeneration-pause and mana-return displays. Midnight adds Ignore Pain duration and Arcane window timing, with shared geometry and separate colors.",
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
                            text = "Accent the final tick of a supported channel. Highlight last channel tick adds a final-tick cue to spell-specific Player castbar tick markers.",
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
                            text = "Fine-tune portrait artwork. Portrait controls include zoom, left-to-right flip, inset shadow strength and more placement, size and layering choices for portrait dragons.",
                            link = {
                                pageKey = "uf_player",
                                query = "flip portrait left to right",
                                label = "Flip portrait left to right",
                                sectionId = "portrait",
                                controlId = "menu2.uf_player.unit.portrait.portraitflip",
                                settingKey = "player.portraitFlip",
                                prepareKind = "unitPortraitTab",
                                prepareValue = "advanced",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Profile variants: override selected settings and layouts for specializations, locations or a hotkey while preserving the base profile. Variants have their own recording editor, conditions, priority, field selection and import/export options.",
                        "Resource marks and thresholds: add absolute-value or percentage marks to Player Power, Class Resource or Alternative Mana, restrict them by power type, and choose marker width, color and an above/below color-change threshold.",
                        "Group auxiliary frames have individual layout and text controls. Member targets can include your own target, pets have a configurable count limit, allied bosses can be restricted to your assigned Healer role, and healer mana rows can show the mana amount with their own text color.",
                        "Group size tiers combine optional frame dimensions, growth and position with each tier's scale percentage. Base dimensions remain the fallback; indicator, aura and tracked-buff resizing can be enabled independently.",
                        "Forever buff coverage checks Mark of the Wild, Thorns, Arcane Intellect, Paladin blessings, Fortitude and Divine Spirit according to the selected options and group providers. Thorns can be tank-only; Intellect and Spirit follow mana users. Restricted-state visibility is optional and preserves known coverage where fresh data is unavailable.",
                        "Forever Swing Timers support separate hand settings, an off-hand lane within the main-hand bar, queued-attack cues and custom labels, reach warnings, fill direction and elapsed or remaining time. Disabling the module restores Blizzard's previous swing-bar visibility.",
                        "Midnight Arcane window timing can display seconds, global cooldowns or both, with adjustable countdown visibility, warning timing and phase colors. Resource helper colors are available under Colors > Additional resource colors.",
                        "Menu navigation, section labels, control help and disabled-setting explanations are clearer. Search respects the active client, preserves field edits and improves discovery of MSUF Suite settings when Suite is installed.",
                        "Updated translations across the twelve supported locales.",
                        "The in-game Assistant is retired and no longer included. Its saved chat data is removed once and excluded from profile transfers. After a manual update, delete the old MidnightSimpleUnitFrames_Assistant folder from Interface/AddOns.",
                    },
                },
                {
                    title = "MSUF Suite companion",
                    bullets = {
                        "With MSUF Suite installed separately, Retail and WoW Forever can use the Mapko skin for Blizzard Nameplates, with appearance, text, castbar, aura and threat options. Blizzard continues to own health, threat, casts, auras, selection and click handling; the module ships in MSUF Suite.",
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
