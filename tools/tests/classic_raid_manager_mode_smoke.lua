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

local button = { hooks = {} }
function button:HookScript(kind, callback) self.hooks[kind] = callback end
function button:IsForbidden() return false end

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
local updateShownSelf

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
_G.hooksecurefunc = function() end
_G.C_Timer = { After = function(_, callback) callback() end }
_G.CompactRaidFrameManager = manager
_G.CompactRaidFrameManagerToggleButton = button
_G.CompactRaidFrameManager_UpdateShown = function(self) updateShownSelf = self end

local path = root .. "/MidnightSimpleUnitFrames/Game/Classic/UnitFrames/Group/MSUF_UF_Group_Blizzard.lua"
local chunk = assert(loadfile(path))
chunk("MidnightSimpleUnitFrames", _G.MSUF_NS)

local GF = assert(_G.MSUF_NS.GF)
assert(type(GF.ApplyBlizzardRaidManagerMode) == "function", "Raid Manager apply entry point missing")

configs.party.raidManagerMode = "SHOW"
assert(GF.ApplyBlizzardRaidManagerMode() == "SHOW", "SHOW mode did not resolve")
assert(manager.alpha == 1 and manager.mouseEnabled == true, "SHOW mode must be visible and interactive")

configs.party.raidManagerMode = "HIDDEN"
assert(GF.ApplyBlizzardRaidManagerMode() == "HIDDEN", "HIDDEN mode did not resolve")
assert(manager.alpha == 0 and manager.mouseEnabled == false, "HIDDEN mode must be invisible and click-through")

configs.party.raidManagerMode = "MOUSEOVER"
mouseFoci = {}
assert(GF.ApplyBlizzardRaidManagerMode() == "MOUSEOVER", "MOUSEOVER mode did not resolve")
assert(manager.alpha == 0 and manager.mouseEnabled == true, "MOUSEOVER idle state must be transparent and interactive")
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

configs.party.enabled = false
configs.party.showSolo = false
configs.party.raidManagerMode = "SHOW"
assert(GF.ApplyBlizzardGroupFrameOwnership("classic-signature-smoke") == true, "ownership apply failed")
assert(updateShownSelf == manager, "Classic CompactRaidFrameManager_UpdateShown must receive manager self")

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
local headersPath = root .. "/MidnightSimpleUnitFrames/Game/Classic/UnitFrames/Group/MSUF_UF_Group_Headers.lua"
assert(loadfile(headersPath))("MidnightSimpleUnitFrames", _G.MSUF_NS)

local header = assert(GF.SetupHeader("raid", "raid"), "Classic raid header did not build")
assert(header:GetAttribute("_msufSortMode") == "INDEX",
    "Classic raid header changed INDEX without Preserve raid groups")
assert(header:GetAttribute("nameList") == "Member1,Member2,Member3,Member4",
    "Classic INDEX raid order was not stable")

headerConf.preserveRaidGroups = true
header = assert(GF.SetupHeader("raid", "raid"), "preserved Classic raid header did not rebuild")
assert(header:GetAttribute("_msufSortMode") == "GROUP",
    "Preserve raid groups did not derive GROUP from INDEX")
assert(header:GetAttribute("nameList") == "Member2,Member4,Member1,Member3",
    "Preserve raid groups did not keep subgroup members together")

headerConf.sortMode = "ROLE"
header = assert(GF.SetupHeader("raid", "raid"), "group-role Classic raid header did not rebuild")
assert(header:GetAttribute("_msufSortMode") == "GROUP_ROLE",
    "Preserve raid groups did not derive GROUP_ROLE from ROLE")

headerConf.preserveRaidGroups = false
header = assert(GF.SetupHeader("raid", "raid"), "restored Classic raid header did not rebuild")
assert(header:GetAttribute("_msufSortMode") == "ROLE" and headerConf.sortMode == "ROLE",
    "disabling Preserve raid groups did not restore the saved sort mode")

print("classic raid-manager and group-header smoke passed")
