-- Assistant Global Bar scoped registry: per-scope bar overrides and texture/gradient controls.
-- Loaded before MSUF_AssistantRegistry_GlobalBarSettings.lua; the main file passes shared helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalBarRegistry = A.GlobalBarRegistry or {}

function A.GlobalBarRegistry.RegisterScopedBarSettings(ctx)
    if type(ctx) ~= "table" then return false end

    local GeneralDB = ctx.GeneralDB
    local ApplyBars = ctx.ApplyBars
    local ApplyBarGradients = ctx.ApplyBarGradients
    local RegisterScopedSetting = ctx.RegisterScopedSetting
    local RegisterScopedOverlaySettings = A.GlobalBarRegistry.RegisterScopedOverlaySettings
    local GLOBAL_SCOPE_ORDER = ctx.GLOBAL_SCOPE_ORDER
    local GlobalScopeHasOverride = ctx.GlobalScopeHasOverride
    local GlobalScopeSetOverride = ctx.GlobalScopeSetOverride
    local GlobalScopeRead = ctx.GlobalScopeRead
    local GlobalScopeWrite = ctx.GlobalScopeWrite
    local GlobalScopeAliases = ctx.GlobalScopeAliases
    local NormalizeTextureKeyForAssistant = ctx.NormalizeTextureKeyForAssistant
    local GRADIENT_DIRECTION_VALUES = ctx.GRADIENT_DIRECTION_VALUES
    local GRADIENT_DIRECTION_KEYS = ctx.GRADIENT_DIRECTION_KEYS
    local GRADIENT_DIRECTION_ALIASES = ctx.GRADIENT_DIRECTION_ALIASES

    if type(GeneralDB) ~= "function" then return false end
    if type(RegisterScopedSetting) ~= "function" or type(RegisterScopedOverlaySettings) ~= "function" then return false end
    if type(GLOBAL_SCOPE_ORDER) ~= "table" or type(GlobalScopeAliases) ~= "function" then return false end
    if type(GlobalScopeHasOverride) ~= "function" then return false end
    if type(GlobalScopeSetOverride) ~= "function" or type(GlobalScopeRead) ~= "function" or type(GlobalScopeWrite) ~= "function" then return false end
    if type(NormalizeTextureKeyForAssistant) ~= "function" then return false end
    if type(GRADIENT_DIRECTION_VALUES) ~= "table" or type(GRADIENT_DIRECTION_KEYS) ~= "table" then return false end

    for _, scope in ipairs(GLOBAL_SCOPE_ORDER) do
        RegisterScopedSetting("barScope", scope, "override", "override", "Bars Override", "boolean", false, GlobalScopeAliases(scope, {
            "bars override", "custom bars", "custom bar settings", "bar custom settings",
        }), {
            flag = "hlOverride",
            get = function(scopeKey) return GlobalScopeHasOverride(scopeKey, "hlOverride") end,
            set = function(scopeKey, value) GlobalScopeSetOverride(scopeKey, "hlOverride", value and true or false) end,
            apply = ApplyBars,
            reason = "MSUF_ASSISTANT_BARS_OVERRIDE",
            description = "Enables or disables custom Global Bars settings for this target.",
        })
        RegisterScopedSetting("barScope", scope, "barTexture", "texture", "Bar Texture", "string", "Blizzard", GlobalScopeAliases(scope, {
            "bar texture", "bars texture", "global bar texture", "global bars texture", "health bar texture", "power bar texture", "foreground bar texture", "foreground texture", "foreground bar texture",
        }), {
            flag = "hlOverride",
            normalizeValue = NormalizeTextureKeyForAssistant,
            apply = ApplyBars,
            reason = "MSUF_ASSISTANT_SCOPED_BAR_TEXTURE",
        })
        RegisterScopedSetting("barScope", scope, "barBackgroundTexture", "backgroundTexture", "Bar Background Texture", "string", "", GlobalScopeAliases(scope, {
            "bar background texture", "background bar texture", "bar bg texture",
        }), {
            flag = "hlOverride",
            normalizeValue = NormalizeTextureKeyForAssistant,
            apply = ApplyBars,
            reason = "MSUF_ASSISTANT_SCOPED_BAR_BACKGROUND_TEXTURE",
        })
        RegisterScopedSetting("barScope", scope, "enableGradient", "healthGradient", "HP Bar Gradient", "boolean", false, GlobalScopeAliases(scope, {
            "hp bar gradient", "health bar gradient", "health gradient", "hp gradient",
        }), {
            flag = "hlOverride",
            apply = ApplyBarGradients,
            reason = "MSUF_ASSISTANT_SCOPED_HP_GRADIENT",
        })
        RegisterScopedSetting("barScope", scope, "enablePowerGradient", "powerGradient", "Power Bar Gradient", "boolean", false, GlobalScopeAliases(scope, {
            "power bar gradient", "power gradient", "mana gradient",
        }), {
            flag = "hlOverride",
            apply = ApplyBarGradients,
            reason = "MSUF_ASSISTANT_SCOPED_POWER_GRADIENT",
        })
        RegisterScopedSetting("barScope", scope, "gradientStrength", "gradientStrength", "Bar Gradient Strength", "number", 0.45, GlobalScopeAliases(scope, {
            "gradient strength", "bar gradient strength", "health gradient strength", "power gradient strength",
        }), {
            flag = "hlOverride",
            min = 0,
            max = 1,
            step = 0.05,
            percent = true,
            apply = ApplyBarGradients,
            reason = "MSUF_ASSISTANT_SCOPED_GRADIENT_STRENGTH",
        })
        RegisterScopedSetting("barScope", scope, "gradientDirection", "gradientDirection", "Bar Gradient Direction", "enum", "RIGHT", GlobalScopeAliases(scope, {
            "gradient direction", "bar gradient direction", "health gradient direction", "power gradient direction",
            "bar right gradient", "bar right direction", "right bar gradient",
        }), {
            flag = "hlOverride",
            values = GRADIENT_DIRECTION_VALUES,
            valueAliases = GRADIENT_DIRECTION_ALIASES,
            get = function(scopeKey)
                for i = 1, #GRADIENT_DIRECTION_VALUES do
                    local value = GRADIENT_DIRECTION_VALUES[i]
                    if GlobalScopeRead(scopeKey, "hlOverride", GeneralDB(), GRADIENT_DIRECTION_KEYS[value], false) == true then return value end
                end
                local value = GlobalScopeRead(scopeKey, "hlOverride", GeneralDB(), "gradientDirection", "RIGHT")
                return GRADIENT_DIRECTION_KEYS[value] and value or "RIGHT"
            end,
            set = function(scopeKey, value)
                if not GRADIENT_DIRECTION_KEYS[value] then value = "RIGHT" end
                for i = 1, #GRADIENT_DIRECTION_VALUES do
                    local dir = GRADIENT_DIRECTION_VALUES[i]
                    GlobalScopeWrite(scopeKey, "hlOverride", GeneralDB(), GRADIENT_DIRECTION_KEYS[dir], dir == value)
                end
                GlobalScopeWrite(scopeKey, "hlOverride", GeneralDB(), "gradientDirection", value)
            end,
            apply = ApplyBarGradients,
            reason = "MSUF_ASSISTANT_SCOPED_GRADIENT_DIRECTION",
        })
        if RegisterScopedOverlaySettings(ctx, scope) == false then return false end
    end

    return true
end
