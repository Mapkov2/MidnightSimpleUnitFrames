-- Native aura runtime (Midnight and WoW Forever): UNIT_FACTION on the player.
-- The player's own disposition (a duel, mind control, a PvP flag) flips the
-- observer side of UnitCanAssist("player", unit) for every assist-gated owner
-- on target, focus, boss and arena, while no event names those units. The
-- shared identity driver must re-gate each of them, not only the player's own
-- owners; group owners keep their own assist-state path.
-- Arguments: repository root, then optionally the IdentityEvents path (mutation runs).
local root = assert(arg[1], "repository root argument missing")
root = (tostring(root):gsub("\\", "/"):gsub("/+$", ""))
local path = arg[2] or (root .. "/MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_IdentityEvents.lua")

local function Check(ok, message)
    if not ok then error(message, 2) end
end

local frames = {}
local function CreateFrame()
    local frame = { events = {} }
    function frame:SetScript(name, handler) self[name] = handler end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:RegisterUnitEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() self.events = {} end
    frames[#frames + 1] = frame
    return frame
end

local MSUF = {
    Auras3RuntimeFactories = {},
    UF = { IsBossUnit = function(unit) return type(unit) == "string" and unit:match("^boss%d$") ~= nil end },
}
local A3 = {}
assert(loadfile(path))("MidnightSimpleUnitFrames", MSUF)
local factory = assert(MSUF.Auras3RuntimeFactories.IdentityEvents, "IdentityEvents factory did not register")
factory("MidnightSimpleUnitFrames", MSUF, A3, {}, function(_, value) return value end, {
    Platform = {
        C_Timer = { After = function(_, fn) fn() end },
        CreateFrame = CreateFrame,
        InCombat = function() return false end,
        issecretvalue = function() return false end,
    },
    Identity = {
        ContainerOwnsHelpfulAuras = function() return false end,
        IsLiveGroupAuraFrame = function() return false end,
    },
    Presence = { SyncCuratedBigDefensiveContainer = function() return false end },
})

local driver = assert(A3._EnsureDirectIdentityRefreshFrame(), "the identity driver frame was not created")
local onEvent = assert(driver.OnEvent, "the identity driver has no OnEvent handler")

-- Shared event tables the Identity runtime owns (MSUF_Auras3_Runtime_Identity.lua).
A3._directIdentityRefreshAllEvents = { PLAYER_ENTERING_WORLD = true, ZONE_CHANGED_NEW_AREA = true }
A3._directIdentityEventUnits = { PLAYER_TARGET_CHANGED = { "target" } }
A3._HasGroupAuraAssistOwners = function() return false end
A3._IsGroupUnitToken = function(unit)
    return type(unit) == "string" and (unit:match("^party%d+$") ~= nil or unit:match("^raid%d+$") ~= nil)
end
A3._unitAuraIdentityOwnersByUnit = {
    target = { [{}] = true }, focus = { [{}] = true }, boss2 = { [{}] = true }, arena1 = { [{}] = true },
    party1 = { [{}] = true },
}
local scheduled = {}
A3._ScheduleDirectIdentityEventRefresh = function(unit, nonGroupOnly)
    scheduled[unit] = nonGroupOnly == true and "nonGroup" or "all"
    return true
end

onEvent(driver, "UNIT_FACTION", "player")
Check(scheduled.player == "nonGroup", "UNIT_FACTION on the player no longer refreshes the player's own owners")
for _, unit in ipairs({ "target", "focus", "boss2", "arena1" }) do
    Check(scheduled[unit] == "nonGroup",
        "UNIT_FACTION on the player left the assist-gated " .. unit .. " owners on the previous disposition")
end
Check(scheduled.party1 == nil, "UNIT_FACTION on the player re-gated a group owner outside its assist-state path")

-- Another unit's faction change still refreshes that unit alone.
for key in pairs(scheduled) do scheduled[key] = nil end
onEvent(driver, "UNIT_FACTION", "target")
local count = 0
for _ in pairs(scheduled) do count = count + 1 end
Check(count == 1 and scheduled.target == "all", "UNIT_FACTION on the target fanned out beyond the target")

print("native identity faction fan-out smoke passed")
