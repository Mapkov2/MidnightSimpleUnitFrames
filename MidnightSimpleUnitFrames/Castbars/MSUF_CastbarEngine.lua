--- Castbars/MSUF_CastbarEngine.lua
--- Normalizes Blizzard cast/channel/empower API output into one cast-state
--- table used by the player, target, focus, boss, kick-ready, and preview code.
---
--- This is a data layer, not a visual layer. Keep frame mutation in Runtime,
--- Driver, Frames, or Visuals; Engine should answer "what is the unit casting?"
--- and cache only enough to avoid duplicate work within the same frame.

local _, ns = ...
ns = ns or {}

local Registry = ns.MSUF_CastbarRegistry

local PlainNumber = _G.MSUF_CastbarRuntime_PlainNumber or function(value)
    if value == nil then
        return nil
    end

    local toPlain = _G.ToPlain
    if type(toPlain) == "function" then
        local plain = toPlain(value)
        plain = tonumber(tostring(plain))
        if plain ~= nil then
            return plain
        end
    end

    local valueType = type(value)
    if valueType == "number" or valueType == "string" then
        return tonumber(tostring(value))
    end

    return nil
end

ns.MSUF_CastbarEngine = ns.MSUF_CastbarEngine or {}

local Engine = ns.MSUF_CastbarEngine
local buildStateCacheTime = {}

Engine.VERSION = 3
Engine._subs = Engine._subs or {}
Engine._state = Engine._state or {}

--- Tiny pub/sub hook for code that wants cast-state notifications without
--- taking ownership of the castbar frames themselves.
local function SubscriptionList(key)
    if not key then
        return nil
    end

    local subscriptions = Engine._subs[key]
    if not subscriptions then
        subscriptions = {}
        Engine._subs[key] = subscriptions
    end

    return subscriptions
end

function Engine:RegisterBar(key, unit, frame, meta)
    if Registry and Registry.Register then
        Registry:Register(key, unit, frame, meta)
    end
end

function Engine:UnregisterBar(key)
    if Registry and Registry.Unregister then
        Registry:Unregister(key)
    end
end

function Engine:Subscribe(key, callback)
    if not key or type(callback) ~= "function" then
        return
    end

    local subscriptions = SubscriptionList(key)
    subscriptions[#subscriptions + 1] = callback
end

function Engine:Notify(key, payload)
    local subscriptions = Engine._subs and Engine._subs[key]
    if not subscriptions then
        return
    end

    for index = 1, #subscriptions do
        local callback = subscriptions[index]
        if type(callback) == "function" then
            callback(payload)
        end
    end
end

function Engine:ForceRefresh()
end

function Engine:GetState(unit)
    return Engine._state and Engine._state[unit]
end

local EnsureDBLazy = _G.MSUF_EnsureDBLazy or function()
    if not MSUF_DB and type(EnsureDB) == "function" then
        EnsureDB()
    end
end

--- Fill direction is part of cast-state because channels/empower casts can run
--- opposite to normal casts unless the profile requests unified direction.
local function ReverseFillForCastType(castType, unit)
    EnsureDBLazy()

    local general = (MSUF_DB and MSUF_DB.general) or {}
    local reverseFill = (general.castbarFillDirection == "RTL") and true or false

    if unit == "target" and general.castbarOpositeDirectionTarget == true then
        reverseFill = not reverseFill
    end

    local unifiedDirection = general.castbarUnifiedDirection == true
    if castType == "CHANNEL" or castType == "EMPOWER" then
        if unifiedDirection then
            return reverseFill
        end

        return not reverseFill
    end

    return reverseFill
end

--- UNIT_SPELLCAST_INTERRUPTIBLE/NOT_INTERRUPTIBLE can arrive separately from
--- cast start. Preserve the previous value until the interruptibility event
--- confirms the new cast's state.
local function PreserveInterruptState(_, previousState)
    if previousState and previousState.isNotInterruptible ~= nil then
        return previousState.isNotInterruptible == true
    end

    return false
end

local function UnitIsEmpowering(unit)
    if unit ~= "player" then
        return false
    end

    if type(GetUnitEmpowerStageCount) ~= "function" then
        return false
    end

    local stageCount = PlainNumber(GetUnitEmpowerStageCount(unit))
    return type(stageCount) == "number" and stageCount > 0
end

--- Main API: return a reusable state table for the unit. The same-frame cache
--- avoids repeated UnitCastingInfo/UnitChannelInfo reads when multiple castbar
--- helpers ask for state during one event burst.
function Engine:BuildState(unit, previousState)
    if not unit then
        return { active = false }
    end

    local now = GetTime()
    if buildStateCacheTime[unit] == now and Engine._state[unit] then
        return Engine._state[unit]
    end

    buildStateCacheTime[unit] = now

    local state = Engine._state[unit]
    if not state then
        state = {}
        Engine._state[unit] = state
    end

    state.active = false
    state.unit = unit
    state.castType = "NONE"
    state.spellName = nil
    state.text = nil
    state.icon = nil
    state.spellId = nil
    state.startTimeMS = nil
    state.endTimeMS = nil
    state.durationObj = nil
    state.isNotInterruptible = false
    state.apiNotInterruptible = nil
    state.apiNotInterruptibleRaw = nil
    state.reverseFill = nil

    local name, text, icon, startTimeMS, endTimeMS, _, _, apiNotInterruptible, spellId = UnitCastingInfo(unit)
    if name then
        local isEmpower = UnitIsEmpowering(unit)

        state.castType = isEmpower and "EMPOWER" or "CAST"
        state.spellName = name
        state.text = text or name
        state.icon = icon
        state.spellId = spellId
        state.startTimeMS = startTimeMS
        state.endTimeMS = endTimeMS
        state.active = true
        state.apiNotInterruptible = apiNotInterruptible
        state.apiNotInterruptibleRaw = apiNotInterruptible
        state.isNotInterruptible = PreserveInterruptState(unit, previousState)

        if type(UnitCastingDuration) == "function" then
            state.durationObj = UnitCastingDuration(unit)
        end

        state.reverseFill = ReverseFillForCastType(state.castType, state.unit)
        return state
    end

    name, text, icon, startTimeMS, endTimeMS, _, apiNotInterruptible, spellId = UnitChannelInfo(unit)
    if name then
        state.castType = "CHANNEL"
        state.apiNotInterruptible = apiNotInterruptible
        state.apiNotInterruptibleRaw = apiNotInterruptible
        state.spellName = name
        state.text = text or name
        state.icon = icon
        state.spellId = spellId
        state.startTimeMS = startTimeMS
        state.endTimeMS = endTimeMS
        state.active = true
        state.isNotInterruptible = PreserveInterruptState(unit, previousState)

        if type(UnitChannelDuration) == "function" then
            state.durationObj = UnitChannelDuration(unit)
        end

        state.reverseFill = ReverseFillForCastType(state.castType, state.unit)
        return state
    end

    return state
end

if not _G.MSUF_BuildCastState then
    function _G.MSUF_BuildCastState(unit, previousState)
        return Engine:BuildState(unit, previousState)
    end
end

if not _G.MSUF_GetCastbarEngine then
    _G.MSUF_GetCastbarEngine = function()
        return Engine
    end
end
