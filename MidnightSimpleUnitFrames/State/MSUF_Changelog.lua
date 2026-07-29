-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-Beta37",
    previousVersion = "6.0-Beta36",
    rangeLabel = "6.0-Beta36 -> 6.0-Beta37",
    entries = {
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
        {
            version = "6.0-Beta35",
            date = "2026-07-28",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "MSUF can now format every health, power, and resource number the same way on every client language. Blizzard's own abbreviator takes its breakpoints and letters from the game's locale, which inserts a space on some languages (\"123 K\"), uses different letters on others, and moves the decimal around, so the same value could read differently from one client language to the next. A new \"Number abbreviation\" control on the Misc page's Language section - Compact or Game default - switches every text surface (unit frames, group frames, class power) to a fixed, locale-independent breakpoint table (12.3K / 123M / 1.23B), with a live example line so the difference is visible before you commit to it. Game default remains exactly what you had, and CJK languages are left alone on purpose, since their abbreviations are intentionally different and were never the problem. The Assistant can set it too, in English and German (\"use compact numbers\", \"zahlen kuerzen\").",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Cast Bars gained a \"Filtering & Feedback\" section with two new options, both off by default. \"Hide profession casts\" drops crafting and gathering casts before they reach a frame - the profession flag is never a protected value, so this also holds for units whose spell data is restricted in PvP. \"Show cast pushback\" appends the delay a cast has accumulated to its name, for example \"Fireball +0.4\".",
                        "The per-unit \"Power texture\" and \"Power background\" dropdowns are gone from each frame's Visuals page. Power bar art is set once on the Bars page now, and any per-unit override you already had keeps resolving the same way.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed channels no longer draining when a cast reports no duration object, which the client hits often. Every manual bar write had started reading fill direction from the unified-direction setting instead of the cast type, so those channels filled like a cast instead of counting down. Channels now always count down unless \"Always use fill direction for all casts\" is on; casts and empowered casts are unaffected either way, and the native timer and the manual fallback render the same bar.",
                        "Fixed MSUF fighting another unitframe addon over the same frame's parent. The client's frame-hiding accepts a parent that another addon already hid, so MSUF re-asserting its own hidden parent bounced the frame between both addons' hooks until the stack overflowed.",
                        "The \"/rl\" reload shortcut is only claimed while it is still free, instead of unconditionally. It is a shared convenience command, and claiming it outright let load order alone decide which addon's handler answered it.",
                        "\"Sync width to Class Resource\" now follows the class power bar's own show/hide transition. Nothing else was watching for that specific change, so a detached power bar could keep a stale synced width after the bar it was following disappeared.",
                        "A detached power bar's fallback width no longer sticks to its last value after its source is hidden. Resolving the width and refreshing it are now separate steps, so a hidden source clears its cached width instead of keeping the stale number.",
                        "The Group Indicators status-icon preview now highlights whichever of \"Current\" or \"All\" is the active preview mode, matching the unit frame visuals page and its preview helpers.",
                        "Fixed the Dashboard's changelog and support disclosures jumping the whole page back to the top every time you opened or closed one. Auras and Group Auras already restored the reader's scroll position after this kind of rebuild; Dashboard used a plain page reselect that never carried the offset over. All three now share one implementation, so opening a card near the bottom of a long page no longer sends you back to the first line.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta34",
            date = "2026-07-28",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "When the Assistant cannot work out which control you meant, it now hands you the relevant part of the menu instead of a generic list. Asking it to \"change reseted icon\" used to offer \"Show options for the current Group Layout page\" or \"Show general Assistant examples\", neither of which has anything to do with the rested icon. Three separate things caused that: the uncertain branch never consulted the Assistant's own knowledge index, the leading command verb dragged the ranking onto an unrelated page, and the misspelling was never corrected. Typos are now repaired against the words that actually appear in MSUF's control labels, command verbs are stripped before searching, and the match has to clear a relevance floor - below it the Assistant still says it does not know rather than confidently opening the wrong page.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed \"Always use fill direction for all casts\" not applying to channelled casts. Channels kept draining from full to empty, so the one option whose entire purpose is to make every cast move the same way left channels running opposite to everything else. A channel now fills from empty to full in the direction you configured, timed by the client itself, and the classic drain remains the default while the option is off. The spark also stays on the bar's moving edge in both modes instead of sitting on the anchor side, and the Cast Bars page preview shows the same thing the frame does.",
                        "Fixed the aura icon border and drop shadow never showing up in any preview. The Icon Border & Shadow settings reached real frames, but none of the preview surfaces drew them - not the Sample and Live preview on the Auras page, not the unit frame preview in the options window, and not the Edit Mode aura lanes - so there was no way to judge a border style without closing the menu and looking at the frames. All three now draw through the same renderer the live buttons use, including the per-scope opt-out and the lane padding, which the previews had been ignoring as well.",
                        "Fixed the Auras page preview not reacting to an icon border or shadow change. The preview repainted before the queued aura update had run and re-read the previous configuration, so it kept showing the old style until some unrelated interaction happened to refresh it - the reason the frames updated but the preview did not.",
                        "Fixed the \"Preview as\" row and the Sample/Live switch on the Auras page showing no selection at all. Both were built from the plain action button, which draws its selected state exactly like its unselected one, and the selection was never re-stamped on click because switching tabs repaints the preview without rebuilding the page.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
