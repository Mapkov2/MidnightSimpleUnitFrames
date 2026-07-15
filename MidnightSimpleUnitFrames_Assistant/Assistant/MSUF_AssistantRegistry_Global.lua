-- Assistant Global registry: exposes cross-subsystem appearance and behavior controls.
-- Keep broad refreshes explicit so global setting writes do not hide runtime fanout.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.Workflow = A.Workflow or {}

local C = A.RegistryCore
if type(C) ~= "table" then return end

-- Global registry domain.
-- Owns assistant entries for shared colors, fonts, textures, bar behavior, and global visuals.
-- Apply callbacks fan out to the focused runtime refreshers to avoid full addon rebuilds.
local Registry = C.Registry
local EnsureDB = C.EnsureDB
local GeneralDB = C.GeneralDB
local BarsDB = C.BarsDB
local GameplayDB = C.GameplayDB
local ClampNumber = C.ClampNumber
local CallGlobal = C.CallGlobal
local ApplyGeneral = C.ApplyGeneral
local ApplyVisuals = C.ApplyVisuals
local ApplyColors = C.ApplyColors
local ApplyCastbarColors = C.ApplyCastbarColors
local ApplyGameplayColors = C.ApplyGameplayColors
local ApplyClassPowerColors = C.ApplyClassPowerColors
local ApplyAuraColors = C.ApplyAuraColors
local ApplyPortraitColors = C.ApplyPortraitColors
local ApplyFonts = C.ApplyFonts
local ApplyBars = C.ApplyBars
local ApplyBarGradients = C.ApplyBarGradients
local ApplyBarOutline = C.ApplyBarOutline
local ApplyRoundedBars = C.ApplyRoundedBars
local ApplyAggroBorder = C.ApplyAggroBorder
local ApplyDispelPurgeBorder = C.ApplyDispelPurgeBorder
local ApplyBossTargetBorder = C.ApplyBossTargetBorder
local ApplyHighlightBorders = C.ApplyHighlightBorders
local ApplyAbsorbBars = C.ApplyAbsorbBars
local ApplyCastbar = C.ApplyCastbar
local RegisterGeneralBoolean = C.RegisterGeneralBoolean
local RegisterGeneralNumberSetting = C.RegisterGeneralNumberSetting
local RegisterGeneralEnum = C.RegisterGeneralEnum
local RegisterGeneralString = C.RegisterGeneralString
local RegisterGeneralMappedEnum = C.RegisterGeneralMappedEnum
local RegisterBarsBoolean = C.RegisterBarsBoolean
local RegisterBarsNumber = C.RegisterBarsNumber
local RegisterGameplayBoolean = C.RegisterGameplayBoolean
local GLOBAL_SCOPE_ORDER = C.GLOBAL_SCOPE_ORDER
local NormalizeGlobalScope = C.NormalizeGlobalScope
local GlobalScopeLabel = C.GlobalScopeLabel
local GlobalScopeIsGroup = C.GlobalScopeIsGroup
local GlobalScopeHasOverride = C.GlobalScopeHasOverride
local GlobalScopeSetOverride = C.GlobalScopeSetOverride
local GlobalScopeRead = C.GlobalScopeRead
local GlobalScopeWrite = C.GlobalScopeWrite
local GlobalScopeAliases = C.GlobalScopeAliases
local RegisterScopedSetting = C.RegisterScopedSetting
local RegisterScopedMappedEnum = C.RegisterScopedMappedEnum

local RegisterGlobalBaseSettings = A.GlobalRegistry and A.GlobalRegistry.RegisterBaseSettings
if type(RegisterGlobalBaseSettings) == "function" then
    RegisterGlobalBaseSettings({
        Registry = Registry,
        M = M,
        GeneralDB = GeneralDB,
        ApplyGeneral = ApplyGeneral,
        ApplyVisuals = ApplyVisuals,
        ApplyColors = ApplyColors,
        ApplyFonts = ApplyFonts,
        RegisterGeneralBoolean = RegisterGeneralBoolean,
        RegisterGeneralNumberSetting = RegisterGeneralNumberSetting,
        RegisterGeneralEnum = RegisterGeneralEnum,
        RegisterGeneralString = RegisterGeneralString,
    })
end

local RegisterGlobalCastbarSettings = A.GlobalRegistry and A.GlobalRegistry.RegisterCastbarSettings
if type(RegisterGlobalCastbarSettings) == "function" then
    RegisterGlobalCastbarSettings({
        RegisterGeneralBoolean = RegisterGeneralBoolean,
        RegisterGeneralNumberSetting = RegisterGeneralNumberSetting,
        RegisterGeneralEnum = RegisterGeneralEnum,
        ApplyCastbar = ApplyCastbar,
    })
end


A.GlobalRegistry = A.GlobalRegistry or {}
A.GlobalRegistry.TooltipModuleSettings = {
    Registry = Registry,
    GeneralDB = GeneralDB,
    CallGlobal = CallGlobal,
}

A.GlobalRegistry = A.GlobalRegistry or {}
A.GlobalRegistry.Actions = {
    Registry = Registry,
    M = M,
    NormalizeGlobalScope = NormalizeGlobalScope,
    GlobalScopeSetOverride = GlobalScopeSetOverride,
    GlobalScopeLabel = GlobalScopeLabel,
    GLOBAL_SCOPE_ORDER = GLOBAL_SCOPE_ORDER,
    ApplyBars = ApplyBars,
    ApplyFonts = ApplyFonts,
    ApplyAbsorbBars = ApplyAbsorbBars,
}

A.GlobalRegistry = A.GlobalRegistry or {}
A.GlobalRegistry.ColorSettings = {
    Registry = Registry,
    M = M,
    MSUF = MSUF,
    EnsureDB = EnsureDB,
    GeneralDB = GeneralDB,
    BarsDB = BarsDB,
    GameplayDB = GameplayDB,
    ClampNumber = ClampNumber,
    CallGlobal = CallGlobal,
    ApplyGeneral = ApplyGeneral,
    ApplyVisuals = ApplyVisuals,
    ApplyColors = ApplyColors,
    ApplyCastbarColors = ApplyCastbarColors,
    ApplyGameplayColors = ApplyGameplayColors,
    ApplyClassPowerColors = ApplyClassPowerColors,
    ApplyAuraColors = ApplyAuraColors,
    ApplyPortraitColors = ApplyPortraitColors,
    ApplyBarGradients = ApplyBarGradients,
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
}
