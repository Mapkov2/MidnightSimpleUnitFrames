-- Delayed scheduling allocates nothing per call on clients without
-- TimedSignalMap (review F27: Midnight 12.1.0 live and every Classic client
-- used to allocate a closure per ScheduleAfter). The debounce, earlier
-- deadline and cancel contracts hold with a game clock.
-- Usage: lua tools/tests/scheduler_delayed_alloc_smoke.lua <repoRoot>
local repo = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local now = 100
GetTime = function() return now end
TimerUtil = nil
-- A timer list kept in preallocated slots so the stub itself allocates nothing.
local due, fns, count = {}, {}, 0
for i = 1, 4096 do due[i], fns[i] = 0, false end
C_Timer = { After = function(delay, fn) count = count + 1; due[count] = now + delay; fns[count] = fn end }
local frame = { SetScript = function() end }
CreateFrame = function() return frame end
local ns = { ExportPublic = function() end }
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Scheduler.lua"))("MSUF", ns)
local s = ns.Scheduler
local function Advance(to)
    now = to
    for i = 1, count do
        if fns[i] and due[i] <= now then local fn = fns[i]; fns[i] = false; fn() end
    end
end
local runs = 0
local function Work() runs = runs + 1 end

-- Allocation: reschedule one stable key 2000 times.
s.ScheduleAfter("burst", 1, Work)
collectgarbage("collect"); collectgarbage("stop")
local kb = collectgarbage("count")
for _ = 1, 2000 do s.ScheduleAfter("burst", 1, Work) end
local grown = collectgarbage("count") - kb
collectgarbage("restart")
assert(grown < 1, string.format("2000 reschedules allocated %.1f KB", grown))
Advance(101)
assert(runs == 1, "a debounced burst ran " .. runs .. " times")

-- A later deadline replaces an earlier one.
runs = 0
s.ScheduleAfter("later", 1, Work)
now = 100.5
s.ScheduleAfter("later", 1, Work)
Advance(101)
assert(runs == 0, "the superseded earlier deadline ran the work")
Advance(101.5)
assert(runs == 1, "the newest deadline did not run the work")
-- An earlier deadline replaces a later one.
runs = 0
s.ScheduleAfter("earlier", 5, Work)
s.ScheduleAfter("earlier", 1, Work)
Advance(102.5)
assert(runs == 1, "the shorter new deadline did not run first")
Advance(110)
assert(runs == 1, "the superseded later timer ran the work again")
-- Cancel, then schedule again.
runs = 0
s.ScheduleAfter("cancel", 3, Work)
assert(s.CancelScheduled("cancel"))
s.ScheduleAfter("cancel", 1, Work)
Advance(111)
assert(runs == 1, "a schedule after a cancel did not run")
Advance(120)
assert(runs == 1, "the cancelled timer ran the work")
print(string.format("scheduler_delayed_alloc_smoke: OK (%.2f KB over 2000 reschedules)", grown))
