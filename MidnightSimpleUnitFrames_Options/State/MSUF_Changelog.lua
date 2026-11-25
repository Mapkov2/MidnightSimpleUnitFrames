-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "3D0F741BEEE5C08474C65566513B5399571C5DEDE08CBB09E4605521FF0CBB35",
    currentVersion = "7.0.5-beta2",
    historyFromVersion = "7.021",
    previousVersion = "7.0.4",
    rangeLabel = "7.0.4 -> 7.0.5-beta2",
    entries = {
        {
            version = "7.0.5-beta2",
            date = "2026-11-25",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Class-colored frame outlines. In Bars > Frame Outline, turn on Class Color Outline to use each player character's class color. NPCs keep the outline color you picked. Set it once in Shared or override it for a unit, party or raid scope.",
                            link = {
                                pageKey = "opt_bars",
                                query = "class color outline",
                                label = "Class Color Outline",
                                sectionId = "bars_outline",
                                controlId = "menu2.opt.bars.global.outline.class.color",
                                settingKey = "",
                            },
                        },
                    },
                },
                {
                    title = "Frames and portraits",
                    bullets = {
                        "Joining a group while already in combat could block the health bar layout and leave a party portrait missing. The frame now retries protected layout when it becomes writable.",
                        "Party members whose names arrive late when entering a dungeon appear in the roster and move into the configured sort order when their names are ready.",
                        "The animated party preview now shows the spell icon while a sample cast is active and restores the 3D portrait afterwards.",
                    },
                },
                {
                    title = "Colors and appearance",
                    bullets = {
                        "Open the outline settings from the gear beside a border control or color shortcut. The overview also lets you adjust the shared group-border and focus-highlight colors and set thickness for the selected group scope.",
                        "External Defensives have their own aura icon style and shape. Each setting inherits the Buffs appearance until you override it.",
                        "The player castbar can show the collected item's icon for recognized pickups. Icon spacing is consistent on either side of the bar and in its preview.",
                    },
                },
                {
                    title = "Options and compatibility",
                    bullets = {
                        "The Nameplates font preview shows the selected color. Reset restores the inherited color, and searching for character name parts opens Shared.",
                        "On WoW Forever, hand settings in Swing Timer reflect the module's enabled state. Characters whose realm is temporarily unavailable can recover an existing profile and its specialization assignments.",
                        "The Misc tooltip shortcut opens the Suite's unit-frame tooltip settings when available. Core provides its own tooltip controls when used on its own.",
                        "Added the Midnight 12.1.7 interface alongside 12.1.5.",
                    },
                },
            },
        },
        {
            version = "7.0.4",
            date = "2026-11-20",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Aura Lanes and Bars. Icons or bars per buff and debuff lane. Retail and WoW Forever.",
                            link = {
                                pageKey = "uf_player",
                                query = "show as bars",
                                label = "Player Buffs: Show as Bars",
                                sectionId = "auras",
                                controlId = "menu2.uf_player.auras.unit-workspace.lane.buff.layout.show-as-bars",
                                settingKey = "",
                                prepareKind = "unitAuraWorkspace",
                                prepareValue = "buff_bars",
                            },
                        },
                        {
                            text = "Player castbar Force Off. Hide Blizzard's castbar for Quartz or similar addons.",
                            link = {
                                pageKey = "uf_player",
                                query = "castbar provider",
                                label = "Castbar provider",
                                sectionId = "castbar",
                                controlId = "menu2.uf_player.unit.castbar.provider",
                                settingKey = "general.castbarPlayerBackend",
                                prepareKind = "unitCastbarTab",
                                prepareValue = "general",
                            },
                        },
                        {
                            text = "Party frames in raids. Keep your own subgroup visible.",
                            link = {
                                pageKey = "gf_layout",
                                query = "Show Party Frames in Raid",
                                label = "Show Party Frames in Raid",
                                sectionId = "layout_advanced",
                                controlId = "menu2.gf_layout.group.field.showpartyinraid",
                                settingKey = "gf_party.showPartyInRaid",
                                prepareKind = "groupScope",
                                prepareValue = "party",
                            },
                        },
                        {
                            text = "Outline Settings gear. Edit individual borders or use All outlines. Supports compatible Suite borders.",
                            link = {
                                pageKey = "opt_bars",
                                query = "bar outline thickness",
                                label = "Frame Outline gear",
                                sectionId = "bars_outline",
                                controlId = "menu2.opt.bars.global.outline.thickness",
                                settingKey = "",
                            },
                        },
                    },
                },
                {
                    title = "Aura Bar Layout options",
                    bullets = {
                        "Growth and fill. Four growth directions. Independent fill direction.",
                        "Combined bars. Buffs first, debuffs next. Shared Buff anchor and growth. Separate filters, sorting and limits.",
                        "Appearance. Textures, icon position and size, spacing, colors and outlines.",
                    },
                },
                {
                    title = "Fixes and improvements",
                    bullets = {
                        "See New Features. Unread notes are highlighted in the toolbar. Clicking the button takes you to the top of the latest notes, with links to highlighted settings.",
                        "Player channels. Penance and other casts that transition to channels keep their recipient names and spell ranks where ranks are supported.",
                        "WoW Forever range fading. Hostile targets recover when the initial range check has no result. Warlocks use the highest known Shadow Bolt rank, with Drain Life as a fallback.",
                        "Combined aura bars. Dragging joined buff and debuff bars in Edit Mode keeps the preview under the cursor until you release it.",
                        "Party and raid class colors. Health bars recover their class color after resurrection in instances, including when a frame reaches full health before combat ends.",
                        "Profiles. Inactive profiles stay compact, and restore points share identical settings to use less memory. Existing profiles retain supported aura-bar appearance options.",
                        "Options. Settings search uses less memory. Options and Edit Mode previews reflect the selected aura-bar layout and appearance. Choice popups and themed color fields render correctly.",
                        "Textures. The Blizzard-style unit frame texture is included in MSUF Core.",
                    },
                },
            },
        },
        {
            version = "7.0.3",
            date = "2026-11-18",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "PvP countdown. See your remaining PvP flag time next to the Player PvP icon on WoW Forever.",
                            link = {
                                pageKey = "uf_player",
                                query = "show pvp countdown",
                                label = "Show PvP countdown",
                                sectionId = "status_icons",
                                controlId = "menu2.uf_player.unit.status.pvp.countdown",
                                settingKey = "player.pvpIndicatorCountdownEnabled",
                                prepareKind = "unitStatus",
                                prepareValue = "statusPvp",
                            },
                        },
                        {
                            text = "Weakened Soul. Track it on WoW Forever under Party/Raid Frames > Auras > Spell Indicators > Choose spell. Similar debuffs and duplicate icons can appear.",
                            linkless = true,
                        },
                        {
                            text = "Player cast recipient. Show who receives your cast, including mouseover casts.",
                            link = {
                                pageKey = "uf_player",
                                query = "target name",
                                label = "Enable",
                                sectionId = "castbar",
                                controlId = "menu2.uf_player.unit.castbar.show_target_name",
                                settingKey = "general.castbarPlayerShowTargetName",
                                prepareKind = "menuTab",
                                prepareValue = "spell",
                            },
                        },
                        {
                            text = "Castbar fades. Make castbars fade in and out.",
                            link = {
                                pageKey = "opt_castbar",
                                query = "fade castbars in and out",
                                label = "Fade castbars in and out",
                                sectionId = "castbar_behavior",
                                controlId = "menu2.opt.castbar.global.behavior.castbar.fade.enabled",
                                settingKey = "general.castbarFadeEnabled",
                            },
                        },
                        {
                            text = "Frame fades. Fade in unit frames as they appear.",
                            link = {
                                pageKey = "uf_target",
                                query = "fade in when shown",
                                label = "Fade in when shown",
                                sectionId = "transparency",
                                controlId = "menu2.uf_target.unit.transparency.fade_in_on_show",
                                settingKey = "target.fadeInOnShow",
                                prepareKind = "unitAlphaTab",
                                prepareValue = "combat",
                            },
                        },
                        {
                            text = "Short numbers for Power Text. Choose full or abbreviated resource values.",
                            link = {
                                pageKey = "uf_player",
                                query = "power text short numbers",
                                label = "Short numbers",
                                sectionId = "text",
                                controlId = "menu2.uf_player.unit.text.power.full_value_short",
                                settingKey = "player.powerFullValueShort",
                                prepareKind = "menuTab",
                                prepareValue = "power",
                            },
                        },
                    },
                },
                {
                    title = "General",
                    bullets = {
                        "Start Setup with your current profile, a preset, or an import.",
                        "Settings search handles common questions and typos.",
                        "Show spell ranks on Forever, Classic Era and TBC Anniversary.",
                        "Set the Player castbar latency color and opacity.",
                        "Give Party and Raid frames their own appearance fade.",
                        "Hide the resource bar and text when its resource is unavailable.",
                        "Edit health text gradient stops from the Fonts shortcut.",
                        "Copy To Settings makes room for translated labels.",
                    },
                },
                {
                    title = "Fixes",
                    bullets = {
                        "Fixed blank preview portraits and stale Target and Focus portraits.",
                        "Party frames update when you accept an invite during outdoor combat.",
                        "Party, Raid and Priority frames keep their positions during instance combat.",
                        "Reused group frames refresh their text and clear the old absorb value.",
                        "Group health bars recover their class color after resurrection.",
                        "Fixed Blizzard player castbar handoff and late channel-stop events.",
                        "Fixed the AFK timer and corrected Penance tick markers on WoW Forever.",
                        "Includes the 7.021 fix for Castbars settings and Timer Bar tabs on Classic.",
                    },
                },
            },
        },
        {
            version = "7.021",
            date = "2026-11-15",
            title = "Classic Menu Hotfix",
            sections = {
                {
                    title = "Fixes",
                    bullets = {
                        "Fixed a Lua error that could prevent the Castbars settings from opening. Timer bar tabs now open and can be selected on all three Classic clients.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
