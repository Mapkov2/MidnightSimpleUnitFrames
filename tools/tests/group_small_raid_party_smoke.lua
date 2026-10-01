-- group_small_raid_party_smoke.lua <repoRoot>
--
-- "Use Party layout for raids up to 5 players" on the real Mainline graph:
--   (a) it applies only while the Party scope itself is on; with Party off the
--       Raid scope keeps the raid, so frames never vanish;
--   (b) Party sort options work from the raid roster (raidN tokens);
--   (c) Priority Frames read the raid roster while keeping Party visuals;
--   (d) the Party layout's "show player" choice holds in the small raid;
--   (e) Blizzard's raid frames stay hidden while the party frames show the raid,
--   (f) and return once it grows past five, without MSUF ever showing them itself.
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

-- (e) Blizzard raid frames stay hidden although the Raid scope is off, and (f)
--     only while the raid is small: past five members they come back mid-session
--     (in combat too), and MSUF itself never makes them visible -- their OnShow
--     (CompactUnitFrame_OnShow) would run tainted. Visibility comes from a secure
--     state driver; SecureStateDriver.lua resolveDriver is modelled below for the
--     conditionals MSUF uses.
local drivers = {}
env.RegisterStateDriver = function(frame, state, values)
    drivers[#drivers + 1] = { frame = frame, state = state, values = values }
end
local blizzard = false
local function Visible(frame)
    while frame do
        if not frame:IsShown() then return false end
        frame = frame:GetParent()
    end
    return true
end
local function AsBlizzard(fn)
    blizzard = true
    fn()
    blizzard = false
end
local function RunDrivers()
    AsBlizzard(function()
        for _, driver in ipairs(drivers) do
            assert(driver.state == "visibility", "unmodelled driver state " .. tostring(driver.state))
            local result
            for clause in (driver.values .. ";"):gmatch("%s*([^;]+);") do
                local conditions, action = clause:match("^%[(.-)%]%s*(%S+)%s*$")
                if not conditions then conditions, action = "", clause:match("^(%S+)%s*$") end
                local target, ok = "target", true
                for token in conditions:gmatch("[^,]+") do
                    local unit = token:match("^@(.+)$")
                    if unit then target = unit
                    elseif token == "exists" then ok = ok and env.UnitExists(target)
                    elseif token == "noexists" then ok = ok and not env.UnitExists(target)
                    else error("unmodelled macro conditional " .. token) end
                end
                if ok then result = action break end
            end
            if result == "show" then driver.frame:Show() elseif result == "hide" then driver.frame:Hide() end
        end
    end)
end
local function SetRaidSize(count)
    for index = #roster + 1, count do
        local member = { name = "Member" .. index, class = "MAGE", role = "DAMAGER", group = 2, unit = "raid" .. index,
            guid = "G" .. index }
        roster[index], byUnit[member.unit] = member, member
    end
    for index = #roster, count + 1, -1 do
        byUnit[roster[index].unit], roster[index] = nil, nil
    end
end

raid.enabled = false
local container = env.CreateFrame("Frame", "CompactRaidFrameContainer", env.UIParent)
env.CompactRaidFrameContainer = container
container:Show()
local madeVisible = {}
local setParent, show = container.SetParent, container.Show
container.SetParent = function(self, parent)
    local before = Visible(self)
    setParent(self, parent)
    if not before and Visible(self) and not blizzard then madeVisible[#madeVisible + 1] = "SetParent" end
end
container.Show = function(self)
    local before = Visible(self)
    show(self)
    if not before and Visible(self) and not blizzard then madeVisible[#madeVisible + 1] = "Show" end
end
-- Blizzard's GROUP_ROSTER_UPDATE: CompactRaidFrameManager_UpdateContainerVisibility.
local function BlizzardRosterUpdate()
    AsBlizzard(function() if env.IsInRaid() then container:Show() else container:Hide() end end)
end

GF.ApplyBlizzardGroupFrameOwnership("addon-loaded-smoke")
RunDrivers()
assert(not Visible(container), "Blizzard raid frames showed next to the party frames of a small raid")

-- One roster change as the client orders it: Blizzard's manager and the driver
-- react to GROUP_ROSTER_UPDATE first, MSUF's deferred ownership pass after.
local function RosterChange(count)
    SetRaidSize(count)
    BlizzardRosterUpdate()
    RunDrivers()
    GF.ApplyBlizzardGroupFrameOwnership("GROUP_ROSTER_UPDATE")
    RunDrivers()
end

-- (f) The raid grows to six: no MSUF setting changed, Blizzard's frames return.
RosterChange(6)
assert(GF.IsSmallRaidPartyContext() == false, "a six-member raid still counts as small")
assert(Visible(container), "Blizzard raid frames stayed hidden for the session after the raid grew past five")

-- In combat the ownership pass defers, but the secure driver still follows the roster.
world.widgets:SetCombat(true)
RosterChange(4)
assert(not Visible(container), "a raid that shrank to four in combat showed Blizzard's raid frames twice")
RosterChange(7)
assert(Visible(container), "a raid that grew in combat kept Blizzard's raid frames hidden")
world.widgets:SetCombat(false)
RosterChange(3)
assert(not Visible(container), "a small raid after combat showed Blizzard's raid frames twice")

-- The option off in a small raid: handing the container back now would show it
-- from addon code, so it waits for the next roster change that shows it anyway.
party.smallRaidAsParty = false
GF.ApplyBlizzardGroupFrameOwnership("menu")
assert(container:GetParent() ~= env.UIParent and not Visible(container),
    "the container was handed back while the proxy hid it")
RosterChange(6)
assert(container:GetParent() == env.UIParent and Visible(container),
    "turning the option off did not hand Blizzard's raid container back")
RosterChange(3)
assert(Visible(container), "with the option off a small raid still hid Blizzard's raid frames")
assert(#madeVisible == 0, "MSUF made Blizzard's raid frames visible itself (" .. tostring(madeVisible[1])
    .. "); their OnShow would run tainted")
party.smallRaidAsParty = true

print("group_small_raid_party_smoke: PASS")
