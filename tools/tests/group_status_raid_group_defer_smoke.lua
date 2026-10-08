-- group_status_raid_group_defer_smoke.lua <repoRoot>
--
-- Raid-group labels on group frames are cold data: a GROUP_ROSTER_UPDATE in
-- combat defers their repaint to one group runtime pass at regen
-- (MSUF_UF_Group_Status.lua DeferRaidGroupForCombat). The `raidGroupDeferred`
-- latch that keeps one fight to one deferral was cleared only by an
-- out-of-combat roster repaint; the deferred pass itself repaints through
-- RunStatusApply and never cleared it. With leader/assist on (the roster event
-- stays live in combat), the second fight's roster changes then deferred
-- nothing and its labels stayed stale until some later out-of-combat roster
-- event. Contract: every fight that sees a roster change defers exactly one
-- repaint. Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local inCombat = false
local driver
local function NewFrame()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(kind, handler) self.scripts[kind] = handler end
    return frame
end

local element
local paints = { raidGroup = 0, leader = 0 }
local defers = 0
local MSUF = {
    UF = { RegisterElement = function(name, value) if name == "GroupStatusRuntime" then element = value end end },
    UFStatusRuntime = {
        UpdateLeaderPair = function() paints.leader = paints.leader + 1 end,
        UpdateRaidGroup = function() paints.raidGroup = paints.raidGroup + 1 end,
    },
    GF = {},
}
local GF = MSUF.GF
GF.DeferGroupRuntime = function(reason, kind, mask)
    defers = defers + 1
    GF._pendingGroupRuntime = true
    return false
end

_G.CreateFrame = function()
    driver = NewFrame()
    return driver
end
_G.InCombatLockdown = function() return inCombat end

assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Status.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
Check(type(element) == "table" and type(element.Apply) == "function", "GroupStatusRuntime did not register")

-- One raid frame with leader/assist and the raid group label on.
local frame = {
    _msufActiveElements = { GroupStatusRuntime = true },
    MSUFSpec = { status = {
        runtimeLeaderPair = true,
        runtimeRaidGroup = true,
        groupRuntimeUnitlessEvents = { "GROUP_ROSTER_UPDATE" },
    } },
}
GF.frames = { [frame] = true }
element.Apply(frame)
Check(driver ~= nil and driver.events.GROUP_ROSTER_UPDATE == true, "the roster event was not registered")
local OnEvent = assert(driver.scripts.OnEvent, "status driver has no event handler")

-- What the group runtime's regen flush does for a deferred "refresh".
local function RegenFlush()
    inCombat = false
    OnEvent(driver, "PLAYER_REGEN_ENABLED")
    if GF._pendingGroupRuntime then
        GF._pendingGroupRuntime = nil
        element.Apply(frame)
    end
end

for fight = 1, 3 do
    OnEvent(driver, "PLAYER_REGEN_DISABLED")
    inCombat = true
    Check(driver.events.GROUP_ROSTER_UPDATE == true, "leader/assist must keep the roster event live in combat")
    local before, painted = defers, paints.raidGroup
    OnEvent(driver, "GROUP_ROSTER_UPDATE")
    OnEvent(driver, "GROUP_ROSTER_UPDATE")
    Check(paints.raidGroup == painted, "fight " .. fight .. ": the raid group label repainted in combat")
    Check(defers == before + 1, string.format("fight %d: %d deferred repaints, expected exactly one",
        fight, defers - before))
    RegenFlush()
    Check(paints.raidGroup > painted, "fight " .. fight .. ": regen did not repaint the raid group label")
end

-- Out of combat the label repaints at once and defers nothing.
local before, painted = defers, paints.raidGroup
OnEvent(driver, "GROUP_ROSTER_UPDATE")
Check(defers == before and paints.raidGroup == painted + 1, "an out-of-combat roster change must repaint at once")

print("group_status_raid_group_defer_smoke: ok (3 fights, one deferral each)")

-- A full raid and a noisy combat roster still enqueue only one cold replay.
for i=2,40 do
 local extra={_msufActiveElements={GroupStatusRuntime=true},MSUFSpec=frame.MSUFSpec}
 GF.frames[extra]=true
 element.Apply(extra)
end
OnEvent(driver,"PLAYER_REGEN_DISABLED")
inCombat=true
before,painted=defers,paints.raidGroup
local leaderBefore=paints.leader
for i=1,100 do OnEvent(driver,"GROUP_ROSTER_UPDATE") end
Check(defers==before+1,"40-frame roster storm queued multiple replays")
Check(paints.raidGroup==painted,"roster storm repainted subgroup labels in combat")
Check(paints.leader==leaderBefore+4000,"leader event cohort changed")
RegenFlush()
print("group_status_raid_group_defer_smoke: 40 frames / 100 events -> one deferred replay")
