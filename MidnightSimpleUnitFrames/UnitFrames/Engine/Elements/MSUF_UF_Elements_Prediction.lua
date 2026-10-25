--- UnitFrames/Engine/Elements/MSUF_UF_Elements_Prediction.lua
--- Heal/absorb prediction element for unitframes.

local _, MSUF = ...
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "MSUF_UF_Elements_Prediction.lua")

local UF = MSUF.UF
-- Cold lifecycle and texture providers, kept in one table (main-chunk local ceiling).
local Providers = {
  EventBusRegister = MSUF.Require("MSUF_EventBus_Register", "MSUF_UF_Elements_Prediction.lua"),
  EventBusUnregister = MSUF.Require("MSUF_EventBus_Unregister", "MSUF_UF_Elements_Prediction.lua"),
  ScheduleOnce = MSUF.Require("MSUF_ScheduleOnce", "MSUF_UF_Elements_Prediction.lua"),
  ResolveStatusbarTextureKey = MSUF.Optional("MSUF_ResolveStatusbarTextureKey"),
}

-- Bind mandatory factories once; report both the consumer and received shape.
function Providers.RequireFactory(key)
  local factories = MSUF.UFModuleFactories
  local factory = factories[key]
  local kind = type(factory)
  assert(kind == "function", "Elements/MSUF_UF_Elements_Prediction.lua: required UF provider " .. key .. " (expected function, got " .. kind .. ")")
  return factory
end
local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitIsConnected = UnitIsConnected
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitHealthPercent = UnitHealthPercent
local UnitGetIncomingHeals = UnitGetIncomingHeals
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local UnitGetTotalHealAbsorbs = UnitGetTotalHealAbsorbs
local CreateUnitHealPredictionCalculator = CreateUnitHealPredictionCalculator
local UnitGetDetailedHealPrediction = UnitGetDetailedHealPrediction
local InCombatLockdown = InCombatLockdown
local tonumber = tonumber
local type = type
local CurveAPI = C_CurveUtil
local LuaCurveType = Enum and Enum.LuaCurveType
local ReadUnitExistsCached = UF.ReadUnitExistsCached
-- The saved overlay anchor modes (MSUF_UF_Shared.lua). The layout, clip and update
-- paths compare the follow modes per event, so those two are plain upvalues.
local ABSORB_ANCHOR = UF.Shared.ABSORB_ANCHOR
local FOLLOW_HP, FOLLOW_HP_OVERFLOW = ABSORB_ANCHOR.FOLLOW_HP, ABSORB_ANCHOR.FOLLOW_HP_OVERFLOW
local Layout = Providers.RequireFactory("PredictionLayout")(PixelLayoutRegion)
local NormalizeAnchorMode = Layout.NormalizeAnchorMode
local ReverseForMode = Layout.ReverseForMode
local StatusTexture = Layout.StatusTexture
local VisibleFollowBar = Layout.VisibleFollowBar
local InvalidateHpGeometry = Layout.InvalidateHpGeometry
local EnsureHpGeometryHook = Layout.EnsureHpGeometryHook
local LayoutBar = Layout.LayoutBar
local PredictionLayoutCurrent = Layout.PredictionLayoutCurrent
local LayoutBarIfNeeded = Layout.LayoutBarIfNeeded
local LayoutHealAbsorbBar = Layout.LayoutHealAbsorbBar
local Plans = Providers.RequireFactory("PredictionPlans")(NormalizeAnchorMode)
local EMPTY_EVENTS = Plans.EMPTY_EVENTS
local PREDICTION_DATA_EVENT_BITS = Plans.PREDICTION_DATA_EVENT_BITS
local PREDICTION_DIRTY_PLAN_KEYS = Plans.PREDICTION_DIRTY_PLAN_KEYS
local PREDICTION_EVENTS = Plans.PREDICTION_EVENTS
local PREDICTION_HEALTH_EVENTS = Plans.PREDICTION_HEALTH_EVENTS
local PREDICTION_EVENTS_PLAYER = Plans.PREDICTION_EVENTS_PLAYER
local PREDICTION_HEALTH_EVENTS_PLAYER = Plans.PREDICTION_HEALTH_EVENTS_PLAYER
local PREDICTION_EVENTS_DEPENDENT = Plans.PREDICTION_EVENTS_DEPENDENT
local PREDICTION_HEALTH_EVENTS_DEPENDENT = Plans.PREDICTION_HEALTH_EVENTS_DEPENDENT
local GROUP_LIFECYCLE_EVENTS = Plans.GROUP_LIFECYCLE_EVENTS
local PLAN_REFRESH_HEAL = Plans.PLAN_REFRESH_HEAL
local PLAN_REFRESH_ABSORB = Plans.PLAN_REFRESH_ABSORB
local PLAN_REFRESH_HEAL_ABSORB = Plans.PLAN_REFRESH_HEAL_ABSORB
local PLAN_SHOW_HEAL = Plans.PLAN_SHOW_HEAL
local PLAN_SHOW_ABSORB = Plans.PLAN_SHOW_ABSORB
local PLAN_SHOW_HEAL_ABSORB = Plans.PLAN_SHOW_HEAL_ABSORB
local PLAN_FORCE_MAX = Plans.PLAN_FORCE_MAX
local MixedFollowNeedsClamp = Plans.MixedFollowNeedsClamp
local NeedsHealthEvent = Plans.NeedsHealthEvent
local PredictionMask = Plans.PredictionMask
local CompilePredictionPlans = Plans.CompilePredictionPlans

local UnitMissing
do
  local issv = issecretvalue
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
local issecretvalue = issecretvalue

-- Heal/absorb prediction element.
local WHITE = "Interface\\Buttons\\WHITE8x8"
local UnitDamageAbsorbClampMode = Enum and Enum.UnitDamageAbsorbClampMode
local ABSORB_MISSING = UnitDamageAbsorbClampMode
  and UnitDamageAbsorbClampMode.MissingHealthWithoutIncomingHeals or 1
local TEST_MAX = 100
local TEST_INCOMING = 20
local TEST_ABSORB = 25
local TEST_HEAL_ABSORB = 15
local PREVIEW_INCOMING = 14
local PREVIEW_ABSORB = 10
local PREVIEW_HEAL_ABSORB = 7
local OVER_ABSORB_TEXTURE = "Interface\\RaidFrame\\Shield-Overshield"
local OVER_ABSORB_GLOW_W = 16
local OVER_ABSORB_GLOW_OFFSET = 7
local overAbsorbFullHealthCurve
local PREDICTION_HEALER_UNIT = "player"
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
  "_msufPredictionAllHealers",
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
    bar._msufAlphaStatusTextureObject = nil
    bar._msufGFStatusBarTextureWidget = nil
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
local function ReadIncomingHeals(frame, unit)
  if not UnitGetIncomingHeals then return nil end
  if frame._msufPredictionAllHealers == true then
    return UnitGetIncomingHeals(unit)
  end
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
  if frame._msufPredictionAllHealers == true then
    UnitGetDetailedHealPrediction(unit, nil, calc)
  else
    UnitGetDetailedHealPrediction(unit, PREDICTION_HEALER_UNIT, calc)
  end
  local getAbsorb = calc.GetDamageAbsorbs or calc.GetTotalDamageAbsorbs
  if getAbsorb then return getAbsorb(calc) end
  return ReadDamageAbsorbs(frame, unit)
end

local function ResolveTexture(key, fallback)
  if type(key) == "string" and key ~= "" then
    local resolve = Providers.ResolveStatusbarTextureKey
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
  bar = PixelLayoutRegion(CreateFrame("StatusBar", nil, frame._msufHealthVisualRoot or frame))
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

local PositionOverAbsorbGlow = Providers.RequireFactory("PredictionGlow")(
  CreateFrame, PixelLayoutRegion, OVER_ABSORB_TEXTURE, OVER_ABSORB_GLOW_W, OVER_ABSORB_GLOW_OFFSET, issecretvalue
)

local function HideOverAbsorbGlow(frame)
  local holder = frame and frame.overAbsorbGlowBar
  if holder and holder._msufShown ~= false then
    holder:SetShown(false)
    holder._msufShown = false
  end
end

local function SetOverAbsorbAlpha(holder, alpha, secret)
  -- Every caller owns the value it passes and already knows whether it came
  -- from a secret-capable native source. Carry that classification into this
  -- sink instead of repeating issecretvalue for every health follower write.
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

-- ReadHealthForOverAbsorb rationale: docs/uf-responsibility-notes.md.
local overAbsorbPartialCurve
local function UngateOverAbsorbGlow(holder)
  if holder._msufOverAbsorbGlowGated == true then
    local glow = holder._msufOverAbsorbGlowTexture
    if glow then glow:SetAlpha(1) end
    holder._msufOverAbsorbGlowGated = nil
  end
end

local function ShowProtectedOverAbsorb(frame, holder, unit, stripeEnabled)
  if issecretvalue(unit) == true or not UnitGetDetailedHealPrediction then return false end
  local calc = frame._msufPredictionOverAbsorbCalc
  if not calc then
    calc = CreateUnitHealPredictionCalculator and CreateUnitHealPredictionCalculator()
    if not (calc and calc.SetDamageAbsorbClampMode and calc.GetDamageAbsorbs) then return false end
    calc:SetDamageAbsorbClampMode(UnitDamageAbsorbClampMode and UnitDamageAbsorbClampMode.MissingHealth or 0)
    frame._msufPredictionOverAbsorbCalc = calc
  end
  local glow = holder._msufOverAbsorbGlowTexture
  if not (glow and glow.SetAlphaFromBoolean) then return false end
  local curve
  if not stripeEnabled then
    curve = overAbsorbPartialCurve
    if not curve then
      if not (CurveAPI and CurveAPI.CreateCurve and UnitHealthPercent) then return false end
      curve = CurveAPI.CreateCurve()
      if not curve then return false end
      if curve.SetType then curve:SetType(LuaCurveType and LuaCurveType.Step or 1) end
      -- Step: every partial health keeps 1, exact max health drops to 0.
      curve:AddPoint(0, 1)
      curve:AddPoint(1, 0)
      overAbsorbPartialCurve = curve
    end
  end
  if frame._msufPredictionAllHealers == true then
    UnitGetDetailedHealPrediction(unit, nil, calc)
  else
    UnitGetDetailedHealPrediction(unit, PREDICTION_HEALER_UNIT, calc)
  end
  local _, clamped = calc:GetDamageAbsorbs()
  if curve then
    glow:SetAlphaFromBoolean(clamped, UnitHealthPercent(unit, true, curve), 0)
  else
    glow:SetAlphaFromBoolean(clamped, 1, 0)
  end
  holder._msufOverAbsorbGlowGated = true
  -- The flag sink carries both gates; the holder itself stays opaque, which
  -- also retires the stripe's full-health gate on it.
  SetOverAbsorbAlpha(holder, 1, false)
  frame._msufPredictionFullHealthAlphaReady = nil
  if holder._msufShown ~= true then
    holder:SetShown(true)
    holder._msufShown = true
  end
  return true
end

-- Replaces the shortcut's existing ungate call, including its alpha cache and shown sink.
local function ShowFullHealthStripe(frame, holder, unit)
  if frame._msufPredictionFullHealthAlphaReady ~= true
    or frame._msufPredictionFullHealthAlphaDirty == true
    or frame._msufPredictionFullHealthAlphaUnit ~= unit then
    -- Inline the reader too: its nil/error path never paid an ungate call.
    local alpha
    if UnitHealthPercent and unit then
      local curve = overAbsorbFullHealthCurve
      if not curve then curve = EnsureFullHealthCurve() end
      if curve then alpha = UnitHealthPercent(unit, true, curve) end
    end
    local alphaSecret = issecretvalue(alpha) == true
    if not alphaSecret and alpha == nil then HideOverAbsorbGlow(frame) return end
    SetOverAbsorbAlpha(holder, alpha, alphaSecret)
    frame._msufPredictionFullHealthAlphaReady = true
    frame._msufPredictionFullHealthAlphaDirty = nil
    frame._msufPredictionFullHealthAlphaUnit = unit
  end
  if holder._msufOverAbsorbGlowGated == true then
    local glow = holder._msufOverAbsorbGlowTexture
    if glow then glow:SetAlpha(1) end
    holder._msufOverAbsorbGlowGated = nil
  end
  if holder._msufShown ~= true then
    holder:SetShown(true)
    holder._msufShown = true
  end
end

-- Existing budget-sensitive painter: no extra phase dispatch on exported Update.
-- hot path: kept whole (perf rule)
local function UpdateOverAbsorbGlow(frame, cfg, unit, hp, maxHP, absorb, refreshFullHealthAlpha,
  writeAbsorbValue, knownAbsorbSecret)
  if frame and refreshFullHealthAlpha == true then frame._msufPredictionFullHealthAlphaDirty = true end
  local overAbsorbEnabled = frame and frame._msufPredictionOverAbsorbOverlay == true
  local fullHealthStripeEnabled = frame and frame._msufPredictionFullHealthStripe == true
  if not (frame and (overAbsorbEnabled or fullHealthStripeEnabled)) then
    HideOverAbsorbGlow(frame)
    return
  end
  local absorbSecret = knownAbsorbSecret
  if absorbSecret == nil then absorbSecret = issecretvalue(absorb) == true end
  local reverse = frame._msufPredictionHpReverse == true
  local hpBar = frame.hpBar or frame.Health
  local holder = frame.overAbsorbGlowBar
  if writeAbsorbValue == true then
    if not holder then holder = PositionOverAbsorbGlow(frame, reverse) end
    if holder then
      local payload = absorb
      local payloadSecret = absorbSecret
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
  if not fullHealthStripeEnabled then
    if not absorbSecret and (type(absorb) ~= "number" or absorb <= 0) then HideOverAbsorbGlow(frame) return end
    if absorbSecret or issecretvalue(hp) == true or issecretvalue(maxHP) == true then
      if not (holder and hpBar
          and holder._msufOverAbsorbReverse == reverse
          and holder._msufOverAbsorbAnchor == hpBar) then
        holder = PositionOverAbsorbGlow(frame, reverse)
      end
      if not (holder and ShowProtectedOverAbsorb(frame, holder, unit, false)) then
        HideOverAbsorbGlow(frame)
      end
      return
    end
  end
  if fullHealthStripeEnabled then
    local knownZero = writeAbsorbValue == true
      and not absorbSecret
      and (type(absorb) ~= "number" or absorb <= 0)
    if not knownZero and writeAbsorbValue ~= true
      and holder and holder._msufOverAbsorbValuePlain == true then
      local gateValue = holder._msufOverAbsorbValue
      knownZero = type(gateValue) ~= "number" or gateValue <= 0
    end
    if knownZero then HideOverAbsorbGlow(frame) return end

    if writeAbsorbValue == true
      and absorbSecret
      and not overAbsorbEnabled
      and holder and hpBar
      and holder._msufOverAbsorbReverse == reverse
      and holder._msufOverAbsorbAnchor == hpBar
      and frame._msufPredictionFullHealthAlphaReady == true
      and frame._msufPredictionFullHealthAlphaDirty ~= true
      and frame._msufPredictionFullHealthAlphaUnit == unit then
      UngateOverAbsorbGlow(holder)
      if holder._msufShown ~= true then
        holder:SetShown(true)
        holder._msufShown = true
      end
      return
    end
  end

  if fullHealthStripeEnabled and cfg and cfg.test ~= true
    and not overAbsorbEnabled
    and issecretvalue(unit) ~= true
    and (issecretvalue(hp) == true or issecretvalue(maxHP) == true)
    and holder and hpBar
    and holder._msufOverAbsorbReverse == reverse
    and holder._msufOverAbsorbAnchor == hpBar then
    ShowFullHealthStripe(frame, holder, unit)
    return
  end
  local hpSecret, maxSecret
  hp, maxHP, hpSecret, maxSecret = ReadHealthForOverAbsorb(frame, unit, hp, maxHP)
  if not (fullHealthStripeEnabled and writeAbsorbValue ~= true)
    and not absorbSecret and (type(absorb) ~= "number" or absorb <= 0) then
    HideOverAbsorbGlow(frame)
    return
  end
  if not (holder and hpBar
      and holder._msufOverAbsorbReverse == reverse
      and holder._msufOverAbsorbAnchor == hpBar) then
    holder = PositionOverAbsorbGlow(frame, reverse)
  end
  if not holder then return end

  if absorbSecret or hpSecret or maxSecret then
    if overAbsorbEnabled and ShowProtectedOverAbsorb(frame, holder, unit, fullHealthStripeEnabled) then
      return
    end
    if not fullHealthStripeEnabled then HideOverAbsorbGlow(frame) return end
    local alphaReady = frame._msufPredictionFullHealthAlphaReady == true
      and frame._msufPredictionFullHealthAlphaDirty ~= true
      and issecretvalue(unit) ~= true
      and frame._msufPredictionFullHealthAlphaUnit == unit
    if not alphaReady then
      local alpha, alphaSecret
      if not hpSecret and not maxSecret and type(hp) == "number" and type(maxHP) == "number" and maxHP > 0 then
        alpha = hp >= maxHP and 1 or 0
        alphaSecret = false
      else
        alpha = FullHealthAlpha(unit)
        alphaSecret = issecretvalue(alpha) == true
      end
      if not alphaSecret and alpha == nil then HideOverAbsorbGlow(frame) return end
      SetOverAbsorbAlpha(holder, alpha, alphaSecret)
      frame._msufPredictionFullHealthAlphaReady = true
      frame._msufPredictionFullHealthAlphaDirty = nil
      frame._msufPredictionFullHealthAlphaUnit = issecretvalue(unit) ~= true and unit or nil
    end
  else
    if type(hp) ~= "number" or type(maxHP) ~= "number" or maxHP <= 0 then HideOverAbsorbGlow(frame) return end
    local incoming = frame._msufPredictionIncoming
    if issecretvalue(incoming) == true or type(incoming) ~= "number" or incoming < 0 then incoming = 0 end
    local atFullHealth = hp >= maxHP
    local show = fullHealthStripeEnabled and atFullHealth
    if not show and not atFullHealth and overAbsorbEnabled then
      show = (hp + incoming + absorb) >= maxHP or (hp + absorb) >= maxHP
    end
    if not show then HideOverAbsorbGlow(frame) return end
    SetOverAbsorbAlpha(holder, 1, false)
  end
  UngateOverAbsorbGlow(holder)
  if holder._msufShown ~= true then
    holder:SetShown(true)
    holder._msufShown = true
  end
end

local Prediction = { UpdateOnApply = true }
local ActivatePredictionLifecycle
local DeactivatePredictionLifecycle
local CancelQueuedPrediction
local QueuePredictionDataEvent
local UpdateFull
local UpdateBoundPredictionData
local absorbDataWriters
local UpdateGlowHealthFast
local UpdateFullHealthStripeFast
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
  frame._msufPredictionAbsorbSecret = nil
  frame._msufPredictionHealAbsorb = nil
  frame._msufPredictionHealthVisualActive = nil
  frame._msufPredictionHealthMax = nil
  frame._msufPredictionHealthMaxUnit = nil
  ClearBarValueCache(frame.incomingHealBar)
  ClearBarValueCache(frame.absorbBar)
  ClearBarValueCache(frame.healAbsorbBar)
end

-- ClearPredictionCache rationale: docs/uf-responsibility-notes.md.
local function FlushFlatPrediction(frame, mask)
  if type(mask) ~= "number" then mask = 7 end
  local unit = frame.MSUFUnitKey
  -- Preserve the original phase order and secret gates; full rationale is in docs/uf-responsibility-notes.md.
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
      local incoming = ReadIncomingHeals(frame, unit)
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
  -- Preserve the original phase order and secret gates; full rationale is in docs/uf-responsibility-notes.md.
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
  local healMode = NormalizeAnchorMode(cfg.healAnchorMode, FOLLOW_HP)
  local absorbMode = NormalizeAnchorMode(cfg.absorbAnchorMode, ABSORB_ANCHOR.RIGHT)
  local healAbsorbMode = NormalizeAnchorMode(cfg.healAbsorbAnchorMode, FOLLOW_HP)
  local followAbsorb = cfg.absorb == true and (absorbMode == FOLLOW_HP or absorbMode == FOLLOW_HP_OVERFLOW)
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
  frame._msufPredictionAllHealers = cfg.healAllHealers == true
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
    elseif frame._msufPredictionFullHealthStripe == true then
      frame._msufUpdatePredictionHealthValue = UpdateFullHealthStripeFast
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
    elseif frame._msufPredictionMask == 2 then
      -- Absorb-only configurations cannot use the mixed heal/follow clamp.
      -- Bind shared writers; no per-frame closure or per-event plan expansion.
      local glow = frame._msufPredictionOverAbsorbOverlay or frame._msufPredictionFullHealthStripe
      local key = (followAbsorb and 1 or 0) + (glow and 2 or 0)
        + (frame._msufPredictionFullHealthStripe and 4 or 0)
      frame._msufPredictionFlushData = absorbDataWriters[key]
      frame._msufPredictionSimpleAbsorb = nil
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
  local dependent = plainUnit == "targettarget" or plainUnit == "focustarget" or plainUnit == "pettarget"
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
  local healMode = frame._msufPredictionHealMode or NormalizeAnchorMode(cfg.healAnchorMode, FOLLOW_HP)
  local absorbMode = frame._msufPredictionAbsorbMode or NormalizeAnchorMode(cfg.absorbAnchorMode, ABSORB_ANCHOR.RIGHT)

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

function Prediction.ClearPreview(frame)
  SuspendPrediction(frame, true)
end
UF.ClearPredictionPreview = Prediction.ClearPreview

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
  LayoutBarIfNeeded(frame, bar, 2, FOLLOW_HP, frame._msufPredictionAbsorbReverse, follow,
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

-- Preserve the original phase order and secret gates; full rationale is in docs/uf-responsibility-notes.md.
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
    frame._msufPredictionAbsorb, true, nil,
    frame._msufPredictionAbsorbSecret == true)
end

-- Bound full-health-stripe follower. CompilePredictionRuntime installs this
-- only for the non-mixed stripe archetype, so its UNIT_HEALTH path never pays
-- the generic glow wrapper's feature tests or partial-overlay bucket branch.
-- It consumes only the absorb payload cached by the data-event owner.
-- hot path: kept whole (perf rule)
UpdateFullHealthStripeFast = function(frame, event, unit, seedHP, seedMaxHP)
  if not frame then return end
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
  local absorbSecret = frame._msufPredictionAbsorbSecret == true
  -- The data-event owner opens _msufPredictionHealthVisualActive only for a
  -- plain positive absorb or, for this stripe archetype, a secret absorb. The
  -- validated warm cache therefore makes another type/value test redundant.

  local holder = frame.overAbsorbGlowBar
  local hpBar = frame.hpBar or frame.Health
  local reverse = frame._msufPredictionHpReverse == true
  if not (holder and hpBar
    and holder._msufOverAbsorbReverse == reverse
    and holder._msufOverAbsorbAnchor == hpBar) then
    return UpdateOverAbsorbGlow(frame, cfg, unit, seedHP, seedMaxHP, absorb, true,
      nil, absorbSecret)
  end

  -- A plain percent is already owned by Health. It is enough to resolve the
  -- full-health edge and, when partial over-absorb is enabled, lets the general
  -- threshold path reconstruct current health without another UnitHealth read.
  local pct = CachedHealthPercent(frame, unit)
  -- Health publishes only plain percentages into this comparison cache and
  -- clears both fields for protected values, so type is the complete gate.
  if type(pct) == "number" then
    if pct < 100 then
      if frame._msufPredictionOverAbsorbOverlay == true then
        return UpdateOverAbsorbGlow(frame, cfg, unit, seedHP, seedMaxHP, absorb, true,
          nil, absorbSecret)
      end
      HideOverAbsorbGlow(frame)
      return
    end
    SetOverAbsorbAlpha(holder, 1, false)
  else
    -- With the partial overlay on, protected health renders through the
    -- calculator flag in the general path.
    if frame._msufPredictionOverAbsorbOverlay == true then
      return UpdateOverAbsorbGlow(frame, cfg, unit, seedHP, seedMaxHP, absorb, true,
        nil, absorbSecret)
    end
    -- A protected percentage cannot be passed into LuaCurve:Evaluate from
    -- addon code: that call is tainted even though the value itself came from
    -- UnitHealthPercent. Re-enter the native API with the curve so Blizzard
    -- performs the secret evaluation in untainted execution.
    local alpha = FullHealthAlpha(unit)
    local alphaSecret = issecretvalue(alpha) == true
    if not alphaSecret then
      if type(alpha) ~= "number" then
        return UpdateOverAbsorbGlow(frame, cfg, unit, seedHP, seedMaxHP, absorb, true,
          nil, absorbSecret)
      end
      if alpha <= 0 then
        if frame._msufPredictionOverAbsorbOverlay == true then
          return UpdateOverAbsorbGlow(frame, cfg, unit, seedHP, seedMaxHP, absorb, true,
            nil, absorbSecret)
        end
        HideOverAbsorbGlow(frame)
        return
      end
    end
    SetOverAbsorbAlpha(holder, alpha, alphaSecret)
  end

  frame._msufPredictionFullHealthAlphaReady = true
  frame._msufPredictionFullHealthAlphaDirty = nil
  frame._msufPredictionFullHealthAlphaUnit = unit
  UngateOverAbsorbGlow(holder)
  if holder._msufShown ~= true then
    holder:SetShown(true)
    holder._msufShown = true
  end
end

-- hot path: kept whole (perf rule)
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
  -- Preserve the original phase order and secret gates; full rationale is in docs/uf-responsibility-notes.md.
  if frame._msufPredictionAbsorbSecret == true then
    local holder = frame.overAbsorbGlowBar
    if holder and frame._msufPredictionOverAbsorbOverlay == true
      and holder._msufOverAbsorbReverse == (frame._msufPredictionHpReverse == true)
      and holder._msufOverAbsorbAnchor == (frame.hpBar or frame.Health) then
      frame._msufPredictionFullHealthAlphaDirty = true
      -- A queued data event drains before this frame draws and renders the
      -- glow from the same (synchronous-event) unit state: leave it to the
      -- drain, which repeats this tick when its plan draws no glow.
      if frame._msufPredictionQueued == true then
        frame._msufPredictionGlowDeferred = true
        return
      end
      if not ShowProtectedOverAbsorb(frame, holder, unit, false) then HideOverAbsorbGlow(frame) end
      return
    end
    return UpdateOverAbsorbGlow(frame, cfg, unit, seedHP, seedMaxHP, absorb, true, nil, true)
  end
  -- UpdateHealthValue rationale: docs/uf-responsibility-notes.md.
  local bar = frame.hpBar
  local pct = bar and bar._msufHealthPercentValue
  if type(pct) == "number"
    and bar._msufHealthPercentUnit == unit then
    local bucket = pct
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
  return UpdateOverAbsorbGlow(frame, cfg, unit, seedHP, seedMaxHP, absorb, true,
    nil, false)
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
  -- Preserve the original phase order and secret gates; full rationale is in docs/uf-responsibility-notes.md.
  if forceMax == true then
    InvalidateHpGeometry(frame.hpBar or frame.Health)
  end
  if refreshHeal then
    frame._msufPredictionIncoming = ReadIncomingHeals(frame, unit)
  end
  if refreshAbsorb then
    local readAbsorb = frame._msufPredictionReadAbsorb or ReadDamageAbsorbs
    local absorb = readAbsorb(frame, unit)
    frame._msufPredictionAbsorb = absorb
    local absorbSecret = issecretvalue(absorb) == true
    frame._msufPredictionAbsorbSecret = absorbSecret and true or nil
    local absorbPositive = not absorbSecret and type(absorb) == "number" and absorb > 0
    frame._msufPredictionHealthVisualActive = (absorbPositive
      or (absorbSecret and (frame._msufPredictionFullHealthStripe == true
        or frame._msufPredictionOverAbsorbOverlay == true))) and true or nil
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
    if absorbMode == FOLLOW_HP or absorbMode == FOLLOW_HP_OVERFLOW then
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
      -- This settles the glow from fresh inputs: a deferred health tick is done.
      frame._msufPredictionGlowDeferred = nil
      local glowAbsorb = frame._msufPredictionAbsorb
      if refreshAbsorb == true and frame._msufPredictionMixedFollowClamp == true then
        glowAbsorb = ReadDamageAbsorbs(frame, unit)
      end
      local holder = frame.overAbsorbGlowBar
      local knownInactive = refreshAbsorb == true
        and frame._msufPredictionFullHealthStripe ~= true
        and issecretvalue(glowAbsorb) ~= true
        and (type(glowAbsorb) ~= "number" or glowAbsorb <= 0)
        and (holder == nil or (holder._msufShown == false
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

local function ApplyPreviewValues(frame, cfg, unit, showHeal, showAbsorb, showHealAbsorb,
  healthValue, incomingValue, absorbValue, healAbsorbValue)
  healthValue = healthValue or TEST_MAX
  incomingValue = incomingValue or TEST_INCOMING
  absorbValue = absorbValue or TEST_ABSORB
  healAbsorbValue = healAbsorbValue or TEST_HEAL_ABSORB
  local healMode = frame._msufPredictionHealMode or NormalizeAnchorMode(cfg.healAnchorMode, FOLLOW_HP)
  local absorbMode = frame._msufPredictionAbsorbMode or NormalizeAnchorMode(cfg.absorbAnchorMode, ABSORB_ANCHOR.RIGHT)
  if showHeal and frame.incomingHealBar then
    LayoutBar(frame, frame.incomingHealBar, 1, healMode, frame._msufPredictionHealReverse, nil,
      frame._msufPredictionHealHeight, frame._msufPredictionHealOffsetY)
    ShowValue(frame.incomingHealBar, TEST_MAX, incomingValue)
  elseif frame.incomingHealBar then
    HideBar(frame.incomingHealBar)
  end
  if showAbsorb and frame.absorbBar then
    if absorbMode == FOLLOW_HP or absorbMode == FOLLOW_HP_OVERFLOW then
      local follow = VisibleFollowBar(cfg, frame.incomingHealBar)
      LayoutBar(frame, frame.absorbBar, 2, absorbMode, frame._msufPredictionAbsorbReverse, follow,
        frame._msufPredictionAbsorbHeight, frame._msufPredictionAbsorbOffsetY)
    end
    ShowValue(frame.absorbBar, TEST_MAX, absorbValue)
    UpdateOverAbsorbGlow(frame, cfg, unit, healthValue, TEST_MAX, absorbValue, true, true)
  elseif frame.absorbBar then
    HideBar(frame.absorbBar)
    HideOverAbsorbGlow(frame)
  end
  if showHealAbsorb and frame.healAbsorbBar then
    LayoutHealAbsorbBar(frame, frame.healAbsorbBar, 3, frame._msufPredictionHpReverse == true,
      frame._msufPredictionHealAbsorbMode,
      frame._msufPredictionHealAbsorbHeight, frame._msufPredictionHealAbsorbOffsetY)
    ShowValue(frame.healAbsorbBar, TEST_MAX, healAbsorbValue)
  elseif frame.healAbsorbBar then
    HideBar(frame.healAbsorbBar)
  end
end

--- The optional values are percentages of the bar (0..100); a preview that owns its sample passes them.
function Prediction.ApplyPreview(frame, healthValue, incoming, absorb, healAbsorb)
  local cfg = frame and frame._msufPredictionRuntimeCfg
  if not (cfg and cfg.enabled == true) then return false end
  if cfg.test == true then
    UpdateFull(frame, "MSUF_PREDICTION_PREVIEW", frame.MSUFUnitKey)
    return true
  end
  frame._msufPredictionDisabled = nil
  ApplyPreviewValues(frame, cfg, frame.MSUFUnitKey,
    cfg.heal == true, cfg.absorb == true, cfg.healAbsorb == true,
    healthValue, incoming or PREVIEW_INCOMING, absorb or PREVIEW_ABSORB, healAbsorb or PREVIEW_HEAL_ABSORB)
  return true
end
UF.ApplyPredictionPreview = Prediction.ApplyPreview

--- Scene form: incoming heal, absorb and heal absorb from a sample, as percents of the health maximum.
function Prediction.PaintSample(frame, healthValue, incoming, absorb, healAbsorb)
  local cfg = frame and frame._msufPredictionRuntimeCfg
  if not (cfg and cfg.enabled == true) then return false end
  frame._msufPredictionDisabled = nil
  ApplyPreviewValues(frame, cfg, frame.MSUFUnitKey, cfg.heal == true, cfg.absorb == true, cfg.healAbsorb == true,
    healthValue, incoming, absorb, healAbsorb)
  return true
end

-- Values-only companion for an owner's animation clock. Native follow anchors track the health texture themselves.
function Prediction.PaintSampleData(frame, healthValue, incoming, absorb, healAbsorb)
  local cfg = frame._msufPredictionRuntimeCfg
  if not (cfg and cfg.enabled) then return false end
  if cfg.heal and frame.incomingHealBar then ShowValue(frame.incomingHealBar, TEST_MAX, incoming) end
  if cfg.absorb and frame.absorbBar then
    ShowValue(frame.absorbBar, TEST_MAX, absorb)
    UpdateOverAbsorbGlow(frame, cfg, frame.MSUFUnitKey, healthValue, TEST_MAX, absorb, true, true)
  end
  if cfg.healAbsorb and frame.healAbsorbBar then ShowValue(frame.healAbsorbBar, TEST_MAX, healAbsorb) end
  return true
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

  if trustedActive ~= true and cfg.test == true then
    local explicitTests = cfg.healTest ~= nil or cfg.absorbTest ~= nil or cfg.healAbsorbTest ~= nil
    ApplyPreviewValues(frame, cfg, unit,
      cfg.healTest == true or not explicitTests,
      cfg.absorbTest == true or not explicitTests,
      cfg.healAbsorbTest == true or not explicitTests)
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

-- Preserve the original phase order and secret gates; full rationale is in docs/uf-responsibility-notes.md.
-- hot path: kept whole (perf rule)
UpdateBoundPredictionData = function(frame, mask)
  local unit = frame.MSUFUnitKey
  local cfg = frame._msufPredictionRuntimeCfg
  local plans = frame._msufPredictionEventPlans
  local plan = type(mask) == "number"
    and plans and plans[mask] or nil
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

-- Preserve the original phase order and secret gates; full rationale is in docs/uf-responsibility-notes.md.
local function CreateAbsorbDataWriter(followAbsorb, withGlow, fullStripe)
  -- hot path: kept whole (perf rule)
  return function(frame, mask)
    local unit = frame.MSUFUnitKey
    local cfg = frame._msufPredictionRuntimeCfg
    local plans = frame._msufPredictionEventPlans
    local plan = type(mask) == "number" and plans and plans[mask] or nil
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

    local absorb = ReadDamageAbsorbs(frame, unit)
    frame._msufPredictionAbsorb = absorb
    local absorbSecret = issecretvalue(absorb) == true
    frame._msufPredictionAbsorbSecret = absorbSecret and true or nil
    local absorbPositive = not absorbSecret and type(absorb) == "number" and absorb > 0
    frame._msufPredictionHealthVisualActive = (absorbPositive
      or (absorbSecret and (fullStripe or frame._msufPredictionOverAbsorbOverlay == true))) and true or nil
    -- The guard already established CacheReady/Unit/Cfg. Only the glow's
    -- health-tick dedupe becomes stale when its absorb payload changes.
    frame._msufGlowTickBucket, frame._msufGlowTickUnit = nil, nil

    local bar = frame.absorbBar
    if not bar then return end
    if followAbsorb then
      LayoutBarIfNeeded(frame, bar, 2, frame._msufPredictionAbsorbMode,
        frame._msufPredictionAbsorbReverse, nil,
        frame._msufPredictionAbsorbHeight, frame._msufPredictionAbsorbOffsetY)
    end
    local maxHP
    if bar._msufMaxReady ~= true then maxHP = ReadHealthMax(frame, unit, false) end
    ShowValue(bar, maxHP, absorb, false)
    if withGlow then
      frame._msufPredictionGlowDeferred = nil
      local holder = frame.overAbsorbGlowBar
      local knownInactive = not fullStripe and not absorbSecret
        and (type(absorb) ~= "number" or absorb <= 0)
        and (holder == nil or (holder._msufShown == false
          and holder._msufOverAbsorbValuePlain == true
          and (type(holder._msufOverAbsorbValue) ~= "number" or holder._msufOverAbsorbValue <= 0)))
      if not knownInactive then
        UpdateOverAbsorbGlow(frame, cfg, unit, nil, maxHP, absorb, false, true, absorbSecret)
      end
    end
  end
end

absorbDataWriters = {
  [1] = CreateAbsorbDataWriter(true, false, false),
  [2] = CreateAbsorbDataWriter(false, true, false),
  [3] = CreateAbsorbDataWriter(true, true, false),
  [6] = CreateAbsorbDataWriter(false, true, true),
  [7] = CreateAbsorbDataWriter(true, true, true),
}

QueuePredictionDataEvent, CancelQueuedPrediction = Providers.RequireFactory("PredictionQueue")(
  PREDICTION_DATA_EVENT_BITS, PREDICTION_DIRTY_PLAN_KEYS, UpdateFull, UpdateGlowHealthFast
)

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
Prediction.UpdateFullHealthStripeFast = UpdateFullHealthStripeFast
Prediction.UpdateMixedFollowHealthFast = UpdateMixedFollowHealthFast
-- Core may omit this follower entirely while the absorb-data owner says there
-- is no health-dependent glow/stripe to render.
Prediction.HealthVisualGateUpdates = {
  [UpdateGlowHealthFast] = true,
  [UpdateFullHealthStripeFast] = true,
}

--- Reseed live prediction values after Blizzard has finalized world/unit data.
function Prediction.RefreshVisible(reason)
  if InCombatLockdown and InCombatLockdown() then return false end
  local frames = UF and UF.attachedFrameList
  if type(frames) ~= "table" then return false end

  local did = false
  local PublicGlobals = MSUF.PublicGlobals
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
        or PublicGlobals.MSUF_PreviewTestMode == true
        or PublicGlobals.MSUF_BossTestMode == true
        or PublicGlobals.MSUF2_BossUnitframePreviewActive == true
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
  Providers.ScheduleOnce("UF_PREDICTION_WORLD_ENTRY", FlushWorldEntryPredictionSeed)
end

local predictionWorldEventRegistered
local PREDICTION_WORLD_EVENT_KEY = "MSUF_UF_PREDICTION_WORLD_ENTRY"

local function SyncPredictionWorldEvent()
  local shouldRegister = (Prediction._msufActiveLifecycleCount or 0) > 0
  if shouldRegister then
    if predictionWorldEventRegistered == true then return end
    if Providers.EventBusRegister("PLAYER_ENTERING_WORLD", PREDICTION_WORLD_EVENT_KEY, OnPredictionWorldEntry) ~= false then
      predictionWorldEventRegistered = true
    end
    return
  end
  if predictionWorldEventRegistered == true then
    Providers.EventBusUnregister("PLAYER_ENTERING_WORLD", PREDICTION_WORLD_EVENT_KEY)
    predictionWorldEventRegistered = nil
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

Prediction.Routes = { events = true, identity = true }
UF.RegisterElement("Prediction", Prediction)
