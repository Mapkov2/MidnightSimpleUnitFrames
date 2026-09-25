local root = assert(arg[1], "repository root argument missing")
local registered

_G.CreateFrame = function() error("unexpected top-level prediction frame creation") end
_G.UnitExists = function() return true end
_G.UnitIsConnected = function() return true end
_G.UnitHealth = function() return 50 end
_G.UnitHealthMax = function() return 100 end
local incomingUnit, incomingSource
_G.UnitGetIncomingHeals = function(unit, source)
    incomingUnit, incomingSource = unit, source
    return source == "player" and 10 or 25
end
local detailedUnit, detailedSource
_G.UnitGetDetailedHealPrediction = function(unit, source)
    detailedUnit, detailedSource = unit, source
end
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

local function Upvalue(fn, wanted)
    for index = 1, 100 do
        local name, value = debug.getupvalue(fn, index)
        if not name then break end
        if name == wanted then return value end
    end
    error("missing prediction upvalue: " .. wanted)
end

local compile = Upvalue(registered.Apply, "CompilePredictionRuntime")
local readIncoming = Upvalue(Upvalue(compile, "FlushFlatPrediction"), "ReadIncomingHeals")
local readMixed = Upvalue(compile, "ReadMixedFollowAbsorbs")
local frame = { _msufPredictionAbsorbClampCalc = { GetDamageAbsorbs = function() return 20 end } }
compile(frame, { enabled = true, heal = true, healAllHealers = false }, {})
assert(readIncoming(frame, "raid1") == 10 and incomingUnit == "raid1" and incomingSource == "player",
    "own-heal mode did not filter incoming heals to the player")
assert(readMixed(frame, "raid1") == 20 and detailedUnit == "raid1" and detailedSource == "player",
    "own-heal mode did not filter the detailed calculator to the player")
compile(frame, { enabled = true, heal = true, healAllHealers = true }, {})
assert(readIncoming(frame, "raid1") == 25 and incomingUnit == "raid1" and incomingSource == nil,
    "all-healer mode did not read total incoming heals")
assert(readMixed(frame, "raid1") == 20 and detailedUnit == "raid1" and detailedSource == nil,
    "all-healer mode did not use total incoming heals for the detailed calculator")

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
