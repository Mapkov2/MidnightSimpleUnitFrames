_G = _G or _ENV

-- Issue #142: "By Role" on Raid/Mythic Raid with Preserve raid groups sorted
-- roles inside each subgroup only. The Sort roles across entire raid toggle
-- (sortRolesAcrossRaid) must fill the preserved blocks from ONE raid-wide role
-- order, keep the block cap and subgroup filter semantics coherent, fail open
-- to the native per-subgroup sort while the roster is incomplete, turn the
-- flat Group + Role layout into the raid-wide ROLE order, and never touch Party.
-- Everything here is cold-path header attribute state; no combat work exists.

local headerPath = "MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Headers.lua"

local function Region(parent)
    local region = { parent = parent, shown = false }
    function region:IsShown() return self.shown == true end
    function region:SetShown(value) self.shown = value == true end
    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    function region:ClearAllPoints() self.points = {} end
    function region:SetPoint(...) self.points = { ... } end
    function region:SetAllPoints(target) self.allPoints = target or true end
    function region:SetHeight(value) self.height = value end
    function region:SetWidth(value) self.width = value end
    function region:SetSize(width, height) self.width, self.height = width, height or width end
    function region:GetWidth() return self.width or 0 end
    function region:GetHeight() return self.height or 0 end
    function region:SetParent(value) self.parent = value end
    function region:GetParent() return self.parent end
    function region:EnableMouse() end
    function region:SetClampedToScreen(value) self.clampedToScreen = value end
    function region:CreateTexture() return Region(self) end
    return region
end

local unpackValues = table.unpack or unpack
local function TestFrame(name, parent)
    local frame = Region(parent)
    frame.name = name
    frame.children = {}
    frame.attributes = {}
    function frame:SetAttribute(key, value) self.attributes[key] = value end
    function frame:GetAttribute(key) return self.attributes[key] end
    function frame:GetChildren() return unpackValues(self.children) end
    if parent and parent.children then
        parent.children[#parent.children + 1] = frame
    end
    return frame
end

-- index -> { name, group, role }; a nil name models a lagging roster entry.
local roster = {
    { name = "Tank1", group = 1, role = "TANK" },
    { name = "Dps1", group = 1, role = "DAMAGER" },
    { name = "Heal1", group = 1, role = "HEALER" },
    { name = "Dps2", group = 1, role = "DAMAGER" },
    { name = "Dps3", group = 1, role = "DAMAGER" },
    { name = "Dps4", group = 2, role = "DAMAGER" },
    { name = "Tank2", group = 2, role = "TANK" },
    { name = "Heal2", group = 2, role = "HEALER" },
    { name = "Dps5", group = 2, role = "DAMAGER" },
    { name = "Dps6", group = 2, role = "DAMAGER" },
    { name = "Heal3", group = 3, role = "HEALER" },
    { name = "Dps7", group = 3, role = "DAMAGER" },
}
local liveKind = "raid"
local partyNames = { player = "Player", party1 = "AllyA", party2 = "AllyB" }
local raidRosterInfoCalls = 0
local inCombat = false

local MSUF = {
    GF = {},
    Secrets = {
        IsSecret = function() return false end,
        UnitMissing = function(unit)
            local index = tonumber(unit:match("^raid(%d+)$"))
            if index then return roster[index] == nil or roster[index].name == nil end
            return partyNames[unit] == nil
        end,
    },
}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF
_G.UIParent = TestFrame("UIParent")
_G.InCombatLockdown = function() return inCombat end
_G.GetNumGroupMembers = function() return liveKind == "raid" and #roster or 3 end
_G.GetNumSubgroupMembers = function() return liveKind == "raid" and 4 or 2 end
_G.GetNumArenaOpponentSpecs = function() return 0 end
_G.GetNumArenaOpponents = function() return 0 end
_G.IsInGroup = function() return true end
_G.IsInRaid = function() return liveKind == "raid" end
_G.GetRaidRosterInfo = function(index)
    raidRosterInfoCalls = raidRosterInfoCalls + 1
    local member = roster[index]
    if not member then return nil end
    return member.name, 0, member.group, 80, "Mage", "MAGE", "Zone", true, false, nil, false, member.role
end
_G.UnitName = function(unit)
    local index = tonumber(unit:match("^raid(%d+)$"))
    if index then return roster[index] and roster[index].name or nil end
    return partyNames[unit]
end
_G.UnitClass = function() return "Mage", "MAGE" end
_G.UnitGroupRolesAssigned = function(unit)
    local index = tonumber(unit:match("^raid(%d+)$"))
    return index and roster[index] and roster[index].role or "DAMAGER"
end
-- Headers.lua binds UnitGUID as a load-time upvalue, so the player identity
-- must be switched through this closure state instead of re-stubbing.
local playerRaidUnit = nil
_G.UnitGUID = function(unit)
    if playerRaidUnit and unit == playerRaidUnit then return "guid-player" end
    return "guid-" .. tostring(unit)
end
_G.issecretvalue = function() return false end
_G.CreateFrame = function(_, name, parent) return TestFrame(name, parent) end

local function BaseConf()
    return {
        enabled = true, growth = "DOWN", groupGrowth = "RIGHT",
        showPlayer = true, showSolo = false,
        width = 80, height = 32, spacing = 1,
        unitsPerColumn = 5, maxColumns = 8, preserveRaidGroups = true,
        point = "CENTER", anchorPoint = "CENTER", offsetX = 0, offsetY = 0,
        sortMode = "ROLE", sortByRole = true, roleOrder = "TANK,HEALER,DAMAGER",
        sortRolesAcrossRaid = false,
    }
end
local conf = BaseConf()
MSUF.GF.EnsureDB = function() end
MSUF.GF.GetConf = function() return conf end
MSUF.GF.GetLiveGroupKind = function() return liveKind end
MSUF.GF.GetScaledFrameMetrics = function() return 80, 32, 1 end
MSUF.GF.GetGridMetrics = function(_, count, preservedGroupCount)
    -- Mirror the production geometry bridge: without the setup-local count it
    -- would perform its own full authoritative roster scan.
    local groups = preservedGroupCount
    if groups == nil and conf.preserveRaidGroups == true then
        groups = MSUF.GF.GetPreservedRaidGroupCount(conf)
    end
    return 0, 0, 80 * (groups or 1), 32, count
end
MSUF.GF.ScheduleScan = function() end
MSUF.GF.BeginHeaderLayoutRebind = function() return true end
MSUF.GF.EndHeaderLayoutRebind = function() return true end
MSUF.GF.UntrackFrame = function() end
MSUF.GF.GetConfigDBKey = function(kind) return "gf_" .. kind end

local nativeTableSort = table.sort
local raidSortCalls = 0
table.sort = function(...)
    raidSortCalls = raidSortCalls + 1
    return nativeTableSort(...)
end
local headerChunk, headerErr = loadfile(headerPath)
assert(headerChunk, headerErr)
headerChunk("MidnightSimpleUnitFrames", MSUF)
table.sort = nativeTableSort
local GF = MSUF.GF

local function SetupRaid()
    local callsBefore = raidRosterInfoCalls
    local sortsBefore = raidSortCalls
    local header = assert(GF.SetupHeader("raid", "raid"), "raid header missing")
    assert(raidRosterInfoCalls - callsBefore == #roster,
        "raid setup must read each authoritative roster entry exactly once")
    local sortDelta = raidSortCalls - sortsBefore
    assert(sortDelta <= 1, "raid setup sorted the same roster more than once")
    return header, sortDelta
end

-- The secure gate must reject combat before the setup-local roster snapshot,
-- its sort, or the geometry bridge can perform any work.
inCombat = true
local combatRosterCalls, combatSortCalls = raidRosterInfoCalls, raidSortCalls
assert(GF.SetupHeader("raid", "raid") == nil, "combat setup did not defer protected headers")
assert(raidRosterInfoCalls == combatRosterCalls, "combat setup read the authoritative raid roster")
assert(raidSortCalls == combatSortCalls, "combat setup sorted a preserved raid snapshot")
inCombat = false

local function Block(index)
    return assert(GF.raidGroupHeaders[index], "preserved block " .. index .. " missing")
end

local function AssertBlock(index, nameList, allowed, message)
    local header = Block(index)
    assert(header.attributes.sortMethod == "NAMELIST", message .. ": block " .. index .. " is not NAMELIST")
    assert(header.attributes.nameList == nameList,
        message .. ": block " .. index .. " nameList " .. tostring(header.attributes.nameList) .. " ~= " .. nameList)
    assert(header._msufPreservedGroupAllowed == allowed,
        message .. ": block " .. index .. " allowed " .. tostring(header._msufPreservedGroupAllowed))
end

-- Baseline: preserved groups + By Role keep today's per-subgroup role order.
local _, baselineSorts = SetupRaid()
assert(baselineSorts == 1, "complete preserved raid setup did not sort its one roster snapshot")
assert(Block(1).attributes._msufSortMode == "GROUP_ROLE", "preserved By Role must resolve to GROUP_ROLE by default")
AssertBlock(1, "Tank1,Heal1,Dps1,Dps2,Dps3", true, "baseline")
AssertBlock(2, "Tank2,Heal2,Dps4,Dps5,Dps6", true, "baseline")
AssertBlock(3, "Heal3,Dps7", true, "baseline")

-- Toggle on: one raid-wide role order sliced into the preserved 5-slot blocks.
conf.sortRolesAcrossRaid = true
SetupRaid()
assert(Block(1).attributes._msufSortMode == "ROLE", "raid-wide role sorting must resolve to ROLE on preserved blocks")
AssertBlock(1, "Tank1,Tank2,Heal1,Heal2,Heal3", true, "raid-wide")
AssertBlock(2, "Dps1,Dps2,Dps3,Dps4,Dps5", true, "raid-wide")
AssertBlock(3, "Dps6,Dps7", true, "raid-wide")
AssertBlock(4, "", true, "raid-wide unused block")
for index = 1, 8 do
    assert(Block(index).attributes.groupBy == nil and Block(index).attributes.groupFilter == nil,
        "raid-wide block " .. index .. " leaked native group attributes")
end

-- Player-first and descending order still apply to the raid-wide list.
conf.playerFirstInRole = true
playerRaidUnit = "raid9"
SetupRaid()
AssertBlock(2, "Dps5,Dps1,Dps2,Dps3,Dps4", true, "player-first")
playerRaidUnit = nil
conf.playerFirstInRole = false
conf.sortDescending = true
SetupRaid()
AssertBlock(1, "Dps7,Dps6,Dps5,Dps4,Dps3", true, "descending")
conf.sortDescending = nil

-- Max columns is the block cap: members beyond cap*5 stay hidden and the
-- capped block is retired instead of showing its subgroup.
conf.maxColumns = 2
SetupRaid()
AssertBlock(1, "Tank1,Tank2,Heal1,Heal2,Heal3", true, "block cap")
AssertBlock(2, "Dps1,Dps2,Dps3,Dps4,Dps5", true, "block cap")
AssertBlock(3, "", false, "block cap")
assert(Block(3):IsShown() == false, "capped block must be retired")
conf.maxColumns = 8

-- A subgroup filter still decides WHO is listed, while the blocks that show
-- the survivors stay allowed even when their own subgroup number is filtered.
conf.groupFilter = { [1] = false }
SetupRaid()
AssertBlock(1, "Tank2,Heal2,Heal3,Dps4,Dps5", true, "subgroup filter")
AssertBlock(2, "Dps6,Dps7", true, "subgroup filter")
AssertBlock(3, "", true, "subgroup filter")

-- Incomplete roster: no raid-wide list may be published. The blocks fail open
-- to Blizzard's native per-subgroup role sort and the subgroup filter applies.
roster[5].name = nil
SetupRaid()
for index = 1, 3 do
    local header = Block(index)
    assert(header.attributes.nameList == nil and header.attributes.sortMethod == "INDEX"
        and header.attributes.groupBy == "ASSIGNEDROLE" and header.attributes.groupFilter == tostring(index),
        "incomplete roster must fall back to the native per-subgroup role sort on block " .. index)
end
assert(Block(1)._msufPreservedGroupAllowed == false and Block(2)._msufPreservedGroupAllowed == true,
    "native fallback must honor the subgroup filter again")
roster[5].name = "Dps3"
conf.groupFilter = nil
SetupRaid()
AssertBlock(1, "Tank1,Tank2,Heal1,Heal2,Heal3", true, "roster restored")

-- Toggle off restores the per-subgroup order and mode token.
conf.sortRolesAcrossRaid = false
SetupRaid()
assert(Block(1).attributes._msufSortMode == "GROUP_ROLE", "toggle off must restore GROUP_ROLE")
AssertBlock(1, "Tank1,Heal1,Dps1,Dps2,Dps3", true, "toggle off")

-- Flat layout: Group + Role becomes the raid-wide ROLE order with the toggle.
conf.preserveRaidGroups = false
conf.sortMode = "GROUP_ROLE"
conf.sortByRole = false
conf.sortRolesAcrossRaid = true
local flat = SetupRaid()
assert(flat._msufRaidGroupIndex == nil, "flat layout must not keep preserved block headers")
assert(flat.attributes._msufSortMode == "ROLE" and flat.attributes.sortMethod == "NAMELIST"
    and flat.attributes.nameList == "Tank1,Tank2,Heal1,Heal2,Heal3,Dps1,Dps2,Dps3,Dps4,Dps5,Dps6,Dps7",
    "flat Group + Role with the toggle must publish the raid-wide role order")
conf.sortRolesAcrossRaid = false
SetupRaid()
assert(flat.attributes._msufSortMode == "GROUP_ROLE"
    and flat.attributes.nameList == "Tank1,Heal1,Dps1,Dps2,Dps3,Tank2,Heal2,Dps4,Dps5,Dps6,Heal3,Dps7",
    "flat Group + Role without the toggle must keep the group-major order")

-- Plain flat By Role was already raid-wide; the toggle must not change it.
conf.sortMode = "ROLE"
conf.sortByRole = true
SetupRaid()
local plainRole = flat.attributes.nameList
conf.sortRolesAcrossRaid = true
SetupRaid()
assert(flat.attributes.nameList == plainRole and flat.attributes._msufSortMode == "ROLE",
    "flat By Role must be unaffected by the raid-wide toggle")

-- Party never consults the toggle: its role sort stays the native Blizzard path.
liveKind = "party"
conf = BaseConf()
conf.sortRolesAcrossRaid = true
conf.sortMode = "GROUP_ROLE"
local party = assert(GF.SetupHeader("party", "party"), "party header missing")
assert(party.attributes._msufSortMode == "ROLE" and party.attributes.groupBy == "ASSIGNEDROLE"
    and party.attributes.nameList == nil,
    "party must ignore sortRolesAcrossRaid and keep its native role sort")

print("raid_wide_role_sort_smoke: ok")
