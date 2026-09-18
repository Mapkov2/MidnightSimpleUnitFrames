--- Game/Classic/Auras/MSUF_Auras3_Compile.lua
--- Classic aura config compiler: lane specs, filters, blacklist hashes,
--- dispel visuals and sort comparators. It turns DB/model choices into the
--- lane config the runtime consumes, so UNIT_AURA never walks SavedVariables.
---
--- Loaded immediately before MSUF_Auras3_UnitFrames.lua, which imports these
--- helpers through A3._ClassicCompile.
if not (select(2, ...) and select(2, ...).Client and select(2, ...).Client.IsClassic) then return end
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local ExportPublic = MSUF.ExportPublic

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end

if not (MSUF.UF and MSUF.UF.RegisterElement) then return end
if A3.__unitFrameBackendLoaded or A3._ClassicCompile then return end

local type, tostring, tonumber, pairs, select = type, tostring, tonumber, pairs, select
local math_floor, math_ceil, math_min, math_max = math.floor, math.ceil, math.min, math.max
local wipe = table.wipe or wipe
local C_CurveUtil = _G.C_CurveUtil
local CreateColor = _G.CreateColor
local Enum = _G.Enum
local IsSecret = _G.issecretvalue or function() return false end
-- Debuffs this player can dispel, in the filter this client honours
-- (Game/Shared/Initialize.lua; Classic Era needs HARMFUL|RAID).
local DISPELLABLE_DEBUFF_FILTER = MSUF.Client.DispellableDebuffFilter or "HARMFUL|RAID_PLAYER_DISPELLABLE"

local BOSS_UNITS = {
    boss1 = true, boss2 = true, boss3 = true, boss4 = true, boss5 = true,
}
local MANAGED_UNITS = {
    player = true, target = true, focus = true,
    boss1 = true, boss2 = true, boss3 = true, boss4 = true, boss5 = true,
    arena1 = true, arena2 = true, arena3 = true,
}

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

local UNIT_FLAG = {
    player = "showPlayer",
    target = "showTarget",
    focus = "showFocus",
    boss1 = "showBoss",
    boss2 = "showBoss",
    boss3 = "showBoss",
    boss4 = "showBoss",
    boss5 = "showBoss",
    arena1 = "showArena",
    arena2 = "showArena",
    arena3 = "showArena",
}
-- TBC and Mists field five arena opponents (Game/Shared/Initialize.lua).
for i = 4, tonumber(_G.MSUF_MAX_ARENA_FRAMES) or 3 do
    MANAGED_UNITS["arena" .. i] = true
    UNIT_FLAG["arena" .. i] = "showArena"
end

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
    sortOrder = 1,
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
        spacingKey = "buffSpacing",
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
        spacingKey = "debuffSpacing",
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
        nonPlayerKey = "debuffNonPlayer",
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
    if value == "INSTANCE_ID" then return 0 end
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
        return DISPELLABLE_DEBUFF_FILTER
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
    if unit == "arena" then return "arena1" end
    return MANAGED_UNITS[unit] and unit or nil
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
    if BOSS_UNITS[unit] then return "boss" end
    if unit == "arena1" or unit == "arena2" or unit == "arena3" then return "arena" end
    return unit
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
    if auras.showArena == nil then auras.showArena = true end
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
    -- Defaults/Core materialize every Unit lane into its explicit owner once.
    -- Runtime must never resume inheriting mutable layout/style/filter values
    -- from auras3.shared after that migration.
    local layout = pu and type(pu.layout) == "table" and pu.layout or {}
    local sharedLayout = pu and type(pu.layoutShared) == "table" and pu.layoutShared or {}
    local blacklist = nil
    if pu and pu.overrideBlacklist == true and type(pu.blacklist) == "table" then
        blacklist = pu.blacklist
    else
        blacklist = shared and shared.blacklist
    end
    local filters = pu and type(pu.filters) == "table" and pu.filters or {}
    return layout, sharedLayout, blacklist, filters
end

A3._ClassicResolveHidePermanent = function(blacklist, filtersRoot, kind)
    kind = tostring(kind or "buff"):lower()
    if kind == "buffs" then kind = "buff" end
    if kind == "debuffs" then kind = "debuff" end
    local spec = LANE_SPECS[kind]
    if not spec then return false end

    local rootFilters = type(filtersRoot) == "table" and filtersRoot or nil
    local storedLaneFilters = rootFilters and type(rootFilters[spec.dbKey]) == "table"
        and rootFilters[spec.dbKey] or nil
    local explicitLaneBlacklist = type(blacklist) == "table"
        and type(blacklist[spec.dbKey]) == "table" and blacklist[spec.dbKey] or nil

    if explicitLaneBlacklist and explicitLaneBlacklist.hidePermanent ~= nil then
        -- The current menu writes the blacklist lane. Keep an explicit false
        -- authoritative so a unit can disable an inherited legacy rule.
        return explicitLaneBlacklist.hidePermanent == true
    end
    if type(explicitLaneBlacklist or blacklist) == "table"
        and (explicitLaneBlacklist or blacklist).hidePermanent == true then
        return true
    end
    -- Portable/legacy profiles can carry the rule in the effective filter
    -- lane. The old root field applied to Buffs only and remains the final
    -- compatibility fallback.
    if storedLaneFilters and storedLaneFilters.hidePermanent == true then return true end
    return kind == "buff" and rootFilters and rootFilters.hidePermanent == true or false
end

A3._ClassicReadBlacklistHidePermanent = function(scope, kind)
    scope = tostring(scope or "player")
    if BOSS_UNITS[scope] then scope = "boss" end
    -- The shared menu model collapses every Arena scope to arena1 for reads.
    -- Arena rendering is owned separately, but the Classic menu adapter must
    -- still preserve that current SavedVariables ownership contract.
    local runtimeUnit = (scope == "arena" or scope:match("^arena%d+$")) and "arena1"
        or NormalizeRuntimeUnit(scope)
    if not runtimeUnit then return false end

    local auras
    if type(A3.EnsureDB) == "function" then auras = A3.EnsureDB() end
    if type(auras) ~= "table" then auras = EnsureRootDB() end
    local _, _, blacklist, filters = EffectiveTables(auras, runtimeUnit)
    return A3._ClassicResolveHidePermanent(blacklist, filters, kind)
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
    if not root then return nil end
    local filters = root[dbKey]
    return type(filters) == "table" and filters.enabled ~= false and filters or nil
end

local SortAuras, SortAurasID, SortComparator
local frameSpecConfigCache = setmetatable and setmetatable({}, { __mode = "k" }) or {}
local function ResetFrameSpecConfigCache()
    frameSpecConfigCache = setmetatable and setmetatable({}, { __mode = "k" }) or {}
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
    --- Retail switches a dispel type's symbol art to the Tintable variant when
    --- the user overrode that type's colour, so the native colour map can
    --- repaint it. Classic has no native colouring, so the renderer repaints it
    --- directly. Collect the overridden types here, where the dispel block is
    --- already read, and stamp a signature: the renderer must never rebuild one
    --- per update.
    local symbolTints, symbolTintKey
    local dispelSpec = symbolEnabled and type(spec.dispel) == "table" and spec.dispel or nil
    if dispelSpec then
        for i = 1, #DISPEL_POINTS do
            local point = DISPEL_POINTS[i]
            local base = "type" .. point[2]
            if dispelSpec[base .. "R"] ~= nil or dispelSpec[base .. "G"] ~= nil
                or dispelSpec[base .. "B"] ~= nil then
                local tr = DispelColorValue(dispelSpec, base .. "R", point[3])
                local tg = DispelColorValue(dispelSpec, base .. "G", point[4])
                local tb = DispelColorValue(dispelSpec, base .. "B", point[5])
                symbolTints = symbolTints or {}
                symbolTints[point[2]] = { tr, tg, tb }
                symbolTintKey = (symbolTintKey and (symbolTintKey .. "|") or "")
                    .. point[2] .. tostring(tr) .. "," .. tostring(tg) .. "," .. tostring(tb)
            end
        end
    end

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
            tint = symbolTints,
            tintKey = symbolTintKey,
        } or nil,
    }
end

local function CompileLane(runtimeUnit, shared, layout, sharedLayout, blacklist, filtersRoot, kind, forceScan, visual, renderAllowed)
    local spec = LANE_SPECS[kind]
    local sizeDefault = tonumber(ReadRaw(layout, nil, spec.sizeKey))
        or DEFAULT_SHARED.iconSize
    local size = ClampNumber(sizeDefault, DEFAULT_SHARED.iconSize, 1, 128)
    local spacing = ReadNumber(layout, nil, spec.spacingKey, DEFAULT_SHARED.spacing, 0, 64)
    local perRow = ReadNumber(sharedLayout, nil, spec.perRowKey, DEFAULT_SHARED.perRow, 1, 40)
    local maxCount = ReadNumber(sharedLayout, nil, spec.maxKey, DEFAULT_SHARED[spec.maxKey] or 12, 0, 80)
    local show = ReadBool(sharedLayout, nil, spec.showKey, true)
    local growth = ReadRaw(sharedLayout, nil, spec.growthKey) or DEFAULT_SHARED.growth
    local rowWrap = ReadRaw(sharedLayout, nil, spec.wrapKey) or DEFAULT_SHARED.rowWrap
    local growthX, growthY, xSign, ySign, verticalGrowth = GrowthParts(growth, rowWrap)
    local lanePadding = Round(ClampNumber(ReadRaw(layout, nil, kind .. "StylePadding"), 0, 0, 16))
    local x = ReadNumber(layout, nil, spec.xKey, DEFAULT_SHARED[spec.xKey] or 0, -4096, 4096)
    local y = ReadNumber(layout, nil, spec.yKey, DEFAULT_SHARED[spec.yKey] or 0, -4096, 4096)
    local anchor = ReadAnchor(layout, nil, spec.anchorKey, spec.defaultAnchor)
    local layer = ReadNumber(layout, nil, spec.layerKey, spec.defaultLayer, 1, 15)
    local stackAnchor = ReadAnchor(sharedLayout, nil, spec.stackAnchorKey, DEFAULT_SHARED.stackCountAnchor or "TOPRIGHT")
    local filters = FilterTable(filtersRoot, spec.dbKey)
    local nonPlayerFilter = kind == "debuff" and filters and filters.nonPlayer == true or false
    local explicitLaneBlacklist = type(blacklist) == "table"
        and type(blacklist[spec.dbKey]) == "table" and blacklist[spec.dbKey] or nil
    local laneBlacklist = explicitLaneBlacklist or blacklist
    -- Classic unit lanes filter by Only mine and Hide permanent, plus the
    -- blacklist, non-player and sated rules. The Retail-only filters (important,
    -- raid, stealable, boss, raid-in-combat, max duration) have no Classic
    -- setting, so the lane config exports them as fixed off values.
    local onlyMine = filters and filters.onlyMine == true
    local hidePermanent = A3._ClassicResolveHidePermanent(blacklist, filtersRoot, kind)
    local showSated = kind ~= "buff" or ReadBool(nil, shared, "showSated", true)
    local satedThreshold = kind == "buff" and ReadNumber(nil, shared, "satedShowAtSeconds", 0, 0, 3600) or 0
    local satedFilter = kind == "buff" and (showSated ~= true or satedThreshold > 0)
    local ownHighlight = kind == "buff"
        and ReadBool(nil, shared, "highlightOwnBuffs", false)
        or (kind == "debuff" and ReadBool(nil, shared, "highlightOwnDebuffs", false))
    local filterPlan = A3.ClassicFeatures and A3.ClassicFeatures.CompileSettingsFilter
        and A3.ClassicFeatures.CompileSettingsFilter(filters, kind == "buff") or nil
    local visualNeedsPlayer = kind == "debuff" and visual and visual.needsPlayerFlag == true
    local hasInclusive = (filterPlan and filterPlan.hasRequirements == true) or onlyMine == true
    local black = CompileBlacklist(laneBlacklist)
    local hasFilterWork = black ~= nil or hasInclusive or hidePermanent or nonPlayerFilter or satedFilter
    local renderEnabled = renderAllowed ~= false and show and maxCount > 0
    local visualDirect = kind == "debuff"
        and visual
        and visual.directVisualEligible == true
        and hasFilterWork ~= true
    local enabled = renderEnabled or (forceScan == true and kind == "debuff" and visualDirect ~= true)
    -- Capped scan: every rule ShouldShowAura applies to this lane (blacklist,
    -- auto-exclusion, Hide permanent, non-player, sated) is decided per aura,
    -- so the scan may stop once cfg.max auras are visible. Lanes with an
    -- inclusive filter (Only mine, or a requirement from the feature compiler)
    -- keep the full walk. That carve-out comes from Retail, where inclusive
    -- filters OR-ed extra filter tokens into the lane; Classic keeps it so the
    -- Only mine scan path is unchanged.
    local cappedFilterScan = hasFilterWork == true and hasInclusive ~= true
    local step = size + spacing
    local roundedMax = Round(maxCount)
    local roundedPerRow = Round(perRow)
    local cols, rows = GridShape(roundedMax, roundedPerRow, verticalGrowth)
    local sortOrder = A3._ClassicSortMode(ReadRaw(sharedLayout, nil, kind .. "SortMethod"), DEFAULT_SHARED.sortOrder)
    local sortReverse = ReadBool(sharedLayout, nil, kind .. "SortReverse", false)
    local showCooldownSwipe = ReadBool(sharedLayout, nil, spec.showSwipeKey, DEFAULT_SHARED.showCooldownSwipe ~= false)
    local showCooldownText = ReadBool(sharedLayout, nil, spec.showTextKey, DEFAULT_SHARED.showCooldownText ~= false)
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
    local nativePlayerFilter = filterPlan and filterPlan.nativePlayerFilter == true or false
    local debuffTypeBorderMode = kind == "debuff" and A3.NormalizeClassicDebuffTypeBorderMode(
        ReadRaw(sharedLayout, nil, "debuffTypeBorderMode"),
        ReadBool(sharedLayout, nil, "useDebuffTypeBorders", false), false) or "OFF"
    local showDispelTypeBorder = kind == "debuff" and renderEnabled == true and debuffTypeBorderMode ~= "OFF"
    local dispelVisual = (kind == "debuff" and (visual or (showDispelTypeBorder and CompileDispelVisual(nil)))) or nil
    local needsPlayerFlag = (filterPlan and filterPlan.needsPlayerFlag == true)
        or onlyMine == true or ownHighlight == true or (visualNeedsPlayer == true and visualDirect ~= true)
        or sortOrder == 1 or sortOrder == 2 or sortOrder == 3 or sortOrder == 5
    local sortComparator = sortOrder == 0 and (needsPlayerFlag and SortAuras or SortAurasID) or SortComparator(Round(sortOrder))
    local naturalOrder = sortOrder == 0 and needsPlayerFlag ~= true
    local visibleOnlyScan = renderEnabled == true
        and naturalOrder == true
        and not (kind == "debuff" and visual and visual.enabled == true and visualDirect ~= true)

    return {
        kind = kind,
        unit = runtimeUnit,
        enabled = enabled == true,
        renderEnabled = renderEnabled == true,
        harmful = spec.harmful == true,
        filter = baseFilter,
        playerFilter = nativePlayerFilter and baseFilter or (baseFilter .. "|PLAYER"),
        importantFilter = baseFilter .. "|IMPORTANT",
        raidFilter = baseFilter .. "|RAID",
        raidInCombatFilter = baseFilter .. "|RAID_IN_COMBAT",
        stealableFilter = "HELPFUL|STEALABLE",
        dispellableFilter = DISPELLABLE_DEBUFF_FILTER,
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
        padding = lanePadding,
        width = math_max(1, cols * size + math_max(cols - 1, 0) * spacing + 2 * lanePadding),
        height = math_max(1, rows * size + math_max(rows - 1, 0) * spacing + 2 * lanePadding),
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
        -- A refresh can move an aura only in the time-keyed modes (2 duration,
        -- 3 expiration, 4 expiration only). Every other key is fixed for the
        -- aura's lifetime; an ownership flip is caught by the update path.
        reorderOnUpdate = sortOrder == 2 or sortOrder == 3 or sortOrder == 4,
        ownHighlight = ownHighlight == true,
        ownR = ownR,
        ownG = ownG,
        ownB = ownB,
        clickThrough = ReadBool(nil, shared, "clickThroughAuras", false),
        showTooltip = ReadBool(sharedLayout, nil, kind .. "ShowTooltip", DEFAULT_SHARED.showTooltip ~= false),
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
        cooldownSize = ReadNumber(layout, nil, spec.cooldownSizeKey, DEFAULT_SHARED.cooldownTextSize, 6, 40),
        cooldownDecimalSeconds = ReadNumber(sharedLayout, nil, kind .. "CooldownDecimalSeconds",
            DEFAULT_SHARED.cooldownDecimalSeconds or 3, 0, 30),
        cooldownAnchor = ReadAnchor(sharedLayout, nil, kind .. "CooldownTextAnchor", DEFAULT_SHARED.cooldownTextAnchor or "CENTER"),
        cooldownX = ReadNumber(layout, nil, spec.cooldownXKey, DEFAULT_SHARED.cooldownTextOffsetX, -2000, 2000),
        cooldownY = ReadNumber(layout, nil, spec.cooldownYKey, DEFAULT_SHARED.cooldownTextOffsetY, -2000, 2000),
        showStacks = ReadBool(sharedLayout, nil, spec.showStackKey, DEFAULT_SHARED.showStackCount ~= false),
        stackAnchor = stackAnchor,
        stackSize = ReadNumber(layout, nil, spec.stackSizeKey, DEFAULT_SHARED.stackTextSize, 6, 40),
        stackX = ReadNumber(layout, nil, spec.stackXKey, DEFAULT_SHARED.stackTextOffsetX, -2000, 2000),
        stackY = ReadNumber(layout, nil, spec.stackYKey, DEFAULT_SHARED.stackTextOffsetY, -2000, 2000),
        stackR = stackR,
        stackG = stackG,
        stackB = stackB,
        blacklist = black,
        filterPlan = filterPlan,
        filterRequirements = filterPlan and filterPlan.requirements or nil,
        nativePlayerFilter = nativePlayerFilter,
        hasFilterWork = hasFilterWork,
        visualDirect = visualDirect == true,
        exclusiveImportant = false,
        onlyImportant = false,
        onlyMine = onlyMine == true,
        raid = false,
        includeStealable = false,
        boss = false,
        hidePermanent = hidePermanent == true,
        nonPlayerFilter = nonPlayerFilter,
        maxDuration = 0,
        showSated = showSated == true,
        satedThreshold = satedThreshold,
        satedFilter = satedFilter == true,
        raidInCombat = false,
        hasInclusive = hasInclusive == true,
        needsPlayerFlag = needsPlayerFlag,
        needsCombatRefresh = filterPlan and filterPlan.needsCombatRefresh == true or false,
        visual = kind == "debuff" and visual or nil,
        showDispelTypeBorder = showDispelTypeBorder == true,
        showDispelTypeSymbol = showDispelTypeBorder == true and debuffTypeBorderMode == "SYMBOL",
        showStealableMarker = kind == "buff" and renderEnabled == true
            and ReadBool(sharedLayout, nil, "buffShowStealable", false),
        stealableStyle = kind == "buff" and A3.NormalizeClassicStealableStyle(
            ReadRaw(sharedLayout, nil, "buffStealableStyle")) or nil,
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
    if kind == "buff" or kind == "debuff" then
        -- Generic Classic group lanes support only All and Player. Do not
        -- rewrite the stored token: Retail can consume it again after import.
        -- The External lane's auto-blacklist is an internal ownership rule,
        -- not a user-selected Retail filter, so preserve that one negation.
        local playerOnly = false
        local excludeExternalDefensives = false
        for token in tostring(rawFilter):gmatch("[^|]+") do
            token = token:upper():gsub("%s+", "")
            if token == "PLAYER" then
                playerOnly = true
            elseif token == "!EXTERNAL_DEFENSIVE" or token == "NOT_EXTERNAL_DEFENSIVE" then
                excludeExternalDefensives = true
            end
        end
        rawFilter = playerOnly and (spec.filter .. "|PLAYER") or spec.filter
        if kind == "buff" and excludeExternalDefensives then
            rawFilter = rawFilter .. "|!EXTERNAL_DEFENSIVE"
        end
    end
    local filterPlan = A3.ClassicFeatures and A3.ClassicFeatures.CompileRawFilter
        and A3.ClassicFeatures.CompileRawFilter(rawFilter, spec.harmful ~= true) or nil
    local filter = filterPlan and filterPlan.scanFilter or spec.filter
    local nativePlayerFilter = filterPlan and filterPlan.nativePlayerFilter == true or false
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
    local nonPlayerFilter = spec.nonPlayerKey and source[spec.nonPlayerKey] == true or false
    local hasFilterWork = black ~= nil or type(includeSpellIDs) == "table" or hidePermanent
        or nonPlayerFilter
        or (filterPlan and filterPlan.hasRequirements == true)
    local visualDirect = kind == "debuff"
        and visual
        and visual.directVisualEligible == true
        and hasFilterWork ~= true
    local enabled = renderEnabled or (forceScan == true and kind == "debuff" and visualDirect ~= true)
    local cappedFilterScan = (black ~= nil or hidePermanent or nonPlayerFilter)
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
    local lanePadding = Round(ClampNumber(source.stylePadding, 0, 0, 16))
    local roundedMax = Round(maxCount)
    local roundedPerRow = Round(perRow)
    local cols, rows = GridShape(roundedMax, roundedPerRow, verticalGrowth)
    local sortOrder = A3._ClassicSortMode(source[kind .. "SortMethod"] or source.sortMethod,
        source.sortByDuration == true and 2 or 1)
    local sortReverse = source[kind .. "SortReverse"] == true
        or (source[kind .. "SortReverse"] == nil and source.sortReverse == true)
    local debuffTypeBorderMode = kind == "debuff" and A3.NormalizeClassicDebuffTypeBorderMode(
        source.debuffDispelBorderMode or source.debuffTypeBorderMode or source.dispelBorderMode,
        source.debuffShowDispelBorder == true or source.showDispelBorder == true,
        source.debuffShowDispelSymbol == true or source.showDispelSymbol == true) or "OFF"
    local showDispelTypeBorder = kind == "debuff" and renderEnabled == true and debuffTypeBorderMode ~= "OFF"
    local dispelVisual = (kind == "debuff" and (visual or (showDispelTypeBorder and CompileDispelVisual(nil)))) or nil
    local needsPlayerFlag = source.preferPlayer == true
        or (filterPlan and filterPlan.needsPlayerFlag == true)
        or (kind == "debuff" and visual and visual.needsPlayerFlag == true and visualDirect ~= true)
        or sortOrder == 1 or sortOrder == 2 or sortOrder == 3 or sortOrder == 5

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
        playerFilter = nativePlayerFilter and filter or (filter .. "|PLAYER"),
        importantFilter = filter .. "|IMPORTANT",
        raidFilter = filter .. "|RAID",
        raidInCombatFilter = filter .. "|RAID_IN_COMBAT",
        stealableFilter = "HELPFUL|STEALABLE",
        dispellableFilter = DISPELLABLE_DEBUFF_FILTER,
        bossFilter = "HARMFUL|BOSS",
        max = renderEnabled and roundedMax or 0,
        size = size,
        spacing = spacing,
        step = step,
        perRow = roundedPerRow,
        cols = cols,
        rows = rows,
        padding = lanePadding,
        width = math_max(1, cols * size + math_max(cols - 1, 0) * spacing + 2 * lanePadding),
        height = math_max(1, rows * size + math_max(rows - 1, 0) * spacing + 2 * lanePadding),
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
        -- Time-keyed modes only, as in CompileLane.
        reorderOnUpdate = sortOrder == 2 or sortOrder == 3 or sortOrder == 4,
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
        cooldownDecimalSeconds = ClampNumber(source[kind .. "CooldownDecimalSeconds"] or source.cooldownDecimalSeconds, 3, 0, 30),
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
        nativePlayerFilter = nativePlayerFilter,
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
        nonPlayerFilter = nonPlayerFilter,
        maxDuration = 0,
        needsPlayerFlag = needsPlayerFlag == true,
        needsCombatRefresh = filterPlan and filterPlan.needsCombatRefresh == true or false,
        visual = kind == "debuff" and visual or nil,
        showDispelTypeBorder = showDispelTypeBorder == true,
        showDispelTypeSymbol = showDispelTypeBorder == true and debuffTypeBorderMode == "SYMBOL",
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
    local layout, sharedLayout, blacklist, filtersRoot = EffectiveTables(auras, unit)
    if auraIconsEnabled or needDebuffScan then
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
        local lanePadding = ReadRaw(layout, nil, "buffStylePadding")
        local extraLanes, extraOrder, extraSource = A3.ClassicFeatures.CompileUnitLanes(
            auras, unit, frameSpec, lanePadding)
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
        padding = lane.padding,
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

A3._ClassicCompile = {
    MANAGED_UNITS = MANAGED_UNITS,
    DEFAULT_SHARED = DEFAULT_SHARED,
    WipeTable = WipeTable,
    FillAuraSlots = FillAuraSlots,
    PlainNumber = PlainNumber,
    PlainString = PlainString,
    DirectVisualFilterForTrigger = DirectVisualFilterForTrigger,
    ColorObjectRGBA = ColorObjectRGBA,
    HasSecretColor = HasSecretColor,
    NormalizeRuntimeUnit = NormalizeRuntimeUnit,
    IsUnitToken = IsUnitToken,
    IsGroupFrame = IsGroupFrame,
    SortAuras = SortAuras,
    SortComparator = SortComparator,
    CompileFrameAuraVisual = CompileFrameAuraVisual,
    ResolveGroupFrameConfig = ResolveGroupFrameConfig,
    FrameAuraConfig = FrameAuraConfig,
    ResetFrameSpecConfigCache = ResetFrameSpecConfigCache,
}
