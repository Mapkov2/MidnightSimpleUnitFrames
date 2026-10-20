-- UF responsibility owner; dependencies bind once before runtime.
local _, MSUF = ...
MSUF.UFModuleFactories = MSUF.UFModuleFactories or {}

MSUF.UFModuleFactories.StatusGroupRuntime = function(
  UpdatePowerRoleVisibility, ApplyRoleTexture, ApplyStatusIconPackTexture, C_IncomingSummon, C_Timer, FreshUnitState, GetRaidRosterInfo,
    GetReadyCheckStatus, GetTime, InCombatLockdown, MSUF, Media, ReadUnitIsPlayerCached, ReadyCheckQueue, Runtime, SUMMON_TEXTURES,
    SafeNumber, SetShown, SetTexCoord, SetText, SetTexture, UnitExistsRuntime, UnitGroupRolesAssigned, UnitInRaid, UnitIsPlayerRuntime,
    UnitPhaseReason, issecretvalue, tostring, type
)

local function CancelReadyCheckTimer(frame)
  if frame then
    ReadyCheckQueue.timers[frame] = nil
  end
end

local ReadyCheckTimerCallback
local Scheduler = MSUF.Scheduler

-- One scheduler key; each arm replaces its deadline.
local function ArmReadyCheckTimer(when)
  if ReadyCheckQueue.timerAt and ReadyCheckQueue.timerAt <= when then return end
  ReadyCheckQueue.timerAt = when
  Scheduler.ScheduleAt("MSUF_READY_CHECK_HIDE", when, ReadyCheckTimerCallback)
end

ReadyCheckTimerCallback = function()
  -- Ready-check icons share one compact timer queue instead of one timer per frame. The
  -- callback compacts sparse slots so raid-size checks do not leave long-lived table holes.
  ReadyCheckQueue.timerAt = nil
  local now = GetTime and GetTime() or 0
  local nextAt
  local out = ReadyCheckQueue.head
  local last = ReadyCheckQueue.tail

  for i = ReadyCheckQueue.head, last do
    local frame = ReadyCheckQueue.list[i]
    local due = frame and ReadyCheckQueue.timers[frame]
    if not due then
      ReadyCheckQueue.list[i] = nil
    elseif now >= due then
      ReadyCheckQueue.timers[frame] = nil
      ReadyCheckQueue.list[i] = nil
      SetShown(frame.readyCheckIcon, false)
    else
      if out ~= i then
        ReadyCheckQueue.list[out] = frame
        ReadyCheckQueue.list[i] = nil
      end
      out = out + 1
      if not nextAt or due < nextAt then nextAt = due end
    end
  end

  local appendedTail = ReadyCheckQueue.tail
  if appendedTail > last then
    for i = last + 1, appendedTail do
      local frame = ReadyCheckQueue.list[i]
      local due = frame and ReadyCheckQueue.timers[frame]
      if due then
        if out ~= i then
          ReadyCheckQueue.list[out] = frame
          ReadyCheckQueue.list[i] = nil
        end
        out = out + 1
        if not nextAt or due < nextAt then nextAt = due end
      else
        ReadyCheckQueue.list[i] = nil
      end
    end
  end

  ReadyCheckQueue.head = 1
  ReadyCheckQueue.tail = out - 1
  if ReadyCheckQueue.tail <= 0 then
    ReadyCheckQueue.tail = 0
  end
  if nextAt then
    ArmReadyCheckTimer(nextAt)
  end
end

local function QueueReadyCheckHide(frame)
  if not frame then return end
  local now = GetTime and GetTime() or 0
  local due = now + 6
  local known = ReadyCheckQueue.timers[frame] ~= nil
  ReadyCheckQueue.timers[frame] = due
  if not known then
    ReadyCheckQueue.tail = ReadyCheckQueue.tail + 1
    ReadyCheckQueue.list[ReadyCheckQueue.tail] = frame
  end
  ArmReadyCheckTimer(due)
end

function Runtime.UpdateRole(frame, status)
  local cfg = status and status.role
  local tex = frame and frame.roleIcon
  local unit = frame and frame.MSUFUnitKey
  local unitState = FreshUnitState(frame, unit)
  local exists = UnitExistsRuntime(unit, unitState, frame)
  local role
  if UnitGroupRolesAssigned and unit then role = UnitGroupRolesAssigned(unit) end
  if issecretvalue(role) == true then role = nil end
  if role == "NONE" then role = nil end
  if frame and frame._msufIsGroupFrame and InCombatLockdown and InCombatLockdown() then
    local gf = MSUF and MSUF.GF
    local refresh = gf and gf.RefreshFrameRoleOverlay
    if refresh then
      local oldRole = status and status.roleValue
      if issecretvalue(oldRole) == true then oldRole = nil end
      if gf.NormalizeGroupRole(oldRole) ~= gf.NormalizeGroupRole(role) then
        refresh(frame)
      end
    end
  end
  if status then status.roleValue = role end
  UpdatePowerRoleVisibility(frame, status)

  if not (cfg and cfg.enabled and tex and exists and role) then
    SetShown(tex, false)
    return
  end
  if (role == "TANK" and cfg.showTank == false)
    or (role == "HEALER" and cfg.showHealer == false)
    or (role == "DAMAGER" and cfg.showDPS == false) then
    SetShown(tex, false)
    return
  end
  if ApplyRoleTexture(tex, cfg, status, role) then
    SetShown(tex, true)
  else
    SetShown(tex, false)
  end
end

function Runtime.UpdateReadyCheck(frame, status, event)
  local cfg = status and status.readyCheck
  local tex = frame and frame.readyCheckIcon
  local unit = frame and frame.MSUFUnitKey
  if not (cfg and cfg.enabled and tex and unit) then
    SetShown(tex, false)
    CancelReadyCheckTimer(frame)
    return
  end

  local ready = GetReadyCheckStatus and GetReadyCheckStatus(unit)
  local texture = Media.READY_TEXTURES[ready]
  if texture then
    CancelReadyCheckTimer(frame)
    if not ApplyStatusIconPackTexture(tex, cfg, status, "readyCheck", ready) then
      SetTexture(tex, texture)
      SetTexCoord(tex, 0, 1, 0, 1)
    end
    SetShown(tex, true)
  elseif event == "READY_CHECK_FINISHED" and tex.IsShown and tex:IsShown() then
    -- Blizzard leaves ready-check result icons visible briefly after finish; queue a delayed
    -- hide so MSUF matches that readable window without polling.
    QueueReadyCheckHide(frame)
  else
    SetShown(tex, false)
  end
end

function Runtime.UpdateSummon(frame, status)
  local cfg = status and status.summon
  local tex = frame and frame.summonIcon
  local unit = frame and frame.MSUFUnitKey
  if not (cfg and cfg.enabled and tex and unit) then
    SetShown(tex, false)
    if frame then frame._msufGFSummonActive = false end
    return
  end
  local summonStatus
  if C_IncomingSummon and C_IncomingSummon.IncomingSummonStatus then
    summonStatus = C_IncomingSummon.IncomingSummonStatus(unit)
  end
  if issecretvalue(summonStatus) == true then
    -- Summon status can be restricted; an unknown value means hide the icon, not inspect it.
    summonStatus = nil
  end
  local texture = summonStatus and SUMMON_TEXTURES[summonStatus]
  if texture then
    if not ApplyStatusIconPackTexture(tex, cfg, status, "summon", summonStatus) then
      SetTexture(tex, texture)
      SetTexCoord(tex, 0, 1, 0, 1)
    end
    SetShown(tex, true)
    frame._msufGFSummonActive = true
  else
    SetShown(tex, false)
    frame._msufGFSummonActive = false
  end
end

function Runtime.UpdatePhase(frame, status)
  local cfg = status and status.phase
  local tex = frame and frame.phaseIcon
  local unit = frame and frame.MSUFUnitKey
  if not (cfg and cfg.enabled and tex and unit) then
    SetShown(tex, false)
    return
  end
  local reason
  local unitState = FreshUnitState(frame, unit)
  local isPlayer = UnitIsPlayerRuntime(unit, unitState, frame)
  if isPlayer == true and UnitPhaseReason then
    reason = UnitPhaseReason(unit)
  end
  if issecretvalue(reason) ~= true and reason then
    if not ApplyStatusIconPackTexture(tex, cfg, status, "phase", reason) then
      SetTexture(tex, Media.PHASE_TEXTURE)
      SetTexCoord(tex, 0, 1, 0, 1)
    end
    SetShown(tex, true)
  else
    SetShown(tex, false)
  end
end

local function RaidGroupText(style, subgroup)
  if style == "BRACKET" then
    return "[" .. subgroup .. "]"
  elseif style == "NONE" then
    return tostring(subgroup)
  end
  return "(" .. subgroup .. ")"
end

--- A secure raid header's unit token already encodes the roster index
--- ("raid7" -> 7), so the group-frame case resolves without an API call and
--- without depending on UnitInRaid resolving that token. UnitInRaid stays as
--- the fallback for party tokens and for target/focus unit frames.
local RAID_TOKEN_INDEX = {}
for i = 1, 40 do RAID_TOKEN_INDEX["raid" .. i] = i end

function Runtime.UpdateRaidGroup(frame, status)
  local cfg = status and status.raidGroup
  local fs = frame.raidGroupNameText
  local unit = frame.MSUFUnitKey
  local unitState = FreshUnitState(frame, unit)
  local exists = UnitExistsRuntime(unit, unitState, frame)
  if not (cfg and cfg.enabled and fs and GetRaidRosterInfo and exists) then
    SetShown(fs, false)
    return
  end
  local index = RAID_TOKEN_INDEX[unit]
  if not index then
    -- Only a PLAYER can be in the raid roster, so a mob target never needs the
    -- roster lookup at all; this keeps rapid target-swaps over mobs cheap.
    local isPlayer, isPlayerKnown = ReadUnitIsPlayerCached(frame, unit)
    if isPlayerKnown == true and isPlayer ~= true then
      SetShown(fs, false)
      return
    end
    index = UnitInRaid and SafeNumber(UnitInRaid(unit)) or nil
  end
  local subgroup
  if index then
    local _, _, sg = GetRaidRosterInfo(index)
    if type(sg) == "number" and sg > 0 then
      subgroup = sg
    end
  end
  local serial = frame._msufStatusIndicatorSerial
    or (frame.MSUFSpec and frame.MSUFSpec._msufGFCompileSerial)
    or 0
  if frame._msufRaidGroupSubgroup == subgroup
    and frame._msufRaidGroupSerial == serial
    and frame._msufRaidGroupStyle == cfg.style
    and fs._msufShown == (subgroup ~= nil) then
    return
  end
  frame._msufRaidGroupSubgroup = subgroup
  frame._msufRaidGroupSerial = serial
  frame._msufRaidGroupStyle = cfg.style
  if subgroup then
    SetText(fs, RaidGroupText(cfg.style, subgroup))
    SetShown(fs, true)
  else
    SetShown(fs, false)
  end
end

return CancelReadyCheckTimer, RaidGroupText
end
