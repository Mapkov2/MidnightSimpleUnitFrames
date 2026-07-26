-- Regression coverage for the custom pet HP color and NPC-color isolation.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local function Clamp01(value, fallback)
    value = tonumber(value)
    if value == nil then value = fallback end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

_G.CreateFrame = function()
    return {
        SetScript = function() end,
        RegisterEvent = function() end,
        RegisterUnitEvent = function() end,
    }
end
_G.InCombatLockdown = function() return false end
_G.IsInInstance = function() return false, "none" end
_G.UnitIsPVP = function() return false end
_G.UnitIsPVPFreeForAll = function() return false end
_G.issecretvalue = function() return false end
local unitClassCalls = 0
_G.UnitClass = function(unit)
    unitClassCalls = unitClassCalls + 1
    if unit == "player" then return "Rogue", "ROGUE" end
    return nil, nil
end
_G.RAID_CLASS_COLORS = { ROGUE = { r = 1, g = 0.96, b = 0.41 } }

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
local MSUF = {
    UF = UF,
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

local function Load(relativePath)
    local path = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/" .. relativePath
    return assert(loadfile(path))("MidnightSimpleUnitFrames", MSUF)
end

_G.MSUF_DB = {
    general = {},
    bars = {},
    classColors = { ROGUE = { r = 0.67, g = 0.23, b = 0.84 } },
}
Load("MSUF_UF_Config.lua")

local cache = UF.Config.RefreshSettingsCache()
Check(cache.petFrameColorEnabled == false,
    "an unset pet color unexpectedly enabled the custom override")
Check(cache.petFrameUsePlayerClassColor == false,
    "the player class-color override unexpectedly defaulted on")

_G.MSUF_DB.general.petFrameColorR = 0.91
_G.MSUF_DB.general.petFrameColorG = 0.72
cache = UF.Config.RefreshSettingsCache()
Check(cache.petFrameColorEnabled == false,
    "an incomplete pet RGB color unexpectedly enabled the custom override")

_G.MSUF_DB.general.petFrameColorB = 0.19
cache = UF.Config.RefreshSettingsCache()
Check(cache.petFrameColorEnabled == true,
    "a complete saved pet RGB color did not enable the custom override")
Check(cache.petFrameColorR == 0.91 and cache.petFrameColorG == 0.72 and cache.petFrameColorB == 0.19,
    "the compiled pet RGB color changed")

local npcR, npcG, npcB = 0, 1, 0
_G.UnitExists = function() return true end
_G.UnitIsDeadOrGhost = function() return false end
_G.UnitIsConnected = function() return true end
_G.UnitIsPlayer = function() return false end
_G.UnitReaction = function() return 5 end
_G.UnitSelectionType = function() return 2 end
_G.UnitClassification = function() return "normal" end
_G.MSUF_UFCore_GetNPCReactionColorFast = function() return npcR, npcG, npcB end
function UF.FreshUnitState(frame, unit)
    local state = frame and frame._msufUnitState
    if state and state.ready == true and state.unit == unit
        and frame._msufDispatchActive == true
        and state.dispatchToken == frame._msufDispatchToken then
        return state
    end
    return nil
end
function UF.ReadUnitExistsCached(_, unit) return _G.UnitExists(unit), true end
function UF.ReadUnitIsPlayerCached(_, unit) return _G.UnitIsPlayer(unit), true end
function UF.ReadUnitClassCached(_, unit) return _G.UnitClass(unit) end

Load("Elements/MSUF_UF_Elements_BarsCommon.lua")
local Common = assert(MSUF.UFBarTextCommon, "bar common missing")
local petSpec = {
    key = "pet",
    health = {
        mode = "class",
        petColorEnabled = cache.petFrameColorEnabled,
        petR = cache.petFrameColorR,
        petG = cache.petFrameColorG,
        petB = cache.petFrameColorB,
    },
}
local petFrame = {
    unit = "pet",
    configKey = "pet",
    MSUFSpec = petSpec,
    _msufDispatchActive = true,
    _msufDispatchToken = 1,
}

local r, g, b = Common.HealthColor(petFrame, "pet", 100, 100, false, "MSUF_UNIT_IDENTITY")
Check(r == 0.91 and g == 0.72 and b == 0.19,
    "the saved pet color did not win over the friendly NPC color")

npcR, npcG, npcB = 0.85, 0.10, 0.10
petFrame._msufDispatchToken = 2
r, g, b = Common.HealthColor(petFrame, "pet", 100, 100, false, "MSUF_UNIT_IDENTITY")
Check(r == 0.91 and g == 0.72 and b == 0.19,
    "changing an NPC color bled into the custom pet color")

_G.MSUF_DB.general.petFrameUsePlayerClassColor = true
cache = UF.Config.RefreshSettingsCache()
Check(cache.petFrameUsePlayerClassColor == true and cache.playerClassToken == "ROGUE",
    "the player class-color override was not compiled")
Check(cache.petPlayerClassR == 0.67 and cache.petPlayerClassG == 0.23 and cache.petPlayerClassB == 0.84,
    "the player class-color override ignored MSUF's configured class color")
petSpec.health.petUsePlayerClassColor = cache.petFrameUsePlayerClassColor
petSpec.health.petPlayerClassR = cache.petPlayerClassR
petSpec.health.petPlayerClassG = cache.petPlayerClassG
petSpec.health.petPlayerClassB = cache.petPlayerClassB
petFrame._msufDispatchToken = 3
unitClassCalls = 0
r, g, b = Common.HealthColor(petFrame, "pet", 100, 100, false, "MSUF_UNIT_IDENTITY")
Check(r == 0.67 and g == 0.23 and b == 0.84,
    "the player class color did not take priority over the fixed pet color")
Check(unitClassCalls == 0,
    "the pet health-color hotpath called UnitClass instead of using compiled RGB")

local function ReadSource(relativePath)
    local file = assert(io.open(root .. "/" .. relativePath, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local unitMenu = ReadSource("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua")
local colorMenu = ReadSource("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors.lua")
Check(unitMenu:find("basics.use_player_class_color", 1, true),
    "the player class-color toggle is missing from Pet Frame Basics")
Check(colorMenu:find("unit.pet.use_player_class_color", 1, true),
    "the player class-color toggle is missing from Unitframe Colors")

print("PASS pet frame color: fixed and player-class RGB paths stay compiled and NPC-isolated")
