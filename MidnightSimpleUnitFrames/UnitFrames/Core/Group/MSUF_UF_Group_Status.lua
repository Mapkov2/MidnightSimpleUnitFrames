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
local issecretvalue = _G.issecretvalue

local RANGE_EVENTS = {
    "UNIT_IN_RANGE_UPDATE", "UNIT_PHASE",
    "UNIT_CTR_OPTIONS", "UNIT_OTHER_PARTY_CHANGED",
}
local OFFLINE_EVENTS = { "UNIT_CONNECTION" }
local RANGE_OFFLINE_EVENTS = {
    "UNIT_IN_RANGE_UPDATE", "UNIT_PHASE",
    "UNIT_CTR_OPTIONS", "UNIT_OTHER_PARTY_CHANGED",
    "UNIT_CONNECTION",
}
local EMPTY_EVENTS = {}
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
function GroupStatusRuntime.Update(frame, event)
    local status = frame and frame.MSUFSpec and frame.MSUFSpec.status
    if not status then return end
    if (not UpdateStatusText or not UpdateRole) and not BindStatusRuntime() then return end
    local kind = STATUS_EVENT_KIND[event]
    if kind == 1 then
        if status.runtimeRaidMarker == true then
            UpdateRaidMarker(frame, status)
        end
        return
    elseif kind == 2 then
        UpdateLeaderPair(frame, status)
        return
    elseif kind == 3 then
        if status.runtimeLeaderPair == true then
            UpdateLeaderPair(frame, status)
        end
        if status.runtimeRaidGroup == true then
            UpdateRaidGroup(frame, status)
        end
        return
    elseif kind == 4 then
        UpdateReadyCheck(frame, status, event)
        return
    elseif kind == 5 then
        UpdateSummon(frame, status)
        if status.runtimeIncomingRes == true then
            UpdateIncomingRes(frame, status)
        end
        return
    elseif kind == 6 then
        if status.runtimeIncomingRes == true then
            UpdateIncomingRes(frame, status)
        end
        return
    elseif kind == 7 then
        UpdatePhase(frame, status)
        return
    elseif kind == 8 then
        if status.runtimeStatusText == true then
            UpdateStatusText(frame, status, event)
        end
        return
    end
    -- Initial Apply (and any unrecognised event): refresh every enabled
    -- indicator so the frame's status state matches reality from the start.
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
        UpdateStatusText(frame, status, event)
    end
end

function GroupStatusRuntime.Apply(frame)
    GroupStatusRuntime.Update(frame, "MSUF_GF_STATUS_APPLY")
end

UF.RegisterElement("GroupStatusRuntime", GroupStatusRuntime)

local GroupRangeFade = {}
local C_Timer = C_Timer

function GroupRangeFade.IsEnabled(frame, spec)
    return spec and spec.scope == "group" and spec.group
        and (spec.group.rangeFadeEnabled == true or spec.group.hideOfflineEnabled == true)
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
    frame._msufGFRangeCacheable = nil
end

local function ClearOfflineDelay(frame)
    if not frame then return end
    frame._msufGFOfflineDelayToken = (frame._msufGFOfflineDelayToken or 0) + 1
    frame._msufGFOfflineDelayUnit = nil
    frame._msufGFOfflineDelayReady = nil
end

local function StoreRange(frame, inRange)
    if not frame then return false end
    local unit = frame.unit
    local unitChanged = frame._msufGFRangeUnit ~= unit
    frame._msufGFRangeUnit = frame.unit

    if type(inRange) == "nil" then
        if not unitChanged and frame._msufGFRangeKnown == nil and frame._msufGFInRangeRaw == nil then
            return false
        end
        frame._msufGFRangeKnown = nil
        frame._msufGFInRangeRaw = nil
        frame._msufGFRangeCacheable = nil
        return true
    end

    local cacheable = not (issecretvalue and issecretvalue(inRange))
    if cacheable and not unitChanged and frame._msufGFRangeCacheable == true
        and frame._msufGFRangeKnown == true and frame._msufGFInRangeRaw == inRange then
        return false
    end

    frame._msufGFRangeKnown = true
    frame._msufGFInRangeRaw = inRange
    frame._msufGFRangeCacheable = cacheable and true or nil
    return true
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

function GroupRangeFade.GetEvents(frame, spec)
    local cfg = spec and spec.group
    local range = cfg and cfg.rangeFadeEnabled == true
    local offline = cfg and cfg.hideOfflineEnabled == true
    if range and offline then
        return RANGE_OFFLINE_EVENTS
    elseif range then
        return RANGE_EVENTS
    elseif offline then
        return OFFLINE_EVENTS
    end
    return EMPTY_EVENTS
end

local ApplyAlpha

local function SetAlphaCached(region, alpha, key)
    if region and region.SetAlpha and region[key] ~= alpha then
        region:SetAlpha(alpha)
        region[key] = alpha
    end
end

local function ClearAlphaCaches(frame)
    if not frame then return end
    frame._msufGFRangeFrameAlpha = nil
    frame._msufGFRangeHealthAlpha = nil
    frame._msufGFRangeHealthBool = nil
    frame._msufGFRangeHealthBoolIn = nil
    frame._msufGFRangeHealthBoolOut = nil
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
    if frame._msufGFRangeHealthAlpha == alpha and frame._msufGFRangeHealthBool == nil then
        return
    end
    frame._msufGFRangeHealthAlpha = alpha
    frame._msufGFRangeHealthBool = nil
    frame._msufGFRangeHealthBoolIn = nil
    frame._msufGFRangeHealthBoolOut = nil
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
    local cacheable = not (issecretvalue and issecretvalue(value))
    if cacheable
        and frame._msufGFRangeHealthBool == value
        and frame._msufGFRangeHealthBoolIn == inAlpha
        and frame._msufGFRangeHealthBoolOut == outAlpha then
        return true
    end
    frame._msufGFRangeHealthAlpha = nil
    local applied = SetStatusAlphaFromBoolean(frame.hpBar or frame.Health, value, inAlpha, outAlpha)
    applied = SetTextureAlphaFromBoolean(frame.bg, value, inAlpha, outAlpha) or applied
    applied = SetTextureAlphaFromBoolean(frame.hpBarBG, value, inAlpha, outAlpha) or applied
    applied = SetStatusAlphaFromBoolean(frame.incomingHealBar, value, inAlpha, outAlpha) or applied
    applied = SetStatusAlphaFromBoolean(frame.absorbBar, value, inAlpha, outAlpha) or applied
    applied = SetStatusAlphaFromBoolean(frame.healAbsorbBar, value, inAlpha, outAlpha) or applied
    if applied and cacheable then
        frame._msufGFRangeHealthBool = value
        frame._msufGFRangeHealthBoolIn = inAlpha
        frame._msufGFRangeHealthBoolOut = outAlpha
    else
        frame._msufGFRangeHealthBool = nil
        frame._msufGFRangeHealthBoolIn = nil
        frame._msufGFRangeHealthBoolOut = nil
    end
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
    local spec = frame and frame.MSUFSpec
    local cfg = spec and spec.group
    if not cfg then return 1, false end
    local unit = frame.unit
    if frame._msufGFRangeUnit ~= unit then
        ClearRange(frame)
    end
    local base = CoreAlpha(frame)
    local exists = unit ~= nil
    if UnitExists then
        local existsRaw = UnitExists(unit)
        exists = existsRaw == true or existsRaw == 1
    end
    local connected = UnitIsConnected and exists and UnitIsConnected(unit)
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
    local spec = frame and frame.MSUFSpec
    local cfg = spec and spec.group
    local baseAlpha, baseLocked = BaseAlpha(frame)
    if baseLocked == true then
        ApplyHealthRangeAlpha(frame, 1)
        SetAlphaCached(frame, baseAlpha, "_msufGFRangeFrameAlpha")
        return
    end

    if cfg and cfg.rangeFadeEnabled == true and frame._msufGFRangeKnown == true then
        local inRange = frame._msufGFInRangeRaw
        if cfg.rangeFadeLayerMode == "health" then
            SetAlphaCached(frame, baseAlpha, "_msufGFRangeFrameAlpha")
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
            frame._msufGFRangeFrameAlpha = nil
            return
        end

        local safe = SafeBool(inRange)
        if safe ~= nil then
            SetAlphaCached(frame, baseAlpha * (safe and 1 or (cfg.rangeFadeAlpha or 0.4)), "_msufGFRangeFrameAlpha")
            return
        end
    end

    ApplyHealthRangeAlpha(frame, 1)
    SetAlphaCached(frame, baseAlpha, "_msufGFRangeFrameAlpha")
end

function GroupRangeFade.Apply(frame)
    ClearAlphaCaches(frame)
    if UnitIsPlayer(frame and frame.unit) then
        StoreRange(frame, true)
    else
        -- No initial range poll here. Group range fade is driven only by
        -- UNIT_IN_RANGE_UPDATE plus the related phase/party option events.
        StoreRange(frame, nil)
    end
    ApplyAlpha(frame)
end

function GroupRangeFade.Update(frame, event, unit, inRange)
    -- The core dispatcher already routes UNIT_EVENT_HAS_UNIT events to the
    -- frame whose .unit matches the event's unit, so unit-vs-frame matching
    -- is a no-op here in the normal path. We still tolerate a mismatching
    -- unit (defensive).
    local changed = false
    if event == "UNIT_IN_RANGE_UPDATE" then
        if not unit or unit == "" or unit == frame.unit then
            changed = StoreRange(frame, ResolveRangeValue(frame, unit or frame.unit, inRange))
        end
    elseif event == "UNIT_PHASE" or event == "UNIT_CTR_OPTIONS" or event == "UNIT_OTHER_PARTY_CHANGED" then
        if not unit or unit == "" or unit == frame.unit then
            changed = StoreRange(frame, ResolveRangeValue(frame, unit or frame.unit, nil))
        end
    elseif event == "UNIT_CONNECTION" then
        changed = true
    end
    if changed then
        ApplyAlpha(frame)
    end
end

function GroupRangeFade.Disable(frame)
    ClearRange(frame)
    ClearAlphaCaches(frame)
    ApplyHealthRangeAlpha(frame, 1)
    if frame and frame.SetAlpha then
        frame:SetAlpha(CoreAlpha(frame))
    end
end

UF.RegisterElement("GroupRangeFade", GroupRangeFade)
