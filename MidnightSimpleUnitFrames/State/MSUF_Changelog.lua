-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "0F4D4DEB7B5C6FB191C138874B2C10CFA1068C1AAD41385508DAE559D9880B5E",
    currentVersion = "6.504-beta3",
    historyFromVersion = "6.501",
    previousVersion = "6.503",
    rangeLabel = "6.503 -> 6.504-beta3",
    entries = {
        {
            version = "6.504-beta3",
            date = "2026-10-20",
            sections = {
                {
                    title = "Bug Fixes",
                    bullets = {
                        {
                            text = "Fixed buffs on the target and other unit frames still going missing until /reload in some places, such as the Labyrinth delve. Aura icons are now set up more robustly, and a broken aura display is rebuilt right away instead of on the next target change.",
                            link = {
                                pageKey = "uf_target",
                                query = "target buff aura visible",
                                label = "Target buff visibility",
                                sectionId = "auras",
                                controlId = "menu2.uf_target.auras.unit-workspace.lane.buff.layout.visible",
                                settingKey = "auras3.target.buff.visible",
                            },
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
        {
            version = "6.501",
            date = "2026-10-14",
            sections = {
                {
                    title = "Bug Fixes",
                    bullets = {
                        {
                            text = "Fixed boss power bars and power text freezing on Target and Boss frames when an encounter uses a custom resource name.",
                            linkless = true,
                        },
                        {
                            text = "Fixed delayed or missing party and raid member names after joining a group or changing zones. Names now refresh when the client receives the unit's name.",
                            linkless = true,
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        {
                            text = "Removed the feature, bug fix and performance counters from the login welcome message.",
                            link = {
                                pageKey = "opt_misc",
                                query = "show welcome message",
                                label = "Show welcome message",
                                sectionId = "misc_startup",
                                controlId = "menu2.opt.misc.global.setting.show.welcome.message",
                                settingKey = "general.showWelcomeMessage",
                            },
                        },
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
