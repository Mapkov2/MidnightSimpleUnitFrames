local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
  _G[name] = value
  return value
end

local UF = MSUF.UF
if not UF then return end

UF.Factory = UF.Factory or {}
local Factory = UF.Factory

local type = type
local tonumber = tonumber
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local RegisterUnitWatch = RegisterUnitWatch
local UnregisterUnitWatch = UnregisterUnitWatch
local UIParent = UIParent
local PetBattleFrameHider = PetBattleFrameHider
local Mixin = Mixin
local PingableType_UnitFrameMixin = PingableType_UnitFrameMixin
local UnitExists = UnitExists
local UnitGUID = UnitGUID

local COOLDOWN_ANCHORS = {
  EssentialCooldownViewer = true,
  UtilityCooldownViewer = true,
  BuffIconCooldownViewer = true,
}

local clickCastRegistered = setmetatable({}, { __mode = "k" })

local function InCombat()
  return InCombatLockdown and InCombatLockdown()
end

local function ResolvePetBattleFrameHider()
  return PetBattleFrameHider or UIParent
end

UF.GetPetBattleFrameHider = ResolvePetBattleFrameHider

local function IsCooldownViewerAnchor(name)
  return COOLDOWN_ANCHORS[name] == true
end

local function ResolveNamedAnchor(name)
  if type(name) ~= "string" or name == "" then return nil, nil end
  if IsCooldownViewerAnchor(name) then
    local resolver = _G.MSUF_GetEffectiveCooldownFrame
    local frame = (type(resolver) == "function" and resolver(name)) or _G[name]
    if frame then return frame, nil, true end
    return nil, name, true
  end
  if UF.frames and UF.frames[name] then return UF.frames[name], nil end
  if _G[name] then return _G[name], nil end
  return nil, name
end

local function ResolveAnchor(spec, frame)
  local anchor = UIParent
  local name = spec and spec.anchorFrameName
  if type(name) ~= "string" or name == "" then
    name = spec and spec.anchorToUnitframe
    if name == "GLOBAL" or name == "global" or name == "FREE" then
      name = nil
    end
  end
  if type(name) == "string" and name ~= "" then
    local resolved, missing = ResolveNamedAnchor(name)
    if resolved and resolved ~= frame then return resolved, nil, name end
    return anchor, missing or name, name
  end
  return anchor, nil, nil
end

local MAX_ANCHOR_DEPTH = 16

local function AnchorDependsOn(region, target, seen, depth)
  if not (region and target) then return false end
  if region == target then return true end
  depth = (tonumber(depth) or 0) + 1
  if depth > MAX_ANCHOR_DEPTH then return false end
  seen = seen or {}
  if seen[region] then return false end
  seen[region] = true
  if not (region.GetNumPoints and region.GetPoint) then return false end
  for i = 1, region:GetNumPoints() or 0 do
    local _, relativeTo = region:GetPoint(i)
    if relativeTo == target or AnchorDependsOn(relativeTo, target, seen, depth) then
      return true
    end
  end
  return false
end

local function AnchorWouldCreateCycle(frame, anchor)
  return frame and anchor and anchor ~= UIParent and AnchorDependsOn(anchor, frame) == true
end

local function ScreenCacheKey(spec, frame)
  return spec and spec.key or (UF.ConfigKeyForUnit and UF.ConfigKeyForUnit(frame and frame.unit)) or frame and frame.unit
end

local function LayoutFrame(frame)
  return frame
end

local function ShouldCacheScreenPosition(spec, requestedAnchor)
  return type(spec and spec.anchorFrameName) == "string"
    and spec.anchorFrameName ~= ""
    or COOLDOWN_ANCHORS[requestedAnchor] == true
end

local function MarkPending(unit)
  if unit then
    local units = UF.UnitsForConfigKey and UF.UnitsForConfigKey(unit)
    if units then
      for i = 1, #units do UF.pendingApply[units[i]] = true end
    else
      UF.pendingApply[unit] = true
    end
  else
    for i = 1, #UF.unitOrder do UF.pendingApply[UF.unitOrder[i]] = true end
  end
  if UF.Config then UF.Config.dirty = true end
end

local function DeferApply(unit)
  MarkPending(unit)
  Factory.EnsureDeferredDriver()
  return false
end

local function ResolveConfig(refresh)
  local config = UF.Config
  if not (config and type(config.GetSpec) == "function") then
    if config then config.dirty = true end
    return nil
  end
  if refresh and type(config.Refresh) == "function" then
    config.Refresh()
  end
  return config
end

local function ApplyPosition(frame, spec)
  if frame._msufDragActive == true then return true end
  if InCombat() then return DeferApply(frame.unit) end
  local layout = LayoutFrame(frame)

  local point = spec.point or "CENTER"
  local relativePoint = spec.relativePoint or point
  local x = tonumber(spec.x) or 0
  local y = tonumber(spec.y) or 0
  local anchor, missingAnchorName, requestedAnchor = ResolveAnchor(spec, frame)
  local key = ScreenCacheKey(spec, frame)

  if missingAnchorName then
    if type(_G.MSUF_ScheduleLateAnchorReanchor) == "function" then
      _G.MSUF_ScheduleLateAnchorReanchor()
    end
    local applyCached = _G.MSUF_ApplyCachedUnitFrameScreenPosition
    if type(applyCached) == "function" and applyCached(layout, key, frame.unit) then
      return true
    end
    if frame._msufPositionInitialized == true then return true end
  end

  if AnchorWouldCreateCycle(layout, anchor) then
    anchor = UIParent
    relativePoint = point
  end

  if layout._msufPoint ~= point
    or layout._msufAnchor ~= anchor
    or layout._msufRelativePoint ~= relativePoint
    or layout._msufX ~= x
    or layout._msufY ~= y then
    layout:ClearAllPoints()
    layout:SetPoint(point, anchor, relativePoint, x, y)
    layout._msufPoint = point
    layout._msufAnchor = anchor
    layout._msufRelativePoint = relativePoint
    layout._msufX = x
    layout._msufY = y
  end
  if frame ~= layout and frame.ClearAllPoints and frame.SetAllPoints then
    frame:ClearAllPoints()
    frame:SetAllPoints(layout)
  end

  frame._msufPositionInitialized = true
  if not missingAnchorName
    and ShouldCacheScreenPosition(spec, requestedAnchor)
    and type(_G.MSUF_CacheUnitFrameScreenPosition) == "function" then
    _G.MSUF_CacheUnitFrameScreenPosition(layout, key, frame.unit, point)
  end
  return true
end

local function ApplySize(frame, spec)
  if InCombat() then return DeferApply(frame.unit) end
  local layout = LayoutFrame(frame)
  local width = tonumber(spec.width) or 220
  local height = tonumber(spec.height) or 34
  if layout._msufWidth ~= width or layout._msufHeight ~= height then
    layout:SetSize(width, height)
    layout._msufWidth = width
    layout._msufHeight = height
  end
  if frame ~= layout then frame:SetSize(width, height) end
  frame._msufWidth = width
  frame._msufHeight = height
  return true
end

local function DisableFrame(frame)
  if not frame then return end
  local clickOverlay = frame._msufClickOverlay
  if clickOverlay then
    if UnregisterUnitWatch then UnregisterUnitWatch(clickOverlay) end
    clickOverlay._msufClickOverlayWatched = nil
    if clickOverlay.Hide then clickOverlay:Hide() end
  end
  if frame.Disable then
    frame:Disable()
  else
    if UnregisterUnitWatch then UnregisterUnitWatch(frame) end
    frame:Hide()
  end
end

local function RegisterGlobals(unit, frame)
  UF.frames[unit] = frame
  ExportPublic("MSUF_UnitFrames", UF.frames)
  ExportPublic(UF.FrameName(unit), frame)
  if unit == "targettarget" then ExportPublic("MSUF_tot", frame) end

  for i = 1, #UF.frameList do
    if UF.frameList[i] == frame then
      ExportPublic("MSUF_UnitFramesList", UF.frameList)
      return
    end
  end
  UF.frameList[#UF.frameList + 1] = frame
  ExportPublic("MSUF_UnitFramesList", UF.frameList)
end

function UF.GetSecureUnitButtonTemplate()
  return "SecureUnitButtonTemplate, PingableUnitFrameTemplate"
end

function UF.GetSecureHeaderUnitButtonTemplate()
  return "SecureUnitButtonTemplate, SecureHandlerStateTemplate, SecureHandlerEnterLeaveTemplate, PingableUnitFrameTemplate"
end

function UF.CreateSecureUnitButton(name, parent)
  return CreateFrame("Button", name, parent or ResolvePetBattleFrameHider(), UF.GetSecureUnitButtonTemplate())
end

function UF.RegisterClickCastFrame(frame)
  if not frame then return false end
  _G.ClickCastFrames = type(_G.ClickCastFrames) == "table" and _G.ClickCastFrames or {}
  _G.ClickCastFrames[frame] = true
  clickCastRegistered[frame] = true
  frame._msufClickCastDisabledForClickSpikeTest = nil
  return true
end

function UF.ResolvePingUnit(frame)
  if not frame then return nil end
  if frame.GetAttribute then
    local unit = frame:GetAttribute("unit")
    if type(unit) == "string" and unit ~= "" then return unit end
  end
  return type(frame.unit) == "string" and frame.unit or nil
end

function UF.ForEachPingBindingAttribute()
  return false
end

function UF.GetSecurePingInitialConfig()
  return "self:SetAttribute('ping-receiver', true)\n"
end

function UF.DisablePingCompatibility(frame)
  if not frame then return false end
  frame._msufPingCompatInstalled = nil
  frame._msufNativePingGUID = nil
  local ping = frame.pingIconFrame or frame.PingIconFrame
  if ping and ping.Hide then ping:Hide() end
  return true
end

function UF.InstallPingCompatibility()
  return false
end

function UF.RefreshPingCompatibility()
  return false
end

function UF.ConfigurePingableUnitFrame(frame)
  if not frame or InCombat() then return false end
  if Mixin and PingableType_UnitFrameMixin and frame._msufPingableMixedIn ~= true then
    Mixin(frame, PingableType_UnitFrameMixin)
    frame._msufPingableMixedIn = true
  end
  if frame.SetAttribute and frame:GetAttribute("ping-receiver") ~= true then
    frame:SetAttribute("ping-receiver", true)
  end
  if type(frame.GetTargetPingGUID) ~= "function" then
    frame.GetTargetPingGUID = function(self)
      local unit = self.GetAttribute and self:GetAttribute("unit") or self.unit
      if unit and UnitExists and UnitExists(unit) and UnitGUID then
        return UnitGUID(unit)
      end
    end
  end
  return true
end

function UF.EnsureNativePingIcon(frame)
  return nil
end

function UF.RefreshNativePingIcon(frame)
  return false
end

ExportPublic("MSUF_RefreshPingCompatibility", UF.RefreshPingCompatibility)
ExportPublic("MSUF_DebugPingFrame", function(unitOrFrame)
  if type(unitOrFrame) == "table" then return unitOrFrame end
  return UF.frames and UF.frames[unitOrFrame]
end)

function UF.GetSecureMenuProxy()
  return nil
end

function UF.AttachSecureUnitMenu(frame)
  if not (frame and frame.SetAttribute) or InCombat() then return nil end
  -- PTR 12.1 blocks delegated secure click actions; use Blizzard's addon
  -- supported togglemenu action directly on the unit button.
  frame:SetAttribute("type2", nil)
  frame:SetAttribute("*type2", "togglemenu")
  frame:SetAttribute("clickbutton2", nil)
  frame:SetAttribute("*clickbutton2", nil)
  return nil
end

local function ConfigureClickTarget(button, unit)
  if not (button and button.SetAttribute) or InCombat() then return false end
  if button._msufSecureUnit ~= unit then
    button:SetAttribute("unit", unit)
    button._msufSecureUnit = unit
  end
  button:SetAttribute("type1", nil)
  button:SetAttribute("*type1", "target")
  UF.AttachSecureUnitMenu(button)
  UF.ConfigurePingableUnitFrame(button)
  button._msufSecureType1Target = true
  button._msufSecureType2Menu = true
  if button._msufSecureToggleVehicle ~= true then
    button:SetAttribute("toggleForVehicle", true)
    button._msufSecureToggleVehicle = true
  end
  if button.RegisterForClicks and button._msufClicksRegistered ~= true then
    button:RegisterForClicks("AnyUp")
    button._msufClicksRegistered = true
  end
  if button.EnableMouse and button._msufMouseEnabledForDirectClick ~= true then
    button:EnableMouse(true)
    button._msufMouseEnabledForDirectClick = true
  end
  return true
end

local function EnsureClickOverlay(frame, unit)
  if not frame then return nil end
  local button = frame._msufClickOverlay
  if button and not InCombat() then
    if UnregisterUnitWatch then UnregisterUnitWatch(button) end
    button._msufClickOverlayWatched = nil
    if button.EnableMouse then button:EnableMouse(false) end
    if button.Hide then button:Hide() end
    frame._msufClickOverlay = nil
  end
  return nil
end

local function SetSecureUnitAttributes(frame, unit)
  frame.unit = unit
  frame.MSUFUnitKey = unit
  frame.unitKey = unit
  EnsureClickOverlay(frame, unit)
  ConfigureClickTarget(frame, unit)
  UF.RegisterClickCastFrame(frame)
end

local function FrameOnShow(frame)
  if not frame or frame._msufDisabledByConfig == true or frame._msufRuntimeOnShowBusy == true then return end
  if not frame.MSUFSpec or frame.MSUFSpec.enabled == false then return end
  if not frame._msufRuntimeAllPath and not frame._msufIdentityPath then return end
  frame._msufRuntimeOnShowBusy = true
  if UF.FrameRuntimeUpdate then UF.FrameRuntimeUpdate(frame, "MSUF_FRAME_SHOWN") end
  frame._msufRuntimeOnShowBusy = nil
end

local function EnsureRuntimeOnShow(frame)
  if not frame or frame._msufRuntimeOnShowHooked == true then return end
  if frame.HookScript then
    frame:HookScript("OnShow", FrameOnShow)
    frame._msufRuntimeOnShowHooked = true
  end
end

local function SpawnFrame(unit)
  if not (UF.IsManagedUnit and UF.IsManagedUnit(unit)) then return nil end
  if UF.ShouldUseMSUFUnitFrame and UF.ShouldUseMSUFUnitFrame(unit) == false then return nil end

  local name = UF.FrameName(unit)
  local parent = ResolvePetBattleFrameHider()
  local frame = _G[name]
  if not (frame and frame.SetAttribute and frame.RegisterForClicks) then
    frame = UF.CreateSecureUnitButton(name, parent)
  elseif frame.SetParent and frame:GetParent() ~= parent and not InCombat() then
    frame:SetParent(parent)
  end
  UF.AttachFrame(frame, { scope = "single" })
  EnsureRuntimeOnShow(frame)
  SetSecureUnitAttributes(frame, unit)
  frame.Enable = function(self)
    if RegisterUnitWatch then RegisterUnitWatch(self) end
    if self.Show then self:Show() end
    return true
  end
  frame.Disable = function(self)
    if UnregisterUnitWatch then UnregisterUnitWatch(self) end
    if self.Hide then self:Hide() end
  end
  if frame.Show then frame:Show() end
  RegisterGlobals(unit, frame)
  return frame
end

local function ApplyFrame(frame, spec)
  if not (frame and spec) then return false end
  if InCombat() then return DeferApply(frame.unit) end

  EnsureRuntimeOnShow(frame)
  UF.SetFrameSpec(frame, spec, frame.unit)
  SetSecureUnitAttributes(frame, frame.unit)

  if spec.enabled == false then
    DisableFrame(frame)
    if UF.DetachFrame then UF.DetachFrame(frame) end
    frame._msufDisabledByConfig = true
    return true
  end

  frame._msufDisabledByConfig = nil
  if ApplySize(frame, spec) == false or ApplyPosition(frame, spec) == false then
    return false
  end

  UF.ApplySpec(frame, spec, "MSUF_APPLY", true)

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
  return true
end

local function ApplyOne(unit, config)
  if not (UF.IsManagedUnit and UF.IsManagedUnit(unit)) then return false end
  if UF.ShouldUseMSUFUnitFrame and UF.ShouldUseMSUFUnitFrame(unit) == false then
    local frame = UF.frames[unit]
    if frame then
      DisableFrame(frame)
      if UF.DetachFrame then UF.DetachFrame(frame) end
      frame._msufDisabledByConfig = true
    end
    return true
  end
  local frame = UF.frames[unit] or SpawnFrame(unit)
  if not frame then return false end
  return ApplyFrame(frame, config.GetSpec(unit))
end

function Factory.SpawnAll()
  if InCombat() then return DeferApply(nil) end
  local config = ResolveConfig(true)
  if not config then return false end
  if UF.DisableBlizzardFrames then UF.DisableBlizzardFrames() end
  for i = 1, #UF.unitOrder do
    ApplyOne(UF.unitOrder[i], config)
  end
  UF.spawned = true
  UF.initialized = true
  if UF.FlushDeferredRefreshes then UF.FlushDeferredRefreshes() end
  return true
end

function Factory.Apply(unit)
  if InCombat() then return DeferApply(unit) end
  if not UF.spawned and not unit then return Factory.SpawnAll() end
  local config = ResolveConfig(unit == nil)
  if not config then return false end

  local units = unit and UF.UnitsForConfigKey and UF.UnitsForConfigKey(unit)
  if unit and not units then return false end
  if units then
    for i = 1, #units do ApplyOne(units[i], config) end
  else
    for i = 1, #UF.unitOrder do ApplyOne(UF.unitOrder[i], config) end
    UF.spawned = true
    UF.initialized = true
  end

  if UF.FlushDeferredRefreshes then UF.FlushDeferredRefreshes() end
  return true
end

local function DeferredOnEvent(self)
  if InCombat() then return end
  self:UnregisterEvent("PLAYER_REGEN_ENABLED")
  if UF.ApplyDirty then UF.ApplyDirty() end
  if UF.FlushDeferredRefreshes then UF.FlushDeferredRefreshes() end
end

function Factory.EnsureDeferredDriver()
  if not Factory.deferredDriver then
    Factory.deferredDriver = CreateFrame("Frame")
    Factory.deferredDriver:SetScript("OnEvent", DeferredOnEvent)
  end
  Factory.deferredDriver:RegisterEvent("PLAYER_REGEN_ENABLED")
  return true
end

local LATE_ANCHOR_KEYS = { "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }

local function HasLateAnchorConfig()
  local db = _G.MSUF_DB
  if type(db) ~= "table" then return false end
  for i = 1, #LATE_ANCHOR_KEYS do
    local conf = db[LATE_ANCHOR_KEYS[i]]
    if type(conf) == "table" then
      local frameName = conf.anchorFrameName
      if type(frameName) == "string" and frameName ~= "" and not IsCooldownViewerAnchor(frameName) then
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
  if InCombat() then
    if UF.RequestReanchorAfterCombat then UF.RequestReanchorAfterCombat() end
    return false
  end
  Factory.Apply()
  if type(_G.MSUF_ClassPower_Apply) == "function" then
    _G.MSUF_ClassPower_Apply({ anchor = true, cdm = true, syncNow = false })
  elseif type(_G.MSUF_ClassPower_Refresh) == "function" then
    _G.MSUF_ClassPower_Refresh()
  end
  return true
end

local function ScheduleLateAnchorReanchor()
  if InCombat() then
    if UF.RequestReanchorAfterCombat then UF.RequestReanchorAfterCombat() end
    return false
  end
  local state = _G.MSUF_LateAnchorReanchorState
  if type(state) ~= "table" then
    state = { pending = false }
    ExportPublic("MSUF_LateAnchorReanchorState", state)
  end
  if state.pending then return false end
  state.pending = true
  if _G.C_Timer and _G.C_Timer.After then
    _G.C_Timer.After(0, function()
      if not state.pending then return end
      state.pending = false
      FlushLateAnchorReanchor()
    end)
  else
    state.pending = false
    FlushLateAnchorReanchor()
  end
  return true
end

ExportPublic("MSUF_ScheduleLateAnchorReanchor", ScheduleLateAnchorReanchor)
ExportPublic("MSUF_ForceReanchorAllUnitFrames_Once", function()
  if InCombat() then
    if UF.RequestReanchorAfterCombat then UF.RequestReanchorAfterCombat() end
    return false
  end
  return Factory.Apply()
end)

do
  local lateAnchorEvents = CreateFrame("Frame")
  lateAnchorEvents:RegisterEvent("PLAYER_LOGIN")
  lateAnchorEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
  lateAnchorEvents:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
  lateAnchorEvents:RegisterEvent("ADDON_LOADED")
  lateAnchorEvents:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon ~= "Blizzard_EditMode" then return end
    if HasLateAnchorConfig() then ScheduleLateAnchorReanchor() end
  end)
end

function UF.Initialize()
  if UF.initialized then return true end
  return Factory.SpawnAll()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_LOGIN")
  UF.Initialize()
end)
