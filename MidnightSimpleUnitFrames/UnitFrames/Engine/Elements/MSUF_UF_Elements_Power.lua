local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}

--- UnitFrames/Engine/Elements/MSUF_UF_Elements_Power.lua
---
--- Power bar element for single unit frames. Config compilation decides whether
--- power is embedded/detached/shaped; this element creates the regions, applies
--- the compiled layout, and exposes fast update functions used by Dispatch.
--- Keep DB reads out of Update paths; use frame.MSUFSpec.power instead.

local C = MSUF.UFBarTextCommon
if not C then return end

local UF = C.UF
local CreateFrame = C.CreateFrame
local UnitPower = C.UnitPower
local UnitPowerMax = C.UnitPowerMax
local UnitPowerType = C.UnitPowerType
local tonumber = C.tonumber
local floor = C.floor
local WHITE = C.WHITE
local POWER_EVENTS = C.POWER_EVENTS
local POWER_EVENTS_FREQUENT = C.POWER_EVENTS_FREQUENT
local SetStatusTexture = C.SetStatusTexture
local ApplyStatusColor = C.ApplyStatusColor
local SetBarMinMax = C.SetBarMinMax
local SetBarMinMaxKnown = C.SetBarMinMaxKnown
local SetBarMinMaxPlain = C.SetBarMinMaxPlain or C.SetBarMinMax
local SetBarValue = C.SetBarValue
local SetBarValueKnown = C.SetBarValueKnown
local SetBarValuePlain = C.SetBarValuePlain or C.SetBarValue
local SnapBarInterpolation = C.SnapBarInterpolation
local SetBarSmoothing = C.SetBarSmoothing
local SetShownCached = C.SetShownCached
local SetFrameLevelCached = C.SetFrameLevelCached
local ExternalFrameWidth = C.ExternalFrameWidth
local ApplyBackgrounds = C.ApplyBackgrounds
local ApplyBarGradient = C.ApplyBarGradient
local HideBarGradient = C.HideBarGradient
local PowerColor = C.PowerColor
local issecretvalue = _G.issecretvalue or function(_) return false end
local Power = {}
local POWER_SHAPE_MEDIA = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\ClassPower\\"
local POWER_SHAPE_TEXTURES = {
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
    axis = "VERTICAL",
  },
}

local function NormalizePowerShape(value)
  value = tostring(value or "BAR"):upper()
  if value == "ROUND" or value == "CRYSTAL" or value == "ORB" then return value end
  return "BAR"
end

local function PowerShapeTextures(value)
  return POWER_SHAPE_TEXTURES[NormalizePowerShape(value)]
end

local function ShapeOutlineAlpha(value)
  value = tonumber(value) or 0
  if value <= 0 then return 0 end
  if value >= 8 then return 1 end
  return 0.49 + (value * 0.065)
end

local function ClearPowerShapeFillClip(bar)
  if not bar then return end
  if bar.SetScript and bar._msufPowerShapeFillClipEnabled == true then
    bar:SetScript("OnValueChanged", nil)
  end
  bar._msufPowerShapeFillClipEnabled = nil
  bar._msufPowerShapeAxis = nil
  local tex = bar._msufPowerShapeFillTex or (bar.GetStatusBarTexture and bar:GetStatusBarTexture())
  if tex then
    tex:SetTexCoord(0, 1, 0, 1)
    tex._msufPowerShapeL, tex._msufPowerShapeR = nil, nil
    tex._msufPowerShapeT, tex._msufPowerShapeB = nil, nil
  end
  bar._msufPowerShapeFillTex = nil
end

local function ApplyNativePowerShapeFill(bar, axis)
  ClearPowerShapeFillClip(bar)
  if bar and bar.SetOrientation then
    bar:SetOrientation(axis == "VERTICAL" and "VERTICAL" or "HORIZONTAL")
  end
  if bar then
    bar._msufPowerShapeAxis = axis == "VERTICAL" and "VERTICAL" or nil
  end
end

local function DisablePowerShapeFillClip(bar)
  local wasVertical = bar and bar._msufPowerShapeAxis == "VERTICAL"
  ClearPowerShapeFillClip(bar)
  if bar and bar.SetOrientation and wasVertical then
    bar:SetOrientation("HORIZONTAL")
  end
end

local function StorePowerMax(frame, bar, unit, maxPower, maxSecret)
  if maxSecret == nil then maxSecret = issecretvalue(maxPower) == true end
  if maxSecret then
    -- Secret max-power values must not leak into text/runtime caches. Keep the
    -- bar update path functional, but force future reads to ask the client again.
    bar._msufPowerMax = nil
    bar._msufPowerMaxSecret = nil
    bar._msufPowerMaxUnit = nil
    bar._msufPowerMaxReady = nil
    if frame then
      frame._msufTextPowerMax = nil
      frame._msufTextPowerMaxUnit = nil
    end
    return
  end
  bar._msufPowerMax = maxPower
  bar._msufPowerMaxSecret = nil
  bar._msufPowerMaxUnit = unit
  bar._msufPowerMaxReady = true
  if frame then
    frame._msufTextPowerMax = maxPower
    frame._msufTextPowerMaxUnit = unit
  end
end

if not SetBarMinMaxKnown then
  SetBarMinMaxKnown = function(bar, maxValue)
    return SetBarMinMax(bar, maxValue, true)
  end
end

if not SetBarValueKnown then
  SetBarValueKnown = function(bar, value, _, animate)
    return SetBarValue(bar, value, true, animate)
  end
end

local function ReadPowerType(unit)
  if not UnitPowerType then
    return nil, nil
  end
  local powerType, powerToken = UnitPowerType(unit)
  if issecretvalue(powerType) == true then powerType = nil end
  if issecretvalue(powerToken) == true then powerToken = nil end
  return powerType, powerToken
end

local function ReadPowerMeta(frame, bar, unit, force)
  local cacheUnit = unit
  local maxUnit = bar._msufPowerMaxUnit
  local sameMaxUnit = cacheUnit ~= nil and maxUnit == cacheUnit
  if not force and bar._msufPowerMaxReady == true and sameMaxUnit then
    return bar._msufPowerType, bar._msufPowerMax, bar._msufPowerToken, false, bar._msufPowerMaxSecret == true
  end

  local needsType = frame and frame._msufPowerBarNeedsType == true
  local powerType, powerToken
  if needsType then
    -- Alternate power bars need the power type token; plain power bars skip it
    -- to avoid extra UnitPowerType calls in frequent update paths.
    powerType, powerToken = ReadPowerType(unit)
  end
  local maxPower
  if powerType == nil then
    maxPower = UnitPowerMax(unit)
  else
    maxPower = UnitPowerMax(unit, powerType)
  end
  local maxSecret = issecretvalue(maxPower) == true
  if not maxSecret and maxPower == nil then maxPower = 1 end

  local powerMetaChanged = powerType ~= bar._msufPowerType or powerToken ~= bar._msufPowerToken
  bar._msufPowerType = powerType
  bar._msufPowerToken = powerToken
  if needsType then
    frame._msufTextPowerType = powerType
    frame._msufTextPowerToken = powerToken
    frame._msufTextPowerTypeKnown = true
    frame._msufTextPowerTypeUnit = cacheUnit
  end
  StorePowerMax(frame, bar, cacheUnit, maxPower, maxSecret)
  return powerType, maxPower, powerToken, powerMetaChanged, maxSecret
end

local function ReadPowerValues(frame, bar, unit, event, animate)
  local powerType, maxPower, powerToken, powerMetaChanged, maxSecret
  local cacheUnit = unit
  local maxUnit = bar._msufPowerMaxUnit
  local sameMaxUnit = cacheUnit ~= nil and maxUnit == cacheUnit
  if animate and bar._msufPowerMaxReady == true and sameMaxUnit then
    powerType = bar._msufPowerType
    maxPower = bar._msufPowerMax
    powerToken = bar._msufPowerToken
    powerMetaChanged = false
    maxSecret = bar._msufPowerMaxSecret == true
  else
    local forceMeta = bar._msufPowerMaxReady ~= true
      or not sameMaxUnit
    if not forceMeta and not animate then
      forceMeta = event == "UNIT_MAXPOWER"
        or event == "UNIT_DISPLAYPOWER"
        or event == "UNIT_POWER_BAR_SHOW"
        or event == "UNIT_POWER_BAR_HIDE"
        or event == "MSUF_APPLY"
        or event == "MSUF_FORCE_UPDATE"
        or event == "MSUF_POWER_LAYOUT"
    end
    powerType, maxPower, powerToken, powerMetaChanged, maxSecret = ReadPowerMeta(frame, bar, unit, forceMeta)
  end
  local power
  if powerType ~= nil then
    power = UnitPower(unit, powerType)
  else
    power = UnitPower(unit)
  end
  local powerSecret = issecretvalue(power) == true
  if not powerSecret and power == nil then power = 0 end
  return power, maxPower, powerType, powerToken, powerMetaChanged, powerSecret, maxSecret
end

local function EnsurePowerBackground(frame, bar, spec)
  local bg = frame and frame.powerBarBG
  if bg and bg.GetParent and bg:GetParent() == bar then
    return bg
  end
  if bg then
    bg:Hide()
  end
  bg = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
  bg:SetColorTexture(0, 0, 0, spec and spec.backgroundAlpha or 0.72)
  frame.powerBarBG = bg
  frame.powerBg = bg
  return bg
end

local function HidePowerBorderEdges(bar)
  local edges = bar and bar.MSUFPowerBorderEdges
  if not edges then
    if bar and bar.MSUFPowerBorderHost then
      SetShownCached(bar.MSUFPowerBorderHost, false)
    end
    return
  end
  for i = 1, 4 do
    SetShownCached(edges[i], false)
  end
  if bar and bar.MSUFPowerBorderHost then
    SetShownCached(bar.MSUFPowerBorderHost, false)
  end
end

local function HidePowerBorder(bar)
  HidePowerBorderEdges(bar)
  if bar and bar._msufPowerShapeEdge then
    SetShownCached(bar._msufPowerShapeEdge, false)
  end
end

local function EnsurePowerBorder(bar)
  if not bar then return nil end
  local parent = bar.GetParent and bar:GetParent()
  if not parent then return nil end
  local host = bar.MSUFPowerBorderHost
  if not host then
    host = CreateFrame("Frame", nil, parent)
    host:EnableMouse(false)
    bar.MSUFPowerBorderHost = host
  elseif host.GetParent and host:GetParent() ~= parent then
    host:SetParent(parent)
    bar.MSUFPowerBorderEdges = nil
    bar._msufPowerBorderThickness = nil
    bar._msufPowerBorderR, bar._msufPowerBorderG, bar._msufPowerBorderB, bar._msufPowerBorderA = nil, nil, nil, nil
  end
  local edges = bar.MSUFPowerBorderEdges
  if edges and edges._host == host then
    return edges, host
  end
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
  if PowerShapeTextures(power and power.shape) then
    HidePowerBorderEdges(bar)
    return
  end
  if bar and bar._msufPowerShapeEdge then
    SetShownCached(bar._msufPowerShapeEdge, false)
  end
  local detached = power and power.detached == true
  local thickness = floor((tonumber(detached and power.detachedOutline or power and power.borderThickness) or 0) + 0.5)
  if thickness <= 0 or (not detached and not (power and power.borderEnabled == true)) then
    HidePowerBorder(bar)
    return
  end
  if thickness > 8 then
    thickness = 8
  end
  local r, g, b, a = power.borderR or 0, power.borderG or 0, power.borderB or 0, power.borderA or 1
  local edges, host = EnsurePowerBorder(bar)
  if not edges then return end
  host:ClearAllPoints()
  host:SetPoint("TOPLEFT", bar, "TOPLEFT", -thickness, thickness)
  host:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", thickness, -thickness)
  if host.SetFrameLevel and bar.GetFrameLevel then
    host:SetFrameLevel((bar:GetFrameLevel() or 1) + 2)
  end
  SetShownCached(host, true)
  local top, bottom, left, right = edges[1], edges[2], edges[3], edges[4]
  if bar._msufPowerBorderThickness ~= thickness then
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
  if bar._msufPowerBorderR ~= r or bar._msufPowerBorderG ~= g or bar._msufPowerBorderB ~= b or bar._msufPowerBorderA ~= a then
    for i = 1, 4 do
      edges[i]:SetColorTexture(r, g, b, a)
    end
    bar._msufPowerBorderR, bar._msufPowerBorderG, bar._msufPowerBorderB, bar._msufPowerBorderA = r, g, b, a
  end
  for i = 1, 4 do
    SetShownCached(edges[i], true)
  end
end

local function EnsurePowerShapeEdge(bar)
  if not bar then return nil end
  if bar._msufPowerShapeEdge then return bar._msufPowerShapeEdge end
  local edge = bar:CreateTexture(nil, "OVERLAY", nil, 7)
  edge:SetAllPoints(bar)
  edge:SetVertexColor(0, 0, 0, 1)
  edge:Hide()
  bar._msufPowerShapeEdge = edge
  return edge
end

local function ApplyPowerShape(bar, bg, power, powerColorR, powerColorG, powerColorB)
  local shapeInfo = PowerShapeTextures(power and power.shape)
  if not shapeInfo then
    DisablePowerShapeFillClip(bar)
    if bar and bar._msufPowerShapeEdge then
      SetShownCached(bar._msufPowerShapeEdge, false)
    end
    return false
  end

  SetStatusTexture(bar, shapeInfo.fill)
  ApplyNativePowerShapeFill(bar, shapeInfo.axis)
  if bg then
    local bgSpec = power and power.background
    bg:SetTexture(shapeInfo.bg)
    bg:SetVertexColor(
      (bgSpec and bgSpec.r) or powerColorR or 0,
      (bgSpec and bgSpec.g) or powerColorG or 0,
      (bgSpec and bgSpec.b) or powerColorB or 0,
      (bgSpec and bgSpec.a) or 0.72
    )
  end

  local detached = power and power.detached == true
  local thickness = floor((tonumber(detached and power.detachedOutline or power and power.borderThickness) or 0) + 0.5)
  if thickness > 8 then thickness = 8 end
  local showEdge = power and thickness > 0 and (detached or power.borderEnabled == true)
  local edge = EnsurePowerShapeEdge(bar)
  if edge then
    edge:SetTexture(shapeInfo.edge)
    edge:SetVertexColor(power.borderR or 0, power.borderG or 0, power.borderB or 0, (power.borderA or 1) * ShapeOutlineAlpha(thickness))
    if showEdge and edge._msufPowerShapeOutline ~= "FIT" then
      edge:ClearAllPoints()
      edge:SetAllPoints(bar)
      edge._msufPowerShapeOutline = "FIT"
    end
    SetShownCached(edge, showEdge)
  end
  return true
end

function Power.IsEnabled(frame, spec)
  return spec and spec.power and spec.power.enabled == true
end

function Power.GetEvents(frame, spec)
  return spec and spec.power and spec.power.frequent == true and POWER_EVENTS_FREQUENT or POWER_EVENTS
end

function Power.Disable(frame)
  if frame.targetPowerBar then
    SetShownCached(frame.targetPowerBar, false)
  end
  if frame.powerBarBG then
    SetShownCached(frame.powerBarBG, false)
  end
  if HideBarGradient then
    HideBarGradient(frame.powerGradients)
  end
  HidePowerBorder(frame.targetPowerBar)
end

function Power.Create(frame, spec)
  if frame.targetPowerBar then
    return
  end
  local bar = CreateFrame("StatusBar", nil, frame)
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(0)
  bar:SetStatusBarTexture((spec and spec.texture) or WHITE)
  frame.targetPowerBar = bar
  frame.powerBar = bar
  frame.Power = bar
  frame.power = bar

  local bg = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
  bg:SetColorTexture(0, 0, 0, spec and spec.backgroundAlpha or 0.72)
  frame.powerBarBG = bg
  frame.powerBg = bg
end

function Power.Apply(frame, spec)
  if not frame.targetPowerBar then
    Power.Create(frame, spec)
  end
  local bar = frame.targetPowerBar
  frame.Power = bar
  frame.powerBar = bar
  frame.power = bar
  local bg = EnsurePowerBackground(frame, bar, spec)
  local power = spec and spec.power or {}
  local needsType = power.mode == nil or power.mode == "power"
  if frame._msufPowerBarNeedsType ~= (needsType and true or nil) then
    frame._msufPowerBarNeedsType = needsType and true or nil
    bar._msufPowerType = nil
    bar._msufPowerToken = nil
    bar._msufPowerMaxReady = nil
    bar._msufPowerMaxUnit = nil
  end
  local h = tonumber(power.height) or 3
  local layout = power.detached == true and "DETACHED" or (power.embed == false and "OUTSIDE" or "EMBED")
  local shape = layout == "DETACHED" and NormalizePowerShape(power.shape) or "BAR"
  local classAnchor = power.detached == true and power.detachedAnchorClass == true and _G.MSUF_ClassPowerContainer or nil
  if classAnchor and classAnchor.IsShown and not classAnchor:IsShown() then
    classAnchor = nil
  end
  local width = tonumber(power.detachedWidth) or tonumber(spec and spec.width) or frame:GetWidth()
  if power.detached == true then
    if power.detachedSyncClass == true then
      local classWidth = classAnchor and classAnchor.GetWidth and classAnchor:GetWidth() or nil
      if classWidth and classWidth < 20 then
        classWidth = nil
      end
      width = classWidth
        or ExternalFrameWidth(power.detachedClassWidthFrameName, bar)
        or tonumber(power.detachedClassWidth)
        or width
    else
      width = ExternalFrameWidth(power.detachedWidthFrameName, bar) or width
    end
  end
  width = tonumber(width) or tonumber(spec and spec.width) or frame:GetWidth()
  if width < 20 then
    width = tonumber(spec and spec.width) or 20
  end
  local detachedH = tonumber(power.detachedHeight) or h
  if shape == "ORB" then
    local orbSize = tonumber(power.orbSize) or 54
    if orbSize < 20 then orbSize = 20 elseif orbSize > 160 then orbSize = 160 end
    width = orbSize
    detachedH = orbSize
  end
  local detachedX = tonumber(power.detachedX) or 0
  local detachedY = tonumber(power.detachedY) or -4
  local detachedLevel = tonumber(power.detachedLevel) or 6
  local frameLevel = frame.GetFrameLevel and (frame:GetFrameLevel() or 1) or 1
  local targetLevel = frameLevel + detachedLevel
  local layoutChanged = bar._msufPowerLayout ~= layout
    or bar._msufPowerShape ~= shape
    or bar._msufPowerHeight ~= h
    or bar._msufPowerWidth ~= width
    or bar._msufPowerDetachedHeight ~= detachedH
    or bar._msufPowerDetachedX ~= detachedX
    or bar._msufPowerDetachedY ~= detachedY
    or bar._msufPowerDetachedLevel ~= detachedLevel
    or bar._msufPowerFrameLevel ~= frameLevel
    or bar._msufPowerAnchorFrame ~= classAnchor
  if layoutChanged then
    bar:ClearAllPoints()
    bg:ClearAllPoints()
  end
  if power.detached == true then
    frame._msufPowerBarDetached = true
    if layoutChanged then
      if classAnchor then
        bar:SetPoint("TOP", classAnchor, "BOTTOM", detachedX, detachedY)
      else
        bar:SetPoint("TOP", frame, "BOTTOM", detachedX, detachedY)
      end
      bar:SetSize(width, detachedH)
      SetFrameLevelCached(bar, targetLevel)
    end
  elseif power.embed == false then
    frame._msufPowerBarDetached = nil
    if layoutChanged then
      bar:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -1)
      bar:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -1)
      bar:SetHeight(h)
      SetFrameLevelCached(bar, frameLevel + 1)
    end
  else
    frame._msufPowerBarDetached = nil
    if layoutChanged then
      bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
      bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
      bar:SetHeight(h)
      SetFrameLevelCached(bar, frameLevel + 1)
    end
  end
  if layoutChanged then
    bg:SetAllPoints(bar)
    bar._msufPowerLayout = layout
    bar._msufPowerShape = shape
    bar._msufPowerHeight = h
    bar._msufPowerWidth = width
    bar._msufPowerDetachedHeight = detachedH
    bar._msufPowerDetachedX = detachedX
    bar._msufPowerDetachedY = detachedY
    bar._msufPowerDetachedLevel = detachedLevel
    bar._msufPowerFrameLevel = frameLevel
    bar._msufPowerAnchorFrame = classAnchor
  end
  if bar.SetReverseFill then
    local reverse = power.reverse == true
    if bar._msufReverseFill ~= reverse then
      bar:SetReverseFill(reverse)
      bar._msufReverseFill = reverse
    end
  end
  SetBarSmoothing(bar, power.smooth == true)
  SetStatusTexture(bar, power.texture or WHITE)
  local pr, pg, pb = PowerColor(frame, frame.unit)
  ApplyStatusColor(bar, pr, pg, pb)
  ApplyBackgrounds(frame)
  local shapedPower = shape ~= "BAR" and ApplyPowerShape(bar, bg, power, pr, pg, pb) or false
  if not shapedPower then
    DisablePowerShapeFillClip(bar)
  end
  bar._msufPowerShapeActive = shapedPower == true
  if shapedPower then
    if HideBarGradient then
      HideBarGradient(frame.powerGradients)
    end
  elseif ApplyBarGradient then
    ApplyBarGradient(frame, bar, power.barGradient, "powerGradients")
  end
  frame._msufUpdatePowerValue = frame.unit == "player" and Power.UpdateValuePlain or Power.UpdateValue
  if power.enabled == true then
    SetShownCached(bar, true)
    SetShownCached(bg, true)
    ApplyPowerBorder(bar, power)
  else
    SetShownCached(bar, false)
    SetShownCached(bg, false)
    HidePowerBorder(bar)
  end
end

function Power.UpdateValuePlain(frame, event, unit)
  unit = unit or frame.unit
  if issecretvalue(unit) == true or unit ~= "player" then
    return Power.UpdateValue(frame, event, unit)
  end
  -- Player power cannot be a foreign secure unit token, so this fastpath can use
  -- plain setters and skip secret plumbing unless the unit changes unexpectedly.
  local bar = frame.targetPowerBar
  if not bar or bar._msufShown == false or (bar._msufShown == nil and bar.IsShown and not bar:IsShown()) then
    return
  end

  local powerType, maxPower, powerToken, powerMetaChanged, maxSecret
  local cacheUnit = unit
  local maxUnit = bar._msufPowerMaxUnit
  local sameMaxUnit = cacheUnit ~= nil and maxUnit == cacheUnit
  if bar._msufPowerMaxReady == true and sameMaxUnit then
    powerType = bar._msufPowerType
    maxPower = bar._msufPowerMax
    powerToken = bar._msufPowerToken
    maxSecret = bar._msufPowerMaxSecret == true
    powerMetaChanged = false
  else
    powerType, maxPower, powerToken, powerMetaChanged, maxSecret = ReadPowerMeta(frame, bar, unit, true)
  end

  local power
  if powerType ~= nil then
    power = UnitPower(unit, powerType)
  else
    power = UnitPower(unit)
  end
  power = power or 0

  if powerMetaChanged or bar._msufMinMaxInit ~= true then
    SetBarMinMaxPlain(bar, maxPower)
    bar._msufMinMaxInit = true
  end
  SetBarValuePlain(bar, power, true)

  if bar._msufStatusR == nil or powerMetaChanged then
    ApplyStatusColor(bar, PowerColor(frame, unit, powerType, powerToken, true))
  end
  return power, maxPower
end

function Power.UpdateValue(frame, event, unit)
  unit = unit or frame.unit
  local bar = frame.targetPowerBar
  if not bar or bar._msufShown == false or (bar._msufShown == nil and bar.IsShown and not bar:IsShown()) then
    return
  end

  local powerType, maxPower, powerToken, powerMetaChanged, maxSecret
  local cacheUnit = unit
  local maxUnit = bar._msufPowerMaxUnit
  local sameMaxUnit = cacheUnit ~= nil and maxUnit == cacheUnit
  if bar._msufPowerMaxReady == true and sameMaxUnit then
    powerType = bar._msufPowerType
    maxPower = bar._msufPowerMax
    powerToken = bar._msufPowerToken
    maxSecret = bar._msufPowerMaxSecret == true
    powerMetaChanged = false
  else
    powerType, maxPower, powerToken, powerMetaChanged, maxSecret = ReadPowerMeta(frame, bar, unit, true)
  end

  local power
  if powerType ~= nil then
    power = UnitPower(unit, powerType)
  else
    power = UnitPower(unit)
  end
  local powerSecret = issecretvalue(power) == true
  if not powerSecret and power == nil then power = 0 end

  if powerMetaChanged or bar._msufMinMaxInit ~= true then
    SetBarMinMaxKnown(bar, maxPower, maxSecret)
    bar._msufMinMaxInit = true
  end
  SetBarValueKnown(bar, power, powerSecret, true)

  if bar._msufStatusR == nil or powerMetaChanged then
    ApplyStatusColor(bar, PowerColor(frame, unit, powerType, powerToken, true))
  end
  return power, maxPower
end

function Power.Update(frame, event, unit)
  unit = unit or frame.unit
  local bar = frame.targetPowerBar
  if not bar or bar._msufShown == false or (bar._msufShown == nil and bar.IsShown and not bar:IsShown()) then
    return
  end

  local animate = event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT"
  local power, maxPower, powerType, powerToken, powerMetaChanged, powerSecret, maxSecret = ReadPowerValues(frame, bar, unit, event, animate)

  if not animate or powerMetaChanged or bar._msufMinMaxInit ~= true then
    SetBarMinMaxKnown(bar, maxPower, maxSecret)
    bar._msufMinMaxInit = true
  end
  SetBarValueKnown(bar, power, powerSecret, animate)
  if not animate then
    SnapBarInterpolation(bar)
  end

  if bar._msufStatusR == nil
    or powerMetaChanged
    or (not animate and (event == "UNIT_DISPLAYPOWER" or event == "MSUF_APPLY" or event == "MSUF_FORCE_UPDATE" or event == "MSUF_POWER_LAYOUT")) then
    ApplyStatusColor(bar, PowerColor(frame, unit, powerType, powerToken, true))
  end
  return power, maxPower
end

UF.RegisterElement("Power", Power)
