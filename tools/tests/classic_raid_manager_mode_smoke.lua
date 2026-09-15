local root = assert(arg[1], "repository root argument missing")
root = root:gsub("\\", "/"):gsub("/$", "")

local configs = {
    party = { enabled = false, showSolo = false, showPlayer = true, blizzardFallbackMode = "SHOW", raidManagerMode = "SHOW" },
    raid = { enabled = false, blizzardFallbackMode = "SHOW" },
    mythicraid = { enabled = false, blizzardFallbackMode = "SHOW" },
}

local eventFrame = { events = {} }
function eventFrame:RegisterEvent(event) self.events[event] = true end
function eventFrame:UnregisterEvent(event) self.events[event] = nil end
function eventFrame:UnregisterAllEvents() self.events = {} end
function eventFrame:SetScript(kind, callback) self[kind] = callback end
function eventFrame:SetAllPoints() end
function eventFrame:Hide() end

local button = { hooks = {}, mouseEnabled = true }
function button:HookScript(kind, callback) self.hooks[kind] = callback end
function button:IsForbidden() return false end
function button:EnableMouse(enabled) self.mouseEnabled = enabled and true or false end
function button:IsMouseEnabled() return self.mouseEnabled end
function button:IsProtected() return false end

local manager = {
    alpha = 1,
    mouseEnabled = true,
    collapsed = true,
    hooks = {},
    toggleButton = button,
}
function manager:SetAlpha(alpha) self.alpha = alpha end
function manager:EnableMouse(enabled) self.mouseEnabled = enabled and true or false end
function manager:IsMouseEnabled() return self.mouseEnabled end
function manager:IsForbidden() return false end
function manager:IsProtected() return false end
function manager:GetParent() return _G.UIParent end
function manager:HookScript(kind, callback) self.hooks[kind] = callback end

local mouseFoci = {}

_G.MSUF_NS = {
    GF = {
        GetConf = function(kind) return configs[kind] end,
        GetLiveRaidKind = function() return "raid" end,
    },
}
_G.CreateFrame = function() return eventFrame end
_G.UIParent = {}
_G.InCombatLockdown = function() return false end
_G.IsInGroup = function() return false end
_G.IsInRaid = function() return false end
_G.GetNumGroupMembers = function() return 0 end
_G.GetMouseFoci = function() return mouseFoci end
local secureHooks = {}
_G.hooksecurefunc = function(frame, method, callback)
    if type(frame) == "table" then
        secureHooks[frame] = secureHooks[frame] or {}
        secureHooks[frame][method] = callback
    end
end
_G.C_Timer = { After = function(_, callback) callback() end }
_G.CompactRaidFrameManager = manager
_G.CompactRaidFrameManagerToggleButton = button

local path = root .. "/MidnightSimpleUnitFrames/Game/Classic/UnitFrames/Group/MSUF_UF_Group_Blizzard.lua"
local chunk = assert(loadfile(path))
chunk("MidnightSimpleUnitFrames", _G.MSUF_NS)

local GF = assert(_G.MSUF_NS.GF)
assert(type(GF.ApplyBlizzardRaidManagerMode) == "function", "Raid Manager apply entry point missing")

configs.party.raidManagerMode = "SHOW"
assert(GF.ApplyBlizzardRaidManagerMode() == "SHOW", "SHOW mode did not resolve")
assert(manager.alpha == 1 and manager.mouseEnabled == true, "SHOW mode must be visible and interactive")
assert(button.mouseEnabled == true, "SHOW mode must keep the toggle button interactive")

configs.party.raidManagerMode = "HIDDEN"
assert(GF.ApplyBlizzardRaidManagerMode() == "HIDDEN", "HIDDEN mode did not resolve")
assert(manager.alpha == 0 and manager.mouseEnabled == false, "HIDDEN mode must be invisible and click-through")
assert(button.mouseEnabled == false, "HIDDEN mode must make the collapsed toggle button click-through")
assert(type(button.hooks.OnClick) == "function", "HIDDEN mode must install the toggle-button hook without MOUSEOVER")

configs.party.raidManagerMode = "MOUSEOVER"
mouseFoci = {}
assert(GF.ApplyBlizzardRaidManagerMode() == "MOUSEOVER", "MOUSEOVER mode did not resolve")
assert(manager.alpha == 0 and manager.mouseEnabled == true, "MOUSEOVER idle state must be transparent and interactive")
assert(button.mouseEnabled == true, "MOUSEOVER must restore the toggle button mouse input")
assert(type(manager.hooks.OnEnter) == "function" and type(manager.hooks.OnLeave) == "function", "manager hover hooks missing")
assert(type(button.hooks.OnClick) == "function", "Classic legacy toggle-button hook missing")
manager.hooks.OnEnter(manager)
assert(manager.alpha == 1, "MOUSEOVER OnEnter did not reveal manager")
button.hooks.OnClick(button)
assert(manager.alpha == 0, "collapsed Classic toggle did not fade manager")
mouseFoci = { manager }
GF.ApplyBlizzardRaidManagerMode()
assert(manager.alpha == 1, "focused manager should remain visible")

configs.party.raidManagerMode = "AUTO"
configs.party.enabled = false
GF.ApplyBlizzardRaidManagerMode()
assert(manager.alpha == 1 and manager.mouseEnabled == true, "AUTO must show when MSUF owns no live group frames")
configs.party.enabled = true
configs.party.showSolo = true
GF.ApplyBlizzardRaidManagerMode()
assert(manager.alpha == 0 and manager.mouseEnabled == false, "AUTO must hide while MSUF owns live group frames")
assert(button.mouseEnabled == false, "AUTO must make the toggle button click-through while MSUF owns live group frames")

-- An expanded invisible panel keeps its toggle button so the user can collapse it;
-- the collapse click hands the button back to click-through.
configs.party.enabled = false
configs.party.showSolo = false
configs.party.raidManagerMode = "HIDDEN"
manager.collapsed = false
GF.ApplyBlizzardRaidManagerMode()
assert(manager.alpha == 0 and manager.mouseEnabled == false, "expanded HIDDEN manager must stay invisible and click-through")
assert(button.mouseEnabled == true, "expanded HIDDEN manager must keep its toggle button clickable")
manager.collapsed = true
button.hooks.OnClick(button)
assert(button.mouseEnabled == false, "collapsing a HIDDEN manager must make the toggle button click-through")

configs.party.enabled = false
configs.party.showSolo = false
configs.party.raidManagerMode = "SHOW"
assert(GF.ApplyBlizzardGroupFrameOwnership("classic-signature-smoke") == true, "ownership apply failed")
assert(GF.RestoreBlizzardGroupFrames() == false,
    "protected Blizzard CompactUnitFrame ownership must remain reload-only")

-- Classic's hidden-by-default manager parents the raid container itself. That is
-- Blizzard's own chrome, not a foreign hidden parent, so ownership must still move
-- the container; a foreign addon's hidden parent keeps its frame.
local container = { parent = manager, shown = true }
function container:SetParent(value) self.parent = value end
function container:GetParent() return self.parent end
function container:Hide() self.shown = false end
function container:IsForbidden() return false end
function container:IsProtected() return false end
function manager:IsShown() return false end
_G.CompactRaidFrameContainer = container
GF.HideBlizzardRaidFrames()
assert(container.parent == eventFrame and container.shown == false,
    "container under Classic's hidden manager must be reparented to the hidden parent")
local containerHooks = secureHooks[container]
assert(containerHooks and type(containerHooks.SetParent) == "function", "container SetParent hook missing")
container.parent = manager
containerHooks.SetParent(container, manager)
assert(container.parent == eventFrame,
    "Blizzard re-parenting the container under its hidden manager must be taken back")
local foreignHidden = {}
function foreignHidden:IsShown() return false end
container.parent = foreignHidden
GF.HideBlizzardRaidFrames()
assert(container.parent == foreignHidden, "a foreign hidden parent must keep the container")
containerHooks.SetParent(container, foreignHidden)
assert(container.parent == foreignHidden, "the SetParent hook must leave a foreign hidden parent alone")
_G.CompactRaidFrameContainer = nil
manager.IsShown = nil

-- Preserve raid groups must be an effective header mode, not just a saved
-- checkbox that leaves an already-valid INDEX sort untouched.
local function NewHeaderFrame(parent)
    local frame = { parent = parent, attributes = {}, shown = false, width = 0, height = 0 }
    function frame:EnableMouse() end
    function frame:SetClampedToScreen() end
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:SetWidth(width) self.width = width end
    function frame:SetHeight(height) self.height = height end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:ClearAllPoints() end
    function frame:SetPoint() end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:SetParent(value) self.parent = value end
    function frame:GetParent() return self.parent end
    function frame:SetAttribute(key, value) self.attributes[key] = value end
    function frame:GetAttribute(key) return self.attributes[key] end
    function frame:GetChildren() return end
    return frame
end

local headerUIParent = NewHeaderFrame(nil)
headerUIParent.width, headerUIParent.height = 1920, 1080
local headerConf = {
    enabled = true, showPlayer = true, showSolo = false,
    width = 80, height = 32, spacing = 1, growth = "DOWN",
    unitsPerColumn = 5, maxColumns = 8,
    preserveRaidGroups = false, sortMode = "INDEX",
}
local groups = { 2, 1, 2, 1 }
local roles = { "HEALER", "DAMAGER", "TANK", "HEALER" }

_G.UIParent = headerUIParent
_G.PetBattleFrameHider = nil
_G.CreateFrame = function(_, _, parent) return NewHeaderFrame(parent) end
_G.GetNumGroupMembers = function() return #groups end
_G.GetNumSubgroupMembers = function() return 0 end
_G.GetRaidRosterInfo = function(index) return "Member" .. index, nil, groups[index] end
_G.IsInGroup = function() return true end
_G.IsInRaid = function() return true end
_G.UnitName = function(unit)
    local index = tonumber(tostring(unit):match("raid(%d+)$"))
    return index and ("Member" .. index) or "Player"
end
_G.UnitGUID = function(unit) return tostring(unit) .. "-guid" end
_G.UnitClass = function() return "Priest", "PRIEST" end
_G.UnitGroupRolesAssigned = function(unit)
    local index = tonumber(tostring(unit):match("raid(%d+)$"))
    return index and roles[index] or "DAMAGER"
end

_G.MSUF_NS.Client = { IsClassic = true }
GF.GetConf = function() return headerConf end
GF.GetScaledFrameMetrics = function() return 80, 32, 1 end
local headersPath = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Headers.lua"
assert(loadfile(headersPath))("MidnightSimpleUnitFrames", _G.MSUF_NS)

local header = assert(GF.SetupHeader("raid", "raid"), "Classic raid header did not build")
assert(header:GetAttribute("auraContainerTemplate") == nil,
    "Classic headers must not request CustomAuraContainerTemplate")
assert(header:GetAttribute("_msufSortMode") == "INDEX",
    "Classic raid header changed INDEX without Preserve raid groups")
assert(header:GetAttribute("nameList") == "Member1,Member2,Member3,Member4",
    "Classic INDEX raid order was not stable")

headerConf.preserveRaidGroups = true
header = assert(GF.SetupHeader("raid", "raid"), "preserved Classic raid header did not rebuild")
assert(header:GetAttribute("_msufSortMode") == "GROUP",
    "Preserve raid groups did not derive GROUP from INDEX")
assert(header._msufRaidGroupIndex == 1 and header:GetAttribute("nameList") == "Member2,Member4",
    "Preserve raid groups did not build the physical subgroup-one header")
local secondGroup = assert(GF.raidGroupHeaders and GF.raidGroupHeaders[2],
    "Preserve raid groups did not build the physical subgroup-two header")
assert(secondGroup._msufRaidGroupIndex == 2
    and secondGroup:GetAttribute("nameList") == "Member1,Member3",
    "Preserve raid groups did not keep subgroup-two members together")

headerConf.sortMode = "ROLE"
header = assert(GF.SetupHeader("raid", "raid"), "group-role Classic raid header did not rebuild")
assert(header:GetAttribute("_msufSortMode") == "GROUP_ROLE",
    "Preserve raid groups did not derive GROUP_ROLE from ROLE")
assert(header:GetAttribute("nameList") == "Member4,Member2"
    and secondGroup:GetAttribute("nameList") == "Member3,Member1",
    "Preserved physical raid groups did not apply role order inside each subgroup")

headerConf.preserveRaidGroups = false
header = assert(GF.SetupHeader("raid", "raid"), "restored Classic raid header did not rebuild")
assert(header:GetAttribute("_msufSortMode") == "ROLE" and headerConf.sortMode == "ROLE",
    "disabling Preserve raid groups did not restore the saved sort mode")

-- The shared Engine file also loads on Mainline, where the secure child must
-- still carry the native 12.x aura container template.
_G.MSUF_NS.Client = { IsClassic = false }
assert(loadfile(headersPath))("MidnightSimpleUnitFrames", _G.MSUF_NS)
header = assert(GF.SetupHeader("raid", "raid"), "Mainline raid header did not build")
assert(header:GetAttribute("auraContainerTemplate") == "CustomAuraContainerTemplate",
    "Mainline headers must request CustomAuraContainerTemplate")

print("classic raid-manager and group-header smoke passed")
