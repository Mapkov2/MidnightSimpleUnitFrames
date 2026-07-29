--- UnitFrames/Engine/Group/MSUF_UF_Group_Status.lua
--- Group-frame status indicator runtime.
---
--- Status icons/text share the generic UF status runtime, but group frames need
--- extra dispatch for raid markers, leader/assist, ready checks, summons,
--- phase, incoming res, PVP, AFK/DND, and raid group labels. This file compiles
--- those event needs and updates only the affected status regions.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = MSUF

local UF = MSUF.UF
local GF = MSUF.GF or {}
MSUF.GF = GF

if not (UF and UF.RegisterElement) then return end

local CreateFrame = _G.CreateFrame
local InCombatLockdown = _G.InCombatLockdown
local next = next
local type = type

local function InCombat()
  return InCombatLockdown ~= nil and InCombatLockdown() == true
end

local STATUS_EVENT_KIND = {
  RAID_TARGET_UPDATE = 1,
  PARTY_LEADER_CHANGED = 2,
  GROUP_ROSTER_UPDATE = 3,
  READY_CHECK = 4,
  READY_CHECK_CONFIRM = 4,
  READY_CHECK_FINISHED = 4,
  INCOMING_SUMMON_CHANGED = 5,
  INCOMING_RESURRECT_CHANGED = 6,
  UNIT_PHASE = 7,
  UNIT_OTHER_PARTY_CHANGED = 7,
  UNIT_HEALTH = 8,
  UNIT_CONNECTION = 8,
  UNIT_FLAGS = 8,
  PLAYER_FLAGS_CHANGED = 8,
  PARTY_MEMBER_ENABLE = 8,
  PARTY_MEMBER_DISABLE = 8,
  UNIT_FACTION = 9,
  PLAYER_ROLES_ASSIGNED = 10,
  ROLE_CHANGED_INFORM = 10,
}

local statusRuntime = MSUF.UFStatusRuntime or {}
local UpdateRaidMarker = statusRuntime.UpdateRaidMarker
local UpdateLeaderPair = statusRuntime.UpdateLeaderPair
local UpdateReadyCheck = statusRuntime.UpdateReadyCheck
local UpdateSummon = statusRuntime.UpdateSummon
local UpdateIncomingRes = statusRuntime.UpdateIncomingRes
local UpdatePhase = statusRuntime.UpdatePhase
local UpdateStatusText = statusRuntime.UpdateStatusText
local UpdateRaidGroup = statusRuntime.UpdateRaidGroup
local UpdateRole = statusRuntime.UpdateRole
local UpdatePVP = statusRuntime.UpdatePVP
local EMPTY_EVENTS = {}

--- Status runtime may load before or after this file depending on addon order.
--- Bind lazily so Apply/Update can recover once the shared runtime exists.
local function BindStatusRuntime()
  statusRuntime = MSUF.UFStatusRuntime or statusRuntime
  if not statusRuntime then return false end
  UpdateRaidMarker = UpdateRaidMarker or statusRuntime.UpdateRaidMarker
  UpdateLeaderPair = UpdateLeaderPair or statusRuntime.UpdateLeaderPair
  UpdateReadyCheck = UpdateReadyCheck or statusRuntime.UpdateReadyCheck
  UpdateSummon = UpdateSummon or statusRuntime.UpdateSummon
  UpdateIncomingRes = UpdateIncomingRes or statusRuntime.UpdateIncomingRes
  UpdatePhase = UpdatePhase or statusRuntime.UpdatePhase
  UpdateStatusText = UpdateStatusText or statusRuntime.UpdateStatusText
  UpdateRaidGroup = UpdateRaidGroup or statusRuntime.UpdateRaidGroup
  UpdateRole = UpdateRole or statusRuntime.UpdateRole
  UpdatePVP = UpdatePVP or statusRuntime.UpdatePVP
  return statusRuntime ~= nil
end

--- The group status dispatch table stores direct function calls for the enabled
--- status features. Validate the exact handlers the compiled status will use so
--- a partial runtime bind unregisters cleanly instead of nil-calling later.
local function StatusRuntimeReady(status)
  if not status then return false end
  BindStatusRuntime()
  if not statusRuntime then return false end
  if status.runtimeRaidMarker == true and not UpdateRaidMarker then return false end
  if status.runtimeLeaderPair == true and not UpdateLeaderPair then return false end
  if status.role and status.role.enabled == true and not UpdateRole then return false end
  if status.runtimeReadyCheck == true and not UpdateReadyCheck then return false end
  if status.runtimeSummon == true and not UpdateSummon then return false end
  if status.runtimeIncomingRes == true and not UpdateIncomingRes then return false end
  if status.runtimePhase == true and not UpdatePhase then return false end
  if status.runtimeRaidGroup == true and not UpdateRaidGroup then return false end
  if status.runtimeStatusText == true and not UpdateStatusText then return false end
  if status.runtimePVP == true and not UpdatePVP then return false end
  return true
end

local function RunRaidMarker(frame, status)
  UpdateRaidMarker(frame, status)
end

local function RunLeaderPair(frame, status)
  UpdateLeaderPair(frame, status)
end

--- Subgroup membership is cold data, but GROUP_ROSTER_UPDATE also fires for
--- joins, leaves and disconnects, so it must not repaint 40 frames mid-fight.
---
--- When the raid group is the only consumer of that event, the driver drops the
--- registration for the duration of combat (see SuspendRosterForCombat), so the
--- in-combat cost is exactly zero: the event never reaches Lua. Leader/assist
--- share the event and do need it live, so when either is on the event keeps
--- firing and this runner short-circuits on a cached boolean instead of an
--- InCombatLockdown call.
local combatActive = false
local raidGroupDeferred = false

local function DeferRaidGroupForCombat()
  if raidGroupDeferred then return end
  raidGroupDeferred = true
  if type(GF.DeferGroupRuntime) == "function" then
    GF.DeferGroupRuntime("refresh", nil, GF.DIRTY_VISUAL)
  else
    GF._pendingGroupRuntime = GF._pendingGroupRuntime or "refresh"
  end
end

local function UpdateRaidGroupColdPath(frame, status)
  if combatActive then
    DeferRaidGroupForCombat()
    return
  end
  raidGroupDeferred = false
  UpdateRaidGroup(frame, status)
end

local function RunLeaderPairRaidGroup(frame, status)
  UpdateLeaderPair(frame, status)
  UpdateRaidGroupColdPath(frame, status)
end

local function RunRaidGroup(frame, status)
  UpdateRaidGroupColdPath(frame, status)
end

local function RunReadyCheck(frame, status, event)
  UpdateReadyCheck(frame, status, event)
end

local function RunSummon(frame, status)
  UpdateSummon(frame, status)
end

local function RunSummonIncomingRes(frame, status)
  UpdateSummon(frame, status)
  UpdateIncomingRes(frame, status)
end

local function RunIncomingRes(frame, status)
  UpdateIncomingRes(frame, status)
end

local function RunPVP(frame, status)
  if UpdatePVP then
    UpdatePVP(frame, status)
  end
end

local function RunRole(frame, status)
  UpdateRole(frame, status)
end

local function RunPhase(frame, status)
  UpdatePhase(frame, status)
end

local function RunStatusText(frame, status, event, seedHP)
  UpdateStatusText(frame, status, event, seedHP)
end

local function RunStatusApply(frame, status, event)
  if status.runtimeRaidMarker == true then
    UpdateRaidMarker(frame, status)
  end
  if status.runtimeLeaderPair == true then
    UpdateLeaderPair(frame, status)
  end
  if status.runtimeReadyCheck == true then
    UpdateReadyCheck(frame, status, event)
  end
  if status.runtimeSummon == true then
    UpdateSummon(frame, status)
  end
  if status.runtimePhase == true then
    UpdatePhase(frame, status)
  end
  if status.runtimeIncomingRes == true then
    UpdateIncomingRes(frame, status)
  end
  if status.runtimeRaidGroup == true then
    UpdateRaidGroup(frame, status)
  end
  if status.runtimeStatusText == true then
    UpdateStatusText(frame, status, event)
  end
  if status.runtimePVP == true and UpdatePVP then
    UpdatePVP(frame, status)
  end
  if status.role and status.role.enabled == true then
    UpdateRole(frame, status)
  end
end

--- Convert a compiled status config into a small dispatch table so Update can
--- run the exact functions relevant for the incoming event.
local function CompileStatusDispatch(status)
  local dispatch = status and status.runtimeDispatch
  if dispatch then
    return dispatch
  end
  dispatch = {}
  if status.runtimeRaidMarker == true then
    dispatch[1] = RunRaidMarker
  end
  if status.runtimeLeaderPair == true then
    dispatch[2] = RunLeaderPair
  end
  if status.runtimeLeaderPair == true and status.runtimeRaidGroup == true then
    dispatch[3] = RunLeaderPairRaidGroup
  elseif status.runtimeLeaderPair == true then
    dispatch[3] = RunLeaderPair
  elseif status.runtimeRaidGroup == true then
    dispatch[3] = RunRaidGroup
  end
  if status.runtimeReadyCheck == true then
    dispatch[4] = RunReadyCheck
  end
  if status.runtimeSummon == true and status.runtimeIncomingRes == true then
    dispatch[5] = RunSummonIncomingRes
  elseif status.runtimeSummon == true then
    dispatch[5] = RunSummon
  elseif status.runtimeIncomingRes == true then
    dispatch[5] = RunIncomingRes
  end
  if status.runtimeIncomingRes == true then
    dispatch[6] = RunIncomingRes
  end
  if status.runtimePhase == true then
    dispatch[7] = RunPhase
  end
  if status.runtimeStatusText == true then
    dispatch[8] = RunStatusText
  end
  if status.runtimePVP == true then
    dispatch[9] = RunPVP
  end
  if status.role and status.role.enabled == true then
    dispatch[10] = RunRole
  end
  dispatch.apply = RunStatusApply
  status.runtimeDispatch = dispatch
  return dispatch
end

local function RunStatusRuntimeFrame(frame, event, unit, seedHP)
  local status = frame and frame._msufGFStatusRuntimeStatus
  local dispatch = frame and frame._msufGFStatusRuntimeDispatch
  if not (status and dispatch) then
    status = frame and frame.MSUFSpec and frame.MSUFSpec.status
    if not status then return end
    if not StatusRuntimeReady(status) then return end
    dispatch = status.runtimeDispatch or CompileStatusDispatch(status)
  end
  local kind = STATUS_EVENT_KIND[event]
  -- A known event with no compiled owner is intentionally a no-op. Only
  -- synthetic lifecycle/identity reasons (which have no event kind) need the
  -- full apply fallback; using `and/or` here made a missing specialized runner
  -- repaint every status region and could re-read unrelated state.
  local runner = kind and dispatch[kind] or nil
  if not kind then
    runner = dispatch.apply
  end
  if runner then
    runner(frame, status, event, seedHP)
  end
end

local unitlessDriver
local unitlessFramesByEvent = {}
local unitlessIndexByEvent = {}
local unitlessCountByEvent = {}
local unitlessRegistered = {}

local function RunTargetedUnitlessStatus(frame, unit, event, registered, live)
  if frame and (not live or live[frame] == true) then
    local active = frame._msufActiveElements
    if active and active.GroupStatusRuntime == true and registered and registered[frame] then
      RunStatusRuntimeFrame(frame, event, unit)
      return true
    end
  end
  return false
end

local ROSTER_EVENT = "GROUP_ROSTER_UPDATE"
local rosterSuspended = false
local BroadcastUnitlessStatus
local RefreshUnitlessDriverEvent

--- Leader and assist ride the same roster event and do need it live, so the
--- registration may only be dropped when the raid group is its sole consumer.
--- One O(frames) walk per combat start, never per event.
local function RosterEventHasLiveConsumer()
  local list = unitlessFramesByEvent[ROSTER_EVENT]
  if not list then return false end
  for i = 1, #list do
    local frame = list[i]
    local status = frame and (frame._msufGFStatusRuntimeStatus
      or (frame.MSUFSpec and frame.MSUFSpec.status))
    if status and status.runtimeLeaderPair == true then return true end
  end
  return false
end

local function SuspendRosterForCombat()
  if rosterSuspended or not unitlessDriver then return end
  if unitlessRegistered[ROSTER_EVENT] ~= true then return end
  if RosterEventHasLiveConsumer() then return end
  unitlessDriver:UnregisterEvent(ROSTER_EVENT)
  unitlessRegistered[ROSTER_EVENT] = nil
  rosterSuspended = true
end

--- The event was off, so a roster change during the fight went unseen. Restore
--- the registration and repaint once, exactly as the missed event would have.
local function ResumeRosterAfterCombat()
  if not rosterSuspended then return end
  rosterSuspended = false
  RefreshUnitlessDriverEvent(ROSTER_EVENT)
  if BroadcastUnitlessStatus then BroadcastUnitlessStatus(ROSTER_EVENT) end
end

local function EnsureUnitlessDriver()
  if unitlessDriver or not CreateFrame then
    return unitlessDriver
  end
  unitlessDriver = CreateFrame("Frame")
  -- A driver built mid-combat never sees the PLAYER_REGEN_DISABLED that already
  -- happened, so seed the cached state once here instead of leaving it stale.
  combatActive = InCombat()
  unitlessDriver:RegisterEvent("PLAYER_REGEN_DISABLED")
  unitlessDriver:RegisterEvent("PLAYER_REGEN_ENABLED")
  unitlessDriver:SetScript("OnEvent", function(_, event, unitTarget)
    if event == "PLAYER_REGEN_DISABLED" then
      combatActive = true
      SuspendRosterForCombat()
      return
    elseif event == "PLAYER_REGEN_ENABLED" then
      combatActive = false
      ResumeRosterAfterCombat()
      return
    end
    local list = unitlessFramesByEvent[event]
    if not list then
      return
    end
    local live = GF and GF.frames

    -- These unitless registrations still carry the affected unit token. Route
    -- them through the group index instead of broadcasting AFK/DND or ready
    -- state changes across every raid frame. Their start/finished counterparts
    -- remain intentional broadcasts.
    if (event == "READY_CHECK_CONFIRM" or event == "PLAYER_FLAGS_CHANGED")
      and type(unitTarget) == "string" then
      local registered = unitlessIndexByEvent[event]
      local duplicateBucket = GF and GF.priorityUnitFrames and GF.priorityUnitFrames[unitTarget]
      local forEach = GF and GF.ForEachFrameForUnit
      if duplicateBucket and type(forEach) == "function" then
        if forEach(unitTarget, RunTargetedUnitlessStatus, event, registered, live) == true then
          return
        end
        -- A stale duplicate index falls through to the correctness broadcast.
      else
        local frame = GF and type(GF.FrameForUnit) == "function" and GF.FrameForUnit(unitTarget)
        if frame and (not live or live[frame] == true) then
          local active = frame._msufActiveElements
          if active and active.GroupStatusRuntime == true and registered and registered[frame] then
            RunStatusRuntimeFrame(frame, event, unitTarget)
            return
          end
        end
      end
      -- A secure-header unit can be rebound before the adapter's unit index is
      -- refreshed. Preserve correctness by falling through to the old broadcast
      -- path on a lookup miss; the indexed steady state remains O(1).
    end

    BroadcastUnitlessStatus(event, list, live)
  end)
  return unitlessDriver
end

function BroadcastUnitlessStatus(event, list, live)
  list = list or unitlessFramesByEvent[event]
  if not list then return end
  if live == nil then live = GF and GF.frames end
  for i = 1, #list do
    local frame = list[i]
    if frame and (not live or live[frame] == true) then
      local active = frame._msufActiveElements
      if active and active.GroupStatusRuntime == true then
        RunStatusRuntimeFrame(frame, event)
      end
    end
  end
end

function RefreshUnitlessDriverEvent(event)
  local want = (unitlessCountByEvent[event] or 0) > 0
  if not unitlessDriver and not want then
    return
  end
  local driver = EnsureUnitlessDriver()
  if not driver then
    return
  end
  if unitlessRegistered[event] == want then
    return
  end
  if want then
    driver:RegisterEvent(event)
  else
    driver:UnregisterEvent(event)
  end
  unitlessRegistered[event] = want or nil
end

local function AddUnitlessFrame(event, frame)
  if not (event and frame) then
    return
  end
  local list = unitlessFramesByEvent[event]
  if not list then
    list = {}
    unitlessFramesByEvent[event] = list
  end
  local index = unitlessIndexByEvent[event]
  if not index then
    index = {}
    unitlessIndexByEvent[event] = index
  elseif index[frame] then
    return
  end
  local n = #list + 1
  list[n] = frame
  index[frame] = n
  unitlessCountByEvent[event] = (unitlessCountByEvent[event] or 0) + 1
  RefreshUnitlessDriverEvent(event)
end

local function RemoveUnitlessFrame(event, frame)
  local index = event and unitlessIndexByEvent[event]
  local i = index and frame and index[frame]
  if not i then
    return
  end
  local list = unitlessFramesByEvent[event]
  local last = #list
  local tail = list[last]
  list[i] = tail
  list[last] = nil
  index[frame] = nil
  if tail and tail ~= frame then
    index[tail] = i
  end
  local count = (unitlessCountByEvent[event] or 1) - 1
  if count <= 0 then
    unitlessCountByEvent[event] = nil
    unitlessFramesByEvent[event] = nil
    unitlessIndexByEvent[event] = nil
  else
    unitlessCountByEvent[event] = count
  end
  RefreshUnitlessDriverEvent(event)
end

local function ClearUnitlessRegistration(frame)
  local map = frame and frame._msufGFStatusUnitlessMap
  if not map then
    return
  end
  for event in pairs(map) do
    RemoveUnitlessFrame(event, frame)
  end
  frame._msufGFStatusUnitlessMap = nil
end

--- Some status changes are unitless Blizzard events. Register those through one
--- shared driver instead of every frame having its own event frame.
local function SetUnitlessRegistration(frame, status)
  if not frame then
    return
  end
  local events = status and status.groupRuntimeUnitlessEvents
  if not (events and #events > 0) then
    ClearUnitlessRegistration(frame)
    return
  end
  local map = frame._msufGFStatusUnitlessMap
  if not map then
    map = {}
    frame._msufGFStatusUnitlessMap = map
  else
    for event in pairs(map) do
      map[event] = false
    end
  end
  for i = 1, #events do
    local event = events[i]
    if event and map[event] ~= true then
      AddUnitlessFrame(event, frame)
    end
    map[event] = true
  end
  for event, active in pairs(map) do
    if active ~= true then
      RemoveUnitlessFrame(event, frame)
      map[event] = nil
    end
  end
  if next(map) == nil then
    frame._msufGFStatusUnitlessMap = nil
  end
end

local GroupStatusRuntime = {}

function GroupStatusRuntime.IsEnabled(frame, spec)
  local status = spec and spec.status
  return spec and spec.scope == "group" and status and status.groupRuntimeEnabled == true
end

function GroupStatusRuntime.GetEvents(frame, spec)
  local status = spec and spec.status
  return status and status.groupRuntimeEvents or EMPTY_EVENTS
end

function GroupStatusRuntime.GetUnitlessEvents(frame, spec)
  return EMPTY_EVENTS
end

function GroupStatusRuntime.Update(frame, event, unit, seedHP)
  RunStatusRuntimeFrame(frame, event, unit, seedHP)
end

function GroupStatusRuntime.UpdateState(frame, event, unit, seedHP)
  local status = frame and frame._msufGFStatusRuntimeStatus or (frame and frame.MSUFSpec and frame.MSUFSpec.status)
  if not (status and status.runtimeStatusText == true) then return end
  BindStatusRuntime()
  if not UpdateStatusText then return end
  RunStatusText(frame, status, event, seedHP)
end

function GroupStatusRuntime.Apply(frame)
  local status = frame and frame.MSUFSpec and frame.MSUFSpec.status
  if frame then
    frame._msufUpdateGroupStatusState = nil
    frame._msufGFStatusRuntimeStatus = nil
    frame._msufGFStatusRuntimeDispatch = nil
  end
  if not status then
    ClearUnitlessRegistration(frame)
    return
  end
  if not StatusRuntimeReady(status) then
    ClearUnitlessRegistration(frame)
    return
  end
  SetUnitlessRegistration(frame, status)
  local dispatch = status.runtimeDispatch or CompileStatusDispatch(status)
  if frame then
    frame._msufGFStatusRuntimeStatus = status
    frame._msufGFStatusRuntimeDispatch = dispatch
    frame._msufUpdateGroupStatusState = RunStatusRuntimeFrame
  end
  dispatch.apply(frame, status, "MSUF_GF_STATUS_APPLY")
end

function GroupStatusRuntime.Disable(frame)
  if frame then
    ClearUnitlessRegistration(frame)
    frame._msufUpdateGroupStatusState = nil
    frame._msufGFStatusRuntimeStatus = nil
    frame._msufGFStatusRuntimeDispatch = nil
  end
end

UF.RegisterElement("GroupStatusRuntime", GroupStatusRuntime)
