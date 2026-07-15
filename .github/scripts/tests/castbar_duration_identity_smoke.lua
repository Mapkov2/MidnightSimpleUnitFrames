local now = 100
_G.GetTime = function() return now end
_G.GetTimePreciseSec = _G.GetTime
_G.issecretvalue = function() return false end

_G.Enum = {
    StatusBarInterpolation = { Immediate = 0 },
    StatusBarTimerDirection = { ElapsedTime = 0, RemainingTime = 1 },
    DurationTextBindingProperty = {
        RemainingDuration = 0,
        ElapsedDuration = 1,
        TotalDuration = 2,
    },
    NumericRuleFormatRounding = { Nearest = 0 },
}
_G.C_StringUtil = {
    CreateNumericRuleFormatter = function()
        return { SetBreakpoints = function() end }
    end,
}

local bindingCalls = { duration = 0, enabled = 0 }
_G.C_DurationUtil = {
    CreateDurationTextBinding = function()
        return {
            SetFontString = function(self, value) self.fontString = value end,
            SetUpdateInterval = function() end,
            SetTextFormat = function() end,
            SetDuration = function(self, value)
                bindingCalls.duration = bindingCalls.duration + 1
                self.duration = value
            end,
            SetEnabled = function(self, value)
                bindingCalls.enabled = bindingCalls.enabled + 1
                self.enabled = value
            end,
            Disable = function(self) self.enabled = false end,
            UpdateFontString = function() end,
        }
    end,
}

local timers = {}
_G.C_Timer = {
    NewTimer = function(delay, callback)
        local timer = { delay = delay, callback = callback, cancelled = false }
        function timer:Cancel() self.cancelled = true end
        timers[#timers + 1] = timer
        return timer
    end,
}

_G.MSUF_DB = { general = { showPlayerCastTime = true, castbarShowGlow = false } }
_G.MSUF__castTimeGlobalRev = 1
_G.MSUF_GetCastbarTimeFormat = function() return "CURRENT" end
_G.MSUF_GetReverseFillSafe = function() return false end

local ns = {
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}
assert(loadfile("MidnightSimpleUnitFrames/Castbars/MSUF_CastbarRuntime.lua"))("MSUF", ns)
local runtime = assert(_G.MSUF_CastbarRuntime)

local assignCalls = 0
local copyCalls = 0
local function newDuration(remaining, total, canCopy)
    local duration = { remaining = remaining, total = total }
    function duration:GetRemainingDuration() return self.remaining end
    function duration:GetTotalDuration() return self.total end
    function duration:Assign(other)
        assignCalls = assignCalls + 1
        self.remaining = other.remaining
        self.total = other.total
    end
    if canCopy then
        function duration:Copy()
            copyCalls = copyCalls + 1
            return newDuration(self.remaining, self.total, false)
        end
    end
    return duration
end

local frame = {
    unit = "player",
    timeText = { SetText = function() end },
    castText = { SetText = function() end },
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    SetScript = function() end,
}
frame.statusBar = {
    timerCalls = 0,
    GetParent = function() return frame end,
    SetReverseFill = function(self, value) self.reverse = value end,
    SetTimerDuration = function(self, duration)
        self.timerCalls = self.timerCalls + 1
        self.duration = duration
    end,
}

local first = newDuration(5, 5, true)
local state = {
    active = true,
    unit = "player",
    castType = "CAST",
    castBarID = 11,
    spellSequenceID = 11,
    spellName = "First",
    durationObj = first,
}
assert(runtime:ApplyActive(frame, state, { skipRegister = true }))
runtime:PrepareWork(frame)
local stable = assert(frame.MSUF_durationObj)
assert(stable ~= first and copyCalls == 1, "first cast did not create one stable duration container")
assert(frame.statusBar.timerCalls == 1 and bindingCalls.duration == 1 and bindingCalls.enabled == 1)

local update = newDuration(6, 7, true)
state.durationObj = update
assert(runtime:ApplyActive(frame, state, { skipRegister = true }))
runtime:PrepareWork(frame)
assert(frame.MSUF_durationObj == stable, "same cast replaced the bound duration container")
assert(assignCalls == 1, "same cast did not update the stable container exactly once")
assert(frame.statusBar.timerCalls == 1, "same cast rebound the native statusbar")
assert(bindingCalls.duration == 1 and bindingCalls.enabled == 1,
    "same cast rebound or re-enabled native duration text")
assert(stable.remaining == 6 and stable.total == 7, "stable duration did not receive updated values")

state.castBarID = 12
state.spellSequenceID = 12
state.spellName = "Second"
state.durationObj = newDuration(3, 3, true)
assert(runtime:ApplyActive(frame, state, { skipRegister = true }))
runtime:PrepareWork(frame)
assert(frame.MSUF_durationObj == stable and assignCalls == 2,
    "new cast failed to reuse the frame-owned native container")
assert(frame.statusBar.timerCalls == 1 and bindingCalls.duration == 1,
    "new cast rebound native consumers instead of assigning the stable container")

frame._msufCastbarWorkMask = 0
frame._msufPlainEndTime = 105
assert(runtime:ArmNativeCompletion(frame))
assert(runtime:ArmNativeCompletion(frame))
assert(#timers == 1, "unchanged native completion deadline recreated its timer")
frame._msufPlainEndTime = 106
assert(runtime:ArmNativeCompletion(frame))
assert(#timers == 2 and timers[1].cancelled, "changed completion deadline did not replace its timer")

local hideTimer = { cancelled = false, Cancel = function(self) self.cancelled = true end }
local successTimer = { cancelled = false, Cancel = function(self) self.cancelled = true end }
frame.hideTimer = hideTimer
frame.succeededTimer = successTimer
local hideToken = frame._msufHideToken or 0
runtime:Stop(frame, "STOPPED")
assert(hideTimer.cancelled and successTimer.cancelled, "STOPPED returned before timer cleanup")
assert(frame.hideTimer == nil and frame.succeededTimer == nil)
assert(frame._msufHideToken == hideToken + 1, "STOPPED did not invalidate queued hide callbacks")

print("castbar duration identity smoke: ok")
