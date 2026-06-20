-- Assistant registry core helpers for unit aura lane geometry.
-- Loaded before MSUF_AssistantRegistry_Core_UnitAuras.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.RegistryCoreBuilders = A.RegistryCoreBuilders or {}

function A.RegistryCoreBuilders.BuildUnitAuraLaneHelpers(ctx)
    if type(ctx) ~= "table" then return nil end

    local AuraModel = ctx.AuraModel
    local EnsureAuraFallbackDB = ctx.EnsureAuraFallbackDB
    local AURA_LANE_FIELDS = ctx.AURA_LANE_FIELDS or {}
    local ClampNumber = ctx.ClampNumber
    local AuraUnitEnabled = ctx.AuraUnitEnabled
    local SetAuraUnitEnabled = ctx.SetAuraUnitEnabled
    local SetAuraSharedBool = ctx.SetAuraSharedBool

    if type(AuraModel) ~= "function" or type(EnsureAuraFallbackDB) ~= "function" or type(ClampNumber) ~= "function" then return nil end
    if type(AuraUnitEnabled) ~= "function" or type(SetAuraUnitEnabled) ~= "function" or type(SetAuraSharedBool) ~= "function" then return nil end

    local function AuraLaneFields(kind)
        return AURA_LANE_FIELDS[kind == "buff" and "buff" or "debuff"] or {}
    end

    local function AuraLaneMaxKey(kind) return AuraLaneFields(kind).maxKey end
    local function AuraLaneSizeKey(kind) return AuraLaneFields(kind).sizeKey end
    local function AuraLaneXKey(kind) return AuraLaneFields(kind).xKey end
    local function AuraLaneYKey(kind) return AuraLaneFields(kind).yKey end
    local function AuraLaneDefaultMax(kind) return AuraLaneFields(kind).defaultMax end
    local function AuraLaneDefaultY(kind) return AuraLaneFields(kind).defaultY end

    local function AuraReadNumber(scope, key, defaultValue, minValue, maxValue)
        local Model = AuraModel()
        if Model and type(Model.ReadNumber) == "function" then return Model.ReadNumber(scope, key, defaultValue, minValue, maxValue) end
        local _, shared = EnsureAuraFallbackDB()
        return ClampNumber(shared[key] ~= nil and shared[key] or defaultValue, minValue, maxValue, 1) or defaultValue
    end

    local function AuraWriteNumber(scope, key, value, minValue, maxValue)
        local Model = AuraModel()
        if Model and type(Model.WriteNumber) == "function" then
            Model.WriteNumber(scope, key, value, minValue, maxValue)
            return
        end
        local _, shared = EnsureAuraFallbackDB()
        shared[key] = ClampNumber(value, minValue, maxValue, 1)
    end

    local function AuraReadLanePerRow(scope, kind)
        local Model = AuraModel()
        if Model and type(Model.ReadLanePerRow) == "function" then return Model.ReadLanePerRow(scope, kind) end
        return AuraReadNumber(scope, kind == "buff" and "buffPerRow" or "debuffPerRow", 12, 1, 40)
    end

    local function AuraWriteLanePerRow(scope, kind, value)
        local Model = AuraModel()
        if Model and type(Model.WriteLanePerRow) == "function" then
            Model.WriteLanePerRow(scope, kind, value)
            return
        end
        AuraWriteNumber(scope, kind == "buff" and "buffPerRow" or "debuffPerRow", value, 1, 40)
    end

    local function AuraReadLaneGrowth(scope, kind)
        local Model = AuraModel()
        if Model and type(Model.ReadLaneGrowth) == "function" then return Model.ReadLaneGrowth(scope, kind) end
        local key = kind == "buff" and "buffGrowthX" or "debuffGrowthX"
        local _, shared = EnsureAuraFallbackDB()
        local value = shared[key] or "RIGHT"
        if value == "LEFT" or value == "UP" or value == "DOWN" then return value end
        return "RIGHT"
    end

    local function AuraWriteLaneGrowth(scope, kind, value)
        if value ~= "LEFT" and value ~= "UP" and value ~= "DOWN" then value = "RIGHT" end
        local Model = AuraModel()
        if Model and type(Model.WriteLaneGrowth) == "function" then
            Model.WriteLaneGrowth(scope, kind, value)
            return
        end
        local _, shared = EnsureAuraFallbackDB()
        shared[kind == "buff" and "buffGrowthX" or "debuffGrowthX"] = value
    end

    local function AuraReadStackAnchor(scope)
        local Model = AuraModel()
        if Model and type(Model.ReadStackAnchor) == "function" then return Model.ReadStackAnchor(scope) end
        local _, shared = EnsureAuraFallbackDB()
        local value = shared.stackCountAnchor or "TOPRIGHT"
        if value == "TOPLEFT" or value == "BOTTOMRIGHT" or value == "BOTTOMLEFT" then return value end
        return "TOPRIGHT"
    end

    local function AuraWriteStackAnchor(scope, value)
        if value ~= "TOPLEFT" and value ~= "BOTTOMRIGHT" and value ~= "BOTTOMLEFT" then value = "TOPRIGHT" end
        local Model = AuraModel()
        if Model and type(Model.WriteStackAnchor) == "function" then
            Model.WriteStackAnchor(scope, value)
            return
        end
        local _, shared = EnsureAuraFallbackDB()
        shared.stackCountAnchor = value
    end

    local function AuraLaneShown(unit, kind)
        local Model = AuraModel()
        if Model and type(Model.GroupShown) == "function" then
            return Model.UnitEnabled(unit) and Model.GroupShown(unit, kind)
        end
        return AuraUnitEnabled(unit) and AuraReadNumber(unit, AuraLaneMaxKey(kind), AuraLaneDefaultMax(kind), 0, 80) > 0
    end

    local function SetAuraLaneShown(unit, kind, shown)
        local Model = AuraModel()
        if shown then
            SetAuraUnitEnabled(unit, true)
            SetAuraSharedBool(kind == "buff" and "showBuffs" or "showDebuffs", true)
            if Model and type(Model.SetGroupShown) == "function" then
                Model.SetGroupShown(unit, kind, true)
            else
                AuraWriteNumber(unit, AuraLaneMaxKey(kind), AuraLaneDefaultMax(kind), 0, 80)
            end
        else
            if Model and type(Model.SetGroupShown) == "function" then
                Model.SetGroupShown(unit, kind, false)
            else
                AuraWriteNumber(unit, AuraLaneMaxKey(kind), 0, 0, 80)
            end
            if not AuraLaneShown(unit, kind == "buff" and "debuff" or "buff") then
                SetAuraUnitEnabled(unit, false)
            end
        end
    end

    return {
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
        AuraLaneShown = AuraLaneShown,
        SetAuraLaneShown = SetAuraLaneShown,
    }
end
