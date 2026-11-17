local addonName, MSUF = ...
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "MSUF_UF_Visuals_Common.lua")

local UF = MSUF.UF
local Appearance = {}
UF.Appearance = Appearance
local CreateFrame = CreateFrame

-- Shared visual constants/helpers for unitframe elements.
-- Exports common API aliases, event lists, masks, and secret-safe helpers consumed by portrait,
-- border, alpha, and visual element files so they stay behaviorally aligned.
local UnitExists = UnitExists
local UnitThreatSituation = UnitThreatSituation
local UnitAffectingCombat = UnitAffectingCombat
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitClass = UnitClass
local UnitReaction = UnitReaction
local SetPortraitTexture = SetPortraitTexture
local InCombatLockdown = InCombatLockdown
local tonumber = tonumber
local type = type
local pairs = pairs
local max = math.max
local abs = math.abs
local floor = math.floor
local Clamp01 = UF.Clamp01

local Secrets = MSUF.Secrets or {}
local IsNil = Secrets.IsNil
local NotSecretValue = Secrets.NotSecret

local EMPTY_EVENTS = {}
local PORTRAIT_2D_EVENTS = { "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_CONNECTION", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE" }
local BORDER_THREAT_EVENTS = { "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE" }
local WHITE = "Interface\\Buttons\\WHITE8x8"
local MEDIA_ROOT = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\"
local QUESTION_MARK = "Interface\\ICONS\\INV_Misc_QuestionMark"
local ADDON_PATH = "Interface\\AddOns\\" .. (addonName or "MidnightSimpleUnitFrames")
local PORTRAIT_MASKS = {
  SQUARE = WHITE,
  CIRCLE = ADDON_PATH .. "\\Media\\Masks\\circle_mask.tga",
  ROUNDED = ADDON_PATH .. "\\Media\\Masks\\rounded_mask.tga",
  DIAMOND = ADDON_PATH .. "\\Media\\Masks\\diamond_mask.tga",
}
local DYNAMIC_PORTRAIT_BORDER = {
  CLASS_COLOR = true,
  REACTION = true,
}
local QUEUED_2D_PORTRAIT_EVENTS = {
  UNIT_PORTRAIT_UPDATE = true,
  UNIT_MODEL_CHANGED = true,
  UNIT_CONNECTION = true,
  UNIT_ENTERED_VEHICLE = true,
  UNIT_EXITED_VEHICLE = true,
  MSUF_UNIT_IDENTITY_VISUAL = true,
  MSUF_UNIT_IDENTITY_SOFT = true,
  MSUF_UNIT_IDENTITY_SOFT_VISUAL = true,
}

local function SetShown(obj, show)
  if not obj then
    return
  end
  show = show == true
  if obj._msufShown == show then
    return
  end
  obj._msufShown = show
  if obj.SetShown then
    obj:SetShown(show)
  elseif show then
    obj:Show()
  else
    obj:Hide()
  end
end

local function AlphaDiffers(current, target)
  if type(current) ~= "number" then
    return true
  end
  return abs(current - target) > 0.001
end

local function SetFrameAlpha(frame, alpha)
  if not (frame and frame.SetAlpha) then
    return
  end
  alpha = Clamp01(alpha, 1)
  if frame._msufAppearance then
    Appearance.WriteNumber(frame, alpha, "_msufLastAlpha", true)
    return
  end
  if frame._msufLastAlpha == alpha then
    local current = frame.GetAlpha and frame:GetAlpha()
    if not NotSecretValue(current) or current == nil or not AlphaDiffers(current, alpha) then
      return
    end
  end
  frame:SetAlpha(alpha)
  frame._msufLastAlpha = alpha
end

-- Stable rendering parents, created before normal unitframe elements. External
-- anchors and the secure button retain ordinary alpha and their original parent.
function UF.EnsureHealthVisualRoot(frame, independent)
  local key = independent and "_msufHealthIndependentVisualRoot" or "_msufHealthVisualRoot"
  if frame[key] then return frame[key] end
  if InCombatLockdown and InCombatLockdown() then return nil end
  local root = PixelLayoutRegion(CreateFrame("Frame", nil, frame))
  root:SetAllPoints(frame)
  root:SetFrameLevel(frame:GetFrameLevel())
  root:EnableMouse(false)
  if independent then root:SetIgnoreParentAlpha(true) end
  frame[key] = root
  if frame._msufLoadHealthAlphaApply then frame._msufLoadHealthAlphaApply(frame) end
  return root
end

local function SetAlphaCached(obj, alpha, field, force)
  if not (obj and obj.SetAlpha) then
    return
  end
  alpha = Clamp01(alpha, 1)
  field = field or "_msufAlpha"
  if force or obj[field] == nil or AlphaDiffers(obj[field], alpha) then
    obj:SetAlpha(alpha)
    obj[field] = alpha
  end
end

local function ReadGroupRole(frame, unit)
  local token = frame and frame._msufDispatchActive == true and frame._msufDispatchToken or nil
  if token
    and frame._msufGroupRoleDispatchToken == token
    and frame._msufGroupRoleDispatchUnit == unit then
    return frame._msufGroupRoleDispatchValue
  end
  local role
  if UnitGroupRolesAssigned then role = UnitGroupRolesAssigned(unit) end
  if not NotSecretValue(role) then role = nil end
  if token then
    frame._msufGroupRoleDispatchToken = token
    frame._msufGroupRoleDispatchUnit = unit
    frame._msufGroupRoleDispatchValue = role
  end
  return role
end

local function GroupAggroModeNeedsRole(mode)
  return mode == "TANK" or mode == "HEALER" or mode == "NON_TANK"
end

local function GroupAggroModeAllowsRole(mode, role)
  if not GroupAggroModeNeedsRole(mode) then return true end
  if IsNil(role) or not NotSecretValue(role) then return false end
  if mode == "NON_TANK" then return role ~= "TANK" end
  return role == mode
end

local function GroupAggroModeAllows(frame, unit, mode)
  if not GroupAggroModeNeedsRole(mode) then return true end
  local role = ReadGroupRole(frame, unit)
  return GroupAggroModeAllowsRole(mode, role)
end

-- Visible secure group children already own an exact RegisterUnitEvent token.
-- UnitThreatSituation returning nil is therefore also the cheapest missing-unit
-- gate; a separate UnitExists call only duplicated work on every threat event.
local function ReadGroupAggroThreat(unit)
  if not (unit and UnitThreatSituation) then return false end
  local status = UnitThreatSituation(unit)
  if IsNil(status) or not NotSecretValue(status) then return false end
  status = tonumber(status)
  if status == nil or status < 1 then return false end
  -- Threat can lag behind the member's combat flag at the end of a fight.
  -- Only a known out-of-combat result overrides a positive threat state.
  local active = UnitAffectingCombat and UnitAffectingCombat(unit)
  return not NotSecretValue(active) or (active ~= false and active ~= 0)
end

-- Flat group hotpath: read threat once, read role at most once, and derive
-- both enabled visual consumers from those two values. Border and corner modes
-- may differ, so returning a pair preserves their independent configuration
-- without re-entering UnitThreatSituation.
local function ResolveGroupAggroPair(frame, unit, borderMode, cornerMode)
  if not ReadGroupAggroThreat(unit) then return false, false end
  local role
  if GroupAggroModeNeedsRole(borderMode) or GroupAggroModeNeedsRole(cornerMode) then
    role = ReadGroupRole(frame, unit)
  end
  local border = borderMode ~= nil and GroupAggroModeAllowsRole(borderMode, role) or false
  local corner = cornerMode ~= nil and GroupAggroModeAllowsRole(cornerMode, role) or false
  return border, corner
end

-- Mixed event routes share the raw result even when border and corner modes differ.
local function ResolveGroupAggroThreat(frame, unit, mode)
  if not (frame and unit and UnitThreatSituation) then return false end
  local token = frame._msufDispatchActive == true and frame._msufDispatchToken or nil
  local active
  if token
    and frame._msufGroupAggroDispatchToken == token
    and frame._msufGroupAggroDispatchUnit == unit then
    active = frame._msufGroupAggroDispatchValue
  else
    -- Apply and identity refresh can run before the unit is present.
    local exists = UnitExists and UnitExists(unit)
    active = not (NotSecretValue(exists) and (exists == false or exists == 0))
      and ReadGroupAggroThreat(unit)
    if token then
      frame._msufGroupAggroDispatchToken = token
      frame._msufGroupAggroDispatchUnit = unit
      frame._msufGroupAggroDispatchValue = active
    end
  end
  return active and GroupAggroModeAllows(frame, unit, mode)
end

MSUF.UFVisuals = {
  UF = UF,
  CreateFrame = CreateFrame,
  UnitExists = UnitExists,
  UnitThreatSituation = UnitThreatSituation,
  UnitGroupRolesAssigned = UnitGroupRolesAssigned,
  UnitClass = UnitClass,
  UnitReaction = UnitReaction,
  SetPortraitTexture = SetPortraitTexture,
  InCombatLockdown = InCombatLockdown,
  tonumber = tonumber,
  type = type,
  pairs = pairs,
  max = max,
  floor = floor,
  IsNil = IsNil,
  NotSecretValue = NotSecretValue,
  EMPTY_EVENTS = EMPTY_EVENTS,
  PORTRAIT_2D_EVENTS = PORTRAIT_2D_EVENTS,
  BORDER_THREAT_EVENTS = BORDER_THREAT_EVENTS,
  WHITE = WHITE,
  MEDIA_ROOT = MEDIA_ROOT,
  QUESTION_MARK = QUESTION_MARK,
  ADDON_PATH = ADDON_PATH,
  PORTRAIT_MASKS = PORTRAIT_MASKS,
  DYNAMIC_PORTRAIT_BORDER = DYNAMIC_PORTRAIT_BORDER,
  QUEUED_2D_PORTRAIT_EVENTS = QUEUED_2D_PORTRAIT_EVENTS,
  SetShown = SetShown,
  Clamp01 = Clamp01,
  SetFrameAlpha = SetFrameAlpha,
  SetAlphaCached = SetAlphaCached,
  ReadGroupAggroThreat = ReadGroupAggroThreat,
  GroupAggroModeAllows = GroupAggroModeAllows,
  ResolveGroupAggroPair = ResolveGroupAggroPair,
  ResolveGroupAggroThreat = ResolveGroupAggroThreat,
}

-- One finite spring driver for appearance only. Root writers retain their
-- pre-animation inputs; slider, range and combat updates never reuse a painted
-- (possibly secret) alpha as the next target.
do
  local Motion = Appearance
  local StepSpring, SpringDecay = MSUF.Util.StepSpring, MSUF.Util.SpringDecay
  local GeneralDB = MSUF.Require("MSUF_GetGeneralDB", "MSUF_UF_Visuals_Common.lua")
  local PublicGlobals = MSUF.PublicGlobals
  local active, driver, reduced = {}, nil, false

  local function Paint(state)
    local frame, progress = state.frame, state.value
    if state.mode == 1 then
      local alpha = state.alpha * progress
      if state.painted ~= alpha then frame:SetAlpha(alpha) state.painted = alpha end
    elseif state.mode == 2 then
      frame:SetAlphaFromBoolean(state.boolean, state.inAlpha * progress, state.outAlpha * progress)
      state.painted = nil
    else
      local selected = Motion.EvaluateBoolean(state.boolean, state.inAlpha * progress, state.outAlpha * progress)
      frame:SetAlphaFromBoolean(state.checked, selected, state.fallback * progress)
      state.painted = nil
    end
  end

  local function Remove(state)
    local index = state.index
    if not index then return end
    local last, tail = #active, active[#active]
    active[last] = nil
    if index ~= last then active[index], tail.index = tail, index end
    state.index = nil
    if last == 1 then driver:SetScript("OnUpdate", nil) end
  end

  local function Finish(state)
    Remove(state)
    state.value, state.velocity, state.age = 1, 0, 0
    Paint(state)
  end

  local function Update(_, elapsed)
    local decay = SpringDecay(50, elapsed)
    for index = #active, 1, -1 do
      local state = active[index]
      state.age = state.age + elapsed
      state.value, state.velocity = StepSpring(state.value, state.velocity, 1, 50, elapsed, decay)
      if state.age >= 0.25 or (abs(1 - state.value) < 0.002 and abs(state.velocity) < 0.02) then
        Finish(state)
      else
        Paint(state)
      end
    end
  end

  function Motion.UpdateSettings()
    local general = GeneralDB()
    reduced = general ~= nil and (general.reduceMotion == true or general.reducedMotion == true)
    if reduced then
      for index = #active, 1, -1 do Finish(active[index]) end
    end
  end

  function Motion.Cancel(frame)
    local state = frame._msufAppearance
    if state then Finish(state) end
  end

  function Motion.Begin(frame)
    local state = frame._msufAppearance
    if not state or state.index or reduced or PublicGlobals.MSUF_UnitEditModeActive == true then return false end
    if frame._msufDisabledByConfig == true or not frame:IsVisible() then return false end
    if frame._msufIsGroupFrame and MSUF.GF.IsHeaderLayoutRebindActive(frame) then return false end
    if not driver then driver = CreateFrame("Frame") end
    state.value, state.velocity, state.age, state.painted = 0, 0, 0, nil
    Paint(state)
    state.index = #active + 1
    active[state.index] = state
    if #active == 1 then driver:SetScript("OnUpdate", Update) end
    return true
  end

  function Motion.Configure(frame, cfg)
    Motion.UpdateSettings()
    local state = frame._msufAppearance
    if not (cfg and (cfg.fadeIn == true or cfg.fadeInOnShow == true)) then
      if state then Finish(state) frame._msufAppearance = nil end
      return
    end
    if state then return end
    state = frame._msufAppearanceCache
    if not state then
      state = { frame = frame, mode = 1, alpha = 1, value = 1, velocity = 0, age = 0 }
      frame._msufAppearanceCache = state
      frame:HookScript("OnShow", Motion.Begin)
      frame:HookScript("OnHide", Motion.Cancel)
    end
    state.mode = 1
    state.alpha = (frame._msufIsGroupFrame and frame._msufGFRangeFrameAlpha) or frame._msufLastAlpha or 1
    state.boolean, state.checked, state.fallback, state.painted = nil, nil, nil, nil
    frame._msufAppearance = state
    if frame._msufIsPreview or frame._msufPreviewScope or frame._msufGFIsPreviewFrame then Motion.Begin(frame) end
  end

  function Motion.WriteNumber(frame, alpha, field, verifyCurrent)
    local state = frame._msufAppearance
    if verifyCurrent then
      if state.index then state.painted = nil
      elseif state.painted == alpha then
        local current = frame:GetAlpha()
        if NotSecretValue(current) and current ~= nil and AlphaDiffers(current, alpha) then state.painted = nil end
      end
    end
    state.mode, state.alpha = 1, alpha
    frame[field] = alpha
    Paint(state)
  end

  function Motion.WriteBoolean(frame, value, inAlpha, outAlpha, checked, fallback, checkedSecret)
    local state = frame._msufAppearance
    state.mode = checkedSecret == true and 3 or 2
    state.boolean, state.inAlpha, state.outAlpha = value, inAlpha, outAlpha
    state.checked, state.fallback = checked, fallback
    Paint(state)
  end

end
