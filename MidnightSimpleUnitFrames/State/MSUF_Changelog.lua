-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-Beta19",
    previousVersion = "6.0-Beta18",
    rangeLabel = "6.0-Beta18 -> 6.0-Beta19",
    entries = {
        {
            version = "6.0-Beta19",
            date = "2026-07-15",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added separate Health and Power gradient colors, strengths, and directions, plus configurable cast-target name colors.",
                        "Rebuilt Spell Indicators with a clearer editor, expiring icon/frame effects, health-bar highlights, and precise effect layering.",
                        "Added an addon-wide 0-30 layer system and Layer Overview for unit frames, group frames, auras, borders, text, status icons, and class resources.",
                        "Added maximum-duration Aura filters, a full-health absorb stripe, and richer live previews for Auras, absorbs, detached power, Color Painter, and automatic group scaling.",
                        "Tightened Group Frame, boss-castbar, prediction, aggro, role, and load-condition lifecycles to prevent stale or duplicate runtime work.",
                        "Expanded the Assistant with direct Color Painter handoff, safer exact-setting changes, better failure recovery, and offline addon-compatibility guidance.",
                        "Fixed Blizzard castbar ownership, first-load Dashboard state transitions, group-frame login anchors, and scaled-menu screen-edge snapping.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added scoped gradient controls with independent Health and Power settings and live preview updates.",
                        "Added configurable cast-target name colors across live castbars and previews.",
                        "Added native maximum-duration filtering for unit and group-frame Debuffs.",
                        "Reorganized Spell Indicators into outcome-focused spell, placement, health-bar highlight, and appearance cards.",
                        "Added configurable expiring thresholds for Spell Indicator icon glows and frame effects while keeping protected Aura duration decisions C-side.",
                        "Anchored Spell Indicator frame effects to the live health fill and added independent effect layers, priorities, and safer automatic ordering with dispel effects.",
                        "Added an on-demand Layer Overview with editable 0-30 layers across frame text, status icons, auras, borders, bar outlines, group indicators, and class resources.",
                        "Normalized imported and existing numeric layer settings without adding idle events or timers.",
                        "Added a full-health absorb stripe with protected-value-safe rendering and matching absorb-anchor previews.",
                        "Improved Aura preview sizing, pinning, lane navigation, spell selection, and effect parity.",
                        "Added interactive previews for automatic Group Frame scaling breakpoints, absorb directions, detached power width, and layered indicators.",
                        "Consolidated Group Frame lifecycle routes and refreshed role-filtered aggro visuals only on the required cold paths.",
                        "Rebuilt load-condition visibility after world and zone transitions.",
                        "Repaired group-frame anchors after login/world entry and aligned role-icon defaults and preview behavior.",
                        "Hardened boss castbars around death, disconnect, targetability, and encounter transitions while keeping high-frequency health routing active-only.",
                        "Refined heal/absorb prediction plans, secret-value handling, and full-health/overflow edge rendering.",
                        "Limited Blizzard castbar suppression to the native player frame so the pet castbar keeps its own lifecycle.",
                        "Kept first-load state synchronized after SavedVariables repair and highlighted unfinished Guided Setup without reopening onboarding.",
                        "Corrected screen-edge snapping when the Menu is scaled below 100 percent.",
                        "Let Assistant color changes open the real Color Painter for the exact resolved setting and preserve normal history/cancel behavior.",
                        "Added safer scoped bar-outline color commands, read-only handling for subjective Aura requests, and clearer apply/flush failure recovery.",
                        "Added bundled guidance for addon compatibility, overlap, and dependency questions without changing MSUF settings.",
                        "Expanded generated Assistant catalogs, settings-inventory checks, release gates, Lua 5.1 runtime mocks, and regression coverage across Auras, castbars, layers, menus, predictions, profiles, and group frames.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta18",
            date = "2026-07-15",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Rebuilt castbar state, timing, and Blizzard-frame ownership for smoother updates, lower runtime work, and safer player/pet transitions.",
                        "Moved class-resource timing to native duration smoothing and tightened active-only runtime paths.",
                        "Improved legacy profile compatibility, including power anchors, status symbols, aura geometry, and import migration.",
                        "Refined typography, Color Painter scrolling, gameplay camera tracking, and prerelease version detection.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Consolidated player, target, focus, channel, and empower casts around one canonical cast identity and stable duration state.",
                        "Fixed Blizzard pet castbar suppression during world entry while preserving its native pet lifecycle.",
                        "Removed duplicate focus-cast event ownership and detached focus interrupt tracking completely while disabled.",
                        "Reduced redundant castbar timer binding, completion scheduling, visual refreshes, and cold-layout work.",
                        "Added native duration smoothing for class resources without adding idle polling.",
                        "Hardened legacy profile imports and preserved established power-bar anchors and status-symbol styles.",
                        "Aligned aura filtering, lane geometry, preview behavior, and live positioning.",
                        "Added semantic typography roles for more consistent text across frames, menus, Edit Mode, and popup tools.",
                        "Fixed mouse-wheel scrolling through Color Painter overlays and kept combat crosshair zoom synchronized with camera changes.",
                        "Corrected prerelease version comparisons across beta and stable version formats.",
                        "Expanded Lua 5.1 regression coverage for castbars, class resources, profiles, menus, unit frames, and runtime hot paths.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta17",
            date = "2026-07-15",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Reworked the Color menu into an interactive Color Painter with contextual targets, live Unit/Group previews, a color wheel, and recent/saved palettes.",
                        "Streamlined guided setup so its recommendations, navigation, and Edit Mode steps stay focused on the active configuration path.",
                        "Modernized Aura configuration for PTR 5 with safer native handling and more precise filtering choices.",
                        "Made Assistant follow-ups more reliable: actions now remain bound to the exact frame component you just changed.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Rebuilt the Color menu workflow with interactive previews for unit and group frames, direct color-context switching, and streamlined color editing.",
                        "Added live color previews for the refreshed Color Painter controls.",
                        "Refined the guided tour lifecycle, suggested next steps, navigation, and Edit Mode interaction flow.",
                        "Limited NPC class colors to friendly NPCs for clearer hostile-target presentation.",
                        "Updated native Aura handling for PTR 5, keeping configured anchors stable without accessing protected AuraButtons.",
                        "Removed legacy shared AuraButton layout work that conflicts with PTR 5 native ownership restrictions.",
                        "Added Important filters for Buffs and Debuffs.",
                        "Added separate group-dispellable and any-dispel-type filters for unit and group auras.",
                        "Added the matching Assistant commands, help text, control-catalog entries, and regression coverage for Aura filters.",
                        "Added group-aware dispel detection for borders and overlays, including Assistant routing and menu labels.",
                        "Added a direct in-window menu-scale slider with mouse-wheel support and immediate application.",
                        "Refreshed the modern factory profile: cleaner player stacking, compact power text, adjusted elite markers, and updated name presentation.",
                        "Fixed shortened-name limits beside level anchors, including safe handling while name widths are unavailable.",
                        "Improved Assistant routing for streamlined Group Frame pages and canonical guided-page references.",
                        "Hardened Assistant follow-ups for portraits, icons, text, colors, borders, sizing, and movement so they keep the intended component instead of falling back to the whole frame.",
                        "Expanded Assistant regression coverage for Group Frame contracts, retained-object follow-ups, exact text-color choices, and Aura filtering.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta16",
            date = "2026-07-14",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Streamlined Unit, Group, Cast Bar, and Class Resource menus with cleaner layouts, less redundant text, and fewer clipping issues.",
                        "Reworked Group Frame navigation: Text, Resource Bar, and Range Fade now live in Layout; Dispel Overlay and Debuff Stripe share a focused Dispel Overlay page.",
                        "Unified Unit, Group, and Class Resource previews and added live font previews in dropdowns.",
                        "Expanded the Assistant with safer exact menu actions, broader control coverage, faster search, and lower cold-start cost.",
                        "Improved guided setup and Edit Mode placement, and stabilized aura positioning after zone transitions.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added shared group Buff Aura Style support for spell indicators plus configurable bar gradients, textures, transparency, and minimap-icon positioning.",
                        "Fixed bar gradients, castbar channel-tick visibility, and aura repositioning after entering a new zone.",
                        "Fixed guided setup selecting disabled controls and improved skip, highlight, and placement behavior.",
                        "Hardened Assistant value safety, direct Search navigation, ambiguous commands, undo/action routing, and generated schema coverage.",
                        "Added reproducible serialized release gates, self-contained Assistant settings-catalog checks, and broader Menu2/preview regression coverage.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
