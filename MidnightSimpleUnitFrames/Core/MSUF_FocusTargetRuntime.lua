local addonName, ns = ...
ns = ns or {}

local FTR = ns.FocusTargetRuntime or {}
ns.FocusTargetRuntime = FTR

local EVENT_TOKEN = "MSUF_FOCUSTARGET_RUNTIME"
local frame
local registered = false
local refreshQueued = false

local function IsDisabled(conf)
    return type(conf) == "table" and conf.enabled == false
end

local function EffectiveEnabled()
    local db = _G.MSUF_DB
    if type(db) ~= "table" then return false end
    local ft = db.focustarget
    if type(ft) ~= "table" or IsDisabled(ft) then return false end
    if IsDisabled(db.focus) then return false end
    return true
end

function FTR.IsEnabled()
    return EffectiveEnabled()
end

_G.MSUF_IsFocusTargetEffectiveEnabled = EffectiveEnabled

local function UnitFrame()
    local frames = _G.MSUF_UnitFrames
    return type(frames) == "table" and frames.focustarget or nil
end

local function RequestUpdate(reason)
    local f = UnitFrame()
    if f then
        f._msufCachedExists = nil
        f._msufExistsUnit = nil
        f._msufPortraitDirty = true
        f._msufPortraitNextAt = 0
    end

    local req = _G.MSUF_RequestUnitUpdate
    if type(req) == "function" then
        req("focustarget", nil, true, reason or "FOCUSTARGET")
        return
    end

    local apply = _G.MSUF_ApplyUnitFrameKey_Immediate
    if type(apply) == "function" then
        apply("focustarget")
    end
end

local function FlushRefresh()
    refreshQueued = false
    if type(_G.MSUF_RefreshAllUnitVisibilityDrivers) == "function" then
        _G.MSUF_RefreshAllUnitVisibilityDrivers(_G.MSUF_UnitEditModeActive == true)
    end
    if type(_G.MSUF_UFCore_NotifyConfigChanged) == "function" then
        _G.MSUF_UFCore_NotifyConfigChanged("focustarget", false, true, "FocusTargetRuntime")
    end
    RequestUpdate("FOCUSTARGET_REFRESH")
end

local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    if type(_G.MSUF_ScheduleOnce) == "function" then
        _G.MSUF_ScheduleOnce("FOCUSTARGET_RUNTIME_REFRESH", FlushRefresh)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0, FlushRefresh)
    else
        FlushRefresh()
    end
end

local function EnsureFrame()
    if frame then return frame end
    frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_TARGET" and unit ~= "focus" then return end
        RequestUpdate(event)
    end)
    return frame
end

local function Register()
    if registered then return end
    local f = EnsureFrame()
    if f.RegisterUnitEvent then
        f:RegisterUnitEvent("UNIT_TARGET", "focus")
    else
        f:RegisterEvent("UNIT_TARGET")
    end
    f:RegisterEvent("PLAYER_FOCUS_CHANGED")
    registered = true
end

local function Unregister()
    if not registered then return end
    if frame then
        pcall(frame.UnregisterEvent, frame, "UNIT_TARGET")
        pcall(frame.UnregisterEvent, frame, "PLAYER_FOCUS_CHANGED")
    end
    registered = false
end

function FTR.RefreshLifecycle(reason)
    if EffectiveEnabled() then
        Register()
    else
        Unregister()
    end
    QueueRefresh()
end

_G.MSUF_RefreshFocusTargetLifecycle = FTR.RefreshLifecycle

local function OnLoginOrProfile()
    FTR.RefreshLifecycle("BOOT")
end

if type(_G.MSUF_EventBus_Register) == "function" then
    _G.MSUF_EventBus_Register("PLAYER_LOGIN", EVENT_TOKEN, OnLoginOrProfile)
    _G.MSUF_EventBus_Register("PLAYER_ENTERING_WORLD", EVENT_TOKEN, OnLoginOrProfile)
end
