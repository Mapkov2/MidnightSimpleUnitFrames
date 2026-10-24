-- Original-source whole-route ceilings; count real addon VM and client calls.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local harness = (arg[3] or root):gsub("\\", "/")
local measure = arg[4] == "measure"
loadfile, dofile = dofile(harness .. "/tools/tests/responsibility_route_loader.lua")
local World = dofile(harness .. "/tools/tests/health_tick_world.lua")
local Routes = dofile(harness .. "/tools/tests/responsibility_route_paths.lua")
local expected = {}
if not measure then
    local file = assert(io.open(harness .. "/tools/fixtures/costs/responsibility_route_costs.tsv", "rb"))
    for line in file:lines() do
        local client, name, count, vm, native, heap = line:match("^(%S+)\t(%S+)\t(%d+)\t(%d+)\t(%d+)\t([%-]?[%d.]+)")
        if client == flavor then expected[name] = { tonumber(count), tonumber(vm), tonumber(native), tonumber(heap) } end
    end
    file:close()
end
local _, options = Routes.New(World, root, flavor, harness)
local errors = {}
for _, selected in ipairs(options) do
    local activeWorld, cases, Registry = Routes.New(World, root, flavor, harness, selected.name)
    local case
    for _, candidate in ipairs(cases) do if candidate.name == selected.name then case = candidate end end
    assert(case, selected.name)
    case.prepare()
    case.run()
    local function Run() for i = 1, case.iterations do case.run() end end
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
    local first, second
    local thread = coroutine.create(function()
        Run()
        first, second = Allocate(Run, unpack(capacity)), Allocate(Run, unpack(capacity))
    end)
    assert(coroutine.resume(thread))
    assert(coroutine.status(thread) == "dead", "heap operation yielded")
    local allocated = math.min(first, second)
    print(flavor, case.name, case.iterations, "heap", string.format("%.12f", first), string.format("%.12f", second))
    if not measure then
        local cap = assert(expected[case.name], "unmeasured route: " .. case.name)
        assert(case.iterations == cap[1], "route count changed: " .. case.name)
        if allocated > cap[4] then
            errors[#errors + 1] = case.name .. ": " .. allocated .. " KiB"
        end
        expected[case.name] = nil
    end
end
if not measure then assert(next(expected) == nil, "original route omitted") end
assert(#errors == 0, table.concat(errors, "\n"))
print("responsibility_route_heap_smoke: ok (" .. flavor .. ")")
