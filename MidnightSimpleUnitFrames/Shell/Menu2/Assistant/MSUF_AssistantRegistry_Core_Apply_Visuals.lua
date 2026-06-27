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
    local ApplyService = (MRef and MRef.ApplyService) or _G.MSUF_Menu2_ApplyService

    local function PushVisualUpdates()
        local api = MSUFRef and MSUFRef._colorsAPI
        if api and type(api.PushVisualUpdates) == "function" then api.PushVisualUpdates() end
    end

    local function RequestVisuals(reason)
        if ApplyService and type(ApplyService.RequestVisuals) == "function" then
            return ApplyService.RequestVisuals(reason)
        end
        PushVisualUpdates()
        return ApplyGeneral(reason or "MSUF_ASSISTANT_VISUALS", { preview = true, applyAll = false, fonts = true, bars = true })
    end

    local function RequestColors(reason)
        if ApplyService and type(ApplyService.RequestColors) == "function" then
            return ApplyService.RequestColors(reason)
        end
        PushVisualUpdates()
        return ApplyGeneral(reason or "MSUF_ASSISTANT_COLORS", { preview = true, applyAll = false, fonts = true, bars = true, colors = true })
    end

    local function RequestFonts(reason)
        if ApplyService and type(ApplyService.RequestFonts) == "function" then
            return ApplyService.RequestFonts(reason)
        end
        return ApplyGeneral(reason or "MSUF_ASSISTANT_FONTS", { preview = true, applyAll = false, fonts = true })
    end

    local function RequestCastbars(reason)
        if ApplyService and type(ApplyService.RequestCastbars) == "function" then
            return ApplyService.RequestCastbars(reason, "assistant")
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

    local function ApplyCastbarColors(reason)
        reason = reason or "MSUF_ASSISTANT_CASTBAR_COLORS"
        RequestColors(reason)
        RequestCastbars(reason)
    end

    local function ApplyGameplayColors(reason)
        RequestColors(reason or "MSUF_ASSISTANT_GAMEPLAY_COLORS")
    end

    local function ApplyClassPowerColors(reason)
        RequestColors(reason or "MSUF_ASSISTANT_CLASS_POWER_COLORS")
        CallGlobal("MSUF_ClassPower_InvalidateColors")
        CallGlobal("MSUF_ClassPower_Refresh")
        CallGlobal("MSUF_ClassPower_RefreshTextures")
    end

    local function ApplyAuraColors(reason)
        ApplyAura("shared", reason or "MSUF_ASSISTANT_AURA_COLORS")
        RequestColors(reason or "MSUF_ASSISTANT_AURA_COLORS")
        CallGlobal("MSUF_GF_InvalidateCooldownTextCurve")
        CallGlobal("MSUF_GF_ForceCooldownTextRecolor")
        -- Aura timer bucket coloring is baked into a C-side formatter at button-create
        -- time; ApplyFontsFromGlobal bumps the native visual generation so lanes
        -- recreate and pick up new colors/thresholds (a plain RefreshAll reuses lanes).
        local a3 = MSUF and MSUF.MSUF_Auras3
        if a3 and type(a3.ApplyFontsFromGlobal) == "function" then
            a3.ApplyFontsFromGlobal()
        elseif a3 and type(a3.RefreshAll) == "function" then
            a3.RefreshAll()
        end
        CallGlobal("MSUF_GF_ForceAuraTextColorRefresh")
    end

    local function ApplyPortraitColors(reason)
        RequestColors(reason or "MSUF_ASSISTANT_PORTRAIT_COLORS")
        CallGlobal("MSUF_UFCore_NotifyConfigChanged", nil, true, true, reason or "MSUF_ASSISTANT_PORTRAIT_COLORS")
        CallGlobal("MSUF_UFPreview_RequestRefresh", reason or "MSUF_ASSISTANT_PORTRAIT_COLORS")
    end

    local function ApplyFonts(reason)
        RequestFonts(reason or "MSUF_ASSISTANT_FONTS")
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
