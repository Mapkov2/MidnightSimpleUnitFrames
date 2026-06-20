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

function A.RegistryCoreBuilders.BuildGroupApplyHelper(ctx)
    ctx = type(ctx) == "table" and ctx or {}

    local MRef = ctx.M or M
    local MSUFRef = ctx.MSUF or MSUF

    return function(scope, mode)
        local GP = MRef and MRef.GroupPage
        if GP and type(GP.QueueGF) == "function" then
            GP.QueueGF(scope or "party", mode or "visual")
        elseif MSUFRef and MSUFRef.GF then
            if mode == "rebuild" and type(MSUFRef.GF.RebuildAll) == "function" then
                MSUFRef.GF.RebuildAll()
            elseif type(MSUFRef.GF.RefreshVisuals) == "function" then
                MSUFRef.GF.RefreshVisuals()
            end
        end
        if MRef and type(MRef.RefreshGFNativePreviews) == "function" then MRef.RefreshGFNativePreviews() end
    end
end
