-- Assistant Auras setting registry installer.
-- Loaded before MSUF_AssistantRegistry_Auras.lua; the main Auras hub passes helper contexts in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.InstallSettingRegistries(ctx)
    if type(ctx) ~= "table" then return end

    local C = ctx.C
    if type(C) ~= "table" then return end

    local ARef = ctx.A or A
    local RegistryNS = ARef.AurasRegistry or A.AurasRegistry or {}
    local Registry = ctx.Registry or C.Registry
    local Data = ctx.AurasData or ARef.AurasRegistryData or {}
    local AliasHelpers = ctx.AuraAliasHelpers or {}
    local StateHelpers = ctx.AuraStateHelpers or {}
    local SharedStateHelpers = ctx.AuraSharedStateHelpers or {}
    local RegistrationHelpers = ctx.AuraRegistrationHelpers or {}

    local RegisterAuraMenuSettings = RegistryNS.RegisterMenuSettings
    if type(RegisterAuraMenuSettings) == "function" then
        RegisterAuraMenuSettings({
            Registry = Registry,
            M = ctx.M or M,
            AURA_EDIT_SCOPE_VALUES = Data.AURA_EDIT_SCOPE_VALUES,
            AURA_EDIT_SCOPE_ALIASES = Data.AURA_EDIT_SCOPE_ALIASES,
            AURA_LANE_MENU_VALUES = Data.AURA_LANE_MENU_VALUES,
            AURA_LANE_MENU_ALIASES = Data.AURA_LANE_MENU_ALIASES,
            AURA_STYLE_LANE_ALIASES = Data.AURA_STYLE_LANE_ALIASES,
            AURA_STYLE_LANE_EXACT_ALIASES = Data.AURA_STYLE_LANE_EXACT_ALIASES,
            AURA_FILTER_LANE_ALIASES = Data.AURA_FILTER_LANE_ALIASES,
            AURA_FILTER_LANE_EXACT_ALIASES = Data.AURA_FILTER_LANE_EXACT_ALIASES,
            AURA_BLACKLIST_PRESET_VALUES = Data.AURA_BLACKLIST_PRESET_VALUES,
            AURA_BLACKLIST_PRESET_ALIASES = Data.AURA_BLACKLIST_PRESET_ALIASES,
            AURA_UX_MODE_VALUES = Data.AURA_UX_MODE_VALUES,
            AURA_UX_MODE_ALIASES = Data.AURA_UX_MODE_ALIASES,
            AURA_UX_MODE_EXACT_ALIASES = Data.AURA_UX_MODE_EXACT_ALIASES,
            AURA_UX_MODE_VALUE_ALIASES = Data.AURA_UX_MODE_VALUE_ALIASES,
            AuraRootBool = StateHelpers.AuraRootBool,
            SetAuraRootBool = StateHelpers.SetAuraRootBool,
            AuraSharedTable = SharedStateHelpers.AuraSharedTable,
            AuraSharedBool = C.AuraSharedBool,
            SetAuraSharedBool = C.SetAuraSharedBool,
            AuraScopeFromArg = AliasHelpers.AuraScopeFromArg,
            ApplyAura = C.ApplyAura,
        })
    end

    local RegisterAuraSharedSettings = RegistryNS.RegisterSharedSettings
    if type(RegisterAuraSharedSettings) == "function" then
        RegisterAuraSharedSettings({
            Registry = Registry,
            AURA_UNITS = Data.AURA_UNITS,
            AURA_SCOPE_OVERRIDE_SPECS = Data.AURA_SCOPE_OVERRIDE_SPECS or {},
            AURA_SHARED_BOOLEAN_SPECS = Data.AURA_SHARED_BOOLEAN_SPECS or {},
            AURA_REMINDER_SPECS = Data.AURA_REMINDER_SPECS or {},
            AURA_GROWTH_VALUES = Data.AURA_GROWTH_VALUES,
            AURA_GROWTH_ALIASES = Data.AURA_GROWTH_ALIASES,
            AURA_ROW_WRAP_VALUES = Data.AURA_ROW_WRAP_VALUES,
            AURA_ROW_WRAP_ALIASES = Data.AURA_ROW_WRAP_ALIASES,
            AddAliasesForAuraScope = AliasHelpers.AddAliasesForAuraScope,
            AuraScopeLabel = AliasHelpers.AuraScopeLabel,
            AuraOverrideBool = StateHelpers.AuraOverrideBool,
            SetAuraOverrideBool = StateHelpers.SetAuraOverrideBool,
            RegisterAuraScopeBoolean = RegistrationHelpers.RegisterAuraScopeBoolean,
            AuraSharedBool = C.AuraSharedBool,
            SetAuraSharedBool = C.SetAuraSharedBool,
            AuraReadNumber = C.AuraReadNumber,
            AuraWriteNumber = C.AuraWriteNumber,
            AuraSharedString = SharedStateHelpers.AuraSharedString,
            SetAuraSharedString = SharedStateHelpers.SetAuraSharedString,
            AuraSharedTable = SharedStateHelpers.AuraSharedTable,
            ApplyAura = C.ApplyAura,
            ApplyAuraReminders = SharedStateHelpers.ApplyAuraReminders,
        })
    end

    local RegisterAuraUnitLaneSettings = RegistryNS.RegisterUnitLaneSettings
    if type(RegisterAuraUnitLaneSettings) == "function" then
        RegisterAuraUnitLaneSettings({
            A = ARef,
            AURA_UNITS = Data.AURA_UNITS,
            AURA_LANES = Data.AURA_LANES,
            AddAliasesForAuraScope = AliasHelpers.AddAliasesForAuraScope,
            AddAuraLaneAliases = AliasHelpers.AddAuraLaneAliases,
            AddAuraLaneRelativeSizeAliases = AliasHelpers.AddAuraLaneRelativeSizeAliases,
            RegisterAuraUnitLaneBoolean = RegistrationHelpers.RegisterAuraUnitLaneBoolean,
            RegisterAuraUnitLaneNumber = RegistrationHelpers.RegisterAuraUnitLaneNumber,
            RegisterAuraUnitLaneEnum = RegistrationHelpers.RegisterAuraUnitLaneEnum,
            AuraLaneDefaultMax = C.AuraLaneDefaultMax,
            AuraLaneMaxKey = C.AuraLaneMaxKey,
            AuraLaneSizeKey = C.AuraLaneSizeKey,
            AuraLaneXKey = C.AuraLaneXKey,
            AuraLaneYKey = C.AuraLaneYKey,
            AuraLaneDefaultY = C.AuraLaneDefaultY,
            AuraReadNumber = C.AuraReadNumber,
            AuraWriteNumber = C.AuraWriteNumber,
            AuraReadLanePerRow = C.AuraReadLanePerRow,
            AuraWriteLanePerRow = C.AuraWriteLanePerRow,
            AURA_LANE_GROWTH_VALUES = Data.AURA_LANE_GROWTH_VALUES,
            AURA_LANE_GROWTH_ALIASES = Data.AURA_LANE_GROWTH_ALIASES,
            AuraReadLaneGrowthPair = RegistrationHelpers.AuraReadLaneGrowthPair,
            AuraWriteLaneGrowthPair = RegistrationHelpers.AuraWriteLaneGrowthPair,
            AURA_ANCHOR_VALUES = Data.AURA_ANCHOR_VALUES,
            AURA_ANCHOR_ALIASES = Data.AURA_ANCHOR_ALIASES,
            AuraReadLaneAnchor = RegistrationHelpers.AuraReadLaneAnchor,
            AuraWriteLaneAnchor = RegistrationHelpers.AuraWriteLaneAnchor,
            AuraReadLaneLayer = RegistrationHelpers.AuraReadLaneLayer,
            AuraWriteLaneLayer = RegistrationHelpers.AuraWriteLaneLayer,
        })
    end

    local RegisterAuraStyleAndFilterSettings = RegistryNS.RegisterStyleAndFilterSettings
    if type(RegisterAuraStyleAndFilterSettings) == "function" then
        RegisterAuraStyleAndFilterSettings({
            Registry = Registry,
            AURA_SCOPES = Data.AURA_SCOPES,
            AURA_LANES = Data.AURA_LANES,
            AURA_ANCHOR_VALUES = Data.AURA_ANCHOR_VALUES,
            AURA_ANCHOR_ALIASES = Data.AURA_ANCHOR_ALIASES,
            AURA_STACK_ANCHOR_VALUES = Data.AURA_STACK_ANCHOR_VALUES,
            AURA_STACK_ANCHOR_ALIASES = Data.AURA_STACK_ANCHOR_ALIASES,
            AURA_COOLDOWN_SWIPE_DIRECTION_VALUES = Data.AURA_COOLDOWN_SWIPE_DIRECTION_VALUES or {},
            AURA_COOLDOWN_SWIPE_DIRECTION_ALIASES = Data.AURA_COOLDOWN_SWIPE_DIRECTION_ALIASES or {},
            AURA_DURATION_BAR_POSITION_VALUES = Data.AURA_DURATION_BAR_POSITION_VALUES or {},
            AURA_DURATION_BAR_POSITION_ALIASES = Data.AURA_DURATION_BAR_POSITION_ALIASES or {},
            AURA_DURATION_BAR_DISPLAY_VALUES = Data.AURA_DURATION_BAR_DISPLAY_VALUES or {},
            AURA_DURATION_BAR_DISPLAY_ALIASES = Data.AURA_DURATION_BAR_DISPLAY_ALIASES or {},
            AURA_DURATION_BAR_DIRECTION_VALUES = Data.AURA_DURATION_BAR_DIRECTION_VALUES or {},
            AURA_DURATION_BAR_DIRECTION_ALIASES = Data.AURA_DURATION_BAR_DIRECTION_ALIASES or {},
            AURA_LANE_STYLE_BOOLEAN_SPECS = Data.AURA_LANE_STYLE_BOOLEAN_SPECS or {},
            AURA_LANE_STYLE_NUMBER_SPECS = Data.AURA_LANE_STYLE_NUMBER_SPECS or {},
            AURA_DEBUFF_TYPE_BORDER_VALUES = Data.AURA_DEBUFF_TYPE_BORDER_VALUES or {},
            AURA_DEBUFF_TYPE_BORDER_ALIASES = Data.AURA_DEBUFF_TYPE_BORDER_ALIASES or {},
            AURA_FILTER_BOOLEAN_SPECS = Data.AURA_FILTER_BOOLEAN_SPECS or {},
            AURA_EXCLUSIVE_FILTER_VALUES = Data.AURA_EXCLUSIVE_FILTER_VALUES or {},
            AURA_EXCLUSIVE_FILTER_ALIASES = Data.AURA_EXCLUSIVE_FILTER_ALIASES or {},
            AddAliasesForAuraScope = AliasHelpers.AddAliasesForAuraScope,
            AddAuraLaneAliases = AliasHelpers.AddAuraLaneAliases,
            AuraScopeLabel = AliasHelpers.AuraScopeLabel,
            RegisterAuraScopeBoolean = RegistrationHelpers.RegisterAuraScopeBoolean,
            RegisterAuraScopeNumber = RegistrationHelpers.RegisterAuraScopeNumber,
            RegisterAuraScopeEnum = RegistrationHelpers.RegisterAuraScopeEnum,
            RegisterAuraScopeLaneBoolean = RegistrationHelpers.RegisterAuraScopeLaneBoolean,
            RegisterAuraScopeLaneNumber = RegistrationHelpers.RegisterAuraScopeLaneNumber,
            RegisterAuraScopeLaneEnum = RegistrationHelpers.RegisterAuraScopeLaneEnum,
            AuraSharedBool = C.AuraSharedBool,
            SetAuraSharedBool = C.SetAuraSharedBool,
            AuraReadNumber = C.AuraReadNumber,
            AuraWriteNumber = C.AuraWriteNumber,
            AuraReadStackAnchor = C.AuraReadStackAnchor,
            AuraWriteStackAnchor = C.AuraWriteStackAnchor,
            AuraReadCooldownAnchor = C.AuraReadCooldownAnchor,
            AuraWriteCooldownAnchor = C.AuraWriteCooldownAnchor,
            AuraReadLaneStyleBool = RegistrationHelpers.AuraReadLaneStyleBool,
            AuraWriteLaneStyleBool = RegistrationHelpers.AuraWriteLaneStyleBool,
            AuraReadLaneStyleNumber = RegistrationHelpers.AuraReadLaneStyleNumber,
            AuraWriteLaneStyleNumber = RegistrationHelpers.AuraWriteLaneStyleNumber,
            AuraReadLaneStackAnchor = RegistrationHelpers.AuraReadLaneStackAnchor,
            AuraWriteLaneStackAnchor = RegistrationHelpers.AuraWriteLaneStackAnchor,
            AuraReadLaneCooldownAnchor = RegistrationHelpers.AuraReadLaneCooldownAnchor,
            AuraWriteLaneCooldownAnchor = RegistrationHelpers.AuraWriteLaneCooldownAnchor,
            AuraUseSharedVisuals = C.AuraUseSharedVisuals,
            AuraSetUseSharedVisuals = C.AuraSetUseSharedVisuals,
            AuraUseSharedRules = C.AuraUseSharedRules,
            AuraSetUseSharedRules = C.AuraSetUseSharedRules,
            AuraModel = C.AuraModel,
            AuraFiltersEnabled = C.AuraFiltersEnabled,
            AuraSetFiltersEnabled = C.AuraSetFiltersEnabled,
            AuraReadFilter = C.AuraReadFilter,
            AuraWriteFilter = C.AuraWriteFilter,
            ApplyAura = C.ApplyAura,
        })
    end
end
