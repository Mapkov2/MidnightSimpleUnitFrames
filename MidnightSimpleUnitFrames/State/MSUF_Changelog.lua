-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "2A74E840A64861D05520BDF0DFEA1433DD1FCD41B1B3D517096E5D72F3AC448F",
    currentVersion = "6.5-beta8",
    historyFromVersion = "6.5-beta5",
    previousVersion = "6.5-beta7",
    rangeLabel = "6.5-beta7 -> 6.5-beta8",
    entries = {
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
