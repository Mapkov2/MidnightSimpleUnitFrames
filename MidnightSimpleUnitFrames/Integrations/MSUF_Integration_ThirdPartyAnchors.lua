local _, MSUF = ...
local FILE = "Integrations/MSUF_Integration_ThirdPartyAnchors.lua"
local Optional, ExportPublic = MSUF.Optional, MSUF.ExportPublic
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
-- WoW Forever, read once from the client model. A harness without MSUF.Client
-- models a client that is not Forever.
local IS_FOREVER = MSUF.Client ~= nil and MSUF.Client.IsForever == true

-- Third-party anchor integration.
-- Tracks the MSUF Suite, ArcUI, Skiron, Coolinator and EllesmereUI stable cooldown anchors after they exist.
-- Integration is deferred in combat and must not take ownership of external addon layouts.
--
-- Foreign symbols this file depends on. Apart from the MSUF Suite entries, none
-- is a documented public API; every read is type-checked and an absent symbol
-- only leaves that provider unregistered, it never errors:
--   MSUFSuite.API.GetCooldownAnchorFrame(viewerName) for the three viewer
--     names in SUITE_COOLDOWN_VIEWERS, through MSUF.SuiteLink
--     (Kernel/MSUF_SuiteLink.lua; an older Suite: MSUFSuite.
--     CooldownManager.GetAnchorFrame)
--     (MSUF_Suite_CooldownManager, LoadOnDemand, Mainline family only): a plain
--     insecure frame covering the Suite's bar of that name, nil while the module
--     or that bar is off. Absent: RegisterSuiteCooldownAnchor returns false
--     unless the addon is loaded, then the retry ladder polls; Classic clients
--     never ask.
--   EventRegistry callback "MSUFSuite.CooldownManager.AnchorChanged": optional;
--     the Suite fires it when its module is enabled or disabled and whenever
--     the Essential frame is (re)created. Without it the OnShow/OnHide/
--     OnSizeChanged observers and ADDON_LOADED still acquire Essential; a
--     Utility or Tracked Buffs bar first shown after the retry ladder waits
--     for the next event or loading screen. The Suite detects this
--     integration by _G.MSUF_GetSuiteCooldownAnchor.
--   ArcUI_Public.GetGroupAnchor("Essential"), .ANCHOR_CHANGED_EVENT (ArcUI):
--     the Essential group anchor frame. Absent: RegisterArcUIAnchor returns
--     false; the watcher retries on ADDON_LOADED "ArcUI".
--   EventRegistry callbacks "ArcUI.AnchorProxy.SizeChanged" and
--     "SkironCooldownManager.AnchorProxy.SizeChanged": provider resize
--     notifications. Without EventRegistry neither provider registers.
--   SCM_GroupAnchorProxy_1, SCM_GroupAnchor_1 (SkironCooldownManager): the
--     proxy and group anchor frames. Absent: the timed retry ladder gives up
--     and MSUF_SkironCooldownAnchor is never created or stays hidden.
--   CoolinatorPrimaryGroupAnchor (Coolinator): stable primary group anchor.
--     Absent: RegisterCoolinatorAnchor returns false unless the addon is
--     loaded, in which case the retry ladder polls for it.
--   _ECME_GetBarFrame("cooldowns") (EllesmereUICooldownManager): accessor for
--     the movable Essential bar container. Absent: RegisterEllesmereCooldownAnchor
--     returns false unless the addon is loaded, then the retry ladder polls.
--   EssentialCooldownViewer, C_CooldownViewer.IsCooldownViewerAvailable,
--     CVarCallbackRegistry / C_CVar "cooldownViewerEnabled" and
--     Enum.CooldownViewerVisibleSetting (Blizzard_CooldownViewer): the
--     fallback "Blizzard" provider. Absent: GetActiveCooldownAnchorProvider
--     returns nil and the missing-anchor warning may show; without
--     C_CooldownViewer the anchor reports itself unsupported until a layout
--     provider is detected.
--   C_AddOns.IsAddOnLoaded / IsAddOnLoaded (Blizzard): provider detection
--     over AUTOMATIC_COOLDOWN_ADDONS; absent, no provider is auto-detected.
local CreateFrame = CreateFrame
local C_AddOns = C_AddOns
local C_Timer = C_Timer
local EventRegistry = EventRegistry
local UIParent = UIParent
local type = type
local issecretvalue = issecretvalue
--- MSUF owners that load after this file (UnitFrames/Engine/MSUF_UF_Factory.lua,
--- ClassPower/MSUF_CP_Controller.lua). A provider that is already present
--- (the Suite loading first) is acquired at login, when the profile exists.
local function RunOptional(name, ...)
    local fn = Optional(name)
    if fn then return fn(...) end
end
-- Every provider frame and CVar accessor here is foreign. The probes check
-- types first; one that still raises reaches the client error handler (there
-- is no protected boundary here).
local format = string.format

local ARCUI_ANCHOR_EVENT = "ArcUI.AnchorProxy.SizeChanged"
local SKIRON_ANCHOR_EVENT = "SkironCooldownManager.AnchorProxy.SizeChanged"
local SKIRON_RETRY_DELAYS = { 0, 0.05, 0.20, 0.60, 1.20, 2.00 }
local SUITE_COOLDOWN_ADDON = "MSUF_Suite_CooldownManager"
local SUITE_ANCHOR_CHANGED_EVENT = "MSUFSuite.CooldownManager.AnchorChanged"
-- The viewer names the Suite stands in for, Essential first. Essential also
-- has third-party providers and its own consumers; Utility and Tracked Buffs
-- ("BuffIcon") follow only the Suite.
local SUITE_ESSENTIAL_VIEWER = "EssentialCooldownViewer"
local SUITE_COOLDOWN_VIEWERS = { SUITE_ESSENTIAL_VIEWER, "UtilityCooldownViewer", "BuffIconCooldownViewer" }
local AUTOMATIC_COOLDOWN_ADDONS = {
    -- First-party: the MSUF Suite wins over every third-party provider.
    { id = SUITE_COOLDOWN_ADDON, label = "MSUF Suite" },
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
local loginReached = false
local skironSourceHookPending = false
local skironProxyRefreshAfterCombat = false
local skironResolveState = { generation = 0 }
local observedSkironSources = setmetatable({}, { __mode = "k" })
local refreshCoolinatorAnchor
local coolinatorSourceHookPending = false
local coolinatorRefreshAfterCombat = false
local coolinatorResolveState = { generation = 0 }
local coolinatorActiveSource
local observedCoolinatorSources = setmetatable({}, { __mode = "k" })
local ellesmereCooldownRefreshAfterCombat = false
local ellesmereCooldownResolveGeneration = 0
local ellesmereCooldownResolvePending = false
local ellesmereCooldownActiveSource
local registeredSuiteCooldown
local refreshSuiteCooldownAnchor
local suiteCooldownSourceHookPending = false
local suiteCooldownRefreshAfterCombat = false
local suiteCooldownResolveState = { generation = 0 }
-- [viewer name] = the acquired Suite frame of that name.
local suiteCooldownActiveSources = {}
-- [frame] = the viewer name its observers refresh.
local observedSuiteCooldownSources = setmetatable({}, { __mode = "k" })
local automaticCooldownProviderId
local automaticCooldownProviderLabel
local automaticCooldownProviderResolved = false
--- Whether this client can host an Essential Cooldown anchor at all.
--- Blizzard ships the Cooldown Manager for Mainline game types only
--- (Blizzard_CooldownViewer.toc: AllowLoadGameType standard, plus camelot on
--- WoW Forever), yet the shared engine exposes the C_CooldownViewer namespace
--- on every current client, Classic Era, TBC and Mists included. The namespace
--- alone therefore proves nothing on a Classic client: the client family
--- decides first, and a layout provider cannot establish support there either.
--- Game/Shared/Initialize.lua resolves exactly that once, as
--- Client.HostsCooldownManager; addons cannot be installed mid-session, so the
--- answer is fixed. Keeping it as a plain upvalue leaves every anchor consumer
--- at a single boolean read and adds no probing to the cold anchor path.
--- A harness that loads this file without the client model models the Mainline
--- client, where only the engine namespace is left to ask about.
local function ClientHostsCooldownManager()
    local client = MSUF.Client
    if client ~= nil then return client.Family == "Mainline" end
    return true
end
local cooldownAnchorClientSupported = ClientHostsCooldownManager()
--- Client.HostsCooldownManager already carries the family, the owning Blizzard
--- addon and the engine namespace, so nothing is asked twice here. A harness
--- without the model keeps the namespace probe for the Mainline client it
--- stands in for.
local cooldownAnchorSupported = MSUF.Client ~= nil
    and MSUF.Client.HostsCooldownManager == true
    or (MSUF.Client == nil and type(C_CooldownViewer) == "table")
local InCombat
local cooldownConsentPromptProviderId
local cooldownConsentPromptAfterCombat = false
local COOLDOWN_CONSENT_POPUP = "MSUF_COOLDOWN_ANCHOR_CONSENT"
local COOLDOWN_CONFIRM_POPUP = "MSUF_COOLDOWN_ANCHOR_CONFIRM"
local COOLDOWN_MISSING_ANCHOR_POPUP = "MSUF_COOLDOWN_ANCHOR_MISSING"
--- The core prompt layer (Shell/UI/MSUF_Widgets.lua); nothing here writes
--- Blizzard's StaticPopupDialogs.
local UI = MSUF.Require("MSUF_UI", FILE)
--- The existing bounded provider acquisition chain can take up to 4.05 seconds.
--- Warn only after it has had time to resolve so login order does not create a
--- false positive for Skiron, Coolinator or EllesmereUI.
local COOLDOWN_MISSING_ANCHOR_WARNING_DELAY = 4.25
local missingAnchorWarningShown = false

local function Tr(text)
    local translate = MSUF.Translate
    if type(translate) == "function" then return translate(text) end
    local L = MSUF.L or MSUF.Require("MSUF_L", FILE)
    return L[text] or text
end

-- The active profile's general table, or nil before a profile exists.
local function GeneralDB()
    local db = MSUF_DB
    return type(db) == "table" and db.general or nil
end

local function IsAddOnFullyLoaded(addonName)
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
    if type(isLoaded) == "function" then
        local loadedOrLoading, loaded = isLoaded(addonName)
        if loaded ~= nil then return loaded == true end
        -- Test/legacy shims may expose the historical single return value.
        return loadedOrLoading == true
    end
    local legacy = IsAddOnLoaded
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

    local editMode = Optional("MSUF_EM2")
    local hud = editMode and editMode.HUD
    if hud and type(hud.RefreshControls) == "function" then hud.RefreshControls(true) end

    local menu = MSUF.MSUF2 or Optional("MSUF2")
    if menu and type(menu.RequestRefresh) == "function" then
        menu.RequestRefresh(nil, "automatic-cooldown-anchor-provider")
    end
end

local function HideCooldownConsentPrompts()
    UI.HidePrompt(COOLDOWN_CONSENT_POPUP)
    UI.HidePrompt(COOLDOWN_CONFIRM_POPUP)
end

local function RefreshAutomaticCooldownProvider(notify)
    local providerId, providerLabel = DetectAutomaticCooldownProvider()
    local changed = automaticCooldownProviderResolved
        and (providerId ~= automaticCooldownProviderId or providerLabel ~= automaticCooldownProviderLabel)
    automaticCooldownProviderResolved = true
    automaticCooldownProviderId = providerId
    automaticCooldownProviderLabel = providerLabel
    -- A supported layout provider can own the anchor without Blizzard's
    -- Cooldown Manager, so a detected provider also establishes support on a
    -- client that could host one.
    if providerId ~= nil and cooldownAnchorClientSupported then cooldownAnchorSupported = true end
    if changed then
        cooldownConsentPromptProviderId = nil
        HideCooldownConsentPrompts()
    end
    if changed and notify ~= false then
        local general = GeneralDB()
        RefreshAutomaticCooldownAnchorConsumers(type(general) == "table" and general.anchorToCooldown == true)
    end
    return providerId, providerLabel, changed
end

function MSUF.GetAutomaticCooldownAnchorProvider()
    if not automaticCooldownProviderResolved then RefreshAutomaticCooldownProvider(false) end
    return automaticCooldownProviderId, automaticCooldownProviderLabel
end

--- Clients without a Cooldown Manager keep the stored preference untouched so
--- a profile stays portable back to a client that has one, but every consumer
--- reads it as off. Nothing is written, nothing is migrated.
function MSUF.IsCooldownAnchorSupported()
    return cooldownAnchorSupported
end

function MSUF.IsCooldownAnchorEnabled(general)
    return cooldownAnchorSupported and type(general) == "table" and general.anchorToCooldown == true or false
end

local function CooldownConsentDecisions(create)
    local globalDB = MSUF_GlobalDB
    if type(globalDB) ~= "table" then
        if not create then return nil end
        globalDB = {}
        ExportPublic("MSUF_GlobalDB", globalDB)
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

-- Keep screen offsets intact so switching the global layout back to
-- independent restores its saved placement. The selected CDM origin is stored
-- once per profile and shared by the compiler and Edit Mode.
local function RememberCooldownLayoutOrigin(db)
    local general = db.general
    if general.cooldownAnchorLayoutY ~= nil then return end
    local player, target = db.player or {}, db.target or {}
    local playerY = tonumber(player.offsetY or player.y) or -180
    local targetY = tonumber(target.offsetY or target.y) or playerY
    general.cooldownAnchorLayoutY = (playerY + targetY) * 0.5
    general.cooldownAnchorLayoutPlayerY = playerY - general.cooldownAnchorLayoutY
    general.cooldownAnchorLayoutTargetY = targetY - general.cooldownAnchorLayoutY
end

function MSUF.SetCooldownAnchorEnabled(enabled, rememberDecision, position)
    local db = MSUF_DB
    if type(db) ~= "table" then return false end
    if type(db.general) ~= "table" then db.general = {} end
    enabled = enabled == true
    local changed = db.general.anchorToCooldown ~= enabled
    if enabled and (position == "TOP" or position == "CENTER" or position == "BOTTOM") then
        changed = changed or db.general.cooldownAnchorPosition ~= position
        db.general.cooldownAnchorPosition = position
        RememberCooldownLayoutOrigin(db)
    end
    db.general.anchorToCooldown = enabled
    MSUF.Castbars.Config.Invalidate()

    local providerId = MSUF.GetAutomaticCooldownAnchorProvider()
    if rememberDecision ~= false and providerId then RememberCooldownConsent(providerId, enabled) end
    cooldownConsentPromptProviderId = nil
    cooldownConsentPromptAfterCombat = false
    HideCooldownConsentPrompts()
    RefreshAutomaticCooldownAnchorConsumers(changed)
    return true, changed
end

local function FirstConsentText(providerLabel)
    return format(Tr("MSUF detected %s."), providerLabel)
        .. "\n\n"
        .. Tr("Choose where the Unit Frame layout attaches to CDM: above, centered or below. Keep independent leaves it unattached.")
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

--- The MSUF Suite lays its Essential row out for a class resource bar sitting
--- directly on it at the row's width, so accepting the Suite provider opts
--- class power into that anchor too. Only while every class power placement key
--- is still at its default (anchor off, Player frame width, no offset): a value
--- the user chose is never overwritten. Returns true when it wrote the keys.
local function AdoptSuiteClassPowerAnchor()
    local db = MSUF_DB
    if type(db) ~= "table" then return false end
    local bars = db.bars
    if bars ~= nil and type(bars) ~= "table" then return false end
    bars = bars or {}
    if (bars.classPowerAnchorToCooldown ~= nil and bars.classPowerAnchorToCooldown ~= false)
        or (bars.classPowerWidthMode ~= nil and bars.classPowerWidthMode ~= "player")
        or (bars.classPowerOffsetX ~= nil and bars.classPowerOffsetX ~= 0)
        or (bars.classPowerOffsetY ~= nil and bars.classPowerOffsetY ~= 0) then
        return false
    end
    db.bars = bars
    bars.classPowerAnchorToCooldown = true
    bars.classPowerWidthMode = "cooldown"
    return true
end

--- The Class Resource page's own source refresh: re-arm the cooldown observers
--- for the new width/anchor mask, then one full class power apply.
local function RefreshAdoptedSuiteClassPower()
    RunOptional("MSUF_EnsureCooldownWidthObservers")
    RunOptional("MSUF_ClassPower_Apply", { full = true, cdm = true })
end

local function ResolveCooldownConsent(data, enabled)
    if type(data) ~= "table" or data.providerId ~= automaticCooldownProviderId then return end
    if InCombat() then return end
    RememberCooldownConsent(data.providerId, enabled)
    -- Written before the layout switch, so its reanchor recompiles the unit
    -- configuration with the class power width source already in place.
    local classPowerAdopted = enabled == true and data.providerId == SUITE_COOLDOWN_ADDON
        and AdoptSuiteClassPowerAnchor()
    MSUF.SetCooldownAnchorEnabled(enabled, false, data.position)
    if classPowerAdopted then RefreshAdoptedSuiteClassPower() end
end

-- Both consent steps store the answer, so they are MSUF-owned prompts: only
-- their buttons or Escape answer them. (Blizzard's generic dialog also cancels
-- when it finds no free dialog frame or another dialog replaces it, which would
-- store a refusal nobody gave.)
local function CanAnswerCooldownConsent()
    return not InCombat()
end

local function ShowFinalCooldownConsent(data)
    if data.providerId ~= automaticCooldownProviderId then return end
    UI.ShowPrompt(COOLDOWN_CONFIRM_POPUP, {
        text = FinalConsentText(data.providerLabel) .. "\n\n"
            .. format(Tr("Selected position: %s."), Tr(data.position == "TOP" and "Above CDM"
                or data.position == "BOTTOM" and "Below CDM" or "Centered on CDM")),
        accept = Tr("Confirm anchoring"), cancel = CANCEL or Tr("Cancel"),
        owned = true, canAnswer = CanAnswerCooldownConsent,
        onAccept = function() ResolveCooldownConsent(data, true) end,
        onCancel = function() ResolveCooldownConsent(data, false) end,
    })
end

local function ShowFirstCooldownConsent(data)
    UI.ShowPrompt(COOLDOWN_CONSENT_POPUP, {
        text = FirstConsentText(data.providerLabel), accept = Tr("Continue"), cancel = Tr("Keep independent"),
        owned = true, canAnswer = CanAnswerCooldownConsent, selectedChoice = data.position,
        choices = { { label = Tr("Above CDM"), value = "TOP" },
            { label = Tr("Centered on CDM"), value = "CENTER" }, { label = Tr("Below CDM"), value = "BOTTOM" } },
        onChoice = function(position) data.position = position end,
        onAccept = function() ShowFinalCooldownConsent(data) end,
        onCancel = function() ResolveCooldownConsent(data, false) end,
    })
end

local function MaybeShowCooldownConsent()
    local providerId, providerLabel = MSUF.GetAutomaticCooldownAnchorProvider()
    -- Consent offers the Cooldown Manager layout; a client that cannot host
    -- the anchor has nothing to ask about.
    if not cooldownAnchorSupported then return false end
    if MSUF.SuiteLink.InstallerBusy() then return false end
    if not providerId or cooldownConsentPromptProviderId == providerId then return false end
    local general = GeneralDB()
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
    local position = general.cooldownAnchorPosition
    if position ~= "TOP" and position ~= "BOTTOM" then position = "CENTER" end
    ShowFirstCooldownConsent({ providerId = providerId, providerLabel = providerLabel, position = position })
    cooldownConsentPromptProviderId = providerId
    return true
end

InCombat = function()
    return MSUF.Util.InCombat()
end

local function IsSecretValue(value)
    return issecretvalue and issecretvalue(value) == true or false
end

local OPTIONAL_FRAME_FLAG_ABSENT = {}

local function ReadOptionalFrameFlag(frame, key)
    local method = frame[key]
    if method == nil then return OPTIONAL_FRAME_FLAG_ABSENT end
    return method(frame)
end

-- Cooldown providers may anchor their public frame to a restricted AuraContainer
-- child. On 12.1 that makes geometry accessors return secret numbers, which must
-- never enter Lua comparisons or arithmetic. Restrictions precede native reads.
local function GetUsableCooldownAnchorSize(frame, requireHeight, requireSetPoint)
    if not frame or IsSecretValue(frame) or frame == UIParent or frame == WorldFrame then
        return nil
    end

    -- Access restrictions are checked before reading geometry. They describe
    -- unavailable input; an exception from an allowed accessor still propagates.
    local forbidden = ReadOptionalFrameFlag(frame, "IsForbidden")
    if IsSecretValue(forbidden) or (forbidden ~= OPTIONAL_FRAME_FLAG_ABSENT and forbidden ~= false) then return nil end
    local canAccess = ReadOptionalFrameFlag(frame, "CanBeAccessedInContext")
    if IsSecretValue(canAccess) or (canAccess ~= OPTIONAL_FRAME_FLAG_ABSENT and canAccess ~= true) then return nil end
    local anchoringRestricted = ReadOptionalFrameFlag(frame, "IsAnchoringRestricted")
    if IsSecretValue(anchoringRestricted) or (anchoringRestricted ~= OPTIONAL_FRAME_FLAG_ABSENT and anchoringRestricted ~= false) then return nil end
    local anchoringSecret = ReadOptionalFrameFlag(frame, "IsAnchoringSecret")
    if IsSecretValue(anchoringSecret) or (anchoringSecret ~= OPTIONAL_FRAME_FLAG_ABSENT and anchoringSecret ~= false) then return nil end
    local legacy = frame._msufLegacyCooldownAnchor
    if IsSecretValue(legacy) or legacy == true then return nil end
    local shown = ReadOptionalFrameFlag(frame, "IsShown")
    if IsSecretValue(shown) or (shown ~= OPTIONAL_FRAME_FLAG_ABSENT and shown ~= true) then return nil end
    local width = frame:GetWidth()
    local height = requireHeight == true and frame:GetHeight() or nil
    local setPoint = requireSetPoint == true and frame.SetPoint or nil
    if IsSecretValue(width) or IsSecretValue(height) or IsSecretValue(setPoint) then return nil end
    if type(width) ~= "number" or width <= 0 then return nil end
    if requireHeight == true and (type(height) ~= "number" or height <= 0) then return nil end
    if requireSetPoint == true and type(setPoint) ~= "function" then return nil end
    return width, height
end

local function ProbeCooldownAnchorScales(frame, targetFrame)
    local sourceScale, targetScale = 1, 1
    local getSourceScale = frame.GetEffectiveScale
    if getSourceScale ~= nil then sourceScale = getSourceScale(frame) end
    if targetFrame then
        local getTargetScale = targetFrame.GetEffectiveScale
        if getTargetScale ~= nil then targetScale = getTargetScale(targetFrame) end
    end
    return sourceScale, targetScale
end

local function GetCooldownAnchorScaledWidth(frame, targetFrame, knownWidth)
    if IsSecretValue(knownWidth) then return nil end
    local width = knownWidth
    if width == nil then width = GetUsableCooldownAnchorSize(frame) end
    if type(width) ~= "number" or width <= 0 then return nil end
    local sourceScale, targetScale = ProbeCooldownAnchorScales(frame, targetFrame)
    if IsSecretValue(sourceScale) or IsSecretValue(targetScale)
        or type(sourceScale) ~= "number" or type(targetScale) ~= "number" then
        return nil
    end
    if sourceScale <= 0 then sourceScale = 1 end
    if targetScale <= 0 then targetScale = 1 end
    return width * sourceScale / targetScale
end

MSUF.GetUsableCooldownAnchorSize = GetUsableCooldownAnchorSize
MSUF.GetCooldownAnchorScaledWidth = GetCooldownAnchorScaledWidth
ExportPublic("MSUF_GetUsableCooldownAnchorSize", GetUsableCooldownAnchorSize)
ExportPublic("MSUF_GetCooldownAnchorScaledWidth", GetCooldownAnchorScaledWidth)

local function IsFrameUsable(frame)
    return GetUsableCooldownAnchorSize(frame, true, true) ~= nil
end

local function ProbeCooldownAnchorObserver(frame)
    return frame._msufLegacyCooldownAnchor,
        ReadOptionalFrameFlag(frame, "CanBeAccessedInContext"),
        ReadOptionalFrameFlag(frame, "IsForbidden"),
        ReadOptionalFrameFlag(frame, "IsAnchoringRestricted"),
        ReadOptionalFrameFlag(frame, "IsAnchoringSecret"),
        frame.HookScript
end

-- A hidden provider has no usable anchor rectangle yet, but it still needs an
-- OnShow observer so acquisition remains event-driven. Keep this separate from
-- IsFrameUsable: observation validates only frame access and the hook method,
-- and never reads or compares foreign geometry.
local function IsFrameObservable(frame)
    if not frame or IsSecretValue(frame) or frame == UIParent or frame == WorldFrame then
        return false
    end
    local legacy, canAccess, forbidden, anchoringRestricted, anchoringSecret, hookScript = ProbeCooldownAnchorObserver(frame)
    if IsSecretValue(legacy) or IsSecretValue(canAccess) or IsSecretValue(forbidden)
        or IsSecretValue(anchoringRestricted) or IsSecretValue(anchoringSecret)
        or IsSecretValue(hookScript) then
        return false
    end
    if legacy == true then return false end
    if canAccess ~= OPTIONAL_FRAME_FLAG_ABSENT and canAccess ~= true then return false end
    if forbidden ~= OPTIONAL_FRAME_FLAG_ABSENT and forbidden ~= false then return false end
    if anchoringRestricted ~= OPTIONAL_FRAME_FLAG_ABSENT and anchoringRestricted ~= false then return false end
    if anchoringSecret ~= OPTIONAL_FRAME_FLAG_ABSENT and anchoringSecret ~= false then return false end
    return type(hookScript) == "function"
end

local function ResolveSkironAnchorSource(preferredFrame, isActiveProxy)
    if isActiveProxy and IsFrameUsable(preferredFrame) then
        return preferredFrame
    end
    local preferredName = preferredFrame and preferredFrame.GetName and preferredFrame:GetName()
    if preferredName == "SCM_GroupAnchor_1" and IsFrameUsable(preferredFrame) then
        return preferredFrame
    end

    local proxy = SCM_GroupAnchorProxy_1
    if IsFrameUsable(proxy) then
        return proxy
    end

    local groupAnchor = SCM_GroupAnchor_1
    if IsFrameUsable(groupAnchor) then
        return groupAnchor
    end
end

local function ResolveCoolinatorAnchorSource()
    local source = CoolinatorPrimaryGroupAnchor
    if IsFrameUsable(source) then return source end
end

local function ResolveArcUIAnchorSource()
    local api = ArcUI_Public
    local getAnchor = api and api.GetGroupAnchor
    local source = type(getAnchor) == "function" and getAnchor("Essential") or nil
    if IsFrameUsable(source) then return source end
end

local function GetEllesmereCooldownAnchorSource()
    local getBarFrame = _ECME_GetBarFrame
    if type(getBarFrame) ~= "function" then return nil end
    local source = getBarFrame("cooldowns")
    do
return source
end
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
    if not IsFrameObservable(source) then return false end
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
    ObserveCoolinatorSource(CoolinatorPrimaryGroupAnchor)
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

--- The MSUF Suite's cooldown manager exists on the Mainline family only (Retail
--- and WoW Forever). Classic clients never ask for it, so the provider stays
--- inert there even if a table of that name exists.
local function GetSuiteCooldownAnchorCandidate(viewerName)
    if not cooldownAnchorClientSupported then return nil end
    return MSUF.SuiteLink.GetCooldownAnchorFrame(viewerName)
end

-- Hook callbacks receive the frame first; it names the bar to refresh.
local function OnSuiteCooldownSourceChanged(source)
    refreshSuiteCooldownAnchor(observedSuiteCooldownSources[source], true)
end

local function ObserveSuiteCooldownSource(source, viewerName)
    if not IsFrameObservable(source) then return false end
    if observedSuiteCooldownSources[source] then return true end
    -- The Suite promises a plain insecure frame; the protected-frame deferral is
    -- kept anyway so a changed contract can never hook in lockdown.
    if InCombat()
        and source.IsProtected and source:IsProtected() then
        suiteCooldownSourceHookPending = true
        if watcher then watcher:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return false
    end
    observedSuiteCooldownSources[source] = viewerName
    source:HookScript("OnSizeChanged", OnSuiteCooldownSourceChanged)
    source:HookScript("OnShow", OnSuiteCooldownSourceChanged)
    source:HookScript("OnHide", OnSuiteCooldownSourceChanged)
    return true
end

local function EnsureSuiteCooldownAnchorSource(viewerName)
    -- Observe the frame the Suite hands out even while it is hidden or not laid
    -- out yet, so its first OnShow/OnSizeChanged acquires it without polling.
    -- A recreated frame is a new identity: it is observed once and "switched".
    local candidate = GetSuiteCooldownAnchorCandidate(viewerName)
    ObserveSuiteCooldownSource(candidate, viewerName)
    local source = IsFrameUsable(candidate) and candidate or nil
    local previousSource = suiteCooldownActiveSources[viewerName]
    local transition = previousSource ~= source
        and (not previousSource and "acquired" or not source and "lost" or "switched")
        or nil
    if transition and InCombat() then
        suiteCooldownRefreshAfterCombat = true
        if watcher then watcher:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return previousSource, false, nil, true
    end
    suiteCooldownActiveSources[viewerName] = source
    return source, transition ~= nil, transition, false
end

local function ObserveSkironSource(source)
    if not IsFrameObservable(source) then return false end
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

-- The MSUF-owned proxy frame over the Skiron anchor; created on first acquire.
local skironAnchorProxy

local function EnsureSkironAnchorProxy(source, isActiveProxy)
    -- Hook both candidates, including a currently hidden proxy. Skiron can
    -- switch back to that proxy with Show() and unchanged size, which does not
    -- guarantee its public size callback will fire.
    ObserveSkironSource(SCM_GroupAnchorProxy_1)
    ObserveSkironSource(SCM_GroupAnchor_1)
    source = ResolveSkironAnchorSource(source, isActiveProxy)
    local proxy = skironAnchorProxy
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
        proxy = PixelLayoutRegion(CreateFrame("Frame", "MSUF_SkironCooldownAnchor", UIParent), true)
        proxy._msufStableAnchorProxy = true
        proxy._msufExternalAnchorCacheKey = "SkironCooldownManager"
        if proxy.EnableMouse then proxy:EnableMouse(false) end
        if proxy.SetAlpha then proxy:SetAlpha(0) end
        skironAnchorProxy = ExportPublic("MSUF_SkironCooldownAnchor", proxy)
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
    local proxy = skironAnchorProxy
    if proxy and proxy.MSUFSkironSource ~= nil and (not proxy.IsShown or proxy:IsShown()) then
        return proxy
    end
end

--- viewerName is one of SUITE_COOLDOWN_VIEWERS; nil asks for Essential, the
--- only bar callers named before Utility and Tracked Buffs followed the Suite.
function MSUF.GetSuiteCooldownAnchor(viewerName)
    local source = suiteCooldownActiveSources[viewerName or SUITE_ESSENTIAL_VIEWER]
    if source and IsFrameUsable(source) then return source end
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
    local registry = CVarCallbackRegistry
    local getCached = registry and registry.GetCVarValueBool
    if type(getCached) == "function" then
        local enabled = getCached(registry, "cooldownViewerEnabled")
        if enabled ~= nil then return enabled == true end
    end

    local cvar = C_CVar
    local getCVarBool = cvar and cvar.GetCVarBool
    if type(getCVarBool) == "function" then
        local enabled = getCVarBool("cooldownViewerEnabled")
        if enabled ~= nil then return enabled == true end
    end

    local legacy = GetCVarBool
    if type(legacy) == "function" then
        local enabled = legacy("cooldownViewerEnabled")
        if enabled ~= nil then return enabled == true end
    end
    return false
end

local function BlizzardEssentialCooldownAnchorActive()
    local api = C_CooldownViewer
    local isAvailable = api and api.IsCooldownViewerAvailable
    if type(isAvailable) ~= "function" then return false end
    local available = isAvailable()
    if available ~= true or not BlizzardCooldownViewerEnabled() then return false end

    local viewer = EssentialCooldownViewer
    if not viewer then return false end
    local visibleEnum = Enum and Enum.CooldownViewerVisibleSetting
    if visibleEnum and viewer.visibleSetting == visibleEnum.Hidden then return false end
    return true
end

--- Returns the configured provider that can own the Essential cooldown anchor.
--- This is intentionally not an IsAddOnLoaded check: disabled providers may be
--- loaded without exposing an anchor, while Coolinator exposes its own anchor
--- with Blizzard's cooldownViewerEnabled CVar disabled.
function MSUF.GetActiveCooldownAnchorProvider()
    local suiteSource = suiteCooldownActiveSources[SUITE_ESSENTIAL_VIEWER]
    if suiteSource then return SUITE_COOLDOWN_ADDON, suiteSource end
    if arcUIAnchor then return "ArcUI", arcUIAnchor end

    local skironProxy = skironAnchorProxy
    if skironProxy and skironProxy.MSUFSkironSource ~= nil then
        return "SkironCooldownManager", skironProxy
    end
    if coolinatorActiveSource then return "Coolinator", coolinatorActiveSource end
    if ellesmereCooldownActiveSource then return "EllesmereUICooldownManager", ellesmereCooldownActiveSource end
    if BlizzardEssentialCooldownAnchorActive() then
        return "Blizzard", EssentialCooldownViewer
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
    return MSUF.Require("MSUF_OpenExactSettingControl", FILE)("general.anchorToCooldown",
        Tr("Follow Blizzard's Essential Cooldowns"), "uf_player")
end

--- WoW Forever characters start at level 1, and Blizzard's Cooldown Manager
--- asks C_CooldownViewer.IsCooldownViewerAvailable() again on every
--- PLAYER_LEVEL_CHANGED, so the client itself can report the manager
--- unavailable for a while. With no layout addon installed this character then
--- has no anchor it could activate, and the login warning would repeat on every
--- login for a state no setting fixes. Only Blizzard's own availability answer
--- (or a missing viewer) is quiet here: a disabled cooldownViewerEnabled option
--- or a hidden viewer still warns.
local function ForeverCooldownManagerUnavailable()
    if not IS_FOREVER or MSUF.GetAutomaticCooldownAnchorProvider() ~= nil then return false end
    local api = C_CooldownViewer
    local isAvailable = api and api.IsCooldownViewerAvailable
    if type(isAvailable) ~= "function" or EssentialCooldownViewer == nil then return true end
    return isAvailable() ~= true
end

local function ShowMissingCooldownAnchorWarning()
    if missingAnchorWarningShown then return false end
    local general = GeneralDB()
    if not MSUF.IsCooldownAnchorEnabled(general) then return false end
    if MSUF.GetActiveCooldownAnchorProvider() then return false end
    if ForeverCooldownManagerUnavailable() then return false end
    missingAnchorWarningShown = true

    -- Blizzard's generic confirmation: Escape and Cancel only close it.
    UI.ShowPrompt(COOLDOWN_MISSING_ANCHOR_POPUP, {
        text = MissingCooldownAnchorWarningText(), accept = "|cff40ff80" .. Tr("Fix now") .. "|r",
        cancel = CANCEL or Tr("Cancel"), onAccept = OpenCooldownAnchorSetting,
    })
    return true
end

local function ScheduleMissingCooldownAnchorWarning()
    local general = GeneralDB()
    if not MSUF.IsCooldownAnchorEnabled(general) then return end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(COOLDOWN_MISSING_ANCHOR_WARNING_DELAY, ShowMissingCooldownAnchorWarning)
    else
        ShowMissingCooldownAnchorWarning()
    end
end

-- Legacy globals that forward to the namespace function of the same name. The
-- namespace function is looked up per call, so a replaced one is still honored.
local FORWARDED_ANCHOR_GLOBALS = {
    "GetAutomaticCooldownAnchorProvider", "IsCooldownAnchorEnabled", "IsCooldownAnchorSupported",
    "GetCooldownAnchorConsentDecision", "SetCooldownAnchorEnabled", "GetSkironCooldownAnchorProxy",
    "GetSuiteCooldownAnchor", "GetCoolinatorCooldownAnchor", "GetEllesmereCooldownAnchor",
    "GetArcUICooldownAnchor", "GetActiveCooldownAnchorProvider",
}
local function ForwardToNamespace(name)
    ExportPublic("MSUF_" .. name, function(...) return MSUF[name](...) end)
end
for index = 1, #FORWARDED_ANCHOR_GLOBALS do ForwardToNamespace(FORWARDED_ANCHOR_GLOBALS[index]) end

-- Re-places what is anchored to one viewer name (unit and group frames; for
-- Essential also class power) through the Factory's coalesced cold refresh.
-- False while the Factory is not loaded.
local function ScheduleCooldownAnchorConsumers(viewerName)
    local UF = MSUF.UF
    local factory = UF and UF.Factory
    if factory and type(factory.ScheduleExternalAnchorRefresh) == "function" then
        factory.ScheduleExternalAnchorRefresh(viewerName)
        return true
    elseif factory and type(factory.RefreshExternalAnchor) == "function" then
        factory.RefreshExternalAnchor(viewerName)
        return true
    end
    return false
end

local function RefreshEssentialCooldownAnchorConsumers(transition)
    if transition ~= "acquired" and transition ~= "lost" and transition ~= "switched" and transition ~= "changed" then return end
    if transition == "acquired" or transition == "switched" then
        UI.HidePrompt(COOLDOWN_MISSING_ANCHOR_POPUP)
    end
    local factoryHandled = ScheduleCooldownAnchorConsumers("EssentialCooldownViewer")

    local db = MSUF_DB
    local bars = db and db.bars
    if not factoryHandled and bars and bars.classPowerAnchorToCooldown == true
        and bars.classPowerWidthMode ~= "cooldown" then
        RunOptional("MSUF_ClassPower_RefreshLayout")
    end
end

-- Shared acquired/lost/switched follow-up for every provider. A source
-- transition re-arms the width observers and notifies the anchor consumers
-- once with that transition, a same-source resize requests one cold anchor
-- snapshot instead, and either schedules the shared cooldown width refresh.
local function NotifyCooldownAnchorTransition(changed, transition, sizeChanged)
    if changed then
        RunOptional("MSUF_EnsureCooldownWidthObservers", true)
        RefreshEssentialCooldownAnchorConsumers(transition)
    elseif sizeChanged == true then
        RefreshEssentialCooldownAnchorConsumers("changed")
    end
    if changed or sizeChanged == true then
        RunOptional("MSUF_ScheduleCooldownWidthRefresh", "EssentialCooldownViewer", false, true)
    end
end

-- Utility and Tracked Buffs follow only the Suite and have none of Essential's
-- own consumers (missing-anchor prompt, class power anchor). A new, lost or
-- switched frame re-arms the width observers, then refreshes that name's
-- anchored frames and width modes once; a resize is the width observer's job.
local function NotifySuiteViewerTransition(viewerName, changed)
    if not changed then return end
    RunOptional("MSUF_EnsureCooldownWidthObservers", true)
    ScheduleCooldownAnchorConsumers(viewerName)
    RunOptional("MSUF_ScheduleCooldownWidthRefresh", viewerName, false, true)
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
    NotifyCooldownAnchorTransition(transition ~= nil, transition, sizeChanged)
    return source ~= nil
end

refreshSkironAnchorProxy = function(source, isActiveProxy, sizeChanged)
    local proxy, changed, transition, deferred = EnsureSkironAnchorProxy(source, isActiveProxy)
    if deferred then return proxy ~= nil end
    NotifyCooldownAnchorTransition(changed, transition, sizeChanged)
    return proxy ~= nil
end

refreshCoolinatorAnchor = function(sizeChanged)
    local source, changed, transition, deferred = EnsureCoolinatorAnchorSource()
    if deferred then return source ~= nil end
    NotifyCooldownAnchorTransition(changed, transition, sizeChanged)
    return source ~= nil
end

refreshSuiteCooldownAnchor = function(viewerName, sizeChanged)
    local source, changed, transition, deferred = EnsureSuiteCooldownAnchorSource(viewerName)
    if deferred then return source ~= nil end
    if viewerName == SUITE_ESSENTIAL_VIEWER then
        NotifyCooldownAnchorTransition(changed, transition, sizeChanged)
    else
        NotifySuiteViewerTransition(viewerName, changed)
    end
    return source ~= nil
end

-- Every Suite bar MSUF follows, Essential first. True once all are acquired,
-- so the retry ladder runs all its steps while a Suite bar is switched off.
local function refreshSuiteCooldownAnchors(sizeChanged)
    local all = true
    for i = 1, #SUITE_COOLDOWN_VIEWERS do
        all = refreshSuiteCooldownAnchor(SUITE_COOLDOWN_VIEWERS[i], sizeChanged) and all
    end
    return all
end

local function refreshEllesmereCooldownAnchor()
    local source, changed, transition, deferred = EnsureEllesmereCooldownAnchorSource()
    if deferred then return source ~= nil, true end
    NotifyCooldownAnchorTransition(changed, transition, nil)
    return source ~= nil, false
end

-- One bounded retry ladder: try now, then after each SKIRON_RETRY_DELAYS step until
-- refresh() reports success. A newer ladder on the same state supersedes this one.
local function RunAnchorResolveLadder(state, refresh)
    state.generation = state.generation + 1
    local generation = state.generation
    local index = 1
    local function run()
        if generation ~= state.generation then return end
        if refresh() then return end
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

local function ScheduleSkironAnchorResolve()
    RunAnchorResolveLadder(skironResolveState, refreshSkironAnchorProxy)
end

local function ScheduleCoolinatorAnchorResolve()
    RunAnchorResolveLadder(coolinatorResolveState, refreshCoolinatorAnchor)
end

local function ScheduleSuiteCooldownAnchorResolve()
    RunAnchorResolveLadder(suiteCooldownResolveState, refreshSuiteCooldownAnchors)
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
    local api = ArcUI_Public
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
    if not CoolinatorPrimaryGroupAnchor then
        local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
        if type(isLoaded) ~= "function" or not isLoaded("Coolinator") then return false end
    end
    ScheduleCoolinatorAnchorResolve()
    return true
end

local function RegisterEllesmereCooldownAnchor()
    if IsFrameUsable(ellesmereCooldownActiveSource) then return true end
    if type(_ECME_GetBarFrame) ~= "function"
        and not IsAddOnFullyLoaded("EllesmereUICooldownManager") then
        return false
    end
    ScheduleEllesmereCooldownAnchorResolve()
    return true
end

local function OnSuiteCooldownAnchorChanged()
    refreshSuiteCooldownAnchors(true)
end

local function RegisterSuiteCooldownAnchor()
    if not cooldownAnchorClientSupported then return false end
    if not MSUF.SuiteLink.HasCooldownAnchor() and not IsAddOnFullyLoaded(SUITE_COOLDOWN_ADDON) then
        return false
    end
    -- The Suite's change notification is optional; the frame observers and the
    -- retry ladder below acquire the anchor without it.
    if not registeredSuiteCooldown and EventRegistry
        and type(EventRegistry.RegisterCallback) == "function" then
        EventRegistry:RegisterCallback(SUITE_ANCHOR_CHANGED_EVENT, OnSuiteCooldownAnchorChanged, "MidnightSimpleUnitFrames")
        registeredSuiteCooldown = true
    end
    ScheduleSuiteCooldownAnchorResolve()
    return true
end

local function RegisterThirdPartyAnchors()
    if not loginReached then return false end
    local suite = RegisterSuiteCooldownAnchor()
    local arcUI = RegisterArcUIAnchor()
    local skiron = RegisterSkironAnchorProxy()
    local coolinator = RegisterCoolinatorAnchor()
    local ellesmere = RegisterEllesmereCooldownAnchor()
    return suite or arcUI or skiron or coolinator or ellesmere
end

MSUF.RegisterThirdPartyAnchors = RegisterThirdPartyAnchors

watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(self, event, addon)
    if event == "PLAYER_LOGIN" then loginReached = true end
    if not loginReached then return end
    if event == "PLAYER_REGEN_ENABLED" then
        if InCombat() then return end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        local showCooldownConsent = cooldownConsentPromptAfterCombat
        local refreshSuite = suiteCooldownSourceHookPending or suiteCooldownRefreshAfterCombat
        local refreshArcUI = arcUIRefreshAfterCombat
        local refreshSkiron = skironSourceHookPending or skironProxyRefreshAfterCombat
        local refreshCoolinator = coolinatorSourceHookPending or coolinatorRefreshAfterCombat
        local refreshEllesmere = ellesmereCooldownRefreshAfterCombat
        cooldownConsentPromptAfterCombat = false
        if not showCooldownConsent and not refreshSuite and not refreshArcUI and not refreshSkiron
            and not refreshCoolinator and not refreshEllesmere then return end
        suiteCooldownSourceHookPending = false
        suiteCooldownRefreshAfterCombat = false
        arcUIRefreshAfterCombat = false
        skironSourceHookPending = false
        skironProxyRefreshAfterCombat = false
        coolinatorSourceHookPending = false
        coolinatorRefreshAfterCombat = false
        ellesmereCooldownRefreshAfterCombat = false
        if refreshSuite then refreshSuiteCooldownAnchors() end
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
        if addon == SUITE_COOLDOWN_ADDON then
            RegisterSuiteCooldownAnchor()
        elseif addon == "ArcUI" then
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

if cooldownAnchorClientSupported and EventRegistry then
    EventRegistry:RegisterCallback("MSUFSuite.Installer.Finished", MaybeShowCooldownConsent, "MidnightSimpleUnitFrames")
end
