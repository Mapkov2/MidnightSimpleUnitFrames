-- Assistant Global Bar registry shared context builder.
-- Loaded after data helpers and before global bar setting registrars.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalBarRegistry = A.GlobalBarRegistry or {}

function A.GlobalBarRegistry.BuildGlobalBarSettingsContext(ctx)
    ctx = type(ctx) == "table" and ctx or {}

    local C = ctx.RegistryCore or A.RegistryCore
    if type(C) ~= "table" then return nil end

    local Registry = C.Registry
    local GeneralDB = C.GeneralDB
    local RegisterScopedSetting = C.RegisterScopedSetting
    local RegisterGeneralString = C.RegisterGeneralString
    local RegisterGeneralMappedEnum = C.RegisterGeneralMappedEnum
    local RegisterBarsBoolean = C.RegisterBarsBoolean
    local RegisterBarsNumber = C.RegisterBarsNumber
    local RegisterBarsEnum = C.RegisterBarsEnum
    local RegisterBarsString = C.RegisterBarsString
    local RegisterGeneralBoolean = C.RegisterGeneralBoolean
    local RegisterGeneralNumberSetting = C.RegisterGeneralNumberSetting
    local RegisterGeneralEnum = C.RegisterGeneralEnum
    local RegisterScopedMappedEnum = C.RegisterScopedMappedEnum
    local GLOBAL_SCOPE_ORDER = C.GLOBAL_SCOPE_ORDER
    local GlobalScopeAliases = C.GlobalScopeAliases
    local GlobalScopeIsGroup = C.GlobalScopeIsGroup
    local GlobalScopeHasOverride = C.GlobalScopeHasOverride
    local GlobalScopeSetOverride = C.GlobalScopeSetOverride
    local GlobalScopeRead = C.GlobalScopeRead
    local GlobalScopeWrite = C.GlobalScopeWrite

    if not (Registry and type(Registry.RegisterSetting) == "function") then return nil end
    if type(GeneralDB) ~= "function" or type(RegisterScopedSetting) ~= "function" then return nil end
    if type(GLOBAL_SCOPE_ORDER) ~= "table" or type(GlobalScopeAliases) ~= "function" then return nil end
    if type(RegisterGeneralString) ~= "function" or type(RegisterGeneralMappedEnum) ~= "function" then return nil end
    if type(RegisterBarsBoolean) ~= "function" or type(RegisterBarsNumber) ~= "function" or type(RegisterBarsEnum) ~= "function" then return nil end
    if type(RegisterGeneralBoolean) ~= "function" or type(RegisterGeneralNumberSetting) ~= "function" then return nil end
    if type(RegisterGeneralEnum) ~= "function" or type(RegisterScopedMappedEnum) ~= "function" then return nil end
    if type(GlobalScopeIsGroup) ~= "function" or type(GlobalScopeHasOverride) ~= "function" then return nil end
    if type(GlobalScopeSetOverride) ~= "function" or type(GlobalScopeRead) ~= "function" or type(GlobalScopeWrite) ~= "function" then return nil end

    local GlobalBarData = A.GlobalBarRegistry and A.GlobalBarRegistry.Data
    if type(GlobalBarData) ~= "table" then return nil end

    local NormalizeTextureKeyForAssistant = GlobalBarData.NormalizeTextureKeyForAssistant
    if type(NormalizeTextureKeyForAssistant) ~= "function" then return nil end
    local NormalizeBorderKeyForAssistant = GlobalBarData.NormalizeBorderKeyForAssistant
    if type(NormalizeBorderKeyForAssistant) ~= "function" then return nil end

    local GRADIENT_DIRECTION_VALUES = GlobalBarData.GRADIENT_DIRECTION_VALUES
    local GRADIENT_DIRECTION_KEYS = GlobalBarData.GRADIENT_DIRECTION_KEYS
    local GRADIENT_DIRECTION_ALIASES = GlobalBarData.GRADIENT_DIRECTION_ALIASES
    local POWER_GRADIENT_DIRECTION_KEYS = GlobalBarData.POWER_GRADIENT_DIRECTION_KEYS
    local OUTLINE_STRATA_VALUES = GlobalBarData.OUTLINE_STRATA_VALUES
    local OUTLINE_STRATA_ALIASES = GlobalBarData.OUTLINE_STRATA_ALIASES
    local ON_OFF_STORAGE = GlobalBarData.ON_OFF_STORAGE
    local ON_OFF_VALUES = GlobalBarData.ON_OFF_VALUES
    local ON_OFF_ALIASES = GlobalBarData.ON_OFF_ALIASES
    local AGGRO_MODE_VALUES = GlobalBarData.AGGRO_MODE_VALUES
    local AGGRO_MODE_ALIASES = GlobalBarData.AGGRO_MODE_ALIASES
    local ABSORB_MODE_STORAGE = GlobalBarData.ABSORB_MODE_STORAGE
    local ABSORB_MODE_VALUES = GlobalBarData.ABSORB_MODE_VALUES
    local ABSORB_MODE_ALIASES = GlobalBarData.ABSORB_MODE_ALIASES
    local ABSORB_ANCHOR_STORAGE = GlobalBarData.ABSORB_ANCHOR_STORAGE
    local ABSORB_ANCHOR_VALUES = GlobalBarData.ABSORB_ANCHOR_VALUES
    local ABSORB_ANCHOR_ALIASES = GlobalBarData.ABSORB_ANCHOR_ALIASES
    local DISPEL_TRIGGER_VALUES = GlobalBarData.DISPEL_TRIGGER_VALUES
    local DISPEL_TRIGGER_ALIASES = GlobalBarData.DISPEL_TRIGGER_ALIASES
    local UNIT_DISPEL_TRIGGER_VALUES = GlobalBarData.UNIT_DISPEL_TRIGGER_VALUES
    local UNIT_DISPEL_TRIGGER_ALIASES = GlobalBarData.UNIT_DISPEL_TRIGGER_ALIASES
    local UNIT_DISPEL_STYLE_VALUES = GlobalBarData.UNIT_DISPEL_STYLE_VALUES
    local UNIT_DISPEL_STYLE_ALIASES = GlobalBarData.UNIT_DISPEL_STYLE_ALIASES
    local UNIT_DISPEL_SYMBOL_STYLE_VALUES = GlobalBarData.UNIT_DISPEL_SYMBOL_STYLE_VALUES
    local UNIT_DISPEL_SYMBOL_MODE_VALUES = GlobalBarData.UNIT_DISPEL_SYMBOL_MODE_VALUES
    local UNIT_DISPEL_SYMBOL_GROWTH_VALUES = GlobalBarData.UNIT_DISPEL_SYMBOL_GROWTH_VALUES
    local UNIT_DISPEL_SYMBOL_ANCHOR_VALUES = GlobalBarData.UNIT_DISPEL_SYMBOL_ANCHOR_VALUES
    local UNIT_DISPEL_SYMBOL_STRATA_VALUES = GlobalBarData.UNIT_DISPEL_SYMBOL_STRATA_VALUES

    if type(GRADIENT_DIRECTION_VALUES) ~= "table" or type(GRADIENT_DIRECTION_KEYS) ~= "table" or type(GRADIENT_DIRECTION_ALIASES) ~= "table" then return nil end
    if type(POWER_GRADIENT_DIRECTION_KEYS) ~= "table" then return nil end
    if type(OUTLINE_STRATA_VALUES) ~= "table" or type(OUTLINE_STRATA_ALIASES) ~= "table" then return nil end
    if type(ON_OFF_STORAGE) ~= "table" or type(ON_OFF_VALUES) ~= "table" or type(ON_OFF_ALIASES) ~= "table" then return nil end
    if type(AGGRO_MODE_VALUES) ~= "table" or type(AGGRO_MODE_ALIASES) ~= "table" then return nil end
    if type(ABSORB_MODE_STORAGE) ~= "table" or type(ABSORB_MODE_VALUES) ~= "table" or type(ABSORB_MODE_ALIASES) ~= "table" then return nil end
    if type(ABSORB_ANCHOR_STORAGE) ~= "table" or type(ABSORB_ANCHOR_VALUES) ~= "table" or type(ABSORB_ANCHOR_ALIASES) ~= "table" then return nil end
    if type(DISPEL_TRIGGER_VALUES) ~= "table" or type(DISPEL_TRIGGER_ALIASES) ~= "table" then return nil end
    if type(UNIT_DISPEL_TRIGGER_VALUES) ~= "table" or type(UNIT_DISPEL_TRIGGER_ALIASES) ~= "table" then return nil end
    if type(UNIT_DISPEL_STYLE_VALUES) ~= "table" or type(UNIT_DISPEL_STYLE_ALIASES) ~= "table" then return nil end

    return {
        Registry = Registry,
        GeneralDB = GeneralDB,
        CallGlobal = C.CallGlobal,
        ApplyBars = C.ApplyBars,
        ApplyBarGradients = C.ApplyBarGradients,
        ApplyBarOutline = C.ApplyBarOutline,
        ApplyRoundedBars = C.ApplyRoundedBars,
        ApplyAggroBorder = C.ApplyAggroBorder,
        ApplyDispelPurgeBorder = C.ApplyDispelPurgeBorder,
        ApplyBossTargetBorder = C.ApplyBossTargetBorder,
        ApplyHighlightBorders = C.ApplyHighlightBorders,
        ApplyAbsorbBars = C.ApplyAbsorbBars,
        RegisterGeneralBoolean = RegisterGeneralBoolean,
        RegisterGeneralNumberSetting = RegisterGeneralNumberSetting,
        RegisterGeneralEnum = RegisterGeneralEnum,
        RegisterGeneralString = RegisterGeneralString,
        RegisterGeneralMappedEnum = RegisterGeneralMappedEnum,
        RegisterBarsBoolean = RegisterBarsBoolean,
        RegisterBarsNumber = RegisterBarsNumber,
        RegisterBarsEnum = RegisterBarsEnum,
        RegisterBarsString = RegisterBarsString,
        GLOBAL_SCOPE_ORDER = GLOBAL_SCOPE_ORDER,
        GlobalScopeIsGroup = GlobalScopeIsGroup,
        GlobalScopeHasOverride = GlobalScopeHasOverride,
        GlobalScopeSetOverride = GlobalScopeSetOverride,
        GlobalScopeRead = GlobalScopeRead,
        GlobalScopeWrite = GlobalScopeWrite,
        GlobalScopeAliases = GlobalScopeAliases,
        GlobalScopeLabel = C.GlobalScopeLabel,
        NormalizeGlobalScope = C.NormalizeGlobalScope,
        RegisterScopedSetting = RegisterScopedSetting,
        RegisterScopedMappedEnum = RegisterScopedMappedEnum,
        GlobalBarData = GlobalBarData,
        NormalizeTextureKeyForAssistant = NormalizeTextureKeyForAssistant,
        NormalizeBorderKeyForAssistant = NormalizeBorderKeyForAssistant,
        GRADIENT_DIRECTION_VALUES = GRADIENT_DIRECTION_VALUES,
        GRADIENT_DIRECTION_KEYS = GRADIENT_DIRECTION_KEYS,
        GRADIENT_DIRECTION_ALIASES = GRADIENT_DIRECTION_ALIASES,
        POWER_GRADIENT_DIRECTION_KEYS = POWER_GRADIENT_DIRECTION_KEYS,
        OUTLINE_STRATA_VALUES = OUTLINE_STRATA_VALUES,
        OUTLINE_STRATA_ALIASES = OUTLINE_STRATA_ALIASES,
        ON_OFF_STORAGE = ON_OFF_STORAGE,
        ON_OFF_VALUES = ON_OFF_VALUES,
        ON_OFF_ALIASES = ON_OFF_ALIASES,
        AGGRO_MODE_VALUES = AGGRO_MODE_VALUES,
        AGGRO_MODE_ALIASES = AGGRO_MODE_ALIASES,
        ABSORB_MODE_STORAGE = ABSORB_MODE_STORAGE,
        ABSORB_MODE_VALUES = ABSORB_MODE_VALUES,
        ABSORB_MODE_ALIASES = ABSORB_MODE_ALIASES,
        ABSORB_ANCHOR_STORAGE = ABSORB_ANCHOR_STORAGE,
        ABSORB_ANCHOR_VALUES = ABSORB_ANCHOR_VALUES,
        ABSORB_ANCHOR_ALIASES = ABSORB_ANCHOR_ALIASES,
        DISPEL_TRIGGER_VALUES = DISPEL_TRIGGER_VALUES,
        DISPEL_TRIGGER_ALIASES = DISPEL_TRIGGER_ALIASES,
        UNIT_DISPEL_TRIGGER_VALUES = UNIT_DISPEL_TRIGGER_VALUES,
        UNIT_DISPEL_TRIGGER_ALIASES = UNIT_DISPEL_TRIGGER_ALIASES,
        UNIT_DISPEL_STYLE_VALUES = UNIT_DISPEL_STYLE_VALUES,
        UNIT_DISPEL_STYLE_ALIASES = UNIT_DISPEL_STYLE_ALIASES,
        UNIT_DISPEL_SYMBOL_STYLE_VALUES = UNIT_DISPEL_SYMBOL_STYLE_VALUES,
        UNIT_DISPEL_SYMBOL_MODE_VALUES = UNIT_DISPEL_SYMBOL_MODE_VALUES,
        UNIT_DISPEL_SYMBOL_GROWTH_VALUES = UNIT_DISPEL_SYMBOL_GROWTH_VALUES,
        UNIT_DISPEL_SYMBOL_ANCHOR_VALUES = UNIT_DISPEL_SYMBOL_ANCHOR_VALUES,
        UNIT_DISPEL_SYMBOL_STRATA_VALUES = UNIT_DISPEL_SYMBOL_STRATA_VALUES,
    }
end
