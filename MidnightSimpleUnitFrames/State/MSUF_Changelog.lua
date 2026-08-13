-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.05",
    previousVersion = "6.04",
    rangeLabel = "6.04 -> 6.05",
    entries = {
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
        {
            version = "6.03",
            date = "2026-08-12",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Track any group buff from any specialization. Group Frame Spell Icons now provide a shared All Specs workspace, so entries such as Feint can be configured once and remain active across every character specialization.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Multi-Spec now exposes all 40 Retail specializations. Custom Aura IDs can also be added to an individual specialization, allowing a Holy Priest configuration, for example, to track Feint (1966) on another group member while Only show my casts is disabled.",
                        "Added a curated, class-wide Big Defensive Spell-ID filter for friendly Unit and Group Frames, with Blizzard's native classification as the restricted-data fallback. Aura classification choices are now mutually exclusive while Only mine and Also include nameplate-only remain explicit modifiers, and Menu, search, and the Assistant share the same contract.",
                        "Added direct Assistant control and cold-path diagnostics for Unit Frame Buff and Debuff Full-Frame Effects. Menu and Assistant now share the same effect choices without polling or reading protected native Aura visibility.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Target of Target and Focus Target health bars and names losing class colors when WoW protects dependent-unit class data in combat. Protected colors now flow directly through Blizzard-native color sinks without polling or persistent secret-value caches.",
                        "Fixed Health and Power gradients missing or differing in Unit and Group previews. Embedded, detached, and rounded Power previews now reuse the same gradient composition as runtime rendering.",
                        "Fixed Level, Race, and Class text in Unit Frame previews using the default preview font instead of the selected unit font.",
                        "Made Cleanse Border changes request the required UI reload.",
                        "Kept the Player Castbar provider selectable in the Bars menu.",
                        "Fixed native Aura containers triggering a forbidden EventRegistrations error during Unit Frame aura setup.",
                        "Improved the ownership handoff between MSUF and Blizzard Party/Raid frames. Provider and fallback changes now return frames reliably through Blizzard's own lifecycle and request the required UI reload.",
                        "Fixed Clique and other click-cast providers losing their Unit Frame bindings after profile or configuration updates. MSUF now preserves provider-owned secure click attributes after the initial fallback setup.",
                        "Isolated Group Spell Indicator preview positions from live saved positions.",
                        "Restored continuous Devourer class-resource updates and removed obsolete partial-update ownership from the resource pipeline.",
                        "Fixed Icicles showing an Aura icon over Class Resources or retaining incorrect stack counts. Icicles now refreshes the exact player Aura on each Aura change, while protected Icicle and Maelstrom Weapon counts fill their pips through Blizzard's native StatusBar clamping without Lua comparisons.",
                        "Fixed Tip of the Spear showing incorrect stacks after current Survival Hunter spenders and Takedown with Twin Fangs. Stack tracking now also expires correctly without protected Aura reads.",
                        "Fixed native Auras, Spell Indicators, and Aura-based Class Resources becoming stale or retaining incorrect durations after cinematics and entering the world. Lifecycle refreshes are now coalesced and event-driven without polling.",
                        "Refreshed Unit Frame names immediately after anchor changes.",
                        "Restored live Group frames correctly after preview roster handoffs.",
                        "Honored configured Aura layers for fixed Group slots.",
                        "Fixed the animated Resting symbol trying to use an unavailable Blizzard atlas; unsupported clients now fall back safely.",
                        "Fixed Unit Frame Edit Mode quick actions applying stale compiled settings after size, position, reset, copy, or detached Power changes.",
                    },
                },
            },
        },
        {
            version = "6.02",
            date = "2026-08-11",
            sections = {
                {
                    title = "WoW 12.1 Release Highlights",
                    bullets = {
                        "Split Unit Preview Buffs and Debuffs into independent layers with correct handle-to-menu routing, and expanded the frame-local Debuff blacklist presets.",
                        "Added Blizzard-native Ebon Might duration text plus safe, independently configurable Alternative Mana width geometry across runtime, previews, search, and the Assistant.",
                        "Made Blizzard's animated Resting symbol part of the fresh default profile while preserving existing profile choices and live Resting state.",
                        "Reworked the upgrade-highlight tour around real Back/Forward navigation and added Assistant commands that can restart a skipped or completed tour.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed nickname-provider fallback refreshes so updated names reach the correct Unit and Group Frames without broad polling.",
                        "Guarded secret Player Health values before Class Resource logic can inspect them in combat.",
                        "Fixed Texture Layer target refreshes, rounded clipping, true-outline geometry, rounded preview edges, and Castbar preview text positions after live setting changes.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
