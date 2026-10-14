-- Player terminal payloads from live 78282522143e: UnitDocumentation.lua and
-- CastingBarFrame.lua OnEvent/HandleCastStop. EMPOWER_STOP carries completion
-- and interrupter independently; CHANNEL_STOP carries the interrupter in slot 4.
-- Lua source does not specify the engine's cross-event order. Replay competing
-- terminal orders explicitly, without assuming an INTERRUPTED always follows.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/castbar_secret_world.lua"))()
local world = World.New(root)
local env = world.env
env.MSUF_EnsureDB(true)
env.MSUF_DB.player.showInterrupt = true
env.MSUF_Castbars_OnSettingsChanged()
world:Advance(0.5)
-- The shared full-core fixture has unrelated bootstrap callbacks; observe
-- errors only during the cast lifecycle, as castbar_empower_hold_smoke does.
for index = #world.errors, 1, -1 do world.errors[index] = nil end
local player = assert(env.MSUF.Castbars.Frames.Get("player"))
local watch = world:Watch(world:CastbarPaths())
local S = world.Secrets.New
local id = 180
local function Fire(event, ...)
    world:Fire(player, event, "player", S("string"), S(), ...)
end
local function Start()
    id = id + 1
    world:StartChannel("player", "Fire Breath", 2, id, { empowered = true })
    Fire("UNIT_SPELLCAST_EMPOWER_START", id)
    assert(player.isEmpower and player:IsShown(), "empower did not start")
    world:Advance(0.1)
    world.channeling.player = nil
end
local function Feedback(message)
    assert(player:IsShown() and player.castText.text == "Interrupted" and player.interruptFeedbackEndTime,
        message)
    assert(not player.isEmpower and not player.empowerStageEnds, "stages survived feedback")
    local deadline = player.interruptFeedbackEndTime
    world:Advance(0.1)
    assert(player:IsShown() and player.interruptFeedbackEndTime == deadline, "feedback hidden by follow-up work")
    world:Advance(0.8)
    assert(not player:IsShown(), "feedback did not expire")
end

-- Native HandleCastStop accepts CHANNEL_STOP for reverseChanneling too. A kick
-- on this route must not depend on a later EMPOWER_STOP/INTERRUPTED arriving.
for _, interrupter in ipairs({ "Creature-0-1-2-3-4-5", S("string") }) do
    Start()
    Fire("UNIT_SPELLCAST_CHANNEL_STOP", interrupter, id - 1)
    Fire("UNIT_SPELLCAST_INTERRUPTED", interrupter, id - 1)
    Fire("UNIT_SPELLCAST_EMPOWER_STOP", false, interrupter, id - 1)
    world:Fire(player, "UNIT_SPELLCAST_CHANNEL_STOP", "vehicle", S("string"), S(), interrupter, id)
    assert(player.isEmpower and not player.interruptFeedbackEndTime, "unrelated stop interrupted current empower")
    Fire("UNIT_SPELLCAST_CHANNEL_STOP", interrupter, id)
    Feedback("player empower CHANNEL_STOP kick never reached interrupt feedback")
end
Start()
Fire("UNIT_SPELLCAST_CHANNEL_STOP", nil, id)
assert(not player:IsShown() and not player.interruptFeedbackEndTime, "successful channel stop showed feedback")

-- Unlike the old smoke, completion itself is restricted, just as the API permits.
Start()
Fire("UNIT_SPELLCAST_EMPOWER_STOP", S("boolean"), S("string"), id)
Feedback("restricted player empower kick was treated as a successful release")

-- STOP/FAILED are not authoritative for reverseChanneling in Blizzard's handler.
-- An INTERRUPTED in that burst must still see the displayed empower.
for _, event in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED" }) do
    Start()
    Fire(event, id)
    Fire("UNIT_SPELLCAST_INTERRUPTED", nil, id)
    assert(player.interruptFeedbackEndTime and player.castText.text == "Interrupted",
        event .. " discarded empower state before INTERRUPTED")
    Fire("UNIT_SPELLCAST_EMPOWER_STOP", false, nil, id)
    Feedback(event .. " discarded player empower identity before the interrupt")
end

-- A late channel-stop or failed-event resync must not erase established feedback.
for _, event in ipairs({ "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_STOP" }) do
    Start()
    Fire("UNIT_SPELLCAST_EMPOWER_STOP", false, nil, id)
    if event == "UNIT_SPELLCAST_CHANNEL_STOP" then Fire(event, nil, id) else Fire(event, id) end
    Feedback(event .. " erased cancellation feedback")
end

-- A normal full/early successful release must never manufacture an interrupt.
for _, complete in ipairs({ true, S("boolean") }) do
    Start()
    Fire("UNIT_SPELLCAST_EMPOWER_STOP", complete, nil, id)
    Fire("UNIT_SPELLCAST_SUCCEEDED", id)
    Fire("UNIT_SPELLCAST_STOP", id)
    world:Advance(0.1)
    assert(not player:IsShown() and not player.interruptFeedbackEndTime, "successful release showed feedback")
end

-- The real slash command toggles tracing without registering SUCCEEDED at boot.
assert(not player.events.UNIT_SPELLCAST_SUCCEEDED, "debug event registered while off")
local lines = {}
env.print = function(...)
    local values = {}
    for index = 1, select("#", ...) do values[index] = tostring((select(index, ...))) end
    lines[#lines + 1] = table.concat(values, " ")
end
env.MSUF.SlashCommands.Dispatch("castdebug")
assert(player.events.UNIT_SPELLCAST_SUCCEEDED, "debug did not observe SUCCEEDED")
Start()
Fire("UNIT_SPELLCAST_EMPOWER_STOP", S("boolean"), S("string"), id)
Fire("UNIT_SPELLCAST_SUCCEEDED", id)
Feedback("debug changed interrupt feedback")
local output = table.concat(lines, "\n")
assert(output:find("complete=<secret>", 1, true) and output:find("interruptedBy=<secret>", 1, true),
    "debug failed to redact secrets")
assert(output:find("castBarID=" .. id, 1, true) and output:find("decision=feedback", 1, true),
    "debug omitted cast identity or feedback decision")
env.MSUF.SlashCommands.Dispatch("castdebug")
assert(not player.events.UNIT_SPELLCAST_SUCCEEDED, "debug event survived toggle off")
local count = #lines
Start()
Fire("UNIT_SPELLCAST_EMPOWER_STOP", false, nil, id)
Feedback("toggle off changed feedback")
assert(#lines == count, "cast events printed while debug off")

env.MSUF_DB.player.showInterrupt = false
env.MSUF.Castbars.Config.Compile()
Start()
Fire("UNIT_SPELLCAST_EMPOWER_STOP", false, nil, id)
assert(not player:IsShown() and not player.interruptFeedbackEndTime, "disabled feedback was ignored")

local violations = watch()
assert(#violations == 0, table.concat(violations, "\n"))
assert(#world.errors == 0, table.concat(world.errors, "\n"))
print("player_empower_terminal_events_smoke: ok")
