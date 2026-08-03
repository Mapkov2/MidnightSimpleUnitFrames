-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-RC6",
    previousVersion = "6.0-RC5",
    rangeLabel = "6.0-RC5 -> 6.0-RC6",
    entries = {
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
        {
            version = "6.0-RC3",
            date = "2026-08-02",
            sections = {
                {
                    title = "Changes",
                    bullets = {
                        "Menu previews never scroll away any more. The Unit, Group, Aura Style, Colors and Class Resources preview card stays at the top of the viewport while the settings slide underneath it. Use the existing Expand/Compact and \"Hide Preview\" controls to reclaim height.",
                        "The \"Pin Preview\" toggle is gone; previews are always pinned. A preview too tall for the current window scrolls with the page instead, so the settings below it stay reachable.",
                        "The Class Resources spec selector strip is now docked above the scroll area like the unit pages' Editing strip, so the preview pins directly beneath it instead of the strip scrolling away.",
                        "Removed the duplicate \"Spell text color\" and \"Cast time color\" swatches from the unit castbar Spell and Time tabs. Both colors live on the Colors page and in the per-control color shortcuts; the inline copies wrote the same key a second time.",
                        "Double-clicking the castbar in a unit preview now opens its settings, like every other preview element.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed 2D portraits randomly turning empty or stale since Beta 43 when re-targeting a unit seen earlier: re-visits now always re-run Blizzard's native portrait resolver instead of replaying a cached texture value that cannot represent a live portrait render.",
                        "Fixed portraits on hostile units breaking mid-update on 12.1: the portrait cast-icon and reaction-border readers compared secret cast names and reaction values, which throws on 12.1 and left the portrait dressing without an image. Secret casts now still show their spell icon.",
                        "Fixed shaped portraits smearing their mask edge outward. Portrait masks now clamp to black outside their own quad, the way Blizzard declares every portrait mask.",
                        "Fixed long-lived buffs rendering a 0.1 second duration after login or a reload. Lanes that carry helpful auras get fresh duration objects once the world has loaded, on player, target, focus, boss and group units; the pass stays off UNIT_AURA and the identity hot paths.",
                        "Fixed the unit preview labelling custom container 4 \"Dots on target\" on the player frame, where that lane is Defensive Buffs. Tooltip, selection bar and quick actions now follow the bound unit.",
                        "Fixed the Assistant switching a setting on when a follow-up only spelled out its name, for example \"show me Mythic Raid Masque Enabled\". A follow-up that names the control is answered, not applied.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
