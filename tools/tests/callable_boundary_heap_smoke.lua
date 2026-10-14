-- Hook-free heap control; paired with the complete VM/native process.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local harness = (arg[3] or root):gsub("\\", "/")
local measure = arg[4] == "measure"
local World = dofile(harness .. "/tools/tests/health_tick_world.lua")
local Paths = dofile(harness .. "/tools/tests/callable_boundary_paths.lua")
local expected = {}
local file = assert(io.open(harness .. "/tools/fixtures/costs/callable_boundary_costs.tsv", "rb"))
for line in file:lines() do
    local client, name, count, vm, native, allocated = line:match("^(%S+)\t(%S+)\t(%d+)\t(%d+)\t(%d+)\t([%d.]+)")
    if client == flavor then expected[name] = { tonumber(count), tonumber(vm), tonumber(native), tonumber(allocated) } end
end
file:close()
local w, cases = Paths.New(World, root, flavor, harness)
local errors = {}
local capacity = {}
for i = 1, 192 do capacity[i] = false end
local function Allocate(run, ...)
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    run()
    local delta = collectgarbage("count") - before
    collectgarbage("restart")
    return delta
end
for _, selected in ipairs(cases) do
    local case, activeWorld = selected, w
    -- Group-layout and native frame-creation receipts start from fresh graphs;
    -- preceding case allocations must not contaminate native fixture arrays.
    if case.name == "layout:group" or case.name == "layout:group-preview" or case.name == "spawn:secure"
        or case.name:find("round-layout:", 1, true) then
        local fresh, options = Paths.New(World, root, flavor, harness)
        activeWorld = fresh
        for _, option in ipairs(options) do if option.name == case.name then case = option end end
    end
    -- A fresh coroutine fixes the sampler stack independently of the caller's
    -- loadfile/stdin/pcall frame. It replaces the existing preparation and runs;
    -- it performs no additional warm-up or operation.
    local first, second
    local thread = coroutine.create(function()
        case.prepare()
        case.run()
        local function Run()
            for i = 1, case.iterations do case.run() end
        end
        Run()
        first, second = Allocate(Run, unpack(capacity)), Allocate(Run, unpack(capacity))
    end)
    local ok, diagnostic = coroutine.resume(thread)
    assert(ok, diagnostic)
    assert(coroutine.status(thread) == "dead", "heap operation yielded")
    local allocated = math.min(first, second)
    print(flavor, case.name, case.iterations, "heap", string.format("%.12f", first), string.format("%.12f", second))
    if not measure then
        local cap = assert(expected[case.name], "unmeasured operation: " .. case.name)
        assert(case.iterations == cap[1], "measurement count changed: " .. case.name)
        if allocated > cap[4] then
            errors[#errors + 1] = case.name .. ": " .. allocated .. " KiB"
        end
        expected[case.name] = nil
    end
end
if not measure then assert(next(expected) == nil, "original operation was omitted") end
assert(#errors == 0, flavor .. ": complete callable-boundary heap regression:\n" .. table.concat(errors, "\n"))
print("callable_boundary_heap_smoke: ok (" .. flavor .. ")")
