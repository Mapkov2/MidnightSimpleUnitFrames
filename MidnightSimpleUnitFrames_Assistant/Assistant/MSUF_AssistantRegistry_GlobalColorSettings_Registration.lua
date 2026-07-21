-- Assistant global color registration orchestrator.
-- Loaded after color domain registries; consumed by MSUF_AssistantRegistry_GlobalColorSettings.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

function A.GlobalRegistry.RegisterAssistantColorSettings(ctx)
    if type(ctx) ~= "table" then return false end

    local Registry = ctx.Registry
    local ColorCore = ctx.ColorCore or {}
    local ColorData = ctx.ColorData or {}
    local AuraPortraitColorSettings = ctx.AuraPortraitColorSettings
    local GeneralDB = ctx.GeneralDB
    local GameplayDB = ctx.GameplayDB
    local ApplyColors = ctx.ApplyColors
    local ApplyCastbarColors = ctx.ApplyCastbarColors
    local ApplyGameplayColors = ctx.ApplyGameplayColors
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

    if not (Registry and type(Registry.RegisterSetting) == "function") then return false end

    local ApiRGB = ColorCore.ApiRGB
    local ApiSetRGB = ColorCore.ApiSetRGB
    local Clamp01 = ColorCore.Clamp01
    local ColorAPI = ColorCore.ColorAPI
    local ColorComponents = ColorCore.ColorComponents
    local ColorFromName = ColorCore.ColorFromName
    local ColorSame = ColorCore.ColorSame
    local ColorSetting = ColorCore.ColorSetting
    local GeneralRGB = ColorCore.GeneralRGB
    local GeneralRGBAlias = ColorCore.GeneralRGBAlias
    local SetGeneralRGB = ColorCore.SetGeneralRGB
    local SetGeneralRGBAlias = ColorCore.SetGeneralRGBAlias
    local SetTableRGB = ColorCore.SetTableRGB
    local TableRGB = ColorCore.TableRGB

    local RegisterBaseColorSettings = A.GlobalRegistry and A.GlobalRegistry.RegisterBaseColorSettings
    if type(RegisterBaseColorSettings) == "function" then
        RegisterBaseColorSettings({
            Registry = Registry,
            ColorSetting = ColorSetting,
            ColorAPI = ColorAPI,
            GeneralDB = GeneralDB,
            GeneralRGB = GeneralRGB,
            SetGeneralRGB = SetGeneralRGB,
            ApiRGB = ApiRGB,
            ApiSetRGB = ApiSetRGB,
            RegisterGeneralBoolean = RegisterGeneralBoolean,
            RegisterGeneralNumberSetting = RegisterGeneralNumberSetting,
            ApplyColors = ApplyColors,
            COLOR_CLASS_TOKENS = ColorData.COLOR_CLASS_TOKENS or {},
            COLOR_CLASS_LABELS = ColorData.COLOR_CLASS_LABELS or {},
        })
    end

    local RegisterNPCColorSettings = A.GlobalRegistry and A.GlobalRegistry.RegisterNPCColorSettings
    if type(RegisterNPCColorSettings) == "function" then
        RegisterNPCColorSettings({
            Registry = Registry,
            ColorSetting = ColorSetting,
            ColorAPI = ColorAPI,
            GeneralDB = GeneralDB,
            GeneralRGB = GeneralRGB,
            SetGeneralRGB = SetGeneralRGB,
            TableRGB = TableRGB,
            ApiRGB = ApiRGB,
            ApiSetRGB = ApiSetRGB,
            RegisterGeneralBoolean = RegisterGeneralBoolean,
            ApplyColors = ApplyColors,
            COLOR_NPC_ROWS = ColorData.COLOR_NPC_ROWS or {},
            COLOR_NPC_TYPE_TOGGLE_ROWS = ColorData.COLOR_NPC_TYPE_TOGGLE_ROWS or {},
            COLOR_NPC_TYPE_ROWS = ColorData.COLOR_NPC_TYPE_ROWS or {},
        })
    end

    local RegisterBarColorSettings = A.GlobalRegistry and A.GlobalRegistry.RegisterBarColorSettings
    if type(RegisterBarColorSettings) == "function" then
        RegisterBarColorSettings({
            Registry = Registry,
            ColorSetting = ColorSetting,
            ApiRGB = ApiRGB,
            ApiSetRGB = ApiSetRGB,
            GeneralDB = GeneralDB,
            GeneralRGB = GeneralRGB,
            SetGeneralRGB = SetGeneralRGB,
            GeneralRGBAlias = GeneralRGBAlias,
            SetGeneralRGBAlias = SetGeneralRGBAlias,
            ColorComponents = ColorComponents,
            ColorSame = ColorSame,
            Clamp01 = Clamp01,
            RegisterGeneralBoolean = RegisterGeneralBoolean,
            RegisterGeneralEnum = RegisterGeneralEnum,
            ApplyColors = ApplyColors,
            ApplyBarOutline = ApplyBarOutline,
            GLOBAL_SCOPE_ORDER = GLOBAL_SCOPE_ORDER,
            NormalizeGlobalScope = NormalizeGlobalScope,
            GlobalScopeLabel = GlobalScopeLabel,
            GlobalScopeRead = GlobalScopeRead,
            GlobalScopeWrite = GlobalScopeWrite,
            GlobalScopeAliases = GlobalScopeAliases,
        })
    end

    local RegisterCastbarColorSettings = A.GlobalRegistry and A.GlobalRegistry.RegisterCastbarColorSettings
    if type(RegisterCastbarColorSettings) == "function" then
        RegisterCastbarColorSettings({
            ColorSetting = ColorSetting,
            GeneralRGB = GeneralRGB,
            SetGeneralRGB = SetGeneralRGB,
            GeneralDB = GeneralDB,
            TableRGB = TableRGB,
            SetTableRGB = SetTableRGB,
            ApiRGB = ApiRGB,
            ApiSetRGB = ApiSetRGB,
            RegisterGeneralBoolean = RegisterGeneralBoolean,
            RegisterGeneralEnum = RegisterGeneralEnum,
            ApplyCastbarColors = ApplyCastbarColors,
            COLOR_CASTBAR_ROWS = ColorData.COLOR_CASTBAR_ROWS or {},
        })
    end

    local RegisterHighlightColorSettings = A.GlobalRegistry and A.GlobalRegistry.RegisterHighlightColorSettings
    if type(RegisterHighlightColorSettings) == "function" then
        RegisterHighlightColorSettings({
            ColorSetting = ColorSetting,
            RegisterGeneralBoolean = RegisterGeneralBoolean,
            RegisterGeneralNumberSetting = RegisterGeneralNumberSetting,
            RegisterGeneralEnum = RegisterGeneralEnum,
            GeneralDB = GeneralDB,
            TableRGB = TableRGB,
            SetTableRGB = SetTableRGB,
            ColorFromName = ColorFromName,
            ApplyColors = ApplyColors,
        })
    end

    local RegisterGameplayColorSettings = A.GlobalRegistry and A.GlobalRegistry.RegisterGameplayColorSettings
    if type(RegisterGameplayColorSettings) == "function" then
        RegisterGameplayColorSettings({
            ColorSetting = ColorSetting,
            GameplayDB = GameplayDB,
            TableRGB = TableRGB,
            SetTableRGB = SetTableRGB,
            RegisterGameplayBoolean = RegisterGameplayBoolean,
            ApplyGameplayColors = ApplyGameplayColors,
        })
    end

    local RegisterAssistantPowerColorSettings = A.GlobalRegistry and A.GlobalRegistry.RegisterAssistantPowerColorSettings
    if type(RegisterAssistantPowerColorSettings) == "function" then RegisterAssistantPowerColorSettings(ctx) end

    if AuraPortraitColorSettings and type(AuraPortraitColorSettings.RegisterSettings) == "function" then
        AuraPortraitColorSettings.RegisterSettings()
    end
    return true
end
