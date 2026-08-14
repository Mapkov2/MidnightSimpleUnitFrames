-- Assistant Auras lane style read/write helper factory.
-- Loaded before MSUF_AssistantRegistry_Auras_Registration_Lanes.lua; keeps style fallbacks isolated.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.BuildLaneStyleRegistrationHelpers(ctx)
    if type(ctx) ~= "table" then return nil end

    local AuraModel = ctx.AuraModel
    local AuraReadNumber = ctx.AuraReadNumber
    local AuraWriteNumber = ctx.AuraWriteNumber
    local AuraReadStackAnchor = ctx.AuraReadStackAnchor
    local AuraWriteStackAnchor = ctx.AuraWriteStackAnchor
    local AuraReadCooldownAnchor = ctx.AuraReadCooldownAnchor
    local AuraWriteCooldownAnchor = ctx.AuraWriteCooldownAnchor

    if type(AuraModel) ~= "function" then return nil end
    if type(AuraReadNumber) ~= "function" or type(AuraWriteNumber) ~= "function" then return nil end
    if type(AuraReadStackAnchor) ~= "function" or type(AuraWriteStackAnchor) ~= "function" then return nil end
    if type(AuraReadCooldownAnchor) ~= "function" or type(AuraWriteCooldownAnchor) ~= "function" then return nil end

    local function AuraReadLaneStyleBool(scope, lane, key, defaultValue)
        local Model = AuraModel()
        if Model and type(Model.ReadLaneStyleBool) == "function" then return Model.ReadLaneStyleBool(scope, lane, key, defaultValue) end
        return defaultValue and true or false
    end

    local function AuraWriteLaneStyleBool(scope, lane, key, value)
        local Model = AuraModel()
        if Model and type(Model.WriteLaneStyleBool) == "function" then
            Model.WriteLaneStyleBool(scope, lane, key, value)
            return
        end
        -- No Shared fallback for Unit lane writes.
    end

    local function AuraReadLaneStyleNumber(scope, lane, key, defaultValue, minValue, maxValue)
        local Model = AuraModel()
        if Model and type(Model.ReadLaneStyleNumber) == "function" then return Model.ReadLaneStyleNumber(scope, lane, key, defaultValue, minValue, maxValue) end
        return AuraReadNumber(scope, key, defaultValue, minValue, maxValue)
    end

    local function AuraWriteLaneStyleNumber(scope, lane, key, value, minValue, maxValue)
        local Model = AuraModel()
        if Model and type(Model.WriteLaneStyleNumber) == "function" then
            Model.WriteLaneStyleNumber(scope, lane, key, value, minValue, maxValue)
            return
        end
        AuraWriteNumber(scope, key, value, minValue, maxValue)
    end

    local function AuraReadLaneStackAnchor(scope, lane)
        local Model = AuraModel()
        if Model and type(Model.ReadLaneStackAnchor) == "function" then return Model.ReadLaneStackAnchor(scope, lane) end
        return AuraReadStackAnchor(scope)
    end

    local function AuraWriteLaneStackAnchor(scope, lane, value)
        local Model = AuraModel()
        if Model and type(Model.WriteLaneStackAnchor) == "function" then
            Model.WriteLaneStackAnchor(scope, lane, value)
            return
        end
        AuraWriteStackAnchor(scope, value)
    end

    local function AuraReadLaneCooldownAnchor(scope, lane)
        local Model = AuraModel()
        if Model and type(Model.ReadLaneCooldownAnchor) == "function" then return Model.ReadLaneCooldownAnchor(scope, lane) end
        return AuraReadCooldownAnchor(scope)
    end

    local function AuraWriteLaneCooldownAnchor(scope, lane, value)
        local Model = AuraModel()
        if Model and type(Model.WriteLaneCooldownAnchor) == "function" then
            Model.WriteLaneCooldownAnchor(scope, lane, value)
            return
        end
        AuraWriteCooldownAnchor(scope, value)
    end

    return {
        AuraReadLaneStyleBool = AuraReadLaneStyleBool,
        AuraWriteLaneStyleBool = AuraWriteLaneStyleBool,
        AuraReadLaneStyleNumber = AuraReadLaneStyleNumber,
        AuraWriteLaneStyleNumber = AuraWriteLaneStyleNumber,
        AuraReadLaneStackAnchor = AuraReadLaneStackAnchor,
        AuraWriteLaneStackAnchor = AuraWriteLaneStackAnchor,
        AuraReadLaneCooldownAnchor = AuraReadLaneCooldownAnchor,
        AuraWriteLaneCooldownAnchor = AuraWriteLaneCooldownAnchor,
    }
end
