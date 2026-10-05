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

local frame = Check(env.MSUF_TargetCastBar, "the target castbar was not built")
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

-- 2. Secret values: the same cast raises nothing and still binds the hold.
world.secretCasts = true
world:StartChannel("target", "Eternity Surge", 2, 71, { empowered = true })
Fire("UNIT_SPELLCAST_EMPOWER_START", 71)
Check(frame:IsShown() and frame.MSUF_castActive == true, "a secret hostile empowered cast does not show")
Check(frame.MSUF_durationObj and frame.MSUF_durationObj.total == 3, "a secret empowered cast lost the hold at max rank")
world:Advance(2.5)
world.channeling.target = nil
Fire("UNIT_SPELLCAST_EMPOWER_STOP", 71)
world:Advance(1.5)

Check(#world.errors == 0, "Lua errors: " .. table.concat(world.errors, "\n"))
print("castbar_empower_hold_smoke: ok")
