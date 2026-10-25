-- <root> [measure] [runtimePath]: real five-client cast events and Utils contracts.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local measure = arg[2] == "measure"
local runtimePath = root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarRuntime.lua"
local path = arg[3] or runtimePath
local World = dofile(root .. "/tools/tests/castbar_secret_world.lua")
local ClientWorld = dofile(root .. "/tools/tests/client_world.lua")
local providers = { "CB_ApplyTexts", "GetCastbarCountsDown", "GetCastbarReverseFillForFrame" }
local function Load(world)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    local chunk = assert(loadstring(source, "@" .. runtimePath))
    setfenv(chunk, world.env)
    chunk("MidnightSimpleUnitFrames", world.core)
end
-- Full-event baselines in L2: repeat CAST/CHANNEL 2178/2644 modern,
-- 2110/2171 Classic; distinct 2184/2650 modern, 2157/2173 Classic.
-- Distinct costs include the existing native text/timer fixture allocations;
-- the same before/after fixture keeps those allocations and native counts equal.
local function Budget(world, label, fire, maxVM, maxKB, maxNatives)
    for _ = 1, 30 do fire() end
    local vm = world:AddonInstructions(fire)
    local before = {}
    for key, value in pairs(world.counts) do before[key] = value end
    fire()
    local natives = 0
    for key, value in pairs(world.counts) do natives = natives + value - (before[key] or 0) end
    local minimum = math.huge
    for _ = 1, 2 do
        collectgarbage("collect")
        for _ = 1, 30 do fire() end
        collectgarbage("stop")
        local kb = collectgarbage("count")
        for _ = 1, 1000 do fire() end
        minimum = math.min(minimum, collectgarbage("count") - kb)
        collectgarbage("restart")
    end
    print(string.format("%s: %d VM/event, %.3f KB/1000, %d counted natives", label, vm, minimum, natives))
    assert(minimum <= maxKB + .001, label .. " allocation budget exceeded")
    assert(natives == maxNatives, label .. " native call budget changed")
    if not measure then assert(vm <= maxVM, label .. " VM budget exceeded") end
    return vm, natives
end
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local legacy = flavor ~= "Mainline" and flavor ~= "Forever"
    local graph = ClientWorld.Graph(root, ClientWorld.CoreTOC(legacy and flavor or "Mainline"),
        "enUS", flavor == "Forever" and "camelot" or nil)
    local owner, reader
    for i, file in ipairs(graph) do
        if file:find("Castbars/MSUF_CastbarUtils.lua", 1, true) then owner = i end
        if file:find("Castbars/MSUF_CastbarRuntime.lua", 1, true) then reader = i end
    end
    assert(owner and reader and owner < reader, flavor .. " Utils load order changed")
    local world = World.New(root, { budget = true, flavor = flavor, setup = function(env)
        if legacy then
            local cast = env.UnitCastingInfo
            env.UnitCastingInfo = function(unit)
                local a,b,c,d,e,f,g,h,i = cast(unit)
                return a,b,c,d,e,f,g,h,i
            end
            env.UnitCastingDuration, env.UnitChannelDuration = false, false
        end
    end })
    world.core.Require("MSUF_EnsureDB", "castbar providers test")(true)
    local general = world.env.MSUF_DB.general
    general.showGCDBar = false
    general.castbarShowPushback = true
    world.core.Require("MSUF_Castbars_OnSettingsChanged", "castbar providers test")()
    world:Advance(.5)
    for i = #world.errors, 1, -1 do world.errors[i] = nil end
    world.secretCasts = false
    local frame = assert(world.core.Castbars.Frames.Get("player"))
    if legacy then frame.statusBar.SetTimerDuration = false end
    Load(world)
    local id = not legacy and 501 or nil
    local function Fire(event) world:Fire(frame, event, "player", nil, nil, id) end
    local cast = world:StartCast("player", "Provider cast", 600, id, { delayMS = 400 })
    Fire("UNIT_SPELLCAST_START")
    assert(frame.MSUF_castActive == true and frame._msufCountsDown == false, flavor .. " cast did not start")
    local castVM, castNative = Budget(world, flavor .. " CAST repeat", function() Fire("UNIT_SPELLCAST_START") end,
        legacy and 2110 or 2144, 0, legacy and 3 or 4)
    local function DistinctCast()
        if not legacy then id = id + 1; cast.castBarID = id end
        cast.startMS, cast.endMS = cast.startMS + 1, cast.endMS + 1
        Fire("UNIT_SPELLCAST_START")
    end
    local distinctCastVM = Budget(world, flavor .. " CAST distinct", DistinctCast,
        legacy and 2157 or 2150, legacy and .771484375 or 179.25, legacy and 3 or 5)
    world.casting.player = nil
    local channel = world:StartChannel("player", "Provider channel", 600, id)
    Fire("UNIT_SPELLCAST_CHANNEL_START")
    assert(frame._msufCountsDown == true, "normal channel did not drain")
    local channelVM, channelNative = Budget(world, flavor .. " CHANNEL repeat", function() Fire("UNIT_SPELLCAST_CHANNEL_START") end,
        legacy and 2171 or 2608, 0, legacy and 3 or 4)
    local function DistinctChannel()
        if not legacy then id = id + 1; channel.castBarID = id end
        channel.startMS, channel.endMS = channel.startMS + 1, channel.endMS + 1
        Fire("UNIT_SPELLCAST_CHANNEL_START")
    end
    local distinctChannelVM = Budget(world, flavor .. " CHANNEL distinct", DistinctChannel,
        legacy and 2173 or 2614, .21484375, legacy and 3 or 4)
    assert(castNative == (legacy and 3 or 4) and channelNative == (legacy and 3 or 4), "native budget changed")
    -- Frozen before/after ceilings are filled from the real baseline measurement.
    if not measure then
        local utils, saved = world.core.Castbars.Utils, {}
        for _, key in ipairs(providers) do saved[key], utils[key] = utils[key], nil end
        local mt = getmetatable(utils)
        setmetatable(utils, { __index = function(_, key)
            local source = debug.getinfo(2, "S").source
            if source:find("/Castbars/MSUF_CastbarRuntime.lua", 1, true) then
                assert(not saved[key], "runtime re-read mandatory " .. key)
            end
            return saved[key]
        end })
        -- Direction reads live configuration through the captured provider.
        general = world.env.MSUF_DB.general
        general.castbarUnifiedDirection = true
        world.core.Castbars.Config.Invalidate()
        Fire("UNIT_SPELLCAST_CHANNEL_START")
        assert(frame._msufCountsDown == false, "bound direction provider lost live configuration")
        general.castbarUnifiedDirection = false
        world.core.Castbars.Config.Invalidate()
        Fire("UNIT_SPELLCAST_CHANNEL_START")
        assert(frame._msufCountsDown == true, "bound channel direction changed")
        world.channeling.player = nil
        world:StartCast("player", "Bound provider text", 600, id)
        Fire("UNIT_SPELLCAST_START")
        assert(frame.castText:GetText():find("Bound provider text", 1, true), "bound text provider lost output")
        world.core.Castbars.Runtime:Stop(frame)
        setmetatable(utils, mt)
        for _, key in ipairs(providers) do utils[key] = saved[key] end
        for _, key in ipairs(providers) do
            for _, invalid in ipairs({ false, true, 42, "provider", {} }) do
                utils[key] = invalid
                local ok, message = pcall(Load, world)
                assert(not ok and tostring(message):find(key, 1, true), "invalid mandatory provider accepted: " .. key)
            end
            utils[key] = nil
            local ok, message = pcall(Load, world)
            assert(not ok and tostring(message):find(key, 1, true), "missing mandatory provider accepted: " .. key)
            utils[key] = saved[key]
        end
    end
    assert(#world.errors == 0, table.concat(world.errors, "\n"))
end
print("PASS castbar_runtime_providers: real Utils, five load graphs, cast/channel budgets and required load contracts")
