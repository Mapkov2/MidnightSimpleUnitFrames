local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

local UF = MSUF.UF
local GF = MSUF.GF or {}
MSUF.GF = GF

if not (UF and UF.RegisterElement) then return end

local CreateFrame = _G.CreateFrame
local next = next

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
  return UpdateStatusText ~= nil
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
    return false
  elseif event == "UNIT_CONNECTION" then
    return cfg.showDead == true
  elseif event == "UNIT_FLAGS" or event == "PLAYER_FLAGS_CHANGED" then
    return cfg.showDead == true or cfg.showGhost == true or cfg.showAFK == true or cfg.showDND == true
  end
  return true
end

local function StatusTextFlagsKey(frame, cfg)
  local unit = frame and frame.unit
  if not IsUnitToken(unit) then return nil end
  local state = frame and frame._msufUnitState
  local stateReady = state and state.ready == true
    and state.unit == unit
  local stateFresh = stateReady
    and frame._msufDispatchActive == true
    and state.dispatchToken == frame._msufDispatchToken
  local key = 0
  if cfg.showGhost == true and UnitIsGhost then
    local ghost = UnitIsGhost(unit)
    if issecretvalue(ghost) == true then return nil end
    if ghost == true or ghost == 1 then key = key + 2 end
  end
  if cfg.showDead == true then
    if stateFresh and state.deadKnown == true then
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

local function StatusTextChanged(frame, status, event)
  local cfg = status and status.statusText
  if not (cfg and cfg.enabled == true) then return true end
  if status.testMode == true then return true end
  if not StatusTextEventRelevant(cfg, event) then return false end
  local storeKey, key
  if event == "UNIT_HEALTH" then
    return false
  elseif event == "UNIT_CONNECTION" then
    storeKey = "_msufGFStatusTextConnectionKey"
    key = StatusTextConnectionKey(frame, cfg)
  elseif event == "UNIT_FLAGS" or event == "PLAYER_FLAGS_CHANGED" then
    storeKey = "_msufGFStatusTextFlagsKey"
    key = StatusTextFlagsKey(frame, cfg)
  else
    return true
  end
  if key == nil then return true end
  if frame[storeKey] == key then return false end
  frame[storeKey] = key
  return true
end

local function RunStatusText(frame, status, event)
  if not StatusTextChanged(frame, status, event) then
    return
  end
  UpdateStatusText(frame, status, event)
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
    UpdateStatusText(frame, status, event)
  end
  if status.runtimePVP == true and UpdatePVP then
    UpdatePVP(frame, status)
  end
end

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

local function RunStatusRuntimeFrame(frame, event)
  local status = frame and frame._msufGFStatusRuntimeStatus
  local dispatch = frame and frame._msufGFStatusRuntimeDispatch
  if not (status and dispatch) then
    status = frame and frame.MSUFSpec and frame.MSUFSpec.status
    if not status then return end
    if (not UpdateStatusText or not UpdateRole or (status.runtimePVP == true and not UpdatePVP)) and not BindStatusRuntime() then return end
    dispatch = status.runtimeDispatch or CompileStatusDispatch(status)
  end
  local kind = STATUS_EVENT_KIND[event]
  local runner = kind and dispatch[kind] or dispatch.apply
  if runner then
    runner(frame, status, event)
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

function GroupStatusRuntime.Update(frame, event)
  RunStatusRuntimeFrame(frame, event)
end

function GroupStatusRuntime.UpdateState(frame, event)
  local status = frame and frame._msufGFStatusRuntimeStatus or (frame and frame.MSUFSpec and frame.MSUFSpec.status)
  if not (status and status.runtimeStatusText == true) then return end
  if not UpdateStatusText and not BindStatusRuntime() then return end
  RunStatusText(frame, status, event)
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
  if (not UpdateStatusText or not UpdateRole or (status.runtimePVP == true and not UpdatePVP)) and not BindStatusRuntime() then
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
