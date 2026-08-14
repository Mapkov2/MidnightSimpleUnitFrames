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

    local function FallbackFilters(scope, create)
        if scope ~= "player" and scope ~= "target" and scope ~= "focus" and scope ~= "boss" then return nil end
        local auras = EnsureAuraFallbackDB()
        local unit = AuraRuntimeUnit(scope)
        local pu = auras.perUnit and auras.perUnit[unit]
        if create and type(pu) ~= "table" then
            pu = {}
            auras.perUnit[unit] = pu
        end
        if pu then
            if create and type(pu.filters) ~= "table" then pu.filters = {} end
            return pu.filters
        end
        return nil
    end

    local function AuraFiltersEnabled(scope, kind)
        local Model = AuraModel()
        local modelValue = Model and type(Model.LaneFiltersEnabled) == "function"
            and Model.LaneFiltersEnabled(scope, kind) or nil
        local filters = FallbackFilters(scope, false)
        local group = type(filters) == "table" and filters[kind == "buff" and "buffs" or "debuffs"] or nil
        if type(group) == "table" and group.enabled ~= nil then return group.enabled ~= false end
        if modelValue ~= nil then return modelValue ~= false end
        return true
    end

    local function AuraSetFiltersEnabled(scope, kind, value)
        local Model = AuraModel()
        if Model and type(Model.SetLaneFiltersEnabled) == "function" then Model.SetLaneFiltersEnabled(scope, kind, value) end
        local filters = FallbackFilters(scope, true)
        if type(filters) == "table" then
            local key = kind == "buff" and "buffs" or "debuffs"
            filters[key] = type(filters[key]) == "table" and filters[key] or {}
            filters[key].enabled = value == true
        end
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
        AuraFiltersEnabled = AuraFiltersEnabled,
        AuraSetFiltersEnabled = AuraSetFiltersEnabled,
        AuraReadFilter = AuraReadFilter,
        AuraWriteFilter = AuraWriteFilter,
    }
end
