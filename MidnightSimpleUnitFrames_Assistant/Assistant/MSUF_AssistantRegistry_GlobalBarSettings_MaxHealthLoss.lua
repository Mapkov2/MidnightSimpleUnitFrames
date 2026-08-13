-- Assistant Global Bar registry: the Bars page "Maximum Health Loss" section.
-- Loaded before MSUF_AssistantRegistry_GlobalBarSettings.lua; the main file passes shared helpers in.
--
-- The overlay marks the slice of maximum health a debuff took away, so players
-- describe it by what they see ("show me how much max health I lost") rather
-- than by the storage name. Every control the section shows is registered here
-- for the shared scope and for each per-unit/group Bars scope, mirroring how
-- the menu writes through BarScopeGet/BarScopeSet.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalBarRegistry = A.GlobalBarRegistry or {}

-- Order matters: the registry keeps only the first MAX_SETTING_ALIASES of a
-- list, so the wording players actually type has to come before the
-- storage-name variants, not after them.
local ENABLED_ALIASES = {
    "maximum health loss", "max health loss", "maximum health loss overlay",
    "max health loss overlay", "show maximum health loss", "show max health loss",
    "how much maximum health i lost", "how much max health i lost",
    "maximum health i lost", "max health i lost",
    "part of the bar i lost", "part of the bar i lost to a max health debuff",
    "lost to a max health debuff", "max health debuff overlay", "max health debuff",
    "maximum health reduction", "max health reduction", "max hp reduction",
    "lost maximum health", "missing maximum health",
}
local TEXTURE_ALIASES = {
    "maximum health loss texture", "max health loss texture",
    "texture for the maximum health loss overlay", "texture for the max health loss overlay",
    "maximum health loss overlay texture", "max hp loss texture",
    "temp max health texture", "maximum health loss art", "max health loss art",
}
local COLOR_ALIASES = {
    "maximum health loss color", "maximum health loss colour", "max health loss color",
    "max health loss colour", "max hp loss color", "temp max health color",
    "maximum health loss overlay color", "loss color", "lost health color",
    "max health loss part", "maximum health loss part",
}
local OPACITY_ALIASES = {
    "maximum health loss opacity", "max health loss opacity", "max hp loss opacity",
    "temp max health opacity", "maximum health loss overlay opacity",
    "maximum health loss alpha", "max health loss alpha",
    "maximum health loss transparency", "max health loss transparency",
    "maximum health loss more transparent", "max health loss more transparent",
    "fade the maximum health loss overlay", "fade max health loss",
    "maximum health loss stronger", "max health loss stronger",
    "max health loss overlay is too strong", "maximum health loss overlay is too strong",
}
local BACKGROUND_ALIASES = {
    "maximum health loss background opacity", "max health loss background opacity",
    "max hp loss background opacity", "temp max health background opacity",
    "maximum health loss background alpha", "max health loss background alpha",
    "maximum health loss background transparency", "max health loss background",
}

local DEFAULT_R, DEFAULT_G, DEFAULT_B = 0.70, 0.10, 0.10

local function ColorParts(value, r, g, b)
    if type(value) == "table" then
        return tonumber(value.r or value[1]) or r,
            tonumber(value.g or value[2]) or g,
            tonumber(value.b or value[3]) or b
    end
    return r, g, b
end

local function ColorSame(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    local ar, ag, ab = ColorParts(a, -1, -1, -1)
    local br, bg, bb = ColorParts(b, -1, -1, -1)
    return math.abs(ar - br) < 0.004 and math.abs(ag - bg) < 0.004 and math.abs(ab - bb) < 0.004
end

function A.GlobalBarRegistry.RegisterMaxHealthLossSettings(ctx)
    if type(ctx) ~= "table" then return false end

    local Registry = ctx.Registry
    local GeneralDB = ctx.GeneralDB
    local CallGlobal = ctx.CallGlobal
    local ApplyBars = ctx.ApplyBars
    local RegisterGeneralBoolean = ctx.RegisterGeneralBoolean
    local RegisterGeneralNumberSetting = ctx.RegisterGeneralNumberSetting
    local RegisterGeneralString = ctx.RegisterGeneralString
    local RegisterScopedSetting = ctx.RegisterScopedSetting
    local NormalizeTextureKeyForAssistant = ctx.NormalizeTextureKeyForAssistant
    local GLOBAL_SCOPE_ORDER = ctx.GLOBAL_SCOPE_ORDER
    local GlobalScopeAliases = ctx.GlobalScopeAliases
    local GlobalScopeLabel = ctx.GlobalScopeLabel
    local GlobalScopeRead = ctx.GlobalScopeRead
    local GlobalScopeWrite = ctx.GlobalScopeWrite
    local NormalizeGlobalScope = ctx.NormalizeGlobalScope

    if not (Registry and type(Registry.RegisterSetting) == "function") then return false end
    if type(GeneralDB) ~= "function" or type(ApplyBars) ~= "function" then return false end
    if type(RegisterGeneralBoolean) ~= "function" or type(RegisterGeneralNumberSetting) ~= "function" then return false end
    if type(RegisterGeneralString) ~= "function" or type(RegisterScopedSetting) ~= "function" then return false end
    if type(NormalizeTextureKeyForAssistant) ~= "function" then return false end
    if type(GLOBAL_SCOPE_ORDER) ~= "table" or type(GlobalScopeAliases) ~= "function" then return false end
    if type(GlobalScopeRead) ~= "function" or type(GlobalScopeWrite) ~= "function" then return false end
    if type(GlobalScopeLabel) ~= "function" or type(NormalizeGlobalScope) ~= "function" then return false end

    -- The overlay is repainted by its own runtime entry point; ApplyBars alone
    -- redraws the bar but leaves the loss slice at its previous width.
    local function ApplyMaxHealthLoss(reason, scope)
        reason = reason or "MSUF_ASSISTANT_TEMP_MAX_HEALTH"
        if type(CallGlobal) == "function" then
            CallGlobal("MSUF_RefreshTempMaxHealth", scope or "shared", reason)
        end
        ApplyBars(reason)
    end

    local category = "Global / Bars / Maximum Health Loss"

    RegisterGeneralBoolean("tempMaxHealthEnabled", "maxHealthLoss", "Maximum Health Loss", false,
        ENABLED_ALIASES, {
            category = category,
            frameType = "globalBars",
            apply = ApplyMaxHealthLoss,
            reason = "MSUF_ASSISTANT_TEMP_MAX_HEALTH_ENABLED",
            description = "Shows the part of maximum health that a debuff has temporarily taken away, drawn at the end of the health bar.",
        })
    RegisterGeneralString("tempMaxHealthTexture", "maxHealthLossTexture", "Maximum Health Loss Texture", "Solid",
        TEXTURE_ALIASES, {
            category = category,
            frameType = "globalBars",
            apply = ApplyMaxHealthLoss,
            reason = "MSUF_ASSISTANT_TEMP_MAX_HEALTH_TEXTURE",
            normalizeValue = NormalizeTextureKeyForAssistant,
            description = "Art used for the maximum-health loss overlay. Leave empty to follow the foreground bar texture.",
        })
    RegisterGeneralNumberSetting("tempMaxHealthOpacity", "maxHealthLossOpacity", "Maximum Health Loss Opacity", 1, 0.05, 1,
        OPACITY_ALIASES, {
            category = category,
            frameType = "globalBars",
            apply = ApplyMaxHealthLoss,
            reason = "MSUF_ASSISTANT_TEMP_MAX_HEALTH_OPACITY",
            step = 0.05,
            percent = true,
            description = "How opaque the maximum-health loss overlay is drawn.",
        })
    RegisterGeneralNumberSetting("tempMaxHealthBackgroundOpacity", "maxHealthLossBackgroundOpacity",
        "Maximum Health Loss Background Opacity", 0.65, 0, 1, BACKGROUND_ALIASES, {
            category = category,
            frameType = "globalBars",
            apply = ApplyMaxHealthLoss,
            reason = "MSUF_ASSISTANT_TEMP_MAX_HEALTH_BACKGROUND",
            step = 0.05,
            percent = true,
            description = "How opaque the bar background stays underneath the maximum-health loss overlay.",
        })
    Registry:RegisterSetting({
        key = "general.tempMaxHealthColor",
        label = "Maximum Health Loss Color",
        category = category,
        unit = "global",
        frameType = "globalBars",
        attribute = "maxHealthLossColor",
        type = "color",
        aliases = COLOR_ALIASES,
        get = function()
            local g = GeneralDB()
            return {
                r = tonumber(g.tempMaxHealthColorR) or DEFAULT_R,
                g = tonumber(g.tempMaxHealthColorG) or DEFAULT_G,
                b = tonumber(g.tempMaxHealthColorB) or DEFAULT_B,
            }
        end,
        set = function(value)
            local r, g, b = ColorParts(value, DEFAULT_R, DEFAULT_G, DEFAULT_B)
            local db = GeneralDB()
            db.tempMaxHealthColorR, db.tempMaxHealthColorG, db.tempMaxHealthColorB = r, g, b
        end,
        sameValue = ColorSame,
        apply = function() ApplyMaxHealthLoss("MSUF_ASSISTANT_TEMP_MAX_HEALTH_COLOR", "shared") end,
        combatSafe = false,
        description = "Color of the maximum-health loss overlay.",
    })

    for _, scope in ipairs(GLOBAL_SCOPE_ORDER) do
        RegisterScopedSetting("barScope", scope, "tempMaxHealthEnabled", "maxHealthLoss", "Maximum Health Loss",
            "boolean", false, GlobalScopeAliases(scope, ENABLED_ALIASES), {
                flag = "hlOverride",
                apply = ApplyMaxHealthLoss,
                reason = "MSUF_ASSISTANT_SCOPED_TEMP_MAX_HEALTH_ENABLED",
                description = "Shows the temporarily unavailable part of maximum health for this Bars scope.",
            })
        RegisterScopedSetting("barScope", scope, "tempMaxHealthTexture", "maxHealthLossTexture",
            "Maximum Health Loss Texture", "string", "Solid", GlobalScopeAliases(scope, TEXTURE_ALIASES), {
                flag = "hlOverride",
                normalizeValue = NormalizeTextureKeyForAssistant,
                apply = ApplyMaxHealthLoss,
                reason = "MSUF_ASSISTANT_SCOPED_TEMP_MAX_HEALTH_TEXTURE",
            })
        RegisterScopedSetting("barScope", scope, "tempMaxHealthOpacity", "maxHealthLossOpacity",
            "Maximum Health Loss Opacity", "number", 1, GlobalScopeAliases(scope, OPACITY_ALIASES), {
                flag = "hlOverride",
                min = 0.05,
                max = 1,
                step = 0.05,
                percent = true,
                apply = ApplyMaxHealthLoss,
                reason = "MSUF_ASSISTANT_SCOPED_TEMP_MAX_HEALTH_OPACITY",
            })
        RegisterScopedSetting("barScope", scope, "tempMaxHealthBackgroundOpacity", "maxHealthLossBackgroundOpacity",
            "Maximum Health Loss Background Opacity", "number", 0.65, GlobalScopeAliases(scope, BACKGROUND_ALIASES), {
                flag = "hlOverride",
                min = 0,
                max = 1,
                step = 0.05,
                percent = true,
                apply = ApplyMaxHealthLoss,
                reason = "MSUF_ASSISTANT_SCOPED_TEMP_MAX_HEALTH_BACKGROUND",
            })
        local scopeKey = NormalizeGlobalScope(scope)
        Registry:RegisterSetting({
            key = "barScope." .. scopeKey .. ".tempMaxHealthColor",
            label = GlobalScopeLabel(scope) .. " Maximum Health Loss Color",
            category = "Global / Bars / Scoped",
            unit = scopeKey,
            frameType = "globalBars",
            attribute = "maxHealthLossColor",
            type = "color",
            aliases = GlobalScopeAliases(scope, COLOR_ALIASES),
            get = function()
                return {
                    r = tonumber(GlobalScopeRead(scope, "hlOverride", GeneralDB(), "tempMaxHealthColorR", DEFAULT_R)) or DEFAULT_R,
                    g = tonumber(GlobalScopeRead(scope, "hlOverride", GeneralDB(), "tempMaxHealthColorG", DEFAULT_G)) or DEFAULT_G,
                    b = tonumber(GlobalScopeRead(scope, "hlOverride", GeneralDB(), "tempMaxHealthColorB", DEFAULT_B)) or DEFAULT_B,
                }
            end,
            set = function(value)
                local r, g, b = ColorParts(value, DEFAULT_R, DEFAULT_G, DEFAULT_B)
                GlobalScopeWrite(scope, "hlOverride", GeneralDB(), "tempMaxHealthColorR", r)
                GlobalScopeWrite(scope, "hlOverride", GeneralDB(), "tempMaxHealthColorG", g)
                GlobalScopeWrite(scope, "hlOverride", GeneralDB(), "tempMaxHealthColorB", b)
            end,
            sameValue = ColorSame,
            apply = function() ApplyMaxHealthLoss("MSUF_ASSISTANT_SCOPED_TEMP_MAX_HEALTH_COLOR", scope) end,
            combatSafe = false,
        })
    end

    return true
end
