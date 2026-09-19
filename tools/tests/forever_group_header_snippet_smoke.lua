-- Forever group headers without secure snippets.
--
--   lua tools/tests/forever_group_header_snippet_smoke.lua <repo root>
--
-- FOREVER-SNIPPET-WORKAROUND: WoW Forever cannot compile secure snippets.
-- Blizzard_EnvironmentCleanup clears loadstring_untainted before
-- RestrictedExecution.lua caches it, so every initialConfigFunction throws
-- "RestrictedExecution.lua:79: attempt to call a nil value" and no party, raid
-- or Priority button is ever configured. This smoke runs the real
-- MSUF_UF_Group_Headers.lua against a SecureGroupHeader stub that fails the same
-- way. Forever headers must carry no snippet, copy the snippet's attributes
-- through _initialAttributeNames, and create and size their buttons out of
-- combat. Every other client must keep the snippet.
-- Delete this smoke and its row in tools/classic-gate-smokes.tsv together with
-- the workaround.
local repo = assert(arg[1], "repository root is required"):gsub("\\", "/"):gsub("/$", "")
local headersPath = repo .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Headers.lua"

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local FOREVER_SNIPPET_ERROR = "RestrictedExecution.lua:79: attempt to call a nil value"

local inCombat = false
local inGroup, inRaid = true, false
local partyUnits = { "player", "party1", "party2" }
local raidCount = 0
local snippetsCompile = false
local startingIndexWrites = 0

local function NewRegion(parent)
    local frame = { parent = parent, attributes = {}, shown = false, width = 0, height = 0, hooks = {} }
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:SetWidth(width) self.width = width end
    function frame:SetHeight(height) self.height = height end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:ClearAllPoints() end
    function frame:SetPoint() end
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
    local startingIndex = header.attributes.startingIndex or 1
    local unitCount = #units
    local numDisplayed = unitCount - (startingIndex - 1)
    local unitsPerColumn = header.attributes.unitsPerColumn
    local numColumns
    if unitsPerColumn and numDisplayed > unitsPerColumn then
        numColumns = math.min(math.ceil(numDisplayed / unitsPerColumn), header.attributes.maxColumns or 1)
    else
        unitsPerColumn = numDisplayed
        numColumns = 1
    end
    local loopStart = startingIndex
    local loopFinish = math.min((startingIndex - 1) + unitsPerColumn * numColumns, unitCount)
    numDisplayed = loopFinish - (loopStart - 1)
    local needButtons = math.max(1, numDisplayed)
    if not header.attributes["child" .. needButtons] then
        for index = 1, needButtons do
            if not header.attributes["child" .. index] then
                local button = NewRegion(header)
                button.protected = true
                header.children = header.children or {}
                header.children[#header.children + 1] = button
                local configCode = header.attributes.initialConfigFunction
                if type(configCode) == "string" then
                    if not snippetsCompile then error(FOREVER_SNIPPET_ERROR, 0) end
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
    end
    local buttonNum = 0
    for index = loopStart, loopFinish do
        buttonNum = buttonNum + 1
        local button = header.attributes["child" .. buttonNum]
        button:SetAttribute("unit", units[index])
        button.shown = true
    end
    repeat
        buttonNum = buttonNum + 1
        local button = header.attributes["child" .. buttonNum]
        if button then
            button.shown = false
            button:SetAttribute("unit", nil)
        end
    until not button
    local first = header.attributes.child1
    header.width, header.height = first.width, first.height * math.max(numDisplayed, 1)
end

local function NewGroupHeader(parent)
    local header = NewRegion(parent)
    header.protected = true
    header.OnShow = UpdateHeader
    function header:SetAttribute(key, value)
        if key == "startingIndex" then startingIndexWrites = startingIndexWrites + 1 end
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
        -- Flat raid headers build a name list, which reads unit tokens.
        UF = { IsUnitToken = function(unit) return type(unit) == "string" and unit ~= "" end },
        GF = {},
    }
    local GF = ns.GF
    GF.GetConf = function(kind) return kind == "party" and conf.party or conf.raid end
    GF.GetPriorityConf = function() return { spacing = 2, growth = "DOWN", anchorMode = "FREE" } end
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
    _G.MSUF_NS = ns
    assert(loadfile(headersPath))("MidnightSimpleUnitFrames", ns)
    return GF, conf
end

_G.InCombatLockdown = function() return inCombat end
_G.IsInGroup = function() return inGroup end
_G.IsInRaid = function() return inRaid end
_G.GetNumGroupMembers = function() return inRaid and raidCount or #partyUnits end
_G.GetNumSubgroupMembers = function() return #partyUnits - 1 end
_G.GetRaidRosterInfo = function(index) return "Member" .. index, nil, 1 end
_G.UnitName = function(unit) return tostring(unit) end
_G.UnitGUID = function(unit) return tostring(unit) .. "-guid" end
_G.UnitClass = function() return "Priest", "PRIEST" end
_G.UnitGroupRolesAssigned = function() return "DAMAGER" end
_G.issecretvalue = function() return false end
-- Kernel/MSUF_Util.lua: protected frames refuse the call in combat.
_G.MSUF_SetRoundLayoutToNearestPixel = function(frame, enabled)
    if not (frame and frame.SetRoundLayoutToNearestPixel) then return false end
    if _G.InCombatLockdown() and frame:IsProtected() then return false end
    frame:SetRoundLayoutToNearestPixel(enabled ~= false)
    return true
end

-- The stub models Forever: a header with a snippet throws on its first button.
do
    local probe = NewGroupHeader(nil)
    probe.attributes.showParty, probe.attributes.showPlayer = true, true
    probe.attributes.initialConfigFunction = "self:SetWidth(1)"
    local ok, err = pcall(probe.Show, probe)
    Check(not ok and tostring(err) == FOREVER_SNIPPET_ERROR, "the stub must fail snippets like the Forever client")
end

local SNIPPET_ATTRIBUTES = {
    type1 = nil, ["*type1"] = "target", type2 = nil, ["*type2"] = "togglemenu",
    ["*clickbutton2"] = nil, toggleForVehicle = true, ["ping-receiver"] = true,
}

local function CheckButtonAttributes(button, label)
    for name, value in pairs(SNIPPET_ATTRIBUTES) do
        Check(button:GetAttribute(name) == value, label .. ": " .. name .. " does not match the snippet")
    end
    Check(button:GetAttribute("type1") == nil and button:GetAttribute("type2") == nil
        and button:GetAttribute("*clickbutton2") == nil, label .. ": the snippet clears type1, type2 and *clickbutton2")
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

---------------------------------------------------------------------------
-- WoW Forever
---------------------------------------------------------------------------
local GF, conf = Load(true)

-- Party of three: no snippet, and the spare slots up to five exist and are sized.
local party = assert(GF.SetupHeader("party", "party"), "Forever party header did not build")
Check(party:GetAttribute("initialConfigFunction") == nil, "Forever party header must carry no secure snippet")
Check(party:GetAttribute("_initialAttributeNames") == "type1,*type1,type2,*type2,*clickbutton2,toggleForVehicle,ping-receiver",
    "Forever party header must copy the snippet's attributes")
local okShow, showErr = pcall(GF.ShowHeaders, "party")
Check(okShow, "showing the Forever party header raised: " .. tostring(showErr))
local buttons = Children(party)
Check(#buttons == 5, "Forever party header must pre-create five buttons, got " .. #buttons)
Check(buttons[1]:GetAttribute("unit") == "player" and buttons[2]:GetAttribute("unit") == "party1"
    and buttons[3]:GetAttribute("unit") == "party2", "pre-creation must restore the real unit layout")
Check(buttons[4]:GetAttribute("unit") == nil and buttons[5]:GetAttribute("unit") == nil
    and not buttons[4].shown and not buttons[5].shown, "spare party buttons must stay empty and hidden")
Check(party:GetAttribute("startingIndex") == nil, "pre-creation must clear startingIndex again")
for index = 1, #buttons do
    CheckButtonAttributes(buttons[index], "party button " .. index)
    Check(buttons[index].roundLayout == true, "party button " .. index .. " must round its layout like the snippet")
end
Check(buttons[4].width == 120 and buttons[4].height == 40 and buttons[5].width == 120,
    "spare party buttons must carry the configured size")
Check(buttons[4].clicks == "AnyUp" and buttons[5].clicks == "AnyUp",
    "spare party buttons must take right clicks before combat")
Check(buttons[1].width == 0, "unit buttons are sized by the adapter when it applies them, not here")

-- Combat: nothing protected is touched when the header shows again, even with
-- a size and a missing spare button pending.
inCombat = true
local writesBefore = startingIndexWrites
party._msufGFButtonWidth = 100
party.attributes.child5 = nil
party:Hide()
party:Show()
Check(startingIndexWrites == writesBefore, "combat show must not create buttons")
Check(buttons[4].width == 120, "combat show must not resize buttons")
party.attributes.child5 = buttons[5]
party._msufGFButtonWidth = 120
inCombat = false

-- A size change resizes the spare buttons out of combat.
conf.party.width = 90
party = assert(GF.SetupHeader("party", "party"), "Forever party header did not rebuild")
Check(party:IsShown(), "a visible party header must be shown again after a size change")
Check(buttons[4].width == 90 and buttons[5].width == 90, "a size change must resize the spare party buttons")
Check(#Children(party) == 5, "a size change must not create more buttons")

-- Raid of twelve in three columns of five: fifteen buttons, three spare.
inRaid, raidCount = true, 12
local raid = assert(GF.SetupHeader("raid", "raid"), "Forever raid header did not build")
Check(raid:GetAttribute("initialConfigFunction") == nil, "Forever raid header must carry no secure snippet")
local okRaid, raidErr = pcall(GF.ShowHeaders, "raid")
Check(okRaid, "showing the Forever raid header raised: " .. tostring(raidErr))
local raidButtons = Children(raid)
Check(#raidButtons == 15, "Forever raid header must pre-create its column capacity, got " .. #raidButtons)
Check(raidButtons[12]:GetAttribute("unit") == "raid12" and raidButtons[13]:GetAttribute("unit") == nil,
    "raid pre-creation must restore the real unit layout")
Check(raidButtons[15].width == 80 and raidButtons[15].height == 32, "spare raid buttons must carry the configured size")
CheckButtonAttributes(raidButtons[15], "raid button 15")

-- Preserved raid groups: one header per subgroup, five buttons each at most.
conf.raid.preserveRaidGroups = true
raid = assert(GF.SetupHeader("raid", "raid"), "Forever preserved raid headers did not build")
Check(raid._msufRaidGroupIndex == 1, "preserved raid groups must build subgroup headers")
Check(raid:GetAttribute("initialConfigFunction") == nil and raid:GetAttribute("_initialAttributeNames") ~= nil,
    "Forever preserved raid headers must copy attributes instead of running a snippet")
Check(raid._msufGFButtonLimit == 5, "a preserved raid group holds five buttons")
conf.raid.preserveRaidGroups = false
inRaid, raidCount = false, 0

-- Priority Frames use the same secure header.
local priority = GF.SetupPriorityHeader("party", "player,party1", 2)
Check(priority ~= nil, "Forever Priority header did not build")
Check(priority:GetAttribute("initialConfigFunction") == nil, "Forever Priority header must carry no secure snippet")
Check(#Children(priority) == 5, "Forever Priority header must pre-create five buttons")
CheckButtonAttributes(Children(priority)[5], "priority button 5")

---------------------------------------------------------------------------
-- Every other client keeps the snippet
---------------------------------------------------------------------------
GF, conf = Load(false)
snippetsCompile = true
party = assert(GF.SetupHeader("party", "party"), "party header did not build")
local snippet = party:GetAttribute("initialConfigFunction")
Check(type(snippet) == "string" and snippet:find("SetWidth(120.000)", 1, true)
    and snippet:find("'ping-receiver', true", 1, true), "other clients must keep the secure snippet")
Check(party:GetAttribute("_initialAttributeNames") == nil, "other clients must not copy attributes")
GF.ShowHeaders("party")
Check(#Children(party) == 3 and Children(party)[1].snippetConfigured == true,
    "other clients must build only the shown buttons through the snippet")
Check(party.hooks.OnShow == nil, "other clients must not hook the header OnShow")

print("PASS Forever group headers: no secure snippet, attributes copied, buttons pre-created and sized out of combat; other clients keep the snippet")
