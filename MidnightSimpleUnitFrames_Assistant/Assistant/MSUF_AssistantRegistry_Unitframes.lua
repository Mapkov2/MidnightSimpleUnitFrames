-- Assistant UnitFrame registry: declares natural-language coverage for unit frame settings and actions.
-- Keep this cold metadata aligned with Menu2 controls; runtime updates belong to UF apply helpers.
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

-- Unitframes registry domain.
-- Registers declarative controls for individual player/target/focus/pet/boss frames. Setters
-- only update the owning DB field; apply callbacks route through the normal unitframe refresh.
local Registry = C.Registry
local UNIT_LABELS = C.UNIT_LABELS
local AddAliasesForUnit = C.AddAliasesForUnit
local UnitDB = C.UnitDB
local GeneralDB = C.GeneralDB
local BarsDB = C.BarsDB
local ApplyUnit = C.ApplyUnit
local CallGlobal = C.CallGlobal
local ClampNumber = C.ClampNumber

local UNIT_KEYS = { "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }

local UnitframeData = A.UnitframeRegistryData
if type(UnitframeData) ~= "table" then return end

A.UnitframesRegistry = A.UnitframesRegistry or {}
local BuildUnitframesCore = A.UnitframesRegistry.BuildCoreContext
local UnitframesCore = type(BuildUnitframesCore) == "function" and BuildUnitframesCore({
    Registry = Registry,
    UNIT_LABELS = UNIT_LABELS,
    AddAliasesForUnit = AddAliasesForUnit,
    UnitDB = UnitDB,
    GeneralDB = GeneralDB,
    BarsDB = BarsDB,
    ApplyUnit = ApplyUnit,
    CallGlobal = CallGlobal,
    ClampNumber = ClampNumber,
    UnitframeData = UnitframeData,
    UNIT_KEYS = UNIT_KEYS,
}) or nil
if type(UnitframesCore) ~= "table" then return end

A.ResolveUnitStatusSpec = UnitframesCore.ResolveUnitStatusSpec

local RegisterCoreLoopSettings = A.UnitframesRegistry.RegisterCoreLoopSettings
if type(RegisterCoreLoopSettings) == "function" then
    RegisterCoreLoopSettings({
        AddAliasesForUnit = AddAliasesForUnit,
        MakeAliases = UnitframesCore.MakeAliases,
        RegisterUnitBooleanSetting = UnitframesCore.RegisterUnitBooleanSetting,
        RegisterUnitEnum = UnitframesCore.RegisterUnitEnum,
        RegisterUnitAnchoringSettings = A.UnitframesRegistry.RegisterAnchoringSettings,
        RegisterUnitPortraitSettings = A.UnitframesRegistry.RegisterPortraitSettings,
        RegisterUnitPowerSettings = A.UnitframesRegistry.RegisterPowerSettings,
        RegisterUnitTextSettings = A.UnitframesRegistry.RegisterTextSettings,
        RegisterUnitTransparencyAndRangeSettings = A.UnitframesRegistry.RegisterTransparencyAndRangeSettings,
        RegisterUnitTextureLayerSettings = A.UnitframesRegistry.RegisterTextureLayerSettings,
        RegisterUnitStatusIconSettings = A.UnitframesRegistry.RegisterStatusIconSettings,
        RegisterStatusTextStateSettings = A.UnitframesRegistry.RegisterStatusTextStateSettings,
        UnitDB = UnitDB,
        CallGlobal = CallGlobal,
        ApplyLoadCondition = UnitframesCore.ApplyLoadCondition,
        UNIT_KEYS = UnitframesCore.UNIT_KEYS or UNIT_KEYS,
        UNIT_LABELS = UNIT_LABELS,
        LOAD_CONDITION_SPECS = UnitframesCore.LOAD_CONDITION_SPECS,
        UnitAnchoringSettings = UnitframesCore.UnitAnchoringSettings,
        UnitPortraitSettings = UnitframesCore.UnitPortraitSettings,
        UnitPowerSettings = UnitframesCore.UnitPowerSettings,
        UnitTextSettings = UnitframesCore.UnitTextSettings,
        UnitTransparencySettings = UnitframesCore.UnitTransparencySettings,
        UnitTextureLayerSettings = UnitframesCore.UnitTextureLayerSettings,
        UnitStatusSettings = UnitframesCore.UnitStatusSettings,
        HEALTH_COLOR_MODE_VALUES = UnitframeData.HEALTH_COLOR_MODE_VALUES,
        HEALTH_COLOR_MODE_ALIASES = UnitframeData.HEALTH_COLOR_MODE_ALIASES,
    })
end

A.UnitframesRegistry.SpecialSettings = UnitframesCore.SpecialSettings
A.UnitframesRegistry.Actions = UnitframesCore.Actions
