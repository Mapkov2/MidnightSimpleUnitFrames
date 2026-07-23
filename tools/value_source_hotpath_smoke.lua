_G = _G or _ENV

local function Exists(path)
  local handle = io.open(path, "r")
  if not handle then return false end
  handle:close()
  return true
end

local root = "MidnightSimpleUnitFrames/"
if not Exists(root .. "UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua") then
  root = ""
end

local function LoadAddon(path, namespace)
  local chunk, err = loadfile(root .. path)
  assert(chunk, err)
  chunk("MidnightSimpleUnitFrames", namespace)
end

local secretHealth, secretHealthMax, secretPower, secretPowerMax
_G.issecretvalue = function(value)
  return (secretHealth ~= nil and value == secretHealth)
    or (secretHealthMax ~= nil and value == secretHealthMax)
    or (secretPower ~= nil and value == secretPower)
    or (secretPowerMax ~= nil and value == secretPowerMax)
end
_G.UnitInPartyIsAI = function() return false end

local reads = {
  health = 0,
  healthMax = 0,
  healthPercent = 0,
  power = 0,
  powerMax = 0,
  powerPercent = 0,
  powerType = 0,
}
local commonPowerType, commonPowerToken = 0, "MANA"
local lastPowerReadType
local powerReadValue, powerReadMaximum = 40, 100

local function ResetReads()
  for key in pairs(reads) do reads[key] = 0 end
end

local function NewBar()
  local bar = { shown = true, _msufShown = true }
  function bar:IsShown() return self.shown end
  function bar:SetMinMaxValues(minimum, maximum)
    self.minimum, self.maximum = minimum, maximum
  end
  function bar:SetValue(value)
    self.value = value
  end
  function bar:SetStatusBarColor() end
  return bar
end

local UF = {
  elements = {},
  _updateKeys = { Health = "_healthUpdate", Power = "_powerUpdate" },
}
function UF.RegisterElement(name, element)
  UF.elements[name] = element
end

local Common = {
  UF = UF,
  UnitHealth = function()
    reads.health = reads.health + 1
    return secretHealth or 50
  end,
  UnitHealthMax = function()
    reads.healthMax = reads.healthMax + 1
    return secretHealthMax or 100
  end,
  UnitHealthPercent = function()
    reads.healthPercent = reads.healthPercent + 1
    return 50
  end,
  UnitPower = function(_, powerType)
    reads.power = reads.power + 1
    lastPowerReadType = powerType
    return powerReadValue
  end,
  UnitPowerMax = function()
    reads.powerMax = reads.powerMax + 1
    return powerReadMaximum
  end,
  UnitPowerType = function()
    reads.powerType = reads.powerType + 1
    return commonPowerType, commonPowerToken
  end,
  UnitPowerPercent = function()
    reads.powerPercent = reads.powerPercent + 1
    return 40
  end,
  SCALE_100 = {},
  WHITE = "white",
  PowerBarColor = { MANA = { r = 0, g = 0.4, b = 1 } },
}
local namespace = { UF = UF, UFBarTextCommon = Common }
LoadAddon("UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua", namespace)
LoadAddon("UnitFrames/Engine/Elements/MSUF_UF_Elements_Power.lua", namespace)

local Health = assert(UF.elements.Health, "health element missing")
local Power = assert(UF.elements.Power, "power element missing")

local function NewHealthFrame(runtime)
  return {
    unit = "party1",
    hpBar = NewBar(),
    MSUFSpec = { scope = "group", health = { mode = "dark" } },
    _msufIsGroupFrame = true,
    _msufTextRuntime = runtime,
    _msufActiveElements = { Health = true },
  }
end

local function NewSingleHealthFrame(runtime)
  return {
    unit = "target",
    hpBar = NewBar(),
    MSUFSpec = { scope = "single", health = { mode = "dark" } },
    _msufTextRuntime = runtime,
    _msufActiveElements = { Health = true },
  }
end

local percentHealthFrame = NewHealthFrame({
  healthSlotCount = 1,
  healthNeedsPercent = true,
})
local percentHealthUpdate = Health.SelectUpdate(percentHealthFrame, percentHealthFrame.MSUFSpec)
percentHealthFrame.hpBar._msufHealthValue = 45
percentHealthFrame.hpBar._msufHealthValueUnit = "party1"
percentHealthFrame.hpBar._msufHealthMax = 100
percentHealthFrame.hpBar._msufHealthMaxUnit = "party1"
percentHealthFrame.hpBar._msufHealthMaxReady = true
ResetReads()
local healthPercent, healthPercentMax, percentReady = percentHealthUpdate(
  percentHealthFrame, "UNIT_HEALTH", "party1")
assert(reads.healthPercent == 1 and reads.health == 0 and reads.healthMax == 0,
  "percent-only health must use exactly UnitHealthPercent")
assert(healthPercent == 50 and healthPercentMax == nil and percentReady == true,
  "percent-only health return contract changed")
assert(percentHealthFrame.hpBar._msufHealthValue == 45
    and percentHealthFrame.hpBar._msufHealthValueUnit == "party1"
    and percentHealthFrame.hpBar._msufHealthMax == 100
    and percentHealthFrame.hpBar._msufHealthMaxUnit == "party1"
    and percentHealthFrame.hpBar._msufHealthMaxReady == true,
  "compiled percent health tick churned inactive absolute-route caches")
Health.SelectGroupHealthUpdater(percentHealthFrame)
assert(percentHealthFrame.hpBar._msufHealthValue == nil
    and percentHealthFrame.hpBar._msufHealthValueUnit == nil
    and percentHealthFrame.hpBar._msufHealthMax == nil
    and percentHealthFrame.hpBar._msufHealthMaxUnit == nil
    and percentHealthFrame.hpBar._msufHealthMaxReady == nil,
  "health route transition retained stale value-source caches")

local maxOnlyHealthFrame = NewHealthFrame({
  healthSlotCount = 1,
  healthNeedsMax = true,
})
assert(Health.SelectUpdate(maxOnlyHealthFrame, maxOnlyHealthFrame.MSUFSpec) == percentHealthUpdate,
  "MAX-only health must not promote every UNIT_HEALTH tick to absolute reads")

local colorOnlyHealthFrame = NewHealthFrame({
  healthSlotCount = 1,
  healthColorByHealth = true,
})
local colorOnlyHealthUpdate = Health.SelectUpdate(colorOnlyHealthFrame, colorOnlyHealthFrame.MSUFSpec)
assert(colorOnlyHealthUpdate == percentHealthUpdate,
  "health text gradient alone must stay on the native percent path")
ResetReads()
colorOnlyHealthUpdate(colorOnlyHealthFrame, "UNIT_HEALTH", "party1")
assert(reads.healthPercent == 1 and reads.health == 0 and reads.healthMax == 0,
  "health text gradient must not force UnitHealth/UnitHealthMax reads")
assert(colorOnlyHealthFrame._msufTextRuntime._dispatchHealthPercentReady == true,
  "health text gradient did not receive the shared native percent sample")

local currentGroupHealthFrame = NewHealthFrame({
  healthSlotCount = 1,
  healthNeedsCurrent = true,
})
local currentGroupHealthUpdate = Health.SelectUpdate(
  currentGroupHealthFrame, currentGroupHealthFrame.MSUFSpec)
assert(currentGroupHealthUpdate == percentHealthUpdate,
  "group CURRENT health must leave absolute text reads to the shared dirty drain")
ResetReads()
local groupCurrentHealth, groupCurrentHealthMax, groupCurrentPercentReady = currentGroupHealthUpdate(
  currentGroupHealthFrame, "UNIT_HEALTH", "party1")
assert(reads.healthPercent == 1 and reads.health == 0 and reads.healthMax == 0,
  "group CURRENT health must keep the bar on one native percent read")
assert(groupCurrentHealth == 50 and groupCurrentHealthMax == nil and groupCurrentPercentReady == true,
  "group CURRENT health percent contract changed")

local currentHealthFrame = NewSingleHealthFrame({
  healthSlotCount = 1,
  healthNeedsCurrent = true,
})
local currentHealthUpdate = Health.SelectUpdate(currentHealthFrame, currentHealthFrame.MSUFSpec)
assert(currentHealthUpdate == Health.UpdateValueSingleCurrent
    and currentHealthUpdate ~= percentHealthUpdate,
  "single CURRENT health did not compile its shared absolute-bar plan")
ResetReads()
local currentHealth, currentHealthMax, currentPercentReady = currentHealthUpdate(
  currentHealthFrame, "UNIT_HEALTH", "party1")
assert(reads.healthPercent == 0 and reads.health == 1 and reads.healthMax == 1,
  "CURRENT-only health did not share one absolute value with the bar")
assert(currentHealth == 50 and currentHealthMax == nil and currentPercentReady == false,
  "CURRENT health partial snapshot contract changed")
currentHealthUpdate(currentHealthFrame, "UNIT_HEALTH", "party1")
assert(reads.health == 2 and reads.healthMax == 1 and reads.healthPercent == 0,
  "steady CURRENT-only health reread its event-owned maximum")
currentHealthUpdate(currentHealthFrame, "UNIT_MAXHEALTH", "party1")
assert(reads.health == 3 and reads.healthMax == 2 and reads.healthPercent == 0,
  "CURRENT-only UNIT_MAXHEALTH did not refresh the bar maximum")

secretHealth, secretHealthMax = {}, {}
local secretCurrentHealthFrame = NewSingleHealthFrame({
  healthSlotCount = 1,
  healthNeedsCurrent = true,
})
local secretCurrentHealthUpdate = Health.SelectUpdate(secretCurrentHealthFrame, secretCurrentHealthFrame.MSUFSpec)
ResetReads()
local protectedHealth, protectedHealthMaximum = secretCurrentHealthUpdate(
  secretCurrentHealthFrame, "UNIT_HEALTH", "party1")
assert(protectedHealth == secretHealth and protectedHealthMaximum == nil
    and secretCurrentHealthFrame.hpBar.value == secretHealth
    and secretCurrentHealthFrame.hpBar.maximum == secretHealthMax,
  "CURRENT-only health did not forward protected value/max through native setters")
secretCurrentHealthUpdate(secretCurrentHealthFrame, "UNIT_HEALTH", "party1")
assert(reads.health == 2 and reads.healthMax == 1 and reads.healthPercent == 0,
  "steady protected CURRENT-only health reread its owned maximum")
secretHealth, secretHealthMax = nil, nil

local absoluteGroupHealthFrame = NewHealthFrame({
  healthSlotCount = 1,
  healthNeedsCurrent = true,
  healthNeedsMax = true,
})
local absoluteGroupHealthUpdate = Health.SelectUpdate(
  absoluteGroupHealthFrame, absoluteGroupHealthFrame.MSUFSpec)
assert(absoluteGroupHealthUpdate == percentHealthUpdate,
  "group current+max health must leave absolute text reads to the shared dirty drain")
ResetReads()
local groupHealth, groupHealthMax, groupAbsolutePercentReady = absoluteGroupHealthUpdate(
  absoluteGroupHealthFrame, "UNIT_HEALTH", "party1")
assert(reads.healthPercent == 1 and reads.health == 0 and reads.healthMax == 0
    and groupHealth == 50 and groupHealthMax == nil and groupAbsolutePercentReady == true,
  "group current+max health left the native percent hotpath")

local absoluteHealthFrame = NewSingleHealthFrame({
  healthSlotCount = 1,
  healthNeedsCurrent = true,
  healthNeedsMax = true,
})
local absoluteHealthUpdate = Health.SelectUpdate(absoluteHealthFrame, absoluteHealthFrame.MSUFSpec)
assert(absoluteHealthUpdate == Health.UpdateValueSingleAbsolute
    and absoluteHealthUpdate ~= percentHealthUpdate and absoluteHealthUpdate ~= currentHealthUpdate,
  "current+max health did not compile a separate absolute update path")
ResetReads()
local health, healthMax, absolutePercentReady = absoluteHealthUpdate(
  absoluteHealthFrame, "UNIT_HEALTH", "party1")
assert(reads.health == 1 and reads.healthMax == 1 and reads.healthPercent == 0,
  "absolute health path must read one coherent value pair without UnitHealthPercent")
assert(health == 50 and healthMax == 100 and absolutePercentReady == false,
  "absolute health snapshot was not returned to route followers")
absoluteHealthUpdate(absoluteHealthFrame, "UNIT_HEALTH", "party1")
assert(reads.health == 2 and reads.healthMax == 1,
  "steady absolute health reread an unchanged event-owned maximum")
absoluteHealthUpdate(absoluteHealthFrame, "UNIT_MAXHEALTH", "party1")
assert(reads.health == 3 and reads.healthMax == 2,
  "UNIT_MAXHEALTH did not refresh the absolute health maximum")
Health.SelectGroupHealthUpdater(absoluteHealthFrame)
assert(absoluteHealthFrame._healthUpdate == absoluteHealthUpdate,
  "health hotpath reselection did not rebind the active update key")

local predictionHealthFrame = NewHealthFrame({
  healthSlotCount = 1,
  healthNeedsPercent = true,
})
predictionHealthFrame._msufPredictionNeedsHealth = true
assert(Health.SelectUpdate(predictionHealthFrame, predictionHealthFrame.MSUFSpec) == percentHealthUpdate,
  "Prediction state leaked back into the compiled Health value-source plan")
assert(UF.ReadPredictionDetailedHealth == nil,
  "removed Prediction detailed-health compatibility provider was restored")

local function NewPowerFrame(runtime)
  return {
    unit = "party1",
    targetPowerBar = NewBar(),
    MSUFSpec = { scope = "group", power = { mode = "power" } },
    _msufTextRuntime = runtime,
    _msufActiveElements = { Power = true },
  }
end

local function NewSinglePowerFrame(runtime)
  return {
    unit = "target",
    targetPowerBar = NewBar(),
    MSUFSpec = { scope = "single", power = { mode = "power" } },
    _msufTextRuntime = runtime,
    _msufActiveElements = { Power = true },
  }
end

local percentPowerFrame = NewPowerFrame({
  powerSlotCount = 1,
  powerNeedsPercent = true,
})
local percentPowerUpdate = Power.SelectUpdate(percentPowerFrame, percentPowerFrame.MSUFSpec)
ResetReads()
local powerValue, powerMaximum = percentPowerUpdate(
  percentPowerFrame, "UNIT_POWER_UPDATE", "party1")
assert(reads.powerPercent == 1 and reads.power == 0 and reads.powerMax == 0,
  "percent-only power must use exactly UnitPowerPercent")
assert(powerValue == nil and powerMaximum == nil,
  "percent-only power must keep absolute route payloads empty")

local currentGroupPowerFrame = NewPowerFrame({
  powerSlotCount = 1,
  powerNeedsCurrent = true,
})
local currentGroupPowerUpdate = Power.SelectUpdate(
  currentGroupPowerFrame, currentGroupPowerFrame.MSUFSpec)
assert(currentGroupPowerUpdate == percentPowerUpdate,
  "group CURRENT power must leave absolute text reads to the shared dirty drain")
ResetReads()
local groupCurrentPower, groupCurrentPowerMax = currentGroupPowerUpdate(
  currentGroupPowerFrame, "UNIT_POWER_UPDATE", "party1")
assert(reads.powerPercent == 1 and reads.power == 0 and reads.powerMax == 0
    and groupCurrentPower == nil and groupCurrentPowerMax == nil,
  "group CURRENT power left the native percent hotpath")

local currentPowerFrame = NewSinglePowerFrame({
  powerSlotCount = 1,
  powerNeedsCurrent = true,
})
local currentPowerUpdate = Power.SelectUpdate(currentPowerFrame, currentPowerFrame.MSUFSpec)
assert(currentPowerUpdate == Power.UpdateValueCurrentPath
    and currentPowerUpdate ~= percentPowerUpdate,
  "single CURRENT power did not compile its shared absolute-bar plan")
ResetReads()
local currentPower, currentPowerMax = currentPowerUpdate(
  currentPowerFrame, "UNIT_POWER_UPDATE", "party1")
assert(reads.powerPercent == 0 and reads.power == 1 and reads.powerMax == 1,
  "CURRENT-only power did not share one absolute value with the bar")
assert(currentPower == 40 and currentPowerMax == nil,
  "CURRENT power partial snapshot contract changed")
currentPowerUpdate(currentPowerFrame, "UNIT_POWER_UPDATE", "party1")
assert(reads.power == 2 and reads.powerMax == 1 and reads.powerPercent == 0,
  "steady CURRENT-only power reread its event-owned maximum")
currentPowerUpdate(currentPowerFrame, "UNIT_MAXPOWER", "party1")
assert(reads.power == 3 and reads.powerMax == 2 and reads.powerPercent == 0,
  "CURRENT-only UNIT_MAXPOWER did not refresh the bar maximum")

secretPower, secretPowerMax = {}, {}
powerReadValue, powerReadMaximum = secretPower, secretPowerMax
local secretCurrentPowerFrame = NewSinglePowerFrame({
  powerSlotCount = 1,
  powerNeedsCurrent = true,
})
local secretCurrentPowerUpdate = Power.SelectUpdate(
  secretCurrentPowerFrame, secretCurrentPowerFrame.MSUFSpec)
ResetReads()
local protectedCurrent, protectedMaximum = secretCurrentPowerUpdate(
  secretCurrentPowerFrame, "UNIT_POWER_UPDATE", "party1")
assert(protectedCurrent == secretPower and protectedMaximum == nil
    and secretCurrentPowerFrame.targetPowerBar.value == secretPower
    and secretCurrentPowerFrame.targetPowerBar.maximum == secretPowerMax,
  "CURRENT-only power did not forward protected value/max through native setters")
secretCurrentPowerUpdate(secretCurrentPowerFrame, "UNIT_POWER_UPDATE", "party1")
assert(reads.power == 2 and reads.powerMax == 1 and reads.powerPercent == 0,
  "steady protected CURRENT-only power reread its owned maximum")
secretPower, secretPowerMax = nil, nil
powerReadValue, powerReadMaximum = 40, 100

local mixedCurrentPercentFrame = NewSinglePowerFrame({
  powerSlotCount = 1,
  powerNeedsCurrent = true,
  powerNeedsPercent = true,
})
local mixedCurrentPercentUpdate = Power.SelectUpdate(
  mixedCurrentPercentFrame, mixedCurrentPercentFrame.MSUFSpec)
assert(mixedCurrentPercentUpdate ~= currentPowerUpdate
    and mixedCurrentPercentUpdate ~= percentPowerUpdate,
  "CURRENT+PERCENT power did not compile its dedicated secret-safe path")
ResetReads()
local mixedCurrent, mixedMaximum = mixedCurrentPercentUpdate(
  mixedCurrentPercentFrame, "UNIT_POWER_UPDATE", "party1")
assert(reads.powerPercent == 1 and reads.power == 1 and reads.powerMax == 0,
  "CURRENT+PERCENT power lost its secret-safe native percent sample")
assert(mixedCurrent == 40 and mixedMaximum == nil
    and mixedCurrentPercentFrame._msufTextRuntime._dispatchPowerPercentReady == true,
  "CURRENT+PERCENT partial snapshot contract changed")

local absoluteGroupPowerFrame = NewPowerFrame({
  powerSlotCount = 1,
  powerNeedsCurrent = true,
  powerNeedsMax = true,
})
local absoluteGroupPowerUpdate = Power.SelectUpdate(
  absoluteGroupPowerFrame, absoluteGroupPowerFrame.MSUFSpec)
assert(absoluteGroupPowerUpdate == percentPowerUpdate,
  "group current+max power must leave absolute text reads to the shared dirty drain")
ResetReads()
local groupPower, groupPowerMax = absoluteGroupPowerUpdate(
  absoluteGroupPowerFrame, "UNIT_POWER_UPDATE", "party1")
assert(reads.powerPercent == 1 and reads.power == 0 and reads.powerMax == 0
    and groupPower == nil and groupPowerMax == nil,
  "group current+max power left the native percent hotpath")

local absolutePowerFrame = NewSinglePowerFrame({
  powerSlotCount = 1,
  powerNeedsCurrent = true,
  powerNeedsMax = true,
})
local absolutePowerUpdate = Power.SelectUpdate(absolutePowerFrame, absolutePowerFrame.MSUFSpec)
assert(absolutePowerUpdate == Power.UpdateValueAbsolutePath
    and absolutePowerUpdate ~= percentPowerUpdate and absolutePowerUpdate ~= currentPowerUpdate,
  "current+max power did not compile a separate absolute update path")
ResetReads()
local power, powerMax = absolutePowerUpdate(
  absolutePowerFrame, "UNIT_POWER_UPDATE", "party1")
assert(reads.power == 1 and reads.powerMax == 1 and reads.powerPercent == 0,
  "absolute power path must read one coherent value pair without UnitPowerPercent")
assert(power == 40 and powerMax == 100,
  "absolute power snapshot was not returned to route followers")
absolutePowerUpdate(absolutePowerFrame, "UNIT_POWER_UPDATE", "party1")
assert(reads.power == 2 and reads.powerMax == 1,
  "steady absolute power reread an unchanged event-owned maximum")
absolutePowerUpdate(absolutePowerFrame, "UNIT_MAXPOWER", "party1")
assert(reads.power == 3 and reads.powerMax == 2,
  "UNIT_MAXPOWER did not refresh the absolute power maximum")
Power.SelectGroupPowerUpdater(absolutePowerFrame)
assert(absolutePowerFrame._powerUpdate == absolutePowerUpdate,
  "power hotpath reselection did not rebind the active update key")

local maxOnlyPowerFrame = NewPowerFrame({
  powerSlotCount = 1,
  powerNeedsMax = true,
})
assert(Power.SelectUpdate(maxOnlyPowerFrame, maxOnlyPowerFrame.MSUFSpec) == percentPowerUpdate,
  "MAX-only power must not promote every UNIT_POWER tick to absolute reads")

local lifecyclePowerFrame = NewPowerFrame({
  powerSlotCount = 1,
  powerNeedsCurrent = true,
})
lifecyclePowerFrame.MSUFSpec.power = { mode = "static", r = 0.2, g = 0.2, b = 0.2 }
lifecyclePowerFrame.targetPowerBar._msufPowerTypeKnown = true
lifecyclePowerFrame.targetPowerBar._msufPowerTypeUnit = "party1"
lifecyclePowerFrame.targetPowerBar._msufPowerType = 0
lifecyclePowerFrame.targetPowerBar._msufPowerToken = "MANA"
commonPowerType, commonPowerToken = 1, "RAGE"
ResetReads()
Power.SelectUpdate(lifecyclePowerFrame, lifecyclePowerFrame.MSUFSpec)(
  lifecyclePowerFrame, "PARTY_MEMBER_ENABLE", "party1")
assert(reads.powerType == 1 and reads.powerPercent == 1
    and reads.power == 0 and reads.powerMax == 0,
  "group lifecycle did not invalidate a same-token power-type cache")
commonPowerType, commonPowerToken = 0, "MANA"

local function NewFontString()
  local fs = { shown = true, writes = 0 }
  function fs:IsShown() return self.shown end
  function fs:SetText(value) self.writes = self.writes + 1; self.text = value end
  function fs:SetFormattedText(pattern, ...)
    self.writes = self.writes + 1
    self.text = string.format(pattern, ...)
  end
  return fs
end

local TextUF = { elements = {} }
function TextUF.RegisterElement(name, element)
  TextUF.elements[name] = element
end
local textHealthReads, textHealthMaxReads = 0, 0
local textPowerReads, textPowerMaxReads = 0, 0
local textHealthPercentReads, textPowerPercentReads = 0, 0
local textHealthMaxValue = 100
local textPowerType, textPowerToken = 0, "MANA"
local lastTextPowerMaxType
local Text = {
  tonumber = tonumber,
  type = type,
  format = string.format,
  floor = math.floor,
  max = math.max,
  abs = math.abs,
  GetTime = function() return 1 end,
  SetPowerTextColor = function() end,
  UnitHealth = function()
    textHealthReads = textHealthReads + 1
    return 50
  end,
  UnitHealthMax = function()
    textHealthMaxReads = textHealthMaxReads + 1
    return textHealthMaxValue
  end,
  UnitPower = function()
    textPowerReads = textPowerReads + 1
    return 40
  end,
  UnitPowerMax = function(_, powerType)
    textPowerMaxReads = textPowerMaxReads + 1
    lastTextPowerMaxType = powerType
    return 100
  end,
  UnitPowerType = function() return textPowerType, textPowerToken end,
  SCALE_100 = {},
  UnitHealthPercent = function()
    textHealthPercentReads = textHealthPercentReads + 1
    return 50
  end,
  UnitPowerPercent = function()
    textPowerPercentReads = textPowerPercentReads + 1
    return 40
  end,
}
local textNamespace = {
  UF = TextUF,
  UFText = Text,
  Secrets = { UnitMissing = function() return false end },
  Apply = {},
}
LoadAddon("UnitFrames/Engine/Elements/MSUF_UF_Text_Format.lua", textNamespace)
LoadAddon("UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua", textNamespace)

local textFrame = {
  unit = "party1",
  hpTextLeft = NewFontString(),
  powerTextLeft = NewFontString(),
}
local textSpec = {
  scope = "group",
  showHealthText = true,
  showPowerText = true,
  power = { enabled = true },
  text = { healthLeft = "CURPERCENT", powerLeft = "CURPERCENT" },
}
local runtime = Text.CompileTextRuntime(textFrame, textSpec, textSpec.text)
local hot = assert(Text.RuntimeHotFunctions, "text hot function registry missing")
assert(type(hot.healthFromValues) == "function" and type(hot.powerFromValues) == "function",
  "absolute text hotpath builders were not registered")
assert(runtime.healthHot ~= hot.healthHot and runtime.powerHot ~= hot.powerHot,
  "group value text did not activate the precompiled single-slot writers")

TextUF.elements.HealthText.Update(textFrame, "UNIT_HEALTH", "party1", 50, 100)
TextUF.elements.PowerText.Update(textFrame, "UNIT_POWER_UPDATE", "party1", 40, 100, 0, "MANA", false)
assert(textHealthPercentReads == 0 and textPowerPercentReads == 0,
  "plain mixed text must derive percent from the shared absolute snapshot")

local singleTextFrame = {
  unit = "player",
  hpTextLeft = NewFontString(),
  powerTextLeft = NewFontString(),
}
local singleTextSpec = {
  scope = "single",
  showHealthText = true,
  showPowerText = true,
  power = { enabled = true },
  text = { healthLeft = "CURMAXPERCENT", powerLeft = "CURMAXPERCENT" },
}
Text.CompileTextRuntime(singleTextFrame, singleTextSpec, singleTextSpec.text)
textHealthPercentReads, textPowerPercentReads = 0, 0
TextUF.elements.HealthText.Update(singleTextFrame, "UNIT_HEALTH", "player", 50, 100)
TextUF.elements.PowerText.Update(singleTextFrame, "UNIT_POWER_UPDATE", "player", 40, 100, 0, "MANA", false)
assert(textHealthPercentReads == 0 and textPowerPercentReads == 0,
  "single-frame absolute snapshots must derive readable percentages without a third API read")

local partialTextFrame = {
  unit = "party1",
  hpTextLeft = NewFontString(),
  powerTextLeft = NewFontString(),
}
local partialTextSpec = {
  scope = "single",
  showHealthText = true,
  showPowerText = true,
  power = { enabled = true },
  text = { healthLeft = "CURPERCENT", powerLeft = "CURPERCENT" },
}
local partialRuntime = Text.CompileTextRuntime(partialTextFrame, partialTextSpec, partialTextSpec.text)
textHealthMaxReads, textPowerMaxReads = 0, 0
textHealthPercentReads, textPowerPercentReads = 0, 0
partialRuntime._dispatchHealthPercent, partialRuntime._dispatchHealthPercentReady = 50, true
partialRuntime._dispatchPowerPercent, partialRuntime._dispatchPowerPercentReady = 40, true
TextUF.elements.HealthText.Update(partialTextFrame, "UNIT_HEALTH", "party1", 50, nil)
TextUF.elements.PowerText.Update(partialTextFrame, "UNIT_POWER_UPDATE", "party1", 40, nil, 0, "MANA", false)
assert(textHealthMaxReads == 0 and textPowerMaxReads == 0
    and textHealthPercentReads == 0 and textPowerPercentReads == 0,
  "CURRENT+PERCENT partial plans performed an unnecessary max or percent reread")

local groupPartialFrame = {
  unit = "party1",
  hpTextLeft = NewFontString(),
  powerTextLeft = NewFontString(),
}
local groupPartialSpec = {
  scope = "group",
  showHealthText = true,
  showPowerText = true,
  power = { enabled = true },
  text = { healthLeft = "CURPERCENT", powerLeft = "CURPERCENT" },
}
local groupPartialRuntime = Text.CompileTextRuntime(groupPartialFrame, groupPartialSpec, groupPartialSpec.text)
groupPartialRuntime._dispatchHealthPercent, groupPartialRuntime._dispatchHealthPercentReady = 50, true
groupPartialRuntime._dispatchPowerPercent, groupPartialRuntime._dispatchPowerPercentReady = 40, true
TextUF.elements.HealthText.Update(groupPartialFrame, "UNIT_HEALTH", "party1", 50, nil)
TextUF.elements.PowerText.Update(groupPartialFrame, "UNIT_POWER_UPDATE", "party1", 40, nil, 0, "MANA", false)
assert(groupPartialRuntime._msufGFHotHealthHP == 50
    and groupPartialRuntime._msufGFHotHealthMax == false
    and groupPartialRuntime._msufGFHotPower == 40
    and groupPartialRuntime._msufGFHotPowerMax == false,
  "group CURRENT partial payloads bypassed their compiled hot dedupe plan")

local percentDedupeFrame = {
  unit = "party1",
  hpTextLeft = NewFontString(),
  powerTextLeft = NewFontString(),
}
local percentDedupeSpec = {
  scope = "group",
  showHealthText = true,
  showPowerText = true,
  power = { enabled = true },
  text = { healthLeft = "PERCENT", powerLeft = "PERCENT" },
}
Text.CompileTextRuntime(percentDedupeFrame, percentDedupeSpec, percentDedupeSpec.text)
TextUF.elements.HealthText.Update(percentDedupeFrame, "UNIT_HEALTH", "party1", 49.6, nil)
TextUF.elements.PowerText.Update(percentDedupeFrame, "UNIT_POWER_UPDATE", "party1", 49.6, nil, 0, "MANA", false)
assert(percentDedupeFrame.hpTextLeft.text == "49%" and percentDedupeFrame.powerTextLeft.text == "49%",
  "zero-decimal percent display semantics changed")
TextUF.elements.HealthText.Update(percentDedupeFrame, "UNIT_HEALTH", "party1", 50.0, nil)
TextUF.elements.PowerText.Update(percentDedupeFrame, "UNIT_POWER_UPDATE", "party1", 50.0, nil, 0, "MANA", false)
assert(percentDedupeFrame.hpTextLeft.text == "50%" and percentDedupeFrame.powerTextLeft.text == "50%",
  "percent dedupe skipped a visible truncation boundary")

local lifecycleTextFrame = {
  unit = "party1",
  powerTextLeft = NewFontString(),
}
local lifecycleTextSpec = {
  scope = "group",
  showHealthText = false,
  showPowerText = true,
  power = { enabled = true },
  text = { powerLeft = "MAX" },
}
local lifecycleTextRuntime = Text.CompileTextRuntime(lifecycleTextFrame, lifecycleTextSpec, lifecycleTextSpec.text)
lifecycleTextFrame._msufTextPowerType = 0
lifecycleTextFrame._msufTextPowerToken = "MANA"
lifecycleTextFrame._msufTextPowerTypeKnown = true
lifecycleTextFrame._msufTextPowerTypeUnit = "party1"
lifecycleTextFrame._msufTextPowerMax = 77
lifecycleTextFrame._msufTextPowerMaxUnit = "party1"
textPowerType, textPowerToken = 1, "RAGE"
textPowerMaxReads, lastTextPowerMaxType = 0, nil
TextUF.elements.PowerText.Update(
  lifecycleTextFrame, "PARTY_MEMBER_ENABLE", "party1", nil, nil, 1, "RAGE", true)
assert(textPowerMaxReads == 1 and lastTextPowerMaxType == 1
    and lifecycleTextFrame._msufTextPowerMax == 100
    and lifecycleTextRuntime ~= nil,
  "group lifecycle retained stale same-token power text metadata/max cache")
textPowerType, textPowerToken = 0, "MANA"

secretHealth, secretHealthMax = 51, 101
secretPower, secretPowerMax = 41, 101
TextUF.elements.HealthText.Update(textFrame, "UNIT_HEALTH", "party1", secretHealth, secretHealthMax)
TextUF.elements.PowerText.Update(textFrame, "UNIT_POWER_UPDATE", "party1", secretPower, secretPowerMax, 0, "MANA", false)
assert(textHealthPercentReads == 1 and textPowerPercentReads == 1,
  "secret mixed text must retain the native percent API fallback")

secretHealth, secretHealthMax, secretPower, secretPowerMax = nil, nil, nil, nil
local maxPercentFrame = {
  unit = "party1",
  hpTextLeft = NewFontString(),
}
local maxPercentSpec = {
  scope = "group",
  showHealthText = true,
  showPowerText = false,
  text = { healthLeft = "MAXPERCENT" },
}
local maxPercentRuntime = Text.CompileTextRuntime(maxPercentFrame, maxPercentSpec, maxPercentSpec.text)
textHealthReads, textHealthMaxReads, textHealthPercentReads = 0, 0, 0
maxPercentRuntime._dispatchHealthPercent = 50
maxPercentRuntime._dispatchHealthPercentReady = true
TextUF.elements.HealthText.Update(maxPercentFrame, "UNIT_HEALTH", "party1")
maxPercentRuntime._dispatchHealthPercent = 49
maxPercentRuntime._dispatchHealthPercentReady = true
TextUF.elements.HealthText.Update(maxPercentFrame, "UNIT_HEALTH", "party1")
assert(textHealthReads == 0 and textHealthMaxReads == 1 and textHealthPercentReads == 0,
  "MAXPERCENT health must reuse its cached max across value ticks")
maxPercentRuntime._dispatchHealthPercent = 48
maxPercentRuntime._dispatchHealthPercentReady = true
TextUF.elements.HealthText.Update(maxPercentFrame, "UNIT_MAXHEALTH", "party1")
assert(textHealthMaxReads == 2,
  "UNIT_MAXHEALTH must refresh the compiled health max cache")

secretHealthMax = 101
textHealthMaxValue = secretHealthMax
textHealthMaxReads = 0
maxPercentRuntime._dispatchHealthPercent, maxPercentRuntime._dispatchHealthPercentReady = 47, true
TextUF.elements.HealthText.Update(maxPercentFrame, "UNIT_MAXHEALTH", "party1")
for pct = 46, 45, -1 do
  maxPercentRuntime._dispatchHealthPercent, maxPercentRuntime._dispatchHealthPercentReady = pct, true
  TextUF.elements.HealthText.Update(maxPercentFrame, "UNIT_HEALTH", "party1")
end
assert(textHealthMaxReads == 1 and maxPercentFrame._msufTextHealthMaxReady == true
    and _G.issecretvalue(maxPercentFrame._msufTextHealthMax) == true,
  "steady secret health text reread an unchanged event-owned maximum")
secretHealthMax = nil
textHealthMaxValue = 100

local shortFrame = {
  unit = "party1",
  hpTextLeft = NewFontString(),
}
local shortSpec = {
  scope = "group",
  showHealthText = true,
  showPowerText = false,
  text = {
    healthLeft = "CURRENT",
    healthShortNumbers = true,
  },
}
Text.CompileTextRuntime(shortFrame, shortSpec, shortSpec.text)
TextUF.elements.HealthText.Update(shortFrame, "UNIT_HEALTH", "party1", 12345, 20000)
assert(shortFrame.hpTextLeft.text == "12K",
  "CURRENT health lost the compiled healthShortNumbers setting")

print("value source hotpath smoke: ok")
