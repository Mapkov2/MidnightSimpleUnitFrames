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
    local ApplyHighlightBorders = ctx.ApplyHighlightBorders
    local RegisterScopedSetting = ctx.RegisterScopedSetting
    local RegisterScopedOverlaySettings = A.GlobalBarRegistry.RegisterScopedOverlaySettings
    local GLOBAL_SCOPE_ORDER = ctx.GLOBAL_SCOPE_ORDER
    local GlobalScopeHasOverride = ctx.GlobalScopeHasOverride
    local GlobalScopeSetOverride = ctx.GlobalScopeSetOverride
    local GlobalScopeRead = ctx.GlobalScopeRead
    local GlobalScopeWrite = ctx.GlobalScopeWrite
    local GlobalScopeAliases = ctx.GlobalScopeAliases
    local NormalizeTextureKeyForAssistant = ctx.NormalizeTextureKeyForAssistant
    local NormalizeBorderKeyForAssistant = ctx.NormalizeBorderKeyForAssistant
    local GRADIENT_DIRECTION_VALUES = ctx.GRADIENT_DIRECTION_VALUES
    local GRADIENT_DIRECTION_KEYS = ctx.GRADIENT_DIRECTION_KEYS
    local GRADIENT_DIRECTION_ALIASES = ctx.GRADIENT_DIRECTION_ALIASES
    local POWER_GRADIENT_DIRECTION_KEYS = ctx.POWER_GRADIENT_DIRECTION_KEYS

    if type(GeneralDB) ~= "function" or type(ApplyHighlightBorders) ~= "function" then return false end
    if type(POWER_GRADIENT_DIRECTION_KEYS) ~= "table" then return false end
    if type(RegisterScopedSetting) ~= "function" or type(RegisterScopedOverlaySettings) ~= "function" then return false end
    if type(GLOBAL_SCOPE_ORDER) ~= "table" or type(GlobalScopeAliases) ~= "function" then return false end
    if type(GlobalScopeHasOverride) ~= "function" then return false end
    if type(GlobalScopeSetOverride) ~= "function" or type(GlobalScopeRead) ~= "function" or type(GlobalScopeWrite) ~= "function" then return false end
    if type(NormalizeTextureKeyForAssistant) ~= "function" or type(NormalizeBorderKeyForAssistant) ~= "function" then return false end
    if type(GRADIENT_DIRECTION_VALUES) ~= "table" or type(GRADIENT_DIRECTION_KEYS) ~= "table" then return false end

    local HIGHLIGHT_KEYS = { "dispel", "aggro", "purge", "bossTarget" }
    local HIGHLIGHT_ALLOWED = { dispel = true, aggro = true, purge = true, bossTarget = true }
    local HIGHLIGHT_ALIASES = {
        Dispel = "dispel", DISPEL = "dispel", Aggro = "aggro", AGGRO = "aggro",
        Purge = "purge", PURGE = "purge", BossTarget = "bossTarget", BOSS_TARGET = "bossTarget",
        ["Boss Target"] = "bossTarget", ["boss target"] = "bossTarget", boss_target = "bossTarget",
        bosstarget = "bossTarget", magic = "dispel", curse = "dispel", disease = "dispel",
        poison = "dispel", bleed = "dispel",
    }
    local HIGHLIGHT_VALUES = {}
    local function BuildPermutations(prefix, used)
        if #prefix == #HIGHLIGHT_KEYS then
            HIGHLIGHT_VALUES[#HIGHLIGHT_VALUES + 1] = table.concat(prefix, ",")
            return
        end
        for i = 1, #HIGHLIGHT_KEYS do
            local key = HIGHLIGHT_KEYS[i]
            if not used[key] then
                used[key], prefix[#prefix + 1] = true, key
                BuildPermutations(prefix, used)
                prefix[#prefix], used[key] = nil, nil
            end
        end
    end
    BuildPermutations({}, {})

    local function CopyArray(value)
        local out = {}
        for i = 1, #(type(value) == "table" and value or {}) do out[i] = value[i] end
        return out
    end

    local function NormalizeHighlightOrder(value)
        local source = {}
        if type(value) == "string" then
            for token in value:gmatch("[^,]+") do source[#source + 1] = token:match("^%s*(.-)%s*$") end
        elseif type(value) == "table" then
            for i = 1, #value do source[#source + 1] = value[i] end
        else
            return nil
        end
        local out, used = {}, {}
        for i = 1, #source do
            local raw = source[i]
            local key = type(raw) == "string" and (HIGHLIGHT_ALIASES[raw] or HIGHLIGHT_ALIASES[raw:lower()] or raw) or nil
            if not HIGHLIGHT_ALLOWED[key] or used[key] then return nil end
            used[key], out[#out + 1] = true, key
        end
        if #out ~= #HIGHLIGHT_KEYS then return nil end
        return out
    end

    local function PhysicalScopeKeys(scope)
        if scope == "shared" then return { "general" } end
        if scope == "gf_raid" then return { "gf_raid", "gf_mythicraid" } end
        return { scope }
    end

    local function CaptureHighlightState(scope)
        local db = _G.MSUF_DB or {}
        local state = { scope = scope, entries = {} }
        local keys = PhysicalScopeKeys(scope)
        for i = 1, #keys do
            local key = keys[i]
            local owner = type(db[key]) == "table" and db[key] or {}
            state.entries[i] = {
                key = key,
                hasOrder = owner.hlPrioOrder ~= nil,
                order = CopyArray(owner.hlPrioOrder),
                hasOverride = owner.hlOverride ~= nil,
                override = owner.hlOverride,
                hasLegacy = owner.highlightPrioOrder ~= nil,
                legacy = CopyArray(owner.highlightPrioOrder),
            }
        end
        return state
    end

    local function RestoreHighlightState(state)
        if type(state) ~= "table" or type(state.entries) ~= "table" then return false end
        local db = _G.MSUF_DB
        if type(db) ~= "table" then return false end
        for i = 1, #state.entries do
            local entry = state.entries[i]
            if type(entry) ~= "table" or type(entry.key) ~= "string" then return false end
            db[entry.key] = type(db[entry.key]) == "table" and db[entry.key] or {}
            local owner = db[entry.key]
            owner.hlPrioOrder = entry.hasOrder and CopyArray(entry.order) or nil
            owner.hlOverride = entry.hasOverride and entry.override or nil
            owner.highlightPrioOrder = entry.hasLegacy and CopyArray(entry.legacy) or nil
        end
        return true
    end

    local function RegisterHighlightPriority(scope)
        local dbScopes
        if scope == "shared" then
            dbScopes = {
                { scope = "general", dbKey = "hlPrioOrder" },
                { scope = "general", dbKey = "highlightPrioOrder" },
            }
        end
        RegisterScopedSetting("barScope", scope, "hlPrioOrder", "highlightPriorityOrder",
            "Highlight Priority Order", "enum", HIGHLIGHT_VALUES[1], GlobalScopeAliases(scope, {
                "highlight priority order", "border priority order", "highlight order", "border order",
            }), {
                flag = "hlOverride",
                values = HIGHLIGHT_VALUES,
                dbScopes = dbScopes,
                dbScopeKeys = { "hlPrioOrder" },
                get = function(scopeKey)
                    local raw = GlobalScopeRead(scopeKey, "hlOverride", GeneralDB(), "hlPrioOrder", nil)
                    if type(raw) ~= "table" and scopeKey == "shared" then raw = GeneralDB().highlightPrioOrder end
                    local order = NormalizeHighlightOrder(raw) or CopyArray(HIGHLIGHT_KEYS)
                    return table.concat(order, ",")
                end,
                set = function(scopeKey, value)
                    local order = NormalizeHighlightOrder(value)
                    if not order then error("invalid highlight priority order") end
                    GlobalScopeWrite(scopeKey, "hlOverride", GeneralDB(), "hlPrioOrder", CopyArray(order))
                    if scopeKey == "shared" then GeneralDB().highlightPrioOrder = CopyArray(order) end
                end,
                captureTransactionState = function() return CaptureHighlightState(scope) end,
                restoreTransactionState = RestoreHighlightState,
                apply = ApplyHighlightBorders,
                reason = "MSUF_ASSISTANT_HIGHLIGHT_PRIORITY_ORDER",
                description = "Sets the complete four-item highlight priority as one validated order.",
            })
    end

    RegisterHighlightPriority("shared")
    for _, scope in ipairs(GLOBAL_SCOPE_ORDER) do
        RegisterHighlightPriority(scope)
        RegisterScopedSetting("barScope", scope, "override", "override", "Bars Override", "boolean", false, GlobalScopeAliases(scope, {
            "bars override", "custom bars", "custom bar settings", "bar custom settings",
            "frame have its own bar settings", "have its own bar settings",
            "frames have their own bar settings",
        }), {
            flag = "hlOverride",
            get = function(scopeKey) return GlobalScopeHasOverride(scopeKey, "hlOverride") end,
            set = function(scopeKey, value) GlobalScopeSetOverride(scopeKey, "hlOverride", value and true or false) end,
            dbScopeKeys = { "hlOverride" },
            apply = ApplyBars,
            reason = "MSUF_ASSISTANT_BARS_OVERRIDE",
            description = "Enables or disables custom Global Bars settings for this target.",
        })
        if scope == "gf_party" or scope == "gf_raid" then
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
        end
        RegisterScopedSetting("barScope", scope, "enableGradient", "healthGradient", "HP Bar Gradient", "boolean", false, GlobalScopeAliases(scope, {
            "hp bar gradient", "health bar gradient", "health gradient", "hp gradient",
            "bar gradient", "bars gradient", "bar gradients", "unitframe gradient",
            "unit frame gradient", "unitframe bar gradient", "unit frame bar gradient",
        }), {
            flag = "hlOverride",
            apply = ApplyBarGradients,
            reason = "MSUF_ASSISTANT_SCOPED_HP_GRADIENT",
        })
        RegisterScopedSetting("barScope", scope, "enablePowerGradient", "powerGradient", "Power Bar Gradient", "boolean", false, GlobalScopeAliases(scope, {
            "power bar gradient", "power gradient", "mana gradient", "mana bar gradient",
            "resource gradient", "resource bar gradient",
        }), {
            flag = "hlOverride",
            apply = ApplyBarGradients,
            reason = "MSUF_ASSISTANT_SCOPED_POWER_GRADIENT",
        })
        RegisterScopedSetting("barScope", scope, "gradientStrength", "gradientStrength", "Bar Gradient Strength", "number", 0.45, GlobalScopeAliases(scope, {
            "gradient strength", "bar gradient strength", "health gradient strength", "hp gradient strength",
            "health bar gradient strength", "gradient intensity",
        }), {
            flag = "hlOverride",
            min = 0,
            max = 1,
            step = 0.05,
            percent = true,
            apply = ApplyBarGradients,
            reason = "MSUF_ASSISTANT_SCOPED_GRADIENT_STRENGTH",
        })
        RegisterScopedSetting("barScope", scope, "powerGradientStrength", "powerGradientStrength",
            "Power Gradient Strength", "number", 0.45, GlobalScopeAliases(scope, {
                "power gradient strength", "power bar gradient strength", "mana gradient strength",
                "resource gradient strength", "power gradient intensity",
            }), {
                flag = "hlOverride",
                min = 0,
                max = 1,
                step = 0.05,
                percent = true,
                apply = ApplyBarGradients,
                reason = "MSUF_ASSISTANT_SCOPED_POWER_GRADIENT_STRENGTH",
            })
        RegisterScopedSetting("barScope", scope, "gradientDirection", "gradientDirection", "Bar Gradient Direction", "enum", "RIGHT", GlobalScopeAliases(scope, {
            "gradient direction", "bar gradient direction", "health gradient direction",
            "health bar gradient direction", "hp gradient direction",
            "bar right gradient", "bar right direction", "right bar gradient",
            "gradient from right", "gradient from left", "gradient from top", "gradient from bottom",
            "bar gradient from right", "bar gradient from left", "bar gradient from top", "bar gradient from bottom",
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
            dbScopeKeys = {
                "gradientDirRight", "gradientDirLeft", "gradientDirUp", "gradientDirDown", "gradientDirection",
            },
            apply = ApplyBarGradients,
            reason = "MSUF_ASSISTANT_SCOPED_GRADIENT_DIRECTION",
        })
        RegisterScopedSetting("barScope", scope, "powerGradientDirection", "powerGradientDirection",
            "Power Gradient Direction", "enum", "RIGHT", GlobalScopeAliases(scope, {
                "power gradient direction", "power bar gradient direction", "mana gradient direction",
                "resource gradient direction",
            }), {
                flag = "hlOverride",
                values = GRADIENT_DIRECTION_VALUES,
                valueAliases = GRADIENT_DIRECTION_ALIASES,
                get = function(scopeKey)
                    for i = 1, #GRADIENT_DIRECTION_VALUES do
                        local value = GRADIENT_DIRECTION_VALUES[i]
                        if GlobalScopeRead(scopeKey, "hlOverride", GeneralDB(),
                            POWER_GRADIENT_DIRECTION_KEYS[value], false) == true then return value end
                    end
                    -- With no explicit power direction the runtime follows the
                    -- health direction, so report the direction the bar shows.
                    local value = GlobalScopeRead(scopeKey, "hlOverride", GeneralDB(), "powerGradientDirection", nil)
                        or GlobalScopeRead(scopeKey, "hlOverride", GeneralDB(), "gradientDirection", "RIGHT")
                    return POWER_GRADIENT_DIRECTION_KEYS[value] and value or "RIGHT"
                end,
                set = function(scopeKey, value)
                    if not POWER_GRADIENT_DIRECTION_KEYS[value] then value = "RIGHT" end
                    for i = 1, #GRADIENT_DIRECTION_VALUES do
                        local dir = GRADIENT_DIRECTION_VALUES[i]
                        GlobalScopeWrite(scopeKey, "hlOverride", GeneralDB(),
                            POWER_GRADIENT_DIRECTION_KEYS[dir], dir == value)
                    end
                    GlobalScopeWrite(scopeKey, "hlOverride", GeneralDB(), "powerGradientDirection", value)
                end,
                dbScopeKeys = {
                    "powerGradientDirRight", "powerGradientDirLeft", "powerGradientDirUp",
                    "powerGradientDirDown", "powerGradientDirection",
                },
                apply = ApplyBarGradients,
                reason = "MSUF_ASSISTANT_SCOPED_POWER_GRADIENT_DIRECTION",
                menuControlDisposition = "standalone",
                menuControlDispositionReason = "Menu2 exposes power-gradient direction as four independent toggle actions; this scoped Assistant enum is their atomic single-direction controller.",
                menuControlDispositionEvidence = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalBars.lua BuildDirectionPad",
            })
        RegisterScopedSetting("barScope", scope, "barOutlineLayer", "layer", "Bar Outline Layer", "number", 0, GlobalScopeAliases(scope, {
            "bar outline strata", "bar outline layer", "frame outline strata", "frame outline layer",
            "outline strata", "outline layer",
        }), {
            flag = "hlOverride",
            shared = "bars",
            min = 0,
            max = 30,
            step = 1,
            apply = ctx.ApplyBarOutline,
            reason = "MSUF_ASSISTANT_SCOPED_BAR_OUTLINE_LAYER",
            description = "Controls this scope's bar and frame outline Layer (0-30).",
        })
        RegisterScopedSetting("barScope", scope, "barOutlineTexture", "outlineTexture", "Frame Outline Style", "string", "", GlobalScopeAliases(scope, {
            "frame outline style", "outline style", "true outline", "frame outline texture", "bar outline texture", "outline texture", "border texture",
        }), {
            flag = "hlOverride",
            shared = "bars",
            mediaType = "border",
            normalizeValue = NormalizeBorderKeyForAssistant,
            apply = ctx.ApplyBarOutline,
            reason = "MSUF_ASSISTANT_SCOPED_BAR_OUTLINE_TEXTURE",
            description = "Optional texture for this scope's square frame outline. Empty keeps the classic solid color; rounded frames always keep the solid outline color.",
        })
        if RegisterScopedOverlaySettings(ctx, scope) == false then return false end
    end

    return true
end
