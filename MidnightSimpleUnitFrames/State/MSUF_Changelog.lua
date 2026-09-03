-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "6978A5ED2C27E6C2EC397B4FFCEE55E7721A94A84BB212E9E9C5AE51B772DBE7",
    currentVersion = "6.15-beta3",
    historyFromVersion = "6.14",
    previousVersion = "6.15-beta2",
    rangeLabel = "6.15-beta2 -> 6.15-beta3",
    entries = {
        {
            version = "6.15-beta3",
            date = "2026-09-03",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "The Assistant now understands requests that name one unit frame and then describe the result. \"Show the PvP flag on my target frame\", \"put the portrait on the left of my player frame\" or \"the name on my player frame is too small\" resolve against that frame's own controls instead of the frame's master toggle or a single matching word.",
                            linkless = true,
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Questions about one control of one unit frame are answered with that control - its page, what it does and its current value - instead of a page-level overview. \"Don't show raid markers on my player frame\" is read as a hide command, and \"upwards\"/\"downwards\" now reach the movement lanes.",
                        "Out of range opacity, Texture Layer opacity and Portrait opacity are no longer written to the health bar's opacity.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Aura owners that cannot be visible for the current unit stop parsing every UNIT_AURA update: the native registration is dropped while the owner is ineligible and Blizzard's own reparse restores it, and the spell-name resolver only listens per unit while an active owner still has names to resolve.",
                        "Cleanse and Purge borders draw in the Frame Outline layer band at the Borders highlight detail, so the live border lands exactly where the Cleanse test border draws.",
                        "Unit Frame dispel borders follow Blizzard's own assist check and only appear on units you can dispel; the Purge marker and \"cast by me\" sensors keep their previous behaviour, and exact-ID group aura lanes drop a native owner per unit on 12.1.",
                        "The dead and offline health background now follows secret health values on Group Frames instead of lagging behind the real state.",
                        "Preserved raid groups take one authoritative roster snapshot per header setup instead of one per block, and the number of laid-out blocks follows the roster so a raid using more subgroups than the configured column limit no longer fills a different grid than it draws.",
                    },
                },
            },
        },
        {
            version = "6.15-beta2",
            date = "2026-09-02",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Raid and Mythic Raid role sorting can now span the entire raid. Enable Sort roles across entire raid under Frames > Party/Raid Frames > Layout > Sorting to order tanks, healers, and damage dealers across the whole raid instead of within each raid group, including with Preserve raid groups.",
                            linkless = true,
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added Sort roles across entire raid to Raid and Mythic Raid sorting with defaults, profile copy, locales, search, and Assistant support. By Role with Preserve raid groups and Group + Role follow the raid-wide order; Party is unaffected.",
                        "The Boss Preview now renders incoming heal, absorb, and heal-absorb bars plus the absorb text so prediction settings can be judged without a live boss.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Raid role sorting stays fully out of combat: the raid-wide order is rebuilt only when roles or the roster change outside combat, and Blizzard's secure header applies it natively.",
                        "Tidied the Group Layout Sorting card so the Sort Mode dropdown and its toggles sit evenly inside the card.",
                    },
                },
            },
        },
        {
            version = "6.15-beta1",
            date = "2026-09-01",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Absorbs and heal prediction can now stay visible when Unit Frame health opacity is reduced. Enable Keep Absorbs + Prediction Visible per frame to preserve these overlays independently from the health fill.",
                            link = {
                                pageKey = "uf_player",
                                query = "keep absorbs prediction visible",
                                label = "Keep Absorbs + Prediction Visible",
                                sectionId = "transparency",
                                controlId = "menu2.uf_player.unit.transparency.alpha_exclude_prediction_bars",
                                settingKey = "player.alphaExcludePredictionBars",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added the matching Keep Absorbs + Prediction Visible option for Party and Raid Frames, including profile copy, defaults, previews, search, and Assistant support.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Health gradients, texture changes, prediction refreshes, Group Range Fade, and the Boss Preview now preserve the configured health and prediction opacity instead of resetting fills to full opacity.",
                        "Detached Player Power bars attached or width-synced to Class Resources keep using the controller-maintained hidden anchor, preventing width or position jumps when shapeshifting hides the visible Class Resource bar.",
                    },
                },
            },
        },
        {
            version = "6.14",
            date = "2026-08-30",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Health-bar backgrounds can now fill the full bar or only missing health. The background can be colored independently with Custom tint, Match health bar, Class color, or Health gradient, with matching Unit Frame, Group Frame, and preview rendering.",
                            link = {
                                pageKey = "opt_colors",
                                query = "background fill missing health only",
                                label = "Background Fill",
                                sectionId = "colors_background",
                                controlId = "menu2.opt.colors.advanced.background.fill.mode",
                                settingKey = "general.barBgFillMode",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added Full bar and Missing health only background-fill modes plus independent health-background color sources, while migrating existing profiles without changing their current appearance.",
                        "The Assistant now routes Aura content and filter requests to the Unit or Group Frame that owns them, exposes the See New Features destination directly, and presents ambiguous controls with readable menu breadcrumbs instead of internal identifiers.",
                        "Unit Frame tooltips react immediately when their configured modifier key is pressed or released while the frame remains hovered.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Player Castbar interrupt feedback survives the client event order where the cast stops before the interrupted result arrives, without reviving stale casts.",
                        "State Tint controls appear and disappear immediately when their master toggles change instead of requiring the Colors page to be reopened.",
                        "Assistant queues, history, undo, pending choices, workflows, and deferred callbacks are now isolated to the profile that created them, preventing stale work from crossing a profile switch or surviving beyond its conversational context.",
                        "Immediate and deferred Assistant mutations now share the same failure-recovery path so partial work rolls back consistently.",
                        "General Aura guidance no longer competes with frame-local Aura owners, and question-shaped duration-filter requests retain their safe executable choices.",
                        "Aura-name fallback updates skip redundant unit-scan setup when no unresolved additions can benefit from it.",
                        "Opening Unit Frame Power settings no longer errors while building the detached-bar Text on detached bar control.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
