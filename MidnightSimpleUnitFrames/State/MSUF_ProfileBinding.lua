-- Only the cold startup boundary reads a legacy standalone SavedVariable.
-- Stored profiles retain the exact 6.50 precedence when the runtime alias
-- replaces the standalone copy; migration adds no persistent archive keys.
local _, MSUF = ...
local Binding = {}
MSUF.ProfileBinding = Binding

function Binding.MigrateLegacyBarTextures(profile)
    return MSUF.ProfileMigrations.RepairBarNames(profile)
end

local function PreserveUpgradePositions(profile)
    if type(profile) ~= "table" or getmetatable(profile) ~= nil then return end
    local revision, schema, state = profile._msufDefaultsRevision, profile._msufProfileSchema, profile._msufStateSchema
    local v2, v3 = profile._msufSparseDefaultsV2, profile._msufSparseDefaultsV3
    local secret = MSUF.Util.IsSecret
    if secret(revision) or secret(schema) or secret(state) or secret(v2) or secret(v3) then return end
    if (revision == 17 or revision == 18) and schema == 600 and state == nil and v2 == nil and v3 == nil
        and MSUF.DefaultsSchema.IsLegacyFullProfile(profile) then
        MSUF.UF.Config.PreserveUpgradePositions(profile)
    end
end

--- A Forever surname character that has no binding of its own yet copies its
--- 6.5x binding (active profile, spec map, auto switch). The 6.5x entry stays
--- for 6.5x and for other characters that shared it. Without this the first
--- 7.0 login bound Default until the player picked the profile again.
function Binding.AdoptLegacyCharacter(globalDB, charKey)
    local chars = type(globalDB) == "table" and globalDB.char
    if type(chars) ~= "table" or type(charKey) ~= "string" or type(chars[charKey]) == "table" then return false end
    local legacyKey = MSUF.GetLegacyCharacterProfileKey()
    local legacy = legacyKey and chars[legacyKey]
    if type(legacy) ~= "table" or getmetatable(legacy) ~= nil then return false end
    chars[charKey] = CopyTable(legacy)
    return true
end

function Binding.Migrate(legacy, clearLegacy)
    MSUF_DB = nil
    if clearLegacy and type(legacy) == "table" then legacy.assistant = nil end
    local globalDB = MSUF_GlobalDB
    local charKey = MSUF.Require("MSUF_GetCharKey", "State/MSUF_ProfileBinding.lua")()
    -- Before resolving: MSUF_InitProfiles must resolve the same profile name.
    Binding.AdoptLegacyCharacter(globalDB, charKey)
    local active, source = MSUF.ResolveStartupProfile(globalDB, legacy, charKey)
    local profiles = type(globalDB) == "table" and globalDB.profiles
    -- FirstLoad captured the untouched account before this startup-only pass.
    -- The ordinary migration ledger stamps state 700 after binding each profile.
    PreserveUpgradePositions(legacy)
    for _, stored in pairs(type(profiles) == "table" and profiles or {}) do PreserveUpgradePositions(stored) end
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

