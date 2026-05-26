local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

local UF = MSUF.UF
local GF = MSUF.GF or {}
MSUF.GF = GF

if not (UF and UF.RegisterElement) then return end

local tonumber = tonumber

local UnitExists = UnitExists
local UnitIsConnected = UnitIsConnected
local UnitIsUnit = UnitIsUnit
local UnitInRange = UnitInRange
local InCombatLockdown = InCombatLockdown

local RANGE_EVENTS = {
    "UNIT_IN_RANGE_UPDATE", "UNIT_PHASE",
    "UNIT_CTR_OPTIONS", "UNIT_OTHER_PARTY_CHANGED",
}
local EMPTY_EVENTS = {}

local function UnitExistsSafe(unit)
    if not UnitExists then return unit ~= nil end
    local exists = UnitExists(unit)
    return exists == true or exists == 1
end

local function GroupSpec(frame)
    local spec = frame and frame.MSUFSpec
    return spec and spec.group
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

-- Hot-path event dispatch. Each branch handles exactly the indicators that
-- depend on that event; disabled indicators are skipped via per-key
-- `xxx.enabled == true` guards. The fall-through ONLY runs on initial
-- Apply (MSUF_GF_STATUS_APPLY) and updates every enabled indicator.
local function UpdateStatus(frame, event)
    local runtime = MSUF.UFStatusRuntime
    local status = frame and frame.MSUFSpec and frame.MSUFSpec.status
    if not (runtime and status) then return end
    if event == "RAID_TARGET_UPDATE" then
        if status.raidMarker and status.raidMarker.enabled == true then
            runtime.UpdateRaidMarker(frame, status)
        end
        return
    elseif event == "PARTY_LEADER_CHANGED" then
        runtime.UpdateLeaderPair(frame, status)
        return
    elseif event == "GROUP_ROSTER_UPDATE" then
        if (status.leader and status.leader.enabled == true)
            or (status.assist and status.assist.enabled == true) then
            runtime.UpdateLeaderPair(frame, status)
        end
        if status.raidGroup and status.raidGroup.enabled == true then
            runtime.UpdateRaidGroup(frame, status)
        end
        return
    elseif event == "READY_CHECK" or event == "READY_CHECK_CONFIRM" or event == "READY_CHECK_FINISHED" then
        runtime.UpdateReadyCheck(frame, status, event)
        return
    elseif event == "INCOMING_SUMMON_CHANGED" then
        runtime.UpdateSummon(frame, status)
        if status.incomingRes and status.incomingRes.enabled == true then
            runtime.UpdateIncomingRes(frame, status)
        end
        return
    elseif event == "INCOMING_RESURRECT_CHANGED" then
        if status.incomingRes and status.incomingRes.enabled == true then
            runtime.UpdateIncomingRes(frame, status)
        end
        return
    elseif event == "UNIT_PHASE" or event == "UNIT_OTHER_PARTY_CHANGED" then
        runtime.UpdatePhase(frame, status)
        return
    elseif event == "UNIT_HEALTH" or event == "UNIT_CONNECTION"
        or event == "UNIT_FLAGS" or event == "PLAYER_FLAGS_CHANGED" then
        if status.statusText and status.statusText.enabled == true then
            runtime.UpdateStatusText(frame, status)
        end
        return
    end
    -- Initial Apply (and any unrecognised event): refresh every enabled
    -- indicator so the frame's status state matches reality from the start.
    if status.raidMarker and status.raidMarker.enabled == true then
        runtime.UpdateRaidMarker(frame, status)
    end
    if (status.leader and status.leader.enabled == true)
        or (status.assist and status.assist.enabled == true) then
        runtime.UpdateLeaderPair(frame, status)
    end
    if status.role and status.role.enabled == true then
        runtime.UpdateRole(frame, status)
    end
    if status.readyCheck and status.readyCheck.enabled == true then
        runtime.UpdateReadyCheck(frame, status, event)
    end
    if status.summon and status.summon.enabled == true then
        runtime.UpdateSummon(frame, status)
    end
    if status.phase and status.phase.enabled == true then
        runtime.UpdatePhase(frame, status)
    end
    if status.incomingRes and status.incomingRes.enabled == true then
        runtime.UpdateIncomingRes(frame, status)
    end
    if status.raidGroup and status.raidGroup.enabled == true then
        runtime.UpdateRaidGroup(frame, status)
    end
    if status.statusText and status.statusText.enabled == true then
        runtime.UpdateStatusText(frame, status)
    end
end

function GroupStatusRuntime.Apply(frame)
    UpdateStatus(frame, "MSUF_GF_STATUS_APPLY")
end

function GroupStatusRuntime.Update(frame, event)
    UpdateStatus(frame, event)
end

UF.RegisterElement("GroupStatusRuntime", GroupStatusRuntime)

local GroupRangeFade = {}
local C_Timer = C_Timer

function GroupRangeFade.IsEnabled(frame, spec)
    return spec and spec.scope == "group" and spec.group
        and (spec.group.rangeFadeEnabled == true or spec.group.hideOfflineEnabled == true)
end

function GroupRangeFade.GetEvents()
    return RANGE_EVENTS
end

function GroupRangeFade.GetUnitlessEvents()
    return EMPTY_EVENTS
end

local function SafeBool(value)
    if value == true or value == 1 then
        return true
    end
    if value == false or value == 0 then
        return false
    end
    return nil
end

local function ClearRange(frame)
    if not frame then return end
    frame._msufGFRangeUnit = frame.unit
    frame._msufGFRangeKnown = nil
    frame._msufGFInRangeRaw = nil
end

local function ClearOfflineDelay(frame)
    if not frame then return end
    frame._msufGFOfflineDelayToken = (frame._msufGFOfflineDelayToken or 0) + 1
    frame._msufGFOfflineDelayUnit = nil
    frame._msufGFOfflineDelayReady = nil
end

local function StoreRange(frame, inRange)
    if not frame then return end
    frame._msufGFRangeUnit = frame.unit

    if type(inRange) == "nil" then
        frame._msufGFRangeKnown = nil
        frame._msufGFInRangeRaw = nil
        return
    end

    frame._msufGFRangeKnown = true
    frame._msufGFInRangeRaw = inRange
end

local function UnitIsPlayer(unit)
    if not (unit and unit ~= "") then
        return false
    end
    if unit == "player" then
        return true
    end
    if UnitIsUnit then
        local same = UnitIsUnit(unit, "player")
        return same == true or same == 1
    end
    return false
end

local function ResolveRangeValue(frame, unit, inRange)
    unit = unit or (frame and frame.unit)
    if UnitIsPlayer(unit) then
        return true
    end
    if type(inRange) ~= "nil" then
        return inRange
    end
    if UnitInRange and unit and unit ~= "" then
        return UnitInRange(unit)
    end
    return nil
end

local ApplyAlpha

local function SetAlphaCached(region, alpha, key)
    if region and region.SetAlpha and region[key] ~= alpha then
        region:SetAlpha(alpha)
        region[key] = alpha
    end
end

local function StatusTexture(bar)
    return bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture() or nil
end

local function SetStatusAlpha(bar, alpha, key)
    SetAlphaCached(bar, alpha, key)
    local tex = StatusTexture(bar)
    if tex and tex ~= bar then
        SetAlphaCached(tex, alpha, key .. "Tex")
    end
end

local function SetTextureAlpha(tex, alpha, key)
    SetAlphaCached(tex, alpha, key)
end

local function SetStatusAlphaFromBoolean(bar, value, inAlpha, outAlpha)
    local applied = false
    if bar and bar.SetAlphaFromBoolean then
        bar:SetAlphaFromBoolean(value, inAlpha, outAlpha)
        applied = true
    end
    local tex = StatusTexture(bar)
    if tex and tex.SetAlphaFromBoolean then
        tex:SetAlphaFromBoolean(value, inAlpha, outAlpha)
        applied = true
    end
    return applied
end

local function SetTextureAlphaFromBoolean(tex, value, inAlpha, outAlpha)
    if tex and tex.SetAlphaFromBoolean then
        tex:SetAlphaFromBoolean(value, inAlpha, outAlpha)
        return true
    end
    return false
end

local function RefreshHealthVisual(frame)
    local element = UF.elements and UF.elements.GroupVisuals
    if frame and frame._msufActiveElements and frame._msufActiveElements.GroupVisuals == true and element and element.Update then
        element.Update(frame, "MSUF_GF_RANGE_ALPHA", frame.unit)
        return true
    end
    return false
end

local function ApplyHealthRangeAlpha(frame, alpha)
    alpha = tonumber(alpha) or 1
    frame._msufGFRangeHealthAlpha = alpha
    local refreshed = RefreshHealthVisual(frame)
    if not refreshed then
        SetStatusAlpha(frame.hpBar or frame.Health, alpha, "_msufGFRangeHealth")
        SetTextureAlpha(frame.bg, alpha, "_msufGFRangeHealthBg")
        SetTextureAlpha(frame.hpBarBG, alpha, "_msufGFRangeHealthBg")
    end
    SetStatusAlpha(frame.incomingHealBar, alpha, "_msufGFRangePredict")
    SetStatusAlpha(frame.absorbBar, alpha, "_msufGFRangePredict")
    SetStatusAlpha(frame.healAbsorbBar, alpha, "_msufGFRangePredict")
end

local function ApplyHealthRangeAlphaFromBoolean(frame, value, inAlpha, outAlpha)
    frame._msufGFRangeHealthAlpha = nil
    local applied = SetStatusAlphaFromBoolean(frame.hpBar or frame.Health, value, inAlpha, outAlpha)
    applied = SetTextureAlphaFromBoolean(frame.bg, value, inAlpha, outAlpha) or applied
    applied = SetTextureAlphaFromBoolean(frame.hpBarBG, value, inAlpha, outAlpha) or applied
    applied = SetStatusAlphaFromBoolean(frame.incomingHealBar, value, inAlpha, outAlpha) or applied
    applied = SetStatusAlphaFromBoolean(frame.absorbBar, value, inAlpha, outAlpha) or applied
    applied = SetStatusAlphaFromBoolean(frame.healAbsorbBar, value, inAlpha, outAlpha) or applied
    return applied
end

local function CoreAlpha(frame)
    local spec = frame and frame.MSUFSpec
    local alpha = spec and spec.alpha
    if alpha and alpha.active == true then
        local element = UF.elements and UF.elements.Alpha
        if frame._msufAlphaEffective == nil and element and element.Apply then
            element.Apply(frame, spec)
        end
        return tonumber(frame._msufAlphaEffective) or 1
    end
    return 1
end

local function OfflineHideReady(frame, cfg)
    local delay = tonumber(cfg and cfg.hideOfflineDelay) or 0
    if delay <= 0 or not (C_Timer and C_Timer.After) then
        return true
    end
    local unit = frame and frame.unit
    if frame._msufGFOfflineDelayUnit == unit and frame._msufGFOfflineDelayReady == true then
        return true
    end
    if frame._msufGFOfflineDelayUnit == unit and frame._msufGFOfflineDelayPending == true then
        return false
    end

    local token = (frame._msufGFOfflineDelayToken or 0) + 1
    frame._msufGFOfflineDelayToken = token
    frame._msufGFOfflineDelayUnit = unit
    frame._msufGFOfflineDelayPending = true
    frame._msufGFOfflineDelayReady = nil

    C_Timer.After(delay, function()
        if not frame or frame._msufGFOfflineDelayToken ~= token or frame.unit ~= unit then
            return
        end
        frame._msufGFOfflineDelayPending = nil
        frame._msufGFOfflineDelayReady = true
        if ApplyAlpha then
            ApplyAlpha(frame)
        end
    end)
    return false
end

local function BaseAlpha(frame)
    local cfg = GroupSpec(frame)
    if not cfg then return 1, false end
    local unit = frame.unit
    if frame._msufGFRangeUnit ~= unit then
        ClearRange(frame)
    end
    local base = CoreAlpha(frame)
    local connected = UnitIsConnected and unit and UnitExistsSafe(unit) and UnitIsConnected(unit)
    if connected == false or connected == 0 then
        if cfg.hideOfflineEnabled == true and (not (InCombatLockdown and InCombatLockdown()) or cfg.hideOfflineInCombat == true) then
            if OfflineHideReady(frame, cfg) then
                return 0, true
            end
        end
        return base * (cfg.offlineAlpha or 0.5), true
    end
    ClearOfflineDelay(frame)
    return base, false
end

function ApplyAlpha(frame)
    local cfg = GroupSpec(frame)
    local baseAlpha, baseLocked = BaseAlpha(frame)
    if baseLocked == true then
        ApplyHealthRangeAlpha(frame, 1)
        frame:SetAlpha(baseAlpha)
        return
    end

    if cfg and cfg.rangeFadeEnabled == true and frame._msufGFRangeKnown == true then
        local inRange = frame._msufGFInRangeRaw
        if cfg.rangeFadeLayerMode == "health" then
            frame:SetAlpha(baseAlpha)
            local rangeAlpha = cfg.rangeFadeAlpha or 0.4
            if type(inRange) ~= "nil" and ApplyHealthRangeAlphaFromBoolean(frame, inRange, 1, rangeAlpha) then
                return
            end
            local safe = SafeBool(inRange)
            if safe ~= nil then
                ApplyHealthRangeAlpha(frame, safe and 1 or rangeAlpha)
                return
            end
            ApplyHealthRangeAlpha(frame, 1)
            return
        end
        ApplyHealthRangeAlpha(frame, 1)
        if frame.SetAlphaFromBoolean and type(inRange) ~= "nil" then
            frame:SetAlphaFromBoolean(inRange, baseAlpha, baseAlpha * (cfg.rangeFadeAlpha or 0.4))
            return
        end

        local safe = SafeBool(inRange)
        if safe ~= nil then
            frame:SetAlpha(baseAlpha * (safe and 1 or (cfg.rangeFadeAlpha or 0.4)))
            return
        end
    end

    ApplyHealthRangeAlpha(frame, 1)
    frame:SetAlpha(baseAlpha)
end

function GroupRangeFade.Apply(frame)
    StoreRange(frame, ResolveRangeValue(frame, frame and frame.unit, nil))
    ApplyAlpha(frame)
end

function GroupRangeFade.Update(frame, event, unit, inRange)
    -- The core dispatcher already routes UNIT_EVENT_HAS_UNIT events to the
    -- frame whose .unit matches the event's unit, so unit-vs-frame matching
    -- is a no-op here in the normal path. We still tolerate a mismatching
    -- unit (defensive).
    if event == "UNIT_IN_RANGE_UPDATE" then
        if not unit or unit == "" or unit == frame.unit then
            StoreRange(frame, ResolveRangeValue(frame, unit or frame.unit, inRange))
        end
    elseif event == "UNIT_PHASE" or event == "UNIT_CTR_OPTIONS" or event == "UNIT_OTHER_PARTY_CHANGED" then
        if not unit or unit == "" or unit == frame.unit then
            StoreRange(frame, ResolveRangeValue(frame, unit or frame.unit, nil))
        end
    end
    ApplyAlpha(frame)
end

function GroupRangeFade.Disable(frame)
    ClearRange(frame)
    ApplyHealthRangeAlpha(frame, 1)
    if frame and frame.SetAlpha then
        frame:SetAlpha(CoreAlpha(frame))
    end
end

UF.RegisterElement("GroupRangeFade", GroupRangeFade)
