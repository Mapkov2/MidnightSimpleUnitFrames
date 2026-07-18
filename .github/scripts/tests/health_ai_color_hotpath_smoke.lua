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
local detailedCalls, colorCalls = 0, 0
local MSUF = {
  UF = {
    RegisterElement = function(name, element)
      if name == "Health" then Health = element end
    end,
    ReadDetailedHealth = function()
      detailedCalls = detailedCalls + 1
      return 80, 100
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
Check(colorCalls == 0,
  "steady positive AI UNIT_HEALTH repeated the full runtime color path")

frame._msufHealthStatusGone = true
update(frame, "UNIT_HEALTH", "party1")
Check(detailedCalls == 2 and colorCalls == 1,
  "gone-state UNIT_HEALTH lost its revive/status recolor")

local identityUpdate = Health.SelectEventUpdate(frame, frame.MSUFSpec, "UNIT_FACTION")
identityUpdate(frame, "UNIT_FACTION", "party1")
Check(colorCalls == 2 and detailedCalls == 2,
  "identity-only color event performed health work or skipped recolor")

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
