-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-Beta41",
    previousVersion = "6.0-beta40",
    rangeLabel = "6.0-beta40 -> 6.0-Beta41",
    entries = {
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
        {
            version = "6.0-Beta38",
            date = "2026-07-29",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "New Dispel Symbol for unit frames and group frames: a placed icon that names which debuff type is on a unit (Magic, Curse, Disease, Poison, Bleed). Choose from three Blizzard sets or four new MSUF sets, each using its own shape per type so it stays readable at small sizes.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "The Dispel Symbol can be placed by dragging: switch on its preview in Global Style > Bars or Group Frames > Dispel Symbol and drag the symbols where you want them.",
                        "The Dispel Symbol shows only the highest-priority debuff type by default, or one symbol per active type if you prefer.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta37",
            date = "2026-07-29",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Party group frames gained a Portrait, matching the unit frame version: left/right position, 2D or class art, attached/detached/overlay placement, square/circle/rounded/diamond shapes with flat or relief borders, background tint, and an optional cast-spell-icon overlay. Draggable in the group preview and Assistant-settable (\"party portrait\", \"portrait shape\"); Raid and Mythic Raid don't get it.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Role, leader and assist group icons now pick their style per-indicator in Group Frames > Indicators, replacing the old scope-wide \"Default role icon style\" + \"Use Midnight Style\" toggle. Midnight art is now its own dropdown entry (\"UX Pro (Midnight)\") instead of a separate checkbox. Old profiles keep resolving through the previous scope-wide setting until an indicator is given its own style.",
                        "On clients older than 12.1, MSUF now says once per login that auras, dispel highlighting and a few other 12.1-only features stay disabled until that patch goes live. Everything else keeps working, so there is nothing to act on.",
                        "The party portrait's border color and opacity moved to the Shape & Border card's Colors shortcut, where the unit frames already keep theirs, instead of two rows on the card itself.",
                        "The group preview gained a Tank/Healer/DPS switch, so per-role resource bar visibility and the role icon can be judged without swapping specs. Clicking a role toggle in the Resource Bar section jumps the preview to that role.",
                        "Edit Mode toolbar controls now tint their label on hover instead of just the surrounding pill, matching the page navigation rail.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed the options keybind loading the addon and building the whole options window in the same frame on the first open each session, which could hitch the game. Loading and window construction are now split across two frames; pressing the key again while that's pending is ignored.",
                        "Fixed Edit Mode drags/resizes occasionally snapping a frame back to its old position or size - the single-frame refresh after a drag could still read a stale compiled spec. The spec is refreshed before applying now.",
                        "Fixed the Player frame offering a \"Dots on target\" aura container: it tracks DoTs on your current target, which never made sense on your own frame. Removed from Player's Aura Style page, workspace tabs, Edit Mode, preview, and Layer Overview; Target, Focus and Boss keep it.",
                        "Fixed toolbar buttons that carry both a tooltip and hover styling (Groups, Exit, Discard All, the frame inspector selector) losing their hover highlight - the tooltip handler was overwriting the button's own hover handlers instead of layering on top.",
                        "Fixed group frame resource bar text being unable to set its own color mode - the Global Fonts Power Text Color control and the quick text-settings Color Mode row were both hard-disabled for group scopes.",
                        "Fixed the party portrait being hard to grab in the group preview: its artwork was drawn on a frame sitting above the drag handle, so clicks landed on the wrong thing. The handle owns the artwork now, and portrait opacity no longer fades the selection outline with it.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
