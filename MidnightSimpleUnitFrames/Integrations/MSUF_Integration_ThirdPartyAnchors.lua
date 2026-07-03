local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}

-- Third-party anchor integration.
-- Tracks Skiron's cooldown anchor proxy after frames exist.
-- Integration is deferred in combat and must not take ownership of external addon layouts.
local CreateFrame = CreateFrame
local C_Timer = C_Timer
local EventRegistry = EventRegistry
local InCombatLockdown = InCombatLockdown
local UIParent = UIParent
local type = type

local SKIRON_ANCHOR_EVENT = "SkironCooldownManager.AnchorProxy.SizeChanged"
local SKIRON_RETRY_DELAYS = { 0, 0.05, 0.20, 0.60, 1.20, 2.00 }

local registeredSkiron

local function IsFrameUsable(frame)
    if not (frame and frame ~= UIParent and frame ~= WorldFrame) then
        return false
    end
    if frame.IsForbidden and frame:IsForbidden() then
        return false
    end
    if frame.IsShown and not frame:IsShown() then
        return false
    end
    local width = frame.GetWidth and frame:GetWidth() or 0
    local height = frame.GetHeight and frame:GetHeight() or 0
    return width > 0 and height > 0 and frame.SetPoint ~= nil
end

local function ResolveSkironAnchorSource(preferredFrame, isActiveProxy)
    if isActiveProxy and IsFrameUsable(preferredFrame) then
        return preferredFrame
    end
    local preferredName = preferredFrame and preferredFrame.GetName and preferredFrame:GetName()
    if preferredName == "SCM_GroupAnchor_1" and IsFrameUsable(preferredFrame) then
        return preferredFrame
    end

    local proxy = _G.SCM_GroupAnchorProxy_1
    if IsFrameUsable(proxy) then
        return proxy
    end

    local groupAnchor = _G.SCM_GroupAnchor_1
    if IsFrameUsable(groupAnchor) then
        return groupAnchor
    end
end

local function EnsureSkironAnchorProxy(source, isActiveProxy)
    source = ResolveSkironAnchorSource(source, isActiveProxy)
    if not source then
        return nil, false
    end

    local proxy = _G.MSUF_SkironCooldownAnchor
    if not proxy then
        proxy = CreateFrame("Frame", "MSUF_SkironCooldownAnchor", UIParent)
        proxy._msufStableAnchorProxy = true
        proxy._msufExternalAnchorCacheKey = "SkironCooldownManager"
        if proxy.EnableMouse then proxy:EnableMouse(false) end
        if proxy.SetAlpha then proxy:SetAlpha(0) end
        _G.MSUF_SkironCooldownAnchor = proxy
    end

    local changed = proxy.MSUFSkironSource ~= source
    if changed then
        proxy:ClearAllPoints()
        proxy:SetAllPoints(source)
        proxy.MSUFSkironSource = source
    end
    if proxy.Show then proxy:Show() end
    return proxy, changed
end

function MSUF.GetSkironCooldownAnchorProxy()
    return EnsureSkironAnchorProxy()
end

_G.MSUF_GetSkironCooldownAnchorProxy = function()
    return MSUF.GetSkironCooldownAnchorProxy()
end

local function TraceCP(msg)
    local buf = _G.MSUF_CPTraceBuffer
    if buf and #buf < 80 then
        buf[#buf + 1] = "[skiron] " .. msg
    end
end

local function RequestSkironAnchorApply()
    local UF = MSUF.UF
    if not (UF and UF.spawned) then
        TraceCP("apply skipped: UF not spawned yet")
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        if type(UF.RequestReanchorAfterCombat) == "function" then
            UF.RequestReanchorAfterCombat()
        end
        -- ClassPower and the detached power bar are insecure frames; they may
        -- re-anchor onto the proxy during lockdown (combat reload). Secure
        -- unit-frame geometry stays queued for the regen driver above.
        TraceCP("proxy resolved in combat -> CP refresh")
        if type(_G.MSUF_ClassPower_Refresh) == "function" then
            _G.MSUF_ClassPower_Refresh()
        end
        return
    end
    local factory = UF.Factory
    if factory and type(factory.Apply) == "function" then
        factory.Apply()
    end
end

local function RefreshSkironAnchorProxy(source, isActiveProxy)
    local proxy, changed = EnsureSkironAnchorProxy(source, isActiveProxy)
    if changed and proxy then
        TraceCP("source changed -> "
            .. tostring(proxy.MSUFSkironSource and proxy.MSUFSkironSource.GetName and proxy.MSUFSkironSource:GetName() or "?"))
        RequestSkironAnchorApply()
    end
    return proxy ~= nil
end

local function ScheduleSkironAnchorResolve()
    local function run()
        RefreshSkironAnchorProxy()
    end
    if not (C_Timer and C_Timer.After) then
        run()
        return
    end
    for i = 1, #SKIRON_RETRY_DELAYS do
        C_Timer.After(SKIRON_RETRY_DELAYS[i], run)
    end
end

local function OnSkironAnchorProxySizeChanged(_, proxyGroup, proxy, _width, _height, _selectedAnchorRef, isActiveProxy)
    if proxyGroup ~= 1 then
        return
    end
    RefreshSkironAnchorProxy(proxy, isActiveProxy)
end

local function RegisterSkironAnchorProxy()
    if registeredSkiron then
        ScheduleSkironAnchorResolve()
        return true
    end
    if not (EventRegistry and type(EventRegistry.RegisterCallback) == "function") then
        return false
    end
    EventRegistry:RegisterCallback(SKIRON_ANCHOR_EVENT, OnSkironAnchorProxySizeChanged, "MidnightSimpleUnitFrames")
    registeredSkiron = true
    ScheduleSkironAnchorResolve()
    return true
end

local function RegisterThirdPartyAnchors()
    return RegisterSkironAnchorProxy()
end

MSUF.RegisterThirdPartyAnchors = RegisterThirdPartyAnchors

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" and addon ~= "SkironCooldownManager" then
        return
    end
    RegisterThirdPartyAnchors()
end)

RegisterSkironAnchorProxy()
