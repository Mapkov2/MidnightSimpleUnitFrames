-- The scheduler has two keyed policies and they differ on purpose
-- (Kernel/MSUF_Scheduler.lua, header):
--   RunNextFrame / ScheduleOnce  the FIRST function queued for a pending key
--                                wins; later calls for it are ignored
--   ScheduleAfter                the LAST function and the LAST deadline win
-- Pinned here on both delayed backends (TimedSignalMap and C_Timer.After), plus
-- the independence of the two tables.
-- Usage: lua tools/tests/scheduler_pending_key_policy_smoke.lua <repoRoot>
local repo = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local schedulerPath = repo .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Scheduler.lua"

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
    C_Timer = nil
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

print("scheduler_pending_key_policy_smoke: OK")
