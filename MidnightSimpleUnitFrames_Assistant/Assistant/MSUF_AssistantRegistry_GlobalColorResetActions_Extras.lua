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
local SetAllPortraitRGB = ctx.SetAllPortraitRGB

if not (Registry and type(Registry.RegisterAction) == "function") then return end
if type(GeneralDB) ~= "function" or type(GameplayDB) ~= "function" then return end
if type(ApplyGameplayColors) ~= "function" or type(ApplyAuraColors) ~= "function" then return end
if type(ApplyPortraitColors) ~= "function" or type(ApplyClassPowerColors) ~= "function" then return end
if type(SetAllPortraitRGB) ~= "function" then return end

local function ParseClassPowerFullColorAliasArgs(text)
    local normalized = tostring(text or ""):lower():gsub("[^%w]+", " ")
    normalized = " " .. normalized:gsub("^%s+", ""):gsub("%s+$", "") .. " "

    local data = A.GlobalColorSettingsRegistryData
    for _, resource in ipairs(type(data) == "table" and data.CLASS_POWER_SLOT_RESOURCES or {}) do
        for _, alias in ipairs(resource.aliases or {}) do
            local phrase = tostring(alias or ""):lower():gsub("[^%w]+", " ")
            phrase = phrase:gsub("^%s+", ""):gsub("%s+$", "")
            if phrase ~= "" and normalized:find(" " .. phrase .. " ", 1, true) then
                return { resourceToken = resource.token }
            end
        end
    end

    -- A generic request still belongs to this action, but the explicit input
    -- contract will retain it as a safe resource-choice clarification.
    return {}
end

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
        g.dispelTypeColorOverrides = nil
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

Registry:RegisterAction({
    key = "reset_class_power_full_color",
    label = "Reset Class Power Full Resource Color",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    aliases = {
        "reset vengeance soul fragments full resource color",
        "reset holy power full resource color",
        "reset class resource full color", "reset class power full color",
        "restore class resource full color",
    },
    parseAliasArgs = ParseClassPowerFullColorAliasArgs,
    run = function(args)
        local resourceToken = args and args.resourceToken
        if type(resourceToken) ~= "string" or resourceToken == "" then
            return false, "Which class resource full color do you want me to reset?"
        end

        local g = GeneralDB()
        if type(g.classPowerColorOverrides) ~= "table" then g.classPowerColorOverrides = {} end
        g.classPowerColorOverrides[resourceToken .. "_FULL"] = nil

        local bars = type(BarsDB) == "function" and BarsDB() or nil
        if type(bars) == "table" then
            if type(bars.classPowerFullColorEnabled) ~= "table" then bars.classPowerFullColorEnabled = {} end
            bars.classPowerFullColorEnabled[resourceToken] = nil
        end

        ApplyClassPowerColors("MSUF_ASSISTANT_RESET_CLASS_POWER_FULL_COLOR")
        if M and type(M.RequestRefresh) == "function" then
            M.RequestRefresh(nil, "class-power-full-color-reset")
        elseif M and type(M.Refresh) == "function" then
            M.Refresh()
        end
        return true, "Done. Reset that class resource's full color."
    end,
})
