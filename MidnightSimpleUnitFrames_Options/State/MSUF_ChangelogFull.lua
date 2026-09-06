-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "9B877D9912A7502D3A5F50A31354FEA52FBFEA078D7043F1C7C5AAE1F4AA2F90",
    currentVersion = "6.5-alpha12",
    historyFromVersion = "6.5-alpha1",
    previousVersion = "6.5-alpha11",
    rangeLabel = "6.5-alpha11 -> 6.5-alpha12",
    entries = {
        {
            version = "6.5-alpha12",
            date = "2026-09-06",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Highlight borders work reliably again on rounded frames and respect the configured border thickness.",
                            link = {
                                pageKey = "opt_bars",
                                query = "rounded frame texture",
                                label = "Rounded frame texture",
                                sectionId = "bars_rounded",
                                controlId = "menu2.opt.bars.global.rounded.rounded.frames.enabled",
                                settingKey = "bars.roundedFramesEnabled",
                            },
                        },
                        {
                            text = "MSUF menus and Edit Mode can follow your MapkoSkin appearance. The Use MapkoSkin for MSUF menus option connects compatible MapkoSkin installations to MSUF menu styling.",
                            link = {
                                pageKey = "opt_misc",
                                query = "use mapkoskin for msuf menus",
                                label = "Use MapkoSkin for MSUF menus",
                                sectionId = "misc_mapkoskin",
                                controlId = "menu2.opt.misc.global.setting.mapko.skin.menus",
                                settingKey = "general.mapkoSkinMenus",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Includes the complete Retail 6.15 and 6.151 feature and fix set, including the earlier prediction-opacity, raid-sorting, Assistant, and performance improvements.",
                        "MapkoSkin menu integration is available across the Mainline, Vanilla, TBC, and Mists flavors, with its own searchable toggle.",
                        "The Mainline flavor retains Retail 12.1.5 support and Arena Frames. Vanilla 1.15.9, TBC 2.5.6, and Mists 5.5.4 compatibility remains included.",
                    },
                },
                {
                    title = "Fixes",
                    bullets = {
                        "Restored rounded highlight startup and layering, including border thickness up to 30.",
                        "Native Dispel and Purge borders apply their configured thickness on all frame shapes and refresh immediately after Menu changes.",
                        "Group Frame highlight detection continues working when Aura icons are disabled.",
                        "Any dispel type highlights can detect typed harmful Auras on enemy units.",
                    },
                },
            },
        },
        {
            version = "6.5-alpha11",
            date = "2026-09-05",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Busy group combat now spends less time updating health gradients, dynamic backgrounds, protected text, Aura fallback state, and Range Fade timers. Existing colors, status transitions, unresolved-Aura discovery, and range sampling behavior are preserved.",
                            link = {
                                pageKey = "opt_colors",
                                query = "health gradient",
                                label = "Health Gradient",
                                sectionId = "colors_appearance",
                                controlId = "menu2.opt.colors.advanced.appearance.gradient.enabled",
                                settingKey = "general.enableHealthGradient",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Synchronized the complete Retail 6.15-beta7 performance set into the unified Alpha package.",
                        "The Mainline flavor keeps its Retail 12.1.5 native Aura, scheduler, tooltip-caster, and pixel-rounding paths. Arena Frames and the Vanilla 1.15.9, TBC 2.5.6, and Mists 5.5.4 flavors remain included.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Health gradients reuse bounded native scalar curves for their RGB channels, avoid per-update ColorMixin allocation, and keep constant channels out of the native evaluation path.",
                        "Group health updates avoid a repeated dynamic-background refresh and an empty color handoff after the background has already been painted.",
                        "Dynamic health backgrounds cache stable alpha inputs and known cache keys, use the native secret-value predicate when available, and forward protected colors directly to their supported rendering sink.",
                        "Protected current, maximum, and percentage text modes use compiled single-value writers instead of the general multi-value formatter.",
                        "Unresolved Aura fallback scans avoid resynchronizing an unchanged active-work state while later discovery, owner reactivation, and unregister cleanup remain intact.",
                        "Group death-background updates skip cache probes that cannot be reused outside an active frame dispatch while retaining fresh native death and resurrection checks.",
                        "Range Fade keeps an earlier timer when its logical deadline moves later, reducing timer replacement churn without moving range checks or alpha changes forward.",
                    },
                },
            },
        },
        {
            version = "6.5-alpha10",
            date = "2026-09-04",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Absorbs and heal prediction can now stay visible when the health bar is faded into the background. Enable Keep Absorbs + Prediction Visible per Unit Frame or for Party and Raid Frames to keep these overlays at full opacity independently from the health fill.",
                            link = {
                                pageKey = "uf_player",
                                query = "keep absorbs prediction visible",
                                label = "Keep Absorbs + Prediction Visible",
                                sectionId = "transparency",
                                controlId = "menu2.uf_player.unit.transparency.alpha_exclude_prediction_bars",
                                settingKey = "player.alphaExcludePredictionBars",
                            },
                        },
                        {
                            text = "Raid and Mythic Raid role sorting can now span the entire raid. Enable Sort roles across entire raid under Group Layout > Sorting to order tanks, healers, and damage dealers across the whole raid instead of within each raid group.",
                            link = {
                                pageKey = "gf_layout",
                                query = "sort roles across entire raid",
                                label = "Sort roles across entire raid",
                                sectionId = "sorting",
                                controlId = "menu2.gf_layout.group.field.sortrolesacrossraid",
                                settingKey = "gf_raid.sortRolesAcrossRaid",
                                prepareKind = "groupScope",
                                prepareValue = "raid",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Synchronized the complete Retail 6.15-beta6 feature and fix set into the unified Alpha package.",
                        "Added Keep Absorbs + Prediction Visible to Unit Frames and Party/Raid Frames, including profile copy, defaults, previews, search, and Assistant support.",
                        "Added Sort roles across entire raid for Raid and Mythic Raid Frames, including defaults, profile copy, locales, search, and Assistant support. Party sorting remains unchanged.",
                        "The Boss Preview now displays incoming heals, absorbs, heal absorbs, and absorb text so prediction settings can be reviewed without a live boss.",
                        "The Assistant now resolves requests about a specific Unit Frame and its opacity, visibility, movement, portrait, texture, and text controls more precisely.",
                        "Retired pre-6.0 profile conversion and import controls while preserving every supported MSUF 6.x profile and Wago import.",
                        "The Mainline flavor retains its Retail 12.1.5 native Aura, scheduler, tooltip-caster, and pixel-rounding paths. Arena Frames and the Vanilla 1.15.9, TBC 2.5.6, and Mists 5.5.4 client flavors remain included.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Health gradients, texture changes, prediction refreshes, Group Range Fade, and the Boss Preview preserve the configured health and prediction opacity.",
                        "Detached Player Power bars attached or width-synced to Class Resources keep their controller-managed anchor while the Class Resource bar is hidden.",
                        "Aura owners that cannot be visible stop parsing UNIT_AURA; registration and unresolved-name work resume when the owner becomes eligible again.",
                        "Cleanse and Purge borders share the Frame Outline layer, Unit Frame dispel borders follow Blizzard's assist rules, and exact-ID Group Aura ownership remains intact.",
                        "Group Frame dead and offline backgrounds follow secret health updates, and preserved raid groups build and sort from one authoritative roster snapshot per secure-header setup.",
                        "Interrupted full Aura refreshes arm recovery before synchronous work, retain the Retail 12.1.5 native contracts, and no longer leave later refreshes pending.",
                        "Class Resource previews can schedule refreshes again after Menu lifecycle cancellation.",
                    },
                },
            },
        },
        {
            version = "6.5-alpha9",
            date = "2026-09-04",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "The unified Alpha now carries the current Retail 12.1.5 Aura path. Its Mainline flavor keeps the newer native Aura contracts while the Vanilla, TBC and Mists flavors retain their client-owned fallbacks.",
                            link = {
                                pageKey = "uf_player",
                                query = "player buff aura layout visible",
                                label = "Player Auras",
                                sectionId = "auras",
                                controlId = "menu2.uf_player.auras.unit-workspace.container-selector",
                                settingKey = "auras3.player.buff.visible",
                                prepareKind = "unitAuraWorkspace",
                                prepareValue = "buff_layout",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "CurseForge now presents this Alpha for Retail 12.1.5 together with Vanilla 1.15.9, TBC 2.5.6 and Mists 5.5.4; Retail 12.1.0 remains on the separate Beta track.",
                        "Synchronized the current Class Resource preview-recovery fix while retaining the client-owned resource implementations for Vanilla, TBC and Mists.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Native Aura hook recovery stays inside the factory-owned runtime, preserving the 12.1 contract floor without reintroducing the missing-global Aura failure.",
                        "Class Resource previews reacquire their current controls after a Menu rebuild, so preview movement continues to work after settings change.",
                        "Extended the Aura and Menu interaction smokes for the synchronized Retail paths.",
                    },
                },
            },
        },
        {
            version = "6.5-alpha8",
            date = "2026-09-04",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Restored Auras when the unified Alpha is used on Retail. The next-frame recovery callback now closes over the private identity-topology batch state instead of reading a missing Lua global.",
                        "Restored Mists Monk Class Resources after changing settings. Mistweaver and Windwalker Chi can refresh normally again instead of stopping on a missing Retail-only Ebon Might method.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Classic now installs its absent Ebon Might callbacks as one-time no-op contracts during ClassPower initialization, preventing repeated nil checks and keeping the ordinary ClassPower apply path allocation-free.",
                        "Interrupted full Aura refreshes now drain their private topology batch through a scope-owned closure; Lua 5.1 bytecode verification guards against compiling that state as a global again.",
                        "Added regression coverage for Mists Monk Chi resolution and the Classic controller's optional Ebon lifecycle contract.",
                    },
                },
            },
        },
        {
            version = "6.5-alpha7",
            date = "2026-09-04",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Aura displays recover instead of remaining disabled when a full refresh exceeds the Lua execution budget.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Retired the complete pre-6.0 profile conversion path and its legacy import controls. Every MSUF 6.x schema-600 profile and the 6.x Wago envelope remain supported; older or unversioned stored profiles are archived instead of being normalized into the active profile list.",
                        "The unified package accepts Retail 12.0.7, 12.1.0 and 12.1.5 while retaining the client-specific Vanilla, TBC and Mists manifests.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Full Aura refreshes batch identity-event topology once and arm their next-frame recovery before synchronous work, so a script ran too long abort cannot leave every later Aura refresh permanently latched as pending.",
                        "Pre-6 profile fallback code no longer runs in current profiles or imports, reducing cold-path work and maintenance surface without changing any supported 6.x profile.",
                    },
                },
            },
        },
        {
            version = "6.5-alpha6",
            date = "2026-09-03",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "The unified package now supports both Retail 12.1.0 and 12.1.5. Retail 12.1.0 keeps the established aura, timer and pixel-layout paths, while Retail 12.1.5 automatically activates the newer native paths when those APIs are present.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Declared both 120100 and 120105 in all three Mainline manifests and restored Retail 12.1.0 to the CurseForge compatibility metadata.",
                        "Added a dedicated Retail 12.1.0 fallback smoke covering keyed delayed scheduling, the unavailable aura-caster tooltip CVar and every newly adopted 12.1.5-only method boundary.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Retail 12.1.0 no longer requires Load out of date AddOns for the Alpha 5 runtime changes.",
                        "The 12.1.0 compatibility path remains event-driven and uses the existing C_Timer.After scheduler fallback without polling; Retail 12.1.5 retains the allocation-saving native TimedSignalMap path.",
                    },
                },
            },
        },
        {
            version = "6.5-alpha5",
            date = "2026-09-03",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Retail 12.1.5 support is now built into the unified Classic package. Aura Pandemic pulses use Blizzard's native animation ownership, bursty delayed work is consolidated through the new keyed scheduler, and native pixel rounding keeps supported frames aligned without recurring layout work.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Updated all Mainline manifests to Interface 120105; Vanilla, Mists and TBC retain their client-specific interfaces and now report version 6.5-alpha5.",
                        "Added the Retail 12.1.5 Pandemic contracts to MSUF aura containers, including duplicate-safe region ownership, native active animations and Edit Mode preview suppression.",
                        "Added the Show aura caster names tooltip setting across defaults, runtime, Menu, search and Assistant control coverage.",
                        "Rebuilt the generated search and Assistant schema data and refreshed the explicit Classic Retail override manifest for the synchronized source.",
                        "Updated the CurseForge release metadata so the Mainline flavor targets Retail 12.1.5 alongside Vanilla 1.15.9, TBC 2.5.6 and Mists 5.5.4.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Consolidated aura refreshes and castbar latency, interrupt and resync callbacks onto one TimedSignalMap scheduler, preserving keyed replacement while reducing independent timer allocation and callback churn.",
                        "Applied native nearest-pixel layout rounding to supported aura containers, castbars, status bars, unit frames and group frames.",
                        "Hardened Pandemic-region refreshes against duplicate registration and kept the native pulse active only while an aura is inside its Pandemic window.",
                        "Added a focused Retail 12.1.5 runtime smoke and extended the complete Classic gate; all static, bootstrap, drift and packaging checks pass on the release tree.",
                    },
                },
            },
        },
        {
            version = "6.5-alpha4",
            date = "2026-09-03",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "The Assistant now understands requests that name one unit frame and then describe the result. \"Show the PvP flag on my target frame\", \"put the portrait on the left of my player frame\" or \"the name on my player frame is too small\" resolve against that frame's own controls; the new unit-scope parser is registered in the Vanilla, Mists, and TBC runtime manifests as well.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Synchronized the shared addon source with Retail 6.15-beta3 (44de569e): the unit-scope Assistant lanes and their question shortcut, the identity-gated native aura owners, the Cleanse and Purge border layer band, the secret-safe dead and offline health background, and the preserved raid roster snapshot.",
                        "Ported the Retail preserved-raid header refactor into the Classic group headers: one authoritative roster snapshot per out-of-combat setup feeds both the per-block name lists and the roster-derived block count, and the geometry bridge takes that count instead of running its own sweep.",
                        "Rebased the explicit Classic Retail overrides (Auras3 unit frames, the unit-frame core, the Mainline TOC, and the four Assistant parser and router files) onto that snapshot.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Raids using more subgroups than the configured column limit lay out the same number of blocks they fill.",
                        "The Classic gate passes on the synchronized tree.",
                    },
                },
            },
        },
        {
            version = "6.5-alpha3",
            date = "2026-09-02",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Vanilla, Mists, and TBC now run the synchronized Retail 6.15 engine. The Classic flavors load the shared Player castbar runtime with its STOP/INTERRUPTED fixes, and their group headers, Blizzard group-frame handoff, unit config, class resources, and defaults were ported from Retail 6.15-beta2, including Sort roles across entire raid.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Retired the stale Classic player-castbar duplicate; the Classic client manifests load Castbars/MSUF_PlayerCastbarRuntime.lua directly and the gate keeps it that way.",
                        "Ported the Retail group-frame engine into the Classic group headers: physical preserved raid groups with one secure header per subgroup, the saved sort preference, the runtime footprint clamp, configured party columns, arena roster handling, and the raid-wide role order.",
                        "Ported the Retail class-power runtime (Augmentation split, explicit player mana source, resource text modes, secret-safe text) plus the unit config and defaults additions (health background fill and color modes, status indicators, GCD anchor, group highlight filter defaults) into the Classic flavors.",
                        "Added the Arena page preview to the Classic Unit page and refreshed the Classic-owned Unit Preview view, search keywords, and Assistant status registrations from Retail.",
                        "Rebased the Classic overrides for the Retail Text on detached bar fix and re-derived the Classic search index source hash.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "The Classic raid-manager, castbar, and arena smokes pin the ported contracts, and the Classic gate passes on the synchronized tree.",
                    },
                },
            },
        },
        {
            version = "6.5-alpha2",
            date = "2026-09-02",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Raid and Mythic Raid role sorting can now span the entire raid. Enable Sort roles across entire raid under Frames > Party/Raid Frames > Layout > Sorting to order tanks, healers, and damage dealers across the whole raid instead of within each raid group, including with Preserve raid groups.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Synchronized the shared addon source with Retail 6.15-beta2 (348b3643): raid-wide role sorting with defaults, profile copy, locales, search and Assistant support, plus the Boss Preview now rendering incoming heal, absorb and heal-absorb bars with the absorb text.",
                        "Rebased the explicit Classic Retail overrides (locales, defaults, Assistant parser and manifest, generated schema and search index) onto that snapshot while keeping the Arena-aware inventories.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Raid role sorting stays fully out of combat: the raid-wide order is rebuilt only when roles or the roster change outside combat, and the secure header applies it natively.",
                        "Tidied the Group Layout Sorting card so the Sort Mode dropdown and its toggles sit evenly inside the card.",
                    },
                },
            },
        },
        {
            version = "6.5-alpha1",
            date = "2026-09-01",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Published the first public 6.5 Classic alpha as one unified Mainline, Vanilla, Mists and TBC package, incorporating the accumulated shared feature and bugfix set from Retail 6.01 through 6.15-beta1 while retaining every client-specific API, ClassPower and manifest owner.",
                        "Reworked Unit Frame Auras around explicit lane ownership. Buff and Debuff lanes now own their layout, filtering, text, effects and visibility, while icon appearance remains global by Aura type across runtime, Menu, Edit Mode, search and the Assistant.",
                        "Added dedicated Arena Frames for arena1-3 with their own castbars, auras, Edit Mode movers, options page and Assistant coverage, including match preparation, stealth and trinket tracking.",
                        "Added independent health-background rendering with Full bar and Missing health only fill modes plus Custom tint, Match health bar, Class color and Health gradient sources for Unit Frames, Group Frames and previews.",
                        "Added Keep Absorbs + Prediction Visible per Unit, Party and Raid Frame so prediction overlays can remain visible when health opacity is reduced, including defaults, profile copy, previews, search and Assistant support.",
                        "Added the curated MSUF Highlights Group Buff filter with 122 important offensive, support, defensive and healer cooldowns. New and Factory-reset profiles use it by default; existing profiles keep their current filter and can opt in.",
                        "Added the option to keep the Focus castbar visible beside the compact Focus Kick interrupt icon.",
                        "Expanded Texture Layers with target-only accents, source-color treatments, crop and mirror controls, rounded clipping and matching Unit Preview controls.",
                        "Added rounded Class Resources, safe alternative-mana width and X-offset controls, native Ebon Might duration text on Mainline, and protected-value-safe ClassPower text and Player-health handling.",
                        "Reworked the upgrade highlight tour around navigation history, with pulsing Back and Forward arrows and Assistant commands to start or restart a skipped tour.",
                        "Added dynamic Custom Priority ordering for Target Dots and Custom 1-3 aura containers, keeping the configured spell order compact as tracked auras appear or expire.",
                        "Added a combat aura scanner to the blacklist workspace that captures blockable auras during combat and reopens the menu with the collected list.",
                        "Added the MidnightSkin theme bridge so the MSUF menu and Edit Mode popup chrome follow the active UI theme.",
                        "Expanded Assistant control of Absorb, Heal Absorb, Heal Prediction and Maximum Health Loss bars, including natural comparative requests such as making an overlay stronger, softer or more transparent.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Updated the Auras menus to describe the current Unit and Group Frame workspaces directly, with shorter upgrade-highlight copy and more styling controls.",
                        "Added the animated Blizzard resting symbol to the shared status model and fresh profile defaults. Mainline uses the native flipbook atlas; Classic clients fall back to the existing static resting icon when that atlas is unavailable.",
                        "Extended debuff-blacklist presets and clarified that blacklist choices apply only to the selected lane and frame scope.",
                        "Split Unit Preview Buff and Debuff strata, rebuilt the correct Aura lane after handle clicks and aligned castbar spell/time positioning with runtime.",
                        "Improved nickname-provider refreshes so unit-aware providers update the correct Unit and Group Frames without periodic polling.",
                        "Distinguished true outline geometry from texture borders and exposed the matching controls and previews.",
                        "Added a profile-specific option to disable Northern Sky Raid Tools nicknames on MSUF frames without changing NSRT itself; the integration remains enabled by default.",
                        "Added the shared All Specs Group Spell Indicator workspace, curated Big Defensive filtering and direct Full-Frame Aura Effect control.",
                        "Refreshed the generated Assistant schema, search index and menu inventories for the synchronized controls and replay-tour commands.",
                        "Reworked the menu UX with focus-section chips, a dashboard jump hub, search ranking and palette fixes, guarded destructive actions and explanations for disabled controls, with menu strings in all twelve locales.",
                        "Moved aura ordering into dedicated, scope-aware Ordering workspaces for Unit Frames, Group Frames, custom aura containers and external defensives.",
                        "Extended the Maximum duration filter to every aura lane on Unit and Group Frames, including Buffs, Tracked Buffs and External Defensives.",
                        "Added an optional Boss Number status indicator for Boss Frames.",
                        "Separated Augmentation Evoker resources on Mainline so Ebon Might renders on Player Power, Essence remains a Class Resource and Mana moves to Alternative Mana.",
                        "Added the Show spell IDs in aura tooltips toggle. It remains a guarded no-op on Vanilla, Mists and TBC where the underlying client option does not exist.",
                        "MSUF Highlights uses one shared immutable catalog and exact-ID candidate filtering without a MiniAuras dependency, polling or recurring roster scans.",
                        "The Assistant now understands German negative determiners, colloquial removal requests and double negatives, can switch supported MSUF or Blizzard Unit Frames globally, and retries zero-result setting searches with registered synonyms.",
                        "Assistant Aura actions accept enchant-related inputs and route Aura filter and blacklist requests more precisely; exact searches recognize registry aliases and complete portrait-control labels.",
                        "Typed HEX colors in the compact color picker now commit on Enter through the same apply path as the visual picker.",
                        "Removed the experimental built-in Rogue APEX developer helper and its retired settings, menu controls, Assistant registrations and generated metadata.",
                        "The Group Frame preview roster now includes B3NZII.",
                        "Existing profiles migrate to the new health-background fill and color-source settings without changing their current appearance.",
                        "The Assistant routes Aura content and filter requests to the owning Unit or Group Frame, exposes See New Features directly, and presents ambiguous controls with readable menu breadcrumbs instead of internal identifiers.",
                        "Unit Frame tooltips react immediately when their configured modifier key is pressed or released while the frame remains hovered.",
                        "This alpha reflects synchronized source plus automated repository, package and smoke validation; it does not claim live /reload, Arena, visual, taint or per-client gameplay certification.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed manual detached Power width being overwritten by automatic geometry.",
                        "Fixed Boss preview initialization before portrait refresh and kept mouseover outline colors current after style changes.",
                        "Fixed Unit copy actions bypassing their action guard and added the missing Castbar copy path.",
                        "Fixed rounded Texture Layer and preview edges being clipped, and refreshed target-dependent visibility on UNIT_TARGET.",
                        "Fixed restricted ClassPower values hiding text that can still be rendered safely, including native Ebon Might duration text on Mainline.",
                        "Reduced recurring Health and Texture Layer work by coalescing pending updates, refreshing only affected texture slots and reusing runtime objects.",
                        "Fixed Elite, Rare Elite, Rare and Boss classifications in Unit Frame previews and kept runtime and preview icons on one shared position.",
                        "Fixed incomplete Raid roster name data omitting members, restored live Group Frames after preview handoffs and honored configured Aura layers for fixed Group slots.",
                        "Fixed Tracked Buff sorting ownership, immediate Group preview border refreshes and rounded borders overwriting active Aggro or Dispel test colors.",
                        "Kept reload-required popups above the Options window, expanded clipped Unit Frame Basics sections and clarified the disabled Options-module error.",
                        "Fixed the CPU spike when an Arena match starts.",
                        "Group Frames preserve raid groups without overwriting the configured sort mode.",
                        "Fixed external-defensive aura filters on Classic clients and kept only-mine auras filtered out of range checks.",
                        "Isolated the Classic aura backend load graph from the Mainline manifest.",
                        "Reused cached absorb protection state and prebuilt alias scan lists on prediction and aura hot paths.",
                        "Fixed gameplay mover offsets drifting on scaled anchors and the combat timer not being movable while its position was unlocked.",
                        "Aura scanning respects Blizzard's instanced-content restrictions instead of erroring and, on clients that expose secret-state restrictions, reports how many auras are hidden.",
                        "Player Castbar terminal handling now ignores false interrupted or failed events without a real cast while retaining interrupt feedback when the client stops a cast before delivering its interrupted result.",
                        "Focus interrupt and cast trackers reinitialize after the active profile and frames become available during startup, follow the icon lifecycle and clear stale Focus cast ownership when the combined display is disabled.",
                        "Party Frames honor the configured Units per column and Max columns values instead of forcing a single secure column, including future combat-safe secure-header capacity.",
                        "Live Party, Raid and Mythic Group Frame blocks clamp their actual rendered footprint across scale and anchor combinations without rewriting SavedVariables; unavailable protected geometry fails closed.",
                        "Party-style Arena Group Frames fail open to Blizzard's secure roster while the Arena or Shuffle roster is temporarily incomplete instead of publishing an unusable partial name list.",
                        "Group Range Fade re-queries the bound member on native range events in PvP instances and refreshes its event route when the instance context changes.",
                        "Unit Range Fade reuses unchanged poll sets across movement and identity edges instead of rebuilding or duplicating scheduler work.",
                        "Player Power current-value text retains its resolved resource identity through form, vehicle and explicit Mana handoffs.",
                        "The Player Resting indicator refreshes when its frame becomes visible after a hidden zoning transition without adding polling or permanent update work.",
                        "Aura-name fallback scans coalesce to one pending unit scan and skip update-only, removal-only and already-resolved updates that cannot benefit from another alias scan.",
                        "Heal-prediction stripes use a specialized full-health path and avoid redundant secret checks and overflow work.",
                        "Assistant ambiguity handling fails closed for conflicting colors, cross-frame wording, contradictory movement, partial compound commands and misleading numbers in control labels instead of applying unrelated settings.",
                        "Exact setting, location and purpose questions outrank generic concept guidance so profile-copy, Aura, status-indicator, castbar and frame-specific requests reach their precise owner.",
                        "Safe Assistant questions preserve their original polarity and capability intent across page-context routing instead of becoming setting changes.",
                        "Read-only Assistant requests stay off broad mutation indexes, explicit numeric movement remains on bounded routes, and clarification choices survive repeated classification.",
                        "The Assistant's unloaded-Menu Group copy path mirrors native chunked health and power fill fields while excluding anchor and migration-only state.",
                        "On Mainline, exact-ID group buffs remain available on follower-dungeon Party NPCs under Blizzard's group-member identity contract instead of being hidden by the old assist gate.",
                        "Durationless curated states such as Shroud recipient membership bypass generic Hide Permanent and Maximum Duration restrictions, while every other Group Aura filter keeps the saved restrictions.",
                        "Exact-ID candidate filters are installed before any broad native filter transition, avoiding an intermediate unrestricted Helpful-aura refresh.",
                        "State Tint controls appear and disappear immediately when their master toggles change instead of requiring the Colors page to be reopened.",
                        "Assistant queues, history, undo, pending choices, workflows and deferred callbacks are isolated to the profile that created them, preventing stale work from crossing a profile switch or conversational context.",
                        "Immediate and deferred Assistant mutations share one failure-recovery path so partial work rolls back consistently.",
                        "General Aura guidance no longer competes with frame-local Aura owners, and question-shaped duration-filter requests retain their safe executable choices.",
                        "Opening Unit Frame Power settings no longer errors while building the detached-bar Text on detached bar control.",
                        "Health gradients, texture changes, prediction refreshes, Group Range Fade and Boss Preview preserve the configured health and prediction opacity instead of resetting fills to full opacity.",
                        "Detached Player Power bars attached or width-synced to Class Resources keep using the controller-maintained hidden anchor, preventing width or position jumps when shapeshifting hides the visible Class Resource bar.",
                    },
                },
            },
        },
    },
}

ns.MSUF_FullChangelog = data
ExportPublic("MSUF_FullChangelog", data)
