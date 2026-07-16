local root = arg and arg[1] or "."

local function Read(path)
  local file = assert(io.open(path, "rb"))
  local body = file:read("*a")
  file:close()
  return body
end

local function Has(body, needle, message)
  assert(body:find(needle, 1, true), message)
end

local host = {
  width = 180,
  height = 44,
  shown = true,
}
function host:GetFrameStrata() return "MEDIUM" end
function host:GetFrameLevel() return 7 end

BackdropTemplateMixin = {}
MSUF_DB = {
  general = {
    highlightEnabled = true,
    highlightColor = { 0.2, 0.4, 0.6 },
    highlightThickness = 3,
  },
}

function CreateFrame(_, _, parent)
  local frame = { parent = parent, shown = false }
  function frame:SetPoint() end
  function frame:EnableMouse() end
  function frame:Hide() self.shown = false end
  function frame:Show() self.shown = true end
  function frame:IsShown() return self.shown end
  function frame:GetWidth() return self.parent.width end
  function frame:GetHeight() return self.parent.height end
  function frame:SetFrameStrata(value) self.strata = value end
  function frame:SetFrameLevel(value) self.level = value end
  function frame:SetBackdrop(value) self.backdrop = value end
  function frame:SetBackdropBorderColor(r, g, b, a) self.color = { r, g, b, a } end
  return frame
end

local MSUF = {
  UF = {
    frames = { target = host },
    frameList = { host },
  },
}

assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Highlight.lua"))(
  "MidnightSimpleUnitFrames",
  MSUF
)

assert(type(MSUF.Highlight) == "table", "highlight runtime did not load")
assert(type(MSUF_RefreshMouseoverHighlight) == "function", "highlight refresh export is missing")

MSUF.Highlight.Show(host)
assert(host._msufHL and host._msufHL:IsShown(), "enabled highlight did not show")
assert(host._msufHL.backdrop and host._msufHL.backdrop.edgeSize == 3, "highlight thickness was not applied")
assert(host._msufHL.color[1] == 0.2 and host._msufHL.color[2] == 0.4 and host._msufHL.color[3] == 0.6,
  "highlight color was not applied")

MSUF_DB.general.highlightEnabled = false
MSUF_RefreshMouseoverHighlight()
assert(not host._msufHL:IsShown(), "turning highlight off left a visible border")
MSUF.Highlight.Show(host)
assert(not host._msufHL:IsShown(), "disabled highlight still showed on mouseover")

MSUF_DB.general.highlightEnabled = true
MSUF_DB.general.highlightColor = { 0.8, 0.1, 0.3 }
MSUF_RefreshMouseoverHighlight()
MSUF.Highlight.Show(host)
assert(host._msufHL:IsShown(), "turning highlight back on did not restore mouseover")
assert(host._msufHL.color[1] == 0.8 and host._msufHL.color[2] == 0.1 and host._msufHL.color[3] == 0.3,
  "live highlight color refresh failed")

local roundedCalls = 0
local function RoundedUnit(frame, active)
  roundedCalls = roundedCalls + 1
  frame._roundedMouseover = active and true or false
  if frame._msufHL then frame._msufHL:Hide() end
  return true
end
MSUF.Highlight.SetRoundedMouseoverState(true, false, RoundedUnit, nil)
MSUF.Highlight.UnitEnter(host)
assert(roundedCalls == 1 and host._roundedMouseover == true, "unit mouseover did not use cached rounded handler")
assert(not host._msufHL:IsShown(), "standalone highlight overlapped rounded mouseover")
MSUF.Highlight.UnitLeave(host)
assert(roundedCalls == 2 and host._roundedMouseover == false, "unit mouseleave did not use cached rounded handler")

local elements = Read(root .. "/MidnightSimpleUnitFrames/UnitFrames/Embeds/MSUF_UFCore/MSUF_UFCore_Elements.xml")
Has(elements, "MSUF_UF_Highlight.lua", "embedded UFCore does not load the highlight runtime")

local factory = Read(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Factory.lua")
Has(factory, 'frame:HookScript("OnEnter", Highlight.UnitEnter)', "unit frames do not directly wire mouseover enter")
Has(factory, 'frame:HookScript("OnLeave", Highlight.UnitLeave)', "unit frames do not directly wire mouseover leave")
assert(not factory:find("MSUF_RoundedUF_OnUnitMouseover", 1, true), "unit mouseover hotpath still performs global rounded lookup")

local groups = Read(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Adapter.lua")
Has(groups, 'frame:HookScript("OnEnter", Highlight.GroupEnter)', "group frames do not directly wire mouseover enter")
Has(groups, 'frame:HookScript("OnLeave", Highlight.GroupLeave)', "group frames do not directly wire mouseover leave")
assert(not groups:find("MSUF_RoundedUF_OnGroupMouseover", 1, true), "group mouseover hotpath still performs global rounded lookup")

local rounded = Read(root .. "/MidnightSimpleUnitFrames/UnitFrames/Effects/MSUF_UF_RoundedFrames.lua")
Has(rounded, "if not (f and unitMouseoverHotEnabled) then return false end",
  "rounded unit mouseover still resolves settings in the hotpath")
Has(rounded, "if not groupMouseoverHotEnabled then",
  "rounded group mouseover still resolves settings in the hotpath")

print("PASS mouseover highlight runtime: load, hover wiring, live toggle, color, and rounded ownership")
