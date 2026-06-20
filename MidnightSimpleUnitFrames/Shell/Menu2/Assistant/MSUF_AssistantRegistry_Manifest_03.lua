-- Assistant registry domain load manifest chunk 03.
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
        "MSUF_AssistantRegistry_GroupFrames_Data_StatusIcons_Extras.lua",
        "MSUF_AssistantRegistry_GroupFrames_Data_StatusIcons.lua",
        "MSUF_AssistantRegistry_GroupFrames_Core_Status.lua",
        "MSUF_AssistantRegistry_GroupFrames_Core_Text_Aliases.lua",
        "MSUF_AssistantRegistry_GroupFrames_Core_Text_Names.lua",
        "MSUF_AssistantRegistry_GroupFrames_Core_Text_Colors.lua",
        "MSUF_AssistantRegistry_GroupFrames_Core_Text.lua",
        "MSUF_AssistantRegistry_GroupFrames_Core_Register.lua",
        "MSUF_AssistantRegistry_GroupFrames_Core.lua",
        "MSUF_AssistantRegistry_GroupFrames.lua",
        "MSUF_AssistantRegistry_GroupFramesStatus.lua",
        "MSUF_AssistantRegistry_GroupFramesText_Basics.lua",
        "MSUF_AssistantRegistry_GroupFramesText.lua",
        "MSUF_AssistantRegistry_GroupFramesVisual_Highlights.lua",
        "MSUF_AssistantRegistry_GroupFramesVisual.lua",
        "MSUF_AssistantRegistry_GroupFramesScaling.lua",
        "MSUF_AssistantRegistry_GroupFramesLayout.lua",
        "MSUF_AssistantRegistry_GroupFramesSettings_Basic.lua",
        "MSUF_AssistantRegistry_GroupFramesSettings_Bars_Power.lua",
        "MSUF_AssistantRegistry_GroupFramesSettings_Bars.lua",
        "MSUF_AssistantRegistry_GroupFramesSettings_FrameState.lua",
        "MSUF_AssistantRegistry_GroupFramesSettings_FrameOrdering.lua",
        "MSUF_AssistantRegistry_GroupFramesSettings_FrameAlphaAnchor.lua",
        "MSUF_AssistantRegistry_GroupFramesSettings.lua",
        "MSUF_AssistantRegistry_GroupFramesActions.lua",
        "MSUF_AssistantRegistry_GroupFramesSpellIndicators_Data.lua",
        "MSUF_AssistantRegistry_GroupFramesSpellIndicators_Slots.lua",
        "MSUF_AssistantRegistry_GroupFramesSpellIndicators_ActionHelpers.lua",
        "MSUF_AssistantRegistry_GroupFramesSpellIndicators_CornerActions.lua",
        "MSUF_AssistantRegistry_GroupFramesSpellIndicators_Actions.lua",
        "MSUF_AssistantRegistry_GroupFramesSpellIndicators_CornerSettings.lua",
        "MSUF_AssistantRegistry_GroupFramesSpellIndicators_Resolvers.lua",
        "MSUF_AssistantRegistry_GroupFramesSpellIndicators_State.lua",
        "MSUF_AssistantRegistry_GroupFramesSpellIndicators_Nested.lua",
        "MSUF_AssistantRegistry_GroupFramesSpellIndicators_Core.lua",
        "MSUF_AssistantRegistry_GroupFramesSpellIndicators.lua",
        "MSUF_AssistantRegistry_Boss.lua",
        "MSUF_AssistantRegistry_ClassPower_Data.lua",
        "MSUF_AssistantRegistry_ClassPower_Data_PlayerHP.lua",
        "MSUF_AssistantRegistry_ClassPower_Data_Preview.lua",
        "MSUF_AssistantRegistry_ClassPower_AltMana.lua",
        "MSUF_AssistantRegistry_ClassPower_PlayerHP_Text.lua",
        "MSUF_AssistantRegistry_ClassPower_PlayerHP.lua",
        "MSUF_AssistantRegistry_ClassPower_DetachedPower.lua",
        "MSUF_AssistantRegistry_ClassPower_Anchoring_Placement.lua",
        "MSUF_AssistantRegistry_ClassPower_Anchoring.lua",
        "MSUF_AssistantRegistry_ClassPower_Visibility.lua",
        "MSUF_AssistantRegistry_ClassPower_Textures.lua",
        "MSUF_AssistantRegistry_ClassPower_Display_Background.lua",
        "MSUF_AssistantRegistry_ClassPower_Display_Numbers.lua",
        "MSUF_AssistantRegistry_ClassPower_Display_Text.lua",
        "MSUF_AssistantRegistry_ClassPower_Display.lua",
        "MSUF_AssistantRegistry_ClassPower_Base_Geometry.lua",
        "MSUF_AssistantRegistry_ClassPower_Base.lua",
        "MSUF_AssistantRegistry_ClassPower.lua",
        "MSUF_AssistantRegistry_ClassPower_Preview.lua",
        "MSUF_AssistantRegistry_ClassPowerActions.lua",
    })
end
