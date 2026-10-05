-- group_preserved_role_block_count_smoke.lua <repoRoot>
--
-- Preserve raid groups + Group + Role with "Sort roles across the entire raid"
-- fills the preserved blocks from one raid-wide role order: block N holds the
-- Nth five names, whatever subgroup they came from. The subgroup filter
-- therefore does not hide a block (Headers PreservedBlockAllowed), and the
-- layout's block count (anchor, group border, stable grid position) must count
-- the same blocks the headers show. With Collapse empty groups and the filter
-- "1,3", ten members in subgroups 1 and 3 fill blocks 1 and 2; the count used to
-- apply the subgroup filter to block 2 and size everything for one block.
--
-- Real group runtime on an emulated SecureGroupHeader
-- (tools/tests/group_header_world.lua). Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")

local failures = 0
local function Check(ok, message)
    if not ok then
        failures = failures + 1
        print("FAIL " .. message)
    end
end

local function Run(flavor, sortRolesAcrossRaid)
    -- Ten members: raid1-5 in subgroup 1, raid6-10 in subgroup 3. Installed
    -- before boot: the group runtime caches the API at load.
    local h = Harness.New(root, flavor, { beforeBoot = function(hh)
        hh.env.GetRaidRosterInfo = function(index)
            local unit = hh.units[index]
            if not unit then return nil end
            local subgroup = index <= 5 and 1 or 3
            return "Name-" .. unit, 0, subgroup, 60, "Warrior", "WARRIOR", nil, true
        end
    end })
    local GF = h.GF
    GF.EnsureDB()
    local raid = GF.GetConf("raid")
    raid.enabled = true
    raid.preserveRaidGroups = true
    raid.sortMode = "GROUP_ROLE"
    raid.sortRolesAcrossRaid = sortRolesAcrossRaid
    raid.collapseEmptyGroups = true
    raid.groupFilter = "1,3"

    local recorded
    local ensure = GF.EnsureStableGridPosition
    GF.EnsureStableGridPosition = function(kind, count, conf, preservedGroupCount, ...)
        if kind == "raid" then recorded = preservedGroupCount end
        return ensure(kind, count, conf, preservedGroupCount, ...)
    end

    h:SetRaid(10)
    GF.InvalidateLayoutRoster()
    GF.RefreshHeaderLayout()
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()

    local shown = 0
    for _, header in pairs(GF.raidGroupHeaders or {}) do
        if header._msufPreservedGroupAllowed == true then shown = shown + 1 end
    end
    local label = ("%s, roles across raid=%s"):format(flavor, tostring(sortRolesAcrossRaid))
    Check(shown == 2, ("%s: %d preserved blocks shown, expected 2"):format(label, shown))
    Check(recorded == shown, ("%s: layout sized for %s blocks, %d shown"):format(label, tostring(recorded), shown))
    GF.EnsureStableGridPosition = ensure
end

for _, flavor in ipairs({ "Mainline", "Vanilla" }) do
    Run(flavor, true)
    Run(flavor, false) -- subgroup blocks 1 and 3: the filter applies, still two blocks
end

if failures > 0 then error(("group preserved role block count smoke: %d failure(s)"):format(failures)) end
print("group preserved role block count smoke: ok (Mainline, Vanilla)")
