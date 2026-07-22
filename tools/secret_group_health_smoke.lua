_G = _G or _ENV

local SECRET_HP = 617001
local SECRET_MAX = 775001
local SECRET_PCT = 73001
local INTERP = {}
local detailedHP, detailedMax = SECRET_HP, SECRET_MAX
local plainPercent = 100
local detailedCalls = 0
local Health

_G.issecretvalue = function(value)
  return value == SECRET_HP or value == SECRET_MAX or value == SECRET_PCT
end
_G.UnitInPartyIsAI = function(unit) return unit == "party1" end
_G.CreateUnitHealPredictionCalculator = function()
  return {
    GetCurrentHealth = function() return detailedHP end,
    GetMaximumHealth = function() return detailedMax end,
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
      return unit == "player" and SECRET_PCT or plainPercent
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

local aiStatusSeed, aiGoneSeed = false, false
local aiBar = Bar()
aiBar._msufSmoothInterp = INTERP
local aiFrame = {
  unit = "party1",
  hpBar = aiBar,
  MSUFSpec = { scope = "group", health = { mode = "dark" } },
  _msufIsGroupFrame = true,
  _msufUpdateGroupStatusState = function(_, _, _, seed) aiStatusSeed = seed end,
  _msufUpdateGroupVisualsGoneState = function(_, _, _, seed) aiGoneSeed = seed end,
}

Health.Update(aiFrame, "UNIT_HEALTH", "party1")
assert(aiBar.maximum == SECRET_MAX and aiBar.value == SECRET_HP,
  "secret authoritative AI health must still reach the StatusBar")
assert(detailedCalls == 1, "AI health must retain the detailed calculator path")
assert(aiBar._msufMinMax == nil and aiBar._msufHealthValue == nil
    and aiBar._msufHealthMax == SECRET_MAX and aiBar._msufHealthMaxReady == true
    and _G.issecretvalue(aiBar._msufHealthMax) == true,
  "secret detailed max was not retained as an opaque event-owned payload")
assert(aiStatusSeed == false and aiGoneSeed == nil,
  "secret detailed health must not reach status/dead comparisons")

Health.Update(aiFrame, "UNIT_HEALTH", "party1")
assert(detailedCalls == 2 and aiBar.minMaxCalls == 1,
  "steady secret health repeated the unchanged native max setter")

detailedHP, detailedMax = 617000, 775000
Health.Update(aiFrame, "PARTY_MEMBER_ENABLE", "party1")
assert(aiBar.value == 617000 and aiBar.maximum == 775000
    and aiBar._msufHealthValue == 617000 and aiBar._msufHealthMax == 775000
    and aiBar.minMaxCalls == 2 and aiBar.interpolation == nil
    and aiBar._msufInterpolating == nil,
  "plain authoritative AI recovery must retain the detailed-health cache")

detailedHP = 616999
Health.Update(aiFrame, "UNIT_HEALTH", "party1")
assert(aiBar.value == 616999 and aiBar.interpolation == INTERP
    and aiBar._msufInterpolating == true,
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
