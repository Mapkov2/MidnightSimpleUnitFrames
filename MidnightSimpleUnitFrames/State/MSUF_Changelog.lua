-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "5931C27E88B4F99D58898705292A469E12A8D79FB0AB325FD81DACEEA582625B",
    currentVersion = "6.14",
    historyFromVersion = "6.11",
    previousVersion = "6.13",
    rangeLabel = "6.13 -> 6.14",
    entries = {
        {
            version = "6.14",
            date = "2026-08-30",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Health-bar backgrounds can now fill the full bar or only missing health. The background can be colored independently with Custom tint, Match health bar, Class color, or Health gradient, with matching Unit Frame, Group Frame, and preview rendering.",
                            link = {
                                pageKey = "opt_colors",
                                query = "background fill missing health only",
                                label = "Background Fill",
                                sectionId = "colors_background",
                                controlId = "menu2.opt.colors.advanced.background.fill.mode",
                                settingKey = "general.barBgFillMode",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added Full bar and Missing health only background-fill modes plus independent health-background color sources, while migrating existing profiles without changing their current appearance.",
                        "The Assistant now routes Aura content and filter requests to the Unit or Group Frame that owns them, exposes the See New Features destination directly, and presents ambiguous controls with readable menu breadcrumbs instead of internal identifiers.",
                        "Unit Frame tooltips react immediately when their configured modifier key is pressed or released while the frame remains hovered.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Player Castbar interrupt feedback survives the client event order where the cast stops before the interrupted result arrives, without reviving stale casts.",
                        "State Tint controls appear and disappear immediately when their master toggles change instead of requiring the Colors page to be reopened.",
                        "Assistant queues, history, undo, pending choices, workflows, and deferred callbacks are now isolated to the profile that created them, preventing stale work from crossing a profile switch or surviving beyond its conversational context.",
                        "Immediate and deferred Assistant mutations now share the same failure-recovery path so partial work rolls back consistently.",
                        "General Aura guidance no longer competes with frame-local Aura owners, and question-shaped duration-filter requests retain their safe executable choices.",
                        "Aura-name fallback updates skip redundant unit-scan setup when no unresolved additions can benefit from it.",
                        "Opening Unit Frame Power settings no longer errors while building the detached-bar Text on detached bar control.",
                    },
                },
            },
        },
        {
            version = "6.13",
            date = "2026-08-28",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Party and Raid Frames now have a curated MSUF Highlights Buff filter. It shows 122 important offensive, support, defensive, and healer cooldowns from every group member, including short player effects such as Shadow Dance and shared states such as Shroud, while leaving common rotational buffs out. New and Factory-reset profiles use it by default; existing profiles keep their current filter and can opt in.",
                            link = {
                                pageKey = "gf_auras",
                                query = "msuf highlights buff filter",
                                label = "MSUF Highlights",
                                sectionId = "auras",
                                controlId = "menu2.gf_auras.auras.group-workspace.lane.buff.tool-selector",
                                settingKey = "gf_party.auras.buff.filterToken",
                                prepareKind = "groupAuraWorkspace",
                                prepareValue = "party_buff_filters",
                            },
                        },
                        {
                            text = "Focus Kick can now stay visible beside the Focus castbar. The new option keeps the compact interrupt icon while restoring the matching Focus castbar and its normal cast ownership.",
                            link = {
                                pageKey = "opt_castbar",
                                query = "show castbar with focus kick icon",
                                label = "Show castbar with Focus Kick icon",
                                sectionId = "castbar_focus_kick",
                                controlId = "menu2.opt.castbar.global.focus.kick.focus.kick.show.castbar",
                                settingKey = "general.focusKickShowCastbar",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "MSUF Highlights uses one shared immutable catalog and Blizzard's native exact-ID candidate filtering, with no MiniAuras dependency, polling, or recurring roster scans.",
                        "The Assistant now understands German negative determiners, colloquial removal requests, and double negatives, can switch all supported MSUF or Blizzard Unit Frames globally, and retries zero-result setting searches with registered synonyms.",
                        "Assistant Aura actions accept enchant-related inputs and route Aura filter and blacklist requests more precisely.",
                        "Exact Assistant searches recognize registry aliases and complete portrait-control labels.",
                        "Typed HEX colors in the compact color picker now commit on Enter through the same apply path as the visual picker.",
                        "Removed the experimental built-in Rogue APEX developer helper and its retired settings, menu controls, Assistant registrations, and generated metadata.",
                        "The Group Frame preview roster now includes B3NZII.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "The Player Castbar now ignores interrupted or failed terminal events when no real cast is active, preventing false \"Interrupted\" flashes during rapid instant-cast spam while preserving normal cast, channel, vehicle, and Empower feedback.",
                        "Focus interrupt and cast trackers reinitialize after the active profile and frames become available during startup.",
                        "Focus Kick castbar state follows the icon lifecycle and clears stale Focus cast ownership when the combined display is disabled.",
                        "Party Frames now honor the configured Units per column and Max columns values instead of forcing a single secure column, including future combat-safe secure-header capacity.",
                        "Live Party, Raid, and Mythic Group Frame blocks clamp their actual rendered footprint across scale and anchor combinations without rewriting SavedVariables; Edit Mode and previews keep the configured point semantics, and unavailable protected geometry fails closed.",
                        "Party-style Arena Group Frames fail open to Blizzard's secure roster while the Arena or Shuffle roster is temporarily incomplete instead of publishing an unusable partial name list.",
                        "Group Range Fade re-queries the bound member on native range events in PvP instances and refreshes its event route when the instance context changes.",
                        "Unit Range Fade reuses unchanged poll sets across movement and identity edges instead of rebuilding or duplicating scheduler work.",
                        "Player Power current-value text retains its resolved resource identity through form, vehicle, and explicit Mana handoffs.",
                        "The Player Resting indicator refreshes when its frame becomes visible after a hidden zoning transition, without adding polling or permanent update work.",
                        "Aura-name fallback scans coalesce to one pending unit scan and skip update-only or removal-only events that cannot resolve a new alias.",
                        "Heal-prediction stripes use a specialized full-health path and avoid redundant secret checks and overflow work.",
                        "Assistant ambiguity handling fails closed for conflicting colors, cross-frame wording, contradictory movement, partial compound commands, and misleading numbers in control labels instead of applying unrelated settings.",
                        "Exact setting, location, and purpose questions outrank generic concept guidance so profile-copy, Aura, status-indicator, castbar, and frame-specific requests reach their precise owner.",
                        "Safe Assistant questions preserve their original polarity and capability intent across page-context routing instead of becoming setting changes.",
                        "Full portrait control wording resolves to the intended Unit or Group Frame portrait control.",
                        "Read-only Assistant definition, location, relationship, and diagnostic requests stay off broad mutation indexes, while explicit numeric movement remains on bounded routes.",
                        "Assistant clarification choices survive repeated classification instead of being lost through a cached provisional read-only result.",
                        "The Assistant's unloaded-Menu Group copy path now mirrors the native chunked health and power fill fields while excluding anchor and migration-only state.",
                        "Exact-ID group buffs remain available on follower-dungeon Party NPCs under Blizzard's Retail group-member identity contract instead of being hidden by the old assist gate.",
                        "Durationless curated states such as Shroud recipient membership bypass generic Hide Permanent and Maximum Duration restrictions, while every other Group Aura filter keeps the saved restrictions.",
                        "Exact-ID candidate filters are installed before any broad native filter transition, avoiding an intermediate unrestricted Helpful-aura refresh.",
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
