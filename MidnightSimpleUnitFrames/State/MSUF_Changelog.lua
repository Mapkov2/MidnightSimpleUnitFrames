-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-Beta35",
    previousVersion = "6.0-Beta34",
    rangeLabel = "6.0-Beta34 -> 6.0-Beta35",
    entries = {
        {
            version = "6.0-Beta35",
            date = "2026-07-28",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "MSUF can now format every health, power, and resource number the same way on every client language. Blizzard's own abbreviator takes its breakpoints and letters from the game's locale, which inserts a space on some languages (\"123 K\"), uses different letters on others, and moves the decimal around, so the same value could read differently from one client language to the next. A new \"Number abbreviation\" control on the Misc page's Language section - Compact or Game default - switches every text surface (unit frames, group frames, class power) to a fixed, locale-independent breakpoint table (12.3K / 123M / 1.23B), with a live example line so the difference is visible before you commit to it. Game default remains exactly what you had, and CJK languages are left alone on purpose, since their abbreviations are intentionally different and were never the problem. The Assistant can set it too, in English and German (\"use compact numbers\", \"zahlen kuerzen\").",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Cast Bars gained a \"Filtering & Feedback\" section with two new options, both off by default. \"Hide profession casts\" drops crafting and gathering casts before they reach a frame - the profession flag is never a protected value, so this also holds for units whose spell data is restricted in PvP. \"Show cast pushback\" appends the delay a cast has accumulated to its name, for example \"Fireball +0.4\".",
                        "The per-unit \"Power texture\" and \"Power background\" dropdowns are gone from each frame's Visuals page. Power bar art is set once on the Bars page now, and any per-unit override you already had keeps resolving the same way.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed channels no longer draining when a cast reports no duration object, which the client hits often. Every manual bar write had started reading fill direction from the unified-direction setting instead of the cast type, so those channels filled like a cast instead of counting down. Channels now always count down unless \"Always use fill direction for all casts\" is on; casts and empowered casts are unaffected either way, and the native timer and the manual fallback render the same bar.",
                        "Fixed MSUF fighting another unitframe addon over the same frame's parent. The client's frame-hiding accepts a parent that another addon already hid, so MSUF re-asserting its own hidden parent bounced the frame between both addons' hooks until the stack overflowed.",
                        "The \"/rl\" reload shortcut is only claimed while it is still free, instead of unconditionally. It is a shared convenience command, and claiming it outright let load order alone decide which addon's handler answered it.",
                        "\"Sync width to Class Resource\" now follows the class power bar's own show/hide transition. Nothing else was watching for that specific change, so a detached power bar could keep a stale synced width after the bar it was following disappeared.",
                        "A detached power bar's fallback width no longer sticks to its last value after its source is hidden. Resolving the width and refreshing it are now separate steps, so a hidden source clears its cached width instead of keeping the stale number.",
                        "The Group Indicators status-icon preview now highlights whichever of \"Current\" or \"All\" is the active preview mode, matching the unit frame visuals page and its preview helpers.",
                        "Fixed the Dashboard's changelog and support disclosures jumping the whole page back to the top every time you opened or closed one. Auras and Group Auras already restored the reader's scroll position after this kind of rebuild; Dashboard used a plain page reselect that never carried the offset over. All three now share one implementation, so opening a card near the bottom of a long page no longer sends you back to the first line.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta34",
            date = "2026-07-28",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "When the Assistant cannot work out which control you meant, it now hands you the relevant part of the menu instead of a generic list. Asking it to \"change reseted icon\" used to offer \"Show options for the current Group Layout page\" or \"Show general Assistant examples\", neither of which has anything to do with the rested icon. Three separate things caused that: the uncertain branch never consulted the Assistant's own knowledge index, the leading command verb dragged the ranking onto an unrelated page, and the misspelling was never corrected. Typos are now repaired against the words that actually appear in MSUF's control labels, command verbs are stripped before searching, and the match has to clear a relevance floor - below it the Assistant still says it does not know rather than confidently opening the wrong page.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed \"Always use fill direction for all casts\" not applying to channelled casts. Channels kept draining from full to empty, so the one option whose entire purpose is to make every cast move the same way left channels running opposite to everything else. A channel now fills from empty to full in the direction you configured, timed by the client itself, and the classic drain remains the default while the option is off. The spark also stays on the bar's moving edge in both modes instead of sitting on the anchor side, and the Cast Bars page preview shows the same thing the frame does.",
                        "Fixed the aura icon border and drop shadow never showing up in any preview. The Icon Border & Shadow settings reached real frames, but none of the preview surfaces drew them - not the Sample and Live preview on the Auras page, not the unit frame preview in the options window, and not the Edit Mode aura lanes - so there was no way to judge a border style without closing the menu and looking at the frames. All three now draw through the same renderer the live buttons use, including the per-scope opt-out and the lane padding, which the previews had been ignoring as well.",
                        "Fixed the Auras page preview not reacting to an icon border or shadow change. The preview repainted before the queued aura update had run and re-read the previous configuration, so it kept showing the old style until some unrelated interaction happened to refresh it - the reason the frames updated but the preview did not.",
                        "Fixed the \"Preview as\" row and the Sample/Live switch on the Auras page showing no selection at all. Both were built from the plain action button, which draws its selected state exactly like its unselected one, and the selection was never re-stamped on click because switching tabs repaints the preview without rebuilding the page.",
                    },
                },
            },
        },
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
