-- UF bars common element helpers: shared statusbar setup, textures, and geometry utilities.
-- Keep live unit-event code allocation-light; cold spec/application work belongs in callers.
local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
  _G[name] = value
  return value
end

local UF = MSUF.UF
local CreateFrame = CreateFrame
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitGetTotalAbsorbs = _G.UnitGetTotalAbsorbs
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitHealthPercent = _G.UnitHealthPercent
local UnitPowerPercent = _G.UnitPowerPercent
local AbbreviateNumbers = _G.AbbreviateNumbers
local BreakUpLargeNumbers = _G.BreakUpLargeNumbers
local AbbreviateLargeNumbers = _G.AbbreviateLargeNumbers or _G.ShortenNumber
local InCombatLockdown = _G.InCombatLockdown
local UnitName = UnitName
local UnitIsPlayer = UnitIsPlayer
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsConnected = UnitIsConnected
local UnitCanAttack = UnitCanAttack
local UnitCanAssist = UnitCanAssist
local UnitReaction = UnitReaction
local UnitSelectionType = UnitSelectionType
local UnitSelectionColor = UnitSelectionColor
local UnitClassification = UnitClassification or GetUnitClassification
local UnitIsBossMob = UnitIsBossMob
local UnitIsLieutenant = UnitIsLieutenant
local UnitEffectiveLevel = UnitEffectiveLevel
local UnitHasPowerType = UnitHasPowerType
local UnitPowerType = UnitPowerType
local IsInInstance = IsInInstance
local GetMaxLevelForExpansionLevel = GetMaxLevelForExpansionLevel
local GetMaximumExpansionLevel = GetMaximumExpansionLevel
local PowerBarColor = PowerBarColor
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local type = type
local tonumber = tonumber
local format = string.format
local byte, sub = string.byte, string.sub
local abs, floor, max = math.abs, math.floor, math.max
local Clamp01 = UF.Clamp01
local FreshUnitState = UF.FreshUnitState
local ReadUnitExistsCached = UF.ReadUnitExistsCached
local ReadUnitIsPlayerCached = UF.ReadUnitIsPlayerCached
local ReadUnitClassCached = UF.ReadUnitClassCached
local ReadConnectedCached = UF.ReadConnectedCached
local ReadDeadCached = UF.ReadDeadCached
local GetTime = _G.GetTime
local C_Timer = _G.C_Timer
local Enum = _G.Enum
local StatusBarInterpolation = Enum and Enum.StatusBarInterpolation
local SMOOTH_INTERP = StatusBarInterpolation and StatusBarInterpolation.ExponentialEaseOut or nil
local C_CurveUtil = _G.C_CurveUtil
local CreateColor = _G.CreateColor
local C_ClassColor_GetClassColor = _G.C_ClassColor and _G.C_ClassColor.GetClassColor
local Secrets = MSUF.Secrets or {}
local IsSecret = Secrets.IsSecret or function(_) return false end
local IsNil = Secrets.IsNil or function(value) return value == nil end
local issecretvalue = _G.issecretvalue or function(_) return false end
local SafeNumber = Secrets.SafeNumber or tonumber
local POWER_TYPE_MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
local SECRET_NATIVE_CLASS_COLOR = 2

local npcTypeReferenceLevel
local npcTypeReferenceInstanceType
local npcTypeLieutenantLevel

local IsUnitToken = UF.IsUnitToken or function(unit)
  return issecretvalue(unit) ~= true and type(unit) == "string" and unit ~= ""
end

-- Shared bar/text primitives for unitframe elements.
-- Health, power, text, color, and smoothing helpers live here so element files can share the
-- same secret-value handling and cached mutation rules instead of diverging per unit type.
local WHITE = "Interface\\Buttons\\WHITE8x8"
local SCALE_100 = _G.CurveConstants and _G.CurveConstants.ScaleTo100
local ABSORB_HEALTH_MODE_BASE = {
  CURRENTABSORB = "CURRENT",
  FULLVALUEABSORB = "FULLVALUE",
  MAXABSORB = "MAX",
  DEFICITABSORB = "DEFICIT",
  CURMAXABSORB = "CURMAX",
  PERCENTABSORB = "PERCENT",
  CURPERCENTABSORB = "CURPERCENT",
  CURMAXPERCENTABSORB = "CURMAXPERCENT",
  MAXPERCENTABSORB = "MAXPERCENT",
  PERCENTCURABSORB = "PERCENTCUR",
  PERCENTMAXABSORB = "PERCENTMAX",
  PERCENTCURMAXABSORB = "PERCENTCURMAX",
  MAXCURABSORB = "MAXCUR",
  PERCENTMAXCURABSORB = "PERCENTMAXCUR",
}
local REVERSE_HEALTH_MODE = {
  CURPERCENT = "PERCENTCUR",
  PERCENTCUR = "CURPERCENT",
  CURMAX = "MAXCUR",
  MAXCUR = "CURMAX",
  CURMAXPERCENT = "PERCENTMAXCUR",
  PERCENTMAXCUR = "CURMAXPERCENT",
  MAXPERCENT = "PERCENTMAX",
  PERCENTMAX = "MAXPERCENT",
  PERCENTCURMAX = "CURMAXPERCENT",
  CURPERCENTABSORB = "PERCENTCURABSORB",
  PERCENTCURABSORB = "CURPERCENTABSORB",
  CURMAXABSORB = "MAXCURABSORB",
  MAXCURABSORB = "CURMAXABSORB",
  CURMAXPERCENTABSORB = "PERCENTMAXCURABSORB",
  PERCENTMAXCURABSORB = "CURMAXPERCENTABSORB",
  MAXPERCENTABSORB = "PERCENTMAXABSORB",
  PERCENTMAXABSORB = "MAXPERCENTABSORB",
  PERCENTCURMAXABSORB = "CURMAXPERCENTABSORB",
}
local EMPTY_EVENTS = {}
local POWER_EVENTS = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_POWER_BAR_SHOW", "UNIT_POWER_BAR_HIDE" }
local POWER_EVENTS_FREQUENT = { "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_POWER_BAR_SHOW", "UNIT_POWER_BAR_HIDE" }
local TEXT_EVENT_SETS = {
  -- Event sets are deliberately prebuilt tables. The dispatcher stores references to these
  -- tables and should not allocate new event arrays every time a text mode changes.
  [0] = EMPTY_EVENTS,
  [1] = { "UNIT_NAME_UPDATE" },
  [2] = { "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_FLAGS", "UNIT_CONNECTION", "UNIT_CLASSIFICATION_CHANGED" },
  [3] = { "UNIT_NAME_UPDATE", "UNIT_TARGET" },
  [4] = { "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_FLAGS", "UNIT_CONNECTION", "UNIT_CLASSIFICATION_CHANGED", "UNIT_TARGET" },
}
local TEXT_EVENT_SETS_ABSORB = {
  [0] = { "UNIT_ABSORB_AMOUNT_CHANGED" },
  [1] = { "UNIT_NAME_UPDATE", "UNIT_ABSORB_AMOUNT_CHANGED" },
  [2] = { "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_FLAGS", "UNIT_CONNECTION", "UNIT_CLASSIFICATION_CHANGED", "UNIT_ABSORB_AMOUNT_CHANGED" },
  [3] = { "UNIT_NAME_UPDATE", "UNIT_TARGET", "UNIT_ABSORB_AMOUNT_CHANGED" },
  [4] = { "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_FLAGS", "UNIT_CONNECTION", "UNIT_CLASSIFICATION_CHANGED", "UNIT_TARGET", "UNIT_ABSORB_AMOUNT_CHANGED" },
}

local function ClampFrameLayer(layer, fallback)
  layer = floor((tonumber(layer) or fallback or 5) + 0.5)
  if layer < 0 then
    return 0
  elseif layer > 30 then
    return 30
  end
  return layer
end

local function DrawSubLayer(layer, fallback)
  layer = ClampFrameLayer(layer, fallback)
  if layer > 7 then
    return 7
  end
  return layer
end

local function GetLayerBaseLevel(frame)
  local base = frame and (frame.Health or frame.hpBar or frame)
  return base and base.GetFrameLevel and (base:GetFrameLevel() or 0) or 0
end

local function SetStatusTexture(bar, texture)
  if bar and texture and bar.MSUFTexture ~= texture then
    bar:SetStatusBarTexture(texture)
    bar.MSUFTexture = texture
  end
end

local function ApplyStatusColor(bar, r, g, b, a)
  if bar then
    r, g, b, a = r or 1, g or 1, b or 1, a or 1
    if bar._msufStatusR ~= r or bar._msufStatusG ~= g or bar._msufStatusB ~= b or bar._msufStatusA ~= a then
      bar:SetStatusBarColor(r, g, b, a)
      bar._msufStatusR, bar._msufStatusG, bar._msufStatusB, bar._msufStatusA = r, g, b, a
    end
  end
end

local function SetBarMinMax(bar, maxValue, directValue)
  if directValue then
    -- Direct mode passes Blizzard values straight to StatusBar APIs. When a value is secret,
    -- clear Lua comparison caches and let the C-side widget own the payload.
    local maxSecret = issecretvalue(maxValue) == true
    if not maxSecret and bar._msufDirectMaxValuePlain == true and bar._msufDirectMaxValue == maxValue then
      return false
    end
    bar:SetMinMaxValues(0, maxValue)
    if maxSecret then
      bar._msufDirectMaxValue = nil
      bar._msufDirectMaxValuePlain = nil
    else
      bar._msufDirectMaxValue = maxValue
      bar._msufDirectMaxValuePlain = true
    end
    bar._msufMaxValue = nil
    bar._msufMaxValuePlain = nil
    return true
  end
  bar._msufDirectMaxValue = nil
  bar._msufDirectMaxValuePlain = nil
  maxValue = SafeNumber(maxValue) or 0
  if bar._msufMaxValuePlain ~= true or bar._msufMaxValue ~= maxValue then
    bar:SetMinMaxValues(0, maxValue)
    bar._msufMaxValue = maxValue
    bar._msufMaxValuePlain = true
    return true
  end
  return false
end

local function SetBarMinMaxKnown(bar, maxValue, maxSecret)
  if maxSecret == nil then
    maxSecret = issecretvalue(maxValue) == true
  end
  if not maxSecret and bar._msufDirectMaxValuePlain == true and bar._msufDirectMaxValue == maxValue then
    return false
  end
  bar:SetMinMaxValues(0, maxValue)
  if maxSecret then
    bar._msufDirectMaxValue = nil
    bar._msufDirectMaxValuePlain = nil
  else
    bar._msufDirectMaxValue = maxValue
    bar._msufDirectMaxValuePlain = true
  end
  bar._msufMaxValue = nil
  bar._msufMaxValuePlain = nil
  return true
end
local SetBarMinMaxPlain = SetBarMinMaxKnown

local function SetBarValue(bar, value, directValue, animate)
  if directValue then
    local valueSecret = issecretvalue(value) == true
    local interp = animate and bar._msufSmoothInterp or nil
    if not valueSecret and bar._msufDirectValuePlain == true and bar._msufDirectValue == value then
      return false
    end
    if interp then
      bar:SetValue(value, interp)
      bar._msufInterpolating = true
    else
      bar:SetValue(value)
      bar._msufInterpolating = nil
    end
    if valueSecret then
      bar._msufDirectValue = nil
      bar._msufDirectValuePlain = nil
    else
      bar._msufDirectValue = value
      bar._msufDirectValuePlain = true
    end
    bar._msufValue = nil
    bar._msufValuePlain = nil
    return true
  end
  bar._msufDirectValue = nil
  bar._msufDirectValuePlain = nil
  value = SafeNumber(value) or 0
  if bar._msufValuePlain ~= true or bar._msufValue ~= value then
    local interp = animate and bar._msufSmoothInterp or nil
    if interp then
      bar:SetValue(value, interp)
      bar._msufInterpolating = true
    else
      bar:SetValue(value)
      bar._msufInterpolating = nil
    end
    bar._msufValue = value
    bar._msufValuePlain = true
    return true
  end
  return false
end

local function SetBarValueKnown(bar, value, valueSecret, animate)
  if valueSecret == nil then
    valueSecret = issecretvalue(value) == true
  end
  local interp = animate and bar._msufSmoothInterp or nil
  if not valueSecret and bar._msufDirectValuePlain == true and bar._msufDirectValue == value then
    return false
  end
  if interp then
    bar:SetValue(value, interp)
    bar._msufInterpolating = true
  else
    bar:SetValue(value)
    bar._msufInterpolating = nil
  end
  if valueSecret then
    bar._msufDirectValue = nil
    bar._msufDirectValuePlain = nil
  else
    bar._msufDirectValue = value
    bar._msufDirectValuePlain = true
  end
  bar._msufValue = nil
  bar._msufValuePlain = nil
  return true
end

local function SetBarValuePlain(bar, value, animate)
  local valueSecret = issecretvalue(value) == true
  if not valueSecret and bar._msufDirectValuePlain == true and bar._msufDirectValue == value then
    return false
  end
  local interp = animate and bar._msufSmoothInterp or nil
  if interp then
    bar:SetValue(value, interp)
    bar._msufInterpolating = true
  else
    bar:SetValue(value)
    bar._msufInterpolating = nil
  end
  if valueSecret then
    bar._msufDirectValue = nil
    bar._msufDirectValuePlain = nil
  else
    bar._msufDirectValue = value
    bar._msufDirectValuePlain = true
  end
  bar._msufValue = nil
  bar._msufValuePlain = nil
  return true
end

local function SnapBarInterpolation(bar)
  if not (bar and bar._msufInterpolating == true) then
    return false
  end
  if bar.SetToTargetValue then
    bar:SetToTargetValue()
  end
  bar._msufInterpolating = nil
  return true
end

local function CreateLossTrail(parent, texture, initialValue)
  if not parent then return nil end
  local trail = CreateFrame("StatusBar", nil, parent)
  trail:SetMinMaxValues(0, 100)
  trail:SetValue(initialValue or 0)
  trail:SetStatusBarTexture(texture or WHITE)
  if trail.EnableMouse then trail:EnableMouse(false) end
  trail:Hide()
  if trail.CreateAnimationGroup then
    local animation = trail:CreateAnimationGroup()
    local hold = animation:CreateAnimation("Alpha")
    hold:SetFromAlpha(1)
    hold:SetToAlpha(1)
    hold:SetDuration(0.4)
    hold:SetOrder(1)
    local fade = animation:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(0.2)
    fade:SetOrder(2)
    animation:SetScript("OnFinished", function()
      trail._msufLossAnimating = nil
      trail:Hide()
      trail:SetAlpha(1)
    end)
    trail._msufLossAnimation = animation
  end
  return trail
end

local function CreateLossTrailPool(parent, texture, initialValue, count)
  count = tonumber(count) or 1
  if count < 1 then count = 1 end
  local root = CreateLossTrail(parent, texture, initialValue)
  if not root or count == 1 then return root end
  local pool = { root }
  root._msufLossTrailPool = pool
  for i = 2, count do
    local trail = CreateLossTrail(parent, texture, initialValue)
    if not trail then break end
    trail._msufLossTrailRoot = root
    pool[#pool + 1] = trail
  end
  return root
end

local function StopSingleLossTrailAnimation(trail)
  if not trail then return end
  local animation = trail._msufLossAnimation
  if animation and animation.Stop then animation:Stop() end
  trail._msufLossAnimating = nil
  trail:SetAlpha(1)
  trail:Hide()
end

local function StopLossTrailAnimation(trail)
  if not trail then return end
  local pool = trail._msufLossTrailPool
  if pool then
    for i = 1, #pool do StopSingleLossTrailAnimation(pool[i]) end
    trail._msufLossTrailNext = nil
    return
  end
  StopSingleLossTrailAnimation(trail)
end

local function PlaySingleLossTrailAnimation(trail)
  if not trail then return end
  trail:SetAlpha(1)
  trail:Show()
  trail._msufLossAnimating = true
  local animation = trail._msufLossAnimation
  if animation and animation.Play then animation:Play() end
end

local function SetSingleLossTrailValue(trail, value)
  if not trail then return end
  trail:SetValue(value)
end

local function SetLossTrailValue(trail, value)
  if not trail then return end
  local pool = trail._msufLossTrailPool
  if pool then
    for i = 1, #pool do SetSingleLossTrailValue(pool[i], value) end
    return
  end
  SetSingleLossTrailValue(trail, value)
end

-- Clip the old-value StatusBar at the live fill edge. The mask follows the
-- native StatusBar texture geometry, so the visible region is exactly the
-- old/new delta without reading or doing arithmetic on opaque combat values.
local function AnchorSingleLossTrailMask(bar, trail)
  if not (bar and trail and bar.GetStatusBarTexture and trail.GetStatusBarTexture) then return end
  local liveFill = bar:GetStatusBarTexture()
  local trailFill = trail:GetStatusBarTexture()
  if not (liveFill and trailFill and trailFill.AddMaskTexture) then return end
  if trailFill.SetBlendMode then trailFill:SetBlendMode(trail._msufLossBlendMode or "ADD") end

  local mask = trail._msufLossClipMask
  if not mask and trail.CreateMaskTexture then
    mask = trail:CreateMaskTexture()
    mask:SetTexture(WHITE)
    trail._msufLossClipMask = mask
  end
  if not mask then return end

  local maskedFill = trail._msufLossMaskedFill
  if maskedFill ~= trailFill then
    if maskedFill and maskedFill.RemoveMaskTexture then maskedFill:RemoveMaskTexture(mask) end
    trailFill:AddMaskTexture(mask)
    trail._msufLossMaskedFill = trailFill
  end

  mask:ClearAllPoints()
  local orientation = bar._msufPowerOrientation or bar._msufOrientation or "HORIZONTAL"
  local reverse = bar._msufReverseFill == true
  if orientation == "VERTICAL" then
    if reverse then
      mask:SetPoint("TOPRIGHT", liveFill, "BOTTOMRIGHT", 0, 0)
      mask:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    else
      mask:SetPoint("BOTTOMLEFT", liveFill, "TOPLEFT", 0, 0)
      mask:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    end
  elseif reverse then
    mask:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    mask:SetPoint("BOTTOMRIGHT", liveFill, "BOTTOMLEFT", 0, 0)
  else
    mask:SetPoint("TOPLEFT", liveFill, "TOPRIGHT", 0, 0)
    mask:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
  end
end

local function AnchorLossTrailMask(bar, trail)
  if not trail then return end
  local pool = trail._msufLossTrailPool
  if pool then
    for i = 1, #pool do AnchorSingleLossTrailMask(bar, pool[i]) end
    return
  end
  AnchorSingleLossTrailMask(bar, trail)
end

local function AcquireLossTrailSnapshot(root)
  local pool = root and root._msufLossTrailPool
  if not pool then return root end
  local count = #pool
  local start = root._msufLossTrailNext or 1
  local selected
  for offset = 0, count - 1 do
    local index = ((start + offset - 1) % count) + 1
    local candidate = pool[index]
    if candidate._msufLossAnimating ~= true then
      selected = candidate
      root._msufLossTrailNext = (index % count) + 1
      break
    end
  end
  if selected then return selected end
  selected = pool[start]
  root._msufLossTrailNext = (start % count) + 1
  StopSingleLossTrailAnimation(selected)
  return selected
end

-- This mirrors the loss-bar portion of Blizzard's BuilderSpender feedback:
-- keep the old/new delta for 0.4s, then fade it by 0.6s while the real bar
-- snaps immediately. Native StatusBar geometry and the mask above avoid
-- inspecting, comparing, or subtracting opaque Midnight values in Lua.
local function ChunkedSetValue(bar, value, interpolation)
  local nativeSetValue = bar._msufNativeSetValue
  local trail = bar._msufLossTrail
  if interpolation == SMOOTH_INTERP and trail then
    local snapshot = AcquireLossTrailSnapshot(trail)
    local startTrail = trail._msufLossTrailPool ~= nil or snapshot._msufLossAnimating ~= true
    if startTrail then SetSingleLossTrailValue(snapshot, bar:GetValue()) end
    nativeSetValue(bar, value)
    -- A Player power pool gives every dense Energy tick its own native
    -- snapshot. Gain snapshots stay clipped away while a subsequent spend
    -- remains visible for its complete hold/fade window.
    if startTrail then PlaySingleLossTrailAnimation(snapshot) end
    return
  end
  nativeSetValue(bar, value, interpolation)
  if trail then
    StopLossTrailAnimation(trail)
    SetLossTrailValue(trail, value)
  end
end

local function ChunkedSetMinMaxValues(bar, minValue, maxValue)
  bar._msufNativeSetMinMaxValues(bar, minValue, maxValue)
  local trail = bar._msufLossTrail
  if trail then
    trail:SetMinMaxValues(minValue, maxValue)
  end
end

local function RestoreNativeBarMethods(bar)
  if bar._msufNativeSetValue then
    bar.SetValue = bar._msufNativeSetValue
    bar._msufNativeSetValue = nil
  end
  if bar._msufNativeSetMinMaxValues then
    bar.SetMinMaxValues = bar._msufNativeSetMinMaxValues
    bar._msufNativeSetMinMaxValues = nil
  end
end

local function SetBarSmoothing(bar, enabled, chunked, lossTrail)
  if not bar then
    return
  end
  local useChunked = chunked == true and lossTrail ~= nil and SMOOTH_INTERP ~= nil
  local interp = (enabled == true or useChunked) and SMOOTH_INTERP or nil
  if useChunked then AnchorLossTrailMask(bar, lossTrail) end
  if bar._msufSmoothInterp ~= interp
    or bar._msufChunkedLoss ~= useChunked
    or (useChunked and bar._msufLossTrail ~= lossTrail) then
    SnapBarInterpolation(bar)
    local oldTrail = bar._msufLossTrail
    StopLossTrailAnimation(oldTrail)
    RestoreNativeBarMethods(bar)
    if oldTrail and oldTrail ~= lossTrail then oldTrail:Hide() end
    bar._msufLossTrail = useChunked and lossTrail or nil
    bar._msufChunkedLoss = useChunked
    bar._msufSmoothInterp = interp
    if useChunked then
      lossTrail:SetMinMaxValues(bar:GetMinMaxValues())
      SetLossTrailValue(lossTrail, bar:GetValue())
      bar._msufNativeSetValue = bar.SetValue
      bar._msufNativeSetMinMaxValues = bar.SetMinMaxValues
      bar.SetValue = ChunkedSetValue
      bar.SetMinMaxValues = ChunkedSetMinMaxValues
    end
  end
  if lossTrail and not useChunked then StopLossTrailAnimation(lossTrail) end
end

local function ApplyTextureColor(region, texture, r, g, b, a, force)
  if not region then
    return
  end
  r, g, b, a = r or 0, g or 0, b or 0, a or 1
  if texture then
    if force == true or region._msufBgTexture ~= texture or region._msufBgColorTexture == true then
      region:SetTexture(texture)
      region._msufBgTexture = texture
      region._msufBgColorTexture = nil
    end
    if force == true or region._msufBgR ~= r or region._msufBgG ~= g or region._msufBgB ~= b or region._msufBgA ~= a then
      region:SetVertexColor(r, g, b, a)
      region._msufBgR, region._msufBgG, region._msufBgB, region._msufBgA = r, g, b, a
    end
  elseif force == true or region._msufBgColorTexture ~= true or region._msufBgR ~= r or region._msufBgG ~= g or region._msufBgB ~= b or region._msufBgA ~= a then
    region:SetColorTexture(r, g, b, a)
    region._msufBgColorTexture = true
    region._msufBgTexture = nil
    region._msufBgR, region._msufBgG, region._msufBgB, region._msufBgA = r, g, b, a
  end
end

local function SetShownCached(obj, show)
  if obj and obj._msufShown ~= show then
    obj:SetShown(show)
    obj._msufShown = show
  end
end

local GRADIENT_DIRS = { "left", "right", "up", "down" }

local function GradientActive(spec)
  if not (spec and spec.enabled == true) then
    return false
  end
  if (tonumber(spec.strength) or 0) <= 0 then
    return false
  end
  return spec.left == true or spec.right == true or spec.up == true or spec.down == true
end

local function HideBarGradient(grads)
  if type(grads) ~= "table" then
    return
  end
  for i = 1, #GRADIENT_DIRS do
    SetShownCached(grads[GRADIENT_DIRS[i]], false)
  end
end

local function GradientTarget(bar)
  if bar and bar.GetStatusBarTexture then
    local fill = bar:GetStatusBarTexture()
    if fill then
      return fill
    end
  end
  return bar
end

local function AnchorGradientTexture(tex, target)
  if not (tex and target) or tex._msufGradientTarget == target then
    return
  end
  tex:ClearAllPoints()
  tex:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
  tex:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
  tex._msufGradientTarget = target
end

local function ConfigureGradientTexture(tex, direction, alpha, r, g, b)
  if not tex then
    return
  end
  alpha = Clamp01(alpha, 0.45)
  r, g, b = Clamp01(r, 0), Clamp01(g, 0), Clamp01(b, 0)
  local orientation = (direction == "up" or direction == "down") and "VERTICAL" or "HORIZONTAL"
  local minA, maxA
  if direction == "left" or direction == "down" then
    minA, maxA = alpha, 0
  else
    minA, maxA = 0, alpha
  end
  if tex._msufGradientDirection == direction
    and tex._msufGradientAlpha == alpha
    and tex._msufGradientR == r
    and tex._msufGradientG == g
    and tex._msufGradientB == b
    and tex._msufGradientReady == true then
    return
  end
  tex:SetTexture(WHITE)
  if tex.SetBlendMode then
    tex:SetBlendMode("BLEND")
  end
  if tex.SetGradient and CreateColor then
    tex:SetGradient(orientation, CreateColor(r, g, b, minA), CreateColor(r, g, b, maxA))
    tex._msufGradientReady = true
    tex._msufGradientDirection = direction
    tex._msufGradientAlpha = alpha
    tex._msufGradientR, tex._msufGradientG, tex._msufGradientB = r, g, b
    return
  end
  if tex.SetGradientAlpha then
    tex:SetGradientAlpha(orientation, r, g, b, minA, r, g, b, maxA)
    tex._msufGradientReady = true
    tex._msufGradientDirection = direction
    tex._msufGradientAlpha = alpha
    tex._msufGradientR, tex._msufGradientG, tex._msufGradientB = r, g, b
    return
  end
  tex:SetColorTexture(r, g, b, alpha)
  tex._msufGradientReady = true
  tex._msufGradientDirection = direction
  tex._msufGradientAlpha = alpha
  tex._msufGradientR, tex._msufGradientG, tex._msufGradientB = r, g, b
end

local function EnsureGradientTexture(textureOwner, grads, direction)
  local tex = grads and grads[direction]
  if tex then
    return tex
  end
  if not (textureOwner and textureOwner.CreateTexture) then
    return nil
  end
  tex = textureOwner:CreateTexture(nil, "OVERLAY", nil, 0)
  tex:SetTexture(WHITE)
  tex:SetBlendMode("BLEND")
  grads[direction] = tex
  return tex
end

--- Applies the exact runtime gradient composition to an arbitrary fill Texture.
--- StatusBars use ApplyBarGradient below; preview-only texture bars use this
--- lower-level form so both surfaces share direction/color/caching semantics.
local function ApplyBarGradientToTarget(frame, textureOwner, target, spec, storeKey)
  if not (frame and textureOwner and storeKey) then
    return nil
  end
  local grads = frame[storeKey]
  if not grads then
    grads = {}
    frame[storeKey] = grads
  end
  if not GradientActive(spec) then
    HideBarGradient(grads)
    return grads
  end
  if not target then
    HideBarGradient(grads)
    return grads
  end
  local alpha = Clamp01(spec.strength, 0.45)
  local r, g, b = Clamp01(spec.r, 0), Clamp01(spec.g, 0), Clamp01(spec.b, 0)
  for i = 1, #GRADIENT_DIRS do
    local direction = GRADIENT_DIRS[i]
    local tex = grads[direction]
    if spec[direction] == true then
      tex = EnsureGradientTexture(textureOwner, grads, direction)
      AnchorGradientTexture(tex, target)
      ConfigureGradientTexture(tex, direction, alpha, r, g, b)
      SetShownCached(tex, true)
    else
      SetShownCached(tex, false)
    end
  end
  return grads
end

local function ApplyBarGradient(frame, bar, spec, storeKey)
  if not (frame and bar) then
    return nil
  end
  local grads = ApplyBarGradientToTarget(frame, bar, GradientTarget(bar), spec, storeKey)
  if frame._msufIsGroupFrame == true then
    bar._msufGFGrads = grads
  end
  return grads
end

local BAR_GRADIENT_ELEMENTS = { "Health", "Power" }

local function NormalizeGradientScope(scope)
  scope = tostring(scope or ""):lower()
  if scope == "" or scope == "*" or scope == "shared" or scope == "global" or scope == "all" then return nil end
  if scope == "tot" or scope == "targetoftarget" then return "targettarget" end
  if scope == "focus_target" or scope == "focustargettarget" then return "focustarget" end
  return scope
end

local function GradientGroupKinds(scope)
  scope = NormalizeGradientScope(scope)
  if scope == "gf_party" or scope == "party" then return "party" end
  if scope == "gf_raid" or scope == "raid" then return "raid", "mythicraid" end
  if scope == "gf_mythicraid" or scope == "mythicraid" then return "mythicraid" end
  return nil
end

local function UpdateAllBarGradients(unit, skipUnitFrames)
  local refreshed = false
  local kindA, kindB = GradientGroupKinds(unit)
  local unitScope = NormalizeGradientScope(unit)
  if skipUnitFrames ~= true and UF and type(UF.RefreshElements) == "function" then
    if not kindA then
      refreshed = UF.RefreshElements(unitScope, BAR_GRADIENT_ELEMENTS, "MSUF2_GRADIENT") or refreshed
    end
  end
  local GF = MSUF and MSUF.GF
  if GF and type(GF.RefreshVisuals) == "function" then
    if kindA then
      refreshed = GF.RefreshVisuals(kindA, GF.DIRTY_VISUAL) or refreshed
      if kindB then refreshed = GF.RefreshVisuals(kindB, GF.DIRTY_VISUAL) or refreshed end
    elseif not unitScope then
      refreshed = GF.RefreshVisuals(nil, GF.DIRTY_VISUAL) or refreshed
    end
  end
  if not unitScope and _G.MSUF_RoundedUF_Active == true and type(_G.MSUF_RoundedUF_OnApplyAll) == "function" then
    _G.MSUF_RoundedUF_OnApplyAll()
  end
  return refreshed
end

ExportPublic("MSUF_UpdateAllBarGradients", _G.MSUF_UpdateAllBarGradients or UpdateAllBarGradients)
MSUF.MSUF_UpdateAllBarGradients = MSUF.MSUF_UpdateAllBarGradients or UpdateAllBarGradients

local function SetFrameLevelCached(frame, level)
  if frame and frame.SetFrameLevel and frame._msufFrameLevel ~= level then
    frame:SetFrameLevel(level)
    frame._msufFrameLevel = level
  end
end

local function ExternalFrameWidth(frameName, relativeTo)
  if not frameName then
    return nil
  end
  local frame = (type(_G.MSUF_GetEffectiveCooldownFrame) == "function" and _G.MSUF_GetEffectiveCooldownFrame(frameName)) or _G[frameName]
  if not (frame and frame.GetWidth) or frame._msufLegacyCooldownAnchor == true or (frame.IsShown and not frame:IsShown()) then
    return nil
  end
  local widthFn = _G.MSUF_CDM_GetScaledWidth
  local width = type(widthFn) == "function" and widthFn(frame, relativeTo) or frame:GetWidth()
  width = tonumber(width)
  if width and width >= 20 then
    return width
  end
  return nil
end

local function ClassColorForToken(class, classIsKnownPlain)
  if classIsKnownPlain ~= true and issecretvalue(class) == true then
    class = nil
  end
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if not c then
    return nil
  end
  local fast = _G.MSUF_UFCore_GetClassBarColorFast
  if type(fast) == "function" then
    local r, g, b = fast(class)
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
      return r, g, b
    end
  end
  return c.r, c.g, c.b
end

local function ClassColor(unit)
  if IsUnitToken(unit) then
    local _, class = UnitClass(unit)
    local r, g, b = ClassColorForToken(class)
    if r ~= nil then
      return r, g, b
    end
  end
  return 0.12, 0.62, 0.95
end

local function DispatchClassColor(frame, unit, allowSecretPassThrough)
  local _, class = ReadUnitClassCached(frame, unit)
  local classIsKnownPlain
  if allowSecretPassThrough == true then
    if issecretvalue(class) == true then
      return class, nil, nil, SECRET_NATIVE_CLASS_COLOR
    end
    classIsKnownPlain = true
  end
  local r, g, b = ClassColorForToken(class, classIsKnownPlain)
  if r ~= nil then return r, g, b end
  return 0.12, 0.62, 0.95
end

local function FriendlyNPCClassToken(state, frame, unit)
  if not state then
    return nil
  end
  if state.npcClassRead ~= true then
    state.npcClassRead = true
    local reaction = IsUnitToken(unit) and UnitReaction and SafeNumber(UnitReaction(unit, "player")) or nil
    if reaction and reaction >= 5 then
      state.npcClassEligible = true
      local _, class = ReadUnitClassCached(frame, unit)
      state.npcClassSecret = issecretvalue(class) == true
      state.npcClass = class
    else
      state.npcClassEligible = nil
      state.npcClassSecret = nil
    end
  end
  return state.npcClass, state.npcClassSecret == true
end

local function PlainTrue(value)
  return issecretvalue(value) ~= true and (value == true or value == 1)
end

local function UnitIsNeutralForNPCType(unit)
  if not IsUnitToken(unit) then
    return false
  end
  if UnitSelectionType then
    local selection = SafeNumber(UnitSelectionType(unit))
    if selection ~= nil then
      return selection == 2
    end
  end
  if UnitReaction then
    return SafeNumber(UnitReaction(unit, "player")) == 4
  end
  return false
end

local function UnitHasMana(unit)
  if not IsUnitToken(unit) then
    return false
  end
  if UnitHasPowerType then
    return PlainTrue(UnitHasPowerType(unit, POWER_TYPE_MANA))
  end
  if UnitPowerType then
    local powerType = UnitPowerType(unit)
    return issecretvalue(powerType) ~= true and powerType == POWER_TYPE_MANA
  end
  return false
end

local function NPCTypeReferenceLevel()
  local instanceType
  if IsInInstance then
    local inInstance
    inInstance, instanceType = IsInInstance()
    if not PlainTrue(inInstance) or issecretvalue(instanceType) == true then
      instanceType = nil
    end
  end

  local referenceLevel
  if instanceType == "party" and GetMaxLevelForExpansionLevel and GetMaximumExpansionLevel then
    referenceLevel = SafeNumber(GetMaxLevelForExpansionLevel(GetMaximumExpansionLevel()))
  end
  if not referenceLevel and UnitEffectiveLevel then
    referenceLevel = SafeNumber(UnitEffectiveLevel("player"))
  end
  if referenceLevel ~= npcTypeReferenceLevel or instanceType ~= npcTypeReferenceInstanceType then
    npcTypeReferenceLevel = referenceLevel
    npcTypeReferenceInstanceType = instanceType
    npcTypeLieutenantLevel = nil
  end
  return referenceLevel
end

local function NPCEliteKind(unit)
  if not IsUnitToken(unit) then
    return nil
  end
  if UnitIsBossMob and PlainTrue(UnitIsBossMob(unit)) then
    return "npcBoss"
  end
  local level = UnitEffectiveLevel and SafeNumber(UnitEffectiveLevel(unit)) or nil
  if level == -1 then
    return "npcBoss"
  end

  local referenceLevel = NPCTypeReferenceLevel()
  if UnitIsLieutenant and PlainTrue(UnitIsLieutenant(unit)) then
    npcTypeLieutenantLevel = level
    return "npcMiniboss"
  end
  if level and referenceLevel then
    if level == referenceLevel + 1 then
      npcTypeLieutenantLevel = level
      return "npcMiniboss"
    elseif level == referenceLevel + 2 or (npcTypeLieutenantLevel and level == npcTypeLieutenantLevel + 1) then
      return "npcBoss"
    end
  end
  return UnitHasMana(unit) and "npcCaster" or "npcMelee"
end

local function UnitNPCClassificationKind(unit)
  if not IsUnitToken(unit) or not UnitClassification then
    return nil
  end
  local classification = UnitClassification(unit)
  if issecretvalue(classification) == true then
    return nil
  elseif classification == "worldboss" then
    return "npcBoss"
  elseif classification == "elite" then
    return NPCEliteKind(unit)
  elseif classification == "normal" or classification == "trivial" or classification == "minus" then
    return "npcRegular"
  end
  return nil
end

local function BossDisposition(unitState, unit)
  if unitState and unitState._bossDispositionReady == true then
    return unitState._bossDisposition
  end

  local disposition = "unknown"
  if UnitCanAttack then
    local attackable = UnitCanAttack("player", unit)
    if issecretvalue(attackable) ~= true and (attackable == true or attackable == 1) then
      disposition = "hostile"
    end
  end
  if disposition == "unknown" and UnitCanAssist then
    local assistable = UnitCanAssist("player", unit)
    if issecretvalue(assistable) ~= true and (assistable == true or assistable == 1) then
      disposition = "friendly"
    end
  end

  if unitState then
    unitState._bossDisposition = disposition
    unitState._bossDispositionReady = true
  end
  return disposition
end

local function UnitNPCKind(frame, unit, spec, forText, keyOverride)
  if not IsUnitToken(unit) then
    return nil
  end
  local health = spec and spec.health or {}
  local text = spec and spec.text or {}
  local typeColorEnabled, colorMode
  if forText then
    typeColorEnabled = text.npcTypeColorText
    colorMode = text.npcColorMode or health.npcColorMode
  else
    typeColorEnabled = health.npcTypeColorBar
    colorMode = health.npcColorMode
  end
  local key = keyOverride or spec and spec.key or frame.configKey
  local useType = false
  if colorMode == "type" and typeColorEnabled ~= false then
    local allowed = true
    if key == "target" then
      if forText then allowed = text.npcTypeTarget ~= false else allowed = health.npcTypeTarget ~= false end
    elseif key == "focus" then
      if forText then allowed = text.npcTypeFocus ~= false else allowed = health.npcTypeFocus ~= false end
    elseif key == "boss" then
      if forText then allowed = text.npcTypeBoss ~= false else allowed = health.npcTypeBoss ~= false end
    elseif key == "targettarget" or key == "focustarget" then
      if forText then allowed = text.npcTypeToT ~= false else allowed = health.npcTypeToT ~= false end
    end
    useType = allowed
  end

  local unitState = FreshUnitState and FreshUnitState(frame, unit)
  local readyKey = useType and "_npcKindTypeReady" or "_npcKindReactionReady"
  local valueKey = useType and "_npcKindType" or "_npcKindReaction"
  if unitState and unitState[readyKey] == true then
    return unitState[valueKey]
  end

  local kind
  local bossDisposition = key == "boss" and BossDisposition(unitState, unit) or nil
  if useType and bossDisposition ~= "friendly" and not UnitIsNeutralForNPCType(unit) then
    kind = UnitNPCClassificationKind(unit)
  end
  if not kind then
    local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
    if issecretvalue(dead) ~= true and dead then
      kind = "dead"
    elseif bossDisposition == "friendly" then
      kind = "friendly"
    elseif bossDisposition == "hostile" then
      kind = "enemy"
    elseif UnitReaction then
      local reaction = SafeNumber(UnitReaction(unit, "player"))
      if reaction and reaction >= 5 then
        kind = "friendly"
      elseif reaction and reaction == 4 then
        kind = "neutral"
      end
    end
  end
  kind = kind or "enemy"
  if unitState then
    unitState[readyKey] = true
    unitState[valueKey] = kind
  end
  return kind
end

local function ReadKnownUnitBool(api, unit, defaultValue)
  if not api then
    return defaultValue, false
  end
  local value = api(unit)
  if issecretvalue(value) == true or value == nil then
    return defaultValue, false
  end
  return value == true or value == 1, true
end

local function ReadUnitBool(api, unit, defaultValue)
  if not IsUnitToken(unit) then
    return defaultValue, false
  end
  return ReadKnownUnitBool(api, unit, defaultValue)
end

-- Core normally supplies both dispatch-cache readers. Standalone consumers
-- that intentionally load this shared primitive without Core still retain the
-- same secret-safe result contract instead of calling a nil optional helper.
ReadConnectedCached = ReadConnectedCached or function(_, unit)
  return ReadUnitBool(UnitIsConnected, unit, true)
end
ReadDeadCached = ReadDeadCached or function(_, unit)
  return ReadUnitBool(UnitIsDeadOrGhost, unit, false)
end

local function HealthModeNeedsIdentity(spec)
  local health = spec and spec.health
  local mode = health and health.mode
  return mode ~= "dark" and mode ~= "unified" and mode ~= "gradient"
end

local IDENTITY_STABLE_HEALTH_EVENTS = {
  UNIT_HEALTH = true,
  UNIT_MAXHEALTH = true,
  UNIT_MAX_HEALTH_MODIFIERS_CHANGED = true,
}

local function RefreshUnitState(frame, unit, spec, event)
  if not frame then
    return nil
  end
  unit = unit or frame.MSUFUnitKey
  local needsIdentity = HealthModeNeedsIdentity(spec)
  local state = frame._msufUnitState
  if not state then
    state = {}
    frame._msufUnitState = state
  elseif state.unit == unit and state.ready == true then
    local dispatchToken = frame._msufDispatchActive == true and frame._msufDispatchToken or nil
    local needsIdentityRefresh = needsIdentity == true and state.identityReady ~= true
    if dispatchToken and state.dispatchToken == dispatchToken and not needsIdentityRefresh then
      return state
    end
    if not needsIdentityRefresh and event == "UNIT_CONNECTION" then
      state.dispatchToken = dispatchToken
      state.connected, state.connectedKnown = ReadUnitBool(UnitIsConnected, unit, true)
      return state
    elseif not needsIdentityRefresh and event == "UNIT_FLAGS" then
      state.dispatchToken = dispatchToken
      state.dead, state.deadKnown = ReadUnitBool(UnitIsDeadOrGhost, unit, false)
      return state
    elseif not needsIdentityRefresh and (event == "UNIT_MAXHEALTH" or event == "UNIT_MAX_HEALTH_MODIFIERS_CHANGED") then
      state.dispatchToken = dispatchToken
      return state
    end
    if event ~= "UNIT_HEALTH"
      and event ~= "UNIT_POWER_FREQUENT"
      and event ~= "UNIT_POWER_UPDATE" then
    elseif needsIdentityRefresh then
    else
      return state
    end
  end

  local preserveIdentity = needsIdentity == true
    and IDENTITY_STABLE_HEALTH_EVENTS[event] == true
    and state.unit == unit
    and state.identityReady == true
    and state.isPlayerKnown == true
    and (state.isPlayer == true or state.npcKindKnown == true)
    and (state.npcClassEligible ~= true or state.npcClassSecret == true or state.npcClass ~= nil)
  local oldExists, oldExistsKnown = state.exists, state.existsKnown
  local oldDead, oldDeadKnown = state.dead, state.deadKnown
  local oldConnected, oldConnectedKnown = state.connected, state.connectedKnown
  local dispatchToken = frame._msufDispatchActive == true and frame._msufDispatchToken or nil
  state.unit = unit
  state.dispatchToken = dispatchToken
  -- Publish the state only after the volatile tuple has been refreshed. This
  -- prevents the dispatch cache from mistaking the prior event's values for a
  -- fresh state while RefreshUnitState itself is rebuilding the table.
  state.ready = false
  local validUnit = IsUnitToken(unit)
  if validUnit then
    state.exists, state.existsKnown = ReadUnitExistsCached(frame, unit)
    state.dead, state.deadKnown = ReadDeadCached(frame, unit)
    state.connected, state.connectedKnown = ReadConnectedCached(frame, unit)
  else
    state.exists, state.existsKnown = true, false
    state.dead, state.deadKnown = false, false
    state.connected, state.connectedKnown = true, false
  end
  state.ready = true

  if preserveIdentity and (
      oldExistsKnown ~= state.existsKnown
      or (state.existsKnown == true and oldExists ~= state.exists)
      or oldDeadKnown ~= state.deadKnown
      or (state.deadKnown == true and oldDead ~= state.dead)
      or oldConnectedKnown ~= state.connectedKnown
      or (state.connectedKnown == true and oldConnected ~= state.connected)) then
    preserveIdentity = false
  end

  if not preserveIdentity then
    state.isPlayer = false
    state.isPlayerKnown = false
    state.npcKind = nil
    state.npcKindKnown = false
    state.npcClass = nil
    state.npcClassRead = nil
    state.npcClassEligible = nil
    state.npcClassSecret = nil
    state._npcKindTypeReady = nil
    state._npcKindType = nil
    state._npcKindReactionReady = nil
    state._npcKindReaction = nil
    state._bossDispositionReady = nil
    state._bossDisposition = nil
    state.identityReady = nil
  end
  if needsIdentity and not preserveIdentity then
    if validUnit then
      local isPlayer
      isPlayer, state.isPlayerKnown = ReadUnitIsPlayerCached(frame, unit)
      state.isPlayer = isPlayer == true
    end
    if state.isPlayerKnown and not state.isPlayer then
      state.npcKind = UnitNPCKind(frame, unit, spec)
      state.npcKindKnown = state.npcKind ~= nil
      local health = spec and spec.health
      if health and health.npcClassColorBar == true and spec.key ~= "pet" and spec.key ~= "boss" then
        FriendlyNPCClassToken(state, frame, unit)
      end
    end
    state.identityReady = true
  elseif needsIdentity then
    state.identityReady = true
  end
  return state
end

local function NPCColor(kind)
  local fast = _G.MSUF_UFCore_GetNPCReactionColorFast
  if type(fast) == "function" then
    local r, g, b = fast(kind)
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
      return r, g, b
    end
  end
  if kind == "friendly" then return 0, 1, 0 end
  if kind == "neutral" then return 1, 1, 0 end
  if kind == "dead" then return 0.4, 0.4, 0.4 end
  if kind == "npcBoss" then return 0.74, 0.11, 0 end
  if kind == "npcMiniboss" then return 0.56, 0, 0.74 end
  if kind == "npcCaster" then return 0, 0.45, 0.74 end
  if kind == "npcMelee" then return 0.99, 0.99, 0.99 end
  if kind == "npcRegular" then return 0.70, 0.56, 0.33 end
  return 0.85, 0.10, 0.10
end

local healthGradientCurve
local HEALTH_GRADIENT_CURVE_CACHE_LIMIT = 8
local healthGradientCurveCache = {}
local healthGradientCurveCacheCount = 0
local healthGradientCurveCacheNext = 1
local function GradientStops(health)
  if type(health) == "table" then
    return tonumber(health.gradientLowR) or 1, tonumber(health.gradientLowG) or 0, tonumber(health.gradientLowB) or 0,
      tonumber(health.gradientMidR) or 1, tonumber(health.gradientMidG) or 1, tonumber(health.gradientMidB) or 0,
      tonumber(health.gradientHighR) or 0, tonumber(health.gradientHighG) or 1, tonumber(health.gradientHighB) or 0
  end
  return 1, 0, 0, 1, 1, 0, 0, 1, 0
end

local function CreateHealthGradientCurve(lr, lg, lb, mr, mg, mb, hr, hg, hb)
  if C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor then
    -- Unit/group specs normally share the same global gradient stops. Reuse
    -- their immutable native curve instead of creating three ColorMixins and
    -- one curve per frame/spec. Keep the cache bounded so live colour-slider
    -- previews cannot retain an unbounded number of intermediate curves.
    for i = 1, healthGradientCurveCacheCount do
      local cached = healthGradientCurveCache[i]
      if cached[1] == lr and cached[2] == lg and cached[3] == lb
        and cached[4] == mr and cached[5] == mg and cached[6] == mb
        and cached[7] == hr and cached[8] == hg and cached[9] == hb then
        return cached[10]
      end
    end

    local curve = C_CurveUtil.CreateColorCurve()
    curve:AddPoint(0, CreateColor(lr, lg, lb, 1))
    curve:AddPoint(0.5, CreateColor(mr, mg, mb, 1))
    curve:AddPoint(1, CreateColor(hr, hg, hb, 1))

    local entry = { lr, lg, lb, mr, mg, mb, hr, hg, hb, curve }
    if healthGradientCurveCacheCount < HEALTH_GRADIENT_CURVE_CACHE_LIMIT then
      healthGradientCurveCacheCount = healthGradientCurveCacheCount + 1
      healthGradientCurveCache[healthGradientCurveCacheCount] = entry
    else
      healthGradientCurveCache[healthGradientCurveCacheNext] = entry
      healthGradientCurveCacheNext = healthGradientCurveCacheNext + 1
      if healthGradientCurveCacheNext > HEALTH_GRADIENT_CURVE_CACHE_LIMIT then
        healthGradientCurveCacheNext = 1
      end
    end
    return curve
  end
  return false
end

local function HealthGradientCurve(health)
  local lr, lg, lb, mr, mg, mb, hr, hg, hb = GradientStops(health)
  if type(health) == "table" then
    if health._msufGradientCurve ~= nil
      and health._msufGradientLowR == lr and health._msufGradientLowG == lg and health._msufGradientLowB == lb
      and health._msufGradientMidR == mr and health._msufGradientMidG == mg and health._msufGradientMidB == mb
      and health._msufGradientHighR == hr and health._msufGradientHighG == hg and health._msufGradientHighB == hb then
      return health._msufGradientCurve
    end
    local curve = CreateHealthGradientCurve(lr, lg, lb, mr, mg, mb, hr, hg, hb)
    health._msufGradientCurve = curve
    health._msufGradientLowR, health._msufGradientLowG, health._msufGradientLowB = lr, lg, lb
    health._msufGradientMidR, health._msufGradientMidG, health._msufGradientMidB = mr, mg, mb
    health._msufGradientHighR, health._msufGradientHighG, health._msufGradientHighB = hr, hg, hb
    return curve
  end
  if healthGradientCurve ~= nil then
    return healthGradientCurve
  end
  healthGradientCurve = CreateHealthGradientCurve(lr, lg, lb, mr, mg, mb, hr, hg, hb)
  return healthGradientCurve
end

local function GradientFromValues(health, hp, maxHP)
  if issecretvalue(hp) == true or issecretvalue(maxHP) == true then
    return nil
  end
  hp = tonumber(hp)
  maxHP = tonumber(maxHP)
  if not hp or not maxHP or maxHP <= 0 then
    return nil
  end
  local pct = hp / maxHP
  if pct < 0 then
    pct = 0
  elseif pct > 1 then
    pct = 1
  end
  local lr, lg, lb, mr, mg, mb, hr, hg, hb = GradientStops(health)
  if pct <= 0.5 then
    local t = pct * 2
    return lr + (mr - lr) * t, lg + (mg - lg) * t, lb + (mb - lb) * t, true
  end
  local t = (pct - 0.5) * 2
  return mr + (hr - mr) * t, mg + (hg - mg) * t, mb + (hb - mb) * t, true
end

local function GradientColor(unit, calc, frame)
  local spec = frame and frame.MSUFSpec
  local health = spec and spec.health or nil
  -- Health.Apply seeds this for health-gradient frames. Text-only gradient
  -- consumers seed it on their first update. The spec apply path clears or
  -- replaces it, so the hot event path does not need nine stop comparisons.
  local curve = frame and frame._msufHealthGradientCurve
  if curve == nil then
    curve = HealthGradientCurve(health)
    if frame then frame._msufHealthGradientCurve = curve end
  end
  if calc and curve and calc.EvaluateCurrentHealthPercent then
    -- EvaluateCurrentHealthPercent owns the secret percentage evaluation.
    -- Passing GetCurrentHealthPercent() into curve:EvaluateUnpacked() is only
    -- allowed during untainted execution and breaks addon text updates.
    local color = calc:EvaluateCurrentHealthPercent(curve)
    if color and color.GetRGB then
      local r, g, b = color:GetRGB()
      return r, g, b, true
    end
  end
  if IsUnitToken(unit) and UnitHealthPercent and curve then
    -- Keep the curve inside UnitHealthPercent so Blizzard evaluates secret
    -- health in the permitted native context before exposing RGB components.
    local color = UnitHealthPercent(unit, true, curve)
    if color and color.GetRGB then
      local r, g, b = color:GetRGB()
      return r, g, b, true
    end
  end
  return 0.2, 0.8, 0.2, false
end

local function PreviewHealthGradientColor(health, pct)
  pct = Clamp01(pct, 1)
  local curve = HealthGradientCurve(health)
  if curve and curve.EvaluateUnpacked then
    local r, g, b = curve:EvaluateUnpacked(pct)
    if r ~= nil then
      return r, g, b, true
    end
  elseif curve and curve.Evaluate then
    local color = curve:Evaluate(pct)
    if color and color.GetRGB then
      local r, g, b = color:GetRGB()
      return r, g, b, true
    end
  end
  local r, g, b, raw = GradientFromValues(health, pct * 100, 100)
  if raw == true then
    return r, g, b, true
  end
  return 0.2, 0.8, 0.2, false
end

local function HealthColor(frame, unit, hp, maxHP, calc, event)
  local spec = frame and frame.MSUFSpec
  local health = spec and spec.health or {}
  local state = RefreshUnitState(frame, unit, spec, event or "UNIT_HEALTH")
  if state and state.existsKnown and state.exists == false then
    frame._msufHealthStatusGone = true
    return 0.28, 0.28, 0.28
  end
  if state and ((state.deadKnown and state.dead == true) or (state.connectedKnown and state.connected == false)) then
    frame._msufHealthStatusGone = true
    return 0.35, 0.35, 0.35
  end
  if frame then
    frame._msufHealthStatusGone = nil
  end

  if health.mode == "dark" or health.mode == "unified" then
    return health.r or 1, health.g or 1, health.b or 1
  elseif health.mode == "gradient" then
    return GradientColor(unit, calc, frame, hp, maxHP)
  end

  if spec and spec.key == "pet" then
    if health.petUsePlayerClassColor == true then
      return health.petPlayerClassR or 0.12, health.petPlayerClassG or 0.62, health.petPlayerClassB or 0.95
    elseif health.petColorEnabled == true then
      return health.petR or 0, health.petG or 0.8, health.petB or 0
    end
  end

  if state and state.isPlayerKnown and state.isPlayer then
    return DispatchClassColor(frame, unit, true)
  end

  if health.npcClassColorBar == true and spec and spec.key ~= "pet" and spec.key ~= "boss"
      and state and state.isPlayerKnown and not state.isPlayer then
    local class, secretClass = FriendlyNPCClassToken(state, frame, unit)
    if secretClass == true then
      if unit == "targettarget" or unit == "focustarget" then
        return class, nil, nil, SECRET_NATIVE_CLASS_COLOR
      end
      class = nil
    end
    local r, g, b = ClassColorForToken(class)
    if r ~= nil then
      return r, g, b
    end
  end

  local kind = state and state.npcKindKnown and state.npcKind or UnitNPCKind(frame, unit, spec)
  if kind then
    return NPCColor(kind)
  elseif UnitSelectionColor and IsUnitToken(unit) then
    local r, g, b = UnitSelectionColor(unit)
    if issecretvalue(r) ~= true and issecretvalue(g) ~= true and issecretvalue(b) ~= true and r ~= nil then
      return r, g, b
    end
  end
  return health.r or 0.1, health.g or 0.6, health.b or 0.9
end

local function ApplyHealthStatusColor(bar, frame, unit, hp, maxHP, calc, event)
  local spec = frame and frame.MSUFSpec
  local health = spec and spec.health or {}
  local r, g, b, raw = HealthColor(frame, unit, hp, maxHP, calc, event)
  if raw == SECRET_NATIVE_CLASS_COLOR then
    -- UnitClass can return an identity-restricted token for player units.
    -- C_ClassColor and SetStatusBarColor explicitly accept this secret
    -- pipeline; never inspect or retain the resulting RGB values.
    local classColor = C_ClassColor_GetClassColor and C_ClassColor_GetClassColor(r)
    if classColor then
      bar:SetStatusBarColor(classColor:GetRGB())
      bar._msufStatusR, bar._msufStatusG, bar._msufStatusB, bar._msufStatusA = nil, nil, nil, nil
      return true
    end
    r, g, b, raw = 0.12, 0.62, 0.95, nil
  end
  if health.mode == "gradient" and raw == true then
    if issecretvalue(r) == true or issecretvalue(g) == true or issecretvalue(b) == true then
      -- Restricted curve results cannot participate in Lua comparisons. Pass
      -- them straight through and invalidate the plain-value cache.
      bar:SetStatusBarColor(r, g, b, 1)
      bar._msufStatusR, bar._msufStatusG, bar._msufStatusB, bar._msufStatusA = nil, nil, nil, nil
    else
      -- Native curve APIs also return ordinary RGB outside restricted combat.
      -- Those values are safe to dedupe just like every other status color.
      ApplyStatusColor(bar, r, g, b)
    end
    frame._msufGradStashR, frame._msufGradStashG, frame._msufGradStashB = r, g, b
    frame._msufGradStashAt = GetTime and GetTime() or 0
    return true
  end
  ApplyStatusColor(bar, r, g, b)
  return false
end

local function ApplyBackgrounds(frame, health, power, force)
  local spec = frame and frame.MSUFSpec
  if not spec then
    return
  end
  if health == nil then health = true end
  if power == nil then power = true end
  local hb = spec.health and spec.health.background
  if health and frame.bg and hb then
    local r, g, b = hb.r, hb.g, hb.b
    if spec.health.backgroundClassColor == true then
      local bars = MSUF.Bars
      local resolveClass = bars and bars._ClassBackgroundColor
      if type(resolveClass) == "function" then
        r, g, b = resolveClass(frame, r, g, b)
      end
    elseif frame._msufHealthBgDynamic == true and frame.hpBar and frame.hpBar.GetStatusBarColor then
      local cr, cg, cb = frame.hpBar:GetStatusBarColor()
      if type(cr) == "number" and type(cg) == "number" and type(cb) == "number" then
        r, g, b = cr, cg, cb
      end
    end
    ApplyTextureColor(frame.bg, spec.health.backgroundTexture, r, g, b, hb.a or spec.backgroundAlpha or 0.9, force)
    frame._msufHPBgTex = spec.health.backgroundTexture
  end
  local pb = spec.power and spec.power.background
  if power and frame.powerBarBG and pb then
    local r, g, b = pb.r, pb.g, pb.b
    if frame._msufPowerBgDynamic == true and frame.hpBar and frame.hpBar.GetStatusBarColor then
      local cr, cg, cb = frame.hpBar:GetStatusBarColor()
      if type(cr) == "number" and type(cg) == "number" and type(cb) == "number" then
        r, g, b = cr, cg, cb
      end
    end
    ApplyTextureColor(frame.powerBarBG, spec.power.backgroundTexture, r, g, b, pb.a or spec.backgroundAlpha or 0.9, force)
    frame._msufPowerBgTex = spec.power.backgroundTexture
  end
end

local function PowerColor(frame, unit, powerType, token, metaKnown)
  local spec = frame and frame.MSUFSpec
  local powerSpec = spec and spec.power or {}
  if powerSpec.mode == "dark" or powerSpec.mode == "unified" or powerSpec.mode == "static" then
    return powerSpec.r or 0.1, powerSpec.g or 0.35, powerSpec.b or 0.95
  elseif powerSpec.mode == "class" then
    return DispatchClassColor(frame, unit)
  end

  local tokenKey, powerTypeKey
  if metaKnown == true then
    tokenKey = token
    powerTypeKey = powerType
  elseif IsUnitToken(unit) and UnitPowerType then
    powerType, token = UnitPowerType(unit)
    tokenKey = issecretvalue(token) ~= true and token or nil
    powerTypeKey = issecretvalue(powerType) ~= true and powerType or nil
  end
  local resolved = _G.MSUF_GetResolvedPowerColor
  if type(resolved) == "function" then
    local r, g, b = resolved(powerTypeKey, tokenKey)
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
      return r, g, b
    end
  end
  local override = powerSpec.colors and tokenKey ~= nil and powerSpec.colors[tokenKey] or nil
  if override then
    return override.r, override.g, override.b
  end
  local c = tokenKey ~= nil and PowerBarColor and PowerBarColor[tokenKey]
  if not c and powerTypeKey ~= nil then
    c = PowerBarColor and PowerBarColor[powerTypeKey]
  end
  if not c then
    c = PowerBarColor and PowerBarColor["MANA"]
  end
  return c and c.r or 0.2, c and c.g or 0.45, c and c.b or 1
end

MSUF.UFBarTextCommon = {
  UF = UF,
  CreateFrame = CreateFrame,
  UnitClass = UnitClass,
  UnitExists = UnitExists,
  UnitHealth = UnitHealth,
  UnitHealthMax = UnitHealthMax,
  UnitGetTotalAbsorbs = UnitGetTotalAbsorbs,
  UnitPower = UnitPower,
  UnitPowerMax = UnitPowerMax,
  UnitPowerType = UnitPowerType,
  UnitHealthPercent = UnitHealthPercent,
  UnitPowerPercent = UnitPowerPercent,
  AbbreviateNumbers = AbbreviateNumbers,
  BreakUpLargeNumbers = BreakUpLargeNumbers,
  AbbreviateLargeNumbers = AbbreviateLargeNumbers,
  InCombatLockdown = InCombatLockdown,
  UnitName = UnitName,
  UnitIsPlayer = UnitIsPlayer,
  UnitIsDeadOrGhost = UnitIsDeadOrGhost,
  UnitIsConnected = UnitIsConnected,
  UnitReaction = UnitReaction,
  UnitSelectionColor = UnitSelectionColor,
  PowerBarColor = PowerBarColor,
  RAID_CLASS_COLORS = RAID_CLASS_COLORS,
  type = type,
  tonumber = tonumber,
  format = format,
  byte = byte,
  sub = sub,
  abs = abs,
  floor = floor,
  max = max,
  GetTime = GetTime,
  C_Timer = C_Timer,
  StatusBarInterpolation = StatusBarInterpolation,
  SMOOTH_INTERP = SMOOTH_INTERP,
  WHITE = WHITE,
  SCALE_100 = SCALE_100,
  ABSORB_HEALTH_MODE_BASE = ABSORB_HEALTH_MODE_BASE,
  REVERSE_HEALTH_MODE = REVERSE_HEALTH_MODE,
  EMPTY_EVENTS = EMPTY_EVENTS,
  POWER_EVENTS = POWER_EVENTS,
  POWER_EVENTS_FREQUENT = POWER_EVENTS_FREQUENT,
  TEXT_EVENT_SETS = TEXT_EVENT_SETS,
  TEXT_EVENT_SETS_ABSORB = TEXT_EVENT_SETS_ABSORB,
  ClampFrameLayer = ClampFrameLayer,
  DrawSubLayer = DrawSubLayer,
  GetLayerBaseLevel = GetLayerBaseLevel,
  IsSecret = IsSecret,
  IsNil = IsNil,
  RefreshUnitState = RefreshUnitState,
  SetStatusTexture = SetStatusTexture,
  ApplyStatusColor = ApplyStatusColor,
  SetBarMinMax = SetBarMinMax,
  SetBarMinMaxKnown = SetBarMinMaxKnown,
  SetBarMinMaxPlain = SetBarMinMaxPlain,
  SetBarValue = SetBarValue,
  SetBarValueKnown = SetBarValueKnown,
  SetBarValuePlain = SetBarValuePlain,
  SnapBarInterpolation = SnapBarInterpolation,
  CreateLossTrail = CreateLossTrail,
  CreateLossTrailPool = CreateLossTrailPool,
  SetBarSmoothing = SetBarSmoothing,
  ApplyTextureColor = ApplyTextureColor,
  SetShownCached = SetShownCached,
  ApplyBarGradient = ApplyBarGradient,
  ApplyBarGradientToTarget = ApplyBarGradientToTarget,
  HideBarGradient = HideBarGradient,
  UpdateAllBarGradients = UpdateAllBarGradients,
  SetFrameLevelCached = SetFrameLevelCached,
  ExternalFrameWidth = ExternalFrameWidth,
  ClassColorForToken = ClassColorForToken,
  ClassColor = ClassColor,
  UnitNPCKind = UnitNPCKind,
  NPCColor = NPCColor,
  PrepareHealthGradientCurve = HealthGradientCurve,
  GradientColor = GradientColor,
  HealthGradientColorFromValues = GradientFromValues,
  PreviewHealthGradientColor = PreviewHealthGradientColor,
  HealthColor = HealthColor,
  ApplyHealthStatusColor = ApplyHealthStatusColor,
  ApplyBackgrounds = ApplyBackgrounds,
  PowerColor = PowerColor,
}
