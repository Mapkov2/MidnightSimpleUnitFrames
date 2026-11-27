-- group_raid_manager_visibility_smoke.lua <root> <flavor>
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), assert(arg[2])
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local gamepad = false
local mw = MenuWorld.Open(root, flavor, { page = "gf_layout", clientScriptBindings = true, beforeCore = function(world)
    local env = world.env
    local manager = env.CreateFrame("Frame", "CompactRaidFrameManager", env.UIParent)
    env.CompactRaidFrameManager = manager
    local display = env.CreateFrame("Frame", nil, manager)
    manager.displayFrame = display
    manager.toggleButtonForward = env.CreateFrame("Button", nil, manager)
    manager.toggleButtonBack = env.CreateFrame("Button", nil, manager)
    for _, frame in ipairs({ manager, manager.toggleButtonForward, manager.toggleButtonBack }) do
        frame.EnableMouse = function(self, enabled) self.mouseEnabled = enabled end
        frame.IsMouseEnabled = function(self) return self.mouseEnabled end
        frame:EnableMouse(true)
    end
    MenuWorld.FireVisibilityScripts(display)
    env.CompactRaidFrameManager_Collapse = function()
        manager.collapsed = true
        display:Hide()
        manager.toggleButtonBack:Hide()
        manager.toggleButtonForward:Show()
    end
    env.CompactRaidFrameManager_Expand = function()
        manager.collapsed = false
        display:Show()
        manager.toggleButtonBack:Show()
        manager.toggleButtonForward:Hide()
    end
    env.InputUtil = { IsGamepadUIEnabled = function() return gamepad end }
    manager:Show()
    env.CompactRaidFrameManager_Collapse()
end })

local env, gf = mw.env, mw.core.GF
local manager, party = env.CompactRaidFrameManager, gf.GetConf("party")
gf.GetLiveGroupKind = function() return "party" end
party.enabled, party.raidManagerMode = true, "AUTO"
gf.ApplyBlizzardRaidManagerMode()
assert(manager:IsShown() and manager:GetAlpha() == 0 and not manager:IsMouseEnabled(),
    "AUTO exposed a collapsed Blizzard tab while MSUF owns the party frames")
env.CompactRaidFrameManager_Expand()
assert(manager:GetAlpha() == 1 and manager:IsMouseEnabled() and manager.toggleButtonBack:IsMouseEnabled(),
    "the expansion invoked by the Suite shortcut stayed invisible or click-through")
gf.ApplyBlizzardRaidManagerMode()
assert(manager:GetAlpha() == 1 and manager:IsMouseEnabled(), "group refresh closed the expanded tray")
env.CompactRaidFrameManager_Collapse()
assert(manager:GetAlpha() == 0 and not manager:IsMouseEnabled() and not manager.toggleButtonForward:IsMouseEnabled(),
    "collapse failed to return to the hidden AUTO tab")

party.raidManagerMode = "HIDDEN"
gf.ApplyBlizzardRaidManagerMode()
env.CompactRaidFrameManager_Expand()
assert(manager:GetAlpha() == 0 and not manager:IsMouseEnabled(), "shortcut overrode the explicit Hidden preference")
env.CompactRaidFrameManager_Collapse()
gamepad = true
env.CompactRaidFrameManager_Expand()
assert(manager:GetAlpha() == 1 and not manager:IsMouseEnabled(), "native gamepad expansion lost its visibility")
env.CompactRaidFrameManager_Collapse()
assert(manager:GetAlpha() == 0, "native gamepad collapse failed to return to the hidden tab")
print("group_raid_manager_visibility_smoke: PASS " .. flavor)
