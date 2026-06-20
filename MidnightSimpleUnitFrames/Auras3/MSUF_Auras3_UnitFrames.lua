--- Auras3/MSUF_Auras3_UnitFrames.lua
--- WoW 12.1 native AuraContainer/AuraButton runtime.
---
--- MSUF 6.0 is 12.1-only for aura display work. This file intentionally does
--- not inspect or transform aura payload data itself. Blizzard's native
--- AuraContainer owns tracking, filtering, and assignment; MSUF only builds the
--- visual containers, AuraButton pools, layout, and refresh surface.
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

local type, tostring, tonumber, pairs, next = type, tostring, tonumber, pairs, next
local table_concat = table.concat
local math_floor, math_min, math_max = math.floor, math.min, math.max
local CreateFrame = _G.CreateFrame
local STANDARD_TEXT_FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local EMPTY_EVENTS = {}

local MANAGED_UNITS = {
    player = true, target = true, focus = true,
    boss1 = true, boss2 = true, boss3 = true, boss4 = true, boss5 = true,
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
    showCooldownText = true,
    showStackCount = true,
    iconSize = 26,
    spacing = 2,
    perRow = 12,
    maxBuffs = 12,
    maxDebuffs = 12,
    growth = "RIGHT",
    rowWrap = "DOWN",
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
    stackTextSize = 14,
    stackTextOffsetX = -1,
    stackTextOffsetY = 1,
    cooldownTextSize = 14,
    cooldownTextOffsetX = 0,
    cooldownTextOffsetY = 0,
}

local LANE_SPECS = {
    buff = {
        rootKey = "Buffs",
        filter = "HELPFUL",
        filterKey = "buffs",
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
        showTextKey = "buffShowCooldownText",
        showStackKey = "buffShowStackCount",
        stackAnchorKey = "buffStackCountAnchor",
        stackSizeKey = "buffStackTextSize",
        stackXKey = "buffStackTextOffsetX",
        stackYKey = "buffStackTextOffsetY",
        cooldownSizeKey = "buffCooldownTextSize",
        cooldownXKey = "buffCooldownTextOffsetX",
        cooldownYKey = "buffCooldownTextOffsetY",
        defaultAnchor = "BOTTOMRIGHT",
        defaultLayer = 5,
    },
    debuff = {
        rootKey = "Debuffs",
        filter = "HARMFUL",
        filterKey = "debuffs",
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
        showTextKey = "debuffShowCooldownText",
        showStackKey = "debuffShowStackCount",
        stackAnchorKey = "debuffStackCountAnchor",
        stackSizeKey = "debuffStackTextSize",
        stackXKey = "debuffStackTextOffsetX",
        stackYKey = "debuffStackTextOffsetY",
        cooldownSizeKey = "debuffCooldownTextSize",
        cooldownXKey = "debuffCooldownTextOffsetX",
        cooldownYKey = "debuffCooldownTextOffsetY",
        defaultAnchor = "TOPLEFT",
        defaultLayer = 6,
    },
}

local GROUP_LANE_SPECS = {
    buff = {
        rootKey = "Buffs", filter = "HELPFUL",
        showKey = "showBuffs", maxKey = "maxBuffs", sizeKey = "buffIconSize",
        spacingKey = "buffSpacing", perRowKey = "buffPerRow", growthXKey = "buffGrowthX",
        growthYKey = "buffGrowthY", anchorKey = "buffAnchor", xKey = "buffOffsetX",
        yKey = "buffOffsetY", layerKey = "buffLayer", filterKey = "buffFilter",
        showTextKey = "buffShowCooldown", showStackKey = "buffShowStacks",
        cooldownSizeKey = "buffCooldownSize", stackSizeKey = "buffStackSize",
        defaultSize = 22, defaultMax = 4, defaultPerRow = 4, defaultAnchor = "BOTTOMRIGHT",
        defaultLayer = 5,
    },
    debuff = {
        rootKey = "Debuffs", filter = "HARMFUL",
        showKey = "showDebuffs", maxKey = "maxDebuffs", sizeKey = "debuffIconSize",
        spacingKey = "debuffSpacing", perRowKey = "debuffPerRow", growthXKey = "debuffGrowthX",
        growthYKey = "debuffGrowthY", anchorKey = "debuffAnchor", xKey = "debuffOffsetX",
        yKey = "debuffOffsetY", layerKey = "debuffLayer", filterKey = "debuffFilter",
        showTextKey = "debuffShowCooldown", showStackKey = "debuffShowStacks",
        cooldownSizeKey = "debuffCooldownSize", stackSizeKey = "debuffStackSize",
        defaultSize = 20, defaultMax = 3, defaultPerRow = 3, defaultAnchor = "TOPLEFT",
        defaultLayer = 6,
    },
    external = {
        rootKey = "Externals", filter = "HELPFUL|RAID",
        showKey = "showExternals", maxKey = "maxExternals", sizeKey = "externalIconSize",
        spacingKey = "externalSpacing", perRowKey = "externalPerRow", growthXKey = "externalGrowthX",
        growthYKey = "externalGrowthY", anchorKey = "externalAnchor", xKey = "externalOffsetX",
        yKey = "externalOffsetY", layerKey = "externalLayer", filterKey = "externalFilter",
        showTextKey = "externalShowCooldown", showStackKey = "externalShowStacks",
        cooldownSizeKey = "externalCooldownSize", stackSizeKey = "externalStackSize",
        defaultSize = 28, defaultMax = 2, defaultPerRow = 2, defaultAnchor = "CENTER",
        defaultLayer = 7,
    },
}

local function NoopTrue() return true end
local function NoopFalse() return false end

local CT = A3.CooldownText
if type(CT) ~= "table" then
    CT = {}
    A3.CooldownText = CT
end

local function Round(value)
    value = tonumber(value) or 0
    return math_floor(value + 0.5)
end

local function ClampNumber(value, fallback, minValue, maxValue)
    value = tonumber(value)
    if value == nil then value = tonumber(fallback) or 0 end
    if minValue and value < minValue then value = minValue end
    if maxValue and value > maxValue then value = maxValue end
    return value
end

local function Clamp01(value, fallback)
    return ClampNumber(value, fallback or 1, 0, 1)
end

local function ReadRaw(primary, secondary, key)
    if type(primary) == "table" and primary[key] ~= nil then return primary[key] end
    if type(secondary) == "table" and secondary[key] ~= nil then return secondary[key] end
    return nil
end

local function ReadBool(primary, secondary, key, fallback)
    local value = ReadRaw(primary, secondary, key)
    if value == nil then return fallback == true end
    return value == true
end

local function ReadNumber(primary, secondary, key, fallback, minValue, maxValue)
    return ClampNumber(ReadRaw(primary, secondary, key), fallback, minValue, maxValue)
end

local function ReadAnchor(primary, secondary, key, fallback)
    local value = ReadRaw(primary, secondary, key)
    if value == "TOPLEFT" or value == "TOP" or value == "TOPRIGHT"
        or value == "LEFT" or value == "CENTER" or value == "RIGHT"
        or value == "BOTTOMLEFT" or value == "BOTTOM" or value == "BOTTOMRIGHT" then
        return value
    end
    return fallback or "CENTER"
end

local function EnsureDB()
    if A3.EnsureDB then
        local auras, shared = A3.EnsureDB()
        if type(auras) == "table" then
            auras.shared = type(auras.shared) == "table" and auras.shared or {}
            return auras, auras.shared
        end
    end
    local db = _G.MSUF_DB
    if type(db) ~= "table" then return {}, {} end
    db.auras3 = type(db.auras3) == "table" and db.auras3 or {}
    db.auras3.shared = type(db.auras3.shared) == "table" and db.auras3.shared or {}
    return db.auras3, db.auras3.shared
end

local function NormalizeRuntimeUnit(unit)
    unit = tostring(unit or "")
    if unit == "boss" then return "boss1" end
    if MANAGED_UNITS[unit] then return unit end
    return nil
end

local function IsGroupFrame(frame)
    if not frame then return false end
    if frame._msufIsGroupFrame or frame._msufGFKind then return true end
    local unit = frame.unit
    return type(unit) == "string" and (unit:match("^party%d+$") or unit:match("^raid%d+$")) and true or false
end

local function UnitAuraIconsEnabled(auras, unit)
    if not (type(auras) == "table" and auras.enabled == true) then return false end
    local flag = UNIT_FLAG[NormalizeRuntimeUnit(unit)]
    return flag and auras[flag] == true or false
end

local function EffectiveUnitTables(auras, unit)
    local shared = type(auras.shared) == "table" and auras.shared or {}
    local perUnit = type(auras.perUnit) == "table" and auras.perUnit or nil
    local unitCfg = perUnit and perUnit[unit] or nil
    local layout = unitCfg and unitCfg.overrideLayout == true and type(unitCfg.layout) == "table" and unitCfg.layout or nil
    local filters = unitCfg and unitCfg.overrideFilters == true and type(unitCfg.filters) == "table" and unitCfg.filters or nil
    return layout or {}, shared, filters or shared.filters
end

local function GrowthParts(growth, rowWrap)
    growth = tostring(growth or "RIGHT")
    rowWrap = tostring(rowWrap or "DOWN")
    if growth == "LEFTUP" then return "LEFT", "UP", -1, 1, false end
    if growth == "LEFTDOWN" then return "LEFT", "DOWN", -1, -1, false end
    if growth == "RIGHTUP" then return "RIGHT", "UP", 1, 1, false end
    if growth == "RIGHTDOWN" then return "RIGHT", "DOWN", 1, -1, false end
    if growth == "LEFT" then return "LEFT", rowWrap, -1, rowWrap == "UP" and 1 or -1, false end
    if growth == "UP" then return "UP", "UP", 1, 1, true end
    if growth == "DOWN" then return "DOWN", "DOWN", 1, -1, true end
    return "RIGHT", rowWrap, 1, rowWrap == "UP" and 1 or -1, false
end

local function GroupGrowthParts(growthX, growthY)
    growthX = tostring(growthX or "RIGHT")
    growthY = tostring(growthY or "DOWN")
    if growthX == "UP" or growthX == "DOWN" then
        return growthX, growthX, 1, growthX == "UP" and 1 or -1, true
    end
    local xSign = growthX == "LEFT" and -1 or 1
    local ySign = growthY == "UP" and 1 or -1
    return growthX == "LEFT" and "LEFT" or "RIGHT", growthY == "UP" and "UP" or "DOWN", xSign, ySign, false
end

local function ButtonAnchor(xSign, ySign)
    if xSign < 0 then
        return ySign > 0 and "BOTTOMRIGHT" or "TOPRIGHT"
    end
    return ySign > 0 and "BOTTOMLEFT" or "TOPLEFT"
end

local VALID_NATIVE_FILTER_TOKENS = {
    HELPFUL = true,
    HARMFUL = true,
    PLAYER = true,
    RAID = true,
    CANCELABLE = true,
    NOT_CANCELABLE = true,
    INCLUDE_NAME_PLATE_ONLY = true,
}

local function AddNativeFilterToken(out, seen, token, baseToken)
    token = tostring(token or ""):upper():gsub("^%s+", ""):gsub("%s+$", "")
    if token == "" or not VALID_NATIVE_FILTER_TOKENS[token] then return end
    if (token == "HELPFUL" or token == "HARMFUL") and token ~= baseToken then return end
    if seen[token] then return end
    seen[token] = true
    out[#out + 1] = token
end

local function NormalizeNativeFilterString(filter, fallback)
    fallback = tostring(fallback or "")
    filter = tostring(filter or "")
    local baseToken = (fallback:find("HARMFUL", 1, true) or filter:find("HARMFUL", 1, true)) and "HARMFUL" or "HELPFUL"
    local out, seen = {}, {}
    AddNativeFilterToken(out, seen, baseToken, baseToken)
    for token in fallback:gmatch("[^|]+") do AddNativeFilterToken(out, seen, token, baseToken) end
    for token in filter:gmatch("[^|]+") do AddNativeFilterToken(out, seen, token, baseToken) end
    return table_concat(out, "|")
end

local function GridShape(maxCount, perRow, verticalGrowth)
    maxCount = Round(maxCount)
    perRow = math_max(Round(perRow), 1)
    if maxCount <= 0 then return 1, 1 end
    local major = math_min(perRow, maxCount)
    local minor = math_floor((maxCount + perRow - 1) / perRow)
    if verticalGrowth then return minor, major end
    return major, minor
end

local function NativeFilter(baseFilter, filters)
    filters = type(filters) == "table" and filters or nil
    local filter = tostring(baseFilter or "")
    local helpful = filter:find("HELPFUL", 1, true) ~= nil
    local harmful = filter:find("HARMFUL", 1, true) ~= nil
    if filters then
        if filters.onlyMine == true then filter = filter .. "|PLAYER" end
        if filters.onlyImportant == true or filters.exclusive == "important" then filter = filter .. "|RAID" end
        if filters.raid == true then filter = filter .. "|RAID" end
        if filters.includeBoss == true or filters.boss == true then filter = filter .. "|RAID" end
        if filters.includeStealable == true and helpful then filter = filter .. "|RAID" end
        if filters.includeDispellable == true and harmful then filter = filter .. "|RAID" end
    end
    return NormalizeNativeFilterString(filter, baseFilter)
end

local function CompileUnitLane(unit, shared, layout, filtersRoot, kind)
    local spec = LANE_SPECS[kind]
    local filters = type(filtersRoot) == "table" and type(filtersRoot[spec.filterKey]) == "table" and filtersRoot[spec.filterKey] or nil
    local sizeDefault = ReadRaw(layout, shared, spec.sizeKey) or ReadRaw(layout, shared, "iconSize") or DEFAULT_SHARED.iconSize
    local size = ClampNumber(sizeDefault, DEFAULT_SHARED.iconSize, 1, 128)
    local spacing = ReadNumber(layout, shared, "spacing", DEFAULT_SHARED.spacing, 0, 64)
    local perRow = ReadNumber(shared, nil, spec.perRowKey, ReadRaw(shared, nil, "perRow") or DEFAULT_SHARED.perRow, 1, 40)
    local maxCount = ReadNumber(shared, nil, spec.maxKey, DEFAULT_SHARED[spec.maxKey] or 12, 0, 80)
    local enabled = ReadBool(shared, nil, spec.showKey, true) and maxCount > 0
    local growth = ReadRaw(shared, nil, spec.growthKey) or ReadRaw(shared, nil, "growth") or DEFAULT_SHARED.growth
    local rowWrap = ReadRaw(shared, nil, spec.wrapKey) or ReadRaw(shared, nil, "rowWrap") or DEFAULT_SHARED.rowWrap
    local growthX, growthY, xSign, ySign, verticalGrowth = GrowthParts(growth, rowWrap)
    local cols, rows = GridShape(maxCount, perRow, verticalGrowth)
    return {
        kind = kind,
        rootKey = spec.rootKey,
        unit = unit,
        enabled = enabled == true,
        nativeFilter = NativeFilter(spec.filter, filters),
        max = Round(maxCount),
        size = size,
        spacing = spacing,
        step = size + spacing,
        perRow = Round(perRow),
        cols = cols,
        rows = rows,
        width = math_max(1, cols * size + math_max(cols - 1, 0) * spacing),
        height = math_max(1, rows * size + math_max(rows - 1, 0) * spacing),
        x = Round(ReadNumber(layout, shared, spec.xKey, DEFAULT_SHARED[spec.xKey] or 0, -4096, 4096)),
        y = Round(ReadNumber(layout, shared, spec.yKey, DEFAULT_SHARED[spec.yKey] or 0, -4096, 4096)),
        anchor = ReadAnchor(layout, shared, spec.anchorKey, spec.defaultAnchor),
        layer = Round(ReadNumber(layout, shared, spec.layerKey, spec.defaultLayer, 1, 15)),
        alpha = 1,
        growthX = growthX,
        growthY = growthY,
        xSign = xSign,
        ySign = ySign,
        verticalGrowth = verticalGrowth == true,
        initialAnchor = ButtonAnchor(xSign, ySign),
        showCooldownText = ReadBool(shared, nil, spec.showTextKey, ReadBool(shared, nil, "showCooldownText", true)),
        showStacks = ReadBool(shared, nil, spec.showStackKey, ReadBool(shared, nil, "showStackCount", true)),
        cooldownSize = ReadNumber(layout, shared, spec.cooldownSizeKey, ReadRaw(shared, nil, "cooldownTextSize") or DEFAULT_SHARED.cooldownTextSize, 6, 40),
        cooldownX = ReadNumber(layout, shared, spec.cooldownXKey, ReadRaw(shared, nil, "cooldownTextOffsetX") or DEFAULT_SHARED.cooldownTextOffsetX, -2000, 2000),
        cooldownY = ReadNumber(layout, shared, spec.cooldownYKey, ReadRaw(shared, nil, "cooldownTextOffsetY") or DEFAULT_SHARED.cooldownTextOffsetY, -2000, 2000),
        stackAnchor = ReadAnchor(shared, nil, spec.stackAnchorKey, ReadRaw(shared, nil, "stackCountAnchor") or DEFAULT_SHARED.stackCountAnchor),
        stackSize = ReadNumber(layout, shared, spec.stackSizeKey, ReadRaw(shared, nil, "stackTextSize") or DEFAULT_SHARED.stackTextSize, 6, 40),
        stackX = ReadNumber(layout, shared, spec.stackXKey, ReadRaw(shared, nil, "stackTextOffsetX") or DEFAULT_SHARED.stackTextOffsetX, -2000, 2000),
        stackY = ReadNumber(layout, shared, spec.stackYKey, ReadRaw(shared, nil, "stackTextOffsetY") or DEFAULT_SHARED.stackTextOffsetY, -2000, 2000),
    }
end

local function CompileGroupLane(unit, source, kind)
    local spec = GROUP_LANE_SPECS[kind]
    if not (spec and type(source) == "table") then return nil end
    local size = ClampNumber(source[spec.sizeKey] or source.iconSize, spec.defaultSize, 1, 128)
    local spacing = ClampNumber(source[spec.spacingKey] or source.spacing, 1, 0, 64)
    local perRow = ClampNumber(source[spec.perRowKey] or source.perRow, spec.defaultPerRow, 1, 40)
    local maxCount = ClampNumber(source[spec.maxKey], spec.defaultMax, 0, 80)
    local enabled = source.enabled ~= false and source[spec.showKey] == true and maxCount > 0
    local growthX, growthY, xSign, ySign, verticalGrowth = GroupGrowthParts(source[spec.growthXKey], source[spec.growthYKey])
    local cols, rows = GridShape(maxCount, perRow, verticalGrowth)
    return {
        kind = kind,
        rootKey = spec.rootKey,
        unit = unit,
        enabled = enabled == true,
        nativeFilter = NormalizeNativeFilterString(source[spec.filterKey], spec.filter),
        max = Round(maxCount),
        size = size,
        spacing = spacing,
        step = size + spacing,
        perRow = Round(perRow),
        cols = cols,
        rows = rows,
        width = math_max(1, cols * size + math_max(cols - 1, 0) * spacing),
        height = math_max(1, rows * size + math_max(rows - 1, 0) * spacing),
        x = Round(ClampNumber(source[spec.xKey], 0, -4096, 4096)),
        y = Round(ClampNumber(source[spec.yKey], 0, -4096, 4096)),
        anchor = ReadAnchor(source, nil, spec.anchorKey, spec.defaultAnchor),
        layer = Round(ClampNumber(source[spec.layerKey], spec.defaultLayer, 1, 15)),
        alpha = Clamp01(source[spec.alphaKey], 1),
        growthX = growthX,
        growthY = growthY,
        xSign = xSign,
        ySign = ySign,
        verticalGrowth = verticalGrowth == true,
        initialAnchor = ButtonAnchor(xSign, ySign),
        showCooldownText = source[spec.showTextKey] ~= false,
        showStacks = source[spec.showStackKey] ~= false,
        cooldownSize = ClampNumber(source[spec.cooldownSizeKey] or source.cooldownSize, DEFAULT_SHARED.cooldownTextSize, 6, 40),
        cooldownX = 0,
        cooldownY = 0,
        stackAnchor = "BOTTOMRIGHT",
        stackSize = ClampNumber(source[spec.stackSizeKey] or source.stackSize, DEFAULT_SHARED.stackTextSize, 6, 40),
        stackX = 0,
        stackY = 0,
    }
end

local frameSpecConfigCache = setmetatable({}, { __mode = "k" })

local function InvalidateUnitRuntimeConfig(unit)
    unit = NormalizeRuntimeUnit(unit)
    if not unit then return nil end
    local runtimeCache = A3._runtimeConfigCache
    if runtimeCache then runtimeCache[unit] = nil end
    for frameSpec, cached in pairs(frameSpecConfigCache) do
        if cached and cached.unit == unit then frameSpecConfigCache[frameSpec] = nil end
    end
    return unit
end

local function BuildUnitFrameConfig(unit)
    unit = NormalizeRuntimeUnit(unit)
    if not unit then return nil end
    local auras, shared = EnsureDB()
    if not UnitAuraIconsEnabled(auras, unit) then
        return { unit = unit, enabled = false, lanes = {} }
    end
    local layout, sharedLayout, filtersRoot = EffectiveUnitTables(auras, unit)
    local buff = CompileUnitLane(unit, sharedLayout, layout, filtersRoot, "buff")
    local debuff = CompileUnitLane(unit, sharedLayout, layout, filtersRoot, "debuff")
    return {
        unit = unit,
        enabled = (buff and buff.enabled == true) or (debuff and debuff.enabled == true),
        lanes = { buff = buff, debuff = debuff },
        group = false,
    }
end

function A3.ResolveUnitFrameConfig(unit, frameSpec)
    unit = NormalizeRuntimeUnit(unit)
    if not unit then return nil end
    local gen = A3._runtimeConfigGen or 1
    if frameSpec ~= nil then
        local cached = frameSpecConfigCache[frameSpec]
        if cached and cached.gen == gen and cached.unit == unit then return cached.config end
        local cfg = BuildUnitFrameConfig(unit)
        frameSpecConfigCache[frameSpec] = { gen = gen, unit = unit, config = cfg }
        return cfg
    end
    A3._runtimeConfigCache = A3._runtimeConfigCache or {}
    local cached = A3._runtimeConfigCache[unit]
    if cached and cached.gen == gen then return cached.config end
    local cfg = BuildUnitFrameConfig(unit)
    A3._runtimeConfigCache[unit] = { gen = gen, config = cfg }
    return cfg
end

local function ResolveGroupFrameConfig(frame, unit)
    if not frame then return nil end
    unit = unit or frame.unit
    local spec = frame.MSUFSpec
    local source = spec and (spec.auras or (spec.group and spec.group.auras))
    local gen = A3._runtimeConfigGen or 1
    local cached = frame._msufA3NativeGroupConfig
    if cached and frame._msufA3NativeGroupSource == source and frame._msufA3NativeGroupUnit == unit
        and frame._msufA3NativeGroupGen == gen then
        return cached
    end
    local cfg = { unit = unit, enabled = false, lanes = {}, group = true }
    if type(source) == "table" and type(unit) == "string" and unit ~= "" and source.enabled ~= false then
        local buff = CompileGroupLane(unit, source, "buff")
        local debuff = CompileGroupLane(unit, source, "debuff")
        local external = CompileGroupLane(unit, source, "external")
        cfg.lanes.buff = buff
        cfg.lanes.debuff = debuff
        cfg.lanes.external = external
        cfg.enabled = (buff and buff.enabled == true) or (debuff and debuff.enabled == true) or (external and external.enabled == true)
    end
    frame._msufA3NativeGroupSource = source
    frame._msufA3NativeGroupUnit = unit
    frame._msufA3NativeGroupGen = gen
    frame._msufA3NativeGroupConfig = cfg
    return cfg
end

local function FrameAuraConfig(frame, unit)
    if IsGroupFrame(frame) then
        return ResolveGroupFrameConfig(frame, unit or frame.unit)
    end
    return A3.ResolveUnitFrameConfig(unit or (frame and frame.unit), frame and frame.MSUFSpec)
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
        cols = lane.cols,
        rows = lane.rows,
        width = lane.width,
        height = lane.height,
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
    }
end

function A3.UnitFrameAuraEnabled(unit)
    local cfg = A3.ResolveUnitFrameConfig(unit)
    return cfg and cfg.enabled == true or false
end

local function ApplyFont(fs, size)
    if not fs then return end
    local fontPath, fontFlags, r, g, b, _, useShadow
    local readFont = _G.MSUF_GetGlobalFontSettings
    if type(readFont) == "function" then
        fontPath, fontFlags, r, g, b, _, useShadow = readFont()
    end
    fs:SetFont(fontPath or STANDARD_TEXT_FONT, ClampNumber(size, 12, 6, 40), fontFlags or "OUTLINE")
    fs:SetTextColor(r or 1, g or 1, b or 1, 1)
    if useShadow then fs:SetShadowOffset(1, -1) else fs:SetShadowOffset(0, 0) end
end

local function EnsureRoot(frame)
    if not frame then return nil end
    local root = frame.Auras
    if root and root._msufA3NativeRoot == true then return root end
    root = CreateFrame("Frame", nil, frame)
    root._msufA3NativeRoot = true
    root:SetAllPoints(frame)
    root:Hide()
    frame.Auras = root
    return root
end

local function LaneTrackingSignature(lane)
    return tostring(lane.unit) .. "\030" .. tostring(lane.kind) .. "\030" .. tostring(lane.nativeFilter)
        .. "\030" .. tostring(lane.max)
end

local function LaneLayoutSignature(lane)
    return tostring(lane.size) .. "\030" .. tostring(lane.spacing)
        .. "\030" .. tostring(lane.step) .. "\030" .. tostring(lane.perRow)
        .. "\030" .. tostring(lane.cols) .. "\030" .. tostring(lane.rows)
        .. "\030" .. tostring(lane.width) .. "\030" .. tostring(lane.height)
        .. "\030" .. tostring(lane.anchor) .. "\030" .. tostring(lane.x)
        .. "\030" .. tostring(lane.y) .. "\030" .. tostring(lane.layer)
        .. "\030" .. tostring(lane.xSign) .. "\030" .. tostring(lane.ySign)
        .. "\030" .. tostring(lane.verticalGrowth) .. "\030" .. tostring(lane.initialAnchor)
        .. "\030" .. tostring(lane.showCooldownText) .. "\030" .. tostring(lane.cooldownSize)
        .. "\030" .. tostring(lane.cooldownX) .. "\030" .. tostring(lane.cooldownY)
        .. "\030" .. tostring(lane.alpha) .. "\030" .. tostring(A3._nativeVisualGen or 0)
end

local function LayoutButton(button, lane, index)
    local n = index - 1
    local perRow = math_max(lane.perRow or 1, 1)
    local major = n % perRow
    local minor = math_floor(n / perRow)
    local col, row
    if lane.verticalGrowth then
        col, row = minor, major
    else
        col, row = major, minor
    end
    local x = col * (lane.step or lane.size or 1) * (lane.xSign or 1)
    local y = row * (lane.step or lane.size or 1) * (lane.ySign or -1)
    button:ClearAllPoints()
    button:SetPoint(lane.initialAnchor or "TOPLEFT", button:GetParent(), lane.initialAnchor or "TOPLEFT", x, y)
    button:SetSize(lane.size, lane.size)
end

local function PrepareAuraButton(button, lane, index)
    button._msufA3NativeButton = true
    button._msufA3LaneKind = lane.kind
    button:SetSize(lane.size, lane.size)
    button:SetFrameLevel((button:GetParent():GetFrameLevel() or 0) + 1)

    local icon = button.Icon
    if not icon then
        icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(button)
        button.Icon = icon
    end
    button:SetIcon(icon)

    local duration = button.Text or button.DurationText
    if not duration then
        duration = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        button.Text = duration
    end
    duration:ClearAllPoints()
    duration:SetPoint("CENTER", button, "CENTER", lane.cooldownX or 0, lane.cooldownY or 0)
    ApplyFont(duration, lane.cooldownSize)
    if lane.showCooldownText ~= true then duration:Hide() else duration:Show() end
    button:SetDurationText(duration)

    LayoutButton(button, lane, index)
end

local function ConfigureContainer(container, lane, parentFrame)
    container._msufA3NativeLane = lane.kind
    container.unit = lane.unit
    container.createdButtons = lane.max
    container:SetSize(lane.width, lane.height)
    container:ClearAllPoints()
    container:SetPoint(lane.anchor, parentFrame, lane.anchor, lane.x, lane.y)
    container:SetAlpha(lane.alpha or 1)
    container:SetFrameLevel((parentFrame:GetFrameLevel() or 0) + (lane.layer or 1))
    container:SetUnit(lane.unit)
    container:AddAuraFilter(lane.nativeFilter, { maxFrameCount = lane.max })
end

local function CreateNativeLane(root, lane, parentFrame)
    local container = CreateFrame("AuraContainer", nil, root, "CustomAuraContainerTemplate")
    A3.nativeAuraRuntimeAvailable = true
    ConfigureContainer(container, lane, parentFrame)
    for i = 1, lane.max do
        local button = CreateFrame("AuraButton", nil, container, "CustomAuraButtonTemplate")
        PrepareAuraButton(button, lane, i)
        container[i] = button
        container:AddAuraFrame(button)
    end
    container:Show()
    return container
end

local function HideLane(lane)
    if lane then lane:Hide() end
end

local function ApplyLane(root, lane, parentFrame)
    if not (root and lane and lane.enabled) then return nil end
    local key = lane.rootKey
    local trackingSignature = LaneTrackingSignature(lane)
    local layoutSignature = LaneLayoutSignature(lane)
    local current = root[key]
    if current
        and current._msufA3TrackingSignature == trackingSignature
        and current._msufA3LayoutSignature == layoutSignature
    then
        current:Show()
        return current
    end
    HideLane(current)
    current = CreateNativeLane(root, lane, parentFrame)
    if current then
        current._msufA3TrackingSignature = trackingSignature
        current._msufA3LayoutSignature = layoutSignature
        root[key] = current
    end
    return current
end

local function HideState(frame)
    local root = frame and frame.Auras
    if not (root and root._msufA3NativeRoot) then return end
    HideLane(root.Buffs)
    HideLane(root.Debuffs)
    HideLane(root.Externals)
    root._msufA3Config = nil
    root:Hide()
    local unit = frame and frame.unit
    if unit and A3._runtimeFrames and A3._runtimeFrames[unit] == frame then
        A3._runtimeFrames[unit] = nil
    end
    if unit and A3._unitFrameOwners and A3._unitFrameOwners[unit] == frame then
        A3._unitFrameOwners[unit] = nil
    end
    if frame then frame._msufA3UnitAuraOwner = nil end
end

local function ApplyConfig(frame, cfg)
    if not (frame and cfg and cfg.enabled) then
        HideState(frame)
        return false
    end
    local root = EnsureRoot(frame)
    if not root then return false end
    root.unit = cfg.unit or frame.unit
    root._msufA3Config = cfg
    root:SetAllPoints(frame)
    local lanes = cfg.lanes or {}
    ApplyLane(root, lanes.buff, frame)
    ApplyLane(root, lanes.debuff, frame)
    ApplyLane(root, lanes.external, frame)
    if not (lanes.buff and lanes.buff.enabled) then HideLane(root.Buffs) end
    if not (lanes.debuff and lanes.debuff.enabled) then HideLane(root.Debuffs) end
    if not (lanes.external and lanes.external.enabled) then HideLane(root.Externals) end
    root:Show()
    return true
end

function A3.SetUnitFrameOwner(unit, frame, owns)
    if not unit then return end
    A3._unitFrameOwners = A3._unitFrameOwners or {}
    if owns and frame then
        A3._unitFrameOwners[unit] = frame
    elseif A3._unitFrameOwners[unit] == frame or frame == nil then
        A3._unitFrameOwners[unit] = nil
    end
end

function A3.EnableFrame(frame)
    if not (frame and frame.unit and MANAGED_UNITS[frame.unit]) then return false end
    local cfg = A3.ResolveUnitFrameConfig(frame.unit, frame.MSUFSpec)
    if not (cfg and cfg.enabled) then
        HideState(frame)
        A3.SetUnitFrameOwner(frame.unit, frame, false)
        return false
    end
    A3._runtimeFrames = A3._runtimeFrames or {}
    A3._runtimeFrames[frame.unit] = frame
    A3.SetUnitFrameOwner(frame.unit, frame, true)
    return ApplyConfig(frame, cfg)
end

function A3.DisableFrame(frame)
    if not frame then return true end
    HideState(frame)
    local unit = frame.unit
    if unit and A3._runtimeFrames and A3._runtimeFrames[unit] == frame then
        A3._runtimeFrames[unit] = nil
    end
    if unit then A3.SetUnitFrameOwner(unit, frame, false) end
    frame._msufA3UnitAuraOwner = nil
    return true
end

function A3.RenderFrame(frame)
    if not frame then return false end
    local cfg = FrameAuraConfig(frame, frame.unit)
    return ApplyConfig(frame, cfg)
end

A3.ForceUpdateFrame = A3.RenderFrame
A3.RenderCachedFrame = A3.RenderFrame

function A3.QueueIdentityAuraRebuild(frame)
    return A3.RenderFrame(frame)
end

function A3.RuntimeOwnsUnit(unit)
    unit = NormalizeRuntimeUnit(unit)
    return unit and A3._runtimeFrames and A3._runtimeFrames[unit] ~= nil or false
end

local function ApplyRuntimeUnit(runtimeUnit)
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
    frame._msufIsGroupFrame = true
    if kind then frame._msufGFKind = kind end
    if UF.ApplyElementToFrame then
        UF.ApplyElementToFrame(frame, "Auras", frame.MSUFSpec, nil)
    else
        A3.RenderFrame(frame)
    end
    return true
end

function A3._RequestGroupKindNow(kind)
    local gf = A3._GroupAPI()
    if not gf then return false end
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
    local frame = type(gf.FrameForUnit) == "function" and gf.FrameForUnit(unit) or nil
    return frame and A3._ApplyGroupAuraFrame(frame, unit, frame._msufGFKind) or false
end

local function RequestUnitNow(unit)
    unit = tostring(unit or "")
    if unit == "" or unit == "*" then
        local didWork = ApplyRuntimeUnit("player")
        didWork = ApplyRuntimeUnit("target") or didWork
        didWork = ApplyRuntimeUnit("focus") or didWork
        for i = 1, 5 do didWork = ApplyRuntimeUnit("boss" .. i) or didWork end
        didWork = A3._RequestGroupKindNow(nil) or didWork
        return didWork
    end
    if unit == "boss" then
        local didWork = false
        for i = 1, 5 do didWork = ApplyRuntimeUnit("boss" .. i) or didWork end
        return didWork
    end
    if unit == "group" or unit == "groups" then return A3._RequestGroupKindNow(nil) end
    if unit == "party" or unit == "gf_party" then return A3._RequestGroupKindNow("party") end
    if unit == "raid" or unit == "gf_raid" then
        local didWork = A3._RequestGroupKindNow("raid")
        return A3._RequestGroupKindNow("mythicraid") or didWork
    end
    if unit == "mythicraid" or unit == "gf_mythicraid" then return A3._RequestGroupKindNow("mythicraid") end
    if unit:match("^party%d+$") or unit:match("^raid%d+$") then return A3._RequestGroupUnitNow(unit) end
    unit = NormalizeRuntimeUnit(unit)
    return unit and ApplyRuntimeUnit(unit) or false
end

function A3.RequestUnit(unit)
    return RequestUnitNow(unit)
end

function A3.RefreshAll()
    A3.BumpRuntimeConfig()
    A3._runtimeConfigCache = nil
    frameSpecConfigCache = setmetatable({}, { __mode = "k" })
    RequestUnitNow("*")
    return true
end

function A3.RequestApply()
    return A3.RefreshAll()
end

function A3.RefreshUnit(unit)
    if unit == "boss" then
        for i = 1, 5 do InvalidateUnitRuntimeConfig("boss" .. i) end
        return A3.RequestUnit("boss")
    end
    local runtimeUnit = InvalidateUnitRuntimeConfig(unit)
    if runtimeUnit then return A3.RequestUnit(runtimeUnit) end
    A3.BumpRuntimeConfig()
    A3._runtimeConfigCache = nil
    frameSpecConfigCache = setmetatable({}, { __mode = "k" })
    return A3.RequestUnit(unit)
end

function A3.ApplyFontsFromGlobal()
    A3._nativeVisualGen = (A3._nativeVisualGen or 0) + 1
    return A3.RefreshAll()
end

local AurasElement = {
    events = EMPTY_EVENTS,
    unitlessEvents = EMPTY_EVENTS,
}

function AurasElement.IsEnabled(frame)
    local cfg = FrameAuraConfig(frame, frame and frame.unit)
    return cfg and cfg.enabled == true or false
end

function AurasElement.Create(frame)
    EnsureRoot(frame)
end

function AurasElement.Apply(frame)
    return A3.RenderFrame(frame)
end

function AurasElement.Enable(frame)
    if IsGroupFrame(frame) then
        frame._msufA3GroupRuntime = true
        local cfg = ResolveGroupFrameConfig(frame, frame and frame.unit)
        if not (cfg and cfg.enabled) then
            HideState(frame)
            return false
        end
        return ApplyConfig(frame, cfg)
    end
    return A3.EnableFrame(frame)
end

function AurasElement.Disable(frame)
    return A3.DisableFrame(frame)
end

function AurasElement.Update(frame)
    return A3.RenderFrame(frame)
end

UF.RegisterElement("Auras", AurasElement)

A3.frontendOnly = false
A3.backendEnabled = true
A3.unitFrameAuras = true
A3.nativeAuraBackend = true
A3.RefreshRuntime = A3.RefreshAll
MSUF.AuraBackendEnabled = true
MSUF.AuraCore = MSUF.AuraCore or _G.MSUF_AuraCore or {}
MSUF.AuraCore.Auras3 = A3

CT.ApplyButtonStyle = NoopFalse
CT.RegisterButton = NoopFalse
CT.TouchButton = NoopTrue
CT.UnregisterButton = NoopTrue
CT.Invalidate = function() return A3.RefreshAll() end
CT.ForceRecolor = function() return A3.ApplyFontsFromGlobal() end
