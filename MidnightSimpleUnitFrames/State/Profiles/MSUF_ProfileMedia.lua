-- Profile import media validation and user-facing warning collection.
local _, MSUF = ...
local Parts = MSUF.ProfilesParts
local ExportPublic = Parts.ExportPublic
local PixelLayoutRegion = Parts.PixelLayoutRegion
local ProfileChat = Parts.ProfileChat
local MSUF_DeepCopy
local MSUF_ProfileIO_ImportWarningMap = {}
local MSUF_ProfileIO_ImportWarnings = {}

local function MSUF_ProfileIO_ResetImportWarnings()
    for key in pairs(MSUF_ProfileIO_ImportWarningMap) do
        MSUF_ProfileIO_ImportWarningMap[key] = nil
    end
    for i = #MSUF_ProfileIO_ImportWarnings, 1, -1 do
        MSUF_ProfileIO_ImportWarnings[i] = nil
    end
    ExportPublic("MSUF_ProfileIO_LastImportWarnings", nil)
end

local function MSUF_ProfileIO_AddImportWarning(kind, label, value)
    if type(value) ~= "string" or value == "" then return end
    kind = tostring(kind or "media")
    label = tostring(label or "profile")
    local id = kind .. "\001" .. label .. "\001" .. value
    if MSUF_ProfileIO_ImportWarningMap[id] then return end
    MSUF_ProfileIO_ImportWarningMap[id] = true
    MSUF_ProfileIO_ImportWarnings[#MSUF_ProfileIO_ImportWarnings + 1] = {
        kind = kind,
        label = label,
        value = value,
    }
end

local function MSUF_ProfileIO_PublishImportWarnings()
    if #MSUF_ProfileIO_ImportWarnings == 0 then
        ExportPublic("MSUF_ProfileIO_LastImportWarnings", nil)
        return nil
    end
    local copy = {}
    for i = 1, #MSUF_ProfileIO_ImportWarnings do
        copy[i] = MSUF_DeepCopy(MSUF_ProfileIO_ImportWarnings[i])
    end
    ExportPublic("MSUF_ProfileIO_LastImportWarnings", copy)
    return copy
end

local function MSUF_ProfileIO_ReportImportWarnings()
    local warnings = MSUF_ProfileIO_PublishImportWarnings()
    if not warnings then return end
    local count = #warnings
    local maxLines = count > 5 and 5 or count
    for i = 1, maxLines do
        local w = warnings[i]
        local text = (w.kind == "font") and "Import warning: missing font '%s' in %s. Using fallback font."
            or "Import warning: missing texture '%s' in %s. Using fallback texture."
        ProfileChat("note", text, tostring(w.value), tostring(w.label))
    end
    if count > maxLines then
        ProfileChat("note", "Import warning: %d more missing media item(s).", count - maxLines)
    end
end

local function MSUF_ProfileIO_GetLSM()
    return (MSUF and MSUF.LSM) or MSUF.PublicGlobals.MSUF_LSM or (_G.LibStub and _G.LibStub("LibSharedMedia-3.0", true))
end

local function MSUF_ProfileIO_LooksLikeMediaPath(value)
    if MSUF.Fonts.IsFontPath(value) then return true end
    if type(value) ~= "string" or value == "" then return false end
    local lower = value:lower()
    return lower:match("%.tga$") ~= nil or lower:match("%.blp$") ~= nil or lower:match("%.png$") ~= nil
end

local function MSUF_ProfileIO_FontPathAvailable(path)
    if type(path) ~= "string" or path == "" then return false end
    --- Runtime/MSUF_FontRegistry.lua answers availability from registry
    --- metadata (MSUF_IsAvailableFontPath); the SetFont probe it replaced,
    --- MSUF_FontPathIsLoadable, no longer exists.
    local isAvailable = MSUF.Require("MSUF_IsAvailableFontPath", "State/MSUF_Profiles.lua")
    return isAvailable(path) == true
end

local function MSUF_ProfileIO_FontKeyAvailable(key)
    if type(key) ~= "string" or key == "" then return true end
    if MSUF_ProfileIO_LooksLikeMediaPath(key) then return MSUF_ProfileIO_FontPathAvailable(key) end
    local path = MSUF.Fonts.InternalPathForKey(key)
    return MSUF_ProfileIO_FontPathAvailable(path)
end

local MSUF_ProfileIO_TextureProbeHost
local MSUF_ProfileIO_TextureProbe
local MSUF_ProfileIO_TextureProbeReliable
local MSUF_ProfileIO_TexturePathCache = {}

local function MSUF_ProfileIO_NormalizeTexturePath(path)
    if type(path) ~= "string" or path == "" then return nil end
    path = path:gsub("/", "\\")
    return path ~= "" and path or nil
end

local function MSUF_ProfileIO_TextureProbeRaw(path)
    path = MSUF_ProfileIO_NormalizeTexturePath(path)
    if not path or type(_G.CreateFrame) ~= "function" then return nil end
    if not MSUF_ProfileIO_TextureProbe then
        MSUF_ProfileIO_TextureProbeHost = _G.CreateFrame("Frame")
        if MSUF_ProfileIO_TextureProbeHost.Hide then MSUF_ProfileIO_TextureProbeHost:Hide() end
        MSUF_ProfileIO_TextureProbe = PixelLayoutRegion(MSUF_ProfileIO_TextureProbeHost:CreateTexture(nil, "ARTWORK"), true)
    end
    local probe = MSUF_ProfileIO_TextureProbe
    if not (probe and type(probe.SetTexture) == "function") then return nil end
    probe:SetTexture(nil)
    -- SetTexture reports an unloadable path via its documented success return.
    local applied = probe:SetTexture(path)
    if applied == false then
        probe:SetTexture(nil)
        return false
    end
    if type(probe.GetTexture) == "function" then
        local tex = probe:GetTexture()
        probe:SetTexture(nil)
        return tex ~= nil and tex ~= ""
    end
    probe:SetTexture(nil)
    return true
end

local function MSUF_ProfileIO_TextureProbeIsReliable()
    if MSUF_ProfileIO_TextureProbeReliable ~= nil then return MSUF_ProfileIO_TextureProbeReliable end
    local result = MSUF_ProfileIO_TextureProbeRaw("Interface\\AddOns\\MidnightSimpleUnitFrames\\__msuf_missing_texture_probe__")
    MSUF_ProfileIO_TextureProbeReliable = (result == false)
    return MSUF_ProfileIO_TextureProbeReliable
end

local function MSUF_ProfileIO_TexturePathLoadable(path)
    path = MSUF_ProfileIO_NormalizeTexturePath(path)
    if not path then return false end
    local cached = MSUF_ProfileIO_TexturePathCache[path]
    if cached ~= nil then return cached end
    local isKnown = MSUF.PublicGlobals.MSUF_IsKnownFileAsset
    if type(isKnown) == "function" and isKnown(path) == false then
        MSUF_ProfileIO_TexturePathCache[path] = false
        return false
    end
    if not MSUF_ProfileIO_TextureProbeIsReliable() then
        MSUF_ProfileIO_TexturePathCache[path] = true
        return true
    end
    local lower = path:lower()
    local exists = MSUF_ProfileIO_TextureProbeRaw(path) == true
    if not exists and not (lower:match("%.tga$") or lower:match("%.blp$") or lower:match("%.png$")) then
        exists = MSUF_ProfileIO_TextureProbeRaw(path .. ".tga") == true
            or MSUF_ProfileIO_TextureProbeRaw(path .. ".blp") == true
            or MSUF_ProfileIO_TextureProbeRaw(path .. ".png") == true
    end
    MSUF_ProfileIO_TexturePathCache[path] = exists and true or false
    return MSUF_ProfileIO_TexturePathCache[path]
end

local function MSUF_ProfileIO_StatusbarTextureAvailable(key)
    if type(key) ~= "string" or key == "" then return true end
    local builtins = MSUF.PublicGlobals.MSUF_BUILTIN_BAR_TEXTURES
    if type(builtins) == "table" and MSUF_ProfileIO_TexturePathLoadable(builtins[key]) then
        return true
    end
    if key == "Solid" or key == "Blizzard" or key == "Flat" or key == "RaidHP" or key == "RaidPower" then
        return true
    end
    if MSUF_ProfileIO_LooksLikeMediaPath(key) then
        return MSUF_ProfileIO_TexturePathLoadable(key)
    end
    local lsm = MSUF_ProfileIO_GetLSM()
    if lsm and type(lsm.HashTable) == "function" then
        local bars = lsm:HashTable("statusbar")
        local path = bars and bars[key]
        if MSUF_ProfileIO_TexturePathLoadable(path) then return true end
    end
    if lsm and type(lsm.Fetch) == "function" then
        local path = lsm:Fetch("statusbar", key, true)
        if MSUF_ProfileIO_TexturePathLoadable(path) then return true end
    end
    return false
end

local function MSUF_ProfileIO_CollectStatusbarTextureWarnings(scope, labelPrefix, keys)
    if type(scope) ~= "table" then return end
    for _, key in ipairs(keys) do
        local value = scope[key]
        if type(value) == "string" and value ~= "" and not MSUF_ProfileIO_StatusbarTextureAvailable(value) then
            MSUF_ProfileIO_AddImportWarning("texture", labelPrefix .. "." .. key, value)
        end
    end
end

local MSUF_PROFILEIO_GENERAL_TEXTURE_WARNING_KEYS = {
    "barTexture",
    "barBackgroundTexture",
    "castbarTexture",
    "castbarBackgroundTexture",
    "absorbBarTexture",
    "healAbsorbBarTexture",
}

local MSUF_PROFILEIO_BARS_TEXTURE_WARNING_KEYS = {
    "classPowerTexture",
    "classPowerBgTexture",
    "powerBarTexture",
    "powerBarBgTexture",
    "playerHPBarTexture",
    "playerHPBarBgTexture",
}

local MSUF_PROFILEIO_UNIT_TEXTURE_WARNING_KEYS = {
    "barTexture",
    "barBackgroundTexture",
    "powerBarTexture",
    "powerBarBgTexture",
    "absorbBarTexture",
    "healAbsorbBarTexture",
}

local MSUF_PROFILEIO_MEDIA_UNIT_SCOPE_KEYS = {
    "player", "target", "targettarget", "tot", "focustarget", "focus", "pet", "pettarget", "boss", "arena",
}

local MSUF_PROFILEIO_GROUP_TEXTURE_WARNING_KEYS = {
    "barTexture",
    "barBackgroundTexture",
    "barBgTexture",
    "absorbBarTexture",
    "healAbsorbBarTexture",
}

local function MSUF_ProfileIO_CollectProfileMediaWarnings(profile)
    if type(profile) ~= "table" then return end
    local g = profile.general
    if type(g) == "table" then
        if type(g.fontKey) == "string" and g.fontKey ~= "" and not MSUF_ProfileIO_FontKeyAvailable(g.fontKey) then
            MSUF_ProfileIO_AddImportWarning("font", "general.fontKey", g.fontKey)
        end
        MSUF_ProfileIO_CollectStatusbarTextureWarnings(g, "general", MSUF_PROFILEIO_GENERAL_TEXTURE_WARNING_KEYS)
    end
    local bars = profile.bars
    if type(bars) == "table" then
        MSUF_ProfileIO_CollectStatusbarTextureWarnings(bars, "bars", MSUF_PROFILEIO_BARS_TEXTURE_WARNING_KEYS)
    end
    for _, scopeKey in ipairs(MSUF_PROFILEIO_MEDIA_UNIT_SCOPE_KEYS) do
        local scope = profile[scopeKey]
        if type(scope) == "table" then
            MSUF_ProfileIO_CollectStatusbarTextureWarnings(scope, scopeKey, MSUF_PROFILEIO_UNIT_TEXTURE_WARNING_KEYS)
        end
    end
    for _, scopeKey in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
        local scope = profile[scopeKey]
        if type(scope) == "table" then
            MSUF_ProfileIO_CollectStatusbarTextureWarnings(scope, scopeKey, MSUF_PROFILEIO_GROUP_TEXTURE_WARNING_KEYS)
        end
    end
end

ExportPublic("MSUF_ProfileIO_GetLastImportWarnings", function()
    return MSUF_ProfileIO_PublishImportWarnings()
end)


Parts.MSUF_ProfileIO_CollectProfileMediaWarnings = MSUF_ProfileIO_CollectProfileMediaWarnings
Parts.MSUF_ProfileIO_ReportImportWarnings = MSUF_ProfileIO_ReportImportWarnings
Parts.MSUF_ProfileIO_ResetImportWarnings = MSUF_ProfileIO_ResetImportWarnings
function Parts.Bind1()
    MSUF_DeepCopy = Parts.MSUF_DeepCopy
end
