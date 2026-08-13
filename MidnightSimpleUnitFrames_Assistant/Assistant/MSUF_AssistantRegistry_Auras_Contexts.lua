-- Assistant Auras context exports.
-- Keeps downstream group/action context tables out of the main Auras registry wiring file.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.InstallContexts(ctx)
    if type(ctx) ~= "table" then return end

    A.AurasRegistry.GroupSettings = {
        Registry = ctx.Registry,
        A = ctx.A or A,
        UNIT_LABELS = ctx.UNIT_LABELS,
        UNIT_ALIASES = ctx.UNIT_ALIASES,
        AddAliasesForUnit = ctx.AddAliasesForUnit,
        AuraModel = ctx.AuraModel,
        GFAurasRoot = ctx.GFAurasRoot,
        GFAuraGroup = ctx.GFAuraGroup,
        GFAuraLaneShown = ctx.GFAuraLaneShown,
        SetGFAuraLaneShown = ctx.SetGFAuraLaneShown,
        GFReadAuraNumber = ctx.GFReadAuraNumber,
        GFWriteAuraNumber = ctx.GFWriteAuraNumber,
        GFReadAuraValue = ctx.GFReadAuraValue,
        GFWriteAuraValue = ctx.GFWriteAuraValue,
        GFReadConfValue = ctx.GFReadConfValue,
        GFWriteConfValue = ctx.GFWriteConfValue,
        ApplyGroup = ctx.ApplyGroup,
        AURA_LANES = ctx.AURA_LANES,
        AURA_RELATIVE_SIZE_NOUNS = ctx.AURA_RELATIVE_SIZE_NOUNS,
    }

    A.AurasRegistry.Actions = {
        Registry = ctx.Registry,
        M = ctx.M or M,
        A = ctx.A or A,
        AuraScopeFromArg = ctx.AuraScopeFromArg,
        AuraScopeLabel = ctx.AuraScopeLabel,
        AuraModel = ctx.AuraModel,
        ApplyAura = ctx.ApplyAura,
    }
end
