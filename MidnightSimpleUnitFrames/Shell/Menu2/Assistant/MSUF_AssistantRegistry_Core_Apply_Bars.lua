-- Assistant registry core bar and border apply helpers.
-- Loaded before MSUF_AssistantRegistry_Core_Apply.lua; consumed by the apply helper builder.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.RegistryCoreBuilders = A.RegistryCoreBuilders or {}

function A.RegistryCoreBuilders.BuildBarApplyHelpers(ctx)
    ctx = type(ctx) == "table" and ctx or {}

    local CallGlobal = ctx.CallGlobal
    local ApplyGeneral = ctx.ApplyGeneral
    local ApplyColors = ctx.ApplyColors
    local MSUFRef = ctx.MSUF or MSUF
    if type(CallGlobal) ~= "function" or type(ApplyGeneral) ~= "function" then return nil end
    if type(ApplyColors) ~= "function" then return nil end
    local ApplyService = _G.MSUF_Menu2_ApplyService

    local function RequestBars(reason)
        if ApplyService and type(ApplyService.RequestBars) == "function" then
            return ApplyService.RequestBars(reason)
        end
        return ApplyGeneral(reason or "MSUF_ASSISTANT_BARS", { preview = true, applyAll = false, bars = true })
    end

    local function ApplyBars(reason)
        RequestBars(reason or "MSUF_ASSISTANT_BARS")
    end

    local function ApplyBarGradients(reason)
        ApplyGeneral(reason or "MSUF_ASSISTANT_BAR_GRADIENT", { preview = true, applyAll = false, notify = false, bars = true })
        CallGlobal("MSUF_UpdateAllBarGradients")
    end

    local function ApplyBarOutline(reason)
        ApplyBars(reason or "MSUF_ASSISTANT_BAR_OUTLINE")
        CallGlobal("MSUF_ApplyBarOutlineThickness_All")
        CallGlobal("MSUF_GF_RefreshOutlineGeometry")
        CallGlobal("MSUF_ApplyRoundedUnitframes")
    end

    local function ApplyRoundedBars(reason)
        ApplyBars(reason or "MSUF_ASSISTANT_ROUNDED_BARS")
        CallGlobal("MSUF_ApplyRoundedUnitframes")
        CallGlobal("MSUF_GF_RefreshPreviewLayout", "party")
        CallGlobal("MSUF_GF_RefreshPreviewLayout", "raid")
        CallGlobal("MSUF_GF_RefreshPreviewLayout", "mythicraid")
        CallGlobal("MSUF_GF_RefreshPreviewBox")
    end

    local function ApplyAggroBorder(reason)
        ApplyBars(reason or "MSUF_ASSISTANT_AGGRO_BORDER")
        CallGlobal("MSUF_UFCore_RefreshSettingsCache", "MSUF_ASSISTANT_AGGRO_BORDER")
        CallGlobal("MSUF_ApplyBarOutlineThickness_All")
        CallGlobal("MSUF_AggroOutline_ApplyEventRegistration")
    end

    local function ApplyDispelPurgeBorder(reason)
        ApplyBars(reason or "MSUF_ASSISTANT_DISPEL_PURGE_BORDER")
        CallGlobal("MSUF_UFCore_RefreshSettingsCache", "MSUF_ASSISTANT_DISPEL_PURGE_BORDER")
        CallGlobal("MSUF_ApplyBarOutlineThickness_All")
        CallGlobal("MSUF_DispelOutline_ApplyEventRegistration")
        CallGlobal("MSUF_RefreshDispelOutlineStates", true)
        CallGlobal("MSUF_RefreshUnitDispelOverlays")
    end

    local function ApplyBossTargetBorder(reason)
        ApplyBars(reason or "MSUF_ASSISTANT_BOSS_TARGET_BORDER")
        CallGlobal("MSUF_UFCore_RefreshSettingsCache", "MSUF_ASSISTANT_BOSS_TARGET_BORDER")
        local UF = MSUFRef and MSUFRef.UF
        if UF and type(UF.ForceUpdate) == "function" then UF.ForceUpdate(nil) end
    end

    local function ApplyHighlightBorders(reason)
        ApplyAggroBorder(reason or "MSUF_ASSISTANT_HIGHLIGHT_BORDERS")
        ApplyDispelPurgeBorder(reason or "MSUF_ASSISTANT_HIGHLIGHT_BORDERS")
        ApplyBossTargetBorder(reason or "MSUF_ASSISTANT_HIGHLIGHT_BORDERS")
    end

    local function ApplyAbsorbBars(reason)
        ApplyBars(reason or "MSUF_ASSISTANT_ABSORB_BARS")
    end

    return {
        ApplyBars = ApplyBars,
        ApplyBarGradients = ApplyBarGradients,
        ApplyBarOutline = ApplyBarOutline,
        ApplyRoundedBars = ApplyRoundedBars,
        ApplyAggroBorder = ApplyAggroBorder,
        ApplyDispelPurgeBorder = ApplyDispelPurgeBorder,
        ApplyBossTargetBorder = ApplyBossTargetBorder,
        ApplyHighlightBorders = ApplyHighlightBorders,
        ApplyAbsorbBars = ApplyAbsorbBars,
    }
end
