-- Regression coverage for the 12.1 group-health hotpath. AI/follower units
-- use the same native percent route as ordinary party/raid members; text
-- requirements and Prediction must not pull detailed-health calculation into
-- every UNIT_HEALTH event.
local root = arg and arg[1] or "."

local function Check(condition, message)
  if not condition then error(message or "check failed", 2) end
end

_G.issecretvalue = function() return false end

local aiChecks, detailedCalls = 0, 0
local calculatorCreates, healthReads, maxReads, percentReads = 0, 0, 0, 0
local colorCalls, predictionEventRegistrations = 0, 0
_G.UnitInPartyIsAI = function()
  aiChecks = aiChecks + 1
  return true
end
_G.CreateUnitHealPredictionCalculator = function()
  calculatorCreates = calculatorCreates + 1
  return {}
end
_G.UnitGetDetailedHealPrediction = function()
  detailedCalls = detailedCalls + 1
end
_G.MSUF_EventBus_Register = function()
  predictionEventRegistrations = predictionEventRegistrations + 1
  return true
end

local Health
local Prediction
local MSUF = {
  UF = {
    RegisterElement = function(name, element)
      if name == "Health" then Health = element end
      if name == "Prediction" then Prediction = element end
    end,
  },
  UFBarTextCommon = {
    UnitHealthPercent = function()
      percentReads = percentReads + 1
      return 80
    end,
    UnitHealth = function()
      healthReads = healthReads + 1
      return 80
    end,
    UnitHealthMax = function()
      maxReads = maxReads + 1
      return 100
    end,
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
Check(Health.ReadDetailedHealth == nil and MSUF.UF.ReadDetailedHealth == nil,
  "group Health retained the legacy detailed-health provider")

assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Prediction.lua"))(
  "MidnightSimpleUnitFrames", MSUF)
Check(Prediction ~= nil, "prediction element was not registered")
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
  _msufTextRuntime = {
    healthSlotCount = 1,
    healthNeedsCurrent = true,
    healthNeedsMax = true,
    healthNeedsMissing = true,
  },
  _msufIsGroupFrame = true,
  _msufHealthRuntimeColorEnabled = true,
  _msufHealthRuntimeGradient = false,
}

local update = Health.SelectUpdate(frame, frame.MSUFSpec)
local hp, hpMax, percentReady = update(frame, "UNIT_HEALTH", "party1")
Check(hp == 80 and hpMax == nil and percentReady == true
    and bar.value == 80 and bar.maximum == 100,
  "group health did not stay on the native percent route")
Check(percentReads == 1 and healthReads == 0 and maxReads == 0,
  "group text requirements leaked absolute health reads into UNIT_HEALTH")
Check(aiChecks == 0 and detailedCalls == 0 and calculatorCreates == 0,
  "AI/follower metadata or detailed prediction remained in group Health")
Check(colorCalls == 0,
  "steady positive group UNIT_HEALTH repeated the full runtime color path")

frame._msufHealthStatusGone = true
update(frame, "UNIT_HEALTH", "party1")
Check(percentReads == 2 and colorCalls == 1,
  "gone-state UNIT_HEALTH lost its revive/status recolor")
Check(detailedCalls == 0 and calculatorCreates == 0,
  "revive/status recolor reintroduced detailed-health work")
frame._msufHealthStatusGone = nil

local identityUpdate = Health.SelectEventUpdate(frame, frame.MSUFSpec, "UNIT_FACTION")
identityUpdate(frame, "UNIT_FACTION", "party1")
Check(colorCalls == 2 and percentReads == 2,
  "identity-only color event performed health-value work or skipped recolor")

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

print("PASS group health hotpath: native percent is independent of text, AI, and Prediction")
