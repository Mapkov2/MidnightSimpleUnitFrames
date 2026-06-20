-- Assistant registry core aura apply helpers.
-- Loaded before MSUF_AssistantRegistry_Core_Apply.lua; consumed by the apply helper builder.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.RegistryCoreBuilders = A.RegistryCoreBuilders or {}

function A.RegistryCoreBuilders.BuildAuraApplyHelpers(ctx)
    ctx = type(ctx) == "table" and ctx or {}

    local MSUFRef = ctx.MSUF or MSUF
    local EnsureDB = ctx.EnsureDB
    local CallGlobal = ctx.CallGlobal
    local ApplyGroup = ctx.ApplyGroup
    if type(EnsureDB) ~= "function" or type(CallGlobal) ~= "function" or type(ApplyGroup) ~= "function" then return nil end

    local function AuraModel()
        local a3 = MSUFRef and MSUFRef.MSUF_Auras3
        return a3 and a3.MenuModel or nil
    end

    local function ApplyAura(scope, reason)
        local Model = AuraModel()
        if Model and type(Model.Apply) == "function" then
            Model.Apply(scope or "shared", reason or "MSUF_ASSISTANT_AURAS")
            return
        end
        local a3 = MSUFRef and MSUFRef.MSUF_Auras3
        if a3 and type(a3.RequestApply) == "function" then
            a3.RequestApply()
        end
        CallGlobal("MSUF_UFPreview_RequestRefresh", reason or "MSUF_ASSISTANT_AURAS")
    end

    local function ApplyAuraText(reason)
        local a3 = MSUFRef and MSUFRef.MSUF_Auras3
        local ct = a3 and a3.CooldownText
        if ct and type(ct.Invalidate) == "function" then ct.Invalidate("unit") end
        if ct and type(ct.ForceRecolor) == "function" then ct.ForceRecolor("unit") end
        CallGlobal("MSUF_GF_InvalidateCooldownTextCurve")
        CallGlobal("MSUF_GF_ForceCooldownTextRecolor")
        ApplyAura("shared", reason or "MSUF_ASSISTANT_AURA_TEXT")
        ApplyGroup("party", "visual")
        ApplyGroup("raid", "visual")
        ApplyGroup("mythicraid", "visual")
    end

    local function EnsureAuraFallbackDB()
        local db = EnsureDB()
        db.auras3 = type(db.auras3) == "table" and db.auras3 or {}
        local auras = db.auras3
        auras.enabled = auras.enabled ~= false
        auras.shared = type(auras.shared) == "table" and auras.shared or {}
        auras.perUnit = type(auras.perUnit) == "table" and auras.perUnit or {}
        return auras, auras.shared
    end

    return {
        AuraModel = AuraModel,
        ApplyAura = ApplyAura,
        ApplyAuraText = ApplyAuraText,
        EnsureAuraFallbackDB = EnsureAuraFallbackDB,
    }
end
