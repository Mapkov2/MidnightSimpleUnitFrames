-- Priority roster and hotkey reads must guard values before any Lua operation.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
Secrets.Install()
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local path = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Priority.lua"
local file = assert(io.open(path, "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local lines = {}
for line in (source .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
local hidden, secret = {}, Secrets.New("string")

-- Lua 5.1 cannot trap a table's truth conversion. Check the executed API call
-- site as well: an `or` after the call consumes its result before any guard.
local function DirectRead(api)
    local caller = debug.getinfo(3, "Sl")
    if caller.source:find("MSUF_UF_Group_Priority.lua", 1, true) then
        local line = lines[caller.currentline]
        assert(not line:find(api .. "%b()%s+or%s"), "secret truth test: " .. line)
    end
end

local h = Harness.New(root, "Mainline", { beforeBoot = function(world)
    world.env.type, world.env.issecretvalue = type, issecretvalue
    for _, api in ipairs({ "UnitName", "UnitGUID", "UnitGroupRolesAssigned", "GetRaidRosterInfo" }) do
        local plain = world.env[api]
        world.env[api] = function(...)
            local caller = debug.getinfo(2, "S")
            if hidden[api] and caller.source:find("MSUF_UF_Group_Priority.lua", 1, true) then
                DirectRead(api)
                return secret
            end
            if api == "UnitName" and (...) == "player" then return "Name-player" end
            return plain(...)
        end
    end
end })
local GF = h.GF
GF.EnsureDB()
h:SetRoster({ "player", "party1", "party2" })
local conf = GF.GetPriorityConf()
conf.enabled, conf.autoTanks = true, true
local stop = Secrets.Watch(path)
hidden.UnitGroupRolesAssigned = true
local _, count = GF.ResolvePrioritySelection()
assert(count == 0, "a secret role selected an automatic tank")
hidden.UnitGUID = true
assert(GF.TogglePriorityUnit("party1"), "plain name must still pin when GUID and role are secret")
local names, pinned = GF.ResolvePrioritySelection()
assert(pinned == 1 and names == "Name-party1", "name-only priority pin stopped resolving")
hidden.UnitName = true
assert(GF.TogglePriorityUnit("party2") == false, "a secret party name became a pin")
local _, anonymous = GF.ResolvePrioritySelection()
assert(anonymous == 0, "secret names entered the name list")
hidden.UnitName = nil
h:SetRaid(3)
hidden.GetRaidRosterInfo = true
assert(GF.TogglePriorityUnit("raid1") == false, "a secret raid name became a pin")
local _, raidCount = GF.ResolvePrioritySelection()
assert(raidCount == 0, "secret raid names entered the name list")
local violations = stop()
assert(#violations == 0, table.concat(violations, "\n"))
print("group_priority_secret_identity_smoke: PASS")
