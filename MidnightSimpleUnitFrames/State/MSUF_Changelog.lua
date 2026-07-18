-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-Beta22",
    previousVersion = "6.0-Beta21",
    rangeLabel = "6.0-Beta21 -> 6.0-Beta22",
    entries = {
        {
            version = "6.0-Beta22",
            date = "2026-07-19",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added target DoT lanes with curated class spells and full-frame effects.",
                        "Unified Undo and Redo across Menu2 and Edit Mode.",
                        "Added beginner Quick Setup, Coolinator anchors, and scoped icon zoom.",
                        "Refined color tools, Menu search, and window controls.",
                    },
                },
                {
                    title = "Fixes",
                    bullets = {
                        "Fixed clipped Level and status-indicator controls.",
                        "Improved castbar interrupt feedback and inactive resync handling.",
                        "Reduced Unit Frame and Menu runtime work, especially during combat.",
                        "Preserved legacy group text geometry, class-resource stacks, and character keybindings.",
                        "Completed Beta 22 Menu translations and regression coverage.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta21",
            date = "2026-07-18",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added separate Blizzard-frame controls for each unit.",
                        "Completed all Menu2 and Priority Frames translations.",
                        "Added ten new bar textures.",
                        "Expanded text, absorb, and prediction settings.",
                        "Improved cooldown-frame width syncing.",
                        "Reduced Menu and Guided Tour workload.",
                    },
                },
                {
                    title = "Fixes",
                    bullets = {
                        "Frames and previews now stay on screen.",
                        "Fixed incorrect pet-frame colors.",
                        "Fixed Color Painter previews.",
                        "Preview zoom is now preserved.",
                        "Improved old profile migration.",
                        "Improved Assistant controls and recovery.",
                        "Added more regression tests.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta20",
            date = "2026-07-16",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added Pinned Frames (Priority Frames): keep up to five manually pinned group members or automatic tanks in a stable extra strip with hover-hotkey pinning, inherited Party/Raid visuals and click-casting, plus attached or free Edit Mode placement.",
                        "Kept Auras, status indicators, targeted spells, identity updates, and group lifecycles synchronized across normal and duplicated Priority Frames.",
                        "Improved Range Fade for PTR-restricted unit payloads and movement-driven target/focus fallbacks without restoring continuous polling.",
                        "Fixed resurrection status recovery, removed duplicate dependent-unit prediction reads, and tightened mouseover-highlight hot paths.",
                        "Expanded profile compatibility, Priority Frames import/export, Menu and Edit Mode integration, Assistant guidance, and regression coverage.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added character-specific manual pins, automatic tank selection, one-to-five visible slots, stable ordering, and duplicate prevention for Priority Frames.",
                        "Added a managed hover hotkey with conflict handling, manual pin controls, attached placement, configurable growth and spacing, and a dedicated free-position mover.",
                        "Inherited the active Party, Raid, or Mythic Raid appearance and click-cast behavior while keeping Priority layout settings profile-wide.",
                        "Deferred secure Priority roster and layout changes safely during combat and kept selection event-driven with no ticker or OnUpdate loop.",
                        "Updated Auras, ready checks, targeted-spell icons, names, group status, lifecycle fanout, and visual refreshes for every exact frame copy of a unit.",
                        "Hardened Range Fade for secret UNIT_IN_RANGE_UPDATE payloads, split filtered unit registrations safely, and limited fallback checks to movement while needed.",
                        "Rechecked dead, ghost, and offline labels after resurrection even when PTR group health values remain protected.",
                        "Coalesced dependent-unit prediction with the authoritative identity refresh to avoid duplicate calculator reads.",
                        "Corrected legacy Aura2 offsets, legacy range-fade portrait migration, partial 5.57 snapshot detection, and Priority Frames profile payload handling.",
                        "Removed per-hover DB/global reads from rounded and standard mouseover highlights and kept disabled paths lean.",
                        "Improved power-color preview parity, binding and specialization status refreshes, Priority Edit Mode cancel/reset behavior, and Menu search routing.",
                        "Added Assistant navigation, safe setting control, pinning guidance, troubleshooting, and performance help for Priority Frames.",
                        "Expanded Lua 5.1 runtime, secure-header, lifecycle, migration, binding, Menu, Assistant, Range Fade, prediction, and duplicate-frame regression coverage.",
                        "Removed obsolete development mockups and audit artifacts from the addon source tree.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta19",
            date = "2026-07-16",
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
                        "Added spell-specific channel tick markers and the new MSUF Lucent bar texture.",
                        "Kept Group Frame foreground indicators above full-frame Aura effects and made expiring effects PTR-safe.",
                        "Fixed Blizzard castbar ownership, first-load Dashboard state transitions, group-frame login anchors, and scaled-menu screen-edge snapping.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added scoped gradient controls with independent Health and Power settings and live preview updates.",
                        "Added configurable cast-target name colors across live castbars and previews.",
                        "Replaced fixed channel lines with spell-specific tick markers and a safe fallback for unsupported channels.",
                        "Added the bundled MSUF Lucent status-bar texture across the addon and Assistant media resolver.",
                        "Added native maximum-duration filtering for unit and group-frame Debuffs.",
                        "Reorganized Spell Indicators into outcome-focused spell, placement, health-bar highlight, and appearance cards.",
                        "Added configurable expiring thresholds for Spell Indicator icon glows and frame effects while keeping protected Aura duration decisions C-side.",
                        "Anchored Spell Indicator frame effects to the live health fill and added independent effect layers, priorities, and safer automatic ordering with dispel effects.",
                        "Kept expiring Spell Indicator effects on the protected-duration-safe PTR path without runtime duration reads.",
                        "Raised Group Frame text, status icons, targeted spells, Aura icons, and corner indicators above full-frame effects in live frames and previews.",
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
