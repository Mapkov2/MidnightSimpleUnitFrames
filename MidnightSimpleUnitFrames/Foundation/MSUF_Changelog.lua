-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.5 Beta 3",
    previousVersion = "5.5 Beta 2",
    rangeLabel = "5.5 Beta 2 -> 5.5 Beta 3",
    entries = {
        {
            version = "5.5 Beta 3",
            date = "2026-05-22",
            sections = {
                {
                    title = "Beta 3",
                    bullets = {
                        "Fixed a Range Fade protected-call warning by keeping the CheckInteractDistance fallback out of combat while preserving spell-based range checks and out-of-combat fallback behavior.",
                    },
                },
            },
        },
        {
            version = "5.5 Beta 2",
            date = "2026-05-22",
            sections = {
                {
                    title = "Beta 2",
                    bullets = {
                        "Fixed a Menu2 preview helper load error caused by ambiguous Lua function-call syntax when creating rounded masks.",
                    },
                },
            },
        },
        {
            version = "5.5 Beta 1",
            date = "2026-05-22",
            sections = {
                {
                    title = "Beta 1",
                    bullets = {
                        "Reworked the Unit Auras setup page around a clearer first-pass workflow with Essentials, Scope, Preset & View cards, visible-unit toggles, quick presets, Basic / All settings modes, reset actions, and a live aura preview.",
                        "Fixed Group Frame disabled fallback ownership so Blizzard default behaves like the old off-state: Blizzard only takes over when all MSUF group-frame scopes are off, while any active MSUF party, raid, or mythic raid scope keeps Blizzard group frames hidden.",
                        "Improved Group Frame disable/search wording so questions about turning off party or raid frames point directly to the Use MSUF group frames switch and the If this switch is off fallback dropdown.",
                        "Fixed the Group Frames Buffs & Debuffs text-option layout so cooldown and stack text controls can expand the section height instead of being clipped.",
                        "Continued splitting Menu2 internals into focused modules for search data, dropdown helpers, preview helpers, widgets, and the dashboard, keeping the runtime page builders smaller and easier to maintain.",
                        "Removed obsolete font resolver blocks from the old library/bootstrap path.",
                    },
                },
            },
        },
        {
            version = "5.41",
            date = "2026-05-21",
            sections = {
                {
                    title = "Patch Release",
                    bullets = {
                        "Restored the 5.32 MSUF keybind synchronization behavior and removed the new account-wide SaveBindings / LoadBindings path to avoid a reload-only keyboard input edge case where movement could become unresponsive until the game client was restarted.",
                        "Added /msuf inputdebug to print movement bindings, keyboard focus, MSUF edit state, and visible keyboard-enabled frames when diagnosing rare input-capture issues.",
                        "Reset keyboard input propagation when MSUF edit-mode popups, HUD panels, and picker overlays hide, so ESC-handled overlays cannot leave stale keyboard capture state behind.",
                        "Improved Auras2 handling for stealable buffs when mine-only, important-buff, and merged buff filters are active.",
                        "Refreshed runtime systems after profile switch, reset, import, and external profile overwrite so unit frames, auras, class power, powerbar embeds, and portrait decorations update without stale state.",
                        "Hardened Group Frame unit-slot cleanup during roster changes so stale debuff, dispel, status, highlight, and displayed-aura state cannot bleed into the next unit assigned to the same secure button.",
                        "Improved Class Power hidden-anchor handling and powerbar embed anchoring when class power is disabled or hidden.",
                        "Improved portrait decoration layout recovery when portrait containers are rebuilt or their anchor points change.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
