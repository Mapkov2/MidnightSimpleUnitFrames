-- Assistant dashboard setup diagnostic helper.
-- Loaded before MSUF_AssistantRegistry_Diagnostics_Gameplay.lua; keeps dashboard setup text separate from gameplay feature checks.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.DiagnosticsRegistry = A.DiagnosticsRegistry or {}

function A.DiagnosticsRegistry.BuildDashboardSetupDiagnostic(ctx)
    if type(ctx) ~= "table" then return nil end

    local Assistant = ctx.A or A
    local Menu = ctx.M or M
    local AddActionChoice = ctx.AddActionChoice
    local AppendFixChoices = ctx.AppendFixChoices

    if type(AddActionChoice) ~= "function" or type(AppendFixChoices) ~= "function" then return nil end

    local function DashboardPageLabel(page)
        if type(page) ~= "string" or page == "" then return "not open" end
        if Assistant and type(Assistant.DisplayPageLabel) == "function" then return Assistant.DisplayPageLabel(page, "MSUF page") end
        return "MSUF page"
    end

    local function GuidedStepLabel()
        local flow = Assistant.pendingFlow
        if type(flow) ~= "table" then return "none" end
        if Assistant.Workflow and type(Assistant.Workflow.FlowLabel) == "function" then return Assistant.Workflow.FlowLabel(flow) end
        return "guided step"
    end

    local function NativeGuidedTourIsActive()
        local tour = MSUF.GuidedTour6 or _G.MSUF_GuidedTour6
        if type(tour) ~= "table" or type(tour.IsActive) ~= "function" then return false end
        local ok, active = pcall(tour.IsActive, tour)
        return ok and active == true
    end

    local function DashboardSetupDiagnosticText()
        local global = type(_G.MSUF_GlobalDB) == "table" and _G.MSUF_GlobalDB or nil
        local dashRoot = global and type(global.global) == "table" and global.global or nil
        local dash = dashRoot and type(dashRoot.dashboard) == "table" and dashRoot.dashboard or {}
        local hasPending = Assistant.pendingConfirmation or (type(Assistant.pendingChoices) == "table" and #Assistant.pendingChoices > 0) or type(Assistant.pendingFlow) == "table"
        local recoveryOpen = dash.dashboardRecoveryOpen == true or (Menu and Menu.dashboardRecoveryOpen == true)
        local scalingOpen = dash.dashboardScalingOpen == true or (Menu and Menu.dashboardScalingOpen == true)
        local changelogOpen = dash.dashboardChangelogOpen == true or (Menu and Menu.dashboardChangelogOpen == true)
        local navReady = (Menu and type(Menu.Open) == "function") or (Menu and type(Menu.SelectPage) == "function")
        local pendingChoices = type(Assistant.pendingChoices) == "table" and #Assistant.pendingChoices or 0
        local function YesNo(value) return value and "yes" or "no" end
        local function OpenClosed(value) return value and "open" or "closed" end
        local lines = {
            "Dashboard setup check:",
            "Current page: " .. DashboardPageLabel(Menu and Menu.activeKey),
            "Dashboard navigation: " .. (navReady and "ready" or "open the menu first"),
            "Pages in back history: " .. tostring(Assistant.Workflow and type(Assistant.Workflow.navStack) == "table" and #Assistant.Workflow.navStack or 0),
            "Confirmation waiting: " .. YesNo(Assistant.pendingConfirmation ~= nil),
            "Choices waiting: " .. (pendingChoices > 0 and tostring(pendingChoices) or "no"),
            "Guided step: " .. GuidedStepLabel(),
            "Native guided tour: " .. tostring(NativeGuidedTourIsActive() and "active" or "inactive"),
            "Recovery panel: " .. OpenClosed(recoveryOpen),
            "Scaling panel: " .. OpenClosed(scalingOpen),
            "Changelog panel: " .. OpenClosed(changelogOpen),
            "Search intro: " .. ((Menu and Menu.searchIntroSeen == true) and "already seen" or "can show"),
        }
        if not (Menu and (type(Menu.Open) == "function" or type(Menu.SelectPage) == "function")) then
            lines[#lines + 1] = "Next step: open the MSUF menu once so I can navigate from there."
        elseif hasPending then
            lines[#lines + 1] = "Next step: answer the current Assistant question, or use 'cancel'."
        else
            lines[#lines + 1] = "Dashboard setup looks OK."
        end
        local choices = {}
        if hasPending then
            AddActionChoice(choices, "assistant.workflow.cancel", {}, "Cancel current Assistant step", "Clears the current prompt, choice, guided step, or panel.")
        end
        if Menu and Menu.searchIntroSeen == true then
            AddActionChoice(choices, "set_nav_search_intro", { command = "reset" }, "Reset Search Intro", "Makes the Ask MSUF search intro eligible to show again.")
        end
        if Menu and Menu.activeKey ~= "home" then
            AddActionChoice(choices, "open_page", { page = "home", label = "Dashboard" }, "Open Dashboard page", "Returns to the Dashboard home page.")
        end
        if not recoveryOpen then
            AddActionChoice(choices, "open_recovery_tools", {}, "Open Recovery Tools", "Opens the Dashboard recovery tools.")
        end
        if not scalingOpen then
            AddActionChoice(choices, "open_dashboard_panel", { panel = "scaling" }, "Open Scaling Tools", "Opens the Dashboard scaling tools.")
        end
        if not changelogOpen then
            AddActionChoice(choices, "open_dashboard_panel", { panel = "changelog" }, "Open Changelog", "Opens the Dashboard changelog panel.")
        end
        return AppendFixChoices(table.concat(lines, "\n"), choices)
    end

    return {
        DashboardSetupDiagnosticText = DashboardSetupDiagnosticText,
    }
end
