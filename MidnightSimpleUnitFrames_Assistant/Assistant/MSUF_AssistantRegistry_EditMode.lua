-- Assistant EditMode registry: exposes safe EditMode lifecycle and window controls.
-- Protected frame changes must continue through EditMode helpers and combat guards.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value) _G[name] = value; return value end
local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry
if not (Registry and type(Registry.RegisterAction) == "function") then return end

A.Workflow = A.Workflow or {}
A.Workflow.EditMode = A.Workflow.EditMode or {}

-- Edit Mode assistant actions.
-- This domain coordinates Menu2/HUD lifecycle helpers and reports combat-locked state. It
-- does not bypass secure-frame restrictions; direct frame moves stay in edit-mode runtime.
local EditMode = A.Workflow.EditMode
local SOURCE_FILE = "Shell/Menu2/Assistant/MSUF_AssistantRegistry_EditMode.lua"
local SOURCE_CONTROL = "M.SetMSUFEditModeActive / M.CancelMSUFEditMode / M.ToggleMSUFEditMode"
local SOURCE_HUD = "Shell/UI/EditMode/MSUF_EditMode_HUD.lua"

local BuildSharedHelpers = A.EditModeRegistry and A.EditModeRegistry.BuildSharedHelpers
local SharedHelpers = type(BuildSharedHelpers) == "function" and BuildSharedHelpers({
    M = M,
    MSUF = MSUF,
    ExportPublic = ExportPublic,
}) or {}
local Status = SharedHelpers.Status
local Refresh = SharedHelpers.Refresh
local EnsureDB = SharedHelpers.EnsureDB
local EM2 = SharedHelpers.EM2
local HUD = SharedHelpers.HUD
local Grid = SharedHelpers.Grid
local RefreshHUDControls = SharedHelpers.RefreshHUDControls
local ApplyAllSettings = SharedHelpers.ApplyAllSettings
local ScheduleEditModeSync = SharedHelpers.ScheduleEditModeSync
local ToggleValue = SharedHelpers.ToggleValue
local StateWord = SharedHelpers.StateWord
local StateMessage = SharedHelpers.StateMessage
local Clamp = SharedHelpers.Clamp
local Round = SharedHelpers.Round
local FormatPercent = SharedHelpers.FormatPercent
if type(Status) ~= "function" or type(Refresh) ~= "function" or type(EnsureDB) ~= "function" then return end
if type(EM2) ~= "function" or type(HUD) ~= "function" or type(Grid) ~= "function" then return end
if type(RefreshHUDControls) ~= "function" or type(ApplyAllSettings) ~= "function" or type(ScheduleEditModeSync) ~= "function" then return end
if type(ToggleValue) ~= "function" or type(StateWord) ~= "function" or type(StateMessage) ~= "function" then return end
if type(Clamp) ~= "function" or type(Round) ~= "function" or type(FormatPercent) ~= "function" then return end

local BuildPreviewControls = A.EditModeRegistry and A.EditModeRegistry.BuildPreviewControls
local PreviewControls = type(BuildPreviewControls) == "function" and BuildPreviewControls({
    M = M,
    MSUF = MSUF,
    ExportPublic = ExportPublic,
    EnsureDB = EnsureDB,
    Refresh = Refresh,
    RefreshHUDControls = RefreshHUDControls,
    ToggleValue = ToggleValue,
    StateWord = StateWord,
    StateMessage = StateMessage,
    Status = Status,
}) or {}
EditMode.SetPreview = PreviewControls.SetPreview
EditMode.SetBossPreview = PreviewControls.SetBossPreview
EditMode.SetAuraPreview = PreviewControls.SetAuraPreview
EditMode.SetGroupPreview = PreviewControls.SetGroupPreview

local BuildControlHandlers = A.EditModeRegistry and A.EditModeRegistry.BuildControlHandlers
local ControlHandlers = type(BuildControlHandlers) == "function" and BuildControlHandlers({
    EM2 = EM2,
    HUD = HUD,
    Grid = Grid,
    EnsureDB = EnsureDB,
    RefreshHUDControls = RefreshHUDControls,
    ToggleValue = ToggleValue,
    StateMessage = StateMessage,
    Clamp = Clamp,
    Round = Round,
    FormatPercent = FormatPercent,
    ApplyAllSettings = ApplyAllSettings,
    ScheduleEditModeSync = ScheduleEditModeSync,
}) or {}
EditMode.SetSnap = ControlHandlers.SetSnap
EditMode.SetGrid = ControlHandlers.SetGrid
EditMode.SetGridStep = ControlHandlers.SetGridStep
EditMode.SetBackgroundOpacity = ControlHandlers.SetBackgroundOpacity
EditMode.SetCooldownAnchor = ControlHandlers.SetCooldownAnchor
EditMode.Undo = ControlHandlers.Undo
EditMode.Redo = ControlHandlers.Redo
EditMode.ResetCurrentPosition = ControlHandlers.ResetCurrentPosition
EditMode.OpenAnchorPicker = ControlHandlers.OpenAnchorPicker

function EditMode.StatusText(reason)
    local st = Status()
    local lines = {}
    lines[#lines + 1] = st.active and "MSUF Edit Mode is enabled." or "MSUF Edit Mode is disabled."
    if st.unitKey then lines[#lines + 1] = "Focused unit: " .. tostring(st.unitKey) end
    lines[#lines + 1] = "Combat lock: " .. (st.combatLocked and "yes" or "no")
    lines[#lines + 1] = "Edit Mode controls available: " .. ((st.hasDirectHelper or st.hasStateEnter or st.hasStateExit) and "yes" or "not right now")
    lines[#lines + 1] = "Cancel available: " .. (st.hasStateCancel and "yes" or "not right now")
    if reason == "why_exit" then
        if not st.active then
            lines[#lines + 1] = "MSUF Edit Mode is already disabled."
        elseif st.hasDirectHelper or st.hasStateExit then
            lines[#lines + 1] = "MSUF should be able to leave Edit Mode from here."
        else
            lines[#lines + 1] = "Enter Edit Mode so I can exit it cleanly."
        end
    end
    return table.concat(lines, "\n")
end

local function EditModeFailureText(kind, reason)
    if reason == "combat_locked" then return "Edit Mode has to wait until combat ends." end
    if reason == "missing_enter_helper" then return "MSUF Edit Mode controls are not available from here." end
    if reason == "missing_exit_helper" then return "MSUF Edit Mode exit is not available from here." end
    if reason == "missing_cancel_helper" then return "MSUF Edit Mode cancel is not available from here." end
    if kind == "exit" then return "Enter Edit Mode so I can exit it cleanly." end
    if kind == "cancel" then return "Enter Edit Mode so I can cancel it cleanly." end
    return "Enter Edit Mode so I can change that option."
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

A.EditModeRegistry = A.EditModeRegistry or {}
A.EditModeRegistry.Actions = {
    Status = Status,
    EditModeFailureText = EditModeFailureText,
    SOURCE_FILE = SOURCE_FILE,
    SOURCE_CONTROL = SOURCE_CONTROL,
    SOURCE_HUD = SOURCE_HUD,
}
