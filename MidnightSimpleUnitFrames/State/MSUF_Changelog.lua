-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-RC17",
    previousVersion = "6.0-RC16",
    rangeLabel = "6.0-RC16 -> 6.0-RC17",
    entries = {
        {
            version = "6.0-RC17",
            date = "2026-08-09",
            sections = {
                {
                    title = "Changes",
                    bullets = {
                        "Fresh and reset profiles now start from the native 6.0 Aura model. Focus Auras are enabled by default with 3 Buff and 4 Debuff slots, matching the useful Target/Boss baseline while keeping the Focus-specific placement.",
                        "Edit Mode X/Y fields now use one visual screen-center contract for Unit Frames, Castbars, Auras, Group Frames and external elements. Resizing an element keeps the displayed position stable.",
                        "Retired Assistant controls for old Auras2 reminders and incompatible quick presets now report that they are unavailable instead of accepting writes that cannot affect Auras3.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed legacy Unit and Group Aura fields being restored into current profiles. The one-time native-model repair removes retired state while preserving the visible first icon position and size for upgraded and imported profiles.",
                        "Fixed Aura layout and style ownership drifting between live frames, the menu, Edit Mode and the Assistant. Lane gaps, sorting, text, swipes, duration bars, tooltips and shared/per-frame overrides now read and write the same owner without reviving dormant values.",
                        "Fixed Dispel Border, Overlay and Symbol depending on another UnitFrame's Auras or a shared Bars owner. Each supported UnitFrame now owns its Dispel settings and automatically enables its Aura sensor; both icon caps may remain at 0.",
                        "Fixed Aura icons intercepting clicks. Only normal Player Buffs keep Right-click cancellation; every other Unit and Group Aura remains click-through while configured tooltips still work.",
                        "Fixed cooldown swipes being hidden or out of sync in menu and Edit Mode previews. Edit Mode now follows the existing menu animation clock, adds no second driver and remains paused in combat.",
                        "Fixed Copy To reporting success when nothing was copied or when Copy to All was cancelled. Unsupported Aura destinations are reported accurately, Player Defensive and Target DoT-only style fields stay with their product, and Group Spell Indicator caches are refreshed after a copy.",
                        "Fixed PvP indicator paths staying compiled after War Mode was disabled during its deactivation timer. Context recompiles remain event-driven and are skipped in combat.",
                        "Fixed Group Frame screen clamping adding a grid-size-dependent offset, so the same Anchor Point and X/Y identify the same position for Party and Raid.",
                        "Fixed stale Edit Mode SavedVariables making Player or Boss castbar previews reappear after logout or reload.",
                    },
                },
            },
        },
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
