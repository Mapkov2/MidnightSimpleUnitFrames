local repo = assert(arg[1])
local marker = {}
local frame = {}
function frame:SetScript(_, fn) self.update = fn end
CreateFrame = function() return frame end
TimerUtil = nil
local timers = {}
C_Timer = { After = function(delay, callback) timers[#timers + 1] = { delay, callback } end }
local ns = { ExportPublic = function() end }
local loadScheduler = assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Scheduler.lua"))
loadScheduler("MSUF", ns)
local s = ns.Scheduler
for _, call in ipairs({
    function() s.RunNextFrame(nil) end,
    function() s.ScheduleOnce("bad", false) end,
    function() s.ScheduleAfter("bad", 1, nil) end,
    function() s.ScheduleAfter("bad", -1, function() end) end,
    function() s.ScheduleAfter("bad", 0/0, function() end) end,
    function() s.ScheduleAfter("bad", math.huge, function() end) end,
}) do
    assert(not pcall(call), "invalid scheduler contract was concealed")
    assert(not s.IsScheduled("bad"), "invalid call left pending work")
end
local seen = {}
s.ScheduleOnce("fails", function() error(marker) end)
s.ScheduleOnce("survives", function() seen[#seen + 1] = "survives" end)
local ok, err = pcall(frame.update)
assert(not ok and err == marker, "callback error was replaced or swallowed")
assert(not s.IsScheduled("fails"))
frame.update()
assert(seen[1] == "survives" and frame.update == nil, "error stranded the queue")
s.ScheduleOnce("reentrant", function()
    seen[#seen + 1] = "first"
    s.ScheduleOnce("reentrant", function() seen[#seen + 1] = "next" end)
end)
frame.update(); assert(seen[2] == "first" and seen[3] == nil)
frame.update(); assert(seen[3] == "next" and frame.update == nil)
s.ScheduleAfter("delay", 1, function() error("stale callback ran") end)
s.ScheduleAfter("delay", 2, function() seen[#seen + 1] = "latest" end)
assert(#timers == 2 and seen[4] == nil, "delayed callback ran synchronously")
timers[1][2](); timers[2][2](); assert(seen[4] == "latest")
s.ScheduleAfter("cancel", 1, function() error("cancelled callback ran") end)
assert(s.CancelScheduled("cancel")); timers[3][2]()
s.ScheduleAfter("error", 1, function() error(marker) end)
ok, err = pcall(timers[4][2]); assert(not ok and err == marker and not s.IsScheduled("error"))
C_Timer = nil
ok, err = pcall(loadScheduler, "MSUF", { ExportPublic = function() end })
assert(not ok and tostring(err):find("requires C_Timer.After", 1, true), "missing timer silently changed scheduling")
print("PASS scheduler: explicit contracts, deferred work, replacement, cancellation, reentrancy and native errors")
