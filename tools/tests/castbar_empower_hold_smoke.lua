-- castbar_empower_hold_smoke.lua <repoRoot>
--
-- Another unit's empowered cast (an Evoker's Fire Breath or Eternity Surge on
-- the target, focus, boss or arena castbar) runs through the hold at max rank
-- like Blizzard's castbar (CastingBarFrame: endTime +
-- GetUnitEmpowerHoldAtMaxTime). UnitChannelDuration ends at the last stage,
-- so the bar must take UnitEmpoweredChannelDuration, which includes the hold:
-- otherwise its native completion reads 0 remaining at the last stage and
-- ends the bar while the cast is still held and still interruptible.
--
-- Runs the real Mainline core in tools/tests/castbar_secret_world.lua with
-- readable cast values (a spell flagged never secret), then once more with
-- secret ones (no Lua error, the hold duration still bound).
--
-- Plain Lua 5.1, repo root (absolute) as arg 1.

local root = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local SecretWorld = assert(loadfile(root .. "/tools/tests/castbar_secret_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
    return condition
end

local world = SecretWorld.New(root)
local env = world.env
env.MSUF_EnsureDB(true)
env.MSUF_Castbars_OnSettingsChanged()
world:Advance(0.5)
for index = #world.errors, 1, -1 do world.errors[index] = nil end

local frame = Check(env.MSUF.Castbars.Frames.Get("target"), "the target castbar was not built")
local function Fire(event, castBarID)
    world:Fire(frame, event, world:Payload(event, "target", castBarID))
end

-- 1. Readable values: two seconds of stages, one second held at max rank.
world.secretCasts = false
world:StartChannel("target", "Fire Breath", 2, 70, { empowered = true })
Fire("UNIT_SPELLCAST_EMPOWER_START", 70)
Check(frame:IsShown() and frame.MSUF_castActive == true, "a hostile empowered cast does not show")
local bound = frame.MSUF_durationObj
Check(bound and bound.total == 3, "the bar is bound to a " .. tostring(bound and bound.total)
    .. " s duration, not to the 3 s of stages plus the hold at max rank")
world:Advance(2.5)
Check(frame:IsShown() and frame.MSUF_castActive == true,
    "the bar ended at the last empower stage while the cast was still held at max rank")
world.channeling.target = nil
Fire("UNIT_SPELLCAST_EMPOWER_STOP", 70)
world:Advance(1.5)
Check(frame.MSUF_castActive ~= true, "the bar did not end with the empowered cast")
Check(not frame.interrupted, "empower stop without interrupter must end as succeeded")

-- 2. Secret values: the same cast raises nothing and still binds the hold.
world.secretCasts = true
world:StartChannel("target", "Eternity Surge", 2, 71, { empowered = true })
Fire("UNIT_SPELLCAST_EMPOWER_START", 71)
Check(frame:IsShown() and frame.MSUF_castActive == true, "a secret hostile empowered cast does not show")
Check(frame.MSUF_durationObj and frame.MSUF_durationObj.total == 3, "a secret empowered cast lost the hold at max rank")
world:Advance(2.5)
world.channeling.target = nil
Fire("UNIT_SPELLCAST_EMPOWER_STOP", 71)
Check(not frame.interrupted, "restricted empower stop without interrupter must end as succeeded")
world:Advance(1.5)

-- 3. Player cancellation and kicks keep feedback for either event order.
local player = Check(env.MSUF.Castbars.Frames.Get("player"), "the player castbar was not built")
env.MSUF_DB.player.showInterrupt = true
if env.MSUF and env.MSUF.Castbars then env.MSUF.Castbars.Config.Compile() end
local stopWatch = world:Watch(world:CastbarPaths())
local function CheckStagesCleared()
    Check(not player.isEmpower and player.empowerStageEnds == nil, "player empower stages were not cleared")
    for _, regions in ipairs({ player.empowerTicks or {}, player.empowerSegments or {} }) do
        for _, region in ipairs(regions) do Check(not region:IsShown(), "an empower stage remains visible") end
    end
end
local function PlayerStop(complete, interrupted)
    local S = world.Secrets.New
    world:Fire(player, "UNIT_SPELLCAST_EMPOWER_STOP", "player", S("string"), S(), complete, interrupted, 80)
end
local function PlayerInterrupted()
    world:Fire(player, "UNIT_SPELLCAST_INTERRUPTED", world:Payload("UNIT_SPELLCAST_INTERRUPTED", "player", 80, true))
end
for _, secret in ipairs({ false, true }) do
    world.secretCasts = secret
    for _, order in ipairs({ "cancel", "interrupted-first", "stop-first", "ordinary-stop-first", "failed-first" }) do
        world:StartChannel("player", "Fire Breath", 2, 80, { empowered = true })
        world:Fire(player, "UNIT_SPELLCAST_EMPOWER_START", world:Payload("UNIT_SPELLCAST_EMPOWER_START", "player", 80))
        Check(player.isEmpower and player:IsShown(), "player empower did not start")
        world:Advance(0.1)
        world.channeling.player = nil
        local deadline
        if order == "interrupted-first" then
            PlayerInterrupted()
            deadline = player.interruptFeedbackEndTime
            world:Advance(0.05)
        end
        if order == "ordinary-stop-first" then
            world:Fire(player, "UNIT_SPELLCAST_STOP", world:Payload("UNIT_SPELLCAST_STOP", "player", 80))
        elseif order == "failed-first" then
            world:Fire(player, "UNIT_SPELLCAST_FAILED", world:Payload("UNIT_SPELLCAST_FAILED", "player", 80))
        end
        PlayerStop(false, order ~= "cancel" and world.Secrets.New("string") or nil)
        if order == "stop-first" then PlayerInterrupted() end
        Check(player:IsShown() and player.castText.text == "Interrupted" and player.interruptFeedbackEndTime ~= nil,
            "player empower " .. order .. " lost Interrupted feedback (secret cast " .. tostring(secret) .. ")")
        if deadline then Check(player.interruptFeedbackEndTime == deadline, "EMPOWER_STOP extended existing interrupt feedback") end
        CheckStagesCleared()
        world:Advance(0.1)
        Check(player:IsShown(), "player empower feedback hid before its hold expired")
        world:Advance(0.8)
        Check(not player:IsShown(), "player empower feedback outlived its hold")
    end
end
-- Successful stops and the user's disabled-feedback option retain their behavior.
for _, show in ipairs({ true, false }) do
    env.MSUF_DB.player.showInterrupt = show
    if env.MSUF and env.MSUF.Castbars then env.MSUF.Castbars.Config.Compile() end
    world:StartChannel("player", "Fire Breath", 2, 80, { empowered = true })
    world:Fire(player, "UNIT_SPELLCAST_EMPOWER_START", world:Payload("UNIT_SPELLCAST_EMPOWER_START", "player", 80))
    world.channeling.player = nil
    PlayerStop(show, nil)
    Check(not player:IsShown() and player.interruptFeedbackEndTime == nil,
        show and "completed empower showed interrupt feedback" or "disabled interrupt feedback showed")
    CheckStagesCleared()
    world:Advance(0.8)
end
local violations = stopWatch()
Check(#violations == 0, "secret misuse: " .. table.concat(violations, "\n"))

Check(#world.errors == 0, "Lua errors: " .. table.concat(world.errors, "\n"))
print("castbar_empower_hold_smoke: ok")
