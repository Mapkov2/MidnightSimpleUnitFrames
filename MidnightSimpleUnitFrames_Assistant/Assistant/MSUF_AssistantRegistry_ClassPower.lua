-- Assistant ClassPower registry: exposes class resources, detached power, and player HP bridge controls.
-- Writes route through ClassPower helpers so parser metadata does not own live frame behavior.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.Workflow = A.Workflow or {}

local C = A.RegistryCore
if type(C) ~= "table" then return end

-- ClassPower registry domain.
-- Exposes class-resource, detached power, and player-HP bridge settings to the assistant.
-- Presentation updates are delegated to ClassPower runtime helpers after DB writes.
local Registry = C.Registry
local RegisterBarsBoolean = C.RegisterBarsBoolean
local RegisterBarsString = C.RegisterBarsString
local RegisterBarsNumber = C.RegisterBarsNumber
local RegisterBarsEnum = C.RegisterBarsEnum
local ClassPowerAliases = C.ClassPowerAliases
local ApplyClassPower = C.ApplyClassPower
local ApplyDetachedPowerBar = C.ApplyDetachedPowerBar
local ApplyDetachedPowerBarOutline = C.ApplyDetachedPowerBarOutline

local ClassPowerData = A.ClassPowerRegistryData
if type(ClassPowerData) ~= "table" then return end

local CLASS_POWER_WIDTH_MODE_ALIASES = ClassPowerData.CLASS_POWER_WIDTH_MODE_ALIASES
local CLASS_POWER_SHAPE_ALIASES = ClassPowerData.CLASS_POWER_SHAPE_ALIASES
local CLASS_POWER_SHAPE_ALIGN_ALIASES = ClassPowerData.CLASS_POWER_SHAPE_ALIGN_ALIASES
local COMBO_POINT_COLOR_MODE_ALIASES = ClassPowerData.COMBO_POINT_COLOR_MODE_ALIASES
local DETACHED_POWER_WIDTH_MODE_ALIASES = ClassPowerData.DETACHED_POWER_WIDTH_MODE_ALIASES

local function NormalizeInheritedTexture(value)
    local text = tostring(value or ""):match("^%s*(.-)%s*$")
    local lower = text:lower()
    if lower == "" or lower == "global" or lower == "use global" or lower == "use global bar texture" then return "" end
    if lower == "inherit" or lower == "inherited" or lower == "default" or lower == "follow global" then return "" end
    return text
end

local function NormalizeForegroundTexture(value)
    local text = NormalizeInheritedTexture(value)
    local lower = text:lower()
    if lower == "foreground" or lower == "use foreground" or lower == "use foreground texture" then return "" end
    if lower == "same as foreground" or lower == "follow foreground" then return "" end
    return text
end

local RegisterBaseSettings = A.ClassPowerRegistry and A.ClassPowerRegistry.RegisterBaseSettings
if type(RegisterBaseSettings) == "function" then
    RegisterBaseSettings({
        RegisterBarsBoolean = RegisterBarsBoolean,
        RegisterBarsNumber = RegisterBarsNumber,
        RegisterBarsEnum = RegisterBarsEnum,
        ClassPowerAliases = ClassPowerAliases,
        CLASS_POWER_WIDTH_MODE_ALIASES = CLASS_POWER_WIDTH_MODE_ALIASES,
        CLASS_POWER_SHAPE_ALIASES = CLASS_POWER_SHAPE_ALIASES,
        CLASS_POWER_SHAPE_ALIGN_ALIASES = CLASS_POWER_SHAPE_ALIGN_ALIASES,
    })
end

local RegisterAnchoringSettings = A.ClassPowerRegistry and A.ClassPowerRegistry.RegisterAnchoringSettings
if type(RegisterAnchoringSettings) == "function" then
    RegisterAnchoringSettings({
        RegisterBarsBoolean = RegisterBarsBoolean,
        ClassPowerAliases = ClassPowerAliases,
    })
end
local RegisterDisplaySettings = A.ClassPowerRegistry and A.ClassPowerRegistry.RegisterDisplaySettings
if type(RegisterDisplaySettings) == "function" then
    RegisterDisplaySettings({
        RegisterBarsBoolean = RegisterBarsBoolean,
        RegisterBarsNumber = RegisterBarsNumber,
        RegisterBarsEnum = RegisterBarsEnum,
        ClassPowerAliases = ClassPowerAliases,
        COMBO_POINT_COLOR_MODE_ALIASES = COMBO_POINT_COLOR_MODE_ALIASES,
    })
end
local RegisterTextureSettings = A.ClassPowerRegistry and A.ClassPowerRegistry.RegisterTextureSettings
if type(RegisterTextureSettings) == "function" then
    RegisterTextureSettings({
        RegisterBarsString = RegisterBarsString,
        ApplyClassPower = ApplyClassPower,
        NormalizeInheritedTexture = NormalizeInheritedTexture,
        NormalizeForegroundTexture = NormalizeForegroundTexture,
    })
end

local RegisterVisibilitySettings = A.ClassPowerRegistry and A.ClassPowerRegistry.RegisterVisibilitySettings
if type(RegisterVisibilitySettings) == "function" then
    RegisterVisibilitySettings({
        RegisterBarsBoolean = RegisterBarsBoolean,
        ClassPowerAliases = ClassPowerAliases,
    })
end

local RegisterDetachedPowerSettings = A.ClassPowerRegistry and A.ClassPowerRegistry.RegisterDetachedPowerSettings
if type(RegisterDetachedPowerSettings) == "function" then
    RegisterDetachedPowerSettings({
        RegisterBarsEnum = RegisterBarsEnum,
        RegisterBarsString = RegisterBarsString,
        RegisterBarsNumber = RegisterBarsNumber,
        ApplyDetachedPowerBar = ApplyDetachedPowerBar,
        ApplyDetachedPowerBarOutline = ApplyDetachedPowerBarOutline,
        NormalizeInheritedTexture = NormalizeInheritedTexture,
        NormalizeForegroundTexture = NormalizeForegroundTexture,
        DETACHED_POWER_WIDTH_MODE_ALIASES = DETACHED_POWER_WIDTH_MODE_ALIASES,
    })
end

local RegisterPlayerHPSettings = A.ClassPowerRegistry and A.ClassPowerRegistry.RegisterPlayerHPSettings
if type(RegisterPlayerHPSettings) == "function" then
    RegisterPlayerHPSettings({
        RegisterBarsBoolean = RegisterBarsBoolean,
        RegisterBarsString = RegisterBarsString,
        RegisterBarsNumber = RegisterBarsNumber,
        RegisterBarsEnum = RegisterBarsEnum,
        ApplyClassPower = ApplyClassPower,
        NormalizeInheritedTexture = NormalizeInheritedTexture,
        NormalizeForegroundTexture = NormalizeForegroundTexture,
    })
end

local RegisterAltManaSettings = A.ClassPowerRegistry and A.ClassPowerRegistry.RegisterAltManaSettings
if type(RegisterAltManaSettings) == "function" then
    RegisterAltManaSettings({
        RegisterBarsBoolean = RegisterBarsBoolean,
        RegisterBarsNumber = RegisterBarsNumber,
        RegisterBarsEnum = RegisterBarsEnum,
    })
end
