-- Assistant registry domain load manifest chunk 04.
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
        "MSUF_AssistantRegistry_Gameplay_Combat.lua",
        "MSUF_AssistantRegistry_Gameplay_Crosshair.lua",
        "MSUF_AssistantRegistry_Gameplay_Totems.lua",
        "MSUF_AssistantRegistry_Gameplay.lua",
        "MSUF_AssistantRegistry_Global_CastbarSettings.lua",
        "MSUF_AssistantRegistry_Global_BaseSettings_Appearance.lua",
        "MSUF_AssistantRegistry_Global_BaseSettings.lua",
        "MSUF_AssistantRegistry_Global.lua",
        "MSUF_AssistantRegistry_Global_TooltipModules.lua",
        "MSUF_AssistantRegistry_GlobalFontSettings_Data.lua",
        "MSUF_AssistantRegistry_GlobalFontSettings_Core.lua",
        "MSUF_AssistantRegistry_GlobalFontSettings_Scoped_UnitText.lua",
        "MSUF_AssistantRegistry_GlobalFontSettings_Scoped.lua",
        "MSUF_AssistantRegistry_GlobalFontSettings.lua",
        "MSUF_AssistantRegistry_GlobalBarSettings_Data.lua",
        "MSUF_AssistantRegistry_GlobalBarSettings_Context.lua",
        "MSUF_AssistantRegistry_GlobalBarSettings_TextureGradient.lua",
        "MSUF_AssistantRegistry_GlobalBarSettings_Absorb.lua",
        "MSUF_AssistantRegistry_GlobalBarSettings_Base.lua",
        "MSUF_AssistantRegistry_GlobalBarSettings_Scoped.lua",
        "MSUF_AssistantRegistry_GlobalBarSettings_Scoped_Overlays_Unit.lua",
        "MSUF_AssistantRegistry_GlobalBarSettings_Scoped_Overlays.lua",
        "MSUF_AssistantRegistry_GlobalBarSettings.lua",
        "MSUF_AssistantRegistry_GlobalColorSettings_Data.lua",
        "MSUF_AssistantRegistry_GlobalColorSettings_ColorValues.lua",
        "MSUF_AssistantRegistry_GlobalColorSettings_ClassPowerCore.lua",
        "MSUF_AssistantRegistry_GlobalColorSettings_PowerCore.lua",
        "MSUF_AssistantRegistry_GlobalColorSettings_Core_DB.lua",
        "MSUF_AssistantRegistry_GlobalColorSettings_Core.lua",
        "MSUF_AssistantRegistry_GlobalColorSettings_Workflow_Tooltips.lua",
        "MSUF_AssistantRegistry_GlobalColorSettings_Workflow.lua",
        "MSUF_AssistantRegistry_GlobalColorSettings_Scale.lua",
        "MSUF_AssistantRegistry_GlobalColorSettings_FontActions.lua",
        "MSUF_AssistantRegistry_GlobalColorSettings_WorkflowActions.lua",
        "MSUF_AssistantRegistry_GlobalColorSettings_Base.lua",
        "MSUF_AssistantRegistry_GlobalColorSettings_Bars.lua",
        "MSUF_AssistantRegistry_GlobalColorSettings_Auras.lua",
        "MSUF_AssistantRegistry_GlobalColorSettings_Castbars.lua",
        "MSUF_AssistantRegistry_GlobalColorSettings_NPC.lua",
        "MSUF_AssistantRegistry_GlobalColorSettings_ClassPower.lua",
        "MSUF_AssistantRegistry_GlobalColorSettings_Gameplay.lua",
        "MSUF_AssistantRegistry_GlobalColorSettings_Power.lua",
        "MSUF_AssistantRegistry_GlobalColorSettings_Highlight.lua",
        "MSUF_AssistantRegistry_GlobalColorSettings_Registration_Power.lua",
        "MSUF_AssistantRegistry_GlobalColorSettings_Registration.lua",
        "MSUF_AssistantRegistry_GlobalColorSettings_ResetContext.lua",
        "MSUF_AssistantRegistry_GlobalColorSettings.lua",
        "MSUF_AssistantRegistry_GlobalActions.lua",
        "MSUF_AssistantRegistry_GlobalColorResetActions.lua",
        "MSUF_AssistantRegistry_GlobalColorResetActions_Extras.lua",
        "MSUF_AssistantRegistry_Dashboard_Panels.lua",
        "MSUF_AssistantRegistry_Dashboard_Panels_Nav.lua",
        "MSUF_AssistantRegistry_Dashboard_Copy_Data.lua",
        "MSUF_AssistantRegistry_Dashboard_Copy_Group.lua",
        "MSUF_AssistantRegistry_Dashboard_Copy.lua",
    })
end
