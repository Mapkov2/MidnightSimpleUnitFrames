-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-Beta40",
    previousVersion = "6.0-beta39",
    rangeLabel = "6.0-beta39 -> 6.0-Beta40",
    entries = {
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
        {
            version = "6.0-Beta36",
            date = "2026-07-29",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Group frame resource bars caught up with the unit frames. The Resource Bar section on the Group Layout page now carries the same cards a unit frame has: \"Border & fill\" with its own outline toggle and thickness, \"Embed into health\" and \"Detach from frame\", and a \"Detached placement\" card with X, Y, width, height, layer and \"Text on detached bar\". The bar also reads the same colors the unit frames do, so a resource color set in the Color Painter reaches party and raid members instead of only the frame you picked it on, and the power gradient, the static, dark and unified bar modes and the health fill direction all carry over. Bar art and the color mode stay global, as on the unit page. The card lists every resource color it can reach rather than guessing one from the preview scope, which named the wrong resource whichever way it guessed. The group preview follows all three placements - embedded, attached below, and detached - and the detached bar can be dragged there like any other element.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Both dispel overlays gained a \"Preview overlay\" toggle - Global Style > Bars for unit frames, Group Frames > Dispel Overlay for group frames. The live tint is drawn by the client and only shows while a real dispellable debuff is up, so style, opacity and layer were impossible to judge. The preview paints an MSUF-owned stand-in through the same layout the real overlay uses, and on the group side it reaches the preview rows in the options window too. It is never written to your profile, drops itself when the page closes or the overlay is switched off, and will not turn on in combat.",
                        "Group frames gained \"Fade offline members\" in the Range Fade section. It dims a disconnected member to the Offline opacity that section already had, which until now did nothing unless \"Hide offline members\" was on. Hiding still takes precedence, and the Assistant can set it (\"offline fade\", \"dim disconnected members\").",
                        "The group \"Group Number\" indicator gained a Style dropdown - (2), [2], or a plain 2 - matching the unit frames' Raid Group indicator, and both print through one shared formatter now. Its Anchor dropdown offers all nine anchor points instead of the aura set, and the card says what the number is: the raid subgroup, which a five-player party does not have until you are in a real raid.",
                        "The Group Number can be dragged in the group preview, on a handle that sits on the text itself rather than a fixed box, so where you drop it is where the frame draws it.",
                        "Group frame Spacing goes up to 60 instead of 20.",
                        "The Dashboard's guided setup card carries a \"Wago Profiles\" button. The link existed only on the recovery card further down the page.",
                        "Class-colored group health no longer offers a health color to edit. Class coloring is one color per class rather than a single foreground, so the picker had been handing out an arbitrary class and writing it into the shared class color table; the card points at Colors > Class Colors instead.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed the group Frame Outline's Layer slider never lifting the outline above a name. Group text and icons sit in a foreground band measured from the health bar, while the outline was still on the older band measured from the frame, which topped out exactly where group text begins. Outlines now run on the same scale as the rest of the foreground, keeping text over outline at Layer 0 and the spacing that stops an activating dispel or aggro border from dropping below the outline it replaces.",
                        "Fixed the Group Border having no preview at all. It is drawn on the header anchor, which both the in-game group preview and the options window preview replace, so thickness, padding and color could only be judged with a real group. Both surfaces draw it now through the same geometry the live header uses, and the anchor takes it back when the preview closes.",
                        "Fixed the group preview putting the member name in the wrong place. Group frames anchor the name across the health bar; the preview laid it out as a fixed-width box on the frame, so position and alignment drifted for every offset you set. The preview follows the live span now, and the grab handle fits the drawn text instead of the whole bar.",
                        "Fixed the cast spell icon in the portrait overwriting the portrait itself. Both shared one texture, so every cast and channel that ended rebuilt an otherwise unchanged portrait through an expensive native call. The cast icon has its own overlay now, created only where the feature is on and kept under the same mask, so a cast start and stop is a visibility change.",
                        "Fixed the group number vanishing from frames whose identity the client had not resolved yet: the lookup bailed on anything it could not confirm was a player, instead of only on a confirmed non-player. A raid frame needs no roster call at all now, since a secure header's unit token carries the roster index, and the number is no longer repainted in combat - the roster event driving it also fires for deaths and disconnects, so one deferral is recorded and flushed when combat ends.",
                        "Fixed the group preview keeping a stale group number on screen after the setting was switched off, and printing a bare digit where the frame prints the configured style.",
                        "Fixed the Resource Bar section on the Group Layout page under-sizing its own body, which let its cards bleed over the sections below it.",
                        "Fixed the close button on the text quick settings popup drawing nothing. It was built from the standard button, whose label is inset twelve pixels from each edge - on a twenty pixel wide button that leaves the glyph a negative width. It uses the shared window control now.",
                        "Fixed a bar-anchored name collapsing to its string width while being dragged in the preview: it is anchored left and right, and only the first anchor was captured and put back.",
                        "Selecting the group number's preview handle no longer blanks the Status Icons dropdown, and with it every other status handle. The group number is a placed status text with its own card, not an entry in that dropdown, so it stays out of a selection it can never be part of.",
                        "Fixed the options window rebuilding page header chrome twice on every page switch, and leaving the previous page's header in place when a page failed to build.",
                        "Less work on a target swap. A frame becoming visible skips the full runtime sequence when the identity pass that just ran already covered every element it has, the health gradient curve is prepared once when the bar is configured rather than on the first unit it sees, and a unit token with nothing behind it keeps its compiled prediction routes instead of rebuilding them.",
                        "Menu refreshes no longer restyle navigation buttons, castbar segments, scope selectors and the preview pin button that were already in the state being set.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
