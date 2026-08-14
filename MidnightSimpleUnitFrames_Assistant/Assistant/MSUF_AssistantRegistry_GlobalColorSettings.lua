local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- Global color, scale, and tooltip assistant setting domain.
-- Depends on MSUF_AssistantRegistry_Global.lua for shared registry helpers.
local ctx = A.GlobalRegistry and A.GlobalRegistry.ColorSettings
if type(ctx) ~= "table" then return end

local Registry = ctx.Registry
M = ctx.M or M
MSUF = ctx.MSUF or MSUF
local EnsureDB = ctx.EnsureDB
local GeneralDB = ctx.GeneralDB
local BarsDB = ctx.BarsDB
local GameplayDB = ctx.GameplayDB
local ClampNumber = ctx.ClampNumber
local CallGlobal = ctx.CallGlobal
local ApplyGeneral = ctx.ApplyGeneral
local ApplyVisuals = ctx.ApplyVisuals
local ApplyColors = ctx.ApplyColors
local ApplyCastbarColors = ctx.ApplyCastbarColors
local ApplyGameplayColors = ctx.ApplyGameplayColors
local ApplyClassPowerColors = ctx.ApplyClassPowerColors
local ApplyAuraColors = ctx.ApplyAuraColors
local ApplyPortraitColors = ctx.ApplyPortraitColors
local ApplyBarOutline = ctx.ApplyBarOutline
local RegisterGeneralBoolean = ctx.RegisterGeneralBoolean
local RegisterGeneralNumberSetting = ctx.RegisterGeneralNumberSetting
local RegisterGeneralEnum = ctx.RegisterGeneralEnum
local RegisterGameplayBoolean = ctx.RegisterGameplayBoolean
local GLOBAL_SCOPE_ORDER = ctx.GLOBAL_SCOPE_ORDER or {}
local NormalizeGlobalScope = ctx.NormalizeGlobalScope
local GlobalScopeLabel = ctx.GlobalScopeLabel
local GlobalScopeRead = ctx.GlobalScopeRead
local GlobalScopeWrite = ctx.GlobalScopeWrite
local GlobalScopeAliases = ctx.GlobalScopeAliases

if not (Registry and type(Registry.RegisterSetting) == "function" and type(Registry.RegisterAction) == "function") then return end
if type(GeneralDB) ~= "function" or type(EnsureDB) ~= "function" then return end
if type(ClampNumber) ~= "function" or type(RegisterGeneralBoolean) ~= "function" then return end

local ColorData = A.GlobalColorSettingsRegistryData
if type(ColorData) ~= "table" then return end
local AURA_COOLDOWN_TEXT_COLOR_ROWS = ColorData.AURA_COOLDOWN_TEXT_COLOR_ROWS or {}
local AURA_COOLDOWN_TEXT_THRESHOLD_ROWS = ColorData.AURA_COOLDOWN_TEXT_THRESHOLD_ROWS or {}

do
local BuildColorSettingsCoreContext = A.GlobalRegistry and A.GlobalRegistry.BuildColorSettingsCoreContext
local ColorCore = type(BuildColorSettingsCoreContext) == "function" and BuildColorSettingsCoreContext({
    Registry = Registry,
    GeneralDB = GeneralDB,
    ApplyColors = ApplyColors,
    MSUF = MSUF,
    ColorData = ColorData,
}) or nil
if type(ColorCore) ~= "table" then return end

local ColorSetting = ColorCore.ColorSetting
local GeneralRGB = ColorCore.GeneralRGB
local SetTableRGB = ColorCore.SetTableRGB
local TableRGB = ColorCore.TableRGB

local CreateAuraAndPortraitColorSettings = A.GlobalRegistry and A.GlobalRegistry.CreateAuraAndPortraitColorSettings
local AuraPortraitColorSettings = type(CreateAuraAndPortraitColorSettings) == "function" and CreateAuraAndPortraitColorSettings({
    ColorSetting = ColorSetting,
    GeneralRGB = GeneralRGB,
    GeneralDB = GeneralDB,
    EnsureDB = EnsureDB,
    TableRGB = TableRGB,
    SetTableRGB = SetTableRGB,
    RegisterGeneralBoolean = RegisterGeneralBoolean,
    RegisterGeneralNumberSetting = RegisterGeneralNumberSetting,
    ApplyAuraColors = ApplyAuraColors,
    ApplyPortraitColors = ApplyPortraitColors,
    AURA_COOLDOWN_TEXT_COLOR_ROWS = AURA_COOLDOWN_TEXT_COLOR_ROWS,
    AURA_COOLDOWN_TEXT_THRESHOLD_ROWS = AURA_COOLDOWN_TEXT_THRESHOLD_ROWS,
}) or nil

local RegisterWorkflowAndFontActions = A.GlobalRegistry and A.GlobalRegistry.RegisterWorkflowAndFontActions
if type(RegisterWorkflowAndFontActions) == "function" then
    RegisterWorkflowAndFontActions(ctx, ColorCore)
end

local RegisterAssistantColorSettings = A.GlobalRegistry and A.GlobalRegistry.RegisterAssistantColorSettings
if type(RegisterAssistantColorSettings) ~= "function" then return end

A.GlobalRegistry = A.GlobalRegistry or {}
local InstallColorResetActions = A.GlobalRegistry and A.GlobalRegistry.InstallColorResetActions
if type(InstallColorResetActions) == "function" then
    InstallColorResetActions(ctx, ColorCore, AuraPortraitColorSettings)
end
if RegisterAssistantColorSettings({
    Registry = Registry,
    ColorCore = ColorCore,
    ColorData = ColorData,
    AuraPortraitColorSettings = AuraPortraitColorSettings,
    GeneralDB = GeneralDB,
    BarsDB = BarsDB,
    GameplayDB = GameplayDB,
    ApplyColors = ApplyColors,
    ApplyCastbarColors = ApplyCastbarColors,
    ApplyGameplayColors = ApplyGameplayColors,
    ApplyClassPowerColors = ApplyClassPowerColors,
    ApplyBarOutline = ApplyBarOutline,
    RegisterGeneralBoolean = RegisterGeneralBoolean,
    RegisterGeneralNumberSetting = RegisterGeneralNumberSetting,
    RegisterGeneralEnum = RegisterGeneralEnum,
    RegisterGameplayBoolean = RegisterGameplayBoolean,
    GLOBAL_SCOPE_ORDER = GLOBAL_SCOPE_ORDER,
    NormalizeGlobalScope = NormalizeGlobalScope,
    GlobalScopeLabel = GlobalScopeLabel,
    GlobalScopeRead = GlobalScopeRead,
    GlobalScopeWrite = GlobalScopeWrite,
    GlobalScopeAliases = GlobalScopeAliases,
}) == false then return end
end
