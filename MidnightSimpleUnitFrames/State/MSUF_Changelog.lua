-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-Beta4",
    previousVersion = "6.0-Beta3",
    rangeLabel = "6.0-Beta3 -> 6.0-Beta4",
    entries = {
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
        {
            version = "6.0-Beta3",
            date = "2026-07-03",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added selectable status icon packs for unit and group frames.",
                        "Added per-indicator custom icon overrides and live icon previews.",
                        "Added the first Assistant context-engine pass for smarter follow-up commands.",
                        "Restored Wago-compatible profile exports with embedded full MSUF6 data.",
                        "Added an MSUF button to the Blizzard Escape/Game Menu.",
                    },
                },
                {
                    title = "Status Icons And Indicators",
                    bullets = {
                        "Added bundled icon styles: Classic, Midnight, UX Pro, Glossy Orbs, Dark Emboss, Glass Panels, Neon Outline, Ring Symbols, Dots, Shapes, Diamonds, and Squares.",
                        "Added external icon-pack support through public registration, addon metadata, and SharedMedia.",
                        "Added style/custom-icon support for role, leader, assist, raid marker, ready check, summon, resurrection, PvP, phase, combat/resting, and elite indicators.",
                        "Added Midnight-style switching and icon-pack filtering by supported indicator type.",
                        "Added icon preview strips and custom icon asset dropdowns.",
                        "Updated live unit-frame and group-frame status rendering to use the new icon resolver.",
                    },
                },
                {
                    title = "Menu And Preview Improvements",
                    bullets = {
                        "Added a Game Menu MSUF entry with addon icon.",
                        "Added the showGameMenuButton default.",
                        "Added smoother Menu2 scrolling for pages and dropdowns.",
                        "Replaced the preview gear glyph with a drawn settings icon.",
                        "Added Menu2 auto-height helpers.",
                        "Added /msufmenucheck for read-only menu consistency checks.",
                        "Unified live and preview layer constants for unit-frame and group-frame text, status, portrait, power, targeted-spell, and preview-overlay stacking.",
                        "Added on-demand live-vs-preview layer diagnostics for unit and group previews without combat-time event, timer, or update overhead.",
                        "Aligned unit and group preview mock text layering with runtime text-layer specs for closer 1:1 visual previews.",
                    },
                },
                {
                    title = "Assistant And Search",
                    bullets = {
                        "Split large parser phrase tables into _Data.lua modules.",
                        "Added generated fallback coverage for scalar DB settings.",
                        "Added /msufcoverage reports, stubs, manifest export, smoke tracking, and gate checks.",
                        "Added no-op escalation for relative nudges like \"more to the right\".",
                        "Added continuation follow-ups for partially repeated subjects like \"now move target leader up\".",
                        "Added context scoring for recent unit/category/text-area matches.",
                        "De-prioritized generated fallbacks during ambiguous matches.",
                        "Prioritized long exact aliases before broad fast paths.",
                        "Improved generated labels and aliases.",
                        "Improved coverage/audit detection for three-segment scoped keys.",
                        "Improved AutoCoverage labels for acronym boundaries.",
                        "Added small synonym expansion for generated Assistant aliases.",
                        "Added minimum-token exact-alias parsing.",
                        "Added an early priority pass for long exact aliases.",
                    },
                },
                {
                    title = "Profiles And Imports",
                    bullets = {
                        "Added MSUF3-prefixed compact export support for Wago.",
                        "Added normalized Wago compatibility payloads.",
                        "Embedded full msuf6 snapshots in exported strings.",
                        "Prefer embedded full MSUF6 data on import when available.",
                        "Normalized aura and group-frame payloads for Wago compatibility.",
                    },
                },
                {
                    title = "Release And Publishing",
                    bullets = {
                        "Fixed compact prerelease tags like MSUF_6.0B3 so Wago and CurseForge publish them as beta instead of stable/release.",
                        "Added MSUF_* tag support to the release workflow and normalized compact A/B tags to addon versions like 6.0-alpha3 and 6.0-beta3.",
                        "Updated the release version marker to 6.0-beta3.",
                    },
                },
                {
                    title = "Class Resources And Power Text",
                    bullets = {
                        "Added left/center/right slot controls for detached Player Power text.",
                        "Added per-slot value modes, delimiter, size, global offsets, per-slot offsets, and text layer.",
                        "Cleared stale hpPowerTextOverride state when detached power text changes.",
                        "Bumped the Class Resources page version.",
                    },
                },
                {
                    title = "Auras, Castbars, And Runtime Fixes",
                    bullets = {
                        "Added localized minute suffixes for aura duration text.",
                        "Fixed sub-second decimal aura timer display.",
                        "Reduced redundant boss castbar and castbar visual updates.",
                        "Reduced redundant Interrupt Ready visual updates.",
                        "Improved explicit non-interruptible Interrupt Ready colors.",
                        "Added Player health lifecycle events for dead/alive/ghost updates.",
                        "Improved target/focus portrait refresh handling.",
                    },
                },
                {
                    title = "What To Test First",
                    bullets = {
                        "Status icon packs and Midnight variants.",
                        "Custom icon overrides and live previews.",
                        "External icon packs via SharedMedia and addon metadata.",
                        "Unit-frame and group-frame preview layering compared with the matching live frames.",
                        "Assistant follow-ups, exact option names, /msufcoverage, and /msufcoverage gate.",
                        "Wago export/import and full MSUF import from the same string.",
                        "Detached Player Power text slots and offsets.",
                        "Aura duration text around sub-second and minute-long timers.",
                        "Castbar updates, Interrupt Ready visuals, portraits, and Player dead/ghost health refresh.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta2",
            date = "2026-07-03",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Better previews: quick settings access, context controls, gear buttons, and improved preview handle behavior.",
                        "Better visuals: 2D portrait zoom, resource-bar opacity, live power alpha, and optional over-absorb glow.",
                        "Better stability: castbar border fixes, class-power reload fixes, faster Assistant routing, and less redundant runtime work.",
                    },
                },
                {
                    title = "Menu And Preview Improvements",
                    bullets = {
                        "Quick settings access from unit, group, and class-resource preview handles.",
                        "New preview-handle context controls and gear buttons.",
                        "Improved moving, nudging, zooming, panning, and fit behavior in previews.",
                        "Fixed preview checkbox/text sync issues.",
                        "Refined group preview controls and native group preview behavior.",
                    },
                },
                {
                    title = "Unit Frames, Bars, And Visuals",
                    bullets = {
                        "Added 2D portrait zoom.",
                        "Added separate resource-bar foreground/background opacity.",
                        "Added live power-bar alpha support.",
                        "Added optional over-absorb overlay/glow.",
                        "Fixed live HP percent formatting.",
                        "Reduced redundant unit-frame and portrait refresh work.",
                    },
                },
                {
                    title = "Castbars And Class Resources",
                    bullets = {
                        "Fixed long-standing castbar border/layout inset issues.",
                        "Fixed boss castbar border/layout inset handling.",
                        "Reduced redundant castbar text/time updates.",
                        "Stabilized detached class-power and Player Power anchors.",
                        "Fixed class power placement after /reload in combat.",
                    },
                },
                {
                    title = "Assistant And Search",
                    bullets = {
                        "More Assistant coverage for frame settings, geometry/text, auras, castbars, global bars, colors, transparency, portrait zoom, over-absorb, and group-frame actions.",
                        "Faster Assistant routing and cancellable work.",
                        "Better followups, exact aliases, media resolution, and changelog/dashboard answers.",
                        "Added Assistant coverage documentation.",
                    },
                },
                {
                    title = "Edit Mode, Popups, And Diagnostics",
                    bullets = {
                        "Fixed Edit Mode popups letting clicks pass through.",
                        "Added debug position diagnostics.",
                        "Added runtime localization fallbacks for new menu/search strings.",
                    },
                },
                {
                    title = "What To Test First",
                    bullets = {
                        "Preview gear/context shortcuts.",
                        "2D portrait zoom on all unit frames.",
                        "Health/resource opacity on live frames.",
                        "Absorb and over-absorb display.",
                        "Castbar borders, including boss castbars.",
                        "Class resources and detached Player Power after /reload.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta1",
            date = "2026-07-01",
            sections = {
                {
                    title = "Short Version",
                    bullets = {
                        "6.0-Beta1 is the real upgrade path from 5.60 to 6.0, not a small follow-up patch.",
                        "It is built for WoW 12.1. If you are still using 5.60, export your profiles before trying this beta.",
                        "All Alpha 1-8 changes are included here, plus the final Beta1 fixes and polish.",
                        "The addon should still feel like MSUF, but a lot underneath it has been replaced so it can work properly on the 12.1 client.",
                    },
                },
                {
                    title = "What You Will Notice First",
                    bullets = {
                        "Auras are the biggest change. Buffs and debuffs now use the WoW 12.1 native aura system instead of the old 5.60 aura renderer.",
                        "Group frames should feel more complete and more consistent, especially in parties and raids.",
                        "Class resources and Player power bars have more visual styles, better previews, and more layout control.",
                        "The settings menu is more useful. The new Assistant can find settings, apply many changes, handle followups, run checks, and undo changes it made.",
                        "Castbars are now part of the main 6.0 setup instead of feeling like a separate older layer.",
                        "Profile import/export is more forgiving, especially when older strings, missing fonts, missing textures, or alpha profiles are involved.",
                    },
                },
                {
                    title = "New Compared To 5.60",
                    bullets = {
                        "Auras3 replaces Auras2 for live aura display on WoW 12.1.",
                        "Aura duration bars can now be shown under buff and debuff icons.",
                        "Aura cooldown swipe direction can be normal or reversed.",
                        "Aura lanes can be moved more directly in Edit Mode.",
                        "Buff and debuff lanes have clearer Shared/Custom style controls, cooldown text placement, stack text placement, native filters, and preview support.",
                        "Native dispel detection is wired into the new aura path.",
                        "Party Targeted Spell Indicators can show enemy nameplate casts on the party member being targeted.",
                        "MSUF4 profile strings are now supported, while older MSUF2/MSUF3 strings are still handled as fallback imports.",
                        "Northern Sky Raid Tools nicknames can be used for unit-frame names.",
                        "External anchor support was added, including Skiron cooldown anchors.",
                        "New class-resource and power-bar shapes were added: circle, diamond, hex, round, crystal, and orb-style options.",
                        "Class Resources now has shape presets such as Classic Bar, Clean Dots, Gems, Hex Pips, and Compact.",
                        "The detached Player Power bar can now follow class-resource styling or use its own bar, round, crystal, or orb style.",
                        "An optional extra Player HP bar can be shown near class resources or Player Power, with its own text, size, color, texture, and shape options.",
                        "The in-game changelog can be opened from MSUF after updating.",
                    },
                },
                {
                    title = "Reworked From 5.60",
                    bullets = {
                        "Unit frames were rebuilt for 6.0: health, power, text, alpha, range fade, status icons, prediction bars, borders, and load conditions now use the new engine.",
                        "Group frames were rebuilt instead of patched on top of the old 5.60 group system. Party, Raid, and Mythic Raid now share the same newer frame logic.",
                        "Castbars existed in 5.60, but 6.0 integrates Player, Target, Focus, Boss, Focus Kick, and Interrupt Ready into the main addon flow with better previews and cleaner ownership.",
                        "Class Resources were expanded with better class/spec previews, shape media, smoother resource presentation, detached power-bar controls, and the optional Player HP bridge.",
                        "Menu2 was already present in 5.60, but 6.0 turns it into a fuller settings shell with navigation, previews, search, Assistant support, bug report tools, and better window handling.",
                        "Edit Mode moved from the old EditMode2 path to the new 6.0 Edit Mode, including aura handles, cast/aura popups, popup scaling, and the new logo intro.",
                        "Gameplay helpers were reorganized and hardened around combat, reloads, target sound, totem preview, and related helper settings.",
                    },
                },
                {
                    title = "Auras In Plain English",
                    bullets = {
                        "5.60 displayed auras with MSUF's own older scanner and renderer. 6.0 lets Blizzard's 12.1 aura system do the live tracking and lets MSUF control how those auras look.",
                        "This should make target swaps, focus swaps, group updates, and combat aura updates more reliable on the new client.",
                        "You get more visible controls for each aura lane: size, spacing, growth direction, cooldown text, stack text, duration bars, filters, and tooltip behavior.",
                        "Existing blacklist data is kept, but old Auras2 filtering may not match perfectly because the new system uses Blizzard's native 12.1 filter strings.",
                    },
                },
                {
                    title = "Group Frames",
                    bullets = {
                        "Party, Raid, and Mythic Raid are now handled by the same 6.0 group-frame system.",
                        "Party Targeted Spell Indicators are the main new gameplay feature here: in dungeon content, a party frame can show when an enemy cast is aimed at that player.",
                        "Group auras now use the new Auras3 path, including native dispel support and better preview behavior.",
                        "Status indicators, spell indicators, range fade, health fade, offline/dead visuals, role filters, threat/aggro visuals, and text handling were cleaned up into one more predictable setup.",
                        "Beta1 also adds more visibility/load conditions, including housing cases, and more control over which roles show aggro borders.",
                    },
                },
                {
                    title = "Class Resources And Power Bars",
                    bullets = {
                        "Class resources are no longer just the old rectangular class bar style. You can use bar, dot, gem, hex, compact, round, crystal, and orb-like looks depending on the resource or attached power bar.",
                        "The Class Resources page now has better previews for real class/spec cases such as runes, combo points, soul shards, essence, holy power, chi, insanity, maelstrom, stagger, and similar resource styles.",
                        "Shape presets make it faster to switch between classic bars, clean dots, gem-style pips, hex pips, and compact resource displays.",
                        "Detached Player Power can sync with class resources or use its own style, size, texture, outline, text, and placement.",
                        "The optional Player HP bar can sit above or below class resources or Player Power, and can follow the Player Power style if you want a matched resource cluster.",
                        "Power-bar and class-resource previews were improved so changes are easier to judge before leaving the settings menu.",
                    },
                },
                {
                    title = "Profiles And Migration",
                    bullets = {
                        "6.0 tries to migrate 5.60 profiles automatically, but this is a major version jump. Export first.",
                        "Old profile strings, missing media, older alpha data, and some external imports should recover better instead of failing the whole import.",
                        "MSUF4 is the new profile string format for 6.0.",
                        "Older MSUF2/MSUF3 profile strings are still attempted through fallback import paths.",
                        "Imported profiles can be applied to the current profile or brought in as a new profile, depending on the workflow.",
                    },
                },
                {
                    title = "From Alpha 1 To Beta1",
                    bullets = {
                        "Alpha 1 opened the 6.0 branch with the new foundation, previews, castbar work, class-resource work, profile import/export, group-frame work, and the first Auras3 version.",
                        "Alpha 2 moved live aura display to Blizzard's native 12.1 AuraContainer system.",
                        "Alpha 3 improved aura timer colors, Assistant context, geometry followups, castbar controls, class-resource previews, and preview routing.",
                        "Alpha 4 improved Shared aura styling, per-unit aura text overrides, cooldown text anchors, aura previews, and boss preview refresh.",
                        "Alpha 5 added reverse cooldown swipe and fixed important castbar preview/runtime issues.",
                        "Alpha 6 added Party Targeted Spell Indicators, NSRT nicknames, MSUF4 profile strings, class-resource shapes, stronger import handling, and the in-game changelog.",
                        "Alpha 7 added the Edit Mode logo intro and prepared the CurseForge-only alpha release path.",
                        "Alpha 8 added aura dragging, menu performance work, combat performance work, and more Assistant coverage for group and bar settings.",
                        "Beta1 stabilizes all of that for wider 5.60 -> 6.0 testing.",
                    },
                },
                {
                    title = "Beta1 Polish",
                    bullets = {
                        "Aura duration bars and native dispel sensors are now connected through live frames, previews, defaults, menus, and the Assistant.",
                        "The Assistant understands more aura, group-frame, bar, overlay, load-condition, and followup requests.",
                        "Castbar width mode, castbar text, Interrupt Ready refresh, and class-bar quick setup issues were fixed.",
                        "Group-frame layout, group status refresh, menu keyboard handling, unit-frame prediction updates, and font checks were tightened up.",
                        "Local development files, stale bytecode output, and release packaging were cleaned up for the beta build.",
                    },
                },
                {
                    title = "What To Test First",
                    bullets = {
                        "Import or copy a 5.60 profile, then check Player, Target, Focus, Boss, Target of Target, Focus Target, Party, Raid, and Mythic Raid.",
                        "Test auras on WoW 12.1: target swaps, focus swaps, party/raid conversion, dispellable debuffs, duration bars, cooldown text, stack text, aura dragging, and filters.",
                        "Test Party Targeted Spell Indicators in 5-player content with enemy nameplates enabled.",
                        "Test Class Resources on several classes/specs, especially shape presets, detached Player Power, the optional Player HP bar, and preview switching.",
                        "Test castbars for normal casts, channels, empower casts, Boss casts, Focus Kick, Interrupt Ready, and Blizzard/MSUF player castbar ownership.",
                        "Test profile strings, missing font/texture fallback, NSRT nicknames, external anchors, Edit Mode, and /reload after combat.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
