-- Assistant Castbars registry: maps natural-language controls to castbar settings/actions.
-- Registry writes must stay compatible with live castbar runtime and preview refresh helpers.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry or { settings = {}, settingsByKey = {}, actions = {}, actionsByKey = {}, todos = {} }
A.Registry = Registry
A.Workflow = A.Workflow or {}

local C = A.RegistryCore
if type(C) ~= "table" then return end

-- Castbars registry domain.
-- Describes backend, size, text/icon, interrupt, and visual controls for assistant matching.
-- Actual castbar frame mutation still belongs to the castbar runtime/bridge modules.
local Registry = C.Registry
local UNIT_LABELS = C.UNIT_LABELS
local AddAliasesForUnit = C.AddAliasesForUnit
local GeneralDB = C.GeneralDB
local ClampNumber = C.ClampNumber
local CallGlobal = C.CallGlobal
local ApplyCastbar = C.ApplyCastbar
local RegisterGeneralBoolean = C.RegisterGeneralBoolean
local RegisterGeneralNumberSetting = C.RegisterGeneralNumberSetting
local RegisterGeneralEnum = C.RegisterGeneralEnum
local RegisterGeneralString = C.RegisterGeneralString

local BuildCastbarCoreContext = A.CastbarsRegistry and A.CastbarsRegistry.BuildCoreContext
local CastbarCore = type(BuildCastbarCoreContext) == "function" and BuildCastbarCoreContext({
    Registry = Registry,
    RegistryCore = C,
    UNIT_LABELS = UNIT_LABELS,
    AddAliasesForUnit = AddAliasesForUnit,
    GeneralDB = GeneralDB,
    ClampNumber = ClampNumber,
    CallGlobal = CallGlobal,
    ApplyCastbar = ApplyCastbar,
    RegisterGeneralEnum = RegisterGeneralEnum,
}) or nil
if type(CastbarCore) ~= "table" then return end

local CASTBAR_KEYS = CastbarCore.CASTBAR_KEYS
local CASTBAR_DETAIL_FIELDS = CastbarCore.CASTBAR_DETAIL_FIELDS
local RegisterUnitCastbarBoolean = CastbarCore.RegisterUnitCastbarBoolean
local RegisterGeneralNumber = CastbarCore.RegisterGeneralNumber
local RegisterGeneralEnumSetting = CastbarCore.RegisterGeneralEnumSetting
local RegisterCastbarUnitGeneralBoolean = CastbarCore.RegisterCastbarUnitGeneralBoolean
local RegisterBossCastbarDetachSetting = CastbarCore.RegisterBossCastbarDetachSetting
local RegisterPlayerCastbarProvider = CastbarCore.RegisterPlayerCastbarProvider

local RegisterCastbarUnitSettings = A.CastbarsRegistry and A.CastbarsRegistry.RegisterUnitSettings
if type(RegisterCastbarUnitSettings) == "function" then
    RegisterCastbarUnitSettings({
        CASTBAR_KEYS = CASTBAR_KEYS,
        CASTBAR_DETAIL_FIELDS = CASTBAR_DETAIL_FIELDS,
        AddAliasesForUnit = AddAliasesForUnit,
        RegisterUnitCastbarBoolean = RegisterUnitCastbarBoolean,
        RegisterGeneralNumber = RegisterGeneralNumber,
        RegisterGeneralEnumSetting = RegisterGeneralEnumSetting,
        RegisterCastbarUnitGeneralBoolean = RegisterCastbarUnitGeneralBoolean,
        RegisterBossCastbarDetachSetting = RegisterBossCastbarDetachSetting,
        RegisterPlayerCastbarProvider = RegisterPlayerCastbarProvider,
    })
end

local BuildCastbarRegistryHelperContext = A.CastbarsRegistry and A.CastbarsRegistry.BuildRegistryHelperContext
local CastbarHelpers = type(BuildCastbarRegistryHelperContext) == "function" and BuildCastbarRegistryHelperContext({
    AddAliasesForUnit = AddAliasesForUnit,
    CallGlobal = CallGlobal,
    ApplyCastbar = ApplyCastbar,
    RegisterGeneralBoolean = RegisterGeneralBoolean,
    RegisterGeneralNumberSetting = RegisterGeneralNumberSetting,
    RegisterGeneralEnum = RegisterGeneralEnum,
    RegisterGeneralString = RegisterGeneralString,
}) or nil
if type(CastbarHelpers) ~= "table" then return end

local CastbarAliases = CastbarHelpers.CastbarAliases
local UnitCastbarAliases = CastbarHelpers.UnitCastbarAliases
local ApplyCastbarTextures = CastbarHelpers.ApplyCastbarTextures
local ApplyCastbarOutline = CastbarHelpers.ApplyCastbarOutline
local ApplyFocusKick = CastbarHelpers.ApplyFocusKick
local ApplyFocusKickText = CastbarHelpers.ApplyFocusKickText
local RegisterCastbarBoolean = CastbarHelpers.RegisterCastbarBoolean
local RegisterCastbarNumber = CastbarHelpers.RegisterCastbarNumber
local RegisterCastbarEnum = CastbarHelpers.RegisterCastbarEnum
local RegisterCastbarString = CastbarHelpers.RegisterCastbarString

local BuildCastbarNumericBooleanRegistrar = A.CastbarsRegistry and A.CastbarsRegistry.BuildNumericBooleanRegistrar
local RegisterCastbarNumericBoolean = type(BuildCastbarNumericBooleanRegistrar) == "function" and BuildCastbarNumericBooleanRegistrar({
    Registry = Registry,
    GeneralDB = GeneralDB,
    ApplyCastbar = ApplyCastbar,
}) or nil
if type(RegisterCastbarNumericBoolean) ~= "function" then return end

local RegisterCastbarDetailSettings = A.CastbarsRegistry and A.CastbarsRegistry.RegisterDetailSettings
if type(RegisterCastbarDetailSettings) == "function" then
    RegisterCastbarDetailSettings({
        CASTBAR_DETAIL_FIELDS = CASTBAR_DETAIL_FIELDS,
        CastbarAliases = CastbarAliases,
        UnitCastbarAliases = UnitCastbarAliases,
        RegisterCastbarNumber = RegisterCastbarNumber,
        RegisterGeneralNumber = RegisterGeneralNumber,
        RegisterGeneralEnumSetting = RegisterGeneralEnumSetting,
        ApplyCastbarTextures = ApplyCastbarTextures,
        ApplyCastbar = ApplyCastbar,
    })
end

local RegisterCastbarAppearanceSettings = A.CastbarsRegistry and A.CastbarsRegistry.RegisterAppearanceSettings
if type(RegisterCastbarAppearanceSettings) == "function" then
    RegisterCastbarAppearanceSettings({
        Registry = Registry,
        CastbarAliases = CastbarAliases,
        RegisterCastbarBoolean = RegisterCastbarBoolean,
        RegisterCastbarNumber = RegisterCastbarNumber,
        RegisterCastbarEnum = RegisterCastbarEnum,
        RegisterCastbarString = RegisterCastbarString,
        RegisterCastbarNumericBoolean = RegisterCastbarNumericBoolean,
        ApplyCastbarTextures = ApplyCastbarTextures,
        ApplyCastbarOutline = ApplyCastbarOutline,
        ApplyFocusKick = ApplyFocusKick,
        ApplyFocusKickText = ApplyFocusKickText,
    })
end

C.CASTBAR_KEYS = CASTBAR_KEYS
C.GetCastbarBackend = CastbarCore.GetCastbarBackend
