-- Assistant Global Bar registry: shape and visibility of the three absorb lanes.
-- Loaded before MSUF_AssistantRegistry_GlobalBarSettings.lua; the main file passes shared helpers in.
--
-- The Bars page "Shields & Absorbs" section has three tabs -- positive absorbs,
-- negative heal absorbs and heal prediction -- and each carries a show toggle,
-- a bar height and a vertical offset. Only the textures, opacities and anchors
-- were reachable by name before; the rest existed as generated storage entries
-- with machine labels, so "make the absorb bar taller" reached nothing.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalBarRegistry = A.GlobalBarRegistry or {}

-- Human wording first: the registry keeps only the first MAX_SETTING_ALIASES
-- entries, so anything past that is dropped in silence.
local ABSORB_ENABLED_ALIASES = {
    "show positive absorbs", "positive absorbs", "absorb bar", "absorb bars",
    "shields on my health bar", "shields on the health bar", "shields drawn on the health bar",
    "see damage absorbs", "damage absorbs", "absorbs on the health bar",
    "show shields", "shield bar", "show shield bar", "absorb shields", "show absorb shields",
    "show absorbs", "show absorb bar", "damage absorb bar", "absorb overlay", "display absorbs",
}
local ABSORB_HEIGHT_ALIASES = {
    "absorb bar height", "shield bar height", "absorb height",
    "make the absorb bar taller", "make the shield bar bigger", "shield bar is too thin",
    "absorb bar is too thin", "shield bar too small", "absorb bar taller", "shield bar taller",
    "absorb bar thickness", "absorb bar thicker", "absorb bar thinner",
    "make the absorb bar shorter", "make the shield bar smaller", "absorb bar shorter",
    -- "make the shield bar 6 pixels tall" names height only through "tall";
    -- without these the per-unit frame Heights outrank the absorb bar.
    "shield bar pixels tall", "shield bar tall", "absorb bar pixels tall", "absorb bar tall",
    "make the shield bar", "make the absorb bar",
}
local ABSORB_OFFSET_ALIASES = {
    "absorb bar vertical offset", "absorb bar offset y", "absorb vertical offset",
    "shield bar vertical offset", "move the absorb bar up", "move the absorb bar down",
    "absorb bar up", "absorb bar down", "shield bar offset",
}
local HEAL_ABSORB_ENABLED_ALIASES = {
    "show negative heal absorbs", "negative heal absorbs", "heal absorb bar",
    "how much healing is being blocked", "healing being blocked", "blocked healing",
    "show blocked healing", "healing that is blocked", "healing absorb shields",
    "heal absorbs", "show heal absorbs", "healing absorbs", "show healing absorbs",
    "heal absorption", "healing absorption",
}
local HEAL_ABSORB_ANCHOR_ALIASES = {
    "heal absorb anchor", "heal absorb bar anchor", "healing absorb anchor",
    "heal absorb bar side", "heal absorb anchoring", "negative absorb anchor",
    "where the heal absorb bar sits", "healing absorb bar side", "healing absorb bar position",
    "healing absorb bar on the left", "healing absorb bar on the right",
}
local HEAL_ABSORB_HEIGHT_ALIASES = {
    "heal absorb bar height", "heal absorb height", "healing absorb bar height",
    "heal absorb bar taller", "heal absorb bar thickness", "make the heal absorb bar taller",
}
local HEAL_ABSORB_OFFSET_ALIASES = {
    "heal absorb bar vertical offset", "heal absorb bar offset y", "heal absorb vertical offset",
    "move the heal absorb bar up", "move the heal absorb bar down", "healing absorb bar offset",
}
local HEAL_PRED_HEIGHT_ALIASES = {
    "heal prediction bar height", "incoming heal bar height", "incoming heals bar height",
    "heal prediction height", "incoming heal bar taller", "make the incoming heal bar taller",
    "heal prediction bar thickness",
}
local HEAL_PRED_OFFSET_ALIASES = {
    "heal prediction bar vertical offset", "incoming heal bar vertical offset",
    "heal prediction bar offset y", "move the incoming heal bar up", "move the incoming heal bar down",
    "incoming heal bar offset",
}
local HEAL_PRED_TEXTURE_ALIASES = {
    "heal prediction bar texture", "incoming heal bar texture", "incoming heals texture",
    "heal prediction texture", "texture for incoming heals", "incoming heal art",
}
local HEAL_PRED_OPACITY_ALIASES = {
    "heal prediction bar opacity", "incoming heal bar opacity", "incoming heals opacity",
    "heal prediction opacity", "heal prediction alpha", "incoming heal transparency",
    "how transparent incoming heals are",
}
local HEAL_PRED_ENABLED_ALIASES = {
    "show heal prediction", "heal prediction", "incoming heals", "show incoming heals",
    "incoming healing", "heals on the way", "predicted heals", "heal prediction overlay",
    "incoming heal prediction", "healing that is on its way", "heals that are still casting",
    "healing on the way", "heals coming in", "incoming heal overlay",
}

function A.GlobalBarRegistry.RegisterAbsorbGeometrySettings(ctx)
    if type(ctx) ~= "table" then return false end

    local Registry = ctx.Registry
    local GeneralDB = ctx.GeneralDB
    local ApplyAbsorbBars = ctx.ApplyAbsorbBars
    local RegisterGeneralBoolean = ctx.RegisterGeneralBoolean
    local RegisterGeneralNumberSetting = ctx.RegisterGeneralNumberSetting
    local RegisterGeneralString = ctx.RegisterGeneralString
    local RegisterGeneralMappedEnum = ctx.RegisterGeneralMappedEnum
    local RegisterScopedSetting = ctx.RegisterScopedSetting
    local RegisterScopedMappedEnum = ctx.RegisterScopedMappedEnum
    local NormalizeTextureKeyForAssistant = ctx.NormalizeTextureKeyForAssistant
    local GLOBAL_SCOPE_ORDER = ctx.GLOBAL_SCOPE_ORDER
    local GlobalScopeAliases = ctx.GlobalScopeAliases
    local GlobalScopeIsGroup = ctx.GlobalScopeIsGroup
    local ABSORB_ANCHOR_STORAGE = ctx.ABSORB_ANCHOR_STORAGE
    local ABSORB_ANCHOR_ALIASES = ctx.ABSORB_ANCHOR_ALIASES

    if not (Registry and type(Registry.RegisterSetting) == "function") then return false end
    if type(GeneralDB) ~= "function" or type(ApplyAbsorbBars) ~= "function" then return false end
    if type(RegisterGeneralBoolean) ~= "function" or type(RegisterGeneralNumberSetting) ~= "function" then return false end
    if type(RegisterGeneralString) ~= "function" or type(RegisterGeneralMappedEnum) ~= "function" then return false end
    if type(RegisterScopedSetting) ~= "function" or type(RegisterScopedMappedEnum) ~= "function" then return false end
    if type(NormalizeTextureKeyForAssistant) ~= "function" then return false end
    if type(GLOBAL_SCOPE_ORDER) ~= "table" or type(GlobalScopeAliases) ~= "function" then return false end
    if type(GlobalScopeIsGroup) ~= "function" then return false end
    if type(ABSORB_ANCHOR_STORAGE) ~= "table" or type(ABSORB_ANCHOR_ALIASES) ~= "table" then return false end

    -- The negative lane cannot overflow past maximum health, so its dropdown
    -- offers four of the five anchors.
    local HEAL_ABSORB_ANCHOR_VALUES = { "left", "right", "follow", "reverse" }

    local category = "Global / Bars / Absorb"

    -- The menu toggle writes the display mode alongside the flag; leaving the
    -- mode behind would show the toggle as on while the bar stays hidden.
    RegisterGeneralBoolean("enableAbsorbBar", "absorbBar", "Show Positive Absorbs", true,
        ABSORB_ENABLED_ALIASES, {
            category = category,
            frameType = "globalBars",
            apply = ApplyAbsorbBars,
            reason = "MSUF_ASSISTANT_ABSORB_ENABLED",
            description = "Draws damage-absorb shields on top of the health bar.",
            dbScopes = {
                { scope = "general", dbKey = "enableAbsorbBar" },
                { scope = "general", dbKey = "absorbTextMode" },
            },
            dbScopesReplace = true,
            afterSet = function(value)
                GeneralDB().absorbTextMode = value and 2 or 1
            end,
        })
    RegisterGeneralNumberSetting("absorbBarHeight", "absorbBarHeight", "Absorb Bar Height", 0, 0, 100,
        ABSORB_HEIGHT_ALIASES, {
            category = category,
            frameType = "globalBars",
            apply = ApplyAbsorbBars,
            reason = "MSUF_ASSISTANT_ABSORB_HEIGHT",
            step = 1,
            description = "Height of the absorb bar in pixels. 0 makes it as tall as the health bar.",
        })
    RegisterGeneralNumberSetting("absorbBarOffsetY", "absorbBarOffsetY", "Absorb Bar Vertical Offset", 0, -100, 100,
        ABSORB_OFFSET_ALIASES, {
            category = category,
            frameType = "globalBars",
            apply = ApplyAbsorbBars,
            reason = "MSUF_ASSISTANT_ABSORB_OFFSET",
            step = 1,
            description = "Moves the absorb bar up or down relative to the health bar.",
        })
    RegisterGeneralBoolean("healAbsorbEnabled", "healAbsorbBar", "Show Negative Heal Absorbs", true,
        HEAL_ABSORB_ENABLED_ALIASES, {
            category = category,
            frameType = "globalBars",
            apply = ApplyAbsorbBars,
            reason = "MSUF_ASSISTANT_HEAL_ABSORB_ENABLED",
            description = "Draws heal-absorption effects, the shields that swallow incoming healing, on the health bar.",
        })
    RegisterGeneralMappedEnum("healAbsorbAnchorMode", "healAbsorbAnchor", "Heal Absorb Bar Anchor", "follow",
        HEAL_ABSORB_ANCHOR_VALUES, ABSORB_ANCHOR_STORAGE, HEAL_ABSORB_ANCHOR_ALIASES, {
            category = category,
            frameType = "globalBars",
            apply = ApplyAbsorbBars,
            reason = "MSUF_ASSISTANT_HEAL_ABSORB_ANCHOR",
            valueAliases = ABSORB_ANCHOR_ALIASES,
        })
    RegisterGeneralNumberSetting("healAbsorbBarHeight", "healAbsorbBarHeight", "Heal Absorb Bar Height", 0, 0, 100,
        HEAL_ABSORB_HEIGHT_ALIASES, {
            category = category,
            frameType = "globalBars",
            apply = ApplyAbsorbBars,
            reason = "MSUF_ASSISTANT_HEAL_ABSORB_HEIGHT",
            step = 1,
            description = "Height of the heal-absorb bar in pixels. 0 makes it as tall as the health bar.",
        })
    RegisterGeneralNumberSetting("healAbsorbBarOffsetY", "healAbsorbBarOffsetY", "Heal Absorb Bar Vertical Offset",
        0, -100, 100, HEAL_ABSORB_OFFSET_ALIASES, {
            category = category,
            frameType = "globalBars",
            apply = ApplyAbsorbBars,
            reason = "MSUF_ASSISTANT_HEAL_ABSORB_OFFSET",
            step = 1,
            description = "Moves the heal-absorb bar up or down relative to the health bar.",
        })
    RegisterGeneralNumberSetting("healPredictionBarHeight", "healPredictionBarHeight", "Heal Prediction Bar Height",
        0, 0, 100, HEAL_PRED_HEIGHT_ALIASES, {
            category = category,
            frameType = "globalBars",
            apply = ApplyAbsorbBars,
            reason = "MSUF_ASSISTANT_HEALPRED_HEIGHT",
            step = 1,
            description = "Height of the incoming-heal bar in pixels. 0 makes it as tall as the health bar.",
        })
    RegisterGeneralNumberSetting("healPredictionBarOffsetY", "healPredictionBarOffsetY",
        "Heal Prediction Bar Vertical Offset", 0, -100, 100, HEAL_PRED_OFFSET_ALIASES, {
            category = category,
            frameType = "globalBars",
            apply = ApplyAbsorbBars,
            reason = "MSUF_ASSISTANT_HEALPRED_OFFSET",
            step = 1,
            description = "Moves the incoming-heal bar up or down relative to the health bar.",
        })
    RegisterGeneralString("healPredictionBarTexture", "healPredictionTexture", "Heal Prediction Bar Texture", "",
        HEAL_PRED_TEXTURE_ALIASES, {
            category = category,
            frameType = "globalBars",
            apply = ApplyAbsorbBars,
            reason = "MSUF_ASSISTANT_HEALPRED_TEXTURE",
            normalizeValue = NormalizeTextureKeyForAssistant,
            description = "Art used for incoming heals. Leave empty to follow the foreground bar texture.",
        })
    RegisterGeneralNumberSetting("healPredictionBarOpacity", "healPredictionOpacity", "Heal Prediction Bar Opacity",
        0.45, 0, 1, HEAL_PRED_OPACITY_ALIASES, {
            category = category,
            frameType = "globalBars",
            apply = ApplyAbsorbBars,
            reason = "MSUF_ASSISTANT_HEALPRED_OPACITY",
            step = 0.05,
            percent = true,
            description = "How opaque the incoming-heal bar is drawn.",
        })

    for _, scope in ipairs(GLOBAL_SCOPE_ORDER) do
        local scopeAliases = GlobalScopeAliases
        RegisterScopedSetting("barScope", scope, "enableAbsorbBar", "absorbBar", "Show Positive Absorbs",
            "boolean", true, scopeAliases(scope, ABSORB_ENABLED_ALIASES), {
                flag = "hlOverride",
                dbScopeKeys = { "enableAbsorbBar", "absorbTextMode" },
                apply = ApplyAbsorbBars,
                reason = "MSUF_ASSISTANT_SCOPED_ABSORB_ENABLED",
            })
        RegisterScopedSetting("barScope", scope, "absorbBarHeight", "absorbBarHeight", "Absorb Bar Height",
            "number", 0, scopeAliases(scope, ABSORB_HEIGHT_ALIASES), {
                flag = "hlOverride",
                min = 0,
                max = 100,
                step = 1,
                apply = ApplyAbsorbBars,
                reason = "MSUF_ASSISTANT_SCOPED_ABSORB_HEIGHT",
            })
        RegisterScopedSetting("barScope", scope, "absorbBarOffsetY", "absorbBarOffsetY", "Absorb Bar Vertical Offset",
            "number", 0, scopeAliases(scope, ABSORB_OFFSET_ALIASES), {
                flag = "hlOverride",
                min = -100,
                max = 100,
                step = 1,
                apply = ApplyAbsorbBars,
                reason = "MSUF_ASSISTANT_SCOPED_ABSORB_OFFSET",
            })
        RegisterScopedSetting("barScope", scope, "healAbsorbEnabled", "healAbsorbBar", "Show Negative Heal Absorbs",
            "boolean", true, scopeAliases(scope, HEAL_ABSORB_ENABLED_ALIASES), {
                flag = "hlOverride",
                apply = ApplyAbsorbBars,
                reason = "MSUF_ASSISTANT_SCOPED_HEAL_ABSORB_ENABLED",
            })
        RegisterScopedMappedEnum("barScope", scope, "healAbsorbAnchorMode", "healAbsorbAnchor",
            "Heal Absorb Bar Anchor", "follow", HEAL_ABSORB_ANCHOR_VALUES, ABSORB_ANCHOR_STORAGE,
            scopeAliases(scope, HEAL_ABSORB_ANCHOR_ALIASES), {
                flag = "hlOverride",
                valueAliases = ABSORB_ANCHOR_ALIASES,
                apply = ApplyAbsorbBars,
                reason = "MSUF_ASSISTANT_SCOPED_HEAL_ABSORB_ANCHOR",
            })
        RegisterScopedSetting("barScope", scope, "healAbsorbBarHeight", "healAbsorbBarHeight", "Heal Absorb Bar Height",
            "number", 0, scopeAliases(scope, HEAL_ABSORB_HEIGHT_ALIASES), {
                flag = "hlOverride",
                min = 0,
                max = 100,
                step = 1,
                apply = ApplyAbsorbBars,
                reason = "MSUF_ASSISTANT_SCOPED_HEAL_ABSORB_HEIGHT",
            })
        RegisterScopedSetting("barScope", scope, "healAbsorbBarOffsetY", "healAbsorbBarOffsetY",
            "Heal Absorb Bar Vertical Offset", "number", 0, scopeAliases(scope, HEAL_ABSORB_OFFSET_ALIASES), {
                flag = "hlOverride",
                min = -100,
                max = 100,
                step = 1,
                apply = ApplyAbsorbBars,
                reason = "MSUF_ASSISTANT_SCOPED_HEAL_ABSORB_OFFSET",
            })
        RegisterScopedSetting("barScope", scope, "healPredictionBarHeight", "healPredictionBarHeight",
            "Heal Prediction Bar Height", "number", 0, scopeAliases(scope, HEAL_PRED_HEIGHT_ALIASES), {
                flag = "hlOverride",
                min = 0,
                max = 100,
                step = 1,
                apply = ApplyAbsorbBars,
                reason = "MSUF_ASSISTANT_SCOPED_HEALPRED_HEIGHT",
            })
        RegisterScopedSetting("barScope", scope, "healPredictionBarOffsetY", "healPredictionBarOffsetY",
            "Heal Prediction Bar Vertical Offset", "number", 0, scopeAliases(scope, HEAL_PRED_OFFSET_ALIASES), {
                flag = "hlOverride",
                min = -100,
                max = 100,
                step = 1,
                apply = ApplyAbsorbBars,
                reason = "MSUF_ASSISTANT_SCOPED_HEALPRED_OFFSET",
            })
        RegisterScopedSetting("barScope", scope, "healPredictionBarTexture", "healPredictionTexture",
            "Heal Prediction Bar Texture", "string", "", scopeAliases(scope, HEAL_PRED_TEXTURE_ALIASES), {
                flag = "hlOverride",
                normalizeValue = NormalizeTextureKeyForAssistant,
                apply = ApplyAbsorbBars,
                reason = "MSUF_ASSISTANT_SCOPED_HEALPRED_TEXTURE",
            })
        RegisterScopedSetting("barScope", scope, "healPredictionBarOpacity", "healPredictionOpacity",
            "Heal Prediction Bar Opacity", "number", 0.45, scopeAliases(scope, HEAL_PRED_OPACITY_ALIASES), {
                flag = "hlOverride",
                min = 0,
                max = 1,
                step = 0.05,
                percent = true,
                apply = ApplyAbsorbBars,
                reason = "MSUF_ASSISTANT_SCOPED_HEALPRED_OPACITY",
            })
        -- Group scopes already own these two through the scoped overlay
        -- registrar; registering them twice would give one control two owners.
        if not GlobalScopeIsGroup(scope) then
            RegisterScopedSetting("barScope", scope, "healPredEnabled", "healPrediction", "Show Heal Prediction",
                "boolean", false, scopeAliases(scope, HEAL_PRED_ENABLED_ALIASES), {
                    flag = "hlOverride",
                    apply = ApplyAbsorbBars,
                    reason = "MSUF_ASSISTANT_SCOPED_HEAL_PREDICTION",
                })
            RegisterScopedMappedEnum("barScope", scope, "healPredAnchorMode", "healPredictionAnchor",
                "Heal Prediction Anchor", "follow", ctx.ABSORB_ANCHOR_VALUES, ABSORB_ANCHOR_STORAGE,
                scopeAliases(scope, {
                    "heal prediction anchor", "heal prediction anchoring", "incoming heal anchor",
                    "incoming heal bar anchor",
                }), {
                    flag = "hlOverride",
                    valueAliases = ABSORB_ANCHOR_ALIASES,
                    apply = ApplyAbsorbBars,
                    reason = "MSUF_ASSISTANT_SCOPED_HEAL_PREDICTION_ANCHOR",
                })
        end
    end

    return true
end
