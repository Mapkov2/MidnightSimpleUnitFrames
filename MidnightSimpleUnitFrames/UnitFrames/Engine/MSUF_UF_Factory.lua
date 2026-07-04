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
local select = select
local table_concat = table.concat
local string_format = string.format
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local RegisterUnitWatch = RegisterUnitWatch
local UnregisterUnitWatch = UnregisterUnitWatch
local UnitFrame_OnEnter = UnitFrame_OnEnter
local UnitFrame_OnLeave = UnitFrame_OnLeave
local UnitGUID = UnitGUID
local GetBindingKey = GetBindingKey
local ClearOverrideBindings = ClearOverrideBindings
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

local MAX_ANCHOR_DEPENDENCY_DEPTH = 16

local function AnchorDependsOn(region, target, seen, depth)
  if not (region and target) then
    return false
  end
  if region == target then
    return true
  end
  depth = (tonumber(depth) or 0) + 1
  if depth > MAX_ANCHOR_DEPENDENCY_DEPTH then
    return false
  end
  seen = seen or {}
  if seen[region] then
    return false
  end
  seen[region] = true
  if type(region.GetNumPoints) ~= "function" or type(region.GetPoint) ~= "function" then
    return false
  end

  local count = region:GetNumPoints() or 0
  for i = 1, count do
    local _, relativeTo = region:GetPoint(i)
    if relativeTo == target or AnchorDependsOn(relativeTo, target, seen, depth) then
      return true
    end
  end
  return false
end

local function AnchorWouldCreateCycle(frame, anchor)
  if not (frame and anchor) or anchor == UIParent then
    return false
  end
  return AnchorDependsOn(anchor, frame)
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
    if AnchorWouldCreateCycle(frame, anchor) then
      frame._msufRejectedAnchor, frame._msufRejectedAnchorReason = requestedAnchor, "cycle"
      if frame._msufPositionInitialized == true then
        return true
      end
      local applyCached = _G.MSUF_ApplyCachedUnitFrameScreenPosition
      if type(applyCached) == "function" and applyCached(frame, key, frame.unit) then
        return true
      end
      anchor, missingAnchorName, requestedAnchor = UIParent, requestedAnchor, nil
    else
      frame._msufRejectedAnchor, frame._msufRejectedAnchorReason = nil, nil
    end
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
    if UF.DisablePingCompatibility then
      UF.DisablePingCompatibility(frame)
    end
    frame._msufDisabledByConfig = true
    return true
  end
  frame._msufDisabledByConfig = nil
  if ApplySize(frame, spec) == false or ApplyPosition(frame, spec) == false then
    return false
  end
  if UF.InstallPingCompatibility then
    UF.InstallPingCompatibility(frame)
  end
  UF.RefreshNativePingIcon(frame)
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
  if self and (self._msufGFIsPreviewFrame or self._msufGFPreviewActive) then
    return false
  end
  return PingTargetGUID(self) ~= nil
end

local function MSUF_GetAllowRadialWheel()
  return true
end

local SECURE_UNIT_BUTTON_TEMPLATE = "SecureUnitButtonTemplate"
-- Blizzard's PingableUnitFrameTemplate sends a GUID through protected ping code
-- after reading addon-owned unit data. Use secure /ping macros instead.
local PING_COMPAT_UNIT_BUTTON_TEMPLATE = "SecureUnitButtonTemplate,SecureHandlerEnterLeaveTemplate,SecureHandlerShowHideTemplate"
local PING_ICON_TEMPLATE = "UnitPingIconFrameTemplate"
local MAX_PING_BINDING_KEYS = 2
local SECURE_PING_BINDINGS = {
  { command = "TOGGLEPINGLISTENER", button = "MSUFPing", attrPrefix = "msuf-ping-key-context", macro = "/ping [@mouseover]" },
  { command = "PINGATTACK", button = "MSUFPingAttack", attrPrefix = "msuf-ping-key-attack", macro = "/ping [@mouseover] 1" },
  { command = "PINGWARNING", button = "MSUFPingWarning", attrPrefix = "msuf-ping-key-warning", macro = "/ping [@mouseover] 2" },
  { command = "PINGONMYWAY", button = "MSUFPingOnMyWay", attrPrefix = "msuf-ping-key-onmyway", macro = "/ping [@mouseover] 3" },
  { command = "PINGASSIST", button = "MSUFPingAssist", attrPrefix = "msuf-ping-key-assist", macro = "/ping [@mouseover] 4" },
}
local SECURE_PING_ONENTER = [[
local owner = self:GetFrameRef("MSUFPingBindingOwner") or self
owner:ClearBindings()
local name = self:GetName()
if name then
  local key = self:GetAttribute("msuf-ping-key-context-1")
  if key then owner:SetBindingClick(true, key, name, "MSUFPing") end
  key = self:GetAttribute("msuf-ping-key-context-2")
  if key then owner:SetBindingClick(true, key, name, "MSUFPing") end
  key = self:GetAttribute("msuf-ping-key-attack-1")
  if key then owner:SetBindingClick(true, key, name, "MSUFPingAttack") end
  key = self:GetAttribute("msuf-ping-key-attack-2")
  if key then owner:SetBindingClick(true, key, name, "MSUFPingAttack") end
  key = self:GetAttribute("msuf-ping-key-warning-1")
  if key then owner:SetBindingClick(true, key, name, "MSUFPingWarning") end
  key = self:GetAttribute("msuf-ping-key-warning-2")
  if key then owner:SetBindingClick(true, key, name, "MSUFPingWarning") end
  key = self:GetAttribute("msuf-ping-key-onmyway-1")
  if key then owner:SetBindingClick(true, key, name, "MSUFPingOnMyWay") end
  key = self:GetAttribute("msuf-ping-key-onmyway-2")
  if key then owner:SetBindingClick(true, key, name, "MSUFPingOnMyWay") end
  key = self:GetAttribute("msuf-ping-key-assist-1")
  if key then owner:SetBindingClick(true, key, name, "MSUFPingAssist") end
  key = self:GetAttribute("msuf-ping-key-assist-2")
  if key then owner:SetBindingClick(true, key, name, "MSUFPingAssist") end
end
]]
local SECURE_PING_ONLEAVE = [[
local owner = self:GetFrameRef("MSUFPingBindingOwner") or self
owner:ClearBindings()
]]
local SECURE_PING_ONHIDE = SECURE_PING_ONLEAVE
local pingBindingCache = {}
local pingBindingCacheValid = false
local pingBindingCacheVersion = 0
local pendingPingFrames = setmetatable({}, { __mode = "k" })
local pingEventFrame
local securePingInitialConfig

local function InvalidatePingBindingCache()
  pingBindingCacheValid = false
  pingBindingCacheVersion = pingBindingCacheVersion + 1
end

function UF.GetSecureUnitButtonTemplate()
  return PING_COMPAT_UNIT_BUTTON_TEMPLATE
end

function UF.ResolvePingUnit(frame)
  return ResolvePingUnit(frame)
end

local function InCombat()
  return (InCombatLockdown and InCombatLockdown()) or _G.MSUF_InCombat == true
end

local function EnsurePingEventFrame()
  if pingEventFrame then
    return pingEventFrame
  end
  pingEventFrame = CreateFrame("Frame")
  pingEventFrame:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" then
      if addon ~= "Blizzard_PingUI" then return end
    elseif event ~= "PLAYER_REGEN_ENABLED" and event ~= "UPDATE_BINDINGS" then
      return
    end

    if event == "UPDATE_BINDINGS" then
      InvalidatePingBindingCache()
      if UF.RefreshPingCompatibility then
        UF.RefreshPingCompatibility()
      end
      return
    end

    if not InCombat() then
      self:UnregisterEvent("PLAYER_REGEN_ENABLED")
      for frame in pairs(pendingPingFrames) do
        pendingPingFrames[frame] = nil
        if frame then
          UF.InstallPingCompatibility(frame)
          UF.RefreshNativePingIcon(frame)
        end
      end
    end

    if event == "ADDON_LOADED" then
      self:UnregisterEvent("ADDON_LOADED")
      if UF.RefreshPingCompatibility then
        UF.RefreshPingCompatibility()
      end
    end
  end)
  return pingEventFrame
end

local function QueuePingRefresh(frame)
  if frame then
    pendingPingFrames[frame] = true
  end
  EnsurePingEventFrame():RegisterEvent("PLAYER_REGEN_ENABLED")
end

local function ClearAddonPingMethods(frame)
  if not frame then return false end
  frame.IsPingable = nil
  if frame.GetTargetInfo == MSUF_GetPingTargetInfo then frame.GetTargetInfo = nil end
  if frame.GetTargetPingGUID == MSUF_GetTargetPingGUID then frame.GetTargetPingGUID = nil end
  if frame.GetContextualPingType == MSUF_GetContextualPingType then frame.GetContextualPingType = nil end
  if frame.GetIsPingable == MSUF_GetIsPingable then frame.GetIsPingable = nil end
  if frame.GetAllowRadialWheel == MSUF_GetAllowRadialWheel then frame.GetAllowRadialWheel = nil end
  return true
end

local function ClearLegacyPingReceiver(frame)
  if not (frame and frame.SetAttribute) then
    return false
  end
  if frame.ClearAttribute then
    frame:ClearAttribute("ping-receiver")
    frame:ClearAttribute("ping-top-level-pass-through")
  else
    frame:SetAttribute("ping-receiver", nil)
    frame:SetAttribute("ping-top-level-pass-through", nil)
  end
  return true
end

local function PingBindingKey(command, index)
  if not GetBindingKey then
    return nil
  end
  return select(index, GetBindingKey(command))
end

local function RefreshPingBindingCache()
  if pingBindingCacheValid then
    return pingBindingCache, pingBindingCacheVersion
  end

  local n = 0
  for i = 1, #SECURE_PING_BINDINGS do
    local info = SECURE_PING_BINDINGS[i]
    for keyIndex = 1, MAX_PING_BINDING_KEYS do
      n = n + 1
      local slot = pingBindingCache[n]
      if not slot then
        slot = {}
        pingBindingCache[n] = slot
      end
      slot.attribute = info.attrPrefix .. "-" .. keyIndex
      slot.key = PingBindingKey(info.command, keyIndex)
    end
  end
  for i = n + 1, #pingBindingCache do
    pingBindingCache[i] = nil
  end

  pingBindingCacheValid = true
  return pingBindingCache, pingBindingCacheVersion
end

function UF.ForEachPingBindingAttribute(callback)
  if type(callback) ~= "function" then
    return
  end
  local bindings = RefreshPingBindingCache()
  for i = 1, #bindings do
    local slot = bindings[i]
    callback(slot.attribute, slot.key)
  end
end

local function ApplyPingBindingKeys(frame, force)
  local bindings, version = RefreshPingBindingCache()
  if force ~= true and frame._msufPingBindingVersion == version then
    return false
  end
  for i = 1, #bindings do
    local slot = bindings[i]
    frame:SetAttribute(slot.attribute, slot.key)
  end
  frame._msufPingBindingVersion = version
  return true
end

local function EnsurePingBindingOwner(frame)
  if not frame or frame._msufPingBindingOwner or type(frame.SetFrameRef) ~= "function" then
    return true
  end
  local ok, owner = pcall(CreateFrame, "Frame", nil, frame, "SecureHandlerBaseTemplate")
  if not ok or not owner then
    frame._msufPingBindingOwnerError = owner
    return true
  end
  frame._msufPingBindingOwner = owner
  frame:SetFrameRef("MSUFPingBindingOwner", owner)
  return true
end

local function ClearPingOverrideBindings(frame)
  if not (ClearOverrideBindings and frame) then
    return
  end
  ClearOverrideBindings(frame._msufPingBindingOwner or frame)
end

local function ApplySecurePingCompatibility(frame)
  if not (frame and frame.SetAttribute) then
    return false
  end
  local unit = ResolvePingUnit(frame)
  if frame._msufGFIsPreviewFrame or frame._msufGFPreviewActive or not unit then
    return false
  end
  if InCombat() then
    QueuePingRefresh(frame)
    return false
  end

  local _, bindingVersion = RefreshPingBindingCache()
  if frame._msufPingCompatInstalled == true
    and frame._msufPingCompatConfigured == true
    and frame._msufPingCompatUnit == unit
    and frame._msufPingBindingVersion == bindingVersion then
    return true
  end

  ClearAddonPingMethods(frame)
  ClearLegacyPingReceiver(frame)
  EnsurePingBindingOwner(frame)

  for _, info in ipairs(SECURE_PING_BINDINGS) do
    frame:SetAttribute("type-" .. info.button, "macro")
    frame:SetAttribute("macrotext-" .. info.button, info.macro)
  end
  ApplyPingBindingKeys(frame, true)
  frame:SetAttribute("_onenter", SECURE_PING_ONENTER)
  frame:SetAttribute("_onleave", SECURE_PING_ONLEAVE)
  frame:SetAttribute("_onhide", SECURE_PING_ONHIDE)
  frame._msufPingCompatConfigured = true
  frame._msufPingCompatUnit = unit
  return true
end

local function BuildSecurePingInitialConfig()
  local lines = {}
  for _, info in ipairs(SECURE_PING_BINDINGS) do
    lines[#lines + 1] = string_format("self:SetAttribute(%q, %q)", "type-" .. info.button, "macro")
    lines[#lines + 1] = string_format("self:SetAttribute(%q, %q)", "macrotext-" .. info.button, info.macro)
  end
  lines[#lines + 1] = "local msufPingHeader = self:GetParent()"
  UF.ForEachPingBindingAttribute(function(attribute)
    lines[#lines + 1] = string_format("self:SetAttribute(%q, msufPingHeader and msufPingHeader:GetAttribute(%q) or nil)", attribute, attribute)
  end)
  return table_concat(lines, "\n")
end

function UF.GetSecurePingInitialConfig()
  if not securePingInitialConfig then
    securePingInitialConfig = BuildSecurePingInitialConfig()
  end
  return securePingInitialConfig
end

function UF.DisablePingCompatibility(frame)
  if not frame then return false end
  if InCombat() then
    QueuePingRefresh(frame)
    return false
  end
  ClearPingOverrideBindings(frame)
  ClearAddonPingMethods(frame)
  ClearLegacyPingReceiver(frame)
  frame._msufPingCompatInstalled = nil
  frame._msufPingCompatConfigured = nil
  frame._msufPingCompatUnit = nil
  frame._msufPingBindingVersion = nil
  return true
end

function UF.InstallPingCompatibility(frame)
  if not frame then
    return false
  end
  if IsForbidden and IsForbidden(frame) then
    return false
  end
  local unit = ResolvePingUnit(frame)
  if frame._msufGFIsPreviewFrame or frame._msufGFPreviewActive or not unit then
    return false
  end
  if InCombat() then
    if frame._msufPingCompatInstalled == true
      and frame._msufPingCompatConfigured == true
      and frame._msufPingCompatUnit == unit
      and pingBindingCacheValid == true
      and frame._msufPingBindingVersion == pingBindingCacheVersion then
      return true
    end
    QueuePingRefresh(frame)
    return frame._msufPingCompatInstalled == true
  end
  local ok = ApplySecurePingCompatibility(frame)
  frame._msufPingCompatInstalled = ok and true or nil
  return ok
end

function UF.RefreshPingCompatibility()
  for i = 1, #UF.frameList do
    local frame = UF.frameList[i]
    if frame then
      UF.InstallPingCompatibility(frame)
      UF.RefreshNativePingIcon(frame)
    end
  end
  local GF = MSUF.GF
  if GF and type(GF.ForEachFrame) == "function" then
    GF.ForEachFrame(function(frame)
      UF.InstallPingCompatibility(frame)
      UF.RefreshNativePingIcon(frame)
    end, true)
  end
  return true
end
ExportPublic("MSUF_RefreshPingCompatibility", UF.RefreshPingCompatibility)

local function PingDebugValue(frame)
  if not frame then return nil end
  local unit = ResolvePingUnit(frame)
  return {
    frame = frame.GetName and frame:GetName() or tostring(frame),
    unit = unit,
    guid = unit and UnitGUID(unit) or nil,
    pingReceiver = frame.GetAttribute and frame:GetAttribute("ping-receiver") or nil,
    passThrough = frame.GetAttribute and frame:GetAttribute("ping-top-level-pass-through") or nil,
    hasTargetInfo = type(frame.GetTargetInfo) == "function",
    hasIsPingable = type(frame.GetIsPingable) == "function",
    hasPingBindingOwner = frame._msufPingBindingOwner ~= nil,
    addonTargetInfo = frame.GetTargetInfo == MSUF_GetPingTargetInfo,
    addonIsPingable = frame.GetIsPingable == MSUF_GetIsPingable,
    addonAllowRadial = frame.GetAllowRadialWheel == MSUF_GetAllowRadialWheel,
    isPingable = type(frame.GetIsPingable) == "function" and frame:GetIsPingable() or nil,
    allowRadial = type(frame.GetAllowRadialWheel) == "function" and frame:GetAllowRadialWheel() or nil,
    pingMacro = frame.GetAttribute and frame:GetAttribute("macrotext-MSUFPing") or nil,
    pingKey1 = frame.GetAttribute and frame:GetAttribute("msuf-ping-key-context-1") or nil,
    attackKey1 = frame.GetAttribute and frame:GetAttribute("msuf-ping-key-attack-1") or nil,
    pingTemplate = frame._msufPingTemplate,
    pingCompat = frame._msufPingCompatInstalled == true,
    nativePingGUID = frame._msufNativePingGUID,
  }
end

local function CountArray(list)
  return type(list) == "table" and #list or 0
end

local function FrameMatchesUnit(frame, unit)
  if not frame or type(unit) ~= "string" then
    return false
  end
  if frame.unit == unit or frame.MSUFUnitKey == unit or frame.unitKey == unit then
    return true
  end
  if frame.GetAttribute then
    return frame:GetAttribute("unit") == unit
  end
  return false
end

local function FindPingDebugFrame(unit)
  local frame = UF.frames and UF.frames[unit]
  if frame then
    return frame, "UF.frames"
  end
  if UF.FrameName then
    frame = _G[UF.FrameName(unit)]
    if frame then
      return frame, "global"
    end
  end
  if type(UF.frameList) == "table" then
    for i = 1, #UF.frameList do
      frame = UF.frameList[i]
      if FrameMatchesUnit(frame, unit) then
        return frame, "UF.frameList"
      end
    end
  end
  local GF = MSUF.GF
  if GF and type(GF.FrameForUnit) == "function" then
    frame = GF.FrameForUnit(unit)
    if frame then
      return frame, "GF.FrameForUnit"
    end
  end
  if GF and type(GF.frameList) == "table" then
    for i = 1, #GF.frameList do
      frame = GF.frameList[i]
      if FrameMatchesUnit(frame, unit) then
        return frame, "GF.frameList"
      end
    end
  end
  return nil, nil
end

ExportPublic("MSUF_DebugPingFrame", function(unitOrFrame)
  local frame = unitOrFrame
  local source
  if type(unitOrFrame) == "string" then
    frame, source = FindPingDebugFrame(unitOrFrame)
    if not frame then
      local GF = MSUF.GF
      return {
        missing = true,
        requested = unitOrFrame,
        expectedGlobal = UF.FrameName and UF.FrameName(unitOrFrame) or nil,
        ufFrameListCount = CountArray(UF.frameList),
        gfFrameListCount = GF and CountArray(GF.frameList) or 0,
      }
    end
  end
  local info = PingDebugValue(frame)
  if info then
    info.source = source
  end
  return info or {
    missing = true,
    requested = unitOrFrame,
    ufFrameListCount = CountArray(UF.frameList),
  }
end)

function UF.CreateSecureUnitButton(name, parent)
  local ok, frame = pcall(CreateFrame, "Button", name, parent or UIParent, PING_COMPAT_UNIT_BUTTON_TEMPLATE)
  if ok and frame then
    frame._msufPingTemplate = PING_COMPAT_UNIT_BUTTON_TEMPLATE
    return frame
  end
  UF._pingableUnitButtonTemplateError = frame
  frame = CreateFrame("Button", name, parent or UIParent, SECURE_UNIT_BUTTON_TEMPLATE)
  frame._msufPingTemplate = SECURE_UNIT_BUTTON_TEMPLATE
  return frame
end

EnsurePingEventFrame():RegisterEvent("UPDATE_BINDINGS")

if type(_G.UnitPingIconFrameMixin) ~= "table" then
  EnsurePingEventFrame():RegisterEvent("ADDON_LOADED")
end

function UF.EnsureNativePingIcon(frame)
  if not frame then
    return nil
  end
  local ping = frame.pingIconFrame or frame.PingIconFrame
  if not ping then
    if InCombat() or type(_G.UnitPingIconFrameMixin) ~= "table" then
      frame._msufNativePingGUID = nil
      return nil
    end
    local ok, created = pcall(CreateFrame, "Frame", nil, frame, PING_ICON_TEMPLATE)
    if not ok or not created then
      frame._msufNativePingGUID = nil
      frame._msufNativePingIconError = created
      return nil
    end
    ping = created
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
    if type(ping.SetGUIDMatch) == "function" then
      ping:SetGUIDMatch(function(guid)
        return guid ~= nil and guid == frame._msufNativePingGUID
      end)
    end
  end
  ping.isRaidFrame = frame._msufIsGroupFrame == true
  frame.pingIconFrame = ping
  frame.PingIconFrame = ping
  if ping.Show then
    ping:Show()
  end
  return ping
end

function UF.RefreshNativePingIcon(frame)
  if not frame then return false end
  local unit = UF.ResolvePingUnit and UF.ResolvePingUnit(frame) or frame and frame.unit
  local guid = unit and UnitGUID(unit) or nil
  local ping = frame.pingIconFrame or frame.PingIconFrame
  if ping and ping._msufNativePingIconConfigured == true and frame._msufNativePingGUID == guid then
    return true
  end
  if guid == nil and not ping then
    frame._msufNativePingGUID = nil
    return false
  end
  ping = UF.EnsureNativePingIcon(frame)
  if not ping then
    return false
  end
  if frame._msufNativePingGUID == guid then
    return true
  end
  frame._msufNativePingGUID = guid
  if guid == nil then
    if ping.ClearPing then ping:ClearPing() end
  else
    ping:Show()
  end
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
    frame = UF.CreateSecureUnitButton(name, UIParent)
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
      if UF.DetachFrame then
        UF.DetachFrame(frame)
      end
      if UF.DisablePingCompatibility then
        UF.DisablePingCompatibility(frame)
      end
      frame._msufDisabledByConfig = true
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
