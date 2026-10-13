-- A secret subgroup must never be tested, converted or enter a partial name list.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
local secret, restricted = Secrets.New("number"), false
local h = Harness.New(root, flavor, { beforeBoot = function(world)
    local env, roster = world.env, world.env.GetRaidRosterInfo
    env.issecretvalue = Secrets.IsSecret
    env.GetRaidRosterInfo = function(index)
        local name, rank, subgroup, level, class, classFile = roster(index)
        if restricted and index == 3 then subgroup = secret end
        return name, rank, subgroup, level, class, classFile, nil, true, nil, nil, nil, "DAMAGER"
    end
    local number = env.tonumber
    env.tonumber = function(value, ...)
        assert(not Secrets.IsSecret(value), "secret subgroup reached tonumber")
        return number(value, ...)
    end
end })
local GF = h.GF
GF.EnsureDB()
local raid = GF.GetConf("raid")
raid.enabled = true
GF.RefreshHeaderLayout()
h:SetRaid(10)
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
restricted = true
local path = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Headers.lua"
local errors = {}
local function Case(label, fn)
    local stop = Secrets.Watch(path, { strict = true })
    local ok, err = pcall(fn)
    local violations = stop()
    if not ok then errors[#errors + 1] = label .. ": " .. tostring(err) end
    for _, violation in ipairs(violations) do errors[#errors + 1] = label .. ": " .. violation end
end
Case("preserved count", function()
    raid.maxColumns, raid.collapseEmptyGroups = 8, true
    assert(GF.GetPreservedRaidGroupCount(raid) == 8, "unknown subgroup narrowed the preserved grid")
end)
Case("player-first list", function()
    raid.collapseEmptyGroups = false
    raid.sortMode, raid.playerFirstInRole = "ROLE", true
    GF.RefreshHeaderLayout()
    assert(GF.headers.raid.attributes.nameList == nil, "secret subgroup produced a partial name list")
end)
Case("frozen list", function()
    raid.sortMode, raid.playerFirstInRole = "GROUP_ROLE", false
    GF.RefreshHeaderLayout()
    h:EnterCombat()
    assert(GF.headers.raid.attributes.nameList == nil, "secret subgroup produced a partial frozen name list")
    h:LeaveCombat()
end)
assert(#errors == 0, table.concat(errors, "\n"))
assert(#h.violations == 0, tostring(h.violations[1]))
print("group_headers_secret_subgroup_smoke: ok (" .. flavor .. ": count, name list, freeze)")
