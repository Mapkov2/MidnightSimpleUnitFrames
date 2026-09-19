-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "938B3C9993753D79EA39E95B1716895A279BB30ED502DF7A87FCA69364302941",
    currentVersion = "6.5-beta5",
    historyFromVersion = "6.5-beta2",
    previousVersion = "6.5-beta4",
    rangeLabel = "6.5-beta4 -> 6.5-beta5",
    entries = {
        {
            version = "6.5-beta5",
            date = "2026-09-19",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "See your aggro as a percentage. Classic Era, TBC and WoW Forever can show Threat % on supported Target, Focus and Boss frames, with 100% meaning you have aggro. Open the Target's Threat % status to adjust its placement, size, background and threat coloring.",
                            link = {
                                pageKey = "uf_target",
                                query = "threat percent",
                                label = "Target Threat %",
                                sectionId = "status_icons",
                                controlId = "menu2.uf_target.unit.status.selected.size",
                                settingKey = "target.threatIndicatorSize",
                                prepareKind = "unitStatus",
                                prepareValue = "statusThreat",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Party and Raid frames can show each member's threat percentage against your current target on Classic Era, TBC and WoW Forever. Party threat text starts enabled; Raid threat text is opt-in.",
                        "Threat text can follow a configurable low, medium and high threat color curve. Adjust the colors under Appearance > Colors > Status Text Colors or through the Threat % status editor.",
                        "Updated the shared factory profile, including Slug font rendering, Focus and Target-of-Target placement, Pet transparency and Party threat text. Fresh installs, new profiles and profile resets use the new baseline.",
                        "Consolidated target-based combo point handling across Classic clients and WoW Forever.",
                        "Menu search now filters client-specific controls by availability, including Pet Happiness and Threat %.",
                        "Section Copy To lists only supported frames and marks disabled frames as unavailable destinations.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "WoW Forever: added a temporary workaround for the client bug that prevented secure group-frame setup and made Party, Raid and Priority frames disappear when joining a group.",
                        "Classic clients: repaired untouched sparse factory aura layouts from 6.5-alpha18 through beta3 while preserving customized aura owners.",
                        "Classic clients: the cleanse border now respects the Friendly, Enemy and Both display conditions selected under Bars.",
                        "Classic clients: Buff/Debuff lanes and custom containers now use the same sorting and Hide permanent rules.",
                        "Classic clients: group-frame auras refresh when a roster change assigns a different member to the same party or raid slot.",
                        "Classic clients: hid the unsupported Pandemic-only effect option and corrected client-specific menu search entries.",
                        "Classic previews now show the power gradient and class-resource text layer correctly; Mists Boss previews also show the boss-target marker.",
                        "Corrected analytics initialization writing to an unintended global instead of the account-wide settings table.",
                        "Cooldown Manager anchoring now checks whether the client actually supports the manager before offering or applying the anchor.",
                        "Strengthened client startup checks, menu-index validation and beta release packaging.",
                    },
                },
            },
        },
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
