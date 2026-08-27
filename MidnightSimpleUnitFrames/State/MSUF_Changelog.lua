-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "CF5F9F201767039F3C36FA8E0B588EB720EEF6EBDBA0E88BCEA678D94268C05F",
    currentVersion = "6.13-beta3",
    historyFromVersion = "6.12",
    previousVersion = "6.13-beta2",
    rangeLabel = "6.13-beta2 -> 6.13-beta3",
    entries = {
        {
            version = "6.13-beta3",
            date = "2026-08-27",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Focus Kick can now stay visible beside the Focus castbar. The new option keeps the compact interrupt icon while restoring the matching Focus castbar and its normal cast ownership.",
                            link = {
                                pageKey = "opt_castbar",
                                query = "show castbar with focus kick icon",
                                label = "Show castbar with Focus Kick icon",
                                sectionId = "castbar_focus_kick",
                                controlId = "menu2.opt.castbar.global.focus.kick.focus.kick.show.castbar",
                                settingKey = "general.focusKickShowCastbar",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Party Frames now honor the configured Units per column and Max columns values instead of forcing a single secure column, including combat-safe secure-header growth.",
                        "The Assistant now understands German negative determiners and double negatives, can switch all supported MSUF or Blizzard Unit Frames globally, and retries zero-result setting searches with registered synonyms.",
                        "Explicit Assistant setting searches resolve exact registry aliases, full portrait control labels resolve to their owning controls, and ambiguous read-only questions remain non-mutating.",
                        "Typed HEX colors in the compact color picker now commit on Enter through the same apply path as the visual picker.",
                        "The Group Frame preview roster now includes B3NZII.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Live Party, Raid, and Mythic Group Frame blocks clamp their actual rendered footprint across scale and anchor combinations without rewriting SavedVariables; Edit Mode and previews keep the configured point semantics, and unavailable protected geometry fails closed.",
                        "The Player Resting indicator refreshes when its frame becomes visible after a hidden zoning transition, without adding polling or permanent update work.",
                        "Assistant routing preserves the original request polarity and capability intent across page-context resolution, preventing safe questions from being rewritten into setting changes.",
                        "Read-only Assistant questions now reach their dedicated definition, location, relationship, and diagnostic lanes before broad registry scans, keeping cold responses within the interactive latency budget without polling or background work.",
                        "The Assistant's unloaded-Menu group-copy fallback now mirrors the native copy categories for chunked health and power fills while excluding anchor and migration-only fields.",
                        "Focus Kick castbar state follows the icon lifecycle and clears stale cast ownership when the combined display is disabled.",
                    },
                },
            },
        },
        {
            version = "6.13-beta2",
            date = "2026-08-26",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Range Fade now stays accurate in PvP instances. Group and Unit Frames re-query when the instance context changes, while unchanged polling sets avoid redundant rebuilds.",
                            link = {
                                pageKey = "uf_target",
                                query = "target range fade",
                                label = "Enable Range Fade",
                                sectionId = "range_fade",
                                controlId = "menu2.uf_target.unit.range_fade.enabled",
                                settingKey = "target.rangeFadeEnabled",
                            },
                        },
                        {
                            text = "Focus castbar trackers recover correctly after startup. Focus interrupt and cast ownership is restored when the underlying tracker becomes available after the initial load.",
                            link = {
                                pageKey = "opt_castbar",
                                query = "focus interrupt tracker",
                                label = "Focus interrupt tracker",
                                sectionId = "castbar_focus_kick",
                                controlId = "menu2.opt.castbar.global.focus.kick.enable.focus.kick.icon",
                                settingKey = "general.enableFocusKickIcon",
                            },
                        },
                        {
                            text = "Player Power text keeps the correct current resource identity. Current-value text no longer loses its power type when the live bar source has already been resolved.",
                            link = {
                                pageKey = "classpower",
                                query = "displayed resource",
                                label = "Displayed resource",
                                sectionId = "classpower_detached_power",
                                controlId = "menu2.classpower.advanced.detached.power.layout.resource.source",
                                settingKey = "player.playerPowerSource",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Reissued the 6.13 Beta 1 runtime code as Beta 2 after a local CurseForge client installation was interrupted while a locale file was locked. Only release metadata, the bundled changelog, and release validation changed; this is not an addon code fix.",
                        "Revalidated every Core TOC payload path, Lua 5.1 loadability, and the affected XML manifests before republishing.",
                    },
                },
            },
        },
        {
            version = "6.13-beta1",
            date = "2026-08-26",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Range Fade now stays accurate in PvP instances. Group and Unit Frames re-query when the instance context changes, while unchanged polling sets avoid redundant rebuilds.",
                            link = {
                                pageKey = "uf_target",
                                query = "target range fade",
                                label = "Enable Range Fade",
                                sectionId = "range_fade",
                                controlId = "menu2.uf_target.unit.range_fade.enabled",
                                settingKey = "target.rangeFadeEnabled",
                            },
                        },
                        {
                            text = "Focus castbar trackers recover correctly after startup. Focus interrupt and cast ownership is restored when the underlying tracker becomes available after the initial load.",
                            link = {
                                pageKey = "opt_castbar",
                                query = "focus interrupt tracker",
                                label = "Focus interrupt tracker",
                                sectionId = "castbar_focus_kick",
                                controlId = "menu2.opt.castbar.global.focus.kick.enable.focus.kick.icon",
                                settingKey = "general.enableFocusKickIcon",
                            },
                        },
                        {
                            text = "Player Power text keeps the correct current resource identity. Current-value text no longer loses its power type when the live bar source has already been resolved.",
                            link = {
                                pageKey = "classpower",
                                query = "displayed resource",
                                label = "Displayed resource",
                                sectionId = "classpower_detached_power",
                                controlId = "menu2.classpower.advanced.detached.power.layout.resource.source",
                                settingKey = "player.playerPowerSource",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Expanded Assistant action inputs for enchant-related requests and tightened Aura action routing.",
                        "Exact setting guidance now outranks broader suggestions, while ambiguous control requests fail closed without changing settings.",
                        "Removed the experimental built-in Rogue APEX developer helper and its retired settings, menu controls, Assistant registrations, and generated metadata.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Party-style Arena Group Frames fail open when Blizzard's Arena roster is temporarily incomplete instead of publishing an unusable secure roster.",
                        "Aura-name fallback work is coalesced so repeated unresolved-name events do not trigger duplicate scans in the same frame.",
                        "Heal-prediction stripe updates use a specialized full-health path and avoid redundant overflow work.",
                        "Range drivers reuse unchanged poll sets and keep PvP instance transitions event-driven.",
                    },
                },
            },
        },
        {
            version = "6.12",
            date = "2026-08-23",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Boss Range Fade can now update up to 20 times per second. The new Boss update-rate slider keeps the adaptive standard cadence at zero or continuously checks visible Boss Frames from 1 through 20 updates per second.",
                            link = {
                                pageKey = "uf_boss",
                                query = "boss range update rate",
                                label = "Updates per second",
                                sectionId = "range_fade",
                                controlId = "menu2.uf_boss.unit.range_fade.update_rate",
                                settingKey = "boss.rangeFadeUpdateRate",
                            },
                        },
                        {
                            text = "Class Resources can now keep Player Power Automatic or explicitly display Mana. The new Displayed resource dropdown preserves the existing class/spec behavior in Automatic mode, while Mana keeps the Player power surface on its Mana pool whenever the character has one.",
                            link = {
                                pageKey = "classpower",
                                query = "mana automatic displayed resource",
                                label = "Displayed resource",
                                sectionId = "classpower_detached_power",
                                controlId = "menu2.classpower.advanced.detached.power.layout.resource.source",
                                settingKey = "player.playerPowerSource",
                            },
                        },
                        {
                            text = "Class Resource text can now show Current, Maximum, or Current / Maximum. The new Resource text selector keeps Automatic as the untouched resource-specific default, while explicit modes change only the central resource value.",
                            link = {
                                pageKey = "classpower",
                                query = "class resource text mode",
                                label = "Resource text",
                                sectionId = "classpower_visuals",
                                controlId = "menu2.classpower.advanced.style.text.mode",
                                settingKey = "bars.classPowerTextMode",
                            },
                        },
                        {
                            text = "MiniAuras and MiniCC now work with MSUF Party and Raid Frames again. The event-driven frame provider refreshes only when the authoritative Group Frame registry changes, without polling the roster or frame list.",
                            linkless = true,
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added Automatic, Current, Maximum, and Current / Maximum formats for the central Class Resource value. Rune timers, Ebon Might duration, and the Ironfur stack counter retain their native formats; previews and the Assistant mirror the selected mode.",
                        "The Player Power resource selector is shared between Player Power and Class Resources, follows vehicle-resource handoffs, and is supported by previews, reset/undo history, search, and the Assistant.",
                        "Preserve Raid Groups now creates a separate secure header for each physical raid subgroup, retaining empty subgroup geometry and the selected Index, Name, or Role sorting inside each group. Scanning, Edit Mode bounds, visibility, and runtime layout cover every active subgroup header.",
                        "Retired unused legacy Class Resource text-format fields from existing profiles and generated fallback metadata.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "One-icon aura lanes now use Blizzard's one-frame AuraSlot primitive instead of allocating a ten-frame AuraGroup pool; weapon-enchant and custom-priority lanes keep their specialized group behavior.",
                        "Aura identity-event topology changes are batched across secure Group Frame header scans, resolved aura-name registrations survive unchanged layout refreshes, and redundant native full-aura refreshes were removed.",
                        "Target name and health text now resolve protected PvP class tokens through Blizzard's native class-color object without comparing or caching secret-backed RGB values.",
                        "Standard Boss Range Fade retains its adaptive 0.75/2-second checks, while a custom rate accelerates only visible Boss Frames through the existing scheduler. Custom rates are visually distinguished and show a once-per-menu-session performance warning.",
                        "Boss encounter lifecycle bursts now coalesce Unit Frame identity, AuraContainer identity, and Range Fade reconciliation into next-frame refreshes instead of repeating synchronous work for every Boss token.",
                        "Group threat-role changes refresh only the affected border and corner-indicator domains, and Group Adapter header scans retain their standalone single-header fallback.",
                        "Rounded native dispel-overlay masks are fully configured before Blizzard takes ownership and are recreated through the cold Auras3 refresh path after rounded-frame setting or media changes.",
                        "The global Castbar preview canvas is taller so below-bar text, thick outlines, and vertical icon offsets are no longer clipped.",
                        "The GCD indicator now rejects protected or otherwise non-plain spell IDs before lookup instead of allowing them into Lua table indexing.",
                        "Explicit Player Mana ownership no longer creates a duplicate Alternative Mana bar, survives vehicle and module lifecycle transitions, and keeps live bars, text, colors, Class Resource previews, and Unit Frame previews on the same displayed resource.",
                        "Class Resource, Player HP, Alternative Mana, detached-power width, and power-text controls now refresh their dependent enabled states immediately after changes, resets, undo, or Assistant application.",
                        "Gameplay configuration caching now follows the active profile table, and a failed gameplay apply can no longer leave later apply requests permanently blocked.",
                        "See New Features now reports the correct compact and full-history version ranges for 6.11.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
