-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.04",
    previousVersion = "6.03",
    rangeLabel = "6.03 -> 6.04",
    entries = {
        {
            version = "6.04",
            date = "2026-08-12",
            sections = {
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed the Elite Indicator missing from Unit Frame previews. Elite, Rare Elite, Rare, and Boss classifications now use their matching Blizzard icons in runtime and previews while sharing one position, size, and layer.",
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
        {
            version = "6.01",
            date = "2026-08-10",
            sections = {
                {
                    title = "Final Beta Release Highlights",
                    bullets = {
                        "Expanded Texture Layers with a built-in target-highlight recipe, Current Target visibility, custom-class-color following, automatic sizing, top/bottom texture cropping, and Original or Monochrome source treatment.",
                        "Added real eight-piece outline media alongside the existing solid and stretched-texture Frame Outline styles.",
                        "Added optional rounded rectangular Class Resources and Blizzard's animated native Resting symbol across live frames and previews.",
                        "Refreshed the complete fresh-install visual baseline with cohesive dark bars, warm target accents, and deliberate 6.01 defaults without changing existing profiles.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed nickname-provider Target refreshes so only the affected Unit and Group Frames are invalidated, with combat changes still coalesced safely.",
                        "Fixed restricted 12.1 Class Resource values hiding their text in combat; protected values now pass directly to Blizzard's native text and StatusBar sinks while preserving configured styling.",
                        "Fixed Unit Copy To bypassing its action guard and reporting unsupported Castbar copies as successful. Pet, Target of Target, and Focus Target now skip Castbar settings explicitly while mixed copies keep every supported category.",
                        "Fixed Castbar Spell, Time, and Target text using different layout rules in the Unit Preview than on the live runtime castbar.",
                        "Fixed Manual Detached Power width losing authority to a synchronized width source in Edit Mode and Menu controls.",
                        "Fixed Boss portrait refreshes missing frames that had not yet been seeded into the Edit Mode registry.",
                        "Fixed rounded mouseover edges retaining their previous color until the next hover transition.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
