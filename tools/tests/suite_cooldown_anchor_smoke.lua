-- MSUF Suite cooldown anchor provider.
--
-- The MSUF Suite's LoadOnDemand cooldown manager (MSUF_Suite_CooldownManager,
-- Mainline family only) hands MSUF a plain frame over its Essential bar through
-- MSUFSuite.CooldownManager.GetAnchorFrame("EssentialCooldownViewer") and may
-- fire EventRegistry "MSUFSuite.CooldownManager.AnchorChanged". This smoke pins:
--
--   1. The provider itself (Integrations/MSUF_Integration_ThirdPartyAnchors.lua)
--      on every client model: first in the automatic provider list, acquire,
--      lost, recreated, retry ladder, ADDON_LOADED, combat deferral, the
--      one-time observers, and complete inertness on Vanilla, TBC and Mists.
--   2. The two-step consent: accepting the Suite provider also anchors class
--      power to the cooldown bar at cooldown width, only while those class
--      power keys are still at their defaults; declining, another provider and
--      the plain setter never touch class power.
--   3. The real ClassPower layout (ClassPower/MSUF_CP_Core.lua): on the Suite's
--      anchor the bar sits on top of the Essential row (BOTTOM -> TOP, same
--      width, hard lock and screen cache on BOTTOM); every other provider keeps
--      TOP -> BOTTOM.
--   4. The real TOC load graph per client: the resolver picks the Suite first
--      on Midnight and WoW Forever, and the Classic clients never ask for it.
--
-- Usage (Lua 5.1):
--   lua tools/tests/suite_cooldown_anchor_smoke.lua <repoRoot>
local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")

local Stubs = assert(loadfile(root .. "/.github/scripts/msuf_test_stubs.lua"))()

local ANCHORS = root .. "/MidnightSimpleUnitFrames/Integrations/MSUF_Integration_ThirdPartyAnchors.lua"
local SUITE_ID = "MSUF_Suite_CooldownManager"
local SUITE_EVENT = "MSUFSuite.CooldownManager.AnchorChanged"
local CONSENT_POPUP = "MSUF_COOLDOWN_ANCHOR_CONSENT"
local CONFIRM_POPUP = "MSUF_COOLDOWN_ANCHOR_CONFIRM"

local function ReadFile(path)
    local handle = assert(io.open(path, "rb"), "missing file " .. path)
    local text = handle:read("*a")
    handle:close()
    return (text:gsub("\r\n", "\n"))
end

local CASES, passed, failures = {}, 0, {}
local function Case(name, run) CASES[#CASES + 1] = { name = name, run = run } end

--------------------------------------------------------------------------
-- 1 + 2. The provider on a stub client
--------------------------------------------------------------------------

-- Client models as MSUF.Client publishes them (Game/Shared/Initialize.lua);
-- section 4 checks the same split against the real model.
local MODELS = {
    Midnight = { Family = "Mainline", Flavor = "Mainline", HostsCooldownManager = true, IsForever = false },
    Forever = { Family = "Mainline", Flavor = "Mainline", HostsCooldownManager = true, IsForever = true },
    Vanilla = { Family = "Classic", Flavor = "Vanilla", HostsCooldownManager = false, IsForever = false },
    TBC = { Family = "Classic", Flavor = "TBC", HostsCooldownManager = false, IsForever = false },
    Mists = { Family = "Classic", Flavor = "Mists", HostsCooldownManager = false, IsForever = false },
}
local MAINLINE_MODELS = { "Midnight", "Forever" }
local CLASSIC_MODELS = { "Vanilla", "TBC", "Mists" }

local function NewRegistry()
    local registry = { callbacks = {} }
    function registry:RegisterCallback(event, callback, owner)
        local list = self.callbacks[event] or {}
        self.callbacks[event] = list
        list[#list + 1] = { callback = callback, owner = owner }
    end
    function registry:TriggerEvent(event, ...)
        local list = self.callbacks[event]
        if not list then return 0 end
        for i = 1, #list do list[i].callback(list[i].owner, ...) end
        return #list
    end
    function registry:Count(event) return self.callbacks[event] and #self.callbacks[event] or 0 end
    return registry
end

-- Loads the real integration file into a fresh stub client.
--   model       MODELS key
--   suite       true: the Suite API exists at load
--   loaded      addon names C_AddOns reports as loaded
--   db          MSUF_DB (default: anchor off, class power defaults)
local function LoadProvider(options)
    options = options or {}
    local env = Stubs.New({ timer = "queue", shown = true, width = 400, height = 36 })
    local h = { env = env, popups = {}, hidden = {}, ensure = 0, schedule = 0, external = {},
        forceReanchor = 0, cpApply = {}, suiteCalls = 0, suiteViewers = {} }

    _G.MSUF_NS = nil
    _G.MSUF_PixelLayoutRegion = nil
    _G.CreateFrame = function(frameType, name, parent, template)
        return env:CreateFrame(frameType, name, parent, template)
    end
    _G.UIParent = env.UIParent
    _G.WorldFrame = env.WorldFrame
    _G.C_Timer = env:BuildTimerLibrary()
    _G.InCombatLockdown = function() return env:IsInCombat() end
    _G.issecretvalue = nil
    _G.ArcUI_Public, _G.SCM_GroupAnchorProxy_1, _G.SCM_GroupAnchor_1 = nil, nil, nil
    _G.CoolinatorPrimaryGroupAnchor, _G._ECME_GetBarFrame = nil, nil
    _G.C_CooldownViewer, _G.EssentialCooldownViewer, _G.CVarCallbackRegistry = nil, nil, nil
    _G.C_CVar, _G.GetCVarBool, _G.Enum = nil, nil, nil
    _G.MSUF_EM2, _G.MSUF2, _G.MSUF_OpenExactSettingControl = nil, nil, nil
    _G.MSUF_ClassPower_RefreshLayout = nil

    h.loaded = {}
    for _, name in ipairs(options.loaded or {}) do h.loaded[name] = true end
    _G.C_AddOns = { IsAddOnLoaded = function(name) return h.loaded[name] == true, h.loaded[name] == true end }
    _G.IsAddOnLoaded = nil

    h.registry = NewRegistry()
    _G.EventRegistry = h.registry

    h.frame = env:CreateFrame("Frame", "MSUFSuiteEssentialAnchor", env.UIParent)
    h.suite = {
        CooldownManager = {
            GetAnchorFrame = function(viewerName)
                h.suiteCalls = h.suiteCalls + 1
                h.suiteViewers[#h.suiteViewers + 1] = viewerName
                if viewerName ~= "EssentialCooldownViewer" then return nil end
                return h.frame
            end,
        },
    }
    _G.MSUFSuite = options.suite and h.suite or nil

    _G.StaticPopupDialogs = {}
    _G.StaticPopup_Show = function(name, text, _, data)
        h.popups[#h.popups + 1] = { name = name, text = text, data = data }
        return {}
    end
    _G.StaticPopup_Hide = function(name) h.hidden[#h.hidden + 1] = name end
    _G.MSUF_DB = options.db or { general = { anchorToCooldown = false },
        bars = { classPowerWidthMode = "player", classPowerOffsetX = 0, classPowerOffsetY = 0 } }
    _G.MSUF_GlobalDB = options.globalDB or {}

    _G.MSUF_EnsureCooldownWidthObservers = function() h.ensure = h.ensure + 1 end
    _G.MSUF_ScheduleCooldownWidthRefresh = function() h.schedule = h.schedule + 1 end
    _G.MSUF_ClassPower_Apply = function(opts) h.cpApply[#h.cpApply + 1] = opts end

    local ns = {
        Client = MODELS[options.model or "Midnight"],
        UF = {
            spawned = true,
            Factory = {
                ScheduleExternalAnchorRefresh = function(name) h.external[#h.external + 1] = name end,
                ForceReanchor = function()
                    h.forceReanchor = h.forceReanchor + 1
                    local bars = _G.MSUF_DB and _G.MSUF_DB.bars
                    h.widthModeAtReanchor = bars and bars.classPowerWidthMode
                end,
            },
        },
    }
    h.ns = ns
    assert(loadfile(ANCHORS))("MidnightSimpleUnitFrames", ns)
    for i = 1, #env.frames do
        local frame = env.frames[i]
        if frame.events.ADDON_LOADED and frame.events.PLAYER_LOGIN then h.watcher = frame end
    end
    assert(h.watcher and h.watcher.scripts.OnEvent, "the anchor watcher was not installed")
    return h
end

local function Fire(h, event, ...)
    h.watcher.scripts.OnEvent(h.watcher, event, ...)
end

local function Active(h)
    return h.ns.GetActiveCooldownAnchorProvider()
end

local function PopupNamed(h, name)
    for i = #h.popups, 1, -1 do
        if h.popups[i].name == name then return h.popups[i] end
    end
end

-- Accept (or decline) the two-step consent exactly like the dialog buttons do.
local function AnswerConsent(h, acceptFirst, acceptSecond)
    local first = assert(PopupNamed(h, CONSENT_POPUP), "the first consent step was not shown")
    local dialogs = _G.StaticPopupDialogs
    if not acceptFirst then
        dialogs[CONSENT_POPUP].OnCancel(nil, first.data, "clicked")
        return first
    end
    dialogs[CONSENT_POPUP].OnAccept(nil, first.data)
    local second = assert(PopupNamed(h, CONFIRM_POPUP), "the second consent step was not shown")
    assert(second.data == first.data, "the second step lost the provider data")
    if acceptSecond then
        dialogs[CONFIRM_POPUP].OnAccept(nil, second.data)
    else
        dialogs[CONFIRM_POPUP].OnCancel(nil, second.data, "clicked")
    end
    return first
end

Case("provider list: the Suite is the first automatic provider", function()
    local text = ReadFile(ANCHORS)
    local list = assert(text:match("local AUTOMATIC_COOLDOWN_ADDONS = {\n(.-)\n}"), "provider list missing")
    local first = assert(list:match("{ id = ([^,]+), label = \"([^\"]+)\" }"), "provider list has no entry")
    assert(first == "SUITE_COOLDOWN_ADDON", "the first provider entry is " .. tostring(first))
    assert(text:find('local SUITE_COOLDOWN_ADDON = "' .. SUITE_ID .. '"', 1, true), "Suite addon id changed")
    assert(list:find('{ id = SUITE_COOLDOWN_ADDON, label = "MSUF Suite" }', 1, true), "Suite label changed")
    -- With the Suite and a third-party provider both loaded, the Suite is detected.
    local h = LoadProvider({ suite = true, loaded = { "ArcUI", "Coolinator", SUITE_ID } })
    local id, label = h.ns.GetAutomaticCooldownAnchorProvider()
    assert(id == SUITE_ID and label == "MSUF Suite", "detected " .. tostring(id) .. " / " .. tostring(label))
    assert(type(_G.MSUF_GetSuiteCooldownAnchor) == "function", "the Suite detection export is missing")
end)

for _, modelName in ipairs(MAINLINE_MODELS) do
    Case(modelName .. ": acquire at load, one observer set, precedence over third parties", function()
        local h = LoadProvider({ model = modelName, suite = true, loaded = { SUITE_ID } })
        assert(h.registry:Count(SUITE_EVENT) == 1, "the AnchorChanged callback was not registered once")
        assert(h.ns.GetSuiteCooldownAnchor() == nil, "acquired before the retry ladder ran")
        h.env:RunTimers()
        assert(h.suiteViewers[1] == "EssentialCooldownViewer", "asked the Suite for " .. tostring(h.suiteViewers[1]))
        assert(h.ns.GetSuiteCooldownAnchor() == h.frame, "the Suite anchor was not acquired")
        assert(_G.MSUF_GetSuiteCooldownAnchor() == h.frame, "the global export does not return the anchor")
        local id, source = Active(h)
        assert(id == SUITE_ID and source == h.frame, "active provider is " .. tostring(id))
        assert(h.ensure == 1 and #h.external == 1 and h.external[1] == "EssentialCooldownViewer" and h.schedule == 1,
            "acquire did not notify the anchor consumers exactly once")
        -- Login, zoning and ADDON_LOADED run the registration again: still one
        -- callback, one hook set, no new transition.
        Fire(h, "PLAYER_LOGIN")
        Fire(h, "PLAYER_ENTERING_WORLD")
        Fire(h, "ADDON_LOADED", SUITE_ID)
        h.env:RunTimers()
        assert(h.registry:Count(SUITE_EVENT) == 1, "the AnchorChanged callback was registered twice")
        assert(h.ensure == 1 and #h.external == 1, "an unchanged anchor re-notified the consumers")
        local calls = h.suiteCalls
        h.frame.scripts.OnSizeChanged(h.frame)
        assert(h.suiteCalls == calls + 1, "OnSizeChanged was hooked more than once or not at all")
        assert(#h.external == 2 and h.ensure == 1, "a resize must request one cold anchor refresh, no re-arm")
        -- An ArcUI anchor resolved at the same time never outranks the Suite.
        local arc = h.env:CreateFrame("Frame", "ArcAnchor", h.env.UIParent)
        _G.ArcUI_Public = { GetGroupAnchor = function() return arc end }
        h.ns.RegisterThirdPartyAnchors()
        h.env:RunTimers()
        assert(h.ns.GetArcUICooldownAnchor() == arc, "the ArcUI anchor was not resolved")
        assert(Active(h) == SUITE_ID, "ArcUI outranked the Suite")
    end)

    Case(modelName .. ": lost on hide and module off, reacquired on show and recreate", function()
        local h = LoadProvider({ model = modelName, suite = true, loaded = { SUITE_ID } })
        h.env:RunTimers()
        assert(h.ns.GetSuiteCooldownAnchor() == h.frame)
        -- The Suite hides its Essential bar: the OnHide observer drops it.
        h.frame:Hide()
        h.frame.scripts.OnHide(h.frame)
        assert(h.ns.GetSuiteCooldownAnchor() == nil and Active(h) == nil, "a hidden anchor is still active")
        assert(h.ensure == 2, "loss did not re-arm the width observers")
        h.frame:Show()
        h.frame.scripts.OnShow(h.frame)
        assert(h.ns.GetSuiteCooldownAnchor() == h.frame, "OnShow did not reacquire the anchor")
        -- Module off: GetAnchorFrame answers nil and the Suite fires the event.
        local old = h.frame
        h.frame = nil
        assert(h.registry:TriggerEvent(SUITE_EVENT) == 1)
        assert(h.ns.GetSuiteCooldownAnchor() == nil and Active(h) == nil, "module off left the anchor active")
        -- Module on again with a recreated frame: switched to the new identity,
        -- observed once, and the old frame's hooks cannot bring it back.
        local recreated = h.env:CreateFrame("Frame", "MSUFSuiteEssentialAnchor2", h.env.UIParent)
        h.frame = recreated
        h.registry:TriggerEvent(SUITE_EVENT)
        assert(h.ns.GetSuiteCooldownAnchor() == recreated, "the recreated frame was not acquired")
        assert(type(recreated.scripts.OnShow) == "function" and type(recreated.scripts.OnHide) == "function"
            and type(recreated.scripts.OnSizeChanged) == "function", "the recreated frame is not observed")
        old.scripts.OnHide(old)
        assert(h.ns.GetSuiteCooldownAnchor() == recreated, "the old frame's hook replaced the new anchor")
        -- Without the optional event the observers still acquire: frame hidden
        -- and resized to nothing first, then shown with a real size.
        local late = h.env:CreateFrame("Frame", "MSUFSuiteEssentialAnchor3", h.env.UIParent)
        late.width = 0
        h.frame = late
        h.registry:TriggerEvent(SUITE_EVENT)
        assert(h.ns.GetSuiteCooldownAnchor() == nil, "a zero-width frame counted as an anchor")
        assert(type(late.scripts.OnSizeChanged) == "function", "an unusable frame was not observed")
        late.width = 380
        late.scripts.OnSizeChanged(late)
        assert(h.ns.GetSuiteCooldownAnchor() == late, "OnSizeChanged did not acquire the laid-out frame")
    end)

    Case(modelName .. ": the retry ladder polls until the frame is usable", function()
        local h = LoadProvider({ model = modelName, suite = true, loaded = { SUITE_ID } })
        h.frame.width = 0
        h.env:RunTimers(1)
        assert(h.ns.GetSuiteCooldownAnchor() == nil)
        h.frame.width = 410
        h.env:RunTimers()
        assert(h.ns.GetSuiteCooldownAnchor() == h.frame, "the retry ladder never acquired the anchor")
    end)

    Case(modelName .. ": combat defers every transition to PLAYER_REGEN_ENABLED", function()
        local h = LoadProvider({ model = modelName, suite = true, loaded = { SUITE_ID } })
        h.env:RunTimers()
        local ensure, external = h.ensure, #h.external
        h.env:SetCombat(true)
        local old = h.frame
        h.frame = nil
        h.registry:TriggerEvent(SUITE_EVENT)
        assert(h.ns.GetSuiteCooldownAnchor() == old, "a transition was applied in combat")
        assert(h.ensure == ensure and #h.external == external, "consumers were notified in combat")
        assert(h.watcher.events.PLAYER_REGEN_ENABLED == true, "the regen replay was not armed")
        Fire(h, "PLAYER_REGEN_ENABLED")
        assert(h.ns.GetSuiteCooldownAnchor() == old, "PLAYER_REGEN_ENABLED ran while still in combat")
        h.env:SetCombat(false)
        Fire(h, "PLAYER_REGEN_ENABLED")
        assert(h.ns.GetSuiteCooldownAnchor() == nil and Active(h) == nil, "the deferred loss was not replayed")
        assert(h.ensure == ensure + 1 and h.watcher.events.PLAYER_REGEN_ENABLED == nil)
        -- A protected frame appearing in combat is neither hooked nor acquired
        -- until combat ends; then it is hooked once and acquired.
        local protected = h.env:CreateFrame("Frame", "ProtectedSuiteAnchor", h.env.UIParent)
        protected.IsProtected = function() return true end
        h.frame = protected
        h.env:SetCombat(true)
        h.registry:TriggerEvent(SUITE_EVENT)
        assert(protected.scripts.OnShow == nil, "a protected frame was hooked in combat")
        assert(h.ns.GetSuiteCooldownAnchor() == nil, "a protected frame was acquired in combat")
        h.env:SetCombat(false)
        Fire(h, "PLAYER_REGEN_ENABLED")
        assert(type(protected.scripts.OnShow) == "function", "the deferred hook never ran")
        assert(h.ns.GetSuiteCooldownAnchor() == protected, "the deferred acquire never ran")
    end)

    Case(modelName .. ": ADDON_LOADED registers a Suite that loads after MSUF", function()
        local h = LoadProvider({ model = modelName, suite = false })
        assert(h.registry:Count(SUITE_EVENT) == 0 and h.suiteCalls == 0, "registered without the Suite")
        assert(h.ns.GetAutomaticCooldownAnchorProvider() == nil)
        _G.MSUFSuite = h.suite
        h.loaded[SUITE_ID] = true
        Fire(h, "ADDON_LOADED", SUITE_ID)
        assert(h.registry:Count(SUITE_EVENT) == 1, "ADDON_LOADED did not register the callback")
        assert(h.ns.GetAutomaticCooldownAnchorProvider() == SUITE_ID, "the Suite was not detected")
        assert(PopupNamed(h, CONSENT_POPUP) and PopupNamed(h, CONSENT_POPUP).data.providerId == SUITE_ID,
            "the consent prompt did not name the Suite")
        h.env:RunTimers()
        assert(h.ns.GetSuiteCooldownAnchor() == h.frame, "the Suite anchor was not acquired after ADDON_LOADED")
    end)
end

for _, modelName in ipairs(CLASSIC_MODELS) do
    Case(modelName .. ": the provider is inert", function()
        local h = LoadProvider({ model = modelName, suite = true, loaded = { SUITE_ID } })
        Fire(h, "PLAYER_LOGIN")
        Fire(h, "PLAYER_ENTERING_WORLD")
        Fire(h, "ADDON_LOADED", SUITE_ID)
        h.registry:TriggerEvent(SUITE_EVENT)
        h.ns.RegisterThirdPartyAnchors()
        h.env:RunTimers()
        assert(h.suiteCalls == 0, modelName .. " asked the Suite for an anchor")
        assert(h.registry:Count(SUITE_EVENT) == 0, modelName .. " registered the Suite callback")
        assert(h.frame.scripts.OnShow == nil, modelName .. " hooked the Suite frame")
        assert(h.ns.GetSuiteCooldownAnchor() == nil and _G.MSUF_GetSuiteCooldownAnchor() == nil)
        assert(Active(h) == nil and h.ns.IsCooldownAnchorSupported() == false)
        assert(PopupNamed(h, CONSENT_POPUP) == nil, modelName .. " offered the cooldown consent")
        assert(h.ensure == 0 and #h.external == 0, modelName .. " notified cooldown anchor consumers")
    end)
end

-- 2. Consent -------------------------------------------------------------

local function ConsentWorld(db, loaded, suite)
    local h = LoadProvider({ model = "Midnight", suite = suite ~= false, loaded = loaded or { SUITE_ID }, db = db })
    Fire(h, "PLAYER_LOGIN")
    return h
end

Case("consent: accepting the Suite anchors class power at cooldown width", function()
    local h = ConsentWorld()
    local first = AnswerConsent(h, true, true)
    assert(first.data.providerId == SUITE_ID)
    local bars = _G.MSUF_DB.bars
    assert(_G.MSUF_DB.general.anchorToCooldown == true, "the unit frame layout was not anchored")
    assert(h.ns.GetCooldownAnchorConsentDecision(SUITE_ID) == "accepted")
    assert(bars.classPowerAnchorToCooldown == true and bars.classPowerWidthMode == "cooldown",
        "class power was not anchored to the Suite's Essential bar")
    assert(bars.classPowerOffsetX == 0 and bars.classPowerOffsetY == 0, "the class power offsets changed")
    assert(h.forceReanchor == 1 and h.widthModeAtReanchor == "cooldown",
        "the reanchor ran before the class power width source was written")
    assert(h.ensure >= 1 and #h.cpApply == 1 and h.cpApply[1].full == true and h.cpApply[1].cdm == true,
        "class power was not refreshed through the Class Resource page's source path")
end)

Case("consent: fresh bars table (keys never written) counts as defaults", function()
    local h = ConsentWorld({ general = { anchorToCooldown = false } })
    AnswerConsent(h, true, true)
    local bars = _G.MSUF_DB.bars
    assert(type(bars) == "table" and bars.classPowerAnchorToCooldown == true and bars.classPowerWidthMode == "cooldown")
end)

local CUSTOM = {
    { "a custom width mode", { classPowerWidthMode = "custom", classPowerOffsetX = 0, classPowerOffsetY = 0 } },
    { "Utility width", { classPowerWidthMode = "utility" } },
    { "an existing anchor choice", { classPowerAnchorToCooldown = true, classPowerWidthMode = "player" } },
    { "an X offset", { classPowerWidthMode = "player", classPowerOffsetX = 12, classPowerOffsetY = 0 } },
    { "a Y offset", { classPowerOffsetY = -40 } },
}
for _, custom in ipairs(CUSTOM) do
    Case("consent: accepting the Suite keeps " .. custom[1], function()
        local bars = {}
        for key, value in pairs(custom[2]) do bars[key] = value end
        local h = ConsentWorld({ general = { anchorToCooldown = false }, bars = bars })
        AnswerConsent(h, true, true)
        assert(_G.MSUF_DB.general.anchorToCooldown == true, "the unit frame layout was not anchored")
        local after = _G.MSUF_DB.bars
        local keys = { "classPowerAnchorToCooldown", "classPowerWidthMode", "classPowerOffsetX", "classPowerOffsetY" }
        for _, key in ipairs(keys) do
            assert(after[key] == custom[2][key], "consent overwrote " .. key .. " (" .. tostring(after[key]) .. ")")
        end
        assert(#h.cpApply == 0, "class power was refreshed although nothing changed")
    end)
end

Case("consent: declining either step never touches class power", function()
    for _, second in ipairs({ false, true }) do
        local h = ConsentWorld()
        if second then AnswerConsent(h, true, false) else AnswerConsent(h, false) end
        local bars = _G.MSUF_DB.bars
        assert(_G.MSUF_DB.general.anchorToCooldown == false and h.ns.GetCooldownAnchorConsentDecision(SUITE_ID) == "declined")
        assert(bars.classPowerAnchorToCooldown == nil and bars.classPowerWidthMode == "player" and #h.cpApply == 0,
            "declining changed class power")
    end
end)

Case("consent: another provider and the plain setter never touch class power", function()
    local h = ConsentWorld(nil, { "Coolinator" }, false)
    local first = AnswerConsent(h, true, true)
    assert(first.data.providerId == "Coolinator" and _G.MSUF_DB.general.anchorToCooldown == true)
    assert(_G.MSUF_DB.bars.classPowerAnchorToCooldown == nil and _G.MSUF_DB.bars.classPowerWidthMode == "player",
        "accepting Coolinator changed class power")
    local s = LoadProvider({ model = "Midnight", suite = true, loaded = { SUITE_ID } })
    s.ns.SetCooldownAnchorEnabled(true)
    assert(_G.MSUF_DB.general.anchorToCooldown == true and _G.MSUF_DB.bars.classPowerAnchorToCooldown == nil
        and _G.MSUF_DB.bars.classPowerWidthMode == "player", "the Edit Mode/menu setter changed class power")
end)

--------------------------------------------------------------------------
-- 3. The real ClassPower layout
--------------------------------------------------------------------------

local CP_CLEARED_GLOBALS = {
    "__MSUF_ClassPower_Loaded", "MSUF_CP_CONST", "MSUF_CP_CORE_BUILDERS", "MSUF_CP_MODE_BUILDERS",
    "MSUF_CP_FEATURE_BUILDERS", "MSUF_CP_CoreUnitFrame", "MSUF_ClassPowerContainer", "MSUF_player",
    "MSUF_GetEffectiveCooldownFrame", "MSUF_GetUsableCooldownAnchorSize", "MSUF_GetActiveCooldownAnchorProvider",
    "MSUF_CacheUnitFrameScreenPosition", "MSUF_ApplyCachedUnitFrameScreenPosition", "MSUF_CDM_GetScaledWidth",
    "MSUF_IsUnitFramePositionLocked", "MSUF_ClassPower_Apply", "MSUF_ClassPower_RefreshLayout",
    "MSUF_EnsureCooldownWidthObservers", "MSUF_ScheduleCooldownWidthRefresh",
}

-- Same order as the ClassPower block of MidnightSimpleUnitFrames_Mainline.toc.
local CP_LOAD_ORDER = {
    "Libs/MSUFUnitFrames/MSUF_UF_Secrets.lua",
    "ClassPower/MSUF_CP_Constants.lua",
    "Game/Shared/ClassPower/MSUF_CP_TargetCombo.lua",
    "Game/Forever/ClassPower.lua",
    "ClassPower/MSUF_CP_Modes.lua",
    "ClassPower/MSUF_CP_Core.lua",
    "ClassPower/MSUF_CP_AltMana.lua",
    "ClassPower/MSUF_CP_PlayerHP.lua",
    "ClassPower/MSUF_CP_BalanceDruid.lua",
    "ClassPower/MSUF_CP_Ironfur.lua",
    "ClassPower/MSUF_CP_EbonMight.lua",
    "ClassPower/MSUF_CP_NativeAuras.lua",
    "ClassPower/MSUF_CP_Controller_Config.lua",
    "ClassPower/MSUF_CP_Controller_Colors.lua",
    "ClassPower/MSUF_CP_Controller_Surface.lua",
    "ClassPower/MSUF_CP_Controller.lua",
}

local function Upvalue(fn, wanted)
    for i = 1, 255 do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
    end
    error("missing test seam: " .. wanted, 2)
end

-- Boots the real Mainline ClassPower stack for a rogue with combo points and
-- class power anchored to the cooldown bar. `provider` is what the
-- integration reports as the active provider and its source frame.
local function StartClassPower(provider, bars)
    local env = Stubs.New({ timer = "queue", registerGlobalNames = true, time = 100 })
    env:InstallGlobals({ secretValue = true, time = true })
    for i = 1, #CP_CLEARED_GLOBALS do _G[CP_CLEARED_GLOBALS[i]] = nil end
    local t = { env = env, cache = {} }

    env.Methods.RegisterUnitEvent = function(self, event) self.events[event] = true end
    local ns = {}
    local player = env:CreateFrame("Frame", "MSUF_player", UIParent)
    player.shown, player.width, player.height = true, 275, 40
    ns.UF = { GetFrame = function(unit) if unit == "player" then return player end end }
    ns.ExportPublic = function(name, value) _G[name] = value return value end
    _G.MSUF_NS = ns

    function UnitClass() return "Rogue", "ROGUE" end
    function UnitPowerType() return 3 end
    function UnitPower(_, powerType) return powerType == 4 and 2 or 0 end
    function UnitPowerMax(_, powerType) return powerType == 4 and 5 or 100 end
    function UnitPowerDisplayMod() return 1 end
    function UnitHasVehicleUI() return false end
    function GetSpecialization() return 1 end
    function UnitAffectingCombat() return false end
    function wipe(tbl) for key in pairs(tbl) do tbl[key] = nil end return tbl end
    canaccesstable = function() return true end
    MSUF_UF_NormalizeClassPowerShape = function(shape)
        shape = shape and tostring(shape):upper() or "BAR"
        if shape == "" then shape = "BAR" end
        return shape
    end
    MSUF_UF_NormalizeShapeAlign = function(value) return value or "CENTER" end
    MSUF_ApplyResolvedFont = function(region, path, size, flags)
        region:SetFont(path, size, flags)
        return true, path, "requested"
    end
    MSUF_SetFontChecked = function(region, path, size, flags)
        region:SetFont(path, size, flags)
        return true
    end
    MSUF_ResolveFontShadowMetrics = function() return 1, 1, -1 end

    -- The cooldown anchor surface ClassPower reads, as the integration and the
    -- runtime publish it (Integrations/, Runtime/, Libs/MSUFUnitFrames/).
    t.anchor = env:CreateFrame("Frame", nil, UIParent)
    t.anchor.shown, t.anchor.width, t.anchor.height = true, 412, 38
    t.provider = provider
    _G.MSUF_GetEffectiveCooldownFrame = function(name)
        if name == "EssentialCooldownViewer" then return t.anchor end
    end
    _G.MSUF_GetUsableCooldownAnchorSize = function(frame)
        if frame and frame.shown and (frame.width or 0) > 0 then return frame.width, frame.height end
    end
    _G.MSUF_CDM_GetScaledWidth = function(frame) return frame and frame.width end
    _G.MSUF_GetActiveCooldownAnchorProvider = function()
        local id = t.provider
        if id == nil then return nil end
        return id, t.providerSource or t.anchor
    end
    _G.MSUF_CacheUnitFrameScreenPosition = function(frame, key, unit, point)
        t.cache[key .. ":" .. unit] = { point = point, frame = frame }
        return true
    end
    _G.MSUF_ApplyCachedUnitFrameScreenPosition = function(frame, key, unit)
        local cached = t.cache[key .. ":" .. unit]
        if not cached then return false end
        frame:ClearAllPoints()
        frame:SetPoint(cached.point, UIParent, "CENTER", 0, 0)
        frame._msufPositionInitialized = true
        frame._msufHardLockedToUIParent = true
        frame._msufHardLockPoint = cached.point
        return true
    end

    local b = { showClassPower = true, showAltMana = false, playerHPBarEnabled = false,
        classPowerAnchorToCooldown = true, classPowerWidthMode = "cooldown" }
    for key, value in pairs(bars or {}) do b[key] = value end
    MSUF_DB = { general = {}, bars = b }

    local module
    function MSUF_RegisterModule(name, callbacks)
        if name == "ClassPower" then module = callbacks end
    end
    for i = 1, #CP_LOAD_ORDER do
        assert(loadfile(root .. "/MidnightSimpleUnitFrames/" .. CP_LOAD_ORDER[i]))("MidnightSimpleUnitFrames", ns)
    end
    assert(module, "the ClassPower controller did not register")
    t.module = module
    t.CP = Upvalue(Upvalue(module.Enable, "FullRefresh"), "CP")
    module.Enable()
    t.container = assert(t.CP.container, "class power container missing")
    assert(t.CP.visible == true, "rogue combo points did not show the class power bar")
    return t
end

-- The layout reads the live DB and cooldown globals, so the harness table is
-- only passed for readability at the call sites.
local function Relayout(_)
    assert(type(_G.MSUF_ClassPower_RefreshLayout) == "function", "MSUF_ClassPower_RefreshLayout missing")
    _G.MSUF_ClassPower_RefreshLayout()
end

local function ExpectPoint(t, point, relativeTo, relativePoint, x, y, label)
    local c = t.container
    assert(#c.points == 1, label .. ": expected one point, got " .. #c.points)
    local p, rel, relPoint, px, py = c:GetPoint(1)
    assert(p == point and rel == relativeTo and relPoint == relativePoint and px == x and py == y,
        string.format("%s: point %s -> %s %s (%s, %s)", label, tostring(p), tostring(rel and (rel.frameName or rel)),
            tostring(relPoint), tostring(px), tostring(py)))
end

Case("class power: on the Suite anchor the bar sits on top of the Essential row", function()
    local t = StartClassPower(SUITE_ID)
    ExpectPoint(t, "BOTTOM", t.anchor, "TOP", 0, 0, "Suite")
    assert(t.container.width == t.anchor.width, "class power is not as wide as the Essential row: " .. tostring(t.container.width))
    assert(t.container._msufHardLockPoint == "BOTTOM", "hard lock point " .. tostring(t.container._msufHardLockPoint))
    assert(t.container._msufStableExternalAnchor == t.anchor and t.container._msufDirectCooldownAnchor == true)
    assert(t.cache["classpower:classpower"] and t.cache["classpower:classpower"].point == "BOTTOM",
        "the screen cache recorded a different edge than the live anchor")
    -- Offsets keep their meaning: +Y moves the bar up, away from the row.
    MSUF_DB.bars.classPowerOffsetX, MSUF_DB.bars.classPowerOffsetY = 3, 5
    Relayout(t)
    ExpectPoint(t, "BOTTOM", t.anchor, "TOP", 3, 5, "Suite with offsets")
    -- Combat-edge restore from the screen cache keeps the BOTTOM edge.
    t.container._msufPositionInitialized = nil
    t.container._msufHardLockPoint = nil
    t.env:SetCombat(true)
    Relayout(t)
    t.env:SetCombat(false)
    assert(t.container._msufHardLockPoint == "BOTTOM", "the cached restore switched the lock edge to "
        .. tostring(t.container._msufHardLockPoint))
    local p, rel = t.container:GetPoint(1)
    assert(p == "BOTTOM" and rel == UIParent, "the cached restore used " .. tostring(p))
    -- Out of combat with the Suite's bar hidden, the last screen position is
    -- restored on the same BOTTOM edge.
    Relayout(t)
    ExpectPoint(t, "BOTTOM", t.anchor, "TOP", 3, 5, "Suite after combat")
    t.anchor.shown = false
    t.container._msufHardLockPoint = nil
    Relayout(t)
    p, rel = t.container:GetPoint(1)
    assert(p == "BOTTOM" and rel == UIParent and t.container._msufHardLockPoint == "BOTTOM",
        "a hidden Suite bar restored the cached position on " .. tostring(t.container._msufHardLockPoint))
    t.anchor.shown = true
    Relayout(t)
    ExpectPoint(t, "BOTTOM", t.anchor, "TOP", 3, 5, "Suite shown again")
    t.module.Disable()
    t.module.Shutdown()
end)

for _, provider in ipairs({ "Coolinator", "EllesmereUICooldownManager", "ArcUI", "SkironCooldownManager", "Blizzard", false }) do
    Case("class power: " .. tostring(provider or "no provider") .. " keeps the bar under the anchor", function()
        local t = StartClassPower(provider or nil)
        ExpectPoint(t, "TOP", t.anchor, "BOTTOM", 0, 0, tostring(provider))
        assert(t.container._msufHardLockPoint == "TOP")
        assert(t.cache["classpower:classpower"].point == "TOP", "cache edge changed for " .. tostring(provider))
        t.module.Disable()
        t.module.Shutdown()
    end)
end

Case("class power: the Suite id on a different frame keeps the bar under the anchor", function()
    local t = StartClassPower(SUITE_ID)
    t.providerSource = t.env:CreateFrame("Frame", nil, UIParent)
    Relayout(t)
    ExpectPoint(t, "TOP", t.anchor, "BOTTOM", 0, 0, "Suite id, foreign frame")
    -- Switching the provider live flips the edge on the next layout.
    t.providerSource = nil
    Relayout(t)
    ExpectPoint(t, "BOTTOM", t.anchor, "TOP", 0, 0, "Suite again")
    t.provider = "Coolinator"
    Relayout(t)
    ExpectPoint(t, "TOP", t.anchor, "BOTTOM", 0, 0, "back to Coolinator")
    t.module.Disable()
    t.module.Shutdown()
end)

--------------------------------------------------------------------------
-- 4. The real load graph per client
--------------------------------------------------------------------------

local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    Case("boot " .. flavor .. ": resolver and client gate", function()
        local world = World.New(root, flavor)
        local env = world.env
        local registry = NewRegistry()
        setmetatable(registry, { __index = function() return function() end end })
        env.EventRegistry = registry
        local calls = 0
        local frame = world.widgets:CreateFrame("Frame", nil, env.UIParent)
        local arc = world.widgets:CreateFrame("Frame", nil, env.UIParent)
        env.MSUFSuite = { CooldownManager = { GetAnchorFrame = function(viewerName)
            calls = calls + 1
            return viewerName == "EssentialCooldownViewer" and frame or nil
        end } }
        local mainline = not world.client.isClassic
        if mainline then env.ArcUI_Public = { GetGroupAnchor = function() return arc end } end
        world:Boot()
        local failure = world:FirstFailure()
        assert(not failure, flavor .. ": boot failed in " .. tostring(failure and failure.file) .. ": "
            .. tostring(failure and failure.message))
        local ns = world.core
        assert((ns.Client.Family == "Mainline") == mainline, flavor .. ": unexpected client family")
        if mainline then
            assert(ns.GetArcUICooldownAnchor() == arc, flavor .. ": ArcUI was not resolved at load")
            assert(registry:Count(SUITE_EVENT) == 1, flavor .. ": the Suite callback was not registered at load")
            registry:TriggerEvent(SUITE_EVENT)
            assert(calls >= 1 and env.MSUF_GetSuiteCooldownAnchor() == frame, flavor .. ": Suite anchor not acquired")
            assert(env.MSUF_GetActiveCooldownAnchorProvider() == SUITE_ID, flavor .. ": Suite is not the active provider")
            assert(env.MSUF_GetEffectiveCooldownFrame("EssentialCooldownViewer") == frame,
                flavor .. ": the effective cooldown frame is not the Suite's")
            -- The Suite hides its bar: the resolver falls back to ArcUI at once.
            frame:Hide()
            frame.scripts.OnHide(frame)
            assert(env.MSUF_GetEffectiveCooldownFrame("EssentialCooldownViewer") == arc,
                flavor .. ": no fallback to the next provider after the Suite anchor was lost")
            assert(env.MSUF_GetActiveCooldownAnchorProvider() == "ArcUI")
        else
            ns.RegisterThirdPartyAnchors()
            registry:TriggerEvent(SUITE_EVENT)
            world.widgets:RunTimers()
            assert(calls == 0, flavor .. " asked the Suite for an anchor")
            assert(registry:Count(SUITE_EVENT) == 0, flavor .. " registered the Suite callback")
            assert(env.MSUF_GetSuiteCooldownAnchor() == nil)
            assert(env.MSUF_GetEffectiveCooldownFrame("EssentialCooldownViewer") == nil)
        end
    end)
end

--------------------------------------------------------------------------

for _, case in ipairs(CASES) do
    local ok, err = pcall(case.run)
    if ok then
        passed = passed + 1
    else
        failures[#failures + 1] = case.name .. ": " .. tostring(err)
    end
end

if #failures > 0 then
    for i = 1, #failures do io.stderr:write("FAIL " .. failures[i] .. "\n") end
    io.stderr:write(string.format("suite_cooldown_anchor_smoke: %d of %d cases failed\n", #failures, #CASES))
    os.exit(1)
end
print(string.format("PASS MSUF Suite cooldown anchor: %d cases (provider, consent, class power edge, 5 client boots)", passed))
