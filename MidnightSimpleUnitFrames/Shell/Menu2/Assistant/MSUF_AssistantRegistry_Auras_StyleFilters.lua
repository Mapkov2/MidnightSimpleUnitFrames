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
    local AURA_STACK_ANCHOR_VALUES = ctx.AURA_STACK_ANCHOR_VALUES or {}
    local AURA_STACK_ANCHOR_ALIASES = ctx.AURA_STACK_ANCHOR_ALIASES or {}
    local AURA_LANE_STYLE_BOOLEAN_SPECS = ctx.AURA_LANE_STYLE_BOOLEAN_SPECS or {}
    local AURA_LANE_STYLE_NUMBER_SPECS = ctx.AURA_LANE_STYLE_NUMBER_SPECS or {}
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
    local AuraReadLaneStyleBool = ctx.AuraReadLaneStyleBool
    local AuraWriteLaneStyleBool = ctx.AuraWriteLaneStyleBool
    local AuraReadLaneStyleNumber = ctx.AuraReadLaneStyleNumber
    local AuraWriteLaneStyleNumber = ctx.AuraWriteLaneStyleNumber
    local AuraReadLaneStackAnchor = ctx.AuraReadLaneStackAnchor
    local AuraWriteLaneStackAnchor = ctx.AuraWriteLaneStackAnchor
    local AuraUseSharedVisuals = ctx.AuraUseSharedVisuals
    local AuraSetUseSharedVisuals = ctx.AuraSetUseSharedVisuals
    local AuraUseSharedRules = ctx.AuraUseSharedRules
    local AuraSetUseSharedRules = ctx.AuraSetUseSharedRules

    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(AddAliasesForAuraScope) ~= "function" or type(AddAuraLaneAliases) ~= "function" then return end
    if type(AuraScopeLabel) ~= "function" or type(RegisterAuraScopeBoolean) ~= "function" then return end

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

        aliases = {}
        AddAliasesForAuraScope(aliases, scope, "stack anchor")
        AddAliasesForAuraScope(aliases, scope, "stack count anchor")
        RegisterAuraScopeEnum(scope, "stackAnchor", "Stack Count Anchor", AURA_STACK_ANCHOR_VALUES, AURA_STACK_ANCHOR_ALIASES, aliases,
            function() return AuraReadStackAnchor(scope) end,
            function(value) AuraWriteStackAnchor(scope, value) end,
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

            for i = 1, #AURA_LANE_STYLE_NUMBER_SPECS do
                local spec = AURA_LANE_STYLE_NUMBER_SPECS[i]
                aliases = {}
                for j = 1, #spec.words do AddAuraLaneAliases(aliases, settingScope, settingLane, spec.words[j]) end
                RegisterAuraScopeLaneNumber(settingScope, settingLane, spec.key, spec.label, spec.defaultValue, spec.minValue, spec.maxValue, aliases,
                    function() return AuraReadLaneStyleNumber(settingScope, settingLane, spec.key, spec.defaultValue, spec.minValue, spec.maxValue) end,
                    function(value) AuraWriteLaneStyleNumber(settingScope, settingLane, spec.key, value, spec.minValue, spec.maxValue) end,
                    true)
            end
        end

        if scope ~= "shared" then
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
            RegisterAuraScopeBoolean(scope, "useSharedRules", "Use Shared Rules", true, aliases,
                function() return AuraUseSharedRules(scope) end,
                function(value) AuraSetUseSharedRules(scope, value) end,
                false)
        end

        local RegisterFilterSettings = A.AurasRegistry and A.AurasRegistry.RegisterFilterSettings
        if type(RegisterFilterSettings) == "function" then RegisterFilterSettings(ctx, scope) end
    end
end
