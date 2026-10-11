-- group_regen_status_replay_smoke.lua <repoRoot>
--
-- The combat-end burst of the raid trace 2026-10-11 (capture 6, frame 3681,
-- 147 ms): PLAYER_REGEN_ENABLED ran a DIRTY_VISUAL group refresh that re-applied
-- every element of every raid frame, auras included (RefreshVisuals 30.9 ms of
-- the 36.0 ms RuntimeOnEvent root, 24 frame applies, 96 aura lane compiles).
-- Its only request came from MSUF_UF_Group_Status.lua: a GROUP_ROSTER_UPDATE in
-- combat deferred the subgroup labels as GF.DeferGroupRuntime("refresh", nil,
-- GF.DIRTY_VISUAL). The labels now replay alone, from the status driver.
--
-- Loads the real Metadata, Status and Runtime files on minimal stubs and drives
-- both event handlers in either order at regen. Contracts:
--  * an in-combat roster change queues no refresh reason and no dirty mask;
--  * regen runs the roster work the group runtime deferred for itself (the
--    header pass), repaints each subgroup label exactly once, and applies no
--    frame element, invalidates no compiled spec and notifies no
--    "refreshVisuals" observer;
--  * a genuine visual change made in combat still keeps its own deferral and
--    is applied at regen next to the label replay.
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local GROUP = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/"

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local combat = false
_G.InCombatLockdown = function() return combat end
_G.IsInGroup = function() return true end
_G.IsInRaid = function() return true end
_G.GetNumGroupMembers = function() return 40 end
_G.C_Timer = { After = function(_, fn) fn() end }
_G.MSUF_UF_MaskHas = function(mask, flag)
    mask, flag = tonumber(mask) or 0, tonumber(flag) or 0
    if flag == 0 then return false end
    return math.floor(mask / flag) % 2 == 1
end

local created = {}
_G.CreateFrame = function()
    local frame = { events = {} }
    function frame:SetScript(name, fn) if name == "OnEvent" then self.onEvent = fn end end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() self.events = {} end
    created[#created + 1] = frame
    return frame
end

local count = { applies = 0, invalidations = 0, setups = 0, raidGroup = 0, leader = 0 }
local element
local ns = {
    ExportPublic = function() end,
    UF = {
        IsUnitToken = function(unit) return type(unit) == "string" and unit ~= "" end,
        ApplySpec = function() count.applies = count.applies + 1; return true end,
        RegisterElement = function(name, value) if name == "GroupStatusRuntime" then element = value end end,
    },
    UFStatusRuntime = {
        UpdateLeaderPair = function() count.leader = count.leader + 1 end,
        UpdateRaidGroup = function() count.raidGroup = count.raidGroup + 1 end,
    },
    GF = { frames = {} },
}
local GF = ns.GF
assert(loadfile(GROUP .. "MSUF_UF_Group_Metadata.lua"))("MidnightSimpleUnitFrames", ns)

local frames = {}
function GF.GetConf(kind) return { enabled = kind == "raid" } end
function GF.GetLiveGroupKind() return "raid" end
function GF.GetLiveRaidKind() return "raid" end
GF.EnsureDB = function() end
GF.SetupHeader = function() count.setups = count.setups + 1; return {}, true end
GF.ShowHeaders = function() return true end
GF.RetireHeader = function() return true end
GF.CompileSpec = function(kind) return { kind = kind } end
GF.ApplyStructureSpec = function() count.applies = count.applies + 1; return true end
GF.InvalidateCompiledSpecs = function() count.invalidations = count.invalidations + 1 end
function GF.ForEachFrame(fn, _, a, b, c)
    local any = false
    for _, frame in ipairs(frames) do
        if fn(frame, frame.MSUFUnitKey, frame._msufGFKind, a, b, c) == true then any = true end
    end
    return any
end

assert(loadfile(GROUP .. "MSUF_UF_Group_Status.lua"))("MidnightSimpleUnitFrames", ns)
Check(type(element) == "table" and type(element.Apply) == "function", "GroupStatusRuntime did not register")
assert(loadfile(GROUP .. "MSUF_UF_Group_Runtime.lua"))("MidnightSimpleUnitFrames", ns)
local runtimeFrame = created[#created]
Check(type(runtimeFrame and runtimeFrame.onEvent) == "function", "the group runtime installed no event handler")
GF.RefreshHeaderLayout() -- subscribes the runtime, out of combat

local observed = {}
GF.RegisterRuntimeObserver("regen-status-replay-smoke", function(operation)
    observed[operation] = (observed[operation] or 0) + 1
end)

-- A full raid with leader/assist and the subgroup label on: the roster event
-- stays live in combat (the label is not its only consumer).
for i = 1, 40 do
    local frame = {
        MSUFUnitKey = "raid" .. i,
        _msufGFKind = "raid",
        _msufActiveElements = { GroupStatusRuntime = true },
        MSUFSpec = { status = {
            runtimeLeaderPair = true,
            runtimeRaidGroup = true,
            groupRuntimeUnitlessEvents = { "PARTY_LEADER_CHANGED", "GROUP_ROSTER_UPDATE" },
        } },
    }
    frames[i] = frame
    GF.frames[frame] = true
    element.Apply(frame)
end
local statusDriver = created[#created]
Check(statusDriver ~= runtimeFrame and type(statusDriver.onEvent) == "function", "the status driver was not built")
Check(statusDriver.events.GROUP_ROSTER_UPDATE == true, "the status driver does not follow the roster")
Check(runtimeFrame.events.GROUP_ROSTER_UPDATE == true and runtimeFrame.events.PLAYER_REGEN_ENABLED == true,
    "the group runtime is not subscribed")

local function Dispatch(event, order)
    for _, frame in ipairs(order) do
        if frame.events[event] then frame.onEvent(frame, event) end
    end
end

local function Reset()
    for key in pairs(count) do count[key] = 0 end
    for key in pairs(observed) do observed[key] = nil end
end

local function Fight(order, inCombat)
    Dispatch("PLAYER_REGEN_DISABLED", order)
    combat = true
    for _ = 1, 3 do Dispatch("GROUP_ROSTER_UPDATE", order) end
    if inCombat then inCombat() end
    local reasons = GF._pendingGroupRuntimeReasons
    Check(GF._pendingGroupRuntime == true and reasons and reasons.roster == true,
        "the in-combat roster change did not defer the group runtime's own roster pass")
    combat = false
    Reset()
    Dispatch("PLAYER_REGEN_ENABLED", order)
    Check(GF._pendingGroupRuntime == nil, "the regen flush left work pending")
end

local ORDERS = {
    { label = "runtime first", frames = { runtimeFrame, statusDriver } },
    { label = "status first", frames = { statusDriver, runtimeFrame } },
}

-- (a) A roster change in combat: header pass + label replay, no frame apply.
for _, order in ipairs(ORDERS) do
    local queuedReasons, queuedMask
    Fight(order.frames, function()
        local reasons = GF._pendingGroupRuntimeReasons
        queuedReasons = reasons and reasons.refresh
        queuedMask = GF._pendingGroupRuntimeMask
    end)
    Check(queuedReasons == nil, order.label .. ": a combat roster change queued a group refresh")
    Check(queuedMask == nil, order.label .. ": a combat roster change queued a dirty mask")
    Check(count.setups >= 1, order.label .. ": regen skipped the deferred roster header pass")
    Check(count.applies == 0, string.format("%s: regen re-applied %d group frames for a roster change",
        order.label, count.applies))
    Check(count.invalidations == 0, order.label .. ": regen invalidated the compiled group specs")
    Check(observed.refreshVisuals == nil, order.label .. ": regen notified a refreshVisuals pass")
    Check(count.raidGroup == 40, string.format("%s: regen repainted %d subgroup labels, expected 40",
        order.label, count.raidGroup))
    Check(count.leader == 0, order.label .. ": the regen replay repainted leader/assist")
end
print("group_regen_status_replay_smoke: roster change in combat -> 40 label repaints, 0 frame applies (both orders)")

-- (b) A real visual change made in combat keeps its own deferral and mask.
for _, order in ipairs(ORDERS) do
    Fight(order.frames, function() GF.RefreshFonts(nil) end)
    Check(count.applies == 40, string.format("%s: the deferred font refresh applied %d frames, expected 40",
        order.label, count.applies))
    Check(observed.refreshVisuals == 1, order.label .. ": the deferred font refresh did not notify its observers")
    Check(count.raidGroup == 40, order.label .. ": the label replay changed next to a deferred font refresh")
end
print("group_regen_status_replay_smoke: a deferred font refresh still applies at regen")
