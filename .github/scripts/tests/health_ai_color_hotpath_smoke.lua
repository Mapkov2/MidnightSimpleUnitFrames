-- Regression coverage for the AI/follower health color hotpath. Ordinary
-- positive UNIT_HEALTH updates must retain detailed health while avoiding a
-- complete class/NPC/status recolor. Identity/status events still recolor.
local root = arg and arg[1] or "."

local function Check(condition, message)
  if not condition then error(message or "check failed", 2) end
end

_G.issecretvalue = function() return false end
_G.UnitInPartyIsAI = function(unit) return unit == "party1" end

local Health
local Prediction
local detailedCalls, colorCalls = 0, 0
local calculatorCreates, predictionEventRegistrations = 0, 0
local sharedHealthCalculator

_G.CreateUnitHealPredictionCalculator = function()
  calculatorCreates = calculatorCreates + 1
  local calc = {
    GetCurrentHealth = function() return 80 end,
    GetMaximumHealth = function() return 100 end,
  }
  sharedHealthCalculator = sharedHealthCalculator or calc
  return calc
end
_G.UnitGetDetailedHealPrediction = function(unit, healer)
  Check(unit == "party1" and healer == "player",
    "detailed health used the wrong unit/healer contract")
  detailedCalls = detailedCalls + 1
end
_G.MSUF_EventBus_Register = function()
  predictionEventRegistrations = predictionEventRegistrations + 1
  return true
end

local MSUF = {
  UF = {
    RegisterElement = function(name, element)
      if name == "Health" then Health = element end
      if name == "Prediction" then Prediction = element end
    end,
  },
  UFBarTextCommon = {
    UnitHealthPercent = function() return 80 end,
    UnitHealth = function() return 80 end,
    UnitHealthMax = function() return 100 end,
    SCALE_100 = 100,
    WHITE = "white",
    ApplyHealthStatusColor = function()
      colorCalls = colorCalls + 1
      return false
    end,
  },
}
MSUF.UFBarTextCommon.UF = MSUF.UF

assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua"))(
  "MidnightSimpleUnitFrames", MSUF)
Check(Health ~= nil, "health element was not registered")
local healthOwnedReader = MSUF.UF.ReadDetailedHealth
Check(type(healthOwnedReader) == "function", "Health did not publish its detailed-health source")

assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Prediction.lua"))(
  "MidnightSimpleUnitFrames", MSUF)
Check(Prediction ~= nil, "prediction element was not registered")
Check(MSUF.UF.ReadDetailedHealth == healthOwnedReader,
  "Prediction replaced the Health-owned detailed-health source")
Check(MSUF.UF.ReadPredictionDetailedHealth == nil and Prediction.ReadDetailedHealth == nil,
  "Prediction retained a detailed-health compatibility provider")
Check(predictionEventRegistrations == 0,
  "disabled Prediction registered a lifecycle event at module load")

local bar = {}
function bar:SetMinMaxValues(minimum, maximum)
  self.minimum, self.maximum = minimum, maximum
end
function bar:SetValue(value) self.value = value end
function bar:SetStatusBarColor() end

local frame = {
  unit = "party1",
  MSUFUnitKey = "party1",
  hpBar = bar,
  MSUFSpec = {
    scope = "group",
    health = { mode = "class", npcClassColorBar = true },
  },
  _msufIsGroupFrame = true,
  _msufHealthAIUnit = "party1",
  _msufHealthAI = true,
  _msufHealthRuntimeColorEnabled = true,
  _msufHealthRuntimeGradient = false,
}

local update = Health.SelectUpdate(frame, frame.MSUFSpec)
update(frame, "UNIT_HEALTH", "party1")
Check(detailedCalls == 1 and bar.value == 80 and bar.maximum == 100,
  "AI health lost its authoritative detailed-health update")
Check(calculatorCreates == 1 and frame._msufPredictionCalc == nil,
  "prediction-disabled AI health created frame-owned Prediction state")
Check((Prediction._msufActiveLifecycleCount or 0) == 0,
  "prediction-disabled AI health activated the Prediction lifecycle")
Check(colorCalls == 0,
  "steady positive AI UNIT_HEALTH repeated the full runtime color path")

frame._msufHealthStatusGone = true
update(frame, "UNIT_HEALTH", "party1")
Check(detailedCalls == 2 and colorCalls == 1,
  "gone-state UNIT_HEALTH lost its revive/status recolor")
Check(calculatorCreates == 1,
  "prediction-disabled AI health stopped reusing the shared Health calculator")
frame._msufHealthStatusGone = nil

-- A calculator left on the frame by a formerly enabled overlay must not pull
-- disabled Prediction back into AI health. Only an active runtime config can
-- select the Prediction provider.
local stalePredictionCalc = {}
frame._msufPredictionCalc = stalePredictionCalc
update(frame, "UNIT_HEALTH", "party1")
Check(detailedCalls == 3 and calculatorCreates == 1,
  "stale Prediction state bypassed the Health-owned calculator")
Check(stalePredictionCalc._msufPredictionUpdateUnit == nil,
  "stale Prediction calculator was refreshed while Prediction was disabled")

-- Even an active-looking Prediction state cannot select a frame calculator.
-- Detailed health remains the independent shared AI-only source.
local activePredictionCalc = {}
frame._msufPredictionCalc = activePredictionCalc
frame._msufPredictionRuntimeCfg = { enabled = true }
local activeHP, activeMax, activeCalc = MSUF.UF.ReadDetailedHealth(frame, "party1")
Check(activeHP == 80 and activeMax == 100 and activeCalc == sharedHealthCalculator,
  "active Prediction state replaced the independent AI-health calculator")
Check(activeCalc ~= activePredictionCalc,
  "AI health reused a frame-owned Prediction calculator")
frame._msufPredictionRuntimeCfg = nil

local detailedBeforeNonAI = detailedCalls
frame._msufHealthAI = false
Check(MSUF.UF.ReadDetailedHealth(frame, "party1") == nil,
  "ordinary group member entered the AI detailed-health source")
Check(detailedCalls == detailedBeforeNonAI,
  "ordinary group member performed a detailed-health API read")
frame._msufHealthAI = true

local identityUpdate = Health.SelectEventUpdate(frame, frame.MSUFSpec, "UNIT_FACTION")
identityUpdate(frame, "UNIT_FACTION", "party1")
Check(colorCalls == 2 and detailedCalls == 4,
  "identity-only color event performed health work or skipped recolor: colors="
    .. tostring(colorCalls) .. " detailed=" .. tostring(detailedCalls))

local function HasEvent(events, wanted)
  for i = 1, #events do
    if events[i] == wanted then return true end
  end
  return false
end

local classEvents = Health.GetEvents(frame, frame.MSUFSpec)
Check(HasEvent(classEvents, "UNIT_FACTION")
    and HasEvent(classEvents, "UNIT_CLASSIFICATION_CHANGED")
    and HasEvent(classEvents, "UNIT_NAME_UPDATE")
    and HasEvent(classEvents, "UNIT_LEVEL"),
  "identity-colored health mode lacks explicit identity invalidation events")

local gradientSpec = { scope = "group", health = { mode = "gradient" } }
local gradientEvents = Health.GetEvents(frame, gradientSpec)
Check(not HasEvent(gradientEvents, "UNIT_FACTION")
    and not HasEvent(gradientEvents, "UNIT_CLASSIFICATION_CHANGED"),
  "gradient health inherited unnecessary identity event subscriptions")

print("PASS AI health color hotpath: detailed values stay live, stable identity recolor is event-driven")
