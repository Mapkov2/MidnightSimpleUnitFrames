--- Auras3/MSUF_Auras3_UnitFrames.lua
--- WoW 12.1 native AuraContainer/AuraButton runtime.
---
--- MSUF 6.0 is 12.1-only for aura display work. This file intentionally does
--- not inspect or transform aura payload data itself. Blizzard's native
--- AuraContainer owns tracking, filtering, and assignment; MSUF only builds the
--- visual containers, AuraButton pools, layout, and refresh surface.
local addonName, MSUF = ...
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
if A3.swapUseUpdateAllAuras == nil then
    A3.swapUseUpdateAllAuras = false
end

local type, tostring, tonumber, pairs, next = type, tostring, tonumber, pairs, next
local table_concat, table_sort = table.concat, table.sort
local math_floor, math_min, math_max = math.floor, math.min, math.max
local CreateFrame = _G.CreateFrame
local C_AddOns = _G.C_AddOns
local C_Timer = _G.C_Timer
local STANDARD_TEXT_FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local EMPTY_EVENTS = {}
local AURA_CONTAINER_ADDON = "Blizzard_AuraContainer"
local MSUF_AURA_SENSOR_EDGE_TEXTURE = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\Masks\\msuf_frame_edge_thin_256x64.tga"
local AURA_BORDER_OPTIONS = {
    showIcon = false,
    showWhenHarmful = true,
    showWhenHelpful = false,
}
local AURA_SENSOR_BORDER_OPTIONS = {
    showIcon = false,
    showWhenHarmful = true,
    showWhenHelpful = false,
}
local AURA_SENSOR_OVERLAY_OPTIONS = {
    showIcon = false,
    showWhenHarmful = true,
    showWhenHelpful = false,
}
local IDENTITY_AURA_REFRESH_REASONS = {
    MSUF_UNIT_IDENTITY_AURAS = true,
    MSUF_UNIT_IDENTITY_SOFT_AURAS = true,
    MSUF_GF_UNIT_IDENTITY = true,
}
-- Identity reasons safe to coalesce and flush next tick. A target/focus swap
-- keeps the same unit token, so MSUF must ask the container for one content
-- refresh. Coalesce that refresh by frame so swap spam resolves to the latest
-- identity once per tick instead of forcing synchronous reparses per event.
-- Group identity is intentionally excluded so roster builds settle in one pass.
local DEFERRED_IDENTITY_REASONS = {
    MSUF_UNIT_IDENTITY_AURAS = true,
    MSUF_UNIT_IDENTITY_SOFT_AURAS = true,
}
local COLD_APPLY_REASONS = {
    MSUF_ELEMENT_REFRESH = true,
}

local RefreshAppliedNativeRoot
local EnsureNativeAuraRefreshDriver

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
    showTooltip = true,
    showCooldownSwipe = true,
    cooldownSwipeReverse = false,
    showDurationBar = false,
    durationBarHeight = 2,
    durationBarDisplay = "BAR_ONLY",
    durationBarPosition = "BOTTOM",
    durationBarDirection = "REMAINING",
    showCooldownText = true,
    showStackCount = true,
    debuffTypeBorderMode = "OFF",
    useDebuffTypeBorders = false,
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
    cooldownTextAnchor = "CENTER",
    stackTextSize = 14,
    stackTextOffsetX = -1,
    stackTextOffsetY = 1,
    cooldownTextSize = 14,
    cooldownTextOffsetX = 0,
    cooldownTextOffsetY = 0,
    cooldownDecimalSeconds = 3,
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
        swipeKey = "buffShowCooldownSwipe",
        swipeReverseKey = "buffCooldownSwipeReverse",
        showDurationBarKey = "buffShowDurationBar",
        durationBarHeightKey = "buffDurationBarHeight",
        durationBarDisplayKey = "buffDurationBarDisplay",
        durationBarPositionKey = "buffDurationBarPosition",
        durationBarDirectionKey = "buffDurationBarDirection",
        showStackKey = "buffShowStackCount",
        stackAnchorKey = "buffStackCountAnchor",
        stackSizeKey = "buffStackTextSize",
        stackXKey = "buffStackTextOffsetX",
        stackYKey = "buffStackTextOffsetY",
        cooldownSizeKey = "buffCooldownTextSize",
        cooldownAnchorKey = "buffCooldownTextAnchor",
        cooldownXKey = "buffCooldownTextOffsetX",
        cooldownYKey = "buffCooldownTextOffsetY",
        cooldownDecimalKey = "buffCooldownDecimalSeconds",
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
        swipeKey = "debuffShowCooldownSwipe",
        swipeReverseKey = "debuffCooldownSwipeReverse",
        showDurationBarKey = "debuffShowDurationBar",
        durationBarHeightKey = "debuffDurationBarHeight",
        durationBarDisplayKey = "debuffDurationBarDisplay",
        durationBarPositionKey = "debuffDurationBarPosition",
        durationBarDirectionKey = "debuffDurationBarDirection",
        showStackKey = "debuffShowStackCount",
        stackAnchorKey = "debuffStackCountAnchor",
        stackSizeKey = "debuffStackTextSize",
        stackXKey = "debuffStackTextOffsetX",
        stackYKey = "debuffStackTextOffsetY",
        cooldownSizeKey = "debuffCooldownTextSize",
        cooldownAnchorKey = "debuffCooldownTextAnchor",
        cooldownXKey = "debuffCooldownTextOffsetX",
        cooldownYKey = "debuffCooldownTextOffsetY",
        cooldownDecimalKey = "debuffCooldownDecimalSeconds",
        defaultAnchor = "TOPLEFT",
        defaultLayer = 6,
    },
}

local STYLE_LAYOUT_KEYS = {
    stackTextSize = true,
    stackTextOffsetX = true,
    stackTextOffsetY = true,
    cooldownTextSize = true,
    cooldownTextOffsetX = true,
    cooldownTextOffsetY = true,
    cooldownDecimalSeconds = true,
    durationBarHeight = true,
    buffStackTextSize = true,
    buffStackTextOffsetX = true,
    buffStackTextOffsetY = true,
    buffCooldownTextSize = true,
    buffCooldownTextOffsetX = true,
    buffCooldownTextOffsetY = true,
    buffCooldownDecimalSeconds = true,
    buffDurationBarHeight = true,
    debuffStackTextSize = true,
    debuffStackTextOffsetX = true,
    debuffStackTextOffsetY = true,
    debuffCooldownTextSize = true,
    debuffCooldownTextOffsetX = true,
    debuffCooldownTextOffsetY = true,
    debuffCooldownDecimalSeconds = true,
    debuffDurationBarHeight = true,
}

local STYLE_SHARED_LAYOUT_KEYS = {
    showTooltip = true,
    showCooldownSwipe = true,
    cooldownSwipeReverse = true,
    showDurationBar = true,
    durationBarDisplay = true,
    durationBarPosition = true,
    durationBarDirection = true,
    showCooldownText = true,
    showStackCount = true,
    debuffTypeBorderMode = true,
    useDebuffTypeBorders = true,
    buffShowCooldownSwipe = true,
    buffCooldownSwipeReverse = true,
    buffShowDurationBar = true,
    buffDurationBarDisplay = true,
    buffDurationBarPosition = true,
    buffDurationBarDirection = true,
    buffShowCooldownText = true,
    buffShowStackCount = true,
    buffStackCountAnchor = true,
    buffCooldownTextAnchor = true,
    debuffShowCooldownSwipe = true,
    debuffCooldownSwipeReverse = true,
    debuffShowDurationBar = true,
    debuffDurationBarDisplay = true,
    debuffDurationBarPosition = true,
    debuffDurationBarDirection = true,
    debuffShowCooldownText = true,
    debuffShowStackCount = true,
    debuffStackCountAnchor = true,
    debuffCooldownTextAnchor = true,
    stackCountAnchor = true,
    cooldownTextAnchor = true,
    cooldownDecimalSeconds = true,
    buffCooldownDecimalSeconds = true,
    debuffCooldownDecimalSeconds = true,
}

local GROUP_LANE_SPECS = {
    buff = {
        rootKey = "Buffs", filter = "HELPFUL",
        showKey = "showBuffs", maxKey = "maxBuffs", sizeKey = "buffIconSize",
        spacingKey = "buffSpacing", perRowKey = "buffPerRow", growthXKey = "buffGrowthX",
        growthYKey = "buffGrowthY", anchorKey = "buffAnchor", xKey = "buffOffsetX",
        yKey = "buffOffsetY", layerKey = "buffLayer", filterKey = "buffFilter",
        showTextKey = "buffShowCooldown", showStackKey = "buffShowStacks", swipeKey = "buffShowCooldownSwipe",
        swipeReverseKey = "buffCooldownSwipeReverse",
        showDurationBarKey = "buffShowDurationBar", durationBarHeightKey = "buffDurationBarHeight",
        durationBarDisplayKey = "buffDurationBarDisplay",
        durationBarPositionKey = "buffDurationBarPosition", durationBarDirectionKey = "buffDurationBarDirection",
        cooldownSizeKey = "buffCooldownSize", stackSizeKey = "buffStackSize",
        cooldownAnchorKey = "buffCooldownAnchor", cooldownXKey = "buffCooldownX",
        cooldownYKey = "buffCooldownY", stackAnchorKey = "buffStackAnchor",
        cooldownDecimalKey = "cooldownDecimalSeconds",
        stackXKey = "buffStackX", stackYKey = "buffStackY",
        defaultSize = 22, defaultMax = 4, defaultPerRow = 4, defaultAnchor = "BOTTOMRIGHT",
        defaultLayer = 5,
    },
    debuff = {
        rootKey = "Debuffs", filter = "HARMFUL",
        showKey = "showDebuffs", maxKey = "maxDebuffs", sizeKey = "debuffIconSize",
        spacingKey = "debuffSpacing", perRowKey = "debuffPerRow", growthXKey = "debuffGrowthX",
        growthYKey = "debuffGrowthY", anchorKey = "debuffAnchor", xKey = "debuffOffsetX",
        yKey = "debuffOffsetY", layerKey = "debuffLayer", filterKey = "debuffFilter",
        showTextKey = "debuffShowCooldown", showStackKey = "debuffShowStacks", swipeKey = "debuffShowCooldownSwipe",
        swipeReverseKey = "debuffCooldownSwipeReverse",
        showDurationBarKey = "debuffShowDurationBar", durationBarHeightKey = "debuffDurationBarHeight",
        durationBarDisplayKey = "debuffDurationBarDisplay",
        durationBarPositionKey = "debuffDurationBarPosition", durationBarDirectionKey = "debuffDurationBarDirection",
        cooldownSizeKey = "debuffCooldownSize", stackSizeKey = "debuffStackSize",
        cooldownAnchorKey = "debuffCooldownAnchor", cooldownXKey = "debuffCooldownX",
        cooldownYKey = "debuffCooldownY", stackAnchorKey = "debuffStackAnchor",
        cooldownDecimalKey = "cooldownDecimalSeconds",
        stackXKey = "debuffStackX", stackYKey = "debuffStackY",
        defaultSize = 20, defaultMax = 3, defaultPerRow = 3, defaultAnchor = "TOPLEFT",
        defaultLayer = 6,
    },
    external = {
        rootKey = "Externals", filter = "HELPFUL|RAID",
        showKey = "showExternals", maxKey = "maxExternals", sizeKey = "externalIconSize",
        spacingKey = "externalSpacing", perRowKey = "externalPerRow", growthXKey = "externalGrowthX",
        growthYKey = "externalGrowthY", anchorKey = "externalAnchor", xKey = "externalOffsetX",
        yKey = "externalOffsetY", layerKey = "externalLayer", filterKey = "externalFilter",
        showTextKey = "externalShowCooldown", showStackKey = "externalShowStacks", swipeKey = "externalShowCooldownSwipe",
        swipeReverseKey = "externalCooldownSwipeReverse",
        showDurationBarKey = "externalShowDurationBar", durationBarHeightKey = "externalDurationBarHeight",
        durationBarDisplayKey = "externalDurationBarDisplay",
        durationBarPositionKey = "externalDurationBarPosition", durationBarDirectionKey = "externalDurationBarDirection",
        cooldownSizeKey = "externalCooldownSize", stackSizeKey = "externalStackSize",
        cooldownAnchorKey = "externalCooldownAnchor", cooldownXKey = "externalCooldownX",
        cooldownYKey = "externalCooldownY", stackAnchorKey = "externalStackAnchor",
        stackXKey = "externalStackX", stackYKey = "externalStackY",
        defaultSize = 28, defaultMax = 2, defaultPerRow = 2, defaultAnchor = "CENTER",
        defaultLayer = 7,
    },
}

local function InCombat()
    return type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() == true
end

-- NOTE: Inbound AuraContainer/AuraButton methods (SetEnabled, SetUnit,
-- AddAuraFrame, SetIcon, ...) are secure delegates. Call them directly from
-- our code. Wrapping them does not fix forbidden table access and makes PTR
-- stack traces harder to reason about.
--
-- PTR3 exposes UpdateAllAuras() as the intended stable-token refresh hook,
-- but addon-created CustomAuraContainers still fail to refresh reliably on
-- target/focus swaps on current PTR builds. Keep the content-correct
-- ClearAuraFilters()+AddAuraFilter() path as default, coalesced by frame.
-- A3.swapUseUpdateAllAuras=true remains an opt-in A/B switch for future PTRs.

local function IsAddOnLoaded(addonName)
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        return C_AddOns.IsAddOnLoaded(addonName) == true
    end
    if type(_G.IsAddOnLoaded) == "function" then
        return _G.IsAddOnLoaded(addonName) == true
    end
    return false
end

local function EnsureBlizzardAuraContainerLoaded()
    if IsAddOnLoaded(AURA_CONTAINER_ADDON) then
        A3.nativeAuraRuntimeLoadError = nil
        return true
    end

    local loadAddOn = C_AddOns and C_AddOns.LoadAddOn or _G.LoadAddOn
    if type(loadAddOn) ~= "function" then
        A3.nativeAuraRuntimeLoadError = "LoadAddOn API is unavailable"
        return false
    end

    local loaded, reason = loadAddOn(AURA_CONTAINER_ADDON)
    if loaded == true or IsAddOnLoaded(AURA_CONTAINER_ADDON) then
        A3.nativeAuraRuntimeLoadError = nil
        return true
    end

    A3.nativeAuraRuntimeLoadError = tostring(reason or loaded or "not loaded")
    return false
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

local function NormalizeDebuffTypeBorderMode(value, fallback)
    if value == true then return "SYMBOL" end
    if value == false then return "OFF" end
    value = tostring(value or ""):upper()
    if value == "BORDER" or value == "COLOR" or value == "ON" then return "BORDER" end
    if value == "SYMBOL" or value == "BORDER_SYMBOL" or value == "BORDER_SYMBOLS"
        or value == "BORDER+SYMBOL" or value == "ICON" or value == "WITH_SYMBOL" then
        return "SYMBOL"
    end
    if value == "OFF" or value == "NONE" or value == "DISABLED" then return "OFF" end
    return fallback or "OFF"
end

local function ReadDebuffTypeBorderMode(primary, secondary)
    local mode
    if type(primary) == "table" then
        mode = primary.debuffTypeBorderMode
        if mode == nil then mode = primary.dispelBorderMode end
        if mode == nil and primary.useDebuffTypeBorders ~= nil then
            return primary.useDebuffTypeBorders == true and "SYMBOL" or "OFF"
        end
        if mode ~= nil and NormalizeDebuffTypeBorderMode(mode, "OFF") == "OFF" and primary.useDebuffTypeBorders == true then
            return "SYMBOL"
        end
    end
    if mode == nil and type(secondary) == "table" then
        mode = secondary.debuffTypeBorderMode
        if mode == nil then mode = secondary.dispelBorderMode end
        if mode == nil and secondary.useDebuffTypeBorders ~= nil then
            return secondary.useDebuffTypeBorders == true and "SYMBOL" or "OFF"
        end
        if mode ~= nil and NormalizeDebuffTypeBorderMode(mode, "OFF") == "OFF" and secondary.useDebuffTypeBorders == true then
            return "SYMBOL"
        end
    end
    return NormalizeDebuffTypeBorderMode(mode, "OFF")
end

local function ReadGroupDebuffTypeBorderMode(source)
    local mode = source and (source.debuffDispelBorderMode or source.debuffTypeBorderMode or source.dispelBorderMode)
    if mode == nil and source then
        if source.debuffShowDispelSymbol ~= nil then return source.debuffShowDispelSymbol == true and "SYMBOL" or "BORDER" end
        if source.debuffShowDispelBorder ~= nil then return source.debuffShowDispelBorder == true and "SYMBOL" or "OFF" end
        if type(source.blizzard) == "table" and source.blizzard.dispelBorder == true then return "SYMBOL" end
    end
    if source and NormalizeDebuffTypeBorderMode(mode, "OFF") == "OFF" and source.debuffShowDispelBorder == true then
        return "SYMBOL"
    end
    return NormalizeDebuffTypeBorderMode(mode, "OFF")
end

local function GetAuraBorderOptions(showIcon)
    AURA_BORDER_OPTIONS.style = nil
    AURA_BORDER_OPTIONS.showIcon = showIcon == true
    return AURA_BORDER_OPTIONS
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

local function NormalizeDurationBarPosition(value, fallback)
    value = tostring(value or fallback or "BOTTOM"):upper()
    if value == "TOP" then return "TOP" end
    return "BOTTOM"
end

local function NormalizeDurationBarDirection(value, fallback)
    value = tostring(value or fallback or "REMAINING"):upper()
    if value == "ELAPSED" or value == "ELAPSED_TIME" then return "ELAPSED" end
    return "REMAINING"
end

local function NormalizeDurationBarDisplay(value, fallback)
    value = tostring(value or fallback or "BAR_ONLY"):upper()
    if value == "ICON" or value == "ICONS" or value == "ICON_BAR" or value == "ICON+BAR" or value == "OVERLAY" then return "OVERLAY" end
    return "BAR_ONLY"
end

local function ReadDurationBarPosition(primary, secondary, key, fallback)
    return NormalizeDurationBarPosition(ReadRaw(primary, secondary, key), fallback)
end

local function ReadDurationBarDirection(primary, secondary, key, fallback)
    return NormalizeDurationBarDirection(ReadRaw(primary, secondary, key), fallback)
end

local function ReadDurationBarDisplay(primary, secondary, key, fallback)
    return NormalizeDurationBarDisplay(ReadRaw(primary, secondary, key), fallback)
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

local function TableHasAnyKey(tbl, keys)
    if type(tbl) ~= "table" or type(keys) ~= "table" then return false end
    for key in pairs(keys) do
        if tbl[key] ~= nil then return true end
    end
    return false
end

local function UnitStyleOverrideActive(unitCfg)
    if type(unitCfg) ~= "table" then return false end
    if unitCfg.overrideStyle ~= nil then return unitCfg.overrideStyle == true end
    return TableHasAnyKey(unitCfg.layout, STYLE_LAYOUT_KEYS) or TableHasAnyKey(unitCfg.layoutShared, STYLE_SHARED_LAYOUT_KEYS)
end

local function UnitLayoutValue(layout, styleKeys, styleActive, key)
    if type(layout) ~= "table" then return nil end
    local value = layout[key]
    if value ~= nil and (not styleKeys[key] or styleActive) then return value end
    return nil
end

local function EffectiveUnitTables(auras, unit)
    local shared = type(auras.shared) == "table" and auras.shared or {}
    local perUnit = type(auras.perUnit) == "table" and auras.perUnit or nil
    local unitCfg = perUnit and perUnit[unit] or nil
    local layout = unitCfg and unitCfg.overrideLayout == true and type(unitCfg.layout) == "table" and unitCfg.layout or nil
    local layoutShared = unitCfg and unitCfg.overrideSharedLayout == true and type(unitCfg.layoutShared) == "table" and unitCfg.layoutShared or nil
    local filters = unitCfg and unitCfg.overrideFilters == true and type(unitCfg.filters) == "table" and unitCfg.filters or nil
    local styleActive = UnitStyleOverrideActive(unitCfg)
    local effectiveLayout = layout and setmetatable({}, { __index = function(_, key)
        return UnitLayoutValue(layout, STYLE_LAYOUT_KEYS, styleActive, key)
    end }) or {}
    if layoutShared then
        return effectiveLayout, setmetatable({}, { __index = function(_, key)
            local value = UnitLayoutValue(layoutShared, STYLE_SHARED_LAYOUT_KEYS, styleActive, key)
            if value ~= nil then return value end
            return shared[key]
        end }), filters or shared.filters
    end
    return effectiveLayout, shared, filters or shared.filters
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
    MAW = true,
    INCLUDE_NAME_PLATE_ONLY = true,
    EXTERNAL_DEFENSIVE = true,
    CROWD_CONTROL = true,
    RAID_IN_COMBAT = true,
    RAID_PLAYER_DISPELLABLE = true,
    BIG_DEFENSIVE = true,
}

local LEGACY_NATIVE_FILTER_TOKENS = {
    ALL = false,
    DISPELLABLE = "RAID_PLAYER_DISPELLABLE",
}

local function AddNativeFilterToken(out, seen, token, baseToken)
    token = tostring(token or ""):upper():gsub("^%s+", ""):gsub("%s+$", "")
    local legacy = LEGACY_NATIVE_FILTER_TOKENS[token]
    if legacy ~= nil then
        if legacy == false then return end
        token = legacy
    end
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

local LaneTrackingSignature, LaneLayoutSignature

local function FinalizeLane(lane)
    if lane then
        lane._msufA3TrackingSignature = LaneTrackingSignature(lane)
        lane._msufA3LayoutSignature = LaneLayoutSignature(lane)
    end
    return lane
end

local function NativeFilter(baseFilter, filters)
    filters = type(filters) == "table" and filters or nil
    local filter = tostring(baseFilter or "")
    local helpful = filter:find("HELPFUL", 1, true) ~= nil
    local harmful = filter:find("HARMFUL", 1, true) ~= nil
    if filters and filters.enabled ~= false then
        if filters.onlyMine == true then filter = filter .. "|PLAYER" end
        if filters.exclusive == "raid" then filter = filter .. "|RAID" end
        if filters.raid == true then filter = filter .. "|RAID" end
        if filters.includeNameplateOnly == true then filter = filter .. "|INCLUDE_NAME_PLATE_ONLY" end
        if filters.cancelable == true and helpful then filter = filter .. "|CANCELABLE" end
        if filters.notCancelable == true and helpful then filter = filter .. "|NOT_CANCELABLE" end
        if filters.raidInCombat == true then filter = filter .. "|RAID_IN_COMBAT" end
        if filters.includeDispellable == true and harmful then filter = filter .. "|RAID_PLAYER_DISPELLABLE" end
        if filters.dispellable == true and harmful then filter = filter .. "|RAID_PLAYER_DISPELLABLE" end
        if filters.crowdControl == true and harmful then filter = filter .. "|CROWD_CONTROL" end
        if filters.externalDefensive == true and helpful then filter = filter .. "|EXTERNAL_DEFENSIVE" end
        if filters.bigDefensive == true and helpful then filter = filter .. "|BIG_DEFENSIVE" end
    end
    return NormalizeNativeFilterString(filter, baseFilter)
end

local function NormalizeDispelSensorTrigger(value, fallback)
    value = tostring(value or fallback or "BY_ME"):upper()
    if value == "BORDER" or value == "INHERIT" or value == "SAME" then return "BORDER" end
    if value == "DISPEL_TYPE" or value == "TYPE" or value == "ANY_DISPEL_TYPE" then return "DISPEL_TYPE" end
    if value == "ANY_DEBUFF" or value == "DEBUFF" or value == "ANY" or value == "ALL_DEBUFFS" then return "ANY_DEBUFF" end
    if value == "PLAYER_CAST" or value == "CAST_BY_ME" or value == "MY_DEBUFF" then return "PLAYER_CAST" end
    return "BY_ME"
end

local function DispelSensorNativeFilter(trigger)
    trigger = NormalizeDispelSensorTrigger(trigger, "BY_ME")
    if trigger == "DISPEL_TYPE" then
        -- Use the raid-filtered harmful list as the best current native path for
        -- typed/important debuffs without class-specific dispellability. Keeping
        -- the candidate window small prevents stacked full-frame borders and
        -- avoids rebuilding large hidden button pools on target swaps.
        return "HARMFUL|RAID", 3
    end
    if trigger == "PLAYER_CAST" then
        return "HARMFUL|PLAYER", 3
    end
    if trigger == "ANY_DEBUFF" then
        -- AuraButton border/symbol visibility is driven by auraData.dispelName,
        -- so true any-debuff frame highlights are not representable without an
        -- addon aura scan. Keep this secret-safe by falling back to dispellable.
        return "HARMFUL|RAID_PLAYER_DISPELLABLE", 1
    end
    return "HARMFUL|RAID_PLAYER_DISPELLABLE", 1
end

local function NormalizeDispelOverlayStyle(value)
    value = tostring(value or "FULL"):upper()
    if value == "TOP" or value == "BOTTOM" or value == "LEFT" or value == "RIGHT" then return value end
    return "FULL"
end

local function CompileCornerDispelSlots(corner)
    if not (type(corner) == "table" and corner.enabled == true and corner.needsDispel == true and type(corner.dispelSlots) == "table") then
        return nil, nil
    end
    local source = corner.dispelSlots
    local slots, parts = {}, {}
    for i = 1, #source do
        local slot = source[i]
        if type(slot) == "table" then
            local key = tostring(slot.key or i)
            local anchor = ReadAnchor(slot, nil, "anchor", "TOPLEFT")
            local x = Round(ClampNumber(slot.x, 0, -128, 128))
            local y = Round(ClampNumber(slot.y, 0, -128, 128))
            local out = { key = key, anchor = anchor, x = x, y = y }
            slots[#slots + 1] = out
            parts[#parts + 1] = key .. ":" .. anchor .. ":" .. tostring(x) .. ":" .. tostring(y)
        end
    end
    if #slots == 0 then return nil, nil end
    return slots, table_concat(parts, "|")
end

local function CompileDispelSensor(unit, frameSpec, groupMode, visual)
    if not (type(unit) == "string" and unit ~= "" and type(frameSpec) == "table") then return nil end
    local border = frameSpec.border
    local group = frameSpec.group
    local overlay = groupMode and group or frameSpec.dispelOverlay
    local corner = groupMode and frameSpec.cornerIndicators or nil
    local cornerSlots, cornerSignature = nil, nil
    if visual == "corner" then
        cornerSlots, cornerSignature = CompileCornerDispelSlots(corner)
    end
    local borderOn = border and border.dispel == true
    local overlayOn = overlay and ((groupMode and overlay.dispelOverlayEnabled == true) or (not groupMode and overlay.enabled == true))
    if visual == "border" and not borderOn then return nil end
    if visual == "overlay" and not overlayOn then return nil end
    if visual == "corner" and not cornerSlots then return nil end

    local borderTrigger = NormalizeDispelSensorTrigger(border and border.dispelTrigger, "BY_ME")
    local trigger = borderTrigger
    if visual == "overlay" then
        trigger = NormalizeDispelSensorTrigger(groupMode and overlay.dispelOverlayTrigger or overlay.trigger, "BORDER")
        if trigger == "BORDER" then trigger = borderTrigger end
    elseif visual == "corner" then
        trigger = "BY_ME"
    end

    local nativeFilter, maxCount = DispelSensorNativeFilter(trigger)
    local target = visual == "overlay" and ((groupMode and overlay.dispelOverlayOnHealth ~= false) or (not groupMode and overlay.onHealth ~= false)) and "health" or "frame"
    local cornerCount = cornerSlots and #cornerSlots or nil
    return {
        sensor = true,
        kind = visual == "corner" and "dispelCorner" or (visual == "overlay" and "dispelOverlay" or "dispelBorder"),
        rootKey = visual == "corner" and "DispelCornerSensor" or (visual == "overlay" and "DispelOverlaySensor" or "DispelBorderSensor"),
        unit = unit,
        enabled = true,
        nativeFilter = nativeFilter,
        max = cornerCount or maxCount,
        filterCount = cornerCount,
        filterMax = cornerCount and 1 or maxCount,
        visual = visual,
        target = target,
        style = visual == "overlay" and NormalizeDispelOverlayStyle(groupMode and overlay.dispelOverlayStyle or overlay.style) or "FULL",
        alpha = visual == "corner" and Clamp01(corner and corner.alpha, 1) or (visual == "overlay" and Clamp01(groupMode and overlay.dispelOverlayAlpha or overlay.alpha, 0.35) or 1),
        thickness = ClampNumber(border and border.highlightThickness, 3, 1, 32),
        size = cornerSlots and ClampNumber(corner and corner.size, 8, 1, 64) or nil,
        slots = cornerSlots,
        slotSignature = cornerSignature,
        layer = visual == "corner" and (30 + ClampNumber(corner and corner.layer, 7, 0, 30)) or (visual == "overlay" and 13 or 45),
        trigger = trigger,
    }
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
    local debuffTypeBorderMode = kind == "debuff" and ReadDebuffTypeBorderMode(layout, shared) or "OFF"
    local cooldownAnchor = ReadAnchor(shared, nil, "cooldownTextAnchor", DEFAULT_SHARED.cooldownTextAnchor)
    return FinalizeLane({
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
        showCooldownText = ReadBool(layout, shared, spec.showTextKey, ReadBool(layout, shared, "showCooldownText", true)),
        showCooldownSwipe = ReadBool(layout, shared, spec.swipeKey, ReadBool(layout, shared, "showCooldownSwipe", true)),
        cooldownSwipeReverse = ReadBool(layout, shared, spec.swipeReverseKey, ReadBool(layout, shared, "cooldownSwipeReverse", false)),
        showDurationBar = ReadBool(layout, shared, spec.showDurationBarKey, ReadBool(layout, shared, "showDurationBar", false)),
        durationBarHeight = ReadNumber(layout, shared, spec.durationBarHeightKey, ReadRaw(layout, shared, "durationBarHeight") or DEFAULT_SHARED.durationBarHeight, 1, 16),
        durationBarDisplay = ReadDurationBarDisplay(shared, nil, spec.durationBarDisplayKey, ReadRaw(shared, nil, "durationBarDisplay") or DEFAULT_SHARED.durationBarDisplay),
        durationBarPosition = ReadDurationBarPosition(shared, nil, spec.durationBarPositionKey, ReadRaw(shared, nil, "durationBarPosition") or DEFAULT_SHARED.durationBarPosition),
        durationBarDirection = ReadDurationBarDirection(shared, nil, spec.durationBarDirectionKey, ReadRaw(shared, nil, "durationBarDirection") or DEFAULT_SHARED.durationBarDirection),
        showStacks = ReadBool(layout, shared, spec.showStackKey, ReadBool(layout, shared, "showStackCount", true)),
        showTooltip = ReadBool(layout, shared, "showTooltip", DEFAULT_SHARED.showTooltip),
        showAuraBorder = debuffTypeBorderMode ~= "OFF",
        showAuraSymbol = debuffTypeBorderMode == "SYMBOL",
        cooldownSize = ReadNumber(layout, shared, spec.cooldownSizeKey, ReadRaw(shared, nil, "cooldownTextSize") or DEFAULT_SHARED.cooldownTextSize, 6, 40),
        cooldownAnchor = ReadAnchor(shared, nil, spec.cooldownAnchorKey, cooldownAnchor),
        cooldownX = ReadNumber(layout, shared, spec.cooldownXKey, ReadRaw(shared, nil, "cooldownTextOffsetX") or DEFAULT_SHARED.cooldownTextOffsetX, -2000, 2000),
        cooldownY = ReadNumber(layout, shared, spec.cooldownYKey, ReadRaw(shared, nil, "cooldownTextOffsetY") or DEFAULT_SHARED.cooldownTextOffsetY, -2000, 2000),
        cooldownDecimalSeconds = ReadNumber(layout, shared, spec.cooldownDecimalKey, ReadRaw(shared, nil, "cooldownDecimalSeconds") or DEFAULT_SHARED.cooldownDecimalSeconds, 0, 30),
        stackAnchor = ReadAnchor(shared, nil, spec.stackAnchorKey, ReadRaw(shared, nil, "stackCountAnchor") or DEFAULT_SHARED.stackCountAnchor),
        stackSize = ReadNumber(layout, shared, spec.stackSizeKey, ReadRaw(shared, nil, "stackTextSize") or DEFAULT_SHARED.stackTextSize, 6, 40),
        stackX = ReadNumber(layout, shared, spec.stackXKey, ReadRaw(shared, nil, "stackTextOffsetX") or DEFAULT_SHARED.stackTextOffsetX, -2000, 2000),
        stackY = ReadNumber(layout, shared, spec.stackYKey, ReadRaw(shared, nil, "stackTextOffsetY") or DEFAULT_SHARED.stackTextOffsetY, -2000, 2000),
    })
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
    local debuffTypeBorderMode = kind == "debuff" and ReadGroupDebuffTypeBorderMode(source) or "OFF"
    local cooldownSwipeReverse = source[spec.swipeReverseKey]
    if cooldownSwipeReverse == nil then cooldownSwipeReverse = source.cooldownSwipeReverse end
    return FinalizeLane({
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
        showCooldownSwipe = source[spec.swipeKey] ~= false,
        cooldownSwipeReverse = cooldownSwipeReverse == true,
        showDurationBar = source[spec.showDurationBarKey] == true or source.showDurationBar == true,
        durationBarHeight = ClampNumber(source[spec.durationBarHeightKey] or source.durationBarHeight, DEFAULT_SHARED.durationBarHeight, 1, 16),
        durationBarDisplay = NormalizeDurationBarDisplay(source[spec.durationBarDisplayKey] or source.durationBarDisplay, DEFAULT_SHARED.durationBarDisplay),
        durationBarPosition = NormalizeDurationBarPosition(source[spec.durationBarPositionKey] or source.durationBarPosition, DEFAULT_SHARED.durationBarPosition),
        durationBarDirection = NormalizeDurationBarDirection(source[spec.durationBarDirectionKey] or source.durationBarDirection, DEFAULT_SHARED.durationBarDirection),
        showStacks = source[spec.showStackKey] ~= false,
        showTooltip = source.showTooltip ~= false,
        showAuraBorder = debuffTypeBorderMode ~= "OFF",
        showAuraSymbol = debuffTypeBorderMode == "SYMBOL",
        cooldownSize = ClampNumber(source[spec.cooldownSizeKey] or source.cooldownSize, DEFAULT_SHARED.cooldownTextSize, 6, 40),
        cooldownAnchor = ReadAnchor(source, nil, spec.cooldownAnchorKey, "CENTER"),
        cooldownX = ClampNumber(source[spec.cooldownXKey] or source.cooldownX, 0, -2000, 2000),
        cooldownY = ClampNumber(source[spec.cooldownYKey] or source.cooldownY, 0, -2000, 2000),
        cooldownDecimalSeconds = ClampNumber(source[spec.cooldownDecimalKey] or source.cooldownDecimalSeconds, DEFAULT_SHARED.cooldownDecimalSeconds, 0, 30),
        stackAnchor = ReadAnchor(source, nil, spec.stackAnchorKey, "BOTTOMRIGHT"),
        stackSize = ClampNumber(source[spec.stackSizeKey] or source.stackSize, DEFAULT_SHARED.stackTextSize, 6, 40),
        stackX = ClampNumber(source[spec.stackXKey] or source.stackX, 0, -2000, 2000),
        stackY = ClampNumber(source[spec.stackYKey] or source.stackY, 0, -2000, 2000),
    })
end

local function InvalidateUnitRuntimeConfig(unit)
    unit = NormalizeRuntimeUnit(unit)
    if not unit then return nil end
    local runtimeCache = A3._runtimeConfigCache
    if runtimeCache then runtimeCache[unit] = nil end
    return unit
end

local function BuildUnitFrameConfig(unit, frameSpec)
    unit = NormalizeRuntimeUnit(unit)
    if not unit then return nil end
    local auras, shared = EnsureDB()
    local iconsEnabled = UnitAuraIconsEnabled(auras, unit)
    local dispelBorder = CompileDispelSensor(unit, frameSpec, false, "border")
    local dispelOverlay = CompileDispelSensor(unit, frameSpec, false, "overlay")
    if not iconsEnabled then
        return {
            unit = unit,
            enabled = (dispelBorder and dispelBorder.enabled == true) or (dispelOverlay and dispelOverlay.enabled == true),
            lanes = {},
            sensors = { dispelBorder = dispelBorder, dispelOverlay = dispelOverlay },
            group = false,
            _msufA3ConfigGen = A3._runtimeConfigGen or 1,
            _msufA3VisualGen = A3._nativeVisualGen or 0,
        }
    end
    local layout, sharedLayout, filtersRoot = EffectiveUnitTables(auras, unit)
    local buff = CompileUnitLane(unit, sharedLayout, layout, filtersRoot, "buff")
    local debuff = CompileUnitLane(unit, sharedLayout, layout, filtersRoot, "debuff")
    return {
        unit = unit,
        enabled = (buff and buff.enabled == true) or (debuff and debuff.enabled == true)
            or (dispelBorder and dispelBorder.enabled == true) or (dispelOverlay and dispelOverlay.enabled == true),
        lanes = { buff = buff, debuff = debuff },
        sensors = { dispelBorder = dispelBorder, dispelOverlay = dispelOverlay },
        group = false,
        _msufA3ConfigGen = A3._runtimeConfigGen or 1,
        _msufA3VisualGen = A3._nativeVisualGen or 0,
    }
end

function A3.ResolveUnitFrameConfig(unit, frameSpec)
    unit = NormalizeRuntimeUnit(unit)
    if not unit then return nil end
    local gen = A3._runtimeConfigGen or 1
    local visualGen = A3._nativeVisualGen or 0
    if frameSpec ~= nil then
        -- Frame-spec configs also consume UnitFrame border/overlay settings.
        -- Those are cold-path spec data and can change without touching the
        -- Auras DB generation, so rebuild them from the current spec.
        return BuildUnitFrameConfig(unit, frameSpec)
    end
    A3._runtimeConfigCache = A3._runtimeConfigCache or {}
    local cached = A3._runtimeConfigCache[unit]
    if cached and cached.gen == gen and cached.visualGen == visualGen then return cached.config end
    local cfg = BuildUnitFrameConfig(unit, nil)
    A3._runtimeConfigCache[unit] = { gen = gen, visualGen = visualGen, config = cfg }
    return cfg
end

local function ResolveGroupFrameConfig(frame, unit)
    if not frame then return nil end
    unit = unit or frame.unit
    local spec = frame.MSUFSpec
    local source = spec and (spec.auras or (spec.group and spec.group.auras))
    local gen = A3._runtimeConfigGen or 1
    local visualGen = A3._nativeVisualGen or 0
    local cached = frame._msufA3NativeGroupConfig
    if cached and frame._msufA3NativeGroupSource == source and frame._msufA3NativeGroupUnit == unit
        and frame._msufA3NativeGroupGen == gen and frame._msufA3NativeGroupVisualGen == visualGen then
        return cached
    end
    local cfg = {
        unit = unit,
        enabled = false,
        lanes = {},
        sensors = {},
        group = true,
        _msufA3ConfigGen = gen,
        _msufA3VisualGen = visualGen,
        _msufA3Source = source,
    }
    if type(source) == "table" and type(unit) == "string" and unit ~= "" and source.enabled ~= false then
        local buff = CompileGroupLane(unit, source, "buff")
        local debuff = CompileGroupLane(unit, source, "debuff")
        local external = CompileGroupLane(unit, source, "external")
        cfg.lanes.buff = buff
        cfg.lanes.debuff = debuff
        cfg.lanes.external = external
        cfg.enabled = (buff and buff.enabled == true) or (debuff and debuff.enabled == true) or (external and external.enabled == true)
    end
    if type(unit) == "string" and unit ~= "" then
        local dispelBorder = CompileDispelSensor(unit, spec, true, "border")
        local dispelOverlay = CompileDispelSensor(unit, spec, true, "overlay")
        local dispelCorner = CompileDispelSensor(unit, spec, true, "corner")
        cfg.sensors.dispelBorder = dispelBorder
        cfg.sensors.dispelOverlay = dispelOverlay
        cfg.sensors.dispelCorner = dispelCorner
        cfg.enabled = cfg.enabled == true
            or (dispelBorder and dispelBorder.enabled == true)
            or (dispelOverlay and dispelOverlay.enabled == true)
            or (dispelCorner and dispelCorner.enabled == true)
    end
    frame._msufA3NativeGroupSource = source
    frame._msufA3NativeGroupUnit = unit
    frame._msufA3NativeGroupGen = gen
    frame._msufA3NativeGroupVisualGen = visualGen
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

-- Aura timer text format/color: C-side formatter objects evaluated by
-- Blizzard's DurationTextBinding against the secret aura duration object. MSUF
-- only builds/caches formatter objects when style config changes; there is no
-- addon timer or OnUpdate work per aura.
local _durationFormatterCache

local function NumericRuleFormatRounding(name, fallback)
    local enum = _G.Enum and _G.Enum.NumericRuleFormatRounding
    if enum and enum[name] ~= nil then return enum[name] end
    local numericRuleFormatter = _G.NumericRuleFormatter and _G.NumericRuleFormatter.Rounding
    if numericRuleFormatter and numericRuleFormatter[name] ~= nil then return numericRuleFormatter[name] end
    return fallback
end

local function ColorEscape(r, g, b)
    return string.format("|cff%02x%02x%02x", Round(Clamp01(r, 1) * 255), Round(Clamp01(g, 1) * 255), Round(Clamp01(b, 1) * 255))
end

local AURA_TIMER_MINUTE_SUFFIX_KEY = "MSUF_AURA_TIMER_MINUTE_SUFFIX"

local function EscapeFormatLiteral(text)
    return tostring(text or ""):gsub("%%", "%%%%")
end

local function LocalizedMinuteSuffix()
    local suffix
    if type(MSUF.Translate) == "function" then
        suffix = MSUF.Translate(AURA_TIMER_MINUTE_SUFFIX_KEY)
        if suffix == AURA_TIMER_MINUTE_SUFFIX_KEY then suffix = nil end
    end
    if suffix == nil or suffix == "" then suffix = "M" end
    return tostring(suffix)
end

local function BuildAuraDurationFormatter(lane)
    local general = (_G.MSUF_DB and _G.MSUF_DB.general) or nil
    if not general then return nil end
    local buckets = general.aurasCooldownTextUseBuckets == true
    local decimalSec = ClampNumber(lane and lane.cooldownDecimalSeconds, DEFAULT_SHARED.cooldownDecimalSeconds, 0, 30)

    local C_StringUtil = _G.C_StringUtil
    if not (C_StringUtil and type(C_StringUtil.CreateNumericRuleFormatter) == "function") then return nil end

    -- Safe color falls back to the configured global font color when the user has
    -- not picked one, matching the menu's Safe swatch behavior.
    local safe = general.aurasCooldownTextSafeColor
    local sr, sg, sb
    if type(safe) == "table" then
        sr, sg, sb = safe[1] or safe.r, safe[2] or safe.g, safe[3] or safe.b
    elseif type(_G.MSUF_GetConfiguredFontColor) == "function" then
        sr, sg, sb = _G.MSUF_GetConfiguredFontColor()
    end
    sr, sg, sb = Clamp01(sr, 1), Clamp01(sg, 1), Clamp01(sb, 1)

    local warn = general.aurasCooldownTextWarningColor
    local wr, wg, wb = 1, 0.85, 0.20
    if type(warn) == "table" then wr, wg, wb = warn[1] or warn.r or wr, warn[2] or warn.g or wg, warn[3] or warn.b or wb end

    local urgent = general.aurasCooldownTextUrgentColor
    local ur, ug, ub = 1, 0.55, 0.10
    if type(urgent) == "table" then ur, ug, ub = urgent[1] or urgent.r or ur, urgent[2] or urgent.g or ug, urgent[3] or urgent.b or ub end

    -- Three boundaries in seconds, ascending: Urgent < Warning < Safe. A breakpoint's
    -- threshold is the minimum input value it applies to; the highest threshold
    -- <= remaining seconds wins. Above the Safe boundary we emit no color escape so
    -- the text keeps its base font color (the fontstring's own SetTextColor).
    local urgentSec = ClampNumber(general.aurasCooldownTextUrgentSeconds, 5, 0, 600)
    local warningSec = ClampNumber(general.aurasCooldownTextWarningSeconds, 15, 0, 600)
    local safeSec = ClampNumber(general.aurasCooldownTextSafeSeconds, 60, 0, 600)
    if warningSec < urgentSec then warningSec = urgentSec end
    if safeSec < warningSec then safeSec = warningSec end

    local minuteSuffix = LocalizedMinuteSuffix()
    local minuteFormatSuffix = EscapeFormatLiteral(minuteSuffix)
    local sig = table_concat({
        "minutes-suffix-color", buckets and 1 or 0, decimalSec, minuteSuffix, sr, sg, sb, wr, wg, wb, ur, ug, ub, urgentSec, warningSec, safeSec,
    }, "\030")
    if _durationFormatterCache and _durationFormatterCache[sig] then return _durationFormatterCache[sig] end

    local roundingDown = NumericRuleFormatRounding("Down", 2)
    local thresholds, seen = {}, {}
    local function AddThreshold(value)
        value = ClampNumber(value, 0, 0, 600)
        if seen[value] then return end
        seen[value] = true
        thresholds[#thresholds + 1] = value
    end
    AddThreshold(0)
    if decimalSec > 0 then AddThreshold(decimalSec) end
    AddThreshold(60)
    if buckets then
        AddThreshold(urgentSec)
        AddThreshold(warningSec)
        AddThreshold(safeSec)
    end
    table_sort(thresholds)

    local function ColorPrefix(threshold)
        if not buckets then return "" end
        if safeSec > warningSec and threshold >= safeSec then return "" end
        if threshold >= warningSec then return ColorEscape(sr, sg, sb) end
        if threshold >= urgentSec then return ColorEscape(wr, wg, wb) end
        return ColorEscape(ur, ug, ub)
    end
    local function BreakpointAt(threshold)
        local colorPrefix = ColorPrefix(threshold)
        local colorSuffix = colorPrefix ~= "" and "|r" or ""
        if threshold >= 60 then
            return {
                threshold = threshold,
                step = 1,
                rounding = roundingDown,
                min = 1,
                format = colorPrefix .. "%.0f" .. minuteFormatSuffix .. colorSuffix,
                components = {
                    { div = 60, step = 1, rounding = roundingDown },
                },
            }
        end
        local decimalBreakpoint = threshold < decimalSec
        return {
            threshold = threshold,
            step = decimalBreakpoint and 0.1 or 1,
            rounding = roundingDown,
            -- Blizzard's native duration binding defaults missing minima to 1.
            -- Decimal aura timers must be allowed below one second.
            min = decimalBreakpoint and 0.1 or 1,
            format = colorPrefix .. (decimalBreakpoint and "%.1f" or "%.0f") .. colorSuffix,
        }
    end

    local formatter = C_StringUtil.CreateNumericRuleFormatter()
    for i = 1, #thresholds do
        formatter:AddBreakpoint(BreakpointAt(thresholds[i]))
    end

    _durationFormatterCache = _durationFormatterCache or {}
    _durationFormatterCache[sig] = formatter
    return formatter
end

-- Reusable options table for SetDurationText. Blizzard securecopies options on
-- each call, so a single mutated table is safe across buttons and avoids per-button
-- garbage; we only ever set cold-path formatter references on it.
local _durationTextOptions = {}
local _durationBarOptions = {}
local RegisterNativeContainer

local function PlaceStackText(fs, owner, lane)
    if not (fs and owner and lane) then return end
    fs:ClearAllPoints()
    local anchor = lane.stackAnchor or "TOPRIGHT"
    local x, y = lane.stackX or -1, lane.stackY or 1
    if anchor == "TOPLEFT" or anchor == "LEFT" then
        fs:SetPoint(anchor, owner, anchor, x, y)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV(anchor == "LEFT" and "MIDDLE" or "TOP")
    elseif anchor == "BOTTOMLEFT" then
        fs:SetPoint(anchor, owner, anchor, x, y)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("BOTTOM")
    elseif anchor == "BOTTOMRIGHT" then
        fs:SetPoint(anchor, owner, anchor, x, y)
        fs:SetJustifyH("RIGHT")
        fs:SetJustifyV("BOTTOM")
    elseif anchor == "CENTER" or anchor == "TOP" or anchor == "BOTTOM" then
        fs:SetPoint(anchor, owner, anchor, x, y)
        fs:SetJustifyH("CENTER")
        fs:SetJustifyV(anchor == "TOP" and "TOP" or (anchor == "BOTTOM" and "BOTTOM" or "MIDDLE"))
    elseif anchor == "RIGHT" then
        fs:SetPoint(anchor, owner, anchor, x, y)
        fs:SetJustifyH("RIGHT")
        fs:SetJustifyV("MIDDLE")
    else
        fs:SetPoint("TOPRIGHT", owner, "TOPRIGHT", x, y)
        fs:SetJustifyH("RIGHT")
        fs:SetJustifyV("TOP")
    end
end

local function PlaceCooldownText(fs, owner, lane)
    if not (fs and owner and lane) then return end
    fs:ClearAllPoints()
    local anchor = lane.cooldownAnchor or "CENTER"
    local x, y = lane.cooldownX or 0, lane.cooldownY or 0
    fs:SetPoint(anchor, owner, anchor, x, y)
    if anchor == "TOPLEFT" or anchor == "LEFT" or anchor == "BOTTOMLEFT" then
        fs:SetJustifyH("LEFT")
    elseif anchor == "TOPRIGHT" or anchor == "RIGHT" or anchor == "BOTTOMRIGHT" then
        fs:SetJustifyH("RIGHT")
    else
        fs:SetJustifyH("CENTER")
    end
    if anchor == "TOPLEFT" or anchor == "TOP" or anchor == "TOPRIGHT" then
        fs:SetJustifyV("TOP")
    elseif anchor == "BOTTOMLEFT" or anchor == "BOTTOM" or anchor == "BOTTOMRIGHT" then
        fs:SetJustifyV("BOTTOM")
    else
        fs:SetJustifyV("MIDDLE")
    end
end

local function CallButtonMethod(button, methodName, ...)
    local method = button and button[methodName]
    if type(method) ~= "function" then return false end
    method(button, ...)
    return true
end

local function EnsureRoot(frame)
    if not frame then return nil end
    local root = frame.Auras
    if root and root._msufA3NativeRoot == true then return root end
    root = CreateFrame("Frame", nil, frame)
    root._msufA3NativeRoot = true
    root:SetAllPoints(frame)
    root:SetScript("OnShow", function(self)
        -- Re-show needs a content reparse: while hidden the container is
        -- unregistered from UNIT_AURA, so it missed any aura changes.
        if RefreshAppliedNativeRoot then RefreshAppliedNativeRoot(self, true) end
    end)
    root:Hide()
    frame.Auras = root
    return root
end

local function ConfigGen(cfg)
    return cfg and cfg._msufA3ConfigGen or (A3._runtimeConfigGen or 1)
end

local function VisualGen(cfg)
    return cfg and cfg._msufA3VisualGen or (A3._nativeVisualGen or 0)
end

local function ReasonRequiresAuraApply(reason)
    if reason == nil then return true end
    if IDENTITY_AURA_REFRESH_REASONS[reason] == true then return true end
    if COLD_APPLY_REASONS[reason] == true then return true end
    reason = tostring(reason or "")
    return reason:find("^AURAS3_", 1, false) ~= nil
        or reason:find("^MSUF2_", 1, false) ~= nil
        or reason:find("^MSUF_ASSISTANT_", 1, false) ~= nil
end

local function RootAppliedConfigIsCurrent(root, frame, cfg, reason)
    if not (root and root._msufA3NativeRoot == true and root._msufA3Applied == true) then return false end
    if root.needFullUpdate == true then return false end
    if ReasonRequiresAuraApply(reason) and not (reason == nil and cfg and root._msufA3Config == cfg) then return false end
    if cfg and root._msufA3Config ~= cfg then return false end
    if root._msufA3ConfigGen ~= (cfg and ConfigGen(cfg) or (A3._runtimeConfigGen or 1)) then return false end
    if root._msufA3VisualGen ~= (cfg and VisualGen(cfg) or (A3._nativeVisualGen or 0)) then return false end
    if root._msufA3AppliedUnit ~= (cfg and cfg.unit or (frame and frame.unit)) then return false end
    if root._msufA3FrameSpec ~= (frame and frame.MSUFSpec) then return false end
    return true
end

local function FrameAppliedConfigIsCurrent(frame, reason)
    if not frame then return false end
    return RootAppliedConfigIsCurrent(frame.Auras, frame, nil, reason)
end

LaneTrackingSignature = function(lane)
    return tostring(lane.unit) .. "\030" .. tostring(lane.kind) .. "\030" .. tostring(lane.nativeFilter)
        .. "\030" .. tostring(lane.max)
end

LaneLayoutSignature = function(lane)
    return tostring(lane.size) .. "\030" .. tostring(lane.spacing)
        .. "\030" .. tostring(lane.step) .. "\030" .. tostring(lane.perRow)
        .. "\030" .. tostring(lane.cols) .. "\030" .. tostring(lane.rows)
        .. "\030" .. tostring(lane.width) .. "\030" .. tostring(lane.height)
        .. "\030" .. tostring(lane.anchor) .. "\030" .. tostring(lane.x)
        .. "\030" .. tostring(lane.y) .. "\030" .. tostring(lane.layer)
        .. "\030" .. tostring(lane.xSign) .. "\030" .. tostring(lane.ySign)
        .. "\030" .. tostring(lane.verticalGrowth) .. "\030" .. tostring(lane.initialAnchor)
        .. "\030" .. tostring(lane.showCooldownText) .. "\030" .. tostring(lane.showCooldownSwipe)
        .. "\030" .. tostring(lane.cooldownSwipeReverse) .. "\030" .. tostring(lane.cooldownSize)
        .. "\030" .. tostring(lane.cooldownAnchor) .. "\030" .. tostring(lane.cooldownX)
        .. "\030" .. tostring(lane.cooldownY) .. "\030" .. tostring(lane.cooldownDecimalSeconds)
        .. "\030" .. tostring(lane.showDurationBar) .. "\030" .. tostring(lane.durationBarHeight)
        .. "\030" .. tostring(lane.durationBarDisplay) .. "\030" .. tostring(lane.durationBarPosition)
        .. "\030" .. tostring(lane.durationBarDirection)
        .. "\030" .. tostring(lane.showStacks) .. "\030" .. tostring(lane.stackAnchor)
        .. "\030" .. tostring(lane.stackSize) .. "\030" .. tostring(lane.stackX)
        .. "\030" .. tostring(lane.stackY) .. "\030" .. tostring(lane.showTooltip)
        .. "\030" .. tostring(lane.showAuraBorder) .. "\030" .. tostring(lane.showAuraSymbol)
        .. "\030" .. tostring(lane.alpha) .. "\030" .. tostring(A3._nativeVisualGen or 0)
end

local function SensorTrackingSignature(sensor)
    return tostring(sensor.unit) .. "\030" .. tostring(sensor.kind) .. "\030" .. tostring(sensor.nativeFilter)
        .. "\030" .. tostring(sensor.max) .. "\030" .. tostring(sensor.filterCount) .. "\030" .. tostring(sensor.filterMax)
end

local function SensorLayoutSignature(sensor)
    return tostring(sensor.visual) .. "\030" .. tostring(sensor.target)
        .. "\030" .. tostring(sensor.style) .. "\030" .. tostring(sensor.alpha)
        .. "\030" .. tostring(sensor.thickness) .. "\030" .. tostring(sensor.layer)
        .. "\030" .. tostring(sensor.size) .. "\030" .. tostring(sensor.slotSignature)
        .. "\030" .. tostring(sensor.trigger) .. "\030" .. tostring(A3._nativeVisualGen or 0)
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

local function LayoutAuraBorder(button, border, lane)
    local size = tonumber(lane and lane.size) or DEFAULT_SHARED.iconSize
    local pad = math_max(1, math_floor((size / 24) + 0.5))
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", button, "TOPLEFT", -pad, pad)
    border:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", pad, -pad)
end

local function LayoutDurationBar(button, bar, lane)
    if not (button and bar and lane) then return end
    local height = ClampNumber(lane.durationBarHeight, DEFAULT_SHARED.durationBarHeight, 1, math_max(1, lane.size or DEFAULT_SHARED.iconSize))
    local inset = math_max(1, math_floor(((lane.size or DEFAULT_SHARED.iconSize) / 32) + 0.5))
    bar:ClearAllPoints()
    bar:SetHeight(height)
    if lane.durationBarPosition == "TOP" then
        bar:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
        bar:SetPoint("TOPRIGHT", button, "TOPRIGHT", -inset, -inset)
    else
        bar:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", inset, inset)
        bar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
    end
end

local function ResolveDurationBarOptions(lane)
    local enum = _G.Enum
    local interpolation = enum and enum.StatusBarInterpolation
    local direction = enum and enum.StatusBarTimerDirection
    _durationBarOptions.interpolation = interpolation and interpolation.Immediate or nil
    if lane and lane.durationBarDirection == "ELAPSED" then
        _durationBarOptions.direction = direction and direction.ElapsedTime or nil
    else
        _durationBarOptions.direction = direction and direction.RemainingTime or nil
    end
    return _durationBarOptions
end

local function ApplyDurationBarColor(bar)
    if not bar then return end
    local general = (_G.MSUF_DB and _G.MSUF_DB.general) or nil
    local color = general and general.aurasCooldownTextSafeColor
    local r, g, b = 0.08, 0.78, 1.00
    if type(color) == "table" then
        r, g, b = color[1] or color.r or r, color[2] or color.g or g, color[3] or color.b or b
    end
    if bar.SetStatusBarColor then bar:SetStatusBarColor(Clamp01(r, 1), Clamp01(g, 1), Clamp01(b, 1), 0.95) end
end

local function SyncButtonGeometry(button, lane, index)
    if not (button and lane) then return false end
    LayoutButton(button, lane, index)
    if button.Icon then
        button.Icon:ClearAllPoints()
        button.Icon:SetAllPoints(button)
    end
    if button._msufA3Cooldown then
        button._msufA3Cooldown:ClearAllPoints()
        button._msufA3Cooldown:SetAllPoints(button)
    end
    if button._msufA3AuraBorder then
        LayoutAuraBorder(button, button._msufA3AuraBorder, lane)
    end
    if button._msufA3DurationBar then
        LayoutDurationBar(button, button._msufA3DurationBar, lane)
    end
    return true
end

local function SyncContainerGeometry(container, lane, parentFrame)
    if not (container and lane) then return false end
    parentFrame = parentFrame or container._msufA3ParentFrame or container:GetParent()
    container._msufA3NativeLaneConfig = lane
    container._msufA3ParentFrame = parentFrame
    -- Geometry depends only on the lane's layout signature (size/spacing/anchor/
    -- offsets/level/growth/visual gen) and the parent frame. Content-only
    -- refreshes -- swaps, identity, UNIT_AURA -- reuse the same lane, so skip the
    -- container resize + per-button re-layout when nothing geometric changed. A
    -- changed icon count or filter alters the tracking signature instead, which
    -- recreates the container, so a stale skip here is not possible.
    local sig = lane._msufA3LayoutSignature
    if sig ~= nil and container._msufA3GeomSig == sig and container._msufA3GeomParent == parentFrame then
        return true
    end
    container._msufA3GeomSig = sig
    container._msufA3GeomParent = parentFrame
    container.createdButtons = lane.max
    container:SetSize(lane.width, lane.height)
    if parentFrame then
        container:ClearAllPoints()
        container:SetPoint(lane.anchor, parentFrame, lane.anchor, lane.x, lane.y)
    end
    container:SetAlpha(lane.alpha or 1)
    if parentFrame then
        container:SetFrameLevel((parentFrame:GetFrameLevel() or 0) + (lane.layer or 1))
    end
    for i = 1, (container.createdButtons or lane.max or 0) do
        SyncButtonGeometry(container[i], lane, i)
    end
    return true
end

local function PrepareAuraButton(button, lane, index)
    button._msufA3NativeButton = true
    button._msufA3LaneKind = lane.kind
    button:SetSize(lane.size, lane.size)
    button:SetFrameLevel((button:GetParent():GetFrameLevel() or 0) + 1)

    local barOnly = lane.showDurationBar == true and lane.durationBarDisplay == "BAR_ONLY"
    local icon = button.Icon
    if barOnly then
        CallButtonMethod(button, "ClearIcon")
        if icon then
            icon:SetAlpha(0)
            icon:Hide()
        end
    else
        if not icon then
            icon = button:CreateTexture(nil, "ARTWORK")
            button.Icon = icon
        end
        icon:ClearAllPoints()
        icon:SetAllPoints(button)
        icon:SetAlpha(1)
        icon:Show()
        CallButtonMethod(button, "SetIcon", icon)
    end

    -- Native cooldown swipe. Blizzard's ApplyDurationCooldown drives this from
    -- the (secret) aura duration C-side, so there is no addon timer cost.
    --
    -- Use CooldownFrameTemplate for the actual swipe art, then immediately opt
    -- out of countdown numbers, bling, and edge drawing. Created once per button
    -- and reused.
    if lane.showCooldownSwipe == true and not barOnly then
        local cooldown = button._msufA3Cooldown
        if not cooldown then
            local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
            cd:SetAllPoints(button)
            if type(cd.SetDrawSwipe) == "function" then cd:SetDrawSwipe(true) end
            if type(cd.SetHideCountdownNumbers) == "function" then cd:SetHideCountdownNumbers(true) end
            if type(cd.SetDrawBling) == "function" then cd:SetDrawBling(false) end
            if type(cd.SetDrawEdge) == "function" then cd:SetDrawEdge(false) end
            button._msufA3Cooldown = cd
            cooldown = cd
        end
        if cooldown then
            if type(cooldown.SetReverse) == "function" then cooldown:SetReverse(lane.cooldownSwipeReverse == true) end
            cooldown:Show()
            CallButtonMethod(button, "SetDurationCooldown", cooldown)
        end
    else
        CallButtonMethod(button, "ClearDurationCooldown")
        if button._msufA3Cooldown then button._msufA3Cooldown:Hide() end
    end

    if lane.showDurationBar == true then
        local bar = button._msufA3DurationBar
        if not bar then
            bar = CreateFrame("StatusBar", nil, button)
            bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(0)
            button._msufA3DurationBar = bar
        end
        if type(bar.SetFrameLevel) == "function" then bar:SetFrameLevel((button:GetFrameLevel() or 0) + 2) end
        LayoutDurationBar(button, bar, lane)
        ApplyDurationBarColor(bar)
        if CallButtonMethod(button, "SetDurationBar", bar, ResolveDurationBarOptions(lane)) then
            bar:Show()
        else
            bar:Hide()
        end
    else
        CallButtonMethod(button, "ClearDurationBar")
        if button._msufA3DurationBar then button._msufA3DurationBar:Hide() end
    end

    local duration = button.Text or button.DurationText
    if not duration then
        duration = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        button.Text = duration
    end
    duration:Hide()
    if lane.showCooldownText == true then
        ApplyFont(duration, lane.cooldownSize)
        PlaceCooldownText(duration, button, lane)
        duration:Show()
        -- Hand Blizzard a C-side formatter so the duration text is
        -- formatted from the secret duration object with no addon cost. MSUF caps
        -- long buffs at localized whole minutes instead of raw seconds or
        -- hour/day units.
        local formatter = BuildAuraDurationFormatter(lane)
        if formatter then
            _durationTextOptions.formatter = formatter
            CallButtonMethod(button, "SetDurationText", duration, _durationTextOptions)
            _durationTextOptions.formatter = nil
        else
            _durationTextOptions.formatter = nil
            CallButtonMethod(button, "SetDurationText", duration)
        end
    else
        CallButtonMethod(button, "ClearDurationText")
    end

    local count = button._msufA3ApplicationCount or button.Count or button.ApplicationCount
    if not count then
        count = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        button._msufA3ApplicationCount = count
    end
    button.Count = count
    count:Hide()
    if lane.showStacks == true then
        ApplyFont(count, lane.stackSize)
        PlaceStackText(count, button, lane)
        count:Show()
        CallButtonMethod(button, "SetApplicationCount", count, {})
    else
        CallButtonMethod(button, "ClearApplicationCount")
    end

    local auraBorderBound = false
    if lane.showAuraBorder == true and not barOnly then
        local border = button._msufA3AuraBorder or button.AuraBorder or button.Border
        if not border then
            border = button:CreateTexture(nil, "OVERLAY")
        end
        LayoutAuraBorder(button, border, lane)
        button._msufA3AuraBorder = border
        auraBorderBound = CallButtonMethod(button, "SetAuraBorder", border, GetAuraBorderOptions(lane.showAuraSymbol))
    else
        CallButtonMethod(button, "ClearAuraBorder")
        if button._msufA3AuraBorder and button._msufA3AuraBorder.Hide then button._msufA3AuraBorder:Hide() end
    end

    if lane.showAuraSymbol == true and auraBorderBound == true and not barOnly then
        local symbol = button._msufA3AuraSymbol or button.AuraSymbol or button.Symbol
        if not symbol then
            symbol = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        end
        button._msufA3AuraSymbol = symbol
        button.Symbol = symbol
        symbol:ClearAllPoints()
        symbol:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        symbol:SetJustifyH("RIGHT")
        symbol:SetJustifyV("BOTTOM")
        ApplyFont(symbol, math_min(lane.stackSize or DEFAULT_SHARED.stackTextSize, 14))
        CallButtonMethod(button, "SetAuraSymbol", symbol, { showWhenHarmful = true, showWhenHelpful = false })
    else
        CallButtonMethod(button, "ClearAuraSymbol")
        if button._msufA3AuraSymbol and button._msufA3AuraSymbol.Hide then button._msufA3AuraSymbol:Hide() end
    end

    CallButtonMethod(button, "SetMouseMotionEnabled", lane.showTooltip ~= false)

    SyncButtonGeometry(button, lane, index)
end

local function DispelSensorTarget(parentFrame, sensor)
    if sensor and sensor.target == "health" and parentFrame then
        return parentFrame.hpBar or parentFrame.Health or parentFrame.health or parentFrame
    end
    return parentFrame
end

local function LayoutDispelSensorButton(button, sensor, parentFrame, index)
    if not (button and sensor and parentFrame) then return false end
    local target = DispelSensorTarget(parentFrame, sensor) or parentFrame
    button:ClearAllPoints()
    if sensor.visual == "corner" then
        local slot = sensor.slots and sensor.slots[index or 1]
        if not slot then return false end
        local size = ClampNumber(sensor.size, 8, 1, 64)
        button:SetSize(size, size)
        button:SetPoint(slot.anchor or "TOPLEFT", target, slot.anchor or "TOPLEFT", slot.x or 0, slot.y or 0)
    else
        button:SetAllPoints(target)
    end
    if button.SetFrameLevel then button:SetFrameLevel((parentFrame:GetFrameLevel() or 0) + (sensor.layer or 14)) end
    return true
end

local function LayoutDispelSensorOverlay(region, button, sensor)
    if not (region and button and sensor) then return end
    local style = sensor.style or "FULL"
    local thickness = ClampNumber(sensor.thickness, 3, 1, 32)
    region:ClearAllPoints()
    if sensor.visual == "corner" then
        region:SetAllPoints(button)
        return
    end
    if sensor.visual == "border" then
        local pad = math_min(2, math_max(0, math_floor((thickness * 0.5) + 0.5)))
        region:SetPoint("TOPLEFT", button, "TOPLEFT", -pad, pad)
        region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", pad, -pad)
        return
    end
    if style == "TOP" then
        region:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        region:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
        region:SetHeight(thickness)
    elseif style == "BOTTOM" then
        region:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
        region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
        region:SetHeight(thickness)
    elseif style == "LEFT" then
        region:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        region:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
        region:SetWidth(thickness)
    elseif style == "RIGHT" then
        region:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
        region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
        region:SetWidth(thickness)
    else
        region:SetAllPoints(button)
    end
end

local function GetSensorOverlayOptions()
    local styles = _G.AuraButtonBorderStyle
    AURA_SENSOR_OVERLAY_OPTIONS.style = styles and styles.Color or 1
    return AURA_SENSOR_OVERLAY_OPTIONS
end

local function GetSensorBorderOptions()
    local styles = _G.AuraButtonBorderStyle
    AURA_SENSOR_BORDER_OPTIONS.style = styles and styles.Color or 1
    return AURA_SENSOR_BORDER_OPTIONS
end

local SENSOR_FILTER_OPTIONS = {}
local function AddDispelSensorAuraFilters(container, sensor)
    if not (container and sensor and sensor.nativeFilter) then return false end
    local count = math_floor((tonumber(sensor.filterCount) or 1) + 0.5)
    if count < 1 then count = 1 end
    SENSOR_FILTER_OPTIONS.maxFrameCount = math_floor((tonumber(sensor.filterMax) or tonumber(sensor.max) or 1) + 0.5)
    if SENSOR_FILTER_OPTIONS.maxFrameCount < 1 then SENSOR_FILTER_OPTIONS.maxFrameCount = 1 end
    for _ = 1, count do
        container:AddAuraFilter(sensor.nativeFilter, SENSOR_FILTER_OPTIONS)
    end
    return true
end

local function PrepareDispelSensorButton(button, sensor, parentFrame, index)
    if not (button and sensor and parentFrame) then return false end
    button._msufA3NativeButton = true
    button._msufA3DispelSensor = sensor.visual
    if button.EnableMouse then button:EnableMouse(false) end
    CallButtonMethod(button, "SetMouseMotionEnabled", false)
    LayoutDispelSensorButton(button, sensor, parentFrame, index)

    local icon = button.Icon
    if not icon then
        icon = button:CreateTexture(nil, "ARTWORK")
        button.Icon = icon
    end
    icon:ClearAllPoints()
    icon:SetAllPoints(button)
    icon:SetAlpha(0)
    CallButtonMethod(button, "SetIcon", icon)
    CallButtonMethod(button, "ClearApplicationCount")
    CallButtonMethod(button, "ClearDurationCooldown")
    CallButtonMethod(button, "ClearDurationText")
    CallButtonMethod(button, "ClearDurationBar")
    CallButtonMethod(button, "ClearAuraSymbol")

    local region = button._msufA3DispelSensorRegion
    if not region then
        region = button:CreateTexture(nil, "OVERLAY")
        button._msufA3DispelSensorRegion = region
    end
    LayoutDispelSensorOverlay(region, button, sensor)
    if sensor.visual == "corner" then
        region:SetTexture("Interface\\Buttons\\WHITE8X8")
        region:SetAlpha(Clamp01(sensor.alpha, 1))
        CallButtonMethod(button, "SetAuraBorder", region, GetSensorOverlayOptions())
    elseif sensor.visual == "overlay" then
        region:SetTexture("Interface\\Buttons\\WHITE8X8")
        region:SetAlpha(Clamp01(sensor.alpha, 0.35))
        CallButtonMethod(button, "SetAuraBorder", region, GetSensorOverlayOptions())
    else
        region:SetTexture(MSUF_AURA_SENSOR_EDGE_TEXTURE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        region:SetAlpha(0.82)
        CallButtonMethod(button, "SetAuraBorder", region, GetSensorBorderOptions())
    end
    return true
end

local function SyncDispelSensorGeometry(container, sensor, parentFrame)
    if not (container and sensor) then return false end
    parentFrame = parentFrame or container._msufA3ParentFrame or container:GetParent()
    if not parentFrame then return false end
    container._msufA3NativeLaneConfig = sensor
    container._msufA3ParentFrame = parentFrame
    local target = DispelSensorTarget(parentFrame, sensor)
    local sig = sensor._msufA3LayoutSignature or SensorLayoutSignature(sensor)
    if sig ~= nil
        and container._msufA3GeomSig == sig
        and container._msufA3GeomParent == parentFrame
        and container._msufA3GeomTarget == target
    then
        return true
    end
    container._msufA3GeomSig = sig
    container._msufA3GeomParent = parentFrame
    container._msufA3GeomTarget = target
    local root = container:GetParent()
    if root then container:SetAllPoints(root) end
    if parentFrame and container.SetFrameLevel then
        container:SetFrameLevel((parentFrame:GetFrameLevel() or 0) + (sensor.layer or 14))
    end
    for i = 1, (container.createdButtons or sensor.max or 0) do
        PrepareDispelSensorButton(container[i], sensor, parentFrame, i)
    end
    return true
end

local function CreateNativeDispelSensor(root, sensor, parentFrame)
    if not EnsureBlizzardAuraContainerLoaded() then
        A3.nativeAuraRuntimeAvailable = false
        A3.nativeAuraRuntimeError = AURA_CONTAINER_ADDON .. " is not loaded: " .. tostring(A3.nativeAuraRuntimeLoadError or "unknown")
        return nil
    end
    local container = CreateFrame("AuraContainer", nil, root, "CustomAuraContainerTemplate")
    if not container then
        A3.nativeAuraRuntimeAvailable = false
        A3.nativeAuraRuntimeError = "CustomAuraContainerTemplate is unavailable"
        return nil
    end
    A3.nativeAuraRuntimeAvailable = true
    container._msufA3NativeLane = sensor.kind
    container._msufA3NativeRegistered = nil
    container._msufA3NativeRegistrationPending = nil
    container.unit = sensor.unit
    container.createdButtons = sensor.max or 1
    container:Show()
    container:SetUnit(sensor.unit)
    if type(container.SetEnabled) == "function" then container:SetEnabled(true) end
    for i = 1, container.createdButtons do
        local button = CreateFrame("AuraButton", nil, container, "CustomAuraButtonTemplate")
        if not button then
            A3.nativeAuraRuntimeAvailable = false
            A3.nativeAuraRuntimeError = "CustomAuraButtonTemplate is unavailable"
            if container.Hide then container:Hide() end
            return nil
        end
        PrepareDispelSensorButton(button, sensor, parentFrame, i)
        container[i] = button
        container:AddAuraFrame(button)
    end
    AddDispelSensorAuraFilters(container, sensor)
    if not RegisterNativeContainer(container) then
        if container.Hide then container:Hide() end
        return nil
    end
    A3.nativeAuraRuntimeError = nil
    return container
end

local function ConfigureContainer(container, lane, parentFrame)
    container._msufA3NativeLane = lane.kind
    container._msufA3NativeRegistered = nil
    container._msufA3NativeRegistrationPending = nil
    container.unit = lane.unit
    SyncContainerGeometry(container, lane, parentFrame)
end

local function NativeContainerVisible(container)
    if not container then return false end
    if type(container.IsVisible) == "function" and container:IsVisible() ~= true then return false end
    if type(container.IsShown) == "function" and container:IsShown() ~= true then return false end
    return true
end

RegisterNativeContainer = function(container, forceRefresh)
    if not container then return false end
    if forceRefresh ~= true and container._msufA3NativeRegistered == true then return true end
    if not NativeContainerVisible(container) then
        container._msufA3NativeRegistrationPending = true
        return true
    end

    -- Enable the container so Blizzard registers it for UNIT_AURA on this unit
    -- (ShouldRegisterForEvents = IsVisible() and IsEnabled()). Without this the
    -- container never self-updates: a hidden->shown transition reparses via
    -- OnShow, but a same-token target swap or an aura expiring/refreshing does
    -- not, so content goes stale. Enabling routes all steady-state updates
    -- through the container's cheap incremental delta path (added/updated/
    -- removed) instead of an MSUF forced reparse. SetEnabled is a secure
    -- delegate (safe to call directly) and is idempotent.
    if type(container.SetEnabled) == "function" then container:SetEnabled(true) end
    container._msufA3NativeRegistered = true
    container._msufA3NativeRegistrationPending = nil
    return true
end

local function UnregisterNativeContainer(container)
    if not container then return true end
    container._msufA3NativeRegistered = nil
    container._msufA3NativeRegistrationPending = nil
    return true
end

local function CreateNativeLane(root, lane, parentFrame)
    if not EnsureBlizzardAuraContainerLoaded() then
        A3.nativeAuraRuntimeAvailable = false
        A3.nativeAuraRuntimeError = AURA_CONTAINER_ADDON .. " is not loaded: " .. tostring(A3.nativeAuraRuntimeLoadError or "unknown")
        return nil
    end

    local container = CreateFrame("AuraContainer", nil, root, "CustomAuraContainerTemplate")
    if not container then
        A3.nativeAuraRuntimeAvailable = false
        A3.nativeAuraRuntimeError = "CustomAuraContainerTemplate is unavailable"
        return nil
    end
    A3.nativeAuraRuntimeAvailable = true
    ConfigureContainer(container, lane, parentFrame)
    container:Show()
    container:SetUnit(lane.unit)
    -- Enable before the filter and frames so the container registers for UNIT_AURA
    -- and its setup parses run over zero filters (cheap). The one populating parse
    -- then happens once, on AddAuraFilter below, against the already-built pool --
    -- instead of AddAuraFilter parsing empty, then re-parsing on SetEnabled.
    if type(container.SetEnabled) == "function" then container:SetEnabled(true) end
    -- Add buttons one at a time. The batch AddAuraFramesFromTable() TAINTS on 12.1:
    -- it ipairs/indexes the addon-owned table inside the secure delegate and throws
    -- "cannot be accessed while tainted" (unlike AddAuraFilter, which securecopies
    -- its options). Per-frame AddAuraFrame only ever passes a single forbidden
    -- object, so it is safe -- and because the filter is added afterwards, each
    -- AddAuraFrame here re-walks over zero filters (cheap); the one populating parse
    -- happens on AddAuraFilter below.
    for i = 1, lane.max do
        local button = CreateFrame("AuraButton", nil, container, "CustomAuraButtonTemplate")
        if not button then
            A3.nativeAuraRuntimeAvailable = false
            A3.nativeAuraRuntimeError = "CustomAuraButtonTemplate is unavailable"
            if container.Hide then container:Hide() end
            return nil
        end
        PrepareAuraButton(button, lane, i)
        container[i] = button
        container:AddAuraFrame(button)
    end
    container:AddAuraFilter(lane.nativeFilter, { maxFrameCount = lane.max })
    if not RegisterNativeContainer(container) then
        if container.Hide then container:Hide() end
        return nil
    end
    A3.nativeAuraRuntimeError = nil
    return container
end

local function HideLane(lane)
    if lane then
        UnregisterNativeContainer(lane)
        lane:Hide()
    end
end

local function ApplyLane(root, lane, parentFrame, forceRecreate)
    if not (root and lane and lane.enabled) then return nil end
    local key = lane.rootKey
    local trackingSignature = lane._msufA3TrackingSignature or LaneTrackingSignature(lane)
    local layoutSignature = lane._msufA3LayoutSignature or LaneLayoutSignature(lane)
    local current = root[key]
    if forceRecreate ~= true
        and current
        and current._msufA3TrackingSignature == trackingSignature
        and current._msufA3LayoutSignature == layoutSignature
    then
        SyncContainerGeometry(current, lane, parentFrame)
        current:Show()
        return RegisterNativeContainer(current) and current or nil
    end
    HideLane(current)
    root[key] = nil
    current = CreateNativeLane(root, lane, parentFrame)
    if current then
        current._msufA3TrackingSignature = trackingSignature
        current._msufA3LayoutSignature = layoutSignature
        root[key] = current
    end
    return current
end

local function ApplyDispelSensor(root, sensor, parentFrame, forceRecreate)
    if not (root and sensor and sensor.enabled) then return nil end
    local key = sensor.rootKey
    local trackingSignature = sensor._msufA3TrackingSignature or SensorTrackingSignature(sensor)
    local layoutSignature = sensor._msufA3LayoutSignature or SensorLayoutSignature(sensor)
    local current = root[key]
    if forceRecreate ~= true
        and current
        and current._msufA3TrackingSignature == trackingSignature
        and current._msufA3LayoutSignature == layoutSignature
    then
        SyncDispelSensorGeometry(current, sensor, parentFrame)
        current:Show()
        return RegisterNativeContainer(current) and current or nil
    end
    HideLane(current)
    root[key] = nil
    current = CreateNativeDispelSensor(root, sensor, parentFrame)
    if current then
        current._msufA3TrackingSignature = trackingSignature
        current._msufA3LayoutSignature = layoutSignature
        sensor._msufA3TrackingSignature = trackingSignature
        sensor._msufA3LayoutSignature = layoutSignature
        root[key] = current
    end
    return current
end

local function RefreshNativeContainer(container, forceRefresh, lane, parentFrame)
    lane = lane or (container and container._msufA3NativeLaneConfig)
    if lane and lane.sensor == true then
        SyncDispelSensorGeometry(container, lane, parentFrame)
    else
        SyncContainerGeometry(container, lane, parentFrame)
    end
    if not RegisterNativeContainer(container) then return false end
    if not NativeContainerVisible(container) then return true end
    if forceRefresh == true and lane and lane.nativeFilter and lane.max then
        -- Stable-token swaps need a full content refresh. UpdateAllAuras() is
        -- cheaper in theory, but current PTR builds still leave addon-created
        -- CustomAuraContainers stale in this path. Default to the proven
        -- content-correct filter re-add route, still coalesced by frame in
        -- FlushIdentityQueue. Keep UpdateAllAuras as an explicit A/B switch.
        if A3.swapUseUpdateAllAuras == true and type(container.UpdateAllAuras) == "function" then
            container:UpdateAllAuras()
        else
            container:ClearAuraFilters()
            if lane.sensor == true then
                AddDispelSensorAuraFilters(container, lane)
            else
                container:AddAuraFilter(lane.nativeFilter, { maxFrameCount = lane.max })
            end
        end
    end
    return true
end

RefreshAppliedNativeRoot = function(root, forceRefresh)
    if not (root and root._msufA3NativeRoot == true and root._msufA3Applied == true) then return false end
    local cfg = root._msufA3Config
    local lanes = cfg and cfg.lanes or nil
    if not lanes then return false end

    local ok, any = true, false
    if lanes.buff and lanes.buff.enabled then
        any = true
        ok = RefreshNativeContainer(root.Buffs, forceRefresh, lanes.buff, root:GetParent()) and ok
    end
    if lanes.debuff and lanes.debuff.enabled then
        any = true
        ok = RefreshNativeContainer(root.Debuffs, forceRefresh, lanes.debuff, root:GetParent()) and ok
    end
    if lanes.external and lanes.external.enabled then
        any = true
        ok = RefreshNativeContainer(root.Externals, forceRefresh, lanes.external, root:GetParent()) and ok
    end
    local sensors = cfg.sensors
    if sensors and sensors.dispelBorder and sensors.dispelBorder.enabled then
        any = true
        ok = RefreshNativeContainer(root.DispelBorderSensor, forceRefresh, sensors.dispelBorder, root:GetParent()) and ok
    end
    if sensors and sensors.dispelOverlay and sensors.dispelOverlay.enabled then
        any = true
        ok = RefreshNativeContainer(root.DispelOverlaySensor, forceRefresh, sensors.dispelOverlay, root:GetParent()) and ok
    end
    if sensors and sensors.dispelCorner and sensors.dispelCorner.enabled then
        any = true
        ok = RefreshNativeContainer(root.DispelCornerSensor, forceRefresh, sensors.dispelCorner, root:GetParent()) and ok
    end
    if ok and any then A3.nativeAuraRuntimeError = nil end
    return ok and any
end

local function RefreshAppliedNativeAuras(frame, forceRefresh)
    return RefreshAppliedNativeRoot(frame and frame.Auras, forceRefresh)
end

EnsureNativeAuraRefreshDriver = function()
    if A3._nativeAuraRefreshDriver then return A3._nativeAuraRefreshDriver end
    A3._nativeAuraRefreshDriver = true
    return true
end

-- Deferred, coalesced identity flush. On a same-token target/focus swap the
-- container does NOT self-refresh: UNIT_AURA does not fire just because the
-- "target" token repoints to a new GUID, and SetUnit() is a no-op when the token
-- is unchanged -- so the new unit's auras would otherwise never load. We
-- therefore trigger a content reparse here, but keep it off the synchronous
-- identity tick and coalesce it: enqueue the frame in a frame-keyed set and run
-- one forced refresh next tick (vs the old path's synchronous reparse on every
-- identity event). Frame-keyed => natural coalescing under swap spam; the unit is
-- re-read at flush so the latest identity wins. Steady-state aura changes
-- (expiry/refresh/stacks) on the current target are handled separately by the
-- container's own UNIT_AURA once it is enabled (see RegisterNativeContainer).
local _identityQueue
local _identityFlushScheduled = false

local function FlushIdentityQueue()
    _identityFlushScheduled = false
    local queue = _identityQueue
    _identityQueue = nil
    if not queue then return end
    for frame in pairs(queue) do
        local root = frame and frame.Auras
        -- Only touch frames that still own applied native auras; a frame disabled
        -- between enqueue and flush must not be resurrected here.
        if root and root._msufA3NativeRoot == true and root._msufA3Applied == true then
            -- One coalesced reparse per settled identity tick. (UnitGUID is a secret
            -- value on 12.1 and errors when compared while tainted, so we cannot gate
            -- on whether the GUID changed -- the deferral + frame-keyed coalescing
            -- already collapse swap spam to one reparse per tick, which is the win.)
            RefreshAppliedNativeAuras(frame, true)
        end
    end
end

local function HideState(frame)
    local root = frame and frame.Auras
    if not (root and root._msufA3NativeRoot) then return end
    HideLane(root.Buffs)
    HideLane(root.Debuffs)
    HideLane(root.Externals)
    HideLane(root.DispelBorderSensor)
    HideLane(root.DispelOverlaySensor)
    HideLane(root.DispelCornerSensor)
    root._msufA3Config = nil
    root._msufA3Applied = nil
    root._msufA3ConfigGen = nil
    root._msufA3VisualGen = nil
    root._msufA3AppliedUnit = nil
    root._msufA3FrameSpec = nil
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

local function ApplyConfig(frame, cfg, reason)
    if not (frame and cfg and cfg.enabled) then
        HideState(frame)
        return false
    end
    local root = EnsureRoot(frame)
    if not root then return false end
    if RootAppliedConfigIsCurrent(root, frame, cfg, reason) then
        RefreshAppliedNativeRoot(root, false)
        return true
    end
    root.unit = cfg.unit or frame.unit
    root:SetAllPoints(frame)
    root:Show()
    local lanes = cfg.lanes or {}
    local sensors = cfg.sensors or {}
    local forceRecreate = false
    local ok = true
    if lanes.buff and lanes.buff.enabled and not ApplyLane(root, lanes.buff, frame, forceRecreate) then ok = false end
    if lanes.debuff and lanes.debuff.enabled and not ApplyLane(root, lanes.debuff, frame, forceRecreate) then ok = false end
    if lanes.external and lanes.external.enabled and not ApplyLane(root, lanes.external, frame, forceRecreate) then ok = false end
    if sensors.dispelBorder and sensors.dispelBorder.enabled and not ApplyDispelSensor(root, sensors.dispelBorder, frame, forceRecreate) then ok = false end
    if sensors.dispelOverlay and sensors.dispelOverlay.enabled and not ApplyDispelSensor(root, sensors.dispelOverlay, frame, forceRecreate) then ok = false end
    if sensors.dispelCorner and sensors.dispelCorner.enabled and not ApplyDispelSensor(root, sensors.dispelCorner, frame, forceRecreate) then ok = false end
    if not (lanes.buff and lanes.buff.enabled) then HideLane(root.Buffs) end
    if not (lanes.debuff and lanes.debuff.enabled) then HideLane(root.Debuffs) end
    if not (lanes.external and lanes.external.enabled) then HideLane(root.Externals) end
    if not (sensors.dispelBorder and sensors.dispelBorder.enabled) then HideLane(root.DispelBorderSensor) end
    if not (sensors.dispelOverlay and sensors.dispelOverlay.enabled) then HideLane(root.DispelOverlaySensor) end
    if not (sensors.dispelCorner and sensors.dispelCorner.enabled) then HideLane(root.DispelCornerSensor) end
    root._msufA3Config = cfg
    root._msufA3Applied = ok == true
    root._msufA3ConfigGen = ConfigGen(cfg)
    root._msufA3VisualGen = VisualGen(cfg)
    root._msufA3AppliedUnit = cfg.unit or frame.unit
    root._msufA3FrameSpec = frame.MSUFSpec
    root.needFullUpdate = nil
    root:Show()
    return ok == true
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
    if EnsureNativeAuraRefreshDriver then EnsureNativeAuraRefreshDriver() end
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

function A3.RenderFrame(frame, reason)
    if not frame then return false end
    if DEFERRED_IDENTITY_REASONS[reason] == true then
        -- Coalesce target/focus swaps off the tick; the container's own
        -- UNIT_AURA full-update repopulates content. See FlushIdentityQueue.
        return A3.QueueIdentityAuraRebuild(frame)
    end
    if IDENTITY_AURA_REFRESH_REASONS[reason] == true then
        -- Group identity stays synchronous so roster builds settle in one pass,
        -- but never forces a filter rebuild: keep geometry/registration current
        -- (no ClearAuraFilters/AddAuraFilter) and let the container's UNIT_AURA
        -- own aura content.
        if RefreshAppliedNativeAuras(frame, false) then return true end
        if InCombat() then return false end
    end
    if FrameAppliedConfigIsCurrent(frame, reason) then
        RefreshAppliedNativeAuras(frame, false)
        return true
    end
    local cfg = FrameAuraConfig(frame, frame.unit)
    return ApplyConfig(frame, cfg, reason)
end

A3.ForceUpdateFrame = A3.RenderFrame
A3.RenderCachedFrame = A3.RenderFrame

function A3.QueueIdentityAuraRebuild(frame)
    if not frame then return false end
    _identityQueue = _identityQueue or {}
    _identityQueue[frame] = true
    if not _identityFlushScheduled then
        if C_Timer and C_Timer.After then
            _identityFlushScheduled = true
            C_Timer.After(0, FlushIdentityQueue)
        else
            FlushIdentityQueue()
        end
    end
    return true
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
    if EnsureNativeAuraRefreshDriver then EnsureNativeAuraRefreshDriver() end
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
    RequestUnitNow("*")
    return true
end

function A3.RequestApply()
    return A3.RefreshAll()
end

if type(MSUF.RegisterLocaleCallback) == "function" then
    MSUF.RegisterLocaleCallback("MSUF_Auras3_DurationFormatter", function()
        _durationFormatterCache = nil
        if type(A3.RequestApply) == "function" then A3.RequestApply() end
    end)
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
    return A3.RequestUnit(unit)
end

function A3.ApplyFontsFromGlobal()
    A3._nativeVisualGen = (A3._nativeVisualGen or 0) + 1
    return A3.RefreshAll()
end

-- AuraContainer owns UNIT_AURA and per-aura churn. Do not add an MSUF UNIT_AURA
-- scanner here; target/focus identity refresh is handled by the coalesced
-- container refresh path above.
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

function AurasElement.Update(frame, event)
    if event ~= nil and not ReasonRequiresAuraApply(event) then
        return FrameAppliedConfigIsCurrent(frame, event)
    end
    return A3.RenderFrame(frame, event)
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
