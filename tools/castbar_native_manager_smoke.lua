local now = 100

_G.GetTimePreciseSec = function() return now end
_G.GetTime = _G.GetTimePreciseSec
_G.issecretvalue = function() return false end

_G.Enum = {
    StatusBarInterpolation = { Immediate = 0 },
    StatusBarTimerDirection = { ElapsedTime = 0, RemainingTime = 1 },
    DurationTextBindingProperty = {
        RemainingDuration = 0,
        RemainingPercent = 1,
        ElapsedDuration = 2,
        ElapsedPercent = 3,
        TotalDuration = 4,
        StartTime = 5,
        EndTime = 6,
    },
    NumericRuleFormatRounding = { Nearest = 0 },
}

_G.C_StringUtil = {
    CreateNumericRuleFormatter = function()
        return {
            SetBreakpoints = function(self, rules)
                self.rules = rules
            end,
        }
    end,
}

local bindings = {}
local bindingWithoutDisable
_G.C_DurationUtil = {
    CreateDurationTextBinding = function()
        local binding = {
            SetFontString = function(self, fontString) self.fontString = fontString end,
            SetUpdateInterval = function(self, interval) self.interval = interval end,
            SetTextFormat = function(self, format, components)
                self.format = format
                self.components = components
            end,
            SetDuration = function(self, duration) self.duration = duration end,
            SetEnabled = function(self, enabled) self.enabled = enabled end,
            UpdateFontString = function(self)
                if self.fontString then self.fontString.text = "native" end
            end,
        }
        if not bindingWithoutDisable then
            binding.Disable = function(self) self.enabled = false end
        end
        bindings[#bindings + 1] = binding
        return binding
    end,
}

local timers = {}
local tickers = {}
_G.C_Timer = {
    NewTimer = function(delay, callback)
        local timer = { delay = delay, callback = callback, cancelled = false }
        function timer:Cancel() self.cancelled = true end
        timers[#timers + 1] = timer
        return timer
    end,
    NewTicker = function(interval, callback)
        local ticker = { interval = interval, callback = callback, cancelled = false }
        function ticker:Cancel() self.cancelled = true end
        tickers[#tickers + 1] = ticker
        return ticker
    end,
}

local function LiveTickers(interval)
    local count = 0
    local last
    for index = 1, #tickers do
        local ticker = tickers[index]
        if ticker.interval == interval and not ticker.cancelled then
            count = count + 1
            last = ticker
        end
    end
    return count, last
end

local function CreatedTickers(interval)
    local count = 0
    for index = 1, #tickers do
        if tickers[index].interval == interval then count = count + 1 end
    end
    return count
end

local function NewScriptFrame()
    local frame = { scripts = {}, shown = false }
    function frame:SetScript(name, callback) self.scripts[name] = callback end
    function frame:HookScript(name, callback) self.scripts["Hook" .. name] = callback end
    function frame:Show() self.shown = true end
    function frame:Hide()
        local wasShown = self.shown
        self.shown = false
        local callback = wasShown and self.scripts.HookOnHide
        if callback then callback(self) end
        callback = wasShown and self.scripts.OnHide
        if callback then callback(self) end
    end
    function frame:IsShown() return self.shown end
    return frame
end

_G.CreateFrame = function() return NewScriptFrame() end

local unitExists = {}
_G.UnitExists = function(unit) return unitExists[unit] ~= false end
_G.UnitIsDeadOrGhost = function() return false end
_G.UnitChannelInfo = function() return "Channel" end

_G.MSUF_DB = {
    general = {
        showPlayerCastTime = true,
        showTargetCastTime = true,
        showFocusCastTime = true,
        showBossCastTime = true,
        castbarShowGlow = false,
    },
}
_G.MSUF__castTimeGlobalRev = 1
_G.MSUF_GetCastbarTimeFormat = function() return "CURRENT_MAX" end
_G.MSUF_GetCastbarReverseFillForFrame = function() return false end
_G.MSUF_SetTextIfChanged = function(fontString, text)
    text = text or ""
    if fontString._msufLastText == text then return end
    fontString._msufLastText = text
    fontString.text = text
end
_G.MSUF_SetCastTimeText = function(frame, remaining, total)
    frame.timeText.text = tostring(remaining) .. "/" .. tostring(total)
end
_G.MSUF_ApplyCastbarGlowFade = function() end
_G.MSUF_ResetCastbarGlowFade = function(frame) frame.glowReset = true end

local namespace = {}
assert(loadfile("MidnightSimpleUnitFrames/Castbars/MSUF_CastbarRuntime.lua"))("MSUF", namespace)
assert(loadfile("MidnightSimpleUnitFrames/Castbars/MSUF_Castbars.lua"))("MSUF", namespace)

local runtime = assert(_G.MSUF_CastbarRuntime)
local manager = assert(_G.MSUF_CastbarManager)
local UNIT_FAILSAFE = runtime.WorkMask.UNIT_FAILSAFE

local function NewFontString()
    local fontString = { text = "" }
    function fontString:SetText(text) self.text = text or "" end
    function fontString:GetText() return self.text end
    function fontString:SetFormattedText(format, ...)
        self.text = string.format(format, ...)
    end
    return fontString
end

local function NewDuration(remaining, total)
    return {
        remaining = remaining,
        total = total,
        GetRemainingDuration = function(self) return self.remaining end,
        GetTotalDuration = function(self) return self.total end,
    }
end

local function NewCastFrame(unit)
    local frame = NewScriptFrame()
    frame.unit = unit
    frame.timeText = NewFontString()
    frame.castText = NewFontString()
    frame.statusBar = {
        min = 0,
        max = 2,
        value = 0,
        GetParent = function() return frame end,
        SetReverseFill = function(self, reverse) self.reverse = reverse end,
        SetTimerDuration = function(self, duration) self.duration = duration end,
        SetMinMaxValues = function(self, minimum, maximum)
            self.min = minimum
            self.max = maximum
        end,
        GetMinMaxValues = function(self) return self.min, self.max end,
        SetValue = function(self, value) self.value = value end,
        GetValue = function(self) return self.value end,
        SetStatusBarColor = function() end,
    }
    function frame:SetSucceeded()
        self.succeeded = true
        runtime:Stop(self, "SUCCEEDED")
    end
    return frame
end

local function StartCast(unit, castType, configure)
    local frame = NewCastFrame(unit)
    if configure then configure(frame) end
    local duration = NewDuration(2, 2)
    assert(runtime:ApplyActive(frame, {
        active = true,
        unit = unit,
        castType = castType or "CAST",
        spellName = "Smoke",
        text = "Smoke",
        durationObj = duration,
    }, { skipColor = true }))
    return frame, duration
end

-- DurationTextBinding writes behind the Lua text cache. Both activation and
-- deactivation must invalidate it, including SetEnabled(false) fallback.
bindingWithoutDisable = true
local cacheFrame = NewCastFrame("player")
cacheFrame.timeText._msufLastText = "lua-before-native"
local cacheDuration = NewDuration(2, 2)
assert(runtime:ApplyActive(cacheFrame, {
    active = true,
    unit = "player",
    castType = "CAST",
    spellName = "Cache",
    durationObj = cacheDuration,
}, { skipRegister = true, skipTimeText = true, skipColor = true }))
assert(runtime:PrepareWork(cacheFrame) == 0)
assert(cacheFrame.timeText._msufLastText == nil, "native activation left stale text cache")
cacheFrame.timeText._msufLastText = "native-behind-cache"
runtime:DeactivateNative(cacheFrame)
assert(cacheFrame.timeText._msufLastText == nil, "native disable left stale text cache")
assert(cacheFrame._msufDurationTextBinding.enabled == false, "SetEnabled(false) fallback failed")
runtime:ReleaseActive(cacheFrame)
bindingWithoutDisable = false

-- A driver-owned target and a boss with encounter lifecycle ownership need no
-- periodic unit poll. Native completion is the only Lua timer left.
local ownedTarget = StartCast("target", nil, function(frame)
    frame._msufCastLifecycleOwned = true
end)
assert(ownedTarget._msufCastbarWorkMask == 0, "owned target mask=" .. tostring(ownedTarget._msufCastbarWorkMask)
    .. " owned=" .. tostring(ownedTarget._msufCastLifecycleOwned)
    .. " timer=" .. tostring(ownedTarget._msufNativeTimerUnsafe)
    .. " snapshot=" .. tostring(ownedTarget._msufDurationSnapshotUnsafe)
    .. " text=" .. tostring(ownedTarget._msufNativeTextUnsafe))
assert(manager.active[ownedTarget] == nil)
assert(ownedTarget._msufNativeCompletionTimer ~= nil)
assert(LiveTickers(0.25) == 0 and LiveTickers(0.10) == 0)
runtime:Stop(ownedTarget, "STOPPED")

local ownedBoss = StartCast("boss1", nil, function(frame)
    frame._msufIsBossCastbar = true
    frame._msufCastLifecycleOwned = true
end)
assert(ownedBoss._msufCastbarWorkMask == 0)
assert(manager.active[ownedBoss] == nil and ownedBoss._msufNativeCompletionTimer ~= nil)
runtime:Stop(ownedBoss, "STOPPED")

-- Proven native failures promote an otherwise lifecycle-owned frame onto the
-- degraded manager/failsafe path.
local createBinding = _G.C_DurationUtil.CreateDurationTextBinding
_G.C_DurationUtil.CreateDurationTextBinding = function() return nil end
local bindingFailure = StartCast("target", nil, function(frame)
    frame._msufCastLifecycleOwned = true
end)
assert(bindingFailure._msufCastbarWorkMask == UNIT_FAILSAFE + runtime.WorkMask.TIME_TEXT)
assert(manager.low[bindingFailure] == true and bindingFailure._msufNativeTextUnsafe == true)
runtime:Stop(bindingFailure, "STOPPED")
_G.C_DurationUtil.CreateDurationTextBinding = createBinding

local newTimer = _G.C_Timer.NewTimer
_G.C_Timer.NewTimer = function() error("timer unavailable") end
local timerFailure = StartCast("target", nil, function(frame)
    frame._msufCastLifecycleOwned = true
end)
assert(timerFailure._msufCastbarWorkMask == UNIT_FAILSAFE + runtime.WorkMask.DURATION_FALLBACK)
assert(manager.low[timerFailure] == true and timerFailure._msufNativeCompletionUnsafe == true)
runtime:Stop(timerFailure, "STOPPED")
_G.C_Timer.NewTimer = newTimer

-- A detached time consumer can force the source onto its existing manager
-- cadence. The follower is written only when the source decimal changes.
local follower = NewFontString()
local followedTarget = StartCast("target", nil, function(frame)
    frame._msufCastLifecycleOwned = true
    frame._msufForceLuaTimeTextFollower = true
    frame._msufTimeTextFollower = follower
end)
assert(followedTarget._msufCastbarWorkMask == runtime.WorkMask.TIME_TEXT)
assert(manager.low[followedTarget] == true and LiveTickers(0.10) == 1)
local _, followerTicker = LiveTickers(0.10)
now = now + 0.1
followerTicker.callback()
assert(follower.text == followedTarget.timeText.text and follower.text ~= "",
    "manager did not update detached time follower: follower=" .. tostring(follower.text)
        .. " source=" .. tostring(followedTarget.timeText.text))
runtime:Stop(followedTarget, "STOPPED")
assert(LiveTickers(0.10) == 0)

-- A native target/focus cast has only the unit-missing failsafe in Lua. It
-- must use one shared 0.25 s ticker plus a one-shot native completion timer.
local target = StartCast("target")
assert(target._msufCastbarWorkMask == UNIT_FAILSAFE)
assert(manager.active[target] == true and manager.failsafe[target] == true)
assert(manager.low[target] == nil and manager.high[target] == nil)
assert(target._msufNativeCompletionTimer ~= nil)
assert(LiveTickers(0.25) == 1, "failsafe ticker missing")
assert(LiveTickers(0.10) == 0, "failsafe-only cast started 0.10 s ticker")

local focus = StartCast("focus")
assert(manager.failsafe[focus] == true)
assert(LiveTickers(0.25) == 1, "failsafe frames did not share ticker")
assert(CreatedTickers(0.25) == 1, "duplicate failsafe ticker allocated")

local oldTargetCompletion = target._msufNativeCompletionTimer
_G.MSUF_RegisterCastbar(target)
assert(oldTargetCompletion.cancelled == false
    and target._msufNativeCompletionTimer == oldTargetCompletion,
    "repeat registration replaced an unchanged completion timer")
assert(manager.failsafe[target] == true and LiveTickers(0.25) == 1)

-- Adding/removing ordinary low and high-frequency work must not disturb the
-- independent failsafe ticker or leave manager scripts/tickers running.
local channel = StartCast("player", "CHANNEL")
assert(manager.low[channel] == true and LiveTickers(0.10) == 1)
assert(LiveTickers(0.25) == 1)
runtime:Stop(channel, "STOPPED")
assert(LiveTickers(0.10) == 0, "low ticker survived last runtime-low frame")
assert(LiveTickers(0.25) == 1, "low removal stopped failsafe ticker")

local empower = StartCast("player", "CAST", function(frame)
    frame.isEmpower = true
    frame.empowerStartTime = now
    frame.empowerTotalWithGrace = 2
end)
assert(manager.high[empower] == true)
assert(type(manager.scripts.OnUpdate) == "function", "high-frequency frame did not arm OnUpdate")
runtime:Stop(empower, "STOPPED")
assert(manager.scripts.OnUpdate == nil, "OnUpdate survived last high-frequency frame")
assert(LiveTickers(0.25) == 1)

-- Reclassifying an already-active frame must keep all local counters exact.
_G.MSUF_DB.general.castbarShowGlow = true
_G.MSUF__castTimeGlobalRev = _G.MSUF__castTimeGlobalRev + 1
local targetCompletion = target._msufNativeCompletionTimer
_G.MSUF_RegisterCastbar(target)
assert(manager.failsafe[target] == nil and manager.low[target] == true)
assert(targetCompletion.cancelled == true and target._msufNativeCompletionTimer == nil)
assert(LiveTickers(0.10) == 1 and LiveTickers(0.25) == 1)

_G.MSUF_DB.general.castbarShowGlow = false
_G.MSUF__castTimeGlobalRev = _G.MSUF__castTimeGlobalRev + 1
_G.MSUF_RegisterCastbar(target)
assert(manager.failsafe[target] == true and manager.low[target] == nil)
assert(target._msufNativeCompletionTimer ~= nil)
assert(LiveTickers(0.10) == 0 and LiveTickers(0.25) == 1)

-- Missing-unit callbacks remove one frame without stopping the shared ticker,
-- then fully tear down manager/timer state after the last frame.
unitExists.focus = false
local _, failsafeTicker = LiveTickers(0.25)
failsafeTicker.callback()
assert(manager.active[focus] == nil and manager.active[target] == true)
assert(LiveTickers(0.25) == 1)

unitExists.target = false
now = now + 0.25
local targetTimer = target._msufNativeCompletionTimer
local _, remainingFailsafeTicker = LiveTickers(0.25)
remainingFailsafeTicker.callback()
assert(manager.active[target] == nil and manager:IsShown() == false)
assert(targetTimer.cancelled == true, "unit-missing stop leaked completion timer")
assert(LiveTickers(0.25) == 0 and LiveTickers(0.10) == 0)

-- Native completion remains authoritative for failsafe-only frames: it can
-- reschedule a delayed duration, complete cleanly, or promote an unreadable
-- duration back to the ordinary manager without corrupting bucket counters.
unitExists.target = true
local completionTarget, completionDuration = StartCast("target")
local firstCompletion = completionTarget._msufNativeCompletionTimer
completionDuration.remaining = 0.5
firstCompletion.callback()
local secondCompletion = completionTarget._msufNativeCompletionTimer
assert(secondCompletion and secondCompletion ~= firstCompletion)
assert(manager.failsafe[completionTarget] == true and LiveTickers(0.25) == 1)
completionDuration.remaining = 0
secondCompletion.callback()
assert(completionTarget.succeeded == true and manager.active[completionTarget] == nil)
assert(LiveTickers(0.25) == 0)

local unsafeTarget, unsafeDuration = StartCast("target")
unsafeDuration.GetRemainingDuration = function() error("unreadable") end
unsafeTarget._msufNativeCompletionTimer.callback()
assert(unsafeTarget._msufCastbarWorkMask == UNIT_FAILSAFE + runtime.WorkMask.DURATION_FALLBACK)
assert(manager.failsafe[unsafeTarget] == nil and manager.low[unsafeTarget] == true)
assert(LiveTickers(0.25) == 0 and LiveTickers(0.10) == 1)
runtime:Stop(unsafeTarget, "STOPPED")
assert(LiveTickers(0.10) == 0 and manager:IsShown() == false)

local player = StartCast("player")
local playerCompletion = player._msufNativeCompletionTimer
assert(player._msufCastbarWorkMask == 0 and manager.active[player] == nil)
runtime:Stop(player, "STOPPED")
assert(playerCompletion.cancelled == true and manager.active[player] == nil)

-- Clients without NewTicker retain the original OnUpdate/low-bucket fallback.
local newTicker = _G.C_Timer.NewTicker
_G.C_Timer.NewTicker = nil
unitExists.target = true
local fallback = StartCast("target")
assert(manager.low[fallback] == true and manager.failsafe[fallback] == nil)
assert(type(manager.scripts.OnUpdate) == "function")
runtime:Stop(fallback, "STOPPED")
assert(manager.scripts.OnUpdate == nil and manager:IsShown() == false)
_G.C_Timer.NewTicker = newTicker

print("castbar native manager smoke: ok")
