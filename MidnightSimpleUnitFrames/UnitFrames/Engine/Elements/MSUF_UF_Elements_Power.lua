local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}

local C = MSUF.UFBarTextCommon
local UF = C and C.UF or MSUF.UF
if not UF then return end

local CreateFrame = C and C.CreateFrame or CreateFrame
local UnitPower = C and C.UnitPower or UnitPower
local UnitPowerMax = C and C.UnitPowerMax or UnitPowerMax
local UnitPowerType = C and C.UnitPowerType or UnitPowerType
local UnitPowerPercent = C and C.UnitPowerPercent or UnitPowerPercent
local PowerBarColor = C and C.PowerBarColor or PowerBarColor
local ResolvePowerColor = C and C.PowerColor
local WHITE = C and C.WHITE or "Interface\\Buttons\\WHITE8X8"
local SCALE_100 = C and C.SCALE_100
local SetBarSmoothing = C and C.SetBarSmoothing
local tonumber = tonumber
local tostring = tostring
local type = type
local math_floor = math.floor
local math_max = math.max
local issecretvalue = _G.issecretvalue or function(_) return false end

local Power = {}
local EVENTS = { "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }
local POWER_SHAPE_MEDIA = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\ClassPower\\"
local DETACHED_SHAPE_TEXTURES = {
  ROUND = {
    fill = POWER_SHAPE_MEDIA .. "power_round_fill.tga",
    bg = POWER_SHAPE_MEDIA .. "power_round_bg.tga",
    edge = POWER_SHAPE_MEDIA .. "power_round_edge.tga",
  },
  CRYSTAL = {
    fill = POWER_SHAPE_MEDIA .. "power_crystal_fill.tga",
    bg = POWER_SHAPE_MEDIA .. "power_crystal_bg.tga",
    edge = POWER_SHAPE_MEDIA .. "power_crystal_edge.tga",
  },
  ORB = {
    fill = POWER_SHAPE_MEDIA .. "pip_circle_fill.tga",
    bg = POWER_SHAPE_MEDIA .. "pip_circle_bg.tga",
    edge = POWER_SHAPE_MEDIA .. "pip_circle_edge.tga",
    vertical = true,
  },
}
local IDENTITY_EVENTS = {
  MSUF_UNIT_IDENTITY = true,
  MSUF_UNIT_IDENTITY_FAST = true,
  MSUF_UNIT_IDENTITY_SOFT = true,
  MSUF_UNIT_IDENTITY_SOFT_FAST = true,
  MSUF_GF_UNIT_IDENTITY = true,
  MSUF_GF_UNIT_STRUCTURE = true,
}

local function IsFiniteNumber(value)
  return type(value) == "number" and value == value and (value - value) == 0
end

local function IsSecret(value)
  return issecretvalue(value) == true
end

local function ClearPowerValueCaches(bar)
  if not bar then return end
  bar._msufPowerValue = nil
  bar._msufPowerValueUnit = nil
  bar._msufPowerMax = nil
  bar._msufPowerMaxUnit = nil
  bar._msufPowerMaxReady = nil
end

local function SetPowerBarValue(bar, value, secret)
  if secret then
    bar:SetValue(value)
    bar._msufInterpolating = nil
    return
  end
  local interp = bar._msufSmoothInterp
  if interp then
    bar:SetValue(value, interp)
    bar._msufInterpolating = true
  else
    bar:SetValue(value)
  end
end

local function SpecPower(frame)
  return frame and frame.MSUFSpec and frame.MSUFSpec.power or nil
end

local function ResolveDynamicPowerColor(frame, unit, powerType, token, metaKnown)
  if ResolvePowerColor then
    local r, g, b = ResolvePowerColor(frame, unit, powerType, token, metaKnown)
    if IsFiniteNumber(r) and IsFiniteNumber(g) and IsFiniteNumber(b) then
      return r, g, b
    end
  end
  local power = SpecPower(frame)
  local override = power and power.colors and token ~= nil and power.colors[token] or nil
  if override then
    return override.r, override.g, override.b
  end
  local c = token ~= nil and PowerBarColor and PowerBarColor[token]
  if not c and powerType ~= nil then
    c = PowerBarColor and PowerBarColor[powerType]
  end
  if not c then
    c = PowerBarColor and PowerBarColor.MANA
  end
  return c and c.r or 0.2, c and c.g or 0.45, c and c.b or 1
end

local function ReadPowerTypeCached(frame, bar, unit, force)
  if not UnitPowerType then return nil, nil end
  if force ~= true and bar and bar._msufPowerTypeKnown == true and bar._msufPowerTypeUnit == unit then
    return bar._msufPowerType, bar._msufPowerToken
  end
  local powerType, token = UnitPowerType(unit)
  local typeSecret = issecretvalue(powerType) == true
  local tokenSecret = issecretvalue(token) == true
  if typeSecret then powerType = nil end
  if tokenSecret then token = nil end
  if typeSecret or tokenSecret then
    if bar then
      bar._msufPowerType = nil
      bar._msufPowerToken = nil
      bar._msufPowerTypeKnown = nil
      bar._msufPowerTypeUnit = nil
    end
    return nil, nil
  end
  if bar then
    bar._msufPowerType = powerType
    bar._msufPowerToken = token
    bar._msufPowerTypeKnown = true
    bar._msufPowerTypeUnit = unit
  end
  return powerType, token
end

local function BarShown(bar)
  if not bar then return false end
  if bar._msufShown == false then return false end
  if bar.IsShown and not bar:IsShown() then return false end
  return true
end

local function SetShown(frame, shown)
  local bar = frame and frame.targetPowerBar
  if not bar then return end
  if bar._msufShown == shown then return end
  bar._msufShown = shown
  if shown then bar:Show() else bar:Hide() end
  local bg = frame.powerBarBG
  if bg then if shown then bg:Show() else bg:Hide() end end
end

local function ShapeOutlineAlpha(value)
  value = tonumber(value) or 0
  if value <= 0 then return 0 end
  if value >= 8 then return 1 end
  return 0.49 + (value * 0.065)
end

local function NormalizeShape(shape)
  shape = tostring(shape or "BAR"):upper()
  if shape == "ROUND" or shape == "CRYSTAL" or shape == "ORB" then return shape end
  return "BAR"
end

local function Number(value, fallback)
  value = tonumber(value)
  if value ~= nil and value == value and (value - value) == 0 then return value end
  return fallback
end

local function RoundPositive(value, fallback)
  value = Number(value, fallback)
  if value < 1 then value = 1 end
  return math_floor(value + 0.5)
end

local function RoundNonNegative(value, fallback)
  value = Number(value, fallback)
  if value < 0 then value = 0 end
  return math_floor(value + 0.5)
end

local function FrameWidth(frame)
  if not (frame and frame.GetWidth) then return nil end
  local width = frame:GetWidth()
  if type(width) == "number" and width > 1 then return width end
  return nil
end

local function ResolveCooldownWidthFrame(name)
  if type(name) ~= "string" or name == "" then return nil end
  local resolver = _G.MSUF_GetEffectiveCooldownFrame
  local frame = type(resolver) == "function" and resolver(name) or nil
  return frame or _G[name]
end

local function ResolveDetachedWidth(frame, power)
  local width
  if power.detachedSyncClass == true then
    width = FrameWidth(_G.MSUF_ClassPowerContainer) or Number(power.detachedClassWidth, nil)
  end
  width = width or FrameWidth(ResolveCooldownWidthFrame(power.detachedWidthFrameName))
  width = width or Number(power.detachedWidth, nil)
  width = width or FrameWidth(frame)
  return RoundPositive(width, 1)
end

local function ResolveDetachedAnchor(power)
  local anchor = _G.MSUF_ClassPowerContainer
  if power.detachedAnchorClass == true and anchor and anchor.GetWidth and anchor:GetWidth() > 1 then
    return anchor, "TOP", "BOTTOM"
  end
  return nil, "TOP", "BOTTOM"
end

local function ApplyShapeMedia(frame, power, texture)
  local bar = frame and frame.targetPowerBar
  if not bar then return texture or WHITE end
  local shape = NormalizeShape(power and power.shape)
  local media = DETACHED_SHAPE_TEXTURES[shape]
  if media then
    if bar.SetOrientation then
      local orientation = media.vertical and "VERTICAL" or "HORIZONTAL"
      if bar._msufPowerOrientation ~= orientation then
        bar:SetOrientation(orientation)
        bar._msufPowerOrientation = orientation
      end
    end
    local bg = frame.powerBarBG
    if bg then
      if bg._msufTexture ~= media.bg then
        bg:SetTexture(media.bg)
        bg._msufTexture = media.bg
      end
      local ba = power.backgroundAlpha or frame.MSUFSpec and frame.MSUFSpec.backgroundAlpha or 0.72
      if bg._msufMode ~= "shape" or bg._msufA ~= ba then
        bg:SetVertexColor(1, 1, 1, ba)
        bg._msufMode = "shape"
        bg._msufA = ba
      end
    end
    local edge = bar._msufDetachedShapeEdge
    if not edge then
      edge = bar:CreateTexture(nil, "OVERLAY", nil, 1)
      bar._msufDetachedShapeEdge = edge
    end
    edge:ClearAllPoints()
    edge:SetAllPoints(bar)
    if edge._msufTexture ~= media.edge then
      edge:SetTexture(media.edge)
      edge._msufTexture = media.edge
    end
    local alpha = ShapeOutlineAlpha(power.detachedOutline)
    if edge._msufAlpha ~= alpha then
      edge:SetAlpha(alpha)
      edge._msufAlpha = alpha
    end
    if alpha > 0 then edge:Show() else edge:Hide() end
    return media.fill
  end

  if bar.SetOrientation and bar._msufPowerOrientation ~= "HORIZONTAL" then
    bar:SetOrientation("HORIZONTAL")
    bar._msufPowerOrientation = "HORIZONTAL"
  end
  local edge = bar._msufDetachedShapeEdge
  if edge then edge:Hide() end
  return texture or WHITE
end

local function ApplyBackgroundMedia(frame, power)
  local bg = frame and frame.powerBarBG
  if not bg then return end
  local texture = power and power.backgroundTexture
  local ba = power and power.backgroundAlpha or frame.MSUFSpec and frame.MSUFSpec.backgroundAlpha or 0.72
  local media = power and power.detached == true and DETACHED_SHAPE_TEXTURES[NormalizeShape(power.shape)]
  if media then
    if bg._msufTexture ~= media.bg then
      bg:SetTexture(media.bg)
      bg._msufTexture = media.bg
    end
    if bg._msufMode ~= "shape" or bg._msufA ~= ba then
      bg:SetVertexColor(1, 1, 1, ba)
      bg._msufMode = "shape"
      bg._msufA = ba
    end
    return
  end
  if type(texture) == "string" and texture ~= "" then
    if bg._msufTexture ~= texture then
      bg:SetTexture(texture)
      bg._msufTexture = texture
    end
    if bg._msufMode ~= "texture" or bg._msufA ~= ba then
      bg:SetVertexColor(0, 0, 0, ba)
      bg._msufMode = "texture"
      bg._msufA = ba
    end
  elseif bg._msufMode ~= "solid" or bg._msufA ~= ba then
    bg:SetColorTexture(0, 0, 0, ba)
    bg._msufTexture = nil
    bg._msufMode = "solid"
    bg._msufA = ba
  end
end

local function LayoutDetached(frame, bar, power, defaultHeight)
  local shape = NormalizeShape(power.shape)
  local size = shape ~= "BAR" and RoundPositive(power.orbSize, power.detachedHeight or defaultHeight or 6) or nil
  local width = size or ResolveDetachedWidth(frame, power)
  local height = size or RoundPositive(power.detachedHeight, defaultHeight or 6)
  local x = math_floor(Number(power.detachedX, 0) + 0.5)
  local y = math_floor(Number(power.detachedY, -4) + 0.5)
  local anchor, point, relativePoint = ResolveDetachedAnchor(power)

  bar:ClearAllPoints()
  bar:SetSize(math_max(1, width), math_max(1, height))
  if anchor then
    bar:SetPoint(point, anchor, relativePoint, x, y)
  else
    bar:SetPoint(point, frame, relativePoint, x, y)
  end
  if bar.SetFrameLevel and frame.GetFrameLevel then
    local level = (frame:GetFrameLevel() or 1) + RoundNonNegative(power.detachedLevel, 6)
    if bar._msufDetachedLevel ~= level then
      bar:SetFrameLevel(level)
      bar._msufDetachedLevel = level
    end
  end
  bar._msufDetached = true
end

local function SetColor(frame, force)
  local bar = frame and frame.targetPowerBar
  if not bar then return end
  local power = SpecPower(frame) or {}
  local mode = power.mode
  local r, g, b
  if mode == "dark" or mode == "unified" or mode == "static" then
    r, g, b = power.r, power.g, power.b
  end
  if not (IsFiniteNumber(r) and IsFiniteNumber(g) and IsFiniteNumber(b)) then
    local powerType, token
    local metaKnown = false
    if mode ~= "class" and UnitPowerType then
      powerType, token = ReadPowerTypeCached(frame, bar, frame.unit, true)
      metaKnown = powerType ~= nil or token ~= nil
    end
    r, g, b = ResolveDynamicPowerColor(frame, frame.unit, powerType, token, metaKnown)
  end
  local a = power.alpha or 1
  if force or bar._msufR ~= r or bar._msufG ~= g or bar._msufB ~= b or bar._msufA ~= a then
    bar:SetStatusBarColor(r, g, b, a)
    bar._msufR, bar._msufG, bar._msufB, bar._msufA = r, g, b, a
  end
end

function Power.IsEnabled(frame, spec)
  local power = spec and spec.power
  return power and power.enabled == true
end

function Power.GetEvents()
  return EVENTS
end

function Power.Disable(frame)
  SetShown(frame, false)
end

function Power.Create(frame, spec)
  if frame.targetPowerBar then return end
  local bar = CreateFrame("StatusBar", nil, frame)
  bar:SetMinMaxValues(0, 100)
  bar:SetValue(0)
  bar:SetStatusBarTexture((spec and spec.texture) or WHITE)
  frame.targetPowerBar = bar
  frame.powerBar = bar
  frame.Power = bar
  frame.power = bar

  local bg = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
  bg:SetAllPoints(bar)
  bg:SetColorTexture(0, 0, 0, spec and spec.backgroundAlpha or 0.72)
  frame.powerBarBG = bg
  frame.powerBg = bg
end

function Power.Apply(frame, spec)
  if not frame.targetPowerBar then Power.Create(frame, spec) end
  local bar = frame.targetPowerBar
  frame.Power = bar
  frame.powerBar = bar
  frame.power = bar

  local power = spec and spec.power or {}
  local h = tonumber(power.height) or 3
  if power.detached == true then
    LayoutDetached(frame, bar, power, h)
  else
    bar._msufDetached = nil
    bar:ClearAllPoints()
    if power.embed == false then
      bar:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -1)
      bar:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -1)
      bar:SetHeight(h)
    else
      bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
      bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
      bar:SetHeight(h)
    end
  end
  if frame.powerBarBG then
    frame.powerBarBG:ClearAllPoints()
    frame.powerBarBG:SetAllPoints(bar)
  end
  local texture = power.texture or spec and spec.texture or WHITE
  if power.detached == true then
    texture = ApplyShapeMedia(frame, power, texture)
  else
    ApplyShapeMedia(frame, nil, texture)
  end
  if bar._msufTexture ~= texture then
    bar:SetStatusBarTexture(texture)
    bar._msufTexture = texture
  end
  ApplyBackgroundMedia(frame, power)
  if bar.SetReverseFill then
    local reverse = power.reverse == true
    if bar._msufReverseFill ~= reverse then
      bar:SetReverseFill(reverse)
      bar._msufReverseFill = reverse
    end
  end
  bar._msufMinMax = nil
  bar._msufPowerValue = nil
  bar._msufPowerMax = nil
  bar._msufPowerValueUnit = nil
  bar._msufPowerMaxUnit = nil
  bar._msufPowerMaxReady = nil
  bar._msufPowerPercentValue = nil
  bar._msufPowerType = nil
  bar._msufPowerToken = nil
  bar._msufPowerTypeKnown = nil
  bar._msufPowerTypeUnit = nil
  if SetBarSmoothing then SetBarSmoothing(bar, power.smooth == true) end
  SetColor(frame, true)
  SetShown(frame, power.enabled == true)
end

local function UpdatePercent(frame, event, unit)
  if not (UnitPowerPercent and UnitPowerType and SCALE_100) then return false end
  local bar = frame.targetPowerBar
  local power = SpecPower(frame)
  local mode = power and power.mode
  local forceType = event ~= "UNIT_POWER_UPDATE" and event ~= "UNIT_POWER_FREQUENT" and mode ~= "power"
  local powerType, token = ReadPowerTypeCached(frame, bar, unit, forceType)
  local pct = UnitPowerPercent(unit, powerType or 0, true, SCALE_100)
  local secret = IsSecret(pct)
  if not secret and pct == nil then pct = 0 end
  if not secret and not IsFiniteNumber(pct) then pct = 0 end
  local cachedMinMax = bar._msufMinMax
  if IsSecret(cachedMinMax) or cachedMinMax ~= 100 then
    bar:SetMinMaxValues(0, 100)
    bar._msufMinMax = 100
  end
  local cachedPct = bar._msufPowerPercentValue
  local cachedPctSecret = IsSecret(cachedPct)
  if secret or cachedPctSecret or cachedPct ~= pct then
    SetPowerBarValue(bar, pct, secret)
    bar._msufPowerPercentValue = secret and nil or pct
  end
  ClearPowerValueCaches(bar)
  local rt = frame._msufTextRuntime
  if rt and rt.powerNeedsPercent == true and not secret then
    rt._dispatchPowerPercent = pct
    rt._dispatchPowerPercentReady = true
  elseif rt then
    rt._dispatchPowerPercent = nil
    rt._dispatchPowerPercentReady = nil
  end
  return true, pct, powerType, token
end

local function UpdateAbsolute(frame, unit)
  local powerType, token
  local bar = frame.targetPowerBar
  powerType, token = ReadPowerTypeCached(frame, bar, unit, true)
  local value = powerType ~= nil and UnitPower(unit, powerType) or UnitPower(unit)
  local valueSecret = IsSecret(value)
  local maxValue = powerType ~= nil and UnitPowerMax(unit, powerType) or UnitPowerMax(unit)
  local maxSecret = IsSecret(maxValue)
  if not valueSecret then
    value = value or 0
    if not IsFiniteNumber(value) then value = 0 end
  end
  if not maxSecret then
    maxValue = maxValue or 1
    if not IsFiniteNumber(maxValue) or maxValue <= 0 then maxValue = 1 end
  end
  local cachedMinMax = bar._msufMinMax
  local cachedMinMaxSecret = IsSecret(cachedMinMax)
  if maxSecret or cachedMinMaxSecret or cachedMinMax ~= maxValue then
    bar:SetMinMaxValues(0, maxValue)
    bar._msufMinMax = maxSecret and nil or maxValue
  end
  local cachedValue = bar._msufPowerValue
  local cachedValueSecret = IsSecret(cachedValue)
  if valueSecret or cachedValueSecret or cachedValue ~= value or bar._msufPowerValueUnit ~= unit then
    SetPowerBarValue(bar, value, valueSecret)
  end
  bar._msufPowerValue = valueSecret and nil or value
  bar._msufPowerValueUnit = valueSecret and nil or unit
  bar._msufPowerMax = maxSecret and nil or maxValue
  bar._msufPowerMaxUnit = maxSecret and nil or unit
  bar._msufPowerMaxReady = maxSecret and nil or true
  bar._msufPowerPercentValue = nil
  return value, maxValue, powerType, token
end

function Power.Update(frame, event, unit)
  unit = unit or frame.unit
  local bar = frame and frame.targetPowerBar
  if not (bar and unit and BarShown(bar)) then return end
  if event ~= "UNIT_POWER_UPDATE" and event ~= "UNIT_POWER_FREQUENT" or IDENTITY_EVENTS[event] == true then
    SetColor(frame)
  end
  local ok, _, powerType, token = UpdatePercent(frame, event, unit)
  if ok then return nil, nil, powerType, token, event == "UNIT_DISPLAYPOWER" end
  local value, maxValue, absoluteType, absoluteToken = UpdateAbsolute(frame, unit)
  return value, maxValue, absoluteType, absoluteToken, event == "UNIT_DISPLAYPOWER"
end

Power.UpdateValue = Power.Update
Power.UpdateValuePlain = Power.Update
Power.UpdateValueStatic = Power.Update
Power.UpdateValueStaticPlain = Power.Update
Power.UpdateValueGroupPercent = Power.Update
function Power.SelectGroupPowerUpdater() return nil end

UF.RegisterElement("Power", Power)
