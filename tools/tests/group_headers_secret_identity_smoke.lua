-- group_headers_secret_identity_smoke.lua <repoRoot> <flavor>
--
-- The group header name lists (MSUF_UF_Group_Headers.lua UnitFullName/UnitRole)
-- read UnitName, SecretWhenUnitNameIdentityRestricted, and UnitGroupRolesAssigned,
-- SecretWhenUnitIdentityRestricted (Blizzard_APIDocumentationGenerated/
-- UnitDocumentation.lua). Both results were truth-tested, compared and
-- concatenated without issecretvalue; a secret party name reached the
-- published nameList (table.concat of a secret raises in the client too).
-- Contract on the real load graph (SecureGroupHeader emulator): a secret name
-- keeps its unit out of the name list, a secret role sorts as DAMAGER, and in
-- both helpers issecretvalue runs before any other use of the value.
-- Plain Lua 5.1, repo root as arg 1, flavor as arg 2.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required")
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

-- Secret stand-ins as strict as plain Lua allows: any concatenation, arithmetic,
-- ordering, indexing or length raises.
local function Secret(label)
    local function Raise() error("attempt to use a secret value (" .. label .. ")", 2) end
    return setmetatable({}, { __concat = Raise, __lt = Raise, __le = Raise, __index = Raise,
        __add = Raise, __sub = Raise, __len = Raise, __call = Raise, __tostring = function() return label end })
end
local SECRET_NAME, SECRET_ROLE = Secret("name"), Secret("role")

local h = Harness.New(root, flavor, { beforeBoot = function(harness)
    local env = harness.env
    env.issecretvalue = function(value) return rawequal(value, SECRET_NAME) or rawequal(value, SECRET_ROLE) end
    local unitName, unitRole = env.UnitName, env.UnitGroupRolesAssigned
    env.UnitName = function(unit)
        if unit == "party2" then return SECRET_NAME, nil end
        return unitName(unit)
    end
    env.UnitGroupRolesAssigned = function(unit)
        if unit == "party1" then return SECRET_ROLE end
        if unit == "party3" then return "TANK" end
        return unitRole(unit)
    end
end })
local GF = h.GF
GF.EnsureDB()
local party = GF.GetConf("party")
party.enabled, party.showPlayer = true, true
-- Player first within a role publishes a name list built from UnitName.
party.sortMode, party.playerFirstInRole = "ROLE", true
GF.RefreshHeaderLayout()
h:SetRoster({ "player", "party1", "party2", "party3" })
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()

local header = GF.headers.party
Check(header ~= nil, "the party header did not build")
local nameList = header.attributes.nameList
Check(type(nameList) == "string", "no player-first name list was published")
Check(not nameList:find("party2", 1, true), "a secret name reached the published name list")
local order = {}
for name in nameList:gmatch("[^,]+") do order[#order + 1] = name end
Check(table.concat(order, ",") == "Name-party3,Name-player,Name-party1",
    "a secret role must sort as DAMAGER behind the tank, the player first within the role: " .. nameList)

-- Source order: issecretvalue before any other use of each value.
local file = assert(io.open(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Headers.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local nameBody = assert(source:match("\nlocal function UnitFullName%(unit%)\n(.-)\nend\n"), "UnitFullName moved")
local roleBody = assert(source:match("\nlocal function UnitRole%(unit%)\n(.-)\nend\n"), "UnitRole moved")
local guardName = nameBody:find("issecretvalue(name)", 1, true)
Check(guardName and guardName < nameBody:find("not name", 1, true), "UnitFullName tests the name before issecretvalue")
local guardRole = roleBody:find("issecretvalue(role)", 1, true)
Check(guardRole and guardRole < roleBody:find('role == "TANK"', 1, true)
    and not roleBody:find("UnitGroupRolesAssigned(unit) or", 1, true), "UnitRole tests the role before issecretvalue")

print(string.format("group_headers_secret_identity_smoke: ok (%s: secret name kept out, secret role sorted as DAMAGER)", flavor))
