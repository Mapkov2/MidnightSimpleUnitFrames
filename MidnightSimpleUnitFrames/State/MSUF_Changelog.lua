-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.07-Beta4",
    previousVersion = "6.07-Beta3",
    rangeLabel = "6.07-Beta3 -> 6.07-Beta4",
    entries = {
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
        {
            version = "6.07-Beta1",
            date = "2026-08-14",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Texture Layers are now three fully configurable, HP-reactive decoration slots. Each texture can follow the shared low/mid/high HP gradient, switch to class or custom colors above a threshold, change opacity or appear only at low health, and combine current-target and combat-state rules. The reorganized setup adds quick Text Background and Highlight presets plus runtime-faithful previews, while HP reactions reuse the existing Health update path without polling.",
                        "Added Chunked Health and Power Loss for Unit and Group Frames. The live bar updates immediately while a short, configurable loss trail shows what was just spent or lost; Smooth and Chunked modes are mutually exclusive and share runtime-faithful previews, rounded-frame support, copy controls, and dedicated loss colors.",
                        "Added independent profile-wide switches for Blizzard's player Buff Frame and normal Debuff icons near the minimap. Private Auras and Deadly Debuff warnings remain visible, and the feature stays passive with no polling or recurring MSUF work.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Group Aura lanes and Spell Indicators remaining visible for members who are offline, phased, on another map, or inside a different instance group. Presence now composes with helpful/hostile assistability and fails closed through coalesced lifecycle events. Identity, phase, and connection changes remain combat-live, while cold map and instance reconciliation is deferred into one post-combat pass.",
                        "Removed the Objective Tracker from MSUF's Blizzard Edit Mode bridge to avoid propagating dirty layout state into combat-secret UI paths. The tracker remains fully Blizzard-owned, and Group Edit Mode now relies on its single shared state listener.",
                        "Fixed native Player portraits occasionally remaining stale or blank after login or world entry.",
                        "Fixed several Unit Aura layout settings writing to the wrong scope, including lane visibility and separate Buff/Debuff style padding.",
                        "Improved Assistant handling for natural highlight on/off requests, texture names without connector words, border styles and opacity, outline layers, absorb height, gradient intensity, and how-to navigation. Unmatched navigation requests now offer the closest controls without changing settings.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
