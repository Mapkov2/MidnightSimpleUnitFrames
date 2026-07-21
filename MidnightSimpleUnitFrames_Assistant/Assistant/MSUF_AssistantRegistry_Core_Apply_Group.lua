-- Assistant registry core group apply helper.
-- Loaded before MSUF_AssistantRegistry_Core.lua; BuildApplyHelpers consumes this builder.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.RegistryCoreBuilders = A.RegistryCoreBuilders or {}

local function NormalizeScope(scope)
    scope = tostring(scope or "")
    if scope == "gf_party" then return "party" end
    if scope == "gf_raid" then return "raid" end
    if scope == "gf_mythicraid" then return "mythicraid" end
    if scope == "gf_priority" or scope == "priority" then return "priority" end
    if scope == "party" or scope == "raid" or scope == "mythicraid" then return scope end
    return nil
end

local function AddDirty(mask, flag)
    if not flag then return mask end
    mask = tonumber(mask) or 0
    flag = tonumber(flag) or 0
    if flag <= 0 then return mask end
    if mask % (flag * 2) >= flag then return mask end
    return mask + flag
end

local function DirtyForMode(gf, mode)
    if type(gf) ~= "table" then return nil end
    if mode == "geometry" then
        local dirty = AddDirty(nil, gf.DIRTY_GEOMETRY)
        dirty = AddDirty(dirty, gf.DIRTY_LAYOUT)
        return dirty ~= 0 and dirty or gf.DIRTY_VISUAL
    end
    if mode == "auras" then return gf.DIRTY_AURAS end
    if mode == "fonts" or mode == "font" then return gf.DIRTY_FONT end
    if mode == "border" or mode == "borders" then return gf.DIRTY_BORDER end
    if mode == "colors" or mode == "color" then return gf.DIRTY_COLOR end
    return gf.DIRTY_VISUAL
end

local function ApplyLegacyGroup(scope, mode, gf)
    scope = NormalizeScope(scope)
    local dirty = DirtyForMode(gf, mode)
    if mode == "rebuild" and scope then
        local did = false
        if type(_G.MSUF_GF_RefreshGeometry) == "function" then _G.MSUF_GF_RefreshGeometry(scope); did = true end
        if type(_G.MSUF_GF_RefreshUnitBindings) == "function" then _G.MSUF_GF_RefreshUnitBindings(scope); did = true end
        if type(_G.MSUF_GF_RefreshVisuals) == "function" then _G.MSUF_GF_RefreshVisuals(scope, gf and gf.DIRTY_ALL or dirty); did = true end
        if did then return true end
    elseif mode == "geometry" and scope then
        local did = false
        if type(_G.MSUF_GF_RefreshGeometry) == "function" then _G.MSUF_GF_RefreshGeometry(scope); did = true end
        if type(_G.MSUF_GF_RefreshVisuals) == "function" and dirty then _G.MSUF_GF_RefreshVisuals(scope, dirty); did = true end
        if did then return true end
    elseif scope and type(_G.MSUF_GF_RefreshVisuals) == "function" then
        _G.MSUF_GF_RefreshVisuals(scope, dirty)
        return true
    end
    if mode == "rebuild" and type(_G.MSUF_GF_RefreshAll) == "function" then
        _G.MSUF_GF_RefreshAll()
        return true
    end
    return false
end

function A.RegistryCoreBuilders.BuildGroupApplyHelper(ctx)
    ctx = type(ctx) == "table" and ctx or {}

    local MRef = ctx.M or M
    local MSUFRef = ctx.MSUF or MSUF
    local function CurrentApplyService()
        return (MRef and MRef.ApplyService) or (M and M.ApplyService) or _G.MSUF_Menu2_ApplyService
    end

    return function(scope, mode)
        scope = NormalizeScope(scope) or scope
        mode = mode or "visual"
        local ApplyService = CurrentApplyService()
        local gf = MSUFRef and MSUFRef.GF
        local dirty = DirtyForMode(gf, mode)
        local reason = "MSUF_ASSISTANT_GROUP"
        if ApplyService then
            if mode ~= "rebuild" and mode ~= "reset" and dirty and type(ApplyService.RequestGroupDirtyMask) == "function" then
                return ApplyService.RequestGroupDirtyMask(scope or "party", dirty, reason)
            end
            if type(ApplyService.RequestGroup) == "function" then
                return ApplyService.RequestGroup(scope or "party", mode, reason)
            end
        end
        local GP = MRef and MRef.GroupPage
        if GP and type(GP.QueueGF) == "function" then
            GP.QueueGF(scope or "party", mode)
        elseif not ApplyLegacyGroup(scope, mode, gf) and MRef and type(MRef.RefreshGFNativePreviews) == "function" then
            MRef.RefreshGFNativePreviews()
        end
        if MRef and type(MRef.RefreshGFNativePreviews) == "function" then MRef.RefreshGFNativePreviews() end
    end
end
