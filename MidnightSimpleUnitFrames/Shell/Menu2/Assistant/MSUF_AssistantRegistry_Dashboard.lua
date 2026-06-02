local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry
if not (Registry and type(Registry.RegisterAction) == "function") then return end

A.Workflow = A.Workflow or {}

local function ActiveProfileName()
    local name = tostring(_G.MSUF_ActiveProfile or "Default")
    if name == "" then return "Default" end
    return name
end

function A.Workflow.DashboardState()
    _G.MSUF_GlobalDB = type(_G.MSUF_GlobalDB) == "table" and _G.MSUF_GlobalDB or {}
    _G.MSUF_GlobalDB.global = type(_G.MSUF_GlobalDB.global) == "table" and _G.MSUF_GlobalDB.global or {}
    _G.MSUF_GlobalDB.global.dashboard = type(_G.MSUF_GlobalDB.global.dashboard) == "table" and _G.MSUF_GlobalDB.global.dashboard or {}
    return _G.MSUF_GlobalDB.global.dashboard
end

function A.Workflow.SetWagoBackupConfirmed(confirmed)
    local dash = A.Workflow.DashboardState()
    dash.wagoProfileBackupConfirmed = type(dash.wagoProfileBackupConfirmed) == "table" and dash.wagoProfileBackupConfirmed or {}
    if confirmed == true then
        dash.wagoProfileBackupConfirmed[ActiveProfileName()] = true
    else
        dash.wagoProfileBackupConfirmed[ActiveProfileName()] = nil
    end
    if M and type(M.InvalidatePage) == "function" then M.InvalidatePage("home") end
    if M and type(M.SelectPage) == "function" then M.SelectPage("home") end
    return true
end

local DASHBOARD_PANEL_FIELDS = {
    recovery = { field = "dashboardRecoveryOpen", label = "Dashboard recovery tools" },
    scaling = { field = "dashboardScalingOpen", label = "Dashboard scaling tools" },
    changelog = { field = "dashboardChangelogOpen", label = "Dashboard changelog" },
}

function A.Workflow.SetDashboardPanel(panel, open)
    local spec = DASHBOARD_PANEL_FIELDS[tostring(panel or "")]
    if not spec then return false, "I do not know which Dashboard panel to change." end
    if open == nil then
        open = not (M and M[spec.field] == true)
    else
        open = open and true or false
    end
    if M and type(M.PersistMenuStateValue) == "function" then
        M.PersistMenuStateValue(spec.field, open)
    elseif M then
        M[spec.field] = open
    end
    if M and type(M.InvalidatePage) == "function" then M.InvalidatePage("home") end
    if M and type(M.Open) == "function" then
        if M.Open("home") == false then return false, "Dashboard navigation is not available right now." end
    elseif M and type(M.SelectPage) == "function" then
        if M.SelectPage("home") == false then return false, "Dashboard navigation is not available right now." end
    else
        return false, "Dashboard navigation is not available right now."
    end
    return true, (open and "Opened " or "Closed ") .. spec.label .. "."
end

function A.Workflow.OpenDashboardPanel(panel)
    return A.Workflow.SetDashboardPanel(panel, true)
end

function A.Workflow.ControlMenuWindow(command)
    command = tostring(command or "")
    local frame = M and M.frame or nil
    if command == "close" then
        if M and type(M.HideSlashMenuAndMinibar) == "function" then
            M.HideSlashMenuAndMinibar(frame)
            return true, "Closed the MSUF menu."
        end
        return false, "Menu close is not available right now."
    end
    if command == "minimize" then
        if M and type(M.MinimizeSlashMenuWindow) == "function" then
            if M.MinimizeSlashMenuWindow(frame) ~= false then return true, "Minimized the MSUF menu." end
        end
        return false, "Menu minimize is not available right now."
    end
    if command == "maximize" then
        if M and type(M.MaximizeSlashMenuWindow) == "function" then
            if M.MaximizeSlashMenuWindow(frame) ~= false then return true, "Maximized or restored the MSUF menu." end
        end
        return false, "Menu maximize is not available right now."
    end
    if command == "restore" then
        if M and M.minimizedBar and M.minimizedBar.IsShown and M.minimizedBar:IsShown() and type(M.RestoreMinimizedSlashMenu) == "function" then
            if M.RestoreMinimizedSlashMenu(frame) ~= false then return true, "Restored the MSUF menu." end
        end
        if M and type(M.RestoreSlashMenuWindow) == "function" then
            if M.RestoreSlashMenuWindow(frame) ~= false then return true, "Restored the MSUF menu." end
        end
        return false, "Menu restore is not available right now."
    end
    return false, "I do not know which menu window action to run."
end

function A.Workflow.StageFactoryReset()
    if not (M and type(M.StageFactoryReset) == "function") then
        return false, "Factory reset is not available right now."
    end
    if M.StageFactoryReset() then
        return true, "Done. Factory reset is staged. Reload UI to rebuild clean defaults."
    end
    return false, "Factory reset could not be staged right now."
end

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
    aliases = { "maximize menu", "maximize msuf menu", "maximize dashboard", "fullscreen menu", "restore maximized menu" },
    combatSafe = true,
    run = function()
        return A.Workflow.ControlMenuWindow("maximize")
    end,
})

Registry:RegisterAction({
    key = "menu_window_restore",
    label = "Restore MSUF Menu",
    type = "navigation",
    aliases = { "restore menu", "restore msuf menu", "restore dashboard", "unminimize menu", "show minimized menu" },
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
