local root = assert(arg[1]):gsub("\\", "/")
local measure = arg[2] == "measure"
local ns = {}
assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/MSUF_ProfileFields.lua"))("test", ns)
local F = ns.ProfileFields
local value = { flag = false, zero = 0, child = { x = 3, y = "value" } }
for i = 1, 1000 do value[i] = i end
local copy, ok = F.CopySnapshot(value)
assert(ok and copy ~= value and copy.flag == false and copy.zero == 0 and copy.child ~= value.child)
for key, v in pairs(value) do if type(v) ~= "table" then assert(copy[key] == v) end end
for _, invalid in ipairs({ function() end, math.huge, 0/0,
    setmetatable({}, {}), { function() end } }) do
    local _, valid = F.CopySnapshot(invalid)
    assert(not valid, "invalid sparse value accepted")
end
local cycle = {}
cycle.self = cycle
assert(select(2, F.CopySnapshot(cycle)) == false)
assert(select(2, F.CopySnapshot(value, { count = 0, limit = 4 })) == false)
assert(select(2, F.CopySnapshot(value, { count = 0, maxDepth = 1 })) == false)
assert(select(2, F.CopySnapshot({ text = "12345" }, { count = 0, maxBytes = 8 })) == false)
assert(select(3, F.CopySnapshot({ math.huge })) == "number")
assert(F.CopySnapshot({ [0] = false })[0] == false)
local calls = 0
local file = assert(io.open(root .. "/MidnightSimpleUnitFrames/State/MSUF_ProfileFields.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local pos = assert(source:find("local function Copy(entry,depth,seen)", 1, true))
local _, copyLine = source:sub(1, pos):gsub("\n", "\n")
copyLine = copyLine + 1
for pass = 1, 2 do
    collectgarbage("collect")
    collectgarbage("stop")
    local kb, vm = collectgarbage("count"), 0
    calls = 0
    debug.sethook(function() vm = vm + 1 end, "", 1)
    for i = 1, 20 do assert(F.CopySnapshot(value)) end
    debug.sethook()
    local delta = collectgarbage("count") - kb
    collectgarbage("restart")
    print(string.format("A2 profile-copy-snapshot x20 vm=%d kb=%.3f native=0", vm, delta))
end
calls = 0
-- Count recursion separately: debug.getinfo allocates and must not enter the KB measurement.
debug.sethook(function(event)
    if event == "call" then
        local info = debug.getinfo(2, "S")
        if info.linedefined == copyLine and info.source:find("MSUF_ProfileFields.lua", 1, true) then calls = calls + 1 end
    end
end, "c")
for i = 1, 20 do assert(F.CopySnapshot(value)) end
debug.sethook()
print("A2 snapshot recursive copies=" .. calls)
if not measure then assert(calls == 40, "copy recursively calls itself for scalar leaves") end
print("PASS history_copy_budget_smoke")
