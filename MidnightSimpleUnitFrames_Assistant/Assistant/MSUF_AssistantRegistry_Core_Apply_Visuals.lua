-- Assistant registry visual/color apply helper builder.
-- Loaded before MSUF_AssistantRegistry_Core_Apply.lua; consumed by the apply helper builder.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.RegistryCoreBuilders = A.RegistryCoreBuilders or {}

function A.RegistryCoreBuilders.BuildVisualApplyHelpers(ctx)
    ctx = type(ctx) == "table" and ctx or {}

    local MRef = ctx.M or M
    local MSUFRef = ctx.MSUF or MSUF
    local CallGlobal = ctx.CallGlobal
    local ApplyGeneral = ctx.ApplyGeneral
    local ApplyAura = ctx.ApplyAura
    if type(CallGlobal) ~= "function" or type(ApplyGeneral) ~= "function" then return nil end

    local function CurrentApplyService()
        return (MRef and MRef.ApplyService) or (M and M.ApplyService) or _G.MSUF_Menu2_ApplyService
    end

    local function PushVisualUpdates()
        local api = MSUFRef and MSUFRef._colorsAPI
        if api and type(api.PushVisualUpdates) == "function" then
            api.PushVisualUpdates()
            return true
        end
        return false
    end

    local function RequestVisuals(reason)
        local ApplyService = CurrentApplyService()
        if ApplyService and type(ApplyService.RequestVisuals) == "function" then
            return ApplyService.RequestVisuals(reason)
        end
        return ApplyGeneral(reason or "MSUF_ASSISTANT_VISUALS", { preview = true, applyAll = false, fonts = true })
    end

    local function RequestColors(reason, scope)
        local ApplyService = CurrentApplyService()
        if ApplyService and type(ApplyService.RequestColors) == "function" then
            return ApplyService.RequestColors(reason, scope)
        end
        if not scope and PushVisualUpdates() then return true end
        return ApplyGeneral(reason or "MSUF_ASSISTANT_COLORS", { preview = true, applyAll = false, colors = true, colorScope = scope })
    end

    local function RequestFonts(reason, scope)
        local ApplyService = CurrentApplyService()
        if ApplyService and type(ApplyService.RequestFonts) == "function" then
            return ApplyService.RequestFonts(reason, scope)
        end
        return ApplyGeneral(reason or "MSUF_ASSISTANT_FONTS", { preview = true, applyAll = false, fonts = true, fontScope = scope })
    end

    local function RequestCastbars(reason, unit)
        local ApplyService = CurrentApplyService()
        if ApplyService and type(ApplyService.RequestCastbars) == "function" then
            return ApplyService.RequestCastbars(reason, "assistant", unit)
        end
        if unit then
            if CallGlobal("MSUF_ApplyCastbarUnitAndSync", unit) then return true end
            if CallGlobal("MSUF_ApplyCastbarVisualsForUnit", unit) then return true end
        end
        return ApplyGeneral(reason or "MSUF_ASSISTANT_CASTBAR_COLORS", {
            castbar = true,
            castbarTextures = true,
            preview = true,
            applyAll = false,
        })
    end

    local function ApplyVisuals(reason)
        RequestVisuals(reason or "MSUF_ASSISTANT_VISUALS")
    end

    local function ApplyColors(reason)
        reason = reason or "MSUF_ASSISTANT_COLORS"
        RequestColors(reason)
    end

    local function ApplyCastbarColors(reason, unit)
        reason = reason or "MSUF_ASSISTANT_CASTBAR_COLORS"
        if unit then
            return RequestCastbars(reason, unit)
        end
        return RequestCastbars(reason, unit)
    end

    local function ApplyGameplayColors(reason)
        RequestColors(reason or "MSUF_ASSISTANT_GAMEPLAY_COLORS")
    end

    local function ApplyClassPowerColors(reason)
        reason = reason or "MSUF_ASSISTANT_CLASS_POWER_COLORS"
        local ApplyService = CurrentApplyService()
        if ApplyService and type(ApplyService.RequestClassPower) == "function" then
            return ApplyService.RequestClassPower(reason, { colors = true, playerHP = true }, { preview = true, applyAll = false, colors = true, colorScope = "player" })
        end
        RequestColors(reason, "player")
        CallGlobal("MSUF_ClassPower_InvalidateColors")
    end

    local function ApplyAuraColors(reason)
        reason = reason or "MSUF_ASSISTANT_AURA_COLORS"
        RequestColors(reason or "MSUF_ASSISTANT_AURA_COLORS")
        CallGlobal("MSUF_GF_InvalidateCooldownTextCurve")
        CallGlobal("MSUF_GF_ForceCooldownTextRecolor")
        -- Aura timer bucket coloring is baked into native button setup. Queue one
        -- visual-generation bump and container refresh after color apply.
        local apply = CurrentApplyService()
        if apply and type(apply.RequestAuraFonts) == "function" then
            apply.RequestAuraFonts("shared", reason)
        elseif type(ApplyAura) == "function" then
            ApplyAura("shared", reason)
        end
        CallGlobal("MSUF_GF_ForceAuraTextColorRefresh")
    end

    local function ApplyPortraitColors(reason)
        reason = reason or "MSUF_ASSISTANT_PORTRAIT_COLORS"
        local ApplyService = CurrentApplyService()
        if ApplyService and type(ApplyService.RequestGeneral) == "function" then
            return ApplyService.RequestGeneral(reason, { preview = true, applyAll = true, colors = true })
        end
        CallGlobal("MSUF_UFCore_NotifyConfigChanged", nil, true, true, reason)
        return CallGlobal("MSUF_UFPreview_RequestRefresh", reason)
    end

    local function ApplyFonts(reason, scope)
        RequestFonts(reason or "MSUF_ASSISTANT_FONTS", scope)
    end

    return {
        ApplyVisuals = ApplyVisuals,
        ApplyColors = ApplyColors,
        ApplyCastbarColors = ApplyCastbarColors,
        ApplyGameplayColors = ApplyGameplayColors,
        ApplyClassPowerColors = ApplyClassPowerColors,
        ApplyAuraColors = ApplyAuraColors,
        ApplyPortraitColors = ApplyPortraitColors,
        ApplyFonts = ApplyFonts,
    }
end
