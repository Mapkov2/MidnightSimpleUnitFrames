-- Three-subscriber mutation, nested dispatch, next-notify subscription and zero-allocation budget.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local path = root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarEngine.lua"
local f = assert(io.open(path, "rb"))
local source = f:read("*a"):gsub("\r\n", "\n")
f:close()
source = assert(source:match("^(.-)function Engine:AdvanceGeneration"))
local engine = {}
local castbars = { Engine = engine, Utils = {}, PublicAPI = {} }
assert(loadstring(source, "@" .. path))("test", { Require = function() return { Castbars = castbars } end })
local function Noop() end
local a, b, c = function() end, function() end, function() end
engine:Subscribe("budget", a)
engine:Subscribe("budget", b)
engine:Subscribe("budget", c)
local instructions = 0
debug.sethook(function()
    if debug.getinfo(2, "S").source == "@" .. path then instructions = instructions + 1 end
end, "", 1)
for _ = 1, 100 do engine:Notify("budget", false, "test") end
debug.sethook()
local minimum = math.huge
for _ = 1, 2 do
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 1000 do engine:Notify("budget", false, "test") end
    minimum = math.min(minimum, collectgarbage("count") - before)
    collectgarbage("restart")
end
print(string.format("pubsub budget: %.0f VM/notify, %.3f KB/1000, 0 native calls", instructions / 100, minimum))
local calls = {}
local first
first = function() calls[#calls + 1] = 1 engine:Unsubscribe("self", first) end
engine:Subscribe("self", first)
engine:Subscribe("self", function() calls[#calls + 1] = 2 end)
engine:Subscribe("self", function() calls[#calls + 1] = 3 end)
engine:Notify("self")
assert(table.concat(calls, ",") == "1,2,3", "self-unsubscribe skipped a subscriber: " .. table.concat(calls, ","))
local added = function() calls[#calls + 1] = 4 end
local later = function() calls[#calls + 1] = 5 end
engine:Subscribe("add", function() engine:Subscribe("add", added) engine:Unsubscribe("add", later) end)
engine:Subscribe("add", later)
calls = {}
engine:Notify("add")
assert(#calls == 0, "new subscription ran in its creating dispatch or a removed callback ran")
engine:Notify("add")
assert(table.concat(calls, ",") == "4", "new subscription did not run from the next notify")
local nested, depth = {}, 0
local selfRemoving
selfRemoving = function()
    nested[#nested + 1] = "a"
    engine:Unsubscribe("nested", selfRemoving)
    if depth == 0 then depth = 1 engine:Notify("nested") end
end
engine:Subscribe("nested", selfRemoving)
engine:Subscribe("nested", function() nested[#nested + 1] = "b" end)
engine:Notify("nested")
assert(table.concat(nested, ",") == "a,b,b", "nested dispatch compacted an active iteration")
local nestedAdd, nesting = {}, false
local child = function() nestedAdd[#nestedAdd + 1] = "child" end
engine:Subscribe("nested-add", function()
    nestedAdd[#nestedAdd + 1] = "parent"
    if not nesting then
        nesting = true
        engine:Subscribe("nested-add", child)
        engine:Notify("nested-add")
    end
end)
engine:Notify("nested-add")
assert(table.concat(nestedAdd, ",") == "parent,parent,child", "nested next-notify subscription semantics changed")
local throwing
throwing = function() engine:Unsubscribe("throw", throwing) error("subscriber-fault") end
engine:Subscribe("throw", throwing)
engine:Subscribe("throw", Noop)
local ok, err = pcall(engine.Notify, engine, "throw")
assert(not ok and tostring(err):find("subscriber-fault", 1, true), "subscriber error was suppressed")
engine:Notify("throw")
engine:Unsubscribe("throw", Noop)
assert(engine._subs.throw == nil, "callback error permanently latched tombstones")
engine:Subscribe("only", Noop)
engine:Unsubscribe("only", Noop)
assert(engine._subs.only == nil, "last subscriber retained")
engine:Subscribe("idle", Noop)
for _ = 1, 1000 do
    local temporary = function() end
    engine:Subscribe("idle", temporary)
    engine:Unsubscribe("idle", temporary)
end
local node, reachable = engine._subs.idle.first, 0
while node do reachable = reachable + 1 node = node.next end
assert(reachable <= 2 and engine._subs.idle.count == 1, "idle topic retained unbounded tombstones")
engine:Notify("idle")
assert(engine._subs.idle.first.next == nil, "notify did not compact the final tombstone")
assert(instructions / 100 <= 43, "three-subscriber notify exceeded original VM budget")
assert(minimum <= 0.001, "notify allocated")
print("castbar_pubsub_mutation: PASS")
