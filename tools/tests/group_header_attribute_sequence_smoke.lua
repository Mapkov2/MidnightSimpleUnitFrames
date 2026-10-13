-- Pin every ordered header attribute write before changing the controller.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local output = {}
local function Encode(value)
    return type(value) .. ":" .. tostring(value):gsub("\\", "\\\\"):gsub("\t", "\\t")
        :gsub("\r", "\\r"):gsub("\n", "\\n")
end
local function Scenario(kind, count, sort, preserve)
    local writes, names = {}, {}
    local h = Harness.New(root, flavor, { beforeBoot = function(world)
        local create = world.env.CreateFrame
        world.env.CreateFrame = function(frameType, name, parent, template)
            local frame = create(frameType, name, parent, template)
            if template == "SecureGroupHeaderTemplate" or template == "SecureGroupPetHeaderTemplate" then
                local rows = {}
                writes[name], names[#names + 1] = rows, name
                local set = frame.SetAttribute
                frame.SetAttribute = function(self, key, value)
                    rows[#rows + 1] = key .. "\t" .. Encode(value)
                    return set(self, key, value)
                end
            end
            return frame
        end
        world.env.UnitGroupRolesAssigned = function(unit)
            local index = tonumber((unit or ""):match("%d+")) or 0
            return index % 3 == 0 and "HEALER" or index % 3 == 1 and "TANK" or "DAMAGER"
        end
        world.env.GetInstanceInfo = function()
            return "Instance", kind == "mythicraid" and "raid" or "none", kind == "mythicraid" and 16 or 0
        end
    end })
    local GF = h.GF
    GF.EnsureDB()
    local conf = GF.GetConf(kind)
    conf.enabled, conf.showSolo = true, false
    conf.sortMode, conf.preserveRaidGroups = sort, preserve
    conf.playerFirstInRole, conf.sortAlphabeticalWithinRole = true, true
    conf.petsEnabled, conf.petsColumns = true, 3
    if kind == "party" then h:SetRoster({ "player", "party1", "party2", "party3", "party4" })
    else h:SetRaid(count) end
    GF.RefreshHeaderLayout()
    h:RunTimers()
    GF.RefreshAdditionalGroups()
    -- Warm no-op, topology/size changes, native/name-list transitions and reuse.
    GF.RefreshHeaderLayout()
    for _, growth in ipairs({ "UP", "LEFT", "RIGHT", "DOWN" }) do
        conf.growth, conf.width = growth, conf.width + 1
        GF.RefreshHeaderLayout()
    end
    conf.sortMode = "INDEX"
    GF.RefreshHeaderLayout()
    conf.sortMode = sort
    GF.RefreshHeaderLayout()
    GF.SetupPriorityHeader(kind, "Name-raid1,Name-raid2", 2)
    GF.SetupPriorityHeader(kind, "Name-raid1,Name-raid2", 2)
    GF.RetireHeader(kind == "party" and "party" or "raid")
    GF.RefreshHeaderLayout()
    GF.RefreshAdditionalGroups()
    assert(#h.violations == 0, tostring(h.violations[1]))
    assert(#h.callMethodErrors == 0, tostring(h.callMethodErrors[1]))
    table.sort(names)
    output[#output + 1] = table.concat({ "CASE", kind, count, sort, tostring(preserve) }, "\t")
    for _, name in ipairs(names) do
        output[#output + 1] = "HEADER\t" .. name
        for _, row in ipairs(writes[name]) do output[#output + 1] = row end
    end
end
for _, sort in ipairs({ "INDEX", "ROLE", "GROUP", "GROUP_ROLE" }) do
    Scenario("party", 5, sort, false)
    for _, count in ipairs({ 10, 20, 25, 40 }) do
        Scenario("raid", count, sort, false)
        Scenario("raid", count, sort, true)
    end
    Scenario("mythicraid", 20, sort, false)
    Scenario("mythicraid", 20, sort, true)
end
local actual = table.concat(output, "\n") .. "\n"
local golden = root .. "/tools/fixtures/group_header_attributes/" .. flavor .. ".tsv"
if arg[3] == "capture" then
    local file = assert(io.open(golden, "wb"))
    file:write(actual)
    file:close()
else
    local file = assert(io.open(golden, "rb"))
    local expected = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    if actual ~= expected then
        local limit = math.min(#actual, #expected)
        local index = 1
        while index <= limit and actual:byte(index) == expected:byte(index) do index = index + 1 end
        error(flavor .. ": header attribute sequence differs at byte " .. index
            .. "\nexpected: " .. expected:sub(index - 70, index + 200)
            .. "\nactual: " .. actual:sub(index - 70, index + 200))
    end
end
print("group_header_attribute_sequence_smoke: ok (" .. flavor .. ": 44 layouts, exact ordered writes)")
