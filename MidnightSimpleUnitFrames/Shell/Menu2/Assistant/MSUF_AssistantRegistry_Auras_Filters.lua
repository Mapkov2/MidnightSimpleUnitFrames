-- Assistant Auras filter registry shard.
-- Loaded before MSUF_AssistantRegistry_Auras_StyleFilters.lua; keeps filter settings separate from visual style settings.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.RegisterFilterSettings(ctx, scope)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local AURA_LANES = ctx.AURA_LANES or {}
    local AURA_FILTER_BOOLEAN_SPECS = ctx.AURA_FILTER_BOOLEAN_SPECS or {}
    local AURA_EXCLUSIVE_FILTER_VALUES = ctx.AURA_EXCLUSIVE_FILTER_VALUES or {}
    local AURA_EXCLUSIVE_FILTER_ALIASES = ctx.AURA_EXCLUSIVE_FILTER_ALIASES or {}
    local AddAliasesForAuraScope = ctx.AddAliasesForAuraScope
    local AddAuraLaneAliases = ctx.AddAuraLaneAliases
    local AuraScopeLabel = ctx.AuraScopeLabel
    local RegisterAuraScopeBoolean = ctx.RegisterAuraScopeBoolean
    local AuraFiltersEnabled = ctx.AuraFiltersEnabled
    local AuraSetFiltersEnabled = ctx.AuraSetFiltersEnabled
    local AuraReadFilter = ctx.AuraReadFilter
    local AuraWriteFilter = ctx.AuraWriteFilter
    local ApplyAura = ctx.ApplyAura

    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(AddAliasesForAuraScope) ~= "function" or type(AddAuraLaneAliases) ~= "function" then return end
    if type(AuraScopeLabel) ~= "function" or type(RegisterAuraScopeBoolean) ~= "function" then return end

    local aliases = {}
    AddAliasesForAuraScope(aliases, scope, "filters")
    AddAliasesForAuraScope(aliases, scope, "enable filters")
    RegisterAuraScopeBoolean(scope, "filtersEnabled", "Filters Enabled", true, aliases,
        function() return AuraFiltersEnabled(scope) end,
        function(value) AuraSetFiltersEnabled(scope, value) end,
        false)

    for i = 1, #AURA_FILTER_BOOLEAN_SPECS do
        local spec = AURA_FILTER_BOOLEAN_SPECS[i]
        aliases = {}
        for j = 1, #spec.words do AddAliasesForAuraScope(aliases, scope, spec.words[j]) end
        Registry:RegisterSetting({
            key = "auras3." .. scope .. "." .. spec.lane .. ".filter." .. spec.key,
            label = AuraScopeLabel(scope) .. " " .. spec.label,
            category = AuraScopeLabel(scope) .. " / Aura Filters",
            unit = scope,
            frameType = "aura",
            attribute = "aura" .. spec.lane .. "Filter" .. spec.key,
            type = "boolean",
            aliases = aliases,
            get = function() return AuraReadFilter(scope, spec.lane, spec.key, false) == true end,
            set = function(value) AuraWriteFilter(scope, spec.lane, spec.key, value and true or false) end,
            apply = function() ApplyAura(scope, "MSUF_ASSISTANT_AURA_FILTER") end,
            combatSafe = false,
        })
    end

    for _, laneInfo in ipairs(AURA_LANES) do
        local lane = laneInfo.key
        local settingScope, settingLane = scope, lane
        aliases = {}
        AddAuraLaneAliases(aliases, settingScope, settingLane, "exclusive filter")
        AddAuraLaneAliases(aliases, settingScope, settingLane, "exclusive")
        Registry:RegisterSetting({
            key = "auras3." .. settingScope .. "." .. settingLane .. ".filter.exclusive",
            label = AuraScopeLabel(settingScope) .. " " .. laneInfo.label .. " Exclusive Filter",
            category = AuraScopeLabel(settingScope) .. " / Aura Filters",
            unit = settingScope,
            frameType = "aura",
            attribute = "aura" .. settingLane .. "FilterExclusive",
            type = "enum",
            aliases = aliases,
            values = AURA_EXCLUSIVE_FILTER_VALUES[settingLane],
            valueAliases = AURA_EXCLUSIVE_FILTER_ALIASES,
            get = function() return tostring(AuraReadFilter(settingScope, settingLane, "exclusive", "none") or "none") end,
            set = function(value) AuraWriteFilter(settingScope, settingLane, "exclusive", value or "none") end,
            apply = function() ApplyAura(settingScope, "MSUF_ASSISTANT_AURA_FILTER_EXCLUSIVE") end,
            combatSafe = false,
        })
    end
end
