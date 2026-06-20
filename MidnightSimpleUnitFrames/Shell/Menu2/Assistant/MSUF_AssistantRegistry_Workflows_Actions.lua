-- Assistant workflow action registrations.
-- Loaded before MSUF_AssistantRegistry_Workflows.lua; the main workflow module passes its helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.Workflow = A.Workflow or {}

function A.Workflow.RegisterCoreActions(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local Trim = ctx.Trim or function(text)
        text = tostring(text or "")
        return (text:gsub("^%s+", ""):gsub("%s+$", ""))
    end

    if not (Registry and type(Registry.RegisterAction) == "function") then return end
    local RegisterProfileWorkflowActions = A.Workflow and A.Workflow.RegisterProfileWorkflowActions
    if type(RegisterProfileWorkflowActions) ~= "function" then return end

    Registry:RegisterAction({
        key = "assistant.workflow.status",
        label = "Show Assistant Step Status",
        type = "diagnostic",
        combatSafe = true,
        lifecycle = { workflow = "assistant", canStart = true, canCancel = true, canExitStop = true, canReportStatus = true },
        run = function()
            local text = A.Workflow.WorkflowStatusText()
            if type(A.ShowLargeTextPanel) == "function" then
                A.ShowLargeTextPanel({ kind = "text", title = "Assistant Steps", help = "Current confirmations, guided steps, panels, and Edit Mode state.", text = text, status = "No MSUF options were changed." })
            end
            return true, text
        end,
    })

    Registry:RegisterAction({
        key = "assistant.workflow.cancel",
        label = "Cancel Current Assistant Step",
        type = "setup",
        combatSafe = true,
        lifecycle = { workflow = "assistant", canCancel = true, canExitStop = true, canReportStatus = true },
        run = function()
            return A.Workflow.CancelActiveWorkflow()
        end,
    })

    Registry:RegisterAction({
        key = "assistant.panel.close",
        label = "Close Assistant Panel",
        type = "navigation",
        combatSafe = true,
        lifecycle = { workflow = "assistantPanel", canCancel = true, canExitStop = true, canReportStatus = true },
        run = function()
            return A.Workflow.CloseLargePanel()
        end,
    })

    Registry:RegisterAction({
        key = "dashboard_page_back",
        label = "Open Previous Dashboard Page",
        type = "navigation",
        combatSafe = true,
        lifecycle = { workflow = "dashboardNavigation", canStart = true, canExitStop = true, canReportStatus = true },
        run = function()
            return A.Workflow.GoBackPage()
        end,
    })

    Registry:RegisterAction({
        key = "dashboard_page_forward",
        label = "Open Next Dashboard Page",
        type = "navigation",
        combatSafe = true,
        lifecycle = { workflow = "dashboardNavigation", canStart = true, canExitStop = true, canReportStatus = true },
        run = function()
            return A.Workflow.GoForwardPage()
        end,
    })

    Registry:RegisterAction({
        key = "start_unit_custom_anchor_picker",
        label = "Start Unit Custom Anchor Picker",
        type = "navigation",
        combatSafe = false,
        lifecycle = { workflow = "customAnchorPicker", canStart = true, canCancel = true, canExitStop = true, canReportStatus = true },
        run = function(args)
            return A.Workflow.StartUnitAnchorPicker(args and args.unit)
        end,
    })

    Registry:RegisterAction({
        key = "start_group_custom_anchor_picker",
        label = "Start Group Custom Anchor Picker",
        type = "navigation",
        combatSafe = false,
        lifecycle = { workflow = "customAnchorPicker", canStart = true, canCancel = true, canExitStop = true, canReportStatus = true },
        run = function(args)
            return A.Workflow.StartGroupAnchorPicker(args and args.scope)
        end,
    })

    Registry:RegisterAction({
        key = "cancel_custom_anchor_picker",
        label = "Cancel Custom Anchor Picker",
        type = "navigation",
        combatSafe = true,
        lifecycle = { workflow = "customAnchorPicker", canCancel = true, canExitStop = true, canReportStatus = true },
        run = function()
            return A.Workflow.CancelAnchorPicker()
        end,
    })

    Registry:RegisterAction({
        key = "custom_anchor_picker_status",
        label = "Show Custom Anchor Picker Status",
        type = "diagnostic",
        combatSafe = true,
        lifecycle = { workflow = "customAnchorPicker", canReportStatus = true },
        run = function()
            return true, A.Workflow.AnchorPickerStatus()
        end,
    })

    RegisterProfileWorkflowActions(ctx)
end
