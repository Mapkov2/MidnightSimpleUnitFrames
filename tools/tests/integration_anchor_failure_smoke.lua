-- Execute the real anchor registration, refresh, callback and retry paths.
local root = assert(arg[1])
local function Run(mode)
    local provider = mode:match("^([^%-]+)")
    local frames, timers, callbacks, reports, registrations = {}, {}, {}, {}, {}
    local broken, calls, combat = mode ~= "control", 0, false
    local combatOnLookup = false
    local env = setmetatable({}, { __index = _G })
    env._G, env.UIParent, env.WorldFrame = env, {}, {}
    env.issecretvalue = function() return false end
    env.MSUF_DB = { general = { anchorToCooldown = false } }
    env.MSUF_GlobalDB = {}
    env.C_AddOns = { IsAddOnLoaded = function() return false, false end }
    env.C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
    env.geterrorhandler = function() return function(message)
        reports[#reports + 1] = message
        if mode == "reporter" then error("foreign error handler failed") end
    end end
    local function Noop() end
    local function Frame()
        local frame = { events = {}, hooks = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:SetScript(_, callback) self.callback = callback end
        function frame:HookScript(event, callback)
            local hook = tonumber(mode:match("hook(%d)"))
            local failEvent = ({ "OnSizeChanged", "OnShow", "OnHide" })[hook]
            if broken and event == failEvent then error("foreign hook failed") end
            self.hooks[event] = callback
            self.hookCalls = self.hookCalls or {}
            self.hookCalls[event] = (self.hookCalls[event] or 0) + 1
        end
        function frame:GetWidth()
            if broken and (mode == "skiron" or mode == "coolinator") then error("foreign geometry failed") end
            return 200
        end
        function frame:GetHeight() return 30 end
        function frame:IsShown() return self.shown ~= false end
        function frame:IsProtected() return false end
        function frame:GetName() return "anchor" end
        frame.SetPoint, frame.ClearAllPoints, frame.SetSize, frame.SetAllPoints = Noop, Noop, Noop, Noop
        frame.Show, frame.Hide, frame.SetFrameStrata, frame.SetFrameLevel = Noop, Noop, Noop, Noop
        frames[#frames + 1] = frame
        return frame
    end
    env.CreateFrame = Frame
    local anchor = Frame()
    env.EventRegistry = { RegisterCallback = function(_, event, callback, owner)
        if broken and mode == "registration" and event == "ArcUI.AnchorProxy.SizeChanged" then
            error("foreign registration failed")
        end
        registrations[event] = (registrations[event] or 0) + 1
        callbacks[event] = function(...) return callback(owner, ...) end
    end }
    local ns = { Client = { Family = "Mainline", HostsCooldownManager = true },
        Util = { InCombat = function() return combat end }, Optional = function() end,
        ExportPublic = function(_, value) return value end, Translate = function(text) return text end }
    ns.Require = function(name)
        if name == "MSUF_PixelLayoutRegion" then return function(frame) return frame end end
        if name == "MSUF_UI" then return { HidePrompt = Noop, ShowPrompt = Noop } end
        error("unexpected dependency " .. name)
    end
    if provider == "suite" then
        env.MSUFSuite = { API = { version = 1,
            IsInstallerPending = function()
                if broken and mode == "suite-consent" then error("foreign Suite consent failed") end
                return false
            end,
            IsInstallerOpen = function() return false end,
            HasCooldownAnchor = function() return true end,
            GetCooldownAnchorFrame = function()
                calls = calls + 1
                if broken and mode == "suite" then error("foreign Suite lookup failed") end
                return anchor
            end } }
    end
    env.ArcUI_Public = { GetGroupAnchor = function()
        calls = calls + 1
        if broken and (mode == "arc" or mode == "reporter") then error("foreign ArcUI lookup failed") end
        return anchor
    end }
    if mode == "ellesmere" then env._ECME_GetBarFrame = function()
        calls = calls + 1
        if broken then error("foreign Ellesmere lookup failed") end
        if combatOnLookup then combat = true end
        return anchor
    end end
    if provider == "skiron" then env.SCM_GroupAnchor_1 = anchor end
    if provider == "coolinator" then env.CoolinatorPrimaryGroupAnchor = anchor end
    local function Load(path)
        local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/" .. path))
        setfenv(chunk, env)("MidnightSimpleUnitFrames", ns)
    end
    Load("Kernel/MSUF_Boundary.lua")
    Load("Kernel/MSUF_SuiteLink.lua")
    Load("Integrations/MSUF_Integration_ThirdPartyAnchors.lua")
    local watcher = assert(frames[2])
    local function Fire(event, addon)
        local ok, message = pcall(watcher.callback, watcher, event, addon)
        assert(ok, mode .. ": provider escaped boundary: " .. tostring(message))
    end
    local function Settle()
        local steps = 0
        while #timers > 0 do
            steps = steps + 1
            assert(steps < 100, "unbounded provider retry")
            local ok, message = pcall(table.remove(timers, 1))
            assert(ok, mode .. ": timer escaped boundary: " .. tostring(message))
        end
        return steps
    end
    Fire("PLAYER_LOGIN")
    assert(registrations["SkironCooldownManager.AnchorProxy.SizeChanged"] == 1,
        mode .. ": failed provider prevented following Skiron registration")
    Settle()
    if mode == "control" then
        assert(#reports == 0 and ns.GetArcUICooldownAnchor() == anchor, "healthy provider control failed")
        return
    end
    assert(#reports > 0, mode .. ": foreign failure was not reported")
    local failures = #reports
    Fire("PLAYER_ENTERING_WORLD")
    Settle()
    assert(#reports > failures, mode .. ": failed provider could not retry")
    local beforeRecovery = #reports
    broken = false
    Fire("ADDON_LOADED", "ArcUI")
    Fire("PLAYER_ENTERING_WORLD")
    Settle()
    local recovered = #reports
    assert(recovered == beforeRecovery, mode .. ": recovery produced unexpected errors: " .. tostring(reports[#reports]))
    assert(ns.GetArcUICooldownAnchor() == anchor, mode .. ": ArcUI did not recover")
    if provider == "suite" then assert(ns.GetSuiteCooldownAnchor() == anchor) end
    if mode == "ellesmere" then assert(ns.GetEllesmereCooldownAnchor() == anchor) end
    if provider == "coolinator" then assert(ns.GetCoolinatorCooldownAnchor() == anchor) end
    if provider == "skiron" then assert(ns.GetSkironCooldownAnchorProxy()) end
    if provider == "suite" or provider == "skiron" or provider == "coolinator" then
        for _, event in ipairs({ "OnSizeChanged", "OnShow", "OnHide" }) do
            assert(anchor.hooks[event] and anchor.hookCalls[event] == 1,
                mode .. ": observer recovery lost or duplicated " .. event)
        end
    end
    assert(registrations["ArcUI.AnchorProxy.SizeChanged"] == 1, "successful registration duplicated")
    assert(registrations["SkironCooldownManager.AnchorProxy.SizeChanged"] == 1, "Skiron registration duplicated")
    callbacks["ArcUI.AnchorProxy.SizeChanged"]("Essential")
    assert(#reports == recovered, "recovered callback still failed")
    if mode == "ellesmere" then
        -- A provider can cross the combat edge inside its accessor. Preserve
        -- the refresh's second result so this deferred ladder stops at once.
        local previous = anchor
        previous.shown = false
        Fire("PLAYER_ENTERING_WORLD")
        anchor, combatOnLookup = Frame(), true
        assert(Settle() < 10, "combat deferral did not stop the resolve ladder")
        assert(ns.GetEllesmereCooldownAnchor() == nil, "combat transition acquired a different source")
        combat, combatOnLookup = false, false
        Fire("PLAYER_REGEN_ENABLED")
        Settle()
        assert(ns.GetEllesmereCooldownAnchor() == anchor, "combat-deferred provider did not recover")
        assert(#reports == recovered, "combat deferral raised")
    end
    -- A provider can break a cached frame after acquisition. Both public
    -- geometry probes and provider getters must leave fallback callers running.
    local getWidth, getScale = anchor.GetWidth, anchor.GetEffectiveScale
    anchor.GetWidth = function() error("foreign cached geometry failed") end
    assert(ns.GetUsableCooldownAnchorSize(anchor) == nil, "cached geometry failure escaped")
    if provider == "suite" then assert(ns.GetSuiteCooldownAnchor() == nil) end
    if provider == "coolinator" then assert(ns.GetCoolinatorCooldownAnchor() == nil) end
    if provider == "ellesmere" then assert(ns.GetEllesmereCooldownAnchor() == nil) end
    anchor.GetWidth = getWidth
    anchor.GetEffectiveScale = function() error("foreign cached scale failed") end
    assert(ns.GetCooldownAnchorScaledWidth(anchor) == nil, "cached scale failure escaped")
    anchor.GetEffectiveScale = getScale
    recovered = #reports
    -- Callback failures are isolated too, and a later callback can recover.
    if mode == "arc" then
        broken = true
        callbacks["ArcUI.AnchorProxy.SizeChanged"]("Essential")
        assert(#reports == recovered + 1, "callback error was not reported")
        broken = false
        callbacks["ArcUI.AnchorProxy.SizeChanged"]("Essential")
        assert(ns.GetArcUICooldownAnchor() == anchor)
    end
end
if arg[2] then Run(arg[2])
else
    for _, mode in ipairs({ "control", "arc", "registration", "suite", "suite-consent", "ellesmere", "skiron", "coolinator", "reporter",
        "suite-hook1", "suite-hook2", "suite-hook3", "skiron-hook1", "skiron-hook2", "skiron-hook3",
        "coolinator-hook1", "coolinator-hook2", "coolinator-hook3" }) do Run(mode) end
end
print("PASS integration_anchor_failure_smoke")
