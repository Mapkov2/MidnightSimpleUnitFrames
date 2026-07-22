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

local Unpack = unpack or (table and table.unpack)

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
        local isShared = scope == "shared"
        local outlineAliases = {
            "font outline", "text outline", "outline style",
        }
        if isShared then
            outlineAliases[#outlineAliases + 1] = "global font outline"
            outlineAliases[#outlineAliases + 1] = "global text outline"
            outlineAliases[#outlineAliases + 1] = "shared font outline"
            outlineAliases[#outlineAliases + 1] = "shared text outline"
            outlineAliases[#outlineAliases + 1] = "default font outline"
            outlineAliases[#outlineAliases + 1] = "default text outline"
        end
        RegisterScopedSetting("fontScope", scope, "outline", "outline", "Font Outline", "enum", "OUTLINE", SharedOrScopedAliases(scope, {
            Unpack(outlineAliases),
        }), {
            flag = "fontOverride",
            dbScopes = scope == "gf_party" and {
                { scope = "gf_party", dbKey = "fontOutline" },
            } or (scope == "gf_raid" and {
                { scope = "gf_raid", dbKey = "fontOutline" },
                { scope = "gf_mythicraid", dbKey = "fontOutline" },
            } or nil),
            values = FONT_OUTLINE_VALUES,
            valueAliases = FONT_OUTLINE_ALIASES,
            get = ScopedFontOutline,
            set = SetScopedFontOutline,
            dbScopeKeys = GlobalScopeIsGroup(scope) and { "fontOutline" } or { "boldText", "noOutline" },
            apply = ApplyFonts,
            reason = "MSUF_ASSISTANT_FONT_OUTLINE",
        })
        local renderingAliases = {
            "font rendering", "text rendering", "font smoothing", "text smoothing", "sharp text", "pixel font", "monochrome font",
        }
        if isShared then
            renderingAliases[#renderingAliases + 1] = "global font rendering"
            renderingAliases[#renderingAliases + 1] = "global text rendering"
            renderingAliases[#renderingAliases + 1] = "global font smoothing"
            renderingAliases[#renderingAliases + 1] = "global monochrome font"
            renderingAliases[#renderingAliases + 1] = "global font monochrome"
            renderingAliases[#renderingAliases + 1] = "shared font rendering"
            renderingAliases[#renderingAliases + 1] = "shared text rendering"
            renderingAliases[#renderingAliases + 1] = "shared font smoothing"
            renderingAliases[#renderingAliases + 1] = "shared monochrome font"
            renderingAliases[#renderingAliases + 1] = "shared font monochrome"
            renderingAliases[#renderingAliases + 1] = "default font rendering"
            renderingAliases[#renderingAliases + 1] = "default font monochrome"
            renderingAliases[#renderingAliases + 1] = "font outline monochrome"
            renderingAliases[#renderingAliases + 1] = "global font outline monochrome"
            renderingAliases[#renderingAliases + 1] = "shared font outline monochrome"
        end
        RegisterScopedSetting("fontScope", scope, "fontMonochrome", "rendering", "Rendering", "enum", "SMOOTH", SharedOrScopedAliases(scope, {
            Unpack(renderingAliases),
        }), {
            flag = "fontOverride",
            values = FONT_RENDERING_VALUES,
            valueAliases = FONT_RENDERING_ALIASES,
            get = function(scopeKey) return GlobalScopeRead(scopeKey, "fontOverride", GeneralDB(), "fontMonochrome", false) and "SHARP" or "SMOOTH" end,
            set = function(scopeKey, value) GlobalScopeWrite(scopeKey, "fontOverride", GeneralDB(), "fontMonochrome", value == "SHARP") end,
            apply = ApplyFonts,
            reason = "MSUF_ASSISTANT_FONT_RENDERING",
        })
        local opacityAliases = {
            "text opacity", "font opacity", "text alpha", "font alpha",
        }
        if isShared then
            opacityAliases[#opacityAliases + 1] = "global text opacity"
            opacityAliases[#opacityAliases + 1] = "global font opacity"
            opacityAliases[#opacityAliases + 1] = "shared text opacity"
            opacityAliases[#opacityAliases + 1] = "shared font opacity"
        end
        RegisterScopedSetting("fontScope", scope, "fontTextAlpha", "textOpacity", "Text Opacity", "number", 1, SharedOrScopedAliases(scope, {
            Unpack(opacityAliases),
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
        local baselineAliases = {
            "text baseline", "font baseline", "baseline offset", "vertical font offset", "font y nudge", "text y nudge",
        }
        if isShared then
            baselineAliases[#baselineAliases + 1] = "global text baseline"
            baselineAliases[#baselineAliases + 1] = "global font baseline"
            baselineAliases[#baselineAliases + 1] = "global baseline offset"
            baselineAliases[#baselineAliases + 1] = "shared text baseline"
            baselineAliases[#baselineAliases + 1] = "shared font baseline"
            baselineAliases[#baselineAliases + 1] = "shared baseline offset"
        end
        RegisterScopedSetting("fontScope", scope, "fontBaselineOffset", "baseline", "Baseline", "number", 0, SharedOrScopedAliases(scope, {
            Unpack(baselineAliases),
        }), {
            flag = "fontOverride",
            min = -4,
            max = 4,
            step = 1,
            apply = ApplyFonts,
            reason = "MSUF_ASSISTANT_FONT_BASELINE",
        })
        local nameColorAliases = {
            "name color", "name text color", "player name color", "unit name color",
            "name text by class", "name text color by class", "color name by class",
            "color name text by class", "class color name text", "class colored name text",
        }
        if isShared then
            nameColorAliases[#nameColorAliases + 1] = "global name color"
            nameColorAliases[#nameColorAliases + 1] = "global name text color"
            nameColorAliases[#nameColorAliases + 1] = "shared name color"
            nameColorAliases[#nameColorAliases + 1] = "shared name text color"
        end
        RegisterScopedSetting("fontScope", scope, "nameColorMode", "nameColor", "Name Text Color Mode", "enum", "DEFAULT", SharedOrScopedAliases(scope, {
            Unpack(nameColorAliases),
        }), {
            flag = "fontOverride",
            values = CLASS_DEFAULT_VALUES,
            valueAliases = CLASS_DEFAULT_ALIASES,
            get = ScopedFontNameColor,
            set = SetScopedFontNameColor,
            dbScopeKeys = GlobalScopeIsGroup(scope) and { "nameColorMode" } or { "nameClassColor" },
            apply = ApplyFonts,
            reason = "MSUF_ASSISTANT_NAME_COLOR_MODE",
        })
        local shadowAliases = {
            "text shadow", "font shadow", "shadow text", "shadow",
        }
        if isShared then
            shadowAliases[#shadowAliases + 1] = "global text shadow"
            shadowAliases[#shadowAliases + 1] = "global font shadow"
            shadowAliases[#shadowAliases + 1] = "shared text shadow"
            shadowAliases[#shadowAliases + 1] = "shared font shadow"
        end
        RegisterScopedSetting("fontScope", scope, "textBackdrop", "textShadow", "Text Shadow", "boolean", true, SharedOrScopedAliases(scope, {
            Unpack(shadowAliases),
        }), {
            flag = "fontOverride",
            apply = ApplyFonts,
            reason = "MSUF_ASSISTANT_FONT_SHADOW",
        })
        local shadowOpacityAliases = {
            "shadow opacity", "text shadow opacity", "font shadow opacity",
        }
        if isShared then
            shadowOpacityAliases[#shadowOpacityAliases + 1] = "global shadow opacity"
            shadowOpacityAliases[#shadowOpacityAliases + 1] = "global text shadow opacity"
            shadowOpacityAliases[#shadowOpacityAliases + 1] = "shared shadow opacity"
            shadowOpacityAliases[#shadowOpacityAliases + 1] = "shared text shadow opacity"
        end
        RegisterScopedSetting("fontScope", scope, "fontShadowOpacity", "shadowOpacity", "Shadow Opacity", "number", 1, SharedOrScopedAliases(scope, {
            Unpack(shadowOpacityAliases),
        }), {
            flag = "fontOverride",
            min = 0.20,
            max = 1,
            step = 0.05,
            percent = true,
            get = function(scopeKey)
                local alpha = _G.MSUF_ResolveFontShadowMetrics(
                    GlobalScopeRead(scopeKey, "fontOverride", GeneralDB(), "fontShadowOpacity", nil),
                    GlobalScopeRead(scopeKey, "fontOverride", GeneralDB(), "fontShadowDistance", nil),
                    GlobalScopeRead(scopeKey, "fontOverride", GeneralDB(), "fontShadowStrength", nil))
                return alpha
            end,
            set = function(scopeKey, value)
                local alpha = _G.MSUF_ResolveFontShadowMetrics(value, 1)
                alpha = math.floor(alpha * 20 + 0.5) / 20
                GlobalScopeWrite(scopeKey, "fontOverride", GeneralDB(), "fontShadowStrength", nil)
                GlobalScopeWrite(scopeKey, "fontOverride", GeneralDB(), "fontShadowOpacity", alpha)
            end,
            apply = ApplyFonts,
            reason = "MSUF_ASSISTANT_FONT_SHADOW_OPACITY",
        })
        local shadowDistanceAliases = {
            "shadow distance", "text shadow distance", "font shadow distance", "shadow depth", "shadow offset",
        }
        if isShared then
            shadowDistanceAliases[#shadowDistanceAliases + 1] = "global shadow distance"
            shadowDistanceAliases[#shadowDistanceAliases + 1] = "global shadow depth"
            shadowDistanceAliases[#shadowDistanceAliases + 1] = "shared shadow distance"
            shadowDistanceAliases[#shadowDistanceAliases + 1] = "shared shadow depth"
        end
        RegisterScopedSetting("fontScope", scope, "fontShadowDistance", "shadowDistance", "Shadow Distance", "number", 1, SharedOrScopedAliases(scope, {
            Unpack(shadowDistanceAliases),
        }), {
            flag = "fontOverride",
            min = 1,
            max = 2,
            step = 1,
            get = function(scopeKey)
                local _, distance = _G.MSUF_ResolveFontShadowMetrics(
                    GlobalScopeRead(scopeKey, "fontOverride", GeneralDB(), "fontShadowOpacity", nil),
                    GlobalScopeRead(scopeKey, "fontOverride", GeneralDB(), "fontShadowDistance", nil),
                    GlobalScopeRead(scopeKey, "fontOverride", GeneralDB(), "fontShadowStrength", nil))
                return distance
            end,
            set = function(scopeKey, value)
                local _, distance = _G.MSUF_ResolveFontShadowMetrics(1, value)
                GlobalScopeWrite(scopeKey, "fontOverride", GeneralDB(), "fontShadowStrength", nil)
                GlobalScopeWrite(scopeKey, "fontOverride", GeneralDB(), "fontShadowDistance", distance)
            end,
            apply = ApplyFonts,
            reason = "MSUF_ASSISTANT_FONT_SHADOW_DISTANCE",
        })
        local shadowStrengthAliases = {
            "shadow strength", "text shadow strength", "font shadow strength", "shadow intensity",
            "soft shadow preset", "normal shadow preset", "deep shadow preset",
        }
        if isShared then
            shadowStrengthAliases[#shadowStrengthAliases + 1] = "global shadow strength"
            shadowStrengthAliases[#shadowStrengthAliases + 1] = "global text shadow strength"
            shadowStrengthAliases[#shadowStrengthAliases + 1] = "global font shadow strength"
            shadowStrengthAliases[#shadowStrengthAliases + 1] = "shared shadow strength"
            shadowStrengthAliases[#shadowStrengthAliases + 1] = "shared text shadow strength"
            shadowStrengthAliases[#shadowStrengthAliases + 1] = "shared font shadow strength"
            shadowStrengthAliases[#shadowStrengthAliases + 1] = "global shadow preset"
            shadowStrengthAliases[#shadowStrengthAliases + 1] = "shared shadow preset"
        end
        RegisterScopedSetting("fontScope", scope, "fontShadowStrength", "shadowStrength", "Legacy Shadow Preset", "enum", "NORMAL", SharedOrScopedAliases(scope, {
            Unpack(shadowStrengthAliases),
        }), {
            flag = "fontOverride",
            values = FONT_SHADOW_STRENGTH_VALUES,
            valueAliases = FONT_SHADOW_STRENGTH_ALIASES,
            apply = ApplyFonts,
            reason = "MSUF_ASSISTANT_FONT_SHADOW_STRENGTH",
            menuControlDisposition = "standalone",
            menuControlDispositionReason = "Legacy shadow presets remain Assistant-compatible, while Menu2 exposes the replacement opacity and distance controls.",
            menuControlDispositionEvidence = "MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GlobalFonts.lua:82-96",
        })
        if not GlobalScopeIsGroup(scope) then
            if RegisterScopedUnitFontTextSettings(ctx, scope) == false then return false end
        end
    end
    return true
end
