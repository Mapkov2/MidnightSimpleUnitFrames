-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "90D0D08F10D8B647D290BD9A9DC68B4781B850F01146E5B7A25401E655525E90",
    currentVersion = "6.5-alpha2",
    historyFromVersion = "6.0-RC17",
    previousVersion = "6.5-alpha1",
    rangeLabel = "6.5-alpha1 -> 6.5-alpha2",
    entries = {
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
        {
            version = "6.0-RC18",
            date = "2026-08-09",
            sections = {
                {
                    title = "Changes",
                    bullets = {
                        "Added a versioned nickname-provider API for Unit and Group Frames. Providers are priority ordered, cached, event-driven and deferred safely across combat; the bundled Northern Sky Raid Tools adapter now uses the same public contract.",
                        "Documented the supported Nickname and Edit Mode provider APIs for addon authors in the README.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Boss Frame health, power, background and border geometry moving or leaving the screen after a combat reload (#77). Pixel-snapped regions now remain attached to their secure frame owner.",
                        "Fixed Boss castbar spell-name shortening being ignored at runtime and in Edit Mode previews (#78), including the renderer-only path required for secret combat values.",
                        "Fixed Edit Mode always showing the Boss castbar leading-edge spark even when the setting was disabled (#79). The animation no longer overrides the cold style owner every tick.",
                        "Fixed detached Boss castbars appearing outside the Unit Preview (#80). The preview projects the applied runtime relationship without changing the saved absolute position.",
                        "Fixed Player Defensives being re-enabled by Menu normalization after the user disabled them. Runtime, Menu preview and Edit Mode now honor the same master switch, while tracked Target DoTs keep their disabled configuration preview.",
                        "Fixed Player search routes treating the layer substring inside player as a Text section request. Portrait and other exact results no longer open an unrelated accordion or rebuild the page unnecessarily.",
                        "Fixed explicit guided-setup phrases containing topics such as profiles being consumed by text creation guidance instead of opening the native guided setup.",
                    },
                },
            },
        },
        {
            version = "6.0-RC17",
            date = "2026-08-09",
            sections = {
                {
                    title = "Changes",
                    bullets = {
                        "Fresh and reset profiles now start from the native 6.0 Aura model. Focus Auras are enabled by default with 3 Buff and 4 Debuff slots, matching the useful Target/Boss baseline while keeping the Focus-specific placement.",
                        "Edit Mode X/Y fields now use one visual screen-center contract for Unit Frames, Castbars, Auras, Group Frames and external elements. Resizing an element keeps the displayed position stable.",
                        "Retired Assistant controls for old Auras2 reminders and incompatible quick presets now report that they are unavailable instead of accepting writes that cannot affect Auras3.",
                        "Classic accepts only 6.0 profile schema 600. Older or unversioned profiles are removed from the active profile list and kept in a recoverable SavedVariables archive instead of being migrated through the Retail 5.x compatibility path; legacy imports are rejected.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed legacy Unit and Group Aura fields being restored into current profiles. The one-time native-model repair removes retired state while preserving the visible first icon position and size for upgraded and imported profiles.",
                        "Fixed Aura layout and style ownership drifting between live frames, the menu, Edit Mode and the Assistant. Lane gaps, sorting, text, swipes, duration bars, tooltips and shared/per-frame overrides now read and write the same owner without reviving dormant values.",
                        "Fixed Dispel Border, Overlay and Symbol depending on another UnitFrame's Auras or a shared Bars owner. Each supported UnitFrame now owns its Dispel settings and automatically enables its Aura sensor; both icon caps may remain at 0.",
                        "Fixed Aura icons intercepting clicks. Only normal Player Buffs keep Right-click cancellation; every other Unit and Group Aura remains click-through while configured tooltips still work.",
                        "Fixed cooldown swipes being hidden or out of sync in menu and Edit Mode previews. Edit Mode now follows the existing menu animation clock, adds no second driver and remains paused in combat.",
                        "Fixed Copy To reporting success when nothing was copied or when Copy to All was cancelled. Unsupported Aura destinations are reported accurately, Player Defensive and Target DoT-only style fields stay with their product, and Group Spell Indicator caches are refreshed after a copy.",
                        "Fixed PvP indicator paths staying compiled after War Mode was disabled during its deactivation timer. Context recompiles remain event-driven and are skipped in combat.",
                        "Fixed Group Frame screen clamping adding a grid-size-dependent offset, so the same Anchor Point and X/Y identify the same position for Party and Raid.",
                        "Fixed stale Edit Mode SavedVariables making Player or Boss castbar previews reappear after logout or reload.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
