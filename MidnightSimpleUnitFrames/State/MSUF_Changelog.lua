-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-RC18",
    previousVersion = "6.0-RC17",
    rangeLabel = "6.0-RC17 -> 6.0-RC18",
    entries = {
        {
            version = "6.0-RC18",
            date = "2026-08-09",
            sections = {
                {
                    title = "Changes",
                    bullets = {
                        "Added a versioned nickname-provider API for Unit and Group Frames. Providers are priority ordered, cached, event-driven and deferred safely across combat; the bundled Northern Sky Raid Tools adapter now uses the same public contract.",
                        "Documented the supported Nickname and Edit Mode provider APIs for addon authors in the README.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Boss Frame health, power, background and border geometry moving or leaving the screen after a combat reload (#77). Pixel-snapped regions now remain attached to their secure frame owner.",
                        "Fixed Boss castbar spell-name shortening being ignored at runtime and in Edit Mode previews (#78), including the renderer-only path required for secret combat values.",
                        "Fixed Edit Mode always showing the Boss castbar leading-edge spark even when the setting was disabled (#79). The animation no longer overrides the cold style owner every tick.",
                        "Fixed detached Boss castbars appearing outside the Unit Preview (#80). The preview projects the applied runtime relationship without changing the saved absolute position.",
                        "Fixed Player Defensives being re-enabled by Menu normalization after the user disabled them. Runtime, Menu preview and Edit Mode now honor the same master switch, while tracked Target DoTs keep their disabled configuration preview.",
                        "Fixed Player search routes treating the layer substring inside player as a Text section request. Portrait and other exact results no longer open an unrelated accordion or rebuild the page unnecessarily.",
                    },
                },
            },
        },
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
