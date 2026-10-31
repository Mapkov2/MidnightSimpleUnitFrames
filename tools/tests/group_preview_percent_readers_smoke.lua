-- Percent callbacks are private immutable sample readers, with the original
-- rounding/fallback semantics and no allocation for a normal 0..100 paint.
local root = assert(arg[1])
local Harness = assert(loadfile(root .. "/tools/tests/group_header_world.lua"))()
local h = Harness.New(root, "Mainline", { beforeBoot = function(world) world.env.MAX_BOSS_FRAMES = 5 end })
local function Find(fn, wanted, seen)
    seen = seen or {}
    if seen[fn] then return end
    seen[fn] = true
    local nested = {}
    for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
        if type(value) == "function" then nested[#nested + 1] = value end
    end
    for i = 1, #nested do
        local value = Find(nested[i], wanted, seen)
        if value then return value end
    end
end
local factory = assert(Find(h.GF.PreviewSamples.ApplyPreviewData, "PercentFactory"), "private percentage reader was not reached")
local function Check(value, expected)
    local reader = factory(value)
    local result = reader()
    assert(result == expected or (result ~= result and expected ~= expected), "percent rounding/fallback changed")
    return reader
end
Check(nil, 0)
Check(false, 0)
Check("24.5", 25)
Check(0.49, 0)
Check(37.499, 37)
local retained = Check(37.5, 38)
Check(100, 100)
Check(100.5, 101)
Check(-4.5, -4)
Check(1000.25, 1000)
Check(math.huge, math.huge)
Check(-math.huge, -math.huge)
Check(0 / 0, 0 / 0)
Check(72.5, 73)
assert(retained() == 38, "a later paint mutated a retained percent callback")
local minimum = math.huge
for pass = 1, 4 do
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for n = 1, 5000 do assert(factory(n % 101)() == n % 101) end
    minimum = math.min(minimum, (collectgarbage("count") - before) / 5000)
    collectgarbage("restart")
end
assert(minimum <= 0.001, "normal percentage readers allocate a closure per paint")
print(("PASS private immutable percent readers %.9f KB/call"):format(minimum))
