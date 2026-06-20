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

    local function ApplyClassPower(reason)
        CallGlobal("MSUF_ClassPower_Refresh")
        CallGlobal("MSUF_ClassPower_RefreshTextures")
        CallGlobal("MSUF_ClassPower_RefreshCDMWidthBindings", true)
        ApplyGeneral(reason or "MSUF_ASSISTANT_CLASSPOWER", { preview = true, applyAll = false })
    end

    local function ApplyDetachedPowerBar(reason)
        CallGlobal("MSUF_DetachedPowerBar_RefreshTextures")
        CallGlobal("MSUF_ApplyPowerBarEmbedLayout_All")
        CallGlobal("MSUF_ClassPower_PlayerHP_Refresh")
        ApplyGeneral(reason or "MSUF_ASSISTANT_DETACHED_POWER_BAR", { preview = true, power = true, applyAll = false })
    end

    local function ApplyDetachedPowerBarOutline(reason)
        CallGlobal("MSUF_ApplyBarOutlineThickness_All")
        ApplyDetachedPowerBar(reason or "MSUF_ASSISTANT_DETACHED_POWER_BAR_OUTLINE")
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

    local function ApplyCastbar(reason)
        ApplyGeneral(reason or "MSUF_ASSISTANT_CASTBAR", { castbar = true, preview = true, applyAll = false })
        CallGlobal("MSUF_Castbars_OnSettingsChanged", "assistant")
        CallGlobal("MSUF_UpdateCastbarVisuals")
    end

    return {
        ApplyClassPower = ApplyClassPower,
        ApplyDetachedPowerBar = ApplyDetachedPowerBar,
        ApplyDetachedPowerBarOutline = ApplyDetachedPowerBarOutline,
        ApplyGameplay = ApplyGameplay,
        ApplyCastbar = ApplyCastbar,
    }
end
