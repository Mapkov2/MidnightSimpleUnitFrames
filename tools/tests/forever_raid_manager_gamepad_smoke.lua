-- Forever Raid Manager and the gamepad UI.
--
--   lua tools/tests/forever_raid_manager_gamepad_smoke.lua <repo root>
--
-- WoW Forever 1.60.1.70009 gave Blizzard's Raid Manager gamepad support: while the
-- manager is shown, GAMEPAD_MENU_LEFT expands it and moves gamepad focus into it.
-- MSUF's HIDDEN, AUTO and MOUSEOVER modes keep the manager shown at alpha 0, so a
-- gamepad could open an invisible panel. MSUF_UF_Group_Blizzard.lua lights the panel
-- while its displayFrame is shown with the gamepad UI on, and hands the alpha back
-- to the mode when it closes. Mouse users and managers without gamepad support
-- (Midnight, Classic) keep the old behaviour.
local root = assert(arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local configs, manager, display, mouseFoci, gamepadUI

local function NewHookable()
    local frame = { hooks = {} }
    function frame:HookScript(kind, callback) self.hooks[kind] = callback end
    function frame:IsForbidden() return false end
    return frame
end

local function Load(hasGamepadManager)
    configs = {
        party = { enabled = false, showSolo = false, showPlayer = true, blizzardFallbackMode = "SHOW", raidManagerMode = "SHOW" },
        raid = { enabled = false, blizzardFallbackMode = "SHOW" },
        mythicraid = { enabled = false, blizzardFallbackMode = "SHOW" },
    }
    mouseFoci, gamepadUI = {}, true

    local eventFrame = { events = {} }
    function eventFrame:RegisterEvent(event) self.events[event] = true end
    function eventFrame:UnregisterEvent(event) self.events[event] = nil end
    function eventFrame:UnregisterAllEvents() self.events = {} end
    function eventFrame:SetScript(kind, callback) self[kind] = callback end
    function eventFrame:SetAllPoints() end
    function eventFrame:Hide() end

    display = NewHookable()
    manager = NewHookable()
    manager.alpha, manager.mouseEnabled, manager.collapsed = 1, true, true
    manager.displayFrame = display
    manager.toggleButtonBack, manager.toggleButtonForward = NewHookable(), NewHookable()
    function manager:SetAlpha(alpha) self.alpha = alpha end
    function manager:EnableMouse(enabled) self.mouseEnabled = enabled and true or false end
    function manager:IsMouseEnabled() return self.mouseEnabled end
    function manager:IsProtected() return false end
    function manager:GetParent() return _G.UIParent end

    _G.MSUF_NS = {
        Client = { Family = "Mainline", IsForever = hasGamepadManager },
        ExportPublic = function(name, value) _G[name] = value; return value end,
        GF = {
            GetConf = function(kind) return configs[kind] end,
            GetLiveRaidKind = function() return "raid" end,
        },
    }
    _G.CreateFrame = function() return eventFrame end
    _G.UIParent = {}
    _G.InCombatLockdown = function() return false end
    _G.IsInGroup = function() return true end
    _G.IsInRaid = function() return false end
    _G.GetNumGroupMembers = function() return 3 end
    _G.GetMouseFoci = function() return mouseFoci end
    _G.hooksecurefunc = function() end
    _G.C_Timer = { After = function(_, callback) callback() end }
    _G.InputUtil = { IsGamepadUIEnabled = function() return gamepadUI end }
    _G.CompactRaidFrameManager = manager
    _G.CompactRaidFrameManager_InitializeGamepad = hasGamepadManager and function() end or nil

    local path = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Blizzard.lua"
    assert(loadfile(path))("MidnightSimpleUnitFrames", _G.MSUF_NS)
    return assert(_G.MSUF_NS.GF)
end

local function SetMode(GF, mode)
    configs.party.raidManagerMode = mode
    return GF.ApplyBlizzardRaidManagerMode()
end

---------------------------------------------------------------------------
-- Forever: Blizzard's manager has gamepad support
---------------------------------------------------------------------------
local GF = Load(true)

Check(SetMode(GF, "HIDDEN") == "HIDDEN", "HIDDEN mode did not resolve")
Check(manager.alpha == 0 and manager.mouseEnabled == false, "HIDDEN must stay invisible and click-through")
Check(type(display.hooks.OnShow) == "function" and type(display.hooks.OnHide) == "function",
    "HIDDEN must watch the displayFrame, which shows exactly while the panel is expanded")

-- The gamepad opens the panel: it is lit while open, and a mode re-apply keeps it lit.
display.hooks.OnShow(display)
Check(manager.alpha == 1, "a panel the gamepad opened must be visible while it holds focus")
SetMode(GF, "HIDDEN")
Check(manager.alpha == 1 and manager.mouseEnabled == false, "re-applying HIDDEN must not black out an open gamepad panel")
display.hooks.OnHide(display)
Check(manager.alpha == 0, "closing the gamepad panel must hand the alpha back to HIDDEN")

-- AUTO resolves to HIDDEN while MSUF owns the live group frames.
configs.party.enabled, configs.party.showSolo = true, true
Check(SetMode(GF, "AUTO") == "AUTO", "AUTO mode did not resolve")
Check(manager.alpha == 0, "AUTO must hide the manager while MSUF owns the group frames")
display.hooks.OnShow(display)
Check(manager.alpha == 1, "AUTO: a panel the gamepad opened must be visible")
display.hooks.OnHide(display)
Check(manager.alpha == 0, "AUTO: closing the gamepad panel must hide it again")
configs.party.enabled, configs.party.showSolo = false, false

-- Mouse and keyboard: nothing changes.
gamepadUI = false
SetMode(GF, "HIDDEN")
display.hooks.OnShow(display)
Check(manager.alpha == 0, "without the gamepad UI an expanded HIDDEN panel must stay invisible, as before")
display.hooks.OnHide(display)
Check(manager.alpha == 0, "without the gamepad UI a collapse must not touch the alpha")
gamepadUI = true

-- MOUSEOVER: the open panel is lit; on close it fades unless the pointer is on it.
Check(SetMode(GF, "MOUSEOVER") == "MOUSEOVER", "MOUSEOVER mode did not resolve")
Check(manager.alpha == 0, "MOUSEOVER idle state must be transparent")
display.hooks.OnShow(display)
Check(manager.alpha == 1, "MOUSEOVER: a panel the gamepad opened must be visible")
SetMode(GF, "MOUSEOVER")
Check(manager.alpha == 1, "MOUSEOVER: re-applying the mode must keep an open gamepad panel lit")
mouseFoci = { manager }
display.hooks.OnHide(display)
Check(manager.alpha == 1, "MOUSEOVER: a hovered manager stays lit after the gamepad closes it")
mouseFoci = {}
display.hooks.OnShow(display)
display.hooks.OnHide(display)
Check(manager.alpha == 0, "MOUSEOVER: closing the gamepad panel must fade it when nothing hovers it")

-- SHOW: always visible; the gamepad hooks leave the alpha alone.
SetMode(GF, "SHOW")
Check(manager.alpha == 1, "SHOW must be visible")
display.hooks.OnShow(display)
display.hooks.OnHide(display)
Check(manager.alpha == 1, "SHOW must stay visible when the gamepad closes the panel")

---------------------------------------------------------------------------
-- Midnight: no gamepad support in Blizzard's manager, no displayFrame hooks
---------------------------------------------------------------------------
GF = Load(false)
SetMode(GF, "HIDDEN")
Check(manager.alpha == 0 and display.hooks.OnShow == nil and display.hooks.OnHide == nil,
    "a manager without gamepad support must not be hooked")

print("PASS Forever Raid Manager: a panel the gamepad opens is visible until it closes; mouse users and Midnight unchanged")
