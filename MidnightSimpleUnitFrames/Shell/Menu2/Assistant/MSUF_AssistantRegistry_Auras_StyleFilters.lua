-- Assistant Auras style/filter registry shard.
-- Loaded before MSUF_AssistantRegistry_Auras.lua; the main domain passes DB and registry helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.RegisterStyleAndFilterSettings(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local AURA_SCOPES = ctx.AURA_SCOPES or {}
    local AURA_LANES = ctx.AURA_LANES or {}
    local AURA_ANCHOR_VALUES = ctx.AURA_ANCHOR_VALUES or {}
    local AURA_ANCHOR_ALIASES = ctx.AURA_ANCHOR_ALIASES or {}
    local AURA_STACK_ANCHOR_VALUES = ctx.AURA_STACK_ANCHOR_VALUES or {}
    local AURA_STACK_ANCHOR_ALIASES = ctx.AURA_STACK_ANCHOR_ALIASES or {}
    local AURA_COOLDOWN_SWIPE_DIRECTION_VALUES = ctx.AURA_COOLDOWN_SWIPE_DIRECTION_VALUES or {}
    local AURA_COOLDOWN_SWIPE_DIRECTION_ALIASES = ctx.AURA_COOLDOWN_SWIPE_DIRECTION_ALIASES or {}
    local AURA_DURATION_BAR_POSITION_VALUES = ctx.AURA_DURATION_BAR_POSITION_VALUES or {}
    local AURA_DURATION_BAR_POSITION_ALIASES = ctx.AURA_DURATION_BAR_POSITION_ALIASES or {}
    local AURA_DURATION_BAR_DISPLAY_VALUES = ctx.AURA_DURATION_BAR_DISPLAY_VALUES or {}
    local AURA_DURATION_BAR_DISPLAY_ALIASES = ctx.AURA_DURATION_BAR_DISPLAY_ALIASES or {}
    local AURA_DURATION_BAR_DIRECTION_VALUES = ctx.AURA_DURATION_BAR_DIRECTION_VALUES or {}
    local AURA_DURATION_BAR_DIRECTION_ALIASES = ctx.AURA_DURATION_BAR_DIRECTION_ALIASES or {}
    local AURA_LANE_STYLE_BOOLEAN_SPECS = ctx.AURA_LANE_STYLE_BOOLEAN_SPECS or {}
    local AURA_LANE_STYLE_NUMBER_SPECS = ctx.AURA_LANE_STYLE_NUMBER_SPECS or {}
    local AURA_DEBUFF_TYPE_BORDER_VALUES = ctx.AURA_DEBUFF_TYPE_BORDER_VALUES or {}
    local AURA_DEBUFF_TYPE_BORDER_ALIASES = ctx.AURA_DEBUFF_TYPE_BORDER_ALIASES or {}
    local AddAliasesForAuraScope = ctx.AddAliasesForAuraScope
    local AddAuraLaneAliases = ctx.AddAuraLaneAliases
    local AuraScopeLabel = ctx.AuraScopeLabel
    local RegisterAuraScopeBoolean = ctx.RegisterAuraScopeBoolean
    local RegisterAuraScopeNumber = ctx.RegisterAuraScopeNumber
    local RegisterAuraScopeEnum = ctx.RegisterAuraScopeEnum
    local RegisterAuraScopeLaneBoolean = ctx.RegisterAuraScopeLaneBoolean
    local RegisterAuraScopeLaneNumber = ctx.RegisterAuraScopeLaneNumber
    local RegisterAuraScopeLaneEnum = ctx.RegisterAuraScopeLaneEnum
    local AuraSharedBool = ctx.AuraSharedBool
    local SetAuraSharedBool = ctx.SetAuraSharedBool
    local AuraReadNumber = ctx.AuraReadNumber
    local AuraWriteNumber = ctx.AuraWriteNumber
    local AuraReadStackAnchor = ctx.AuraReadStackAnchor
    local AuraWriteStackAnchor = ctx.AuraWriteStackAnchor
    local AuraReadCooldownAnchor = ctx.AuraReadCooldownAnchor
    local AuraWriteCooldownAnchor = ctx.AuraWriteCooldownAnchor
    local AuraReadLaneStyleBool = ctx.AuraReadLaneStyleBool
    local AuraWriteLaneStyleBool = ctx.AuraWriteLaneStyleBool
    local AuraReadLaneStyleNumber = ctx.AuraReadLaneStyleNumber
    local AuraWriteLaneStyleNumber = ctx.AuraWriteLaneStyleNumber
    local AuraReadLaneStackAnchor = ctx.AuraReadLaneStackAnchor
    local AuraWriteLaneStackAnchor = ctx.AuraWriteLaneStackAnchor
    local AuraReadLaneCooldownAnchor = ctx.AuraReadLaneCooldownAnchor
    local AuraWriteLaneCooldownAnchor = ctx.AuraWriteLaneCooldownAnchor
    local AuraUseSharedVisuals = ctx.AuraUseSharedVisuals
    local AuraSetUseSharedVisuals = ctx.AuraSetUseSharedVisuals
    local AuraUseSharedRules = ctx.AuraUseSharedRules
    local AuraSetUseSharedRules = ctx.AuraSetUseSharedRules
    local AuraModel = ctx.AuraModel
    local ApplyAura = ctx.ApplyAura

    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(AddAliasesForAuraScope) ~= "function" or type(AddAuraLaneAliases) ~= "function" then return end
    if type(AuraScopeLabel) ~= "function" or type(RegisterAuraScopeBoolean) ~= "function" then return end

    if #AURA_DEBUFF_TYPE_BORDER_VALUES == 0 then
        AURA_DEBUFF_TYPE_BORDER_VALUES = { "OFF", "BORDER", "SYMBOL" }
    end
    if #AURA_COOLDOWN_SWIPE_DIRECTION_VALUES == 0 then
        AURA_COOLDOWN_SWIPE_DIRECTION_VALUES = { "NORMAL", "REVERSE" }
    end
    if #AURA_DURATION_BAR_POSITION_VALUES == 0 then
        AURA_DURATION_BAR_POSITION_VALUES = { "BOTTOM", "TOP" }
    end
    if #AURA_DURATION_BAR_DISPLAY_VALUES == 0 then
        AURA_DURATION_BAR_DISPLAY_VALUES = { "BAR_ONLY", "OVERLAY" }
    end
    if #AURA_DURATION_BAR_DIRECTION_VALUES == 0 then
        AURA_DURATION_BAR_DIRECTION_VALUES = { "REMAINING", "ELAPSED" }
    end
    local debuffBorderAllowed = {}
    for i = 1, #AURA_DEBUFF_TYPE_BORDER_VALUES do debuffBorderAllowed[AURA_DEBUFF_TYPE_BORDER_VALUES[i]] = true end

    local durationBarPositionAllowed = {}
    for i = 1, #AURA_DURATION_BAR_POSITION_VALUES do durationBarPositionAllowed[AURA_DURATION_BAR_POSITION_VALUES[i]] = true end
    local durationBarDisplayAllowed = {}
    for i = 1, #AURA_DURATION_BAR_DISPLAY_VALUES do durationBarDisplayAllowed[AURA_DURATION_BAR_DISPLAY_VALUES[i]] = true end
    local durationBarDirectionAllowed = {}
    for i = 1, #AURA_DURATION_BAR_DIRECTION_VALUES do durationBarDirectionAllowed[AURA_DURATION_BAR_DIRECTION_VALUES[i]] = true end

    local function NormalizeDebuffTypeBorderMode(value)
        value = tostring(value or "OFF")
        return debuffBorderAllowed[value] and value or "OFF"
    end

    local function LaneStyleKey(lane, key)
        local prefix = lane == "buff" and "buff" or "debuff"
        return prefix .. key:sub(1, 1):upper() .. key:sub(2)
    end

    local function NormalizeDurationBarPosition(value)
        value = tostring(value or "BOTTOM"):upper()
        return durationBarPositionAllowed[value] and value or "BOTTOM"
    end

    local function NormalizeDurationBarDisplay(value)
        value = tostring(value or "BAR_ONLY"):upper()
        if value == "ICON" or value == "ICON_BAR" then value = "OVERLAY" end
        return durationBarDisplayAllowed[value] and value or "BAR_ONLY"
    end

    local function NormalizeDurationBarDirection(value)
        value = tostring(value or "REMAINING"):upper()
        if value == "ELAPSED_TIME" then value = "ELAPSED" end
        return durationBarDirectionAllowed[value] and value or "REMAINING"
    end

    local function AuraReadLaneDurationBarPosition(scope, lane)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.ReadLaneDurationBarPosition) == "function" then
            return NormalizeDurationBarPosition(Model.ReadLaneDurationBarPosition(scope, lane))
        end
        if Model and type(Model.ReadValue) == "function" then
            local laneKey = LaneStyleKey(lane, "durationBarPosition")
            local value = Model.ReadValue(scope, laneKey, nil)
            if value == nil then value = Model.ReadValue(scope, "durationBarPosition", "BOTTOM") end
            return NormalizeDurationBarPosition(value)
        end
        return "BOTTOM"
    end

    local function AuraWriteLaneDurationBarPosition(scope, lane, value)
        value = NormalizeDurationBarPosition(value)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.WriteLaneDurationBarPosition) == "function" then
            Model.WriteLaneDurationBarPosition(scope, lane, value)
            return
        end
        if Model and type(Model.WriteValue) == "function" then
            Model.WriteValue(scope, LaneStyleKey(lane, "durationBarPosition"), value)
        end
    end

    local function AuraReadLaneDurationBarDisplay(scope, lane)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.ReadLaneDurationBarDisplay) == "function" then
            return NormalizeDurationBarDisplay(Model.ReadLaneDurationBarDisplay(scope, lane))
        end
        if Model and type(Model.ReadValue) == "function" then
            local laneKey = LaneStyleKey(lane, "durationBarDisplay")
            local value = Model.ReadValue(scope, laneKey, nil)
            if value == nil then value = Model.ReadValue(scope, "durationBarDisplay", "BAR_ONLY") end
            return NormalizeDurationBarDisplay(value)
        end
        return "BAR_ONLY"
    end

    local function AuraWriteLaneDurationBarDisplay(scope, lane, value)
        value = NormalizeDurationBarDisplay(value)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.WriteLaneDurationBarDisplay) == "function" then
            Model.WriteLaneDurationBarDisplay(scope, lane, value)
            return
        end
        if Model and type(Model.WriteValue) == "function" then
            Model.WriteValue(scope, LaneStyleKey(lane, "durationBarDisplay"), value)
        end
    end

    local function AuraReadLaneDurationBarDirection(scope, lane)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.ReadLaneDurationBarDirection) == "function" then
            return NormalizeDurationBarDirection(Model.ReadLaneDurationBarDirection(scope, lane))
        end
        if Model and type(Model.ReadValue) == "function" then
            local laneKey = LaneStyleKey(lane, "durationBarDirection")
            local value = Model.ReadValue(scope, laneKey, nil)
            if value == nil then value = Model.ReadValue(scope, "durationBarDirection", "REMAINING") end
            return NormalizeDurationBarDirection(value)
        end
        return "REMAINING"
    end

    local function AuraWriteLaneDurationBarDirection(scope, lane, value)
        value = NormalizeDurationBarDirection(value)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.WriteLaneDurationBarDirection) == "function" then
            Model.WriteLaneDurationBarDirection(scope, lane, value)
            return
        end
        if Model and type(Model.WriteValue) == "function" then
            Model.WriteValue(scope, LaneStyleKey(lane, "durationBarDirection"), value)
        end
    end

    local function AuraReadStyleBool(scope, key, defaultValue)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.ReadBool) == "function" then return Model.ReadBool(scope, key, defaultValue) end
        return AuraSharedBool(key, defaultValue)
    end

    local function AuraWriteStyleBool(scope, key, value)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.WriteBool) == "function" then
            Model.WriteBool(scope, key, value)
            return
        end
        SetAuraSharedBool(key, value)
    end

    local function AuraReadDebuffTypeBorderMode(scope)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.ReadDebuffTypeBorderMode) == "function" then
            return NormalizeDebuffTypeBorderMode(Model.ReadDebuffTypeBorderMode(scope))
        end
        return AuraReadLaneStyleBool(scope, "debuff", "useDebuffTypeBorders", false) and "SYMBOL" or "OFF"
    end

    local function AuraWriteDebuffTypeBorderMode(scope, value)
        value = NormalizeDebuffTypeBorderMode(value)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.WriteDebuffTypeBorderMode) == "function" then
            Model.WriteDebuffTypeBorderMode(scope, value)
            return
        end
        AuraWriteLaneStyleBool(scope, "debuff", "useDebuffTypeBorders", value ~= "OFF")
    end

    for _, scope in ipairs(AURA_SCOPES) do
        local aliases = {}
        AddAliasesForAuraScope(aliases, scope, "show stack count")
        AddAliasesForAuraScope(aliases, scope, "stack count")
        RegisterAuraScopeBoolean(scope, "showStackCount", "Show Stack Count", true, aliases,
            function() return AuraSharedBool("showStackCount", true) end,
            function(value) SetAuraSharedBool("showStackCount", value) end,
            true)

        aliases = {}
        AddAliasesForAuraScope(aliases, scope, "show cooldown text")
        AddAliasesForAuraScope(aliases, scope, "cooldown text")
        RegisterAuraScopeBoolean(scope, "showCooldownText", "Show Cooldown Text", true, aliases,
            function() return AuraSharedBool("showCooldownText", true) end,
            function(value) SetAuraSharedBool("showCooldownText", value) end,
            true)

        aliases = {}
        AddAliasesForAuraScope(aliases, scope, "show cooldown swipe")
        AddAliasesForAuraScope(aliases, scope, "cooldown swipe")
        RegisterAuraScopeBoolean(scope, "showCooldownSwipe", "Show Cooldown Swipe", true, aliases,
            function() return AuraSharedBool("showCooldownSwipe", true) end,
            function(value) SetAuraSharedBool("showCooldownSwipe", value) end,
            true)

        if scope ~= "shared" then
            aliases = {}
            AddAliasesForAuraScope(aliases, scope, "show tooltip")
            AddAliasesForAuraScope(aliases, scope, "tooltip")
            AddAliasesForAuraScope(aliases, scope, "aura tooltip")
            AddAliasesForAuraScope(aliases, scope, "aura tooltips")
            RegisterAuraScopeBoolean(scope, "showTooltip", "Aura Tooltips", true, aliases,
                function() return AuraReadStyleBool(scope, "showTooltip", true) end,
                function(value) AuraWriteStyleBool(scope, "showTooltip", value) end,
                true)
        end

        aliases = {}
        AddAliasesForAuraScope(aliases, scope, "debuff type border")
        AddAliasesForAuraScope(aliases, scope, "debuff border mode")
        AddAliasesForAuraScope(aliases, scope, "dispel type border")
        AddAliasesForAuraScope(aliases, scope, "dispel border mode")
        AddAliasesForAuraScope(aliases, scope, "aura debuff border")
        Registry:RegisterSetting({
            key = "auras3." .. scope .. ".debuffTypeBorderMode",
            label = AuraScopeLabel(scope) .. " Debuff Type Border",
            category = AuraScopeLabel(scope) .. " / Aura Style",
            unit = scope,
            frameType = "aura",
            attribute = "auraDebuffTypeBorderMode",
            type = "enum",
            aliases = aliases,
            values = AURA_DEBUFF_TYPE_BORDER_VALUES,
            valueAliases = AURA_DEBUFF_TYPE_BORDER_ALIASES,
            get = function() return AuraReadDebuffTypeBorderMode(scope) end,
            set = function(value) AuraWriteDebuffTypeBorderMode(scope, value) end,
            apply = function()
                if type(ApplyAura) == "function" then ApplyAura(scope, "MSUF_ASSISTANT_AURA_STYLE") end
            end,
            combatSafe = false,
        })

        aliases = {}
        AddAliasesForAuraScope(aliases, scope, "stack anchor")
        AddAliasesForAuraScope(aliases, scope, "stack count anchor")
        RegisterAuraScopeEnum(scope, "stackAnchor", "Stack Count Anchor", AURA_STACK_ANCHOR_VALUES, AURA_STACK_ANCHOR_ALIASES, aliases,
            function() return AuraReadStackAnchor(scope) end,
            function(value) AuraWriteStackAnchor(scope, value) end,
            true)

        aliases = {}
        AddAliasesForAuraScope(aliases, scope, "cooldown anchor")
        AddAliasesForAuraScope(aliases, scope, "cooldown text anchor")
        AddAliasesForAuraScope(aliases, scope, "timer text anchor")
        RegisterAuraScopeEnum(scope, "cooldownAnchor", "Cooldown Anchor", AURA_ANCHOR_VALUES, AURA_ANCHOR_ALIASES, aliases,
            function() return AuraReadCooldownAnchor(scope) end,
            function(value) AuraWriteCooldownAnchor(scope, value) end,
            true)

        aliases = {}
        AddAliasesForAuraScope(aliases, scope, "stack size")
        AddAliasesForAuraScope(aliases, scope, "stack text size")
        RegisterAuraScopeNumber(scope, "stackTextSize", "Stack Text Size", 14, 6, 40, aliases,
            function() return AuraReadNumber(scope, "stackTextSize", 14, 6, 40) end,
            function(value) AuraWriteNumber(scope, "stackTextSize", value, 6, 40) end,
            true)

        aliases = {}
        AddAliasesForAuraScope(aliases, scope, "cooldown size")
        AddAliasesForAuraScope(aliases, scope, "cooldown text size")
        RegisterAuraScopeNumber(scope, "cooldownTextSize", "Cooldown Text Size", 14, 6, 40, aliases,
            function() return AuraReadNumber(scope, "cooldownTextSize", 14, 6, 40) end,
            function(value) AuraWriteNumber(scope, "cooldownTextSize", value, 6, 40) end,
            true)

        for _, laneInfo in ipairs(AURA_LANES) do
            local lane = laneInfo.key
            local settingScope, settingLane = scope, lane
            for i = 1, #AURA_LANE_STYLE_BOOLEAN_SPECS do
                local spec = AURA_LANE_STYLE_BOOLEAN_SPECS[i]
                aliases = {}
                for j = 1, #spec.words do AddAuraLaneAliases(aliases, settingScope, settingLane, spec.words[j]) end
                if spec.key == "showDurationBar" then
                    A._AssistantAddAuraAllLaneNouns(aliases, settingScope, { "duration bar", "show duration bar", "timer bar", "show timer bar" })
                    A._AssistantAddAllAuraNouns(aliases, settingLane, "all", { "duration bar", "show duration bar", "timer bar", "show timer bar" })
                end
                RegisterAuraScopeLaneBoolean(settingScope, settingLane, spec.key, spec.label, spec.defaultValue, aliases,
                    function() return AuraReadLaneStyleBool(settingScope, settingLane, spec.key, spec.defaultValue) end,
                    function(value) AuraWriteLaneStyleBool(settingScope, settingLane, spec.key, value) end,
                    true)
            end

            aliases = {}
            AddAuraLaneAliases(aliases, settingScope, settingLane, "stack anchor")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "stack count anchor")
            RegisterAuraScopeLaneEnum(settingScope, settingLane, "stackAnchor", "Stack Count Anchor", AURA_STACK_ANCHOR_VALUES, AURA_STACK_ANCHOR_ALIASES, aliases,
                function() return AuraReadLaneStackAnchor(settingScope, settingLane) end,
                function(value) AuraWriteLaneStackAnchor(settingScope, settingLane, value) end,
                true)

            aliases = {}
            AddAuraLaneAliases(aliases, settingScope, settingLane, "cooldown anchor")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "cooldown text anchor")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "timer text anchor")
            RegisterAuraScopeLaneEnum(settingScope, settingLane, "cooldownAnchor", "Cooldown Anchor", AURA_ANCHOR_VALUES, AURA_ANCHOR_ALIASES, aliases,
                function() return AuraReadLaneCooldownAnchor(settingScope, settingLane) end,
                function(value) AuraWriteLaneCooldownAnchor(settingScope, settingLane, value) end,
                true)

            aliases = {}
            AddAuraLaneAliases(aliases, settingScope, settingLane, "swipe direction")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "cooldown swipe direction")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "timer swipe direction")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "reverse cooldown swipe")
            RegisterAuraScopeLaneEnum(settingScope, settingLane, "cooldownSwipeReverse", "Cooldown Swipe Direction", AURA_COOLDOWN_SWIPE_DIRECTION_VALUES, AURA_COOLDOWN_SWIPE_DIRECTION_ALIASES, aliases,
                function() return AuraReadLaneStyleBool(settingScope, settingLane, "cooldownSwipeReverse", false) and "REVERSE" or "NORMAL" end,
                function(value) AuraWriteLaneStyleBool(settingScope, settingLane, "cooldownSwipeReverse", value == "REVERSE") end,
                true)

            aliases = {}
            AddAuraLaneAliases(aliases, settingScope, settingLane, "duration bar position")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "timer bar position")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "duration bar edge")
            A._AssistantAddAuraAllLaneNouns(aliases, settingScope, { "duration bar position", "timer bar position", "duration bar edge" })
            RegisterAuraScopeLaneEnum(settingScope, settingLane, "durationBarPosition", "Duration Bar Position", AURA_DURATION_BAR_POSITION_VALUES, AURA_DURATION_BAR_POSITION_ALIASES, aliases,
                function() return AuraReadLaneDurationBarPosition(settingScope, settingLane) end,
                function(value) AuraWriteLaneDurationBarPosition(settingScope, settingLane, value) end,
                true)

            aliases = {}
            AddAuraLaneAliases(aliases, settingScope, settingLane, "duration bar display")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "timer bar display")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "duration bar mode")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "timer bar mode")
            A._AssistantAddAuraAllLaneNouns(aliases, settingScope, { "duration bar display", "timer bar display", "duration bar mode", "timer bar mode" })
            RegisterAuraScopeLaneEnum(settingScope, settingLane, "durationBarDisplay", "Duration Bar Display", AURA_DURATION_BAR_DISPLAY_VALUES, AURA_DURATION_BAR_DISPLAY_ALIASES, aliases,
                function() return AuraReadLaneDurationBarDisplay(settingScope, settingLane) end,
                function(value) AuraWriteLaneDurationBarDisplay(settingScope, settingLane, value) end,
                true)

            aliases = {}
            AddAuraLaneAliases(aliases, settingScope, settingLane, "duration bar fill mode")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "duration bar direction")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "timer bar fill mode")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "timer bar direction")
            A._AssistantAddAuraAllLaneNouns(aliases, settingScope, { "duration bar fill mode", "duration bar direction", "timer bar fill mode", "timer bar direction" })
            RegisterAuraScopeLaneEnum(settingScope, settingLane, "durationBarDirection", "Duration Bar Fill Mode", AURA_DURATION_BAR_DIRECTION_VALUES, AURA_DURATION_BAR_DIRECTION_ALIASES, aliases,
                function() return AuraReadLaneDurationBarDirection(settingScope, settingLane) end,
                function(value) AuraWriteLaneDurationBarDirection(settingScope, settingLane, value) end,
                true)

            for i = 1, #AURA_LANE_STYLE_NUMBER_SPECS do
                local spec = AURA_LANE_STYLE_NUMBER_SPECS[i]
                aliases = {}
                for j = 1, #spec.words do AddAuraLaneAliases(aliases, settingScope, settingLane, spec.words[j]) end
                if spec.key == "durationBarHeight" then
                    A._AssistantAddAuraAllLaneNouns(aliases, settingScope, { "duration bar height", "timer bar height" })
                    A._AssistantAddAllAuraNouns(aliases, settingLane, "all", { "duration bar height", "timer bar height" })
                end
                RegisterAuraScopeLaneNumber(settingScope, settingLane, spec.key, spec.label, spec.defaultValue, spec.minValue, spec.maxValue, aliases,
                    function() return AuraReadLaneStyleNumber(settingScope, settingLane, spec.key, spec.defaultValue, spec.minValue, spec.maxValue) end,
                    function(value) AuraWriteLaneStyleNumber(settingScope, settingLane, spec.key, value, spec.minValue, spec.maxValue) end,
                    true)
            end
        end

        if scope ~= "shared" then
            aliases = {}
            AddAliasesForAuraScope(aliases, scope, "custom aura style")
            AddAliasesForAuraScope(aliases, scope, "use custom aura style")
            AddAliasesForAuraScope(aliases, scope, "use custom aura style for this scope")
            AddAliasesForAuraScope(aliases, scope, "aura style override")
            AddAliasesForAuraScope(aliases, scope, "custom aura visuals")
            RegisterAuraScopeBoolean(scope, "customStyle", "Custom Aura Style", false, aliases,
                function() return not AuraUseSharedVisuals(scope) end,
                function(value) AuraSetUseSharedVisuals(scope, not value) end,
                false,
                { "custom aura style", "use custom aura style", "use custom aura style for this scope", "aura style override", "custom aura visuals" })

            aliases = {}
            AddAliasesForAuraScope(aliases, scope, "use shared style")
            AddAliasesForAuraScope(aliases, scope, "shared aura style")
            RegisterAuraScopeBoolean(scope, "useSharedStyle", "Use Shared Style", true, aliases,
                function() return AuraUseSharedVisuals(scope) end,
                function(value) AuraSetUseSharedVisuals(scope, value) end,
                false)

            aliases = {}
            AddAliasesForAuraScope(aliases, scope, "use shared rules")
            AddAliasesForAuraScope(aliases, scope, "shared aura rules")
            AddAliasesForAuraScope(aliases, scope, "use shared filters")
            AddAliasesForAuraScope(aliases, scope, "shared filters")
            AddAliasesForAuraScope(aliases, scope, "shared aura filters")
            AddAliasesForAuraScope(aliases, scope, "inherit filters")
            AddAliasesForAuraScope(aliases, scope, "follow shared filters")
            RegisterAuraScopeBoolean(scope, "useSharedRules", "Use Shared Rules", true, aliases,
                function() return AuraUseSharedRules(scope) end,
                function(value) AuraSetUseSharedRules(scope, value) end,
                false)
        end

        local RegisterFilterSettings = A.AurasRegistry and A.AurasRegistry.RegisterFilterSettings
        if type(RegisterFilterSettings) == "function" then RegisterFilterSettings(ctx, scope) end
    end
end
