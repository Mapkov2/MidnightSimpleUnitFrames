local root = assert(arg[1]):gsub("\\", "/")
local measure = arg[2] == "measure"
local W = dofile(root .. "/tools/tests/client_world.lua")
local w = W.New(root, "Mainline")
w:LoadGraph("MidnightSimpleUnitFrames", W.Graph(root, W.CoreTOC("Mainline"), "enUS"), w.core)
assert(w:FirstFailure() == nil)
local api, captures = w.core.EditModeAPI, 0
local state = { value = false }
for i = 1, 11 do state = { child = state } end
local restored
for i = 1, 513 do
    assert(api.RegisterElement("test.snapshot", { id = "item" .. i, label = "item", getFrame = function() return w.env.UIParent end,
        captureState = function() captures = captures + 1 return state end,
        restoreState = function(copy) restored = copy end, movePosition = function() end }))
end
assert(api._BeginSession(true))
assert(captures == 513)
local snapshot = assert(api._CaptureHistorySnapshot())
assert(type(snapshot.elements) == "table", "entry copy rejected the valid registry")
local count = 0
for i = 1, 513 do
    local value = assert(snapshot.elements["external:test.snapshot:item" .. i])
    count = count + 1
    assert(value ~= state)
    for i = 1, 11 do value = value.child end
    assert(value.value == false, "entry copy changed state at the allowed depth")
    value.value = 31
end
assert(count == 513)
assert(api._EndSession("discard"))
for i = 1, 11 do restored = restored.child end
assert(restored.value == false, "history cursor corrupted the independent discard snapshot")
print("A2 entry external captures=" .. captures .. " records=" .. count)
if not measure then assert(captures == 513, "history recaptured entry owners before callbacks") end
print("PASS editmode_entry_snapshot_smoke")
