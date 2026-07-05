--- UnitFrames/Engine/Group/MSUF_UF_Group_Runtime.lua
--- Runtime coordinator for party/raid/mythicraid frames.
---
--- This file owns roster/zone events, combat deferral, header visibility,
--- rebuild-vs-refresh decisions, and public GF.Refresh* bridge functions. The
--- actual secure header setup lives in Headers, per-child tracking in Adapter,
--- and visual/status work in registered UF elements.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = MSUF
local ExportPublic = MSUF.ExportPublic or function(name, value)
  _G[name] = value
  return value
end

local GF = MSUF.GF or {}
MSUF.GF = GF
local UF = MSUF.UF
local Metadata = GF.Metadata or {}

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local InCombatLockdown = InCombatLockdown
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local GetNumSubgroupMembers = GetNumSubgroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local GetInstanceInfo = GetInstanceInfo
local UnitGUID = UnitGUID
local UnitName = UnitName
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local C_Housing = _G.C_Housing
local floor = math.floor
local table_concat = table.concat
local type = type
local tostring = tostring
local wipe = wipe or function(t)
  for k in pairs(t) do
    t[k] = nil
  end
  return t
end
local issecretvalue = _G.issecretvalue or function(_) return false end

local function IsUnitToken(unit)
  return issecretvalue(unit) ~= true and type(unit) == "string" and unit ~= ""
end

local eventFrame
local rosterRebuildQueued = false
local zoneRefreshQueued = false
local rosterSettleToken = 0
local nameEventsRegistered = false
local rosterEventsRegistered = false
local lastRosterMode
local lastRosterSignature
local lastRosterStructureSignature
local lastRosterLayoutSignature
local lastDifficultyToken
local rosterSignatureParts = {}
local ROSTER_EVENTS = { "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "ROLE_CHANGED_INFORM" }
local INIT_EVENTS = {
  "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_DIFFICULTY_CHANGED",
  "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
  "BARBER_SHOP_OPEN", "BARBER_SHOP_CLOSE",
}

local function ConfEnabled(kind)
  local conf = GF.GetConf and GF.GetConf(kind)
  return conf and conf.enabled == true
end

local function AnyGroupFrameEnabled()
  if type(GF.AnyMSUFGroupFrameEnabled) == "function" then
    return GF.AnyMSUFGroupFrameEnabled() == true
  end
  return ConfEnabled("party") or ConfEnabled("raid") or ConfEnabled("mythicraid")
end

GF.AnyGroupRuntimeEnabled = AnyGroupFrameEnabled

local function InCombat()
  return InCombatLockdown and InCombatLockdown()
end

local band = bit and bit.band or bit32 and bit32.band
local bor = bit and bit.bor or bit32 and bit32.bor
local DIRTY_FLAGS = {
  GF.DIRTY_GEOMETRY, GF.DIRTY_VISUAL, GF.DIRTY_FONT, GF.DIRTY_COLOR,
  GF.DIRTY_BORDER, GF.DIRTY_LAYOUT, GF.DIRTY_AURAS,
  GF.DIRTY_UNIT_BINDING, GF.DIRTY_CONFIG,
}
local function Has(mask, flag)
  if not mask then return false end
  if band then return band(mask, flag) ~= 0 end
  return mask % (flag * 2) >= flag
end

local function OrMask(a, b)
  if a == nil or b == nil then return nil end
  if bor then return bor(a, b) end
  local out = a
  for i = 1, #DIRTY_FLAGS do
    local flag = DIRTY_FLAGS[i]
    if flag and Has(b, flag) and not Has(out, flag) then
      out = out + flag
    end
  end
  return out
end

local MASK_RUNTIME = Metadata.MASK_RUNTIME or {}
local DIRTY_APPLY_MASKS = Metadata.dirtyApplyMasks or {}

local function DirtyApplyMask(mask)
  if not mask or mask == GF.DIRTY_ALL
    or Has(mask, GF.DIRTY_GEOMETRY)
    or Has(mask, GF.DIRTY_LAYOUT)
    or Has(mask, GF.DIRTY_UNIT_BINDING)
    or Has(mask, GF.DIRTY_CONFIG) then
    return nil
  end
  return DIRTY_APPLY_MASKS[mask] or MASK_RUNTIME
end

local function DirtyRuntimeReason(mask, reason)
  if reason ~= nil and reason ~= "MSUF_GF_REFRESH_VISUALS" and reason ~= "MSUF_GF_MARK_DIRTY" then
    return reason
  end
  if mask == GF.DIRTY_FONT then
    return "MSUF_GF_DIRTY_FONT"
  end
  if mask == GF.DIRTY_BORDER then
    return "MSUF_GF_DIRTY_BORDER"
  end
  if mask == GF.DIRTY_AURAS then
    return "MSUF_GF_DIRTY_AURAS"
  end
  return reason or "MSUF_GF_DIRTY"
end

local function BumpAuras3ConfigForGroup(mask)
  if mask ~= nil and mask ~= GF.DIRTY_ALL and not Has(mask, GF.DIRTY_AURAS) then return end
  local A3 = MSUF and MSUF.MSUF_Auras3
  if A3 and type(A3.BumpRuntimeConfig) == "function" then
    A3.BumpRuntimeConfig()
  end
end

local function InvalidateSpecs(kind)
  if GF.InvalidateCompiledSpecs then
    GF.InvalidateCompiledSpecs(kind)
  end
end

local function DropSpecs(kind)
  if GF.DropCompiledSpecs then
    GF.DropCompiledSpecs(kind)
  elseif GF.InvalidateCompiledSpecs then
    GF.InvalidateCompiledSpecs(kind)
  end
end

local function ApplyFrameDirty(frame, kind, mask, reason)
  local profToken = GF.ProfBegin and GF.ProfBegin("applySpec")
  local applyMask = DirtyApplyMask(mask)
  if not applyMask then
    local result = GF.ApplyButton and GF.ApplyButton(frame, kind, reason or "MSUF_GF_DIRTY_FULL")
    if GF.ProfEnd then GF.ProfEnd("applySpec", profToken) end
    return result
  end
  if not (UF and UF.ApplySpec and GF.CompileSpec) then
    local result = GF.ApplyButton and GF.ApplyButton(frame, kind, reason or "MSUF_GF_DIRTY_FALLBACK")
    if GF.ProfEnd then GF.ProfEnd("applySpec", profToken) end
    return result
  end
  local spec = GF.CompileSpec(kind, frame, frame and frame.unit)
  local dirtyReason = DirtyRuntimeReason(mask, reason)
  local applyStructure = GF.ApplyStructureSpec
  local result
  if applyStructure then
    result = applyStructure(frame, spec, dirtyReason, applyMask)
  else
    result = UF.ApplySpec(frame, spec, dirtyReason, applyMask)
    if GF.RebindGroupHotRuntime then
      GF.RebindGroupHotRuntime(frame, spec)
    end
  end
  if GF.ProfEnd then GF.ProfEnd("applySpec", profToken) end
  return result
end

local function RefreshVisualsFrame(frame, _, frameKind, refreshKind, mask)
  if not refreshKind or refreshKind == frameKind then
    ApplyFrameDirty(frame, frameKind, mask, "MSUF_GF_REFRESH_VISUALS")
  end
end

local function AddPendingRefresh(kind, mask)
  if GF._pendingGroupRefresh == true then
    if GF._pendingGroupRefreshKind ~= kind then
      GF._pendingGroupRefreshKind = nil
    end
    if GF._pendingGroupRefreshMaskSet == true then
      GF._pendingGroupRefreshMask = OrMask(GF._pendingGroupRefreshMask, mask)
    else
      GF._pendingGroupRefreshMask = mask
      GF._pendingGroupRefreshMaskSet = true
    end
    return
  end
  GF._pendingGroupRefresh = true
  GF._pendingGroupRefreshKind = kind
  GF._pendingGroupRefreshMask = mask
  GF._pendingGroupRefreshMaskSet = true
end

local PENDING_REBUILD_PRIORITY = { roster = 1, rebuild = 2, zone = 3 }
local function RememberPendingRebuildReason(reason)
  local current = GF._pendingGroupRebuildReason
  if not current or (PENDING_REBUILD_PRIORITY[reason] or 0) > (PENDING_REBUILD_PRIORITY[current] or 0) then
    GF._pendingGroupRebuildReason = reason
  end
end

function GF.DeferGroupRuntime(reason, kind, mask)
  -- Group headers are secure/protected. Any refresh that could move, create, or
  -- rebind children while in combat is reduced to flags and replayed on regen.
  reason = reason or "refresh"
  GF._pendingGroupRuntime = reason
  if reason == "roster" then
    GF._pendingGroupUnitBinding = true
    RememberPendingRebuildReason(reason)
  elseif reason == "zone" then
    GF._pendingGroupLayout = true
    GF._pendingGroupDropSpecs = true
  elseif reason == "layout" or reason == "geometry" or reason == "setup" then
    GF._pendingGroupLayout = true
  elseif reason == "rebuild" then
    GF._pendingGroupRebuild = true
    RememberPendingRebuildReason(reason)
  elseif reason == "visibility" then
    GF._pendingGroupVisibility = true
  else
    AddPendingRefresh(kind, mask)
  end
  if eventFrame then
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
  end
end

local function GroupUnitMatches(frame, unit, unitGuid)
  local frameUnit = frame and frame.unit
  if unit == nil then
    return true
  end
  if issecretvalue(unit) == true then return false end
  if type(unit) ~= "string" then return false end
  if unit == "" then return true end
  if not IsUnitToken(frameUnit) then return false end
  if frameUnit == unit then
    return true
  end
  if not frameUnit then
    return false
  end
  local frameGuid = UnitGUID(frameUnit)
  unitGuid = unitGuid or UnitGUID(unit)
  if issecretvalue(frameGuid) == true or issecretvalue(unitGuid) == true then
    return false
  end
  return frameGuid ~= nil and frameGuid == unitGuid
end

local function RefreshGroupNameFrame(frame, _, _, runtime, matchUnit, matchGuid)
  local active = frame and frame._msufActiveElements
  if active and active.NameText == true and GroupUnitMatches(frame, matchUnit, matchGuid) then
    runtime.UpdateName(frame, "MSUF_GF_NAME_UPDATE", frame.unit)
    return true
  end
end

function GF.RefreshGroupNames(unit)
  if InCombat() then
    return false
  end
  local runtime = MSUF.UFTextRuntime
  if not (runtime and runtime.UpdateName) then
    return false
  end
  if IsUnitToken(unit) and GF.FrameForUnit then
    local frame = GF.FrameForUnit(unit)
    local active = frame and frame._msufActiveElements
    if active and active.NameText == true then
      runtime.UpdateName(frame, "MSUF_GF_NAME_UPDATE", frame.unit)
      return true
    end
    if not GF.ForEachFrame then
      return false
    end
  elseif not GF.ForEachFrame then
    return false
  end
  local matchGuid
  if IsUnitToken(unit) then
    local guid = UnitGUID(unit)
    if issecretvalue(guid) ~= true then
      matchGuid = guid
    end
  end
  return GF.ForEachFrame(RefreshGroupNameFrame, true, runtime, unit, matchGuid) == true
end

local CurrentGroupRuntimeActive

local function RegisterNameEvents()
  if eventFrame and not nameEventsRegistered and not InCombat()
    and CurrentGroupRuntimeActive and CurrentGroupRuntimeActive() == true then
    eventFrame:RegisterEvent("UNIT_NAME_UPDATE")
    nameEventsRegistered = true
  end
end

local function UnregisterNameEvents()
  if eventFrame and nameEventsRegistered then
    eventFrame:UnregisterEvent("UNIT_NAME_UPDATE")
    nameEventsRegistered = false
  end
end

local function RegisterRosterEvents()
  if eventFrame and not rosterEventsRegistered and not InCombat() and AnyGroupFrameEnabled() then
    for i = 1, #ROSTER_EVENTS do
      eventFrame:RegisterEvent(ROSTER_EVENTS[i])
    end
    rosterEventsRegistered = true
  end
end

local function UnregisterRosterEvents()
  if eventFrame and rosterEventsRegistered then
    for i = 1, #ROSTER_EVENTS do
      eventFrame:UnregisterEvent(ROSTER_EVENTS[i])
    end
    rosterEventsRegistered = false
  end
end

local function RefreshRuntimeEventRegistration()
  if InCombat() or not AnyGroupFrameEnabled() then
    UnregisterNameEvents()
    UnregisterRosterEvents()
    return false
  end
  if CurrentGroupRuntimeActive and CurrentGroupRuntimeActive() == true then
    RegisterNameEvents()
  else
    UnregisterNameEvents()
  end
  RegisterRosterEvents()
  return true
end

local function LiveRaidKind()
  return GF.GetLiveRaidKind and GF.GetLiveRaidKind() or "raid"
end

local function ShouldShowParty()
  local conf = GF.GetConf and GF.GetConf("party") or {}
  if conf.enabled ~= true or (IsInRaid and IsInRaid()) then
    return false
  end
  if IsInGroup and IsInGroup() then
    return true
  end
  return conf.showSolo == true and conf.showPlayer ~= false
end

CurrentGroupRuntimeActive = function()
  if IsInRaid and IsInRaid() then
    local conf = GF.GetConf and GF.GetConf(LiveRaidKind()) or {}
    return conf.enabled == true
  end
  return ShouldShowParty()
end

local function RosterMode()
  if IsInRaid and IsInRaid() then
    return "raid"
  end
  if IsInGroup and IsInGroup() then
    return "party"
  end
  return "solo"
end

local function MarkRosterMode()
  local mode = RosterMode()
  if lastRosterMode ~= nil and lastRosterMode ~= mode then
    GF._forceRecreateHeaders = true
  end
  lastRosterMode = mode
  return mode
end

local function UnitIdentity(unit)
  if not IsUnitToken(unit) then
    return ""
  end
  local guid = UnitGUID(unit)
  if issecretvalue(guid) ~= true and guid then return guid end
  if UnitName then
    local name, realm = UnitName(unit)
    if issecretvalue(name) ~= true and name and name ~= "" then
      if issecretvalue(realm) ~= true and realm and realm ~= "" then
        return name .. "-" .. realm
      end
      return name
    end
  end
  return unit
end

local function UnitRoleToken(unit)
  return (UnitGroupRolesAssigned and IsUnitToken(unit) and UnitGroupRolesAssigned(unit)) or ""
end

local function CurrentRosterSignature(includeRoles)
  local mode = RosterMode()
  local parts = rosterSignatureParts
  wipe(parts)
  parts[1] = mode
  local n = 1
  local raidConf = GF.GetConf and GF.GetConf(LiveRaidKind()) or {}
  local wantRaid = (IsInRaid and IsInRaid()) and raidConf.enabled == true
  local wantParty = ShouldShowParty()
  n = n + 1
  parts[n] = wantParty and "party:on" or "party:off"
  n = n + 1
  parts[n] = wantRaid and "raid:on" or "raid:off"
  if mode == "raid" and wantRaid then
    local count = GetNumGroupMembers and (GetNumGroupMembers() or 0) or 0
    n = n + 1
    parts[n] = tostring(count)
    for i = 1, count do
      local unit = "raid" .. i
      local subgroup = GetRaidRosterInfo and select(3, GetRaidRosterInfo(i)) or ""
      n = n + 1
      parts[n] = UnitIdentity(unit)
      if includeRoles ~= false then
        n = n + 1
        parts[n] = UnitRoleToken(unit)
      end
      n = n + 1
      parts[n] = tostring(subgroup or "")
    end
  elseif mode == "party" and wantParty then
    local count = GetNumSubgroupMembers and (GetNumSubgroupMembers() or 0) or 0
    n = n + 1
    parts[n] = tostring(count)
    n = n + 1
    parts[n] = UnitIdentity("player")
    if includeRoles ~= false then
      n = n + 1
      parts[n] = UnitRoleToken("player")
    end
    for i = 1, count do
      local unit = "party" .. i
      n = n + 1
      parts[n] = UnitIdentity(unit)
      if includeRoles ~= false then
        n = n + 1
        parts[n] = UnitRoleToken(unit)
      end
    end
  end
  return table_concat(parts, "\031", 1, n)
end

local function CurrentRosterLayoutSignature()
  local mode = RosterMode()
  local parts = rosterSignatureParts
  wipe(parts)
  local raidKind = LiveRaidKind()
  local raidConf = GF.GetConf and GF.GetConf(raidKind) or {}
  local wantRaid = (IsInRaid and IsInRaid()) and raidConf.enabled == true
  local wantParty = ShouldShowParty()
  local n = 1
  parts[n] = mode
  n = n + 1
  parts[n] = wantParty and "party:on" or "party:off"
  n = n + 1
  parts[n] = wantRaid and "raid:on" or "raid:off"
  n = n + 1
  parts[n] = raidKind
  if mode == "raid" and wantRaid then
    n = n + 1
    parts[n] = tostring(GetNumGroupMembers and (GetNumGroupMembers() or 0) or 0)
  elseif mode == "party" and wantParty then
    n = n + 1
    parts[n] = tostring(GetNumSubgroupMembers and (GetNumSubgroupMembers() or 0) or 0)
  end
  return table_concat(parts, "\031", 1, n)
end

local function RefreshRosterSignature()
  -- Track two signatures: structural changes need secure header work, while
  -- role-only changes are handled by per-frame runtime/status refreshes.
  lastRosterSignature = CurrentRosterSignature(true)
  lastRosterStructureSignature = CurrentRosterSignature(false)
  lastRosterLayoutSignature = CurrentRosterLayoutSignature()
end

local function CurrentDifficultyToken()
  if not GetInstanceInfo then
    return nil
  end
  local _, instanceType, difficultyID, _, _, _, _, instanceMapID = GetInstanceInfo()
  return tostring(instanceType) .. ":" .. tostring(difficultyID) .. ":" .. tostring(instanceMapID)
end

local function RosterSignatureChanged()
  local current = CurrentRosterSignature(true)
  return current ~= lastRosterSignature
end

local function RosterStructureChanged()
  local current = CurrentRosterSignature(false)
  return current ~= lastRosterStructureSignature
end

local function RosterLayoutChanged()
  local current = CurrentRosterLayoutSignature()
  return current ~= lastRosterLayoutSignature
end

local function HeaderKindForKey(key)
  if key == "raid" then
    return LiveRaidKind()
  end
  return key
end

local function InHousing()
  local fn = C_Housing and C_Housing.IsInsideHouseOrPlot
  if type(fn) ~= "function" then
    return false
  end
  return fn() == true
end

local function HeaderLoadHidden(key)
  local kind = HeaderKindForKey(key)
  local conf = GF.GetConf and GF.GetConf(kind) or nil
  if not conf then
    return false
  end
  if GF._clientSceneActive == true and conf.hideInClientScene ~= false then
    return true
  end
  if conf.hideInHousing == true and InHousing() then
    return true
  end
  return false
end

local function ApplyHeaderSceneAlpha(key)
  local header = GF.headers and GF.headers[key]
  local anchor = GF.anchors and GF.anchors[key]
  local hidden = HeaderLoadHidden(key)
  if header then
    header._msufGF_clientSceneHidden = hidden and true or nil
  end
  if anchor and anchor.SetAlpha then
    anchor:SetAlpha(hidden and 0 or 1)
  elseif header and header.SetAlpha then
    header:SetAlpha(hidden and 0 or 1)
  end
end

local function ApplySceneAlphas()
  ApplyHeaderSceneAlpha("party")
  ApplyHeaderSceneAlpha("raid")
end

local RefreshRosterStateBindings
local RefreshStructuralMask
local ResetRefreshSlice

local function ScanRaidHeaderChildren()
  local header = GF.headers and GF.headers.raid
  if not (header and GF.ScheduleScan) then
    return false
  end
  GF.ScheduleScan("raid", LiveRaidKind())
  return true
end

local function ScheduleRosterSettle()
  if RosterMode() ~= "raid" or not CurrentGroupRuntimeActive() then
    return
  end
  rosterSettleToken = rosterSettleToken + 1
  local token = rosterSettleToken
  local function Run()
    if token ~= rosterSettleToken or RosterMode() ~= "raid" then
      return
    end
    local layoutChanged = GF._forceRecreateHeaders == true or RosterLayoutChanged()
    local bindingChanged = RosterStructureChanged()
    local stateChanged = RosterSignatureChanged()
    if layoutChanged then
      GF._forceScanHeaders = true
      GF.RefreshHeaderLayout("rosterSettle")
      return
    end
    if bindingChanged then
      if not ScanRaidHeaderChildren() then
        GF._forceScanHeaders = true
        GF.RefreshUnitBindings()
      else
        RefreshRosterStateBindings()
      end
      return
    end
    if stateChanged then
      RefreshRosterStateBindings()
      GF.RefreshVisuals(nil, GF.DIRTY_VISUAL)
    end
  end
  C_Timer.After(0.15, Run)
  C_Timer.After(0.60, Run)
end

local dbReadyRetryToken = 0
local function DBReady()
  return type(_G.MSUF_DB) == "table"
end

local function ScheduleDBReadyRetry(builder)
  if DBReady() then
    return
  end
  dbReadyRetryToken = dbReadyRetryToken + 1
  local token = dbReadyRetryToken
  local attempt = 0
  local function Run()
    if token ~= dbReadyRetryToken then return end
    if not DBReady() then
      attempt = attempt + 1
      if attempt <= 20 then
        C_Timer.After(0.1, Run)
      end
      return
    end
    builder()
  end
  C_Timer.After(0.1, Run)
end

local groupRuntimeDeferFrame
local groupRuntimeDeferActive
local groupRuntimeDeferQueue = {}
local groupRuntimeDeferKeys = {}
local groupRuntimeDeferCount = 0

local function GroupRuntimeDeferOnUpdate(self)
  if self then
    self:SetScript("OnUpdate", nil)
  end
  groupRuntimeDeferActive = nil
  local count = groupRuntimeDeferCount
  groupRuntimeDeferCount = 0
  for i = 1, count do
    local key = groupRuntimeDeferKeys[i]
    groupRuntimeDeferKeys[i] = nil
    local fn = groupRuntimeDeferQueue[key]
    groupRuntimeDeferQueue[key] = nil
    if type(fn) == "function" then
      fn()
    end
  end
  if groupRuntimeDeferCount > 0 and groupRuntimeDeferFrame then
    groupRuntimeDeferActive = true
    groupRuntimeDeferFrame:SetScript("OnUpdate", GroupRuntimeDeferOnUpdate)
  end
end

local function ScheduleGroupRuntimeNextFrame(key, fn)
  if type(fn) ~= "function" then return false end
  if _G.MSUF_ScheduleOnce then
    _G.MSUF_ScheduleOnce(key, fn)
    return true
  end
  if not groupRuntimeDeferFrame then
    groupRuntimeDeferFrame = CreateFrame("Frame")
  end
  key = key or fn
  if groupRuntimeDeferQueue[key] == nil then
    groupRuntimeDeferCount = groupRuntimeDeferCount + 1
    groupRuntimeDeferKeys[groupRuntimeDeferCount] = key
  end
  groupRuntimeDeferQueue[key] = fn
  if not groupRuntimeDeferActive then
    groupRuntimeDeferActive = true
    groupRuntimeDeferFrame:SetScript("OnUpdate", GroupRuntimeDeferOnUpdate)
  end
  return true
end

RefreshRosterStateBindings = function()
  -- Role-only roster changes must update per-frame status/name bindings, but
  -- they do not need a secure-header scan or a compiled-spec cache drop.
  GF._forceScanHeaders = nil
  RefreshRosterSignature()
  if GF.RefreshGroupNames then GF.RefreshGroupNames() end
  if GF.RefreshClickCastFrames then GF.RefreshClickCastFrames() end
end

local function RunScheduledRosterRebuild()
  rosterRebuildQueued = false
  local layoutChanged = GF._forceRecreateHeaders == true or RosterLayoutChanged()
  local bindingChanged = RosterStructureChanged()
  local stateChanged = RosterSignatureChanged()
  if not layoutChanged and not bindingChanged then
    if stateChanged then
      RefreshRosterStateBindings()
      GF.RefreshVisuals(nil, GF.DIRTY_VISUAL)
      return
    end
    if GF.RefreshGroupNames then GF.RefreshGroupNames() end
    if GF.RefreshClickCastFrames then GF.RefreshClickCastFrames() end
    return
  end
  if layoutChanged then
    GF._forceScanHeaders = true
    GF.RefreshHeaderLayout("rosterLayout")
    return
  end
  GF.RefreshUnitBindings()
end

local function ScheduleRosterRebuild()
  if rosterRebuildQueued then
    return
  end
  rosterRebuildQueued = true
  if not ScheduleGroupRuntimeNextFrame("MSUF_GF_ROSTER_REBUILD", RunScheduledRosterRebuild) then
    RunScheduledRosterRebuild()
  end
end

local function RunScheduledZoneRefresh()
  zoneRefreshQueued = false
  if InCombat() then
    GF.DeferGroupRuntime("zone")
    return
  end
  DropSpecs()
  -- Zone/difficulty changes may rebuild secure headers, but do not require a
  -- full visual/auras config sweep after the structural pass.
  RefreshStructuralMask(GF.DIRTY_GEOMETRY)
end

local function ScheduleZoneRefresh()
  if zoneRefreshQueued then
    return
  end
  zoneRefreshQueued = true
  if not ScheduleGroupRuntimeNextFrame("MSUF_GF_ZONE_REFRESH", RunScheduledZoneRefresh) then
    RunScheduledZoneRefresh()
  end
end

local function HideOrRetireHeader(key)
  local header = GF.headers and GF.headers[key]
  if not header then return end
  if GF.RetireHeader then
    GF.RetireHeader(key)
  else
    header:Hide()
  end
end

local function ClearGroupRuntimeQueues()
  rosterRebuildQueued = false
  zoneRefreshQueued = false
  rosterSettleToken = rosterSettleToken + 1
  if groupRuntimeDeferFrame then
    groupRuntimeDeferFrame:SetScript("OnUpdate", nil)
  end
  groupRuntimeDeferActive = nil
  for i = 1, groupRuntimeDeferCount do
    local key = groupRuntimeDeferKeys[i]
    groupRuntimeDeferKeys[i] = nil
    if key ~= nil then
      groupRuntimeDeferQueue[key] = nil
    end
  end
  groupRuntimeDeferCount = 0
  if ResetRefreshSlice then
    ResetRefreshSlice()
  end
end

local function RetireDisabledGroupRuntime(reason)
  HideOrRetireHeader("party")
  HideOrRetireHeader("raid")
  ClearGroupRuntimeQueues()
  DropSpecs()
  GF._forceScanHeaders = nil
  GF._forceRecreateHeaders = nil
  RefreshRuntimeEventRegistration()
  if GF.ApplyBlizzardGroupFrameOwnership then
    GF.ApplyBlizzardGroupFrameOwnership(reason or "disabled")
  end
end

local function PreviewSuppressesHeader(key)
  if _G.MSUF_UnitEditModeActive == true then
    return false
  end
  local active = GF._previewActive
  if not active then return false end
  if key == "party" then
    return active.party == true
  end
  if key == "raid" then
    return active.raid == true or active.mythicraid == true
  end
  return false
end

--- Show/retire headers based on current group state and preview ownership.
--- This is separate from RebuildAll so menu preview toggles can hide headers
--- without forcing a full spec drop.
function GF.UpdateGroupVisibility()
  if InCombat() then
    GF.DeferGroupRuntime("visibility")
    return false
  end
  if not DBReady() then
    ScheduleDBReadyRetry(GF.RebuildAll)
    return false
  end
  if GF.EnsureDB then GF.EnsureDB() end
  if not AnyGroupFrameEnabled() then
    RetireDisabledGroupRuntime("visibility-disabled")
    return true
  end
  if not CurrentGroupRuntimeActive() then
    RetireDisabledGroupRuntime("visibility-inactive")
    return true
  end

  local wantParty = ShouldShowParty() and not PreviewSuppressesHeader("party")
  local raidKind = LiveRaidKind()
  local raidConf = GF.GetConf and GF.GetConf(raidKind) or {}
  local wantRaid = (IsInRaid and IsInRaid()) and raidConf.enabled == true and not PreviewSuppressesHeader("raid")

  local party = GF.headers and GF.headers.party
  local raid = GF.headers and GF.headers.raid
  if not wantParty and party then
    HideOrRetireHeader("party")
    party = nil
  end
  if not wantRaid and raid then
    HideOrRetireHeader("raid")
    raid = nil
  end

  if wantParty then
    party = party or (GF.SetupHeader and GF.SetupHeader("party", "party"))
    if party then party:Show() end
  end
  ApplyHeaderSceneAlpha("party")

  if wantRaid then
    if (not raid or raid._msufGFKind ~= raidKind) and GF.SetupHeader then
      raid = GF.SetupHeader("raid", raidKind) or raid
    end
    if raid then raid:Show() end
  end
  ApplyHeaderSceneAlpha("raid")
  if GF.ApplyBlizzardGroupFrameOwnership then
    GF.ApplyBlizzardGroupFrameOwnership("visibility")
  end
  RefreshRuntimeEventRegistration()
  return true
end

--- Header layout refresh: update anchors/secure-header attributes and schedule
--- child scans, but do not drop compiled specs or force a full visual sweep.
function GF.RefreshHeaderLayout(reason)
  local profToken = GF.ProfBegin and GF.ProfBegin("layout")
  if InCombat() then
    GF.DeferGroupRuntime("layout")
    if GF.ProfEnd then GF.ProfEnd("layout", profToken) end
    return false
  end
  if not DBReady() then
    ScheduleDBReadyRetry(GF.RefreshHeaderLayout)
    if GF.ProfEnd then GF.ProfEnd("layout", profToken) end
    return false
  end
  if GF.EnsureDB then GF.EnsureDB() end
  if not AnyGroupFrameEnabled() then
    RetireDisabledGroupRuntime(reason or "layout-disabled")
    if GF.ProfEnd then GF.ProfEnd("layout", profToken) end
    return true
  end
  if not CurrentGroupRuntimeActive() then
    RetireDisabledGroupRuntime(reason or "layout-inactive")
    if GF.ProfEnd then GF.ProfEnd("layout", profToken) end
    return true
  end

  local wantParty = ShouldShowParty() and not PreviewSuppressesHeader("party")
  local raidKind = LiveRaidKind()
  local raidConf = GF.GetConf and GF.GetConf(raidKind) or {}
  local wantRaid = (IsInRaid and IsInRaid()) and raidConf.enabled == true and not PreviewSuppressesHeader("raid")

  if not wantParty and GF.headers and GF.headers.party then
    HideOrRetireHeader("party")
  end
  if not wantRaid and GF.headers and GF.headers.raid then
    HideOrRetireHeader("raid")
  end

  if wantParty and GF.SetupHeader then
    local party = GF.SetupHeader("party", "party")
    if party then party:Show() end
  end
  if wantRaid and GF.SetupHeader then
    local raid = GF.SetupHeader("raid", raidKind)
    if raid then raid:Show() end
  end

  ApplyHeaderSceneAlpha("party")
  ApplyHeaderSceneAlpha("raid")
  if GF.ApplyBlizzardGroupFrameOwnership then
    GF.ApplyBlizzardGroupFrameOwnership(reason or "layout")
  end
  GF._forceScanHeaders = nil
  GF._forceRecreateHeaders = nil
  RefreshRosterSignature()
  RefreshRuntimeEventRegistration()
  if GF.ProfEnd then GF.ProfEnd("layout", profToken) end
  return true
end

--- Unit-binding refresh: ask existing secure headers for their current children
--- and let Adapter's ApplyUnitChangeFast rebind changed units. This is the
--- common roster path and must not become a global RebuildAll.
function GF.RefreshUnitBindings(kind)
  local profToken = GF.ProfBegin and GF.ProfBegin("unitBinding")
  if InCombat() then
    GF.DeferGroupRuntime("roster", kind, GF.DIRTY_UNIT_BINDING)
    if GF.ProfEnd then GF.ProfEnd("unitBinding", profToken) end
    return false
  end
  if not AnyGroupFrameEnabled() then
    RetireDisabledGroupRuntime("unit-binding-disabled")
    if GF.ProfEnd then GF.ProfEnd("unitBinding", profToken) end
    return true
  end
  if not CurrentGroupRuntimeActive() then
    RetireDisabledGroupRuntime("unit-binding-inactive")
    if GF.ProfEnd then GF.ProfEnd("unitBinding", profToken) end
    return true
  end
  if GF._forceRecreateHeaders == true or RosterLayoutChanged() then
    local result = GF.RefreshHeaderLayout("unitBinding")
    if GF.ProfEnd then GF.ProfEnd("unitBinding", profToken) end
    return result
  end
  local didScan = false
  if GF.ScheduleScan and GF.headers then
    if (not kind or kind == "party") and GF.headers.party then
      GF.ScheduleScan("party", "party")
      didScan = true
    end
    local raidKind = LiveRaidKind()
    if (not kind or kind == "raid" or kind == "mythicraid" or kind == raidKind) and GF.headers.raid then
      GF.ScheduleScan("raid", raidKind)
      didScan = true
    end
  end
  GF._forceScanHeaders = nil
  RefreshRosterStateBindings()
  if GF.ProfEnd then GF.ProfEnd("unitBinding", profToken) end
  return didScan
end

--- Full structural pass: rebuild secure headers, drop compiled specs when
--- needed, bump Auras3 config, and refresh Blizzard ownership.
function GF.RebuildAll(preInvalidated, auras3ConfigBumped)
  local profToken = GF.ProfBegin and GF.ProfBegin("rebuildAll")
  if InCombat() then
    GF.DeferGroupRuntime("rebuild")
    if GF.ProfEnd then GF.ProfEnd("rebuildAll", profToken) end
    return false
  end
  if not DBReady() then
    ScheduleDBReadyRetry(GF.RebuildAll)
    if GF.ProfEnd then GF.ProfEnd("rebuildAll", profToken) end
    return false
  end
  if GF.EnsureDB then GF.EnsureDB() end
  if not AnyGroupFrameEnabled() then
    RetireDisabledGroupRuntime("rebuild-disabled")
    if GF.ProfEnd then GF.ProfEnd("rebuildAll", profToken) end
    return true
  end
  if not CurrentGroupRuntimeActive() then
    RetireDisabledGroupRuntime("rebuild-inactive")
    if GF.ProfEnd then GF.ProfEnd("rebuildAll", profToken) end
    return true
  end
  if preInvalidated ~= true then
    InvalidateSpecs()
  end
  if auras3ConfigBumped ~= true then
    BumpAuras3ConfigForGroup(GF.DIRTY_ALL)
  end

  local wantParty = ShouldShowParty() and not PreviewSuppressesHeader("party")
  local raidKind = LiveRaidKind()
  local raidConf = GF.GetConf and GF.GetConf(raidKind) or {}
  local wantRaid = (IsInRaid and IsInRaid()) and raidConf.enabled == true and not PreviewSuppressesHeader("raid")

  if not wantParty and GF.headers and GF.headers.party then
    HideOrRetireHeader("party")
  end
  if not wantRaid and GF.headers and GF.headers.raid then
    HideOrRetireHeader("raid")
  end

  if wantParty and GF.SetupHeader then
    local party = GF.SetupHeader("party", "party")
    if party then party:Show() end
  end
  if wantRaid and GF.SetupHeader then
    local raid = GF.SetupHeader("raid", raidKind)
    if raid then raid:Show() end
  end
  ApplyHeaderSceneAlpha("party")
  ApplyHeaderSceneAlpha("raid")
  if GF.ApplyBlizzardGroupFrameOwnership then
    GF.ApplyBlizzardGroupFrameOwnership("rebuild")
  end
  GF._forceScanHeaders = nil
  GF._forceRecreateHeaders = nil
  RefreshRosterSignature()
  RefreshRuntimeEventRegistration()
  if GF.ProfEnd then GF.ProfEnd("rebuildAll", profToken) end
  return true
end

--- PERF: RefreshVisuals applies a compiled spec to every live group frame; in
--- a raid that was a single-frame 40-60ms stall (~3.5ms ApplySpec per frame).
--- Small groups still complete fully synchronously (identical behavior), larger
--- sets apply under a per-chunk time budget and continue next frame. Combat
--- starting mid-slice aborts the remainder into the standard DeferGroupRuntime
--- replay, so in-combat semantics are unchanged.
local REFRESH_SLICE_BUDGET = 0.008
local REFRESH_SLICE_SYNC_MAX = 6
local refreshSliceFrames = {}
local refreshSliceKinds = {}
local refreshSliceCount = 0
local refreshSliceIndex = 0
local refreshSliceKind, refreshSliceMask
local refreshSliceActive = false

ResetRefreshSlice = function()
  for i = refreshSliceIndex + 1, refreshSliceCount do
    refreshSliceFrames[i] = nil
    refreshSliceKinds[i] = nil
  end
  refreshSliceCount = 0
  refreshSliceIndex = 0
  refreshSliceKind, refreshSliceMask = nil, nil
  refreshSliceActive = false
end

local function CollectRefreshVisualsFrame(frame, _, frameKind)
  refreshSliceCount = refreshSliceCount + 1
  refreshSliceFrames[refreshSliceCount] = frame
  refreshSliceKinds[refreshSliceCount] = frameKind
end

local RefreshSliceNow = _G.GetTimePreciseSec or _G.GetTime or function() return 0 end

local RunRefreshVisualsSlice

local function ScheduleRefreshVisualsSlice()
  if not ScheduleGroupRuntimeNextFrame("MSUF_GF_REFRESH_VISUALS_SLICE", RunRefreshVisualsSlice) then
    RunRefreshVisualsSlice()
  end
end

RunRefreshVisualsSlice = function()
  if refreshSliceActive ~= true then
    return
  end
  if InCombat() then
    GF.DeferGroupRuntime("refresh", refreshSliceKind, refreshSliceMask)
    ResetRefreshSlice()
    return
  end
  local budgeted = refreshSliceCount > REFRESH_SLICE_SYNC_MAX
  local deadline = budgeted and (RefreshSliceNow() + REFRESH_SLICE_BUDGET) or nil
  local kind, mask = refreshSliceKind, refreshSliceMask
  local live = GF.frames
  local profToken = GF.ProfBegin and GF.ProfBegin("refreshVisuals")
  while refreshSliceIndex < refreshSliceCount do
    local i = refreshSliceIndex + 1
    refreshSliceIndex = i
    local frame = refreshSliceFrames[i]
    refreshSliceFrames[i] = nil
    local frameKind = refreshSliceKinds[i]
    refreshSliceKinds[i] = nil
    if frame and (not live or live[frame] == true) then
      RefreshVisualsFrame(frame, nil, frameKind, kind, mask)
    end
    if deadline and refreshSliceIndex < refreshSliceCount and RefreshSliceNow() >= deadline then
      if GF.ProfEnd then GF.ProfEnd("refreshVisuals", profToken) end
      ScheduleRefreshVisualsSlice()
      return
    end
  end
  if GF.ProfEnd then GF.ProfEnd("refreshVisuals", profToken) end
  ResetRefreshSlice()
end

--- Warm visual refresh. Dirty masks let option changes touch only affected
--- runtime elements instead of reapplying every group-frame element.
function GF.RefreshVisuals(kind, mask, preInvalidated, auras3ConfigBumped)
  if InCombat() then
    GF.DeferGroupRuntime("refresh", kind, mask)
    return false
  end
  if not AnyGroupFrameEnabled() then
    RetireDisabledGroupRuntime("refresh-disabled")
    return true
  end
  if not CurrentGroupRuntimeActive() then
    RetireDisabledGroupRuntime("refresh-inactive")
    return true
  end
  if preInvalidated ~= true then
    InvalidateSpecs(kind)
  end
  if auras3ConfigBumped ~= true then
    BumpAuras3ConfigForGroup(mask)
  end
  if GF.ApplyGroupBorder then
    GF.ApplyGroupBorder(kind)
  end
  if not GF.ForEachFrame then
    return true
  end
  if refreshSliceActive == true then
    -- Merge with the in-flight sliced refresh and restart. Reapplying frames
    -- that already finished is redundant but always correct.
    if refreshSliceKind ~= kind then
      kind = nil
    end
    mask = OrMask(refreshSliceMask, mask)
    ResetRefreshSlice()
  end
  refreshSliceKind, refreshSliceMask = kind, mask
  GF.ForEachFrame(CollectRefreshVisualsFrame, true)
  if refreshSliceCount <= 0 then
    ResetRefreshSlice()
    return true
  end
  refreshSliceActive = true
  RunRefreshVisualsSlice()
  return true
end

function GF.RefreshAll(preInvalidated)
  if InCombat() then
    GF.DeferGroupRuntime("layout", nil, GF.DIRTY_ALL)
    GF.DeferGroupRuntime("refresh", nil, GF.DIRTY_ALL)
    return false
  end
  if not AnyGroupFrameEnabled() then
    RetireDisabledGroupRuntime("refresh-all-disabled")
    return true
  end
  if not CurrentGroupRuntimeActive() then
    RetireDisabledGroupRuntime("refresh-all-inactive")
    return true
  end
  if preInvalidated ~= true then
    InvalidateSpecs()
  end
  BumpAuras3ConfigForGroup(GF.DIRTY_ALL)
  GF.RefreshHeaderLayout("refreshAll")
  GF.RefreshVisuals(nil, GF.DIRTY_ALL, true, true)
  return true
end

RefreshStructuralMask = function(mask)
  if InCombat() then
    GF.DeferGroupRuntime("layout")
    GF.DeferGroupRuntime("refresh", nil, mask)
    return false
  end
  if not AnyGroupFrameEnabled() then
    RetireDisabledGroupRuntime("structural-disabled")
    return true
  end
  if not CurrentGroupRuntimeActive() then
    RetireDisabledGroupRuntime("structural-inactive")
    return true
  end
  local dirty = mask or GF.DIRTY_ALL
  InvalidateSpecs()
  BumpAuras3ConfigForGroup(dirty)
  GF.RefreshHeaderLayout("structural")
  GF.RefreshVisuals(nil, dirty, true, true)
  return true
end

GF.Refresh = GF.RefreshAll
GF.RefreshGeometry = function() return RefreshStructuralMask(GF.DIRTY_GEOMETRY) end
GF.RefreshOverlays = function(kind) return GF.RefreshVisuals(kind, GF.DIRTY_AURAS) end
GF.RefreshColors = function(kind) return GF.RefreshVisuals(kind, GF.DIRTY_COLOR) end
GF.RefreshBorder = function(kind) return GF.RefreshVisuals(kind, GF.DIRTY_BORDER) end
GF.RefreshOutlineGeometry = GF.RefreshBorder
GF.RefreshFonts = function(kind) return GF.RefreshVisuals(kind, GF.DIRTY_FONT) end

function GF.MarkDirty(frame, mask)
  if mask and Has(mask, GF.DIRTY_UNIT_BINDING)
    and not Has(mask, GF.DIRTY_GEOMETRY)
    and not Has(mask, GF.DIRTY_LAYOUT)
    and not Has(mask, GF.DIRTY_CONFIG) then
    return GF.RefreshUnitBindings(frame and frame._msufGFKind)
  end
  InvalidateSpecs(frame and frame._msufGFKind)
  if frame and frame._msufGFKind then
    return ApplyFrameDirty(frame, frame._msufGFKind, mask, "MSUF_GF_MARK_DIRTY")
  end
  return GF.RefreshVisuals(nil, mask, true)
end

function GF.MarkAllDirty(mask)
  if mask and Has(mask, GF.DIRTY_UNIT_BINDING)
    and not Has(mask, GF.DIRTY_GEOMETRY)
    and not Has(mask, GF.DIRTY_LAYOUT)
    and not Has(mask, GF.DIRTY_CONFIG) then
    return GF.RefreshUnitBindings()
  end
  if not mask or mask == GF.DIRTY_ALL
    or Has(mask, GF.DIRTY_GEOMETRY)
    or Has(mask, GF.DIRTY_LAYOUT)
    or Has(mask, GF.DIRTY_CONFIG) then
    return RefreshStructuralMask(mask)
  end
  InvalidateSpecs()
  return GF.RefreshVisuals(nil, mask, true)
end

function GF.BuildFrameCache(frame)
  return frame and frame.MSUFSpec
end

function GF.EM2_SetActivePreviewKind(kind)
  GF._activePreviewKind = kind
  return true
end

function GF.EM2_NudgePreview(key, dx, dy)
  if InCombat() then return true end
  local kind = key
  if key == "gf_party" then kind = "party"
  elseif key == "gf_raid" then kind = "raid"
  elseif key == "gf_mythicraid" then kind = "mythicraid" end
  if kind ~= "party" and kind ~= "raid" and kind ~= "mythicraid" then return false end
  local conf = GF.GetConf and GF.GetConf(kind)
  if not conf then return false end
  conf.offsetX = floor(((tonumber(conf.offsetX) or 0) + (tonumber(dx) or 0)) + 0.5)
  conf.offsetY = floor(((tonumber(conf.offsetY) or 0) + (tonumber(dy) or 0)) + 0.5)
  GF.RefreshGeometry()
  return true
end

--- Collapse multiple deferred requests into one post-combat action set. Roster
--- changes are split into layout, unit-binding, and state work so regen does
--- not turn every roster burst into a full structural rebuild.
local function TakePendingGroupRuntime(rosterLayoutChanged, rosterBindingChanged, rosterStateChanged)
  local pending = GF._pendingGroupRuntime
  local rebuild = GF._pendingGroupRebuild == true
  local rebuildReason = GF._pendingGroupRebuildReason
  local dropSpecs = GF._pendingGroupDropSpecs == true
  local layout = GF._pendingGroupLayout == true
  local unitBinding = GF._pendingGroupUnitBinding == true
  local visibility = GF._pendingGroupVisibility == true
  local refresh = GF._pendingGroupRefresh == true
  local refreshKind = GF._pendingGroupRefreshKind
  local refreshMask = GF._pendingGroupRefreshMask
  local stateOnly = false

  GF._pendingGroupRuntime = nil
  GF._pendingGroupRebuild = nil
  GF._pendingGroupRebuildReason = nil
  GF._pendingGroupDropSpecs = nil
  GF._pendingGroupLayout = nil
  GF._pendingGroupUnitBinding = nil
  GF._pendingGroupVisibility = nil
  GF._pendingGroupRefresh = nil
  GF._pendingGroupRefreshKind = nil
  GF._pendingGroupRefreshMask = nil
  GF._pendingGroupRefreshMaskSet = nil

  if pending and not (rebuild or dropSpecs or layout or unitBinding or visibility or refresh) then
    if pending == "roster" then
      unitBinding = true
    elseif pending == "zone" then
      layout = true
      dropSpecs = true
    elseif pending == "layout" or pending == "geometry" or pending == "setup" then
      layout = true
    elseif pending == "rebuild" then
      rebuild = true
    elseif pending == "visibility" then
      visibility = true
    else
      refresh = true
    end
  end

  if rosterLayoutChanged then
    layout = true
    unitBinding = true
    stateOnly = false
  elseif rosterBindingChanged then
    unitBinding = true
  elseif rebuildReason == "roster" and GF._forceRecreateHeaders ~= true then
    rebuild = false
    dropSpecs = false
    unitBinding = false
    stateOnly = rosterStateChanged == true
  elseif rosterStateChanged then
    stateOnly = true
  end

  return pending or rosterLayoutChanged or rosterBindingChanged or stateOnly,
    rebuild, dropSpecs, layout, unitBinding, visibility, refresh, refreshKind, refreshMask, stateOnly
end

local function FlushPendingGroupRuntime(rosterLayoutChanged, rosterBindingChanged, rosterStateChanged)
  local hasPending, rebuild, dropSpecs, layout, unitBinding, visibility, refresh, refreshKind, refreshMask, stateOnly =
    TakePendingGroupRuntime(rosterLayoutChanged, rosterBindingChanged, rosterStateChanged)
  if not hasPending then
    return false
  end

  if dropSpecs then
    DropSpecs()
  end
  if rebuild then
    GF.RebuildAll(dropSpecs == true)
  end
  if layout and not rebuild then
    GF.RefreshHeaderLayout("regenLayout")
  end
  if visibility and not (rebuild or layout) then
    GF.UpdateGroupVisibility()
  end
  if unitBinding and not rebuild then
    GF.RefreshUnitBindings()
  end
  if stateOnly and not rebuild then
    RefreshRosterStateBindings()
    refreshKind = nil
    if not refresh then
      refresh = true
      refreshMask = GF.DIRTY_VISUAL
    elseif refreshMask ~= nil then
      refreshMask = OrMask(refreshMask, GF.DIRTY_VISUAL)
    end
  end
  if refresh then
    GF.RefreshVisuals(refreshKind, refreshMask, dropSpecs == true)
  end
  return true
end

local function HasPendingGroupRuntime()
  return GF._pendingGroupRuntime ~= nil
    or GF._pendingGroupRebuild == true
    or GF._pendingGroupDropSpecs == true
    or GF._pendingGroupLayout == true
    or GF._pendingGroupUnitBinding == true
    or GF._pendingGroupVisibility == true
    or GF._pendingGroupRefresh == true
end

--- Central event router for group runtime. Keep event-specific decisions here so
--- Headers/Adapter/Visuals stay callable from explicit refresh paths too.
local function OnEvent(self, event, ...)
  if event == "PLAYER_REGEN_ENABLED" then
    ExportPublic("MSUF_InCombat", false)
    local active = RefreshRuntimeEventRegistration()
    if not active then
      if HasPendingGroupRuntime() then
        FlushPendingGroupRuntime(false, false, false)
        RefreshRuntimeEventRegistration()
      end
      return
    end
    if not CurrentGroupRuntimeActive() then
      if HasPendingGroupRuntime() then
        FlushPendingGroupRuntime(false, false, false)
      else
        RetireDisabledGroupRuntime("regen-inactive")
      end
      RefreshRuntimeEventRegistration()
      return
    end
    local rosterLayoutChanged = GF._forceRecreateHeaders == true or RosterLayoutChanged()
    local rosterBindingChanged = RosterStructureChanged()
    local rosterStateChanged = RosterSignatureChanged()
    if rosterStateChanged then
      MarkRosterMode()
      rosterLayoutChanged = GF._forceRecreateHeaders == true or rosterLayoutChanged or RosterLayoutChanged()
      if rosterLayoutChanged or rosterBindingChanged then
        if GF.InvalidateGroupSizeCache then GF.InvalidateGroupSizeCache() end
        GF._forceScanHeaders = true
      end
    end
    if not FlushPendingGroupRuntime(rosterLayoutChanged, rosterBindingChanged, rosterStateChanged) then
      GF.RefreshGroupNames()
      if GF.RefreshClickCastFrames then
        GF.RefreshClickCastFrames()
      end
    end
  elseif event == "PLAYER_REGEN_DISABLED" then
    ExportPublic("MSUF_InCombat", true)
    UnregisterNameEvents()
    UnregisterRosterEvents()
  elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
    ExportPublic("MSUF_InCombat", InCombat())
    local active
    if _G.MSUF_InCombat then
      UnregisterNameEvents()
      UnregisterRosterEvents()
    else
      active = RefreshRuntimeEventRegistration()
    end
    lastDifficultyToken = CurrentDifficultyToken()
    if not active then
      RetireDisabledGroupRuntime(event == "PLAYER_LOGIN" and "login-disabled" or "entering-world-disabled")
      return
    end
    if not CurrentGroupRuntimeActive() then
      RetireDisabledGroupRuntime(event == "PLAYER_LOGIN" and "login-inactive" or "entering-world-inactive")
      return
    end
    MarkRosterMode()
    if event == "PLAYER_ENTERING_WORLD" then
      GF._forceRecreateHeaders = true
    end
    DropSpecs()
    GF.RebuildAll(true)
  elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" or event == "ROLE_CHANGED_INFORM" then
    if not AnyGroupFrameEnabled() then
      RefreshRuntimeEventRegistration()
      return
    end
    if not CurrentGroupRuntimeActive() then
      RetireDisabledGroupRuntime("roster-inactive")
      return
    end
    if InCombat() then
      if GF.InvalidateGroupSizeCache then GF.InvalidateGroupSizeCache() end
      GF._forceScanHeaders = true
      GF.DeferGroupRuntime("roster")
      return
    end
    local mode = MarkRosterMode()
    if GF.InvalidateGroupSizeCache then GF.InvalidateGroupSizeCache() end
    GF._forceScanHeaders = true
    ScheduleRosterRebuild()
    if event == "GROUP_ROSTER_UPDATE" and mode == "raid" then
      ScheduleRosterSettle()
    end
  elseif event == "PLAYER_DIFFICULTY_CHANGED" then
    if not AnyGroupFrameEnabled() or not CurrentGroupRuntimeActive() then return end
    local token = CurrentDifficultyToken()
    if token ~= lastDifficultyToken then
      lastDifficultyToken = token
      GF._forceRecreateHeaders = true
      ScheduleZoneRefresh()
    end
  elseif event == "ZONE_CHANGED_NEW_AREA" then
    if not AnyGroupFrameEnabled() or not CurrentGroupRuntimeActive() then return end
    lastDifficultyToken = CurrentDifficultyToken()
    GF._forceRecreateHeaders = true
    ApplySceneAlphas()
    ScheduleZoneRefresh()
  elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
    if not AnyGroupFrameEnabled() or not CurrentGroupRuntimeActive() then return end
    ApplySceneAlphas()
  elseif event == "BARBER_SHOP_OPEN" then
    if not AnyGroupFrameEnabled() or not CurrentGroupRuntimeActive() then return end
    GF._clientSceneActive = true
    ApplySceneAlphas()
  elseif event == "BARBER_SHOP_CLOSE" then
    if not AnyGroupFrameEnabled() or not CurrentGroupRuntimeActive() then return end
    GF._clientSceneActive = nil
    ApplySceneAlphas()
    GF.UpdateGroupVisibility()
  elseif event == "UNIT_NAME_UPDATE" then
    if not AnyGroupFrameEnabled() then
      RefreshRuntimeEventRegistration()
      return
    end
    if not CurrentGroupRuntimeActive() then
      RefreshRuntimeEventRegistration()
      return
    end
    GF.RefreshGroupNames(select(1, ...))
  end
end

eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", OnEvent)
for i = 1, #INIT_EVENTS do
  eventFrame:RegisterEvent(INIT_EVENTS[i])
end
RefreshRuntimeEventRegistration()

local GF_PUBLIC_ALIASES = {
  { "MSUF_GF_RebuildAll", "RebuildAll" },
  { "MSUF_GF_RefreshAll", "RefreshAll" },
  { "MSUF_GF_Refresh", "RefreshAll" },
  { "MSUF_GF_RefreshVisuals", "RefreshVisuals" },
  { "MSUF_GF_RefreshHeaderLayout", "RefreshHeaderLayout" },
  { "MSUF_GF_RefreshUnitBindings", "RefreshUnitBindings" },
  { "MSUF_GF_RefreshGeometry", "RefreshGeometry" },
  { "MSUF_GF_UpdateGroupVisibility", "UpdateGroupVisibility" },
  { "MSUF_GF_RefreshOverlays", "RefreshOverlays" },
  { "MSUF_GF_RefreshBorder", "RefreshBorder" },
  { "MSUF_GF_RefreshOutlineGeometry", "RefreshOutlineGeometry" },
  { "MSUF_GF_RefreshColors", "RefreshColors" },
  { "MSUF_GF_RefreshFonts", "RefreshFonts" },
  { "MSUF_GF_EM2_SetActivePreviewKind", "EM2_SetActivePreviewKind" },
  { "MSUF_GF_EM2_NudgePreview", "EM2_NudgePreview" },
}

MSUF.GroupFrames = GF
for i = 1, #GF_PUBLIC_ALIASES do
  local alias, method = GF_PUBLIC_ALIASES[i][1], GF_PUBLIC_ALIASES[i][2]
  ExportPublic(alias, function(...)
    return GF[method](...)
  end)
end
ExportPublic("MSUF_GF_ForceAuraTextColorRefresh", function() return GF.RefreshVisuals(nil, GF.DIRTY_AURAS) end)
