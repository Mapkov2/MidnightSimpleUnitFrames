-- <repoRoot> [measure] [playerRuntimePath]: real player events and mandatory pushback provider.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local measure = arg[2] == "measure"
local runtimePath = root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_PlayerCastbarRuntime.lua"
local path = arg[3] or runtimePath
local World = dofile(root .. "/tools/tests/castbar_secret_world.lua")
local ClientWorld = dofile(root .. "/tools/tests/client_world.lua")
local function Load(world)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    local chunk = assert(loadstring(source, "@" .. runtimePath))
    setfenv(chunk, world.env)
    chunk("MidnightSimpleUnitFrames", world.core)
end
-- ce4767d34 before -> bound provider, START / DELAYED / CHANNEL_START / CHANNEL_UPDATE:
-- Mainline + Forever: 2185/2233/2651/2692 -> 2178/2226/2644/2685 VM/event.
-- Vanilla + TBC + Mists: 2164/2208/2178/2215 -> 2157/2201/2171/2208 VM/event.
-- Both: 0 KB/1000 events; native calls, objects and provider calls stay unchanged.
local VM = {
    modern = { 2178, 2226, 2644, 2685 },
    legacy = { 2157, 2201, 2171, 2208 },
}
local function Measure(world, label, fire, budget, legacy)
    for _ = 1, 30 do fire() end
    local instructions = world:AddonInstructions(fire)
    local counts = {}
    for key, value in pairs(world.counts) do counts[key] = value end
    fire()
    local natives, timers, objects = 0, 0, 0
    for key, value in pairs(world.counts) do
        local delta = value - (counts[key] or 0)
        natives = natives + delta
        if key == "SetTimerDuration" then timers = delta end
        if key == "UnitDuration" then objects = delta end
    end
    local expected = legacy and { SetValue = 2, SetText = 1 } or { UnitDuration = 1, SetTimerDuration = 1, SetText = 2 }
    for key, value in pairs(world.counts) do
        assert(value - (counts[key] or 0) == (expected[key] or 0), label .. " native count changed: " .. key .. "=" .. (value - (counts[key] or 0)))
    end
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
    print(string.format("%s: %d VM/event, %.3f KB/1000, %d counted native calls, %d duration objects, %d native timers",
        label, instructions, minimum, natives, objects, timers))
    if not measure then assert(instructions <= budget, label .. " VM budget exceeded: " .. instructions) end
    assert(minimum <= .001, label .. " allocated")
    assert(natives == (legacy and 3 or 4) and objects == (legacy and 0 or 1) and timers == (legacy and 0 or 1),
        label .. " native budget changed")
end
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local legacy = flavor ~= "Mainline" and flavor ~= "Forever"
    local graph = ClientWorld.Graph(root, ClientWorld.CoreTOC(legacy and flavor or "Mainline"),
        "enUS", flavor == "Forever" and "camelot" or nil)
    local providerIndex, consumerIndex
    for i, file in ipairs(graph) do
        if file:find("Castbars/MSUF_CastbarUtils.lua", 1, true) then providerIndex = i end
        if file:find("Castbars/MSUF_PlayerCastbarRuntime.lua", 1, true) then consumerIndex = i end
    end
    assert(providerIndex and consumerIndex and providerIndex < consumerIndex, flavor .. " provider must load first")
    local world = World.New(root, { budget = true, flavor = flavor, setup = function(env)
        if legacy then
            -- The Classic tuple has neither castBarID nor delay; duration APIs are absent.
            local casting = env.UnitCastingInfo
            env.UnitCastingInfo = function(unit)
                local name, text, icon, startMS, endMS, trade, castID, interruptible, spellID = casting(unit)
                return name, text, icon, startMS, endMS, trade, castID, interruptible, spellID
            end
            env.UnitCastingDuration, env.UnitChannelDuration = false, false
        end
    end })
    world.core.Require("MSUF_EnsureDB", "player pushback test")(true)
    world.env.MSUF_DB.general.showGCDBar = false
    world.env.MSUF_DB.general.castbarShowPushback = true
    world.core.Require("MSUF_Castbars_OnSettingsChanged", "player pushback test")()
    world:Advance(.5)
    for i = #world.errors, 1, -1 do world.errors[i] = nil end
    world.secretCasts = false
    local player = assert(world.core.Castbars.Frames.Get("player"))
    if legacy then player.statusBar.SetTimerDuration = false end
    Load(world)
    player:SetScript("OnEvent", world.core.Castbars.Player.PlayerCastbar_OnEvent)
    local utils = world.core.Castbars.Utils
    local provider = assert(utils.Castbar_ResolvePushbackMS)
    local payloadID, expectedInitial
    if not legacy then payloadID, expectedInitial = 501, 0 end
    local function Fire(event)
        world:Fire(player, event, "player", nil, nil, payloadID)
    end
    local cast = world:StartCast("player", "Pushback cast", 600, payloadID)
    Fire("UNIT_SPELLCAST_START")
    assert(player.MSUF_castActive == true and player:IsShown(), flavor .. " player cast did not start")
    local initial = player._msufPushbackMS
    assert(initial == expectedInitial, flavor .. " initial delay changed")
    cast.startMS, cast.endMS, cast.delayMS = cast.startMS + 250, cast.endMS + 250, 400
    Fire("UNIT_SPELLCAST_DELAYED")
    assert(player._msufPushbackMS == (legacy and 250 or 400), flavor .. " real resolver lost pushback")
    assert(player.castText:GetText():find(legacy and "+0.3" or "+0.4", 1, true), flavor .. " pushback text missing")
    local budgets = VM[legacy and "legacy" or "modern"]
    for index, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED" }) do
        Measure(world, flavor .. " " .. event, function() Fire(event) end, budgets[index], legacy)
    end
    -- The player applies the real provider once in addition to the shared duration runtime.
    local calls = 0
    debug.sethook(function(event)
        if event == "call" and debug.getinfo(2, "f").func == provider then calls = calls + 1 end
    end, "c")
    Fire("UNIT_SPELLCAST_DELAYED")
    debug.sethook()
    assert(calls == (legacy and 1 or 2), flavor .. " provider call budget changed: " .. calls)
    world.casting.player = nil
    if not legacy then payloadID = 502 end
    world:StartChannel("player", "Channel", 600, payloadID)
    Fire("UNIT_SPELLCAST_CHANNEL_START")
    assert(player.MSUF_isChanneled == true and player._msufPushbackMS == nil, flavor .. " channel retained pushback")
    assert((player.MSUF_timerDriven == true) == (not legacy), flavor .. " timer capability changed")
    for index, event in ipairs({ "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE" }) do
        Measure(world, flavor .. " " .. event, function() Fire(event) end, budgets[index + 2], legacy)
    end
    if not legacy then
        world.channeling.player = nil
        world.secretCasts = true
        payloadID = 501
        cast = world:StartCast("player", "Restricted cast", 600, payloadID, { delayMS = 500 })
        local stop = world:Watch(world:CastbarPaths())
        Fire("UNIT_SPELLCAST_START")
        Fire("UNIT_SPELLCAST_DELAYED")
        local violations = stop()
        assert(#violations == 0, table.concat(violations, "\n"))
        assert(player._msufPushbackMS == 500 and player.MSUF_timerDriven == true, "restricted cast changed")
        world.secretCasts = false
    end
    assert(#world.errors == 0, table.concat(world.errors, "\n"))
    if not measure then
        -- Retain the captured real provider after its namespace field disappears.
        utils.Castbar_ResolvePushbackMS = nil
        local previous = getmetatable(utils)
        setmetatable(utils, { __index = function(_, key)
            assert(key ~= "Castbar_ResolvePushbackMS", "player looked up its guaranteed pushback provider again")
        end })
        world.channeling.player = nil
        if not legacy then payloadID = 501 end
        cast = world:StartCast("player", "Bound provider", 600, payloadID, { delayMS = 400 })
        Fire("UNIT_SPELLCAST_START")
        cast.startMS = cast.startMS + 250
        Fire("UNIT_SPELLCAST_DELAYED")
        assert(player._msufPushbackMS == (legacy and 250 or 400), "bound real provider bypassed")
        setmetatable(utils, previous)
        for _, invalid in ipairs({ false, true, 42, "provider", {} }) do
            utils.Castbar_ResolvePushbackMS = invalid
            local ok, message = pcall(Load, world)
            assert(not ok and tostring(message):find("Castbar_ResolvePushbackMS", 1, true),
                flavor .. " invalid provider was not rejected at load")
        end
        utils.Castbar_ResolvePushbackMS = nil
        local ok, message = pcall(Load, world)
        assert(not ok and tostring(message):find("Castbar_ResolvePushbackMS", 1, true),
            flavor .. " missing provider was not rejected at load")
        utils.Castbar_ResolvePushbackMS = provider
    end
end
print("castbar_player_pushback_provider: PASS")
