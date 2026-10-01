-- castbar_hotpath_budget_smoke.lua <repoRoot> [print]
--
-- Deterministic cost budgets for the castbar hot paths, never wall-clock time:
--   * Lua VM instructions per operation (count hook, every instruction);
--   * bytes allocated per operation, with the collector stopped.
-- The real stack runs in tools/tests/castbar_world.lua (Mists TOC order, Lua
-- fill: no Classic client has duration objects). Covered:
--   * the castbar manager tick for one target cast (per rendered frame);
--   * target, boss and arena driver events: START, DELAYED, the active-cast
--     UNIT_HEALTH death signal and the pool's UNIT_FLAGS hook;
--   * the pool lifecycle: a boss encounter engage pass (five bars plus the
--     prewarm) and an arena opponent update.
-- Budgets were frozen on 2026-10-01 from the measured cost before the Boss and
-- Arena castbars were merged into one module, plus 2 % (AGENTS_QUALITY.md §1.2).
-- A restructure may only stay inside them. "print" reports the measured values.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local printOnly = arg[2] == "print"
local World = assert(loadfile(root .. "/tools/tests/castbar_world.lua"))()

-- instructions, bytes per operation (8 bytes: below any per-operation table)
local BUDGETS = {
    ["manager tick: target cast"] = { 181, 8 },
    ["target START"] = { 2176, 8 },
    ["target DELAYED"] = { 2040, 8 },
    ["boss1 START"] = { 2279, 8 },
    ["boss1 UNIT_HEALTH"] = { 109, 8 },
    ["boss1 UNIT_FLAGS"] = { 202, 8 },
    ["arena1 START"] = { 2302, 8 },
    ["arena1 UNIT_HEALTH"] = { 109, 8 },
    ["arena1 UNIT_FLAGS"] = { 202, 8 },
    ["boss encounter engage pass"] = { 6120, 8 },
    ["arena opponent update"] = { 2075, 8 },
}

-- Instructions are averaged over 240 operations (a multiple of the manager's
-- heavy-tick cadence). Bytes are averaged over 2,000 more with the collector
-- stopped, after a warm-up: a one-off table or string-table resize amortizes
-- away, a per-operation allocation does not. Every path here is allocation-free,
-- so the byte budgets sit just above zero.
local WARMUP, INSTRUCTION_REPS, ALLOCATION_REPS = 60, 240, 2000
local measured = {}

local function Measure(label, setup, operation)
    assert(BUDGETS[label], "no budget for " .. label)
    if setup then setup() end
    for _ = 1, WARMUP do operation() end
    local ticks = 0
    debug.sethook(function() ticks = ticks + 1 end, "", 1)
    for _ = 1, INSTRUCTION_REPS do operation() end
    debug.sethook()
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, ALLOCATION_REPS do operation() end
    local bytes = (collectgarbage("count") - before) * 1024
    collectgarbage("restart")
    measured[#measured + 1] = {
        label = label, instructions = ticks / INSTRUCTION_REPS, bytes = bytes / ALLOCATION_REPS,
    }
end

local world = World.New(root, "timer", { pools = true })
world.exists.boss2, world.exists.boss3, world.exists.boss4, world.exists.boss5 = true, true, true, true
_G.MSUF_ApplyBossCastbarsEnabled()
_G.MSUF_ApplyArenaCastbarsEnabled()

local function LifecycleFrame(event)
    for index = 1, #world.frames do
        local frame = world.frames[index]
        if frame.events[event] and frame.scripts.OnEvent and not frame.unit then return frame end
    end
    error("no lifecycle frame listens to " .. event)
end

local scheduler = world.ns.Scheduler
local function FlushNextFrame()
    local onUpdate = scheduler.frame.scripts.OnUpdate
    if onUpdate then onUpdate(scheduler.frame, World.STEP) end
end

-- Manager tick: one target Lua-fill cast, one rendered frame per operation.
local target = world:Driver("target")
local manager = assert(_G.MSUF_CastbarManager, "castbar manager missing")
Measure("manager tick: target cast", function()
    world:StartCast("target", "Fireball", 600, 7)
    world:Fire(target, "UNIT_SPELLCAST_START")
end, function()
    world.clock = world.clock + World.STEP
    manager.scripts.OnUpdate(manager, World.STEP)
end)

Measure("target START", nil, function() world:Fire(target, "UNIT_SPELLCAST_START") end)
Measure("target DELAYED", nil, function() world:Fire(target, "UNIT_SPELLCAST_DELAYED") end)

for _, unit in ipairs({ "boss1", "arena1" }) do
    local pool = unit == "boss1" and _G.MSUF_BossCastbars or _G.MSUF_ArenaCastbars
    local bar = world:PoolCastbar(pool and pool[1])
    Measure(unit .. " START", function()
        world:StartCast(unit, "Shadow Bolt", 600, 9)
    end, function() world:Fire(bar, "UNIT_SPELLCAST_START") end)
    assert(bar.MSUF_castActive == true and bar.events.UNIT_HEALTH == true, unit .. ": the cast is not active")
    Measure(unit .. " UNIT_HEALTH", nil, function() world:Fire(bar, "UNIT_HEALTH") end)
    Measure(unit .. " UNIT_FLAGS", nil, function() world:Fire(bar, "UNIT_FLAGS") end)
    assert(bar.MSUF_castActive == true, unit .. ": a living unit's flags stopped the cast")
end

-- Boss encounter engage: the lifecycle event queues one pool pass and the
-- prewarm; the next rendered frame runs the pass.
local bossLifecycle = LifecycleFrame("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
Measure("boss encounter engage pass", nil, function()
    bossLifecycle.scripts.OnEvent(bossLifecycle, "INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    FlushNextFrame()
    FlushNextFrame()
end)

local arenaLifecycle = LifecycleFrame("ARENA_OPPONENT_UPDATE")
Measure("arena opponent update", nil, function()
    arenaLifecycle.scripts.OnEvent(arenaLifecycle, "ARENA_OPPONENT_UPDATE", "arena1", "seen")
end)

local failures = {}
for _, entry in ipairs(measured) do
    local budget = BUDGETS[entry.label]
    local line = string.format("%-28s %8.1f instructions %8.1f bytes  (budget %d / %d)",
        entry.label, entry.instructions, entry.bytes, budget[1], budget[2])
    if printOnly then
        print(line)
    elseif entry.instructions > budget[1] or entry.bytes > budget[2] then
        failures[#failures + 1] = line
    end
end
if printOnly then return end
if #failures > 0 then
    error("castbar hot path over budget:\n  " .. table.concat(failures, "\n  "), 0)
end
print(string.format("castbar_hotpath_budget_smoke: ok (%d operations within budget)", #measured))
