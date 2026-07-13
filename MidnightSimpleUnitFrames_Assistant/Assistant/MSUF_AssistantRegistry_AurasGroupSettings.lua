-- Assistant Group Aura registry: maps group aura settings to registry metadata.
-- Aura rendering remains Auras3-owned; broad group changes must keep confirmation semantics.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local A = MSUF.Assistant or {}
MSUF.Assistant = A

-- Group Auras assistant registry domain.
local ctx = A.AurasRegistry and A.AurasRegistry.GroupSettings
if type(ctx) ~= "table" then return end

local Registry = ctx.Registry
A = ctx.A or A
local UNIT_LABELS = ctx.UNIT_LABELS or {}
local UNIT_ALIASES = ctx.UNIT_ALIASES or {}
local AddAliasesForUnit = ctx.AddAliasesForUnit
local AuraModel = ctx.AuraModel
local GFAurasRoot = ctx.GFAurasRoot
local GFAuraGroup = ctx.GFAuraGroup
local GFAuraLaneShown = ctx.GFAuraLaneShown
local SetGFAuraLaneShown = ctx.SetGFAuraLaneShown
local GFReadAuraNumber = ctx.GFReadAuraNumber
local GFWriteAuraNumber = ctx.GFWriteAuraNumber
local GFReadAuraValue = ctx.GFReadAuraValue
local GFWriteAuraValue = ctx.GFWriteAuraValue
local GFReadConfValue = ctx.GFReadConfValue
local GFWriteConfValue = ctx.GFWriteConfValue
local ApplyGroup = ctx.ApplyGroup
local AURA_LANES = ctx.AURA_LANES or {}
local AURA_RELATIVE_SIZE_NOUNS = ctx.AURA_RELATIVE_SIZE_NOUNS or {}
local AurasData = A.AurasRegistryData or {}

if not (Registry and type(Registry.RegisterSetting) == "function") then return end
if type(AddAliasesForUnit) ~= "function" or type(AuraModel) ~= "function" then return end
if type(GFAurasRoot) ~= "function" or type(GFAuraGroup) ~= "function" then return end
if type(GFAuraLaneShown) ~= "function" or type(SetGFAuraLaneShown) ~= "function" then return end
if type(GFReadAuraNumber) ~= "function" or type(GFWriteAuraNumber) ~= "function" then return end
if type(GFReadAuraValue) ~= "function" or type(GFWriteAuraValue) ~= "function" then return end
if type(GFReadConfValue) ~= "function" or type(GFWriteConfValue) ~= "function" then return end
if type(ApplyGroup) ~= "function" then return end
local GF_AURA_GROUPS = AurasData.GF_AURA_GROUPS or {}
local GF_AURA_ANCHORS = AurasData.GF_AURA_ANCHORS or {}
local GF_AURA_GROWTH = AurasData.GF_AURA_GROWTH or {}
local GF_AURA_FILTER_VALUES = AurasData.GF_AURA_FILTER_VALUES or {}
local GF_AURA_FILTER_ALIASES = AurasData.GF_AURA_FILTER_ALIASES or {}

local BuildGroupAuraLaneCore = A.AurasRegistry and A.AurasRegistry.BuildGroupAuraLaneCore
local LaneCore = type(BuildGroupAuraLaneCore) == "function" and BuildGroupAuraLaneCore({
    A = A,
    Registry = Registry,
    UNIT_LABELS = UNIT_LABELS,
    UNIT_ALIASES = UNIT_ALIASES,
    AddAliasesForUnit = AddAliasesForUnit,
    GFAurasRoot = GFAurasRoot,
    GFAuraLaneShown = GFAuraLaneShown,
    SetGFAuraLaneShown = SetGFAuraLaneShown,
    GFReadAuraNumber = GFReadAuraNumber,
    GFWriteAuraNumber = GFWriteAuraNumber,
    GFReadAuraValue = GFReadAuraValue,
    GFWriteAuraValue = GFWriteAuraValue,
    ApplyGroup = ApplyGroup,
    AURA_RELATIVE_SIZE_NOUNS = AURA_RELATIVE_SIZE_NOUNS,
}) or nil
if type(LaneCore) ~= "table" then return end
local AddGFAuraAliases = LaneCore.AddGFAuraAliases
local AddGFAuraStrictAliases = LaneCore.AddGFAuraStrictAliases
local AddGFAuraRelativeSizeAliases = LaneCore.AddGFAuraRelativeSizeAliases
local RegisterGFAuraBoolean = LaneCore.RegisterGFAuraBoolean
local RegisterGFAuraNumber = LaneCore.RegisterGFAuraNumber
local RegisterGFAuraEnum = LaneCore.RegisterGFAuraEnum

local GF_AURA_CATEGORY_SCOPES = AurasData.GF_AURA_CATEGORY_SCOPES or {}
local GF_AURA_CATEGORY_FALLBACK = AurasData.GF_AURA_CATEGORY_FALLBACK or {}
local BuildGroupAuraCategoryCore = A.AurasRegistry and A.AurasRegistry.BuildGroupAuraCategoryCore
local CategoryCore = type(BuildGroupAuraCategoryCore) == "function" and BuildGroupAuraCategoryCore({
    A = A,
    AuraModel = AuraModel,
    GFAuraGroup = GFAuraGroup,
    ApplyGroup = ApplyGroup,
    GF_AURA_CATEGORY_FALLBACK = GF_AURA_CATEGORY_FALLBACK,
}) or nil
if type(CategoryCore) ~= "table" then return end
local GFAuraCategoryValues = CategoryCore.GFAuraCategoryValues
local GFAuraCategoryLabel = CategoryCore.GFAuraCategoryLabel
local GFAuraCategoryScopeLabel = CategoryCore.GFAuraCategoryScopeLabel
local GFAuraCategoryLaneLabel = CategoryCore.GFAuraCategoryLaneLabel
local ReadGFAuraCategorySetting = CategoryCore.ReadGFAuraCategorySetting
local WriteGFAuraCategoryState = CategoryCore.WriteGFAuraCategoryState
local SameGFAuraCategoryState = CategoryCore.SameGFAuraCategoryState
local ApplyGFAuraCategory = CategoryCore.ApplyGFAuraCategory
if type(GFAuraCategoryValues) ~= "function" or type(GFAuraCategoryLabel) ~= "function" then return end
if type(GFAuraCategoryScopeLabel) ~= "function" or type(GFAuraCategoryLaneLabel) ~= "function" then return end
if type(ReadGFAuraCategorySetting) ~= "function" or type(WriteGFAuraCategoryState) ~= "function" then return end
if type(SameGFAuraCategoryState) ~= "function" or type(ApplyGFAuraCategory) ~= "function" then return end

local RegisterGroupAuraLaneSettings = A.AurasRegistry and A.AurasRegistry.RegisterGroupAuraLaneSettings
if type(RegisterGroupAuraLaneSettings) == "function" then
    RegisterGroupAuraLaneSettings({
        A = A,
        Registry = Registry,
        AuraModel = AuraModel,
        UNIT_LABELS = UNIT_LABELS,
        AddAliasesForUnit = AddAliasesForUnit,
        AddGFAuraAliases = AddGFAuraAliases,
        AddGFAuraStrictAliases = AddGFAuraStrictAliases,
        AddGFAuraRelativeSizeAliases = AddGFAuraRelativeSizeAliases,
        RegisterGFAuraBoolean = RegisterGFAuraBoolean,
        RegisterGFAuraNumber = RegisterGFAuraNumber,
        RegisterGFAuraEnum = RegisterGFAuraEnum,
        RegisterGroupAuraRootSettings = A.AurasRegistry and A.AurasRegistry.RegisterGroupAuraRootSettings,
        GFAurasRoot = GFAurasRoot,
        GFReadAuraValue = GFReadAuraValue,
        GFWriteAuraValue = GFWriteAuraValue,
        GFReadConfValue = GFReadConfValue,
        GFWriteConfValue = GFWriteConfValue,
        ApplyGroup = ApplyGroup,
        GF_AURA_GROUPS = GF_AURA_GROUPS,
        GF_AURA_ANCHORS = GF_AURA_ANCHORS,
        GF_AURA_GROWTH = GF_AURA_GROWTH,
        GF_AURA_FILTER_VALUES = GF_AURA_FILTER_VALUES,
        GF_AURA_FILTER_ALIASES = GF_AURA_FILTER_ALIASES,
        AURA_COOLDOWN_SWIPE_DIRECTION_VALUES = AurasData.AURA_COOLDOWN_SWIPE_DIRECTION_VALUES or {},
        AURA_COOLDOWN_SWIPE_DIRECTION_ALIASES = AurasData.AURA_COOLDOWN_SWIPE_DIRECTION_ALIASES or {},
        AURA_SORT_METHOD_VALUES = AurasData.AURA_SORT_METHOD_VALUES or {},
        AURA_SORT_METHOD_ALIASES = AurasData.AURA_SORT_METHOD_ALIASES or {},
        AURA_SORT_DIRECTION_VALUES = AurasData.AURA_SORT_DIRECTION_VALUES or {},
        AURA_SORT_DIRECTION_ALIASES = AurasData.AURA_SORT_DIRECTION_ALIASES or {},
        AURA_DURATION_BAR_POSITION_VALUES = AurasData.AURA_DURATION_BAR_POSITION_VALUES or {},
        AURA_DURATION_BAR_POSITION_ALIASES = AurasData.AURA_DURATION_BAR_POSITION_ALIASES or {},
        AURA_DURATION_BAR_DISPLAY_VALUES = AurasData.AURA_DURATION_BAR_DISPLAY_VALUES or {},
        AURA_DURATION_BAR_DISPLAY_ALIASES = AurasData.AURA_DURATION_BAR_DISPLAY_ALIASES or {},
        AURA_DURATION_BAR_DIRECTION_VALUES = AurasData.AURA_DURATION_BAR_DIRECTION_VALUES or {},
        AURA_DURATION_BAR_DIRECTION_ALIASES = AurasData.AURA_DURATION_BAR_DIRECTION_ALIASES or {},
        AURA_DEBUFF_TYPE_BORDER_VALUES = AurasData.AURA_DEBUFF_TYPE_BORDER_VALUES or {},
        AURA_DEBUFF_TYPE_BORDER_ALIASES = AurasData.AURA_DEBUFF_TYPE_BORDER_ALIASES or {},
        AURA_LANES = AURA_LANES,
    })
end

local RegisterGroupAuraCategorySettings = A.AurasRegistry and A.AurasRegistry.RegisterGroupAuraCategorySettings
if type(RegisterGroupAuraCategorySettings) == "function" then
    RegisterGroupAuraCategorySettings({
        Registry = Registry,
        AuraModel = AuraModel,
        AddAliasesForUnit = AddAliasesForUnit,
        GFAuraCategoryValues = GFAuraCategoryValues,
        GFAuraCategoryLabel = GFAuraCategoryLabel,
        GFAuraCategoryScopeLabel = GFAuraCategoryScopeLabel,
        GFAuraCategoryLaneLabel = GFAuraCategoryLaneLabel,
        ReadGFAuraCategorySetting = ReadGFAuraCategorySetting,
        WriteGFAuraCategoryState = WriteGFAuraCategoryState,
        SameGFAuraCategoryState = SameGFAuraCategoryState,
        ApplyGFAuraCategory = ApplyGFAuraCategory,
        GF_AURA_CATEGORY_SCOPES = GF_AURA_CATEGORY_SCOPES,
        AURA_LANES = AURA_LANES,
    })
end
