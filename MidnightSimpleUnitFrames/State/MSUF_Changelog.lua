-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-RC9",
    previousVersion = "6.0-RC8",
    rangeLabel = "6.0-RC8 -> 6.0-RC9",
    entries = {
        {
            version = "6.0-RC9",
            date = "2026-08-05",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added native EllesmereUI Unlock Mode integration.",
                        "Added EllesmereUI Cooldown Manager to the consent-based cooldown anchoring providers.",
                        "Rebuilt Aura styling around clear ownership. Appearance > Aura Style now contains four genuinely global icon themes - Buffs, Debuffs, Player Defensives and Dots on Target - while each UnitFrame and GroupFrame owns its layout, filters, timers, text, ordering, Pandemic presentation and Full-Frame effects.",
                        "Restored Purge Border for Target and Focus through WoW 12.1's native stealable-aura filtering. It uses a dedicated one-slot Aura sensor, works even when normal aura lanes are hidden, respects the configured highlight priority/color and adds no MSUF scan, ticker or OnUpdate.",
                        "Added optional native Stealable Buff markers to Buff containers with Border, Border + Icon and Icon styles. The marker uses Blizzard's AuraButton filter and does not add an MSUF aura scan, ticker or per-frame update.",
                        "Added an optional Pandemic warning for Dots on Target with Border, Tint and a combined Border + Tint style plus color, thickness, padding, opacity and blend controls. It is disabled by default and the menu explicitly warns that Blizzard's native Pandemic region may run an OnUpdate on each affected visible aura button.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added a dedicated, Group-scope-aware Spell Icon Style editor for icon zoom/scale, opacity, native tooltip behavior, cooldown text and swipe, decimal threshold, stack count and duration bars. Spell Icons use the shared Buff theme only for shape, border and shadow, and they no longer intercept click-casting while tooltips are enabled.",
                        "Gave Custom 1-3, Player Defensives and Dots on Target the same frame-local deep Style workflow. Existing shared special-container presentation is migrated once into the owning UnitFrames without moving visibility, filters, placement or tracked spells.",
                        "Split Unit and Group Copy To into independent Aura Options and Aura Style categories. Content, filters, lists and tracked spells can now be copied without overwriting presentation, or presentation can be copied without replacing content; the global Appearance theme is never copied implicitly.",
                        "Moved UnitFrame Dispel Overlay and Dispel Symbol controls from the global Bars page to the owning Player, Target, Focus and Boss pages beside Auras. The editors follow Shared Bars versus per-frame override ownership and include in-page runtime previews; symbols can be dragged directly into position.",
                        "Added zoom out/in, Fit, 1:1 and Ctrl-wheel support to the shared Aura Style preview so global icon themes can be inspected without changing live Aura sizing.",
                        "Expanded preview parity for Unit and Group dispel overlays/symbols, Stealable markers, Pandemic timing, Custom Aura Full-Frame effects and Group Spell Icon styling. Rounded masks, layer visibility, configured alpha/shape and preview footprints now follow the same owners as live frames.",
                        "Simplified preview interaction: a single click on a handle opens its exact settings, dragging still moves it and right-click keeps related actions. Position readouts now use full-size - / + nudges, and redundant double-click instructions and duplicate X/Y controls were removed.",
                        "Added top-left, top-center and top-right Group name anchors, plus clearer portrait zoom/pan, detached Power Bar, castbar, status-icon, text and dispel layouts across narrow and wide Menu2 pages.",
                        "Added optional preview drag guidance for movable Unit, Group and Class Power handles. A compact mouse-and-arrow-key cue plus reduced handle tooltips teach dragging and keyboard nudging; new profiles see the guidance per opened preview until their first real move, while experienced profiles see it only once per session. The Global > Misc toggle controls the short menu-only AnimationGroup, with no ticker or persistent OnUpdate.",
                        "Removed the obsolete MSUF Masque dependency, saved toggle and Assistant route. MSUF 6.0 does not register its Aura buttons with Masque; Masque and its settings for other addons remain untouched.",
                        "Unified the RC compatibility notice with the login welcome message so opening Menu2 no longer prints a duplicate warning. On clients older than WoW 12.1, the required compatibility notice remains visible even when the optional welcome message is disabled.",
                        "Updated the bundled dashboard credits to list Aur0r4 as Lead QA across all shipped locales.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed the RC1-RC8 Group-page option-domain shift that could feed one dropdown's values into the next setting. Existing Party, Raid and Mythic Raid profiles are repaired once at the cold database boundary, covering name anchors, sorting, Power text, delimiters, dispel presentation, status positions, Aura anchors and Spell Indicator effects.",
                        "Fixed Edit Mode drag geometry at non-default UI/frame scales. Unit movement now uses consistent UI-space deltas, Group movement commits the visible and logical anchors atomically with rollback on failure, and detaching a castbar preserves its current on-screen center instead of reinterpreting old offsets off-screen.",
                        "Fixed disabling MSUF Global UI Scale and then returning to Blizzard scaling. MSUF now restores the untouched Blizzard useUiScale / uiScale state instead of writing its temporary overlay scale back into those CVars, with protected API fallbacks handled safely.",
                        "Fixed a fully disabled UnitFrame being rebuilt unsafely in the same session when re-enabled. MSUF keeps the detached zero-overhead state intact and requests one clean /reload before instantiating the frame again.",
                        "Fixed native Player weapon-enchantment Aura buttons not being recreated when the shared option changed.",
                        "Fixed dismissing a cooldown-provider consent popup with Escape being stored as an explicit rejection; only clicking Cancel now records a decline.",
                        "Fixed Menu2 previews painting outside or visibly chasing the shell during minimize, maximize and restore animations. Preview work is suspended during the transition and committed once at the final geometry.",
                        "Fixed Group and Unit preview interaction/parity issues including stale or missing dispel layers, Custom Aura frame effects, Spell Icon opacity/shape, castbar text hit regions, hidden cast-target handles and Target-DoT Pandemic animation restarting instead of expiring once.",
                        "Fixed highlight stacking so higher-priority Dispel and Purge borders remain authoritative over lower-priority frame highlights.",
                        "Fixed Group Copy To omitting newer fields such as maximum frames, auto tanks, scaling, detached Power Bar details, individual HP/Power text slots, status indicators, role visibility, color ownership and Aggro settings.",
                        "Fixed the Dashboard's pending global-enable state losing an explicit false value.",
                        "Expanded Assistant coverage for the new shared-versus-frame-local Aura ownership, Stealable marker controls, Spell Icon Style and independent Aura Copy To categories. Search and command routing now better distinguishes singular/plural control names, Target from Target of Target/Focus Target, control labels from their current dropdown value, polite/question-shaped mutations and vague style requests that should open guidance instead of changing an unrelated setting.",
                    },
                },
            },
        },
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
                        "Fixed Unit Frame and Class Resources Guide layers becoming stale after profile switches or resets. Factory profiles start with both Guide layers visible, the RC8 repair enables Class Resources Guides once for existing profiles, and a later explicit user choice to hide either layer remains authoritative.",
                        "Fixed the preview zoom controls using an unintuitive button order. Zoom out, the live zoom readout and Zoom in now stay together before Fit, 1:1 and Help.",
                        "Recalibrated Menu Scale so the former physical 80% size is now the clear 100% reference, with a 25-200% range across the window slider, Dashboard and Assistant while existing saved sizes remain visually unchanged.",
                        "Extended MSUF Frame Scale to 200% across persistence, live frames, castbar and Unit Frame previews, Dashboard controls and Assistant commands.",
                        "Fixed previews now open expanded by default in a fresh UI session and after page or factory resets; choosing Compact remains authoritative for the rest of that session.",
                        "Styled Copy To consistently as a green success action on Unit and Group pages so the primary replication workflow is easier to find.",
                        "Kept the toolbar Edit Mode action visually neutral instead of painting it like the menu's primary confirmation action.",
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
