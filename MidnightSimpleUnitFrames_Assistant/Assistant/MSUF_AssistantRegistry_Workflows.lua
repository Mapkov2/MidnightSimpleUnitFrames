-- Assistant Workflow registry: wires workflow state, navigation, status, and action helpers.
-- Workflow actions should be idempotent and serialize state through Assistant context.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry
local C = A.RegistryCore or {}
if not (Registry and type(Registry.RegisterAction) == "function") then return end

A.Workflow = A.Workflow or {}
A.Workflow.Lifecycle = A.Workflow.Lifecycle or {}

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

local function SafeContext()
    if A.GetContext then return A.GetContext() end
    A.context = type(A.context) == "table" and A.context or {}
    return A.context
end

local function NativeGuidedTourIsActive()
    local tour = MSUF.GuidedTour6 or _G.MSUF_GuidedTour6
    if type(tour) ~= "table" or type(tour.IsActive) ~= "function" then return false end
    local ok, active = pcall(tour.IsActive, tour)
    return ok and active == true
end

local function SetContextFlow(flow)
    local ctx = SafeContext()
    if ctx then ctx.pendingFlow = flow end
end

local function SerializablePendingFlow(kind, data)
    local flow = { kind = kind }
    for key, value in pairs(data or {}) do
        local valueType = type(value)
        if valueType == "string" or valueType == "number" or valueType == "boolean" then
            flow[key] = value
        end
    end
    return flow
end

function A.StartPendingFlow(kind, data)
    if type(kind) ~= "string" or kind == "" then return false end
    data = type(data) == "table" and data or {}
    data.kind = kind
    A.pendingFlow = data
    -- Pending setting conversations keep only scalar semantic data (setting
    -- keys, labels, expected value type, and movement nouns).  This survives
    -- a UI rebuild without retaining widgets, closures, or page objects.
    SetContextFlow(SerializablePendingFlow(kind, data))
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

local WORKFLOW_KIND_LABELS = {
    action = "action",
    export = "export",
    flow = "guided step",
    groupAnchorPicker = "group custom-anchor picker",
    import = "import",
    profileCopyDestination = "profile copy step",
    profileRenameDestination = "profile rename step",
    text = "text",
    unitAnchorPicker = "unit custom-anchor picker",
}

local function WorkflowKindLabel(kind)
    kind = tostring(kind or "")
    if WORKFLOW_KIND_LABELS[kind] then return WORKFLOW_KIND_LABELS[kind] end
    return "guided step"
end

local function WorkflowFlowLabel(flow)
    if type(flow) ~= "table" then return "none" end
    return WorkflowKindLabel(flow.kind)
end

function A.Workflow.FlowLabel(flow)
    return WorkflowFlowLabel(flow)
end

function A.Workflow.CloseLargePanel(reason)
    local kind = CurrentLargePanelKind()
    if not kind then return false, "There is no Assistant panel open right now." end
    if type(A.CloseLargeTextPanel) == "function" then A.CloseLargeTextPanel() end
    return true, reason or ("Closed the Assistant " .. WorkflowKindLabel(kind) .. " panel.")
end

local RegisterAnchorPickerHandlers = A.Workflow and A.Workflow.RegisterAnchorPickerHandlers
if type(RegisterAnchorPickerHandlers) == "function" then
    RegisterAnchorPickerHandlers({
        UnitDB = C.UnitDB,
        GroupDB = C.GroupDB,
        ApplyUnit = C.ApplyUnit,
        ApplyGroup = C.ApplyGroup,
        UNIT_LABELS = C.UNIT_LABELS or A.UnitLabels,
    })
end

local InstallNavigationHelpers = A.Workflow and A.Workflow.InstallNavigationHelpers
if type(InstallNavigationHelpers) ~= "function" then return end
InstallNavigationHelpers({ M = M })

function A.Workflow.WorkflowStatusText()
    local lines = {}
    local flow = A.Workflow.PendingFlow()
    lines[#lines + 1] = "Current Assistant step:"
    lines[#lines + 1] = "- Confirmation waiting: " .. (A.pendingConfirmation and "yes" or "no")
    lines[#lines + 1] = "- Choices waiting: " .. ((type(A.pendingChoices) == "table" and #A.pendingChoices > 0) and tostring(#A.pendingChoices) or "no")
    lines[#lines + 1] = "- Guided step: " .. WorkflowFlowLabel(flow)
    lines[#lines + 1] = "- Open Assistant panel: " .. (CurrentLargePanelKind() or "none")
    lines[#lines + 1] = "- Native guided tour: " .. (NativeGuidedTourIsActive() and "active" or "inactive")
    if M and type(M.GetPageHistoryState) == "function" then
        local state = M.GetPageHistoryState() or {}
        lines[#lines + 1] = "- Page history: " .. tostring(tonumber(state.backCount) or 0) .. " back, " .. tostring(tonumber(state.forwardCount) or 0) .. " forward"
    end
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
        return true, "Cancelled. I cleared the current confirmation."
    end
    if type(A.pendingChoices) == "table" and #A.pendingChoices > 0 then
        A.pendingChoices = nil
        local ctx = A.GetContext and A.GetContext()
        if ctx then ctx.pendingChoices = nil end
        return true, "Cancelled. I cleared the current choice."
    end
    local flow = A.Workflow.PendingFlow()
    if type(flow) == "table" then
        if flow.kind == "unitAnchorPicker" or flow.kind == "groupAnchorPicker" then A.Workflow.CancelAnchorPicker() end
        A.ClearPendingFlow()
        return true, "Cancelled " .. WorkflowFlowLabel(flow) .. "."
    end
    if CurrentLargePanelKind() then return A.Workflow.CloseLargePanel("Cancelled. I closed the open Assistant panel.") end
    return false, "There is no Assistant step waiting to cancel."
end

local RegisterPendingFlowHandlers = A.Workflow and A.Workflow.RegisterPendingFlowHandlers
if type(RegisterPendingFlowHandlers) == "function" then
    RegisterPendingFlowHandlers({
        Registry = Registry,
        Trim = Trim,
        Normalize = Normalize,
    })
end

local RegisterWorkflowActions = A.Workflow and A.Workflow.RegisterCoreActions
if type(RegisterWorkflowActions) == "function" then
    RegisterWorkflowActions({
        Registry = Registry,
        Trim = Trim,
    })
end
