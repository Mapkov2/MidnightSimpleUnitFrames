-- classpower_load_profile_smoke.lua <repoRoot>
--
-- The client loads an addon's SavedVariables after every one of its Lua files
-- ran (load_time_profile_read_smoke). A Class Resource file that reads MSUF_DB
-- while it loads sees no saved profile and acts on defaults. Booting each
-- client's real core graph (tools/tests/client_world.lua) as a Druid, so the
-- Midnight Balance runtime loads too, no ClassPower file may look up MSUF_DB
-- while it loads.
-- Before: MSUF_CP_BalanceDruid.lua evaluated its runtime (_refreshActiveState)
-- and MSUF_CP_Controller.lua chose its startup events from
-- CPConfig.AnyFeatureEnabled() at load. Both now evaluate the saved profile at
-- PLAYER_ENTERING_WORLD / the first FullRefresh, which the ClassPower smokes
-- drive (classpower_world.lua enables the module after the files loaded).
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
end

local function Relative(path)
    path = tostring(path or ""):gsub("\\", "/")
    local index = path:find("MidnightSimpleUnitFrames", 1, true)
    return index and path:sub(index) or path
end

local function IsClassPowerFile(file)
    return file:find("^MidnightSimpleUnitFrames/ClassPower/") ~= nil
        or file:find("^MidnightSimpleUnitFrames/Game/[^/]+/ClassPower") ~= nil
end

local loaded = 0
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local world = World.New(root, flavor)
    rawset(world.env, "UnitClass", function() return "Druid", "DRUID", 11 end)
    -- MSUF_DB is absent until the SavedVariables load, so every lookup reaches
    -- the sandbox's __index.
    local meta = getmetatable(world.env)
    local lookup = meta.__index
    local reads = {}
    meta.__index = function(env, key)
        if key == "MSUF_DB" and world.loading then
            local file = Relative(world.loading)
            if IsClassPowerFile(file) then reads[file] = (reads[file] or 0) + 1 end
        end
        return lookup(env, key)
    end
    world:Boot()
    meta.__index = lookup
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    local files = {}
    for file in pairs(reads) do files[#files + 1] = file end
    table.sort(files)
    for _, file in ipairs(files) do
        Check(false, flavor .. ": " .. file .. " reads MSUF_DB " .. reads[file]
            .. " time(s) while it loads, before the SavedVariables exist")
    end
    for _, path in ipairs(world.loaded) do
        if IsClassPowerFile(path) then loaded = loaded + 1 end
    end
end
Check(loaded > 0, "no ClassPower file loaded in any client")

if #failures > 0 then
    error("classpower_load_profile_smoke:\n  " .. table.concat(failures, "\n  "), 0)
end
print(("classpower_load_profile_smoke: ok (%d ClassPower file loads across 5 clients, no profile read)"):format(loaded))
