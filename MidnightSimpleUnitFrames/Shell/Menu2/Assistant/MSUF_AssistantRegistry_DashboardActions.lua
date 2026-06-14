local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- Dashboard assistant action domain.
-- Depends on MSUF_AssistantRegistry_Dashboard.lua for workflow helpers.
local ctx = A.DashboardRegistry and A.DashboardRegistry.Actions
if type(ctx) ~= "table" then return end

local Registry = ctx.Registry
A = ctx.A or A
M = ctx.M or M

if not (Registry and type(Registry.RegisterAction) == "function") then return end

local function StageFactoryReset()
    if not (M and type(M.StageFactoryReset) == "function") then
        return false, "Factory reset is not available right now."
    end
    if M.StageFactoryReset() then
        return true, "Done. Factory reset is staged. Reload UI to rebuild clean defaults."
    end
    return false, "Factory reset could not be staged right now."
end

A.Workflow = A.Workflow or {}
A.Workflow.StageFactoryReset = StageFactoryReset

Registry:RegisterAction({
    key = "confirm_wago_backup",
    label = "Confirm Wago Backup",
    type = "setup",
    combatSafe = true,
    run = function(args)
        local confirmed = not (args and args.confirmed == false)
        A.Workflow.SetWagoBackupConfirmed(confirmed)
        return true, confirmed and "Done. Wago backup is marked confirmed for this profile." or "Done. Wago backup confirmation was cleared for this profile."
    end,
})

Registry:RegisterAction({
    key = "open_recovery_tools",
    label = "Open Recovery Tools",
    type = "navigation",
    combatSafe = true,
    run = function()
        return A.Workflow.OpenDashboardPanel("recovery")
    end,
})

Registry:RegisterAction({
    key = "open_dashboard_panel",
    label = "Open Dashboard Panel",
    type = "navigation",
    combatSafe = true,
    run = function(args)
        return A.Workflow.OpenDashboardPanel(args and args.panel)
    end,
})

Registry:RegisterAction({
    key = "set_dashboard_panel",
    label = "Set Dashboard Panel",
    type = "navigation",
    aliases = {
        "open dashboard panel", "close dashboard panel", "toggle dashboard panel",
        "open recovery tools", "close recovery tools", "toggle recovery tools",
        "open scaling tools", "close scaling tools", "toggle scaling tools",
        "open changelog", "close changelog", "toggle changelog",
    },
    combatSafe = true,
    run = function(args)
        return A.Workflow.SetDashboardPanel(args and args.panel, args and args.open)
    end,
})

Registry:RegisterAction({
    key = "set_nav_section",
    label = "Set Navigation Section",
    type = "navigation",
    aliases = {
        "open navigation section", "close navigation section", "toggle navigation section",
        "expand frames section", "collapse frames section",
        "expand group frames section", "collapse group frames section",
        "expand appearance section", "collapse appearance section",
        "expand advanced section", "collapse advanced section",
    },
    combatSafe = true,
    run = function(args)
        return A.Workflow.SetNavSection(args and args.section, args and args.open)
    end,
})

Registry:RegisterAction({
    key = "set_nav_search_intro",
    label = "Set Search Intro",
    type = "navigation",
    aliases = {
        "show search intro", "hide search intro", "reset search intro",
        "mark search intro seen", "show ask msuf intro",
    },
    combatSafe = true,
    run = function(args)
        return A.Workflow.SetNavSearchIntro(args and args.command)
    end,
})

Registry:RegisterAction({
    key = "set_menu_selector_state",
    label = "Set Menu Selector State",
    type = "navigation",
    aliases = {
        "select text tab", "select text slot", "select status tab", "select status indicator",
        "select group status icon", "select spell indicator", "select corner editor slot",
        "select power color token", "select class resource color token",
        "select class power style tab", "select class resource style tab", "select class resources style area",
        "select highlight borders tab", "select bars highlight tab", "select highlight area",
        "move text as one group", "move text per slot", "text move together",
        "select profile export kind", "set profile staging field", "set profile string field",
        "set unit copy category", "select unit copy categories",
        "set group copy category", "select group copy categories",
    },
    combatSafe = true,
    run = function(args)
        return A.Workflow.SetMenuSelectorState(args)
    end,
})

Registry:RegisterAction({
    key = "menu_window_close",
    label = "Close MSUF Menu",
    type = "navigation",
    aliases = { "close menu", "close msuf menu", "close dashboard", "hide menu", "hide msuf menu" },
    combatSafe = true,
    run = function()
        return A.Workflow.ControlMenuWindow("close")
    end,
})

Registry:RegisterAction({
    key = "menu_window_minimize",
    label = "Minimize MSUF Menu",
    type = "navigation",
    aliases = { "minimize menu", "minimize msuf menu", "minimize dashboard", "collapse menu window" },
    combatSafe = true,
    run = function()
        return A.Workflow.ControlMenuWindow("minimize")
    end,
})

Registry:RegisterAction({
    key = "menu_window_maximize",
    label = "Maximize MSUF Menu",
    type = "navigation",
    aliases = { "maximize menu", "maximize msuf menu", "maximize dashboard", "fullscreen menu" },
    combatSafe = true,
    run = function()
        return A.Workflow.ControlMenuWindow("maximize")
    end,
})

Registry:RegisterAction({
    key = "menu_window_restore",
    label = "Restore MSUF Menu",
    type = "navigation",
    aliases = { "restore menu", "restore msuf menu", "restore dashboard", "restore maximized menu", "unminimize menu", "show minimized menu" },
    combatSafe = true,
    run = function()
        return A.Workflow.ControlMenuWindow("restore")
    end,
})

Registry:RegisterAction({
    key = "assistant.action.history.undo",
    label = "Undo Last Assistant Change",
    type = "history",
    combatSafe = false,
    run = function()
        if not (A and type(A.UndoLast) == "function") then
            return false, "Assistant undo is not available right now."
        end
        return A.UndoLast()
    end,
})

Registry:RegisterAction({
    key = "assistant.action.history.redo",
    label = "Redo Last Assistant Change",
    type = "history",
    combatSafe = false,
    run = function()
        if not (A and type(A.RedoLast) == "function") then
            return false, "Assistant redo is not available right now."
        end
        return A.RedoLast()
    end,
})

Registry:RegisterAction({
    key = "menu_history_undo",
    label = "Undo Last Menu Change",
    type = "history",
    aliases = { "undo menu change", "undo menu history", "undo ui change", "undo navrail history" },
    combatSafe = false,
    run = function()
        if not (M and type(M.Undo) == "function") then return false, "MSUF menu undo is not available right now." end
        local ok = M.Undo()
        if ok then return true, "Done. Undid the last MSUF menu change." end
        return false, "There is no MSUF menu change to undo."
    end,
})

Registry:RegisterAction({
    key = "menu_history_redo",
    label = "Redo Last Menu Change",
    type = "history",
    aliases = { "redo menu change", "redo menu history", "redo ui change", "redo navrail history" },
    combatSafe = false,
    run = function()
        if not (M and type(M.Redo) == "function") then return false, "MSUF menu redo is not available right now." end
        local ok = M.Redo()
        if ok then return true, "Done. Redid the last MSUF menu change." end
        return false, "There is no MSUF menu change to redo."
    end,
})

Registry:RegisterAction({
    key = "menu_history_reset_session",
    label = "Reset Menu Session Changes",
    type = "history",
    aliases = {
        "reset all menu changes", "reset menu session changes", "reset all session changes",
        "reset msuf2 menu changes", "reset navrail history session",
    },
    combatSafe = false,
    confirmRequired = true,
    captureProfileSnapshot = true,
    run = function()
        if not (M and type(M.ResetHistorySession) == "function") then return false, "MSUF menu session reset is not available right now." end
        local state = M.GetHistoryState and M.GetHistoryState() or nil
        if state and not state.canResetAll then return false, "There are no MSUF menu session changes to reset." end
        local ok = M.ResetHistorySession()
        if ok then return true, "Done. Reset all MSUF menu changes from this open session." end
        return false, "MSUF menu session changes could not be reset right now."
    end,
})

Registry:RegisterAction({
    key = "factory_reset_all",
    label = "Factory Reset All",
    type = "reset",
    combatSafe = false,
    confirmRequired = true,
    captureProfileSnapshot = true,
    run = function()
        return A.Workflow.StageFactoryReset()
    end,
})
