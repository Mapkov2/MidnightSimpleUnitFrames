local now = 10
local cast = { active = true, castBarID = 44, duration = {} }

_G.GetTime = function() return now end
_G.issecretvalue = function() return false end
_G.UnitCastingInfo = function(unit)
    if unit ~= "focus" or not cast.active then return nil end
    return "Spell", "Spell", 1, 10000, 15000, false, "Cast-GUID", false, 123, cast.castBarID, 0
end
_G.UnitChannelInfo = function() return nil end
_G.UnitCastingDuration = function() return cast.duration end
_G.UnitChannelDuration = function() return nil end
_G.GetUnitEmpowerStageCount = function() return 0 end
_G.MSUF_DB = { general = {} }

local ns = {
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}
assert(loadfile("MidnightSimpleUnitFrames/Castbars/MSUF_CastbarEngine.lua"))("MSUF", ns)
local engine = assert(_G.MSUF_GetCastbarEngine())

cast.active = false
local idle = engine:BuildState("focus")
assert(idle.active == false and idle.castType == "NONE" and idle._msufInactiveNormalized == true,
    "initial inactive state was not normalized")
now = now + 0.01
engine:Invalidate("focus")
assert(engine:BuildState("focus") == idle and idle.spellName == nil and idle.castBarID == nil,
    "steady inactive rebuild changed or dirtied the reusable state")
cast.active = true
now = now + 0.01
engine:Invalidate("focus")

local state = engine:BuildState("focus")
assert(state.active and state.spellSequenceID == 44)
assert(state.identity.castBarID == 44 and state.identity.sequenceID == 44)
local firstIdentity = {
    active = true,
    unit = state.identity.unit,
    castType = state.identity.castType,
    castBarID = state.identity.castBarID,
    generation = state.identity.generation,
}

cast.duration = nil
now = now + 0.01
engine:Invalidate("focus")
state = engine:BuildState("focus")
assert(state.spellSequenceID == 44 and engine:SameIdentity(firstIdentity, state.identity),
    "transient nil duration changed canonical cast identity")

cast.castBarID = 45
cast.duration = {}
now = now + 0.01
engine:Invalidate("focus")
state = engine:BuildState("focus")
assert(state.spellSequenceID == 45 and not engine:SameIdentity(firstIdentity, state.identity),
    "new castBarID reused the previous identity")

cast.castBarID = nil
engine:AdvanceGeneration("focus")
now = now + 0.01
state = engine:BuildState("focus")
local fallbackSequence = state.spellSequenceID
assert(type(fallbackSequence) == "number" and fallbackSequence > 0)
now = now + 0.01
engine:Invalidate("focus")
assert(engine:BuildState("focus").spellSequenceID == fallbackSequence,
    "fallback generation changed within one cast")
engine:AdvanceGeneration("focus")
now = now + 0.01
assert(engine:BuildState("focus").spellSequenceID ~= fallbackSequence,
    "explicit cast start did not advance fallback identity")

local notifications = 0
local function subscriber(payload, event)
    assert(payload == state and event == "TEST")
    notifications = notifications + 1
end
assert(engine:Subscribe("focus", subscriber))
assert(engine:Subscribe("focus", subscriber), "duplicate subscription was rejected")
engine:Notify("focus", state, "TEST")
assert(notifications == 1, "duplicate subscription produced duplicate work")
assert(engine:Unsubscribe("focus", subscriber))
engine:Notify("focus", state, "TEST")
assert(notifications == 1, "disabled subscriber still received cast events")

print("castbar engine identity smoke: ok")
