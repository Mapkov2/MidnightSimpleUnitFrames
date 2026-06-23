-- UF factory: creates and wires unit-frame instances from compiled specs.
-- Frame creation is cold/warm-path work; live event dispatch belongs to UF runtime/core modules.
local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
  _G[name] = value
  return value
end

local UF = MSUF.UF
UF.Factory = UF.Factory or {}
local Factory = UF.Factory

--- UnitFrames/Engine/MSUF_UF_Factory.lua
---
--- Creates and applies the concrete Blizzard frames for unit frames. Factory is
--- the protected-frame boundary: size, point, secure attributes, RegisterUnitWatch,
--- and combat-deferred apply work belong here. Event dispatch and element logic
--- should stay in Core/Dispatch/Elements after the frame exists.

local type = type
local ipairs = ipairs
local tonumber = tonumber
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local RegisterUnitWatch = RegisterUnitWatch
local UnregisterUnitWatch = UnregisterUnitWatch
local UnitFrame_OnEnter = UnitFrame_OnEnter
local UnitFrame_OnLeave = UnitFrame_OnLeave
local UnitGUID = UnitGUID
local UIParent = UIParent

local COOLDOWN_ANCHORS = {
  EssentialCooldownViewer = true,
  UtilityCooldownViewer = true,
  BuffIconCooldownViewer = true,
}

--- Anchors may be ordinary globals, MSUF unit frames, or cooldown-viewer frames
--- that can appear late. ResolveNamedAnchor returns both the frame (if present)
--- and the missing name so Factory can schedule a late reanchor without losing
--- the user's intended attachment.
local function IsCooldownViewerAnchor(name)
  return COOLDOWN_ANCHORS[name] == true
end

local function ResolveNamedAnchor(name)
  if type(name) ~= "string" or name == "" then
    return nil, nil
  end
  if IsCooldownViewerAnchor(name) then
    local resolver = _G.MSUF_GetEffectiveCooldownFrame
    local frame = (type(resolver) == "function" and resolver(name)) or _G[name]
    if frame then
      return frame, nil, true
    end
    return nil, name, true
  end
  if UF.frames and UF.frames[name] then
    return UF.frames[name], nil
  end
  local frame = _G[name]
  if frame then
    return frame, nil
  end
  return nil, name
end

local function ResolveAnchor(spec, frame)
  local anchor = UIParent
  if type(spec.anchorFrameName) == "string" and spec.anchorFrameName ~= "" then
    local named, missing = ResolveNamedAnchor(spec.anchorFrameName)
    if named and named ~= frame then
      return named, nil, spec.anchorFrameName
    end
    return anchor, missing or spec.anchorFrameName, spec.anchorFrameName
  elseif type(spec.anchorToUnitframe) == "string"
    and spec.anchorToUnitframe ~= ""
    and spec.anchorToUnitframe ~= "GLOBAL"
    and spec.anchorToUnitframe ~= "global"
    and spec.anchorToUnitframe ~= "FREE" then
    local other = UF.frames[spec.anchorToUnitframe]
    local missing
    if not other then
      other, missing = ResolveNamedAnchor(spec.anchorToUnitframe)
    end
    if other and other ~= frame then
      return other, nil, spec.anchorToUnitframe
    end
    return anchor, missing or spec.anchorToUnitframe, spec.anchorToUnitframe
  end
  return anchor, nil, nil
end

local function ShouldCacheScreenPosition(spec, requestedAnchor)
  if type(spec.anchorFrameName) == "string" and spec.anchorFrameName ~= "" then
    return true
  end
  return COOLDOWN_ANCHORS[requestedAnchor] == true
end

--- Combat lockdown cannot safely rebuild protected frame positions/attributes.
--- Defer by config key rather than raw unit where possible so boss/alias units
--- are reapplied together after combat.
local function DeferApply(unit)
  if unit then
    local units = UF.UnitsForConfigKey and UF.UnitsForConfigKey(unit)
    if units then
      for i = 1, #units do
        UF.pendingApply[units[i]] = true
      end
    else
      UF.pendingApply[unit] = true
    end
  else
    for i = 1, #UF.unitOrder do
      UF.pendingApply[UF.unitOrder[i]] = true
    end
  end
  if UF.Config then
    UF.Config.dirty = true
  end
  Factory.EnsureDeferredDriver()
  return false
end

local function ResolveConfig(refresh)
  local config = UF.Config
  if not (config and type(config.GetSpec) == "function") then
    if config then
      config.dirty = true
    end
    return nil
  end
  if refresh and type(config.Refresh) == "function" then
    config.Refresh()
  end
  return config
end

--- Position apply is intentionally conservative. While dragging, in combat, or
--- waiting for a late anchor, it preserves the current visible position and
--- queues the real apply instead of forcing a potentially protected SetPoint.
local function ApplyPosition(frame, spec)
  if frame._msufDragActive == true then
    return true
  end
  if InCombatLockdown and InCombatLockdown() then
    UF.pendingApply[frame.unit] = true
    Factory.EnsureDeferredDriver()
    return false
  end
  local point = spec.point or "CENTER"
  local anchor, missingAnchorName, requestedAnchor = ResolveAnchor(spec, frame)
  local relativePoint = spec.relativePoint or point
  local x = tonumber(spec.x) or 0
  local y = tonumber(spec.y) or 0
  local key = spec.key or (UF.ConfigKeyForUnit and UF.ConfigKeyForUnit(frame.unit)) or frame.unit

  if missingAnchorName then
    if type(_G.MSUF_ScheduleLateAnchorReanchor) == "function" then
      _G.MSUF_ScheduleLateAnchorReanchor()
    end
    local applyCached = _G.MSUF_ApplyCachedUnitFrameScreenPosition
    if type(applyCached) == "function" and applyCached(frame, key, frame.unit) then
      return true
    end
    if frame._msufPositionInitialized == true then
      return true
    end
  end

  if frame._msufPoint ~= point
    or frame._msufAnchor ~= anchor
    or frame._msufRelativePoint ~= relativePoint
    or frame._msufX ~= x
    or frame._msufY ~= y then
    frame:ClearAllPoints()
    frame:SetPoint(point, anchor, relativePoint, x, y)
    frame._msufPoint, frame._msufAnchor, frame._msufRelativePoint = point, anchor, relativePoint
    frame._msufX, frame._msufY = x, y
  end
  frame._msufPositionInitialized = true
  frame._msufHardLockedToUIParent = nil
  if not missingAnchorName
    and ShouldCacheScreenPosition(spec, requestedAnchor)
    and type(_G.MSUF_CacheUnitFrameScreenPosition) == "function" then
    _G.MSUF_CacheUnitFrameScreenPosition(frame, key, frame.unit, point)
  end
  return true
end

local function ApplySize(frame, spec)
  if InCombatLockdown and InCombatLockdown() then
    UF.pendingApply[frame.unit] = true
    Factory.EnsureDeferredDriver()
    return false
  end
  local width = tonumber(spec.width) or 220
  local height = tonumber(spec.height) or 34
  if frame._msufWidth ~= width or frame._msufHeight ~= height then
    frame:SetSize(width, height)
    frame._msufWidth, frame._msufHeight = width, height
  end
  return true
end

local function DisableFrame(frame)
  if not frame then
    return
  end
  if frame.Disable then
    frame:Disable()
  else
    UnregisterUnitWatch(frame)
    frame:Hide()
  end
end

local function ApplyFrame(frame, spec)
  if not (frame and spec) then
    return false
  end
  if InCombatLockdown and InCombatLockdown() then
    return DeferApply(frame.unit)
  end
  UF.SetFrameSpec(frame, spec, frame.unit)
  if spec.enabled == false then
    DisableFrame(frame)
    if UF.DetachFrame then
      UF.DetachFrame(frame)
    end
    frame._msufDisabledByConfig = true
    return true
  end
  frame._msufDisabledByConfig = nil
  if ApplySize(frame, spec) == false or ApplyPosition(frame, spec) == false then
    return false
  end
  UF.ApplySpec(frame, spec, nil, true)

  -- LoadConditions.Apply (run inside ApplySpec above) owns visibility: it
  -- either installs a secure state driver (_msufVisibilityManaged) or, for the
  -- existence-only case, registers the lightweight unit watch itself
  -- (_msufUnitWatched). Only fall back to a manual watch/show when neither
  -- path claimed the frame.
  if frame._msufVisibilityManaged ~= true and frame._msufUnitWatched ~= true then
    if frame.Enable then
      frame:Enable()
      frame._msufUnitWatched = true
    elseif RegisterUnitWatch then
      RegisterUnitWatch(frame)
      frame._msufUnitWatched = true
    else
      frame:Show()
    end
  end
  frame:ForceUpdate("MSUF_APPLY")
  return true
end

local function RegisterGlobals(unit, frame)
  UF.frames[unit] = frame
  ExportPublic("MSUF_UnitFrames", UF.frames)
  ExportPublic(UF.FrameName(unit), frame)
  if unit == "targettarget" then
    ExportPublic("MSUF_tot", frame)
  end

  local found = false
  for i = 1, #UF.frameList do
    if UF.frameList[i] == frame then
      found = true
      break
    end
  end
  if not found then
    UF.frameList[#UF.frameList + 1] = frame
  end
  ExportPublic("MSUF_UnitFramesList", UF.frameList)
end

local function ShowUnitTooltip(frame)
  if _G.MSUF_RoundedUF_OnUnitMouseover then
    _G.MSUF_RoundedUF_OnUnitMouseover(frame, true)
  end
  if MSUF.Highlight then
    MSUF.Highlight.Show(frame)
  end
  local tooltips = MSUF and MSUF.Tooltips
  if tooltips and type(tooltips.ShowUnit) == "function" then
    tooltips.ShowUnit(frame, frame and frame.unit)
    return
  end
  if UnitFrame_OnEnter then
    UnitFrame_OnEnter(frame)
  end
end

local function HideUnitTooltip(frame)
  if _G.MSUF_RoundedUF_OnUnitMouseover then
    _G.MSUF_RoundedUF_OnUnitMouseover(frame, false)
  end
  if MSUF.Highlight then
    MSUF.Highlight.Hide(frame)
  end
  local tooltips = MSUF and MSUF.Tooltips
  if tooltips and type(tooltips.HideUnit) == "function" then
    tooltips.HideUnit(frame)
    return
  end
  if UnitFrame_OnLeave then
    UnitFrame_OnLeave(frame)
  elseif GameTooltip then
    GameTooltip:Hide()
  end
end

local function ResolvePingUnit(frame)
  if not frame then
    return nil
  end
  if frame.GetAttribute then
    local attrUnit = frame:GetAttribute("unit")
    if type(attrUnit) == "string" and attrUnit ~= "" then
      return attrUnit
    end
  end
  local unit = frame.unit
  if type(unit) == "string" and unit ~= "" then
    return unit
  end
  return nil
end

local function PingTargetGUID(frame)
  local unit = ResolvePingUnit(frame)
  return unit and UnitGUID(unit) or nil
end

local function MSUF_GetPingTargetInfo(self)
  return {
    guid = PingTargetGUID(self),
  }
end

local function MSUF_GetTargetPingGUID(self)
  return PingTargetGUID(self)
end

local function MSUF_GetContextualPingType(self)
  local guid = PingTargetGUID(self)
  if PingUtil and type(PingUtil.GetContextualPingTypeForUnit) == "function" then
    return PingUtil:GetContextualPingTypeForUnit(guid)
  end
  return nil
end

local function MSUF_GetIsPingable(self)
  return PingTargetGUID(self) ~= nil
end

local function MSUF_GetAllowRadialWheel()
  return true
end

function UF.ResolvePingUnit(frame)
  return ResolvePingUnit(frame)
end

function UF.InstallPingCompatibility(frame)
  if not frame then
    return false
  end
  if frame._msufPingCompatInstalled == true then
    return true
  end
  frame._msufPingCompatInstalled = true
  frame.IsPingable = true
  frame.GetTargetInfo = MSUF_GetPingTargetInfo
  frame.GetTargetPingGUID = MSUF_GetTargetPingGUID
  frame.GetContextualPingType = MSUF_GetContextualPingType
  if type(frame.GetIsPingable) ~= "function" then
    frame.GetIsPingable = MSUF_GetIsPingable
  end
  if type(frame.GetAllowRadialWheel) ~= "function" then
    frame.GetAllowRadialWheel = MSUF_GetAllowRadialWheel
  end
  return true
end

function UF.EnsureNativePingIcon(frame)
  if not frame then
    return nil
  end
  local ping = frame.pingIconFrame or frame.PingIconFrame
  if not ping then
    -- UnitPingIconFrameTemplate is restricted; only drive a native ping child if Blizzard created one.
    frame._msufNativePingGUID = nil
    return nil
  end
  if IsForbidden and IsForbidden(ping) then
    return nil
  end
  if type(ping.SetGUIDMatch) ~= "function" then
    return nil
  end
  if not ping._msufNativePingIconConfigured then
    ping._msufNativePingIconConfigured = true
    if ping.SetSize then
      ping:SetSize(24, 24)
    end
    if ping.ClearAllPoints and ping.SetPoint then
      ping:ClearAllPoints()
      ping:SetPoint("CENTER", frame, "CENTER", 0, 0)
    end
    if ping.SetFrameLevel and frame.GetFrameLevel then
      ping:SetFrameLevel((frame:GetFrameLevel() or 0) + 20)
    end
    if ping.SetOnUpdateMode then
      ping:SetOnUpdateMode("RunWhenVisible")
    end
  end
  frame.pingIconFrame = ping
  frame.PingIconFrame = ping
  if ping.Show then
    ping:Show()
  end
  return ping
end

function UF.RefreshNativePingIcon(frame)
  local ping = UF.EnsureNativePingIcon(frame)
  if not ping then
    return false
  end
  local unit = UF.ResolvePingUnit and UF.ResolvePingUnit(frame) or frame and frame.unit
  local guid = unit and UnitGUID(unit) or nil
  if frame._msufNativePingGUID == guid then
    return true
  end
  frame._msufNativePingGUID = guid
  if guid == nil then
    ping:Hide()
  else
    ping:Show()
  end
  ping:SetGUIDMatch(guid)
  return true
end

local function SpawnFrame(unit)
  if not UF.IsManagedUnit(unit) then
    return nil
  end
  if UF.ShouldUseMSUFUnitFrame and UF.ShouldUseMSUFUnitFrame(unit) == false then
    return nil
  end

  local name = UF.FrameName(unit)
  local frame = _G[name]
  if not frame then
    frame = CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate, PingableUnitFrameTemplate")
  end

  UF.AttachFrameMethods(frame)
  frame.unit = unit
  frame.MSUFUnitKey = unit
  frame:SetAttribute("unit", unit)
  frame:SetAttribute("*type1", "target")
  frame:SetAttribute("*type2", "togglemenu")
  frame:SetAttribute("toggleForVehicle", true)
  frame:RegisterForClicks("AnyUp")
  UF.InstallPingCompatibility(frame)
  UF.RefreshNativePingIcon(frame)
  frame.Enable = RegisterUnitWatch
  frame.Disable = function(self)
    UnregisterUnitWatch(self)
    self:Hide()
  end
  if not frame._msufTooltipHooked then
    frame:HookScript("OnEnter", ShowUnitTooltip)
    frame:HookScript("OnLeave", HideUnitTooltip)
    frame._msufTooltipHooked = true
  end

  RegisterGlobals(unit, frame)
  return frame
end

local function ApplyOne(unit)
  if not UF.IsManagedUnit(unit) then
    return false
  end
  if UF.ShouldUseMSUFUnitFrame and UF.ShouldUseMSUFUnitFrame(unit) == false then
    local frame = UF.frames[unit]
    if frame then
      frame:Hide()
    end
    return true
  end
  local frame = UF.frames[unit]
  if not frame then
    frame = SpawnFrame(unit)
  end
  if not frame then
    return false
  end
  local config = ResolveConfig(false)
  return config and ApplyFrame(frame, config.GetSpec(unit)) or false
end

--- SpawnAll is the first-time construction path. It creates all managed unit
--- frames out of combat, applies their compiled specs, and then marks the engine
--- initialized so later changes can use the narrower Apply path.
function Factory.SpawnAll()
  if UF.spawned then
    UF.initialized = true
    return true
  end
  if InCombatLockdown and InCombatLockdown() then
    Factory.EnsureDeferredDriver()
    return false
  end

  local config = ResolveConfig(true)
  if not config then
    return false
  end
  if UF.DisableBlizzardFrames then
    UF.DisableBlizzardFrames()
  end

  for i = 1, #UF.unitOrder do
    local unit = UF.unitOrder[i]
    local frame = SpawnFrame(unit)
    if frame then
      ApplyFrame(frame, config.GetSpec(unit))
    end
  end

  UF.spawned = true
  UF.initialized = true
  if type(MSUF.RegisterThirdPartyAnchors) == "function" then
    MSUF.RegisterThirdPartyAnchors()
  end
  return true
end

--- Public cold/warm apply entry. It may refresh compiled config, apply one
--- unit/config-key, or queue the work through the deferred driver when protected
--- frame operations are unsafe.
function Factory.Apply(unit)
  if not UF.spawned then
    return Factory.SpawnAll()
  end
  if InCombatLockdown and InCombatLockdown() then
    return DeferApply(unit)
  end
  local config = ResolveConfig(false)
  if not config then
    return false
  end
  if unit then
    local units = UF.UnitsForConfigKey(unit)
    if not units then
      return false
    end
    if config.RefreshUnit then
      for i = 1, #units do
        config.RefreshUnit(units[i])
      end
    elseif config.Refresh then
      config.Refresh()
    end
    local ok = false
    for i = 1, #units do
      ok = ApplyOne(units[i]) or ok
    end
    return ok
  end
  ResolveConfig(true)
  for i = 1, #UF.unitOrder do
    ApplyOne(UF.unitOrder[i])
  end
  return true
end

local function DeferredOnEvent(self)
  if InCombatLockdown and InCombatLockdown() then
    return
  end
  self:UnregisterEvent("PLAYER_REGEN_ENABLED")
  if not UF.spawned then
    Factory.SpawnAll()
    return
  end
  local config = ResolveConfig(UF.Config and UF.Config.dirty == true)
  if not config then
    Factory.EnsureDeferredDriver()
    return
  end
  for unit in pairs(UF.pendingApply) do
    UF.pendingApply[unit] = nil
    local frame = UF.frames[unit]
    if frame then
      ApplyFrame(frame, config.GetSpec(unit))
    end
  end
  if UF.FlushDeferredRefreshes then
    UF.FlushDeferredRefreshes()
  end
end

function Factory.EnsureDeferredDriver()
  if not Factory.deferredDriver then
    Factory.deferredDriver = CreateFrame("Frame")
    Factory.deferredDriver:SetScript("OnEvent", DeferredOnEvent)
  end
  Factory.deferredDriver:RegisterEvent("PLAYER_REGEN_ENABLED")
end

local LATE_ANCHOR_KEYS = { "player", "target", "targettarget", "focus", "focustarget", "pet", "boss" }

local function HasClassPowerLateAnchor()
  return false
end

local function HasLateAnchorConfig()
  local db = _G.MSUF_DB
  if type(db) ~= "table" then return false end
  local general = db.general
  if general and general.anchorToCooldown == true then return false end
  if HasClassPowerLateAnchor() then return true end
  for i = 1, #LATE_ANCHOR_KEYS do
    local conf = db[LATE_ANCHOR_KEYS[i]]
    if type(conf) == "table" then
      if type(conf.anchorFrameName) == "string" and conf.anchorFrameName ~= "" and not IsCooldownViewerAnchor(conf.anchorFrameName) then
        return true
      end
      local anchorTo = conf.anchorToUnitframe
      if type(anchorTo) == "string"
        and anchorTo ~= ""
        and anchorTo ~= "GLOBAL"
        and anchorTo ~= "global"
        and anchorTo ~= "FREE"
        and not IsCooldownViewerAnchor(anchorTo) then
        return true
      end
    end
  end
  return false
end

local function FlushLateAnchorReanchor()
  if InCombatLockdown and InCombatLockdown() then
    UF.RequestReanchorAfterCombat()
    return false
  end
  Factory.Apply()
  if HasClassPowerLateAnchor() and type(_G.MSUF_ClassPower_Refresh) == "function" then
    _G.MSUF_ClassPower_Refresh()
  end
  return true
end

local function ScheduleLateAnchorReanchor()
  ExportPublic("MSUF_CDMBridgeDirty", true)
  if InCombatLockdown and InCombatLockdown() then
    UF.RequestReanchorAfterCombat()
    return false
  end

  local state = _G.MSUF_LateAnchorReanchorState
  if type(state) ~= "table" then
    state = { pending = false }
    ExportPublic("MSUF_LateAnchorReanchorState", state)
  end
  if state.pending then return false end
  state.pending = true

  _G.C_Timer.After(0, function()
    if not state.pending then return end
    FlushLateAnchorReanchor()
    state.pending = false
  end)
  return true
end
ExportPublic("MSUF_ScheduleLateAnchorReanchor", ScheduleLateAnchorReanchor)

local function ForceReanchorAllUnitFramesOnce()
  if InCombatLockdown and InCombatLockdown() then
    UF.RequestReanchorAfterCombat()
    return false
  end
  return Factory.Apply()
end
ExportPublic("MSUF_ForceReanchorAllUnitFrames_Once", ForceReanchorAllUnitFramesOnce)

do
  local function ScheduleFromEvent()
    local function run()
      if HasLateAnchorConfig() and type(_G.MSUF_ScheduleLateAnchorReanchor) == "function" then
        _G.MSUF_ScheduleLateAnchorReanchor()
      end
    end
    _G.C_Timer.After(0, run)
  end

  local lateAnchorEvents = CreateFrame("Frame")
  lateAnchorEvents:RegisterEvent("PLAYER_LOGIN")
  lateAnchorEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
  lateAnchorEvents:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
  lateAnchorEvents:RegisterEvent("ADDON_LOADED")
  lateAnchorEvents:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" then
      if type(addon) ~= "string" then return end
      if addon ~= "Blizzard_EditMode" then return end
    end
    ScheduleFromEvent()
  end)
end

function UF.Initialize()
  if UF.initialized then
    return true
  end
  return Factory.SpawnAll()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_LOGIN")
  UF.Initialize()
end)
