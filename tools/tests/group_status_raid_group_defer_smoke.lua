-- group_status_raid_group_defer_smoke.lua <repoRoot>
--
-- Raid-group labels on group frames are cold data: a GROUP_ROSTER_UPDATE in
-- combat only marks them stale (MSUF_UF_Group_Status.lua UpdateRaidGroupColdPath)
-- and the status driver repaints just those labels once at PLAYER_REGEN_ENABLED
-- (ReplayDeferredRaidGroups). Contracts:
--  * every fight that sees a roster change repaints each label exactly once at
--    regen, and the latch re-arms for the next fight (the second fight's labels
--    once stayed stale until some later out-of-combat roster event);
--  * the status runtime never asks the group runtime for a deferred pass: a
--    DIRTY_VISUAL group refresh used to stand in for the label replay and
--    re-applied every element of every raid frame, auras included, at regen
--    (raid trace 2026-10-11: 30.9 ms of a 36 ms regen root);
--  * the replay touches only live frames with the label on, and only the label
--    (leader/assist stayed live through the fight);
--  * a roster event suspended for the fight (the label its only consumer)
--    catches up through the one roster broadcast at regen and never adds a
--    second replay, also when a leader/assist frame re-registered the event
--    mid-fight.
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local STATUS = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Status.lua"

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local inCombat = false
_G.InCombatLockdown = function() return inCombat end

local function NewDriverFrame()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(kind, handler) self.scripts[kind] = handler end
    return frame
end

-- One fresh copy of the status module (its driver and latches are file locals).
local function NewWorld()
    local world = { raidGroup = {}, leader = {}, raidGroupTotal = 0, leaderTotal = 0, defers = 0 }
    local MSUF = {
        UF = { RegisterElement = function(name, value) if name == "GroupStatusRuntime" then world.element = value end end },
        UFStatusRuntime = {
            UpdateLeaderPair = function(frame)
                world.leader[frame] = (world.leader[frame] or 0) + 1
                world.leaderTotal = world.leaderTotal + 1
            end,
            UpdateRaidGroup = function(frame)
                world.raidGroup[frame] = (world.raidGroup[frame] or 0) + 1
                world.raidGroupTotal = world.raidGroupTotal + 1
            end,
        },
        GF = { frames = {} },
    }
    world.GF = MSUF.GF
    world.GF.DeferGroupRuntime = function()
        world.defers = world.defers + 1
        return false
    end
    _G.CreateFrame = function()
        world.driver = NewDriverFrame()
        return world.driver
    end
    assert(loadfile(STATUS))("MidnightSimpleUnitFrames", MSUF)
    Check(type(world.element) == "table" and type(world.element.Apply) == "function",
        "GroupStatusRuntime did not register")
    function world:Frame(leader, raidGroup, live, active)
        local events = {}
        if leader then events[#events + 1] = "PARTY_LEADER_CHANGED" end
        if leader or raidGroup then events[#events + 1] = "GROUP_ROSTER_UPDATE" end
        local frame = {
            _msufActiveElements = { GroupStatusRuntime = active ~= false },
            MSUFSpec = { status = {
                runtimeLeaderPair = leader == true,
                runtimeRaidGroup = raidGroup == true,
                groupRuntimeUnitlessEvents = events,
            } },
        }
        if live ~= false then self.GF.frames[frame] = true end
        self.element.Apply(frame)
        return frame
    end
    function world:Event(event)
        local handler = assert(self.driver and self.driver.scripts.OnEvent, "status driver has no event handler")
        handler(self.driver, event)
    end
    function world:Fight(roster)
        self:Event("PLAYER_REGEN_DISABLED")
        inCombat = true
        for _ = 1, roster do
            if self.driver.events.GROUP_ROSTER_UPDATE then self:Event("GROUP_ROSTER_UPDATE") end
        end
    end
    function world:Regen()
        inCombat = false
        self:Event("PLAYER_REGEN_ENABLED")
    end
    return world
end

-- 1. One frame with leader/assist and the label: three fights, one repaint each.
do
    local world = NewWorld()
    local frame = world:Frame(true, true)
    Check(world.driver.events.GROUP_ROSTER_UPDATE == true, "the roster event was not registered")
    for fight = 1, 3 do
        local painted, led = world.raidGroup[frame], world.leader[frame]
        world:Fight(2)
        Check(world.driver.events.GROUP_ROSTER_UPDATE == true, "leader/assist must keep the roster event live in combat")
        Check(world.raidGroup[frame] == painted, "fight " .. fight .. ": the raid group label repainted in combat")
        Check(world.leader[frame] == led + 2, "fight " .. fight .. ": leader/assist must stay live in combat")
        world:Regen()
        Check(world.raidGroup[frame] == painted + 1, string.format(
            "fight %d: regen repainted the label %d times, expected once", fight, world.raidGroup[frame] - painted))
        Check(world.leader[frame] == led + 2, "fight " .. fight .. ": the regen replay repainted leader/assist")
    end
    -- A fight without a roster change replays nothing.
    local painted = world.raidGroup[frame]
    world:Fight(0)
    world:Regen()
    Check(world.raidGroup[frame] == painted, "a fight without a roster change replayed the label")
    -- Out of combat the label repaints at once.
    world:Event("GROUP_ROSTER_UPDATE")
    Check(world.raidGroup[frame] == painted + 1, "an out-of-combat roster change must repaint at once")
    Check(world.defers == 0, "the status runtime asked the group runtime for a deferred pass")
    print("group_status_raid_group_defer_smoke: ok (3 fights, one label replay each, no group runtime pass)")
end

-- 2. A full raid and a noisy combat roster: one label replay, only where it is due.
do
    local world = NewWorld()
    local raid = {}
    for i = 1, 40 do raid[i] = world:Frame(true, true) end
    local leaderOnly = world:Frame(true, false)
    local notLive = world:Frame(true, true, false)
    local inactive = world:Frame(true, true, true, false)
    local raidBefore, leaderBefore = world.raidGroupTotal, world.leaderTotal
    world:Fight(100)
    Check(world.raidGroupTotal == raidBefore, "a roster storm repainted subgroup labels in combat")
    -- 40 raid frames + the leader-only frame are live and active: 41 x 100 leader paints.
    Check(world.leaderTotal == leaderBefore + 4100, "leader event cohort changed: " .. (world.leaderTotal - leaderBefore))
    world:Regen()
    for i = 1, 40 do
        Check(world.raidGroup[raid[i]] == 2, "raid frame " .. i .. ": expected one apply paint and one regen replay")
    end
    Check(world.raidGroup[leaderOnly] == nil, "the replay painted a frame without the label")
    Check(world.raidGroup[notLive] == 1, "the replay painted a frame that is not live")
    Check(world.raidGroup[inactive] == 1, "the replay painted a frame whose status element is off")
    Check(world.raidGroupTotal == raidBefore + 40, "regen replayed " .. (world.raidGroupTotal - raidBefore) .. " labels")
    Check(world.leaderTotal == leaderBefore + 4100, "the regen replay repainted leader/assist")
    Check(world.defers == 0, "the status runtime asked the group runtime for a deferred pass")
    print("group_status_raid_group_defer_smoke: 40 frames / 100 events -> 40 label repaints at regen, nothing else")
end

-- 3. The label alone: the roster event is dropped for the fight and the regen
--    catch-up is the one roster broadcast.
do
    local world = NewWorld()
    local raid = {}
    for i = 1, 10 do raid[i] = world:Frame(false, true) end
    world:Fight(5)
    Check(world.driver.events.GROUP_ROSTER_UPDATE == nil, "a label-only roster event must be suspended in combat")
    world:Regen()
    Check(world.driver.events.GROUP_ROSTER_UPDATE == true, "regen did not restore the roster event")
    for i = 1, 10 do
        Check(world.raidGroup[raid[i]] == 2, "suspended roster: frame " .. i .. " repainted "
            .. (world.raidGroup[raid[i]] - 1) .. " times at regen, expected once")
    end
    -- A leader/assist frame applied mid-fight re-registers the suspended event;
    -- the roster change it then delivers must not add a replay to the broadcast.
    world:Fight(0)
    Check(world.driver.events.GROUP_ROSTER_UPDATE == nil, "the second fight did not suspend the roster event")
    local leader = world:Frame(true, false)
    Check(world.driver.events.GROUP_ROSTER_UPDATE == true, "a mid-fight leader frame did not re-register the event")
    world:Event("GROUP_ROSTER_UPDATE")
    Check(world.raidGroup[raid[1]] == 2, "a mid-fight roster change repainted the label in combat")
    local led = world.leader[leader]
    world:Regen()
    for i = 1, 10 do
        Check(world.raidGroup[raid[i]] == 3, "suspended roster with a live leader frame: frame " .. i
            .. " repainted " .. (world.raidGroup[raid[i]] - 2) .. " times at regen, expected once")
    end
    Check(world.leader[leader] == led + 1, "the regen broadcast must catch leader/assist up once")
    Check(world.defers == 0, "the status runtime asked the group runtime for a deferred pass")
    print("group_status_raid_group_defer_smoke: suspended roster -> one broadcast catch-up, no double replay")
end
