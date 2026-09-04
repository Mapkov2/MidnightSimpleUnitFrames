-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "F92434FAE6914BABA1734C36E75C3CE639BE696F3949D91175AF9971E4FEB829",
    currentVersion = "6.5-alpha9",
    historyFromVersion = "6.5-alpha6",
    previousVersion = "6.5-alpha8",
    rangeLabel = "6.5-alpha8 -> 6.5-alpha9",
    entries = {
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
        {
            version = "6.5-alpha7",
            date = "2026-09-04",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Aura displays recover instead of remaining disabled when a full refresh exceeds the Lua execution budget.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Retired the complete pre-6.0 profile conversion path and its legacy import controls. Every MSUF 6.x schema-600 profile and the 6.x Wago envelope remain supported; older or unversioned stored profiles are archived instead of being normalized into the active profile list.",
                        "The unified package accepts Retail 12.0.7, 12.1.0 and 12.1.5 while retaining the client-specific Vanilla, TBC and Mists manifests.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Full Aura refreshes batch identity-event topology once and arm their next-frame recovery before synchronous work, so a script ran too long abort cannot leave every later Aura refresh permanently latched as pending.",
                        "Pre-6 profile fallback code no longer runs in current profiles or imports, reducing cold-path work and maintenance surface without changing any supported 6.x profile.",
                    },
                },
            },
        },
        {
            version = "6.5-alpha6",
            date = "2026-09-03",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "The unified package now supports both Retail 12.1.0 and 12.1.5. Retail 12.1.0 keeps the established aura, timer and pixel-layout paths, while Retail 12.1.5 automatically activates the newer native paths when those APIs are present.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Declared both 120100 and 120105 in all three Mainline manifests and restored Retail 12.1.0 to the CurseForge compatibility metadata.",
                        "Added a dedicated Retail 12.1.0 fallback smoke covering keyed delayed scheduling, the unavailable aura-caster tooltip CVar and every newly adopted 12.1.5-only method boundary.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Retail 12.1.0 no longer requires Load out of date AddOns for the Alpha 5 runtime changes.",
                        "The 12.1.0 compatibility path remains event-driven and uses the existing C_Timer.After scheduler fallback without polling; Retail 12.1.5 retains the allocation-saving native TimedSignalMap path.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
