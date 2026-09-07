--- Auras3 menu composition and cold-path preview/apply boundary.
--- All public methods retain the existing A3.MenuModel table. Feature owners
--- install once through explicit factories; their dependencies are cached
--- locals, so splitting the model does not add runtime dispatch or polling.
---
--- Ownership map: Storage handles sparse profile inheritance; Appearance
--- handles presentation; Containers/CustomSpells handle custom products;
--- Filters/GroupFilters handle rules; Presets supplies curated menu choices.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local type, tostring = type, tostring
local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end
local Model = A3.MenuModel
if type(Model) ~= "table" then
    Model = {}
    A3.MenuModel = Model
end

-- XML loads factories first; composition has no runtime loadfile/require path.
local Factories = assert(MSUF.Auras3MenuModelFactories, "Auras3 menu factories must load before Menu_Model")
local Schema = Factories.Schema(A3)
local Common = Factories.Common(Schema)
local Storage = Factories.Storage(A3, Model, Schema, Common, ExportPublic)
local Presets = Factories.Presets(Model, Common)
Factories.GroupFilters(A3, Model, Common, Presets, ExportPublic)
local Appearance = Factories.Appearance(A3, Model, Schema, Common, Storage)
Factories.Containers(A3, Model, Schema, Common, Storage)
Factories.CustomSpells(A3, Model, Schema, Common)
Factories.Filters(A3, Model, Schema, Common, Storage)

-- Installed methods retain only their cached dependencies. Release one-time
-- constructors so their setup code is not kept alive for the whole session.
MSUF.Auras3MenuModelFactories = nil

local BOSS_UNITS = Schema.BOSS_UNITS

local ARENA_UNITS = Schema.ARENA_UNITS

local ARENA_LOOKUP = Schema.ARENA_LOOKUP
local CUSTOM_CONTAINER_MAX = Schema.CUSTOM_CONTAINER_MAX
local RuntimeUnit = Common.RuntimeUnit
local EachRuntimeUnit = Common.EachRuntimeUnit
local NormalizeUnit = Common.NormalizeUnit
local NormalizeScope = Common.NormalizeScope
local CreatePreviewReadContext = Storage.CreatePreviewReadContext
local ReadPreviewNumber = Appearance.ReadPreviewNumber
local ReadPreviewBool = Appearance.ReadPreviewBool
local ReadPreviewString = Appearance.ReadPreviewString
local ReadPreviewEnum = Appearance.ReadPreviewEnum
local ReadPreviewValue = Appearance.ReadPreviewValue
local ReadDebuffModeFromTables = Appearance.ReadDebuffModeFromTables
local NormalizeDurationBarPosition = Appearance.NormalizeDurationBarPosition
local NormalizeDurationBarDirection = Appearance.NormalizeDurationBarDirection
local NormalizeDurationBarDisplay = Appearance.NormalizeDurationBarDisplay
local GROUPS = Schema.GROUPS
local AURA_ANCHOR_OK = Schema.AURA_ANCHOR_OK
local STACK_ANCHOR_OK = Schema.STACK_ANCHOR_OK
local GROWTH_OK = Schema.GROWTH_OK
local ROW_WRAP_OK = Schema.ROW_WRAP_OK

function Model.ReadPreviewConfig(unit)
    unit = NormalizeUnit(unit)
    local auras, shared = Model.EnsureDB()
    if type(auras) ~= "table" or type(shared) ~= "table" then return nil end
    local runtimeCfg = type(A3.ResolveUnitFrameConfig) == "function" and A3.ResolveUnitFrameConfig(RuntimeUnit(unit)) or nil
    local buildMetrics = runtimeCfg and type(A3.BuildAuraLaneMetrics) == "function" and A3.BuildAuraLaneMetrics or nil
    local buffMetrics = buildMetrics and buildMetrics(runtimeCfg, "buff") or nil
    local debuffMetrics = buildMetrics and buildMetrics(runtimeCfg, "debuff") or nil
    local customMetrics = {}
    if buildMetrics then
        for index = 1, CUSTOM_CONTAINER_MAX do
            customMetrics[index] = buildMetrics(runtimeCfg, "custom" .. tostring(index))
        end
    end
    -- Runtime metric compilation can materialize/replace profile tables. Resolve
    -- the final read context afterwards, then reuse it for every fallback field.
    local context = CreatePreviewReadContext(unit)
    local buffSpec, debuffSpec = GROUPS.buff, GROUPS.debuff
    local unitEnabled = runtimeCfg and runtimeCfg.enabled == true or context.enabled
    local showBuffs = false
    local showDebuffs = false
    if unitEnabled then
        if buffMetrics then showBuffs = buffMetrics.enabled == true else showBuffs = (buffSpec and ReadPreviewBool(context, buffSpec.showKey, true) and ReadPreviewNumber(context, buffSpec.maxKey, 12, 0, 80) > 0) or false end
        if debuffMetrics then showDebuffs = debuffMetrics.enabled == true else showDebuffs = (debuffSpec and ReadPreviewBool(context, debuffSpec.showKey, true) and ReadPreviewNumber(context, debuffSpec.maxKey, 12, 0, 80) > 0) or false end
    end
    return {
        unit = unit,
        enabled = unitEnabled,
        showBuffs = showBuffs == true,
        showDebuffs = showDebuffs == true,
        buffMetrics = buffMetrics,
        debuffMetrics = debuffMetrics,
        customMetrics = customMetrics,
        buffX = buffMetrics and buffMetrics.x or ReadPreviewNumber(context, "buffGroupOffsetX", 0, -4096, 4096),
        buffY = buffMetrics and buffMetrics.y or ReadPreviewNumber(context, "buffGroupOffsetY", 36, -4096, 4096),
        debuffX = debuffMetrics and debuffMetrics.x or ReadPreviewNumber(context, "debuffGroupOffsetX", 0, -4096, 4096),
        debuffY = debuffMetrics and debuffMetrics.y or ReadPreviewNumber(context, "debuffGroupOffsetY", 6, -4096, 4096),
        buffAnchor = buffMetrics and buffMetrics.anchor or ReadPreviewEnum(context, buffSpec and buffSpec.anchorKey or "buffAnchor", buffSpec and buffSpec.defaultAnchor or "TOPLEFT", AURA_ANCHOR_OK),
        debuffAnchor = debuffMetrics and debuffMetrics.anchor or ReadPreviewEnum(context, debuffSpec and debuffSpec.anchorKey or "buffAnchor", debuffSpec and debuffSpec.defaultAnchor or "TOPLEFT", AURA_ANCHOR_OK),
        buffLayer = ReadPreviewNumber(context, buffSpec and buffSpec.layerKey or "buffLayer", buffSpec and buffSpec.defaultLayer or 5, 0, 30),
        debuffLayer = ReadPreviewNumber(context, debuffSpec and debuffSpec.layerKey or "buffLayer", debuffSpec and debuffSpec.defaultLayer or 5, 0, 30),
        buffSize = buffMetrics and buffMetrics.size or ReadPreviewNumber(context, "buffGroupIconSize", ReadPreviewNumber(context, "iconSize", 26, 1, 128), 1, 128),
        debuffSize = debuffMetrics and debuffMetrics.size or ReadPreviewNumber(context, "debuffGroupIconSize", ReadPreviewNumber(context, "iconSize", 26, 1, 128), 1, 128),
        buffIconZoom = buffMetrics and buffMetrics.iconZoom or ReadPreviewNumber(context, "iconZoom", 100, 100, 200, "buff"),
        debuffIconZoom = debuffMetrics and debuffMetrics.iconZoom or ReadPreviewNumber(context, "iconZoom", 100, 100, 200, "debuff"),
        buffIconShape = buffMetrics and buffMetrics.iconShape or ReadPreviewString(context, "iconShape", "RECTANGLE", "buff"),
        debuffIconShape = debuffMetrics and debuffMetrics.iconShape or ReadPreviewString(context, "iconShape", "RECTANGLE", "debuff"),
        buffRequestedIconShape = buffMetrics and buffMetrics.requestedIconShape,
        debuffRequestedIconShape = debuffMetrics and debuffMetrics.requestedIconShape,
        spacing = (buffMetrics and buffMetrics.spacing) or (debuffMetrics and debuffMetrics.spacing) or ReadPreviewNumber(context, "spacing", 2, 0, 64),
        stylePadding = (buffMetrics and buffMetrics.padding) or (debuffMetrics and debuffMetrics.padding) or ReadPreviewNumber(context, "stylePadding", 0, 0, 16),
        perRow = (buffMetrics and buffMetrics.perRow) or (debuffMetrics and debuffMetrics.perRow) or ReadPreviewNumber(context, "perRow", 12, 1, 40),
        buffPerRow = buffMetrics and buffMetrics.perRow or ReadPreviewNumber(context, buffSpec and buffSpec.perRowKey or "perRow", 12, 1, 40),
        debuffPerRow = debuffMetrics and debuffMetrics.perRow or ReadPreviewNumber(context, debuffSpec and debuffSpec.perRowKey or "perRow", 12, 1, 40),
        buffSpacing = buffMetrics and buffMetrics.spacing or ReadPreviewNumber(context, buffSpec and buffSpec.spacingKey or "spacing", 2, 0, 64),
        debuffSpacing = debuffMetrics and debuffMetrics.spacing or ReadPreviewNumber(context, debuffSpec and debuffSpec.spacingKey or "spacing", 2, 0, 64),
        maxBuffs = buffMetrics and buffMetrics.num or ReadPreviewNumber(context, "maxBuffs", 12, 0, 80),
        maxDebuffs = debuffMetrics and debuffMetrics.num or ReadPreviewNumber(context, "maxDebuffs", 12, 0, 80),
        growth = (buffMetrics and buffMetrics.growth) or (debuffMetrics and debuffMetrics.growth) or ReadPreviewEnum(context, "growth", "RIGHT", GROWTH_OK),
        rowWrap = (buffMetrics and buffMetrics.rowWrap) or (debuffMetrics and debuffMetrics.rowWrap) or ReadPreviewEnum(context, "rowWrap", "DOWN", ROW_WRAP_OK),
        buffGrowthX = buffMetrics and buffMetrics.growth or ReadPreviewEnum(context, buffSpec and buffSpec.growthKey or "growth", "RIGHT", GROWTH_OK),
        buffGrowthY = buffMetrics and buffMetrics.rowWrap or ReadPreviewEnum(context, buffSpec and buffSpec.wrapKey or "rowWrap", "DOWN", ROW_WRAP_OK),
        debuffGrowthX = debuffMetrics and debuffMetrics.growth or ReadPreviewEnum(context, debuffSpec and debuffSpec.growthKey or "growth", "RIGHT", GROWTH_OK),
        debuffGrowthY = debuffMetrics and debuffMetrics.rowWrap or ReadPreviewEnum(context, debuffSpec and debuffSpec.wrapKey or "rowWrap", "DOWN", ROW_WRAP_OK),
        showStackCount = ReadPreviewBool(context, "showStackCount", true),
        showCooldownText = ReadPreviewBool(context, "showCooldownText", true),
        buffShowStackCount = ReadPreviewBool(context, "showStackCount", true, "buff"),
        buffShowCooldownText = ReadPreviewBool(context, "showCooldownText", true, "buff"),
        buffShowCooldownSwipe = ReadPreviewBool(context, "showCooldownSwipe", true, "buff"),
        buffCooldownSwipeReverse = ReadPreviewBool(context, "cooldownSwipeReverse", false, "buff"),
        buffShowStealable = ReadPreviewBool(context, "showStealable", false, "buff"),
        buffStealableStyle = ReadPreviewString(context, "stealableStyle", "BORDER_ICON", "buff"),
        debuffShowStackCount = ReadPreviewBool(context, "showStackCount", true, "debuff"),
        debuffShowCooldownText = ReadPreviewBool(context, "showCooldownText", true, "debuff"),
        debuffShowCooldownSwipe = ReadPreviewBool(context, "showCooldownSwipe", true, "debuff"),
        debuffCooldownSwipeReverse = ReadPreviewBool(context, "cooldownSwipeReverse", false, "debuff"),
        debuffTypeBorderMode = ReadDebuffModeFromTables(context.shared, context.sharedLayout),
        useDebuffTypeBorders = ReadPreviewBool(context, "useDebuffTypeBorders", false, "debuff"),
        stackAnchor = (runtimeCfg and runtimeCfg.stackAnchor) or ReadPreviewEnum(context, "stackCountAnchor", "TOPRIGHT", STACK_ANCHOR_OK),
        buffStackAnchor = ReadPreviewEnum(context, "stackCountAnchor", "TOPRIGHT", STACK_ANCHOR_OK, "buff"),
        debuffStackAnchor = ReadPreviewEnum(context, "stackCountAnchor", "TOPRIGHT", STACK_ANCHOR_OK, "debuff"),
        stackSize = ReadPreviewNumber(context, "stackTextSize", 14, 6, 40),
        stackX = ReadPreviewNumber(context, "stackTextOffsetX", -1, -2000, 2000),
        stackY = ReadPreviewNumber(context, "stackTextOffsetY", 1, -2000, 2000),
        cooldownSize = ReadPreviewNumber(context, "cooldownTextSize", 14, 6, 40),
        cooldownAnchor = ReadPreviewEnum(context, "cooldownTextAnchor", "CENTER", AURA_ANCHOR_OK),
        cooldownX = ReadPreviewNumber(context, "cooldownTextOffsetX", 0, -2000, 2000),
        cooldownY = ReadPreviewNumber(context, "cooldownTextOffsetY", 0, -2000, 2000),
        buffStackSize = ReadPreviewNumber(context, "stackTextSize", 14, 6, 40, "buff"),
        buffStackX = ReadPreviewNumber(context, "stackTextOffsetX", -1, -2000, 2000, "buff"),
        buffStackY = ReadPreviewNumber(context, "stackTextOffsetY", 1, -2000, 2000, "buff"),
        buffCooldownSize = ReadPreviewNumber(context, "cooldownTextSize", 14, 6, 40, "buff"),
        buffCooldownAnchor = ReadPreviewEnum(context, "cooldownTextAnchor", "CENTER", AURA_ANCHOR_OK, "buff"),
        buffCooldownX = ReadPreviewNumber(context, "cooldownTextOffsetX", 0, -2000, 2000, "buff"),
        buffCooldownY = ReadPreviewNumber(context, "cooldownTextOffsetY", 0, -2000, 2000, "buff"),
        buffCooldownDecimalSeconds = ReadPreviewNumber(context, "cooldownDecimalSeconds", 3, 0, 30, "buff"),
        buffShowDurationBar = ReadPreviewBool(context, "showDurationBar", false, "buff"),
        buffDurationBarHeight = ReadPreviewNumber(context, "durationBarHeight", 2, 1, 16, "buff"),
        buffDurationBarDisplay = NormalizeDurationBarDisplay(ReadPreviewValue(context, "durationBarDisplay", nil, "buff"), "BAR_ONLY"),
        buffDurationBarPosition = NormalizeDurationBarPosition(ReadPreviewValue(context, "durationBarPosition", nil, "buff"), "BOTTOM"),
        buffDurationBarDirection = NormalizeDurationBarDirection(ReadPreviewValue(context, "durationBarDirection", nil, "buff"), "REMAINING"),
        debuffStackSize = ReadPreviewNumber(context, "stackTextSize", 14, 6, 40, "debuff"),
        debuffStackX = ReadPreviewNumber(context, "stackTextOffsetX", -1, -2000, 2000, "debuff"),
        debuffStackY = ReadPreviewNumber(context, "stackTextOffsetY", 1, -2000, 2000, "debuff"),
        debuffCooldownSize = ReadPreviewNumber(context, "cooldownTextSize", 14, 6, 40, "debuff"),
        debuffCooldownAnchor = ReadPreviewEnum(context, "cooldownTextAnchor", "CENTER", AURA_ANCHOR_OK, "debuff"),
        debuffCooldownX = ReadPreviewNumber(context, "cooldownTextOffsetX", 0, -2000, 2000, "debuff"),
        debuffCooldownY = ReadPreviewNumber(context, "cooldownTextOffsetY", 0, -2000, 2000, "debuff"),
        debuffCooldownDecimalSeconds = ReadPreviewNumber(context, "cooldownDecimalSeconds", 3, 0, 30, "debuff"),
        debuffShowDurationBar = ReadPreviewBool(context, "showDurationBar", false, "debuff"),
        debuffDurationBarHeight = ReadPreviewNumber(context, "durationBarHeight", 2, 1, 16, "debuff"),
        debuffDurationBarDisplay = NormalizeDurationBarDisplay(ReadPreviewValue(context, "durationBarDisplay", nil, "debuff"), "BAR_ONLY"),
        debuffDurationBarPosition = NormalizeDurationBarPosition(ReadPreviewValue(context, "durationBarPosition", nil, "debuff"), "BOTTOM"),
        debuffDurationBarDirection = NormalizeDurationBarDirection(ReadPreviewValue(context, "durationBarDirection", nil, "debuff"), "REMAINING"),
    }
end

function Model.Apply(unit, reason)
    Model.InvalidateDefaultSeedCache()
    reason = reason or "AURAS3_MENU"
    local function IsGroupApplyScope(scope)
        scope = tostring(scope or ""):lower()
        return scope == "group" or scope == "groups"
            or scope == "party" or scope == "raid" or scope == "mythicraid"
            or scope == "gf_party" or scope == "gf_raid" or scope == "gf_mythicraid"
    end
    local normalizedScope = unit and NormalizeScope(unit) or "shared"
    local globalScope = (not unit) or normalizedScope == "shared" or IsGroupApplyScope(unit)
    if type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() == true then
        if type(A3._QueueDeferredAuraRuntime) == "function" then
            return A3._QueueDeferredAuraRuntime(unit or "shared", reason, false)
        end
        return false
    end
    if globalScope then
        -- A group edit must not discard unrelated Unit configuration caches.
        -- Standalone menu consumers keep the historical global fallback.
        local scopedGroup = unit and IsGroupApplyScope(unit)
            and type(A3.InvalidateGroupRuntimeConfig) == "function"
            and A3.InvalidateGroupRuntimeConfig(unit)
        if not scopedGroup and A3.BumpRuntimeConfig then A3.BumpRuntimeConfig() end
    end
    local function RefreshGroup(scope)
        if A3.RequestUnit then
            return A3.RequestUnit(scope)
        end
        local gf = MSUF and MSUF.GF
        if gf and type(gf.RefreshVisuals) == "function" then
            if scope == "party" or scope == "gf_party" then
                return gf.RefreshVisuals("party", gf.DIRTY_AURAS)
            elseif scope == "mythicraid" or scope == "gf_mythicraid" then
                return gf.RefreshVisuals("mythicraid", gf.DIRTY_AURAS)
            elseif scope == "raid" or scope == "gf_raid" then
                local didWork = gf.RefreshVisuals("raid", gf.DIRTY_AURAS)
                return gf.RefreshVisuals("mythicraid", gf.DIRTY_AURAS) or didWork
            end
            return gf.RefreshVisuals(nil, gf.DIRTY_AURAS)
        end
        return false
    end
    local function Refresh(runtimeUnit)
        -- RefreshUnit owns both the runtime lane and its Edit Mode follower.
        -- UpdateUnitAnchor is only the preview half of the same operation and
        -- calling both repaints every dummy twice.
        if type(A3.RefreshUnit) == "function" then
            A3.RefreshUnit(runtimeUnit)
        elseif type(A3.UpdateUnitAnchor) == "function" then
            A3.UpdateUnitAnchor(runtimeUnit)
        end
        return "OFF"
    end
    if unit and IsGroupApplyScope(unit) then
        RefreshGroup(unit)
    elseif unit and NormalizeScope(unit) ~= "shared" then
        EachRuntimeUnit(unit, Refresh)
    else
        Refresh("player")
        Refresh("target")
        Refresh("focus")
        for i = 1, #BOSS_UNITS do Refresh(BOSS_UNITS[i]) end
        for i = 1, #ARENA_UNITS do Refresh(ARENA_UNITS[i]) end
        RefreshGroup("group")
    end
    if type(A3._NotifyAuraColdpathPreview) == "function" then
        A3._NotifyAuraColdpathPreview(reason, unit or normalizedScope)
    elseif type(_G.MSUF_UFPreview_RequestRefresh) == "function" then
        _G.MSUF_UFPreview_RequestRefresh(reason)
    end
end
