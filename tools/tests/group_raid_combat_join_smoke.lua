-- group_raid_combat_join_smoke.lua <repoRoot> <flavor>
--
-- Raid slots stay fixed in combat; a late member receives a frame at regen.
-- A member who joined out of combat before the pull must already have a usable
-- frame, even when the next-frame settle has not run. The configured column cap
-- still binds the native header after catch-up.
--
-- Runs the real core load graph of one flavor on the SecureGroupHeader emulator
-- of tools/tests/group_header_world.lua. Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required")
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

local h = Harness.New(root, flavor)
local GF = h.GF
GF.EnsureDB()
local raid = GF.GetConf("raid")
raid.enabled = true
raid.preserveRaidGroups = false
raid.sortMode = "INDEX"
raid.unitsPerColumn = 5
raid.maxColumns = 8
GF.RefreshHeaderLayout()

local function Settle(count)
    h:SetRaid(count)
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
end

-- Units with a shown frame on the flat raid header, and the first one without.
local function Coverage(header)
    local shown = {}
    for _, child in ipairs(h:Children(header)) do
        local unit = child.attributes.unit
        if unit and child.shown then shown[unit] = true end
    end
    for _, unit in ipairs(h.units) do
        if not shown[unit] then return false, unit end
    end
    return true
end

Settle(10)
local header = GF.headers.raid
Check(header ~= nil and header._msufRaidGroupIndex == nil and header.shown, "the flat raid header did not build")
Check(Coverage(header), "a ten-member raid is missing frames out of combat")
local columns = header.attributes.maxColumns
Check(columns == 8, "a ten-member raid wrote maxColumns=" .. tostring(columns) .. " instead of the configured 8")

-- Joins in lockdown across the column boundary (5 per column, 10 -> 11).
h:EnterCombat()
Settle(11)
local ok, missing = Coverage(header)
Check(not ok and missing == "raid11", "combat join changed the frozen ten-member roster")
Check(#h.violations == 0, "protected write in combat:\n" .. tostring(h.violations[1]))
h:LeaveCombat()
Check(Coverage(header), "a member is missing after the regen catch-up")

-- Joins out of combat; the pull comes before the next-frame settle.
Settle(10)
h:SetRaid(11)
h:Event("GROUP_ROSTER_UPDATE")
h:EnterCombat()
h:RunTimers()
ok, missing = Coverage(header)
Check(ok, "a member who joined just before the pull has no frame: " .. tostring(missing))
Check(#h.violations == 0, "protected write after the pull:\n" .. tostring(h.violations[1]))
h:LeaveCombat()
Check(header.attributes.maxColumns == columns, "the roster changed the column cap")

-- The configured cap still binds.
raid.maxColumns = 2
GF.RefreshHeaderLayout()
h:RunTimers()
Check(header.attributes.maxColumns == 2, "the configured column cap was not written")
local shown = 0
for _, child in ipairs(h:Children(header)) do
    if child.shown and child.attributes.unit then shown = shown + 1 end
end
Check(shown == 10, "maxColumns=2 showed " .. shown .. " frames instead of 10")

print(("group_raid_combat_join_smoke: ok (%s)"):format(flavor))
