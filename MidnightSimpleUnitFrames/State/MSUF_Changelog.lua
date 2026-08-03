-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-RC4",
    previousVersion = "6.0-rc3",
    rangeLabel = "6.0-rc3 -> 6.0-RC4",
    entries = {
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
                        "Fixed the Unit Frame preview sometimes turning into a black plate or hiding the selected health-bar texture. Background and fill opacity now remain independent, including a real zero-alpha state, and per-unit background values update immediately while editing.",
                        "Fixed preview rounded edges, square outlines and selection handles competing for the same draw level. Only the configured border owner is visible, and drag handles remain above every configurable visual layer.",
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
        {
            version = "6.0-RC2",
            date = "2026-08-02",
            sections = {
                {
                    title = "Fixes",
                    bullets = {
                        "Restored unit-frame anchoring to CooldownManager, Skiron, Arc UI, and Coolinator.",
                    },
                },
            },
        },
        {
            version = "6.0-RC1",
            date = "2026-08-02",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Dots on target now support portrait tracking. The lane can move onto the frame portrait with up to eight portrait-sized icons that follow its exact width, height and shape, including cooldown text, on Target, Focus and Boss frames.",
                        "Aura icons can now take a shape: Rectangular, Circle, Rounded, Diamond, Hexagon, Star, Blizzard portrait, or Follow frame portrait. The choice exists per lane for unit buffs and debuffs, group lanes and custom containers, and each lane can optionally follow the Shared shape while keeping the rest of its style local.",
                        "MSUF castbars can use the rounded frame style. A new \"Castbars\" toggle in Rounded rounds the castbar surface, its fill and its outline with the shared corner strength; Blizzard castbars, spell icons and the GCD bar stay untouched.",
                        "New opt-in Ironfur tracker for Guardian Druids. In Bear Form the empty class-resource slot shows an estimated Ironfur lifetime bar with one moving marker per cast, including Ursoc's Endurance (7s to 9s base) and Guardian of Elune (+3s).",
                        "Unit name text gained a full anchor set: Top Left, Top Center, Top Right plus a new vertically centered Left, Center and Right row. Existing profiles migrate their old values to the matching top anchors.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Unit-frame Aura filters no longer expose the legacy \"Own filters\" prerequisite. Migrated 5.77 profiles keep their saved Shared/Own behavior, while the first filter change on a frame automatically creates an isolated copy so Enable filters and every detailed filter work immediately without changing other frames.",
                        "Custom aura containers now resolve spells by name the way WeakAuras does. A talent or spellbook ID whose visible buff carries a different spell ID (Shadow Dance, Fade to Nothing) is matched once the aura appears.",
                        "Fade to Nothing was added to the Rogue defensive list.",
                        "The rounded \"Aura borders\" toggle is gone; aura icon edges now follow the new Icon Shape instead.",
                        "Profiles: \"Backup & Transfer\" is now called \"Import & Export\" everywhere, including the hero card and the guided tooltips.",
                        "The Assistant answers feature-existence questions (\"does MSUF have a GCD bar?\") in a dedicated read-only lane instead of falling through to a generic list of pages.",
                        "A question that names one exact control is now answered about that control instead of the topic its words belong to, and the label lookup runs off an index instead of scanning every registered setting.",
                        "The Assistant reports a corrected value instead of silently clamping it, so \"set player width to 4000\" says that MSUF applied 900.",
                        "A plan that switches many frames off at once is flagged as a destructive sweep and names what disappears before it runs.",
                        "The Assistant learned the new name anchors: \"top left\" and \"upper right\" pick the top row, while a plain \"left\", \"center\" or \"right\" now aligns the name on the frame's vertical middle.",
                        "\"Set player alpha to 50\" is read as frame opacity again instead of matching the alpha channel of some colour swatch, and an NPC-qualified bar colour request reaches the NPC control instead of the nearest generic colour mode.",
                        "\"Reset everything\" and \"hide everything\" name a scope, not a control, so the Assistant explains the actual options instead of picking one wholesale action.",
                        "\"No, I meant target\" re-aims the change that just ran instead of starting a new request, and \"what is Castbar Texture\" defines that control instead of the topic its words belong to.",
                        "Opening a setting from a preview now lands on the exact tab: the matching text slot, portrait placement, the castbar's icon, time or spell tab, the selected texture-layer slot, an aura lane's Layout tool, and the Class Power text, detached power and player health tabs.",
                        "Refreshed the factory default profile and raised the profile normalization revision.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Clarified and corrected tooltip ownership: Always, Out of Combat, Modifier and Never now control unit and group frame tooltips only, while every aura lane keeps its own Show Tooltip switch. Aura tooltips still follow the selected Blizzard/MSUF appearance and cursor position, and stale per-unit aura values can no longer override the Shared tooltip setting.",
                        "Hardened the 5.x-to-6.0 profile conversion and import/export round trip so every element keeps its placement, including unit frames, texts, portraits, bars, castbars, status and private-aura icons, Class Power, Party/Raid/Mythic frames, spell indicators, group auras, and Aura2 lanes migrated to Aura3.",
                        "Failed profile exports and imports now say what actually went wrong instead of reporting a bare \"materialization failed\".",
                        "The Assistant no longer offers to set the group frame Blizzard fallback mode, which Beta44 removed.",
                        "Spell indicator filters now deduplicate their compiled spell IDs including the new aliases.",
                        "Optional callbacks across the options UI, search index and Assistant catalog share one error boundary, so a failing page provider reports itself and lets the rest of the menu finish instead of being handled four different ways.",
                        "Fixed saved bar background transparency not being restored after login or a reload. A secure show transition could reset the live texture while the cached value still matched, so the cold apply skipped it; the three owning elements are now reasserted once after the world finishes loading.",
                        "Fixed portraits occasionally showing another unit's art. The bounded session texture cache added in Beta44 could answer with a stale asset because native portrait resolution can finish asynchronously; the cache is gone.",
                        "Fixed the portrait \"Size override\" slider doing nothing whenever a width or height override was still stored. Size now wins, the per-axis overrides only apply while Size is Auto, and both are disabled for a portrait that fills the bar.",
                        "Fixed unit-frame portrait previews disagreeing with the live frame and Edit Mode. Auto-sized portraits now use the geometry applied by runtime, while Attached and Overlay portraits account for the health-bar space reserved by an embedded power bar; manual sizes and Detached placement keep their existing behavior.",
                        "Fixed Range Fade controls staying disabled after \"Enable Range Fade\" was switched on. The opacity slider and Affects selector now activate immediately without leaving and reopening the MSUF menu.",
                        "Unified every layer-controlled MSUF visual under one real 0-30 draw order. Castbars, text, status icons, portraits, auras, spell and dispel indicators, outlines, texture layers, detached bars and class resources now compare directly across unit and group frames; an element's text, border, cooldown or glow can no longer jump above the next user layer, and the live frames, Edit Mode and menu previews follow the same order.",
                        "Fixed the Unit Frame Castbar Advanced panel clipping its Whole Castbar Layer card into the following Status Icons section.",
                        "Fixed castbar text ignoring a per-unit font scope's shadow settings while the scope refresh itself did run.",
                        "Fixed the \"Interrupted\" flash always painting the bar red instead of using the configured Interrupt Feedback color. Player, target, focus and boss castbars now read the same setting.",
                        "Fixed the rounded castbar surface not picking up empower stage segments created after the first refresh.",
                        "Fixed boss frames coloring friendly boss-slot units as hostile. Boss NPC coloring now resolves the unit's actual disposition first.",
                        "Fixed boss placeholder data drawing a fixed red health bar, or a black one when the range fade had already dimmed the fill. The placeholder now follows the configured health color mode.",
                        "Fixed profile imports losing everything stored under a numeric key. The fallback serializer quoted table keys, so a spec or spell ID like [71] came back as [\"71\"] and the geometry saved below it was orphaned.",
                        "Fixed 5.x and Wago profile imports aborting before settings were committed when a profile referenced an unavailable SharedMedia font. Missing fonts now produce a warning and fall back safely instead of stopping the import.",
                        "Fixed the profile export box painting its text across the menu once the string outgrew it. The box now scrolls inside its own clipped host frame.",
                        "Fixed the profile string box emptying itself after an import, and when the \"Import and create new profile\" toggle was flipped. The pasted string stays put, so sending it into a new profile no longer needs a second paste.",
                        "Fixed the Aura Duration Bar dropdowns stretching across the entire settings panel and covering the controls below. Display, Position, and Fill Mode now share one compact responsive row on wide layouts and stack cleanly when the menu is narrow.",
                        "Fixed the Color Painter preview swallowing clicks on the background selector and the zoom bar, and fixed selection chrome reappearing there after a renderer refresh.",
                        "Fixed pinned previews hiding the settings they belong to. A full inline preview is no longer compressed to the pinned minimum height, it is capped so the target control still fits underneath, and jumping to a section now scrolls clear of the overlay at any menu scale.",
                        "Fixed previews rendering at the wrong size when the menu and the game use different scales. Unit and castbar previews now measure against the live frame's effective scale, and a castbar following its unit frame's width no longer falls back to the preview width.",
                        "Fixed the group preview's jump-to-settings landing on the wrong section for buff, debuff and external lanes, and fixed the detached power bar handle opening the Power section instead of its own Class Power section.",
                        "Fixed Edit Mode aura dragging leaving the Buff and Debuff X/Y values stale in Settings. The coordinate controls now stay synchronized with the moved lane.",
                        "Fixed a rejected anchor during an Edit Mode drag leaving frames scattered. The move is rolled back to its last valid position, boss frames included.",
                        "Fixed the Assistant answering \"frame outline texture\" with an outline-versus-border clarification instead of the control that Beta44 added.",
                        "Fixed Assistant questions about a font shadow failing when the shared shadow resolver was not reachable.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
