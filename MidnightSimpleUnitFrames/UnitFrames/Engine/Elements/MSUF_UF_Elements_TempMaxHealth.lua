local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}

local C = MSUF.UFBarTextCommon
local UF = C and C.UF or MSUF.UF
if not UF then return end

local CreateFrame = C and C.CreateFrame or CreateFrame
local GetUnitTotalModifiedMaxHealthPercent = _G.GetUnitTotalModifiedMaxHealthPercent
local WHITE = C and C.WHITE or "Interface\\Buttons\\WHITE8X8"

local TempMaxHealth = {}
local EVENTS = { "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" }
local EMPTY_EVENTS = {}
local TEST_VALUE = 0.20

local function Config(frame, spec)
  spec = spec or (frame and frame.MSUFSpec)
  return spec and spec.tempMaxHealth
end

local function SetTexture(bar, texture)
  texture = texture or WHITE
  if bar._msufTempMaxTexture ~= texture then
    bar:SetStatusBarTexture(texture)
    local bg = bar._msufTempMaxBackground
    local fill = bar:GetStatusBarTexture()
    if bg and fill then
      bg:ClearAllPoints()
      bg:SetAllPoints(fill)
    end
    bar._msufTempMaxTexture = texture
  end
end

local function SetColor(bar, cfg)
  local r = cfg and cfg.r or 0.70
  local g = cfg and cfg.g or 0.10
  local b = cfg and cfg.b or 0.10
  local a = cfg and cfg.a or 1
  if bar._msufTempMaxR ~= r or bar._msufTempMaxG ~= g
    or bar._msufTempMaxB ~= b or bar._msufTempMaxA ~= a then
    bar:SetStatusBarColor(r, g, b, a)
    bar._msufTempMaxR, bar._msufTempMaxG = r, g
    bar._msufTempMaxB, bar._msufTempMaxA = b, a
  end

  local bg = bar._msufTempMaxBackground
  local bgAlpha = cfg and cfg.backgroundAlpha or 0.65
  if bg and bg._msufTempMaxAlpha ~= bgAlpha then
    bg:SetColorTexture(0, 0, 0, bgAlpha)
    bg._msufTempMaxAlpha = bgAlpha
  end
end

local function Layout(frame, bar, spec)
  local hpBar = frame and (frame.hpBar or frame.Health)
  if not (bar and hpBar) then return end
  if bar._msufTempMaxAnchor ~= hpBar then
    bar:ClearAllPoints()
    bar:SetAllPoints(hpBar)
    bar._msufTempMaxAnchor = hpBar
  end

  local hpReverse = spec and spec.health and spec.health.reverse == true
  local reverse = not hpReverse
  if bar.SetReverseFill and bar._msufTempMaxReverse ~= reverse then
    bar:SetReverseFill(reverse)
    bar._msufTempMaxReverse = reverse
  end

  -- Match the health bar level. Prediction bars start at health + 1, keeping
  -- this loss overlay above health and deterministically below predictions.
  if bar.SetFrameLevel and hpBar.GetFrameLevel then
    local level = hpBar:GetFrameLevel()
    if bar._msufTempMaxLevel ~= level then
      bar:SetFrameLevel(level)
      bar._msufTempMaxLevel = level
    end
  end
end

function TempMaxHealth.IsEnabled(frame, spec)
  local cfg = Config(frame, spec)
  return cfg and cfg.enabled == true
    and (cfg.test == true or type(GetUnitTotalModifiedMaxHealthPercent) == "function")
end

function TempMaxHealth.Create(frame, spec)
  if not (frame and CreateFrame) or frame.tempMaxHealthBar then return end
  local hpBar = frame.hpBar or frame.Health
  if not hpBar then return end

  local bar = CreateFrame("StatusBar", nil, frame)
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(0)
  bar:SetStatusBarTexture(WHITE)
  if bar.EnableMouse then bar:EnableMouse(false) end

  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetColorTexture(0, 0, 0, 0.65)
  bg:SetAllPoints(bar:GetStatusBarTexture())
  bar._msufTempMaxBackground = bg

  frame.tempMaxHealthBar = bar
  frame.reducedMaxHealthBar = bar
  frame.tempMaxHealthBackground = bg
  Layout(frame, bar, spec)
  bar:Hide()
end

function TempMaxHealth.Apply(frame, spec)
  local bar = frame and frame.tempMaxHealthBar
  if not bar then
    TempMaxHealth.Create(frame, spec)
    bar = frame and frame.tempMaxHealthBar
  end
  if not bar then return end

  local cfg = Config(frame, spec)
  Layout(frame, bar, spec)
  SetTexture(bar, cfg and cfg.texture)
  SetColor(bar, cfg)
  bar:Show()
end

function TempMaxHealth.GetEvents(frame, spec)
  local cfg = Config(frame, spec)
  return cfg and cfg.test == true and EMPTY_EVENTS or EVENTS
end

function TempMaxHealth.Update(frame, event, unit, eventPercent)
  local bar = frame and frame.tempMaxHealthBar
  if not bar then return end
  local cfg = Config(frame)
  if cfg and cfg.test == true then
    bar:SetValue(TEST_VALUE)
    return
  end

  -- Midnight marks this event payload secret. Forward it straight into the
  -- native StatusBar without comparing, clamping, caching, or re-reading it.
  if event == "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then
    bar:SetValue(eventPercent)
    return
  end

  -- Cold seed path only: initial apply, OnShow, and unit identity changes.
  if GetUnitTotalModifiedMaxHealthPercent and unit then
    bar:SetValue(GetUnitTotalModifiedMaxHealthPercent(unit))
  else
    bar:SetValue(0)
  end
end

function TempMaxHealth.Disable(frame)
  local bar = frame and frame.tempMaxHealthBar
  if not bar then return end
  bar:SetValue(0)
  bar:Hide()
end

TempMaxHealth.UpdateOnApply = true

UF.RegisterElement("TempMaxHealth", TempMaxHealth)
