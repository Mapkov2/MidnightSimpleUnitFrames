-- Assistant Dashboard panel and navigation workflow helpers.
-- Loaded before MSUF_AssistantRegistry_Dashboard.lua; actions consume these A.Workflow helpers.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value) _G[name] = value; return value end

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.Workflow = A.Workflow or {}

local function ActiveProfileName()
    local name = tostring(_G.MSUF_ActiveProfile or "Default")
    if name == "" then return "Default" end
    return name
end

function A.Workflow.DashboardState()
    -- Dashboard state lives in the global DB because it describes UI guidance/recovery
    -- progress, not the active profile's unitframe layout.
    ExportPublic("MSUF_GlobalDB", type(_G.MSUF_GlobalDB) == "table" and _G.MSUF_GlobalDB or {})
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
    if not spec then return false, "Which Dashboard panel do you want me to change?" end
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
        if M.Open("home") == false then return false, "Open the MSUF menu first so I can navigate the Dashboard." end
    elseif M and type(M.SelectPage) == "function" then
        if M.SelectPage("home") == false then return false, "Open the MSUF menu first so I can navigate the Dashboard." end
    else
        return false, "Open the MSUF menu first so I can navigate the Dashboard."
    end
    return true, (open and "Opened " or "Closed ") .. spec.label .. "."
end

function A.Workflow.OpenDashboardPanel(panel)
    return A.Workflow.SetDashboardPanel(panel, true)
end
