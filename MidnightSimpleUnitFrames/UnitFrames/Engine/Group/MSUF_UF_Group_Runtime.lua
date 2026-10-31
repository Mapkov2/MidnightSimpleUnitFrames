local _, MSUF = ...

local ExportPublic = MSUF.ExportPublic

local GF = MSUF.GF or {}
MSUF.GF = GF
local UF = MSUF.UF
local Metadata = GF.Metadata or {}

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local InCombatLockdown = InCombatLockdown
local IsInRaid = IsInRaid
local pairs = pairs
local tonumber = tonumber
local tostring = tostring
local type = type

local eventFrame
local runtimeObservers = {}
local dirtyApplyMaskCache = {}
local appliedLayoutScaleByKind = {}
local appliedLayoutWidthByKind, appliedLayoutHeightByKind = {}, {}

local function InCombat()
  return GF._raidRosterCombatActive or InCombatLockdown()
end

local function SyncCombatState(inCombat)
  if inCombat == nil then inCombat = InCombat() end
  inCombat = inCombat == true
  ExportPublic("MSUF_InCombat", inCombat)
  return inCombat
end

local IsUnitToken = UF and UF.IsUnitToken

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

  GF.EnsureDB()
  local resolve = GF.ResolveFrameScale
  local desiredScale = tonumber(resolve(kind))
  local width, height
  width, height = GF.GetScaledFrameMetrics(kind)
  if (desiredScale ~= nil and appliedLayoutScaleByKind[kind] ~= desiredScale)
    or (width ~= nil and (appliedLayoutWidthByKind[kind] ~= width or appliedLayoutHeightByKind[kind] ~= height)) then
    GF.InvalidateCompiledSpecs(kind)
  end

  local header, scanned, success = setup(key, kind)
  if header and desiredScale ~= nil then
    appliedLayoutScaleByKind[kind] = desiredScale
  end
  if header then appliedLayoutWidthByKind[kind], appliedLayoutHeightByKind[kind] = width, height end
  return header, scanned, success
end

local function RefreshRosterStateFrame(frame, _, kind, reason, refreshOverlay)
  if frame._msufGFIsPreviewFrame or (kind ~= "party" and kind ~= "raid" and kind ~= "mythicraid") then return false end
  -- OOC header scans already compile the binding. Frozen combat slots need
  -- current power-role ownership before the lifecycle consumes their spec.
  if refreshOverlay then GF.RefreshFrameRoleOverlay(frame) end
  local refresh = UF and UF.RefreshGroupFrameState
  local did = refresh(frame, reason) == true or false
  -- A roster slot can acquire another player without changing its unit token.
  -- Repaint from the current unit; no readable GUID is required.
  local active = frame._msufActiveElements
  local elements = did and kind ~= "party" and UF.elements
  local health = elements and elements.Health
  if health and active and active.Health == true then health.UpdateIdentityBackground(frame) end
  return did
end

local function RefreshVisibleRosterState(reason)

  return GF.ForEachFrame(RefreshRosterStateFrame, false, reason, InCombat())
end

--- The settled roster repaints as an identity change, not as the raw event:
--- the group status runtime maps GROUP_ROSTER_UPDATE to leader/raid group only,
--- and range fade, power type and the indicators reseed only on this reason. A
--- slot that kept its token for another occupant, or read a disconnect while
--- the roster was in flux, otherwise kept OFFLINE/DEAD/AFK from that read.
local ROSTER_IDENTITY_REASON = "MSUF_GF_UNIT_IDENTITY"

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

  return GF.ForEachFrame(RefreshRoleStateFrame, false, reason or "PLAYER_ROLES_ASSIGNED")
end

local function ConfEnabled(kind)
  local conf = Conf(kind)
  return conf and conf.enabled == true
end

local LiveGroupKind = GF.GetLiveGroupKind

local function ArenaPartyContext()
  return GF.IsArenaPartyContext() == true
end

local function ArenaPartyHeaderActive()
  return ArenaPartyContext() and ConfEnabled("party")
end

-- PVP_MATCH_STATE_CHANGED is Retail-only; Classic arena clients reject the
-- registration. The client model is initialized before the group runtime.
local function MatchStateEventSupported()
  local client = MSUF.Client
  return client.SupportsEvent("PVP_MATCH_STATE_CHANGED") == true
end

--- Only a Party ROLE sort with Player-first emits MSUF's native nameList.
--- Keep its identity catch-up completely absent from PvE and from Arena
--- configurations that stay on SecureGroupHeader's ordinary roster path.
local function ArenaPartyNameListActive()
  if not ArenaPartyHeaderActive() then return false end
  local conf = Conf("party")
  if not (conf and conf.playerFirstInRole == true) then return false end
  local mode = conf.sortMode
  return mode == "ROLE" or (mode == nil and conf.sortByRole == true)
end

local function PriorityNameRefreshActive()
  local kind = GF.GetPriorityBaseKind() or nil
  if not kind then kind = LiveGroupKind() end
  return kind ~= nil and ConfEnabled(kind)
    and GF.PriorityFramesConfigured() == true
end

local function AnyGroupFrameEnabled()
  return GF.AnyMSUFGroupFrameEnabled() == true
end

--- UNIT_NAME_UPDATE has no unit filter (RegisterUnitEvent takes two units), and
--- nameplates raise it all the time. Only these tokens can change a party
--- nameList or a Priority Frames pin; RuntimeOnEvent drops every other unit
--- after one lookup, before any config is read.
local NAME_LIST_UNITS = { player = true }
for i = 1, 4 do NAME_LIST_UNITS["party" .. i] = true end
for i = 1, 40 do NAME_LIST_UNITS["raid" .. i] = true end

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
-- Walking onto or off a plot changes C_Housing.IsInsideHouseOrPlot without a
-- zone change; Blizzard_HousingControls follows these two events for it.
-- Registered only while a scope has Hide in Housing on, where the API exists
-- and the client knows the event.
local HOUSING_EVENTS = { "HOUSE_PLOT_ENTERED", "HOUSE_PLOT_EXITED" }
local housingHidden = { party = false, raid = false }
local housingEventsOn, sceneEventsOn = false, false
local runtimeEventState = {}

--- Group Layout "Hide in Housing" (per scope, off by default): while the player
--- is inside a house or on a plot it retires everything that scope's settings
--- draw: the block, its group border, the Priority Frames that take their
--- settings from it, and its extra blocks (MSUF_GroupFrames_Additional.lua).
--- Blizzard's UI reads IsInsideHouseOrPlot on the Mainline-family clients
--- (Blizzard_Game/Mainline/EventImplementation.lua); the Classic API docs list
--- it too, so the read is feature-detected and a client without it hides nothing.
local function HiddenInHousing(kind)
  local conf = Conf(kind)
  if not (conf and conf.hideInHousing == true) then return false end
  local housing = C_Housing
  local inside = housing and housing.IsInsideHouseOrPlot
  return inside ~= nil and inside() == true
end
GF.HiddenInHousing = HiddenInHousing

local function HiddenByEnvironment(kind)
  if HiddenInHousing(kind) then return true end
  local conf = Conf(kind)
  local scene, types = C_ClientScene, Enum and Enum.ClientSceneType
  if not (conf and conf.hideInClientScene ~= false and scene and scene.IsSceneTypeActive and types and types.MinigameSceneType) then
    return false
  end
  -- Same state as Blizzard_ClientSceneVisManager on upstream/live.
  return scene.IsSceneTypeActive(types.MinigameSceneType) == true
end
GF.HiddenByEnvironment = HiddenByEnvironment

local function SceneEventsWanted()
  local scene, types = C_ClientScene, Enum and Enum.ClientSceneType
  if not (scene and scene.IsSceneTypeActive and types and types.MinigameSceneType and AnyGroupFrameEnabled()) then return false end
  local party, raid, mythic = Conf("party"), Conf("raid"), Conf("mythicraid")
  return (party and party.hideInClientScene ~= false) or (raid and raid.hideInClientScene ~= false)
    or (mythic and mythic.hideInClientScene ~= false) or false
end

local function HousingEventsWanted()
  local housing = C_Housing
  if not (housing and housing.IsInsideHouseOrPlot and AnyGroupFrameEnabled()) then return false end
  local party, raid, mythic = Conf("party"), Conf("raid"), Conf("mythicraid")
  return (party and party.hideInHousing == true) or (raid and raid.hideInHousing == true)
    or (mythic and mythic.hideInHousing == true) or false
end

local function SetRuntimeEventsEnabled(enabled, regenOnly)
  if not eventFrame then return end
  enabled, regenOnly = enabled == true, regenOnly == true
  local active = enabled and not regenOnly
  local matchEvents = active and ArenaPartyHeaderActive() and MatchStateEventSupported() or false
  local nameEvents = active and (PriorityNameRefreshActive() or ArenaPartyNameListActive()) or false
  local client = MSUF.Client
  local sceneEvents = active and client and client.SupportsEvent and SceneEventsWanted() or false
  local housingEvents = active and client and client.SupportsEvent and HousingEventsWanted() or false
  local state = runtimeEventState
  if state.enabled == enabled and state.regenOnly == regenOnly
    and state.matchEvents == matchEvents and state.nameEvents == nameEvents
    and sceneEventsOn == sceneEvents and housingEventsOn == housingEvents then return end
  state.enabled, state.regenOnly = enabled, regenOnly
  state.matchEvents, state.nameEvents = matchEvents, nameEvents
  sceneEventsOn, housingEventsOn = sceneEvents, housingEvents
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
  -- Match-state transitions are the authoritative extra boundary for Arena
  -- round/team swaps. Never subscribe in PvE or on clients that lack the event.
  if matchEvents then
    eventFrame:RegisterEvent("PVP_MATCH_STATE_CHANGED")
  end
  if nameEvents then
    eventFrame:RegisterEvent("UNIT_NAME_UPDATE")
  end
  if sceneEvents then
    if client.SupportsEvent("CLIENT_SCENE_OPENED") then eventFrame:RegisterEvent("CLIENT_SCENE_OPENED") end
    if client.SupportsEvent("CLIENT_SCENE_CLOSED") then eventFrame:RegisterEvent("CLIENT_SCENE_CLOSED") end
  end
  if housingEvents then
    for i = 1, #HOUSING_EVENTS do
      if client.SupportsEvent(HOUSING_EVENTS[i]) then eventFrame:RegisterEvent(HOUSING_EVENTS[i]) end
    end
  end
end

local function LiveRaidKind()
  local kind = GF.GetLiveRaidKind and GF.GetLiveRaidKind() or nil
  if kind == "mythicraid" then return "mythicraid" end
  if LiveGroupKind() == nil then
    local raid, mythic = Conf("raid"), Conf("mythicraid")
    if not (raid and raid.enabled and raid.showSolo) and mythic and mythic.enabled and mythic.showSolo then
      return "mythicraid"
    end
  end
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
  if kind == nil then
    local conf = Conf(LiveRaidKind())
    return conf and conf.enabled == true and conf.showSolo == true and conf.showPlayer ~= false
  end
  if kind ~= "raid" and kind ~= "mythicraid" then return false end
  return ConfEnabled(kind)
end

local function PreviewSuppressesHeader(key)
  if MSUF_UnitEditModeActive == true then return false end
  local active = GF._previewActive
  if not active then return false end
  if key == "party" then return active.party == true end
  if key == "raid" then return active.raid == true or active.mythicraid == true end
  if key == "priority" then return active.priority == true end
  return false
end

local function LivePriorityKind()
  return GF.GetPriorityBaseKind()
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
  local priorityKind = LivePriorityKind()
  local wanted = WantPriorityBase(priorityKind)
    and not PreviewSuppressesHeader("priority")
    and not HiddenByEnvironment(priorityKind)
    and GF.PriorityFramesConfigured() == true
  if not wanted then
    GF._pendingPriorityRefresh = nil
    return RetireHeader("priority"), true
  end
  local resolve = GF.ResolvePrioritySelection
  local setup = GF.SetupPriorityHeader
  local nameList, count = resolve()
  if not nameList or not count or count < 1 then
    GF._pendingPriorityRefresh = nil
    GF.NotifyPriorityListeners("runtime-empty", 0)
    return RetireHeader("priority"), true
  end
  local header, _, success = setup(priorityKind, nameList, count)
  if header and header.Show then header:Show() end
  success = header ~= nil and success ~= false
  GF._pendingPriorityRefresh = not success or nil
  GF.NotifyPriorityListeners("runtime", count)
  return success, success
end

local function FinishOwnershipHandoff()
  -- Group borders live on persistent, unprotected anchors rather than on the
  -- secure headers retired above. Reconcile both anchors after every scope
  -- transition so the inactive Party/Raid border cannot survive the switch.
  GF.ApplyGroupBorder()

  if GF.ApplyBlizzardGroupFrameOwnership then
    GF.ApplyBlizzardGroupFrameOwnership("lean-runtime")
  end
  return true
end

local function SetupWantedHeaders(kind)
  local scope = HeaderScope(kind)
  local raidKind = LiveRaidKind()
  -- "Hide in Housing" retires a block the way a preview does. Remember what this
  -- pass decided per block: a plot boundary, or the option changing inside
  -- (RefreshVisuals), runs the visibility pass only when that changes.
  if scope ~= "raid" and scope ~= "priority" then housingHidden.party = HiddenByEnvironment("party") end
  if scope ~= "party" and scope ~= "priority" then housingHidden.raid = HiddenByEnvironment(raidKind) end
  if not AnyGroupFrameEnabled() then
    if not scope or scope == "party" then RetireHeader("party") end
    if not scope or scope == "raid" then RetireHeader("raid") end
    RetireHeader("priority")
    return FinishOwnershipHandoff(), true
  end

  local success = true
  local wantParty = WantParty() and not PreviewSuppressesHeader("party") and not housingHidden.party
  local wantRaid = WantRaid() and not PreviewSuppressesHeader("raid") and not housingHidden.raid

  if scope ~= "raid" and scope ~= "priority" and wantParty then
    local header, scanHandled, scanned
    header, scanHandled, scanned = SetupLiveHeader("party", "party")
    GF.ShowHeaders("party")
    if not header or scanned == false then
      success = false
    elseif not scanHandled then
      local did
      did, scanned = GF.ScanHeader("party", "party")
      if scanned == false then success = false end
    end
  elseif scope ~= "raid" and scope ~= "priority" then
    RetireHeader("party")
  end

  if scope ~= "party" and scope ~= "priority" and wantRaid then
    local header, scanHandled, scanned
    header, scanHandled, scanned = SetupLiveHeader("raid", raidKind)
    GF.ShowHeaders("raid")
    if not header or scanned == false then
      success = false
    elseif not scanHandled then
      local did
      did, scanned = GF.ScanHeader("raid", raidKind)
      if scanned == false then success = false end
    end
  elseif scope ~= "party" and scope ~= "priority" then
    RetireHeader("raid")
  end

  -- Priority inherits whichever base group kind is active, so both Party and
  -- Raid scoped layout changes must update the one switching secure header.
  local _, prioritySuccess = SetupWantedPriority()
  if prioritySuccess == false then success = false end
  FinishOwnershipHandoff()
  return true, success
end

local function ApplyFrameDirty(frame, kind, mask, reason, applyMask)
  if not (frame and kind) then return nil end
  if not IsUnitToken(frame.MSUFUnitKey) then return nil end
  local spec = GF.CompileSpec(kind, frame, frame.MSUFUnitKey)
  if not spec then return false end
  applyMask = applyMask or (GF.ApplyMaskForDirtyMask and GF.ApplyMaskForDirtyMask(mask)) or Metadata.MASK_RUNTIME
  return GF.ApplyStructureSpec(frame, spec, reason or "MSUF_GF_DIRTY", applyMask) == true
end

local function ApplyRefreshFrame(frame, _, frameKind, kind, mask, applyMask)
  if kind and kind ~= frameKind then return nil end
  return ApplyFrameDirty(frame, frameKind, mask, "MSUF_GF_REFRESH_VISUALS", applyMask)
end

local MaskHas = MSUF.Require("MSUF_UF_MaskHas", "UnitFrames/Engine/Group/MSUF_UF_Group_Runtime.lua")

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
  out = AddDirty(out, MaskHas(incoming, GF.DIRTY_AGGRO) and GF.DIRTY_AGGRO or nil)
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
  if MaskHas(mask, GF.DIRTY_AGGRO) then did = AddElementNames(out, Metadata.MASK_AGGRO) or did end
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

local function NotifyRuntimeObservers(operation, kind, mask, result, success)
  for _, callback in pairs(runtimeObservers) do
    callback(operation, kind, mask, result, success)
  end
  return result, success
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

--- Kinds a deferred pass can be scoped to. Anything else, nil included, means
--- every kind. The merged scope only widens: an unscoped request, or two
--- different kinds, leave the pending kind at DEFER_ALL_KINDS until the flush.
local DEFER_SCOPED_KINDS = { party = true, raid = true, mythicraid = true, priority = true, gf_priority = true }
local DEFER_ALL_KINDS = false

function GF.DeferGroupRuntime(reason, kind, mask)
  GF._pendingGroupRuntime = true
  GF._pendingGroupRuntimeSerial = (GF._pendingGroupRuntimeSerial or 0) + 1
  reason = reason or GF._pendingGroupRuntimeReason or "refresh"
  AddPendingReason(reason)
  local currentReason = GF._pendingGroupRuntimeReason
  if not currentReason or currentReason == "refresh" then
    GF._pendingGroupRuntimeReason = reason
  elseif reason ~= "refresh" then
    GF._pendingGroupRuntimeReason = reason
  end
  if not DEFER_SCOPED_KINDS[kind] then kind = DEFER_ALL_KINDS end
  local currentKind = GF._pendingGroupRuntimeKind
  if currentKind == nil then
    GF._pendingGroupRuntimeKind = kind
  elseif currentKind ~= kind then
    GF._pendingGroupRuntimeKind = DEFER_ALL_KINDS
  end
  if reason == "refresh" and mask == nil then mask = GF.DIRTY_ALL end
  GF._pendingGroupRuntimeMask = MergeDirtyMask(GF._pendingGroupRuntimeMask, mask)
  return false, false
end

function GF.UpdateGroupVisibility()
  if InCombat() then return GF.DeferGroupRuntime("visibility") end
  local did, success = SetupWantedHeaders()
  if success == false then GF.DeferGroupRuntime("visibility") end
  return did, success
end

--- True when Hide in Housing would now retire or restore a block that the last
--- header pass left as it was (a plot boundary, or the option changing inside).
local function HousingVisibilityStale()
  return HiddenByEnvironment("party") ~= housingHidden.party
    or HiddenByEnvironment(LiveRaidKind()) ~= housingHidden.raid
end

function GF.RefreshHeaderLayout(kind)
  GF.InvalidateLayoutRoster()
  local inCombat = GF._raidRosterCombatActive or InCombatLockdown()
  if not inCombat then GF.EnsureDB() end
  local enabled = AnyGroupFrameEnabled()
  if inCombat then
    local result = GF.DeferGroupRuntime("layout", kind)
    SetRuntimeEventsEnabled(enabled, not enabled)
    return result, false
  end
  local result, success = SetupWantedHeaders(kind)
  if success == false then GF.DeferGroupRuntime("layout", kind) end
  SetRuntimeEventsEnabled(enabled)
  GF.RefreshSpellIndicatorSeedEvents()
  return result, success
end

local startupVisualsPending = false

local function RefreshStartupVisuals()
  if not startupVisualsPending then return false end
  local did, success = GF.RefreshVisuals(nil, GF.DIRTY_VISUAL)
  if success ~= false then startupVisualsPending = false end
  return did, success
end

-- SecureGroupHeader can change its measured footprint after MSUF's roster or
-- entering-world handler returns (including from our layout nonce). Re-read the
-- live kind/count and apply saved visuals once on the next frame so secure
-- children have settled before anchor sizing, screen clamping, and opacity.
--- What the one pending settle pass also refreshes; a merge keeps the widest.
--- ROSTER (group state and roles) includes ROLES (role state only).
local SETTLE = { LAYOUT = 0, ROLES = 1, ROSTER = 2 }
local headerLayoutSettlePending = false
local headerLayoutSettleState = SETTLE.LAYOUT
local difficultyLayoutPending = false
local difficultyLayoutGroupKind, difficultyLayoutRaidKind

local function FlushHeaderLayoutSettle()
  local state = headerLayoutSettleState
  headerLayoutSettlePending = false
  difficultyLayoutPending = false

  if not AnyGroupFrameEnabled() then return false end
  local did
  if GF._raidRosterCombatActive or InCombatLockdown() then
    -- Raid slots/layout are frozen, but raidN occupants can still change. Keep
    -- the coalesced identity repaint aligned with the secure click unit.
    did = GF.DeferGroupRuntime(state ~= SETTLE.LAYOUT and "roster" or "layout")
  else
    did = GF.RefreshHeaderLayout()
    did = RefreshStartupVisuals() or did
  end
  if state == SETTLE.ROSTER then did = RefreshVisibleRosterState(ROSTER_IDENTITY_REASON) or did end
  if state ~= SETTLE.LAYOUT then did = RefreshVisibleRoleState("PLAYER_ROLES_ASSIGNED") or did end
  if headerLayoutSettleState == state then headerLayoutSettleState = SETTLE.LAYOUT end
  return did
end

local function ScheduleHeaderLayoutSettle(state)
  if state and state > headerLayoutSettleState then headerLayoutSettleState = state end
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
  local did, success = false, true
  if (not kind or kind == "party") and GF.headers.party then
    local worked, applied = GF.ScanHeader("party", "party")
    did, success = worked or did, success and applied ~= false
  end
  local raidKind = LiveRaidKind()
  if (not kind or kind == "raid" or kind == "mythicraid" or kind == raidKind) and GF.headers.raid then
    local worked, applied = GF.ScanHeader("raid", raidKind)
    did, success = worked or did, success and applied ~= false
  end
  local priorityHeader = GF.headers.priority
  local priorityKind = LivePriorityKind() or (priorityHeader and priorityHeader._msufGFKind) or raidKind
  local priorityRaidLike = priorityKind == "raid" or priorityKind == "mythicraid"
  local priorityMatches = not kind or kind == "priority" or kind == "gf_priority" or kind == priorityKind
    or (priorityRaidLike and (kind == "raid" or kind == "mythicraid"))
  if priorityMatches and priorityHeader then
    local worked, applied = GF.ScanHeader("priority", priorityKind)
    did, success = worked or did, success and applied ~= false
  end
  if not success then GF.DeferGroupRuntime("roster", kind, GF.DIRTY_UNIT_BINDING) end
  return did, success
end

function GF.RefreshPriorityFrames(reason)
  if InCombat() then
    GF._pendingPriorityRefresh = reason or true
    GF._pendingGroupRuntime = true
    GF._pendingGroupRuntimeSerial = (GF._pendingGroupRuntimeSerial or 0) + 1
    AddPendingReason("priority")
    if not GF._pendingGroupRuntimeReason or GF._pendingGroupRuntimeReason == "refresh" then
      GF._pendingGroupRuntimeReason = "priority"
    end
    return false, false
  end
  local result, success = SetupWantedPriority()
  if success == false then GF.DeferGroupRuntime("priority") end
  SetRuntimeEventsEnabled(AnyGroupFrameEnabled())
  return NotifyRuntimeObservers("refreshPriority", LivePriorityKind(), GF.DIRTY_UNIT_BINDING, result, success)
end

function GF.RebuildAll()
  GF.InvalidateLayoutRoster()
  if InCombat() then return GF.DeferGroupRuntime("rebuild") end
  if GF.InvalidateCompiledSpecs then GF.InvalidateCompiledSpecs() end
  local result, success = GF.RefreshHeaderLayout()
  return NotifyRuntimeObservers("rebuildAll", nil, nil, result, success)
end

function GF.Rebuild(kind)
  if kind == nil then return GF.RebuildAll() end
  if InCombat() then return GF.DeferGroupRuntime("rebuild", kind) end
  if GF.InvalidateCompiledSpecs then GF.InvalidateCompiledSpecs(kind) end
  local layout, layoutSuccess = GF.RefreshHeaderLayout(kind)
  local visual, visualSuccess = GF.RefreshVisuals(kind, GF.DIRTY_ALL)
  return visual or layout, layoutSuccess ~= false and visualSuccess ~= false
end

-- The group block border lives on the anchor, not on a unit frame, so no
-- element apply can reach it. SetupHeader owns the cold path; without this hook
-- the setting would only take effect on the next layout rebuild or /reload.
local function RefreshGroupBorderForMask(kind, mask)

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
  local layoutResult, layoutSuccess = GF.RefreshHeaderLayout()
  local visualResult, visualSuccess = RefreshVisualsNow(nil, GF.DIRTY_ALL)
  return visualResult or layoutResult, layoutSuccess ~= false and visualSuccess ~= false
end

function GF.RefreshVisuals(kind, mask)
  if GF.InvalidateTextFormatCache then GF.InvalidateTextFormatCache() end
  if InCombat() then return GF.DeferGroupRuntime("refresh", kind, mask) end
  local result, success = RefreshVisualsNow(kind, mask)
  -- The Hide in Housing toggle applies as a visual change: the header pass
  -- retires or restores the block and (un)registers the plot events.
  if HousingVisibilityStale() or HousingEventsWanted() ~= housingEventsOn or SceneEventsWanted() ~= sceneEventsOn then
    local layout, layoutSuccess = GF.RefreshHeaderLayout()
    result, success = layout or result, success ~= false and layoutSuccess ~= false
  end
  if success == false then GF.DeferGroupRuntime("refresh", kind, mask) end
  return NotifyRuntimeObservers("refreshVisuals", kind, mask, result, success)
end

function GF.RefreshAll()
  if InCombat() then return GF.DeferGroupRuntime("refreshAll") end
  local layout, layoutSuccess = GF.RefreshHeaderLayout()
  local visual, visualSuccess = GF.RefreshVisuals(nil, GF.DIRTY_ALL)
  return visual or layout, layoutSuccess ~= false and visualSuccess ~= false
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
    return GF.RefreshHeaderLayout()
  end
  return GF.RefreshVisuals(nil, mask)
end

local function RefreshGroupNameFrame(frame)
  return UF and UF.RunLeanIdentity and UF.RunLeanIdentity(frame, "MSUF_GF_NAME_UPDATE") == true or false
end

function GF.RefreshGroupNames(unit)
  if unit then return GF.ForEachFrameForUnit(unit, RefreshGroupNameFrame) end
  return GF.ForEachFrame(RefreshGroupNameFrame, true)
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
local function ReplayDeferred(reasons, kind, mask)

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
    if kind then return GF.Rebuild(kind) end
    local result, success = RefreshAllNow()
    return NotifyRuntimeObservers("rebuildAll", nil, GF.DIRTY_ALL, result, success)
  end
  if reasons.refreshAll then return GF.RefreshAll() end

  local did, success = false, true
  --- Header setup. roster/layout scope it to `kind`; visibility always covers
  --- every wanted kind, and carries no SetRuntimeEventsEnabled/seed-event work,
  --- so both passes run when both were deferred.
  if reasons.roster or reasons.layout then
    local worked, applied = GF.RefreshHeaderLayout(kind)
    did, success = worked or did, success and applied ~= false
  end
  if reasons.visibility then
    local worked, applied = GF.UpdateGroupVisibility()
    did, success = worked or did, success and applied ~= false
  end
  if reasons.roster then
    did = RefreshVisibleRosterState(ROSTER_IDENTITY_REASON) or did
    did = RefreshVisibleRoleState("PLAYER_ROLES_ASSIGNED") or did
  end
  if reasons.priority and not (reasons.roster or reasons.layout or reasons.visibility) then
    local worked, applied = GF.RefreshPriorityFrames("deferred-priority")
    did, success = worked or did, success and applied ~= false
  end
  --- Header passes already include priority. A priority-only request runs the
  --- same owner above, once, and retains its flag until the scan succeeds.
  --- "refresh" always repaints visuals; layout/priority only when a mask came
  --- with them, matching the previous per-reason behaviour.
  if reasons.refresh then
    local worked, applied = GF.RefreshVisuals(kind, mask)
    did, success = worked or did, success and applied ~= false
  elseif mask and (reasons.layout or reasons.priority) then
    local worked, applied = GF.RefreshVisuals(kind, mask)
    did, success = worked or did, success and applied ~= false
  end
  return did, success
end

local function FlushDeferred()
  local serial = GF._pendingGroupRuntimeSerial
  local kind = GF._pendingGroupRuntimeKind
  if kind == DEFER_ALL_KINDS then kind = nil end
  local did, success = ReplayDeferred(GF._pendingGroupRuntimeReasons, kind, GF._pendingGroupRuntimeMask)
  if success ~= false and GF._pendingGroupRuntimeSerial == serial then
    GF._pendingGroupRuntime = nil
    GF._pendingGroupRuntimeReason = nil
    GF._pendingGroupRuntimeReasons = nil
    GF._pendingGroupRuntimeKind = nil
    GF._pendingGroupRuntimeMask = nil
  end
  return did, success
end

local function RuntimeOnEvent(self, event, unit)
  if event == "UNIT_NAME_UPDATE" and not (IsUnitToken(unit) and NAME_LIST_UNITS[unit]) then return end
  -- SavedVariables/config caches are only reliable at the startup event
  -- boundary. Handle it before the disabled fast-exit so a cold cache cannot
  -- unregister the very events that perform the first live header setup.
  if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
    SyncCombatState()
    GF.RefreshHeaderLayout()
    if event == "PLAYER_ENTERING_WORLD" then
      startupVisualsPending = true
      RefreshVisibleRosterState(event)
      RefreshVisibleRoleState("PLAYER_ROLES_ASSIGNED")
      ScheduleHeaderLayoutSettle()
    end
    return
  end
  if not AnyGroupFrameEnabled() and event ~= "PLAYER_REGEN_ENABLED" then
    SetRuntimeEventsEnabled(false, InCombat())
    return
  end
  if event == "PLAYER_REGEN_ENABLED" then
    SyncCombatState(false)
    local refreshEvents = GF._pendingGroupRuntime or runtimeEventState.regenOnly
    GF.SetRaidRosterFrozen(false)
    if GF._pendingGroupRuntime then FlushDeferred() end
    RefreshStartupVisuals()
    -- Priority selection is orthogonal to the broader pending reason. Catch up
    -- once unless the broad flush already rebuilt the active Priority header.
    if GF._pendingPriorityRefresh and not GF._pendingGroupRuntime then GF.RefreshPriorityFrames("deferred-priority") end
    GF.RefreshCornerThreatState(event)
    if refreshEvents then SetRuntimeEventsEnabled(AnyGroupFrameEnabled()) end
    return
  elseif event == "PLAYER_REGEN_DISABLED" then
    SyncCombatState(true)
    -- A preview retires its scope's live header (PreviewSuppressesHeader), and
    -- combat hides every preview. Hand the block back to the live header now:
    -- REGEN_DISABLED fires before InCombatLockdown() is true, and once lockdown
    -- begins the header could not come back before regen.
    if GF.HidePreviewsForCombat() == true then
      SetupWantedHeaders()
    end
    GF.SetRaidRosterFrozen(true)
    return
  elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" or event == "ROLE_CHANGED_INFORM" then
    GF.InvalidateLayoutRoster()
    local inCombat = InCombat()
    if event == "GROUP_ROSTER_UPDATE" then
      GF.ApplyGroupBorder(inCombat and "party" or nil)
    end
    if inCombat then
      GF.DeferGroupRuntime("roster")
      if event == "GROUP_ROSTER_UPDATE" then ScheduleHeaderLayoutSettle(SETTLE.ROSTER) end
    else
      -- Let Blizzard's SecureGroupHeader finish the current roster dispatch;
      -- repeated roster churn and a role poll's burst of PLAYER_ROLES_ASSIGNED /
      -- ROLE_CHANGED_INFORM (one per member) collapse into this one pass.
      ScheduleHeaderLayoutSettle(event == "GROUP_ROSTER_UPDATE" and SETTLE.ROSTER or SETTLE.ROLES)
    end
    return
  elseif event == "PVP_MATCH_STATE_CHANGED" then
    if not ArenaPartyHeaderActive() then return end
    if InCombat() then
      GF.DeferGroupRuntime("roster", "party")
    else
      -- One coalesced cold-path pass per match-state edge; no polling.
      ScheduleHeaderLayoutSettle(SETTLE.ROSTER)
    end
    return
  elseif event == "UNIT_NAME_UPDATE" then
    local partyNameListUnit = ArenaPartyNameListActive()
      and (unit == "player" or unit:match("^party[1-4]$") ~= nil)
    local priorityUnit = false
    if PriorityNameRefreshActive() then
      priorityUnit = GF.IsPriorityGroupUnit(unit) == true
    end
    if partyNameListUnit ~= true and priorityUnit ~= true then return end
    if InCombat() then
      if partyNameListUnit == true then GF.DeferGroupRuntime("roster", "party") end
      if priorityUnit == true then GF.RefreshPriorityFrames("unit-name") end
    else
      if partyNameListUnit == true then ScheduleHeaderLayoutSettle() end
      if priorityUnit == true then SchedulePriorityNameSettle() end
    end
    return
  elseif event == "PLAYER_DIFFICULTY_CHANGED" then
    -- Keep a real shared-header kind switch immediate. Repeated difficulty
    -- notifications for the same kinds share that pass until the native settle.
    local groupKind, raidKind = LiveGroupKind(), LiveRaidKind()
    if not difficultyLayoutPending or groupKind ~= difficultyLayoutGroupKind or raidKind ~= difficultyLayoutRaidKind then
      difficultyLayoutPending = false
      local _, success = GF.RefreshHeaderLayout()
      if success ~= false then
        difficultyLayoutPending = true
        difficultyLayoutGroupKind, difficultyLayoutRaidKind = groupKind, raidKind
      end
    end
    ScheduleHeaderLayoutSettle()
  elseif event == "ZONE_CHANGED_NEW_AREA" then
    -- HeaderScope() is nil for this event, so an inline pass would be an exact
    -- duplicate of the settle's own RefreshHeaderLayout(). Rebuilding every raid
    -- button twice inside the post-loading-screen frame is what tripped the
    -- script watchdog; the queued pass alone repaints one frame later.
    ScheduleHeaderLayoutSettle()
  elseif event == "HOUSE_PLOT_ENTERED" or event == "HOUSE_PLOT_EXITED"
    or event == "CLIENT_SCENE_OPENED" or event == "CLIENT_SCENE_CLOSED" then
    -- Only a scope with Hide in Housing on changes; the visibility pass waits
    -- for the end of combat by itself, and so do the protected extra blocks.
    if HousingVisibilityStale() then
      GF.UpdateGroupVisibility()
      if GF.RequestAdditionalGroupsRefresh then GF.RequestAdditionalGroupsRefresh() end
    end
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
