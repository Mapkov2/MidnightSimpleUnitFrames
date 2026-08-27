_G = _G or _ENV

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
    function region:CreateTexture()
        return Region(self)
    end
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

local SECRET_ARENA_SIZE = {}
local subgroupCount = 2
local arenaSpecCount = 3
local arenaOpponentCount = 3
local arenaParty = true
local unitNames = {
    player = "Player",
    party1 = "AllyA",
    party2 = "AllyB",
}

local MSUF = {
    GF = {},
    Secrets = {
        IsSecret = function(value) return value == SECRET_ARENA_SIZE end,
        UnitMissing = function(unit) return unitNames[unit] == nil end,
    },
}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF
_G.UIParent = TestFrame("UIParent")
_G.InCombatLockdown = function() return false end
_G.GetNumGroupMembers = function() return subgroupCount + 1 end
_G.GetNumSubgroupMembers = function() return subgroupCount end
_G.GetNumArenaOpponentSpecs = function() return arenaSpecCount end
_G.GetNumArenaOpponents = function() return arenaOpponentCount end
_G.IsInGroup = function() return true end
_G.IsInRaid = function() return false end
_G.UnitName = function(unit) return unitNames[unit] end
_G.UnitClass = function() return "Warrior", "WARRIOR" end
_G.UnitGroupRolesAssigned = function() return "DAMAGER" end
_G.UnitGUID = function(unit) return unitNames[unit] and ("guid-" .. unit) or nil end
_G.issecretvalue = function(value) return value == SECRET_ARENA_SIZE end
_G.CreateFrame = function(_, name, parent)
    return TestFrame(name, parent)
end

local conf = {
    enabled = true,
    growth = "DOWN",
    showPlayer = true,
    showSolo = false,
    unitsPerColumn = 5,
    maxColumns = 8,
    point = "CENTER",
    offsetX = 0,
    offsetY = 0,
    sortMode = "ROLE",
    sortByRole = true,
    playerFirstInRole = true,
}
MSUF.GF.EnsureDB = function() end
MSUF.GF.GetConf = function() return conf end
MSUF.GF.IsArenaPartyContext = function() return arenaParty end
MSUF.GF.GetLiveGroupKind = function() return "party" end
MSUF.GF.GetScaledFrameMetrics = function() return 80, 32, 1 end
MSUF.GF.GetGridMetrics = function(_, count) return 0, 0, 80, 32, count end
MSUF.GF.ScheduleScan = function() end
MSUF.GF.BeginHeaderLayoutRebind = function() return true end
MSUF.GF.EndHeaderLayoutRebind = function() return true end

local headerChunk, headerErr = loadfile(headerPath)
assert(headerChunk, headerErr)
headerChunk("MidnightSimpleUnitFrames", MSUF)

local function SetupParty()
    return assert(MSUF.GF.SetupHeader("party", "party"), "party header missing")
end

local function AssertNativeRoleFallback(header, message)
    assert(header.attributes.nameList == nil
        and header.attributes.sortMethod == "INDEX"
        and header.attributes.groupBy == "ASSIGNEDROLE", message)
end

local header = SetupParty()
assert(header.attributes.sortMethod == "NAMELIST"
    and header.attributes.nameList == "Player,AllyA,AllyB",
    "complete three-player Arena roster did not retain Player-first role sorting")

-- Original issue #129 guard: even with a known fixed 3v3 size, one lagging
-- party identity must fail open instead of hiding that teammate.
unitNames.party2 = nil
header = SetupParty()
AssertNativeRoleFallback(header,
    "known 3v3 size published a partial hard filtering nameList")

-- Issue #129 residual: during a Shuffle side swap the fixed spec count can be
-- briefly unknown while GetNumSubgroupMembers already exposes a partial
-- roster. That count must not authorize a hard filtering nameList.
subgroupCount = 1
arenaSpecCount = 0
arenaOpponentCount = 0
header = SetupParty()
AssertNativeRoleFallback(header,
    "partial Shuffle subgroup count published a hard filtering nameList")

-- Blizzard defines GetNumArenaOpponents as whoever currently happens to be
-- present when no fixed size is known. A positive partial value is therefore
-- still not allowed to authorize a hard name list.
unitNames.party2 = nil
subgroupCount = 1
arenaOpponentCount = 2
header = SetupParty()
AssertNativeRoleFallback(header,
    "partial GetNumArenaOpponents value authorized a filtering nameList")

-- A positive fixed pre-match spec count restores Player-first sorting once
-- every expected identity is readable.
unitNames.party2 = "AllyB"
arenaSpecCount = 3
header = SetupParty()
assert(header.attributes.sortMethod == "NAMELIST"
    and header.attributes.nameList == "Player,AllyA,AllyB",
    "fixed Arena-size signal did not restore the complete Arena list")

-- Secret or otherwise unreadable Arena counts also fail open. Do not infer
-- completeness from a transiently complete subgroup count alone.
subgroupCount = 2
arenaSpecCount = SECRET_ARENA_SIZE
arenaOpponentCount = 0
header = SetupParty()
AssertNativeRoleFallback(header,
    "secret Arena-size state did not fail open to native roster sorting")

-- The guard is Arena-only. PvE Party retains its established four-token scan,
-- including its historical partial Player-first name list behavior.
arenaParty = false
unitNames.party2 = nil
subgroupCount = 1
arenaSpecCount = 0
header = SetupParty()
assert(header.attributes.sortMethod == "NAMELIST"
    and header.attributes.nameList == "Player,AllyA",
    "Arena completeness guard changed the PvE Party name-list path")

-- Issue #135: the Party header must publish the configured native column cap.
-- Keep that cap independent of the current roster so Blizzard can grow the
-- secure header during combat without an insecure MSUF attribute rewrite.
subgroupCount = 1
unitNames.party2 = nil
conf.unitsPerColumn = 1
conf.maxColumns = 5
header = SetupParty()
assert(header.attributes.unitsPerColumn == 1 and header.attributes.maxColumns == 5,
    "Party 1x5 did not reach the SecureGroupHeader attributes")

subgroupCount = 4
unitNames.party2 = "AllyB"
unitNames.party3 = "AllyC"
unitNames.party4 = "AllyD"
local nativeColumns = math.min(math.ceil((subgroupCount + 1) / header.attributes.unitsPerColumn),
    header.attributes.maxColumns)
assert(math.min(header.attributes.unitsPerColumn * nativeColumns, subgroupCount + 1) == 5,
    "Party 1x5 native layout hid a party member")

print("arena_party_roster_fail_open_smoke: ok")
