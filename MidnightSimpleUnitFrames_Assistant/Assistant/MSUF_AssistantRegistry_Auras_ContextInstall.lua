-- Assistant Auras context install wiring.
-- Keeps downstream group/action context payload out of the main Auras registry file.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.InstallRuntimeContexts(ctx)
    if type(ctx) ~= "table" then return end

    local InstallAuraContexts = A.AurasRegistry and A.AurasRegistry.InstallContexts
    local C = ctx.C
    if type(InstallAuraContexts) ~= "function" or type(C) ~= "table" then return end

    local ARef = ctx.A or A
    local Data = ctx.AurasData or ARef.AurasRegistryData or {}
    InstallAuraContexts({
        Registry = ctx.Registry or C.Registry,
        M = ctx.M or M,
        A = ARef,
        UNIT_LABELS = ctx.UNIT_LABELS or C.UNIT_LABELS,
        UNIT_ALIASES = ctx.UNIT_ALIASES or C.UNIT_ALIASES,
        AddAliasesForUnit = ctx.AddAliasesForUnit or C.AddAliasesForUnit,
        AuraModel = ctx.AuraModel or C.AuraModel,
        ApplyAura = ctx.ApplyAura or C.ApplyAura,
        GFAurasRoot = ctx.GFAurasRoot or C.GFAurasRoot,
        GFAuraGroup = ctx.GFAuraGroup or C.GFAuraGroup,
        GFAuraLaneShown = ctx.GFAuraLaneShown or C.GFAuraLaneShown,
        SetGFAuraLaneShown = ctx.SetGFAuraLaneShown or C.SetGFAuraLaneShown,
        GFReadAuraNumber = ctx.GFReadAuraNumber or C.GFReadAuraNumber,
        GFWriteAuraNumber = ctx.GFWriteAuraNumber or C.GFWriteAuraNumber,
        GFReadAuraValue = ctx.GFReadAuraValue or C.GFReadAuraValue,
        GFWriteAuraValue = ctx.GFWriteAuraValue or C.GFWriteAuraValue,
        GFReadConfValue = ctx.GFReadConfValue or C.GFReadConfValue,
        GFWriteConfValue = ctx.GFWriteConfValue or C.GFWriteConfValue,
        ApplyGroup = ctx.ApplyGroup or C.ApplyGroup,
        AURA_LANES = ctx.AURA_LANES or Data.AURA_LANES,
        AURA_RELATIVE_SIZE_NOUNS = ctx.AURA_RELATIVE_SIZE_NOUNS or Data.AURA_RELATIVE_SIZE_NOUNS,
        AuraScopeFromArg = ctx.AuraScopeFromArg,
        AuraScopeLabel = ctx.AuraScopeLabel,
    })
end
