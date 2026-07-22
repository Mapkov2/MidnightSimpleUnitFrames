_G = _G or _ENV

local elements = {}
local aiChecks = 0
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
local detailedCurrent = 775000
_G.GetTime = function() return 10 end
_G.CreateUnitHealPredictionCalculator = function()
  return {
    GetCurrentHealth = function() return detailedCurrent end,
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
    UnitHealthPercent = function() return 100 end,
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
assert(bar.value == 775000 and bar.maximum == 775000,
  "party enable must use committed detailed health instead of stale direct health")
assert(bar._msufHealthValue == 775000 and bar._msufHealthMax == 775000,
  "detailed lifecycle health must seed the shared bar/text cache")
assert(Prediction.ReadDetailedHealth == nil and detailedCalls == 1,
  "Prediction restored the removed detailed-health compatibility provider")
lifecycleFrame._msufDispatchToken = 2
Health.Update(lifecycleFrame, "PARTY_MEMBER_ENABLE", "party1")
assert(detailedCalls == 2,
  "a second state dispatch at the same GetTime must not reuse a stale calculator fill")
local metadataChecks = aiChecks
assert(Health.UpdateGroupLifecycleMetadata(lifecycleFrame, "PARTY_MEMBER_ENABLE", "party1") == true
    and aiChecks == metadataChecks + 1,
  "active AI followers must retain the authoritative detailed lifecycle snapshot")
lifecycleFrame._msufGroupLifecycleAIMetadataReady = true
lifecycleFrame._msufDispatchToken = 3
metadataChecks = aiChecks
Health.Update(lifecycleFrame, "PARTY_MEMBER_ENABLE", "party1")
assert(aiChecks == metadataChecks,
  "compiled lifecycle metadata dependency must prevent a duplicate AI classification read")
lifecycleFrame._msufGroupLifecycleAIMetadataReady = nil
lifecycleFrame._msufDispatchActive = nil

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
lifecycleFrame._msufDispatchToken = 4
detailedCurrent = 617000
Health.Update(lifecycleFrame, "UNIT_HEALTH", "party1")
assert(detailedCalls == 4 and bar.value == 617000,
  "AI UNIT_HEALTH must read the authoritative detailed pool")
assert(statusSeed == nil and goneSeed == 617000,
  "living AI health must skip status while still seeding dead-background recovery")
lifecycleFrame._msufStatusTextValue = "DEAD"
lifecycleFrame._msufDispatchToken = 5
detailedCurrent = 700000
Health.Update(lifecycleFrame, "UNIT_HEALTH", "party1")
assert(statusSeed == 700000 and goneSeed == 700000,
  "positive AI health must clear a stale gone status in the same dispatch")
local checksAfterFirstHealth = aiChecks
lifecycleFrame._msufDispatchToken = 6
detailedCurrent = 710000
Health.Update(lifecycleFrame, "UNIT_HEALTH", "party1")
assert(detailedCalls == 6 and aiChecks == checksAfterFirstHealth,
  "AI classification must be cached while each health dispatch remains authoritative")

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
Health.Update(normalFrame, "UNIT_HEALTH", "party2")
assert(normalBar.value == 100 and detailedCalls == 6,
  "non-AI group health must retain the percent fastpath")
local changedFrame = {
  unit = "party2",
  _msufIsGroupFrame = true,
  _msufHealthAIUnit = "party1",
  _msufHealthAI = true,
}
assert(Health.UpdateGroupLifecycleMetadata(changedFrame, "PARTY_MEMBER_DISABLE", "party2") == true
    and changedFrame._msufHealthAI == false,
  "AI mode transition must promote the non-target frame to a full health snapshot")
local stableAIState = {
  _msufIsGroupFrame = true,
  _msufHealthAIUnit = "party2",
  _msufHealthAI = false,
}
local stableAIWrites = 0
local stableFrame = setmetatable({}, {
  __index = stableAIState,
  __newindex = function(_, key, value)
    stableAIWrites = stableAIWrites + 1
    stableAIState[key] = value
  end,
})
assert(Health.UpdateGroupLifecycleMetadata(stableFrame, "PARTY_MEMBER_ENABLE", "party2") == false
    and stableAIWrites == 0,
  "unchanged lifecycle AI metadata must not rewrite frame state")

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
