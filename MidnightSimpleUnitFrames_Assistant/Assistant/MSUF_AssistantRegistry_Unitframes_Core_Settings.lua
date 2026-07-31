-- Assistant UnitFrames shared core settings table builder.
-- Loaded before MSUF_AssistantRegistry_Unitframes_Core.lua; keeps registry subcontext assembly isolated.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.UnitframesRegistry = A.UnitframesRegistry or {}

function A.UnitframesRegistry.BuildCoreSettingsContext(ctx)
    if type(ctx) ~= "table" then return nil end

    local Registry = ctx.Registry
    local UNIT_LABELS = ctx.UNIT_LABELS
    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local UnitDB = ctx.UnitDB
    local GeneralDB = ctx.GeneralDB
    local BarsDB = ctx.BarsDB
    local ApplyUnit = ctx.ApplyUnit
    local CallGlobal = ctx.CallGlobal
    local UnitframeData = ctx.UnitframeData
    local UNIT_KEYS = ctx.UNIT_KEYS
    local MRef = ctx.M or M
    local MSUFRef = ctx.MSUF or MSUF
    local MakeAliases = ctx.MakeAliases
    local AllowedMap = ctx.AllowedMap
    local RegisterUnitBooleanSetting = ctx.RegisterUnitBooleanSetting
    local RegisterUnitNumberSetting = ctx.RegisterUnitNumberSetting
    local RegisterUnitEnum = ctx.RegisterUnitEnum
    local RegisterUnitString = ctx.RegisterUnitString
    local RegisterGeneralNestedBoolean = ctx.RegisterGeneralNestedBoolean
    local StatusCore = ctx.StatusCore
    local TextSpecialCore = ctx.TextSpecialCore

    if not (Registry and type(Registry.RegisterSetting) == "function") then return nil end
    if type(UnitframeData) ~= "table" or type(StatusCore) ~= "table" or type(TextSpecialCore) ~= "table" then return nil end
    if type(AddAliasesForUnit) ~= "function" or type(UnitDB) ~= "function" or type(GeneralDB) ~= "function" then return nil end
    if type(MakeAliases) ~= "function" or type(AllowedMap) ~= "function" then return nil end

    local TEXT_ANCHOR_VALUES = UnitframeData.TEXT_ANCHOR_VALUES
    local HP_MODE_VALUES = UnitframeData.HP_MODE_VALUES
    local POWER_MODE_VALUES = UnitframeData.POWER_MODE_VALUES
    local SEPARATOR_VALUES = UnitframeData.SEPARATOR_VALUES
    local RANGE_LAYER_VALUES = UnitframeData.RANGE_LAYER_VALUES
    local ANCHOR_TARGET_VALUES = UnitframeData.ANCHOR_TARGET_VALUES
    local ANCHOR_TARGET_TERMS = UnitframeData.ANCHOR_TARGET_TERMS or {}
    local ANCHOR_TARGET_ALIAS_BASE = UnitframeData.ANCHOR_TARGET_ALIAS_BASE or {}
    local ANCHOR_POINT_VALUES = UnitframeData.ANCHOR_POINT_VALUES
    local HP_MODE_ALIASES = UnitframeData.HP_MODE_ALIASES
    local POWER_MODE_ALIASES = UnitframeData.POWER_MODE_ALIASES
    local SEPARATOR_ALIASES = UnitframeData.SEPARATOR_ALIASES

    local unitStatusSettings = {
        AddAliasesForUnit = AddAliasesForUnit,
        MakeAliases = MakeAliases,
        RegisterUnitBooleanSetting = RegisterUnitBooleanSetting,
        RegisterUnitString = RegisterUnitString,
        RegisterUnitEnum = RegisterUnitEnum,
        RegisterUnitNumberSetting = RegisterUnitNumberSetting,
        RegisterGeneralNestedBoolean = RegisterGeneralNestedBoolean,
        StatusIconOpts = StatusCore.StatusIconOpts,
        UnitDB = UnitDB,
        GeneralDB = GeneralDB,
        AllowedMap = AllowedMap,
        ApplyStatusTextState = StatusCore.ApplyStatusTextState,
        STATUS_CONTROL_SPECS = StatusCore.STATUS_CONTROL_SPECS,
        STATUS_TEXT_STATE_SPECS = StatusCore.STATUS_TEXT_STATE_SPECS,
        STATUS_ICON_PACK_FALLBACK_VALUES = StatusCore.STATUS_ICON_PACK_FALLBACK_VALUES,
        STATUS_SYMBOL_ALIASES = StatusCore.STATUS_SYMBOL_ALIASES,
        STATUS_ANCHOR_VALUES = StatusCore.STATUS_ANCHOR_VALUES,
        STATUS_CORNER_ANCHOR_VALUES = StatusCore.STATUS_CORNER_ANCHOR_VALUES,
        STATUS_ANCHOR_ALIASES = StatusCore.STATUS_ANCHOR_ALIASES,
        RAID_GROUP_STYLE_VALUES = StatusCore.RAID_GROUP_STYLE_VALUES,
        RAID_GROUP_STYLE_ALIASES = StatusCore.RAID_GROUP_STYLE_ALIASES,
    }

    local unitTextSettings = {
        UnitDB = UnitDB,
        GeneralDB = GeneralDB,
        MakeAliases = MakeAliases,
        RegisterUnitBooleanSetting = RegisterUnitBooleanSetting,
        RegisterUnitEnum = RegisterUnitEnum,
        RegisterUnitTextNumber = TextSpecialCore.RegisterUnitTextNumber,
        TextValue = TextSpecialCore.TextValue,
        TEXT_ANCHOR_VALUES = TEXT_ANCHOR_VALUES,
        HP_MODE_VALUES = HP_MODE_VALUES,
        HP_MODE_ALIASES = HP_MODE_ALIASES,
        POWER_MODE_VALUES = POWER_MODE_VALUES,
        POWER_MODE_ALIASES = POWER_MODE_ALIASES,
        SEPARATOR_VALUES = SEPARATOR_VALUES,
        SEPARATOR_ALIASES = SEPARATOR_ALIASES,
    }

    local unitPowerSettings = {
        UnitDB = UnitDB,
        BarsDB = BarsDB,
        MakeAliases = MakeAliases,
        RegisterUnitBooleanSetting = RegisterUnitBooleanSetting,
        RegisterUnitNumberSetting = RegisterUnitNumberSetting,
        RegisterUnitEnum = RegisterUnitEnum,
        RegisterUnitString = RegisterUnitString,
        DETACHED_POWER_SHAPE_VALUES = UnitframeData.DETACHED_POWER_SHAPE_VALUES,
        DETACHED_POWER_SHAPE_ALIASES = UnitframeData.DETACHED_POWER_SHAPE_ALIASES,
    }

    local unitTransparencySettings = {
        MakeAliases = MakeAliases,
        RegisterUnitBooleanSetting = RegisterUnitBooleanSetting,
        RegisterUnitNumberSetting = RegisterUnitNumberSetting,
        RegisterUnitEnum = RegisterUnitEnum,
        RANGE_LAYER_VALUES = RANGE_LAYER_VALUES,
    }

    local unitTextureLayerSettings = {
        MakeAliases = MakeAliases,
        RegisterUnitBooleanSetting = RegisterUnitBooleanSetting,
        RegisterUnitNumberSetting = RegisterUnitNumberSetting,
        RegisterUnitEnum = RegisterUnitEnum,
        RegisterUnitString = RegisterUnitString,
    }

    local unitAnchoringSettings = {
        AddAliasesForUnit = AddAliasesForUnit,
        MakeAliases = MakeAliases,
        RegisterUnitEnum = RegisterUnitEnum,
        RegisterUnitString = RegisterUnitString,
        UnitDB = UnitDB,
        AllowedMap = AllowedMap,
        ANCHOR_TARGET_VALUES = ANCHOR_TARGET_VALUES,
        ANCHOR_TARGET_TERMS = ANCHOR_TARGET_TERMS,
        ANCHOR_TARGET_ALIAS_BASE = ANCHOR_TARGET_ALIAS_BASE,
        ANCHOR_POINT_VALUES = ANCHOR_POINT_VALUES,
        STATUS_ANCHOR_ALIASES = StatusCore.STATUS_ANCHOR_ALIASES,
    }

    return {
        UnitStatusSettings = unitStatusSettings,
        UnitTextSettings = unitTextSettings,
        UnitPowerSettings = unitPowerSettings,
        UnitTransparencySettings = unitTransparencySettings,
        UnitTextureLayerSettings = unitTextureLayerSettings,
        UnitAnchoringSettings = unitAnchoringSettings,
        UnitPortraitSettings = {
            UnitDB = UnitDB,
            MakeAliases = MakeAliases,
            RegisterUnitEnum = RegisterUnitEnum,
            RegisterUnitString = RegisterUnitString,
            RegisterUnitNumberSetting = RegisterUnitNumberSetting,
            RegisterUnitBooleanSetting = RegisterUnitBooleanSetting,
        },
        SpecialSettings = TextSpecialCore.SpecialSettings,
        Actions = {
            Registry = Registry,
            UnitDB = UnitDB,
            UNIT_LABELS = UNIT_LABELS,
            UNIT_KEYS = UNIT_KEYS,
            ApplyUnit = ApplyUnit,
            CallGlobal = CallGlobal,
            ResolveUnitStatusSpec = StatusCore.ResolveUnitStatusSpec,
            ApplyStatusRefresh = StatusCore.ApplyStatusRefresh,
            AllowedMap = AllowedMap,
            ANCHOR_TARGET_VALUES = ANCHOR_TARGET_VALUES,
            M = MRef,
            MSUF = MSUFRef,
        },
    }
end
