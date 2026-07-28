_G = _G or _ENV

local now = 10
local detailedReads = 0
local incomingReads = 0
local unitExists = true
local Prediction

_G.GetTime = function() return now end
_G.issecretvalue = function() return false end
_G.UnitExists = function() return unitExists end
_G.UnitIsConnected = function() return true end
_G.UnitHealth = function() return 80 end
_G.UnitHealthMax = function() return 100 end
_G.UnitGetIncomingHeals = function() incomingReads = incomingReads + 1; return 10 end
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

local cfg = { enabled = true, heal = true, healAnchorMode = 3, test = false }
local refreshHeal = { [1] = true, [4] = true, [7] = true }
local bar = {}
function bar:SetMinMaxValues(minValue, maxValue) self.minValue, self.maxValue = minValue, maxValue end
function bar:SetValue(value) self.value = value; self.valueWrites = (self.valueWrites or 0) + 1 end
function bar:SetShown(shown) self.shown = shown end

local frame = {
  unit = "party1",
  MSUFUnitKey = "party1",
  incomingHealBar = bar,
  _msufPredictionRuntimeCfg = cfg,
  _msufPredictionMask = 1,
  _msufPredictionHealActive = true,
  _msufPredictionNeedsHealth = false,
  _msufPredictionHealMode = 3,
  _msufPredictionConnectionUnit = "party1",
  _msufPredictionConnectionOnline = true,
  _msufPredictionFullHealthAlphaReady = true,
  _msufPredictionFullHealthAlphaUnit = "party1",
  _msufPredictionEventPlans = {
    UNIT_HEAL_PREDICTION = refreshHeal,
  },
  _msufPredictionFullPlan = refreshHeal,
}

local events = Prediction.GetEvents(frame, { prediction = cfg })
for i = 1, #events do
  assert(events[i] ~= "UNIT_HEALTH", "mode-3 heal retained its health-event dependency")
end

Prediction.Update(frame, "UNIT_HEAL_PREDICTION", "party1")
assert(incomingReads == 1 and detailedReads == 0,
  "mode-3 heal did not use exactly one raw prediction read")
assert(bar.value == 10 and bar.shown == true, "prediction data event did not paint its value")
local valueWrites = bar.valueWrites
Prediction.Update(frame, "UNIT_HEALTH", "party1", 80, 100)
assert(incomingReads == 1 and detailedReads == 0,
  "UNIT_HEALTH re-entered a prediction data/calculator path")
assert(bar.valueWrites == valueWrites, "health event rewrote mode-3 prediction")

local compiledPlans = frame._msufPredictionEventPlans
unitExists = false
Prediction.Update(frame, "MSUF_UF_ONSHOW", "party1")
assert(frame._msufPredictionDisabled == true and bar.shown == false,
  "missing unit did not suspend prediction visuals")
assert(frame._msufPredictionRuntimeCfg == cfg
    and frame._msufPredictionEventPlans == compiledPlans
    and frame._msufPredictionMask == 1,
  "temporary missing unit discarded the compiled prediction runtime")
assert(frame._msufPredictionConnectionUnit == nil
    and frame._msufPredictionConnectionOnline == nil
    and frame._msufPredictionFullHealthAlphaReady == nil
    and frame._msufPredictionFullHealthAlphaDirty == true
    and frame._msufPredictionFullHealthAlphaUnit == nil,
  "temporary missing unit retained stale identity-owned prediction state")

unitExists = true
Prediction.Update(frame, "MSUF_UF_ONSHOW", "party1")
assert(frame._msufPredictionDisabled == nil
    and frame._msufPredictionRuntimeCfg == cfg
    and frame._msufPredictionEventPlans == compiledPlans,
  "reappearing unit did not reuse the compiled prediction runtime")

Prediction.Disable(frame)
assert(frame._msufPredictionDisabled == true
    and frame._msufPredictionRuntimeCfg == nil
    and frame._msufPredictionEventPlans == nil
    and frame._msufPredictionMask == 0,
  "authoritative prediction disable retained compiled runtime state")

print("prediction fastpath smoke: ok")
