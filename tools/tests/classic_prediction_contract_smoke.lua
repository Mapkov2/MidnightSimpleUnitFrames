local root = assert(arg[1], "repository root argument missing")
local registered

_G.CreateFrame = function() error("unexpected top-level prediction frame creation") end
_G.UnitExists = function() return true end
_G.UnitIsConnected = function() return true end
_G.UnitHealth = function() return 50 end
_G.UnitHealthMax = function() return 100 end
_G.UnitGetIncomingHeals = function() return 10 end
_G.UnitGetTotalAbsorbs = function() return 20 end
_G.UnitGetTotalHealAbsorbs = function() return 5 end
_G.issecretvalue = function() return false end

local namespace = {
    UF = {
        Layers = {},
        RegisterElement = function(name, element)
            assert(name == "Prediction", "unexpected prediction element name")
            registered = element
        end,
    },
}

local path = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Prediction.lua"
assert(loadfile(path))("MidnightSimpleUnitFrames", namespace)
assert(registered, "prediction element did not register")

local function EventSet(events)
    local out = {}
    for i = 1, #events do out[events[i]] = true end
    return out
end

local prediction = {
    enabled = true,
    heal = true,
    absorb = true,
    healAbsorb = true,
}
local targetEvents = EventSet(registered.GetEvents({ MSUFUnitKey = "target" }, { prediction = prediction }))
assert(targetEvents.UNIT_HEAL_PREDICTION
    and targetEvents.UNIT_ABSORB_AMOUNT_CHANGED
    and targetEvents.UNIT_HEAL_ABSORB_AMOUNT_CHANGED,
    "Classic prediction did not subscribe to all native data events")
assert(targetEvents.UNIT_MAXHEALTH and targetEvents.UNIT_CONNECTION,
    "Classic target prediction lifecycle events are incomplete")

local playerEvents = EventSet(registered.GetEvents({ MSUFUnitKey = "player" }, { prediction = prediction }))
assert(playerEvents.UNIT_CONNECTION ~= true,
    "player prediction registered an unnecessary connection event")

local groupEvents = EventSet(registered.GetUnitlessEvents(nil, {
    scope = "group", prediction = prediction,
}))
assert(groupEvents.PARTY_MEMBER_ENABLE and groupEvents.PARTY_MEMBER_DISABLE,
    "Classic group prediction lifecycle events are incomplete")

print("classic prediction contract smoke passed")
