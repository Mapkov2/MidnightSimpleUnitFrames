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
    local AuraModel = ctx.AuraModel
    local ApplyAura = ctx.ApplyAura

    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(AddAliasesForAuraScope) ~= "function" or type(AddAuraLaneAliases) ~= "function" then return end
    if type(AuraScopeLabel) ~= "function" or type(RegisterAuraScopeBoolean) ~= "function" then return end

    local function AuraUseSharedBlacklist(scopeKey)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.UseSharedBlacklist) == "function" then return Model.UseSharedBlacklist(scopeKey) end
        return true
    end

    local function AuraSetUseSharedBlacklist(scopeKey, value)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.SetUseSharedBlacklist) == "function" then Model.SetUseSharedBlacklist(scopeKey, value) end
    end

    local aliases = {}
    AddAliasesForAuraScope(aliases, scope, "filters")
    AddAliasesForAuraScope(aliases, scope, "enable filters")
    RegisterAuraScopeBoolean(scope, "filtersEnabled", "Filters Enabled", true, aliases,
        function() return AuraFiltersEnabled(scope) end,
        function(value) AuraSetFiltersEnabled(scope, value) end,
        false)

    local registerMutableLegacyBlacklistScopeSetting = false
    if registerMutableLegacyBlacklistScopeSetting and scope ~= "shared" then
        -- Exact aura blacklist storage is legacy read-only while the native 12.1
        -- backend is active, so do not expose inheritance as a live mutation.
        aliases = {}
        AddAliasesForAuraScope(aliases, scope, "use shared blacklist")
        AddAliasesForAuraScope(aliases, scope, "shared blacklist")
        AddAliasesForAuraScope(aliases, scope, "use shared hidden auras")
        AddAliasesForAuraScope(aliases, scope, "shared hidden auras")
        AddAliasesForAuraScope(aliases, scope, "custom blacklist")
        AddAliasesForAuraScope(aliases, scope, "custom hidden aura list")
        AddAliasesForAuraScope(aliases, scope, "custom hidden auras")
        Registry:RegisterSetting({
            key = "auras3." .. scope .. ".useSharedBlacklist",
            label = AuraScopeLabel(scope) .. " Use Shared Blacklist",
            category = AuraScopeLabel(scope) .. " / Aura Filters",
            unit = scope,
            frameType = "aura",
            attribute = "auraUseSharedBlacklist",
            type = "boolean",
            aliases = aliases,
            booleanAliases = {
                ["use shared blacklist"] = true,
                ["shared blacklist"] = true,
                ["inherit blacklist"] = true,
                ["use shared hidden auras"] = true,
                ["shared hidden auras"] = true,
                ["inherit hidden auras"] = true,
                ["use custom blacklist"] = false,
                ["custom blacklist"] = false,
                ["own blacklist"] = false,
                ["use custom hidden auras"] = false,
                ["custom hidden auras"] = false,
                ["custom hidden aura list"] = false,
                ["own hidden aura list"] = false,
            },
            get = function() return AuraUseSharedBlacklist(scope) end,
            set = function(value) AuraSetUseSharedBlacklist(scope, value and true or false) end,
            apply = function() ApplyAura(scope, "MSUF_ASSISTANT_AURA_BLACKLIST_SHARED") end,
            combatSafe = false,
        })
    end

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
            set = function(value)
                value = value and true or false
                if value == true and type(spec.conflicts) == "table" then
                    for k = 1, #spec.conflicts do
                        AuraWriteFilter(scope, spec.lane, spec.conflicts[k], false)
                    end
                end
                AuraWriteFilter(scope, spec.lane, spec.key, value)
            end,
            apply = function() ApplyAura(scope, "MSUF_ASSISTANT_AURA_FILTER") end,
            combatSafe = false,
        })
    end

    for _, laneInfo in ipairs(AURA_LANES) do
        local lane = laneInfo.key
        local settingScope, settingLane = scope, lane
        local values = AURA_EXCLUSIVE_FILTER_VALUES[settingLane] or { "none" }
        local defaultValue = values[1] or "none"
        local allowed = {}
        for i = 1, #values do allowed[values[i]] = true end
        local valueAliases = {}
        for alias, value in pairs(AURA_EXCLUSIVE_FILTER_ALIASES) do
            if allowed[value] then valueAliases[alias] = value end
        end
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
            values = values,
            valueAliases = valueAliases,
            get = function()
                local value = tostring(AuraReadFilter(settingScope, settingLane, "exclusive", defaultValue) or defaultValue)
                return allowed[value] and value or defaultValue
            end,
            set = function(value)
                value = tostring(value or defaultValue)
                AuraWriteFilter(settingScope, settingLane, "exclusive", allowed[value] and value or defaultValue)
            end,
            apply = function() ApplyAura(settingScope, "MSUF_ASSISTANT_AURA_FILTER_EXCLUSIVE") end,
            combatSafe = false,
        })
    end
end
