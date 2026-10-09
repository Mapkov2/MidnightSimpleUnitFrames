-- rc1_b_smoke.lua <repoRoot> <flavor>
--
-- rc1 package B: secrets, combat-state edges and profile apply. Every case
-- loads the shipped files; the world cases boot the client's whole core and
-- Options graph (tools/tests/client_world.lua), the secret cases run under the
-- strict secrets helper (tools/tests/classpower_secrets.lua Watch, strict).
--   1. DR2-1 Features/Gameplay/MSUF_Feature_GameplayRuntime.lua: the Combat
--      Timer starts on the PLAYER_REGEN_DISABLED dispatch, while
--      InCombatLockdown() still answers false; it reads 0:01 one second in and
--      a locked timer is shown from the first frame.
--   2. Crosshair (same file): a secret personal-nameplate height
--      (GetHeight is SecretWhenAnchoringSecret on 12.1.5 and Forever) keeps
--      the centered anchor instead of doing arithmetic on it.
--   3. C04-K1 Features/Gameplay/MSUF_Feature_ArenaMatch.lua and
--      Features/Telemetry/MSUF_Analytics.lua: their PLAYER_REGEN_ENABLED
--      handlers act even while the latched MSUF_InCombat mirror is still set
--      (only the group runtime's own handler clears it), and refuse in lockdown.
--   4. DR2-2 Runtime/MSUF_TooltipSpellIDs.lua via State/MSUF_ProfileRuntime.lua
--      (Mainline/Forever only, the file is not in the Classic TOCs): a profile
--      switch never writes "0" for an aura tooltip CVar that MSUF did not turn
--      on; it writes "1" for a profile with the toggle on and "0" only after
--      MSUF itself turned the option on. Login with the toggles off writes
--      nothing.
--   5. LB-3 UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua: the deferred
--      power text drain asks issecretvalue before comparing a cached secret
--      UnitPowerMax / UnitPower with nil.
--   6. UnitFrames/Engine/Elements/MSUF_UF_Visuals_Common.lua SetFrameAlpha: a
--      secret GetAlpha() result is never compared with nil.
--   7. LB-2 MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_PagePreviews.lua:
--      combat starting with the menu on the Boss or Arena page hides the fake
--      aura lanes and gives the real boss/arena auras their alpha back.
--
-- Plain Lua 5.1, repo root as arg 1, client flavor as arg 2.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
    return condition
end
local function Case(name, fn)
    local ok, err = pcall(fn)
    if not ok then failures[#failures + 1] = name .. ": raised " .. tostring(err) end
end

local Secrets = assert(loadfile(root .. "/tools/tests/classpower_secrets.lua"))()
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

------------------------------------------------------------------------------
-- World cases (1-4)
------------------------------------------------------------------------------
local world = World.New(root, flavor)
local env, W = world.env, world.widgets
env.MAX_TOTEMS, env.MAX_BOSS_FRAMES = 4, 5
env.TotemFrame = false
env.issecretvalue = Secrets.IsSecret
local cvars = { tooltipShowAuraSpellIDs = "1", tooltipShowAuraCasterNames = "1" }
local cvarWrites = {}
env.GetCVar = function(name) return cvars[name] end
env.GetCVarBool = function(name) return name == "nameplateShowSelf" end
env.SetCVar = function(name, value)
    cvarWrites[#cvarWrites + 1] = tostring(name) .. "=" .. tostring(value)
    cvars[name] = tostring(value)
end
env.C_CVar = { GetCVar = env.GetCVar, SetCVar = env.SetCVar, GetCVarBool = env.GetCVarBool }
local playerPlate
env.C_NamePlate = { GetNamePlateForUnit = function(unit) if unit == "player" then return playerPlate end end }
env.GetCameraZoom = function() return 0 end
world:Boot()
local bootFailure = world:FirstFailure()
assert(not bootFailure, bootFailure and (bootFailure.file .. ": " .. bootFailure.message))

local function FindFrame(name)
    for _, frame in ipairs(W.frames) do
        if rawget(frame, "frameName") == name then return frame end
    end
end
local function BusHandler(event, key)
    local ev = env.MSUF_EventBus.handlers[event]
    local index = ev and ev.index[key]
    return index and ev.list[index].fn or nil
end
-- The client dispatches every frame's OnEvent; one raising handler does not
-- stop the others (harness widgets raise in unrelated renderers).
local function Fire(event, ...)
    for _, frame in ipairs(W.frames) do
        local events, scripts = rawget(frame, "events"), rawget(frame, "scripts")
        local onEvent = scripts and scripts.OnEvent
        if onEvent and events and (events[event] or events["*"]) then pcall(onEvent, frame, event, ...) end
    end
end
local function TakeWrites()
    local list = table.concat(cvarWrites, ",")
    cvarWrites = {}
    return list
end

local Default = { _msufProfileSchema = 600, general = {},
    gameplay = { enableCombatTimer = true, lockCombatTimer = false, enableCombatCrosshair = true } }
local Other = { _msufProfileSchema = 600, general = {}, gameplay = {} }
rawset(env, "MSUF_DB", Default)
rawset(env, "MSUF_GlobalDB", { profiles = { Default = Default, Other = Other },
    char = { ["Tester-Realm"] = { activeProfile = "Default" } }, global = {} })
Fire("ADDON_LOADED", "MidnightSimpleUnitFrames", false)
Fire("PLAYER_LOGIN")
local tooltipCVars = world.core.TooltipSpellIDs ~= nil
if tooltipCVars then
    Check(TakeWrites() == "", "login with the aura tooltip toggles off wrote a tooltip CVar")
end
world.core.MSUF_ApplyGameplayVisuals()

-- 1. Combat Timer at the client's combat edge ------------------------------------
Case("combat timer", function()
    local timerFrame = assert(FindFrame("MSUF_CombatTimerFrame"), "combat timer frame missing")
    local text
    for _, region in ipairs(timerFrame.regions) do
        if region:GetText() == "0:00" then text = region end
    end
    assert(text, "unlocked combat timer did not paint its 0:00 placeholder")
    local onDisabled = assert(BusHandler("PLAYER_REGEN_DISABLED", "MSUF_COMBAT_TIMER"), "timer REGEN_DISABLED")
    local onEnabled = assert(BusHandler("PLAYER_REGEN_ENABLED", "MSUF_COMBAT_TIMER"), "timer REGEN_ENABLED")
    local function Tick(seconds)
        W:AdvanceTime(seconds)
        for _, ticker in ipairs(W.tickers) do
            if not ticker.cancelled then ticker.callback(ticker) end -- the client passes the ticker
        end
    end
    local function Fight(label)
        W.inCombat = false
        onDisabled("PLAYER_REGEN_DISABLED") -- lockdown starts after this dispatch
        W.inCombat = true
        Check(timerFrame:IsShown() == true, label .. ": combat timer hidden at PLAYER_REGEN_DISABLED")
        Tick(1.0)
        Check(text:GetText() == "0:01", label .. ": timer read " .. tostring(text:GetText()) .. " one second in")
        for _ = 2, 10 do Tick(1.0) end
        Check(text:GetText() == "0:10", label .. ": timer read " .. tostring(text:GetText()) .. " ten seconds in")
        W:AdvanceTime(1 / 60)
        W.inCombat = false
        onEnabled("PLAYER_REGEN_ENABLED")
    end
    Fight("unlocked")
    Check(text:GetText() == "0:00", "unlocked timer did not return to 0:00 after combat")
    Default.gameplay.lockCombatTimer = true
    world.core.MSUF_ApplyGameplayVisuals()
    Check(timerFrame:IsShown() == false, "locked timer shown out of combat")
    Fight("locked")
    Check(timerFrame:IsShown() == false, "locked timer stayed shown after combat")
end)

-- 2. Crosshair on a secret personal-nameplate height -----------------------------
Case("crosshair", function()
    local crosshair = assert(FindFrame("MSUF_CombatCrosshairFrame"), "crosshair frame missing")
    local eventFrame = assert(FindFrame("MSUF_CombatCrosshairEventFrame"), "crosshair event frame missing")
    local onEvent = eventFrame.scripts.OnEvent
    playerPlate = env.CreateFrame("Frame", "NamePlate1", env.UIParent)
    local secretHeight = Secrets.New("number")
    playerPlate.GetHeight = function() return secretHeight end
    local runtime = World.Normalize(root .. "/MidnightSimpleUnitFrames/Features/Gameplay/MSUF_Feature_GameplayRuntime.lua")
    local stop = Secrets.Watch(runtime, { strict = true })
    local ok, err = pcall(onEvent, eventFrame, "PLAYER_ENTERING_WORLD")
    local violations = stop()
    Check(ok, "secret nameplate height raised: " .. tostring(err))
    for _, line in ipairs(violations) do Check(false, "secret nameplate height misuse: " .. line) end
    Check(crosshair._msufAnchorTo == env.UIParent and crosshair._msufAnchorOffsetY == -20,
        "secret nameplate height did not keep the centered crosshair anchor")
    playerPlate.GetHeight = function() return 50 end
    onEvent(eventFrame, "PLAYER_ENTERING_WORLD")
    Check(crosshair._msufAnchorTo == playerPlate and crosshair._msufAnchorOffsetY == -48,
        "plain nameplate height no longer anchors the crosshair under the player plate: "
        .. tostring(crosshair._msufAnchorOffsetY))
    playerPlate = nil
    onEvent(eventFrame, "PLAYER_ENTERING_WORLD")
    Check(crosshair._msufAnchorTo == env.UIParent, "crosshair kept a removed nameplate anchor")
end)

-- 3. Latched combat mirror at PLAYER_REGEN_ENABLED ---------------------------------
Case("arena prep regen", function()
    local regen = BusHandler("PLAYER_REGEN_ENABLED", "MSUF_ARENA_MATCH_REGEN")
    local arena = world.core.Client.SupportsUnit("arena1") ~= false
    Check((regen ~= nil) == arena, "arena match REGEN_ENABLED wiring does not follow arena support")
    if not regen then return end
    local asked = 0
    env.GetNumArenaOpponentSpecs = function() asked = asked + 1 return 0 end
    rawset(env, "MSUF_InCombat", true) -- the group runtime's handler has not run yet
    W.inCombat = false
    regen("PLAYER_REGEN_ENABLED")
    Check(asked == 1, "arena prep hand-off skipped at PLAYER_REGEN_ENABLED while the latched mirror was set")
    local before = asked
    W.inCombat = true
    env.MSUF_ArenaMatch_SyncPrepDisplay()
    Check(asked == before, "arena prep display ran in combat lockdown")
    W.inCombat = false
    rawset(env, "MSUF_InCombat", false)
end)

Case("analytics regen", function()
    local Analytics = world.core.Analytics
    if not (Analytics and Analytics.FlushSession) then return end
    local registered = {}
    for _, frame in ipairs(W.frames) do registered[frame] = frame.events.PLAYER_REGEN_ENABLED end
    W.inCombat = true
    Analytics.FlushSession("rc1")
    local deferFrame
    for _, frame in ipairs(W.frames) do
        if frame.events.PLAYER_REGEN_ENABLED and not registered[frame] then deferFrame = frame end
    end
    assert(deferFrame, "analytics did not defer its session in combat lockdown")
    rawset(env, "MSUF_InCombat", true) -- the group runtime's handler has not run yet
    W.inCombat = false
    local ok, err = pcall(deferFrame.scripts.OnEvent, deferFrame, "PLAYER_REGEN_ENABLED")
    Check(ok, "analytics PLAYER_REGEN_ENABLED handler raised: " .. tostring(err))
    Check(not deferFrame.events.PLAYER_REGEN_ENABLED,
        "analytics re-deferred at PLAYER_REGEN_ENABLED while the latched mirror was set")
    rawset(env, "MSUF_InCombat", false)
end)

-- 4. Aura tooltip CVars across profile switches ---------------------------------
Case("tooltip cvars", function()
    if not tooltipCVars then return end
    env.MSUF_UFCore_NotifyConfigChanged = function() end
    env.MSUF_GF_RebuildAll = function() end
    env.MSUF_ClassPower_Apply = function() end
    world.core.Highlight.Refresh = function() end
    env.MSUF_ApplyAllCastbarsAndSync = function() end
    env.MSUF_Castbars_OnSettingsChanged = function() end
    env.MSUF_ApplyPowerBarEmbedLayout_All = function() end
    env.MSUF_UpdateAllFonts_Immediate = function() end
    env.MSUF_ApplyModules = function() end
    local function Switch(name)
        local ok, err = pcall(env.MSUF_SwitchProfile, name)
        assert(ok, "profile switch to " .. name .. " raised: " .. tostring(err))
        return TakeWrites()
    end
    local function Toggle(on)
        Other.general.tooltipShowAuraSpellIDs = on
        Other.general.tooltipShowAuraCasterNames = on
        env.MSUF_ApplyTooltipSpellIDs(on)
        env.MSUF_ApplyTooltipCasterNames(on)
        return TakeWrites()
    end
    TakeWrites()
    Check(Switch("Other") == "", "profile switch (toggles off) zeroed aura tooltip CVars MSUF never set")
    Check(cvars.tooltipShowAuraSpellIDs == "1" and cvars.tooltipShowAuraCasterNames == "1",
        "externally enabled aura tooltip CVars lost on a profile switch")
    Check(Toggle(true) == "tooltipShowAuraSpellIDs=1,tooltipShowAuraCasterNames=1", "explicit toggle on")
    Check(Switch("Default") == "tooltipShowAuraSpellIDs=0,tooltipShowAuraCasterNames=0",
        "switch to a toggle-off profile kept the CVars MSUF had turned on")
    Check(Switch("Other") == "tooltipShowAuraSpellIDs=1,tooltipShowAuraCasterNames=1",
        "switch to a toggle-on profile did not write the CVars on")
    Check(Toggle(false) == "tooltipShowAuraSpellIDs=0,tooltipShowAuraCasterNames=0", "explicit toggle off")
    Check(Switch("Default") == "", "switch after an explicit toggle off wrote the CVars again")
end)

------------------------------------------------------------------------------
-- Strict secret cases (5-6) and the Menu2 page preview (7)
------------------------------------------------------------------------------
Secrets.Install()
Secrets.GUARD_NAMES.falsy.NotSecretValue = true

-- 5. Deferred power text drain ------------------------------------------------------
Case("power text drain", function()
    local ticker
    _G.C_Timer = {
        NewTicker = function(_, fn) ticker = fn return { Cancel = function() end } end,
        After = function() end,
    }
    local elements = {}
    local UF = {
        RegisterElement = function(name, element) elements[name] = element end,
        FrameVisibleForEvent = function() return true end,
        attachedFrames = {},
    }
    local noop = function() end
    local Text = setmetatable({ floor = math.floor, EMPTY_EVENTS = {}, POWER_EVENTS = {}, POWER_EVENTS_FREQUENT = {} },
        { __index = function() return noop end })
    local runtime = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua"
    assert(loadfile(runtime))("MidnightSimpleUnitFrames", { UFText = Text, UF = UF, Secrets = {} })
    local drained
    local frame = {
        MSUFUnitKey = "target",
        _msufActiveElements = { PowerText = true },
        _msufTextRuntime = {
            powerSlotCount = 1,
            powerNeedsCurrent = true,
            powerNeedsMax = true,
            powerDrain = function(_, unit, power) drained = { unit = unit, power = power } end,
        },
        -- MSUF_UF_Elements_Power.lua keeps a secret maximum on refreshMax.
        targetPowerBar = {
            _msufShown = true,
            _msufPowerValue = Secrets.New("number"),
            _msufPowerValueUnit = "target",
            _msufPowerMax = Secrets.New("number"),
            _msufPowerMaxReady = true,
            _msufPowerMaxUnit = "target",
        },
    }
    UF.attachedFrames[frame] = true
    local stop = Secrets.Watch(runtime, { strict = true })
    elements.PowerText.MarkValueDirty(frame)
    local ok, err
    if ticker then ok, err = pcall(ticker) end
    local violations = stop()
    assert(ticker, "dirty-text ticker was not armed")
    Check(ok, "power text drain raised: " .. tostring(err))
    for _, line in ipairs(violations) do Check(false, "secret cached power misuse: " .. line) end
    Check(drained and drained.unit == "target" and drained.power == nil,
        "secret cached power reached the drain as a plain value")
end)

-- 6. SetFrameAlpha on a secret alpha ----------------------------------------------
Case("frame alpha", function()
    local visuals = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Visuals_Common.lua"
    local ns = { UF = { Clamp01 = function(value, fallback)
        value = tonumber(value) or fallback
        return math.max(0, math.min(1, value))
    end } }
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Secrets.lua"))("MidnightSimpleUnitFrames", ns)
    assert(loadfile(visuals))("MidnightSimpleUnitFrames", ns)
    local SetFrameAlpha = assert(ns.UFVisuals and ns.UFVisuals.SetFrameAlpha, "SetFrameAlpha not exported")
    local current = Secrets.New("number")
    local frame = { _msufLastAlpha = 1, writes = 0 }
    function frame:GetAlpha() return current end
    function frame:SetAlpha() self.writes = self.writes + 1 end
    local stop = Secrets.Watch(visuals, { strict = true })
    local ok, err = pcall(SetFrameAlpha, frame, 1)
    local violations = stop()
    Check(ok, "SetFrameAlpha raised on a secret alpha: " .. tostring(err))
    for _, line in ipairs(violations) do Check(false, "secret alpha misuse: " .. line) end
    Check(frame.writes == 0, "SetFrameAlpha rewrote an unchanged target over a secret alpha")
    current = 0.25
    SetFrameAlpha(frame, 1)
    Check(frame.writes == 1, "SetFrameAlpha no longer repairs a drifted plain alpha")
    current = 1
    SetFrameAlpha(frame, 1)
    Check(frame.writes == 1, "SetFrameAlpha rewrote an unchanged plain alpha")
end)

-- 7. Menu2 Boss/Arena page open when combat starts -------------------------------
-- The real Auras3 edit-mode modules and the real PagePreviews file on generic
-- widgets. InCombatLockdown() is false at PLAYER_REGEN_DISABLED and true
-- afterwards; UnitAffectingCombat("player") is true from REGEN_DISABLED on.
local function PagePreviewWorld()
    local lockdown, affecting = false, false
    local G = {}
    G.InCombatLockdown = function() return lockdown end
    G.UnitAffectingCombat = function() return affecting end
    local timers = {}
    G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end,
        NewTimer = function(_, fn) timers[#timers + 1] = fn return { Cancel = function() end } end }
    local function RunTimers() local list = timers timers = {} for i = 1, #list do list[i]() end end
    local Widget = {}
    local VERBS = { "Set", "Clear", "Enable", "Disable", "Register", "Unregister", "Raise", "Lower", "Stop",
        "Play", "Is", "Get", "Add", "Remove", "Start", "Adjust", "Apply" }
    local noop = function() return nil end
    Widget.__index = function(_, key)
        local method = rawget(Widget, key)
        if method then return method end
        if type(key) == "string" then
            for i = 1, #VERBS do
                local verb = VERBS[i]
                if key:sub(1, #verb) == verb and key:sub(#verb + 1, #verb + 1):match("%u") then return noop end
            end
        end
        return nil
    end
    local function NewWidget(name)
        return setmetatable({ _name = name, _shown = true, _alpha = 1, _scripts = {} }, Widget)
    end
    function Widget:Show() self._shown = true end
    function Widget:Hide() self._shown = false end
    function Widget:IsShown() return self._shown end
    function Widget:SetAlpha(alpha) self._alpha = alpha end
    function Widget:GetAlpha() return self._alpha end
    function Widget:IsForbidden() return false end
    function Widget:GetEffectiveScale() return 1 end
    function Widget:GetFrameLevel() return 1 end
    function Widget:GetWidth() return 200 end
    function Widget:GetHeight() return 40 end
    function Widget:GetSize() return 200, 40 end
    function Widget:SetScript(key, fn) self._scripts[key] = fn end
    function Widget:HookScript(key, fn) self._scripts[key] = fn end
    function Widget:CreateTexture() return NewWidget("texture") end
    function Widget:CreateFontString() return NewWidget("fontstring") end
    function Widget:CreateAnimationGroup() return NewWidget("animation") end
    function Widget:CreateAnimation() return NewWidget("animation") end
    function Widget:GetParent() return nil end
    function Widget:GetCenter() return 0, 0 end
    function Widget:GetLeft() return 0 end
    function Widget:GetRight() return 200 end
    function Widget:GetTop() return 40 end
    function Widget:GetBottom() return 0 end
    function Widget:GetScale() return 1 end
    function Widget:IsMouseEnabled() return false end
    G.CreateFrame = function(_, name) return NewWidget(name or "frame") end
    G.UIParent = NewWidget("UIParent")
    G.MSUF_SetFontChecked = function() end
    G.MSUF_MAX_ARENA_FRAMES = 3
    G.MSUF_AuraAnchorOffset = function() return 0, 0 end
    G.MSUF_AuraPaddingInset = function() return 0, 0 end
    G.MSUF_AuraButtonAnchor = function(x, y) return (y > 0 and "BOTTOM" or "TOP") .. (x > 0 and "LEFT" or "RIGHT") end
    local namespace = { ExportPublic = function(key, value) G[key] = value return value end, UF = { frames = {} } }
    G.MSUF_NS = namespace
    local units = {}
    for i = 1, 5 do units[#units + 1] = "boss" .. i end
    for i = 1, 3 do units[#units + 1] = "arena" .. i end
    for _, unit in ipairs(units) do
        local frame = NewWidget("MSUF_" .. unit)
        frame.MSUFUnitKey = unit
        local element = { _alpha = 1 }
        function element:SetAlpha(alpha) self._alpha = alpha end
        function element:GetAlpha() return self._alpha end
        function element:IsForbidden() return false end
        frame.Auras = element
        namespace.UF.frames[unit] = frame
    end
    namespace.UF.GetFrame = function(unit) return namespace.UF.frames[unit] end
    G.MSUF_DB = { auras3 = { enabled = true, showBoss = true, showArena = true, shared = {}, perUnit = {} } }
    local A3 = { CUSTOM_CONTAINER_COUNT = 4, PRESET_CUSTOM_CONTAINER_INDEX = 4,
        IconShape = { IconZoomInset = function() return 0.07 end } }
    namespace.MSUF_Auras3 = A3
    G._G = G
    setmetatable(G, { __index = _G })
    local function Load(relative)
        local chunk = assert(loadfile(root .. "/" .. relative))
        setfenv(chunk, G)
        chunk("MidnightSimpleUnitFrames", namespace)
    end
    for _, part in ipairs({ "Config", "Layout", "Drag", "Preview" }) do
        Load("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_EditMode_" .. part .. ".lua")
    end
    Load("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_EditMode.lua")
    RunTimers()
    local M = { KeySetFromWords = function(words)
        local set = {}
        for word in words:gmatch("%S+") do set[word] = true end
        return set
    end, EnsureDB = function() return G.MSUF_DB end, UnitPage = {} }
    namespace.MSUF2 = M
    M.frame = NewWidget("MSUF2_Window")
    M.UnitPage.SetBossPagePreviewActive = function(active) G.MSUF2_BossUnitframePreviewActive = active or nil end
    M.UnitPage.SetArenaPagePreviewActive = function(active) G.MSUF2_ArenaUnitframePreviewActive = active or nil end
    Load("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_PagePreviews.lua")
    local view = { M = M, G = G, RunTimers = RunTimers }
    function view.Combat(state, locked) affecting, lockdown = state, locked end
    function view.Lanes(prefix)
        local shown = 0
        for unit, byUnit in pairs(A3.EditMode.groups or {}) do
            if unit:sub(1, #prefix) == prefix then
                for _, group in pairs(byUnit) do if group:IsShown() then shown = shown + 1 end end
            end
        end
        return shown
    end
    function view.RealAlpha(prefix)
        local hidden = 0
        for unit, frame in pairs(namespace.UF.frames) do
            if unit:sub(1, #prefix) == prefix and frame.Auras._alpha ~= 1 then hidden = hidden + 1 end
        end
        return hidden
    end
    return view
end

for _, page in ipairs({ { key = "uf_boss", prefix = "boss", flag = "MSUF2_BossPageAuraPreviewActive" },
    { key = "uf_arena", prefix = "arena", flag = "MSUF2_ArenaPageAuraPreviewActive" } }) do
    Case("page preview " .. page.prefix, function()
        local view = PagePreviewWorld()
        local M, G = view.M, view.G
        M.activeKey = page.key
        M.SyncBossPagePreviewForKey(page.key, true)
        view.RunTimers()
        assert(G[page.flag] == true and view.Lanes(page.prefix) > 0 and view.RealAlpha(page.prefix) > 0,
            page.prefix .. " page did not open its aura preview")
        -- PLAYER_REGEN_DISABLED: Menu2 hides itself; OnHide resets the cache and syncs.
        view.Combat(true, false)
        M.frame:Hide()
        M.ResetBossPagePreviewCache()
        M.SyncBossPagePreviewForKey(nil, true)
        view.RunTimers()
        Check(G[page.flag] == nil, page.prefix .. " page aura preview flag survived combat start")
        Check(view.Lanes(page.prefix) == 0, page.prefix .. " fake aura lanes stayed shown after combat start")
        Check(view.RealAlpha(page.prefix) == 0, page.prefix .. " real auras stayed at alpha 0 after combat start")
        view.Combat(true, true)
        view.RunTimers()
        view.Combat(false, false)
        M.frame:Show()
        M.activeKey = "uf_player"
        M.SyncBossPagePreviewForKey("uf_player", false)
        view.RunTimers()
        Check(view.Lanes(page.prefix) == 0 and view.RealAlpha(page.prefix) == 0,
            page.prefix .. " aura preview did not recover after combat")
    end)
end

if #failures > 0 then
    for _, message in ipairs(failures) do print("FAIL: " .. message) end
    error(("rc1_b_smoke (%s): %d failure(s)"):format(flavor, #failures))
end
print(("rc1_b_smoke (%s): ok"):format(flavor))
