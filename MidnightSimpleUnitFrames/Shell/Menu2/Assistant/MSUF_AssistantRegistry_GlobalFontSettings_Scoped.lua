-- Assistant Global Font scoped detail registry.
-- Loaded before MSUF_AssistantRegistry_GlobalFontSettings.lua; consumed by the global font registry.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

function A.GlobalRegistry.RegisterScopedFontDetailSettings(ctx)
    if type(ctx) ~= "table" then return false end

    local GeneralDB = ctx.GeneralDB
    local ApplyFonts = ctx.ApplyFonts
    local GlobalScopeIsGroup = ctx.GlobalScopeIsGroup
    local GlobalScopeRead = ctx.GlobalScopeRead
    local GlobalScopeWrite = ctx.GlobalScopeWrite
    local RegisterScopedSetting = ctx.RegisterScopedSetting
    local FontContext = ctx.FontContext or {}
    local FontData = FontContext.FontData or {}

    local SCOPED_FONT_CONTROL_SCOPES = FontData.SCOPED_FONT_CONTROL_SCOPES
    local FONT_OUTLINE_VALUES = FontData.FONT_OUTLINE_VALUES
    local FONT_OUTLINE_ALIASES = FontData.FONT_OUTLINE_ALIASES
    local FONT_RENDERING_VALUES = FontData.FONT_RENDERING_VALUES
    local FONT_RENDERING_ALIASES = FontData.FONT_RENDERING_ALIASES
    local FONT_SHADOW_STRENGTH_VALUES = FontData.FONT_SHADOW_STRENGTH_VALUES
    local FONT_SHADOW_STRENGTH_ALIASES = FontData.FONT_SHADOW_STRENGTH_ALIASES
    local CLASS_DEFAULT_VALUES = FontData.CLASS_DEFAULT_VALUES
    local CLASS_DEFAULT_ALIASES = FontData.CLASS_DEFAULT_ALIASES
    local SharedOrScopedAliases = FontContext.SharedOrScopedAliases
    local NormalizeFontTextAlpha = FontContext.NormalizeFontTextAlpha
    local ScopedFontOutline = FontContext.ScopedFontOutline
    local SetScopedFontOutline = FontContext.SetScopedFontOutline
    local ScopedFontNameColor = FontContext.ScopedFontNameColor
    local SetScopedFontNameColor = FontContext.SetScopedFontNameColor

    if type(GeneralDB) ~= "function" or type(RegisterScopedSetting) ~= "function" then return false end
    if type(GlobalScopeIsGroup) ~= "function" or type(GlobalScopeRead) ~= "function" then return false end
    if type(GlobalScopeWrite) ~= "function" then return false end
    if type(SCOPED_FONT_CONTROL_SCOPES) ~= "table" or type(FONT_OUTLINE_VALUES) ~= "table" then return false end
    if type(FONT_OUTLINE_ALIASES) ~= "table" or type(FONT_RENDERING_VALUES) ~= "table" then return false end
    if type(FONT_RENDERING_ALIASES) ~= "table" or type(FONT_SHADOW_STRENGTH_VALUES) ~= "table" then return false end
    if type(FONT_SHADOW_STRENGTH_ALIASES) ~= "table" or type(CLASS_DEFAULT_VALUES) ~= "table" then return false end
    if type(CLASS_DEFAULT_ALIASES) ~= "table" then return false end
    if type(SharedOrScopedAliases) ~= "function" or type(NormalizeFontTextAlpha) ~= "function" then return false end
    if type(ScopedFontOutline) ~= "function" or type(SetScopedFontOutline) ~= "function" then return false end
    if type(ScopedFontNameColor) ~= "function" or type(SetScopedFontNameColor) ~= "function" then return false end
    local RegisterScopedUnitFontTextSettings = A.GlobalRegistry and A.GlobalRegistry.RegisterScopedUnitFontTextSettings
    if type(RegisterScopedUnitFontTextSettings) ~= "function" then return false end

    for _, scope in ipairs(SCOPED_FONT_CONTROL_SCOPES) do
        RegisterScopedSetting("fontScope", scope, "outline", "outline", "Font Outline", "enum", "OUTLINE", SharedOrScopedAliases(scope, {
            "font outline", "text outline", "outline style",
        }), {
            flag = "fontOverride",
            values = FONT_OUTLINE_VALUES,
            valueAliases = FONT_OUTLINE_ALIASES,
            get = ScopedFontOutline,
            set = SetScopedFontOutline,
            apply = ApplyFonts,
            reason = "MSUF_ASSISTANT_FONT_OUTLINE",
        })
        RegisterScopedSetting("fontScope", scope, "fontMonochrome", "rendering", "Rendering", "enum", "SMOOTH", SharedOrScopedAliases(scope, {
            "font rendering", "text rendering", "font smoothing", "text smoothing", "sharp text", "pixel font", "monochrome font",
        }), {
            flag = "fontOverride",
            values = FONT_RENDERING_VALUES,
            valueAliases = FONT_RENDERING_ALIASES,
            get = function(scopeKey) return GlobalScopeRead(scopeKey, "fontOverride", GeneralDB(), "fontMonochrome", false) and "SHARP" or "SMOOTH" end,
            set = function(scopeKey, value) GlobalScopeWrite(scopeKey, "fontOverride", GeneralDB(), "fontMonochrome", value == "SHARP") end,
            apply = ApplyFonts,
            reason = "MSUF_ASSISTANT_FONT_RENDERING",
        })
        RegisterScopedSetting("fontScope", scope, "fontTextAlpha", "textOpacity", "Text Opacity", "number", 1, SharedOrScopedAliases(scope, {
            "text opacity", "font opacity", "text alpha", "font alpha",
        }), {
            flag = "fontOverride",
            min = 0.7,
            max = 1,
            step = 0.05,
            percent = true,
            get = function(scopeKey) return NormalizeFontTextAlpha(GlobalScopeRead(scopeKey, "fontOverride", GeneralDB(), "fontTextAlpha", 1)) end,
            set = function(scopeKey, value) GlobalScopeWrite(scopeKey, "fontOverride", GeneralDB(), "fontTextAlpha", NormalizeFontTextAlpha(value)) end,
            apply = ApplyFonts,
            reason = "MSUF_ASSISTANT_FONT_TEXT_ALPHA",
        })
        RegisterScopedSetting("fontScope", scope, "fontBaselineOffset", "baseline", "Baseline", "number", 0, SharedOrScopedAliases(scope, {
            "text baseline", "font baseline", "baseline offset", "vertical font offset", "font y nudge", "text y nudge",
        }), {
            flag = "fontOverride",
            min = -4,
            max = 4,
            step = 1,
            apply = ApplyFonts,
            reason = "MSUF_ASSISTANT_FONT_BASELINE",
        })
        RegisterScopedSetting("fontScope", scope, "nameColorMode", "nameColor", "Name Text Color Mode", "enum", "DEFAULT", SharedOrScopedAliases(scope, {
            "name color", "name text color", "player name color", "unit name color",
            "name text by class", "name text color by class", "color name by class",
            "color name text by class", "class color name text", "class colored name text",
        }), {
            flag = "fontOverride",
            values = CLASS_DEFAULT_VALUES,
            valueAliases = CLASS_DEFAULT_ALIASES,
            get = ScopedFontNameColor,
            set = SetScopedFontNameColor,
            apply = ApplyFonts,
            reason = "MSUF_ASSISTANT_NAME_COLOR_MODE",
        })
        RegisterScopedSetting("fontScope", scope, "textBackdrop", "textShadow", "Text Shadow", "boolean", true, SharedOrScopedAliases(scope, {
            "text shadow", "font shadow", "shadow text", "shadow",
        }), {
            flag = "fontOverride",
            apply = ApplyFonts,
            reason = "MSUF_ASSISTANT_FONT_SHADOW",
        })
        RegisterScopedSetting("fontScope", scope, "fontShadowStrength", "shadowStrength", "Shadow Strength", "enum", "NORMAL", SharedOrScopedAliases(scope, {
            "shadow strength", "text shadow strength", "font shadow strength", "shadow intensity",
        }), {
            flag = "fontOverride",
            values = FONT_SHADOW_STRENGTH_VALUES,
            valueAliases = FONT_SHADOW_STRENGTH_ALIASES,
            apply = ApplyFonts,
            reason = "MSUF_ASSISTANT_FONT_SHADOW_STRENGTH",
        })
        if not GlobalScopeIsGroup(scope) then
            if RegisterScopedUnitFontTextSettings(ctx, scope) == false then return false end
        end
    end
    return true
end
