-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.74",
    previousVersion = "5.73",
    rangeLabel = "5.73 -> 5.74",
    entries = {
        {
            version = "5.74",
            date = "2026-07-19",
            sections = {
                {
                    title = "Highlight",
                    bullets = {
                        "Rebuilt Castbar outlines for crisp, pixel-perfect borders at every UI scale across live Castbars, previews, and Boss Castbars.",
                    },
                },
                {
                    title = "Improvements & Fixes",
                    bullets = {
                        "Added independent Castbar icon-outline thickness using the configured Castbar border color.",
                        "Expanded Auto Width to Player, Target, Focus, and Boss Castbars with exact Unit Frame or Cooldown Manager matching and adjustable offsets.",
                        "Fixed imported profiles with legacy UI_Parent anchors causing an endless full Unit Frame reanchor loop, extreme idle CPU usage, and severe FPS loss; affected profiles are now repaired automatically.",
                        "Expanded Skyriding aura filtering to include Thrill of the Skies and both Flight Style auras, with per-Boss Unit Aura ignore-list overrides available again.",
                        "Preserved character-specific keybindings by no longer replaying account-wide stored bindings automatically.",
                        "Reopened the options menu on its last active page and corrected custom scrollbar dragging without idle polling.",
                    },
                },
            },
        },
        {
            version = "5.73",
            date = "2026-07-18",
            sections = {
                {
                    title = "Highlight",
                    bullets = {
                        "Import UnhaltedUnitFrames 12.1 profiles directly into MSUF with the load-on-demand UUF importer.",
                        "Added full support for Coolinator and Skiron CDM",
                    },
                },
                {
                    title = "Minor Bug Fixes",
                    bullets = {
                        "Fixed imported UUF profiles losing independent health-fill and missing-health transparency in live frames and previews.",
                        "Fixed aura icon size controls not staying synchronized between the menu and Edit Mode.",
                        "Fixed edge case Blizzard Cooldown Manager anchors shifting unit frames after instance and zone transitions.",
                        "Fixed visible Group Frame power bars shifting name text vertically in live frames and previews.",
                        "Fixed split health text updates relying on secret-string comparisons.",
                        "Fixed dragging third-party anchored unit frames and synchronizing cooldown-sized power bars.",
                    },
                },
            },
        },
        {
            version = "5.72",
            date = "2026-07-18",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "New load-on-demand importer for UnhaltedUnitFrames 12.1 profiles.",
                        "New Unit and Group preview controls: zoom, pan, quick actions, and direct settings links.",
                        "Per-unit Blizzard frame ownership for Player, Pet, Target, Target of Target, Focus, Focus Target, and Boss frames.",
                    },
                },
                {
                    title = "Import & Layout Fidelity",
                    bullets = {
                        "Native conversion of supported frame, aura, castbar, indicator, color, texture, alpha, range, text, and position settings.",
                        "Safer imports with warnings, conversion reports, transactional profiles, and active-profile protection.",
                        "Improved Target of Target text, per-frame textures, legacy indicator sizes, custom status icons, and matching previews.",
                        "Automatic on-screen correction for imported and manually moved Unit and Group Frames.",
                    },
                },
                {
                    title = "Fixes & Polish",
                    bullets = {
                        "Fixed range fading for complete Unit Frames.",
                        "Improved Group previews, aura controls, Edit Mode dragging, change history, font previews, menu scaling, and search.",
                        "Fixed overlapping Blizzard-frame notices in compact Unit Basics layouts.",
                    },
                },
            },
        },
        {
            version = "5.71",
            date = "2026-07-11",
            sections = {
                {
                    title = "Hotfix",
                    bullets = {
                        "Fixed repeated ADDON_ACTION_FORBIDDEN errors on Warrior login caused by the Whirlwind tracker registering COMBAT_LOG_EVENT_UNFILTERED while Class Resource was disabled.",
                        "Restored the lightweight 5.6 spellcast-driven Whirlwind generator tracking and removed the global combat-log listener.",
                        "Bound Whirlwind tracker events only while the Warrior Class Resource is active and cleanly unbound them when the feature is disabled.",
                    },
                },
            },
        },
        {
            version = "5.70",
            date = "2026-07-08",
            sections = {
                {
                    title = "Patch Highlights",
                    bullets = {
                        "Moved the MSUF2 navigation rail into the 6.0-style layout while keeping the 5.x feature set intact.",
                        "Added optional navigation rail icons for existing profiles, with icons disabled by default for fresh profiles.",
                        "Added smooth menu scrolling with a Misc option to disable it.",
                        "Added scope-aware Frame Outline strata and frame-level offset controls for unit frames and group frames.",
                    },
                },
                {
                    title = "Bug Fixes",
                    bullets = {
                        "Fixed Group Frame Outline geometry so secure-header refreshes cannot reset the outline to the inner bar bounds.",
                        "Fixed Group Frame Outline live refresh so opening or using the options menu no longer requires a reload to apply the outline correctly.",
                        "Fixed Group Frame mouseover, target, and focus highlight strata so selected or hover borders no longer draw over Blizzard panels while aggro and dispel highlights keep their priority.",
                        "Fixed Unit Auras scope override clipping in compact layouts.",
                        "Fixed Class Resource menu clipping issues in compact layouts.",
                        "Fixed navigation rail icon positioning after closing and reopening the menu.",
                        "Restored scope controls on Unit Frames and Group Frames pages after the nav rail layout update.",
                        "Fixed Warrior Whirlwind cleave stacks so the bar only appears after a valid Improved Whirlwind target hit.",
                        "Fixed the GCD castbar path for current WoW cooldown APIs.",
                    },
                },
                {
                    title = "General Changes",
                    bullets = {
                        "Replaced the menu logo with the current MSUF logo.",
                        "Added a WoW 12.1 compatibility warning for MSUF 5.x stable builds that points users to the current CurseForge Beta.",
                        "Kept the new outline strata, frame-level, smooth-scroll, icon, and layout apply work on cold menu paths.",
                        "Kept combat and castbar fixes event-driven and cache-aware without adding constant polling.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
