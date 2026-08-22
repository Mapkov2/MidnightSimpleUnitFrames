-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "6D981891C5FDC0B1D75A21CF0E1B7F0207E58C354A91C131EDBADA6FDC0B7175",
    currentVersion = "6.11",
    historyFromVersion = "6.08",
    previousVersion = "6.08",
    rangeLabel = "6.08 -> 6.11",
    entries = {
        {
            version = "6.11",
            date = "2026-08-21",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Expanded Buff Tracking is back for Custom 1-3 aura containers. Every whitelisted spell keeps a fixed slot, missing buffs show as dimmed placeholders, and the same slots can securely cast spells or use bound items when clicked.",
                            link = {
                                pageKey = "uf_player",
                                query = "buff reminder fixed slots",
                                label = "Buff Reminder",
                                sectionId = "auras",
                                controlId = "menu2.uf_player.auras.unit-workspace.container-selector",
                                settingKey = "auras3.player.custom1.placed.reminderEnabled",
                                prepareKind = "unitAuraWorkspace",
                                prepareValue = "custom1_reminder",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Buff Reminder accepts Spell IDs, spell links, item links, and separate tracked-spell/item-action pairs. Player reminders can also track Main Hand and Off Hand temporary enchants, filter out spells the current character cannot apply, and pin shared consumables with Always show.",
                        "Main Hand and Off Hand enchant reminders now show their remaining time and a shaped cooldown swipe. A configurable 5-240 minute duration keeps the swipe proportional after login or reload, while the native duration binding updates without polling.",
                        "Reminder slots follow whitelist order, preserve their positions as auras appear or expire, and keep their secure click bindings fixed outside combat without polling or recurring aura reads.",
                        "Localized the complete Buff Reminder setup, whitelist actions, weapon-enchant controls, status text, and tooltips across all 12 supported locales.",
                        "The Assistant can now execute explicit multi-control requests clause by clause, including comma-separated and shared-scope commands, while continuing to fail closed for questions, planning requests, incomplete values, and ambiguous fragments.",
                        "Menu pages, accordion sections, and Back/Forward navigation now switch immediately without transition fades or a recurring discovery pulse.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Friendly Target Range Fade becoming inaccurate in instanced combat when Blizzard temporarily stops returning a fresh range result. MSUF now keeps the last authoritative result until a native range event or a real target change supplies a replacement, without adding polling, timers, or an open-world fallback path.",
                        "Castbars reuse unchanged manager topology and boss-frame geometry validation, resolve cast activity once per update, and share the player's plain interrupt-cooldown status across same-frame Target, Focus, and Boss refreshes.",
                        "Player-first role-sorted Party Frames now wait for a complete Arena roster before publishing their secure name list and refresh on Arena match-state and unit-name transitions; the additional listeners remain disabled in PvE.",
                        "The Assistant no longer mistakes player-count ranges inside Group Frame scale labels (such as 1-10 Players) for a requested value when none was supplied.",
                        "Fixed Elemental Shamans seeing Maelstrom on both resource bars. While Maelstrom owns the Class Resource row, the Player power bar now consistently displays Mana across fill, current value, maximum, percentage, text color, and event filtering; disabling that row or entering a vehicle restores the primary resource.",
                        "Applied the same resource-ownership transition to Shadow Priest Mana/Insanity and cleared both overrides when the Class Resource module shuts down.",
                        "Made third-party cooldown-viewer and external-frame anchoring safe when 12.1 returns protected geometry. MSUF validates foreign frames once, shares one stable proxy between Unit Frames, and freezes that proxy at the combat edge instead of repeatedly touching every consumer.",
                        "Boss castbars now prewarm at most one hidden bar per rendered frame when an encounter starts, avoiding one large synchronous layout burst while retaining authoritative validation when a real cast begins.",
                        "Aura-name fallback scans are coalesced to one frame and permanently retire each resolved alias until the container configuration changes, removing repeated name lookups from unrelated full aura updates.",
                        "Aura menu search now opens the Filters tool correctly for Player Defensives and Target Dots instead of falling back to Setup.",
                        "Rounded Unit Frames no longer read the protected parent of Blizzard-owned dispel-overlay textures; the safe owner is captured before the region becomes forbidden and reused when masks are applied.",
                        "Group Frame previews keep their generated character names when ordinary player-unit events refresh the dummy frames outside Edit Mode.",
                    },
                },
            },
        },
        {
            version = "6.1",
            date = "2026-08-19",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "The Raid Group indicator now has its own Size slider in Status icons, on every frame that can show it. It used to render at the frame's name font size with no way to change it; an untouched profile keeps that size, so nothing moves until you drag the slider.",
                            link = {
                                pageKey = "uf_player",
                                query = "raid group size",
                                label = "Size",
                                sectionId = "status_icons",
                                controlId = "menu2.uf_player.unit.status.selected.size",
                                settingKey = "player.raidGroupNameSize",
                                prepareKind = "unitStatus",
                                prepareValue = "raidgroupname",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Separated the Augmentation Evoker resources: Ebon Might now renders on the Player power bar, Essence is an ordinary Class Resource, and Mana moves to Alternative Mana. The Ebon Might bar takes its height, position, texture, background, border and text from the Player Power settings; only its fill colour still comes from the Ebon Might colour entry.",
                        "Class Resource width, offsets, pixel snapping and cooldown anchoring finally apply to an Augmentation Evoker's Essence bar; it used to silently copy the power bar's width and anchor and ignore those settings.",
                        "Turning the Player Power bar off now also turns off the Ebon Might display instead of leaving an empty bar behind.",
                        "Ebon Might's bar and duration text follow live setting changes instead of freezing at the values they had when the native aura slot was first created.",
                        "Added a Power width slider to the Class Resources > Player Power card, where Width mode \"Manual\" previously had no width to set. Dragging it releases *Sync width to Class Resource*, because that sync outranks an explicit width.",
                        "Switching the Active profile now offers a UI reload: frames re-apply at once, but settings that are only read at load time otherwise keep the old profile's values until the next reload.",
                        "The group preview LAYERS chips now apply to the preview frames drawn on screen as well as to the preview box in the menu, and Shift-click solo shows only that one element on them.",
                        "Cooldown and stack numbers on the preview's aura icons follow the CD/Stack chip, and the chip is greyed out when no enabled aura lane prints a timer or stack count.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Power text on the Target, Focus, Pet and Boss frames follows the unit you are actually on again. With *Colour power text by type* enabled the colour was resolved once and then kept across every target change, so a Focus or Rage target could stay on the previous target's colour, or sit on Mana blue for the rest of the session (#125). Frames with the power bar switched off were affected the most, because they had no bar to take fresh resource data from.",
                        "Power text no longer falls back to the Mana colour when a unit reports no resource at all. It renders the configured text colour instead, which is what those slots show with colour by power type switched off.",
                        "Boss frames no longer freeze at the range fade they happened to have when the pull started. Boss units have no range event of their own, so the periodic check behind *Enable Range Fade* now keeps running in combat instead of stopping at the encounter start.",
                        "The range fade check now retires completely once nothing is left to sample. Only units MSUF has no range event for keep the timer running, so a state without such a unit costs nothing while idle instead of waking up every 0.75 to 2 seconds.",
                        "The Assistant can see and set the Power width slider again. Its generated control schema had not been rebuilt since the slider landed, so the one control added this cycle was missing from everything the Assistant can reach by name.",
                        "The Assistant can now drive the Active auras on this frame dropdown in the blacklist workspace. It was the only control in that section it could not see, so a live scan could be started and blocked by hand but not by request.",
                        "Aura name resolution compiles its alias list once per container instead of rebuilding an iterator on every event, which is the hot path whenever the client falls back to a full aura update in a raid.",
                        "The over-absorb glow decides once per render pass whether the absorb value is protected, instead of re-checking it at every branch that writes to the bar.",
                        "Fixed a spell indicator's health-bar highlight covering the player name and the aura icons on live Group Frames, while the menu preview drew the same effect correctly underneath (#123). The effect rode along whenever its native aura container was re-levelled, so opening the settings or changing zone could flip the order either way; it now keeps the Layer it was configured with.",
                        "Full-Frame effect previews in the Group preview and in Edit Mode now paint through the same renderer the frames use, so Glow shows its real halo instead of four flat edges and Pulse animates with its live opacity.",
                        "Changing a spell indicator's Display as shape now re-gates that section right away; controls belonging to the previous shape, such as Icon Effect, could stay visible until an unrelated click refreshed the page.",
                        "Colour changes on the Colors page now repaint the Resources strip in the preview immediately instead of leaving it on the previous colours until the tab was rebuilt.",
                        "Fixed a raid frame block not staying where it was placed in Edit Mode: the saved position was converted between two internal formats with mismatched roster counts and drifted by up to 162 pixels, and a click that never moved could permanently lock the conversion out.",
                        "Long castbar spell names are now shortened with a visible ellipsis that respects the bar width instead of being clipped by the renderer at an unpredictable spot (#121); a 23-character name could previously disappear completely under a 25-character limit, because the client cuts a bounded line at a glyph-dependent position.",
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
        {
            version = "6.09",
            date = "2026-08-17",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Added dynamic Custom Priority ordering for Dots on target and Custom 1-3 aura containers, keeping the configured spell order compact and stable as tracked auras appear or expire.",
                            link = {
                                pageKey = "uf_target",
                                query = "dots on target custom priority",
                                label = "Custom Priority",
                                sectionId = "auras",
                                controlId = "menu2.uf_target.auras.unit-workspace.container-selector",
                                settingKey = "auras3.target.custom4.placed.sortMethod",
                                prepareKind = "unitAuraWorkspace",
                                prepareValue = "custom4_behavior",
                            },
                        },
                        {
                            text = "Added a combat aura scanner to the Unitframe blacklist workspace: one click closes the menu, keeps capturing every blockable aura with its icon until combat ends, then reopens the menu with the collected list, ready to block.",
                            link = {
                                pageKey = "uf_target",
                                query = "target debuff blacklist",
                                label = "Combat scan",
                                sectionId = "auras",
                                controlId = "menu2.uf_target.auras.unit-workspace.container-selector",
                                settingKey = "auras3.target.debuff.blacklist.hidePermanent",
                                prepareKind = "unitAuraWorkspace",
                                prepareValue = "debuff_blacklist",
                            },
                        },
                        {
                            text = "Manual blacklist entries are now verified by Spell ID against the live unit: when your cast's ID differs from the aura's actual ID, MSUF warns and offers to block the real aura ID instead.",
                            link = {
                                pageKey = "uf_target",
                                query = "target debuff blacklist",
                                label = "Blacklist",
                                sectionId = "auras",
                                controlId = "menu2.uf_target.auras.unit-workspace.container-selector",
                                settingKey = "auras3.target.debuff.blacklist.hidePermanent",
                                prepareKind = "unitAuraWorkspace",
                                prepareValue = "debuff_blacklist",
                            },
                        },
                        {
                            text = "Added an optional Show spell IDs in aura tooltips toggle that keeps the native 12.1 tooltip option enabled across logins.",
                            link = {
                                pageKey = "opt_misc",
                                query = "spell ids",
                                label = "Aura tooltip spell IDs",
                                sectionId = "misc_tooltips",
                                controlId = "menu2.opt.misc.global.setting.tooltip.show.aura.spell.ids",
                                settingKey = "general.tooltipShowAuraSpellIDs",
                            },
                        },
                        {
                            text = "Added an optional Boss Number status indicator so boss frames can show their encounter index directly on the frame.",
                            link = {
                                pageKey = "uf_boss",
                                query = "boss number",
                                label = "Boss Number",
                                sectionId = "status_icons",
                                controlId = "menu2.uf_boss.unit.status.selected.enabled",
                                settingKey = "boss.showBossNumberIndicator",
                                prepareKind = "unitStatus",
                                prepareValue = "bossNumber",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Moved aura ordering out of Style into dedicated, scope-aware Ordering workspaces for Unit Frames, Group Frames, custom aura containers, and external defensives, with draggable priority rows that snap to their new slot.",
                        "Added a live Active auras on this frame dropdown to the blacklist with one-click blocking, a Rescan button, and a session capture list; scans run only on click.",
                        "Extended the Maximum duration filter to every aura lane on unit and group frames, including Buffs, Tracked Buffs, and External Defensives.",
                        "Reworked pandemic-window Full-Frame effects for tracked DoTs to bind to the visible aura buttons themselves, including portrait mode.",
                        "Replaced Aura list scrollbars with the consistent MSUF scrollbar style and exposed Ordering options directly without a redundant accordion.",
                        "Added Blizzard's NEW badge to the See New Features button, shown until the bundled release notes have been opened.",
                        "Added Deathstalker's Mark for Rogues and Atmospheric Exposure for Druids to the tracked target-effect presets, and corrected the Balance Druid presets for Moonfire (164812), Sunfire (164815), and Atmospheric Exposure (430589).",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed the combat timer not being movable while its position was unlocked.",
                        "Added a tooltip to the combat timer's Lock position toggle explaining how positioning works.",
                        "Fixed the Combat Enter/Leave text vanishing after every combat transition while unlocked; it now stays visible as its movable handle.",
                        "Fixed gameplay mover offsets drifting when the moved element was anchored to a scaled frame, and dragging a mover now repaints its X/Y sliders live.",
                        "Scanning respects Blizzard's instanced-content restrictions: encounter, Mythic+, and PvP lockdowns show a clear notice pointing to the curated presets and resume automatically instead of erroring.",
                        "Scan results state how many auras Blizzard hides as secret; hidden auras cannot be identified or blocked by any addon, so everything blockable is always captured.",
                        "Fixed Edit Mode arrow-key nudging for Custom 1-4 aura containers, including shared boss-frame positioning.",
                        "Fixed Spell Indicator controls from an inactive display type remaining visible after selection or preview changes.",
                        "Kept Custom Priority ordering and blacklist scanning fully event- and click-driven: no polling, no recurring OnUpdate work, and nothing added to combat hotpaths.",
                    },
                },
            },
        },
        {
            version = "6.08",
            date = "2026-08-16",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Added optional profile-wide custom colors for Magic, Curse, Disease, Poison, and Bleed across Unit and Group Frame dispel visuals while preserving Blizzard's native defaults whenever no override is enabled.",
                            link = {
                                pageKey = "opt_colors",
                                query = "magic dispel color",
                                label = "Magic color",
                                sectionId = "colors_auras",
                                controlId = "menu2.opt.colors.advanced.auras.dispel.magic.color",
                                settingKey = "general.dispelTypeColorOverrides.Magic",
                            },
                        },
                        {
                            text = "Added an optional, class-colored interrupter name beside the castbar's interrupted state.",
                            link = {
                                pageKey = "uf_target",
                                query = "show interrupter name",
                                label = "Show interrupter name",
                                sectionId = "castbar",
                                controlId = "menu2.uf_target.unit.castbar.show_interrupt_source",
                                settingKey = "target.showInterruptSource",
                                prepareKind = "unitCastbarTab",
                                prepareValue = "general",
                            },
                        },
                        {
                            text = "Added configurable AFK timers to Unit and Group Frame status text.",
                            link = {
                                pageKey = "uf_player",
                                query = "afk timer",
                                label = "AFK Timer",
                                sectionId = "status_icons",
                                controlId = "menu2.uf_player.unit.status.selected.enabled",
                                settingKey = "player.statusAFKTimerEnabled",
                                prepareKind = "unitStatus",
                                prepareValue = "statusAFKTimer",
                            },
                        },
                        {
                            text = "Added an optional Player Frame Stance text indicator for warrior stances, paladin auras, druid forms, and other native stance-bar forms.",
                            link = {
                                pageKey = "uf_player",
                                query = "stance",
                                label = "Stance",
                                sectionId = "status_icons",
                                controlId = "menu2.uf_player.unit.status.selected.enabled",
                                settingKey = "player.showStanceIndicator",
                                prepareKind = "unitStatus",
                                prepareValue = "stance",
                            },
                        },
                        {
                            text = "Added explicit Uniform and Width & height portrait sizing modes for Unit and Group Frames while preserving existing portrait geometry during migration.",
                            link = {
                                pageKey = "uf_player",
                                query = "portrait size mode",
                                label = "Size mode",
                                sectionId = "portrait",
                                controlId = "menu2.uf_player.unit.portrait.portraitsizemode",
                                settingKey = "player.portraitSizeMode",
                                prepareKind = "unitPortraitTab",
                                prepareValue = "geometry",
                            },
                        },
                        {
                            text = "Added configurable edge softness for circular, rounded, and diamond portraits, with matching Unit Frame, Group Frame, and preview rendering.",
                            link = {
                                pageKey = "uf_player",
                                query = "portrait edge softness",
                                label = "Portrait edge softness",
                                sectionId = "portrait",
                                controlId = "menu2.uf_player.unit.portrait.portraitedgesoftness",
                                settingKey = "player.portraitEdgeSoftness",
                                prepareKind = "unitPortraitTab",
                                prepareValue = "border",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added an optional Slug font rendering mode for clearer, more consistent text across Unit Frames, Group Frames, Castbars, Class Resources, and other MSUF text.",
                        "Applied custom Dispel colors consistently to Unit Dispel Overlays, Group Dispel Overlays, Dispel Highlight Borders, MSUF Dispel symbols, Edit Mode, and every matching Menu preview.",
                        "Added ::: color shortcuts to Unit Dispel Overlay, Group Dispel Overlay, and Highlight Borders for direct access to the matching global Dispel colors.",
                        "Kept original Blizzard and MSUF Dispel artwork for default colors; tint-neutral MSUF symbol assets are selected only for Dispel types with an active custom override.",
                        "Replaced the toolbar's New Task action with a dedicated See New Features changelog page. Highlighted feature sentences now link directly to their exact MSUF Menu controls and subcategories.",
                        "Localized the new Dispel colors, AFK timer, stance, portrait sizing, portrait edge-softness, and related controls across all 12 supported locales.",
                        "Updated Assistant registrations, profile behavior, copy/reset handling, search routing, generated coverage data, and static search data for the new controls.",
                        "Added daily GitHub synchronization from Retail main to the Classic repository, clearer sync-failure reporting, and required versioned Classic validation.",
                        "Added manual release-channel recovery support to the GitHub release workflow.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Updated Spell Indicator filters in place through Blizzard's public AuraSlot setter, avoiding unnecessary restricted AuraButton and container rebuilds when only a friendly/hostile filter changes.",
                        "Fixed custom MSUF Dispel symbols becoming black or incorrectly multiplied after recoloring. Custom overrides now use tint-neutral, alpha-identical companions, while unchanged colors continue using the original assets.",
                        "Fixed Group Frame absorb overlays ignoring the configured opacity.",
                        "Fixed aura icon zoom scaling when a Debuff border is active, including runtime and preview rendering.",
                        "Fixed the Castbar General tab height after adding the interrupter-name option.",
                        "Changed Target and Focus castbar identity refreshes from deferred callbacks to direct synchronous updates.",
                        "Cleared the castbar driver's unused OnUpdate script once during construction instead of repeating the native transition on target swaps.",
                        "Fixed player Unit Frames showing the fallback blue or another incorrect health color for identity-restricted PvP targets by routing every player class through Blizzard's native secret-safe class-color pipeline.",
                        "Fixed restricted Race and Class status text showing a unit name or blank value by using Blizzard's stable identity return directly when localized identity text is protected.",
                        "Streamlined Unit Frame identity refreshes across bars, portraits, status text, regular text, and range fading so unchanged identity state avoids redundant work.",
                        "Skipped player-only nickname-provider APIs for NPC units while retaining supported NPC nickname sources.",
                        "Fixed Arena Group Frames using Raid instead of Party configuration across runtime, Blizzard-frame ownership, Edit Mode, and previews.",
                        "Fixed exact-ID aura indicators mixing friendly and hostile filters after switching targets.",
                        "Limited PvP indicator runtime to Arenas, Battlegrounds, and War Mode, removing unrelated faction and PvP-timer event traffic outside those modes.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
