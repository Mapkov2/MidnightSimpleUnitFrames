-- inline_tot_secret_anchor_smoke.lua (run with the repo root as cwd, no arguments)
--
-- The inline target-of-target separator follows the rendered end of the target
-- name. It used to read nameText:GetStringWidth() and pass that width to
-- SetPoint and into the anchor cache. GetStringWidth is SecretWhenAnchoringSecret
-- (SimpleFontStringAPIDocumentation) and SetPoint takes secret offsets only
-- AllowedWhenUntainted (SimpleScriptRegionResizingAPIDocumentation), so a
-- restricted target name raised in the inline update.
--
-- This smoke drives the real Text layout (MSUF_UF_Text_Layout.lua) with font
-- strings as strict as the client: GetStringWidth answers a secret for a secret
-- text, SetPoint raises on a secret argument, a secret refuses comparison and
-- arithmetic. It pins that the separator hangs off the name's glyph edge (the
-- name itself when it sizes itself, the invisible auto-width twin when the name
-- spans the bar), that no width is ever read, and that a re-anchor writes
-- nothing while the edge stays the same.

_G = _G or _ENV
_G.MSUF_FontApplyEpoch = 0

local SECRET_META = {
  __lt = function() error("attempt to compare a secret value", 2) end,
  __le = function() error("attempt to compare a secret value", 2) end,
  __add = function() error("attempt to perform arithmetic on a secret value", 2) end,
  __sub = function() error("attempt to perform arithmetic on a secret value", 2) end,
  __concat = function() error("attempt to concatenate a secret value", 2) end,
  __tostring = function() return "<secret>" end,
}
local function Secret() return setmetatable({ __secret = true }, SECRET_META) end
local function IsSecret(value) return type(value) == "table" and getmetatable(value) == SECRET_META end
_G.issecretvalue = IsSecret

local widthReads = 0

local function NewFontString(parent)
  local fs = { parent = parent, shown = false, pointWrites = 0 }
  function fs:GetParent() return self.parent end
  function fs:SetParent(value) self.parent = value end
  function fs:ClearAllPoints() self.point = nil end
  function fs:SetPoint(point, relativeTo, relativePoint, x, y)
    for _, value in ipairs({ point, relativeTo, relativePoint, x, y }) do
      if IsSecret(value) then error("SetPoint: secret argument from tainted code", 2) end
    end
    self.pointWrites = self.pointWrites + 1
    self.point = { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y }
  end
  function fs:GetStringWidth()
    widthReads = widthReads + 1
    if IsSecret(self.text) then return Secret() end
    return #(self.text or "") * 6
  end
  function fs:SetJustifyH(value) self.justify = value end
  function fs:SetWordWrap(value) self.wordWrap = value end
  function fs:SetNonSpaceWrap(value) self.nonSpaceWrap = value end
  function fs:SetDrawLayer(layer, subLayer) self.drawLayer, self.subLayer = layer, subLayer end
  function fs:SetTextColor(...) self.color = { ... } end
  function fs:SetText(value) self.text = value end
  function fs:GetText() return self.text end
  function fs:SetWidth(value) self.width = value end
  function fs:SetAlpha(value) self.alpha = value end
  function fs:SetShown(value) self.shown = value == true end
  function fs:IsShown() return self.shown == true end
  function fs:Show() self.shown = true end
  function fs:Hide() self.shown = false end
  function fs:SetFont(font, size, flags)
    self.font, self.fontSize, self.fontFlags = font, size, flags
    return true
  end
  function fs:GetFont() return self.font, self.fontSize, self.fontFlags end
  return fs
end

local function NewOverlay(parent)
  local overlay = { parent = parent }
  function overlay:SetAllPoints(value) self.allPoints = value or true end
  function overlay:EnableMouse(value) self.mouseEnabled = value == true end
  function overlay:SetClipsChildren(value) self.clipsChildren = value == true end
  function overlay:SetFrameLevel(value) self.frameLevel = value end
  function overlay:GetFrameLevel() return self.frameLevel or 0 end
  function overlay:CreateFontString() return NewFontString(self) end
  return overlay
end

local MSUF = {
  Secrets = { IsSecret = IsSecret },
  UF = { Layers = {}, elements = {} },
}
assert(loadfile("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Apply.lua"))("InlineToTSecretSmoke", MSUF)
local ApplyText = assert(MSUF.Apply and MSUF.Apply.Text)
local Text = {
  CreateFrame = function(_, _, parent) return NewOverlay(parent) end,
  UF = MSUF.UF,
  tonumber = tonumber,
  floor = math.floor,
  max = math.max,
  EMPTY_EVENTS = {},
  DrawSubLayer = function(layer, fallback) return tonumber(layer) or fallback end,
  ClampFrameLayer = function(layer, fallback) return tonumber(layer) or fallback end,
  GetLayerBaseLevel = function() return 0 end,
  SetFrameLevelCached = function(frame, level)
    if frame._msufFrameLevel ~= level then
      frame:SetFrameLevel(level)
      frame._msufFrameLevel = level
    end
  end,
  SetShownCached = function(region, shown)
    if region and region._msufShown ~= (shown == true) then
      region:SetShown(shown == true)
      region._msufShown = shown == true
    end
  end,
  SetTextCached = ApplyText,
  SetFont = function(fs, spec, size)
    if not fs then return true end
    return fs:SetFont((spec and spec.font) or "Fonts\\FRIZQT__.TTF", tonumber(size) or 12, "OUTLINE") ~= false
  end,
  SetNameTextColor = function() end,
  ApplyNameTextColor = function() end,
  NameTextColor = function() return 1, 1, 1, 1 end,
  ResolveHealthTextModes = function(text)
    text = text or {}
    return text.healthLeft, text.healthCenter, text.healthRight
  end,
  CompileTextRuntime = function(frame)
    local runtime = frame._msufTextRuntime or {}
    frame._msufTextRuntime = runtime
    return runtime
  end,
  SetHealthTextColor = function() end,
  UpdateHealthTextColor = function() end,
}
MSUF.UFText = Text
assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Layout.lua"))("InlineToTSecretSmoke", MSUF)

local failures = {}
local function Expect(condition, message)
  if not condition then failures[#failures + 1] = message end
end

local function NewFrame()
  local frame = { MSUFUnitKey = "target" }
  function frame:GetFrameLevel() return 1 end
  function frame:GetWidth() return 220 end
  return frame
end

local function TargetSpec(barAnchored, nameAnchor)
  return {
    key = "target", scope = "single", width = 220, height = 40,
    font = "Fonts\\FRIZQT__.TTF", nameFontSize = 12, healthFontSize = 12, powerFontSize = 12,
    showName = true, showHealthText = false, showPowerText = false,
    text = {
      anchorToBars = barAnchored == true, nameAnchor = nameAnchor or "LEFT", nameX = 4, nameY = -4,
      nameLayer = 5, nameShorten = false, healthLayer = 5, powerLayer = 2,
      healthLeft = "NONE", healthCenter = "NONE", healthRight = "NONE",
      powerLeft = "NONE", powerCenter = "NONE", powerRight = "NONE",
      inlineToT = { enabled = true, separator = " - ", stamp = 1 },
    },
  }
end

local function SepAnchor(frame)
  local point = frame.totInlineSep and frame.totInlineSep.point
  return point and point.point, point and point.relativeTo, point and point.relativePoint, point and point.x
end

for _, case in ipairs({
  { label = "bar-anchored name", barAnchored = true, twin = true },
  { label = "self-sized name", barAnchored = false, twin = false },
}) do
  widthReads = 0
  local frame = NewFrame()
  local ok, err = pcall(Text.Apply, frame, TargetSpec(case.barAnchored))
  Expect(ok, case.label .. ": layout raised: " .. tostring(err))
  local name, sep = frame.nameText, frame.totInlineSep
  Expect(name and sep, case.label .. ": the inline separator was not built")
  if name and sep then
    local edge = case.twin and frame._msufNameAnchorText or name
    Expect(not case.twin or frame._msufNameAnchorTextActive == true,
      case.label .. ": the auto-width name twin is not active for the inline separator")
    local point, relativeTo, relativePoint, x = SepAnchor(frame)
    Expect(point == "LEFT" and relativeTo == edge and relativePoint == "RIGHT" and x == 0,
      case.label .. ": the separator does not hang off the name's glyph edge ("
        .. tostring(point) .. " " .. tostring(relativePoint) .. " " .. tostring(x) .. ")")

    -- A restricted target name arrives: the warm inline update re-anchors.
    local secretName = Secret()
    ApplyText(name, secretName)
    if frame._msufNameAnchorTextActive == true then ApplyText(frame._msufNameAnchorText, secretName) end
    local writes = sep.pointWrites
    ok, err = pcall(Text.AnchorInlineToName, frame)
    Expect(ok, case.label .. ": the inline re-anchor raised on a secret name: " .. tostring(err))
    Expect(sep.pointWrites == writes, case.label .. ": an unchanged glyph edge rewrote the separator anchor")
    Expect(not IsSecret(sep._msufX) and not IsSecret(sep._msufY), case.label .. ": a secret entered the anchor cache")
  end
  Expect(widthReads == 0, case.label .. ": the layout read " .. widthReads .. " name width(s)")
end

-- A centered or right-justified name keeps its own clip or fallback anchors.
widthReads = 0
local centered = NewFrame()
local ok = pcall(Text.Apply, centered, TargetSpec(true, "TOP"))
Expect(ok and centered._msufInlineAnchorDynamic ~= true, "a centered name took the glyph-edge inline anchor")
Expect(centered._msufNameAnchorTextActive ~= true, "a centered name activated the inline glyph twin")

if #failures > 0 then
  for i = 1, #failures do print("FAIL " .. failures[i]) end
  os.exit(1)
end
print("inline_tot_secret_anchor_smoke: ok")
