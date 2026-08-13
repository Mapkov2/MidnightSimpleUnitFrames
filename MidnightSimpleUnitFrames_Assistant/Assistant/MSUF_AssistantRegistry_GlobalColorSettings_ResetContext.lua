-- Assistant global color reset context installer.
-- Loaded before MSUF_AssistantRegistry_GlobalColorSettings.lua; consumed by GlobalColorResetActions.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

function A.GlobalRegistry.InstallColorResetActions(ctx, colorCore, auraPortraitColorSettings)
    if type(ctx) ~= "table" or type(colorCore) ~= "table" then return false end

    A.GlobalRegistry.ColorResetActions = {
        Registry = ctx.Registry,
        GeneralDB = ctx.GeneralDB,
        BarsDB = ctx.BarsDB,
        GameplayDB = ctx.GameplayDB,
        ColorAPI = colorCore.ColorAPI,
        ApplyColors = ctx.ApplyColors,
        ApplyCastbarColors = ctx.ApplyCastbarColors,
        ApplyBarGradients = ctx.ApplyBarGradients,
        ApplyGameplayColors = ctx.ApplyGameplayColors,
        ApplyAuraColors = ctx.ApplyAuraColors,
        ApplyPortraitColors = ctx.ApplyPortraitColors,
        ApplyClassPowerColors = ctx.ApplyClassPowerColors,
        SetAllPortraitRGB = auraPortraitColorSettings and auraPortraitColorSettings.SetAllPortraitRGB,
    }

    return true
end
