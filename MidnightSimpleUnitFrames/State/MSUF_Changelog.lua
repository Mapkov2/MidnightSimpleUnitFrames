-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "74A3D86382112210F00843DF59B4C625D8B2EC97128A01B036C95D26489DD66E",
    currentVersion = "6.12-beta3",
    historyFromVersion = "6.11",
    previousVersion = "6.12-beta2",
    rangeLabel = "6.12-beta2 -> 6.12-beta3",
    entries = {
        {
            version = "6.12-beta3",
            date = "2026-08-23",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Subtlety Rogues can now highlight Shadow Techniques at five or more stacks. The opt-in native Cooldown Viewer glow supports configurable color, size, and strength while keeping the protected stack comparison inside Blizzard's formatter.",
                            link = {
                                pageKey = "gameplay",
                                query = "shadow techniques stack glow",
                                label = "Shadow Techniques: 5+ Stack Glow",
                                sectionId = "gameplay_dev_auras",
                                controlId = "menu2.gameplay.advanced.dev.aura.shadow.techniques.stack.highlight.enabled",
                                settingKey = "gameplay.enableShadowTechniquesStackHighlight",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Preserve Raid Groups now creates a separate secure header for each physical raid subgroup, keeping subgroup blocks intact while retaining the selected Index, Name, or Role sorting inside each group.",
                        "Group Frame scanning, Edit Mode bounds, visibility, and runtime layout handling now cover every active preserved subgroup header.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Custom Boss Range Fade rates now show a once-per-menu-session performance warning, use a wider value field, and visually distinguish continuous custom rates from the adaptive Standard mode.",
                        "Group Adapter header scans retain the single-header fallback used by isolated and legacy load paths.",
                    },
                },
            },
        },
        {
            version = "6.12-beta2",
            date = "2026-08-22",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Subtlety Rogues can now enable an APEX IT combat cue. The opt-in Deathstalker helper shows at five or more Shadow Techniques stacks while Darkest Night is active and Ancient Arts is not, with configurable text size, position, and an in-menu preview.",
                            link = {
                                pageKey = "gameplay",
                                query = "subtlety rogue apex it",
                                label = "Subtlety Rogue: APEX IT",
                                sectionId = "gameplay_dev_auras",
                                controlId = "menu2.gameplay.advanced.dev.aura.apex.it.enabled",
                                settingKey = "gameplay.enableApexItDevAura",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "APEX IT follows Blizzard's native Cooldown Viewer and AuraContainer state updates without polling, fails closed for secret spell values, and disables its event routes outside the supported specialization and talent.",
                        "Preserve Raid Groups now derives the effective group-aware sorting mode without overwriting the selected Index, Name, or Role preference.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Boss encounter lifecycle bursts now coalesce Unit Frame identity, AuraContainer identity, and Range Fade reconciliation into next-frame refreshes instead of repeating synchronous work for every Boss token.",
                        "Group threat-role changes now refresh only the affected border and corner-indicator domains rather than invalidating unrelated Group Frame configuration.",
                        "Rounded native dispel-overlay masks are fully configured before Blizzard takes ownership and are recreated through the cold Auras3 refresh path after rounded-frame setting or media changes.",
                        "The global Castbar preview canvas is taller so below-bar text, thick outlines, and vertical icon offsets are no longer clipped.",
                        "Gameplay configuration caching now follows the active profile table, and a failed gameplay apply can no longer leave later apply requests permanently blocked.",
                    },
                },
            },
        },
        {
            version = "6.12-beta1",
            date = "2026-08-22",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
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
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Added Automatic, Current, Maximum, and Current / Maximum formats for the central Class Resource value. Rune timers, Ebon Might duration, and the Ironfur stack counter retain their native formats.",
                        "Class Resource previews mirror the selected text mode, and the Assistant can find and set both the resource-text format and the Boss range-update rate.",
                        "Retired unused legacy Class Resource text-format fields from existing profiles and generated fallback metadata.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "One-icon aura lanes now use Blizzard's one-frame AuraSlot primitive instead of allocating a ten-frame AuraGroup pool; weapon-enchant and custom-priority lanes keep their specialized group behavior.",
                        "Aura identity-event topology changes are batched across secure Group Frame header scans, resolved aura-name registrations survive unchanged layout refreshes, and redundant native full-aura refreshes were removed.",
                        "Target name and health text now resolve protected PvP class tokens through Blizzard's native class-color object without comparing or caching secret-backed RGB values.",
                        "Standard Boss Range Fade retains its adaptive 0.75/2-second checks, while a custom rate accelerates only visible Boss Frames and shares the existing timer scheduler.",
                        "See New Features now reports the correct compact and full-history version ranges for 6.11.",
                    },
                },
            },
        },
        {
            version = "6.11",
            date = "2026-08-21",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Expanded Buff Tracking is back for Custom 1-3 aura containers. Every whitelisted spell keeps a fixed slot, missing buffs show as dimmed placeholders, and the same slots can securely cast spells or use bound items when clicked.",
                            link = {
                                pageKey = "uf_player",
                                query = "buff reminder fixed slots",
                                label = "Buff Reminder",
                                sectionId = "auras",
                                controlId = "menu2.uf_player.auras.unit-workspace.container-selector",
                                settingKey = "auras3.player.custom1.placed.reminderEnabled",
                                prepareKind = "unitAuraWorkspace",
                                prepareValue = "custom1_reminder",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Buff Reminder accepts Spell IDs, spell links, item links, and separate tracked-spell/item-action pairs. Player reminders can also track Main Hand and Off Hand temporary enchants, filter out spells the current character cannot apply, and pin shared consumables with Always show.",
                        "Main Hand and Off Hand enchant reminders now show their remaining time and a shaped cooldown swipe. A configurable 5-240 minute duration keeps the swipe proportional after login or reload, while the native duration binding updates without polling.",
                        "Reminder slots follow whitelist order, preserve their positions as auras appear or expire, and keep their secure click bindings fixed outside combat without polling or recurring aura reads.",
                        "Localized the complete Buff Reminder setup, whitelist actions, weapon-enchant controls, status text, and tooltips across all 12 supported locales.",
                        "The Assistant can now execute explicit multi-control requests clause by clause, including comma-separated and shared-scope commands, while continuing to fail closed for questions, planning requests, incomplete values, and ambiguous fragments.",
                        "Menu pages, accordion sections, and Back/Forward navigation now switch immediately without transition fades or a recurring discovery pulse.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Friendly Target Range Fade becoming inaccurate in instanced combat when Blizzard temporarily stops returning a fresh range result. MSUF now keeps the last authoritative result until a native range event or a real target change supplies a replacement, without adding polling, timers, or an open-world fallback path.",
                        "Castbars reuse unchanged manager topology and boss-frame geometry validation, resolve cast activity once per update, and share the player's plain interrupt-cooldown status across same-frame Target, Focus, and Boss refreshes.",
                        "Player-first role-sorted Party Frames now wait for a complete Arena roster before publishing their secure name list and refresh on Arena match-state and unit-name transitions; the additional listeners remain disabled in PvE.",
                        "The Assistant no longer mistakes player-count ranges inside Group Frame scale labels (such as 1-10 Players) for a requested value when none was supplied.",
                        "Fixed Elemental Shamans seeing Maelstrom on both resource bars. While Maelstrom owns the Class Resource row, the Player power bar now consistently displays Mana across fill, current value, maximum, percentage, text color, and event filtering; disabling that row or entering a vehicle restores the primary resource.",
                        "Applied the same resource-ownership transition to Shadow Priest Mana/Insanity and cleared both overrides when the Class Resource module shuts down.",
                        "Made third-party cooldown-viewer and external-frame anchoring safe when 12.1 returns protected geometry. MSUF validates foreign frames once, shares one stable proxy between Unit Frames, and freezes that proxy at the combat edge instead of repeatedly touching every consumer.",
                        "Boss castbars now prewarm at most one hidden bar per rendered frame when an encounter starts, avoiding one large synchronous layout burst while retaining authoritative validation when a real cast begins.",
                        "Aura-name fallback scans are coalesced to one frame and permanently retire each resolved alias until the container configuration changes, removing repeated name lookups from unrelated full aura updates.",
                        "Aura menu search now opens the Filters tool correctly for Player Defensives and Target Dots instead of falling back to Setup.",
                        "Rounded Unit Frames no longer read the protected parent of Blizzard-owned dispel-overlay textures; the safe owner is captured before the region becomes forbidden and reused when masks are applied.",
                        "Group Frame previews keep their generated character names when ordinary player-unit events refresh the dummy frames outside Edit Mode.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
