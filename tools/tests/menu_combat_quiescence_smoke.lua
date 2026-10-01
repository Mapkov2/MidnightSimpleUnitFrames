-- menu_combat_quiescence_smoke.lua <repoRoot> <flavor>
--
-- The options menu goes quiet when combat starts (review 2026-09-30, F15: the
-- Classic gate had no smoke for it):
--   * PLAYER_REGEN_DISABLED closes the open window, ends its history session,
--     unregisters its status events and cancels every delayed menu task;
--   * the minimized bar alone is closed by the fallback combat listener;
--   * while combat lockdown lasts the menu refuses to open, a direct Show is
--     undone by the window's OnShow, and no delayed menu work can be queued;
--   * after PLAYER_REGEN_ENABLED the menu opens again.
-- The client sends PLAYER_REGEN_DISABLED before lockdown starts and
-- PLAYER_REGEN_ENABLED after it ends; the smoke keeps that order, and also
-- closes the minimized bar from inside lockdown.
--
-- Boots the real core and Options graph of one client (client_world.lua) and
-- opens the real menu window. Plain Lua 5.1, repo root and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_combat_quiescence_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

local world = World.New(root, flavor, { locale = "enUS" })
-- Widget surface the real page builders use and the shared stubs leave out.
local widgetMethods = getmetatable(world.env.UIParent).__index
for _, name in ipairs({ "Normal", "Highlight", "Pushed", "Disabled", "Checked" }) do
    widgetMethods["Set" .. name .. "Texture"] = function(self, path)
        local texture = self["fixture" .. name] or self:CreateTexture()
        texture:SetTexture(path)
        self["fixture" .. name] = texture
    end
    widgetMethods["Get" .. name .. "Texture"] = function(self) return self["fixture" .. name] end
end
for _, name in ipairs({ "EnableKeyboard", "SetPropagateKeyboardInput", "SetNumeric", "SetTextInsets", "SetMaxLetters",
    "ClearFocus", "SetCursorPosition", "HighlightText" }) do
    widgetMethods[name] = function(self, ...) self["fixture" .. name] = { ... } end
end
widgetMethods.HasFocus = function() return false end
widgetMethods.SetAutoFocus = function(self, value) self.autoFocus = value end
widgetMethods.SetValueStep = function(self, value) self.valueStep = value end
widgetMethods.SetObeyStepOnDrag = function(self, value) self.obeyStep = value end
widgetMethods.SetScrollChild = function(self, child) self.scrollChild = child end
widgetMethods.GetScrollChild = function(self) return self.scrollChild end
widgetMethods.SetVerticalScroll = function(self, value) self.verticalScroll = value end
widgetMethods.GetVerticalScroll = function(self) return self.verticalScroll or 0 end
widgetMethods.GetVerticalScrollRange = function() return 0 end
world.env.MAX_BOSS_FRAMES = 5 -- Harness gap only: every client defines it.
world:Boot()
local failure = world:FirstFailure()
Check(not failure, "boot failed: " .. tostring(failure and failure.file) .. " " .. tostring(failure and failure.message))
local e, n = world.env, world.core
local M = Check(n.MSUF2, "Menu2 did not load")
local runtime = Check(M.MenuRuntime, "the menu runtime is missing")
e.MSUF_EnsureDB(true)
M.ApplyService.Flush = function() return true end
-- The lock message goes to the menu's status line and to the error frame.
local told = {}
e.UIErrorsFrame = { AddMessage = function(_, text) told[#told + 1] = tostring(text) end }

-- The client fires OnShow/OnHide from Show/Hide; the shared stubs do not.
local function FireVisibilityScripts(frame)
    local show, hide = frame.Show, frame.Hide
    function frame:Show()
        local wasShown = self:IsShown()
        show(self)
        local handler = not wasShown and self:GetScript("OnShow")
        if handler then handler(self) end
    end
    function frame:Hide()
        local wasShown = self:IsShown()
        hide(self)
        local handler = wasShown and self:GetScript("OnHide")
        if handler then handler(self) end
    end
    function frame:SetShown(shown) if shown then self:Show() else self:Hide() end end
end

-- Dispatch an event to the Options addon's own listeners only.
local function MenuListeners(event, fileSuffix)
    local out = {}
    for _, frame in ipairs(world.widgets.frames) do
        local handler = frame.events and (frame.events[event] or frame.events["*"]) and frame:GetScript("OnEvent")
        local source = handler and debug.getinfo(handler, "S").source or ""
        if source:find("MidnightSimpleUnitFrames_Options", 1, true)
            and (not fileSuffix or source:sub(-#fileSuffix) == fileSuffix) then
            out[#out + 1] = { frame = frame, handler = handler }
        end
    end
    return out
end
local function Fire(event, ...)
    local listeners = MenuListeners(event)
    for i = 1, #listeners do listeners[i].handler(listeners[i].frame, event, ...) end
    return #listeners
end
local function ToldCombatLock(from)
    for i = from + 1, #told do
        if told[i]:find("locked in combat", 1, true) then return true end
    end
    return false
end
local function EnterCombat(lockFirst)
    if lockFirst then world.widgets:SetCombat(true) end
    local listeners = Fire("PLAYER_REGEN_DISABLED")
    world.widgets:SetCombat(true)
    return listeners
end
local function LeaveCombat()
    world.widgets:SetCombat(false)
    Fire("PLAYER_REGEN_ENABLED")
    world.widgets:RunTimers()
end

-- Open once so the window and the minimized bar exist, then reopen through
-- the real show path so the window's OnShow lifecycle has run.
Check(M.Open("profiles") ~= false, "the menu did not open")
world.widgets:RunTimers()
local win = Check(M.frame, "the menu window was not built")
local bar = Check(M.minimizedBar, "the minimized bar was not built")
FireVisibilityScripts(win)
FireVisibilityScripts(bar)
M.HideSlashMenuAndMinibar(win)
world.widgets:RunTimers()
local function OpenMenu(label)
    Check(M.Open("profiles") ~= false, "the menu did not open " .. label)
    world.widgets:RunTimers()
    Check(win:IsShown() and runtime.active == true, "the menu is not open and active " .. label)
    Check(win.status and win.status._msuf2EventsRegistered == true, "the open menu did not register its status events " .. label)
end
OpenMenu("before combat")

---------------------------------------------------------------------------
-- 1. Combat closes the open window and cancels its delayed work
---------------------------------------------------------------------------
local ran = 0
local task = M.MenuTimer.After(5, function() ran = ran + 1 end)
Check(task and runtime:PendingTaskCount() >= 1, "the open menu did not queue delayed work")
Check(EnterCombat(false) > 0, "nothing in the menu listens for combat entry")
Check(not win:IsShown() and not bar:IsShown(), "combat left the menu window or its bar on screen")
Check(runtime.active == false and runtime:PendingTaskCount() == 0, "combat left the menu runtime active or its work queued")
Check(win.status._msuf2EventsRegistered == nil, "the closed menu kept its status events registered")
world.widgets:RunTimers()
Check(ran == 0, "delayed menu work ran after combat closed the menu")

---------------------------------------------------------------------------
-- 2. Lockdown keeps the menu closed
---------------------------------------------------------------------------
world.widgets:AdvanceTime(5) -- The lock message is throttled per second.
local toldBefore = #told
Check(M.Open("profiles") == false and not win:IsShown(), "the menu opened during combat lockdown")
Check(ToldCombatLock(toldBefore), "a refused open did not tell the player why")
win:Show()
Check(not win:IsShown(), "the window's OnShow did not undo a direct Show during lockdown")
Check(M.MenuTimer.After(0, function() ran = ran + 1 end) == nil, "delayed menu work was queued during lockdown")
Check(M.Toggle("profiles") == false and not win:IsShown(), "toggling opened the menu during lockdown")
world.widgets:RunTimers()
Check(ran == 0, "delayed menu work ran during lockdown")

---------------------------------------------------------------------------
-- 3. After combat the menu opens again
---------------------------------------------------------------------------
LeaveCombat()
OpenMenu("after combat")

---------------------------------------------------------------------------
-- 4. The minimized bar alone is closed by the fallback listener
---------------------------------------------------------------------------
local function Minimize()
    Check(M.MinimizeSlashMenuWindow(win), "the menu did not minimize")
    local driver = win._msuf2WindowLayoutDriver
    local step = driver and driver:GetScript("OnUpdate")
    if step then step(driver, 10) end
    world.widgets:RunTimers()
    Check(bar:IsShown() and not win:IsShown(), "minimizing did not leave the bar alone on screen")
    Check(#MenuListeners("PLAYER_REGEN_DISABLED", "MSUF_Menu2_API.lua") == 1,
        "the minimized bar has no combat listener of its own")
end
Minimize()
EnterCombat(false)
Check(not bar:IsShown() and not win:IsShown(), "combat left the minimized bar on screen")
Check(runtime.active == false, "combat left the runtime of the minimized menu active")
Check(#MenuListeners("PLAYER_REGEN_DISABLED", "MSUF_Menu2_API.lua") == 0, "the closed bar kept its combat listener")
LeaveCombat()

-- Inside lockdown too (a combat event that arrives late), with the message.
OpenMenu("before the second minimize")
Minimize()
world.widgets:AdvanceTime(5)
toldBefore = #told
EnterCombat(true)
Check(not bar:IsShown() and not win:IsShown(), "combat inside lockdown left the minimized bar on screen")
Check(ToldCombatLock(toldBefore), "closing the bar inside lockdown did not tell the player why")
LeaveCombat()
OpenMenu("at the end")

print(string.format("menu_combat_quiescence_smoke: ok (%s: combat closes window and bar, lockdown refuses opens and timers)", flavor))
