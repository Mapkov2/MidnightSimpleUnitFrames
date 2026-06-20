-- Assistant Auras registration helper factory.
-- Loaded before MSUF_AssistantRegistry_Auras.lua; the main domain passes registry/model helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.BuildRegistrationHelpers(ctx)
    if type(ctx) ~= "table" then return nil end

    local Registry = ctx.Registry
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local AuraScopeLabel = ctx.AuraScopeLabel
    local AuraModel = ctx.AuraModel
    local ApplyAura = ctx.ApplyAura
    local ApplyAuraText = ctx.ApplyAuraText
    local EnsureAuraFallbackDB = ctx.EnsureAuraFallbackDB
    local AuraSharedBool = ctx.AuraSharedBool
    local SetAuraSharedBool = ctx.SetAuraSharedBool
    local AuraReadNumber = ctx.AuraReadNumber
    local AuraWriteNumber = ctx.AuraWriteNumber
    local AuraReadStackAnchor = ctx.AuraReadStackAnchor
    local AuraWriteStackAnchor = ctx.AuraWriteStackAnchor
    local AuraLaneShown = ctx.AuraLaneShown
    local SetAuraLaneShown = ctx.SetAuraLaneShown
    local AURA_ANCHOR_VALUES = ctx.AURA_ANCHOR_VALUES or {}

    if not (Registry and type(Registry.RegisterSetting) == "function") then return nil end
    if type(AuraScopeLabel) ~= "function" or type(AuraModel) ~= "function" then return nil end
    if type(ApplyAura) ~= "function" or type(ApplyAuraText) ~= "function" then return nil end
    if type(EnsureAuraFallbackDB) ~= "function" then return nil end
    if type(AuraSharedBool) ~= "function" or type(SetAuraSharedBool) ~= "function" then return nil end
    if type(AuraReadNumber) ~= "function" or type(AuraWriteNumber) ~= "function" then return nil end
    if type(AuraReadStackAnchor) ~= "function" or type(AuraWriteStackAnchor) ~= "function" then return nil end
    if type(AuraLaneShown) ~= "function" or type(SetAuraLaneShown) ~= "function" then return nil end

    local BuildUnitLaneRegistrationHelpers = A.AurasRegistry and A.AurasRegistry.BuildUnitLaneRegistrationHelpers
    local UnitLaneRegistrationHelpers = type(BuildUnitLaneRegistrationHelpers) == "function" and BuildUnitLaneRegistrationHelpers({
        Registry = Registry,
        UNIT_LABELS = UNIT_LABELS,
        ApplyAura = ApplyAura,
        AuraLaneShown = AuraLaneShown,
        SetAuraLaneShown = SetAuraLaneShown,
    }) or nil
    if type(UnitLaneRegistrationHelpers) ~= "table" then return nil end
    local RegisterAuraUnitLaneBoolean = UnitLaneRegistrationHelpers.RegisterAuraUnitLaneBoolean
    local RegisterAuraUnitLaneNumber = UnitLaneRegistrationHelpers.RegisterAuraUnitLaneNumber
    local RegisterAuraUnitLaneEnum = UnitLaneRegistrationHelpers.RegisterAuraUnitLaneEnum

    local function ApplyAuraScope(scope, applyText)
        if applyText then ApplyAuraText("MSUF_ASSISTANT_AURA_TEXT") else ApplyAura(scope, "MSUF_ASSISTANT_AURAS") end
    end

    local BuildScopeRegistrationHelpers = A.AurasRegistry and A.AurasRegistry.BuildScopeRegistrationHelpers
    local ScopeRegistrationHelpers = type(BuildScopeRegistrationHelpers) == "function" and BuildScopeRegistrationHelpers({
        Registry = Registry,
        AuraScopeLabel = AuraScopeLabel,
        AuraSharedBool = AuraSharedBool,
        SetAuraSharedBool = SetAuraSharedBool,
        AuraReadNumber = AuraReadNumber,
        AuraWriteNumber = AuraWriteNumber,
        ApplyAuraScope = ApplyAuraScope,
    }) or nil
    if type(ScopeRegistrationHelpers) ~= "table" then return nil end

    local RegisterAuraScopeLaneBoolean = ScopeRegistrationHelpers.RegisterAuraScopeLaneBoolean
    local RegisterAuraScopeLaneNumber = ScopeRegistrationHelpers.RegisterAuraScopeLaneNumber
    local RegisterAuraScopeLaneEnum = ScopeRegistrationHelpers.RegisterAuraScopeLaneEnum
    local RegisterAuraScopeBoolean = ScopeRegistrationHelpers.RegisterAuraScopeBoolean
    local RegisterAuraScopeNumber = ScopeRegistrationHelpers.RegisterAuraScopeNumber
    local RegisterAuraScopeEnum = ScopeRegistrationHelpers.RegisterAuraScopeEnum
    if type(RegisterAuraScopeLaneBoolean) ~= "function" then return nil end
    if type(RegisterAuraScopeLaneNumber) ~= "function" then return nil end
    if type(RegisterAuraScopeLaneEnum) ~= "function" then return nil end
    if type(RegisterAuraScopeBoolean) ~= "function" then return nil end
    if type(RegisterAuraScopeNumber) ~= "function" then return nil end
    if type(RegisterAuraScopeEnum) ~= "function" then return nil end

    local BuildLaneRegistrationHelpers = A.AurasRegistry and A.AurasRegistry.BuildLaneRegistrationHelpers
    local LaneRegistrationHelpers = type(BuildLaneRegistrationHelpers) == "function" and BuildLaneRegistrationHelpers({
        AuraModel = AuraModel,
        EnsureAuraFallbackDB = EnsureAuraFallbackDB,
        AuraSharedBool = AuraSharedBool,
        SetAuraSharedBool = SetAuraSharedBool,
        AuraReadNumber = AuraReadNumber,
        AuraWriteNumber = AuraWriteNumber,
        AuraReadStackAnchor = AuraReadStackAnchor,
        AuraWriteStackAnchor = AuraWriteStackAnchor,
        AURA_ANCHOR_VALUES = AURA_ANCHOR_VALUES,
    }) or nil
    if type(LaneRegistrationHelpers) ~= "table" then return nil end

    local AuraReadValue = LaneRegistrationHelpers.AuraReadValue
    local AuraWriteValue = LaneRegistrationHelpers.AuraWriteValue
    local AuraLaneKey = LaneRegistrationHelpers.AuraLaneKey
    local AuraReadLaneAnchor = LaneRegistrationHelpers.AuraReadLaneAnchor
    local AuraWriteLaneAnchor = LaneRegistrationHelpers.AuraWriteLaneAnchor
    local AuraReadLaneLayer = LaneRegistrationHelpers.AuraReadLaneLayer
    local AuraWriteLaneLayer = LaneRegistrationHelpers.AuraWriteLaneLayer
    local AuraReadLaneGrowthPair = LaneRegistrationHelpers.AuraReadLaneGrowthPair
    local AuraWriteLaneGrowthPair = LaneRegistrationHelpers.AuraWriteLaneGrowthPair
    local AuraReadLaneStyleBool = LaneRegistrationHelpers.AuraReadLaneStyleBool
    local AuraWriteLaneStyleBool = LaneRegistrationHelpers.AuraWriteLaneStyleBool
    local AuraReadLaneStyleNumber = LaneRegistrationHelpers.AuraReadLaneStyleNumber
    local AuraWriteLaneStyleNumber = LaneRegistrationHelpers.AuraWriteLaneStyleNumber
    local AuraReadLaneStackAnchor = LaneRegistrationHelpers.AuraReadLaneStackAnchor
    local AuraWriteLaneStackAnchor = LaneRegistrationHelpers.AuraWriteLaneStackAnchor

    return {
        RegisterAuraUnitLaneBoolean = RegisterAuraUnitLaneBoolean,
        RegisterAuraUnitLaneNumber = RegisterAuraUnitLaneNumber,
        RegisterAuraUnitLaneEnum = RegisterAuraUnitLaneEnum,
        RegisterAuraScopeLaneBoolean = RegisterAuraScopeLaneBoolean,
        RegisterAuraScopeLaneNumber = RegisterAuraScopeLaneNumber,
        RegisterAuraScopeLaneEnum = RegisterAuraScopeLaneEnum,
        RegisterAuraScopeBoolean = RegisterAuraScopeBoolean,
        RegisterAuraScopeNumber = RegisterAuraScopeNumber,
        RegisterAuraScopeEnum = RegisterAuraScopeEnum,
        AuraReadValue = AuraReadValue,
        AuraWriteValue = AuraWriteValue,
        AuraLaneKey = AuraLaneKey,
        AuraReadLaneAnchor = AuraReadLaneAnchor,
        AuraWriteLaneAnchor = AuraWriteLaneAnchor,
        AuraReadLaneLayer = AuraReadLaneLayer,
        AuraWriteLaneLayer = AuraWriteLaneLayer,
        AuraReadLaneGrowthPair = AuraReadLaneGrowthPair,
        AuraWriteLaneGrowthPair = AuraWriteLaneGrowthPair,
        AuraReadLaneStyleBool = AuraReadLaneStyleBool,
        AuraWriteLaneStyleBool = AuraWriteLaneStyleBool,
        AuraReadLaneStyleNumber = AuraReadLaneStyleNumber,
        AuraWriteLaneStyleNumber = AuraWriteLaneStyleNumber,
        AuraReadLaneStackAnchor = AuraReadLaneStackAnchor,
        AuraWriteLaneStackAnchor = AuraWriteLaneStackAnchor,
    }
end
