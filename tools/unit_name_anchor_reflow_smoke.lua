_G = _G or _ENV

-- Unit-name anchor changes are a cold layout operation, but the following
-- NameText update often carries the same string. Exercise the production
-- Apply.Text cache together with the production text-layout owner so a stale
-- cache cannot suppress the SetText which makes WoW rebuild glyph geometry.

_G.MSUF_FontApplyEpoch = 0
_G.issecretvalue = function() return false end

local fontStringCount = 0

local function NewFontString(parent)
  fontStringCount = fontStringCount + 1
  local fs = {
    parent = parent,
    shown = false,
    pointWrites = 0,
    textWrites = 0,
    fontWrites = 0,
  }

  function fs:GetParent() return self.parent end
  function fs:SetParent(value) self.parent = value end
  function fs:ClearAllPoints() self.point = nil end
  function fs:SetPoint(point, relativeTo, relativePoint, x, y)
    self.pointWrites = self.pointWrites + 1
    self.point = {
      point = point,
      relativeTo = relativeTo,
      relativePoint = relativePoint,
      x = x,
      y = y,
    }
  end
  function fs:SetJustifyH(value) self.justify = value end
  function fs:SetWordWrap(value) self.wordWrap = value end
  function fs:SetNonSpaceWrap(value) self.nonSpaceWrap = value end
  function fs:SetDrawLayer(layer, subLayer) self.drawLayer, self.subLayer = layer, subLayer end
  function fs:SetTextColor(...) self.color = { ... } end
  function fs:SetText(value)
    self.textWrites = self.textWrites + 1
    self.text = value
  end
  function fs:GetText() return self.text end
  function fs:SetWidth(value) self.width = value end
  function fs:SetAlpha(value) self.alpha = value end
  function fs:SetShown(value) self.shown = value == true end
  function fs:IsShown() return self.shown == true end
  function fs:Show() self.shown = true end
  function fs:Hide() self.shown = false end
  function fs:SetFont(font, size, flags)
    self.fontWrites = self.fontWrites + 1
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
  Secrets = { IsSecret = function() return false end },
  UF = { Layers = {}, elements = {} },
}

assert(loadfile("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Apply.lua"))(
  "UnitNameAnchorReflowSmoke",
  MSUF
)

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
    local font = (spec and spec.font) or "Fonts\\FRIZQT__.TTF"
    local flags = (spec and spec.fontFlags) or "OUTLINE"
    size = tonumber(size) or 12
    if fs.font ~= font or fs.fontSize ~= size or fs.fontFlags ~= flags then
      return fs:SetFont(font, size, flags) ~= false
    end
    return true
  end,
  SetNameTextColor = function() end,
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

assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Layout.lua"))(
  "UnitNameAnchorReflowSmoke",
  MSUF
)

local function NewFrame(unit)
  local frame = { MSUFUnitKey = unit }
  function frame:GetFrameLevel() return 1 end
  function frame:GetWidth() return 180 end
  return frame
end

local function NewSpec(anchor, barAnchored)
  return {
    key = barAnchored and "gf_party" or "boss",
    scope = barAnchored and "group" or "single",
    width = 180,
    height = 30,
    font = "Fonts\\FRIZQT__.TTF",
    fontFlags = "OUTLINE",
    nameFontSize = 12,
    healthFontSize = 12,
    powerFontSize = 12,
    showName = true,
    showHealthText = false,
    showPowerText = false,
    text = {
      anchorToBars = barAnchored == true,
      nameAnchor = anchor,
      nameX = 4,
      nameY = -4,
      nameLayer = 5,
      nameShorten = false,
      healthLayer = 5,
      powerLayer = 2,
      healthLeft = "NONE",
      healthCenter = "NONE",
      healthRight = "NONE",
      powerLeft = "NONE",
      powerCenter = "NONE",
      powerRight = "NONE",
    },
  }
end

local failures = {}
local function Check(condition, message)
  if not condition then failures[#failures + 1] = message end
end

local function CheckPoint(fs, point, relativePoint, x, justify, label)
  local actual = fs and fs.point
  Check(actual and actual.point == point and actual.relativePoint == relativePoint
      and actual.x == x and actual.y == -4,
    label .. ": wrong anchor geometry")
  Check(fs and fs.justify == justify, label .. ": stale horizontal justification")
end

-- Live/runtime path: the same plain unit name must be committed again after
-- each actual anchor transition, without changing the font or recreating the
-- FontString. An unchanged apply must remain a no-op.
local live = NewFrame("boss1")
Text.Apply(live, NewSpec("TOP"))
local liveName = assert(live.nameText)
ApplyText(liveName, "Boss One")
local liveFontWrites = liveName.fontWrites
local livePointWrites = liveName.pointWrites
local liveTextWrites = liveName.textWrites
CheckPoint(liveName, "TOP", "TOP", 4, "CENTER", "live TOP")

Text.Apply(live, NewSpec("TOP"))
ApplyText(liveName, "Boss One")
Check(live.nameText == liveName, "live unchanged apply recreated the name FontString")
Check(liveName.pointWrites == livePointWrites, "live unchanged apply rewrote anchor geometry")
Check(liveName.textWrites == liveTextWrites, "live unchanged apply bypassed the text cache")

Text.Apply(live, NewSpec("FRAMECENTER"))
CheckPoint(liveName, "CENTER", "CENTER", 4, "CENTER", "live FRAMECENTER")
ApplyText(liveName, "Boss One")
liveTextWrites = liveTextWrites + 1
Check(liveName.textWrites == liveTextWrites,
  "live TOP -> FRAMECENTER did not recommit the unchanged name")

Text.Apply(live, NewSpec("TOPRIGHT"))
CheckPoint(liveName, "TOPRIGHT", "TOPRIGHT", -4, "RIGHT", "live TOPRIGHT")
ApplyText(liveName, "Boss One")
liveTextWrites = liveTextWrites + 1
Check(liveName.textWrites == liveTextWrites,
  "live FRAMECENTER -> TOPRIGHT did not recommit the unchanged name")
Check(live.nameText == liveName, "live anchor transition recreated the name FontString")
Check(liveName.fontWrites == liveFontWrites, "live anchor transition required a font-size/font rewrite")
Check(liveName:IsShown(), "live anchor transition hid the name FontString")

-- Name-relative status uses an invisible, same-text proxy. Its glyph geometry
-- has the identical cache contract and must be invalidated with the visible
-- name. Group anchors use CENTER for the middle row.
local proxyFrame = NewFrame("party1")
proxyFrame._msufIsGroupFrame = true
proxyFrame._msufNameRelativeStatus = true
Text.Apply(proxyFrame, NewSpec("TOP", true))
local proxyName = assert(proxyFrame.nameText)
local proxy = assert(proxyFrame._msufNameAnchorText)
Check(proxyFrame._msufNameAnchorTextActive == true, "name-anchor proxy was not active")
ApplyText(proxyName, "Proxy Member")
ApplyText(proxy, "Proxy Member")
local proxyNameWrites, proxyWrites = proxyName.textWrites, proxy.textWrites

Text.Apply(proxyFrame, NewSpec("TOP", true))
ApplyText(proxyName, "Proxy Member")
ApplyText(proxy, "Proxy Member")
Check(proxyName.textWrites == proxyNameWrites and proxy.textWrites == proxyWrites,
  "unchanged proxy apply bypassed the text cache")

Text.Apply(proxyFrame, NewSpec("CENTER", true))
ApplyText(proxyName, "Proxy Member")
ApplyText(proxy, "Proxy Member")
proxyNameWrites, proxyWrites = proxyNameWrites + 1, proxyWrites + 1
Check(proxyName.textWrites == proxyNameWrites,
  "visible group name cache survived TOP -> CENTER")
Check(proxy.textWrites == proxyWrites,
  "active name-anchor proxy cache survived TOP -> CENTER")

Text.Apply(proxyFrame, NewSpec("TOPRIGHT", true))
ApplyText(proxyName, "Proxy Member")
ApplyText(proxy, "Proxy Member")
proxyNameWrites, proxyWrites = proxyNameWrites + 1, proxyWrites + 1
Check(proxyName.textWrites == proxyNameWrites,
  "visible group name cache survived CENTER -> TOPRIGHT")
Check(proxy.textWrites == proxyWrites,
  "active name-anchor proxy cache survived CENTER -> TOPRIGHT")

-- External Boss preview hand-off: NameText caches the absent live boss as an
-- empty string, then the preview owner writes its synthetic label directly.
-- An unchanged layout deliberately keeps that hand-off cached. A changed
-- anchor must invalidate the empty cache so NameText clears the old glyph run
-- before the preview owner re-stamps the same synthetic string.
local preview = NewFrame("boss1")
Text.Apply(preview, NewSpec("TOP"))
local previewName = assert(preview.nameText)
ApplyText(previewName, "")
previewName:SetText("Boss Preview")
local previewFontWrites = previewName.fontWrites
local previewWrites = previewName.textWrites

Text.Apply(preview, NewSpec("TOP"))
ApplyText(previewName, "")
Check(previewName.textWrites == previewWrites and previewName.text == "Boss Preview",
  "unchanged Boss preview layout disturbed the cached raw-text hand-off")

Text.Apply(preview, NewSpec("FRAMECENTER"))
ApplyText(previewName, "")
previewWrites = previewWrites + 1
Check(previewName.textWrites == previewWrites and previewName.text == "",
  "Boss preview TOP -> FRAMECENTER did not clear the stale synthetic glyph run")
previewName:SetText("Boss Preview")
previewWrites = previewWrites + 1

Text.Apply(preview, NewSpec("FRAMECENTER"))
ApplyText(previewName, "")
Check(previewName.textWrites == previewWrites and previewName.text == "Boss Preview",
  "unchanged FRAMECENTER preview disturbed the cached raw-text hand-off")

Text.Apply(preview, NewSpec("TOPRIGHT"))
ApplyText(previewName, "")
previewWrites = previewWrites + 1
Check(previewName.textWrites == previewWrites and previewName.text == "",
  "Boss preview FRAMECENTER -> TOPRIGHT did not clear the stale synthetic glyph run")
previewName:SetText("Boss Preview")
previewWrites = previewWrites + 1
Check(preview.nameText == previewName, "Boss preview anchor transition recreated the name FontString")
Check(previewName.fontWrites == previewFontWrites,
  "Boss preview anchor transition required a font-size/font rewrite")
Check(previewName:IsShown(), "Boss preview anchor transition hid the name FontString")

-- Level/race/class preview text shares the name-relative glyph geometry above.
-- Keep its font owner aligned with the runtime status element: the compiled
-- unit font must be applied before SetPreviewIconTexture restores the
-- indicator-specific text color, and the layout branch must not overwrite it.
local previewFile = assert(io.open(
  "MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Render.lua", "rb"))
local previewSource = previewFile:read("*a")
previewFile:close()
local runtimeFontCall =
  "ApplyRuntimePreviewFont(runtimeSpec, ApplyPreviewFont, icon.txt, max(7, sz),"
local runtimeFontPos = previewSource:find(runtimeFontCall, 1, true)
Check(runtimeFontPos ~= nil, "identity Preview does not use the compiled runtime font")
Check(previewSource:find('return (anchor == "NAMERIGHT" or anchor == "NAMELEFT") and "name" or nil', 1, true),
  "identity Preview changes font roles outside name-relative anchors")
local previewTextPos = runtimeFontPos and previewSource:find(
  "R.SetPreviewIconTexture(icon, spec, conf, g, key, data, statusCfg, box._previewStatusText)",
  runtimeFontPos, true)
Check(previewTextPos ~= nil and runtimeFontPos < previewTextPos,
  "identity Preview applies its font after its indicator color")
local identityLayoutPos = previewTextPos and previewSource:find(
  "if isIdentityText then", previewTextPos, true)
local statusTextLayoutPos = identityLayoutPos and previewSource:find(
  "elseif R.PreviewStatus.IsStatusTextState", identityLayoutPos, true)
local identityLayout = identityLayoutPos and statusTextLayoutPos
  and previewSource:sub(identityLayoutPos, statusTextLayoutPos - 1) or ""
Check(identityLayout ~= "", "identity Preview layout branch is missing")
Check(not identityLayout:find("ApplyPreviewFont(icon.txt", 1, true),
  "identity Preview layout overwrites the compiled runtime font")

local statusFile = assert(io.open(
  "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Status.lua", "rb"))
local statusSource = statusFile:read("*a")
statusFile:close()
Check(statusSource:find('NAME_FONT_STATUS[key] and nameRelative and "name" or nil', 1, true),
  "runtime identity text does not share the name font role")

local fontRuntimeFile = assert(io.open(
  "MidnightSimpleUnitFrames/Runtime/MSUF_FontRuntime.lua", "rb"))
local fontRuntimeSource = fontRuntimeFile:read("*a")
fontRuntimeFile:close()
Check(fontRuntimeSource:find("_MSUF_ApplyFontCached(f._msufNameAnchorText, nameSize", 1, true),
  "font fallback does not keep the name anchor proxy metric-identical")

if #failures > 0 then
  error("unit name anchor reflow smoke failed:\n - " .. table.concat(failures, "\n - "), 0)
end

print("unit name anchor reflow smoke: ok")
