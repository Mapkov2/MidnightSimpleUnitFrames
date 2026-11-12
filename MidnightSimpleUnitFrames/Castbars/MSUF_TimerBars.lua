-- Optional mirror timers and countdowns. Only running, unpaused timers tick, and
-- only the events of enabled timers are registered: an unused timer costs nothing.
local _, MSUF = ...
local Bars = {}
MSUF.TimerBars = Bars
local FILE = "Castbars/MSUF_TimerBars.lua"
local IsSecret = issecretvalue
local Clock = GetTime
local MirrorInfo, MirrorProgress = GetMirrorTimerInfo, GetMirrorTimerProgress
local START_TYPES = Enum and Enum.StartTimerType or {}
local TYPES = { breath = "BREATH", fatigue = "EXHAUSTION", feign = "FEIGNDEATH" }
local DEFAULTS = {
    enabled = false, hideBlizzard = true, ownSize = false, width = 250, height = 18,
    x = 0, y = 200, lowWarning = false, warningPercent = 30, showUnderNumbers = false,
    r = 0.2, g = 0.65, b = 1, texture = "", backgroundTexture = "", timeFont = "",
    -- Text settings. An empty position and a size of 0 follow the Player castbar.
    labelPosition = "", labelSize = 0, labelX = 0, labelY = 0,
    timeFormat = "CURRENT", timePosition = "", timeSize = 0, timeX = 0, timeY = 0,
}
local LIMITS = {
    width = { 40, 1200 }, height = { 4, 100 }, x = { -2000, 2000 }, y = { -1200, 1200 },
    warningPercent = { 1, 100 }, r = { 0, 1 }, g = { 0, 1 }, b = { 0, 1 },
    labelSize = { 0, 48 }, timeSize = { 0, 48 },
    labelX = { -300, 300 }, labelY = { -300, 300 }, timeX = { -300, 300 }, timeY = { -300, 300 },
}
-- Text settings that take one of a fixed set of values; anything else reads as the default.
local POSITIONS = { [""] = true, LEFT = true, CENTER = true, RIGHT = true, ABOVE = true, BELOW = true }
local CHOICES = { labelPosition = POSITIONS, timePosition = POSITIONS,
    timeFormat = { CURRENT = true, ELAPSED = true, ELAPSED_MAX = true, CURRENT_MAX = true } }
Bars.Order = { "breath", "fatigue", "feign", "battle", "countdown" }
Bars.Labels = { breath = "Breath", fatigue = "Fatigue", feign = "Feign Death",
    battle = "Battle Start", countdown = "Group Countdown" }
Bars.States = {}
local byTimer, byCountdown = {}, {}
local driver = CreateFrame("Frame")
local enabled, editing, manualPreview, nativeQueued, ticking = false, false, false, false, false
local elapsedSinceUpdate = 0
local Apply, Resync, SyncDriver, SyncEvents, SyncNative

local function Public(value)
    return not (IsSecret and IsSecret(value))
end
local function Number(value)
    return Public(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end
Bars.IsPublicNumber = Number
for index, id in ipairs(Bars.Order) do
    local state = { id = id, index = index, timer = TYPES[id] }
    Bars.States[id] = state
    if state.timer then byTimer[state.timer] = state end
end
byTimer.DEATH = Bars.States.feign
Bars.States.battle.timerType, Bars.States.battle.numbersAt = START_TYPES.PvPBeginTimer, 11
Bars.States.countdown.timerType, Bars.States.countdown.numbersAt = START_TYPES.PlayerCountdown, 31
for _, id in ipairs({ "battle", "countdown" }) do
    local state = Bars.States[id]
    if state.timerType then byCountdown[state.timerType] = state end
end
-- Each timer names the events it needs; nothing else is ever registered for it.
local MIRROR_EVENTS = { "MIRROR_TIMER_START", "MIRROR_TIMER_STOP", "MIRROR_TIMER_PAUSE" }
local COUNTDOWN_EVENTS = { "START_TIMER", "STOP_TIMER_OF_TYPE" }
for _, id in ipairs(Bars.Order) do
    local state = Bars.States[id]
    state.events = state.timer and MIRROR_EVENTS or COUNTDOWN_EVENTS
end
Bars.States.countdown.events = { "START_TIMER", "STOP_TIMER_OF_TYPE", "START_PLAYER_COUNTDOWN", "CANCEL_PLAYER_COUNTDOWN" }
local wantedEvents, registeredEvents = {}, {}

function Bars.IsAvailable(id)
    local state = Bars.States[id]
    return state ~= nil and (state.timer and MirrorInfo ~= nil and MirrorProgress ~= nil or state.timerType ~= nil)
end
local function Saved(id, create)
    local db = MSUF.Castbars.Config.Source(false)
    if type(db) ~= "table" or type(db.general) ~= "table" then return end
    local all = db.general.castbarTimers
    if type(all) ~= "table" then
        if not create then return end
        all = {}
        db.general.castbarTimers = all
    end
    if type(all[id]) ~= "table" and create then all[id] = {} end
    return type(all[id]) == "table" and all[id] or nil
end
function Bars.Default(id, key)
    local state = Bars.States[id]
    if not state then return end
    if key == "y" then return 200 - (state.index - 1) * 28 end
    if key == "r" and id ~= "breath" then return 1 end
    if key == "g" and id ~= "breath" then return 0.7 end
    if key == "b" and id ~= "breath" then return 0.2 end
    return DEFAULTS[key]
end
function Bars.Get(id, key)
    if not Bars.States[id] or DEFAULTS[key] == nil then return end
    local cfg = Saved(id)
    local value = cfg and cfg[key]
    local fallback = Bars.Default(id, key)
    if type(fallback) == "boolean" then return value == true or (value == nil and fallback) end
    if type(fallback) == "string" then
        local choices = CHOICES[key]
        if type(value) ~= "string" or (choices and not choices[value]) then return fallback end
        return value
    end
    if not Number(value) then return fallback end
    local limit = LIMITS[key]
    return limit and math.max(limit[1], math.min(limit[2], value)) or value
end
function Bars.GetEnabled()
    for _, id in ipairs(Bars.Order) do
        if Bars.IsAvailable(id) and Bars.Get(id, "enabled") then return true end
    end
    return false
end
function Bars.CopySettings(state, id)
    state.id = id
    for key in pairs(DEFAULTS) do state[key] = Bars.Get(id, key) end
end
function Bars.IsPreview()
    return editing or manualPreview
end
local function Clear(state)
    state.active, state.paused, state.deadline, state.lastSecond = false, false, nil, nil
    if not state.frame then return end
    if state.enabled and Bars.IsPreview() then
        Bars.Paint(state, Clock(), true)
        state.frame:Show()
    else state.frame:Hide() end
end
local function Show(state, now)
    if not state.enabled then return end
    local preview = Bars.IsPreview()
    local visible = preview or state.active
    if visible and not preview and state.numbersAt and not state.showUnderNumbers then
        visible = state.value >= state.numbersAt * 1000
    end
    if visible then Bars.Paint(state, now, preview) end
    state.frame:SetShown(visible == true)
end
local function StartMirror(timer, value, maximum, scale, paused, label)
    if not Public(timer) or type(timer) ~= "string" then return end
    local state = byTimer[timer]
    if not state or not state.enabled or not Number(value) or not Number(maximum) or maximum <= 0 then return end
    if not Public(paused) then return end
    state.active, state.timerKey = true, timer
    state.value, state.maximum = math.max(0, value), maximum
    state.paused = paused == true or (Number(paused) and paused > 0)
    state.rising = Number(scale) and scale > 0
    state.label = Public(label) and type(label) == "string" and label or MSUF.Translate(Bars.Labels[state.id])
    state.lastSecond = nil
    Show(state, Clock())
end
local function StartCountdown(timerType, seconds, total)
    if not Public(timerType) then return end
    local state = byCountdown[timerType]
    if not state or not state.enabled or not Number(seconds) or not Number(total) then return end
    if seconds <= 0 or total <= 0 then Clear(state) return end
    state.active, state.paused, state.rising = true, false, false
    state.deadline, state.value, state.maximum = Clock() + seconds, seconds * 1000, total * 1000
    state.label, state.lastSecond = MSUF.Translate(Bars.Labels[state.id]), nil
    Show(state, Clock())
end

-- Native frames retain their parents, events and scripts. Keep ownership off-frame.
local muted = {}
local nativeGeneration = 0
local function NativeFrame(frame, state, tracker)
    if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
    if frame.IsProtected and frame:IsProtected() then return end
    local record = muted[frame]
    if enabled and state and state.enabled and state.active and state.hideBlizzard then
        if not record then
            record = { alpha = frame:GetAlpha(), tracker = tracker, shown = frame:IsShown() }
            muted[frame] = record
        end
        record.generation = nativeGeneration
        -- TimerTracker animates its child's alpha natively. Hiding only that
        -- unprotected child keeps fades from exposing it, while the parent
        -- continues its countdown, sounds and golden number animations.
        if tracker then frame:Hide() else frame:SetAlpha(0) end
    end
end
SyncNative = function()
    nativeGeneration = nativeGeneration + 1
    local container = MirrorTimerContainer
    local mirrors = container and container.mirrorTimers
    for i = 1, 3 do
        local frame = mirrors and mirrors[i]
        if not mirrors then
            if i == 1 then frame = MirrorTimer1 elseif i == 2 then frame = MirrorTimer2 else frame = MirrorTimer3 end
        end
        local timer = frame and frame.timer
        NativeFrame(frame, Public(timer) and byTimer[timer] or nil)
    end
    local tracker = TimerTracker
    if tracker and tracker.timerList then
        for _, timer in ipairs(tracker.timerList) do
            local timerType = timer.type
            NativeFrame(timer.bar, Public(timerType) and byCountdown[timerType] or nil, timer)
        end
    end
    for frame, record in pairs(muted) do
        if record.generation ~= nativeGeneration then
            local alpha = record.alpha
            if record.tracker then alpha = record.tracker.barShowing and 1 or 0 end
            frame:SetAlpha(alpha)
            if record.tracker then frame:SetShown(record.shown) end
            muted[frame] = nil
        end
    end
end
local function NativeLater()
    nativeQueued = false
    SyncNative()
end
local function QueueNative()
    if nativeQueued then return end
    nativeQueued = true
    C_Timer.After(0, NativeLater)
end
local function Tick(_, elapsed)
    elapsedSinceUpdate = elapsedSinceUpdate + elapsed
    if elapsedSinceUpdate < 0.05 then return end
    elapsedSinceUpdate = 0
    local now = Clock()
    for _, id in ipairs(Bars.Order) do
        local state = Bars.States[id]
        if state.enabled and state.active and not state.paused then
            local value
            if state.deadline then value = math.max(0, state.deadline - now) * 1000
            else value = MirrorProgress(state.timerKey) end
            if not Number(value) or value < 0 or (state.deadline and value == 0) then
                Clear(state)
            else
                if value ~= state.value then state.rising = value > state.value end
                state.value = value
                Show(state, now)
            end
        end
    end
    SyncNative()
    SyncDriver()
end
SyncDriver = function()
    local running = false
    for _, id in ipairs(Bars.Order) do
        local state = Bars.States[id]
        if state.enabled and state.active and not state.paused then running = true break end
    end
    if running == ticking then return end
    ticking, elapsedSinceUpdate = running, 0
    driver:SetScript("OnUpdate", running and Tick or nil)
end
Resync = function(world)
    for _, id in ipairs(Bars.Order) do
        local state = Bars.States[id]
        if state.timer or (world and id == "battle") then Clear(state) end
    end
    if MirrorInfo then
        for i = 1, 3 do StartMirror(MirrorInfo(i)) end
    end
    local tracker = TimerTracker
    if tracker and tracker.timerList then
        for _, timer in ipairs(tracker.timerList) do
            local timerType = timer.type
            local state = Public(timerType) and byCountdown[timerType]
            local deadline = timer.endTime
            if state and not (world and state.id == "battle") and not timer.isFree and Number(deadline) and timer.bar then
                local _, maximum = timer.bar:GetMinMaxValues()
                StartCountdown(timerType, deadline - Clock(), maximum)
            end
        end
    end
    for _, id in ipairs(Bars.Order) do Show(Bars.States[id], Clock()) end
    SyncDriver()
    QueueNative()
end
local function OnEvent(_, event, a, b, c, d, e, f)
    if event == "PLAYER_ENTERING_WORLD" then
        if not enabled then Apply() end
        if enabled then Resync(true) end
    elseif event == "MIRROR_TIMER_START" then StartMirror(a, b, c, d, e, f)
    elseif event == "MIRROR_TIMER_STOP" then
        local state = Public(a) and byTimer[a]
        if state and state.timerKey == a then Clear(state) end
    elseif event == "MIRROR_TIMER_PAUSE" then
        local state = Public(a) and byTimer[a]
        if state and state.timerKey == a and Public(b) then
            state.paused = b == true or (Number(b) and b > 0)
            Show(state, Clock())
        end
    elseif event == "START_TIMER" then StartCountdown(a, b, c)
    elseif event == "START_PLAYER_COUNTDOWN" then StartCountdown(START_TYPES.PlayerCountdown, b, c)
    elseif event == "CANCEL_PLAYER_COUNTDOWN" then Clear(Bars.States.countdown)
    elseif event == "STOP_TIMER_OF_TYPE" then
        local state = Public(a) and byCountdown[a]
        if state then Clear(state) end
    elseif event == "PLAYER_REGEN_DISABLED" then
        editing, manualPreview = false, false
        for _, id in ipairs(Bars.Order) do
            local state = Bars.States[id]
            if state.frame then state.frame:StopMovingOrSizing() state.frame:EnableMouse(false) end
            Show(state, Clock())
        end
        SyncEvents()
    end
    SyncDriver()
    QueueNative()
end
-- Registers exactly what the enabled timers need. Combat only matters while a
-- sample can be dragged, so its event exists during preview and Edit Mode alone.
SyncEvents = function()
    for event in pairs(wantedEvents) do wantedEvents[event] = nil end
    if enabled then
        wantedEvents.PLAYER_ENTERING_WORLD = true
        if Bars.IsPreview() then wantedEvents.PLAYER_REGEN_DISABLED = true end
        for _, id in ipairs(Bars.Order) do
            local state = Bars.States[id]
            if state.enabled then
                for _, event in ipairs(state.events) do wantedEvents[event] = true end
            end
        end
    end
    for event in pairs(registeredEvents) do
        if not wantedEvents[event] then
            driver:UnregisterEvent(event)
            registeredEvents[event] = nil
        end
    end
    for event in pairs(wantedEvents) do
        if not registeredEvents[event] then
            driver:RegisterEvent(event)
            registeredEvents[event] = true
        end
    end
end
Apply = function()
    local wanted = Bars.GetEnabled()
    local started = wanted and not enabled
    enabled = wanted
    for _, id in ipairs(Bars.Order) do
        local state = Bars.States[id]
        state.enabled = Bars.IsAvailable(id) and Bars.Get(id, "enabled")
        if state.enabled then
            Bars.CopySettings(state, id)
            state.frame = state.frame or Bars.Create(state)
            Bars.ApplyStyle(state)
            Show(state, Clock())
        else Clear(state) end
    end
    if enabled then
        SyncEvents()
        MSUF.EventBus:Register("CONFIG_APPLIED", "TimerBars", Apply)
        Resync(false)
    else
        manualPreview = false
        SyncEvents()
        MSUF.EventBus:Unregister("CONFIG_APPLIED", "TimerBars")
        SyncDriver()
        SyncNative()
    end
    if started then QueueNative() end
end
Bars.Apply = Apply
function Bars.Set(id, key, value)
    if not Bars.States[id] or DEFAULTS[key] == nil or MSUF.Util.InCombat() then return false end
    local fallback, limit = DEFAULTS[key], LIMITS[key]
    if type(fallback) == "boolean" then value = value == true
    elseif type(fallback) == "string" then
        local choices = CHOICES[key]
        if type(value) ~= "string" or #value > 260 or (choices and value ~= "" and not choices[value]) then return false end
        -- An empty choice follows the castbar; it and the default leave no profile override.
        if value == "" or value == fallback then value = nil end
    elseif not Number(value) or value < limit[1] or value > limit[2] then return false end
    local cfg = Saved(id, value ~= nil)
    if not cfg then return value == nil end
    cfg[key] = value
    Apply()
    return true
end
function Bars.SetColor(id, r, g, b)
    if MSUF.Util.InCombat() or not Bars.States[id] then return false end
    if not Number(r) or not Number(g) or not Number(b) then return false end
    if math.min(r, g, b) < 0 or math.max(r, g, b) > 1 then return false end
    local cfg = Saved(id, true)
    if not cfg then return false end
    cfg.r, cfg.g, cfg.b = r, g, b
    Apply()
    return true
end
function Bars.SavePosition(id, x, y)
    if MSUF.Util.InCombat() or not Number(x) or not Number(y) or not Bars.States[id] then return false end
    local cfg = Saved(id, true)
    if not cfg then return false end
    cfg.x = math.max(-2000, math.min(2000, math.floor(x + 0.5)))
    cfg.y = math.max(-1200, math.min(1200, math.floor(y + 0.5)))
    Apply()
    return true
end
function Bars.SetPreview(value)
    if value and MSUF.Util.InCombat() then return false end
    manualPreview = value == true
    Apply()
    return true
end
local function Shutdown()
    enabled, editing, manualPreview, ticking = false, false, false, false
    driver:UnregisterAllEvents()
    for event in pairs(registeredEvents) do registeredEvents[event] = nil end
    driver:SetScript("OnUpdate", nil)
    MSUF.EventBus:Unregister("CONFIG_APPLIED", "TimerBars")
    for _, id in ipairs(Bars.Order) do Clear(Bars.States[id]) end
    SyncNative()
end
local function EditChanged(value)
    editing = value == true and not MSUF.Util.InCombat()
    if enabled then Apply() end
end
MSUF.Require("MSUF_RegisterAnyEditModeListener", FILE)(EditChanged)
MSUF.MSUF_RegisterModule("TimerBars", { order = 76, IsEnabled = Bars.GetEnabled,
    Enable = Apply, Disable = Apply, RefreshSettings = Apply, Shutdown = Shutdown })
driver:SetScript("OnEvent", OnEvent)
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
registeredEvents.PLAYER_ENTERING_WORLD = true
