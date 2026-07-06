local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}

--- UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua
---
--- Health bar element for single unit frames. It owns bar creation, compiled
--- health visual apply, and the narrow health fast paths used by Dispatch.
--- Health events are hot: avoid DB lookups and broad visual refreshes here.

local C = MSUF.UFBarTextCommon
if not C then return end

local UF = C.UF
local CreateFrame = C.CreateFrame
local UnitHealth = C.UnitHealth
local UnitHealthMax = C.UnitHealthMax
local WHITE = C.WHITE
local SetStatusTexture = C.SetStatusTexture
local SetBarMinMax = C.SetBarMinMax
local SetBarMinMaxKnown = C.SetBarMinMaxKnown
local SetBarMinMaxPlain = C.SetBarMinMaxPlain or C.SetBarMinMax
local SetBarValue = C.SetBarValue
local SetBarValueKnown = C.SetBarValueKnown
local SetBarValuePlain = C.SetBarValuePlain or C.SetBarValue
local SnapBarInterpolation = C.SnapBarInterpolation
local SetBarSmoothing = C.SetBarSmoothing
local ApplyHealthStatusColor = C.ApplyHealthStatusColor
local ApplyBackgrounds = C.ApplyBackgrounds
local ApplyBarGradient = C.ApplyBarGradient
local RefreshUnitState = C.RefreshUnitState
local UnitHealthPercent = C.UnitHealthPercent
local SCALE_100 = C.SCALE_100
local issecretvalue = _G.issecretvalue or function(_) return false end
local floor = C.floor or math.floor
local GetTime = C.GetTime or _G.GetTime
local type = type

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

local GRADIENT_SECRET_THROTTLE = 0.1
local HEALTH_EVENTS_CLASS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_MAX_HEALTH_MODIFIERS_CHANGED", "UNIT_CONNECTION", "UNIT_FLAGS", "UNIT_FACTION" }
local HEALTH_EVENTS_CLASS_NPC_TYPE = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_MAX_HEALTH_MODIFIERS_CHANGED", "UNIT_CONNECTION", "UNIT_FLAGS", "UNIT_FACTION", "UNIT_CLASSIFICATION_CHANGED" }
local Health = {
  events = HEALTH_EVENTS_CLASS,
}
local HEALTH_EVENTS_NO_FACTION = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_MAX_HEALTH_MODIFIERS_CHANGED", "UNIT_CONNECTION", "UNIT_FLAGS" }
local HEALTH_EVENTS_PLAYER = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_MAX_HEALTH_MODIFIERS_CHANGED", "UNIT_FLAGS" }
local HEALTH_PLAYER_LIFECYCLE_EVENTS = { "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }
local GROUP_HEALTH_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" }

local function HealthCanUseStaticHotpath(frame, spec)
  if frame and frame._msufIsGroupFrame == true then
    return false
  end
  if spec and spec.scope == "group" then
    return false
  end
  local health = spec and spec.health
  if health and health.mode == "gradient" then
    return false
  end
  if health and health.backgroundMatchHealth == true then
    return false
  end
  local power = spec and spec.power
  if power and power.backgroundMatchHealth == true then
    return false
  end
  return true
end

local function StoreHealthValue(bar, unit, hp, hpSecret)
  if not bar then return end
  if hpSecret == nil then hpSecret = issecretvalue(hp) == true end
  if hpSecret then
    if bar._msufHealthValue == nil and bar._msufHealthValueUnit == nil then
      return
    end
    bar._msufHealthValue = nil
    bar._msufHealthValueUnit = nil
    return
  end
  if bar._msufHealthValue == hp and bar._msufHealthValueUnit == unit then
    return
  end
  bar._msufHealthValue = hp
  bar._msufHealthValueUnit = unit
end

local function StoreHealthMax(bar, unit, maxHP, maxSecret)
  if not bar then return end
  if maxSecret == nil then maxSecret = issecretvalue(maxHP) == true end
  if maxSecret then
    if bar._msufHealthMax == nil
      and bar._msufHealthMaxUnit == nil
      and bar._msufHealthMaxSecret == nil
      and bar._msufHealthMaxReady == nil then
      return
    end
    bar._msufHealthMax = nil
    bar._msufHealthMaxUnit = nil
    bar._msufHealthMaxSecret = nil
    bar._msufHealthMaxReady = nil
    return
  end
  if bar._msufHealthMax == maxHP
    and bar._msufHealthMaxUnit == unit
    and bar._msufHealthMaxSecret == nil
    and bar._msufHealthMaxReady == true then
    return
  end
  bar._msufHealthMax = maxHP
  bar._msufHealthMaxUnit = unit
  bar._msufHealthMaxSecret = nil
  bar._msufHealthMaxReady = true
end

local function ConnectionStatusKey(frame, unit, event)
  if not RefreshUnitState then
    return nil
  end
  local state = RefreshUnitState(frame, unit, frame and frame.MSUFSpec, event or "UNIT_CONNECTION")
  if not state then
    return nil
  end
  if state.existsKnown == true and state.exists == false then
    return 1
  end
  if state.deadKnown == true and state.dead == true then
    return 2
  end
  if state.connectedKnown == true and state.connected == false then
    return 3
  end
  if state.existsKnown == true and state.deadKnown == true and state.connectedKnown == true then
    return 0
  end
  return nil
end

local function GroupHealthStatusNeedsRefresh(frame, hp, hpSecret)
  local shown = frame and frame._msufStatusTextValue
  if shown == "DEAD" or shown == "GHOST" then
    return true
  end
  return hpSecret ~= true and hp == 0
end

local function RefreshGroupDeadStateFromHealth(frame, event, unit, hp, hpSecret)
  if event ~= "UNIT_HEALTH" or not (frame and frame._msufIsGroupFrame == true) then
    return
  end
  if GroupHealthStatusNeedsRefresh(frame, hp, hpSecret) then
    local fn = frame._msufUpdateGroupStatusState
    if fn then
      fn(frame, event, unit, hpSecret ~= true and hp or nil)
    end
  end
  if hpSecret ~= true and (hp == 0 or frame._msufGFDeadBgState == true) then
    local fn = frame._msufUpdateGroupVisualsGoneState
    if fn then
      fn(frame, event, unit, hp)
    end
  end
end

function Health.Create(frame, spec)
  if frame.hpBar then
    return
  end
  local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
  bg:SetAllPoints(frame)
  bg:SetColorTexture(0.02, 0.02, 0.025, spec and spec.backgroundAlpha or 0.72)
  frame.bg = bg
  frame.hpBarBG = bg
  frame.healthBg = bg

  local bar = CreateFrame("StatusBar", nil, frame)
  bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(1)
  bar:SetStatusBarTexture((spec and spec.texture) or WHITE)
  frame.hpBar = bar
  frame.Health = bar
  frame.health = bar
end

function Health.Apply(frame, spec)
  if not frame.hpBar then
    Health.Create(frame, spec)
  end
  frame.Health = frame.hpBar
  frame.health = frame.hpBar
  frame.healthBg = frame.hpBarBG or frame.bg
  frame.hpBar._msufGradientPct = nil
  frame._msufGradStashAt = nil
  frame._msufIsGroupFrame = spec and spec.scope == "group"
  frame._msufHealthColorByHealth = spec and spec.health and spec.health.mode == "gradient"
  frame._msufHealthBgDynamic = spec and spec.health and spec.health.backgroundMatchHealth == true
  frame._msufPowerBgDynamic = spec and spec.power and spec.power.backgroundMatchHealth == true
  frame._msufHealthConnectionColorKey = nil
  frame._msufHealthColdColor = frame._msufIsGroupFrame
    and frame._msufHealthColorByHealth ~= true
    or nil
  SetStatusTexture(frame.hpBar, spec and spec.health and spec.health.texture or spec and spec.texture or WHITE)
  if frame.hpBar.SetReverseFill then
    local reverse = spec and spec.health and spec.health.reverse == true
    if frame.hpBar._msufReverseFill ~= reverse then
      frame.hpBar:SetReverseFill(reverse)
      frame.hpBar._msufReverseFill = reverse
    end
  end
  SetBarSmoothing(frame.hpBar, spec and spec.health and spec.health.smooth == true)
  ApplyBackgrounds(frame)
  if ApplyBarGradient then
    ApplyBarGradient(frame, frame.hpBar, spec and spec.health and spec.health.barGradient, "hpGradients")
  end
  local colorStable = frame._msufHealthColorByHealth ~= true
    and frame._msufHealthBgDynamic ~= true
    and frame._msufPowerBgDynamic ~= true
  local groupStaticHot = frame._msufIsGroupFrame == true and colorStable
  -- Single (non-group) frames that use the static hotpath are ALSO percent-path
  -- candidates: the text runtime promotes them to Health.UpdateValuePercent when
  -- no consumer needs an absolute HP number, so a boss target's sustained-damage
  -- ticks skip the UnitHealth/Max/Store work. Both flags are read by the unified
  -- Health.SelectPercentHealthUpdater. Group ones keep their existing updaters.
  local singleStaticHot = frame._msufIsGroupFrame ~= true and colorStable
    and HealthCanUseStaticHotpath(frame, spec)
  frame._msufGroupStaticHot = groupStaticHot or nil
  frame._msufSingleStaticHot = singleStaticHot or nil
  if groupStaticHot then
    frame._msufUpdateHealthValue = Health.UpdateValueGroupStatic
    frame._msufUpdateHealthMaxValue = Health.UpdateMaxValueStatic
  elseif HealthCanUseStaticHotpath(frame, spec) then
    frame._msufUpdateHealthValue = frame.unit == "player" and Health.UpdateValueStaticPlain or Health.UpdateValueStatic
    frame._msufUpdateHealthMaxValue = frame.unit == "player" and Health.UpdateMaxValueStaticPlain or Health.UpdateMaxValueStatic
  else
    frame._msufUpdateHealthValue = frame.unit == "player" and Health.UpdateValuePlain or Health.UpdateValue
    frame._msufUpdateHealthMaxValue = frame.unit == "player" and Health.UpdateMaxValuePlain or Health.UpdateMaxValue
  end
  frame._msufUpdateHealthConnection = Health.UpdateConnectionState
  frame._msufUpdateHealthIdentityColor = Health.UpdateIdentityColor
end

function Health.GetEvents(frame, spec)
  if frame._msufIsGroupFrame or (spec and spec.scope == "group") then
    return GROUP_HEALTH_EVENTS
  end
  local health = spec and spec.health
  local unit = frame and frame.unit
  if unit == "player" or (spec and spec.key == "player") then
    return HEALTH_EVENTS_PLAYER
  end
  if (health and health.mode) ~= "class" then
    return HEALTH_EVENTS_NO_FACTION
  end
  if health and health.npcColorMode == "type" and health.npcTypeColorBar ~= false then
    return HEALTH_EVENTS_CLASS_NPC_TYPE
  end
  return Health.events
end

function Health.GetUnitlessEvents(frame, spec)
  local unit = frame and frame.unit
  if unit == "player" or (spec and spec.key == "player") then
    return HEALTH_PLAYER_LIFECYCLE_EVENTS
  end
  return nil
end

function Health.UpdateValuePlain(frame, event, unit)
  unit = unit or frame.unit
  if issecretvalue(unit) == true or unit ~= "player" then
    return Health.UpdateValue(frame, event, unit)
  end
  local bar = frame.hpBar
  if not bar then
    return
  end

  local hp = UnitHealth(unit)
  if issecretvalue(hp) == true then
    return Health.UpdateValue(frame, event, unit)
  end
  if hp == nil then hp = 0 end
  StoreHealthValue(bar, unit, hp, false)

  local maxUnit = bar._msufHealthMaxUnit
  local maxReady = bar._msufHealthMaxReady == true and maxUnit == unit
  local maxHP
  if maxReady then
    maxHP = bar._msufHealthMax
  else
    maxHP = UnitHealthMax(unit)
    if issecretvalue(maxHP) == true then
      return Health.UpdateValue(frame, event, unit)
    end
    if maxHP == nil then maxHP = 1 end
    StoreHealthMax(bar, unit, maxHP, false)
  end

  if bar._msufMinMaxInit ~= true then
    SetBarMinMaxPlain(bar, maxHP)
    bar._msufMinMaxInit = true
  end
  SetBarValuePlain(bar, hp, true)

  local coldColor = frame._msufHealthColdColor == true
  local updateColor
  if coldColor then
    updateColor = bar._msufStatusR == nil
  else
    updateColor = frame._msufHealthColorByHealth == true or bar._msufStatusR == nil
  end

  local gradientBucket
  if frame._msufHealthColorByHealth == true and type(hp) == "number" and type(maxHP) == "number" and maxHP > 0 then
    gradientBucket = floor((hp / maxHP) * 100 + 0.5)
    if bar._msufGradientPct == gradientBucket then
      updateColor = false
    end
  end

  local rawHealthColor
  if updateColor then
    rawHealthColor = ApplyHealthStatusColor(bar, frame, unit, hp, maxHP, nil, event or "UNIT_HEALTH")
    if gradientBucket ~= nil then
      bar._msufGradientPct = rawHealthColor == true and gradientBucket or nil
    end
  end
  if updateColor and not rawHealthColor and (frame._msufHealthBgDynamic == true or frame._msufPowerBgDynamic == true) then
    ApplyBackgrounds(frame, frame._msufHealthBgDynamic == true, frame._msufPowerBgDynamic == true)
  end
  RefreshGroupDeadStateFromHealth(frame, event, unit, hp, false)
  return hp, maxHP
end

function Health.UpdateValueStaticPlain(frame, event, unit)
  unit = unit or frame.unit
  if issecretvalue(unit) == true or unit ~= "player" then
    return Health.UpdateValueStatic(frame, event, unit)
  end
  local bar = frame.hpBar
  if not bar then
    return
  end

  local hp = UnitHealth(unit)
  if issecretvalue(hp) == true then
    return Health.UpdateValueStatic(frame, event, unit)
  end
  if hp == nil then hp = 0 end
  StoreHealthValue(bar, unit, hp, false)

  local maxHP
  if bar._msufHealthMaxReady == true and bar._msufHealthMaxUnit == unit then
    maxHP = bar._msufHealthMax
  else
    maxHP = UnitHealthMax(unit)
    if issecretvalue(maxHP) == true then
      return Health.UpdateValueStatic(frame, event, unit)
    end
    if maxHP == nil then maxHP = 1 end
    StoreHealthMax(bar, unit, maxHP, false)
  end

  if bar._msufMinMaxInit ~= true then
    SetBarMinMaxPlain(bar, maxHP)
    bar._msufMinMaxInit = true
  end
  SetBarValuePlain(bar, hp, true)

  local zeroHealth = hp == 0
  if bar._msufStatusR == nil or bar._msufStaticZeroHealth ~= zeroHealth then
    bar._msufStaticZeroHealth = zeroHealth
    ApplyHealthStatusColor(bar, frame, unit, hp, maxHP, nil, event or "UNIT_HEALTH")
  end
  return hp, maxHP
end

function Health.UpdateValueStatic(frame, event, unit)
  unit = unit or frame.unit
  local bar = frame.hpBar
  if not bar then
    return
  end

  local hp = UnitHealth(unit)
  local hpSecret = issecretvalue(hp) == true
  if not hpSecret and hp == nil then hp = 0 end
  local cacheUnit = unit
  StoreHealthValue(bar, cacheUnit, hp, hpSecret)

  local maxHP, maxSecret
  if bar._msufHealthMaxReady == true and cacheUnit ~= nil and bar._msufHealthMaxUnit == cacheUnit then
    maxHP = bar._msufHealthMax
    maxSecret = bar._msufHealthMaxSecret == true
  else
    maxHP = UnitHealthMax(unit)
    maxSecret = issecretvalue(maxHP) == true
    if not maxSecret and maxHP == nil then maxHP = 1 end
    StoreHealthMax(bar, cacheUnit, maxHP, maxSecret)
  end

  if bar._msufMinMaxInit ~= true then
    SetBarMinMaxKnown(bar, maxHP, maxSecret)
    bar._msufMinMaxInit = true
  end
  SetBarValueKnown(bar, hp, hpSecret, true)

  local zeroHealth = not hpSecret and hp == 0
  if bar._msufStatusR == nil or bar._msufStaticZeroHealth ~= zeroHealth then
    bar._msufStaticZeroHealth = zeroHealth
    ApplyHealthStatusColor(bar, frame, unit, hp, maxHP, nil, event or "UNIT_HEALTH")
  end
  return hp, maxHP
end

function Health.UpdateValueGroupStatic(frame, event, unit)
  unit = unit or frame.unit
  local bar = frame.hpBar
  if not bar then
    return
  end

  local hp = UnitHealth(unit)
  local hpSecret = issecretvalue(hp) == true
  if not hpSecret and hp == nil then hp = 0 end
  local cacheUnit = unit
  StoreHealthValue(bar, cacheUnit, hp, hpSecret)

  local maxHP, maxSecret
  if bar._msufHealthMaxReady == true and cacheUnit ~= nil and bar._msufHealthMaxUnit == cacheUnit then
    maxHP = bar._msufHealthMax
    maxSecret = bar._msufHealthMaxSecret == true
  else
    maxHP = UnitHealthMax(unit)
    maxSecret = issecretvalue(maxHP) == true
    if not maxSecret and maxHP == nil then maxHP = 1 end
    StoreHealthMax(bar, cacheUnit, maxHP, maxSecret)
  end

  if bar._msufMinMaxInit ~= true then
    SetBarMinMaxKnown(bar, maxHP, maxSecret)
    bar._msufMinMaxInit = true
  end
  SetBarValueKnown(bar, hp, hpSecret, true)

  local zeroHealth = not hpSecret and hp == 0
  if bar._msufStatusR == nil or bar._msufStaticZeroHealth ~= zeroHealth then
    bar._msufStaticZeroHealth = zeroHealth
    ApplyHealthStatusColor(bar, frame, unit, hp, maxHP, nil, event or "UNIT_HEALTH")
  end
  RefreshGroupDeadStateFromHealth(frame, event, unit, hp, hpSecret)
  return hp, maxHP
end

--- EUI-parity percent path for group frames that never need an absolute HP
--- number (no "number" text mode, no gradient-by-health color). One
--- `UnitHealthPercent` C-call handles value + secret + scale-to-100; there is no
--- `UnitHealthMax`, no MaxHP cache, and no second `issecretvalue`. MinMax is
--- pinned to (0,100) once, so only the fill value moves per event. Returns the
--- percent as the first value so the compiled text writer reuses it instead of
--- calling `UnitHealthPercent` a second time (dispatch key mode 4). The second
--- return is nil: this path is gated on "no max needed", so no caller reads it.
function Health.UpdateValueGroupPercent(frame, event, unit)
  unit = unit or frame.unit
  local bar = frame.hpBar
  if not bar then
    return
  end

  local pct = UnitHealthPercent(unit, true, SCALE_100)
  local pctSecret = issecretvalue(pct) == true
  if not pctSecret and pct == nil then pct = 0 end

  -- Always (re-)assert the 0-100 scale: UNIT_MAXHEALTH runs UpdateMaxValueStatic
  -- (which pins MinMax to the absolute max), so a shared _msufMinMaxInit guard
  -- would leave the bar on absolute min/max while we feed it a percent.
  -- SetBarMinMaxKnown dedups internally (no-op when already 0-100).
  SetBarMinMaxKnown(bar, 100, false)
  bar._msufMinMaxInit = true
  SetBarValueKnown(bar, pct, pctSecret, true)

  local zeroHealth = not pctSecret and pct == 0
  if bar._msufStatusR == nil or bar._msufStaticZeroHealth ~= zeroHealth then
    bar._msufStaticZeroHealth = zeroHealth
    ApplyHealthStatusColor(bar, frame, unit, nil, nil, nil, event or "UNIT_HEALTH")
  end
  RefreshGroupDeadStateFromHealth(frame, event, unit, pct, pctSecret)
  return pct, nil
end

--- Percent path for SINGLE frames (target/focus/boss/pet). Same idea as
--- UpdateValueGroupPercent -- one UnitHealthPercent C-call, no UnitHealth/
--- UnitHealthMax/Store bookkeeping, MinMax pinned to (0,100) -- so a boss target
--- taking sustained damage spends far less per health tick. The one difference
--- from the group variant: single-frame health COLOR depends on unit identity
--- (class/reaction/NPC changes on a target swap), so color is resolved on any
--- non-tick event (identity/flags/faction) and dedup-skipped on a plain tick,
--- exactly like Health.UpdateValueStatic. No RefreshGroupDeadStateFromHealth
--- (that is group-only and early-outs anyway).
function Health.UpdateValuePercent(frame, event, unit)
  unit = unit or frame.unit
  local bar = frame.hpBar
  if not bar then
    return
  end

  local pct = UnitHealthPercent(unit, true, SCALE_100)
  local pctSecret = issecretvalue(pct) == true
  if not pctSecret and pct == nil then pct = 0 end

  if bar._msufMinMaxInit ~= true then
    SetBarMinMaxKnown(bar, 100, false)
    bar._msufMinMaxInit = true
  end
  SetBarValueKnown(bar, pct, pctSecret, event == "UNIT_HEALTH")
  if event ~= "UNIT_HEALTH" then
    SnapBarInterpolation(bar)
  end

  -- Color: on a plain health tick keep the resolved color (dedup on _msufStatusR
  -- + zero-health toggle); on any identity/flag/faction event re-resolve, because
  -- the unit or its class/reaction/state may have changed.
  local zeroHealth = not pctSecret and pct == 0
  local tick = event == "UNIT_HEALTH"
  if not tick or bar._msufStatusR == nil or bar._msufStaticZeroHealth ~= zeroHealth then
    bar._msufStaticZeroHealth = zeroHealth
    ApplyHealthStatusColor(bar, frame, unit, nil, nil, nil, event or "UNIT_HEALTH")
  end
  return pct, nil
end

--- Called by the text runtime once the health-text mode is resolved (it is
--- registered after Health, so Health.Apply cannot see the text runtime for the
--- current spec). Promotes a group-static-hot frame to the EUI percent path when
--- NO consumer needs an absolute HP number: dispatch key mode 0 (no text) or 4
--- (percent-only text, no max). Modes 1/2/3/5 need current and/or max, so they
--- stay on the absolute static path. Requires the ScaleTo100 curve constant;
--- without it (older client) the percent API is unavailable and we keep static.
--- Idempotent and reversible: a later config change that adds a number slot
--- re-runs this and restores the static updater.
--- Unified percent-path promotion for BOTH group and single frames. Called from
--- the text runtime once the health-text mode is known. Picks the percent updater
--- when NO consumer needs an absolute HP number (dispatch key mode 0/4) and the
--- frame is percent-eligible (static color, no gradient/bg-match, no prediction/
--- group-visuals that need raw hp). Group frames use the Group* pair, single
--- frames the plain pair. Idempotent + reversible: a config change that adds an
--- absolute-number text slot re-runs this and restores the static updater. The
--- name is kept (SelectGroupHealthUpdater) since callers reference it.
function Health.SelectGroupHealthUpdater(frame)
  local isGroup = frame._msufGroupStaticHot == true
  local isSingle = frame._msufSingleStaticHot == true
  if not (isGroup or isSingle) then
    return
  end
  local percentFn = isGroup and Health.UpdateValueGroupPercent or Health.UpdateValuePercent
  local staticFn = isGroup and Health.UpdateValueGroupStatic
    or (frame.unit == "player" and Health.UpdateValueStaticPlain or Health.UpdateValueStatic)

  local function useStatic()
    if frame._msufUpdateHealthValue == percentFn then
      frame._msufUpdateHealthValue = staticFn
      local bar = frame.hpBar
      if bar then bar._msufMinMaxInit = nil end
    end
  end

  -- Prediction (and group health-visuals) consume RAW hp/hpMax (heal/absorb bars,
  -- over-absorb glow), which the percent path does not produce -> not eligible.
  local active = frame._msufActiveElements
  if active and (active.Prediction == true or (isGroup and active.GroupVisuals == true)) then
    useStatic()
    return
  end
  local rt = frame._msufTextRuntime
  local mode = rt and rt.healthDispatchKeyMode or 0
  local percentOnly = SCALE_100 ~= nil and UnitHealthPercent ~= nil
    and (mode == 0 or mode == 4)
  if percentOnly then
    if frame._msufUpdateHealthValue ~= percentFn then
      frame._msufUpdateHealthValue = percentFn
      local bar = frame.hpBar
      if bar then bar._msufMinMaxInit = nil end
    end
  else
    useStatic()
  end
end

function Health.UpdateValue(frame, event, unit)
  unit = unit or frame.unit
  local bar = frame.hpBar
  if not bar then
    return
  end

  local hp = UnitHealth(unit)
  local hpSecret = issecretvalue(hp) == true
  if not hpSecret and hp == nil then hp = 0 end
  local cacheUnit = unit
  StoreHealthValue(bar, cacheUnit, hp, hpSecret)

  local maxUnit = bar._msufHealthMaxUnit
  local maxReady = bar._msufHealthMaxReady == true
    and cacheUnit ~= nil
    and maxUnit == cacheUnit
  local maxHP, maxSecret
  if maxReady then
    maxHP = bar._msufHealthMax
    maxSecret = bar._msufHealthMaxSecret == true
  else
    maxHP = UnitHealthMax(unit)
    maxSecret = issecretvalue(maxHP) == true
    if not maxSecret and maxHP == nil then maxHP = 1 end
    StoreHealthMax(bar, cacheUnit, maxHP, maxSecret)
  end

  if bar._msufMinMaxInit ~= true then
    SetBarMinMaxKnown(bar, maxHP, maxSecret)
    bar._msufMinMaxInit = true
  end
  SetBarValueKnown(bar, hp, hpSecret, true)

  local coldColor = frame._msufHealthColdColor == true
  local updateColor
  if coldColor then
    updateColor = bar._msufStatusR == nil
  else
    updateColor = frame._msufHealthColorByHealth == true or bar._msufStatusR == nil
  end

  local gradientBucket
  if frame._msufHealthColorByHealth == true then
    if not (hpSecret or maxSecret)
      and type(hp) == "number" and type(maxHP) == "number" and maxHP > 0 then
      gradientBucket = floor((hp / maxHP) * 100 + 0.5)
      if bar._msufGradientPct == gradientBucket then
        updateColor = false
      end
    elseif GetTime then
      bar._msufGradientPct = nil
      local now = GetTime()
      local nextAt = bar._msufGradientThrottleAt
      if nextAt and now < nextAt then
        updateColor = false
      else
        bar._msufGradientThrottleAt = now + GRADIENT_SECRET_THROTTLE
      end
    end
  end

  local rawHealthColor
  if updateColor then
    rawHealthColor = ApplyHealthStatusColor(bar, frame, unit, hp, maxHP, nil, event or "UNIT_HEALTH")
    if gradientBucket ~= nil then
      bar._msufGradientPct = rawHealthColor == true and gradientBucket or nil
    end
  end
  if updateColor and not rawHealthColor and (frame._msufHealthBgDynamic == true or frame._msufPowerBgDynamic == true) then
    ApplyBackgrounds(frame, frame._msufHealthBgDynamic == true, frame._msufPowerBgDynamic == true)
  end
  RefreshGroupDeadStateFromHealth(frame, event, unit, hp, hpSecret)
  return hp, maxHP
end

function Health.UpdateMaxValuePlain(frame, event, unit)
  unit = unit or frame.unit
  if issecretvalue(unit) == true or unit ~= "player" then
    return Health.UpdateMaxValue(frame, event, unit)
  end
  local bar = frame.hpBar
  if not bar then
    return
  end

  local hp = UnitHealth(unit)
  if issecretvalue(hp) == true then
    return Health.UpdateMaxValue(frame, event, unit)
  end
  if hp == nil then hp = 0 end
  local maxHP = UnitHealthMax(unit)
  if issecretvalue(maxHP) == true then
    return Health.UpdateMaxValue(frame, event, unit)
  end
  if maxHP == nil then maxHP = 1 end
  StoreHealthValue(bar, unit, hp, false)
  StoreHealthMax(bar, unit, maxHP, false)

  SetBarMinMaxPlain(bar, maxHP)
  bar._msufMinMaxInit = true
  SetBarValuePlain(bar, hp, false)
  SnapBarInterpolation(bar)

  local rawHealthColor
  local updateColor = frame._msufHealthColorByHealth == true or frame._msufHealthColdColor ~= true or bar._msufStatusR == nil
  if updateColor then
    rawHealthColor = ApplyHealthStatusColor(bar, frame, unit, hp, maxHP, nil, event or "UNIT_MAXHEALTH")
    bar._msufGradientPct = nil
  end
  if updateColor and not rawHealthColor and (frame._msufHealthBgDynamic == true or frame._msufPowerBgDynamic == true) then
    ApplyBackgrounds(frame, frame._msufHealthBgDynamic == true, frame._msufPowerBgDynamic == true)
  end
  return hp, maxHP
end

function Health.UpdateMaxValueStaticPlain(frame, event, unit)
  unit = unit or frame.unit
  if issecretvalue(unit) == true or unit ~= "player" then
    return Health.UpdateMaxValueStatic(frame, event, unit)
  end
  local bar = frame.hpBar
  if not bar then
    return
  end

  local hp = UnitHealth(unit)
  if issecretvalue(hp) == true then
    return Health.UpdateMaxValueStatic(frame, event, unit)
  end
  if hp == nil then hp = 0 end
  local maxHP = UnitHealthMax(unit)
  if issecretvalue(maxHP) == true then
    return Health.UpdateMaxValueStatic(frame, event, unit)
  end
  if maxHP == nil then maxHP = 1 end
  StoreHealthValue(bar, unit, hp, false)
  StoreHealthMax(bar, unit, maxHP, false)

  SetBarMinMaxPlain(bar, maxHP)
  bar._msufMinMaxInit = true
  SetBarValuePlain(bar, hp, false)
  SnapBarInterpolation(bar)

  local zeroHealth = hp == 0
  if bar._msufStatusR == nil or bar._msufStaticZeroHealth ~= zeroHealth then
    bar._msufStaticZeroHealth = zeroHealth
    ApplyHealthStatusColor(bar, frame, unit, hp, maxHP, nil, event or "UNIT_MAXHEALTH")
  end
  return hp, maxHP
end

function Health.UpdateMaxValueStatic(frame, event, unit)
  unit = unit or frame.unit
  local bar = frame.hpBar
  if not bar then
    return
  end

  local hp = UnitHealth(unit)
  local hpSecret = issecretvalue(hp) == true
  if not hpSecret and hp == nil then hp = 0 end
  local maxHP = UnitHealthMax(unit)
  local maxSecret = issecretvalue(maxHP) == true
  if not maxSecret and maxHP == nil then maxHP = 1 end
  local cacheUnit = unit
  StoreHealthValue(bar, cacheUnit, hp, hpSecret)
  StoreHealthMax(bar, cacheUnit, maxHP, maxSecret)

  SetBarMinMaxKnown(bar, maxHP, maxSecret)
  bar._msufMinMaxInit = true
  SetBarValueKnown(bar, hp, hpSecret, false)
  SnapBarInterpolation(bar)

  local zeroHealth = not hpSecret and hp == 0
  if bar._msufStatusR == nil or bar._msufStaticZeroHealth ~= zeroHealth then
    bar._msufStaticZeroHealth = zeroHealth
    ApplyHealthStatusColor(bar, frame, unit, hp, maxHP, nil, event or "UNIT_MAXHEALTH")
  end
  return hp, maxHP
end

function Health.UpdateMaxValue(frame, event, unit)
  unit = unit or frame.unit
  local bar = frame.hpBar
  if not bar then
    return
  end

  local hp = UnitHealth(unit)
  local hpSecret = issecretvalue(hp) == true
  if not hpSecret and hp == nil then hp = 0 end
  local maxHP = UnitHealthMax(unit)
  local maxSecret = issecretvalue(maxHP) == true
  if not maxSecret and maxHP == nil then maxHP = 1 end
  local cacheUnit = unit
  StoreHealthValue(bar, cacheUnit, hp, hpSecret)
  StoreHealthMax(bar, cacheUnit, maxHP, maxSecret)

  SetBarMinMaxKnown(bar, maxHP, maxSecret)
  bar._msufMinMaxInit = true
  SetBarValueKnown(bar, hp, hpSecret, false)
  SnapBarInterpolation(bar)

  local rawHealthColor
  local updateColor = frame._msufHealthColorByHealth == true or frame._msufHealthColdColor ~= true or bar._msufStatusR == nil
  if updateColor then
    rawHealthColor = ApplyHealthStatusColor(bar, frame, unit, hp, maxHP, nil, event or "UNIT_MAXHEALTH")
    bar._msufGradientPct = nil
  end
  if updateColor and not rawHealthColor and (frame._msufHealthBgDynamic == true or frame._msufPowerBgDynamic == true) then
    ApplyBackgrounds(frame, frame._msufHealthBgDynamic == true, frame._msufPowerBgDynamic == true)
  end
  return hp, maxHP
end

function Health.UpdateConnectionState(frame, event, unit)
  unit = unit or frame.unit
  local bar = frame.hpBar
  if not bar then
    return
  end

  local cacheUnit = unit
  local valueUnit = bar._msufHealthValueUnit
  local hp = cacheUnit ~= nil and valueUnit == cacheUnit and bar._msufHealthValue or nil
  local hpSecret = issecretvalue(hp) == true
  if not hpSecret and hp == nil then
    hp = UnitHealth(unit)
    hpSecret = issecretvalue(hp) == true
    if not hpSecret and hp == nil then hp = 0 end
    StoreHealthValue(bar, cacheUnit, hp, hpSecret)
  end

  local maxUnit = bar._msufHealthMaxUnit
  local maxReady = bar._msufHealthMaxReady == true
    and cacheUnit ~= nil
    and maxUnit == cacheUnit
  local maxHP, maxSecret
  if maxReady then
    maxHP = bar._msufHealthMax
    maxSecret = bar._msufHealthMaxSecret == true
  else
    maxHP = UnitHealthMax(unit)
    maxSecret = issecretvalue(maxHP) == true
    if not maxSecret and maxHP == nil then maxHP = 1 end
    StoreHealthMax(bar, cacheUnit, maxHP, maxSecret)
  end

  local wroteBar
  if bar._msufMinMaxInit ~= true then
    wroteBar = SetBarMinMaxKnown(bar, maxHP, maxSecret) or wroteBar
    bar._msufMinMaxInit = true
  end
  wroteBar = SetBarValueKnown(bar, hp, hpSecret, false) or wroteBar
  if wroteBar or bar._msufInterpolating == true then
    SnapBarInterpolation(bar)
  end

  local colorKey = ConnectionStatusKey(frame, unit, event)
  if colorKey == nil or frame._msufHealthConnectionColorKey ~= colorKey then
    local rawHealthColor = ApplyHealthStatusColor(bar, frame, unit, hp, maxHP, nil, event or "UNIT_CONNECTION")
    frame._msufHealthConnectionColorKey = colorKey
    if rawHealthColor ~= true then
      bar._msufGradientPct = nil
    end
    if not rawHealthColor and (frame._msufHealthBgDynamic == true or frame._msufPowerBgDynamic == true) then
      ApplyBackgrounds(frame, frame._msufHealthBgDynamic == true, frame._msufPowerBgDynamic == true)
    end
  end
  return hp, maxHP
end

function Health.UpdateIdentityColor(frame, event, unit)
  unit = unit or frame.unit
  local bar = frame.hpBar
  if not bar then
    return
  end
  local cacheUnit = unit
  local hpUnit = bar._msufHealthValueUnit
  local maxUnit = bar._msufHealthMaxUnit
  local hp = cacheUnit ~= nil and hpUnit == cacheUnit and bar._msufHealthValue or nil
  local maxHP = cacheUnit ~= nil and maxUnit == cacheUnit and bar._msufHealthMax or nil
  local rawHealthColor = ApplyHealthStatusColor(bar, frame, unit, hp, maxHP, nil, event or "UNIT_CLASSIFICATION_CHANGED")
  if rawHealthColor ~= true then
    bar._msufGradientPct = nil
  end
  if not rawHealthColor and (frame._msufHealthBgDynamic == true or frame._msufPowerBgDynamic == true) then
    ApplyBackgrounds(frame, frame._msufHealthBgDynamic == true, frame._msufPowerBgDynamic == true)
  end
  return hp, maxHP
end

function Health.Update(frame, event, unit)
  unit = unit or frame.unit
  local bar = frame.hpBar
  if not bar then
    return
  end
  local coldColor = frame._msufHealthColdColor == true

  if event == "UNIT_FLAGS" or event == "UNIT_FACTION" then
    local cacheUnit = unit
    local hpUnit = bar._msufHealthValueUnit
    local maxUnit = bar._msufHealthMaxUnit
    local hp = cacheUnit ~= nil and hpUnit == cacheUnit and bar._msufHealthValue or nil
    local maxHP = cacheUnit ~= nil and maxUnit == cacheUnit and bar._msufHealthMax or nil
    -- UNIT_FLAGS fires very frequently in combat (dispatch probe: boss
    -- UNIT_FLAGS ~20x in a 6s window) but the health *color* for a flag change
    -- only depends on exists/dead/connected state. Gate ONLY UNIT_FLAGS on the
    -- same status key UpdateConnectionState uses, so flag spam that doesn't
    -- change that state skips ApplyHealthStatusColor. UNIT_FACTION is NOT gated:
    -- it can change reaction/PvP color without changing the status key, so it
    -- must always recolor.
    if event == "UNIT_FLAGS" then
      local colorKey = ConnectionStatusKey(frame, unit, event)
      if colorKey ~= nil and frame._msufHealthConnectionColorKey == colorKey then
        return hp, maxHP
      end
      local rawHealthColor = ApplyHealthStatusColor(bar, frame, unit, hp, maxHP, nil, event)
      frame._msufHealthConnectionColorKey = colorKey
      if rawHealthColor ~= true then
        bar._msufGradientPct = nil
      end
      if not rawHealthColor and (frame._msufHealthBgDynamic == true or frame._msufPowerBgDynamic == true) then
        ApplyBackgrounds(frame, frame._msufHealthBgDynamic == true, frame._msufPowerBgDynamic == true)
      end
      return hp, maxHP
    end
    local rawHealthColor = ApplyHealthStatusColor(bar, frame, unit, hp, maxHP, nil, event)
    if rawHealthColor ~= true then
      bar._msufGradientPct = nil
    end
    if not rawHealthColor and (frame._msufHealthBgDynamic == true or frame._msufPowerBgDynamic == true) then
      ApplyBackgrounds(frame, frame._msufHealthBgDynamic == true, frame._msufPowerBgDynamic == true)
    end
    return hp, maxHP
  end

  local hp = UnitHealth(unit)
  local hpSecret = issecretvalue(hp) == true
  if not hpSecret and hp == nil then hp = 0 end
  local cacheUnit = unit
  StoreHealthValue(bar, cacheUnit, hp, hpSecret)

  local animate = event == "UNIT_HEALTH"
  local maxUnit = bar._msufHealthMaxUnit
  local maxReady = bar._msufHealthMaxReady == true
    and cacheUnit ~= nil
    and maxUnit == cacheUnit
  local maxHP, maxSecret
  if animate and maxReady then
    maxHP = bar._msufHealthMax
    maxSecret = bar._msufHealthMaxSecret == true
  else
    maxHP = UnitHealthMax(unit)
    maxSecret = issecretvalue(maxHP) == true
    if not maxSecret and maxHP == nil then maxHP = 1 end
    StoreHealthMax(bar, cacheUnit, maxHP, maxSecret)
  end

  if not animate or bar._msufMinMaxInit ~= true then
    SetBarMinMaxKnown(bar, maxHP, maxSecret)
    bar._msufMinMaxInit = true
  end
  SetBarValueKnown(bar, hp, hpSecret, animate)
  if not animate then
    SnapBarInterpolation(bar)
  end

  local updateColor
  if coldColor then
    updateColor = bar._msufStatusR == nil or (event ~= "UNIT_HEALTH" and event ~= "UNIT_MAXHEALTH")
  else
    updateColor = frame._msufHealthColorByHealth == true
      or event ~= "UNIT_HEALTH"
      or bar._msufStatusR == nil
  end

  local gradientBucket
  if event == "UNIT_HEALTH" and frame._msufHealthColorByHealth == true then
    if not (hpSecret or maxSecret)
      and type(hp) == "number" and type(maxHP) == "number" and maxHP > 0 then
      gradientBucket = floor((hp / maxHP) * 100 + 0.5)
      if bar._msufGradientPct == gradientBucket then
        updateColor = false
      end
    elseif GetTime then
      bar._msufGradientPct = nil
      local now = GetTime()
      local nextAt = bar._msufGradientThrottleAt
      if nextAt and now < nextAt then
        updateColor = false
      else
        bar._msufGradientThrottleAt = now + GRADIENT_SECRET_THROTTLE
      end
    end
  end

  local rawHealthColor
  if updateColor then
    rawHealthColor = ApplyHealthStatusColor(bar, frame, unit, hp, maxHP, nil, event)
    if gradientBucket ~= nil then
      bar._msufGradientPct = rawHealthColor == true and gradientBucket or nil
    end
  end
  if updateColor and not rawHealthColor and (frame._msufHealthBgDynamic == true or frame._msufPowerBgDynamic == true) then
    ApplyBackgrounds(frame, frame._msufHealthBgDynamic == true, frame._msufPowerBgDynamic == true)
  end
  RefreshGroupDeadStateFromHealth(frame, event, unit, hp, hpSecret)
  return hp, maxHP
end

UF.RegisterElement("Health", Health)
