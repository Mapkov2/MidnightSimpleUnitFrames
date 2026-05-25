-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.53",
    previousVersion = "5.41",
    rangeLabel = "5.41 -> 5.53",
    entries = {
        {
            version = "5.53",
            date = "2026-05-26",
            sections = {
                {
                    title = "Critical Fixes",
                    bullets = {
                        "Fixed target, focus, and boss frame alpha/background recovery after combat so frames no longer need a target swap or reload to restore missing backgrounds.",
                        "Fixed post-combat range fade handling so combat end restores cached alpha/background state instead of running an expensive range scan or full alpha refresh.",
                        "Fixed group-frame range fade incorrectly fading the player/self frame by treating the player token and matching player GUID as always in range.",
                        "Fixed stale absorb, shield, and heal-absorb overlays that could stay visible after the target no longer had an active absorb or heal absorb.",
                        "Fixed group-frame secure-button recovery after login, reload, and party/raid changes so blank party or raid frames are reconciled without requiring /reload.",
                        "Fixed CDM/custom-anchor login timing so unit frames keep their cached screen position until Blizzard EditMode or the configured anchor is available, instead of saving wrong UIParent offsets.",
                        "Added a legacy no-op anchor for old Blizzard EditMode layouts that still reference EssentialCooldownViewer_MSA_Container, preventing repeated CDM SetPoint warnings after removing the old MSA dependency.",
                    },
                },
                {
                    title = "Menu and Preview Fixes",
                    bullets = {
                        "Fixed Buff Reminders checkboxes so the full label row is clickable again.",
                        "Fixed Global Ignore List checkboxes and the per-unit override toggle so their click areas match the visible controls.",
                        "Fixed Unit Auras scope/override clipping in compact or scaled menu layouts.",
                        "Fixed Group Frame Aura Display Mode clipping by making the Blizzard aura routing and layering controls responsive in narrow menu layouts.",
                        "Added a castbar size label to the Unit Frame preview so castbar width and height are visible while editing.",
                    },
                },
                {
                    title = "Performance and Stability",
                    bullets = {
                        "Kept alpha/range fixes cached and event-driven, avoiding broad post-combat frame sweeps.",
                        "Kept absorb and heal-absorb cleanup on the existing prediction update paths with secret-safe positive-value checks.",
                        "Improved post-login group-frame recovery through delayed live-frame reconciliation without adding constant polling.",
                        "Kept late anchor recovery event-driven with a short, finite retry window only for profiles that actually use CDM, custom, or unit-frame anchors.",
                    },
                },
            },
        },
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
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
