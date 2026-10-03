-- group_filter_predicate_smoke.lua <repoRoot> <flavor>
--
-- conf.groupFilter (a native SecureGroupHeader string, or a per-subgroup table
-- from older profile imports) used to be read four ways: the native header filter
-- (Headers ResolveGroupFilter) took a table as an allow-list of true entries, the
-- name lists, the preserved raid blocks and the grid size
-- (MSUF_GroupFrames_DB_Geometry.lua GetLayoutGroupCount) as deny-lists. A
-- deny-list such as { [3] = false } therefore showed group 3 natively while the
-- grid was sized without it. GF.GroupFilterAllowsSubgroup is now the one reading:
--   * a table holding any true is an allow-list, any other a deny-list, and one
--     that would leave no subgroup is ignored; integer keys before string keys;
--   * in a string only numeric tokens name subgroups.
-- Contract on the real load graph (SecureGroupHeader emulator): for every filter
-- form, the native groupFilter attribute, the grid's member count and the
-- name-list path agree with the predicate.
-- Plain Lua 5.1, repo root as arg 1, flavor as arg 2.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required")
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

local h = Harness.New(root, flavor)
local GF = h.GF
local Allows = assert(GF.GroupFilterAllowsSubgroup, "GF.GroupFilterAllowsSubgroup is missing")

-- The predicate itself.
local function Groups(filter)
    local out = {}
    for group = 1, 8 do if Allows(filter, group) then out[#out + 1] = group end end
    return table.concat(out, ",")
end
local ALL = "1,2,3,4,5,6,7,8"
Check(Groups(nil) == ALL and Groups({}) == ALL and Groups("") == ALL, "no filter must allow every subgroup")
Check(Groups({ [3] = false }) == "1,2,4,5,6,7,8", "a deny-list must hide exactly its false subgroups")
Check(Groups({ ["3"] = false, [5] = false }) == "1,2,4,6,7,8", "string keys must deny like integer keys")
Check(Groups({ [1] = true, ["2"] = true, [4] = false }) == "1,2", "a table with a true must be an allow-list")
Check(Groups({ [2] = true, ["2"] = false }) == "2", "the integer key must win over the string key")
Check(Groups({ false, false, false, false, false, false, false, false }) == ALL,
    "a table that leaves no subgroup must be ignored, as the native filter always did")
Check(Groups("1,3") == "1,3" and Groups(" 2 ,WARRIOR") == "2", "numeric string tokens name the subgroups")
Check(Groups("WARRIOR,HEALER") == ALL, "class and role tokens filter units, not subgroups")
Check(Groups("0") == "", "a numeric token that names no subgroup leaves none, as the native filter does")
Check(Allows({ [3] = false }, 0) == true and Allows({ [3] = false }, nil) == true, "out-of-range subgroups are not filtered")

-- Every consumer on the live raid header: 15 members in subgroups 1-3.
GF.EnsureDB()
local raid = GF.GetConf("raid")
raid.enabled, raid.excludeHiddenGroups = true, true
local sortMode = raid.sortMode
h:SetRaid(15)
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()

local function Expected(filter)
    local members, groups = 0, {}
    for group = 1, 3 do if Allows(filter, group) then members = members + 5 end end
    for group = 1, 8 do if Allows(filter, group) then groups[#groups + 1] = tostring(group) end end
    if #groups == 8 then return members, nil end -- every subgroup: no native filter
    return members, table.concat(groups, ",")
end

local CASES = {
    { label = "deny-list", filter = { [3] = false } },
    { label = "string-key deny-list", filter = { ["2"] = false } },
    { label = "allow-list", filter = { [1] = true, ["3"] = true } },
    { label = "full table", filter = { true, false, true, true, true, true, true, true } },
    { label = "empty deny-list", filter = { false, false, false, false, false, false, false, false } },
}
for _, case in ipairs(CASES) do
    raid.groupFilter = case.filter
    raid.sortMode, raid.playerFirstInRole = sortMode, false
    GF.InvalidateLayoutRoster()
    GF.RefreshHeaderLayout()
    h:RunTimers()
    local header = GF.headers.raid
    Check(header ~= nil, case.label .. ": no raid header")
    local members, native = Expected(case.filter)
    Check(header.attributes.groupFilter == native, string.format("%s: native filter %s, the predicate allows %s",
        case.label, tostring(header.attributes.groupFilter), tostring(native)))
    Check(GF.GetLayoutGroupCount("raid") == members, string.format("%s: the grid counts %d members, the header shows %d",
        case.label, GF.GetLayoutGroupCount("raid"), members))
    -- The name-list path (player first within a role) filters by the same reading.
    raid.sortMode, raid.playerFirstInRole = "ROLE", true
    GF.RefreshHeaderLayout()
    h:RunTimers()
    local nameList = GF.headers.raid.attributes.nameList
    local listed = 0
    for _ in tostring(nameList or ""):gmatch("[^,]+") do listed = listed + 1 end
    Check(nameList ~= nil and listed == members, string.format("%s: the name list holds %d members, the header %d",
        case.label, listed, members))
end
raid.groupFilter, raid.sortMode, raid.playerFirstInRole = nil, sortMode, false

print(string.format("group_filter_predicate_smoke: ok (%s, %d filter forms)", flavor, #CASES))
