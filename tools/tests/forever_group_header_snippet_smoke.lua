-- Forever group headers use the secure snippet like every other client.
--
--   lua tools/tests/forever_group_header_snippet_smoke.lua <repo root>
--
-- WoW Forever builds before 1.60.1.70009 could not compile secure snippets:
-- Blizzard_EnvironmentCleanup cleared loadstring_untainted before
-- RestrictedExecution.lua cached it. 70009 orders Blizzard_RestrictedAddOnEnvironment
-- first (unconditional OptionalDep, as on live), and tools/audit-classic-ui-source.ps1
-- pins that. MSUF therefore dropped its snippet-free Forever header path. This
-- smoke runs the real MSUF_UF_Group_Headers.lua against a SecureGroupHeader stub
-- and fails if any client, Forever included, builds a header without the snippet
-- or brings back the attribute copies, pre-created buttons or OnShow hook.
local repo = assert(arg[1], "repository root is required"):gsub("\\", "/"):gsub("/$", "")
local headersPath = repo .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Headers.lua"

local function Check(condition, message)
    if not condition then error(message, 2) end
end

-- MSUF_GroupFrames_DB.lua, the first group file on every client, owns the saved
-- Priority anchor modes the header code compares against.
local function PriorityAnchorModes()
    local file = assert(io.open(repo .. "/MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB.lua", "rb"))
    local source = file:read("*a")
    file:close()
    local body = assert(source:match("\nGF%.PRIORITY_ANCHOR_MODES = (%b{})"), "the group DB lost GF.PRIORITY_ANCHOR_MODES")
    return assert(loadstring("return " .. body))()
end

local inGroup, inRaid = true, false
local partyUnits = { "player", "party1", "party2" }
local raidCount = 0
local rosterGroups = {}

local function NewRegion(parent)
    local frame = { parent = parent, attributes = {}, shown = false, width = 0, height = 0, hooks = {} }
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:SetWidth(width) self.width = width end
    function frame:SetHeight(height) self.height = height end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:ClearAllPoints() end
    function frame:SetPoint(...) self.point = {...} end
    function frame:EnableMouse() end
    function frame:SetClampedToScreen() end
    function frame:SetParent(value) self.parent = value end
    function frame:GetParent() return self.parent end
    function frame:IsShown() return self.shown end
    function frame:IsVisible()
        if not self.shown then return false end
        return not (self.parent and self.parent.IsVisible) or self.parent:IsVisible()
    end
    function frame:IsProtected() return self.protected == true end
    function frame:SetRoundLayoutToNearestPixel(enabled) self.roundLayout = enabled end
    function frame:RegisterForClicks(clicks) self.clicks = clicks end
    function frame:GetAttribute(key) return self.attributes[key] end
    function frame:SetAttribute(key, value) self.attributes[key] = value end
    function frame:HookScript(kind, callback)
        self.hooks[kind] = self.hooks[kind] or {}
        self.hooks[kind][#self.hooks[kind] + 1] = callback
    end
    function frame:Show()
        if self.shown then return end
        self.shown = true
        if self.OnShow then self:OnShow() end
        for _, callback in ipairs(self.hooks.OnShow or {}) do callback(self) end
    end
    function frame:Hide() self.shown = false end
    function frame:GetChildren() return unpack(self.children or {}) end
    function frame:RegisterEvent() end
    function frame:UnregisterAllEvents() end
    return frame
end

-- The units SecureGroupHeader's GetGroupHeaderType would list for this header.
local function HeaderUnits(header)
    local units = {}
    if inRaid and header.attributes.showRaid then
        for index = 1, raidCount do units[#units + 1] = "raid" .. index end
    elseif inGroup and header.attributes.showParty then
        for index = 1, #partyUnits do
            local unit = partyUnits[index]
            if unit ~= "player" or header.attributes.showPlayer then units[#units + 1] = unit end
        end
    end
    return units
end

-- Blizzard_RestrictedAddOnEnvironment/SecureGroupHeaders.lua configureChildren,
-- reduced to button creation, SetupUnitButtonConfiguration and unit assignment.
local function UpdateHeader(header)
    if not header:IsVisible() then return end
    local units = HeaderUnits(header)
    local unitCount = #units
    local unitsPerColumn = header.attributes.unitsPerColumn
    local numColumns
    if unitsPerColumn and unitCount > unitsPerColumn then
        numColumns = math.min(math.ceil(unitCount / unitsPerColumn), header.attributes.maxColumns or 1)
    else
        unitsPerColumn = unitCount
        numColumns = 1
    end
    local numDisplayed = math.min(unitsPerColumn * numColumns, unitCount)
    local needButtons = math.max(1, numDisplayed)
    for index = 1, needButtons do
        if not header.attributes["child" .. index] then
            local button = NewRegion(header)
            button.protected = true
            header.children = header.children or {}
            header.children[#header.children + 1] = button
            if type(header.attributes.initialConfigFunction) == "string" then
                button.snippetConfigured = true
            end
            local names = header.attributes._initialAttributeNames
            if type(names) == "string" then
                for name in names:gmatch("[^,]+") do
                    button:SetAttribute(name, header.attributes["_initialAttribute-" .. name])
                end
            end
            header.attributes["child" .. index] = button
        end
    end
    for index = 1, numDisplayed do
        local button = header.attributes["child" .. index]
        button:SetAttribute("unit", units[index])
        button.shown = true
    end
end

local function NewGroupHeader(parent)
    local header = NewRegion(parent)
    header.protected = true
    header.OnShow = UpdateHeader
    function header:SetAttribute(key, value)
        self.attributes[key] = value
        -- SecureGroupHeader_OnAttributeChanged; child refs are set without response.
        if not key:find("^child") and not key:find("^frameref") then UpdateHeader(self) end
    end
    return header
end

local function Load(isForever)
    local UIParentStub = NewRegion(nil)
    UIParentStub.shown = true
    _G.UIParent = UIParentStub
    _G.PetBattleFrameHider = nil
    _G.CreateFrame = function(_, _, parent, template)
        if template == "SecureGroupHeaderTemplate" then return NewGroupHeader(parent) end
        return NewRegion(parent)
    end
    local conf = {
        party = {
            enabled = true, showPlayer = true, showSolo = false,
            width = 120, height = 40, spacing = 1, growth = "DOWN",
            unitsPerColumn = 5, maxColumns = 1, sortMode = "INDEX", point = "CENTER",
        },
        raid = {
            enabled = true, showPlayer = true, showSolo = false,
            width = 80, height = 32, spacing = 1, growth = "DOWN",
            unitsPerColumn = 5, maxColumns = 8, sortMode = "INDEX", point = "CENTER",
        },
    }
    local ns = {
        Client = { IsForever = isForever, IsClassic = false },
        -- Kernel/MSUF_Require.lua: hard dependencies resolve from _G and raise when absent.
        Require = function(name)
            local value = _G[name]
            assert(type(value) == "function" or type(value) == "table", "fixture lacks " .. tostring(name))
            return value
        end,
        -- Flat raid headers build a name list, which reads unit tokens.
        UF = { IsUnitToken = function(unit) return type(unit) == "string" and unit ~= "" end },
        GF = {},
        Secrets = { UnitMissing = function(unit) return unit == "party3" or unit == "party4" end },
    }
    local GF = ns.GF
    GF.PRIORITY_ANCHOR_MODES = PriorityAnchorModes()
    GF.GetConf = function(kind) return kind == "party" and conf.party or conf.raid end
    local priorityConf = { spacing = 2, growth = "DOWN", anchorMode = "FREE" }
    GF.GetPriorityConf = function() return priorityConf end
    GF.GetScaledFrameMetrics = function(kind)
        local c = GF.GetConf(kind)
        return c.width, c.height, c.spacing
    end
    GF.GetLiveGroupKind = function() return inRaid and "raid" or (inGroup and "party" or nil) end
    GF.GetAnchorPoint = function(c) return c and c.point or "CENTER" end
    GF.ResolveAnchorPoint = function(_, c)
        local point = GF.GetAnchorPoint(c)
        return point, point
    end
    dofile(repo .. "/tools/tests/group_dependencies.lua")(ns)
    _G.MSUF_NS = ns
    assert(loadfile(headersPath))("MidnightSimpleUnitFrames", ns)
    return GF, conf
end

_G.InCombatLockdown = function() return false end
_G.IsInGroup = function() return inGroup end
_G.IsInRaid = function() return inRaid end
_G.GetNumGroupMembers = function() return inRaid and raidCount or #partyUnits end
_G.GetNumSubgroupMembers = function() return #partyUnits - 1 end
_G.GetRaidRosterInfo = function(index) return "Member" .. index, nil, rosterGroups[index] or 1, nil, nil, index == 1 and "PRIEST" or "MAGE" end
_G.UnitName = function(unit) return tostring(unit) end
_G.UnitGUID = function(unit) return tostring(unit) .. "-guid" end
_G.UnitClass = function(unit) return "Class", unit == "party1" and "MAGE" or unit == "party2" and "WARRIOR" or "PRIEST" end
_G.UnitGroupRolesAssigned = function() return "DAMAGER" end
_G.issecretvalue = function() return false end
_G.MSUF_ScheduleLateAnchorReanchor = function() end
_G.MSUF_Snap = function(_, value) return value end
-- Kernel/MSUF_Util.lua: protected frames refuse the call in combat.
_G.MSUF_SetRoundLayoutToNearestPixel = function(frame, enabled)
    if not (frame and frame.SetRoundLayoutToNearestPixel) then return false end
    if _G.InCombatLockdown() and frame:IsProtected() then return false end
    frame:SetRoundLayoutToNearestPixel(enabled ~= false)
    return true
end

local function Children(header)
    local out = {}
    for index = 1, 40 do
        local child = header:GetAttribute("child" .. index)
        if not child then break end
        out[#out + 1] = child
    end
    return out
end

-- The snippet carries the configured size and the click, vehicle and ping setup.
local function CheckSnippet(header, width, height, label)
    local snippet = header:GetAttribute("initialConfigFunction")
    Check(type(snippet) == "string", label .. " must carry the secure snippet")
    Check(snippet:find(("SetWidth(%.3f)"):format(width), 1, true)
        and snippet:find(("SetHeight(%.3f)"):format(height), 1, true), label .. " snippet must size the buttons")
    Check(snippet:find("'*type1', 'target'", 1, true) and snippet:find("'*type2', 'togglemenu'", 1, true)
        and snippet:find("'ping-receiver', true", 1, true), label .. " snippet must set up clicks and pings")
    Check(header:GetAttribute("_initialAttributeNames") == nil, label .. " must not copy attributes instead")
    Check(header.hooks.OnShow == nil, label .. " must not hook OnShow to pre-create buttons")
    -- A child born in combat is adopted through the header's insecure method
    -- (the oUF pattern); tools/tests/group_header_combat_child_smoke.lua runs it.
    Check(snippet:find("header:CallMethod('MSUFGFInitChild', self:GetName())", 1, true),
        label .. " snippet must hand new children to the header's insecure method")
    Check(type(header.MSUFGFInitChild) == "function", label .. " carries no MSUFGFInitChild method")
end

local SecureSort = assert(loadfile(repo .. "/tools/tests/secure_group_sort.lua"))()
local function RaidRoster()
    local members = {}
    for index = 1, raidCount do
        local name, _, subgroup, _, _, class = GetRaidRosterInfo(index)
        members[index] = { unit = "raid" .. index, name = name, subgroup = subgroup, class = class, assignedRole = "DAMAGER" }
    end
    return { kind = "RAID", members = members }
end
local function PartyRoster()
    local members = {}
    for index, unit in ipairs(partyUnits) do
        local _, class = UnitClass(unit)
        members[index] = { unit = unit, name = UnitName(unit), class = class, assignedRole = "DAMAGER" }
    end
    return { kind = "PARTY", members = members }
end

local function RunClient(isForever)
    local client = isForever and "Forever" or "other clients"
    inGroup, inRaid, raidCount = true, false, 0
    local GF, conf = Load(isForever)

    local party = assert(GF.SetupHeader("party", "party"), client .. ": party header did not build")
    CheckSnippet(party, 120, 40, client .. " party header")
    GF.ShowHeaders("party")
    local buttons = Children(party)
    Check(#buttons == 3, client .. ": the party header must build only its shown buttons, got " .. #buttons)
    for index = 1, #buttons do
        Check(buttons[index].snippetConfigured == true, client .. ": party button " .. index .. " must come from the snippet")
    end

    inRaid, raidCount = true, 12
    local raid = assert(GF.SetupHeader("raid", "raid"), client .. ": raid header did not build")
    CheckSnippet(raid, 80, 32, client .. " raid header")
    conf.raid.sortClassPriority, conf.raid.classOrder = true, "MAGE,PRIEST"
    raid = GF.SetupHeader("raid", "raid")
    -- Class priority is a native CLASS grouping: no frozen name list.
    local raidShown = SecureSort.Order(raid, RaidRoster())
    Check(raid:GetAttribute("nameList") == nil and raid:GetAttribute("groupBy") == "CLASS"
        and raidShown:match("^Member2,") and raidShown:match(",Member1$"),
        client .. ": class priority did not refine raid index order")
    conf.raid.sortClassPriority = false

    conf.raid.preserveRaidGroups = true
    raid = assert(GF.SetupHeader("raid", "raid"), client .. ": preserved raid headers did not build")
    Check(raid._msufRaidGroupIndex == 1, client .. ": preserved raid groups must build subgroup headers")
    CheckSnippet(raid, 80, 32, client .. " preserved raid header")
    raidCount = 2; rosterGroups[1], rosterGroups[2] = 1, 3
    conf.raid.collapseEmptyGroups = true
    GF.SetupHeader("raid", "raid")
    local first, third = GF.raidGroupHeaders[1], GF.raidGroupHeaders[3]
    Check(GF.raidGroupHeaders[2]._msufPreservedGroupAllowed == false, client .. " empty group not collapsed")
    Check(third.point[4] == 81, client .. " occupied group must move into adjacent slot")
    conf.raid.collapseEmptyGroups = false
    GF.SetupHeader("raid", "raid")
    Check(third.point[4] == 162, client .. " disabling collapse must restore subgroup slot")
    rosterGroups[2] = 5
    GF.IsMythicRaidContext = function() return true end
    conf.raid.hideMythicGroupsFiveToEight = true
    GF.SetupHeader("raid", "mythicraid")
    Check(GF.raidGroupHeaders[5]._msufPreservedGroupAllowed == false, client .. " Mythic group 5 not hidden")
    conf.raid.hideMythicGroupsFiveToEight = false
    GF.IsMythicRaidContext = function() return false end
    rosterGroups[1], rosterGroups[2] = nil, nil
    conf.raid.preserveRaidGroups = false
    inRaid, raidCount = false, 0

    conf.party.sortClassPriority = true
    conf.party.classOrder = "WARRIOR,MAGE,PRIEST"
    -- Header captures the native UnitClass function at load, so the fixture's
    -- class lookup below supplies distinct public classes from the start.
    party = GF.SetupHeader("party", "party")
    Check(party:GetAttribute("nameList") == nil and party:GetAttribute("groupBy") == "CLASS"
        and SecureSort.Order(party, PartyRoster()) == "party2,party1,player", client .. ": class priority did not order the party")
    conf.party.sortClassPriority = false
    party = GF.SetupHeader("party", "party")
    Check(party:GetAttribute("nameList") == nil, client .. ": disabling class priority retained filtering name list")

    local priority = GF.SetupPriorityHeader("party", "player,party1", 2)
    Check(priority ~= nil, client .. ": Priority header did not build")
    Check(type(priority:GetAttribute("initialConfigFunction")) == "string", client .. " Priority header must carry the secure snippet")
    Check(priority:GetAttribute("initialConfigFunction"):find("header:CallMethod('MSUFGFInitChild'", 1, true)
        and type(priority.MSUFGFInitChild) == "function", client .. " Priority header must adopt combat-born children")
    Check(priority:GetAttribute("_initialAttributeNames") == nil and priority.hooks.OnShow == nil,
        client .. " Priority header must not bring back the snippet-free path")
    GF.GetPriorityFrameMetrics = function() return 110, 25 end
    GF.GetPriorityConf().unitsPerColumn = 2
    priority = GF.SetupPriorityHeader("party", "player,party1,party2,party3,party4", 5)
    Check(priority:GetAttribute("initial-width") == 110 and priority:GetAttribute("initial-height") == 25,
        client .. " independent Priority size missing")
    Check(priority:GetAttribute("unitsPerColumn") == 2 and priority:GetAttribute("maxColumns") == 3,
        client .. " Priority grid did not wrap into multiple columns")
end

RunClient(true)
RunClient(false)

print("PASS group headers: Forever and every other client configure buttons through the secure snippet")
