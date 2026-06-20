-- Assistant registry domain load manifest chunk 02.
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
        "MSUF_AssistantRegistry_Castbars_Core_Provider.lua",
        "MSUF_AssistantRegistry_Castbars_Core.lua",
        "MSUF_AssistantRegistry_Castbars_Details_Data.lua",
        "MSUF_AssistantRegistry_Castbars_Details.lua",
        "MSUF_AssistantRegistry_Castbars_Units.lua",
        "MSUF_AssistantRegistry_Castbars_Appearance_Interrupts.lua",
        "MSUF_AssistantRegistry_Castbars_Appearance.lua",
        "MSUF_AssistantRegistry_Castbars_NumericBoolean.lua",
        "MSUF_AssistantRegistry_Castbars_Context.lua",
        "MSUF_AssistantRegistry_Castbars.lua",
        "MSUF_AssistantRegistry_Castbars_Actions.lua",
        "MSUF_AssistantRegistry_Auras_Data.lua",
        "MSUF_AssistantRegistry_Auras_Data_Layout.lua",
        "MSUF_AssistantRegistry_Auras_Data_Shared.lua",
        "MSUF_AssistantRegistry_Auras_Data_BlacklistPresets.lua",
        "MSUF_AssistantRegistry_Auras_Data_GroupCategories.lua",
        "MSUF_AssistantRegistry_Auras_Data_StyleFilters.lua",
        "MSUF_AssistantRegistry_Auras_Aliases.lua",
        "MSUF_AssistantRegistry_Auras_State_Shared.lua",
        "MSUF_AssistantRegistry_Auras_State.lua",
        "MSUF_AssistantRegistry_Auras_Registration_Lanes_Style.lua",
        "MSUF_AssistantRegistry_Auras_Registration_Lanes.lua",
        "MSUF_AssistantRegistry_Auras_Registration_UnitLanes.lua",
        "MSUF_AssistantRegistry_Auras_Registration_Scope.lua",
        "MSUF_AssistantRegistry_Auras_Registration.lua",
        "MSUF_AssistantRegistry_AurasUnitLanes_Geometry.lua",
        "MSUF_AssistantRegistry_AurasUnitLanes.lua",
        "MSUF_AssistantRegistry_Auras_Menu_Shared.lua",
        "MSUF_AssistantRegistry_Auras_Menu_Blacklist.lua",
        "MSUF_AssistantRegistry_Auras_Menu.lua",
        "MSUF_AssistantRegistry_Auras_Shared_Layout.lua",
        "MSUF_AssistantRegistry_Auras_Shared.lua",
        "MSUF_AssistantRegistry_Auras_Shared_Reminders.lua",
        "MSUF_AssistantRegistry_Auras_Filters.lua",
        "MSUF_AssistantRegistry_Auras_StyleFilters.lua",
        "MSUF_AssistantRegistry_Auras_SettingRegistries.lua",
        "MSUF_AssistantRegistry_Auras_Contexts.lua",
        "MSUF_AssistantRegistry_Auras_ContextInstall.lua",
        "MSUF_AssistantRegistry_Auras.lua",
        "MSUF_AssistantRegistry_AurasGroupRootSettings.lua",
        "MSUF_AssistantRegistry_AurasGroupCategories.lua",
        "MSUF_AssistantRegistry_AurasGroupLaneGeometry.lua",
        "MSUF_AssistantRegistry_AurasGroupLaneSettings.lua",
        "MSUF_AssistantRegistry_AurasGroupLaneCore.lua",
        "MSUF_AssistantRegistry_AurasGroupBlacklistCore.lua",
        "MSUF_AssistantRegistry_AurasGroupCategoryCore_Summary.lua",
        "MSUF_AssistantRegistry_AurasGroupCategoryCore_Resolve.lua",
        "MSUF_AssistantRegistry_AurasGroupCategoryCore.lua",
        "MSUF_AssistantRegistry_AurasGroupSettings.lua",
        "MSUF_AssistantRegistry_AurasActions_Blacklist_Summary.lua",
        "MSUF_AssistantRegistry_AurasActions_Blacklist.lua",
        "MSUF_AssistantRegistry_AurasActions_Parsers_Blacklist.lua",
        "MSUF_AssistantRegistry_AurasActions_Parsers.lua",
        "MSUF_AssistantRegistry_AurasActions_Presets.lua",
        "MSUF_AssistantRegistry_AurasActions.lua",
        "MSUF_AssistantRegistry_AurasGroupActions_Blacklist.lua",
        "MSUF_AssistantRegistry_AurasGroupActions_Parsers_DirectHelpers.lua",
        "MSUF_AssistantRegistry_AurasGroupActions_Parsers_Direct.lua",
        "MSUF_AssistantRegistry_AurasGroupActions_Parsers.lua",
        "MSUF_AssistantRegistry_AurasGroupActions.lua",
        "MSUF_AssistantRegistry_GroupFrames_Data.lua",
    })
end
