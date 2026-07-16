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
local refreshSkironAnchorProxy
local watcher
local skironSourceHookPending = false
local observedSkironSources = setmetatable({}, { __mode = "k" })

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

local function ObserveSkironSource(source)
    if not (source and source.HookScript) then return false end
    if source.IsForbidden and source:IsForbidden() then return false end
    if observedSkironSources[source] then return true end
    if InCombatLockdown and InCombatLockdown()
        and source.IsProtected and source:IsProtected() then
        skironSourceHookPending = true
        if watcher then watcher:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return false
    end
    observedSkironSources[source] = true
    source:HookScript("OnSizeChanged", function(frame)
        refreshSkironAnchorProxy(frame, true, true)
    end)
    source:HookScript("OnShow", function(frame)
        refreshSkironAnchorProxy(frame, true, true)
    end)
    source:HookScript("OnHide", function()
        refreshSkironAnchorProxy(nil, false, true)
    end)
    return true
end

local function EnsureSkironAnchorProxy(source, isActiveProxy)
    -- Hook both candidates, including a currently hidden proxy. Skiron can
    -- switch back to that proxy with Show() and unchanged size, which does not
    -- guarantee its public size callback will fire.
    ObserveSkironSource(_G.SCM_GroupAnchorProxy_1)
    ObserveSkironSource(_G.SCM_GroupAnchor_1)
    source = ResolveSkironAnchorSource(source, isActiveProxy)
    local proxy = _G.MSUF_SkironCooldownAnchor
    if not source then
        local changed = proxy and proxy.MSUFSkironSource ~= nil or false
        if changed then
            proxy:ClearAllPoints()
            proxy.MSUFSkironSource = nil
            if proxy.Hide then proxy:Hide() end
        end
        return nil, changed
    end
    ObserveSkironSource(source)

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

local function RequestSkironAnchorApply()
    local UF = MSUF.UF
    if not (UF and UF.spawned) then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        if type(UF.RequestReanchorAfterCombat) == "function" then
            UF.RequestReanchorAfterCombat()
        end
        -- ClassPower and the detached power bar are insecure frames; they may
        -- re-anchor onto the proxy during lockdown (combat reload). Secure
        -- unit-frame geometry stays queued for the regen driver above.
        if type(_G.MSUF_ClassPower_Apply) == "function" then
            _G.MSUF_ClassPower_Apply({ anchor = true, cdm = true, syncNow = false })
        elseif type(_G.MSUF_ClassPower_Refresh) == "function" then
            _G.MSUF_ClassPower_Refresh()
        end
        return
    end
    local factory = UF.Factory
    if factory and type(factory.Apply) == "function" then
        factory.Apply()
    end
end

refreshSkironAnchorProxy = function(source, isActiveProxy, sizeChanged)
    local proxy, changed = EnsureSkironAnchorProxy(source, isActiveProxy)
    if proxy and type(_G.MSUF_EnsureCooldownWidthObservers) == "function" then
        _G.MSUF_EnsureCooldownWidthObservers()
    end
    if changed then
        RequestSkironAnchorApply()
    end
    if (changed or sizeChanged == true) and type(_G.MSUF_ScheduleCooldownWidthRefresh) == "function" then
        _G.MSUF_ScheduleCooldownWidthRefresh()
    end
    return proxy ~= nil
end

local function ScheduleSkironAnchorResolve()
    local function run()
        refreshSkironAnchorProxy()
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
    refreshSkironAnchorProxy(proxy, isActiveProxy, true)
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

watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(self, event, addon)
    if event == "PLAYER_REGEN_ENABLED" then
        if InCombatLockdown and InCombatLockdown() then return end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        skironSourceHookPending = false
        refreshSkironAnchorProxy(nil, false, true)
        return
    end
    if event == "ADDON_LOADED" and addon ~= "SkironCooldownManager" then
        return
    end
    RegisterThirdPartyAnchors()
end)

RegisterSkironAnchorProxy()
