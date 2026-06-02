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
A.Workflow.EditMode = A.Workflow.EditMode or {}

local EditMode = A.Workflow.EditMode
local SOURCE_FILE = "Shell/Menu2/Assistant/MSUF_AssistantRegistry_EditMode.lua"
local SOURCE_CONTROL = "M.SetMSUFEditModeActive / M.CancelMSUFEditMode / M.ToggleMSUFEditMode"

local function Status()
    if M and type(M.EditModeLifecycleStatus) == "function" then
        return M.EditModeLifecycleStatus(true)
    end
    return {
        active = _G.MSUF_UnitEditModeActive == true,
        combatLocked = ((_G.InCombatLockdown and _G.InCombatLockdown()) or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))) and true or false,
        unitKey = _G.MSUF_CurrentEditUnitKey,
        hasDirectHelper = type(_G.MSUF_SetMSUFEditModeDirect) == "function" or type(_G.MSUF_SetEditMode) == "function",
        hasStateEnter = false,
        hasStateExit = false,
        hasStateCancel = false,
    }
end

local function Refresh()
    if M and type(M.RefreshMenuFramePriority) == "function" then M.RefreshMenuFramePriority() end
    if M and type(M.RefreshDashboardEditModeButton) == "function" then M.RefreshDashboardEditModeButton() end
    if M and M.frame and type(M.frame.RefreshStatus) == "function" then M.frame:RefreshStatus() end
end

function EditMode.StatusText(reason)
    local st = Status()
    local lines = {}
    lines[#lines + 1] = st.active and "MSUF Edit Mode is enabled." or "MSUF Edit Mode is disabled."
    if st.unitKey then lines[#lines + 1] = "Focused unit: " .. tostring(st.unitKey) end
    lines[#lines + 1] = "Combat locked: " .. (st.combatLocked and "yes" or "no")
    lines[#lines + 1] = "Enter/exit helper: " .. ((st.hasDirectHelper or st.hasStateEnter or st.hasStateExit) and "available" or "missing")
    lines[#lines + 1] = "Cancel helper: " .. (st.hasStateCancel and "available" or "missing")
    if reason == "why_exit" then
        if not st.active then
            lines[#lines + 1] = "Exit is not needed because MSUF Edit Mode is already disabled."
        elseif st.hasDirectHelper or st.hasStateExit then
            lines[#lines + 1] = "Exit should be available through the shared MSUF Edit Mode helper."
        else
            lines[#lines + 1] = "I could not exit Edit Mode because no shared helper is available."
        end
    end
    return table.concat(lines, "\n")
end

local function EditModeFailureText(kind, reason)
    if reason == "combat_locked" then return "Edit Mode is locked in combat." end
    if reason == "missing_enter_helper" then return "I could not enter Edit Mode because no shared helper is available." end
    if reason == "missing_exit_helper" then return "I could not exit Edit Mode because no shared helper is available." end
    if reason == "missing_cancel_helper" then return "I could not cancel Edit Mode because no shared cancel helper is available." end
    if kind == "exit" then return "I could not exit Edit Mode because no shared helper is available." end
    if kind == "cancel" then return "I could not cancel Edit Mode because no shared cancel helper is available." end
    return "Edit Mode control is not available right now."
end

function EditMode.Set(active, unitKey)
    if not (M and type(M.SetMSUFEditModeActive) == "function") then
        return false, active and "missing_enter_helper" or "missing_exit_helper"
    end
    local ok, reason = M.SetMSUFEditModeActive(active and true or false, unitKey, {
        includeBlizzard = true,
        source = "assistant",
    })
    Refresh()
    return ok, reason
end

function EditMode.Cancel()
    if not (M and type(M.CancelMSUFEditMode) == "function") then
        return false, "missing_cancel_helper"
    end
    local ok, reason = M.CancelMSUFEditMode({ includeBlizzard = true, source = "assistant_cancel" })
    Refresh()
    return ok, reason
end

function EditMode.Toggle(unitKey)
    if not (M and type(M.ToggleMSUFEditMode) == "function") then
        return false, "missing_enter_helper"
    end
    local ok, reason = M.ToggleMSUFEditMode(unitKey, {
        includeBlizzard = true,
        source = "assistant_toggle",
    })
    Refresh()
    return ok, reason
end

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

Registry:RegisterAction({
    key = "assistant.diagnostic.editMode.status",
    label = "Show MSUF Edit Mode Status",
    type = "diagnostic",
    combatSafe = true,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_CONTROL,
    lifecycle = LIFECYCLE,
    run = function(args)
        local text = EditMode.StatusText(args and args.reason)
        if A and type(A.ShowLargeTextPanel) == "function" then
            A.ShowLargeTextPanel({
                kind = "text",
                title = "MSUF Edit Mode",
                help = "Read-only lifecycle status for the shared MSUF Edit Mode helpers.",
                text = text,
                status = "No settings changed.",
            })
        end
        return true, text
    end,
})
