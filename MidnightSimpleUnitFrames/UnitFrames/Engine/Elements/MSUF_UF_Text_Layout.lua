local _, MSUF = ...
local Text = MSUF and MSUF.UFText
if not Text then return end

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
local SetFrameLevelCached = Text.SetFrameLevelCached
local SetShownCached = Text.SetShownCached
local SetFont = Text.SetFont
local SetNameTextColor = Text.SetNameTextColor
local NameTextColor = Text.NameTextColor
local ResolveHealthTextModes = Text.ResolveHealthTextModes
local CompileTextRuntime = Text.CompileTextRuntime
local UpdateHealthTextColor = Text.UpdateHealthTextColor
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

local function LayoutTextSpan(fs, relativeTo, leftX, rightX, y, justify)
  if not (fs and relativeTo) then
    return
  end
  leftX, rightX, y = tonumber(leftX) or 0, tonumber(rightX) or 0, tonumber(y) or 0
  if fs._msufPoint ~= "SPAN"
    or fs._msufRelativeTo ~= relativeTo
    or fs._msufLeftX ~= leftX
    or fs._msufRightX ~= rightX
    or fs._msufY ~= y then
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", relativeTo, "LEFT", leftX, y)
    fs:SetPoint("RIGHT", relativeTo, "RIGHT", rightX, y)
    fs._msufPoint, fs._msufRelPoint, fs._msufRelativeTo = "SPAN", nil, relativeTo
    fs._msufLeftX, fs._msufRightX, fs._msufX, fs._msufY = leftX, rightX, nil, y
  end
  if fs._msufJustifyH ~= justify then
    fs:SetJustifyH(justify)
    fs._msufJustifyH = justify
  end
end

local function LayoutName(fs, spec, text)
  if not fs then
    return
  end
  local anchor = text and text.nameAnchor or "LEFT"
  local x = tonumber(text and text.nameX) or 4
  local y = tonumber(text and text.nameY) or -4
  if anchor == "RIGHT" then
    LayoutText(fs, "TOPRIGHT", "TOPRIGHT", -x, y, "RIGHT")
  elseif anchor == "CENTER" then
    LayoutText(fs, "TOP", "TOP", x, y, "CENTER")
  else
    LayoutText(fs, "TOPLEFT", "TOPLEFT", x, y, "LEFT")
  end
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
  local health = BarTextHealthAnchor(frame)
  local anchor = text and text.nameAnchor or "LEFT"
  local x = tonumber(text and text.nameX) or 0
  local y = tonumber(text and text.nameY) or 0
  if anchor == "CENTER" then
    LayoutTextSpan(fs, health, 3 + x, -3 + x, y, "CENTER")
  elseif anchor == "RIGHT" then
    LayoutTextSpan(fs, health, 3 + x, -3 + x, y, "RIGHT")
  else
    LayoutTextSpan(fs, health, 3 + x, -3, y, "LEFT")
  end
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
    local level = GetLayerBaseLevel(frame) + ClampFrameLayer(layer, 5)
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
  local anchor = text and text.nameAnchor or "LEFT"
  local x = tonumber(text and text.nameX) or 4
  local y = tonumber(text and text.nameY) or -4
  local parent = clip:GetParent()
  local point, relPoint
  if anchor == "RIGHT" then
    point, relPoint, x = "TOPRIGHT", "TOPRIGHT", -x
  elseif anchor == "CENTER" then
    point, relPoint = "TOP", "TOP"
  else
    point, relPoint = "TOPLEFT", "TOPLEFT"
  end
  if clip._msufPoint ~= point or clip._msufRelPoint ~= relPoint or clip._msufX ~= x or clip._msufY ~= y then
    clip:ClearAllPoints()
    clip:SetPoint(point, parent, relPoint, x, y)
    clip._msufPoint, clip._msufRelPoint, clip._msufX, clip._msufY = point, relPoint, x, y
  end
  clip:Show()
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
  local point = side == "LEFT" and "TOPRIGHT" or "TOPLEFT"
  local justify = side == "LEFT" and "RIGHT" or "LEFT"
  if fs._msufPoint ~= point or fs._msufRelPoint ~= point or fs._msufRelativeTo ~= clip then
    fs:ClearAllPoints()
    fs:SetPoint(point, clip, point, 0, 0)
    fs._msufPoint, fs._msufRelPoint, fs._msufRelativeTo, fs._msufX, fs._msufY = point, point, clip, 0, 0
  end
  if fs._msufJustifyH ~= justify then
    fs:SetJustifyH(justify)
    fs._msufJustifyH = justify
  end
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

  fs:SetWordWrap(false)
  if fs.SetNonSpaceWrap then
    fs:SetNonSpaceWrap(false)
  end

  local frameWidth = tonumber(spec and spec.width) or (frame.GetWidth and frame:GetWidth()) or 220
  if frameWidth <= 0 then frameWidth = 220 end
  local nameWidth = floor(frameWidth * 0.80 + 0.5)
  if nameWidth < 80 then nameWidth = 80 end

  local maxChars = text and text.nameShorten == true and tonumber(text.nameShortenMax) or 0
  local shorten = maxChars and maxChars > 0
  if shorten then
    local approx = ApproxNameWidth(fs, maxChars)
    if approx > 0 then
      local w = floor(approx + 0.5)
      if w < nameWidth then
        nameWidth = w
        if nameWidth < 40 then nameWidth = 40 end
      end
    end
  end

  local clipSide = text.nameShortenSide == "RIGHT" and "RIGHT" or "LEFT"
  local anchor = text.nameAnchor or "LEFT"
  local justify = (anchor == "RIGHT" and "RIGHT") or (anchor == "CENTER" and "CENTER") or "LEFT"
  if shorten and anchor == "LEFT" then
    justify = clipSide == "LEFT" and "RIGHT" or "LEFT"
  end

  if shorten and text.nameShortenDots ~= true and ApplyNoEllipsisClip(frame, fs, spec, text, nameWidth, clipSide) then
    return
  end

  if fs._msufJustifyH ~= justify then
    fs:SetJustifyH(justify)
    fs._msufJustifyH = justify
  end
  if fs._msufNameClipTextWidth ~= nameWidth then
    fs:SetWidth(nameWidth)
    fs._msufNameClipTextWidth = nameWidth
  end
  fs._msufShown = nil

  if shorten and text.nameShortenDots == true then
    local dots = EnsureDotsFS(frame, "_msufNameDotsFS", "GameFontNormal", text.nameLayer)
    SetFont(dots, spec, spec and spec.nameFontSize)
    LayoutDots(dots, fs, clipSide)
  else
    HideDots(frame._msufNameDotsFS)
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
    SetFont(dots, spec, spec and spec.nameFontSize)
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
    local level = GetLayerBaseLevel(frame) + ClampFrameLayer(layer, fallback)
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
  if fs and fs.GetParent and fs:GetParent() ~= overlay then
    if fs.SetParent then
      fs:SetParent(overlay)
      fs:ClearAllPoints()
      fs._msufPoint, fs._msufRelPoint, fs._msufRelativeTo, fs._msufX, fs._msufY = nil, nil, nil, nil, nil
    else
      fs:Hide()
      fs:SetText("")
      fs = nil
    end
  end
  if not fs then
    fs = overlay:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
    if fs.SetWordWrap then
      fs:SetWordWrap(false)
    end
    frame[key] = fs
  end
  return fs
end

function Text.GetEvents()
  return EMPTY_EVENTS
end

function Text.GetUnitlessEvents()
  return EMPTY_EVENTS
end

function Text.Create(frame, spec)
  local text = spec and spec.text or {}
  frame.nameText = EnsureFontString(frame, "nameText", "GameFontNormal", text.nameLayer, 5, "MSUFNameTextLayer")
  frame.hpTextLeft = EnsureFontString(frame, "hpTextLeft", "GameFontNormalSmall", text.healthLayer, 5, "MSUFHealthTextLayer")
  frame.hpTextCenter = EnsureFontString(frame, "hpTextCenter", "GameFontNormalSmall", text.healthLayer, 5, "MSUFHealthTextLayer")
  frame.hpTextRight = EnsureFontString(frame, "hpTextRight", "GameFontNormalSmall", text.healthLayer, 5, "MSUFHealthTextLayer")
  frame.hpText = frame.hpTextRight
  frame.powerTextLeft = EnsureFontString(frame, "powerTextLeft", "GameFontNormalSmall", text.powerLayer, 2, "MSUFPowerTextLayer")
  frame.powerTextCenter = EnsureFontString(frame, "powerTextCenter", "GameFontNormalSmall", text.powerLayer, 2, "MSUFPowerTextLayer")
  frame.powerTextRight = EnsureFontString(frame, "powerTextRight", "GameFontNormalSmall", text.powerLayer, 2, "MSUFPowerTextLayer")
  frame.powerText = frame.powerTextRight
end

local SIG_SPEC_KEYS = { "key", "scope", "width", "height", "font", "fontFlags", "nameFontSize", "healthFontSize", "powerFontSize", "fontShadow", "fontShadowAlpha", "fontShadowX", "fontShadowY", "_msufGFCompileSerial" }
local SIG_POWER_KEYS = { "enabled", "detached", "textOnDetached", "shape", "detachedLevel", "detachedHeight", "detachedWidth", "detachedX", "detachedY", "detachedSyncClass", "detachedAnchorClass", "detachedClassWidth", "detachedWidthFrameName", "detachedClassWidthFrameName" }
local SIG_TEXT_KEYS = {
  "anchorToBars", "nameAnchor", "nameX", "nameY", "nameLayer", "nameShorten", "nameShortenSide", "nameShortenDots", "nameShortenMax", "nameShortenWidth", "nameLeftWidth",
  "directLayout", "directNamePoint", "directNameRelativePoint", "directNameX", "directNameY",
  "healthLayer", "healthLeft", "healthCenter", "healthRight", "healthDelimiter", "healthColorByHealth", "healthThrottle", "healthLeftX", "healthLeftY", "healthCenterX", "healthCenterY", "healthRightX", "healthRightY",
  "directHealthLeftPoint", "directHealthLeftRelativePoint", "directHealthLeftX", "directHealthLeftY", "directHealthCenterPoint", "directHealthCenterRelativePoint", "directHealthCenterX", "directHealthCenterY", "directHealthRightPoint", "directHealthRightRelativePoint", "directHealthRightX", "directHealthRightY",
  "powerLayer", "powerLeft", "powerCenter", "powerRight", "powerDelimiter", "powerColorByType", "powerThrottle", "powerLeftX", "powerLeftY", "powerCenterX", "powerCenterY", "powerRightX", "powerRightY",
  "directPowerLeftPoint", "directPowerLeftRelativePoint", "directPowerLeftX", "directPowerLeftY", "directPowerCenterPoint", "directPowerCenterRelativePoint", "directPowerCenterX", "directPowerCenterY", "directPowerRightPoint", "directPowerRightRelativePoint", "directPowerRightX", "directPowerRightY",
  "shortNumbers", "hidePercentSymbol", "hideNameOnDeadOffline",
}
local SIG_TEXT_COLOR_KEYS = { "nameColor", "directNameColor", "directHealthLeftColor", "directHealthCenterColor", "directHealthRightColor", "directPowerLeftColor", "directPowerCenterColor", "directPowerRightColor" }
local SIG_INLINE_KEYS = { "enabled", "separator", "unit", "colorMode", "targetNameClassColor", "targetNameNpcColor", "totNameClassColor", "totNameNpcColor", "nameShorten", "nameShortenSide", "nameShortenDots", "nameShortenMax", "nameShortenWidth" }
local SIG_PARTS = {}

local function SigAddKeys(parts, n, src, keys)
  for i = 1, #keys do
    n = n + 1
    parts[n] = tostring(src and src[keys[i]])
  end
  return n
end

local function SigAddColor(parts, n, color)
  n = n + 1
  if type(color) == "table" then
    parts[n] = tostring(color.r or color[1]) .. ":" .. tostring(color.g or color[2]) .. ":" .. tostring(color.b or color[3]) .. ":" .. tostring(color.a or color[4] or 1)
  else
    parts[n] = ""
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
  n = SigAddColor(parts, n, spec and spec.textColor)
  n = SigAddKeys(parts, n, power, SIG_POWER_KEYS)
  n = SigAddKeys(parts, n, text, SIG_TEXT_KEYS)
  for i = 1, #SIG_TEXT_COLOR_KEYS do
    n = SigAddColor(parts, n, text and text[SIG_TEXT_COLOR_KEYS[i]])
  end
  n = SigAddKeys(parts, n, inline, SIG_INLINE_KEYS)
  for i = n + 1, #parts do
    parts[i] = nil
  end
  return concat(parts, "\031", 1, n)
end

function Text.Apply(frame, spec)
  local text = spec and spec.text or {}
  local signature = TextApplySignature(spec, text)
  if frame._msufTextApplySignature == signature
    and frame.nameText
    and frame.hpTextLeft
    and frame.hpTextCenter
    and frame.hpTextRight
    and frame.powerTextLeft
    and frame.powerTextCenter
    and frame.powerTextRight then
    local rt = frame._msufTextRuntime
    if UpdateHealthTextColor then
      UpdateHealthTextColor(frame, rt, frame.unit)
    end
    if frame.nameText then
      SetNameTextColor(frame, NameTextColor(frame, frame.unit))
    end
    return
  end
  Text.Create(frame, spec)
  local inlineEnabled = spec and spec.key == "target" and text.inlineToT and text.inlineToT.enabled == true
  if inlineEnabled then
    frame.totInlineSep = EnsureFontString(frame, "totInlineSep", "GameFontNormal", text.nameLayer, 5, "MSUFNameTextLayer")
    frame.totInlineText = EnsureFontString(frame, "totInlineText", "GameFontNormal", text.nameLayer, 5, "MSUFNameTextLayer")
  elseif frame.totInlineSep or frame.totInlineText then
    SetShownCached(frame.totInlineSep, false)
    SetShownCached(frame.totInlineText, false)
    HideDots(frame._msufInlineDotsFS)
    frame._msufInlineRaw, frame._msufInlineText, frame._msufInlineStamp = nil, nil, nil
  end
  SetFont(frame.nameText, spec, spec and spec.nameFontSize)
  if inlineEnabled then
    SetFont(frame.totInlineSep, spec, spec and spec.nameFontSize)
    SetFont(frame.totInlineText, spec, spec and spec.nameFontSize)
  end
  SetFont(frame.hpTextLeft, spec, spec and spec.healthFontSize)
  SetFont(frame.hpTextCenter, spec, spec and spec.healthFontSize)
  SetFont(frame.hpTextRight, spec, spec and spec.healthFontSize)
  SetFont(frame.powerTextLeft, spec, spec and spec.powerFontSize)
  SetFont(frame.powerTextCenter, spec, spec and spec.powerFontSize)
  SetFont(frame.powerTextRight, spec, spec and spec.powerFontSize)
  frame._msufNameTextR, frame._msufNameTextG, frame._msufNameTextB, frame._msufNameTextA = nil, nil, nil, nil
  frame._msufLastNameRaw, frame._msufLastNameText, frame._msufLastNameShortenStamp = nil, nil, nil
  frame._msufPowerTextColorInitialized = nil
  frame._msufPowerTextColorType = nil
  frame._msufPowerTextColorToken = nil
  frame._msufPowerTextR, frame._msufPowerTextG, frame._msufPowerTextB, frame._msufPowerTextA = nil, nil, nil, nil
  frame._msufHealthTextR, frame._msufHealthTextG, frame._msufHealthTextB, frame._msufHealthTextA = nil, nil, nil, nil
  local power = spec and spec.power or {}
  local detachedPowerText = power.enabled == true and power.detached == true and power.textOnDetached == true and frame.targetPowerBar
  local barAnchoredText = text.anchorToBars == true
  local directText = text.directLayout == true
  if detachedPowerText then
    local detachedTextLayer = max(tonumber(text.powerLayer) or 2, (tonumber(power.detachedLevel) or 6) + 1)
    local overlay = EnsureTextOverlay(frame, "MSUFPowerTextLayer", detachedTextLayer, 2)
    local baseLevel = frame.GetFrameLevel and (frame:GetFrameLevel() or 0) or GetLayerBaseLevel(frame)
    SetFrameLevelCached(overlay, baseLevel + detachedTextLayer)
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
  if directText then
    LayoutDirectText(frame.hpTextLeft, text, "directHealthLeft", "LEFT", "LEFT", 4, 0, "LEFT")
    LayoutDirectText(frame.hpTextCenter, text, "directHealthCenter", "CENTER", "CENTER", 0, 0, "CENTER")
    LayoutDirectText(frame.hpTextRight, text, "directHealthRight", "RIGHT", "RIGHT", -4, 0, "RIGHT")
    LayoutDirectText(frame.powerTextLeft, text, "directPowerLeft", "LEFT", "LEFT", 4, 0, "LEFT")
    LayoutDirectText(frame.powerTextCenter, text, "directPowerCenter", "CENTER", "CENTER", 0, 0, "CENTER")
    LayoutDirectText(frame.powerTextRight, text, "directPowerRight", "RIGHT", "RIGHT", -4, 0, "RIGHT")
  elseif barAnchoredText then
    local health = BarTextHealthAnchor(frame)
    local powerAnchor = BarTextPowerAnchor(frame, power)
    LayoutText(frame.hpTextLeft, "LEFT", "LEFT", 3 + (text.healthLeftX or 0), text.healthLeftY or 0, "LEFT", health)
    LayoutTextSpan(frame.hpTextCenter, health, 3 + (text.healthCenterX or 0), -3 + (text.healthCenterX or 0), text.healthCenterY or 0, "CENTER")
    LayoutText(frame.hpTextRight, "RIGHT", "RIGHT", -3 + (text.healthRightX or 0), text.healthRightY or 0, "RIGHT", health)
    LayoutText(frame.powerTextLeft, "LEFT", "LEFT", 2 + (text.powerLeftX or 0), text.powerLeftY or 0, "LEFT", powerAnchor)
    LayoutText(frame.powerTextCenter, "CENTER", "CENTER", text.powerCenterX or 0, text.powerCenterY or 0, "CENTER", powerAnchor)
    LayoutText(frame.powerTextRight, "RIGHT", "RIGHT", -2 + (text.powerRightX or 0), text.powerRightY or 0, "RIGHT", powerAnchor)
  elseif detachedPowerText then
    LayoutText(frame.hpTextLeft, "LEFT", "LEFT", 4 + (text.healthLeftX or 0), text.healthLeftY or 0, "LEFT")
    LayoutText(frame.hpTextCenter, "CENTER", "CENTER", text.healthCenterX or 0, text.healthCenterY or 0, "CENTER")
    LayoutText(frame.hpTextRight, "RIGHT", "RIGHT", -4 + (text.healthRightX or 0), text.healthRightY or 0, "RIGHT")
    LayoutText(frame.powerTextLeft, "LEFT", "LEFT", 4 + (text.powerLeftX or 0), text.powerLeftY or 0, "LEFT", frame.targetPowerBar)
    LayoutText(frame.powerTextCenter, "CENTER", "CENTER", text.powerCenterX or 0, text.powerCenterY or 0, "CENTER", frame.targetPowerBar)
    LayoutText(frame.powerTextRight, "RIGHT", "RIGHT", -4 + (text.powerRightX or 0), text.powerRightY or 0, "RIGHT", frame.targetPowerBar)
  else
    LayoutText(frame.hpTextLeft, "LEFT", "LEFT", 4 + (text.healthLeftX or 0), text.healthLeftY or 0, "LEFT")
    LayoutText(frame.hpTextCenter, "CENTER", "CENTER", text.healthCenterX or 0, text.healthCenterY or 0, "CENTER")
    LayoutText(frame.hpTextRight, "RIGHT", "RIGHT", -4 + (text.healthRightX or 0), text.healthRightY or 0, "RIGHT")
    LayoutText(frame.powerTextLeft, "BOTTOMLEFT", "BOTTOMLEFT", 4 + (text.powerLeftX or 0), 1 + (text.powerLeftY or 0), "LEFT")
    LayoutText(frame.powerTextCenter, "BOTTOM", "BOTTOM", text.powerCenterX or 0, 1 + (text.powerCenterY or 0), "CENTER")
    LayoutText(frame.powerTextRight, "BOTTOMRIGHT", "BOTTOMRIGHT", -4 + (text.powerRightX or 0), 1 + (text.powerRightY or 0), "RIGHT")
  end
  SetTextLayer(frame.hpTextLeft, text.healthLayer)
  SetTextLayer(frame.hpTextCenter, text.healthLayer)
  SetTextLayer(frame.hpTextRight, text.healthLayer)
  SetTextLayer(frame.powerTextLeft, text.powerLayer)
  SetTextLayer(frame.powerTextCenter, text.powerLayer)
  SetTextLayer(frame.powerTextRight, text.powerLayer)
  if directText then
    if text.healthColorByHealth ~= true then
      ApplyTextColor(frame.hpTextLeft, text.directHealthLeftColor)
      ApplyTextColor(frame.hpTextCenter, text.directHealthCenterColor)
      ApplyTextColor(frame.hpTextRight, text.directHealthRightColor)
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
  local showName = spec and spec.showName ~= false
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
  local showPower = spec and spec.showPowerText ~= false
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
  if UpdateHealthTextColor then
    UpdateHealthTextColor(frame, rt, frame.unit)
  end
  if frame.nameText then
    SetNameTextColor(frame, NameTextColor(frame, frame.unit))
  end
  frame._msufTextApplySignature = signature
end
