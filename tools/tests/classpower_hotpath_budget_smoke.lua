-- classpower_hotpath_budget_smoke.lua <repoRoot> [print]
--
-- Deterministic cost budgets for the ClassPower controller hot paths, never
-- wall-clock time:
--   * Lua VM instructions per event (count hook, every instruction);
--   * bytes allocated per event, with the collector stopped.
-- The REAL ClassPower stack of each client TOC runs in tools/tests/classpower_world.lua
-- (the stubs of classpower_target_combo_trace_smoke.lua). Covered:
--   * Midnight Rogue: combo point UNIT_POWER_UPDATE (count text off and on) and the Energy
--     UNIT_POWER_FREQUENT tick the controller must drop;
--   * Mists Rogue: target-owned combo points on UNIT_POWER_FREQUENT;
--   * Midnight Death Knight: RUNE_POWER_UPDATE;
--   * Midnight Evoker: Essence on UNIT_POWER_FREQUENT;
--   * Midnight Enhancement Shaman: a Maelstrom Weapon stack change on UNIT_AURA,
--     and aura churn without one;
--   * Midnight Brewmaster Monk: one central Stagger tick.
-- Budgets were frozen on 2026-10-02 from the cost measured before the
-- CP_Controller split, plus 2 % (AGENTS_QUALITY.md §1.2). A restructure may
-- only stay inside them. "print" reports the measured values.
--
-- Plain Lua 5.1, repo root as arg 1.

local repo = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local printOnly = arg[2] == "print"

-- instructions, bytes per operation (8 bytes: below any per-operation table).
-- A Maelstrom Weapon stack change allocated 252 bytes before the split too:
-- the per-call refresh closure (CPAuras.RefreshActive), the deferred
-- update's timer entry and the segmented repaint. 2026-10-03: RefreshActive
-- builds no closure any more (60 bytes on every hidden-payload UNIT_AURA);
-- both Shaman paths are frozen at the new cost plus 2 %: 1984 instructions /
-- 192 bytes and 542 instructions / 0 bytes. Those 192 bytes are the shared
-- fixture's timer entry and RGBA tuple (96 bytes each on 32-bit Lua 5.1).
-- Their native counterparts allocate no Lua tables. Only their measured
-- architecture excess is normalized; the frozen budgets remain unchanged.
local BUDGETS = {
    ["Mainline ROGUE combo UNIT_POWER_UPDATE"] = { 796, 8 },
    ["Mainline ROGUE combo UNIT_POWER_UPDATE, count text on"] = { 859, 8 },
    ["Mainline ROGUE energy UNIT_POWER_FREQUENT"] = { 64, 8 },
    ["Mists ROGUE target combo UNIT_POWER_FREQUENT"] = { 815, 8 },
    ["Mainline DEATHKNIGHT RUNE_POWER_UPDATE"] = { 1026, 8 },
    ["Mainline EVOKER essence UNIT_POWER_FREQUENT"] = { 756, 8 },
    ["Mainline SHAMAN maelstrom UNIT_AURA"] = { 2024, 196 },
    ["Mainline SHAMAN unchanged UNIT_AURA"] = { 553, 8 },
    ["Mainline MONK stagger tick"] = { 230, 8 },
}

local WARMUP, INSTRUCTION_REPS, ALLOCATION_REPS = 40, 200, 2000
local measured = {}

local function Measure(label, operation, nativeFixture)
    assert(BUDGETS[label], "no budget for " .. label)
    for _ = 1, WARMUP do operation() end
    local ticks = 0
    debug.sethook(function() ticks = ticks + 1 end, "", 1)
    for _ = 1, INSTRUCTION_REPS do operation() end
    debug.sethook()
    if nativeFixture then nativeFixture.Begin() end
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, ALLOCATION_REPS do operation() end
    local bytes = (collectgarbage("count") - before) * 1024
    collectgarbage("restart")
    if nativeFixture then bytes = nativeFixture.Finish(label, bytes, ALLOCATION_REPS) end
    measured[#measured + 1] = {
        label = label, instructions = ticks / INSTRUCTION_REPS, bytes = bytes / ALLOCATION_REPS,
    }
end

local World = assert(loadfile(repo .. "/tools/tests/classpower_world.lua"))()
local PT_MANA, PT_ENERGY, PT_COMBO, PT_ESSENCE = World.PT.MANA, World.PT.ENERGY, World.PT.COMBO, World.PT.ESSENCE
local CountSetters, Dispatcher = World.CountSetters, World.Dispatcher
local function Start(toc, class, spec, primary, bars) return World.Start(repo, toc, class, spec, primary, bars) end

-- Calibrate the ACTUAL shared fixture methods, without running addon code.
-- Warm the timer queue and dummy widget before measuring their table sizes.
local function FixtureBytes(operation)
    for _ = 1, WARMUP do operation() end
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, ALLOCATION_REPS do operation() end
    local bytes = (collectgarbage("count") - before) * 1024 / ALLOCATION_REPS
    collectgarbage("restart")
    return bytes
end

local function ShamanNativeFixture(t)
    local timers, methods = C_Timer, t.env.Methods
    local after, setColor = timers.After, methods.SetStatusBarColor
    local dummy = t.env:CreateFrame("StatusBar")
    local function Noop() end
    local timerBytes = FixtureBytes(function() after(0, Noop) t.env:RunTimers() end)
    local colorBytes = FixtureBytes(function() setColor(dummy, 1, 1, 1, 1) end)
    local afterCalls, colorCalls = 0, 0
    return {
        Begin = function()
            afterCalls, colorCalls = 0, 0
            -- Wrap only the allocation pass: instruction ceilings continue to
            -- measure the original fixture, with no accounting overhead.
            timers.After = function(delay, callback)
                afterCalls = afterCalls + 1
                return after(delay, callback)
            end
            methods.SetStatusBarColor = function(widget, r, g, b, a)
                colorCalls = colorCalls + 1
                return setColor(widget, r, g, b, a)
            end
        end,
        Finish = function(label, bytes, reps)
            timers.After, methods.SetStatusBarColor = after, setColor
            local expected = label == "Mainline SHAMAN maelstrom UNIT_AURA" and reps or 0
            assert(afterCalls == expected and colorCalls == expected,
                "Maelstrom native call budget changed: " .. afterCalls .. " timers, " .. colorCalls .. " colors")
            -- One timer entry and one RGBA tuple per changed event; none on
            -- unchanged events. Extra addon tables/closures are never deducted.
            return bytes - afterCalls * (timerBytes - 96) - colorCalls * (colorBytes - 96)
        end,
    }
end

--------------------------------------------------------------------------
-- Scenarios
--------------------------------------------------------------------------

do
    local t = Start("Mainline", "ROGUE", 1, PT_ENERGY)
    assert(t.CP.visible and t.CP.powerType == PT_COMBO, "Midnight Rogue did not route combo points")
    local combo = 0
    local update = Dispatcher(t, "UNIT_POWER_UPDATE", "player", "COMBO_POINTS")
    Measure("Mainline ROGUE combo UNIT_POWER_UPDATE", function()
        combo = combo % 5 + 1
        t.S.combo = combo
        update()
    end)
    Measure("Mainline ROGUE energy UNIT_POWER_FREQUENT", Dispatcher(t, "UNIT_POWER_FREQUENT", "player", "ENERGY"))
end

do
    -- The count text is off by default (no FontString exists); with it on the
    -- update also paints the count.
    local t = Start("Mainline", "ROGUE", 1, PT_ENERGY, { classPowerShowText = true })
    assert(t.CP.text, "Class Resource text on created no count FontString")
    local combo = 0
    local update = Dispatcher(t, "UNIT_POWER_UPDATE", "player", "COMBO_POINTS")
    Measure("Mainline ROGUE combo UNIT_POWER_UPDATE, count text on", function()
        combo = combo % 5 + 1
        t.S.combo = combo
        update()
    end)
end

do
    local t = Start("Mists", "ROGUE", 1, PT_ENERGY)
    assert(t.CP.visible and t.CP.powerType == PT_COMBO, "Mists Rogue did not route combo points")
    local combo = 0
    local update = Dispatcher(t, "UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
    Measure("Mists ROGUE target combo UNIT_POWER_FREQUENT", function()
        combo = combo % 5 + 1
        t.S.combo = combo
        update()
    end)
end

do
    local t = Start("Mainline", "DEATHKNIGHT", 1, 6)
    assert(t.CP.visible, "Midnight Death Knight did not route runes")
    local rune = 0
    local onEvent, frame = t.onEvent, t.eventFrame
    Measure("Mainline DEATHKNIGHT RUNE_POWER_UPDATE", function()
        rune = rune % 6 + 1
        onEvent(frame, "RUNE_POWER_UPDATE", rune, false)
    end)
end

do
    local t = Start("Mainline", "EVOKER", 1, PT_MANA)
    assert(t.CP.visible and t.CP.powerType == PT_ESSENCE, "Midnight Evoker did not route Essence")
    Measure("Mainline EVOKER essence UNIT_POWER_FREQUENT", Dispatcher(t, "UNIT_POWER_FREQUENT", "player", "ESSENCE"))
end

do
    local t = Start("Mainline", "SHAMAN", 2, PT_MANA)
    assert(t.CP.visible and t.CP.isAuraPower, "Midnight Enhancement did not route Maelstrom Weapon")
    local nativeFixture = ShamanNativeFixture(t)
    local stacks = 0
    local update = Dispatcher(t, "UNIT_AURA", "player", { isFullUpdate = true })
    Measure("Mainline SHAMAN maelstrom UNIT_AURA", function()
        stacks = stacks % 10 + 1
        t.S.auraStacks = stacks
        update()
        t.env:RunTimers()
    end, nativeFixture)
    -- Aura churn without a stack change: the cache compares the new aura's
    -- fields and repaints nothing.
    local variant = 0
    Measure("Mainline SHAMAN unchanged UNIT_AURA", function()
        variant = 1 - variant
        t.S.auraVariant = variant
        update()
        t.env:RunTimers()
    end, nativeFixture)
    local function Fire() update() t.env:RunTimers() end
    t.S.auraVariant = 1 - variant
    local unchanged = CountSetters(t, Fire)
    t.S.auraStacks = stacks % 10 + 1
    local changed = CountSetters(t, Fire)
    assert(unchanged == 0 and changed > 0, "Maelstrom Weapon repaint does not follow the stack count")
end

do
    local t = Start("Mainline", "MONK", 1, PT_ENERGY)
    assert(t.CP.visible, "Midnight Brewmaster did not route Stagger")
    local tickFrame
    for _, frame in ipairs(t.env.frames or {}) do
        if frame.scripts and frame.scripts.OnUpdate and frame ~= t.eventFrame then tickFrame = frame end
    end
    assert(tickFrame, "Brewmaster has no running central tick")
    local onUpdate = tickFrame.scripts.OnUpdate
    Measure("Mainline MONK stagger tick", function() onUpdate(tickFrame, 0.05) end)
    -- The central tick runs its mode at 30 Hz at most.
    t.S.stagger = 650
    local early = CountSetters(t, function() onUpdate(tickFrame, 0.02) end)
    local due = CountSetters(t, function() onUpdate(tickFrame, 0.02) end)
    assert(early == 0 and due > 0, "the central tick does not throttle Stagger to 30 Hz")
    -- Leaving Brewmaster stops the central tick: no OnUpdate is left running.
    t.S.spec = 3
    t.CP.RefreshPublic()
    t.env:RunTimers()
    assert(tickFrame.scripts.OnUpdate == nil and not tickFrame.shown, "the central tick outlived Stagger")
end

--------------------------------------------------------------------------
-- Verdict
--------------------------------------------------------------------------

local failures = {}
for _, row in ipairs(measured) do
    local budget = BUDGETS[row.label]
    local line = ("%-48s %8.1f instructions (budget %d)  %7.1f bytes (budget %d)"):format(
        row.label, row.instructions, budget[1], row.bytes, budget[2])
    if printOnly then
        print(line)
    elseif row.instructions > budget[1] or row.bytes > budget[2] then
        failures[#failures + 1] = line
    end
end
if printOnly then return end
if #failures > 0 then
    error("classpower_hotpath_budget_smoke: over budget:\n  " .. table.concat(failures, "\n  "), 0)
end
print(("classpower_hotpath_budget_smoke: ok (%d hot paths within budget)"):format(#measured))
