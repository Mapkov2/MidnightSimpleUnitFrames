local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}

local C = MSUF.UFBarTextCommon
local UF = C and C.UF or MSUF.UF
if not UF then return end

local CreateFrame = C and C.CreateFrame or CreateFrame
local UnitHealth = C and C.UnitHealth or UnitHealth
local UnitHealthMax = C and C.UnitHealthMax or UnitHealthMax
local UnitHealthPercent = C and C.UnitHealthPercent or UnitHealthPercent
local WHITE = C and C.WHITE or "Interface\\Buttons\\WHITE8X8"
local SCALE_100 = C and C.SCALE_100
local SetBarSmoothing = C and C.SetBarSmoothing
local ApplyHealthStatusColor = C and C.ApplyHealthStatusColor
local issecretvalue = _G.issecretvalue or function(_) return false end
local ExportPublic = MSUF.ExportPublic or function(name, value)
  _G[name] = value
  return value
end

local Health = {}
local EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH" }
local STATUS_COLOR_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION", "UNIT_FLAGS" }
local PLAYER_STATUS_COLOR_EVENTS = { "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }
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

local function SetTexture(bar, texture)
  if not bar then return end
  if bar._msufTexture ~= texture then
    bar:SetStatusBarTexture(texture or WHITE)
    bar._msufTexture = texture or WHITE
  end
end

local function SetColor(frame, force)
  local bar = frame and frame.hpBar
  if not bar then return end
  local health = frame.MSUFSpec and frame.MSUFSpec.health or nil
  local r = health and health.r or 0.1
  local g = health and health.g or 0.75
  local b = health and health.b or 0.1
  local a = health and health.alpha or 1
  if force or bar._msufR ~= r or bar._msufG ~= g or bar._msufB ~= b or bar._msufA ~= a then
    bar:SetStatusBarColor(r, g, b, a)
    bar._msufR, bar._msufG, bar._msufB, bar._msufA = r, g, b, a
    bar._msufStatusR, bar._msufStatusG, bar._msufStatusB, bar._msufStatusA = nil, nil, nil, nil
  end
  frame._msufHealthStatusGone = nil
  local bg = frame.hpBarBG or frame.bg
  if bg then
    local ba = frame.MSUFSpec and frame.MSUFSpec.backgroundAlpha or 0.72
    if bg._msufA ~= ba then
      bg:SetColorTexture(0.02, 0.02, 0.025, ba)
      bg._msufA = ba
    end
  end
end

local function RuntimeColorEnabled(frame)
  local health = frame and frame.MSUFSpec and frame.MSUFSpec.health
  local mode = health and health.mode
  return mode ~= "dark" and mode ~= "unified"
end

local function RuntimeColorEnabledForSpec(spec)
  local health = spec and spec.health
  local mode = health and health.mode
  return mode ~= "dark" and mode ~= "unified"
end

local function RuntimeColorOnHealth(frame)
  local health = frame and frame.MSUFSpec and frame.MSUFSpec.health
  return health and health.mode == "gradient"
end

local function RuntimeColorOnHealthEvent(frame, value)
  if RuntimeColorOnHealth(frame) then
    return true
  end
  if frame and frame._msufHealthStatusGone == true then
    return true
  end
  if issecretvalue(value) == true then
    return false
  end
  return type(value) == "number" and value <= 0
end

local function ApplyRuntimeColor(frame, event, unit, hp, maxHP)
  local bar = frame and frame.hpBar
  if not (bar and ApplyHealthStatusColor and RuntimeColorEnabled(frame)) then
    return false
  end
  if maxHP == nil and type(hp) == "number" then
    maxHP = 100
  end
  ApplyHealthStatusColor(bar, frame, unit or frame.unit, hp, maxHP, nil, event)
  return true
end

function Health.Create(frame, spec)
  if frame.hpBar then return end
  local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
  bg:SetAllPoints(frame)
  bg:SetColorTexture(0.02, 0.02, 0.025, spec and spec.backgroundAlpha or 0.72)
  frame.bg = bg
  frame.hpBarBG = bg
  frame.healthBg = bg

  local bar = CreateFrame("StatusBar", nil, frame)
  bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  bar:SetMinMaxValues(0, 100)
  bar:SetValue(100)
  bar:SetStatusBarTexture((spec and spec.texture) or WHITE)
  frame.hpBar = bar
  frame.Health = bar
  frame.health = bar
end

function Health.Apply(frame, spec)
  if not frame.hpBar then Health.Create(frame, spec) end
  frame.Health = frame.hpBar
  frame.health = frame.hpBar
  frame.healthBg = frame.hpBarBG or frame.bg
  frame._msufIsGroupFrame = spec and spec.scope == "group" or nil
  local h = spec and spec.health or nil
  SetTexture(frame.hpBar, h and h.texture or spec and spec.texture or WHITE)
  if frame.hpBar.SetReverseFill then
    local reverse = h and h.reverse == true
    if frame.hpBar._msufReverseFill ~= reverse then
      frame.hpBar:SetReverseFill(reverse)
      frame.hpBar._msufReverseFill = reverse
    end
  end
  frame.hpBar._msufMinMax = nil
  frame.hpBar._msufHealthValue = nil
  frame.hpBar._msufHealthMax = nil
  frame.hpBar._msufHealthValueUnit = nil
  frame.hpBar._msufHealthMaxUnit = nil
  frame.hpBar._msufHealthMaxReady = nil
  frame.hpBar._msufHealthPercentValue = nil
  if SetBarSmoothing then SetBarSmoothing(frame.hpBar, h and h.smooth == true) end
  SetColor(frame, true)
  ApplyRuntimeColor(frame, "MSUF_COLOR_CHANGE", frame.unit)
end

function Health.GetEvents(frame, spec)
  return RuntimeColorEnabledForSpec(spec) and STATUS_COLOR_EVENTS or EVENTS
end

function Health.GetUnitlessEvents(frame, spec)
  if frame and frame.unit == "player" and RuntimeColorEnabledForSpec(spec) then
    return PLAYER_STATUS_COLOR_EVENTS
  end
  return nil
end

local function UpdatePercent(frame, unit)
  if not (UnitHealthPercent and SCALE_100) then return false end
  local pct = UnitHealthPercent(unit, true, SCALE_100)
  local secret = issecretvalue(pct) == true
  if not secret and pct == nil then pct = 0 end
  if not secret and not IsFiniteNumber(pct) then pct = 0 end
  local bar = frame.hpBar
  if bar._msufMinMax ~= 100 then
    bar:SetMinMaxValues(0, 100)
    bar._msufMinMax = 100
  end
  if secret or bar._msufHealthPercentValue ~= pct then
    local interp = bar._msufSmoothInterp
    if interp then
      bar:SetValue(pct, interp)
      bar._msufInterpolating = true
    else
      bar:SetValue(pct)
    end
    bar._msufHealthPercentValue = secret and nil or pct
  end
  bar._msufHealthValue = nil
  bar._msufHealthValueUnit = nil
  bar._msufHealthMax = nil
  bar._msufHealthMaxUnit = nil
  bar._msufHealthMaxReady = nil
  local rt = frame._msufTextRuntime
  if rt and rt.healthNeedsPercent == true then
    rt._dispatchHealthPercent = pct
    rt._dispatchHealthPercentReady = true
  end
  return true, pct, nil, true
end

local function UpdateAbsolute(frame, unit)
  local hp = UnitHealth and UnitHealth(unit) or 0
  local hpSecret = issecretvalue(hp) == true
  local maxHP = UnitHealthMax and UnitHealthMax(unit) or 1
  local maxSecret = issecretvalue(maxHP) == true
  if not hpSecret then
    hp = hp or 0
    if not IsFiniteNumber(hp) then hp = 0 end
  end
  if not maxSecret then
    maxHP = maxHP or 1
    if not IsFiniteNumber(maxHP) or maxHP <= 0 then maxHP = 1 end
  end
  local bar = frame.hpBar
  if maxSecret or bar._msufMinMax ~= maxHP then
    bar:SetMinMaxValues(0, maxHP)
    bar._msufMinMax = maxSecret and nil or maxHP
  end
  if hpSecret or bar._msufHealthValue ~= hp or bar._msufHealthValueUnit ~= unit then
    local interp = bar._msufSmoothInterp
    if interp then
      bar:SetValue(hp, interp)
      bar._msufInterpolating = true
    else
      bar:SetValue(hp)
    end
  end
  bar._msufHealthValue = hpSecret and nil or hp
  bar._msufHealthValueUnit = hpSecret and nil or unit
  bar._msufHealthMax = maxSecret and nil or maxHP
  bar._msufHealthMaxUnit = maxSecret and nil or unit
  bar._msufHealthMaxReady = maxSecret and nil or true
  bar._msufHealthPercentValue = nil
  return hp, maxHP, false
end

function Health.Update(frame, event, unit)
  unit = unit or frame.unit
  if not (frame and frame.hpBar and unit) then return end
  local ok, pct, maxValue, percentReady = UpdatePercent(frame, unit)
  if ok then
    if event ~= "UNIT_HEALTH" or IDENTITY_EVENTS[event] == true or RuntimeColorOnHealthEvent(frame, pct) then
      if not ApplyRuntimeColor(frame, event, unit, pct, 100) then
        SetColor(frame)
      end
    end
    return pct, maxValue, percentReady
  end
  local hp, maxHP, absolutePercentReady = UpdateAbsolute(frame, unit)
  if event ~= "UNIT_HEALTH" or IDENTITY_EVENTS[event] == true or RuntimeColorOnHealthEvent(frame, hp) then
    if not ApplyRuntimeColor(frame, event, unit, hp, maxHP) then
      SetColor(frame)
    end
  end
  return hp, maxHP, absolutePercentReady
end

Health.UpdateValue = Health.Update
Health.UpdateValuePlain = Health.Update
Health.UpdateValueStatic = Health.Update
Health.UpdateValueStaticPlain = Health.Update
Health.UpdateValueGroupStatic = Health.Update
Health.UpdateValueGroupPercent = Health.Update
Health.UpdateValuePercent = Health.Update
Health.UpdateMaxValue = Health.Update
Health.UpdateMaxValuePlain = Health.Update
Health.UpdateMaxValueStatic = Health.Update
Health.UpdateMaxValueStaticPlain = Health.Update
Health.UpdateConnectionState = Health.Update
Health.UpdateIdentityColor = Health.Update
function Health.SelectGroupHealthUpdater() return nil end

function Health.RefreshColor(frameOrUnit, event)
  local frame = frameOrUnit
  if type(frameOrUnit) == "string" then
    frame = UF.frames and UF.frames[frameOrUnit]
  end
  if not (frame and frame.hpBar) then return false end
  if ApplyRuntimeColor(frame, event or "MSUF_COLOR_CHANGE", frame.unit) then
    return true
  end
  SetColor(frame, true)
  return true
end

ExportPublic("MSUF_UFCore_RefreshHealthBarColor", Health.RefreshColor)

UF.RegisterElement("Health", Health)
