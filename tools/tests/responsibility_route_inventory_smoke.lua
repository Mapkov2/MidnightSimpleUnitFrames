-- Discovery remains complete and ordered; selection changes only retained case records.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local harness = (arg[3] or root):gsub("\\", "/")
local mode = arg[4]
local compile, execute = dofile(harness .. "/tools/tests/responsibility_route_loader.lua")
loadfile, dofile = compile, execute or dofile
local World = dofile(harness .. "/tools/tests/health_tick_world.lua")
local Routes = dofile(harness .. "/tools/tests/responsibility_route_paths.lua")
local expected = {}
local file = assert(io.open(harness .. "/tools/fixtures/costs/responsibility_route_costs.tsv", "rb"))
for line in file:lines() do
    local client, name, iterations = line:match("^(%S+)\t(%S+)\t(%d+)\t")
    if client == flavor then expected[#expected + 1] = { name, tonumber(iterations) } end
end
file:close()
assert(#expected > 0, "route inventory has no pinned client")
local inventoryWorld, cases = Routes.New(World, root, flavor, harness)
assert(#cases == #expected, "complete route inventory changed")
local seen = {}
for index, case in ipairs(cases) do
    assert(not seen[case.name], "duplicate route: " .. case.name)
    seen[case.name] = true
    assert(case.name == expected[index][1] and case.iterations == expected[index][2], "route order/count changed: " .. index)
    if mode == "inventory" or mode == "compare" then print("ROUTE", case.name, case.iterations) end
end
if mode ~= "inventory" then
    for _, index in ipairs({ 1, math.floor(#cases / 2), #cases }) do
        local selected = cases[index]
        local world, chosen = Routes.New(World, root, flavor, harness, selected.name)
        assert(#chosen == 1, "selected route retained unrelated case records")
        assert(chosen[1].name == selected.name and chosen[1].iterations == selected.iterations, "selected route changed")
        assert(world ~= inventoryWorld and world.env ~= inventoryWorld.env, "selected world reused")
        assert(world.h.widgets ~= inventoryWorld.h.widgets and world.env.MSUF_DB ~= inventoryWorld.env.MSUF_DB,
            "selected widgets or profile reused")
        assert(chosen[1].run ~= selected.run and chosen[1].prepare ~= selected.prepare, "selected closures reused")
    end
end
print("responsibility_route_inventory_smoke: ok", flavor, #cases)
