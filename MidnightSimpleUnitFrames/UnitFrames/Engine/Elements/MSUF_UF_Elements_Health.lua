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
local CreateLossTrail = C and C.CreateLossTrail
local SetBarSmoothing = C and C.SetBarSmoothing
local ApplyHealthStatusColor = C and C.ApplyHealthStatusColor
local ApplyBackgrounds = C and C.ApplyBackgrounds
local ApplyBarGradient = C and C.ApplyBarGradient
local PrepareHealthGradientCurve = C and C.PrepareHealthGradientCurve
local issecretvalue = _G.issecretvalue or function(_) return false end
local math_max = math.max
local ExportPublic = MSUF.ExportPublic or function(name, value)
  _G[name] = value
  return value
end

local Health = {}
local EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION" }
local STATUS_COLOR_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION", "UNIT_FLAGS" }
local IDENTITY_STATUS_COLOR_EVENTS = {
  "UNIT_HEALTH",
  "UNIT_MAXHEALTH",
  "UNIT_CONNECTION",
  "UNIT_FLAGS",
  "UNIT_NAME_UPDATE",
  "UNIT_FACTION",
  "UNIT_CLASSIFICATION_CHANGED",
  "UNIT_LEVEL",
}
local COLOR_ONLY_EVENTS = {
  UNIT_FLAGS = true,
  UNIT_NAME_UPDATE = true,
  UNIT_FACTION = true,
  UNIT_CLASSIFICATION_CHANGED = true,
  UNIT_LEVEL = true,
}
local PLAYER_STATUS_COLOR_EVENTS = { "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }
local GROUP_LIFECYCLE_EVENTS = { "PARTY_MEMBER_ENABLE", "PARTY_MEMBER_DISABLE" }
local IDENTITY_EVENTS = {
  MSUF_UNIT_IDENTITY = true,
  MSUF_UNIT_IDENTITY_FAST = true,
  MSUF_UNIT_IDENTITY_SOFT = true,
  MSUF_UNIT_IDENTITY_SOFT_FAST = true,
  MSUF_GF_UNIT_IDENTITY = true,
  MSUF_GF_UNIT_STRUCTURE = true,
  MSUF_GF_NAME_UPDATE = true,
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

local function RuntimeColorNeedsIdentityForSpec(spec)
  local health = spec and spec.health
  local mode = health and health.mode
  return mode ~= "dark" and mode ~= "unified" and mode ~= "gradient"
end

local function RuntimeColorOnHealthEvent(frame, value, valueSecret)
  local gradient = frame and frame._msufHealthRuntimeGradient
  if gradient == nil and frame then
    local health = frame.MSUFSpec and frame.MSUFSpec.health
    gradient = health and health.mode == "gradient" or false
  end
  if gradient == true then
    return true
  end
  if frame and frame._msufHealthStatusGone == true then
    return true
  end
  if valueSecret == nil then valueSecret = issecretvalue(value) == true end
  if valueSecret == true then
    return false
  end
  return type(value) == "number" and value <= 0
end

local function ApplyRuntimeColor(frame, event, unit, hp, maxHP)
  local bar = frame and frame.hpBar
  local runtimeEnabled = frame and frame._msufHealthRuntimeColorEnabled
  if runtimeEnabled == nil and frame then
    runtimeEnabled = RuntimeColorEnabled(frame)
  end
  if not (bar and ApplyHealthStatusColor and runtimeEnabled == true) then
    return false
  end
  if issecretvalue(maxHP) ~= true
    and maxHP == nil
    and issecretvalue(hp) ~= true
    and type(hp) == "number" then
    maxHP = 100
  end
  ApplyHealthStatusColor(bar, frame, unit or frame.MSUFUnitKey, hp, maxHP, nil, event)
  return true
end

function Health.Layout(frame, spec, powerEnabled)
  local bar = frame and frame.hpBar
  if not bar then return end
  spec = spec or frame.MSUFSpec
  local power = spec and spec.power
  if powerEnabled == nil then powerEnabled = power and power.enabled == true end
  local powerInset = 0
  if powerEnabled == true and power and power.embed ~= false and power.detached ~= true then
    local replacementHeight = frame._msufAugPowerReplacementActive == true
      and tonumber(frame._msufAugPowerReplacementHeight) or nil
    powerInset = replacementHeight or tonumber(power.height) or 3
    if not IsFiniteNumber(powerInset) or powerInset < 0 then powerInset = 0 end
  end
  if bar._msufHealthPowerInset == powerInset and bar._msufHealthLayoutFrame == frame then return end
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, powerInset)
  bar._msufHealthPowerInset = powerInset
  bar._msufHealthLayoutFrame = frame
end

function Health.Create(frame, spec)
  if frame.hpBar then return end
  local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
  bg:SetAllPoints(frame)
  bg:SetColorTexture(0.02, 0.02, 0.025, spec and spec.backgroundAlpha or 0.72)
  frame.bg = bg
  frame.hpBarBG = bg
  frame.healthBg = bg

  local trail = CreateLossTrail and CreateLossTrail(frame, (spec and spec.texture) or WHITE, 100) or nil
  local bar = CreateFrame("StatusBar", nil, frame)
  bar:SetMinMaxValues(0, 100)
  bar:SetValue(100)
  bar:SetStatusBarTexture((spec and spec.texture) or WHITE)
  frame.hpBar = bar
  frame.Health = bar
  frame.health = bar
  if trail then
    trail:SetAllPoints(bar)
    trail:SetStatusBarColor(1, 0.55, 0.08, 1)
    if trail.SetFrameLevel and bar.GetFrameLevel then
      local level = bar:GetFrameLevel() or 1
      trail:SetFrameLevel(math_max(0, level - 1))
    end
    frame.healthLossTrail = trail
  end
  Health.Layout(frame, spec)
end

function Health.Apply(frame, spec)
  if not frame.hpBar then Health.Create(frame, spec) end
  frame.Health = frame.hpBar
  frame.health = frame.hpBar
  frame.healthBg = frame.hpBarBG or frame.bg
  Health.Layout(frame, spec)
  frame._msufIsGroupFrame = spec and spec.scope == "group" or nil
  local h = spec and spec.health or nil
  local mode = h and h.mode
  if mode == "gradient" and PrepareHealthGradientCurve then
    frame._msufHealthGradientCurve = PrepareHealthGradientCurve(h)
  else
    -- A text-only health gradient lazily seeds this on its next update. Clear
    -- the frame cache on every spec apply so changed colour stops are visible
    -- immediately without rechecking all nine values in the event hot path.
    frame._msufHealthGradientCurve = nil
  end
  frame._msufHealthRuntimeColorEnabled = mode ~= "dark" and mode ~= "unified"
  frame._msufHealthRuntimeGradient = mode == "gradient"
  SetTexture(frame.hpBar, h and h.texture or spec and spec.texture or WHITE)
  SetTexture(frame.healthLossTrail, h and h.texture or spec and spec.texture or WHITE)
  if frame.hpBar.SetOrientation then
    -- Native fill axis; set-once per Apply, no hot-path cost. VERTICAL combines
    -- with SetReverseFill below (reverse flips the direction within the axis).
    local orientation = (h and h.vertical == true) and "VERTICAL" or "HORIZONTAL"
    if frame.hpBar._msufOrientation ~= orientation then
      frame.hpBar:SetOrientation(orientation)
      frame.hpBar._msufOrientation = orientation
      -- Force the reverse-fill block below to re-apply after an axis flip.
      frame.hpBar._msufReverseFill = nil
    end
    if frame.healthLossTrail and frame.healthLossTrail._msufOrientation ~= orientation then
      frame.healthLossTrail:SetOrientation(orientation)
      frame.healthLossTrail._msufOrientation = orientation
      frame.healthLossTrail._msufReverseFill = nil
    end
  end
  if frame.hpBar.SetReverseFill then
    local reverse = h and h.reverse == true
    if frame.hpBar._msufReverseFill ~= reverse then
      frame.hpBar:SetReverseFill(reverse)
      frame.hpBar._msufReverseFill = reverse
    end
    if frame.healthLossTrail and frame.healthLossTrail._msufReverseFill ~= reverse then
      frame.healthLossTrail:SetReverseFill(reverse)
      frame.healthLossTrail._msufReverseFill = reverse
    end
  end
  frame.hpBar._msufMinMax = nil
  frame.hpBar._msufHealthValue = nil
  frame.hpBar._msufHealthMax = nil
  frame.hpBar._msufHealthValueUnit = nil
  frame.hpBar._msufHealthMaxUnit = nil
  frame.hpBar._msufHealthMaxReady = nil
  frame.hpBar._msufHealthPercentValue = nil
  frame.hpBar._msufHealthPercentUnit = nil
  if frame.healthLossTrail then
    frame.healthLossTrail:SetStatusBarColor(
      h and h.lossR or 1,
      h and h.lossG or 0.55,
      h and h.lossB or 0.08,
      1)
  end
  if SetBarSmoothing then
    SetBarSmoothing(frame.hpBar, h and h.smooth == true, h and h.chunked == true, frame.healthLossTrail)
  end
  if ApplyBarGradient then ApplyBarGradient(frame, frame.hpBar, h and h.barGradient, "hpGradients") end
  SetColor(frame, true)
  -- Apply is the authoritative cold path. A secure show/startup transition can
  -- reset the live texture while leaving our last-value cache intact, so never
  -- let that cache suppress the saved background opacity here.
  if ApplyBackgrounds then ApplyBackgrounds(frame, true, false, true) end
  ApplyRuntimeColor(frame, "MSUF_COLOR_CHANGE", frame.MSUFUnitKey)
  if type(_G.MSUF_ApplyBossPhysicalBarGeometry) == "function" then
    _G.MSUF_ApplyBossPhysicalBarGeometry(frame)
  end
end

function Health.GetEvents(frame, spec)
  if not RuntimeColorEnabledForSpec(spec) then return EVENTS end
  return RuntimeColorNeedsIdentityForSpec(spec) and IDENTITY_STATUS_COLOR_EVENTS or STATUS_COLOR_EVENTS
end

function Health.GetUnitlessEvents(frame, spec)
  if spec and spec.scope == "group" then
    return GROUP_LIFECYCLE_EVENTS
  end
  if frame and frame.MSUFUnitKey == "player" and RuntimeColorEnabledForSpec(spec) then
    return PLAYER_STATUS_COLOR_EVENTS
  end
  return nil
end

local function UpdatePercent(frame, unit, animate)
  if not (UnitHealthPercent and SCALE_100) then return false end
  local pct = UnitHealthPercent(unit, true, SCALE_100)
  local secret = issecretvalue(pct) == true
  if not secret and not IsFiniteNumber(pct) then pct = 0 end
  local bar = frame.hpBar
  -- Secret min/max and value payloads are never retained in these caches; the
  -- secret branches below clear them. Comparing the plain cache fields is
  -- therefore sufficient and avoids two secret-value API calls per update.
  if bar._msufMinMax ~= 100 then
    bar:SetMinMaxValues(0, 100)
    bar._msufMinMax = 100
  end
  if secret
    or bar._msufHealthPercentValue ~= pct
    or bar._msufHealthPercentUnit ~= unit then
    -- Restricted values cannot be deduplicated, but they must keep the
    -- configured native interpolation: SetValue accepts secret values with an
    -- interpolation mode (only the enum itself must stay plain), and stripping
    -- it here turned smoothing off exactly in combat, where values are secret.
    local interp = animate == true and bar._msufSmoothInterp or nil
    if interp then
      bar:SetValue(pct, interp)
      bar._msufInterpolating = true
    else
      bar:SetValue(pct)
      bar._msufInterpolating = nil
    end
    if secret then
      bar._msufHealthPercentValue = nil
      bar._msufHealthPercentUnit = nil
    else
      bar._msufHealthPercentValue = pct
      bar._msufHealthPercentUnit = unit
    end
  end
  local rt = frame._msufTextRuntime
  if rt and (animate ~= true or rt.healthDefersUnitHealthText ~= true)
    and (rt.healthNeedsPercent == true or rt.healthColorByHealth == true) then
    rt._dispatchHealthPercent = pct
    rt._dispatchHealthPercentReady = true
  end
  return true, pct, nil, true, secret
end

local function UpdateAbsoluteValues(frame, unit, hp, maxHP, refreshMax, animate)
  local hpSecret = issecretvalue(hp) == true
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
  local maxNeedsRefresh = refreshMax == true
    or bar._msufHealthMaxReady ~= true
    or bar._msufHealthMaxUnit ~= unit
  local maxChanged = false
  if maxSecret then
    if maxNeedsRefresh then
      bar:SetMinMaxValues(0, maxHP)
      bar._msufMinMax = nil
    end
  else
    maxChanged = bar._msufMinMax ~= maxHP
    if maxChanged then
      bar:SetMinMaxValues(0, maxHP)
      bar._msufMinMax = maxHP
    end
  end
  if maxSecret then
    -- Secret values are opaque payloads: retain them only for native
    -- forwarding between UNIT_MAXHEALTH boundaries, never for comparison.
    if maxNeedsRefresh then
      bar._msufHealthMax = maxHP
      bar._msufHealthMaxUnit = unit
      bar._msufHealthMaxReady = true
    end
  else
    if maxNeedsRefresh or maxChanged then
      bar._msufHealthMax = maxHP
      bar._msufHealthMaxUnit = unit
      bar._msufHealthMaxReady = true
    end
  end
  if hpSecret
    or bar._msufHealthValue ~= hp
    or bar._msufHealthValueUnit ~= unit then
    local interp = animate == true and bar._msufSmoothInterp or nil
    if interp then
      bar:SetValue(hp, interp)
      bar._msufInterpolating = true
    else
      bar:SetValue(hp)
      bar._msufInterpolating = nil
    end
  end
  if hpSecret then
    bar._msufHealthValue = nil
    bar._msufHealthValueUnit = nil
  else
    bar._msufHealthValue = hp
    bar._msufHealthValueUnit = unit
  end
  bar._msufHealthPercentValue = nil
  bar._msufHealthPercentUnit = nil
  return hp, maxHP, false, hpSecret, maxSecret
end

local function UpdateAbsolute(frame, event, unit)
  -- UnitHealth/UnitHealthMax may return secret values. Keep these reads as
  -- pure pass-throughs; boolean fallback expressions would inspect the
  -- returned value before UpdateAbsoluteValues can handle it safely.
  local hp = UnitHealth(unit)
  local bar = frame.hpBar
  local refreshMax = event ~= "UNIT_HEALTH"
    or bar._msufHealthMaxReady ~= true
    or bar._msufHealthMaxUnit ~= unit
  local maxHP
  if refreshMax then
    maxHP = UnitHealthMax(unit)
  else
    maxHP = bar._msufHealthMax
  end
  return UpdateAbsoluteValues(frame, unit, hp, maxHP, refreshMax, event == "UNIT_HEALTH")
end

local function NotifyHealthState(frame, event, unit, hp, hpSecret)
  local group = frame._msufIsGroupFrame == true
  if group ~= true then
    -- Single-frame status owns UNIT_CONNECTION directly. Its health handoff is
    -- only the missing DEAD/GHOST boundary, so reject every other event before
    -- doing secret/type work on the steady-state route.
    if event ~= "UNIT_HEALTH" or not frame._msufUpdateStatusTextIndicator then return end
  elseif event ~= "UNIT_HEALTH" and event ~= "UNIT_CONNECTION" then
    return
  end
  if hpSecret == nil then hpSecret = issecretvalue(hp) == true end
  local seedHP = hpSecret ~= true and type(hp) == "number" and hp or nil
  local transitionNeeded = false
  if frame._msufStatusTextHealthRefresh ~= true then
    local value = frame._msufStatusTextValue
    if value == "DEAD" or value == "GHOST" or value == "OFFLINE" then
      -- Secret health still rechecks a visible gone label so resurrection and
      -- reconnect transitions remain authoritative.
      transitionNeeded = hpSecret == true or seedHP == nil or seedHP > 0
    elseif hpSecret ~= true and seedHP ~= nil and seedHP <= 0 then
      transitionNeeded = true
    end
  end
  local updateStatus
  if group then
    local groupStatus = frame._msufUpdateGroupStatusState
    if groupStatus and (event == "UNIT_CONNECTION" or transitionNeeded) then
      updateStatus = groupStatus
    end
  elseif transitionNeeded then
    updateStatus = frame._msufUpdateStatusTextIndicator
  end
  if updateStatus then
    frame._msufHealthStateNotify = true
    updateStatus(frame, event, unit, seedHP)
    frame._msufHealthStateNotify = nil
  end
  local updateGoneState = group and frame._msufUpdateGroupVisualsGoneState or nil
  if updateGoneState then
    updateGoneState(frame, event, unit, seedHP)
  end
end

local function UpdateTextureLayerHealthState(update, frame, unit, hp, maxHP)
  if frame._msufTexLayerHealthColorMask
    and frame._msufHealthRuntimeGradient == true and frame._msufHealthStatusGone ~= true then
    return update(frame, unit, hp, maxHP,
      frame._msufGradStashR, frame._msufGradStashG, frame._msufGradStashB)
  end
  return update(frame, unit, hp, maxHP)
end

local function UpdateSingle(frame, event, unit)
  unit = unit or frame.MSUFUnitKey
  local rt = frame and frame._msufTextRuntime
  if rt and rt._dispatchHealthPercentReady == true then
    rt._dispatchHealthPercent = nil
    rt._dispatchHealthPercentReady = nil
  end
  if not (frame and frame.hpBar and unit) then return end

  local ok, pct, maxValue, percentReady, pctSecret = UpdatePercent(frame, unit, event == "UNIT_HEALTH")
  if ok then
    if frame._msufHealthRuntimeColorEnabled ~= false
      and (event ~= "UNIT_HEALTH" or IDENTITY_EVENTS[event] == true or RuntimeColorOnHealthEvent(frame, pct, pctSecret)) then
      if not ApplyRuntimeColor(frame, event, unit, pct, 100) then SetColor(frame) end
    end
    local updateTextureState = frame._msufTexLayerHealthUpdate
    if updateTextureState then
      UpdateTextureLayerHealthState(updateTextureState, frame, unit, pct, 100)
    end
    if frame._msufUpdateStatusTextIndicator then
      NotifyHealthState(frame, event, unit, pct, pctSecret)
    end
    return pct, maxValue, percentReady
  end

  local hp, maxHP, absolutePercentReady, hpSecret = UpdateAbsolute(frame, event, unit)
  if frame._msufHealthRuntimeColorEnabled ~= false
    and (event ~= "UNIT_HEALTH" or IDENTITY_EVENTS[event] == true or RuntimeColorOnHealthEvent(frame, hp, hpSecret)) then
    if not ApplyRuntimeColor(frame, event, unit, hp, maxHP) then SetColor(frame) end
  end
  local updateTextureState = frame._msufTexLayerHealthUpdate
  if updateTextureState then
    UpdateTextureLayerHealthState(updateTextureState, frame, unit, hp, maxHP)
  end
  if frame._msufUpdateStatusTextIndicator then
    NotifyHealthState(frame, event, unit, hp, hpSecret)
  end
  return hp, maxHP, absolutePercentReady
end

local function UpdateSingleAbsolute(frame, event, unit)
  unit = unit or frame.MSUFUnitKey
  local rt = frame and frame._msufTextRuntime
  if rt and rt._dispatchHealthPercentReady == true then
    rt._dispatchHealthPercent = nil
    rt._dispatchHealthPercentReady = nil
  end
  if not (frame and frame.hpBar and unit) then return end

  local hp, maxHP, percentReady, hpSecret = UpdateAbsolute(frame, event, unit)
  if frame._msufHealthRuntimeColorEnabled ~= false
    and (event ~= "UNIT_HEALTH" or IDENTITY_EVENTS[event] == true or RuntimeColorOnHealthEvent(frame, hp, hpSecret)) then
    if not ApplyRuntimeColor(frame, event, unit, hp, maxHP) then SetColor(frame) end
  end
  local updateTextureState = frame._msufTexLayerHealthUpdate
  if updateTextureState then
    UpdateTextureLayerHealthState(updateTextureState, frame, unit, hp, maxHP)
  end
  if frame._msufUpdateStatusTextIndicator then
    NotifyHealthState(frame, event, unit, hp, hpSecret)
  end
  return hp, maxHP, percentReady
end

local function UpdateSingleCurrent(frame, event, unit)
  unit = unit or frame.MSUFUnitKey
  local rt = frame and frame._msufTextRuntime
  if rt and rt._dispatchHealthPercentReady == true then
    rt._dispatchHealthPercent = nil
    rt._dispatchHealthPercentReady = nil
  end
  if not (frame and frame.hpBar and unit) then return end

  -- CURRENT-only text can share UnitHealth with the bar. UnitHealthMax is
  -- retained by the absolute bar path between its own invalidation events, so
  -- steady health ticks avoid the extra UnitHealthPercent call entirely.
  local hp, maxHP, _, hpSecret = UpdateAbsolute(frame, event, unit)
  if frame._msufHealthRuntimeColorEnabled ~= false
    and (event ~= "UNIT_HEALTH" or IDENTITY_EVENTS[event] == true or RuntimeColorOnHealthEvent(frame, hp, hpSecret)) then
    if not ApplyRuntimeColor(frame, event, unit, hp, maxHP) then SetColor(frame) end
  end
  local updateTextureState = frame._msufTexLayerHealthUpdate
  if updateTextureState then
    UpdateTextureLayerHealthState(updateTextureState, frame, unit, hp, maxHP)
  end
  if frame._msufUpdateStatusTextIndicator then
    NotifyHealthState(frame, event, unit, hp, hpSecret)
  end
  return hp, nil, false
end

local function UpdateGroup(frame, event, unit)
  unit = unit or frame.MSUFUnitKey
  local rt = frame and frame._msufTextRuntime
  if rt and rt._dispatchHealthPercentReady == true then
    rt._dispatchHealthPercent = nil
    rt._dispatchHealthPercentReady = nil
  end
  if not (frame and frame.hpBar and unit) then return end

  local ok, pct, maxValue, percentReady, pctSecret = UpdatePercent(frame, unit, event == "UNIT_HEALTH")
  if ok then
    if frame._msufHealthRuntimeColorEnabled ~= false
      and (event ~= "UNIT_HEALTH" or IDENTITY_EVENTS[event] == true or RuntimeColorOnHealthEvent(frame, pct, pctSecret)) then
      if not ApplyRuntimeColor(frame, event, unit, pct, 100) then SetColor(frame) end
    end
    NotifyHealthState(frame, event, unit, pct, pctSecret)
    return pct, maxValue, percentReady
  end

  local hp, maxHP, absolutePercentReady, hpSecret = UpdateAbsolute(frame, event, unit)
  if frame._msufHealthRuntimeColorEnabled ~= false
    and (event ~= "UNIT_HEALTH" or IDENTITY_EVENTS[event] == true or RuntimeColorOnHealthEvent(frame, hp, hpSecret)) then
    if not ApplyRuntimeColor(frame, event, unit, hp, maxHP) then SetColor(frame) end
  end
  NotifyHealthState(frame, event, unit, hp, hpSecret)
  return hp, maxHP, absolutePercentReady
end

-- Group percent bar with zero health-text consumers: the single-pass lane.
-- UpdatePercent, the runtime-color gate, and the steady-state half of
-- NotifyHealthState are folded into one function so a group UNIT_HEALTH tick
-- runs without text-runtime handshakes or helper-call boundaries. Behaviour is
-- identical to UpdateGroup for a frame whose text runtime has no health slots;
-- SelectGroupHealthUpdater swaps back to UpdateGroup the moment slots appear.
local function UpdateGroupPercentLean(frame, event, unit)
  unit = unit or frame.MSUFUnitKey
  local bar = frame and frame.hpBar
  if not (bar and unit) then return end
  if not (UnitHealthPercent and SCALE_100) then
    return UpdateGroup(frame, event, unit)
  end

  local pct = UnitHealthPercent(unit, true, SCALE_100)
  local secret = issecretvalue(pct) == true
  if not secret and (type(pct) ~= "number" or pct ~= pct or (pct - pct) ~= 0) then pct = 0 end
  if bar._msufMinMax ~= 100 then
    bar:SetMinMaxValues(0, 100)
    bar._msufMinMax = 100
  end
  if secret
    or bar._msufHealthPercentValue ~= pct
    or bar._msufHealthPercentUnit ~= unit then
    local interp = event == "UNIT_HEALTH" and bar._msufSmoothInterp or nil
    if interp then
      bar:SetValue(pct, interp)
      bar._msufInterpolating = true
    else
      bar:SetValue(pct)
      bar._msufInterpolating = nil
    end
    if secret then
      bar._msufHealthPercentValue = nil
      bar._msufHealthPercentUnit = nil
    else
      bar._msufHealthPercentValue = pct
      bar._msufHealthPercentUnit = unit
    end
  end

  -- UNIT_HEALTH text writers are deferred dirty markers and immediately
  -- discard dispatch payloads. For the common alive/static-color member there
  -- is likewise no status or dead-background consumer, so finish at the bar
  -- write instead of entering the generic color/status handoff. Identity,
  -- connection, gradient, gone-state, and smoothing semantics above remain
  -- unchanged.
  if event == "UNIT_HEALTH"
    and frame._msufHealthRuntimeGradient ~= true
    and frame._msufHealthStatusGone ~= true
    and frame._msufStatusTextValue == nil
    and frame._msufStatusTextHealthRefresh ~= true
    and frame._msufUpdateGroupVisualsGoneState == nil
    and (secret or pct > 0) then
    return pct, nil, true
  end

  if frame._msufHealthRuntimeColorEnabled ~= false
    and (event ~= "UNIT_HEALTH" or IDENTITY_EVENTS[event] == true or RuntimeColorOnHealthEvent(frame, pct, secret)) then
    if not ApplyRuntimeColor(frame, event, unit, pct, 100) then SetColor(frame) end
  end

  -- Steady alive tick with a plain percent and no visible gone label feeds the
  -- gone-state sink directly; every other case keeps the full notify contract.
  if event == "UNIT_HEALTH"
    and not secret
    and pct > 0
    and frame._msufStatusTextValue == nil
    and frame._msufStatusTextHealthRefresh ~= true then
    local goneState = frame._msufUpdateGroupVisualsGoneState
    if goneState then goneState(frame, event, unit, pct) end
  else
    NotifyHealthState(frame, event, unit, pct, secret)
  end
  return pct, nil, true
end

local HEALTH_PLAN_PERCENT = 1
local HEALTH_PLAN_CURRENT = 2
local HEALTH_PLAN_ABSOLUTE = 3

local function HealthValuePlan(frame)
  local rt = frame and frame._msufTextRuntime
  if not (rt and (rt.healthSlotCount or 0) > 0) then return HEALTH_PLAN_PERCENT end
  if rt.healthNeedsCurrent == true and rt.healthNeedsMax == true then
    return HEALTH_PLAN_ABSOLUTE
  end
  -- CURRENT can share the bar's UnitHealth read only when no active text
  -- component (including health-based text color) still needs a percentage.
  -- CURPERCENT therefore stays on the percent path and preserves two native
  -- reads instead of adding an initial UnitHealthMax lookup.
  if rt.healthNeedsCurrent == true
    and rt.healthNeedsPercent ~= true
    and rt.healthColorByHealth ~= true then
    return HEALTH_PLAN_CURRENT
  end
  return HEALTH_PLAN_PERCENT
end

local function UpdateColorOnly(frame, event, unit)
  if not (frame and frame.hpBar) then return end
  local frameUnit = frame.MSUFUnitKey
  if unit ~= nil and issecretvalue(unit) ~= true and unit ~= frameUnit then return end
  if not ApplyRuntimeColor(frame, event, frameUnit) then
    SetColor(frame)
  end
end

local function UpdateIdentityBackground(frame)
  local health = frame and frame.MSUFSpec and frame.MSUFSpec.health
  if not (health and health.backgroundClassColor == true and ApplyBackgrounds) then return false end
  ApplyBackgrounds(frame, true, false)
  return true
end

function Health.Update(frame, event, unit)
  -- Core installs UpdateGroup/UpdateSingle directly through SelectUpdate, so
  -- event hot paths stay branch-free. Preserve the public update contract for
  -- direct callers and compatibility paths that have a group frame.
  if frame and frame._msufIsGroupFrame == true then
    return UpdateGroup(frame, event, unit)
  end
  local plan = HealthValuePlan(frame)
  if plan == HEALTH_PLAN_ABSOLUTE then return UpdateSingleAbsolute(frame, event, unit) end
  if plan == HEALTH_PLAN_CURRENT then return UpdateSingleCurrent(frame, event, unit) end
  return UpdateSingle(frame, event, unit)
end

function Health.SelectUpdate(frame, spec)
  if (spec and spec.scope == "group") or (frame and frame._msufIsGroupFrame == true) then
    -- No health-text consumers -> the folded single-pass lane. Any text slot,
    -- percent need, or health-driven text color keeps the generic group path
    -- that owns the text-runtime percent handshake.
    local rt = frame and frame._msufTextRuntime
    if rt == nil
      or ((rt.healthSlotCount or 0) == 0
        and rt.healthColorByHealth ~= true
        and rt.healthNeedsPercent ~= true) then
      return UpdateGroupPercentLean
    end
    return UpdateGroup
  end
  local plan = HealthValuePlan(frame)
  if plan == HEALTH_PLAN_ABSOLUTE then return UpdateSingleAbsolute end
  if plan == HEALTH_PLAN_CURRENT then return UpdateSingleCurrent end
  return UpdateSingle
end

function Health.SelectEventUpdate(_frame, spec, event)
  -- Group health text uses a shared deferred drain on UNIT_HEALTH, so the
  -- generic UpdateGroup dispatch-percent handshake is dead work on that event.
  -- Reuse the same folded bar path already used by text-free Raid/Mythic
  -- frames; cold max/connection/identity events retain the full updater.
  if event == "UNIT_HEALTH" and spec and spec.scope == "group" then
    return UpdateGroupPercentLean
  end
  -- UNIT_FLAGS changes dead/ghost/AFK/DND status, not the health value. The
  -- color resolver performs the exact status and (for gradient mode) native
  -- curve reads it needs, so a second UnitHealthPercent + StatusBar write is
  -- redundant here.
  if COLOR_ONLY_EVENTS[event] == true then
    return UpdateColorOnly
  end
  return nil
end

Health.UpdateValue = Health.Update
Health.UpdateValuePlain = Health.Update
Health.UpdateValueStatic = Health.Update
Health.UpdateValueStaticPlain = Health.Update
Health.UpdateValueGroupStatic = UpdateGroup
Health.UpdateValueGroupPercent = UpdateGroup
Health.UpdateValueGroupPercentLean = UpdateGroupPercentLean
-- Static implementations are exposed on the element descriptor so Core can
-- safely intern direct route prototypes without retaining frame-owned closures.
Health.UpdateValueSinglePercent = UpdateSingle
Health.UpdateValueSingleCurrent = UpdateSingleCurrent
Health.UpdateValueSingleAbsolute = UpdateSingleAbsolute
Health.UpdateValuePercent = Health.Update
Health.UpdateMaxValue = Health.Update
Health.UpdateMaxValuePlain = Health.Update
Health.UpdateMaxValueStatic = Health.Update
Health.UpdateMaxValueStaticPlain = Health.Update
Health.UpdateConnectionState = Health.Update
Health.UpdateIdentityColor = Health.Update
Health.UpdateIdentityBackground = UpdateIdentityBackground
function Health.SelectGroupHealthUpdater(frame)
  if not frame then return nil end
  local update = Health.SelectUpdate(frame, frame.MSUFSpec)
  local updateKey = UF._updateKeys and UF._updateKeys.Health
  if updateKey and frame._msufActiveElements and frame._msufActiveElements.Health == true then
    if frame[updateKey] ~= update then
      local bar = frame.hpBar
      if bar then
        bar._msufHealthValue = nil
        bar._msufHealthValueUnit = nil
        bar._msufHealthMax = nil
        bar._msufHealthMaxUnit = nil
        bar._msufHealthMaxReady = nil
        bar._msufHealthPercentValue = nil
        bar._msufHealthPercentUnit = nil
      end
    end
    frame[updateKey] = update
  end
  return update
end

function Health.RefreshColor(frameOrUnit, event)
  local frame = frameOrUnit
  if type(frameOrUnit) == "string" then
    frame = UF.frames and UF.frames[frameOrUnit]
  end
  if not (frame and frame.hpBar) then return false end
  if ApplyRuntimeColor(frame, event or "MSUF_COLOR_CHANGE", frame.MSUFUnitKey) then
    return true
  end
  SetColor(frame, true)
  return true
end

ExportPublic("MSUF_UFCore_RefreshHealthBarColor", Health.RefreshColor)

UF.RegisterElement("Health", Health)
