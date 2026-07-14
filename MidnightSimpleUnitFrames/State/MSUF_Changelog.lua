-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-Beta16",
    previousVersion = "6.0-Beta15",
    rangeLabel = "6.0-Beta15 -> 6.0-Beta16",
    entries = {
        {
            version = "6.0-Beta16",
            date = "2026-07-14",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added shared Buff Aura Style controls for Party and Raid spell indicators.",
                        "Added a generated Assistant control schema for safer exact menu navigation and actions.",
                        "Refined Menu2 frame controls, previews, and visual layout.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Fixed castbar channel ticks to always honor the global visibility switch.",
                        "Added configurable bar gradients, textures, transparency, and minimap-icon positioning.",
                        "Hardened Assistant value validation, cancellation, undo/redo, and action-input handling.",
                        "Added Assistant schema and spell-indicator regression coverage to the release gate.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta15",
            date = "2026-07-14",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added a guided Beta 15 upgrade highlights flow and refined first-load onboarding.",
                        "Added configurable castbar name/target text.",
                        "Added group-frame role icons and mouse-drag positioning for spell icons directly in the preview.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Refined first-load routing and guided setup behavior.",
                        "Added configurable castbar target text.",
                        "Added NPC class colors and name-relative status anchors for unit frames.",
                        "Stabilized spell-indicator geometry and aura filtering.",
                        "Hardened Menu2 scrolling for secret values and refreshed layout behavior.",
                        "Expanded regression smoke coverage for the updated runtime paths.",
                        "Gated castbar lifecycle and hotpath events to active features.",
                        "Reseeded visible prediction bars after world entry and cold-start recovery.",
                        "Added group-frame role icons and live spell-indicator preview placement.",
                        "Detached event routes for disabled features to reduce idle work.",
                        "Unified Menu2 and Edit Mode layout tokens.",
                        "Updated prediction and locale-aware default baselines.",
                        "Added the Beta 15 upgrade highlights flow and onboarding integration.",
                        "Added lifecycle and group-frame regression coverage for the Beta 15 changes.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta14",
            date = "2026-07-13",
            sections = {
                {
                    title = "Changes",
                    bullets = {
                        "Coalesced and interned core runtime update paths to reduce duplicate work.",
                        "Added compact/abbreviated HP values and full-value HP formatting support where relevant.",
                        "Stabilized group layout behavior with adaptive roster scaling and improved group runtime refresh ordering.",
                        "Added configurable aura lane sorting, filtering, and improved aura growth/local budget handling.",
                        "Improved class text and group text settings to keep health formatting and preview states in sync.",
                        "Expanded assistant setting routes, guided actions, and conversational workflow behavior.",
                        "Improved assistant diagnostics and control routing to match current menu pages and workflows.",
                        "Refreshed release/tooling inventories and updated runtime release metadata handling.",
                        "Wired HP abbreviation into group text runtime specs and kept runtime specs aligned with feature changes.",
                        "Interned group lifecycle work plans and tightened status updates for gone-state and lifecycle transitions.",
                        "Scaled castbar lifecycle and hotpath handling to active casts only for lower per-frame overhead.",
                        "Compiled ClassPower mode runtime state and improved aurawork layout stability in active runtime paths.",
                        "Optimized frequent color pathups with font/color fast paths.",
                        "Reduced redundant visibility, metadata, and power-cached update work in hot paths.",
                        "Streamlined prediction geometry caching and dependent-unit routing.",
                        "Fixed player profile refresh to correctly apply alpha state.",
                        "Refreshed menu theme/history feedback and exact setting-control resolution flow.",
                        "Restored event-driven profile lifecycle behavior for target-sound handling.",
                        "Updated Menu2 runtime and onboarding UX: first-load plus guided-tour states and pages.",
                        "Expanded and cleaned Menu2 page/preview/runtime navigation for onboarding and grouped workflows.",
                        "Updated smoke tests (including hotpath/coldpath coverage) and hardened release helper scripts.",
                        "Extended Menu2/runtime coverage for new UI/locale paths and connected frame, aura, castbar, chat, EventBus, edit-mode, and range-fade behavior.",
                        "Fixed Auras3 positioning after zone transitions so Auras3 layout remains correct after entering a new zone.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta13",
            date = "2026-07-12",
            sections = {
                {
                    title = "Changes",
                    bullets = {
                        "Stabilized Class Power textures, detached power shapes, and targeted unit-frame refreshes.",
                        "Improved class portrait fallbacks for transient and new Blizzard class tokens.",
                        "Smoothed Menu2 visuals, scrolling, menu fonts, and Assistant startup behavior.",
                        "Expanded Assistant parsing, setting navigation, and exact control routing.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
