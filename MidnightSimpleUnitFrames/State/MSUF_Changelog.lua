-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "B5520429E4ABDE963DB170CE99F531E99503EFD705F078BF47C5C27E07AF4E5E",
    currentVersion = "6.15-beta2",
    historyFromVersion = "6.13",
    previousVersion = "6.15-beta1",
    rangeLabel = "6.15-beta1 -> 6.15-beta2",
    entries = {
        {
            version = "6.15-beta2",
            date = "2026-09-02",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Raid and Mythic Raid role sorting can now span the entire raid. Enable Sort roles across entire raid under Frames > Party/Raid Frames > Layout > Sorting to order tanks, healers, and damage dealers across the whole raid instead of within each raid group, including with Preserve raid groups.",
                            linkless = true,
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added Sort roles across entire raid to Raid and Mythic Raid sorting with defaults, profile copy, locales, search, and Assistant support. By Role with Preserve raid groups and Group + Role follow the raid-wide order; Party is unaffected.",
                        "The Boss Preview now renders incoming heal, absorb, and heal-absorb bars plus the absorb text so prediction settings can be judged without a live boss.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Raid role sorting stays fully out of combat: the raid-wide order is rebuilt only when roles or the roster change outside combat, and Blizzard's secure header applies it natively.",
                        "Tidied the Group Layout Sorting card so the Sort Mode dropdown and its toggles sit evenly inside the card.",
                    },
                },
            },
        },
        {
            version = "6.15-beta1",
            date = "2026-09-01",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Absorbs and heal prediction can now stay visible when Unit Frame health opacity is reduced. Enable Keep Absorbs + Prediction Visible per frame to preserve these overlays independently from the health fill.",
                            link = {
                                pageKey = "uf_player",
                                query = "keep absorbs prediction visible",
                                label = "Keep Absorbs + Prediction Visible",
                                sectionId = "transparency",
                                controlId = "menu2.uf_player.unit.transparency.alpha_exclude_prediction_bars",
                                settingKey = "player.alphaExcludePredictionBars",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added the matching Keep Absorbs + Prediction Visible option for Party and Raid Frames, including profile copy, defaults, previews, search, and Assistant support.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Health gradients, texture changes, prediction refreshes, Group Range Fade, and the Boss Preview now preserve the configured health and prediction opacity instead of resetting fills to full opacity.",
                        "Detached Player Power bars attached or width-synced to Class Resources keep using the controller-maintained hidden anchor, preventing width or position jumps when shapeshifting hides the visible Class Resource bar.",
                    },
                },
            },
        },
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
