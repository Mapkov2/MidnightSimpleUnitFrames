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
-- Reserve native timer storage before heap sampling. All actual timer calls,
-- their state, and the mock native text-formatting costs remain in the sample.
-- Lua 5.1 strings have the same payload but a 16- or 24-byte header. Each
-- distinct channel second produces ten timer display strings on modern clients.
-- The static Classic >30 label removes those timer strings, leaving the ten
-- suffixes and ten composed names for distinct Classic casts.
-- The x86 limits below already charge the 16-byte header on every string.
string.rep("b", 129) -- Warm the calibration call before counting its payload.
collectgarbage("stop")
local stringBefore = collectgarbage("count")
local headerProbe = string.rep("q", 257)
local stringHeader = (collectgarbage("count") - stringBefore) * 1024 - #headerProbe - 1
collectgarbage("restart")
assert(stringHeader == 16 or stringHeader == 24, "unexpected Lua string header: " .. stringHeader)
-- 2026-11-27: long Classic casts and channels skip one text write. VM
-- ceilings stay within 2% of the uncapped checkout: 2130/2177 CAST and
-- 2179/2181 CHANNEL (repeat/distinct).
local function Budget(world, label, fire, maxVM, maxKB, maxNatives, strings)
    for _ = 1, 30 do fire() end
    local vm = world:AddonInstructions(fire)
    local before = {}
    for key, value in pairs(world.counts) do before[key] = value end
    local timerCount = world.timerCount
    fire()
    local timersPerEvent = world.timerCount - timerCount
    local natives = 0
    for key, value in pairs(world.counts) do natives = natives + value - (before[key] or 0) end
    local minimum = math.huge
    for _ = 1, 2 do
        collectgarbage("collect")
        for _ = 1, 30 do fire() end
        if timersPerEvent > 0 then world:ReserveTimerEntries(1000 * timersPerEvent) end
        collectgarbage("stop")
        local kb = collectgarbage("count")
        for _ = 1, 1000 do fire() end
        minimum = math.min(minimum, collectgarbage("count") - kb)
        collectgarbage("restart")
    end
    print(string.format("%s: %d VM/event, %.3f KB/1000, %d counted natives", label, vm, minimum, natives))
    local comparableKB = minimum - (strings or 0) * (stringHeader - 16) / 1024
    assert(comparableKB <= maxKB + .001, label .. " allocation budget exceeded")
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
    if not measure then
        local format = world.core.MSUF_Util.FormatCastbarTimeText
        assert(format("CURRENT", 60, nil) == ">30", "long casts need the default remaining-time cap")
        assert(format("CURRENT", 30, 60) == "30.0" and format("CURRENT", 29.9, 60) == "29.9")
        assert(format("CURRENT_MAX", 30.001, 60) == ">30 / 60.0")
        assert(format("MAX_CURRENT", 45, 60) == "60.0 / >30")
        assert(format("ELAPSED", 32, 75) == "43.0")
        assert(format("ELAPSED_MAX", 32, 75) == "43.0 / 75.0")
        assert(format("MAX_ELAPSED", 32, 75) == "75.0 / 43.0")
        local setTime = world.core.MSUF_Util.SetCastTimeText
        setTime(frame, 30.001, 60)
        assert(frame.timeText:GetText() == ">30", "live Lua renderer lost the long-cast cap")
        local writes = world.counts.SetText
        setTime(frame, 59, 60)
        assert(world.counts.SetText == writes, "a static >30 label caused another write")
        setTime(frame, 30, 60)
        assert(frame.timeText:GetText() == "30.0", "live Lua renderer lost the cutoff transition")
        if not legacy then
            local binding = assert(frame._msufDurationTextBinding)
            local rules = binding.properties[1].formatter.breakpoints
            assert(rules[1].format == "%.1f" and rules[2] and rules[2].format == ">30"
                and rules[2].threshold > 30 and rules[2].threshold <= 30.001,
                "native binding did not use the capped remaining-duration formatter")
            local runtime = world.core.Castbars.Runtime
            for _, spec in ipairs({ { "CURRENT_MAX", 1, 2 }, { "MAX_CURRENT", 2, 1 } }) do
                assert(runtime:BindNativeTimeText(frame, frame.MSUF_durationObj, spec[1]))
                local remaining = binding.properties[spec[2]].formatter
                assert(remaining == runtime:GetRemainingTimeFormatter(), "remaining-duration format was not shared")
                assert(#remaining.breakpoints == 2 and remaining.breakpoints[2].format == ">30")
                assert(#binding.properties[spec[3]].formatter.breakpoints == 1, "total duration was capped")
            end
            for _, mode in ipairs({ "ELAPSED", "ELAPSED_MAX", "MAX_ELAPSED" }) do
                assert(runtime:BindNativeTimeText(frame, frame.MSUF_durationObj, mode))
                for _, component in ipairs(binding.properties) do
                    assert(#component.formatter.breakpoints == 1, "elapsed/total duration was capped")
                end
            end
            assert(runtime:BindNativeTimeText(frame, frame.MSUF_durationObj, "CURRENT"))
        end
    end
    local castVM, castNative = Budget(world, flavor .. " CAST repeat", function() Fire("UNIT_SPELLCAST_START") end,
        legacy and 2172 or 2186, 0, legacy and 2 or 4)
    local function DistinctCast()
        if not legacy then id = id + 1; cast.castBarID = id end
        cast.startMS, cast.endMS = cast.startMS + 1, cast.endMS + 1
        Fire("UNIT_SPELLCAST_START")
    end
    local distinctCastVM = Budget(world, flavor .. " CAST distinct", DistinctCast,
        legacy and 2220 or 2193, legacy and .556640625 or 0, legacy and 2 or 5, legacy and 20 or 0)
    world.casting.player = nil
    local channel = world:StartChannel("player", "Provider channel", 600, id)
    Fire("UNIT_SPELLCAST_CHANNEL_START")
    assert(frame._msufCountsDown == true, "normal channel did not drain")
    local channelVM, channelNative = Budget(world, flavor .. " CHANNEL repeat", function() Fire("UNIT_SPELLCAST_CHANNEL_START") end,
        legacy and 2222 or 2660, 0, legacy and 2 or 4)
    local function DistinctChannel()
        if not legacy then id = id + 1; channel.castBarID = id end
        channel.startMS, channel.endMS = channel.startMS + 1, channel.endMS + 1
        Fire("UNIT_SPELLCAST_CHANNEL_START")
    end
    local distinctChannelVM = Budget(world, flavor .. " CHANNEL distinct", DistinctChannel,
        legacy and 2224 or 2666, legacy and 0 or .21484375, legacy and 2 or 4, legacy and 0 or 10)
    assert(castNative == (legacy and 2 or 4) and channelNative == (legacy and 2 or 4), "native budget changed")
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
    if not measure and not legacy then
        local runtime = world.core.Castbars.Runtime
        runtime:Stop(frame)
        world.casting.player = nil
        world:StartChannel("player", "Readable long channel", 32, 709)
        world:Fire(frame, "UNIT_SPELLCAST_CHANNEL_START", "player", nil, nil, 709)
        local update = world.core.Castbars.Manager.UpdateCastbarFrame
        local deadline = assert(frame._msufPlainEndTime)
        update(frame, 0, deadline - 30.05)
        assert(frame.timeText:GetText() == ">30", "a long channel lost its cap")
        update(frame, 0, deadline - 30)
        assert(frame.timeText:GetText() == "30.0", "the Lua cache hid the cutoff transition")

        runtime:Stop(frame)
        world.secretCasts = true
        local watch = world:Watch(world:CastbarPaths())
        world:StartChannel("player", "Restricted long channel", 31, 710)
        world:Fire(frame, "UNIT_SPELLCAST_CHANNEL_START", world:Payload("UNIT_SPELLCAST_CHANNEL_START", "player", 710))
        world:Advance(0.2)
        local duration = assert(frame.MSUF_durationObj, "protected channel did not get a duration")
        assert(duration.lastRemainingFormat == ">30" and world.env.issecretvalue(frame.timeText:GetText()),
            "a protected channel did not use the native remaining-time formatter")
        world:Advance(1)
        assert(duration.lastRemainingFormat == "%.1f" and world.env.issecretvalue(frame.timeText:GetText()),
            "a protected channel did not return to the countdown")
        local violations = watch()
        assert(#violations == 0, table.concat(violations, " | "))
    end
    assert(#world.errors == 0, table.concat(world.errors, "\n"))
end
print("PASS castbar_runtime_providers: real Utils, five load graphs, cast/channel budgets and required load contracts")
