local _, MSUF = ...
local Text = MSUF and MSUF.UFText
if not Text then return end

--- UnitFrames/Engine/Elements/MSUF_UF_Text_Layout.lua
---
--- Cold/warm text layout and FontString apply code. Text formatting/runtime
--- lives in the companion text modules; this file positions FontStrings, applies
--- font/color/layer settings, and rebuilds compiled text runtime after layout
--- changes. Hot text updates should use the compiled functions, not layout work.

local CreateFrame = Text.CreateFrame
local UF = Text.UF
local tonumber = Text.tonumber
local floor = Text.floor
local max = Text.max
local concat = table.concat
local tostring = tostring
local EMPTY_EVENTS = Text.EMPTY_EVENTS
local DrawSubLayer = Text.DrawSubLayer
local ClampFrameLayer = Text.ClampFrameLayer
local GetLayerBaseLevel = Text.GetLayerBaseLevel
local Layers = UF and UF.Layers or {}
local SetFrameLevelCached = Text.SetFrameLevelCached
local SetShownCached = Text.SetShownCached
local SetTextCached = Text.SetTextCached
local SetFont = Text.SetFont
local ApplyNameTextColor = Text.ApplyNameTextColor or function(frame, unit)
  Text.SetNameTextColor(frame, Text.NameTextColor(frame, unit))
end
local ResolveHealthTextModes = Text.ResolveHealthTextModes
local CompileTextRuntime = Text.CompileTextRuntime
local SetHealthTextColor = Text.SetHealthTextColor
local UpdateHealthTextColor = Text.UpdateHealthTextColor
local RefreshNameRelativeStatusAnchors = MSUF.UFStatusRuntime and MSUF.UFStatusRuntime.RefreshNameRelativeAnchors
local issecretvalue = _G.issecretvalue or function(_) return false end
local function LayoutText(fs, point, relPoint, x, y, justify, relativeTo)
  if not fs then
    return
  end
  x, y = tonumber(x) or 0, tonumber(y) or 0
  relativeTo = relativeTo or fs:GetParent()
  if fs._msufPoint ~= point or fs._msufRelPoint ~= relPoint or fs._msufRelativeTo ~= relativeTo or fs._msufX ~= x or fs._msufY ~= y then
    fs:ClearAllPoints()
    fs:SetPoint(point, relativeTo, relPoint, x, y)
    fs._msufPoint, fs._msufRelPoint, fs._msufRelativeTo, fs._msufX, fs._msufY = point, relPoint, relativeTo, x, y
  end
  if fs._msufJustifyH ~= justify then
    fs:SetJustifyH(justify)
    fs._msufJustifyH = justify
  end
end

local VALID_TEXT_POINTS = {
  TOPLEFT = true, TOP = true, TOPRIGHT = true,
  LEFT = true, CENTER = true, RIGHT = true,
  BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local function DirectTextPoint(value, fallback)
  value = type(value) == "string" and value:upper() or nil
  if value == "NAMELEFT" then
    return "LEFT"
  elseif value == "NAMERIGHT" then
    return "RIGHT"
  end
  if value and VALID_TEXT_POINTS[value] then
    return value
  end
  return fallback or "CENTER"
end

local function DirectJustify(point, fallback)
  point = tostring(point or ""):upper()
  if point:find("LEFT", 1, true) then
    return "LEFT"
  elseif point:find("RIGHT", 1, true) then
    return "RIGHT"
  elseif fallback then
    return fallback
  end
  return "CENTER"
end

local function LayoutDirectText(fs, text, prefix, fallbackPoint, fallbackRelPoint, fallbackX, fallbackY, fallbackJustify, relativeTo)
  local point = DirectTextPoint(text and text[prefix .. "Point"], fallbackPoint)
  local relPoint = DirectTextPoint(text and text[prefix .. "RelativePoint"], fallbackRelPoint or point)
  local x = tonumber(text and text[prefix .. "X"])
  local y = tonumber(text and text[prefix .. "Y"])
  if x == nil then x = fallbackX or 0 end
  if y == nil then y = fallbackY or 0 end
  LayoutText(fs, point, relPoint, x, y, DirectJustify(point, fallbackJustify), relativeTo)
end

local function ApplyTextColor(fs, color)
  if not (fs and type(color) == "table") then
    return
  end
  local r = tonumber(color.r or color[1])
  local g = tonumber(color.g or color[2])
  local b = tonumber(color.b or color[3])
  local a = color.a
  if a == nil then a = color[4] end
  a = tonumber(a) or 1
  if r == nil or g == nil or b == nil then
    return
  end
  if fs._msufTextR ~= r or fs._msufTextG ~= g or fs._msufTextB ~= b or fs._msufTextA ~= a then
    fs:SetTextColor(r, g, b, a)
    fs._msufTextR, fs._msufTextG, fs._msufTextB, fs._msufTextA = r, g, b, a
  end
end

local function LayoutTextSpan(fs, relativeTo, leftX, rightX, y, justify, verticalPoint)
  if not (fs and relativeTo) then
    return
  end
  leftX, rightX, y = tonumber(leftX) or 0, tonumber(rightX) or 0, tonumber(y) or 0
  verticalPoint = verticalPoint == "TOP" and "TOP" or "CENTER"
  local leftPoint = verticalPoint == "TOP" and "TOPLEFT" or "LEFT"
  local rightPoint = verticalPoint == "TOP" and "TOPRIGHT" or "RIGHT"
  if fs._msufPoint ~= "SPAN"
    or fs._msufRelativeTo ~= relativeTo
    or fs._msufLeftX ~= leftX
    or fs._msufRightX ~= rightX
    or fs._msufY ~= y
    or fs._msufSpanVerticalPoint ~= verticalPoint then
    fs:ClearAllPoints()
    fs:SetPoint(leftPoint, relativeTo, leftPoint, leftX, y)
    fs:SetPoint(rightPoint, relativeTo, rightPoint, rightX, y)
    fs._msufPoint, fs._msufRelPoint, fs._msufRelativeTo = "SPAN", nil, relativeTo
    fs._msufLeftX, fs._msufRightX, fs._msufX, fs._msufY = leftX, rightX, nil, y
    fs._msufSpanVerticalPoint = verticalPoint
  end
  if fs._msufJustifyH ~= justify then
    fs:SetJustifyH(justify)
    fs._msufJustifyH = justify
  end
end

local function ResolveUnitNameAnchor(anchor, x)
  anchor = tostring(anchor or "TOPLEFT"):upper()
  x = tonumber(x) or 0
  -- 5.77 and the early 6.0 betas stored LEFT/CENTER/RIGHT while rendering
  -- them on the top edge. Keep those aliases as a defensive runtime fallback;
  -- normalized profiles use TOP* for that legacy geometry and FRAME* for the
  -- newly selectable vertical-center row.
  if anchor == "LEFT" then anchor = "TOPLEFT"
  elseif anchor == "CENTER" then anchor = "TOP"
  elseif anchor == "RIGHT" then anchor = "TOPRIGHT" end

  if anchor == "TOPRIGHT" then
    return "TOPRIGHT", "TOPRIGHT", -x, "RIGHT", anchor
  elseif anchor == "TOP" then
    return "TOP", "TOP", x, "CENTER", anchor
  elseif anchor == "FRAMELEFT" then
    return "LEFT", "LEFT", x, "LEFT", anchor
  elseif anchor == "FRAMECENTER" then
    return "CENTER", "CENTER", x, "CENTER", anchor
  elseif anchor == "FRAMERIGHT" then
    return "RIGHT", "RIGHT", -x, "RIGHT", anchor
  end
  return "TOPLEFT", "TOPLEFT", x, "LEFT", "TOPLEFT"
end

local function LayoutName(fs, spec, text)
  if not fs then
    return
  end
  local x = tonumber(text and text.nameX) or 4
  local y = tonumber(text and text.nameY) or -4
  local point, relPoint, resolvedX, justify = ResolveUnitNameAnchor(text and text.nameAnchor, x)
  LayoutText(fs, point, relPoint, resolvedX, y, justify)
  if fs.SetDrawLayer then
    local layer = tonumber(text and text.nameLayer) or 5
    local sub = DrawSubLayer(layer, 5)
    if fs._msufDrawLayer ~= sub then
      fs:SetDrawLayer("OVERLAY", sub)
      fs._msufDrawLayer = sub
    end
  end
end

local function BarTextHealthAnchor(frame)
  return frame and (frame.hpBar or frame.Health or frame.health) or frame
end

local function BarTextPowerAnchor(frame, power)
  if power and power.enabled == true then
    return frame and (frame.targetPowerBar or frame.powerBar or frame.Power or frame.power) or BarTextHealthAnchor(frame)
  end
  return BarTextHealthAnchor(frame)
end

local function LayoutBarAnchoredName(frame, text)
  local fs = frame and frame.nameText
  if not fs then
    return
  end
  local health = text and text.nameAnchorToFrame == true and frame or BarTextHealthAnchor(frame)
  local anchor = text and text.nameAnchor or "LEFT"
  local x = tonumber(text and text.nameX) or 0
  local y = tonumber(text and text.nameY) or 0
  local justify = (anchor == "TOP" or anchor == "CENTER") and "CENTER"
    or (anchor == "TOPRIGHT" or anchor == "RIGHT") and "RIGHT"
    or "LEFT"
  local rightX = justify == "LEFT" and -3 or (-3 + x)
  local verticalPoint = (anchor == "TOPLEFT" or anchor == "TOP" or anchor == "TOPRIGHT") and "TOP" or "CENTER"
  LayoutTextSpan(fs, health, 3 + x, rightX, y, justify, verticalPoint)
  if fs.SetDrawLayer then
    local layer = tonumber(text and text.nameLayer) or 5
    local sub = DrawSubLayer(layer, 5)
    if fs._msufDrawLayer ~= sub then
      fs:SetDrawLayer("OVERLAY", sub)
      fs._msufDrawLayer = sub
    end
  end
end

local function SetTextLayer(fs, layer)
  if fs and fs.SetDrawLayer then
    local sub = DrawSubLayer(layer, 5)
    if fs._msufDrawLayer ~= sub then
      fs:SetDrawLayer("OVERLAY", sub)
      fs._msufDrawLayer = sub
    end
  end
end

local function SetTextSlotShown(fs, show, mode)
  if fs then
    SetShownCached(fs, show == true and mode ~= "NONE")
  end
end

local function EnsureDotsFS(frame, key, template, layer)
  local fs = frame and frame[key]
  if fs then
    return fs
  end
  local parent = frame and frame.MSUFNameTextLayer or frame
  if not parent then
    return nil
  end
  fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
  fs:SetText("..")
  fs:SetJustifyH("CENTER")
  if fs.SetWordWrap then
    fs:SetWordWrap(false)
  end
  if fs.SetNonSpaceWrap then
    fs:SetNonSpaceWrap(false)
  end
  frame[key] = fs
  SetTextLayer(fs, layer)
  return fs
end

local function HideDots(fs)
  if fs then
    fs:Hide()
    fs._msufShown = nil
  end
end

local function EnsureClipFrame(frame, key, layer)
  local clip = frame and frame[key]
  if clip then
    return clip
  end
  local parent = frame and frame.MSUFNameTextLayer or frame
  if not parent then
    return nil
  end
  clip = CreateFrame("Frame", nil, parent)
  clip:EnableMouse(false)
  if clip.SetClipsChildren then
    clip:SetClipsChildren(true)
  end
  frame[key] = clip
  if frame.GetFrameLevel and clip.SetFrameLevel then
    local level = (Layers.TextLevel and Layers.TextLevel(frame, layer, 5)) or (GetLayerBaseLevel(frame) + 10 + ClampFrameLayer(layer, 5))
    SetFrameLevelCached(clip, level)
  end
  return clip
end

local function LayoutDots(dots, fs, side)
  if not (dots and fs) then
    return
  end
  dots:ClearAllPoints()
  if side == "LEFT" then
    dots:SetPoint("RIGHT", fs, "LEFT", -1, 0)
  else
    dots:SetPoint("LEFT", fs, "RIGHT", 1, 0)
  end
  dots:Show()
  dots._msufShown = true
end

local function AnchorInlineToName(frame)
  local name = frame and frame.nameText
  local sep = frame and frame.totInlineSep
  if not (frame and frame._msufInlineAnchorDynamic == true and name and sep and name.GetStringWidth) then
    return
  end
  local width = name:GetStringWidth()
  sep:ClearAllPoints()
  sep:SetPoint("LEFT", name, "LEFT", width, 0)
  sep._msufPoint, sep._msufRelPoint, sep._msufRelativeTo, sep._msufX, sep._msufY = "LEFT", "LEFT", name, width, 0
end

local function AnchorInlineToNameClip(frame)
  local clip = frame and frame._msufNameInlineClip
  local name = frame and frame.nameText
  local sep = frame and frame.totInlineSep
  if not (clip and name and sep) then
    return false
  end
  if frame._msufNameCenterClip == true then
    -- Centered mode re-anchors the name FontString per name (fit vs overflow),
    -- so hang the inline text off the stable clip window edge instead.
    if sep._msufPoint ~= "LEFT" or sep._msufRelPoint ~= "RIGHT" or sep._msufRelativeTo ~= clip or sep._msufX ~= 4 or sep._msufY ~= 0 then
      sep:ClearAllPoints()
      sep:SetPoint("LEFT", clip, "RIGHT", 4, 0)
      sep._msufPoint, sep._msufRelPoint, sep._msufRelativeTo, sep._msufX, sep._msufY = "LEFT", "RIGHT", clip, 4, 0
    end
    return true
  end
  local side = frame._msufNameInlineClipSide
  local width = frame._msufNameInlineClipWidth or clip._msufW or 0
  local relPoint = side == "RIGHT" and "LEFT" or "RIGHT"
  local x = side == "RIGHT" and (width + 4) or 4
  if sep._msufPoint ~= "LEFT" or sep._msufRelPoint ~= relPoint or sep._msufRelativeTo ~= name or sep._msufX ~= x or sep._msufY ~= 0 then
    sep:ClearAllPoints()
    sep:SetPoint("LEFT", name, relPoint, x, 0)
    sep._msufPoint, sep._msufRelPoint, sep._msufRelativeTo, sep._msufX, sep._msufY = "LEFT", relPoint, name, x, 0
  end
  return true
end

Text.AnchorInlineToName = AnchorInlineToName

local measureFS
local function ApproxNameWidth(fs, maxChars)
  maxChars = floor((tonumber(maxChars) or 0) + 0.5)
  if maxChars <= 0 then return 0 end
  if not measureFS then
    measureFS = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    measureFS:Hide()
  end
  if fs and fs.GetFont and measureFS.SetFont then
    local font, size, flags = fs:GetFont()
    if font and size then
      measureFS:SetFont(font, size, flags)
    end
  end
  measureFS:SetText("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
  local w = measureFS:GetStringWidth()
  if type(w) == "number" and w > 0 then
    return floor((w / 52) * maxChars + 0.5)
  end
  local size
  if fs and fs.GetFont then
    local _, fontSize = fs:GetFont()
    size = fontSize
  end
  return floor(((tonumber(size) or 12) * 0.62 * maxChars) + 0.5)
end

local function RestoreNameParent(frame)
  local fs = frame and frame.nameText
  local clip = frame and frame._msufNameClipFrame
  if fs and clip and fs.GetParent and fs:GetParent() == clip then
    fs:SetParent(frame._msufNameTextOrigParent or frame.MSUFNameTextLayer or frame)
    fs:ClearAllPoints()
    fs._msufPoint, fs._msufRelPoint, fs._msufRelativeTo, fs._msufX, fs._msufY = nil, nil, nil, nil, nil
    fs._msufShown = nil
  end
end

local function NameRightReservation(frame, spec)
  local status = spec and spec.status
  if not status then
    return 0
  end
  local reserved = 0
  local raidGroup = status.raidGroup
  if raidGroup and raidGroup.enabled == true and raidGroup.anchor == "NAMERIGHT" then
    reserved = reserved + 24
  end
  local level = status.level
  if level and level.enabled == true and level.anchor == "NAMERIGHT" then
    reserved = reserved + 26
  end
  return reserved
end

local function ClearNameClip(frame)
  if not frame then return end
  RestoreNameParent(frame)
  if frame._msufNameClipFrame then
    frame._msufNameClipFrame:Hide()
  end
  if frame._msufNameDotsFS then
    frame._msufNameDotsFS:Hide()
  end
  frame._msufNameClipStamp = nil
  frame._msufNameClipAnchorStamp = nil
  frame._msufNameTextClipStamp = nil
  frame._msufNameDotsStamp = nil
  frame._msufNameInlineAnchor = frame.nameText
  frame._msufNameInlineClip = nil
  frame._msufNameInlineClipSide = nil
  frame._msufNameInlineClipWidth = nil
  frame._msufNameCenterClip = nil
  frame._msufNameCenterClipOverflow = nil
  if frame.nameText then
    frame.nameText._msufShown = nil
  end
  HideDots(frame._msufNameDotsFS)
end

local function LayoutNameClip(clip, spec, text, width)
  if not clip then
    return
  end
  local height = tonumber(spec and spec.nameFontSize) or 16
  height = floor(height + 6 + 0.5)
  if height < 12 then
    height = 12
  end
  if clip._msufW ~= width or clip._msufH ~= height then
    clip:SetSize(width, height)
    clip._msufW, clip._msufH = width, height
  end
  local x = tonumber(text and text.nameX) or 4
  local y = tonumber(text and text.nameY) or -4
  local parent = clip:GetParent()
  local point, relPoint, resolvedX = ResolveUnitNameAnchor(text and text.nameAnchor, x)
  x = resolvedX
  if clip._msufPoint ~= point or clip._msufRelPoint ~= relPoint or clip._msufX ~= x or clip._msufY ~= y then
    clip:ClearAllPoints()
    clip:SetPoint(point, parent, relPoint, x, y)
    clip._msufPoint, clip._msufRelPoint, clip._msufX, clip._msufY = point, relPoint, x, y
  end
  clip:Show()
end

local function AnchorNameToClip(fs, clip, point, justify)
  if fs._msufPoint ~= point or fs._msufRelPoint ~= point or fs._msufRelativeTo ~= clip then
    fs:ClearAllPoints()
    fs:SetPoint(point, clip, point, 0, 0)
    fs._msufPoint, fs._msufRelPoint, fs._msufRelativeTo, fs._msufX, fs._msufY = point, point, clip, 0, 0
  end
  if fs._msufJustifyH ~= justify then
    fs:SetJustifyH(justify)
    fs._msufJustifyH = justify
  end
end

local function NameCenterClipAnchor(frame, side)
  if frame._msufNameCenterClipOverflow == true then
    if side == "LEFT" then
      return "TOPRIGHT", "RIGHT"
    end
    return "TOPLEFT", "LEFT"
  end
  return "TOP", "CENTER"
end

local function ApplyNoEllipsisClip(frame, fs, spec, text, width, side)
  local clip = EnsureClipFrame(frame, "_msufNameClipFrame", text and text.nameLayer)
  if not clip then
    return false
  end
  LayoutNameClip(clip, spec, text, width)
  if fs.GetParent and fs:GetParent() ~= clip then
    frame._msufNameTextOrigParent = frame._msufNameTextOrigParent or fs:GetParent()
    fs:SetParent(clip)
    fs:ClearAllPoints()
    fs._msufPoint, fs._msufRelPoint, fs._msufRelativeTo, fs._msufX, fs._msufY = nil, nil, nil, nil, nil
  end

  local frameWidth = tonumber(spec and spec.width) or (frame.GetWidth and frame:GetWidth()) or 220
  if frameWidth <= 0 then
    frameWidth = 220
  end
  local renderWidth = max(512, frameWidth * 2, width * 4)
  if fs._msufNameClipTextWidth ~= renderWidth then
    fs:SetWidth(renderWidth)
    fs._msufNameClipTextWidth = renderWidth
  end
  local _, _, _, anchorJustify = ResolveUnitNameAnchor(text and text.nameAnchor, 0)
  local point, justify
  if anchorJustify == "CENTER" then
    -- Keep TOP/FRAMECENTER names optically centered even when the actual unit
    -- name is restricted and cannot be measured. The oversized FontString is
    -- centered behind the clip window, so short and long names share one
    -- secret-safe center without GetStringWidth or string slicing. The warm
    -- name path (Text.RefreshNameCenterClipFit) re-anchors measurable names
    -- that overflow the window so only the configured clip side is cut instead
    -- of both ends; this cold pass replays its last verdict without measuring.
    frame._msufNameCenterClip = true
    point, justify = NameCenterClipAnchor(frame, side)
  else
    frame._msufNameCenterClip = nil
    frame._msufNameCenterClipOverflow = nil
    point = side == "LEFT" and "TOPRIGHT" or "TOPLEFT"
    justify = side == "LEFT" and "RIGHT" or "LEFT"
  end
  AnchorNameToClip(fs, clip, point, justify)
  frame._msufNameInlineAnchor = clip
  frame._msufNameInlineClip = clip
  frame._msufNameInlineClipSide = side
  frame._msufNameInlineClipWidth = width
  HideDots(frame._msufNameDotsFS)
  fs._msufShown = nil
  return true
end

local function ApplyNameClip(frame, spec, text)
  local fs = frame and frame.nameText
  if not fs then return end

  RestoreNameParent(frame)
  if frame._msufNameClipFrame then
    frame._msufNameClipFrame:Hide()
  end
  if frame._msufNameDotsFS then
    frame._msufNameDotsFS:Hide()
  end
  frame._msufNameClipStamp = nil
  frame._msufNameClipAnchorStamp = nil
  frame._msufNameTextClipStamp = nil
  frame._msufNameDotsStamp = nil
  frame._msufNameInlineAnchor = fs
  frame._msufNameInlineClip = nil
  frame._msufNameInlineClipSide = nil
  frame._msufNameInlineClipWidth = nil
  frame._msufNameCenterClip = nil

  fs:SetWordWrap(false)
  if fs.SetNonSpaceWrap then
    fs:SetNonSpaceWrap(false)
  end

  local frameWidth = tonumber(spec and spec.width) or (frame.GetWidth and frame:GetWidth()) or 220
  if frameWidth <= 0 then frameWidth = 220 end
  local nameWidth = floor(frameWidth * 0.80 + 0.5)
  if nameWidth < 80 then nameWidth = 80 end
  local reservedRight = NameRightReservation(frame, spec)
  if reservedRight > 0 then
    nameWidth = nameWidth - reservedRight
    if nameWidth < 40 then nameWidth = 40 end
  end

  local legacyTruncation = text and text.nameLegacyTruncation == true
  local maxChars = not legacyTruncation and text and text.nameShorten == true and tonumber(text.nameShortenMax) or 0
  local shorten = maxChars and maxChars > 0
  local clipSide = text and text.nameShortenSide == "RIGHT" and "RIGHT" or "LEFT"
  local _, _, _, justify = ResolveUnitNameAnchor(text and text.nameAnchor, 0)
  if not shorten then
    if fs._msufJustifyH ~= justify then
      fs:SetJustifyH(justify)
      fs._msufJustifyH = justify
    end
    if fs._msufNameClipTextWidth ~= 0 then
      fs:SetWidth(0)
      fs._msufNameClipTextWidth = 0
    end
    HideDots(frame._msufNameDotsFS)
    fs._msufShown = nil
    return
  end

  if shorten then
    local approx = ApproxNameWidth(fs, maxChars)
    if approx > 0 then
      -- NameRightReservation already reduces the frame-space cap above. Keep
      -- the configured character cap independent so anchoring Level/Raid Group
      -- to NAMERIGHT cannot silently turn 10 requested characters into fewer.
      local w = floor(approx + 0.5)
      if w < nameWidth then
        nameWidth = w
        if nameWidth < 40 then nameWidth = 40 end
      end
    end
  end

  if shorten and justify == "LEFT" then
    justify = clipSide == "LEFT" and "RIGHT" or "LEFT"
  end

  local maskPx = text and text.nameShortenDots == true and tonumber(text.nameShortenMaskPx) or 0
  maskPx = floor((maskPx or 0) + 0.5)
  if maskPx < 0 then
    maskPx = 0
  elseif maskPx > 80 then
    maskPx = 80
  end
  local clipWidth = nameWidth - maskPx
  if clipWidth < 10 then clipWidth = 10 end

  if shorten and text.nameShortenDots ~= true and ApplyNoEllipsisClip(frame, fs, spec, text, nameWidth, clipSide) then
    return
  end

  if fs._msufJustifyH ~= justify then
    fs:SetJustifyH(justify)
    fs._msufJustifyH = justify
  end
  if fs._msufNameClipTextWidth ~= clipWidth then
    fs:SetWidth(clipWidth)
    fs._msufNameClipTextWidth = clipWidth
  end
  fs._msufShown = nil

  if shorten and text.nameShortenDots == true then
    local dots = EnsureDotsFS(frame, "_msufNameDotsFS", "GameFontNormal", text.nameLayer)
    SetFont(dots, spec, spec and spec.nameFontSize, "name")
    LayoutDots(dots, fs, clipSide)
  else
    HideDots(frame._msufNameDotsFS)
  end
end

-- Warm companion to ApplyNoEllipsisClip's centered branch, called after each
-- name write. Names that are plain strings and measurably overflow the clip
-- window switch to the configured clip side so only one end is cut; secret
-- names keep the measurement-free centered slice.
function Text.RefreshNameCenterClipFit(frame)
  local fs = frame and frame.nameText
  local clip = frame and frame._msufNameInlineClip
  if not (fs and clip) then
    return
  end
  local overflow = false
  local raw = fs.GetText and fs:GetText()
  if not (raw == nil or issecretvalue(raw) == true) and raw ~= "" and fs.GetStringWidth then
    local window = tonumber(frame._msufNameInlineClipWidth) or 0
    local width = fs:GetStringWidth()
    if window > 0 and type(width) == "number" and width > window + 0.5 then
      overflow = true
    end
  end
  if frame._msufNameCenterClipOverflow ~= overflow then
    frame._msufNameCenterClipOverflow = overflow
    if frame._msufNameCenterClip == true then
      local point, justify = NameCenterClipAnchor(frame, frame._msufNameInlineClipSide)
      AnchorNameToClip(fs, clip, point, justify)
    end
    -- NAMELEFT/NAMERIGHT status text flips between the glyph-edge twin and
    -- the window's cut edge with this verdict.
    if frame._msufNameRelativeStatus == true and RefreshNameRelativeStatusAnchors then
      RefreshNameRelativeStatusAnchors(frame)
    end
  end
end

local function ApplyInlineNameClip(frame, spec, text)
  local fs = frame and frame.totInlineText
  local inline = text and text.inlineToT
  if not fs then
    return
  end

  fs:SetWordWrap(false)
  if fs.SetNonSpaceWrap then
    fs:SetNonSpaceWrap(false)
  end

  local maxChars = inline and inline.nameShorten == true and tonumber(inline.nameShortenMax) or 0
  local frameWidth = tonumber(spec and spec.width) or (frame.GetWidth and frame:GetWidth()) or 220
  if frameWidth <= 0 then
    frameWidth = 220
  end
  if not maxChars or maxChars <= 0 then
    local width = floor(frameWidth * 0.42 + 0.5)
    if width < 80 then
      width = 80
    end
    if fs._msufInlineNameWidth ~= width then
      fs:SetWidth(width)
      fs._msufInlineNameWidth = width
    end
    if fs._msufJustifyH ~= "LEFT" then
      fs:SetJustifyH("LEFT")
      fs._msufJustifyH = "LEFT"
    end
    HideDots(frame._msufInlineDotsFS)
    return
  end

  local width = ApproxNameWidth(fs, maxChars)
  if width <= 0 then
    width = 48
  elseif width < 40 then
    width = 40
  end

  local cap = floor(frameWidth * 0.42 + 0.5)
  if cap > 40 and width > cap then
    width = cap
  end

  local clipSide = inline.nameShortenSide == "LEFT" and "LEFT" or "RIGHT"
  local justify = clipSide == "LEFT" and "RIGHT" or "LEFT"
  if fs._msufJustifyH ~= justify then
    fs:SetJustifyH(justify)
    fs._msufJustifyH = justify
  end
  if fs._msufInlineNameWidth ~= width then
    fs:SetWidth(width)
    fs._msufInlineNameWidth = width
  end

  if inline.nameShortenDots == true then
    local dots = EnsureDotsFS(frame, "_msufInlineDotsFS", "GameFontNormal", text.nameLayer)
    SetFont(dots, spec, spec and spec.nameFontSize, "name")
    LayoutDots(dots, fs, clipSide)
  else
    HideDots(frame._msufInlineDotsFS)
  end
end
local function EnsureTextOverlay(frame, field, layer, fallback)
  local overlay = frame[field]
  if not overlay then
    overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints(frame)
    overlay:EnableMouse(false)
    if overlay.SetClipsChildren then
      overlay:SetClipsChildren(false)
    end
    frame[field] = overlay
  end
  if frame.GetFrameLevel and overlay.SetFrameLevel then
    local level = (Layers.TextLevel and Layers.TextLevel(frame, layer, fallback)) or (GetLayerBaseLevel(frame) + 10 + ClampFrameLayer(layer, fallback))
    if overlay._msufFrameLevel ~= level then
      overlay:SetFrameLevel(level)
      overlay._msufFrameLevel = level
    end
  end
  return overlay
end

local function EnsureFontString(frame, key, template, layer, fallback, layerField)
  local overlay = EnsureTextOverlay(frame, layerField, layer, fallback)
  local fs = frame[key]
  local changed = false
  if fs and fs.GetParent and fs:GetParent() ~= overlay then
    if fs.SetParent then
      fs:SetParent(overlay)
      fs:ClearAllPoints()
      fs._msufPoint, fs._msufRelPoint, fs._msufRelativeTo, fs._msufX, fs._msufY = nil, nil, nil, nil, nil
      changed = true
    else
      fs:Hide()
      fs:SetText("")
      fs = nil
      changed = true
    end
  end
  if not fs then
    fs = overlay:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
    if fs.SetWordWrap then
      fs:SetWordWrap(false)
    end
    frame[key] = fs
    changed = true
  end
  return fs, changed
end

local function EnsureNameAnchorProxy(frame, spec)
  if not frame then return false end
  local text = spec and spec.text or {}
  local shortenMax = text.nameShorten == true and tonumber(text.nameShortenMax) or 0
  local clipped = text.nameLegacyTruncation ~= true and shortenMax and shortenMax > 0

  -- Shortened names render inside a fixed maxChars-wide window, so the window
  -- edge is not the glyph edge for names that fit it. Hang the twin off the
  -- same window corner the visible run starts from; its auto-sized far edge
  -- then coincides with the rendered glyphs without measuring the (possibly
  -- secret) name. Status anchoring falls back to the window's cut edge only
  -- while the warm fit reports a real overflow.
  local clipTarget, clipPoint
  if clipped and text.directLayout ~= true then
    if text.nameShortenDots ~= true then
      clipTarget = frame._msufNameInlineClip
      if clipTarget then
        if frame._msufNameCenterClip == true then
          clipPoint = "TOP"
        elseif frame._msufNameInlineClipSide == "LEFT" then
          clipPoint = "TOPRIGHT"
        else
          clipPoint = "TOPLEFT"
        end
      end
    else
      clipTarget = frame.nameText
      if clipTarget then
        local justify = clipTarget._msufJustifyH
        clipPoint = justify == "RIGHT" and "TOPRIGHT" or justify == "CENTER" and "TOP" or "TOPLEFT"
      end
    end
  end

  local active = frame._msufNameRelativeStatus == true
    and spec and spec.showName ~= false
    and text.directLayout ~= true
    and ((text.anchorToBars == true and not clipped) or clipTarget ~= nil)
  local proxy = frame._msufNameAnchorText

  if not active then
    local changed = frame._msufNameAnchorTextActive == true
    frame._msufNameAnchorTextActive = nil
    if proxy then
      if changed and SetTextCached then SetTextCached(proxy, "") end
      SetShownCached(proxy, false)
    end
    return changed
  end

  local created
  proxy, created = EnsureFontString(frame, "_msufNameAnchorText", "GameFontNormal", text.nameLayer, 5, "MSUFNameTextLayer")
  if not proxy then return false end
  local wasActive = frame._msufNameAnchorTextActive == true
  frame._msufNameAnchorTextActive = true

  SetFont(proxy, spec, spec and spec.nameFontSize, "name")
  if proxy._msufNameAnchorNoWrap ~= true then
    if proxy.SetWordWrap then proxy:SetWordWrap(false) end
    if proxy.SetNonSpaceWrap then proxy:SetNonSpaceWrap(false) end
    proxy._msufNameAnchorNoWrap = true
  end
  if proxy._msufNameAnchorWidth ~= 0 then
    proxy:SetWidth(0)
    proxy._msufNameAnchorWidth = 0
  end
  if proxy.SetAlpha and proxy._msufNameAnchorAlpha ~= 0 then
    proxy:SetAlpha(0)
    proxy._msufNameAnchorAlpha = 0
  end

  if clipTarget then
    local justify = clipPoint == "TOPRIGHT" and "RIGHT" or clipPoint == "TOP" and "CENTER" or "LEFT"
    LayoutText(proxy, clipPoint, clipPoint, 0, 0, justify, clipTarget)
  else
    local health = text.nameAnchorToFrame == true and frame or BarTextHealthAnchor(frame)
    local anchor = text.nameAnchor or "LEFT"
    local x = tonumber(text.nameX) or 0
    local y = tonumber(text.nameY) or 0
    if anchor == "TOP" then
      LayoutText(proxy, "TOP", "TOP", x, y, "CENTER", health)
    elseif anchor == "TOPRIGHT" then
      LayoutText(proxy, "TOPRIGHT", "TOPRIGHT", -3 + x, y, "RIGHT", health)
    elseif anchor == "TOPLEFT" then
      LayoutText(proxy, "TOPLEFT", "TOPLEFT", 3 + x, y, "LEFT", health)
    elseif anchor == "CENTER" then
      LayoutText(proxy, "CENTER", "CENTER", x, y, "CENTER", health)
    elseif anchor == "RIGHT" then
      LayoutText(proxy, "RIGHT", "RIGHT", -3 + x, y, "RIGHT", health)
    else
      LayoutText(proxy, "LEFT", "LEFT", 3 + x, y, "LEFT", health)
    end
  end
  SetShownCached(proxy, true)

  -- This is a secret-safe pass-through: no comparison, measurement, or Lua
  -- arithmetic is performed on the unit name.
  if not wasActive and frame.nameText and frame.nameText.GetText and SetTextCached then
    SetTextCached(proxy, frame.nameText:GetText())
  end
  return created or not wasActive
end

Text.EnsureNameAnchorProxy = EnsureNameAnchorProxy

function Text.GetEvents()
  return EMPTY_EVENTS
end

function Text.GetUnitlessEvents()
  return EMPTY_EVENTS
end

local function TextModeEnabled(mode)
  return mode ~= nil and mode ~= "NONE"
end

local function EnsureConfiguredTextSinks(frame, spec)
  local text = spec and spec.text or {}
  local changed, ready = false, true
  local sink, sinkChanged

  if spec and spec.showName ~= false then
    sink, sinkChanged = EnsureFontString(frame, "nameText", "GameFontNormal", text.nameLayer, 5, "MSUFNameTextLayer")
    frame.nameText = sink
    changed = sinkChanged or changed
    ready = sink ~= nil and ready
  end

  local healthLeft, healthCenter, healthRight = ResolveHealthTextModes(text)
  if spec and spec.showHealthText ~= false then
    if TextModeEnabled(healthLeft) then
      sink, sinkChanged = EnsureFontString(frame, "hpTextLeft", "GameFontNormalSmall", text.healthLayer, 5, "MSUFHealthTextLayer")
      frame.hpTextLeft = sink
      changed = sinkChanged or changed
      ready = sink ~= nil and ready
    end
    if TextModeEnabled(healthCenter) then
      sink, sinkChanged = EnsureFontString(frame, "hpTextCenter", "GameFontNormalSmall", text.healthLayer, 5, "MSUFHealthTextLayer")
      frame.hpTextCenter = sink
      changed = sinkChanged or changed
      ready = sink ~= nil and ready
    end
    if TextModeEnabled(healthRight) then
      sink, sinkChanged = EnsureFontString(frame, "hpTextRight", "GameFontNormalSmall", text.healthLayer, 5, "MSUFHealthTextLayer")
      frame.hpTextRight = sink
      changed = sinkChanged or changed
      ready = sink ~= nil and ready
    end
  end
  frame.hpText = frame.hpTextRight

  if spec and spec.showPowerText ~= false then
    if TextModeEnabled(text.powerLeft) then
      sink, sinkChanged = EnsureFontString(frame, "powerTextLeft", "GameFontNormalSmall", text.powerLayer, 2, "MSUFPowerTextLayer")
      frame.powerTextLeft = sink
      changed = sinkChanged or changed
      ready = sink ~= nil and ready
    end
    if TextModeEnabled(text.powerCenter) then
      sink, sinkChanged = EnsureFontString(frame, "powerTextCenter", "GameFontNormalSmall", text.powerLayer, 2, "MSUFPowerTextLayer")
      frame.powerTextCenter = sink
      changed = sinkChanged or changed
      ready = sink ~= nil and ready
    end
    if TextModeEnabled(text.powerRight) then
      sink, sinkChanged = EnsureFontString(frame, "powerTextRight", "GameFontNormalSmall", text.powerLayer, 2, "MSUFPowerTextLayer")
      frame.powerTextRight = sink
      changed = sinkChanged or changed
      ready = sink ~= nil and ready
    end
  end
  frame.powerText = frame.powerTextRight
  return changed, ready
end

function Text.Create(frame, spec)
  return EnsureConfiguredTextSinks(frame, spec)
end

local SIG_SPEC_KEYS = { "key", "scope", "width", "height", "font", "fontFlags", "nameFontSize", "healthFontSize", "powerFontSize", "fontShadow", "fontShadowAlpha", "fontShadowX", "fontShadowY", "_msufTextLayoutRevision" }
local SIG_POWER_KEYS = { "enabled", "detached", "textOnDetached", "shape", "orbSize", "detachedLevel", "detachedHeight", "detachedWidth", "detachedWidthExplicit", "detachedX", "detachedY", "detachedAnchorMode", "detachedSyncClass", "detachedAnchorClass", "detachedClassWidth", "detachedWidthFrameName", "detachedClassWidthFrameName" }
local SIG_TEXT_KEYS = {
  "anchorToBars", "nameAnchorToFrame", "nameLegacyTruncation", "nameAnchor", "nameX", "nameY", "nameLayer", "nameShorten", "nameShortenSide", "nameShortenDots", "nameShortenMax", "nameShortenWidth", "nameLeftWidth",
  "nameShortenMaskPx",
  "directLayout", "directNamePoint", "directNameRelativePoint", "directNameX", "directNameY",
  "nameClassColor", "nameNpcColor", "nameNpcClassColor", "npcColorMode", "npcTypeColorText", "npcTypeTarget", "npcTypeFocus", "npcTypeBoss", "npcTypeToT",
  "healthLayer", "healthLeft", "healthCenter", "healthRight", "healthLeftFontSize", "healthCenterFontSize", "healthRightFontSize", "healthLeftHidePercentSymbol", "healthCenterHidePercentSymbol", "healthRightHidePercentSymbol", "healthReverse", "healthDelimiter", "healthPercentDecimals", "healthShortNumbers", "healthAbsorbIcon", "healthLeftAbsorbIcon", "healthCenterAbsorbIcon", "healthRightAbsorbIcon", "healthColorByHealth", "healthColorByClass", "healthLeftX", "healthLeftY", "healthCenterX", "healthCenterY", "healthRightX", "healthRightY",
  "directHealthLeftPoint", "directHealthLeftRelativePoint", "directHealthLeftX", "directHealthLeftY", "directHealthCenterPoint", "directHealthCenterRelativePoint", "directHealthCenterX", "directHealthCenterY", "directHealthRightPoint", "directHealthRightRelativePoint", "directHealthRightX", "directHealthRightY",
  "powerLayer", "powerLeft", "powerCenter", "powerRight", "powerLeftFontSize", "powerCenterFontSize", "powerRightFontSize", "powerLeftHidePercentSymbol", "powerCenterHidePercentSymbol", "powerRightHidePercentSymbol", "powerDelimiter", "powerColorByType", "powerLeftX", "powerLeftY", "powerCenterX", "powerCenterY", "powerRightX", "powerRightY",
  "directPowerLeftPoint", "directPowerLeftRelativePoint", "directPowerLeftX", "directPowerLeftY", "directPowerCenterPoint", "directPowerCenterRelativePoint", "directPowerCenterX", "directPowerCenterY", "directPowerRightPoint", "directPowerRightRelativePoint", "directPowerRightX", "directPowerRightY",
  "shortNumbers", "hidePercentSymbol", "hideNameOnDeadOffline",
}
local SIG_INLINE_KEYS = { "enabled", "separator", "unit", "colorMode", "targetNameClassColor", "targetNameNpcColor", "targetNameNpcClassColor", "totNameClassColor", "totNameNpcColor", "totNameNpcClassColor", "nameShorten", "nameShortenSide", "nameShortenDots", "nameShortenMax", "nameShortenWidth" }
local SIG_PARTS = {}

local function SigAddKeys(parts, n, src, keys)
  for i = 1, #keys do
    n = n + 1
    parts[n] = tostring(src and src[keys[i]])
  end
  return n
end

local function TextApplySignature(spec, text)
  local parts, n = SIG_PARTS, 0
  local power = spec and spec.power or EMPTY_EVENTS
  local inline = text and text.inlineToT or EMPTY_EVENTS
  n = SigAddKeys(parts, n, spec, SIG_SPEC_KEYS)
  n = n + 1; parts[n] = tostring(spec and spec.showName ~= false)
  n = n + 1; parts[n] = tostring(spec and spec.showHealthText ~= false)
  n = n + 1; parts[n] = tostring(spec and spec.showPowerText ~= false)
  n = SigAddKeys(parts, n, power, SIG_POWER_KEYS)
  n = SigAddKeys(parts, n, text, SIG_TEXT_KEYS)
  n = SigAddKeys(parts, n, inline, SIG_INLINE_KEYS)
  for i = n + 1, #parts do
    parts[i] = nil
  end
  return concat(parts, "\031", 1, n)
end

--- Reverse order renders the configured Right slot on the physical left
--- FontString and vice versa. ResolveHealthTextModes already mirrors the slot
--- contents (mode / hide-% / absorb icon); these mirror the per-slot font
--- sizes, offsets, direct anchors, and direct colors so every slot setting
--- follows its content to the mirrored side. Apply/cold path only.
local function HealthSlotLayoutKeys(text)
  local leftSize, rightSize = text.healthLeftFontSize, text.healthRightFontSize
  local leftX, leftY = text.healthLeftX, text.healthLeftY
  local rightX, rightY = text.healthRightX, text.healthRightY
  local leftDirect, rightDirect = "directHealthLeft", "directHealthRight"
  if text.healthReverse == true then
    leftSize, rightSize = rightSize, leftSize
    leftX, rightX = rightX, leftX
    leftY, rightY = rightY, leftY
    leftDirect, rightDirect = rightDirect, leftDirect
  end
  return leftSize, rightSize, leftX, leftY, rightX, rightY, leftDirect, rightDirect
end

local function HealthSlotDirectColors(text)
  local leftColor, rightColor = text.directHealthLeftColor, text.directHealthRightColor
  if text.healthReverse == true then
    leftColor, rightColor = rightColor, leftColor
  end
  return leftColor, rightColor
end

local function RefreshAppliedTextColors(frame, spec, text)
  local rt = frame._msufTextRuntime
  local base = spec and spec.textColor
  if rt then
    rt.textColorR = base and base.r or 1
    rt.textColorG = base and base.g or 1
    rt.textColorB = base and base.b or 1
    rt.textColorA = base and base.a or 1
    rt.healthTextAlpha = rt.textColorA
    rt._textGradientPct = nil
  end
  if text and text.directLayout == true then
    if text.healthColorByHealth ~= true and text.healthColorByClass ~= true then
      local hpLeftDirectColor, hpRightDirectColor = HealthSlotDirectColors(text)
      ApplyTextColor(frame.hpTextLeft, hpLeftDirectColor)
      ApplyTextColor(frame.hpTextCenter, text.directHealthCenterColor)
      ApplyTextColor(frame.hpTextRight, hpRightDirectColor)
    end
    if text.powerColorByType ~= true then
      ApplyTextColor(frame.powerTextLeft, text.directPowerLeftColor)
      ApplyTextColor(frame.powerTextCenter, text.directPowerCenterColor)
      ApplyTextColor(frame.powerTextRight, text.directPowerRightColor)
    end
  end
  frame._msufPowerTextColorInitialized = nil
  if text and text.healthColorByHealth ~= true and text.healthColorByClass ~= true
    and text.directLayout ~= true and rt then
    -- The health-color updater is intentionally a no-op in the default color
    -- mode. Refresh that cold path here so font opacity changes cannot leave HP
    -- text on its previous alpha while name/power text already use the new one.
    SetHealthTextColor(frame, rt, rt.textColorR, rt.textColorG, rt.textColorB, rt.textColorA)
  elseif UpdateHealthTextColor then
    UpdateHealthTextColor(frame, rt, frame.MSUFUnitKey)
  end
  if frame.nameText then
    ApplyNameTextColor(frame, frame.MSUFUnitKey)
  end
  frame._msufTextColorRevision = spec and spec._msufTextColorRevision
end

local FONT_EPOCH_TEXT_FIELDS = {
  "nameText", "_msufNameAnchorText", "raidGroupNameText", "totInlineSep", "totInlineText",
  "hpTextLeft", "hpTextCenter", "hpTextRight",
  "powerTextLeft", "powerTextCenter", "powerTextRight",
  "levelText", "classificationIndicatorText", "statusIndicatorText", "statusIndicatorOverlayText", "statusAFKTimerText",
  "_msufInlineDotsFS",
}

local function InvalidateCachedText(region)
  if not region then return end
  region._aText = nil
  region._aTextPlain = nil
  region._msufLastSetT = nil
end

local function InvalidateTextForFontEpoch(frame)
  for i = 1, #FONT_EPOCH_TEXT_FIELDS do
    InvalidateCachedText(frame[FONT_EPOCH_TEXT_FIELDS[i]])
  end
  frame._msufTextApplySignature = nil
  frame._msufTextLayoutRevision = nil
  frame._msufLastNameRaw, frame._msufLastNameText, frame._msufLastNameShortenStamp = nil, nil, nil
  frame._msufInlineRaw, frame._msufInlineText, frame._msufInlineStamp = nil, nil, nil
end

function Text.Apply(frame, spec)
  local text = spec and spec.text or {}
  local augPowerReplacement = frame._msufAugPowerReplacementActive == true
  local fontEpoch = tonumber(_G.MSUF_FontApplyEpoch) or 0
  if frame._msufTextFontAttemptEpoch ~= fontEpoch then
    InvalidateTextForFontEpoch(frame)
  end
  local sinksChanged, sinksReady = EnsureConfiguredTextSinks(frame, spec)
  sinksChanged = EnsureNameAnchorProxy(frame, spec) or sinksChanged
  local layoutRevision = spec and spec._msufTextLayoutRevision
  if frame._msufGFPreviewDetached ~= true
    and not sinksChanged
    and sinksReady
    and frame._msufTextFontAttemptEpoch == fontEpoch
    and frame._msufTextAugPowerReplacement == augPowerReplacement
    and layoutRevision ~= nil
    and frame._msufTextLayoutRevision == layoutRevision
  then
    RefreshAppliedTextColors(frame, spec, text)
    return
  end
  local signature = TextApplySignature(spec, text)
  if frame._msufGFPreviewDetached ~= true
    and not sinksChanged
    and sinksReady
    and frame._msufTextFontAttemptEpoch == fontEpoch
    and frame._msufTextAugPowerReplacement == augPowerReplacement
    and frame._msufTextApplySignature == signature
  then
    RefreshAppliedTextColors(frame, spec, text)
    return
  end
  local showName = spec and spec.showName ~= false
  local inlineEnabled = showName and spec.key == "target" and text.inlineToT and text.inlineToT.enabled == true
  if inlineEnabled then
    frame.totInlineSep = EnsureFontString(frame, "totInlineSep", "GameFontNormal", text.nameLayer, 5, "MSUFNameTextLayer")
    frame.totInlineText = EnsureFontString(frame, "totInlineText", "GameFontNormal", text.nameLayer, 5, "MSUFNameTextLayer")
  elseif frame.totInlineSep or frame.totInlineText then
    SetShownCached(frame.totInlineSep, false)
    SetShownCached(frame.totInlineText, false)
    HideDots(frame._msufInlineDotsFS)
    frame._msufInlineRaw, frame._msufInlineText, frame._msufInlineStamp = nil, nil, nil
  end
  local fontsReady = SetFont(frame.nameText, spec, spec and spec.nameFontSize, "name") ~= false
  if inlineEnabled then
    if SetFont(frame.totInlineSep, spec, spec and spec.nameFontSize, "name") == false then fontsReady = false end
    if SetFont(frame.totInlineText, spec, spec and spec.nameFontSize, "name") == false then fontsReady = false end
  end
  local hpLeftSize, hpRightSize, hpLeftX, hpLeftY, hpRightX, hpRightY, hpLeftDirect, hpRightDirect = HealthSlotLayoutKeys(text)
  if SetFont(frame.hpTextLeft, spec, hpLeftSize or (spec and spec.healthFontSize), "health") == false then fontsReady = false end
  if SetFont(frame.hpTextCenter, spec, text.healthCenterFontSize or (spec and spec.healthFontSize), "health") == false then fontsReady = false end
  if SetFont(frame.hpTextRight, spec, hpRightSize or (spec and spec.healthFontSize), "health") == false then fontsReady = false end
  if SetFont(frame.powerTextLeft, spec, text.powerLeftFontSize or (spec and spec.powerFontSize), "power") == false then fontsReady = false end
  if SetFont(frame.powerTextCenter, spec, text.powerCenterFontSize or (spec and spec.powerFontSize), "power") == false then fontsReady = false end
  if SetFont(frame.powerTextRight, spec, text.powerRightFontSize or (spec and spec.powerFontSize), "power") == false then fontsReady = false end
  frame._msufTextFontPending = fontsReady and nil or true
  frame._msufNameTextR, frame._msufNameTextG, frame._msufNameTextB, frame._msufNameTextA = nil, nil, nil, nil
  frame._msufLastNameRaw, frame._msufLastNameText, frame._msufLastNameShortenStamp = nil, nil, nil
  frame._msufPowerTextColorInitialized = nil
  frame._msufPowerTextColorType = nil
  frame._msufPowerTextColorToken = nil
  frame._msufPowerTextR, frame._msufPowerTextG, frame._msufPowerTextB, frame._msufPowerTextA = nil, nil, nil, nil
  frame._msufHealthTextR, frame._msufHealthTextG, frame._msufHealthTextB, frame._msufHealthTextA = nil, nil, nil, nil
  local power = spec and spec.power or {}
  local hasPowerText = frame.powerTextLeft or frame.powerTextCenter or frame.powerTextRight
  local detachedPowerText = hasPowerText and power.enabled == true and power.detached == true and power.textOnDetached == true and frame.targetPowerBar
  local barAnchoredText = text.anchorToBars == true
  local directText = text.directLayout == true
  if detachedPowerText then
    local detachedTextLayer = ClampFrameLayer(tonumber(text.powerLayer) or 2, 2)
    local overlay = EnsureTextOverlay(frame, "MSUFPowerTextLayer", detachedTextLayer, 2)
    local baseLevel = frame.GetFrameLevel and (frame:GetFrameLevel() or 0) or GetLayerBaseLevel(frame)
    SetFrameLevelCached(overlay, (Layers.TextLevel and Layers.TextLevel(baseLevel, detachedTextLayer, 2)) or (baseLevel + 10 + detachedTextLayer))
  end

  RestoreNameParent(frame)
  if directText then
    LayoutDirectText(frame.nameText, text, "directName", "CENTER", "CENTER", 0, 0, "CENTER")
  elseif barAnchoredText then
    LayoutBarAnchoredName(frame, text)
  else
    LayoutName(frame.nameText, spec, text)
  end
  if directText then
    ClearNameClip(frame)
  else
    ApplyNameClip(frame, spec, text)
    -- The clip window and its side/center verdict only exist after
    -- ApplyNameClip; re-run the proxy so name-relative status text anchors to
    -- the glyph edge inside the freshly laid-out window.
    if frame._msufNameRelativeStatus == true then
      EnsureNameAnchorProxy(frame, spec)
    end
  end
  -- Re-anchoring a FontString can invalidate its rendered glyph geometry even
  -- when the text itself is unchanged. Force the next cold runtime name update
  -- to restamp both the visible name and its secret-safe anchor proxy.
  InvalidateCachedText(frame.nameText)
  if frame._msufNameAnchorTextActive == true then
    InvalidateCachedText(frame._msufNameAnchorText)
  end
  if inlineEnabled then
    frame._msufInlineAnchorDynamic = frame.nameText and frame.nameText._msufJustifyH == "LEFT" and text.nameShorten ~= true and true or nil
    if frame._msufInlineAnchorDynamic then
      AnchorInlineToName(frame)
    elseif AnchorInlineToNameClip(frame) then
    else
      LayoutText(frame.totInlineSep, "LEFT", "RIGHT", 4, 0, "LEFT", frame._msufNameInlineAnchor or frame.nameText)
    end
    LayoutText(frame.totInlineText, "LEFT", "RIGHT", 4, 0, "LEFT", frame.totInlineSep)
    ApplyInlineNameClip(frame, spec, text)
    SetTextLayer(frame.totInlineSep, text.nameLayer)
    SetTextLayer(frame.totInlineText, text.nameLayer)
    frame.totInlineSep:SetTextColor(0.72, 0.76, 0.84, 1)
  else
    frame._msufInlineAnchorDynamic = nil
    HideDots(frame._msufInlineDotsFS)
  end
  if directText and detachedPowerText then
    LayoutDirectText(frame.hpTextLeft, text, hpLeftDirect, "LEFT", "LEFT", 4, 0, "LEFT")
    LayoutDirectText(frame.hpTextCenter, text, "directHealthCenter", "CENTER", "CENTER", 0, 0, "CENTER")
    LayoutDirectText(frame.hpTextRight, text, hpRightDirect, "RIGHT", "RIGHT", -4, 0, "RIGHT")
    LayoutText(frame.powerTextLeft, "LEFT", "LEFT", 4 + (text.powerLeftX or 0), text.powerLeftY or 0, "LEFT", frame.targetPowerBar)
    LayoutText(frame.powerTextCenter, "CENTER", "CENTER", text.powerCenterX or 0, text.powerCenterY or 0, "CENTER", frame.targetPowerBar)
    LayoutText(frame.powerTextRight, "RIGHT", "RIGHT", -4 + (text.powerRightX or 0), text.powerRightY or 0, "RIGHT", frame.targetPowerBar)
  elseif directText then
    LayoutDirectText(frame.hpTextLeft, text, hpLeftDirect, "LEFT", "LEFT", 4, 0, "LEFT")
    LayoutDirectText(frame.hpTextCenter, text, "directHealthCenter", "CENTER", "CENTER", 0, 0, "CENTER")
    LayoutDirectText(frame.hpTextRight, text, hpRightDirect, "RIGHT", "RIGHT", -4, 0, "RIGHT")
    LayoutDirectText(frame.powerTextLeft, text, "directPowerLeft", "LEFT", "LEFT", 4, 0, "LEFT")
    LayoutDirectText(frame.powerTextCenter, text, "directPowerCenter", "CENTER", "CENTER", 0, 0, "CENTER")
    LayoutDirectText(frame.powerTextRight, text, "directPowerRight", "RIGHT", "RIGHT", -4, 0, "RIGHT")
  elseif barAnchoredText then
    local health = BarTextHealthAnchor(frame)
    local powerAnchor = BarTextPowerAnchor(frame, power)
    LayoutText(frame.hpTextLeft, "LEFT", "LEFT", 3 + (hpLeftX or 0), hpLeftY or 0, "LEFT", health)
    LayoutTextSpan(frame.hpTextCenter, health, 3 + (text.healthCenterX or 0), -3 + (text.healthCenterX or 0), text.healthCenterY or 0, "CENTER")
    LayoutText(frame.hpTextRight, "RIGHT", "RIGHT", -3 + (hpRightX or 0), hpRightY or 0, "RIGHT", health)
    LayoutText(frame.powerTextLeft, "LEFT", "LEFT", 2 + (text.powerLeftX or 0), text.powerLeftY or 0, "LEFT", powerAnchor)
    LayoutText(frame.powerTextCenter, "CENTER", "CENTER", text.powerCenterX or 0, text.powerCenterY or 0, "CENTER", powerAnchor)
    LayoutText(frame.powerTextRight, "RIGHT", "RIGHT", -2 + (text.powerRightX or 0), text.powerRightY or 0, "RIGHT", powerAnchor)
  elseif detachedPowerText then
    LayoutText(frame.hpTextLeft, "TOPLEFT", "TOPLEFT", 4 + (hpLeftX or 0), hpLeftY or 0, "LEFT")
    LayoutText(frame.hpTextCenter, "TOP", "TOP", text.healthCenterX or 0, text.healthCenterY or 0, "CENTER")
    LayoutText(frame.hpTextRight, "TOPRIGHT", "TOPRIGHT", -4 + (hpRightX or 0), hpRightY or 0, "RIGHT")
    LayoutText(frame.powerTextLeft, "LEFT", "LEFT", 4 + (text.powerLeftX or 0), text.powerLeftY or 0, "LEFT", frame.targetPowerBar)
    LayoutText(frame.powerTextCenter, "CENTER", "CENTER", text.powerCenterX or 0, text.powerCenterY or 0, "CENTER", frame.targetPowerBar)
    LayoutText(frame.powerTextRight, "RIGHT", "RIGHT", -4 + (text.powerRightX or 0), text.powerRightY or 0, "RIGHT", frame.targetPowerBar)
  else
    LayoutText(frame.hpTextLeft, "TOPLEFT", "TOPLEFT", 4 + (hpLeftX or 0), hpLeftY or 0, "LEFT")
    LayoutText(frame.hpTextCenter, "TOP", "TOP", text.healthCenterX or 0, text.healthCenterY or 0, "CENTER")
    LayoutText(frame.hpTextRight, "TOPRIGHT", "TOPRIGHT", -4 + (hpRightX or 0), hpRightY or 0, "RIGHT")
    LayoutText(frame.powerTextLeft, "BOTTOMLEFT", "BOTTOMLEFT", 4 + (text.powerLeftX or 0), text.powerLeftY or 0, "LEFT")
    LayoutText(frame.powerTextCenter, "BOTTOM", "BOTTOM", text.powerCenterX or 0, text.powerCenterY or 0, "CENTER")
    LayoutText(frame.powerTextRight, "BOTTOMRIGHT", "BOTTOMRIGHT", -4 + (text.powerRightX or 0), text.powerRightY or 0, "RIGHT")
  end
  SetTextLayer(frame.hpTextLeft, text.healthLayer)
  SetTextLayer(frame.hpTextCenter, text.healthLayer)
  SetTextLayer(frame.hpTextRight, text.healthLayer)
  SetTextLayer(frame.powerTextLeft, text.powerLayer)
  SetTextLayer(frame.powerTextCenter, text.powerLayer)
  SetTextLayer(frame.powerTextRight, text.powerLayer)
  if directText then
    if text.healthColorByHealth ~= true and text.healthColorByClass ~= true then
      local hpLeftDirectColor, hpRightDirectColor = HealthSlotDirectColors(text)
      ApplyTextColor(frame.hpTextLeft, hpLeftDirectColor)
      ApplyTextColor(frame.hpTextCenter, text.directHealthCenterColor)
      ApplyTextColor(frame.hpTextRight, hpRightDirectColor)
    end
    if text.powerColorByType ~= true then
      ApplyTextColor(frame.powerTextLeft, text.directPowerLeftColor)
      ApplyTextColor(frame.powerTextCenter, text.directPowerCenterColor)
      ApplyTextColor(frame.powerTextRight, text.directPowerRightColor)
    end
  end

  if frame.nameText then
    frame.nameText._msufShown = nil
  end
  SetShownCached(frame.nameText, showName)
  if not showName then
    HideDots(frame._msufNameDotsFS)
  end
  SetShownCached(frame.totInlineSep, inlineEnabled and showName)
  SetShownCached(frame.totInlineText, inlineEnabled and showName)
  if not (inlineEnabled and showName) then
    HideDots(frame._msufInlineDotsFS)
  end
  local showHealth = spec and spec.showHealthText ~= false
  local showPower = spec and spec.showPowerText ~= false and not augPowerReplacement
  local healthLeft, healthCenter, healthRight = ResolveHealthTextModes(text)
  SetTextSlotShown(frame.hpTextLeft, showHealth, healthLeft)
  SetTextSlotShown(frame.hpTextCenter, showHealth, healthCenter)
  SetTextSlotShown(frame.hpTextRight, showHealth, healthRight)
  SetTextSlotShown(frame.powerTextLeft, showPower, text.powerLeft)
  SetTextSlotShown(frame.powerTextCenter, showPower, text.powerCenter)
  SetTextSlotShown(frame.powerTextRight, showPower, text.powerRight)
  frame._msufPowerTextColorInitialized = nil
  frame._msufPowerTextColorType = nil
  frame._msufPowerTextColorToken = nil
  frame._msufHealthTextR, frame._msufHealthTextG, frame._msufHealthTextB, frame._msufHealthTextA = nil, nil, nil, nil
  local rt = CompileTextRuntime(frame, spec, text)
  -- Single-frame percent-path promotion: now that healthDispatchKeyMode is known,
  -- let Health switch a percent-eligible single frame (no absolute-HP text, no
  -- prediction) to Health.UpdateValuePercent so its health ticks skip the
  -- UnitHealth/Max/Store work. Group frames get this from the group adapter's
  -- apply/rebind path, so only drive it here for non-group frames.
  if frame._msufIsGroupFrame ~= true then
    local healthElement = UF and UF.elements and UF.elements.Health
    if healthElement and healthElement.SelectGroupHealthUpdater then
      healthElement.SelectGroupHealthUpdater(frame)
    end
  end
  if UpdateHealthTextColor then
    UpdateHealthTextColor(frame, rt, frame.MSUFUnitKey)
  end
  if frame.nameText then
    ApplyNameTextColor(frame, frame.MSUFUnitKey)
  end
  if frame._msufNameRelativeStatus == true and RefreshNameRelativeStatusAnchors then
    RefreshNameRelativeStatusAnchors(frame)
  end
  frame._msufTextApplySignature = signature
  frame._msufTextLayoutRevision = layoutRevision
  frame._msufTextAugPowerReplacement = augPowerReplacement
  frame._msufTextColorRevision = spec and spec._msufTextColorRevision
  frame._msufTextFontAttemptEpoch = fontEpoch
  frame._msufTextFontEpoch = fontsReady and fontEpoch or nil
end
