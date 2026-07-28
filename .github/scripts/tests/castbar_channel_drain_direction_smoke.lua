--- castbar_channel_drain_direction_smoke.lua
---
--- Pins the castbar direction model, which regressed twice:
---   * the fill ANCHOR is direction-only (castbarFillDirection, plus the
---     target-opposite option). It never flips per cast type.
---   * the bar VALUE carries the drain: a cast counts up (ElapsedTime) so it
---     fills toward the far edge, a channel counts down (RemainingTime) so the
---     same anchor drains and its moving edge travels the opposite way.
---   * "always fill in one direction" (castbarUnifiedDirection) makes channels
---     count up like a cast; empower bars always count up.
---
--- Both renderings must agree: the native 12.1 timer direction AND the Lua
--- fallback that writes the value by hand when no duration object exists.

local repoRoot = ...
if repoRoot and repoRoot ~= "" then
    local sep = package.config:sub(1, 1)
    if repoRoot:sub(-1) ~= sep then repoRoot = repoRoot .. sep end
else
    repoRoot = ""
end

local function LoadFile(relative)
    local path = repoRoot .. relative
    local chunk = assert(loadfile(path), "failed to load " .. path)
    return chunk
end

local now = 100
_G.GetTime = function() return now end
_G.GetTimePreciseSec = _G.GetTime
_G.issecretvalue = function() return false end

local ELAPSED, REMAINING = 0, 1
_G.Enum = {
    StatusBarInterpolation = { Immediate = 0 },
    StatusBarTimerDirection = { ElapsedTime = ELAPSED, RemainingTime = REMAINING },
    DurationTextBindingProperty = { RemainingDuration = 0, ElapsedDuration = 1, TotalDuration = 2 },
    NumericRuleFormatRounding = { Nearest = 0 },
}
_G.C_StringUtil = {
    CreateNumericRuleFormatter = function()
        return { SetBreakpoints = function() end }
    end,
}
_G.C_DurationUtil = {
    CreateDurationTextBinding = function()
        return {
            SetFontString = function() end,
            SetUpdateInterval = function() end,
            SetTextFormat = function() end,
            SetDuration = function() end,
            SetEnabled = function() end,
            Disable = function() end,
            UpdateFontString = function() end,
        }
    end,
}
_G.C_Timer = {
    NewTimer = function(delay, callback)
        local timer = { delay = delay, callback = callback }
        function timer:Cancel() end
        return timer
    end,
    After = function() end,
}

_G.MSUF_DB = { general = { castbarFillDirection = "LTR", castbarUnifiedDirection = false } }

local ns = {
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}

LoadFile("MidnightSimpleUnitFrames/Castbars/MSUF_CastbarUtils.lua")("MSUF", ns)
LoadFile("MidnightSimpleUnitFrames/Castbars/MSUF_CastbarRuntime.lua")("MSUF", ns)

local CountsDown = assert(_G.MSUF_GetCastbarCountsDown, "MSUF_GetCastbarCountsDown was not exported")
local ReverseFill = assert(_G.MSUF_GetCastbarReverseFillForFrame, "reverse fill resolver missing")
local runtime = assert(_G.MSUF_CastbarRuntime)

local function NewFrame()
    local frame = {
        unit = "player",
        timeText = { SetText = function() end },
        castText = { SetText = function() end },
        Show = function() end,
        Hide = function() end,
        SetScript = function() end,
    }
    frame.statusBar = {
        GetParent = function() return frame end,
        SetReverseFill = function(self, value) self.reverse = value end,
        SetMinMaxValues = function(self, minValue, maxValue)
            self.min, self.max = minValue, maxValue
        end,
        SetValue = function(self, value) self.value = value end,
        SetTimerDuration = function(self, duration, interpolation, direction)
            self.duration = duration
            self.interpolation = interpolation
            self.direction = direction
        end,
    }
    return frame
end

local function NewDuration(remaining, total)
    local duration = { remaining = remaining, total = total }
    function duration:GetRemainingDuration() return self.remaining end
    function duration:GetTotalDuration() return self.total end
    function duration:Assign(other)
        self.remaining, self.total = other.remaining, other.total
    end
    function duration:Copy() return NewDuration(self.remaining, self.total) end
    return duration
end

local function ApplyCast(frame, castType, sequence)
    local state = {
        active = true,
        unit = "player",
        castType = castType,
        castBarID = sequence,
        spellSequenceID = sequence,
        spellName = castType,
        durationObj = NewDuration(4, 4),
    }
    assert(runtime:ApplyActive(frame, state, { skipRegister = true }))
end

-- 1. Count direction is a cast-type property.
assert(CountsDown(nil, false) == false, "a cast must count up")
assert(CountsDown(nil, true) == true, "a channel must count down by default")
assert(CountsDown({ isEmpower = true }, true) == false, "empower bars fill, they never drain")

_G.MSUF_DB.general.castbarUnifiedDirection = true
assert(CountsDown(nil, true) == false, "unified direction must make channels fill like a cast")
_G.MSUF_DB.general.castbarUnifiedDirection = false

-- 2. The anchor is direction-only: identical for casts and channels.
for _, direction in ipairs({ "LTR", "RTL" }) do
    _G.MSUF_DB.general.castbarFillDirection = direction
    local expected = (direction == "RTL")
    local frame = NewFrame()
    assert(ReverseFill(frame, false) == expected, direction .. ": cast anchor")
    assert(ReverseFill(frame, true) == expected,
        direction .. ": channel anchor flipped away from the cast anchor")
end
_G.MSUF_DB.general.castbarFillDirection = "LTR"

-- 3. Native timer: same anchor for both, opposite value direction.
local frame = NewFrame()
ApplyCast(frame, "CAST", 1)
assert(frame.statusBar.reverse == false, "LTR cast anchored on the wrong edge")
assert(frame.statusBar.direction == ELAPSED, "cast did not bind ElapsedTime")
assert(frame._msufCountsDown == false, "cast marked as counting down")

ApplyCast(frame, "CHANNEL", 2)
assert(frame.statusBar.reverse == false, "channel flipped the anchor instead of draining")
assert(frame.statusBar.direction == REMAINING, "channel did not bind RemainingTime (it would fill)")
assert(frame._msufCountsDown == true, "channel not marked as counting down")
assert(frame._msufTimerAssumeCountdown == true, "time text would read the bar the wrong way")

_G.MSUF_DB.general.castbarUnifiedDirection = true
ApplyCast(frame, "CHANNEL", 3)
assert(frame.statusBar.reverse == false, "unified channel moved the anchor")
assert(frame.statusBar.direction == ELAPSED, "unified channel did not bind ElapsedTime")
assert(frame._msufCountsDown == false, "unified channel still marked as draining")
_G.MSUF_DB.general.castbarUnifiedDirection = false

-- 4. RTL keeps the same relationship: anchor moves, value direction does not.
_G.MSUF_DB.general.castbarFillDirection = "RTL"
local rtl = NewFrame()
ApplyCast(rtl, "CAST", 4)
assert(rtl.statusBar.reverse == true and rtl.statusBar.direction == ELAPSED, "RTL cast")
ApplyCast(rtl, "CHANNEL", 5)
assert(rtl.statusBar.reverse == true, "RTL channel flipped the anchor")
assert(rtl.statusBar.direction == REMAINING, "RTL channel did not drain")
_G.MSUF_DB.general.castbarFillDirection = "LTR"

-- 5. The Lua fallback paths write the bar value by hand when a cast has no
--    duration object (UnitChannelDuration MayReturnNothing). Those writes must
--    key off the cast type, never off the anchor - deriving "counts down" from
--    reverseFill is exactly how channels started filling again.
local function ReadSource(relative)
    local handle = assert(io.open(repoRoot .. relative, "rb"), "missing " .. relative)
    local source = handle:read("*a")
    handle:close()
    return (source:gsub("\r\n", "\n"))
end

local valueSites = {
    ["MidnightSimpleUnitFrames/Castbars/MSUF_CastbarDriver.lua"] =
        "statusBar:SetValue(countsDown and remaining or (total - remaining))",
    ["MidnightSimpleUnitFrames/Castbars/MSUF_Castbars.lua"] =
        "local value = frame._msufCountsDown and remaining or (total - remaining)",
}
for relative, expected in pairs(valueSites) do
    local source = ReadSource(relative)
    assert(source:find(expected, 1, true), relative .. ": manual bar value lost its cast-type source")
    assert(not source:find("_msufStripeReverseFill and remaining", 1, true),
        relative .. ": manual bar value derives the drain from the anchor again")
end

local playerSource = ReadSource("MidnightSimpleUnitFrames/Castbars/MSUF_PlayerCastbarRuntime.lua")
assert(playerSource:find("local function SetStatusBarRemaining(frame, totalSeconds, remainingSeconds, countsDown)", 1, true),
    "player fallback no longer takes the count direction")
assert(playerSource:find("SetStatusBarRemaining(frame, frame._msufPlainTotal, frame._msufRemaining, countsDown)", 1, true),
    "player fallback is fed the anchor instead of the count direction")

print("castbar channel drain direction smoke: ok")
