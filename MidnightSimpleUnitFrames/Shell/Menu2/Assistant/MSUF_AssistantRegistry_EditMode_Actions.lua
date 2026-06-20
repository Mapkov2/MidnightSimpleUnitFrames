-- Assistant EditMode action registry.
-- Loaded after MSUF_AssistantRegistry_EditMode.lua so actions call the shared workflow helpers.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry
if not (Registry and type(Registry.RegisterAction) == "function") then return end

local EditMode = A.Workflow and A.Workflow.EditMode
local EditModeContext = A.EditModeRegistry and A.EditModeRegistry.Actions
if type(EditMode) ~= "table" or type(EditModeContext) ~= "table" then return end

local Status = EditModeContext.Status
local EditModeFailureText = EditModeContext.EditModeFailureText
if type(Status) ~= "function" or type(EditModeFailureText) ~= "function" then return end

local SOURCE_FILE = EditModeContext.SOURCE_FILE or "Shell/Menu2/Assistant/MSUF_AssistantRegistry_EditMode.lua"
local SOURCE_CONTROL = EditModeContext.SOURCE_CONTROL or "M.SetMSUFEditModeActive / M.CancelMSUFEditMode / M.ToggleMSUFEditMode"
local SOURCE_HUD = EditModeContext.SOURCE_HUD or "Shell/UI/EditMode/MSUF_EditMode_HUD.lua"

local LIFECYCLE = {
    workflow = "editMode",
    canStart = true,
    canConfirmApply = true,
    canCancel = true,
    canExitStop = true,
    canToggle = true,
    canReportStatus = true,
    existingHelper = "M.SetMSUFEditModeActive / M.CancelMSUFEditMode / M.ToggleMSUFEditMode",
}

A.EditModeRegistry.ActionContext = {
    Registry = Registry,
    A = A,
    EditMode = EditMode,
    Status = Status,
    SOURCE_FILE = SOURCE_FILE,
    SOURCE_CONTROL = SOURCE_CONTROL,
    SOURCE_HUD = SOURCE_HUD,
    LIFECYCLE = LIFECYCLE,
}

Registry:RegisterAction({
    key = "assistant.action.editMode.enter",
    label = "Enter MSUF Edit Mode",
    type = "setup",
    combatSafe = false,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_CONTROL,
    lifecycle = LIFECYCLE,
    run = function(args)
        local ok, reason = EditMode.Set(true, args and args.unit)
        if not ok then return false, EditModeFailureText("enter", reason) end
        if reason == "already_enabled" then return true, "MSUF Edit Mode is already enabled." end
        return true, "Done. MSUF Edit Mode enabled."
    end,
})

Registry:RegisterAction({
    key = "assistant.action.editMode.exit",
    label = "Exit MSUF Edit Mode",
    type = "setup",
    combatSafe = true,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_CONTROL,
    lifecycle = LIFECYCLE,
    run = function()
        local ok, reason = EditMode.Set(false)
        if not ok then return false, EditModeFailureText("exit", reason) end
        if reason == "already_disabled" then return true, "MSUF Edit Mode is already disabled." end
        return true, "Done. MSUF Edit Mode disabled."
    end,
})

Registry:RegisterAction({
    key = "assistant.action.editMode.cancel",
    label = "Cancel MSUF Edit Mode",
    type = "setup",
    combatSafe = true,
    confirmRequired = true,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_CONTROL,
    lifecycle = LIFECYCLE,
    run = function()
        local ok, reason = EditMode.Cancel()
        if not ok then return false, EditModeFailureText("cancel", reason) end
        if reason == "already_disabled" then return true, "MSUF Edit Mode is already disabled." end
        return true, "Done. MSUF Edit Mode canceled."
    end,
})

Registry:RegisterAction({
    key = "assistant.action.editMode.toggle",
    label = "Toggle MSUF Edit Mode",
    type = "setup",
    combatSafe = false,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_CONTROL,
    lifecycle = LIFECYCLE,
    run = function(args)
        local wasActive = Status().active == true
        local ok, reason = EditMode.Toggle(args and args.unit)
        if not ok then return false, EditModeFailureText(wasActive and "exit" or "enter", reason) end
        if wasActive then return true, "Done. MSUF Edit Mode disabled." end
        return true, "Done. MSUF Edit Mode enabled."
    end,
})
