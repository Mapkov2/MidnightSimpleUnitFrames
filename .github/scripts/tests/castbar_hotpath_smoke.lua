-- Standalone regressions for trace-driven castbar hotpath ownership.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local function Equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function LoadAddonFile(relativePath, namespace)
    local chunk, loadError = loadfile(root .. "/MidnightSimpleUnitFrames/" .. relativePath)
    Check(chunk ~= nil, loadError)
    chunk("MidnightSimpleUnitFrames", namespace)
end

local function NewNamespace()
    local namespace = {}
    function namespace.ExportPublic(name, value)
        _G[name] = value
        return value
    end
    return namespace
end

-- Global castbar colors share exactly one ColorObject per semantic color.
do
    local createColorCalls = 0
    _G.CreateColor = function(red, green, blue, alpha)
        createColorCalls = createColorCalls + 1
        return { id = createColorCalls, red = red, green = green, blue = blue, alpha = alpha }
    end
    _G.C_CurveUtil = {
        EvaluateColorFromBoolean = function(value, falseColor, trueColor)
            return value == true and trueColor or falseColor
        end,
    }
    _G.C_Timer = { After = function() end }
    _G.issecretvalue = function() return false end
    _G.MSUF_DB = { general = {} }
    _G.MSUF_SetStatusBarColorIfChanged = nil

    LoadAddonFile("Castbars/MSUF_CastbarUtils.lua", NewNamespace())
    local applyTint = _G.MSUF_Castbar_ApplyNonInterruptibleTint
    Check(type(applyTint) == "function", "non-interruptible tint export missing")

    local function NewTintFrame()
        local texture = {}
        function texture:SetVertexColorFromBoolean(value, falseColor, trueColor)
            self.value, self.falseColor, self.trueColor = value, falseColor, trueColor
        end
        local statusBar = { texture = texture }
        function statusBar:GetStatusBarTexture() return self.texture end
        function statusBar:SetStatusBarColor(red, green, blue, alpha)
            self.red, self.green, self.blue, self.alpha = red, green, blue, alpha
        end
        return { statusBar = statusBar }
    end

    local function Tint(frame, unavailable)
        return applyTint(
            frame,
            false,
            0.1, 0.2, 0.3, 1,
            0.4, 0.8, 0.9, 1,
            false,
            1, 0.5, 0.1, 1,
            false,
            unavailable == true
        )
    end

    local target = NewTintFrame()
    local focus = NewTintFrame()
    Check(Tint(target, false) == true, "target boolean tint failed")
    Equal(createColorCalls, 2, "global cold ColorObject count")
    Check(Tint(focus, false) == true, "focus boolean tint failed")
    Equal(createColorCalls, 2, "focus recreated global castbar colors")
    Check(target.statusBar.texture.falseColor == focus.statusBar.texture.falseColor
        and target.statusBar.texture.trueColor == focus.statusBar.texture.trueColor,
        "frames did not share global castbar ColorObjects")
    Check(Tint(target, true) == true, "unavailable tint failed")
    Equal(createColorCalls, 3, "unavailable color was not created exactly once")
    Tint(focus, true)
    Equal(createColorCalls, 3, "unchanged unavailable color was recreated")
end

-- Native duration-text cleanup is a transition: steady disabled calls do no C work,
-- while a partially configured binding still receives a forced disable.
do
    _G.Enum = {
        StatusBarInterpolation = { Immediate = 0 },
        StatusBarTimerDirection = { ElapsedTime = 0, RemainingTime = 1 },
        DurationTextBindingProperty = {
            RemainingDuration = 1,
            ElapsedDuration = 2,
            TotalDuration = 3,
        },
        NumericRuleFormatRounding = { Nearest = 1 },
    }
    _G.C_StringUtil = {
        CreateNumericRuleFormatter = function()
            return { SetBreakpoints = function() end }
        end,
    }
    _G.C_Timer = {
        NewTimer = function() return { Cancel = function() end } end,
    }
    _G.GetTime = function() return 10 end
    _G.GetTimePreciseSec = nil
    _G.issecretvalue = function() return false end
    _G.MSUF_CastbarRuntime = nil

    local createdBinding
    _G.C_DurationUtil = {
        CreateDurationTextBinding = function() return createdBinding end,
    }
    local namespace = NewNamespace()
    LoadAddonFile("Castbars/MSUF_CastbarRuntime.lua", namespace)
    local runtime = namespace.MSUF_CastbarRuntime
    Check(type(runtime) == "table", "castbar runtime missing")

    local disableCalls = 0
    local frame = {
        timeText = { _msufLastText = "native" },
        _msufNativeTimeBound = true,
        _msufDurationTextBinding = {
            Disable = function() disableCalls = disableCalls + 1 end,
        },
    }
    runtime:DisableNativeTimeText(frame)
    runtime:DisableNativeTimeText(frame)
    Equal(disableCalls, 1, "steady disabled binding repeated native Disable")
    Equal(frame._msufNativeTimeBound, nil, "successful disable retained bound flag")
    Equal(frame.timeText._msufLastText, nil, "native disable did not invalidate Lua text cache")

    local partialDisableCalls = 0
    createdBinding = {
        SetFontString = function() error("synthetic SetFontString failure") end,
        Disable = function() partialDisableCalls = partialDisableCalls + 1 end,
    }
    local partialFrame = { timeText = {} }
    Check(runtime:BindNativeTimeText(partialFrame, {}, "CURRENT") == false,
        "partial native binding failure reported success")
    Equal(partialDisableCalls, 1, "partial native binding was not force-disabled")
    Equal(partialFrame._msufNativeTextCleanupPending, nil, "successful partial cleanup stayed pending")
    Equal(partialFrame._msufNativeTimeBound, nil, "partial cleanup marked binding live")

    local rejectCleanup = true
    local retryDisableCalls, retrySetEnabledCalls = 0, 0
    local retryFrame = {
        timeText = {},
        _msufNativeTextCleanupPending = true,
        _msufDurationTextBinding = {
            Disable = function()
                retryDisableCalls = retryDisableCalls + 1
                error("synthetic Disable failure")
            end,
            SetEnabled = function(_, enabled)
                retrySetEnabledCalls = retrySetEnabledCalls + 1
                Check(enabled == false, "cleanup enabled native text")
                if rejectCleanup then error("synthetic SetEnabled failure") end
            end,
        },
    }
    runtime:DisableNativeTimeText(retryFrame)
    Check(retryFrame._msufNativeTextCleanupPending == true, "failed cleanup lost retry ownership")
    Check(retryFrame._msufNativeTimeBound == true, "failed cleanup was treated as disabled")
    rejectCleanup = false
    runtime:DisableNativeTimeText(retryFrame)
    Equal(retryDisableCalls, 2, "failed cleanup was not retried")
    Equal(retrySetEnabledCalls, 2, "SetEnabled cleanup was not retried")
    Equal(retryFrame._msufNativeTextCleanupPending, nil, "successful retry stayed pending")
    Equal(retryFrame._msufNativeTimeBound, nil, "successful retry stayed bound")
end

-- GetSpellCooldownDuration returns a userdata object. Reuse it inside one frame,
-- but invalidate before every relevant cooldown/spec/world refresh.
do
    local now = 100
    local cooldownAPICalls = 0
    local timers = {}
    local interruptEventFrame

    _G.GetTime = function() return now end
    _G.GetTimePreciseSec = nil
    _G.UnitClass = function() return "Mage", "MAGE" end
    _G.GetSpecialization = function() return 1 end
    _G.GetSpecializationInfo = function() return 62 end
    _G.Constants = { SpellCooldownConsts = { GLOBAL_RECOVERY_CATEGORY = 77 } }
    _G.C_Spell = {
        GetSpellCooldownDuration = function(spellID)
            cooldownAPICalls = cooldownAPICalls + 1
            return {
                spellID = spellID,
                GetRemainingDuration = function() return 8 end,
                IsZero = function() return false end,
            }
        end,
    }
    _G.C_Timer = {
        After = function(delay, callback)
            timers[#timers + 1] = { delay = delay, callback = callback }
        end,
    }
    _G.C_CurveUtil = nil
    _G.issecretvalue = function() return false end
    _G.MSUF_DB = { general = {} }
    _G.CreateFrame = function()
        local frame = { scripts = {}, events = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:SetScript(script, callback) self.scripts[script] = callback end
        interruptEventFrame = frame
        return frame
    end

    LoadAddonFile("Castbars/MSUF_InterruptReady.lua", NewNamespace())
    Equal(_G.MSUF_KickReady_Init(), 2139, "mage interrupt spell resolution")
    Check(_G.MSUF_KickReady_IsReady() == false, "cooldown unexpectedly ready")
    Check(_G.MSUF_KickReady_IsReady() == false, "cached cooldown unexpectedly ready")
    Equal(cooldownAPICalls, 1, "same-frame readiness calls allocated multiple DurationObjects")

    now = 101
    _G.MSUF_KickReady_GetReadyBoolForTint()
    Equal(cooldownAPICalls, 2, "new frame reused stale cooldown snapshot")

    local onEvent = interruptEventFrame and interruptEventFrame.scripts.OnEvent
    Check(type(onEvent) == "function", "interrupt event handler missing")
    onEvent(interruptEventFrame, "SPELL_UPDATE_COOLDOWN", 2139, 2139, nil, 0)
    Equal(cooldownAPICalls, 3, "relevant cooldown event did not invalidate snapshot")
    _G.MSUF_KickReady_IsReady()
    Equal(cooldownAPICalls, 3, "event refresh object was not shared with same-frame consumers")

    onEvent(interruptEventFrame, "SPELL_UPDATE_COOLDOWN", 999999, 999999, nil, 0)
    Equal(cooldownAPICalls, 3, "unrelated cooldown event queried interrupt duration")
    now = 102
    onEvent(interruptEventFrame, "SPELL_UPDATE_COOLDOWN", 2139, 2139, nil, 0)
    Equal(cooldownAPICalls, 4, "next relevant cooldown event reused stale snapshot")
end

-- Low-frequency register/reclassify initializes only the affected frame. High-
-- frequency initialization stays caller-owned; a complete low-bucket pass is
-- reserved for an actual frame-driver <-> ticker topology hand-off.
-- Player channel hard-stop reads the stored active token without BuildState.
do
    local now = 0
    local unitExistsCalls = {}
    local channelCalls = {}
    local channelState = { player = "Channel", vehicle = nil }
    local vehicleUI = false
    local tickerCallbacks = {}

    _G.GetTimePreciseSec = function() return now end
    _G.GetTime = function() return now end
    _G.UnitExists = function(unit)
        unitExistsCalls[unit] = (unitExistsCalls[unit] or 0) + 1
        return true
    end
    _G.UnitIsDeadOrGhost = function() return false end
    _G.UnitHasVehicleUI = function() return vehicleUI end
    _G.UnitChannelInfo = function(unit)
        channelCalls[#channelCalls + 1] = unit
        return channelState[unit]
    end
    _G.GetCVar = function() return "400" end
    _G.C_Timer = {
        After = function() end,
        NewTicker = function(interval, callback)
            local ticker = { interval = interval, callback = callback, cancelled = false }
            function ticker:Cancel() self.cancelled = true end
            tickerCallbacks[#tickerCallbacks + 1] = ticker
            return ticker
        end,
    }

    local FrameMethods = {}
    function FrameMethods:SetScript(script, callback) self.scripts[script] = callback end
    function FrameMethods:HookScript(script, callback) self.hooks[script] = callback end
    function FrameMethods:Show() self.shown = true end
    function FrameMethods:Hide()
        local wasShown = self.shown ~= false
        self.shown = false
        if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
        if wasShown and self.hooks.OnHide then self.hooks.OnHide(self) end
    end
    function FrameMethods:IsShown() return self.shown ~= false end

    local function NewFrame()
        return setmetatable({ scripts = {}, hooks = {}, shown = true }, { __index = FrameMethods })
    end

    _G.MSUF_CastbarManager = nil
    _G.CreateFrame = function() return NewFrame() end
    local managerRuntime = {
        WorkMask = { UNIT_FAILSAFE = 32 },
    }
    function managerRuntime:PrepareWork(frame)
        frame._msufCastbarWorkMask = frame.testWorkMask
        return frame.testWorkMask
    end
    function managerRuntime:CancelNativeCompletion() end
    function managerRuntime:DeactivateNative() end
    function managerRuntime:ArmNativeCompletion() return false end
    _G.MSUF_CastbarRuntime = managerRuntime
    _G.MSUF_ApplyCastbarGlowFade = nil
    _G.MSUF_ResetCastbarGlowFade = nil
    _G.MSUF_RefreshCastbarStyleCache = nil

    LoadAddonFile("Castbars/MSUF_Castbars.lua", NewNamespace())
    local register = _G.MSUF_RegisterCastbar
    local unregister = _G.MSUF_UnregisterCastbar
    Check(type(register) == "function" and type(unregister) == "function", "castbar manager exports missing")

    local function NewManagedFrame(unit, workMask, empower)
        local frame = NewFrame()
        frame.unit = unit
        frame.statusBar = {}
        frame.timeText = {
            SetFormattedText = function(self) self.formatted = (self.formatted or 0) + 1 end,
            SetText = function() end,
        }
        frame.MSUF_castActive = true
        frame.MSUF_timerDriven = true
        frame._msufCastTimeEnabled = true
        frame._msufPlainEndTime = now + 5
        frame.testWorkMask = workMask
        frame.isEmpower = empower == true
        return frame
    end

    local target = NewManagedFrame("target", 1, false)
    register(target)
    Equal(unitExistsCalls.target, 1, "initial low topology did not initialize target once")

    now = 0.30
    local focus = NewManagedFrame("focus", 1, false)
    register(focus)
    Equal(unitExistsCalls.target, 1, "focus registration synchronously rescanned target")
    Equal(unitExistsCalls.focus, 1, "focus registration was not initialized immediately")

    now = 0.60
    focus._msufPlainEndTime = now + 5
    register(focus)
    Equal(unitExistsCalls.target, 1, "focus re-registration synchronously rescanned target")
    Equal(unitExistsCalls.focus, 2, "focus re-registration did not refresh only focus")

    now = 0.90
    unregister(focus)
    Equal(unitExistsCalls.target, 1, "steady low unregister synchronously rescanned target")

    now = 1.20
    local boss = NewManagedFrame("boss1", 8, true)
    register(boss)
    Equal(unitExistsCalls.target, 1, "low-to-frame topology transition rescanned low sibling early")
    Equal(unitExistsCalls.boss1, nil, "manager duplicated caller-owned high-frequency initialization")

    now = 1.50
    unregister(boss)
    Equal(unitExistsCalls.target, 2, "frame-to-low-ticker topology hand-off skipped coherent low scan")

    local effectiveUnitCalls = 0
    _G.MSUF_PlayerCastbar_GetEffectiveUnit = function()
        effectiveUnitCalls = effectiveUnitCalls + 1
        error("hard-stop rebuilt cast state")
    end
    local player = NewManagedFrame("player", 4, false)
    player.timeText = nil
    player._msufCastTimeEnabled = false
    player.MSUF_isChanneled = true
    player._msufActiveCastUnit = "player"
    now = 1.80
    register(player)
    Equal(effectiveUnitCalls, 0, "player channel hard-stop called GetEffectiveUnit/BuildState")
    Equal(channelCalls[#channelCalls], "player", "stored player channel token was not used")

    channelCalls = {}
    channelState.player = nil
    channelState.vehicle = "Vehicle Channel"
    vehicleUI = true
    player._msufActiveCastUnit = "player"
    player._msufHardStopNext = nil
    now = 2.10
    register(player)
    Equal(#channelCalls, 2, "vehicle transition did not probe exactly primary plus fallback")
    Equal(channelCalls[1], "player", "vehicle transition skipped stored primary token")
    Equal(channelCalls[2], "vehicle", "vehicle transition did not probe vehicle fallback")
    Equal(player._msufActiveCastUnit, "vehicle", "vehicle fallback did not stabilize active token")

    channelCalls = {}
    player._msufHardStopNext = nil
    now = 2.40
    register(player)
    Equal(#channelCalls, 1, "steady vehicle channel performed fallback work")
    Equal(channelCalls[1], "vehicle", "steady vehicle channel ignored stored active token")
    Equal(effectiveUnitCalls, 0, "vehicle channel hard-stop called GetEffectiveUnit/BuildState")

    unregister(player)
    unregister(target)
end

print("PASS castbar hotpaths: shared ColorObjects, native-text transition cleanup, cooldown snapshot sharing, O(1) manager refresh, channel unit fastpath")
