-- Only the cold startup boundary reads a legacy standalone SavedVariable.
-- Stored profiles retain the exact 6.50 precedence when the runtime alias
-- replaces the standalone copy; migration adds no persistent archive keys.
local _, MSUF = ...
local Binding = {}
MSUF.ProfileBinding = Binding

local BAR_NAMES = { ["MSUF Flat"] = "Solid" }
for _, suffix in ipairs({ "Charcoal", "Minimalist", "Slickrock", "Smooth", "Smooth v2", "Smoother" }) do
    BAR_NAMES["Midnight " .. suffix] = "MSUF " .. suffix
end

function Binding.MigrateLegacyBarTextures(profile)
    local general = type(profile) == "table" and profile.general
    if type(general) ~= "table" then return end
    local bar, castbar = general.barTexture, general.castbarTexture
    if type(bar) == "string" and BAR_NAMES[bar] then general.barTexture = BAR_NAMES[bar] end
    if type(castbar) == "string" and BAR_NAMES[castbar] then general.castbarTexture = BAR_NAMES[castbar] end
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
    Binding.MigrateLegacyBarTextures(profile)
    return { legacyDB = legacy, profile = profile }
end

