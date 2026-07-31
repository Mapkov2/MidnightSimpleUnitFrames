-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-Beta43",
    previousVersion = "6.0-beta42",
    rangeLabel = "6.0-beta42 -> 6.0-Beta43",
    entries = {
        {
            version = "6.0-Beta43",
            date = "2026-07-31",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Rounded unit and group frames now use a clean adjustable corner style with five strength levels. Health, embedded or detached Power, frame outlines, aggro/dispel/highlight borders and mouseover effects share the same geometry.",
                        "Profiles gained a redesigned management workspace with a persistent active-profile overview, responsive management cards, safer import/export guidance and clearer specialization assignments.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "The MSUF Assistant gained broader exact setting coverage for unit and group auras, text, bars, fonts and profiles, plus more useful local guidance for comparisons, troubleshooting and incomplete requests.",
                        "Unit and Group preview layer buttons now identify the currently selected draggable element, while responsive preview and profile layouts rebuild correctly after menu-scale changes.",
                        "Rounded-corner strength updates the lightweight preview during dragging and applies the live runtime once on release or after a short bounded delay.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed rounded Group frames, embedded Power bars, native Dispel overlays and modern frame borders losing or mismatching their outer mask, separator or border treatment.",
                        "Fixed the Rounded Texture preview overlapping the following Menu2 sections after the corner-strength control was added.",
                        "Fixed secret health colours reaching unsafe Lua comparisons in background matching, and made Group Power textures resolve once into the compiled cold-path configuration.",
                        "Fixed hidden Party-only Portrait sections reserving space in Raid/Mythic layouts and made Aura preview scaling tolerate accessible numeric values.",
                        "Fixed Assistant routing regressions for guided tours, natural health-text commands, contextual follow-ups and explicit negated or list-clearing commands.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta42",
            date = "2026-07-30",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Group External Defensives now use Blizzard's native 12.1 classification and can automatically stay out of the normal Buff lane while their dedicated lane is visible.",
                        "Unit and Group preview canvases can now use bright stone, a city scene, dark stone, Studio, or a custom color to check readability before applying settings.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Preview canvases start expanded after reload, keep configured frame outlines visible, and handle overlapping Aura controls more reliably.",
                        "Menu2 dropdowns stay inside their owning window; non-Midnight accents use a calmer shared highlight ramp across navigation and window controls.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Edit Mode dock dragging so it follows the cursor reliably, remains within the screen, and only snaps to an edge when released near one.",
                        "The explicit realtime Player Power Text option now follows the direct power-event update path; normal Power Text keeps its existing coalesced update behavior.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta41",
            date = "2026-07-30",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Aura and Spell Indicator icons can now scale independently from their unit or group frame. Buffs, Debuffs, External Defensives and Spell Icons each support 20% to 300% scaling without changing the surrounding frame.",
                        "Aura and Spell Indicator previews now consume the same finalized layout configuration as the live runtime across unit frames, Party, Raid, Mythic Raid and Edit Mode dummies.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Preview geometry now mirrors live anchor, growth, rows, spacing, offsets, alpha, layer, icon zoom, cooldown text, stacks, duration bars, borders and shadows.",
                        "Player Defensive Buffs placed inside the portrait now respect the configured growth direction, per-row layout, offsets and shared Aura appearance.",
                        "Removed the legacy automatic changelog popup; release notes remain available through the normal addon and distribution pages.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Aura and Spell preview refreshes stay on the out-of-combat cold path, use targeted pooled updates and add no recurring combat work.",
                        "Fixed deferred unit- and group-frame refresh requests overwriting earlier queued work during combat; all accumulated reasons and element sets now flush together.",
                        "Added a PlayerFrame compatibility mode that keeps Blizzard-owned resource bars functional while the visible Blizzard PlayerFrame remains hidden.",
                        "Migrated legacy Combat and Incoming Resurrection indicator positions to the runtime anchor schema without overwriting explicit profile choices.",
                        "Fixed Raid Group Indicator font-size changes not reaching the compiled live group-frame configuration immediately.",
                        "Fixed spacing and clipping in the Group Frames Range Fade section.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta40",
            date = "2026-07-30",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Player frames gained a dedicated Defensive Buffs lane. MSUF tracks the curated defensive buffs for your class, lets you add or exclude individual spells, and can show the currently active defensive directly in the Player Portrait instead of beside the frame.",
                        "Dispel Symbols now show one symbol for each active dispel type by default on both unit and group frames. The previous single highest-priority symbol remains available as an option.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "The player Defensive Buffs lane has its own setup, layout and defensive-spell controls in the Auras page, including a matching preview.",
                        "Defensive Buffs are now enabled by default for new and existing profiles. They stay a normal saved choice afterwards, and the portrait mode can show one to eight defensive icons while retaining the proven single-icon layout by default.",
                        "Unit and group previews gained an element picker, exact X/Y offset inputs, reset and jump-to-settings actions, plus Tab/Shift+Tab selection for handles hidden behind other preview elements. Their layer controls now flow below the canvas, and zoom/pan can be locked while layers change.",
                        "Group-frame previews now render multiple active Dispel Symbol types just like the live frames.",
                        "Aura management is easier to navigate: unit and group blacklists, Custom Aura whitelists, tracked DoTs and player Defensive Buffs gained search, clearer icon-and-Spell-ID entries and explicit Remove buttons. Blacklists can add an entire curated set or a single spell from it; Buff blacklists still accept an exact custom spell, while Debuff blacklists stay curated for 12.x.",
                        "Removed duplicate permanent-aura toggles from the Auras page.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Group Portrait size overrides being forced to at least 16 pixels. Every positive slider value is now kept exactly; 0 still means automatic sizing.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
