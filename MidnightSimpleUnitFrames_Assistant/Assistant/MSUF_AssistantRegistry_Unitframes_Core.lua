-- Assistant UnitFrames shared registry helpers.
-- Builds the helper/context tables consumed by the split UnitFrames registry modules.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.UnitframesRegistry = A.UnitframesRegistry or {}

function A.UnitframesRegistry.BuildCoreContext(ctx)
    if type(ctx) ~= "table" then return nil end

    local Registry = ctx.Registry
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local UnitDB = ctx.UnitDB
    local GeneralDB = ctx.GeneralDB
    local BarsDB = ctx.BarsDB
    local ApplyUnit = ctx.ApplyUnit
    local CallGlobal = ctx.CallGlobal
    local ClampNumber = ctx.ClampNumber
    local UnitframeData = ctx.UnitframeData
    local UNIT_KEYS = ctx.UNIT_KEYS or { "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }

    if not (Registry and type(Registry.RegisterSetting) == "function") then return nil end
    if type(AddAliasesForUnit) ~= "function" or type(UnitDB) ~= "function" then return nil end
    if type(GeneralDB) ~= "function" or type(ApplyUnit) ~= "function" then return nil end
    if type(CallGlobal) ~= "function" or type(ClampNumber) ~= "function" then return nil end
    if type(UnitframeData) ~= "table" then return nil end

    local TEXT_ANCHOR_VALUES = UnitframeData.TEXT_ANCHOR_VALUES
    local HP_MODE_VALUES = UnitframeData.HP_MODE_VALUES
    local POWER_MODE_VALUES = UnitframeData.POWER_MODE_VALUES
    local SEPARATOR_VALUES = UnitframeData.SEPARATOR_VALUES
    local RANGE_LAYER_VALUES = UnitframeData.RANGE_LAYER_VALUES
    local ANCHOR_TARGET_VALUES = UnitframeData.ANCHOR_TARGET_VALUES
    local ANCHOR_TARGET_TERMS = UnitframeData.ANCHOR_TARGET_TERMS or {}
    local ANCHOR_TARGET_ALIAS_BASE = UnitframeData.ANCHOR_TARGET_ALIAS_BASE or {}
    local ANCHOR_POINT_VALUES = UnitframeData.ANCHOR_POINT_VALUES
    local BOSS_LAYOUT_VALUES = UnitframeData.BOSS_LAYOUT_VALUES
    local TOT_INLINE_COLOR_VALUES = UnitframeData.TOT_INLINE_COLOR_VALUES
    local TOT_INLINE_SEPARATOR_CUSTOM = UnitframeData.TOT_INLINE_SEPARATOR_CUSTOM

    local HP_MODE_ALIASES = UnitframeData.HP_MODE_ALIASES
    local POWER_MODE_ALIASES = UnitframeData.POWER_MODE_ALIASES
    local SEPARATOR_ALIASES = UnitframeData.SEPARATOR_ALIASES
    local BOSS_LAYOUT_ALIASES = UnitframeData.BOSS_LAYOUT_ALIASES
    local TOT_INLINE_COLOR_ALIASES = UnitframeData.TOT_INLINE_COLOR_ALIASES
    local LOAD_CONDITION_SPECS = UnitframeData.LOAD_CONDITION_SPECS
    local BuildStatusCoreContext = A.UnitframesRegistry and A.UnitframesRegistry.BuildStatusCoreContext
    local StatusCore = type(BuildStatusCoreContext) == "function" and BuildStatusCoreContext({
        UnitframeData = UnitframeData,
        ApplyUnit = ApplyUnit,
        CallGlobal = CallGlobal,
    }) or nil
    if type(StatusCore) ~= "table" then return nil end

    local BuildSettingBaseContext = A.UnitframesRegistry and A.UnitframesRegistry.BuildSettingBaseContext
    local SettingBase = type(BuildSettingBaseContext) == "function" and BuildSettingBaseContext({
        Registry = Registry,
        UNIT_LABELS = UNIT_LABELS,
        AddAliasesForUnit = AddAliasesForUnit,
        UnitDB = UnitDB,
        GeneralDB = GeneralDB,
        ApplyUnit = ApplyUnit,
        CallGlobal = CallGlobal,
        ClampNumber = ClampNumber,
    }) or nil
    if type(SettingBase) ~= "table" then return nil end

    local MakeAliases = SettingBase.MakeAliases
    local AllowedMap = SettingBase.AllowedMap
    local RegisterUnitBooleanSetting = SettingBase.RegisterUnitBooleanSetting
    local RegisterUnitNumberSetting = SettingBase.RegisterUnitNumberSetting
    local RegisterUnitEnum = SettingBase.RegisterUnitEnum
    local RegisterUnitString = SettingBase.RegisterUnitString
    local RegisterGeneralNestedBoolean = SettingBase.RegisterGeneralNestedBoolean

    local BuildTextSpecialCoreContext = A.UnitframesRegistry and A.UnitframesRegistry.BuildTextSpecialCoreContext
    local TextSpecialCore = type(BuildTextSpecialCoreContext) == "function" and BuildTextSpecialCoreContext({
        Registry = Registry,
        UnitDB = UnitDB,
        GeneralDB = GeneralDB,
        ApplyUnit = ApplyUnit,
        CallGlobal = CallGlobal,
        MakeAliases = MakeAliases,
        RegisterUnitNumberSetting = RegisterUnitNumberSetting,
        RegisterUnitEnum = RegisterUnitEnum,
        M = M,
        MSUF = MSUF,
        SEPARATOR_ALIASES = SEPARATOR_ALIASES,
        TOT_INLINE_COLOR_VALUES = TOT_INLINE_COLOR_VALUES,
        TOT_INLINE_COLOR_ALIASES = TOT_INLINE_COLOR_ALIASES,
        TOT_INLINE_SEPARATOR_CUSTOM = TOT_INLINE_SEPARATOR_CUSTOM,
        BOSS_LAYOUT_VALUES = BOSS_LAYOUT_VALUES,
        BOSS_LAYOUT_ALIASES = BOSS_LAYOUT_ALIASES,
    }) or nil
    if type(TextSpecialCore) ~= "table" then return nil end

    local BuildCoreSettingsContext = A.UnitframesRegistry and A.UnitframesRegistry.BuildCoreSettingsContext
    local CoreSettings = type(BuildCoreSettingsContext) == "function" and BuildCoreSettingsContext({
        Registry = Registry,
        UNIT_LABELS = UNIT_LABELS,
        AddAliasesForUnit = AddAliasesForUnit,
        UnitDB = UnitDB,
        GeneralDB = GeneralDB,
        BarsDB = BarsDB,
        ApplyUnit = ApplyUnit,
        CallGlobal = CallGlobal,
        UnitframeData = UnitframeData,
        UNIT_KEYS = UNIT_KEYS,
        M = M,
        MSUF = MSUF,
        MakeAliases = MakeAliases,
        AllowedMap = AllowedMap,
        RegisterUnitBooleanSetting = RegisterUnitBooleanSetting,
        RegisterUnitNumberSetting = RegisterUnitNumberSetting,
        RegisterUnitEnum = RegisterUnitEnum,
        RegisterUnitString = RegisterUnitString,
        RegisterGeneralNestedBoolean = RegisterGeneralNestedBoolean,
        StatusCore = StatusCore,
        TextSpecialCore = TextSpecialCore,
    }) or nil
    if type(CoreSettings) ~= "table" then return nil end

    return {
        MakeAliases = MakeAliases,
        RegisterUnitBooleanSetting = RegisterUnitBooleanSetting,
        RegisterUnitNumberSetting = RegisterUnitNumberSetting,
        RegisterUnitEnum = RegisterUnitEnum,
        RegisterUnitString = RegisterUnitString,
        RegisterUnitTextNumber = TextSpecialCore.RegisterUnitTextNumber,
        UnitStatusSettings = CoreSettings.UnitStatusSettings,
        UnitTextSettings = CoreSettings.UnitTextSettings,
        UnitPowerSettings = CoreSettings.UnitPowerSettings,
        UnitTransparencySettings = CoreSettings.UnitTransparencySettings,
        UnitTextureLayerSettings = CoreSettings.UnitTextureLayerSettings,
        UnitAnchoringSettings = CoreSettings.UnitAnchoringSettings,
        UnitPortraitSettings = CoreSettings.UnitPortraitSettings,
        SpecialSettings = CoreSettings.SpecialSettings,
        Actions = CoreSettings.Actions,
        ResolveUnitStatusSpec = StatusCore.ResolveUnitStatusSpec,
        ApplyLoadCondition = TextSpecialCore.ApplyLoadCondition,
        UNIT_KEYS = UNIT_KEYS,
        LOAD_CONDITION_SPECS = LOAD_CONDITION_SPECS,
    }
end
