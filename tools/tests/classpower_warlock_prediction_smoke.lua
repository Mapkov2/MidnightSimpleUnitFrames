-- classpower_warlock_prediction_smoke.lua <repoRoot>
--
-- Warlock shard prediction ("3*" while a shard generator casts) is driven by
-- UNIT_SPELLCAST_START. The segmented painter predicts for Affliction and
-- Demonology (CPConst.WL_SHARD_DELTAS[1] and [2]), so the lite event bindings
-- (the default) must bind the cast events for a Warlock's segmented shards,
-- not only for Destruction's fractional ones, and never for other classes.
--
-- Runs the real ClassPower stack (tools/tests/classpower_world.lua).
-- Plain Lua 5.1, repo root as arg 1.

local repo = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(repo .. "/tools/tests/classpower_world.lua"))()
local PT = World.PT

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
end

local SHADOW_BOLT, DEMONBOLT, INCINERATE = 686, 264178, 29722

local function Cast(t, event, spellID)
    t.onEvent(t.eventFrame, event, "player", "Cast-1", spellID)
end

for _, case in ipairs({
    { spec = 1, name = "Affliction", spell = SHADOW_BOLT, predicted = "3*" },
    { spec = 2, name = "Demonology", spell = DEMONBOLT, predicted = "3*" },
    { spec = 3, name = "Destruction", spell = INCINERATE, predicted = "3*" },
}) do
    local t = World.Start(repo, "Mainline", "WARLOCK", case.spec, PT.MANA, { classPowerShowText = true })
    local events, CP = t.eventFrame.events, t.CP
    Check(CP.visible and CP.powerType == PT.SHARDS, case.name .. " did not route soul shards")
    Check(events.UNIT_SPELLCAST_START and events.UNIT_SPELLCAST_STOP and events.UNIT_SPELLCAST_SUCCEEDED,
        case.name .. ": the lite bindings miss the cast events shard prediction needs")
    Cast(t, "UNIT_SPELLCAST_START", case.spell)
    Check(CP.wlPredDelta ~= 0 and CP.text and CP.text.text == case.predicted,
        case.name .. ": a shard generator cast shows no prediction (text " .. tostring(CP.text and CP.text.text) .. ")")
    Cast(t, "UNIT_SPELLCAST_SUCCEEDED", case.spell)
    Check(CP.wlPredDelta == 0, case.name .. ": the prediction outlived the cast")
end

do
    local t = World.Start(repo, "Mainline", "ROGUE", 1, PT.ENERGY)
    Check(not t.eventFrame.events.UNIT_SPELLCAST_START, "a Rogue binds the Warlock cast events")
end

if #failures > 0 then
    error("classpower_warlock_prediction_smoke:\n  " .. table.concat(failures, "\n  "), 0)
end
print("classpower_warlock_prediction_smoke: ok (Affliction, Demonology, Destruction, Rogue)")
