-- Errors propagate to the client; dispatch bookkeeping survives an unwound call.
local ns = { ExportPublic = function(name, value) _G[name] = value; return value end }
assert(loadfile("MidnightSimpleUnitFrames/Kernel/MSUF_Boundary.lua"))("MSUF", ns)
for _, name in ipairs({ "TryCall", "TryRead", "InvokeBoundary", "InvokeLabeledBoundary", "CaptureError", "CreateErrorHandler" }) do
    assert(ns[name] == nil, "removed call boundary survived: " .. name)
end
local frames = {}
_G.CreateFrame = function()
    local frame = { events = {}, scripts = {} }
    function frame:Hide() end
    function frame:SetScript(event, fn) self.scripts[event] = fn end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:RegisterUnitEvent(event, ...) self.events[event] = { ... } end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:IsEventRegistered(event) return self.events[event] ~= nil end
    frames[#frames + 1] = frame
    return frame
end
assert(loadfile("MidnightSimpleUnitFrames/Kernel/MSUF_EventBus.lua"))("MSUF", ns)
local bus, driver = ns.EventBus, frames[1]
local seen, marker = {}, {}
bus:Register("TEST", "failure", function()
    bus:Unregister("TEST", "cancelled")
    error(marker)
end, nil, true)
bus:Register("TEST", "cancelled", function() error("cancelled callback fired") end)
bus:Register("TEST", "remaining", function(_, first, hole, last)
    assert(first == "a" and hole == nil and last == "c", "argument holes lost")
    seen[#seen + 1] = "remaining"
end)
local ok, failure = pcall(driver.scripts.OnEvent, driver, "TEST", "a", nil, "c")
assert(not ok and failure == marker and #seen == 0, "event exception was intercepted")
driver.scripts.OnEvent(driver, "TEST", "a", nil, "c")
assert(#seen == 1 and #bus.handlers.TEST.list == 1, "once/removal bookkeeping was stranded")
bus:Unregister("TEST", "remaining")
assert(not bus.handlers.TEST and not driver.events.TEST)
local nested = 0
bus:Register("NESTED", "once", function()
    nested = nested + 1
    driver.scripts.OnEvent(driver, "NESTED")
end, nil, true)
driver.scripts.OnEvent(driver, "NESTED")
assert(nested == 1, "once subscriber replayed under nested delivery")
local filtered = 0
bus:Register("UNIT_HEALTH", "target", function() filtered = filtered + 1 end, "target")
driver.scripts.OnEvent(driver, "UNIT_HEALTH", "player")
driver.scripts.OnEvent(driver, "UNIT_HEALTH", "target")
assert(filtered == 1, "unit filtering changed")
-- Model the client's outer error handler and verify that the callback's source
-- is still in the stack when it observes the original error object.
local providerFault = assert(loadstring("error(marker)", "@msuf-original-provider.lua"))
setfenv(providerFault, { error = error, marker = marker })
bus:Register("STACK", "provider", providerFault)
local trace
ok, failure = xpcall(function() driver.scripts.OnEvent(driver, "STACK") end, function(err)
    trace = debug.traceback()
    return err
end)
assert(not ok and failure == marker and trace:find("msuf-original-provider.lua:1", 1, true),
    "outer error handler lost the callback source or original exception")
bus:Unregister("STACK", "provider")
assert(loadfile("MidnightSimpleUnitFrames/Kernel/MSUF_Scheduler.lua"))("MSUF", ns)
local scheduler, scheduleFrame = ns.Scheduler, frames[2]
local executed = {}
scheduler.ScheduleOnce("bad", function()
    scheduler.ScheduleOnce("later", function() executed[#executed + 1] = "later" end)
    error(marker)
end)
scheduler.ScheduleOnce("next", function() executed[#executed + 1] = "next" end)
scheduler.ScheduleOnce("next", function() error("duplicate key ran") end)
ok, failure = pcall(scheduleFrame.scripts.OnUpdate)
assert(not ok and failure == marker and scheduler.pending.bad == nil, "scheduler hid or retained failing item")
assert(scheduleFrame.scripts.OnUpdate and scheduler.head == 2, "scheduler lost remaining work")
scheduleFrame.scripts.OnUpdate()
assert(table.concat(executed, ",") == "next,later" and scheduleFrame.scripts.OnUpdate == nil, "scheduler failed to resume/drain")
local ticks = 0
local function Again()
    ticks = ticks + 1
    if ticks == 1 then scheduler.RunNextFrame(Again) end
end
scheduler.RunNextFrame(Again)
scheduleFrame.scripts.OnUpdate()
assert(ticks == 1 and scheduleFrame.scripts.OnUpdate, "reentrant work ran in its scheduling frame")
scheduleFrame.scripts.OnUpdate()
assert(ticks == 2 and not scheduleFrame.scripts.OnUpdate)
print("boundary_contract_smoke: OK (direct exceptions, once/reentrancy, cancellation, unit filters, scheduler continuation)")
