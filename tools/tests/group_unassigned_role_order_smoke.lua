-- group_unassigned_role_order_smoke.lua <repoRoot>
--
-- Role sort has two paths. The native one is SecureGroupHeader's ASSIGNEDROLE
-- grouping with groupingOrder RoleOrder(conf) = "TANK,HEALER,DAMAGER,NONE":
-- members without an assigned role sort after DPS (Blizzard
-- SecureGroupHeaders.lua groups by the roster's assignedRole). Player first in
-- role or class priority switch the header to a NAMELIST built in Lua. That
-- list used to map an unassigned role to DAMAGER, so the toggle interleaved
-- unassigned members with DPS by raid index and visibly reordered the raid.
--
-- Pins, on the real group runtime and an emulated SecureGroupHeader
-- (tools/tests/group_header_world.lua): the native path still groups by
-- ASSIGNEDROLE with NONE last, and the name list orders unassigned members
-- after every DPS, in raid index order.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")

local ROLES = { "DAMAGER", "NONE", "HEALER", "NONE", "TANK", "DAMAGER", "NONE", "DAMAGER" }
local EXPECTED = "Name-raid5,Name-raid3,Name-raid1,Name-raid6,Name-raid8,Name-raid2,Name-raid4,Name-raid7"

local failures = 0
local function Check(ok, message)
    if not ok then
        failures = failures + 1
        print("FAIL " .. message)
    end
end

local function Run(flavor)
    -- Installed before boot: the group runtime caches both APIs at load.
    local h = Harness.New(root, flavor, { beforeBoot = function(hh)
        local function Index(unit)
            return tonumber(tostring(unit):match("^raid(%d+)$"))
        end
        hh.env.UnitGroupRolesAssigned = function(unit)
            local index = Index(unit)
            return index and ROLES[index] or "NONE"
        end
        hh.env.GetRaidRosterInfo = function(index)
            local unit = hh.units[index]
            if not unit then return nil end
            return "Name-" .. unit, 0, 1, 60, "Warrior", "WARRIOR", nil, true, false, nil, false, ROLES[index]
        end
    end })
    local GF = h.GF
    GF.EnsureDB()
    local raid = GF.GetConf("raid")
    raid.enabled = true
    raid.preserveRaidGroups = false
    raid.sortMode = "ROLE"
    raid.sortClassPriority = false
    raid.playerFirstInRole = false
    raid.roleOrder = nil
    h:SetRaid(#ROLES)
    GF.InvalidateLayoutRoster()
    GF.RefreshHeaderLayout()
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()

    local header = GF.headers.raid
    Check(header ~= nil, flavor .. ": no raid header")
    if not header then return end
    local attributes = header.attributes
    Check(attributes.groupBy == "ASSIGNEDROLE", flavor .. ": native role sort groups by " .. tostring(attributes.groupBy))
    Check(attributes.groupingOrder == "TANK,HEALER,DAMAGER,NONE",
        flavor .. ": native role order " .. tostring(attributes.groupingOrder))

    -- Player first in role: the same order through the name list.
    raid.playerFirstInRole = true
    GF.InvalidateLayoutRoster()
    GF.RefreshHeaderLayout()
    h:RunTimers()
    Check(attributes.sortMethod == "NAMELIST", flavor .. ": player first did not switch to a name list ("
        .. tostring(attributes.sortMethod) .. ")")
    Check(attributes.nameList == EXPECTED, ("%s: name list %s, expected %s")
        :format(flavor, tostring(attributes.nameList), EXPECTED))
end

for _, flavor in ipairs({ "Mainline", "Vanilla" }) do Run(flavor) end

if failures > 0 then error(("group unassigned role order smoke: %d failure(s)"):format(failures)) end
print("group unassigned role order smoke: ok (Mainline, Vanilla)")
