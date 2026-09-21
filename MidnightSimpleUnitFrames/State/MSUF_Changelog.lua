-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "B0EAF90509C01D2072384D3908334D36CF82153663D18B969F7FEAE6FD1E21A9",
    currentVersion = "6.5-beta7",
    historyFromVersion = "6.5-beta4",
    previousVersion = "6.5-beta6",
    rangeLabel = "6.5-beta6 -> 6.5-beta7",
    entries = {
        {
            version = "6.5-beta7",
            date = "2026-09-21",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Give the level text a round badge with a gold rim. Enable Round level badge under Status > Level; its position, size and layer follow the existing level controls, with native artwork or a bundled fallback for older clients.",
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
                            text = "Add Blizzard's bottom-right gold connector to a Blizzard-style portrait. The new Portrait > Border option is reflected in the live frame and menu preview.",
                            link = {
                                pageKey = "uf_player",
                                query = "bottom-right gold connector",
                                label = "Bottom-right gold connector",
                                sectionId = "portrait",
                                controlId = "menu2.uf_player.unit.portrait.portraitblizzardcorner",
                                settingKey = "player.portraitBlizzardCorner",
                                prepareKind = "unitPortraitTab",
                                prepareValue = "border",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Export and import individual unitframes. Profiles > Import & Export now offers Selected unitframes, with a separate multi-selection for Player, Target, Target of Target, Pet, Focus, Focus Target, Boss and Arena where supported by the client.",
                        "Selected-frame strings carry each included frame's own settings, aura configuration and castbar. Imports update only those frames in the current profile or a new profile, preserving other frames and shared settings. Settings inherited from a shared appearance continue to use the receiving profile's appearance.",
                        "Empty selections and imports containing unsupported frames or settings outside their selected frames are rejected. Existing full-profile and category exports retain their previous behavior.",
                        "Texture-layer profiles can use native Blizzard atlases. Runtime rendering and menu previews preserve the atlas crop and fall back to the ordinary texture source if the atlas is unavailable.",
                        "Portrait profiles that already use complete Blizzard frame artwork can suppress the duplicate standalone portrait rim while retaining the corner connector.",
                        "Leader, assistant and combat indicators use the matching native artwork when available, with texture fallbacks on older clients. The status and portrait previews follow the same artwork choices.",
                        "Section Copy To includes the new portrait connector, standalone-ring choice, level badge and texture-layer atlas settings.",
                    },
                },
                {
                    title = "Fixes",
                    bullets = {
                        "Turning off the level indicator also hides the fallback badge ring; a leftover gold circle no longer remains behind.",
                        "Selected-frame aura imports avoid full-profile aura resets, and default repair runs on a private copy before committing the selected settings.",
                    },
                },
            },
        },
        {
            version = "6.5-beta6",
            date = "2026-09-20",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Blizzard-style portraits can display elite and rare dragons. Enable the new option under Portrait > Border; the menu preview shows the matching decoration.",
                            link = {
                                pageKey = "uf_target",
                                query = "elite and rare dragon",
                                label = "Elite and rare dragon",
                                sectionId = "portrait",
                                controlId = "menu2.uf_target.unit.portrait.portraitblizzardelite",
                                settingKey = "target.portraitBlizzardElite",
                                prepareKind = "unitPortraitTab",
                                prepareValue = "border",
                            },
                        },
                        {
                            text = "Choose Classic Glass or Midnight as your menu appearance on every supported client. Classic Glass has a refined palette and clearer panels, while existing appearance choices are preserved.",
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
                    title = "Changes",
                    bullets = {
                        "Portrait > Border now offers a temporary Runtime Preview for elite, rare and boss dragons on the live portrait. Closing the section or entering combat restores the real classification.",
                        "Updated the shared factory profile and the Classic/Forever defaults, including clearer power bars, separated Alternative Mana placement, a compact raid layout, and revised text and aura positions.",
                        "Class Resources using Player frame width now span the full Player frame.",
                        "Consolidated shared client handling, defaults, Class Resources and preview behavior across the supported clients.",
                        "Refreshed Assistant bindings and menu catalog tooling, and expanded client, locale and release validation.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Classic and WoW Forever group members without an assigned role retain their power bar when power is enabled for any role; explicit role filters still apply.",
                        "Corrected Blizzard-style portrait rim and mask alignment, foreground opacity and layer behavior, and portrait zoom after native refreshes.",
                        "Fixed Classic aura filtering and faction handling, Class Resource refreshes and previews, font previews, and several default-setting inconsistencies.",
                        "Reused completed pixel-layout setup to avoid repeated work while keeping deferred combat updates available.",
                    },
                },
            },
        },
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
