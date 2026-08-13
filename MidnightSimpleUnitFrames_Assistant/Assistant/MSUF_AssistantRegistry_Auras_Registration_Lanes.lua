-- Assistant Auras lane read/write helper factory.
-- Loaded before MSUF_AssistantRegistry_Auras_Registration.lua; keeps lane model fallback helpers isolated.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.BuildLaneRegistrationHelpers(ctx)
    if type(ctx) ~= "table" then return nil end

    local AuraModel = ctx.AuraModel
    local EnsureAuraFallbackDB = ctx.EnsureAuraFallbackDB
    local AuraReadNumber = ctx.AuraReadNumber
    local AuraWriteNumber = ctx.AuraWriteNumber
    local AuraReadStackAnchor = ctx.AuraReadStackAnchor
    local AuraWriteStackAnchor = ctx.AuraWriteStackAnchor
    local AuraReadCooldownAnchor = ctx.AuraReadCooldownAnchor
    local AuraWriteCooldownAnchor = ctx.AuraWriteCooldownAnchor
    local AURA_ANCHOR_VALUES = ctx.AURA_ANCHOR_VALUES or {}
    local BuildLaneStyleRegistrationHelpers = A.AurasRegistry and A.AurasRegistry.BuildLaneStyleRegistrationHelpers

    if type(AuraModel) ~= "function" or type(EnsureAuraFallbackDB) ~= "function" then return nil end
    if type(AuraReadNumber) ~= "function" or type(AuraWriteNumber) ~= "function" then return nil end
    if type(AuraReadStackAnchor) ~= "function" or type(AuraWriteStackAnchor) ~= "function" then return nil end
    if type(AuraReadCooldownAnchor) ~= "function" or type(AuraWriteCooldownAnchor) ~= "function" then return nil end
    if type(BuildLaneStyleRegistrationHelpers) ~= "function" then return nil end

    local StyleHelpers = BuildLaneStyleRegistrationHelpers({
        AuraModel = AuraModel,
        AuraReadNumber = AuraReadNumber,
        AuraWriteNumber = AuraWriteNumber,
        AuraReadStackAnchor = AuraReadStackAnchor,
        AuraWriteStackAnchor = AuraWriteStackAnchor,
        AuraReadCooldownAnchor = AuraReadCooldownAnchor,
        AuraWriteCooldownAnchor = AuraWriteCooldownAnchor,
    })
    if type(StyleHelpers) ~= "table" then return nil end

    local function AuraReadValue(scope, key, defaultValue)
        local Model = AuraModel()
        if Model and type(Model.ReadValue) == "function" then return Model.ReadValue(scope, key, defaultValue) end
        return defaultValue
    end

    local function AuraWriteValue(scope, key, value)
        local Model = AuraModel()
        if Model and type(Model.WriteValue) == "function" then
            Model.WriteValue(scope, key, value)
            return
        end
        -- No Shared fallback for Unit lane writes.
    end

    local function AuraLaneKey(lane, buffKey, debuffKey)
        return lane == "buff" and buffKey or debuffKey
    end

    local function AuraReadLaneAnchor(scope, lane)
        local Model = AuraModel()
        if Model and type(Model.ReadLaneAnchor) == "function" then return Model.ReadLaneAnchor(scope, lane) end
        local defaultValue = lane == "buff" and "BOTTOMRIGHT" or "TOPLEFT"
        local value = tostring(AuraReadValue(scope, AuraLaneKey(lane, "buffAnchor", "debuffAnchor"), defaultValue) or defaultValue)
        for i = 1, #AURA_ANCHOR_VALUES do if AURA_ANCHOR_VALUES[i] == value then return value end end
        return defaultValue
    end

    local function AuraWriteLaneAnchor(scope, lane, value)
        local allowed = {}
        for i = 1, #AURA_ANCHOR_VALUES do allowed[AURA_ANCHOR_VALUES[i]] = true end
        local defaultValue = lane == "buff" and "BOTTOMRIGHT" or "TOPLEFT"
        value = allowed[value] and value or defaultValue
        local Model = AuraModel()
        if Model and type(Model.WriteLaneAnchor) == "function" then
            Model.WriteLaneAnchor(scope, lane, value)
            return
        end
        AuraWriteValue(scope, AuraLaneKey(lane, "buffAnchor", "debuffAnchor"), value)
    end

    local function AuraReadLaneLayer(scope, lane)
        local Model = AuraModel()
        if Model and type(Model.ReadLaneLayer) == "function" then return Model.ReadLaneLayer(scope, lane) end
        return AuraReadNumber(scope, AuraLaneKey(lane, "buffLayer", "debuffLayer"), lane == "buff" and 5 or 6, 0, 30)
    end

    local function AuraWriteLaneLayer(scope, lane, value)
        local Model = AuraModel()
        if Model and type(Model.WriteLaneLayer) == "function" then
            Model.WriteLaneLayer(scope, lane, value)
            return
        end
        AuraWriteNumber(scope, AuraLaneKey(lane, "buffLayer", "debuffLayer"), value, 0, 30)
    end

    --- Gap is stored per lane (buffSpacing/debuffSpacing) with the legacy
    --- unit-wide `spacing` as the fallback, so a profile that never touched a
    --- lane key keeps showing the value it always had.
    local function AuraReadLaneSpacing(scope, lane)
        local Model = AuraModel()
        if Model and type(Model.ReadLaneSpacing) == "function" then return Model.ReadLaneSpacing(scope, lane) end
        local fallback = AuraReadNumber(scope, "spacing", 2, 0, 64)
        return AuraReadNumber(scope, AuraLaneKey(lane, "buffSpacing", "debuffSpacing"), fallback, 0, 64)
    end

    local function AuraWriteLaneSpacing(scope, lane, value)
        local Model = AuraModel()
        if Model and type(Model.WriteLaneSpacing) == "function" then
            Model.WriteLaneSpacing(scope, lane, value)
            return
        end
        AuraWriteNumber(scope, AuraLaneKey(lane, "buffSpacing", "debuffSpacing"), value, 0, 64)
    end

    local function AuraReadLaneGrowthPair(scope, lane)
        local Model = AuraModel()
        if Model and type(Model.ReadLaneGrowthPair) == "function" then return Model.ReadLaneGrowthPair(scope, lane) end
        local x = tostring(AuraReadValue(scope, AuraLaneKey(lane, "buffGrowthX", "debuffGrowthX"), "RIGHT") or "RIGHT")
        local y = tostring(AuraReadValue(scope, AuraLaneKey(lane, "buffGrowthY", "debuffGrowthY"), "DOWN") or "DOWN")
        if x == "UP" or x == "DOWN" then return x end
        local pair = x .. y
        if pair == "LEFTDOWN" or pair == "RIGHTUP" or pair == "LEFTUP" then return pair end
        return "RIGHTDOWN"
    end

    local function AuraWriteLaneGrowthPair(scope, lane, value)
        local Model = AuraModel()
        if Model and type(Model.WriteLaneGrowthPair) == "function" then
            Model.WriteLaneGrowthPair(scope, lane, value)
            return
        end
        local x, y = "RIGHT", "DOWN"
        if value == "LEFTDOWN" then x = "LEFT"
        elseif value == "RIGHTUP" then y = "UP"
        elseif value == "LEFTUP" then x, y = "LEFT", "UP"
        elseif value == "UP" then x = "UP"
        elseif value == "DOWN" then x = "DOWN" end
        AuraWriteValue(scope, AuraLaneKey(lane, "buffGrowthX", "debuffGrowthX"), x)
        AuraWriteValue(scope, AuraLaneKey(lane, "buffGrowthY", "debuffGrowthY"), y)
    end

    return {
        AuraReadValue = AuraReadValue,
        AuraWriteValue = AuraWriteValue,
        AuraLaneKey = AuraLaneKey,
        AuraReadLaneAnchor = AuraReadLaneAnchor,
        AuraWriteLaneAnchor = AuraWriteLaneAnchor,
        AuraReadLaneLayer = AuraReadLaneLayer,
        AuraWriteLaneLayer = AuraWriteLaneLayer,
        AuraReadLaneSpacing = AuraReadLaneSpacing,
        AuraWriteLaneSpacing = AuraWriteLaneSpacing,
        AuraReadLaneGrowthPair = AuraReadLaneGrowthPair,
        AuraWriteLaneGrowthPair = AuraWriteLaneGrowthPair,
        AuraReadLaneStyleBool = StyleHelpers.AuraReadLaneStyleBool,
        AuraWriteLaneStyleBool = StyleHelpers.AuraWriteLaneStyleBool,
        AuraReadLaneStyleNumber = StyleHelpers.AuraReadLaneStyleNumber,
        AuraWriteLaneStyleNumber = StyleHelpers.AuraWriteLaneStyleNumber,
        AuraReadLaneStackAnchor = StyleHelpers.AuraReadLaneStackAnchor,
        AuraWriteLaneStackAnchor = StyleHelpers.AuraWriteLaneStackAnchor,
        AuraReadLaneCooldownAnchor = StyleHelpers.AuraReadLaneCooldownAnchor,
        AuraWriteLaneCooldownAnchor = StyleHelpers.AuraWriteLaneCooldownAnchor,
    }
end
