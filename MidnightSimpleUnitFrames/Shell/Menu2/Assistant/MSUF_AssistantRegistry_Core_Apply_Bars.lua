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
    local MRef = ctx.M or M
    if type(CallGlobal) ~= "function" or type(ApplyGeneral) ~= "function" then return nil end
    if type(ApplyColors) ~= "function" then return nil end

    local function CurrentApplyService()
        return (MRef and MRef.ApplyService) or (M and M.ApplyService) or _G.MSUF_Menu2_ApplyService
    end

    local function RequestBars(reason, scope)
        local ApplyService = CurrentApplyService()
        if ApplyService and type(ApplyService.RequestBars) == "function" then
            return ApplyService.RequestBars(reason, scope)
        end
        return ApplyGeneral(reason or "MSUF_ASSISTANT_BARS", { preview = true, applyAll = false, bars = true, barsScope = scope })
    end

    local function RequestBarGradients(reason, scope)
        local ApplyService = CurrentApplyService()
        if ApplyService and type(ApplyService.RequestBarGradients) == "function" then
            return ApplyService.RequestBarGradients(reason, scope)
        end
        if ApplyService and type(ApplyService.RequestGeneral) == "function" then
            return ApplyService.RequestGeneral(reason or "MSUF_ASSISTANT_BAR_GRADIENT", {
                preview = true,
                applyAll = false,
                notify = false,
                barGradients = true,
                barsScope = scope,
            })
        end
        ApplyGeneral(reason or "MSUF_ASSISTANT_BAR_GRADIENT", {
            preview = true,
            applyAll = false,
            notify = false,
            barGradients = true,
            barsScope = scope,
        })
        return CallGlobal("MSUF_UpdateAllBarGradients", scope)
    end

    local function ApplyBars(reason, scope)
        RequestBars(reason or "MSUF_ASSISTANT_BARS", scope)
    end

    local function ApplyBarGradients(reason, scope)
        RequestBarGradients(reason or "MSUF_ASSISTANT_BAR_GRADIENT", scope)
    end

    local function RefreshBossTargetBorderFallback(reason, scope)
        reason = reason or "MSUF_ASSISTANT_BOSS_TARGET_BORDER"
        ApplyGeneral(reason, { preview = true, applyAll = false, notify = false })
        CallGlobal("MSUF_UFCore_RefreshSettingsCache", reason)
        local refreshScope = tostring(scope or "")
        if refreshScope ~= "boss" and not refreshScope:match("^boss%d+$") then refreshScope = "boss" end
        local ApplyService = CurrentApplyService()
        if ApplyService and type(ApplyService.RequestUnit) == "function" then
            return ApplyService.RequestUnit(refreshScope, reason, { preview = true })
        end
        if type(_G.MSUF_UFCore_NotifyConfigChanged) == "function" then
            return _G.MSUF_UFCore_NotifyConfigChanged(refreshScope, true, true, reason)
        end
        return false
    end

    local function ApplyBarOutline(reason, scope)
        local ApplyService = CurrentApplyService()
        if ApplyService and type(ApplyService.RequestBarOutline) == "function" then
            return ApplyService.RequestBarOutline(reason or "MSUF_ASSISTANT_BAR_OUTLINE", scope)
        end
        ApplyBars(reason or "MSUF_ASSISTANT_BAR_OUTLINE", scope)
        CallGlobal("MSUF_ApplyBarOutlineThickness_All")
        CallGlobal("MSUF_GF_RefreshOutlineGeometry")
        CallGlobal("MSUF_ApplyRoundedUnitframes")
    end

    local function ApplyRoundedBars(reason, scope)
        local ApplyService = CurrentApplyService()
        if ApplyService and type(ApplyService.RequestRoundedBars) == "function" then
            return ApplyService.RequestRoundedBars(reason or "MSUF_ASSISTANT_ROUNDED_BARS", scope)
        end
        ApplyBars(reason or "MSUF_ASSISTANT_ROUNDED_BARS", scope)
        CallGlobal("MSUF_ApplyRoundedUnitframes")
        CallGlobal("MSUF_GF_RefreshPreviewLayout", "party")
        CallGlobal("MSUF_GF_RefreshPreviewLayout", "raid")
        CallGlobal("MSUF_GF_RefreshPreviewLayout", "mythicraid")
        CallGlobal("MSUF_GF_RefreshPreviewBox")
    end

    local function ApplyAggroBorder(reason, scope)
        local ApplyService = CurrentApplyService()
        if ApplyService and type(ApplyService.RequestAggroBorder) == "function" then
            return ApplyService.RequestAggroBorder(reason or "MSUF_ASSISTANT_AGGRO_BORDER", scope)
        end
        ApplyBars(reason or "MSUF_ASSISTANT_AGGRO_BORDER", scope)
        CallGlobal("MSUF_UFCore_RefreshSettingsCache", "MSUF_ASSISTANT_AGGRO_BORDER")
        CallGlobal("MSUF_ApplyBarOutlineThickness_All")
        CallGlobal("MSUF_AggroOutline_ApplyEventRegistration")
    end

    local function ApplyDispelPurgeBorder(reason, scope)
        local ApplyService = CurrentApplyService()
        if ApplyService and type(ApplyService.RequestDispelPurgeBorder) == "function" then
            return ApplyService.RequestDispelPurgeBorder(reason or "MSUF_ASSISTANT_DISPEL_PURGE_BORDER", scope)
        end
        ApplyBars(reason or "MSUF_ASSISTANT_DISPEL_PURGE_BORDER", scope)
        CallGlobal("MSUF_UFCore_RefreshSettingsCache", "MSUF_ASSISTANT_DISPEL_PURGE_BORDER")
        CallGlobal("MSUF_ApplyBarOutlineThickness_All")
        CallGlobal("MSUF_DispelOutline_ApplyEventRegistration")
        CallGlobal("MSUF_RefreshDispelOutlineStates", true)
        CallGlobal("MSUF_RefreshUnitDispelOverlays")
    end

    local function ApplyBossTargetBorder(reason, scope)
        local ApplyService = CurrentApplyService()
        if ApplyService and type(ApplyService.RequestBossTargetBorder) == "function" then
            return ApplyService.RequestBossTargetBorder(reason or "MSUF_ASSISTANT_BOSS_TARGET_BORDER", scope)
        end
        return RefreshBossTargetBorderFallback(reason or "MSUF_ASSISTANT_BOSS_TARGET_BORDER", scope)
    end

    local function ApplyHighlightBorders(reason, scope)
        local ApplyService = CurrentApplyService()
        if ApplyService and type(ApplyService.RequestHighlightBorders) == "function" then
            return ApplyService.RequestHighlightBorders(reason or "MSUF_ASSISTANT_HIGHLIGHT_BORDERS", scope)
        end
        ApplyAggroBorder(reason or "MSUF_ASSISTANT_HIGHLIGHT_BORDERS", scope)
        ApplyDispelPurgeBorder(reason or "MSUF_ASSISTANT_HIGHLIGHT_BORDERS", scope)
        RefreshBossTargetBorderFallback(reason or "MSUF_ASSISTANT_HIGHLIGHT_BORDERS", scope)
    end

    local function ApplyAbsorbBars(reason, scope)
        ApplyBars(reason or "MSUF_ASSISTANT_ABSORB_BARS", scope)
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
