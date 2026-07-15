-- Regression: MSUF's compact role glyphs are the group-frame default, remain
-- readable at the larger default sizes, and safely fall back for non-role
-- status types that the role-only pack does not provide.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

_G.wipe = function(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
    return tbl
end
_G.CopyTable = function(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do copy[key] = _G.CopyTable(child) end
    return copy
end
_G.MSUF_DB = { general = {} }

local MSUF = { UF = {} }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Metadata.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

local GF = assert(MSUF.GF, "group-frame API missing")
Check(GF.PARTY_DEFAULTS.iconStyle == "MSUF_ROLES", "party did not default to MSUF Roles")
Check(GF.PARTY_DEFAULTS.roleIconSize == 16, "party role icon default is not 16px")
Check(GF.PARTY_DEFAULTS.roleIconAnchor == "LEFT" and GF.PARTY_DEFAULTS.roleIconX == 4,
    "party role icon is not safely inset at frame left")
Check(GF.PARTY_DEFAULTS.nameOffsetX == 28,
    "party name does not reserve the enlarged role-icon lane")
Check(GF.PARTY_DEFAULTS.groupNumberLayer == 7,
    "party group number has no independent default layer")
Check(GF.RAID_DEFAULTS.iconStyle == "MSUF_ROLES", "raid did not inherit MSUF Roles")
Check(GF.RAID_DEFAULTS.roleIconSize == 14, "raid role icon default is not 14px")
Check(GF.RAID_DEFAULTS.nameOffsetX == 28,
    "raid name does not reserve the enlarged role-icon lane")
Check(GF.MYTHIC_RAID_DEFAULTS.iconStyle == "MSUF_ROLES", "mythic raid did not inherit MSUF Roles")
Check(GF.MYTHIC_RAID_DEFAULTS.roleIconSize == 14, "mythic role icon default is not 14px")

local expected = {
    TANK = "tank",
    HEALER = "healer",
    DAMAGER = "dps",
}
for role, file in pairs(expected) do
    local path, left, right, top, bottom = GF.GetRoleTexture("party", role)
    Check(path == "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Icons\\MSUFRoles\\" .. file,
        role .. " did not resolve the MSUF role asset")
    Check(left == 0 and right == 1 and top == 0 and bottom == 1, role .. " texture crop changed")
    Check(GF.StatusIconPackSupports("MSUF_ROLES", "role", role, false) == true,
        role .. " was not reported as supported")
end

local leaderPath = GF.GetStatusIconTexture("MSUF_ROLES", "leader", nil, false)
Check(leaderPath == "Interface\\GroupFrame\\UI-Group-LeaderIcon",
    "role-only style did not fall back to Blizzard for leader")
Check(GF.StatusIconPackSupports("MSUF_ROLES", "leader", nil, false) == false,
    "role-only style incorrectly advertised leader support")

GF.EnsureDB()
GF.InvalidateConfCache()
for _, item in ipairs({ { "party", 16 }, { "raid", 14 }, { "mythicraid", 14 } }) do
    GF.InvalidateCompiledSpecs(item[1])
    local compiled = GF.CompileSpec(item[1], nil, "party1")
    Check(compiled.status.role.size == item[2], item[1] .. " compiled role size changed")
    Check(compiled.status.role.anchor == "LEFT" and compiled.status.role.x == 4,
        item[1] .. " compiled role placement changed")
    Check(compiled.text.nameX == 28,
        item[1] .. " compiled name does not clear the role icon")
    Check(compiled.status.role.x + compiled.status.role.size + 4 <= compiled.text.nameX,
        item[1] .. " compiled role icon overlaps the name lane")
end

_G.MSUF_DB.gf_party.showGroupNumber = true
_G.MSUF_DB.gf_party.statusTextLayer = 2
_G.MSUF_DB.gf_party.groupNumberLayer = 29
GF.InvalidateConfCache()
GF.InvalidateCompiledSpecs("party")
local partyWithGroupNumber = GF.CompileSpec("party", nil, "party1")
Check(partyWithGroupNumber.status.raidGroup.enabled == true,
    "party group number did not compile as enabled")
Check(partyWithGroupNumber.status.raidGroup.layer == 29,
    "party group number still reused the dead-text layer")

print("PASS MSUF role icons: default style, larger sizes, asset resolution, and safe fallback")
