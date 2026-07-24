-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-Beta28",
    previousVersion = "6.0-Beta27",
    rangeLabel = "6.0-Beta27 -> 6.0-Beta28",
    entries = {
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
                        "Updated all supported locales for the new aura color, shape outline, and icon border/shadow controls.",
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
                        "Expanded the Core Lua 5.1 suite to 158 passing tests, including new anchor picker scan budget, preview live parity, and page reset cache purge regressions.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta27",
            date = "2026-07-24",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Aura Border Styling",
                        "All features ready for PTR 7",
                        "MSUF 6.0 reached feature complete status",
                    },
                },
            },
        },
        {
            version = "6.0-Beta26",
            date = "2026-07-24",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Expanded the Assistant with more natural explanations, follow-up context, safer scope selection, and stronger move, anchor, color, number, enum, and boolean request handling.",
                        "Reworked Unit Frame and Group Frame runtime paths to share event-owned identity and value state, coalesce text and prediction refreshes, and remove unnecessary idle, range, threat, and lifecycle work.",
                        "Unified 12.1 Group Aura slot ownership for Spell Indicators, dispel visuals, and fixed external icons, including secret-safe party range gating and safer native container reuse.",
                        "Added clearer Group Frame provider controls for MSUF, normal Blizzard ownership, forced Blizzard frames, and fully disabled frames.",
                        "Added an optional \"Show cast spell icon in portrait\" mode that temporarily replaces 2D or class portraits during casts, channels, and empowered spells.",
                        "Added compact top-right three-dot color shortcuts across supported Menu2 cards so their exact scoped colors open directly in the shared color picker.",
                        "Improved Aura styling workflows and live previews across Menu2, Edit Mode, Unit Frames, Group Frames, and custom Aura containers.",
                        "Added a Fill Direction setting per Unit Frame so Health and Power can fill left to right, right to left, bottom to top, or top to bottom.",
                        "Added dedicated Power bar textures with a shared Bars default and a per-unit override, so a power bar no longer has to inherit the frame's bar texture.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Split status text presentation from status icons and migrated existing Unit Frame and Group Frame profile values automatically.",
                        "Made Health, Power, Class Resource, and Alternative Mana smoothing explicit opt-in settings while preserving Quick Setup as an intentional smoothing preset.",
                        "Simplified contextual text editing, added direct Bars/Aura/Text color targets, refined accordion and dashboard visuals, and suppressed redundant shortcuts on the dedicated Colors page.",
                        "Completed Menu2/Edit Mode source coverage for all shipped locales, including the new portrait, provider, status, Aura, and color-picker controls.",
                        "Replaced the per-frame \"Reverse fill direction\" toggle with a single Fill Direction dropdown that combines the fill axis and direction; existing reversed frames keep their setting.",
                        "Added a \"Power textures\" card to every Unit Frame page and matching Power bar texture defaults on the Bars page, with the Class Resource detached texture still taking precedence for a detached Player bar.",
                        "Added the /msufgp group event pulse profiler, which reports how much in-combat group-frame time flows through compiled event routes versus work outside them. It is inert until switched on.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Reduced Castbar first-cast work, duplicate native cleanup, and Auto Width fan-out with per-source dirty routing and reusable geometry state.",
                        "Kept Blizzard's native Target and Focus Castbars untouched unless the frame is explicitly owned by MSUF.",
                        "Reduced duplicate health, power, class-color, NPC-kind, status, prediction, and text reads across hot event paths.",
                        "Coalesced text and prediction rendering, narrowed Group Frame event routing, retired stale unit subscriptions, and cancelled inactive range timers immediately.",
                        "Consolidated compatible Group Aura slots and flowing icons into shared native owners, including secure-header container birth and separate secret-safe Party range gating.",
                        "Compiled lean Health, Power, Prediction, and Threat routes for Group Frames, reusing resolved values directly and skipping consumers that have no visible work.",
                        "Kept suspended secure Group Frame children in a stable inventory so roster rebinds reactivate them without duplicate entries or stale active routing.",
                        "Improved offline Group Frame visibility, status targeting, level/name anchoring, secret-safe absorb handling, and profile migration behavior.",
                        "Fixed the \"Power bar border\" toggle and \"Border thickness\" slider being ignored while the power bar was detached; a detached bar now uses its own unit frame's border in both the flat and rounded skins. The Class Resource \"Power bar outline\" slider keeps its Round/Crystal/Orb edge and is disabled for the Bar shape, and a customized value migrates into the affected unit's border once.",
                        "Fixed detaching the power bar silently repainting it: an unset detached background texture now follows the global bar background instead of borrowing the foreground, and the detached texture overrides no longer leak from Player onto Target, Focus, or Pet.",
                        "Wrote percent-only Group Frame health and power text inline in the same compiled route pass as the bar, skipping the deferred dirty-text ticker for the most common raid text shape.",
                        "Started the timed-aura driver only while an Aura slot actually owns an aura, so empty slots add no shared OnUpdate work.",
                        "Dropped the alternate-power event registrations from Group Frame power bars and gave flat absorb setups a lean writer that only updates values.",
                        "Removed the native health-bar measurement from the per-event prediction layout check by caching it and invalidating on real bar resizes, authoritative refreshes, and applies.",
                        "Expanded the Core Lua 5.1 suite to 155 passing runtime, Menu2, Assistant, Aura, Castbar, Group Frame, smoothing, status, and hotpath regression tests.",
                    },
                },
            },
        },
        {
            version = "6.0-Beta25",
            date = "2026-07-21",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added a customizable Maximum Health Loss overlay for Unit Frames and Group Frames, with texture, loss color, overlay opacity, background opacity, and a live effect preview.",
                        "Replaced the old shadow-strength presets with a scoped Shadow Opacity slider and 1 px / 2 px Shadow Distance controls; existing profile values migrate automatically.",
                        "Added independent Font Size controls for each selected left, center, and right Health/Power text slot, with matching live previews.",
                        "Added real opacity controls for Health and Power backgrounds, including exact live-preview parity and consistent class-colored backgrounds.",
                        "Refined Menu2 with compact reference previews, clearer shared settings layouts, and highlighted open accordion sections.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added compact and expanded preview modes across Unit Frame, Group Frame, Class Resource, and Color Painter workflows.",
                        "Unified repeated settings and color-card layouts for clearer navigation and more consistent controls.",
                        "Improved Group Preview ownership so heavy native previews can be reused safely between Group Frame pages.",
                        "Updated all supported locales for the new font, background, preview, and maximum-health-loss controls.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Reduced Menu2 opening, resizing, search, font-refresh, Color Painter, and preview work through lazy section builds, reusable layouts, cached control metadata, and pooled preview targets.",
                        "Cached normalized search queries, font probes, profile reads, and Aura default seeding without adding idle or combat polling.",
                        "Fixed slider drags so the complete gesture, including the final released value, creates exactly one Undo/Redo step.",
                        "Fixed rounded frame masks on login and kept class-colored backgrounds correct for players, NPCs, pets, bosses, and temporarily missing units.",
                        "Prevented background opacity from being multiplied twice and kept color changes attached to the active imported profile.",
                        "Expanded Lua 5.1 regression coverage for Menu2 cold paths, preview lifecycles, text-slot sizing, opacity, history, Auras, and rounded-frame startup.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
