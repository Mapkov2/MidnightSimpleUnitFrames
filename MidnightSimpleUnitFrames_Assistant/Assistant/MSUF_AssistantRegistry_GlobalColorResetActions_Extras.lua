-- Global color reset assistant action domain for non-bar color domains.
-- Loaded after MSUF_AssistantRegistry_GlobalColorResetActions.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local ctx = A.GlobalRegistry and A.GlobalRegistry.ColorResetActions
if type(ctx) ~= "table" then return end

local Registry = ctx.Registry
local GeneralDB = ctx.GeneralDB
local BarsDB = ctx.BarsDB
local GameplayDB = ctx.GameplayDB
local ApplyGameplayColors = ctx.ApplyGameplayColors
local ApplyAuraColors = ctx.ApplyAuraColors
local ApplyPortraitColors = ctx.ApplyPortraitColors
local ApplyClassPowerColors = ctx.ApplyClassPowerColors
local AuraSharedDB = ctx.AuraSharedDB
local SetAllPortraitRGB = ctx.SetAllPortraitRGB

if not (Registry and type(Registry.RegisterAction) == "function") then return end
if type(GeneralDB) ~= "function" or type(GameplayDB) ~= "function" then return end
if type(ApplyGameplayColors) ~= "function" or type(ApplyAuraColors) ~= "function" then return end
if type(ApplyPortraitColors) ~= "function" or type(ApplyClassPowerColors) ~= "function" then return end
if type(AuraSharedDB) ~= "function" or type(SetAllPortraitRGB) ~= "function" then return end

Registry:RegisterAction({
    key = "reset_gameplay_colors",
    label = "Reset Gameplay Colors",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    run = function()
        local gp = GameplayDB()
        gp.combatTimerColor = { 1, 1, 1 }
        gp.combatStateEnterColor = { 1, 1, 1 }
        gp.combatStateLeaveColor = gp.combatStateColorSync and { 1, 1, 1 } or { 0.7, 0.7, 0.7 }
        gp.crosshairInRangeColor = { 0, 1, 0 }
        gp.crosshairOutRangeColor = { 1, 0, 0 }
        ApplyGameplayColors("MSUF_ASSISTANT_RESET_GAMEPLAY_COLORS")
        return true, "Done. Gameplay colors reset."
    end,
})

Registry:RegisterAction({
    key = "reset_aura_colors",
    label = "Reset Aura Colors",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    run = function()
        local g = GeneralDB()
        g.aurasOwnBuffHighlightColor = { 1, 0.85, 0.2 }
        g.aurasOwnDebuffHighlightColor = { 1, 0.30, 0.30 }
        g.aurasStackCountColor = { 1, 1, 1 }
        g.aurasCooldownTextUseBuckets = false
        g.aurasCooldownTextSafeColor = nil
        g.aurasCooldownTextWarningColor = { 1, 0.85, 0.2 }
        g.aurasCooldownTextUrgentColor = { 1, 0.55, 0.1 }
        g.aurasCooldownTextSafeSeconds = 60
        g.aurasCooldownTextWarningSeconds = 15
        g.aurasCooldownTextUrgentSeconds = 5
        local sh = AuraSharedDB()
        sh.pandemicR, sh.pandemicG, sh.pandemicB = 0, 0.4, 1
        ApplyAuraColors("MSUF_ASSISTANT_RESET_AURA_COLORS")
        return true, "Done. Aura colors reset."
    end,
})

Registry:RegisterAction({
    key = "reset_portrait_colors",
    label = "Reset Portrait Colors",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    run = function()
        SetAllPortraitRGB("portraitBorderColor", 1, 1, 1)
        SetAllPortraitRGB("portraitBgColor", 0.05, 0.05, 0.05)
        local g = GeneralDB()
        g.portraitBorderColorA = 1
        g.portraitBgColorA = 0.85
        ApplyPortraitColors("MSUF_ASSISTANT_RESET_PORTRAIT_COLORS")
        return true, "Done. Portrait colors reset."
    end,
})

Registry:RegisterAction({
    key = "reset_resource_colors",
    label = "Reset Resource Colors",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    run = function()
        local g = GeneralDB()
        g.powerColorOverrides = nil
        g.classPowerColorOverrides = nil
        g.classPowerBgColorOverrides = nil
        if type(BarsDB) == "function" then BarsDB().classPowerFullColorEnabled = nil end
        ApplyClassPowerColors("MSUF_ASSISTANT_RESET_RESOURCE_COLORS")
        return true, "Done. Resource colors reset."
    end,
})
