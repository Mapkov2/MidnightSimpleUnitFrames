local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}

MSUF.UF = MSUF.UF or {}

--- UnitFrames/Engine/MSUF_UF_Runtime.lua
---
--- Warm runtime scheduler for unit frames. This file handles deferred element
--- refreshes, profile/config invalidation, identity coalescing,
--- and post-combat reanchors. It should coordinate work that is too broad for
--- Dispatch hot handlers but still needs to happen without a full /reload.

local UF = MSUF.UF
local Metadata = UF.Metadata or {}
local type = type
local tostring = tostring
local tonumber = tonumber
local next = next
local CreateFrame = CreateFrame
local pairs = pairs
local InCombatLockdown = InCombatLockdown
local math_floor = math.floor
local UnitExists = UnitExists
local UnitGUID = UnitGUID
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitName = UnitName
local UnitIsConnected = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitAffectingCombat = UnitAffectingCombat
local issecretvalue = _G.issecretvalue or function(_) return false end

local EMPTY_METADATA_SET = {}
local ApplyElementToFrame = UF.ApplyElementToFrame
local DEFERRED_REFRESH_ALL = "*"

--- Element refreshes can be requested while config is dirty or combat prevents
--- a safe apply. Queue by unit/config-key so multiple option changes collapse
--- into one element reapply on the deferred driver.
local function QueueDeferredElementRefresh(unit, names, updateReason)
  local pending = UF.pendingElementRefreshes
  local key = unit or DEFERRED_REFRESH_ALL
  if key == DEFERRED_REFRESH_ALL then
    for existing in pairs(pending) do
      pending[existing] = nil
    end
  elseif pending[DEFERRED_REFRESH_ALL] then
    key = DEFERRED_REFRESH_ALL
  end
  local entry = pending[key]
  if not entry then
    entry = { names = {} }
    pending[key] = entry
  end
  local set = entry.names
  for i = 1, #names do
    set[names[i]] = true
  end
  entry.reason = updateReason or entry.reason or "MSUF_DEFERRED_REFRESH"
  local factory = UF.Factory
  if factory and factory.EnsureDeferredDriver then
    factory.EnsureDeferredDriver()
  end
  return false
end

local function BuildDeferredRefreshList(entry)
  local list = entry.list
  if not list then
    list = {}
    entry.list = list
  end
  local n = 0
  local set = entry.names
  for i = 1, #UF.elementOrder do
    local name = UF.elementOrder[i]
    if set[name] == true then
      n = n + 1
      list[n] = name
    end
  end
  for i = n + 1, #list do
    list[i] = nil
  end
  return list
end

--- Elements whose Apply only touches insecure child frames and regions (bars,
--- font strings, textures). Insecure SetPoint/SetSize/Show on those is legal
--- during combat lockdown, so they may apply immediately (combat-reload fix).
--- Everything else (RegisterUnitWatch, secure visibility, protected sizing)
--- must keep waiting for the post-combat driver.
local COMBAT_SAFE_ELEMENTS = {
  Power = true,
  Text = true,
  PowerText = true,
}

function UF.RefreshElements(unit, names, updateReason)
  if type(names) ~= "table" then
    return false
  end
  if InCombatLockdown and InCombatLockdown() then
    local safeNames, deferredNames
    for i = 1, #names do
      local name = names[i]
      if COMBAT_SAFE_ELEMENTS[name] == true then
        safeNames = safeNames or {}
        safeNames[#safeNames + 1] = name
      else
        deferredNames = deferredNames or {}
        deferredNames[#deferredNames + 1] = name
      end
    end
    if deferredNames then
      QueueDeferredElementRefresh(unit, deferredNames, updateReason)
    end
    if not safeNames then
      return false
    end
    names = safeNames
  end
  local refreshedAll = false
  if not unit and UF.Config and UF.Config.Refresh then
    UF.Config.Refresh()
    refreshedAll = true
  end
  local function refreshFrame(frame)
    if not frame then
      return
    end
    local spec
    if refreshedAll and UF.Config and UF.Config.GetSpec then
      spec = UF.Config.GetSpec(frame.unit)
    elseif UF.Config and UF.Config.RefreshUnit then
      spec = UF.Config.RefreshUnit(frame.unit)
    elseif UF.Config and UF.Config.GetSpec then
      spec = UF.Config.GetSpec(frame.unit)
    else
      spec = frame.MSUFSpec
    end
    for i = 1, #names do
      ApplyElementToFrame(frame, names[i], spec, updateReason or "MSUF_ELEMENT_REFRESH")
    end
  end
  if unit then
    local units = UF.UnitsForConfigKey(unit)
    if not units then
      return false
    end
    for i = 1, #units do
      refreshFrame(UF.frames[units[i]])
    end
    return true
  end
  UF.ForEachFrame(refreshFrame)
  return true
end

function UF.FlushDeferredRefreshes()
  if InCombatLockdown and InCombatLockdown() then
    return false
  end
  local pending = UF.pendingElementRefreshes
  local any = false
  for key, entry in pairs(pending) do
    pending[key] = nil
    local unit = key ~= DEFERRED_REFRESH_ALL and key or nil
    local names = BuildDeferredRefreshList(entry)
    if #names > 0 then
      UF.RefreshElements(unit, names, entry.reason or "MSUF_DEFERRED_REFRESH")
      any = true
    end
  end
  return any
end

function UF.MarkDirty(unit)
  if unit then
    local units = UF.UnitsForConfigKey(unit)
    if not units then
      return
    end
    for i = 1, #units do
      UF.pendingApply[units[i]] = true
    end
    return
  end
  for i = 1, #UF.unitOrder do
    UF.pendingApply[UF.unitOrder[i]] = true
  end
end

function UF.ApplyDirty()
  local factory = UF.Factory
  if not (factory and factory.Apply) then
    return false
  end
  for unit in pairs(UF.pendingApply) do
    UF.pendingApply[unit] = nil
    factory.Apply(unit)
  end
  return true
end

function UF.RequestReanchorAfterCombat()
  if InCombatLockdown and InCombatLockdown() then
    UF.MarkDirty(nil)
    local factory = UF.Factory
    if factory and factory.EnsureDeferredDriver then
      factory.EnsureDeferredDriver()
    end
    return false
  end
  return UF.Apply(nil)
end

local function GetUnitFrameScreenCacheKey(key, unit)
  local k = tostring(key or "")
  local u = tostring(unit or "")
  if k == "" then return u ~= "" and u or nil end
  if k == "boss" and u ~= "" then return k .. ":" .. u end
  return k
end

local function GetUnitFrameScreenCacheBucket()
  local fn = _G.MSUF_GetProfileScopedCache
  if type(fn) ~= "function" then return nil end
  return fn("unitFrameScreenCache")
end

local function GetFramePoint(frame, point)
  if not frame then return nil, nil, nil end
  point = point or "CENTER"
  if point == "CENTER" and frame.GetCenter then
    local x, y = frame:GetCenter()
    return x, y, "CENTER"
  end
  if not frame.GetLeft or not frame.GetRight or not frame.GetTop or not frame.GetBottom then
    if frame.GetCenter then
      local x, y = frame:GetCenter()
      return x, y, "CENTER"
    end
    return nil, nil, nil
  end

  local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
  if not l or not r or not t or not b then
    if frame.GetCenter then
      local x, y = frame:GetCenter()
      return x, y, "CENTER"
    end
    return nil, nil, nil
  end

  local cx = (l + r) * 0.5
  local cy = (t + b) * 0.5
  if point == "TOPLEFT" then return l, t, point end
  if point == "TOP" then return cx, t, point end
  if point == "TOPRIGHT" then return r, t, point end
  if point == "LEFT" then return l, cy, point end
  if point == "RIGHT" then return r, cy, point end
  if point == "BOTTOMLEFT" then return l, b, point end
  if point == "BOTTOM" then return cx, b, point end
  if point == "BOTTOMRIGHT" then return r, b, point end
  return cx, cy, "CENTER"
end

local function CacheUnitFrameScreenPosition(frame, key, unit, point, allowLocked)
  local uiParent = _G.UIParent
  if not frame or not key or not uiParent or not uiParent.GetCenter then return false end
  if allowLocked ~= true and InCombatLockdown and InCombatLockdown() then return false end

  point = point or frame._msufHardLockPoint or "CENTER"
  local fx, fy, usedPoint = GetFramePoint(frame, point)
  local ux, uy = uiParent:GetCenter()
  if not fx or not fy or not ux or not uy then return false end

  local fs = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
  local us = (uiParent.GetEffectiveScale and uiParent:GetEffectiveScale()) or 1
  if fs == 0 then fs = 1 end
  if us == 0 then us = 1 end

  local id = GetUnitFrameScreenCacheKey(key, unit)
  local bucket = GetUnitFrameScreenCacheBucket()
  if not id or not bucket then return false end

  local w = frame.GetWidth and frame:GetWidth() or nil
  local h = frame.GetHeight and frame:GetHeight() or nil
  bucket[id] = {
    v = 3,
    x = math_floor(((fx * fs - ux * us) / us) + 0.5),
    y = math_floor(((fy * fs - uy * us) / us) + 0.5),
    w = w,
    h = h,
    scale = frame.GetScale and frame:GetScale() or nil,
    point = usedPoint or point or "CENTER",
  }
  return true
end

local function ApplyCachedUnitFrameScreenPosition(frame, key, unit)
  local uiParent = _G.UIParent
  if not frame or not key or not uiParent then return false end
  local bucket = GetUnitFrameScreenCacheBucket()
  local id = GetUnitFrameScreenCacheKey(key, unit)
  local cached = bucket and id and bucket[id]
  if type(cached) ~= "table" or (cached.v ~= 2 and cached.v ~= 3) then return false end
  local x, y = tonumber(cached.x), tonumber(cached.y)
  if not x or not y then return false end

  if cached.v == 3 and frame.SetScale and tonumber(cached.scale) then
    frame:SetScale(tonumber(cached.scale))
  end

  local point = cached.point
  if type(point) ~= "string" or point == "" then point = "CENTER" end
  frame:ClearAllPoints()
  frame:SetPoint(point, uiParent, "CENTER", math_floor(x + 0.5), math_floor(y + 0.5))
  frame._msufPositionInitialized = true
  frame._msufHardLockedToUIParent = true
  frame._msufHardLockPoint = point
  frame._msufLoadedFromScreenCache = true
  return true
end

local DependentIdentityGuidChanged
local SyncRuntimeDriver
local DEPENDENT_UNIT_TICK_REASON = "MSUF_UNIT_IDENTITY_SOFT_FAST"
local DEPENDENT_UNITS = { "targettarget", "focustarget" }

local function RuntimeFrame(unit)
  local frames = UF.frames
  local frame = frames and frames[unit]
  local spec = frame and frame.MSUFSpec
  local active = frame and frame._msufActiveElements
  if frame and active and next(active) ~= nil and not (spec and spec.enabled == false) then
    return frame
  end
  return nil
end

local IDENTITY_DRIVER_ELEMENTS = {
  LoadConditions = true,
  Health = true,
  Power = true,
  Text = true,
  NameText = true,
  HealthText = true,
  PowerText = true,
  InlineToT = true,
  Portrait = true,
  StatusIndicators = true,
  RaidMarkerIndicator = true,
  LeaderIndicator = true,
  LevelIndicator = true,
  RaidGroupIndicator = true,
  EliteIndicator = true,
  StatusTextIndicator = true,
  CombatIndicator = true,
  RestingIndicator = true,
  IncomingResIndicator = true,
  PVPIndicator = true,
  Prediction = true,
  Alpha = true,
  Borders = true,
  Auras = true,
  GroupStatusRuntime = true,
  GroupVisuals = true,
  GroupCornerIndicators = true,
}

local function FrameNeedsIdentityDriver(frame)
  local active = frame and frame._msufActiveElements
  if not active then
    return false
  end
  for name in pairs(active) do
    if IDENTITY_DRIVER_ELEMENTS[name] == true then
      return true
    end
  end
  return false
end

local function IdentityRuntimeFrame(unit)
  local frame = RuntimeFrame(unit)
  if frame and FrameNeedsIdentityDriver(frame) then
    return frame
  end
  return nil
end

local function RunRuntimeFrame(frame, reason)
  local update = UF.FrameRuntimeUpdate
  if update then
    return update(frame, reason)
  end
  return frame and UF.UpdateRuntime(frame.unit, reason)
end

local function UnitExistsPlain(unit)
  if not UnitExists then
    return true
  end
  local exists = UnitExists(unit)
  if issecretvalue(exists) == true then
    return true
  end
  return exists == true or exists == 1
end

local function PlainUnitValue(fn, unit)
  if not fn then
    return nil, false
  end
  local value = fn(unit)
  if issecretvalue(value) == true then
    return nil, true
  end
  return value, false
end

local DEP_POLL_HEALTH = 1
local DEP_POLL_POWER = 2
local DEP_POLL_NAME = 4
local DEP_POLL_STATUS = 8
local DEP_POLL_COMBAT = 16
local DEP_POLL_ALL = DEP_POLL_HEALTH + DEP_POLL_POWER + DEP_POLL_NAME + DEP_POLL_STATUS + DEP_POLL_COMBAT

-- ToT/FoT do not receive normal unit events. Poll only the state buckets that
-- active elements can consume instead of sampling every unit API every tick.
local function DependentPollMask(frame)
  local active = frame and frame._msufActiveElements
  if not active then
    return DEP_POLL_ALL
  end

  local needHealth = active.Health or active.HealthText or active.Prediction or active.StatusTextIndicator
  local needPower = active.Power or active.PowerText
  local needName = active.NameText or active.InlineToT
  local needStatus = active.Health or active.NameText or active.StatusTextIndicator
    or active.PVPIndicator or active.GroupStatusRuntime
  local needCombat = active.CombatIndicator or active.Alpha or active.Borders
  if active.Auras or active.Portrait or active.RaidMarkerIndicator or active.LeaderIndicator
    or active.LevelIndicator or active.RaidGroupIndicator or active.EliteIndicator
    or active.IncomingResIndicator or active.RestingIndicator or active.LoadConditions then
    needStatus = true
  end

  local mask = 0
  if needHealth then mask = mask + DEP_POLL_HEALTH end
  if needPower then mask = mask + DEP_POLL_POWER end
  if needName then mask = mask + DEP_POLL_NAME end
  if needStatus then mask = mask + DEP_POLL_STATUS end
  if needCombat then mask = mask + DEP_POLL_COMBAT end
  if mask == 0 then
    return DEP_POLL_STATUS
  end
  return mask
end

local function ClearDependentPollCache(frame)
  if not frame then return end
  frame._msufDependentPollGUID = nil
  frame._msufDependentPollHP = nil
  frame._msufDependentPollMaxHP = nil
  frame._msufDependentPollPower = nil
  frame._msufDependentPollMaxPower = nil
  frame._msufDependentPollPowerType = nil
  frame._msufDependentPollName = nil
  frame._msufDependentPollConnected = nil
  frame._msufDependentPollDead = nil
  frame._msufDependentPollCombat = nil
end

local function DependentUnitPollStateChanged(frame, unit)
  local guid = frame._msufIdentityGUID
  if guid == false then
    return true
  end

  local mask = DependentPollMask(frame)
  local maskChanged = frame._msufDependentPollMask ~= mask
  if maskChanged then
    frame._msufDependentPollMask = mask
    ClearDependentPollCache(frame)
  end

  local hp, hpSecret, maxHP, maxSecret
  local power, powerSecret, maxPower, maxPowerSecret, powerType, powerTypeSecret
  local name, nameSecret
  local connected, connectedSecret, dead, deadSecret
  local combat, combatSecret

  if mask % (DEP_POLL_HEALTH * 2) >= DEP_POLL_HEALTH then
    hp, hpSecret = PlainUnitValue(UnitHealth, unit)
    maxHP, maxSecret = PlainUnitValue(UnitHealthMax, unit)
  end
  if mask % (DEP_POLL_POWER * 2) >= DEP_POLL_POWER then
    power, powerSecret = PlainUnitValue(UnitPower, unit)
    maxPower, maxPowerSecret = PlainUnitValue(UnitPowerMax, unit)
    powerType, powerTypeSecret = PlainUnitValue(UnitPowerType, unit)
  end
  if mask % (DEP_POLL_NAME * 2) >= DEP_POLL_NAME then
    name, nameSecret = PlainUnitValue(UnitName, unit)
  end
  if mask % (DEP_POLL_STATUS * 2) >= DEP_POLL_STATUS then
    connected, connectedSecret = PlainUnitValue(UnitIsConnected, unit)
    dead, deadSecret = PlainUnitValue(UnitIsDeadOrGhost, unit)
  end
  if mask % (DEP_POLL_COMBAT * 2) >= DEP_POLL_COMBAT then
    combat, combatSecret = PlainUnitValue(UnitAffectingCombat, unit)
  end

  if hpSecret or maxSecret or powerSecret or maxPowerSecret or powerTypeSecret
    or nameSecret or connectedSecret or deadSecret or combatSecret then
    return true
  end

  local changed = maskChanged
    or frame._msufDependentPollGUID ~= guid
    or frame._msufDependentPollHP ~= hp
    or frame._msufDependentPollMaxHP ~= maxHP
    or frame._msufDependentPollPower ~= power
    or frame._msufDependentPollMaxPower ~= maxPower
    or frame._msufDependentPollPowerType ~= powerType
    or frame._msufDependentPollName ~= name
    or frame._msufDependentPollConnected ~= connected
    or frame._msufDependentPollDead ~= dead
    or frame._msufDependentPollCombat ~= combat

  frame._msufDependentPollGUID = guid
  frame._msufDependentPollHP = hp
  frame._msufDependentPollMaxHP = maxHP
  frame._msufDependentPollPower = power
  frame._msufDependentPollMaxPower = maxPower
  frame._msufDependentPollPowerType = powerType
  frame._msufDependentPollName = name
  frame._msufDependentPollConnected = connected
  frame._msufDependentPollDead = dead
  frame._msufDependentPollCombat = combat
  return changed
end

local function RunDependentUnitImmediate(unit)
  local frame = IdentityRuntimeFrame(unit)
  if not frame then
    return false
  end
  local spec = frame.MSUFSpec
  if spec and spec.enabled == false then
    return false
  end
  if _G.MSUF_PreviewTestMode ~= true
    and frame.IsShown
    and not frame:IsShown() then
    return false
  end
  if not UnitExistsPlain(unit) then
    RunRuntimeFrame(frame, "MSUF_UNIT_IDENTITY_SOFT")
    return true
  end
  local guidChanged = DependentIdentityGuidChanged(frame, unit)
  if guidChanged ~= false then
    RunRuntimeFrame(frame, "MSUF_UNIT_IDENTITY_SOFT")
    return true
  end
  if DependentUnitPollStateChanged(frame, unit) then
    RunRuntimeFrame(frame, DEPENDENT_UNIT_TICK_REASON)
    return true
  end
  return false
end

local function RunDependentUnitsForParent(parent)
  if parent == "target" then
    return RunDependentUnitImmediate("targettarget")
  elseif parent == "focus" then
    return RunDependentUnitImmediate("focustarget")
  end
  local a = RunDependentUnitImmediate("targettarget")
  local b = RunDependentUnitImmediate("focustarget")
  return a or b
end

local RUNTIME_DRIVER_PEW = 1
local RUNTIME_DRIVER_TARGET = 2
local RUNTIME_DRIVER_FOCUS = 4
local RUNTIME_DRIVER_PET = 8
local RUNTIME_DRIVER_BOSS = 16
local RUNTIME_DRIVER_UNIT_TARGET_TARGET = 32
local RUNTIME_DRIVER_UNIT_TARGET_FOCUS = 64
local runtimeDriverMask

-- Blizzard's unit frames register optional events only while an owning frame
-- exists and an active element can consume that identity refresh. RangeFade and
-- group range have their own drivers, so they do not keep this global frame awake.
local function AnyIdentityRuntimeFrame()
  for i = 1, #UF.unitOrder do
    if IdentityRuntimeFrame(UF.unitOrder[i]) then
      return true
    end
  end
  return false
end

local function AnyBossIdentityFrame()
  return IdentityRuntimeFrame("boss1") or IdentityRuntimeFrame("boss2") or IdentityRuntimeFrame("boss3")
    or IdentityRuntimeFrame("boss4") or IdentityRuntimeFrame("boss5")
end

local function RuntimeDriverMask()
  local mask = 0
  if AnyIdentityRuntimeFrame() then
    mask = mask + RUNTIME_DRIVER_PEW
  end
  if IdentityRuntimeFrame("target") or IdentityRuntimeFrame("targettarget") then
    mask = mask + RUNTIME_DRIVER_TARGET
  end
  if IdentityRuntimeFrame("focus") or IdentityRuntimeFrame("focustarget") then
    mask = mask + RUNTIME_DRIVER_FOCUS
  end
  if IdentityRuntimeFrame("pet") then
    mask = mask + RUNTIME_DRIVER_PET
  end
  if AnyBossIdentityFrame() then
    mask = mask + RUNTIME_DRIVER_BOSS
  end
  if IdentityRuntimeFrame("targettarget") then
    mask = mask + RUNTIME_DRIVER_UNIT_TARGET_TARGET
  end
  if IdentityRuntimeFrame("focustarget") then
    mask = mask + RUNTIME_DRIVER_UNIT_TARGET_FOCUS
  end
  return mask
end

SyncRuntimeDriver = function()
  local driver = UF.driver
  if not driver then
    return false
  end
  local mask = RuntimeDriverMask()
  if runtimeDriverMask == mask then
    return true
  end

  driver:UnregisterAllEvents()
  if mask % (RUNTIME_DRIVER_PEW * 2) >= RUNTIME_DRIVER_PEW then
    driver:RegisterEvent("PLAYER_ENTERING_WORLD")
  end
  if mask % (RUNTIME_DRIVER_TARGET * 2) >= RUNTIME_DRIVER_TARGET then
    driver:RegisterEvent("PLAYER_TARGET_CHANGED")
  end
  if mask % (RUNTIME_DRIVER_FOCUS * 2) >= RUNTIME_DRIVER_FOCUS then
    driver:RegisterEvent("PLAYER_FOCUS_CHANGED")
  end
  if mask % (RUNTIME_DRIVER_PET * 2) >= RUNTIME_DRIVER_PET then
    driver:RegisterEvent("UNIT_PET")
  end
  if mask % (RUNTIME_DRIVER_BOSS * 2) >= RUNTIME_DRIVER_BOSS then
    driver:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
  end

  local wantTargetTarget = mask % (RUNTIME_DRIVER_UNIT_TARGET_TARGET * 2) >= RUNTIME_DRIVER_UNIT_TARGET_TARGET
  local wantFocusTarget = mask % (RUNTIME_DRIVER_UNIT_TARGET_FOCUS * 2) >= RUNTIME_DRIVER_UNIT_TARGET_FOCUS
  if wantTargetTarget and wantFocusTarget then
    driver:RegisterUnitEvent("UNIT_TARGET", "target", "focus")
  elseif wantTargetTarget then
    driver:RegisterUnitEvent("UNIT_TARGET", "target")
  elseif wantFocusTarget then
    driver:RegisterUnitEvent("UNIT_TARGET", "focus")
  end

  runtimeDriverMask = mask
  return true
end
UF.SyncRuntimeDriver = SyncRuntimeDriver

local function ConfigTouchesDependentUnits(unit)
  if unit == nil or unit == "*" then
    return true
  end
  local units = UF.UnitsForConfigKey and UF.UnitsForConfigKey(unit)
  if not units then
    return false
  end
  for i = 1, #units do
    local resolved = units[i]
    if resolved == "targettarget" or resolved == "focustarget" then
      return true
    end
  end
  return false
end

local function RefreshTargetVisual(skipAuras, frame)
  frame = frame or RuntimeFrame("target")
  if not frame then return end
  local wantAuras = skipAuras ~= true and frame._msufUpdateAuras ~= nil
  local wantVisual = frame._msufRuntimeVisualCount ~= nil
  if not wantAuras and not wantVisual then return end
  if wantVisual then
    UF.UpdateRuntime("target", "MSUF_UNIT_IDENTITY_VISUAL")
  end
  if wantAuras then
    UF.UpdateRuntime("target", "MSUF_UNIT_IDENTITY_AURAS")
  end
end

local function RefreshFocusVisual(skipAuras, frame)
  frame = frame or RuntimeFrame("focus")
  if not frame then return end
  local wantAuras = skipAuras ~= true and frame._msufUpdateAuras ~= nil
  local wantVisual = frame._msufRuntimeVisualCount ~= nil
  if not wantAuras and not wantVisual then return end
  if wantVisual then
    UF.UpdateRuntime("focus", "MSUF_UNIT_IDENTITY_VISUAL")
  end
  if wantAuras then
    UF.UpdateRuntime("focus", "MSUF_UNIT_IDENTITY_AURAS")
  end
end

local function RefreshTargetIdentityVisual(skipAuras, frame)
  RefreshTargetVisual(skipAuras, frame)
end

local function RefreshFocusIdentityVisual(skipAuras, frame)
  RefreshFocusVisual(skipAuras, frame)
end

-- oUF-style identity gate for dependent units: a group click changes MY
-- target, but ToT/FoT often still resolve to the same GUID (everyone is
-- targeting the boss). The token never stopped pointing at that GUID, so the
-- live event stream kept the frame current and the full identity fanout is
-- redundant -- this is the main reason oUF showed ~0 on group clicks while
-- MSUF re-ran 11 ToT elements per click. Secret GUIDs are treated as unknown,
-- not "changed every tick": the poll snapshot and periodic full tick keep the
-- frame correct without forcing a full identity pass every 0.5s in combat.
DependentIdentityGuidChanged = function(frame, unit)
  local guid = UnitGUID(unit)
  if issecretvalue(guid) == true then
    local firstUnknown = frame._msufIdentityGUID == nil
    frame._msufIdentityGUID = false
    return firstUnknown and true or nil
  end
  if guid == frame._msufIdentityGUID then
    return false
  end
  frame._msufIdentityGUID = guid
  return true
end

local function RunImmediateIdentityAuras(frame, reason)
  if not (frame and frame._msufUpdateAuras) then return false end
  local wasDeferred = frame._msufA3DeferAuraVisualNotify
  frame._msufA3DeferAuraVisualNotify = true
  RunRuntimeFrame(frame, reason)
  frame._msufA3DeferAuraVisualNotify = wasDeferred
  return true
end

local function RuntimeUpdateExistingFrame(frame, _, reason)
  local unit = frame and frame.unit
  if unit and UnitExists then
    local exists = UnitExists(unit)
    if issecretvalue(exists) ~= true and exists == false
      and _G.MSUF_PreviewTestMode ~= true
      and _G.MSUF_BossTestMode ~= true
      and _G.MSUF2_BossUnitframePreviewActive ~= true then
      return
    end
  end
  return RunRuntimeFrame(frame, reason)
end

local function DriverOnEvent(self, event, unit)
  if event == "PLAYER_TARGET_CHANGED" then
    local frame = IdentityRuntimeFrame("target")
    if frame then
      RunRuntimeFrame(frame, "MSUF_UNIT_IDENTITY_FAST")
      RunImmediateIdentityAuras(frame, "MSUF_UNIT_IDENTITY_AURAS")
    end
    RefreshTargetIdentityVisual(true, frame)
    RunDependentUnitsForParent("target")
  elseif event == "PLAYER_FOCUS_CHANGED" then
    local frame = IdentityRuntimeFrame("focus")
    if frame then
      RunRuntimeFrame(frame, "MSUF_UNIT_IDENTITY_FAST")
      RunImmediateIdentityAuras(frame, "MSUF_UNIT_IDENTITY_AURAS")
    end
    RefreshFocusIdentityVisual(true, frame)
    RunDependentUnitsForParent("focus")
  elseif event == "UNIT_TARGET" then
    RunDependentUnitsForParent(unit)
  elseif event == "UNIT_PET" then
    if unit == "player" then
      local frame = IdentityRuntimeFrame("pet")
      if frame then
        RunRuntimeFrame(frame, "MSUF_UNIT_IDENTITY")
      end
    end
  elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
    local frame
    frame = IdentityRuntimeFrame("boss1")
    if frame then RunRuntimeFrame(frame, "MSUF_UNIT_IDENTITY") end
    frame = IdentityRuntimeFrame("boss2")
    if frame then RunRuntimeFrame(frame, "MSUF_UNIT_IDENTITY") end
    frame = IdentityRuntimeFrame("boss3")
    if frame then RunRuntimeFrame(frame, "MSUF_UNIT_IDENTITY") end
    frame = IdentityRuntimeFrame("boss4")
    if frame then RunRuntimeFrame(frame, "MSUF_UNIT_IDENTITY") end
    frame = IdentityRuntimeFrame("boss5")
    if frame then RunRuntimeFrame(frame, "MSUF_UNIT_IDENTITY") end
  else
    UF.ForEachFrame(RuntimeUpdateExistingFrame, "MSUF_FORCE_UPDATE")
    RunDependentUnitsForParent()
  end
end

if not UF.driver then
  UF.driver = CreateFrame("Frame")
end
UF.driver:SetScript("OnEvent", DriverOnEvent)
SyncRuntimeDriver()

local REFRESH_ELEMENT_GROUPS = Metadata.refreshElementGroups or EMPTY_METADATA_SET

local HEALTH_TEXT_BORDER_ELEMENTS = REFRESH_ELEMENT_GROUPS.healthTextBorder or EMPTY_METADATA_SET
local VISUAL_ELEMENTS = REFRESH_ELEMENT_GROUPS.visuals or EMPTY_METADATA_SET
local POWER_TEXT_ELEMENTS = REFRESH_ELEMENT_GROUPS.powerText or EMPTY_METADATA_SET
local COLOR_ELEMENTS = REFRESH_ELEMENT_GROUPS.colors or VISUAL_ELEMENTS
local TEXT_ELEMENTS = REFRESH_ELEMENT_GROUPS.text or EMPTY_METADATA_SET
local BORDER_ELEMENTS = REFRESH_ELEMENT_GROUPS.borders or EMPTY_METADATA_SET
local REVERSE_FILL_ELEMENTS = REFRESH_ELEMENT_GROUPS.reverseFill or EMPTY_METADATA_SET
local ALPHA_ELEMENTS = REFRESH_ELEMENT_GROUPS.alpha or EMPTY_METADATA_SET

function UF.NotifyConfigChanged(unit, applyNow, forceUpdate)
  if InCombatLockdown and InCombatLockdown() then
    UF.MarkDirty(unit)
    if UF.Config then
      UF.Config.dirty = true
    end
    local factory = UF.Factory
    if factory and factory.EnsureDeferredDriver then
      factory.EnsureDeferredDriver()
    end
    return false
  end
  if applyNow ~= false then
    local applied = UF.Apply(unit) and true or false
    if ConfigTouchesDependentUnits(unit) then
      RunDependentUnitsForParent()
    end
    return applied
  elseif forceUpdate ~= false then
    if UF.Config then
      if unit and UF.Config.RefreshUnit then
        local units = UF.UnitsForConfigKey(unit)
        if units then
          for i = 1, #units do
            UF.Config.RefreshUnit(units[i])
          end
        end
      elseif UF.Config.Refresh then
        UF.Config.Refresh()
      end
    end
    local updated = UF.ForceUpdate(unit) and true or false
    if ConfigTouchesDependentUnits(unit) then
      RunDependentUnitsForParent()
    end
    return updated
  end
  return true
end

function UF.RegisterVisualRefreshCallback(key, fn)
  if type(fn) ~= "function" then
    return false
  end
  UF.visualRefreshCallbacks[key or fn] = fn
  return true
end

local function RunVisualRefreshCallbacks(unit)
  for _, fn in pairs(UF.visualRefreshCallbacks) do
    fn(unit)
  end
end

function UF.RefreshVisuals(unit)
  local ok = UF.RefreshElements(unit, VISUAL_ELEMENTS, "MSUF_VISUALS")
  RunVisualRefreshCallbacks(unit)
  return ok
end

function UF.RefreshIdentityColors()
  return UF.RefreshElements(nil, HEALTH_TEXT_BORDER_ELEMENTS, "MSUF_IDENTITY_COLORS")
end

function UF.RefreshPowerTextColors()
  return UF.RefreshElements(nil, POWER_TEXT_ELEMENTS, "MSUF_POWER_TEXT_COLORS")
end

function UF.RefreshColors()
  return UF.RefreshElements(nil, COLOR_ELEMENTS, "MSUF_COLOR_CHANGE")
end

function UF.RefreshAlphas()
  return UF.RefreshElements(nil, ALPHA_ELEMENTS, "MSUF_ALPHA")
end

function UF.RefreshBorders()
  return UF.RefreshElements(nil, BORDER_ELEMENTS, "MSUF_BORDER_LAYOUT")
end

function UF.RefreshHealthLayout()
  return UF.RefreshElements(nil, REVERSE_FILL_ELEMENTS, "MSUF_REVERSE_FILL")
end

function UF.RefreshPowerLayout(unit)
  return UF.RefreshElements(unit, POWER_TEXT_ELEMENTS, "MSUF_POWER_LAYOUT")
end

function UF.RefreshPowerLayoutForFrame(frame)
  if frame and frame.unit then
    return UF.RefreshPowerLayout(frame.unit)
  end
  return UF.RefreshPowerLayout(nil)
end

function UF.RefreshTextLayout(unit)
  return UF.RefreshElements(unit, TEXT_ELEMENTS, "MSUF_TEXT_LAYOUT")
end

UF.ApplyUnitFrameKey = UF.Apply

local ExportPublic = MSUF.ExportPublic or function(name, value)
  _G[name] = value
  return value
end

MSUF.UnitFrames = UF
ExportPublic("MSUF_UnitFrames", UF.frames)
ExportPublic("MSUF_UnitFramesList", UF.frameList)
ExportPublic("MSUF_ForEachUnitFrame", UF.ForEachFrame)
ExportPublic("MSUF_GetUnitFrameScreenCacheKey", GetUnitFrameScreenCacheKey)
ExportPublic("MSUF_GetUnitFrameScreenCacheBucket", GetUnitFrameScreenCacheBucket)
ExportPublic("MSUF_CacheUnitFrameScreenPosition", CacheUnitFrameScreenPosition)
ExportPublic("MSUF_ApplyCachedUnitFrameScreenPosition", ApplyCachedUnitFrameScreenPosition)
ExportPublic("MSUF_UFCore_NotifyConfigChanged", UF.NotifyConfigChanged)
ExportPublic("MSUF_RefreshAllFrames", UF.RefreshVisuals)
MSUF.MSUF_RefreshAllFrames = UF.RefreshVisuals
ExportPublic("MSUF_RefreshAllFrameColors", UF.RefreshColors)
ExportPublic("MSUF_RefreshAllIdentityColors", UF.RefreshIdentityColors)
ExportPublic("MSUF_RefreshAllPowerTextColors", UF.RefreshPowerTextColors)
ExportPublic("MSUF_ForceTextLayoutForUnitKey", UF.RefreshTextLayout)
ExportPublic("MSUF_RefreshAllUnitAlphas", UF.RefreshAlphas)
ExportPublic("MSUF_ApplyBarOutlineThickness_All", UF.RefreshBorders)
ExportPublic("MSUF_ApplyPowerBarBorder_All", UF.RefreshBorders)
ExportPublic("MSUF_ApplyReverseFillBars", UF.RefreshHealthLayout)
ExportPublic("MSUF_ApplyAllAlpha", UF.RefreshAlphas)
ExportPublic("MSUF_ApplyPowerBarEmbedLayout_All", UF.RefreshPowerLayout)
ExportPublic("MSUF_ApplyPowerBarEmbedLayout", UF.RefreshPowerLayoutForFrame)
ExportPublic("MSUF_ApplyPowerBarEmbedLayout_ForUnitKey", UF.RefreshPowerLayout)
ExportPublic("MSUF_ApplyUnitFrameKey_Immediate", UF.ApplyUnitFrameKey)
ExportPublic("MSUF_RequestUnitFrameReanchorAfterCombat", UF.RequestReanchorAfterCombat)
