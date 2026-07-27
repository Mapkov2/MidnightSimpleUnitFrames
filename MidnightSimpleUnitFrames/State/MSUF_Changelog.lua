-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-Beta33",
    previousVersion = "6.0-Beta32",
    rangeLabel = "6.0-Beta32 -> 6.0-Beta33",
    entries = {
        {
            version = "6.0-Beta33",
            date = "2026-07-27",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "The MSUF Assistant can now change close to two hundred settings it used to refuse. A setting stayed read-only whenever nothing proved which values it accepts, so ordinary requests like \"set target absorb bar height to 6\" were declined even though the slider for exactly that sits in the options window. Those ranges are now taken from the control that owns them: 112 settings gained the range of their menu slider, another 76 gained the closed list of choices their dropdown offers, and texture and portrait-pack fields are checked against the media you actually have installed instead of a fixed list. Anything without that evidence stays read-only, and a build check re-reads the options source, so the range the Assistant writes can never drift away from the slider you see.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "\"Show cast spell icon in portrait\" now also sits on the Cast Bars section's Icon tab, in its own \"Portrait Cast Icon\" card. It is the same setting as the one under Portrait > More Options and either one updates the other; it is there because that is where it gets looked for. It still needs the portrait enabled, and it works with both castbar providers.",
                        "The Cooldown Manager and global anchor buttons are no longer limited to the advanced Edit Mode layout. They were built only for that layout, so the standard toolbar had no way to reach either one; the toolbar is a little wider now to hold them.",
                        "The Assistant no longer offers a dozen fields that were never controls: legacy mirrors of the health and power text slot modes, of the group aggro border and the highlight priority toggle, the tooltip style derived from the anchor dropdown, and interface state the options window keeps for itself, such as its own size and the dashboard's tip counter. Each of them was answered as if it were a setting, so \"set the window width\" could land on the options panel instead of a frame.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed AFK and DND text never appearing on anything but the player frame. The client does not report another unit's away toggle through the event MSUF was listening to, so a target or party member going AFK changed nothing until something unrelated happened to refresh the frame. Frames that show AFK or DND now listen for the event that actually carries it, filtered to their own unit.",
                        "Fixed AFK, DND, dead and ghost text falling back to the base position and size after a refresh that did not come from a flag change - a font change, a PvP context change, or a group reseed. The placement that belongs to the shown state is now applied at the same moment the rest of the text is.",
                        "Fixed the aura \"Decimals below sec\" sliders reading back the global value in the options window. The per-unit value is stored in the shared layout, and the menu stopped looking before it got there, so the slider could show something other than what the frame was using.",
                        "Fixed the Assistant losing the subject of a help answer on /reload. \"Where is it\" or \"explain that simpler\" then resolved against the last setting you changed instead, so you could ask about range fade, reload, ask where it is, and be handed the menu location of an unrelated control. The subject now survives a reload and a logout, and starting a new topic retires it.",
                        "Fixed the Assistant asking a question it could not accept an answer to. When a request matched several controls it listed them numbered, but replying \"2\" fell through to \"I'm not sure which MSUF request you mean yet\". A numbered reply now works in that list, entries sharing a name carry the page that tells them apart, and where no list can be offered the answer says so and suggests a phrasing that names one control.",
                        "Fixed color requests being refused for colors whose setting name does not contain the word \"color\". Castbar text, the unified bar, the class resource ramp, the group frame font and the targeted-spells text were each published as three unrelated numbers, so asking for one of them got a \"no reviewed range\" refusal instead of a pointer to the color picker. A color is now recognised from its red, green and blue parts existing together, which no naming convention can defeat.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta32",
            date = "2026-07-27",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "The GCD bar is back, rebuilt for 12.1. When an instant spell triggers the global cooldown, the Player castbar runs a short bar for it, carrying that spell's name and icon and the remaining time. The old version approximated the cooldown from a fixed base value; this one asks the client for the real, haste-scaled window, so the bar ends when you can actually cast again. Fill and time text are driven natively by the client, so nothing ticks per frame while the bar runs, and while the feature is switched off MSUF does not even listen for the event. A real cast, channel, or empowered cast always owns the castbar and is never pushed aside by the GCD. The feature is off by default and lives in a new \"GCD Bar\" section on the Cast Bars page, with separate toggles for the time text and for the spell name and icon.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "The debuff blacklist is now fully preset-driven. Three curated preset groups joined the list - Challenge/Instance Debuffs (Challenger's Burden and other instance-wide timers), Class/Utility Auras (Stagger and similar class debuffs), and Skyriding/Ride Along Auras - and Sated/Exhaustion now also covers the Evoker's Fury of the Aspects lockout. The spell sets are shared with EnhanceQoL's daily-verified never-secret list, with thanks to R41z0r.",
                        "The free-form \"Spell ID, link, or name\" entry was removed from the Debuff blacklists on unit and group frames. Debuff data is secret at runtime on 12.x clients, so a hand-typed spell ID could never match anything outside the curated never-secret sets; the presets above are now the way to build the debuff list, and existing entries keep working. Buff blacklists are unchanged and keep their free-form entry.",
                        "The \"Reset All\" button in the options toolbar is now called \"Reset page\", and it carries a tooltip naming the page it will reset. It never touched anything but the page you were looking at; only the label suggested otherwise.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed custom raid target marker icons and status icon packs never reaching the marker. On 12.x, drawing a default marker slices whichever texture the region is holding at that moment, so once a custom icon or an icon pack had been placed there, the marker could show a cut-out piece of that artwork instead, and switching back to the custom icon afterwards could be skipped altogether. The marker now restores the stock marker sheet before slicing and clears its cached coordinates, and a custom icon is used even on frames whose marker index the client keeps hidden.",
                        "Fixed MSUF blocking Blizzard's protected slash commands. The options loader and the Assistant's coverage command each wrote to the shared slash command table while loading, which marks that table as addon-owned; because the client re-reads it for every slash command, protected ones such as /pvp then failed with an \"action blocked\" error. Neither module writes that global in the game any more.",
                        "Fixed the Cast Bars page leaving its demo cast running on the real castbar when the options window was closed straight from that page.",
                    },
                },
            },
        },
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
                        "The shipped default profile has been re-captured against the full 6.0 settings surface, so a fresh install now starts with a considered opinion on the portrait, aura, castbar, and group-frame controls added during this cycle instead of falling back to per-key defaults for them. Existing profiles are untouched; this only applies the first time MSUF sets itself up.",
                        "\"Bar mode\" on the Global Colors page is now a single segmented row. The four mode cards and the dropdown that repeated the same choice have become one control, which is also the control search and the Assistant address, so the visible widget and the automated one can no longer drift apart. The per-mode tooltips moved onto the segments and the section is more compact.",
                        "The MSUF Assistant dashboard card no longer carries the red \"Early Alpha\" tag.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed the % sign disappearing from health text on some frames. Each slot's \"Hide % sign\" setting could leak from the Right slot onto the Left and Center ones, so a frame showing its percentage in the center - the shipped default for the target frame - hid the symbol even with its own toggle off. The player frame shows its percentage in the Right slot and was never affected, which is why it looked like a target-only problem. The per-slot absorb icon leaked the same way, and a per-slot \"show the % sign\" is no longer overruled by the global setting.",
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
