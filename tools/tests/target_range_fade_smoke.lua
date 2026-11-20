local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local forever = flavor == "Forever"
local World = dofile(root .. "/tools/tests/castbar_secret_world.lua")
local OUT_ALPHA = .4
local FIRST_RETRY_WINDOW = .3
local ALL_RETRIES_WINDOW = 2

local function NewTarget(playerClass, known)
    local state = { reads = 0, targetReads = 0, registered = {} }
    local world = World.New(root, {
        flavor = flavor,
        playerClass = playerClass,
        setup = function(env)
            env.TotemFrame = false
            env.UnitCanAssist = function() return false end
            env.UnitInRange = function() return false, false end
            env.C_SpellBook.IsSpellKnownOrInSpellBook = function(id) return known[id] == true end
            env.C_Spell.EnableSpellRangeCheck = function(id, enable)
                state.registered[id] = enable and true or nil
            end
            env.C_Spell.IsSpellInRange = function(id, ...)
                state.reads = state.reads + 1
                state.spell = id
                state.targetArgCount = select("#", ...)
                state.targetArg = ...
                if state.targetArgCount == 0 or state.targetArg == "target" then
                    state.targetReads = state.targetReads + 1
                end
                return state.result
            end
        end,
    })
    local UF = world.core.UF
    world.core.Require("MSUF_EnsureDB", "target range smoke")(true)
    local frame = world.env.CreateFrame("Button", nil, world.env.UIParent)
    frame.MSUFUnitKey = "target"
    frame.MSUFSpec = {
        alpha = UF.Shared.CompileAlpha({}, {}, false),
        range = { active = true, alpha = OUT_ALPHA },
    }
    UF.frames.target = frame
    assert(UF.Range.RegisterFrame(frame, frame.MSUFSpec), "target range registration failed")
    return world, frame, state
end

local function Acquire(world, state, result)
    state.result = result
    world.base:FireEvent("PLAYER_TARGET_CHANGED")
    return state.reads
end

local function Hunter()
    local world, frame, state = NewTarget("HUNTER", { [75] = true, [1130] = true })
    assert(state.registered[75] and not state.registered[1130], "Hunter must use Auto Shot")

    local scheduler = world.core.Scheduler
    local retryKey = "MSUF_UF_RangeFade_TargetRetry"
    local scheduleAfter, cancelScheduled = scheduler.ScheduleAfter, scheduler.CancelScheduled
    local arms, cancels = 0, 0
    scheduler.ScheduleAfter = function(key, ...)
        if key == retryKey then arms = arms + 1 end
        return scheduleAfter(key, ...)
    end
    scheduler.CancelScheduled = function(key)
        if key == retryKey then cancels = cancels + 1 end
        return cancelScheduled(key)
    end

    local reads = Acquire(world, state, nil)
    assert(frame:GetAlpha() == 1, "unknown initial range should remain fully opaque")
    state.result = false
    world:Advance(FIRST_RETRY_WINDOW)
    if forever then
        assert(state.reads == reads + 1 and frame:GetAlpha() == OUT_ALPHA,
            "Forever Hunter must recover a far target with one fresh check")
        assert(state.targetArgCount == 0, "Forever must check the current target without a unit argument")
    else
        assert(state.reads == reads and frame:GetAlpha() == 1, "Mainline target range should stay event driven")
        assert(state.targetArgCount == 1 and state.targetArg == "target", "Mainline must keep the explicit target unit")
    end

    local previousArms, previousCancels = arms, cancels
    local previousReads = state.reads
    reads = Acquire(world, state, false)
    assert(frame:GetAlpha() == OUT_ALPHA and reads == previousReads + 1,
        "valid false must fade on acquisition with one spell read")
    assert(arms == previousArms and cancels == previousCancels,
        "resolved acquisition without pending recovery must avoid the retry scheduler")
    world:Advance(ALL_RETRIES_WINDOW)
    assert(state.reads == reads, "valid initial result must not schedule recovery")
    world.base:FireEvent("SPELL_RANGE_CHECK_UPDATE", 75, true, true)
    assert(frame:GetAlpha() == 1, "valid in-range spell event must restore opacity")
    world.base:FireEvent("SPELL_RANGE_CHECK_UPDATE", 75, false, true)
    assert(frame:GetAlpha() == OUT_ALPHA, "valid out-of-range spell event must fade")
    world.base:FireEvent("SPELL_RANGE_CHECK_UPDATE", 75, false, true)
    assert(state.reads == reads and arms == previousArms and cancels == previousCancels,
        "checked range events must avoid new spell and scheduler calls when no retry is pending")

    state.result = nil
    world.base:FireEvent("SPELLS_CHANGED")
    assert(state.reads == reads and frame:GetAlpha() == OUT_ALPHA,
        "rebuilding the same spell set must preserve the checked range")
    assert(world.core.UF.Range.RegisterFrame(frame, frame.MSUFSpec))
    assert(state.reads == reads and frame:GetAlpha() == OUT_ALPHA,
        "reapplying settings to the same target must preserve the checked range")
    if not forever then return end

    reads = Acquire(world, state, nil)
    previousArms, previousCancels = arms, cancels
    world.base:FireEvent("SPELLS_CHANGED")
    assert(world.core.UF.Range.RegisterFrame(frame, frame.MSUFSpec))
    assert(state.reads == reads and arms == previousArms and cancels == previousCancels,
        "an unchanged spellbook or configuration refresh must leave pending recovery alone")
    world.base:FireEvent("SPELL_RANGE_CHECK_UPDATE", 75, false, false)
    assert(frame:GetAlpha() == 1, "unchecked event must not fade")
    world:Advance(FIRST_RETRY_WINDOW)
    assert(state.reads == reads + 1 and frame:GetAlpha() == 1,
        "unchecked event must allow recovery and a repeated nil must stay opaque")
    world:Advance(ALL_RETRIES_WINDOW)
    assert(state.reads == reads + 3 and frame:GetAlpha() == 1, "unknown range must allow only three recovery checks")
    world:Advance(ALL_RETRIES_WINDOW)
    assert(state.reads == reads + 3, "unknown range must not start continuous polling")

    reads = Acquire(world, state, nil)
    world:Advance(FIRST_RETRY_WINDOW)
    assert(state.reads == reads + 1 and frame:GetAlpha() == 1, "first unknown retry must keep the frame opaque")
    state.result = false
    world:Advance(.5)
    assert(state.reads == reads + 2 and frame:GetAlpha() == OUT_ALPHA, "a later valid retry must fade the frame")
    world:Advance(ALL_RETRIES_WINDOW)
    assert(state.reads == reads + 2, "valid retry must stop further checks")

    reads = Acquire(world, state, nil)
    state.result = false
    assert(scheduler.IsScheduled(retryKey), "unresolved acquisition must schedule its retry")
    previousArms, previousCancels = arms, cancels
    world.base:FireEvent("SPELL_RANGE_CHECK_UPDATE", 75, true, true)
    assert(not scheduler.IsScheduled(retryKey) and cancels == previousCancels + 1,
        "valid event must cancel the pending retry immediately")
    world.base:FireEvent("SPELL_RANGE_CHECK_UPDATE", 75, true, true)
    assert(cancels == previousCancels + 1 and arms == previousArms, "duplicate result must avoid the scheduler")
    world:Advance(ALL_RETRIES_WINDOW)
    assert(state.reads == reads and frame:GetAlpha() == 1, "valid range event must win over recovery")

    Acquire(world, state, nil)
    reads = Acquire(world, state, true)
    state.result = false
    world:Advance(ALL_RETRIES_WINDOW)
    assert(state.reads == reads and frame:GetAlpha() == 1, "old recovery must not affect a replacement target")

    Acquire(world, state, nil)
    world:Advance(FIRST_RETRY_WINDOW)
    reads = Acquire(world, state, nil)
    world:Advance(FIRST_RETRY_WINDOW)
    assert(state.reads == reads + 1, "a new unresolved target must restart the retry cadence")
    world:Advance(ALL_RETRIES_WINDOW)
    assert(state.reads == reads + 3 and not scheduler.IsScheduled(retryKey),
        "replacing an unresolved target must give it exactly its own retry budget")

    reads = Acquire(world, state, nil)
    world.exists.target = false
    world.base:FireEvent("PLAYER_TARGET_CHANGED")
    world:Advance(ALL_RETRIES_WINDOW)
    assert(state.reads == reads and frame:GetAlpha() == 1, "clearing the target must stop recovery")

    world.exists.target = true
    reads = Acquire(world, state, nil)
    frame:Hide()
    assert(not scheduler.IsScheduled(retryKey), "hiding the target frame must immediately cancel its retry")
    world:Advance(ALL_RETRIES_WINDOW)
    assert(state.reads == reads, "hidden target frame must not recheck range")

    frame:Show()
    reads = Acquire(world, state, nil)
    world.core.UF.Range.UnregisterFrame(frame)
    world:Advance(ALL_RETRIES_WINDOW)
    assert(state.reads == reads, "disabled range fade must not recheck range")
    assert(#world.errors == 0, table.concat(world.errors, "\n"))
end

local function Warlock()
    local known = { [11660] = true, [686] = true, [11699] = true, [234153] = true }
    local world, frame, state = NewTarget("WARLOCK", known)
    Acquire(world, state, false)
    local expected = forever and 11660 or 234153
    assert(state.spell == expected and state.registered[expected],
        "Warlock must probe and arm the highest known Forever Shadow Bolt rank or Mainline default")
    assert(not state.registered[686] and not state.registered[11699], "secondary Warlock probes must not also arm")
    assert(frame:GetAlpha() == OUT_ALPHA, "valid Warlock result must fade on acquisition")
    if forever then
        assert(state.targetArgCount == 0, "Forever Warlock must use the native current target")
        local reads = Acquire(world, state, nil)
        state.result = false
        known[11661] = true
        world.base:FireEvent("SPELLS_CHANGED")
        assert(state.spell == 11661 and state.registered[11661] and not state.registered[11660],
            "learning the next Shadow Bolt rank must replace the previous probe")
        assert(state.reads == reads + 1 and frame:GetAlpha() == OUT_ALPHA,
            "a new rank must refresh the current target immediately even while an earlier retry is pending")

        known[11661], known[11660], known[686] = nil, nil, nil
        world.base:FireEvent("SPELLS_CHANGED")
        assert(state.spell == 11699 and state.registered[11699] and not state.registered[11661],
            "Drain Life must be available when no Shadow Bolt is known")
    end
end

local function Reveal()
    local world, frame, state = NewTarget("HUNTER", { [75] = true })
    local range = world.core.UF.Range
    local dependent = world.env.CreateFrame("Button", nil, world.env.UIParent)
    dependent.MSUFUnitKey, dependent.MSUFSpec = "targettarget", frame.MSUFSpec
    world.core.UF.frames.targettarget = dependent
    world.exists.targettarget = false
    assert(range.RegisterFrame(dependent, dependent.MSUFSpec))

    local function HideTarget()
        Acquire(world, state, true)
        frame:Hide()
        world.exists.target = false
        world.base:FireEvent("PLAYER_TARGET_CHANGED")
        world:Advance(.1)
        world.exists.target = true
        state.result = false
        return state.targetReads
    end

    local reads = HideTarget()
    frame:Show()
    world.base:FireEvent("PLAYER_TARGET_CHANGED")
    world:Advance(.1)
    assert(state.targetReads == reads + 1 and frame:GetAlpha() == OUT_ALPHA,
        "revealing a target followed by its change event must use a single spell read")

    reads = HideTarget()
    world.base:FireEvent("PLAYER_TARGET_CHANGED")
    frame:Show()
    world:Advance(.1)
    assert(state.targetReads == reads + 1 and frame:GetAlpha() == OUT_ALPHA,
        "revealing a target after its change event must still seed range")
end

Hunter()
Warlock()
if forever then Reveal() end
print("Target range fade passed (" .. flavor .. ")")
