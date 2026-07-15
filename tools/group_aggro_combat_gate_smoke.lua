_G = _G or _ENV

local element
local inCombat = false
local threat = 3

_G.issecretvalue = function(value) return type(value) == "table" and value.secret == true end
_G.UnitThreatSituation = function() return threat end
_G.UnitAffectingCombat = function() return inCombat end
_G.UnitGroupRolesAssigned = function() return "TANK" end
_G.CreateFrame = function(_, _, parent)
  local holder = { parent = parent, level = 0 }
  function holder:SetAllPoints() end
  function holder:EnableMouse() end
  function holder:SetFrameLevel(level) self.level = level end
  function holder:CreateTexture()
    local texture = { parent = self }
    function texture:GetParent() return self.parent end
    function texture:SetDrawLayer() end
    function texture:SetSize() end
    function texture:SetColorTexture() end
    function texture:ClearAllPoints() end
    function texture:SetPoint() end
    function texture:SetShown(shown) self.shown = shown end
    function texture:Hide() self.shown = false end
    return texture
  end
  return holder
end

local MSUF = {
  UF = { RegisterElement = function(_, value) element = value end },
  GF = {},
  Secrets = { UnitMissing = function() return false end },
}

assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Indicators.lua"))(
  "MidnightSimpleUnitFrames",
  MSUF
)
assert(element, "group corner indicator element was not registered")

local frame = {
  unit = "party1",
  hpBar = { GetFrameLevel = function() return 1 end },
  MSUFSpec = {
    scope = "group",
    cornerIndicators = {
      enabled = true,
      hasWork = true,
      needsThreat = true,
      aggroMode = "ALL",
      aggroSlots = { { category = "aggro", key = "TR", anchor = "TOPRIGHT" } },
    },
  },
}

element.Apply(frame)
local indicator = assert(frame.MSUFGFCornerIndicators.TR)
assert(indicator.shown == false, "stale out-of-combat threat must stay hidden")

inCombat = true
element.Update(frame, "UNIT_FLAGS")
assert(indicator.shown == true, "active combat threat must be shown")

inCombat = false
element.Update(frame, "UNIT_FLAGS")
assert(indicator.shown == false, "combat exit must clear the threat indicator")

local events = table.concat(element.GetEvents(frame, frame.MSUFSpec), "|")
local unitless = table.concat(element.GetUnitlessEvents(frame, frame.MSUFSpec), "|")
assert(events:find("UNIT_FLAGS", 1, true))
assert(unitless:find("PLAYER_REGEN_ENABLED", 1, true))

print("group aggro combat gate smoke: ok")
