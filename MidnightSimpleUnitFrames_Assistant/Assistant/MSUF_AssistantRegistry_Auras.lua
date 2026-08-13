-- Assistant Auras registry: maps natural phrases to Auras3 unit/group settings and actions.
-- This file owns metadata only; live aura tracking and assignment stay in Blizzard's native 12.1 containers.
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

-- Auras registry domain.
-- Maps assistant phrases onto Auras3 unit/group settings and filter toggles. The registry
-- writes saved config only; Auras3 only refreshes native container/frame layout.
-- C.Registry is the single shared registry table (A.Registry === A.RegistryCore.Registry).
local Registry = C.Registry
local UNIT_LABELS = C.UNIT_LABELS
local UNIT_ALIASES = C.UNIT_ALIASES
local AuraModel = C.AuraModel
local ApplyAura = C.ApplyAura
local ApplyAuraText = C.ApplyAuraText
local EnsureAuraFallbackDB = C.EnsureAuraFallbackDB
local AuraRuntimeUnit = C.AuraRuntimeUnit
local AuraReadNumber = C.AuraReadNumber
local AuraWriteNumber = C.AuraWriteNumber
local AuraReadStackAnchor = C.AuraReadStackAnchor
local AuraWriteStackAnchor = C.AuraWriteStackAnchor
local AuraReadCooldownAnchor = C.AuraReadCooldownAnchor
local AuraWriteCooldownAnchor = C.AuraWriteCooldownAnchor
local AuraLaneShown = C.AuraLaneShown
local SetAuraLaneShown = C.SetAuraLaneShown

local AurasData = A.AurasRegistryData
if type(AurasData) ~= "table" then return end

local AURA_SCOPE_ALIASES = AurasData.AURA_SCOPE_ALIASES
local AURA_EDIT_SCOPE_ALIASES = AurasData.AURA_EDIT_SCOPE_ALIASES
local AURA_RELATIVE_SIZE_NOUNS = AurasData.AURA_RELATIVE_SIZE_NOUNS
local AURA_ANCHOR_VALUES = AurasData.AURA_ANCHOR_VALUES

local BuildAuraAliasHelpers = A.AurasRegistry and A.AurasRegistry.BuildAliasHelpers
if type(BuildAuraAliasHelpers) ~= "function" then return end
local AuraAliasHelpers = BuildAuraAliasHelpers({
    A = A,
    UNIT_LABELS = UNIT_LABELS,
    UNIT_ALIASES = UNIT_ALIASES,
    AURA_SCOPE_ALIASES = AURA_SCOPE_ALIASES,
    AURA_EDIT_SCOPE_ALIASES = AURA_EDIT_SCOPE_ALIASES,
    AURA_RELATIVE_SIZE_NOUNS = AURA_RELATIVE_SIZE_NOUNS,
})
local AuraScopeLabel = AuraAliasHelpers.AuraScopeLabel
local AuraScopeFromArg = AuraAliasHelpers.AuraScopeFromArg
local AddAliasesForAuraScope = AuraAliasHelpers.AddAliasesForAuraScope
local AddAuraLaneAliases = AuraAliasHelpers.AddAuraLaneAliases
local AddAuraLaneRelativeSizeAliases = AuraAliasHelpers.AddAuraLaneRelativeSizeAliases
if type(AuraScopeLabel) ~= "function" or type(AuraScopeFromArg) ~= "function" then return end
if type(AddAliasesForAuraScope) ~= "function" or type(AddAuraLaneAliases) ~= "function" then return end
if type(AddAuraLaneRelativeSizeAliases) ~= "function" then return end

local BuildAuraStateHelpers = A.AurasRegistry and A.AurasRegistry.BuildStateHelpers
local AuraStateHelpers = type(BuildAuraStateHelpers) == "function" and BuildAuraStateHelpers({
    AuraModel = AuraModel,
    EnsureAuraFallbackDB = EnsureAuraFallbackDB,
    AuraRuntimeUnit = AuraRuntimeUnit,
}) or nil
if type(AuraStateHelpers) ~= "table" then return end
local BuildAuraRegistrationHelpers = A.AurasRegistry and A.AurasRegistry.BuildRegistrationHelpers
local AuraRegistrationHelpers = type(BuildAuraRegistrationHelpers) == "function" and BuildAuraRegistrationHelpers({
    Registry = Registry,
    UNIT_LABELS = UNIT_LABELS,
    AuraScopeLabel = AuraScopeLabel,
    AuraModel = AuraModel,
    ApplyAura = ApplyAura,
    ApplyAuraText = ApplyAuraText,
    EnsureAuraFallbackDB = EnsureAuraFallbackDB,
    AuraReadNumber = AuraReadNumber,
    AuraWriteNumber = AuraWriteNumber,
    AuraReadStackAnchor = AuraReadStackAnchor,
    AuraWriteStackAnchor = AuraWriteStackAnchor,
    AuraReadCooldownAnchor = AuraReadCooldownAnchor,
    AuraWriteCooldownAnchor = AuraWriteCooldownAnchor,
    AuraLaneShown = AuraLaneShown,
    SetAuraLaneShown = SetAuraLaneShown,
    AURA_ANCHOR_VALUES = AURA_ANCHOR_VALUES,
}) or nil
if type(AuraRegistrationHelpers) ~= "table" then return end
local InstallAuraSettingRegistries = A.AurasRegistry and A.AurasRegistry.InstallSettingRegistries
if type(InstallAuraSettingRegistries) == "function" then
    InstallAuraSettingRegistries({
        C = C,
        M = M,
        A = A,
        Registry = Registry,
        AurasData = AurasData,
        AuraAliasHelpers = AuraAliasHelpers,
        AuraStateHelpers = AuraStateHelpers,
        AuraRegistrationHelpers = AuraRegistrationHelpers,
    })
end

local InstallAuraRuntimeContexts = A.AurasRegistry and A.AurasRegistry.InstallRuntimeContexts
if type(InstallAuraRuntimeContexts) == "function" then
    InstallAuraRuntimeContexts({
        C = C,
        M = M,
        A = A,
        AurasData = AurasData,
        AuraScopeFromArg = AuraScopeFromArg,
        AuraScopeLabel = AuraScopeLabel,
    })
end
