-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "067B0789F828801EA9E1EEAD391D29ABC3EA006BCF729121C4EB1007F83F50F9",
    currentVersion = "6.1-Beta4",
    historyFromVersion = "6.1-Beta1",
    previousVersion = "6.1-Beta3",
    rangeLabel = "6.1-Beta3 -> 6.1-Beta4",
    entries = {
        {
            version = "6.1-Beta4",
            date = "2026-08-19",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Power text on the Target, Focus, Pet and Boss frames follows the unit you are actually on again. With *Colour power text by type* enabled the colour was resolved once and then kept across every target change, so a Focus or Rage target could stay on the previous target's colour, or sit on Mana blue for the rest of the session (#125). Frames with the power bar switched off were affected the most, because they had no bar to take fresh resource data from.",
                            link = {
                                pageKey = "uf_target",
                                query = "show power text",
                                label = "Show Power Text",
                                sectionId = "text",
                                controlId = "menu2.uf_target.unit.text.power.show",
                                settingKey = "target.showPowerText",
                            },
                        },
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Power text no longer falls back to the Mana colour when a unit reports no resource at all. It renders the configured text colour instead, which is what those slots show with colour by power type switched off.",
                        "The range fade check now retires completely once nothing is left to sample. Only units MSUF has no range event for keep the timer running, so a state without such a unit costs nothing while idle instead of waking up every 0.75 to 2 seconds.",
                    },
                },
            },
        },
        {
            version = "6.1-Beta3",
            date = "2026-08-19",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Boss frames no longer freeze at the range fade they happened to have when the pull started. Boss units have no range event of their own, so the periodic check behind *Enable Range Fade* now keeps running in combat instead of stopping at the encounter start.",
                            link = {
                                pageKey = "uf_boss",
                                query = "enable range fade",
                                label = "Enable Range Fade",
                                sectionId = "range_fade",
                                controlId = "menu2.uf_boss.unit.range_fade.enabled",
                                settingKey = "boss.rangeFadeEnabled",
                            },
                        },
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed a spell indicator's health-bar highlight covering the player name and the aura icons on live Group Frames, while the menu preview drew the same effect correctly underneath (#123). The effect rode along whenever its native aura container was re-levelled, so opening the settings or changing zone could flip the order either way; it now keeps the Layer it was configured with.",
                        "Full-Frame effect previews in the Group preview and in Edit Mode now paint through the same renderer the frames use, so Glow shows its real halo instead of four flat edges and Pulse animates with its live opacity.",
                    },
                },
            },
        },
        {
            version = "6.1-Beta2",
            date = "2026-08-18",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Added a Power width slider to the Class Resources > Player Power card, where Width mode \"Manual\" previously had no width to set. Dragging it releases *Sync width to Class Resource*, because that sync outranks an explicit width.",
                            link = {
                                pageKey = "classpower",
                                query = "power width",
                                label = "Power width",
                                sectionId = "classpower_detached_power",
                                controlId = "menu2.classpower.advanced.detached.power.layout.width",
                                settingKey = "player.detachedPowerBarWidth",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Switching the Active profile now offers a UI reload: frames re-apply at once, but settings that are only read at load time otherwise keep the old profile's values until the next reload.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Colour changes on the Colors page now repaint the Resources strip in the preview immediately instead of leaving it on the previous colours until the tab was rebuilt.",
                        "Changing a spell indicator's Display as shape now re-gates that section right away; controls belonging to the previous shape, such as Icon Effect, could stay visible until an unrelated click refreshed the page.",
                    },
                },
            },
        },
        {
            version = "6.1-Beta1",
            date = "2026-08-18",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Separated the Augmentation Evoker resources: Ebon Might now renders on the Player power bar, Essence is an ordinary Class Resource, and Mana moves to Alternative Mana. The Ebon Might bar takes its height, position, texture, background, border and text from the Player Power settings; only its fill colour still comes from the Ebon Might colour entry.",
                            link = {
                                pageKey = "classpower",
                                query = "ebon might",
                                label = "Ebon Might",
                                sectionId = "classpower_behavior",
                                controlId = "menu2.classpower.advanced.behavior.ebon",
                                settingKey = "bars.showEbonMight",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Class Resource width, offsets, pixel snapping and cooldown anchoring finally apply to an Augmentation Evoker's Essence bar; it used to silently copy the power bar's width and anchor and ignore those settings.",
                        "Turning the Player Power bar off now also turns off the Ebon Might display instead of leaving an empty bar behind.",
                        "Ebon Might's bar and duration text follow live setting changes instead of freezing at the values they had when the native aura slot was first created.",
                        "The group preview LAYERS chips now apply to the preview frames drawn on screen as well as to the preview box in the menu, and Shift-click solo shows only that one element on them.",
                        "Cooldown and stack numbers on the preview's aura icons follow the CD/Stack chip, and the chip is greyed out when no enabled aura lane prints a timer or stack count.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed a raid frame block not staying where it was placed in Edit Mode: the saved position was converted between two internal formats with mismatched roster counts and drifted by up to 162 pixels, and a click that never moved could permanently lock the conversion out.",
                        "Long castbar spell names are now shortened with a visible ellipsis that respects the bar width instead of being clipped by the renderer at an unpredictable spot; a name could previously disappear completely even when it was shorter than the configured limit.",
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
