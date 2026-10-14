-- Only the cold startup boundary reads a legacy standalone SavedVariable.
-- Stored profiles retain the exact 6.50 precedence when the runtime alias
-- replaces the standalone copy; migration adds no persistent archive keys.
local _, MSUF = ...
local Binding = {}
MSUF.ProfileBinding = Binding

function Binding.MigrateLegacyBarTextures(profile)
    return MSUF.ProfileMigrations.RepairBarNames(profile)
end

function Binding.Migrate(legacy, clearLegacy)
    MSUF_DB = nil
    if clearLegacy and type(legacy) == "table" then legacy.assistant = nil end
    local globalDB = MSUF_GlobalDB
    local charKey = MSUF.Require("MSUF_GetCharKey", "State/MSUF_ProfileBinding.lua")()
    local active, source = MSUF.ResolveStartupProfile(globalDB, legacy, charKey)
    local profiles = type(globalDB) == "table" and globalDB.profiles
    local profile = source
    if type(profiles) ~= "table" or profiles[active] ~= source then
        profile = type(source) == "table" and CopyTable(source) or nil
    end
    if type(profile) == "table" then
        MSUF.ProfileNormalize.TranslateProfileToCurrent(profile, { source = "init", trustNormalizationMarker = true })
        MSUF.Require("MSUF_NormalizeProfileDefaults", "State/MSUF_ProfileBinding.lua")(profile, false, true)
    end
    return { legacyDB = legacy, profile = profile }
end

