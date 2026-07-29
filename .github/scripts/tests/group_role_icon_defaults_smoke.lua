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

-- Midnight art rides inside the style value ("UXPRO@MIDNIGHT") so one per-indicator dropdown
-- covers every icon type. Packs without midnight art must not gain a phantom second entry.
Check(select(1, GF.SplitIconStyle("UXPRO@MIDNIGHT")) == "UXPRO"
    and select(2, GF.SplitIconStyle("UXPRO@MIDNIGHT")) == true,
    "suffixed style did not split into pack and midnight flag")
Check(select(2, GF.SplitIconStyle("UXPRO")) == false, "plain style reported midnight art")
Check(GF.JoinIconStyle("UXPRO", true) == "UXPRO@MIDNIGHT", "midnight style value did not round-trip")
Check(GF.JoinIconStyle("UXPRO", false) == "UXPRO", "non-midnight style value gained a suffix")

local midnightRole = GF.GetStatusIconTexture("UXPRO@MIDNIGHT", "role", "TANK")
Check(midnightRole == "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Icons\\UXPro\\tank_midnight",
    "suffixed style did not resolve the midnight asset")
Check(GF.GetStatusIconTexture("UXPRO", "role", "TANK")
    == "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Icons\\UXPro\\tank",
    "plain style stopped resolving the classic asset")
Check(GF.StatusIconPackSupports("UXPRO@MIDNIGHT", "role", "TANK", false) == true,
    "suffixed style was not reported as supported")

local styleItems = GF.GetIconStyleItems(false, true)
local seenStyle = {}
for i = 1, #styleItems do seenStyle[styleItems[i].value] = styleItems[i].text end
Check(seenStyle["DEFAULT"] == nil, "per-indicator style list still offers the retired global entry")
Check(seenStyle["UXPRO"] and seenStyle["UXPRO@MIDNIGHT"] == "UX Pro (Midnight)",
    "pack with midnight art is missing its own dropdown entry")
Check(seenStyle["MSUF_ROLES"] and seenStyle["MSUF_ROLES@MIDNIGHT"] == nil,
    "suffix-less pack gained a duplicate midnight entry")
Check(seenStyle["BLIZZARD@MIDNIGHT"] == nil, "Blizzard art gained a midnight entry")
Check(#GF.GetIconStyleItems(true, false) == #GF.ICON_STYLE_ITEMS + 1,
    "legacy style list shape changed")

-- Profiles saved before the split keep "DEFAULT" per indicator plus the retired scope-wide
-- pair; both must still drive the art now that the menu no longer exposes them.
_G.MSUF_DB.gf_party.iconStyle = "UXPRO"
_G.MSUF_DB.gf_party.useMidnightIcons = true
_G.MSUF_DB.gf_party.roleIconStyle = "DEFAULT"
GF.InvalidateConfCache()
Check(GF.GetRoleTexture("party", "TANK")
    == "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Icons\\UXPro\\tank_midnight",
    "legacy global style plus midnight toggle stopped resolving")
local legacyStyle, legacyMidnight = GF.GetIndicatorIconStyle("party", "roleIcon")
Check(legacyStyle == "UXPRO" and legacyMidnight == true,
    "indicator resolver did not inherit the legacy global style and midnight flag")

-- An explicit per-indicator pick wins over the legacy pair.
_G.MSUF_DB.gf_party.roleIconStyle = "DOTS"
GF.InvalidateConfCache()
Check(GF.GetRoleTexture("party", "TANK")
    == "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Icons\\Dots\\tank",
    "explicit indicator style did not override the legacy pair")

-- Non-role indicators carry their own style into the compiled spec now.
_G.MSUF_DB.gf_party.raidMarkerStyle = "DOTS@MIDNIGHT"
GF.InvalidateConfCache()
GF.InvalidateCompiledSpecs("party")
local styledSpec = GF.CompileSpec("party", nil, "party1")
Check(styledSpec.status.raidMarker.style == "DOTS@MIDNIGHT",
    "raid marker style never reached the compiled spec")
Check(styledSpec.status.phase.style == GF.PARTY_DEFAULTS.phaseIconStyle,
    "phase icon style never reached the compiled spec")

print("PASS MSUF role icons: default style, larger sizes, asset resolution, and safe fallback")
