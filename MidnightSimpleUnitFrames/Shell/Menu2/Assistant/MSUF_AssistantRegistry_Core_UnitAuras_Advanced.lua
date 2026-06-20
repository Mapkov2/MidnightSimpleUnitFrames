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
        if Model and type(Model.UseSharedRules) == "function" then return Model.UseSharedRules(scope) end
        return true
    end

    local function AuraSetUseSharedRules(scope, value)
        local Model = AuraModel()
        if Model and type(Model.SetUseSharedRules) == "function" then Model.SetUseSharedRules(scope, value) end
    end

    local function AuraFiltersEnabled(scope)
        local Model = AuraModel()
        if Model and type(Model.ScopeFiltersEnabled) == "function" then return Model.ScopeFiltersEnabled(scope) end
        return true
    end

    local function AuraSetFiltersEnabled(scope, value)
        local Model = AuraModel()
        if Model and type(Model.SetScopeFiltersEnabled) == "function" then Model.SetScopeFiltersEnabled(scope, value) end
    end

    local function AuraReadFilter(scope, kind, key, defaultValue)
        local Model = AuraModel()
        if Model and type(Model.ReadFilter) == "function" then return Model.ReadFilter(scope, kind, key, defaultValue) end
        return defaultValue
    end

    local function AuraWriteFilter(scope, kind, key, value)
        local Model = AuraModel()
        if Model and type(Model.WriteFilter) == "function" then Model.WriteFilter(scope, kind, key, value) end
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
