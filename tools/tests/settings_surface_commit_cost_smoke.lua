-- Settings publication must not enter the internal frame-apply surface commit.
-- Reuse the existing complete routes, native registry and immutable original caps.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
loadfile = dofile(root .. "/tools/tests/responsibility_route_loader.lua")
local World = dofile(root .. "/tools/tests/health_tick_world.lua")
local Routes = dofile(root .. "/tools/tests/responsibility_route_paths.lua")
local caps = {}
local file = assert(io.open(root .. "/tools/fixtures/costs/responsibility_route_costs.tsv", "rb"))
for line in file:lines() do
    local client, name, count, vm, native = line:match("^(%S+)\t(%S+)\t(%d+)\t(%d+)\t(%d+)")
    if client == flavor and name:match("^spawn%-apply:") then
        caps[name] = { tonumber(count), tonumber(vm), tonumber(native) }
    end
end
file:close()
local _, options = Routes.New(World, root, flavor, root)
local checked, errors = 0, {}
for _, selected in ipairs(options) do
    if selected.name:match("^spawn%-apply:") then
        local _, cases, Registry = Routes.New(World, root, flavor, root)
        local case
        for _, candidate in ipairs(cases) do if candidate.name == selected.name then case = candidate end end
        assert(case, selected.name)
        case.prepare()
        case.run()
        local function Run() for _ = 1, case.iterations do case.run() end end
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
        local cap = assert(caps[case.name], "missing original cap: " .. case.name)
        assert(case.iterations == cap[1], "original case count changed")
        print(flavor, case.name, case.iterations, work, native, "VM/native original caps")
        if work > cap[2] or native ~= cap[3] then errors[#errors + 1] = case.name .. ": " .. work .. " VM / " .. native .. " natives" end
        caps[case.name] = nil
        checked = checked + 1
    end
end
assert(checked == 25 and next(caps) == nil, "original surface commit route omitted")
assert(#errors == 0, table.concat(errors, "\n"))
print("settings_surface_commit_cost_smoke: " .. flavor .. " 25 original complete-operation caps held")
