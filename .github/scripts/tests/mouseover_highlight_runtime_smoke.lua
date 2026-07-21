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

local function Between(body, first, last)
  local from = assert(body:find(first, 1, true), "missing block start: " .. first)
  local to = assert(body:find(last, from + #first, true), "missing block end: " .. last)
  return body:sub(from, to - 1)
end

local host = {
  width = 180,
  height = 44,
  shown = true,
}
function host:GetFrameStrata() self.strataReads = (self.strataReads or 0) + 1; return "MEDIUM" end
function host:GetFrameLevel() self.levelReads = (self.levelReads or 0) + 1; return 7 end

BackdropTemplateMixin = {}
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
MSUF_DB = {
  general = {
    highlightEnabled = true,
    highlightColor = { 0.2, 0.4, 0.6 },
    highlightStyle = "GRADIENT",
    highlightThickness = 6,
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
  function frame:CreateTexture()
    local tex = { shown = false }
    function tex:SetPoint() end
    function tex:SetTexture(value) self.texture = value end
    function tex:SetBlendMode(value) self.blendMode = value end
    function tex:SetWidth(value) self.width = value end
    function tex:SetHeight(value) self.height = value end
    function tex:SetGradient(orientation, from, to) self.gradient = { orientation, from, to } end
    function tex:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function tex:Show() self.shown = true end
    function tex:Hide() self.shown = false end
    return tex
  end
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
local gradient = host._msufHL._msufGradient
assert(gradient and gradient.up.shown and gradient.left.shown, "soft gradient did not render")
assert(gradient.up.height == 6 and gradient.left.width == 6, "gradient size was not applied")
assert(gradient.up.gradient[3].r == 0.2 and gradient.up.gradient[3].g == 0.4 and gradient.up.gradient[3].b == 0.6,
  "gradient color was not applied")
local strataReads, levelReads = host.strataReads, host.levelReads
MSUF.Highlight.Hide(host)
MSUF.Highlight.Show(host)
assert(host.strataReads == strataReads and host.levelReads == levelReads,
  "steady-state mouseover repeated cold frame-layout reads")

MSUF_DB.general.highlightEnabled = false
MSUF_RefreshMouseoverHighlight()
assert(not host._msufHL:IsShown(), "turning highlight off left a visible border")
MSUF.Highlight.Show(host)
assert(not host._msufHL:IsShown(), "disabled highlight still showed on mouseover")

MSUF_DB.general.highlightEnabled = true
MSUF_DB.general.highlightColor = { 0.8, 0.1, 0.3 }
MSUF_DB.general.highlightThickness = 10
MSUF_RefreshMouseoverHighlight()
MSUF.Highlight.Show(host)
assert(host._msufHL:IsShown(), "turning highlight back on did not restore mouseover")
assert(gradient.up.height == 10 and gradient.up.gradient[3].r == 0.8
  and gradient.up.gradient[3].g == 0.1 and gradient.up.gradient[3].b == 0.3,
  "live highlight color refresh failed")

MSUF_DB.general.highlightStyle = "BORDER"
MSUF_DB.general.highlightThickness = 16
MSUF_RefreshMouseoverHighlight()
assert(host._msufHL.backdrop and host._msufHL.backdrop.edgeSize == 16, "solid border style did not live-apply")
assert(not gradient.up.shown and not gradient.left.shown, "solid border left gradient textures visible")

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
Has(rounded, "if not (f and groupMouseoverHotEnabled) then return false end",
  "rounded group mouseover still resolves settings in the hotpath")
local unitRoundedHover = Between(rounded, "local function HandleUnitMouseover", "local function ResolveDetachedPowerEdgeThickness")
local groupRoundedHover = Between(rounded, "local function HandleGroupMouseover", "local function HandleGroupHighlightChanged")
Has(unitRoundedHover, "local container = f._msufRUF_HoverContainer",
  "rounded unit mouseover does not use its cached overlay container")
Has(groupRoundedHover, "local container = f._msufRGF_HoverContainer",
  "rounded group mouseover does not use its cached overlay container")
assert(not unitRoundedHover:find("ShowRoundedEdgeStack", 1, true)
    and not unitRoundedHover:find("HideRoundedEdgeStack", 1, true)
    and not unitRoundedHover:find("highlightBorder", 1, true),
  "rounded unit mouseover still performs per-texture or native-border work")
assert(not groupRoundedHover:find("ShowRoundedEdgeStack", 1, true)
    and not groupRoundedHover:find("HideRoundedEdgeStack", 1, true)
    and not groupRoundedHover:find("highlightBorder", 1, true),
  "rounded group mouseover still performs per-texture or native-border work")

local misc = Read(root .. "/MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GlobalMisc.lua")
Has(misc, 'CollapsibleSection("misc_mouseover_highlight"', "mouseover controls were not moved to Miscellaneous")
Has(misc, '"highlightStyle"', "Miscellaneous is missing the mouseover style control")
Has(misc, '"highlightThickness"', "Miscellaneous is missing the mouseover size control")

local colors = Read(root .. "/MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors.lua")
assert(not colors:find('Meta("highlight.mouseover.enabled")', 1, true),
  "Colors still owns the mouseover enable toggle")
Has(colors, 'Meta("highlight.mouseover.color")', "Colors lost the mouseover color control")

Has(misc, "mouseoverHighlight = true",
  "Miscellaneous does not request the dedicated mouseover apply path")
assert(not misc:find("colors = true", 1, true),
  "Miscellaneous mouseover controls still request the unrelated full color refresh")

local realHighlightRefresh = MSUF_RefreshMouseoverHighlight
local roundedApplyCalls, highlightRefreshCalls, colorRefreshCalls = 0, 0, 0
MSUF_ApplyRoundedUnitframes = function() roundedApplyCalls = roundedApplyCalls + 1 end
MSUF_RefreshMouseoverHighlight = function()
  highlightRefreshCalls = highlightRefreshCalls + 1
  return realHighlightRefresh()
end
MSUF_RefreshAllFrameColors = function() colorRefreshCalls = colorRefreshCalls + 1 end
MSUF.MSUF2 = MSUF.MSUF2 or {}
MSUF.MSUF2.ApplyService = nil
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_ApplyService.lua"))(
  "MidnightSimpleUnitFrames",
  MSUF
)
MSUF.Highlight.SetRoundedMouseoverState(false, false, nil, nil)
MSUF_DB.general.highlightStyle = "GRADIENT"
MSUF_DB.general.highlightThickness = 3
MSUF.MSUF2.ApplyService.RequestGeneral("MSUF2_MOUSEOVER_STYLE", {
  preview = false,
  applyAll = false,
  mouseoverHighlight = true,
})
assert(roundedApplyCalls == 1 and highlightRefreshCalls == 1,
  "menu change did not live-apply rounded and standalone mouseover renderers")
assert(colorRefreshCalls == 0,
  "dedicated mouseover apply performed an unrelated full color refresh")
MSUF.Highlight.Show(host)
assert(host._msufHL.backdrop == nil and gradient.up.shown and gradient.up.height == 3,
  "dedicated menu apply did not replace the live solid border with the selected gradient size")

print("PASS mouseover highlight runtime: gradient/border styles, live settings, direct hover wiring, and menu ownership")
