-- Assistant registry domain load manifest chunk 05.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local append = A.AppendRegistryDomainFiles
if type(append) == "function" then
    append({
        "MSUF_AssistantRegistry_Dashboard_TextSelectors_Group.lua",
        "MSUF_AssistantRegistry_Dashboard_TextSelectors.lua",
        "MSUF_AssistantRegistry_Dashboard_StyleTabs.lua",
        "MSUF_AssistantRegistry_Dashboard_StagingSelectors.lua",
        "MSUF_AssistantRegistry_Dashboard_StatusSelectors.lua",
        "MSUF_AssistantRegistry_Dashboard.lua",
        "MSUF_AssistantRegistry_Dashboard_Workflows.lua",
        "MSUF_AssistantRegistry_DashboardActions_Navigation.lua",
        "MSUF_AssistantRegistry_DashboardActions.lua",
        "MSUF_AssistantRegistry_DashboardActions_History.lua",
        "MSUF_AssistantRegistry_Profiles_Workflow_Spec.lua",
        "MSUF_AssistantRegistry_Profiles_Workflow_Character.lua",
        "MSUF_AssistantRegistry_Profiles_Workflow.lua",
        "MSUF_AssistantRegistry_Profiles_Workflow_Summary.lua",
        "MSUF_AssistantRegistry_Profiles_ImportActions.lua",
        "MSUF_AssistantRegistry_Profiles_ImportExport.lua",
        "MSUF_AssistantRegistry_Profiles_LifecycleActions.lua",
        "MSUF_AssistantRegistry_Profiles.lua",
        "MSUF_AssistantRegistry_EditMode_Shared.lua",
        "MSUF_AssistantRegistry_EditMode_Previews_Group.lua",
        "MSUF_AssistantRegistry_EditMode_Previews.lua",
        "MSUF_AssistantRegistry_EditMode_Controls_Position.lua",
        "MSUF_AssistantRegistry_EditMode_Controls.lua",
        "MSUF_AssistantRegistry_EditMode.lua",
        "MSUF_AssistantRegistry_EditMode_Actions.lua",
        "MSUF_AssistantRegistry_EditMode_Actions_Position.lua",
        "MSUF_AssistantRegistry_EditMode_Actions_Controls.lua",
        "MSUF_AssistantRegistry_EditMode_Actions_Status.lua",
        "MSUF_AssistantRegistry_Workflows_ProfileActions.lua",
        "MSUF_AssistantRegistry_Workflows_Actions.lua",
        "MSUF_AssistantRegistry_Workflows_AnchorPicker.lua",
        "MSUF_AssistantRegistry_Workflows_PendingFlows.lua",
        "MSUF_AssistantRegistry_Workflows_Navigation.lua",
        "MSUF_AssistantRegistry_Workflows.lua",
        "MSUF_AssistantRegistry_Diagnostics_Data.lua",
        "MSUF_AssistantRegistry_Diagnostics_Data_Guides.lua",
        "MSUF_AssistantRegistry_Diagnostics_Data_Guides_Extra.lua",
        "MSUF_AssistantRegistry_Diagnostics_Setup.lua",
        "MSUF_AssistantRegistry_Diagnostics_Support.lua",
        "MSUF_AssistantRegistry_Diagnostics_ScopeHelp.lua",
        "MSUF_AssistantRegistry_Diagnostics_Profiles.lua",
        "MSUF_AssistantRegistry_Diagnostics_Gameplay_Dashboard.lua",
        "MSUF_AssistantRegistry_Diagnostics_Gameplay_ClassPower.lua",
        "MSUF_AssistantRegistry_Diagnostics_Gameplay.lua",
        "MSUF_AssistantRegistry_Diagnostics_Frames.lua",
        "MSUF_AssistantRegistry_Diagnostics_Auras_Filters.lua",
        "MSUF_AssistantRegistry_Diagnostics_Auras.lua",
        "MSUF_AssistantRegistry_Diagnostics.lua",
        "MSUF_AssistantRegistry_DiagnosticsActions_Navigation.lua",
        "MSUF_AssistantRegistry_DiagnosticsActions_Support.lua",
        "MSUF_AssistantRegistry_DiagnosticsActions_Setup.lua",
        "MSUF_AssistantRegistry_DiagnosticsActions.lua",
    })
end
