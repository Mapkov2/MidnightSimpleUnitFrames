local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}

local UF = MSUF.UF
local CreateFrame = CreateFrame

-- Shared visual constants/helpers for unitframe elements.
-- Exports common API aliases, event lists, masks, and secret-safe helpers consumed by portrait,
-- border, alpha, and visual element files so they stay behaviorally aligned.
local UnitExists = UnitExists
local UnitThreatSituation = UnitThreatSituation
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
local IsNil = Secrets.IsNil or function(value) return value == nil end
local NotSecretValue = Secrets.NotSecret or function(_) return true end

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
  if frame._msufLastAlpha == alpha then
    local current = frame.GetAlpha and frame:GetAlpha()
    if current == nil or not NotSecretValue(current) or not AlphaDiffers(current, alpha) then
      return
    end
  end
  frame:SetAlpha(alpha)
  frame._msufLastAlpha = alpha
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
  local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or nil
  if token then
    frame._msufGroupRoleDispatchToken = token
    frame._msufGroupRoleDispatchUnit = unit
    frame._msufGroupRoleDispatchValue = role
  end
  return role
end

-- Borders run before corner indicators in the compiled event path. Resolve
-- their common group-aggro predicate once per dispatch; corners retain their
-- stricter combat gate and reuse this result when both visuals are enabled.
local function ResolveGroupAggroThreat(frame, unit, mode)
  if not (frame and unit and UnitThreatSituation) then return false end
  local token = frame._msufDispatchActive == true and frame._msufDispatchToken or nil
  if token
    and frame._msufGroupAggroDispatchToken == token
    and frame._msufGroupAggroDispatchUnit == unit
    and frame._msufGroupAggroDispatchMode == mode then
    return frame._msufGroupAggroDispatchValue == true
  end

  local active = true
  local exists = UnitExists and UnitExists(unit)
  if not IsNil(exists) and NotSecretValue(exists)
    and (exists == false or exists == 0) then
    active = false
  end
  if active and (mode == "TANK" or mode == "HEALER" or mode == "NON_TANK") then
    local role = ReadGroupRole(frame, unit)
    if IsNil(role) or not NotSecretValue(role)
      or (mode == "NON_TANK" and role == "TANK")
      or (mode ~= "NON_TANK" and role ~= mode) then
      active = false
    end
  end
  if active then
    local status = UnitThreatSituation(unit)
    if IsNil(status) or not NotSecretValue(status) then
      active = false
    else
      status = tonumber(status)
      active = status ~= nil and status >= 1
    end
  end

  if token then
    frame._msufGroupAggroDispatchToken = token
    frame._msufGroupAggroDispatchUnit = unit
    frame._msufGroupAggroDispatchMode = mode
    frame._msufGroupAggroDispatchValue = active
  end
  return active
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
  ResolveGroupAggroThreat = ResolveGroupAggroThreat,
}
