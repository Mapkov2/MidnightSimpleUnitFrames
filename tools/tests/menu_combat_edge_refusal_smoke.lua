-- menu_combat_edge_refusal_smoke.lua <repoRoot> <flavor>
--
-- The client sends PLAYER_REGEN_DISABLED while InCombatLockdown() still
-- answers false. The menu's combat refusal (Kernel/MSUF_Util.lua
-- IsConfigCombatLocked) asked only the lockdown, so on that frame the menu
-- teardown decided "out of combat" (re-review CX-RVC #1, R7 P3):
--   * MenuRuntime:Quiesce passed combat = false to ApplyService.Quiesce, which
--     flushed a pending player-frame apply on the combat-start frame;
--   * EndHistorySession committed the open slider transaction with a full
--     profile snapshot on that frame.
-- This smoke opens the real menu, queues a player-frame apply, opens a slider
-- transaction that changed a setting, and sends PLAYER_REGEN_DISABLED to the
-- Options addon's own listeners only, with the lockdown still false (no core
-- handler marks the edge first, so the menu must pass the event itself):
--   1. the apply owner is not asked on that frame; it runs once after
--      PLAYER_REGEN_ENABLED;
--   2. the history commit takes no snapshot on that frame and pushes no entry;
--      the deferred entry lands when the menu opens again;
--   3. the same holds when only the minimized bar is on screen (the fallback
--      combat listener quiesces the runtime itself);
--   4. the refusal source answers true for the event and for the rest of its
--      frame, and false again once the lockdown ended;
--   5. MSUF Edit Mode, closed by its own combat listener (sent the event
--      alone), defers its open move the same way: no snapshot, no entry on
--      that frame, the entry after combat.
-- Boots the real core and Options graph of one client (client_world.lua).
-- Plain Lua 5.1, repo root and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_combat_edge_refusal_smoke " .. flavor .. ": " .. message, 2) end
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
e.MSUF_EnsureDB(true)
e.UIErrorsFrame = { AddMessage = function() end }

-- The apply owner the flush asks for a unit (ApplyService FlushPendingUnits),
-- counted instead of run: the engine itself is not what this smoke models.
local applied = {}
Check(e.MSUF_UFCore_NotifyConfigChanged, "the unit-frame apply owner is not published")
e.MSUF_UFCore_NotifyConfigChanged = function(unit)
    applied[#applied + 1] = tostring(unit)
    return true
end
-- The history snapshot (Bindings_History SnapshotDB) copies the profile here.
local variants = Check(n.ProfileVariants, "MSUF.ProfileVariants is missing")
local baseSnapshot, snapshots = variants.BaseSnapshot, 0
variants.BaseSnapshot = function(...)
    snapshots = snapshots + 1
    return baseSnapshot(...)
end

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
local function OptionsListeners(event, fileSuffix)
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
local function Fire(event)
    local listeners = OptionsListeners(event)
    for i = 1, #listeners do listeners[i].handler(listeners[i].frame, event) end
    return #listeners
end

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
    Check(win:IsShown(), "the menu is not open " .. label)
end

local function UndoCount()
    local state = M.GetHistoryState and M.GetHistoryState() or {}
    return tonumber(state.undoCount) or 0
end

-- Queue a player-frame apply and, while the window holds a history session,
-- open a slider transaction that changed a setting. Nothing may run before
-- combat starts. A minimized menu has ended its session (the window hid).
local function PrepareMenuWork(label, width, slider)
    applied = {}
    Check(M.ApplyService.RequestUnit("player", "SMOKE_COMBAT_EDGE") ~= false, "the player apply was not queued " .. label)
    if slider then
        Check(M.BeginHistoryTransaction("Smoke slider " .. label, "menu:slider:smoke") == true,
            "the slider transaction did not open " .. label)
        e.MSUF_DB.player.width = width
    end
    Check(#applied == 0, "the queued apply ran before combat " .. label)
end

-- PLAYER_REGEN_DISABLED in the client's order: the lockdown is still false.
local function CombatStartFrame(label, expectListener)
    local undoBefore = UndoCount()
    snapshots = 0
    Check(not e.InCombatLockdown(), "the harness entered lockdown before PLAYER_REGEN_DISABLED")
    Check(Fire("PLAYER_REGEN_DISABLED") > 0, "no Options listener heard PLAYER_REGEN_DISABLED " .. label)
    if expectListener then
        Check(#OptionsListeners("PLAYER_REGEN_DISABLED", expectListener) == 0,
            "the " .. expectListener .. " combat listener stayed registered " .. label)
    end
    Check(not win:IsShown() and not bar:IsShown(), "combat left the menu on screen " .. label)
    Check(#applied == 0, "the pending player apply ran on the combat-start frame " .. label
        .. " (" .. table.concat(applied, ",") .. ")")
    Check(snapshots == 0, "the history commit took " .. snapshots .. " profile snapshot(s) on the combat-start frame " .. label)
    Check(UndoCount() == undoBefore, "the history commit pushed an entry on the combat-start frame " .. label)
    Check(M.IsConfigCombatLocked() == true and e.MSUF_IsConfigCombatLocked() == true,
        "the combat refusal answered false for the rest of the combat-start frame " .. label)
    -- The lockdown starts after the dispatch; the queued flush timer is gone.
    world.widgets:SetCombat(true)
    world.widgets:RunTimers()
    Check(#applied == 0, "the pending player apply ran during lockdown " .. label)
    return undoBefore
end

local function CombatEnd(label, undoBefore, slider)
    world.widgets:AdvanceTime(1)
    world.widgets:SetCombat(false)
    Check(e.MSUF_IsConfigCombatLocked() == false, "the combat refusal still answers true after the lockdown " .. label)
    Fire("PLAYER_REGEN_ENABLED")
    world.widgets:RunTimers()
    local players = 0
    for i = 1, #applied do if applied[i] == "player" then players = players + 1 end end
    Check(players == 1, "the deferred player apply ran " .. players .. " time(s) after combat " .. label)
    OpenMenu("after combat " .. label)
    local want = undoBefore + (slider and 1 or 0)
    Check(UndoCount() == want, "after combat the history holds " .. UndoCount() .. " entries, not " .. want .. " " .. label)
end

---------------------------------------------------------------------------
-- 1 + 2. The open window
---------------------------------------------------------------------------
OpenMenu("before combat")
local width = tonumber(e.MSUF_DB.player.width) or 200
PrepareMenuWork("(window)", width + 7, true)
local undoBefore = CombatStartFrame("(window)")
CombatEnd("(window)", undoBefore, true)

---------------------------------------------------------------------------
-- 3. Only the minimized bar is on screen
---------------------------------------------------------------------------
Check(M.MinimizeSlashMenuWindow(win), "the menu did not minimize")
local driver = win._msuf2WindowLayoutDriver
local step = driver and driver:GetScript("OnUpdate")
if step then step(driver, 10) end
world.widgets:RunTimers()
Check(bar:IsShown() and not win:IsShown(), "minimizing did not leave the bar alone on screen")
Check(#OptionsListeners("PLAYER_REGEN_DISABLED", "MSUF_Menu2_API.lua") == 1,
    "the minimized bar has no combat listener of its own")
PrepareMenuWork("(minimized bar)", width + 11, false)
undoBefore = CombatStartFrame("(minimized bar)", "MSUF_Menu2_API.lua")
CombatEnd("(minimized bar)", undoBefore, false)

---------------------------------------------------------------------------
-- 4. The refusal source itself
---------------------------------------------------------------------------
world.widgets:AdvanceTime(1)
Check(e.MSUF_IsConfigCombatLocked() == false, "the refusal answers true out of combat")
Check(e.MSUF_IsConfigCombatLocked("PLAYER_REGEN_DISABLED") == true, "the refusal ignores PLAYER_REGEN_DISABLED")
Check(M.IsConfigCombatLocked() == true, "the menu refusal forgot the combat edge within its frame")
world.widgets:AdvanceTime(1)
Check(M.IsConfigCombatLocked() == false, "the combat edge outlived its frame without a lockdown")
world.widgets:SetCombat(true)
Check(M.IsConfigCombatLocked() == true, "the refusal ignores the lockdown")
world.widgets:SetCombat(false)
Check(M.IsConfigCombatLocked("PLAYER_REGEN_ENABLED") == false, "the refusal holds after PLAYER_REGEN_ENABLED")

---------------------------------------------------------------------------
-- 5. MSUF Edit Mode's own combat exit
---------------------------------------------------------------------------
do
    world.widgets:AdvanceTime(1)
    M.HideSlashMenuAndMinibar(win)
    world.widgets:RunTimers()
    -- The unit-frame engine is not what this section models
    -- (editmode_shell_locale_smoke does the same).
    n.UF.Apply = function() return true end
    e.MSUF_ForceReanchorAllUnitFrames_Once = function() end
    local EM2 = Check(e.MSUF_EM2, "MSUF Edit Mode did not load")
    Check(EM2.State.Enter("player") == true, "Edit Mode did not open")
    world.widgets:RunTimers()
    Check(EM2.Undo.BeginChange("unit", "player", "Move") == true, "the Edit Mode move did not open its transaction")
    e.MSUF_DB.player.offsetX = (tonumber(e.MSUF_DB.player.offsetX) or 0) + 5
    local listener
    for _, frame in ipairs(world.widgets.frames) do
        local handler = frame.events and frame.events.PLAYER_REGEN_DISABLED and frame:GetScript("OnEvent")
        if handler and debug.getinfo(handler, "S").source:find("MSUF_EditMode_State.lua", 1, true) then
            listener = { frame = frame, handler = handler }
        end
    end
    if Check(listener, "Edit Mode registered no combat listener") then
        local undoBefore = UndoCount()
        snapshots = 0
        listener.handler(listener.frame, "PLAYER_REGEN_DISABLED")
        Check(EM2.State.IsActive and EM2.State.IsActive() ~= true, "combat left Edit Mode open")
        Check(snapshots == 0, "the Edit Mode exit took " .. snapshots .. " profile snapshot(s) on the combat-start frame")
        Check(UndoCount() == undoBefore, "the Edit Mode exit pushed an entry on the combat-start frame")
        world.widgets:SetCombat(true)
        world.widgets:AdvanceTime(1)
        world.widgets:SetCombat(false)
        Fire("PLAYER_REGEN_ENABLED")
        listener.handler(listener.frame, "PLAYER_REGEN_ENABLED")
        world.widgets:RunTimers()
        OpenMenu("after the Edit Mode combat exit")
        Check(UndoCount() == undoBefore + 1, "the deferred Edit Mode move did not land after combat")
    end
end

print(string.format("menu_combat_edge_refusal_smoke: ok (%s: the combat-start frame defers the apply and the history commit)",
    flavor))
