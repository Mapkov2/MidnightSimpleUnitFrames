-- Assistant registry core apply helper builder.
-- Loaded before MSUF_AssistantRegistry_Core.lua; keeps cold-path apply callbacks isolated.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.RegistryCoreBuilders = A.RegistryCoreBuilders or {}

function A.RegistryCoreBuilders.BuildApplyHelpers(ctx)
    ctx = type(ctx) == "table" and ctx or {}

    local MRef = ctx.M or M
    local MSUFRef = ctx.MSUF or MSUF
    local EnsureDB = ctx.EnsureDB
    local CallGlobal = ctx.CallGlobal
    if type(EnsureDB) ~= "function" or type(CallGlobal) ~= "function" then return nil end

    local function CurrentApplyService()
        return (MRef and MRef.ApplyService) or _G.MSUF_Menu2_ApplyService
    end

    local function ApplyUnit(unit, reason, opts)
        reason = reason or "MSUF_ASSISTANT_UNIT"
        opts = opts or { preview = true }
        if MRef and type(MRef.RequestUnitApply) == "function" then
            return MRef.RequestUnitApply(unit, reason, opts)
        end
        local apply = CurrentApplyService()
        if apply and type(apply.RequestUnit) == "function" then
            return apply.RequestUnit(unit, reason, opts)
        end
        if type(_G.MSUF_UFCore_NotifyConfigChanged) == "function" then
            _G.MSUF_UFCore_NotifyConfigChanged(unit, true, true, reason)
            return true
        end
        return false
    end

    local function ApplyGeneral(reason, opts)
        reason = reason or "MSUF_ASSISTANT_GENERAL"
        opts = opts or { preview = true }
        if MRef and type(MRef.RequestGeneralApply) == "function" then
            return MRef.RequestGeneralApply(reason, opts)
        end
        local apply = CurrentApplyService()
        if apply and type(apply.RequestGeneral) == "function" then
            return apply.RequestGeneral(reason, opts)
        end
        return false
    end

    local ApplyAura, ApplyAuraText, AuraModel, EnsureAuraFallbackDB

    local BuildVisualApplyHelpers = A.RegistryCoreBuilders and A.RegistryCoreBuilders.BuildVisualApplyHelpers
    local VisualApplyHelpers = type(BuildVisualApplyHelpers) == "function" and BuildVisualApplyHelpers({
        M = MRef,
        MSUF = MSUFRef,
        CallGlobal = CallGlobal,
        ApplyGeneral = ApplyGeneral,
        ApplyAura = function(scope, reason) return ApplyAura(scope, reason) end,
    }) or nil
    if type(VisualApplyHelpers) ~= "table" then return nil end
    local ApplyVisuals = VisualApplyHelpers.ApplyVisuals
    local ApplyColors = VisualApplyHelpers.ApplyColors
    local ApplyCastbarColors = VisualApplyHelpers.ApplyCastbarColors
    local ApplyGameplayColors = VisualApplyHelpers.ApplyGameplayColors
    local ApplyClassPowerColors = VisualApplyHelpers.ApplyClassPowerColors
    local ApplyAuraColors = VisualApplyHelpers.ApplyAuraColors
    local ApplyPortraitColors = VisualApplyHelpers.ApplyPortraitColors
    local ApplyFonts = VisualApplyHelpers.ApplyFonts
    if type(ApplyVisuals) ~= "function" or type(ApplyColors) ~= "function" or type(ApplyFonts) ~= "function" then return nil end

    local BuildBarApplyHelpers = A.RegistryCoreBuilders and A.RegistryCoreBuilders.BuildBarApplyHelpers
    local BarApplyHelpers = type(BuildBarApplyHelpers) == "function" and BuildBarApplyHelpers({
        MSUF = MSUFRef,
        CallGlobal = CallGlobal,
        ApplyGeneral = ApplyGeneral,
        ApplyColors = ApplyColors,
    }) or nil
    if type(BarApplyHelpers) ~= "table" then return nil end
    local ApplyBars = BarApplyHelpers.ApplyBars
    local ApplyBarGradients = BarApplyHelpers.ApplyBarGradients
    local ApplyBarOutline = BarApplyHelpers.ApplyBarOutline
    local ApplyRoundedBars = BarApplyHelpers.ApplyRoundedBars
    local ApplyAggroBorder = BarApplyHelpers.ApplyAggroBorder
    local ApplyDispelPurgeBorder = BarApplyHelpers.ApplyDispelPurgeBorder
    local ApplyBossTargetBorder = BarApplyHelpers.ApplyBossTargetBorder
    local ApplyHighlightBorders = BarApplyHelpers.ApplyHighlightBorders
    local ApplyAbsorbBars = BarApplyHelpers.ApplyAbsorbBars
    if type(ApplyBars) ~= "function" or type(ApplyBarOutline) ~= "function" or type(ApplyHighlightBorders) ~= "function" then return nil end

    local BuildDomainApplyHelpers = A.RegistryCoreBuilders and A.RegistryCoreBuilders.BuildDomainApplyHelpers
    local DomainApplyHelpers = type(BuildDomainApplyHelpers) == "function" and BuildDomainApplyHelpers({
        M = MRef,
        MSUF = MSUFRef,
        CallGlobal = CallGlobal,
        ApplyGeneral = ApplyGeneral,
    }) or nil
    if type(DomainApplyHelpers) ~= "table" then return nil end
    local ApplyClassPower = DomainApplyHelpers.ApplyClassPower
    local ApplyDetachedPowerBar = DomainApplyHelpers.ApplyDetachedPowerBar
    local ApplyDetachedPowerBarOutline = DomainApplyHelpers.ApplyDetachedPowerBarOutline
    local ApplyGameplay = DomainApplyHelpers.ApplyGameplay
    local ApplyCastbar = DomainApplyHelpers.ApplyCastbar

    local BuildGroupApplyHelper = A.RegistryCoreBuilders and A.RegistryCoreBuilders.BuildGroupApplyHelper
    local ApplyGroup = type(BuildGroupApplyHelper) == "function" and BuildGroupApplyHelper({
        M = MRef,
        MSUF = MSUFRef,
    }) or nil
    if type(ApplyGroup) ~= "function" then return nil end

    local BuildAuraApplyHelpers = A.RegistryCoreBuilders and A.RegistryCoreBuilders.BuildAuraApplyHelpers
    local AuraApplyHelpers = type(BuildAuraApplyHelpers) == "function" and BuildAuraApplyHelpers({
        M = MRef,
        MSUF = MSUFRef,
        EnsureDB = EnsureDB,
        CallGlobal = CallGlobal,
        ApplyGroup = ApplyGroup,
    }) or nil
    if type(AuraApplyHelpers) ~= "table" then return nil end
    AuraModel = AuraApplyHelpers.AuraModel
    ApplyAura = AuraApplyHelpers.ApplyAura
    ApplyAuraText = AuraApplyHelpers.ApplyAuraText
    EnsureAuraFallbackDB = AuraApplyHelpers.EnsureAuraFallbackDB

    return {
        ApplyUnit = ApplyUnit,
        ApplyGeneral = ApplyGeneral,
        ApplyVisuals = ApplyVisuals,
        ApplyColors = ApplyColors,
        ApplyCastbarColors = ApplyCastbarColors,
        ApplyGameplayColors = ApplyGameplayColors,
        ApplyClassPowerColors = ApplyClassPowerColors,
        ApplyAuraColors = ApplyAuraColors,
        ApplyPortraitColors = ApplyPortraitColors,
        ApplyFonts = ApplyFonts,
        ApplyBars = ApplyBars,
        ApplyBarGradients = ApplyBarGradients,
        ApplyBarOutline = ApplyBarOutline,
        ApplyRoundedBars = ApplyRoundedBars,
        ApplyAggroBorder = ApplyAggroBorder,
        ApplyDispelPurgeBorder = ApplyDispelPurgeBorder,
        ApplyBossTargetBorder = ApplyBossTargetBorder,
        ApplyHighlightBorders = ApplyHighlightBorders,
        ApplyAbsorbBars = ApplyAbsorbBars,
        ApplyClassPower = ApplyClassPower,
        ApplyDetachedPowerBar = ApplyDetachedPowerBar,
        ApplyDetachedPowerBarOutline = ApplyDetachedPowerBarOutline,
        ApplyGameplay = ApplyGameplay,
        ApplyCastbar = ApplyCastbar,
        ApplyGroup = ApplyGroup,
        AuraModel = AuraModel,
        ApplyAura = ApplyAura,
        ApplyAuraText = ApplyAuraText,
        EnsureAuraFallbackDB = EnsureAuraFallbackDB,
    }
end
