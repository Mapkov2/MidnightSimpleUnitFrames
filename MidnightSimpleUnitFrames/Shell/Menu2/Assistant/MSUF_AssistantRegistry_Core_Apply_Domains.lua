-- Assistant registry core domain apply helpers.
-- Loaded after MSUF_AssistantRegistry_Core_Apply.lua; BuildApplyHelpers consumes this builder.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.RegistryCoreBuilders = A.RegistryCoreBuilders or {}

function A.RegistryCoreBuilders.BuildDomainApplyHelpers(ctx)
    ctx = type(ctx) == "table" and ctx or {}

    local MRef = ctx.M or M
    local MSUFRef = ctx.MSUF or MSUF
    local CallGlobal = ctx.CallGlobal
    local ApplyGeneral = ctx.ApplyGeneral
    if type(CallGlobal) ~= "function" or type(ApplyGeneral) ~= "function" then return nil end
    local function CurrentApplyService()
        return (MRef and MRef.ApplyService) or _G.MSUF_Menu2_ApplyService
    end

    local function ApplyClassPower(reason)
        local ApplyService = CurrentApplyService()
        if ApplyService and type(ApplyService.RequestClassPower) == "function" then
            return ApplyService.RequestClassPower(reason or "MSUF_ASSISTANT_CLASSPOWER", { full = true, cdm = true }, { preview = true, applyAll = false })
        end
        CallGlobal("MSUF_ClassPower_Apply", { full = true, cdm = true })
        return ApplyGeneral(reason or "MSUF_ASSISTANT_CLASSPOWER", { preview = true, applyAll = false })
    end

    local function ApplyPlayerPowerLayout()
        if CallGlobal("MSUF_ApplyPowerBarEmbedLayout_ForUnitKey", "player", true) then return true end
        return CallGlobal("MSUF_ApplyPowerBarEmbedLayout_All")
    end

    local function ApplyDetachedPowerBar(reason)
        local ApplyService = CurrentApplyService()
        reason = reason or "MSUF_ASSISTANT_DETACHED_POWER_BAR"
        local flags = { preview = true, power = true, detachedPowerBar = true, applyAll = false, unit = "player" }
        if ApplyService and type(ApplyService.RequestClassPower) == "function" then
            if type(ApplyService.RequestDetachedPowerBar) == "function" then
                return ApplyService.RequestDetachedPowerBar(reason, nil, flags)
            end
            return ApplyService.RequestClassPower(reason, { anchor = true, cdm = true, playerHP = true, syncNow = false }, flags)
        end
        CallGlobal("MSUF_DetachedPowerBar_RefreshTextures")
        ApplyPlayerPowerLayout()
        CallGlobal("MSUF_ClassPower_Apply", { playerHP = true })
        return ApplyGeneral(reason, { preview = true, power = true, applyAll = false })
    end

    local function ApplyDetachedPowerBarOutline(reason)
        reason = reason or "MSUF_ASSISTANT_DETACHED_POWER_BAR_OUTLINE"
        local ApplyService = CurrentApplyService()
        if ApplyService and type(ApplyService.RequestBarOutline) == "function" then
            ApplyService.RequestBarOutline(reason, "player")
        else
            CallGlobal("MSUF_ApplyBarOutlineThickness_All", "player")
        end
        ApplyDetachedPowerBar(reason)
    end

    local function ApplyGameplay(reason)
        if MSUFRef and type(MSUFRef.MSUF_RequestGameplayApply) == "function" then
            MSUFRef.MSUF_RequestGameplayApply(reason or "MSUF_ASSISTANT_GAMEPLAY")
        elseif MSUFRef and type(MSUFRef.MSUF_ApplyGameplayVisuals) == "function" then
            MSUFRef.MSUF_ApplyGameplayVisuals()
        elseif MRef and type(MRef.ApplyGameplay) == "function" then
            MRef.ApplyGameplay()
        end
    end

    local function ApplyCastbar(reason, unit)
        if ApplyService and type(ApplyService.RequestCastbars) == "function" then
            return ApplyService.RequestCastbars(reason or "MSUF_ASSISTANT_CASTBAR", "assistant", unit)
        end
        if unit then
            CallGlobal("MSUF_Castbars_OnSettingsChanged", "assistant")
            if CallGlobal("MSUF_ApplyCastbarUnitAndSync", unit) then return true end
            if CallGlobal("MSUF_ApplyCastbarVisualsForUnit", unit) then return true end
        end
        ApplyGeneral(reason or "MSUF_ASSISTANT_CASTBAR", { castbar = true, castbarTextures = true, preview = true, applyAll = false })
        CallGlobal("MSUF_Castbars_OnSettingsChanged", "assistant")
    end

    return {
        ApplyClassPower = ApplyClassPower,
        ApplyDetachedPowerBar = ApplyDetachedPowerBar,
        ApplyDetachedPowerBarOutline = ApplyDetachedPowerBarOutline,
        ApplyGameplay = ApplyGameplay,
        ApplyCastbar = ApplyCastbar,
    }
end
