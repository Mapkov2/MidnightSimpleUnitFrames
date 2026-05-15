-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.2 Beta 1",
    previousVersion = "",
    rangeLabel = "5.2 Beta 1",
    entries = {
        {
            version = "5.2 Beta 1",
            date = "2026-05-15",
            sections = {
                {
                    title = "Performance",
                    bullets = {
                        "Improved combat-aware update handling across auras, power bars, borders, castbars, portraits, status indicators, unit frames, and group frames.",
                        "Reduced unnecessary refresh work during combat, menu preview updates, aura rendering, and group frame effects.",
                        "Improved preview update behavior for unit frames, group frames, and castbars so menu changes feel smoother.",
                        "Restored and polished the one-click installer flow.",
                    },
                },
                {
                    title = "Bugfixes",
                    bullets = {
                        "Fixed several group frame, aura preview, and menu issues that could cause inconsistent previews or stale UI state.",
                        "Fixed additional Midnight beta combat restrictions by avoiding unsafe updates while combat lockdown is active.",
                        "Improved aura reminder, border, castbar, status icon, and interrupt-ready handling for safer beta behavior.",
                        "Made click-casting on unit frames more reliable.",
                    },
                },
                {
                    title = "Changes / Improvements",
                    bullets = {
                        "Added class-colored bar background support across unit frames and group frames.",
                        "Added the new Rested symbol for both Classic and Midnight-style rested indicators.",
                        "Improved the menu and dashboard experience with clearer, more user-friendly behavior.",
                        "Improved unit frame and group frame previews so layout, colors, castbars, and aura changes are easier to verify before applying.",
                        "Improved advanced color, global, profile, group layout, group aura, group indicator, and unit settings pages.",
                        "Improved Class Power setup and brought back the one-click installer.",
                        "Improved group frame rendering, spell indicators, aura previews, and range/highlight behavior.",
                        "Improved castbar preview behavior, boss castbar preview text, and castbar anchoring.",
                        "Improved Edit Mode mover and popup behavior.",
                        "Updated bundled changelog support so the in-game dashboard can show the 5.2 Beta 1 notes.",
                        "Prepared the addon for the 5.2 Beta 1 release.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
