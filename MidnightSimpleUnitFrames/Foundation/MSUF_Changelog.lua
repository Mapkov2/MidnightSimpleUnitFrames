-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.52",
    previousVersion = "5.4",
    rangeLabel = "5.4 -> 5.52",
    entries = {
        {
            version = "5.52",
            date = "2026-05-23",
            sections = {
                {
                    title = "Critical Fixes",
                    bullets = {
                        "Fixed the Dashboard Edit frames button so it no longer calls private Menu2 core helpers that are not visible from the dashboard module.",
                        "Restored the dashboard Edit Mode toggle path while keeping the existing combat-lock handling and menu frame priority refresh.",
                    },
                },
            },
        },
        {
            version = "5.51",
            date = "2026-05-22",
            sections = {
                {
                    title = "Critical Fixes",
                    bullets = {
                        "Fixed a critical edge case where selected debuff dispel-type filters could hide unrelated debuffs globally instead of only narrowing the dispellable-debuff exception.",
                        "Fixed Aura Filters menu checkbox hitboxes and labels so the dispel and include toggles are easier to click and only active when they affect the current filter setup.",
                    },
                },
            },
        },
        {
            version = "5.5",
            date = "2026-05-22",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Reworked the Castbar Menu with dedicated live previews for Player, Target, Focus, and Boss castbars, including normal casts, channels, empowered casts, interrupt states, latency, spark, glow, icons, spell text, and cast time.",
                        "Reworked the Unit Auras setup page around a clearer first-pass workflow with Essentials, Scope, presets, view modes, visible-unit toggles, reset actions, and a live aura preview.",
                        "Fully reworked Dispel / Debuff Overlay and border highlights for Unit Frames and Group Frames around one visible Highlight Priority model.",
                        "Added persistent Menu2 memory so the menu remembers opened cards, selected tabs, pinned previews, page state, color picker choices, and other recent selections.",
                        "Added per-indicator icon pack selection for Unit Frame and Group Frame status indicators, including bundled UX Pro icons and support for external replacement packs.",
                    },
                },
                {
                    title = "Menu2 and UX",
                    bullets = {
                        "Improved Menu2 search so it also works as an ask-style field for questions like where to move frames, change fonts, adjust inline text colors, or disable group frames.",
                        "Added broader English and German search handling, better direct-control ranking, and a first-use Search / Ask intro popover.",
                        "Improved compact menu layouts for scaled or narrow UI setups so sliders, switches, edit boxes, previews, and layout toggles clamp cleanly instead of overlapping.",
                        "Fixed a Menu2 preview helper load error caused by ambiguous Lua function-call syntax when creating rounded masks.",
                        "Improved Group Frame disable/search wording so party and raid frame questions point directly to the Use MSUF group frames switch and Blizzard fallback dropdown.",
                    },
                },
                {
                    title = "Castbars",
                    bullets = {
                        "Rebuilt the Global Castbars page around a more accurate preview surface that follows runtime sizing, per-unit match-width behavior, fill direction, channel ticks, empower stages, latency, spark, glow, icon visibility, spell text, cast time, and interrupt shake.",
                        "Added per-castbar time format controls for Player, Target, Focus, and Boss castbars.",
                        "Improved castbar preview fidelity so menu previews line up with runtime width, height, text placement, icon placement, and cast-time rendering more closely.",
                        "Split Boss Castbar preview/edit-mode behavior away from runtime boss cast handling.",
                        "Reduced idle work in the castbar and interrupt-ready paths through tighter event gating, cached checks, and safer apply scheduling.",
                    },
                },
                {
                    title = "Unit Frames and Group Frames",
                    bullets = {
                        "Added Group Frame Blizzard fallback mode for layouts that should let Blizzard own the secure group frame path.",
                        "Fixed Group Frame disabled fallback ownership so Blizzard only takes over when all MSUF group-frame scopes are off, while active MSUF party, raid, or mythic raid scopes keep Blizzard group frames hidden.",
                        "Added status icon Advanced tabs with extended offsets, layer controls, reset actions, test mode, and preview actions.",
                        "Added Group Frame options to hide name text while units are dead or offline.",
                        "Moved heal prediction controls into the Bars pages and improved Group Frame heal prediction and absorb test rendering.",
                        "Added a global Bar Outline Color for Unit Frames and Group Frames while keeping aggro, purge, dispel, and other indicator colors independent.",
                        "Improved Unit Frame and Group Frame outline rendering so detached, active, preview, live, and pixel-snapped borders use consistent outside-outline behavior.",
                        "Added configurable Target-of-Target inline text color modes: Auto, ToT Name Color, Target Name Color, NPC / Type Color, and Default Font Color.",
                        "Improved Group Frame HP text handling, including reverse-order HP text, stable centered HP text, and font outline updates.",
                        "Fixed Group Frames Buffs & Debuffs text-option layout so cooldown and stack text controls can expand instead of being clipped.",
                    },
                },
                {
                    title = "Dispel, Debuff Overlay, and Highlights",
                    bullets = {
                        "Rebuilt Unit Frame and Group Frame dispel priority around one visible Highlight Priority order: Dispel, Aggro, Purge, Boss Target, Target, and Focus.",
                        "Migrated legacy Magic, Curse, Disease, Poison, and Bleed custom sorting into the single Dispel visual lane.",
                        "Kept Dispel Border and Dispel Overlay independently configurable while sharing the same resolved debuff winner.",
                        "Improved Any Debuff, Any Dispel Type, typed color mode, typed priority order, and Bleed handling so the highest-priority debuff is selected consistently.",
                        "Added renderer-independent Group Frame dispel highlights so priority visuals still work when Blizzard owns aura icons.",
                        "Improved cleanup for reused Group Frames so stale dispel, debuff, status, highlight, and aura state cannot leak into newly assigned units.",
                    },
                },
                {
                    title = "Auras and Performance",
                    bullets = {
                        "Improved Auras2 performance by caching dispel metadata, tracking structural aura changes, and avoiding repeated filter/sort work when aura structure and configuration are unchanged.",
                        "Reduced Auras2 event and render overhead when unit aura modules are disabled, including stronger cleanup of inactive containers and private aura state.",
                        "Improved handling for stealable buffs when mine-only, important-buff, and merged buff filters are active.",
                        "Improved aura delta handling so priority-based dispel visuals rescan only when relevant aura data can change.",
                        "Fixed Unit Frame range alpha background bleed and kept Sated aura threshold filters fresh after aura rule changes.",
                        "Fixed a Range Fade protected-call warning by keeping the CheckInteractDistance fallback out of combat while preserving spell-based range checks and out-of-combat fallback behavior.",
                    },
                },
                {
                    title = "Stability and Fixes",
                    bullets = {
                        "Restored the previous MSUF keybind synchronization behavior and removed the newer account-wide SaveBindings / LoadBindings path to avoid a reload-only keyboard input edge case.",
                        "Added /msuf inputdebug to help diagnose rare keyboard focus or input-capture issues.",
                        "Reset keyboard input propagation when MSUF edit-mode popups, HUD panels, and picker overlays hide.",
                        "Refreshed runtime systems after profile switch, reset, import, and external profile overwrite so frames, auras, class power, powerbar embeds, and portrait decorations update without stale state.",
                        "Improved Class Power hidden-anchor handling and powerbar embed anchoring when class power is disabled or hidden.",
                        "Improved portrait decoration layout recovery when portrait containers are rebuilt or their anchor points change.",
                        "Reduced idle work in castbar, interrupt-ready, aura, range-fade, gameplay apply, target-swap, and boss castbar runtime paths.",
                    },
                },
                {
                    title = "Localization and Internals",
                    bullets = {
                        "Added German labels for the new Target-of-Target inline color options.",
                        "Expanded localization coverage for Menu2 search, Castbar, Group Frame, and changelog strings.",
                        "Split several large runtime and Menu2 files into focused modules for search data, dropdown helpers, preview helpers, widgets, dashboard, Group Frame effects, Auras2, Target-of-Target inline text, frame previews, totem previews, Class Power, and Boss Castbar previews.",
                        "Updated release tooling so release packages and changelogs are generated more consistently.",
                    },
                },
            },
        },
        {
            version = "5.41",
            date = "2026-05-21",
            sections = {
                {
                    title = "Patch Release",
                    bullets = {
                        "Restored the 5.32 MSUF keybind synchronization behavior and removed the new account-wide SaveBindings / LoadBindings path to avoid a reload-only keyboard input edge case where movement could become unresponsive until the game client was restarted.",
                        "Added /msuf inputdebug to print movement bindings, keyboard focus, MSUF edit state, and visible keyboard-enabled frames when diagnosing rare input-capture issues.",
                        "Reset keyboard input propagation when MSUF edit-mode popups, HUD panels, and picker overlays hide, so ESC-handled overlays cannot leave stale keyboard capture state behind.",
                        "Improved Auras2 handling for stealable buffs when mine-only, important-buff, and merged buff filters are active.",
                        "Refreshed runtime systems after profile switch, reset, import, and external profile overwrite so unit frames, auras, class power, powerbar embeds, and portrait decorations update without stale state.",
                        "Hardened Group Frame unit-slot cleanup during roster changes so stale debuff, dispel, status, highlight, and displayed-aura state cannot bleed into the next unit assigned to the same secure button.",
                        "Improved Class Power hidden-anchor handling and powerbar embed anchoring when class power is disabled or hidden.",
                        "Improved portrait decoration layout recovery when portrait containers are rebuilt or their anchor points change.",
                    },
                },
            },
        },
        {
            version = "5.4",
            date = "2026-05-21",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Reworked the Castbar Menu with a dedicated live preview for Player, Target, Focus, and Boss castbars, including normal casts, channels, empowered casts, and interrupt preview states.",
                        "Added persistent Menu2 memory so the menu remembers what you last opened or selected across rebuilds and reopening.",
                        "Fully reworked Dispel / Debuff Overlay and border highlights for Unit Frames and Group Frames around one visible Highlight Priority model.",
                    },
                },
                {
                    title = "Castbars",
                    bullets = {
                        "Rebuilt the Global Castbars page around a more accurate preview surface that follows runtime sizing, per-unit match-width behavior, fill direction, channel ticks, empower stages, latency, spark, glow, icon visibility, spell text, cast time, and interrupt shake.",
                        "Added per-castbar time format controls for Player, Target, Focus, and Boss castbars.",
                        "Improved castbar preview fidelity for Player, Target, Focus, and Boss so menu previews line up with runtime width, height, text placement, icon placement, and cast-time rendering more closely.",
                        "Split Boss Castbar preview/edit-mode behavior away from runtime boss cast handling.",
                        "Reduced idle work in the castbar and interrupt-ready paths through tighter event gating, cached checks, and safer apply scheduling.",
                    },
                },
                {
                    title = "Menu2 and UX",
                    bullets = {
                        "Menu2 now persists accordion/card open states, pinned previews, dashboard panels, page selectors, tabs, selected scopes, color pickers, profile import/export choices, and other last-clicked menu state.",
                        "Improved Menu2 search so the search field also works as an \"ask\" field for location-style questions such as where to move frames, change fonts, or adjust inline text colors.",
                        "Added broader English and German question handling, better direct-control ranking, a first-use Search / Ask intro popover, and localized search coverage improvements.",
                        "Reduced menu search and navigation overhead by cancelling unused background indexing, rebuilding search records only when needed, and skipping redundant title, subtitle, status-bar, navigation, and result refreshes.",
                        "Improved compact menu layouts for scaled or narrow UI setups so sliders, switches, edit boxes, gameplay controls, group previews, and layout toggles clamp cleanly instead of overlapping.",
                        "Added live party and raid previews while editing Group Frame bar settings without taking over the normal Edit Mode group preview state.",
                        "Made MSUF keybinds account-wide and cleaned up quick setup styling for Class Bar actions.",
                    },
                },
                {
                    title = "Dispel, Debuff Overlay, and Highlights",
                    bullets = {
                        "Rebuilt Unit Frame and Group Frame dispel priority around one visible Highlight Priority order: Dispel, Aggro, Purge, Boss Target, Target, and Focus.",
                        "Collapsed legacy Magic, Curse, Disease, Poison, and Bleed custom sorting into the single Dispel visual lane and migrated old overlay/debuff priority settings across saved profiles.",
                        "Kept Dispel Border and Dispel Overlay independently enabled and configured while sharing the same resolved debuff winner, so border-only, overlay-only, and combined setups behave consistently.",
                        "Improved Any Debuff, Any Dispel Type, typed color mode, typed priority order, and Bleed handling so the highest-priority debuff is selected consistently.",
                        "Added renderer-independent Group Frame dispel highlights so MSUF can still draw priority visuals when Blizzard owns aura icons, while custom aura rendering uses the same priority path.",
                        "Added separate effect layers for highlight borders, dispel overlays, and debuff stripes so active visual lanes stack predictably.",
                        "Reduced redundant border, glow, overlay, color, reverse-fill, and status-bar updates with settings, aura-version, priority-signature, color-revision, and unit-guid cache guards.",
                        "Improved cleanup for retired or reused Group Frames so stale dispel/debuff visuals cannot leak into newly assigned units.",
                    },
                },
                {
                    title = "Unit Frames and Group Frames",
                    bullets = {
                        "Added per-indicator icon pack selection for Unit Frame and Group Frame status indicators.",
                        "Added status icon Advanced tabs with extended offsets, layer controls, reset actions, test mode, and preview actions.",
                        "Added bundled UX Pro status icons and support for external Interface\\Icons replacement packs.",
                        "Improved status icon texture resolution across aura previews, aura rendering, healer buffs, spell indicators, focus kick icons, and dropdown previews.",
                        "Added a separate Show Cooldown Swipe control for icon-style Group Frame Spell Indicators.",
                        "Added Group Frame options to hide name text while units are dead or offline.",
                        "Moved heal prediction controls into the Bars pages and improved Group Frame heal prediction / absorb test rendering.",
                        "Added a global Bar Outline Color for Unit Frames and Group Frames while keeping aggro, purge, dispel, and other indicator colors independent.",
                        "Improved Unit Frame and Group Frame outline rendering so detached, active, preview, live, and pixel-snapped borders use consistent outside-outline behavior.",
                        "Added configurable Target-of-Target inline text color modes: Auto, ToT Name Color, Target Name Color, NPC / Type Color, and Default Font Color.",
                        "Improved Target preview rendering and runtime Target-of-Target inline color resolution for class colors, target-name colors, NPC reaction colors, NPC type colors, and default font colors.",
                        "Added Group Frame Blizzard fallback mode for layouts that should let Blizzard own the secure group frame path.",
                        "Improved Group Frame HP text handling, including reverse-order HP text, stable centered HP text, and font outline updates when face and size stay unchanged.",
                        "Fixed Unit Frame range alpha background bleed and kept Sated aura threshold filters fresh after aura rule changes.",
                    },
                },
                {
                    title = "Auras and Performance",
                    bullets = {
                        "Improved Auras2 performance by caching dispel metadata, tracking structural aura changes with epochs, and avoiding repeated filter/sort work when aura structure and configuration are unchanged.",
                        "Reduced Auras2 event and render overhead when the feature or all unit aura modules are disabled, including harder cleanup of inactive containers and private aura state.",
                        "Improved aura delta handling for added, updated, and removed debuffs so priority-based dispel visuals rescan only when relevant aura data can change.",
                        "Improved range-fade stability and cost by repairing unchanged layered alpha less often while still clearing stale fade state when range becomes unknown.",
                        "Refined low-risk runtime paths for aura commits, target-swap visuals, gameplay apply scheduling, crosshair target callbacks, and boss castbar event registration.",
                    },
                },
                {
                    title = "Localization",
                    bullets = {
                        "Added German labels for the new Target-of-Target inline color options.",
                        "Expanded runtime localization coverage for the new Menu2 search, Castbar, Group Frame, and changelog strings.",
                    },
                },
                {
                    title = "Under the Hood",
                    bullets = {
                        "Refactored the Group Frame effects runtime into focused modules for text, aura effects, range/threat, events, cleanup, highlights, status/offline handling, frame cache, and tooltip/mouseover behavior.",
                        "Refactored Auras2 into clearer cache, collection, icon, layout, Masque, cooldown-text, render, reminder, event, and edit-mode responsibilities.",
                        "Split Target-of-Target inline widget logic into Core/MSUF_UFCore_ToTInline.lua.",
                        "Split preview/test-mode frame behavior into Core/MSUF_FramePreview.lua.",
                        "Split Blizzard Totem Preview handling into Features/MSUF_Gameplay_TotemPreview.lua.",
                        "Split ClassPower alternate mana and Balance Druid prediction into dedicated modules.",
                        "Split Boss Castbar preview handling into MidnightSimpleUnitFrames_Castbars/Modules/BossCastbars_Preview.lua.",
                        "Preserved public Group Frame APIs and diagnostic wrappers while moving hot-path work behind smaller internal modules.",
                        "Updated release tooling and Perfy documentation so temporary instrumented builds stay separate from normal release packages.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
