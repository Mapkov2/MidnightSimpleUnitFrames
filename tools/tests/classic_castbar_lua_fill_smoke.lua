-- Executes the Classic castbar Lua fill path. Supported Classic clients have no
-- UnitCastingDuration, UnitChannelDuration, C_DurationUtil or
-- StatusBar:SetTimerDuration, so every castbar fills through the manager's
-- endTime path. A fake clock pumps the real manager through a cast (fill, time
-- text, completion), a glow that must use the cast's plain total, a pushback
-- re-seed, a channel's natural end and a channel
-- whose UnitChannelInfo ends without a stop event (hard stop). The real target
-- driver then shows the legacy pushback suffix after UNIT_SPELLCAST_DELAYED.
-- The fill repaints on every rendered frame (at most once); time text, glow and
-- hard stops keep the 20 Hz heavy cadence.
local root = assert(arg[1], "repository root argument missing")

local STEP = 1 / 60
local clock = 100
local channelActive = false
local pendingAfter = {}

_G.GetTime = function() return clock end
-- The high-precision clock advances by a tiny epsilon on every read inside a
-- counted frame (like the live client), so a writer that reads its own clock
-- instead of the shared frame timestamp writes the fill twice.
local preciseDrift, preciseOffset = false, 0
_G.GetTimePreciseSec = function()
    if not preciseDrift then return clock end
    preciseOffset = preciseOffset + 1e-7
    return clock + preciseOffset
end
_G.C_Timer = {
    -- No NewTicker: the manager has to take its frame-driven OnUpdate path.
    After = function(_, callback) pendingAfter[#pendingAfter + 1] = callback end,
}
_G.issecretvalue = function() return false end
_G.wipe = function(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
    return tbl
end
_G.UnitExists = function() return true end
_G.UnitIsDeadOrGhost = function() return false end
_G.UnitHasVehicleUI = function() return false end
_G.UnitChannelInfo = function()
    if channelActive then return "Mind Flay", "Mind Flay", 136208, 0, 0, false, false, 15407 end
    return nil
end
local casting
_G.UnitCastingInfo = function()
    if not casting then return nil end
    return unpack(casting)
end
_G.UnitCastingDuration = nil
_G.UnitChannelDuration = nil
_G.C_DurationUtil = nil
_G.GetCVar = function(name)
    if name == "SpellQueueWindow" then return "600" end
    return nil
end
_G.MSUF_DB = { general = {} }

-- Widget factory. The explicit methods record what the castbar writes; any
-- other CamelCase method is a no-op. Data fields stay nil, and the native
-- timer API stays absent exactly as on a Classic client.
local function NoOp() end
local ABSENT_METHODS = { SetTimerDuration = true, ClearTimerDuration = true }
local widgetMeta = {
    __index = function(_, key)
        if type(key) == "string" and not ABSENT_METHODS[key] and key:match("^%u%a*$") then
            return NoOp
        end
        return nil
    end,
}

local function NewWidget(kind)
    local widget = setmetatable({ kind = kind, scripts = {}, hooks = {}, shown = true }, widgetMeta)

    function widget:SetScript(name, handler) self.scripts[name] = handler end
    function widget:GetScript(name) return self.scripts[name] end
    function widget:HookScript(name, handler)
        local list = self.hooks[name] or {}
        self.hooks[name] = list
        list[#list + 1] = handler
    end
    function widget:IsShown() return self.shown == true end
    function widget:Show() self.shown = true end
    function widget:Hide()
        if not self.shown then return end
        self.shown = false
        if self.scripts.OnHide then self.scripts.OnHide(self) end
        for _, handler in ipairs(self.hooks.OnHide or {}) do handler(self) end
    end
    function widget:SetMinMaxValues(minValue, maxValue) self.minValue, self.maxValue = minValue, maxValue end
    function widget:GetMinMaxValues() return self.minValue or 0, self.maxValue or 1 end
    function widget:SetValue(value)
        self.value = value
        if self.values then self.values[#self.values + 1] = value end
    end
    function widget:GetValue() return self.value or 0 end
    function widget:GetStatusBarColor() return 1, 0.7, 0, 1 end
    function widget:SetText(text)
        self.text = text
        local number = tonumber(text)
        if number and self.numbers then self.numbers[#self.numbers + 1] = number end
    end
    function widget:SetFormattedText(format, ...)
        self.text = string.format(format, ...)
        local number = tonumber((...))
        if number and self.numbers then self.numbers[#self.numbers + 1] = number end
    end
    function widget:GetText() return self.text end
    return widget
end

_G.CreateFrame = function(kind) return NewWidget(kind) end
_G.UIParent = NewWidget("Frame")
_G.GameFontHighlight = NewWidget("Font")

local ns = {
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
    Client = { IsClassic = true, IsVanilla = true },
}

local manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()
manifest.LoadSelected(root, "Vanilla", ns, {
    "Castbars/MSUF_CastbarUtils.lua",
    "Castbars/MSUF_CastbarRuntime.lua",
    "Castbars/MSUF_CastbarEngine.lua",
    "Castbars/MSUF_CastbarDriver.lua",
    "Castbars/MSUF_Castbars.lua",
})
-- The client runs zero-delay callbacks on the next frame; the files above
-- re-resolve their late-bound helpers there.
-- Glow recorder: while glowTotals is a table it records the total and skips
-- the real fade, otherwise it delegates. Installed before the zero-delay
-- callbacks so the castbar manager re-resolves this global.
local realGlowFade = assert(_G.MSUF_ApplyCastbarGlowFade, "MSUF_ApplyCastbarGlowFade missing")
local glowTotals
_G.MSUF_ApplyCastbarGlowFade = function(frame, remaining, total)
    if glowTotals then
        glowTotals[#glowTotals + 1] = total
        return
    end
    return realGlowFade(frame, remaining, total)
end
for index = 1, #pendingAfter do pendingAfter[index]() end
pendingAfter = {}

local manager = assert(_G.MSUF_CastbarManager, "castbar manager missing")
local RegisterCastbar = assert(_G.MSUF_RegisterCastbar, "MSUF_RegisterCastbar missing")
local UpdateCastbarFrame = assert(_G.MSUF_UpdateCastbarFrame, "MSUF_UpdateCastbarFrame missing")
local GetCountsDown = assert(_G.MSUF_GetCastbarCountsDown, "MSUF_GetCastbarCountsDown missing")
assert(type(_G.MSUF_CB_ResetStateOnStop) == "function", "MSUF_CB_ResetStateOnStop missing")

local function NewCastbar(unit)
    local frame = NewWidget("Frame")
    frame.shown = false
    frame.unit = unit
    frame._msufBarKey = unit
    frame.statusBar = NewWidget("StatusBar")
    frame.castText = NewWidget("FontString")
    frame.timeText = NewWidget("FontString")
    frame.completions = 0
    -- The driver's SetSucceeded ends in the shared runtime stop.
    function frame:SetSucceeded()
        self.completions = self.completions + 1
        _G.MSUF_CB_ResetStateOnStop(self, "SUCCEEDED")
    end
    return frame
end

-- Mirrors the driver's ApplyFallbackActiveDuration: a plain end-time snapshot,
-- the initial bar value, then manager registration.
local function SeedCast(frame, duration, isChannel)
    frame.interrupted = nil
    frame.MSUF_castActive = true
    frame.MSUF_durationObj = nil
    frame.MSUF_timerDriven = nil
    frame.MSUF_isChanneled = isChannel
    frame._msufHardStopNoChannelSince = nil
    frame._msufHardStopNoCastSince = nil
    frame._msufCountsDown = GetCountsDown(frame, isChannel) == true
    frame.endTime = clock + duration
    frame._msufPlainEndTime = frame.endTime
    frame._msufPlainTotal = duration
    frame._msufRemaining = duration
    frame.statusBar:SetMinMaxValues(0, duration)
    frame.statusBar:SetValue(frame._msufCountsDown and duration or 0)
    frame:Show()
    RegisterCastbar(frame)
end

local function StartRecording(frame)
    frame.statusBar.values = {}
    frame.timeText.numbers = {}
end

local function Step()
    clock = clock + STEP
    preciseOffset = 0
    local onUpdate = manager.shown and manager.scripts.OnUpdate
    if onUpdate then onUpdate(manager, STEP) end
end

local function Pump(steps)
    for _ = 1, steps do Step() end
end

local function AssertMonotonic(list, increasing, label)
    for index = 2, #list do
        local previous, current = list[index - 1], list[index]
        if increasing then
            assert(current >= previous - 1e-9, label .. " moved backwards at sample " .. index)
        else
            assert(current <= previous + 1e-9, label .. " moved forwards at sample " .. index)
        end
    end
end

-- A per-frame fill moves by at most one frame of cast time between writes.
local function AssertSmoothSteps(list, label)
    local limit = STEP * 1.05 + 1e-9
    for index = 2, #list do
        local delta = math.abs(list[index] - list[index - 1])
        assert(delta <= limit, label .. " jumped " .. delta .. " at sample " .. index)
    end
end

-- Pumps the manager and fails when one rendered frame wrote the fill twice.
local function PumpCounted(frame, steps)
    preciseDrift = true
    for _ = 1, steps do
        local before = #frame.statusBar.values
        Step()
        local writes = #frame.statusBar.values - before
        assert(writes <= 1, "one frame wrote the fill " .. writes .. " times")
    end
    preciseDrift = false
end

local function Extremes(list)
    local low, high = math.huge, -math.huge
    for index = 1, #list do
        if list[index] < low then low = list[index] end
        if list[index] > high then high = list[index] end
    end
    return low, high
end

local function AssertFinished(frame, label)
    assert(frame.completions == 1, label .. " completed " .. frame.completions .. " times")
    assert(manager.active[frame] == nil, label .. " stayed registered with the manager")
    assert(frame.shown == false and frame.MSUF_castActive == false, label .. " stayed visible or active")
end

-- 1. A 2 s target cast fills, counts its time text down and completes once.
local target = NewCastbar("target")
SeedCast(target, 2, false)
assert(target._msufTickInterval == 0.05,
    "Lua fill cast did not get the 20 Hz manager cadence: " .. tostring(target._msufTickInterval))
assert(manager.active[target] == true and manager.shown and manager.scripts.OnUpdate ~= nil,
    "manager did not take the Lua fill cast")
assert(target._msufCastbarWorkMask % 32 >= 16, "Lua fill cast lost the duration fallback work bit")
assert(target._msufLuaFill == true, "plain end-time cast did not take the per-frame fill")
StartRecording(target)
PumpCounted(target, 150)
local castValues = target.statusBar.values
assert(#castValues >= 110, "manager wrote only " .. #castValues .. " fill values for a 2 s cast at 60 fps")
AssertMonotonic(castValues, true, "cast fill")
AssertSmoothSteps(castValues, "cast fill")
local _, castMax = Extremes(castValues)
assert(castMax >= 1.9, "cast fill stopped short of the end: " .. castMax)
local castTimes = target.timeText.numbers
assert(#castTimes >= 10, "manager wrote only " .. #castTimes .. " time text values")
AssertMonotonic(castTimes, false, "cast time text")
AssertFinished(target, "cast")
assert(manager.scripts.OnUpdate == nil, "idle manager kept its OnUpdate")
assert(target._msufLuaFill == nil and target._msufLuaFillValue == nil,
    "finished cast kept its per-frame fill state")

-- 1b. The glow fades against the cast's plain total and never reads the status
-- bar range: GetMinMaxValues raises for the whole cast.
local glowCast = NewCastbar("focus")
SeedCast(glowCast, 2, false)
assert(glowCast._msufCastbarGlowTick == true, "Lua fill cast lost its glow tick")
function glowCast.statusBar:GetMinMaxValues()
    error("castbar glow read the status bar range", 2)
end
glowTotals = {}
Pump(150)
local recordedTotals = glowTotals
glowTotals = nil
assert(#recordedTotals >= 10, "glow ticked only " .. #recordedTotals .. " times")
for index = 1, #recordedTotals do
    assert(recordedTotals[index] == 2,
        "glow used total " .. tostring(recordedTotals[index]) .. " at tick " .. index)
end
AssertFinished(glowCast, "glow cast")

-- 2. A legacy pushback moves start and end together. The driver re-captures
-- the timing and registers again; the next fill value must drop back.
target.completions = 0
SeedCast(target, 2, false)
Pump(30)
UpdateCastbarFrame(target, 0)
local beforeDelay = target.statusBar.value
target.endTime = target.endTime + 0.5
target._msufPlainEndTime = target.endTime
StartRecording(target)
RegisterCastbar(target)
Step()
local afterDelay = target.statusBar.values[1]
assert(afterDelay and beforeDelay - afterDelay > 0.4,
    "pushback re-seed did not pull the fill back: " .. tostring(beforeDelay) .. " -> " .. tostring(afterDelay))
Pump(200)
AssertMonotonic(target.statusBar.values, true, "re-seeded fill")
AssertFinished(target, "pushed-back cast")

-- 3. A channel drains and completes once when UnitChannelInfo ends with it.
target.completions = 0
channelActive = true
SeedCast(target, 1.5, true)
assert(target._msufCountsDown == true, "non-unified channel does not count down")
assert(target._msufCastbarWorkMask % 8 >= 4, "channel lost the channel work bit")
StartRecording(target)
local channelEnd = target.endTime
local channelStoppedAt
for _ = 1, 300 do
    if clock >= channelEnd then
        channelActive = false
        channelStoppedAt = channelStoppedAt or clock
    end
    Step()
    if channelStoppedAt and clock >= channelStoppedAt + 0.15 then break end
end
assert(channelStoppedAt and clock >= channelStoppedAt + 0.15, "channel scenario never reached its end")
local channelValues = target.statusBar.values
assert(#channelValues >= 80, "manager wrote only " .. #channelValues .. " channel values for a 1.5 s channel")
AssertMonotonic(channelValues, false, "channel drain")
AssertSmoothSteps(channelValues, "channel drain")
local channelMin = Extremes(channelValues)
assert(channelMin <= 0.05, "channel did not drain to its end: " .. channelMin)
AssertFinished(target, "channel")

-- 4. UnitChannelInfo ends early without a stop event. SpellQueueWindow is 600,
-- so its grace (0.60 s + 0.10 s pad = 0.70 s) beats the 0.45 s base and stays
-- under the 0.80 s ceiling: the hard stop waits 0.70 s from its first silent
-- sample and then completes once. The hard stop samples manager time, which
-- advances with the fake clock, so the wait is measured in clock steps from the
-- step that took the first silent sample. Checks run every 0.15 s.
target.completions = 0
channelActive = true
SeedCast(target, 3, true)
StartRecording(target)
Pump(60)
channelActive = false
local silentAt = clock
local sampledAt, silentThreshold, completedAt
for _ = 1, 120 do
    Step()
    if target.completions > 0 then
        completedAt = clock
        break
    end
    if not sampledAt and target._msufHardStopNoChannelSince then sampledAt = clock end
    silentThreshold = target._msufHardStopChanThresh or silentThreshold
end
assert(completedAt, "silently ended channel never completed")
assert(sampledAt, "hard stop never sampled the silent channel")
assert(silentThreshold and math.abs(silentThreshold - 0.70) < 1e-9,
    "hard stop grace did not follow SpellQueueWindow: " .. tostring(silentThreshold))
local lag = completedAt - sampledAt
assert(lag >= 0.70 - 1e-6, "hard stop fired before the queue grace: " .. lag)
assert(completedAt - silentAt <= 1.2, "hard stop took too long: " .. (completedAt - silentAt))
AssertMonotonic(target.statusBar.values, false, "hard-stopped channel drain")
Pump(30)
AssertFinished(target, "hard-stopped channel")

-- 5. Legacy pushback through the real target driver. Classic cast tuples carry
-- no delayTimeMS, so UNIT_SPELLCAST_DELAYED only moves startTimeMS; the driver
-- measures that shift and repaints the cast text with the "+x.x" suffix.
_G.MSUF_DB.general.castbarShowPushback = true
local driven = assert(_G.MSUF_CreateCastBar("MSUF_TargetCastBar", "target"), "driver castbar missing")
driven.statusBar = NewWidget("StatusBar")
driven.castText = NewWidget("FontString")
local function FireCast(event) driven.scripts.OnEvent(driven, event, "target") end
local startMS = math.floor(clock * 1000)
casting = { "Fireball", "Fireball", 135812, startMS, startMS + 3000, false, "push-guid", false, 133 }
FireCast("UNIT_SPELLCAST_START")
assert(driven.castText.text == "Fireball" and driven._msufPushbackMS == nil,
    "driver START reported a pushback: " .. tostring(driven.castText.text))
clock = clock + 0.2
casting = { "Fireball", "Fireball", 135812, startMS + 400, startMS + 3400, false, "push-guid", false, 133 }
FireCast("UNIT_SPELLCAST_DELAYED")
assert(driven._msufPushbackMS == 400,
    "driver did not measure the legacy start shift: " .. tostring(driven._msufPushbackMS))
assert(driven.castText.text == "Fireball +0.4",
    "driver did not repaint the pushback suffix: " .. tostring(driven.castText.text))
clock = clock + 0.2
startMS = math.floor(clock * 1000)
casting = { "Frostbolt", "Frostbolt", 135846, startMS, startMS + 2500, false, "next-guid", false, 116 }
FireCast("UNIT_SPELLCAST_START")
assert(driven._msufPushbackMS == nil and driven.castText.text == "Frostbolt",
    "a new driver cast inherited the pushback: " .. tostring(driven.castText.text))

print("classic castbar Lua fill smoke passed")
