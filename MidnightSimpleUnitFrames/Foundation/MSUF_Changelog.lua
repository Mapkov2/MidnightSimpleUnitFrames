-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.4",
    previousVersion = "5.3",
    rangeLabel = "5.3 -> 5.4",
    entries = {
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
        {
            version = "5.32",
            date = "2026-05-18",
            sections = {
                {
                    title = "Patch Release",
                    bullets = {
                        "Fixed a group-frame Spell Indicators crash when linked aura rules, such as Restoration Druid Symbiotic Relationship, checked the scan ownership cache before it was in local scope.",
                        "Bundled the 5.31 and 5.3 release notes with this hotfix so the in-game changelog keeps the full recent release context.",
                    },
                },
            },
        },
        {
            version = "5.31",
            date = "2026-05-18",
            sections = {
                {
                    title = "Patch Release",
                    bullets = {
                        "Fixed a critical group-frame Preserve HP color crash in Midnight when background frame colors are returned as secret numbers.",
                        "Reverted the delayed range-fade alpha repair performance optimization so layered range alpha is repaired immediately again while range state is unchanged.",
                        "Bundled the full 5.3 release notes with this patch release so the in-game changelog still includes the complete 5.3 release.",
                    },
                },
            },
        },
        {
            version = "5.3",
            date = "2026-05-18",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added Focus Target as a new unit frame with its own settings, Edit Mode mover, Menu2 preview, copy targets, text options, status icons, and secure runtime refresh.",
                        "Added Rounded Frames through Global Style > Bars > Rounded Texture, with separate controls for unit frames, group frames, power bars, and mouseover highlights.",
                        "Reworked Dispel Border / Glow so it can be useful for every class, including classes without a defensive dispel.",
                        "Continued the Menu2 redesign with cleaner cards, better navigation, stronger search coverage, and clearer profile/menu workflows.",
                    },
                },
                {
                    title = "Focus Target",
                    bullets = {
                        "Added a dedicated Focus Target frame that appears when Focus is enabled and your focus has a target.",
                        "Integrated Focus Target into unit-frame defaults, secure show/hide state, live refreshes, Edit Mode, preview rendering, copy/apply actions, import/export handling, alpha controls, text settings, portraits, and indicators.",
                        "Kept Focus Target lightweight by default: it has health/name support like other unit frames, while power is off by default and castbars/auras remain out of scope for this frame.",
                        "Added Focus Target help/search text and menu safeguards so the frame clearly explains when Focus must be enabled first.",
                    },
                },
                {
                    title = "Rounded Frames",
                    bullets = {
                        "Added rounded mask media and runtime support for unit frames, group frames, health bars, power bars, detached power bars, absorbs, overlays, highlights, and preview samples.",
                        "Added a master Rounded Texture switch plus per-surface toggles for Unit frames, Group frames, Power bars, and Mouseover highlights.",
                        "Integrated rounded edges with active borders, mouseover highlights, dispel highlights, aggro/target/focus highlights, group-frame overlays, and layer ordering so rounded frames no longer fall back to square highlight visuals.",
                        "Added preview, search coverage, localization, reload guidance, and safe rebuild behavior for rounded frame texture changes.",
                        "Rounded Frames stay disabled by default and avoid their runtime path while disabled.",
                    },
                },
                {
                    title = "Dispel Border / Glow",
                    bullets = {
                        "Added Dispel Border detection modes: Dispellable by me, Any dispel-type debuff, and Any debuff.",
                        "Dispel Border / Glow can now support all classes: healers can keep class-aware dispel detection, while non-dispel classes can still highlight debuff types or any debuff without losing the debuff list.",
                        "Added MSUF Dispel Border / Glow for Blizzard aura mode, so Blizzard can keep rendering aura icons while MSUF still draws the configured dispel border and glow.",
                        "Added scope-aware group-frame behavior for dispel colors, glow options, scan state, and highlight priority, so party/raid scopes can keep the correct visual rules.",
                        "Improved dispel color resolution, secret-safe aura scanning, debuff filtering, and highlight cache behavior for Magic, Curse, Poison, Disease, and generic debuff states.",
                    },
                },
                {
                    title = "Menu2",
                    bullets = {
                        "Expanded the card-based layout across unit frames, group frames, auras, indicators, bars, colors, gameplay, profiles, class power, and advanced pages.",
                        "Improved the dashboard preview, collapsed text badges, clipping behavior, input readability, submenu colors, scroll behavior, dynamic strata handling, and card enable states.",
                        "Added a larger search module with better guidance for auras, name shortening, rounded frames, Focus Target, Unit Auras, Blizzard aura modes, and profile workflows.",
                        "Refined switches, range fade controls, profile UX, FAQ text, and warnings around Blizzard-managed buffs/debuffs.",
                    },
                },
                {
                    title = "Other Improvements",
                    bullets = {
                        "Added heal prediction anchor modes.",
                        "Added more status icon anchor options.",
                        "Added player aggro border support.",
                        "Added a global Preserve HP color sync option for unit-frame Bar Background Tint and improved Dark Mode missing-health background handling.",
                        "Added raid group number display next to unit names.",
                        "Improved Unit Auras debuff filters, including Include dispellable debuffs and the Magic, Curse, Poison, and Disease toggles.",
                        "Defaulted tooltips back to Blizzard-controlled behavior for better compatibility.",
                    },
                },
                {
                    title = "Performance and Stability",
                    bullets = {
                        "Improved bar background rendering, text update paths, interrupt-ready handling, range fade alpha repair, and castbar width-source layout checks.",
                        "Reduced unnecessary group-frame header rescans and repeated group health color/alpha work.",
                        "Hardened backend namespace compatibility and imported media handling.",
                        "Fixed detached unit-frame outline borders, player aura helpful classification, group HP reverse order, aura tooltip hover sizing, menu preview refreshes, dashboard support clipping, and layer ordering consistency.",
                    },
                },
                {
                    title = "Localization",
                    bullets = {
                        "Completed direct locale coverage for enUS, enGB, deDE, frFR, esES, esMX, itIT, koKR, ptBR, ruRU, zhCN, and zhTW.",
                        "Moved locale coverage into real locale files and updated runtime localization coverage for the 5.3 feature set.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
