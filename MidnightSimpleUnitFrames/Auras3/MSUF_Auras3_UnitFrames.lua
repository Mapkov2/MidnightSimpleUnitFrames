--- Auras3/MSUF_Auras3_UnitFrames.lua
--- Delta-first UnitFrame aura backend.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
_G.MSUF_NS = MSUF

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end
_G.MSUF_Auras3 = A3

local UF = MSUF.UF
if not (UF and UF.RegisterElement) then return end

if A3.__unitFrameBackendLoaded then return end
A3.__unitFrameBackendLoaded = true

local type, tostring, tonumber, pairs, next, select = type, tostring, tonumber, pairs, next, select
local math_floor, math_ceil, math_min, math_max = math.floor, math.ceil, math.min, math.max
local table_sort = table.sort
local wipe = table.wipe or wipe
local CreateFrame = _G.CreateFrame
local GameTooltip = _G.GameTooltip
local UnitExists = _G.UnitExists
local GetTime = _G.GetTime
local C_Timer = _G.C_Timer
local C_UnitAuras = _G.C_UnitAuras
local C_CurveUtil = _G.C_CurveUtil
local AuraUtil = _G.AuraUtil
local CreateColor = _G.CreateColor
local Enum = _G.Enum
local nativeSecrets = _G.issecretvalue ~= nil
local IsSecret = _G.issecretvalue or function() return false end

local GetAuraSlots = C_UnitAuras and C_UnitAuras.GetAuraSlots
local GetAuraDataBySlot = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot
local GetAuraDataByAuraInstanceID = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
local IsAuraFilteredOutByInstanceID = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID
local GetAuraDuration = C_UnitAuras and C_UnitAuras.GetAuraDuration
local GetAuraApplicationDisplayCount = C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount
local GetAuraDispelTypeColor = C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor

local BOSS_UNITS = {
    boss1 = true, boss2 = true, boss3 = true, boss4 = true, boss5 = true,
}
local MANAGED_UNITS = {
    player = true, target = true, focus = true,
    boss1 = true, boss2 = true, boss3 = true, boss4 = true, boss5 = true,
}
local EMPTY_EVENTS = {}
local COMBAT_AURA_EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }
local W8 = "Interface\\Buttons\\WHITE8X8"
local DEBUFF_OVERLAY_TEXTURE = "Interface\\Buttons\\UI-Debuff-Overlays"

local DISPEL_POINTS = {
    { 0, "None", 0.80, 0.00, 0.00 },
    { 1, "Magic", 0.20, 0.60, 1.00 },
    { 2, "Curse", 0.60, 0.00, 1.00 },
    { 3, "Disease", 0.60, 0.40, 0.00 },
    { 4, "Poison", 0.00, 0.60, 0.00 },
    { 9, "Enrage", 0.95, 0.37, 0.96 },
    { 11, "Bleed", 0.80, 0.10, 0.10 },
}

local SATED_SPELLS = {
    [57723] = true, -- Exhaustion
    [57724] = true, -- Sated
    [80354] = true, -- Temporal Displacement
    [95809] = true, -- Insanity
    [160455] = true, -- Fatigued
    [264689] = true, -- Fatigued
}

local UNIT_FLAG = {
    player = "showPlayer",
    target = "showTarget",
    focus = "showFocus",
    boss1 = "showBoss",
    boss2 = "showBoss",
    boss3 = "showBoss",
    boss4 = "showBoss",
    boss5 = "showBoss",
}

local DEFAULT_SHARED = {
    showBuffs = true,
    showDebuffs = true,
    showTooltip = true,
    showCooldownSwipe = true,
    showCooldownText = true,
    showStackCount = true,
    buffShowCooldownSwipe = true,
    buffShowCooldownText = true,
    buffShowStackCount = true,
    debuffShowCooldownSwipe = true,
    debuffShowCooldownText = true,
    debuffShowStackCount = true,
    clickThroughAuras = false,
    iconSize = 26,
    spacing = 2,
    perRow = 12,
    maxBuffs = 12,
    maxDebuffs = 12,
    sortOrder = 0,
    growth = "RIGHT",
    rowWrap = "DOWN",
    offsetX = 0,
    offsetY = 6,
    buffOffsetX = 0,
    buffOffsetY = 30,
    buffGroupOffsetX = 0,
    buffGroupOffsetY = 36,
    debuffGroupOffsetX = 0,
    debuffGroupOffsetY = 6,
    buffGroupIconSize = 26,
    debuffGroupIconSize = 26,
    buffAnchor = "BOTTOMRIGHT",
    debuffAnchor = "TOPLEFT",
    buffLayer = 5,
    debuffLayer = 6,
    stackCountAnchor = "TOPRIGHT",
    buffStackCountAnchor = "TOPRIGHT",
    debuffStackCountAnchor = "TOPRIGHT",
    stackTextSize = 14,
    stackTextOffsetX = -1,
    stackTextOffsetY = 1,
    cooldownTextSize = 14,
    cooldownTextOffsetX = 0,
    cooldownTextOffsetY = 0,
    buffStackTextSize = 14,
    buffStackTextOffsetX = -1,
    buffStackTextOffsetY = 1,
    buffCooldownTextSize = 14,
    buffCooldownTextOffsetX = 0,
    buffCooldownTextOffsetY = 0,
    debuffStackTextSize = 14,
    debuffStackTextOffsetX = -1,
    debuffStackTextOffsetY = 1,
    debuffCooldownTextSize = 14,
    debuffCooldownTextOffsetX = 0,
    debuffCooldownTextOffsetY = 0,
}

local LANE_SPECS = {
    buff = {
        dbKey = "buffs",
        filter = "HELPFUL",
        showKey = "showBuffs",
        maxKey = "maxBuffs",
        xKey = "buffGroupOffsetX",
        yKey = "buffGroupOffsetY",
        sizeKey = "buffGroupIconSize",
        anchorKey = "buffAnchor",
        layerKey = "buffLayer",
        perRowKey = "buffPerRow",
        growthKey = "buffGrowthX",
        wrapKey = "buffGrowthY",
        stackAnchorKey = "buffStackCountAnchor",
        showSwipeKey = "buffShowCooldownSwipe",
        showTextKey = "buffShowCooldownText",
        showStackKey = "buffShowStackCount",
        stackSizeKey = "buffStackTextSize",
        stackXKey = "buffStackTextOffsetX",
        stackYKey = "buffStackTextOffsetY",
        cooldownSizeKey = "buffCooldownTextSize",
        cooldownXKey = "buffCooldownTextOffsetX",
        cooldownYKey = "buffCooldownTextOffsetY",
        defaultAnchor = "BOTTOMRIGHT",
        defaultLayer = 5,
        harmful = false,
    },
    debuff = {
        dbKey = "debuffs",
        filter = "HARMFUL",
        showKey = "showDebuffs",
        maxKey = "maxDebuffs",
        xKey = "debuffGroupOffsetX",
        yKey = "debuffGroupOffsetY",
        sizeKey = "debuffGroupIconSize",
        anchorKey = "debuffAnchor",
        layerKey = "debuffLayer",
        perRowKey = "debuffPerRow",
        growthKey = "debuffGrowthX",
        wrapKey = "debuffGrowthY",
        stackAnchorKey = "debuffStackCountAnchor",
        showSwipeKey = "debuffShowCooldownSwipe",
        showTextKey = "debuffShowCooldownText",
        showStackKey = "debuffShowStackCount",
        stackSizeKey = "debuffStackTextSize",
        stackXKey = "debuffStackTextOffsetX",
        stackYKey = "debuffStackTextOffsetY",
        cooldownSizeKey = "debuffCooldownTextSize",
        cooldownXKey = "debuffCooldownTextOffsetX",
        cooldownYKey = "debuffCooldownTextOffsetY",
        defaultAnchor = "TOPLEFT",
        defaultLayer = 6,
        harmful = true,
    },
}

local GROUP_LANE_SPECS = {
    buff = {
        filter = "HELPFUL|RAID",
        showKey = "showBuffs",
        maxKey = "maxBuffs",
        sizeKey = "buffIconSize",
        spacingKey = "buffSpacing",
        perRowKey = "buffPerRow",
        growthXKey = "buffGrowthX",
        growthYKey = "buffGrowthY",
        anchorKey = "buffAnchor",
        xKey = "buffOffsetX",
        yKey = "buffOffsetY",
        layerKey = "buffLayer",
        alphaKey = "buffAlpha",
        filterKey = "buffFilter",
        blacklistKey = "buffBlacklistHash",
        showSwipeKey = "buffShowCooldownSwipe",
        showCooldownKey = "buffShowCooldown",
        showStackKey = "buffShowStacks",
        cooldownSizeKey = "buffCooldownSize",
        cooldownAnchorKey = "buffCooldownAnchor",
        stackSizeKey = "buffStackSize",
        defaultAnchor = "BOTTOMRIGHT",
        defaultLayer = 5,
        defaultMax = 4,
        defaultSize = 16,
        defaultPerRow = 4,
        harmful = false,
    },
    debuff = {
        filter = "HARMFUL",
        showKey = "showDebuffs",
        maxKey = "maxDebuffs",
        sizeKey = "debuffIconSize",
        spacingKey = "debuffSpacing",
        perRowKey = "debuffPerRow",
        growthXKey = "debuffGrowthX",
        growthYKey = "debuffGrowthY",
        anchorKey = "debuffAnchor",
        xKey = "debuffOffsetX",
        yKey = "debuffOffsetY",
        layerKey = "debuffLayer",
        alphaKey = "debuffAlpha",
        filterKey = "debuffFilter",
        blacklistKey = "debuffBlacklistHash",
        showSwipeKey = "debuffShowCooldownSwipe",
        showCooldownKey = "debuffShowCooldown",
        showStackKey = "debuffShowStacks",
        cooldownSizeKey = "debuffCooldownSize",
        cooldownAnchorKey = "debuffCooldownAnchor",
        stackSizeKey = "debuffStackSize",
        defaultAnchor = "TOPLEFT",
        defaultLayer = 6,
        defaultMax = 4,
        defaultSize = 16,
        defaultPerRow = 3,
        harmful = true,
    },
}

local function WipeTable(tbl)
    if not tbl then return {} end
    if wipe then return wipe(tbl) end
    for k in pairs(tbl) do tbl[k] = nil end
    return tbl
end

local function FillAuraSlots(out, ...)
    out = WipeTable(out)
    local count = select("#", ...)
    for i = 1, count do
        out[i] = select(i, ...)
    end
    return out, count
end

local function ClampNumber(value, defaultValue, minValue, maxValue)
    value = tonumber(value)
    if value == nil then value = defaultValue end
    if minValue and value < minValue then value = minValue end
    if maxValue and value > maxValue then value = maxValue end
    return value
end

local function Clamp01(value, defaultValue)
    value = tonumber(value)
    if value == nil then value = defaultValue end
    if value == nil then value = 1 end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function PlainNumber(value)
    if IsSecret(value) then return nil end
    return type(value) == "number" and value or nil
end

local function PlainString(value)
    if IsSecret(value) then return nil end
    return type(value) == "string" and value or nil
end

local function PlainBool(value)
    if IsSecret(value) then return nil end
    if value == true then return true end
    if value == false then return false end
    return nil
end

local function ReadGeneralColor(key, defaultR, defaultG, defaultB)
    local general = _G.MSUF_DB and _G.MSUF_DB.general
    local value = general and general[key]
    if type(value) == "table" then
        return Clamp01(value[1], defaultR), Clamp01(value[2], defaultG), Clamp01(value[3], defaultB)
    end
    return defaultR or 1, defaultG or 1, defaultB or 1
end

local function NormalizeDispelTrigger(value, fallback)
    value = tostring(value or ""):upper()
    if value == "BORDER" or value == "INHERIT" or value == "SAME" then
        return "BORDER"
    elseif value == "DISPEL_TYPE" or value == "TYPE" or value == "ANY_DISPEL_TYPE" then
        return "DISPEL_TYPE"
    elseif value == "ANY_DEBUFF" or value == "DEBUFF" or value == "ANY" or value == "ALL_DEBUFFS" then
        return "ANY_DEBUFF"
    elseif value == "PLAYER_CAST" or value == "CAST_BY_ME" or value == "MY_DEBUFF" then
        return "PLAYER_CAST"
    elseif value == "BY_ME" or value == "PLAYER" or value == "DISPELLABLE_BY_ME" then
        return "BY_ME"
    end
    return fallback or "BY_ME"
end

local function DispelColorValue(spec, key, fallback)
    local value = spec and spec[key]
    value = tonumber(value)
    if value == nil then value = fallback end
    return Clamp01(value, fallback)
end

local function AddDispelCurvePoint(curve, index, r, g, b, a)
    if not (curve and curve.AddPoint and CreateColor) then return end
    curve:AddPoint(index, CreateColor(Clamp01(r, 1), Clamp01(g, 1), Clamp01(b, 1), Clamp01(a, 1)))
end

local function BuildDispelColorCurve(spec)
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local curve = C_CurveUtil.CreateColorCurve()
    if not curve then return nil end
    if curve.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then
        curve:SetType(Enum.LuaCurveType.Step)
    end
    AddDispelCurvePoint(curve, 0, DispelColorValue(spec, "typeNoneR", 0.80), DispelColorValue(spec, "typeNoneG", 0.00), DispelColorValue(spec, "typeNoneB", 0.00), 1)
    for i = 2, #DISPEL_POINTS do
        local point = DISPEL_POINTS[i]
        local key = "type" .. point[2]
        AddDispelCurvePoint(curve, point[1],
            DispelColorValue(spec, key .. "R", point[3]),
            DispelColorValue(spec, key .. "G", point[4]),
            DispelColorValue(spec, key .. "B", point[5]),
            1)
    end
    return curve
end

local function CompileDispelVisual(spec)
    local visual = type(spec) == "table" and spec or nil
    local mode = visual and visual.colorMode == "TYPE" and "TYPE" or "SINGLE"
    return {
        colorMode = mode,
        r = DispelColorValue(visual, "r", 0.25),
        g = DispelColorValue(visual, "g", 0.75),
        b = DispelColorValue(visual, "b", 1.00),
        a = DispelColorValue(visual, "a", 1.00),
        dispelColorCurve = BuildDispelColorCurve(visual),
    }
end

local function ColorObjectRGBA(color)
    if not color then return nil end
    if color.GetRGBA then
        return color:GetRGBA()
    end
    return color.r, color.g, color.b, color.a
end

local function HasSecretColor(r, g, b, a)
    return IsSecret(r) or IsSecret(g) or IsSecret(b) or IsSecret(a)
end

local function Round(value)
    value = tonumber(value) or 0
    if value < 0 then return -math_floor((-value) + 0.5) end
    return math_floor(value + 0.5)
end

local function NormalizeRuntimeUnit(unit)
    unit = tostring(unit or "player")
    if unit == "boss" then return "boss1" end
    if BOSS_UNITS[unit] or unit == "player" or unit == "target" or unit == "focus" then
        return unit
    end
    return nil
end

local function NormalizeConfigUnit(unit)
    unit = NormalizeRuntimeUnit(unit)
    return BOSS_UNITS[unit] and "boss" or unit
end

local function IsGroupFrame(frame)
    if not frame then return false end
    if frame._msufCoreScope == "group" or frame._msufIsGroupFrame == true then return true end
    local spec = frame.MSUFSpec
    return spec and spec.scope == "group" or false
end

local function EachRuntimeUnit(unit, fn)
    unit = tostring(unit or "")
    if unit == "" or unit == "*" then
        fn("player")
        fn("target")
        fn("focus")
        for i = 1, 5 do fn("boss" .. i) end
        return
    end
    if unit == "boss" then
        for i = 1, 5 do fn("boss" .. i) end
        return
    end
    unit = NormalizeRuntimeUnit(unit)
    if unit then fn(unit) end
end

local function EnsureRootDB()
    local db = _G.MSUF_DB
    if type(db) ~= "table" then
        db = {}
        _G.MSUF_DB = db
    end
    if type(db.auras3) ~= "table" then db.auras3 = {} end
    local auras = db.auras3
    if type(auras.shared) ~= "table" then auras.shared = {} end
    if type(auras.perUnit) ~= "table" then auras.perUnit = {} end
    if auras.enabled == nil then auras.enabled = true end
    if auras.showPlayer == nil then auras.showPlayer = false end
    if auras.showTarget == nil then auras.showTarget = true end
    if auras.showFocus == nil then auras.showFocus = true end
    if auras.showBoss == nil then auras.showBoss = true end
    return auras, auras.shared
end

local function ReadRaw(primary, secondary, key)
    if primary and primary[key] ~= nil then return primary[key] end
    if secondary and secondary[key] ~= nil then return secondary[key] end
    return nil
end

local function ReadShared(shared, key)
    local v = shared and shared[key]
    if v == nil then v = DEFAULT_SHARED[key] end
    return v
end

local function ReadBool(primary, secondary, key, defaultValue)
    local v = ReadRaw(primary, secondary, key)
    if v == nil then return defaultValue and true or false end
    return v == true
end

local function ReadNumber(primary, secondary, key, defaultValue, minValue, maxValue)
    local v = ReadRaw(primary, secondary, key)
    return ClampNumber(v, defaultValue, minValue, maxValue)
end

local function ReadAnchor(primary, secondary, key, fallback)
    local value = ReadRaw(primary, secondary, key) or fallback or "TOPLEFT"
    if value ~= "TOPLEFT" and value ~= "TOPRIGHT" and value ~= "BOTTOMLEFT"
        and value ~= "BOTTOMRIGHT" and value ~= "CENTER" then
        value = fallback or "TOPLEFT"
    end
    return value
end

local function GrowthParts(growth, rowWrap)
    if growth ~= "LEFT" and growth ~= "UP" and growth ~= "DOWN" then growth = "RIGHT" end
    if rowWrap ~= "UP" then rowWrap = "DOWN" end
    local xSign = growth == "LEFT" and -1 or 1
    local ySign = rowWrap == "UP" and 1 or -1
    if growth == "UP" or growth == "DOWN" then
        xSign = 1
        ySign = growth == "UP" and 1 or -1
    end
    return growth, rowWrap, xSign, ySign
end

local function GroupGrowthParts(growthX, growthY)
    if growthX ~= "LEFT" and growthX ~= "UP" and growthX ~= "DOWN" then growthX = "RIGHT" end
    if growthY ~= "UP" then growthY = "DOWN" end
    local xSign = growthX == "LEFT" and -1 or 1
    local ySign = growthY == "UP" and 1 or -1
    if growthX == "UP" or growthX == "DOWN" then
        xSign = 1
        ySign = growthX == "UP" and 1 or -1
    end
    return growthX, growthY, xSign, ySign
end

local function ButtonAnchor(xSign, ySign)
    if ySign > 0 then
        return xSign < 0 and "BOTTOMRIGHT" or "BOTTOMLEFT"
    end
    return xSign < 0 and "TOPRIGHT" or "TOPLEFT"
end

local function EffectiveTables(auras, runtimeUnit)
    local pu = auras and auras.perUnit and auras.perUnit[runtimeUnit]
    local shared = auras and auras.shared
    local layout = pu and pu.overrideLayout == true and type(pu.layout) == "table" and pu.layout or nil
    local sharedLayout = pu and pu.overrideSharedLayout == true and type(pu.layoutShared) == "table" and pu.layoutShared or nil
    local blacklist = nil
    if pu and pu.overrideBlacklist == true and type(pu.blacklist) == "table" then
        blacklist = pu.blacklist
    else
        blacklist = shared and shared.blacklist
    end
    local filters = nil
    if pu and pu.overrideFilters == true and type(pu.filters) == "table" then
        filters = pu.filters
    else
        filters = shared and shared.filters
    end
    return layout, sharedLayout, blacklist, filters
end

local function CompileBlacklist(blacklist)
    local spells = type(blacklist) == "table" and blacklist.spells
    if type(spells) ~= "table" then return nil end
    local out, n = nil, 0
    for key, enabled in pairs(spells) do
        if enabled == true then
            local id = tonumber(key)
            if id then
                if not out then out = {} end
                out[math_floor(id + 0.5)] = true
                n = n + 1
            end
        end
    end
    return n > 0 and out or nil
end

local function FilterTable(filtersRoot, dbKey)
    local root = type(filtersRoot) == "table" and filtersRoot or nil
    if not root or root.enabled == false then return nil end
    local filters = root[dbKey]
    return type(filters) == "table" and filters or nil
end

local SortAuras, SortAurasID, SortComparator

local function CompileFrameAuraVisual(spec)
    if type(spec) ~= "table" then return nil end
    local group = spec.scope == "group" and spec.group or nil
    local border = spec.border
    local dispel = CompileDispelVisual(spec.dispel)
    local unitOverlay = spec.dispelOverlay

    local borderEnabled = border and border.dispel == true
    local overlayEnabled
    local overlayTrigger
    local overlayStyle
    local overlayAlpha
    local overlayOnHealth
    local stripeEnabled
    local stripeEdge
    local stripeHeight
    local stripeAlpha
    local stripeR
    local stripeG
    local stripeB

    if group then
        overlayEnabled = group.dispelOverlayEnabled == true
        overlayTrigger = NormalizeDispelTrigger(group.dispelOverlayTrigger, "BORDER")
        overlayStyle = group.dispelOverlayStyle or "FULL"
        overlayAlpha = Clamp01(group.dispelOverlayAlpha, 0.35)
        overlayOnHealth = group.dispelOverlayOnHealth ~= false
        stripeEnabled = group.debuffStripeEnabled == true
        stripeEdge = group.debuffStripeEdge or "BOTTOM"
        stripeHeight = ClampNumber(group.debuffStripeHeight, 3, 1, 32)
        stripeAlpha = Clamp01(group.debuffStripeAlpha, 0.6)
        stripeR = Clamp01(group.debuffStripeColorR, 0.8)
        stripeG = Clamp01(group.debuffStripeColorG, 0.2)
        stripeB = Clamp01(group.debuffStripeColorB, 0.2)
    else
        overlayEnabled = unitOverlay and unitOverlay.enabled == true
        overlayTrigger = NormalizeDispelTrigger(unitOverlay and unitOverlay.trigger, "BORDER")
        overlayStyle = unitOverlay and unitOverlay.style or "FULL"
        overlayAlpha = Clamp01(unitOverlay and unitOverlay.alpha, 0.35)
        overlayOnHealth = not unitOverlay or unitOverlay.onHealth ~= false
        stripeEnabled = false
    end

    if overlayStyle ~= "TOP" and overlayStyle ~= "BOTTOM" and overlayStyle ~= "LEFT" and overlayStyle ~= "RIGHT" then
        overlayStyle = "FULL"
    end
    if stripeEdge ~= "TOP" and stripeEdge ~= "LEFT" and stripeEdge ~= "RIGHT" then
        stripeEdge = "BOTTOM"
    end

    local borderTrigger = NormalizeDispelTrigger(border and border.dispelTrigger, "BY_ME")
    local overlayActualTrigger = overlayTrigger == "BORDER" and borderTrigger or overlayTrigger
    local needsScan = borderEnabled == true or overlayEnabled == true or stripeEnabled == true
    if not needsScan then return nil end

    return {
        enabled = true,
        borderEnabled = borderEnabled == true,
        overlayEnabled = overlayEnabled == true,
        stripeEnabled = stripeEnabled == true,
        borderTrigger = borderTrigger,
        overlayTrigger = overlayActualTrigger,
        needsPlayerFlag = borderTrigger == "PLAYER_CAST" or overlayActualTrigger == "PLAYER_CAST",
        colorMode = dispel.colorMode,
        r = dispel.r,
        g = dispel.g,
        b = dispel.b,
        a = dispel.a,
        dispelColorCurve = dispel.dispelColorCurve,
        overlayStyle = overlayStyle,
        overlayAlpha = overlayAlpha,
        overlayOnHealth = overlayOnHealth == true,
        stripeEdge = stripeEdge,
        stripeHeight = stripeHeight,
        stripeAlpha = stripeAlpha,
        stripeR = stripeR,
        stripeG = stripeG,
        stripeB = stripeB,
    }
end

local function CompileLane(runtimeUnit, shared, layout, sharedLayout, blacklist, filtersRoot, kind, forceScan, visual, renderAllowed)
    local spec = LANE_SPECS[kind]
    local sizeDefault = tonumber(ReadRaw(layout, shared, spec.sizeKey))
        or tonumber(ReadRaw(layout, shared, "iconSize"))
        or DEFAULT_SHARED.iconSize
    local size = ClampNumber(sizeDefault, DEFAULT_SHARED.iconSize, 1, 128)
    local spacing = ReadNumber(layout, shared, "spacing", DEFAULT_SHARED.spacing, 0, 64)
    local perRow = ReadNumber(sharedLayout, shared, spec.perRowKey, ReadShared(shared, "perRow"), 1, 40)
    local maxCount = ReadNumber(sharedLayout, shared, spec.maxKey, DEFAULT_SHARED[spec.maxKey] or 12, 0, 80)
    local show = ReadBool(sharedLayout, shared, spec.showKey, true)
    local legacyGrowthKey = kind == "buff" and "buffGrowth" or "debuffGrowth"
    local legacyWrapKey = kind == "buff" and "buffRowWrap" or "debuffRowWrap"
    local growth = ReadRaw(sharedLayout, shared, spec.growthKey)
        or ReadRaw(sharedLayout, shared, legacyGrowthKey)
        or ReadRaw(sharedLayout, shared, "growth")
        or DEFAULT_SHARED.growth
    local rowWrap = ReadRaw(sharedLayout, shared, spec.wrapKey)
        or ReadRaw(sharedLayout, shared, legacyWrapKey)
        or ReadRaw(sharedLayout, shared, "rowWrap")
        or DEFAULT_SHARED.rowWrap
    local growthX, growthY, xSign, ySign = GrowthParts(growth, rowWrap)
    local x = ReadNumber(layout, shared, spec.xKey, DEFAULT_SHARED[spec.xKey] or 0, -4096, 4096)
    local y = ReadNumber(layout, shared, spec.yKey, DEFAULT_SHARED[spec.yKey] or 0, -4096, 4096)
    local anchor = ReadAnchor(layout, shared, spec.anchorKey, spec.defaultAnchor)
    local layer = ReadNumber(layout, shared, spec.layerKey, spec.defaultLayer, 1, 15)
    local stackAnchor = ReadAnchor(sharedLayout, shared, spec.stackAnchorKey, ReadShared(shared, "stackCountAnchor") or "TOPRIGHT")
    local filters = FilterTable(filtersRoot, spec.dbKey)
    local rootFilters = type(filtersRoot) == "table" and filtersRoot or nil
    local exclusive = filters and filters.exclusive
    local onlyImportant = filters and (filters.onlyImportant == true or exclusive == "important")
    local onlyMine = filters and filters.onlyMine == true
    local raid = filters and filters.raid == true
    local includeStealable = kind == "buff" and filters and filters.includeStealable == true
    local boss = filters and (filters.boss == true or filters.includeBoss == true)
    local onlyBoss = rootFilters and rootFilters.onlyBossAuras == true
    local hidePermanent = kind == "buff" and rootFilters and rootFilters.hidePermanent == true
    local showSated = kind ~= "buff" or ReadBool(nil, shared, "showSated", true)
    local satedThreshold = kind == "buff" and ReadNumber(nil, shared, "satedShowAtSeconds", 0, 0, 3600) or 0
    local satedFilter = kind == "buff" and (showSated ~= true or satedThreshold > 0)
    local ownHighlight = kind == "buff"
        and ReadBool(nil, shared, "highlightOwnBuffs", false)
        or (kind == "debuff" and ReadBool(nil, shared, "highlightOwnDebuffs", false))
    local raidInCombat = filters and (
        filters.raidInCombat == true
        or filters.raidInCombatPlayer == true
        or filters.RaidInCombat == true
        or filters.RaidInCombatPlayer == true
    )
    local visualNeedsPlayer = kind == "debuff" and visual and visual.needsPlayerFlag == true
    local hasInclusive = onlyMine or raid or includeStealable or boss or raidInCombat
    local black = CompileBlacklist(blacklist)
    local renderEnabled = renderAllowed ~= false and show and maxCount > 0
    local enabled = renderEnabled or (forceScan == true and kind == "debuff")
    local step = size + spacing
    local cols = math_min(math_max(maxCount, 1), math_max(perRow, 1))
    local rows = math_ceil(math_max(maxCount, 1) / math_max(perRow, 1))
    local sortOrder = ReadNumber(sharedLayout, shared, "sortOrder", DEFAULT_SHARED.sortOrder, 0, 6)
    local showCooldownSwipe = ReadBool(sharedLayout, shared, spec.showSwipeKey, ReadShared(shared, "showCooldownSwipe") ~= false)
    local showCooldownText = ReadBool(sharedLayout, shared, spec.showTextKey, ReadShared(shared, "showCooldownText") ~= false)
    local cooldownSwipeDarken = ReadBool(nil, shared, "cooldownSwipeDarkenOnLoss", false)
    local stackR, stackG, stackB = ReadGeneralColor("aurasStackCountColor", 1, 1, 1)
    local ownR, ownG, ownB = 1, 1, 1
    if ownHighlight == true then
        if kind == "buff" then
            ownR, ownG, ownB = ReadGeneralColor("aurasOwnBuffHighlightColor", 1, 0.85, 0.20)
        else
            ownR, ownG, ownB = ReadGeneralColor("aurasOwnDebuffHighlightColor", 1, 0.30, 0.30)
        end
    end
    local general = _G.MSUF_DB and _G.MSUF_DB.general
    local cooldownTextBuckets = general and general.aurasCooldownTextUseBuckets == true
    local cooldownSafeR, cooldownSafeG, cooldownSafeB = 1, 1, 1
    local cooldownWarnR, cooldownWarnG, cooldownWarnB = 1, 0.85, 0.20
    local cooldownUrgentR, cooldownUrgentG, cooldownUrgentB = 1, 0.55, 0.10
    if cooldownTextBuckets == true then
        cooldownSafeR, cooldownSafeG, cooldownSafeB = ReadGeneralColor("aurasCooldownTextSafeColor", 1, 1, 1)
        cooldownWarnR, cooldownWarnG, cooldownWarnB = ReadGeneralColor("aurasCooldownTextWarningColor", 1, 0.85, 0.20)
        cooldownUrgentR, cooldownUrgentG, cooldownUrgentB = ReadGeneralColor("aurasCooldownTextUrgentColor", 1, 0.55, 0.10)
    end
    local baseFilter = onlyBoss and (spec.filter .. "|BOSS") or spec.filter
    local showDispelTypeBorder = kind == "debuff" and renderEnabled == true and ReadBool(nil, shared, "useDebuffTypeBorders", false)
    local dispelVisual = (kind == "debuff" and (visual or (showDispelTypeBorder and CompileDispelVisual(nil)))) or nil
    local needsPlayerFlag = onlyMine == true or ownHighlight == true or visualNeedsPlayer == true
    local sortComparator = sortOrder == 0 and (needsPlayerFlag and SortAuras or SortAurasID) or SortComparator(Round(sortOrder))

    return {
        kind = kind,
        unit = runtimeUnit,
        enabled = enabled == true,
        renderEnabled = renderEnabled == true,
        harmful = spec.harmful == true,
        filter = baseFilter,
        playerFilter = baseFilter .. "|PLAYER",
        importantFilter = baseFilter .. "|IMPORTANT",
        raidFilter = baseFilter .. "|RAID",
        raidInCombatFilter = baseFilter .. "|RAID_IN_COMBAT",
        stealableFilter = "HELPFUL|STEALABLE",
        dispellableFilter = "HARMFUL|RAID_PLAYER_DISPELLABLE",
        bossFilter = spec.filter .. "|BOSS",
        max = renderEnabled and Round(maxCount) or 0,
        size = size,
        spacing = spacing,
        step = step,
        perRow = Round(perRow),
        cols = cols,
        rows = rows,
        width = math_max(1, cols * size + math_max(cols - 1, 0) * spacing),
        height = math_max(1, rows * size + math_max(rows - 1, 0) * spacing),
        x = Round(x),
        y = Round(y),
        anchor = anchor,
        layer = Round(layer),
        growthX = growthX,
        growthY = growthY,
        xSign = xSign,
        ySign = ySign,
        initialAnchor = ButtonAnchor(xSign, ySign),
        sortOrder = Round(sortOrder),
        sortComparator = sortComparator,
        naturalOrder = sortOrder == 0 and needsPlayerFlag ~= true,
        reorderOnUpdate = sortOrder ~= 0,
        ownHighlight = ownHighlight == true,
        ownR = ownR,
        ownG = ownG,
        ownB = ownB,
        clickThrough = ReadBool(nil, shared, "clickThroughAuras", false),
        showTooltip = ReadBool(nil, shared, "showTooltip", true),
        showCooldownSwipe = showCooldownSwipe,
        showCooldownText = showCooldownText,
        showCooldown = renderEnabled == true and (showCooldownSwipe ~= false or showCooldownText ~= false),
        cooldownSwipeDarken = cooldownSwipeDarken == true,
        cooldownTextBuckets = cooldownTextBuckets,
        cooldownSafeR = cooldownSafeR,
        cooldownSafeG = cooldownSafeG,
        cooldownSafeB = cooldownSafeB,
        cooldownWarnR = cooldownWarnR,
        cooldownWarnG = cooldownWarnG,
        cooldownWarnB = cooldownWarnB,
        cooldownUrgentR = cooldownUrgentR,
        cooldownUrgentG = cooldownUrgentG,
        cooldownUrgentB = cooldownUrgentB,
        cooldownSafeSeconds = ClampNumber(general and general.aurasCooldownTextSafeSeconds, 60, 0, 600),
        cooldownWarningSeconds = ClampNumber(general and general.aurasCooldownTextWarningSeconds, 15, 0, 60),
        cooldownUrgentSeconds = ClampNumber(general and general.aurasCooldownTextUrgentSeconds, 5, 0, 60),
        cooldownSize = ReadNumber(layout, shared, spec.cooldownSizeKey, ReadShared(shared, "cooldownTextSize") or DEFAULT_SHARED.cooldownTextSize, 6, 40),
        cooldownX = ReadNumber(layout, shared, spec.cooldownXKey, ReadShared(shared, "cooldownTextOffsetX") or DEFAULT_SHARED.cooldownTextOffsetX, -2000, 2000),
        cooldownY = ReadNumber(layout, shared, spec.cooldownYKey, ReadShared(shared, "cooldownTextOffsetY") or DEFAULT_SHARED.cooldownTextOffsetY, -2000, 2000),
        showStacks = ReadBool(sharedLayout, shared, spec.showStackKey, ReadShared(shared, "showStackCount") ~= false),
        stackAnchor = stackAnchor,
        stackSize = ReadNumber(layout, shared, spec.stackSizeKey, ReadShared(shared, "stackTextSize"), 6, 40),
        stackX = ReadNumber(layout, shared, spec.stackXKey, ReadShared(shared, "stackTextOffsetX"), -2000, 2000),
        stackY = ReadNumber(layout, shared, spec.stackYKey, ReadShared(shared, "stackTextOffsetY"), -2000, 2000),
        stackR = stackR,
        stackG = stackG,
        stackB = stackB,
        blacklist = black,
        hasFilterWork = black ~= nil or onlyImportant or hasInclusive or hidePermanent or satedFilter,
        exclusiveImportant = exclusive == "important",
        onlyImportant = onlyImportant == true,
        onlyMine = onlyMine == true,
        raid = raid == true,
        includeStealable = includeStealable == true,
        boss = boss == true,
        hidePermanent = hidePermanent == true,
        showSated = showSated == true,
        satedThreshold = satedThreshold,
        satedFilter = satedFilter == true,
        raidInCombat = raidInCombat == true,
        hasInclusive = hasInclusive == true,
        needsPlayerFlag = needsPlayerFlag,
        needsCombatRefresh = raidInCombat == true,
        visual = kind == "debuff" and visual or nil,
        showDispelTypeBorder = showDispelTypeBorder == true,
        dispelColorCurve = dispelVisual and dispelVisual.dispelColorCurve or nil,
    }
end

local function CompileGroupLane(unit, source, kind, forceScan, visual, renderAllowed)
    local spec = GROUP_LANE_SPECS[kind]
    source = type(source) == "table" and source or nil
    if not (spec and source) then return nil end

    local size = ClampNumber(source[spec.sizeKey], spec.defaultSize, 1, 128)
    local spacing = ClampNumber(source[spec.spacingKey] or source.spacing, DEFAULT_SHARED.spacing, 0, 64)
    local perRow = ClampNumber(source[spec.perRowKey] or source.perRow, spec.defaultPerRow, 1, 40)
    local maxCount = ClampNumber(source[spec.maxKey], spec.defaultMax, 0, 80)
    local renderEnabled = renderAllowed ~= false and source[spec.showKey] == true and maxCount > 0
    local enabled = renderEnabled or (forceScan == true and kind == "debuff")
    local growthX, growthY, xSign, ySign = GroupGrowthParts(source[spec.growthXKey], source[spec.growthYKey])
    local x = ClampNumber(source[spec.xKey], 0, -4096, 4096)
    local y = ClampNumber(source[spec.yKey], 0, -4096, 4096)
    local anchor = source[spec.anchorKey] or spec.defaultAnchor
    if anchor ~= "TOPLEFT" and anchor ~= "TOPRIGHT" and anchor ~= "BOTTOMLEFT"
        and anchor ~= "BOTTOMRIGHT" and anchor ~= "CENTER" then
        anchor = spec.defaultAnchor
    end
    local layer = ClampNumber(source[spec.layerKey], spec.defaultLayer, 1, 15)
    local alpha = ClampNumber(source[spec.alphaKey], 1, 0, 1)
    local filter = source[spec.filterKey] or spec.filter
    local black = type(source[spec.blacklistKey]) == "table" and source[spec.blacklistKey] or nil
    local showCooldown = source[spec.showCooldownKey] ~= false
    local showCooldownSwipe = showCooldown and source[spec.showSwipeKey] ~= false
    local stackR, stackG, stackB = ReadGeneralColor("aurasStackCountColor", 1, 1, 1)
    local general = _G.MSUF_DB and _G.MSUF_DB.general
    local cooldownTextBuckets = general and general.aurasCooldownTextUseBuckets == true
    local cooldownSafeR, cooldownSafeG, cooldownSafeB = 1, 1, 1
    local cooldownWarnR, cooldownWarnG, cooldownWarnB = 1, 0.85, 0.20
    local cooldownUrgentR, cooldownUrgentG, cooldownUrgentB = 1, 0.55, 0.10
    if cooldownTextBuckets == true then
        cooldownSafeR, cooldownSafeG, cooldownSafeB = ReadGeneralColor("aurasCooldownTextSafeColor", 1, 1, 1)
        cooldownWarnR, cooldownWarnG, cooldownWarnB = ReadGeneralColor("aurasCooldownTextWarningColor", 1, 0.85, 0.20)
        cooldownUrgentR, cooldownUrgentG, cooldownUrgentB = ReadGeneralColor("aurasCooldownTextUrgentColor", 1, 0.55, 0.10)
    end
    local step = size + spacing
    local cols = math_min(math_max(maxCount, 1), math_max(perRow, 1))
    local rows = math_ceil(math_max(maxCount, 1) / math_max(perRow, 1))
    local sortOrder = source.sortByDuration == true and 2 or 0
    local showDispelTypeBorder = kind == "debuff" and renderEnabled == true and source.debuffShowDispelBorder == true
    local dispelVisual = (kind == "debuff" and (visual or (showDispelTypeBorder and CompileDispelVisual(nil)))) or nil
    local needsPlayerFlag = source.preferPlayer == true or (kind == "debuff" and visual and visual.needsPlayerFlag == true)

    return {
        kind = kind,
        unit = unit,
        enabled = enabled == true,
        renderEnabled = renderEnabled == true,
        harmful = spec.harmful == true,
        filter = filter,
        playerFilter = filter .. "|PLAYER",
        importantFilter = filter .. "|IMPORTANT",
        raidFilter = filter .. "|RAID",
        raidInCombatFilter = filter .. "|RAID_IN_COMBAT",
        stealableFilter = "HELPFUL|STEALABLE",
        dispellableFilter = "HARMFUL|RAID_PLAYER_DISPELLABLE",
        bossFilter = "HARMFUL|BOSS",
        max = renderEnabled and Round(maxCount) or 0,
        size = size,
        spacing = spacing,
        step = step,
        perRow = Round(perRow),
        cols = cols,
        rows = rows,
        width = math_max(1, cols * size + math_max(cols - 1, 0) * spacing),
        height = math_max(1, rows * size + math_max(rows - 1, 0) * spacing),
        x = Round(x),
        y = Round(y),
        anchor = anchor,
        layer = Round(layer),
        alpha = alpha,
        growthX = growthX,
        growthY = growthY,
        xSign = xSign,
        ySign = ySign,
        initialAnchor = ButtonAnchor(xSign, ySign),
        sortOrder = sortOrder,
        sortComparator = sortOrder == 0 and SortAurasID or SortComparator(sortOrder),
        naturalOrder = sortOrder == 0 and needsPlayerFlag ~= true,
        reorderOnUpdate = sortOrder ~= 0,
        clickThrough = source.clickThrough == true,
        showTooltip = source.showTooltip ~= false,
        showCooldownSwipe = renderEnabled == true and showCooldownSwipe == true,
        showCooldownText = renderEnabled == true and showCooldown == true,
        showCooldown = renderEnabled == true and showCooldown == true,
        cooldownSwipeDarken = source.cooldownSwipeDarkenOnLoss == true,
        cooldownTextBuckets = cooldownTextBuckets,
        cooldownSafeR = cooldownSafeR,
        cooldownSafeG = cooldownSafeG,
        cooldownSafeB = cooldownSafeB,
        cooldownWarnR = cooldownWarnR,
        cooldownWarnG = cooldownWarnG,
        cooldownWarnB = cooldownWarnB,
        cooldownUrgentR = cooldownUrgentR,
        cooldownUrgentG = cooldownUrgentG,
        cooldownUrgentB = cooldownUrgentB,
        cooldownSafeSeconds = ClampNumber(general and general.aurasCooldownTextSafeSeconds, 60, 0, 600),
        cooldownWarningSeconds = ClampNumber(general and general.aurasCooldownTextWarningSeconds, 15, 0, 60),
        cooldownUrgentSeconds = ClampNumber(general and general.aurasCooldownTextUrgentSeconds, 5, 0, 60),
        cooldownSize = ClampNumber(source[spec.cooldownSizeKey] or source.cooldownSize, DEFAULT_SHARED.cooldownTextSize, 6, 40),
        cooldownAnchor = ReadAnchor(source, nil, spec.cooldownAnchorKey, "CENTER"),
        cooldownX = 0,
        cooldownY = 0,
        showStacks = source[spec.showStackKey] ~= false,
        stackAnchor = source.stackAnchor or "BOTTOMRIGHT",
        stackSize = ClampNumber(source[spec.stackSizeKey], DEFAULT_SHARED.stackTextSize, 6, 40),
        stackX = 0,
        stackY = 0,
        stackR = stackR,
        stackG = stackG,
        stackB = stackB,
        blacklist = black,
        hasFilterWork = black ~= nil,
        exclusiveImportant = false,
        onlyImportant = false,
        onlyMine = false,
        raid = false,
        includeStealable = false,
        boss = false,
        raidInCombat = false,
        hasInclusive = false,
        needsPlayerFlag = needsPlayerFlag == true,
        needsCombatRefresh = false,
        visual = kind == "debuff" and visual or nil,
        showDispelTypeBorder = showDispelTypeBorder == true,
        dispelColorCurve = dispelVisual and dispelVisual.dispelColorCurve or nil,
    }
end

local function ResolveGroupFrameConfig(frame, unit)
    if not frame then return nil end
    unit = unit or frame.unit
    local spec = frame.MSUFSpec
    local source = spec and spec.group and spec.group.auras
    local visual = CompileFrameAuraVisual(spec)
    local cached = frame._msufA3GroupConfig
    if cached and frame._msufA3GroupSource == source and frame._msufA3GroupUnit == unit
        and frame._msufA3GroupSpec == spec then
        return cached
    end

    local cfg = { unit = unit, enabled = false, lanes = {}, group = true, source = source, visual = visual }
    if type(source) == "table" and type(unit) == "string" and unit ~= "" then
        local sourceEnabled = source.enabled == true
        local needDebuffScan = visual and visual.enabled == true
        local buff = sourceEnabled and source.showBuffs == true and CompileGroupLane(unit, source, "buff", false, nil, true) or nil
        local debuff = (sourceEnabled and source.showDebuffs == true or needDebuffScan)
            and CompileGroupLane(unit, source, "debuff", needDebuffScan, visual, sourceEnabled == true) or nil
        cfg.showTooltip = source.showTooltip ~= false
        cfg.clickThrough = source.clickThrough == true
        cfg.lanes.buff = buff
        cfg.lanes.debuff = debuff
        cfg.enabled = (buff and buff.enabled == true) or (debuff and debuff.enabled == true)
    end

    frame._msufA3GroupSource = source
    frame._msufA3GroupUnit = unit
    frame._msufA3GroupSpec = spec
    frame._msufA3GroupConfig = cfg
    return cfg
end

local function FrameAuraConfig(frame, unit)
    if IsGroupFrame(frame) then
        return ResolveGroupFrameConfig(frame, unit)
    end
    return A3.ResolveUnitFrameConfig(unit or (frame and frame.unit), frame and frame.MSUFSpec)
end

local function BuildUnitFrameConfig(unit, frameSpec)
    unit = NormalizeRuntimeUnit(unit)
    if not unit then return nil end

    local auras, shared = EnsureRootDB()
    local flag = UNIT_FLAG[unit]
    local visual = CompileFrameAuraVisual(frameSpec)
    local cfg = { unit = unit, enabled = false, lanes = {}, visual = visual }
    local auraIconsEnabled = auras.enabled == true and flag and auras[flag] == true
    local needDebuffScan = visual and visual.enabled == true
    if auraIconsEnabled or needDebuffScan then
        local layout, sharedLayout, blacklist, filtersRoot = EffectiveTables(auras, unit)
        local buff = auraIconsEnabled and CompileLane(unit, shared, layout, sharedLayout, blacklist, filtersRoot, "buff", false, nil, true) or nil
        local debuff = (auraIconsEnabled or needDebuffScan)
            and CompileLane(unit, shared, layout, sharedLayout, blacklist, filtersRoot, "debuff", needDebuffScan, visual, auraIconsEnabled == true) or nil
        cfg.showTooltip = ReadBool(nil, shared, "showTooltip", true)
        cfg.clickThrough = ReadBool(nil, shared, "clickThroughAuras", false)
        cfg.lanes.buff = buff
        cfg.lanes.debuff = debuff
        cfg.enabled = (buff and buff.enabled == true) or (debuff and debuff.enabled == true)
    end

    return cfg
end

function A3.ResolveUnitFrameConfig(unit, frameSpec)
    unit = NormalizeRuntimeUnit(unit)
    if not unit then return nil end
    if frameSpec ~= nil then
        return BuildUnitFrameConfig(unit, frameSpec)
    end
    A3._runtimeConfigCache = A3._runtimeConfigCache or {}
    local gen = A3._runtimeConfigGen or 1
    local cached = A3._runtimeConfigCache[unit]
    if cached and cached.gen == gen then return cached.config end

    local cfg = BuildUnitFrameConfig(unit, nil)
    A3._runtimeConfigCache[unit] = { gen = gen, config = cfg }
    return cfg
end

function A3.BuildAuraLaneMetrics(configOrUnit, kind)
    kind = (kind == "debuff" or kind == "debuffs") and "debuff" or "buff"
    local cfg = type(configOrUnit) == "table" and configOrUnit or A3.ResolveUnitFrameConfig(configOrUnit)
    local lane = cfg and cfg.lanes and cfg.lanes[kind]
    if not lane then return nil end
    return {
        enabled = lane.enabled == true,
        num = lane.max,
        size = lane.size,
        spacing = lane.spacing,
        step = lane.step,
        perRow = lane.perRow,
        width = lane.width,
        height = lane.height,
        growthX = lane.xSign,
        growthY = lane.ySign,
        x = lane.x,
        y = lane.y,
        anchor = lane.anchor,
    }
end

function A3.UnitFrameAuraEnabled(unit)
    local cfg = A3.ResolveUnitFrameConfig(unit)
    return cfg and cfg.enabled == true
end

local function OnAuraEnter(button)
    if not (button and button:IsVisible() and GameTooltip and not GameTooltip:IsForbidden()) then return end
    local lane = button._msufA3Lane
    if not (lane and lane.config and lane.config.showTooltip and button.auraInstanceID) then return end
    GameTooltip:SetOwner(button, "ANCHOR_CURSOR")
    if GameTooltip.SetUnitAuraByAuraInstanceID then
        GameTooltip:SetUnitAuraByAuraInstanceID(lane.unit, button.auraInstanceID)
    end
end

local function OnAuraLeave()
    if GameTooltip and not GameTooltip:IsForbidden() then GameTooltip:Hide() end
end

local function ApplyFont(fs, size)
    if not fs then return end
    local fontPath, fontFlags, r, g, b, _, useShadow
    local gfs = _G.MSUF_GetGlobalFontSettings
    if type(gfs) == "function" then
        fontPath, fontFlags, r, g, b, _, useShadow = gfs()
    end
    fontPath = fontPath or _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    fontFlags = fontFlags or "OUTLINE"
    local fontKey = (_G.MSUF_DB and _G.MSUF_DB.general and _G.MSUF_DB.general.fontKey) or "FRIZQT"
    if type(_G.MSUF_SetFontSafe) == "function" then
        _G.MSUF_SetFontSafe(fs, fontPath, size or 14, fontFlags, fontKey)
    elseif fs.SetFont then
        fs:SetFont(fontPath, size or 14, fontFlags)
    end
    if fs.SetTextColor then fs:SetTextColor(r or 1, g or 1, b or 1, 1) end
    if fs.SetShadowOffset then
        if useShadow then fs:SetShadowOffset(1, -1) else fs:SetShadowOffset(0, 0) end
    end
end

local function PlaceStackText(fs, button, cfg)
    if not (fs and button and cfg) then return end
    fs:ClearAllPoints()
    if cfg.stackAnchor == "TOPLEFT" then
        fs:SetPoint("TOPLEFT", button, "TOPLEFT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
    elseif cfg.stackAnchor == "BOTTOMLEFT" then
        fs:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("BOTTOM")
    elseif cfg.stackAnchor == "BOTTOMRIGHT" then
        fs:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("RIGHT")
        fs:SetJustifyV("BOTTOM")
    else
        fs:SetPoint("TOPRIGHT", button, "TOPRIGHT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("RIGHT")
        fs:SetJustifyV("TOP")
    end
end

local function PositionButton(lane, button, index)
    local cfg = lane.config
    local perRow = cfg.perRow > 0 and cfg.perRow or 1
    local col = (index - 1) % perRow
    local row = math_floor((index - 1) / perRow)
    local x = col * cfg.step * cfg.xSign
    local y = row * cfg.step * cfg.ySign
    button:ClearAllPoints()
    button:SetPoint(cfg.initialAnchor, lane.frame, cfg.initialAnchor, x, y)
end

local CooldownTextRegion
local ResetCooldownTextColor

local function CooldownTextLayoutCustom(cfg)
    if not cfg then return false end
    if (cfg.cooldownSize or DEFAULT_SHARED.cooldownTextSize) ~= DEFAULT_SHARED.cooldownTextSize then return true end
    if (cfg.cooldownX or 0) ~= 0 or (cfg.cooldownY or 0) ~= 0 then return true end
    return cfg.cooldownAnchor ~= nil and cfg.cooldownAnchor ~= "CENTER"
end

local function ApplyCooldownTextLayout(cooldown, button, cfg)
    if not (cooldown and button and cfg) then return end
    local custom = CooldownTextLayoutCustom(cfg)
    local fs = cooldown._msufA3TextRegion
    if not custom and not fs then return end
    fs = fs or (CooldownTextRegion and CooldownTextRegion(cooldown))
    if not fs then return end

    if fs.GetFont and not fs._msufA3BaseFont then
        fs._msufA3BaseFont, fs._msufA3BaseSize, fs._msufA3BaseFlags = fs:GetFont()
    end

    if fs.SetFont then
        local font = fs._msufA3BaseFont
        local size = custom and (cfg.cooldownSize or DEFAULT_SHARED.cooldownTextSize) or fs._msufA3BaseSize
        local flags = fs._msufA3BaseFlags
        if font and size and fs._msufA3AppliedSize ~= size then
            fs:SetFont(font, size, flags or "")
            fs._msufA3AppliedSize = size
        end
    end

    if fs.ClearAllPoints and fs.SetPoint then
        local anchor = custom and (cfg.cooldownAnchor or "CENTER") or "CENTER"
        local x = custom and (cfg.cooldownX or 0) or 0
        local y = custom and (cfg.cooldownY or 0) or 0
        if fs._msufA3Anchor ~= anchor or fs._msufA3X ~= x or fs._msufA3Y ~= y then
            fs:ClearAllPoints()
            fs:SetPoint(anchor, button, anchor, x, y)
            fs._msufA3Anchor, fs._msufA3X, fs._msufA3Y = anchor, x, y
        end
    end
end

local function ApplyButtonLayout(lane, button, index)
    local cfg = lane.config
    if not cfg then return end
    button._msufA3Lane = lane
    button:SetSize(cfg.size, cfg.size)
    button:EnableMouse(not cfg.clickThrough)
    if button.Cooldown then
        if button.Cooldown.SetDrawSwipe then button.Cooldown:SetDrawSwipe(cfg.showCooldown == true and cfg.showCooldownSwipe ~= false) end
        if button.Cooldown.SetHideCountdownNumbers then button.Cooldown:SetHideCountdownNumbers(cfg.showCooldownText == false) end
        ApplyCooldownTextLayout(button.Cooldown, button, cfg)
        if cfg.cooldownTextBuckets ~= true and ResetCooldownTextColor then
            ResetCooldownTextColor(button.Cooldown)
        end
        if button.Cooldown.SetSwipeColor then
            if cfg.cooldownSwipeDarken == true then
                button.Cooldown:SetSwipeColor(0, 0, 0, 0.78)
            else
                button.Cooldown:SetSwipeColor(0, 0, 0, 0.55)
            end
        end
        if cfg.showCooldown ~= true then
            button.Cooldown:Hide()
            button._msufA3CooldownShown = nil
        end
    end
    if button.Count then
        if cfg.showStacks == false then
            button.Count:Hide()
        else
            button.Count:Show()
            ApplyFont(button.Count, cfg.stackSize)
            PlaceStackText(button.Count, button, cfg)
            if button.Count.SetTextColor then
                button.Count:SetTextColor(cfg.stackR or 1, cfg.stackG or 1, cfg.stackB or 1, 1)
            end
        end
    end
    if cfg.showDispelTypeBorder ~= true and button._msufA3DispelOverlay then
        button._msufA3DispelOverlay:Hide()
    end
    PositionButton(lane, button, index)
end

local function CreateAuraButton(lane, index)
    local button = CreateFrame("Button", nil, lane.frame)
    local icon = button:CreateTexture(nil, "BORDER")
    icon:SetAllPoints()
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button.Icon = icon

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints()
    if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
    if cooldown.SetReverse then cooldown:SetReverse(true) end
    button.Cooldown = cooldown

    local textLayer = CreateFrame("Frame", nil, button)
    textLayer:SetAllPoints(button)
    if cooldown.GetFrameLevel and textLayer.SetFrameLevel then
        textLayer:SetFrameLevel(cooldown:GetFrameLevel() + 1)
    end
    local count = textLayer:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.Count = count

    button:SetScript("OnEnter", OnAuraEnter)
    button:SetScript("OnLeave", OnAuraLeave)
    ApplyButtonLayout(lane, button, index)
    button:Hide()

    lane[index] = button
    lane.createdButtons = index
    if type(lane.PostCreateButton) == "function" then
        lane:PostCreateButton(button)
    end
    local CT = A3.CooldownText
    if CT and type(CT.RegisterButton) == "function" then
        CT.RegisterButton(button, "unit")
    end
    return button
end

local function EnsureButton(lane, index)
    return lane[index] or CreateAuraButton(lane, index)
end

local function ApplyLaneLayout(lane)
    local cfg = lane.config
    if not (lane.frame and cfg) then return end
    lane.frame:ClearAllPoints()
    lane.frame:SetPoint(cfg.anchor, lane.root, cfg.anchor, cfg.x, cfg.y)
    lane.frame:SetSize(cfg.width, cfg.height)
    if lane.frame.SetAlpha then lane.frame:SetAlpha(cfg.alpha or 1) end
    if lane.root.GetFrameLevel and lane.frame.SetFrameLevel then
        lane.frame:SetFrameLevel((lane.root:GetFrameLevel() or 0) + cfg.layer)
    end
    for i = 1, lane.createdButtons or 0 do
        local button = lane[i]
        if button then ApplyButtonLayout(lane, button, i) end
    end
end

local HideButton
local ClearFrameAuraVisualState

local function ClearLane(lane)
    lane.all = WipeTable(lane.all)
    lane.active = WipeTable(lane.active)
    lane.sorted = WipeTable(lane.sorted)
    lane.ordered = WipeTable(lane.ordered)
    lane.visibleByID = WipeTable(lane.visibleByID)
    lane.orderedCount = 0
    lane.orderDirty = nil
    lane.visible = 0
    for i = 1, lane.createdButtons or 0 do
        local button = lane[i]
        if button then
            button.auraInstanceID = nil
            HideButton(button)
        end
    end
end

local function ResetLaneData(lane)
    lane.all = WipeTable(lane.all)
    lane.active = WipeTable(lane.active)
    lane.sorted = WipeTable(lane.sorted)
    lane.ordered = WipeTable(lane.ordered)
    lane.visibleByID = WipeTable(lane.visibleByID)
    lane.orderedCount = 0
    lane.orderDirty = nil
end

local function EnsureLane(root, state, kind)
    local lanes = state.lanes
    local lane = lanes[kind]
    if lane then return lane end
    local frame = CreateFrame("Frame", nil, root)
    lane = {
        kind = kind,
        root = root,
        frame = frame,
        all = {},
        active = {},
        sorted = {},
        ordered = {},
        slotScratch = {},
        visibleByID = {},
        orderedCount = 0,
        visible = 0,
        createdButtons = 0,
    }
    lanes[kind] = lane
    return lane
end

local function EnsureState(frame)
    local state = frame._msufA3State
    if state then return state end
    local root = frame.Auras
    if not (root and root.SetAllPoints) then
        root = CreateFrame("Frame", nil, frame)
        root:SetAllPoints(frame)
        frame.Auras = root
    end
    state = {
        frame = frame,
        root = root,
        lanes = {},
        configGen = 0,
        needFullUpdate = true,
    }
    frame._msufA3State = state
    root.__owner = frame
    root.Buffs = EnsureLane(root, state, "buff")
    root.Debuffs = EnsureLane(root, state, "debuff")
    return state
end

local function ApplyConfig(frame, cfg)
    local state = EnsureState(frame)
    local root = state.root
    root:SetAllPoints(frame)
    root:Show()
    state.unit = cfg.unit
    state.config = cfg
    state.configGen = A3._runtimeConfigGen or 1
    state.frameSpec = frame.MSUFSpec
    state.needFullUpdate = true

    for kind in pairs(LANE_SPECS) do
        local lane = EnsureLane(root, state, kind)
        lane.unit = cfg.unit
        lane.config = cfg.lanes and cfg.lanes[kind]
        if lane.config and lane.config.enabled then
            if lane.config.renderEnabled == true then
                lane.frame:Show()
                ApplyLaneLayout(lane)
            else
                lane.frame:Hide()
            end
        else
            lane.frame:Hide()
            ClearLane(lane)
        end
    end
    return state
end

local function HideState(frame)
    local state = frame and frame._msufA3State
    if not state then return end
    for _, lane in pairs(state.lanes) do ClearLane(lane) end
    if state.root then state.root:Hide() end
    ClearFrameAuraVisualState(frame)
end

local function Filtered(unit, auraInstanceID, filter)
    if not IsAuraFilteredOutByInstanceID then return false end
    local filtered = IsAuraFilteredOutByInstanceID(unit, auraInstanceID, filter)
    if IsSecret(filtered) then return false end
    return filtered == true
end

local function ProcessData(lane, unit, data)
    if type(data) ~= "table" then return nil end
    local auraInstanceID = data.auraInstanceID
    if auraInstanceID == nil then return nil end
    local cfg = lane.config
    if cfg.needsPlayerFlag == true then
        data.isPlayerAura = not Filtered(unit, auraInstanceID, cfg.playerFilter)
    else
        data.isPlayerAura = false
    end
    data.isHarmfulAura = cfg.harmful == true
    return data
end

local function Blacklisted(cfg, data)
    local blacklist = cfg.blacklist
    if not blacklist then return false end
    local spellID = data and data.spellId
    if spellID == nil or IsSecret(spellID) then return false end
    spellID = tonumber(spellID)
    return spellID and blacklist[math_floor(spellID + 0.5)] == true or false
end

local function MatchFilter(unit, auraInstanceID, filter)
    return not Filtered(unit, auraInstanceID, filter)
end

local function AuraDispelColor(cfg, unit, data)
    if not (cfg and unit and data and data.auraInstanceID and GetAuraDispelTypeColor and cfg.dispelColorCurve) then
        return false
    end
    if data._msufA3DispelKnown == true then
        if data._msufA3DispelHasColor == true then
            if data._msufA3DispelSecretColor == true then
                local color = data._msufA3DispelColorObject
                local r, g, b, a = ColorObjectRGBA(color)
                if r then
                    return true, r, g, b, a or 1, true
                end
                return false
            end
            return true, data._msufA3DispelR, data._msufA3DispelG, data._msufA3DispelB, data._msufA3DispelA, false
        end
        return false
    end
    local color = GetAuraDispelTypeColor(unit, data.auraInstanceID, cfg.dispelColorCurve)
    local r, g, b, a = ColorObjectRGBA(color)
    data._msufA3DispelKnown = true
    if r then
        data._msufA3DispelHasColor = true
        if HasSecretColor(r, g, b, a) then
            data._msufA3DispelSecretColor = true
            data._msufA3DispelColorObject = color
            data._msufA3DispelR, data._msufA3DispelG, data._msufA3DispelB, data._msufA3DispelA = nil, nil, nil, nil
            return true, r, g, b, a or 1, true
        end
        data._msufA3DispelSecretColor = nil
        data._msufA3DispelColorObject = nil
        data._msufA3DispelR, data._msufA3DispelG, data._msufA3DispelB, data._msufA3DispelA = r, g, b, a or 1
        return true, r, g, b, a or 1, false
    end
    data._msufA3DispelHasColor = false
    data._msufA3DispelSecretColor = nil
    data._msufA3DispelColorObject = nil
    data._msufA3DispelR, data._msufA3DispelG, data._msufA3DispelB, data._msufA3DispelA = nil, nil, nil, nil
    return false
end

local function MatchDispelTrigger(lane, unit, data, trigger)
    if not (lane and data) then return false end
    if trigger == "ANY_DEBUFF" then
        return true
    elseif trigger == "PLAYER_CAST" then
        return data.isPlayerAura == true
    elseif trigger == "DISPEL_TYPE" then
        return AuraDispelColor(lane.config, unit, data)
    end
    return MatchFilter(unit, data.auraInstanceID, lane.config.dispellableFilter)
end

local function DispelVisualColor(lane, visual, unit, data)
    if visual and visual.colorMode == "TYPE" then
        local hasColor, r, g, b, a, secret = AuraDispelColor(lane.config, unit, data)
        if hasColor then return r, g, b, a, secret == true end
    end
    return visual and visual.r or 0.25, visual and visual.g or 0.75, visual and visual.b or 1, visual and visual.a or 1, false
end

local function TimedAura(data)
    local duration = PlainNumber(data and data.duration)
    local expirationTime = PlainNumber(data and data.expirationTime)
    return duration and expirationTime and duration > 0 and expirationTime > 0
end

local function RemainingTime(data)
    local expirationTime = PlainNumber(data and data.expirationTime)
    if not (expirationTime and expirationTime > 0 and GetTime) then return nil end
    local remaining = expirationTime - GetTime()
    if remaining < 0 then remaining = 0 end
    return remaining
end

local function SatedAura(data)
    local spellID = PlainNumber(data and data.spellId)
    return spellID and SATED_SPELLS[math_floor(spellID + 0.5)] == true or false
end

local function ShouldShowAura(lane, unit, data)
    local cfg = lane.config
    if Blacklisted(cfg, data) then return false end
    if cfg.hidePermanent == true and not TimedAura(data) then return false end
    if cfg.satedFilter == true and SatedAura(data) then
        if cfg.showSated ~= true then return false end
        local threshold = cfg.satedThreshold or 0
        local remaining = threshold > 0 and RemainingTime(data) or nil
        if remaining and remaining > threshold then return false end
    end
    if not cfg.hasFilterWork then return true end
    local auraInstanceID = data.auraInstanceID
    if cfg.exclusiveImportant then
        return MatchFilter(unit, auraInstanceID, cfg.importantFilter)
    end
    if cfg.onlyImportant and not cfg.hasInclusive then
        return MatchFilter(unit, auraInstanceID, cfg.importantFilter)
    end
    if cfg.hasInclusive then
        if cfg.onlyMine and data.isPlayerAura then return true end
        if cfg.raid and MatchFilter(unit, auraInstanceID, cfg.raidFilter) then return true end
        if cfg.raidInCombat and MatchFilter(unit, auraInstanceID, cfg.raidInCombatFilter) then return true end
        if cfg.includeStealable and MatchFilter(unit, auraInstanceID, cfg.stealableFilter) then return true end
        if cfg.boss and MatchFilter(unit, auraInstanceID, cfg.bossFilter) then return true end
        if cfg.onlyImportant and MatchFilter(unit, auraInstanceID, cfg.importantFilter) then return true end
        return false
    end
    return true
end

SortAuras = function(a, b)
    if a.isPlayerAura ~= b.isPlayerAura then return a.isPlayerAura end
    return (a.auraInstanceID or 0) < (b.auraInstanceID or 0)
end

SortAurasID = function(a, b)
    return (a.auraInstanceID or 0) < (b.auraInstanceID or 0)
end

local function AuraID(data)
    return PlainNumber(data and data.auraInstanceID) or 0
end

local function SortAurasDefault(a, b)
    if a.isPlayerAura ~= b.isPlayerAura then return a.isPlayerAura end
    local ca = PlainBool(a.canApplyAura)
    local cb = PlainBool(b.canApplyAura)
    if ca ~= cb then return ca == true end
    return AuraID(a) < AuraID(b)
end

local function SortAurasDurationDesc(a, b)
    local da = PlainNumber(a.duration) or 0
    local db = PlainNumber(b.duration) or 0
    if da ~= db then return da > db end
    return SortAuras(a, b)
end

local function ExpirationValue(data)
    local value = PlainNumber(data and data.expirationTime)
    if value and value > 0 then return value end
    return 2147483647
end

local function SortAurasExpiration(a, b)
    local ea = ExpirationValue(a)
    local eb = ExpirationValue(b)
    if ea ~= eb then return ea < eb end
    return SortAuras(a, b)
end

local function SortAurasExpirationOnly(a, b)
    local ea = ExpirationValue(a)
    local eb = ExpirationValue(b)
    if ea ~= eb then return ea < eb end
    return AuraID(a) < AuraID(b)
end

local function NameValue(data)
    return PlainString(data and data.name) or ""
end

local function SortAurasName(a, b)
    local na = NameValue(a)
    local nb = NameValue(b)
    if na ~= nb then return na < nb end
    return SortAuras(a, b)
end

local function SortAurasNameOnly(a, b)
    local na = NameValue(a)
    local nb = NameValue(b)
    if na ~= nb then return na < nb end
    return AuraID(a) < AuraID(b)
end

SortComparator = function(mode)
    if mode == 1 then return SortAurasDefault end
    if mode == 2 then return SortAurasDurationDesc end
    if mode == 3 then return SortAurasExpiration end
    if mode == 4 then return SortAurasExpirationOnly end
    if mode == 5 then return SortAurasName end
    if mode == 6 then return SortAurasNameOnly end
    return SortAuras
end

local function DataMatchesLane(data, cfg)
    if nativeSecrets ~= true and type(data) == "table" then
        local harmful = data.isHarmful
        if harmful ~= nil and not IsSecret(harmful) then
            return (harmful == true) == (cfg.harmful == true)
        end
        local helpful = data.isHelpful
        if helpful ~= nil and not IsSecret(helpful) then
            return (helpful == true) ~= (cfg.harmful == true)
        end
    end
    local auraInstanceID = data and data.auraInstanceID
    return auraInstanceID ~= nil and not Filtered(cfg.unit, auraInstanceID, cfg.filter)
end

local function AddAuraToLane(lane, unit, data)
    data = ProcessData(lane, unit, data)
    if not data then return false end
    local auraInstanceID = data.auraInstanceID
    local isNew = lane.all[auraInstanceID] == nil
    lane.all[auraInstanceID] = data
    if isNew then
        local n = (lane.orderedCount or 0) + 1
        lane.ordered[n] = auraInstanceID
        lane.orderedCount = n
    end
    if lane.config.hasFilterWork ~= true then
        lane.active[auraInstanceID] = true
        return true
    end
    if ShouldShowAura(lane, unit, data) then
        lane.active[auraInstanceID] = true
        return true
    end
    lane.active[auraInstanceID] = nil
    lane.orderDirty = true
    return false
end

local function FullScanLane(lane, unit)
    local cfg = lane.config
    ResetLaneData(lane)
    if not (cfg and cfg.enabled) then return false end

    if GetAuraSlots and GetAuraDataBySlot then
        local slots, count = FillAuraSlots(lane.slotScratch, GetAuraSlots(unit, cfg.filter))
        lane.slotScratch = slots
        for i = 2, count do
            local data = GetAuraDataBySlot(unit, slots[i])
            AddAuraToLane(lane, unit, data)
        end
        return true
    end

    if AuraUtil and type(AuraUtil.ForEachAura) == "function" then
        AuraUtil.ForEachAura(unit, cfg.filter, nil, function(data)
            AddAuraToLane(lane, unit, data)
        end, true)
        return true
    end

    return true
end

local UpdateButton

local function ShowButton(button)
    if button._msufA3Shown ~= true then
        button._msufA3Shown = true
        button:Show()
    end
end

HideButton = function(button)
    if button._msufA3Shown ~= nil then
        button._msufA3Shown = nil
        button:Hide()
    elseif button.auraInstanceID ~= nil then
        button:Hide()
    end
end

local function ShowCooldown(button, cooldown)
    if button._msufA3CooldownShown ~= true then
        button._msufA3CooldownShown = true
        cooldown:Show()
    end
end

local function HideCooldown(button, cooldown)
    if button._msufA3CooldownShown ~= nil then
        button._msufA3CooldownShown = nil
        cooldown:Hide()
    end
end

local function EnsureOwnHighlight(button)
    local tex = button._msufA3OwnHighlight
    if tex then return tex end
    tex = button:CreateTexture(nil, "OVERLAY")
    tex:SetTexture(W8)
    tex:SetAllPoints(button)
    tex:SetBlendMode("ADD")
    tex:Hide()
    button._msufA3OwnHighlight = tex
    return tex
end

local function EnsureDispelTypeOverlay(button)
    local tex = button._msufA3DispelOverlay
    if tex then return tex end
    tex = button:CreateTexture(nil, "OVERLAY")
    tex:SetTexture(DEBUFF_OVERLAY_TEXTURE)
    tex:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
    tex:SetAllPoints(button)
    tex:Hide()
    button._msufA3DispelOverlay = tex
    return tex
end

local function UpdateDispelTypeOverlay(button, lane, unit, data)
    local cfg = lane and lane.config
    if not (cfg and cfg.showDispelTypeBorder == true) then
        local tex = button and button._msufA3DispelOverlay
        if tex then tex:Hide() end
        return
    end
    local hasColor, r, g, b, a = AuraDispelColor(cfg, unit, data)
    local tex = button._msufA3DispelOverlay
    if hasColor then
        tex = tex or EnsureDispelTypeOverlay(button)
        tex:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
        tex:Show()
    elseif tex then
        tex:Hide()
    end
end

local function UpdateOwnHighlight(button, cfg, data)
    local active = cfg and cfg.ownHighlight == true and data and data.isPlayerAura == true
    local tex = button._msufA3OwnHighlight
    if active then
        tex = EnsureOwnHighlight(button)
        tex:SetVertexColor(cfg.ownR or 1, cfg.ownG or 1, cfg.ownB or 1, 0.24)
        tex:Show()
    elseif tex then
        tex:Hide()
    end
end

local function CooldownTextRGB(cfg, data)
    if not (cfg and cfg.cooldownTextBuckets == true) then
        return cfg and cfg.cooldownSafeR or 1, cfg and cfg.cooldownSafeG or 1, cfg and cfg.cooldownSafeB or 1
    end
    local remaining = RemainingTime(data)
    if not remaining then
        return cfg.cooldownSafeR or 1, cfg.cooldownSafeG or 1, cfg.cooldownSafeB or 1
    end
    if remaining <= (cfg.cooldownUrgentSeconds or 5) then
        return cfg.cooldownUrgentR or 1, cfg.cooldownUrgentG or 0.55, cfg.cooldownUrgentB or 0.10
    end
    if remaining <= (cfg.cooldownWarningSeconds or 15) then
        return cfg.cooldownWarnR or 1, cfg.cooldownWarnG or 0.85, cfg.cooldownWarnB or 0.20
    end
    return cfg.cooldownSafeR or 1, cfg.cooldownSafeG or 1, cfg.cooldownSafeB or 1
end

CooldownTextRegion = function(cooldown)
    if not cooldown then return nil end
    local cached = cooldown._msufA3TextRegion
    if cached and cached.SetTextColor then return cached end
    if not cooldown.GetRegions then return nil end
    for i = 1, cooldown:GetNumRegions() do
        local region = select(i, cooldown:GetRegions())
        if region and region.GetObjectType and region:GetObjectType() == "FontString"
            and region.SetTextColor then
            cooldown._msufA3TextRegion = region
            return region
        end
    end
    return nil
end

local function MarkCooldownTextColor(cooldown, region, r, g, b)
    if region.GetTextColor and not region._msufA3BaseTextR then
        region._msufA3BaseTextR, region._msufA3BaseTextG, region._msufA3BaseTextB, region._msufA3BaseTextA = region:GetTextColor()
    end
    region:SetTextColor(r, g, b, 1)
    region._msufA3ColorApplied = true
    if cooldown then cooldown._msufA3ColorApplied = true end
end

ResetCooldownTextColor = function(cooldown)
    if not (cooldown and cooldown._msufA3ColorApplied == true) then return end
    local region = cooldown._msufA3TextRegion
    if region and region.SetTextColor and region._msufA3ColorApplied == true then
        region:SetTextColor(region._msufA3BaseTextR or 1, region._msufA3BaseTextG or 1, region._msufA3BaseTextB or 1, region._msufA3BaseTextA or 1)
        region._msufA3ColorApplied = nil
    elseif cooldown.SetCooldownTextColor then
        cooldown:SetCooldownTextColor(1, 1, 1, 1)
    elseif cooldown.SetTextColor then
        cooldown:SetTextColor(1, 1, 1, 1)
    end
    cooldown._msufA3ColorApplied = nil
end

local function ApplyCooldownTextColor(cooldown, cfg, data)
    if not (cooldown and cfg and cfg.showCooldownText ~= false and cfg.cooldownTextBuckets == true) then return end
    local r, g, b = CooldownTextRGB(cfg, data)
    if cooldown.SetCooldownTextColor then
        cooldown:SetCooldownTextColor(r, g, b, 1)
        cooldown._msufA3ColorApplied = true
        return
    end
    if cooldown.SetTextColor then
        cooldown:SetTextColor(r, g, b, 1)
        cooldown._msufA3ColorApplied = true
        return
    end
    local region = CooldownTextRegion(cooldown)
    if region then MarkCooldownTextColor(cooldown, region, r, g, b) end
end

local function UpdateLaneFromDelta(lane, unit, updateInfo)
    local cfg = lane.config
    if not (cfg and cfg.enabled) then return false end
    local needsRender = false

    local added = updateInfo and updateInfo.addedAuras
    if added then
        for i = 1, #added do
            local data = added[i]
            local auraInstanceID = data and data.auraInstanceID
            if auraInstanceID ~= nil and DataMatchesLane(data, cfg) then
                if AddAuraToLane(lane, unit, data) then needsRender = true end
            end
        end
    end

    local updated = updateInfo and updateInfo.updatedAuraInstanceIDs
    if updated and GetAuraDataByAuraInstanceID then
        for i = 1, #updated do
            local auraInstanceID = updated[i]
            if auraInstanceID ~= nil and lane.all[auraInstanceID] then
                local oldData = lane.all[auraInstanceID]
                local oldPlayer = oldData and oldData.isPlayerAura
                local wasActive = lane.active[auraInstanceID] == true
                local data = ProcessData(lane, unit, GetAuraDataByAuraInstanceID(unit, auraInstanceID))
                if data then
                    lane.all[auraInstanceID] = data
                    local nowActive = cfg.hasFilterWork ~= true or ShouldShowAura(lane, unit, data)
                    if nowActive then
                        lane.active[auraInstanceID] = true
                        if wasActive then
                            if cfg.reorderOnUpdate == true or oldPlayer ~= data.isPlayerAura then
                                needsRender = true
                            else
                                local index = lane.visibleByID and lane.visibleByID[auraInstanceID]
                                local button = index and lane[index]
                                if button then
                                    UpdateButton(lane, button, unit, data)
                                end
                            end
                        else
                            needsRender = true
                        end
                    else
                        lane.active[auraInstanceID] = nil
                        lane.orderDirty = true
                        if wasActive then needsRender = true end
                    end
                else
                    lane.all[auraInstanceID] = nil
                    lane.orderDirty = true
                    if wasActive then
                        lane.active[auraInstanceID] = nil
                        needsRender = true
                    end
                end
            end
        end
    end

    local removed = updateInfo and updateInfo.removedAuraInstanceIDs
    if removed then
        for i = 1, #removed do
            local auraInstanceID = removed[i]
            if auraInstanceID ~= nil and lane.all[auraInstanceID] then
                lane.all[auraInstanceID] = nil
                lane.orderDirty = true
                if lane.active[auraInstanceID] then
                    lane.active[auraInstanceID] = nil
                    needsRender = true
                end
            end
        end
    end

    return needsRender
end

local function SetIcon(button, icon)
    local tex = button.Icon
    if not tex then return end
    if nativeSecrets == true then
        tex:SetTexture(icon)
        return
    end
    if IsSecret(icon) then
        tex:SetTexture(icon)
        button._msufA3Icon = nil
        button._msufA3IconPlain = nil
        return
    end
    if button._msufA3IconPlain == true and button._msufA3Icon == icon then
        return
    end
    tex:SetTexture(icon)
    button._msufA3Icon = icon
    button._msufA3IconPlain = true
end

local function SetCount(button, text)
    local count = button.Count
    if not count then return end
    if nativeSecrets == true then
        count:SetText(text or "")
        return
    end
    if IsSecret(text) then
        count:SetText(text)
        button._msufA3Count = nil
        button._msufA3CountPlain = nil
        return
    end
    text = text or ""
    if button._msufA3CountPlain == true and button._msufA3Count == text then
        return
    end
    count:SetText(text)
    button._msufA3Count = text
    button._msufA3CountPlain = true
end

local function UpdateCooldown(button, cooldown, unit, data)
    if nativeSecrets ~= true then
        local duration = data.duration
        local expirationTime = data.expirationTime
        if not IsSecret(duration) and not IsSecret(expirationTime)
            and type(duration) == "number" and type(expirationTime) == "number"
            and duration > 0 and expirationTime > 0 then
            local start = expirationTime - duration
            if button._msufA3CooldownPlain ~= true
                or button._msufA3CooldownStart ~= start
                or button._msufA3CooldownDuration ~= duration then
                cooldown:SetCooldown(start, duration)
                button._msufA3CooldownStart = start
                button._msufA3CooldownDuration = duration
                button._msufA3CooldownPlain = true
            end
            ShowCooldown(button, cooldown)
            return
        end
    end

    local durationObject = GetAuraDuration and GetAuraDuration(unit, data.auraInstanceID)
    button._msufA3CooldownStart = nil
    button._msufA3CooldownDuration = nil
    button._msufA3CooldownPlain = nil
    if durationObject then
        if cooldown.SetCooldownFromDurationObject then
            cooldown:SetCooldownFromDurationObject(durationObject)
        end
        ShowCooldown(button, cooldown)
    else
        HideCooldown(button, cooldown)
    end
end

UpdateButton = function(lane, button, unit, data)
    local cfg = lane.config
    button.auraInstanceID = data.auraInstanceID
    button.isHarmfulAura = cfg.harmful == true
    SetIcon(button, data.icon)
    local cooldown = button.Cooldown
    if cooldown and cfg.showCooldown == true then
        UpdateCooldown(button, cooldown, unit, data)
        if cfg.cooldownTextBuckets == true then
            ApplyCooldownTextColor(cooldown, cfg, data)
        end
    elseif cooldown then
        HideCooldown(button, cooldown)
    end
    if cfg.showStacks ~= false then
        local applications = data.applications
        if nativeSecrets ~= true and not IsSecret(applications) and type(applications) == "number" then
            SetCount(button, applications > 1 and applications or "")
        elseif GetAuraApplicationDisplayCount then
            SetCount(button, GetAuraApplicationDisplayCount(unit, data.auraInstanceID, 2, 999))
        else
            SetCount(button, "")
        end
    end
    if cfg.ownHighlight == true or button._msufA3OwnHighlight then
        UpdateOwnHighlight(button, cfg, data)
    end
    if cfg.showDispelTypeBorder == true or button._msufA3DispelOverlay then
        UpdateDispelTypeOverlay(button, lane, unit, data)
    end
    ShowButton(button)
end

local function HideTrailingButtons(lane, visibleByID, visible)
    for i = visible + 1, lane.visible do
        local button = lane[i]
        if button then
            if button.auraInstanceID ~= nil then
                visibleByID[button.auraInstanceID] = nil
            end
            button.auraInstanceID = nil
            HideButton(button)
        end
    end
    lane.visible = visible
end

local function CompactLaneOrder(lane)
    local ordered = lane.ordered
    local all = lane.all
    local active = lane.active
    local write = 0
    for i = 1, lane.orderedCount or 0 do
        local auraInstanceID = ordered[i]
        if active[auraInstanceID] and all[auraInstanceID] then
            write = write + 1
            ordered[write] = auraInstanceID
        end
    end
    for i = write + 1, lane.orderedCount or 0 do
        ordered[i] = nil
    end
    lane.orderedCount = write
    lane.orderDirty = nil
end

local function RenderLaneNatural(lane, unit, cfg)
    local visibleByID = WipeTable(lane.visibleByID)
    local ordered = lane.ordered
    local all = lane.all
    local active = lane.active
    local visible = 0
    local maxVisible = cfg.max
    for i = 1, lane.orderedCount or 0 do
        local auraInstanceID = ordered[i]
        if active[auraInstanceID] then
            local data = all[auraInstanceID]
            if data then
                visible = visible + 1
                local button = EnsureButton(lane, visible)
                UpdateButton(lane, button, unit, data)
                visibleByID[auraInstanceID] = visible
                if visible >= maxVisible then break end
            end
        end
    end
    HideTrailingButtons(lane, visibleByID, visible)
    if lane.orderDirty == true and (lane.orderedCount or 0) > 96 then
        CompactLaneOrder(lane)
    end
    return true
end

local function RenderLane(lane, unit)
    local cfg = lane.config
    if not (cfg and cfg.enabled) then
        ClearLane(lane)
        return false
    end
    if cfg.max <= 0 or cfg.renderEnabled ~= true then
        for i = 1, lane.visible do
            local button = lane[i]
            if button then
                button.auraInstanceID = nil
                HideButton(button)
            end
        end
        lane.visibleByID = WipeTable(lane.visibleByID)
        lane.visible = 0
        return true
    end
    if cfg.naturalOrder == true then
        return RenderLaneNatural(lane, unit, cfg)
    end
    local sorted = WipeTable(lane.sorted)
    local count = 0
    for auraInstanceID in next, lane.active do
        local data = lane.all[auraInstanceID]
        if data then
            count = count + 1
            sorted[count] = data
        end
    end
    if count > 1 then
        table_sort(sorted, cfg.sortComparator or SortAuras)
    end

    local visible = math_min(cfg.max, count)
    local visibleByID = WipeTable(lane.visibleByID)
    for i = 1, visible do
        local button = EnsureButton(lane, i)
        local data = sorted[i]
        UpdateButton(lane, button, unit, data)
        visibleByID[data.auraInstanceID] = i
    end
    HideTrailingButtons(lane, visibleByID, visible)
    return true
end

local function ResolveDispelTriggerVisual(lane, unit, visual, trigger)
    if not (lane and visual and trigger) then return false end
    local active = lane.active
    local all = lane.all
    if not (active and all) then return false end
    for auraInstanceID in next, active do
        local data = all[auraInstanceID]
        if data and MatchDispelTrigger(lane, unit, data, trigger) then
            local token = data.auraInstanceID
            if IsSecret(token) then token = nil end
            local r, g, b, a, secret = DispelVisualColor(lane, visual, unit, data)
            return true, r, g, b, a, secret == true, token
        end
    end
    return false
end

local function HasActiveDebuff(lane)
    return lane and lane.active and next(lane.active) ~= nil or false
end

local function NotifyFrameAuraVisuals(frame)
    if not frame then return end
    local active = frame._msufActiveElements
    local elements = UF and UF.elements
    local borders = active and active.Borders == true and elements and elements.Borders
    if borders and borders.Update then
        borders.Update(frame, "MSUF_A3_AURA_VISUAL", frame.unit)
    end
    if frame.MSUFSpec and frame.MSUFSpec.scope == "group" then
        local visuals = active and active.GroupVisuals == true and elements and elements.GroupVisuals
        if visuals and visuals.Update then
            visuals.Update(frame, "MSUF_A3_AURA_VISUAL", frame.unit)
        end
    end
end

local function SetFrameAuraVisualState(frame, borderActive, br, bg, bb, ba, borderSecret, borderToken, overlayActive, orr, og, ob, oa, overlaySecret, overlayToken, stripeActive, visual)
    if not frame then return end
    br, bg, bb, ba = br or 0.25, bg or 0.75, bb or 1, ba or 1
    orr, og, ob, oa = orr or br, og or bg, ob or bb, oa or ba
    borderSecret = borderSecret == true
    overlaySecret = overlaySecret == true
    local borderChanged = frame._msufA3DispelActive ~= borderActive
        or frame._msufA3DispelColorSecret ~= borderSecret
        or frame._msufA3DispelToken ~= borderToken
    if not borderChanged and not borderSecret then
        if HasSecretColor(frame._msufA3DispelR, frame._msufA3DispelG, frame._msufA3DispelB, frame._msufA3DispelA) then
            borderChanged = true
        else
            borderChanged = frame._msufA3DispelR ~= br
                or frame._msufA3DispelG ~= bg
                or frame._msufA3DispelB ~= bb
                or frame._msufA3DispelA ~= ba
        end
    end
    local overlayChanged = frame._msufA3DispelOverlayActive ~= overlayActive
        or frame._msufA3DispelOverlayColorSecret ~= overlaySecret
        or frame._msufA3DispelOverlayToken ~= overlayToken
    if not overlayChanged and not overlaySecret then
        if HasSecretColor(frame._msufA3DispelOverlayR, frame._msufA3DispelOverlayG, frame._msufA3DispelOverlayB, frame._msufA3DispelOverlayA) then
            overlayChanged = true
        else
            overlayChanged = frame._msufA3DispelOverlayR ~= orr
                or frame._msufA3DispelOverlayG ~= og
                or frame._msufA3DispelOverlayB ~= ob
                or frame._msufA3DispelOverlayA ~= oa
        end
    end
    local changed = borderChanged or overlayChanged
        or frame._msufA3DebuffStripeActive ~= stripeActive
        or frame._msufA3DebuffStripeR ~= (visual and visual.stripeR)
        or frame._msufA3DebuffStripeG ~= (visual and visual.stripeG)
        or frame._msufA3DebuffStripeB ~= (visual and visual.stripeB)
        or frame._msufA3DebuffStripeA ~= (visual and visual.stripeAlpha)
        or frame._msufA3DebuffStripeEdge ~= (visual and visual.stripeEdge)
        or frame._msufA3DebuffStripeHeight ~= (visual and visual.stripeHeight)
    if not changed then return end
    frame._msufA3DispelActive = borderActive == true
    frame._msufA3DispelColorSecret = borderSecret or nil
    frame._msufA3DispelToken = borderToken
    frame._msufA3DispelR, frame._msufA3DispelG, frame._msufA3DispelB, frame._msufA3DispelA = br, bg, bb, ba
    frame._msufA3DispelOverlayActive = overlayActive == true
    frame._msufA3DispelOverlayColorSecret = overlaySecret or nil
    frame._msufA3DispelOverlayToken = overlayToken
    frame._msufA3DispelOverlayR, frame._msufA3DispelOverlayG, frame._msufA3DispelOverlayB, frame._msufA3DispelOverlayA = orr, og, ob, oa
    frame._msufA3DebuffStripeActive = stripeActive == true
    frame._msufA3DebuffStripeR = visual and visual.stripeR or nil
    frame._msufA3DebuffStripeG = visual and visual.stripeG or nil
    frame._msufA3DebuffStripeB = visual and visual.stripeB or nil
    frame._msufA3DebuffStripeA = visual and visual.stripeAlpha or nil
    frame._msufA3DebuffStripeEdge = visual and visual.stripeEdge or nil
    frame._msufA3DebuffStripeHeight = visual and visual.stripeHeight or nil
    NotifyFrameAuraVisuals(frame)
end

ClearFrameAuraVisualState = function(frame)
    SetFrameAuraVisualState(frame, false, nil, nil, nil, nil, false, nil, false, nil, nil, nil, nil, false, nil, false, nil)
end

local function UpdateFrameAuraVisualState(frame, state, cfg, unit)
    local visual = cfg and cfg.visual
    if not (visual and visual.enabled == true) then
        ClearFrameAuraVisualState(frame)
        return
    end
    local lane = state and state.lanes and state.lanes.debuff
    if not (lane and lane.config and lane.config.enabled == true) then
        ClearFrameAuraVisualState(frame)
        return
    end
    local anyDebuff = HasActiveDebuff(lane)
    local borderActive, br, bg, bb, ba, borderSecret, borderToken = false
    local overlayActive, orr, og, ob, oa, overlaySecret, overlayToken = false
    if anyDebuff and visual.borderEnabled == true then
        borderActive, br, bg, bb, ba, borderSecret, borderToken = ResolveDispelTriggerVisual(lane, unit, visual, visual.borderTrigger)
    end
    if anyDebuff and visual.overlayEnabled == true then
        if visual.overlayTrigger == visual.borderTrigger then
            overlayActive, orr, og, ob, oa, overlaySecret, overlayToken = borderActive, br, bg, bb, ba, borderSecret, borderToken
        else
            overlayActive, orr, og, ob, oa, overlaySecret, overlayToken = ResolveDispelTriggerVisual(lane, unit, visual, visual.overlayTrigger)
        end
    end
    local stripeActive = anyDebuff and visual.stripeEnabled == true
    SetFrameAuraVisualState(frame, borderActive, br, bg, bb, ba, borderSecret, borderToken, overlayActive, orr, og, ob, oa, overlaySecret, overlayToken, stripeActive, visual)
end

local function EmptyAuraPayload(updateInfo)
    return updateInfo and not updateInfo.isFullUpdate
        and not updateInfo.addedAuras
        and not updateInfo.updatedAuraInstanceIDs
        and not updateInfo.removedAuraInstanceIDs
end

local function CurrentFrameState(frame, unit)
    local state = frame and frame._msufA3State
    if frame and frame._msufA3GroupRuntime == true then
        local cfg = ResolveGroupFrameConfig(frame, unit)
        if state and state.config == cfg and state.unit == unit then
            return state, cfg
        end
        if not (cfg and cfg.enabled) then
            return state, cfg
        end
        state = ApplyConfig(frame, cfg)
        return state, cfg
    end

    local gen = A3._runtimeConfigGen or 1
    if state and state.configGen == gen and state.config and state.unit == unit
        and state.frameSpec == frame.MSUFSpec then
        return state, state.config
    end

    local cfg = A3.ResolveUnitFrameConfig(unit, frame.MSUFSpec)
    if not (cfg and cfg.enabled) then
        return state, cfg
    end
    state = ApplyConfig(frame, cfg)
    return state, cfg
end

local function UpdateAuras(frame, event, unit, updateInfo, forceFull)
    if not frame then return false end
    unit = unit or frame.unit
    if unit ~= frame.unit then return false end
    if EmptyAuraPayload(updateInfo) and forceFull ~= true then return false end

    local state, cfg = CurrentFrameState(frame, unit)
    if not (cfg and cfg.enabled) then
        HideState(frame)
        return false
    end

    forceFull = forceFull == true or state.config ~= cfg
    local full = forceFull == true or state.needFullUpdate == true or not updateInfo or updateInfo.isFullUpdate == true
    state.needFullUpdate = false

    if full and UnitExists then
        local exists = UnitExists(unit)
        if not IsSecret(exists) and exists == false then
            local lanes = state.lanes
            local lane = lanes and lanes.buff
            if lane then ClearLane(lane) end
            lane = lanes and lanes.debuff
            if lane then ClearLane(lane) end
            ClearFrameAuraVisualState(frame)
            return false
        end
    end

    local changedCount = 0

    local lanes = state.lanes
    local lane = lanes and lanes.buff
    if lane and lane.config and lane.config.enabled then
        if full then
            if FullScanLane(lane, unit) then
                changedCount = changedCount + 1
                RenderLane(lane, unit)
            end
        elseif UpdateLaneFromDelta(lane, unit, updateInfo) then
            changedCount = changedCount + 1
            RenderLane(lane, unit)
        end
    end

    lane = lanes and lanes.debuff
    if lane and lane.config and lane.config.enabled then
        if full then
            if FullScanLane(lane, unit) then
                changedCount = changedCount + 1
                RenderLane(lane, unit)
            end
        elseif UpdateLaneFromDelta(lane, unit, updateInfo) then
            changedCount = changedCount + 1
            RenderLane(lane, unit)
        end
    end

    if changedCount > 0 then
        UpdateFrameAuraVisualState(frame, state, cfg, unit)
    end
    return changedCount > 0
end

local function RenderCachedAuras(frame, combatOnly)
    if not frame then return false end
    local unit = frame.unit
    local state, cfg = CurrentFrameState(frame, unit)
    if not (state and cfg and cfg.enabled) then
        HideState(frame)
        return false
    end
    if state.needFullUpdate == true then
        return UpdateAuras(frame, "ForceUpdate", unit, nil, true)
    end

    local changed = false
    local lanes = state.lanes
    local lane = lanes and lanes.buff
    local laneCfg = lane and lane.config
    if laneCfg and laneCfg.enabled and (combatOnly ~= true or laneCfg.needsCombatRefresh == true) then
        RenderLane(lane, unit)
        changed = true
    end
    lane = lanes and lanes.debuff
    laneCfg = lane and lane.config
    if laneCfg and laneCfg.enabled and (combatOnly ~= true or laneCfg.needsCombatRefresh == true) then
        RenderLane(lane, unit)
        changed = true
    end
    if changed then
        UpdateFrameAuraVisualState(frame, state, cfg, unit)
    end
    return changed
end

local function NeedsCombatAuraEvents(cfg)
    if not (cfg and cfg.enabled and cfg.lanes) then return false end
    local lane = cfg.lanes.buff
    if lane and lane.enabled and lane.needsCombatRefresh == true then return true end
    lane = cfg.lanes.debuff
    return lane and lane.enabled and lane.needsCombatRefresh == true or false
end

function A3.EnableFrame(frame)
    if not (frame and frame.unit and MANAGED_UNITS[frame.unit]) then return false end
    local cfg = A3.ResolveUnitFrameConfig(frame.unit, frame.MSUFSpec)
    if not (cfg and cfg.enabled) then
        HideState(frame)
        A3.SetUnitFrameOwner(frame.unit, frame, false)
        return false
    end
    ApplyConfig(frame, cfg)
    A3._runtimeFrames = A3._runtimeFrames or {}
    A3._runtimeFrames[frame.unit] = frame
    A3.SetUnitFrameOwner(frame.unit, frame, true)
    UpdateAuras(frame, "ForceUpdate", frame.unit, nil, true)
    return true
end

function A3.DisableFrame(frame)
    if not frame then return true end
    local unit = frame.unit
    HideState(frame)
    frame._msufA3GroupConfig = nil
    frame._msufA3GroupSource = nil
    frame._msufA3GroupUnit = nil
    frame._msufA3GroupRuntime = nil
    if unit then
        if A3._runtimeFrames and A3._runtimeFrames[unit] == frame then
            A3._runtimeFrames[unit] = nil
        end
        A3.SetUnitFrameOwner(unit, frame, false)
    end
    frame._msufA3UnitAuraOwner = nil
    return true
end

function A3.RenderFrame(frame)
    if not frame then return false end
    return UpdateAuras(frame, "ForceUpdate", frame.unit, nil, true)
end

A3.ForceUpdateFrame = A3.RenderFrame
A3.RenderCachedFrame = RenderCachedAuras

function A3.HandleUnitAura(frame, event, unit, updateInfo)
    return UpdateAuras(frame, event, unit, updateInfo, false)
end

function A3.UnitFrameOwnsUnitAura(unit, frame)
    unit = NormalizeRuntimeUnit(unit)
    return unit and A3._runtimeFrames and A3._runtimeFrames[unit] == frame or false
end

function A3.RuntimeOwnsUnit(unit)
    unit = NormalizeRuntimeUnit(unit)
    return unit and A3._runtimeFrames and A3._runtimeFrames[unit] ~= nil or false
end

local function RequestUnitNow(unit)
    local didWork = false
    EachRuntimeUnit(unit, function(runtimeUnit)
        local frame = (A3._runtimeFrames and A3._runtimeFrames[runtimeUnit])
            or (UF.frames and UF.frames[runtimeUnit])
            or (_G.MSUF_UnitFrames and _G.MSUF_UnitFrames[runtimeUnit])
            or _G["MSUF_" .. runtimeUnit]
        if frame then
            if UF.ApplyElementToFrame then
                UF.ApplyElementToFrame(frame, "Auras", frame.MSUFSpec, nil)
            else
                A3.EnableFrame(frame)
            end
            didWork = true
        end
    end)
    return didWork
end

function A3.RequestUnit(unit, delay)
    delay = tonumber(delay) or 0
    if delay > 0 and C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay, function() RequestUnitNow(unit) end)
        return true
    end
    return RequestUnitNow(unit)
end

function A3.RefreshAll()
    A3.BumpRuntimeConfig()
    A3._runtimeConfigCache = nil
    RequestUnitNow("*")
    return true
end

function A3.RefreshUnit(unit)
    A3.BumpRuntimeConfig()
    A3._runtimeConfigCache = nil
    return A3.RequestUnit(unit, 0)
end

function _G.MSUF_Auras3_ApplyFontsFromGlobal()
    local frames = A3._runtimeFrames
    if not frames then return true end
    for _, frame in pairs(frames) do
        local state = frame and frame._msufA3State
        if state then
            for _, lane in pairs(state.lanes) do
                for i = 1, lane.createdButtons or 0 do
                    local button = lane[i]
                    if button then ApplyButtonLayout(lane, button, i) end
                end
            end
        end
    end
    return true
end

local AurasElement = {
    events = { "UNIT_AURA" },
    unitlessEvents = EMPTY_EVENTS,
}

function AurasElement.IsEnabled(frame)
    if not (frame and frame.unit) then return false end
    if IsGroupFrame(frame) then
        local cfg = ResolveGroupFrameConfig(frame, frame.unit)
        return cfg and cfg.enabled == true or false
    end
    return A3.UnitFrameAuraEnabled(frame.unit) == true
end

function AurasElement.GetUnitlessEvents(frame)
    local cfg = frame and frame.unit and FrameAuraConfig(frame, frame.unit)
    return NeedsCombatAuraEvents(cfg) and COMBAT_AURA_EVENTS or EMPTY_EVENTS
end

function AurasElement.Create(frame)
    if frame then EnsureState(frame) end
end

function AurasElement.Apply(frame)
    if not frame then return end
    local isGroup = IsGroupFrame(frame)
    frame._msufA3GroupRuntime = isGroup == true or nil
    if isGroup then
        frame._msufA3GroupConfig = nil
    end
    local cfg = isGroup and ResolveGroupFrameConfig(frame, frame.unit) or A3.ResolveUnitFrameConfig(frame.unit, frame.MSUFSpec)
    if cfg and cfg.enabled then
        ApplyConfig(frame, cfg)
        if frame._msufActiveElements and frame._msufActiveElements.Auras == true then
            UpdateAuras(frame, "ForceUpdate", frame.unit, nil, true)
        end
    else
        HideState(frame)
    end
end

function AurasElement.Enable(frame)
    if IsGroupFrame(frame) then
        frame._msufA3GroupRuntime = true
        frame._msufA3GroupConfig = nil
        local cfg = ResolveGroupFrameConfig(frame, frame and frame.unit)
        if not (cfg and cfg.enabled == true) then
            HideState(frame)
            return false
        end
        local state = frame._msufA3State
        if not (state and state.config == cfg and state.unit == frame.unit) then
            ApplyConfig(frame, cfg)
        end
        UpdateAuras(frame, "ForceUpdate", frame.unit, nil, true)
        return true
    end
    return A3.EnableFrame(frame)
end

function AurasElement.Disable(frame)
    return A3.DisableFrame(frame)
end

function AurasElement.Update(frame, event, unit, updateInfo)
    if event == "ForceUpdate"
        or event == "MSUF_FORCE_UPDATE" then
        return A3.RenderFrame(frame)
    end
    if event == "PLAYER_REGEN_DISABLED"
        or event == "PLAYER_REGEN_ENABLED" then
        return RenderCachedAuras(frame, true)
    end
    return A3.HandleUnitAura(frame, event, unit, updateInfo)
end

UF.RegisterElement("Auras", AurasElement)

A3.frontendOnly = false
A3.backendEnabled = true
A3.unitFrameAuras = true
MSUF.AuraBackendEnabled = true

_G.MSUF_A3_RequestUnit = A3.RequestUnit
_G.MSUF_Auras3_RefreshUnit = A3.RefreshUnit
_G.MSUF_Auras3_RefreshAll = A3.RefreshAll
