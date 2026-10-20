-- timed_signal_deadlines_smoke.lua <repoRoot>
--
-- Deadline timers run through the shared scheduler (Kernel/MSUF_Scheduler.lua)
-- and, on 12.1.5 and WoW Forever, through one C_Timer.NewTimedSignalMap.
-- Pinned here:
--   A. the scheduler takes the signal map only when the native constructor
--      exists (TimerUtil alone keeps C_Timer.After), and ScheduleAt hands an
--      absolute GetTime() deadline to SignalAt, a past one clamped to now; the
--      After fallback converts it to a clamped delay. One key policy for
--      ScheduleAfter and ScheduleAt, finite deadlines only, and no allocation
--      per reschedule on both paths.
--   B. on the real Mainline load graph (tools/tests/client_world.lua), once on
--      the signal map (12.1.5) and once on the C_Timer.After fallback (12.1.0):
--      1. the castbar native completion, whose deadline is on
--         GetTimePreciseSec, lands on the GetTime() clock (50 ms floor);
--      2. every delayed group offline hide is one key per frame;
--      3. the ready-check hide queue is one scheduler key, re-armed for its next
--         due hide after each pass; a cancelled frame is skipped;
--      4. the group hover tooltip is one debounced key, cancelled on leave;
--      5. the combat-state text clear is one key that a new combat edge moves;
--      6. (12.1.5 run) the preview pandemic region is styled once per paint;
--         the animation tick only flips its shown state.
--   C. the pandemic performance notes name 12.1.0 as the only per-frame
--      OnUpdate client, in the page and in all twelve locale packs.
-- Tip of the Spear (one re-armed key) is pinned in classpower_lifecycle_smoke.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local SCHEDULER = root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Scheduler.lua"

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
    return condition
end

-- A fake native signal map, built the way TimerUtil.CreateTimedSignalCallbackMap
-- builds one, on a caller-supplied clock. due[key] is the absolute deadline.
local function NewSignalMap(clock)
    local map = { callbacks = {}, due = {}, registered = 0, signalAt = 0, signalAfter = 0, cancels = 0 }
    function map:RegisterCallback(fn)
        self.registered = self.registered + 1
        self.callbacks[self.registered] = fn
        return self.registered
    end
    function map:SignalAt(key, time)
        assert(type(key) == "number" and type(time) == "number", "SignalAt takes a number key and time")
        self.signalAt = self.signalAt + 1
        self.due[key] = time
    end
    function map:SignalAfter(key, delay)
        assert(type(key) == "number" and type(delay) == "number", "SignalAfter takes a number key and delay")
        self.signalAfter = self.signalAfter + 1
        self.due[key] = clock() + delay
    end
    function map:CancelSignal(key)
        self.cancels = self.cancels + 1
        self.due[key] = nil
    end
    function map:Pending()
        local count = 0
        for _ in pairs(self.due) do count = count + 1 end
        return count
    end
    -- The earliest key due at the clock, or nil.
    function map:NextDue()
        local best, bestAt
        for key, at in pairs(self.due) do
            if at <= clock() + 1e-9 and (not bestAt or at < bestAt) then best, bestAt = key, at end
        end
        return best, bestAt
    end
    function map:Fire(key)
        self.due[key] = nil
        self.callbacks[key]()
    end
    return map
end

local function NativeConstructor()
    error("the scheduler builds its map through TimerUtil.CreateTimedSignalCallbackMap")
end

local function LoadScheduler(timer, timerUtil, now)
    C_Timer, TimerUtil = timer, timerUtil
    GetTime = function() return now() end
    CreateFrame = function() return { SetScript = function() end } end
    local ns = { ExportPublic = function() end }
    assert(loadfile(SCHEDULER))("MSUF", ns)
    return ns.Scheduler
end

-- A. Scheduler -------------------------------------------------------------
do
    local now = 100
    local clock = function() return now end
    -- Preallocated slots: the stub itself allocates nothing per call.
    local delays, fns, count = {}, {}, 0
    for i = 1, 4096 do delays[i], fns[i] = 0, false end
    local function After(delay, fn)
        count = count + 1
        delays[count], fns[count] = delay, fn
    end

    -- A TimerUtil without the native constructor keeps C_Timer.After.
    local wrapperOnly = NewSignalMap(clock)
    local s = LoadScheduler({ After = After }, { CreateTimedSignalCallbackMap = function() return wrapperOnly end }, clock)
    Check(s.signalMap == false, "A: a TimerUtil without C_Timer.NewTimedSignalMap selected the signal map")
    s.ScheduleAfter("key", 1, function() end)
    Check(count == 1 and wrapperOnly.signalAfter == 0,
        "A: without C_Timer.NewTimedSignalMap a delay did not go through C_Timer.After")

    -- With both, the map is built once through TimerUtil.
    local map = NewSignalMap(clock)
    s = LoadScheduler({ After = After, NewTimedSignalMap = NativeConstructor },
        { CreateTimedSignalCallbackMap = function() return map end }, clock)
    Check(s.signalMap == map, "A: the scheduler ignored the 12.1.5 signal map")
    local ran = {}
    local function Mark(name) return function() ran[#ran + 1] = name end end
    Check(type(s.ScheduleAt) == "function", "A: Scheduler.ScheduleAt is missing")
    if type(s.ScheduleAt) == "function" then
        s.ScheduleAt("deadline", 105.5, Mark("stale"))
        local signalKey = s.delayedKeys.deadline
        Check(map.signalAt == 1 and map.due[signalKey] == 105.5,
            "A: ScheduleAt did not hand its absolute deadline to SignalAt")
        s.ScheduleAfter("deadline", 2, Mark("after"))
        Check(map.registered == 1 and map.due[signalKey] == 102,
            "A: ScheduleAfter on a ScheduleAt key registered a second signal or kept the old deadline")
        s.ScheduleAt("deadline", 104, Mark("latest"))
        Check(map.registered == 1 and map.due[signalKey] == 104, "A: the last ScheduleAt did not move the deadline")
        map:Fire(signalKey)
        Check(table.concat(ran, ",") == "latest" and not s.IsScheduled("deadline"),
            "A: the last function did not run once: " .. table.concat(ran, ","))
        s.ScheduleAt("cancel", 101, Mark("cancelled"))
        Check(s.CancelScheduled("cancel") == true and map.due[s.delayedKeys.cancel] == nil,
            "A: CancelScheduled did not retire a ScheduleAt signal")
        -- A past deadline is clamped to now, as SignalAfter(0) was.
        s.ScheduleAt("past", 99, Mark("past"))
        Check(map.due[s.delayedKeys.past] == 100, "A: a past deadline reached SignalAt unclamped")
        s.CancelScheduled("past")
        for _, bad in ipairs({ 0 / 0, math.huge, -math.huge, "101" }) do
            Check(not pcall(s.ScheduleAt, "bad", bad, Mark("bad")) and not s.IsScheduled("bad"),
                "A: ScheduleAt accepted the deadline " .. tostring(bad))
        end
        Check(not pcall(s.ScheduleAt, "bad", 101, nil), "A: ScheduleAt accepted a missing callback")

        -- No allocation per reschedule on the signal path.
        s.ScheduleAt("burst", 110, Mark("burst"))
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for i = 1, 2000 do s.ScheduleAt("burst", 110 + i * 0.001, Mark) end
        local grown = collectgarbage("count") - before
        collectgarbage("restart")
        Check(grown < 1 and map.registered == 4,
            string.format("A: 2000 signal-map ScheduleAt reschedules allocated %.2f KB or registered more keys", grown))

        -- The C_Timer.After path converts the deadline to a clamped delay and
        -- keeps the scheduler's last-call-wins runner.
        count = 0
        s = LoadScheduler({ After = After }, nil, clock)
        ran = {}
        s.ScheduleAt("fallback", 102.5, Mark("early"))
        s.ScheduleAt("fallback", 103, Mark("fallback"))
        s.ScheduleAt("past", 99, Mark("past"))
        Check(count == 3 and delays[1] == 2.5 and delays[2] == 3 and delays[3] == 0,
            "A: the C_Timer.After path did not convert deadlines to clamped delays")
        now = 102.5
        fns[1]()
        Check(#ran == 0, "A: a superseded ScheduleAt deadline ran its work on the C_Timer.After path")
        now = 103
        fns[2]()
        fns[3]()
        Check(table.concat(ran, ",") == "fallback,past", "A: the C_Timer.After path ran " .. table.concat(ran, ","))
        count = 0
        collectgarbage("collect")
        collectgarbage("stop")
        before = collectgarbage("count")
        for i = 1, 2000 do s.ScheduleAt("fallback", 104 + i * 0.001, Mark) end
        grown = collectgarbage("count") - before
        collectgarbage("restart")
        Check(count == 2000 and grown < 1,
            string.format("A: 2000 C_Timer.After ScheduleAt reschedules allocated %.2f KB", grown))
    end
    C_Timer, TimerUtil, GetTime, CreateFrame = nil, nil, nil, nil
end

-- B. The real Mainline graph, on the signal map (12.1.5) and on C_Timer.After (12.1.0)
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function RunClient(signal)
    local label = signal and "B[12.1.5]" or "B[12.1.0]"
    local function Fail(condition, message) return Check(condition, label .. " " .. message) end
    local w = World.New(root, "Mainline")
    local env = w.env
    local function Now() return w.widgets:GetTime() end
    local map = NewSignalMap(Now)
    if signal then
        env.TimerUtil = { CreateTimedSignalCallbackMap = function() return map end }
        env.C_Timer.NewTimedSignalMap = NativeConstructor
    else
        env.TimerUtil = nil
    end
    -- Every C_Timer.After, the scheduler's fallback included, with its deadline.
    local afterQueue = {}
    env.C_Timer.After = function(delay, fn)
        afterQueue[#afterQueue + 1] = { due = Now() + delay, fn = fn }
    end
    local precise = 0
    env.GetTimePreciseSec = function() return w.widgets:GetTime() + precise end
    local OFFLINE = { party1 = true, party2 = true, party3 = true }
    env.UnitIsConnected = function(unit) return not OFFLINE[unit] end
    env.UnitExists = function(unit) return unit == "player" or OFFLINE[unit] == true end
    env.UnitIsPlayer = function(unit) return unit == "player" or OFFLINE[unit] == true end
    env.GetReadyCheckStatus = function() return nil end
    w:Boot()
    local failure = w:FirstFailure()
    assert(not failure, failure and (failure.file .. ": " .. failure.message))
    local core = w.core
    local Scheduler = core.Scheduler
    Fail((Scheduler.signalMap == map) == signal, "the scheduler picked the wrong delayed backend")

    -- Advance the clock to `to`, running every due signal and After callback in
    -- deadline order (a deadline already past runs at the current time).
    local function RunUntil(to)
        for _ = 1, 10000 do
            local bestAt, kind, ref
            for key, at in pairs(map.due) do
                if at <= to + 1e-9 and (not bestAt or at < bestAt) then bestAt, kind, ref = at, "signal", key end
            end
            for i = 1, #afterQueue do
                local due = afterQueue[i].due
                if due <= to + 1e-9 and (not bestAt or due < bestAt) then bestAt, kind, ref = due, "after", i end
            end
            if not bestAt then break end
            if bestAt > Now() then w.widgets:SetTime(bestAt) end
            if kind == "signal" then map:Fire(ref) else table.remove(afterQueue, ref).fn() end
        end
        if Now() < to then w.widgets:SetTime(to) end
    end
    w.widgets:RunTimers(1000)
    RunUntil(Now() + 5)

    -- The deadline the scheduler holds for a key on either backend.
    local function DueOf(key)
        if not Scheduler.IsScheduled(key) then return nil end
        if signal then return map.due[Scheduler.delayedKeys[key]] end
        return Scheduler.delayedDeadline[key]
    end
    local function Pending()
        local count = 0
        for _ in pairs(Scheduler.delayedPending) do count = count + 1 end
        return count
    end
    local function Near(a, b) return a ~= nil and b ~= nil and math.abs(a - b) < 1e-9 end
    local function NewTimers() return w.widgets.newTimerCount end

    -- B1. Castbar native completion: its deadline is on GetTimePreciseSec, so it
    -- goes to the scheduler as a delay and lands on the GetTime() clock.
    do
        local Runtime = core.Castbars and core.Castbars.Runtime
        if Fail(Runtime and Runtime.ArmNativeCompletion, "castbar runtime not loaded") then
            precise = 5000
            local t = Now()
            local frame = { _msufCastbarWorkMask = 0, _msufPlainEndTime = t + precise + 2 }
            Fail(Runtime:ArmNativeCompletion(frame) == true, "native completion did not arm")
            local key = frame._msufNativeCompletionCallback
            Fail(Near(DueOf(key), t + 2.05), "native completion is due at " .. tostring(DueOf(key))
                .. " on the GetTime() clock instead of " .. (t + 2.05))
            frame._msufPlainEndTime = t + precise - 1
            Runtime:ArmNativeCompletion(frame)
            Fail(Near(DueOf(key), t + 0.05), "native completion lost its 50 ms floor")
            Runtime:CancelNativeCompletion(frame)
            Fail(DueOf(key) == nil, "cancelling native completion left it scheduled")
            precise = 0
        end
    end

    -- B2. Delayed group offline hide: one key per frame.
    local GF, UF = core.GF, core.UF
    local function GroupMember(unit, delay)
        local frame = env.CreateFrame("Button", nil, env.UIParent)
        frame.MSUFUnitKey = unit
        frame.MSUFSpec = {
            scope = "group",
            group = { hideOfflineEnabled = true, hideOfflineInCombat = false, offlineAlpha = 0.5, hideOfflineDelay = delay },
        }
        GF.frames = GF.frames or {}
        GF.frames[frame] = true
        return frame
    end
    do
        local element = UF.elements and UF.elements.GroupRangeFade
        if Fail(element, "GroupRangeFade not registered") then
            local t = Now()
            local pending, timers, signals = Pending(), NewTimers(), map:Pending()
            local early, late = GroupMember("party1", 2), GroupMember("party2", 5)
            element.Apply(early)
            element.Apply(late)
            Fail(early:GetAlpha() == 0.5 and late:GetAlpha() == 0.5, "a delayed offline hide did not start at the offline fade")
            Fail(NewTimers() == timers, "the offline delay created C_Timer.NewTimer objects")
            Fail(Pending() == pending + 2, "two delayed frames did not own one scheduler key each")
            Fail(not signal or map:Pending() == signals + 2, "two delayed frames did not own one signal each")
            Fail(Near(DueOf(early._msufGFOfflineDelayExpiry), t + 2) and Near(DueOf(late._msufGFOfflineDelayExpiry), t + 5),
                "a frame's offline hide is not due at its own deadline")
            RunUntil(t + 2)
            Fail(early:GetAlpha() == 0 and late:GetAlpha() == 0.5,
                "the first deadline hid " .. tostring(early:GetAlpha()) .. "/" .. tostring(late:GetAlpha()))
            RunUntil(t + 5)
            Fail(late:GetAlpha() == 0, "the later frame was not hidden at its own deadline")
            local gone = GroupMember("party3", 4)
            element.Apply(gone)
            local key = gone._msufGFOfflineDelayExpiry
            Fail(DueOf(key) ~= nil, "the third frame did not queue its hide")
            element.Disable(gone)
            Fail(DueOf(key) == nil and (not signal or map.due[Scheduler.delayedKeys[key]] == nil),
                "disabling a delayed frame left its key armed")
            for _, frame in ipairs({ early, late, gone }) do
                element.Disable(frame)
                GF.frames[frame] = nil
            end
        end
    end

    -- B3. Ready-check icon hide: the shared queue owns one scheduler key, re-armed
    -- for the next due hide; a cancelled frame is skipped when it fires.
    do
        local Status = core.UFStatusRuntime
        if Fail(Status and Status.UpdateReadyCheck, "status runtime not loaded") then
            local KEY = "MSUF_READY_CHECK_HIDE"
            local status = { readyCheck = { enabled = true } }
            local function Member(unit)
                local frame = env.CreateFrame("Button", nil, env.UIParent)
                frame.MSUFUnitKey = unit
                frame.readyCheckIcon = frame:CreateTexture()
                frame.readyCheckIcon:Show()
                return frame
            end
            local a, b = Member("party1"), Member("party2")
            local t = Now()
            local pending, signals, queued = Pending(), map:Pending(), #afterQueue
            Status.UpdateReadyCheck(a, status, "READY_CHECK_FINISHED")
            Status.UpdateReadyCheck(b, status, "READY_CHECK_FINISHED")
            Fail(Pending() == pending + 1 and Near(DueOf(KEY), t + 6),
                "two ready-check hides are not one scheduler key due at the first hide")
            Fail(signal and (map:Pending() == signals + 1 and #afterQueue == queued) or (not signal and #afterQueue == queued + 1),
                "a ready-check batch armed more than one native timer")
            RunUntil(t + 3)
            queued = #afterQueue
            Status.UpdateReadyCheck(a, status, "READY_CHECK_FINISHED")
            Fail(Pending() == pending + 1 and Near(DueOf(KEY), t + 6) and #afterQueue == queued,
                "a later re-queue armed another timer or moved the earlier deadline")
            Status.UpdateReadyCheck(b, { readyCheck = { enabled = false } }, "READY_CHECK_FINISHED")
            b.readyCheckIcon:Show()
            RunUntil(t + 6.5)
            Fail(a.readyCheckIcon:IsShown() and b.readyCheckIcon:IsShown(),
                "the re-queued hide or the cancelled one ran at the first deadline")
            Fail(Pending() == pending + 1 and Near(DueOf(KEY), t + 9), "the queue key was not re-armed for the re-queued hide")
            RunUntil(t + 9.1)
            Fail(not a.readyCheckIcon:IsShown(), "the re-queued hide did not run at its moved deadline")
            Fail(b.readyCheckIcon:IsShown(), "the cancelled hide still ran")
            Fail(Pending() == pending, "the ready-check queue left its key scheduled")
        end
    end

    -- B4. Group hover tooltip: one debounced key, cancelled on leave.
    do
        local tooltips = core.Tooltips
        if Fail(tooltips and GF.PortraitMouseEnter, "unit tooltips or the group adapter not loaded") then
            local shown = {}
            local saved = { tooltips.hoverInert, tooltips.Allowed, tooltips.ShowUnit, tooltips.HideUnit, tooltips.TrackUnitHover }
            tooltips.hoverInert = false
            tooltips.Allowed = function() return true end
            tooltips.ShowUnit = function(frame) shown[#shown + 1] = frame end
            tooltips.HideUnit = function() end
            tooltips.TrackUnitHover = nil
            local function Hovered(unit)
                local frame = env.CreateFrame("Button", nil, env.UIParent)
                frame.MSUFUnitKey = unit
                frame.IsMouseOver = function() return true end
                return frame
            end
            local a, b, c, d = Hovered("party1"), Hovered("party2"), Hovered("party3"), Hovered("party4")
            local t = Now()
            local pending, queued, signals = Pending(), #afterQueue, map:Pending()
            GF.PortraitMouseEnter(a)
            w.widgets:SetTime(t + 0.05)
            GF.PortraitMouseEnter(b)
            w.widgets:SetTime(t + 0.1)
            GF.PortraitMouseEnter(c)
            Fail(Pending() == pending + 1, "a hover sweep held more than one scheduler key")
            Fail(not signal or (#afterQueue == queued and map:Pending() == signals + 1),
                "a hover sweep armed C_Timer.After calls or more than one signal")
            Fail(Near(DueOf("MSUF_GF_TOOLTIP_HOVER"), t + 0.22), "the hover deadline did not follow the last hover")
            RunUntil(t + 0.3)
            Fail(#shown == 1 and shown[1] == c, "the sweep showed " .. #shown .. " tooltips, not only the settled frame")
            GF.PortraitMouseEnter(d)
            GF.PortraitMouseLeave(d)
            Fail(DueOf("MSUF_GF_TOOLTIP_HOVER") == nil, "leaving the frame left its hover key armed")
            RunUntil(t + 1)
            Fail(#shown == 1, "a frame left before the delay still showed its tooltip")
            tooltips.hoverInert, tooltips.Allowed, tooltips.ShowUnit, tooltips.HideUnit, tooltips.TrackUnitHover =
                saved[1], saved[2], saved[3], saved[4], saved[5]
        end
    end

    -- B5. Combat-state text: a new combat edge moves the pending clear. The
    -- product no longer reaches for C_Timer.NewTimer, so its absence (the case
    -- whose After fallback could not be cancelled) changes nothing.
    do
        local db = core.MSUF_EnsureGameplayDefaults and core.MSUF_EnsureGameplayDefaults()
        if Fail(db and core.MSUF_ApplyGameplayVisuals, "gameplay runtime not loaded") then
            -- Only the combat-state text: the other gameplay features stay off here.
            db.enableCombatTimer, db.enableCombatCrosshair, db.enablePlayerTotems = false, false, false
            db.enableCombatStateText, db.lockCombatState, db.combatStateDuration = true, true, 1.5
            core.MSUF_ApplyGameplayVisuals()
            RunUntil(Now())
            local text
            for _, owned in ipairs(w.widgets.frames) do
                if owned:GetName() == "MSUF_CombatStateFrame" then
                    for _, region in ipairs(owned.regions or {}) do
                        if region.GetText then text = region end
                    end
                end
            end
            if Fail(text, "the combat state text was not created") then
                local newTimer = env.C_Timer.NewTimer
                env.C_Timer.NewTimer = nil
                local t = Now()
                w:EnterCombat()
                Fail(text:GetText() == "+Combat" and text:IsShown(), "entering combat did not show its text")
                RunUntil(t + 1)
                w:LeaveCombat()
                local left = Now()
                Fail(text:GetText() == "-Combat" and text:IsShown(), "leaving combat did not show its text")
                Fail(Near(DueOf("MSUF_COMBAT_STATE_CLEAR"), left + 1.5),
                    "the combat edge did not move the pending clear to its own deadline")
                RunUntil(t + 1.6)
                Fail(text:GetText() == "-Combat" and text:IsShown(), "the entering edge's clear blanked the leaving text early")
                RunUntil(left + 1.6)
                Fail(not text:IsShown(), "the leaving text was not cleared after its duration")
                env.C_Timer.NewTimer = newTimer
            end
            db.enableCombatStateText = false
            core.MSUF_ApplyGameplayVisuals()
            RunUntil(Now())
        end
    end
    return w, core
end

RunClient(false)
local w, core = RunClient(true)
local env, GF = w.env, core.GF

-- B6. Preview pandemic: styled once per paint, toggled per tick.
do
    local Auras = core.MSUF_Auras3
    local found, seenFn, seenTable = {}, {}, {}
    local WANT = { ApplyFrameAuraPreview = true, EnsureAuraPreview = true, EnsureFrameAuraLaneHost = true }
    local WalkTable
    local function WalkFunction(fn, name, depth)
        if type(fn) ~= "function" or seenFn[fn] or depth > 18 then return end
        seenFn[fn] = true
        if WANT[name] and debug.getinfo(fn, "S").source:find("MSUF_UF_Group_Preview.lua", 1, true) then found[name] = fn end
        for index = 1, 60 do
            local childName, child = debug.getupvalue(fn, index)
            if not childName then break end
            if type(child) == "function" then WalkFunction(child, childName, depth + 1)
            elseif type(child) == "table" and not rawget(child, "objectType") and childName ~= "_G" and childName ~= "env" then
                WalkTable(child, depth + 1)
            end
        end
    end
    WalkTable = function(tbl, depth)
        if seenTable[tbl] or depth > 12 or rawget(tbl, "objectType") then return end
        seenTable[tbl] = true
        for key, value in pairs(tbl) do
            if type(value) == "function" then WalkFunction(value, tostring(key), depth + 1) end
        end
    end
    WalkTable(GF, 0)
    if Check(Auras and Auras.ApplyPandemicVisual and found.ApplyFrameAuraPreview and found.EnsureAuraPreview
        and found.EnsureFrameAuraLaneHost and GF.NewPreviewScene, "B6: group preview painters not found") then
        local parent = env.CreateFrame("Frame", nil, env.UIParent)
        parent:SetSize(40, 30)
        parent:Show()
        local rootScene = GF.NewPreviewScene(parent)
        local frame = rootScene:Unit("player"):Frame()
        local host = found.EnsureFrameAuraLaneHost(frame, "debuff")
        host:SetSize(200, 80)
        host:Show()
        frame:Show()
        local lane = { size = 24, iconZoom = 100, initialAnchor = "TOPLEFT", perRow = 3, xSign = 1, ySign = -1,
            targetDots = true, pandemicEnabled = true, pandemicStyle = "BORDER", pandemicColor = { 1, 0, 0 } }
        local visual = found.EnsureAuraPreview(frame, 1, "_msufGFFrameAuraPreviews")
        local function Paint()
            found.ApplyFrameAuraPreview(frame, "unit", visual, lane, { key = "debuff", textures = { 135987 } }, 0, 1, host)
        end
        Paint()
        GF.AnimateUnitFrameAuras(frame, 1)
        local region = visual._msufA3PandemicRegion
        if Check(region, "B6: the preview did not build its pandemic region") then
            local owned = { [region] = true, [region.tint] = true, [region.shapeBorder] = true }
            for i = 1, #region.edges do owned[region.edges[i]] = true end
            local calls = 0
            local tables, saved = {}, {}
            tables[w.widgets.Methods] = true
            tables[getmetatable(env.UIParent).__index] = true
            for methods in pairs(tables) do
                saved[methods] = {}
                for name, method in pairs(methods) do
                    if type(name) == "string" and name:find("^Set") and type(method) == "function" then
                        saved[methods][name] = method
                        methods[name] = function(self, ...)
                            if owned[self] then calls = calls + 1 end
                            return method(self, ...)
                        end
                    end
                end
            end
            local hiddenAt1 = not region:IsShown()
            GF.AnimateUnitFrameAuras(frame, 13)
            local shownAt13 = region:IsShown()
            for tick = 1, 18 do GF.AnimateUnitFrameAuras(frame, tick % 2 == 0 and 13 or 1) end
            local perTick = calls / 19
            for methods, names in pairs(saved) do
                for name, method in pairs(names) do methods[name] = method end
            end
            Check(hiddenAt1 and shownAt13, "B6: the animation tick no longer follows the pandemic window")
            Check(perTick <= 1, string.format("B6: an animation tick made %.1f widget calls on the pandemic region", perTick))
            -- A repaint restyles once: a new color reaches the region.
            lane.pandemicColor = { 0, 1, 0 }
            Paint()
            GF.AnimateUnitFrameAuras(frame, 13)
            local _, g = region.edges[1]:GetVertexColor()
            Check(g == 1, "B6: a repaint did not restyle the pandemic region")
        end
        rootScene:Release()
    end
end

-- C. Pandemic performance notes ----------------------------------------------
do
    local function Read(relative)
        local file = assert(io.open(root .. "/" .. relative, "rb"))
        local text = file:read("*a")
        file:close()
        return text
    end
    local page = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace.lua")
    local NOTES = {
        "PERFORMANCE NOTE: On 12.1.0 Blizzard runs an OnUpdate every frame on each visible aura button",
        "Disabled by default. On 12.1.0 Blizzard's native implementation enables a per-frame OnUpdate",
        "Shows this effect only while a tracked DoT is in its native Pandemic window. Multiple DoTs in Pandemic can "
            .. "intensify the same effect. On 12.1.0 Blizzard runs an OnUpdate on each visible aura button",
    }
    for i = 1, #NOTES do
        Check(page:find(NOTES[i], 1, true), "C: the custom workspace lost note " .. i)
    end
    Check(page:find("not only while the warning is shown; enable it there only if you accept that combat cost.", 1, true),
        "C: the custom workspace note lost its 12.1.0 advice")
    for _, stale in ipairs({ "PERFORMANCE WARNING (12.1):", "Blizzard may run an OnUpdate on each visible aura button",
        "Disabled by default. Blizzard's native implementation enables a per-frame OnUpdate" }) do
        Check(not page:find(stale, 1, true), "C: the custom workspace still claims " .. stale)
    end
    for _, code in ipairs({ "enUS", "enGB", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
        local pack = Read("MidnightSimpleUnitFrames/Locales/" .. code .. ".lua")
        local english = code == "enUS" or code == "enGB"
        for i = 1, #NOTES do
            local present = pack:find('L["' .. NOTES[i], 1, true) ~= nil
            Check(present or (english and i == 3), "C: " .. code .. " has no translation of note " .. i)
        end
        Check(not pack:find("PERFORMANCE WARNING (12.1):", 1, true)
            and not pack:find("Blizzard may run an OnUpdate on each visible aura button", 1, true),
            "C: " .. code .. " still carries a stale pandemic OnUpdate warning")
        for i = 1, #NOTES do
            local line = pack:match('L%["' .. NOTES[i]:gsub("%p", "%%%0") .. '[^\r\n]*')
            local value = line and line:match('%] = "(.*)"')
            Check(not line or (value and value:find("12.1.0", 1, true) and value:find("12.1.5", 1, true)),
                "C: " .. code .. " note " .. i .. " does not name both 12.1.0 and 12.1.5")
        end
    end
end

if #failures > 0 then
    error("timed_signal_deadlines_smoke:\n  " .. table.concat(failures, "\n  "), 0)
end
print("timed_signal_deadlines_smoke: OK (scheduler ScheduleAt and native gate, castbar, group offline, ready check, "
    .. "hover tooltip, combat state, preview pandemic, notes)")
