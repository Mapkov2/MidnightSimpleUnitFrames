-- uf_dispatch_budget_smoke.lua <repoRoot> <flavor>
--
-- Hot-path budget of the unit-frame engine's event dispatch (quality program
-- net N2, "engine dispatch: health, power, text"). Ten secure raid children
-- built by the real core load graph on the SecureGroupHeader emulator of
-- tools/tests/group_header_world.lua receive 100 rounds of each unit event
-- through their own OnEvent script, the compiled routes of MSUF_UF_Core.lua.
-- Two deterministic measures, never wall-clock time: Lua VM instructions
-- (count hook, thousands) and kilobytes allocated with the collector stopped.
--
-- Budgets (2026-10-02, 32-bit PUC Lua 5.1, 1000 dispatches each): the base
-- 4e83620c and the current tree measure the same, UNIT_HEALTH 95k / 0.12 KB,
-- UNIT_MAXHEALTH 1391k / 2.35 KB, UNIT_POWER_UPDATE 120k / 0.05 KB,
-- UNIT_NAME_UPDATE 927k / 0.05 KB, UNIT_FLAGS 1216k / 2.63 KB, on Mainline and
-- Vanilla. Each instruction limit sits 2% above. KB limits are for 32-bit
-- Lua; on any interpreter the value events (health, power) must stay
-- allocation-free (one table per dispatch would cost 16 KB or more).
-- Since 2026-10-02 the KB figure is the smaller of two identical windows:
-- the 2.35 / 2.63 KB above were a one-off VM table growth, and every event
-- now measures 0.00 KB.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required")
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")

-- [event] = { k instructions, KB (32-bit) }
local BUDGETS = {
    UNIT_HEALTH = { 97, 1 },
    UNIT_MAXHEALTH = { 1419, 3 },
    UNIT_POWER_UPDATE = { 123, 1 },
    UNIT_NAME_UPDATE = { 946, 1 },
    UNIT_FLAGS = { 1241, 3 },
}
local EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_NAME_UPDATE", "UNIT_FLAGS" }
local VALUE_EVENTS = { UNIT_HEALTH = true, UNIT_POWER_UPDATE = true }
local MEASURE_ONLY = os.getenv("MSUF_BUDGET_MEASURE") == "1"

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

-- Plain, varying unit values: every dispatch reads a new health value. Every
-- member is a healer, so the raid frames carry their mana bar and its routes.
local tick = 0
local h = Harness.New(root, flavor, { beforeBoot = function(harness)
    local env = harness.env
    env.MAX_BOSS_FRAMES = 5
    env.UnitHealth = function() tick = tick + 1; return 50000 + (tick % 7) * 1000 end
    env.UnitHealthMax = function() return 100000 end
    env.UnitHealthPercent = function() return 0.5 + (tick % 7) / 100 end
    env.UnitPower = function() return 30 + tick % 5 end
    env.UnitPowerMax = function() return 100 end
    env.UnitPowerPercent = function() return 0.3 end
    env.UnitPowerType = function() return 0, "MANA" end
    env.UnitGroupRolesAssigned = function() return "HEALER" end
    env.UnitIsDeadOrGhost = function() return false end
    env.UnitIsDead = function() return false end
    env.UnitIsGhost = function() return false end
    env.UnitGetTotalAbsorbs = function() return 0 end
    env.UnitGetIncomingHeals = function() return 0 end
    env.UnitGetTotalHealAbsorbs = function() return 0 end
end })
local GF = h.GF

local raid = GF.GetConf("raid")
raid.enabled = true
GF.RefreshHeaderLayout()
h:SetRaid(10)
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
local frames = {}
for index = 1, 10 do
    local frame = GF.FrameForUnit("raid" .. index)
    Check(frame and frame._msufCoreVisible == true and frame._msufCoreSpecEnabled == true
        and type(frame.scripts.OnEvent) == "function", "raid" .. index .. " is not a live group frame")
    Check(frame.UNIT_HEALTH ~= nil and frame.UNIT_POWER_UPDATE ~= nil, "raid" .. index .. " compiled no value routes")
    frames[index] = frame
end

local function Dispatch(event)
    for index = 1, #frames do
        local frame = frames[index]
        frame.scripts.OnEvent(frame, event, "raid" .. index)
    end
end

local results = {}
local function Measure(event)
    -- Warm route caches and coalescers, then drain what they queued.
    for _ = 1, 3 do Dispatch(event) end
    h:RunTimers()
    local ticks = 0
    collectgarbage("collect")
    collectgarbage("stop")
    local kb = collectgarbage("count")
    debug.sethook(function() ticks = ticks + 1 end, "", 1000)
    for _ = 1, 100 do Dispatch(event) end
    debug.sethook()
    kb = collectgarbage("count") - kb
    -- A one-off growth of a shared VM structure (the interned string table
    -- doubles once the string count reaches its size) lands in whichever
    -- window crosses that size, so it moves between events whenever the load
    -- graph interns a few more strings (2026-10-02: new locale keys moved a
    -- 2.5 KB step from UNIT_FLAGS to UNIT_NAME_UPDATE). It cannot repeat in a
    -- second identical window; a per-dispatch allocation does. Count the
    -- smaller window.
    local second = collectgarbage("count")
    for _ = 1, 100 do Dispatch(event) end
    second = collectgarbage("count") - second
    if second < kb then kb = second end
    collectgarbage("restart")
    h:RunTimers()
    results[#results + 1] = { event = event, k = ticks, kb = kb }
end
for _, event in ipairs(EVENTS) do Measure(event) end

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
    local budget = BUDGETS[result.event]
    if not MEASURE_ONLY then
        Check(result.k <= budget[1], string.format("%s: %d k instructions per 1000 dispatches, budget %d k",
            result.event, result.k, budget[1]))
        if not wideTables then
            Check(result.kb <= budget[2], string.format("%s: %.2f KB per 1000 dispatches, budget %d KB",
                result.event, result.kb, budget[2]))
        end
        if VALUE_EVENTS[result.event] then
            Check(result.kb < 1, string.format("%s allocates on the value path: %.2f KB per 1000 dispatches",
                result.event, result.kb))
        end
    end
    summary[#summary + 1] = string.format("%s %dk/%.2fKB", result.event, result.k, result.kb)
end
print(string.format("uf_dispatch_budget_smoke: ok (%s, %s-bit%s: %s)", flavor, wideTables and "64" or "32",
    MEASURE_ONLY and ", measure only" or "", table.concat(summary, ", ")))
