-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-Beta7",
    previousVersion = "6.0-Beta6",
    rangeLabel = "6.0-Beta6 -> 6.0-Beta7",
    entries = {
        {
            version = "6.0-Beta7",
            date = "2026-07-09",
            sections = {
                {
                    title = "UFCore Rewrite",
                    bullets = {
                        "Moved the unit-frame backend behind the embedded MSUF_UFCore loader and removed the old broad dispatch module from the main runtime path.",
                        "Reworked unit-frame, group-frame, health, power, text, border, status, load-condition, and factory runtime code around direct Core-owned frame APIs.",
                        "Updated the TOC and XML load order so UFCore owns unit-frame elements, factory setup, and group-frame runtime loading.",
                        "Preserved compatibility bridges for existing feature modules while routing live frame lookup through MSUF.UF and MSUF.GF.",
                    },
                },
                {
                    title = "Performance And Runtime",
                    bullets = {
                        "Routed hot unit events through direct frame handlers instead of the old broad dispatch path.",
                        "Reduced normal menu and Assistant apply work by targeting UFCore scopes and dirty masks instead of forcing broad full-frame updates.",
                        "Added opt-in Auras3 performance tracing with /msufa3trace tooling for focused aura profiling.",
                        "Added diagnostics and rewrite notes for UFCore connection audits, click-spike tracing, and coldpath/hotpath migration checks.",
                        "Kept click and secure-frame diagnostics out of the default hotpath unless explicitly invoked.",
                    },
                },
                {
                    title = "Auras",
                    bullets = {
                        "Core feature restored: the Aura Designer is usable again, including healer-focused aura and spell-indicator setup.",
                        "Reconnected Auras3 to UFCore frame resolution and scoped apply paths for unit, target, focus, boss, pet, and group lanes.",
                        "Added separate tooltip controls for buff and debuff lanes.",
                        "Improved target/focus aura refresh behavior and native aura-container rebuild handling.",
                        "Added tracked group-buff lane support backed by spell-indicator data.",
                        "Added Auras3 spell-indicator runtime support for 12.1 CustomAuraContainer aura slots.",
                        "Improved aura include/exclude spell-ID filtering, candidate signatures, and native filter handling.",
                    },
                },
                {
                    title = "Group Frames And Spell Indicators",
                    bullets = {
                        "Restored spell-indicator data load order for group frames inside the UFCore group embed.",
                        "Added tracked-buff compilation from selected spell-indicator specs and enabled spell-indicator-driven tracked aura lanes.",
                        "Improved group aura defaults, lane configuration, tooltip behavior, and external defensive filtering.",
                        "Updated group indicator Assistant actions, page wiring, and search routing for the new tracked aura/spell-indicator paths.",
                        "Improved group preview rendering for aura lanes, spell-indicator placements, and handle interactions.",
                    },
                },
                {
                    title = "Menu2, Assistant, And Search",
                    bullets = {
                        "Updated Menu2 apply service, bindings, pages, and Assistant registries to use scoped UFCore apply routes.",
                        "Improved Assistant aura parsing, aura group-lane routing, and dashboard/status selector coverage.",
                        "Added menu controls for frame-border strata and exposed the matching Global Bars control.",
                        "Updated Menu2 aura, group aura, group indicator, and global bar pages for the new Aura3 and group tracked-buff options.",
                        "Improved Menu2 search keywords, FAQ routing, and support text for the new aura and spell-indicator workflows.",
                        "Added and localized new user-facing labels for the spell-indicator and tooltip reset flows.",
                    },
                },
                {
                    title = "Castbars, Class Power, And Integrations",
                    bullets = {
                        "Connected castbars, boss castbars, player castbar runtime, class power, and gameplay hooks to UFCore-first frame lookup.",
                        "Updated previews and edit-mode interactions for castbars, class power, auras, group frames, and unit frames.",
                        "Kept castbar and class-power live event paths external and direct while refreshing visuals through UFCore callbacks.",
                        "Updated third-party anchor integration and runtime color/font/texture helpers for the UFCore rewrite.",
                    },
                },
                {
                    title = "Visuals And Previews",
                    bullets = {
                        "Updated Edit Mode movers, popups, HUD, and layout handling for UFCore-backed frames.",
                        "Updated unit and group previews to resolve live frames through UFCore and render updated aura, castbar, class-power, text, and group layers.",
                        "Replaced frame-border level-offset behavior with frame-border strata selection for more predictable overlay layering.",
                        "Improved rounded-frame, border, highlight, alpha, portrait, and status element integration with scoped UFCore refreshes.",
                    },
                },
                {
                    title = "What To Test First",
                    bullets = {
                        "Rapid target and focus swaps with buffs, debuffs, tracked buffs, tooltips, and cooldown text enabled.",
                        "Party, raid, and mythic raid group auras, especially spell-indicator tracked buffs and external defensive filters.",
                        "Group indicator setup, Assistant commands for spell indicators, and Menu2 search routing for aura/group-aura settings.",
                        "Frame-border strata on unit and group frames across normal UI, previews, and Edit Mode.",
                        "Castbar, class power, rounded-frame, and third-party-anchor behavior after profile swaps and /reload.",
                        "/msufa3trace, /msufclickcore, and UFCore diagnostics only when explicitly testing performance.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta6",
            date = "2026-07-06",
            sections = {
                {
                    title = "Bug Fixes",
                    bullets = {
                        "Fixed auras not refreshing on target and focus swaps, which could leave the previous unit's buffs and debuffs showing on the new unit.",
                        "Restored the proven forced aura refresh on every target/focus identity change so the native aura container always reparses for the new unit instead of skipping the rebuild when the applied config looked unchanged.",
                    },
                },
                {
                    title = "Performance Highlights",
                    bullets = {
                        "Added a direct frame event path for RegisterUnitEvent-owned frames so hot unit events run their prebuilt handler immediately instead of going through the broad event router, removing the redundant re-derivation of which frame an event belonged to.",
                        "Added an Ellesmere-style value hot path that bakes the exact health and power work into one closure per frame and event, so value ticks skip the generic runner layer.",
                        "Added a percent-only health path for single frames (target, focus, boss, pet) that uses one UnitHealthPercent call and skips UnitHealth, UnitHealthMax, and store bookkeeping, so a boss target taking sustained damage costs far less per health tick.",
                        "Added direct group-frame health and power dispatch for frequent value updates.",
                    },
                },
                {
                    title = "Runtime Optimizations",
                    bullets = {
                        "Single-frame health color is now re-resolved only on identity, flag, and faction changes and deduplicated on plain health ticks, so target swaps stay correct without per-tick color work.",
                        "Removed a legacy value-handler baker that a profiling session proved never produced a real health or power handler in practice; value events still run correctly through the unified path.",
                        "Added distinct profiling labels for the direct event path so /msufprof shows whether the lean dispatch actually ran.",
                    },
                },
                {
                    title = "What To Test First",
                    bullets = {
                        "Rapid target and focus swapping, including quick swaps with multiple visible buff and debuff lanes, to confirm auras always update for the new unit.",
                        "Target-of-target and focus-target aura and health behavior.",
                        "Boss, target, focus, and pet health under sustained damage, and health bar color on target swaps between players, NPCs, and different reactions.",
                        "Frequent group health and power changes in party and raid layouts.",
                        "/msufprof fast-path, lean-event, and identity diagnostic output.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta5",
            date = "2026-07-05",
            sections = {
                {
                    title = "Performance Highlights",
                    bullets = {
                        "Added lean Target, Focus, and target-of-target identity refreshes that use prebaked element update lists instead of the full runtime wrapper path.",
                        "Added lean per-unit event dispatch for hot unit events so filtered unit trackers can call compiled frame handlers directly.",
                        "Added direct group-frame health dispatch to reduce overhead on frequent health updates.",
                        "Retired inactive group-frame runtime work when party, raid, or mythic raid frames are disabled or not active for the current roster state.",
                    },
                },
                {
                    title = "Runtime Optimizations",
                    bullets = {
                        "Reduced target/focus swap cost by skipping redundant visibility rebuilds and avoiding unnecessary player-only or NPC-only status API checks.",
                        "Reduced group-frame background event work by unregistering name, roster, and Blizzard fallback listeners when group runtime is inactive.",
                        "Tightened targeted-spell refreshes so party-only state is not recalculated for unrelated group-frame updates.",
                        "Added profiling diagnostics for identity refreshes and fast-path dispatch verification.",
                    },
                },
                {
                    title = "What To Test First",
                    bullets = {
                        "Rapid target and focus swapping, including target-of-target and focus-target frames.",
                        "Frequent group health changes in party and raid layouts.",
                        "Enabling, disabling, and switching Party/Raid/Mythic Raid frames, including solo and inactive roster states.",
                        "/msufprof fast-path, detail, and identity diagnostic output.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta4",
            date = "2026-07-05",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Refreshed the Menu2 visual shell with stronger contrast, updated panel textures, clearer navigation states, and improved window controls.",
                        "Added MSUF menu font selection.",
                        "Added per-slot percent-symbol controls for unit-frame, group-frame, and Class Resource text.",
                        "Improved unit and group previews so visible layers, pinned previews, zoom, and snap behavior are more reliable.",
                        "Improved fresh-install and profile-reset handling so the bundled factory profile is applied more consistently.",
                    },
                },
                {
                    title = "Menu And Preview",
                    bullets = {
                        "Updated Menu2 panel, rail, popup, status, and navigation textures.",
                        "Improved Menu2 window snapping, minimize/restore handling, close cleanup, and combat-entry cleanup.",
                        "Improved pinned preview stability when switching pages or closing the menu.",
                        "Improved unit preview fitting for text, status icons, portrait, power, castbar, auras, and class-resource layers.",
                        "Improved group preview layer controls, hover hints, disabled-layer visuals, and restore placement.",
                        "Reset preview zoom and pan when non-guide layers are toggled so changed layers stay visible.",
                        "Reduced menu and Assistant warmup work during normal menu use.",
                    },
                },
                {
                    title = "Unit Frames And Text",
                    bullets = {
                        "Added per-slot percent-symbol visibility for health and power text.",
                        "Added menu and Assistant support for the new percent-symbol text controls.",
                        "Improved NPC type coloring for health bars, name text, and inline target-of-target names.",
                        "Updated NPC type colors when unit classification changes.",
                        "Improved safe handling for protected/secret unit values in color and text logic.",
                        "Reduced redundant unit-frame identity, power text, and aura identity refresh work.",
                    },
                },
                {
                    title = "Group Frames And Edit Mode",
                    bullets = {
                        "Improved Party Targeted Spell Indicator performance.",
                        "Improved group-frame preview and Edit Mode placement for large party, raid, and mythic raid layouts.",
                        "Kept group-frame preview anchors clamped to screen bounds without forcing large layouts into bad positions.",
                        "Fixed mover and popup geometry issues in Edit Mode.",
                        "Stopped motion previews and menu preview interactions more cleanly when combat starts.",
                    },
                },
                {
                    title = "Assistant And Recovery",
                    bullets = {
                        "Added a frame recovery workflow for restoring hidden or misplaced frames.",
                        "Improved Assistant handling for percent-symbol visibility requests.",
                        "Improved Assistant setting search, exact aliases, follow-up parsing, and dashboard/changelog answers.",
                        "Improved Assistant-facing labels and setting registry coverage for text and group-frame options.",
                    },
                },
                {
                    title = "Profiles And Defaults",
                    bullets = {
                        "Improved fresh-install detection when early startup modules already created small bootstrap database buckets.",
                        "Preserved exported factory-profile values while filling only missing structural defaults.",
                        "Initialized the active profile before Menu2, gameplay settings, and previews read MSUF_DB.",
                        "Refreshed preview runtime specs after profile swaps or resets so previews do not use stale profile data.",
                    },
                },
                {
                    title = "What To Test First",
                    bullets = {
                        "Menu2 window controls, snapping, minimize/restore, and close behavior.",
                        "Menu font selection and the refreshed Menu2 styling.",
                        "Unit-frame, group-frame, and Class Resource percent-symbol toggles.",
                        "NPC type colors on target, focus, boss, and target-of-target text.",
                        "Group-frame preview placement with large party, raid, and mythic raid layouts.",
                        "Frame recovery workflow from the Assistant.",
                        "Fresh install, profile reset, and profile swap behavior.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
