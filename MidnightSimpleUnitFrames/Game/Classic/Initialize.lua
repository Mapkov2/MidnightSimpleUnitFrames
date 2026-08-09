--- Classic-only local API adapters.
---
--- This file is absent from Mainline's TOC/load graph. Never add or replace
--- fields on Blizzard's global C_* namespace tables here: even assigning the
--- already-existing function gives the field MSUF taint and can later turn a
--- hardware ActionButton click into ADDON_ACTION_FORBIDDEN at UseAction().

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local Client = MSUF.Client
if not (Client and Client.IsClassic == true) then return end

local type = type
local tonumber = tonumber
local pairs = pairs
local rawget = rawget
local Compat = MSUF.Compat or {}
MSUF.Compat = Compat

-- Classic starts at the native 6.0 profile contract. Profiles without schema
-- 600 are never fed through Retail's 5.x translators: move them out of the
-- active profile roots while SavedVariables are still cold and keep a
-- recoverable archive for manual inspection.
local CURRENT_PROFILE_SCHEMA = 600
local ProfilePolicy = MSUF.ProfilePolicy or {}
MSUF.ProfilePolicy = ProfilePolicy
ProfilePolicy.CurrentSchema = CURRENT_PROFILE_SCHEMA

function ProfilePolicy.AcceptsProfile(profile)
    return type(profile) == "table"
        and tonumber(profile._msufProfileSchema) == CURRENT_PROFILE_SCHEMA
end

local globalDB = rawget(_G, "MSUF_GlobalDB")
local retiredNames
local archivedCount = 0

local function EnsureArchive()
    if type(globalDB) ~= "table" then
        globalDB = {}
        _G.MSUF_GlobalDB = globalDB
    end
    if type(globalDB.classicIgnoredLegacyProfiles) ~= "table" then
        globalDB.classicIgnoredLegacyProfiles = {}
    end
    return globalDB.classicIgnoredLegacyProfiles
end

if type(globalDB) == "table" and type(globalDB.profiles) == "table" then
    for name, profile in pairs(globalDB.profiles) do
        if not ProfilePolicy.AcceptsProfile(profile) then
            local archive = EnsureArchive()
            if archive[name] == nil then
                archive[name] = profile
            end
            globalDB.profiles[name] = nil
            retiredNames = retiredNames or {}
            retiredNames[name] = true
            archivedCount = archivedCount + 1
        end
    end
end

local standalone = rawget(_G, "MSUF_DB")
if standalone ~= nil and not ProfilePolicy.AcceptsProfile(standalone) then
    local archive = EnsureArchive()
    if archive.__standalone == nil then
        archive.__standalone = standalone
    end
    _G.MSUF_DB = nil
    archivedCount = archivedCount + 1
end

if retiredNames and type(globalDB) == "table" then
    if type(globalDB.char) == "table" then
        for _, binding in pairs(globalDB.char) do
            if type(binding) == "table" then
                if retiredNames[binding.activeProfile] then
                    binding.activeProfile = nil
                end
                if type(binding.specProfileMap) == "table" then
                    for specID, profileName in pairs(binding.specProfileMap) do
                        if retiredNames[profileName] then
                            binding.specProfileMap[specID] = nil
                        end
                    end
                end
            end
        end
    end
    if type(globalDB.global) == "table"
        and retiredNames[globalDB.global.defaultProfileForNewChars] then
        globalDB.global.defaultProfileForNewChars = nil
    end
end

ProfilePolicy.ArchivedThisLoad = archivedCount

local nativeAddOns = type(_G.C_AddOns) == "table" and _G.C_AddOns or nil
Compat.AddOns = {
    GetAddOnMetadata = nativeAddOns and nativeAddOns.GetAddOnMetadata or _G.GetAddOnMetadata,
    IsAddOnLoaded = nativeAddOns and nativeAddOns.IsAddOnLoaded or _G.IsAddOnLoaded,
    LoadAddOn = nativeAddOns and nativeAddOns.LoadAddOn or _G.LoadAddOn,
    EnableAddOn = nativeAddOns and nativeAddOns.EnableAddOn or _G.EnableAddOn,
    DisableAddOn = nativeAddOns and nativeAddOns.DisableAddOn or _G.DisableAddOn,
}

local nativeSpell = type(_G.C_Spell) == "table" and _G.C_Spell or nil
local legacyGetSpellInfo = _G.GetSpellInfo
Compat.Spell = {
    GetSpellName = nativeSpell and nativeSpell.GetSpellName or function(identifier)
        return type(legacyGetSpellInfo) == "function" and legacyGetSpellInfo(identifier) or nil
    end,
    GetSpellTexture = nativeSpell and nativeSpell.GetSpellTexture or _G.GetSpellTexture,
    IsSpellInRange = nativeSpell and nativeSpell.IsSpellInRange or _G.IsSpellInRange,
}

local nativeSpellBook = type(_G.C_SpellBook) == "table" and _G.C_SpellBook or nil
Compat.SpellBook = {
    IsSpellKnown = nativeSpellBook and nativeSpellBook.IsSpellKnown or _G.IsSpellKnown,
    IsSpellKnownOrInSpellBook = nativeSpellBook and nativeSpellBook.IsSpellKnownOrInSpellBook or _G.IsSpellKnown,
}
