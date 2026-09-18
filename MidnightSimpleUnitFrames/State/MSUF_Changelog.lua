-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "3908B003740C7666E33A7C1EB64F61D7A6CEBE49741759DD197C81E72E08EE14",
    currentVersion = "6.5-beta4",
    historyFromVersion = "6.5-alpha18",
    previousVersion = "6.5-beta3",
    rangeLabel = "6.5-beta3 -> 6.5-beta4",
    entries = {
        {
            version = "6.5-beta4",
            date = "2026-09-19",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "The level text is colored by how hard a unit is for you. Red far above your level and for \"??\", orange above, white at your level, green below and gray when trivial. Every frame that shows a level starts with it, and the five colors are yours to change in Appearance > Colors > Status Text Colors.",
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
                            text = "Mobs another player tagged first are grayed out, as on Blizzard's target frame. The name always turns gray and the health bar follows wherever its color carries meaning.",
                            link = {
                                pageKey = "opt_colors",
                                query = "gray out mobs tagged by others",
                                label = "Gray out mobs tagged by others",
                                sectionId = "colors_unit",
                                controlId = "menu2.opt.colors.advanced.npc.tap.denied.gray",
                                settingKey = "general.tapDeniedGray",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "A frame keeps its own level text color if it already had one; the difficulty colors are switched per frame under Status icons > Level Text.",
                        "Party and Raid frames can show their own level text, off by default, with the same difficulty coloring.",
                        "Classic clients offer \"No target\" and \"Out of combat and no target\" as load conditions. Both were already implemented but missing from the list.",
                        "Classic Era reads channel tick markers from its own spell data, one entry per rank, as WoW Forever already did. Channels up to fifteen ticks are marked; TBC and Mists keep the previous table until their spell data is verified.",
                        "WoW Forever hides the Empowered Casts castbar section. It is an Evoker mechanic and Forever has nine classes.",
                        "Blizzard's AddOn list shows the version of the client you are on, because each shared manifest now carries one version line per game type.",
                        "The pet indicator is called \"Pet Happiness\" again. The \"(Vanilla/TBC)\" suffix was wrong once WoW Forever gained it.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "The Classic add-on titles showed a stray \"b\" in Blizzard's AddOn list. A color code carried nine digits instead of eight, so the ninth was printed.",
                        "WoW Forever: the welcome screen and the \"what's new\" tour no longer return on every login. That client still drops its SavedVariables between sessions, which read as a fresh install each time.",
                        "Classic clients: setting the player power bar to Mana had no effect, and the separate Alternative Mana bar was drawn on top of the untouched class resource.",
                        "Classic clients: a class without a mana pool no longer receives an Alternative Mana bar from a profile shared with a mana class.",
                        "Classic clients: class resources refresh after death and resurrect again. Every bar that is not aura-segmented ran the wrong update.",
                        "Classic clients: a shaped aura icon could paint its dispel border in the Magic blue of the menu sample instead of the debuff's own color.",
                        "Classic clients: an aura filtered out of a lane could never reappear, and a failed aura update now forces a full rescan instead of leaving half-merged icons.",
                        "Classic clients: the preview's Layers dropdown kept its chips inside the panel again.",
                        "Classic clients: Copy To carries the mouseover text settings, the clickable portrait, chunked fill and \"exclude prediction bars from transparency\".",
                        "Deleting a profile moves its characters to \"Default\", or to the alphabetically first profile when none exists. The target used to depend on table order.",
                        "Importing a profile validates its fonts through the font registry again. The check called a function that no longer existed.",
                        "TBC and Mists: castbar width matching and the arena portrait preview cover all five arena frames. Both stopped at three.",
                        "TBC and Mists: arena castbars keep their own event frame when the shared event bus declines a subscription, instead of silently missing opponent and match-state updates, and all three text regions drop their font cache after a font change.",
                        "Arena frames re-read their power text when a slot binds to a different opponent, which happens every Solo Shuffle round.",
                        "Mists: the arena trinket fallback listens to the combat log only inside an arena instance. It stayed subscribed everywhere, including raids.",
                        "Auras re-sort only in the modes keyed to time, and only when a duration or expiration actually moved. Every other sort order rebuilt the whole lane on each aura refresh.",
                        "Aura icon layout and the shaped dispel border are re-applied only when something they depend on changed.",
                        "Arena castbars validate their geometry once per style change instead of before every cast.",
                        "A client MSUF cannot identify no longer offers arena frames it has no slots for, and a Mainline client without the WoW Forever marker prints one login line asking for /msuf clientinfo.",
                        "Releases carry the WoW Forever game version on CurseForge by themselves and are also published to Wago.",
                    },
                },
            },
        },
        {
            version = "6.5-beta3",
            date = "2026-09-18",
            sections = {
                {
                    title = "Changes",
                    bullets = {
                        "New factory default profile on every client. First login, \"Reset profile\" and \"New profile\" all start from it.",
                        "Factory castbars fill left to right. Existing profiles keep their direction.",
                        "The factory cleanse border detects \"Dispellable by group\" instead of every debuff with a dispel type.",
                        "Factory target buffs and debuffs sit on the same line; player and target aura positions follow the new profile.",
                        "WoW Forever: hunter pet happiness shows on the pet frame.",
                        "WoW Forever: Fonts page option to show the full character name, the first name or the surname.",
                        "WoW Forever: group frames offer Party and Raid only.",
                        "MSUF versions are now per game client. WoW Forever and the Classic clients report 6.5; Midnight keeps its own Retail version. /msuf clientinfo prints the running version.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "First login and \"Reset profile\" received the code defaults instead of the factory profile. Both start from the factory profile again, including Focus Target.",
                        "The class resource bar in the Unit Frames preview and the Class Resources preview sits where the live bar sits. It was drawn the bar height plus 6 px too high.",
                        "WoW Forever: the menu preview backgrounds (Silvermoon and the stone scenes) no longer stay black. Other clients fall back the same way when a scene fails to load.",
                        "The addon version is read once at load instead of on every version display, version check and analytics pass.",
                    },
                },
            },
        },
        {
            version = "6.5-beta2",
            date = "2026-09-18",
            sections = {
                {
                    title = "Changes",
                    bullets = {
                        "WoW Forever hour-0 support: Mainline family, camelot detection, Interface 16001, no arena, and the Classic Glass menu only on Forever.",
                        "Detects WoW Forever from the Blizzard_Game Camelot marker and keeps Family and Flavor Mainline.",
                        "/msuf clientinfo prints the client facts needed for Forever bug reports.",
                        "Factory profiles inflate deflate(CBOR) before DeserializeCBOR so Forever can create and import profiles.",
                        "TBC and Mists keep five Arena slots. Forever reports arena as unsupported.",
                        "The Classic Glass menu skin and \"MSUF (Forever Version)\" title show only on Forever.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Missing imported fonts fall back instead of aborting UI construction.",
                        "Profile import validates and stages the string before it creates or switches a profile.",
                        "Era dispel scans keep HARMFUL|RAID.",
                    },
                },
            },
        },
        {
            version = "6.5-alpha18",
            date = "2026-09-13",
            sections = {
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed options-menu and Edit Mode startup failures caused by fonts reporting incomplete values during client startup. Font readiness no longer aborts UI construction, and pending applications remain uncached until they are ready.",
                        "MSUF starts and applies profiles without optional integration addons installed. Classic clients no longer require unavailable EllesmereUI or Blizzard Edit Mode adapters.",
                        "Consolidated shared Defaults, ClassPower, aura-menu and preview helpers across Classic clients while preserving their class resources, pet happiness and Arena support.",
                        "Removed redundant protected calls and no-op substitutes so native Lua errors remain visible to BugSack/BugGrabber.",
                        "Corrected shared-helper load order and refreshed menu search indexes for Vanilla, TBC, Mists and Mainline.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
