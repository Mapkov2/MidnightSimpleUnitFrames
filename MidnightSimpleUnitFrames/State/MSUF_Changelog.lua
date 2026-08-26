-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "17546BBBA5AAED6C1F4DCCF61FEF0086E593E8F83834CF7C9B07A91780D8976B",
    currentVersion = "6.13-beta1",
    historyFromVersion = "6.1",
    previousVersion = "6.12",
    rangeLabel = "6.12 -> 6.13-beta1",
    entries = {
        {
            version = "6.13-beta1",
            date = "2026-08-26",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Range Fade now stays accurate in PvP instances. Group and Unit Frames re-query when the instance context changes, while unchanged polling sets avoid redundant rebuilds.",
                            link = {
                                pageKey = "uf_target",
                                query = "target range fade",
                                label = "Enable Range Fade",
                                sectionId = "range_fade",
                                controlId = "menu2.uf_target.unit.range_fade.enabled",
                                settingKey = "target.rangeFadeEnabled",
                            },
                        },
                        {
                            text = "Focus castbar trackers recover correctly after startup. Focus interrupt and cast ownership is restored when the underlying tracker becomes available after the initial load.",
                            link = {
                                pageKey = "opt_castbar",
                                query = "focus interrupt tracker",
                                label = "Focus interrupt tracker",
                                sectionId = "castbar_focus_kick",
                                controlId = "menu2.opt.castbar.global.focus.kick.enable.focus.kick.icon",
                                settingKey = "general.enableFocusKickIcon",
                            },
                        },
                        {
                            text = "Player Power text keeps the correct current resource identity. Current-value text no longer loses its power type when the live bar source has already been resolved.",
                            link = {
                                pageKey = "classpower",
                                query = "displayed resource",
                                label = "Displayed resource",
                                sectionId = "classpower_detached_power",
                                controlId = "menu2.classpower.advanced.detached.power.layout.resource.source",
                                settingKey = "player.playerPowerSource",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Expanded Assistant action inputs for enchant-related requests and tightened Aura action routing.",
                        "Exact setting guidance now outranks broader suggestions, while ambiguous control requests fail closed without changing settings.",
                        "Removed the experimental built-in Rogue APEX developer helper and its retired settings, menu controls, Assistant registrations, and generated metadata.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Party-style Arena Group Frames fail open when Blizzard's Arena roster is temporarily incomplete instead of publishing an unusable secure roster.",
                        "Aura-name fallback work is coalesced so repeated unresolved-name events do not trigger duplicate scans in the same frame.",
                        "Heal-prediction stripe updates use a specialized full-health path and avoid redundant overflow work.",
                        "Range drivers reuse unchanged poll sets and keep PvP instance transitions event-driven.",
                    },
                },
            },
        },
        {
            version = "6.12",
            date = "2026-08-23",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Boss Range Fade can now update up to 20 times per second. The new Boss update-rate slider keeps the adaptive standard cadence at zero or continuously checks visible Boss Frames from 1 through 20 updates per second.",
                            link = {
                                pageKey = "uf_boss",
                                query = "boss range update rate",
                                label = "Updates per second",
                                sectionId = "range_fade",
                                controlId = "menu2.uf_boss.unit.range_fade.update_rate",
                                settingKey = "boss.rangeFadeUpdateRate",
                            },
                        },
                        {
                            text = "Class Resources can now keep Player Power Automatic or explicitly display Mana. The new Displayed resource dropdown preserves the existing class/spec behavior in Automatic mode, while Mana keeps the Player power surface on its Mana pool whenever the character has one.",
                            link = {
                                pageKey = "classpower",
                                query = "mana automatic displayed resource",
                                label = "Displayed resource",
                                sectionId = "classpower_detached_power",
                                controlId = "menu2.classpower.advanced.detached.power.layout.resource.source",
                                settingKey = "player.playerPowerSource",
                            },
                        },
                        {
                            text = "Class Resource text can now show Current, Maximum, or Current / Maximum. The new Resource text selector keeps Automatic as the untouched resource-specific default, while explicit modes change only the central resource value.",
                            link = {
                                pageKey = "classpower",
                                query = "class resource text mode",
                                label = "Resource text",
                                sectionId = "classpower_visuals",
                                controlId = "menu2.classpower.advanced.style.text.mode",
                                settingKey = "bars.classPowerTextMode",
                            },
                        },
                        {
                            text = "MiniAuras and MiniCC now work with MSUF Party and Raid Frames again. The event-driven frame provider refreshes only when the authoritative Group Frame registry changes, without polling the roster or frame list.",
                            linkless = true,
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added Automatic, Current, Maximum, and Current / Maximum formats for the central Class Resource value. Rune timers, Ebon Might duration, and the Ironfur stack counter retain their native formats; previews and the Assistant mirror the selected mode.",
                        "The Player Power resource selector is shared between Player Power and Class Resources, follows vehicle-resource handoffs, and is supported by previews, reset/undo history, search, and the Assistant.",
                        "Preserve Raid Groups now creates a separate secure header for each physical raid subgroup, retaining empty subgroup geometry and the selected Index, Name, or Role sorting inside each group. Scanning, Edit Mode bounds, visibility, and runtime layout cover every active subgroup header.",
                        "Retired unused legacy Class Resource text-format fields from existing profiles and generated fallback metadata.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "One-icon aura lanes now use Blizzard's one-frame AuraSlot primitive instead of allocating a ten-frame AuraGroup pool; weapon-enchant and custom-priority lanes keep their specialized group behavior.",
                        "Aura identity-event topology changes are batched across secure Group Frame header scans, resolved aura-name registrations survive unchanged layout refreshes, and redundant native full-aura refreshes were removed.",
                        "Target name and health text now resolve protected PvP class tokens through Blizzard's native class-color object without comparing or caching secret-backed RGB values.",
                        "Standard Boss Range Fade retains its adaptive 0.75/2-second checks, while a custom rate accelerates only visible Boss Frames through the existing scheduler. Custom rates are visually distinguished and show a once-per-menu-session performance warning.",
                        "Boss encounter lifecycle bursts now coalesce Unit Frame identity, AuraContainer identity, and Range Fade reconciliation into next-frame refreshes instead of repeating synchronous work for every Boss token.",
                        "Group threat-role changes refresh only the affected border and corner-indicator domains, and Group Adapter header scans retain their standalone single-header fallback.",
                        "Rounded native dispel-overlay masks are fully configured before Blizzard takes ownership and are recreated through the cold Auras3 refresh path after rounded-frame setting or media changes.",
                        "The global Castbar preview canvas is taller so below-bar text, thick outlines, and vertical icon offsets are no longer clipped.",
                        "The GCD indicator now rejects protected or otherwise non-plain spell IDs before lookup instead of allowing them into Lua table indexing.",
                        "Explicit Player Mana ownership no longer creates a duplicate Alternative Mana bar, survives vehicle and module lifecycle transitions, and keeps live bars, text, colors, Class Resource previews, and Unit Frame previews on the same displayed resource.",
                        "Class Resource, Player HP, Alternative Mana, detached-power width, and power-text controls now refresh their dependent enabled states immediately after changes, resets, undo, or Assistant application.",
                        "Gameplay configuration caching now follows the active profile table, and a failed gameplay apply can no longer leave later apply requests permanently blocked.",
                        "See New Features now reports the correct compact and full-history version ranges for 6.11.",
                    },
                },
            },
        },
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
