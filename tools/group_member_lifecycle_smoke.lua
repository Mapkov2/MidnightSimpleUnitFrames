_G = _G or _ENV

local elements = {}
local aiChecks = 0
local percentCalls = 0
local healthPercent = 100
_G.issecretvalue = function() return false end
_G.C_Timer = {
  NewTimer = function()
    return { Cancel = function() end }
  end,
}
_G.UnitInPartyIsAI = function(unit)
  aiChecks = aiChecks + 1
  return unit == "party1"
end
local detailedCalls = 0
_G.GetTime = function() return 10 end
_G.CreateUnitHealPredictionCalculator = function()
  return {
    GetCurrentHealth = function() return 775000 end,
    GetMaximumHealth = function() return 775000 end,
  }
end
_G.UnitGetDetailedHealPrediction = function(unit, healer, calc)
  assert(unit == "party1" and healer == "player" and calc)
  detailedCalls = detailedCalls + 1
end

local MSUF = {
  UF = {
    RegisterElement = function(name, element) elements[name] = element end,
    IsUnitToken = function(unit) return type(unit) == "string" and unit ~= "" end,
  },
  UFBarTextCommon = {
    UF = nil,
    UnitHealthPercent = function(unit, usePredicted, curve)
      assert((unit == "party1" or unit == "party2") and usePredicted == true and curve == 100,
        "group health used the wrong native predicted-percent contract")
      percentCalls = percentCalls + 1
      return healthPercent
    end,
    SCALE_100 = 100,
    WHITE = "white",
    POWER_EVENTS = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_POWER_BAR_SHOW", "UNIT_POWER_BAR_HIDE" },
  },
  Secrets = { UnitMissing = function() return false end },
  GF = {},
}
MSUF.UFBarTextCommon.UF = MSUF.UF

assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua"))(
  "MidnightSimpleUnitFrames",
  MSUF
)
local Health = assert(elements.Health, "health element was not registered")

local function EventSet(events)
  local out = {}
  for i = 1, #events do out[events[i]] = true end
  return out
end

local groupEvents = EventSet(Health.GetEvents(nil, {
  scope = "group",
  health = { mode = "dark" },
}))
local groupUnitlessEvents = EventSet(Health.GetUnitlessEvents(nil, {
  scope = "group",
  health = { mode = "dark" },
}))
assert(groupEvents.UNIT_CONNECTION, "group health must refresh on connection changes")
assert(groupUnitlessEvents.PARTY_MEMBER_ENABLE and groupUnitlessEvents.PARTY_MEMBER_DISABLE,
  "group health must broadcast party availability changes")
assert(not groupEvents.PARTY_MEMBER_ENABLE and not groupEvents.PARTY_MEMBER_DISABLE,
  "group health must not unit-filter party lifecycle events")
assert(not groupEvents.INCOMING_RESURRECT_CHANGED,
  "health must not retain the obsolete resurrection timer event")

local unitEvents = EventSet(Health.GetEvents(nil, {
  scope = "unit",
  health = { mode = "dark" },
}))
assert(unitEvents.UNIT_CONNECTION, "health must refresh after reconnect")
assert(not unitEvents.PARTY_MEMBER_ENABLE and not unitEvents.PARTY_MEMBER_DISABLE,
  "non-group health must not subscribe to party lifecycle events")

assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Power.lua"))(
  "MidnightSimpleUnitFrames",
  MSUF
)
local Power = assert(elements.Power, "power element was not registered")
local powerEvents = EventSet(Power.GetEvents({ unit = "party1" }, {
  scope = "group",
  power = { enabled = true },
}))
assert(not powerEvents.PARTY_MEMBER_ENABLE and not powerEvents.PARTY_MEMBER_DISABLE,
  "group power must be refreshed by the shared lifecycle driver, not register the events itself")

assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Prediction.lua"))(
  "MidnightSimpleUnitFrames",
  MSUF
)
local Prediction = assert(elements.Prediction, "prediction element was not registered")
local predictionEvents = EventSet(Prediction.GetEvents({ unit = "party1" }, {
  scope = "group",
  prediction = { enabled = true, heal = true },
}))
local predictionUnitlessEvents = EventSet(Prediction.GetUnitlessEvents({ unit = "party1" }, {
  scope = "group",
  prediction = { enabled = true, heal = true },
}))
assert(predictionUnitlessEvents.PARTY_MEMBER_ENABLE and predictionUnitlessEvents.PARTY_MEMBER_DISABLE,
  "group prediction must broadcast party lifecycle events")
assert(not predictionEvents.PARTY_MEMBER_ENABLE and not predictionEvents.PARTY_MEMBER_DISABLE,
  "group prediction must not unit-filter party lifecycle events")

local bar = {}
function bar:SetMinMaxValues(minimum, maximum) self.minimum, self.maximum = minimum, maximum end
function bar:SetValue(value) self.value = value end
function bar:SetStatusBarColor() end
local predictionCfg = { enabled = true, heal = true }
local lifecycleFrame = {
  unit = "party1",
  hpBar = bar,
  MSUFSpec = { scope = "group", health = { mode = "dark" }, prediction = predictionCfg },
  _msufPredictionRuntimeCfg = predictionCfg,
  _msufIsGroupFrame = true,
  _msufDispatchActive = true,
  _msufDispatchToken = 1,
}
Health.Update(lifecycleFrame, "PARTY_MEMBER_ENABLE", "party1")
assert(bar.value == 100 and bar.maximum == 100,
  "party enable must use the native predicted-percent group path")
assert(bar._msufHealthPercentValue == 100 and bar._msufHealthPercentUnit == "party1"
    and bar._msufHealthValue == nil and bar._msufHealthMax == nil,
  "group lifecycle health must seed only the percent cache")
assert(Prediction.ReadDetailedHealth == nil and Health.UpdateGroupLifecycleMetadata == nil
    and detailedCalls == 0 and aiChecks == 0 and percentCalls == 1,
  "group lifecycle health restored the removed AI/detailed-health path")

local statusSeed, goneSeed
lifecycleFrame._msufUpdateGroupStatusState = function(_, event, unit, hp)
  assert(event == "UNIT_HEALTH" and unit == "party1")
  statusSeed = hp
  if type(hp) == "number" and hp > 0 then
    lifecycleFrame._msufStatusTextValue = nil
  end
end
lifecycleFrame._msufUpdateGroupVisualsGoneState = function(_, event, unit, hp)
  assert(event == "UNIT_HEALTH" and unit == "party1")
  goneSeed = hp
end
lifecycleFrame._msufDispatchActive = true
healthPercent = 61
Health.Update(lifecycleFrame, "UNIT_HEALTH", "party1")
assert(detailedCalls == 0 and aiChecks == 0 and percentCalls == 2 and bar.value == 61,
  "group UNIT_HEALTH must stay on one native predicted-percent read")
assert(statusSeed == nil and goneSeed == 61,
  "living group health must skip status while still seeding dead-background recovery")
lifecycleFrame._msufStatusTextValue = "DEAD"
healthPercent = 70
Health.Update(lifecycleFrame, "UNIT_HEALTH", "party1")
assert(statusSeed == 70 and goneSeed == 70,
  "positive group health must clear a stale gone status in the same dispatch")

local normalBar = {}
function normalBar:SetMinMaxValues(minimum, maximum) self.minimum, self.maximum = minimum, maximum end
function normalBar:SetValue(value) self.value = value end
function normalBar:SetStatusBarColor() end
local normalFrame = {
  unit = "party2",
  hpBar = normalBar,
  MSUFSpec = { scope = "group", health = { mode = "dark" } },
  _msufIsGroupFrame = true,
  _msufDispatchActive = true,
  _msufDispatchToken = 1,
}
healthPercent = 80
Health.Update(normalFrame, "UNIT_HEALTH", "party2")
assert(normalBar.value == 80 and detailedCalls == 0 and aiChecks == 0 and percentCalls == 4,
  "all group members must share the predicted-percent fastpath")

MSUF.UFVisuals = { UF = MSUF.UF }
assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Portrait.lua"))(
  "MidnightSimpleUnitFrames",
  MSUF
)
local Portrait = assert(elements.Portrait, "portrait element was not registered")
local portraitEvents = EventSet(Portrait.GetEvents({ unit = "party1" }, {
  scope = "group",
  portrait = { enabled = true, render = "2D" },
}))
local portraitUnitlessEvents = EventSet(Portrait.GetUnitlessEvents({ unit = "party1" }, {
  scope = "group",
  portrait = { enabled = true, render = "2D" },
}))
assert(not portraitUnitlessEvents.PARTY_MEMBER_ENABLE and not portraitUnitlessEvents.PARTY_MEMBER_DISABLE,
  "group portrait must be refreshed by the shared lifecycle driver")
assert(not portraitEvents.PARTY_MEMBER_ENABLE and not portraitEvents.PARTY_MEMBER_DISABLE,
  "group portrait must not unit-filter party lifecycle events")

_G.MSUF = MSUF
assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Range/MSUF_UF_Group_RangeFade.lua"))(
  "MidnightSimpleUnitFrames",
  MSUF
)
local GroupRangeFade = assert(elements.GroupRangeFade, "group range element was not registered")
local rangeEvents = EventSet(GroupRangeFade.GetEvents({ unit = "party1" }, {
  scope = "group",
  group = { rangeFadeEnabled = true, hideOfflineEnabled = true },
}))
local rangeUnitlessEvents = EventSet(GroupRangeFade.GetUnitlessEvents({ unit = "party1" }, {
  scope = "group",
  group = { rangeFadeEnabled = true, hideOfflineEnabled = true },
}))
assert(not rangeUnitlessEvents.PARTY_MEMBER_ENABLE and not rangeUnitlessEvents.PARTY_MEMBER_DISABLE,
  "group range must be refreshed by the shared lifecycle driver")
assert(not rangeEvents.PARTY_MEMBER_ENABLE and not rangeEvents.PARTY_MEMBER_DISABLE,
  "group range must not unit-filter party lifecycle events")

print("group member lifecycle smoke: ok")
