-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-RC11",
    previousVersion = "6.0-rc10",
    rangeLabel = "6.0-rc10 -> 6.0-RC11",
    entries = {
        {
            version = "6.0-RC11",
            date = "2026-08-06",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added optional Grid2 and Details! integration to MSUF Edit Mode. Both addons keep ownership of their frames and saved positions.",
                        "Added native WoW 12.1 Player resource pings for health and supported mana states. Portrait pings keep the normal radial wheel.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added a public API for registering external frames with MSUF Edit Mode.",
                        "Expanded translations for recent Aura, Preview, Class Resource and Layer settings.",
                        "Unified the detached Player Power outline across settings, Copy To, live frames and previews.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Group Preview layer order and Name positioning for all anchors.",
                        "Fixed detached Player Power outline thickness at different preview zoom levels.",
                        "Fixed exact Assistant commands being intercepted by greetings, guides or movement shortcuts.",
                        "Added Assistant help for shortened and clipped Unit and Group names.",
                    },
                },
            },
        },
        {
            version = "6.0-RC10",
            date = "2026-08-06",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Reworked Menu2 preview interaction around the rendered result. The preview background can now pan directly, selected position controls stand out more clearly, disabled elements route to their owning settings, and all selection handles stay centered on the pixels they actually represent.",
                        "Made Group target and focus indicators safe for WoW 12.1 restricted combat data. Readable identities continue to use the existing O(1) GUID buckets, while secret comparison results are forwarded directly to Blizzard's restricted-safe region alpha API without scanning the group or branching on protected values.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Removed the Navigation Hover Size option and its row magnification behavior. Navigation entries now keep a stable width and layout while hovered, and the retired setting has been removed from defaults, profile repair, locales, search and Assistant metadata.",
                        "Renamed the Unit and Group transparency base state from In Combat to General so the editor matches its actual always-on ownership; the separate Out of Combat state remains unchanged.",
                        "Selecting a visible castbar icon border style now restores a minimal border thickness when the independent thickness value was still disabled.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Group Border leaking between Party and Raid layouts. Persistent border anchors now follow the active live scope immediately, including roster transitions during combat, so Party borders cannot remain visible in a raid and Raid/Mythic Raid borders cannot remain visible in a party or while solo.",
                        "Fixed clipping and overlapping controls in the Group Spell Icon Style editor. The Stack Count controls now stay inside their card, the shared appearance hint clears both columns, and enabling Duration Bar immediately activates Height, Display, Position and Fill Mode without reopening the menu.",
                        "Fixed Group target/focus borders under restricted combat data, reconnects and target changes. Rounded and square indicators now share the same secret-safe visibility contract, retain readable frame identity through restrictions and update only the affected GUID bucket or hinted frame.",
                        "Fixed Unit and Group preview text, text handles and composite element handles drifting at non-default frame scale, Fit zoom or after panning. Text now uses the same font-size-then-frame-scale order as live frames, scaled rectangles are converted into canvas space once, and pan-following handles move without a full repaint.",
                        "Fixed additional preview interaction issues: minimum-size and remaining handles are centered, Dispel Symbol bounds use the rendered art, castbar child handles win over their container, direct Aura navigation stays expanded, and non-Player previews no longer expose Class Resource controls.",
                        "Fixed full Unit previews inheriting an unintended first-use Fit scale instead of opening at 1:1, while later user-selected zoom and pan remain authoritative.",
                        "Fixed the Color Painter hiding disabled castbars or empty Aura lanes and reusing an unrelated camera state. Castbar and Aura color views now start fitted, remain inspectable and remember their own zoom and pan.",
                        "Removed temporary table allocations from live castbar interrupt feedback while preserving the public options-table compatibility path.",
                        "Fixed Assistant routing added around RC9 controls: Group scope words and conversational lead-ins no longer block exact settings, Pandemic details no longer mutate unrelated borders, contracted questions remain read-only, and explicit activate/deactivate commands keep the requested polarity.",
                        "Fixed more Assistant exact-setting commands phrased with polite lead-ins or everyday verbs such as Configure, Update, Modify, Customize and Tweak. Numeric requests containing text-mode words such as max now continue to their actual numeric control instead of being intercepted as an incomplete HP-text command. These routes reuse already-warm label and alias indexes, keeping the cold synchronous preflight fast and leaving conjunctions to compound-command parsing.",
                        "Fixed Assistant Copy To handling for independent Aura Options, Aura Style and Texture Layer categories so style-only requests no longer fall back to broader content or default copies.",
                        "Fixed Assistant catalog-only controls, percentage-bearing labels and ambiguous commands with supplied values. Exact catalog controls now get their turn before generic guidance, % survives rendered labels, and a numeric follow-up can complete the selected mutation without retyping the request.",
                    },
                },
            },
        },
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
