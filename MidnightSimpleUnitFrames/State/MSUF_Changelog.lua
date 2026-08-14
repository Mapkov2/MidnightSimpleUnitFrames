-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.07",
    previousVersion = "6.06",
    rangeLabel = "6.06 -> 6.07",
    entries = {
        {
            version = "6.07",
            date = "2026-08-15",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Expanded Texture Layers into three independently configurable, HP-reactive decoration slots with shared gradients, threshold colors, opacity rules, target/combat conditions, presets, and runtime-faithful previews.",
                        "Added Chunked Health and Power Loss for Unit and Group Frames. Bars update immediately while a configurable loss trail shows recently spent Health or Power without polling.",
                        "Added profile-wide controls for Blizzard's Player Buff Frame and normal Debuff icons while keeping Private Auras and Deadly Debuff warnings available.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added direct Edit Mode popup controls for Custom Aura 1-4, Dots on Target, and Player Defensive Buffs, including position, size, spacing, reset, undo, Boss synchronization, and Menu focus.",
                        "Restored Spell Indicator bars with Blizzard's native aura-duration StatusBar, configurable growth direction, smoothing, timer text, geometry, color, alpha, and layer.",
                        "Increased the Menu Back and Forward buttons for easier navigation.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Group Aura lanes and Spell Indicators remaining visible for offline, phased, distant-map, or different-instance members. Presence updates remain coalesced and event-driven.",
                        "Fixed Unit Aura preview handles requiring a second click before their X/Y controls appeared after switching lanes. The first click now survives the settings-page rebuild.",
                        "Fixed Target of Target identity and color events being routed through the Target frame without unit filtering. Updates now listen only to targettarget, and foreign unit events can no longer recolor the Target health bar.",
                        "Fixed Texture Layer controls writing to the wrong slot and protected HP-driven alpha values being cached or compared from Lua.",
                        "Fixed Spell Indicator icon, bar, glow, and full-frame effect ownership, opacity, cleanup, preview parity, and layer ordering.",
                        "Fixed Level, Race, Class, and other name-relative status text drifting away from shortened or repositioned Unit Frame names.",
                        "Fixed stale Player portraits, Unit Aura settings writing to the wrong lane, and Objective Tracker state leaking through MSUF's Edit Mode bridge.",
                        "Fixed Class Resource preview text handles becoming trapped behind higher-layer bar visuals.",
                    },
                },
            },
        },
        {
            version = "6.07-Beta4",
            date = "2026-08-14",
            sections = {
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Level, Race, and Class text with Left to name / Right to name anchors floating away from shortened names. The text now follows the rendered name edge and only snaps to the shortening cut while the name actually overflows its configured width.",
                    },
                },
            },
        },
        {
            version = "6.07-Beta3",
            date = "2026-08-14",
            sections = {
                {
                    title = "Changes",
                    bullets = {
                        "Added direct Edit Mode popup controls for Custom Aura 1-4, Dots on target, and Player Defensive Buffs. Each lane can now adjust position, size, and spacing with reset, undo, Boss synchronization, Menu focus, and Assistant parity.",
                        "Restored Spell Indicator Display as: Bar with Blizzard's native C-side aura-duration StatusBar. Bars keep their configured geometry, color, alpha and layer while adding Growth-controlled fill direction, optional native smoothing and movable native timer text without Lua polling.",
                        "Increased the Back and Forward navigation buttons for easier Menu navigation.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Class Resource preview text handles becoming stuck behind higher-layer bar visuals.",
                        "Fixed Group Frame Spell Indicator glow previews differing from runtime effects. The preview now uses the shared runtime renderer and cleans up its effect owners when suspended.",
                        "Fixed Unit Aura handles losing their first-click selection when opening a lane rebuilt its settings page. Selection is now restored only onto the newly created Preview handle.",
                        "Fixed Spell Indicator full-frame effect opacity and layer ordering against render targets, Aura names, and other text. Persistent effects remain visible while editing, and the selected Group Frame Name Overlay stays above its source text.",
                        "Fixed name-relative Unit Frame status text ignoring the configured Name anchor and offsets.",
                        "Fixed Assistant questions and navigation requests applying settings, including enum values that were never stated. Pure small talk now keeps its conversation context without entering a settings lane.",
                        "Fixed Assistant requests about borders, Auras, text, colors, and other frame details falling through to whole-frame toggles or unrelated position controls. Scoped Highlight Borders now control their Aggro, Dispel, and Purge outlines together.",
                        "Fixed narrow Group Frame position phrases matching unrelated horizontal or vertical layout controls.",
                    },
                },
            },
        },
        {
            version = "6.07-Beta2",
            date = "2026-08-14",
            sections = {
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Texture Layer controls writing to the wrong texture after switching slots or opening another texture from the preview. Each control now remains bound to its own slot, and protected HP-driven alpha values are no longer cached or compared from Lua.",
                        "Fixed Spell Indicator icons and full-frame effects competing for AuraSlot ownership. Both styles now share one native Blizzard assignment while retaining independent element layers. Unsupported expiration-timed full-frame effects now fall back to the active-aura effect without secret-value hooks or polling.",
                        "Improved Assistant handling for conversational bar dimensions, rounded-frame requests, no-target load conditions, Raid filters versus Raid frame scope, Aura lane attributes, and outline layer wording.",
                        "Fixed narrow Assistant navigation, reset, and profile-copy requests being interpreted as broader setting changes.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
