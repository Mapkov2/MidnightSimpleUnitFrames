-- Assistant Global Bar absorb and heal-prediction setting registry.
-- Loaded before MSUF_AssistantRegistry_GlobalBarSettings.lua; the main file passes shared helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalBarRegistry = A.GlobalBarRegistry or {}

function A.GlobalBarRegistry.RegisterAbsorbSettings(ctx)
    if type(ctx) ~= "table" then return end

    local GeneralDB = ctx.GeneralDB
    local CallGlobal = ctx.CallGlobal
    local RegisterGeneralMappedEnum = ctx.RegisterGeneralMappedEnum
    local RegisterGeneralBoolean = ctx.RegisterGeneralBoolean
    local RegisterGeneralNumberSetting = ctx.RegisterGeneralNumberSetting
    local RegisterGeneralString = ctx.RegisterGeneralString
    local ApplyAbsorbBars = ctx.ApplyAbsorbBars
    local NormalizeTextureKeyForAssistant = ctx.NormalizeTextureKeyForAssistant
    local ABSORB_MODE_STORAGE = ctx.ABSORB_MODE_STORAGE
    local ABSORB_MODE_VALUES = ctx.ABSORB_MODE_VALUES
    local ABSORB_MODE_ALIASES = ctx.ABSORB_MODE_ALIASES
    local ABSORB_ANCHOR_STORAGE = ctx.ABSORB_ANCHOR_STORAGE
    local ABSORB_ANCHOR_VALUES = ctx.ABSORB_ANCHOR_VALUES
    local ABSORB_ANCHOR_ALIASES = ctx.ABSORB_ANCHOR_ALIASES

    if type(GeneralDB) ~= "function" or type(CallGlobal) ~= "function" then return end
    if type(RegisterGeneralMappedEnum) ~= "function" or type(RegisterGeneralBoolean) ~= "function" then return end
    if type(RegisterGeneralNumberSetting) ~= "function" or type(RegisterGeneralString) ~= "function" then return end
    if type(ApplyAbsorbBars) ~= "function" or type(NormalizeTextureKeyForAssistant) ~= "function" then return end
    if type(ABSORB_MODE_STORAGE) ~= "table" or type(ABSORB_MODE_VALUES) ~= "table" or type(ABSORB_MODE_ALIASES) ~= "table" then return end
    if type(ABSORB_ANCHOR_STORAGE) ~= "table" or type(ABSORB_ANCHOR_VALUES) ~= "table" or type(ABSORB_ANCHOR_ALIASES) ~= "table" then return end

    RegisterGeneralMappedEnum("absorbTextMode", "absorbMode", "Absorb Display Mode", "bar", ABSORB_MODE_VALUES, ABSORB_MODE_STORAGE, {
        "absorb display mode", "absorb mode", "absorb bars",
    }, { category = "Global / Bars / Absorb", frameType = "globalBars", apply = ApplyAbsorbBars, reason = "MSUF_ASSISTANT_ABSORB_MODE", valueAliases = ABSORB_MODE_ALIASES })
    RegisterGeneralMappedEnum("absorbAnchorMode", "absorbAnchor", "Absorb Bar Anchor", "right", ABSORB_ANCHOR_VALUES, ABSORB_ANCHOR_STORAGE, {
        "absorb bar anchor", "absorb anchor", "absorb anchoring",
        "global absorb bar anchor", "global bar absorb anchor",
        "global bar right absorb", "global absorb right", "right absorb bar", "right absorb anchor",
        "absorb right side", "absorb anchor right", "absorb bar right side",
    }, { category = "Global / Bars / Absorb", frameType = "globalBars", apply = ApplyAbsorbBars, reason = "MSUF_ASSISTANT_ABSORB_ANCHOR", valueAliases = ABSORB_ANCHOR_ALIASES })
    RegisterGeneralBoolean("overAbsorbOverlay", "overAbsorbOverlay", "Over-Absorb Overlay", false, {
        "over absorb overlay", "over-absorb overlay", "over absorb glow", "overshield overlay",
        "full hp absorb overlay", "full health absorb overlay",
    }, { category = "Global / Bars / Absorb", frameType = "globalBars", apply = ApplyAbsorbBars, reason = "MSUF_ASSISTANT_OVER_ABSORB_OVERLAY" })
    RegisterGeneralBoolean("fullHealthAbsorbStripe", "fullHealthAbsorbStripe", "Full-Health Absorb Stripe", false, {
        "full-health absorb stripe", "full health absorb stripe", "full hp absorb stripe",
        "absorb stripe at full health", "absorb stripe on full health",
    }, { category = "Global / Bars / Absorb", frameType = "globalBars", apply = ApplyAbsorbBars, reason = "MSUF_ASSISTANT_FULL_HEALTH_ABSORB_STRIPE" })
    RegisterGeneralBoolean("showSelfHealPrediction", "healPrediction", "Heal Prediction Overlay", false, {
        "heal prediction", "heal prediction overlay", "incoming heal prediction", "self heal prediction",
    }, {
        category = "Global / Bars / Absorb",
        frameType = "globalBars",
        apply = function(reason)
            CallGlobal("MSUF_RefreshSelfHealPredUnitEvent")
            ApplyAbsorbBars(reason)
        end,
        reason = "MSUF_ASSISTANT_HEAL_PREDICTION",
    })
    RegisterGeneralMappedEnum("healPredAnchorMode", "healPredictionAnchor", "Heal Prediction Anchor", "follow", ABSORB_ANCHOR_VALUES, ABSORB_ANCHOR_STORAGE, {
        "heal prediction anchor", "heal prediction anchoring", "incoming heal anchor",
    }, { category = "Global / Bars / Absorb", frameType = "globalBars", apply = ApplyAbsorbBars, reason = "MSUF_ASSISTANT_HEAL_PREDICTION_ANCHOR", valueAliases = ABSORB_ANCHOR_ALIASES })
    RegisterGeneralNumberSetting("absorbBarOpacity", "absorbOpacity", "Absorb Bar Opacity", 0.75, 0, 1, {
        "absorb bar opacity", "absorb opacity", "absorb alpha",
    }, { category = "Global / Bars / Absorb", frameType = "globalBars", apply = ApplyAbsorbBars, reason = "MSUF_ASSISTANT_ABSORB_OPACITY", step = 0.05, percent = true })
    RegisterGeneralString("absorbBarTexture", "absorbTexture", "Absorb Bar Texture", "", {
        "absorb bar texture", "absorb texture",
    }, { category = "Global / Bars / Absorb", frameType = "globalBars", apply = ApplyAbsorbBars, reason = "MSUF_ASSISTANT_ABSORB_TEXTURE", normalizeValue = NormalizeTextureKeyForAssistant })
    RegisterGeneralString("healAbsorbBarTexture", "healAbsorbTexture", "Heal Absorb Bar Texture", "", {
        "heal absorb texture", "heal-absorb texture", "heal absorb bar texture",
    }, { category = "Global / Bars / Absorb", frameType = "globalBars", apply = ApplyAbsorbBars, reason = "MSUF_ASSISTANT_HEAL_ABSORB_TEXTURE", normalizeValue = NormalizeTextureKeyForAssistant })
    RegisterGeneralNumberSetting("healAbsorbBarOpacity", "healAbsorbOpacity", "Heal Absorb Bar Opacity", 1, 0, 1, {
        "heal absorb opacity", "heal-absorb opacity", "heal absorb bar opacity",
    }, { category = "Global / Bars / Absorb", frameType = "globalBars", apply = ApplyAbsorbBars, reason = "MSUF_ASSISTANT_HEAL_ABSORB_OPACITY", step = 0.05, percent = true })
end
