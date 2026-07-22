_G = _G or _ENV

local element
local inCombat = false
local threat = 3
local combatReads = 0

_G.issecretvalue = function(value) return type(value) == "table" and value.secret == true end
_G.UnitThreatSituation = function() return threat end
_G.UnitAffectingCombat = function()
  combatReads = combatReads + 1
  return inCombat
end
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
  UF = {
    Clamp01 = function(value) return value end,
    RegisterElement = function(_, value) element = value end,
  },
  GF = {},
  Secrets = { UnitMissing = function() return false end },
}

assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Visuals_Common.lua"))(
  "MidnightSimpleUnitFrames",
  MSUF
)
assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Indicators.lua"))(
  "MidnightSimpleUnitFrames",
  MSUF
)
assert(element, "group corner indicator element was not registered")

local frame = {
  unit = "party1",
  MSUFUnitKey = "party1",
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
local readsBeforeThreatEvent = combatReads
element.Update(frame, "UNIT_THREAT_LIST_UPDATE")
assert(combatReads == readsBeforeThreatEvent,
  "authoritative threat event repeated the combat-state API query")

inCombat = false
element.Update(frame, "UNIT_FLAGS")
assert(indicator.shown == false, "combat exit must clear the threat indicator")

local events = table.concat(element.GetEvents(frame, frame.MSUFSpec), "|")
local unitless = table.concat(element.GetUnitlessEvents(frame, frame.MSUFSpec), "|")
assert(events:find("UNIT_FLAGS", 1, true))
assert(not unitless:find("PLAYER_REGEN_ENABLED", 1, true),
  "corner indicators must reuse the shared group regen owner")

frame._msufActiveElements = { GroupCornerIndicators = true }
local inactive = {
  _msufActiveElements = { GroupCornerIndicators = false },
  _msufGFCornerPreparedCfg = {
    needsThreat = true,
    runtimeThreat = function() error("inactive corner frame was updated") end,
  },
}
local noThreat = {
  _msufActiveElements = { GroupCornerIndicators = true },
  _msufGFCornerPreparedCfg = {
    needsThreat = false,
    runtimeThreat = function() error("no-needsThreat corner frame was updated") end,
  },
}
MSUF.GF.ForEachFrame = function(fn, includeHidden, ...)
  assert(includeHidden == false, "shared corner catch-up must stay visibility-gated")
  local any = fn(inactive, "party2", "party", ...)
  any = fn(noThreat, "party3", "party", ...) or any
  return fn(frame, frame.MSUFUnitKey, "party", ...) or any
end
inCombat = true
threat = 3
element.Update(frame, "UNIT_THREAT_LIST_UPDATE")
assert(indicator.shown == true, "shared regen setup failed")
inCombat = false
assert(MSUF.GF.RefreshCornerThreatState("PLAYER_REGEN_ENABLED") == true)
assert(indicator.shown == false, "shared regen owner did not clear stale corner threat")

print("group aggro combat gate smoke: ok")
