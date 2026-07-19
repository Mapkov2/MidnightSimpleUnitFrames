-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-Beta23",
    previousVersion = "6.0-Beta22",
    rangeLabel = "6.0-Beta22 -> 6.0-Beta23",
    entries = {
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
