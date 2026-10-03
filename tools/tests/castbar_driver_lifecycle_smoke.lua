-- castbar_driver_lifecycle_smoke.lua <repoRoot>
--
-- Drives the real target/focus castbar driver through the real Kernel
-- scheduler on both of its delayed backends:
--   * "timer":  C_Timer.After with one runner per key (every Classic client,
--               Midnight 12.1.0);
--   * "signal": TimerUtil.CreateTimedSignalCallbackMap (12.1.5).
-- A fake clock pumps every due timer, signal and OnUpdate in deadline order
-- (tools/tests/castbar_world.lua).
--
-- Pinned contracts:
--   C2.1  every stop re-check owns its own scheduler key: a plain cast whose
--         STOP finds nothing casting completes at the 0.12 s re-check, not at
--         the 0.40 s failsafe, and a channel keeps its failsafe after the
--         second re-check was scheduled.
--   C2.2  a new UNIT_SPELLCAST_START ends the interrupt feedback hold at once.
--   C2.3  every path that shows a cast publishes it to engine subscribers
--         (start retry, stop re-check, target/focus swap).
--   C2.3b a boss or arena pool lifecycle pass that shows a cast publishes it
--         through the driver too.
--   C2.6  boss and arena pools own their cast lifecycle (no failsafe poll);
--         other units' empowered casts fill like casts; an interrupt for
--         another castBarID is ignored; a kicked channel shows its feedback.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/castbar_world.lua"))()

local function NewWorld(backend, options) return World.New(root, backend, options) end

--------------------------------------------------------------------------
-- C2.1: distinct scheduler keys for the stop re-checks
--------------------------------------------------------------------------

local function StopRecheckKeys(backend)
    local world = NewWorld(backend)
    local bar = world:Driver("target")

    -- A plain cast that really ended: the 0.12 s re-check confirms it.
    world:StartCast("target", "Fireball", 3, 41)
    world:Fire(bar, "UNIT_SPELLCAST_START")
    assert(bar.MSUF_castActive == true and bar.castText.text == "Fireball",
        backend .. ": START did not show the cast")
    world:Advance(0.5)
    local stopAt = world.clock
    world.casting.target = nil
    world:Fire(bar, "UNIT_SPELLCAST_STOP")
    world:Advance(0.10)
    assert(#bar.completedAt == 0, backend .. ": a stopped cast completed before its first re-check")
    world:Advance(0.05)
    assert(#bar.completedAt == 1, string.format(
        "%s: a stopped cast was not confirmed by the 0.12 s re-check (completions %d by +%.2f s)",
        backend, #bar.completedAt, world.clock - stopAt))
    assert(bar.completedAt[1] - stopAt <= 0.13, backend .. ": the cast re-check fired late")
    world:Advance(0.5)
    assert(#bar.completedAt == 1, backend .. ": the cast failsafe completed the same stop again")

    -- A channel: once the first re-check has scheduled the second one, the
    -- channel failsafe must still be pending under its own key (SpellQueueWindow
    -- 400 ms: second re-check at +0.48 s, failsafe at +1.03 s).
    local scheduler = world.ns.Scheduler
    world:StartChannel("target", "Mind Flay", 3, 51)
    world:Fire(bar, "UNIT_SPELLCAST_CHANNEL_START")
    world:Advance(0.3)
    world.channeling.target = nil
    world:Fire(bar, "UNIT_SPELLCAST_CHANNEL_STOP")
    world:Advance(0.13)
    assert(bar._msufStopTimer2 == true, backend .. ": the first channel re-check did not schedule the second")
    assert(bar._msufStopCB_chanT2 ~= bar._msufStopCB_failsafe
        and bar._msufStopCB_castT1 ~= bar._msufStopCB_failsafe
        and bar._msufStopCB_castT1 ~= bar._msufStopCB_chanT2,
        backend .. ": stop re-checks share one scheduler key")
    assert(scheduler.IsScheduled(bar._msufStopCB_chanT2) and scheduler.IsScheduled(bar._msufStopCB_failsafe),
        backend .. ": the channel failsafe was dropped once the second re-check was scheduled")
    local completionsBefore = #bar.completedAt
    world:Advance(1.0)
    assert(#bar.completedAt == completionsBefore + 1,
        backend .. ": a stopped channel completed " .. (#bar.completedAt - completionsBefore) .. " times")
end

for _, backend in ipairs({ "timer", "signal" }) do
    StopRecheckKeys(backend)
end

--------------------------------------------------------------------------
-- C2.2: a new cast ends the interrupt feedback hold at once
--------------------------------------------------------------------------

do
    local world = NewWorld("timer")
    _G.MSUF_DB.general.castbarInterruptFeedbackDuration = 2
    local bar = world:Driver("target")
    world:StartCast("target", "Fireball", 3, 61)
    world:Fire(bar, "UNIT_SPELLCAST_START")
    world:Advance(0.4)
    world.casting.target = nil
    world:Fire(bar, "UNIT_SPELLCAST_INTERRUPTED", "Fireball-guid", 133, nil, 61)
    assert(bar.interrupted == true and bar.shown, "INTERRUPTED did not show the feedback hold")
    world:Advance(0.2)
    world:StartCast("target", "Frostbolt", 2.5, 62)
    world:Fire(bar, "UNIT_SPELLCAST_START")
    assert(bar.interrupted == nil, "the interrupt hold survived the next UNIT_SPELLCAST_START")
    assert(bar.MSUF_castActive == true and bar.shown and bar.castText.text == "Frostbolt",
        "the next cast stayed hidden behind the interrupt hold: " .. tostring(bar.castText.text))
    world:Advance(2.0)
    assert(bar.shown and bar.MSUF_castActive == true and bar.castText.text == "Frostbolt",
        "the expiring interrupt hold hid the next cast")
end

--------------------------------------------------------------------------
-- C2.3: every path that shows a cast publishes it to engine subscribers
--------------------------------------------------------------------------

do
    local world = NewWorld("timer")
    local bar = world:Driver("focus")
    local engine = assert(_G.MSUF_GetCastbarEngine(), "castbar engine missing")
    local published = {}
    engine:Subscribe("focus", function(state)
        published[#published + 1] = (state and state.active == true) and state.spellName or false
    end)
    local function LastPublished() return published[#published] end

    -- START before UnitCastingInfo answers: the 0.05 s start retry shows it.
    world:Fire(bar, "UNIT_SPELLCAST_START")
    assert(LastPublished() == false and not bar.MSUF_castActive, "an empty START published a cast")
    world:StartCast("focus", "Polymorph", 1.5, 71)
    world:Advance(0.06)
    assert(bar.MSUF_castActive == true and bar.castText.text == "Polymorph", "the start retry did not show the cast")
    assert(LastPublished() == "Polymorph", "the start retry showed a cast without publishing it")

    -- A follow-up cast found by the stop re-check.
    world.casting.focus = nil
    world:Fire(bar, "UNIT_SPELLCAST_STOP")
    world:StartCast("focus", "Fear", 1.5, 72)
    world:Advance(0.13)
    assert(bar.castText.text == "Fear", "the stop re-check did not show the follow-up cast")
    assert(LastPublished() == "Fear", "the stop re-check showed a cast without publishing it")

    -- A focus swap onto a unit that is already casting.
    world.casting.focus = nil
    world:Fire(bar, "UNIT_SPELLCAST_STOP")
    world:Advance(0.5)
    assert(not bar.MSUF_castActive, "the stopped focus cast stayed active")
    world:StartCast("focus", "Hex", 1.5, 73)
    bar.scripts.OnEvent(bar, "PLAYER_FOCUS_CHANGED")
    assert(bar.MSUF_castActive == true and bar.castText.text == "Hex", "the focus swap did not show the cast")
    assert(LastPublished() == "Hex", "the focus swap showed a cast without publishing it")
end

--------------------------------------------------------------------------
-- C2.3b: pool lifecycle passes publish what they show
--------------------------------------------------------------------------

do
    local world = NewWorld("timer", { pools = true })
    _G.MSUF_ApplyBossCastbarsEnabled()
    _G.MSUF_ApplyArenaCastbarsEnabled()
    local engine = assert(_G.MSUF_GetCastbarEngine(), "castbar engine missing")
    local pools = world.ns.Castbars.Pools
    for _, unit in ipairs({ "boss1", "arena1" }) do
        local published = {}
        engine:Subscribe(unit, function(state)
            published[#published + 1] = (state and state.active == true) and state.spellName or false
        end)
        local pool = pools.kinds[unit:match("^(%a+)")]
        local bar = world:PoolCastbar(pool.Bar(1))
        -- The unit is already casting when the encounter or opponent pass runs.
        world:StartCast(unit, "Shadow Bolt", 2.5, 91)
        assert(pool.RefreshFromUnit(bar, false) == true and bar.MSUF_castActive == true,
            unit .. ": the lifecycle pass did not show the running cast")
        assert(published[#published] == "Shadow Bolt",
            unit .. ": the lifecycle pass showed a cast without publishing it")
        assert(bar._msufActiveSeq == 91, unit .. ": the lifecycle pass kept no cast identity")
        world.casting[unit] = nil
        world:Fire(bar, "UNIT_SPELLCAST_STOP")
        world:Advance(0.5)
    end
end

--------------------------------------------------------------------------
-- C2.6: boss and arena pools own their cast lifecycle (no manager poll)
--------------------------------------------------------------------------

do
    local world = NewWorld("timer", { pools = true })
    _G.MSUF_ApplyBossCastbarsEnabled()
    _G.MSUF_ApplyArenaCastbarsEnabled()
    local FAILSAFE = 32
    for _, unit in ipairs({ "boss1", "arena1" }) do
        local pool = unit == "boss1" and _G.MSUF_BossCastbars or _G.MSUF_ArenaCastbars
        local bar = world:PoolCastbar(pool and pool[1])
        world:StartCast(unit, "Shadow Bolt", 2.5, 81)
        world:Fire(bar, "UNIT_SPELLCAST_START")
        assert(bar.MSUF_castActive == true, unit .. ": START did not show the cast")
        assert(bar._msufCastLifecycleOwned == true, unit .. ": the pool did not own the cast lifecycle")
        local mask = bar._msufCastbarWorkMask or 0
        assert(mask % (FAILSAFE * 2) < FAILSAFE,
            unit .. ": an event-owned cast still polls the unit failsafe (work mask " .. mask .. ")")
        assert(bar.events.UNIT_HEALTH == true, unit .. ": an active cast has no UNIT_HEALTH death signal")
        assert(bar.events.UNIT_FLAGS == true, unit .. ": the pool lost its persistent UNIT_FLAGS")
        world.casting[unit] = nil
        world:Fire(bar, "UNIT_SPELLCAST_STOP")
        world:Advance(0.5)
        assert(not bar.MSUF_castActive and bar.events.UNIT_HEALTH == nil,
            unit .. ": UNIT_HEALTH outlived the cast")
    end

    -- Switching a pool off mid-cast drops every event; switched back on, the
    -- next cast must register its UNIT_HEALTH signal again.
    local arena = _G.MSUF_ArenaCastbars[1]
    world:StartCast("arena1", "Chaos Bolt", 2.5, 82)
    world:Fire(arena, "UNIT_SPELLCAST_START")
    assert(arena.events.UNIT_HEALTH == true, "arena1: no UNIT_HEALTH before the pool was switched off")
    _G.MSUF_DB.general.enableArenaCastbar = false
    _G.MSUF_ApplyArenaCastbarsEnabled()
    assert(next(arena.events) == nil, "arena1: a disabled pool kept events")
    _G.MSUF_DB.general.enableArenaCastbar = true
    _G.MSUF_ApplyArenaCastbarsEnabled()
    world:Advance(0.1)
    world:StartCast("arena1", "Incinerate", 2, 83)
    world:Fire(arena, "UNIT_SPELLCAST_START")
    assert(arena.MSUF_castActive == true and arena.events.UNIT_HEALTH == true,
        "arena1: a re-enabled pool lost the UNIT_HEALTH death signal")
end

--------------------------------------------------------------------------
-- C2.6: another unit's empowered cast fills like a cast
--------------------------------------------------------------------------

do
    local world = NewWorld("timer")
    local bar = world:Driver("target")
    world:StartChannel("target", "Fire Breath", 2, 91, true)
    world:Fire(bar, "UNIT_SPELLCAST_EMPOWER_START")
    assert(bar.MSUF_castActive == true and bar.castText.text == "Fire Breath", "the empowered cast was not shown")
    assert(bar.MSUF_isChanneled ~= true and bar._msufCountsDown ~= true,
        "an enemy empowered cast drains like a channel")
    local first = bar.statusBar.value
    world:Advance(0.5)
    assert(bar.statusBar.value > first, "an enemy empowered cast does not fill: "
        .. tostring(first) .. " -> " .. tostring(bar.statusBar.value))
    -- A plain channel keeps draining.
    world.channeling.target = nil
    world:Fire(bar, "UNIT_SPELLCAST_EMPOWER_STOP")
    world:Advance(0.5)
    world:StartChannel("target", "Mind Flay", 2, 92)
    world:Fire(bar, "UNIT_SPELLCAST_CHANNEL_START")
    assert(bar.MSUF_isChanneled == true and bar._msufCountsDown == true, "a plain channel stopped draining")
end

--------------------------------------------------------------------------
-- C2.6: interrupts follow the shown cast bar; kicked channels give feedback
--------------------------------------------------------------------------

do
    local world = NewWorld("timer")
    local bar = world:Driver("focus")
    local engine = assert(_G.MSUF_GetCastbarEngine(), "castbar engine missing")
    local events = {}
    engine:Subscribe("focus", function(_, event) events[#events + 1] = event end)

    -- A late UNIT_SPELLCAST_INTERRUPTED for an older cast bar is ignored.
    world:StartCast("focus", "Fireball", 3, 101)
    world:Fire(bar, "UNIT_SPELLCAST_START")
    world:Fire(bar, "UNIT_SPELLCAST_INTERRUPTED", "Old-guid", 133, "Player-1-0001", 100)
    assert(bar.interrupted ~= true and bar.MSUF_castActive == true and bar.castText.text == "Fireball",
        "an interrupt of another cast bar hid the shown cast")
    world.casting.focus = nil
    world:Fire(bar, "UNIT_SPELLCAST_INTERRUPTED", "Fireball-guid", 133, "Player-1-0001", 101)
    assert(bar.interrupted == true, "the shown cast's interrupt was ignored")
    world:Advance(1.0)

    -- A kicked channel: CHANNEL_STOP carries the interrupter.
    events = {}
    world:StartChannel("focus", "Drain Life", 3, 111)
    world:Fire(bar, "UNIT_SPELLCAST_CHANNEL_START")
    assert(bar.MSUF_isChanneled == true and bar.interrupted ~= true, "the channel was not shown")
    world.channeling.focus = nil
    world:Fire(bar, "UNIT_SPELLCAST_CHANNEL_STOP", "Drain-guid", 689, "Player-1-0002", 111)
    assert(bar.interrupted == true, "a kicked channel showed no interrupt feedback")
    assert(events[#events] == "UNIT_SPELLCAST_INTERRUPTED",
        "a kicked channel did not tell the subscribers: " .. tostring(events[#events]))
    -- The INTERRUPTED that may follow does not replay the feedback.
    local published = #events
    world:Fire(bar, "UNIT_SPELLCAST_INTERRUPTED", "Drain-guid", 689, "Player-1-0002", 111)
    assert(#events == published, "a second interrupt event replayed the feedback")
    world:Advance(1.0)

    -- A channel that simply ended keeps the normal stop confirmation.
    world:StartChannel("focus", "Mind Flay", 2, 112)
    world:Fire(bar, "UNIT_SPELLCAST_CHANNEL_START")
    world.channeling.focus = nil
    world:Fire(bar, "UNIT_SPELLCAST_CHANNEL_STOP", "Flay-guid", 15407, nil, 112)
    assert(bar.interrupted ~= true, "a channel that ended normally showed an interrupt")
    world:Advance(1.5)
    assert(not bar.MSUF_castActive and #bar.completedAt >= 1, "the ended channel did not complete")
end

print("castbar_driver_lifecycle_smoke: ok (stop re-check keys on timer and signal backends, interrupt hold yields, every shown cast is published, pool passes publish, pools own the lifecycle, enemy empowers fill, interrupts match the cast bar, kicked channels)")
