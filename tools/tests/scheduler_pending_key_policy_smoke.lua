-- The scheduler has two keyed policies and they differ on purpose
-- (Kernel/MSUF_Scheduler.lua, header):
--   RunNextFrame / ScheduleOnce  the FIRST function queued for a pending key
--                                wins; later calls for it are ignored
--   ScheduleAfter / ScheduleAt   the LAST function and the LAST deadline win
-- Pinned here on both delayed backends (TimedSignalMap and C_Timer.After), plus
-- the independence of the two tables.
-- Usage: lua tools/tests/scheduler_pending_key_policy_smoke.lua <repoRoot>
local repo = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local schedulerPath = arg[2] or repo .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Scheduler.lua"

local frame
local function NewFrame()
    frame = { update = nil }
    function frame:SetScript(_, fn) self.update = fn end
    return frame
end

local function Flush()
    assert(frame.update, "nothing is armed for the next frame")
    frame.update()
end

local function LoadScheduler()
    local ns = { ExportPublic = function() end }
    CreateFrame = NewFrame
    assert(loadfile(schedulerPath))("MSUF", ns)
    return ns.Scheduler
end

local function Log()
    local ran = {}
    local function Mark(name) return function() ran[#ran + 1] = name end end
    local function Reset() for i = #ran, 1, -1 do ran[i] = nil end end
    return ran, Mark, Reset
end

-- Next-frame policy: first function wins, backend independent. ---------------
do
    TimerUtil = nil
    C_Timer = { After = function() end }
    local s = LoadScheduler()
    local ran, mark, reset = Log()

    s.ScheduleOnce("key", mark("first"))
    s.ScheduleOnce("key", mark("second"))
    s.ScheduleOnce("other", mark("other"))
    Flush()
    assert(table.concat(ran, ",") == "first,other",
        "ScheduleOnce must keep the first function for a pending key, ran: " .. table.concat(ran, ","))
    assert(frame.update == nil, "the driver stayed armed after the queue drained")

    -- The key is free again once the queued callback has been taken.
    reset()
    s.ScheduleOnce("key", function()
        ran[#ran + 1] = "third"
        s.ScheduleOnce("key", function() ran[#ran + 1] = "fourth" end)
        s.ScheduleOnce("key", function() ran[#ran + 1] = "ignored" end)
    end)
    Flush()
    assert(table.concat(ran, ",") == "third", "a callback must not run its own re-queue in the same frame")
    Flush()
    assert(table.concat(ran, ",") == "third,fourth", "re-queueing a key from its own callback lost the first re-queue")
    assert(frame.update == nil)

    -- The key defaults to the function: one function queued twice runs once, two closures both run.
    reset()
    local same = mark("same")
    s.ScheduleOnce(nil, same)
    s.ScheduleOnce(nil, same)
    s.ScheduleOnce(nil, mark("distinct"))
    s.RunNextFrame(same)
    s.RunNextFrame(mark("distinct2"))
    Flush()
    assert(table.concat(ran, ",") == "same,distinct,distinct2",
        "default key must be the function itself, ran: " .. table.concat(ran, ","))
end

-- Delayed policy on C_Timer.After: last function and last deadline win. -------
do
    TimerUtil = nil
    local timers = {}
    C_Timer = { After = function(delay, callback) timers[#timers + 1] = { delay = delay, callback = callback } end }
    local now = 100
    GetTime = function() return now end
    local s = LoadScheduler()
    local ran, mark, reset = Log()

    -- A later, longer request replaces the earlier one; the earlier timer steps aside.
    s.ScheduleAfter("key", 1, mark("early"))
    s.ScheduleAfter("key", 3, mark("late"))
    assert(#timers == 2 and s.IsScheduled("key"))
    now = 101
    timers[1].callback()
    assert(#ran == 0, "the superseded timer ran the work before the newest deadline")
    now = 103
    timers[2].callback()
    assert(table.concat(ran, ",") == "late", "the last function must run, ran: " .. table.concat(ran, ","))
    assert(not s.IsScheduled("key"))

    -- A later, shorter request wins too: the work runs at the new deadline.
    timers = {}
    reset()
    now = 200
    s.ScheduleAfter("key", 3, mark("long"))
    s.ScheduleAfter("key", 1, mark("short"))
    now = 201
    timers[2].callback()
    assert(table.concat(ran, ",") == "short", "the last request's deadline must win, ran: " .. table.concat(ran, ","))
    now = 203
    timers[1].callback()
    assert(table.concat(ran, ",") == "short", "the superseded long timer ran stale work")

    -- Cancelling leaves nothing behind.
    timers = {}
    reset()
    s.ScheduleAfter("key", 1, mark("cancelled"))
    assert(s.CancelScheduled("key") == true and not s.IsScheduled("key"))
    timers[1].callback()
    assert(#ran == 0, "a cancelled delayed callback ran")
    assert(s.CancelScheduled("key") == false and s.CancelScheduled(nil) == false)
end

-- Delayed policy on TimedSignalMap: one registered signal per key, re-signalled. -
do
    local map = { registered = 0, callbacks = {}, signals = {}, cancelled = {} }
    function map:RegisterCallback(fn)
        self.registered = self.registered + 1
        self.callbacks[self.registered] = fn
        return self.registered
    end
    function map:SignalAfter(signalKey, delay) self.signals[#self.signals + 1] = { signalKey, delay } end
    function map:CancelSignal(signalKey) self.cancelled[signalKey] = true end
    TimerUtil = { CreateTimedSignalCallbackMap = function() return map end }
    -- The native constructor must exist for the scheduler to pick this backend;
    -- without After, a fallback would fail to load instead of passing silently.
    C_Timer = { NewTimedSignalMap = function() error("built through TimerUtil") end }
    local s = LoadScheduler()
    local ran, mark, reset = Log()

    s.ScheduleAfter("key", 5, mark("first"))
    s.ScheduleAfter("key", 1, mark("second"))
    assert(map.registered == 1, "a reschedule must reuse the key's signal, registered " .. map.registered)
    assert(#map.signals == 2 and map.signals[2][2] == 1, "the last deadline must be the one signalled last")
    map.callbacks[1]()
    assert(table.concat(ran, ",") == "second", "the last function must run, ran: " .. table.concat(ran, ","))
    map.callbacks[1]()
    assert(#ran == 1, "a signal with nothing pending ran work")

    s.ScheduleAfter("key", 1, mark("cancelled"))
    assert(s.CancelScheduled("key") == true and map.cancelled[1] == true)
    map.callbacks[1]()
    assert(#ran == 1, "a cancelled signal ran work")
end

-- The two tables are independent: one key can be pending in both. -------------
do
    TimerUtil = nil
    local timers = {}
    C_Timer = { After = function(delay, callback) timers[#timers + 1] = { delay = delay, callback = callback } end }
    GetTime = nil
    local s = LoadScheduler()
    local ran, mark, reset = Log()

    s.ScheduleOnce("shared", mark("next-frame"))
    s.ScheduleAfter("shared", 1, mark("delayed"))
    assert(s.IsScheduled("shared") == true, "IsScheduled must report the delayed work")
    assert(s.CancelScheduled("shared") == true)
    Flush()
    assert(table.concat(ran, ",") == "next-frame", "cancelling delayed work must not drop the next-frame callback")
    timers[1].callback()
    assert(table.concat(ran, ",") == "next-frame", "the cancelled delayed callback ran")
end

-- Absolute deadlines: execute callbacks through a chronological fake clock,
-- rather than firing them manually and hiding deadline conversion mistakes.
local function CheckDeadlines(native)
    local now, timers, callbacks, signals = 100, {}, {}, {}
    local map = {}
    GetTime = function() return now end
    function map:RegisterCallback(fn)
        callbacks[#callbacks + 1] = fn
        return #callbacks
    end
    function map:SignalAt(key, at) signals[key] = at end
    function map:SignalAfter() error("ScheduleAt must use native absolute deadlines") end
    function map:CancelSignal(key) signals[key] = nil end
    if native then
        TimerUtil = { CreateTimedSignalCallbackMap = function() return map end }
        C_Timer = { NewTimedSignalMap = function() error("built through TimerUtil") end }
    else
        TimerUtil = nil
        C_Timer = { After = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end }
    end
    local s, ran = LoadScheduler(), {}
    local function Mark(name)
        return function() ran[#ran + 1] = { name, now } end
    end
    local function Advance(at)
        assert(at >= now)
        while true do
            local first, deadline
            if native then
                for key, due in pairs(signals) do
                    if due <= at and (deadline == nil or due < deadline) then first, deadline = key, due end
                end
            else
                for key, timer in ipairs(timers) do
                    if timer.at <= at and (deadline == nil or timer.at < deadline) then first, deadline = key, timer.at end
                end
            end
            if not first then break end
            assert(deadline >= now, "backend received a deadline in the past")
            now = deadline
            if native then
                signals[first] = nil
                callbacks[first]()
            else
                table.remove(timers, first).fn()
            end
        end
        now = at
    end
    local function Expect(count, name, at)
        assert(#ran == count, "unexpected callback count: " .. #ran .. ", expected " .. count)
        if name then
            assert(ran[count][1] == name and ran[count][2] == at, "wrong callback or actual execution time")
        end
    end

    assert(s.ScheduleAt("key", 50, Mark("past")) == true and s.IsScheduled("key"))
    Expect(0) -- Even a past deadline waits for backend dispatch.
    Advance(100)
    Expect(1, "past", 100)
    assert(not s.IsScheduled("key"))

    Advance(200)
    s.ScheduleAt("key", 240, Mark("future"))
    Advance(239)
    Expect(1)
    Advance(240)
    Expect(2, "future", 240)

    Advance(300)
    s.ScheduleAt("key", 310, Mark("replaced"))
    Advance(302)
    s.ScheduleAt("key", 320, Mark("later"))
    Advance(310)
    Expect(2)
    Advance(320)
    Expect(3, "later", 320)

    Advance(400)
    s.ScheduleAt("key", 430, Mark("replaced"))
    Advance(402)
    s.ScheduleAt("key", 410, Mark("earlier"))
    Advance(409)
    Expect(3)
    Advance(410)
    Expect(4, "earlier", 410)
    Advance(430)
    Expect(4)

    Advance(500)
    s.ScheduleAt("key", 510, Mark("cancelled"))
    assert(s.CancelScheduled("key") and not s.IsScheduled("key"))
    assert(not s.CancelScheduled("key"))
    Advance(510)
    Expect(4)

    Advance(600)
    s.ScheduleAt("key", 610, Mark("cancelled"))
    s.CancelScheduled("key")
    Advance(602)
    s.ScheduleAt("key", 620, Mark("reused"))
    Advance(610)
    Expect(4)
    Advance(620)
    Expect(5, "reused", 620)
    assert(not s.IsScheduled("key"))
    if native then assert(#callbacks == 1, "rescheduling registered extra native callbacks") end

    local callback = Mark("default-key")
    s.ScheduleAt(nil, 650, callback)
    assert(s.IsScheduled(callback))
    Advance(650)
    Expect(6, "default-key", 650)
    assert(not s.IsScheduled(callback))
    print("ScheduleAt deadlines: " .. (native and "TimedSignalMap" or "C_Timer.After") .. " OK")
end
CheckDeadlines(false)
CheckDeadlines(true)

print("scheduler_pending_key_policy_smoke: OK")
