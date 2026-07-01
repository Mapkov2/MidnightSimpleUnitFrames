-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-Beta1",
    previousVersion = "6.0-alpha8",
    rangeLabel = "6.0-alpha8 -> 6.0-Beta1",
    entries = {
        {
            version = "6.0-Beta1",
            date = "2026-07-01",
            sections = {
                {
                    title = "Comparison Scope",
                    bullets = {
                        "Compared against 5.60 / MSUF_5.6. This beta includes the full 6.0 line since 5.60, not only the last alpha.",
                        "The comparison covers 219 commits, 732 changed files, 539 added files, and 133 removed files.",
                        "6.0-Beta1 targets the WoW 12.1 addon/runtime path. 5.60 remains the last 5.x baseline for the older 12.0.x-era code path.",
                    },
                },
                {
                    title = "10 Highlight Features Since 5.60",
                    bullets = {
                        "New Auras3 system: MSUF now uses WoW 12.1 native AuraContainer/AuraButton handling instead of the old Auras2 custom scanner and renderer.",
                        "New aura lane controls: unit and group auras now support shared/per-scope style inheritance, buff/debuff lane editing, cooldown text placement, reverse swipe, stack text, native filter toggles, and duration bars.",
                        "New integrated castbars: Player, Target, Focus, Boss, Focus Kick, Interrupt Ready, channels, empower casts, latency, spark, glow, icons, and live previews are now handled by the main addon's 6.0 castbar runtime.",
                        "New 6.x UnitFrame engine: health, power, text, alpha, prediction bars, load conditions, status elements, borders, range fade, and dispatch are split into focused runtime modules with fewer hot-path updates.",
                        "New 6.x GroupFrame engine: secure headers, Blizzard fallback, group previews, spell/status indicators, health fade, offline/dead visuals, aggro role filters, dispel overlays, corner indicators, and range handling were rebuilt from the 5.60 group-frame stack.",
                        "New party Targeted Spell Indicators: MSUF can show enemy nameplate casts that target party members, with configurable icon count, placement, timer text, and time-based colors.",
                        "New full Assistant: the 5.60 search/ask flow is replaced by a registry-driven assistant with natural language commands, setting changes, followups, diagnostics, page routing, undo, dashboard actions, profile actions, and broad aura/group/castbar/class-power coverage.",
                        "New Menu2 shell and preview system: dashboard, navigation rail, window controls, search FAQ, page previews, unit/group/class-power previews, zoom/pan, anchor picker, bug report flow, and the in-game changelog prompt are now bundled in the 6.0 UI.",
                        "New profile transition layer: 6.0 adds MSUF4 compact profile export/import, stronger 5.60-to-6.0 migration, LibDeflate/AceSerializer fallback decoding, safer missing font/texture fallback, and more complete old-profile normalization.",
                        "New integrations and visuals: NSRT nickname support, third-party anchor support, Skiron cooldown-anchor handling, new class-resource shapes/assets, PvP flag indicators, native dispel sensors, new outline/opacity controls, and refreshed rounded-frame media were added after 5.60.",
                    },
                },
                {
                    title = "Auras And WoW 12.1",
                    bullets = {
                        "Removed the old Auras2 runtime files from the active path and added Auras3 modules for native unit-frame and group-frame aura rendering.",
                        "Added native filter workflows for raid/player/dispellable/crowd-control/defensive aura use cases, with clearer handling for legacy exact blacklist data while Blizzard's native 12.1 aura backend is active.",
                        "Added duration bar support for unit and group aura lanes, including display mode, position, fill direction, height, preview rendering, Assistant commands, and saved defaults.",
                        "Added native dispel sensors so dispel borders, overlays, and corner indicators can use the 12.1 AuraContainer path without relying on the old custom aura scan.",
                        "Improved target/focus aura swap refresh behavior and coalesced aura refresh work so fast target changes avoid unnecessary synchronous rebuilds.",
                    },
                },
                {
                    title = "Unit Frames, Group Frames, And Castbars",
                    bullets = {
                        "Replaced the old monolithic UnitFrame runtime with the new UnitFrames/Engine modules for config, factory, dispatch, text, visuals, bars, borders, predictions, status, secrets, range fade, and group adapters.",
                        "Rebuilt group frames around the 6.x engine, including secure header setup, Blizzard frame fallback behavior, group visual compilation, targeted spells, spell registry data, and live group previews.",
                        "Added or expanded group-frame options for health fade, role-specific power/resource bars, aggro role filtering, fallback aggro/dispel borders, target/focus highlight controls, group-border opacity, and offline/dead status text aliases.",
                        "Moved castbars from the separate castbar addon tree into the main addon and expanded runtime/preview coverage for channels, empower casts, boss casts, player castbar ownership, focus kick, and interrupt-ready behavior.",
                        "Added dependent target visibility shortcuts and improved Target of Target / Focus Target handling for visibility, sizing, text, castbars, range fade, colors, and positioning.",
                    },
                },
                {
                    title = "Menu, Assistant, And UX",
                    bullets = {
                        "Added the full Assistant framework with knowledge, parser, router, command registry, match cache, media resolver, queue, undo, dashboard, diagnostics, and profile workflows.",
                        "Expanded Assistant coverage for aura style/filter commands, group aura lane geometry, group-frame visual settings, scoped bar overrides, castbars, class power, unit frames, profiles, dashboard navigation, and safe troubleshooting answers.",
                        "Rebuilt Menu2 under the Shell structure with dashboard state, navigation rail, Apply service, page previews, control gates, search routing, searchable FAQ catalogs, persistent UI state, and dedicated preview modules.",
                        "Added the bundled dashboard changelog data and popup so users can open release notes from inside MSUF after updating.",
                        "Added a richer bug report/support flow and clearer diagnostics guidance for setup, profile, aura, gameplay, and frame-visibility questions.",
                    },
                },
                {
                    title = "Profiles, Compatibility, And Integrations",
                    bullets = {
                        "Added MSUF4 profile strings while preserving compatibility paths for MSUF3 and legacy MSUF2 imports.",
                        "Added migration and normalization for 5.60-era profiles, including aura geometry, text/name fields, fonts, textures, group-frame scopes, status indicators, and old 6.0 alpha layouts.",
                        "Added optional Northern Sky Raid Tools nickname integration with combat-safe refresh behavior.",
                        "Added third-party anchor helpers, including Skiron cooldown anchor support for profiles anchored to external cooldown UI.",
                        "Added a WoW 12.1-ready versioning path and release tooling updates for beta packaging, static checks, and safer CurseForge/Wago publishing metadata.",
                    },
                },
                {
                    title = "Performance And Stability",
                    bullets = {
                        "Reduced hot-path work across unit frames, group frames, castbars, auras, range fade, menu previews, assistant matching, and font application.",
                        "Added bounded caches and coalesced refresh paths for expensive Assistant fuzzy matching, aura refreshes, target/focus swaps, menu rebuilds, and visual updates.",
                        "Hardened font and texture application so missing SharedMedia or disabled addon media falls back safely instead of producing asset errors.",
                        "Improved combat-lockdown handling for frame movement, late anchors, profile applies, menu actions, and secure group-frame recovery.",
                        "Added local static checks and release-time validation for namespace safety, Assistant parser/registry coverage, group status runtime behavior, spell indicator data, and general addon quality gates.",
                    },
                },
                {
                    title = "Beta Testing Notes",
                    bullets = {
                        "Export important 5.60 profiles before testing 6.0-Beta1.",
                        "Test Player, Target, Focus, Boss, Party, Raid, Mythic Raid, Target of Target, and Focus Target pages after importing an old profile.",
                        "Test auras on WoW 12.1 content specifically: target swaps, focus swaps, party/raid conversion, dispellable debuffs, duration bars, cooldown text, stack text, and group aura filters.",
                        "Test party Targeted Spell Indicators with enemy nameplates enabled in 5-player content.",
                        "Test profile import/export, font fallback, texture fallback, NSRT nicknames, external anchors, and castbar ownership changes after /reload and after combat.",
                    },
                },
            },
        },
        {
            version = "6.0-alpha8",
            date = "2026-06-30",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Fixed several bugs including aura movement",
                    },
                },
            },
        },
        {
            version = "6.0-alpha7",
            date = "2026-06-30",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added the MSUF Edit Mode Logo Wake intro using the high-resolution MSUF logo asset.",
                        "Added a CurseForge-only release path so Alpha 7 can be published without also uploading to Wago.",
                    },
                },
                {
                    title = "Edit Mode",
                    bullets = {
                        "Updated the logo intro so the logo fades in smoothly, gets a brief cyan wake glow, then lets the ring trace run once and close.",
                        "Kept the intro animation scoped to the Edit Mode opening sequence; its OnUpdate is removed again when the intro stops.",
                    },
                },
                {
                    title = "Release And Notes",
                    bullets = {
                        "Release name: MSUF_6.0A7.",
                        "Bumped VERSION and addon metadata to 6.0-alpha7.",
                        "This tag is intentionally an alpha build; use 6.0-alpha7 as the publish tag.",
                        "Alpha 7 is intended for CurseForge-only publishing.",
                    },
                },
                {
                    title = "Alpha Testing Notes",
                    bullets = {
                        "This is an alpha build for the 6.0 branch. Export important profiles before testing.",
                        "Please test opening and leaving Edit Mode repeatedly and verify the logo intro does not continue running after Edit Mode closes.",
                        "Please test opening Edit Mode shortly before/after combat to confirm no combat overhead or lingering animation state.",
                    },
                },
            },
        },
        {
            version = "6.0-alpha6",
            date = "2026-06-29",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added party targeted spell indicators that can show enemy nameplate casts on the targeted party frame, with icon stack, placement, timer text, and time-based text color controls.",
                        "Added optional Northern Sky Raid Tools nickname integration for unit-frame display names.",
                        "Improved profile import/export and migration handling, including the new MSUF4 compact profile format and better fallback decoding for older MSUF2/MSUF3 profile strings.",
                        "Added the bundled in-game changelog prompt so users can open release notes from the dashboard after updating.",
                    },
                },
                {
                    title = "Group Frames And Indicators",
                    bullets = {
                        "Added party-only targeted spell tracking for enemy casts, including cast/channel pickup, retarget verification, cooldown text, and per-party-frame icon placement.",
                        "Added Targeted Spells controls to Group Indicators with enable mode, icon size/count/layer, anchor/growth, offsets, cooldown text, and timer color thresholds.",
                        "Updated group-frame defaults and configuration so targeted spell settings are carried by the party profile scope.",
                        "Improved group preview rendering for targeted spell/status indicator placement and native preview refreshes.",
                    },
                },
                {
                    title = "Profiles, Imports, And Defaults",
                    bullets = {
                        "Added MSUF4 profile export strings while keeping import compatibility for MSUF3 and legacy MSUF2 variants.",
                        "Improved compact profile decoding by trying Blizzard decompression, direct CBOR, and LibDeflate-backed fallbacks where available.",
                        "Added profile translation and normalization for older 6.0 alpha profile layouts, including aura geometry, text/name shortening aliases, status indicator fields, and group-frame scope fields.",
                        "Hardened profile runtime apply calls so one apply error is captured instead of breaking the whole profile operation.",
                    },
                },
                {
                    title = "Menu, Assistant, And Integrations",
                    bullets = {
                        "Added NSRT nickname resolver support with combat-safe refresh behavior and cache updates when NSRT nickname data changes.",
                        "Expanded Assistant parsing and registry coverage for aura style/filter commands, group aura lane geometry, targeted spell controls, global bar settings, and base global options.",
                        "Improved dashboard and nav-rail behavior, including hover scale defaults and typewriter/changelog handling.",
                        "Clarified Global Bars texture inheritance: unit scopes keep Shared textures while group-frame scopes can override textures and gradients.",
                        "Temporarily disabled dispel/purge border controls for 12.1 PTR until native AuraContainer exposes the needed detection path again.",
                    },
                },
                {
                    title = "Fonts, Text, And Visuals",
                    bullets = {
                        "Improved font path probing and safe font fallback resolution for missing or unavailable fonts.",
                        "Updated text layout/status paths to handle layer frames, status fonts, name shortening, and profile-translated text fields more consistently.",
                        "Refined castbar, class power, aura popup, group preview, and Edit Mode HUD rendering details.",
                        "Updated superellipse media assets used by the rounded frame visuals.",
                    },
                },
                {
                    title = "Release And Notes",
                    bullets = {
                        "Release name: MSUF_6.0A6.",
                        "Bumped VERSION and addon metadata to 6.0-alpha6.",
                        "Regenerated the in-game dashboard changelog data for Alpha 6.",
                        "Hardened the release workflow and Wago upload step so alpha metadata, alpha tags, and A-style alpha release names cannot be uploaded to Wago as stable/release.",
                        "This tag is intentionally an alpha build; use 6.0-alpha6 as the publish tag so Wago receives stability = alpha, CurseForge receives an alpha release type, and GitHub marks the release as prerelease.",
                    },
                },
                {
                    title = "Alpha Testing Notes",
                    bullets = {
                        "This is an alpha build for the 6.0 branch. Export important profiles before testing.",
                        "Please test Targeted Spells in 5-player party content with enemy nameplates enabled, especially casts that retarget or channel.",
                        "Please test importing older Alpha 2 through Alpha 5 profile strings, especially profiles with custom aura positions, fonts, textures, and group-frame text settings.",
                        "Please test NSRT nickname display with NSRT global nicknames enabled and disabled.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
