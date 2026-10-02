-- classpower_mists_embers_smoke.lua <repoRoot>
--
-- Mists Destruction Burning Embers. Blizzard's Mists ShardBar.lua
-- (BurningEmbersBarMixin:Update) counts embers as
--   floor(UnitPowerMax("player", BurningEmbers, true) / MAX_POWER_PER_EMBER)
-- with MAX_POWER_PER_EMBER = 10, and fills each ember from the unmodified
-- power. MSUF already distrusts the client display modifier for embers
-- (Game/Mists/ClassPower.lua uses the fixed scale 10); the ember COUNT must
-- come from the same unmodified maximum, never from the modified one.
--
-- Runs the real Mists ClassPower stack (tools/tests/classpower_world.lua).
-- Plain Lua 5.1, repo root as arg 1.

local repo = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(repo .. "/tools/tests/classpower_world.lua"))()
local PT = World.PT
local PT_BURNING_EMBERS = 14

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
end

-- rawMax: the unmodified maximum (10 per ember). The modified maximum is the
-- raw value here: the client's modifier for embers is not trusted.
local function Start(rawMax, rawPower)
    return World.Start(repo, "Mists", "WARLOCK", 3, PT.MANA, nil, { beforeLoad = function(_, S)
        local nativeMax, nativePower = UnitPowerMax, UnitPower
        UnitPowerMax = function(unit, powerType, unmodified)
            if powerType == PT_BURNING_EMBERS then return rawMax end
            return nativeMax(unit, powerType, unmodified)
        end
        UnitPower = function(unit, powerType, unmodified)
            if powerType == PT_BURNING_EMBERS then
                if unmodified then return rawPower end
                return math.floor(rawPower / 10)
            end
            return nativePower(unit, powerType, unmodified)
        end
    end })
end

for _, case in ipairs({ { raw = 30, embers = 3 }, { raw = 40, embers = 4 } }) do
    local t = Start(case.raw, 25)
    local CP = t.CP
    Check(CP.visible and CP.powerType == PT_BURNING_EMBERS, "Mists Destruction did not route Burning Embers")
    Check(CP.currentMax == case.embers, ("%d unmodified ember power shows %s embers, Blizzard shows %d")
        :format(case.raw, tostring(CP.currentMax), case.embers))
    -- 25 raw power: two full embers and half of the third.
    Check(CP.bars[1].value == 1 and CP.bars[2].value == 1 and CP.bars[3].value == 0.5,
        "the embers do not fill from the unmodified power")
end

-- Shard prediction on Mists Destruction. The two cast-time ember spells keep
-- their Midnight IDs on Mists (Blizzard_TalentUI/Mists SPEC_SPELLS_DISPLAY[267]
-- and Mists SpellBookFrame.lua SPEC_CORE_ABILITY_DISPLAY[267] list Incinerate
-- 29722 and Chaos Bolt 116858). Only the sign of a WL_SHARD_DELTAS entry is
-- read (the "*" marker), never its size, so the shared table marks them right.
do
    local t = Start(30, 20)
    local CP = t.CP
    MSUF_DB.bars.classPowerShowText = true
    CP.RefreshPublic()
    t.env:RunTimers()
    for _, spellID in ipairs({ 29722, 116858 }) do
        t.onEvent(t.eventFrame, "UNIT_SPELLCAST_START", "player", "Cast-1", spellID)
        Check(CP.text and CP.text.text == "2*", ("Mists Destruction cast %d shows no prediction marker (text %s)")
            :format(spellID, tostring(CP.text and CP.text.text)))
        t.onEvent(t.eventFrame, "UNIT_SPELLCAST_STOP", "player", "Cast-1", spellID)
        Check(CP.wlPredDelta == 0 and CP.text.text == 2, "the Mists ember prediction outlived its cast")
    end
end

if #failures > 0 then
    error("classpower_mists_embers_smoke:\n  " .. table.concat(failures, "\n  "), 0)
end
print("classpower_mists_embers_smoke: ok (ember count and fill from the unmodified maximum, Destruction prediction)")
