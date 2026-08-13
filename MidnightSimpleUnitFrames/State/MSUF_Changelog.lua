-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.5-alpha3",
    previousVersion = "6.5-alpha2",
    rangeLabel = "6.5-alpha2 -> 6.5-alpha3",
    entries = {
        {
            version = "6.5-alpha3",
            date = "2026-08-13",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Synchronized the unified Mainline, Mists, TBC and Vanilla package with the MSUF 6.04 feature and fix set while retaining client-specific API owners.",
                        "Reworked Unit Frame Auras around explicit lane ownership. Buff and Debuff lanes now own their layout, filtering, text, effects and visibility, while icon appearance remains global by Aura type across runtime, Menu, Edit Mode, search and the Assistant.",
                        "Expanded Assistant control of Absorb, Heal Absorb, Heal Prediction and Maximum Health Loss bars, including natural comparative requests such as making an overlay stronger, softer or more transparent.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added a profile-specific option to disable Northern Sky Raid Tools nicknames on MSUF frames without changing NSRT itself. The integration remains enabled by default.",
                        "Added the shared All Specs Group Spell Indicator workspace, curated Big Defensive filtering and direct Full-Frame Aura Effect control.",
                        "Refreshed the generated Assistant schema and complete Menu search index for the synchronized controls.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Reduced recurring Health and Texture Layer work by coalescing pending updates, refreshing only affected texture slots and reusing runtime objects.",
                        "Fixed Elite, Rare Elite, Rare and Boss classifications in Unit Frame previews and kept runtime and preview icons on one shared position.",
                        "Fixed incomplete Raid roster name data omitting members, restored live Group frames after preview handoffs and honored configured Aura layers for fixed Group slots.",
                        "Fixed Tracked Buff sorting ownership, immediate Group preview border refreshes and rounded borders overwriting active Aggro or Dispel test colors.",
                        "Kept reload-required popups above the options window, expanded clipped Unit Frame Basics sections and clarified the disabled Options-module error.",
                    },
                },
            },
        },
        {
            version = "6.5-alpha2",
            date = "2026-08-11",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Brought the unified Mainline, Mists, TBC and Vanilla package up to feature parity with MSUF 6.01 plus the current post-release fixes. Client-specific ClassPower owners remain separated by TOC, while shared profiles, menus, previews and Assistant controls use the same contracts.",
                        "Reworked the upgrade highlight tour around the real navigation history feature. Back and Forward are introduced first, their menu arrows pulse prominently while that page stays active, and the local Assistant can replay a skipped tour from requests such as start the highlight tour or restart the tour.",
                        "Expanded Texture Layers with target-only accents, source-color treatments, crop and mirror controls, rounded clipping and matching Unit Preview controls.",
                        "Added rounded Class Resources, safe alternative-mana width and X-offset controls, native Ebon Might duration text on Mainline, and protected-value-safe ClassPower text and Player-health handling.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Updated the Auras menus to describe the current Unit Frame and Group Frame workspaces directly, with shorter upgrade-highlight copy and more styling controls on the Auras page.",
                        "Added the animated Blizzard resting symbol to the shared status model and fresh profile defaults. Mainline uses the native flipbook atlas; Classic clients detect that the atlas is unavailable and fall back to the existing static resting icon.",
                        "Extended debuff-blacklist presets and clarified that blacklist choices apply only to the selected lane and frame scope.",
                        "Split Unit Preview Buff and Debuff strata, rebuilt the correct Aura lane after handle clicks and aligned castbar spell/time positioning with runtime.",
                        "Improved nickname-provider refreshes so unit-aware providers update the correct Unit and Group Frames without periodic polling.",
                        "Distinguished true outline geometry from texture borders and exposed the matching controls and previews.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed manual detached Power width being overwritten by automatic geometry.",
                        "Fixed Boss preview initialization before portrait refresh and kept mouseover outline colors current after style changes.",
                        "Fixed Unit copy actions bypassing their action guard and added the missing Castbar copy path.",
                        "Fixed rounded Texture Layer and preview edges being clipped, and refreshed target-dependent visibility on UNIT_TARGET.",
                        "Fixed restricted ClassPower values hiding text that can still be rendered safely, including native Ebon Might duration text.",
                        "Refreshed Assistant, search and generated menu inventories for the new controls and replay-tour commands.",
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
