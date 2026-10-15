-- Real Player runtime: a finishing cast must not mask a newly started channel.
-- Models overlapping API snapshots; this is not a claim about live API timing.
local root = assert(arg[1], "repository root missing"):gsub("\\", "/"):gsub("/$", "")
local SecretWorld = assert(loadfile(root .. "/tools/tests/castbar_secret_world.lua"))()
local cases = 0
local function Check(condition, message)
    assert(condition, message)
    cases = cases + 1
end

local function NewWorld(secret)
    local reads = { cast = 0, channel = 0, castDuration = 0, channelDuration = 0 }
    local world = SecretWorld.New(root, { budget = true, playerClass = "PRIEST", setup = function(env, world)
        -- Count the Engine's selection reads separately from the existing
        -- native-timer liveness checks, which also query UnitChannelInfo.
        local function CountAPI(name, key)
            local api = env[name]
            env[name] = function(unit)
                if debug.getinfo(2, "S").source:match("/Castbars/MSUF_CastbarEngine.lua$") then
                    reads[key] = reads[key] + 1
                end
                return api(unit)
            end
        end
        CountAPI("UnitCastingInfo", "cast")
        CountAPI("UnitChannelInfo", "channel")
        CountAPI("UnitCastingDuration", "castDuration")
        CountAPI("UnitChannelDuration", "channelDuration")
        env.UnitHasVehicleUI = function() return world.vehicle == true end
    end })
    local env = world.env
    env.MSUF_EnsureDB(true)
    local g = env.MSUF_DB.general
    g.showGCDBar, g.castbarShowLatency, g.castbarChannelTicks = false, true, false
    g.castbarFeedbackDuration = 0
    env.MSUF_Castbars_OnSettingsChanged()
    world:Advance(0.5)
    for index = #world.errors, 1, -1 do world.errors[index] = nil end
    world.secretCasts = secret
    return world, assert(env.MSUF.Castbars.Frames.Get("player")), reads
end

local function Fire(world, frame, event, unit, id)
    world:Fire(frame, event, world:Payload(event, unit or "player", id))
end

local function State(frame, kind, id, label)
    local state = frame._msufPlayerState
    Check(frame:IsShown() and frame.MSUF_castActive == true, label .. ": bar hidden")
    Check(state and state.castType == kind and state.castBarID == id, label .. ": wrong API snapshot")
    Check(frame.MSUF_isChanneled == (kind == "CHANNEL"), label .. ": wrong timer direction")
end

for _, secret in ipairs({ false, true }) do
    local world, frame, reads = NewWorld(secret)
    local engine = assert(world.core.Castbars.Engine)
    local stop = world:Watch(world:CastbarPaths())
    -- Prime a same-frame cast cache before the channel event invalidates it.
    world:StartCast("player", "Previous Flash Heal", 0, 99)
    engine:BuildState("player")
    world:StartChannel("player", "Mind Flay", 3, 100)
    local castReads, channelReads = reads.cast, reads.channel
    Fire(world, frame, "UNIT_SPELLCAST_CHANNEL_START", "player", 100)
    State(frame, "CHANNEL", 100, "cast -> channel START")
    Check(reads.cast == castReads and reads.channel == channelReads + 1, "channel START must query only channel API")
    if not secret then Check(frame.castText.text == "Mind Flay", "new channel name missing") end
    world:Advance(0.3)
    State(frame, "CHANNEL", 100, "channel survives initial tick")

    for _, event in ipairs({ "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
        "UNIT_SPELLCAST_INTERRUPTIBLE" }) do
        castReads, channelReads = reads.cast, reads.channel
        Fire(world, frame, event, "player", 100)
        State(frame, "CHANNEL", 100, event)
        Check(reads.cast == castReads and reads.channel == channelReads + 1, event .. ": channel selection lost")
    end

    -- The next ordinary cast wins even while the old channel API still answers.
    world:StartCast("player", "Flash Heal", 2, 101)
    for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
        "UNIT_SPELLCAST_INTERRUPTIBLE" }) do
        Fire(world, frame, event, "player", 101)
        State(frame, "CAST", 101, "channel -> cast " .. event)
    end
    -- Legacy/unkeyed late channel updates must not replace a normal cast.
    Fire(world, frame, "UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
    State(frame, "CAST", 101, "late channel update without castBarID")
    world.channeling.player, world.casting.player = nil, nil
    Fire(world, frame, "UNIT_SPELLCAST_STOP", "player", 101)

    world:StartChannel("player", "Mind Flay", 3, 116)
    Fire(world, frame, "UNIT_SPELLCAST_CHANNEL_UPDATE", "player", 116)
    State(frame, "CHANNEL", 116, "channel UPDATE recovers idle bar")
    world.channeling.player = nil
    Fire(world, frame, "UNIT_SPELLCAST_CHANNEL_STOP", "player", 116)
    -- A new normal cast can become readable before its START event, while
    -- the prior channel STOP is still waiting for its deferred resync.
    world:StartCast("player", "Flash Heal", 2, 117)
    Fire(world, frame, "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "player")
    State(frame, "CAST", 117, "channel stop -> normal cast interruptibility")
    world.casting.player = nil
    Fire(world, frame, "UNIT_SPELLCAST_STOP", "player", 117)
    world:Advance(0.3)

    -- Missing channel data must not fall back to the stale cast or poison a
    -- generic read in the same frame. Same selection still reuses its cache.
    world:StartCast("player", "Flash Heal", 2, 102)
    engine:Invalidate("player")
    Check(engine:BuildState("player").castType == "CAST", "generic cache seed")
    castReads, channelReads = reads.cast, reads.channel
    Check(engine:BuildState("player", nil, true).active == false, "missing channel used stale cast")
    Check(reads.cast == castReads and reads.channel == channelReads + 1, "channel-only cache miss reads")
    engine:BuildState("player", nil, true)
    Check(reads.cast == castReads and reads.channel == channelReads + 1, "channel-only cache not reused")
    Check(engine:BuildState("player").castType == "CAST", "channel-only cache poisoned generic selection")
    Check(reads.cast == castReads + 1, "generic selection not refreshed")
    engine:BuildState("player", nil, false)
    Check(reads.cast == castReads + 1, "generic cache not reused for nil/false selection")
    world:StartChannel("player", "Mind Flay", 3, 103)
    Check(engine:BuildState("player", nil, true).castBarID == 103, "generic cache masked forced channel")

    -- Dedicated Empower handling stays authoritative, including its updates.
    world.channeling.player = nil
    world:StartCast("player", "Fire Breath", 3, 104, { empowered = true })
    Fire(world, frame, "UNIT_SPELLCAST_EMPOWER_START", "player", 104)
    Check(frame:IsShown() and frame.isEmpower == true, "Empower START regressed")
    Fire(world, frame, "UNIT_SPELLCAST_EMPOWER_UPDATE", "player", 104)
    Check(frame:IsShown() and frame.isEmpower == true, "Empower UPDATE regressed")
    world.casting.player = nil
    Fire(world, frame, "UNIT_SPELLCAST_EMPOWER_STOP", "player", 104)
    world:Advance(0.6)

    -- Vehicle selection must apply the same query to both candidate units.
    world.vehicle, world.exists.vehicle = true, true
    world:StartCast("vehicle", "Expired vehicle cast", 0, 105)
    world:StartChannel("player", "Mind Flay", 3, 106)
    Fire(world, frame, "UNIT_SPELLCAST_CHANNEL_START", "player", 106)
    State(frame, "CHANNEL", 106, "inactive vehicle -> player channel")
    Check(frame._msufActiveCastUnit == "player", "stale vehicle cast stole player channel")
    world:StartChannel("vehicle", "Vehicle channel", 3, 107)
    Fire(world, frame, "UNIT_SPELLCAST_CHANNEL_START", "vehicle", 107)
    State(frame, "CHANNEL", 107, "vehicle channel")
    Check(frame._msufActiveCastUnit == "vehicle", "vehicle channel unit lost")
    Fire(world, frame, "UNIT_SPELLCAST_CHANNEL_UPDATE", "vehicle", 107)
    State(frame, "CHANNEL", 107, "vehicle channel update")
    world.vehicle = false
    Fire(world, frame, "UNIT_SPELLCAST_CHANNEL_START", "player", 106)
    State(frame, "CHANNEL", 106, "vehicle exit -> player channel")

    -- Other castbars retain their generic cast-first contract and still show
    -- ordinary channels. Use their actual event scripts, not Player helpers.
    local Frames = world.env.MSUF.Castbars.Frames
    local others = { { Frames.Get("target"), "target" }, { Frames.Get("focus"), "focus" },
        { Frames.Get("boss", 1), "boss1" }, { Frames.Get("arena", 1), "arena1" } }
    for _, pair in ipairs(others) do
        local other, unit = assert(pair[1]), pair[2]
        world:StartCast(unit, "Shadow Bolt", 2, 110)
        world:StartChannel(unit, "Mind Flay", 3, 111)
        Fire(world, other, "UNIT_SPELLCAST_START", unit, 110)
        Check(other:IsShown() and engine:BuildState(unit).castType == "CAST", unit .. ": normal cast regressed")
        world.casting[unit] = nil
        Fire(world, other, "UNIT_SPELLCAST_CHANNEL_START", unit, 111)
        Check(other:IsShown() and engine:BuildState(unit).castType == "CHANNEL", unit .. ": channel regressed")
    end
    -- A clean channel stop can soft-resync to the next regular cast; stale
    -- channel selection must not leak into that existing recovery callback.
    world.channeling.player = nil
    world:StartCast("player", "Flash Heal", 2, 112)
    Fire(world, frame, "UNIT_SPELLCAST_CHANNEL_STOP", "player", 106)
    world:Advance(0.3)
    State(frame, "CAST", 112, "channel STOP -> generic soft resync")
    world.casting.player = nil
    Fire(world, frame, "UNIT_SPELLCAST_STOP", "player", 112)
    world:StartCast("player", "Expired Flash Heal", 0, 113)
    castReads = reads.cast
    Fire(world, frame, "UNIT_SPELLCAST_CHANNEL_START", "player", 114)
    Check(reads.cast == castReads, "missing channel abort performed an unused cast query")
    Check(not frame:IsShown() and frame.MSUF_castActive ~= true, "missing channel displayed expired cast")
    world:StartCast("player", "Flash Heal", 2, 115)
    Fire(world, frame, "UNIT_SPELLCAST_START", "player", 115)
    State(frame, "CAST", 115, "ordinary cast after missing channel")
    local violations = stop()
    Check(#violations == 0, "secret misuse: " .. table.concat(violations, " | "))
    Check(#world.errors == 0, "deferred error: " .. table.concat(world.errors, " | "))
end
print("Player channel transition: " .. cases .. " checks passed (readable + strict secret)")
