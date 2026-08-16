-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "7E2C3BBD8F6C69D4F7B4BFF349ABDF4DA052DA0E9817C747974DB8EA8414EC0C",
    currentVersion = "6.08",
    historyFromVersion = "6.02",
    previousVersion = "6.07",
    rangeLabel = "6.07 -> 6.08",
    entries = {
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
        {
            version = "6.08-Beta2",
            date = "2026-08-15",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
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
                        "Replaced the toolbar's New Task action with a dedicated See New Features changelog page whose highlighted change sentences link directly to their matching MSUF menu settings.",
                        "Localized the new stance, portrait sizing, and portrait edge-softness controls across all 12 supported locales.",
                        "Updated Assistant registrations, generated coverage data, search routing, and static search data for the new status and portrait controls.",
                        "Corrected the bundled release history so features added after Beta 1 are listed under Beta 2 instead of the already-published Beta 1 package.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed the Castbar General tab height after adding the interrupter-name option.",
                        "Changed Target and Focus castbar identity refreshes from deferred callbacks to direct synchronous updates.",
                        "Cleared the castbar driver's unused OnUpdate script once during construction instead of repeating the native transition on target swaps.",
                        "Fixed player Unit Frames showing the fallback blue or another incorrect health color for identity-restricted PvP targets by routing every player class through Blizzard's native secret-safe class-color pipeline.",
                        "Streamlined Unit Frame identity refreshes across bars, portraits, status text, regular text, and range fading so unchanged identity state avoids redundant work.",
                        "Skipped player-only nickname-provider APIs for NPC units while retaining supported NPC nickname sources.",
                        "Fixed Arena Group Frames using raid instead of party configuration, including runtime, Blizzard-frame ownership, Edit Mode, and previews.",
                        "Fixed exact-ID aura indicators mixing friendly and hostile filters after switching targets.",
                        "Limited PvP indicator runtime to arenas, battlegrounds, and War Mode, removing unrelated faction and PvP-timer event traffic outside those modes.",
                    },
                },
            },
        },
        {
            version = "6.08-Beta1",
            date = "2026-08-15",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added an optional Slug font rendering mode for clearer, more consistent text across Unit and Group Frames.",
                        "Added configurable AFK timers to Unit and Group Frame status text.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Group Frame absorb overlays ignoring the configured opacity.",
                        "Fixed aura icon zoom scaling when a debuff border is active.",
                    },
                },
            },
        },
        {
            version = "6.07",
            date = "2026-08-15",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Expanded Texture Layers into three independently configurable, HP-reactive decoration slots with shared gradients, threshold colors, opacity rules, target/combat conditions, presets, and runtime-faithful previews.",
                        "Added League of Legends-style Health and Power loss feedback for Unit and Group Frames. Bars update immediately while a configurable trailing chunk shows recently lost Health or spent Power without polling.",
                        "Added profile-wide controls for Blizzard's Player Buff Frame and normal Debuff icons while keeping Private Auras and Deadly Debuff warnings available.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added direct Edit Mode popup controls for Custom Aura 1-4, Dots on Target, and Player Defensive Buffs, including position, size, spacing, reset, undo, Boss synchronization, and Menu focus.",
                        "Restored Spell Indicator bars with Blizzard's native aura-duration StatusBar, configurable growth direction, smoothing, timer text, geometry, color, alpha, and layer.",
                        "Increased the Menu Back and Forward buttons for easier navigation.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Group Aura lanes and Spell Indicators remaining visible for offline, phased, distant-map, or different-instance members. Presence updates remain coalesced and event-driven.",
                        "Fixed Unit Aura preview handles requiring a second click before their X/Y controls appeared after switching lanes. The first click now survives the settings-page rebuild.",
                        "Fixed Target of Target identity and color events being routed through the Target frame without unit filtering. Updates now listen only to targettarget, and foreign unit events can no longer recolor the Target health bar.",
                        "Fixed Texture Layer controls writing to the wrong slot and protected HP-driven alpha values being cached or compared from Lua.",
                        "Fixed Spell Indicator icon, bar, glow, and full-frame effect ownership, opacity, cleanup, preview parity, and layer ordering.",
                        "Fixed Level, Race, Class, and other name-relative status text drifting away from shortened or repositioned Unit Frame names.",
                        "Fixed stale Player portraits, Unit Aura settings writing to the wrong lane, and Objective Tracker state leaking through MSUF's Edit Mode bridge.",
                        "Fixed Class Resource preview text handles becoming trapped behind higher-layer bar visuals.",
                    },
                },
            },
        },
        {
            version = "6.07-Beta4",
            date = "2026-08-14",
            sections = {
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Level, Race, and Class text with Left to name / Right to name anchors floating away from shortened names. The text now follows the rendered name edge and only snaps to the shortening cut while the name actually overflows its configured width.",
                    },
                },
            },
        },
        {
            version = "6.07-Beta3",
            date = "2026-08-14",
            sections = {
                {
                    title = "Changes",
                    bullets = {
                        "Added direct Edit Mode popup controls for Custom Aura 1-4, Dots on target, and Player Defensive Buffs. Each lane can now adjust position, size, and spacing with reset, undo, Boss synchronization, Menu focus, and Assistant parity.",
                        "Restored Spell Indicator Display as: Bar with Blizzard's native C-side aura-duration StatusBar. Bars keep their configured geometry, color, alpha and layer while adding Growth-controlled fill direction, optional native smoothing and movable native timer text without Lua polling.",
                        "Increased the Back and Forward navigation buttons for easier Menu navigation.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Class Resource preview text handles becoming stuck behind higher-layer bar visuals.",
                        "Fixed Group Frame Spell Indicator glow previews differing from runtime effects. The preview now uses the shared runtime renderer and cleans up its effect owners when suspended.",
                        "Fixed Unit Aura handles losing their first-click selection when opening a lane rebuilt its settings page. Selection is now restored only onto the newly created Preview handle.",
                        "Fixed Spell Indicator full-frame effect opacity and layer ordering against render targets, Aura names, and other text. Persistent effects remain visible while editing, and the selected Group Frame Name Overlay stays above its source text.",
                        "Fixed name-relative Unit Frame status text ignoring the configured Name anchor and offsets.",
                        "Fixed Assistant questions and navigation requests applying settings, including enum values that were never stated. Pure small talk now keeps its conversation context without entering a settings lane.",
                        "Fixed Assistant requests about borders, Auras, text, colors, and other frame details falling through to whole-frame toggles or unrelated position controls. Scoped Highlight Borders now control their Aggro, Dispel, and Purge outlines together.",
                        "Fixed narrow Group Frame position phrases matching unrelated horizontal or vertical layout controls.",
                    },
                },
            },
        },
        {
            version = "6.07-Beta2",
            date = "2026-08-14",
            sections = {
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Texture Layer controls writing to the wrong texture after switching slots or opening another texture from the preview. Each control now remains bound to its own slot, and protected HP-driven alpha values are no longer cached or compared from Lua.",
                        "Fixed Spell Indicator icons and full-frame effects competing for AuraSlot ownership. Both styles now share one native Blizzard assignment while retaining independent element layers. Unsupported expiration-timed full-frame effects now fall back to the active-aura effect without secret-value hooks or polling.",
                        "Improved Assistant handling for conversational bar dimensions, rounded-frame requests, no-target load conditions, Raid filters versus Raid frame scope, Aura lane attributes, and outline layer wording.",
                        "Fixed narrow Assistant navigation, reset, and profile-copy requests being interpreted as broader setting changes.",
                    },
                },
            },
        },
        {
            version = "6.07-Beta1",
            date = "2026-08-14",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Texture Layers are now three fully configurable, HP-reactive decoration slots. Each texture can follow the shared low/mid/high HP gradient, switch to class or custom colors above a threshold, change opacity or appear only at low health, and combine current-target and combat-state rules. The reorganized setup adds quick Text Background and Highlight presets plus runtime-faithful previews, while HP reactions reuse the existing Health update path without polling.",
                        "Added Chunked Health and Power Loss for Unit and Group Frames. The live bar updates immediately while a short, configurable loss trail shows what was just spent or lost; Smooth and Chunked modes are mutually exclusive and share runtime-faithful previews, rounded-frame support, copy controls, and dedicated loss colors.",
                        "Added independent profile-wide switches for Blizzard's player Buff Frame and normal Debuff icons near the minimap. Private Auras and Deadly Debuff warnings remain visible, and the feature stays passive with no polling or recurring MSUF work.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Group Aura lanes and Spell Indicators remaining visible for members who are offline, phased, on another map, or inside a different instance group. Presence now composes with helpful/hostile assistability and fails closed through coalesced lifecycle events. Identity, phase, and connection changes remain combat-live, while cold map and instance reconciliation is deferred into one post-combat pass.",
                        "Removed the Objective Tracker from MSUF's Blizzard Edit Mode bridge to avoid propagating dirty layout state into combat-secret UI paths. The tracker remains fully Blizzard-owned, and Group Edit Mode now relies on its single shared state listener.",
                        "Fixed native Player portraits occasionally remaining stale or blank after login or world entry.",
                        "Fixed several Unit Aura layout settings writing to the wrong scope, including lane visibility and separate Buff/Debuff style padding.",
                        "Improved Assistant handling for natural highlight on/off requests, texture names without connector words, border styles and opacity, outline layers, absorb height, gradient intensity, and how-to navigation. Unmatched navigation requests now offer the closest controls without changing settings.",
                    },
                },
            },
        },
        {
            version = "6.06",
            date = "2026-08-13",
            sections = {
                {
                    title = "Changes",
                    bullets = {
                        "Added a Non-Player Auras Debuff filter for Unit and Group Frames, including Menu, profile import, diagnostics, and Assistant support. It keeps encounter and environment Debuffs while excluding effects caused by players or player pets.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed an edge case where Player, Target, Boss, and other Unit Frame health text remained hidden after importing profiles with a conflicting obsolete visibility value. Current profile settings now always win, while legacy-only profiles retain their previous behavior without profile rewrites or recurring runtime work.",
                        "Fixed the MSUF Game Menu button using mismatched dimensions and styling. It now follows the active Game Menu button template, size, font, and EllesmereUI skin without stretching.",
                    },
                },
            },
        },
        {
            version = "6.05",
            date = "2026-08-13",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Reworked Augmentation Evoker resources into one coherent Player Power surface: segmented Essence remains visible while Ebon Might uses its own native duration row. Runtime, embedded and detached layouts, rounded styling, text layers, Menu previews, search, and the Assistant now share the same geometry and ownership.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added Unit Frame load conditions for No target and Out of combat and no target, including Copy To, search, diagnostics, and Assistant control.",
                        "Added a dedicated Class Resource text layer so resource numbers, Rune times, and Ebon Might duration text can be ordered independently from the resource bar and normal Player Power text.",
                        "Added a delayed warning with a direct settings shortcut when Unit Frames are configured to follow Essential Cooldowns but no supported Blizzard or third-party cooldown anchor is active.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Spell Icon Full-Frame Effects ignoring their configured element layer. Effects now use a frame-local surface so their 0-30 layer orders correctly against bars, text, and other Unit Frame elements.",
                        "Fixed helpful and hostile Group Aura owners retaining invalid exact-ID assignments after assistability, roster-presence, or instance transitions. Updates remain event-driven and fail closed without polling or restricted Aura reads.",
                        "Fixed Interrupt Ready colors and Focus Kick state becoming stale when a protected cooldown completed. MSUF now uses Blizzard's native duration completion callback with a one-shot fallback and ignores unrelated cooldown events.",
                        "Fixed Group Range Fade briefly treating members from another instance or phase as in range after portal and party-presence transitions.",
                        "Fixed Castbars jumping when switching between Unit Frame anchoring and independent Edit Mode placement.",
                        "Fixed later canonical Aura profile revisions being mistaken for legacy data eligible for the original Aura reset.",
                        "Refreshed cached Menu pages when reopening MSUF, made exported profile strings immediately selectable for copying, and exposed the HEX value in the compact color picker.",
                        "Improved Assistant handling for direct control wording, target-aware visibility requests, outline sizing, background textures, and maximum-health-loss textures.",
                    },
                },
            },
        },
        {
            version = "6.04",
            date = "2026-08-13",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Reworked Unit Frame Auras around explicit lane ownership. Every Buff and Debuff lane now owns its exact layout, filtering, text, effect, and visibility settings, while icon appearance remains global by Aura type. Existing profiles retain their visible setup, and runtime, Menu, Edit Mode, search, and the Assistant now use the same ownership model.",
                        "Added a profile-specific option to disable Northern Sky Raid Tools nicknames on MSUF frames without changing NSRT or its settings. The integration remains enabled by default and can also be controlled through the Assistant.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Reduced recurring work on frequent Health and Texture Layer events. Health prediction and text followers now skip already-pending updates, while dynamic Texture Layers refresh only affected slots, use color-only updates where possible, and reuse their runtime objects.",
                        "Fixed the Elite Indicator missing from Unit Frame previews. Elite, Rare Elite, Rare, and Boss classifications now use their matching Blizzard icons in runtime and previews while sharing one position, size, and layer.",
                        "Fixed identity-dependent Aura displays becoming stale after taxi transitions and helpful Group auras remaining visible when their caster identity could no longer be verified out of range. The existing range and lifecycle events now refresh them without polling.",
                        "Fixed sorted or filtered Raid headers temporarily omitting roster members when unit-name data lagged behind the authoritative Raid roster. MSUF now waits for a complete name list and otherwise falls back to Blizzard's native roster path.",
                        "Fixed Tracked Buffs silently inheriting the normal Buff container's sort method and direction instead of using their own ordering.",
                        "Fixed Group Frame preview borders not repainting immediately, and fixed rounded borders overwriting active Aggro or Dispel test colors after the preview refresh.",
                        "Kept reload-required popups above the MSUF options window and expanded Unit Frame Basics sections so their controls no longer clip.",
                        "Improved the disabled Options-module error so it tells the user to enable MSUF Options in Blizzard's AddOns menu.",
                    },
                },
            },
        },
        {
            version = "6.03",
            date = "2026-08-12",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Track any group buff from any specialization. Group Frame Spell Icons now provide a shared All Specs workspace, so entries such as Feint can be configured once and remain active across every character specialization.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Multi-Spec now exposes all 40 Retail specializations. Custom Aura IDs can also be added to an individual specialization, allowing a Holy Priest configuration, for example, to track Feint (1966) on another group member while Only show my casts is disabled.",
                        "Added a curated, class-wide Big Defensive Spell-ID filter for friendly Unit and Group Frames, with Blizzard's native classification as the restricted-data fallback. Aura classification choices are now mutually exclusive while Only mine and Also include nameplate-only remain explicit modifiers, and Menu, search, and the Assistant share the same contract.",
                        "Added direct Assistant control and cold-path diagnostics for Unit Frame Buff and Debuff Full-Frame Effects. Menu and Assistant now share the same effect choices without polling or reading protected native Aura visibility.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Target of Target and Focus Target health bars and names losing class colors when WoW protects dependent-unit class data in combat. Protected colors now flow directly through Blizzard-native color sinks without polling or persistent secret-value caches.",
                        "Fixed Health and Power gradients missing or differing in Unit and Group previews. Embedded, detached, and rounded Power previews now reuse the same gradient composition as runtime rendering.",
                        "Fixed Level, Race, and Class text in Unit Frame previews using the default preview font instead of the selected unit font.",
                        "Made Cleanse Border changes request the required UI reload.",
                        "Kept the Player Castbar provider selectable in the Bars menu.",
                        "Fixed native Aura containers triggering a forbidden EventRegistrations error during Unit Frame aura setup.",
                        "Improved the ownership handoff between MSUF and Blizzard Party/Raid frames. Provider and fallback changes now return frames reliably through Blizzard's own lifecycle and request the required UI reload.",
                        "Fixed Clique and other click-cast providers losing their Unit Frame bindings after profile or configuration updates. MSUF now preserves provider-owned secure click attributes after the initial fallback setup.",
                        "Isolated Group Spell Indicator preview positions from live saved positions.",
                        "Restored continuous Devourer class-resource updates and removed obsolete partial-update ownership from the resource pipeline.",
                        "Fixed Icicles showing an Aura icon over Class Resources or retaining incorrect stack counts. Icicles now refreshes the exact player Aura on each Aura change, while protected Icicle and Maelstrom Weapon counts fill their pips through Blizzard's native StatusBar clamping without Lua comparisons.",
                        "Fixed Tip of the Spear showing incorrect stacks after current Survival Hunter spenders and Takedown with Twin Fangs. Stack tracking now also expires correctly without protected Aura reads.",
                        "Fixed native Auras, Spell Indicators, and Aura-based Class Resources becoming stale or retaining incorrect durations after cinematics and entering the world. Lifecycle refreshes are now coalesced and event-driven without polling.",
                        "Refreshed Unit Frame names immediately after anchor changes.",
                        "Restored live Group frames correctly after preview roster handoffs.",
                        "Honored configured Aura layers for fixed Group slots.",
                        "Fixed the animated Resting symbol trying to use an unavailable Blizzard atlas; unsupported clients now fall back safely.",
                        "Fixed Unit Frame Edit Mode quick actions applying stale compiled settings after size, position, reset, copy, or detached Power changes.",
                    },
                },
            },
        },
        {
            version = "6.02",
            date = "2026-08-11",
            sections = {
                {
                    title = "WoW 12.1 Release Highlights",
                    bullets = {
                        "Split Unit Preview Buffs and Debuffs into independent layers with correct handle-to-menu routing, and expanded the frame-local Debuff blacklist presets.",
                        "Added Blizzard-native Ebon Might duration text plus safe, independently configurable Alternative Mana width geometry across runtime, previews, search, and the Assistant.",
                        "Made Blizzard's animated Resting symbol part of the fresh default profile while preserving existing profile choices and live Resting state.",
                        "Reworked the upgrade-highlight tour around real Back/Forward navigation and added Assistant commands that can restart a skipped or completed tour.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed nickname-provider fallback refreshes so updated names reach the correct Unit and Group Frames without broad polling.",
                        "Guarded secret Player Health values before Class Resource logic can inspect them in combat.",
                        "Fixed Texture Layer target refreshes, rounded clipping, true-outline geometry, rounded preview edges, and Castbar preview text positions after live setting changes.",
                    },
                },
            },
        },
    },
}

ns.MSUF_FullChangelog = data
ExportPublic("MSUF_FullChangelog", data)
