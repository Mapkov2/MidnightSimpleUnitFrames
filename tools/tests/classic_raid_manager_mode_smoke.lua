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

print("classic raid-manager mode smoke passed")
