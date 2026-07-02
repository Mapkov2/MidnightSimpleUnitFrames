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
local lastDifficultyToken
local rosterSignatureParts = {}
local ROSTER_EVENTS = { "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "ROLE_CHANGED_INFORM" }
local INIT_EVENTS = {
  "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_DIFFICULTY_CHANGED",
  "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
  "BARBER_SHOP_OPEN", "BARBER_SHOP_CLOSE",
}

local function InCombat()
  return InCombatLockdown and InCombatLockdown()
end

local band = bit and bit.band or bit32 and bit32.band
local bor = bit and bit.bor or bit32 and bit32.bor
local DIRTY_FLAGS = {
  GF.DIRTY_GEOMETRY, GF.DIRTY_VISUAL, GF.DIRTY_FONT, GF.DIRTY_COLOR,
  GF.DIRTY_BORDER, GF.DIRTY_LAYOUT, GF.DIRTY_AURAS,
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
  if not mask or mask == GF.DIRTY_ALL or Has(mask, GF.DIRTY_GEOMETRY) or Has(mask, GF.DIRTY_LAYOUT) then
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
  local applyMask = DirtyApplyMask(mask)
  if not applyMask then
    return GF.ApplyButton and GF.ApplyButton(frame, kind, reason or "MSUF_GF_DIRTY_FULL")
  end
  if not (UF and UF.ApplySpec and GF.CompileSpec) then
    return GF.ApplyButton and GF.ApplyButton(frame, kind, reason or "MSUF_GF_DIRTY_FALLBACK")
  end
  local spec = GF.CompileSpec(kind, frame, frame and frame.unit)
  return UF.ApplySpec(frame, spec, DirtyRuntimeReason(mask, reason), applyMask)
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
  if reason == "roster" or reason == "zone" then
    GF._pendingGroupRebuild = true
    GF._pendingGroupDropSpecs = true
    RememberPendingRebuildReason(reason)
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

local function RegisterNameEvents()
  if eventFrame and not nameEventsRegistered and not InCombat() then
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
  if eventFrame and not rosterEventsRegistered and not InCombat() then
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
  n = n + 1
  parts[n] = ShouldShowParty() and "party:on" or "party:off"
  n = n + 1
  parts[n] = wantRaid and "raid:on" or "raid:off"
  if mode == "raid" then
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
  elseif mode == "party" then
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

local function RefreshRosterSignature()
  -- Track two signatures: structural changes need secure header work, while
  -- role-only changes are handled by per-frame runtime/status refreshes.
  lastRosterSignature = CurrentRosterSignature(true)
  lastRosterStructureSignature = CurrentRosterSignature(false)
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

local function ScanRaidHeaderChildren()
  local header = GF.headers and GF.headers.raid
  if not (header and GF.ScheduleScan) then
    return false
  end
  GF.ScheduleScan("raid", LiveRaidKind())
  return true
end

local function ScheduleRosterSettle()
  if RosterMode() ~= "raid" then
    return
  end
  rosterSettleToken = rosterSettleToken + 1
  local token = rosterSettleToken
  local function Run()
    if token ~= rosterSettleToken or RosterMode() ~= "raid" then
      return
    end
    local structureChanged = GF._forceRecreateHeaders == true or RosterStructureChanged()
    local stateChanged = RosterSignatureChanged()
    if structureChanged or not ScanRaidHeaderChildren() then
      GF._forceScanHeaders = true
      GF.RebuildAll()
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
  local structureChanged = GF._forceRecreateHeaders == true or RosterStructureChanged()
  local stateChanged = RosterSignatureChanged()
  if not structureChanged then
    if stateChanged then
      RefreshRosterStateBindings()
      GF.RefreshVisuals(nil, GF.DIRTY_VISUAL)
      return
    end
    if GF.RefreshGroupNames then GF.RefreshGroupNames() end
    if GF.RefreshClickCastFrames then GF.RefreshClickCastFrames() end
    return
  end
  DropSpecs()
  GF.RebuildAll(true)
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
  return true
end

--- Full structural pass: rebuild secure headers, drop compiled specs when
--- needed, bump Auras3 config, and refresh Blizzard ownership.
function GF.RebuildAll(preInvalidated, auras3ConfigBumped)
  if InCombat() then
    GF.DeferGroupRuntime("rebuild")
    return false
  end
  if not DBReady() then
    ScheduleDBReadyRetry(GF.RebuildAll)
    return false
  end
  if preInvalidated ~= true then
    InvalidateSpecs()
  end
  if auras3ConfigBumped ~= true then
    BumpAuras3ConfigForGroup(GF.DIRTY_ALL)
  end
  if GF.EnsureDB then GF.EnsureDB() end

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

local function ResetRefreshSlice()
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
      ScheduleRefreshVisualsSlice()
      return
    end
  end
  ResetRefreshSlice()
end

--- Warm visual refresh. Dirty masks let option changes touch only affected
--- runtime elements instead of reapplying every group-frame element.
function GF.RefreshVisuals(kind, mask, preInvalidated, auras3ConfigBumped)
  if InCombat() then
    GF.DeferGroupRuntime("refresh", kind, mask)
    return false
  end
  if preInvalidated ~= true then
    InvalidateSpecs(kind)
  end
  if auras3ConfigBumped ~= true then
    BumpAuras3ConfigForGroup(mask)
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
    GF.DeferGroupRuntime("refresh", nil, GF.DIRTY_ALL)
    return false
  end
  if preInvalidated ~= true then
    InvalidateSpecs()
  end
  BumpAuras3ConfigForGroup(GF.DIRTY_ALL)
  GF.RebuildAll(true, true)
  GF.RefreshVisuals(nil, GF.DIRTY_ALL, true, true)
  return true
end

RefreshStructuralMask = function(mask)
  if InCombat() then
    GF.DeferGroupRuntime("rebuild")
    GF.DeferGroupRuntime("refresh", nil, mask)
    return false
  end
  local dirty = mask or GF.DIRTY_ALL
  BumpAuras3ConfigForGroup(dirty)
  GF.RebuildAll(true, true)
  GF.RefreshVisuals(nil, dirty, true, true)
  return true
end

GF.Refresh = GF.RefreshAll
GF.RefreshGeometry = GF.RebuildAll
GF.RefreshOverlays = function(kind) return GF.RefreshVisuals(kind, GF.DIRTY_AURAS) end
GF.RefreshColors = function(kind) return GF.RefreshVisuals(kind, GF.DIRTY_COLOR) end
GF.RefreshBorder = function(kind) return GF.RefreshVisuals(kind, GF.DIRTY_BORDER) end
GF.RefreshOutlineGeometry = GF.RefreshBorder
GF.RefreshFonts = function(kind) return GF.RefreshVisuals(kind, GF.DIRTY_FONT) end

function GF.MarkDirty(frame, mask)
  InvalidateSpecs(frame and frame._msufGFKind)
  if frame and frame._msufGFKind then
    return ApplyFrameDirty(frame, frame._msufGFKind, mask, "MSUF_GF_MARK_DIRTY")
  end
  return GF.RefreshVisuals(nil, mask, true)
end

function GF.MarkAllDirty(mask)
  InvalidateSpecs()
  if not mask or mask == GF.DIRTY_ALL or Has(mask, GF.DIRTY_GEOMETRY) or Has(mask, GF.DIRTY_LAYOUT) then
    return RefreshStructuralMask(mask)
  end
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
  GF.RebuildAll()
  return true
end

--- Collapse multiple deferred requests into one post-combat action set. Roster
--- changes win over simple visual refreshes because unit identity can change.
local function TakePendingGroupRuntime(rosterChanged, rosterStateChanged)
  local pending = GF._pendingGroupRuntime
  local rebuild = GF._pendingGroupRebuild == true
  local rebuildReason = GF._pendingGroupRebuildReason
  local dropSpecs = GF._pendingGroupDropSpecs == true
  local visibility = GF._pendingGroupVisibility == true
  local refresh = GF._pendingGroupRefresh == true
  local refreshKind = GF._pendingGroupRefreshKind
  local refreshMask = GF._pendingGroupRefreshMask
  local stateOnly = false

  GF._pendingGroupRuntime = nil
  GF._pendingGroupRebuild = nil
  GF._pendingGroupRebuildReason = nil
  GF._pendingGroupDropSpecs = nil
  GF._pendingGroupVisibility = nil
  GF._pendingGroupRefresh = nil
  GF._pendingGroupRefreshKind = nil
  GF._pendingGroupRefreshMask = nil
  GF._pendingGroupRefreshMaskSet = nil

  if pending and not (rebuild or dropSpecs or visibility or refresh) then
    if pending == "roster" then
      stateOnly = true
    elseif pending == "zone" then
      rebuild = true
      dropSpecs = true
    elseif pending == "rebuild" then
      rebuild = true
    elseif pending == "visibility" then
      visibility = true
    else
      refresh = true
    end
  end

  if rosterChanged then
    rebuild = true
    dropSpecs = true
    stateOnly = false
  elseif rebuildReason == "roster" and GF._forceRecreateHeaders ~= true then
    rebuild = false
    dropSpecs = false
    stateOnly = true
  elseif rosterStateChanged then
    stateOnly = true
  end

  return pending or rosterChanged or stateOnly, rebuild, dropSpecs, visibility, refresh, refreshKind, refreshMask, stateOnly
end

local function FlushPendingGroupRuntime(rosterChanged, rosterStateChanged)
  local hasPending, rebuild, dropSpecs, visibility, refresh, refreshKind, refreshMask, stateOnly = TakePendingGroupRuntime(rosterChanged, rosterStateChanged)
  if not hasPending then
    return false
  end

  if dropSpecs then
    DropSpecs()
  end
  if rebuild then
    GF.RebuildAll(dropSpecs == true)
  end
  if visibility and not rebuild then
    GF.UpdateGroupVisibility()
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

--- Central event router for group runtime. Keep event-specific decisions here so
--- Headers/Adapter/Visuals stay callable from explicit refresh paths too.
local function OnEvent(self, event, ...)
  if event == "PLAYER_REGEN_ENABLED" then
    ExportPublic("MSUF_InCombat", false)
    RegisterNameEvents()
    RegisterRosterEvents()
    local rosterStateChanged = RosterSignatureChanged()
    local rosterChanged = GF._forceRecreateHeaders == true or RosterStructureChanged()
    if rosterStateChanged then
      MarkRosterMode()
      if rosterChanged then
        if GF.InvalidateGroupSizeCache then GF.InvalidateGroupSizeCache() end
        GF._forceScanHeaders = true
      end
    end
    if not FlushPendingGroupRuntime(rosterChanged, rosterStateChanged) then
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
    if _G.MSUF_InCombat then
      UnregisterNameEvents()
      UnregisterRosterEvents()
    else
      RegisterNameEvents()
      RegisterRosterEvents()
    end
    MarkRosterMode()
    lastDifficultyToken = CurrentDifficultyToken()
    if event == "PLAYER_ENTERING_WORLD" then
      GF._forceRecreateHeaders = true
    end
    DropSpecs()
    GF.RebuildAll(true)
  elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" or event == "ROLE_CHANGED_INFORM" then
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
    local token = CurrentDifficultyToken()
    if token ~= lastDifficultyToken then
      lastDifficultyToken = token
      GF._forceRecreateHeaders = true
      ScheduleZoneRefresh()
    end
  elseif event == "ZONE_CHANGED_NEW_AREA" then
    lastDifficultyToken = CurrentDifficultyToken()
    GF._forceRecreateHeaders = true
    ApplySceneAlphas()
    ScheduleZoneRefresh()
  elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
    ApplySceneAlphas()
  elseif event == "BARBER_SHOP_OPEN" then
    GF._clientSceneActive = true
    ApplySceneAlphas()
  elseif event == "BARBER_SHOP_CLOSE" then
    GF._clientSceneActive = nil
    ApplySceneAlphas()
    GF.UpdateGroupVisibility()
  elseif event == "UNIT_NAME_UPDATE" then
    GF.RefreshGroupNames(select(1, ...))
  end
end

eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", OnEvent)
for i = 1, #INIT_EVENTS do
  eventFrame:RegisterEvent(INIT_EVENTS[i])
end
RegisterNameEvents()
RegisterRosterEvents()

local GF_PUBLIC_ALIASES = {
  { "MSUF_GF_RebuildAll", "RebuildAll" },
  { "MSUF_GF_RefreshAll", "RefreshAll" },
  { "MSUF_GF_Refresh", "RefreshAll" },
  { "MSUF_GF_RefreshVisuals", "RefreshVisuals" },
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
