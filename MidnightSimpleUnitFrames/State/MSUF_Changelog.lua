-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-Beta31",
    previousVersion = "6.0-Beta30",
    rangeLabel = "6.0-Beta30 -> 6.0-Beta31",
    entries = {
        {
            version = "6.0-Beta31",
            date = "2026-07-26",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "The global castbar page now previews on the real castbar. While the page is open, the unit picked by its unit segment runs a demo cast on the actual frame out in the world, so size, texture, position, and text are judged where they will really be seen instead of against a mock. Picking Boss brings up the boss frames underneath so boss castbars anchor exactly like they do live. The preview is purely temporary: it never writes the persistent preview or test-mode settings, it follows the selection, it disappears when the page closes, and it tears itself down the moment combat starts, so it costs nothing while playing.",
                        "Custom aura containers now preview the spells they actually track. A lane used to draw a row of identical placeholder icons that told you nothing; it now shows one icon per configured spell with that spell's own artwork, capped by the lane's icon limit. The Target DoTs container applies the same include filter the runtime uses, so the preview shows exactly the icons that will appear on the frame - and a container with nothing configured previews nothing.",
                        "Boss aura lanes are visible from the boss page without entering Edit Mode. While the page owns the boss preview, the aura lanes render on those preview frames with no header, backdrop, or drag handling, so they read as a plain preview of the auras rather than an editing surface, and they stay put when you leave Edit Mode.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "\"Bar mode\" on the Global Colors page is now a single segmented row. The four mode cards and the dropdown that repeated the same choice have become one control, which is also the control search and the Assistant address, so the visible widget and the automated one can no longer drift apart. The per-mode tooltips moved onto the segments and the section is more compact.",
                        "The MSUF Assistant dashboard card no longer carries the red \"Early Alpha\" tag.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed castbars freezing on their previous timing. Whenever a cast reused the frame's duration container - pushback, channel updates, and every new cast on the same frame - the fill kept drawing the old cast's progress, because the client snapshots the duration when the bar is bound. Empowered casts were affected the same way.",
                        "Fixed the per-slot health text settings ignoring \"Reverse order\". Reversing mirrors the whole line, but only the slot contents moved: font size, X/Y offset, and the direct-layout anchor and color stayed on the physical side, so the \"Selected slot\" sliders edited the hidden text and appeared dead. Every per-slot setting now follows its content, in the live frames and in both menu previews, where the drag handles and the focus ring now also point at the text you actually see.",
                        "Fixed reverse order barely working on group frames at all: the reversal was applied twice, so the text modes snapped back to normal order while the hide-% and absorb-icon settings stayed mirrored.",
                        "Fixed \"Copy to\" carrying only part of a portrait. Width, height, placement, detached anchors, overlay alignment, layer, opacity, pan, and border art were left behind, so the copy's geometry disagreed with the portrait it was copied from. Border and background colors are still shared by all units and deliberately stay out of the copy.",
                        "Fixed health bar opacity in the group preview not matching the frames. The preview faded the bar in a way the client discards on the next value change; it now fades the fill texture like the live frames, scales the heal, absorb, and heal-absorb overlays with it, and fades the texts along unless \"Keep text + portrait visible\" is on.",
                        "Fixed four Assistant phrasings landing on a neighbouring setting: bar outline draw order was swallowed by outline thickness, Custom aura container geometry was answered by the Buff/Debuff shortcut, aura live-filtering claimed the group externals layer, and power bar textures were written to the global bar texture.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta30",
            date = "2026-07-26",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "The complete options interface now lives in its own Load-on-Demand companion and is loaded only when configuration is requested. Normal gameplay no longer eagerly loads the large Menu2 implementation, while the minimap button, slash commands, Edit Mode, search, guided setup, and Assistant routes keep their existing entry points.",
                        "Portraits can now be Attached, freely Detached, or placed as an Overlay inside the health bar. Independent width and height, nine-point anchoring, layer, opacity, and pannable zoom controls make rectangular and watermark-style portraits possible without adding per-frame work.",
                        "Added Relief portrait rings and shape-following flat borders for Square, Circle, Rounded, and Diamond portraits. Border direction rotates the relief lighting, and static colors remain zero-cost after settings are applied.",
                        "Menu search now ships with a complete prebuilt index, so the first search sees controls on every page without building those pages or causing the previous first-use pause.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Portrait placement and border controls now route through the correct unit workspaces, guided-tour targets, search routes, and Assistant settings.",
                        "The unit-frame core was extracted into an isolated embeddable MSUFUnitFrames framework while preserving the existing MSUF API and legacy compatibility bridges.",
                        "The 6.0 upgrade tour grew to sixteen curated highlights: Spell Indicators, Fill Direction, the portrait overhaul, and status icon packs joined the lineup, existing cards were refreshed for the newest features, and the layer card now shows an inline preview of the layer sub-menu instead of routing away.",
                        "Updated all supported locales for portrait placement, geometry, border art, long-duration aura suffixes, and the expanded upgrade tour.",
                        "The Assistant companion now declares the MSUF addon icon, so the load-on-demand module carries MSUF branding in the addon list.",
                        "The support card now credits Aur0r4 for the shipped default profile alongside Mapko and R41z0r, in every supported locale.",
                        "Assistant control schemas, reviewed inventory evidence, and reproducible release gates were refreshed for the Beta 30 control surface and three-addon package.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed permanent auras retaining a recycled countdown, and promoted long aura durations to localized hour and day displays.",
                        "Batched aura style applies, removed redundant native calls, and trimmed icon artwork work when the resulting aura state did not change.",
                        "Fixed color controls that did not apply their new color live while the picker was open.",
                        "Fixed unit-to-unit copy operations losing source semantics for settings whose meaning differs by unit.",
                        "Reused portrait identity keys and aligned live and preview overlay sizing to avoid unnecessary portrait work and geometry drift.",
                        "Removed the Anchor Picker's full-UI hover scans; hover validation now stays within a bounded candidate set.",
                        "Search is fully quiescent in combat, understands raw keys such as gf_party.hpTextMode, and deduplicates controls by stable route identity.",
                        "Group frames now apply their one-time startup visuals only after Blizzard's secure header bounds have settled, preventing saved opacity and visual state from being applied against transient login geometry.",
                        "The Options loader is zero-idle until configuration demand, preserves saved UI-scale behavior in the always-loaded core, and keeps configuration loading blocked safely during combat.",
                        "Fixed the options unit preview clamping tall or narrow frames to landscape proportions. Edit Mode writes and the preview mock now share one legal size range (40-800 wide, 8-200 high), so frame-relative elements such as the raid marker preview exactly where they land on the live frame.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta29",
            date = "2026-07-25",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added a \"Border Style\" choice for aura icons. Solid is the crisp pixel ring you already had, Soft Glow adds a halo around the icon, and Shadow shades the icon's own edges the way a drop shadow falls across artwork. Blizzard's tooltip, dialog and achievement frames plus every LibSharedMedia border can also be picked as icon border art, and Thickness scales the edge.",
                        "Replaced the aura icon shadow with a real soft drop shadow. It used to be two stacked hard rectangles, which read as chunky black steps around every icon; it is now a single smooth falloff with rounded corners. It is drawn once when a button is created, so it still costs nothing while playing.",
                        "Aura icon border and shadow can now be switched off per frame: Player, Target, Focus, Boss, Party, and Raid each have their own \"Use icon border & shadow on ... frames\" toggle, while the style itself stays one shared block. An excluded frame compiles the style away completely instead of drawing hidden regions.",
                        "Fixed Boss frame borders going soft or uneven at some heights. Boss frames now place their border, health bar, power bar, and attached castbar on one shared absolute physical-pixel rectangle instead of inheriting the half-pixel phase a centered container picks up at odd heights, so every edge stays a crisp 1 px at any Boss height and UI scale. Attached Boss castbars move to an edge-to-edge anchor; an existing offset is converted once and keeps its position on screen.",
                        "/msuf edit now starts MSUF Edit Mode instead of opening an empty \"native page missing\" page, and it accepts a frame name: /msuf edit target drops you straight onto the Target frame, and typing it again while Edit Mode runs switches frames rather than closing it. /msuf lock leaves Edit Mode.",
                        "Added profile slash commands. /msuf profile lists your profiles and marks the active one, /msuf profile <name> saves the current settings as a new profile and switches to it, /msuf load <name> loads one by full name or by a unique prefix, and /msuf delete <name> removes one once you repeat the command. /msuf default resets every setting in the active profile, which is what /msuf reset never did: that one only moves frames back.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added six bundled bar textures contributed by Aur0r4 - \"MSUF Dreamy\", \"MSUF Dreamy Soft\", \"MSUF Dreamy Ultra Soft\", \"MSUF Foggy\", \"MSUF Glass\", and \"MSUF Mirrored Glass\" - which show up in every texture dropdown: health and power bars, bar backgrounds, castbars, class resources, and group frames.",
                        "Added a per-unit \"Layer (0-30)\" slider for the castbar icon under Castbar > Advanced > Icon Style, on Player, Target, Focus, and Boss. 0 keeps the icon just above the bar and moves it together with the whole-castbar layer, exactly as before; 1-30 pins the icon to that frame level on the shared layer scale, so a large icon can be ordered in front of or behind the bar, texts, and other frame elements. Copy-between-units, reset, and the Assistant all know the new setting.",
                        "Every /msuf sub-command now registers itself in one shared list that both the dispatcher and the help text read, so /msuf help shows exactly what is loaded. The everyday commands are grouped by topic, and /msuf help all adds the diagnostics. The Dashboard's \"Print Help\" button prints that complete list.",
                        "Added /msuf search <text>, which runs a menu search and opens the results, plus /msuf version for the version, active profile, and Edit Mode state, and /msuf reload as a spelled-out /rl.",
                        "Anything /msuf does not recognise as a command or a page name is now treated as a menu search instead of opening a blank page, so a typo or a half-remembered setting name still lands somewhere useful.",
                        "The Gameplay page's \"Preview\" and \"Reset TotemFrame layout\" buttons now measure their translated label instead of assuming the English width, and wrap onto a second row when the pair no longer fits side by side. The Preview button lights up while the preview is running, and the From/To anchor dropdowns no longer overlap each other at narrow menu widths.",
                        "MSUF Edit Mode gained a frame picker. Overlapping frames used to be a dead end \" the frame on top swallows the click and the one underneath cannot be selected at all \" so the HUD now lists the placeable elements and selects the one you pick, no dragging things out of the way first. The list follows your current selection, closes with the HUD, and is unavailable in combat.",
                        "The 6.0 upgrade tour now targets 5.76 and older, and covers the features an upgrader would otherwise never stumble onto: Priority Frames, the Colors painter, and MSUF Edit Mode, whose card starts Edit Mode directly since it has no settings page to open. The group frames and Auras3 cards now name what actually changed \" adaptive layouts and scaling, per-lane aura filters and blacklists, the Dispel Overlay page, role icons and range fade \" instead of describing the area in general terms.",
                        "\"Copy to...\" on a unit page now carries what the page actually owns. Frame Basics takes the whole per-unit Bars override \" bar and background texture, outline, highlight priority and triggers, dispel overlay, absorb, heal prediction, and gradient \" along with the override switch itself, so a frame that was following the global Bars page keeps following it. Text takes the per-slot offsets and the unit's font settings (font, outline, shadow, color, name shortening). Portrait, Power Bar, Castbar, and Layout pick up the fields that were quietly skipped, including portrait decoration, power bar textures, castbar frame level, and the Boss layout mode and spacing. Group frame copying gains the absorb text icons and the DND status text. Castbar X/Y still only travel while the castbar is anchored to its frame: detached, those are absolute screen coordinates and copying them would stack both castbars in one spot.",
                        "The Assistant now resolves text-movement follow-ups against the object you were just talking about. \"move the power text up\" names the text but not the frame that owns it, so it used to fall through to a fuzzy search that could land on any control sharing a word - which is how \"power text\" reached Class Resource Text. Asking a retained text object for a control it does not have, such as an anchor on Health Text, now reports the controls that object really has instead of asking you to name it again.",
                        "Widened what the Assistant can change directly: profiles, unit frame power, base and bar settings, aura colors, castbar details, and the texture and gradient context all gained registry coverage. Action-backed menu controls now also carry their argument contract, so they are published as real actions rather than being downgraded to guided steps - the new \"New character profile\" dropdown among them.",
                        "Updated all supported locales for the new aura border styles and per-frame icon styling, the castbar icon layer, and the slash-command help and profile messages.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed the Blizzard TotemFrame preview ignoring the mouse: SetOnUpdateMode takes an enum value rather than a name, so passing it a string left the drag driver switched off and the preview only moved by arrow keys. Every call site is corrected in the same pass - the TotemFrame preview, aura group dragging in MSUF Edit Mode, the class resource preview animation, and the position debug overlay - and each one now tolerates a client that does not offer the method at all.",
                        "Fixed the TotemFrame keeping MSUF's position after the feature was turned off during combat, which held until the next enable or UI reload; the restore now completes when you leave combat.",
                        "Stopped refreshing the TotemFrame on every successful player cast. Blizzard's own rebuild is hooked instead, which covers totem drops, shapeshifts, talents, and spec changes in one place, so the two timers that ran per cast are gone. Each refresh also verifies parent, anchor, scale, and strata before writing, so a Blizzard-driven rebuild costs a handful of getters instead of a full re-layout.",
                        "Fixed /msuf gfhoverdebug doing nothing at all: only a handful of sub-commands were forwarded from /msuf to the older handler, and everything else fell through to the page opener and drew an empty page.",
                        "Dropped !msuf help and /msufdbgpos from the help output. The chat trigger was removed a while ago and the position debugger is not shipped, so the help listed two commands that did not exist. Diagnostic commands now add themselves to the help from the file that owns them, which makes that class of drift impossible.",
                        "The compiled aura icon style is memoized per runtime configuration, so all lanes in a refresh share one style table instead of each re-reading the database and re-resolving its border media.",
                        "Fixed Class Resources ignoring auto-hide in three situations, each leaving the bar at whatever opacity the previous repaint happened to set until some unrelated event moved it: a secret power value, which only rules out the full and empty checks but not the combat one; an idle Ebon Might timer whose remaining time never changes; and the refresh that first switches the bar on at login, spec change, or feature toggle.",
                        "Fixed Smooth fill doing nothing in combat since Beta 26. The hot-path rework started writing restricted (secret) health and power values without the configured native interpolation, and in combat live values are restricted - so health bars, the Player power bar, Class Resources, Alternative Mana, and the Class Resources Player HP bar all snapped exactly when smoothing is meant to show. The StatusBar API accepts a restricted value together with an interpolation mode and animates it client-side, so those writes now keep the configured smoothing; only the write deduplication still skips restricted values, which never enter Lua comparisons. Class Resources also stopped paying for repaints that change nothing: pip values and the resource text are deduplicated Lua-side now, so an aura or power event that leaves a pip as it was no longer issues a native call for it.",
                        "Fixed the Devourer Demon Hunter class resource ignoring Separator and Pip gap. It was drawn as a single continuous bar, so Outline was the only style slider that changed anything. It now draws one segment per soul fragment - counted the way Blizzard's own bar counts them, from Dark Heart outside Void Metamorphosis and from the collapsing star cost inside it - so separators, pip gap, and hide-when-full or hide-when-empty behave like they do on every other class resource. A client that does not report a usable count keeps the previous single-bar fill.",
                        "Fixed the Assistant dashboard card showing its \"Early Alpha\" notice only after the companion had loaded, so the placeholder shell carries it too.",
                        "MSUF Edit Mode's quick popup \"Copy to...\" copied the source frame's position as well, which dropped the destination exactly on top of it \" and a stacked frame cannot be grabbed to drag it back off. It now copies size only and says \"Copy size to...\", on both unit and group popups. Use the unit page's copy dialog when position really should travel.",
                        "Fixed aura preview stack and timer text ignoring their configured anchor, so a corner placement no longer renders centered, and resolved the preview font once per font, size, and outline instead of re-resolving it on every stack and timer update.",
                        "Expanded the Core Lua 5.1 suite to 164 passing tests, including new aura border style, slash-command registry, Devourer class resource, and unit copy coverage regressions.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta28",
            date = "2026-07-25",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Fixed unit frame and group frame tooltips not appearing on hover at all; hovering Player, Target, Focus, Pet, Party, and Raid frames shows the unit tooltip again, and the related tooltip settings do something once more.",
                        "Rebuilt aura icon layering on one shared 0-30 scale per frame kind, so an aura lane at layer 7 now renders above a text at layer 5 and below one at layer 9 instead of sinking below every text and status element.",
                        "Added \"Show Weapon Enchants (Player)\", which renders temporary weapon enchants as native icons inside the Player buff lane.",
                        "Menu previews now mirror the live frame: real name, class, portrait, level, reaction, and exact Health/Power/absorb values, with the stylized sample kept as the fallback.",
                        "Fixed the Anchor Picker freezing the game while open by moving the expensive anchor-cycle walk out of the hover loop; rejected targets are now reported when you confirm one.",
                        "Retired the separate Class Resources detached power textures so the Bars page and the Player unit page own the power bar's art whether it is detached or not; a customized detached texture migrates onto the Player page once.",
                        "Fixed the MSUF Color Picker's color wheel, brightness bar, and opacity slider ignoring the mouse, which left the compact picker looking frozen; dragging them changes the color live again.",
                        "Fixed the Castbar texture not stretching across the bar: the fill repeated the 256 px art instead of scaling it, which showed a seam near the right edge of the default Player and Target castbars and cut the gradient short on narrower ones.",
                        "Rebuilt the Custom Aura full-frame Glow effect: instead of stretching Blizzard's square action-button alert art over the wide health bar, the glow is now a crisp radial halo with round corners that fits any bar shape. It renders from eight static slices of one small texture with no animation, so an active glow costs nothing per frame; the marching-ants glow stays on square aura icons where it belongs.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Moved the Aura \"Icon Border Color\" and \"Icon Shadow Color\" swatches to the Colors page under a new \"Icon Border & Shadow\" card, reachable from the Aura style section through the three-dot color shortcut. Thickness, size, and alpha stay inline.",
                        "Added a \"Lane Padding\" slider that insets aura icons from the lane box using the native flow padding.",
                        "Replaced the Class Resources \"Power Textures\" card with a \"Shape Outline\" card that only keeps the Round/Crystal/Orb edge it still owns.",
                        "Made \"Reset to defaults\" drop the matching runtime caches, so a reset frame no longer keeps pre-reset aura offsets, spell-indicator anchors, textures, castbar styling, or positions.",
                        "Hidden group frames now unregister their unit events by default instead of only when opted in; single frames are excluded because their unit is already gone when hidden. /msufgp suspendhidden default restores the automatic behavior.",
                        "Added the /msufauralayers diagnostic, which dumps the aura level/strata chain and probes host and container layering live. It is inert until invoked.",
                        "Added \"New character profile\" to Profiles > Profile Management, which picks the profile a brand-new character starts on instead of always landing on Default. The active profile itself stays a per-character choice, and the setting clears itself if the profile it points at is deleted.",
                        "Made the menu accent color own only the interactive layer by default: navigation, tabs, pills, focus rings, and highlights follow the accent while panels stay midnight. The new \"Tint menu surfaces\" toggle under Global > Misc > Menu behavior restores the full re-tint of panels, borders, and the navigation rail, and applies after a UI reload just like the accent itself.",
                        "Split the Custom Aura \"Icon Style\" card into the same accordion sub-sections the Buff and Debuff style pages already use - Basics, Stack Count, Cooldown Text, and Duration Bar - for every custom container including Dots on target. Detail controls now gray out while their master toggle is off, so it is visible at a glance which sliders belong to which feature.",
                        "Brought Custom 1-3 and Dots on target to full feature parity with the Buff and Debuff lanes: Basics gained Icon Zoom, a container Opacity slider, and a Dispel-type Border choice for harmful containers, and a new Ordering section carries the same Sort By and Order options the lanes have. The shared \"Lane Padding\" inset now applies to custom containers as well, and all custom style sections show the same collapsed-header summary badges as their lane counterparts.",
                        "Updated all supported locales for the new aura color, shape outline, icon border/shadow, new character profile, and menu surface tinting controls.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Folded aura lanes that legacy builds and imports had pinned to the MEDIUM strata back to AUTO exactly once, so aura layering can be ordered against bars and texts again; a deliberately re-picked strata is kept.",
                        "Made the aura container the single layering authority and stopped writing AuraButton levels and strata entirely, which is the surface PTR 7 restricts hardest.",
                        "Fixed spell indicator icons on unit frames rendering a full band below every text at the same layer.",
                        "Fixed an aura lane dying when a filter token Blizzard rejects reached the native validator; the lane now falls back to its plain base filter and reports the reason.",
                        "Fixed the group and unit preview raid group number, target-of-target name, and portrait so they follow the live roster and unit instead of a fixed sample.",
                        "Fixed preview edits not reaching the live frame when no host panel was attached, and when the text-layout entry point was unavailable.",
                        "Made in-combat hovers cost a single flag read while tooltips are set to Never or Out of combat, recomputed only on combat transitions and setting changes.",
                        "Debounced group frame tooltips by a short hover delay, so sweeping the cursor across raid frames only builds a tooltip for the frame it settles on.",
                        "Collapsed the aura combat check to a single upvalue read after the aura container has loaded once, so combat identity refreshes pay no C calls there.",
                        "Moved aura strata and level writes behind the geometry signature guard, so content-only refreshes such as aura swaps and identity updates perform no widget calls.",
                        "Coalesced live preview refreshes on a wider window, capping value streams at five renders per second, and dropped every listener for the duration of a fight.",
                        "Removed the pcall wrappers from aura font application and validated SetFont through its return value instead.",
                        "Fixed the detached power bar preview and the global texture refresh still resolving the retired detached texture keys.",
                        "Made the repair that runs when a character's active profile has gone missing always clone the same source \" Default when it exists, otherwise the first profile by name \" instead of whichever profile the table happened to hand back first.",
                        "Fixed menu labels becoming unreadable under a bright accent. Rotating the palette onto a new hue does not preserve luminance, so accents like the gold class colors or Jade could leave near-white text on a light pill. The text ramp is now re-validated against WCAG contrast after an accent is applied, and an accent-colored pill darkens to a deeper shade of itself rather than flipping its label to black. Success, warning, and danger colors are never touched.",
                        "Brightened disabled control labels from a 2.4:1 to a 3.7:1 contrast ratio against the panel, so a gated control still reads well enough to tell what enabling its parent would unlock.",
                        "Dropped three menu textures per glassed frame \" the grain, the outer glow, and the top-line bloom \" plus the panel depth grain. All of them carried 0.008-0.014 alpha in a color within ~0.01 of the surface beneath, which resolves to less than one 8-bit level: they cost draw calls to render nothing visible.",
                        "Expanded the Core Lua 5.1 suite to 159 passing tests, including new anchor picker scan budget, preview live parity, page reset cache purge, and new-character profile selection regressions.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
