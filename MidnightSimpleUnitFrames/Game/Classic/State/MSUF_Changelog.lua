-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "8CF8E561840ADBDDAC76B482D3D048C3B53E121333FA25FE50F4AC0340CC5AD3",
    currentVersion = "6.5-alpha11",
    historyFromVersion = "6.5-alpha8",
    previousVersion = "6.5-alpha10",
    rangeLabel = "6.5-alpha10 -> 6.5-alpha11",
    entries = {
        {
            version = "6.5-alpha11",
            date = "2026-09-05",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Busy group combat now spends less time updating health gradients, dynamic backgrounds, protected text, Aura fallback state, and Range Fade timers. Existing colors, status transitions, unresolved-Aura discovery, and range sampling behavior are preserved.",
                            link = {
                                pageKey = "opt_colors",
                                query = "health gradient",
                                label = "Health Gradient",
                                sectionId = "colors_appearance",
                                controlId = "menu2.opt.colors.advanced.appearance.gradient.enabled",
                                settingKey = "general.enableHealthGradient",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Synchronized the complete Retail 6.15-beta7 performance set into the unified Alpha package.",
                        "The Mainline flavor keeps its Retail 12.1.5 native Aura, scheduler, tooltip-caster, and pixel-rounding paths. Arena Frames and the Vanilla 1.15.9, TBC 2.5.6, and Mists 5.5.4 flavors remain included.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Health gradients reuse bounded native scalar curves for their RGB channels, avoid per-update ColorMixin allocation, and keep constant channels out of the native evaluation path.",
                        "Group health updates avoid a repeated dynamic-background refresh and an empty color handoff after the background has already been painted.",
                        "Dynamic health backgrounds cache stable alpha inputs and known cache keys, use the native secret-value predicate when available, and forward protected colors directly to their supported rendering sink.",
                        "Protected current, maximum, and percentage text modes use compiled single-value writers instead of the general multi-value formatter.",
                        "Unresolved Aura fallback scans avoid resynchronizing an unchanged active-work state while later discovery, owner reactivation, and unregister cleanup remain intact.",
                        "Group death-background updates skip cache probes that cannot be reused outside an active frame dispatch while retaining fresh native death and resurrection checks.",
                        "Range Fade keeps an earlier timer when its logical deadline moves later, reducing timer replacement churn without moving range checks or alpha changes forward.",
                    },
                },
            },
        },
        {
            version = "6.5-alpha10",
            date = "2026-09-04",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Absorbs and heal prediction can now stay visible when the health bar is faded into the background. Enable Keep Absorbs + Prediction Visible per Unit Frame or for Party and Raid Frames to keep these overlays at full opacity independently from the health fill.",
                            link = {
                                pageKey = "uf_player",
                                query = "keep absorbs prediction visible",
                                label = "Keep Absorbs + Prediction Visible",
                                sectionId = "transparency",
                                controlId = "menu2.uf_player.unit.transparency.alpha_exclude_prediction_bars",
                                settingKey = "player.alphaExcludePredictionBars",
                            },
                        },
                        {
                            text = "Raid and Mythic Raid role sorting can now span the entire raid. Enable Sort roles across entire raid under Group Layout > Sorting to order tanks, healers, and damage dealers across the whole raid instead of within each raid group.",
                            link = {
                                pageKey = "gf_layout",
                                query = "sort roles across entire raid",
                                label = "Sort roles across entire raid",
                                sectionId = "sorting",
                                controlId = "menu2.gf_layout.group.field.sortrolesacrossraid",
                                settingKey = "gf_raid.sortRolesAcrossRaid",
                                prepareKind = "groupScope",
                                prepareValue = "raid",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Synchronized the complete Retail 6.15-beta6 feature and fix set into the unified Alpha package.",
                        "Added Keep Absorbs + Prediction Visible to Unit Frames and Party/Raid Frames, including profile copy, defaults, previews, search, and Assistant support.",
                        "Added Sort roles across entire raid for Raid and Mythic Raid Frames, including defaults, profile copy, locales, search, and Assistant support. Party sorting remains unchanged.",
                        "The Boss Preview now displays incoming heals, absorbs, heal absorbs, and absorb text so prediction settings can be reviewed without a live boss.",
                        "The Assistant now resolves requests about a specific Unit Frame and its opacity, visibility, movement, portrait, texture, and text controls more precisely.",
                        "Retired pre-6.0 profile conversion and import controls while preserving every supported MSUF 6.x profile and Wago import.",
                        "The Mainline flavor retains its Retail 12.1.5 native Aura, scheduler, tooltip-caster, and pixel-rounding paths. Arena Frames and the Vanilla 1.15.9, TBC 2.5.6, and Mists 5.5.4 client flavors remain included.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Health gradients, texture changes, prediction refreshes, Group Range Fade, and the Boss Preview preserve the configured health and prediction opacity.",
                        "Detached Player Power bars attached or width-synced to Class Resources keep their controller-managed anchor while the Class Resource bar is hidden.",
                        "Aura owners that cannot be visible stop parsing UNIT_AURA; registration and unresolved-name work resume when the owner becomes eligible again.",
                        "Cleanse and Purge borders share the Frame Outline layer, Unit Frame dispel borders follow Blizzard's assist rules, and exact-ID Group Aura ownership remains intact.",
                        "Group Frame dead and offline backgrounds follow secret health updates, and preserved raid groups build and sort from one authoritative roster snapshot per secure-header setup.",
                        "Interrupted full Aura refreshes arm recovery before synchronous work, retain the Retail 12.1.5 native contracts, and no longer leave later refreshes pending.",
                        "Class Resource previews can schedule refreshes again after Menu lifecycle cancellation.",
                    },
                },
            },
        },
        {
            version = "6.5-alpha9",
            date = "2026-09-04",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "The unified Alpha now carries the current Retail 12.1.5 Aura path. Its Mainline flavor keeps the newer native Aura contracts while the Vanilla, TBC and Mists flavors retain their client-owned fallbacks.",
                            link = {
                                pageKey = "uf_player",
                                query = "player buff aura layout visible",
                                label = "Player Auras",
                                sectionId = "auras",
                                controlId = "menu2.uf_player.auras.unit-workspace.container-selector",
                                settingKey = "auras3.player.buff.visible",
                                prepareKind = "unitAuraWorkspace",
                                prepareValue = "buff_layout",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "CurseForge now presents this Alpha for Retail 12.1.5 together with Vanilla 1.15.9, TBC 2.5.6 and Mists 5.5.4; Retail 12.1.0 remains on the separate Beta track.",
                        "Synchronized the current Class Resource preview-recovery fix while retaining the client-owned resource implementations for Vanilla, TBC and Mists.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Native Aura hook recovery stays inside the factory-owned runtime, preserving the 12.1 contract floor without reintroducing the missing-global Aura failure.",
                        "Class Resource previews reacquire their current controls after a Menu rebuild, so preview movement continues to work after settings change.",
                        "Extended the Aura and Menu interaction smokes for the synchronized Retail paths.",
                    },
                },
            },
        },
        {
            version = "6.5-alpha8",
            date = "2026-09-04",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Restored Auras when the unified Alpha is used on Retail. The next-frame recovery callback now closes over the private identity-topology batch state instead of reading a missing Lua global.",
                        "Restored Mists Monk Class Resources after changing settings. Mistweaver and Windwalker Chi can refresh normally again instead of stopping on a missing Retail-only Ebon Might method.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Classic now installs its absent Ebon Might callbacks as one-time no-op contracts during ClassPower initialization, preventing repeated nil checks and keeping the ordinary ClassPower apply path allocation-free.",
                        "Interrupted full Aura refreshes now drain their private topology batch through a scope-owned closure; Lua 5.1 bytecode verification guards against compiling that state as a global again.",
                        "Added regression coverage for Mists Monk Chi resolution and the Classic controller's optional Ebon lifecycle contract.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
