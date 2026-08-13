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

    -- "absorb bar" and "absorb bars" belong to the Show Positive Absorbs
    -- toggle, which is what the Bars page shows and what a player means by
    -- "turn the absorb bar on"; the display mode keeps only its own name.
    RegisterGeneralMappedEnum("absorbTextMode", "absorbMode", "Absorb Display Mode", "bar", ABSORB_MODE_VALUES, ABSORB_MODE_STORAGE, {
        "absorb display mode", "absorb display", "absorb mode",
    }, { category = "Global / Bars / Absorb", frameType = "globalBars", apply = ApplyAbsorbBars, reason = "MSUF_ASSISTANT_ABSORB_MODE", valueAliases = ABSORB_MODE_ALIASES })
    RegisterGeneralMappedEnum("absorbAnchorMode", "absorbAnchor", "Absorb Bar Anchor", "right", ABSORB_ANCHOR_VALUES, ABSORB_ANCHOR_STORAGE, {
        "absorb bar anchor", "absorb anchor", "absorb anchoring",
        "where the absorb bar sits", "absorb bar follows the health bar",
        "absorb bar follow the health bar", "shield bar follows the hp bar",
        "shield bar anchor", "shield bar side", "absorb bar side",
        "shield bar should follow the hp bar", "shield bar should follow the health bar",
        "global absorb bar anchor", "global bar absorb anchor",
        "global bar right absorb", "global absorb right", "right absorb bar", "right absorb anchor",
        "absorb right side", "absorb anchor right", "absorb bar right side",
    }, { category = "Global / Bars / Absorb", frameType = "globalBars", apply = ApplyAbsorbBars, reason = "MSUF_ASSISTANT_ABSORB_ANCHOR", valueAliases = ABSORB_ANCHOR_ALIASES })
    RegisterGeneralBoolean("overAbsorbOverlay", "overAbsorbOverlay", "Over-Absorb Overlay", false, {
        "over absorb overlay", "over-absorb overlay", "over absorb glow", "overshield overlay",
        "full hp absorb overlay", "full health absorb overlay",
        "glow when my shield is bigger than my missing health", "shields that overflow past full health",
        "mark shields that overflow", "overflowing shield glow", "shield bigger than missing health",
    }, {
        category = "Global / Bars / Absorb",
        frameType = "globalBars",
        apply = ApplyAbsorbBars,
        reason = "MSUF_ASSISTANT_OVER_ABSORB_OVERLAY",
        description = "Marks the part of a shield that is larger than the health you are missing, so an overflowing absorb is still visible.",
    })
    RegisterGeneralBoolean("fullHealthAbsorbStripe", "fullHealthAbsorbStripe", "Full-Health Absorb Stripe", false, {
        "full-health absorb stripe", "full health absorb stripe", "full hp absorb stripe",
        "absorb stripe at full health", "absorb stripe on full health",
        "stripe when i have a shield at full health", "marker for shields while my health is full",
        "shield marker at full health", "stripe for shields at full hp",
    }, {
        category = "Global / Bars / Absorb",
        frameType = "globalBars",
        apply = ApplyAbsorbBars,
        reason = "MSUF_ASSISTANT_FULL_HEALTH_ABSORB_STRIPE",
        description = "Draws a thin marker at the end of a full health bar so a shield is still visible when there is no missing health to fill.",
    })
    -- The menu's "Show heal prediction" toggle stores healPredEnabled and
    -- mirrors it into showSelfHealPrediction on the shared scope. Writing only
    -- the mirror would leave the bar hidden, so this owns both keys.
    RegisterGeneralBoolean("showSelfHealPrediction", "healPrediction", "Heal Prediction Overlay", false, {
        "heal prediction", "heal prediction overlay", "incoming heal prediction", "self heal prediction",
        "show heal prediction", "incoming heals", "show incoming heals", "incoming healing",
        "heals on the way", "healing on the way", "predicted heals", "heals that are still casting",
        "healing on its way", "heals on its way", "healing that is coming",
    }, {
        category = "Global / Bars / Absorb",
        frameType = "globalBars",
        apply = function(reason)
            CallGlobal("MSUF_RefreshSelfHealPredUnitEvent")
            ApplyAbsorbBars(reason)
        end,
        reason = "MSUF_ASSISTANT_HEAL_PREDICTION",
        description = "Shows healing that is on its way -- casts still in flight and heal-over-time ticks -- as an overlay past current health.",
        dbScopes = {
            { scope = "general", dbKey = "showSelfHealPrediction" },
            { scope = "general", dbKey = "healPredEnabled" },
        },
        dbScopesReplace = true,
        afterSet = function(value) GeneralDB().healPredEnabled = value end,
    })
    RegisterGeneralMappedEnum("healPredAnchorMode", "healPredictionAnchor", "Heal Prediction Anchor", "follow", ABSORB_ANCHOR_VALUES, ABSORB_ANCHOR_STORAGE, {
        "heal prediction anchor", "heal prediction anchoring", "incoming heal anchor",
        "incoming heal bar anchor", "where incoming heals sit", "incoming heals side",
        "anchor incoming heals",
    }, { category = "Global / Bars / Absorb", frameType = "globalBars", apply = ApplyAbsorbBars, reason = "MSUF_ASSISTANT_HEAL_PREDICTION_ANCHOR", valueAliases = ABSORB_ANCHOR_ALIASES })
    RegisterGeneralNumberSetting("absorbBarOpacity", "absorbOpacity", "Absorb Bar Opacity", 0.75, 0, 1, {
        "absorb bar opacity", "absorb opacity", "absorb alpha",
        "shield bar opacity", "shield bar transparency", "absorb bar transparency",
        "how transparent the absorb bar is",
    }, { category = "Global / Bars / Absorb", frameType = "globalBars", apply = ApplyAbsorbBars, reason = "MSUF_ASSISTANT_ABSORB_OPACITY", step = 0.05, percent = true })
    RegisterGeneralString("absorbBarTexture", "absorbTexture", "Absorb Bar Texture", "", {
        "absorb bar texture", "absorb texture", "shield bar texture", "absorb bar art",
        "texture for the absorb bar", "texture for the shield bar",
    }, { category = "Global / Bars / Absorb", frameType = "globalBars", apply = ApplyAbsorbBars, reason = "MSUF_ASSISTANT_ABSORB_TEXTURE", normalizeValue = NormalizeTextureKeyForAssistant })
    RegisterGeneralString("healAbsorbBarTexture", "healAbsorbTexture", "Heal Absorb Bar Texture", "", {
        "heal absorb texture", "heal-absorb texture", "heal absorb bar texture",
        "healing absorb texture", "texture for the heal absorb bar", "heal absorb bar art",
    }, { category = "Global / Bars / Absorb", frameType = "globalBars", apply = ApplyAbsorbBars, reason = "MSUF_ASSISTANT_HEAL_ABSORB_TEXTURE", normalizeValue = NormalizeTextureKeyForAssistant })
    RegisterGeneralNumberSetting("healAbsorbBarOpacity", "healAbsorbOpacity", "Heal Absorb Bar Opacity", 1, 0, 1, {
        "heal absorb opacity", "heal-absorb opacity", "heal absorb bar opacity",
        "healing absorb opacity", "heal absorb bar transparency",
    }, { category = "Global / Bars / Absorb", frameType = "globalBars", apply = ApplyAbsorbBars, reason = "MSUF_ASSISTANT_HEAL_ABSORB_OPACITY", step = 0.05, percent = true })
end
