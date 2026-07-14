-- Assistant Dashboard panel and navigation workflow helpers.
-- Loaded before MSUF_AssistantRegistry_Dashboard.lua; actions consume these A.Workflow helpers.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.Workflow = A.Workflow or {}

local DASHBOARD_PANEL_FIELDS = {
    recovery = { field = "dashboardRecoveryOpen", label = "Dashboard recovery tools" },
    scaling = { field = "dashboardScalingOpen", label = "Dashboard scaling tools" },
    changelog = { field = "dashboardChangelogOpen", label = "Dashboard changelog" },
}

function A.Workflow.SetDashboardPanel(panel, open)
    if panel == "all" then
        if open ~= false then return false, "Which Dashboard panel do you want me to change?" end
        for _, entry in pairs(DASHBOARD_PANEL_FIELDS) do
            if M and type(M.PersistMenuStateValue) == "function" then
                M.PersistMenuStateValue(entry.field, false)
            elseif M then
                M[entry.field] = false
            end
        end
        if M and type(M.InvalidatePage) == "function" then M.InvalidatePage("home") end
        if M and type(M.Open) == "function" then
            if M.Open("home") == false then return false, "Open the MSUF menu first so I can navigate the Dashboard." end
        elseif M and type(M.SelectPage) == "function" then
            if M.SelectPage("home") == false then return false, "Open the MSUF menu first so I can navigate the Dashboard." end
        else
            return false, "Open the MSUF menu first so I can navigate the Dashboard."
        end
        return true, "Closed all optional Dashboard panels."
    end
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
