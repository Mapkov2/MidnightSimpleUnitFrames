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
local UnitHealthPercent = UnitHealthPercent
local UnitGetIncomingHeals = _G.UnitGetIncomingHeals
local UnitGetTotalAbsorbs = _G.UnitGetTotalAbsorbs
local UnitGetTotalHealAbsorbs = _G.UnitGetTotalHealAbsorbs
local CreateUnitHealPredictionCalculator = _G.CreateUnitHealPredictionCalculator
local UnitGetDetailedHealPrediction = _G.UnitGetDetailedHealPrediction
local InCombatLockdown = _G.InCombatLockdown
local tonumber = tonumber
local type = type
local Enum = _G.Enum
local CurveAPI = _G.C_CurveUtil
local LuaCurveType = Enum and Enum.LuaCurveType
local UnitMissing
do
  local issv = _G.issecretvalue or function(_) return false end
  UnitMissing = function(frame, unit, unitSecret)
    if unitSecret == true then
      return false
    end
    local state = frame and frame._msufUnitState
    if state
      and state.ready == true
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
local OVER_ABSORB_TEXTURE = "Interface\\RaidFrame\\Shield-Overshield"
local OVER_ABSORB_GLOW_W = 16
local OVER_ABSORB_GLOW_OFFSET = 7
local overAbsorbFullHealthCurve
local PREDICTION_HEALER_UNIT = "player"
local EMPTY_EVENTS = {}
local PREDICTION_EVENT_BITS = {
  { 1, "UNIT_HEAL_PREDICTION" },
  { 2, "UNIT_ABSORB_AMOUNT_CHANGED" },
  { 4, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" },
}
local PREDICTION_DATA_EVENT_BITS = {
  UNIT_HEAL_PREDICTION = 1,
  UNIT_ABSORB_AMOUNT_CHANGED = 2,
  UNIT_HEAL_ABSORB_AMOUNT_CHANGED = 4,
}
-- Single-bit masks deliberately reuse the native event keys so specialized
-- paths (notably absorb-only) retain their exact event semantics. Combined
-- masks address precompiled union plans without allocating a table at runtime.
local PREDICTION_DIRTY_PLAN_KEYS = {
  [1] = "UNIT_HEAL_PREDICTION",
  [2] = "UNIT_ABSORB_AMOUNT_CHANGED",
  [3] = "MSUF_PREDICTION_DIRTY_HEAL_ABSORB",
  [4] = "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
  [5] = "MSUF_PREDICTION_DIRTY_HEAL_HEALABSORB",
  [6] = "MSUF_PREDICTION_DIRTY_ABSORB_HEALABSORB",
  [7] = "MSUF_PREDICTION_DIRTY_ALL",
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
-- Core coalesces PLAYER_*_CHANGED + UNIT_TARGET into one authoritative identity
-- refresh for dependent units. Prediction participates in that identity plan;
-- registering UNIT_TARGET here as well would perform a second calculator read.
local PREDICTION_EVENTS_DEPENDENT = PREDICTION_EVENTS
local PREDICTION_HEALTH_EVENTS_DEPENDENT = PREDICTION_HEALTH_EVENTS
local GROUP_LIFECYCLE_EVENTS = { "PARTY_MEMBER_ENABLE", "PARTY_MEMBER_DISABLE" }

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
  "_msufPredictionAbsorbEdgeGlow",
  "_msufPredictionClampHealToMissing",
  "_msufPredictionClampAbsorbToMissing",
  "_msufUpdatePredictionHealthValue",
  "_msufUpdatePredictionConnectionState",
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
  local dispatchToken = frame
    and frame._msufDispatchActive == true
    and frame._msufDispatchToken
    or nil
  if dispatchToken ~= nil
    and calc._msufPredictionUpdateDispatch == dispatchToken
    and calc._msufPredictionUpdateUnit == unit
    and calc._msufPredictionUpdateCfg == cfg then
    return calc
  end
  UnitGetDetailedHealPrediction(unit, PREDICTION_HEALER_UNIT, calc)
  -- Share the calculator only inside one core dispatch. Two state events can
  -- land in the same rendered frame; GetTime-based reuse would let a premature
  -- PARTY_MEMBER_ENABLE snapshot poison the following UNIT_HEALTH update.
  calc._msufPredictionUpdateDispatch = dispatchToken
  calc._msufPredictionUpdateUnit = unit
  calc._msufPredictionUpdateCfg = cfg
  return calc
end

local sharedHealthCalc
local HEALTH_ONLY_CFG = {}

--- Group lifecycle transitions and AI party health can lead the direct health
--- APIs. Reuse the frame calculator when prediction is active; otherwise one
--- shared calculator avoids allocating prediction state on every group frame.
local function ReadDetailedHealth(frame, unit)
  if not (unit and UnitGetDetailedHealPrediction and CreateUnitHealPredictionCalculator) then
    return nil
  end

  local cfg = frame and frame._msufPredictionRuntimeCfg
  local calc
  if frame and (cfg or frame._msufPredictionCalc) then
    calc = UpdateCalc(frame, unit, cfg or HEALTH_ONLY_CFG)
  else
    calc = sharedHealthCalc
    if not calc then
      calc = CreateUnitHealPredictionCalculator()
      sharedHealthCalc = calc
    end
    if calc then
      UnitGetDetailedHealPrediction(unit, PREDICTION_HEALER_UNIT, calc)
    end
  end
  if not calc then return nil end

  local current = calc.GetCurrentHealth and calc:GetCurrentHealth() or nil
  local maximum = calc.GetMaximumHealth and calc:GetMaximumHealth() or nil
  return current, maximum, calc
end

UF.ReadDetailedHealth = ReadDetailedHealth

local function FallbackIncomingHeals(unit)
  return UnitGetIncomingHeals and UnitGetIncomingHeals(unit, PREDICTION_HEALER_UNIT) or nil
end

local function CalcIncomingHeals(calc, unit)
  if calc and calc.GetIncomingHeals then
    local _, healer = calc:GetIncomingHeals()
    return healer
  end
  return FallbackIncomingHeals(unit)
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
  if bar.SetFrameLevel and hpBar and (hpBar.GetFrameLevel or frame.GetFrameLevel) then
    local baseLevel = hpBar.GetFrameLevel and hpBar:GetFrameLevel() or nil
    if baseLevel == nil and frame.GetFrameLevel then
      baseLevel = frame:GetFrameLevel()
    end
    if issecretvalue(baseLevel) ~= true then
      local level = (baseLevel or 1) + levelOffset
      bar:SetFrameLevel(level)
      bar._msufFrameLevel = level
    end
  end
  bar:Hide()
  frame[key] = bar
  return bar
end

local function FullHealthAlpha(unit)
  if not (UnitHealthPercent and CurveAPI and CurveAPI.CreateCurve and unit) then return nil end
  local curve = overAbsorbFullHealthCurve
  if not curve then
    curve = CurveAPI.CreateCurve()
    if not curve then return nil end
    if curve.SetType then curve:SetType(LuaCurveType and LuaCurveType.Step or 1) end
    -- Prediction calculator health percentages use 0..1. Step interpolation
    -- keeps every partial-health value at zero and promotes exact max health.
    curve:AddPoint(0, 0)
    curve:AddPoint(1, 1)
    overAbsorbFullHealthCurve = curve
  end
  return UnitHealthPercent(unit, true, curve)
end

local function EnsureOverAbsorbGlow(frame)
  if not frame then return nil end
  local hpBar = frame.hpBar or frame.Health
  if not hpBar then return nil end
  local holder = frame.overAbsorbGlowBar
  if holder then return holder end
  if not CreateFrame then return nil end

  -- UnitGetTotalAbsorbs is secret-returning on Midnight. A 0..1 StatusBar can
  -- consume that value directly: zero draws nothing and every positive absorb
  -- clamps to the complete Blizzard edge texture. This avoids branching on a
  -- protected value and also gives the glow a frame level above the HP bar.
  holder = CreateFrame("StatusBar", nil, frame)
  if holder.EnableMouse then holder:EnableMouse(false) end
  holder:SetMinMaxValues(0, 1)
  holder:SetValue(0)
  holder:SetStatusBarTexture(OVER_ABSORB_TEXTURE)
  holder:SetStatusBarColor(1, 1, 1, 1)
  local glow = holder:GetStatusBarTexture()
  if glow.SetBlendMode then glow:SetBlendMode("ADD") end
  holder:SetWidth(OVER_ABSORB_GLOW_W)
  holder:Hide()
  local oldGlow = frame.overAbsorbGlow
  if oldGlow and oldGlow ~= glow and oldGlow.Hide then oldGlow:Hide() end
  frame.overAbsorbGlowBar = holder
  frame.overAbsorbGlow = glow
  return holder
end

local function HideOverAbsorbGlow(frame)
  local holder = frame and frame.overAbsorbGlowBar
  if holder and holder._msufOverAbsorbShown ~= false then
    holder:SetShown(false)
    holder:SetValue(0)
    holder._msufOverAbsorbShown = false
  end
end

local function PositionOverAbsorbGlow(frame, reverse)
  local holder = EnsureOverAbsorbGlow(frame)
  local hpBar = frame and (frame.hpBar or frame.Health)
  if not (holder and hpBar) then return nil end
  if holder.SetFrameLevel and hpBar.GetFrameLevel then
    local baseLevel = hpBar:GetFrameLevel()
    if issecretvalue(baseLevel) ~= true then
      local level = (baseLevel or 1) + 4
      if holder._msufOverAbsorbLevel ~= level then
        holder:SetFrameLevel(level)
        holder._msufOverAbsorbLevel = level
      end
    end
  end
  if holder._msufOverAbsorbReverse == reverse and holder._msufOverAbsorbAnchor == hpBar then
    return holder
  end
  holder:ClearAllPoints()
  if reverse then
    holder:SetPoint("TOPRIGHT", hpBar, "TOPLEFT", OVER_ABSORB_GLOW_OFFSET, 0)
    holder:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMLEFT", OVER_ABSORB_GLOW_OFFSET, 0)
  else
    holder:SetPoint("TOPLEFT", hpBar, "TOPRIGHT", -OVER_ABSORB_GLOW_OFFSET, 0)
    holder:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMRIGHT", -OVER_ABSORB_GLOW_OFFSET, 0)
  end
  holder:SetWidth(OVER_ABSORB_GLOW_W)
  holder._msufOverAbsorbReverse = reverse
  holder._msufOverAbsorbAnchor = hpBar
  return holder
end

local function PlainPositive(value)
  if issecretvalue(value) == true or type(value) ~= "number" then return nil end
  return value > 0 and value or nil
end

local function ReadHealthForOverAbsorb(frame, unit, hp, maxHP)
  if PlainPositive(hp) == nil and issecretvalue(hp) ~= true then
    hp = CachedHealthValue(frame, unit)
    if PlainPositive(hp) == nil and issecretvalue(hp) ~= true and UnitHealth then hp = UnitHealth(unit) end
  end
  if PlainPositive(maxHP) == nil and issecretvalue(maxHP) ~= true then
    maxHP = ReadHealthMax(frame, unit)
  end
  return hp, maxHP
end

local function ResolveGlowAbsorb(frame, cfg, unit, hp, maxHP, absorb)
  if not (cfg and cfg.test ~= true and cfg.fullHealthAbsorbStripe == true
      and frame and frame._msufPredictionAbsorbMode == 3
      and UnitGetTotalAbsorbs and unit) then
    return absorb
  end

  local hpSecret = issecretvalue(hp) == true
  local maxSecret = issecretvalue(maxHP) == true
  if not hpSecret and not maxSecret
    and type(hp) == "number" and type(maxHP) == "number" and maxHP > 0
    and hp < maxHP then
    return absorb
  end

  -- "Follow HP bar" clamps its display amount to missing health, which is
  -- correctly zero at full HP. The edge needs the real shield amount instead.
  -- Query it only on this enabled cold path; secret values flow directly into
  -- the 0..1 status gate and are never inspected by Lua.
  local rawAbsorb = UnitGetTotalAbsorbs(unit)
  if issecretvalue(rawAbsorb) == true or rawAbsorb ~= nil then return rawAbsorb end
  return absorb
end

local function UpdateOverAbsorbGlow(frame, cfg, unit, hp, maxHP, absorb)
  local overAbsorbEnabled = cfg and cfg.overAbsorbOverlay == true
  local fullHealthStripeEnabled = cfg and cfg.fullHealthAbsorbStripe == true
  if not (frame and cfg and cfg.absorb == true and (overAbsorbEnabled or fullHealthStripeEnabled)) then
    HideOverAbsorbGlow(frame)
    return
  end
  hp, maxHP = ReadHealthForOverAbsorb(frame, unit, hp, maxHP)
  absorb = ResolveGlowAbsorb(frame, cfg, unit, hp, maxHP, absorb)
  local absorbSecret = issecretvalue(absorb) == true
  if not absorbSecret and (type(absorb) ~= "number" or absorb <= 0) then
    HideOverAbsorbGlow(frame)
    return
  end
  local hpSecret = issecretvalue(hp) == true
  local maxSecret = issecretvalue(maxHP) == true
  local holder = PositionOverAbsorbGlow(frame, frame._msufPredictionHpReverse == true)
  if not holder then return end

  -- Secret absorb values cannot be inspected in Lua. Feed them into the tiny
  -- StatusBar instead; its fill is the positive-absorb gate. For protected HP
  -- values, UnitHealthPercent evaluates a step curve and SetAlpha accepts the
  -- resulting secret scalar. Rendering therefore performs the logical AND.
  if absorbSecret or hpSecret or maxSecret then
    if fullHealthStripeEnabled then
      local alpha
      if not hpSecret and not maxSecret and type(hp) == "number" and type(maxHP) == "number" and maxHP > 0 then
        alpha = hp >= maxHP and 1 or 0
      else
        alpha = FullHealthAlpha(unit)
      end
      if issecretvalue(alpha) == true or alpha ~= nil then
        holder:SetAlpha(alpha)
        holder:SetValue(absorb)
        if holder._msufOverAbsorbShown ~= true then
          holder:SetShown(true)
          holder._msufOverAbsorbShown = true
        end
        return
      end
    end
    HideOverAbsorbGlow(frame)
    return
  end
  if type(hp) ~= "number" or type(maxHP) ~= "number" or maxHP <= 0 then
    HideOverAbsorbGlow(frame)
    return
  end
  local incoming = frame._msufPredictionIncoming
  if issecretvalue(incoming) == true or type(incoming) ~= "number" or incoming < 0 then incoming = 0 end
  local atFullHealth = hp >= maxHP
  local show = fullHealthStripeEnabled and atFullHealth
  if not show and not atFullHealth and overAbsorbEnabled then
    show = (hp + incoming + absorb) >= maxHP or (hp + absorb) >= maxHP
  end
  if not show then
    HideOverAbsorbGlow(frame)
    return
  end
  holder:SetAlpha(1)
  holder:SetValue(absorb)
  if holder._msufOverAbsorbShown ~= true then
    holder:SetShown(true)
    holder._msufOverAbsorbShown = true
  end
end

local function SyncBarLayer(frame, hpBar, bar, levelOffset)
  if not (frame and hpBar and bar) then
    return
  end
  if bar.SetFrameStrata and frame.GetFrameStrata then
    local strata = frame:GetFrameStrata()
    local cachedStrata = bar._msufFrameStrata
    if issecretvalue(strata) ~= true and strata and (issecretvalue(cachedStrata) == true or cachedStrata ~= strata) then
      bar:SetFrameStrata(strata)
      bar._msufFrameStrata = strata
    end
  end
  if bar.SetFrameLevel and (hpBar.GetFrameLevel or frame.GetFrameLevel) then
    local baseLevel = hpBar.GetFrameLevel and hpBar:GetFrameLevel() or nil
    if baseLevel == nil and frame.GetFrameLevel then
      baseLevel = frame:GetFrameLevel()
    end
    if issecretvalue(baseLevel) ~= true then
      local level = (baseLevel or 1) + levelOffset
      if bar._msufFrameLevel ~= level then
        bar:SetFrameLevel(level)
        bar._msufFrameLevel = level
      end
    end
  end
end

local function PredictionLayerCurrent(frame, hpBar, bar, levelOffset)
  if bar.SetFrameStrata and frame.GetFrameStrata then
    local strata = frame:GetFrameStrata()
    local cachedStrata = bar._msufFrameStrata
    if issecretvalue(strata) ~= true and strata
      and (issecretvalue(cachedStrata) == true or cachedStrata ~= strata) then
      return false
    end
  end
  if bar.SetFrameLevel and (hpBar.GetFrameLevel or frame.GetFrameLevel) then
    local baseLevel = hpBar.GetFrameLevel and hpBar:GetFrameLevel() or nil
    if baseLevel == nil and frame.GetFrameLevel then
      baseLevel = frame:GetFrameLevel()
    end
    if issecretvalue(baseLevel) ~= true
      and bar._msufFrameLevel ~= (baseLevel or 1) + levelOffset then
      return false
    end
  end
  return true
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
  local followSource = (mode == 3 or mode == 4) and followBar or nil
  local follow = (mode == 3 or mode == 4) and (followSource and StatusTexture(followSource) or StatusTexture(hpBar)) or nil
  local runtimeWidth = tonumber(frame._msufPredictionFrameWidth)
  local width = (hpBar.GetWidth and hpBar:GetWidth()) or runtimeWidth or 1
  if not width or width <= 0 then
    width = runtimeWidth or 1
  end
  local anchorTarget = follow or hpBar
  local parent = (mode == 4) and frame or hpBar
  local parentCurrent = not bar.GetParent or bar:GetParent() == parent

  local layoutCurrent = bar._msufPredictionMode == mode
    and bar._msufPredictionReverse == reverse
    and bar._msufPredictionFollowBar == followSource
    and bar._msufPredictionAnchorTarget == anchorTarget
    and bar._msufPredictionWidth == width
    and bar._msufPredictionParent == parent
    and bar._msufPredictionLevelOffset == levelOffset
    and bar._msufReverseFill == reverse
    and parentCurrent
  if layoutCurrent and PredictionLayerCurrent(frame, hpBar, bar, levelOffset) then
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
  local followSource = (mode == 3 or mode == 4) and followBar or nil
  local follow = (mode == 3 or mode == 4) and (followSource and StatusTexture(followSource) or StatusTexture(hpBar)) or nil
  local runtimeWidth = tonumber(frame._msufPredictionFrameWidth)
  local width = (hpBar.GetWidth and hpBar:GetWidth()) or runtimeWidth or 1
  if not width or width <= 0 then
    width = runtimeWidth or 1
  end
  local anchorTarget = follow or hpBar
  local parent = (mode == 4) and frame or hpBar
  return bar._msufPredictionMode == mode
    and bar._msufPredictionReverse == reverse
    and bar._msufPredictionFollowBar == followSource
    and bar._msufPredictionAnchorTarget == anchorTarget
    and bar._msufPredictionWidth == width
    and bar._msufPredictionParent == parent
    and bar._msufPredictionLevelOffset == levelOffset
    and bar._msufReverseFill == reverse
    and (not bar.GetParent or bar:GetParent() == parent)
    and PredictionLayerCurrent(frame, hpBar, bar, levelOffset)
end

local function LayoutBarIfNeeded(frame, bar, levelOffset, mode, reverse, followBar)
  if PredictionLayoutCurrent(frame, bar, levelOffset, mode, reverse, followBar) then
    return
  end
  LayoutBar(frame, bar, levelOffset, mode, reverse, followBar)
end

local function LayoutHealAbsorbBar(frame, bar, levelOffset, hpReverse)
  local hpBar = frame and (frame.hpBar or frame.Health)
  if not (bar and hpBar) then
    return
  end
  local hpTexture = StatusTexture(hpBar) or hpBar
  local runtimeWidth = tonumber(frame._msufPredictionFrameWidth)
  local width = (hpBar.GetWidth and hpBar:GetWidth()) or runtimeWidth or 1
  if not width or width <= 0 then
    width = runtimeWidth or 1
  end
  local reverse = hpReverse ~= true

  local layoutCurrent = bar._msufHealAbsorbAnchorTarget == hpTexture
    and bar._msufHealAbsorbWidth == width
    and bar._msufHealAbsorbHpReverse == hpReverse
    and bar._msufHealAbsorbParent == hpBar
    and bar._msufHealAbsorbLevelOffset == levelOffset
    and bar._msufReverseFill == reverse
  if layoutCurrent and bar.GetParent and bar:GetParent() ~= hpBar then
    layoutCurrent = false
  end
  if layoutCurrent and not PredictionLayerCurrent(frame, hpBar, bar, levelOffset) then
    layoutCurrent = false
  end
  if layoutCurrent then
    return
  end

  SyncBarLayer(frame, hpBar, bar, levelOffset)
  local parentChanged = SetParentCached(bar, hpBar)
  if hpBar.SetClipsChildren and hpBar._msufPredictionClipsChildren ~= true then
    hpBar:SetClipsChildren(true)
    hpBar._msufPredictionClipsChildren = true
  end

  if bar._msufHealAbsorbAnchorTarget ~= hpTexture
    or bar._msufHealAbsorbWidth ~= width
    or bar._msufHealAbsorbHpReverse ~= hpReverse
    or bar._msufHealAbsorbParent ~= hpBar
    or parentChanged then
    bar:ClearAllPoints()
    bar:SetWidth(width)
    if hpReverse == true then
      bar:SetPoint("TOPLEFT", hpTexture, "TOPLEFT", 0, 0)
      bar:SetPoint("BOTTOMLEFT", hpTexture, "BOTTOMLEFT", 0, 0)
    else
      bar:SetPoint("TOPRIGHT", hpTexture, "TOPRIGHT", 0, 0)
      bar:SetPoint("BOTTOMRIGHT", hpTexture, "BOTTOMRIGHT", 0, 0)
    end
    bar._msufHealAbsorbAnchorTarget = hpTexture
    bar._msufHealAbsorbWidth = width
    bar._msufHealAbsorbHpReverse = hpReverse
    bar._msufHealAbsorbParent = hpBar
  end
  bar._msufHealAbsorbLevelOffset = levelOffset

  if bar.SetReverseFill and bar._msufReverseFill ~= reverse then
    bar:SetReverseFill(reverse)
    bar._msufReverseFill = reverse
  end
end

local function NeedsHealthEvent(cfg)
  if not cfg then
    return false
  end
  if cfg.heal == true and NormalizeAnchorMode(cfg.healAnchorMode, 3) == 3 then
    return true
  end
  if cfg.absorb == true and NormalizeAnchorMode(cfg.absorbAnchorMode, 2) == 3 then
    return true
  end
  if cfg.absorb == true and cfg.overAbsorbOverlay == true then
    return true
  end
  if cfg.absorb == true and cfg.fullHealthAbsorbStripe == true then
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

local function MergePredictionPlans(plans, mask)
  local merged
  for i = 1, #PREDICTION_EVENT_BITS do
    local bit = PREDICTION_EVENT_BITS[i][1]
    if (mask % (bit * 2)) >= bit then
      local plan = plans[PREDICTION_EVENT_BITS[i][2]]
      if plan then
        merged = merged or {}
        for field = 1, PLAN_NEED_MAX_HP do
          if plan[field] then merged[field] = true end
        end
      end
    end
  end
  return merged
end

local predictionPlanCache = {}

local function PredictionPlanCacheKey(heal, absorb, healAbsorb, clampHeal, clampAbsorb, followAbsorb, absorbEdgeGlow)
  return (heal and 1 or 0)
    + (absorb and 2 or 0)
    + (healAbsorb and 4 or 0)
    + (clampHeal and 8 or 0)
    + (clampAbsorb and 16 or 0)
    + (followAbsorb and 32 or 0)
    + (absorbEdgeGlow and 64 or 0)
end

local function CompilePredictionPlans(cfg, healMode, absorbMode, followAbsorb)
  local heal = cfg and cfg.heal == true
  local absorb = cfg and cfg.absorb == true
  local healAbsorb = cfg and cfg.healAbsorb == true
  local clampHeal = heal and healMode == 3
  local clampAbsorb = absorb and absorbMode == 3
  local absorbEdgeGlow = absorb and cfg
    and (cfg.overAbsorbOverlay == true or cfg.fullHealthAbsorbStripe == true)
  local key = PredictionPlanCacheKey(heal, absorb, healAbsorb, clampHeal, clampAbsorb, followAbsorb, absorbEdgeGlow)
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
  if clampHeal or clampAbsorb or absorbEdgeGlow then
    plans.UNIT_HEALTH = PredictionPlan(clampHeal, clampAbsorb, nil, clampHeal, followAbsorb or absorbEdgeGlow, nil, nil, true, true)
  end
  if heal or absorb or healAbsorb then
    plans.UNIT_MAXHEALTH = PredictionPlan(clampHeal, clampAbsorb, nil, heal, absorb, healAbsorb, true, clampHeal or clampAbsorb or healAbsorb or overAbsorb, heal or absorb or healAbsorb)
  end

  -- The three prediction payload events can arrive in one rendered frame.
  -- Precompile their four possible multi-event unions once per configuration;
  -- the hot event path then only merges an integer mask.
  for mask = 3, 7 do
    if mask ~= 4 then
      local merged = MergePredictionPlans(plans, mask)
      if merged then plans[PREDICTION_DIRTY_PLAN_KEYS[mask]] = merged end
    end
  end

  local fullNeedHP = healAbsorb or clampHeal or clampAbsorb or absorbEdgeGlow
  local fullNeedMaxHP = heal or absorb or healAbsorb or fullNeedHP
  local fullPlan = PredictionPlan(heal, absorb, healAbsorb, heal, absorb, healAbsorb, true, fullNeedHP, fullNeedMaxHP)
  predictionPlanCache[key] = { plans, fullPlan }
  return plans, fullPlan
end

local Prediction = { UpdateOnApply = true }
Prediction.ReadDetailedHealth = ReadDetailedHealth
local PREDICTION_BAR_DEFS = {
  { "heal", "incomingHealBar", 1, "healPredictionBar" },
  { "absorb", "absorbBar", 2 },
  { "healAbsorb", "healAbsorbBar", 3 },
}

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
  -- Invalidate queued data from the previous unit/configuration. The reusable
  -- queue entry may remain until the next driver flush, where it becomes a
  -- no-op; a new event can safely reuse that same entry in the meantime.
  frame._msufPredictionDirtyMask = nil
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
  frame._msufPredictionAbsorbEdgeGlow = cfg.absorb == true
    and (cfg.overAbsorbOverlay == true or cfg.fullHealthAbsorbStripe == true)
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
  local plainUnit = issecretvalue(unit) ~= true and unit or nil
  local player = plainUnit == "player"
  local dependent = plainUnit == "targettarget" or plainUnit == "focustarget"
  local eventTable
  if healthAware ~= false and NeedsHealthEvent(cfg) then
    eventTable = player and PREDICTION_HEALTH_EVENTS_PLAYER
      or dependent and PREDICTION_HEALTH_EVENTS_DEPENDENT
      or PREDICTION_HEALTH_EVENTS
  else
    eventTable = player and PREDICTION_EVENTS_PLAYER
      or dependent and PREDICTION_EVENTS_DEPENDENT
      or PREDICTION_EVENTS
  end
  return eventTable[mask] or EMPTY_EVENTS
end

function Prediction.GetEvents(frame, spec)
  return PredictionEventsForConfig(
    spec and spec.prediction,
    true,
    (frame and frame.unit) or (spec and spec.key)
  )
end

function Prediction.GetUnitlessEvents(frame, spec)
  local cfg = spec and spec.prediction
  if PredictionMask(cfg) == 0 then
    return EMPTY_EVENTS
  end
  if spec and spec.scope == "group" then
    return GROUP_LIFECYCLE_EVENTS
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

local function ApplyHealAbsorbBar(frame, cfg, spec, bar)
  if not bar then return end
  LayoutHealAbsorbBar(frame, bar, 3, frame._msufPredictionHpReverse == true)
  SetTextureCached(bar, ResolveTexture(cfg.healAbsorbTexture, spec and spec.texture or WHITE))
  SetColorCached(bar, cfg.healAbsorbR, cfg.healAbsorbG, cfg.healAbsorbB, cfg.healAbsorbA)
  if cfg.healAbsorb ~= true then HideBar(bar) end
end

function Prediction.Apply(frame, spec)
  local cfg = spec and spec.prediction or {}
  Prediction.Create(frame, spec)
  frame._msufPredictionDisabled = nil
  ClearPredictionCache(frame)
  frame._msufPredictionConnectionUnit = nil
  frame._msufPredictionConnectionOnline = nil
  CompilePredictionRuntime(frame, cfg, spec)
  frame._msufUpdatePredictionHealthValue = Prediction.UpdateHealthValue
  frame._msufUpdatePredictionConnectionState = Prediction.UpdateConnectionState
  if frame._msufPredictionMask ~= 0 and cfg.test ~= true and frame._msufPredictionAbsorbOnly ~= true then
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
  if cfg.absorb == true and (cfg.overAbsorbOverlay == true or cfg.fullHealthAbsorbStripe == true) then
    PositionOverAbsorbGlow(frame, frame._msufPredictionHpReverse == true)
  else
    HideOverAbsorbGlow(frame)
  end
  ApplyHealAbsorbBar(frame, cfg, spec, frame.healAbsorbBar)
end

function Prediction.Disable(frame)
  if not frame or frame._msufPredictionDisabled == true then
    return
  end
  for i = 1, #PREDICTION_BAR_DEFS do
    HideBar(frame[PREDICTION_BAR_DEFS[i][2]])
  end
  HideOverAbsorbGlow(frame)
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

  if refreshAbsorb then
    if frame._msufPredictionClampAbsorbToMissing == true then
      if issecretvalue(hp) ~= true and hp == nil and UnitHealth then hp = UnitHealth(unit) end
      if issecretvalue(maxHP) ~= true and maxHP == nil then maxHP = ReadHealthMax(frame, unit) end
    end
    frame._msufPredictionAbsorb = ReadDamageAbsorbs(nil, unit, hp, maxHP, absorbMode)
    frame._msufPredictionCacheReady = true
    frame._msufPredictionCacheUnit = issecretvalue(unit) ~= true and unit or nil
    frame._msufPredictionCacheCfg = cfg
  end

  if (forceMax == true or bar._msufMaxReady ~= true) and issecretvalue(maxHP) ~= true and maxHP == nil then
    maxHP = ReadHealthMax(frame, unit)
  end
  ShowValue(bar, maxHP, frame._msufPredictionAbsorb, forceMax)
  if frame._msufPredictionAbsorbEdgeGlow == true then
    UpdateOverAbsorbGlow(frame, cfg, unit, hp, maxHP, frame._msufPredictionAbsorb)
  end
end

local UpdateFull

-- Blizzard's CompactUnitFrame defers the three expensive prediction payload
-- events and resolves them at most once per rendered frame. Keep the same
-- contract here with a dedicated, allocation-free hot path: two reusable
-- arrays allow events raised during a flush to land in the next batch without
-- extending the active loop or allocating closures/tables per event.
local predictionQueueA, predictionQueueB = {}, {}
local predictionWriteQueue = predictionQueueA
local predictionWriteCount = 0
local predictionDriver
local predictionDriverArmed
local FlushPredictionQueue

local function ArmPredictionDriver()
  if predictionDriverArmed == true then return true end
  if not predictionDriver and CreateFrame then
    predictionDriver = CreateFrame("Frame")
  end
  if not (predictionDriver and predictionDriver.SetScript) then return false end
  predictionDriverArmed = true
  predictionDriver:SetScript("OnUpdate", FlushPredictionQueue)
  return true
end

local function QueuePredictionDataEvent(frame, event)
  if not frame then return end
  local bit = PREDICTION_DATA_EVENT_BITS[event]
  if not bit then return end

  local mask = frame._msufPredictionDirtyMask or 0
  if (mask % (bit * 2)) < bit then
    frame._msufPredictionDirtyMask = mask + bit
  end
  if frame._msufPredictionQueued == true then return end

  frame._msufPredictionQueued = true
  predictionWriteCount = predictionWriteCount + 1
  predictionWriteQueue[predictionWriteCount] = frame
  if ArmPredictionDriver() then return end

  -- CreateFrame is unavailable only in non-WoW harnesses. Preserve behavior
  -- synchronously there instead of leaving a queued update stranded.
  predictionWriteQueue[predictionWriteCount] = nil
  predictionWriteCount = predictionWriteCount - 1
  frame._msufPredictionQueued = nil
  mask = frame._msufPredictionDirtyMask
  frame._msufPredictionDirtyMask = nil
  if mask then UpdateFull(frame, PREDICTION_DIRTY_PLAN_KEYS[mask], frame.unit) end
end

FlushPredictionQueue = function()
  if predictionDriver and predictionDriver.SetScript then
    predictionDriver:SetScript("OnUpdate", nil)
  end
  predictionDriverArmed = nil

  local batch = predictionWriteQueue
  local count = predictionWriteCount
  predictionWriteQueue = batch == predictionQueueA and predictionQueueB or predictionQueueA
  predictionWriteCount = 0

  for i = 1, count do
    local frame = batch[i]
    batch[i] = nil
    if frame then
      frame._msufPredictionQueued = nil
      local mask = frame._msufPredictionDirtyMask
      frame._msufPredictionDirtyMask = nil
      if mask then
        -- A transiently missing unit may have disabled and cleared the cached
        -- runtime plan after this event was registered. Let UpdateFull validate
        -- the current spec and rebuild that plan instead of stranding the bar
        -- until an unrelated health/lifecycle event happens.
        UpdateFull(frame, PREDICTION_DIRTY_PLAN_KEYS[mask], frame.unit)
      end
    end
  end

  -- A prediction API callback can synchronously queue more work. It belongs to
  -- the following rendered frame, never to the batch currently being drained.
  if predictionWriteCount > 0 then ArmPredictionDriver() end
end

function Prediction.UpdateHealthValue(frame, event, unit, seedHP, seedMaxHP)
  if unit and issecretvalue(unit) == true then
    unit = frame and frame.unit or nil
    seedHP, seedMaxHP = nil, nil
  elseif unit and frame and unit ~= frame.unit then
    return UpdateFull(frame, event, unit, seedHP, seedMaxHP)
  end
  unit = unit or frame.unit
  local cfg = frame._msufPredictionRuntimeCfg
  if not (cfg and cfg.enabled == true)
    or cfg.test == true
    or frame._msufPredictionNeedsHealth ~= true
    or frame._msufPredictionMask == 0 then
    return UpdateFull(frame, event, unit, seedHP, seedMaxHP)
  end
  local cacheUnit = frame._msufPredictionCacheUnit
  if frame._msufPredictionCacheReady ~= true
    or issecretvalue(unit) == true
    or cacheUnit ~= unit
    or frame._msufPredictionCacheCfg ~= cfg then
    return UpdateFull(frame, event, unit, seedHP, seedMaxHP)
  end

  local healBar = frame._msufPredictionHealActive == true and frame.incomingHealBar or nil
  local absorbBar = frame._msufPredictionAbsorbActive == true and frame.absorbBar or nil
  local absorbEdgeGlow = frame._msufPredictionAbsorbEdgeGlow == true and absorbBar ~= nil
  local maxHP = seedMaxHP
  -- UNIT_MAXHEALTH owns max-value invalidation and the full route force-seeds
  -- every active prediction bar there. Ordinary UNIT_HEALTH ticks can retain
  -- that native StatusBar max unless a bar has not been seeded yet or the
  -- over-absorb threshold needs the numeric max for arithmetic.
  local needMax = absorbEdgeGlow
    or (healBar and healBar._msufMaxReady ~= true)
    or (frame._msufPredictionFollowAbsorb == true
      and absorbBar and absorbBar._msufMaxReady ~= true)
  if needMax and issecretvalue(maxHP) ~= true and maxHP == nil then
    maxHP = ReadHealthMax(frame, unit)
  end

  if healBar then
    ShowValue(healBar, maxHP, frame._msufPredictionIncoming)
  end

  if frame._msufPredictionFollowAbsorb == true and absorbBar then
    local follow = cfg.heal == true and healBar and healBar._msufShown == true and healBar or nil
    local absorbMode = frame._msufPredictionAbsorbMode or NormalizeAnchorMode(cfg.absorbAnchorMode, 2)
    LayoutBarIfNeeded(frame, absorbBar, 2, absorbMode, frame._msufPredictionAbsorbReverse, follow)
    ShowValue(absorbBar, maxHP, frame._msufPredictionAbsorb)
  end
  if absorbEdgeGlow then
    UpdateOverAbsorbGlow(frame, cfg, unit, seedHP, maxHP, frame._msufPredictionAbsorb)
  end
end

function Prediction.UpdateConnectionState(frame, event, unit, seedHP, seedMaxHP, seedCalc)
  if unit and issecretvalue(unit) == true then
    unit = frame and frame.unit or nil
    seedHP, seedMaxHP, seedCalc = nil, nil, nil
  elseif unit and frame and unit ~= frame.unit then
    return UpdateFull(frame, event, unit, seedHP, seedMaxHP, seedCalc)
  end
  unit = unit or frame.unit
  local cfg = frame._msufPredictionRuntimeCfg
  if not (cfg and cfg.enabled == true)
    or cfg.test == true
    or frame._msufPredictionMask == 0 then
    return UpdateFull(frame, event, unit, seedHP, seedMaxHP, seedCalc)
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

  local result = UpdateFull(frame, event, unit, seedHP, seedMaxHP, seedCalc)
  if connected == true then
    frame._msufPredictionConnectionUnit = issecretvalue(unit) ~= true and unit or nil
    frame._msufPredictionConnectionOnline = true
  else
    frame._msufPredictionConnectionUnit = nil
    frame._msufPredictionConnectionOnline = nil
  end
  return result
end

UpdateFull = function(frame, event, unit, seedHP, seedMaxHP, seedCalc)
  if unit and issecretvalue(unit) == true then
    unit = frame and frame.unit or nil
    seedHP, seedMaxHP, seedCalc = nil, nil, nil
  elseif unit and frame and unit ~= frame.unit then
    unit = frame.unit
    seedHP, seedMaxHP, seedCalc = nil, nil, nil
  else
    unit = unit or frame.unit
  end
  local unitSecret = issecretvalue(unit) == true
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

  if cfg.test ~= true and UnitMissing(frame, unit, unitSecret) then
    Prediction.Disable(frame)
    return
  end
  frame._msufPredictionDisabled = nil

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
      UpdateOverAbsorbGlow(frame, cfg, unit, TEST_MAX, TEST_MAX, TEST_ABSORB)
    elseif frame.absorbBar then
      HideBar(frame.absorbBar)
      HideOverAbsorbGlow(frame)
    end
    if cfg.healAbsorb == true and frame.healAbsorbBar then
      LayoutHealAbsorbBar(frame, frame.healAbsorbBar, 3, frame._msufPredictionHpReverse == true)
      ShowValue(frame.healAbsorbBar, TEST_MAX, TEST_HEAL_ABSORB)
    elseif frame.healAbsorbBar then
      HideBar(frame.healAbsorbBar)
    end
    return
  end

  local cacheUnit = frame._msufPredictionCacheUnit
  local cacheReady = frame._msufPredictionCacheReady == true
    and unitSecret ~= true
    and cacheUnit == unit
    and frame._msufPredictionCacheCfg == cfg
  local plans = frame._msufPredictionEventPlans
  local pendingMask = frame._msufPredictionDirtyMask
  if pendingMask and frame._msufPredictionAbsorbOnly ~= true then
    local eventBit = PREDICTION_DATA_EVENT_BITS[event]
    if eventBit then
      if (pendingMask % (eventBit * 2)) < eventBit then
        pendingMask = pendingMask + eventBit
      end
      frame._msufPredictionDirtyMask = nil
      event = PREDICTION_DIRTY_PLAN_KEYS[pendingMask]
    elseif not (event and plans and plans[event]) then
      -- A full refresh already covers every queued prediction component.
      frame._msufPredictionDirtyMask = nil
    end
  end
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
    frame._msufPredictionCacheUnit = unitSecret ~= true and unit or nil
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
      LayoutBarIfNeeded(frame, frame.absorbBar, 2, absorbMode, frame._msufPredictionAbsorbReverse, follow)
    end
    if (forceMax == true or frame.absorbBar._msufMaxReady ~= true) and issecretvalue(maxHP) ~= true and maxHP == nil then
      maxHP = ReadHealthMax(frame, unit)
    end
    ShowValue(frame.absorbBar, maxHP, frame._msufPredictionAbsorb, forceMax)
    if frame._msufPredictionAbsorbEdgeGlow == true then
      UpdateOverAbsorbGlow(frame, cfg, unit, hp, maxHP, frame._msufPredictionAbsorb)
    end
  end

  if showHealAbsorb and frame.healAbsorbBar then
    LayoutHealAbsorbBar(frame, frame.healAbsorbBar, 3, frame._msufPredictionHpReverse == true)
    if (forceMax == true or frame.healAbsorbBar._msufMaxReady ~= true) and issecretvalue(maxHP) ~= true and maxHP == nil then
      maxHP = ReadHealthMax(frame, unit)
    end
    ShowValue(frame.healAbsorbBar, maxHP, frame._msufPredictionHealAbsorb, forceMax)
  end
end

function Prediction.Update(frame, event, unit, seedHP, seedMaxHP, seedCalc)
  if event == "UNIT_HEALTH" then
    return Prediction.UpdateHealthValue(frame, event, unit, seedHP, seedMaxHP)
  end
  if event == "UNIT_CONNECTION" then
    return Prediction.UpdateConnectionState(frame, event, unit, seedHP, seedMaxHP, seedCalc)
  end
  return UpdateFull(frame, event, unit, seedHP, seedMaxHP, seedCalc)
end

function Prediction.SelectEventUpdate(_frame, _spec, event)
  if PREDICTION_DATA_EVENT_BITS[event] then
    return QueuePredictionDataEvent
  elseif event == "UNIT_HEALTH" then
    return Prediction.UpdateHealthValue
  elseif event == "UNIT_CONNECTION" then
    return Prediction.UpdateConnectionState
  end
  return UpdateFull
end

--- Reseed live prediction values after Blizzard has finalized world/unit data.
--- This is a cold lifecycle path: it touches only visible frames with an active
--- Prediction element and does not rebuild specs, layouts, or event routing.
function Prediction.RefreshVisible(reason)
  if InCombatLockdown and InCombatLockdown() then return false end
  local frames = UF and UF.attachedFrameList
  if type(frames) ~= "table" then return false end

  local did = false
  reason = reason or "MSUF_PREDICTION_WORLD_ENTRY"
  for i = 1, #frames do
    local frame = frames[i]
    local active = frame and frame._msufActiveElements
    local update = frame and frame._msufUpdatePrediction
    local visible = frame and frame._msufCoreVisible
    if frame
      and frame._msufCoreSpecEnabled ~= false
      and (not UF.IsUnitToken or UF.IsUnitToken(frame.unit))
      and active and active.Prediction == true
      and type(update) == "function"
      and (visible == true
        or _G.MSUF_PreviewTestMode == true
        or _G.MSUF_BossTestMode == true
        or _G.MSUF2_BossUnitframePreviewActive == true
        or (visible == nil and (not frame.IsVisible or frame:IsVisible()))) then
      -- Direct element refreshes do not pass through BeginFrameEvent. Invalidate
      -- a possibly pre-world UnitExists snapshot so UnitMissing reads live state.
      local state = frame._msufUnitState
      if state then state.ready = false end
      update(frame, reason, frame.unit)
      did = true
    end
  end
  return did
end

UF.RefreshVisiblePredictions = Prediction.RefreshVisible

local function FlushWorldEntryPredictionSeed()
  Prediction.RefreshVisible("MSUF_PREDICTION_WORLD_ENTRY")
end

local function OnPredictionWorldEntry()
  local schedule = _G.MSUF_ScheduleOnce
  if type(schedule) == "function" then
    schedule("UF_PREDICTION_WORLD_ENTRY", FlushWorldEntryPredictionSeed)
  else
    FlushWorldEntryPredictionSeed()
  end
end

local registerEvent = _G.MSUF_EventBus_Register
if type(registerEvent) == "function" then
  -- Blizzard performs an authoritative prediction refresh on every world entry.
  -- Use the shared bus plus the shared next-frame scheduler so pre-existing
  -- absorbs are seeded after unit data settles without a private event driver.
  registerEvent("PLAYER_ENTERING_WORLD", "MSUF_UF_PREDICTION_WORLD_ENTRY", OnPredictionWorldEntry)
end

UF.RegisterElement("Prediction", Prediction)
