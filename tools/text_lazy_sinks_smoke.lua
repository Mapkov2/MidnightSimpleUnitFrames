_G = _G or _ENV

local overlayCount, fontStringCount = 0, 0

local function FontString(parent)
  fontStringCount = fontStringCount + 1
  local fs = { parent = parent, shown = false }
  function fs:GetParent() return self.parent end
  function fs:SetParent(value) self.parent = value end
  function fs:ClearAllPoints() self.points = nil end
  function fs:SetPoint(...) self.points = { ... } end
  function fs:SetJustifyH(value) self.justify = value end
  function fs:SetWordWrap(value) self.wordWrap = value end
  function fs:SetNonSpaceWrap(value) self.nonSpaceWrap = value end
  function fs:SetDrawLayer(layer, subLayer) self.drawLayer, self.subLayer = layer, subLayer end
  function fs:SetTextColor(...) self.color = { ... } end
  function fs:SetText(value) self.text = value end
  function fs:SetWidth(value) self.width = value end
  function fs:SetShown(value) self.shown = value == true end
  function fs:IsShown() return self.shown == true end
  function fs:Show() self.shown = true end
  function fs:Hide() self.shown = false end
  return fs
end

local function Overlay(parent)
  overlayCount = overlayCount + 1
  local overlay = { parent = parent }
  function overlay:SetAllPoints(value) self.allPoints = value or true end
  function overlay:EnableMouse(value) self.mouseEnabled = value == true end
  function overlay:SetClipsChildren(value) self.clipsChildren = value == true end
  function overlay:SetFrameLevel(value) self.frameLevel = value end
  function overlay:GetFrameLevel() return self.frameLevel or 0 end
  function overlay:CreateFontString() return FontString(self) end
  return overlay
end

local Text = {
  CreateFrame = function(_, _, parent) return Overlay(parent) end,
  UF = { Layers = {}, elements = {} },
  tonumber = tonumber,
  floor = math.floor,
  max = math.max,
  EMPTY_EVENTS = {},
  DrawSubLayer = function(layer, fallback) return tonumber(layer) or fallback end,
  ClampFrameLayer = function(layer, fallback) return tonumber(layer) or fallback end,
  GetLayerBaseLevel = function() return 0 end,
  SetFrameLevelCached = function(frame, level) frame:SetFrameLevel(level) end,
  SetShownCached = function(region, shown) if region then region:SetShown(shown) end end,
  SetFont = function() end,
  SetNameTextColor = function() end,
  NameTextColor = function() return 1, 1, 1, 1 end,
  ResolveHealthTextModes = function(text)
    text = text or {}
    local left, center, right = text.healthLeft, text.healthCenter, text.healthRight
    if text.healthReverse == true then left, right = right, left end
    return left, center, right
  end,
  CompileTextRuntime = function() return {} end,
  UpdateHealthTextColor = function() end,
}

local MSUF = { UF = Text.UF, UFText = Text }
assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Layout.lua"))(
  "MidnightSimpleUnitFrames",
  MSUF
)

local function Frame()
  local frame = { unit = "party1" }
  function frame:GetFrameLevel() return 1 end
  function frame:GetWidth() return 120 end
  return frame
end

local frame = Frame()
local firstSpec = {
  key = "gf_party",
  width = 120,
  height = 36,
  showName = true,
  showHealthText = true,
  showPowerText = false,
  _msufTextLayoutRevision = 1,
  text = {
    nameLayer = 5,
    healthLayer = 5,
    powerLayer = 2,
    healthLeft = "CURRENT",
    healthCenter = "NONE",
    healthRight = "NONE",
    powerLeft = "NONE",
    powerCenter = "NONE",
    powerRight = "NONE",
  },
}

Text.Create(frame, firstSpec)
assert(frame.nameText and frame.hpTextLeft, "configured name/health sinks were not created")
assert(not frame.hpTextCenter and not frame.hpTextRight, "disabled health sinks were eagerly created")
assert(not frame.powerTextLeft and not frame.powerTextCenter and not frame.powerTextRight,
  "disabled power sinks were eagerly created")
assert(frame.MSUFNameTextLayer and frame.MSUFHealthTextLayer and not frame.MSUFPowerTextLayer,
  "text overlays were not created lazily")
assert(overlayCount == 2 and fontStringCount == 2, "unexpected initial text allocation count")

local nameSink, healthSink = frame.nameText, frame.hpTextLeft
Text.Apply(frame, firstSpec)
assert(overlayCount == 2 and fontStringCount == 2, "initial apply recreated configured sinks")

local powerSpec = {
  key = "gf_party",
  width = 120,
  height = 36,
  showName = true,
  showHealthText = true,
  showPowerText = true,
  _msufTextLayoutRevision = 2,
  text = {
    nameLayer = 5,
    healthLayer = 5,
    powerLayer = 2,
    healthLeft = "CURRENT",
    healthCenter = "NONE",
    healthRight = "NONE",
    powerLeft = "NONE",
    powerCenter = "NONE",
    powerRight = "PERCENT",
  },
}

Text.Apply(frame, powerSpec)
assert(frame.powerTextRight and frame.MSUFPowerTextLayer, "newly enabled power sink was not cold-created")
assert(frame.nameText == nameSink and frame.hpTextLeft == healthSink, "existing text sinks were not reused")
assert(overlayCount == 3 and fontStringCount == 3, "cold apply created more than the missing power sink")

frame.nameText:Hide()
frame.hpTextLeft:Hide()
frame.powerTextRight:Hide()
frame._msufGFPreviewDetached = true
Text.Apply(frame, powerSpec)
assert(frame.nameText:IsShown() and frame.hpTextLeft:IsShown() and frame.powerTextRight:IsShown(),
  "detached preview text sinks were not reactivated on pooled reopen")
frame._msufGFPreviewDetached = nil

local empty = Frame()
Text.Create(empty, {
  key = "gf_party",
  showName = false,
  showHealthText = true,
  showPowerText = true,
  text = {
    healthLeft = "NONE", healthCenter = "NONE", healthRight = "NONE",
    powerLeft = "NONE", powerCenter = "NONE", powerRight = "NONE",
  },
})
assert(not empty.MSUFNameTextLayer and not empty.MSUFHealthTextLayer and not empty.MSUFPowerTextLayer,
  "fully disabled text configuration allocated overlays")
assert(overlayCount == 3 and fontStringCount == 3, "fully disabled text configuration allocated regions")

print("text lazy sinks smoke: ok")
