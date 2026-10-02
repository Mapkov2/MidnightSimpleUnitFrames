--- Game/Classic/Auras/MSUF_Auras3_Compile.lua
--- Classic aura config compiler: lane specs, filters, blacklist hashes,
--- dispel visuals and sort comparators. It turns DB/model choices into the
--- lane config the runtime consumes, so UNIT_AURA never walks SavedVariables.
---
--- Loaded immediately before the unit-frame aura backend (Buttons.lua first),
--- which imports these helpers through A3._ClassicCompile, the one A3 field
--- this file publishes.
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
--- Visuals.lua and Features.lua load right before this file in every
--- Game/<Flavor>/Auras.xml; the lane compilers call both directly.
local Visuals, Features = A3.ClassicVisuals, A3.ClassicFeatures
assert(type(Visuals) == "table" and type(Features) == "table",
    "Classic aura compiler requires Game/Classic/Auras/MSUF_Auras3_Visuals.lua and MSUF_Auras3_Features.lua")

local type, tostring, tonumber, pairs, select = type, tostring, tonumber, pairs, select
local math_floor, math_ceil, math_min, math_max = math.floor, math.ceil, math.min, math.max
local wipe = table.wipe or wipe
local IsSecret = _G.issecretvalue or function() return false end
local InCombatLockdown = _G.InCombatLockdown
-- Debuffs this player can dispel, in the filter this client honours
-- (Game/Shared/Initialize.lua; Classic Era needs HARMFUL|RAID).
local DISPELLABLE_DEBUFF_FILTER = MSUF.Client.DispellableDebuffFilter or "HARMFUL|RAID_PLAYER_DISPELLABLE"

-- Saved profiles can arrive from Retail, an older Classic build, or another
-- Classic family client. Keep the explicit three-state setting authoritative
-- while preserving the former boolean contract (which represented the old
-- border+symbol presentation). The lane compilers here and in Features.lua
-- and the Classic visuals call both normalizers when a lane compiles or
-- renders, which is always after this file has loaded.
A3.NormalizeClassicDebuffTypeBorderMode = A3.NormalizeClassicDebuffTypeBorderMode or function(value, legacyBorder, legacySymbol)
    local mode = type(value) == "string" and value:upper() or nil
    if mode == "SYMBOL" or mode == "BORDER" then return mode end
    if mode == "OFF" then
        if legacySymbol == true or legacyBorder == true then return "SYMBOL" end
        return "OFF"
    end
    return (legacySymbol == true or legacyBorder == true) and "SYMBOL" or "OFF"
end
A3.NormalizeClassicStealableStyle = A3.NormalizeClassicStealableStyle or function(value)
    value = type(value) == "string" and value:upper() or "BORDER_ICON"
    if value == "BORDER" or value == "BORDER_ICON" or value == "ICON" then return value end
    return "BORDER_ICON"
end

local BOSS_UNITS = {
    boss1 = true, boss2 = true, boss3 = true, boss4 = true, boss5 = true,
}
local MANAGED_UNITS = {
    player = true, pet = true, target = true, focus = true,
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

local UNIT_FLAG = {
    player = "showPlayer", pet = "showPet",
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

local BASE_LANE_ORDER = { "buff", "trackedBuff", "debuff", "external" }

--- Aura runtime work waits while combat blocks it: in lockdown, or while
--- MSUF's own combat flag is set. The apply service (Requests.lua), the unit
--- change follower (UnitFrames.lua) and the dispel previews (Preview.lua) ask it.
local function AuraRuntimeCombatBlocked()
    return (InCombatLockdown and InCombatLockdown()) or _G.MSUF_InCombat == true
end

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

--- The one sort-name parser for unit, group and custom container lanes
--- (Features.lua calls it when it compiles a container), so a sort name the
--- shared menu writes sorts the same way on every lane. Classic has no priority
--- slots: a Custom Priority container keeps arrival order, like INSTANCE_ID.
local function SortMode(value, fallback)
    value = tostring(value or ""):upper():gsub("[%s%-]+", "_")
    if value == "DEFAULT" or value == "PLAYER" then return 1 end
    if value == "DURATION" or value == "DURATION_ONLY" or value == "BIG_DEFENSIVE" then return 2 end
    if value == "EXPIRATION" or value == "TIME_REMAINING" or value == "TIME" then return 3 end
    if value == "EXPIRATION_ONLY" then return 4 end
    if value == "NAME" then return 5 end
    if value == "NAME_ONLY" then return 6 end
    if value == "INSTANCE_ID" or value == "CUSTOM_PRIORITY" then return 0 end
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

--- The per-type dispel colours, by AuraData.dispelName ("None" for an untyped
--- debuff), with the profile's overrides. Classic reads the public dispel type
--- straight from the aura: no Blizzard Classic UI calls the curve APIs
--- (C_CurveUtil, GetAuraDispelTypeColor) Retail colours its native buttons with.
local function DispelTypeColors(spec)
    local colors = {}
    for i = 1, #DISPEL_POINTS do
        local point = DISPEL_POINTS[i]
        local key = "type" .. point[2]
        colors[point[2]] = {
            DispelColorValue(spec, key .. "R", point[3]),
            DispelColorValue(spec, key .. "G", point[4]),
            DispelColorValue(spec, key .. "B", point[5]),
        }
    end
    return colors
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
    return {
        colorMode = mode,
        r = DispelColorValue(visual, "r", 0.25),
        g = DispelColorValue(visual, "g", 0.75),
        b = DispelColorValue(visual, "b", 1.00),
        a = DispelColorValue(visual, "a", 1.00),
        dispelTypeColors = DispelTypeColors(visual),
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

--- The engine owns frame identity through MSUFUnitKey/unitKey. The backend
--- only reads it, frame.unit last for a stand-in without either, and never
--- writes frame.unit: engine frames are secure unit buttons, and no other
--- engine or Retail path keeps that field in step.
local function BindFrameUnit(frame)
    if not frame then return nil end
    return frame.MSUFUnitKey or frame.unitKey or frame.unit
end

local function IsUnitToken(unit)
    return unit ~= nil and IsSecret(unit) ~= true and type(unit) == "string" and unit ~= ""
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
    -- The compile only reads the unit show flags. A missing flag is off (the
    -- pet's on), exactly as Retail's runtime reads it (UnitAuraIconsEnabled in
    -- Runtime_ConfigValues); defaults are written by the profile and menu
    -- layers, never from a compile.
    return auras, auras.shared
end

local function ReadRaw(primary, secondary, key)
    if primary and primary[key] ~= nil then return primary[key] end
    if secondary and secondary[key] ~= nil then return secondary[key] end
    return nil
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

--- The nine anchors the aura menu offers (AURA_ANCHORS in
--- Auras3/MenuModel/MSUF_Auras3_Menu_Schema.lua) and Retail's runtime accepts
--- (ReadAnchor in Auras3/Runtime/MSUF_Auras3_Runtime_ConfigValues.lua).
local AURA_ANCHOR_OK = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local function ReadAnchor(primary, secondary, key, fallback)
    local value = ReadRaw(primary, secondary, key) or fallback or "TOPLEFT"
    if AURA_ANCHOR_OK[value] ~= true then
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

local function ResolveHidePermanent(blacklist, filtersRoot, kind)
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

local function ReadBlacklistHidePermanent(scope, kind)
    scope = tostring(scope or "player")
    if BOSS_UNITS[scope] then scope = "boss" end
    -- The shared menu model collapses every Arena scope to arena1 for reads.
    -- Arena rendering is owned separately, but the Classic menu adapter must
    -- still preserve that current SavedVariables ownership contract.
    local runtimeUnit = (scope == "arena" or scope:match("^arena%d+$")) and "arena1"
        or NormalizeRuntimeUnit(scope)
    if not runtimeUnit then return false end

    local auras = A3.EnsureDB()
    local _, _, blacklist, filters = EffectiveTables(auras, runtimeUnit)
    return ResolveHidePermanent(blacklist, filters, kind)
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
--- Drops only the configs one unit compiled from its frame specs, so a scoped
--- refresh never makes the other unit frames recompile and rescan.
local function InvalidateFrameSpecConfig(unit)
    for frameSpec, cached in pairs(frameSpecConfigCache) do
        if cached.unit == unit then frameSpecConfigCache[frameSpec] = nil end
    end
end

--- The lane being sorted hands its own "cast by the player" answers to the
--- comparators (RenderLane in MSUF_Auras3_Lanes.lua): they are kept per
--- lane by aura instance ID, never in the AuraData that lanes share.
local NO_OWNERSHIP = {}
local sortOwnership = NO_OWNERSHIP
local function SetSortOwnership(mine)
    sortOwnership = mine or NO_OWNERSHIP
end

SortAuras = function(a, b)
    local am, bm = sortOwnership[a.auraInstanceID] == true, sortOwnership[b.auraInstanceID] == true
    if am ~= bm then return am end
    return (a.auraInstanceID or 0) < (b.auraInstanceID or 0)
end

SortAurasID = function(a, b)
    return (a.auraInstanceID or 0) < (b.auraInstanceID or 0)
end

local function AuraID(data)
    return PlainNumber(data and data.auraInstanceID) or 0
end

local function SortAurasDefault(a, b)
    local am, bm = sortOwnership[a.auraInstanceID] == true, sortOwnership[b.auraInstanceID] == true
    if am ~= bm then return am end
    -- A missing or secret canApplyAura (a synthetic weapon enchant) ranks as
    -- false. As a third class it tied with both others, which broke the strict
    -- weak order table.sort needs.
    local ca = PlainBool(a.canApplyAura) == true
    local cb = PlainBool(b.canApplyAura) == true
    if ca ~= cb then return ca end
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
    -- Arrival order (instance ID); what Reverse turns into newest first.
    if mode == 0 then return SortAurasID end
    return SortAuras
end

--- The lane schema. Three compilers build the lanes the backend renders: unit
--- Buff/Debuff lanes and group lanes (below), custom containers, their portrait
--- variants and group indicators (Features.lua). Each reads its own settings;
--- the parts every lane carries are filled by these builders, so the runtime
--- (Buttons, Filters, Lanes) reads one shape. As hand-synced copies the
--- containers had drifted: no countdown colour buckets, a fixed stack colour.
--- tools/tests/classic_aura_lane_schema_smoke.lua checks every compiler.
local LaneSchema = {}

--- The filter-token strings the runtime membership checks use (Filters.lua).
function LaneSchema.FilterTokens(lane, filter, nativePlayerFilter, bossFilter)
    lane.filter = filter
    lane.playerFilter = nativePlayerFilter and filter or (filter .. "|PLAYER")
    lane.importantFilter = filter .. "|IMPORTANT"
    lane.raidFilter = filter .. "|RAID"
    lane.raidInCombatFilter = filter .. "|RAID_IN_COMBAT"
    lane.stealableFilter = "HELPFUL|STEALABLE"
    lane.dispellableFilter = DISPELLABLE_DEBUFF_FILTER
    lane.bossFilter = bossFilter
end

--- Sort mode (SortMode) and Reverse. Arrival order renders unsorted unless it
--- is reversed. A refresh can move an aura only in the time-keyed modes (2
--- duration, 3 expiration, 4 expiration only); every other key is fixed for
--- the aura's lifetime, and an ownership flip is caught by the update path.
function LaneSchema.Ordering(lane, sortOrder, sortReverse)
    lane.sortOrder = sortOrder
    lane.sortComparator = SortComparator(sortOrder)
    lane.sortReverse = sortReverse == true
    lane.naturalOrder = sortOrder == 0 and sortReverse ~= true
    lane.reorderOnUpdate = sortOrder == 2 or sortOrder == 3 or sortOrder == 4
end

--- The global text colours (Colors page): the countdown colour buckets with
--- their thresholds, which Retail applies to every lane too
--- (BuildAuraDurationStyle, Auras3/Runtime/MSUF_Auras3_Runtime_DurationText.lua),
--- and the stack count colour.
function LaneSchema.GlobalTextColors(lane)
    local general = _G.MSUF_DB and _G.MSUF_DB.general
    local buckets = general and general.aurasCooldownTextUseBuckets == true
    lane.cooldownTextBuckets = buckets
    lane.cooldownSafeR, lane.cooldownSafeG, lane.cooldownSafeB = 1, 1, 1
    lane.cooldownWarnR, lane.cooldownWarnG, lane.cooldownWarnB = 1, 0.85, 0.20
    lane.cooldownUrgentR, lane.cooldownUrgentG, lane.cooldownUrgentB = 1, 0.55, 0.10
    if buckets == true then
        lane.cooldownSafeR, lane.cooldownSafeG, lane.cooldownSafeB =
            ReadGeneralColor("aurasCooldownTextSafeColor", 1, 1, 1)
        lane.cooldownWarnR, lane.cooldownWarnG, lane.cooldownWarnB =
            ReadGeneralColor("aurasCooldownTextWarningColor", 1, 0.85, 0.20)
        lane.cooldownUrgentR, lane.cooldownUrgentG, lane.cooldownUrgentB =
            ReadGeneralColor("aurasCooldownTextUrgentColor", 1, 0.55, 0.10)
    end
    lane.cooldownSafeSeconds = ClampNumber(general and general.aurasCooldownTextSafeSeconds, 60, 0, 600)
    lane.cooldownWarningSeconds = ClampNumber(general and general.aurasCooldownTextWarningSeconds, 15, 0, 60)
    lane.cooldownUrgentSeconds = ClampNumber(general and general.aurasCooldownTextUrgentSeconds, 5, 0, 60)
    lane.stackR, lane.stackG, lane.stackB = ReadGeneralColor("aurasStackCountColor", 1, 1, 1)
end

--- Unit Buff/Debuff and group lanes lay out maxCount square icons, perRow to a
--- row (to a column when vertical); containers lay out bars and portraits
--- themselves (Features.lua).
function LaneSchema.IconGrid(lane, size, spacing, maxCount, perRow, vertical, padding)
    local roundedPerRow = Round(perRow)
    local cols, rows = GridShape(Round(maxCount), roundedPerRow, vertical)
    lane.size, lane.spacing, lane.step = size, spacing, size + spacing
    lane.perRow, lane.cols, lane.rows, lane.padding = roundedPerRow, cols, rows, padding
    lane.width = math_max(1, cols * size + math_max(cols - 1, 0) * spacing + 2 * padding)
    lane.height = math_max(1, rows * size + math_max(rows - 1, 0) * spacing + 2 * padding)
end

--- The Retail-only filters (important, raid, stealable, boss, raid in combat,
--- maximum duration) have no Classic Buff/Debuff or group setting, so those
--- lanes carry them as fixed off values; ShouldShowAura reads them.
function LaneSchema.RetailOnlyFiltersOff(lane)
    lane.exclusiveImportant, lane.onlyImportant = false, false
    lane.raid, lane.raidInCombat, lane.includeStealable, lane.boss = false, false, false, false
    lane.maxDuration = 0
end

--- The per-aura dispel type border and its symbol mode on a Debuff lane, and
--- the type colours they paint with: the frame visual's when it has one.
function LaneSchema.DispelTypeBorder(lane, mode, visual)
    local show = lane.kind == "debuff" and lane.renderEnabled == true and mode ~= "OFF"
    local dispelVisual = lane.kind == "debuff" and (visual or (show and CompileDispelVisual(nil))) or nil
    lane.showDispelTypeBorder = show == true
    lane.showDispelTypeSymbol = show == true and mode == "SYMBOL"
    lane.dispelTypeColors = dispelVisual and dispelVisual.dispelTypeColors or nil
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
    -- Bars > Show on is Retail's border-only unit filter (CompileDispelSensor in
    -- Auras3/Runtime/MSUF_Auras3_Runtime_DispelConfig.lua): Friendly shows the
    -- border only on a unit the player can assist, Enemy only on one it cannot,
    -- Both adds nothing. A unit frame's cleanse trigger (Dispellable by me or by
    -- group, both BY_ME here) already needs a friendly unit, so Enemy compiles
    -- no border there. Overlay, symbol and stripe keep their own policy even
    -- when they inherit this trigger.
    local borderShowOn = border and border.dispelShowOn
    if borderShowOn ~= "FRIENDLY" and borderShowOn ~= "ENEMY" then borderShowOn = nil end
    if borderShowOn == "ENEMY" and borderTrigger == "BY_ME" and spec.scope ~= "group" then
        borderEnabled = false
    end
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
        -- nil for Both: the runtime then never asks UnitCanAssist.
        borderShowOn = borderEnabled == true and borderShowOn or nil,
        overlayTrigger = overlayActualTrigger,
        directVisualEligible = directVisualEligible == true,
        needsPlayerFlag = borderTrigger == "PLAYER_CAST" or overlayActualTrigger == "PLAYER_CAST",
        colorMode = dispel and dispel.colorMode or "SINGLE",
        r = dispel and dispel.r or 0.25,
        g = dispel and dispel.g or 0.75,
        b = dispel and dispel.b or 1,
        a = dispel and dispel.a or 1,
        dispelTypeColors = dispel and dispel.dispelTypeColors or nil,
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

local function OwnHighlightColor(kind)
    if kind == "buff" then return ReadGeneralColor("aurasOwnBuffHighlightColor", 1, 0.85, 0.20) end
    return ReadGeneralColor("aurasOwnDebuffHighlightColor", 1, 0.30, 0.30)
end

--- The tooltip switch and the countdown and stack text of a unit Buff/Debuff lane.
local function UnitLaneText(lane, spec, layout, sharedLayout, kind)
    lane.showTooltip = ReadBool(sharedLayout, nil, kind .. "ShowTooltip", DEFAULT_SHARED.showTooltip ~= false)
    lane.cooldownSize = ReadNumber(layout, nil, spec.cooldownSizeKey, DEFAULT_SHARED.cooldownTextSize, 6, 40)
    lane.cooldownDecimalSeconds = ReadNumber(sharedLayout, nil, kind .. "CooldownDecimalSeconds",
        DEFAULT_SHARED.cooldownDecimalSeconds or 3, 0, 30)
    lane.cooldownAnchor = ReadAnchor(sharedLayout, nil, kind .. "CooldownTextAnchor",
        DEFAULT_SHARED.cooldownTextAnchor or "CENTER")
    lane.cooldownX = ReadNumber(layout, nil, spec.cooldownXKey, DEFAULT_SHARED.cooldownTextOffsetX, -2000, 2000)
    lane.cooldownY = ReadNumber(layout, nil, spec.cooldownYKey, DEFAULT_SHARED.cooldownTextOffsetY, -2000, 2000)
    lane.showStacks = ReadBool(sharedLayout, nil, spec.showStackKey, DEFAULT_SHARED.showStackCount ~= false)
    lane.stackAnchor = ReadAnchor(sharedLayout, nil, spec.stackAnchorKey, DEFAULT_SHARED.stackCountAnchor or "TOPRIGHT")
    lane.stackSize = ReadNumber(layout, nil, spec.stackSizeKey, DEFAULT_SHARED.stackTextSize, 6, 40)
    lane.stackX = ReadNumber(layout, nil, spec.stackXKey, DEFAULT_SHARED.stackTextOffsetX, -2000, 2000)
    lane.stackY = ReadNumber(layout, nil, spec.stackYKey, DEFAULT_SHARED.stackTextOffsetY, -2000, 2000)
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
    local layer = ReadNumber(layout, nil, spec.layerKey, spec.defaultLayer, 0, 30)
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
    local hidePermanent = ResolveHidePermanent(blacklist, filtersRoot, kind)
    local showSated = kind ~= "buff" or ReadBool(nil, shared, "showSated", true)
    local satedThreshold = kind == "buff" and ReadNumber(nil, shared, "satedShowAtSeconds", 0, 0, 3600) or 0
    local satedFilter = kind == "buff" and (showSated ~= true or satedThreshold > 0)
    local ownHighlight = kind == "buff"
        and ReadBool(nil, shared, "highlightOwnBuffs", false)
        or (kind == "debuff" and ReadBool(nil, shared, "highlightOwnDebuffs", false))
    local filterPlan = Features.CompileSettingsFilter(filters, kind == "buff") or nil
    local visualNeedsPlayer = kind == "debuff" and visual and visual.needsPlayerFlag == true
    local hasInclusive = (filterPlan and filterPlan.hasRequirements == true) or onlyMine == true
    local black = CompileBlacklist(laneBlacklist)
    local hasFilterWork = black ~= nil or hasInclusive or hidePermanent or nonPlayerFilter or satedFilter
    local renderEnabled = renderAllowed ~= false and show and maxCount > 0
    local nativePlayerFilter = filterPlan and filterPlan.nativePlayerFilter == true or false
    -- The frame's cleanse visuals (border, overlay, symbol) never follow this
    -- lane's icon filters, as on Retail, where they are independent native
    -- sensors: they come from everything the lane scans, filtered-out auras
    -- included. A native PLAYER scan (Only mine) never sees other casters'
    -- debuffs, so such a lane resolves them straight from the unit, as does a
    -- lane without filter work whose visuals allow it.
    local visualDirect = kind == "debuff"
        and visual
        and (nativePlayerFilter == true
            or (visual.directVisualEligible == true and hasFilterWork ~= true))
    local enabled = renderEnabled or (forceScan == true and kind == "debuff" and visualDirect ~= true)
    -- Capped scan: every rule ShouldShowAura applies to this lane (blacklist,
    -- auto-exclusion, Hide permanent, non-player, sated) is decided per aura,
    -- so the scan may stop once cfg.max auras are visible. Lanes with an
    -- inclusive filter (Only mine, or a requirement from the feature compiler)
    -- keep the full walk. That carve-out comes from Retail, where inclusive
    -- filters OR-ed extra filter tokens into the lane; Classic keeps it so the
    -- Only mine scan path is unchanged.
    local cappedFilterScan = hasFilterWork == true and hasInclusive ~= true
    local sortOrder = SortMode(ReadRaw(sharedLayout, nil, kind .. "SortMethod"), DEFAULT_SHARED.sortOrder)
    local sortReverse = ReadBool(sharedLayout, nil, kind .. "SortReverse", false)
    local showCooldownSwipe = ReadBool(sharedLayout, nil, spec.showSwipeKey, DEFAULT_SHARED.showCooldownSwipe ~= false)
    local showCooldownText = ReadBool(sharedLayout, nil, spec.showTextKey, DEFAULT_SHARED.showCooldownText ~= false)
    local cooldownSwipeDarken = ReadBool(nil, shared, "cooldownSwipeDarkenOnLoss", false)
    local baseFilter = filterPlan and filterPlan.scanFilter or spec.filter
    local debuffTypeBorderMode = kind == "debuff" and A3.NormalizeClassicDebuffTypeBorderMode(
        ReadRaw(sharedLayout, nil, "debuffTypeBorderMode"),
        ReadBool(sharedLayout, nil, "useDebuffTypeBorders", false), false) or "OFF"
    local needsPlayerFlag = (filterPlan and filterPlan.needsPlayerFlag == true)
        or onlyMine == true or ownHighlight == true or (visualNeedsPlayer == true and visualDirect ~= true)
        or sortOrder == 1 or sortOrder == 2 or sortOrder == 3 or sortOrder == 5

    local lane = {
        kind = kind,
        unit = runtimeUnit,
        enabled = enabled == true,
        renderEnabled = renderEnabled == true,
        harmful = spec.harmful == true,
        max = renderEnabled and Round(maxCount) or 0,
        weaponEnchants = kind == "buff" and runtimeUnit == "player"
            and ReadBool(shared, layout, "showWeaponEnchants", false),
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
        cappedFilterScan = cappedFilterScan == true,
        ownHighlight = ownHighlight == true,
        ownR = 1, ownG = 1, ownB = 1,
        showCooldownSwipe = showCooldownSwipe,
        showCooldownText = showCooldownText,
        showCooldown = renderEnabled == true and (showCooldownSwipe ~= false or showCooldownText ~= false),
        cooldownSwipeDarken = cooldownSwipeDarken == true,
        blacklist = black,
        filterPlan = filterPlan,
        filterRequirements = filterPlan and filterPlan.requirements or nil,
        nativePlayerFilter = nativePlayerFilter,
        hasFilterWork = hasFilterWork,
        visualDirect = visualDirect == true,
        onlyMine = onlyMine == true,
        hidePermanent = hidePermanent == true,
        nonPlayerFilter = nonPlayerFilter,
        showSated = showSated == true,
        satedThreshold = satedThreshold,
        satedFilter = satedFilter == true,
        hasInclusive = hasInclusive == true,
        needsPlayerFlag = needsPlayerFlag,
        needsCombatRefresh = filterPlan and filterPlan.needsCombatRefresh == true or false,
        visual = kind == "debuff" and visual or nil,
        showStealableMarker = kind == "buff" and renderEnabled == true
            and ReadBool(sharedLayout, nil, "buffShowStealable", false),
        stealableStyle = kind == "buff" and A3.NormalizeClassicStealableStyle(
            ReadRaw(sharedLayout, nil, "buffStealableStyle")) or nil,
    }
    if ownHighlight == true then lane.ownR, lane.ownG, lane.ownB = OwnHighlightColor(kind) end
    UnitLaneText(lane, spec, layout, sharedLayout, kind)
    LaneSchema.DispelTypeBorder(lane, debuffTypeBorderMode, visual)
    LaneSchema.FilterTokens(lane, baseFilter, nativePlayerFilter, spec.filter .. "|BOSS")
    LaneSchema.IconGrid(lane, size, spacing, maxCount, perRow, verticalGrowth, lanePadding)
    LaneSchema.Ordering(lane, sortOrder, sortReverse)
    LaneSchema.GlobalTextColors(lane)
    LaneSchema.RetailOnlyFiltersOff(lane)
    -- Arrival order is the aura instance order alone, as Retail's
    -- AuraInstanceIDOnly sort: the ownership work that Only mine, the own-aura
    -- highlight or a cast-by-me dispel visual turns on never reorders it, and
    -- the unsorted render may stop scanning once the lane is full.
    lane.visibleOnlyScan = renderEnabled == true and lane.naturalOrder == true
        and not (kind == "debuff" and visual and visual.enabled == true and visualDirect ~= true)
    return lane
end

--- Generic Classic group lanes support only All and Player. The stored token is
--- never rewritten: Retail can consume it again after an import. The External
--- lane's auto-blacklist is an internal ownership rule, not a user-selected
--- Retail filter, so that one negation is preserved.
local function GroupLaneRawFilter(kind, spec, rawFilter)
    if kind ~= "buff" and kind ~= "debuff" then return rawFilter end
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
    return rawFilter
end

--- A tracked-buff lane's include list. Classic aura payloads often carry a
--- different spellId than the configured one (TBC spell ranks, Mists
--- cast-vs-aura ID drift), so the compiled list adds aliases and the spells'
--- names; exact-ID matching silently emptied tracked-buff whitelists.
local function GroupIncludeSpells(hash)
    if type(hash) ~= "table" then return nil, nil end
    local includeSpellIDs
    for key, enabled in pairs(hash) do
        if enabled == true then
            local id = tonumber(key)
            if id and id > 0 then
                includeSpellIDs = includeSpellIDs or {}
                A3.AddAuraSpellIDAndAliases(includeSpellIDs, id)
            end
        end
    end
    local includeSpellNames
    if includeSpellIDs then includeSpellNames = Features.NameHash(includeSpellIDs) end
    return includeSpellIDs, includeSpellNames
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
    local anchor = ReadAnchor(source, nil, spec.anchorKey, spec.defaultAnchor)
    local layer = ClampNumber(source[spec.layerKey], spec.defaultLayer, 0, 30)
    local alpha = ClampNumber(source[spec.alphaKey], 1, 0, 1)
    local rawFilter = GroupLaneRawFilter(kind, spec, source[spec.filterKey] or spec.filter)
    local filterPlan = Features.CompileRawFilter(rawFilter, spec.harmful ~= true) or nil
    local filter = filterPlan and filterPlan.scanFilter or spec.filter
    local nativePlayerFilter = filterPlan and filterPlan.nativePlayerFilter == true or false
    local black = CompileBlacklistHash(source[spec.blacklistKey])
    local includeSpellIDs, includeSpellNames = GroupIncludeSpells(spec.includeHashKey and source[spec.includeHashKey])
    local hidePermanent = spec.hidePermanentKey and source[spec.hidePermanentKey] == true or false
    local nonPlayerFilter = spec.nonPlayerKey and source[spec.nonPlayerKey] == true or false
    local hasFilterWork = black ~= nil or type(includeSpellIDs) == "table" or hidePermanent
        or nonPlayerFilter
        or (filterPlan and filterPlan.hasRequirements == true)
    -- Cleanse visuals never follow the lane's icon filters (see CompileLane);
    -- the debuff stripe alone shows the debuffs the lane matches, so a direct
    -- lane still scans for it.
    local visualDirect = kind == "debuff"
        and visual
        and (nativePlayerFilter == true
            or (visual.directVisualEligible == true and hasFilterWork ~= true))
    local enabled = renderEnabled or (forceScan == true and kind == "debuff"
        and (visualDirect ~= true or visual.stripeEnabled == true))
    local cappedFilterScan = (black ~= nil or hidePermanent or nonPlayerFilter)
        and type(includeSpellIDs) ~= "table"
        and not (filterPlan and filterPlan.hasRequirements == true)
    local showCooldown = source[spec.showCooldownKey] ~= false
    local showCooldownSwipe = showCooldown and source[spec.showSwipeKey] ~= false
    local lanePadding = Round(ClampNumber(source.stylePadding, 0, 0, 16))
    local sortOrder = SortMode(source[kind .. "SortMethod"] or source.sortMethod,
        source.sortByDuration == true and 2 or 1)
    local sortReverse = source[kind .. "SortReverse"] == true
        or (source[kind .. "SortReverse"] == nil and source.sortReverse == true)
    local debuffTypeBorderMode = kind == "debuff" and A3.NormalizeClassicDebuffTypeBorderMode(
        source.debuffDispelBorderMode or source.debuffTypeBorderMode or source.dispelBorderMode,
        source.debuffShowDispelBorder == true or source.showDispelBorder == true,
        source.debuffShowDispelSymbol == true or source.showDispelSymbol == true) or "OFF"
    local needsPlayerFlag = source.preferPlayer == true
        or (filterPlan and filterPlan.needsPlayerFlag == true)
        or (kind == "debuff" and visual and visual.needsPlayerFlag == true and visualDirect ~= true)
        or sortOrder == 1 or sortOrder == 2 or sortOrder == 3 or sortOrder == 5

    local lane = {
        kind = kind,
        unit = unit,
        enabled = enabled == true,
        renderEnabled = renderEnabled == true,
        harmful = spec.harmful == true,
        max = renderEnabled and Round(maxCount) or 0,
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
        cappedFilterScan = cappedFilterScan == true,
        showTooltip = source[kind .. "ShowTooltip"] ~= false and source.showTooltip ~= false,
        showCooldownSwipe = renderEnabled == true and showCooldownSwipe == true,
        showCooldownText = renderEnabled == true and showCooldown == true,
        showCooldown = renderEnabled == true and showCooldown == true,
        cooldownSwipeDarken = source.cooldownSwipeDarkenOnLoss == true,
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
        blacklist = black,
        includeSpellIDs = includeSpellIDs,
        includeSpellNames = includeSpellNames,
        filterPlan = filterPlan,
        filterRequirements = filterPlan and filterPlan.requirements or nil,
        nativePlayerFilter = nativePlayerFilter,
        hasFilterWork = hasFilterWork,
        visualDirect = visualDirect == true,
        onlyMine = false,
        hasInclusive = false,
        hidePermanent = hidePermanent,
        nonPlayerFilter = nonPlayerFilter,
        needsPlayerFlag = needsPlayerFlag == true,
        needsCombatRefresh = filterPlan and filterPlan.needsCombatRefresh == true or false,
        visual = kind == "debuff" and visual or nil,
    }
    LaneSchema.DispelTypeBorder(lane, debuffTypeBorderMode, visual)
    LaneSchema.FilterTokens(lane, filter, nativePlayerFilter, "HARMFUL|BOSS")
    LaneSchema.IconGrid(lane, size, spacing, maxCount, perRow, verticalGrowth, lanePadding)
    LaneSchema.Ordering(lane, sortOrder, sortReverse)
    LaneSchema.GlobalTextColors(lane)
    LaneSchema.RetailOnlyFiltersOff(lane)
    -- Arrival order renders unsorted, whatever ownership work the lane does.
    lane.visibleOnlyScan = renderEnabled == true and lane.naturalOrder == true
        and not (kind == "debuff" and visual and visual.enabled == true and visualDirect ~= true)
    return lane
end

--- A group edit must not evict the unit-frame configs: each group kind keeps a
--- revision the group config cache is keyed on, as on Retail
--- (Auras3/Runtime/MSUF_Auras3_Runtime_GroupConfig.lua); [false] covers a frame
--- without a declared kind. The shared menu model calls this for a group
--- scope and bumps the global generation only when it is missing. Revisions
--- advance only on configuration writes, never on aura events.
local groupConfigRevisions = { party = 0, raid = 0, mythicraid = 0, [false] = 0 }

function A3.InvalidateGroupRuntimeConfig(scope)
    if type(scope) ~= "string" then return false end
    local party = scope == "party" or scope == "gf_party" or scope:match("^party%d+$") ~= nil
    local raid = scope == "raid" or scope == "gf_raid" or scope:match("^raid%d+$") ~= nil
    local mythic = raid or scope == "mythicraid" or scope == "gf_mythicraid"
    if scope == "group" or scope == "groups" then party, raid, mythic = true, true, true end
    if not (party or raid or mythic) then return false end
    if party then groupConfigRevisions.party = groupConfigRevisions.party + 1 end
    if raid then groupConfigRevisions.raid = groupConfigRevisions.raid + 1 end
    if mythic then groupConfigRevisions.mythicraid = groupConfigRevisions.mythicraid + 1 end
    groupConfigRevisions[false] = groupConfigRevisions[false] + 1
    return true
end

local function ResolveGroupFrameConfig(frame, unit)
    if not frame then return nil end
    unit = unit or BindFrameUnit(frame)
    local spec = frame.MSUFSpec
    local source = spec and (spec.auras or (spec.group and spec.group.auras))
    -- Both counters only advance, so their sum keeps one generation check on a
    -- cache hit; the kind is compared too, as two kinds can reach equal sums.
    local kind = frame._msufGFKind
    local gen = (A3._runtimeConfigGen or 1)
        + (groupConfigRevisions[kind or false] or groupConfigRevisions[false])
    local cached = frame._msufA3GroupConfig
    if cached and frame._msufA3GroupSource == source and frame._msufA3GroupUnit == unit
        and frame._msufA3GroupSpec == spec and frame._msufA3GroupGen == gen
        and frame._msufA3GroupKind == kind then
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
        local scope = frame._msufGFKind or frame._msufCoreKind or "party"
        if buff then Visuals.EnrichGroupLane(buff, source, "buff", spec, scope) end
        if trackedBuff then Visuals.EnrichGroupLane(trackedBuff, source, "trackedBuff", spec, scope) end
        if debuff then Visuals.EnrichGroupLane(debuff, source, "debuff", spec, scope) end
        if external then Visuals.EnrichGroupLane(external, source, "external", spec, scope) end
        cfg.showTooltip = source.showTooltip ~= false
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
    local extraLanes, extraOrder = Features.CompileGroupIndicatorLanes(frame, unit)
    for i = 1, type(extraOrder) == "table" and #extraOrder or 0 do
        local kind = extraOrder[i]
        cfg.lanes[kind] = extraLanes[kind]
        cfg.laneOrder[#cfg.laneOrder + 1] = kind
        cfg.enabled = cfg.enabled == true or (extraLanes[kind] and extraLanes[kind].enabled == true)
    end

    frame._msufA3GroupSource = source
    frame._msufA3GroupUnit = unit
    frame._msufA3GroupSpec = spec
    frame._msufA3GroupGen = gen
    frame._msufA3GroupKind = kind
    frame._msufA3GroupConfig = cfg
    return cfg
end

local function FrameAuraConfig(frame, unit)
    if IsGroupFrame(frame) then
        return ResolveGroupFrameConfig(frame, unit)
    end
    return A3.ResolveUnitFrameConfig(unit or BindFrameUnit(frame), frame and frame.MSUFSpec)
end

local function BuildUnitFrameConfig(unit, frameSpec)
    unit = NormalizeRuntimeUnit(unit)
    if not unit then return nil end

    local auras, shared = EnsureRootDB()
    local flag = UNIT_FLAG[unit]
    local visual = CompileFrameAuraVisual(frameSpec)
    local cfg = { unit = unit, enabled = false, lanes = {}, laneOrder = {}, visual = visual }
    local auraIconsEnabled = auras.enabled == true and flag
        and (auras[flag] == true or (flag == "showPet" and auras[flag] == nil))
    local needDebuffScan = visual and visual.enabled == true
    local layout, sharedLayout, blacklist, filtersRoot = EffectiveTables(auras, unit)
    if auraIconsEnabled or needDebuffScan then
        local buff = auraIconsEnabled and CompileLane(unit, shared, layout, sharedLayout, blacklist, filtersRoot, "buff", false, nil, true) or nil
        local debuff = (auraIconsEnabled or needDebuffScan)
            and CompileLane(unit, shared, layout, sharedLayout, blacklist, filtersRoot, "debuff", needDebuffScan, visual, auraIconsEnabled == true) or nil
        if buff then Visuals.EnrichUnitLane(buff, layout, sharedLayout, shared, "buff", frameSpec) end
        if debuff then Visuals.EnrichUnitLane(debuff, layout, sharedLayout, shared, "debuff", frameSpec) end
        cfg.showTooltip = ReadBool(nil, shared, "showTooltip", true)
        cfg.lanes.buff = buff
        cfg.lanes.debuff = debuff
        if buff then cfg.laneOrder[#cfg.laneOrder + 1] = "buff" end
        if debuff then cfg.laneOrder[#cfg.laneOrder + 1] = "debuff" end
        cfg.visualDirect = debuff and debuff.visualDirect == true or nil
        cfg.enabled = (buff and buff.enabled == true) or (debuff and debuff.enabled == true) or cfg.visualDirect == true
    end

    local lanePadding = ReadRaw(layout, nil, "buffStylePadding")
    local extraLanes, extraOrder, extraSource = Features.CompileUnitLanes(auras, unit, frameSpec, lanePadding)
    if type(extraLanes) == "table" then
        Features.ApplyAutoExclusions(cfg.lanes.buff, cfg.lanes.debuff, extraLanes, extraSource, unit)
        for i = 1, type(extraOrder) == "table" and #extraOrder or 0 do
            local kind = extraOrder[i]
            cfg.lanes[kind] = extraLanes[kind]
            cfg.laneOrder[#cfg.laneOrder + 1] = kind
            cfg.enabled = cfg.enabled == true or (extraLanes[kind] and extraLanes[kind].enabled == true)
        end
    end

    return cfg
end

local function ConfigRoot()
    local db = _G.MSUF_DB
    return type(db) == "table" and db.auras3 or nil
end

--- Compiled configs are keyed on every input that can change without a runtime
--- generation bump: the active profile's auras3 table (a profile switch, reset
--- or import swaps it) and, for a frame spec, UF.Config.serial (the unit-frame
--- compiler refills the same spec table in place). The root is read after the
--- build, which may create it.
function A3.ResolveUnitFrameConfig(unit, frameSpec)
    unit = NormalizeRuntimeUnit(unit)
    if not unit then return nil end
    local gen = A3._runtimeConfigGen or 1
    local root = ConfigRoot()
    if frameSpec ~= nil then
        local ufConfig = MSUF.UF and MSUF.UF.Config
        local specSerial = ufConfig and ufConfig.serial or 0
        local cached = frameSpecConfigCache[frameSpec]
        if cached and cached.gen == gen and cached.unit == unit and cached.root == root
            and cached.specSerial == specSerial then
            return cached.config
        end
        local cfg = BuildUnitFrameConfig(unit, frameSpec)
        frameSpecConfigCache[frameSpec] = {
            gen = gen, unit = unit, root = ConfigRoot(), specSerial = specSerial, config = cfg,
        }
        return cfg
    end
    A3._runtimeConfigCache = A3._runtimeConfigCache or {}
    local cached = A3._runtimeConfigCache[unit]
    if cached and cached.gen == gen and cached.root == root then return cached.config end

    local cfg = BuildUnitFrameConfig(unit, nil)
    A3._runtimeConfigCache[unit] = { gen = gen, root = ConfigRoot(), config = cfg }
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
    LaneSchema = LaneSchema,
    BASE_LANE_ORDER = BASE_LANE_ORDER,
    SortMode = SortMode,
    BindFrameUnit = BindFrameUnit,
    ReadBlacklistHidePermanent = ReadBlacklistHidePermanent,
    AuraRuntimeCombatBlocked = AuraRuntimeCombatBlocked,
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
    InvalidateFrameSpecConfig = InvalidateFrameSpecConfig,
    SetSortOwnership = SetSortOwnership,
}
