-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-RC13",
    previousVersion = "6.0-RC12",
    rangeLabel = "6.0-RC12 -> 6.0-RC13",
    entries = {
        {
            version = "6.0-RC13",
            date = "2026-08-07",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added optional Dominos integration to MSUF Edit Mode. Undocked bars get movers and a native MSUF popup covering the bar's layout settings - Buttons, Columns, Spacing, Padding, Scale, Opacity, Faded Opacity, visibility and click-through - while Dominos keeps ownership of all bar settings.",
                        "Added optional DandersFrames integration to MSUF Edit Mode. Party, raid and free pinned sets get movers, selecting an element starts DandersFrames' own unlock preview for that scope, and DandersFrames keeps ownership of all saved positions.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "External Edit Mode elements can now declare their own quick controls. MSUF renders them as native stepper and toggle rows in the external popup and routes every change through the normal undo history.",
                        "The Edit Mode toolbar now slides in from its docked edge when Edit Mode opens. Reduce Menu Motion skips the animation.",
                        "Trimmed the Dashboard's Display & recovery card to Reset Positions, Print Help and Factory Reset All. The duplicate Wago and Discord buttons were removed; both links stay in the Wago and support rows.",
                        "Restarting an already completed Guided Setup from the Dashboard now asks for confirmation. Resuming an active tour and the first run stay one click.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed the Follow HP bar (overflow) prediction anchor drawing into neighbouring group frames. The overlay is now clipped natively to Blizzard's 5% overflow allowance.",
                        "Fixed overflow prediction bars dropping behind neighbouring frames after re-parenting, and rounded frames clipping away the segment that anchor mode exists to show.",
                        "Fixed group frames built after the startup pass - login roster races and late joins - never receiving their rounded mask.",
                        "Fixed Edit Mode tooltips drawing underneath the toolbar, and the Cancel All / Exit buttons ignoring the toolbar font.",
                        "Fixed the Aura style preview staying hidden when returning to an already built Aura page.",
                        "Fixed set Custom Menu Accent Color to red storing black. The setting now uses the same single-color contract as every other color.",
                        "Fixed Assistant enum values with an underscore being unselectable by name, such as the Blizzard Ring portrait shape and the Dispel Symbol styles that share a stem.",
                        "Fixed control names longer than eight words never entering the Assistant's exact-label index; 36 controls could not be reached by the name the menu prints.",
                        "Fixed a command that spells exactly one control's name being answered with a candidate list instead of changing it - colors above all.",
                        "Fixed enable target combat state indicator toggling the global Combat Enter/Leave Text or the Blizzard Totem Frame instead of the unit's Combat Indicator.",
                        "Fixed the Assistant rejecting an Inline Custom Separator longer than five characters instead of storing the trimmed value.",
                        "Fixed the Big Defensive sort method being unselectable by name, and Only Mine on the preset custom container reporting a failed write instead of explaining that MSUF pins it.",
                        "Follow-ups to a readability answer (make it wider, actually make it 320) now apply to the control that answer named, and a shortened indicator name continues the subject already under discussion.",
                    },
                },
            },
        },
        {
            version = "6.0-RC12",
            date = "2026-08-07",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added Back and Forward page navigation to the menu status strip. Both buttons name their target page in the tooltip, skip the transient Search page, and are available to the Assistant.",
                        "MSUF frames now follow a supported Cooldown Manager provider live while out of combat. Unit frames, Group headers and Class Resources keep a real anchor link to Arc UI, Skiron, Coolinator and Blizzard's viewer, and that link is severed at the combat edge so provider movement can never drag a protected frame mid-fight.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "The Detached Power width mode now outranks a Detached width typed on the frame; the shared Class Resources width mode remains its fallback while width sync is on. Manual resolves to no source, so untouched profiles keep their current width.",
                        "Status text colors now have one entry point per surface: the ::: shortcut on the Status > Selected card and the canonical Colors page. The duplicate swatch on Status > Placement was removed.",
                        "Split the runtime chat/tooltip file into dedicated slash command, unit tooltip and Blizzard Edit Mode bridge modules. Load order, exports and behavior are unchanged.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed MSUF frames not following a Cooldown Manager provider that moved or resized without changing identity. Provider movement is now free out of combat, and combat-time changes are replayed once after regen instead of being lost.",
                        "Fixed frames anchored to a provider whose geometry is not readable yet rendering nowhere. They now keep the cached screen position or fall back to UIParent and retry on the bounded late-anchor pass.",
                        "Fixed Group Cooldown Font and Stack Font not applying until an unrelated setting was changed. Aura text sizes now invalidate the aura domain instead of the text-only fast path.",
                        "Fixed the Custom Aura Pandemic color losing its menu entry. The color is reached through the section's ::: shortcut, and menu search and the Assistant resolve to that shortcut.",
                        "Fixed the detached Power width preview disagreeing with live frames when a Cooldown Viewer source was selected.",
                        "Edit Mode frame positioning is now blocked at the combat boundary and rolls back atomically when an external anchor target cannot resolve.",
                        "Class Resources no longer runs its layout twice when the same Cooldown Viewer provides both its anchor and its width.",
                        "Font runtime resolves its apply-cache helpers once at load instead of per FontString, and the combat regen drivers arm their event only once per fight.",
                    },
                },
            },
        },
        {
            version = "6.0-RC11",
            date = "2026-08-07",
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
