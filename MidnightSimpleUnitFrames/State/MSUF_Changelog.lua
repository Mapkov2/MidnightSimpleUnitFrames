-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-RC8",
    previousVersion = "6.0-RC7",
    rangeLabel = "6.0-RC7 -> 6.0-RC8",
    entries = {
        {
            version = "6.0-RC8",
            date = "2026-08-04",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added Edge Softness to each of the three existing Unit Frame texture layers. The 0-30% slider uses fifteen compact standalone feather masks and renders through the same cold apply path in live frames and the Menu2 preview; Copy To carries the value for every layer.",
                        "Cooldown-manager anchoring now asks for consent instead of silently taking ownership. Detected Arc UI, Skiron, Coolinator, Cooldown Manager Centered and Essential Cooldown Viewer providers can be followed or released from Edit Mode, Guided Setup and the unit-page anchoring controls.",
                    },
                },
                {
                    title = "Fixes",
                    bullets = {
                        "Fixed expanded fixed previews collapsing or restoring an older zoom when a profile/settings rebuild invalidated the active page. Expansion state and the expanded zoom now survive the rebuild as one controlled transition.",
                        "Fixed Assistant explain requests failing when players used a published control alias instead of the visible label. Ambiguous aliases still fail closed, and advice questions such as whether a setting is worth changing remain strictly read-only.",
                        "Fixed the remaining Power Bar color fallback path when a unit exposes a numeric power type whose token must be normalized before resolving configured colors.",
                        "Fixed disabled themed Menu2 segments retaining their active blue paint even though native mouse interaction had already been disabled.",
                        "Fixed existing profiles missing the Class Resources preview guides. The RC8 default repair enables them once, while a later explicit user choice to hide them remains authoritative.",
                    },
                },
            },
        },
        {
            version = "6.0-RC7",
            date = "2026-08-04",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "MSUF now detects Arc UI, Skiron, Coolinator and Cooldown Manager Centered automatically and anchors the global Unit Frame layout to Essential Cooldown Manager while one of those providers is loaded. Edit Mode, Guided Setup, diagnostics and unit-page anchoring all show the active AUTO provider and suppress the conflicting manual choice.",
                        "Menu previews now keep their visible position sliders synchronized while Unit, Group, Aura, text, portrait, Power, Class Resource and Dispel Symbol handles are dragged, nudged or positioned exactly.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Range Fade opacity can now be previewed live while dragging the slider for Unit and Group frames. The preview respects whether fading applies to the whole frame or only the Health layer and returns to its normal state when the gesture ends.",
                        "Expanding a fixed preview now carries over the zoom level from Compact mode instead of jumping to an older Full/Fit scale; pan remains mode-specific for the differently sized canvases.",
                        "The Assistant's reviewed numeric domains now cover Group Dispel Symbol size, offsets, spacing, opacity and layer plus the extended AFK, DND and Ghost status-text offsets, allowing it to use the full ranges exposed by the menu.",
                        "Added dedicated Assistant help for Copy To, including unit/group category selection, excluded identity/anchor data and examples that remain distinct from executable copy commands.",
                    },
                },
                {
                    title = "Fixes",
                    bullets = {
                        "Fixed a saved profile language being ignored during initial addon file loading. Locale packs now register cold loaders and apply the selected profile language only after SavedVariables are available at ADDON_LOADED.",
                        "Fixed Menu2 edge snapping after interrupted or immediately repeated drags and resizes. Pending layout animation now settles first, mouse-release fallback finishes the real drag, and rejected content gestures cannot trigger an invisible snap.",
                        "Fixed configured Power Bar colors falling back to Blizzard defaults for NPC/unit tokens that expose only a numeric PowerType. MSUF now resolves the matching Mana, Rage, Focus, Energy, Runic Power, Lunar Power, Maelstrom, Insanity, Fury, Pain or Essence token first.",
                        "Fixed Assistant exact boolean commands, inverted Hide/Show controls, Blizzard-frame troubleshooting, profile and Aura page guidance, utility-page navigation, recovery help and problem-report precedence. Generated Blizzard-frame settings now use their actual player-facing menu labels.",
                    },
                },
            },
        },
        {
            version = "6.0-RC6",
            date = "2026-08-03",
            sections = {
                {
                    title = "Fixes",
                    bullets = {
                        "Fixed non-Midnight menu accents falling back to Midnight blue while hovering navigation entries. Hover and active states now follow the selected class, preset or custom accent with a restrained contrast between them, while the authored Midnight theme remains unchanged.",
                        "Fixed custom surface tints being applied inconsistently across the Dashboard, collapsible unit and group sections, and Aura preview tabs. These controls now resolve the live accent tokens after SavedVariables load instead of retaining stale blue values.",
                        "Fixed newly created profiles cloning the currently active profile. A new profile now starts from MSUF's factory defaults and fails safely with a clear message if those defaults are unavailable.",
                        "Fixed the compact Elite / Rare icon preview showing two identical skulls. It now matches the live frame and main unit preview with distinct silver and gold classification art, while a selected custom icon remains authoritative.",
                        "Fixed Assistant menu routing for dynamic status colors, castbar text colors, Custom Aura containers, External Defensive layout, Ironfur options and compound color controls. Assistant results now open the correct owning editor without exposing the retired External Defensive Auto List setting.",
                        "Fixed Assistant treating numbers or polarity words embedded in an exact control name as the requested value. Bare requests such as changing Party Scale 1-10 Players or Focus Target Hide in Group now ask for a value instead of silently clamping or toggling the setting.",
                        "Fixed Assistant command precedence for Blizzard frame visibility, slot-aware HP / Power text modes and scoped Blizzard Raid Manager controls, preventing broader visibility or frame settings from consuming those requests.",
                        "Added a Player text outline selector to the detached Player Power section, with the expanded layout and Assistant metadata needed to keep the shared Player font outline route accessible.",
                        "Fixed detached Player Power outline ownership: Class Resources now controls the outline consistently for Bar, Round, Crystal and Orb shapes in live frames and both previews.",
                        "Fixed legacy Target of Target and Focus Target profile aliases surviving beside their canonical settings. Imports, resets, menu edits and Assistant writes now migrate the old keys once and retain a single canonical owner.",
                    },
                },
            },
        },
        {
            version = "6.0-RC5",
            date = "2026-08-03",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Menu previews can now expand in place while remaining fixed above the settings. Unit, Group, Aura Style, Colors and Class Resources previews open into a larger canvas without covering or clipping the page below, and return to the compact layout with the same preview state intact.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Preview zoom, pan, wheel forwarding and search navigation now follow the fixed preview owner across compact and expanded layouts. Search results can open a hidden expanded target before highlighting it, while the settings viewport still receives ordinary wheel scrolling outside active preview gestures.",
                        "Boss unit frames and boss castbars now use a separate Edit Mode hit region for every visible frame instead of one large union box. Gaps stay click-through, every boss remains directly draggable, and all five still move as one shared group.",
                        "Edit Mode controls, the frame picker and position dialogs now stay above stationary preview movers; Undo and Redo use the shared history service directly when available.",
                    },
                },
                {
                    title = "Fixes",
                    bullets = {
                        "Fixed Empower casts changing their fill anchor when unified direction was disabled. Casts and Empower bars now always use the configured edge, channels reverse only their value direction, and Empower stage separators remain aligned with the fill.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
