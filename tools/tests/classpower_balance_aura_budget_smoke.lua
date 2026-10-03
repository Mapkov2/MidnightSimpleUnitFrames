-- classpower_balance_aura_budget_smoke.lua <repoRoot>
--
-- Native aura queries per Balance Druid UNIT_AURA (ClassPower/MSUF_CP_BalanceDruid.lua).
-- The Balance runtime tracks six Eclipse auras. Every C_UnitAuras getter call
-- it makes on a UNIT_AURA is a native call, so they are counted, not timed:
--   * a full update (or a restricted payload) rebuilds the six from the client;
--   * an empty incremental update only refreshes the eclipse colour.
-- The eclipse refresh after a rebuild reuses the rebuild's answers, and an
-- absent eclipse costs one query per getter (the controller's getter already
-- asked GetPlayerAuraBySpellID). Before wave 4 the same events cost 30, 30, 15
-- and 15 queries; the early-removal fix (the controller no longer caches
-- Eclipse auras) briefly raised them to 31, 36, 18 and 18.
-- The eclipse colour is checked too, so a runtime that stopped looking at the
-- auras cannot pass on a low count.
--
-- Runs the real ClassPower stack (tools/tests/classpower_world.lua).
-- Plain Lua 5.1, repo root as arg 1.

local repo = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(repo .. "/tools/tests/classpower_world.lua"))()

local SOLAR = 1233346
local BUDGETS = {
    ["full update, Solar present"] = 11,
    ["full update, no eclipse"] = 12,
    ["empty incremental update, Solar present"] = 10,
    ["empty incremental update, no eclipse"] = 12,
}

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
end

local solarUntil
local queries = 0
local aura
local t = World.Start(repo, "Mainline", "DRUID", 1, 8, nil, { beforeLoad = function()
    local function Answer(spellID)
        queries = queries + 1
        if spellID == SOLAR and solarUntil then
            aura = aura or { spellId = spellID, auraInstanceID = 77, duration = 15 }
            aura.expirationTime = solarUntil
            return aura
        end
        return nil
    end
    C_UnitAuras.GetPlayerAuraBySpellID = Answer
    C_UnitAuras.GetUnitAuraBySpellID = function(_, spellID) return Answer(spellID) end
    C_UnitAuras.GetAuraDataByAuraInstanceID = function() queries = queries + 1 return nil end
    C_UnitAuras.GetUnitAuras = function() queries = queries + 1 return {} end
end })

local playerFrame = MSUF_NS.UF.GetFrame("player")
local bar = CreateFrame("StatusBar", nil, playerFrame)
playerFrame.targetPowerBar = bar
bar:SetStatusBarColor(0.3, 0.52, 0.9, 1)
bar._msufR, bar._msufG, bar._msufB, bar._msufA = 0.3, 0.52, 0.9, 1

local balanceFrame
for _, frame in ipairs(t.env.frames) do
    if frame ~= t.eventFrame and frame.events and frame.events.UNIT_AURA and frame.events.UPDATE_SHAPESHIFT_FORM then
        balanceFrame = frame
    end
end
assert(balanceFrame, "the Balance runtime did not bind its events")

local EMPTY = { addedAuras = {}, updatedAuraInstanceIDs = {}, removedAuraInstanceIDs = {} }
local function Measure(label, payload)
    queries = 0
    balanceFrame.scripts.OnEvent(balanceFrame, "UNIT_AURA", "player", payload)
    t.env:RunTimers()
    Check(queries <= BUDGETS[label], ("%s: %d aura queries (budget %d)"):format(label, queries, BUDGETS[label]))
    return queries
end

local function Solar() return bar.color and bar.color[1] == 0.82 and bar.color[3] == 0.25 end

solarUntil = GetTime() + 15
Measure("full update, Solar present", { isFullUpdate = true })
local measured = {}
measured[1] = Measure("full update, Solar present", { isFullUpdate = true })
Check(Solar(), "a Solar Eclipse did not colour the Player Power bar")
measured[2] = Measure("empty incremental update, Solar present", EMPTY)
Check(Solar(), "an empty aura update dropped the Solar Eclipse colour")
solarUntil = nil
measured[3] = Measure("full update, no eclipse", { isFullUpdate = true })
Check(not Solar(), "the eclipse colour outlived the eclipse")
measured[4] = Measure("empty incremental update, no eclipse", EMPTY)
-- A restricted payload takes the rebuild path too.
Measure("full update, no eclipse", { isFullUpdate = { __secret = true } })

if #failures > 0 then
    error("classpower_balance_aura_budget_smoke:\n  " .. table.concat(failures, "\n  "), 0)
end
print(("classpower_balance_aura_budget_smoke: ok (aura queries per UNIT_AURA: full %d/%d, empty %d/%d)")
    :format(measured[1], measured[3], measured[2], measured[4]))
