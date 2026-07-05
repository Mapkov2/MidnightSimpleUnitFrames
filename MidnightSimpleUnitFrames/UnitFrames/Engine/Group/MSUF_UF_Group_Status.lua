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
local C_Timer = _G.C_Timer
local next = next
local type = type

local function ProfBegin(name)
  if MSUF and MSUF._profEnabled == true and MSUF.ProfBegin then
    return MSUF.ProfBegin(name)
  end
end

local function ProfEnd(name, token)
  if token and MSUF and MSUF.ProfEnd then
    MSUF.ProfEnd(name, token)
  end
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
  UNIT_FACTION = 9,
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
local UnitIsGhost = _G.UnitIsGhost
local UnitIsAFK = _G.UnitIsAFK
local UnitIsDND = _G.UnitIsDND
local issecretvalue = _G.issecretvalue or function(_) return false end
local IsUnitToken = UF.IsUnitToken
local ReadConnectedCached = UF.ReadConnectedCached
local ReadDeadCached = UF.ReadDeadCached

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

local function RunLeaderPairRaidGroup(frame, status)
  UpdateLeaderPair(frame, status)
  UpdateRaidGroup(frame, status)
end

local function RunRaidGroup(frame, status)
  UpdateRaidGroup(frame, status)
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

local function RunPhase(frame, status)
  UpdatePhase(frame, status)
end

local function StatusTextEventRelevant(cfg, event)
  if event == "UNIT_HEALTH" then
    return cfg.showDead == true or cfg.showGhost == true
  elseif event == "UNIT_CONNECTION" then
    return cfg.showDead == true
  elseif event == "UNIT_FLAGS" or event == "PLAYER_FLAGS_CHANGED" then
    return cfg.showDead == true or cfg.showGhost == true or cfg.showAFK == true or cfg.showDND == true
  end
  return true
end

--- Unit flag APIs may return secret values in restricted contexts. Return nil
--- instead of caching a derived key so the next unrestricted event can refresh.
local function SeedHealthDeadOverride(seedHP)
  if type(seedHP) ~= "number" then
    return nil
  end
  return seedHP <= 0
end

local function StatusTextFlagsKey(frame, cfg, seedHP)
  local unit = frame and frame.unit
  if not IsUnitToken(unit) then return nil end
  local healthDead = SeedHealthDeadOverride(seedHP)
  local state = frame and frame._msufUnitState
  local stateReady = state and state.ready == true
    and state.unit == unit
  local stateFresh = stateReady
    and frame._msufDispatchActive == true
    and state.dispatchToken == frame._msufDispatchToken
  local key = 0
  if healthDead ~= false and cfg.showGhost == true and UnitIsGhost then
    local ghost = UnitIsGhost(unit)
    if issecretvalue(ghost) == true then return nil end
    if ghost == true or ghost == 1 then key = key + 2 end
  end
  if cfg.showDead == true then
    if healthDead ~= nil then
      if healthDead == true then key = key + 4 end
    elseif stateFresh and state.deadKnown == true then
      if state.dead == true then key = key + 4 end
    else
      local dead, known = ReadDeadCached(frame, unit)
      if known ~= true then return nil end
      if dead == true then key = key + 4 end
    end
  end
  if cfg.showAFK == true and UnitIsAFK then
    local afk = UnitIsAFK(unit)
    if issecretvalue(afk) == true then return nil end
    if afk == true or afk == 1 then key = key + 8 end
  end
  if cfg.showDND == true and UnitIsDND then
    local dnd = UnitIsDND(unit)
    if issecretvalue(dnd) == true then return nil end
    if dnd == true or dnd == 1 then key = key + 16 end
  end
  return key
end

local function StatusTextConnectionKey(frame, cfg)
  local unit = frame and frame.unit
  if not IsUnitToken(unit) then return nil end
  local state = frame and frame._msufUnitState
  local stateReady = state and state.ready == true
    and state.unit == unit
  local stateFresh = stateReady
    and frame._msufDispatchActive == true
    and state.dispatchToken == frame._msufDispatchToken
  local key = 0
  if cfg.showDead == true and stateFresh and state.connectedKnown == true then
    if state.connected == false then key = key + 1 end
  elseif cfg.showDead == true then
    local connected, known = ReadConnectedCached(frame, unit)
    if known ~= true then return nil end
    if connected == false then key = key + 1 end
  end
  return key
end

local function StatusTextPollKey(frame, cfg)
  local unit = frame and frame.unit
  if not IsUnitToken(unit) then return nil end
  local state = frame and frame._msufUnitState
  local stateReady = state and state.ready == true
    and state.unit == unit
  local stateFresh = stateReady
    and frame._msufDispatchActive == true
    and state.dispatchToken == frame._msufDispatchToken
  local connection = 0
  local flags = 0
  if cfg.showDead == true then
    if stateFresh and state.connectedKnown == true then
      if state.connected == false then connection = 1 end
    else
      local connected, known = ReadConnectedCached(frame, unit)
      if known ~= true then return nil end
      if connected == false then connection = 1 end
    end
  end
  if cfg.showGhost == true and UnitIsGhost then
    local ghost = UnitIsGhost(unit)
    if issecretvalue(ghost) == true then return nil end
    if ghost == true or ghost == 1 then flags = flags + 2 end
  end
  if cfg.showDead == true then
    if stateFresh and state.deadKnown == true then
      if state.dead == true then flags = flags + 4 end
    else
      local dead, known = ReadDeadCached(frame, unit)
      if known ~= true then return nil end
      if dead == true then flags = flags + 4 end
    end
  end
  if cfg.showAFK == true and UnitIsAFK then
    local afk = UnitIsAFK(unit)
    if issecretvalue(afk) == true then return nil end
    if afk == true or afk == 1 then flags = flags + 8 end
  end
  if cfg.showDND == true and UnitIsDND then
    local dnd = UnitIsDND(unit)
    if issecretvalue(dnd) == true then return nil end
    if dnd == true or dnd == 1 then flags = flags + 16 end
  end
  return connection + (flags * 32)
end

--- Status text can be expensive because it combines connection, dead, ghost,
--- AFK, and DND flags. Build compact keys and skip repainting unchanged text.
local function StatusTextChanged(frame, status, event, seedHP)
  local cfg = status and status.statusText
  if not (cfg and cfg.enabled == true) then return true end
  if status.testMode == true then return true end
  if not StatusTextEventRelevant(cfg, event) then return false end
  local storeKey, key
  if event == "UNIT_HEALTH" then
    storeKey = "_msufGFStatusTextHealthKey"
    key = StatusTextFlagsKey(frame, cfg, seedHP)
  elseif event == "UNIT_CONNECTION" then
    storeKey = "_msufGFStatusTextConnectionKey"
    key = StatusTextConnectionKey(frame, cfg)
  elseif event == "UNIT_FLAGS" or event == "PLAYER_FLAGS_CHANGED" then
    storeKey = "_msufGFStatusTextFlagsKey"
    key = StatusTextFlagsKey(frame, cfg)
  elseif event == "MSUF_GF_STATUS_POLL" then
    storeKey = "_msufGFStatusTextPollKey"
    key = StatusTextPollKey(frame, cfg)
  else
    return true
  end
  if key == nil then return true end
  if frame[storeKey] == key then return false end
  frame[storeKey] = key
  return true
end

local function RunStatusText(frame, status, event, seedHP)
  if not StatusTextChanged(frame, status, event, seedHP) then
    return
  end
  UpdateStatusText(frame, status, event, seedHP)
end

local function RunStatusApply(frame, status, event)
  if status.runtimeRaidMarker == true then
    UpdateRaidMarker(frame, status)
  end
  if status.runtimeLeaderPair == true then
    UpdateLeaderPair(frame, status)
  end
  if status.role and status.role.enabled == true then
    UpdateRole(frame, status)
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
    frame._msufGFStatusTextConnectionKey = nil
    frame._msufGFStatusTextFlagsKey = nil
    frame._msufGFStatusTextHealthKey = nil
    frame._msufGFStatusTextPollKey = nil
    UpdateStatusText(frame, status, event)
  end
  if status.runtimePVP == true and UpdatePVP then
    UpdatePVP(frame, status)
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
  local runner = kind and dispatch[kind] or dispatch.apply
  if runner then
    runner(frame, status, event, seedHP)
  end
end

local unitlessDriver
local unitlessFramesByEvent = {}
local unitlessIndexByEvent = {}
local unitlessCountByEvent = {}
local unitlessRegistered = {}

local function EnsureUnitlessDriver()
  if unitlessDriver or not CreateFrame then
    return unitlessDriver
  end
  unitlessDriver = CreateFrame("Frame")
  unitlessDriver:SetScript("OnEvent", function(_, event)
    local list = unitlessFramesByEvent[event]
    if not list then
      return
    end
    local live = GF and GF.frames
    for i = 1, #list do
      local frame = list[i]
      if frame and (not live or live[frame] == true) then
        local active = frame._msufActiveElements
        if active and active.GroupStatusRuntime == true then
          RunStatusRuntimeFrame(frame, event)
        end
      end
    end
  end)
  return unitlessDriver
end

local function RefreshUnitlessDriverEvent(event)
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

local STATUS_POLL_INTERVAL = 0.5
local statusPollDriver
local statusPollTicker
local statusPollFrames = {}
local statusPollIndex = {}
local statusPollCount = 0

local function StatusPollCombatBlocked()
  return InCombatLockdown and InCombatLockdown()
end

local function RunStatusPollFrame(frame)
  local live = GF and GF.frames
  if not (frame and (not live or live[frame] == true)) then
    return
  end
  if frame.IsShown and not frame:IsShown() then
    return
  end
  local active = frame._msufActiveElements
  if not (active and active.GroupStatusRuntime == true) then
    return
  end
  local status = frame._msufGFStatusRuntimeStatus
  if not (status and status.runtimeStatusText == true) then
    return
  end
  RunStatusText(frame, status, "MSUF_GF_STATUS_POLL")
  local gone = frame._msufUpdateGroupVisualsGoneState
  if gone then
    gone(frame, "MSUF_GF_STATUS_POLL", frame.unit)
  end
end

local function RunStatusPollFrames()
  local profName = "group:statusPoll"
  local profToken = ProfBegin(profName)
  if StatusPollCombatBlocked() then
    ProfEnd(profName, profToken)
    return
  end
  for i = 1, #statusPollFrames do
    RunStatusPollFrame(statusPollFrames[i])
  end
  ProfEnd(profName, profToken)
end

--- PERF: the poll cadence runs on a C_Timer ticker instead of a per-frame
--- OnUpdate accumulator. The old driver ticked every render frame just to
--- count up to 0.5s; the ticker wakes exactly twice per second and is
--- cancelled entirely while in combat (regen events restart it).
local function RefreshStatusPollDriver()
  if statusPollCount > 0 and not StatusPollCombatBlocked() then
    if statusPollTicker then
      return
    end
    if C_Timer and C_Timer.NewTicker then
      statusPollTicker = C_Timer.NewTicker(STATUS_POLL_INTERVAL, RunStatusPollFrames)
    end
  elseif statusPollTicker then
    statusPollTicker:Cancel()
    statusPollTicker = nil
  end
end

local function EnsureStatusPollDriver()
  if statusPollDriver or not CreateFrame then
    return statusPollDriver
  end
  statusPollDriver = CreateFrame("Frame")
  statusPollDriver:Hide()
  statusPollDriver:RegisterEvent("PLAYER_REGEN_DISABLED")
  statusPollDriver:RegisterEvent("PLAYER_REGEN_ENABLED")
  statusPollDriver:SetScript("OnEvent", function(_, event)
    RefreshStatusPollDriver()
    if event == "PLAYER_REGEN_ENABLED" and statusPollCount > 0 then
      RunStatusPollFrames()
    end
  end)
  return statusPollDriver
end

local function AddStatusPollFrame(frame)
  if not frame or statusPollIndex[frame] then
    return
  end
  EnsureStatusPollDriver()
  local n = #statusPollFrames + 1
  statusPollFrames[n] = frame
  statusPollIndex[frame] = n
  statusPollCount = statusPollCount + 1
  RefreshStatusPollDriver()
end

local function RemoveStatusPollFrame(frame)
  local i = frame and statusPollIndex[frame]
  if not i then
    return
  end
  local last = #statusPollFrames
  local tail = statusPollFrames[last]
  statusPollFrames[i] = tail
  statusPollFrames[last] = nil
  statusPollIndex[frame] = nil
  if tail and tail ~= frame then
    statusPollIndex[tail] = i
  end
  statusPollCount = statusPollCount - 1
  RefreshStatusPollDriver()
end

local function SetStatusPollRegistration(frame, status)
  local cfg = status and status.statusText
  local want = status and status.runtimeStatusText == true
    and cfg and cfg.enabled == true
    and (cfg.showDead == true or cfg.showGhost == true)
  if want then
    AddStatusPollFrame(frame)
  else
    RemoveStatusPollFrame(frame)
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
    RemoveStatusPollFrame(frame)
    return
  end
  if not StatusRuntimeReady(status) then
    ClearUnitlessRegistration(frame)
    RemoveStatusPollFrame(frame)
    return
  end
  SetUnitlessRegistration(frame, status)
  SetStatusPollRegistration(frame, status)
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
    RemoveStatusPollFrame(frame)
    frame._msufUpdateGroupStatusState = nil
    frame._msufGFStatusRuntimeStatus = nil
    frame._msufGFStatusRuntimeDispatch = nil
  end
end

UF.RegisterElement("GroupStatusRuntime", GroupStatusRuntime)
