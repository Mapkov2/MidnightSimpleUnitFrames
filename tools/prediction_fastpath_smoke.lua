_G = _G or _ENV

local now = 10
local detailedReads = 0
local Prediction

_G.GetTime = function() return now end
_G.issecretvalue = function() return false end
_G.UnitExists = function() return true end
_G.UnitIsConnected = function() return true end
_G.UnitHealth = function() return 80 end
_G.UnitHealthMax = function() return 100 end
_G.UnitGetIncomingHeals = function() return 10 end
_G.UnitGetDetailedHealPrediction = function()
  detailedReads = detailedReads + 1
end
_G.CreateUnitHealPredictionCalculator = function() return {} end

local MSUF = {
  UF = {
    RegisterElement = function(name, element)
      if name == "Prediction" then Prediction = element end
    end,
  },
}

assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Prediction.lua"))(
  "MidnightSimpleUnitFrames",
  MSUF
)
assert(Prediction, "prediction element was not registered")

local cfg = { enabled = true, heal = true, test = false }
local refreshHeal = { [1] = true }
local bar = {}
function bar:SetMinMaxValues(minValue, maxValue) self.minValue, self.maxValue = minValue, maxValue end
function bar:SetValue(value) self.value = value end
function bar:SetShown(shown) self.shown = shown end

local frame = {
  unit = "party1",
  incomingHealBar = bar,
  _msufPredictionRuntimeCfg = cfg,
  _msufPredictionMask = 1,
  _msufPredictionHealActive = true,
  _msufPredictionNeedsHealth = true,
  _msufPredictionHealMode = 3,
  _msufPredictionEventPlans = {
    UNIT_HEAL_PREDICTION = refreshHeal,
    UNIT_ABSORB_AMOUNT_CHANGED = refreshHeal,
  },
  _msufPredictionFullPlan = refreshHeal,
  _msufDispatchActive = true,
  _msufDispatchToken = 1,
}

Prediction.Update(frame, "UNIT_HEAL_PREDICTION", "party1")
Prediction.Update(frame, "UNIT_ABSORB_AMOUNT_CHANGED", "party1")
assert(detailedReads == 1, "one dispatch must reuse its detailed prediction snapshot")

frame._msufDispatchToken = 2
Prediction.Update(frame, "UNIT_HEAL_PREDICTION", "party1")
assert(detailedReads == 2,
  "a new dispatch at the same GetTime must refresh detailed prediction")

frame._msufDispatchToken = 3
Prediction.Update(frame, "UNIT_HEALTH", "party1", 80, 100)
assert(detailedReads == 2, "UNIT_HEALTH must use the cached health fastpath")
assert(bar.value == 10 and bar.shown == true, "health fastpath must repaint cached prediction")

print("prediction fastpath smoke: ok")
