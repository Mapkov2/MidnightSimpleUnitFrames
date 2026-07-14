local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}

local C = MSUF.UFBarTextCommon
local UF = C and C.UF or MSUF.UF
if not UF then return end

local CreateFrame = C and C.CreateFrame or CreateFrame
local UnitHealth = C and C.UnitHealth or UnitHealth
local UnitHealthMax = C and C.UnitHealthMax or UnitHealthMax
local UnitHealthPercent = C and C.UnitHealthPercent or UnitHealthPercent
local UnitInPartyIsAI = _G.UnitInPartyIsAI
local WHITE = C and C.WHITE or "Interface\\Buttons\\WHITE8X8"
local SCALE_100 = C and C.SCALE_100
local SetBarSmoothing = C and C.SetBarSmoothing
local ApplyHealthStatusColor = C and C.ApplyHealthStatusColor
local ApplyBarGradient = C and C.ApplyBarGradient
local issecretvalue = _G.issecretvalue or function(_) return false end
local ExportPublic = MSUF.ExportPublic or function(name, value)
  _G[name] = value
  return value
end

local Health = {}
local EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION" }
local STATUS_COLOR_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION", "UNIT_FLAGS" }
local PLAYER_STATUS_COLOR_EVENTS = { "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }
local GROUP_LIFECYCLE_EVENTS = { "PARTY_MEMBER_ENABLE", "PARTY_MEMBER_DISABLE" }
local GROUP_LIFECYCLE_EVENT = {
  PARTY_MEMBER_ENABLE = true,
  PARTY_MEMBER_DISABLE = true,
}
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

local function RuntimeColorOnHealthEvent(frame, value)
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
  if issecretvalue(value) == true then
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
  local mode = h and h.mode
  frame._msufHealthRuntimeColorEnabled = mode ~= "dark" and mode ~= "unified"
  frame._msufHealthRuntimeGradient = mode == "gradient"
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
  if ApplyBarGradient then ApplyBarGradient(frame, frame.hpBar, h and h.barGradient, "hpGradients") end
  SetColor(frame, true)
  ApplyRuntimeColor(frame, "MSUF_COLOR_CHANGE", frame.unit)
end

function Health.GetEvents(frame, spec)
  return RuntimeColorEnabledForSpec(spec) and STATUS_COLOR_EVENTS or EVENTS
end

function Health.GetUnitlessEvents(frame, spec)
  if spec and spec.scope == "group" then
    return GROUP_LIFECYCLE_EVENTS
  end
  if frame and frame.unit == "player" and RuntimeColorEnabledForSpec(spec) then
    return PLAYER_STATUS_COLOR_EVENTS
  end
  return nil
end

local function UpdatePercent(frame, unit)
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
  if secret or bar._msufHealthPercentValue ~= pct then
    local interp = bar._msufSmoothInterp
    if interp then
      bar:SetValue(pct, interp)
      bar._msufInterpolating = true
    else
      bar:SetValue(pct)
    end
    if secret then
      bar._msufHealthPercentValue = nil
    else
      bar._msufHealthPercentValue = pct
    end
  end
  bar._msufHealthValue = nil
  bar._msufHealthValueUnit = nil
  bar._msufHealthMax = nil
  bar._msufHealthMaxUnit = nil
  bar._msufHealthMaxReady = nil
  local rt = frame._msufTextRuntime
  if rt and (rt.healthNeedsPercent == true or rt.healthColorByHealth == true) then
    rt._dispatchHealthPercent = pct
    rt._dispatchHealthPercentReady = true
  end
  return true, pct, nil, true
end

local function UpdateAbsoluteValues(frame, unit, hp, maxHP)
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
  if maxSecret or bar._msufMinMax ~= maxHP then
    bar:SetMinMaxValues(0, maxHP)
    if maxSecret then
      bar._msufMinMax = nil
    else
      bar._msufMinMax = maxHP
    end
  end
  if hpSecret
    or bar._msufHealthValue ~= hp
    or bar._msufHealthValueUnit ~= unit then
    local interp = bar._msufSmoothInterp
    if interp then
      bar:SetValue(hp, interp)
      bar._msufInterpolating = true
    else
      bar:SetValue(hp)
    end
  end
  if hpSecret then
    bar._msufHealthValue = nil
    bar._msufHealthValueUnit = nil
  else
    bar._msufHealthValue = hp
    bar._msufHealthValueUnit = unit
  end
  if maxSecret then
    bar._msufHealthMax = nil
    bar._msufHealthMaxUnit = nil
    bar._msufHealthMaxReady = nil
  else
    bar._msufHealthMax = maxHP
    bar._msufHealthMaxUnit = unit
    bar._msufHealthMaxReady = true
  end
  bar._msufHealthPercentValue = nil
  return hp, maxHP, false
end

local function UpdateAbsolute(frame, unit)
  -- UnitHealth/UnitHealthMax may return secret values. Keep these reads as
  -- pure pass-throughs; boolean fallback expressions would inspect the
  -- returned value before UpdateAbsoluteValues can handle it safely.
  local hp = UnitHealth(unit)
  local maxHP = UnitHealthMax(unit)
  return UpdateAbsoluteValues(frame, unit, hp, maxHP)
end

local function RefreshGroupAIHealthMode(frame, unit)
  if not (frame and frame._msufIsGroupFrame == true) then
    return false, false
  end
  if not UnitInPartyIsAI then return false, true end
  local oldUnit = frame._msufHealthAIUnit
  local oldAI = frame._msufHealthAI
  local isAI = UnitInPartyIsAI(unit) == true
  local changed = oldUnit ~= unit or oldAI ~= isAI
  if changed then
    frame._msufHealthAIUnit = unit
    frame._msufHealthAI = isAI
  end
  return isAI, changed
end

local function NeedsGroupAIRefresh(frame, event, unit)
  return (GROUP_LIFECYCLE_EVENT[event] == true and frame._msufGroupLifecycleAIMetadataReady ~= true)
    or IDENTITY_EVENTS[event] == true
    or frame._msufHealthAIUnit ~= unit
end

local function HealthStatusTransitionNeeded(frame, seedHP)
  if seedHP == nil or frame._msufStatusTextHealthRefresh == true then
    return false
  end
  local value = frame._msufStatusTextValue
  if value == "DEAD" or value == "GHOST" or value == "OFFLINE" then
    return seedHP > 0
  end
  return seedHP <= 0
end

local function NotifyHealthState(frame, event, unit, hp)
  local group = frame._msufIsGroupFrame == true
  if group ~= true then
    -- Single-frame status owns UNIT_CONNECTION directly. Its health handoff is
    -- only the missing DEAD/GHOST boundary, so reject every other event before
    -- doing secret/type work on the steady-state route.
    if event ~= "UNIT_HEALTH" or not frame._msufUpdateStatusTextIndicator then return end
  elseif event ~= "UNIT_HEALTH" and event ~= "UNIT_CONNECTION" then
    return
  end
  local seedHP = issecretvalue(hp) ~= true and type(hp) == "number" and hp or nil
  local updateStatus
  if group then
    local groupStatus = frame._msufUpdateGroupStatusState
    if groupStatus and (event == "UNIT_CONNECTION" or HealthStatusTransitionNeeded(frame, seedHP)) then
      updateStatus = groupStatus
    end
  elseif HealthStatusTransitionNeeded(frame, seedHP) then
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

local function UpdateSingle(frame, event, unit)
  unit = unit or frame.unit
  local rt = frame and frame._msufTextRuntime
  if rt and rt._dispatchHealthPercentReady == true then
    rt._dispatchHealthPercent = nil
    rt._dispatchHealthPercentReady = nil
  end
  if not (frame and frame.hpBar and unit) then return end

  local ok, pct, maxValue, percentReady = UpdatePercent(frame, unit)
  if ok then
    if event ~= "UNIT_HEALTH" or IDENTITY_EVENTS[event] == true or RuntimeColorOnHealthEvent(frame, pct) then
      if not ApplyRuntimeColor(frame, event, unit, pct, 100) then SetColor(frame) end
    end
    NotifyHealthState(frame, event, unit, pct)
    return pct, maxValue, percentReady
  end

  local hp, maxHP, absolutePercentReady = UpdateAbsolute(frame, unit)
  if event ~= "UNIT_HEALTH" or IDENTITY_EVENTS[event] == true or RuntimeColorOnHealthEvent(frame, hp) then
    if not ApplyRuntimeColor(frame, event, unit, hp, maxHP) then SetColor(frame) end
  end
  NotifyHealthState(frame, event, unit, hp)
  return hp, maxHP, absolutePercentReady
end

local function UpdateSingleAbsolute(frame, event, unit)
  unit = unit or frame.unit
  local rt = frame and frame._msufTextRuntime
  if rt and rt._dispatchHealthPercentReady == true then
    rt._dispatchHealthPercent = nil
    rt._dispatchHealthPercentReady = nil
  end
  if not (frame and frame.hpBar and unit) then return end

  local hp, maxHP, percentReady = UpdateAbsolute(frame, unit)
  if event ~= "UNIT_HEALTH" or IDENTITY_EVENTS[event] == true or RuntimeColorOnHealthEvent(frame, hp) then
    if not ApplyRuntimeColor(frame, event, unit, hp, maxHP) then SetColor(frame) end
  end
  NotifyHealthState(frame, event, unit, hp)
  return hp, maxHP, percentReady
end

local function UpdateSingleCurrent(frame, event, unit)
  unit = unit or frame.unit
  local rt = frame and frame._msufTextRuntime
  if rt and rt._dispatchHealthPercentReady == true then
    rt._dispatchHealthPercent = nil
    rt._dispatchHealthPercentReady = nil
  end
  if not (frame and frame.hpBar and unit) then return end

  local ok, pct = UpdatePercent(frame, unit)
  if not ok then return UpdateSingleAbsolute(frame, event, unit) end
  if event ~= "UNIT_HEALTH" or IDENTITY_EVENTS[event] == true or RuntimeColorOnHealthEvent(frame, pct) then
    if not ApplyRuntimeColor(frame, event, unit, pct, 100) then SetColor(frame) end
  end
  -- CURRENT without MAX is a distinct compiled plan: keep the bar on the
  -- native percent API and read only the one absolute value the text needs.
  local hp = UnitHealth(unit)
  NotifyHealthState(frame, event, unit, hp)
  return hp, nil, false
end

local function UpdateGroup(frame, event, unit)
  unit = unit or frame.unit
  local rt = frame and frame._msufTextRuntime
  if rt and rt._dispatchHealthPercentReady == true then
    rt._dispatchHealthPercent = nil
    rt._dispatchHealthPercentReady = nil
  end
  if not (frame and frame.hpBar and unit) then return end

  if NeedsGroupAIRefresh(frame, event, unit) then
    RefreshGroupAIHealthMode(frame, unit)
  end

  if frame._msufHealthAI == true then
    local readDetailed = UF.ReadDetailedHealth
    if readDetailed then
      local detailedHP, detailedMax = readDetailed(frame, unit)
      local hpAvailable = issecretvalue(detailedHP) == true or detailedHP ~= nil
      local maxAvailable = issecretvalue(detailedMax) == true or detailedMax ~= nil
      if hpAvailable and maxAvailable then
        local hp, maxHP, percentReady = UpdateAbsoluteValues(frame, unit, detailedHP, detailedMax)
        if not ApplyRuntimeColor(frame, event, unit, hp, maxHP) then SetColor(frame) end
        NotifyHealthState(frame, event, unit, hp)
        return hp, maxHP, percentReady
      end
    end
  end

  local ok, pct, maxValue, percentReady = UpdatePercent(frame, unit)
  if ok then
    if event ~= "UNIT_HEALTH" or IDENTITY_EVENTS[event] == true or RuntimeColorOnHealthEvent(frame, pct) then
      if not ApplyRuntimeColor(frame, event, unit, pct, 100) then SetColor(frame) end
    end
    NotifyHealthState(frame, event, unit, pct)
    return pct, maxValue, percentReady
  end

  local hp, maxHP, absolutePercentReady = UpdateAbsolute(frame, unit)
  if event ~= "UNIT_HEALTH" or IDENTITY_EVENTS[event] == true or RuntimeColorOnHealthEvent(frame, hp) then
    if not ApplyRuntimeColor(frame, event, unit, hp, maxHP) then SetColor(frame) end
  end
  NotifyHealthState(frame, event, unit, hp)
  return hp, maxHP, absolutePercentReady
end

local function UpdateGroupAbsolute(frame, event, unit)
  unit = unit or frame.unit
  local rt = frame and frame._msufTextRuntime
  if rt and rt._dispatchHealthPercentReady == true then
    rt._dispatchHealthPercent = nil
    rt._dispatchHealthPercentReady = nil
  end
  if not (frame and frame.hpBar and unit) then return end

  if NeedsGroupAIRefresh(frame, event, unit) then
    RefreshGroupAIHealthMode(frame, unit)
  end

  if frame._msufHealthAI == true then
    local readDetailed = UF.ReadDetailedHealth
    if readDetailed then
      local detailedHP, detailedMax = readDetailed(frame, unit)
      local hpAvailable = issecretvalue(detailedHP) == true or detailedHP ~= nil
      local maxAvailable = issecretvalue(detailedMax) == true or detailedMax ~= nil
      if hpAvailable and maxAvailable then
        local hp, maxHP, percentReady = UpdateAbsoluteValues(frame, unit, detailedHP, detailedMax)
        if not ApplyRuntimeColor(frame, event, unit, hp, maxHP) then SetColor(frame) end
        NotifyHealthState(frame, event, unit, hp)
        return hp, maxHP, percentReady
      end
    end
  end

  local hp, maxHP, percentReady = UpdateAbsolute(frame, unit)
  if event ~= "UNIT_HEALTH" or IDENTITY_EVENTS[event] == true or RuntimeColorOnHealthEvent(frame, hp) then
    if not ApplyRuntimeColor(frame, event, unit, hp, maxHP) then SetColor(frame) end
  end
  NotifyHealthState(frame, event, unit, hp)
  return hp, maxHP, percentReady
end

local function UpdateGroupCurrent(frame, event, unit)
  unit = unit or frame.unit
  local rt = frame and frame._msufTextRuntime
  if rt and rt._dispatchHealthPercentReady == true then
    rt._dispatchHealthPercent = nil
    rt._dispatchHealthPercentReady = nil
  end
  if not (frame and frame.hpBar and unit) then return end

  if NeedsGroupAIRefresh(frame, event, unit) then
    RefreshGroupAIHealthMode(frame, unit)
  end

  if frame._msufHealthAI == true then
    local readDetailed = UF.ReadDetailedHealth
    if readDetailed then
      local detailedHP, detailedMax = readDetailed(frame, unit)
      local hpAvailable = issecretvalue(detailedHP) == true or detailedHP ~= nil
      local maxAvailable = issecretvalue(detailedMax) == true or detailedMax ~= nil
      if hpAvailable and maxAvailable then
        local hp, maxHP, percentReady = UpdateAbsoluteValues(frame, unit, detailedHP, detailedMax)
        if not ApplyRuntimeColor(frame, event, unit, hp, maxHP) then SetColor(frame) end
        NotifyHealthState(frame, event, unit, hp)
        return hp, maxHP, percentReady
      end
    end
  end

  local ok, pct = UpdatePercent(frame, unit)
  if not ok then return UpdateGroupAbsolute(frame, event, unit) end
  if event ~= "UNIT_HEALTH" or IDENTITY_EVENTS[event] == true or RuntimeColorOnHealthEvent(frame, pct) then
    if not ApplyRuntimeColor(frame, event, unit, pct, 100) then SetColor(frame) end
  end
  local hp = UnitHealth(unit)
  NotifyHealthState(frame, event, unit, hp)
  return hp, nil, false
end

local HEALTH_PLAN_PERCENT = 1
local HEALTH_PLAN_CURRENT = 2
local HEALTH_PLAN_ABSOLUTE = 3

local function HealthValuePlan(frame)
  if frame and frame._msufPredictionNeedsHealth == true then
    return HEALTH_PLAN_ABSOLUTE
  end
  local rt = frame and frame._msufTextRuntime
  if not (rt and (rt.healthSlotCount or 0) > 0) then return HEALTH_PLAN_PERCENT end
  if rt.healthNeedsMissing == true
    or (rt.healthNeedsCurrent == true and rt.healthNeedsMax == true) then
    return HEALTH_PLAN_ABSOLUTE
  end
  if rt.healthNeedsCurrent == true then return HEALTH_PLAN_CURRENT end
  return HEALTH_PLAN_PERCENT
end

local function UpdateColorOnly(frame, event, unit)
  if not (frame and frame.hpBar) then return end
  if not ApplyRuntimeColor(frame, event, unit or frame.unit) then
    SetColor(frame)
  end
end

function Health.Update(frame, event, unit)
  -- Core installs UpdateGroup/UpdateSingle directly through SelectUpdate, so
  -- event hot paths stay branch-free. Preserve the public update contract for
  -- direct callers and compatibility paths that have a group frame.
  local plan = HealthValuePlan(frame)
  if frame and frame._msufIsGroupFrame == true then
    if plan == HEALTH_PLAN_ABSOLUTE then return UpdateGroupAbsolute(frame, event, unit) end
    if plan == HEALTH_PLAN_CURRENT then return UpdateGroupCurrent(frame, event, unit) end
    return UpdateGroup(frame, event, unit)
  end
  if plan == HEALTH_PLAN_ABSOLUTE then return UpdateSingleAbsolute(frame, event, unit) end
  if plan == HEALTH_PLAN_CURRENT then return UpdateSingleCurrent(frame, event, unit) end
  return UpdateSingle(frame, event, unit)
end

function Health.SelectUpdate(frame, spec)
  local plan = HealthValuePlan(frame)
  if (spec and spec.scope == "group") or (frame and frame._msufIsGroupFrame == true) then
    if plan == HEALTH_PLAN_ABSOLUTE then return UpdateGroupAbsolute end
    if plan == HEALTH_PLAN_CURRENT then return UpdateGroupCurrent end
    return UpdateGroup
  end
  if plan == HEALTH_PLAN_ABSOLUTE then return UpdateSingleAbsolute end
  if plan == HEALTH_PLAN_CURRENT then return UpdateSingleCurrent end
  return UpdateSingle
end

function Health.SelectEventUpdate(_frame, _spec, event)
  -- UNIT_FLAGS changes dead/ghost/AFK/DND status, not the health value. The
  -- color resolver performs the exact status and (for gradient mode) native
  -- curve reads it needs, so a second UnitHealthPercent + StatusBar write is
  -- redundant here.
  if event == "UNIT_FLAGS" then
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
-- Static implementations are exposed on the element descriptor so Core can
-- safely intern direct route prototypes without retaining frame-owned closures.
Health.UpdateValueSinglePercent = UpdateSingle
Health.UpdateValueSingleCurrent = UpdateSingleCurrent
Health.UpdateValueSingleAbsolute = UpdateSingleAbsolute
Health.UpdateValueGroupCurrent = UpdateGroupCurrent
Health.UpdateValueGroupAbsolute = UpdateGroupAbsolute
Health.UpdateValuePercent = Health.Update
Health.UpdateMaxValue = Health.Update
Health.UpdateMaxValuePlain = Health.Update
Health.UpdateMaxValueStatic = Health.Update
Health.UpdateMaxValueStaticPlain = Health.Update
Health.UpdateConnectionState = Health.Update
Health.UpdateIdentityColor = Health.Update
function Health.UpdateGroupLifecycleMetadata(frame, _event, unit)
  local isAI, changed = RefreshGroupAIHealthMode(frame, unit or (frame and frame.unit))
  -- Detailed AI health/prediction availability is committed by these lifecycle
  -- events. Refresh every active follower, but keep ordinary raid members on
  -- the metadata-only path unless their classification actually changed.
  return isAI == true or changed == true
end
function Health.SelectGroupHealthUpdater(frame)
  if not frame then return nil end
  local update = Health.SelectUpdate(frame, frame.MSUFSpec)
  local updateKey = UF._updateKeys and UF._updateKeys.Health
  if updateKey and frame._msufActiveElements and frame._msufActiveElements.Health == true then
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
  if ApplyRuntimeColor(frame, event or "MSUF_COLOR_CHANGE", frame.unit) then
    return true
  end
  SetColor(frame, true)
  return true
end

ExportPublic("MSUF_UFCore_RefreshHealthBarColor", Health.RefreshColor)

UF.RegisterElement("Health", Health)
