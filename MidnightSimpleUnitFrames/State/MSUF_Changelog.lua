-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-Beta45",
    previousVersion = "6.0-Beta44",
    rangeLabel = "6.0-Beta44 -> 6.0-Beta45",
    entries = {
        {
            version = "6.0-Beta45",
            date = "2026-08-01",
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
        {
            version = "6.0-Beta44",
            date = "2026-08-01",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "New Texture Layer for unit frames: three decorative texture slots per frame, each with its own SharedMedia or custom texture, size, anchor target (frame, health, power, portrait), strata and level, custom or class color with a multi-direction gradient, blend mode, mirroring, combat-only visibility and rounded clipping.",
                        "Unit frames and group frames can now fade out of combat. The whole-frame opacity is set per scope on a new \"Out of Combat\" tab in Transparency, and composes with Range Fade so the strongest fade wins.",
                        "New \"Blizzard ring\" portrait shape: the client's own circular portrait mask, the gold ring cut from Blizzard's player-frame art and its corner embellishment, drawn untinted at any portrait size.",
                        "Text colors are now controllable per element. Each castbar can color its spell name, cast time and target name separately, and Level, Race, Class, Raid Group, Dead, Ghost, AFK and DND text each take their own color. Anything left unset keeps following the font color it inherits today.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "The square frame outline can use a texture instead of a solid color, globally or per unit and group scope. Rounded frames ignore it and keep the tinted rounded edge.",
                        "Blizzard frame ownership is now decided per unit only. The global \"Disable Blizzard unitframes\" and \"Fully Hide Blizzard PlayerFrame\" toggles are gone; use \"Force Blizzard frame on\" in a unit's Frame Basics to keep a native frame.",
                        "Copy To no longer offers to copy placement. \"Size & Anchoring\" is now \"Frame Size\" and copies width and height only, on both unit and group pages, because two frames sharing a position land on top of each other.",
                        "Copy To gained a Texture Layer category and now copies settings it previously skipped: direct text layout and legacy text keys on units, and frame scaling, detached power, out-of-combat fade, per-slot text sizes and offsets, all status icons, aggro and dispel-symbol keys on groups.",
                        "Rounded frames now also cover group target and focus indicators, group block borders, spell indicator edges, group aura visuals, the debuff stripe and the over-absorb glow.",
                        "Menu2 sliders and the menu scale slider now follow the cursor for as long as the mouse button is held instead of jumping once per click.",
                        "The options window only starts a drag from its chrome, so a click that misses a control no longer moves the whole window.",
                        "The release tour can host live settings: the rounded frames card lets you switch the style and corner strength directly from the card.",
                        "Unit frames gained the custom name color that group frames already had, as a third choice next to Default and Class color in the Fonts scope.",
                        "The Colors page groups the new swatches into Castbar Text Colors, Status Text Colors and Texture Layer Colors, and each one is also reachable from the unit page card that owns it. Right-clicking a castbar text swatch drops the override and follows the shared castbar color again.",
                        "Copy To now carries castbar text colors and status indicator colors along with their placement, instead of copying half the setting.",
                        "Aura icons placed in the portrait stay square. Shaping them to the portrait was tried and reverted because 12.1 native aura buttons ignore icon masks; the Auras page now says so instead of leaving you looking for the option.",
                        "Translation pass across all twelve locales: every new setting is translated, several German terms that were machine-translated nonsense are corrected, and text-slot strings that were still English in Russian, Korean and Chinese are now localized.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed the guided tour and the release tour offering themselves again on every menu visit. Both wrote their completed state into an orphaned table when the SavedVariables root was replaced by profile repair or a reset.",
                        "Fixed a configured Dead, Ghost, AFK or DND text color being dropped again by the next font change.",
                        "Fixed boss frames drawing their outline, mouseover highlight and rounded mask against the wrong rectangle when the power bar is embedded, and fixed their square border reappearing after a rebuild.",
                        "Fixed the absorb value in health text ignoring \"Short numbers\" and the thousands separator. The 12.x client hands out absorbs as secret values, which the zero-hiding path could not format.",
                        "Fixed the portrait cast spell icon staying visible after the option was switched off.",
                        "Fixed the unit preview disagreeing with the live frame while Direct Text Layout is active: it placed name, health and power text with the legacy offsets instead of the direct anchors. Slot colors, reversed health sides and the drag handles now line up with the runtime too.",
                        "Fixed several menu sections clipping into the next accordion header: Frame Outline, UnitFrame Dispel Symbol, and the unit Text section, whose height now follows the selected tab instead of one fixed value.",
                        "Fixed Copy To popups stacking the last category over an earlier one once a page had more than ten categories.",
                        "Fixed Copy To panels and other menu popups being drawn underneath a pinned preview.",
                        "Fixed the colored bullet of a color shortcut being painted back on top of its dots after the surrounding controls were re-shown.",
                        "Boss castbars now share one lifecycle handler, collapse same-frame encounter events into a single pool pass, and skip anchor and layout work when no cast is active.",
                        "Aura and range-fade lifecycle work is coalesced when several boss frames appear at once, and the on-show identity refresh no longer runs twice for the same unit.",
                        "Health gradient curves are cached instead of rebuilt per frame, and portrait textures reuse a bounded session cache.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta43",
            date = "2026-07-31",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Rounded unit and group frames now use a clean adjustable corner style with five strength levels. Health, embedded or detached Power, frame outlines, aggro/dispel/highlight borders and mouseover effects share the same geometry.",
                        "Profiles gained a redesigned management workspace with a persistent active-profile overview, responsive management cards, safer import/export guidance and clearer specialization assignments.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "The MSUF Assistant gained broader exact setting coverage for unit and group auras, text, bars, fonts and profiles, plus more useful local guidance for comparisons, troubleshooting and incomplete requests.",
                        "Unit and Group preview layer buttons now identify the currently selected draggable element, while responsive preview and profile layouts rebuild correctly after menu-scale changes.",
                        "Rounded-corner strength updates the lightweight preview during dragging and applies the live runtime once on release or after a short bounded delay.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed rounded Group frames, embedded Power bars, native Dispel overlays and modern frame borders losing or mismatching their outer mask, separator or border treatment.",
                        "Fixed the Rounded Texture preview overlapping the following Menu2 sections after the corner-strength control was added.",
                        "Fixed secret health colours reaching unsafe Lua comparisons in background matching, and made Group Power textures resolve once into the compiled cold-path configuration.",
                        "Fixed hidden Party-only Portrait sections reserving space in Raid/Mythic layouts and made Aura preview scaling tolerate accessible numeric values.",
                        "Fixed Assistant routing regressions for guided tours, natural health-text commands, contextual follow-ups and explicit negated or list-clearing commands.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta42",
            date = "2026-07-30",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Group External Defensives now use Blizzard's native 12.1 classification and can automatically stay out of the normal Buff lane while their dedicated lane is visible.",
                        "Unit and Group preview canvases can now use bright stone, a city scene, dark stone, Studio, or a custom color to check readability before applying settings.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Preview canvases start expanded after reload, keep configured frame outlines visible, and handle overlapping Aura controls more reliably.",
                        "Menu2 dropdowns stay inside their owning window; non-Midnight accents use a calmer shared highlight ramp across navigation and window controls.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Edit Mode dock dragging so it follows the cursor reliably, remains within the screen, and only snaps to an edge when released near one.",
                        "The explicit realtime Player Power Text option now follows the direct power-event update path; normal Power Text keeps its existing coalesced update behavior.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
