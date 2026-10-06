-- Exercise the shipped Esc-menu layout with a protected parent, as supplied
-- by addons with secure menu children. Native writes fail during lockdown.
local root = assert(arg[1], "repository root required")
local flavor = arg[2] or "Mainline"
local sourceRoot = arg[3] or root
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Fixture(startLocked, savedEnabled)
    local world = World.New(root, flavor)
    local env, host, widgets = world.env, world.core, world.widgets
    local state = { writes = 0, scans = 0, creates = 0, registrations = 0, combatQueries = 0,
        menuQueries = 0, ownQueries = 0, ownWrites = 0, ownProtected = false }
    host.ExportPublic = function(name, value) env[name], host[name] = value, value end
    env.MSUF_DB = { general = { showGameMenuButton = savedEnabled ~= false } }
    env.LOGOUT, env.EXIT_GAME, env.RETURN_TO_GAME, env.MACROS = "Logout", "Exit", "Return", "Macros"
    env.EllesmereUI = false
    env.InCombatLockdown = function()
        state.combatQueries = state.combatQueries + 1
        return widgets:IsInCombat()
    end
    local menu = env.CreateFrame("Frame", "GameMenuFrame", env.UIParent)
    env.GameMenuFrame = menu
    menu:SetSize(240, 400)
    local trigger = env.CreateFrame("Button", "SecureMenuTrigger", menu, "SecureHandlerBaseTemplate")
    trigger.protected = true
    menu.IsProtected = function(self)
        state.menuQueries = state.menuQueries + 1
        return trigger.protected and trigger:GetParent() == self, false
    end
    local function Guard(frame, isProtected, own)
        for _, method in ipairs({ "SetHeight", "SetSize", "SetPoint", "ClearAllPoints", "Show", "Hide" }) do
            local original = frame[method]
            local blockedMessage = "protected " .. method .. " during combat"
            frame[method] = function(self, ...)
                if own then state.ownWrites = state.ownWrites + 1 else state.writes = state.writes + 1 end
                assert(not widgets:IsInCombat() or not isProtected(), blockedMessage)
                return original(self, ...)
            end
        end
    end
    -- No child-to-parent C implementation is copied here: this fixture models
    -- the resulting IsProtected fact and refuses the protected native writes.
    Guard(menu, function() return trigger.protected end)
    local macro = env.CreateFrame("Button", "MenuMacros", menu)
    macro:SetText("Macros")
    macro:SetSize(200, 24)
    macro:SetPoint("TOP", menu, "TOP", 0, -200)
    local exit = env.CreateFrame("Button", "MenuExit", menu)
    exit:SetText("Logout")
    exit:SetSize(200, 24)
    exit:SetPoint("TOP", menu, "TOP", 0, -320)
    local getChildren = menu.GetChildren
    menu.GetChildren = function(self)
        state.scans = state.scans + 1
        return getChildren(self)
    end
    local createFrame = env.CreateFrame
    env.CreateFrame = function(kind, name, parent, template)
        local frame = createFrame(kind, name, parent, template)
        local register = frame.RegisterEvent
        frame.RegisterEvent = function(self, event)
            if event == "PLAYER_REGEN_ENABLED" then state.registrations = state.registrations + 1 end
            return register(self, event)
        end
        if name == "MSUF_GameMenuButton" then
            state.creates = state.creates + 1
            frame.IsProtected = function()
                state.ownQueries = state.ownQueries + 1
                return state.ownProtected, state.ownProtected
            end
            Guard(frame, function() return state.ownProtected end, true)
        end
        return frame
    end
    widgets:SetCombat(startLocked == true)
    local chunk = assert(loadfile(sourceRoot .. "/MidnightSimpleUnitFrames/Shell/MSUF_GameMenu.lua"))
    setfenv(chunk, env)
    chunk("MidnightSimpleUnitFrames", host)
    widgets:FireEvent("PLAYER_LOGIN")
    local function Position() env.MSUF_PositionGameMenuButton() end
    local function Toggle(enabled) env.MSUF_SetGameMenuButtonEnabled(enabled) end
    local function OnShow() assert(menu:GetScript("OnShow"))(menu) end
    local function HasReplay()
        for _, frame in ipairs(widgets.frames) do
            if frame.events.PLAYER_REGEN_ENABLED then return true end
        end
        return false
    end
    local function AssertRestored()
        assert(menu:GetHeight() == 400, "original menu height was not restored")
        local _, _, _, _, macroY = macro:GetPoint(1)
        local _, _, _, _, exitY = exit:GetPoint(1)
        assert(macroY == -200 and exitY == -320, "original button offsets were not restored")
        assert(not menu.MSUF or not menu.MSUF:IsShown(), "disabled MSUF button remained shown")
        assert(not menu.MSUFAdjustedHeight and not menu.MSUFAddedHeight, "stale adjusted-height bookkeeping")
    end
    return { world = world, env = env, widgets = widgets, state = state, menu = menu, trigger = trigger,
        macro = macro, exit = exit, Position = Position, Toggle = Toggle, OnShow = OnShow,
        HasReplay = HasReplay, AssertRestored = AssertRestored }
end

-- Ordinary layout, repeated opens and disabling retain their exact geometry.
local f = Fixture()
f.Toggle(true)
f.widgets:RunTimers()
local height = f.menu:GetHeight()
assert(height == 436 and f.menu.MSUF:IsShown(), "ordinary menu layout changed")
for _ = 1, 5 do f.OnShow() end
f.widgets:RunTimers()
assert(f.menu:GetHeight() == height, "reopening accumulated extra height")
f.Toggle(false)
f.AssertRestored()
assert(not f.HasReplay(), "normal layout registered a combat-end listener")

-- Unprotected menus keep their existing combat behavior.
f = Fixture()
f.trigger.protected = false
f.widgets:SetCombat(true)
f.Position()
assert(f.menu:GetHeight() == 436 and not f.HasReplay(), "unprotected combat layout regressed")
f.Toggle(false)
f.AssertRestored()

-- A next-frame OnShow callback must recheck protection at execution time.
f = Fixture()
f.Toggle(true)
f.widgets:RunTimers()
f.OnShow()
f.widgets:EnterCombat()
local before = f.state.writes
f.widgets:RunTimers()
assert(f.state.writes == before and f.HasReplay(), "queued callback wrote to the locked parent")
assert(not f.menu.MSUF:IsShown(), "safe addon button was not hidden during deferral")
f.widgets:LeaveCombat()
assert(f.state.writes == before + 1 and f.menu.MSUF:IsShown(), "visible menu did not replay once")
assert(f.menu:GetHeight() == 436 and not f.HasReplay(), "replay retained a listener or drifted height")
before = f.state.writes
f.widgets:FireEvent("PLAYER_REGEN_ENABLED")
assert(f.state.writes == before, "combat-end replay repeated")

-- Repeated locked requests do no layout scans, timers or repeat registrations.
f.widgets:EnterCombat()
f.Position()
local scans, registrations = f.state.scans, f.state.registrations
local queries, menuQueries, ownQueries = f.state.combatQueries, f.state.menuQueries, f.state.ownQueries
before = f.state.writes
local minAllocated = math.huge
for _ = 1, 2 do
    collectgarbage("collect")
    collectgarbage("stop")
    local start = collectgarbage("count")
    for _ = 1, 1000 do f.Position() end
    minAllocated = math.min(minAllocated, collectgarbage("count") - start)
    collectgarbage("restart")
end
assert(minAllocated < 0.02, string.format("locked layout requests allocate per call: %.3f KB", minAllocated))
assert(f.state.scans == scans and f.state.writes == before and f.state.registrations == registrations,
    "locked requests scanned, wrote protected geometry or repeated event registration")
assert(f.state.combatQueries - queries == 2000 and f.state.menuQueries - menuQueries == 2000
    and f.state.ownQueries - ownQueries == 2000 and #f.widgets.timers == 0,
    "locked requests exceeded their three safety reads or queued timers")
f.widgets:LeaveCombat()
assert(not f.HasReplay())

-- Disabling while pending must preserve the listener and restore even hidden.
f = Fixture()
f.Toggle(true)
f.widgets:RunTimers()
f.widgets:EnterCombat()
f.Position()
before = f.state.writes
f.Toggle(false)
assert(f.state.writes == before and f.HasReplay(), "disable cancelled the pending restore")
f.menu.shown = false -- The native secure menu owner closes it in combat.
f.widgets:LeaveCombat()
f.AssertRestored()
assert(not f.HasReplay() and not f.env.MSUF_DB.general.showGameMenuButton)

-- The latest toggle wins, including a queued callback invalidated by disable.
f = Fixture()
f.Toggle(true)
f.OnShow()
f.widgets:EnterCombat()
f.Toggle(false)
f.Toggle(true)
f.widgets:RunTimers()
before = f.state.writes
f.widgets:LeaveCombat()
assert(f.state.writes == before + 1 and f.menu.MSUF:IsShown() and f.menu:GetHeight() == 436,
    "pending toggles did not resolve to the latest enabled state")

-- Enabled hidden menus do no combat-end work; the next opening lays out normally.
f = Fixture()
f.Toggle(true)
f.widgets:RunTimers()
f.widgets:EnterCombat()
f.Position()
f.menu.shown = false
before = f.state.writes
f.widgets:LeaveCombat()
assert(f.state.writes == before and not f.HasReplay(), "replay painted a hidden enabled menu")
f.menu.shown = true
f.OnShow()
f.widgets:RunTimers()
assert(f.menu.MSUF:IsShown() and f.menu:GetHeight() == 436, "next opening failed after hidden replay")

-- A saved setting changed directly while deferred still controls restoration.
f = Fixture()
f.Position()
f.widgets:EnterCombat()
f.Position()
f.env.MSUF_DB.general.showGameMenuButton = false
f.menu.shown = false
f.widgets:LeaveCombat()
f.AssertRestored()

-- Another addon may protect the custom button too: never hide that in combat.
f = Fixture()
f.Position()
f.state.ownProtected = true
f.widgets:EnterCombat()
local ownWrites = f.state.ownWrites
f.Position()
f.Toggle(false)
assert(f.state.ownWrites == ownWrites and f.HasReplay(), "protected addon button was modified in combat")
f.widgets:LeaveCombat()
f.AssertRestored()

-- If native buttons disappear, the no-anchor cleanup also waits for combat.
f = Fixture()
f.Position()
f.macro:SetText(nil)
f.exit:SetText(nil)
f.widgets:EnterCombat()
before = f.state.writes
f.Position()
assert(f.state.writes == before and f.HasReplay(), "no-anchor cleanup wrote during combat")
f.widgets:LeaveCombat()
assert(f.menu:GetHeight() == 400 and not f.menu.MSUF:IsShown() and not f.HasReplay(),
    "no-anchor cleanup did not restore the menu height")

-- First hooking in combat must not create/style the custom button prematurely.
f = Fixture(true)
assert(f.state.creates == 0 and f.state.writes == 0 and f.HasReplay(), "cold locked hook wrote UI")
f.widgets:LeaveCombat()
assert(f.state.creates == 1 and f.menu.MSUF:IsShown() and f.menu:GetHeight() == 436,
    "cold protected menu did not initialize after combat")
assert(not f.HasReplay())

-- A saved disabled switch survives the same cold protected-menu path.
f = Fixture(true, false)
f.widgets:LeaveCombat()
f.AssertRestored()
assert(f.state.creates == 0 and not f.env.MSUF_DB.general.showGameMenuButton and not f.HasReplay())

print(string.format("game_menu_combat_layout_smoke: PASS (%s; geometry, queued combat, latest toggle, single replay, hidden/cold/protected button; locked allocation %.3f KB)",
    flavor, minAllocated))
