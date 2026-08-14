local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}

-- Third-party anchor integration.
-- Tracks ArcUI, Skiron, Coolinator and EllesmereUI stable cooldown anchors after they exist.
-- Integration is deferred in combat and must not take ownership of external addon layouts.
local CreateFrame = CreateFrame
local C_AddOns = C_AddOns
local C_Timer = C_Timer
local EventRegistry = EventRegistry
local InCombatLockdown = InCombatLockdown
local UIParent = UIParent
local type = type
local format = string.format

local ARCUI_ANCHOR_EVENT = "ArcUI.AnchorProxy.SizeChanged"
local SKIRON_ANCHOR_EVENT = "SkironCooldownManager.AnchorProxy.SizeChanged"
local SKIRON_RETRY_DELAYS = { 0, 0.05, 0.20, 0.60, 1.20, 2.00 }
local AUTOMATIC_COOLDOWN_ADDONS = {
    { id = "ArcUI", label = "Arc UI" },
    { id = "SkironCooldownManager", label = "Skiron" },
    { id = "Coolinator", label = "Coolinator" },
    { id = "EllesmereUICooldownManager", label = "EllesmereUI CDM" },
    -- Cooldown Manager Centered keeps Blizzard's EssentialCooldownViewer as
    -- its public layout frame, so it needs policy detection but no proxy.
    { id = "CooldownManagerCentered", label = "CDMC" },
}
local AUTOMATIC_COOLDOWN_ADDON_IDS = {}
for i = 1, #AUTOMATIC_COOLDOWN_ADDONS do
    AUTOMATIC_COOLDOWN_ADDON_IDS[AUTOMATIC_COOLDOWN_ADDONS[i].id] = true
end

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
local ellesmereCooldownRefreshAfterCombat = false
local ellesmereCooldownResolveGeneration = 0
local ellesmereCooldownResolvePending = false
local ellesmereCooldownActiveSource
local automaticCooldownProviderId
local automaticCooldownProviderLabel
local automaticCooldownProviderResolved = false
local InCombat
local cooldownConsentPromptProviderId
local cooldownConsentPromptAfterCombat = false
local COOLDOWN_CONSENT_POPUP = "MSUF_COOLDOWN_ANCHOR_CONSENT"
local COOLDOWN_CONFIRM_POPUP = "MSUF_COOLDOWN_ANCHOR_CONFIRM"
local COOLDOWN_MISSING_ANCHOR_POPUP = "MSUF_COOLDOWN_ANCHOR_MISSING"
--- The existing bounded provider acquisition chain can take up to 4.05 seconds.
--- Warn only after it has had time to resolve so login order does not create a
--- false positive for Skiron, Coolinator or EllesmereUI.
local COOLDOWN_MISSING_ANCHOR_WARNING_DELAY = 4.25
local missingAnchorWarningShown = false

local function Tr(text)
    local translate = MSUF and MSUF.Translate
    if type(translate) == "function" then return translate(text) end
    local L = (MSUF and MSUF.L) or _G.MSUF_L
    return type(L) == "table" and L[text] or text
end

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

local function RefreshAutomaticCooldownAnchorConsumers(reanchor)
    local UF = MSUF.UF
    local factory = UF and UF.Factory
    if reanchor == true and UF and UF.spawned == true and factory and type(factory.ForceReanchor) == "function" then
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
    if changed then
        cooldownConsentPromptProviderId = nil
        if type(_G.StaticPopup_Hide) == "function" then
            _G.StaticPopup_Hide(COOLDOWN_CONSENT_POPUP)
            _G.StaticPopup_Hide(COOLDOWN_CONFIRM_POPUP)
        end
    end
    if changed and notify ~= false then
        local general = type(_G.MSUF_DB) == "table" and _G.MSUF_DB.general or nil
        RefreshAutomaticCooldownAnchorConsumers(type(general) == "table" and general.anchorToCooldown == true)
    end
    return providerId, providerLabel, changed
end

function MSUF.GetAutomaticCooldownAnchorProvider()
    if not automaticCooldownProviderResolved then RefreshAutomaticCooldownProvider(false) end
    return automaticCooldownProviderId, automaticCooldownProviderLabel
end

function MSUF.IsCooldownAnchorEnabled(general)
    return type(general) == "table" and general.anchorToCooldown == true or false
end

local function CooldownConsentDecisions(create)
    local globalDB = _G.MSUF_GlobalDB
    if type(globalDB) ~= "table" then
        if not create then return nil end
        globalDB = {}
        _G.MSUF_GlobalDB = globalDB
    end
    if type(globalDB.global) ~= "table" then
        if not create then return nil end
        globalDB.global = {}
    end
    local decisions = globalDB.global.cooldownAnchorProviderDecisions
    if type(decisions) ~= "table" then
        if not create then return nil end
        decisions = {}
        globalDB.global.cooldownAnchorProviderDecisions = decisions
    end
    return decisions
end

local function CooldownConsentDecision(providerId)
    providerId = providerId or MSUF.GetAutomaticCooldownAnchorProvider()
    local decisions = providerId and CooldownConsentDecisions(false) or nil
    local decision = decisions and decisions[providerId]
    if decision == "accepted" or decision == "declined" then return decision end
    return nil
end

local function RememberCooldownConsent(providerId, enabled)
    if not providerId then return end
    CooldownConsentDecisions(true)[providerId] = enabled == true and "accepted" or "declined"
end

function MSUF.GetCooldownAnchorConsentDecision(providerId)
    return CooldownConsentDecision(providerId)
end

function MSUF.SetCooldownAnchorEnabled(enabled, rememberDecision)
    local db = _G.MSUF_DB
    if type(db) ~= "table" then return false end
    if type(db.general) ~= "table" then db.general = {} end
    enabled = enabled == true
    local changed = db.general.anchorToCooldown ~= enabled
    db.general.anchorToCooldown = enabled

    local providerId = MSUF.GetAutomaticCooldownAnchorProvider()
    if rememberDecision ~= false and providerId then RememberCooldownConsent(providerId, enabled) end
    cooldownConsentPromptProviderId = nil
    cooldownConsentPromptAfterCombat = false
    if type(_G.StaticPopup_Hide) == "function" then
        _G.StaticPopup_Hide(COOLDOWN_CONSENT_POPUP)
        _G.StaticPopup_Hide(COOLDOWN_CONFIRM_POPUP)
    end
    RefreshAutomaticCooldownAnchorConsumers(changed)
    return true, changed
end

local function FirstConsentText(providerLabel)
    return format(Tr("MSUF detected %s."), providerLabel)
        .. "\n\n"
        .. Tr("Would you like MSUF to anchor the global Unit Frame layout to Essential Cooldown Manager?")
        .. "\n\n"
        .. Tr("Nothing will move unless you confirm again in the next step. If you choose Keep independent, you can enable CDM anchoring at any time in MSUF Edit Mode or under Unit > Anchoring in the MSUF menu.")
end

local function FinalConsentText(providerLabel)
    return format(Tr("Second confirmation for %s."), providerLabel)
        .. "\n\n"
        .. Tr("MSUF will now anchor the global Unit Frame layout to Essential Cooldown Manager.")
        .. "\n\n"
        .. Tr("Confirm only if you want the whole Unit Frame layout to move with your cooldowns.")
end

local function ResolveCooldownConsent(data, enabled)
    if type(data) ~= "table" or data.providerId ~= automaticCooldownProviderId then return end
    RememberCooldownConsent(data.providerId, enabled)
    MSUF.SetCooldownAnchorEnabled(enabled, false)
end

local function InstallCooldownConsentPopups()
    local dialogs = _G.StaticPopupDialogs
    if type(dialogs) ~= "table" then return false end
    if not dialogs[COOLDOWN_CONFIRM_POPUP] then
        dialogs[COOLDOWN_CONFIRM_POPUP] = {
            text = "%s",
            button1 = Tr("Confirm anchoring"),
            button2 = _G.CANCEL or Tr("Cancel"),
            OnAccept = function(_, data) ResolveCooldownConsent(data, true) end,
            OnCancel = function(_, data, reason)
                if reason == "clicked" then ResolveCooldownConsent(data, false) end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    if not dialogs[COOLDOWN_CONSENT_POPUP] then
        dialogs[COOLDOWN_CONSENT_POPUP] = {
            text = "%s",
            button1 = Tr("Continue"),
            button2 = Tr("Keep independent"),
            OnAccept = function(_, data)
                if type(data) ~= "table" or data.providerId ~= automaticCooldownProviderId then return end
                if type(_G.StaticPopup_Show) == "function" then
                    _G.StaticPopup_Show(COOLDOWN_CONFIRM_POPUP, FinalConsentText(data.providerLabel), nil, data)
                end
            end,
            OnCancel = function(_, data, reason)
                if reason == "clicked" then ResolveCooldownConsent(data, false) end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    return true
end

local function MaybeShowCooldownConsent()
    local providerId, providerLabel = MSUF.GetAutomaticCooldownAnchorProvider()
    if not providerId or cooldownConsentPromptProviderId == providerId then return false end
    local db = _G.MSUF_DB
    local general = type(db) == "table" and db.general or nil
    if type(general) ~= "table" then return false end

    if general.anchorToCooldown == true then
        RememberCooldownConsent(providerId, true)
        return false
    end
    if CooldownConsentDecision(providerId) ~= nil then return false end
    if InCombat() then
        cooldownConsentPromptAfterCombat = true
        watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        return false
    end
    if not InstallCooldownConsentPopups() or type(_G.StaticPopup_Show) ~= "function" then return false end

    local data = { providerId = providerId, providerLabel = providerLabel }
    local popup = _G.StaticPopup_Show(COOLDOWN_CONSENT_POPUP, FirstConsentText(providerLabel), nil, data)
    if not popup then return false end
    cooldownConsentPromptProviderId = providerId
    return true
end

_G.MSUF_GetAutomaticCooldownAnchorProvider = function()
    return MSUF.GetAutomaticCooldownAnchorProvider()
end

_G.MSUF_IsCooldownAnchorEnabled = function(general)
    return MSUF.IsCooldownAnchorEnabled(general)
end

_G.MSUF_GetCooldownAnchorConsentDecision = function(providerId)
    return MSUF.GetCooldownAnchorConsentDecision(providerId)
end

_G.MSUF_SetCooldownAnchorEnabled = function(enabled, rememberDecision)
    return MSUF.SetCooldownAnchorEnabled(enabled, rememberDecision)
end

InCombat = function()
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

local function GetEllesmereCooldownAnchorSource()
    local getBarFrame = _G._ECME_GetBarFrame
    if type(getBarFrame) ~= "function" then return nil end
    local ok, source = pcall(getBarFrame, "cooldowns")
    if ok then return source end
end

local function ResolveEllesmereCooldownAnchorSource()
    local source = GetEllesmereCooldownAnchorSource()
    if IsFrameUsable(source) then return source end
end

local function DeferEllesmereCooldownResolve()
    ellesmereCooldownResolveGeneration = ellesmereCooldownResolveGeneration + 1
    ellesmereCooldownResolvePending = false
    if ellesmereCooldownRefreshAfterCombat then return end
    ellesmereCooldownRefreshAfterCombat = true
    if watcher then watcher:RegisterEvent("PLAYER_REGEN_ENABLED") end
end

local function EnsureEllesmereCooldownAnchorSource()
    -- EllesmereUI exposes its movable Essential bar container through this
    -- cross-addon accessor. Blizzard's EssentialCooldownViewer deliberately
    -- remains an unmoved shell. Resolve once, without permanently hooking the
    -- external frame; MSUF's feature-gated width observer owns size updates.
    local source = ResolveEllesmereCooldownAnchorSource()
    local previousSource = ellesmereCooldownActiveSource
    local transition = previousSource ~= source
        and (not previousSource and "acquired" or not source and "lost" or "switched")
        or nil
    if transition and InCombat() then
        DeferEllesmereCooldownResolve()
        return previousSource, false, nil, true
    end
    ellesmereCooldownActiveSource = source
    return source, transition ~= nil, transition, false
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

local function EnsureCoolinatorAnchorSource()
    -- Coolinator keeps this frame identity stable and repoints it at the first
    -- designer/runtime group. Out of combat MSUF consumers follow it live; the
    -- Factory combat-edge freeze severs those links while a fight lasts.
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

function MSUF.GetEllesmereCooldownAnchor()
    local source = ellesmereCooldownActiveSource
    if source and IsFrameUsable(source) then return source end
end

function MSUF.GetArcUICooldownAnchor()
    return arcUIAnchor
end

local function BlizzardCooldownViewerEnabled()
    local registry = _G.CVarCallbackRegistry
    local getCached = registry and registry.GetCVarValueBool
    if type(getCached) == "function" then
        local ok, enabled = pcall(getCached, registry, "cooldownViewerEnabled")
        if ok and enabled ~= nil then return enabled == true end
    end

    local cvar = _G.C_CVar
    local getCVarBool = cvar and cvar.GetCVarBool
    if type(getCVarBool) == "function" then
        local ok, enabled = pcall(getCVarBool, "cooldownViewerEnabled")
        if ok and enabled ~= nil then return enabled == true end
    end

    local legacy = _G.GetCVarBool
    if type(legacy) == "function" then
        local ok, enabled = pcall(legacy, "cooldownViewerEnabled")
        if ok and enabled ~= nil then return enabled == true end
    end
    return false
end

local function BlizzardEssentialCooldownAnchorActive()
    local api = _G.C_CooldownViewer
    local isAvailable = api and api.IsCooldownViewerAvailable
    if type(isAvailable) ~= "function" then return false end
    local ok, available = pcall(isAvailable)
    if not ok or available ~= true or not BlizzardCooldownViewerEnabled() then return false end

    local viewer = _G.EssentialCooldownViewer
    if not viewer then return false end
    local visibleEnum = _G.Enum and _G.Enum.CooldownViewerVisibleSetting
    if visibleEnum and viewer.visibleSetting == visibleEnum.Hidden then return false end
    return true
end

--- Returns the configured provider that can own the Essential cooldown anchor.
--- This is intentionally not an IsAddOnLoaded check: disabled providers may be
--- loaded without exposing an anchor, while Coolinator exposes its own anchor
--- with Blizzard's cooldownViewerEnabled CVar disabled.
function MSUF.GetActiveCooldownAnchorProvider()
    if arcUIAnchor then return "ArcUI", arcUIAnchor end

    local skironProxy = _G.MSUF_SkironCooldownAnchor
    if skironProxy and skironProxy.MSUFSkironSource ~= nil then
        return "SkironCooldownManager", skironProxy
    end
    if coolinatorActiveSource then return "Coolinator", coolinatorActiveSource end
    if ellesmereCooldownActiveSource then return "EllesmereUICooldownManager", ellesmereCooldownActiveSource end
    if BlizzardEssentialCooldownAnchorActive() then
        return "Blizzard", _G.EssentialCooldownViewer
    end
end

local function MissingCooldownAnchorWarningText()
    return "|cffff4040" .. Tr("No cooldown anchor found.") .. "|r"
        .. "\n\n"
        .. "|cffffffff" .. Tr("Follow Blizzard's Essential Cooldowns") .. "|r "
        .. "|cffffd200" .. Tr("is ON, but no supported anchor is active.") .. "|r"
        .. "\n\n"
        .. "|cffff8000" .. Tr("This can cause major frame-position errors.") .. "|r"
        .. "\n\n"
        .. "|cff40ff80" .. Tr("Open Unit > Anchoring to fix it.") .. "|r"
end

local function OpenCooldownAnchorSetting()
    local open = _G.MSUF_OpenExactSettingControl
    if type(open) ~= "function" then return false end
    return open("general.anchorToCooldown", Tr("Follow Blizzard's Essential Cooldowns"), "uf_player")
end

local function InstallMissingCooldownAnchorPopup()
    local dialogs = _G.StaticPopupDialogs
    if type(dialogs) ~= "table" then return false end
    if dialogs[COOLDOWN_MISSING_ANCHOR_POPUP] then return true end
    dialogs[COOLDOWN_MISSING_ANCHOR_POPUP] = {
        text = "%s",
        button1 = "|cff40ff80" .. Tr("Fix now") .. "|r",
        button2 = _G.CANCEL or Tr("Cancel"),
        OnAccept = OpenCooldownAnchorSetting,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    return true
end

local function ShowMissingCooldownAnchorWarning()
    if missingAnchorWarningShown then return false end
    local general = type(_G.MSUF_DB) == "table" and _G.MSUF_DB.general or nil
    if not MSUF.IsCooldownAnchorEnabled(general) then return false end
    if MSUF.GetActiveCooldownAnchorProvider() then return false end
    missingAnchorWarningShown = true

    local text = MissingCooldownAnchorWarningText()
    if InstallMissingCooldownAnchorPopup() and type(_G.StaticPopup_Show) == "function" then
        _G.StaticPopup_Show(COOLDOWN_MISSING_ANCHOR_POPUP, text)
        return true
    end
    if type(_G.print) == "function" then
        _G.print("|cffffd700MSUF:|r " .. text:gsub("\n\n", " "))
    end
    return false
end

local function ScheduleMissingCooldownAnchorWarning()
    local general = type(_G.MSUF_DB) == "table" and _G.MSUF_DB.general or nil
    if not MSUF.IsCooldownAnchorEnabled(general) then return end
    if _G.C_Timer and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(COOLDOWN_MISSING_ANCHOR_WARNING_DELAY, ShowMissingCooldownAnchorWarning)
    else
        ShowMissingCooldownAnchorWarning()
    end
end

_G.MSUF_GetCoolinatorCooldownAnchor = function()
    return MSUF.GetCoolinatorCooldownAnchor()
end

_G.MSUF_GetEllesmereCooldownAnchor = function()
    return MSUF.GetEllesmereCooldownAnchor()
end

_G.MSUF_GetArcUICooldownAnchor = function()
    return MSUF.GetArcUICooldownAnchor()
end

_G.MSUF_GetActiveCooldownAnchorProvider = function()
    return MSUF.GetActiveCooldownAnchorProvider()
end

local function RefreshEssentialCooldownAnchorConsumers(transition)
    if transition ~= "acquired" and transition ~= "lost" and transition ~= "switched" and transition ~= "changed" then return end
    if (transition == "acquired" or transition == "switched")
        and type(_G.StaticPopup_Hide) == "function" then
        _G.StaticPopup_Hide(COOLDOWN_MISSING_ANCHOR_POPUP)
    end
    local UF = MSUF.UF
    local factory = UF and UF.Factory
    local factoryHandled = false
    if factory and type(factory.ScheduleExternalAnchorRefresh) == "function" then
        factory.ScheduleExternalAnchorRefresh("EssentialCooldownViewer")
        factoryHandled = true
    elseif factory and type(factory.RefreshExternalAnchor) == "function" then
        factory.RefreshExternalAnchor("EssentialCooldownViewer")
        factoryHandled = true
    end

    local bars = _G.MSUF_DB and _G.MSUF_DB.bars
    if not factoryHandled and bars and bars.classPowerAnchorToCooldown == true
        and bars.classPowerWidthMode ~= "cooldown"
        and type(_G.MSUF_ClassPower_RefreshLayout) == "function" then
        _G.MSUF_ClassPower_RefreshLayout()
    end
end

refreshArcUIAnchor = function(sizeChanged)
    local source = ResolveArcUIAnchorSource()
    local previousSource = arcUIAnchor
    local transition = previousSource ~= source
        and (not previousSource and "acquired" or not source and "lost" or "switched")
        or nil
    if transition and InCombat() then
        arcUIRefreshAfterCombat = true
        if watcher then watcher:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return previousSource ~= nil
    end
    arcUIAnchor = source
    if transition then
        if type(_G.MSUF_EnsureCooldownWidthObservers) == "function" then
            _G.MSUF_EnsureCooldownWidthObservers(true)
        end
        RefreshEssentialCooldownAnchorConsumers(transition)
    elseif sizeChanged == true then
        RefreshEssentialCooldownAnchorConsumers("changed")
    end
    if (transition or sizeChanged == true) and type(_G.MSUF_ScheduleCooldownWidthRefresh) == "function" then
        _G.MSUF_ScheduleCooldownWidthRefresh("EssentialCooldownViewer", false, true)
    end
    return source ~= nil
end

refreshSkironAnchorProxy = function(source, isActiveProxy, sizeChanged)
    local proxy, changed, transition, deferred = EnsureSkironAnchorProxy(source, isActiveProxy)
    if deferred then return proxy ~= nil end
    if changed then
        if type(_G.MSUF_EnsureCooldownWidthObservers) == "function" then
            _G.MSUF_EnsureCooldownWidthObservers(true)
        end
        RefreshEssentialCooldownAnchorConsumers(transition)
    elseif sizeChanged == true then
        RefreshEssentialCooldownAnchorConsumers("changed")
    end
    if (changed or sizeChanged == true) and type(_G.MSUF_ScheduleCooldownWidthRefresh) == "function" then
        _G.MSUF_ScheduleCooldownWidthRefresh("EssentialCooldownViewer", false, true)
    end
    return proxy ~= nil
end

refreshCoolinatorAnchor = function(sizeChanged)
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
    elseif sizeChanged == true then
        RefreshEssentialCooldownAnchorConsumers("changed")
        if type(_G.MSUF_ScheduleCooldownWidthRefresh) == "function" then
            _G.MSUF_ScheduleCooldownWidthRefresh("EssentialCooldownViewer", false, true)
        end
    end
    return source ~= nil
end

local function refreshEllesmereCooldownAnchor()
    local source, changed, transition, deferred = EnsureEllesmereCooldownAnchorSource()
    if deferred then return source ~= nil, true end
    if changed then
        if type(_G.MSUF_EnsureCooldownWidthObservers) == "function" then
            _G.MSUF_EnsureCooldownWidthObservers(true)
        end
        RefreshEssentialCooldownAnchorConsumers(transition)
        if type(_G.MSUF_ScheduleCooldownWidthRefresh) == "function" then
            _G.MSUF_ScheduleCooldownWidthRefresh("EssentialCooldownViewer", false, true)
        end
    end
    return source ~= nil, false
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

local function ScheduleEllesmereCooldownAnchorResolve()
    if ellesmereCooldownResolvePending then return end
    if InCombat() then
        DeferEllesmereCooldownResolve()
        return
    end
    ellesmereCooldownResolveGeneration = ellesmereCooldownResolveGeneration + 1
    local generation = ellesmereCooldownResolveGeneration
    ellesmereCooldownResolvePending = true
    local index = 1
    local function run()
        if generation ~= ellesmereCooldownResolveGeneration then return end
        if InCombat() then
            DeferEllesmereCooldownResolve()
            return
        end
        local acquired, deferred = refreshEllesmereCooldownAnchor()
        if acquired or deferred then
            ellesmereCooldownResolvePending = false
            return
        end
        index = index + 1
        local delay = SKIRON_RETRY_DELAYS[index]
        if delay and C_Timer and C_Timer.After then
            C_Timer.After(delay, run)
        else
            ellesmereCooldownResolvePending = false
        end
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

local function RegisterEllesmereCooldownAnchor()
    if IsFrameUsable(ellesmereCooldownActiveSource) then return true end
    if type(_G._ECME_GetBarFrame) ~= "function"
        and not IsAddOnFullyLoaded("EllesmereUICooldownManager") then
        return false
    end
    ScheduleEllesmereCooldownAnchorResolve()
    return true
end

local function RegisterThirdPartyAnchors()
    local arcUI = RegisterArcUIAnchor()
    local skiron = RegisterSkironAnchorProxy()
    local coolinator = RegisterCoolinatorAnchor()
    local ellesmere = RegisterEllesmereCooldownAnchor()
    return arcUI or skiron or coolinator or ellesmere
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
        local showCooldownConsent = cooldownConsentPromptAfterCombat
        local refreshArcUI = arcUIRefreshAfterCombat
        local refreshSkiron = skironSourceHookPending or skironProxyRefreshAfterCombat
        local refreshCoolinator = coolinatorSourceHookPending or coolinatorRefreshAfterCombat
        local refreshEllesmere = ellesmereCooldownRefreshAfterCombat
        cooldownConsentPromptAfterCombat = false
        if not showCooldownConsent and not refreshArcUI and not refreshSkiron
            and not refreshCoolinator and not refreshEllesmere then return end
        arcUIRefreshAfterCombat = false
        skironSourceHookPending = false
        skironProxyRefreshAfterCombat = false
        coolinatorSourceHookPending = false
        coolinatorRefreshAfterCombat = false
        ellesmereCooldownRefreshAfterCombat = false
        if refreshArcUI then refreshArcUIAnchor(true) end
        if refreshSkiron then refreshSkironAnchorProxy(nil, false, true) end
        if refreshCoolinator then refreshCoolinatorAnchor() end
        if refreshEllesmere then ScheduleEllesmereCooldownAnchorResolve() end
        if showCooldownConsent then MaybeShowCooldownConsent() end
        return
    end
    if event == "ADDON_LOADED" then
        if not AUTOMATIC_COOLDOWN_ADDON_IDS[addon] then return end
        RefreshAutomaticCooldownProvider(true)
        MaybeShowCooldownConsent()
        if addon == "ArcUI" then
            RegisterArcUIAnchor()
        elseif addon == "SkironCooldownManager" then
            RegisterSkironAnchorProxy()
        elseif addon == "Coolinator" then
            RegisterCoolinatorAnchor()
        elseif addon == "EllesmereUICooldownManager" then
            RegisterEllesmereCooldownAnchor()
        end
        return
    end
    RefreshAutomaticCooldownProvider(true)
    MaybeShowCooldownConsent()
    RegisterThirdPartyAnchors()
    if event == "PLAYER_LOGIN" then ScheduleMissingCooldownAnchorWarning() end
end)

RefreshAutomaticCooldownProvider(false)
RegisterThirdPartyAnchors()
