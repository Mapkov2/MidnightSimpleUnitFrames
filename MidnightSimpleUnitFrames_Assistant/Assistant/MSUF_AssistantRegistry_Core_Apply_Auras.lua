-- Assistant registry core aura apply helpers.
-- Loaded before MSUF_AssistantRegistry_Core_Apply.lua; consumed by the apply helper builder.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.RegistryCoreBuilders = A.RegistryCoreBuilders or {}

function A.RegistryCoreBuilders.BuildAuraApplyHelpers(ctx)
    ctx = type(ctx) == "table" and ctx or {}

    local MSUFRef = ctx.MSUF or MSUF
    local MRef = ctx.M or M
    local EnsureDB = ctx.EnsureDB
    local CallGlobal = ctx.CallGlobal
    local ApplyGroup = ctx.ApplyGroup
    if type(EnsureDB) ~= "function" or type(CallGlobal) ~= "function" or type(ApplyGroup) ~= "function" then return nil end

    local function CurrentApplyService()
        return (MRef and MRef.ApplyService) or (M and M.ApplyService) or _G.MSUF_Menu2_ApplyService
    end

    local EnsureAuraFallbackDB

    -- The Options MenuModel is the preferred owner adapter, but the Assistant
    -- is independently loadable. Its cold fallback must therefore address the
    -- exact Unit lane tables too; writing auras3.shared here would resurrect
    -- the retired Shared-inheritance architecture whenever Options is absent.
    local UNIT_FLAGS = {
        player = "showPlayer", target = "showTarget", focus = "showFocus", boss = "showBoss",
    }
    local LANE_SPECS = {
        buff = {
            show = "showBuffs", max = "maxBuffs", x = "buffGroupOffsetX", y = "buffGroupOffsetY",
            size = "buffGroupIconSize", anchor = "buffAnchor", layer = "buffLayer",
            strata = "buffStrata", spacing = "buffSpacing", perRow = "buffPerRow",
            growthX = "buffGrowthX", growthY = "buffGrowthY", prefix = "buff",
        },
        debuff = {
            show = "showDebuffs", max = "maxDebuffs", x = "debuffGroupOffsetX", y = "debuffGroupOffsetY",
            size = "debuffGroupIconSize", anchor = "debuffAnchor", layer = "debuffLayer",
            strata = "debuffStrata", spacing = "debuffSpacing", perRow = "debuffPerRow",
            growthX = "debuffGrowthX", growthY = "debuffGrowthY", prefix = "debuff",
        },
    }
    local STYLE_KEYS = {
        iconZoom = "IconZoom", stylePadding = "StylePadding",
        showCooldownSwipe = "ShowCooldownSwipe", cooldownSwipeReverse = "CooldownSwipeReverse",
        sortMethod = "SortMethod", sortReverse = "SortReverse",
        showDurationBar = "ShowDurationBar", durationBarHeight = "DurationBarHeight",
        durationBarDisplay = "DurationBarDisplay", durationBarPosition = "DurationBarPosition",
        durationBarDirection = "DurationBarDirection", showTooltip = "ShowTooltip",
        showCooldownText = "ShowCooldownText", showStackCount = "ShowStackCount",
        stackCountAnchor = "StackCountAnchor", cooldownTextAnchor = "CooldownTextAnchor",
        stackTextSize = "StackTextSize", stackTextOffsetX = "StackTextOffsetX",
        stackTextOffsetY = "StackTextOffsetY", cooldownTextSize = "CooldownTextSize",
        cooldownTextOffsetX = "CooldownTextOffsetX", cooldownTextOffsetY = "CooldownTextOffsetY",
        cooldownDecimalSeconds = "CooldownDecimalSeconds",
    }
    local LAYOUT_KEYS, SHARED_LAYOUT_KEYS = {}, {}
    for _, spec in pairs(LANE_SPECS) do
        for _, field in ipairs({ "x", "y", "size", "anchor", "layer", "strata", "spacing" }) do
            LAYOUT_KEYS[spec[field]] = true
        end
        for _, field in ipairs({ "show", "max", "perRow", "growthX", "growthY" }) do
            SHARED_LAYOUT_KEYS[spec[field]] = true
        end
        for key, suffix in pairs(STYLE_KEYS) do
            local laneKey = spec.prefix .. suffix
            if key == "iconZoom" or key == "stylePadding" or key == "durationBarHeight"
                or key == "stackTextSize" or key == "stackTextOffsetX" or key == "stackTextOffsetY"
                or key == "cooldownTextSize" or key == "cooldownTextOffsetX" or key == "cooldownTextOffsetY"
            then
                LAYOUT_KEYS[laneKey] = true
            else
                SHARED_LAYOUT_KEYS[laneKey] = true
            end
        end
        for _, suffix in ipairs({ "Type", "Color", "Priority", "Thickness", "Layer", "Strata" }) do
            SHARED_LAYOUT_KEYS[spec.prefix .. "FrameEffect" .. suffix] = true
        end
    end
    SHARED_LAYOUT_KEYS.buffShowStealable = true
    SHARED_LAYOUT_KEYS.buffStealableStyle = true
    SHARED_LAYOUT_KEYS.debuffTypeBorderMode = true
    SHARED_LAYOUT_KEYS.useDebuffTypeBorders = true

    local function NormalizeUnit(unit)
        unit = tostring(unit or "player"):lower()
        if unit == "boss" or unit:match("^boss[1-5]$") then return "boss" end
        if unit == "target" or unit == "focus" then return unit end
        return "player"
    end

    local function EachRuntimeUnit(unit, callback)
        unit = NormalizeUnit(unit)
        if unit == "boss" then
            for i = 1, 5 do callback("boss" .. tostring(i)) end
        else
            callback(unit)
        end
    end

    local function ReadRuntimeUnit(unit)
        return NormalizeUnit(unit) == "boss" and "boss1" or NormalizeUnit(unit)
    end

    local function UnitRecord(unit, create)
        local auras = EnsureAuraFallbackDB()
        local runtimeUnit = ReadRuntimeUnit(unit)
        local record = auras.perUnit[runtimeUnit]
        if create and type(record) ~= "table" then
            record = {}
            auras.perUnit[runtimeUnit] = record
        end
        return record
    end

    local function Owner(record, key, create)
        if type(record) ~= "table" then return nil end
        local bucketName = LAYOUT_KEYS[key] and "layout" or (SHARED_LAYOUT_KEYS[key] and "layoutShared" or nil)
        if not bucketName then return nil end
        local bucket = record[bucketName]
        if create and type(bucket) ~= "table" then
            bucket = {}
            record[bucketName] = bucket
        end
        if create then
            record[bucketName == "layout" and "overrideLayout" or "overrideSharedLayout"] = true
            record.overrideStyle = true
        end
        return bucket
    end

    local function Clamp(value, defaultValue, minValue, maxValue)
        value = tonumber(value)
        if value == nil then value = tonumber(defaultValue) or 0 end
        if minValue and value < minValue then value = minValue end
        if maxValue and value > maxValue then value = maxValue end
        return value
    end

    local function LaneSpec(lane)
        return LANE_SPECS[lane == "debuff" and "debuff" or "buff"]
    end

    local function LaneStyleKey(lane, key)
        local spec = LaneSpec(lane)
        local suffix = STYLE_KEYS[key]
        if suffix then return spec.prefix .. suffix end
        if key == "showStealable" then return "buffShowStealable" end
        if key == "stealableStyle" then return "buffStealableStyle" end
        if key == "debuffTypeBorderMode" then return "debuffTypeBorderMode" end
        if key == "useDebuffTypeBorders" then return "useDebuffTypeBorders" end
        return key
    end

    local FallbackModel = {}

    function FallbackModel.EnsureDB()
        return EnsureAuraFallbackDB()
    end

    function FallbackModel.UnitEnabled(unit)
        local auras = EnsureAuraFallbackDB()
        local flag = UNIT_FLAGS[NormalizeUnit(unit)]
        return auras.enabled == true and flag ~= nil and auras[flag] == true
    end

    function FallbackModel.SetUnitEnabled(unit, enabled)
        local auras = EnsureAuraFallbackDB()
        local flag = UNIT_FLAGS[NormalizeUnit(unit)]
        if enabled then auras.enabled = true end
        if flag then auras[flag] = enabled == true end
    end

    function FallbackModel.ReadValue(unit, key, defaultValue)
        if tostring(unit or ""):lower() == "shared" then return defaultValue end
        local record = UnitRecord(unit, false)
        local owner = Owner(record, key, false)
        if type(owner) == "table" and owner[key] ~= nil then return owner[key] end
        return defaultValue
    end

    function FallbackModel.WriteValue(unit, key, value)
        if tostring(unit or ""):lower() == "shared" then return false end
        local wrote = false
        EachRuntimeUnit(unit, function(runtimeUnit)
            local auras = EnsureAuraFallbackDB()
            local record = auras.perUnit[runtimeUnit]
            if type(record) ~= "table" then record = {}; auras.perUnit[runtimeUnit] = record end
            local owner = Owner(record, key, true)
            if type(owner) == "table" then owner[key] = value; wrote = true end
        end)
        return wrote
    end

    function FallbackModel.ReadNumber(unit, key, defaultValue, minValue, maxValue)
        return Clamp(FallbackModel.ReadValue(unit, key, defaultValue), defaultValue, minValue, maxValue)
    end

    function FallbackModel.WriteNumber(unit, key, value, minValue, maxValue)
        value = Clamp(value, 0, minValue, maxValue)
        if math.floor(value) == value then value = math.floor(value + 0.5) end
        return FallbackModel.WriteValue(unit, key, value)
    end

    function FallbackModel.ReadBool(unit, key, defaultValue)
        return FallbackModel.ReadValue(unit, key, defaultValue == true) == true
    end

    function FallbackModel.WriteBool(unit, key, value)
        return FallbackModel.WriteValue(unit, key, value == true)
    end

    function FallbackModel.GroupShown(unit, lane)
        local spec = LaneSpec(lane)
        return FallbackModel.ReadBool(unit, spec.show, true)
            and FallbackModel.ReadNumber(unit, spec.max, 12, 0, 80) > 0
    end

    function FallbackModel.SetGroupShown(unit, lane, shown)
        local spec = LaneSpec(lane)
        FallbackModel.WriteBool(unit, spec.show, shown == true)
        if shown and FallbackModel.ReadNumber(unit, spec.max, 0, 0, 80) <= 0 then
            FallbackModel.WriteNumber(unit, spec.max, lane == "buff" and 8 or 12, 0, 80)
        end
    end

    function FallbackModel.ReadLanePerRow(unit, lane)
        return FallbackModel.ReadNumber(unit, LaneSpec(lane).perRow, 12, 1, 40)
    end
    function FallbackModel.WriteLanePerRow(unit, lane, value)
        return FallbackModel.WriteNumber(unit, LaneSpec(lane).perRow, value, 1, 40)
    end
    function FallbackModel.ReadLaneLayer(unit, lane)
        return FallbackModel.ReadNumber(unit, LaneSpec(lane).layer, lane == "buff" and 5 or 6, 0, 30)
    end
    function FallbackModel.WriteLaneLayer(unit, lane, value)
        return FallbackModel.WriteNumber(unit, LaneSpec(lane).layer, value, 0, 30)
    end
    function FallbackModel.ReadLaneSpacing(unit, lane)
        return FallbackModel.ReadNumber(unit, LaneSpec(lane).spacing, 2, 0, 64)
    end
    function FallbackModel.WriteLaneSpacing(unit, lane, value)
        return FallbackModel.WriteNumber(unit, LaneSpec(lane).spacing, value, 0, 64)
    end
    function FallbackModel.ReadLaneAnchor(unit, lane)
        return tostring(FallbackModel.ReadValue(unit, LaneSpec(lane).anchor, lane == "buff" and "BOTTOMRIGHT" or "TOPLEFT"))
    end
    function FallbackModel.WriteLaneAnchor(unit, lane, value)
        return FallbackModel.WriteValue(unit, LaneSpec(lane).anchor, tostring(value or ""))
    end
    function FallbackModel.ReadLaneGrowth(unit, lane)
        return tostring(FallbackModel.ReadValue(unit, LaneSpec(lane).growthX, "RIGHT"))
    end
    function FallbackModel.WriteLaneGrowth(unit, lane, value)
        return FallbackModel.WriteValue(unit, LaneSpec(lane).growthX, tostring(value or "RIGHT"))
    end
    function FallbackModel.ReadLaneGrowthPair(unit, lane)
        local spec = LaneSpec(lane)
        local x = tostring(FallbackModel.ReadValue(unit, spec.growthX, "RIGHT"))
        local y = tostring(FallbackModel.ReadValue(unit, spec.growthY, "DOWN"))
        return (x == "UP" or x == "DOWN") and x or (x .. y)
    end
    function FallbackModel.WriteLaneGrowthPair(unit, lane, value)
        local x, y = "RIGHT", "DOWN"
        if value == "LEFTDOWN" then x = "LEFT"
        elseif value == "RIGHTUP" then y = "UP"
        elseif value == "LEFTUP" then x, y = "LEFT", "UP"
        elseif value == "UP" or value == "DOWN" then x = value
        elseif value == "LEFT" then x = "LEFT" end
        local spec = LaneSpec(lane)
        FallbackModel.WriteValue(unit, spec.growthX, x)
        FallbackModel.WriteValue(unit, spec.growthY, y)
    end

    function FallbackModel.ReadLaneStyleBool(unit, lane, key, defaultValue)
        return FallbackModel.ReadValue(unit, LaneStyleKey(lane, key), defaultValue == true) == true
    end
    function FallbackModel.WriteLaneStyleBool(unit, lane, key, value)
        return FallbackModel.WriteValue(unit, LaneStyleKey(lane, key), value == true)
    end
    function FallbackModel.ReadLaneStyleNumber(unit, lane, key, defaultValue, minValue, maxValue)
        return FallbackModel.ReadNumber(unit, LaneStyleKey(lane, key), defaultValue, minValue, maxValue)
    end
    function FallbackModel.WriteLaneStyleNumber(unit, lane, key, value, minValue, maxValue)
        return FallbackModel.WriteNumber(unit, LaneStyleKey(lane, key), value, minValue, maxValue)
    end
    function FallbackModel.ReadLaneStyleString(unit, lane, key, defaultValue)
        return tostring(FallbackModel.ReadValue(unit, LaneStyleKey(lane, key), defaultValue or ""))
    end
    function FallbackModel.WriteLaneStyleString(unit, lane, key, value)
        return FallbackModel.WriteValue(unit, LaneStyleKey(lane, key), tostring(value or ""))
    end
    function FallbackModel.ReadLaneStackAnchor(unit, lane)
        return FallbackModel.ReadLaneStyleString(unit, lane, "stackCountAnchor", "TOPRIGHT")
    end
    function FallbackModel.WriteLaneStackAnchor(unit, lane, value)
        return FallbackModel.WriteLaneStyleString(unit, lane, "stackCountAnchor", value)
    end
    function FallbackModel.ReadLaneCooldownAnchor(unit, lane)
        return FallbackModel.ReadLaneStyleString(unit, lane, "cooldownTextAnchor", "CENTER")
    end
    function FallbackModel.WriteLaneCooldownAnchor(unit, lane, value)
        return FallbackModel.WriteLaneStyleString(unit, lane, "cooldownTextAnchor", value)
    end
    function FallbackModel.ReadStackAnchor(unit)
        return FallbackModel.ReadLaneStackAnchor(unit, "buff")
    end
    function FallbackModel.WriteStackAnchor(unit, value)
        return FallbackModel.WriteLaneStackAnchor(unit, "buff", value)
    end
    function FallbackModel.ReadCooldownAnchor(unit)
        return FallbackModel.ReadLaneCooldownAnchor(unit, "buff")
    end
    function FallbackModel.WriteCooldownAnchor(unit, value)
        return FallbackModel.WriteLaneCooldownAnchor(unit, "buff", value)
    end
    function FallbackModel.ReadLaneDurationBarPosition(unit, lane)
        return FallbackModel.ReadLaneStyleString(unit, lane, "durationBarPosition", "BOTTOM")
    end
    function FallbackModel.WriteLaneDurationBarPosition(unit, lane, value)
        return FallbackModel.WriteLaneStyleString(unit, lane, "durationBarPosition", value)
    end
    function FallbackModel.ReadLaneDurationBarDisplay(unit, lane)
        return FallbackModel.ReadLaneStyleString(unit, lane, "durationBarDisplay", "BAR_ONLY")
    end
    function FallbackModel.WriteLaneDurationBarDisplay(unit, lane, value)
        return FallbackModel.WriteLaneStyleString(unit, lane, "durationBarDisplay", value)
    end
    function FallbackModel.ReadLaneDurationBarDirection(unit, lane)
        return FallbackModel.ReadLaneStyleString(unit, lane, "durationBarDirection", "REMAINING")
    end
    function FallbackModel.WriteLaneDurationBarDirection(unit, lane, value)
        return FallbackModel.WriteLaneStyleString(unit, lane, "durationBarDirection", value)
    end
    function FallbackModel.ReadDebuffTypeBorderMode(unit)
        local mode = FallbackModel.ReadValue(unit, "debuffTypeBorderMode", nil)
        if mode ~= nil then return tostring(mode) end
        return FallbackModel.ReadBool(unit, "useDebuffTypeBorders", false) and "SYMBOL" or "OFF"
    end
    function FallbackModel.WriteDebuffTypeBorderMode(unit, value)
        value = tostring(value or "OFF"):upper()
        FallbackModel.WriteValue(unit, "debuffTypeBorderMode", value)
        FallbackModel.WriteValue(unit, "useDebuffTypeBorders", value ~= "OFF")
    end

    function FallbackModel.CustomContainer(unit, index, create)
        local auras = EnsureAuraFallbackDB()
        auras.customContainers = type(auras.customContainers) == "table" and auras.customContainers or {}
        local root = auras.customContainers
        root.perUnit = type(root.perUnit) == "table" and root.perUnit or {}
        unit = NormalizeUnit(unit)
        local record = root.perUnit[unit]
        if create and type(record) ~= "table" then record = { items = {} }; root.perUnit[unit] = record end
        if type(record) ~= "table" then return nil end
        record.items = type(record.items) == "table" and record.items or {}
        index = math.max(1, math.min(4, math.floor(tonumber(index) or 1)))
        local item = record.items[index]
        if create and type(item) ~= "table" then
            item = {
                enabled = false, name = "Custom " .. tostring(index), auraType = "BUFF", spellIDs = "",
                filters = { enabled = true, hidePermanent = false },
                placed = {
                    type = "icon", anchor = "TOPRIGHT", growth = "LEFTDOWN", x = 0, y = 0,
                    size = 24, max = 8, perRow = 4, spacing = 2,
                    showCooldown = true, showCooldownSwipe = true, showStacks = true,
                },
                layer = 9, strata = "AUTO",
            }
            if index == 4 then
                if unit == "player" then item.name = "Defensive Buffs"; item.playerDefensives = true
                else item.name = "Dots on target"; item.auraType = "DEBUFF"; item.targetDots = true end
            end
            record.items[index] = item
        end
        return item
    end

    local function AuraModel()
        local a3 = MSUFRef and MSUFRef.MSUF_Auras3
        return a3 and a3.MenuModel or FallbackModel
    end

    local function ApplyAura(scope, reason)
        local ApplyService = CurrentApplyService()
        if ApplyService and type(ApplyService.RequestAuras) == "function" then
            return ApplyService.RequestAuras(scope or "shared", reason or "MSUF_ASSISTANT_AURAS")
        end
        local Model = AuraModel()
        if Model and type(Model.Apply) == "function" then
            Model.Apply(scope or "shared", reason or "MSUF_ASSISTANT_AURAS")
            return true
        end
        local a3 = MSUFRef and MSUFRef.MSUF_Auras3
        if a3 and type(a3.RequestScope) == "function" then
            a3.RequestScope(scope or "shared", reason or "MSUF_ASSISTANT_AURAS")
            CallGlobal("MSUF_UFPreview_RequestRefresh", reason or "MSUF_ASSISTANT_AURAS")
            return true
        elseif a3 and type(a3.RequestApply) == "function" then
            a3.RequestApply(scope or "shared", reason or "MSUF_ASSISTANT_AURAS")
            CallGlobal("MSUF_UFPreview_RequestRefresh", reason or "MSUF_ASSISTANT_AURAS")
            return true
        end
        CallGlobal("MSUF_UFPreview_RequestRefresh", reason or "MSUF_ASSISTANT_AURAS")
        return false
    end

    local function ApplyAuraText(reason)
        local a3 = MSUFRef and MSUFRef.MSUF_Auras3
        local ct = a3 and a3.CooldownText
        if ct and type(ct.Invalidate) == "function" then ct.Invalidate("unit") end
        if ct and type(ct.ForceRecolor) == "function" then ct.ForceRecolor("unit") end
        CallGlobal("MSUF_GF_InvalidateCooldownTextCurve")
        CallGlobal("MSUF_GF_ForceCooldownTextRecolor")
        if not ApplyAura("shared", reason or "MSUF_ASSISTANT_AURA_TEXT") then
            ApplyGroup("party", "auras")
            ApplyGroup("raid", "auras")
            ApplyGroup("mythicraid", "auras")
        end
    end

    EnsureAuraFallbackDB = function()
        local db = EnsureDB()
        db.auras3 = type(db.auras3) == "table" and db.auras3 or {}
        local auras = db.auras3
        auras.enabled = auras.enabled ~= false
        auras.shared = type(auras.shared) == "table" and auras.shared or {}
        auras.perUnit = type(auras.perUnit) == "table" and auras.perUnit or {}
        local materialize = (MSUFRef and MSUFRef.MSUF_MaterializeUnitAuraLaneOwners)
            or _G.MSUF_MaterializeUnitAuraLaneOwners
        if type(materialize) == "function" then materialize(auras) end
        return auras, auras.shared
    end

    return {
        AuraModel = AuraModel,
        ApplyAura = ApplyAura,
        ApplyAuraText = ApplyAuraText,
        EnsureAuraFallbackDB = EnsureAuraFallbackDB,
    }
end
