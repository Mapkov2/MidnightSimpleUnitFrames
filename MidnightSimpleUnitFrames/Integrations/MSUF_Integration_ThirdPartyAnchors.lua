local _, ns = ...

ns = ns or _G.MSUF_NS or {}
_G.MSUF_NS = ns

-- Third-party cooldown-anchor integration for the 5.72 frame engine.
-- This mirrors the 6.0 ownership model: providers own their layout frames,
-- while MSUF only observes provider lifecycle and binds consumers to a stable
-- provider identity. No polling or recurring OnUpdate work is used.
local CreateFrame = CreateFrame
local C_AddOns = C_AddOns
local C_Timer = C_Timer
local EventRegistry = EventRegistry
local InCombatLockdown = InCombatLockdown
local UIParent = UIParent
local WorldFrame = WorldFrame
local type = type

local SKIRON_ANCHOR_EVENT = "SkironCooldownManager.AnchorProxy.SizeChanged"
local RETRY_DELAYS = { 0, 0.05, 0.20, 0.60, 1.20, 2.00 }

local registeredSkiron
local refreshSkironAnchorProxy
local refreshCoolinatorAnchor
local watcher

local skironSourceHookPending = false
local skironProxyRefreshAfterCombat = false
local skironResolveGeneration = 0
local observedSkironSources = setmetatable({}, { __mode = "k" })

local coolinatorSourceHookPending = false
local coolinatorRefreshAfterCombat = false
local coolinatorResolveGeneration = 0
local coolinatorActiveSource
local observedCoolinatorSources = setmetatable({}, { __mode = "k" })
local essentialConsumerRefreshPending = false

local function InCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

local function IsFrameUsable(frame)
    if not (frame and frame ~= UIParent and frame ~= WorldFrame) then return false end
    if frame.IsForbidden and frame:IsForbidden() then return false end
    if frame.IsShown and not frame:IsShown() then return false end
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
    if IsFrameUsable(proxy) then return proxy end
    local groupAnchor = _G.SCM_GroupAnchor_1
    if IsFrameUsable(groupAnchor) then return groupAnchor end
end

local function ResolveCoolinatorAnchorSource()
    local source = _G.CoolinatorPrimaryGroupAnchor
    if IsFrameUsable(source) then return source end
end

local function ObserveSkironSource(source)
    if not (source and source.HookScript) then return false end
    if source.IsForbidden and source:IsForbidden() then return false end
    if observedSkironSources[source] then return true end
    if InCombat() and source.IsProtected and source:IsProtected() then
        skironSourceHookPending = true
        if watcher then watcher:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return false
    end
    observedSkironSources[source] = true
    source:HookScript("OnSizeChanged", function()
        refreshSkironAnchorProxy(nil, false, true)
    end)
    source:HookScript("OnShow", function()
        refreshSkironAnchorProxy(nil, false, true)
    end)
    source:HookScript("OnHide", function()
        refreshSkironAnchorProxy(nil, false, true)
    end)
    return true
end

local function ObserveCoolinatorSource(source)
    if not (source and source.HookScript) then return false end
    if source.IsForbidden and source:IsForbidden() then return false end
    if observedCoolinatorSources[source] then return true end
    if InCombat() and source.IsProtected and source:IsProtected() then
        coolinatorSourceHookPending = true
        if watcher then watcher:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return false
    end
    observedCoolinatorSources[source] = true
    source:HookScript("OnSizeChanged", function()
        refreshCoolinatorAnchor(true)
    end)
    source:HookScript("OnShow", function()
        refreshCoolinatorAnchor(true)
    end)
    source:HookScript("OnHide", function()
        refreshCoolinatorAnchor(true)
    end)
    return true
end

local function EnsureSkironAnchorProxy(source, isActiveProxy)
    -- Observe both primary candidates even while one is hidden. Skiron can
    -- switch ownership with Show() without changing its dimensions.
    ObserveSkironSource(_G.SCM_GroupAnchorProxy_1)
    ObserveSkironSource(_G.SCM_GroupAnchor_1)
    source = ResolveSkironAnchorSource(source, isActiveProxy)

    local proxy = _G.MSUF_SkironCooldownAnchor
    local previousSource = proxy and proxy.MSUFSkironSource or nil
    local transition = previousSource ~= source
        and (not previousSource and "acquired" or not source and "lost" or "switched")
        or nil
    if transition and InCombat() then
        skironProxyRefreshAfterCombat = true
        if watcher then watcher:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return previousSource and proxy or nil, false, nil, true
    end

    if not source then
        local changed = transition ~= nil
        if changed and proxy then
            proxy.MSUFSkironSource = nil
            if proxy.Hide then proxy:Hide() end
        end
        return nil, changed, transition, false
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
    return proxy, changed, transition, false
end

local function EnsureCoolinatorAnchorSource()
    -- Coolinator keeps this identity stable and repoints it at its first
    -- designer/runtime group. Native dependants inherit every geometry change.
    ObserveCoolinatorSource(_G.CoolinatorPrimaryGroupAnchor)
    local source = ResolveCoolinatorAnchorSource()
    local previousSource = coolinatorActiveSource
    local transition = previousSource ~= source
        and (not previousSource and "acquired" or not source and "lost" or "switched")
        or nil
    if transition and InCombat() then
        coolinatorRefreshAfterCombat = true
        if watcher then watcher:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return previousSource, false, nil, true
    end
    coolinatorActiveSource = source
    return source, transition ~= nil, transition, false
end

function ns.GetSkironCooldownAnchorProxy()
    local proxy = _G.MSUF_SkironCooldownAnchor
    if proxy and proxy.MSUFSkironSource ~= nil and (not proxy.IsShown or proxy:IsShown()) then
        return proxy
    end
end

function ns.GetCoolinatorCooldownAnchor()
    local source = coolinatorActiveSource
    if source and IsFrameUsable(source) then return source end
end

function ns.IsThirdPartyCooldownAnchor(frame)
    if not frame then return false end
    if frame == coolinatorActiveSource and IsFrameUsable(frame) then return true end
    local proxy = _G.MSUF_SkironCooldownAnchor
    return frame == proxy and proxy.MSUFSkironSource ~= nil
end

_G.MSUF_GetSkironCooldownAnchorProxy = function()
    return ns.GetSkironCooldownAnchorProxy()
end

_G.MSUF_GetCoolinatorCooldownAnchor = function()
    return ns.GetCoolinatorCooldownAnchor()
end

_G.MSUF_IsThirdPartyCooldownAnchor = function(frame)
    return ns.IsThirdPartyCooldownAnchor(frame)
end

local function ScheduleEssentialCooldownAnchorConsumerRefresh()
    if essentialConsumerRefreshPending then return end
    essentialConsumerRefreshPending = true

    local function run()
        essentialConsumerRefreshPending = false
        local refresh = _G.MSUF_RefreshExternalUnitFrameAnchor
        if type(refresh) == "function" then
            refresh("EssentialCooldownViewer")
        elseif type(_G.MSUF_ForceReanchorAllUnitFrames_Once) == "function" then
            _G.MSUF_ForceReanchorAllUnitFrames_Once(true)
        end
    end

    if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
end

local function ScheduleEssentialCooldownWidthRefresh()
    local schedule = _G.MSUF_ScheduleCooldownWidthRefresh
    if type(schedule) == "function" then
        schedule("EssentialCooldownViewer", false, true)
    end
end

refreshSkironAnchorProxy = function(source, isActiveProxy, sizeChanged)
    local proxy, changed, _transition, deferred = EnsureSkironAnchorProxy(source, isActiveProxy)
    if deferred then return proxy ~= nil end
    if changed or sizeChanged == true then ScheduleEssentialCooldownAnchorConsumerRefresh() end
    if changed or sizeChanged == true then ScheduleEssentialCooldownWidthRefresh() end
    return proxy ~= nil
end

refreshCoolinatorAnchor = function(sizeChanged)
    local source, changed, _transition, deferred = EnsureCoolinatorAnchorSource()
    if deferred then return source ~= nil end
    if changed then ScheduleEssentialCooldownAnchorConsumerRefresh() end
    if changed or sizeChanged == true then ScheduleEssentialCooldownWidthRefresh() end
    return source ~= nil
end

local function ScheduleSkironAnchorResolve()
    skironResolveGeneration = skironResolveGeneration + 1
    local generation = skironResolveGeneration
    local index = 1
    local function run()
        if generation ~= skironResolveGeneration then return end
        if refreshSkironAnchorProxy() then return end
        index = index + 1
        local delay = RETRY_DELAYS[index]
        if delay and C_Timer and C_Timer.After then C_Timer.After(delay, run) end
    end
    if not (C_Timer and C_Timer.After) then
        run()
        return
    end
    C_Timer.After(RETRY_DELAYS[index], run)
end

local function ScheduleCoolinatorAnchorResolve()
    coolinatorResolveGeneration = coolinatorResolveGeneration + 1
    local generation = coolinatorResolveGeneration
    local index = 1
    local function run()
        if generation ~= coolinatorResolveGeneration then return end
        if refreshCoolinatorAnchor() then return end
        index = index + 1
        local delay = RETRY_DELAYS[index]
        if delay and C_Timer and C_Timer.After then C_Timer.After(delay, run) end
    end
    if not (C_Timer and C_Timer.After) then
        run()
        return
    end
    C_Timer.After(RETRY_DELAYS[index], run)
end

local function OnSkironAnchorProxySizeChanged(_, proxyGroup, proxy, _width, _height, _selectedAnchorRef, isActiveProxy)
    if proxyGroup ~= 1 then return end
    refreshSkironAnchorProxy(proxy, isActiveProxy, true)
end

local function RegisterSkironAnchorProxy()
    if registeredSkiron then
        ScheduleSkironAnchorResolve()
        return true
    end
    if not (EventRegistry and type(EventRegistry.RegisterCallback) == "function") then return false end
    EventRegistry:RegisterCallback(SKIRON_ANCHOR_EVENT, OnSkironAnchorProxySizeChanged, "MidnightSimpleUnitFrames")
    registeredSkiron = true
    ScheduleSkironAnchorResolve()
    return true
end

local function RegisterCoolinatorAnchor()
    if not _G.CoolinatorPrimaryGroupAnchor then
        local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
        if type(isLoaded) ~= "function" or not isLoaded("Coolinator") then return false end
    end
    ScheduleCoolinatorAnchorResolve()
    return true
end

local function RegisterThirdPartyAnchors()
    local skiron = RegisterSkironAnchorProxy()
    local coolinator = RegisterCoolinatorAnchor()
    return skiron or coolinator
end

ns.RegisterThirdPartyAnchors = RegisterThirdPartyAnchors
_G.MSUF_RegisterThirdPartyAnchors = RegisterThirdPartyAnchors

watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(self, event, addon)
    if event == "PLAYER_REGEN_ENABLED" then
        if InCombat() then return end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        local refreshSkiron = skironSourceHookPending or skironProxyRefreshAfterCombat
        local refreshCoolinator = coolinatorSourceHookPending or coolinatorRefreshAfterCombat
        if not refreshSkiron and not refreshCoolinator then return end
        skironSourceHookPending = false
        skironProxyRefreshAfterCombat = false
        coolinatorSourceHookPending = false
        coolinatorRefreshAfterCombat = false
        if refreshSkiron then refreshSkironAnchorProxy(nil, false, true) end
        if refreshCoolinator then refreshCoolinatorAnchor(true) end
        return
    end
    if event == "ADDON_LOADED" then
        if addon == "SkironCooldownManager" then
            RegisterSkironAnchorProxy()
        elseif addon == "Coolinator" then
            RegisterCoolinatorAnchor()
        end
        return
    end
    RegisterThirdPartyAnchors()
end)

RegisterThirdPartyAnchors()
