-- One subscriber or scheduled callback that raises must not starve the rest
-- (review F10). The EventBus and the Scheduler run each callback through
-- secureexecuterange, which reports an error to the error handler and moves
-- on; dispatch stays allocation-free. The stub below behaves like the client
-- function: next-order traversal, errors reported, iteration continues.
-- Usage: lua tools/tests/eventbus_isolation_smoke.lua <repoRoot>
local repo = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local reported = {}
function secureexecuterange(tbl, fn, ...)
    local key, value = next(tbl)
    while key ~= nil do
        local ok, err = pcall(fn, key, value, ...)
        if not ok then reported[#reported + 1] = tostring(err) end
        key, value = next(tbl, key)
    end
end
local function NewFrame()
    local f = { events = {}, units = {} }
    function f:Hide() end
    function f:SetScript(kind, fn) self[kind] = fn end
    function f:RegisterEvent(e) self.events[e] = true end
    function f:RegisterUnitEvent(e, ...) self.events[e] = true; self.units[e] = { ... }; return true end
    function f:UnregisterEvent(e) self.events[e] = nil end
    function f:IsEventRegistered(e) return self.events[e] == true end
    return f
end
local frames = {}
function CreateFrame() local f = NewFrame(); frames[#frames + 1] = f; return f end
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
TimerUtil = nil
local ns = { ExportPublic = function() end }
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Kernel/MSUF_EventBus.lua"))("MidnightSimpleUnitFrames", ns)
local bus, driver = ns.EventBus, frames[1]
local function Fire(event, ...) driver.OnEvent(driver, event, ...) end

-- (1) A raising subscriber does not stop the others.
local ran = {}
bus:Register("TEST_EVENT", "a", function() error("subscriber a failed") end)
bus:Register("TEST_EVENT", "b", function(_, value) ran[#ran + 1] = "b:" .. tostring(value) end)
bus:Register("TEST_EVENT", "c", function(_, value) ran[#ran + 1] = "c:" .. tostring(value) end)
Fire("TEST_EVENT", 7)
assert(ran[1] == "b:7" and ran[2] == "c:7", "a raising subscriber starved the rest of the fan-out")
assert(#reported == 1 and reported[1]:find("subscriber a failed", 1, true), "the error was not reported")

-- (2) Unit filters and once subscriptions keep their contract.
local units = {}
bus:Register("UNIT_HEALTH", "player", function(_, unit) units[#units + 1] = unit end, "player")
Fire("UNIT_HEALTH", "target"); Fire("UNIT_HEALTH", "player")
assert(#units == 1 and units[1] == "player", "the unit filter changed")
local onceCount = 0
bus:Register("ONCE_EVENT", "once", function() onceCount = onceCount + 1 end, nil, true)
Fire("ONCE_EVENT"); Fire("ONCE_EVENT")
assert(onceCount == 1, "a once subscription ran twice")

-- (3) A subscription added during a dispatch starts with the next one.
local added = 0
bus:Register("GROW_EVENT", "first", function()
    bus:Register("GROW_EVENT", "late", function() added = added + 1 end)
end)
Fire("GROW_EVENT")
assert(added == 0, "a subscription registered during the dispatch ran in it")
Fire("GROW_EVENT")
assert(added == 1, "the new subscription did not run on the next dispatch")

-- (4) Dispatch allocates nothing (subscribers that build no strings).
for _, key in ipairs({ "a", "b", "c" }) do bus:Unregister("TEST_EVENT", key) end
bus:Register("TEST_EVENT", "quiet1", function() end)
bus:Register("TEST_EVENT", "quiet2", function() end)
bus:Register("UNIT_POWER_UPDATE", "quiet3", function() end, { "player", "target" })
collectgarbage("collect"); collectgarbage("stop")
local kb = collectgarbage("count")
for i = 1, 3000 do Fire("TEST_EVENT", i); Fire("UNIT_POWER_UPDATE", "target", "MANA") end
local grown = collectgarbage("count") - kb
collectgarbage("restart")
assert(grown < 1, string.format("6000 dispatches allocated %.1f KB", grown))

-- (5) Scheduler: a raising callback does not hold back the next one.
local frame = NewFrame()
CreateFrame = function() return frame end
local sns = { ExportPublic = function() end }
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Scheduler.lua"))("MSUF", sns)
local s = sns.Scheduler
local seen = {}
s.ScheduleOnce("fails", function() error("scheduled callback failed") end)
s.ScheduleOnce("survives", function() seen[#seen + 1] = "survives" end)
local before = #reported
frame.OnUpdate()
assert(seen[1] == "survives", "a raising scheduled callback held back the next one")
assert(#reported == before + 1, "the scheduled callback error was not reported")
assert(frame.OnUpdate == nil, "the drained queue left the driver armed")
s.ScheduleAfter("delayed", 1, function() error("delayed callback failed") end)
assert(#timers == 1)
timers[1]()
assert(#reported == before + 2 and not s.IsScheduled("delayed"), "a raising delayed callback was not isolated")
print(string.format("eventbus_isolation_smoke: OK (%.2f KB over 6000 dispatches)", grown))
