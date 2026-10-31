local _, MSUF = ...
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "MSUF_UF_Elements_Health.lua")

local C = MSUF.UFBarTextCommon
local UF = C.UF
if not UF then return end

local CreateFrame = C.CreateFrame or CreateFrame
local UnitHealth = C.UnitHealth or UnitHealth
local UnitHealthMax = C.UnitHealthMax or UnitHealthMax
local UnitHealthPercent = C.UnitHealthPercent or UnitHealthPercent
local WHITE = C.WHITE or "Interface\\Buttons\\WHITE8X8"
local SCALE_100 = C.SCALE_100
local REVERSE_TO_100 = CurveConstants and CurveConstants.ReverseTo100
local CreateLossTrail = C.CreateLossTrail
local SnapBarInterpolation = C.SnapBarInterpolation
local SetBarSmoothing = C.SetBarSmoothing
local ApplyHealthStatusColor = C.ApplyHealthStatusColor
local ApplyBackgrounds = C.ApplyBackgrounds
local ApplyBarGradient = C.ApplyBarGradient
local PrepareHealthGradientCurve = C.PrepareHealthGradientCurve
local RefreshHealthBarBackgroundColor = MSUF.Require("MSUF_RefreshHealthBarBackgroundColor", "MSUF_UF_Elements_Health.lua")
local RefreshHealthGradientBackground = MSUF.Bars and MSUF.Bars.RefreshHealthGradientBackground
local issecretvalue = issecretvalue
-- UpdateSingle/UpdateGroupPercentLean run per UNIT_HEALTH; keep the finite
-- checks off the global table (Prediction/Group_Visuals do the same).
local type = type
local math_max = math.max
local ExportPublic = MSUF.ExportPublic

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

local function BackgroundColorMode(health)
  local mode = health and health.backgroundColorMode
  if mode == "custom" or mode == "match_health" or mode == "class" or mode == "health_gradient" then
    return mode
  end
  if health and health.backgroundClassColor == true then return "class" end
  if health and health.backgroundMatchHealth == true then return "match_health" end
  return "custom"
end

local function BackgroundRuntimeColorEnabledForSpec(spec)
  local mode = BackgroundColorMode(spec and spec.health)
  return mode == "match_health" or mode == "health_gradient"
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
    or BackgroundRuntimeColorEnabledForSpec(spec)
end

local RuntimeColorNeedsIdentityForSpec = MSUF.UFBarTextCommon.HealthModeNeedsIdentity

local function RuntimeColorOnHealthEvent(frame, value, valueSecret)
  local gradient = frame and frame._msufHealthRuntimeGradient
  if gradient == nil and frame then
    local health = frame.MSUFSpec and frame.MSUFSpec.health
    gradient = health and health.mode == "gradient" or false
  end
  if gradient == true or (frame and frame._msufHealthBackgroundGradient == true) then
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

local function ApplyRuntimeColor(frame, event, unit, hp, maxHP, backgroundForce, backgroundApplied, percentReady)
  local bar = frame and frame.hpBar
  local runtimeEnabled = frame and frame._msufHealthRuntimeColorEnabled
  if runtimeEnabled == nil and frame then
    runtimeEnabled = RuntimeColorEnabled(frame)
  end
  local foregroundApplied = false
  if bar and ApplyHealthStatusColor and runtimeEnabled == true then
    if frame._msufHealthRuntimeGradient == true
      and frame._msufHealthBackgroundGradient == true then
      -- ApplyHealthStatusColor sets a plain freshness sentinel alongside its
      -- potentially secret RGB result. Clear only that sentinel first so the
      -- background cannot reuse a stale alive gradient on a gone-state pass.
      frame._msufGradStashAt = nil
    end
    if issecretvalue(maxHP) ~= true
      and maxHP == nil
      and issecretvalue(hp) ~= true
      and type(hp) == "number" then
      maxHP = 100
    end
    ApplyHealthStatusColor(bar, frame, unit or frame.MSUFUnitKey, hp, maxHP, nil, event, percentReady)
    foregroundApplied = true
  end

  if not backgroundApplied and frame and frame._msufHealthBackgroundColorDynamic == true then
    local refresh = frame._msufHealthBackgroundRefresh or RefreshHealthBarBackgroundColor
    backgroundApplied = refresh(frame, event, unit or frame.MSUFUnitKey, hp, maxHP, nil, backgroundForce, percentReady) == true
  end
  return foregroundApplied or backgroundApplied
end

local function SetHealthBackgroundValue(frame, unit, percent, percentSecret, animate)
  local backgroundBar = frame and frame.healthBackgroundBar
  if not backgroundBar then return false end

  local missing, secret
  if percentSecret == false then
    -- Both percent lanes already sanitized this public sample. Cold/absolute
    -- callers pass nil and use the native inverse below; no stale sample reuse.
    missing = 100 - percent
  elseif UnitHealthPercent and REVERSE_TO_100 and unit then
    missing = UnitHealthPercent(unit, true, REVERSE_TO_100)
    -- An opaque input keeps its inverse opaque: no Lua comparison or caching.
    secret = percentSecret == true or issecretvalue(missing) == true
    if not secret and not IsFiniteNumber(missing) then missing = 0 end
  else
    missing = 0
  end

  if not secret then
    if missing < 0 then missing = 0 elseif missing > 100 then missing = 100 end
  end
  if backgroundBar._msufHealthMissingMinMax ~= 100 then
    backgroundBar:SetMinMaxValues(0, 100)
    backgroundBar._msufHealthMissingMinMax = 100
  end
  if secret
    or backgroundBar._msufHealthMissingValue ~= missing
    or backgroundBar._msufHealthMissingUnit ~= unit then
    local interp = animate == true and frame.hpBar and frame.hpBar._msufSmoothInterp or nil
    if interp then backgroundBar:SetValue(missing, interp) else backgroundBar:SetValue(missing) end
    if secret then
      backgroundBar._msufHealthMissingValue = nil
      backgroundBar._msufHealthMissingUnit = nil
    else
      backgroundBar._msufHealthMissingValue = missing
      backgroundBar._msufHealthMissingUnit = unit
    end
  end
  return true
end

local function LayoutBackgroundFill(backgroundBar, bar, owner, missing, orientation, reverse, topInset)
  backgroundBar:ClearAllPoints()
  if topInset and not missing and topInset > 0 then
    backgroundBar:SetPoint("TOPLEFT", owner, "TOPLEFT", 0, -topInset)
    backgroundBar:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", 0, 0)
  else
    backgroundBar:SetAllPoints(missing and bar or owner)
  end
  if backgroundBar.SetOrientation and backgroundBar._msufOrientation ~= orientation then
    backgroundBar:SetOrientation(orientation)
    backgroundBar._msufOrientation = orientation
  end
  if missing then reverse = not reverse end
  if backgroundBar.SetReverseFill and backgroundBar._msufReverseFill ~= reverse then
    backgroundBar:SetReverseFill(reverse)
    backgroundBar._msufReverseFill = reverse
  end
end
Health.LayoutBackgroundFill = LayoutBackgroundFill

local function ApplyHealthBackgroundFillMode(frame, health)
  local backgroundBar = frame and frame.healthBackgroundBar
  local bar = backgroundBar and frame.hpBar
  if not bar then return false end
  local missing = (health and health.backgroundFillMode) == "missing"
  frame._msufHealthBackgroundFillMissing = missing
  frame._msufHealthBackgroundNeedsValue = missing
  LayoutBackgroundFill(backgroundBar, bar, frame, missing,
    bar._msufOrientation or "HORIZONTAL", bar._msufReverseFill == true)

  if missing then
    -- Keep the missing interval on a native StatusBar for secret-safe values.
    if frame._msufIsGroupFrame == true and SnapBarInterpolation then
      -- A settings/cold apply can arrive while the foreground is still easing.
      -- Finish that old target before the inverse bar is seeded so both native
      -- StatusBars start from one coherent visual state.
      SnapBarInterpolation(bar)
    end
    backgroundBar._msufHealthMissingValue = nil
    backgroundBar._msufHealthMissingUnit = nil
    SetHealthBackgroundValue(frame, frame.MSUFUnitKey, nil, nil, false)
  else
    backgroundBar._msufHealthMissingValue = nil
    backgroundBar._msufHealthMissingUnit = nil
    backgroundBar:SetMinMaxValues(0, 100)
    backgroundBar._msufHealthMissingMinMax = 100
    backgroundBar:SetValue(100)
  end
  if backgroundBar.Show then backgroundBar:Show() end
  return true
end

-- Keep the background's full native UV mapping. A white mask follows the live
-- fill edge, including native interpolation, without a second health read.
-- Absolute and chunked-loss bars retain their distinct value semantics.
local function SyncHealthBackgroundMask(frame, percentPlan, resetValue)
  local bar, background = frame.hpBar, frame.healthBackgroundBar
  if not (bar and background) then return end
  local h = frame.MSUFSpec and frame.MSUFSpec.health
  local orientation = bar._msufOrientation or "HORIZONTAL"
  local reverse = bar._msufReverseFill == true
  -- A full reversed StatusBar reports its leading edge on the far side, so a
  -- clip mask anchored there covers the whole bar and the missing-health color
  -- shows at 100%. The inverse value bar has no edge to misread.
  local wanted = frame._msufHealthBackgroundFillMissing == true and percentPlan
    and not (h and h.chunked == true)
    and not reverse
  local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
  local texture = background.GetStatusBarTexture and background:GetStatusBarTexture()
  local supported = fill and texture and background.CreateMaskTexture
    and texture.AddMaskTexture and texture.RemoveMaskTexture
  -- The rounded surface already owns a mask on this very texture. Stacking a
  -- second native clip mask on it renders the missing-health background wrong
  -- (issue #146), so rounded frames keep the value-driven fill that 6.16 beta1
  -- used. Frames without the rounded surface still take the cheap clip mask.
  local roundedMasked = UF.Surface and UF.Surface.OwnsMask(frame, texture)
  local active = wanted and supported and not roundedMasked and true or false
  if not resetValue and frame._msufHealthBackgroundMaskActive == active
    and frame._msufHealthBackgroundMaskFill == fill
    and frame._msufHealthBackgroundMaskTexture == texture
    and (not active or frame._msufHealthBackgroundMaskOwner == background)
    and frame._msufHealthBackgroundMaskAxis == orientation
    and frame._msufHealthBackgroundMaskReverse == reverse then
    frame._msufHealthBackgroundNeedsValue = frame._msufHealthBackgroundFillMissing == true and not active
    return
  end
  local mask = frame._msufHealthBackgroundClipMask
  local oldTexture = frame._msufHealthBackgroundMaskTexture
  if frame._msufHealthBackgroundMaskActive == true and mask and oldTexture then oldTexture:RemoveMaskTexture(mask) end
  if active then
    if not mask or frame._msufHealthBackgroundMaskOwner ~= background then
      mask = background:CreateMaskTexture(nil, "ARTWORK")
      -- Mask region bounds do not clip white UVs by themselves. Black outside
      -- keeps range-faded health from exposing the full background underneath.
      mask:SetTexture(WHITE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      frame._msufHealthBackgroundClipMask = mask
      frame._msufHealthBackgroundMaskOwner = background
    end
    mask:ClearAllPoints()
    if orientation == "VERTICAL" then
      mask:SetPoint("BOTTOMLEFT", fill, "TOPLEFT", 0, 0)
      mask:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    else
      mask:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
      mask:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    end
    texture:AddMaskTexture(mask)
    background:SetMinMaxValues(0, 100)
    background:SetValue(100)
    background._msufHealthMissingMinMax = 100
    background._msufHealthMissingValue, background._msufHealthMissingUnit = nil, nil
  elseif frame._msufHealthBackgroundMaskActive == true and frame._msufHealthBackgroundFillMissing == true then
    -- Restore the inverse when the clip mask is retired. Capability checks and
    -- mask binding stay in this cold layout/route selection path.
    SetHealthBackgroundValue(frame, frame.MSUFUnitKey, nil, nil, false)
  end
  frame._msufHealthBackgroundMaskActive = active
  frame._msufHealthBackgroundMaskFill, frame._msufHealthBackgroundMaskTexture = fill, texture
  frame._msufHealthBackgroundMaskAxis, frame._msufHealthBackgroundMaskReverse = orientation, reverse
  frame._msufHealthBackgroundNeedsValue = frame._msufHealthBackgroundFillMissing == true and not active
end

function Health.Layout(frame, spec, powerEnabled)
  local bar = frame and frame.hpBar
  if not bar then return end
  spec = spec or frame.MSUFSpec
  local power = spec and spec.power
  if powerEnabled == nil then powerEnabled = power and power.enabled == true end
  local powerInset = 0
  if powerEnabled == true and power and power.embed ~= false and power.detached ~= true then
    powerInset = tonumber(power.height) or 3
    if not IsFiniteNumber(powerInset) or powerInset < 0 then powerInset = 0 end
  end
  local topInset = tonumber(spec and spec.health and spec.health.topInset) or 0
  if not IsFiniteNumber(topInset) or topInset < 0 then topInset = 0 end
  if spec and type(spec.height) == "number" then topInset = math.max(0, math.min(topInset, spec.height - powerInset - 1)) end
  if bar._msufHealthPowerInset == powerInset and bar._msufHealthTopInset == topInset and bar._msufHealthLayoutFrame == frame then return end
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -topInset)
  bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, powerInset)
  bar._msufHealthTopInset = topInset
  bar._msufHealthPowerInset = powerInset
  bar._msufHealthLayoutFrame = frame
end

function Health.Create(frame, spec)
  if frame.hpBar then return end
  local backgroundBar = PixelLayoutRegion(CreateFrame("StatusBar", nil, frame._msufHealthVisualRoot or frame))
  backgroundBar:SetAllPoints(frame)
  backgroundBar:SetMinMaxValues(0, 100)
  backgroundBar:SetValue(100)
  backgroundBar:SetStatusBarTexture((spec and spec.health and spec.health.backgroundTexture)
    or (spec and spec.backgroundTexture) or WHITE)
  if backgroundBar.EnableMouse then backgroundBar:EnableMouse(false) end
  if backgroundBar.SetFrameLevel and frame.GetFrameLevel then
    backgroundBar:SetFrameLevel(frame:GetFrameLevel() or 0)
  end
  local bg = backgroundBar:GetStatusBarTexture()
  if bg.SetDrawLayer then bg:SetDrawLayer("BACKGROUND", -7) end
  bg:SetColorTexture(0.02, 0.02, 0.025, spec and spec.backgroundAlpha or 0.72)
  frame.healthBackgroundBar = backgroundBar
  frame.bg = bg
  frame.hpBarBG = bg
  frame.healthBg = bg

  local trail = CreateLossTrail and CreateLossTrail(frame, (spec and spec.texture) or WHITE, 100) or nil
  local bar = PixelLayoutRegion(CreateFrame("StatusBar", nil, frame._msufHealthVisualRoot or frame))
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
  if frame.healthBackgroundBar and frame.healthBackgroundBar.SetFrameLevel and frame.GetFrameLevel then
    local level = frame:GetFrameLevel() or 0
    if frame.healthBackgroundBar._msufFrameLevel ~= level then
      frame.healthBackgroundBar:SetFrameLevel(level)
      frame.healthBackgroundBar._msufFrameLevel = level
    end
  end
  Health.Layout(frame, spec)
  local trail = frame.healthLossTrail
  frame._msufIsGroupFrame = spec and spec.scope == "group" or nil
  local h = spec and spec.health or nil
  local mode = h and h.mode
  local backgroundColorMode = BackgroundColorMode(h)
  local backgroundGradient = backgroundColorMode == "health_gradient"
  local backgroundDynamic = backgroundGradient or backgroundColorMode == "match_health"
  if (mode == "gradient" or backgroundGradient) and PrepareHealthGradientCurve then
    frame._msufHealthGradientCurve, frame._msufHealthGradientChannels = PrepareHealthGradientCurve(h)
  else
    -- A text-only health gradient lazily seeds this on its next update. Clear
    -- the frame cache on every spec apply so changed colour stops are visible
    -- immediately without rechecking all nine values in the event hot path.
    frame._msufHealthGradientCurve = nil
    frame._msufHealthGradientChannels = nil
  end
  local channels = frame._msufHealthGradientChannels
  frame._msufHealthGradientReadPercent = backgroundGradient and channels and channels.ReadHealthPercent or nil
  frame._msufHealthGradientReadOpaque = backgroundGradient and channels and channels.ReadUnit or nil
  frame._msufHealthRuntimeColorEnabled = mode ~= "dark" and mode ~= "unified"
  frame._msufHealthRuntimeGradient = mode == "gradient"
  frame._msufHealthBackgroundColorMode = backgroundColorMode
  frame._msufHealthBackgroundColorDynamic = backgroundDynamic
  frame._msufHealthBackgroundGradient = backgroundGradient
  frame._msufHealthBackgroundRefresh = backgroundGradient and RefreshHealthGradientBackground
    or RefreshHealthBarBackgroundColor
  frame._msufHealthBackgroundRefreshValue = frame._msufHealthBackgroundRefresh
  frame._msufHealthBgDynamic = backgroundDynamic
  frame._msufHealthRuntimeColorUpdateEnabled = frame._msufHealthRuntimeColorEnabled or backgroundDynamic
  local texture = h and h.texture or spec and spec.texture or WHITE
  SetTexture(frame.hpBar, texture)
  SetTexture(trail, texture)
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
    if trail and trail._msufOrientation ~= orientation then
      trail:SetOrientation(orientation)
      trail._msufOrientation = orientation
      trail._msufReverseFill = nil
    end
  end
  if frame.hpBar.SetReverseFill then
    local reverse = h and h.reverse == true
    if frame.hpBar._msufReverseFill ~= reverse then
      frame.hpBar:SetReverseFill(reverse)
      frame.hpBar._msufReverseFill = reverse
    end
    if trail and trail._msufReverseFill ~= reverse then
      trail:SetReverseFill(reverse)
      trail._msufReverseFill = reverse
    end
  end
  ApplyHealthBackgroundFillMode(frame, h)
  local bar = frame.hpBar
  bar._msufMinMax = nil
  bar._msufHealthValue = nil
  bar._msufHealthMax = nil
  bar._msufHealthValueUnit = nil
  bar._msufHealthMaxUnit = nil
  bar._msufHealthMaxReady = nil
  bar._msufHealthPercentValue = nil
  bar._msufHealthPercentUnit = nil
  if trail then
    trail:SetStatusBarColor(
      h and h.lossR or 1,
      h and h.lossG or 0.55,
      h and h.lossB or 0.08,
      1)
  end
  if SetBarSmoothing then
    SetBarSmoothing(frame.hpBar, h and h.smooth == true, h and h.chunked == true, trail)
  end
  if ApplyBarGradient then ApplyBarGradient(frame, frame.hpBar, h and h.barGradient, "hpGradients") end
  local gloss = h and h.barGloss
  if frame.hpGloss or (gloss and gloss.enabled) then C.ApplyBarGloss(frame, frame.hpBar, gloss, "hpGloss") end
  SetColor(frame, true)
  -- Apply is the authoritative cold path. A secure show/startup transition can
  -- reset the live texture while leaving our last-value cache intact, so never
  -- let that cache suppress the saved background opacity here.
  if ApplyBackgrounds then ApplyBackgrounds(frame, true, false, true) end
  ApplyRuntimeColor(frame, "MSUF_COLOR_CHANGE", frame.MSUFUnitKey, nil, nil, true)
  -- UnitFrames/Engine/MSUF_UF_Factory.lua owns the boss bar geometry and loads
  -- after the elements; a spec applies only once the core has loaded.
  MSUF.Require("ApplyBossPhysicalBarGeometry", "UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua", MSUF.UF.Factory)(frame)
  -- The fill-mode apply seeded the value; reassert the full masked texture
  -- even when this frame's mask and orientation did not change.
  if Health.SyncBackgroundPlan then Health.SyncBackgroundPlan(frame, true) end
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
  local value, maximum, percentReady, hpSecret, maxSecret =
    UpdateAbsoluteValues(frame, unit, hp, maxHP, refreshMax, event == "UNIT_HEALTH")
  if frame._msufHealthBackgroundNeedsValue == true then
    SetHealthBackgroundValue(frame, unit, nil, nil, event == "UNIT_HEALTH")
  end
  return value, maximum, percentReady, hpSecret, maxSecret
end

local function NotifyHealthState(frame, event, unit, hp, hpSecret)
  local group = frame._msufIsGroupFrame == true
  if group ~= true then
    -- Single-frame status owns UNIT_CONNECTION directly. Its health handoff is
    -- only the missing DEAD/GHOST boundary, so reject every other event before
    -- doing secret/type work on the steady-state route.
    if event ~= "UNIT_HEALTH" or not frame._msufUpdateStatusTextIndicator then return end
  elseif event ~= "UNIT_HEALTH" and event ~= "UNIT_CONNECTION" then
    -- UNIT_MAXHEALTH repainted the health colours, the gradient background
    -- included: a gone (dead or offline) background goes back over them.
    if event == "UNIT_MAXHEALTH" and frame._msufGFDeadBgState == true then
      local updateGoneState = frame._msufUpdateGroupVisualsGoneState
      if updateGoneState then
        if hpSecret == nil then hpSecret = issecretvalue(hp) == true end
        updateGoneState(frame, event, unit, hpSecret ~= true and type(hp) == "number" and hp or nil)
      end
    end
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
  if frame._msufSurfaceHealthColor
    and frame._msufHealthRuntimeGradient == true and frame._msufHealthStatusGone ~= true then
    return update(frame, unit, hp, maxHP,
      frame._msufGradStashR, frame._msufGradStashG, frame._msufGradStashB)
  end
  return update(frame, unit, hp, maxHP)
end

-- Client capabilities do not change after these local API references are
-- loaded. Select once instead of carrying the absolute path through every
-- native-percent update. Both variants keep the public handoff contract.
local UpdateSingle
if UnitHealthPercent and SCALE_100 then
  -- hot path: kept whole (perf rule)
  UpdateSingle = function(frame, event, unit, group)
    unit = unit or frame.MSUFUnitKey
    local rt = frame and frame._msufHealthSample
    if rt and rt._dispatchHealthPercentReady == true then
      rt._dispatchHealthPercent = nil
      rt._dispatchHealthPercentReady = nil
    end
    if not (frame and frame.hpBar and unit) then return end
    -- Keep the native percent write and its consumers in one pass. The group
    -- lane below owns its deferred-text contract; this lane must still hand
    -- the very same payload to immediate single-frame text consumers.
    local pct = UnitHealthPercent(unit, true, SCALE_100)
    local pctSecret = issecretvalue(pct) == true
    if not pctSecret and (type(pct) ~= "number" or pct ~= pct or (pct - pct) ~= 0) then pct = 0 end
    local bar = frame.hpBar
    local healthTick = event == "UNIT_HEALTH"
    if bar._msufMinMax ~= 100 then
      bar:SetMinMaxValues(0, 100)
      bar._msufMinMax = 100
    end
    if pctSecret or bar._msufHealthPercentValue ~= pct or bar._msufHealthPercentUnit ~= unit then
      local interp = healthTick and bar._msufSmoothInterp or nil
      if interp then
        bar:SetValue(pct, interp)
        bar._msufInterpolating = true
      else
        bar:SetValue(pct)
        bar._msufInterpolating = nil
      end
      if pctSecret then
        bar._msufHealthPercentValue, bar._msufHealthPercentUnit = nil, nil
      else
        bar._msufHealthPercentValue, bar._msufHealthPercentUnit = pct, unit
      end
    end
    if frame._msufHealthBackgroundNeedsValue == true then
      SetHealthBackgroundValue(frame, unit, pct, pctSecret, healthTick)
    end
    if rt and (not healthTick or frame._msufHealthDeferPercent ~= true)
      and frame._msufHealthPublishPercent == true then
      rt._dispatchHealthPercent, rt._dispatchHealthPercentReady = pct, true
    end

    -- Static foreground + independent gradient background needs one painter,
    -- without the generic foreground/status resolver's intermediate calls.
    -- Apply already makes a gradient background dynamic and enables its color
    -- updates. These two flags fully select this route; do not recheck their
    -- derived flags on every value event.
    if healthTick and frame._msufHealthRuntimeColorEnabled == false
      and frame._msufHealthBackgroundGradient == true then
      local refresh = frame._msufHealthBackgroundRefreshValue or RefreshHealthBarBackgroundColor
      if refresh(frame, event, unit, pct, 100, nil, nil, true, pctSecret) ~= true then SetColor(frame) end
    elseif frame._msufHealthRuntimeColorUpdateEnabled ~= false
      and (not healthTick or RuntimeColorOnHealthEvent(frame, pct, pctSecret)) then
      if not ApplyRuntimeColor(frame, event, unit, pct, 100, nil, nil, true) then SetColor(frame) end
    end
    if group then
      NotifyHealthState(frame, event, unit, pct, pctSecret)
    else
      local updateTextureState = frame._msufSurfaceHealthUpdate
      if updateTextureState then
        UpdateTextureLayerHealthState(updateTextureState, frame, unit, pct, 100)
      end
      -- Reject ordinary alive/opaque ticks before the single-frame notifier.
      -- Visible gone labels and health-refresh owners retain every transition.
      if frame._msufUpdateStatusTextIndicator and (healthTick or frame._msufIsGroupFrame == true)
        and (frame._msufIsGroupFrame == true or frame._msufStatusTextHealthRefresh == true
          or frame._msufStatusTextValue == "DEAD" or frame._msufStatusTextValue == "GHOST"
          or frame._msufStatusTextValue == "OFFLINE" or (not pctSecret and pct <= 0)) then
        NotifyHealthState(frame, event, unit, pct, pctSecret)
      end
    end
    return pct, nil, true
  end
else
  -- hot path: kept whole (perf rule)
  UpdateSingle = function(frame, event, unit, group)
    unit = unit or frame.MSUFUnitKey
    local rt = frame and frame._msufHealthSample
    if rt and rt._dispatchHealthPercentReady == true then
      rt._dispatchHealthPercent = nil
      rt._dispatchHealthPercentReady = nil
    end
    if not (frame and frame.hpBar and unit) then return end
    local hp, maxHP, absolutePercentReady, hpSecret = UpdateAbsolute(frame, event, unit)
    if frame._msufHealthRuntimeColorUpdateEnabled ~= false
      and (event ~= "UNIT_HEALTH" or RuntimeColorOnHealthEvent(frame, hp, hpSecret)) then
      if not ApplyRuntimeColor(frame, event, unit, hp, maxHP) then SetColor(frame) end
    end
    if group then
      NotifyHealthState(frame, event, unit, hp, hpSecret)
    else
      local updateTextureState = frame._msufSurfaceHealthUpdate
      if updateTextureState then
        UpdateTextureLayerHealthState(updateTextureState, frame, unit, hp, maxHP)
      end
      if frame._msufUpdateStatusTextIndicator then
        NotifyHealthState(frame, event, unit, hp, hpSecret)
      end
    end
    return hp, maxHP, absolutePercentReady
  end
end

-- hot path: kept whole (perf rule)
local function UpdateSingleAbsolute(frame, event, unit)
  unit = unit or frame.MSUFUnitKey
  local rt = frame and frame._msufHealthSample
  if rt and rt._dispatchHealthPercentReady == true then
    rt._dispatchHealthPercent = nil
    rt._dispatchHealthPercentReady = nil
  end
  if not (frame and frame.hpBar and unit) then return end

  local hp, maxHP, percentReady, hpSecret = UpdateAbsolute(frame, event, unit)
  if frame._msufHealthRuntimeColorUpdateEnabled ~= false
    and (event ~= "UNIT_HEALTH" or RuntimeColorOnHealthEvent(frame, hp, hpSecret)) then
    if not ApplyRuntimeColor(frame, event, unit, hp, maxHP) then SetColor(frame) end
  end
  local updateTextureState = frame._msufSurfaceHealthUpdate
  if updateTextureState then
    UpdateTextureLayerHealthState(updateTextureState, frame, unit, hp, maxHP)
  end
  if frame._msufUpdateStatusTextIndicator then
    NotifyHealthState(frame, event, unit, hp, hpSecret)
  end
  return hp, maxHP, percentReady
end

-- hot path: kept whole (perf rule)
local function UpdateSingleCurrent(frame, event, unit)
  unit = unit or frame.MSUFUnitKey
  local rt = frame and frame._msufHealthSample
  if rt and rt._dispatchHealthPercentReady == true then
    rt._dispatchHealthPercent = nil
    rt._dispatchHealthPercentReady = nil
  end
  if not (frame and frame.hpBar and unit) then return end

  -- CURRENT-only text can share UnitHealth with the bar. UnitHealthMax is
  -- retained by the absolute bar path between its own invalidation events, so
  -- steady health ticks avoid the extra UnitHealthPercent call entirely.
  local hp, maxHP, _, hpSecret = UpdateAbsolute(frame, event, unit)
  if frame._msufHealthRuntimeColorUpdateEnabled ~= false
    and (event ~= "UNIT_HEALTH" or RuntimeColorOnHealthEvent(frame, hp, hpSecret)) then
    if not ApplyRuntimeColor(frame, event, unit, hp, maxHP) then SetColor(frame) end
  end
  local updateTextureState = frame._msufSurfaceHealthUpdate
  if updateTextureState then
    UpdateTextureLayerHealthState(updateTextureState, frame, unit, hp, maxHP)
  end
  if frame._msufUpdateStatusTextIndicator then
    NotifyHealthState(frame, event, unit, hp, hpSecret)
  end
  return hp, nil, false
end

local function UpdateGroup(frame, event, unit)
  -- Cold/explicit group updates share the generic immediate text handoff.
  -- UNIT_HEALTH selects one of the folded lanes below at route compilation.
  return UpdateSingle(frame, event, unit, true)
end

-- Fold the group percent write, runtime-color gate, and steady status update
-- into one pass. Text-free/deferred routes use it directly; the immediate
-- percent-text wrapper below publishes its result only to that consumer.
-- hot path: kept whole (perf rule)
local function UpdateGroupPercentLean(frame, event, unit)
  unit = unit or frame.MSUFUnitKey
  local bar = frame and frame.hpBar
  if not (bar and unit) then return end
  local healthTick = event == "UNIT_HEALTH"
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
    local interp = healthTick and bar._msufSmoothInterp or nil
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
  if frame._msufHealthBackgroundNeedsValue == true then
    SetHealthBackgroundValue(frame, unit, pct, secret, healthTick)
  end

  -- A background-only health gradient can stay on the folded group lane: its
  -- native curve is independent of the foreground color, so refresh it before
  -- the alive/static foreground early return. Match-health waits until after a
  -- dynamic foreground repaint and is therefore handled by ApplyRuntimeColor.
  local backgroundApplied
  if healthTick
    and frame._msufHealthBackgroundGradient == true
    and frame._msufHealthRuntimeGradient ~= true then
    local refresh = frame._msufHealthBackgroundRefreshValue or RefreshHealthBarBackgroundColor
    backgroundApplied = refresh(frame, event, unit, pct, 100, nil, nil, true, secret) == true
  end

  -- UNIT_HEALTH text writers are deferred dirty markers and immediately
  -- discard dispatch payloads. For the common alive/static-color member there
  -- is likewise no status or dead-background consumer, so finish at the bar
  -- write instead of entering the generic color/status handoff. Identity,
  -- connection, gradient, gone-state, and smoothing semantics above remain
  -- unchanged.
  if healthTick
    and frame._msufHealthRuntimeGradient ~= true
    and frame._msufHealthStatusGone ~= true
    and frame._msufStatusTextValue == nil
    and frame._msufStatusTextHealthRefresh ~= true
    and frame._msufUpdateGroupVisualsGoneState == nil
    and (secret or pct > 0) then
    return pct, nil, true
  end

  if (not backgroundApplied or frame._msufHealthRuntimeColorEnabled ~= false)
    and frame._msufHealthRuntimeColorUpdateEnabled ~= false
    and (not healthTick or RuntimeColorOnHealthEvent(frame, pct, secret)) then
    -- A gone/status consumer can prevent the early return above. Its color
    -- handoff must retain the background-only result without evaluating it twice.
    if not ApplyRuntimeColor(frame, event, unit, pct, 100, nil, backgroundApplied, true) then SetColor(frame) end
  end

  -- A steady alive or secret tick with no visible gone label feeds the
  -- gone-state sink directly. Secret values keep the same nil seed that the
  -- full notifier would produce; every visible status transition retains that
  -- notifier contract.
  if healthTick
    and frame._msufStatusTextValue == nil
    and frame._msufStatusTextHealthRefresh ~= true
    and (secret or pct > 0) then
    local goneState = frame._msufUpdateGroupVisualsGoneState
    if goneState then
      local seedHP
      if not secret then seedHP = pct end
      goneState(frame, event, unit, seedHP)
    end
  else
    NotifyHealthState(frame, event, unit, pct, secret)
  end
  return pct, nil, true
end

-- Native API and curve availability are fixed when this module loads. Bind
-- the supported updater once; a legacy client retains its guarded absolute
-- route without a capability decision on every update.
if not (UnitHealthPercent and SCALE_100) then
  UpdateGroupPercentLean = function(frame, event, unit)
    unit = unit or frame.MSUFUnitKey
    if not (frame and frame.hpBar and unit) then return end
    return UpdateGroup(frame, event, unit)
  end
end

-- Only the synchronous percent-text route consumes this sample. Its selector
-- mirrors HealthText.SelectEventUpdate; deferred/value/absorb writers keep the
-- lean updater and never retain a restricted value across events. Publishing
-- through the existing dispatch slot also preserves Core's absolute-HP
-- contract for prediction and visual followers.
local function UpdateGroupPercentText(frame, event, unit)
  local pct, maxHP, percentReady = UpdateGroupPercentLean(frame, event, unit)
  if percentReady == true then
    local rt = frame._msufHealthSample
    if rt then
      rt._dispatchHealthPercent = pct
      rt._dispatchHealthPercentReady = true
    end
  end
  return pct, maxHP, percentReady
end

local HEALTH_PLAN_PERCENT = 1
local HEALTH_PLAN_CURRENT = 2
local HEALTH_PLAN_ABSOLUTE = 3

local function HealthValuePlan(frame)
  return frame and frame._msufHealthValuePlan or HEALTH_PLAN_PERCENT
end

function Health.SyncBackgroundPlan(frame, resetValue)
  if not frame then return end
  local percentPlan = UnitHealthPercent and SCALE_100
    and (frame._msufIsGroupFrame == true or HealthValuePlan(frame) == HEALTH_PLAN_PERCENT)
  SyncHealthBackgroundMask(frame, percentPlan, resetValue)
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
  if not (health and BackgroundColorMode(health) == "class" and ApplyBackgrounds) then return false end
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
  -- Text changes can select a different value path without a full Health.Apply.
  Health.SyncBackgroundPlan(frame)
  if (spec and spec.scope == "group") or (frame and frame._msufIsGroupFrame == true) then
    -- No health-text consumers -> the folded single-pass lane. Any text slot,
    -- percent need, or health-driven text color keeps the generic group path
    -- that owns the text-runtime percent handshake.
    if frame._msufHealthConsumers ~= true then
      return UpdateGroupPercentLean
    end
    return UpdateGroup
  end
  local plan = HealthValuePlan(frame)
  if plan == HEALTH_PLAN_ABSOLUTE then return UpdateSingleAbsolute end
  if plan == HEALTH_PLAN_CURRENT then return UpdateSingleCurrent end
  return UpdateSingle
end

function Health.SelectEventUpdate(frame, spec, event)
  -- Compile the handoff only for the matching immediate percent-text consumer.
  -- All deferred and text-free routes keep the folded bar-only path; cold
  -- max/connection/identity events retain the full updater.
  if event == "UNIT_HEALTH" and spec and spec.scope == "group" then
    if frame._msufHealthSyncPercent then
      return UpdateGroupPercentText
    end
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
Health.UpdateValueGroupPercentText = UpdateGroupPercentText
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
  local foregroundDynamic = frame._msufHealthRuntimeColorEnabled
  if foregroundDynamic == nil then foregroundDynamic = RuntimeColorEnabled(frame) end
  if foregroundDynamic ~= true then SetColor(frame, true) end
  if ApplyRuntimeColor(frame, event or "MSUF_COLOR_CHANGE", frame.MSUFUnitKey, nil, nil, true) then
    return true
  end
  SetColor(frame, true)
  return true
end

ExportPublic("MSUF_UFCore_RefreshHealthBarColor", Health.RefreshColor)

--- Scene form of the dynamic health background (health gradient, match health): the colour of the health the sample
--- bar shows. The live refreshers read the unit's own health percent, or paint a fixed fallback tint when the frame
--- holds no unit; a scene frame stands for a sample and asks the client nothing.
function Health.PaintSampleBackground(frame, fraction)
  local spec = frame and frame.MSUFSpec
  local health = spec and spec.health
  if not health then return false end
  local mode = BackgroundColorMode(health)
  if mode == "match_health" then
    return RefreshHealthBarBackgroundColor(frame, "MSUF_SAMPLE", nil, nil, nil, nil, true) == true
  end
  if mode ~= "health_gradient" then return false end
  local texture = frame.hpBarBG or frame.healthBg or frame.bg
  if not texture then return false end
  local r, g, b = C.PreviewHealthGradientColor(health, fraction)
  local background = health.background
  local a = background and background.a
  if type(a) ~= "number" then a = spec.backgroundAlpha or 0.9 end
  if a < 0 then a = 0 elseif a > 1 then a = 1 end
  texture:SetVertexColor(r, g, b, a)
  frame._msufHPBgR, frame._msufHPBgG, frame._msufHPBgB, frame._msufHPBgA = r, g, b, a
  return true
end

--- Scene form: the health values, background and colours from a sample, with no client query.
function Health.PaintSample(frame, unit, hp, hpMax, animate)
  local bar = frame and frame.hpBar
  if not bar then return false end
  UpdateAbsoluteValues(frame, unit, hp, hpMax, true, animate == true)
  if animate ~= true and bar._msufChunkedLoss then bar:SetValue(hp) end
  if frame._msufHealthBackgroundNeedsValue == true then
    SetHealthBackgroundValue(frame, unit, hp * 100 / hpMax, false, false)
  end
  local health = frame.MSUFSpec and frame.MSUFSpec.health
  if frame._msufHealthRuntimeGradient == true and health then
    local r, g, b = C.PreviewHealthGradientColor(health, hp / hpMax)
    C.ApplyStatusColor(bar, r, g, b)
    frame._msufGradStashR, frame._msufGradStashG, frame._msufGradStashB = r, g, b
    frame._msufGradStashAt = GetTime and GetTime() or 0
  else
    -- The background is painted from the sample below: its live refresh reads the unit's own health.
    ApplyRuntimeColor(frame, "MSUF_SAMPLE", unit, hp, hpMax, true, true, true)
  end
  if ApplyBackgrounds then
    local dynamic = frame._msufHealthBgDynamic
    frame._msufHealthBgDynamic = false
    ApplyBackgrounds(frame, true, false, true)
    frame._msufHealthBgDynamic = dynamic
  end
  Health.PaintSampleBackground(frame, hp / hpMax)
  return true
end

Health.Routes = { basic = true, identityBar = true }
Health.Routes.SelectNeeds = Health.SelectGroupHealthUpdater
UF.RegisterElement("Health", Health)

if UF.RouteCompiler then
  local Compiler = UF.RouteCompiler
  local RouteCache = setmetatable({ directHealth = {}, directGroupHealth = {} }, { __index = Compiler.Cache })
  local IsRegisteredElementFunction = Compiler.IsRegisteredFunction
  local RouteCacheLeaf = Compiler.RouteCacheLeaf
  local SharedDirectRoute = Compiler.SharedDirectRoute
  local BeginFrameEvent, EndFrameEvent = Compiler.BeginFrameEvent, Compiler.EndFrameEvent
  local GetUpdateKey = Compiler.GetUpdateKey
  local SelectElementEventUpdate = Compiler.SelectEventUpdate
  local HEALTH_EVENTS = {
    UNIT_HEALTH = true,
    UNIT_MAXHEALTH = true,
    UNIT_CONNECTION = true,
    PARTY_MEMBER_ENABLE = true,
    PARTY_MEMBER_DISABLE = true,
  }
  -- Route-closure contract for BuildHealthRoute and BuildGroupHealthRoute.
  -- `self._msufTextDirtyMask` is the deferred text drain's pending mask owned by
  -- MSUF_UF_Text_Runtime: bit 1 (value 1) = a HealthText repaint is already
  -- queued, bit 2 (value 2) = a PowerText repaint is queued, 3 = both. The test
  -- `dirty ~= 1 and dirty ~= 3` means "health bit clear" (mask nil or 2) spelled
  -- without a bit library, so the queued drain, not this tick, repaints text.
  -- `self._msufPredictionHealthVisualActive` is the flag Prediction publishes
  -- while a health-dependent absorb visual exists; false skips that follower.
  -- The ten near-identical closures below are intentional unrolling: every
  -- archetype (target-bound vs unit-bound, gated vs plain prediction, gated vs
  -- plain text, with or without visuals, dispatch-free vs Begin/EndFrameEvent)
  -- is one straight-line function whose captured nils were decided once at
  -- compile time, so the dominant UNIT_HEALTH tick pays no per-event branching.
  -- Do not fold them into a generic closure or a shared helper. BuildHealthRoute
  -- only selects the archetype builder below; each builder returns its closures
  -- unchanged.
  local function BuildDispatchFreeGatedRoute(barFn, textFn, predictionFn, routeUnitless, target)
    -- This exact UNIT_HEALTH archetype has no shared state consumer: Health
    -- owns the bar payload, Prediction is a frame-local gate/follower, and the
    -- deferred text marker retains no event payload. Group UNIT_HEALTH already
    -- uses the same dispatch-free contract; single frames can avoid the token
    -- churn too while connection/max/visual routes keep coherent dispatch.
    if target then
      -- hot path: kept whole (perf rule)
      return function(self, ev, _unit)
        local hp, hpMax, percentReady
        if barFn then hp, hpMax, percentReady = barFn(self, ev, target) end
        if self._msufPredictionHealthVisualActive == true then
          if percentReady == true then
            predictionFn(self, ev, target)
          else
            predictionFn(self, ev, target, hp, hpMax)
          end
        end
        local dirty = self._msufTextDirtyMask
        if dirty ~= 1 and dirty ~= 3 then
          if percentReady == true then textFn(self, ev, target) else textFn(self, ev, target, hp, hpMax) end
        end
      end
    end
    -- hot path: kept whole (perf rule)
    return function(self, ev, unit)
      local u = routeUnitless == true and self.MSUFUnitKey or (unit or self.MSUFUnitKey)
      local hp, hpMax, percentReady
      if barFn then hp, hpMax, percentReady = barFn(self, ev, u) end
      if self._msufPredictionHealthVisualActive == true then
        if percentReady == true then
          predictionFn(self, ev, u)
        else
          predictionFn(self, ev, u, hp, hpMax)
        end
      end
      local dirty = self._msufTextDirtyMask
      if dirty ~= 1 and dirty ~= 3 then
        if percentReady == true then textFn(self, ev, u) else textFn(self, ev, u, hp, hpMax) end
      end
    end
  end

  -- hot path: kept whole (perf rule)
  local function BuildGatedRoute(barFn, textFn, predictionFn, visualsFn, routeUnitless, target)
    if target then
      -- hot path: kept whole (perf rule)
      return function(self, ev, _unit)
        BeginFrameEvent(self, ev)
        local hp, hpMax, percentReady
        if barFn then hp, hpMax, percentReady = barFn(self, ev, target) end
        if self._msufPredictionHealthVisualActive == true then
          if percentReady == true then
            predictionFn(self, ev, target)
          else
            predictionFn(self, ev, target, hp, hpMax)
          end
        end
        local dirty = self._msufTextDirtyMask
        if dirty ~= 1 and dirty ~= 3 then
          if percentReady == true then textFn(self, ev, target) else textFn(self, ev, target, hp, hpMax) end
        end
        if visualsFn then visualsFn(self, ev, target, hp, hpMax, percentReady) end
        EndFrameEvent(self)
      end
    end
    -- hot path: kept whole (perf rule)
    return function(self, ev, unit)
      BeginFrameEvent(self, ev)
      local u = routeUnitless == true and self.MSUFUnitKey or (unit or self.MSUFUnitKey)
      local hp, hpMax, percentReady
      if barFn then hp, hpMax, percentReady = barFn(self, ev, u) end
      if self._msufPredictionHealthVisualActive == true then
        if percentReady == true then
          predictionFn(self, ev, u)
        else
          predictionFn(self, ev, u, hp, hpMax)
        end
      end
      local dirty = self._msufTextDirtyMask
      if dirty ~= 1 and dirty ~= 3 then
        if percentReady == true then textFn(self, ev, u) else textFn(self, ev, u, hp, hpMax) end
      end
      if visualsFn then visualsFn(self, ev, u, hp, hpMax, percentReady) end
      EndFrameEvent(self)
    end
  end

  -- hot path: kept whole (perf rule)
  local function BuildPredictionGatedRoute(barFn, textFn, predictionFn, visualsFn, routeUnitless, target)
    if target then
      -- hot path: kept whole (perf rule)
      return function(self, ev, _unit)
        BeginFrameEvent(self, ev)
        local hp, hpMax, percentReady
        if barFn then hp, hpMax, percentReady = barFn(self, ev, target) end
        if self._msufPredictionHealthVisualActive == true then
          if percentReady == true then
            predictionFn(self, ev, target)
          else
            predictionFn(self, ev, target, hp, hpMax)
          end
        end
        if textFn then
          if percentReady == true then textFn(self, ev, target) else textFn(self, ev, target, hp, hpMax) end
        end
        if visualsFn then visualsFn(self, ev, target, hp, hpMax, percentReady) end
        EndFrameEvent(self)
      end
    end
    -- hot path: kept whole (perf rule)
    return function(self, ev, unit)
      BeginFrameEvent(self, ev)
      local u = routeUnitless == true and self.MSUFUnitKey or (unit or self.MSUFUnitKey)
      local hp, hpMax, percentReady
      if barFn then hp, hpMax, percentReady = barFn(self, ev, u) end
      if self._msufPredictionHealthVisualActive == true then
        if percentReady == true then
          predictionFn(self, ev, u)
        else
          predictionFn(self, ev, u, hp, hpMax)
        end
      end
      if textFn then
        if percentReady == true then textFn(self, ev, u) else textFn(self, ev, u, hp, hpMax) end
      end
      if visualsFn then visualsFn(self, ev, u, hp, hpMax, percentReady) end
      EndFrameEvent(self)
    end
  end

  -- hot path: kept whole (perf rule)
  local function BuildTextGatedRoute(barFn, textFn, predictionFn, visualsFn, routeUnitless, target)
    if target then
      return function(self, ev, _unit)
        BeginFrameEvent(self, ev)
        local hp, hpMax, percentReady
        if barFn then hp, hpMax, percentReady = barFn(self, ev, target) end
        if predictionFn then
          if percentReady == true then predictionFn(self, ev, target) else predictionFn(self, ev, target, hp, hpMax) end
        end
        local dirty = self._msufTextDirtyMask
        if dirty ~= 1 and dirty ~= 3 then
          if percentReady == true then textFn(self, ev, target) else textFn(self, ev, target, hp, hpMax) end
        end
        if visualsFn then visualsFn(self, ev, target, hp, hpMax, percentReady) end
        EndFrameEvent(self)
      end
    end
    return function(self, ev, unit)
      BeginFrameEvent(self, ev)
      local u = routeUnitless == true and self.MSUFUnitKey or (unit or self.MSUFUnitKey)
      local hp, hpMax, percentReady
      if barFn then hp, hpMax, percentReady = barFn(self, ev, u) end
      if predictionFn then
        if percentReady == true then predictionFn(self, ev, u) else predictionFn(self, ev, u, hp, hpMax) end
      end
      local dirty = self._msufTextDirtyMask
      if dirty ~= 1 and dirty ~= 3 then
        if percentReady == true then textFn(self, ev, u) else textFn(self, ev, u, hp, hpMax) end
      end
      if visualsFn then visualsFn(self, ev, u, hp, hpMax, percentReady) end
      EndFrameEvent(self)
    end
  end

  local function BuildTargetRoute(barFn, textFn, predictionFn, visualsFn, target)
    if not predictionFn then
      return function(self, ev, _unit)
        BeginFrameEvent(self, ev)
        local hp, hpMax, percentReady
        if barFn then hp, hpMax, percentReady = barFn(self, ev, target) end
        if textFn then
          if percentReady == true then textFn(self, ev, target) else textFn(self, ev, target, hp, hpMax) end
        end
        if visualsFn then visualsFn(self, ev, target, hp, hpMax, percentReady) end
        EndFrameEvent(self)
      end
    end
    -- hot path: kept whole (perf rule)
    return function(self, ev, _unit)
      BeginFrameEvent(self, ev)
      local hp, hpMax, percentReady
      if barFn then hp, hpMax, percentReady = barFn(self, ev, target) end
      if percentReady == true then
        predictionFn(self, ev, target)
      else
        predictionFn(self, ev, target, hp, hpMax)
      end
      if textFn then
        if percentReady == true then textFn(self, ev, target) else textFn(self, ev, target, hp, hpMax) end
      end
      if visualsFn then visualsFn(self, ev, target, hp, hpMax, percentReady) end
      EndFrameEvent(self)
    end
  end

  -- hot path: kept whole (perf rule)
  local function BuildUnitRoute(barFn, textFn, predictionFn, visualsFn, routeUnitless)
    if not predictionFn then
      return function(self, ev, unit)
        BeginFrameEvent(self, ev)
        local u = routeUnitless == true and self.MSUFUnitKey or (unit or self.MSUFUnitKey)
        local hp, hpMax, percentReady
        if barFn then hp, hpMax, percentReady = barFn(self, ev, u) end
        if textFn then
          if percentReady == true then textFn(self, ev, u) else textFn(self, ev, u, hp, hpMax) end
        end
        if visualsFn then visualsFn(self, ev, u, hp, hpMax, percentReady) end
        EndFrameEvent(self)
      end
    end
    -- hot path: kept whole (perf rule)
    return function(self, ev, unit)
      BeginFrameEvent(self, ev)
      local u = routeUnitless == true and self.MSUFUnitKey or (unit or self.MSUFUnitKey)
      local hp, hpMax, percentReady
      if barFn then hp, hpMax, percentReady = barFn(self, ev, u) end
      if percentReady == true then
        predictionFn(self, ev, u)
      else
        predictionFn(self, ev, u, hp, hpMax)
      end
      if textFn then
        if percentReady == true then textFn(self, ev, u) else textFn(self, ev, u, hp, hpMax) end
      end
      if visualsFn then visualsFn(self, ev, u, hp, hpMax, percentReady) end
      EndFrameEvent(self)
    end
  end

  local function BuildHealthRoute(barFn, textFn, predictionFn, visualsFn, routeUnitless, target,
      predictionGated, textDirtyGated)
    -- UNIT_HEALTH can compile two followers whose common state is already known
    -- on the frame: the prediction owner publishes whether a health-dependent
    -- absorb visual exists, while the text coalescer publishes its pending bit.
    -- Keep those gates in this route so the overwhelmingly common no-op tick
    -- never crosses either follower function boundary.
    if predictionGated == true and textDirtyGated == true and predictionFn and textFn then
      if not visualsFn then
        return BuildDispatchFreeGatedRoute(barFn, textFn, predictionFn, routeUnitless, target)
      end
      return BuildGatedRoute(barFn, textFn, predictionFn, visualsFn, routeUnitless, target)
    end
    if predictionGated == true and predictionFn then
      return BuildPredictionGatedRoute(barFn, textFn, predictionFn, visualsFn, routeUnitless, target)
    end
    if textDirtyGated == true and textFn then
      return BuildTextGatedRoute(barFn, textFn, predictionFn, visualsFn, routeUnitless, target)
    end
    if target then
      return BuildTargetRoute(barFn, textFn, predictionFn, visualsFn, target)
    end
    return BuildUnitRoute(barFn, textFn, predictionFn, visualsFn, routeUnitless)
  end

  -- UNIT_HEALTH is the dominant group-frame event. Health passes every value
  -- needed by its text/prediction/visual followers, so the steady route has no
  -- shared unit-state consumer and must not enter the generic dispatch protocol.
  -- Rare connection/max-health/lifecycle paths retain BuildHealthRoute and its
  -- coherent state snapshot.
  local function BuildGroupHealthRoute(barFn, textFn, predictionFn, visualsFn, predictionGated,
      textDirtyGated)
    -- Bar-only gated archetype (group percent bar, no text, no extra visuals):
    -- the steady no-absorb UNIT_HEALTH tick is exactly one updater call.
    if predictionGated == true and barFn and not textFn and not visualsFn then
      return function(self, ev, unit)
        local u = unit or self.MSUFUnitKey
        local hp, hpMax, percentReady = barFn(self, ev, u)
        if self._msufPredictionHealthVisualActive == true then
          if percentReady == true then
            predictionFn(self, ev, u)
          else
            predictionFn(self, ev, u, hp, hpMax)
          end
        end
      end
    end
    if not predictionFn then
      return function(self, ev, unit)
        local u = unit or self.MSUFUnitKey
        local hp, hpMax, percentReady
        if barFn then hp, hpMax, percentReady = barFn(self, ev, u) end
        if textFn then
          local dirty = self._msufTextDirtyMask
          if textDirtyGated ~= true or (dirty ~= 1 and dirty ~= 3) then
            if percentReady == true then textFn(self, ev, u) else textFn(self, ev, u, hp, hpMax) end
          end
        end
        if visualsFn then visualsFn(self, ev, u, hp, hpMax, percentReady) end
      end
    end

    if predictionGated == true then
      -- hot path: kept whole (perf rule)
      return function(self, ev, unit)
        local u = unit or self.MSUFUnitKey
        local hp, hpMax, percentReady
        if barFn then hp, hpMax, percentReady = barFn(self, ev, u) end
        -- Absorb-data events own this plain gate. The common no-absorb member
        -- therefore pays no Prediction call at all on UNIT_HEALTH.
        if self._msufPredictionHealthVisualActive == true then
          if percentReady == true then
            predictionFn(self, ev, u)
          else
            predictionFn(self, ev, u, hp, hpMax)
          end
        end
        if textFn then
          local dirty = self._msufTextDirtyMask
          if textDirtyGated ~= true or (dirty ~= 1 and dirty ~= 3) then
            if percentReady == true then textFn(self, ev, u) else textFn(self, ev, u, hp, hpMax) end
          end
        end
        if visualsFn then visualsFn(self, ev, u, hp, hpMax, percentReady) end
      end
    end

    -- hot path: kept whole (perf rule)
    return function(self, ev, unit)
      local u = unit or self.MSUFUnitKey
      local hp, hpMax, percentReady
      if barFn then hp, hpMax, percentReady = barFn(self, ev, u) end
      if percentReady == true then
        predictionFn(self, ev, u)
      else
        predictionFn(self, ev, u, hp, hpMax)
      end
      if textFn then
        local dirty = self._msufTextDirtyMask
        if textDirtyGated ~= true or (dirty ~= 1 and dirty ~= 3) then
          if percentReady == true then textFn(self, ev, u) else textFn(self, ev, u, hp, hpMax) end
        end
      end
      if visualsFn then visualsFn(self, ev, u, hp, hpMax, percentReady) end
    end
  end

  local function SharedGroupHealthRoute(barFn, textFn, predictionFn, visualsFn, predictionGated,
      textDirtyGated)
    if (barFn and not IsRegisteredElementFunction(barFn))
      or (textFn and not IsRegisteredElementFunction(textFn))
      or (predictionFn and not IsRegisteredElementFunction(predictionFn))
      or (visualsFn and not IsRegisteredElementFunction(visualsFn)) then
      return BuildGroupHealthRoute(barFn, textFn, predictionFn, visualsFn,
        predictionGated, textDirtyGated)
    end
    local mode = predictionGated == true and "prediction-gated" or "direct"
    if textDirtyGated == true then mode = mode .. ":text-dirty-gated" end
    local leaf, key = RouteCacheLeaf(RouteCache.directGroupHealth,
      barFn, textFn, predictionFn, visualsFn, mode, nil)
    local route = leaf[key]
    if not route then
      route = BuildGroupHealthRoute(barFn, textFn, predictionFn, visualsFn,
        predictionGated, textDirtyGated)
      leaf[key] = route
    end
    RouteCache.sharedRoutes[route] = true
    return route
  end

  local function Compile(frame, event, list, target)
    local count = #list
    local barElement = Health
    local barBase = frame[GetUpdateKey("Health")]
    local barUpdate = barBase
      and SelectElementEventUpdate(barElement, frame, event, barBase) or barBase
    local textElement = UF.elements.HealthText
    local textBase = frame[GetUpdateKey("HealthText")]
    local textUpdate = textBase and SelectElementEventUpdate(textElement, frame, event, textBase) or nil
    local predictionUpdate
    local visualsUpdate
    local predictionBase = frame[GetUpdateKey("Prediction")]
    if predictionBase then
      predictionUpdate = SelectElementEventUpdate(UF.elements.Prediction, frame, event, predictionBase)
    end
    local visualsBase = frame[GetUpdateKey("GroupVisuals")]
    if visualsBase then
      visualsUpdate = SelectElementEventUpdate(UF.elements.GroupVisuals, frame, event, visualsBase)
    end
    local barFn, textFn, predictionFn, visualsFn
    local routeUnitless
    local direct = true
    for i = 1, count, 2 do
      local update = list[i]
      local unitless = list[i + 1] == true
      if routeUnitless == nil then
        routeUnitless = unitless
      elseif routeUnitless ~= unitless then
        direct = false
        break
      end
      if update == barUpdate then
        barFn = update
      elseif update == textUpdate then
        textFn = update
      elseif predictionUpdate and update == predictionUpdate then
        predictionFn = update
      elseif visualsUpdate and update == visualsUpdate then
        visualsFn = update
      else
        direct = false
        break
      end
    end
    if direct == true and (barFn or textFn or predictionFn or visualsFn) then
      local prediction = event == "UNIT_HEALTH" and UF.elements.Prediction or nil
      local predictionGated = predictionFn and prediction
        and prediction.HealthVisualGateUpdates
        and prediction.HealthVisualGateUpdates[predictionFn] == true
      local healthText = event == "UNIT_HEALTH" and UF.elements.HealthText or nil
      local textDirtyGated = textFn and healthText
        and healthText.DirtyGateUpdates
        and healthText.DirtyGateUpdates[textFn] == true
      if frame._msufCoreScope == "group" and event == "UNIT_HEALTH"
        and target == nil and routeUnitless ~= true then
        return SharedGroupHealthRoute(
          barFn, textFn, predictionFn, visualsFn,
          predictionGated == true, textDirtyGated == true)
      end
      return SharedDirectRoute(RouteCache.directHealth, BuildHealthRoute,
        barFn, textFn, predictionFn, visualsFn, routeUnitless, target,
        predictionGated == true, textDirtyGated == true)
    end
  end
  UF.RegisterRoute("health", Compile, 20, HEALTH_EVENTS)
end
