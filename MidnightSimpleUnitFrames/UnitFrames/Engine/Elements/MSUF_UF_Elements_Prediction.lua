--- UnitFrames/Engine/Elements/MSUF_UF_Elements_Prediction.lua
--- Heal/absorb prediction element for unitframes.
---
--- WoW prediction APIs can return unknown/secret values during protected states;
--- this file clamps and hides uncertain bars instead of caching unsafe math.

local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}

local UF = MSUF.UF
local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitIsConnected = UnitIsConnected
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitGetIncomingHeals = _G.UnitGetIncomingHeals
local UnitGetTotalAbsorbs = _G.UnitGetTotalAbsorbs
local UnitGetTotalHealAbsorbs = _G.UnitGetTotalHealAbsorbs
local CreateUnitHealPredictionCalculator = _G.CreateUnitHealPredictionCalculator
local UnitGetDetailedHealPrediction = _G.UnitGetDetailedHealPrediction
local tonumber = tonumber
local type = type
local Enum = _G.Enum
local UnitMissing
do
  local issv = _G.issecretvalue or function(_) return false end
  UnitMissing = function(frame, unit)
    if issv(unit) == true then
      return false
    end
    local state = frame and frame._msufUnitState
    if state
      and state.ready == true
      and issv(unit) ~= true
      and issv(state.unit) ~= true
      and state.unit == unit
      and state.existsKnown == true then
      return state.exists == false
    end
    if not UnitExists then
      return false
    end
    local exists = UnitExists(unit)
    if issv(exists) == true then
      return false
    end
    return exists == false or exists == 0
  end
end
local issecretvalue = _G.issecretvalue or function(_) return false end

-- Heal/absorb prediction element.
-- Owns incoming heal, absorb, and heal-absorb overlays for unitframes. The code supports
-- both modern detailed prediction APIs and older fallbacks, and it must tolerate secret unit
-- tokens without leaking or doing math on protected values.
local WHITE = "Interface\\Buttons\\WHITE8x8"
local UnitIncomingHealClampMode = Enum and Enum.UnitIncomingHealClampMode
local UnitDamageAbsorbClampMode = Enum and Enum.UnitDamageAbsorbClampMode
local UnitHealAbsorbClampMode = Enum and Enum.UnitHealAbsorbClampMode
local UnitHealAbsorbMode = Enum and Enum.UnitHealAbsorbMode
local INCOMING_MISSING = UnitIncomingHealClampMode and UnitIncomingHealClampMode.MissingHealth or 0
local INCOMING_MAX = UnitIncomingHealClampMode and UnitIncomingHealClampMode.MaximumHealth or 1
local ABSORB_MISSING = UnitDamageAbsorbClampMode and UnitDamageAbsorbClampMode.MissingHealthWithoutIncomingHeals or 1
local ABSORB_MAX = UnitDamageAbsorbClampMode and UnitDamageAbsorbClampMode.MaximumHealth or 2
local HEAL_ABSORB_CURRENT = UnitHealAbsorbClampMode and UnitHealAbsorbClampMode.CurrentHealth or 0
local HEAL_ABSORB_TOTAL = UnitHealAbsorbMode and UnitHealAbsorbMode.Total or 1
local TEST_MAX = 100
local TEST_INCOMING = 20
local TEST_ABSORB = 25
local TEST_HEAL_ABSORB = 15
local EMPTY_EVENTS = {}
local DERIVED_PREDICTION_TARGET_EVENTS = { "UNIT_TARGET" }
local PREDICTION_EVENT_BITS = {
  { 1, "UNIT_HEAL_PREDICTION" },
  { 2, "UNIT_ABSORB_AMOUNT_CHANGED" },
  { 4, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" },
}

local function BuildPredictionEventTable(healthAware, includeConnection)
  -- Specs opt into only the prediction pieces they display. Build the event lists from bit
  -- masks once so runtime registration stays compact even with several overlay combinations.
  local out = {}
  for mask = 1, 7 do
    local events = {}
    if healthAware then events[#events + 1] = "UNIT_HEALTH" end
    for i = 1, #PREDICTION_EVENT_BITS do
      local bit = PREDICTION_EVENT_BITS[i][1]
      if (mask % (bit * 2)) >= bit then
        events[#events + 1] = PREDICTION_EVENT_BITS[i][2]
      end
    end
    events[#events + 1] = "UNIT_MAXHEALTH"
    if includeConnection then events[#events + 1] = "UNIT_CONNECTION" end
    out[mask] = events
  end
  return out
end

local PREDICTION_EVENTS = BuildPredictionEventTable(false, true)
local PREDICTION_HEALTH_EVENTS = BuildPredictionEventTable(true, true)
local PREDICTION_EVENTS_PLAYER = BuildPredictionEventTable(false, false)
local PREDICTION_HEALTH_EVENTS_PLAYER = BuildPredictionEventTable(true, false)

local PLAN_REFRESH_HEAL = 1
local PLAN_REFRESH_ABSORB = 2
local PLAN_REFRESH_HEAL_ABSORB = 3
local PLAN_SHOW_HEAL = 4
local PLAN_SHOW_ABSORB = 5
local PLAN_SHOW_HEAL_ABSORB = 6
local PLAN_FORCE_MAX = 7
local PLAN_NEED_HP = 8
local PLAN_NEED_MAX_HP = 9

local GATED_PREDICTION_EVENTS = {
  UNIT_HEAL_PREDICTION = true,
  UNIT_ABSORB_AMOUNT_CHANGED = true,
  UNIT_HEAL_ABSORB_AMOUNT_CHANGED = true,
  UNIT_HEALTH = true,
}

local DEFERRED_PREDICTION_EVENT_BITS = {
  UNIT_HEAL_PREDICTION = 1,
  UNIT_ABSORB_AMOUNT_CHANGED = 2,
  UNIT_HEAL_ABSORB_AMOUNT_CHANGED = 4,
}

local PREDICTION_FLUSH_EVENT = "MSUF_PREDICTION_FLUSH"
local calcUnsupported
local BAR_VALUE_CACHE_FIELDS = { "_msufMaxReady", "_msufMaxPlain", "_msufValuePlain" }
local PREDICTION_DISABLE_FIELDS = {
  "_msufPredictionNeedsHealth",
  "_msufPredictionHealActive",
  "_msufPredictionAbsorbActive",
  "_msufPredictionHealAbsorbActive",
  "_msufPredictionAbsorbOnly",
  "_msufPredictionEventPlans",
  "_msufPredictionFullPlan",
  "_msufPredictionConnectionUnit",
  "_msufPredictionConnectionOnline",
  "_msufPredictionRuntimeCfg",
  "_msufPredictionFrameWidth",
  "_msufPredictionHpReverse",
  "_msufPredictionHealMode",
  "_msufPredictionAbsorbMode",
  "_msufPredictionHealReverse",
  "_msufPredictionAbsorbReverse",
  "_msufPredictionFollowAbsorb",
  "_msufPredictionClampHealToMissing",
  "_msufPredictionClampAbsorbToMissing",
  "_msufPredictionQueuedUnit",
  "_msufPredictionFlushing",
  "_msufUpdatePredictionHealthValue",
  "_msufUpdatePredictionConnectionState",
  "_msufQueuePredictionUpdate",
  "_msufQueuePredictionBit",
}

local function SetTextureCached(bar, texture)
  texture = texture or WHITE
  if bar and (bar._msufTexture ~= texture or bar.MSUF_cachedStatusbarTexture ~= texture) then
    bar:SetStatusBarTexture(texture)
    bar._msufTexture = texture
    bar.MSUF_cachedStatusbarTexture = texture
    bar._msufPredictionStatusTexture = nil
  end
end

local function SetColorCached(bar, r, g, b, a)
  r, g, b, a = r or 1, g or 1, b or 1, a or 1
  if bar and (bar._msufR ~= r or bar._msufG ~= g or bar._msufB ~= b or bar._msufA ~= a) then
    bar:SetStatusBarColor(r, g, b, a)
    bar._msufR, bar._msufG, bar._msufB, bar._msufA = r, g, b, a
  end
end

local function NormalizeAnchorMode(mode, fallback)
  mode = tonumber(mode) or fallback or 2
  if mode < 1 or mode > 5 then
    return fallback or 2
  end
  return mode
end

local function AnchorModeReverse(mode, hpReverse)
  if mode == 1 then
    return false
  elseif mode == 5 then
    return hpReverse ~= true
  end
  return true
end

local function FollowModeReverse(hpReverse)
  return hpReverse == true
end

local function ReverseForMode(mode, hpReverse)
  if mode == 3 or mode == 4 then
    return FollowModeReverse(hpReverse)
  end
  return AnchorModeReverse(mode, hpReverse)
end

local function ClampModeForAnchor(mode)
  if mode == 4 or mode == 1 or mode == 2 or mode == 5 then
    return ABSORB_MAX
  end
  return ABSORB_MISSING
end

local function IncomingClampModeForAnchor(mode)
  if mode == 1 or mode == 2 or mode == 4 or mode == 5 then
    return INCOMING_MAX
  end
  return INCOMING_MISSING
end

local function HideBar(bar)
  if not bar then
    return
  end
  if bar._msufMaxReady ~= true or bar._msufMaxPlain ~= true or bar._msufMax ~= 1 then
    bar:SetMinMaxValues(0, 1)
    bar._msufMax = 1
    bar._msufMaxPlain = true
    bar._msufMaxReady = true
    bar._msufValue = nil
    bar._msufValuePlain = nil
  end
  if bar._msufValuePlain ~= true or bar._msufValue ~= 0 then
    bar:SetValue(0)
    bar._msufValue = 0
    bar._msufValuePlain = true
  end
  if bar._msufShown ~= false then
    bar:SetShown(false)
    bar._msufShown = false
  end
end

local function CachedHealthMax(frame, unit)
  local hpBar = frame and (frame.hpBar or frame.Health)
  local cachedUnit = hpBar and hpBar._msufHealthMaxUnit
  if hpBar
    and hpBar._msufHealthMaxReady == true
    and cachedUnit == unit then
    return hpBar._msufHealthMax
  end
  return nil
end

local function CachedHealthValue(frame, unit)
  local hpBar = frame and (frame.hpBar or frame.Health)
  local cachedUnit = hpBar and hpBar._msufHealthValueUnit
  if hpBar and cachedUnit == unit then
    return hpBar._msufHealthValue
  end
  return nil
end

local function CachedHealthValues(frame, unit)
  return CachedHealthValue(frame, unit), CachedHealthMax(frame, unit)
end

local function ReadHealthMax(frame, unit)
  local maxHP = CachedHealthMax(frame, unit)
  if issecretvalue(maxHP) ~= true and maxHP == nil and UnitHealthMax then
    maxHP = UnitHealthMax(unit)
  end
  return maxHP
end

local function ShowValue(bar, maxValue, value, forceMax)
  local valueSecret = issecretvalue(value) == true
  if not bar or (not valueSecret and value == nil) then
    HideBar(bar)
    return
  end

  if not valueSecret then
    local valueType = type(value)
    if valueType == "number" then
      if value <= 0 then
        HideBar(bar)
        return
      end
    elseif (tonumber(value) or 0) <= 0 then
      HideBar(bar)
      return
    end
  end

  local maxReady = bar._msufMaxReady == true
  local needMax = forceMax == true or not maxReady
  local maxSecret = issecretvalue(maxValue) == true
  if maxSecret or maxValue ~= nil then -- not IsNil(maxValue)
    if maxSecret or needMax or bar._msufMaxPlain ~= true or bar._msufMax ~= maxValue then
      bar:SetMinMaxValues(0, maxValue)
      if maxSecret then
        bar._msufMax = nil
        bar._msufMaxPlain = nil
      else
        bar._msufMax = maxValue
        bar._msufMaxPlain = true
      end
      bar._msufMaxReady = true
      bar._msufValue = nil
      bar._msufValuePlain = nil
    end
  elseif needMax then
    bar:SetMinMaxValues(0, 1)
    bar._msufMax = 1
    bar._msufMaxPlain = true
    bar._msufMaxReady = true
    bar._msufValue = nil
    bar._msufValuePlain = nil
  end

  if valueSecret or bar._msufValuePlain ~= true or bar._msufValue ~= value then
    bar:SetValue(value)
    if valueSecret then
      bar._msufValue = nil
      bar._msufValuePlain = nil
    else
      bar._msufValue = value
      bar._msufValuePlain = true
    end
  end

  if bar._msufShown ~= true then
    bar:SetShown(true)
    bar._msufShown = true
  end
end

local function EnsureCalc(frame)
  if calcUnsupported then
    return nil
  end
  local calc = frame._msufPredictionCalc
  if calc then
    return calc
  end
  if not (CreateUnitHealPredictionCalculator and UnitGetDetailedHealPrediction) then
    calcUnsupported = true
    return nil
  end
  calc = CreateUnitHealPredictionCalculator()
  if not calc then
    calcUnsupported = true
    return nil
  end
  if calc.SetIncomingHealOverflowPercent then
    calc:SetIncomingHealOverflowPercent(1)
  end
  frame._msufPredictionCalc = calc
  return calc
end

local function ConfigureCalc(calc, cfg)
  if not calc then
    return
  end
  local healMode = NormalizeAnchorMode(cfg and cfg.healAnchorMode, 3)
  local absorbMode = NormalizeAnchorMode(cfg and cfg.absorbAnchorMode, 2)
  local incomingClamp = IncomingClampModeForAnchor(healMode)
  local damageClamp = ClampModeForAnchor(absorbMode)

  if calc.SetIncomingHealClampMode and calc._msufIncomingClamp ~= incomingClamp then
    calc:SetIncomingHealClampMode(incomingClamp)
    calc._msufIncomingClamp = incomingClamp
  end
  if calc.SetDamageAbsorbClampMode and calc._msufDamageClamp ~= damageClamp then
    calc:SetDamageAbsorbClampMode(damageClamp)
    calc._msufDamageClamp = damageClamp
  end
  if calc.SetHealAbsorbClampMode and calc._msufHealAbsorbClamp ~= HEAL_ABSORB_CURRENT then
    calc:SetHealAbsorbClampMode(HEAL_ABSORB_CURRENT)
    calc._msufHealAbsorbClamp = HEAL_ABSORB_CURRENT
  end
  if calc.SetHealAbsorbMode and calc._msufHealAbsorbMode ~= HEAL_ABSORB_TOTAL then
    calc:SetHealAbsorbMode(HEAL_ABSORB_TOTAL)
    calc._msufHealAbsorbMode = HEAL_ABSORB_TOTAL
  end
  calc._msufPredictionCfg = cfg
end

local function UpdateCalc(frame, unit, cfg)
  local calc = EnsureCalc(frame)
  if not calc then
    return nil
  end
  if calc._msufPredictionCfg ~= cfg then
    ConfigureCalc(calc, cfg)
  end
  UnitGetDetailedHealPrediction(unit, nil, calc)
  return calc
end

local function CalcIncomingHeals(calc, unit)
  if calc and calc.GetIncomingHeals then
    local value = calc:GetIncomingHeals()
    if issecretvalue(value) == true or value ~= nil then
      return value
    end
  end
  if calc and calc.GetTotalIncomingHeals then
    local value = calc:GetTotalIncomingHeals()
    if issecretvalue(value) == true or value ~= nil then
      return value
    end
  end
  return UnitGetIncomingHeals and UnitGetIncomingHeals(unit) or nil
end

local function CalcDamageAbsorbs(calc, unit)
  if calc then
    if calc.GetDamageAbsorbs then
      local value = calc:GetDamageAbsorbs()
      if issecretvalue(value) == true or value ~= nil then return value end
    end
    if calc.GetTotalDamageAbsorbs then
      local value = calc:GetTotalDamageAbsorbs()
      if issecretvalue(value) == true or value ~= nil then return value end
    end
  end
  return UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or nil
end

local function CalcHealAbsorbs(calc, unit)
  if calc then
    if calc.GetHealAbsorbs then
      local value = calc:GetHealAbsorbs()
      if issecretvalue(value) == true or value ~= nil then return value end
    end
    if calc.GetTotalHealAbsorbs then
      local value = calc:GetTotalHealAbsorbs()
      if issecretvalue(value) == true or value ~= nil then return value end
    end
  end
  return UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit) or nil
end

local function ClampIncomingToMissing(value, hp, maxHP)
  if issecretvalue(value) == true or issecretvalue(hp) == true or issecretvalue(maxHP) == true then
    return value
  end
  if type(value) ~= "number" or type(hp) ~= "number" or type(maxHP) ~= "number" then
    return value
  end
  local missing = maxHP - hp
  if missing <= 0 then
    return 0
  end
  if value > missing then
    return missing
  end
  return value
end

local function ReadIncomingHeals(calc, unit, hp, maxHP, healMode)
  local value = CalcIncomingHeals(calc, unit)
  if not calc and healMode == 3 then
    value = ClampIncomingToMissing(value, hp, maxHP)
  end
  return value
end

local function ReadDamageAbsorbs(calc, unit, hp, maxHP, absorbMode)
  local value = CalcDamageAbsorbs(calc, unit)
  if not calc and absorbMode == 3 then
    value = ClampIncomingToMissing(value, hp, maxHP)
  end
  return value
end

local function ClampToValue(value, maxValue)
  if issecretvalue(value) == true or issecretvalue(maxValue) == true then
    return value
  end
  if type(value) ~= "number" or type(maxValue) ~= "number" then
    return value
  end
  if value > maxValue then
    return maxValue
  end
  return value
end

local function ReadHealAbsorbs(calc, unit, hp)
  local value = CalcHealAbsorbs(calc, unit)
  if not calc then
    value = ClampToValue(value, hp)
  end
  return value
end

local function ResolveTexture(key, fallback)
  if type(key) == "string" and key ~= "" then
    local resolve = _G.MSUF_ResolveStatusbarTextureKey
    if type(resolve) == "function" then
      return resolve(key) or fallback
    end
    return key
  end
  return fallback
end

local function EnsureBar(frame, key, levelOffset)
  local bar = frame[key]
  local hpBar = frame.hpBar or frame.Health
  if bar then
    return bar
  end
  bar = CreateFrame("StatusBar", nil, frame)
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(0)
  bar._msufMax = 1
  bar._msufMaxPlain = true
  bar._msufMaxReady = true
  bar._msufValue = 0
  bar._msufValuePlain = true
  bar:SetStatusBarTexture(WHITE)
  bar:SetAllPoints(hpBar or frame)
  if bar.SetFrameLevel and hpBar and hpBar.GetFrameLevel then
    local level = (hpBar:GetFrameLevel() or frame:GetFrameLevel() or 1) + levelOffset
    bar:SetFrameLevel(level)
    bar._msufFrameLevel = level
  end
  bar:Hide()
  frame[key] = bar
  return bar
end

local function SyncBarLayer(frame, hpBar, bar, levelOffset)
  if not (frame and hpBar and bar) then
    return
  end
  if bar.SetFrameStrata and frame.GetFrameStrata then
    local strata = frame:GetFrameStrata()
    if strata and bar._msufFrameStrata ~= strata then
      bar:SetFrameStrata(strata)
      bar._msufFrameStrata = strata
    end
  end
  if bar.SetFrameLevel and hpBar.GetFrameLevel then
    local level = (hpBar:GetFrameLevel() or frame:GetFrameLevel() or 1) + levelOffset
    if bar._msufFrameLevel ~= level then
      bar:SetFrameLevel(level)
      bar._msufFrameLevel = level
    end
  end
end

local function StatusTexture(bar)
  if not (bar and bar.GetStatusBarTexture) then
    return nil
  end
  local tex = bar._msufPredictionStatusTexture
  if not tex then
    tex = bar:GetStatusBarTexture()
    bar._msufPredictionStatusTexture = tex
  end
  return tex
end

local function VisibleFollowBar(cfg, bar)
  return cfg and cfg.heal == true and bar and bar._msufShown == true and bar or nil
end

local function SetParentCached(bar, parent)
  if not (bar and parent and bar.GetParent) then
    return false
  end
  if bar:GetParent() == parent then
    return false
  end
  bar:SetParent(parent)
  return true
end

local function LayoutBar(frame, bar, levelOffset, mode, reverse, followBar)
  local hpBar = frame.hpBar or frame.Health
  if not (bar and hpBar) then
    return
  end
  mode = NormalizeAnchorMode(mode, 2)
  local followSource = (mode == 3 or mode == 4) and followBar or nil
  local follow = (mode == 3 or mode == 4) and (followSource and StatusTexture(followSource) or StatusTexture(hpBar)) or nil
  local runtimeWidth = tonumber(frame._msufPredictionFrameWidth)
  local width = (hpBar.GetWidth and hpBar:GetWidth()) or runtimeWidth or 1
  if not width or width <= 0 then
    width = runtimeWidth or 1
  end
  local anchorTarget = follow or hpBar
  local parent = (mode == 4) and frame or hpBar

  if bar._msufPredictionMode == mode
    and bar._msufPredictionReverse == reverse
    and bar._msufPredictionFollowBar == followSource
    and bar._msufPredictionAnchorTarget == anchorTarget
    and bar._msufPredictionWidth == width
    and bar._msufPredictionParent == parent
    and bar._msufPredictionLevelOffset == levelOffset
    and bar._msufReverseFill == reverse then
    return
  end

  SyncBarLayer(frame, hpBar, bar, levelOffset)
  local parentChanged = SetParentCached(bar, parent)
  if hpBar.SetClipsChildren and mode == 3 and hpBar._msufPredictionClipsChildren ~= true then
    hpBar:SetClipsChildren(true)
    hpBar._msufPredictionClipsChildren = true
  end
  if bar._msufPredictionMode ~= mode
    or bar._msufPredictionReverse ~= reverse
    or bar._msufPredictionFollowBar ~= followSource
    or bar._msufPredictionAnchorTarget ~= anchorTarget
    or bar._msufPredictionWidth ~= width
    or bar._msufPredictionParent ~= parent
    or bar._msufPredictionLevelOffset ~= levelOffset
    or parentChanged then
    bar:ClearAllPoints()
    if follow then
      bar:SetWidth(width)
      if reverse then
        bar:SetPoint("TOPRIGHT", follow, "TOPLEFT", 0, 0)
        bar:SetPoint("BOTTOMRIGHT", follow, "BOTTOMLEFT", 0, 0)
      else
        bar:SetPoint("TOPLEFT", follow, "TOPRIGHT", 0, 0)
        bar:SetPoint("BOTTOMLEFT", follow, "BOTTOMRIGHT", 0, 0)
      end
    else
      bar:SetAllPoints(hpBar)
    end
    bar._msufPredictionMode = mode
    bar._msufPredictionReverse = reverse
    bar._msufPredictionFollowBar = followSource
    bar._msufPredictionAnchorTarget = anchorTarget
    bar._msufPredictionWidth = width
    bar._msufPredictionParent = parent
    bar._msufPredictionLevelOffset = levelOffset
  end
  if bar.SetReverseFill and bar._msufReverseFill ~= reverse then
    bar:SetReverseFill(reverse)
    bar._msufReverseFill = reverse
  end
end

local function PredictionLayoutCurrent(frame, bar, levelOffset, mode, reverse, followBar)
  local hpBar = frame and (frame.hpBar or frame.Health)
  if not (bar and hpBar) then
    return false
  end
  mode = NormalizeAnchorMode(mode, 2)
  local followSource = (mode == 3 or mode == 4) and followBar or nil
  local parent = (mode == 4) and frame or hpBar
  local width = tonumber(frame._msufWidth) or tonumber(frame._msufPredictionFrameWidth)
  return bar._msufPredictionMode == mode
    and bar._msufPredictionReverse == reverse
    and bar._msufPredictionFollowBar == followSource
    and (not width or width <= 0 or bar._msufPredictionWidth == width)
    and bar._msufPredictionParent == parent
    and bar._msufPredictionLevelOffset == levelOffset
    and bar._msufReverseFill == reverse
end

local function LayoutBarIfNeeded(frame, bar, levelOffset, mode, reverse, followBar, force)
  if not force and PredictionLayoutCurrent(frame, bar, levelOffset, mode, reverse, followBar) then
    return
  end
  LayoutBar(frame, bar, levelOffset, mode, reverse, followBar)
end

local function NeedsHealthEvent(cfg)
  if not cfg then
    return false
  end
  if cfg.heal == true and NormalizeAnchorMode(cfg.healAnchorMode, 3) == 3 then
    return true
  end
  return false
end

local function PredictionMask(cfg)
  if not (cfg and cfg.enabled == true) or cfg.test == true then
    return 0
  end
  return (cfg.heal == true and 1 or 0)
    + (cfg.absorb == true and 2 or 0)
    + (cfg.healAbsorb == true and 4 or 0)
end

local function PredictionPlan(refreshHeal, refreshAbsorb, refreshHealAbsorb, showHeal, showAbsorb, showHealAbsorb, forceMax, needHP, needMaxHP)
  return {
    refreshHeal or nil,
    refreshAbsorb or nil,
    refreshHealAbsorb or nil,
    showHeal or nil,
    showAbsorb or nil,
    showHealAbsorb or nil,
    forceMax or nil,
    needHP or nil,
    needMaxHP or nil,
  }
end

local predictionPlanCache = {}

local function PredictionPlanCacheKey(heal, absorb, healAbsorb, clampHeal, clampAbsorb, followAbsorb)
  return (heal and 1 or 0)
    + (absorb and 2 or 0)
    + (healAbsorb and 4 or 0)
    + (clampHeal and 8 or 0)
    + (clampAbsorb and 16 or 0)
    + (followAbsorb and 32 or 0)
end

local function CompilePredictionPlans(cfg, healMode, absorbMode, followAbsorb)
  local heal = cfg and cfg.heal == true
  local absorb = cfg and cfg.absorb == true
  local healAbsorb = cfg and cfg.healAbsorb == true
  local clampHeal = heal and healMode == 3
  local clampAbsorb = absorb and absorbMode == 3
  local key = PredictionPlanCacheKey(heal, absorb, healAbsorb, clampHeal, clampAbsorb, followAbsorb)
  local cached = predictionPlanCache[key]
  if cached then
    return cached[1], cached[2]
  end
  local plans = {}

  if heal then
    plans.UNIT_HEAL_PREDICTION = PredictionPlan(true, nil, nil, true, followAbsorb, nil, nil, clampHeal, clampHeal)
  end
  if absorb then
    plans.UNIT_ABSORB_AMOUNT_CHANGED = PredictionPlan(nil, true, nil, nil, true, nil, nil, clampAbsorb, clampAbsorb)
  end
  if healAbsorb then
    plans.UNIT_HEAL_ABSORB_AMOUNT_CHANGED = PredictionPlan(nil, nil, true, nil, nil, true, nil, true, nil)
  end
  if clampHeal then
    plans.UNIT_HEALTH = PredictionPlan(nil, nil, nil, true, followAbsorb, nil, nil, true, true)
  end
  if heal or absorb or healAbsorb then
    plans.UNIT_MAXHEALTH = PredictionPlan(clampHeal, clampAbsorb, nil, heal, absorb, healAbsorb, true, clampHeal or clampAbsorb or healAbsorb, heal or absorb or healAbsorb)
  end

  local fullNeedHP = healAbsorb or clampHeal or clampAbsorb
  local fullNeedMaxHP = heal or absorb or healAbsorb or fullNeedHP
  local fullPlan = PredictionPlan(heal, absorb, healAbsorb, heal, absorb, healAbsorb, true, fullNeedHP, fullNeedMaxHP)
  predictionPlanCache[key] = { plans, fullPlan }
  return plans, fullPlan
end

local Prediction = {}
local PREDICTION_BAR_DEFS = {
  { "heal", "incomingHealBar", 1, "healPredictionBar" },
  { "absorb", "absorbBar", 2 },
  { "healAbsorb", "healAbsorbBar", 3 },
}

local predictionQueue

local function QueuedPredictionEvent(bits)
  if bits == 1 then
    return "UNIT_HEAL_PREDICTION"
  elseif bits == 2 then
    return "UNIT_ABSORB_AMOUNT_CHANGED"
  elseif bits == 4 then
    return "UNIT_HEAL_ABSORB_AMOUNT_CHANGED"
  end
  return PREDICTION_FLUSH_EVENT
end

local function ProcessQueuedPrediction(frame, bits)
  if not frame then
    return false
  end
  local unit = frame._msufPredictionQueuedUnit or frame.unit
  frame._msufPredictionQueuedUnit = nil
  if frame._msufPredictionDisabled == true or frame._msufDisabledByConfig == true then
    return false
  end
  frame._msufPredictionFlushing = true
  Prediction.Update(frame, QueuedPredictionEvent(bits), unit)
  frame._msufPredictionFlushing = nil
  return true
end

local function EnsurePredictionQueue()
  if predictionQueue ~= nil then
    return predictionQueue or nil
  end
  if not (UF and UF.CreateDirtyQueue) then
    predictionQueue = false
    return nil
  end
  predictionQueue = UF.CreateDirtyQueue("Prediction", {
    scheduleKey = "UF_PREDICTION_FLUSH",
    process = ProcessQueuedPrediction,
    maxPerFlush = 24,
  }) or false
  return predictionQueue or nil
end

local function ClearQueuedPrediction(frame)
  if not frame then
    return
  end
  frame._msufPredictionQueuedUnit = nil
  if predictionQueue and predictionQueue.Retire then
    predictionQueue:Retire(frame)
  end
end

local function PredictionMaskHasBit(mask, bit)
  return type(mask) == "number" and type(bit) == "number" and (mask % (bit * 2)) >= bit
end

local function QueuePredictionBit(frame, bit, unit)
  if not frame or frame._msufPredictionFlushing == true or issecretvalue(unit) == true then
    return false
  end
  local mask = frame._msufPredictionMask or 0
  if not PredictionMaskHasBit(mask, bit) then
    return false
  end
  local cfg = frame._msufPredictionRuntimeCfg
  if not (cfg and cfg.enabled == true)
    or cfg.test == true
    or mask == 0 then
    return false
  end
  local queue = EnsurePredictionQueue()
  if not queue then
    return false
  end
  frame._msufPredictionQueuedUnit = unit or frame.unit
  return queue:Mark(frame, bit)
end

local function QueuePredictionUpdate(frame, event, unit)
  return QueuePredictionBit(frame, DEFERRED_PREDICTION_EVENT_BITS[event], unit)
end

local function ClearBarValueCache(bar)
  if not bar then return end
  for i = 1, #BAR_VALUE_CACHE_FIELDS do
    bar[BAR_VALUE_CACHE_FIELDS[i]] = nil
  end
end

local function ClearPredictionCache(frame)
  if not frame then
    return
  end
  frame._msufPredictionCacheReady = nil
  frame._msufPredictionCacheUnit = nil
  frame._msufPredictionCacheCfg = nil
  frame._msufPredictionIncoming = nil
  frame._msufPredictionAbsorb = nil
  frame._msufPredictionHealAbsorb = nil
  ClearBarValueCache(frame.incomingHealBar)
  ClearBarValueCache(frame.absorbBar)
  ClearBarValueCache(frame.healAbsorbBar)
end

local function CompilePredictionRuntime(frame, cfg, spec)
  if not frame then
    return
  end
  cfg = cfg or {}
  local hpReverse = spec and spec.health and spec.health.reverse == true
  local healMode = NormalizeAnchorMode(cfg.healAnchorMode, 3)
  local absorbMode = NormalizeAnchorMode(cfg.absorbAnchorMode, 2)
  local followAbsorb = cfg.absorb == true and (absorbMode == 3 or absorbMode == 4)
  frame._msufPredictionRuntimeCfg = cfg
  frame._msufPredictionFrameWidth = tonumber(spec and spec.width) or nil
  frame._msufPredictionHpReverse = hpReverse
  frame._msufPredictionHealMode = healMode
  frame._msufPredictionAbsorbMode = absorbMode
  frame._msufPredictionHealReverse = ReverseForMode(healMode, hpReverse)
  frame._msufPredictionAbsorbReverse = ReverseForMode(absorbMode, hpReverse)
  frame._msufPredictionMask = PredictionMask(cfg)
  frame._msufPredictionHealActive = cfg.heal == true
  frame._msufPredictionAbsorbActive = cfg.absorb == true
  frame._msufPredictionHealAbsorbActive = cfg.healAbsorb == true
  frame._msufPredictionAbsorbOnly = cfg.absorb == true and cfg.heal ~= true and cfg.healAbsorb ~= true
  frame._msufPredictionNeedsHealth = NeedsHealthEvent(cfg)
  frame._msufPredictionFollowAbsorb = followAbsorb
  frame._msufPredictionClampHealToMissing = cfg.heal == true and healMode == 3
  frame._msufPredictionClampAbsorbToMissing = cfg.absorb == true and absorbMode == 3
  frame._msufPredictionEventPlans, frame._msufPredictionFullPlan = CompilePredictionPlans(cfg, healMode, absorbMode, followAbsorb)
end

function Prediction.IsEnabled(frame, spec)
  local cfg = spec and spec.prediction
  if not (cfg and cfg.enabled == true) then
    return false
  end
  if cfg.test == true then
    return true
  end
  return PredictionMask(cfg) ~= 0
end

local function PredictionEventsForConfig(cfg, healthAware, unit)
  local mask = PredictionMask(cfg)
  if mask == 0 then
    return EMPTY_EVENTS
  end
  local player = issecretvalue(unit) ~= true and unit == "player"
  local eventTable
  if healthAware ~= false and NeedsHealthEvent(cfg) then
    eventTable = player and PREDICTION_HEALTH_EVENTS_PLAYER or PREDICTION_HEALTH_EVENTS
  else
    eventTable = player and PREDICTION_EVENTS_PLAYER or PREDICTION_EVENTS
  end
  return eventTable[mask] or EMPTY_EVENTS
end

function Prediction.GetEvents(frame, spec)
  return PredictionEventsForConfig(spec and spec.prediction, true, (frame and frame.unit) or (spec and spec.key))
end

function Prediction.GetUnitlessEvents(frame, spec)
  local cfg = spec and spec.prediction
  if PredictionMask(cfg) == 0 then
    return EMPTY_EVENTS
  end
  local unit = frame and frame.unit
  if unit == "targettarget" or unit == "focustarget" then
    return DERIVED_PREDICTION_TARGET_EVENTS
  end
  return EMPTY_EVENTS
end

function Prediction.Create(frame, spec)
  local cfg = spec and spec.prediction or {}
  for i = 1, #PREDICTION_BAR_DEFS do
    local def = PREDICTION_BAR_DEFS[i]
    if cfg[def[1]] == true then
      local bar = EnsureBar(frame, def[2], def[3])
      frame[def[2]] = bar
      if def[4] then
        frame[def[4]] = bar
      end
    end
  end
end

local function ApplyPredictionBar(frame, cfg, spec, bar, active, level, mode, reverse, textureKey, rKey, gKey, bKey, aKey, follow)
  if not bar then return end
  LayoutBar(frame, bar, level, mode, reverse, follow)
  SetTextureCached(bar, ResolveTexture(cfg[textureKey], spec and spec.texture or WHITE))
  SetColorCached(bar, cfg[rKey], cfg[gKey], cfg[bKey], cfg[aKey])
  if active ~= true then HideBar(bar) end
end

function Prediction.Apply(frame, spec)
  local cfg = spec and spec.prediction or {}
  Prediction.Create(frame, spec)
  frame._msufPredictionDisabled = nil
  ClearQueuedPrediction(frame)
  ClearPredictionCache(frame)
  frame._msufPredictionConnectionUnit = nil
  frame._msufPredictionConnectionOnline = nil
  CompilePredictionRuntime(frame, cfg, spec)
  frame._msufUpdatePredictionHealthValue = Prediction.UpdateHealthValue
  frame._msufUpdatePredictionConnectionState = Prediction.UpdateConnectionState
  frame._msufQueuePredictionUpdate = QueuePredictionUpdate
  frame._msufQueuePredictionBit = QueuePredictionBit
  if frame._msufPredictionMask ~= 0 and cfg.test ~= true then
    local calc = EnsureCalc(frame)
    if calc then
      if calc.ResetPredictedValues then
        calc:ResetPredictedValues()
      end
      ConfigureCalc(calc, cfg)
    end
  elseif frame._msufPredictionCalc then
    frame._msufPredictionCalc._msufPredictionCfg = nil
  end
  local healMode = frame._msufPredictionHealMode or NormalizeAnchorMode(cfg.healAnchorMode, 3)
  local absorbMode = frame._msufPredictionAbsorbMode or NormalizeAnchorMode(cfg.absorbAnchorMode, 2)

  ApplyPredictionBar(frame, cfg, spec, frame.incomingHealBar, cfg.heal,
    1, healMode, frame._msufPredictionHealReverse,
    "texture", "healR", "healG", "healB", "healA")
  ApplyPredictionBar(frame, cfg, spec, frame.absorbBar, cfg.absorb,
    2, absorbMode, frame._msufPredictionAbsorbReverse,
    "absorbTexture", "absorbR", "absorbG", "absorbB", "absorbA",
    VisibleFollowBar(cfg, frame.incomingHealBar))
  ApplyPredictionBar(frame, cfg, spec, frame.healAbsorbBar, cfg.healAbsorb,
    3, 5, not frame._msufPredictionHpReverse,
    "healAbsorbTexture", "healAbsorbR", "healAbsorbG", "healAbsorbB", "healAbsorbA")
end

function Prediction.Disable(frame)
  if not frame or frame._msufPredictionDisabled == true then
    return
  end
  ClearQueuedPrediction(frame)
  for i = 1, #PREDICTION_BAR_DEFS do
    HideBar(frame[PREDICTION_BAR_DEFS[i][2]])
  end
  ClearPredictionCache(frame)
  for i = 1, #PREDICTION_DISABLE_FIELDS do
    frame[PREDICTION_DISABLE_FIELDS[i]] = nil
  end
  frame._msufPredictionMask = 0
  frame._msufPredictionDisabled = true
end

local function UpdateAbsorbOnly(frame, event, unit, cfg, seedHP, seedMaxHP, absorbMode)
  local bar = frame.absorbBar
  if not bar then return end

  local cacheUnit = frame._msufPredictionCacheUnit
  local cacheReady = frame._msufPredictionCacheReady == true
    and issecretvalue(unit) ~= true
    and cacheUnit == unit
    and frame._msufPredictionCacheCfg == cfg
  local refreshAbsorb = not cacheReady
  local forceMax = not cacheReady

  if event == "UNIT_ABSORB_AMOUNT_CHANGED" then
    refreshAbsorb = true
  elseif event == "UNIT_MAXHEALTH" then
    forceMax = true
    refreshAbsorb = refreshAbsorb or frame._msufPredictionClampAbsorbToMissing == true
  elseif event ~= "UNIT_CONNECTION" then
    refreshAbsorb = true
    forceMax = true
  end

  local hp, maxHP
  if issecretvalue(seedHP) == true or seedHP ~= nil then hp = seedHP end
  if issecretvalue(seedMaxHP) == true or seedMaxHP ~= nil then maxHP = seedMaxHP end
  if (issecretvalue(hp) ~= true and hp == nil)
    or (issecretvalue(maxHP) ~= true and maxHP == nil) then
    local cachedHP, cachedMax = CachedHealthValues(frame, unit)
    if issecretvalue(hp) ~= true and hp == nil then hp = cachedHP end
    if issecretvalue(maxHP) ~= true and maxHP == nil then maxHP = cachedMax end
  end

  local calc
  if refreshAbsorb then
    calc = UpdateCalc(frame, unit, cfg)
    if not calc and frame._msufPredictionClampAbsorbToMissing == true then
      if issecretvalue(hp) ~= true and hp == nil and UnitHealth then hp = UnitHealth(unit) end
      if issecretvalue(maxHP) ~= true and maxHP == nil then maxHP = ReadHealthMax(frame, unit) end
    end
    frame._msufPredictionAbsorb = ReadDamageAbsorbs(calc, unit, hp, maxHP, absorbMode)
    frame._msufPredictionCacheReady = true
    frame._msufPredictionCacheUnit = issecretvalue(unit) ~= true and unit or nil
    frame._msufPredictionCacheCfg = cfg
  end

  if (forceMax == true or bar._msufMaxReady ~= true) and issecretvalue(maxHP) ~= true and maxHP == nil then
    maxHP = ReadHealthMax(frame, unit)
  end
  ShowValue(bar, maxHP, frame._msufPredictionAbsorb, forceMax)
end

function Prediction.UpdateHealthValue(frame, event, unit, seedHP, seedMaxHP)
  if unit and issecretvalue(unit) == true then
    unit = frame and frame.unit or nil
    seedHP, seedMaxHP = nil, nil
  elseif unit and frame and unit ~= frame.unit then
    return Prediction.Update(frame, event, unit, seedHP, seedMaxHP)
  end
  unit = unit or frame.unit
  local cfg = frame._msufPredictionRuntimeCfg
  if not (cfg and cfg.enabled == true)
    or cfg.test == true
    or frame._msufPredictionNeedsHealth ~= true
    or frame._msufPredictionMask == 0 then
    return Prediction.Update(frame, event, unit, seedHP, seedMaxHP)
  end
  local cacheUnit = frame._msufPredictionCacheUnit
  if frame._msufPredictionCacheReady ~= true
    or issecretvalue(unit) == true
    or cacheUnit ~= unit
    or frame._msufPredictionCacheCfg ~= cfg then
    return Prediction.Update(frame, event, unit, seedHP, seedMaxHP)
  end

  local maxHP = seedMaxHP
  if issecretvalue(maxHP) ~= true and maxHP == nil then
    maxHP = ReadHealthMax(frame, unit)
  end

  local healBar = frame.incomingHealBar
  if healBar then
    ShowValue(healBar, maxHP, frame._msufPredictionIncoming)
  end

  if frame._msufPredictionFollowAbsorb == true and frame.absorbBar then
    local follow = cfg.heal == true and healBar and healBar._msufShown == true and healBar or nil
    local absorbMode = frame._msufPredictionAbsorbMode or NormalizeAnchorMode(cfg.absorbAnchorMode, 2)
    LayoutBarIfNeeded(frame, frame.absorbBar, 2, absorbMode, frame._msufPredictionAbsorbReverse, follow)
    ShowValue(frame.absorbBar, maxHP, frame._msufPredictionAbsorb)
  end
end

function Prediction.UpdateConnectionState(frame, event, unit, seedHP, seedMaxHP, seedCalc)
  if unit and issecretvalue(unit) == true then
    unit = frame and frame.unit or nil
    seedHP, seedMaxHP, seedCalc = nil, nil, nil
  elseif unit and frame and unit ~= frame.unit then
    return Prediction.Update(frame, event, unit, seedHP, seedMaxHP, seedCalc)
  end
  unit = unit or frame.unit
  local cfg = frame._msufPredictionRuntimeCfg
  if not (cfg and cfg.enabled == true)
    or cfg.test == true
    or frame._msufPredictionMask == 0 then
    return Prediction.Update(frame, event, unit, seedHP, seedMaxHP, seedCalc)
  end

  local state = frame._msufUnitState
  local connectedKnown = state
    and state.ready == true
    and issecretvalue(unit) ~= true
    and state.unit == unit
    and frame._msufDispatchActive == true
    and state.dispatchToken == frame._msufDispatchToken
    and state.connectedKnown == true
  local connected = connectedKnown and state.connected or nil
  if not connectedKnown and UnitIsConnected then
    connected = UnitIsConnected(unit)
    if issecretvalue(connected) == true or connected == nil then
      connected = nil
    else
      connected = connected == true or connected == 1
    end
  end

  local connectionUnit = frame._msufPredictionConnectionUnit
  if connected == false then
    if issecretvalue(unit) ~= true
      and connectionUnit == unit
      and frame._msufPredictionConnectionOnline == false
      and (not frame.incomingHealBar or frame.incomingHealBar._msufShown == false)
      and (not frame.absorbBar or frame.absorbBar._msufShown == false)
      and (not frame.healAbsorbBar or frame.healAbsorbBar._msufShown == false) then
      return
    end
    frame._msufPredictionConnectionUnit = issecretvalue(unit) ~= true and unit or nil
    frame._msufPredictionConnectionOnline = false
    HideBar(frame.incomingHealBar)
    HideBar(frame.absorbBar)
    HideBar(frame.healAbsorbBar)
    ClearPredictionCache(frame)
    return
  end

  connectionUnit = frame._msufPredictionConnectionUnit
  local cacheUnit = frame._msufPredictionCacheUnit
  if connected == true
    and issecretvalue(unit) ~= true
    and connectionUnit == unit
    and frame._msufPredictionConnectionOnline == true
    and frame._msufPredictionCacheReady == true
    and cacheUnit == unit
    and frame._msufPredictionCacheCfg == cfg then
    return
  end

  local result = Prediction.Update(frame, event, unit, seedHP, seedMaxHP, seedCalc)
  if connected == true then
    frame._msufPredictionConnectionUnit = issecretvalue(unit) ~= true and unit or nil
    frame._msufPredictionConnectionOnline = true
  else
    frame._msufPredictionConnectionUnit = nil
    frame._msufPredictionConnectionOnline = nil
  end
  return result
end

function Prediction.Update(frame, event, unit, seedHP, seedMaxHP, seedCalc)
  if unit and issecretvalue(unit) == true then
    unit = frame and frame.unit or nil
    seedHP, seedMaxHP, seedCalc = nil, nil, nil
  elseif unit and frame and unit ~= frame.unit then
    unit = frame.unit
    seedHP, seedMaxHP, seedCalc = nil, nil, nil
  else
    unit = unit or frame.unit
  end
  local cfg = frame._msufPredictionRuntimeCfg
  local spec
  if not cfg then
    spec = frame.MSUFSpec
    cfg = spec and spec.prediction
  end
  if not (cfg and cfg.enabled == true) then
    Prediction.Disable(frame)
    return
  end
  if frame._msufPredictionRuntimeCfg ~= cfg then
    CompilePredictionRuntime(frame, cfg, spec or frame.MSUFSpec)
  end
  if cfg.test ~= true and frame._msufPredictionMask == 0 then
    Prediction.Disable(frame)
    return
  end
  if cfg.test ~= true then
    if event == "UNIT_HEAL_PREDICTION" and frame._msufPredictionHealActive ~= true then
      return
    elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" and frame._msufPredictionAbsorbActive ~= true then
      return
    elseif event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" and frame._msufPredictionHealAbsorbActive ~= true then
      return
    elseif event == "UNIT_HEALTH" and frame._msufPredictionNeedsHealth ~= true then
      return
    end
  end

  if UnitMissing(frame, unit) then
    Prediction.Disable(frame)
    return
  end
  frame._msufPredictionDisabled = nil

  if cfg.test ~= true
    and seedHP == nil
    and seedMaxHP == nil
    and seedCalc == nil
    and QueuePredictionUpdate(frame, event, unit) then
    return
  end

  local healMode = frame._msufPredictionHealMode or NormalizeAnchorMode(cfg.healAnchorMode, 3)
  local absorbMode = frame._msufPredictionAbsorbMode or NormalizeAnchorMode(cfg.absorbAnchorMode, 2)

  if cfg.test ~= true and frame._msufPredictionAbsorbOnly == true then
    return UpdateAbsorbOnly(frame, event, unit, cfg, seedHP, seedMaxHP, absorbMode)
  end

  if cfg.test == true then
    if cfg.heal == true and frame.incomingHealBar then
      LayoutBar(frame, frame.incomingHealBar, 1, healMode, frame._msufPredictionHealReverse)
      ShowValue(frame.incomingHealBar, TEST_MAX, TEST_INCOMING)
    elseif frame.incomingHealBar then
      HideBar(frame.incomingHealBar)
    end
    if cfg.absorb == true and frame.absorbBar then
      if absorbMode == 3 or absorbMode == 4 then
        local follow = VisibleFollowBar(cfg, frame.incomingHealBar)
        LayoutBar(frame, frame.absorbBar, 2, absorbMode, frame._msufPredictionAbsorbReverse, follow)
      end
      ShowValue(frame.absorbBar, TEST_MAX, TEST_ABSORB)
    elseif frame.absorbBar then
      HideBar(frame.absorbBar)
    end
    if cfg.healAbsorb == true and frame.healAbsorbBar then
      ShowValue(frame.healAbsorbBar, TEST_MAX, TEST_HEAL_ABSORB)
    elseif frame.healAbsorbBar then
      HideBar(frame.healAbsorbBar)
    end
    return
  end

  local cacheUnit = frame._msufPredictionCacheUnit
  local cacheReady = frame._msufPredictionCacheReady == true
    and issecretvalue(unit) ~= true
    and cacheUnit == unit
    and frame._msufPredictionCacheCfg == cfg
  local plans = frame._msufPredictionEventPlans
  local plan = event and plans and plans[event] or nil
  if not plan then
    if event and GATED_PREDICTION_EVENTS[event] then
      return
    end
    plan = frame._msufPredictionFullPlan
  elseif not cacheReady then
    plan = frame._msufPredictionFullPlan
  end
  if not plan then
    return
  end
  local refreshHeal = plan[PLAN_REFRESH_HEAL]
  local refreshAbsorb = plan[PLAN_REFRESH_ABSORB]
  local refreshHealAbsorb = plan[PLAN_REFRESH_HEAL_ABSORB]
  local showHeal = plan[PLAN_SHOW_HEAL]
  local showAbsorb = plan[PLAN_SHOW_ABSORB]
  local showHealAbsorb = plan[PLAN_SHOW_HEAL_ABSORB]
  local forceMax = plan[PLAN_FORCE_MAX]
  local needHP = plan[PLAN_NEED_HP]
  local needMaxHP = plan[PLAN_NEED_MAX_HP]

  if not (refreshHeal or refreshAbsorb or refreshHealAbsorb or showHeal or showAbsorb or showHealAbsorb) then
    return
  end

  local hp, maxHP
  local canUseSeed = (issecretvalue(seedHP) == true or seedHP ~= nil)
    and (issecretvalue(seedMaxHP) == true or seedMaxHP ~= nil)
  if canUseSeed then
    hp, maxHP = seedHP, seedMaxHP
  end
  if (needHP or needMaxHP)
    and ((issecretvalue(hp) ~= true and hp == nil)
      or (issecretvalue(maxHP) ~= true and maxHP == nil)) then
    local cachedHP, cachedMax = CachedHealthValues(frame, unit)
    if issecretvalue(hp) ~= true and hp == nil then hp = cachedHP end
    if issecretvalue(maxHP) ~= true and maxHP == nil then maxHP = cachedMax end
  end
  if (needHP or needMaxHP) and issecretvalue(hp) ~= true and hp == nil and UnitHealth then hp = UnitHealth(unit) end
  if needMaxHP and issecretvalue(maxHP) ~= true and maxHP == nil then maxHP = ReadHealthMax(frame, unit) end

  local calc
  if refreshHeal or refreshAbsorb or refreshHealAbsorb then
    calc = UpdateCalc(frame, unit, cfg)
  end
  if refreshHeal then
    local incoming = ReadIncomingHeals(calc, unit, hp, maxHP, healMode)
    frame._msufPredictionIncoming = incoming
  end
  if refreshAbsorb then
    frame._msufPredictionAbsorb = ReadDamageAbsorbs(calc, unit, hp, maxHP, absorbMode)
  end
  if refreshHealAbsorb then
    frame._msufPredictionHealAbsorb = ReadHealAbsorbs(calc, unit, hp)
  end
  if refreshHeal or refreshAbsorb or refreshHealAbsorb then
    frame._msufPredictionCacheReady = true
    frame._msufPredictionCacheUnit = issecretvalue(unit) ~= true and unit or nil
    frame._msufPredictionCacheCfg = cfg
  end

  if showHeal and frame.incomingHealBar then
    local incoming = frame._msufPredictionIncoming
    if (forceMax == true or frame.incomingHealBar._msufMaxReady ~= true) and issecretvalue(maxHP) ~= true and maxHP == nil then
      maxHP = ReadHealthMax(frame, unit)
    end
    ShowValue(frame.incomingHealBar, maxHP, incoming, forceMax)
  end

  if showAbsorb and frame.absorbBar then
    if absorbMode == 3 or absorbMode == 4 then
      local follow = cfg.heal == true and frame.incomingHealBar and frame.incomingHealBar._msufShown == true and frame.incomingHealBar or nil
      LayoutBarIfNeeded(frame, frame.absorbBar, 2, absorbMode, frame._msufPredictionAbsorbReverse, follow, forceMax == true)
    end
    if (forceMax == true or frame.absorbBar._msufMaxReady ~= true) and issecretvalue(maxHP) ~= true and maxHP == nil then
      maxHP = ReadHealthMax(frame, unit)
    end
    ShowValue(frame.absorbBar, maxHP, frame._msufPredictionAbsorb, forceMax)
  end

  if showHealAbsorb and frame.healAbsorbBar then
    if (forceMax == true or frame.healAbsorbBar._msufMaxReady ~= true) and issecretvalue(maxHP) ~= true and maxHP == nil then
      maxHP = ReadHealthMax(frame, unit)
    end
    ShowValue(frame.healAbsorbBar, maxHP, frame._msufPredictionHealAbsorb, forceMax)
  end

  if frame._msufPredictionFlushing ~= true and plan == frame._msufPredictionFullPlan then
    ClearQueuedPrediction(frame)
  end
end

UF.RegisterElement("Prediction", Prediction)
