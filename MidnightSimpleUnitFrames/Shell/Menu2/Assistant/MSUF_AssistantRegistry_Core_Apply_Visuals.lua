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

    local function ApplyVisuals(reason)
        local api = MSUFRef and MSUFRef._colorsAPI
        if api and type(api.PushVisualUpdates) == "function" then api.PushVisualUpdates() end
        ApplyGeneral(reason or "MSUF_ASSISTANT_VISUALS", { preview = true, applyAll = false })
        CallGlobal("MSUF_UpdateAllFonts_Immediate")
        CallGlobal("MSUF_UpdateAllFonts")
        CallGlobal("MSUF_UpdateAllBarTextures_Immediate")
        CallGlobal("MSUF_UpdateAllBarTextures")
        CallGlobal("MSUF_RefreshAllFrames")
        CallGlobal("MSUF_UFPreview_RequestRefresh", reason or "MSUF_ASSISTANT_VISUALS")
    end

    local function ApplyColors(reason)
        reason = reason or "MSUF_ASSISTANT_COLORS"
        ApplyVisuals(reason)
        CallGlobal("MSUF_RefreshAllIdentityColors")
        CallGlobal("MSUF_RefreshAllPowerTextColors")
        CallGlobal("MSUF_PrioRows_Reinit")
        local gf = MSUFRef and MSUFRef.GF
        if gf and type(gf.RefreshColors) == "function" then gf.RefreshColors() end
        if gf and type(gf.RefreshVisuals) == "function" then gf.RefreshVisuals() end
    end

    local function ApplyCastbarColors(reason)
        ApplyColors(reason or "MSUF_ASSISTANT_CASTBAR_COLORS")
        CallGlobal("MSUF_UpdateCastbarVisuals_Immediate")
        CallGlobal("MSUF_UpdateCastbarVisuals")
        local fn = MSUFRef and MSUFRef.MSUF_UpdateCastbarVisuals
        if type(fn) == "function" then fn() end
        fn = MSUFRef and MSUFRef.MSUF_UpdateCastbarTextures_Immediate
        if type(fn) == "function" then fn() end
    end

    local function ApplyGameplayColors(reason)
        ApplyColors(reason or "MSUF_ASSISTANT_GAMEPLAY_COLORS")
        if MSUFRef and type(MSUFRef.MSUF_ApplyGameplayVisuals) == "function" then
            MSUFRef.MSUF_ApplyGameplayVisuals()
        elseif MRef and type(MRef.ApplyGameplay) == "function" then
            MRef.ApplyGameplay()
        end
    end

    local function ApplyClassPowerColors(reason)
        ApplyColors(reason or "MSUF_ASSISTANT_CLASS_POWER_COLORS")
        CallGlobal("MSUF_ClassPower_InvalidateColors")
        CallGlobal("MSUF_ClassPower_Refresh")
        CallGlobal("MSUF_ClassPower_RefreshTextures")
    end

    local function ApplyAuraColors(reason)
        ApplyAura("shared", reason or "MSUF_ASSISTANT_AURA_COLORS")
        ApplyColors(reason or "MSUF_ASSISTANT_AURA_COLORS")
        CallGlobal("MSUF_GF_InvalidateCooldownTextCurve")
        CallGlobal("MSUF_GF_ForceCooldownTextRecolor")
        local a3 = MSUF and MSUF.MSUF_Auras3
        if a3 and type(a3.RefreshAll) == "function" then a3.RefreshAll() end
        CallGlobal("MSUF_GF_ForceAuraTextColorRefresh")
    end

    local function ApplyPortraitColors(reason)
        ApplyColors(reason or "MSUF_ASSISTANT_PORTRAIT_COLORS")
        CallGlobal("MSUF_UFCore_NotifyConfigChanged", nil, true, true, reason or "MSUF_ASSISTANT_PORTRAIT_COLORS")
        CallGlobal("MSUF_UFPreview_RequestRefresh", reason or "MSUF_ASSISTANT_PORTRAIT_COLORS")
    end

    local function ApplyFonts(reason)
        ApplyGeneral(reason or "MSUF_ASSISTANT_FONTS", { preview = true, applyAll = false })
        CallGlobal("MSUF_UpdateAllFonts_Immediate")
        CallGlobal("MSUF_UpdateAllFonts")
        CallGlobal("MSUF_UFPreview_RequestRefresh", reason or "MSUF_ASSISTANT_FONTS")
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
