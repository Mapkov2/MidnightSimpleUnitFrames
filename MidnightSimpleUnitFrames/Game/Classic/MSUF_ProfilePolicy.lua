--- Classic-only 6.0 profile admission policy.
---
--- The shared profile module stays byte-identical to Retail for Mainline
--- parity, but supported Classic clients do not import 5.x/full-dump profiles.
--- This file loads immediately after State/MSUF_Profiles.lua and wraps only
--- cold import entry points; it has no gameplay events, ticker, or OnUpdate.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local Client = MSUF.Client
if not (Client and Client.IsClassic == true) then return end

local type = type
local tonumber = tonumber
local pcall = pcall
local print = print

local ProfilePolicy = MSUF.ProfilePolicy or {}
MSUF.ProfilePolicy = ProfilePolicy
local CURRENT_PROFILE_SCHEMA = tonumber(ProfilePolicy.CurrentSchema) or 600

local function IsSupportedDecodedProfile(decoded)
    if type(decoded) ~= "table" then return false end
    if tonumber(decoded._msufProfileSchema) == CURRENT_PROFILE_SCHEMA then
        return true
    end
    if decoded.addon ~= "MSUF" or tonumber(decoded.fmt) ~= 2 then
        return false
    end
    if tonumber(decoded.schema) == CURRENT_PROFILE_SCHEMA then
        return true
    end
    -- Wago's schema-1 compatibility envelope was introduced by MSUF 6.0.
    -- Prefer its lossless msuf6 payload when present, but the portable-only
    -- envelope is still a 6.0 profile and remains supported.
    if tonumber(decoded.schema) == 1 then
        local full = decoded.msuf6
        return full == nil
            or (type(full) == "table"
                and tonumber(full.schema) == CURRENT_PROFILE_SCHEMA
                and type(full.payload) == "table")
    end
    return false
end

local function IsSupportedProfileString(profileString)
    if type(profileString) ~= "string" or not profileString:match("%S") then
        return false
    end
    local decoder = _G.MSUF_TryDecodeCompactString
        or (type(MSUF) == "table" and MSUF.MSUF_TryDecodeCompactString)
    if type(decoder) ~= "function" then return false end
    local ok, decoded = pcall(decoder, profileString)
    return ok and IsSupportedDecodedProfile(decoded)
end

ProfilePolicy.AcceptsDecodedProfile = IsSupportedDecodedProfile
ProfilePolicy.AcceptsProfileString = IsSupportedProfileString

local function RejectLegacyProfile()
    print("|cffff0000MSUF:|r Classic accepts only MSUF 6.0 profiles (schema 600).")
    return false
end

local originalImport = _G.MSUF_Profiles_ImportFromString or _G.MSUF_ImportFromString
local originalExternalImport = _G.MSUF_Profiles_ImportExternal or _G.MSUF_ImportExternal

local function ImportFromString(profileString, ...)
    if not IsSupportedProfileString(profileString) then
        return RejectLegacyProfile()
    end
    if type(originalImport) ~= "function" then return false end
    return originalImport(profileString, ...)
end

local function ImportExternal(profileString, profileKey, ...)
    if not IsSupportedProfileString(profileString) then
        return false, "Classic accepts only MSUF 6.0 profiles (schema 600)."
    end
    if type(originalExternalImport) ~= "function" then
        return false, "profile import is unavailable"
    end
    return originalExternalImport(profileString, profileKey, ...)
end

local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

ExportPublic("MSUF_ImportFromString", ImportFromString)
ExportPublic("MSUF_Profiles_ImportFromString", ImportFromString)
ExportPublic("MSUF_ImportLegacyFromString", RejectLegacyProfile)
ExportPublic("MSUF_Profiles_ImportLegacyFromString", RejectLegacyProfile)
ExportPublic("MSUF_ImportExternal", ImportExternal)
ExportPublic("MSUF_Profiles_ImportExternal", ImportExternal)

MSUF.MSUF_ImportFromString = ImportFromString
MSUF.MSUF_ImportLegacyFromString = RejectLegacyProfile
MSUF.MSUF_ImportExternal = ImportExternal
