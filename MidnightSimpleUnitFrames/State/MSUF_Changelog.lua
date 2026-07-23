-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-Beta26",
    previousVersion = "6.0-Beta25",
    rangeLabel = "6.0-Beta25 -> 6.0-Beta26",
    entries = {
        {
            version = "6.0-Beta26",
            date = "2026-07-23",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Expanded the Assistant with more natural explanations, follow-up context, safer scope selection, and stronger move, anchor, color, number, enum, and boolean request handling.",
                        "Reworked Unit Frame and Group Frame runtime paths to share event-owned identity and value state, coalesce text and prediction refreshes, and remove unnecessary idle, range, threat, and lifecycle work.",
                        "Unified 12.1 Group Aura slot ownership for Spell Indicators, dispel visuals, and fixed external icons, including secret-safe party range gating and safer native container reuse.",
                        "Added clearer Group Frame provider controls for MSUF, normal Blizzard ownership, forced Blizzard frames, and fully disabled frames.",
                        "Added an optional \"Show cast spell icon in portrait\" mode that temporarily replaces 2D or class portraits during casts, channels, and empowered spells.",
                        "Added compact top-right three-dot color shortcuts across supported Menu2 cards so their exact scoped colors open directly in the shared color picker.",
                        "Improved Aura styling workflows and live previews across Menu2, Edit Mode, Unit Frames, Group Frames, and custom Aura containers.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Split status text presentation from status icons and migrated existing Unit Frame and Group Frame profile values automatically.",
                        "Made Health, Power, Class Resource, and Alternative Mana smoothing explicit opt-in settings while preserving Quick Setup as an intentional smoothing preset.",
                        "Simplified contextual text editing, added direct Bars/Aura/Text color targets, refined accordion and dashboard visuals, and suppressed redundant shortcuts on the dedicated Colors page.",
                        "Completed Menu2/Edit Mode source coverage for all shipped locales, including the new portrait, provider, status, Aura, and color-picker controls.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Reduced Castbar first-cast work, duplicate native cleanup, and Auto Width fan-out with per-source dirty routing and reusable geometry state.",
                        "Kept Blizzard's native Target and Focus Castbars untouched unless the frame is explicitly owned by MSUF.",
                        "Reduced duplicate health, power, class-color, NPC-kind, status, prediction, and text reads across hot event paths.",
                        "Coalesced text and prediction rendering, narrowed Group Frame event routing, retired stale unit subscriptions, and cancelled inactive range timers immediately.",
                        "Consolidated compatible Group Aura slots and flowing icons into shared native owners, including secure-header container birth and separate secret-safe Party range gating.",
                        "Compiled lean Health, Power, Prediction, and Threat routes for Group Frames, reusing resolved values directly and skipping consumers that have no visible work.",
                        "Kept suspended secure Group Frame children in a stable inventory so roster rebinds reactivate them without duplicate entries or stale active routing.",
                        "Improved offline Group Frame visibility, status targeting, level/name anchoring, secret-safe absorb handling, and profile migration behavior.",
                        "Expanded the Core Lua 5.1 suite to 152 passing runtime, Menu2, Assistant, Aura, Castbar, Group Frame, smoothing, status, and hotpath regression tests.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta25",
            date = "2026-07-21",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added a customizable Maximum Health Loss overlay for Unit Frames and Group Frames, with texture, loss color, overlay opacity, background opacity, and a live effect preview.",
                        "Replaced the old shadow-strength presets with a scoped Shadow Opacity slider and 1 px / 2 px Shadow Distance controls; existing profile values migrate automatically.",
                        "Added independent Font Size controls for each selected left, center, and right Health/Power text slot, with matching live previews.",
                        "Added real opacity controls for Health and Power backgrounds, including exact live-preview parity and consistent class-colored backgrounds.",
                        "Refined Menu2 with compact reference previews, clearer shared settings layouts, and highlighted open accordion sections.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added compact and expanded preview modes across Unit Frame, Group Frame, Class Resource, and Color Painter workflows.",
                        "Unified repeated settings and color-card layouts for clearer navigation and more consistent controls.",
                        "Improved Group Preview ownership so heavy native previews can be reused safely between Group Frame pages.",
                        "Updated all supported locales for the new font, background, preview, and maximum-health-loss controls.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Reduced Menu2 opening, resizing, search, font-refresh, Color Painter, and preview work through lazy section builds, reusable layouts, cached control metadata, and pooled preview targets.",
                        "Cached normalized search queries, font probes, profile reads, and Aura default seeding without adding idle or combat polling.",
                        "Fixed slider drags so the complete gesture, including the final released value, creates exactly one Undo/Redo step.",
                        "Fixed rounded frame masks on login and kept class-colored backgrounds correct for players, NPCs, pets, bosses, and temporarily missing units.",
                        "Prevented background opacity from being multiplied twice and kept color changes attached to the active imported profile.",
                        "Expanded Lua 5.1 regression coverage for Menu2 cold paths, preview lifecycles, text-slot sizing, opacity, history, Auras, and rounded-frame startup.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta24",
            date = "2026-07-21",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Rebuilt Colors and Color Painter with focused categories, clickable live previews, reusable brush colors, quick reset actions, and lazy loading for faster navigation.",
                        "Added global mouseover highlight styles: a portrait-safe soft gradient or solid border with configurable color and size across Unit Frames and Group Frames.",
                        "Expanded Unit Frame and Group Frame text controls with clearer slot editing, combined HP + Absorb formats, per-slot shield icons, color modes, placement, and layers.",
                        "Redesigned the Edit Mode quick popups and added customizable menu accent themes.",
                        "Added ArcUI cooldown anchors for supported third-party cooldown layouts.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added Player & Target, Party & Raid, Castbar, Aura, Power, and Class Resource color workspaces with matching preview targets and deep-link navigation.",
                        "Added Dark, Class Color, Unified, and Gradient health-color modes plus shared text-color controls inside the Colors workflow.",
                        "Moved mouseover highlight behavior to Miscellaneous while keeping its colors in Colors, and updated Menu search and Assistant routing accordingly.",
                        "Improved Edit Mode popup layouts, responsive controls, and direct access to the relevant Unit Frame, Group Frame, Aura, and Castbar settings.",
                        "Added menu accent presets, class-color accents, and custom accent colors.",
                        "Added a reload recommendation when switching the Player Castbar back to Blizzard's provider.",
                        "Removed the obsolete UUF profile importer and its no-longer-needed compression libraries.",
                        "Updated all supported locales for the new text, Colors, Color Painter, Edit Mode, and highlight controls.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Coalesced Group Frame header rebind, OnShow, and range-settle work so roster layout changes refresh once without adding polling or combat hot-path work.",
                        "Preserved configured health-bar backgrounds when health colors refresh.",
                        "Kept rounded and square mouseover highlights on cached, direct hover paths and live-applied style changes without a full color refresh.",
                        "Reused event-owned Unit Frame health, power, prediction, identity, and status state to avoid duplicate reads and unnecessary event routes.",
                        "Restored compact text-slot controls and changed status toggles to refresh in place.",
                        "Improved combined absorb text, class-colored HP text, Aura growth anchors, Castbar provider handling, Power visibility, screen clamping, and late-anchor retry behavior.",
                        "Expanded Lua 5.1 regression coverage for text, status, Edit Mode, ArcUI anchors, colors, highlights, Group Frame coalescing, and runtime routing.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta23",
            date = "2026-07-19",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Updated Edit Mode with a compact dockable toolbar, responsive layouts, auto-hide, and zero idle polling.",
                        "Rebuilt the Color Picker with progressive controls, palettes, precise RGB/HEX input, and faster color pages.",
                        "Added configurable Castbar icon-border thickness and pixel-perfect outlines across live frames and previews.",
                    },
                },
                {
                    title = "Fixes",
                    bullets = {
                        "Reduced Unit Frame and Group Frame runtime work by reusing event-owned health, power, prediction, and threat state.",
                        "Moved Group Frame database repair out of combat and steady runtime paths.",
                        "Fixed Castbar auto-width, native duration handling, secret-safe target colors, and outline colors after border changes.",
                        "Fixed legacy UI_Parent anchors and prevented repeated retries for unavailable custom anchors.",
                        "Fixed first-open custom Menu fonts, direct menu navigation, and Aura workspace sizing.",
                        "Completed Edit Mode and Color Picker translations and expanded regression coverage.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
