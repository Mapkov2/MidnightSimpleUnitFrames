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
    local frame, engine = assert(env.MSUF_PlayerCastbar), assert(world.core.Castbars.Engine)
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


-- A normal STOP must identify the running cast. Retail permits a missing
-- castBarID; stale readable GUIDs must not end the next player/vehicle cast.
-- Measured known-ID STOP cost: +4 VM instructions, no added allocations;
-- START is unchanged. Unknown identity reuses one coalesced next-frame resync.
local function CheckStopIdentity(secret)
    local world = World.New(root, { budget = true, setup = function(env, w)
        env.UnitHasVehicleUI = function() return w.vehicle == true end
    end })
    local env = world.env
    env.MSUF_EnsureDB(true)
    env.MSUF_DB.general.showGCDBar = false
    env.MSUF_DB.player.showInterrupt = true
    env.MSUF_Castbars_OnSettingsChanged()
    world:Advance(0.5)
    for index = #world.errors, 1, -1 do world.errors[index] = nil end
    local frame = assert(env.MSUF_PlayerCastbar)
    local S = world.Secrets.New
    local stopWatch = world:Watch(world:CastbarPaths())
    local function Start(id, unit)
        unit = unit or "player"
        world.secretCasts = secret
        world.vehicle, world.exists.vehicle = unit == "vehicle", unit == "vehicle"
        world.casting.player, world.casting.vehicle = nil, nil
        world.channeling.player, world.channeling.vehicle = nil, nil
        world:StartCast(unit, "Current cast", 3, id, { guid = "current-guid" })
        world:Fire(frame, "UNIT_SPELLCAST_START", unit, "current-guid", 133, id)
        Check(frame:IsShown() and frame.MSUF_castActive == true, "STOP setup: missing cast")
        return unit
    end
    local function Stop(unit, guid, id, secretPayload)
        if secretPayload then guid = S("string") end
        world:Fire(frame, "UNIT_SPELLCAST_STOP", unit, guid, secretPayload and S() or 133, id)
    end
    local function Active(message)
        Check(frame:IsShown() and frame.MSUF_castActive == true, message)
    end
    for _, ids in ipairs({ { 701, false }, { false, 702 }, { false, false }, { 701, 700 } }) do
        local storedID, eventID = ids[1] or nil, ids[2] or nil
        Start(storedID)
        Stop("player", "old-guid", eventID, secret)
        Active("stale normal STOP hid the current player cast")
        world:Advance(0.1)
        Active("stale normal STOP resync lost the current player cast")
        world.casting.player = nil
        Stop("player", "current-guid", storedID, secret)
        world:Advance(0.1)
        Check(not frame:IsShown() and not frame.MSUF_castActive, "legitimate STOP did not finish")
    end
    -- NeverSecret IDs are authoritative even if a readable GUID disagrees.
    Start(703)
    world.casting.player = nil
    Stop("player", "old-guid", 703, secret)
    Check(not frame:IsShown(), "matching castBarID did not stop immediately")
    -- A readable GUID fallback is exact when either or both IDs are missing.
    if not secret then
        for _, ids in ipairs({ { 704, false }, { false, 704 }, { false, false } }) do
            Start(ids[1] or nil)
            world.casting.player = nil
            Stop("player", "current-guid", ids[2] or nil, false)
            Check(not frame:IsShown(), "matching readable GUID did not stop immediately")
        end
    end
    -- Ambiguous secret identity is coalesced through the existing resync. A
    -- secret on only one side is equally unreadable, not a GUID mismatch.
    Start(nil)
    Stop("player", "old-guid", nil, true)
    Active("ambiguous STOP hid the current cast before confirmation")
    Check(frame._msufSoftResyncPending == true, "ambiguous STOP did not schedule confirmation")
    local callback = frame._msufSoftResyncCB
    Stop("player", "old-guid", nil, true)
    Check(frame._msufSoftResyncCB == callback, "ambiguous STOP allocated another callback")
    world:Advance(0.1)
    Active("ambiguous STOP lost the current API cast")
    Check(not frame._msufSoftResyncPending, "ambiguous STOP confirmation remained pending")
    world.casting.player = nil
    Stop("player", "current-guid", nil, true)
    world:Advance(0.1)
    Check(not frame:IsShown(), "ambiguous legitimate end left the player bar shown")
    if secret then
        Start(nil)
        Stop("player", "old-guid", nil, false)
        world:Advance(0.1)
        Active("plain payload compared to a secret stored GUID")
    end
    -- A normal STOP is not a CHANNEL_STOP, even with a matching bar ID.
    world.casting.player = nil
    world:StartChannel("player", "Current channel", 3, 705)
    world:Fire(frame, "UNIT_SPELLCAST_CHANNEL_START", world:Payload("UNIT_SPELLCAST_CHANNEL_START", "player", 705))
    Stop("player", "old-guid", 705, secret)
    world:Advance(0.1)
    Active("normal STOP killed the active channel")
    Check(frame.MSUF_isChanneled == true, "normal STOP changed the channel phase")
    world.channeling.player = nil
    world:Fire(frame, "UNIT_SPELLCAST_CHANNEL_STOP", world:Payload("UNIT_SPELLCAST_CHANNEL_STOP", "player", 705))
    world:Advance(0.1)
    Check(not frame:IsShown(), "legitimate channel stop failed")
    -- Vehicle casts have the same identity rule; player events cannot stop them.
    Start(706, "vehicle")
    Stop("player", "current-guid", 706, secret)
    Active("player STOP killed a vehicle cast")
    Stop("vehicle", "old-guid", nil, secret)
    world:Advance(0.1)
    Active("stale vehicle STOP killed its current cast")
    world.casting.vehicle = nil
    Stop("vehicle", "current-guid", nil, secret)
    world:Advance(0.1)
    Check(not frame:IsShown(), "legitimate vehicle end failed")
    -- A queued ambiguous confirmation yields to newer interrupt feedback.
    Start(nil)
    Stop("player", "old-guid", nil, true)
    world.casting.player = nil
    world:Fire(frame, "UNIT_SPELLCAST_INTERRUPTED", "player", "current-guid", 133, nil, nil)
    local deadline = frame.interruptFeedbackEndTime
    Check(deadline ~= nil, "interrupt feedback did not start")
    world:Advance(0.1)
    Check(frame:IsShown() and frame.interruptFeedbackEndTime == deadline, "queued STOP erased interrupt feedback")
    Stop("player", "current-guid", nil, true)
    Check(frame:IsShown() and frame.interruptFeedbackEndTime == deadline, "STOP erased interrupt feedback")
    world:Advance(0.8)
    Check(not frame:IsShown(), "interrupt feedback did not terminate")
    -- Idle duplicate stops have nothing to confirm.
    Stop("player", "old-guid", nil, true)
    Check(not frame._msufSoftResyncPending, "idle STOP scheduled a resync")
    local violations = stopWatch()
    Check(#violations == 0, "STOP secret misuse: " .. table.concat(violations, " | "))
    Check(#world.errors == 0, "STOP deferred error: " .. table.concat(world.errors, " | "))
end
for _, secret in ipairs({ false, true }) do CheckStopIdentity(secret) end

print("Player cast-first selection and STOP identity: " .. checks .. " checks passed (readable + strict secret)")
