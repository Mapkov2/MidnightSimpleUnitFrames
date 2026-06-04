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
local C = A.RegistryCore or {}
if not (Registry and type(Registry.RegisterAction) == "function") then return end

A.Workflow = A.Workflow or {}
A.Workflow.Lifecycle = A.Workflow.Lifecycle or {}

local UnitDB = C.UnitDB or function() return {} end
local GroupDB = C.GroupDB or function() return {} end
local ApplyUnit = C.ApplyUnit or function() end
local ApplyGroup = C.ApplyGroup or function() end
local UNIT_LABELS = C.UNIT_LABELS or A.UnitLabels or {}

local function Trim(text)
    if A.Trim then return A.Trim(text) end
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Normalize(text)
    if A.Normalize then return A.Normalize(text) end
    text = tostring(text or ""):lower():gsub("[,;:!?%(%)]", " "):gsub("%s+", " ")
    return Trim(text)
end

local function IsCancel(text)
    text = Normalize(text)
    return text == "cancel" or text == "no" or text == "nein" or text == "abort" or text == "stop" or text == "close"
end

local function SafeContext()
    if A.GetContext then return A.GetContext() end
    A.context = type(A.context) == "table" and A.context or {}
    return A.context
end

local function SetContextFlow(flow)
    local ctx = SafeContext()
    if ctx then ctx.pendingFlow = flow end
end

function A.StartPendingFlow(kind, data)
    if type(kind) ~= "string" or kind == "" then return false end
    data = type(data) == "table" and data or {}
    data.kind = kind
    A.pendingFlow = data
    SetContextFlow({ kind = kind, label = data.label, source = data.source, target = data.target })
    return true
end

function A.ClearPendingFlow()
    A.pendingFlow = nil
    local ctx = A.GetContext and A.GetContext()
    if ctx then ctx.pendingFlow = nil end
end

function A.Workflow.PendingFlow()
    if type(A.pendingFlow) == "table" then return A.pendingFlow end
    local ctx = A.GetContext and A.GetContext()
    if type(ctx) == "table" and type(ctx.pendingFlow) == "table" then
        A.pendingFlow = ctx.pendingFlow
        return A.pendingFlow
    end
    return nil
end

local function CurrentLargePanelKind()
    local p = A.largeTextPanel
    return type(p) == "table" and tostring(p.kind or "text") or nil
end

function A.Workflow.CloseLargePanel(reason)
    local kind = CurrentLargePanelKind()
    if not kind then return false, "No Assistant panel is open." end
    if type(A.CloseLargeTextPanel) == "function" then A.CloseLargeTextPanel() end
    return true, reason or ("Closed the Assistant " .. tostring(kind) .. " panel.")
end

function A.Workflow.CancelAnchorPicker()
    local ov = _G.MSUF_AnchorPicker
    if ov then
        ov._onPick = nil
        if ov.Hide then ov:Hide() end
        return true, "Cancelled the custom anchor picker."
    end
    return false, "No custom anchor picker is active."
end

function A.Workflow.StartUnitAnchorPicker(unit)
    unit = tostring(unit or "")
    if unit == "" then return false, "I need a unit for the custom anchor picker." end
    local ensure = _G.MSUF_EnsureAnchorPicker
    local overlay = type(ensure) == "function" and ensure() or nil
    if not overlay then return false, "Custom anchor picker is not available right now." end
    overlay._onPick = function(frameName)
        local function ApplyPickedAnchor()
            local conf = UnitDB(unit)
            conf.anchorFrameName = frameName
            conf.anchorToUnitframe = "GLOBAL"
            ApplyUnit(unit, "MSUF_ASSISTANT_PICK_CUSTOM_ANCHOR", { preview = true })
        end
        if M and type(M.CaptureHistory) == "function" and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then
            M.CaptureHistory("Pick custom anchor", "assistant:unit:anchorPick:" .. tostring(unit), ApplyPickedAnchor)
        else
            ApplyPickedAnchor()
        end
        A.ClearPendingFlow()
        if type(A.AddHistory) == "function" then
            A.AddHistory("assistant", "Done. Picked " .. tostring(frameName or "") .. " as " .. tostring(UNIT_LABELS[unit] or unit) .. " custom anchor.", "applied")
        end
        if type(A.RefreshUI) == "function" then A.RefreshUI() end
    end
    overlay:Show()
    A.StartPendingFlow("unitAnchorPicker", { source = unit, label = "Unit custom anchor picker" })
    return true, "Click a frame to pick a custom anchor for " .. tostring(UNIT_LABELS[unit] or unit) .. ", or type 'cancel custom anchor picker'."
end

function A.Workflow.StartGroupAnchorPicker(scope)
    scope = tostring(scope or "party")
    if scope ~= "party" and scope ~= "raid" and scope ~= "mythicraid" then scope = "party" end
    local ensure = _G.MSUF_EnsureAnchorPicker
    local overlay = type(ensure) == "function" and ensure() or nil
    if not overlay then return false, "Custom anchor picker is not available right now." end
    overlay._onPick = function(frameName)
        local function ApplyPickedAnchor()
            GroupDB(scope).anchorToFrame = frameName
            ApplyGroup(scope, "rebuild")
        end
        if M and type(M.CaptureHistory) == "function" and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then
            M.CaptureHistory("Pick group anchor", "assistant:group:anchorPick:" .. tostring(scope), ApplyPickedAnchor)
        else
            ApplyPickedAnchor()
        end
        A.ClearPendingFlow()
        if type(A.AddHistory) == "function" then
            A.AddHistory("assistant", "Done. Picked " .. tostring(frameName or "") .. " as " .. tostring(UNIT_LABELS[scope] or scope) .. " custom anchor.", "applied")
        end
        if type(A.RefreshUI) == "function" then A.RefreshUI() end
    end
    overlay:Show()
    A.StartPendingFlow("groupAnchorPicker", { source = scope, label = "Group custom anchor picker" })
    return true, "Click a frame to pick a custom anchor for " .. tostring(UNIT_LABELS[scope] or scope) .. ", or type 'cancel custom anchor picker'."
end

function A.Workflow.AnchorPickerStatus()
    local ov = _G.MSUF_AnchorPicker
    local shown = ov and ov.IsShown and ov:IsShown()
    local flow = A.Workflow.PendingFlow()
    if shown then
        return "Custom anchor picker is active. Click a frame to pick it or type 'cancel custom anchor picker'."
    end
    if type(flow) == "table" and (flow.kind == "unitAnchorPicker" or flow.kind == "groupAnchorPicker") then
        return "A custom anchor picker flow is pending, but the picker overlay is not visible. Type 'cancel custom anchor picker' to clear it."
    end
    return "Custom anchor picker is not active."
end

function A.Workflow.PushNavigationPage(page)
    page = tostring(page or "")
    if page == "" then return end
    A.Workflow.navStack = type(A.Workflow.navStack) == "table" and A.Workflow.navStack or {}
    local stack = A.Workflow.navStack
    if stack[#stack] ~= page then stack[#stack + 1] = page end
    while #stack > 20 do table.remove(stack, 1) end
end

function A.Workflow.GoBackPage()
    local stack = type(A.Workflow.navStack) == "table" and A.Workflow.navStack or nil
    local page = stack and table.remove(stack) or nil
    if type(page) ~= "string" or page == "" then
        return false, "Dashboard back navigation has no Assistant page history yet. Open a page through the Assistant first."
    end
    if M and type(M.Open) == "function" then
        if M.Open(page) ~= false then return true, "Opened previous page." end
    elseif M and type(M.SelectPage) == "function" then
        if M.SelectPage(page) ~= false then return true, "Opened previous page." end
    end
    return false, "Dashboard back navigation is not available right now."
end

function A.Workflow.WorkflowStatusText()
    local lines = {}
    local flow = A.Workflow.PendingFlow()
    lines[#lines + 1] = "Assistant workflow status:"
    lines[#lines + 1] = "- Pending confirmation: " .. (A.pendingConfirmation and "yes" or "no")
    lines[#lines + 1] = "- Pending choices: " .. ((type(A.pendingChoices) == "table" and #A.pendingChoices > 0) and tostring(#A.pendingChoices) or "no")
    lines[#lines + 1] = "- Pending flow: " .. (flow and tostring(flow.label or flow.kind) or "none")
    lines[#lines + 1] = "- Assistant panel: " .. (CurrentLargePanelKind() or "none")
    local guided = SafeContext() and SafeContext().guidedSetup
    lines[#lines + 1] = "- Guided setup: " .. (type(guided) == "table" and "active" or "inactive")
    if A.Workflow.EditMode and type(A.Workflow.EditMode.StatusText) == "function" then
        lines[#lines + 1] = ""
        lines[#lines + 1] = A.Workflow.EditMode.StatusText()
    end
    return table.concat(lines, "\n")
end

function A.Workflow.CancelActiveWorkflow()
    if A.pendingConfirmation then
        A.pendingConfirmation = nil
        local ctx = A.GetContext and A.GetContext()
        if ctx then ctx.pendingConfirmation = nil end
        return true, "Cancelled the pending confirmation."
    end
    if type(A.pendingChoices) == "table" and #A.pendingChoices > 0 then
        A.pendingChoices = nil
        local ctx = A.GetContext and A.GetContext()
        if ctx then ctx.pendingChoices = nil end
        return true, "Cancelled the pending choice."
    end
    local flow = A.Workflow.PendingFlow()
    if type(flow) == "table" then
        if flow.kind == "unitAnchorPicker" or flow.kind == "groupAnchorPicker" then A.Workflow.CancelAnchorPicker() end
        A.ClearPendingFlow()
        return true, "Cancelled " .. tostring(flow.label or flow.kind) .. "."
    end
    if CurrentLargePanelKind() then return A.Workflow.CloseLargePanel("Cancelled the open Assistant panel.") end
    local ctx = A.GetContext and A.GetContext()
    if ctx and type(ctx.guidedSetup) == "table" and A.Workflow.GuidedSetupStep then
        return true, A.Workflow.GuidedSetupStep("cancel")
    end
    return false, "There is no active Assistant workflow to cancel."
end

function A.HandlePendingFlow(text)
    local flow = A.Workflow.PendingFlow()
    if type(flow) ~= "table" then return nil end
    if IsCancel(text) or Normalize(text) == "cancel workflow" then
        local ok, message = A.Workflow.CancelActiveWorkflow()
        return { text = message, status = ok and "applied" or "failed" }
    end
    if flow.kind == "profileCopyDestination" then
        local dest = Trim(text)
        if dest == "" then return { text = "Type the destination profile name or 'cancel'.", status = "confirmation_needed" } end
        A.ClearPendingFlow()
        local action = Registry:GetAction("copy_profile_from_to")
        if not action then return { text = "Profile copy flow is not available right now.", status = "failed" } end
        return A.ExecutePlan({
            kind = "action",
            action = action,
            args = { source = flow.source, name = dest },
            confirmRequired = true,
            label = "Copy profile " .. tostring(flow.source) .. " to " .. tostring(dest),
            summary = "Copies one named profile to a new destination profile.",
        })
    end
    if flow.kind == "profileRenameDestination" then
        local dest = Trim(text)
        if dest == "" then return { text = "Type the new profile name or 'cancel'.", status = "confirmation_needed" } end
        A.ClearPendingFlow()
        local action = Registry:GetAction("rename_profile")
        if not action then return { text = "Profile rename is not available right now.", status = "failed" } end
        return A.ExecutePlan({
            kind = "action",
            action = action,
            args = { source = flow.source, name = dest },
            confirmRequired = true,
            label = "Rename profile " .. tostring(flow.source) .. " to " .. tostring(dest),
            summary = "Renames a profile through the shared profile helper if one exists.",
        })
    end
    return nil
end

Registry:RegisterAction({
    key = "assistant.workflow.status",
    label = "Show Workflow Status",
    type = "diagnostic",
    combatSafe = true,
    lifecycle = { workflow = "assistant", canStart = true, canCancel = true, canExitStop = true, canReportStatus = true },
    run = function()
        local text = A.Workflow.WorkflowStatusText()
        if type(A.ShowLargeTextPanel) == "function" then
            A.ShowLargeTextPanel({ kind = "text", title = "Assistant Workflows", help = "Current pending confirmations, flows, panels, and Edit Mode lifecycle status.", text = text, status = "No settings changed." })
        end
        return true, text
    end,
})

Registry:RegisterAction({
    key = "assistant.workflow.cancel",
    label = "Cancel Active Assistant Workflow",
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

Registry:RegisterAction({
    key = "copy_profile_from_to",
    label = "Copy Profile Source To Destination",
    type = "profile",
    combatSafe = false,
    confirmRequired = true,
    captureSnapshot = true,
    captureProfileSnapshot = true,
    lifecycle = { workflow = "profileCopy", canStart = true, canConfirmApply = true, canCancel = true, canReportStatus = true },
    run = function(args)
        local source = Trim(args and args.source or "")
        local dest = Trim(args and args.name or args and args.destination or "")
        if source == "" then return false, "I need a source profile name." end
        if dest == "" then return false, "I need a destination profile name." end
        local resolve = A.ResolveProfileName
        if type(resolve) == "function" then
            local resolved, how = resolve(source)
            if how == "multiple" then return false, "I found multiple matching source profiles. Please use the exact profile name." end
            if resolved then source = resolved end
        end
        if type(A.ProfileExists) == "function" and not A.ProfileExists(source) then return false, "Profile " .. tostring(source) .. " was not found." end
        if type(_G.MSUF_CopyProfile) ~= "function" then return false, "Profile copy is not available right now." end
        local copied = _G.MSUF_CopyProfile(source, dest)
        if copied and type(_G.MSUF_SwitchProfile) == "function" then _G.MSUF_SwitchProfile(dest) end
        if A and type(A.ApplyBroad) == "function" then A.ApplyBroad("MSUF_ASSISTANT_PROFILE_COPY_FROM_TO") end
        return copied and true or false, copied and ("Done. Copied profile " .. tostring(source) .. " to " .. tostring(dest) .. ".") or "Profile copy failed."
    end,
})

Registry:RegisterAction({
    key = "start_profile_copy_flow",
    label = "Start Profile Copy Flow",
    type = "profile",
    combatSafe = true,
    lifecycle = { workflow = "profileCopy", canStart = true, canConfirmApply = true, canCancel = true, canReportStatus = true },
    run = function(args)
        local source = Trim(args and args.source or "")
        if source == "" then source = type(A.ActiveProfileName) == "function" and A.ActiveProfileName() or tostring(_G.MSUF_ActiveProfile or "Default") end
        A.StartPendingFlow("profileCopyDestination", { source = source, label = "Profile copy" })
        return true, "Copy profile " .. tostring(source) .. " to which destination profile name? Type the new name or 'cancel'."
    end,
})

Registry:RegisterAction({
    key = "rename_profile",
    label = "Rename Profile",
    type = "profile",
    combatSafe = false,
    confirmRequired = true,
    captureSnapshot = true,
    captureProfileSnapshot = true,
    lifecycle = { workflow = "profileRename", canStart = true, canConfirmApply = true, canCancel = true, canReportStatus = true },
    run = function(args)
        local source = Trim(args and args.source or "")
        local dest = Trim(args and args.name or args and args.destination or "")
        if source == "" then source = type(A.ActiveProfileName) == "function" and A.ActiveProfileName() or tostring(_G.MSUF_ActiveProfile or "Default") end
        if dest == "" then return false, "I need the new profile name." end
        local requested = source
        local resolve = A.ResolveProfileName
        if type(resolve) == "function" then
            local resolved, how = resolve(source)
            if how == "multiple" then return false, "I found multiple matching source profiles. Please use the exact profile name." end
            if resolved then source = resolved end
        end
        if type(A.ProfileExists) == "function" then
            if not A.ProfileExists(source) then return false, "Profile " .. tostring(requested) .. " was not found." end
            if A.ProfileExists(dest) then return false, "Profile " .. tostring(dest) .. " already exists." end
        end
        if source == "Default" then return false, "The Default profile cannot be renamed. Copy it to a new profile instead." end
        local rename = _G.MSUF_RenameProfile or _G.MSUF_ProfileRename
        if type(rename) ~= "function" then
            return false, "Profile rename is not available because no shared public rename helper is exposed yet."
        end
        local ok = rename(source, dest)
        if ok == false then return false, "Profile rename failed." end
        if A and type(A.ApplyBroad) == "function" then A.ApplyBroad("MSUF_ASSISTANT_PROFILE_RENAME") end
        return true, "Done. Renamed profile " .. tostring(source) .. " to " .. tostring(dest) .. "."
    end,
})

Registry:RegisterAction({
    key = "start_profile_rename_flow",
    label = "Start Profile Rename Flow",
    type = "profile",
    combatSafe = true,
    lifecycle = { workflow = "profileRename", canStart = true, canConfirmApply = true, canCancel = true, canReportStatus = true },
    run = function(args)
        local source = Trim(args and args.source or "")
        if source == "" then source = type(A.ActiveProfileName) == "function" and A.ActiveProfileName() or tostring(_G.MSUF_ActiveProfile or "Default") end
        A.StartPendingFlow("profileRenameDestination", { source = source, label = "Profile rename" })
        return true, "Rename profile " .. tostring(source) .. " to what new name? Type the new name or 'cancel'."
    end,
})
