-- The owner reverted 6.502's event-selected channel query. Preserve the
-- previous generic cast-first selection, including its same-frame cache.
-- This does not claim the original missing-player-bar report is resolved.
local root = assert(arg[1], "repository root missing"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/castbar_secret_world.lua"))()
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
for _, secret in ipairs({ false, true }) do
    local reads = { cast = 0, channel = 0 }
    local world = World.New(root, { budget = true, setup = function(env, w)
        for name, key in pairs({ UnitCastingInfo = "cast", UnitChannelInfo = "channel" }) do
            local api = env[name]
            env[name] = function(unit)
                if debug.getinfo(2, "S").source:match("/Castbars/MSUF_CastbarEngine.lua$") then
                    reads[key] = reads[key] + 1
                end
                return api(unit)
            end
        end
        env.UnitHasVehicleUI = function() return w.vehicle == true end
    end })
    local env = world.env
    env.MSUF_EnsureDB(true)
    env.MSUF_DB.general.showGCDBar = false
    env.MSUF_Castbars_OnSettingsChanged()
    world:Advance(0.5)
    for index = #world.errors, 1, -1 do world.errors[index] = nil end
    world.secretCasts = secret
    local frame, engine = assert(env.MSUF.Castbars.Frames.Get("player")), assert(world.core.Castbars.Engine)
    local function Fire(event, id, unit)
        world:Fire(frame, event, world:Payload(event, unit or "player", id))
    end
    local function State(kind, id, label)
        Check(frame:IsShown() and frame.MSUF_castActive == true, label .. ": bar hidden")
        local state = frame._msufPlayerState
        Check(state and state.castType == kind and state.castBarID == id, label .. ": wrong snapshot")
        Check(frame.MSUF_isChanneled == (kind == "CHANNEL"), label .. ": wrong direction")
    end
    local stopWatch = world:Watch(world:CastbarPaths())
    -- Overlapping results keep the exact pre-6.502 priority on every event.
    -- Do not reinstate the unconfirmed channel-only selection as a cleanup fix.
    world:StartCast("player", "Outgoing cast", 2, 99)
    world:StartChannel("player", "New channel", 3, 100)
    for _, event in ipairs({ "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
        "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" }) do
        local castReads, channelReads = reads.cast, reads.channel
        Fire(event, 99)
        State("CAST", 99, event .. " overlap")
        Check(reads.cast == castReads + 1 and reads.channel == channelReads, event .. ": cast-first query changed")
    end
    -- An unused third argument must neither select a new query nor split cache.
    engine:Invalidate("player")
    local castReads, channelReads = reads.cast, reads.channel
    Check(engine:BuildState("player").castBarID == 99, "generic selection")
    Check(engine:BuildState("player", nil, true).castBarID == 99, "channel-only selection survived rollback")
    Check(reads.cast == castReads + 1 and reads.channel == channelReads, "generic cache was split by query mode")
    world.casting.player = nil
    for _, event in ipairs({ "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
        "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" }) do
        castReads, channelReads = reads.cast, reads.channel
        Fire(event, 100)
        State("CHANNEL", 100, event)
        Check(reads.cast == castReads + 1 and reads.channel == channelReads + 1, event .. ": channel discovery changed")
    end
    world.channeling.player = nil
    Fire("UNIT_SPELLCAST_CHANNEL_STOP", 100)
    world:Advance(0.1)
    Check(not frame:IsShown(), "channel stop failed")
    world:StartCast("player", "Normal cast", 2, 101)
    for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_INTERRUPTIBLE" }) do
        Fire(event, 101)
        State("CAST", 101, event)
    end
    world.casting.player = nil
    Fire("UNIT_SPELLCAST_STOP", 101)
    Check(not frame:IsShown(), "normal cast stop failed")
    -- Missing start data still reaches the legacy stop cleanup and terminates.
    Fire("UNIT_SPELLCAST_CHANNEL_START", 102)
    Check(not frame:IsShown(), "missing channel displayed a bar")
    world.vehicle, world.exists.vehicle = true, true
    world:StartChannel("vehicle", "Vehicle channel", 3, 103)
    Fire("UNIT_SPELLCAST_CHANNEL_START", 103, "vehicle")
    State("CHANNEL", 103, "vehicle channel")
    Check(frame._msufActiveCastUnit == "vehicle", "vehicle unit lost")
    local violations = stopWatch()
    Check(#violations == 0, "secret misuse: " .. table.concat(violations, " | "))
    Check(#world.errors == 0, "deferred error: " .. table.concat(world.errors, " | "))
end
print("Player cast-first selection: " .. checks .. " checks passed (readable + strict secret)")
