--- Castbars/MSUF_CastbarEngine.lua
--- Normalizes Blizzard cast/channel/empower API output into one cast-state
--- table used by the player, target, focus, boss, kick-ready, and preview code.
---
--- This is a data layer, not a visual layer. Keep frame mutation in Runtime,
--- Driver, Frames, or Visuals; Engine should answer "what is the unit casting?"
--- and cache only enough to avoid duplicate work within the same frame.

local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

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
ns.Castbars = ns.Castbars or {}
ns.Castbars.Engine = Engine
local buildStateCacheTime = {}
local INACTIVE_STATE = { active = false }
local GetTime = _G.GetTime
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local UnitCastingDuration = _G.UnitCastingDuration
local UnitChannelDuration = _G.UnitChannelDuration
local GetUnitEmpowerStageCount = _G.GetUnitEmpowerStageCount
local UnitShouldDisplaySpellTargetName = _G.UnitShouldDisplaySpellTargetName
local UnitSpellTargetName = _G.UnitSpellTargetName
local UnitSpellTargetClass = _G.UnitSpellTargetClass
local ToPlain = _G.ToPlain
local issecretvalue = _G.issecretvalue or function(_) return false end

Engine.VERSION = 4
Engine._subs = Engine._subs or {}
Engine._state = Engine._state or {}
Engine._generation = Engine._generation or {}

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

function Engine:Subscribe(key, callback)
    if not key or type(callback) ~= "function" then
        return false
    end

    local subscriptions = SubscriptionList(key)
    for index = 1, #subscriptions do
        if subscriptions[index] == callback then return true end
    end
    subscriptions[#subscriptions + 1] = callback
    return true
end

function Engine:Unsubscribe(key, callback)
    local subscriptions = key and self._subs and self._subs[key]
    if not subscriptions then return false end
    for index = #subscriptions, 1, -1 do
        if subscriptions[index] == callback then
            table.remove(subscriptions, index)
            if #subscriptions == 0 then self._subs[key] = nil end
            return true
        end
    end
    return false
end

function Engine:Notify(key, payload, event)
    local subscriptions = Engine._subs and Engine._subs[key]
    if not subscriptions then
        return
    end

    for index = 1, #subscriptions do
        local callback = subscriptions[index]
        if type(callback) == "function" then
            callback(payload, event)
        end
    end
end

function Engine:AdvanceGeneration(unit)
    if not unit then return 0 end
    local generation = (self._generation[unit] or 0) + 1
    self._generation[unit] = generation
    self:Invalidate(unit)
    return generation
end

function Engine:ForceRefresh()
end

function Engine:Invalidate(unit)
    if unit then
        buildStateCacheTime[unit] = nil
        return
    end

    for key in pairs(buildStateCacheTime) do
        buildStateCacheTime[key] = nil
    end
end

function Engine:GetState(unit)
    return Engine._state and Engine._state[unit]
end

local function ApplyIdentity(state)
    local generation = Engine._generation[state.unit] or 0
    if generation == 0 and state.active == true then
        generation = 1
        Engine._generation[state.unit] = generation
    end

    local sequenceID = type(state.castBarID) == "number" and state.castBarID or generation
    state.spellSequenceID = sequenceID
    local identity = state.identity
    if not identity then
        identity = {}
        state.identity = identity
    end
    identity.unit = state.unit
    identity.castType = state.castType
    identity.castBarID = type(state.castBarID) == "number" and state.castBarID or nil
    identity.generation = generation
    identity.sequenceID = sequenceID
    identity.active = state.active == true
    return identity
end

function Engine:SameIdentity(left, right)
    left = left and (left.identity or left)
    right = right and (right.identity or right)
    if not (left and right and left.active ~= false and right.active ~= false) then return false end
    if left.unit ~= right.unit or left.castType ~= right.castType then return false end
    if left.castBarID ~= nil or right.castBarID ~= nil then
        return left.castBarID ~= nil and left.castBarID == right.castBarID
    end
    return left.generation ~= nil and left.generation == right.generation
end

local EnsureDBLazy = _G.MSUF_EnsureDBLazy or function()
    if not MSUF_DB and type(EnsureDB) == "function" then
        EnsureDB()
    end
end

--- Profession casts are filtered out before any frame work happens. The flag is
--- NeverSecret in 12.x, so the filter also holds for PvP-restricted units.
local function HideTradeSkillCasts()
    EnsureDBLazy()
    local general = (MSUF_DB and MSUF_DB.general) or {}
    return general.castbarHideTradeSkills == true
end

--- The fill anchor is independent of cast type. Casts and empower bars count
--- up from this edge; non-unified channels keep the edge and count down.
local function ReverseFillForCastType(_, unit)
    EnsureDBLazy()

    local general = (MSUF_DB and MSUF_DB.general) or {}
    local reverseFill = (general.castbarFillDirection == "RTL") and true or false

    if unit == "target" and general.castbarOpositeDirectionTarget == true then
        reverseFill = not reverseFill
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

local function PlainBool(value)
    if value == nil then
        return false
    end

    if issecretvalue(value) == true and type(ToPlain) == "function" then
        value = ToPlain(value)
    end

    return value == true or value == 1 or value == "true"
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

local function ResetState(state, unit)
    state.active = false
    state.unit = unit
    state.castType = "NONE"
    state.spellName = nil
    state.text = nil
    state.icon = nil
    state.spellId = nil
    state.castID = nil
    state.castBarID = nil
    state.spellSequenceID = nil
    state.delayTimeMS = nil
    state.isTradeskill = nil
    state.isEmpowered = nil
    state.numEmpowerStages = nil
    state.startTimeMS = nil
    state.endTimeMS = nil
    state.durationObj = nil
    state.isNotInterruptible = false
    state.apiNotInterruptible = nil
    state.apiNotInterruptibleRaw = nil
    state.reverseFill = nil
    state.targetInfoReady = nil
    state.targetNameAllowed = nil
    state.targetName = nil
    state.targetClass = nil
    state._msufInactiveNormalized = true
end

--- Main API: return a reusable state table for the unit. The same-frame cache
--- avoids repeated UnitCastingInfo/UnitChannelInfo reads when multiple castbar
--- helpers ask for state during one event burst.
function Engine:BuildState(unit, previousState)
    if not unit then
        return INACTIVE_STATE
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

    local name, text, icon, startTimeMS, endTimeMS, isTradeskill, castID, apiNotInterruptible, spellId, castBarID, delayTimeMS = UnitCastingInfo(unit)
    if name and HideTradeSkillCasts() and isTradeskill == true then
        -- isTradeskill is NeverSecret, so this comparison also holds for
        -- PvP-restricted units. Drop the cast before any frame work happens.
        name = nil
    end
    if name then
        ResetState(state, unit)
        state._msufInactiveNormalized = nil
        local isEmpower = UnitIsEmpowering(unit)

        state.castType = isEmpower and "EMPOWER" or "CAST"
        state.spellName = name
        state.text = text or name
        state.icon = icon
        state.spellId = spellId
        state.castID = castID
        state.castBarID = castBarID
        state.delayTimeMS = delayTimeMS
        state.isTradeskill = isTradeskill
        state.isEmpowered = isEmpower
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
        ApplyIdentity(state)
        return state
    end

    name, text, icon, startTimeMS, endTimeMS, isTradeskill, apiNotInterruptible, spellId, isEmpowered, numEmpowerStages, castBarID = UnitChannelInfo(unit)
    if name and HideTradeSkillCasts() and isTradeskill == true then
        name = nil
    end
    if name then
        ResetState(state, unit)
        state._msufInactiveNormalized = nil
        state.castType = "CHANNEL"
        state.apiNotInterruptible = apiNotInterruptible
        state.apiNotInterruptibleRaw = apiNotInterruptible
        state.spellName = name
        state.text = text or name
        state.icon = icon
        state.spellId = spellId
        state.castBarID = castBarID
        state.isTradeskill = isTradeskill
        state.isEmpowered = isEmpowered
        state.numEmpowerStages = numEmpowerStages
        state.startTimeMS = startTimeMS
        state.endTimeMS = endTimeMS
        state.active = true
        state.isNotInterruptible = PreserveInterruptState(unit, previousState)

        if type(UnitChannelDuration) == "function" then
            state.durationObj = UnitChannelDuration(unit)
        end

        state.reverseFill = ReverseFillForCastType(state.castType, state.unit)
        ApplyIdentity(state)
        return state
    end

    -- A target/focus that remains idle is the dominant identity-switch case.
    -- Its reusable state is already fully nil-normalized, so avoid rewriting
    -- the same fields until an active cast has populated them again.
    if state._msufInactiveNormalized ~= true then
        ResetState(state, unit)
    end
    ApplyIdentity(state)
    return state
end

function Engine:ResolveTargetInfo(state)
    if not (state and state.active == true and state.unit) then
        return nil
    end

    if state.targetInfoReady == true then
        return state.targetName, state.targetClass, state.targetNameAllowed == true
    end

    state.targetInfoReady = true
    state.targetNameAllowed = false
    state.targetName = nil
    state.targetClass = nil

    local unit = state.unit
    if not (UnitShouldDisplaySpellTargetName and UnitSpellTargetName) then
        return nil
    end

    if not UnitShouldDisplaySpellTargetName(unit) then
        return nil
    end

    local targetName = UnitSpellTargetName(unit)
    state.targetNameAllowed = true
    state.targetName = targetName
    if UnitSpellTargetClass then
        state.targetClass = UnitSpellTargetClass(unit)
    end

    return state.targetName, state.targetClass, true
end

if not _G.MSUF_BuildCastState then
    ExportPublic("MSUF_BuildCastState", function(unit, previousState)
        return Engine:BuildState(unit, previousState)
    end)
end

if not _G.MSUF_ResolveCastbarTargetInfo then
    ExportPublic("MSUF_ResolveCastbarTargetInfo", function(state)
        return Engine:ResolveTargetInfo(state)
    end)
end

if not _G.MSUF_GetCastbarEngine then
    ExportPublic("MSUF_GetCastbarEngine", function()
        return Engine
    end)
end
