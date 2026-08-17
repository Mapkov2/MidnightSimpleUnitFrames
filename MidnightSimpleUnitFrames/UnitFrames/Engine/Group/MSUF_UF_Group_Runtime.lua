local _, MSUF = ...

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
local floor = math.floor
local pairs = pairs
local tonumber = tonumber
local tostring = tostring
local type = type
local issecretvalue = _G.issecretvalue or function(_) return false end

local eventFrame
local runtimeObservers = {}
local dirtyApplyMaskCache = {}
local appliedLayoutScaleByKind = {}

local function InCombat()
  return InCombatLockdown and InCombatLockdown()
end

local function SyncCombatState(inCombat)
  if inCombat == nil then inCombat = InCombat() end
  inCombat = inCombat == true
  ExportPublic("MSUF_InCombat", inCombat)
  return inCombat
end

local IsUnitToken = UF and UF.IsUnitToken or function(unit)
  return issecretvalue(unit) ~= true and type(unit) == "string" and unit ~= ""
end

local function Conf(kind)
  return GF.GetConf and GF.GetConf(kind) or nil
end

-- Header layout is an out-of-combat cold path. Keep the last scale that was
-- actually committed to a live header separate from conf._resolvedFrameScale:
-- previews and geometry queries are allowed to update that config cache without
-- touching live children. A changed live scale must drop the compiled base spec
-- before SetupHeader scans its existing SecureGroupHeader children.
local function SetupLiveHeader(key, kind)
  local setup = GF.SetupHeader
  if type(setup) ~= "function" then return nil end

  if type(GF.EnsureDB) == "function" then GF.EnsureDB() end
  local resolve = GF.ResolveFrameScale
  local desiredScale = type(resolve) == "function" and tonumber(resolve(kind)) or nil
  if desiredScale ~= nil and appliedLayoutScaleByKind[kind] ~= desiredScale then
    if type(GF.InvalidateCompiledSpecs) == "function" then
      GF.InvalidateCompiledSpecs(kind)
    end
  end

  local header, scanned = setup(key, kind)
  if header and desiredScale ~= nil then
    appliedLayoutScaleByKind[kind] = desiredScale
  end
  return header, scanned
end

local function RefreshPartyStateFrame(frame, _, kind, reason)
  if kind ~= "party" then return false end
  local refresh = UF and UF.RefreshGroupFrameState
  return type(refresh) == "function" and refresh(frame, reason) == true or false
end

local function RefreshVisiblePartyState(reason)
  if type(GF.ForEachFrame) ~= "function" then return false end
  return GF.ForEachFrame(RefreshPartyStateFrame, false, reason)
end

local function RoleFilteredAggroMode(mode)
  mode = tostring(mode or "ALL"):upper()
  if mode == "TANK_ONLY" then mode = "TANK"
  elseif mode == "HEALER_ONLY" then mode = "HEALER" end
  return mode == "TANK" or mode == "HEALER" or mode == "NON_TANK"
end

local function RefreshRoleStateFrame(frame, _, _, reason)
  if not frame then return false end
  reason = reason or "PLAYER_ROLES_ASSIGNED"
  local did = false

  local update = frame._msufUpdateGroupStatusState
  if type(update) == "function" then
    update(frame, reason, frame.MSUFUnitKey)
    did = true
  end

  -- Role-filtered aggro visuals depend on UnitGroupRolesAssigned in addition
  -- to threat. A role change does not guarantee a follow-up threat event, so
  -- refresh just those enabled visual owners on this existing cold path.
  local active = frame._msufActiveElements
  local spec = frame.MSUFSpec
  local elements = UF and UF.elements
  if active and spec and elements then
    local borderCfg = spec.border
    local borders = active.Borders == true and elements.Borders or nil
    if borders and type(borders.Update) == "function"
      and borderCfg and borderCfg.aggro == true
      and RoleFilteredAggroMode(borderCfg.aggroMode) then
      borders.Update(frame, reason, frame.MSUFUnitKey)
      did = true
    end

    local cornerCfg = spec.cornerIndicators
    local corners = active.GroupCornerIndicators == true and elements.GroupCornerIndicators or nil
    if corners and type(corners.Update) == "function"
      and cornerCfg and cornerCfg.enabled == true and cornerCfg.needsThreat == true
      and RoleFilteredAggroMode(cornerCfg.aggroMode) then
      corners.Update(frame, reason, frame.MSUFUnitKey)
      did = true
    end
  end

  return did
end

-- SecureGroupHeader may rescan an unchanged child without reapplying its spec.
-- Role assignments are an OOC cold-path concern, so explicitly catch those
-- reused live frames up after header setup instead of adding role work to the
-- shared combat/lifecycle hot path.
local function RefreshVisibleRoleState(reason)
  if type(GF.ForEachFrame) ~= "function" then return false end
  return GF.ForEachFrame(RefreshRoleStateFrame, false, reason or "PLAYER_ROLES_ASSIGNED")
end

local function ConfEnabled(kind)
  local conf = Conf(kind)
  return conf and conf.enabled == true
end

local function LiveGroupKind()
  if type(GF.GetLiveGroupKind) == "function" then
    return GF.GetLiveGroupKind()
  end
  if IsInRaid and IsInRaid() then
    return type(GF.GetLiveRaidKind) == "function" and GF.GetLiveRaidKind() or "raid"
  end
  if IsInGroup and IsInGroup() then return "party" end
  return nil
end

local function AnyGroupFrameEnabled()
  if type(GF.AnyMSUFGroupFrameEnabled) == "function" then
    return GF.AnyMSUFGroupFrameEnabled() == true
  end
  return ConfEnabled("party") or ConfEnabled("raid") or ConfEnabled("mythicraid")
end
GF.AnyGroupRuntimeEnabled = AnyGroupFrameEnabled

local RUNTIME_EVENTS = {
  "PLAYER_LOGIN",
  "PLAYER_ENTERING_WORLD",
  "GROUP_ROSTER_UPDATE",
  "PLAYER_ROLES_ASSIGNED",
  "ROLE_CHANGED_INFORM",
  "PLAYER_DIFFICULTY_CHANGED",
  "ZONE_CHANGED_NEW_AREA",
  "PLAYER_REGEN_DISABLED",
  "PLAYER_REGEN_ENABLED",
}

local function SetRuntimeEventsEnabled(enabled, regenOnly)
  if not eventFrame then return end
  if eventFrame.UnregisterAllEvents then
    eventFrame:UnregisterAllEvents()
  elseif eventFrame.UnregisterEvent then
    for i = 1, #RUNTIME_EVENTS do eventFrame:UnregisterEvent(RUNTIME_EVENTS[i]) end
  end
  if regenOnly then
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    return
  end
  if not enabled then return end
  for i = 1, #RUNTIME_EVENTS do
    eventFrame:RegisterEvent(RUNTIME_EVENTS[i])
  end
  local priorityKind = type(GF.GetPriorityBaseKind) == "function" and GF.GetPriorityBaseKind() or nil
  if not priorityKind then priorityKind = LiveGroupKind() end
  if priorityKind and ConfEnabled(priorityKind)
    and type(GF.PriorityFramesConfigured) == "function" and GF.PriorityFramesConfigured() == true then
    eventFrame:RegisterEvent("UNIT_NAME_UPDATE")
  end
end

local function LiveRaidKind()
  local kind = GF.GetLiveRaidKind and GF.GetLiveRaidKind() or nil
  if kind == "mythicraid" then return "mythicraid" end
  return "raid"
end

local function WantParty()
  local conf = Conf("party")
  if not (conf and conf.enabled == true) then return false end
  local kind = LiveGroupKind()
  if kind == "party" then return true end
  -- "Show while solo" means solo only: a live raid scope must never surface
  -- the party header next to the raid frames.
  return kind == nil and conf.showSolo == true
end

local function WantRaid()
  local kind = LiveGroupKind()
  if kind ~= "raid" and kind ~= "mythicraid" then return false end
  return ConfEnabled(kind)
end

local function PreviewSuppressesHeader(key)
  if _G.MSUF_UnitEditModeActive == true then return false end
  local active = GF._previewActive
  if not active then return false end
  if key == "party" then return active.party == true end
  if key == "raid" then return active.raid == true or active.mythicraid == true end
  if key == "priority" then return active.priority == true end
  return false
end

local function LivePriorityKind()
  if type(GF.GetPriorityBaseKind) == "function" then return GF.GetPriorityBaseKind() end
  return LiveGroupKind()
end

local function WantPriorityBase(kind)
  if kind == "party" then
    return LiveGroupKind() == "party" and ConfEnabled("party")
  end
  if kind == "raid" or kind == "mythicraid" then
    return LiveGroupKind() == kind and WantRaid()
  end
  return false
end

local function RetireHeader(key)
  if GF.RetireHeader then return GF.RetireHeader(key) end
  local header = GF.headers and GF.headers[key]
  if header and header.Hide then header:Hide() end
  if GF.headers then GF.headers[key] = nil end
  return true
end

local function HeaderScope(kind)
  if kind == "party" then return "party" end
  if kind == "raid" or kind == "mythicraid" then return "raid" end
  if kind == "priority" or kind == "gf_priority" then return "priority" end
  return nil
end

local function SetupWantedPriority()
  GF._pendingPriorityRefresh = nil
  local priorityKind = LivePriorityKind()
  local wanted = WantPriorityBase(priorityKind)
    and not PreviewSuppressesHeader("priority")
    and type(GF.PriorityFramesConfigured) == "function"
    and GF.PriorityFramesConfigured() == true
  if not wanted then
    return RetireHeader("priority")
  end
  local resolve = GF.ResolvePrioritySelection
  local setup = GF.SetupPriorityHeader
  if type(resolve) ~= "function" or type(setup) ~= "function" then
    return RetireHeader("priority")
  end
  local nameList, count = resolve()
  if not nameList or not count or count < 1 then
    if type(GF.NotifyPriorityListeners) == "function" then GF.NotifyPriorityListeners("runtime-empty", 0) end
    return RetireHeader("priority")
  end
  local header = setup(priorityKind, nameList, count)
  if header and header.Show then header:Show() end
  if type(GF.NotifyPriorityListeners) == "function" then GF.NotifyPriorityListeners("runtime", count) end
  return header ~= nil
end

local function FinishOwnershipHandoff()
  -- Group borders live on persistent, unprotected anchors rather than on the
  -- secure headers retired above. Reconcile both anchors after every scope
  -- transition so the inactive Party/Raid border cannot survive the switch.
  if type(GF.ApplyGroupBorder) == "function" then GF.ApplyGroupBorder() end

  if GF.ApplyBlizzardGroupFrameOwnership then
    GF.ApplyBlizzardGroupFrameOwnership("lean-runtime")
  end
  return true
end

local function SetupWantedHeaders(kind)
  local scope = HeaderScope(kind)
  if not AnyGroupFrameEnabled() then
    if not scope or scope == "party" then RetireHeader("party") end
    if not scope or scope == "raid" then RetireHeader("raid") end
    RetireHeader("priority")
    return FinishOwnershipHandoff()
  end

  local wantParty = WantParty() and not PreviewSuppressesHeader("party")
  local wantRaid = WantRaid() and not PreviewSuppressesHeader("raid")
  local raidKind = LiveRaidKind()

  if scope ~= "raid" and scope ~= "priority" and wantParty then
    local header, scanHandled
    header, scanHandled = SetupLiveHeader("party", "party")
    if header and header.Show then header:Show() end
    if not scanHandled and GF.ScheduleScan then GF.ScheduleScan("party", "party") end
  elseif scope ~= "raid" and scope ~= "priority" then
    RetireHeader("party")
  end

  if scope ~= "party" and scope ~= "priority" and wantRaid then
    local header, scanHandled
    header, scanHandled = SetupLiveHeader("raid", raidKind)
    if header and header.Show then header:Show() end
    if not scanHandled and GF.ScheduleScan then GF.ScheduleScan("raid", raidKind) end
  elseif scope ~= "party" and scope ~= "priority" then
    RetireHeader("raid")
  end

  -- Priority inherits whichever base group kind is active, so both Party and
  -- Raid scoped layout changes must update the one switching secure header.
  SetupWantedPriority()

  return FinishOwnershipHandoff()
end

local function ApplyFrameDirty(frame, kind, mask, reason, applyMask)
  if not (frame and kind) then return false end
  if not IsUnitToken(frame.MSUFUnitKey) then return false end
  if not (UF and UF.ApplySpec and GF.CompileSpec) then
    return GF.ApplyButton and GF.ApplyButton(frame, kind, reason)
  end
  local spec = GF.CompileSpec(kind, frame, frame.MSUFUnitKey)
  if not spec then return false end
  applyMask = applyMask or (GF.ApplyMaskForDirtyMask and GF.ApplyMaskForDirtyMask(mask)) or Metadata.MASK_RUNTIME
  if GF.ApplyStructureSpec then
    return GF.ApplyStructureSpec(frame, spec, reason or "MSUF_GF_DIRTY", applyMask) == true
  end
  return UF.ApplySpec(frame, spec, reason or "MSUF_GF_DIRTY", applyMask) == true
end

local function ApplyRefreshFrame(frame, _, frameKind, kind, mask, applyMask)
  if kind and kind ~= frameKind then return false end
  return ApplyFrameDirty(frame, frameKind, mask, "MSUF_GF_REFRESH_VISUALS", applyMask)
end

local function MaskHas(mask, flag)
  mask = tonumber(mask) or 0
  flag = tonumber(flag) or 0
  if flag <= 0 then return false end
  return mask % (flag * 2) >= flag
end

local function AddDirty(mask, flag)
  if not flag then return mask end
  mask = tonumber(mask) or 0
  if MaskHas(mask, flag) then return mask end
  return mask + flag
end

local function MergeDirtyMask(current, incoming)
  if not current then return incoming end
  if not incoming then return current end
  if current == true or incoming == true then return true end
  if current == GF.DIRTY_ALL or incoming == GF.DIRTY_ALL then return GF.DIRTY_ALL end
  if current == GF.DIRTY_CONFIG or incoming == GF.DIRTY_CONFIG then return GF.DIRTY_CONFIG end
  if type(current) ~= "number" or type(incoming) ~= "number" then return incoming end
  local out = current
  out = AddDirty(out, MaskHas(incoming, GF.DIRTY_VISUAL) and GF.DIRTY_VISUAL or nil)
  out = AddDirty(out, MaskHas(incoming, GF.DIRTY_FONT) and GF.DIRTY_FONT or nil)
  out = AddDirty(out, MaskHas(incoming, GF.DIRTY_COLOR) and GF.DIRTY_COLOR or nil)
  out = AddDirty(out, MaskHas(incoming, GF.DIRTY_BORDER) and GF.DIRTY_BORDER or nil)
  out = AddDirty(out, MaskHas(incoming, GF.DIRTY_GEOMETRY) and GF.DIRTY_GEOMETRY or nil)
  out = AddDirty(out, MaskHas(incoming, GF.DIRTY_LAYOUT) and GF.DIRTY_LAYOUT or nil)
  out = AddDirty(out, MaskHas(incoming, GF.DIRTY_AURAS) and GF.DIRTY_AURAS or nil)
  out = AddDirty(out, MaskHas(incoming, GF.DIRTY_UNIT_BINDING) and GF.DIRTY_UNIT_BINDING or nil)
  out = AddDirty(out, MaskHas(incoming, GF.DIRTY_CONFIG) and GF.DIRTY_CONFIG or nil)
  return out
end

local function AddElementNames(out, source)
  if type(source) ~= "table" then return false end
  local did = false
  for name in pairs(source) do
    out[name] = true
    did = true
  end
  return did
end

function GF.ApplyMaskForDirtyMask(mask)
  if mask == nil then return Metadata.MASK_RUNTIME end
  local exact = Metadata.dirtyApplyMasks and Metadata.dirtyApplyMasks[mask]
  if exact then return exact end
  if mask == GF.DIRTY_ALL or mask == GF.DIRTY_CONFIG then return true end
  if type(mask) ~= "number" then return Metadata.MASK_RUNTIME end
  if MaskHas(mask, GF.DIRTY_CONFIG) then return true end

  local cached = dirtyApplyMaskCache[mask]
  if cached then return cached end

  local out = {}
  local did = false
  if MaskHas(mask, GF.DIRTY_VISUAL) then did = AddElementNames(out, Metadata.MASK_VISUAL) or did end
  if MaskHas(mask, GF.DIRTY_FONT) then did = AddElementNames(out, Metadata.MASK_FONT) or did end
  if MaskHas(mask, GF.DIRTY_COLOR) then did = AddElementNames(out, Metadata.MASK_COLOR) or did end
  if MaskHas(mask, GF.DIRTY_BORDER) then did = AddElementNames(out, Metadata.MASK_BORDER) or did end
  if MaskHas(mask, GF.DIRTY_AURAS) then did = AddElementNames(out, Metadata.MASK_AURAS) or did end
  if MaskHas(mask, GF.DIRTY_GEOMETRY) or MaskHas(mask, GF.DIRTY_LAYOUT) or MaskHas(mask, GF.DIRTY_UNIT_BINDING) then
    did = AddElementNames(out, Metadata.MASK_RUNTIME) or did
  end
  if not did then
    dirtyApplyMaskCache[mask] = Metadata.MASK_RUNTIME
    return Metadata.MASK_RUNTIME
  end
  -- UF.ApplySpec only reads element masks. Keep the lazily merged table private
  -- and reuse it as immutable metadata for every frame and later refresh.
  dirtyApplyMaskCache[mask] = out
  return out
end

function GF.RegisterRuntimeObserver(owner, callback)
  if type(owner) ~= "string" or owner == "" or type(callback) ~= "function" then return false end
  runtimeObservers[owner] = callback
  return true
end

function GF.UnregisterRuntimeObserver(owner)
  if runtimeObservers[owner] == nil then return false end
  runtimeObservers[owner] = nil
  return true
end

local function NotifyRuntimeObservers(operation, kind, mask, result)
  for _, callback in pairs(runtimeObservers) do
    callback(operation, kind, mask, result)
  end
  return result
end

--- Deferred reasons accumulate as a set. Keeping only the newest one dropped
--- whole work units: a "visibility" defer landing after a "roster" defer used to
--- lose the party/role state refresh that only the roster branch performs. The
--- dirty mask was already merged; the reason now is too.
local function AddPendingReason(reason)
  if type(reason) ~= "string" or reason == "" then return end
  local reasons = GF._pendingGroupRuntimeReasons
  if not reasons then
    reasons = {}
    GF._pendingGroupRuntimeReasons = reasons
  end
  reasons[reason] = true
end

function GF.DeferGroupRuntime(reason, kind, mask)
  GF._pendingGroupRuntime = true
  reason = reason or GF._pendingGroupRuntimeReason or "refresh"
  AddPendingReason(reason)
  local currentReason = GF._pendingGroupRuntimeReason
  if not currentReason or currentReason == "refresh" then
    GF._pendingGroupRuntimeReason = reason
  elseif reason ~= "refresh" then
    GF._pendingGroupRuntimeReason = reason
  end
  if kind ~= nil then
    local currentKind = GF._pendingGroupRuntimeKind
    if currentKind ~= nil and currentKind ~= kind then
      GF._pendingGroupRuntimeKind = nil
    else
      GF._pendingGroupRuntimeKind = kind
    end
  end
  GF._pendingGroupRuntimeMask = MergeDirtyMask(GF._pendingGroupRuntimeMask, mask)
  return false
end

function GF.UpdateGroupVisibility()
  if InCombat() then return GF.DeferGroupRuntime("visibility") end
  return SetupWantedHeaders()
end

function GF.RefreshHeaderLayout(kind)
  local inCombat = InCombat()
  if not inCombat and GF.EnsureDB then GF.EnsureDB() end
  local enabled = AnyGroupFrameEnabled()
  if inCombat then
    local result = GF.DeferGroupRuntime("layout", kind)
    SetRuntimeEventsEnabled(enabled, not enabled)
    return result
  end
  local result = SetupWantedHeaders(kind)
  SetRuntimeEventsEnabled(enabled)
  if type(GF.RefreshSpellIndicatorSeedEvents) == "function" then
    GF.RefreshSpellIndicatorSeedEvents()
  end
  return result
end

local startupVisualsPending = false

local function RefreshStartupVisuals()
  if not startupVisualsPending then return false end
  startupVisualsPending = false
  return GF.RefreshVisuals(nil, GF.DIRTY_VISUAL)
end

-- SecureGroupHeader can change its measured footprint after MSUF's roster or
-- entering-world handler returns (including from our layout nonce). Re-read the
-- live kind/count and apply saved visuals once on the next frame so secure
-- children have settled before anchor sizing, screen clamping, and opacity.
local headerLayoutSettlePending = false
local headerLayoutSettleNeedsRosterState = false

local function FlushHeaderLayoutSettle()
  local refreshRosterState = headerLayoutSettleNeedsRosterState
  headerLayoutSettlePending = false
  headerLayoutSettleNeedsRosterState = false

  if not AnyGroupFrameEnabled() then return false end
  if InCombat() then
    return GF.DeferGroupRuntime(refreshRosterState and "roster" or "layout")
  end

  local did = GF.RefreshHeaderLayout()
  did = RefreshStartupVisuals() or did
  if not refreshRosterState then return did end
  did = RefreshVisiblePartyState("GROUP_ROSTER_UPDATE") or did
  return RefreshVisibleRoleState("PLAYER_ROLES_ASSIGNED") or did
end

local function ScheduleHeaderLayoutSettle(refreshRosterState)
  if refreshRosterState == true then headerLayoutSettleNeedsRosterState = true end
  if headerLayoutSettlePending then return false end
  headerLayoutSettlePending = true
  if C_Timer and type(C_Timer.After) == "function" then
    C_Timer.After(0, FlushHeaderLayoutSettle)
  else
    FlushHeaderLayoutSettle()
  end
  return true
end

-- UNIT_NAME_UPDATE can arrive in a burst while a group roster is initializing.
-- Collapse that burst into one cold-path secure nameList rebuild instead of
-- repeatedly scanning 40 members and cycling the conditional event set.
local priorityNameSettlePending = false

local function FlushPriorityNameSettle()
  priorityNameSettlePending = false
  return GF.RefreshPriorityFrames("unit-name-settle")
end

local function SchedulePriorityNameSettle()
  if priorityNameSettlePending then return false end
  priorityNameSettlePending = true
  if C_Timer and type(C_Timer.After) == "function" then
    C_Timer.After(0, FlushPriorityNameSettle)
  else
    FlushPriorityNameSettle()
  end
  return true
end

function GF.RefreshUnitBindings(kind)
  if InCombat() then return GF.DeferGroupRuntime("roster", kind, GF.DIRTY_UNIT_BINDING) end
  local did = false
  if GF.headers and GF.ScheduleScan then
    if (not kind or kind == "party") and GF.headers.party then
      did = GF.ScheduleScan("party", "party") or did
    end
    local raidKind = LiveRaidKind()
    if (not kind or kind == "raid" or kind == "mythicraid" or kind == raidKind) and GF.headers.raid then
      did = GF.ScheduleScan("raid", raidKind) or did
    end
    local priorityHeader = GF.headers.priority
    local priorityKind = LivePriorityKind() or (priorityHeader and priorityHeader._msufGFKind) or raidKind
    local priorityRaidLike = priorityKind == "raid" or priorityKind == "mythicraid"
    local priorityMatches = not kind or kind == "priority" or kind == "gf_priority" or kind == priorityKind
      or (priorityRaidLike and (kind == "raid" or kind == "mythicraid"))
    if priorityMatches and priorityHeader then
      did = GF.ScheduleScan("priority", priorityKind) or did
    end
  end
  return did
end

function GF.RefreshPriorityFrames(reason)
  if InCombat() then
    GF._pendingPriorityRefresh = reason or true
    GF._pendingGroupRuntime = true
    AddPendingReason("priority")
    if not GF._pendingGroupRuntimeReason or GF._pendingGroupRuntimeReason == "refresh" then
      GF._pendingGroupRuntimeReason = "priority"
    end
    return false
  end
  local result = SetupWantedPriority()
  SetRuntimeEventsEnabled(AnyGroupFrameEnabled())
  return NotifyRuntimeObservers("refreshPriority", LivePriorityKind(), GF.DIRTY_UNIT_BINDING, result)
end

function GF.RebuildAll()
  if InCombat() then return GF.DeferGroupRuntime("rebuild") end
  if GF.InvalidateCompiledSpecs then GF.InvalidateCompiledSpecs() end
  local result = GF.RefreshHeaderLayout()
  return NotifyRuntimeObservers("rebuildAll", nil, nil, result)
end

function GF.Rebuild(kind)
  if kind == nil then return GF.RebuildAll() end
  if InCombat() then return GF.DeferGroupRuntime("rebuild", kind) end
  if GF.InvalidateCompiledSpecs then GF.InvalidateCompiledSpecs(kind) end
  GF.RefreshHeaderLayout(kind)
  return GF.RefreshVisuals(kind, GF.DIRTY_ALL)
end

-- The group block border lives on the anchor, not on a unit frame, so no
-- element apply can reach it. SetupHeader owns the cold path; without this hook
-- the setting would only take effect on the next layout rebuild or /reload.
local function RefreshGroupBorderForMask(kind, mask)
  if type(GF.ApplyGroupBorder) ~= "function" then return end
  if mask ~= nil and mask ~= true
    and not (mask == GF.DIRTY_ALL or mask == GF.DIRTY_CONFIG
      or MaskHas(mask, GF.DIRTY_BORDER) or MaskHas(mask, GF.DIRTY_VISUAL)
      or MaskHas(mask, GF.DIRTY_COLOR) or MaskHas(mask, GF.DIRTY_GEOMETRY)
      or MaskHas(mask, GF.DIRTY_LAYOUT)) then
    return
  end
  GF.ApplyGroupBorder(kind)
end

local function RefreshVisualsNow(kind, mask)
  local refreshedDomains = GF.RefreshCompiledSpecDomains
    and GF.RefreshCompiledSpecDomains(kind, mask) == true
  if not refreshedDomains and GF.InvalidateCompiledSpecs then
    GF.InvalidateCompiledSpecs(kind)
  end
  RefreshGroupBorderForMask(kind, mask)
  if not GF.ForEachFrame then return false end
  local applyMask = GF.ApplyMaskForDirtyMask(mask)
  return GF.ForEachFrame(ApplyRefreshFrame, true, kind, mask, applyMask)
end

local function RefreshAllNow()
  local layoutResult = GF.RefreshHeaderLayout()
  local visualResult = RefreshVisualsNow(nil, GF.DIRTY_ALL)
  return visualResult or layoutResult
end

function GF.RefreshVisuals(kind, mask)
  if InCombat() then return GF.DeferGroupRuntime("refresh", kind, mask) end
  local result = RefreshVisualsNow(kind, mask)
  return NotifyRuntimeObservers("refreshVisuals", kind, mask, result)
end

function GF.RefreshAll()
  if InCombat() then return GF.DeferGroupRuntime("refreshAll") end
  GF.RefreshHeaderLayout()
  return GF.RefreshVisuals(nil, GF.DIRTY_ALL)
end

GF.Refresh = GF.RefreshAll
GF.RefreshGeometry = function(kind) return GF.RefreshHeaderLayout(kind) end
GF.RefreshOverlays = function(kind) return GF.RefreshVisuals(kind, GF.DIRTY_AURAS) end
GF.RefreshColors = function(kind) return GF.RefreshVisuals(kind, GF.DIRTY_COLOR) end
GF.RefreshBorder = function(kind) return GF.RefreshVisuals(kind, GF.DIRTY_BORDER) end
GF.RefreshOutlineGeometry = GF.RefreshBorder
GF.RefreshFonts = function(kind) return GF.RefreshVisuals(kind, GF.DIRTY_FONT) end

function GF.MarkDirty(frame, mask)
  if InCombat() then
    return GF.DeferGroupRuntime("refresh", frame and frame._msufGFKind or nil, mask)
  end
  if frame and frame._msufGFKind then
    if GF.RefreshCompiledSpecDomains then
      GF.RefreshCompiledSpecDomains(frame._msufGFKind, mask)
    end
    return ApplyFrameDirty(frame, frame._msufGFKind, mask, "MSUF_GF_MARK_DIRTY")
  end
  return GF.RefreshVisuals(nil, mask)
end

function GF.MarkAllDirty(mask)
  if mask == GF.DIRTY_GEOMETRY or mask == GF.DIRTY_LAYOUT or mask == GF.DIRTY_CONFIG then
    return GF.RefreshHeaderLayout("dirty")
  end
  return GF.RefreshVisuals(nil, mask)
end

local function RefreshGroupNameFrame(frame)
  return UF and UF.RunLeanIdentity and UF.RunLeanIdentity(frame, "MSUF_GF_NAME_UPDATE") == true or false
end

function GF.RefreshGroupNames(unit)
  if not (UF and GF.ForEachFrame) then return false end
  if unit then
    if type(GF.ForEachFrameForUnit) == "function" then
      return GF.ForEachFrameForUnit(unit, RefreshGroupNameFrame)
    end
    local frame = GF.FrameForUnit and GF.FrameForUnit(unit)
    return frame and RefreshGroupNameFrame(frame) or false
  end
  return GF.ForEachFrame(RefreshGroupNameFrame, true)
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
  local conf = Conf(kind)
  if not conf then return false end
  if GF.EnsureStableGridPosition then
    local count = GF.GetLiveLayoutCount and GF.GetLiveLayoutCount(kind) or nil
    GF.EnsureStableGridPosition(kind, count, conf)
  end
  conf.offsetX = floor(((tonumber(conf.offsetX) or 0) + (tonumber(dx) or 0)) + 0.5)
  conf.offsetY = floor(((tonumber(conf.offsetY) or 0) + (tonumber(dy) or 0)) + 0.5)
  conf.positionMode = "GRID_BOUNDS_V2"
  return GF.RefreshGeometry(kind)
end

--- Reasons that map to a work unit in FlushDeferred. Anything else falls back to
--- the RefreshAll catch-all, exactly as the previous single-reason dispatch did.
local DEFERRED_REASON_UNITS = {
  refresh = true,
  roster = true,
  visibility = true,
  layout = true,
  rebuild = true,
  refreshAll = true,
  priority = true,
}

--- Runs the union of everything deferred during combat. Reasons are orthogonal
--- work units, not alternatives: only rebuild/refreshAll subsume the rest. Each
--- unit below is an idempotent cold-path pass, so overlapping reasons are safe.
local function FlushDeferred()
  local reasons = GF._pendingGroupRuntimeReasons
  local kind = GF._pendingGroupRuntimeKind
  local mask = GF._pendingGroupRuntimeMask
  GF._pendingGroupRuntime = nil
  GF._pendingGroupRuntimeReason = nil
  GF._pendingGroupRuntimeReasons = nil
  GF._pendingGroupRuntimeKind = nil
  GF._pendingGroupRuntimeMask = nil

  --- No reason recorded (only the bare pending flag, e.g. the Headers fallback
  --- path): keep the established catch-all.
  if not reasons or next(reasons) == nil then return GF.RefreshAll() end

  --- A reason without its own work unit ("setup" from the header rebind path)
  --- used to land on the single-dispatch catch-all. RefreshAll is the strongest
  --- pass and subsumes every unit below, so it still stands in for them.
  for reason in pairs(reasons) do
    if not DEFERRED_REASON_UNITS[reason] then return GF.RefreshAll() end
  end

  if reasons.rebuild then
    if kind and type(GF.Rebuild) == "function" then return GF.Rebuild(kind) end
    local result = RefreshAllNow()
    return NotifyRuntimeObservers("rebuildAll", nil, GF.DIRTY_ALL, result)
  end
  if reasons.refreshAll then return GF.RefreshAll() end

  local did = false
  --- Header setup. roster/layout scope it to `kind`; visibility always covers
  --- every wanted kind, and carries no SetRuntimeEventsEnabled/seed-event work,
  --- so both passes run when both were deferred.
  if reasons.roster or reasons.layout then
    did = GF.RefreshHeaderLayout(kind) or did
  end
  if reasons.visibility then
    did = GF.UpdateGroupVisibility() or did
  end
  if reasons.roster then
    did = RefreshVisiblePartyState("GROUP_ROSTER_UPDATE") or did
    did = RefreshVisibleRoleState("PLAYER_ROLES_ASSIGNED") or did
  end
  --- No priority work unit on purpose: SetupWantedHeaders already ends in
  --- SetupWantedPriority (the one switching secure header follows whichever base
  --- kind is active) and clears _pendingPriorityRefresh, and RuntimeOnEvent
  --- catches up straight after this flush when no header pass ran. Refreshing it
  --- here as well rebuilt the Priority header twice per regen.
  --- "refresh" always repaints visuals; layout/priority only when a mask came
  --- with them, matching the previous per-reason behaviour.
  if reasons.refresh then
    did = GF.RefreshVisuals(kind, mask) or did
  elseif mask and type(GF.RefreshVisuals) == "function"
    and (reasons.layout or reasons.priority) then
    did = GF.RefreshVisuals(kind, mask) or did
  end
  return did
end

local function RuntimeOnEvent(self, event, unit)
  -- SavedVariables/config caches are only reliable at the startup event
  -- boundary. Handle it before the disabled fast-exit so a cold cache cannot
  -- unregister the very events that perform the first live header setup.
  if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
    SyncCombatState()
    GF.RefreshHeaderLayout(event)
    if event == "PLAYER_ENTERING_WORLD" then
      startupVisualsPending = true
      RefreshVisiblePartyState(event)
      RefreshVisibleRoleState("PLAYER_ROLES_ASSIGNED")
      ScheduleHeaderLayoutSettle()
    end
    return
  end
  if not AnyGroupFrameEnabled() and event ~= "PLAYER_REGEN_ENABLED" then
    SetRuntimeEventsEnabled(false)
    return
  end
  if event == "PLAYER_REGEN_ENABLED" then
    SyncCombatState(false)
    if GF._pendingGroupRuntime then FlushDeferred() end
    RefreshStartupVisuals()
    -- Priority selection is orthogonal to the broader pending reason. Catch up
    -- once unless the broad flush already rebuilt the active Priority header.
    if GF._pendingPriorityRefresh then GF.RefreshPriorityFrames("deferred-priority") end
    if type(GF.RefreshCornerThreatState) == "function" then
      GF.RefreshCornerThreatState(event)
    end
    SetRuntimeEventsEnabled(AnyGroupFrameEnabled())
    return
  elseif event == "PLAYER_REGEN_DISABLED" then
    SyncCombatState(true)
    if type(GF.HidePreviewsForCombat) == "function" then
      GF.HidePreviewsForCombat()
    end
    return
  elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" or event == "ROLE_CHANGED_INFORM" then
    if event == "GROUP_ROSTER_UPDATE" and type(GF.ApplyGroupBorder) == "function" then
      -- The border textures are unprotected and can follow Party/Raid state
      -- immediately even when secure header retirement must wait for combat.
      GF.ApplyGroupBorder()
    end
    if InCombat() then
      GF.DeferGroupRuntime("roster")
    elseif event == "GROUP_ROSTER_UPDATE" then
      -- Let Blizzard's SecureGroupHeader finish the current roster dispatch;
      -- repeated roster churn in the same frame collapses into this one pass.
      ScheduleHeaderLayoutSettle(true)
    else
      GF.RefreshHeaderLayout(event)
      RefreshVisibleRoleState(event)
    end
    return
  elseif event == "UNIT_NAME_UPDATE" then
    if not IsUnitToken(unit) then return end
    local valid
    if type(GF.IsPriorityGroupUnit) == "function" then
      valid = GF.IsPriorityGroupUnit(unit)
    elseif LiveGroupKind() ~= "party" and IsInRaid and IsInRaid() then
      valid = unit:match("^raid%d+$") ~= nil
    else
      valid = unit == "player" or unit:match("^party[1-4]$") ~= nil
    end
    if valid ~= true then return end
    if InCombat() then
      GF.RefreshPriorityFrames("unit-name")
    else
      SchedulePriorityNameSettle()
    end
    return
  elseif event == "PLAYER_DIFFICULTY_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" then
    GF.RefreshHeaderLayout(event)
    ScheduleHeaderLayoutSettle()
  end
end

eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", RuntimeOnEvent)
-- SecureGroupHeaderTemplate starts hidden. Keep only the two one-shot startup
-- events until SavedVariables are ready; RefreshHeaderLayout then installs the
-- normal enabled event set or unregisters everything for a disabled runtime.
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

local GF_PUBLIC_ALIASES = {
  { "MSUF_GF_RebuildAll", "RebuildAll" },
  { "MSUF_GF_RefreshAll", "RefreshAll" },
  { "MSUF_GF_Refresh", "RefreshAll" },
  { "MSUF_GF_RefreshVisuals", "RefreshVisuals" },
  { "MSUF_GF_RefreshHeaderLayout", "RefreshHeaderLayout" },
  { "MSUF_GF_RefreshUnitBindings", "RefreshUnitBindings" },
  { "MSUF_GF_RefreshPriorityFrames", "RefreshPriorityFrames" },
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
ExportPublic("MSUF_GF_ForceAuraTextColorRefresh", function()
  return GF.RefreshVisuals(nil, GF.DIRTY_AURAS)
end)
