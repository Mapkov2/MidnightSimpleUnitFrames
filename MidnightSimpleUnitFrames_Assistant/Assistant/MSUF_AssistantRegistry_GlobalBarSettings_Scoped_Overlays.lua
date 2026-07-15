-- Assistant Global Bar scoped overlay registry: absorb, border, and dispel overlay controls.
-- Loaded after MSUF_AssistantRegistry_GlobalBarSettings_Scoped.lua; called by the scoped registrar per scope.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalBarRegistry = A.GlobalBarRegistry or {}

function A.GlobalBarRegistry.RegisterScopedOverlaySettings(ctx, scope)
    if type(ctx) ~= "table" then return false end

    local ApplyBarOutline = ctx.ApplyBarOutline
    local ApplyAggroBorder = ctx.ApplyAggroBorder
    local ApplyDispelPurgeBorder = ctx.ApplyDispelPurgeBorder
    local ApplyHighlightBorders = ctx.ApplyHighlightBorders
    local ApplyAbsorbBars = ctx.ApplyAbsorbBars
    local RegisterScopedSetting = ctx.RegisterScopedSetting
    local RegisterScopedMappedEnum = ctx.RegisterScopedMappedEnum
    local GlobalScopeIsGroup = ctx.GlobalScopeIsGroup
    local GlobalScopeAliases = ctx.GlobalScopeAliases
    local NormalizeTextureKeyForAssistant = ctx.NormalizeTextureKeyForAssistant
    local ON_OFF_VALUES = ctx.ON_OFF_VALUES
    local ON_OFF_STORAGE = ctx.ON_OFF_STORAGE
    local ON_OFF_ALIASES = ctx.ON_OFF_ALIASES
    local AGGRO_MODE_VALUES = ctx.AGGRO_MODE_VALUES
    local AGGRO_MODE_ALIASES = ctx.AGGRO_MODE_ALIASES
    local ABSORB_ANCHOR_VALUES = ctx.ABSORB_ANCHOR_VALUES
    local ABSORB_ANCHOR_STORAGE = ctx.ABSORB_ANCHOR_STORAGE
    local ABSORB_ANCHOR_ALIASES = ctx.ABSORB_ANCHOR_ALIASES
    local ABSORB_MODE_VALUES = ctx.ABSORB_MODE_VALUES
    local ABSORB_MODE_STORAGE = ctx.ABSORB_MODE_STORAGE
    local ABSORB_MODE_ALIASES = ctx.ABSORB_MODE_ALIASES
    local DISPEL_TRIGGER_VALUES = ctx.DISPEL_TRIGGER_VALUES
    local DISPEL_TRIGGER_ALIASES = ctx.DISPEL_TRIGGER_ALIASES
    local UNIT_DISPEL_TRIGGER_VALUES = ctx.UNIT_DISPEL_TRIGGER_VALUES
    local UNIT_DISPEL_TRIGGER_ALIASES = ctx.UNIT_DISPEL_TRIGGER_ALIASES
    local UNIT_DISPEL_STYLE_VALUES = ctx.UNIT_DISPEL_STYLE_VALUES
    local UNIT_DISPEL_STYLE_ALIASES = ctx.UNIT_DISPEL_STYLE_ALIASES

    if type(RegisterScopedSetting) ~= "function" or type(RegisterScopedMappedEnum) ~= "function" then return false end
    if type(GlobalScopeIsGroup) ~= "function" or type(GlobalScopeAliases) ~= "function" then return false end
    if type(NormalizeTextureKeyForAssistant) ~= "function" then return false end

    RegisterScopedMappedEnum("barScope", scope, "absorbTextMode", "absorbMode", "Absorb Display Mode", "bar", ABSORB_MODE_VALUES, ABSORB_MODE_STORAGE, GlobalScopeAliases(scope, {
        "absorb display mode", "absorb mode", "absorb bars",
    }), {
        flag = "hlOverride",
        valueAliases = ABSORB_MODE_ALIASES,
        apply = ApplyAbsorbBars,
        reason = "MSUF_ASSISTANT_SCOPED_ABSORB_MODE",
    })
    RegisterScopedMappedEnum("barScope", scope, "absorbAnchorMode", "absorbAnchor", "Absorb Bar Anchor", "right", ABSORB_ANCHOR_VALUES, ABSORB_ANCHOR_STORAGE, GlobalScopeAliases(scope, {
        "absorb bar anchor", "absorb anchor", "absorb anchoring",
    }), {
        flag = "hlOverride",
        valueAliases = ABSORB_ANCHOR_ALIASES,
        apply = ApplyAbsorbBars,
        reason = "MSUF_ASSISTANT_SCOPED_ABSORB_ANCHOR",
    })
    RegisterScopedSetting("barScope", scope, "overAbsorbOverlay", "overAbsorbOverlay", "Over-Absorb Overlay", "boolean", false, GlobalScopeAliases(scope, {
        "over absorb overlay", "over-absorb overlay", "over absorb glow", "overshield overlay",
        "full hp absorb overlay", "full health absorb overlay",
    }), {
        flag = "hlOverride",
        apply = ApplyAbsorbBars,
        reason = "MSUF_ASSISTANT_SCOPED_OVER_ABSORB_OVERLAY",
    })
    RegisterScopedSetting("barScope", scope, "fullHealthAbsorbStripe", "fullHealthAbsorbStripe", "Full-Health Absorb Stripe", "boolean", false, GlobalScopeAliases(scope, {
        "full-health absorb stripe", "full health absorb stripe", "full hp absorb stripe",
        "absorb stripe at full health", "absorb stripe on full health",
    }), {
        flag = "hlOverride",
        apply = ApplyAbsorbBars,
        reason = "MSUF_ASSISTANT_SCOPED_FULL_HEALTH_ABSORB_STRIPE",
    })
    RegisterScopedSetting("barScope", scope, "absorbBarOpacity", "absorbOpacity", "Absorb Bar Opacity", "number", 0.75, GlobalScopeAliases(scope, {
        "absorb bar opacity", "absorb opacity", "absorb alpha",
    }), {
        flag = "hlOverride",
        min = 0,
        max = 1,
        step = 0.05,
        percent = true,
        apply = ApplyAbsorbBars,
        reason = "MSUF_ASSISTANT_SCOPED_ABSORB_OPACITY",
    })
    RegisterScopedSetting("barScope", scope, "absorbBarTexture", "absorbTexture", "Absorb Bar Texture", "string", "", GlobalScopeAliases(scope, {
        "absorb bar texture", "absorb texture",
    }), {
        flag = "hlOverride",
        normalizeValue = NormalizeTextureKeyForAssistant,
        apply = ApplyAbsorbBars,
        reason = "MSUF_ASSISTANT_SCOPED_ABSORB_TEXTURE",
    })
    RegisterScopedSetting("barScope", scope, "healAbsorbBarTexture", "healAbsorbTexture", "Heal Absorb Bar Texture", "string", "", GlobalScopeAliases(scope, {
        "heal absorb texture", "heal-absorb texture", "heal absorb bar texture",
    }), {
        flag = "hlOverride",
        normalizeValue = NormalizeTextureKeyForAssistant,
        apply = ApplyAbsorbBars,
        reason = "MSUF_ASSISTANT_SCOPED_HEAL_ABSORB_TEXTURE",
    })
    RegisterScopedSetting("barScope", scope, "healAbsorbBarOpacity", "healAbsorbOpacity", "Heal Absorb Bar Opacity", "number", 1, GlobalScopeAliases(scope, {
        "heal absorb opacity", "heal-absorb opacity", "heal absorb bar opacity",
    }), {
        flag = "hlOverride",
        min = 0,
        max = 1,
        step = 0.05,
        percent = true,
        apply = ApplyAbsorbBars,
        reason = "MSUF_ASSISTANT_SCOPED_HEAL_ABSORB_OPACITY",
    })
    RegisterScopedSetting("barScope", scope, "barOutlineThickness", "outline", "Bar Outline Thickness", "number", 1, GlobalScopeAliases(scope, {
        "bar outline thickness", "bar outline", "frame outline thickness", "bar border thickness",
    }), {
        flag = "hlOverride",
        shared = "bars",
        min = 0,
        max = 8,
        apply = ApplyBarOutline,
        reason = "MSUF_ASSISTANT_SCOPED_BAR_OUTLINE",
    })
    RegisterScopedSetting("barScope", scope, "barOutlineColorA", "barOutlineOpacity", "Bar Outline Opacity", "number", 1, GlobalScopeAliases(scope, {
        "bar outline opacity", "bar outline alpha", "frame outline opacity", "frame outline alpha",
        "bar border opacity", "bar border alpha", "frame border opacity", "frame border alpha",
        "outline opacity", "outline alpha",
    }), {
        flag = "hlOverride",
        min = 0,
        max = 1,
        step = 0.05,
        percent = true,
        apply = ApplyBarOutline,
        reason = "MSUF_ASSISTANT_SCOPED_BAR_OUTLINE_OPACITY",
        description = "Controls the scoped alpha channel for the bar/frame outline color.",
    })
    RegisterScopedSetting("barScope", scope, "highlightBorderThickness", "highlightBorder", "Highlight Border Thickness", "number", 2, GlobalScopeAliases(scope, {
        "highlight border thickness", "highlight border size", "aggro border size", "dispel border size",
    }), {
        flag = "hlOverride",
        min = 1,
        max = 30,
        apply = ApplyHighlightBorders,
        reason = "MSUF_ASSISTANT_SCOPED_HIGHLIGHT_BORDER",
    })
    RegisterScopedMappedEnum("barScope", scope, "aggroOutlineMode", "aggroBorder", "Aggro Border", "on", ON_OFF_VALUES, ON_OFF_STORAGE, GlobalScopeAliases(scope, {
        "aggro border", "threat border", "aggro outline",
    }), {
        flag = "hlOverride",
        valueAliases = ON_OFF_ALIASES,
        apply = ApplyAggroBorder,
        reason = "MSUF_ASSISTANT_SCOPED_AGGRO_BORDER",
    })
    RegisterScopedSetting("barScope", scope, "aggroMode", "aggroMode", "Aggro Shows For", "enum", "ALL", GlobalScopeAliases(scope, {
        "aggro shows for", "aggro role filter", "aggro non tanks", "aggro not tank", "threat non tanks",
    }), {
        flag = "hlOverride",
        values = AGGRO_MODE_VALUES,
        valueAliases = AGGRO_MODE_ALIASES,
        apply = ApplyAggroBorder,
        reason = "MSUF_ASSISTANT_SCOPED_AGGRO_MODE",
    })
    RegisterScopedMappedEnum("barScope", scope, "dispelOutlineMode", "dispelBorder", "Dispel Border", "on", ON_OFF_VALUES, ON_OFF_STORAGE, GlobalScopeAliases(scope, {
        "dispel border", "dispellable border", "dispel outline",
    }), {
        flag = "hlOverride",
        valueAliases = ON_OFF_ALIASES,
        apply = ApplyDispelPurgeBorder,
        reason = "MSUF_ASSISTANT_SCOPED_DISPEL_BORDER",
    })
    RegisterScopedSetting("barScope", scope, "dispelBorderTrigger", "dispelBorderTrigger", "Dispel Border Detects", "enum", "DISPEL_TYPE", GlobalScopeAliases(scope, {
        "dispel border detects", "dispel border trigger", "dispel detection",
    }), {
        flag = "hlOverride",
        values = DISPEL_TRIGGER_VALUES,
        valueAliases = DISPEL_TRIGGER_ALIASES,
        apply = ApplyDispelPurgeBorder,
        reason = "MSUF_ASSISTANT_SCOPED_DISPEL_TRIGGER",
    })
    RegisterScopedMappedEnum("barScope", scope, "purgeOutlineMode", "purgeBorder", "Purge Border", "off", ON_OFF_VALUES, ON_OFF_STORAGE, GlobalScopeAliases(scope, {
        "purge border", "purge outline", "purgeable border",
    }), {
        flag = "hlOverride",
        valueAliases = ON_OFF_ALIASES,
        apply = ApplyDispelPurgeBorder,
        reason = "MSUF_ASSISTANT_SCOPED_PURGE_BORDER",
    })
    RegisterScopedSetting("barScope", scope, "hlPrioEnabled", "highlightPriority", "Custom Highlight Priority", "boolean", false, GlobalScopeAliases(scope, {
        "custom highlight priority", "highlight priority", "border priority", "highlight border priority",
        "highlight prio", "border prio", "custom highlight prio",
    }), {
        flag = "hlOverride",
        apply = ApplyHighlightBorders,
        reason = "MSUF_ASSISTANT_SCOPED_HIGHLIGHT_PRIORITY",
    })

    if GlobalScopeIsGroup(scope) then
        RegisterScopedSetting("barScope", scope, "healPredEnabled", "healPrediction", "Heal Prediction Overlay", "boolean", false, GlobalScopeAliases(scope, {
            "heal prediction", "heal prediction overlay", "incoming heal prediction",
        }), {
            flag = "hlOverride",
            apply = ApplyAbsorbBars,
            reason = "MSUF_ASSISTANT_SCOPED_HEAL_PREDICTION",
        })
        RegisterScopedMappedEnum("barScope", scope, "healPredAnchorMode", "healPredictionAnchor", "Heal Prediction Anchor", "follow", ABSORB_ANCHOR_VALUES, ABSORB_ANCHOR_STORAGE, GlobalScopeAliases(scope, {
            "heal prediction anchor", "heal prediction anchoring", "incoming heal anchor",
        }), {
            flag = "hlOverride",
            valueAliases = ABSORB_ANCHOR_ALIASES,
            apply = ApplyAbsorbBars,
            reason = "MSUF_ASSISTANT_SCOPED_HEAL_PREDICTION_ANCHOR",
        })
    else
        local RegisterScopedUnitDispelOverlaySettings = A.GlobalBarRegistry.RegisterScopedUnitDispelOverlaySettings
        if type(RegisterScopedUnitDispelOverlaySettings) ~= "function" or RegisterScopedUnitDispelOverlaySettings(ctx, scope) ~= true then return false end
    end

    return true
end
