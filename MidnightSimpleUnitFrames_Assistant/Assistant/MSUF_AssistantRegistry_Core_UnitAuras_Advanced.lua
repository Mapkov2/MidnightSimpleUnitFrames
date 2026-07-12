-- Assistant registry core helpers for unit aura visual/rule/filter state.
-- Loaded before MSUF_AssistantRegistry_Core_UnitAuras.lua; consumers receive these through the core helper table.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.RegistryCoreBuilders = A.RegistryCoreBuilders or {}

function A.RegistryCoreBuilders.BuildUnitAuraAdvancedHelpers(ctx)
    if type(ctx) ~= "table" then return nil end

    local AuraModel = ctx.AuraModel
    local EnsureAuraFallbackDB = ctx.EnsureAuraFallbackDB
    local AuraRuntimeUnit = ctx.AuraRuntimeUnit

    if type(AuraModel) ~= "function" or type(EnsureAuraFallbackDB) ~= "function" or type(AuraRuntimeUnit) ~= "function" then
        return nil
    end

    local function AuraUseSharedVisuals(scope)
        local Model = AuraModel()
        if Model and type(Model.UseSharedVisuals) == "function" then return Model.UseSharedVisuals(scope) end
        local auras = EnsureAuraFallbackDB()
        local pu = auras.perUnit and auras.perUnit[AuraRuntimeUnit(scope)]
        return not (pu and (pu.overrideLayout == true or pu.overrideSharedLayout == true))
    end

    local function AuraSetUseSharedVisuals(scope, value)
        local Model = AuraModel()
        if Model and type(Model.SetUseSharedVisuals) == "function" then
            Model.SetUseSharedVisuals(scope, value)
            return
        end
        local auras = EnsureAuraFallbackDB()
        local unit = AuraRuntimeUnit(scope)
        auras.perUnit[unit] = type(auras.perUnit[unit]) == "table" and auras.perUnit[unit] or {}
        auras.perUnit[unit].overrideLayout = not value
        auras.perUnit[unit].overrideSharedLayout = not value
    end

    local function AuraUseSharedRules(scope)
        local Model = AuraModel()
        local modelValue = Model and type(Model.UseSharedRules) == "function" and Model.UseSharedRules(scope) or nil
        if scope == "shared" then return true end
        local auras = EnsureAuraFallbackDB()
        local pu = auras.perUnit and auras.perUnit[AuraRuntimeUnit(scope)]
        if pu and pu.overrideFilters ~= nil then return pu.overrideFilters ~= true end
        if modelValue ~= nil then return modelValue == true end
        return true
    end

    local function AuraSetUseSharedRules(scope, value)
        local Model = AuraModel()
        if Model and type(Model.SetUseSharedRules) == "function" then Model.SetUseSharedRules(scope, value) end
        if scope == "shared" then return end
        local auras = EnsureAuraFallbackDB()
        local unit = AuraRuntimeUnit(scope)
        auras.perUnit[unit] = type(auras.perUnit[unit]) == "table" and auras.perUnit[unit] or {}
        local pu = auras.perUnit[unit]
        pu.overrideFilters = value ~= true
        if value ~= true and type(pu.filters) ~= "table" then pu.filters = {} end
    end

    local function FallbackFilters(scope, create)
        local auras, shared = EnsureAuraFallbackDB()
        shared.filters = type(shared.filters) == "table" and shared.filters or (create and {} or nil)
        if scope == "shared" then return shared.filters end
        local unit = AuraRuntimeUnit(scope)
        local pu = auras.perUnit and auras.perUnit[unit]
        if create and type(pu) ~= "table" then
            pu = {}
            auras.perUnit[unit] = pu
        end
        if pu and pu.overrideFilters == true then
            if create and type(pu.filters) ~= "table" then pu.filters = {} end
            return pu.filters
        end
        return shared.filters
    end

    local function AuraFiltersEnabled(scope)
        local Model = AuraModel()
        local modelValue = Model and type(Model.ScopeFiltersEnabled) == "function" and Model.ScopeFiltersEnabled(scope) or nil
        local filters = FallbackFilters(scope, false)
        if type(filters) == "table" and filters.enabled ~= nil then return filters.enabled ~= false end
        if modelValue ~= nil then return modelValue ~= false end
        return true
    end

    local function AuraSetFiltersEnabled(scope, value)
        local Model = AuraModel()
        if Model and type(Model.SetScopeFiltersEnabled) == "function" then Model.SetScopeFiltersEnabled(scope, value) end
        local filters = FallbackFilters(scope, true)
        if type(filters) == "table" then filters.enabled = value == true end
    end

    local function AuraReadFilter(scope, kind, key, defaultValue)
        local Model = AuraModel()
        local modelValue = Model and type(Model.ReadFilter) == "function" and Model.ReadFilter(scope, kind, key, defaultValue) or nil
        local filters = FallbackFilters(scope, false)
        local group = type(filters) == "table" and filters[kind == "buff" and "buffs" or "debuffs"] or nil
        if type(group) == "table" and group[key] ~= nil then return group[key] end
        if modelValue ~= nil then return modelValue end
        return defaultValue
    end

    local function AuraWriteFilter(scope, kind, key, value)
        local Model = AuraModel()
        if Model and type(Model.WriteFilter) == "function" then Model.WriteFilter(scope, kind, key, value) end
        local filters = FallbackFilters(scope, true)
        local groupKey = kind == "buff" and "buffs" or "debuffs"
        if type(filters) == "table" then
            filters[groupKey] = type(filters[groupKey]) == "table" and filters[groupKey] or {}
            filters[groupKey][key] = value
        end
    end

    return {
        AuraUseSharedVisuals = AuraUseSharedVisuals,
        AuraSetUseSharedVisuals = AuraSetUseSharedVisuals,
        AuraUseSharedRules = AuraUseSharedRules,
        AuraSetUseSharedRules = AuraSetUseSharedRules,
        AuraFiltersEnabled = AuraFiltersEnabled,
        AuraSetFiltersEnabled = AuraSetFiltersEnabled,
        AuraReadFilter = AuraReadFilter,
        AuraWriteFilter = AuraWriteFilter,
    }
end
