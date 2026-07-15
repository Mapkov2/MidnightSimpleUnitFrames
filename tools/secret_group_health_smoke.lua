_G = _G or _ENV

local SECRET_HP = 617001
local SECRET_MAX = 775001
local SECRET_PCT = 73001
local detailedHP, detailedMax = SECRET_HP, SECRET_MAX
local detailedCalls = 0
local Health

_G.issecretvalue = function(value)
  return value == SECRET_HP or value == SECRET_MAX or value == SECRET_PCT
end
_G.UnitInPartyIsAI = function(unit) return unit == "party1" end

local MSUF = {
  UF = {
    RegisterElement = function(name, element)
      if name == "Health" then Health = element end
    end,
    ReadDetailedHealth = function()
      detailedCalls = detailedCalls + 1
      return detailedHP, detailedMax
    end,
  },
  UFBarTextCommon = {
    UnitHealthPercent = function(unit)
      return unit == "player" and SECRET_PCT or 100
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
  local bar = {}
  function bar:SetMinMaxValues(minimum, maximum)
    self.minimum, self.maximum = minimum, maximum
  end
  function bar:SetValue(value)
    self.value = value
  end
  function bar:SetStatusBarColor() end
  return bar
end

local playerStatusSeed, playerGoneSeed = false, false
local playerBar = Bar()
playerBar._msufMinMax = SECRET_MAX
playerBar._msufHealthPercentValue = SECRET_PCT
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
assert(playerBar._msufMinMax == 100 and playerBar._msufHealthPercentValue == nil,
  "secret player values must never remain in Lua comparison caches")
assert(playerStatusSeed == false and playerGoneSeed == nil,
  "secret player health must not reach status/dead comparisons")

Health.Update(playerFrame, "PARTY_MEMBER_ENABLE", "player")
assert(playerBar.maximum == 100 and playerBar.value == SECRET_PCT and detailedCalls == 0,
  "player lifecycle refresh must remain on the percent path")

local aiStatusSeed, aiGoneSeed = false, false
local aiBar = Bar()
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
    and aiBar._msufHealthMax == nil and aiBar._msufHealthMaxReady == nil,
  "secret detailed health must never populate Lua comparison caches")
assert(aiStatusSeed == false and aiGoneSeed == nil,
  "secret detailed health must not reach status/dead comparisons")

detailedHP, detailedMax = 617000, 775000
Health.Update(aiFrame, "PARTY_MEMBER_ENABLE", "party1")
assert(aiBar.value == 617000 and aiBar.maximum == 775000
    and aiBar._msufHealthValue == 617000 and aiBar._msufHealthMax == 775000,
  "plain authoritative AI recovery must retain the detailed-health cache")

print("secret group health smoke: ok")
