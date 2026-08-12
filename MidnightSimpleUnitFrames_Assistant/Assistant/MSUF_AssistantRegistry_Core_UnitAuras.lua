-- Assistant registry core helpers for unit aura settings.
-- Loaded before MSUF_AssistantRegistry_Core.lua; the core registry passes DB/model helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.RegistryCoreBuilders = A.RegistryCoreBuilders or {}

function A.RegistryCoreBuilders.BuildUnitAuraHelpers(ctx)
    if type(ctx) ~= "table" then return nil end

    local AuraModel = ctx.AuraModel
    local EnsureAuraFallbackDB = ctx.EnsureAuraFallbackDB
    local AURA_UNIT_FLAGS = ctx.AURA_UNIT_FLAGS or {}
    local AURA_LANE_FIELDS = ctx.AURA_LANE_FIELDS or {}
    local ClampNumber = ctx.ClampNumber

    if type(AuraModel) ~= "function" or type(EnsureAuraFallbackDB) ~= "function" or type(ClampNumber) ~= "function" then return nil end

    local function AuraRuntimeUnit(unit)
        if unit == "boss" or unit == "boss1" or unit == "boss2" or unit == "boss3" or unit == "boss4" or unit == "boss5" then return "boss1" end
        if unit == "target" or unit == "focus" then return unit end
        if unit == "player" then return "player" end
        return nil
    end

    local function AuraUnitEnabled(unit)
        local Model = AuraModel()
        if Model and type(Model.UnitEnabled) == "function" then return Model.UnitEnabled(unit) end
        local auras = EnsureAuraFallbackDB()
        local flag = AURA_UNIT_FLAGS[unit]
        return auras.enabled == true and flag and auras[flag] == true
    end

    local function SetAuraUnitEnabled(unit, enabled)
        local Model = AuraModel()
        if Model and type(Model.SetUnitEnabled) == "function" then
            Model.SetUnitEnabled(unit, enabled)
            return
        end
        local auras = EnsureAuraFallbackDB()
        local flag = AURA_UNIT_FLAGS[unit]
        if enabled then auras.enabled = true end
        if flag then auras[flag] = enabled and true or false end
    end

    local BuildUnitAuraLaneHelpers = A.RegistryCoreBuilders.BuildUnitAuraLaneHelpers
    local LaneHelpers = type(BuildUnitAuraLaneHelpers) == "function" and BuildUnitAuraLaneHelpers({
        AuraModel = AuraModel,
        EnsureAuraFallbackDB = EnsureAuraFallbackDB,
        AURA_LANE_FIELDS = AURA_LANE_FIELDS,
        ClampNumber = ClampNumber,
        AuraUnitEnabled = AuraUnitEnabled,
        SetAuraUnitEnabled = SetAuraUnitEnabled,
    }) or nil
    if type(LaneHelpers) ~= "table" then return nil end
    local AuraLaneMaxKey = LaneHelpers.AuraLaneMaxKey
    local AuraLaneSizeKey = LaneHelpers.AuraLaneSizeKey
    local AuraLaneXKey = LaneHelpers.AuraLaneXKey
    local AuraLaneYKey = LaneHelpers.AuraLaneYKey
    local AuraLaneDefaultMax = LaneHelpers.AuraLaneDefaultMax
    local AuraLaneDefaultY = LaneHelpers.AuraLaneDefaultY
    local AuraReadNumber = LaneHelpers.AuraReadNumber
    local AuraWriteNumber = LaneHelpers.AuraWriteNumber
    local AuraReadLanePerRow = LaneHelpers.AuraReadLanePerRow
    local AuraWriteLanePerRow = LaneHelpers.AuraWriteLanePerRow
    local AuraReadLaneGrowth = LaneHelpers.AuraReadLaneGrowth
    local AuraWriteLaneGrowth = LaneHelpers.AuraWriteLaneGrowth
    local AuraReadStackAnchor = LaneHelpers.AuraReadStackAnchor
    local AuraWriteStackAnchor = LaneHelpers.AuraWriteStackAnchor
    local AuraReadCooldownAnchor = LaneHelpers.AuraReadCooldownAnchor
    local AuraWriteCooldownAnchor = LaneHelpers.AuraWriteCooldownAnchor
    local AuraLaneShown = LaneHelpers.AuraLaneShown
    local SetAuraLaneShown = LaneHelpers.SetAuraLaneShown
    if type(AuraLaneShown) ~= "function" or type(SetAuraLaneShown) ~= "function" then return nil end

    local BuildUnitAuraAdvancedHelpers = A.RegistryCoreBuilders.BuildUnitAuraAdvancedHelpers
    local AdvancedHelpers = type(BuildUnitAuraAdvancedHelpers) == "function" and BuildUnitAuraAdvancedHelpers({
        AuraModel = AuraModel,
        EnsureAuraFallbackDB = EnsureAuraFallbackDB,
        AuraRuntimeUnit = AuraRuntimeUnit,
    }) or {}
    local AuraFiltersEnabled = AdvancedHelpers.AuraFiltersEnabled
    local AuraSetFiltersEnabled = AdvancedHelpers.AuraSetFiltersEnabled
    local AuraReadFilter = AdvancedHelpers.AuraReadFilter
    local AuraWriteFilter = AdvancedHelpers.AuraWriteFilter

    return {
        AuraRuntimeUnit = AuraRuntimeUnit,
        AuraUnitEnabled = AuraUnitEnabled,
        SetAuraUnitEnabled = SetAuraUnitEnabled,
        AuraLaneMaxKey = AuraLaneMaxKey,
        AuraLaneSizeKey = AuraLaneSizeKey,
        AuraLaneXKey = AuraLaneXKey,
        AuraLaneYKey = AuraLaneYKey,
        AuraLaneDefaultMax = AuraLaneDefaultMax,
        AuraLaneDefaultY = AuraLaneDefaultY,
        AuraReadNumber = AuraReadNumber,
        AuraWriteNumber = AuraWriteNumber,
        AuraReadLanePerRow = AuraReadLanePerRow,
        AuraWriteLanePerRow = AuraWriteLanePerRow,
        AuraReadLaneGrowth = AuraReadLaneGrowth,
        AuraWriteLaneGrowth = AuraWriteLaneGrowth,
        AuraReadStackAnchor = AuraReadStackAnchor,
        AuraWriteStackAnchor = AuraWriteStackAnchor,
        AuraReadCooldownAnchor = AuraReadCooldownAnchor,
        AuraWriteCooldownAnchor = AuraWriteCooldownAnchor,
        AuraLaneShown = AuraLaneShown,
        SetAuraLaneShown = SetAuraLaneShown,
        AuraFiltersEnabled = AuraFiltersEnabled,
        AuraSetFiltersEnabled = AuraSetFiltersEnabled,
        AuraReadFilter = AuraReadFilter,
        AuraWriteFilter = AuraWriteFilter,
    }
end
