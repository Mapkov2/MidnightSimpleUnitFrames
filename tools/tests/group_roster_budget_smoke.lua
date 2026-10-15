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
-- reason; never to hide a regression. The original KB limits are for 32-bit Lua.
-- 2026-10-02: keep them and the instruction limits unchanged; use separately
-- measured 64-bit limits for the same baseline/current and identical harness.
-- Lua object sizes differ with pointer width, so a 32-bit KB limit cannot
-- validate a 64-bit interpreter. An empty-table allocation identifies the layout.
-- 2026-10-02 (wave 3, group): Mainline party_join 158k -> 164k (Vanilla's
-- 164k already holds the new 160k). An
-- out-of-combat birth is now built at its own unit write instead of by the
-- next-frame settle (a combat start in between left it blank for the fight), so
-- the joining frame's first build and its once-per-frame catch-up moved from the
-- following settle into the join: Mainline join+settle 154k+41k -> 160k+36k
-- (195k -> 196k), Vanilla 154k+42k -> 160k+37k. Every other case is unchanged.
-- 2026-10-02 (wave 4, W4-C2): the route compiler remembers functions that are
-- no element export, so each frame build stops re-walking every element field
-- for its per-frame closures. Measured: Mainline party_join 161k -> 136k,
-- party_apply 397k -> 288k, raid_build 1863k -> 1502k, raid_apply 1383k -> 1075k;
-- Vanilla 160k -> 135k, 413k -> 307k, 1801k -> 1455k, 1424k -> 1134k. KB and the
-- settle/shift cases unchanged. Those four limits move to the new measurement +2%.
--
-- 2026-10-13: unit-filtered group NameText recovery adds a compiled name
-- follower. Mainline raid_apply: 572.7 -> 583.6 KB (x86), 1069k -> 1056k
-- instructions, 1120 native calls unchanged. Its x86 memory cap is 596 KB
-- (ceil(583.6 * 1.02)); every other limit, including x64, is unchanged.
-- Repeat name notifications allocate no tables/closures (group_name_update).
-- 2026-10-15: GROUP_ROSTER_UPDATE now repaints live raid state after native
-- headers settle, including combat, without GUID reads or event rebinding.
-- Twenty frames add 100 measured native calls; the old path skipped this work.
-- Mainline build/settle/shift: 1485/64/41k -> 1554/133/122k instructions;
-- Vanilla: 1464/65/67k -> 1533/135/148k. Affected caps keep ceil(measured*1.02).
-- Mainline x86 settle allocation: 7.8 -> 10.8KB (12KB cap); other memory caps,
-- including verified PUC Lua5.1 x64, are unchanged. No health/power tick work.
-- group_raid_identity pins final-occupant burst coalescing and secret independence.
-- Cross-review: 40-frame settle baseline -> fixed is Mainline116k ->270k,
-- Vanilla124k ->279k; each adds200 measured native calls (221->421/301->501).
-- Twenty roster events before one combat flush: Mainline1137k ->1317k,
-- Vanilla1792k ->1973k, native2960->3160/4440->4640. Exactly40 paints per burst.
-- Nil-state guards add no native calls and leave those rounded VM counts equal
-- to the pre-guard fix. New case caps are ceil(measured maximum*1.02); existing
-- caps stay unchanged. x86/x64 allocation maxima are measured independently.
-- Runs the real core load graph on the SecureGroupHeader emulator of
-- tools/tests/group_header_world.lua. Plain Lua 5.1, repo root as arg 1.

-- 2026-10-15: freeze native raid roster/layout in combat, retain one identity
-- repaint per burst. Same 40-frame/20-event scenario: Mainline 1317k -> 661k,
-- 3160 -> 200 native calls, 167.5 -> 27.9KB (x86); Vanilla 1973k -> 888k,
-- 4640 -> 1000 calls, 1192.8 -> 290.5KB. Tighten the affected VM/native/x86
-- allocation caps to the new measurements +2%; unchanged routes keep theirs.
-- PUC Lua 5.1 x64: shift 4.1/13.3KB and burst 41.0/403.6KB (Mainline/Vanilla).
local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required")
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")

-- [flavor] = { [case] = { k instructions, KB } }
local BUDGETS = {
    Mainline = {
        party_join = { 139, 220 }, party_settle = { 42, 10 }, party_apply = { 294, 207 }, raid_build = { 1586, 3912 },
        raid_settle = { 136, 12 }, raid_apply = { 1097, 596 }, raid_shift = { 96, 4 },
        raid40_settle = { 276, 10 }, raid40_burst = { 675, 29 },
    },
    Vanilla = {
        party_join = { 138, 272 }, party_settle = { 43, 12 }, party_apply = { 314, 411 }, raid_build = { 1564, 4865 },
        raid_settle = { 138, 18 }, raid_apply = { 1157, 1395 }, raid_shift = { 100, 10 },
        raid40_settle = { 285, 23 }, raid40_burst = { 906, 297 },
    },
}
local MEASURE_ONLY = os.getenv("MSUF_BUDGET_MEASURE") == "1" or arg[3] == "native"

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
-- Native counting runs the same scenarios separately, keeping hook allocations
-- and stack growth out of the original VM/KB measurement.
if arg[3] == "native" then
    local natives = {}
    for _, name in ipairs({ "UnitHealth", "UnitHealthMax", "UnitHealthPercent", "UnitPower", "UnitPowerMax",
        "UnitPowerPercent", "UnitName", "UnitGUID", "UnitGroupRolesAssigned", "GetRaidRosterInfo",
        "UnitIsDeadOrGhost", "UnitIsConnected", "GetNumGroupMembers", "GetNumSubgroupMembers" }) do
        if type(env[name]) == "function" then natives[env[name]] = true end
    end
    for _, name in ipairs({ "SetValue", "SetMinMaxValues", "SetText", "SetFormattedText", "SetTextColor",
        "SetStatusBarColor", "SetStatusBarTexture", "SetVertexColor", "SetColorTexture", "SetTexture",
        "SetPoint", "ClearAllPoints", "SetSize", "SetWidth", "SetHeight", "SetAttribute", "Show", "Hide",
        "RegisterEvent", "RegisterUnitEvent", "UnregisterEvent", "UnregisterAllEvents" }) do
        local fn = h.widgets.Methods[name]
        if type(fn) == "function" then natives[fn] = true end
    end
    h.nativeCounts = {}
    h.nativeTick = function()
        if natives[debug.getinfo(2, "f").func] then h.nativeCalls = h.nativeCalls + 1 end
    end
    h.nativeLimits = flavor == "Mainline" and {
        party_join = 399, party_settle = 71, party_apply = 278, raid_build = 6347,
        raid_settle = 226, raid_apply = 1120, raid_shift = 102, raid40_settle = 430, raid40_burst = 204,
    } or {
        party_join = 439, party_settle = 81, party_apply = 350, raid_build = 6736,
        raid_settle = 267, raid_apply = 1380, raid_shift = 123, raid40_settle = 512, raid40_burst = 1020,
    }
end


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
local function MeasureOnce(fn)
    local ticks = 0
    local function Tick() ticks = ticks + 1 end
    collectgarbage("collect")
    collectgarbage("stop")
    local kb = collectgarbage("count")
    if h.nativeTick then
        h.nativeCalls = 0
        debug.sethook(h.nativeTick, "c")
    else
        debug.sethook(Tick, "", 1000)
    end
    fn()
    debug.sethook()
    kb = collectgarbage("count") - kb
    collectgarbage("restart")
    return ticks, kb
end

-- repeatable: the case leaves the state it found (a settle), so it runs twice
-- and keeps the smaller reading. The full collect before each run can shrink
-- Lua 5.1's string table; regrowing it then lands in whichever run crosses the
-- next power of two, which depends on how many strings the whole tree holds,
-- not on the measured path. A resize happens at most once per pair, so the
-- minimum is the path's own cost.
local function Measure(case, fn, repeatable)
    local ticks, kb = MeasureOnce(fn)
    if repeatable then
        local ticks2, kb2 = MeasureOnce(fn)
        if ticks2 < ticks then ticks = ticks2 end
        if kb2 < kb then kb = kb2 end
    end
    results[#results + 1] = { case = case, k = ticks, kb = kb }
    if h.nativeCounts then
        h.nativeCounts[case] = h.nativeCalls
        Check(h.nativeCalls <= h.nativeLimits[case], case .. ": native-call budget exceeded")
    end
    local budget = (BUDGETS[flavor] or {})[case]
    if budget and not MEASURE_ONLY then
        Check(ticks <= budget[1], string.format("%s: %d k instructions, budget %d k", case, ticks, budget[1]))
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
end, true)
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
-- Warm the unchanged-roster path before measuring its steady-state cost.
-- This keeps one-time VM growth out of the allocation budget; the repeat
-- inside Measure keeps a string-table resize out of it.
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
Measure("raid_settle", function()
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
end, true)
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

-- Forty-member raid and a battleground-sized roster burst in lockdown.
h:RunTimers()
h:SetRaid(40)
h:Event("GROUP_ROSTER_UPDATE"); h:RunTimers()
Check(GF.FrameForUnit("raid40") ~= nil, "forty-member fixture did not build raid40")
Measure("raid40_settle", function()
    h:Event("GROUP_ROSTER_UPDATE"); h:RunTimers()
end, true)
h:EnterCombat()
local refresh, paints = h.UF.RefreshGroupFrameState, 0
h.UF.RefreshGroupFrameState = function(...)
    paints = paints + 1
    return refresh(...)
end
Measure("raid40_burst", function()
    paints = 0
    for i = 1, 20 do
        h.units[1], h.units[40] = h.units[40], h.units[1]
        h:Event("GROUP_ROSTER_UPDATE")
    end
    Check(paints == 0, "BG burst painted before settle")
    h:RunTimers()
    Check(paints == 40, "BG burst did not coalesce to one paint per frame")
end, true)
h.UF.RefreshGroupFrameState = refresh
Check(env.InCombatLockdown() and #h.violations == 0, "40-member combat settle made protected writes")
h:LeaveCombat(); h:RunTimers()

-- Probe after every measurement so calibration does not perturb the fixture heap.
-- 64-bit baseline/current maxima in KB, measured with PUC Lua 5.1 (x64):
-- Mainline: 284.1, 11.9, 262.6, 5103.2, 13.8, 744.7, 32.6.
-- Vanilla: 352.9, 14.0, 519.8, 6319.1, 22.8, 1765.2, 94.7.
-- Each limit is ceil(maximum * 1.02), exactly the original 2% headroom.
local MEMORY_BUDGETS_64 = {
    Mainline = { party_join = 290, party_settle = 13, party_apply = 268, raid_build = 5206,
        raid_settle = 15, raid_apply = 760, raid_shift = 5, raid40_settle = 16, raid40_burst = 42 },
    Vanilla = { party_join = 360, party_settle = 15, party_apply = 531, raid_build = 6446,
        raid_settle = 24, raid_apply = 1801, raid_shift = 14, raid40_settle = 34, raid40_burst = 412 },
}
collectgarbage("collect")
collectgarbage("stop")
local tableBefore = collectgarbage("count")
local tableProbe = {}
local emptyTableBytes = (collectgarbage("count") - tableBefore) * 1024
collectgarbage("restart")
assert(emptyTableBytes == 32 or emptyTableBytes == 64,
    "unmeasured Lua table layout: " .. tostring(emptyTableBytes) .. " bytes")
local wideTables = emptyTableBytes == 64

local summary = {}
for _, result in ipairs(results) do
    local budget = (BUDGETS[flavor] or {})[result.case]
    if budget and not MEASURE_ONLY then
        local memoryBudget = wideTables and MEMORY_BUDGETS_64[flavor][result.case] or budget[2]
        Check(result.kb <= memoryBudget, string.format("%s: %.1f KB allocated, budget %d KB",
            result.case, result.kb, memoryBudget))
    end
    if h.nativeCounts then
        summary[#summary + 1] = string.format("%s %d native calls", result.case, h.nativeCounts[result.case])
    else
        summary[#summary + 1] = string.format("%s %dk/%.1fKB", result.case, result.k, result.kb)
    end
end
print(string.format("group_roster_budget_smoke: ok (%s, %s-bit%s: %s)", flavor,
    wideTables and "64" or "32", MEASURE_ONLY and ", measure only" or "",
    table.concat(summary, ", ")))
