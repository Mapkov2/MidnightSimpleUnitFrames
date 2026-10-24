-- Cached EnsureDB is a runtime guard: no additional event cost or allocation.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local C = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local world = C.NewWorld(root, flavor, "Tester-Realm")
C.Login(world, {})
local function Ticks(fn)
    for _ = 1, 1000 do fn() end
end
local function Measure(fn)
    fn()
    local source = debug.getinfo(fn, "S").source
    local instructions = 0
    debug.sethook(function()
        if debug.getinfo(2, "S").source == source then instructions = instructions + 1 end
    end, "", 1)
    Ticks(fn)
    debug.sethook()
    local bytes = math.huge
    for _ = 1, 2 do
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        Ticks(fn)
        bytes = math.min(bytes, (collectgarbage("count") - before) * 1024)
        collectgarbage("restart")
    end
    local nativeType, natives = world.env.type, 0
    world.env.type = function(value)
        natives = natives + 1
        return nativeType(value)
    end
    Ticks(fn)
    world.env.type = nativeType
    assert(natives == 1000, "cached EnsureDB changed its one native type check per call")
    return instructions / 1000, bytes
end
local afterFn = world.core.PublicGlobals.MSUF_EnsureDB
local after, bytes = Measure(afterFn)
assert(after <= 9 and bytes == 0, "cached EnsureDB exceeded runtime guard budget")
local before = 10
if arg[3] then
    local chunk = assert(loadfile(arg[3] .. "/MSUF_Defaults.lua"))
    setfenv(chunk, world.env)
    chunk("MidnightSimpleUnitFrames", world.core)
    local beforeFn = world.core.PublicGlobals.MSUF_EnsureDB
    local beforeBytes
    before, beforeBytes = Measure(beforeFn)
    assert(after <= before and bytes <= beforeBytes, "cached EnsureDB regressed against baseline")
end
print(string.format("PASS profile_ensure_recovery_budget_smoke %s: %.0f -> %.0f VM instructions/call; %.0f bytes/1000 calls",
    flavor, before, after, bytes))
