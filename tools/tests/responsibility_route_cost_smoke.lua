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
        local client, name, count, vm, native = line:match("^(%S+)\t(%S+)\t(%d+)\t(%d+)\t(%d+)")
        if client == flavor then expected[name] = { tonumber(count), tonumber(vm), tonumber(native) } end
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
    local natives = Registry()
    local work, native = 0, 0
    debug.sethook(function(event)
        local info = debug.getinfo(2, "Sf")
        if event == "count" then
            if info.source:find("/MidnightSimpleUnitFrames/", 1, true) then work = work + 1 end
        elseif natives[info.func] then
            local level = 3
            while true do
                local caller = debug.getinfo(level, "S")
                if not caller then break end
                if caller.source:find("/MidnightSimpleUnitFrames/", 1, true) then native = native + 1; break end
                level = level + 1
            end
        end
    end, "c", 1)
    Run()
    debug.sethook()
    print(flavor, case.name, case.iterations, work, native, "VM/native")
    if not measure then
        local cap = assert(expected[case.name], "unmeasured route: " .. case.name)
        assert(case.iterations == cap[1], "route count changed: " .. case.name)
        if work > cap[2] or native ~= cap[3] then
            errors[#errors + 1] = case.name .. ": " .. work .. " VM / " .. native .. " natives"
        end
        expected[case.name] = nil
    end
end
if not measure then assert(next(expected) == nil, "original route omitted") end
assert(#errors == 0, table.concat(errors, "\n"))
print("responsibility_route_cost_smoke: ok (" .. flavor .. ")")
