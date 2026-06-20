-- Assistant registry domain load manifest chunk 01.
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
        "MSUF_AssistantRegistry_Core_Data.lua",
        "MSUF_AssistantRegistry_Core_DB.lua",
        "MSUF_AssistantRegistry_Core_Apply_Auras.lua",
        "MSUF_AssistantRegistry_Core_Apply_Bars.lua",
        "MSUF_AssistantRegistry_Core_Apply_Visuals.lua",
        "MSUF_AssistantRegistry_Core_Apply.lua",
        "MSUF_AssistantRegistry_Core_Apply_Domains.lua",
        "MSUF_AssistantRegistry_Core_Apply_Group.lua",
        "MSUF_AssistantRegistry_Core_GroupAuras.lua",
        "MSUF_AssistantRegistry_Core_UnitAuras_Advanced.lua",
        "MSUF_AssistantRegistry_Core_UnitAuras_Lanes.lua",
        "MSUF_AssistantRegistry_Core_UnitAuras.lua",
        "MSUF_AssistantRegistry_Core_Context.lua",
        "MSUF_AssistantRegistry_Core.lua",
        "MSUF_AssistantRegistry_Core_Registry.lua",
        "MSUF_AssistantRegistry_Core_Gameplay.lua",
        "MSUF_AssistantRegistry_Core_Settings_Unit.lua",
        "MSUF_AssistantRegistry_Core_Settings_Value.lua",
        "MSUF_AssistantRegistry_Core_Settings.lua",
        "MSUF_AssistantRegistry_Core_Settings_Bars.lua",
        "MSUF_AssistantRegistry_Core_Settings_Bars_String.lua",
        "MSUF_AssistantRegistry_Core_GlobalScope_Accessors.lua",
        "MSUF_AssistantRegistry_Core_GlobalScope.lua",
        "MSUF_AssistantRegistry_Unitframes_Base.lua",
        "MSUF_AssistantRegistry_Unitframes_Data.lua",
        "MSUF_AssistantRegistry_Unitframes_Data_Text.lua",
        "MSUF_AssistantRegistry_Unitframes_Data_StatusSymbols.lua",
        "MSUF_AssistantRegistry_Unitframes_Data_Anchoring.lua",
        "MSUF_AssistantRegistry_Unitframes_StatusData.lua",
        "MSUF_AssistantRegistry_Unitframes_Status.lua",
        "MSUF_AssistantRegistry_Unitframes_StatusText.lua",
        "MSUF_AssistantRegistry_Unitframes_Text.lua",
        "MSUF_AssistantRegistry_Unitframes_Portrait.lua",
        "MSUF_AssistantRegistry_Unitframes_Power_Detached.lua",
        "MSUF_AssistantRegistry_Unitframes_Power.lua",
        "MSUF_AssistantRegistry_Unitframes_Transparency.lua",
        "MSUF_AssistantRegistry_Unitframes_Anchoring.lua",
        "MSUF_AssistantRegistry_Unitframes_CoreLoop.lua",
        "MSUF_AssistantRegistry_Unitframes_Core_Status.lua",
        "MSUF_AssistantRegistry_Unitframes_Core_TextSpecial.lua",
        "MSUF_AssistantRegistry_Unitframes_Core_SettingsBase_General.lua",
        "MSUF_AssistantRegistry_Unitframes_Core_SettingsBase_Unit_String.lua",
        "MSUF_AssistantRegistry_Unitframes_Core_SettingsBase_Unit.lua",
        "MSUF_AssistantRegistry_Unitframes_Core_SettingsBase.lua",
        "MSUF_AssistantRegistry_Unitframes_Core_Settings.lua",
        "MSUF_AssistantRegistry_Unitframes_Core.lua",
        "MSUF_AssistantRegistry_Unitframes.lua",
        "MSUF_AssistantRegistry_Unitframes_Special.lua",
        "MSUF_AssistantRegistry_UnitframeActions_Helpers.lua",
        "MSUF_AssistantRegistry_UnitframeActions_PositionResets.lua",
        "MSUF_AssistantRegistry_UnitframeActions.lua",
        "MSUF_AssistantRegistry_Castbars_Core_Backend.lua",
        "MSUF_AssistantRegistry_Castbars_Core_Data.lua",
    })
end
