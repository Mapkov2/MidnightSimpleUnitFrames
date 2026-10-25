-- <root> [measure] [source fixture directory]: mandatory Utils and real marker/GCD paths.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local measure = arg[2] == "measure"
local World = dofile(root .. "/tools/tests/castbar_secret_world.lua")
local ClientWorld = dofile(root .. "/tools/tests/client_world.lua")
local files = {
    { "MSUF_CastbarGCD.lua", "CB_ApplyTexts", "GetReverseFillSafe", "Castbar_PlainNumber" },
    { "MSUF_CastbarChannelTicks.lua", "GetCastbarCountsDown" },
}
local function Load(world, name)
    local path = root .. "/MidnightSimpleUnitFrames/Castbars/" .. name
    local file = assert(io.open(arg[3] and arg[3] .. "/" .. name or path, "rb"))
    local source = file:read("*a")
    file:close()
    local chunk = assert(loadstring(source, "@" .. path))
    setfenv(chunk, world.env)
    chunk("MidnightSimpleUnitFrames", world.core)
end
local failures = {}
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local world = World.New(root, { budget = true, flavor = flavor })
    world.core.Require("MSUF_EnsureDB", "outer providers test")(true)
    local general = world.env.MSUF_DB.general
    general.showGCDBar, general.showGCDBarTime, general.showGCDBarSpell = true, true, true
    world.core.Castbars.Config.Invalidate()
    world.core.Require("MSUF_Castbars_OnSettingsChanged", "outer providers test")()
    world:Advance(.5)
    local graph = ClientWorld.Graph(root, ClientWorld.CoreTOC(flavor == "Forever" and "Mainline" or flavor),
        "enUS", flavor == "Forever" and "camelot" or nil)
    local positions = {}
    for i, path in ipairs(graph) do positions[path:match("[^/]+$")] = i end
    for _, spec in ipairs(files) do
        assert(positions["MSUF_CastbarUtils.lua"] < positions[spec[1]], flavor .. " provider loads too late")
        Load(world, spec[1])
    end
    local frame = assert(world.core.Castbars.Frames.Get("player"))
    frame.unit = "player"
    if flavor == "Mainline" then
        world.core.Castbars.GCD.GCDBar_SyncRegistration()
        local driver
        for i = #world.widgets.frames, 1, -1 do
            if world.widgets.frames[i].frameName == "MSUF_GCDBarDriver" then driver = world.widgets.frames[i]; break end
        end
        assert(driver)
        world.secretCooldowns, world.secretCasts = false, false
        local cooldown = { startTime = world.clock, total = 1.5 }
        world.cooldowns[61304], world.castTimes[1449] = cooldown, 0
        local function Cycle()
            cooldown.startTime = world.clock
            world:Fire(driver, "UNIT_SPELLCAST_SUCCEEDED", "player", nil, 1449)
            assert(frame._msufGCDActive, "real GCD start was bypassed")
            world:Advance(1.7)
            assert(not frame._msufGCDActive, "real GCD completion was bypassed")
        end
        for _ = 1, 30 do Cycle() end
        local vm = world:AddonInstructions(Cycle)
        local counts, natives = {}, 0
        for key, count in pairs(world.counts) do counts[key] = count end
        Cycle()
        for key, count in pairs(world.counts) do natives = natives + count - (counts[key] or 0) end
        local minimum = math.huge
        for _ = 1, 2 do
            collectgarbage("collect")
            for _ = 1, 30 do Cycle() end
            collectgarbage("stop")
            local kb = collectgarbage("count")
            for _ = 1, 100 do Cycle() end
            minimum = math.min(minimum, collectgarbage("count") - kb)
            collectgarbage("restart")
        end
        print(string.format("Mainline GCD full cast: %d VM, %d counted natives, %.3f KB/100", vm, natives, minimum))
        if not measure then
            assert(vm <= 1218 and natives == 6 and minimum <= .001, "full GCD cast budget regressed")
        end
    end
    general = world.env.MSUF_DB.general
    frame.MSUF_isChanneled, frame.isEmpower, frame._msufCountsDown = true, nil, nil
    general.castbarShowChannelTicks, general.castbarAccentLastTick = true, true
    world.core.Castbars.Config.Invalidate()
    local function Markers() world.core.Castbars.ChannelTicks.PlayerChannelHasteMarkers_Update(frame, true) end
    for _ = 1, 30 do Markers() end
    assert(frame._msufPlayerChannelTickRuntimeActive and frame._msufPlayerChannelHasteMarkers,
        "real marker painter was bypassed")
    local vm = world:AddonInstructions(Markers)
    local minimum = math.huge
    for _ = 1, 2 do
        collectgarbage("collect")
        for _ = 1, 30 do Markers() end
        collectgarbage("stop")
        local kb = collectgarbage("count")
        for _ = 1, 1000 do Markers() end
        minimum = math.min(minimum, collectgarbage("count") - kb)
        collectgarbage("restart")
    end
    print(string.format("%s marker update: %d VM, %.3f KB/1000", flavor, vm, minimum))
    frame._msufCountsDown = true
    local function Tick() world.core.Castbars.ChannelTicks.PlayerChannelHasteMarkers_Update(frame, false) end
    for _ = 1, 30 do Tick() end
    local tickVM = world:AddonInstructions(Tick)
    local tickKB = math.huge
    for _ = 1, 2 do
        collectgarbage("collect")
        for _ = 1, 30 do Tick() end
        collectgarbage("stop")
        local kb = collectgarbage("count")
        for _ = 1, 1000 do Tick() end
        tickKB = math.min(tickKB, collectgarbage("count") - kb)
        collectgarbage("restart")
    end
    local methods, tickNatives = {}, 0
    local marker = frame._msufPlayerChannelHasteMarkers[1]
    for _, key in ipairs({ "SetWidth", "SetColorTexture", "SetAlpha", "Show", "SetPoint", "ClearAllPoints" }) do
        methods[marker[key]] = true
    end
    methods[frame.statusBar.GetWidth] = true
    debug.sethook(function()
        if methods[debug.getinfo(2, "f").func] then tickNatives = tickNatives + 1 end
    end, "c")
    Tick()
    debug.sethook()
    print(string.format("%s marker tick: %d VM, %d counted sinks, %.3f KB/1000", flavor, tickVM, tickNatives, tickKB))
    if not measure then
        assert(tickVM <= 325 and tickNatives == 21 and tickKB <= .001, "marker tick budget regressed")
    end
    frame._msufCountsDown = nil
    if not measure then
        assert(vm <= 547 and minimum <= .001, "marker budget regressed")
        local utils = world.core.Castbars.Utils
        local saved, mt = {}, getmetatable(utils)
        for _, spec in ipairs(files) do
            for i = 2, #spec do saved[spec[i]], utils[spec[i]] = utils[spec[i]], nil end
        end
        setmetatable(utils, { __index = function(_, key)
            local source = debug.getinfo(2, "S").source
            if saved[key] and (source:find("MSUF_CastbarGCD.lua", 1, true)
                or source:find("MSUF_CastbarChannelTicks.lua", 1, true)) then
                error("consumer re-read bound Utils." .. key)
            end
            return saved[key]
        end })
        Markers()
        assert(frame._msufPlayerChannelHasteMarkers[1].width == 3, "normal channel accent moved")
        general.castbarUnifiedDirection = true
        world.core.Castbars.Config.Invalidate()
        Markers()
        local markers = frame._msufPlayerChannelHasteMarkers
        assert(markers[#markers].width == 3, "bound direction lost live configuration")
        world.core.Castbars.GCD.PaintSample(frame, general)
        assert(frame.castText:GetText():find("GCD", 1, true), "bound text provider lost sample output")
        setmetatable(utils, mt)
        for key, provider in pairs(saved) do utils[key] = provider end
        for _, spec in ipairs(files) do
            for i = 2, #spec do
                local key, saved = spec[i], utils[spec[i]]
                for _, bad in ipairs({ false, true, 42, "provider", {} }) do
                    utils[key] = bad
                    local ok, why = pcall(Load, world, spec[1])
                    if ok or not tostring(why):find(key, 1, true) then
                        failures[#failures + 1] = flavor .. " accepted invalid " .. spec[1] .. ": " .. key
                    end
                end
                utils[key] = nil
                local ok, why = pcall(Load, world, spec[1])
                if ok or not tostring(why):find(key, 1, true) then
                    failures[#failures + 1] = flavor .. " accepted absent " .. key
                end
                utils[key] = saved
            end
            Load(world, spec[1])
        end
    end
end
assert(#failures == 0, table.concat(failures, "\n"))
print("PASS castbar_outer_providers: five Utils load contracts and real marker updates")
