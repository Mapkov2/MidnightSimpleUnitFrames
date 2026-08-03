-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-RC7",
    previousVersion = "6.0-rc6",
    rangeLabel = "6.0-rc6 -> 6.0-RC7",
    entries = {
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
        {
            version = "6.0-RC4",
            date = "2026-08-03",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added a Blizzard Raid Manager visibility mode for MSUF group frames. Party, Raid and Mythic Raid now share Auto, Always Show, Mouseover and Hidden choices, restoring access to ready checks, raid markers and role filters without giving Blizzard's compact raid frames back ownership.",
                        "Blizzard's Totem Frame is now available to every class. Death Knight Raise Dead, Paladin Consecration and any other ability that fills a Blizzard totem slot can be seen and dismissed even while MSUF hides the PlayerFrame; the existing preview, offsets and Assistant guidance are no longer Shaman/Monk-only.",
                        "Added the bundled Fritz Soundscape font to MSUF and LibSharedMedia.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Reworked the Unit Frame preview to use the same native StatusBar ownership as live frames. Health and Power textures, backgrounds, opacity, rounded styling and square outlines now render from the real owning regions instead of a second synthetic frame surface.",
                        "Refined Menu2's visual theme: navigation pills keep clean authored end caps at every width, hover feedback stays clearly visible, alternate accents tint only the surfaces they own, and minimize/maximize follow the accent while Close keeps its danger color.",
                        "Refreshed the compact navigation and switch media while reducing their file size.",
                        "The Dashboard Changelog is now the first utility card and uses readable shared typography, brighter bullets, real line spacing and separators between releases.",
                        "Added Silvermoon as the default menu preview background for checking frames against a colored in-game surface.",
                        "The Aura Style container selector now stays docked with the scope selector, so its pinned preview does not lose the lane it belongs to while scrolling.",
                        "Updated the Purge Border notice: the feature returns with WoW 12.1.5 when Blizzard exposes the required API support.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed the Unit Frame preview sometimes turning into a black plate or hiding the selected health-bar texture. Background and fill opacity now remain independent, including a real zero-alpha state, per-unit background values update immediately while editing, and Group Preview shows the configured alpha without the live Edit Mode visibility floor.",
                        "Fixed preview rounded edges, square outlines and selection handles competing for the same draw level. Only the configured border owner is visible, drag handles remain above every configurable visual layer, and the castbar preview surface no longer intercepts their mouse input.",
                        "Fixed Unit and Group previews omitting configured Power Bar outlines. Square bars now show all four edges, rounded embedded bars use their separator, and separately rounded bars keep their own outline.",
                        "Fixed Power Text disappearing from the Unit Frame preview when the Power Bar itself was hidden. Preview availability and footprint now follow the compiled Power Text setting, while Power Bar visibility follows the same per-unit, shared and default fallback chain as live frames.",
                        "Fixed the Texture Layer preview chip staying interactive when none of its three texture slots was enabled.",
                        "Fixed boss-frame outlines appearing thinner than the same setting on player, target, focus and group frames. Boss borders now convert the configured unit-frame thickness through the frame scale before snapping to physical pixels; attached castbar width follows the corrected visible outline.",
                        "Fixed name shortening cutting centered names on both ends. With a Top Center or Center name anchor, an overflowing name keeps its configured clip side so only one end is cut; restricted names retain the safe centered fallback.",
                        "Expanded Unit Frame preview diagnostics with live-versus-preview size, alpha, vertex alpha, texture and StatusBar-fill reporting for faster visual-parity checks.",
                        "Fixed the Assistant treating an unsupported request to copy a unit frame's position or anchor as a broad partial Copy To operation. Positioning requests now make no changes and direct the user to MSUF Edit Mode; mixed requests no longer copy only the other categories silently.",
                    },
                },
                {
                    title = "Release Workflow",
                    bullets = {
                        "Alpha, Beta, RC, Pre and Preview tags can no longer publish to Wago, even when a tag is accidentally annotated with publish-target: all or publish-target: wago. Prereleases remain available through their explicitly selected GitHub or CurseForge channel.",
                        "Stale prerelease tags are rejected unless they point at the current origin/main commit, preventing a bulk git push --tags from publishing forgotten older beta builds.",
                        "Stable Wago uploads now receive only the current release section instead of the complete historical changelog, so old beta notes are not presented again as part of a new release.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
