--- Classic aura backend selected before the Retail 12.1 AuraContainer backend.
--- MoP Classic and TBC Classic expose the C_UnitAuras/AuraUtil scan contract
--- used here, while Classic does not ship the Retail native aura-container runtime.
if not (select(2, ...) and select(2, ...).Client and select(2, ...).Client.IsClassic) then return end
--- Auras3/MSUF_Auras3_UnitFrames.lua
--- Delta-first UnitFrame aura backend.
---
--- Runtime ownership:
--- * Menu_Model writes SavedVariables and invalidates runtime config.
--- * EditMode builds fake preview groups and drag handles only.
--- * This file owns live aura state, full scans, UNIT_AURA deltas, button pools,
---   and frame-level aura visuals for unit and group frames.
---
--- Keep gameplay aura work here and keep menu/edit code out of UNIT_AURA paths.
--- Aura scans are one of the most expensive frame events in MSUF, so new logic
--- should either compile into lane config or run behind the existing delta/full
--- scan split.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end

ExportPublic("MSUF_Auras3", A3)

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
local InCombatLockdown = _G.InCombatLockdown
local IsSecret = _G.issecretvalue or function() return false end

local GetAuraSlots = C_UnitAuras and C_UnitAuras.GetAuraSlots
local GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
local GetAuraDataBySlot = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot
local GetAuraDataByAuraInstanceID = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
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
local DISPEL_CURVE_CACHE = {}

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
        filter = "HELPFUL",
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
        hidePermanentKey = "buffHidePermanent",
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
    trackedBuff = {
        filter = "HELPFUL",
        showKey = "showTrackedBuffs",
        maxKey = "maxTrackedBuffs",
        sizeKey = "trackedBuffIconSize",
        spacingKey = "trackedBuffSpacing",
        perRowKey = "trackedBuffPerRow",
        growthXKey = "trackedBuffGrowthX",
        growthYKey = "trackedBuffGrowthY",
        anchorKey = "trackedBuffAnchor",
        xKey = "trackedBuffOffsetX",
        yKey = "trackedBuffOffsetY",
        layerKey = "trackedBuffLayer",
        alphaKey = "trackedBuffAlpha",
        filterKey = "trackedBuffFilter",
        blacklistKey = "trackedBuffBlacklistHash",
        includeHashKey = "trackedBuffIncludeHash",
        hidePermanentKey = "trackedBuffHidePermanent",
        showSwipeKey = "trackedBuffShowCooldownSwipe",
        showCooldownKey = "trackedBuffShowCooldown",
        showStackKey = "trackedBuffShowStacks",
        cooldownSizeKey = "trackedBuffCooldownSize",
        cooldownAnchorKey = "trackedBuffCooldownAnchor",
        stackSizeKey = "trackedBuffStackSize",
        defaultAnchor = "TOPLEFT",
        defaultLayer = 9,
        defaultMax = 8,
        defaultSize = 22,
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
        hidePermanentKey = "debuffHidePermanent",
        maxDurationKey = "debuffMaxDuration",
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
    external = {
        filter = "HELPFUL|EXTERNAL_DEFENSIVE",
        showKey = "showExternals",
        maxKey = "maxExternals",
        sizeKey = "externalIconSize",
        spacingKey = "externalSpacing",
        perRowKey = "externalPerRow",
        growthXKey = "externalGrowthX",
        growthYKey = "externalGrowthY",
        anchorKey = "externalAnchor",
        xKey = "externalOffsetX",
        yKey = "externalOffsetY",
        layerKey = "externalLayer",
        alphaKey = "externalAlpha",
        filterKey = "externalFilter",
        blacklistKey = "externalBlacklistHash",
        hidePermanentKey = "externalHidePermanent",
        showSwipeKey = "externalShowCooldownSwipe",
        showCooldownKey = "externalShowCooldown",
        showStackKey = "externalShowStacks",
        cooldownSizeKey = "externalCooldownSize",
        cooldownAnchorKey = "externalCooldownAnchor",
        stackSizeKey = "externalStackSize",
        defaultAnchor = "CENTER",
        defaultLayer = 7,
        defaultMax = 2,
        defaultSize = 28,
        defaultPerRow = 2,
        harmful = false,
    },
}

A3._ClassicBaseLaneOrder = { "buff", "trackedBuff", "debuff", "external" }

local function WipeTable(tbl)
    if not tbl then return {} end
    if wipe then return wipe(tbl) end
    for k in pairs(tbl) do tbl[k] = nil end
    return tbl
end

local function FillAuraSlots(out, ...)
    out = out or {}
    local count = select("#", ...)
    if count == 0 then
        out[1] = nil
        return out, 0
    end
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

function A3._ClassicSortMode(value, fallback)
    value = tostring(value or ""):upper():gsub("[%s%-]+", "_")
    if value == "DEFAULT" or value == "PLAYER" then return 1 end
    if value == "DURATION" or value == "DURATION_ONLY" or value == "BIG_DEFENSIVE" then return 2 end
    if value == "EXPIRATION" or value == "TIME_REMAINING" or value == "TIME" then return 3 end
    if value == "EXPIRATION_ONLY" then return 4 end
    if value == "NAME" then return 5 end
    if value == "NAME_ONLY" then return 6 end
    return fallback
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

local function DirectVisualFilterForTrigger(trigger)
    if trigger == "PLAYER_CAST" then
        return "HARMFUL|PLAYER"
    elseif trigger == "BY_ME" then
        return "HARMFUL|RAID_PLAYER_DISPELLABLE"
    elseif trigger == "DISPEL_TYPE" then
        return "HARMFUL|RAID"
    end
end

local function TriggerCanUseDirectVisual(trigger)
    return DirectVisualFilterForTrigger(trigger) ~= nil
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

local function DispelCurveSignature(spec)
    local parts = {}
    local n = 0
    n = n + 1; parts[n] = tostring(DispelColorValue(spec, "typeNoneR", 0.80))
    n = n + 1; parts[n] = tostring(DispelColorValue(spec, "typeNoneG", 0.00))
    n = n + 1; parts[n] = tostring(DispelColorValue(spec, "typeNoneB", 0.00))
    for i = 2, #DISPEL_POINTS do
        local point = DISPEL_POINTS[i]
        local key = "type" .. point[2]
        n = n + 1; parts[n] = tostring(DispelColorValue(spec, key .. "R", point[3]))
        n = n + 1; parts[n] = tostring(DispelColorValue(spec, key .. "G", point[4]))
        n = n + 1; parts[n] = tostring(DispelColorValue(spec, key .. "B", point[5]))
    end
    return table.concat(parts, ":")
end

local function BuildDispelColorCurve(spec)
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local signature = DispelCurveSignature(spec)
    local cached = DISPEL_CURVE_CACHE[signature]
    if cached then return cached end
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
    DISPEL_CURVE_CACHE[signature] = curve
    return curve
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

local function CompileDispelVisual(spec)
    local visual = type(spec) == "table" and spec or nil
    local mode = visual and visual.colorMode == "TYPE" and "TYPE" or "SINGLE"
    local curve = BuildDispelColorCurve(visual)
    local noneR, noneG, noneB, noneA, noneReady, noneSecret
    if curve and curve.Evaluate then
        local color = curve:Evaluate(0)
        noneR, noneG, noneB, noneA = ColorObjectRGBA(color)
        if IsSecret(noneR) == true then
            noneReady = true
            noneSecret = true
        elseif noneR ~= nil then
            noneReady = true
            if IsSecret(noneA) ~= true and noneA == nil then noneA = 1 end
            noneSecret = HasSecretColor(noneR, noneG, noneB, noneA) == true
        end
    end
    return {
        colorMode = mode,
        r = DispelColorValue(visual, "r", 0.25),
        g = DispelColorValue(visual, "g", 0.75),
        b = DispelColorValue(visual, "b", 1.00),
        a = DispelColorValue(visual, "a", 1.00),
        dispelColorCurve = curve,
        dispelNoneReady = noneReady == true,
        dispelNoneR = noneR,
        dispelNoneG = noneG,
        dispelNoneB = noneB,
        dispelNoneA = noneA,
        dispelNoneSecret = noneSecret == true,
    }
end

local function Round(value)
    value = tonumber(value) or 0
    if value < 0 then return -math_floor((-value) + 0.5) end
    return math_floor(value + 0.5)
end

local function NormalizeRuntimeUnit(unit)
    if unit and IsSecret(unit) == true then return nil end
    unit = tostring(unit or "player")
    if unit == "boss" then return "boss1" end
    if BOSS_UNITS[unit] or unit == "player" or unit == "target" or unit == "focus" then
        return unit
    end
    return nil
end

--- The current 6.0 factory owns identity through MSUFUnitKey/unitKey, while
--- the pre-12.1 scan backend originally consumed frame.unit. Keep that legacy
--- field synchronized only on Classic aura lifecycle entry points.
A3._ClassicBindFrameUnit = function(frame)
    if not frame then return nil end
    local unit = frame.MSUFUnitKey or frame.unitKey or frame.unit
    if unit ~= nil and frame.unit ~= unit then frame.unit = unit end
    return unit
end

local function IsUnitToken(unit)
    return unit ~= nil and IsSecret(unit) ~= true and type(unit) == "string" and unit ~= ""
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

local function EnsureRootDB()
    local db = _G.MSUF_DB
    if type(db) ~= "table" then
        db = {}
        ExportPublic("MSUF_DB", db)
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
    local vertical = false
    if growth == "UP" or growth == "DOWN" then
        vertical = true
        xSign = 1
        ySign = growth == "UP" and 1 or -1
    end
    return growth, rowWrap, xSign, ySign, vertical
end

local function GroupGrowthParts(growthX, growthY)
    if growthX ~= "LEFT" and growthX ~= "UP" and growthX ~= "DOWN" then growthX = "RIGHT" end
    if growthY ~= "UP" then growthY = "DOWN" end
    local xSign = growthX == "LEFT" and -1 or 1
    local ySign = growthY == "UP" and 1 or -1
    local vertical = false
    if growthX == "UP" or growthX == "DOWN" then
        vertical = true
        xSign = 1
        ySign = growthX == "UP" and 1 or -1
    end
    return growthX, growthY, xSign, ySign, vertical
end

local function ButtonAnchor(xSign, ySign)
    if ySign > 0 then
        return xSign < 0 and "BOTTOMRIGHT" or "BOTTOMLEFT"
    end
    return xSign < 0 and "TOPRIGHT" or "TOPLEFT"
end

local function GridShape(maxCount, perRow, vertical)
    local count = math_max(Round(maxCount), 1)
    local per = math_max(Round(perRow), 1)
    if vertical == true then
        local rows = math_min(count, per)
        local cols = math_ceil(count / per)
        return cols, rows
    end
    local cols = math_min(count, per)
    local rows = math_ceil(count / per)
    return cols, rows
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

local function CompileBlacklistHash(hash)
    if type(hash) ~= "table" then return nil end
    local out, n = nil, 0
    for key, enabled in pairs(hash) do
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
local frameSpecConfigCache = setmetatable and setmetatable({}, { __mode = "k" }) or {}

--- Config compilation turns DB/model choices into lane specs that the runtime
--- can consume without walking SavedVariables during UNIT_AURA. This is where
--- layout, filters, blacklist hashes, and dispel visual rules should be folded.
local function CompileFrameAuraVisual(spec)
    if type(spec) ~= "table" then return nil end
    local group = spec.scope == "group" and spec.group or nil
    local border = spec.border
    local unitOverlay = spec.dispelOverlay
    local symbol = group and group.dispelSymbol or spec.dispelSymbol

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
    local symbolEnabled = symbol and symbol.enabled == true

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
    local symbolTrigger = NormalizeDispelTrigger(symbol and symbol.trigger, "BORDER")
    if symbolTrigger == "BORDER" then symbolTrigger = borderTrigger end
    local needsScan = borderEnabled == true or overlayEnabled == true or stripeEnabled == true or symbolEnabled == true
    if not needsScan then return nil end
    local directVisualEligible = stripeEnabled ~= true and symbolEnabled ~= true
        and (borderEnabled ~= true or TriggerCanUseDirectVisual(borderTrigger))
        and (overlayEnabled ~= true or TriggerCanUseDirectVisual(overlayActualTrigger))
    local dispel = (borderEnabled == true or overlayEnabled == true) and CompileDispelVisual(spec.dispel) or nil

    return {
        enabled = true,
        borderEnabled = borderEnabled == true,
        overlayEnabled = overlayEnabled == true,
        stripeEnabled = stripeEnabled == true,
        borderTrigger = borderTrigger,
        overlayTrigger = overlayActualTrigger,
        directVisualEligible = directVisualEligible == true,
        needsPlayerFlag = borderTrigger == "PLAYER_CAST" or overlayActualTrigger == "PLAYER_CAST",
        colorMode = dispel and dispel.colorMode or "SINGLE",
        r = dispel and dispel.r or 0.25,
        g = dispel and dispel.g or 0.75,
        b = dispel and dispel.b or 1,
        a = dispel and dispel.a or 1,
        dispelColorCurve = dispel and dispel.dispelColorCurve or nil,
        overlayStyle = overlayStyle,
        overlayAlpha = overlayAlpha,
        overlayOnHealth = overlayOnHealth == true,
        stripeEdge = stripeEdge,
        stripeHeight = stripeHeight,
        stripeAlpha = stripeAlpha,
        stripeR = stripeR,
        stripeG = stripeG,
        stripeB = stripeB,
        symbol = symbolEnabled and {
            enabled = true,
            style = tostring(symbol.style or "BLIZZARD"):upper(),
            mode = tostring(symbol.mode or "ALL"):upper() == "ALL" and "ALL" or "SINGLE",
            trigger = symbolTrigger,
            size = ClampNumber(symbol.size, 14, 4, 64),
            spacing = ClampNumber(symbol.spacing, 2, 0, 32),
            growth = tostring(symbol.growth or "RIGHT"):upper(),
            anchor = tostring(symbol.anchor or "TOPRIGHT"):upper(),
            x = Round(ClampNumber(symbol.x, 0, -4096, 4096)),
            y = Round(ClampNumber(symbol.y, 0, -4096, 4096)),
            alpha = Clamp01(symbol.alpha, 1),
            layer = Round(ClampNumber(symbol.layer, 8, 0, 30)),
            strata = tostring(symbol.strata or "AUTO"):upper(),
        } or nil,
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
    local growthX, growthY, xSign, ySign, verticalGrowth = GrowthParts(growth, rowWrap)
    local x = ReadNumber(layout, shared, spec.xKey, DEFAULT_SHARED[spec.xKey] or 0, -4096, 4096)
    local y = ReadNumber(layout, shared, spec.yKey, DEFAULT_SHARED[spec.yKey] or 0, -4096, 4096)
    local anchor = ReadAnchor(layout, shared, spec.anchorKey, spec.defaultAnchor)
    local layer = ReadNumber(layout, shared, spec.layerKey, spec.defaultLayer, 1, 15)
    local stackAnchor = ReadAnchor(sharedLayout, shared, spec.stackAnchorKey, ReadShared(shared, "stackCountAnchor") or "TOPRIGHT")
    local filters = FilterTable(filtersRoot, spec.dbKey)
    local rootFilters = type(filtersRoot) == "table" and filtersRoot or nil
    local activeRootFilters = rootFilters and rootFilters.enabled ~= false and rootFilters or nil
    local laneBlacklist = type(blacklist) == "table"
        and type(blacklist[spec.dbKey]) == "table"
        and blacklist[spec.dbKey] or blacklist
    local exclusive = filters and filters.exclusive
    local onlyImportant = filters and (filters.onlyImportant == true or exclusive == "important")
    local onlyMine = filters and filters.onlyMine == true
    local raid = filters and (filters.raid == true or exclusive == "raid")
    local includeStealable = kind == "buff" and filters and filters.includeStealable == true
    local boss = filters and (filters.boss == true or filters.includeBoss == true)
    local onlyBoss = activeRootFilters and activeRootFilters.onlyBossAuras == true
    local hidePermanent = type(laneBlacklist) == "table" and laneBlacklist.hidePermanent == true
    if hidePermanent ~= true and kind == "buff" and activeRootFilters then
        -- Legacy profiles stored this one level above the per-lane filter.
        hidePermanent = activeRootFilters.hidePermanent == true
    end
    local maxDuration = kind == "debuff" and type(laneBlacklist) == "table"
        and ClampNumber(laneBlacklist.maxDuration, 0, 0, 180) or 0
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
    local filterPlan = A3.ClassicFeatures and A3.ClassicFeatures.CompileSettingsFilter
        and A3.ClassicFeatures.CompileSettingsFilter(filters, kind == "buff", {
            stealable = includeStealable == true,
            boss = boss == true or onlyBoss == true,
        }) or nil
    local visualNeedsPlayer = kind == "debuff" and visual and visual.needsPlayerFlag == true
    local hasInclusive = filterPlan and filterPlan.hasRequirements == true
        or onlyMine or raid or includeStealable or boss or onlyBoss or raidInCombat
    local black = CompileBlacklist(laneBlacklist)
    local hasFilterWork = black ~= nil or onlyImportant or hasInclusive or hidePermanent
        or maxDuration > 0 or satedFilter
    local renderEnabled = renderAllowed ~= false and show and maxCount > 0
    local visualDirect = kind == "debuff"
        and visual
        and visual.directVisualEligible == true
        and hasFilterWork ~= true
    local enabled = renderEnabled or (forceScan == true and kind == "debuff" and visualDirect ~= true)
    -- Capped scan validity: ShouldShowAura is a pure per-aura predicate for
    -- blacklist / hidePermanent / sated / onlyImportant, so the scan can stop
    -- at cfg.max and still be correct. Only hasInclusive (raid/boss/stealable/
    -- onlyMine OR-inclusion) can match an aura beyond the cap, so it is the one
    -- case that must keep the full walk. (Previously this required a pure
    -- blacklist, which forced a full ~0.3ms scan on the common buff lane where
    -- satedFilter defaults true -- the target-click spike.)
    local cappedFilterScan = hasFilterWork == true and hasInclusive ~= true
    local step = size + spacing
    local roundedMax = Round(maxCount)
    local roundedPerRow = Round(perRow)
    local cols, rows = GridShape(roundedMax, roundedPerRow, verticalGrowth)
    local legacySortOrder = ReadNumber(sharedLayout, shared, "sortOrder", DEFAULT_SHARED.sortOrder, 0, 6)
    local sortOrder = A3._ClassicSortMode(ReadRaw(sharedLayout, shared, kind .. "SortMethod")
        or ReadRaw(sharedLayout, shared, "sortMethod"), legacySortOrder)
    local sortReverse = ReadBool(sharedLayout, shared, kind .. "SortReverse",
        ReadBool(sharedLayout, shared, "sortReverse", false))
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
    local baseFilter = filterPlan and filterPlan.scanFilter or spec.filter
    local showDispelTypeBorder = kind == "debuff" and renderEnabled == true and ReadBool(nil, shared, "useDebuffTypeBorders", false)
    local dispelVisual = (kind == "debuff" and (visual or (showDispelTypeBorder and CompileDispelVisual(nil)))) or nil
    local needsPlayerFlag = (filterPlan and filterPlan.needsPlayerFlag == true)
        or onlyMine == true or ownHighlight == true or (visualNeedsPlayer == true and visualDirect ~= true)
    local sortComparator = sortOrder == 0 and (needsPlayerFlag and SortAuras or SortAurasID) or SortComparator(Round(sortOrder))
    local naturalOrder = sortOrder == 0 and needsPlayerFlag ~= true
    local visibleOnlyScan = renderEnabled == true
        and naturalOrder == true
        and raidInCombat ~= true
        and not (kind == "debuff" and visual and visual.enabled == true and visualDirect ~= true)

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
        max = renderEnabled and roundedMax or 0,
        weaponEnchants = kind == "buff" and runtimeUnit == "player"
            and ReadBool(shared, layout, "showWeaponEnchants", false),
        size = size,
        spacing = spacing,
        step = step,
        perRow = roundedPerRow,
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
        verticalGrowth = verticalGrowth == true,
        initialAnchor = ButtonAnchor(xSign, ySign),
        sortOrder = Round(sortOrder),
        sortComparator = sortComparator,
        sortReverse = sortReverse == true,
        naturalOrder = naturalOrder,
        visibleOnlyScan = visibleOnlyScan == true,
        cappedFilterScan = cappedFilterScan == true,
        reorderOnUpdate = sortOrder ~= 0 or sortReverse == true,
        ownHighlight = ownHighlight == true,
        ownR = ownR,
        ownG = ownG,
        ownB = ownB,
        clickThrough = ReadBool(nil, shared, "clickThroughAuras", false),
        showTooltip = ReadBool(sharedLayout, shared, kind .. "ShowTooltip", ReadBool(nil, shared, "showTooltip", true)),
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
        cooldownAnchor = ReadAnchor(layout, shared, kind .. "CooldownTextAnchor", ReadShared(shared, "cooldownTextAnchor") or "CENTER"),
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
        filterPlan = filterPlan,
        filterRequirements = filterPlan and filterPlan.requirements or nil,
        hasFilterWork = hasFilterWork,
        visualDirect = visualDirect == true,
        exclusiveImportant = exclusive == "important",
        onlyImportant = onlyImportant == true,
        onlyMine = onlyMine == true,
        raid = raid == true,
        includeStealable = includeStealable == true,
        boss = boss == true,
        hidePermanent = hidePermanent == true,
        maxDuration = maxDuration,
        showSated = showSated == true,
        satedThreshold = satedThreshold,
        satedFilter = satedFilter == true,
        raidInCombat = raidInCombat == true,
        hasInclusive = hasInclusive == true,
        needsPlayerFlag = needsPlayerFlag,
        needsCombatRefresh = filterPlan and filterPlan.needsCombatRefresh == true or raidInCombat == true,
        visual = kind == "debuff" and visual or nil,
        showDispelTypeBorder = showDispelTypeBorder == true,
        dispelColorCurve = dispelVisual and dispelVisual.dispelColorCurve or nil,
        dispelNoneReady = dispelVisual and dispelVisual.dispelNoneReady == true or false,
        dispelNoneR = dispelVisual and dispelVisual.dispelNoneR or nil,
        dispelNoneG = dispelVisual and dispelVisual.dispelNoneG or nil,
        dispelNoneB = dispelVisual and dispelVisual.dispelNoneB or nil,
        dispelNoneA = dispelVisual and dispelVisual.dispelNoneA or nil,
        dispelNoneSecret = dispelVisual and dispelVisual.dispelNoneSecret == true or false,
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
    local growthX, growthY, xSign, ySign, verticalGrowth = GroupGrowthParts(source[spec.growthXKey], source[spec.growthYKey])
    local x = ClampNumber(source[spec.xKey], 0, -4096, 4096)
    local y = ClampNumber(source[spec.yKey], 0, -4096, 4096)
    local anchor = source[spec.anchorKey] or spec.defaultAnchor
    if anchor ~= "TOPLEFT" and anchor ~= "TOPRIGHT" and anchor ~= "BOTTOMLEFT"
        and anchor ~= "BOTTOMRIGHT" and anchor ~= "CENTER" then
        anchor = spec.defaultAnchor
    end
    local layer = ClampNumber(source[spec.layerKey], spec.defaultLayer, 1, 15)
    local alpha = ClampNumber(source[spec.alphaKey], 1, 0, 1)
    local rawFilter = source[spec.filterKey] or spec.filter
    local filterPlan = A3.ClassicFeatures and A3.ClassicFeatures.CompileRawFilter
        and A3.ClassicFeatures.CompileRawFilter(rawFilter, kind == "buff") or nil
    local filter = filterPlan and filterPlan.scanFilter or spec.filter
    local black = CompileBlacklistHash(source[spec.blacklistKey])
    -- Classic aura payloads often carry a different spellId than the
    -- configured one (TBC spell ranks, Mists cast-vs-aura ID drift), so the
    -- compiled include list adds alias and name tolerance; exact-ID matching
    -- silently emptied tracked-buff whitelists.
    local includeSpellIDs, includeSpellNames
    if spec.includeHashKey and type(source[spec.includeHashKey]) == "table" then
        for key, enabled in pairs(source[spec.includeHashKey]) do
            if enabled == true then
                local id = tonumber(key)
                if id and id > 0 then
                    includeSpellIDs = includeSpellIDs or {}
                    if type(A3.AddAuraSpellIDAndAliases) == "function" then
                        A3.AddAuraSpellIDAndAliases(includeSpellIDs, id)
                    else
                        includeSpellIDs[math_floor(id + 0.5)] = true
                    end
                end
            end
        end
        if includeSpellIDs and A3.ClassicFeatures
            and type(A3.ClassicFeatures.NameHash) == "function" then
            includeSpellNames = A3.ClassicFeatures.NameHash(includeSpellIDs)
        end
    end
    local hidePermanent = spec.hidePermanentKey and source[spec.hidePermanentKey] == true or false
    local maxDuration = spec.maxDurationKey and ClampNumber(source[spec.maxDurationKey], 0, 0, 180) or 0
    local hasFilterWork = black ~= nil or type(includeSpellIDs) == "table" or hidePermanent or maxDuration > 0
        or (filterPlan and filterPlan.hasRequirements == true)
    local visualDirect = kind == "debuff"
        and visual
        and visual.directVisualEligible == true
        and hasFilterWork ~= true
    local enabled = renderEnabled or (forceScan == true and kind == "debuff" and visualDirect ~= true)
    local cappedFilterScan = (black ~= nil or hidePermanent or maxDuration > 0)
        and type(includeSpellIDs) ~= "table"
        and not (filterPlan and filterPlan.hasRequirements == true)
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
    local roundedMax = Round(maxCount)
    local roundedPerRow = Round(perRow)
    local cols, rows = GridShape(roundedMax, roundedPerRow, verticalGrowth)
    local sortOrder = A3._ClassicSortMode(source[kind .. "SortMethod"] or source.sortMethod,
        source.sortByDuration == true and 2 or 0)
    local sortReverse = source[kind .. "SortReverse"] == true
        or (source[kind .. "SortReverse"] == nil and source.sortReverse == true)
    local showDispelTypeBorder = kind == "debuff" and renderEnabled == true and source.debuffShowDispelBorder == true
    local dispelVisual = (kind == "debuff" and (visual or (showDispelTypeBorder and CompileDispelVisual(nil)))) or nil
    local needsPlayerFlag = source.preferPlayer == true
        or (filterPlan and filterPlan.needsPlayerFlag == true)
        or (kind == "debuff" and visual and visual.needsPlayerFlag == true and visualDirect ~= true)

    local naturalOrder = sortOrder == 0 and needsPlayerFlag ~= true
    local visibleOnlyScan = renderEnabled == true
        and naturalOrder == true
        and not (kind == "debuff" and visual and visual.enabled == true and visualDirect ~= true)

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
        max = renderEnabled and roundedMax or 0,
        size = size,
        spacing = spacing,
        step = step,
        perRow = roundedPerRow,
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
        verticalGrowth = verticalGrowth == true,
        initialAnchor = ButtonAnchor(xSign, ySign),
        sortOrder = sortOrder,
        sortComparator = sortOrder == 0 and SortAurasID or SortComparator(sortOrder),
        sortReverse = sortReverse == true,
        naturalOrder = naturalOrder,
        visibleOnlyScan = visibleOnlyScan == true,
        cappedFilterScan = cappedFilterScan == true,
        reorderOnUpdate = sortOrder ~= 0 or sortReverse == true,
        clickThrough = source.clickThrough == true,
        showTooltip = source[kind .. "ShowTooltip"] ~= false and source.showTooltip ~= false,
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
        includeSpellIDs = includeSpellIDs,
        includeSpellNames = includeSpellNames,
        filterPlan = filterPlan,
        filterRequirements = filterPlan and filterPlan.requirements or nil,
        hasFilterWork = hasFilterWork,
        visualDirect = visualDirect == true,
        exclusiveImportant = false,
        onlyImportant = false,
        onlyMine = false,
        raid = false,
        includeStealable = false,
        boss = false,
        raidInCombat = false,
        hasInclusive = false,
        hidePermanent = hidePermanent,
        maxDuration = maxDuration,
        needsPlayerFlag = needsPlayerFlag == true,
        needsCombatRefresh = filterPlan and filterPlan.needsCombatRefresh == true or false,
        visual = kind == "debuff" and visual or nil,
        showDispelTypeBorder = showDispelTypeBorder == true,
        dispelColorCurve = dispelVisual and dispelVisual.dispelColorCurve or nil,
        dispelNoneReady = dispelVisual and dispelVisual.dispelNoneReady == true or false,
        dispelNoneR = dispelVisual and dispelVisual.dispelNoneR or nil,
        dispelNoneG = dispelVisual and dispelVisual.dispelNoneG or nil,
        dispelNoneB = dispelVisual and dispelVisual.dispelNoneB or nil,
        dispelNoneA = dispelVisual and dispelVisual.dispelNoneA or nil,
        dispelNoneSecret = dispelVisual and dispelVisual.dispelNoneSecret == true or false,
    }
end

local function ResolveGroupFrameConfig(frame, unit)
    if not frame then return nil end
    unit = unit or A3._ClassicBindFrameUnit(frame)
    local spec = frame.MSUFSpec
    local source = spec and (spec.auras or (spec.group and spec.group.auras))
    local gen = A3._runtimeConfigGen or 1
    local cached = frame._msufA3GroupConfig
    if cached and frame._msufA3GroupSource == source and frame._msufA3GroupUnit == unit
        and frame._msufA3GroupSpec == spec and frame._msufA3GroupGen == gen then
        return cached
    end

    local visual = CompileFrameAuraVisual(spec)
    local cfg = { unit = unit, enabled = false, lanes = {}, laneOrder = {}, group = true, source = source, visual = visual }
    if type(source) == "table" and type(unit) == "string" and unit ~= "" then
        local sourceEnabled = source.enabled == true
        local needDebuffScan = visual and visual.enabled == true
        local buff = sourceEnabled and source.showBuffs == true and CompileGroupLane(unit, source, "buff", false, nil, true) or nil
        local trackedBuff = sourceEnabled and source.showTrackedBuffs == true
            and CompileGroupLane(unit, source, "trackedBuff", false, nil, true) or nil
        local debuff = (sourceEnabled and source.showDebuffs == true or needDebuffScan)
            and CompileGroupLane(unit, source, "debuff", needDebuffScan, visual, sourceEnabled == true) or nil
        local external = sourceEnabled and source.showExternals == true
            and CompileGroupLane(unit, source, "external", false, nil, true) or nil
        local visuals = A3.ClassicVisuals
        if visuals and type(visuals.EnrichGroupLane) == "function" then
            local scope = frame._msufGFKind or frame._msufCoreKind or "party"
            if buff then visuals.EnrichGroupLane(buff, source, "buff", spec, scope) end
            if trackedBuff then visuals.EnrichGroupLane(trackedBuff, source, "trackedBuff", spec, scope) end
            if debuff then visuals.EnrichGroupLane(debuff, source, "debuff", spec, scope) end
            if external then visuals.EnrichGroupLane(external, source, "external", spec, scope) end
        end
        cfg.showTooltip = source.showTooltip ~= false
        cfg.clickThrough = source.clickThrough == true
        cfg.lanes.buff = buff
        cfg.lanes.trackedBuff = trackedBuff
        cfg.lanes.debuff = debuff
        cfg.lanes.external = external
        if buff then cfg.laneOrder[#cfg.laneOrder + 1] = "buff" end
        if trackedBuff then cfg.laneOrder[#cfg.laneOrder + 1] = "trackedBuff" end
        if debuff then cfg.laneOrder[#cfg.laneOrder + 1] = "debuff" end
        if external then cfg.laneOrder[#cfg.laneOrder + 1] = "external" end
        cfg.visualDirect = debuff and debuff.visualDirect == true or nil
        cfg.enabled = (buff and buff.enabled == true) or (trackedBuff and trackedBuff.enabled == true)
            or (debuff and debuff.enabled == true) or (external and external.enabled == true)
            or cfg.visualDirect == true
    end
    if A3.ClassicFeatures and type(A3.ClassicFeatures.CompileGroupIndicatorLanes) == "function" then
        local extraLanes, extraOrder = A3.ClassicFeatures.CompileGroupIndicatorLanes(frame, unit)
        for i = 1, type(extraOrder) == "table" and #extraOrder or 0 do
            local kind = extraOrder[i]
            cfg.lanes[kind] = extraLanes[kind]
            cfg.laneOrder[#cfg.laneOrder + 1] = kind
            cfg.enabled = cfg.enabled == true or (extraLanes[kind] and extraLanes[kind].enabled == true)
        end
    end

    frame._msufA3GroupSource = source
    frame._msufA3GroupUnit = unit
    frame._msufA3GroupSpec = spec
    frame._msufA3GroupGen = gen
    frame._msufA3GroupConfig = cfg
    return cfg
end

local function FrameAuraConfig(frame, unit)
    if IsGroupFrame(frame) then
        return ResolveGroupFrameConfig(frame, unit)
    end
    return A3.ResolveUnitFrameConfig(unit or A3._ClassicBindFrameUnit(frame), frame and frame.MSUFSpec)
end

local function BuildUnitFrameConfig(unit, frameSpec)
    unit = NormalizeRuntimeUnit(unit)
    if not unit then return nil end

    local auras, shared = EnsureRootDB()
    local flag = UNIT_FLAG[unit]
    local visual = CompileFrameAuraVisual(frameSpec)
    local cfg = { unit = unit, enabled = false, lanes = {}, laneOrder = {}, visual = visual }
    local auraIconsEnabled = auras.enabled == true and flag and auras[flag] == true
    local needDebuffScan = visual and visual.enabled == true
    if auraIconsEnabled or needDebuffScan then
        local layout, sharedLayout, blacklist, filtersRoot = EffectiveTables(auras, unit)
        local buff = auraIconsEnabled and CompileLane(unit, shared, layout, sharedLayout, blacklist, filtersRoot, "buff", false, nil, true) or nil
        local debuff = (auraIconsEnabled or needDebuffScan)
            and CompileLane(unit, shared, layout, sharedLayout, blacklist, filtersRoot, "debuff", needDebuffScan, visual, auraIconsEnabled == true) or nil
        local visuals = A3.ClassicVisuals
        if visuals and type(visuals.EnrichUnitLane) == "function" then
            if buff then visuals.EnrichUnitLane(buff, layout, sharedLayout, shared, "buff", frameSpec) end
            if debuff then visuals.EnrichUnitLane(debuff, layout, sharedLayout, shared, "debuff", frameSpec) end
        end
        cfg.showTooltip = ReadBool(nil, shared, "showTooltip", true)
        cfg.clickThrough = ReadBool(nil, shared, "clickThroughAuras", false)
        cfg.lanes.buff = buff
        cfg.lanes.debuff = debuff
        if buff then cfg.laneOrder[#cfg.laneOrder + 1] = "buff" end
        if debuff then cfg.laneOrder[#cfg.laneOrder + 1] = "debuff" end
        cfg.visualDirect = debuff and debuff.visualDirect == true or nil
        cfg.enabled = (buff and buff.enabled == true) or (debuff and debuff.enabled == true) or cfg.visualDirect == true
    end

    if A3.ClassicFeatures and type(A3.ClassicFeatures.CompileUnitLanes) == "function" then
        local extraLanes, extraOrder, extraSource = A3.ClassicFeatures.CompileUnitLanes(auras, unit, frameSpec)
        if type(extraLanes) == "table" then
            if type(A3.ClassicFeatures.ApplyAutoExclusions) == "function" then
                A3.ClassicFeatures.ApplyAutoExclusions(cfg.lanes.buff, cfg.lanes.debuff, extraLanes, extraSource, unit)
            end
            for i = 1, type(extraOrder) == "table" and #extraOrder or 0 do
                local kind = extraOrder[i]
                cfg.lanes[kind] = extraLanes[kind]
                cfg.laneOrder[#cfg.laneOrder + 1] = kind
                cfg.enabled = cfg.enabled == true or (extraLanes[kind] and extraLanes[kind].enabled == true)
            end
        end
    end

    return cfg
end

function A3.ResolveUnitFrameConfig(unit, frameSpec)
    unit = NormalizeRuntimeUnit(unit)
    if not unit then return nil end
    if frameSpec ~= nil then
        local gen = A3._runtimeConfigGen or 1
        local cached = frameSpecConfigCache[frameSpec]
        if cached and cached.gen == gen and cached.unit == unit then
            return cached.config
        end
        local cfg = BuildUnitFrameConfig(unit, frameSpec)
        frameSpecConfigCache[frameSpec] = { gen = gen, unit = unit, config = cfg }
        return cfg
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
    local rawKind = tostring(kind or "buff"):lower()
    local customIndex = rawKind:match("^custom(%d)$")
    if customIndex then
        customIndex = math_min(4, math_max(1, tonumber(customIndex) or 1))
        kind = "custom" .. tostring(customIndex)
    else
        kind = (rawKind == "debuff" or rawKind == "debuffs") and "debuff" or "buff"
    end
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
        cols = lane.cols,
        rows = lane.rows,
        width = lane.width,
        height = lane.height,
        alpha = lane.alpha,
        iconZoom = lane.iconZoom,
        iconShape = lane.iconShape,
        growth = lane.growthX,
        rowWrap = lane.growthY,
        growthX = lane.xSign,
        growthY = lane.ySign,
        xSign = lane.xSign,
        ySign = lane.ySign,
        verticalGrowth = lane.verticalGrowth == true,
        initialAnchor = lane.initialAnchor,
        x = lane.x,
        y = lane.y,
        anchor = lane.anchor,
        iconStyle = lane.iconStyle,
        showDurationBar = lane.showDurationBar == true,
        durationBarDisplay = lane.durationBarDisplay,
        durationBarHeight = lane.durationBarHeight,
        durationBarPosition = lane.durationBarPosition,
        durationBarDirection = lane.durationBarDirection,
    }
end

function A3.ResolveAuraPreviewConfig(frame, unit, frameSpec)
    if (_G.InCombatLockdown and _G.InCombatLockdown()) or _G.MSUF_InCombat == true then return nil end
    if frameSpec ~= nil and frame and IsGroupFrame(frame) and frameSpec ~= frame.MSUFSpec then
        local proxy = frame._msufA3AuraPreviewConfigProxy or {}
        frame._msufA3AuraPreviewConfigProxy = proxy
        proxy._msufIsGroupFrame = true
        proxy._msufGFIsPreviewFrame = true
        proxy._msufGFKind = frame._msufGFKind
        proxy.MSUFUnitKey = unit or frame.MSUFUnitKey
        proxy.MSUFSpec = frameSpec
        return ResolveGroupFrameConfig(proxy, proxy.MSUFUnitKey)
    end
    return FrameAuraConfig(frame, unit or (frame and frame.MSUFUnitKey))
end

function A3.UnitFrameAuraEnabled(unit)
    local cfg = A3.ResolveUnitFrameConfig(unit)
    return cfg and cfg.enabled == true
end

--- Era/Mists/TBC do not consistently expose tooltip setters by aura instance
--- ID. Resolve the current filtered index only on mouseover; this never adds
--- work to UNIT_AURA or the render path.
A3._ClassicAuraIndexByInstanceID = function(unit, auraInstanceID, filter)
    if not (GetAuraDataByIndex and auraInstanceID) then return nil end
    local index = 1
    local data = GetAuraDataByIndex(unit, index, filter)
    while data do
        if data.auraInstanceID == auraInstanceID then return index end
        index = index + 1
        data = GetAuraDataByIndex(unit, index, filter)
    end
    return nil
end

local function OnAuraEnter(button)
    if not (button and button:IsVisible() and GameTooltip and not GameTooltip:IsForbidden()) then return end
    local lane = button._msufA3Lane
    if not (lane and lane.config and lane.config.showTooltip and button.auraInstanceID) then return end
    GameTooltip:SetOwner(button, "ANCHOR_CURSOR")
    if button._msufA3WeaponEnchantSlot then
        if GameTooltip.SetInventoryItem then GameTooltip:SetInventoryItem("player", button._msufA3WeaponEnchantSlot) end
        return
    end
    local filter = lane.config.filter
    if lane.config.harmful ~= true and GameTooltip.SetUnitBuffByAuraInstanceID then
        GameTooltip:SetUnitBuffByAuraInstanceID(lane.unit, button.auraInstanceID)
    elseif lane.config.harmful == true and GameTooltip.SetUnitDebuffByAuraInstanceID then
        GameTooltip:SetUnitDebuffByAuraInstanceID(lane.unit, button.auraInstanceID)
    else
        local index = A3._ClassicAuraIndexByInstanceID(lane.unit, button.auraInstanceID, filter)
        if index and lane.config.harmful ~= true and GameTooltip.SetUnitBuff then
            GameTooltip:SetUnitBuff(lane.unit, index, filter)
        elseif index and lane.config.harmful == true and GameTooltip.SetUnitDebuff then
            GameTooltip:SetUnitDebuff(lane.unit, index, filter)
        elseif index and GameTooltip.SetUnitAura then
            GameTooltip:SetUnitAura(lane.unit, index, filter)
        end
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
    local idx = index - 1
    local col, row
    if cfg.verticalGrowth == true then
        row = idx % perRow
        col = (idx - row) / perRow
    else
        col = idx % perRow
        row = (idx - col) / perRow
    end
    local x = col * (cfg.stepX or cfg.step) * cfg.xSign
    local y = row * (cfg.stepY or cfg.step) * cfg.ySign
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
    button:SetSize(cfg.buttonWidth or cfg.size, cfg.buttonHeight or cfg.size)
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
        button._msufA3DispelOverlay._msufA3Shown = nil
        button._msufA3DispelOverlay:Hide()
    end
    if cfg.ownHighlight ~= true and button._msufA3OwnHighlight then
        button._msufA3OwnHighlight._msufA3Shown = nil
        button._msufA3OwnHighlight:Hide()
    end
    PositionButton(lane, button, index)
    local visuals = A3.ClassicVisuals
    if visuals and type(visuals.ApplyButtonLayout) == "function" then
        visuals.ApplyButtonLayout(lane, button)
    end
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

--- Button pools and lane state are runtime-owned. Config may change the desired
--- max/layout, but live buttons stay attached to their lane so delta updates can
--- reuse them without creating frames during combat.
-- Pre-create the visible button pool for single unit frames while out of
-- combat, so the first swap onto an aura-heavy target never pays a burst of
-- CreateFrame calls mid-fight. Group frames keep the lazy path: their pools
-- are per-member, so eager prewarm would multiply login/reload cost across the
-- raid. If group creation spikes regress, fix them with a budgeted render queue
-- instead of creating every member's buttons up front.
local function PrewarmLaneButtons(lane, frame)
    local cfg = lane.config
    if not cfg then return end
    if frame and frame._msufA3GroupRuntime == true then return end
    local want = cfg.max or 0
    if want <= (lane.createdButtons or 0) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    for i = (lane.createdButtons or 0) + 1, want do
        EnsureButton(lane, i)
    end
end

local function ApplyLaneLayout(lane)
    local cfg = lane.config
    if not (lane.frame and cfg) then return end
    lane.frame:ClearAllPoints()
    lane.frame:SetPoint(cfg.anchor, lane.root, cfg.anchor, cfg.x, cfg.y)
    lane.frame:SetSize(cfg.width, cfg.height)
    if lane.frame.SetAlpha then lane.frame:SetAlpha(cfg.alpha or 1) end
    if lane.frame.SetFrameStrata and cfg.strata and cfg.strata ~= "AUTO" then
        lane.frame:SetFrameStrata(cfg.strata)
    end
    if lane.root.GetFrameLevel and lane.frame.SetFrameLevel then
        lane.frame:SetFrameLevel((lane.root:GetFrameLevel() or 0) + cfg.layer)
    end
    for i = 1, lane.createdButtons or 0 do
        local button = lane[i]
        if button then ApplyButtonLayout(lane, button, i) end
    end
end

local HideButton
local HideTrailingButtons
local ClearFrameAuraVisualState
local BuildButtonUpdater
local UpdateButton

local function ResetLaneVisualCache(lane)
    if not lane then return end
    local cfg = lane.config
    local visual = cfg and cfg.visual
    lane._msufA3VisualCacheReady = cfg
        and cfg.enabled == true
        and cfg.visualDirect ~= true
        and visual
        and visual.enabled == true or nil
    lane._msufA3VisualAnyDebuff = nil
    lane._msufA3VisualBorderActive = nil
    lane._msufA3VisualBorderR = nil
    lane._msufA3VisualBorderG = nil
    lane._msufA3VisualBorderB = nil
    lane._msufA3VisualBorderA = nil
    lane._msufA3VisualBorderSecret = nil
    lane._msufA3VisualBorderToken = nil
    lane._msufA3VisualOverlayActive = nil
    lane._msufA3VisualOverlayR = nil
    lane._msufA3VisualOverlayG = nil
    lane._msufA3VisualOverlayB = nil
    lane._msufA3VisualOverlayA = nil
    lane._msufA3VisualOverlaySecret = nil
    lane._msufA3VisualOverlayToken = nil
end

local function ClearLane(lane)
    lane.all = WipeTable(lane.all)
    lane.active = WipeTable(lane.active)
    lane.sorted = WipeTable(lane.sorted)
    lane.ordered = WipeTable(lane.ordered)
    lane.visibleByID = WipeTable(lane.visibleByID)
    lane.orderedCount = 0
    lane.orderDirty = nil
    lane.visible = 0
    lane._msufA3CappedFullScan = nil
    ResetLaneVisualCache(lane)
    for i = 1, lane.createdButtons or 0 do
        local button = lane[i]
        if button then
            button.auraInstanceID = nil
            HideButton(button)
        end
    end
end

local function ResetLaneData(lane, skipOrderScratch)
    lane.all = WipeTable(lane.all)
    lane.active = WipeTable(lane.active)
    if skipOrderScratch ~= true then
        lane.sorted = WipeTable(lane.sorted)
        lane.ordered = WipeTable(lane.ordered)
    end
    lane.visibleByID = WipeTable(lane.visibleByID)
    lane.orderedCount = 0
    lane.orderDirty = nil
    lane._msufA3CappedFullScan = nil
    ResetLaneVisualCache(lane)
end

local function EnsureLane(root, state, kind, cfg)
    local lanes = state.lanes
    local lane = lanes[kind]
    local parent = cfg and cfg.anchorTarget == "portrait"
        and state.frame and state.frame.MSUFPortraitHolder or root
    if lane then
        if parent and lane.root ~= parent and lane.frame and lane.frame.SetParent then
            lane.frame:SetParent(parent)
            lane.root = parent
        end
        return lane
    end
    local frame = CreateFrame("Frame", nil, parent)
    lane = {
        kind = kind,
        root = parent,
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

local function ApplyConfigLane(root, state, cfg, kind)
    local laneConfig = cfg.lanes and cfg.lanes[kind]
    local lane = EnsureLane(root, state, kind, laneConfig)
    lane.unit = cfg.unit
    lane.ownerFrame = state.frame
    lane.config = laneConfig
    if lane.config and lane.config.rootKey then root[lane.config.rootKey] = lane.frame end
    if lane.config and lane.config.enabled then
        if lane.config.sortReverse == true then
            local comparator = SortComparator(lane.config.sortOrder)
            lane.config.sortComparator = function(a, b) return comparator(b, a) end
        elseif not lane.config.sortComparator then
            lane.config.sortComparator = SortComparator(lane.config.sortOrder)
        end
        lane.updateButton = BuildButtonUpdater and BuildButtonUpdater(lane.config) or UpdateButton
        if lane.config.renderEnabled == true then
            lane.frame:Show()
            ApplyLaneLayout(lane)
            PrewarmLaneButtons(lane, state.frame)
        else
            lane.frame:Hide()
        end
    else
        lane.updateButton = nil
        lane.frame:Hide()
        ClearLane(lane)
    end
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

    for kind, lane in pairs(state.lanes) do
        if not (cfg.lanes and cfg.lanes[kind]) then
            lane.config = nil
            lane.frame:Hide()
            ClearLane(lane)
        end
    end
    local order = cfg.laneOrder or A3._ClassicBaseLaneOrder
    for i = 1, #order do ApplyConfigLane(root, state, cfg, order[i]) end
    return state
end

local function HideState(frame)
    local state = frame and frame._msufA3State
    if not state then return end
    for _, lane in pairs(state.lanes or {}) do
        -- Portrait-anchored lanes are parented outside state.root, so hiding
        -- only the root can leave their already-rendered buttons on screen.
        if lane.frame then lane.frame:Hide() end
        ClearLane(lane)
    end
    if state.root then state.root:Hide() end
    ClearFrameAuraVisualState(frame)
end

--- Token-filter membership. C_UnitAuras.IsAuraFilteredOutByInstanceID has no
--- engine-validated consumer on any Classic branch and reported every aura as
--- filtered on Mists, which turned each token filter into an empty lane.
--- Blizzard's own Classic UI evaluates filter tokens through aura scans
--- (Blizzard_RaidUI walks "HELPFUL|RAID|PLAYER"), so membership is derived
--- from the same scan primitive: one filtered instance-ID scan per
--- unit+filter, cached until the unit's next aura event bumps its serial.
--- (State and helpers hang off A3: this file runs at the 200-local ceiling.)
A3._ClassicAuraTokenSets = A3._ClassicAuraTokenSets or {}
A3._ClassicAuraTokenSerial = A3._ClassicAuraTokenSerial or {}
A3._ClassicAuraTokenSet = function(unit, filter)
    local key = unit .. "|" .. filter
    local serial = A3._ClassicAuraTokenSerial[unit] or 0
    local entry = A3._ClassicAuraTokenSets[key]
    if entry and entry.serial == serial then return entry.set end
    if not entry then
        entry = { set = {} }
        A3._ClassicAuraTokenSets[key] = entry
    end
    local set = WipeTable(entry.set)
    entry.set = set
    entry.serial = serial
    local getInstanceIDs = C_UnitAuras and C_UnitAuras.GetUnitAuraInstanceIDs
    if type(getInstanceIDs) == "function" then
        local ids = getInstanceIDs(unit, filter)
        if type(ids) == "table" and not IsSecret(ids) then
            for i = 1, #ids do
                local id = ids[i]
                if id ~= nil and not IsSecret(id) then set[id] = true end
            end
        end
        return set
    end
    if GetAuraSlots and GetAuraDataBySlot then
        local slots, count = FillAuraSlots(entry.scratch or {}, GetAuraSlots(unit, filter))
        entry.scratch = slots
        for i = 2, count do
            local data = GetAuraDataBySlot(unit, slots[i])
            local id = data and data.auraInstanceID
            if id ~= nil and not IsSecret(id) then set[id] = true end
        end
    end
    return set
end

local function Filtered(unit, auraInstanceID, filter)
    if unit == nil or auraInstanceID == nil or filter == nil then return false end
    return A3._ClassicAuraTokenSet(unit, filter)[auraInstanceID] ~= true
end

local function ProcessData(lane, unit, data)
    if type(data) ~= "table" then return nil end
    local auraInstanceID = data.auraInstanceID
    if auraInstanceID == nil then return nil end
    local cfg = lane.config
    if cfg.needsPlayerFlag == true then
        -- Mists/TBC do not reliably populate isFromPlayerOrPlayerPet (the
        -- player's own party-frame HoTs carried false/nil, which blanked
        -- "only mine" lanes). Blizzard's Classic frames identify own casts
        -- by the caster unit, so sourceUnit is authoritative here; the
        -- membership fallback only covers auras with no readable caster.
        local sourceUnit = data.sourceUnit
        local fromPlayer = data.isFromPlayerOrPlayerPet
        if sourceUnit ~= nil and not IsSecret(sourceUnit) then
            data.isPlayerAura = sourceUnit == "player"
                or sourceUnit == "pet" or sourceUnit == "vehicle"
        elseif fromPlayer ~= nil and not IsSecret(fromPlayer) then
            data.isPlayerAura = fromPlayer == true
        else
            data.isPlayerAura = not Filtered(unit, auraInstanceID, cfg.playerFilter)
        end
    end
    return data
end

local function Blacklisted(cfg, data)
    local blacklist = cfg.blacklist
    if not blacklist then return false end
    local spellID = data and data.spellId
    if spellID == nil or IsSecret(spellID) then return false end
    if type(spellID) == "number" then
        return blacklist[spellID] == true
    end
    spellID = tonumber(spellID)
    return spellID and blacklist[math_floor(spellID + 0.5)] == true or false
end

local function MatchFilter(unit, auraInstanceID, filter)
    return not Filtered(unit, auraInstanceID, filter)
end

local function AuraDispelColorByCurve(curve, unit, data)
    if not (curve and unit and data and data.auraInstanceID and GetAuraDispelTypeColor) then
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
    local color = GetAuraDispelTypeColor(unit, data.auraInstanceID, curve)
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

local function AuraDispelColor(cfg, unit, data)
    return AuraDispelColorByCurve(cfg and cfg.dispelColorCurve, unit, data)
end

local function AuraDispelNoneColor(cfg)
    if cfg and cfg.dispelNoneReady == true then
        if cfg.dispelNoneSecret == true then
            return true, cfg.dispelNoneR, cfg.dispelNoneG, cfg.dispelNoneB, cfg.dispelNoneA, true
        end
        return true, cfg.dispelNoneR, cfg.dispelNoneG, cfg.dispelNoneB, cfg.dispelNoneA or 1, false
    end
    local curve = cfg and cfg.dispelColorCurve
    if not (curve and curve.Evaluate) then return false end
    local color = curve:Evaluate(0)
    local r, g, b, a = ColorObjectRGBA(color)
    if r then return true, r, g, b, a or 1, HasSecretColor(r, g, b, a) end
    return false
end

local function MatchDispelTrigger(lane, unit, data, trigger)
    if not (lane and data) then return false end
    if trigger == "ANY_DEBUFF" then
        return true
    elseif trigger == "PLAYER_CAST" then
        return data.isPlayerAura == true
    elseif trigger == "DISPEL_TYPE" then
        local dispelName = PlainString(data.dispelName)
        return dispelName ~= nil and dispelName ~= ""
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

local function DirectDispelVisualColor(visual, unit, data)
    if visual and visual.colorMode == "TYPE" then
        local hasColor, r, g, b, a, secret = AuraDispelColorByCurve(visual.dispelColorCurve, unit, data)
        if hasColor then return r, g, b, a, secret == true end
    end
    return visual and visual.r or 0.25, visual and visual.g or 0.75, visual and visual.b or 1, visual and visual.a or 1, false
end

local function ResolveDirectDispelTriggerVisual(unit, visual, trigger)
    local filter = DirectVisualFilterForTrigger(trigger)
    if not (filter and GetAuraDataByIndex and IsUnitToken(unit)) then
        return false
    end
    local data = GetAuraDataByIndex(unit, 1, filter)
    if not (data and data.auraInstanceID) then
        return false
    end
    if trigger == "DISPEL_TYPE" then
        local dispelName = PlainString(data.dispelName)
        if dispelName == nil or dispelName == "" then return false end
    end
    local token = data.auraInstanceID
    if IsSecret(token) then token = nil end
    local r, g, b, a, secret = DirectDispelVisualColor(visual, unit, data)
    return true, r, g, b, a, secret == true, token
end

local function ConsiderLaneAuraVisual(lane, unit, data)
    if not (lane and lane._msufA3VisualCacheReady == true and data) then return end
    local visual = lane.config and lane.config.visual
    if not (visual and visual.enabled == true) then return end
    if lane._msufA3VisualAnyDebuff == true
        and (visual.borderEnabled ~= true or lane._msufA3VisualBorderActive == true)
        and (visual.overlayEnabled ~= true or lane._msufA3VisualOverlayActive == true) then
        return
    end
    lane._msufA3VisualAnyDebuff = true

    local borderMatched = false
    if visual.borderEnabled == true and lane._msufA3VisualBorderActive ~= true then
        borderMatched = MatchDispelTrigger(lane, unit, data, visual.borderTrigger)
        if borderMatched then
            local token = data.auraInstanceID
            if IsSecret(token) then token = nil end
            local r, g, b, a, secret = DispelVisualColor(lane, visual, unit, data)
            lane._msufA3VisualBorderActive = true
            lane._msufA3VisualBorderR, lane._msufA3VisualBorderG = r, g
            lane._msufA3VisualBorderB, lane._msufA3VisualBorderA = b, a
            lane._msufA3VisualBorderSecret = secret == true
            lane._msufA3VisualBorderToken = token
        end
    end

    if visual.overlayEnabled == true and lane._msufA3VisualOverlayActive ~= true then
        if visual.overlayTrigger == visual.borderTrigger then
            if lane._msufA3VisualBorderActive == true then
                lane._msufA3VisualOverlayActive = true
                lane._msufA3VisualOverlayR = lane._msufA3VisualBorderR
                lane._msufA3VisualOverlayG = lane._msufA3VisualBorderG
                lane._msufA3VisualOverlayB = lane._msufA3VisualBorderB
                lane._msufA3VisualOverlayA = lane._msufA3VisualBorderA
                lane._msufA3VisualOverlaySecret = lane._msufA3VisualBorderSecret
                lane._msufA3VisualOverlayToken = lane._msufA3VisualBorderToken
            end
        elseif MatchDispelTrigger(lane, unit, data, visual.overlayTrigger) then
            local token = data.auraInstanceID
            if IsSecret(token) then token = nil end
            local r, g, b, a, secret = DispelVisualColor(lane, visual, unit, data)
            lane._msufA3VisualOverlayActive = true
            lane._msufA3VisualOverlayR, lane._msufA3VisualOverlayG = r, g
            lane._msufA3VisualOverlayB, lane._msufA3VisualOverlayA = b, a
            lane._msufA3VisualOverlaySecret = secret == true
            lane._msufA3VisualOverlayToken = token
        end
    end
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
    local spellID = data and data.spellId
    if spellID == nil or IsSecret(spellID) then return false end
    if type(spellID) == "number" then
        return SATED_SPELLS[spellID] == true
    end
    spellID = tonumber(spellID)
    return spellID and SATED_SPELLS[math_floor(spellID + 0.5)] == true or false
end

local function ShouldShowAura(lane, unit, data)
    local cfg = lane.config
    if A3.ClassicFeatures and type(A3.ClassicFeatures.IsAutoExcluded) == "function"
        and A3.ClassicFeatures.IsAutoExcluded(cfg, data) then
        return false
    end
    if Blacklisted(cfg, data) then return false end
    if cfg.classicFeatureMatch == true and A3.ClassicFeatures
        and type(A3.ClassicFeatures.MatchAura) == "function" then
        return A3.ClassicFeatures.MatchAura(cfg, unit, data, MatchFilter)
    end
    if type(cfg.includeSpellIDs) == "table" then
        local spellID = data and data.spellId
        local matched = spellID ~= nil and not IsSecret(spellID)
            and cfg.includeSpellIDs[tonumber(spellID)] == true
        if not matched and type(cfg.includeSpellNames) == "table" then
            -- Rank/alias drift: fall back to the aura name so a whitelisted
            -- spell still matches when the live aura reports another spellId.
            local name = data and data.name
            matched = name ~= nil and not IsSecret(name)
                and cfg.includeSpellNames[name] == true
        end
        if not matched then return false end
    end
    if cfg.hidePermanent == true and not TimedAura(data) then return false end
    if cfg.maxDuration and cfg.maxDuration > 0 then
        local duration = PlainNumber(data and data.duration) or 0
        if duration > cfg.maxDuration then return false end
    end
    if cfg.satedFilter == true and SatedAura(data) then
        if cfg.showSated ~= true then return false end
        local threshold = cfg.satedThreshold or 0
        local remaining = threshold > 0 and RemainingTime(data) or nil
        if remaining and remaining > threshold then return false end
    end
    if cfg.filterRequirements and A3.ClassicFeatures
        and type(A3.ClassicFeatures.MatchFilterRequirements) == "function" then
        return A3.ClassicFeatures.MatchFilterRequirements(
            cfg.filterPlan or cfg.filterRequirements, unit, data, MatchFilter)
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
    if type(data) == "table" then
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
    if not data then return false, nil end
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
        if lane._msufA3VisualCacheReady == true then
            ConsiderLaneAuraVisual(lane, unit, data)
        end
        return true, data
    end
    if ShouldShowAura(lane, unit, data) then
        lane.active[auraInstanceID] = true
        if lane._msufA3VisualCacheReady == true then
            ConsiderLaneAuraVisual(lane, unit, data)
        end
        return true, data
    end
    lane.active[auraInstanceID] = nil
    lane.orderDirty = true
    return false, data
end

local function AddVisibleAuraToCappedLane(lane, unit, data)
    data = ProcessData(lane, unit, data)
    if not data then return false, nil end
    if lane.config.hasFilterWork == true and ShouldShowAura(lane, unit, data) ~= true then
        return false, data
    end
    local auraInstanceID = data.auraInstanceID
    lane.all[auraInstanceID] = data
    lane.active[auraInstanceID] = true
    if lane._msufA3VisualCacheReady == true then
        ConsiderLaneAuraVisual(lane, unit, data)
    end
    return true, data
end

local AURA_UTIL_SCAN = {}

--- Full scans rebuild lane state from Blizzard aura data. Deltas are preferred
--- for normal UNIT_AURA, but full scans remain the correctness fallback when
--- Blizzard reports isFullUpdate, the capped visible-only scan loses context,
--- config changes, or identity changes make old lane state untrustworthy.
local function AuraUtilScanCallback(data)
    local scan = AURA_UTIL_SCAN
    local lane = scan.lane
    local unit = scan.unit
    local active, processed = scan.addAura(lane, unit, data)
    if scan.inlineRender == true
        and active == true
        and processed
        and scan.visible < scan.maxVisible then
        local visible = scan.visible + 1
        scan.visible = visible
        local button = EnsureButton(lane, visible)
        scan.updateButton(lane, button, unit, processed)
        scan.visibleByID[processed.auraInstanceID] = visible
        if scan.capped == true and visible >= scan.maxVisible then return true end
    end
end

function A3._AppendClassicWeaponEnchants(lane, unit, inlineRender, visible, maxVisible, visibleByID, updateButton)
    local cfg = lane and lane.config
    if not (cfg and cfg.weaponEnchants == true and unit == "player" and type(_G.GetWeaponEnchantInfo) == "function") then
        return visible
    end
    local values = { _G.GetWeaponEnchantInfo() }
    local now = _G.GetTime and _G.GetTime() or 0
    local slots = { 16, 17, 18 }
    for itemIndex = #slots, 1, -1 do
        local base = (itemIndex - 1) * 4
        local hasEnchant = values[base + 1]
        local expirationMS = tonumber(values[base + 2])
        if hasEnchant == true and expirationMS and expirationMS > 0 then
            local slot = slots[itemIndex]
            local remaining = expirationMS * 0.001
            local duration = remaining <= 600 and 600
                or (remaining <= 1800 and 1800 or math_ceil(remaining / 3600) * 3600)
            local data = {
                auraInstanceID = -1000 - slot,
                isHelpful = true,
                isHarmful = false,
                isFromPlayerOrPlayerPet = true,
                isPlayerAura = true,
                name = _G.ENCHANTED or "Weapon Enchant",
                icon = _G.GetInventoryItemTexture and _G.GetInventoryItemTexture("player", slot) or nil,
                applications = tonumber(values[base + 3]) or 0,
                duration = duration,
                expirationTime = now + remaining,
                timeMod = 1,
                spellId = 0,
                _msufA3WeaponEnchantSlot = slot,
            }
            lane.all[data.auraInstanceID] = data
            lane.active[data.auraInstanceID] = true
            lane.orderedCount = (lane.orderedCount or 0) + 1
            lane.ordered[lane.orderedCount] = data.auraInstanceID
            if inlineRender == true and visible < maxVisible then
                visible = visible + 1
                local button = EnsureButton(lane, visible)
                updateButton(lane, button, unit, data)
                visibleByID[data.auraInstanceID] = visible
            end
        end
    end
    return visible
end

local function FullScanLane(lane, unit, renderInline)
    local cfg = lane.config
    if not (cfg and cfg.enabled) then return false end

    local inlineRender = renderInline == true
        and cfg.naturalOrder == true
        and cfg.renderEnabled == true
        and cfg.max > 0
    local cappedScan = inlineRender
        and cfg.visibleOnlyScan == true
        and (cfg.hasFilterWork ~= true or cfg.cappedFilterScan == true)
    local visibleByID = inlineRender and lane.visibleByID or nil
    local updateButton = inlineRender and (lane.updateButton or UpdateButton) or nil
    local visible = 0
    local maxVisible = cfg.max or 0
    local slotLimit = cappedScan and maxVisible or nil
    local addAura = cappedScan and AddVisibleAuraToCappedLane or AddAuraToLane
    ResetLaneData(lane, cappedScan)
    lane._msufA3CappedFullScan = cappedScan or nil
    visible = A3._AppendClassicWeaponEnchants(lane, unit, inlineRender, visible, maxVisible, visibleByID, updateButton)

    if GetAuraSlots and GetAuraDataBySlot then
        if not cappedScan then
            local slots, count
            slots, count = FillAuraSlots(lane.slotScratch, GetAuraSlots(unit, cfg.filter))
            lane.slotScratch = slots
            if inlineRender then
                for i = 2, count do
                    local active, processed = addAura(lane, unit, GetAuraDataBySlot(unit, slots[i]))
                    if active == true and processed and visible < maxVisible then
                        visible = visible + 1
                        local button = EnsureButton(lane, visible)
                        updateButton(lane, button, unit, processed)
                        visibleByID[processed.auraInstanceID] = visible
                    end
                end
            else
                for i = 2, count do
                    addAura(lane, unit, GetAuraDataBySlot(unit, slots[i]))
                end
            end
        else
            local continuation
            while true do
                local slots, count
                if continuation ~= nil then
                    slots, count = FillAuraSlots(lane.slotScratch, GetAuraSlots(unit, cfg.filter, slotLimit, continuation))
                else
                    slots, count = FillAuraSlots(lane.slotScratch, GetAuraSlots(unit, cfg.filter, slotLimit))
                end
                lane.slotScratch = slots
                continuation = slots[1]
                for i = 2, count do
                    local active, processed = addAura(lane, unit, GetAuraDataBySlot(unit, slots[i]))
                    if active == true and processed and visible < maxVisible then
                        visible = visible + 1
                        local button = EnsureButton(lane, visible)
                        updateButton(lane, button, unit, processed)
                        visibleByID[processed.auraInstanceID] = visible
                        if visible >= maxVisible then break end
                    end
                end
                if visible >= maxVisible or IsSecret(continuation) or continuation == nil then
                    break
                end
            end
        end
        if inlineRender then HideTrailingButtons(lane, visibleByID, visible) end
        return true, inlineRender
    end

    local forEachAura = AuraUtil and AuraUtil.ForEachAura
    if type(forEachAura) == "function" then
        local auraUtilLimit = cappedScan and cfg.hasFilterWork ~= true and maxVisible or nil
        local scan = AURA_UTIL_SCAN
        scan.lane = lane
        scan.unit = unit
        scan.addAura = addAura
        scan.inlineRender = inlineRender
        scan.visibleByID = visibleByID
        scan.updateButton = updateButton
        scan.maxVisible = maxVisible
        scan.visible = visible
        scan.capped = cappedScan
        forEachAura(unit, cfg.filter, auraUtilLimit, AuraUtilScanCallback, true)
        visible = scan.visible or visible
        scan.lane = nil
        scan.unit = nil
        scan.addAura = nil
        scan.inlineRender = nil
        scan.visibleByID = nil
        scan.updateButton = nil
        scan.maxVisible = nil
        scan.visible = nil
        scan.capped = nil
        if inlineRender then HideTrailingButtons(lane, visibleByID, visible) end
        return true, inlineRender
    end

    if inlineRender then HideTrailingButtons(lane, visibleByID, visible) end
    return true, inlineRender
end

local function ShowButton(button)
    if button._msufA3Shown ~= true then
        button._msufA3Shown = true
        button:Show()
    end
end

HideButton = function(button)
    local visuals = A3.ClassicVisuals
    if visuals and type(visuals.HideButtonVisual) == "function" then visuals.HideButtonVisual(button) end
    -- ClearLane intentionally invalidates auraInstanceID before reaching this
    -- helper. Always hide here so a stale/missing visibility marker cannot
    -- leave a pooled Classic aura button visible after its container is off.
    button._msufA3Shown = nil
    button:Hide()
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
        if cooldown.Clear then cooldown:Clear() end
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
        if tex and tex._msufA3Shown ~= nil then
            tex._msufA3Shown = nil
            tex:Hide()
        end
        return
    end
    local hasColor, r, g, b, a, secret = AuraDispelColor(cfg, unit, data)
    if not hasColor then
        hasColor, r, g, b, a, secret = AuraDispelNoneColor(cfg)
    end
    local tex = button._msufA3DispelOverlay
    if hasColor then
        tex = tex or EnsureDispelTypeOverlay(button)
        r, g, b, a = r or 1, g or 1, b or 1, a or 1
        if secret == true or tex._msufA3ColorPlain ~= true
            or tex._msufA3R ~= r or tex._msufA3G ~= g
            or tex._msufA3B ~= b or tex._msufA3A ~= a then
            tex:SetVertexColor(r, g, b, a)
            if secret == true then
                tex._msufA3ColorPlain = nil
            else
                tex._msufA3ColorPlain = true
                tex._msufA3R, tex._msufA3G, tex._msufA3B, tex._msufA3A = r, g, b, a
            end
        end
        if tex._msufA3Shown ~= true then
            tex._msufA3Shown = true
            tex:Show()
        end
    elseif tex then
        if tex._msufA3Shown ~= nil then
            tex._msufA3Shown = nil
            tex:Hide()
        end
    end
end

local function UpdateOwnHighlight(button, cfg, data)
    local active = cfg and cfg.ownHighlight == true and data and data.isPlayerAura == true
    local tex = button._msufA3OwnHighlight
    if active then
        tex = EnsureOwnHighlight(button)
        local r, g, b, a = cfg.ownR or 1, cfg.ownG or 1, cfg.ownB or 1, 0.24
        if tex._msufA3ColorPlain ~= true
            or tex._msufA3R ~= r or tex._msufA3G ~= g
            or tex._msufA3B ~= b or tex._msufA3A ~= a then
            tex:SetVertexColor(r, g, b, a)
            tex._msufA3ColorPlain = true
            tex._msufA3R, tex._msufA3G, tex._msufA3B, tex._msufA3A = r, g, b, a
        end
        if tex._msufA3Shown ~= true then
            tex._msufA3Shown = true
            tex:Show()
        end
    elseif tex then
        if tex._msufA3Shown ~= nil then
            tex._msufA3Shown = nil
            tex:Hide()
        end
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
    cooldown._msufA3TextColorPlain = nil
    cooldown._msufA3TextR, cooldown._msufA3TextG, cooldown._msufA3TextB = nil, nil, nil
end

local function ApplyCooldownTextColor(cooldown, cfg, data)
    if not (cooldown and cfg and cfg.showCooldownText ~= false and cfg.cooldownTextBuckets == true) then return end
    local r, g, b = CooldownTextRGB(cfg, data)
    if cooldown._msufA3TextColorPlain == true
        and cooldown._msufA3TextR == r
        and cooldown._msufA3TextG == g
        and cooldown._msufA3TextB == b then
        return
    end
    if cooldown.SetCooldownTextColor then
        cooldown:SetCooldownTextColor(r, g, b, 1)
        cooldown._msufA3ColorApplied = true
        cooldown._msufA3TextColorPlain = true
        cooldown._msufA3TextR, cooldown._msufA3TextG, cooldown._msufA3TextB = r, g, b
        return
    end
    if cooldown.SetTextColor then
        cooldown:SetTextColor(r, g, b, 1)
        cooldown._msufA3ColorApplied = true
        cooldown._msufA3TextColorPlain = true
        cooldown._msufA3TextR, cooldown._msufA3TextG, cooldown._msufA3TextB = r, g, b
        return
    end
    local region = CooldownTextRegion(cooldown)
    if region then
        MarkCooldownTextColor(cooldown, region, r, g, b)
        cooldown._msufA3TextColorPlain = true
        cooldown._msufA3TextR, cooldown._msufA3TextG, cooldown._msufA3TextB = r, g, b
    end
end

local function UpdateLaneFromDelta(lane, unit, updateInfo)
    local cfg = lane.config
    if not (cfg and cfg.enabled) then return false end
    local needsRender = false
    local visualEnabled = cfg.visual and cfg.visual.enabled == true and cfg.visualDirect ~= true
    local visualDirty = false
    local updateButton = lane.updateButton or UpdateButton

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
                    if visualEnabled and wasActive then
                        lane._msufA3VisualCacheReady = nil
                        visualDirty = true
                    end
                    if nowActive then
                        lane.active[auraInstanceID] = true
                        if visualEnabled and not wasActive then
                            ConsiderLaneAuraVisual(lane, unit, data)
                        end
                        if wasActive then
                            if cfg.reorderOnUpdate == true or oldPlayer ~= data.isPlayerAura then
                                needsRender = true
                            else
                                local index = lane.visibleByID and lane.visibleByID[auraInstanceID]
                                local button = index and lane[index]
                                if button then
                                    updateButton(lane, button, unit, data)
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
                        if visualEnabled then
                            lane._msufA3VisualCacheReady = nil
                            visualDirty = true
                        end
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
                    if visualEnabled then
                        lane._msufA3VisualCacheReady = nil
                        visualDirty = true
                    end
                    lane.active[auraInstanceID] = nil
                    needsRender = true
                end
            end
        end
    end

    return needsRender, visualDirty
end

local function UpdateCappedLaneFromDelta(lane, unit, updateInfo)
    local cfg = lane.config
    if not (cfg and cfg.enabled) then return false, false end

    local added = updateInfo and updateInfo.addedAuras
    if added then
        for i = 1, #added do
            local data = added[i]
            if data and data.auraInstanceID ~= nil and DataMatchesLane(data, cfg) then
                if cfg.hasFilterWork ~= true or ShouldShowAura(lane, unit, data) == true then
                    return true, true
                end
            end
        end
    end

    local needsFullScan = false
    local changed = false
    local removed = updateInfo and updateInfo.removedAuraInstanceIDs
    if removed then
        for i = 1, #removed do
            local auraInstanceID = removed[i]
            if auraInstanceID ~= nil and lane.all[auraInstanceID] then
                if lane.active[auraInstanceID] == true then
                    needsFullScan = true
                end
                lane.all[auraInstanceID] = nil
                lane.active[auraInstanceID] = nil
                lane.orderDirty = true
            end
        end
        if needsFullScan then return true, true end
    end

    local updated = updateInfo and updateInfo.updatedAuraInstanceIDs
    if updated and GetAuraDataByAuraInstanceID then
        local visibleByID = lane.visibleByID
        local updateButton = lane.updateButton or UpdateButton
        for i = 1, #updated do
            local auraInstanceID = updated[i]
            if auraInstanceID ~= nil and lane.all[auraInstanceID] then
                local data = ProcessData(lane, unit, GetAuraDataByAuraInstanceID(unit, auraInstanceID))
                local wasActive = lane.active[auraInstanceID] == true
                if data then
                    lane.all[auraInstanceID] = data
                    local nowActive = cfg.hasFilterWork ~= true or ShouldShowAura(lane, unit, data)
                    if nowActive then
                        lane.active[auraInstanceID] = true
                        local index = visibleByID and visibleByID[auraInstanceID]
                        local button = index and lane[index]
                        if wasActive and button then
                            updateButton(lane, button, unit, data)
                            changed = true
                        else
                            return true, true
                        end
                    else
                        lane.active[auraInstanceID] = nil
                        lane.orderDirty = true
                        if wasActive then return true, true end
                    end
                else
                    lane.all[auraInstanceID] = nil
                    lane.active[auraInstanceID] = nil
                    lane.orderDirty = true
                    if wasActive then return true, true end
                end
            end
        end
    end

    return changed, false
end

local function SetIcon(button, icon)
    local tex = button.Icon
    if not tex then return end
    if IsSecret(icon) then
        tex:SetTexture(icon)
        button._msufA3IconPlain = nil
        button._msufA3Icon = nil
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

local UpdateButtonStacks
if GetAuraApplicationDisplayCount then
    UpdateButtonStacks = function(button, unit, data)
        local applications = data.applications
        if not IsSecret(applications) and type(applications) == "number" then
            SetCount(button, applications > 1 and applications or "")
            return
        end
        SetCount(button, GetAuraApplicationDisplayCount(unit, data.auraInstanceID, 2, 999))
    end
else
    UpdateButtonStacks = function(button, unit, data)
        local applications = data.applications
        if not IsSecret(applications) and type(applications) == "number" then
            SetCount(button, applications > 1 and applications or "")
        else
            SetCount(button, "")
        end
    end
end

-- Classic never uses GetAuraDuration/SetCooldownFromDurationObject: no
-- Blizzard UI on any Classic branch exercises that API pair, and on
-- Mists/TBC it painted hour-scale cooldowns (millisecond-scale values read
-- as seconds -- the "1h Renewing Mist" report). Classic aura duration and
-- expiration are plain numbers, so the raw SetCooldown pair that Blizzard's
-- own Classic target frame uses is the only correct path.
local function UpdateCooldown(button, cooldown, unit, data)
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

    if button._msufA3CooldownPlain ~= nil then
        button._msufA3CooldownStart = nil
        button._msufA3CooldownDuration = nil
        button._msufA3CooldownPlain = nil
    end
    HideCooldown(button, cooldown)
end

UpdateButton = function(lane, button, unit, data)
    local cfg = lane.config
    button.auraInstanceID = data.auraInstanceID
    button._msufA3WeaponEnchantSlot = data._msufA3WeaponEnchantSlot
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
        UpdateButtonStacks(button, unit, data)
    end
    if cfg.ownHighlight == true or button._msufA3OwnHighlight then
        UpdateOwnHighlight(button, cfg, data)
    end
    if cfg.showDispelTypeBorder == true or button._msufA3DispelOverlay then
        UpdateDispelTypeOverlay(button, lane, unit, data)
    end
    ShowButton(button)
end

local function UpdateButtonHeader(lane, button, data)
    button.auraInstanceID = data.auraInstanceID
    button._msufA3WeaponEnchantSlot = data._msufA3WeaponEnchantSlot
    SetIcon(button, data.icon)
end

local function UpdateButtonCooldownOnly(lane, button, unit, data)
    UpdateButtonHeader(lane, button, data)
    UpdateCooldown(button, button.Cooldown, unit, data)
    ShowButton(button)
end

local function UpdateButtonCooldownStacks(lane, button, unit, data)
    UpdateButtonHeader(lane, button, data)
    UpdateCooldown(button, button.Cooldown, unit, data)
    UpdateButtonStacks(button, unit, data)
    ShowButton(button)
end

local function UpdateButtonCooldownBuckets(lane, button, unit, data)
    UpdateButtonHeader(lane, button, data)
    local cooldown = button.Cooldown
    UpdateCooldown(button, cooldown, unit, data)
    ApplyCooldownTextColor(cooldown, lane.config, data)
    ShowButton(button)
end

local function UpdateButtonCooldownBucketsStacks(lane, button, unit, data)
    UpdateButtonHeader(lane, button, data)
    local cooldown = button.Cooldown
    UpdateCooldown(button, cooldown, unit, data)
    ApplyCooldownTextColor(cooldown, lane.config, data)
    UpdateButtonStacks(button, unit, data)
    ShowButton(button)
end

local function UpdateButtonStacksOnly(lane, button, unit, data)
    UpdateButtonHeader(lane, button, data)
    UpdateButtonStacks(button, unit, data)
    ShowButton(button)
end

local function UpdateButtonBasic(lane, button, unit, data)
    UpdateButtonHeader(lane, button, data)
    ShowButton(button)
end

BuildButtonUpdater = function(cfg)
    if not cfg then return UpdateButton end

    local core
    if cfg.showCooldown == true then
        if cfg.cooldownTextBuckets == true and cfg.showCooldownText ~= false then
            core = cfg.showStacks ~= false and UpdateButtonCooldownBucketsStacks or UpdateButtonCooldownBuckets
        else
            core = cfg.showStacks ~= false and UpdateButtonCooldownStacks or UpdateButtonCooldownOnly
        end
    else
        core = cfg.showStacks ~= false and UpdateButtonStacksOnly or UpdateButtonBasic
    end

    local visuals = A3.ClassicVisuals
    if visuals and type(visuals.UpdateButtonVisual) == "function" then
        local rawCore = core
        core = function(lane, button, unit, data)
            rawCore(lane, button, unit, data)
            visuals.UpdateButtonVisual(lane, button, unit, data)
        end
    end

    local own = cfg.ownHighlight == true
    local dispel = cfg.showDispelTypeBorder == true
    if own and dispel then
        return function(lane, button, unit, data)
            core(lane, button, unit, data)
            UpdateOwnHighlight(button, lane.config, data)
            UpdateDispelTypeOverlay(button, lane, unit, data)
        end
    elseif own then
        return function(lane, button, unit, data)
            core(lane, button, unit, data)
            UpdateOwnHighlight(button, lane.config, data)
        end
    elseif dispel then
        return function(lane, button, unit, data)
            core(lane, button, unit, data)
            UpdateDispelTypeOverlay(button, lane, unit, data)
        end
    end
    return core
end

HideTrailingButtons = function(lane, visibleByID, visible)
    local oldVisible = lane.visible or 0
    if visible >= oldVisible then
        lane.visible = visible
        return
    end
    for i = visible + 1, oldVisible do
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
    local updateButton = lane.updateButton or UpdateButton
    local visible = 0
    local maxVisible = cfg.max
    for i = 1, lane.orderedCount or 0 do
        local auraInstanceID = ordered[i]
        if active[auraInstanceID] then
            local data = all[auraInstanceID]
            if data then
                visible = visible + 1
                local button = EnsureButton(lane, visible)
                updateButton(lane, button, unit, data)
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
    local updateButton = lane.updateButton or UpdateButton
    for i = 1, visible do
        local button = EnsureButton(lane, i)
        local data = sorted[i]
        updateButton(lane, button, unit, data)
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

A3._UpdateClassicDispelSymbols = function(frame, lane, visual, unit)
    local renderer = A3.ClassicVisuals
    if not (renderer and type(renderer.UpdateDispelSymbols) == "function") then return false end
    local symbol = visual and visual.symbol
    if not (symbol and symbol.enabled == true and lane and lane.all) then
        return renderer.HideDispelSymbols and renderer.HideDispelSymbols(frame) or false
    end
    local present = {}
    for _, data in pairs(lane.all) do
        local dispelName = PlainString(data and data.dispelName)
        if dispelName and dispelName ~= "" then
            local matched = symbol.trigger == "DISPEL_TYPE"
                or MatchDispelTrigger(lane, unit, data, symbol.trigger)
            if matched then present[dispelName] = true end
        end
    end
    return renderer.UpdateDispelSymbols(frame, visual, present)
end

local function HasActiveDebuff(lane)
    return lane and lane.active and next(lane.active) ~= nil or false
end

local function StoreLaneAuraVisualCache(lane, anyDebuff, borderActive, br, bg, bb, ba, borderSecret, borderToken, overlayActive, orr, og, ob, oa, overlaySecret, overlayToken)
    lane._msufA3VisualCacheReady = true
    lane._msufA3VisualAnyDebuff = anyDebuff == true
    lane._msufA3VisualBorderActive = borderActive == true
    lane._msufA3VisualBorderR, lane._msufA3VisualBorderG = br, bg
    lane._msufA3VisualBorderB, lane._msufA3VisualBorderA = bb, ba
    lane._msufA3VisualBorderSecret = borderSecret == true
    lane._msufA3VisualBorderToken = borderToken
    lane._msufA3VisualOverlayActive = overlayActive == true
    lane._msufA3VisualOverlayR, lane._msufA3VisualOverlayG = orr, og
    lane._msufA3VisualOverlayB, lane._msufA3VisualOverlayA = ob, oa
    lane._msufA3VisualOverlaySecret = overlaySecret == true
    lane._msufA3VisualOverlayToken = overlayToken
end

local function NotifyFrameAuraVisuals(frame)
    if not frame then return end
    if frame._msufA3DeferAuraVisualNotify == true then
        return
    end
    local active = frame._msufActiveElements
    local elements = UF and UF.elements
    local borders = active and active.Borders == true and elements and elements.Borders
    if borders and borders.Update then
        borders.Update(frame, "MSUF_A3_AURA_VISUAL", A3._ClassicBindFrameUnit(frame))
    end
    if frame.MSUFSpec and frame.MSUFSpec.scope == "group" then
        local visuals = active and active.GroupVisuals == true and elements and elements.GroupVisuals
        if visuals and visuals.Update then
            visuals.Update(frame, "MSUF_A3_AURA_VISUAL", A3._ClassicBindFrameUnit(frame))
        end
    end
end

local function SetFrameAuraVisualState(frame, borderActive, br, bg, bb, ba, borderSecret, borderToken, overlayActive, orr, og, ob, oa, overlaySecret, overlayToken, stripeActive, visual)
    if not frame then return false end
    br, bg, bb, ba = br or 0.25, bg or 0.75, bb or 1, ba or 1
    orr, og, ob, oa = orr or br, og or bg, ob or bb, oa or ba
    borderSecret = borderSecret == true
    overlaySecret = overlaySecret == true
    local renderer = A3.ClassicVisuals
    local overlayRendererChanged = renderer and type(renderer.UpdateDispelOverlay) == "function"
        and renderer.UpdateDispelOverlay(frame, visual, overlayActive, orr, og, ob, oa) or false
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
    if not changed then return overlayRendererChanged end
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
    return true
end

local function FrameHasAuraVisualState(frame)
    return frame
        and (frame._msufA3DispelActive == true
            or frame._msufA3DispelOverlayActive == true
            or frame._msufA3DebuffStripeActive == true
            or frame._msufA3DispelColorSecret == true
            or frame._msufA3DispelOverlayColorSecret == true
            or frame._msufA3DispelToken ~= nil
            or frame._msufA3DispelOverlayToken ~= nil
            or frame._msufA3ClassicDispelSymbolsActive == true)
end

ClearFrameAuraVisualState = function(frame)
    if not frame then return false end
    local renderer = A3.ClassicVisuals
    local symbolChanged = renderer and type(renderer.HideDispelSymbols) == "function"
        and renderer.HideDispelSymbols(frame) or false
    if not FrameHasAuraVisualState(frame) then
        return symbolChanged
    end
    return SetFrameAuraVisualState(frame, false, nil, nil, nil, nil, false, nil, false, nil, nil, nil, nil, false, nil, false, nil)
        or symbolChanged
end

local function UpdateFrameAuraVisualState(frame, state, cfg, unit)
    local visual = cfg and cfg.visual
    if not (visual and visual.enabled == true) then
        return ClearFrameAuraVisualState(frame)
    end
    if cfg and cfg.visualDirect == true then
        local borderActive, br, bg, bb, ba, borderSecret, borderToken = false
        local overlayActive, orr, og, ob, oa, overlaySecret, overlayToken = false
        if visual.borderEnabled == true then
            borderActive, br, bg, bb, ba, borderSecret, borderToken = ResolveDirectDispelTriggerVisual(unit, visual, visual.borderTrigger)
        end
        if visual.overlayEnabled == true then
            if visual.overlayTrigger == visual.borderTrigger then
                overlayActive, orr, og, ob, oa, overlaySecret, overlayToken = borderActive, br, bg, bb, ba, borderSecret, borderToken
            else
                overlayActive, orr, og, ob, oa, overlaySecret, overlayToken = ResolveDirectDispelTriggerVisual(unit, visual, visual.overlayTrigger)
            end
        end
        return SetFrameAuraVisualState(frame, borderActive, br, bg, bb, ba, borderSecret, borderToken, overlayActive, orr, og, ob, oa, overlaySecret, overlayToken, false, visual)
    end
    local lane = state and state.lanes and state.lanes.debuff
    if not (lane and lane.config and lane.config.enabled == true) then
        return ClearFrameAuraVisualState(frame)
    end
    if lane._msufA3VisualCacheReady == true then
        local anyDebuff = lane._msufA3VisualAnyDebuff == true
        local stripeActive = anyDebuff and visual.stripeEnabled == true
        local symbolChanged = A3._UpdateClassicDispelSymbols(frame, lane, visual, unit)
        return SetFrameAuraVisualState(frame,
            anyDebuff and lane._msufA3VisualBorderActive == true,
            lane._msufA3VisualBorderR, lane._msufA3VisualBorderG,
            lane._msufA3VisualBorderB, lane._msufA3VisualBorderA,
            lane._msufA3VisualBorderSecret == true, lane._msufA3VisualBorderToken,
            anyDebuff and lane._msufA3VisualOverlayActive == true,
            lane._msufA3VisualOverlayR, lane._msufA3VisualOverlayG,
            lane._msufA3VisualOverlayB, lane._msufA3VisualOverlayA,
            lane._msufA3VisualOverlaySecret == true, lane._msufA3VisualOverlayToken,
            stripeActive, visual) or symbolChanged
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
    StoreLaneAuraVisualCache(lane, anyDebuff, borderActive, br, bg, bb, ba, borderSecret, borderToken, overlayActive, orr, og, ob, oa, overlaySecret, overlayToken)
    local stripeActive = anyDebuff and visual.stripeEnabled == true
    local symbolChanged = A3._UpdateClassicDispelSymbols(frame, lane, visual, unit)
    return SetFrameAuraVisualState(frame, borderActive, br, bg, bb, ba, borderSecret, borderToken, overlayActive, orr, og, ob, oa, overlaySecret, overlayToken, stripeActive, visual)
        or symbolChanged
end

local function EmptyAuraPayload(updateInfo)
    return updateInfo and not updateInfo.isFullUpdate
        and not updateInfo.addedAuras
        and not updateInfo.updatedAuraInstanceIDs
        and not updateInfo.removedAuraInstanceIDs
end

local function ConfigHasEnabledAuraLane(cfg)
    local lanes = cfg and cfg.lanes
    for _, lane in pairs(lanes or {}) do
        if lane and lane.enabled == true then return true end
    end
    return false
end

local function LaneAffectsFrameAuraVisual(lane)
    local cfg = lane and lane.config
    return cfg and cfg.visual and cfg.visual.enabled == true and cfg.visualDirect ~= true or false
end

--- Runtime update path for one lane. It chooses full scan vs delta merge,
--- renders only when the visible order changed, and reports whether frame-level
--- aura visuals need to be recomputed.
local function UpdateAuraLaneRuntime(lane, unit, updateInfo, full)
    if not (lane and lane.config and lane.config.enabled) then
        return false, false
    end
    local laneAffectsVisual = LaneAffectsFrameAuraVisual(lane)
    if full then
        local changed, rendered = FullScanLane(lane, unit, true)
        if changed then
            if rendered ~= true then
                RenderLane(lane, unit)
            end
            return true, laneAffectsVisual
        end
        return false, false
    end
    if lane._msufA3CappedFullScan == true then
        local changed, needsFullScan = UpdateCappedLaneFromDelta(lane, unit, updateInfo)
        if needsFullScan == true then
            local scanned, rendered = FullScanLane(lane, unit, true)
            if scanned then
                if rendered ~= true then
                    RenderLane(lane, unit)
                end
                return true, laneAffectsVisual
            end
            return false, false
        end
        return changed == true, changed == true and laneAffectsVisual or false
    end
    local needsRender, visualDirty = UpdateLaneFromDelta(lane, unit, updateInfo)
    if needsRender then
        RenderLane(lane, unit)
        return true, laneAffectsVisual
    end
    if visualDirty then
        return true, true
    end
    return false, false
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

--- AurasElement.Update lands here from Dispatch. Keep this function narrow:
--- normalize the unit, get/apply compiled config, update both lanes, and notify
--- frame-level aura visuals. Menu preview refreshes and DB writes belong outside.
local function UpdateAuras(frame, event, unit, updateInfo, forceFull)
    if not frame then return false end
    local frameUnit = A3._ClassicBindFrameUnit(frame)
    if unit and IsSecret(unit) == true then
        unit = frameUnit
    elseif unit == nil then
        unit = frameUnit
    elseif unit ~= frameUnit then
        return false
    end
    local preState = frame._msufA3State
    if EmptyAuraPayload(updateInfo) and forceFull ~= true
        and not (preState and preState.needFullUpdate == true) then
        return false
    end

    -- Invalidate this unit's token-membership sets: they must reflect the
    -- aura state this event describes before any lane queries them.
    A3._ClassicAuraTokenSerial[unit] = (A3._ClassicAuraTokenSerial[unit] or 0) + 1

    local state, cfg = CurrentFrameState(frame, unit)
    if not (cfg and cfg.enabled) then
        HideState(frame)
        return false
    end

    forceFull = forceFull == true or state.config ~= cfg
    local full = forceFull == true or state.needFullUpdate == true or not updateInfo or updateInfo.isFullUpdate == true
    state.needFullUpdate = false

    if cfg.visualDirect == true and not ConfigHasEnabledAuraLane(cfg) then
        return UpdateFrameAuraVisualState(frame, state, cfg, unit) == true
    end

    if full and UnitExists then
        local exists = UnitExists(unit)
        if not IsSecret(exists) and exists == false then
            for _, lane in pairs(state.lanes or {}) do ClearLane(lane) end
            ClearFrameAuraVisualState(frame)
            return false
        end
    end

    local changedCount = 0
    local auraVisualDirty = false

    local order = cfg.laneOrder or A3._ClassicBaseLaneOrder
    for i = 1, #order do
        local changed, visualDirty = UpdateAuraLaneRuntime(state.lanes[order[i]], unit, updateInfo, full)
        if changed then
            changedCount = changedCount + 1
            if visualDirty then auraVisualDirty = true end
        end
    end

    local visualChanged = false
    if cfg.visualDirect == true then
        visualChanged = UpdateFrameAuraVisualState(frame, state, cfg, unit) == true
    elseif auraVisualDirty == true then
        if cfg.visual ~= nil or FrameHasAuraVisualState(frame) then
            visualChanged = UpdateFrameAuraVisualState(frame, state, cfg, unit) == true
        end
    elseif full then
        local hasFrameVisual = FrameHasAuraVisualState(frame)
        if hasFrameVisual then
            visualChanged = UpdateFrameAuraVisualState(frame, state, cfg, unit) == true
        end
    end
    return changedCount > 0 or visualChanged == true
end

local function RenderCachedAuras(frame, combatOnly)
    if not frame then return false end
    local unit = A3._ClassicBindFrameUnit(frame)
    local state, cfg = CurrentFrameState(frame, unit)
    if not (state and cfg and cfg.enabled) then
        HideState(frame)
        return false
    end
    if state.needFullUpdate == true then
        return UpdateAuras(frame, "ForceUpdate", unit, nil, true)
    end

    local changed = false
    local order = cfg.laneOrder or A3._ClassicBaseLaneOrder
    for i = 1, #order do
        local lane = state.lanes[order[i]]
        local laneCfg = lane and lane.config
        if laneCfg and laneCfg.enabled and (combatOnly ~= true or laneCfg.needsCombatRefresh == true) then
            RenderLane(lane, unit)
            changed = true
        end
    end
    if changed and (cfg.visual ~= nil or FrameHasAuraVisualState(frame)) then
        UpdateFrameAuraVisualState(frame, state, cfg, unit)
    end
    return changed
end

local function ResetAurasForIdentity(frame)
    if not frame then return false end
    return UpdateAuras(frame, "ForceUpdate", A3._ClassicBindFrameUnit(frame), nil, true)
end

-- Deferred identity aura rebuild. A full rescan of a raid-buffed unit (40+
-- buffs) costs ~1.6ms and was the dominant cost in the target-change tick
-- (IdProbe: target.Auras 1.634ms vs everything else <0.3ms). oUF never runs a
-- synchronous scan on a swap -- the C-fired UNIT_AURA full-update does it on
-- its own frame. We mirror that: identity reasons enqueue the frame and one
-- C_Timer.After(0) flush rebuilds it next tick. Bars/name/portrait still
-- update instantly in the identity pass; only the (expensive) aura scan moves
-- off the tick. Frame-keyed set => natural coalescing under swap spam; the
-- unit is re-read at flush so the latest target always wins.
-- (State and helpers hang off A3 rather than file-scope locals: this file is
-- at Lua's 200-local-per-chunk ceiling.)
A3._identityAuraPending = A3._identityAuraPending or {}

function A3.FlushIdentityAuraRebuilds()
    if not A3._identityAuraQueued then
        A3._identityAuraFlushScheduled = false
        return
    end
    A3._identityAuraQueued = false
    A3._identityAuraFlushScheduled = false
    local pending = A3._identityAuraPending
    A3._identityAuraPending = {}
    -- Clear every pending flag and arm the full-scan fallback BEFORE running
    -- any rebuild. HandleUnitAura drops UNIT_AURA deltas while the flag is
    -- set, so a Lua error inside one frame's rebuild must not leave the
    -- remaining frames flagged -- that froze their auras until reload. With
    -- needFullUpdate armed, a rebuild that never ran is healed by the next
    -- UNIT_AURA escalating to a full scan.
    for frame in pairs(pending) do
        frame._msufA3IdentityRebuildPending = nil
        local state = frame._msufA3State
        if state then state.needFullUpdate = true end
    end
    for frame in pairs(pending) do
        if frame._msufActiveElements and frame._msufActiveElements.Auras == true then
            UpdateAuras(frame, "ForceUpdate", A3._ClassicBindFrameUnit(frame), nil, true)
        end
    end
end

function A3.QueueIdentityAuraRebuild(frame)
    if not frame then return false end
    if not (C_Timer and C_Timer.After) then
        return ResetAurasForIdentity(frame)
    end
    A3._identityAuraPending[frame] = true
    A3._identityAuraQueued = true
    frame._msufA3IdentityRebuildPending = true
    if not A3._identityAuraFlushScheduled then
        A3._identityAuraFlushScheduled = true
        C_Timer.After(0, A3.FlushIdentityAuraRebuilds)
    end
    return true
end

local function NeedsCombatAuraEvents(cfg)
    if not (cfg and cfg.enabled and cfg.lanes) then return false end
    for _, lane in pairs(cfg.lanes) do
        if lane and lane.enabled and lane.needsCombatRefresh == true then return true end
    end
    return false
end

function A3.EnableFrame(frame)
    local unit = A3._ClassicBindFrameUnit(frame)
    if not (unit and MANAGED_UNITS[unit]) then return false end
    local cfg = A3.ResolveUnitFrameConfig(unit, frame.MSUFSpec)
    if not (cfg and cfg.enabled) then
        HideState(frame)
        A3.SetUnitFrameOwner(unit, frame, false)
        return false
    end
    ApplyConfig(frame, cfg)
    A3._runtimeFrames = A3._runtimeFrames or {}
    A3._runtimeFrames[unit] = frame
    A3.SetUnitFrameOwner(unit, frame, true)
    UpdateAuras(frame, "ForceUpdate", unit, nil, true)
    return true
end

function A3.DisableFrame(frame)
    if not frame then return true end
    local unit = A3._ClassicBindFrameUnit(frame)
    HideState(frame)
    frame._msufA3GroupConfig = nil
    frame._msufA3GroupSource = nil
    frame._msufA3GroupUnit = nil
    frame._msufA3GroupGen = nil
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
    return UpdateAuras(frame, "ForceUpdate", A3._ClassicBindFrameUnit(frame), nil, true)
end

A3.ForceUpdateFrame = A3.RenderFrame
A3.RenderCachedFrame = RenderCachedAuras

function A3.HandleUnitAura(frame, event, unit, updateInfo)
    -- A coalesced target/focus swap owns the next full rebuild (see the
    -- aura-identity coalescing in MSUF_UF_Runtime.lua). Interim deltas
    -- describe a unit the lane no longer tracks and are superseded by that
    -- rebuild, so they are dropped instead of being merged into stale state.
    if frame and frame._msufA3IdentityRebuildPending == true then
        return false
    end
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

A3._ClassicAuraRuntimeCombatBlocked = function()
    return (InCombatLockdown and InCombatLockdown()) or _G.MSUF_InCombat == true
end

function A3._EnsureDeferredAuraRuntimeDriver()
    if A3._deferredAuraRuntimeFrame then return A3._deferredAuraRuntimeFrame end
    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(self, event)
        if event ~= "PLAYER_REGEN_ENABLED" or A3._ClassicAuraRuntimeCombatBlocked() then return end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        A3._FlushDeferredAuraRuntime()
    end)
    A3._deferredAuraRuntimeFrame = frame
    return frame
end

function A3._QueueDeferredAuraRuntime(scope, reason, visuals)
    scope = tostring(scope or "shared"):lower()
    A3._deferredAuraRuntime = true
    A3._deferredAuraRuntimeReason = reason or A3._deferredAuraRuntimeReason or "AURAS3_CLASSIC_DEFERRED"
    if visuals == true then A3._deferredAuraRuntimeVisuals = true end
    if scope == "" or scope == "shared" or scope == "global" or scope == "all" or scope == "*" then
        A3._deferredAuraRuntimeAll = true
        A3._deferredAuraRuntimeScopes = nil
    elseif A3._deferredAuraRuntimeAll ~= true then
        A3._deferredAuraRuntimeScopes = A3._deferredAuraRuntimeScopes or {}
        A3._deferredAuraRuntimeScopes[scope] = true
    end
    local frame = A3._EnsureDeferredAuraRuntimeDriver()
    if frame then frame:RegisterEvent("PLAYER_REGEN_ENABLED") end
    return false
end

function A3._AuraPreviewGroupKind(scope)
    local key = tostring(scope or ""):lower()
    if key == "party" or key == "gf_party" or key:match("^party%d+$") then return "party", true end
    if key == "raid" or key == "gf_raid" or key:match("^raid%d+$") then return "raid", true end
    if key == "mythicraid" or key == "gf_mythicraid" then return "mythicraid", true end
    if key == "" or key == "shared" or key == "global" or key == "all" or key == "*"
        or key == "group" or key == "groups" then
        return nil, true
    end
    return nil, false
end

function A3._NotifyAuraColdpathPreview(reason, scope)
    if A3._ClassicAuraRuntimeCombatBlocked() then
        return A3._QueueDeferredAuraRuntime(scope or "shared", reason or "AURAS3_CLASSIC_PREVIEW")
    end
    local didWork = false
    if type(_G.MSUF_UFPreview_RequestRefresh) == "function" then
        _G.MSUF_UFPreview_RequestRefresh(reason or "AURAS3_CLASSIC_PREVIEW")
        didWork = true
    end
    local gf = A3._GroupAPI()
    local kind, touchesGroup = A3._AuraPreviewGroupKind(scope)
    if touchesGroup and gf and type(gf.RefreshPreviewLayout) == "function" then
        gf.RefreshPreviewLayout(kind)
        didWork = true
    elseif touchesGroup and type(_G.MSUF_GF_RefreshPreviewLayout) == "function" then
        _G.MSUF_GF_RefreshPreviewLayout()
        didWork = true
    end
    return didWork
end

local function ApplyRuntimeUnit(runtimeUnit)
    if A3._ClassicAuraRuntimeCombatBlocked() then
        return A3._QueueDeferredAuraRuntime(runtimeUnit, "AURAS3_CLASSIC_RUNTIME_UNIT")
    end
    local frame = (A3._runtimeFrames and A3._runtimeFrames[runtimeUnit])
        or (UF.frames and UF.frames[runtimeUnit])
        or (_G.MSUF_UnitFrames and _G.MSUF_UnitFrames[runtimeUnit])
        or _G["MSUF_" .. runtimeUnit]
    if not frame then return false end
    if UF.ApplyElementToFrame then
        UF.ApplyElementToFrame(frame, "Auras", frame.MSUFSpec, nil)
    else
        A3.EnableFrame(frame)
    end
    return true
end

function A3._GroupAPI()
    local ns = MSUF or _G.MSUF_NS or _G.MSUF
    return ns and ns.GF or nil
end

function A3._ApplyGroupAuraFrame(frame, unit, kind)
    if not (frame and type(unit) == "string" and unit ~= "") then return false end
    if A3._ClassicAuraRuntimeCombatBlocked() then
        return A3._QueueDeferredAuraRuntime(unit, "AURAS3_CLASSIC_GROUP_FRAME")
    end
    frame._msufIsGroupFrame = true
    if kind then frame._msufGFKind = kind end
    local spec = frame.MSUFSpec
    local gf = A3._GroupAPI()
    if gf and type(gf.CompileSpec) == "function" and kind then
        spec = gf.CompileSpec(kind, frame, unit)
    end
    if UF.ApplyElementToFrame then
        UF.ApplyElementToFrame(frame, "Auras", spec, nil)
    else
        A3.RenderFrame(frame)
    end
    return true
end

function A3._RequestGroupKindNow(kind)
    local gf = A3._GroupAPI()
    if not gf then return false end
    if A3._ClassicAuraRuntimeCombatBlocked() then
        return A3._QueueDeferredAuraRuntime(kind or "group", "AURAS3_CLASSIC_GROUP_KIND")
    end

    local didWork = false
    if type(gf.ForEachFrame) == "function" then
        didWork = gf.ForEachFrame(function(frame, frameUnit, frameKind)
            if kind == nil or frameKind == kind then
                return A3._ApplyGroupAuraFrame(frame, frameUnit, frameKind)
            end
            return false
        end, true) == true
    end

    if not didWork and type(gf.RefreshVisuals) == "function" then
        gf.RefreshVisuals(kind, gf.DIRTY_AURAS)
        return true
    end
    return didWork
end

function A3._RequestGroupUnitNow(unit)
    local gf = A3._GroupAPI()
    if not (gf and type(unit) == "string" and unit ~= "") then return false end
    if A3._ClassicAuraRuntimeCombatBlocked() then
        return A3._QueueDeferredAuraRuntime(unit, "AURAS3_CLASSIC_GROUP_UNIT")
    end
    local frame = type(gf.FrameForUnit) == "function" and gf.FrameForUnit(unit) or nil
    return frame and A3._ApplyGroupAuraFrame(frame, unit, frame._msufGFKind) or false
end

local function RequestUnitNow(unit)
    unit = tostring(unit or "")
    if unit == "" or unit == "*" then
        local didWork = ApplyRuntimeUnit("player")
        didWork = ApplyRuntimeUnit("target") or didWork
        didWork = ApplyRuntimeUnit("focus") or didWork
        for i = 1, 5 do
            didWork = ApplyRuntimeUnit("boss" .. i) or didWork
        end
        didWork = A3._RequestGroupKindNow(nil) or didWork
        return didWork
    end
    if unit == "boss" then
        local didWork = false
        for i = 1, 5 do
            didWork = ApplyRuntimeUnit("boss" .. i) or didWork
        end
        return didWork
    end
    if unit == "group" or unit == "groups" then
        return A3._RequestGroupKindNow(nil)
    end
    if unit == "party" or unit == "gf_party" then
        return A3._RequestGroupKindNow("party")
    end
    if unit == "raid" or unit == "gf_raid" then
        local didWork = A3._RequestGroupKindNow("raid")
        return A3._RequestGroupKindNow("mythicraid") or didWork
    end
    if unit == "mythicraid" or unit == "gf_mythicraid" then
        return A3._RequestGroupKindNow("mythicraid")
    end
    if unit:match("^party%d+$") or unit:match("^raid%d+$") then
        return A3._RequestGroupUnitNow(unit)
    end
    unit = NormalizeRuntimeUnit(unit)
    return unit and ApplyRuntimeUnit(unit) or false
end

function A3.RequestUnit(unit, delay)
    if A3._ClassicAuraRuntimeCombatBlocked() then
        return A3._QueueDeferredAuraRuntime(unit, "AURAS3_CLASSIC_REQUEST_UNIT")
    end
    delay = tonumber(delay) or 0
    if delay > 0 and C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay, function() A3.RequestUnit(unit, 0) end)
        return true
    end
    return RequestUnitNow(unit)
end

function A3.RefreshAll()
    if A3._ClassicAuraRuntimeCombatBlocked() then
        return A3._QueueDeferredAuraRuntime("shared", "AURAS3_CLASSIC_REFRESH_ALL")
    end
    A3.BumpRuntimeConfig()
    A3._runtimeConfigCache = nil
    frameSpecConfigCache = setmetatable and setmetatable({}, { __mode = "k" }) or {}
    RequestUnitNow("*")
    return true
end

A3._requestApplyScopeKeys = A3._requestApplyScopeKeys or {
    player = true, target = true, focus = true, boss = true,
    party = true, raid = true, mythicraid = true,
    gf_party = true, gf_raid = true, gf_mythicraid = true,
    group = true, groups = true,
    shared = true, global = true, all = true, ["*"] = true,
}

A3._LooksLikeApplyScope = function(value)
    value = tostring(value or ""):lower()
    if value == "" then return false end
    if A3._requestApplyScopeKeys[value] then return true end
    return value:match("^boss%d+$") ~= nil
        or value:match("^party%d+$") ~= nil
        or value:match("^raid%d+$") ~= nil
end

--- The shared Auras3 core installs a no-runtime RequestScope stub before the
--- client backend loads.  Classic must replace it just like Mainline does;
--- otherwise Menu2 changes only invalidate configuration and never reach the
--- scan lanes until a reload or unrelated identity event.
function A3.RequestScope(scope, reason)
    scope = tostring(scope or "shared"):lower()
    if A3._ClassicAuraRuntimeCombatBlocked() then
        return A3._QueueDeferredAuraRuntime(scope, reason or "AURAS3_CLASSIC_SCOPE_APPLY")
    end
    if scope == "" or scope == "shared" or scope == "global" or scope == "all" or scope == "*" then
        return A3.RefreshAll()
    end
    local result = A3.RefreshUnit(scope)
    A3._NotifyAuraColdpathPreview(reason or "AURAS3_CLASSIC_SCOPE_APPLY", scope)
    return result
end

function A3.RequestApply(scopeOrReason, reason)
    if A3._LooksLikeApplyScope(scopeOrReason) then
        return A3.RequestScope(scopeOrReason, reason or "AURAS3_CLASSIC_REQUEST_APPLY")
    end
    return A3.RefreshAll()
end

function A3.RefreshUnit(unit)
    if A3._ClassicAuraRuntimeCombatBlocked() then
        return A3._QueueDeferredAuraRuntime(unit, "AURAS3_CLASSIC_REFRESH_UNIT")
    end
    A3.BumpRuntimeConfig()
    A3._runtimeConfigCache = nil
    frameSpecConfigCache = setmetatable and setmetatable({}, { __mode = "k" }) or {}
    return A3.RequestUnit(unit, 0)
end

function A3.ApplyFontsFromGlobal(scope, reason)
    if A3._ClassicAuraRuntimeCombatBlocked() then
        return A3._QueueDeferredAuraRuntime(scope or "shared", reason or "AURAS3_CLASSIC_FONT_VISUALS", true)
    end
    local frames = A3._runtimeFrames
    if not frames then return true end
    for _, frame in pairs(frames) do
        local state = frame and frame._msufA3State
        if state then
            for _, lane in pairs(state.lanes or {}) do
                for i = 1, lane.createdButtons or 0 do
                    local button = lane[i]
                    if button then ApplyButtonLayout(lane, button, i) end
                end
            end
        end
    end
    if scope ~= nil then return A3.RequestScope(scope, reason or "AURAS3_CLASSIC_FONT_VISUALS") end
    return true
end
MSUF.ExportPublic("MSUF_Auras3_ApplyFontsFromGlobal", A3.ApplyFontsFromGlobal)

function A3._FlushDeferredAuraRuntime()
    if A3._ClassicAuraRuntimeCombatBlocked() or A3._deferredAuraRuntime ~= true then return false end
    local all = A3._deferredAuraRuntimeAll == true
    local scopes = A3._deferredAuraRuntimeScopes
    local reason = A3._deferredAuraRuntimeReason or "AURAS3_CLASSIC_DEFERRED"
    A3._deferredAuraRuntime = nil
    A3._deferredAuraRuntimeAll = nil
    A3._deferredAuraRuntimeScopes = nil
    A3._deferredAuraRuntimeVisuals = nil
    A3._deferredAuraRuntimeReason = nil
    local previewScope = all and "shared" or nil
    if all or not scopes then
        A3.RefreshAll()
    else
        for scope in pairs(scopes) do
            previewScope = previewScope or scope
            A3.RefreshUnit(scope)
        end
    end
    A3._NotifyAuraColdpathPreview(reason, previewScope)
    return true
end

A3._HideLane = function(lane)
    if not lane then return false end
    if lane.frame and lane.createdButtons ~= nil then
        ClearLane(lane)
        lane.frame:Hide()
        return true
    end
    if lane.Hide then lane:Hide(); return true end
    return false
end

function A3._NormalizeClassicDispelPreviewScope(scope)
    scope = tostring(scope or "shared"):lower()
    if scope == "" or scope == "all" or scope == "global" then return "shared" end
    if scope == "gf_party" then return "party" end
    if scope == "gf_raid" then return "raid" end
    if scope == "gf_mythicraid" then return "mythicraid" end
    return scope
end

function A3._ClassicDispelPreviewApplies(frame, scope, includeGroup)
    if not frame then return false end
    local wanted = A3._NormalizeClassicDispelPreviewScope(scope)
    local spec = frame.MSUFSpec
    local groupKind = frame._msufGFKind or (spec and spec.groupKind)
    local isGroup = groupKind ~= nil or (spec and spec.scope == "group")
    if isGroup and includeGroup ~= true then return false end
    if wanted == "shared" then return true end
    if isGroup then
        if wanted == "raid" then return groupKind == "raid" or groupKind == "mythicraid" end
        return groupKind == wanted
    end
    return frame.MSUFUnitKey == wanted or frame.configKey == wanted
end

function A3._ForEachClassicDispelPreviewFrame(fn)
    if UF and type(UF.ForEachFrame) == "function" then UF.ForEachFrame(fn) end
    local gf = MSUF and MSUF.GF
    if not gf then return end
    if type(gf.ForEachFrame) == "function" then gf.ForEachFrame(fn, true) end
    local previews = gf._previewFrames
    if type(previews) ~= "table" then return end
    for _, frames in pairs(previews) do
        if type(frames) == "table" then
            for _, frame in pairs(frames) do
                if type(frame) == "table" then fn(frame) end
            end
        end
    end
end

function A3._ApplyClassicDispelOverlayPreview(frame)
    local renderer = A3.ClassicVisuals
    if not (renderer and type(renderer.UpdateDispelOverlayPreview) == "function") then return false end
    local active = _G.MSUF_DispelOverlayPreviewMode == true
        and A3._ClassicDispelPreviewApplies(frame, _G.MSUF_DispelOverlayPreviewScope, true)
    local visual = active and frame and frame.MSUFSpec and CompileFrameAuraVisual(frame.MSUFSpec) or nil
    active = active and visual and visual.overlayEnabled == true or false
    return renderer.UpdateDispelOverlayPreview(frame, visual, active)
end

function A3.RefreshDispelOverlayPreview()
    A3._ForEachClassicDispelPreviewFrame(A3._ApplyClassicDispelOverlayPreview)
    return true
end

function A3.SetDispelOverlayPreview(active, scope)
    active = active == true
    if active and A3._ClassicAuraRuntimeCombatBlocked() then active = false end
    ExportPublic("MSUF_DispelOverlayPreviewMode", active)
    ExportPublic("MSUF_DispelOverlayPreviewScope",
        active and A3._NormalizeClassicDispelPreviewScope(scope) or nil)
    A3.RefreshDispelOverlayPreview()
    return active
end

function A3._ApplyClassicDispelSymbolPreview(frame)
    local renderer = A3.ClassicVisuals
    if not (renderer and type(renderer.UpdateDispelSymbolPreview) == "function") then return false end
    local active = _G.MSUF_DispelSymbolPreviewMode == true
        and A3._ClassicDispelPreviewApplies(frame, _G.MSUF_DispelSymbolPreviewScope, false)
    local visual = active and frame and frame.MSUFSpec and CompileFrameAuraVisual(frame.MSUFSpec) or nil
    active = active and visual and visual.symbol and visual.symbol.enabled == true or false
    return renderer.UpdateDispelSymbolPreview(frame, visual, active)
end

function A3.RefreshDispelSymbolPreview()
    A3._ForEachClassicDispelPreviewFrame(A3._ApplyClassicDispelSymbolPreview)
    return true
end

function A3.SetDispelSymbolPreview(active, scope)
    active = active == true
    if active and A3._ClassicAuraRuntimeCombatBlocked() then active = false end
    ExportPublic("MSUF_DispelSymbolPreviewMode", active)
    ExportPublic("MSUF_DispelSymbolPreviewScope",
        active and A3._NormalizeClassicDispelPreviewScope(scope) or nil)
    A3.RefreshDispelSymbolPreview()
    return active
end

function A3.SetDispelSymbolPreviewMoveHandler(handler)
    A3.DispelSymbolPreviewMoveHandler = type(handler) == "function" and handler or nil
    return true
end

ExportPublic("MSUF_SetDispelOverlayPreview", A3.SetDispelOverlayPreview)
ExportPublic("MSUF_RefreshDispelOverlayPreview", A3.RefreshDispelOverlayPreview)
ExportPublic("MSUF_ApplyDispelOverlayPreviewToFrame", A3._ApplyClassicDispelOverlayPreview)
ExportPublic("MSUF_SetDispelSymbolPreview", A3.SetDispelSymbolPreview)
ExportPublic("MSUF_RefreshDispelSymbolPreview", A3.RefreshDispelSymbolPreview)
ExportPublic("MSUF_ApplyDispelSymbolPreviewToFrame", A3._ApplyClassicDispelSymbolPreview)
ExportPublic("MSUF_SetDispelSymbolPreviewMoveHandler", A3.SetDispelSymbolPreviewMoveHandler)

function A3._ClassicMenuPreviewSourceLane(scope, laneKind)

    local unit, cfg
    scope = tostring(scope or "shared"):lower()
    if scope == "party" or scope == "raid" then
        local gf = A3._GroupAPI()
        local frames = gf and gf.frameList
        for i = 1, type(frames) == "table" and #frames or 0 do
            local frame = frames[i]
            local kind = frame and frame._msufGFKind
            if (scope == "party" and kind == "party")
                or (scope == "raid" and (kind == "raid" or kind == "mythicraid")) then
                unit = frame.MSUFUnitKey
                cfg = ResolveGroupFrameConfig(frame, unit)
                if unit and cfg then break end
            end
        end
    else
        unit = scope == "boss" and "boss1" or (scope == "shared" and "player" or scope)
        cfg = A3.ResolveUnitFrameConfig(unit, nil)
    end
    return cfg and cfg.lanes and cfg.lanes[laneKind], unit
end

function A3.UpdateMenuAuraPreview(host, scope, laneKind, width, height)
    if not host or A3._ClassicAuraRuntimeCombatBlocked() then return false, "combat" end
    local source, unit = A3._ClassicMenuPreviewSourceLane(scope, laneKind)
    local preview = host._msufA3ClassicMenuPreviewFrame
    if not (source and source.enabled == true and unit) then
        if preview then HideState(preview) end
        return false, (scope == "party" or scope == "raid") and "no-group-frame" or "not-configured"
    end
    if not preview then
        preview = CreateFrame("Frame", nil, host)
        preview:SetAllPoints(host)
        host._msufA3ClassicMenuPreviewFrame = preview
        if host.HookScript then
            host:HookScript("OnHide", function() HideState(preview) end)
        end
    end
    local lane = {}
    for key, value in pairs(source) do lane[key] = value end
    lane.unit, lane.anchor, lane.x, lane.y, lane.layer = unit, "TOPLEFT", 10, -34, 2
    lane.strata, lane.alpha = "AUTO", 1
    local size = math_max(1, tonumber(lane.size) or 24)
    local spacing = math_max(0, tonumber(lane.spacing) or 0)
    local contentWidth = math_max(1, (tonumber(width) or 300) - 20)
    local contentHeight = math_max(1, (tonumber(height) or 120) - 42)
    local maxCols = math_max(1, math_floor((contentWidth + spacing) / math_max(1, size + spacing)))
    local maxRows = math_max(1, math_floor((contentHeight + spacing) / math_max(1, size + spacing)))
    lane.perRow = math_min(math_max(1, tonumber(lane.perRow) or 1), lane.verticalGrowth == true and maxRows or maxCols)
    lane.max = math_min(math_max(0, tonumber(lane.max) or 0), lane.perRow * (lane.verticalGrowth == true and maxCols or maxRows), 20)
    if lane.max <= 0 then HideState(preview); return false, "empty" end
    lane.cols = lane.verticalGrowth == true and math_ceil(lane.max / lane.perRow) or math_min(lane.max, lane.perRow)
    lane.rows = lane.verticalGrowth == true and math_min(lane.max, lane.perRow) or math_ceil(lane.max / lane.perRow)
    lane.width = math_max(1, lane.cols * (lane.buttonWidth or size) + math_max(lane.cols - 1, 0) * spacing)
    lane.height = math_max(1, lane.rows * (lane.buttonHeight or size) + math_max(lane.rows - 1, 0) * spacing)
    ApplyConfig(preview, { enabled = true, unit = unit, lanes = { [laneKind] = lane }, laneOrder = { laneKind } })
    UpdateAuras(preview, "ForceUpdate", unit, nil, true)
    preview:Show()
    return true, "live"
end

function A3.InvalidateUnitRuntimeConfig(unit)
    local runtimeUnit = NormalizeRuntimeUnit(unit)
    if runtimeUnit and A3._runtimeConfigCache then A3._runtimeConfigCache[runtimeUnit] = nil end
    frameSpecConfigCache = setmetatable and setmetatable({}, { __mode = "k" }) or {}
    return runtimeUnit
end

function A3.RenderUnitChangedFrame(frame, oldUnit, newUnit)
    if not frame then return false end
    newUnit = newUnit or A3._ClassicBindFrameUnit(frame)
    if oldUnit and A3._runtimeFrames and A3._runtimeFrames[oldUnit] == frame then
        A3._runtimeFrames[oldUnit] = nil
    end
    if newUnit then
        frame.unit = newUnit
        A3.InvalidateUnitRuntimeConfig(newUnit)
    end
    if A3._ClassicAuraRuntimeCombatBlocked() then
        return A3._QueueDeferredAuraRuntime(newUnit or "shared", "AURAS3_CLASSIC_UNIT_CHANGED")
    end
    return A3.QueueIdentityAuraRebuild(frame)
end

A3.OnFrameUnitChanged = A3.RenderUnitChangedFrame
A3.RefreshRuntime = A3.RefreshAll

local AurasElement = {
    events = { "UNIT_AURA" },
    unitlessEvents = EMPTY_EVENTS,
}

A3._ClassicWeaponAuraEvents = A3._ClassicWeaponAuraEvents or { "WEAPON_ENCHANT_CHANGED", "WEAPON_SLOT_CHANGED" }
A3._ClassicCombatWeaponAuraEvents = A3._ClassicCombatWeaponAuraEvents
    or { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "WEAPON_ENCHANT_CHANGED", "WEAPON_SLOT_CHANGED" }
A3._ClassicTargetIdentityAuraEvents = A3._ClassicTargetIdentityAuraEvents or { "PLAYER_TARGET_CHANGED" }
A3._ClassicFocusIdentityAuraEvents = A3._ClassicFocusIdentityAuraEvents or { "PLAYER_FOCUS_CHANGED" }
A3._ClassicBossIdentityAuraEvents = A3._ClassicBossIdentityAuraEvents or { "INSTANCE_ENCOUNTER_ENGAGE_UNIT" }
A3._ClassicTargetIdentityCombatAuraEvents = A3._ClassicTargetIdentityCombatAuraEvents
    or { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED" }
A3._ClassicFocusIdentityCombatAuraEvents = A3._ClassicFocusIdentityCombatAuraEvents
    or { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_FOCUS_CHANGED" }
A3._ClassicBossIdentityCombatAuraEvents = A3._ClassicBossIdentityCombatAuraEvents
    or { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "INSTANCE_ENCOUNTER_ENGAGE_UNIT" }
A3._ClassicIdentityAuraEventsByUnit = A3._ClassicIdentityAuraEventsByUnit or {
    target = A3._ClassicTargetIdentityAuraEvents,
    focus = A3._ClassicFocusIdentityAuraEvents,
    boss1 = A3._ClassicBossIdentityAuraEvents,
    boss2 = A3._ClassicBossIdentityAuraEvents,
    boss3 = A3._ClassicBossIdentityAuraEvents,
    boss4 = A3._ClassicBossIdentityAuraEvents,
    boss5 = A3._ClassicBossIdentityAuraEvents,
}
A3._ClassicIdentityCombatAuraEventsByUnit = A3._ClassicIdentityCombatAuraEventsByUnit or {
    target = A3._ClassicTargetIdentityCombatAuraEvents,
    focus = A3._ClassicFocusIdentityCombatAuraEvents,
    boss1 = A3._ClassicBossIdentityCombatAuraEvents,
    boss2 = A3._ClassicBossIdentityCombatAuraEvents,
    boss3 = A3._ClassicBossIdentityCombatAuraEvents,
    boss4 = A3._ClassicBossIdentityCombatAuraEvents,
    boss5 = A3._ClassicBossIdentityCombatAuraEvents,
}
A3._ClassicIdentityAuraEvent = A3._ClassicIdentityAuraEvent or {
    PLAYER_TARGET_CHANGED = true,
    PLAYER_FOCUS_CHANGED = true,
    INSTANCE_ENCOUNTER_ENGAGE_UNIT = true,
}

function AurasElement.IsEnabled(frame)
    local unit = A3._ClassicBindFrameUnit(frame)
    if not unit then return false end
    if IsGroupFrame(frame) then
        local cfg = ResolveGroupFrameConfig(frame, unit)
        return cfg and cfg.enabled == true or false
    end
    local cfg = A3.ResolveUnitFrameConfig(unit, frame.MSUFSpec)
    return cfg and cfg.enabled == true or false
end

function AurasElement.GetUnitlessEvents(frame)
    local unit = A3._ClassicBindFrameUnit(frame)
    local cfg = unit and FrameAuraConfig(frame, unit)
    local combat = NeedsCombatAuraEvents(cfg)
    local weapon = unit == "player" and cfg and cfg.lanes and cfg.lanes.buff
        and cfg.lanes.buff.weaponEnchants == true
    local identity = unit and A3._ClassicIdentityAuraEventsByUnit[unit]
    if identity then
        return combat and A3._ClassicIdentityCombatAuraEventsByUnit[unit] or identity
    end
    if combat and weapon then return A3._ClassicCombatWeaponAuraEvents end
    if weapon then return A3._ClassicWeaponAuraEvents end
    return combat and COMBAT_AURA_EVENTS or EMPTY_EVENTS
end

function AurasElement.Create(frame)
    if frame then EnsureState(frame) end
end

function AurasElement.Apply(frame)
    if not frame then return end
    local unit = A3._ClassicBindFrameUnit(frame)
    local isGroup = IsGroupFrame(frame)
    frame._msufA3GroupRuntime = isGroup == true or nil
    if isGroup then
        frame._msufA3GroupConfig = nil
    end
    local cfg = isGroup and ResolveGroupFrameConfig(frame, unit) or A3.ResolveUnitFrameConfig(unit, frame.MSUFSpec)
    if cfg and cfg.enabled then
        ApplyConfig(frame, cfg)
        if frame._msufActiveElements and frame._msufActiveElements.Auras == true then
            UpdateAuras(frame, "ForceUpdate", unit, nil, true)
        end
    else
        HideState(frame)
    end
end

function AurasElement.Enable(frame)
    local unit = A3._ClassicBindFrameUnit(frame)
    if IsGroupFrame(frame) then
        frame._msufA3GroupRuntime = true
        frame._msufA3GroupConfig = nil
        local cfg = ResolveGroupFrameConfig(frame, unit)
        if not (cfg and cfg.enabled == true) then
            HideState(frame)
            return false
        end
        local state = frame._msufA3State
        if not (state and state.config == cfg and state.unit == unit) then
            ApplyConfig(frame, cfg)
        end
        UpdateAuras(frame, "ForceUpdate", unit, nil, true)
        return true
    end
    return A3.EnableFrame(frame)
end

function AurasElement.Disable(frame)
    return A3.DisableFrame(frame)
end

function AurasElement.Update(frame, event, unit, updateInfo)
    if event == "UNIT_AURA" then
        return A3.HandleUnitAura(frame, event, unit, updateInfo)
    end
    if A3._ClassicIdentityAuraEvent[event] == true then
        -- Classic does not guarantee a UNIT_AURA payload when a stable token
        -- (target/focus/bossN) changes GUID. Blizzard's own TargetFrame performs
        -- a full UpdateAuras from PLAYER_TARGET_CHANGED for the same reason.
        -- Reuse the existing next-tick, frame-keyed queue so swap spam coalesces
        -- into one scan and the latest identity always wins.
        return A3.QueueIdentityAuraRebuild(frame)
    end
    if event == "WEAPON_ENCHANT_CHANGED" or event == "WEAPON_SLOT_CHANGED" then
        return UpdateAuras(frame, event, A3._ClassicBindFrameUnit(frame), nil, true)
    end
    if event == "MSUF_UNIT_IDENTITY_AURAS"
        or event == "MSUF_UNIT_IDENTITY_SOFT_AURAS" then
        -- Defer the expensive full rescan off the identity tick (see
        -- QueueIdentityAuraRebuild). Group identity keeps the synchronous path
        -- below via A3.RenderFrame so roster builds settle in one pass.
        return A3.QueueIdentityAuraRebuild(frame)
    end
    if event == "ForceUpdate"
        or event == "MSUF_FORCE_UPDATE"
        or event == "MSUF_UNIT_IDENTITY"
        or event == "MSUF_UNIT_IDENTITY_SOFT"
        or event == "MSUF_GF_UNIT_IDENTITY" then
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
A3.nativeAuraBackend = false
A3.classicAuraBackend = true
MSUF.AuraBackendEnabled = true

MSUF.ExportPublic("MSUF_A3_RequestUnit", A3.RequestUnit)
MSUF.ExportPublic("MSUF_Auras3_RefreshUnit", A3.RefreshUnit)
MSUF.ExportPublic("MSUF_Auras3_RefreshAll", A3.RefreshAll)
