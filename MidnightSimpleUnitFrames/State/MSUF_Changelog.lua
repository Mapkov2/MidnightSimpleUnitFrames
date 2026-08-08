-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-RC16",
    previousVersion = "6.0-RC15",
    rangeLabel = "6.0-RC15 -> 6.0-RC16",
    entries = {
        {
            version = "6.0-RC16",
            date = "2026-08-08",
            sections = {
                {
                    title = "Changes",
                    bullets = {
                        "The castbar icon border style is now a dropdown on the Castbar Icon tab: None, Dark or the castbar border color. The thickness slider still decides whether a border shows at all, and new castbars default to Dark.",
                        "The Dispel Symbol card's runtime preview toggle is labeled \"Runtime Preview: live UnitFrame (drag)\" so it is no longer identical to the Dispel Overlay preview on the same page.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Party and Raid frames landing in different places from the same X/Y with the same Anchor To and Anchor Point (#67). A leftover relativePoint from older profiles silently anchored one scope to the middle of the anchor frame; the Anchor Point now owns both sides, and the leftover is folded into the saved X/Y so nothing moves.",
                        "Fixed the castbar Spell Text and Time Text Alignment setting doing nothing until an unrelated width or font change re-laid the text out (#69). Both the live castbar and the menu preview now apply the alignment immediately.",
                        "Fixed an imported Blizzard Edit Mode arrangement not being picked up by the game's own Edit Mode manager. Applying a profile ends with a one-shot resync, out of combat only.",
                        "Fixed a mover drag editing the previously active Blizzard layout after Blizzard's own Edit Mode panel switched layouts. The cached layout is dropped when MSUF hands control over.",
                        "Fixed castbar size changes made in the Edit Mode quick popup leaving the open Castbar menu page on the old values. The width and height sliders and the Width mode dropdown now repaint with the write.",
                        "Fixed the aura blacklist not repainting after an entry was added or removed, and the preset spell dropdown still offering spells that are already on the list.",
                        "Fixed \"Preview all spells\" showing only the spec the editor happened to display and skipping spells whose indicator is a frame effect. It now mirrors the compiled runtime set across every tracked spec; corner custom slots stay with Corner Indicators.",
                    },
                },
            },
        },
        {
            version = "6.0-RC15",
            date = "2026-08-08",
            sections = {
                {
                    title = "Changes",
                    bullets = {
                        "The Details!, Grid2 and DandersFrames popups gained a Scale stepper that writes through each addon's own setting - Details! windows 65-150 %, Grid2 layouts and DandersFrames party/raid 50-200 % - and it takes part in undo like every other quick control.",
                        "The Blizzard Damage Meter joined the Blizzard Edit Mode integration: a mover plus Width, Height, Bar Height, Padding, Opacity, Background, Text Size and the spec icon / class color toggles.",
                        "Stepper buttons on a control with a fixed native step now accelerate with Shift and Ctrl (x5 / x10) instead of ignoring the modifiers.",
                        "Undo and redo name the change in plain words. Raw setting keys and internal apply reasons - hpBarAlpha, MSUF2_DASH_GLOBAL_SCALE - are turned into readable labels on the button, in its tooltip and in the status feedback.",
                        "External Edit Mode elements report their position relative to the screen center, the same convention MSUF's own frames use, instead of absolute screen coordinates.",
                        "Edit Mode snap is now remembered per profile rather than reset every session, and a fresh install starts with the grid on at 36 px, snap enabled and the backdrop dimmed to 55 %.",
                        "Player Defensive icons follow the frame portrait shape by default. They replace the portrait, so the rectangular fallback never fit; an explicit shape you already chose stays untouched.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed every Blizzard Edit Mode element failing to move or accept settings on a layout saved before that element existed in the game - the 12.x Damage Meter most visibly. The missing layout row is now seeded from the frame's live position.",
                        "Fixed two tooltip movers being offered at once. While MSUF controls the tooltip anchor its own preview owns Edit Mode, and the Blizzard HUD Tooltip element stays hidden; when Blizzard controls it, only that element appears.",
                        "Fixed long localized labels in external Edit Mode popups clipping past the popup edge. Two number controls only share a row when both labels fit; otherwise each gets its own.",
                    },
                },
            },
        },
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
