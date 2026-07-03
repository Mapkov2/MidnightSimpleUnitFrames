-- Assistant GroupFrames shared registry helpers.
-- Builds the helper/context tables consumed by the split GroupFrames registry modules.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.BuildCoreContext(ctx)
    if type(ctx) ~= "table" then return nil end

    local Registry = ctx.Registry
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local EnsureDB = ctx.EnsureDB
    local GeneralDB = ctx.GeneralDB
    local GroupDB = ctx.GroupDB
    local ClampNumber = ctx.ClampNumber
    local ApplyGroup = ctx.ApplyGroup
    local GroupFramesData = ctx.GroupFramesData

    if not (Registry and type(Registry.RegisterSetting) == "function") then return nil end
    if type(AddAliasesForUnit) ~= "function" or type(GroupDB) ~= "function" then return nil end
    if type(ClampNumber) ~= "function" or type(ApplyGroup) ~= "function" then return nil end
    if type(GroupFramesData) ~= "table" then return nil end

    local BuildStatusIconCoreContext = A.GroupFramesRegistry and A.GroupFramesRegistry.BuildStatusIconCoreContext
    local StatusIconCore = type(BuildStatusIconCoreContext) == "function" and BuildStatusIconCoreContext({
        GroupFramesData = GroupFramesData,
        AddAliasesForUnit = AddAliasesForUnit,
        GroupDB = GroupDB,
        ApplyGroup = ApplyGroup,
    }) or nil
    if type(StatusIconCore) ~= "table" then return nil end

    local BuildRegisterCoreContext = A.GroupFramesRegistry and A.GroupFramesRegistry.BuildRegisterCoreContext
    local RegisterCore = type(BuildRegisterCoreContext) == "function" and BuildRegisterCoreContext({
        Registry = Registry,
        UNIT_LABELS = UNIT_LABELS,
        GroupDB = GroupDB,
        ClampNumber = ClampNumber,
        ApplyGroup = ApplyGroup,
    }) or nil
    if type(RegisterCore) ~= "table" then return nil end
    local RegisterGroupBoolean = RegisterCore.RegisterGroupBoolean
    local RegisterGroupNumber = RegisterCore.RegisterGroupNumber
    local RegisterGroupEnum = RegisterCore.RegisterGroupEnum
    local RegisterGroupString = RegisterCore.RegisterGroupString
    if type(RegisterGroupBoolean) ~= "function" or type(RegisterGroupNumber) ~= "function" then return nil end
    if type(RegisterGroupEnum) ~= "function" or type(RegisterGroupString) ~= "function" then return nil end

    local GROUP_BAR_MODE_VALUES = GroupFramesData.GROUP_BAR_MODE_VALUES or {}
    local GROUP_HEALTH_MODE_VALUES = GroupFramesData.GROUP_HEALTH_MODE_VALUES or {}
    local GROUP_ANCHOR_VALUES = GroupFramesData.GROUP_ANCHOR_VALUES or {}
    local GROUP_DISPEL_TRIGGER_VALUES = GroupFramesData.GROUP_DISPEL_TRIGGER_VALUES or {}
    local GROUP_DISPEL_STYLE_VALUES = GroupFramesData.GROUP_DISPEL_STYLE_VALUES or {}
    local GROUP_STRIPE_EDGE_VALUES = GroupFramesData.GROUP_STRIPE_EDGE_VALUES or {}
    local GROUP_RANGE_LAYER_VALUES = GroupFramesData.GROUP_RANGE_LAYER_VALUES or {}

    local GROUP_ANCHOR_ALIASES = GroupFramesData.GROUP_ANCHOR_ALIASES or {}

    local BuildTextCoreContext = A.GroupFramesRegistry and A.GroupFramesRegistry.BuildTextCoreContext
    local TextCore = type(BuildTextCoreContext) == "function" and BuildTextCoreContext({
        Registry = Registry,
        UNIT_LABELS = UNIT_LABELS,
        EnsureDB = EnsureDB,
        GeneralDB = GeneralDB,
        GroupDB = GroupDB,
        ApplyGroup = ApplyGroup,
        RegisterGroupString = RegisterGroupString,
        RegisterGroupEnum = RegisterGroupEnum,
        GroupFramesData = GroupFramesData,
    }) or nil
    if type(TextCore) ~= "table" then return nil end

    local settings = {
        Registry = Registry,
        UNIT_LABELS = UNIT_LABELS,
        AddAliasesForUnit = AddAliasesForUnit,
        GeneralDB = GeneralDB,
        GroupDB = GroupDB,
        ClampNumber = ClampNumber,
        ApplyGroup = ApplyGroup,
        RegisterGroupBoolean = RegisterGroupBoolean,
        RegisterGroupNumber = RegisterGroupNumber,
        RegisterGroupEnum = RegisterGroupEnum,
        RegisterGroupString = RegisterGroupString,
        RegisterGroupColor = TextCore.RegisterGroupColor,
        RegisterGroupTexture = TextCore.RegisterGroupTexture,
        RegisterGroupTextMode = TextCore.RegisterGroupTextMode,
        RegisterGroupDelimiter = TextCore.RegisterGroupDelimiter,
        GroupReverseFillExactAliases = TextCore.GroupReverseFillExactAliases,
        GroupReverseFillBooleanAliases = TextCore.GroupReverseFillBooleanAliases,
        GroupNameShorteningMax = TextCore.GroupNameShorteningMax,
        GroupNameShorteningEnabled = TextCore.GroupNameShorteningEnabled,
        GroupNameShorteningSide = TextCore.GroupNameShorteningSide,
        GroupNameShorteningNoEllipsis = TextCore.GroupNameShorteningNoEllipsis,
        SetGroupFontOverrideValue = TextCore.SetGroupFontOverrideValue,
        GroupGrowthExactAliases = TextCore.GroupGrowthExactAliases,
        NormalizeGroupRoleOrder = TextCore.NormalizeGroupRoleOrder,
        StandardGroupAnchorTarget = TextCore.StandardGroupAnchorTarget,
        TrimString = TextCore.TrimString,
        GroupBarModeExactAliases = TextCore.GroupBarModeExactAliases,
        GroupColorSame = TextCore.GroupColorSame,
        GetGroupHealthBarColor = TextCore.GetGroupHealthBarColor,
        SetGroupHealthBarColor = TextCore.SetGroupHealthBarColor,
        NormalizeGroupDispelTrigger = TextCore.NormalizeGroupDispelTrigger,
        AddGroupStatusIconAliases = StatusIconCore.AddGroupStatusIconAliases,
        GROUP_BAR_MODE_VALUES = GROUP_BAR_MODE_VALUES,
        GROUP_HEALTH_MODE_VALUES = GROUP_HEALTH_MODE_VALUES,
        GROUP_ANCHOR_VALUES = GROUP_ANCHOR_VALUES,
        GROUP_ANCHOR_ALIASES = GROUP_ANCHOR_ALIASES,
        GROUP_DISPEL_TRIGGER_VALUES = GROUP_DISPEL_TRIGGER_VALUES,
        GROUP_DISPEL_STYLE_VALUES = GROUP_DISPEL_STYLE_VALUES,
        GROUP_STRIPE_EDGE_VALUES = GROUP_STRIPE_EDGE_VALUES,
        GROUP_RANGE_LAYER_VALUES = GROUP_RANGE_LAYER_VALUES,
        GROUP_STATUS_ICON_STYLE_VALUES = StatusIconCore.GROUP_STATUS_ICON_STYLE_VALUES,
        GROUP_STATUS_ICON_STYLE_ALIASES = StatusIconCore.GROUP_STATUS_ICON_STYLE_ALIASES,
        GROUP_STATUS_ICON_PACK_VALUES = StatusIconCore.GROUP_STATUS_ICON_PACK_VALUES,
        GROUP_STATUS_ICON_PACK_ALIASES = StatusIconCore.GROUP_STATUS_ICON_PACK_ALIASES,
        GROUP_STATUS_ANCHOR_VALUES = StatusIconCore.GROUP_STATUS_ANCHOR_VALUES,
        GROUP_STATUS_ANCHOR_ALIASES = StatusIconCore.GROUP_STATUS_ANCHOR_ALIASES,
        GROUP_STATUS_ICON_SPECS = StatusIconCore.GROUP_STATUS_ICON_SPECS,
    }

    return {
        Settings = settings,
        ResolveGroupStatusIcon = StatusIconCore.ResolveGroupStatusIcon,
        ResetGroupStatusIcon = StatusIconCore.ResetGroupStatusIcon,
        GROUP_STATUS_ICON_SPECS = StatusIconCore.GROUP_STATUS_ICON_SPECS,
    }
end
