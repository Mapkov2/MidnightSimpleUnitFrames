--- UnitFrames/Engine/Elements/MSUF_UF_Elements_Prediction.lua
--- Heal/absorb prediction element for unitframes.
---
--- WoW prediction APIs can return unknown/secret values during protected states;
--- native StatusBars and clip geometry consume them without unsafe Lua math.

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
local ReadUnitExistsCached = UF.ReadUnitExistsCached
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
    if ReadUnitExistsCached then
      local exists, known = ReadUnitExistsCached(frame, unit)
      return known == true and exists == false
    end
    if not UnitExists then return false end
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
local UnitDamageAbsorbClampMode = Enum and Enum.UnitDamageAbsorbClampMode
local ABSORB_MISSING = UnitDamageAbsorbClampMode
  and UnitDamageAbsorbClampMode.MissingHealthWithoutIncomingHeals or 1
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

local GATED_PREDICTION_EVENTS = {
  UNIT_HEAL_PREDICTION = true,
  UNIT_ABSORB_AMOUNT_CHANGED = true,
  UNIT_HEAL_ABSORB_AMOUNT_CHANGED = true,
  UNIT_HEALTH = true,
}

local BAR_VALUE_CACHE_FIELDS = { "_msufMaxReady", "_msufMaxPlain", "_msufValuePlain" }
local PREDICTION_DISABLE_FIELDS = {
  "_msufPredictionNeedsHealth",
  "_msufPredictionHealActive",
  "_msufPredictionAbsorbActive",
  "_msufPredictionHealAbsorbActive",
  "_msufPredictionEventPlans",
  "_msufPredictionFullPlan",
  "_msufPredictionConnectionUnit",
  "_msufPredictionConnectionOnline",
  "_msufPredictionRuntimeCfg",
  "_msufPredictionFrameWidth",
  "_msufPredictionHpReverse",
  "_msufPredictionVertical",
  "_msufPredictionHealMode",
  "_msufPredictionAbsorbMode",
  "_msufPredictionHealAbsorbMode",
  "_msufPredictionHealHeight",
  "_msufPredictionHealOffsetY",
  "_msufPredictionAbsorbHeight",
  "_msufPredictionAbsorbOffsetY",
  "_msufPredictionHealAbsorbHeight",
  "_msufPredictionHealAbsorbOffsetY",
  "_msufPredictionHealReverse",
  "_msufPredictionAbsorbReverse",
  "_msufPredictionFollowAbsorb",
  "_msufPredictionMixedFollowClamp",
  "_msufPredictionReadAbsorb",
  "_msufPredictionOverAbsorbOverlay",
  "_msufPredictionFullHealthStripe",
  "_msufPredictionFullHealthAlphaReady",
  "_msufPredictionFullHealthAlphaDirty",
  "_msufPredictionFullHealthAlphaUnit",
  "_msufPredictionFlushData",
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
  if not bar then return end
  if bar._msufR ~= r or bar._msufG ~= g or bar._msufB ~= b then
    bar:SetStatusBarColor(r, g, b, 1)
    bar._msufR, bar._msufG, bar._msufB = r, g, b
  end
  if bar._msufA ~= a then
    bar:SetAlpha(a)
    bar._msufA = a
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

local function HideBar(bar)
  if not bar then
    return
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

local function CachedHealthPercent(frame, unit)
  local hpBar = frame and (frame.hpBar or frame.Health)
  if hpBar and hpBar._msufHealthPercentUnit == unit then
    return hpBar._msufHealthPercentValue
  end
  return nil
end

local function ReadHealthMax(frame, unit, refresh)
  local maxHP
  if refresh ~= true then
    if frame._msufPredictionHealthMaxUnit == unit then
      maxHP = frame._msufPredictionHealthMax
    end
    if issecretvalue(maxHP) ~= true and maxHP == nil then
      maxHP = CachedHealthMax(frame, unit)
    end
  end
  if issecretvalue(maxHP) ~= true and maxHP == nil and UnitHealthMax then
    maxHP = UnitHealthMax(unit)
  end
  if issecretvalue(maxHP) == true or maxHP == nil then
    frame._msufPredictionHealthMax = nil
    frame._msufPredictionHealthMaxUnit = nil
  else
    frame._msufPredictionHealthMax = maxHP
    frame._msufPredictionHealthMaxUnit = unit
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
    -- UNIT_MAXHEALTH and initial seeding own the native maximum. Secret max
    -- values may be forwarded but never compared, so ordinary health ticks
    -- retain the already-seeded StatusBar range without repeating the setter.
    if (maxSecret and needMax)
      or (not maxSecret and (needMax or bar._msufMaxPlain ~= true or bar._msufMax ~= maxValue)) then
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

-- Prediction values are event payloads, not health-tick state. Follow modes
-- anchor their full raw amount to the live HP texture; the HP StatusBar clips
-- mode 3 natively, while mode 4 deliberately parents to the frame to overflow.
-- Keep these reads as direct returns so protected payloads are never inspected
-- by Lua before StatusBar:SetValue consumes them.
local function ReadIncomingHeals(unit)
  if not UnitGetIncomingHeals then return nil end
  return UnitGetIncomingHeals(unit, PREDICTION_HEALER_UNIT)
end

local function ReadDamageAbsorbs(_frame, unit)
  if not UnitGetTotalAbsorbs then return nil end
  return UnitGetTotalAbsorbs(unit)
end

local function ReadHealAbsorbs(unit)
  if not UnitGetTotalHealAbsorbs then return nil end
  return UnitGetTotalHealAbsorbs(unit)
end

-- Only the mixed legacy layout (absorb follows HP while an incoming-heal bar
-- is anchored independently to a side/max) cannot be clipped correctly by the
-- existing geometry. Keep Blizzard's MissingHealthWithoutIncomingHeals clamp
-- solely for that compiled exception; the common follow/follow path never
-- creates or updates a calculator.
local function ReadMixedFollowAbsorbs(frame, unit)
  local calc = frame and frame._msufPredictionAbsorbClampCalc
  if not calc and CreateUnitHealPredictionCalculator and UnitGetDetailedHealPrediction then
    calc = CreateUnitHealPredictionCalculator()
    if calc then
      if calc.SetDamageAbsorbClampMode then
        calc:SetDamageAbsorbClampMode(ABSORB_MISSING)
      end
      frame._msufPredictionAbsorbClampCalc = calc
    end
  end
  if not (calc and UnitGetDetailedHealPrediction) then
    return ReadDamageAbsorbs(frame, unit)
  end
  UnitGetDetailedHealPrediction(unit, PREDICTION_HEALER_UNIT, calc)
  local getAbsorb = calc.GetDamageAbsorbs or calc.GetTotalDamageAbsorbs
  if getAbsorb then return getAbsorb(calc) end
  return ReadDamageAbsorbs(frame, unit)
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

local function EnsureFullHealthCurve()
  if not (CurveAPI and CurveAPI.CreateCurve) then return nil end
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
  return curve
end

local function FullHealthAlpha(unit)
  if not (UnitHealthPercent and unit) then return nil end
  -- Apply prewarms this immutable curve. Keep the health-event route on the
  -- direct upvalue and retain lazy creation only for defensive standalone use.
  local curve = overAbsorbFullHealthCurve
  if not curve then curve = EnsureFullHealthCurve() end
  if not curve then return nil end
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
  holder._msufOverAbsorbValue = 0
  holder._msufOverAbsorbValuePlain = true
  holder._msufOverAbsorbAlpha = 1
  holder._msufOverAbsorbAlphaPlain = true
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
    holder._msufOverAbsorbShown = false
  end
end

local function SetOverAbsorbAlpha(holder, alpha)
  local secret = issecretvalue(alpha) == true
  if not secret
    and holder._msufOverAbsorbAlphaPlain == true
    and holder._msufOverAbsorbAlpha == alpha then
    return
  end
  holder:SetAlpha(alpha)
  if secret then
    holder._msufOverAbsorbAlpha = nil
    holder._msufOverAbsorbAlphaPlain = nil
  else
    holder._msufOverAbsorbAlpha = alpha
    holder._msufOverAbsorbAlphaPlain = true
  end
end

local function PositionOverAbsorbGlow(frame, reverse)
  local holder = EnsureOverAbsorbGlow(frame)
  local hpBar = frame and (frame.hpBar or frame.Health)
  if not (holder and hpBar) then return nil end
  local vertical = frame._msufPredictionVertical == true
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
  if holder._msufOverAbsorbReverse == reverse
    and holder._msufOverAbsorbAnchor == hpBar
    and holder._msufOverAbsorbVertical == vertical then
    return holder
  end
  holder:ClearAllPoints()
  if vertical then
    -- Vertical fill: the over-absorb edge sits at the fill-end (top for
    -- bottom->top HP, bottom for top->bottom HP) as a horizontal strip. The
    -- Shield-Overshield art is drawn for a side edge; a rotated stripe is an
    -- accepted cosmetic trade-off (the presence gate still renders correctly).
    if reverse then
      holder:SetPoint("TOPLEFT", hpBar, "BOTTOMLEFT", 0, OVER_ABSORB_GLOW_OFFSET)
      holder:SetPoint("TOPRIGHT", hpBar, "BOTTOMRIGHT", 0, OVER_ABSORB_GLOW_OFFSET)
    else
      holder:SetPoint("BOTTOMLEFT", hpBar, "TOPLEFT", 0, -OVER_ABSORB_GLOW_OFFSET)
      holder:SetPoint("BOTTOMRIGHT", hpBar, "TOPRIGHT", 0, -OVER_ABSORB_GLOW_OFFSET)
    end
    holder:SetHeight(OVER_ABSORB_GLOW_W)
  else
    if reverse then
      holder:SetPoint("TOPRIGHT", hpBar, "TOPLEFT", OVER_ABSORB_GLOW_OFFSET, 0)
      holder:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMLEFT", OVER_ABSORB_GLOW_OFFSET, 0)
    else
      holder:SetPoint("TOPLEFT", hpBar, "TOPRIGHT", -OVER_ABSORB_GLOW_OFFSET, 0)
      holder:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMRIGHT", -OVER_ABSORB_GLOW_OFFSET, 0)
    end
    holder:SetWidth(OVER_ABSORB_GLOW_W)
  end
  holder._msufOverAbsorbReverse = reverse
  holder._msufOverAbsorbAnchor = hpBar
  holder._msufOverAbsorbVertical = vertical
  return holder
end

local function ReadHealthForOverAbsorb(frame, unit, hp, maxHP)
  local hpSecret = issecretvalue(hp) == true
  if not hpSecret and (type(hp) ~= "number" or hp <= 0) then
    hp = CachedHealthValue(frame, unit)
    hpSecret = issecretvalue(hp) == true
  end
  local maxSecret = issecretvalue(maxHP) == true
  if not maxSecret and (type(maxHP) ~= "number" or maxHP <= 0) then
    maxHP = ReadHealthMax(frame, unit)
    maxSecret = issecretvalue(maxHP) == true
  end
  if not hpSecret and (type(hp) ~= "number" or hp <= 0) then
    local pct = CachedHealthPercent(frame, unit)
    if issecretvalue(pct) ~= true
      and type(pct) == "number"
      and not maxSecret
      and type(maxHP) == "number"
      and maxHP > 0 then
      -- The percent bar and prediction threshold describe the same current
      -- health. Reconstruct the plain value from their already-owned inputs
      -- instead of issuing UnitHealth after UnitHealthPercent in this dispatch.
      hp = (pct * maxHP) / 100
    elseif UnitHealth then
      hp = UnitHealth(unit)
      hpSecret = issecretvalue(hp) == true
    end
  end
  return hp, maxHP, hpSecret, maxSecret
end

local function UpdateOverAbsorbGlow(frame, cfg, unit, hp, maxHP, absorb, refreshFullHealthAlpha,
  writeAbsorbValue)
  if frame and refreshFullHealthAlpha == true then
    frame._msufPredictionFullHealthAlphaDirty = true
  end
  local overAbsorbEnabled = frame and frame._msufPredictionOverAbsorbOverlay == true
  local fullHealthStripeEnabled = frame and frame._msufPredictionFullHealthStripe == true
  if not (frame and (overAbsorbEnabled or fullHealthStripeEnabled)) then
    HideOverAbsorbGlow(frame)
    return
  end
  local reverse = frame._msufPredictionHpReverse == true
  local hpBar = frame.hpBar or frame.Health
  local holder = frame.overAbsorbGlowBar
  if writeAbsorbValue == true then
    if not holder then holder = PositionOverAbsorbGlow(frame, reverse) end
    if holder then
      local payload = absorb
      local payloadSecret = issecretvalue(payload) == true
      if not payloadSecret
        and (type(payload) ~= "number" or payload <= 0) then
        payload = 0
      end
      if payloadSecret
        or refreshFullHealthAlpha == true
        or holder._msufOverAbsorbValuePlain ~= true
        or holder._msufOverAbsorbValue ~= payload then
        holder:SetValue(payload)
        if payloadSecret then
          holder._msufOverAbsorbValue = nil
          holder._msufOverAbsorbValuePlain = nil
        else
          holder._msufOverAbsorbValue = payload
          holder._msufOverAbsorbValuePlain = true
        end
      end
    end
  end
  -- The partial-health over-absorb overlay has no secret-safe arithmetic path:
  -- its existing result for any protected operand is always hidden. Reject
  -- that exact state, and the overwhelmingly common plain zero-shield state,
  -- before health/max lookups and layout checks.
  if not fullHealthStripeEnabled then
    if issecretvalue(hp) == true
      or issecretvalue(maxHP) == true
      or issecretvalue(absorb) == true
      or type(absorb) ~= "number"
      or absorb <= 0 then
      HideOverAbsorbGlow(frame)
      return
    end
  end
  if fullHealthStripeEnabled then
    local knownZero = writeAbsorbValue == true
      and issecretvalue(absorb) ~= true
      and (type(absorb) ~= "number" or absorb <= 0)
    if not knownZero and writeAbsorbValue ~= true
      and holder and holder._msufOverAbsorbValuePlain == true then
      local gateValue = holder._msufOverAbsorbValue
      knownZero = type(gateValue) ~= "number" or gateValue <= 0
    end
    if knownZero then
      HideOverAbsorbGlow(frame)
      return
    end

    -- A protected absorb cannot participate in the optional partial-health
    -- threshold. Its only renderable result is the native full-health stripe:
    -- the holder value gates absorb presence and its cached alpha gates health.
    -- Once both gates are warm, an absorb-data event needs no UnitHealth/
    -- UnitHealthMax recovery at all.
    if writeAbsorbValue == true
      and issecretvalue(absorb) == true
      and holder and hpBar
      and holder._msufOverAbsorbReverse == reverse
      and holder._msufOverAbsorbAnchor == hpBar
      and frame._msufPredictionFullHealthAlphaReady == true
      and frame._msufPredictionFullHealthAlphaDirty ~= true
      and frame._msufPredictionFullHealthAlphaUnit == unit then
      if holder._msufOverAbsorbShown ~= true then
        holder:SetShown(true)
        holder._msufOverAbsorbShown = true
      end
      return
    end
  end

  -- Protected health reduces to two native payloads: a step-curve alpha and
  -- the raw absorb cached by UNIT_ABSORB_AMOUNT_CHANGED. Reuse the warm layout
  -- and skip general health recovery/threshold work on every health event.
  if cfg and cfg.test ~= true
    and fullHealthStripeEnabled
    and issecretvalue(unit) ~= true
    and (issecretvalue(hp) == true or issecretvalue(maxHP) == true)
    and holder and hpBar
    and holder._msufOverAbsorbReverse == reverse
    and holder._msufOverAbsorbAnchor == hpBar then
    local absorbSecret = issecretvalue(absorb) == true
    if writeAbsorbValue == true
      and not absorbSecret and (type(absorb) ~= "number" or absorb <= 0) then
      HideOverAbsorbGlow(frame)
      return
    end
    local alphaReady = frame._msufPredictionFullHealthAlphaReady == true
      and frame._msufPredictionFullHealthAlphaDirty ~= true
      and frame._msufPredictionFullHealthAlphaUnit == unit
    if not alphaReady then
      local alpha = FullHealthAlpha(unit)
      if issecretvalue(alpha) ~= true and alpha == nil then
        HideOverAbsorbGlow(frame)
        return
      end
      SetOverAbsorbAlpha(holder, alpha)
      frame._msufPredictionFullHealthAlphaReady = true
      frame._msufPredictionFullHealthAlphaDirty = nil
      frame._msufPredictionFullHealthAlphaUnit = unit
    end
    if holder._msufOverAbsorbShown ~= true then
      holder:SetShown(true)
      holder._msufOverAbsorbShown = true
    end
    return
  end

  local hpSecret, maxSecret
  hp, maxHP, hpSecret, maxSecret = ReadHealthForOverAbsorb(frame, unit, hp, maxHP)
  local absorbSecret = issecretvalue(absorb) == true
  if not (fullHealthStripeEnabled and writeAbsorbValue ~= true)
    and not absorbSecret and (type(absorb) ~= "number" or absorb <= 0) then
    HideOverAbsorbGlow(frame)
    return
  end
  -- Apply owns layout/frame-level changes. The combat health path can bypass
  -- Ensure/position/frame-level work while the compiled anchor is unchanged.
  if not (holder and hpBar
      and holder._msufOverAbsorbReverse == reverse
      and holder._msufOverAbsorbAnchor == hpBar) then
    holder = PositionOverAbsorbGlow(frame, reverse)
  end
  if not holder then return end

  -- Secret absorb values cannot be inspected in Lua. Feed them into the tiny
  -- StatusBar instead; its fill is the positive-absorb gate. For protected HP
  -- values, UnitHealthPercent evaluates a step curve and SetAlpha accepts the
  -- resulting secret scalar. Rendering therefore performs the logical AND.
  if absorbSecret or hpSecret or maxSecret then
    if fullHealthStripeEnabled then
      local alphaReady = frame._msufPredictionFullHealthAlphaReady == true
        and frame._msufPredictionFullHealthAlphaDirty ~= true
        and issecretvalue(unit) ~= true
        and frame._msufPredictionFullHealthAlphaUnit == unit
      if not alphaReady then
        local alpha
        if not hpSecret and not maxSecret and type(hp) == "number" and type(maxHP) == "number" and maxHP > 0 then
          alpha = hp >= maxHP and 1 or 0
        else
          alpha = FullHealthAlpha(unit)
        end
        if issecretvalue(alpha) ~= true and alpha == nil then
          HideOverAbsorbGlow(frame)
          return
        end
        SetOverAbsorbAlpha(holder, alpha)
        frame._msufPredictionFullHealthAlphaReady = true
        frame._msufPredictionFullHealthAlphaDirty = nil
        frame._msufPredictionFullHealthAlphaUnit = issecretvalue(unit) ~= true and unit or nil
      end
      if frame._msufPredictionFullHealthAlphaReady == true then
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
  SetOverAbsorbAlpha(holder, 1)
  if holder._msufOverAbsorbShown ~= true then
    holder:SetShown(true)
    holder._msufOverAbsorbShown = true
  end
end

-- SetParent resets a frame's strata and level to the new parent's, so this must
-- run AFTER any re-parenting and re-apply unconditionally when the parent just
-- changed -- otherwise the cached level below still reports the wanted layer
-- while the widget sits one level lower, and the layout guard never repairs it.
-- Overflow (mode 4) re-parents the overlay from the HP bar to the frame, which
-- is exactly where that mismatch drops the bar behind neighbouring group frames.
local function SyncBarLayer(frame, hpBar, bar, levelOffset, force)
  if not (frame and hpBar and bar) then
    return
  end
  if bar.SetFrameStrata and frame.GetFrameStrata then
    local strata = frame:GetFrameStrata()
    local cachedStrata = bar._msufFrameStrata
    if issecretvalue(strata) ~= true and strata
      and (force == true or issecretvalue(cachedStrata) == true or cachedStrata ~= strata) then
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
      if force == true or bar._msufFrameLevel ~= level then
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

-- The HP bar's own size changes only on layout/apply -- never on a combat
-- event -- so measuring it inside the per-event layout guard is pure overhead.
-- Measure once and let the widget invalidate the cache itself. Two independent
-- invalidation sources keep this exact: the bar's own OnSizeChanged (covers any
-- resize, including live Edit Mode drags) and Prediction.Apply (deterministic
-- for every config/layout apply, and the path that installs the hook).
local function InvalidateHpGeometry(hpBar)
  if hpBar then hpBar._msufPredGeomReady = nil end
end

local function OnHpGeometryChanged(hpBar)
  hpBar._msufPredGeomReady = nil
end

local function EnsureHpGeometryHook(hpBar)
  if not hpBar or hpBar._msufPredGeomHooked == true or not hpBar.HookScript then return end
  hpBar._msufPredGeomHooked = true
  hpBar:HookScript("OnSizeChanged", OnHpGeometryChanged)
end

-- Extent of the HP bar along the fill axis. Non-positive measurements are
-- cached as nil so the caller's configured fallback still applies, exactly as
-- the previous inline measure did; a later resize re-arms the cache.
local function HpAlongSize(hpBar, vertical, runtimeWidth)
  if hpBar._msufPredGeomReady ~= true then
    local w = hpBar.GetWidth and hpBar:GetWidth() or nil
    local h = hpBar.GetHeight and hpBar:GetHeight() or nil
    if not w or w <= 0 then w = nil end
    if not h or h <= 0 then h = nil end
    hpBar._msufPredGeomW = w
    hpBar._msufPredGeomH = h
    hpBar._msufPredGeomReady = true
  end
  if vertical then
    return hpBar._msufPredGeomH or 1
  end
  return hpBar._msufPredGeomW or runtimeWidth or 1
end

-- Overlay StatusBars fill along the same axis as the HP bar. Orientation is a
-- set-once native flag; the swipe below re-applies reverse fill after any axis
-- flip because SetOrientation can reset it on some clients.
local function ApplyOverlayOrientation(bar, vertical)
  if not bar.SetOrientation then return end
  local orientation = vertical and "VERTICAL" or "HORIZONTAL"
  if bar._msufPredictionBarOrientation ~= orientation then
    bar:SetOrientation(orientation)
    bar._msufPredictionBarOrientation = orientation
    bar._msufReverseFill = nil
  end
end

-- Overflow host for anchor mode 4.
--
-- Mode 4 overlays keep the HP bar's full scale (value/max over one bar width) so
-- the heal/absorb segment stays proportional, which means an amount larger than
-- the missing health would otherwise draw arbitrarily far past the frame -- into
-- the neighbouring group frame. Blizzard bounds the same overflow at
-- MAX_INCOMING_HEAL_OVERFLOW (1.05) by clamping the amount, but that arithmetic
-- needs current health, which is a secret value here. A clipping host reaches
-- the identical result natively: the bar keeps its true scale and the client
-- trims whatever leaves the allowance. The cross axis is left effectively
-- unclipped so stripe heights and vertical offsets are never cut.
local OVERFLOW_ALLOWANCE = 0.05
local OVERFLOW_CROSS_MARGIN = 250

local function EnsureOverflowClip(frame, hpBar, vertical, reverse, alongSize)
  local clip = frame._msufPredictionOverflowClip
  if not clip then
    if not CreateFrame or frame._msufPredictionOverflowUnsupported == true then return nil end
    local created = CreateFrame("Frame", nil, frame)
    -- Without native clipping the host cannot bound anything, so keep the
    -- previous behaviour (parent straight to the frame) instead of adding an
    -- inert layer, and stop rebuilding a host that can never work.
    if not (created and created.SetClipsChildren) then
      frame._msufPredictionOverflowUnsupported = true
      return nil
    end
    if created.EnableMouse then created:EnableMouse(false) end
    created:SetClipsChildren(true)
    clip = created
    frame._msufPredictionOverflowClip = clip
  end

  if clip.SetFrameLevel and hpBar.GetFrameLevel then
    local baseLevel = hpBar:GetFrameLevel()
    if issecretvalue(baseLevel) ~= true and clip._msufOverflowLevel ~= baseLevel then
      clip:SetFrameLevel(baseLevel or 1)
      clip._msufOverflowLevel = baseLevel
    end
  end

  local allowance = (tonumber(alongSize) or 0) * OVERFLOW_ALLOWANCE
  if clip._msufOverflowAnchor == hpBar
    and clip._msufOverflowVertical == vertical
    and clip._msufOverflowReverse == reverse
    and clip._msufOverflowAllowance == allowance then
    return clip
  end
  clip._msufOverflowAnchor = hpBar
  clip._msufOverflowVertical = vertical
  clip._msufOverflowReverse = reverse
  clip._msufOverflowAllowance = allowance

  clip:ClearAllPoints()
  local margin = OVERFLOW_CROSS_MARGIN
  if vertical then
    -- Fill axis is vertical: the allowance sits at the fill end (top for a
    -- bottom->top HP bar, bottom when reversed).
    if reverse then
      clip:SetPoint("TOPLEFT", hpBar, "TOPLEFT", -margin, 0)
      clip:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", margin, -allowance)
    else
      clip:SetPoint("TOPLEFT", hpBar, "TOPLEFT", -margin, allowance)
      clip:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", margin, 0)
    end
  elseif reverse then
    clip:SetPoint("TOPLEFT", hpBar, "TOPLEFT", -allowance, margin)
    clip:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, -margin)
  else
    clip:SetPoint("TOPLEFT", hpBar, "TOPLEFT", 0, margin)
    clip:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", allowance, -margin)
  end
  return clip
end

-- Hot-path guards read the host without building or moving it; a still missing
-- host simply reports a stale layout and lets LayoutBar create it.
local function OverflowParent(frame)
  return frame._msufPredictionOverflowClip or frame
end

local function LayoutBar(frame, bar, levelOffset, mode, reverse, followBar, height, offsetY)
  local hpBar = frame.hpBar or frame.Health
  if not (bar and hpBar) then
    return
  end
  local followSource = (mode == 3 or mode == 4) and followBar or nil
  local follow = (mode == 3 or mode == 4) and (followSource and StatusTexture(followSource) or StatusTexture(hpBar)) or nil
  local vertical = frame._msufPredictionVertical == true
  -- Extent along the fill axis only: width horizontally, height vertically. The
  -- cross axis is pinned by the corner anchors, so it is never measured. Served
  -- from the size-change-invalidated cache -- no native measure per event.
  local width = HpAlongSize(hpBar, vertical, tonumber(frame._msufPredictionFrameWidth))
  local anchorTarget = follow or hpBar
  local parent = hpBar
  if mode == 4 then
    parent = EnsureOverflowClip(frame, hpBar, vertical,
      frame._msufPredictionHpReverse == true, width) or frame
  end
  local parentCurrent = not bar.GetParent or bar:GetParent() == parent
  height = height or 0
  offsetY = offsetY or 0

  local layoutCurrent = bar._msufPredictionMode == mode
    and bar._msufPredictionReverse == reverse
    and bar._msufPredictionFollowBar == followSource
    and bar._msufPredictionAnchorTarget == anchorTarget
    and bar._msufPredictionWidth == width
    and bar._msufPredictionParent == parent
    and bar._msufPredictionLevelOffset == levelOffset
    and bar._msufPredictionHeight == height
    and bar._msufPredictionOffsetY == offsetY
    and bar._msufPredictionVertical == vertical
    and bar._msufReverseFill == reverse
    and parentCurrent
  if layoutCurrent and PredictionLayerCurrent(frame, hpBar, bar, levelOffset) then
    return
  end

  local parentChanged = SetParentCached(bar, parent)
  SyncBarLayer(frame, hpBar, bar, levelOffset, parentChanged)
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
    or bar._msufPredictionHeight ~= height
    or bar._msufPredictionOffsetY ~= offsetY
    or bar._msufPredictionVertical ~= vertical
    or parentChanged then
    bar:ClearAllPoints()
    if vertical then
      -- Vertical fill rotates the horizontal layout 90 degrees. Along-axis is
      -- height (fills bottom->top, or top->bottom when reverse); cross-axis is
      -- width. The `height` param (stripe thickness) maps to width and `offsetY`
      -- becomes a horizontal (cross-axis) nudge.
      if follow then
        bar:SetHeight(width)
        if height > 0 then
          bar:SetWidth(height)
          if reverse then
            bar:SetPoint("TOP", follow, "BOTTOM", offsetY, 0)
          else
            bar:SetPoint("BOTTOM", follow, "TOP", offsetY, 0)
          end
        elseif reverse then
          bar:SetPoint("TOPLEFT", follow, "BOTTOMLEFT", offsetY, 0)
          bar:SetPoint("TOPRIGHT", follow, "BOTTOMRIGHT", offsetY, 0)
        else
          bar:SetPoint("BOTTOMLEFT", follow, "TOPLEFT", offsetY, 0)
          bar:SetPoint("BOTTOMRIGHT", follow, "TOPRIGHT", offsetY, 0)
        end
      elseif height > 0 then
        bar:SetWidth(height)
        bar:SetPoint("BOTTOM", hpBar, "BOTTOM", offsetY, 0)
        bar:SetPoint("TOP", hpBar, "TOP", offsetY, 0)
      elseif offsetY ~= 0 then
        bar:SetPoint("TOPLEFT", hpBar, "TOPLEFT", offsetY, 0)
        bar:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", offsetY, 0)
      else
        bar:SetAllPoints(hpBar)
      end
    elseif follow then
      bar:SetWidth(width)
      if height > 0 then
        bar:SetHeight(height)
        if reverse then
          bar:SetPoint("RIGHT", follow, "LEFT", 0, offsetY)
        else
          bar:SetPoint("LEFT", follow, "RIGHT", 0, offsetY)
        end
      elseif reverse then
        bar:SetPoint("TOPRIGHT", follow, "TOPLEFT", 0, offsetY)
        bar:SetPoint("BOTTOMRIGHT", follow, "BOTTOMLEFT", 0, offsetY)
      else
        bar:SetPoint("TOPLEFT", follow, "TOPRIGHT", 0, offsetY)
        bar:SetPoint("BOTTOMLEFT", follow, "BOTTOMRIGHT", 0, offsetY)
      end
    elseif height > 0 then
      bar:SetHeight(height)
      bar:SetPoint("LEFT", hpBar, "LEFT", 0, offsetY)
      bar:SetPoint("RIGHT", hpBar, "RIGHT", 0, offsetY)
    elseif offsetY ~= 0 then
      bar:SetPoint("TOPLEFT", hpBar, "TOPLEFT", 0, offsetY)
      bar:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, offsetY)
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
    bar._msufPredictionHeight = height
    bar._msufPredictionOffsetY = offsetY
    bar._msufPredictionVertical = vertical
  end
  ApplyOverlayOrientation(bar, vertical)
  if bar.SetReverseFill and bar._msufReverseFill ~= reverse then
    bar:SetReverseFill(reverse)
    bar._msufReverseFill = reverse
  end
end

local function PredictionLayoutCurrent(frame, bar, levelOffset, mode, reverse, followBar, height, offsetY)
  local hpBar = frame and (frame.hpBar or frame.Health)
  if not (bar and hpBar) then
    return false
  end
  local followSource = (mode == 3 or mode == 4) and followBar or nil
  local follow = (mode == 3 or mode == 4) and (followSource and StatusTexture(followSource) or StatusTexture(hpBar)) or nil
  local vertical = frame._msufPredictionVertical == true
  -- Cached along-axis extent (see LayoutBar): this guard is the per-event hot
  -- path, so it must not measure the bar natively.
  local width = HpAlongSize(hpBar, vertical, tonumber(frame._msufPredictionFrameWidth))
  local anchorTarget = follow or hpBar
  local parent = (mode == 4) and OverflowParent(frame) or hpBar
  height = height or 0
  offsetY = offsetY or 0
  return bar._msufPredictionMode == mode
    and bar._msufPredictionReverse == reverse
    and bar._msufPredictionFollowBar == followSource
    and bar._msufPredictionAnchorTarget == anchorTarget
    and bar._msufPredictionWidth == width
    and bar._msufPredictionParent == parent
    and bar._msufPredictionLevelOffset == levelOffset
    and bar._msufPredictionHeight == height
    and bar._msufPredictionOffsetY == offsetY
    and bar._msufPredictionVertical == vertical
    and bar._msufReverseFill == reverse
    and (not bar.GetParent or bar:GetParent() == parent)
    and PredictionLayerCurrent(frame, hpBar, bar, levelOffset)
end

local function LayoutBarIfNeeded(frame, bar, levelOffset, mode, reverse, followBar, height, offsetY)
  if PredictionLayoutCurrent(frame, bar, levelOffset, mode, reverse, followBar, height, offsetY) then
    return
  end
  LayoutBar(frame, bar, levelOffset, mode, reverse, followBar, height, offsetY)
end

local function LayoutHealAbsorbBar(frame, bar, levelOffset, hpReverse, mode, height, offsetY)
  local hpBar = frame and (frame.hpBar or frame.Health)
  if not (bar and hpBar) then
    return
  end
  mode = mode or 3
  height = height or 0
  offsetY = offsetY or 0
  if mode ~= 3 then
    bar._msufHealAbsorbMode = nil
    return LayoutBar(frame, bar, levelOffset, mode, ReverseForMode(mode, hpReverse), nil, height, offsetY)
  end
  local hpTexture = StatusTexture(hpBar) or hpBar
  local vertical = frame._msufPredictionVertical == true
  -- Cached along-axis extent, as in LayoutBar.
  local width = HpAlongSize(hpBar, vertical, tonumber(frame._msufPredictionFrameWidth))
  local reverse = hpReverse ~= true

  local layoutCurrent = bar._msufHealAbsorbAnchorTarget == hpTexture
    and bar._msufHealAbsorbMode == mode
    and bar._msufHealAbsorbWidth == width
    and bar._msufHealAbsorbHpReverse == hpReverse
    and bar._msufHealAbsorbParent == hpBar
    and bar._msufHealAbsorbLevelOffset == levelOffset
    and bar._msufHealAbsorbHeight == height
    and bar._msufHealAbsorbOffsetY == offsetY
    and bar._msufHealAbsorbVertical == vertical
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

  local parentChanged = SetParentCached(bar, hpBar)
  SyncBarLayer(frame, hpBar, bar, levelOffset, parentChanged)
  if hpBar.SetClipsChildren and hpBar._msufPredictionClipsChildren ~= true then
    hpBar:SetClipsChildren(true)
    hpBar._msufPredictionClipsChildren = true
  end

  if bar._msufHealAbsorbAnchorTarget ~= hpTexture
    or bar._msufHealAbsorbMode ~= mode
    or bar._msufHealAbsorbWidth ~= width
    or bar._msufHealAbsorbHpReverse ~= hpReverse
    or bar._msufHealAbsorbParent ~= hpBar
    or bar._msufHealAbsorbHeight ~= height
    or bar._msufHealAbsorbOffsetY ~= offsetY
    or bar._msufHealAbsorbVertical ~= vertical
    or parentChanged then
    bar:ClearAllPoints()
    if vertical then
      -- Vertical mirror: the heal-absorb overlay tracks the HP fill edge on the
      -- fill axis (bottom for bottom->top HP, top for top->bottom HP). `height`
      -- (thickness) becomes width and `offsetY` a horizontal nudge.
      bar:SetHeight(width)
      if height > 0 then
        bar:SetWidth(height)
        if hpReverse == true then
          bar:SetPoint("BOTTOM", hpTexture, "BOTTOM", offsetY, 0)
        else
          bar:SetPoint("TOP", hpTexture, "TOP", offsetY, 0)
        end
      elseif hpReverse == true then
        bar:SetPoint("BOTTOMLEFT", hpTexture, "BOTTOMLEFT", offsetY, 0)
        bar:SetPoint("BOTTOMRIGHT", hpTexture, "BOTTOMRIGHT", offsetY, 0)
      else
        bar:SetPoint("TOPLEFT", hpTexture, "TOPLEFT", offsetY, 0)
        bar:SetPoint("TOPRIGHT", hpTexture, "TOPRIGHT", offsetY, 0)
      end
    else
      bar:SetWidth(width)
      if height > 0 then
        bar:SetHeight(height)
        if hpReverse == true then
          bar:SetPoint("LEFT", hpTexture, "LEFT", 0, offsetY)
        else
          bar:SetPoint("RIGHT", hpTexture, "RIGHT", 0, offsetY)
        end
      elseif hpReverse == true then
        bar:SetPoint("TOPLEFT", hpTexture, "TOPLEFT", 0, offsetY)
        bar:SetPoint("BOTTOMLEFT", hpTexture, "BOTTOMLEFT", 0, offsetY)
      else
        bar:SetPoint("TOPRIGHT", hpTexture, "TOPRIGHT", 0, offsetY)
        bar:SetPoint("BOTTOMRIGHT", hpTexture, "BOTTOMRIGHT", 0, offsetY)
      end
    end
    bar._msufPredictionMode = nil
    bar._msufHealAbsorbAnchorTarget = hpTexture
    bar._msufHealAbsorbMode = mode
    bar._msufHealAbsorbWidth = width
    bar._msufHealAbsorbHpReverse = hpReverse
    bar._msufHealAbsorbParent = hpBar
    bar._msufHealAbsorbHeight = height
    bar._msufHealAbsorbOffsetY = offsetY
    bar._msufHealAbsorbVertical = vertical
  end
  bar._msufHealAbsorbLevelOffset = levelOffset

  ApplyOverlayOrientation(bar, vertical)
  if bar.SetReverseFill and bar._msufReverseFill ~= reverse then
    bar:SetReverseFill(reverse)
    bar._msufReverseFill = reverse
  end
end

local function MixedFollowNeedsClamp(cfg, healMode, absorbMode)
  return cfg ~= nil
    and cfg.heal == true
    and cfg.absorb == true
    and absorbMode == 3
    and healMode ~= 3
    and healMode ~= 4
end

local function NeedsHealthEvent(cfg)
  if not (cfg and cfg.absorb == true) then return false end
  local healMode = NormalizeAnchorMode(cfg.healAnchorMode, 3)
  local absorbMode = NormalizeAnchorMode(cfg.absorbAnchorMode, 2)
  return cfg.overAbsorbOverlay == true
    or cfg.fullHealthAbsorbStripe == true
    or MixedFollowNeedsClamp(cfg, healMode, absorbMode)
end

local function PredictionMask(cfg)
  if not (cfg and cfg.enabled == true) or cfg.test == true then
    return 0
  end
  return (cfg.heal == true and 1 or 0)
    + (cfg.absorb == true and 2 or 0)
    + (cfg.healAbsorb == true and 4 or 0)
end

local function PredictionPlan(refreshHeal, refreshAbsorb, refreshHealAbsorb, showHeal, showAbsorb, showHealAbsorb, forceMax)
  return {
    refreshHeal or nil,
    refreshAbsorb or nil,
    refreshHealAbsorb or nil,
    showHeal or nil,
    showAbsorb or nil,
    showHealAbsorb or nil,
    forceMax or nil,
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
        for field = 1, PLAN_FORCE_MAX do
          if plan[field] then merged[field] = true end
        end
      end
    end
  end
  return merged
end

local predictionPlanCache = {}

local function PredictionPlanCacheKey(heal, absorb, healAbsorb, followAbsorb)
  return (heal and 1 or 0)
    + (absorb and 2 or 0)
    + (healAbsorb and 4 or 0)
    + (followAbsorb and 8 or 0)
end

local function CompilePredictionPlans(cfg, followAbsorb)
  local heal = cfg and cfg.heal == true
  local absorb = cfg and cfg.absorb == true
  local healAbsorb = cfg and cfg.healAbsorb == true
  local key = PredictionPlanCacheKey(heal, absorb, healAbsorb, followAbsorb)
  local cached = predictionPlanCache[key]
  if cached then
    return cached[1], cached[2]
  end
  local plans = {}

  if heal then
    plans.UNIT_HEAL_PREDICTION = PredictionPlan(true, nil, nil, true, followAbsorb)
  end
  if absorb then
    plans.UNIT_ABSORB_AMOUNT_CHANGED = PredictionPlan(nil, true, nil, nil, true)
  end
  if healAbsorb then
    plans.UNIT_HEAL_ABSORB_AMOUNT_CHANGED = PredictionPlan(nil, nil, true, nil, nil, true)
  end
  if heal or absorb or healAbsorb then
    plans.UNIT_MAXHEALTH = PredictionPlan(heal, absorb, healAbsorb, heal, absorb, healAbsorb, true)
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

  local fullPlan = PredictionPlan(heal, absorb, healAbsorb, heal, absorb, healAbsorb, true)
  predictionPlanCache[key] = { plans, fullPlan }
  return plans, fullPlan
end

local Prediction = { UpdateOnApply = true }
local ActivatePredictionLifecycle
local DeactivatePredictionLifecycle
local CancelQueuedPrediction
local UpdateFull
local UpdateBoundPredictionData
local UpdateGlowHealthFast
local UpdateMixedFollowHealthFast
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
  -- Invalidate queued data from the previous unit/configuration. Apply and
  -- Disable are cold paths, so remove the pending entry outright instead of
  -- waking the shared render driver for a known no-op.
  if CancelQueuedPrediction then
    CancelQueuedPrediction(frame)
  end
  frame._msufPredictionDirtyMask = nil
  frame._msufPredictionCacheReady = nil
  frame._msufPredictionCacheUnit = nil
  frame._msufPredictionCacheCfg = nil
  frame._msufPredictionIncoming = nil
  frame._msufPredictionAbsorb = nil
  frame._msufPredictionHealAbsorb = nil
  frame._msufPredictionHealthVisualActive = nil
  frame._msufPredictionPartialGlowHealthActive = nil
  frame._msufPredictionHealthMax = nil
  frame._msufPredictionHealthMaxUnit = nil
  ClearBarValueCache(frame.incomingHealBar)
  ClearBarValueCache(frame.absorbBar)
  ClearBarValueCache(frame.healAbsorbBar)
end

-- FLAT prediction writer for the plain-bar archetype: any combination of an
-- incoming-heal bar, an absorb bar, and a heal-absorb bar with STATIC anchors
-- and NO over-absorb overlay/stripe and NO mixed follow-clamp. This is exactly
-- the flat absorb+heal-prediction shape. It skips the general
-- ApplyPredictionValues state machine (per-lane show/refresh branch pairs,
-- follow-layout checks, over-absorb glow) and does the one thing a data event
-- changes: read the dirty lane(s) from the mask and write the bar(s) with
-- ShowValue's own dedup. Only the lanes flagged in the mask are read, matching
-- the general path's refresh gating so a heal event never reads the absorb API
-- and vice versa. Compiled onto the frame only when the archetype matches.
local function FlushFlatPrediction(frame, mask)
  if type(mask) ~= "number" then mask = 7 end
  local unit = frame.MSUFUnitKey
  -- Resolve which lanes this event touches before doing any work: the mask
  -- selects heal(1)/absorb(2)/heal-absorb(4), gated on the lane being active
  -- and its bar existing. Reading the plain HP max is deferred until we know at
  -- least one lane will render -- and read at most once, with no per-call
  -- closure (this is a per-member, per-event hot path; a boxed upvalue frame
  -- here is pure GC churn a flat writer never pays).
  local doHeal = (mask % 2) >= 1 and frame._msufPredictionHealActive == true and frame.incomingHealBar
  local doAbsorb = (mask % 4) >= 2 and frame._msufPredictionAbsorbActive == true and frame.absorbBar
  local doHealAbsorb = mask >= 4 and frame._msufPredictionHealAbsorbActive == true and frame.healAbsorbBar
  if doHeal or doAbsorb or doHealAbsorb then
    local maxHP
    local hpBar = frame.hpBar
    if hpBar and hpBar._msufHealthMaxReady == true and hpBar._msufHealthMaxUnit == unit then
      maxHP = hpBar._msufHealthMax
    end
    if issecretvalue(maxHP) ~= true and maxHP == nil then
      maxHP = ReadHealthMax(frame, unit)
    end
    if doHeal then
      local incoming = ReadIncomingHeals(unit)
      frame._msufPredictionIncoming = incoming
      ShowValue(frame.incomingHealBar, maxHP, incoming, false)
    end
    if doAbsorb then
      local readAbsorb = frame._msufPredictionReadAbsorb or ReadDamageAbsorbs
      local absorb = readAbsorb(frame, unit)
      frame._msufPredictionAbsorb = absorb
      ShowValue(frame.absorbBar, maxHP, absorb, false)
    end
    if doHealAbsorb then
      local healAbsorb = ReadHealAbsorbs(unit)
      frame._msufPredictionHealAbsorb = healAbsorb
      ShowValue(frame.healAbsorbBar, maxHP, healAbsorb, false)
    end
  end
  -- No reseed-cache bookkeeping here: the cache fields are read only by the
  -- health-gated glow/stripe and general reseed paths, none of which run for a
  -- flat frame (no health-dependent visual). A cold general refresh finding the
  -- cache unset simply reseeds fully -- the safe direction -- so keeping it
  -- unset costs nothing and saves three field writes + an issecretvalue on
  -- every per-event flush, which is the whole point of this archetype.
end

-- Plain-bar archetype: static anchors (no absorb follow), no over-absorb
-- overlay/stripe, no mixed follow-clamp. Heal / absorb / heal-absorb bars in
-- any combination are fine -- none of them layout on a data event.
local function IsFlatPredictionArchetype(cfg, followAbsorb, mixedFollowClamp)
  return cfg.overAbsorbOverlay ~= true
    and cfg.fullHealthAbsorbStripe ~= true
    and followAbsorb ~= true
    and mixedFollowClamp ~= true
end

local function CompilePredictionRuntime(frame, cfg, spec)
  if not frame then
    return
  end
  cfg = cfg or {}
  local hpReverse = spec and spec.health and spec.health.reverse == true
  local healMode = NormalizeAnchorMode(cfg.healAnchorMode, 3)
  local absorbMode = NormalizeAnchorMode(cfg.absorbAnchorMode, 2)
  local healAbsorbMode = NormalizeAnchorMode(cfg.healAbsorbAnchorMode, 3)
  local followAbsorb = cfg.absorb == true and (absorbMode == 3 or absorbMode == 4)
  local mixedFollowClamp = MixedFollowNeedsClamp(cfg, healMode, absorbMode)
  frame._msufPredictionRuntimeCfg = cfg
  frame._msufPredictionFrameWidth = tonumber(spec and spec.width) or nil
  frame._msufPredictionHpReverse = hpReverse
  -- Fill axis for HP: overlays anchor along the same axis (see LayoutBar /
  -- LayoutHealAbsorbBar / PositionOverAbsorbGlow). reverse still flips direction
  -- within the axis; vertical only swaps which axis is the fill axis.
  frame._msufPredictionVertical = spec and spec.health and spec.health.vertical == true
  frame._msufPredictionHealMode = healMode
  frame._msufPredictionAbsorbMode = absorbMode
  frame._msufPredictionHealAbsorbMode = healAbsorbMode
  frame._msufPredictionHealHeight = tonumber(cfg.healHeight) or 0
  frame._msufPredictionHealOffsetY = tonumber(cfg.healOffsetY) or 0
  frame._msufPredictionAbsorbHeight = tonumber(cfg.absorbHeight) or 0
  frame._msufPredictionAbsorbOffsetY = tonumber(cfg.absorbOffsetY) or 0
  frame._msufPredictionHealAbsorbHeight = tonumber(cfg.healAbsorbHeight) or 0
  frame._msufPredictionHealAbsorbOffsetY = tonumber(cfg.healAbsorbOffsetY) or 0
  frame._msufPredictionHealReverse = ReverseForMode(healMode, hpReverse)
  frame._msufPredictionAbsorbReverse = ReverseForMode(absorbMode, hpReverse)
  frame._msufPredictionMask = PredictionMask(cfg)
  frame._msufPredictionHealActive = cfg.heal == true
  frame._msufPredictionAbsorbActive = cfg.absorb == true
  frame._msufPredictionHealAbsorbActive = cfg.healAbsorb == true
  frame._msufPredictionNeedsHealth = NeedsHealthEvent(cfg)
  frame._msufPredictionFollowAbsorb = followAbsorb
  frame._msufPredictionMixedFollowClamp = mixedFollowClamp
  frame._msufPredictionReadAbsorb = mixedFollowClamp and ReadMixedFollowAbsorbs or ReadDamageAbsorbs
  frame._msufPredictionOverAbsorbOverlay = cfg.absorb == true and cfg.overAbsorbOverlay == true
  frame._msufPredictionFullHealthStripe = cfg.absorb == true and cfg.fullHealthAbsorbStripe == true
  frame._msufPredictionFullHealthAlphaDirty = true
  frame._msufPredictionEventPlans, frame._msufPredictionFullPlan = CompilePredictionPlans(cfg, followAbsorb)
  if frame._msufPredictionNeedsHealth == true and cfg.test ~= true then
    if mixedFollowClamp then
      frame._msufUpdatePredictionHealthValue = UpdateMixedFollowHealthFast
    else
      frame._msufUpdatePredictionHealthValue = UpdateGlowHealthFast
    end
  else
    frame._msufUpdatePredictionHealthValue = Prediction.UpdateHealthValue
  end
  frame._msufUpdatePredictionConnectionState = Prediction.UpdateConnectionState
  if frame._msufPredictionMask ~= 0 and cfg.test ~= true then
    if IsFlatPredictionArchetype(cfg, followAbsorb, mixedFollowClamp) then
      frame._msufPredictionFlushData = FlushFlatPrediction
      frame._msufPredictionSimpleAbsorb = true
    else
      frame._msufPredictionFlushData = UpdateBoundPredictionData
      frame._msufPredictionSimpleAbsorb = nil
    end
  else
    frame._msufPredictionFlushData = nil
    frame._msufPredictionSimpleAbsorb = nil
  end
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
    (frame and frame.MSUFUnitKey) or (spec and spec.key)
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

local function ApplyPredictionBar(frame, cfg, spec, bar, active, level, mode, reverse, textureKey, rKey, gKey, bKey, aKey, follow, height, offsetY)
  if not bar then return end
  LayoutBar(frame, bar, level, mode, reverse, follow, height, offsetY)
  SetTextureCached(bar, ResolveTexture(cfg[textureKey], spec and spec.texture or WHITE))
  SetColorCached(bar, cfg[rKey], cfg[gKey], cfg[bKey], cfg[aKey])
  if active ~= true then HideBar(bar) end
end

local function ApplyHealAbsorbBar(frame, cfg, spec, bar)
  if not bar then return end
  LayoutHealAbsorbBar(frame, bar, 3, frame._msufPredictionHpReverse == true,
    frame._msufPredictionHealAbsorbMode,
    frame._msufPredictionHealAbsorbHeight, frame._msufPredictionHealAbsorbOffsetY)
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
  -- Apply is the authoritative geometry boundary: drop the cached HP-bar
  -- measurement and make sure the bar reports later resizes itself, so the
  -- per-event layout guard never has to measure.
  do
    local hpBar = frame.hpBar or frame.Health
    InvalidateHpGeometry(hpBar)
    EnsureHpGeometryHook(hpBar)
  end
  CompilePredictionRuntime(frame, cfg, spec)
  if frame._msufPredictionFullHealthStripe == true then
    -- Curve construction is immutable feature setup. Do it with Apply/layout
    -- work rather than on the first protected combat health event.
    EnsureFullHealthCurve()
  end
  local healMode = frame._msufPredictionHealMode or NormalizeAnchorMode(cfg.healAnchorMode, 3)
  local absorbMode = frame._msufPredictionAbsorbMode or NormalizeAnchorMode(cfg.absorbAnchorMode, 2)

  ApplyPredictionBar(frame, cfg, spec, frame.incomingHealBar, cfg.heal,
    1, healMode, frame._msufPredictionHealReverse,
    "texture", "healR", "healG", "healB", "healA", nil,
    frame._msufPredictionHealHeight, frame._msufPredictionHealOffsetY)
  ApplyPredictionBar(frame, cfg, spec, frame.absorbBar, cfg.absorb,
    2, absorbMode, frame._msufPredictionAbsorbReverse,
    "absorbTexture", "absorbR", "absorbG", "absorbB", "absorbA",
    VisibleFollowBar(cfg, frame.incomingHealBar),
    frame._msufPredictionAbsorbHeight, frame._msufPredictionAbsorbOffsetY)
  if cfg.absorb == true and (cfg.overAbsorbOverlay == true or cfg.fullHealthAbsorbStripe == true) then
    PositionOverAbsorbGlow(frame, frame._msufPredictionHpReverse == true)
  else
    HideOverAbsorbGlow(frame)
  end
  ApplyHealAbsorbBar(frame, cfg, spec, frame.healAbsorbBar)
end

local function SuspendPrediction(frame, preserveRuntime)
  if not frame then return end
  if frame._msufPredictionDisabled == true
    and (preserveRuntime == true or frame._msufPredictionRuntimeCfg == nil) then
    return
  end
  for i = 1, #PREDICTION_BAR_DEFS do
    HideBar(frame[PREDICTION_BAR_DEFS[i][2]])
  end
  HideOverAbsorbGlow(frame)
  ClearPredictionCache(frame)
  if preserveRuntime == true then
    -- The unit token (for example "target") can reappear with a different
    -- identity. Keep immutable compiled routes, but invalidate unit-owned state.
    frame._msufPredictionConnectionUnit = nil
    frame._msufPredictionConnectionOnline = nil
    frame._msufPredictionFullHealthAlphaReady = nil
    frame._msufPredictionFullHealthAlphaDirty = true
    frame._msufPredictionFullHealthAlphaUnit = nil
  else
    for i = 1, #PREDICTION_DISABLE_FIELDS do
      frame[PREDICTION_DISABLE_FIELDS[i]] = nil
    end
    frame._msufPredictionMask = 0
  end
  frame._msufPredictionDisabled = true
end

function Prediction.Enable(frame)
  if not frame then return false end
  if ActivatePredictionLifecycle then ActivatePredictionLifecycle(frame) end
  return true
end

function Prediction.Disable(frame)
  if not frame then return end
  SuspendPrediction(frame)
  if DeactivatePredictionLifecycle then DeactivatePredictionLifecycle(frame) end
end

-- Rare compatibility path for absorb-follow combined with an independently
-- anchored incoming-heal bar. It refreshes only the one calculator-clamped
-- absorb value; incoming heals and heal absorbs remain prediction-event-only.
local function UpdateMixedFollowHealthValue(frame, unit, cfg, seedHP, seedMaxHP)
  local bar = frame and frame.absorbBar
  if not bar then return end
  local readAbsorb = frame._msufPredictionReadAbsorb or ReadMixedFollowAbsorbs
  local absorb = readAbsorb(frame, unit)
  frame._msufPredictionAbsorb = absorb
  frame._msufPredictionCacheReady = true
  frame._msufPredictionCacheUnit = issecretvalue(unit) ~= true and unit or nil
  frame._msufPredictionCacheCfg = cfg

  local follow = cfg.heal == true and frame.incomingHealBar
    and frame.incomingHealBar._msufShown == true and frame.incomingHealBar or nil
  LayoutBarIfNeeded(frame, bar, 2, 3, frame._msufPredictionAbsorbReverse, follow,
    frame._msufPredictionAbsorbHeight, frame._msufPredictionAbsorbOffsetY)
  local maxHP = seedMaxHP
  if bar._msufMaxReady ~= true and issecretvalue(maxHP) ~= true and maxHP == nil then
    maxHP = ReadHealthMax(frame, unit)
  end
  ShowValue(bar, maxHP, absorb)
  if frame._msufPredictionOverAbsorbOverlay == true
    or frame._msufPredictionFullHealthStripe == true then
    UpdateOverAbsorbGlow(frame, cfg, unit, seedHP, maxHP, absorb, true)
  end
end

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
local predictionDriverPersistent
local FlushPredictionQueue

CancelQueuedPrediction = function(frame)
  if not (frame and frame._msufPredictionQueued == true) then return false end
  for i = 1, predictionWriteCount do
    if predictionWriteQueue[i] == frame then
      predictionWriteQueue[i] = predictionWriteQueue[predictionWriteCount]
      predictionWriteQueue[predictionWriteCount] = nil
      predictionWriteCount = predictionWriteCount - 1
      break
    end
  end
  frame._msufPredictionQueued = nil
  frame._msufPredictionDirtyMask = nil
  if predictionWriteCount == 0 and predictionDriverArmed == true then
    if predictionDriverPersistent == true then
      predictionDriver:Hide()
    elseif predictionDriver and predictionDriver.SetScript then
      predictionDriver:SetScript("OnUpdate", nil)
    end
    predictionDriverArmed = nil
  end
  return true
end

local function ArmPredictionDriver()
  if predictionDriverArmed == true then return true end
  if not predictionDriver and CreateFrame then
    predictionDriver = CreateFrame("Frame")
    if predictionDriver and predictionDriver.SetScript
      and predictionDriver.Hide and predictionDriver.Show then
      predictionDriver:SetScript("OnUpdate", FlushPredictionQueue)
      predictionDriver:Hide()
      predictionDriverPersistent = true
    end
  end
  if not (predictionDriver and predictionDriver.SetScript) then return false end
  predictionDriverArmed = true
  if predictionDriverPersistent == true then
    predictionDriver:Show()
  else
    predictionDriver:SetScript("OnUpdate", FlushPredictionQueue)
  end
  return true
end

local function QueuePredictionDataEvent(frame, event)
  if not frame then return end
  local bit = PREDICTION_DATA_EVENT_BITS[event]
  if not bit then return end

  -- Flat archetype (plain heal/absorb bars, no health-gated glow/stripe): the
  -- writer is cheaper than the coalescer's own queue bookkeeping + OnUpdate
  -- driver arm/disarm, so a same-frame burst that "collapses" to one flush
  -- still costs more queued than just flushing each lane on the spot. Measured
  -- net-negative for this archetype -- so render this lane synchronously, which
  -- is exactly the flat per-event model. Every bar write is value-deduped
  -- downstream, and the flush touches only StatusBar values (combat-safe).
  if frame._msufPredictionSimpleAbsorb == true then
    local flush = frame._msufPredictionFlushData
    if flush then
      flush(frame, bit)
      return
    end
  end

  local mask = frame._msufPredictionDirtyMask or 0
  if (mask % (bit * 2)) < bit then
    frame._msufPredictionDirtyMask = mask + bit
  end
  -- The flat baseline renders absorb synchronously on the event (one UpdateAbsorb
  -- call, no render-frame driver). Opt-in parity: flush the accumulated mask
  -- immediately instead of queuing onto the OnUpdate coalescer. Every bar write
  -- downstream is value-deduped, so a same-frame burst still collapses to the
  -- writes that actually changed -- it just drops the per-frame driver arm +
  -- queue bookkeeping. Default keeps the coalescer (off unless the test toggle
  -- sets _G.MSUF_GF_PredictionSync).
  if _G.MSUF_GF_PredictionSync == true then
    frame._msufPredictionQueued = nil
    local syncMask = frame._msufPredictionDirtyMask
    frame._msufPredictionDirtyMask = nil
    if syncMask then
      local flush = frame._msufPredictionFlushData
      if flush then
        flush(frame, syncMask)
      else
        UpdateFull(frame, PREDICTION_DIRTY_PLAN_KEYS[syncMask], frame.MSUFUnitKey, nil, nil, true)
      end
    end
    return
  end
  if frame._msufPredictionQueued == true then return end
  frame._msufPredictionQueued = true
  predictionWriteCount = predictionWriteCount + 1
  predictionWriteQueue[predictionWriteCount] = frame
  if predictionDriverArmed == true or ArmPredictionDriver() then return end

  -- CreateFrame is unavailable only in non-WoW harnesses. Preserve behavior
  -- synchronously there instead of leaving a queued update stranded.
  predictionWriteQueue[predictionWriteCount] = nil
  predictionWriteCount = predictionWriteCount - 1
  frame._msufPredictionQueued = nil
  mask = frame._msufPredictionDirtyMask
  frame._msufPredictionDirtyMask = nil
  if mask then
    local flush = frame._msufPredictionFlushData
    if flush then
      flush(frame, mask)
    else
      UpdateFull(frame, PREDICTION_DIRTY_PLAN_KEYS[mask], frame.MSUFUnitKey, nil, nil, true)
    end
  end
end

FlushPredictionQueue = function()
  if predictionDriverPersistent == true then
    predictionDriver:Hide()
  elseif predictionDriver and predictionDriver.SetScript then
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
        local flush = frame._msufPredictionFlushData
        if flush then
          flush(frame, mask)
        else
          UpdateFull(frame, PREDICTION_DIRTY_PLAN_KEYS[mask], frame.MSUFUnitKey, nil, nil, true)
        end
      end
    end
  end

  -- A prediction API callback can synchronously queue more work. It belongs to
  -- the following rendered frame, never to the batch currently being drained.
  if predictionWriteCount > 0 then ArmPredictionDriver() end
end

function Prediction.UpdateHealthValue(frame, event, unit, seedHP, seedMaxHP)
  if not frame then return end
  if unit and issecretvalue(unit) == true then
    unit = frame.MSUFUnitKey
    seedHP, seedMaxHP = nil, nil
  elseif unit and unit ~= frame.MSUFUnitKey then
    return
  end
  unit = unit or frame.MSUFUnitKey
  local cfg = frame._msufPredictionRuntimeCfg
  if not cfg then
    local spec = frame.MSUFSpec
    cfg = spec and spec.prediction
    if cfg and cfg.enabled == true then CompilePredictionRuntime(frame, cfg, spec) end
  end
  if not (cfg and cfg.enabled == true)
    or cfg.test == true
    or frame._msufPredictionNeedsHealth ~= true
    or frame._msufPredictionMask == 0 then
    return
  end
  if UnitMissing(frame, unit, issecretvalue(unit) == true) then
    SuspendPrediction(frame, true)
    return
  end
  if frame._msufPredictionCacheReady ~= true
    or frame._msufPredictionCacheUnit ~= unit
    or frame._msufPredictionCacheCfg ~= cfg then
    HideOverAbsorbGlow(frame)
    return
  end
  frame._msufPredictionDisabled = nil
  if frame._msufPredictionMixedFollowClamp == true then
    return UpdateMixedFollowHealthValue(frame, unit, cfg, seedHP, seedMaxHP)
  end
  return UpdateOverAbsorbGlow(frame, cfg, unit, seedHP, seedMaxHP,
    frame._msufPredictionAbsorb, true)
end

-- Core has already C-filtered UNIT_HEALTH. The common route only updates the
-- optional edge visual from cached prediction payloads; it never reads one of
-- the three prediction APIs.
local function UpdateWarmFullHealthStripe(frame, unit)
  local holder = frame.overAbsorbGlowBar
  local hpBar = frame.hpBar or frame.Health
  local reverse = frame._msufPredictionHpReverse == true
  if not (holder and hpBar
    and holder._msufOverAbsorbReverse == reverse
    and holder._msufOverAbsorbAnchor == hpBar) then
    return false
  end

  -- A plain percent is already owned by Health. It is enough to resolve the
  -- full-health edge and, when partial over-absorb is enabled, lets the general
  -- threshold path reconstruct current health without another UnitHealth read.
  local pct = CachedHealthPercent(frame, unit)
  if issecretvalue(pct) ~= true and type(pct) == "number" then
    if pct < 100 then
      if frame._msufPredictionOverAbsorbOverlay == true then return false end
      HideOverAbsorbGlow(frame)
      return true
    end
    SetOverAbsorbAlpha(holder, 1)
  else
    -- A protected percentage cannot be passed into LuaCurve:Evaluate from
    -- addon code: that call is tainted even though the value itself came from
    -- UnitHealthPercent. Re-enter the native API with the curve so Blizzard
    -- performs the secret evaluation in untainted execution.
    local alpha = FullHealthAlpha(unit)
    local alphaSecret = issecretvalue(alpha) == true
    if not alphaSecret then
      if type(alpha) ~= "number" then return false end
      if alpha <= 0 then
        if frame._msufPredictionOverAbsorbOverlay == true then return false end
        HideOverAbsorbGlow(frame)
        return true
      end
    end
    SetOverAbsorbAlpha(holder, alpha)
  end

  frame._msufPredictionFullHealthAlphaReady = true
  frame._msufPredictionFullHealthAlphaDirty = nil
  frame._msufPredictionFullHealthAlphaUnit = unit
  if holder._msufOverAbsorbShown ~= true then
    holder:SetShown(true)
    holder._msufOverAbsorbShown = true
  end
  return true
end

UpdateGlowHealthFast = function(frame, event, unit, seedHP, seedMaxHP)
  if not frame then return end
  -- The absorb-data event owns this gate. Most group members have no absorb,
  -- so reject their health ticks before unit/config/cache/secret inspection.
  if frame._msufPredictionHealthVisualActive ~= true then return end
  unit = unit or frame.MSUFUnitKey
  local cfg = frame._msufPredictionRuntimeCfg
  if issecretvalue(unit) == true
    or unit ~= frame.MSUFUnitKey
    or frame._msufPredictionDisabled == true
    or not cfg
    or frame._msufPredictionCacheReady ~= true
    or frame._msufPredictionCacheUnit ~= unit
    or frame._msufPredictionCacheCfg ~= cfg then
    return Prediction.UpdateHealthValue(frame, event, unit, seedHP, seedMaxHP)
  end
  local absorb = frame._msufPredictionAbsorb
  -- Partial over-absorb cannot derive its threshold from protected health or
  -- absorb values. The absorb-data event already hides that unrenderable
  -- state and publishes this plain-positive gate, so steady UNIT_HEALTH ticks
  -- do not repeat secret/type/value inspection. Full-health stripe is
  -- different: its native value/alpha gates intentionally consume protected
  -- payloads.
  local absorbSecret = issecretvalue(absorb) == true
  if not absorbSecret and (type(absorb) ~= "number" or absorb <= 0) then
    return
  end
  -- Steady-tick dedupe (pure overlay, plain absorb). The overshield verdict is
  -- a function of the integer health-percent bucket and the absorb amount; it
  -- cannot change while both are unchanged. Skip the redundant render on
  -- health ticks that stay inside one display bucket -- the common case for a
  -- shielded member whose health jitters -- WITHOUT reimplementing the show
  -- test: a cache miss falls through to the authoritative UpdateOverAbsorbGlow,
  -- which owns the full-health / partial-spill decision. Every prediction data
  -- event clears this key (ApplyPredictionValues) so the next tick re-syncs.
  if frame._msufPredictionFullHealthStripe ~= true and not absorbSecret then
    local bar = frame.hpBar
    local pct = bar and bar._msufHealthPercentValue
    if pct ~= nil and issecretvalue(pct) ~= true and type(pct) == "number"
      and bar._msufHealthPercentUnit == unit then
      local bucket = pct - (pct % 1)
      if frame._msufGlowTickBucket == bucket
        and frame._msufGlowTickAbsorb == absorb
        and frame._msufGlowTickUnit == unit then
        return
      end
      frame._msufGlowTickBucket = bucket
      frame._msufGlowTickAbsorb = absorb
      frame._msufGlowTickUnit = unit
    else
      frame._msufGlowTickBucket = nil
      frame._msufGlowTickUnit = nil
    end
  end
  if frame._msufPredictionFullHealthStripe == true
    and UpdateWarmFullHealthStripe(frame, unit) then
    return
  end
  return UpdateOverAbsorbGlow(frame, cfg, unit, seedHP, seedMaxHP, absorb, true)
end

UpdateMixedFollowHealthFast = function(frame, event, unit, seedHP, seedMaxHP)
  if not frame then return end
  unit = unit or frame.MSUFUnitKey
  local cfg = frame._msufPredictionRuntimeCfg
  if issecretvalue(unit) == true
    or unit ~= frame.MSUFUnitKey
    or frame._msufPredictionDisabled == true
    or frame._msufPredictionMixedFollowClamp ~= true
    or not cfg
    or frame._msufPredictionCacheReady ~= true
    or frame._msufPredictionCacheUnit ~= unit
    or frame._msufPredictionCacheCfg ~= cfg then
    return Prediction.UpdateHealthValue(frame, event, unit, seedHP, seedMaxHP)
  end
  local holder = frame.overAbsorbGlowBar
  if holder and holder._msufOverAbsorbValuePlain == true then
    local gateValue = holder._msufOverAbsorbValue
    if type(gateValue) ~= "number" or gateValue <= 0 then return end
  end
  return UpdateMixedFollowHealthValue(frame, unit, cfg, seedHP, seedMaxHP)
end

function Prediction.UpdateConnectionState(frame, event, unit, seedHP, seedMaxHP)
  if unit and issecretvalue(unit) == true then
    unit = frame and frame.MSUFUnitKey or nil
    seedHP, seedMaxHP = nil, nil
  elseif unit and frame and unit ~= frame.MSUFUnitKey then
    return UpdateFull(frame, event, unit, seedHP, seedMaxHP)
  end
  unit = unit or frame.MSUFUnitKey
  local cfg = frame._msufPredictionRuntimeCfg
  if not (cfg and cfg.enabled == true)
    or cfg.test == true
    or frame._msufPredictionMask == 0 then
    return UpdateFull(frame, event, unit, seedHP, seedMaxHP)
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
    HideOverAbsorbGlow(frame)
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

  local result = UpdateFull(frame, event, unit, seedHP, seedMaxHP)
  if connected == true then
    frame._msufPredictionConnectionUnit = issecretvalue(unit) ~= true and unit or nil
    frame._msufPredictionConnectionOnline = true
  else
    frame._msufPredictionConnectionUnit = nil
    frame._msufPredictionConnectionOnline = nil
  end
  return result
end

local function ApplyPredictionValues(frame, cfg, unit, cacheUnit, event, hp, maxHP,
    refreshHeal, refreshAbsorb, refreshHealAbsorb,
    showHeal, showAbsorb, showHealAbsorb, forceMax)
  -- The live health-bar size -- never a stale spec width -- owns prediction
  -- geometry. Authoritative refreshes (UNIT_MAXHEALTH / UNIT_CONNECTION / full
  -- plan) therefore drop the cached measurement so both overlay types repair
  -- themselves here, exactly as they did when every event measured natively.
  -- High-frequency absorb/heal data events keep serving from the cache, which
  -- the bar's own OnSizeChanged invalidates the moment it actually resizes.
  if forceMax == true then
    InvalidateHpGeometry(frame.hpBar or frame.Health)
  end
  if refreshHeal then
    frame._msufPredictionIncoming = ReadIncomingHeals(unit)
  end
  if refreshAbsorb then
    local readAbsorb = frame._msufPredictionReadAbsorb or ReadDamageAbsorbs
    local absorb = readAbsorb(frame, unit)
    frame._msufPredictionAbsorb = absorb
    local absorbSecret = issecretvalue(absorb) == true
    local absorbPositive = not absorbSecret and type(absorb) == "number" and absorb > 0
    frame._msufPredictionHealthVisualActive = (absorbPositive
      or (absorbSecret and frame._msufPredictionFullHealthStripe == true)) and true or nil
    if frame._msufPredictionFullHealthStripe ~= true and absorbPositive then
      frame._msufPredictionPartialGlowHealthActive = true
    else
      frame._msufPredictionPartialGlowHealthActive = nil
    end
  end
  if refreshHealAbsorb then
    frame._msufPredictionHealAbsorb = ReadHealAbsorbs(unit)
  end
  if refreshHeal or refreshAbsorb or refreshHealAbsorb then
    frame._msufPredictionCacheReady = true
    frame._msufPredictionCacheUnit = cacheUnit
    frame._msufPredictionCacheCfg = cfg
    -- A prediction data event (absorb/heal/max) can change the overshield
    -- verdict at an unchanged health-percent bucket. Clear the steady-tick
    -- glow key so the next UNIT_HEALTH re-syncs through UpdateOverAbsorbGlow.
    frame._msufGlowTickBucket = nil
    frame._msufGlowTickUnit = nil
  end

  if showHeal and frame.incomingHealBar then
    local incoming = frame._msufPredictionIncoming
    if (forceMax == true or frame.incomingHealBar._msufMaxReady ~= true)
      and issecretvalue(maxHP) ~= true and maxHP == nil then
      maxHP = ReadHealthMax(frame, unit, forceMax)
    end
    ShowValue(frame.incomingHealBar, maxHP, incoming, forceMax)
  end

  if showAbsorb and frame.absorbBar then
    local absorbMode = frame._msufPredictionAbsorbMode
    if absorbMode == 3 or absorbMode == 4 then
      local follow = frame._msufPredictionHealActive == true
        and frame.incomingHealBar and frame.incomingHealBar._msufShown == true
        and frame.incomingHealBar or nil
      LayoutBarIfNeeded(frame, frame.absorbBar, 2, absorbMode,
        frame._msufPredictionAbsorbReverse, follow,
        frame._msufPredictionAbsorbHeight, frame._msufPredictionAbsorbOffsetY)
    end
    if (forceMax == true or frame.absorbBar._msufMaxReady ~= true)
      and issecretvalue(maxHP) ~= true and maxHP == nil then
      maxHP = ReadHealthMax(frame, unit, forceMax)
    end
    ShowValue(frame.absorbBar, maxHP, frame._msufPredictionAbsorb, forceMax)
    if frame._msufPredictionOverAbsorbOverlay == true
      or frame._msufPredictionFullHealthStripe == true then
      local glowAbsorb = frame._msufPredictionAbsorb
      if refreshAbsorb == true and frame._msufPredictionMixedFollowClamp == true then
        glowAbsorb = ReadDamageAbsorbs(frame, unit)
      end
      local holder = frame.overAbsorbGlowBar
      local knownInactive = refreshAbsorb == true
        and frame._msufPredictionFullHealthStripe ~= true
        and issecretvalue(glowAbsorb) ~= true
        and (type(glowAbsorb) ~= "number" or glowAbsorb <= 0)
        and (holder == nil or (holder._msufOverAbsorbShown == false
          and holder._msufOverAbsorbValuePlain == true
          and (type(holder._msufOverAbsorbValue) ~= "number"
            or holder._msufOverAbsorbValue <= 0)))
      if not knownInactive then
        UpdateOverAbsorbGlow(frame, cfg, unit, hp, maxHP, glowAbsorb,
          event == "UNIT_MAXHEALTH" or event == "UNIT_CONNECTION", refreshAbsorb == true)
      end
    end
  end

  if showHealAbsorb and frame.healAbsorbBar then
    -- Prediction data changes only the bar value. Static geometry is owned by
    -- Apply; authoritative full/max refreshes retain the defensive repair.
    if forceMax == true then
      LayoutHealAbsorbBar(frame, frame.healAbsorbBar, 3, frame._msufPredictionHpReverse == true,
        frame._msufPredictionHealAbsorbMode,
        frame._msufPredictionHealAbsorbHeight, frame._msufPredictionHealAbsorbOffsetY)
    end
    if (forceMax == true or frame.healAbsorbBar._msufMaxReady ~= true)
      and issecretvalue(maxHP) ~= true and maxHP == nil then
      maxHP = ReadHealthMax(frame, unit, forceMax)
    end
    ShowValue(frame.healAbsorbBar, maxHP, frame._msufPredictionHealAbsorb, forceMax)
  end
end

UpdateFull = function(frame, event, unit, seedHP, seedMaxHP, boundUnit, trustedActive)
  if boundUnit == true then
    unit = frame.MSUFUnitKey
  elseif unit and issecretvalue(unit) == true then
    unit = frame and frame.MSUFUnitKey or nil
    seedHP, seedMaxHP = nil, nil
  elseif unit and frame and unit ~= frame.MSUFUnitKey then
    unit = frame.MSUFUnitKey
    seedHP, seedMaxHP = nil, nil
  else
    unit = unit or frame.MSUFUnitKey
  end
  local unitSecret = boundUnit ~= true and issecretvalue(unit) == true
  local cfg = frame._msufPredictionRuntimeCfg
  if trustedActive ~= true then
    local spec
    if not cfg then
      spec = frame.MSUFSpec
      cfg = spec and spec.prediction
    end
    if not (cfg and cfg.enabled == true) then
      SuspendPrediction(frame)
      return
    end
    if frame._msufPredictionRuntimeCfg ~= cfg then
      CompilePredictionRuntime(frame, cfg, spec or frame.MSUFSpec)
    end
    if cfg.test ~= true and frame._msufPredictionMask == 0 then
      SuspendPrediction(frame)
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
      SuspendPrediction(frame, true)
      return
    end
  end
  frame._msufPredictionDisabled = nil

  local healMode = frame._msufPredictionHealMode or NormalizeAnchorMode(cfg.healAnchorMode, 3)
  local absorbMode = frame._msufPredictionAbsorbMode or NormalizeAnchorMode(cfg.absorbAnchorMode, 2)

  if trustedActive ~= true and cfg.test == true then
    local explicitTests = cfg.healTest ~= nil or cfg.absorbTest ~= nil or cfg.healAbsorbTest ~= nil
    local testHeal = cfg.healTest == true or not explicitTests
    local testAbsorb = cfg.absorbTest == true or not explicitTests
    local testHealAbsorb = cfg.healAbsorbTest == true or not explicitTests
    if testHeal and frame.incomingHealBar then
      LayoutBar(frame, frame.incomingHealBar, 1, healMode, frame._msufPredictionHealReverse, nil,
        frame._msufPredictionHealHeight, frame._msufPredictionHealOffsetY)
      ShowValue(frame.incomingHealBar, TEST_MAX, TEST_INCOMING)
    elseif frame.incomingHealBar then
      HideBar(frame.incomingHealBar)
    end
    if testAbsorb and frame.absorbBar then
      if absorbMode == 3 or absorbMode == 4 then
        local follow = VisibleFollowBar(cfg, frame.incomingHealBar)
        LayoutBar(frame, frame.absorbBar, 2, absorbMode, frame._msufPredictionAbsorbReverse, follow,
          frame._msufPredictionAbsorbHeight, frame._msufPredictionAbsorbOffsetY)
      end
      ShowValue(frame.absorbBar, TEST_MAX, TEST_ABSORB)
      UpdateOverAbsorbGlow(frame, cfg, unit, TEST_MAX, TEST_MAX, TEST_ABSORB, true, true)
    elseif frame.absorbBar then
      HideBar(frame.absorbBar)
      HideOverAbsorbGlow(frame)
    end
    if testHealAbsorb and frame.healAbsorbBar then
      LayoutHealAbsorbBar(frame, frame.healAbsorbBar, 3, frame._msufPredictionHpReverse == true,
        frame._msufPredictionHealAbsorbMode,
        frame._msufPredictionHealAbsorbHeight, frame._msufPredictionHealAbsorbOffsetY)
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
  if pendingMask then
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

  if not (refreshHeal or refreshAbsorb or refreshHealAbsorb or showHeal or showAbsorb or showHealAbsorb) then
    return
  end

  local hp, maxHP
  if issecretvalue(seedHP) == true or seedHP ~= nil then hp = seedHP end
  if issecretvalue(seedMaxHP) == true or seedMaxHP ~= nil then maxHP = seedMaxHP end
  return ApplyPredictionValues(frame, cfg, unit, unitSecret ~= true and unit or nil,
    event, hp, maxHP, refreshHeal, refreshAbsorb, refreshHealAbsorb,
    showHeal, showAbsorb, showHealAbsorb, forceMax)
end

-- Data events enter only through the compiled queue. Apply installs this
-- pointer for a live non-test plan, while Disable/Suspend clears it. Consume
-- the numeric dirty mask directly instead of re-entering UpdateFull's cold
-- unit/config/test/event-plan state machine on every rendered-frame drain.
-- Recovery alone falls back to UpdateFull so a stale/missing cache can rebuild
-- the authoritative runtime before the next hot drain.
UpdateBoundPredictionData = function(frame, mask)
  local unit = frame.MSUFUnitKey
  local cfg = frame._msufPredictionRuntimeCfg
  local plans = frame._msufPredictionEventPlans
  local plan = type(mask) == "number"
    and plans and plans[PREDICTION_DIRTY_PLAN_KEYS[mask]] or nil
  if type(mask) ~= "number"
    or not cfg
    or not plan
    or frame._msufPredictionDisabled == true
    or frame._msufPredictionCacheReady ~= true
    or frame._msufPredictionCacheUnit ~= unit
    or frame._msufPredictionCacheCfg ~= cfg then
    local event = type(mask) == "number" and PREDICTION_DIRTY_PLAN_KEYS[mask] or mask
    return UpdateFull(frame, event, unit, nil, nil, true)
  end

  return ApplyPredictionValues(frame, cfg, unit, unit, nil, nil, nil,
    plan[PLAN_REFRESH_HEAL], plan[PLAN_REFRESH_ABSORB], plan[PLAN_REFRESH_HEAL_ABSORB],
    plan[PLAN_SHOW_HEAL], plan[PLAN_SHOW_ABSORB], plan[PLAN_SHOW_HEAL_ABSORB], false)
end

function Prediction.Update(frame, event, unit, seedHP, seedMaxHP)
  if event == "UNIT_HEALTH" then
    return Prediction.UpdateHealthValue(frame, event, unit, seedHP, seedMaxHP)
  end
  if event == "UNIT_CONNECTION" then
    return Prediction.UpdateConnectionState(frame, event, unit, seedHP, seedMaxHP)
  end
  return UpdateFull(frame, event, unit, seedHP, seedMaxHP)
end

function Prediction.SelectEventUpdate(frame, _spec, event)
  if PREDICTION_DATA_EVENT_BITS[event] then
    return QueuePredictionDataEvent
  elseif event == "UNIT_HEALTH" then
    return frame and frame._msufUpdatePredictionHealthValue or Prediction.UpdateHealthValue
  elseif event == "UNIT_CONNECTION" then
    return Prediction.UpdateConnectionState
  end
  return UpdateFull
end
Prediction.NoDispatchUpdates = { [QueuePredictionDataEvent] = true }
Prediction.UpdateGlowHealthFast = UpdateGlowHealthFast
Prediction.UpdateMixedFollowHealthFast = UpdateMixedFollowHealthFast
-- Core may omit this follower entirely while the absorb-data owner says there
-- is no health-dependent glow/stripe to render.
Prediction.HealthVisualGateUpdates = { [UpdateGlowHealthFast] = true }

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
      and (not UF.IsUnitToken or UF.IsUnitToken(frame.MSUFUnitKey))
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
      update(frame, reason, frame.MSUFUnitKey)
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
  if not ActivatePredictionLifecycle or not Prediction._msufActiveLifecycleCount
    or Prediction._msufActiveLifecycleCount <= 0 then return end
  local schedule = _G.MSUF_ScheduleOnce
  if type(schedule) == "function" then
    schedule("UF_PREDICTION_WORLD_ENTRY", FlushWorldEntryPredictionSeed)
  else
    FlushWorldEntryPredictionSeed()
  end
end

local predictionWorldEventRegistered
local PREDICTION_WORLD_EVENT_KEY = "MSUF_UF_PREDICTION_WORLD_ENTRY"

local function SyncPredictionWorldEvent()
  local shouldRegister = (Prediction._msufActiveLifecycleCount or 0) > 0
  if shouldRegister then
    if predictionWorldEventRegistered == true then return end
    local registerEvent = _G.MSUF_EventBus_Register
    if type(registerEvent) == "function"
      and registerEvent("PLAYER_ENTERING_WORLD", PREDICTION_WORLD_EVENT_KEY, OnPredictionWorldEntry) ~= false then
      predictionWorldEventRegistered = true
    end
    return
  end
  if predictionWorldEventRegistered == true then
    local unregisterEvent = _G.MSUF_EventBus_Unregister
    if type(unregisterEvent) == "function" then
      unregisterEvent("PLAYER_ENTERING_WORLD", PREDICTION_WORLD_EVENT_KEY)
      predictionWorldEventRegistered = nil
    end
  end
end

ActivatePredictionLifecycle = function(frame)
  if frame._msufPredictionLifecycleActive == true then
    SyncPredictionWorldEvent()
    return
  end
  frame._msufPredictionLifecycleActive = true
  Prediction._msufActiveLifecycleCount = (Prediction._msufActiveLifecycleCount or 0) + 1
  SyncPredictionWorldEvent()
end

DeactivatePredictionLifecycle = function(frame)
  if frame._msufPredictionLifecycleActive ~= true then return end
  frame._msufPredictionLifecycleActive = nil
  local count = (Prediction._msufActiveLifecycleCount or 1) - 1
  if count < 0 then count = 0 end
  Prediction._msufActiveLifecycleCount = count
  SyncPredictionWorldEvent()
end

UF.RegisterElement("Prediction", Prediction)
