--- MSUF profile schema policy and pre-6 profile archival.
---
--- This file intentionally loads before any code that normalizes the SavedVariables.
--- Raw SavedVariable presence is the only reliable way to distinguish a clean install
--- from an upgrade without touching the active profile.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = _G.MSUF or MSUF

local _G = _G
local type, pairs = type, pairs
local CURRENT_PROFILE_SCHEMA = 600
local ProfilePolicy = MSUF.ProfilePolicy or {}
MSUF.ProfilePolicy = ProfilePolicy
ProfilePolicy.CurrentSchema = CURRENT_PROFILE_SCHEMA

function ProfilePolicy.AcceptsProfile(profile)
    return type(profile) == "table"
        and tonumber(profile._msufProfileSchema) == CURRENT_PROFILE_SCHEMA
end

local function HasCurrentSnapshotData(snapshot)
    return type(snapshot) == "table"
        and tonumber(snapshot.schema) == CURRENT_PROFILE_SCHEMA
        and type(snapshot.kind) == "string"
        and type(snapshot.payload) == "table"
end

function ProfilePolicy.AcceptsSnapshot(snapshot)
    return HasCurrentSnapshotData(snapshot)
        and snapshot.addon == "MSUF"
        and tonumber(snapshot.fmt) == 2
end

function ProfilePolicy.SelectSupportedDecodedProfile(decoded)
    if ProfilePolicy.AcceptsProfile(decoded) or ProfilePolicy.AcceptsSnapshot(decoded) then
        return decoded
    end
    -- Wago's portable schema-1 envelope was introduced during the 6.x line.
    -- Prefer its lossless schema-600 snapshot when present, while retaining
    -- portable-only 6.x exports. An invalid embedded snapshot fails closed.
    if type(decoded) == "table"
        and decoded.addon == "MSUF"
        and tonumber(decoded.fmt) == 2
        and tonumber(decoded.schema) == 1
        and type(decoded.kind) == "string"
        and type(decoded.payload) == "table" then
        local full = decoded.msuf6
        if full == nil then return decoded end
        if HasCurrentSnapshotData(full) then
            return {
                addon = "MSUF",
                fmt = 2,
                schema = full.schema,
                kind = full.kind,
                profile = type(full.profile) == "string" and full.profile or decoded.profile,
                payload = full.payload,
            }
        end
    end
    return nil
end
-- Capture the SavedVariables before Defaults can create or migrate them.
local rawProfileDB = rawget(_G, "MSUF_DB")
local rawGlobalDB = rawget(_G, "MSUF_GlobalDB")
local hadSavedState = rawProfileDB ~= nil or rawGlobalDB ~= nil

local globalDB = rawget(_G, "MSUF_GlobalDB")
if type(globalDB) ~= "table" then
    globalDB = {}
    _G.MSUF_GlobalDB = globalDB
end
if type(globalDB.global) ~= "table" then
    globalDB.global = {}
end

-- Schema 600 is the profile contract for every MSUF 6.x release. Archive old
-- or unversioned profiles before Defaults/Profiles can normalize them.
local retiredNames
local archivedCount = 0
local function EnsurePre6Archive()
    if type(globalDB.ignoredPre6Profiles) ~= "table" then
        globalDB.ignoredPre6Profiles = {}
    end
    return globalDB.ignoredPre6Profiles
end
if type(globalDB.profiles) == "table" then
    for name, profile in pairs(globalDB.profiles) do
        if not ProfilePolicy.AcceptsProfile(profile) then
            local archive = EnsurePre6Archive()
            if archive[name] == nil then archive[name] = profile end
            globalDB.profiles[name] = nil
            retiredNames = retiredNames or {}
            retiredNames[name] = true
            archivedCount = archivedCount + 1
        end
    end
end
if rawProfileDB ~= nil and not ProfilePolicy.AcceptsProfile(rawProfileDB) then
    local archive = EnsurePre6Archive()
    if archive.__standalone == nil then archive.__standalone = rawProfileDB end
    _G.MSUF_DB = nil
    archivedCount = archivedCount + 1
end
if retiredNames then
    if type(globalDB.char) == "table" then
        for _, binding in pairs(globalDB.char) do
            if type(binding) == "table" then
                if retiredNames[binding.activeProfile] then binding.activeProfile = nil end
                if type(binding.specProfileMap) == "table" then
                    for specID, profileName in pairs(binding.specProfileMap) do
                        if retiredNames[profileName] then binding.specProfileMap[specID] = nil end
                    end
                end
            end
        end
    end
    if retiredNames[globalDB.global.defaultProfileForNewChars] then
        globalDB.global.defaultProfileForNewChars = nil
    end
end
ProfilePolicy.ArchivedThisLoad = archivedCount
ProfilePolicy.WasFreshInstall = not hadSavedState
