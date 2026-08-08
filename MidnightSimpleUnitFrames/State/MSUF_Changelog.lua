-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-RC14",
    previousVersion = "6.0-RC13",
    rangeLabel = "6.0-RC13 -> 6.0-RC14",
    entries = {
        {
            version = "6.0-RC14",
            date = "2026-08-08",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added optional Blizzard Edit Mode integration. The Minimap, Chat, Micro Menu, Bags, Objective Tracker and Tooltip get MSUF movers, and their Blizzard Edit Mode settings - sizes, Minimap rotation, Chat width and height, Micro Menu and Bags layout, tracker opacity and text size - appear as popup controls that apply instantly. Everything is written through the game's own Edit Mode layout, so positions stay taint-free and survive a reload. Selecting an element while a Blizzard preset is active asks for a layout name and saves an editable copy first.",
                        "The Blizzard Edit Mode arrangement can ride MSUF profile export and import through an opt-in switch on the profiles page. It is off by default in both directions, so a foreign profile string can never rearrange your HUD.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "External Edit Mode elements can declare a fixed step for their number controls. Stepper buttons then move by exactly that step instead of the modifier-scaled nudge.",
                        "The Assistant answers newcomer phrasings of \"what can you do\" - including what is this addon, where do i start and how does this work - with the capability overview instead of the catch-all reply.",
                        "The Assistant now reads a first-person possessive as the Player frame when no frame is named: make my name bigger works like make the player name bigger. Bulk wording (all my frames) and aura ownership (my buffs) keep their old meaning.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed the Buff and Debuff Gap sliders being one shared setting (#66). Each lane now stores its own gap on unit frames, in the Edit Mode aura popup, in the preview and for the Assistant. Profiles that never split the two keep the value they had.",
                        "Fixed the Group preview losing its selected element whenever an element's settings opened on another page. The selection, its coordinates and the axis pulse now survive the page switch.",
                        "Fixed the Group preview's Dispel Symbol chip pointing at the Dispel Overlay section instead of the accordion that owns the symbol.",
                        "Fixed the first click on an external Edit Mode element being swallowed. A steady click no longer counts as a drag, so selecting the element opens its popup right away.",
                        "Fixed external Edit Mode movers going invisible in preview test mode. Dominos, DandersFrames and Blizzard elements keep their tinted band and label, which is the only marker that MSUF controls them.",
                        "Removed the duplicate Cast Target Text color swatch from the Castbar page. The color is reached through the card's ::: shortcut and the Colors page, which is the single entry point for every text color.",
                        "Fixed change the separator after a change landing on an unrelated control. A property noun with no pronoun now continues the subject of the previous turn, and both the Separator and Delimiter spellings resolve.",
                        "Fixed a follow-up that names a control but no value being answered with \"no such control\". The Assistant now offers that control's choices instead.",
                        "Fixed make it bigger after enabling a status indicator finding nothing. Status icon geometry is stored under a shorter stem than the toggle, and the follow-up now searches those too.",
                        "Fixed pronoun follow-ups being answered by a catalog token search, which produced confidently wrong readings from unrelated sliders.",
                    },
                },
            },
        },
        {
            version = "6.0-RC13",
            date = "2026-08-07",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added optional Dominos integration to MSUF Edit Mode. Undocked bars get movers and a native MSUF popup covering the bar's layout settings - Buttons, Columns, Spacing, Padding, Scale, Opacity, Faded Opacity, visibility and click-through - while Dominos keeps ownership of all bar settings.",
                        "Added optional DandersFrames integration to MSUF Edit Mode. Party, raid and free pinned sets get movers, selecting an element starts DandersFrames' own unlock preview for that scope, and DandersFrames keeps ownership of all saved positions.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "External Edit Mode elements can now declare their own quick controls. MSUF renders them as native stepper and toggle rows in the external popup and routes every change through the normal undo history.",
                        "The Edit Mode toolbar now slides in from its docked edge when Edit Mode opens. Reduce Menu Motion skips the animation.",
                        "Trimmed the Dashboard's Display & recovery card to Reset Positions, Print Help and Factory Reset All. The duplicate Wago and Discord buttons were removed; both links stay in the Wago and support rows.",
                        "Restarting an already completed Guided Setup from the Dashboard now asks for confirmation. Resuming an active tour and the first run stay one click.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed the Follow HP bar (overflow) prediction anchor drawing into neighbouring group frames. The overlay is now clipped natively to Blizzard's 5% overflow allowance.",
                        "Fixed overflow prediction bars dropping behind neighbouring frames after re-parenting, and rounded frames clipping away the segment that anchor mode exists to show.",
                        "Fixed group frames built after the startup pass - login roster races and late joins - never receiving their rounded mask.",
                        "Fixed Edit Mode tooltips drawing underneath the toolbar, and the Cancel All / Exit buttons ignoring the toolbar font.",
                        "Fixed the Aura style preview staying hidden when returning to an already built Aura page.",
                        "Fixed set Custom Menu Accent Color to red storing black. The setting now uses the same single-color contract as every other color.",
                        "Fixed Assistant enum values with an underscore being unselectable by name, such as the Blizzard Ring portrait shape and the Dispel Symbol styles that share a stem.",
                        "Fixed control names longer than eight words never entering the Assistant's exact-label index; 36 controls could not be reached by the name the menu prints.",
                        "Fixed a command that spells exactly one control's name being answered with a candidate list instead of changing it - colors above all.",
                        "Fixed enable target combat state indicator toggling the global Combat Enter/Leave Text or the Blizzard Totem Frame instead of the unit's Combat Indicator.",
                        "Fixed the Assistant rejecting an Inline Custom Separator longer than five characters instead of storing the trimmed value.",
                        "Fixed the Big Defensive sort method being unselectable by name, and Only Mine on the preset custom container reporting a failed write instead of explaining that MSUF pins it.",
                        "Follow-ups to a readability answer (make it wider, actually make it 320) now apply to the control that answer named, and a shortened indicator name continues the subject already under discussion.",
                    },
                },
            },
        },
        {
            version = "6.0-RC12",
            date = "2026-08-07",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added Back and Forward page navigation to the menu status strip. Both buttons name their target page in the tooltip, skip the transient Search page, and are available to the Assistant.",
                        "MSUF frames now follow a supported Cooldown Manager provider live while out of combat. Unit frames, Group headers and Class Resources keep a real anchor link to Arc UI, Skiron, Coolinator and Blizzard's viewer, and that link is severed at the combat edge so provider movement can never drag a protected frame mid-fight.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "The Detached Power width mode now outranks a Detached width typed on the frame; the shared Class Resources width mode remains its fallback while width sync is on. Manual resolves to no source, so untouched profiles keep their current width.",
                        "Status text colors now have one entry point per surface: the ::: shortcut on the Status > Selected card and the canonical Colors page. The duplicate swatch on Status > Placement was removed.",
                        "Split the runtime chat/tooltip file into dedicated slash command, unit tooltip and Blizzard Edit Mode bridge modules. Load order, exports and behavior are unchanged.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed MSUF frames not following a Cooldown Manager provider that moved or resized without changing identity. Provider movement is now free out of combat, and combat-time changes are replayed once after regen instead of being lost.",
                        "Fixed frames anchored to a provider whose geometry is not readable yet rendering nowhere. They now keep the cached screen position or fall back to UIParent and retry on the bounded late-anchor pass.",
                        "Fixed Group Cooldown Font and Stack Font not applying until an unrelated setting was changed. Aura text sizes now invalidate the aura domain instead of the text-only fast path.",
                        "Fixed the Custom Aura Pandemic color losing its menu entry. The color is reached through the section's ::: shortcut, and menu search and the Assistant resolve to that shortcut.",
                        "Fixed the detached Power width preview disagreeing with live frames when a Cooldown Viewer source was selected.",
                        "Edit Mode frame positioning is now blocked at the combat boundary and rolls back atomically when an external anchor target cannot resolve.",
                        "Class Resources no longer runs its layout twice when the same Cooldown Viewer provides both its anchor and its width.",
                        "Font runtime resolves its apply-cache helpers once at load instead of per FontString, and the combat regen drivers arm their event only once per fight.",
                    },
                },
            },
        },
        {
            version = "6.0-RC11",
            date = "2026-08-07",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added optional Grid2 and Details! integration to MSUF Edit Mode. Both addons keep ownership of their frames and saved positions.",
                        "Added native WoW 12.1 Player resource pings for health and supported mana states. Portrait pings keep the normal radial wheel.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added a public API for registering external frames with MSUF Edit Mode.",
                        "Expanded translations for recent Aura, Preview, Class Resource and Layer settings.",
                        "Unified the detached Player Power outline across settings, Copy To, live frames and previews.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Group Preview layer order and Name positioning for all anchors.",
                        "Fixed detached Player Power outline thickness at different preview zoom levels.",
                        "Fixed exact Assistant commands being intercepted by greetings, guides or movement shortcuts.",
                        "Added Assistant help for shortened and clipped Unit and Group names.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
