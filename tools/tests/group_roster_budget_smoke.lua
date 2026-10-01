-- group_roster_budget_smoke.lua <repoRoot> <flavor>
--
-- Performance budgets for the group runtime's cold-but-frequent paths, with two
-- deterministic measures (never wall-clock time): Lua VM instructions (count
-- hook, in thousands) and kilobytes allocated with the collector stopped.
--   * GF.EnsureDB, the defensive DB boundary every group path crosses: a stable
--     call scans nothing and allocates nothing (port of Retail's
--     group_db_ensure_hotpath smoke), a real mutation repairs exactly once and
--     never in combat;
--   * the roster settle: an unchanged GROUP_ROSTER_UPDATE on a 5-member party
--     and a 20-member raid, and a member joining (header birth plus settle);
--   * the group apply: a full visual refresh of every party and raid frame;
--   * a unit shift in combat (two raid members swap slots).
-- Budgets were measured on the 2026-10-01 baseline (1908d740) and sit 2% above
-- the larger of baseline and current. Raise one only with the measurement and the
-- reason; never to hide a regression.
--
-- Runs the real core load graph on the SecureGroupHeader emulator of
-- tools/tests/group_header_world.lua. Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required")
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")

-- [flavor] = { [case] = { k instructions, KB } }
local BUDGETS = {
    Mainline = {
        party_join = { 158, 220 }, party_settle = { 42, 10 }, party_apply = { 401, 207 }, raid_build = { 1871, 3912 },
        raid_settle = { 64, 8 }, raid_apply = { 1397, 582 }, raid_shift = { 84, 26 },
    },
    Vanilla = {
        party_join = { 164, 272 }, party_settle = { 43, 12 }, party_apply = { 464, 411 }, raid_build = { 1946, 4865 },
        raid_settle = { 66, 18 }, raid_apply = { 1623, 1395 }, raid_shift = { 108, 75 },
    },
}
local MEASURE_ONLY = os.getenv("MSUF_BUDGET_MEASURE") == "1"

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

local pairScans = 0
local h = Harness.New(root, flavor, { beforeBoot = function(harness)
    local realPairs = pairs
    harness.env.pairs = function(t)
        pairScans = pairScans + 1
        return realPairs(t)
    end
end })
local GF, env = h.GF, h.env

---------------------------------------------------------------------------
-- GF.EnsureDB stays a cold path
---------------------------------------------------------------------------
GF.EnsureDB()
local db = env.MSUF_DB
Check(type(db) == "table" and type(db.gf_party) == "table" and type(db.gf_raid) == "table"
    and type(db.gf_mythicraid) == "table" and type(db.gf_priority) == "table",
    "the first EnsureDB did not materialize every group scope")
pairScans = 0
for _ = 1, 100 do GF.EnsureDB() end
Check(pairScans == 0, "stable EnsureDB calls rescanned defaults or migrations")
collectgarbage("collect")
collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, 10000 do GF.EnsureDB() end
local after = collectgarbage("count")
collectgarbage("restart")
Check(after == before, "stable EnsureDB calls allocated Lua memory")
db.gf_party.width = nil
GF.InvalidateConfCache()
h.widgets:SetCombat(true)
pairScans = 0
GF.EnsureDB()
Check(db.gf_party.width == nil and pairScans == 0, "an in-place Group DB repair ran in combat")
h.widgets:SetCombat(false)
GF.EnsureDB()
Check(db.gf_party.width == GF.PARTY_DEFAULTS.width, "an invalidated in-place mutation was not repaired")
pairScans = 0
GF.EnsureDB()
Check(pairScans == 0, "the repaired DB did not return to the scan-free path")

---------------------------------------------------------------------------
-- Measurements
---------------------------------------------------------------------------
local results = {}
local function Measure(case, fn)
    local ticks = 0
    local function Tick() ticks = ticks + 1 end
    collectgarbage("collect")
    collectgarbage("stop")
    local kb = collectgarbage("count")
    debug.sethook(Tick, "", 1000)
    fn()
    debug.sethook()
    kb = collectgarbage("count") - kb
    collectgarbage("restart")
    results[#results + 1] = { case = case, k = ticks, kb = kb }
    local budget = (BUDGETS[flavor] or {})[case]
    if budget and not MEASURE_ONLY then
        Check(ticks <= budget[1], string.format("%s: %d k instructions, budget %d k", case, ticks, budget[1]))
        Check(kb <= budget[2], string.format("%s: %.1f KB allocated, budget %d KB", case, kb, budget[2]))
    end
end

local party = GF.GetConf("party")
party.enabled, party.showPlayer = true, true
local raid = GF.GetConf("raid")
raid.enabled = true
GF.RefreshHeaderLayout()

-- Party of five: built once, then measured.
h:SetRoster({ "player", "party1", "party2", "party3" })
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
local partyHeader = GF.headers.party
Check(partyHeader and #h:Children(partyHeader) == 4, "the party header did not build four children")
Measure("party_join", function()
    h:SetRoster({ "player", "party1", "party2", "party3", "party4" })
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
end)
Check(#h:Children(partyHeader) == 5 and GF.FrameForUnit("party4") ~= nil, "the joining member was not styled")
Measure("party_settle", function()
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
end)
Measure("party_apply", function()
    GF.RefreshVisuals(nil, GF.DIRTY_ALL)
end)

-- Raid of twenty.
Measure("raid_build", function()
    h:SetRaid(20)
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
end)
local raidChildren = 0
GF.ForEachHeader("raid", function(header) raidChildren = raidChildren + #h:Children(header) end)
Check(raidChildren >= 20 and GF.FrameForUnit("raid20") ~= nil, "the raid did not build twenty styled frames")
Measure("raid_settle", function()
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
end)
Measure("raid_apply", function()
    GF.RefreshVisuals(nil, GF.DIRTY_ALL)
end)

-- Two raid members swap slots in combat: the header rewrites both units.
h:EnterCombat()
local units = h.units
Measure("raid_shift", function()
    units[3], units[4] = units[4], units[3]
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
end)
h:LeaveCombat()
Check(#h.violations == 0, "protected write in lockdown:\n" .. tostring(h.violations[1]))

local summary = {}
for _, result in ipairs(results) do
    summary[#summary + 1] = string.format("%s %dk/%.1fKB", result.case, result.k, result.kb)
end
print(string.format("group_roster_budget_smoke: ok (%s%s: %s)", flavor, MEASURE_ONLY and ", measure only" or "",
    table.concat(summary, ", ")))
