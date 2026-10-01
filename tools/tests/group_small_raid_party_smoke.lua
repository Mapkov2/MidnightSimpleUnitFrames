-- group_small_raid_party_smoke.lua <repoRoot>
--
-- "Use Party layout for raids up to 5 players" on the real Mainline graph:
--   (a) it applies only while the Party scope itself is on; with Party off the
--       Raid scope keeps the raid, so frames never vanish;
--   (b) Party sort options work from the raid roster (raidN tokens);
--   (c) Priority Frames read the raid roster while keeping Party visuals;
--   (d) the Party layout's "show player" choice holds in the small raid;
--   (e) Blizzard's raid frames stay hidden while the party frames show the raid.
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg[1], "usage: group_small_raid_party_smoke.lua <root>"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local SecureSort = assert(loadfile(root .. "/tools/tests/secure_group_sort.lua"))()

local roster = {
    { name = "Healy", class = "PRIEST", role = "HEALER", group = 1, unit = "raid1", guid = "G1" },
    { name = "Tanky", class = "WARRIOR", role = "TANK", group = 1, unit = "raid2", guid = "G2" },
    { name = "Tester", class = "MAGE", role = "DAMAGER", group = 2, unit = "raid3", guid = "PLAYER" },
}
local byUnit = {}
for _, member in ipairs(roster) do byUnit[member.unit] = member end
byUnit.player = roster[3]

local world = World.New(root, "Mainline")
local env = world.env
env.IsInRaid = function() return true end
env.IsInGroup = function() return true end
env.GetNumGroupMembers = function() return #roster end
env.GetNumSubgroupMembers = function() return 0 end
env.GetRaidRosterInfo = function(index)
    local m = roster[index]
    if not m then return nil end
    return m.name, 0, m.group, 60, m.class, m.class, "zone", true, false, nil, nil, m.role
end
env.UnitName = function(unit) local m = byUnit[unit]; return m and m.name or nil, nil end
env.UnitGUID = function(unit) local m = byUnit[unit]; return m and m.guid or nil end
env.UnitClass = function(unit) local m = byUnit[unit]; return "Class", m and m.class or "WARRIOR" end
env.UnitGroupRolesAssigned = function(unit) local m = byUnit[unit]; return m and m.role or "NONE" end
env.UnitExists = function(unit) return byUnit[unit] ~= nil end
world:Boot()
assert(not world:FirstFailure(), "Mainline graph failed to boot")
env.MSUF_EnsureDB(true)
local GF = world.core.GF
GF.EnsureDB()
local party, raid = GF.GetConf("party"), GF.GetConf("raid")

-- (a) Party scope off: the Raid scope owns the raid.
party.enabled, party.smallRaidAsParty, raid.enabled = false, true, true
assert(GF.IsSmallRaidPartyContext() == false and GF.GetLiveGroupKind() == "raid",
    "a disabled Party scope took the small raid away from the Raid scope")
party.enabled = true
assert(GF.IsSmallRaidPartyContext() == true and GF.GetLiveGroupKind() == "party", "small raid did not use the Party layout")

local function Shown(header)
    local members = {}
    for _, m in ipairs(roster) do
        members[#members + 1] = { unit = m.unit, name = m.name, subgroup = m.group, class = m.class, assignedRole = m.role }
    end
    return SecureSort.Order(header, { kind = "RAID", members = members })
end

-- (b) Party role order with player first, across two raid subgroups.
party.sortMode, party.playerFirstInRole, party.roleOrder = "ROLE", true, "DAMAGER,TANK,HEALER"
party.showPlayer = true
local header = assert(GF.SetupHeader("party", "party"), "party header did not build in the small raid")
assert(header:GetAttribute("showRaid") == true, "small raid party header does not read the raid roster")
assert(header:GetAttribute("nameList") ~= nil and Shown(header) == "Tester,Tanky,Healy",
    "Party sort options were lost in the small raid: " .. Shown(header))
party.playerFirstInRole = false
header = GF.SetupHeader("party", "party")
assert(header:GetAttribute("nameList") == nil and Shown(header) == "Tester,Tanky,Healy",
    "plain Party role order is not native in the small raid")

-- (d) The Party layout hides the player: the raid header must not list them.
party.showPlayer = false
header = GF.SetupHeader("party", "party")
assert(Shown(header) == "Tanky,Healy", "small raid showed the player although the Party layout hides them: " .. Shown(header))
party.showPlayer = true

-- (c) Priority Frames: raid roster, Party visuals.
assert(GF.GetPriorityGroupType() == "raid", "Priority Frames read party tokens in a small raid")
assert(GF.IsPriorityGroupUnit("raid1") == true and GF.IsPriorityGroupUnit("party1") == false,
    "Priority Frames pinned subgroup party tokens in a small raid")

-- (e) Blizzard raid frames stay hidden although the Raid scope is off.
raid.enabled = false
local container = env.CreateFrame("Frame", "CompactRaidFrameContainer", env.UIParent)
env.CompactRaidFrameContainer = container
container:Show()
GF.ApplyBlizzardGroupFrameOwnership("addon-loaded-smoke")
assert(not container:IsShown() or container:GetParent() ~= env.UIParent,
    "Blizzard raid frames showed next to the party frames of a small raid")

print("group_small_raid_party_smoke: PASS")
