local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}

-- Third-party anchor integration.
-- Tracks ArcUI, Skiron and Coolinator stable cooldown anchors after they exist.
-- Integration is deferred in combat and must not take ownership of external addon layouts.
local CreateFrame = CreateFrame
local C_AddOns = C_AddOns
local C_Timer = C_Timer
local EventRegistry = EventRegistry
local InCombatLockdown = InCombatLockdown
local UIParent = UIParent
local type = type

local ARCUI_ANCHOR_EVENT = "ArcUI.AnchorProxy.SizeChanged"
local SKIRON_ANCHOR_EVENT = "SkironCooldownManager.AnchorProxy.SizeChanged"
local SKIRON_RETRY_DELAYS = { 0, 0.05, 0.20, 0.60, 1.20, 2.00 }
local AUTOMATIC_COOLDOWN_ADDONS = {
    { id = "ArcUI", label = "Arc UI" },
    { id = "SkironCooldownManager", label = "Skiron" },
    { id = "Coolinator", label = "Coolinator" },
    -- Cooldown Manager Centered keeps Blizzard's EssentialCooldownViewer as
    -- its public layout frame, so it needs policy detection but no proxy.
    { id = "CooldownManagerCentered", label = "CDMC" },
}

local registeredArcUI
local arcUIAnchor
local arcUIRefreshAfterCombat = false
local refreshArcUIAnchor
local registeredSkiron
local refreshSkironAnchorProxy
local watcher
local skironSourceHookPending = false
local skironProxyRefreshAfterCombat = false
local skironResolveGeneration = 0
local observedSkironSources = setmetatable({}, { __mode = "k" })
local refreshCoolinatorAnchor
local coolinatorSourceHookPending = false
local coolinatorRefreshAfterCombat = false
local coolinatorResolveGeneration = 0
local coolinatorActiveSource
local observedCoolinatorSources = setmetatable({}, { __mode = "k" })
local automaticCooldownProviderId
local automaticCooldownProviderLabel
local automaticCooldownProviderResolved = false

local function IsAddOnFullyLoaded(addonName)
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
    if type(isLoaded) == "function" then
        local loadedOrLoading, loaded = isLoaded(addonName)
        if loaded ~= nil then return loaded == true end
        -- Test/legacy shims may expose the historical single return value.
        return loadedOrLoading == true
    end
    local legacy = _G.IsAddOnLoaded
    return type(legacy) == "function" and legacy(addonName) == true or false
end

local function DetectAutomaticCooldownProvider()
    for i = 1, #AUTOMATIC_COOLDOWN_ADDONS do
        local provider = AUTOMATIC_COOLDOWN_ADDONS[i]
        if IsAddOnFullyLoaded(provider.id) then
            return provider.id, provider.label
        end
    end
end

local function RefreshAutomaticCooldownAnchorConsumers()
    local UF = MSUF.UF
    local factory = UF and UF.Factory
    if UF and UF.spawned == true and factory and type(factory.ForceReanchor) == "function" then
        factory.ForceReanchor()
    end

    local editMode = _G.MSUF_EM2
    local hud = editMode and editMode.HUD
    if hud and type(hud.RefreshControls) == "function" then hud.RefreshControls(true) end

    local menu = (MSUF and MSUF.MSUF2) or _G.MSUF2
    if menu and type(menu.RequestRefresh) == "function" then
        menu.RequestRefresh(nil, "automatic-cooldown-anchor-provider")
    end
end

local function RefreshAutomaticCooldownProvider(notify)
    local providerId, providerLabel = DetectAutomaticCooldownProvider()
    local changed = automaticCooldownProviderResolved
        and (providerId ~= automaticCooldownProviderId or providerLabel ~= automaticCooldownProviderLabel)
    automaticCooldownProviderResolved = true
    automaticCooldownProviderId = providerId
    automaticCooldownProviderLabel = providerLabel
    if changed and notify ~= false then RefreshAutomaticCooldownAnchorConsumers() end
    return providerId, providerLabel, changed
end

function MSUF.GetAutomaticCooldownAnchorProvider()
    if not automaticCooldownProviderResolved then RefreshAutomaticCooldownProvider(false) end
    return automaticCooldownProviderId, automaticCooldownProviderLabel
end

function MSUF.IsCooldownAnchorEnabled(general)
    if MSUF.GetAutomaticCooldownAnchorProvider() ~= nil then return true end
    return type(general) == "table" and general.anchorToCooldown == true or false
end

_G.MSUF_GetAutomaticCooldownAnchorProvider = function()
    return MSUF.GetAutomaticCooldownAnchorProvider()
end

_G.MSUF_IsCooldownAnchorEnabled = function(general)
    return MSUF.IsCooldownAnchorEnabled(general)
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

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

local function ResolveCoolinatorAnchorSource()
    local source = _G.CoolinatorPrimaryGroupAnchor
    if IsFrameUsable(source) then return source end
end

local function ResolveArcUIAnchorSource()
    local api = _G.ArcUI_Public
    local getAnchor = api and api.GetGroupAnchor
    local source = type(getAnchor) == "function" and getAnchor("Essential") or nil
    if IsFrameUsable(source) then return source end
end

local function ObserveCoolinatorSource(source)
    if not (source and source.HookScript) then return false end
    if source.IsForbidden and source:IsForbidden() then return false end
    if observedCoolinatorSources[source] then return true end
    if InCombat()
        and source.IsProtected and source:IsProtected() then
        coolinatorSourceHookPending = true
        if watcher then watcher:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return false
    end
    observedCoolinatorSources[source] = true
    source:HookScript("OnSizeChanged", function()
        refreshCoolinatorAnchor()
    end)
    source:HookScript("OnShow", function()
        refreshCoolinatorAnchor()
    end)
    source:HookScript("OnHide", function()
        refreshCoolinatorAnchor()
    end)
    return true
end

local function EnsureCoolinatorAnchorSource()
    -- Coolinator keeps this frame identity stable and repoints it at the first
    -- designer/runtime group. Unit frames anchored to it therefore inherit
    -- position and size changes without any recurring MSUF work.
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

local function ObserveSkironSource(source)
    if not (source and source.HookScript) then return false end
    if source.IsForbidden and source:IsForbidden() then return false end
    if observedSkironSources[source] then return true end
    if InCombat()
        and source.IsProtected and source:IsProtected() then
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

local function EnsureSkironAnchorProxy(source, isActiveProxy)
    -- Hook both candidates, including a currently hidden proxy. Skiron can
    -- switch back to that proxy with Show() and unchanged size, which does not
    -- guarantee its public size callback will fire.
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
            -- Keep the last points while hidden. Clearing them can make secure
            -- dependants jump before their targeted fallback rebind runs.
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

function MSUF.GetSkironCooldownAnchorProxy()
    -- Resolver reads must not consume a source transition. Creation, loss and
    -- rebinding are owned by refreshSkironAnchorProxy so every state change
    -- reaches the same targeted anchor/width notification path.
    local proxy = _G.MSUF_SkironCooldownAnchor
    if proxy and proxy.MSUFSkironSource ~= nil and (not proxy.IsShown or proxy:IsShown()) then
        return proxy
    end
end

_G.MSUF_GetSkironCooldownAnchorProxy = function()
    return MSUF.GetSkironCooldownAnchorProxy()
end

function MSUF.GetCoolinatorCooldownAnchor()
    local source = coolinatorActiveSource
    if source and IsFrameUsable(source) then return source end
end

function MSUF.GetArcUICooldownAnchor()
    return arcUIAnchor
end

_G.MSUF_GetCoolinatorCooldownAnchor = function()
    return MSUF.GetCoolinatorCooldownAnchor()
end

_G.MSUF_GetArcUICooldownAnchor = function()
    return MSUF.GetArcUICooldownAnchor()
end

local function RefreshEssentialCooldownAnchorConsumers(transition)
    if transition ~= "acquired" and transition ~= "lost" then return end
    local UF = MSUF.UF
    local factory = UF and UF.Factory
    if factory and type(factory.RefreshExternalAnchor) == "function" then
        factory.RefreshExternalAnchor("EssentialCooldownViewer")
    end

    local bars = _G.MSUF_DB and _G.MSUF_DB.bars
    if bars and bars.classPowerAnchorToCooldown == true
        and bars.classPowerWidthMode ~= "cooldown"
        and type(_G.MSUF_ClassPower_RefreshLayout) == "function" then
        _G.MSUF_ClassPower_RefreshLayout()
    end
end

refreshArcUIAnchor = function(sizeChanged)
    local source = arcUIAnchor or ResolveArcUIAnchorSource()
    if not source then return false end
    local acquired = not arcUIAnchor
    if acquired and InCombat() then
        arcUIRefreshAfterCombat = true
        if watcher then watcher:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return true
    end
    if acquired then
        arcUIAnchor = source
        if type(_G.MSUF_EnsureCooldownWidthObservers) == "function" then
            _G.MSUF_EnsureCooldownWidthObservers(true)
        end
        RefreshEssentialCooldownAnchorConsumers("acquired")
    end
    if (acquired or sizeChanged == true) and type(_G.MSUF_ScheduleCooldownWidthRefresh) == "function" then
        _G.MSUF_ScheduleCooldownWidthRefresh("EssentialCooldownViewer", false, true)
    end
    return true
end

refreshSkironAnchorProxy = function(source, isActiveProxy, sizeChanged)
    local proxy, changed, transition, deferred = EnsureSkironAnchorProxy(source, isActiveProxy)
    if deferred then return proxy ~= nil end
    if changed then
        if type(_G.MSUF_EnsureCooldownWidthObservers) == "function" then
            _G.MSUF_EnsureCooldownWidthObservers(true)
        end
        RefreshEssentialCooldownAnchorConsumers(transition)
    end
    if (changed or sizeChanged == true) and type(_G.MSUF_ScheduleCooldownWidthRefresh) == "function" then
        _G.MSUF_ScheduleCooldownWidthRefresh("EssentialCooldownViewer", false, true)
    end
    return proxy ~= nil
end

refreshCoolinatorAnchor = function()
    local source, changed, transition, deferred = EnsureCoolinatorAnchorSource()
    if deferred then return source ~= nil end
    if changed then
        if type(_G.MSUF_EnsureCooldownWidthObservers) == "function" then
            _G.MSUF_EnsureCooldownWidthObservers(true)
        end
        RefreshEssentialCooldownAnchorConsumers(transition)
        if type(_G.MSUF_ScheduleCooldownWidthRefresh) == "function" then
            _G.MSUF_ScheduleCooldownWidthRefresh("EssentialCooldownViewer", false, true)
        end
    end
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
        local delay = SKIRON_RETRY_DELAYS[index]
        if delay and C_Timer and C_Timer.After then C_Timer.After(delay, run) end
    end
    if not (C_Timer and C_Timer.After) then
        run()
        return
    end
    C_Timer.After(SKIRON_RETRY_DELAYS[index], run)
end

local function ScheduleCoolinatorAnchorResolve()
    coolinatorResolveGeneration = coolinatorResolveGeneration + 1
    local generation = coolinatorResolveGeneration
    local index = 1
    local function run()
        if generation ~= coolinatorResolveGeneration then return end
        if refreshCoolinatorAnchor() then return end
        index = index + 1
        local delay = SKIRON_RETRY_DELAYS[index]
        if delay and C_Timer and C_Timer.After then C_Timer.After(delay, run) end
    end
    if not (C_Timer and C_Timer.After) then
        run()
        return
    end
    C_Timer.After(SKIRON_RETRY_DELAYS[index], run)
end

local function OnSkironAnchorProxySizeChanged(_, proxyGroup, proxy, _width, _height, _selectedAnchorRef, isActiveProxy)
    if proxyGroup ~= 1 then
        return
    end
    refreshSkironAnchorProxy(proxy, isActiveProxy, true)
end

local function OnArcUIAnchorChanged(_, groupName)
    if groupName == "Essential" then refreshArcUIAnchor(true) end
end

local function RegisterArcUIAnchor()
    local api = _G.ArcUI_Public
    if not (api and type(api.GetGroupAnchor) == "function") then return false end
    if not registeredArcUI then
        if not (EventRegistry and type(EventRegistry.RegisterCallback) == "function") then return false end
        EventRegistry:RegisterCallback(api.ANCHOR_CHANGED_EVENT or ARCUI_ANCHOR_EVENT,
            OnArcUIAnchorChanged, "MidnightSimpleUnitFrames")
        registeredArcUI = true
    end
    return refreshArcUIAnchor()
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

local function RegisterCoolinatorAnchor()
    if not _G.CoolinatorPrimaryGroupAnchor then
        local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
        if type(isLoaded) ~= "function" or not isLoaded("Coolinator") then return false end
    end
    ScheduleCoolinatorAnchorResolve()
    return true
end

local function RegisterThirdPartyAnchors()
    local arcUI = RegisterArcUIAnchor()
    local skiron = RegisterSkironAnchorProxy()
    local coolinator = RegisterCoolinatorAnchor()
    return arcUI or skiron or coolinator
end

MSUF.RegisterThirdPartyAnchors = RegisterThirdPartyAnchors

watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(self, event, addon)
    if event == "PLAYER_REGEN_ENABLED" then
        if InCombat() then return end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        local refreshArcUI = arcUIRefreshAfterCombat
        local refreshSkiron = skironSourceHookPending or skironProxyRefreshAfterCombat
        local refreshCoolinator = coolinatorSourceHookPending or coolinatorRefreshAfterCombat
        if not refreshArcUI and not refreshSkiron and not refreshCoolinator then return end
        arcUIRefreshAfterCombat = false
        skironSourceHookPending = false
        skironProxyRefreshAfterCombat = false
        coolinatorSourceHookPending = false
        coolinatorRefreshAfterCombat = false
        if refreshArcUI then refreshArcUIAnchor(true) end
        if refreshSkiron then refreshSkironAnchorProxy(nil, false, true) end
        if refreshCoolinator then refreshCoolinatorAnchor() end
        return
    end
    if event == "ADDON_LOADED" then
        RefreshAutomaticCooldownProvider(true)
        if addon == "ArcUI" then
            RegisterArcUIAnchor()
        elseif addon == "SkironCooldownManager" then
            RegisterSkironAnchorProxy()
        elseif addon == "Coolinator" then
            RegisterCoolinatorAnchor()
        end
        return
    end
    RefreshAutomaticCooldownProvider(true)
    RegisterThirdPartyAnchors()
end)

RefreshAutomaticCooldownProvider(false)
RegisterThirdPartyAnchors()
