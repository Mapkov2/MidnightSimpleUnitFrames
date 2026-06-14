-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0 Alpha 1",
    previousVersion = "5.59",
    rangeLabel = "5.59 -> 6.0 Alpha 1",
    entries = {
        {
            version = "6.0 Alpha 1",
            date = "2026-06-14",
            sections = {
                {
                    title = "Release Context",
                    bullets = {
                        "First public 6.0 alpha after the 5.59 stable line.",
                        "Baseline for this changelog: 5.59.",
                        "5.59 was a maintenance build for compound-unit event routing and Interrupt Ready taint safety. 6.0 Alpha 1 is the first public build of the rewritten 6.x core addon.",
                        "This alpha can load existing profiles, but the runtime below those profiles changed heavily. Export important profiles before testing.",
                        "The biggest change is not one single option. MSUF now has a new runtime foundation, a new configuration experience, integrated castbars, a stronger Assistant, updated class resources, and a much larger preview/editing layer.",
                    },
                },
                {
                    title = "Five Feature Highlights",
                    bullets = {
                        "MSUF Assistant: a new in-menu assistant can find settings, route common setup requests, apply supported changes, handle follow-up commands, protect destructive actions with confirmation, and keep undo/redo available for confirmed actions.",
                        "New design language: Menu2, Edit Mode, popups, controls, previews, dropdowns, status feedback, and dashboard areas now share one cleaner visual system instead of the older mixed 5.x/preview UI style.",
                        "Updated menus and live previews: unit frames, group frames, castbars, auras, class resources, profiles, global colors, fonts, and gameplay options now live in the rebuilt Menu2 shell with search, direct preview focus, zoom, pan, copy/reset actions, and clearer inline feedback.",
                        "Updated class resources: class power received new runtime integration, Player HP support, updated preview behavior, cleaner menu sections, and new circle, diamond, hex, crystal, and round resource shapes.",
                        "No more Castbar LoD split: castbars are now built directly into the core addon package. Player, target, focus, and boss castbars load with MSUF, share the same settings/runtime/previews, and no longer depend on a separate castbar LoD addon path.",
                    },
                },
                {
                    title = "Compared To 5.59",
                    bullets = {
                        "5.59 was a small maintenance build. 6.0 Alpha 1 is a broad rewrite of the shipped core addon.",
                        "The old Core layer was removed from the active load path. Health, power, prediction, absorb, text, alpha, borders, textures, portraits, range fade, status, class power, and castbar bridge work moved into focused runtime modules.",
                        "The old Foundation shape was reorganized into Kernel, Runtime, and State responsibilities. Bootstrap, modules, events, scheduling, utility helpers, Blizzard frame handling, changelog state, profile state, migrations, and UI state now have clearer homes.",
                        "The old EditMode2 implementation was replaced by Shell/EditMode modules for core behavior, HUD, focus, layout, movers, popup scale, aura popups, cast popups, and tooltip/unit/group editing.",
                        "The old broad GroupFrames/MSUF_GF_* backend was replaced or wrapped by the newer 6.x group-frame architecture. Party, raid, mythic raid, headers, visuals, status, indicators, spell indicators, previews, and edit-mode paths are now split by purpose.",
                        "Auras2 files were removed from the shipped addon. Auras3 configuration, profile data, menu model, edit-mode hooks, unit-frame surfaces, and preview surfaces are in the 6.0 tree, while live aura behavior remains alpha because Midnight aura APIs are still moving.",
                        "Castbars moved from the older split-package model into the main addon package so castbars, unit frames, previews, profile updates, and release metadata ship together.",
                        "Menu2 was split from large page/search/widget files into smaller page, preview, routing, search, theme, widget, section, and helper modules.",
                        "The public _G.MSUF_* surface was reduced in the rewritten areas in favor of a clearer MSUF namespace/API pattern, while compatibility exports are kept where older modules or user macros still need them.",
                        "Local docs, audits, smoke-test scripts, and development tooling are kept out of the addon package. They remain local development files and are not meant to ship inside the public ZIP.",
                    },
                },
                {
                    title = "Core Runtime And Architecture",
                    bullets = {
                        "Added a 6.x bootstrap and module load structure that separates startup setup, runtime code, saved state, shell UI, and feature code.",
                        "Added a shared scheduler layer for deferred, budgeted, and combat-aware work instead of spreading ad-hoc timers across runtime modules.",
                        "Added targeted dirty-mask updates so frame changes can refresh only the affected element instead of forcing broad frame rebuilds.",
                        "Added compiled per-frame/event state for hotter unit-frame paths, reducing repeated table lookups and repeated handler discovery during frequent events.",
                        "Added direct handler references for common health, power, prediction, text, status, alpha, border, range, and castbar paths.",
                        "Added shared runtime helpers for fonts, textures, colors, icon layout, portrait media, bar backgrounds, chat/tooltips, and Blizzard frame ownership.",
                        "Added safer public export helpers for shared data such as the in-game changelog, reducing raw global writes in generated/runtime-facing code.",
                        "Added clearer feature folder boundaries for diagnostics, gameplay helpers, telemetry, versioning, third-party anchors, and integration code.",
                        "Removed old load-condition and preview shims that no longer matched the 6.x runtime path.",
                        "Preserved the 5.59 compound-unit event fix for targettarget and focustarget.",
                    },
                },
                {
                    title = "Unit Frames",
                    bullets = {
                        "Rebuilt the Unit Frame engine around focused element modules instead of one broad 5.x core file.",
                        "Reworked health, power, alternate power, heal prediction, absorbs, heal absorbs, text, portraits, borders, background, alpha, range fade, status indicators, elite visuals, and castbar bridge handling.",
                        "Added stronger preview/live parity so menu previews and edit-mode dummy frames use the same runtime assumptions as real frames.",
                        "Added targeted updates for visual-only changes, geometry changes, text changes, range changes, class-color changes, and profile/default changes.",
                        "Improved targettarget and focustarget handling through the retained compound-unit event routing fix from 5.59.",
                        "Improved disconnected, dead, ghost, offline, resurrect, aggro, PvP, role, and status visual handling across rewritten runtime paths.",
                        "Added support paths for independent power text, target power text fixes, NPC name color behavior, text shadow fixes, and safer text refreshes.",
                        "Reduced disabled-feature overhead so inactive text, visual, indicator, aura, range, and status systems avoid unnecessary refresh work.",
                        "Reduced repeated UnitExists, UnitIsConnected, UnitIsPlayer, unit reaction, and power reads inside a single dispatch pass where the runtime can reuse resolved state.",
                        "Improved class-color and reaction-color update paths so common color changes avoid full rebuilds.",
                        "Kept profile defaults compatible enough to migrate old 5.x settings while giving the 6.x runtime cleaner internal defaults.",
                    },
                },
                {
                    title = "Group Frames",
                    bullets = {
                        "Reworked group frames for party, raid, and mythic raid around secure-header-aware runtime modules.",
                        "Added clearer separation for group config, headers, visuals, status, indicators, spell indicators, preview, metadata, edit-mode integration, and Blizzard fallback behavior.",
                        "Added targeted group-frame refresh paths for geometry, bounds, visuals, status, role state, range fade, indicators, spell indicators, and preview work.",
                        "Added roster structure detection so role-only or state-only updates can update bindings without rebuilding secure headers when the group structure did not change.",
                        "Added safer post-combat handling for deferred group-frame work, pending rebuild reasons, and downgrade paths for state-only updates.",
                        "Improved behavior around group transitions, raid entry/exit, party to raid conversion, mythic raid layout, and Blizzard frame ownership.",
                        "Improved preview/live parity for group dummies, party previews, raid previews, mythic raid previews, growth direction, columns, spacing, size, and anchor behavior.",
                        "Improved dead, ghost, offline, resurrection, aggro, status icon, group number, role, mouseover highlight, range/threat, and tooltip mouseover behavior.",
                        "Split spell-indicator data and group-frame DB helpers so large registry-style data is easier to reason about and less risky to edit.",
                        "Kept Auras3 group button-pool prewarming out of this alpha. No extra out-of-combat pool prewarm spike was added.",
                    },
                },
                {
                    title = "Castbars",
                    bullets = {
                        "Integrated the castbar addon code into the core MSUF package.",
                        "Added runtime modules for castbar frames, anchors, registry, driver, backend, style, visuals, previews, preview editing, bridge code, and shared utilities.",
                        "Added player castbar runtime support through the same package as the unit-frame runtime.",
                        "Added target, focus, and boss castbar support paths in the 6.x tree.",
                        "Added boss castbar preview support.",
                        "Added channel tick handling and empower cast handling.",
                        "Added focus kick state driver and focus kick icon support.",
                        "Added Interrupt Ready support in the core package.",
                        "Preserved the 5.59 Interrupt Ready fix that avoids secret RGBA comparison paths and the related _kickReadyFillR taint issue.",
                        "Added safer castbar timing/width behavior to avoid secret-value arithmetic regressions.",
                    },
                },
                {
                    title = "Class Power And Player HP",
                    bullets = {
                        "Reworked class resource rendering around the 6.x runtime and preview model.",
                        "Added Player HP integration for class-resource style layouts.",
                        "Added resource shape assets for circle, diamond, hex, crystal, and round styles.",
                        "Improved class resource menu sections, preview behavior, and visual defaults.",
                        "Kept alternate mana and balance druid logic on the updated controller/model path.",
                    },
                },
                {
                    title = "Menu2, Search, And Edit Mode",
                    bullets = {
                        "Rebuilt Menu2 into smaller modules for pages, sections, widgets, theme, search, routing, previews, navigation, and support behavior.",
                        "Added denser unit-frame and group-frame settings pages with better progressive disclosure for common versus advanced controls.",
                        "Added direct preview focus for text slots, frame visuals, castbars, class power, group-frame layers, and relevant edit targets.",
                        "Added richer unit-frame and group-frame previews with zoom, pan, handles, focus states, and live refresh where supported.",
                        "Added compact Edit Mode popups for unit frames, group frames, castbars, auras, tooltip placement, and popup scaling.",
                        "Added copy-to and reset flows for unit frames, group frames, position, size, profile-related actions, and page/category actions.",
                        "Added calmer inline command feedback so many actions report in the menu status area instead of chat spam or disruptive popups.",
                        "Added dropdown focus behavior, menu motion helpers, popup fade/scale behavior, and more consistent disabled/locked/active states.",
                        "Improved search coverage for setup, movement, profiles, castbars, group frames, unit-frame text, range fade, visibility, aura setup, and troubleshooting.",
                        "Fixed several preview clipping, popup placement, snap-guide, text focus, and preview-anchor problems from earlier 6.0 preview builds.",
                    },
                },
                {
                    title = "Assistant And Profile Workflows",
                    bullets = {
                        "Split Assistant knowledge, routing, command handlers, media resolving, parser domains, registries, and workflow helpers into smaller files.",
                        "Made parser actions more testable by separating command interpretation from UI side effects in the rewritten areas.",
                        "Added clearer Assistant coverage for unit frames, group frames, global settings, castbars, auras, class power, diagnostics, dashboard actions, profiles, and workflows.",
                        "Added confirmation protection for broad or destructive Assistant actions before SavedVariables are changed.",
                        "Added cancel paths for pending Assistant confirmations.",
                        "Improved undo/redo behavior around confirmed Assistant actions and Menu2 actions.",
                        "Improved profile import, export, copy, reset, spec profile, migration, and best-effort UUF import workflows.",
                        "Added AceSerializer and LibDeflate support for profile import/export paths.",
                        "Improved large option registries by splitting data and routing so single files are less likely to hit WoW Lua local/function complexity limits.",
                    },
                },
                {
                    title = "Auras And Aura Scope",
                    bullets = {
                        "Removed the old Auras2 runtime files from the active addon tree.",
                        "Added Auras3 core, menu model, edit-mode hooks, unit-frame surfaces, and runtime XML scaffolding.",
                        "Kept Auras3 profile/configuration and preview surfaces so aura settings can survive while the live backend continues to move.",
                        "Paused or limited live aura-dependent paths where Blizzard Midnight aura APIs are not stable enough for a final backend.",
                        "Disabled old group aura cache, group custom aura lanes, private aura anchoring, custom aura rendering, and aura cooldown-text runtime paths that no longer match the current Midnight API state.",
                        "Aura behavior should be treated as alpha in this build even though configuration and preview surfaces are present.",
                    },
                },
                {
                    title = "Gameplay, Diagnostics, Media, And Localization",
                    bullets = {
                        "Moved gameplay helpers into a clearer Features/Gameplay area.",
                        "Added or reorganized target sound, totem preview, gameplay config, and gameplay runtime helpers.",
                        "Moved diagnostics into a clearer diagnostics feature area, including click/debug position helpers.",
                        "Reorganized telemetry and version-check modules.",
                        "Added third-party anchor integration helpers.",
                        "Reorganized icon assets from the older Icons layout into the media tree.",
                        "Added new class power media assets and checkbox media assets.",
                        "Updated localization files across supported locales for the new Menu2, Assistant, profile, group-frame, castbar, and runtime text.",
                        "Refreshed minimap and UX media used by the 6.x shell.",
                    },
                },
                {
                    title = "Performance And Runtime Safety",
                    bullets = {
                        "Reduced hot-path handler discovery by compiling event state and caching direct update references.",
                        "Reduced frame refresh amplification by using targeted dirty masks and scope-aware refreshes.",
                        "Reduced group-frame rebuilds by distinguishing structural changes from state-only or visual-only changes.",
                        "Reduced disabled-feature overhead in text, alpha, visual, status, aura, range, castbar, and preview paths.",
                        "Added safer combat-lock handling so blocked secure-frame work defers or reports state instead of trying to mutate restricted frames.",
                        "Added budgeted/deferred scheduling for non-urgent work without adding a forced Auras3 group-pool prewarm spike.",
                        "Added more guarded runtime calls and defensive fallbacks around Blizzard ownership, profile state, preview state, and menu state.",
                        "Added local smoke/quality checks for syntax, Assistant command behavior, profile migration, options load, runtime budgets, and WoW Lua local-limit risk.",
                        "Removed local docs and smoke scripts from the shipped addon package so development-only files do not inflate the public install.",
                    },
                },
                {
                    title = "Known Alpha Testing Focus",
                    bullets = {
                        "Test profile migration from 5.59 profiles before treating this as a daily-driver build.",
                        "Test profile import/export, profile copy/reset, spec profiles, UUF import, and undo/redo after Assistant or Menu2 actions.",
                        "Test party, raid, mythic raid, combat lockdown, roster transitions, role changes, dead/offline/ghost states, resurrection visuals, status icons, spell indicators, range fade, and Blizzard frame fallback.",
                        "Test player, target, focus, and boss castbars, including channels, empower casts, interrupt-ready visuals, focus kick behavior, and preview editing.",
                        "Test Unit Frame text, health, power, prediction, absorbs, class power, player HP integration, alpha, borders, portraits, range fade, and status visuals.",
                        "Treat Auras3 live behavior as alpha until Blizzard Midnight aura APIs settle.",
                        "Report regressions against 5.59 when possible, especially visibility issues, combat-state issues, taint, profile migration errors, and secure-frame behavior.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
