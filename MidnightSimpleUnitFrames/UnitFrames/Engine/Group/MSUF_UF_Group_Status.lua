local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

local UF = MSUF.UF
local GF = MSUF.GF or {}
MSUF.GF = GF

if not (UF and UF.RegisterElement) then return end

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
local UnitIsConnected = _G.UnitIsConnected
local UnitIsGhost = _G.UnitIsGhost
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local UnitIsAFK = _G.UnitIsAFK
local UnitIsDND = _G.UnitIsDND
local Secrets = MSUF.Secrets or {}
local IsSecret = Secrets.IsSecret or function(_) return false end

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

local function RunPhase(frame, status)
    UpdatePhase(frame, status)
end

local function StatusTextEventRelevant(cfg, event)
    if event == "UNIT_HEALTH" then
        return cfg.showDead == true or cfg.showGhost == true
    elseif event == "UNIT_CONNECTION" then
        return cfg.showDead == true
    elseif event == "UNIT_FLAGS" or event == "PLAYER_FLAGS_CHANGED" then
        return cfg.showAFK == true or cfg.showDND == true
    end
    return true
end

local function StatusTextHealthKey(frame, cfg)
    local unit = frame and frame.unit
    if not unit then return nil end
    local key = 0
    if cfg.showGhost == true and UnitIsGhost then
        local ghost = UnitIsGhost(unit)
        if IsSecret(ghost) then return nil end
        if ghost == true or ghost == 1 then key = key + 2 end
    end
    if cfg.showDead == true and UnitIsDeadOrGhost then
        local dead = UnitIsDeadOrGhost(unit)
        if IsSecret(dead) then return nil end
        if dead == true or dead == 1 then key = key + 4 end
    end
    return key
end

local function StatusTextConnectionKey(frame, cfg)
    local unit = frame and frame.unit
    if not unit then return nil end
    local key = 0
    if cfg.showDead == true and UnitIsConnected then
        local connected = UnitIsConnected(unit)
        if IsSecret(connected) then return nil end
        if connected == false or connected == 0 then key = key + 1 end
    end
    return key
end

local function StatusTextFlagsKey(frame, cfg)
    local unit = frame and frame.unit
    if not unit then return nil end
    local key = 0
    if cfg.showAFK == true and UnitIsAFK then
        local afk = UnitIsAFK(unit)
        if IsSecret(afk) then return nil end
        if afk == true or afk == 1 then key = key + 8 end
    end
    if cfg.showDND == true and UnitIsDND then
        local dnd = UnitIsDND(unit)
        if IsSecret(dnd) then return nil end
        if dnd == true or dnd == 1 then key = key + 16 end
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
        storeKey = "_msufGFStatusTextHealthKey"
        key = StatusTextHealthKey(frame, cfg)
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
        frame._msufGFStatusTextHealthKey = nil
        frame._msufGFStatusTextConnectionKey = nil
        frame._msufGFStatusTextFlagsKey = nil
        UpdateStatusText(frame, status, event)
    end
end

local function CompileStatusDispatch(status)
    local dispatch = status and status._msufGroupRuntimeDispatch
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
    dispatch.apply = RunStatusApply
    status._msufGroupRuntimeDispatch = dispatch
    return dispatch
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
    local status = spec and spec.status
    return status and status.groupRuntimeUnitlessEvents or EMPTY_EVENTS
end

function GroupStatusRuntime.Update(frame, event)
    local status = frame and frame.MSUFSpec and frame.MSUFSpec.status
    if not status then return end
    local kind = STATUS_EVENT_KIND[event]
    if kind == 8 then
        if status.runtimeStatusText ~= true or not StatusTextChanged(frame, status, event) then
            return
        end
        if not UpdateStatusText and not BindStatusRuntime() then return end
        UpdateStatusText(frame, status, event)
        return
    end
    if (not UpdateStatusText or not UpdateRole) and not BindStatusRuntime() then return end
    local dispatch = CompileStatusDispatch(status)
    local runner = kind and dispatch[kind] or dispatch.apply
    if runner then
        runner(frame, status, event)
    end
end

function GroupStatusRuntime.Apply(frame)
    local status = frame and frame.MSUFSpec and frame.MSUFSpec.status
    if not status then return end
    if (not UpdateStatusText or not UpdateRole) and not BindStatusRuntime() then return end
    local dispatch = CompileStatusDispatch(status)
    dispatch.apply(frame, status, "MSUF_GF_STATUS_APPLY")
end

UF.RegisterElement("GroupStatusRuntime", GroupStatusRuntime)
