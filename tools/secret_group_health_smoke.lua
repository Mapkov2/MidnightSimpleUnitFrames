_G = _G or _ENV

local SECRET_HP = 617001
local SECRET_MAX = 775001
local SECRET_PCT = 73001
local INTERP = {}
local plainPercent = 100
local groupPercent = SECRET_PCT
local aiChecks = 0
local calculatorCalls = 0
local detailedCalls = 0
local Health

_G.issecretvalue = function(value)
  return value == SECRET_HP or value == SECRET_MAX or value == SECRET_PCT
end
_G.UnitInPartyIsAI = function(unit)
  aiChecks = aiChecks + 1
  return unit == "party1"
end
_G.CreateUnitHealPredictionCalculator = function()
  calculatorCalls = calculatorCalls + 1
  return {
    GetCurrentHealth = function() return SECRET_HP end,
    GetMaximumHealth = function() return SECRET_MAX end,
  }
end
_G.UnitGetDetailedHealPrediction = function(unit, healer)
  assert(unit == "party1" and healer == "player",
    "detailed health used the wrong unit/healer contract")
  detailedCalls = detailedCalls + 1
end

local MSUF = {
  UF = {
    RegisterElement = function(name, element)
      if name == "Health" then Health = element end
    end,
  },
  UFBarTextCommon = {
    UnitHealthPercent = function(unit)
      if unit == "player" then return SECRET_PCT end
      if unit == "party1" then return groupPercent end
      return plainPercent
    end,
    SCALE_100 = 100,
    WHITE = "white",
  },
}
MSUF.UFBarTextCommon.UF = MSUF.UF

assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua"))(
  "MidnightSimpleUnitFrames",
  MSUF
)
assert(Health, "health element was not registered")

local function Bar()
  local bar = { minMaxCalls = 0 }
  function bar:SetMinMaxValues(minimum, maximum)
    self.minMaxCalls = self.minMaxCalls + 1
    self.minimum, self.maximum = minimum, maximum
  end
  function bar:SetValue(value, interpolation)
    self.value = value
    self.interpolation = interpolation
  end
  function bar:SetStatusBarColor() end
  return bar
end

local playerStatusSeed, playerGoneSeed = false, false
local playerBar = Bar()
playerBar._msufMinMax = SECRET_MAX
playerBar._msufHealthPercentValue = SECRET_PCT
playerBar._msufSmoothInterp = INTERP
local playerFrame = {
  unit = "player",
  hpBar = playerBar,
  MSUFSpec = { scope = "group", health = { mode = "dark" } },
  _msufIsGroupFrame = true,
  _msufHealthAIUnit = "player",
  _msufHealthAI = false,
  _msufUpdateGroupStatusState = function(_, _, _, seed) playerStatusSeed = seed end,
  _msufUpdateGroupVisualsGoneState = function(_, _, _, seed) playerGoneSeed = seed end,
}

Health.Update(playerFrame, "UNIT_HEALTH", "player")
assert(playerBar.maximum == 100 and playerBar.value == SECRET_PCT,
  "secret player percent must still reach the StatusBar")
assert(playerBar.interpolation == nil and playerBar._msufInterpolating == nil,
  "secret player health created a native interpolation job")
assert(playerBar._msufMinMax == 100 and playerBar._msufHealthPercentValue == nil
    and playerBar._msufHealthPercentUnit == nil,
  "secret player values must never remain in Lua comparison caches")
assert(playerStatusSeed == false and playerGoneSeed == nil,
  "secret player health must not reach status/dead comparisons")

Health.Update(playerFrame, "PARTY_MEMBER_ENABLE", "player")
assert(playerBar.maximum == 100 and playerBar.value == SECRET_PCT and detailedCalls == 0,
  "player lifecycle refresh must remain on the percent path")

local groupStatusSeed, groupGoneSeed = false, false
local groupBar = Bar()
groupBar._msufSmoothInterp = INTERP
local groupFrame = {
  unit = "party1",
  hpBar = groupBar,
  MSUFSpec = { scope = "group", health = { mode = "dark" } },
  _msufIsGroupFrame = true,
  _msufUpdateGroupStatusState = function(_, _, _, seed) groupStatusSeed = seed end,
  _msufUpdateGroupVisualsGoneState = function(_, _, _, seed) groupGoneSeed = seed end,
}

Health.Update(groupFrame, "UNIT_HEALTH", "party1")
assert(groupBar.maximum == 100 and groupBar.value == SECRET_PCT,
  "secret group percent must still reach the StatusBar")
assert(aiChecks == 0 and calculatorCalls == 0 and detailedCalls == 0,
  "group health restored the removed AI/detailed calculator path")
assert(groupBar._msufMinMax == 100 and groupBar._msufHealthPercentValue == nil
    and groupBar._msufHealthPercentUnit == nil
    and groupBar._msufHealthValue == nil and groupBar._msufHealthMax == nil,
  "secret group percent leaked into Lua comparison caches")
assert(groupStatusSeed == false and groupGoneSeed == nil,
  "secret group percent must not reach status/dead comparisons")

Health.Update(groupFrame, "UNIT_HEALTH", "party1")
assert(aiChecks == 0 and calculatorCalls == 0 and detailedCalls == 0
    and groupBar.minMaxCalls == 1,
  "steady secret group health repeated the unchanged native max setter")

groupPercent = 80
Health.Update(groupFrame, "PARTY_MEMBER_ENABLE", "party1")
assert(groupBar.value == 80 and groupBar.maximum == 100
    and groupBar._msufHealthPercentValue == 80
    and groupBar._msufHealthPercentUnit == "party1"
    and groupBar.minMaxCalls == 1 and groupBar.interpolation == nil
    and groupBar._msufInterpolating == nil,
  "plain group recovery must populate the percent cache without interpolation")

groupPercent = 79
Health.Update(groupFrame, "UNIT_HEALTH", "party1")
assert(groupBar.value == 79 and groupBar.interpolation == INTERP
    and groupBar._msufInterpolating == true
    and groupBar._msufHealthPercentValue == 79,
  "plain UNIT_HEALTH lost explicitly enabled smoothing")

local plainBar = Bar()
plainBar._msufSmoothInterp = INTERP
local plainFrame = {
  unit = "target",
  hpBar = plainBar,
  MSUFSpec = { scope = "single", health = { mode = "dark" } },
}
Health.Update(plainFrame, "UNIT_CONNECTION", "target")
assert(plainBar.value == 100 and plainBar.interpolation == nil
    and plainBar._msufInterpolating == nil
    and plainBar._msufHealthPercentValue == 100
    and plainBar._msufHealthPercentUnit == "target",
  "identity/connection refresh started a stale cross-unit interpolation")
plainPercent = 90
Health.Update(plainFrame, "UNIT_HEALTH", "target")
assert(plainBar.value == 90 and plainBar.interpolation == INTERP
    and plainBar._msufInterpolating == true
    and plainBar._msufHealthPercentValue == 90
    and plainBar._msufHealthPercentUnit == "target",
  "plain percent UNIT_HEALTH lost explicitly enabled smoothing")

print("secret group health smoke: ok")
