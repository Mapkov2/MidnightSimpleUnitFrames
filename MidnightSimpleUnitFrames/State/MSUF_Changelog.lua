-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.07-Beta1",
    previousVersion = "6.06",
    rangeLabel = "6.06 -> 6.07-Beta1",
    entries = {
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
        {
            version = "6.06",
            date = "2026-08-13",
            sections = {
                {
                    title = "Changes",
                    bullets = {
                        "Added a Non-Player Auras Debuff filter for Unit and Group Frames, including Menu, profile import, diagnostics, and Assistant support. It keeps encounter and environment Debuffs while excluding effects caused by players or player pets.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed an edge case where Player, Target, Boss, and other Unit Frame health text remained hidden after importing profiles with a conflicting obsolete visibility value. Current profile settings now always win, while legacy-only profiles retain their previous behavior without profile rewrites or recurring runtime work.",
                        "Fixed the MSUF Game Menu button using mismatched dimensions and styling. It now follows the active Game Menu button template, size, font, and EllesmereUI skin without stretching.",
                    },
                },
            },
        },
        {
            version = "6.05",
            date = "2026-08-13",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Reworked Augmentation Evoker resources into one coherent Player Power surface: segmented Essence remains visible while Ebon Might uses its own native duration row. Runtime, embedded and detached layouts, rounded styling, text layers, Menu previews, search, and the Assistant now share the same geometry and ownership.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added Unit Frame load conditions for No target and Out of combat and no target, including Copy To, search, diagnostics, and Assistant control.",
                        "Added a dedicated Class Resource text layer so resource numbers, Rune times, and Ebon Might duration text can be ordered independently from the resource bar and normal Player Power text.",
                        "Added a delayed warning with a direct settings shortcut when Unit Frames are configured to follow Essential Cooldowns but no supported Blizzard or third-party cooldown anchor is active.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Spell Icon Full-Frame Effects ignoring their configured element layer. Effects now use a frame-local surface so their 0-30 layer orders correctly against bars, text, and other Unit Frame elements.",
                        "Fixed helpful and hostile Group Aura owners retaining invalid exact-ID assignments after assistability, roster-presence, or instance transitions. Updates remain event-driven and fail closed without polling or restricted Aura reads.",
                        "Fixed Interrupt Ready colors and Focus Kick state becoming stale when a protected cooldown completed. MSUF now uses Blizzard's native duration completion callback with a one-shot fallback and ignores unrelated cooldown events.",
                        "Fixed Group Range Fade briefly treating members from another instance or phase as in range after portal and party-presence transitions.",
                        "Fixed Castbars jumping when switching between Unit Frame anchoring and independent Edit Mode placement.",
                        "Fixed later canonical Aura profile revisions being mistaken for legacy data eligible for the original Aura reset.",
                        "Refreshed cached Menu pages when reopening MSUF, made exported profile strings immediately selectable for copying, and exposed the HEX value in the compact color picker.",
                        "Improved Assistant handling for direct control wording, target-aware visibility requests, outline sizing, background textures, and maximum-health-loss textures.",
                    },
                },
            },
        },
        {
            version = "6.04",
            date = "2026-08-13",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Reworked Unit Frame Auras around explicit lane ownership. Every Buff and Debuff lane now owns its exact layout, filtering, text, effect, and visibility settings, while icon appearance remains global by Aura type. Existing profiles retain their visible setup, and runtime, Menu, Edit Mode, search, and the Assistant now use the same ownership model.",
                        "Added a profile-specific option to disable Northern Sky Raid Tools nicknames on MSUF frames without changing NSRT or its settings. The integration remains enabled by default and can also be controlled through the Assistant.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Reduced recurring work on frequent Health and Texture Layer events. Health prediction and text followers now skip already-pending updates, while dynamic Texture Layers refresh only affected slots, use color-only updates where possible, and reuse their runtime objects.",
                        "Fixed the Elite Indicator missing from Unit Frame previews. Elite, Rare Elite, Rare, and Boss classifications now use their matching Blizzard icons in runtime and previews while sharing one position, size, and layer.",
                        "Fixed identity-dependent Aura displays becoming stale after taxi transitions and helpful Group auras remaining visible when their caster identity could no longer be verified out of range. The existing range and lifecycle events now refresh them without polling.",
                        "Fixed sorted or filtered Raid headers temporarily omitting roster members when unit-name data lagged behind the authoritative Raid roster. MSUF now waits for a complete name list and otherwise falls back to Blizzard's native roster path.",
                        "Fixed Tracked Buffs silently inheriting the normal Buff container's sort method and direction instead of using their own ordering.",
                        "Fixed Group Frame preview borders not repainting immediately, and fixed rounded borders overwriting active Aggro or Dispel test colors after the preview refresh.",
                        "Kept reload-required popups above the MSUF options window and expanded Unit Frame Basics sections so their controls no longer clip.",
                        "Improved the disabled Options-module error so it tells the user to enable MSUF Options in Blizzard's AddOns menu.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
