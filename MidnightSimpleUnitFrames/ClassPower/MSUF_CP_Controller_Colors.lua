--- ClassPower/MSUF_CP_Controller_Colors.lua - controller colour resolution
--- Cold-path colour bundle for the ClassPower controller.
---
--- Resolves the base, background, charged, per-slot and full-resource colours
--- of the active class resource and caches them per token until the Colors
--- panel or a profile refresh invalidates the cache. The mode runners receive
--- these resolvers by value through their build env; the controller compiles
--- their results into CP.visual once per FullRefresh.

local _, MSUF = ...
local ExportPublic = MSUF.ExportPublic

local CPConst = MSUF.Require("MSUF_CP_CONST", "ClassPower/MSUF_CP_Controller_Colors.lua")
local builders = CPConst.BuilderRegistry("MSUF_CP_CORE_BUILDERS")
local GetPowerBarColor = MSUF.Require("MSUF_GetPowerBarColor", "ClassPower/MSUF_CP_Controller_Colors.lua")

local type, tonumber, tostring = type, tonumber, tostring
local OverrideRGB = CPConst.OverrideRGB
local CPK = CPConst.CPK

builders.CONTROLLER_COLORS = function()
--- Bound by CONTROLLER_COLORS: the shared cached config table and the
--- power-type token map.
local _cpDB, POWER_TYPE_TOKENS

--- Color resolution (uses MSUF's PowerBarColor override system). The caches
--- start empty on every build.
local _cachedColorR, _cachedColorG, _cachedColorB
local _cachedColorToken
local _cachedBgColorToken
local _cachedBgColorR, _cachedBgColorG, _cachedBgColorB
local _cachedChargedR, _cachedChargedG, _cachedChargedB

--- Maelstrom Weapon 5+ threshold color (cached independently)
local _mwAbove5R, _mwAbove5G, _mwAbove5B
local _mwAbove5Resolved

local function ResolveMWAbove5Color()
    if _mwAbove5Resolved then return _mwAbove5R, _mwAbove5G, _mwAbove5B end
    _mwAbove5Resolved = true
    local r, g, b = OverrideRGB(_cpDB.colorOverrides, "MAELSTROM_ABOVE_5")
    if r then
        _mwAbove5R, _mwAbove5G, _mwAbove5B = r, g, b
        return r, g, b
    end
    _mwAbove5R, _mwAbove5G, _mwAbove5B = 1.00, 0.50, 0.00  --- Sensei orange default
    return _mwAbove5R, _mwAbove5G, _mwAbove5B
end

local function ResolveClassPowerColor(powerType)
    --- Token resolution: numeric powerType -> string token, string -> use directly
    local token = POWER_TYPE_TOKENS[powerType]
    if not token and type(powerType) == "string" then
        token = powerType  --- already a string token (e.g. "RESOURCE_TEXT", "SOUL_FRAGMENTS")
    end
    if token == _cachedColorToken and _cachedColorToken then
        return _cachedColorR, _cachedColorG, _cachedColorB
    end
    _cachedColorToken = token

    --- 1. Custom class-power color override (from Colors panel)
    if _cpDB.general then
        local r, g, b = OverrideRGB(_cpDB.colorOverrides, token)
        if r then
            _cachedColorR, _cachedColorG, _cachedColorB = r, g, b
            return r, g, b
        end
    end

    --- 2. MSUF power bar color override
    if token then
        local r, g, b = GetPowerBarColor(powerType, token)
        if type(r) == "number" then
            _cachedColorR, _cachedColorG, _cachedColorB = r, g, b
            return r, g, b
        end
    end

    --- Fallback: MSUF's own resource defaults, then Blizzard PowerBarColor
    local pbc = PowerBarColor
    local own = MSUF._PBCSnap
    if pbc or own then
        local c = (token and own and own[token]) or (pbc and ((token and pbc[token]) or pbc[powerType]))
        if c then
            local r = c.r or c[1]
            local g = c.g or c[2]
            local b = c.b or c[3]
            if type(r) == "number" then
                _cachedColorR, _cachedColorG, _cachedColorB = r, g, b
                return r, g, b
            end
        end
    end

    --- Eclipse has no single PowerBarColor entry on Mists.
    local eclipse = token == "ECLIPSE_SOLAR" and CPK.BAL.CLR_SOLAR
        or token == "ECLIPSE_LUNAR" and CPK.BAL.CLR_LUNAR
        or token == "ECLIPSE_CA" and CPK.BAL.CLR_CA
    if eclipse then
        _cachedColorR, _cachedColorG, _cachedColorB = eclipse[1], eclipse[2], eclipse[3]
        return _cachedColorR, _cachedColorG, _cachedColorB
    end
    --- Hard fallback
    if token == "IRONFUR" then
        _cachedColorR, _cachedColorG, _cachedColorB = 1.00, 0.49, 0.04
        return _cachedColorR, _cachedColorG, _cachedColorB
    end
    _cachedColorR, _cachedColorG, _cachedColorB = 1, 1, 1
    return 1, 1, 1
end

local function ResolveClassPowerBgColor(powerType)
    local token = POWER_TYPE_TOKENS[powerType]
    if not token and type(powerType) == "string" then
        token = powerType
    end
    if token == _cachedBgColorToken and _cachedBgColorToken then
        return _cachedBgColorR, _cachedBgColorG, _cachedBgColorB
    end
    _cachedBgColorToken = token

    if _cpDB.general then
        local r, g, b = OverrideRGB(_cpDB.bgColorOverrides, token)
        if r then
            _cachedBgColorR, _cachedBgColorG, _cachedBgColorB = r, g, b
            return r, g, b
        end
    end

    _cachedBgColorR, _cachedBgColorG, _cachedBgColorB = 0, 0, 0
    return 0, 0, 0
end

local function CP_InvalidateColorCaches()
    _cachedColorToken = nil
    _cachedBgColorToken = nil
    _cachedChargedR = nil
    _cachedChargedG = nil
    _cachedChargedB = nil
    _mwAbove5Resolved = false
end

--- Public: invalidate class power color cache (called from Colors panel)
local function MSUF_ClassPower_InvalidateColors()
    CP_InvalidateColorCaches()
    --- Balance Druid: refresh eclipse + prediction overlay colors
    local invalidateBalance = MSUF.Optional("MSUF_BAL_InvalidateColors")
    if invalidateBalance then invalidateBalance() end
    local apply = MSUF.Optional("MSUF_ClassPower_Apply")
    if apply then
        apply({ visuals = true, playerHP = true })
    else
        MSUF.Require("MSUF_ClassPower_Refresh", "ClassPower/MSUF_CP_Controller_Colors.lua")()
    end
end

--- Charged/empowered color resolution

local function ResolveChargedColor()
    if _cachedChargedR then
        return _cachedChargedR, _cachedChargedG, _cachedChargedB
    end

    --- 1. Custom override from Colors panel
    if _cpDB.general then
        local r, g, b = OverrideRGB(_cpDB.colorOverrides, "CHARGED")
        if r then
            _cachedChargedR, _cachedChargedG, _cachedChargedB = r, g, b
            return r, g, b
        end
    end

    --- 2. Default: MidnightRogueBars purple
    _cachedChargedR, _cachedChargedG, _cachedChargedB = 0.60, 0.20, 0.80
    return 0.60, 0.20, 0.80
end

local COMBO_POINT_SLOT_TOKENS = {
    "COMBO_POINTS_1", "COMBO_POINTS_2", "COMBO_POINTS_3", "COMBO_POINTS_4",
    "COMBO_POINTS_5", "COMBO_POINTS_6", "COMBO_POINTS_7",
}
local COMBO_POINT_RAMP_R = { 0.00, 0.00, 1.00, 1.00, 1.00, 1.00, 1.00 }
local COMBO_POINT_RAMP_G = { 0.95, 0.95, 1.00, 1.00, 1.00, 0.05, 0.05 }
local COMBO_POINT_RAMP_B = { 1.00, 1.00, 0.00, 0.00, 0.00, 0.05, 0.05 }

local function ResolveSlotColorMode(powerToken, config)
    config = config or _cpDB
    local modes = config.slotColorModes
    local mode = modes and modes[powerToken]
    -- Preserve existing Rogue profiles and Assistant actions without copying
    -- the legacy value into every profile.
    if mode == nil and powerToken == "COMBO_POINTS" then mode = config.comboPointColorMode end
    if mode ~= "ramp" and mode ~= "custom" then return "default" end
    return mode
end

local function ResolveSlotColor(powerToken, slot, baseR, baseG, baseB, config)
    config = config or _cpDB
    local mode = ResolveSlotColorMode(powerToken, config)
    if mode ~= "ramp" and mode ~= "custom" then return nil end

    slot = tonumber(slot) or 1
    if slot < 1 then slot = 1 elseif slot > 10 then slot = 10 end

    if mode == "custom" then
        local slotToken = powerToken == "COMBO_POINTS" and COMBO_POINT_SLOT_TOKENS[slot]
            or (powerToken and (powerToken .. "_" .. tostring(slot)))
        local r, g, b = OverrideRGB(config.colorOverrides, slotToken or nil)
        if r then return r, g, b end
        if powerToken ~= "COMBO_POINTS" then return baseR, baseG, baseB end
    end

    -- The established Rogue ramp remains the fallback for untouched custom
    -- slots. Resources with 8-10 segments continue with its final red tier.
    local rampSlot = slot > 7 and 7 or slot
    return COMBO_POINT_RAMP_R[rampSlot] or baseR, COMBO_POINT_RAMP_G[rampSlot] or baseG, COMBO_POINT_RAMP_B[rampSlot] or baseB
end

local function ResolveFullResourceColor(powerToken, baseR, baseG, baseB, config)
    config = config or _cpDB
    local enabled = config.fullColorEnabled
    if not (powerToken and enabled and enabled[powerToken] == true) then return false, baseR, baseG, baseB end
    local r, g, b = OverrideRGB(config.colorOverrides, powerToken .. "_FULL")
    if r then return true, r, g, b end
    return true, baseR, baseG, baseB
end

-- Plain settings can describe a second surface without changing controller
-- caches. The live compiler and both menu surfaces call these same resolvers.
local shared = {
    OverrideRGB = OverrideRGB,
    ResolveSlotColorMode = ResolveSlotColorMode,
    ResolveSlotColor = ResolveSlotColor,
    ResolveFullColor = ResolveFullResourceColor,
    COMBO_POINT_SLOT_TOKENS = COMBO_POINT_SLOT_TOKENS,
    COMBO_POINT_RAMP_R = COMBO_POINT_RAMP_R,
    COMBO_POINT_RAMP_G = COMBO_POINT_RAMP_G,
    COMBO_POINT_RAMP_B = COMBO_POINT_RAMP_B,
}

--- Profile refresh/shutdown drop only the token caches; the charged and
--- Maelstrom caches survive until the next full invalidation.
local function CP_ResetColorTokens()
    _cachedColorToken = nil
    _cachedBgColorToken = nil
end

--- CONTROLLER_COLORS is built once at controller load. It binds the cached
--- config, starts the caches empty and publishes the Colors panel hook.
return function(E)
    _cpDB = E._cpDB
    POWER_TYPE_TOKENS = E.POWER_TYPE_TOKENS
    _cachedColorR, _cachedColorG, _cachedColorB = 1, 1, 1
    _cachedColorToken, _cachedBgColorToken = nil, nil
    _cachedBgColorR, _cachedBgColorG, _cachedBgColorB = 0, 0, 0
    _cachedChargedR, _cachedChargedG, _cachedChargedB = nil, nil, nil
    _mwAbove5R, _mwAbove5G, _mwAbove5B = nil, nil, nil
    _mwAbove5Resolved = false
    if not E.scene then
        ExportPublic("MSUF_ClassPower_InvalidateColors", MSUF_ClassPower_InvalidateColors)
    end
    return {
        ResolveMWAbove5Color = ResolveMWAbove5Color,
        ResolveClassPowerColor = ResolveClassPowerColor,
        ResolveClassPowerBgColor = ResolveClassPowerBgColor,
        InvalidateCaches = CP_InvalidateColorCaches,
        ResetTokens = CP_ResetColorTokens,
        ResolveChargedColor = ResolveChargedColor,
        ResolveSlotColorMode = ResolveSlotColorMode,
        ResolveSlotColor = ResolveSlotColor,
        ResolveFullResourceColor = ResolveFullResourceColor,
    }
end, shared
end

local CreateColorBuilder = builders.CONTROLLER_COLORS
local BuildLiveColors, liveShared = CreateColorBuilder()
MSUF.ClassPowerColors = liveShared
builders.CONTROLLER_COLORS = function(E)
    if E.scene then
        local build = CreateColorBuilder()
        return build(E)
    end
    return BuildLiveColors(E)
end
