-- Regression coverage for exact unit-frame Health/Power background opacity.
--
-- The compiled background alpha is final: explicit color alpha is multiplied
-- exactly once during compilation, while cold repaints and Menu2 preview
-- rendering must not multiply the compiled result again.

local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local function Near(actual, expected, label)
    Check(type(actual) == "number" and math.abs(actual - expected) < 0.000001,
        string.format("%s: expected %.3f, got %s", label, expected, tostring(actual)))
end

local function Read(path)
    local handle = assert(io.open(path, "rb"))
    local source = handle:read("*a") or ""
    handle:close()
    return source
end

local function FindUpvalue(fn, expected)
    for index = 1, 120 do
        local name, value = debug.getupvalue(fn, index)
        if not name then break end
        if name == expected then return value end
    end
    error("missing upvalue " .. tostring(expected), 2)
end

local function Clamp01(value, fallback)
    value = tonumber(value)
    if value == nil then value = fallback end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function FrameStub()
    return {
        EnableMouse = function() end,
        SetAlpha = function() end,
        ClearAllPoints = function() end,
        SetSize = function() end,
        SetPoint = function() end,
        Show = function() end,
        SetScript = function() end,
        RegisterEvent = function() end,
        RegisterUnitEvent = function() end,
    }
end

_G.UIParent = FrameStub()
_G.CreateFrame = function() return FrameStub() end
_G.C_Timer = { After = function(_, callback) callback() end }
_G.InCombatLockdown = function() return false end
_G.IsInInstance = function() return false, "none" end
_G.UnitIsPVP = function() return false end
_G.UnitIsPVPFreeForAll = function() return false end
_G.issecretvalue = function() return false end

local mockUnit = { exists = true, isPlayer = true, classToken = "MAGE", playerClassToken = "ROGUE" }
local playerClassReads = 0
_G.UnitExists = function(unit) return unit == "player" or mockUnit.exists end
_G.UnitIsPlayer = function(unit) return unit == "player" or mockUnit.isPlayer end
_G.UnitClass = function(unit)
    if unit == "player" then playerClassReads = playerClassReads + 1 end
    local token = unit == "player" and mockUnit.playerClassToken or mockUnit.classToken
    return token and token:sub(1, 1) .. token:sub(2):lower() or nil, token
end
_G.RAID_CLASS_COLORS = {
    MAGE = { r = 0.25, g = 0.50, b = 0.90 },
    PRIEST = { r = 0.95, g = 0.95, b = 0.95 },
    ROGUE = { r = 0.80, g = 0.70, b = 0.10 },
}

local UF = {
    Clamp01 = Clamp01,
    NumberWithFallback = function(value, fallback)
        local number = tonumber(value)
        if number == nil then return fallback end
        return number
    end,
    NormalizeDispelDetectTrigger = function(value) return value end,
    NormalizeDispelOverlayTrigger = function(value) return value end,
    NormalizeDispelOverlayStyle = function(value) return value end,
    NormalizeRangeFadeLayerMode = function(value) return value end,
    NormalizeAbsorbTestScope = function(value) return value end,
    AbsorbTextureTestEnabledForScope = function() return false end,
    ConfigScopedValue = function(conf, general, key, fallback)
        local value = conf and conf[key]
        if value == nil then value = general and general[key] end
        if value == nil then return fallback end
        return value
    end,
    CompileBorderPriority = function() return false, {} end,
    ResolveBarGradient = function() return nil end,
    FillPredictionColors = function() end,
}
function UF.ReadUnitExistsCached(_, unit)
    return unit == "player" or mockUnit.exists, true
end
function UF.ReadUnitIsPlayerCached(_, unit)
    return unit == "player" or mockUnit.isPlayer, true
end
function UF.ReadUnitClassCached(_, unit)
    local token = unit == "player" and mockUnit.playerClassToken or mockUnit.classToken
    return token and token:sub(1, 1) .. token:sub(2):lower() or nil, token
end
UF.elements = {}
function UF.RegisterElement(name, element)
    UF.elements[name] = element
    return true
end
local MSUF = {
    UF = UF,
    Bars = {},
    Secrets = {
        SafeNumber = tonumber,
        IsSecret = function() return false end,
        IsNil = function(value) return value == nil end,
    },
}
function MSUF.ExportPublic(name, value)
    MSUF[name] = value
    _G[name] = value
    return value
end
_G.MSUF_NS = MSUF
_G.MSUF_DB = {
    general = {
        classBarBgR = 0.22,
        classBarBgG = 0.33,
        classBarBgB = 0.44,
        powerBarBgColorR = 0.11,
        powerBarBgColorG = 0.22,
        powerBarBgColorB = 0.33,
    },
    bars = { barBackgroundAlpha = 90 },
}

assert(loadfile(root .. "/MidnightSimpleUnitFrames/Runtime/MSUF_Colors.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
local Colors = assert(MSUF._colorsAPI, "color API missing")
local _, _, _, defaultHealthTintAlpha = Colors.GetClassBarBgColor()
local _, _, _, defaultPowerTintAlpha = Colors.GetPowerBarBackgroundColor()
Near(defaultHealthTintAlpha, 1, "default Health tint opacity")
Near(defaultPowerTintAlpha, 1, "default Power tint opacity")

-- Full-profile imports keep the root table stable but may replace `general`.
-- The color API must follow that child replacement instead of writing through
-- its previously cached, now-detached table.
local detachedGeneral = _G.MSUF_DB.general
_G.MSUF_DB.general = {
    classBarBgR = 0.22,
    classBarBgG = 0.33,
    classBarBgB = 0.44,
    powerBarBgColorR = 0.11,
    powerBarBgColorG = 0.22,
    powerBarBgColorB = 0.33,
    barBgClassColor = false,
}
Colors.SetBarBgClassColor(true)
Check(_G.MSUF_DB.general.barBgClassColor == true,
    "class-background toggle wrote to a detached pre-import general table")
Check(detachedGeneral.barBgClassColor == nil,
    "detached pre-import general table was mutated")
Colors.SetBarBgClassColor(false)

Colors.SetClassBarBgColor(0.22, 0.33, 0.44, 0.4)
Colors.SetPowerBarBackgroundColor(0.11, 0.22, 0.33, 0.6)
local _, _, _, storedHealthTintAlpha = Colors.GetClassBarBgColor()
local _, _, _, storedPowerTintAlpha = Colors.GetPowerBarBackgroundColor()
Near(storedHealthTintAlpha, 0.4, "stored Health tint opacity")
Near(storedPowerTintAlpha, 0.6, "stored Power tint opacity")
_G.MSUF_DB.general.classBarBgA = nil
_G.MSUF_DB.general.powerBarBgColorA = nil

assert(loadfile(root .. "/MidnightSimpleUnitFrames/Runtime/MSUF_BarBackgroundRuntime.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Config.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

local buildSettingsCache = FindUpvalue(UF.Config.GetSettingsCache, "BuildSettingsCache")
local resolveHealth = FindUpvalue(buildSettingsCache, "ResolveHealthBackground")
local resolvePower = FindUpvalue(buildSettingsCache, "ResolvePowerBackground")

local health = resolveHealth(_G.MSUF_DB.general, _G.MSUF_DB.bars, {}, {}, { hpBgAlpha = 1 })
local power = resolvePower(_G.MSUF_DB.general, _G.MSUF_DB.bars, {}, {}, { powerBarBgAlpha = 1 })
Near(health.a, 1, "100% Health background compile")
Near(power.a, 1, "100% Power background compile")

_G.MSUF_DB.general.classBarBgA = 0.4
_G.MSUF_DB.general.powerBarBgColorA = 0.6
health = resolveHealth(_G.MSUF_DB.general, _G.MSUF_DB.bars, {}, {}, { hpBgAlpha = 1 })
power = resolvePower(_G.MSUF_DB.general, _G.MSUF_DB.bars, {}, {}, { powerBarBgAlpha = 1 })
Near(health.a, 0.4, "40% explicit Health tint opacity")
Near(power.a, 0.6, "60% explicit Power tint opacity")

health = resolveHealth(_G.MSUF_DB.general, _G.MSUF_DB.bars, {}, {}, { hpBgAlpha = 0.5 })
power = resolvePower(_G.MSUF_DB.general, _G.MSUF_DB.bars, {}, {}, { powerBarBgAlpha = 0.5 })
Near(health.a, 0.2, "Health tint opacity is multiplied once")
Near(power.a, 0.3, "Power tint opacity is multiplied once")

_G.MSUF_DB.general.classBarBgA = nil
_G.MSUF_DB.general.powerBarBgColorA = nil

health = resolveHealth(_G.MSUF_DB.general, _G.MSUF_DB.bars, {}, {}, { hpBgAlpha = 0.35 })
power = resolvePower(_G.MSUF_DB.general, _G.MSUF_DB.bars, {}, {}, { powerBarBgAlpha = 0.65 })
Near(health.a, 0.35, "35% Health background compile")
Near(power.a, 0.65, "65% Power background compile")

local cache = UF.Config.RefreshSettingsCache()
Near(cache.barBgTintA, 0.9, "global Health background cache")
Near(cache.powerBgTintA, 0.9, "global Power background cache")

local function TextureStub()
    local texture = {}
    function texture:SetTexture(value) self.texture = value end
    function texture:SetVertexColor(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a end
    return texture
end

local frame = {
    hpBarBG = TextureStub(),
    powerBarBG = TextureStub(),
    hpBar = { GetStatusBarColor = function() return 0.7, 0.2, 0.1, 1 end },
    MSUFSpec = {
        backgroundTexture = "BackgroundTexture",
        health = { backgroundTexture = "HealthTexture", background = { a = 1 } },
        power = { backgroundTexture = "PowerTexture", background = { a = 0.65 } },
    },
}

_G.MSUF_ApplyBarBackgroundVisual(frame)
Near(frame.hpBarBG.a, 1, "runtime Health repaint")
Near(frame.powerBarBG.a, 0.65, "runtime Power repaint")
local _, _, _, effectiveAlpha = _G.MSUF_GetEffectiveHealthBarBackgroundTintRGBA(frame)
Near(effectiveAlpha, 1, "effective Health tint")

frame.MSUFSpec.health.background.a = 0
frame.MSUFSpec.power.background.a = 0.25
_G.MSUF_ApplyBarBackgroundVisual(frame)
Near(frame.hpBarBG.a, 0, "runtime zero Health repaint")
Near(frame.powerBarBG.a, 0.25, "runtime 25% Power repaint")

assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_BarsCommon.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

local classFrame = {
    MSUFUnitKey = "target",
    bg = TextureStub(),
    MSUFSpec = {
        health = {
            backgroundTexture = "HealthTexture",
            backgroundClassColor = true,
            background = { r = 0.10, g = 0.20, b = 0.30, a = 0.73 },
        },
    },
}
MSUF.UFBarTextCommon.ApplyBackgrounds(classFrame, true, false)
Near(classFrame.bg.r, 0.25, "initial class background red")
Near(classFrame.bg.g, 0.50, "initial class background green")
Near(classFrame.bg.b, 0.90, "initial class background blue")
Near(classFrame.bg.a, 0.73, "class background preserves compiled opacity")

mockUnit.classToken = "PRIEST"
Check(UF.elements.Health.UpdateIdentityBackground(classFrame) == true,
    "identity background refresh must be active for class mode")
Near(classFrame.bg.r, 0.95, "identity class background red")
Near(classFrame.bg.g, 0.95, "identity class background green")
Near(classFrame.bg.b, 0.95, "identity class background blue")
Near(classFrame.bg.a, 0.73, "identity refresh preserves compiled opacity")

mockUnit.isPlayer = false
UF.elements.Health.UpdateIdentityBackground(classFrame)
Near(classFrame.bg.r, 0.80, "NPC falls back to local player class red")
Near(classFrame.bg.g, 0.70, "NPC falls back to local player class green")
Near(classFrame.bg.b, 0.10, "NPC falls back to local player class blue")
Near(classFrame.bg.a, 0.73, "NPC class fallback preserves compiled opacity")
Check(playerClassReads == 1, "local player fallback class was not read exactly once")

mockUnit.exists = false
UF.elements.Health.UpdateIdentityBackground(classFrame)
Near(classFrame.bg.r, 0.80, "missing unit falls back to local player class red")
Near(classFrame.bg.g, 0.70, "missing unit falls back to local player class green")
Near(classFrame.bg.b, 0.10, "missing unit falls back to local player class blue")
Check(playerClassReads == 1, "stable local player class was reread for a missing unit")
mockUnit.exists = true

classFrame.MSUFSpec.health.backgroundClassColor = false
Check(UF.elements.Health.UpdateIdentityBackground(classFrame) == false,
    "disabled class mode must skip identity repaint")

local runtimeSource = Read(root .. "/MidnightSimpleUnitFrames/Runtime/MSUF_BarBackgroundRuntime.lua")
Check(not runtimeSource:find("_MSUF_BarBackgroundAlphaMul", 1, true),
    "runtime still has a second background-alpha multiplier")

local previewModel = Read(root .. "/MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Model.lua")
Check(not previewModel:find("a = a * Clamp01(cache and cache.barBackgroundAlpha", 1, true),
    "unit preview model still multiplies resolved background alpha")
Check(previewModel:find("or UNIT_DATA.player.class", 1, true),
    "unit preview does not show the local-player class fallback for NPCs")

local previewCore = Read(root .. "/MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Core.lua")
Check(previewCore:find("Core.SetRegionAlpha(mock.hpBG, alpha.flat and alpha.frame or 1)", 1, true),
    "unit preview still multiplies Health background alpha via region alpha")
Check(previewCore:find("Core.SetRegionAlpha(mock.powerBG, alpha.flat and alpha.frame or 1)", 1, true),
    "unit preview still multiplies Power background alpha via region alpha")

local unitConfig = Read(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Config.lua")
Check(unitConfig:find("health.backgroundClassColor = general.barBgClassColor == true", 1, true),
    "unit specs do not compile class-background state")

local groupConfig = Read(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua")
Check(groupConfig:find("backgroundClassColor = healthVisual.backgroundClassColor == true", 1, true),
    "group specs do not compile class-background state")

local core = Read(root .. "/MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua")
Check(core:find("RefreshIdentityHealthBackground(frame)", 1, true),
    "identity lifecycle does not refresh class backgrounds")

local groupPreview = Read(root .. "/MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua")
Check(groupPreview:find("runtimeHealth.backgroundClassColor == true", 1, true),
    "group preview ignores compiled class-background state")

print("PASS unit backgrounds: exact opacity and class-color lifecycle stay consistent")
