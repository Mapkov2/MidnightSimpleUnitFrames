local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}

local C = MSUF.UFBarTextCommon
local UF = C and C.UF or MSUF.UF
if not UF then return end
local Health = UF.Elements and UF.Elements.Health

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
local SnapBarInterpolation = C and C.SnapBarInterpolation
local ApplyBackgrounds = C and C.ApplyBackgrounds
local ApplyBarGradient = C and C.ApplyBarGradient
local HideBarGradient = C and C.HideBarGradient
local ExternalFrameWidth = C and C.ExternalFrameWidth
local InCombatLockdown = C and C.InCombatLockdown or _G.InCombatLockdown
local tonumber = tonumber
local tostring = tostring
local type = type
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local issecretvalue = _G.issecretvalue or function(_) return false end

local Power = {}
local POWER_EVENTS = C and C.POWER_EVENTS
  or { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_POWER_BAR_SHOW", "UNIT_POWER_BAR_HIDE" }
local POWER_EVENTS_FAST = {
  "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_POWER_BAR_SHOW", "UNIT_POWER_BAR_HIDE",
}
-- Group power bars never show alternate power, so they skip the BAR_SHOW/HIDE
-- registrations (matches EllesmereUI's lean per-unit tracker).
local POWER_EVENTS_GROUP = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }
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
local function IsFiniteNumber(value)
  return type(value) == "number" and value == value and (value - value) == 0
end

local function SetPowerBarValue(bar, value, animate, valueSecret)
  -- Opaque combat values cannot be deduplicated, so interpolating each event
  -- would create a second native workload on top of the required SetValue.
  -- Keep configured smoothing for ordinary values only.
  local interp = animate == true and valueSecret ~= true and bar._msufSmoothInterp or nil
  if interp then
    bar:SetValue(value, interp)
    bar._msufInterpolating = true
  else
    bar:SetValue(value)
    bar._msufInterpolating = nil
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

local function ReadPowerTypeCached(bar, unit, force)
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

local function SetShown(frame, shown)
  local bar = frame and frame.targetPowerBar
  if not bar then return end
  if bar._msufShown ~= shown then
    bar._msufShown = shown
    if shown then bar:Show() else bar:Hide() end
  end
  local bg = frame.powerBarBG
  if bg then if shown then bg:Show() else bg:Hide() end end
end

local function SetRegionShown(region, shown)
  if not region or region._msufShown == shown then return end
  region._msufShown = shown
  if shown then region:Show() else region:Hide() end
end

local function HidePowerBorderEdges(bar)
  local edges = bar and bar.MSUFPowerBorderEdges
  if edges then
    for i = 1, 4 do SetRegionShown(edges[i], false) end
  end
  if bar and bar.MSUFPowerBorderHost then
    SetRegionShown(bar.MSUFPowerBorderHost, false)
  end
end

local function HidePowerBorder(bar)
  HidePowerBorderEdges(bar)
  if bar and bar._msufDetachedShapeEdge then
    SetRegionShown(bar._msufDetachedShapeEdge, false)
  end
end

local function EnsurePowerBorder(bar)
  if not bar then return nil end
  local parent = bar.GetParent and bar:GetParent()
  if not parent then return nil end
  local host = bar.MSUFPowerBorderHost
  if not host then
    host = CreateFrame("Frame", nil, parent)
    if host.EnableMouse then host:EnableMouse(false) end
    bar.MSUFPowerBorderHost = host
  elseif host.GetParent and host:GetParent() ~= parent then
    host:SetParent(parent)
  end
  local edges = bar.MSUFPowerBorderEdges
  if edges and edges._host == host then return edges, host end
  edges = {}
  for i = 1, 4 do
    local edge = host:CreateTexture(nil, "OVERLAY", nil, 6)
    edge:SetColorTexture(0, 0, 0, 1)
    edges[i] = edge
  end
  edges._host = host
  bar.MSUFPowerBorderEdges = edges
  bar._msufPowerBorderThickness = nil
  bar._msufPowerBorderR, bar._msufPowerBorderG, bar._msufPowerBorderB, bar._msufPowerBorderA = nil, nil, nil, nil
  return edges, host
end

local function ApplyPowerBorder(bar, power)
  if not bar then return end
  if bar._msufPowerShapeActive == true then
    HidePowerBorderEdges(bar)
    return
  end
  if bar._msufDetachedShapeEdge then SetRegionShown(bar._msufDetachedShapeEdge, false) end
  -- The rectangular border is owned by the per-unit toggle/thickness whether the
  -- bar is inline or detached. `detachedOutline` only feeds the Player shape edge
  -- in ApplyShapeMedia; reading it here made the unit-page border controls inert
  -- as soon as the power bar was detached.
  local thickness = math_floor((tonumber(power and power.borderThickness) or 0) + 0.5)
  if thickness <= 0 or not (power and power.borderEnabled == true) then
    HidePowerBorderEdges(bar)
    return
  end
  if thickness > 8 then thickness = 8 end

  local edges, host = EnsurePowerBorder(bar)
  if not edges then return end
  if host.SetFrameLevel and bar.GetFrameLevel then
    local level = (bar:GetFrameLevel() or 1) + 2
    if host._msufPowerBorderLevel ~= level then
      host:SetFrameLevel(level)
      host._msufPowerBorderLevel = level
    end
  end
  SetRegionShown(host, true)

  local top, bottom, left, right = edges[1], edges[2], edges[3], edges[4]
  if bar._msufPowerBorderThickness ~= thickness then
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", bar, "TOPLEFT", -thickness, thickness)
    host:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", thickness, -thickness)
    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
    top:SetHeight(thickness)
    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(thickness)
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
    left:SetWidth(thickness)
    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(thickness)
    bar._msufPowerBorderThickness = thickness
  end

  local r, g, b, a = power.borderR or 0, power.borderG or 0, power.borderB or 0, power.borderA or 1
  if bar._msufPowerBorderR ~= r or bar._msufPowerBorderG ~= g
    or bar._msufPowerBorderB ~= b or bar._msufPowerBorderA ~= a then
    for i = 1, 4 do edges[i]:SetColorTexture(r, g, b, a) end
    bar._msufPowerBorderR, bar._msufPowerBorderG, bar._msufPowerBorderB, bar._msufPowerBorderA = r, g, b, a
  end
  for i = 1, 4 do SetRegionShown(edges[i], true) end
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
  if frame._msufLegacyCooldownAnchor == true then return nil end
  if frame.IsShown and not frame:IsShown() then return nil end
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

-- External cooldown frames may not be safe to re-measure while protected
-- layouts are locked. Keep the last scale-correct measurement on the actual
-- Power bar so differently scaled Player/Target/Focus frames cannot overwrite
-- one shared cache entry. Outside combat a hidden/unavailable source
-- intentionally falls through to the configured manual width.
local function CachedExternalFrameWidth(name, relativeTo)
  if type(name) ~= "string" or name == "" then return nil end
  local inLockdown = InCombatLockdown and InCombatLockdown() or false
  local cache = relativeTo and relativeTo._msufDetachedExternalWidths
  if inLockdown then
    local cached = cache and Number(cache[name], nil)
    return cached and cached >= 20 and cached or nil
  end
  local width = type(ExternalFrameWidth) == "function" and ExternalFrameWidth(name, relativeTo)
    or FrameWidth(ResolveCooldownWidthFrame(name))
  if relativeTo then
    if width and not cache then
      cache = {}
      relativeTo._msufDetachedExternalWidths = cache
    end
    if width then
      cache[name] = math_floor(width + 0.5)
    elseif cache then
      -- The OOC fallback will now be applied to the physical live bar. Drop
      -- the obsolete external value so a preview opened in combat resolves to
      -- that same fallback instead of resurrecting an older visible width.
      cache[name] = nil
    end
  end
  return width
end

local function ResolveDetachedWidth(frame, power)
  local bar = frame and frame.targetPowerBar
  local width
  if power.detachedSyncClass == true then
    width = FrameWidth(_G.MSUF_ClassPowerContainer)
      or CachedExternalFrameWidth(power.detachedClassWidthFrameName, bar)
      or Number(power.detachedClassWidth, nil)
  else
    width = CachedExternalFrameWidth(power.detachedWidthFrameName, bar)
  end
  width = width or Number(power.detachedWidth, nil)
  width = width or FrameWidth(frame)
  return RoundPositive(width, 1)
end
Power.ResolveDetachedWidth = ResolveDetachedWidth

local function ResolveDetachedAnchor(power)
  local anchor = _G.MSUF_ClassPowerContainer
  if power.detachedAnchorClass == true and anchor and anchor.GetWidth and anchor:GetWidth() > 1
    and (not anchor.IsShown or anchor:IsShown()) then
    return anchor, "TOP", "BOTTOM"
  end
  if power.detachedAnchorMode == "LEGACY_TOPLEFT" then
    return nil, "TOPLEFT", "BOTTOMLEFT"
  end
  return nil, "TOP", "BOTTOM"
end

local function ApplyShapeMedia(frame, power, texture)
  local bar = frame and frame.targetPowerBar
  if not bar then return texture or WHITE end
  local shape = NormalizeShape(power and power.shape)
  local media = DETACHED_SHAPE_TEXTURES[shape]
  if media then
    bar._msufPowerShapeActive = true
    if bar.SetOrientation then
      local orientation = media.vertical and "VERTICAL" or "HORIZONTAL"
      if bar._msufPowerOrientation ~= orientation then
        bar:SetOrientation(orientation)
        bar._msufPowerOrientation = orientation
      end
    end
    local edge = bar._msufDetachedShapeEdge
    if not edge then
      edge = bar:CreateTexture(nil, "OVERLAY", nil, 1)
      bar._msufDetachedShapeEdge = edge
    end
    if edge._msufPowerShapeAnchor ~= bar then
      edge:ClearAllPoints()
      edge:SetAllPoints(bar)
      edge._msufPowerShapeAnchor = bar
    end
    if edge._msufTexture ~= media.edge then
      edge:SetTexture(media.edge)
      edge._msufTexture = media.edge
    end
    local alpha = ShapeOutlineAlpha(power.detachedOutline)
    local r, g, b, a = power.borderR or 0, power.borderG or 0, power.borderB or 0, power.borderA or 1
    if edge._msufR ~= r or edge._msufG ~= g or edge._msufB ~= b or edge._msufA ~= a then
      edge:SetVertexColor(r, g, b, a)
      edge._msufR, edge._msufG, edge._msufB, edge._msufA = r, g, b, a
    end
    if edge._msufAlpha ~= alpha then
      edge:SetAlpha(alpha)
      edge._msufAlpha = alpha
    end
    SetRegionShown(edge, alpha > 0)
    return media.fill
  end

  bar._msufPowerShapeActive = nil
  if bar.SetOrientation and bar._msufPowerOrientation ~= "HORIZONTAL" then
    bar:SetOrientation("HORIZONTAL")
    bar._msufPowerOrientation = "HORIZONTAL"
  end
  local edge = bar._msufDetachedShapeEdge
  if edge then SetRegionShown(edge, false) end
  return texture or WHITE
end

local function ApplyBackgroundMedia(frame, power)
  local bg = frame and frame.powerBarBG
  if not bg then return end
  local texture = power and power.backgroundTexture
  local background = power and power.background or nil
  local r = background and background.r or 0
  local g = background and background.g or 0
  local b = background and background.b or 0
  local ba = background and background.a or power and power.backgroundAlpha
    or frame.MSUFSpec and frame.MSUFSpec.backgroundAlpha or 0.72
  local media = power and power.detached == true and DETACHED_SHAPE_TEXTURES[NormalizeShape(power.shape)]
  if media then
    if bg._msufTexture ~= media.bg then
      bg:SetTexture(media.bg)
      bg._msufTexture = media.bg
    end
    if bg._msufMode ~= "shape" or bg._msufR ~= r or bg._msufG ~= g or bg._msufB ~= b or bg._msufA ~= ba then
      bg:SetVertexColor(r, g, b, ba)
      bg._msufMode = "shape"
      bg._msufR, bg._msufG, bg._msufB = r, g, b
      bg._msufA = ba
    end
    bg._msufBgTexture = media.bg
    bg._msufBgColorTexture = nil
    bg._msufBgR, bg._msufBgG, bg._msufBgB, bg._msufBgA = r, g, b, ba
    return
  end
  if type(texture) == "string" and texture ~= "" then
    if bg._msufTexture ~= texture then
      bg:SetTexture(texture)
      bg._msufTexture = texture
    end
    if bg._msufMode ~= "texture" or bg._msufR ~= r or bg._msufG ~= g or bg._msufB ~= b or bg._msufA ~= ba then
      bg:SetVertexColor(r, g, b, ba)
      bg._msufMode = "texture"
      bg._msufR, bg._msufG, bg._msufB = r, g, b
      bg._msufA = ba
    end
    bg._msufBgTexture = texture
    bg._msufBgColorTexture = nil
    bg._msufBgR, bg._msufBgG, bg._msufBgB, bg._msufBgA = r, g, b, ba
  elseif bg._msufMode ~= "solid" or bg._msufR ~= r or bg._msufG ~= g or bg._msufB ~= b or bg._msufA ~= ba then
    bg:SetColorTexture(r, g, b, ba)
    bg._msufTexture = nil
    bg._msufMode = "solid"
    bg._msufR, bg._msufG, bg._msufB = r, g, b
    bg._msufA = ba
    bg._msufBgTexture = nil
    bg._msufBgColorTexture = true
    bg._msufBgR, bg._msufBgG, bg._msufBgB, bg._msufBgA = r, g, b, ba
  end
end

local function SetPowerFrameLevel(bar, level)
  if not (bar and bar.SetFrameLevel) or bar._msufPowerFrameLevel == level then return end
  bar:SetFrameLevel(level)
  bar._msufPowerFrameLevel = level
end

local function LayoutDetached(frame, bar, power, defaultHeight)
  local shape = NormalizeShape(power.shape)
  local size = shape == "ORB" and RoundPositive(power.orbSize, power.detachedHeight or defaultHeight or 6) or nil
  local width = size or ResolveDetachedWidth(frame, power)
  local height = size or RoundPositive(power.detachedHeight, defaultHeight or 6)
  local x = math_floor(Number(power.detachedX, 0) + 0.5)
  local y = math_floor(Number(power.detachedY, -4) + 0.5)
  local anchor, point, relativePoint = ResolveDetachedAnchor(power)

  bar:ClearAllPoints()
  bar:SetSize(math_max(1, width), math_max(1, height))
  bar._msufDetachedWidth = width
  if anchor then
    bar:SetPoint(point, anchor, relativePoint, x, y)
  else
    bar:SetPoint(point, frame, relativePoint, x, y)
  end
  if bar.SetFrameLevel and frame.GetFrameLevel then
    local level = (frame:GetFrameLevel() or 1) + math_min(30, RoundNonNegative(power.detachedLevel, 6))
    SetPowerFrameLevel(bar, level)
  end
  bar._msufDetached = true
end

-- Cooldown-viewer size changes only affect the physical width of an already
-- laid-out detached bar. Keep this path deliberately narrower than Power.Apply:
-- no config compile, element routing, event rebinding, text/media/color work,
-- or protected anchor mutation is needed here.
function Power.RefreshDetachedExternalWidth(frame, sourceName, power)
  local bar = frame and frame.targetPowerBar
  power = power or SpecPower(frame)
  if not (bar and power and power.enabled == true and power.detached == true) then return false end
  if power.shape == "ORB" then return false end

  local configuredSource = power.detachedSyncClass == true
    and power.detachedClassWidthFrameName
    or power.detachedWidthFrameName
  if configuredSource ~= sourceName then return false end

  -- Resolve even when the last width stamp matches: outside combat this also
  -- clears the per-bar protected fallback cache when a source becomes hidden.
  local width = ResolveDetachedWidth(frame, power)
  if bar._msufDetachedWidth ~= width then
    bar:SetWidth(math_max(1, width))
    bar._msufDetachedWidth = width
  end
  return true
end

local function SetColor(frame, force, resolvedPowerType, resolvedToken, resolvedMetaReady)
  local bar = frame and frame.targetPowerBar
  if not bar then return end
  local power = SpecPower(frame) or {}
  local mode = power.mode
  local r, g, b
  if mode == "dark" or mode == "unified" or mode == "static" then
    r, g, b = power.r, power.g, power.b
  end
  if not (IsFiniteNumber(r) and IsFiniteNumber(g) and IsFiniteNumber(b)) then
    local powerType, token = resolvedPowerType, resolvedToken
    local metaKnown = resolvedMetaReady == true and (powerType ~= nil or token ~= nil) or false
    if mode ~= "class" and resolvedMetaReady ~= true and UnitPowerType then
      powerType, token = ReadPowerTypeCached(bar, frame.MSUFUnitKey, true)
      metaKnown = powerType ~= nil or token ~= nil
    end
    r, g, b = ResolveDynamicPowerColor(frame, frame.MSUFUnitKey, powerType, token, metaKnown)
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

function Power.GetEvents(frame, spec)
  local power = spec and spec.power
  -- Realtime player text is the only unit-frame feature that needs Blizzard's
  -- high-frequency stream.  The compiler publishes that decision on the
  -- power spec so ordinary player bars stay on UNIT_POWER_UPDATE.
  if power and power.frequent == true then
    return POWER_EVENTS_FAST
  end
  -- Group members render a normal (mana/rage/energy) power bar; the
  -- alternate-power show/hide stream is a single-frame/boss concern. Dropping
  -- those two registrations per raid member trims the per-frame event set
  -- toward EllesmereUI's lean tracker without changing any displayed value.
  if spec and spec.scope == "group" then
    return POWER_EVENTS_GROUP
  end
  return POWER_EVENTS
end

function Power.Disable(frame)
  SetShown(frame, false)
  HidePowerBorder(frame and frame.targetPowerBar)
  if HideBarGradient and frame then HideBarGradient(frame.powerGradients) end
  if frame then
    frame._msufPowerBarDetached = nil
    if Health and Health.Layout then Health.Layout(frame, frame.MSUFSpec, false) end
  end
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
  frame._msufPowerBarDetached = power.detached == true and true or nil
  if Health and Health.Layout then Health.Layout(frame, spec, power.enabled == true) end
  if power.detached == true then
    LayoutDetached(frame, bar, power, h)
  else
    bar._msufDetached = nil
    bar._msufDetachedWidth = nil
    local inlineLevel = frame.GetFrameLevel and ((frame:GetFrameLevel() or 1) + 1) or nil
    if inlineLevel then SetPowerFrameLevel(bar, inlineLevel) end
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
  if bar._msufPowerShapeActive == true then
    ApplyBackgroundMedia(frame, power)
    if HideBarGradient then HideBarGradient(frame.powerGradients) end
  else
    if ApplyBackgrounds then
      ApplyBackgrounds(frame, false, true)
    else
      ApplyBackgroundMedia(frame, power)
    end
    if ApplyBarGradient then ApplyBarGradient(frame, bar, power.barGradient, "powerGradients") end
  end
  -- Native fill axis for the inline/embedded bar. ApplyShapeMedia owns
  -- _msufPowerOrientation for detached shapes (ORB forces VERTICAL, others
  -- HORIZONTAL); only override the non-shape bar so shapes keep their axis.
  if bar.SetOrientation and bar._msufPowerShapeActive ~= true then
    local orientation = power.vertical == true and "VERTICAL" or "HORIZONTAL"
    if bar._msufPowerOrientation ~= orientation then
      bar:SetOrientation(orientation)
      bar._msufPowerOrientation = orientation
      -- Force the reverse-fill block below to re-apply after an axis flip.
      bar._msufReverseFill = nil
    end
  end
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
  bar._msufPowerMaxType = nil
  bar._msufPowerPercentValue = nil
  bar._msufPowerType = nil
  bar._msufPowerToken = nil
  bar._msufPowerTypeKnown = nil
  bar._msufPowerTypeUnit = nil
  if SetBarSmoothing then SetBarSmoothing(bar, power.smooth == true) end
  SetColor(frame, true)
  local enabled = power.enabled == true
  SetShown(frame, enabled)
  if enabled then
    ApplyPowerBorder(bar, power)
  else
    HidePowerBorder(bar)
    if HideBarGradient then HideBarGradient(frame.powerGradients) end
  end
end

local function UpdatePercent(frame, event, unit, animate)
  if not (UnitPowerPercent and UnitPowerType and SCALE_100) then return false end
  local bar = frame.targetPowerBar
  -- SetColor used to perform the authoritative non-tick type refresh before
  -- this value read. Preserve that freshness here now that both consumers
  -- share the same result instead of calling ReadPowerTypeCached twice.
  local forceType = animate ~= true
  local powerType, token = ReadPowerTypeCached(bar, unit, forceType)
  local pct = UnitPowerPercent(unit, powerType or 0, true, SCALE_100)
  local secret = issecretvalue(pct) == true
  if not secret and pct == nil then pct = 0 end
  if not secret and not IsFiniteNumber(pct) then pct = 0 end
  if bar._msufMinMax ~= 100 then
    bar:SetMinMaxValues(0, 100)
    bar._msufMinMax = 100
  end
  local cachedPct = bar._msufPowerPercentValue
  if secret or cachedPct ~= pct then
    SetPowerBarValue(bar, pct, animate, secret)
    if secret then
      bar._msufPowerPercentValue = nil
    else
      bar._msufPowerPercentValue = pct
    end
  end
  local rt = frame._msufTextRuntime
  if rt and rt.powerNeedsPercent == true then
    rt._dispatchPowerPercent = pct
    rt._dispatchPowerPercentReady = true
  elseif rt then
    rt._dispatchPowerPercent = nil
    rt._dispatchPowerPercentReady = nil
  end
  return true, pct, powerType, token
end

local function UpdateAbsolute(frame, event, unit, animate)
  local powerType, token
  local bar = frame.targetPowerBar
  local forceType = animate ~= true
  powerType, token = ReadPowerTypeCached(bar, unit, forceType)
  local value
  local maxValue
  local refreshMax = animate ~= true
    or bar._msufPowerMaxReady ~= true
    or bar._msufPowerMaxUnit ~= unit
    or bar._msufPowerMaxType ~= powerType
  if powerType ~= nil then
    value = UnitPower(unit, powerType)
    if refreshMax then maxValue = UnitPowerMax(unit, powerType) else maxValue = bar._msufPowerMax end
  else
    value = UnitPower(unit)
    if refreshMax then maxValue = UnitPowerMax(unit) else maxValue = bar._msufPowerMax end
  end
  local valueSecret = issecretvalue(value) == true
  local maxSecret = issecretvalue(maxValue) == true
  if not valueSecret then
    value = value or 0
    if not IsFiniteNumber(value) then value = 0 end
  end
  if not maxSecret then
    maxValue = maxValue or 1
    if not IsFiniteNumber(maxValue) or maxValue <= 0 then maxValue = 1 end
  end
  local cachedMinMax = bar._msufMinMax
  local maxChanged = false
  if maxSecret then
    if refreshMax then
      bar:SetMinMaxValues(0, maxValue)
      bar._msufMinMax = nil
    end
  else
    maxChanged = cachedMinMax ~= maxValue
    if maxChanged then
      bar:SetMinMaxValues(0, maxValue)
      bar._msufMinMax = maxValue
    end
  end
  local cachedValue = bar._msufPowerValue
  if valueSecret or cachedValue ~= value or bar._msufPowerValueUnit ~= unit then
    SetPowerBarValue(bar, value, animate, valueSecret)
  end
  if valueSecret then
    bar._msufPowerValue = nil
    bar._msufPowerValueUnit = nil
  else
    bar._msufPowerValue = value
    bar._msufPowerValueUnit = unit
  end
  if refreshMax or (not maxSecret and maxChanged) then
    bar._msufPowerMax = maxValue
    bar._msufPowerMaxUnit = unit
    bar._msufPowerMaxReady = true
    bar._msufPowerMaxType = powerType
  end
  bar._msufPowerPercentValue = nil
  return value, maxValue, powerType, token
end

local function UpdatePercentPath(frame, event, unit, eventPowerToken)
  unit = unit or (frame and frame.MSUFUnitKey)
  local rt = frame and frame._msufTextRuntime
  if rt and rt._dispatchPowerPercentReady == true then
    rt._dispatchPowerPercent = nil
    rt._dispatchPowerPercentReady = nil
  end
  local bar = frame and frame.targetPowerBar
  local animate = event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT"
  if not (bar and unit) then return end
  local shown = bar._msufShown
  if shown ~= true and (shown == false or (bar.IsShown and not bar:IsShown())) then return end
  if animate and type(eventPowerToken) == "string" and eventPowerToken ~= ""
    and bar._msufPowerTypeKnown == true and bar._msufPowerToken ~= nil
    and bar._msufPowerToken ~= eventPowerToken then return end
  if not animate then
    if SnapBarInterpolation then SnapBarInterpolation(bar) end
  end
  local ok, _, powerType, token = UpdatePercent(frame, event, unit, animate)
  if ok then
    if not animate then SetColor(frame, false, powerType, token, true) end
    return nil, nil, powerType, token, event == "UNIT_DISPLAYPOWER"
  end
  local value, maxValue, absoluteType, absoluteToken = UpdateAbsolute(frame, event, unit, animate)
  if not animate then SetColor(frame, false, absoluteType, absoluteToken, true) end
  return value, maxValue, absoluteType, absoluteToken, event == "UNIT_DISPLAYPOWER"
end

local function UpdateAbsolutePath(frame, event, unit, eventPowerToken)
  unit = unit or (frame and frame.MSUFUnitKey)
  local rt = frame and frame._msufTextRuntime
  if rt and rt._dispatchPowerPercentReady == true then
    rt._dispatchPowerPercent = nil
    rt._dispatchPowerPercentReady = nil
  end
  local bar = frame and frame.targetPowerBar
  local animate = event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT"
  if not (bar and unit) then return end
  local shown = bar._msufShown
  if shown ~= true and (shown == false or (bar.IsShown and not bar:IsShown())) then return end
  if animate and type(eventPowerToken) == "string" and eventPowerToken ~= ""
    and bar._msufPowerTypeKnown == true and bar._msufPowerToken ~= nil
    and bar._msufPowerToken ~= eventPowerToken then return end
  if not animate then
    if SnapBarInterpolation then SnapBarInterpolation(bar) end
  end
  local value, maxValue, powerType, token = UpdateAbsolute(frame, event, unit, animate)
  if not animate then SetColor(frame, false, powerType, token, true) end
  return value, maxValue, powerType, token, event == "UNIT_DISPLAYPOWER"
end

local function UpdateCurrentPath(frame, event, unit, eventPowerToken)
  unit = unit or (frame and frame.MSUFUnitKey)
  local rt = frame and frame._msufTextRuntime
  if rt and rt._dispatchPowerPercentReady == true then
    rt._dispatchPowerPercent = nil
    rt._dispatchPowerPercentReady = nil
  end
  local bar = frame and frame.targetPowerBar
  local animate = event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT"
  if not (bar and unit) then return end
  local shown = bar._msufShown
  if shown ~= true and (shown == false or (bar.IsShown and not bar:IsShown())) then return end
  if animate and type(eventPowerToken) == "string" and eventPowerToken ~= ""
    and bar._msufPowerTypeKnown == true and bar._msufPowerToken ~= nil
    and bar._msufPowerToken ~= eventPowerToken then return end
  if not animate then
    if SnapBarInterpolation then SnapBarInterpolation(bar) end
  end
  -- CURRENT-only text does not need a percent sample. Drive both the bar and
  -- text from one UnitPower read, with UnitPowerMax cached between its owned
  -- invalidation events.
  local value, _, powerType, token = UpdateAbsolute(frame, event, unit, animate)
  if not animate then SetColor(frame, false, powerType, token, true) end
  return value, nil, powerType, token, event == "UNIT_DISPLAYPOWER"
end

-- Mixed CURRENT+PERCENT formats retain UnitPowerPercent because protected
-- values cannot be divided in Lua. Keeping this as its own compiled route also
-- leaves the overwhelmingly common CURRENT-only path free of format branches.
local function UpdateCurrentPercentPath(frame, event, unit, eventPowerToken)
  unit = unit or (frame and frame.MSUFUnitKey)
  local rt = frame and frame._msufTextRuntime
  if rt and rt._dispatchPowerPercentReady == true then
    rt._dispatchPowerPercent = nil
    rt._dispatchPowerPercentReady = nil
  end
  local bar = frame and frame.targetPowerBar
  local animate = event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT"
  if not (bar and unit) then return end
  local shown = bar._msufShown
  if shown ~= true and (shown == false or (bar.IsShown and not bar:IsShown())) then return end
  if animate and type(eventPowerToken) == "string" and eventPowerToken ~= ""
    and bar._msufPowerTypeKnown == true and bar._msufPowerToken ~= nil
    and bar._msufPowerToken ~= eventPowerToken then return end
  if not animate then
    if SnapBarInterpolation then SnapBarInterpolation(bar) end
  end
  local ok, _, powerType, token = UpdatePercent(frame, event, unit, animate)
  if not ok then
    local value, maxValue, absoluteType, absoluteToken = UpdateAbsolute(frame, event, unit, animate)
    if not animate then SetColor(frame, false, absoluteType, absoluteToken, true) end
    return value, maxValue, absoluteType, absoluteToken, event == "UNIT_DISPLAYPOWER"
  end
  local value
  if powerType ~= nil then value = UnitPower(unit, powerType) else value = UnitPower(unit) end
  if not animate then SetColor(frame, false, powerType, token, true) end
  return value, nil, powerType, token, event == "UNIT_DISPLAYPOWER"
end

-- Group percent bar with zero power-text consumers: single-pass lane folding
-- UpdatePercentPath + UpdatePercent without the text-runtime handshakes.
-- Behaviour is identical for a frame whose text runtime has no power slots;
-- SelectGroupPowerUpdater swaps back to UpdatePercentPath when slots appear.
local function UpdateGroupPercentPathLean(frame, event, unit, eventPowerToken)
  unit = unit or (frame and frame.MSUFUnitKey)
  local bar = frame and frame.targetPowerBar
  if not (bar and unit) then return end
  local shown = bar._msufShown
  if shown ~= true and (shown == false or (bar.IsShown and not bar:IsShown())) then return end
  local animate = event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT"
  if animate and type(eventPowerToken) == "string" and eventPowerToken ~= ""
    and bar._msufPowerTypeKnown == true and bar._msufPowerToken ~= nil
    and bar._msufPowerToken ~= eventPowerToken then return end
  if not (UnitPowerPercent and UnitPowerType and SCALE_100) then
    return UpdatePercentPath(frame, event, unit, eventPowerToken)
  end
  if not animate then
    if SnapBarInterpolation then SnapBarInterpolation(bar) end
  end

  local powerType, token = ReadPowerTypeCached(bar, unit, animate ~= true)
  local pct = UnitPowerPercent(unit, powerType or 0, true, SCALE_100)
  local secret = issecretvalue(pct) == true
  if not secret and (type(pct) ~= "number" or pct ~= pct or (pct - pct) ~= 0) then pct = 0 end
  if bar._msufMinMax ~= 100 then
    bar:SetMinMaxValues(0, 100)
    bar._msufMinMax = 100
  end
  if secret or bar._msufPowerPercentValue ~= pct then
    SetPowerBarValue(bar, pct, animate, secret)
    if secret then
      bar._msufPowerPercentValue = nil
    else
      bar._msufPowerPercentValue = pct
    end
  end
  if not animate then SetColor(frame, false, powerType, token, true) end
  return nil, nil, powerType, token, event == "UNIT_DISPLAYPOWER"
end

local POWER_PLAN_PERCENT = 1
local POWER_PLAN_CURRENT = 2
local POWER_PLAN_ABSOLUTE = 3
local POWER_PLAN_CURRENT_PERCENT = 4

local function PowerValuePlan(frame)
  local rt = frame and frame._msufTextRuntime
  if not (rt and (rt.powerSlotCount or 0) > 0) then return POWER_PLAN_PERCENT end
  if rt.powerNeedsCurrent == true and rt.powerNeedsMax == true then return POWER_PLAN_ABSOLUTE end
  if rt.powerNeedsCurrent == true then
    return rt.powerNeedsPercent == true and POWER_PLAN_CURRENT_PERCENT or POWER_PLAN_CURRENT
  end
  return POWER_PLAN_PERCENT
end

function Power.Update(frame, event, unit, eventPowerToken)
  local spec = frame and frame.MSUFSpec
  if frame and (frame._msufIsGroupFrame == true or (spec and spec.scope == "group")) then
    return UpdatePercentPath(frame, event, unit, eventPowerToken)
  end
  local plan = PowerValuePlan(frame)
  if plan == POWER_PLAN_ABSOLUTE then return UpdateAbsolutePath(frame, event, unit, eventPowerToken) end
  if plan == POWER_PLAN_CURRENT_PERCENT then return UpdateCurrentPercentPath(frame, event, unit, eventPowerToken) end
  if plan == POWER_PLAN_CURRENT then return UpdateCurrentPath(frame, event, unit, eventPowerToken) end
  return UpdatePercentPath(frame, event, unit, eventPowerToken)
end

function Power.SelectUpdate(frame, spec)
  if (spec and spec.scope == "group") or (frame and frame._msufIsGroupFrame == true) then
    -- No power-text consumers -> the folded single-pass lane; any power slot
    -- keeps the generic path that owns the text-runtime percent handshake.
    local rt = frame and frame._msufTextRuntime
    if rt == nil or (rt.powerSlotCount or 0) == 0 then
      return UpdateGroupPercentPathLean
    end
    return UpdatePercentPath
  end
  local plan = PowerValuePlan(frame)
  if plan == POWER_PLAN_ABSOLUTE then return UpdateAbsolutePath end
  if plan == POWER_PLAN_CURRENT_PERCENT then return UpdateCurrentPercentPath end
  if plan == POWER_PLAN_CURRENT then return UpdateCurrentPath end
  return UpdatePercentPath
end

Power.UpdateValue = Power.Update
Power.UpdateValuePlain = Power.Update
Power.UpdateValueStatic = Power.Update
Power.UpdateValueStaticPlain = Power.Update
Power.UpdateValueGroupPercent = UpdatePercentPath
Power.UpdateValueGroupPercentLean = UpdateGroupPercentPathLean
-- Keep both compiled value-source implementations discoverable as immutable
-- element functions for shared Core route prototypes.
Power.UpdateValuePercentPath = UpdatePercentPath
Power.UpdateValueCurrentPath = UpdateCurrentPath
Power.UpdateValueCurrentPercentPath = UpdateCurrentPercentPath
Power.UpdateValueAbsolutePath = UpdateAbsolutePath
function Power.SelectGroupPowerUpdater(frame)
  if not frame then return nil end
  local update = Power.SelectUpdate(frame, frame.MSUFSpec)
  local updateKey = UF._updateKeys and UF._updateKeys.Power
  if updateKey and frame._msufActiveElements and frame._msufActiveElements.Power == true then
    frame[updateKey] = update
  end
  return update
end

UF.RegisterElement("Power", Power)
