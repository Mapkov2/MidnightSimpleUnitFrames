-- <root> [client] [measure]: real runtime and native secure-header lifecycle.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local h = Harness.New(root, flavor, { nativeLayout = true, beforeBoot = function(h)
    local load = h.world.LoadGraph
    function h.world:LoadGraph(addon, ...)
        if addon ~= "MidnightSimpleUnitFrames_Options" then return load(self, addon, ...) end
    end
end })
local GF, env = h.GF, h.env
local difficulty = 14
env.GetRaidDifficultyID = function() return difficulty end
env.GetInstanceInfo = function() return "Instance", h.raid and "raid" or "party", difficulty end
for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
    local conf = GF.GetConf(kind)
    conf.enabled, conf.smallRaidAsParty = true, false
end
h:SetRoster({ "player", "party1", "party2", "party3", "party4" })
GF.InvalidateCompiledSpecs()
GF.RefreshHeaderLayout()
h:RunTimers()
local refresh, calls = GF.RefreshHeaderLayout, 0
GF.RefreshHeaderLayout = function(...)
    calls = calls + 1
    return refresh(...)
end
local function Burst()
    for _ = 1, 16 do h:Event("PLAYER_DIFFICULTY_CHANGED") end
end
do
    local vm, kb = math.huge, math.huge
    for _ = 1, 2 do
        collectgarbage("collect")
        collectgarbage("stop")
        local before, ticks = collectgarbage("count"), 0
        debug.sethook(function() ticks = ticks + 1 end, "", 1000)
        Burst()
        h:RunTimers()
        debug.sethook()
        vm, kb = math.min(vm, ticks), math.min(kb, collectgarbage("count") - before)
        collectgarbage("restart")
    end
    local natives, nativeCalls = {}, 0
    for _, name in ipairs({ "SetPoint", "ClearAllPoints", "SetSize", "SetWidth", "SetHeight", "SetAttribute",
        "Show", "Hide", "SetScale", "GetScale", "RegisterEvent", "UnregisterEvent" }) do
        natives[assert(h.widgets.Methods[name])] = true
    end
    for _, name in ipairs({ "IsInRaid", "IsInGroup", "GetNumGroupMembers", "GetNumSubgroupMembers",
        "UnitGroupRolesAssigned", "GetRaidRosterInfo", "GetRaidDifficultyID", "GetInstanceInfo" }) do
        natives[assert(env[name])] = true
    end
    debug.sethook(function()
        if natives[debug.getinfo(2, "f").func] then nativeCalls = nativeCalls + 1 end
    end, "c")
    Burst()
    h:RunTimers()
    debug.sethook()
    print(string.format("MEASURE difficulty %s: %dk VM, %.3f KB, %d counted native calls, %d layouts/three bursts",
        flavor, vm, kb, nativeCalls, calls))
    if arg[3] == "measure" then return end
    -- Measured five-client maximum plus a small margin; the allocation limit
    -- allows 64-bit Lua object sizes. Native and VM work remain separate limits.
    assert(vm <= 76 and kb <= 32, "difficulty burst exceeded VM/allocation budget")
    assert(nativeCalls <= (flavor == "Mainline" and 292 or 221), "difficulty burst exceeded native-call budget")
    calls = 0
end
Burst()
assert(calls == 1, "identical difficulty burst must apply immediately once, got " .. calls)
h:RunTimers()
assert(calls == 2, "native footprint still needs one trailing settle, got " .. calls)
Burst()
assert(calls == 3, "next frame must not reuse an old burst")
h:RunTimers()
assert(calls == 4)

-- A roster-owned settle must also end a difficulty burst's lifetime.
calls = 0
h:Event("GROUP_ROSTER_UPDATE")
Burst()
assert(calls == 1)
h:RunTimers()
assert(calls == 2)
Burst()
assert(calls == 3)
h:RunTimers()
assert(calls == 4)

-- Group kind can change while the numerical difficulty stays the same.
calls = 0
Burst()
h:SetRaid(20)
h:Event("PLAYER_DIFFICULTY_CHANGED")
assert(calls == 2 and GF.headers.raid, "party-to-raid layout switch was delayed")
h:SetRoster({ "player", "party1", "party2", "party3", "party4" })
h:Event("PLAYER_DIFFICULTY_CHANGED")
assert(calls == 3 and GF.headers.party, "raid-to-party layout switch was delayed")
h:RunTimers()

-- Party event-derived combat starts before native lockdown, too.
h:EnterCombat(function() Burst() end)
Burst()
h:RunTimers()
local partyCalls = calls
h:LeaveCombat()
h:RunTimers()
assert(calls > partyCalls, "party combat-deferred layout was lost")

-- A real layout-kind change must remain immediate, even within a pending burst.
h:SetRaid(20)
calls = 0
h:Event("PLAYER_DIFFICULTY_CHANGED")
assert(calls == 1)
local header = assert(GF.headers.raid)
difficulty = 16
h:Event("PLAYER_DIFFICULTY_CHANGED")
local supportsMythic = h.core.Client.SupportsGroupKind("mythicraid")
assert(calls == (supportsMythic and 2 or 1), "raid-kind change was delayed or unsupported kind rebuilt")
if supportsMythic then assert(header._msufGFKind == "mythicraid", "shared header did not switch immediately") end
difficulty = 14
h:Event("PLAYER_DIFFICULTY_CHANGED")
assert(calls == (supportsMythic and 3 or 1), "return to normal raid was delayed")
assert(header._msufGFKind == "raid", "shared header retained mythic configuration")
h:RunTimers()
assert(calls == (supportsMythic and 4 or 2))

-- An unsuccessful immediate layout must be retried; it is never cached as done.
local fail = true
GF.RefreshHeaderLayout = function(...)
    calls = calls + 1
    if fail then fail = false; return false, false end
    return refresh(...)
end
calls = 0
h:Event("PLAYER_DIFFICULTY_CHANGED")
h:Event("PLAYER_DIFFICULTY_CHANGED")
assert(calls == 2, "failed immediate layout was swallowed")
h:RunTimers()
assert(calls == 3)

-- The event-derived combat gate precedes lockdown; leave-combat performs repair.
h:EnterCombat(function() Burst() end)
Burst()
h:RunTimers()
local before = calls
h:LeaveCombat()
h:RunTimers()
assert(calls > before, "combat-deferred layout was lost")
assert(#h.violations == 0, table.concat(h.violations, "\n"))
print("PASS instance_difficulty_layout_smoke " .. flavor .. ": burst, real kind switches, retry, combat and native settle")
