-- Exact committed-parent budgets for complete operations, never just predicates.
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
local w, cases, nativeCount, reset, NativeFunctions = Paths.New(World, root, flavor, harness)
local errors = {}
for _, selected in ipairs(cases) do
    local case, activeWorld, registry = selected, w, NativeFunctions
    -- Group-layout and native frame-creation receipts start from fresh graphs;
    -- preceding case allocations must not contaminate native fixture arrays.
    if case.name == "layout:group" or case.name == "layout:group-preview" or case.name == "spawn:secure"
        or case.name:find("round-layout:", 1, true) then
        local fresh, options, _, _, natives = Paths.New(World, root, flavor, harness)
        activeWorld, registry = fresh, natives
        for _, option in ipairs(options) do if option.name == case.name then case = option end end
    end
    case.prepare()
    case.run()
    local function Run()
        for i = 1, case.iterations do case.run() end
    end
    local work, native = 0, 0
    local nativeFunctions = registry()
    debug.sethook(function(event)
        local info = debug.getinfo(2, "Sf")
        if event == "count" then
            if info.source:find("/MidnightSimpleUnitFrames/", 1, true) then work = work + 1 end
        elseif nativeFunctions[info.func] then
            -- Attribute client calls to an addon operation, including native
            -- wrapper chains; fixture setup/string operations are outside it.
            local level = 3
            while true do
                local caller = debug.getinfo(level, "S")
                if not caller then break end
                if caller.source:find("/MidnightSimpleUnitFrames/", 1, true) then
                    native = native + 1
                    break
                end
                level = level + 1
            end
        end
    end, "c", 1)
    Run()
    debug.sethook()
    print(flavor, case.name, case.iterations, work, native, "VM/native")
    if not measure then
        local cap = assert(expected[case.name], "unmeasured operation: " .. case.name)
        assert(case.iterations == cap[1], "measurement count changed: " .. case.name)
        if work > cap[2] or native ~= cap[3] then
            errors[#errors + 1] = case.name .. ": " .. work .. " VM, " .. native .. " natives"
        end
        expected[case.name] = nil
    end
end
if not measure then assert(next(expected) == nil, "original operation was omitted") end
assert(#errors == 0, flavor .. ": complete callable-boundary regression:\n" .. table.concat(errors, "\n"))
print("callable_boundary_cost_smoke: ok (" .. flavor .. ")")
