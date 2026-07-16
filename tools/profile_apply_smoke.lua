_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then
        handle:close()
        return true
    end
    return false
end

local path = "MidnightSimpleUnitFrames/State/MSUF_Profiles.lua"
if not exists(path) then path = "State/MSUF_Profiles.lua" end

local applyCalls = 0
local notifyCalls = 0
local ensureCalls = {}
local combat = false
local deferFrame
local MSUF = {
    Public = {},
    UF = {
        Apply = function()
            applyCalls = applyCalls + 1
        end,
    },
}

function MSUF.ExportPublic(name, value)
    _G[name] = value
    MSUF.Public[name] = value
    return value
end

local function copyTable(source)
    local out = {}
    for key, value in pairs(source or {}) do
        out[key] = type(value) == "table" and copyTable(value) or value
    end
    return out
end

_G.MSUF_NS = MSUF
_G.MSUF = MSUF
_G.CopyTable = copyTable
_G.loadstring = function()
    error("profile import must never compile user-controlled text")
end
_G.UnitName = function() return "Tester" end
_G.GetRealmName = function() return "Realm" end
_G.InCombatLockdown = function() return combat end
_G.MSUF_EnsureDB = function(force, allowPersistedFastPath, temporaryProfile)
    ensureCalls[#ensureCalls + 1] = {
        force = force == true,
        allowPersistedFastPath = allowPersistedFastPath == true,
        temporaryProfile = temporaryProfile == true,
    }
    _G.MSUF_DB.general = _G.MSUF_DB.general or {}
end
local function notifyConfigChanged()
    notifyCalls = notifyCalls + 1
    MSUF.UF.Apply(nil)
    return true
end
_G.MSUF_UFCore_NotifyConfigChanged = notifyConfigChanged
_G.CreateFrame = function()
    deferFrame = { events = {}, scripts = {} }
    function deferFrame:RegisterEvent(event) self.events[event] = true end
    function deferFrame:UnregisterEvent(event) self.events[event] = nil end
    function deferFrame:SetScript(kind, script) self.scripts[kind] = script end
    return deferFrame
end

_G.MSUF_GlobalDB = {
    profiles = {
        Default = { general = {} },
        Other = { general = {} },
    },
    char = {
        ["Tester-Realm"] = {
            activeProfile = "Default",
            priorityFrames = {
                pins = { { guid = "PRIVATE-PRIORITY-GUID", name = "PrivatePin-Realm" } },
            },
        },
    },
}
_G.MSUF_ActiveProfile = "Default"
_G.MSUF_DB = _G.MSUF_GlobalDB.profiles.Default

local chunk, err = loadfile(path)
assert(chunk, err)
chunk("MidnightSimpleUnitFrames", MSUF)

local duplicateCreated, duplicateError = _G.MSUF_CreateProfile("Other")
assert(duplicateCreated == false and duplicateError == "profile already exists",
    "duplicate profile create did not report failure")
assert(_G.MSUF_ActiveProfile == "Default", "duplicate profile create changed the active profile")
local created, createError = _G.MSUF_CreateProfile("Temporary")
assert(created == true, tostring(createError or "new profile create failed"))
assert(_G.MSUF_ActiveProfile == "Default", "profile create unexpectedly switched profiles")
_G.MSUF_GlobalDB.char["Second-Realm"] = {
    activeProfile = "Temporary",
    specProfileMap = { [71] = "Temporary", [72] = "Other" },
}
local deleted, deleteError = _G.MSUF_DeleteProfile("Temporary")
assert(deleted == true, tostring(deleteError or "profile delete failed"))
assert(_G.MSUF_GlobalDB.char["Second-Realm"].activeProfile ~= "Temporary",
    "profile delete left a character active-profile reference behind")
assert(_G.MSUF_GlobalDB.char["Second-Realm"].specProfileMap[71] == nil
    and _G.MSUF_GlobalDB.char["Second-Realm"].specProfileMap[72] == "Other",
    "profile delete did not remove only the deleted specialization mapping")

_G.MSUF_SwitchProfile("Other")
assert(applyCalls == 1 and notifyCalls == 1, "profile switch must apply unit frames exactly once")
assert(ensureCalls[#ensureCalls] and ensureCalls[#ensureCalls].allowPersistedFastPath == true,
    "profile switch must allow the validated persisted Defaults fast path")

applyCalls, notifyCalls = 0, 0
_G.MSUF_ResetProfile("Other")
assert(applyCalls == 1 and notifyCalls == 1, "active profile reset must apply unit frames exactly once")

applyCalls, notifyCalls = 0, 0
local imported, importError = _G.MSUF_Profiles_ImportExternal([[
return {
    -- Exercise the legacy serializer grammar without compiling it.
    ["general"] = { parserString = "line\n", parserNumber = -1.5e2 };
    shortenNames = false,
}
]], "Other")
assert(imported == true, tostring(importError or "active profile import failed"))
assert(applyCalls == 1 and notifyCalls == 1, "active profile import must apply unit frames exactly once")
assert(_G.MSUF_GlobalDB.profiles.Other.general.parserString == "line\n"
    and _G.MSUF_GlobalDB.profiles.Other.general.parserNumber == -150,
    "non-executing legacy parser lost supported string/number/table syntax")

_G.MSUF_GlobalDB.profiles.Other.general.importSentinel = "preserved"
local rejected, rejectedError = _G.MSUF_Profiles_ImportExternal(
    "return { general = (function() _G.MSUF_IMPORT_EXECUTED = true; return {} end)() }", "Other")
assert(rejected == false and type(rejectedError) == "string", "executable legacy import was accepted")
assert(_G.MSUF_IMPORT_EXECUTED == nil, "legacy import executed user-controlled code")
assert(_G.MSUF_GlobalDB.profiles.Other.general.importSentinel == "preserved",
    "rejected legacy import mutated the destination profile")
local oversized = "return { general = { value = \"" .. string.rep("x", 8 * 1024 * 1024) .. "\" } }"
local oversizedAccepted = _G.MSUF_Profiles_ImportExternal(oversized, "Other")
assert(oversizedAccepted == false, "oversized legacy import bypassed the encoded-size limit")

local validateImport = assert(MSUF.ProfileIOValidateImportValue)
local cyclic = {}
cyclic.self = cyclic
local cycleValid, cycleError = validateImport(cyclic)
assert(cycleValid == false and type(cycleError) == "string", "cyclic import table passed validation")

applyCalls, notifyCalls = 0, 0
_G.MSUF_UFCore_NotifyConfigChanged = nil
_G.MSUF_SwitchProfile("Default")
assert(applyCalls == 1 and notifyCalls == 0, "profile switch must retain a direct apply fallback")

applyCalls, notifyCalls = 0, 0
_G.MSUF_UFCore_NotifyConfigChanged = notifyConfigChanged
combat = true
_G.MSUF_SwitchProfile("Other")
assert(applyCalls == 0 and notifyCalls == 0, "combat profile switch must defer protected unit-frame apply")
assert(deferFrame and deferFrame.scripts.OnEvent, "combat profile switch must install a regen continuation")

combat = false
deferFrame.scripts.OnEvent(deferFrame, "PLAYER_REGEN_ENABLED")
assert(applyCalls == 1 and notifyCalls == 1, "deferred profile switch must apply unit frames exactly once")

-- Every persisted ordering value must survive both the normal in-game profile
-- string and the stateless external API. Include the override gates because a
-- copied numeric value is ineffective if its scoped override is lost.
local orderingFixture = {
    general = {},
    bars = {
        barOutlineLayer = 18,
        barOutlineStrata = "BACKGROUND",
        classPowerFrameLevelOffset = 16,
        playerHPBarFrameLevelOffset = 17,
    },
    player = {
        nameTextLayer = 11,
        hpTextLayer = 12,
        powerTextLayer = 13,
        detachedPowerBarFrameLevelOffset = 14,
        raidMarkerLayer = 15,
        hlOverride = true,
        barOutlineLayer = 19,
        barOutlineStrata = "DIALOG",
    },
    auras3 = {
        shared = {
            buffLayer = 3,
            debuffLayer = 4,
            buffStrata = "LOW",
            debuffStrata = "HIGH",
        },
        perUnit = {
            player = {
                overrideLayout = true,
                layout = {
                    buffLayer = 5,
                    debuffLayer = 6,
                    buffStrata = "MEDIUM",
                    debuffStrata = "FULLSCREEN",
                },
            },
        },
        customContainers = {
            perUnit = {
                player = {
                    items = {
                        {
                            id = "roundtrip",
                            layer = 7,
                            strata = "HIGH",
                            frame = { type = "border", layer = 8, strata = "DIALOG" },
                        },
                    },
                },
            },
        },
    },
    gf_party = {
        nameTextLayer = 1,
        textLayer = 2,
        powerTextLayer = 3,
        groupNumberLayer = 4,
        ciLayer = 5,
        ciStrata = "LOW",
        dispelOverlayLayer = 6,
        dispelOverlayStrata = "MEDIUM",
        targetedSpellsLayer = 7,
        auras = {
            buff = { layer = 8, strata = "HIGH" },
            debuff = { layer = 9, strata = "DIALOG" },
            externals = { layer = 10, strata = "FULLSCREEN" },
        },
        spellIndicators = {
            layer = 11,
            strata = "TOOLTIP",
            specs = {
                [71] = {
                    [12345] = {
                        layer = 12,
                        strata = "HIGH",
                        frame = { type = "border", layer = 13, strata = "DIALOG" },
                    },
                },
            },
        },
    },
    gf_raid = {
        hlOverride = true,
        barOutlineLayer = 20,
        barOutlineStrata = "HIGH",
    },
    gf_mythicraid = {
        hlOverride = true,
        barOutlineLayer = 20,
        barOutlineStrata = "HIGH",
    },
    gf_priority = {
        enabled = true,
        autoTanks = false,
        maxFrames = 4,
        growth = "RIGHT",
        spacing = 3,
        anchorMode = "FREE",
        point = "CENTER",
        relativePoint = "CENTER",
        offsetX = 144,
        offsetY = -36,
    },
}

local function IsOrderingKey(key)
    if type(key) ~= "string" then return false end
    local lower = key:lower()
    return lower == "layer"
        or (lower:sub(-5) == "layer" and lower:sub(-6) ~= "player")
        or lower:sub(-16) == "frameleveloffset"
        or lower == "strata"
        or lower:sub(-6) == "strata"
        or lower == "hloverride"
        or lower == "overridelayout"
        or lower == "overridesharedlayout"
end

local function CaptureOrdering(root)
    local out = {}
    local function Visit(value, path)
        if type(value) ~= "table" then return end
        for key, child in pairs(value) do
            local childPath = path == "" and tostring(key) or (path .. "." .. tostring(key))
            if type(child) == "table" then
                Visit(child, childPath)
            elseif IsOrderingKey(key) then
                out[childPath] = child
            end
        end
    end
    Visit(root, "")
    return out
end

local function AssertOrderingEqual(expected, actual, label)
    for pathKey, value in pairs(expected) do
        assert(actual[pathKey] == value,
            label .. " lost " .. pathKey .. " (expected " .. tostring(value) .. ", got " .. tostring(actual[pathKey]) .. ")")
    end
end

_G.MSUF_DB = _G.MSUF_GlobalDB.profiles.Other
for key in pairs(_G.MSUF_DB) do _G.MSUF_DB[key] = nil end
for key, value in pairs(orderingFixture) do _G.MSUF_DB[key] = copyTable(value) end
local expectedOrdering = CaptureOrdering(_G.MSUF_DB)

-- Priority layout is profile-owned, while player identities are deliberately
-- character-local and must never enter any profile string.
local priorityString = assert(_G.MSUF_ExportSelectionToString("groupframe"))
assert(priorityString:find("gf_priority", 1, true), "group-frame export omitted Priority settings")
assert(not priorityString:find("PRIVATE-PRIORITY-GUID", 1, true)
    and not priorityString:find("PrivatePin-Realm", 1, true),
    "group-frame export leaked character-local Priority pins")
_G.MSUF_DB.gf_priority.enabled = false
_G.MSUF_DB.gf_priority.offsetX = 0
assert(_G.MSUF_ImportFromString(priorityString) == true, "Priority group-frame round-trip import failed")
assert(_G.MSUF_DB.gf_priority.enabled == true and _G.MSUF_DB.gf_priority.offsetX == 144,
    "Priority profile settings did not round-trip")
local privatePins = _G.MSUF_GlobalDB.char["Tester-Realm"].priorityFrames.pins
assert(#privatePins == 1 and privatePins[1].guid == "PRIVATE-PRIORITY-GUID"
    and privatePins[1].name == "PrivatePin-Realm",
    "Priority profile import replaced character-local pins")

local profileString = assert(_G.MSUF_ExportSelectionToString("all"))
local _, priorityPayloadCount = profileString:gsub("gf_priority =", "")
assert(priorityPayloadCount >= 2,
    "Priority settings missing from the Wago-compatible or embedded full payload")
assert(not profileString:find("PRIVATE-PRIORITY-GUID", 1, true)
    and not profileString:find("PrivatePin-Realm", 1, true),
    "full profile export leaked character-local Priority pins")
local _, compatibleBuffLayerCount = profileString:gsub("buffLayer = 3,", "")
local _, compatibleDebuffLayerCount = profileString:gsub("debuffLayer = 4,", "")
assert(compatibleBuffLayerCount >= 2 and compatibleDebuffLayerCount >= 2,
    "Wago-compatible export payload stripped Unit Aura Layer values")

local activeProfileRef = _G.MSUF_DB
_G.MSUF_DB.auras3.shared.buffLayer = 30
_G.MSUF_DB.gf_party.spellIndicators.layer = 30
assert(_G.MSUF_ImportFromString(profileString) == true, "normal profile ordering round-trip import failed")
assert(_G.MSUF_DB == activeProfileRef, "normal profile ordering round-trip replaced the active profile table")
assert(_G.MSUF_DB.gf_priority.enabled == true
    and _G.MSUF_DB.gf_priority.autoTanks == false
    and _G.MSUF_DB.gf_priority.maxFrames == 4
    and _G.MSUF_DB.gf_priority.anchorMode == "FREE"
    and _G.MSUF_DB.gf_priority.offsetX == 144,
    "Priority settings did not survive all-profile round trip")
privatePins = _G.MSUF_GlobalDB.char["Tester-Realm"].priorityFrames.pins
assert(#privatePins == 1 and privatePins[1].guid == "PRIVATE-PRIORITY-GUID"
    and privatePins[1].name == "PrivatePin-Realm",
    "all-profile import replaced character-local Priority pins")
AssertOrderingEqual(expectedOrdering, CaptureOrdering(_G.MSUF_DB), "normal profile ordering round-trip")

local externalOK, externalString = _G.MSUF_Profiles_ExportExternal("Other")
assert(externalOK == true and type(externalString) == "string", "external ordering export failed")
local importedExternal, externalError = _G.MSUF_Profiles_ImportExternal(externalString, "Default")
assert(importedExternal == true, tostring(externalError or "external ordering import failed"))
AssertOrderingEqual(expectedOrdering, CaptureOrdering(_G.MSUF_GlobalDB.profiles.Default),
    "external profile ordering round-trip")

local compatibilityOnly = [[
return {
    addon = "MSUF",
    fmt = 2,
    schema = 1,
    kind = "all",
    payload = {
        auras2 = {
            shared = {
                buffLayer = 21,
                debuffLayer = 22,
                buffStrata = "LOW",
                debuffStrata = "HIGH",
            },
            perUnit = {
                player = {
                    layout = {
                        buffLayer = 23,
                        debuffLayer = 24,
                        buffStrata = "MEDIUM",
                        debuffStrata = "DIALOG",
                    },
                },
            },
        },
    },
}
]]
local compatibilityImported, compatibilityError = _G.MSUF_Profiles_ImportExternal(compatibilityOnly, "Default")
assert(compatibilityImported == true, tostring(compatibilityError or "compatibility-only ordering import failed"))
local compatibilityAuras = assert(_G.MSUF_GlobalDB.profiles.Default.auras3)
assert(compatibilityAuras.shared.buffLayer == 21
    and compatibilityAuras.shared.debuffLayer == 22
    and compatibilityAuras.shared.buffStrata == "LOW"
    and compatibilityAuras.shared.debuffStrata == "HIGH",
    "compatibility-only import lost shared Unit Aura Layer/FrameStrata values")
local compatibilityPlayer = assert(compatibilityAuras.perUnit.player)
assert(compatibilityPlayer.overrideLayout == true
    and compatibilityPlayer.layout.buffLayer == 23
    and compatibilityPlayer.layout.debuffLayer == 24
    and compatibilityPlayer.layout.buffStrata == "MEDIUM"
    and compatibilityPlayer.layout.debuffStrata == "DIALOG",
    "compatibility-only import lost scoped Unit Aura ordering values or its override gate")

local translate = assert(_G.MSUF_ProfileIO_TranslateProfileToCurrent)

-- A current-schema table without the normalization revision is not trusted yet
-- and receives one complete repair before becoming eligible for the fast path.
local malformedStored = {
    _msufProfileSchema = 600,
    general = { nameOffsetX = "900" },
}
local _, firstChanged = translate(malformedStored, {
    source = "smoke_stored",
    markProfile = true,
    trustNormalizationMarker = true,
})
assert(firstChanged == true, "unversioned current profile must be normalized once")
assert(malformedStored.general.nameOffsetX == 500, "stored malformed numeric field was not clamped")
assert(malformedStored._msufProfileNormalizationRevision == 7, "normalization revision was not persisted")

-- The second trusted pass must return before walking the full profile tree.
local nestedWalks = 0
local watchedGeneral = setmetatable({}, {
    __pairs = function()
        nestedWalks = nestedWalks + 1
        return next, {}, nil
    end,
})
local alreadyCurrent = {
    _msufProfileSchema = 600,
    _msufProfileNormalizationRevision = 7,
    general = watchedGeneral,
}
local _, fastChanged = translate(alreadyCurrent, {
    source = "smoke_stored",
    markProfile = true,
    trustNormalizationMarker = true,
})
assert(fastChanged == false, "trusted current profile should use normalization fast path")
assert(nestedWalks == 0, "normalization fast path walked nested profile tables")

-- External payloads never get to assert their own trust markers.
local spoofedImport = {
    _msufProfileSchema = 600,
    _msufProfileNormalizationRevision = 7,
    _msufDefaultsRevision = 1,
    _msufDispelPriorityMigration = 3,
    general = { nameOffsetX = "900" },
}
translate(spoofedImport, { source = "external_import", markProfile = true })
assert(spoofedImport.general.nameOffsetX == 500, "import with copied markers bypassed normalization")
assert(spoofedImport._msufDefaultsRevision == nil, "import retained a spoofable Defaults revision")
assert(spoofedImport._msufDispelPriorityMigration == nil, "import retained a spoofable migration marker")

-- A known legacy signal also defeats the trusted fast path defensively.
local staleLegacy = {
    _msufProfileSchema = 600,
    _msufProfileNormalizationRevision = 1,
    general = {},
    auras2 = { shared = {} },
}
translate(staleLegacy, {
    source = "smoke_stored",
    markProfile = true,
    trustNormalizationMarker = true,
})
assert(staleLegacy.auras2 == nil and type(staleLegacy.auras3) == "table", "legacy signal bypassed repair fast-path guard")

-- Init still ensures the selected active table, but no longer forces a second
-- broad Defaults pass when the persisted revision says it is already current.
_G.MSUF_GlobalDB.profiles.Default = alreadyCurrent
_G.MSUF_DB = alreadyCurrent
ensureCalls = {}
_G.MSUF_InitProfiles()
assert(#ensureCalls == 1
    and ensureCalls[1].force == false
    and ensureCalls[1].allowPersistedFastPath == true,
    "profile init must use the persisted, non-forced EnsureDB fast path")

-- Defaults exposes the dispel migration for imports. Its existing version
-- marker now avoids rebuilding priority arrays on every EnsureDB/login.
_G.PowerBarColor = _G.PowerBarColor or {}
local defaultsPath = path:gsub("MSUF_Profiles%.lua$", "MSUF_Defaults.lua")
local defaultsChunk, defaultsError = loadfile(defaultsPath)
assert(defaultsChunk, defaultsError)
defaultsChunk("MidnightSimpleUnitFrames", MSUF)

local normalizeLayers = assert(_G.MSUF_NormalizeNumericLayers)
local layerFixture = {
    player = {
        nameTextLayer = -4,
        detachedPowerBarFrameLevelOffset = 42,
        showPlayer = 77,
    },
    bars = { classPowerFrameLevelOffset = "12.6" },
    gf_party = {
        spellIndicators = {
            layer = "30.9",
            specs = { [1] = { layer = 4.4, strata = "HIGH" } },
        },
    },
}
assert(normalizeLayers(layerFixture) == true, "addon-wide layer normalization did not report changes")
assert(layerFixture.player.nameTextLayer == 0
    and layerFixture.player.detachedPowerBarFrameLevelOffset == 30
    and layerFixture.bars.classPowerFrameLevelOffset == 13
    and layerFixture.gf_party.spellIndicators.layer == 30
    and layerFixture.gf_party.spellIndicators.specs[1].layer == 4,
    "numeric MSUF layers were not rounded and clamped to 0..30")
assert(layerFixture.player.showPlayer == 77
    and layerFixture.gf_party.spellIndicators.specs[1].strata == "HIGH",
    "layer normalization touched a non-layer or Blizzard FrameStrata field")
assert(normalizeLayers(layerFixture) == false, "layer normalization is not idempotent")

local function currentDefaultsProfile()
    local profile = {
        _msufProfileSchema = 600,
        _msufDefaultsRevision = 5,
        shortenNames = false,
    }
    for _, key in ipairs({
        "general", "classColors", "npcColors", "bars", "gameplay",
        "player", "target", "targettarget", "focustarget", "focus", "pet", "boss",
    }) do
        profile[key] = {}
    end
    profile.general.fontKey = "FRIZQT"
    profile.general.hardKillBlizzardPlayerFrame = true
    profile.bars.barBackgroundAlpha = 90
    profile.gameplay.enableCombatTimer = false
    return profile
end

local currentDefaults = currentDefaultsProfile()
_G.MSUF_DB = currentDefaults
assert(_G.MSUF_EnsureDB(false, true) == currentDefaults, "Defaults fast path did not return the active profile")
assert(currentDefaults.general.anchorName == nil, "persisted Defaults fast path unexpectedly ran the broad fill")

-- Profile switches opt into the persisted marker. Current stored profiles can
-- therefore avoid the broad pass just like login initialization.
local switchedDefaults = currentDefaultsProfile()
_G.MSUF_DB = switchedDefaults
_G.MSUF_EnsureDB(false, true)
assert(switchedDefaults.general.anchorName == nil, "current switched profile unexpectedly ran the broad Defaults fill")

-- A stale revision still falls through to the complete repair path.
local staleDefaults = currentDefaultsProfile()
staleDefaults._msufDefaultsRevision = 0
_G.MSUF_DB = staleDefaults
_G.MSUF_EnsureDB(false, true)
assert(staleDefaults.general.anchorName == "UIParent", "stale switched profile bypassed the Defaults repair")

-- Ensuring an export copy must not evict the live profile from the local cache.
staleDefaults.general.anchorName = nil
_G.MSUF_DB = currentDefaults
_G.MSUF_EnsureDB(false, true, true)
_G.MSUF_DB = staleDefaults
_G.MSUF_EnsureDB()
assert(staleDefaults.general.anchorName == nil, "temporary export ensure evicted the active profile repair cache")

-- Factory provenance markers must never be treated as ownership of values a
-- user may have customized after the profile was seeded.
local customizedFactory = currentDefaultsProfile()
customizedFactory._msufDefaultsRevision = 3
customizedFactory.shortenNames = true
customizedFactory.general._msufFactoryProfileApplied = true
customizedFactory.general._msufModernFactoryProfile_v1 = true
customizedFactory.general.shortenNameMaxChars = 77
customizedFactory.general.shortenNameClipSide = "LEFT"
customizedFactory.general.shortenNameShowDots = true
customizedFactory.target = {
    shortenNames = true,
    shortenNameMaxChars = 91,
    shortenNameClipSide = "CENTER",
    shortenNameShowDots = true,
}
_G.MSUF_DB = customizedFactory
_G.MSUF_EnsureDB(false, true)
assert(customizedFactory.shortenNames == true
    and customizedFactory.general.shortenNameMaxChars == 77
    and customizedFactory.general.shortenNameClipSide == "LEFT"
    and customizedFactory.general.shortenNameShowDots == true
    and customizedFactory.target.shortenNames == true
    and customizedFactory.target.shortenNameMaxChars == 91
    and customizedFactory.target.shortenNameClipSide == "CENTER"
    and customizedFactory.target.shortenNameShowDots == true,
    "factory name migration overwrote customized SavedVariables")
assert(customizedFactory.general._msufModernFactoryNameShortening_v2 == true
    and customizedFactory.general._msufModernFactoryNamePresentation_v1 == true,
    "factory name migration completion markers were not persisted")

local migrateDispel = assert(_G.MSUF_MigrateDispelPriorityProfile)
local migrationProfile = {
    general = {
        hlPrioOrder = { "Magic", "aggro" },
        dispelBorderTrigger = "ANY_DEBUFF",
        unitDispelOverlayTrigger = "ANY_DEBUFF",
    },
    target = { dispelBorderTrigger = "ANY_DEBUFF" },
    gf_raid = { dispelOverlayTrigger = "ANY_DEBUFF" },
}
assert(migrateDispel(migrationProfile) == true, "first dispel migration did not run")
local migratedOrder = migrationProfile.general.hlPrioOrder
assert(migratedOrder[1] == "dispel" and migratedOrder[2] == "aggro", "dispel priorities were not normalized")
assert(migrationProfile.general.dispelBorderTrigger == "DISPEL_TYPE"
    and migrationProfile.general.unitDispelOverlayTrigger == "DISPEL_TYPE"
    and migrationProfile.target.dispelBorderTrigger == "DISPEL_TYPE"
    and migrationProfile.gf_raid.dispelOverlayTrigger == "DISPEL_TYPE",
    "legacy Any Debuff trigger values were not migrated to Any Dispel Type")
assert(migrateDispel(migrationProfile) == false, "completed dispel migration ran again")
assert(migrationProfile.general.hlPrioOrder == migratedOrder, "completed migration rebuilt its priority table")
assert(migrateDispel(migrationProfile, true) == true, "forced import migration did not run")
assert(migrationProfile.general.hlPrioOrder ~= migratedOrder, "forced import migration did not rebuild validation output")

io.write("profile_apply_smoke: ok\n")
