-- Shared product appearance and per-unit lane presentation controls.
-- Presentation writes go through Storage/Model rather than editing raw profile
-- paths here. Content filters and custom spell lists remain separate owners.
-- Blizzard-frame visibility still uses its existing deferred apply boundary.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local Factories = MSUF.Auras3MenuModelFactories
if not Factories then
    Factories = {}
    MSUF.Auras3MenuModelFactories = Factories
end

function Factories.Appearance(A3, Model, Schema, Common, Storage)
    local type = type
    local tostring = tostring
    local math_floor = math.floor
    local AURA_ANCHORS = Schema.AURA_ANCHORS
    local AURA_ANCHOR_OK = Schema.AURA_ANCHOR_OK
    local DEBUFF_TYPE_BORDER_MODE_VALUES = Schema.DEBUFF_TYPE_BORDER_MODE_VALUES
    local DURATION_BAR_DIRECTION_OK = Schema.DURATION_BAR_DIRECTION_OK
    local DURATION_BAR_DIRECTION_VALUES = Schema.DURATION_BAR_DIRECTION_VALUES
    local DURATION_BAR_DISPLAY_OK = Schema.DURATION_BAR_DISPLAY_OK
    local DURATION_BAR_DISPLAY_VALUES = Schema.DURATION_BAR_DISPLAY_VALUES
    local DURATION_BAR_POSITION_OK = Schema.DURATION_BAR_POSITION_OK
    local DURATION_BAR_POSITION_VALUES = Schema.DURATION_BAR_POSITION_VALUES
    local FRAME_STRATA_OK = Schema.FRAME_STRATA_OK
    local GROUPS = Schema.GROUPS
    local GROWTH_OK = Schema.GROWTH_OK
    local GROWTH_VALUES = Schema.GROWTH_VALUES
    local LANE_GROWTH_PARTS = Schema.LANE_GROWTH_PARTS
    local LANE_GROWTH_VALUES = Schema.LANE_GROWTH_VALUES
    local LANE_STYLE_KEYS = Schema.LANE_STYLE_KEYS
    local PUBLIC_UNITS = Schema.PUBLIC_UNITS
    local ROW_WRAP_OK = Schema.ROW_WRAP_OK
    local ROW_WRAP_VALUES = Schema.ROW_WRAP_VALUES
    local STACK_ANCHORS = Schema.STACK_ANCHORS
    local STACK_ANCHOR_OK = Schema.STACK_ANCHOR_OK
    local STYLE_SCOPES = Schema.STYLE_SCOPES
    local STYLE_SHARED_LAYOUT_KEYS = Schema.STYLE_SHARED_LAYOUT_KEYS
    local ClampNumber = Common.ClampNumber
    local NormalizeDebuffTypeBorderMode = Common.NormalizeDebuffTypeBorderMode
    local NormalizeKind = Common.NormalizeKind
    local NormalizeScope = Common.NormalizeScope
    local Round = Common.Round
    local EffectiveLayoutTables = Storage.EffectiveLayoutTables
    local ReadKeyFromTables = Storage.ReadKeyFromTables

    function Model.PublicUnits()
        return PUBLIC_UNITS
    end

    function Model.StyleScopes()
        return STYLE_SCOPES
    end

    function Model.GrowthValues()
        return GROWTH_VALUES
    end

    function Model.RowWrapValues()
        return ROW_WRAP_VALUES
    end

    function Model.AuraAnchorValues()
        return AURA_ANCHORS
    end

    function Model.LaneGrowthValues()
        return LANE_GROWTH_VALUES
    end

    function Model.StackAnchorValues()
        return STACK_ANCHORS
    end

    function Model.DebuffTypeBorderModeValues()
        return DEBUFF_TYPE_BORDER_MODE_VALUES
    end

    --- Border styles for the shared aura icon style. Built fresh because
    --- LibSharedMedia borders can be registered after login; only ever called
    --- while a dropdown is opening.
    function Model.BorderStyleValues()
        local B = MSUF.BorderStyles
        if not (B and type(B.List) == "function") then
            return { { value = "SOLID", text = "Solid" } }
        end
        return B.List()
    end

    local SHARED_APPEARANCE_KINDS = {
        buff = true,
        debuff = true,
        playerDefensives = true,
        targetDots = true,
    }

    local function NormalizeSharedAppearanceKind(kind)
        kind = tostring(kind or "buff")
        if kind == "playerdefensives" then kind = "playerDefensives" end
        if kind == "targetdots" then kind = "targetDots" end
        return SHARED_APPEARANCE_KINDS[kind] and kind or "buff"
    end

    --- Shared Appearance is selected only by Aura product, never by Unit/Group
    --- frame. Legacy scalar values are materialized once by Defaults and are not
    --- active read owners afterwards.
    local function ReadIconShapeFromShared(shared, kind)
        local shapes = type(shared) == "table" and shared.appearanceIconShapes or nil
        local value = type(shapes) == "table" and shapes[kind] or nil
        value = tostring(value or (kind == "playerDefensives" and "FOLLOW_PORTRAIT" or "RECTANGLE"))
        return type(A3.NormalizeAuraIconShape) == "function" and A3.NormalizeAuraIconShape(value) or value
    end

    function Model.ReadSharedAppearanceIconShape(kind)
        kind = NormalizeSharedAppearanceKind(kind)
        local _, shared = Model.EnsureDB()
        return ReadIconShapeFromShared(shared, kind)
    end

    function Model.WriteSharedAppearanceIconShape(kind, value)
        kind = NormalizeSharedAppearanceKind(kind)
        local _, shared = Model.EnsureDB()
        if type(shared) ~= "table" then return false end
        shared.appearanceIconShapes = type(shared.appearanceIconShapes) == "table"
            and shared.appearanceIconShapes or {}
        value = tostring(value or "RECTANGLE")
        if type(A3.NormalizeAuraIconShape) == "function" then value = A3.NormalizeAuraIconShape(value) end
        if shared.appearanceIconShapes[kind] == value then return false end
        shared.appearanceIconShapes[kind] = value
        return true
    end

    --- Appearance values are global by Aura product. They deliberately have no
    --- UnitFrame/GroupFrame scope and no participation switch.
    function Model.ReadSharedAppearanceValue(kind, key, defaultValue)
        kind = NormalizeSharedAppearanceKind(kind)
        local _, shared = Model.EnsureDB()
        if type(shared) ~= "table" then return defaultValue end
        local styles = type(shared.appearanceIconStyles) == "table" and shared.appearanceIconStyles or nil
        local style = type(styles) == "table" and styles[kind] or nil
        if type(style) == "table" and style[key] ~= nil then return style[key] end
        return defaultValue
    end

    function Model.WriteSharedAppearanceValue(kind, key, value)
        kind = NormalizeSharedAppearanceKind(kind)
        local _, shared = Model.EnsureDB()
        if type(shared) ~= "table" then return false end
        shared.appearanceIconStyles = type(shared.appearanceIconStyles) == "table"
            and shared.appearanceIconStyles or {}
        local style = shared.appearanceIconStyles[kind]
        if type(style) ~= "table" then
            style = {}
            shared.appearanceIconStyles[kind] = style
        end
        if style[key] == value then return false end
        style[key] = value
        return true
    end

    function Model.ReadSharedAppearanceBool(kind, key, defaultValue)
        return Model.ReadSharedAppearanceValue(kind, key, defaultValue and true or false) == true
    end

    function Model.WriteSharedAppearanceBool(kind, key, value)
        return Model.WriteSharedAppearanceValue(kind, key, value == true)
    end

    --- Buff and Debuff Appearance mirror these two profile-wide values. The
    --- controls stay synchronized between pages while each Blizzard frame remains
    --- independently configurable.
    local function EnsureBlizzardAuraFrameSettings(shared)
        if type(shared) ~= "table" then return end
        local legacy = shared.hideBlizzardAuraFrames
        if legacy ~= nil then
            if shared.hideBlizzardBuffFrame == nil then
                shared.hideBlizzardBuffFrame = legacy == true
            end
            if shared.hideBlizzardDebuffFrame == nil then
                shared.hideBlizzardDebuffFrame = legacy == true
            end
            shared.hideBlizzardAuraFrames = nil
        end
    end

    local function ReadHideBlizzardAuraFrame(key)
        local _, shared = Model.EnsureDB()
        EnsureBlizzardAuraFrameSettings(shared)
        return type(shared) == "table" and shared[key] == true
    end

    local function WriteHideBlizzardAuraFrame(key, value)
        local _, shared = Model.EnsureDB()
        if type(shared) ~= "table" then return false end
        EnsureBlizzardAuraFrameSettings(shared)
        value = value == true
        local changed = shared[key] ~= value
        shared[key] = value
        local UF = MSUF and MSUF.UF
        if UF and type(UF.ApplyBlizzardAuraVisibility) == "function" then
            UF.ApplyBlizzardAuraVisibility()
        end
        return changed
    end

    function Model.ReadHideBlizzardBuffFrame()
        return ReadHideBlizzardAuraFrame("hideBlizzardBuffFrame")
    end

    function Model.WriteHideBlizzardBuffFrame(value)
        return WriteHideBlizzardAuraFrame("hideBlizzardBuffFrame", value)
    end

    function Model.ReadHideBlizzardDebuffFrame()
        return ReadHideBlizzardAuraFrame("hideBlizzardDebuffFrame")
    end

    function Model.WriteHideBlizzardDebuffFrame(value)
        return WriteHideBlizzardAuraFrame("hideBlizzardDebuffFrame", value)
    end

    function Model.ReadSharedAppearanceNumber(kind, key, defaultValue, minValue, maxValue)
        return ClampNumber(Model.ReadSharedAppearanceValue(kind, key, defaultValue), defaultValue, minValue, maxValue)
    end

    function Model.WriteSharedAppearanceNumber(kind, key, value, minValue, maxValue)
        value = ClampNumber(value, 0, minValue, maxValue)
        if math_floor(value) == value then value = Round(value) end
        return Model.WriteSharedAppearanceValue(kind, key, value)
    end

    function Model.ReadSharedAppearanceBorderStyle(kind)
        local B = MSUF.BorderStyles
        local value = Model.ReadSharedAppearanceValue(kind, "styleBorderStyle", "SOLID")
        if B and type(B.Normalize) == "function" then return B.Normalize(value) end
        return type(value) == "string" and value ~= "" and value or "SOLID"
    end

    function Model.WriteSharedAppearanceBorderStyle(kind, value)
        local B = MSUF.BorderStyles
        if B and type(B.Normalize) == "function" then value = B.Normalize(value) end
        return Model.WriteSharedAppearanceValue(kind, "styleBorderStyle", value)
    end

    function Model.DurationBarDisplayValues()
        return DURATION_BAR_DISPLAY_VALUES
    end

    function Model.DurationBarPositionValues()
        return DURATION_BAR_POSITION_VALUES
    end

    function Model.DurationBarDirectionValues()
        return DURATION_BAR_DIRECTION_VALUES
    end

    function Model.ScopeLabel(scope)
        scope = NormalizeScope(scope)
        if scope == "shared" then return "Shared" end
        if scope == "player" then return "Player" end
        if scope == "target" then return "Target" end
        if scope == "focus" then return "Focus" end
        if scope == "arena" then return "Arena" end
        return "Boss"
    end

    function Model.ReadGrowth(unit)
        local v = tostring(Model.ReadValue(unit, "growth", "RIGHT") or "RIGHT")
        return GROWTH_OK[v] and v or "RIGHT"
    end

    function Model.WriteGrowth(unit, value)
        value = GROWTH_OK[value] and value or "RIGHT"
        Model.WriteValue(unit, "growth", value)
    end

    function Model.ReadRowWrap(unit)
        local v = tostring(Model.ReadValue(unit, "rowWrap", "DOWN") or "DOWN")
        return ROW_WRAP_OK[v] and v or "DOWN"
    end

    function Model.WriteRowWrap(unit, value)
        value = ROW_WRAP_OK[value] and value or "DOWN"
        Model.WriteValue(unit, "rowWrap", value)
    end

    function Model.ReadLanePerRow(unit, kind)
        kind = NormalizeKind(kind)
        local spec = GROUPS[kind]
        return Model.ReadNumber(unit, spec and spec.perRowKey or "perRow", 12, 1, 40)
    end

    function Model.WriteLanePerRow(unit, kind, value)
        kind = NormalizeKind(kind)
        local spec = GROUPS[kind]
        Model.WriteNumber(unit, spec and spec.perRowKey or "perRow", value, 1, 40)
    end

    function Model.ReadLaneSpacing(unit, kind)
        kind = NormalizeKind(kind)
        local spec = GROUPS[kind]
        return Model.ReadNumber(unit, spec and spec.spacingKey or "spacing", 2, 0, 64)
    end

    function Model.WriteLaneSpacing(unit, kind, value)
        kind = NormalizeKind(kind)
        local spec = GROUPS[kind]
        Model.WriteNumber(unit, spec and spec.spacingKey or "spacing", value, 0, 64)
    end

    function Model.ReadLaneGrowth(unit, kind)
        kind = NormalizeKind(kind)
        local spec = GROUPS[kind]
        local fallback = "RIGHT"
        local v = tostring(Model.ReadValue(unit, spec and spec.growthKey or "growth", fallback) or fallback)
        return GROWTH_OK[v] and v or fallback
    end

    function Model.WriteLaneGrowth(unit, kind, value)
        kind = NormalizeKind(kind)
        local spec = GROUPS[kind]
        value = GROWTH_OK[value] and value or "RIGHT"
        Model.WriteValue(unit, spec and spec.growthKey or "growth", value)
    end

    function Model.ReadLaneGrowthPair(unit, kind)
        kind = NormalizeKind(kind)
        local growth = Model.ReadLaneGrowth(unit, kind)
        if growth == "UP" or growth == "DOWN" then return growth end
        local rowWrap = Model.ReadLaneRowWrap(unit, kind)
        local pair = tostring(growth or "RIGHT") .. tostring(rowWrap or "DOWN")
        return LANE_GROWTH_PARTS[pair] and pair or "RIGHTDOWN"
    end

    function Model.WriteLaneGrowthPair(unit, kind, value)
        kind = NormalizeKind(kind)
        local parts = LANE_GROWTH_PARTS[value] or LANE_GROWTH_PARTS.RIGHTDOWN
        Model.WriteLaneGrowth(unit, kind, parts[1])
        Model.WriteLaneRowWrap(unit, kind, parts[2])
    end

    function Model.ReadLaneRowWrap(unit, kind)
        kind = NormalizeKind(kind)
        local spec = GROUPS[kind]
        local fallback = "DOWN"
        local v = tostring(Model.ReadValue(unit, spec and spec.wrapKey or "rowWrap", fallback) or fallback)
        return ROW_WRAP_OK[v] and v or fallback
    end

    function Model.WriteLaneRowWrap(unit, kind, value)
        kind = NormalizeKind(kind)
        local spec = GROUPS[kind]
        value = ROW_WRAP_OK[value] and value or "DOWN"
        Model.WriteValue(unit, spec and spec.wrapKey or "rowWrap", value)
    end

    function Model.ReadLaneAnchor(unit, kind)
        kind = NormalizeKind(kind)
        local spec = GROUPS[kind]
        local fallback = spec and spec.defaultAnchor or "TOPLEFT"
        local value = tostring(Model.ReadValue(unit, spec and spec.anchorKey or "buffAnchor", fallback) or fallback)
        return AURA_ANCHOR_OK[value] and value or fallback
    end

    function Model.WriteLaneAnchor(unit, kind, value)
        kind = NormalizeKind(kind)
        local spec = GROUPS[kind]
        value = AURA_ANCHOR_OK[value] and value or (spec and spec.defaultAnchor) or "TOPLEFT"
        Model.WriteValue(unit, spec and spec.anchorKey or "buffAnchor", value)
    end

    function Model.ReadLaneLayer(unit, kind)
        kind = NormalizeKind(kind)
        local spec = GROUPS[kind]
        return Model.ReadNumber(unit, spec and spec.layerKey or "buffLayer", spec and spec.defaultLayer or 5, 0, 30)
    end

    function Model.ReadLaneStrata(unit, kind)
        kind = NormalizeKind(kind)
        local spec = GROUPS[kind]
        local value = tostring(Model.ReadValue(unit, spec and spec.strataKey or "buffStrata", "AUTO") or "AUTO"):upper()
        return FRAME_STRATA_OK[value] and value or "AUTO"
    end

    function Model.WriteLaneLayer(unit, kind, value)
        kind = NormalizeKind(kind)
        local spec = GROUPS[kind]
        Model.WriteNumber(unit, spec and spec.layerKey or "buffLayer", value, 0, 30)
    end

    function Model.WriteLaneStrata(unit, kind, value)
        kind = NormalizeKind(kind)
        local spec = GROUPS[kind]
        value = tostring(value or "AUTO"):upper()
        if not FRAME_STRATA_OK[value] then value = "AUTO" end
        Model.WriteValue(unit, spec and spec.strataKey or "buffStrata", value)
    end

    function Model.ReadStackAnchor(unit)
        local v = tostring(Model.ReadValue(unit, "stackCountAnchor", "TOPRIGHT") or "TOPRIGHT")
        return STACK_ANCHOR_OK[v] and v or "TOPRIGHT"
    end

    function Model.WriteStackAnchor(unit, value)
        value = STACK_ANCHOR_OK[value] and value or "TOPRIGHT"
        Model.WriteValue(unit, "stackCountAnchor", value)
    end

    local function LaneStyleKey(kind, key)
        kind = NormalizeKind(kind)
        local map = LANE_STYLE_KEYS[kind]
        return map and map[key] or key
    end

    local function ReadLaneStyleRaw(unit, kind, key)
        local auras, shared = Model.EnsureDB()
        if type(shared) ~= "table" then return nil end
        local laneKey = LaneStyleKey(kind, key)
        if NormalizeScope(unit) == "shared" then return shared[laneKey] end
        local layout, sharedLayout = EffectiveLayoutTables(auras, unit)
        local localOwner = STYLE_SHARED_LAYOUT_KEYS[laneKey] and sharedLayout or layout
        if type(localOwner) == "table" then
            return localOwner[laneKey]
        end
        return nil
    end

    function Model.ReadLaneStyleBool(unit, kind, key, defaultValue)
        local value = ReadLaneStyleRaw(unit, kind, key)
        if value == nil then return defaultValue and true or false end
        return value == true
    end

    function Model.WriteLaneStyleBool(unit, kind, key, value)
        Model.WriteValue(unit, LaneStyleKey(kind, key), value and true or false)
    end

    function Model.ReadLaneStyleString(unit, kind, key, defaultValue)
        if key == "iconShape" then
            return Model.ReadSharedAppearanceIconShape(kind)
        end
        local value = ReadLaneStyleRaw(unit, kind, key)
        return tostring(value or defaultValue or "")
    end

    function Model.WriteLaneStyleString(unit, kind, key, value)
        if key == "iconShape" then
            Model.WriteSharedAppearanceIconShape(kind, value)
            return
        end
        Model.WriteValue(unit, LaneStyleKey(kind, key), tostring(value or ""))
    end

    local function ReadDebuffModeFromTables(shared, sharedLayout)
        if type(shared) ~= "table" then return "OFF" end
        if type(sharedLayout) == "table" then
            local storedMode = sharedLayout.debuffTypeBorderMode
            if storedMode == nil then storedMode = sharedLayout.dispelBorderMode end
            if storedMode ~= nil then
                local mode = NormalizeDebuffTypeBorderMode(storedMode, "OFF")
                return (mode == "OFF" and sharedLayout.useDebuffTypeBorders == true) and "SYMBOL" or mode
            end
            if sharedLayout.useDebuffTypeBorders ~= nil then
                return sharedLayout.useDebuffTypeBorders == true and "SYMBOL" or "OFF"
            end
        end
        local storedMode = shared.debuffTypeBorderMode
        if storedMode == nil then storedMode = shared.dispelBorderMode end
        if storedMode ~= nil then
            local mode = NormalizeDebuffTypeBorderMode(storedMode, "OFF")
            return (mode == "OFF" and shared.useDebuffTypeBorders == true) and "SYMBOL" or mode
        end
        return shared.useDebuffTypeBorders == true and "SYMBOL" or "OFF"
    end

    function Model.ReadDebuffTypeBorderMode(unit)
        local auras, shared = Model.EnsureDB()
        local sharedLayout
        if type(shared) == "table" and NormalizeScope(unit) ~= "shared" then
            local layout
            layout, sharedLayout = EffectiveLayoutTables(auras, unit)
        end
        return ReadDebuffModeFromTables(shared, sharedLayout)
    end

    function Model.WriteDebuffTypeBorderMode(unit, value)
        value = NormalizeDebuffTypeBorderMode(value, "OFF")
        Model.WriteValue(unit, "debuffTypeBorderMode", value)
        Model.WriteValue(unit, "useDebuffTypeBorders", value ~= "OFF")
    end

    function Model.ReadLaneStyleNumber(unit, kind, key, defaultValue, minValue, maxValue)
        local value = ReadLaneStyleRaw(unit, kind, key)
        return ClampNumber(value, defaultValue, minValue, maxValue)
    end

    function Model.WriteLaneStyleNumber(unit, kind, key, value, minValue, maxValue)
        value = ClampNumber(value, 0, minValue, maxValue)
        if math_floor(value) == value then value = Round(value) end
        Model.WriteValue(unit, LaneStyleKey(kind, key), value)
    end

    function Model.ReadLaneStackAnchor(unit, kind)
        local value = tostring(ReadLaneStyleRaw(unit, kind, "stackCountAnchor") or "TOPRIGHT")
        return STACK_ANCHOR_OK[value] and value or "TOPRIGHT"
    end

    function Model.WriteLaneStackAnchor(unit, kind, value)
        value = STACK_ANCHOR_OK[value] and value or "TOPRIGHT"
        Model.WriteValue(unit, LaneStyleKey(kind, "stackCountAnchor"), value)
    end

    function Model.ReadCooldownAnchor(unit)
        local v = tostring(Model.ReadValue(unit, "cooldownTextAnchor", "CENTER") or "CENTER")
        return AURA_ANCHOR_OK[v] and v or "CENTER"
    end

    function Model.WriteCooldownAnchor(unit, value)
        value = AURA_ANCHOR_OK[value] and value or "CENTER"
        Model.WriteValue(unit, "cooldownTextAnchor", value)
    end

    function Model.ReadLaneCooldownAnchor(unit, kind)
        local value = tostring(ReadLaneStyleRaw(unit, kind, "cooldownTextAnchor") or "CENTER")
        return AURA_ANCHOR_OK[value] and value or "CENTER"
    end

    function Model.WriteLaneCooldownAnchor(unit, kind, value)
        value = AURA_ANCHOR_OK[value] and value or "CENTER"
        Model.WriteValue(unit, LaneStyleKey(kind, "cooldownTextAnchor"), value)
    end

    local function NormalizeDurationBarPosition(value, fallback)
        value = tostring(value or fallback or "BOTTOM"):upper()
        return DURATION_BAR_POSITION_OK[value] and value or "BOTTOM"
    end

    local function NormalizeDurationBarDirection(value, fallback)
        value = tostring(value or fallback or "REMAINING"):upper()
        if value == "ELAPSED_TIME" then value = "ELAPSED" end
        return DURATION_BAR_DIRECTION_OK[value] and value or "REMAINING"
    end

    local function NormalizeDurationBarDisplay(value, fallback)
        value = tostring(value or fallback or "BAR_ONLY"):upper()
        if value == "ICON" or value == "ICONS" or value == "ICON_BAR" or value == "ICON+BAR" then value = "OVERLAY" end
        return DURATION_BAR_DISPLAY_OK[value] and value or "BAR_ONLY"
    end

    function Model.ReadLaneDurationBarPosition(unit, kind)
        local value = ReadLaneStyleRaw(unit, kind, "durationBarPosition")
        return NormalizeDurationBarPosition(value, "BOTTOM")
    end

    function Model.WriteLaneDurationBarPosition(unit, kind, value)
        Model.WriteValue(unit, LaneStyleKey(kind, "durationBarPosition"), NormalizeDurationBarPosition(value, "BOTTOM"))
    end

    function Model.ReadLaneDurationBarDirection(unit, kind)
        local value = ReadLaneStyleRaw(unit, kind, "durationBarDirection")
        return NormalizeDurationBarDirection(value, "REMAINING")
    end

    function Model.WriteLaneDurationBarDirection(unit, kind, value)
        Model.WriteValue(unit, LaneStyleKey(kind, "durationBarDirection"), NormalizeDurationBarDirection(value, "REMAINING"))
    end

    function Model.ReadLaneDurationBarDisplay(unit, kind)
        local value = ReadLaneStyleRaw(unit, kind, "durationBarDisplay")
        return NormalizeDurationBarDisplay(value, "BAR_ONLY")
    end

    function Model.WriteLaneDurationBarDisplay(unit, kind, value)
        Model.WriteValue(unit, LaneStyleKey(kind, "durationBarDisplay"), NormalizeDurationBarDisplay(value, "BAR_ONLY"))
    end

    function Model.GroupShown(unit, kind)
        kind = NormalizeKind(kind)
        local spec = GROUPS[kind]
        if not spec or Model.ReadBool(unit, spec.showKey, true) ~= true then return false end
        return Model.ReadNumber(unit, spec.maxKey, 12, 0, 80) > 0
    end

    function Model.SetGroupShown(unit, kind, shown)
        kind = NormalizeKind(kind)
        local spec = GROUPS[kind]
        if not spec then return end
        Model.WriteBool(unit, spec.showKey, shown == true)
        if shown then
            if Model.ReadNumber(unit, spec.maxKey, 0, 0, 80) <= 0 then
                Model.WriteNumber(unit, spec.maxKey, kind == "buff" and 8 or 12, 0, 80)
            end
        end
    end

    -- Preview readers share the same key ownership and normalization as the
    -- public getters, but use an already-resolved scope. No per-field DB reads,
    -- temporary closures, persistent cache, or dynamic property dispatcher.
    local function ReadPreviewValue(context, key, fallback, kind)
        local value
        if kind then
            local map = LANE_STYLE_KEYS[kind]
            local laneKey = map and map[key] or key
            local owner = STYLE_SHARED_LAYOUT_KEYS[laneKey] and context.sharedLayout or context.layout
            value = owner and owner[laneKey]
        else
            value = ReadKeyFromTables(context.layout, context.sharedLayout, key)
        end
        if value ~= nil then return value end
        return fallback
    end
    local function ReadPreviewNumber(context, key, fallback, minValue, maxValue, kind)
        return ClampNumber(ReadPreviewValue(context, key, nil, kind), fallback, minValue, maxValue)
    end
    local function ReadPreviewBool(context, key, fallback, kind)
        return ReadPreviewValue(context, key, fallback and true or false, kind) == true
    end
    local function ReadPreviewString(context, key, fallback, kind)
        if key == "iconShape" and kind then return ReadIconShapeFromShared(context.shared, kind) end
        return tostring(ReadPreviewValue(context, key, nil, kind) or fallback or "")
    end
    local function ReadPreviewEnum(context, key, fallback, values, kind)
        local value = ReadPreviewString(context, key, fallback, kind)
        return values[value] and value or fallback
    end

    return {
        ReadPreviewNumber = ReadPreviewNumber,
        ReadPreviewBool = ReadPreviewBool,
        ReadPreviewString = ReadPreviewString,
        ReadPreviewEnum = ReadPreviewEnum,
        ReadPreviewValue = ReadPreviewValue,
        ReadDebuffModeFromTables = ReadDebuffModeFromTables,
        NormalizeDurationBarPosition = NormalizeDurationBarPosition,
        NormalizeDurationBarDirection = NormalizeDurationBarDirection,
        NormalizeDurationBarDisplay = NormalizeDurationBarDisplay,
    }
end
