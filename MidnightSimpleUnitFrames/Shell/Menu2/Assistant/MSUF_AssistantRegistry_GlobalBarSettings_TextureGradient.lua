-- Assistant Global Bar texture and gradient setting registry.
-- Loaded before MSUF_AssistantRegistry_GlobalBarSettings.lua; the main file passes shared helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalBarRegistry = A.GlobalBarRegistry or {}

function A.GlobalBarRegistry.RegisterTextureGradientSettings(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local GeneralDB = ctx.GeneralDB
    local RegisterGeneralString = ctx.RegisterGeneralString
    local RegisterGeneralBoolean = ctx.RegisterGeneralBoolean
    local RegisterGeneralNumberSetting = ctx.RegisterGeneralNumberSetting
    local ApplyBars = ctx.ApplyBars
    local ApplyBarGradients = ctx.ApplyBarGradients
    local NormalizeTextureKeyForAssistant = ctx.NormalizeTextureKeyForAssistant
    local GRADIENT_DIRECTION_VALUES = ctx.GRADIENT_DIRECTION_VALUES
    local GRADIENT_DIRECTION_KEYS = ctx.GRADIENT_DIRECTION_KEYS
    local GRADIENT_DIRECTION_ALIASES = ctx.GRADIENT_DIRECTION_ALIASES

    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(GeneralDB) ~= "function" or type(RegisterGeneralString) ~= "function" then return end
    if type(RegisterGeneralBoolean) ~= "function" or type(RegisterGeneralNumberSetting) ~= "function" then return end
    if type(ApplyBars) ~= "function" or type(ApplyBarGradients) ~= "function" then return end
    if type(NormalizeTextureKeyForAssistant) ~= "function" then return end
    if type(GRADIENT_DIRECTION_VALUES) ~= "table" or type(GRADIENT_DIRECTION_KEYS) ~= "table" then return end

    RegisterGeneralString("barTexture", "texture", "Global Bar Texture", "Solid", {
        "bar texture", "bars texture", "global bar texture", "global bars texture", "health bar texture", "power bar texture", "foreground bar texture", "foreground texture", "foreground bar texture",
    }, {
        category = "Global / Bars / Textures",
        frameType = "globalBars",
        apply = ApplyBars,
        reason = "MSUF_ASSISTANT_BAR_TEXTURE",
        normalizeValue = NormalizeTextureKeyForAssistant,
    })
    RegisterGeneralString("barBackgroundTexture", "backgroundTexture", "Global Bar Background Texture", "Solid", {
        "bar background texture", "global bar background texture", "background bar texture", "bar bg texture", "background texture", "background texture bars", "bars background texture",
    }, {
        category = "Global / Bars / Textures",
        frameType = "globalBars",
        apply = ApplyBars,
        reason = "MSUF_ASSISTANT_BAR_BACKGROUND_TEXTURE",
        normalizeValue = NormalizeTextureKeyForAssistant,
    })
    RegisterGeneralBoolean("enableGradient", "healthGradient", "HP Bar Gradient", false, {
        "hp bar gradient", "health bar gradient", "health gradient", "hp gradient",
        "bar gradient", "bars gradient", "bar gradients", "unitframe gradient",
        "unit frame gradient", "unitframe bar gradient", "unit frame bar gradient",
    }, { category = "Global / Bars / Gradient", frameType = "globalBars", apply = ApplyBarGradients, reason = "MSUF_ASSISTANT_HP_GRADIENT" })
    RegisterGeneralBoolean("enablePowerGradient", "powerGradient", "Power Bar Gradient", false, {
        "power bar gradient", "power gradient", "mana gradient", "mana bar gradient",
        "resource gradient", "resource bar gradient",
    }, { category = "Global / Bars / Gradient", frameType = "globalBars", apply = ApplyBarGradients, reason = "MSUF_ASSISTANT_POWER_GRADIENT" })
    RegisterGeneralNumberSetting("gradientStrength", "gradientStrength", "Bar Gradient Strength", 0.45, 0, 1, {
        "gradient strength", "bar gradient strength", "health gradient strength", "power gradient strength",
    }, { category = "Global / Bars / Gradient", frameType = "globalBars", apply = ApplyBarGradients, reason = "MSUF_ASSISTANT_GRADIENT_STRENGTH", step = 0.05, percent = true })
    Registry:RegisterSetting({
        key = "general.gradientDirection",
        label = "Bar Gradient Direction",
        category = "Global / Bars / Gradient",
        unit = "global",
        frameType = "globalBars",
        attribute = "gradientDirection",
        type = "enum",
        aliases = {
            "gradient direction", "bar gradient direction", "health gradient direction", "power gradient direction",
            "global bar gradient direction", "global bars gradient direction",
            "global bar right", "global bar right gradient", "global bar right direction",
            "global bar right color", "bar right gradient", "bar right direction", "right bar gradient",
            "gradient from right", "gradient from left", "gradient from top", "gradient from bottom",
            "bar gradient from right", "bar gradient from left", "bar gradient from top", "bar gradient from bottom",
        },
        values = GRADIENT_DIRECTION_VALUES,
        valueAliases = GRADIENT_DIRECTION_ALIASES,
        get = function()
            local g = GeneralDB()
            for i = 1, #GRADIENT_DIRECTION_VALUES do
                local value = GRADIENT_DIRECTION_VALUES[i]
                if g[GRADIENT_DIRECTION_KEYS[value]] == true then return value end
            end
            local value = g.gradientDirection
            return GRADIENT_DIRECTION_KEYS[value] and value or "RIGHT"
        end,
        set = function(value)
            if not GRADIENT_DIRECTION_KEYS[value] then value = "RIGHT" end
            local g = GeneralDB()
            for i = 1, #GRADIENT_DIRECTION_VALUES do
                local dir = GRADIENT_DIRECTION_VALUES[i]
                g[GRADIENT_DIRECTION_KEYS[dir]] = dir == value
            end
            g.gradientDirection = value
        end,
        apply = function() ApplyBarGradients("MSUF_ASSISTANT_GRADIENT_DIRECTION") end,
        combatSafe = false,
    })
end
