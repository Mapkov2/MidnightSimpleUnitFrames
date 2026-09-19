-- client_boot_smoke.lua <repoRoot> <flavor>
--
-- Boots one flavor's whole shipped load graph offline: every Lua file of its
-- core TOC and then of its Options TOC, in TOC order, into one namespace each,
-- inside the fake client of tools/tests/client_world.lua.
--
-- The bar is ZERO chunk failures. The graph ends in Kernel/MSUF_RuntimeContracts.lua,
-- the addon's own "did every provider load" check, so a clean run means every
-- file of that flavor ran to its last statement and the load contract held.
--
-- Second contract: the set of globals the harness does not model, read at load,
-- is diffed against tools/client-boot-globals.tsv. A file that starts reading a
-- global nobody reviewed fails here instead of silently taking a nil path in
-- the client. (That baseline already carries one real defect, marked Kind
-- "defect": Features/Telemetry/MSUF_Analytics.lua reads the bare global
-- "global" where it means gdb.global.)
--
-- Flavors: one per tools/classic-client-matrix.tsv row, plus "Forever", which
-- runs the Mainline TOC with Blizzard_Game's camelot marker present.
--
-- Plain Lua 5.1 with the repo root as arg 1 -- not through the aura test
-- driver, which replaces loadfile and io.open.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required (a matrix Suffix or Forever)")
assert(rawget(_G, "MSUF_Auras3TestLoader") == nil,
    "client_boot_smoke loads the real TOC graph; run it with plain Lua 5.1, not auras3_test_driver.lua")

local World = assert(loadfile(root .. "/tools/tests/client_world.lua"),
    "client_boot_smoke: tools/tests/client_world.lua is missing")()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local known = {}
for _, name in ipairs((World.Flavors(root))) do known[name] = true end
Check(known[flavor] == true, "unknown flavor " .. flavor
    .. "; the matrix plus Forever covers: " .. table.concat((World.Flavors(root)), ", "))

local world = World.New(root, flavor):Boot()

-- Load -------------------------------------------------------------------
local failure = world:FirstFailure()
if failure ~= nil then
    local extra = ""
    if #world.failures > 1 then extra = " (" .. (#world.failures - 1) .. " further failure(s))" end
    error(flavor .. " load failed in " .. failure.file .. extra .. "\n        " .. failure.message, 0)
end
Check(#world.corePaths > 200 and #world.optionsPaths > 100,
    flavor .. " load graph is unexpectedly small: " .. #world.corePaths .. " core, "
        .. #world.optionsPaths .. " Options")

-- The fake client has to place the real client, or the run proved nothing.
local client = world.core.Client
Check(type(client) == "table", flavor .. ": Game/Shared/Initialize.lua built no MSUF.Client")
local expectedFamily = world.client.isClassic and "Classic" or "Mainline"
Check(client.Family == expectedFamily,
    flavor .. ": client family is " .. tostring(client.Family) .. ", expected " .. expectedFamily)
Check(client.IsForever == world.client.isForever,
    flavor .. ": IsForever is " .. tostring(client.IsForever))
Check(client.Flavor == (world.client.isForever and "Mainline" or flavor),
    flavor .. ": client flavor is " .. tostring(client.Flavor))
-- RuntimeContracts is the last core file; reaching it means the graph finished.
Check(world.loaded[#world.corePaths]:find("MSUF_RuntimeContracts%.lua$") ~= nil,
    flavor .. ": the core TOC no longer ends in Kernel/MSUF_RuntimeContracts.lua")

-- Unknown globals --------------------------------------------------------
local baseline = World.GlobalsBaseline(root)
local live, unexpected = {}, {}
for _, name in ipairs(world:UnknownGlobals()) do
    live[name] = true
    local entry = baseline[name]
    if entry == nil then
        unexpected[#unexpected + 1] = name .. " (first read by " .. tostring(world.unknown[name]) .. ")"
    elseif not entry.all and not entry.flavors[flavor] then
        unexpected[#unexpected + 1] = name .. " (first read by " .. tostring(world.unknown[name])
            .. "; the baseline does not list " .. flavor .. " for it)"
    end
end
Check(#unexpected == 0, flavor .. " reads " .. #unexpected
    .. " global(s) at load that tools/client-boot-globals.tsv does not list."
    .. "\n  Either stop reading them or add a reviewed row:\n    " .. table.concat(unexpected, "\n    "))

local stale = {}
for name, entry in pairs(baseline) do
    if (entry.all or entry.flavors[flavor]) and not live[name] then stale[#stale + 1] = name end
end
table.sort(stale)
Check(#stale == 0, flavor .. ": tools/client-boot-globals.tsv lists " .. #stale
    .. " global(s) nothing reads at load any more; drop the row or narrow its Flavors:\n    "
    .. table.concat(stale, "\n    "))

print(string.format("client_boot_smoke: ok (%s, %d core + %d Options Lua files, 0 chunk failures, %d reviewed unknown globals)",
    flavor, #world.corePaths, #world.optionsPaths, #world:UnknownGlobals()))
