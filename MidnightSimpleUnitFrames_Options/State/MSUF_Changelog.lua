-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "A0E63A5150C96A922D05FD1E2638DBF66C168727D6F9530040B85B0523916CD1",
    currentVersion = "7.0.5-beta4",
    historyFromVersion = "7.021",
    previousVersion = "7.0.5-beta3",
    rangeLabel = "7.0.5-beta3 -> 7.0.5-beta4",
    entries = {
        {
            version = "7.0.5-beta4",
            date = "2026-11-27",
            sections = {
                {
                    title = "Castbars",
                    bullets = {
                        "Centered spell names keep their configured position when the cast timer is on either side. The timer still limits the available name width in Auto fit and Manual width modes.",
                        "Player and Target castbars preserve these settings when you copy a profile or rebuild it from an export.",
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
