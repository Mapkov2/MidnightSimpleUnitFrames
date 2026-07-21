-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-Beta24",
    previousVersion = "6.0-Beta23",
    rangeLabel = "6.0-Beta23 -> 6.0-Beta24",
    entries = {
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
