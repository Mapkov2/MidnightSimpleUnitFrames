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
    local RegisterBarsString = ctx.RegisterBarsString
    local ApplyBars = ctx.ApplyBars
    local ApplyBarGradients = ctx.ApplyBarGradients
    local NormalizeTextureKeyForAssistant = ctx.NormalizeTextureKeyForAssistant
    local NormalizeBorderKeyForAssistant = ctx.NormalizeBorderKeyForAssistant
    local GRADIENT_DIRECTION_VALUES = ctx.GRADIENT_DIRECTION_VALUES
    local GRADIENT_DIRECTION_KEYS = ctx.GRADIENT_DIRECTION_KEYS
    local GRADIENT_DIRECTION_ALIASES = ctx.GRADIENT_DIRECTION_ALIASES

    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(GeneralDB) ~= "function" or type(RegisterGeneralString) ~= "function" then return end
    if type(RegisterGeneralBoolean) ~= "function" or type(RegisterGeneralNumberSetting) ~= "function" then return end
    if type(ApplyBars) ~= "function" or type(ApplyBarGradients) ~= "function" then return end
    if type(NormalizeTextureKeyForAssistant) ~= "function" or type(NormalizeBorderKeyForAssistant) ~= "function" then return end
    if type(GRADIENT_DIRECTION_VALUES) ~= "table" or type(GRADIENT_DIRECTION_KEYS) ~= "table" then return end

    RegisterGeneralString("barTexture", "texture", "Global Bar Texture", "Solid", {
        "bar texture", "bars texture", "global bar texture", "global bars texture", "health bar texture",
        "foreground bar texture", "foreground texture", "foreground bar art", "health bar art",
        "texture for my health bars", "texture for the health bars", "bar art",
        "solid looking bar texture", "plain bar texture",
    }, {
        category = "Global / Bars / Textures",
        frameType = "globalBars",
        apply = ApplyBars,
        reason = "MSUF_ASSISTANT_BAR_TEXTURE",
        normalizeValue = NormalizeTextureKeyForAssistant,
    })
    RegisterGeneralString("barBackgroundTexture", "backgroundTexture", "Global Bar Background Texture", "Solid", {
        -- Human wording first; the alias head is capped.
        "bar background texture", "background bar texture", "bars background texture",
        "empty part of the bar", "empty part of the health bar",
        "make the empty part of the bar use the flat texture",
        "background art behind the health bar", "art behind the health bar",
        "global bar background texture", "bar bg texture", "background texture",
    }, {
        category = "Global / Bars / Textures",
        frameType = "globalBars",
        apply = ApplyBars,
        reason = "MSUF_ASSISTANT_BAR_BACKGROUND_TEXTURE",
        normalizeValue = NormalizeTextureKeyForAssistant,
    })
    -- Shared power-bar art for every unit power bar, detached or not. It lives
    -- in the bars table rather than general, and an empty value means "follow
    -- the bar texture" -- the same sentinel the menu dropdown shows as
    -- "Use bar texture". These replaced the retired detached-power textures, so
    -- without them the Class Resources power-texture phrasings resolve to a key
    -- that no longer exists.
    if type(RegisterBarsString) == "function" then
        RegisterBarsString("powerBarTexture", "texture", "Power Bar Texture", "", {
            "power bar texture", "power texture", "mana bar texture", "resource bar texture",
            "power bar foreground texture", "power foreground texture", "power bar art",
            "texture for the power bars", "texture for the mana bar", "mana bar art",
        }, {
            category = "Global / Bars / Textures",
            apply = ApplyBars,
            reason = "MSUF_ASSISTANT_POWER_BAR_TEXTURE",
            normalizeValue = NormalizeTextureKeyForAssistant,
            description = "Art for every unit's power bar. Leave empty to follow the shared bar texture; each unit page can override it.",
        })
        RegisterBarsString("powerBarBgTexture", "backgroundTexture", "Power Bar Background Texture", "", {
            "power bar background texture", "power background texture", "power bar bg texture",
            "mana bar background texture", "resource bar background texture",
            "background behind the mana bar", "background behind the power bar",
            "art behind the power bar",
        }, {
            category = "Global / Bars / Textures",
            apply = ApplyBars,
            reason = "MSUF_ASSISTANT_POWER_BAR_BACKGROUND_TEXTURE",
            normalizeValue = NormalizeTextureKeyForAssistant,
            description = "Background art behind every unit's power bar. Overridable per unit on the unit page.",
        })
        -- Square frame outline art. Empty means the classic solid-color outline.
        RegisterBarsString("barOutlineTexture", "outlineTexture", "Global Frame Outline Style", "", {
            "frame outline style", "outline style", "true outline",
            "frame outline texture", "bar outline texture", "outline texture",
            "border texture", "frame border texture", "border style for the frame outline",
            "frame border style", "outline art",
            -- "Border" is the word players actually use for the square outline;
            -- without these phrasings the dispel-border family outranks it for
            -- "put a border around my frames".
            "border around my frames", "border around the frames",
            "border around frames", "border around the frame",
        }, {
            category = "Global / Bars / Outline",
            mediaType = "border",
            apply = type(ctx.ApplyBarOutline) == "function" and ctx.ApplyBarOutline or ApplyBars,
            reason = "MSUF_ASSISTANT_BAR_OUTLINE_TEXTURE",
            normalizeValue = NormalizeBorderKeyForAssistant,
            description = "Optional texture for the square frame outline. Leave empty for the classic solid color; rounded frames always keep the solid outline color.",
        })
    end
    RegisterGeneralBoolean("enableGradient", "healthGradient", "HP Bar Gradient", false, {
        "hp bar gradient", "health bar gradient", "health gradient", "hp gradient",
        "bar gradient", "bars gradient", "bar gradients", "unitframe gradient",
        "unit frame gradient", "unitframe bar gradient", "unit frame bar gradient",
        "colour fade on the health bars", "color fade on the health bars", "gradient look",
        "gradient on my health bars", "health bars a gradient look", "shade the health bars",
        "colour fade to the health bars", "color fade to the health bars",
        "gradient from the health bars", "gradient on the health bars",
        "add a colour fade", "add a color fade", "a colour fade to the health bars",
        "remove the gradient from the health bars",
        "colour fade health bars", "color fade health bars", "gradient health bars",
    }, {
        category = "Global / Bars / Gradient",
        frameType = "globalBars",
        apply = ApplyBarGradients,
        reason = "MSUF_ASSISTANT_HP_GRADIENT",
        description = "Shades the health bar from its base colour towards a darker or lighter tone.",
    })
    RegisterGeneralBoolean("enablePowerGradient", "powerGradient", "Power Bar Gradient", false, {
        "power bar gradient", "power gradient", "mana gradient", "mana bar gradient",
        "resource gradient", "resource bar gradient",
        "gradient on the power bars", "colour fade on the power bars", "color fade on the power bars",
        "power bars to have a colour fade", "power bars to have a color fade",
        "shade the power bars",
    }, {
        category = "Global / Bars / Gradient",
        frameType = "globalBars",
        apply = ApplyBarGradients,
        reason = "MSUF_ASSISTANT_POWER_GRADIENT",
        description = "Shades the power bar from its base colour towards a darker or lighter tone.",
    })
    -- The health and power gradients have separate strength sliders on the
    -- Bars page, so "power gradient strength" must not resolve to this one.
    RegisterGeneralNumberSetting("gradientStrength", "gradientStrength", "Bar Gradient Strength", 0.45, 0, 1, {
        "gradient strength", "bar gradient strength", "health gradient strength", "hp gradient strength",
        "health bar gradient strength", "stronger gradient", "weaker gradient", "subtle gradient",
        "make the gradient stronger", "make the gradient weaker", "gradient stronger", "gradient weaker",
        "bar gradient is too subtle", "gradient is too subtle", "gradient too subtle",
        "gradient intensity", "health gradient intensity",
    }, {
        category = "Global / Bars / Gradient",
        frameType = "globalBars",
        apply = ApplyBarGradients,
        reason = "MSUF_ASSISTANT_GRADIENT_STRENGTH",
        step = 0.05,
        percent = true,
        description = "How far the health bar gradient shades from its base colour.",
    })
    RegisterGeneralNumberSetting("powerGradientStrength", "powerGradientStrength", "Power Gradient Strength", 0.45, 0, 1, {
        "power gradient strength", "power bar gradient strength", "mana gradient strength",
        "mana bar gradient strength", "resource gradient strength", "stronger power gradient",
        "weaker power gradient", "power gradient stronger", "power gradient intensity",
        "make the power gradient stronger", "turn up the power bar gradient strength",
        "turn up the power gradient", "power gradient is too subtle",
    }, {
        category = "Global / Bars / Gradient",
        frameType = "globalBars",
        apply = ApplyBarGradients,
        reason = "MSUF_ASSISTANT_POWER_GRADIENT_STRENGTH",
        step = 0.05,
        percent = true,
        description = "How far the power bar gradient shades from its base colour.",
    })
    Registry:RegisterSetting({
        key = "general.gradientDirection",
        label = "Bar Gradient Direction",
        category = "Global / Bars / Gradient",
        unit = "global",
        frameType = "globalBars",
        attribute = "gradientDirection",
        type = "enum",
        aliases = {
            "gradient direction", "bar gradient direction", "health gradient direction",
            "health bar gradient direction", "hp gradient direction",
            "global bar gradient direction", "global bars gradient direction",
            "global bar right", "global bar right gradient", "global bar right direction",
            "global bar right color", "bar right gradient", "bar right direction", "right bar gradient",
            "gradient from right", "gradient from left", "gradient from top", "gradient from bottom",
            "bar gradient from right", "bar gradient from left", "bar gradient from top", "bar gradient from bottom",
            "health bar gradient fade from", "gradient fades from", "which side the gradient fades from",
            "health bar gradient fade from the left", "health bar gradient fade from the right",
            "gradient fade from the left", "gradient fade from the right",
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
        description = "Which edge the health bar gradient fades from.",
    })
    -- The power gradient keeps its own direction flags; before this the four
    -- powerGradientDir* booleans were storage with no way to name them.
    local POWER_GRADIENT_DIRECTION_KEYS = ctx.POWER_GRADIENT_DIRECTION_KEYS
    Registry:RegisterSetting({
        key = "general.powerGradientDirection",
        label = "Power Gradient Direction",
        category = "Global / Bars / Gradient",
        unit = "global",
        frameType = "globalBars",
        attribute = "powerGradientDirection",
        type = "enum",
        aliases = {
            "power gradient direction", "power bar gradient direction", "mana gradient direction",
            "mana bar gradient direction", "resource gradient direction",
            "power gradient from right", "power gradient from left",
            "power gradient from top", "power gradient from bottom",
            "power bar gradient fade from", "which side the power gradient fades from",
        },
        values = GRADIENT_DIRECTION_VALUES,
        valueAliases = GRADIENT_DIRECTION_ALIASES,
        dbScopes = {
            { scope = "general", dbKey = "powerGradientDirection" },
            { scope = "general", dbKey = "powerGradientDirRight" },
            { scope = "general", dbKey = "powerGradientDirLeft" },
            { scope = "general", dbKey = "powerGradientDirUp" },
            { scope = "general", dbKey = "powerGradientDirDown" },
        },
        dbScopesReplace = true,
        get = function()
            local g = GeneralDB()
            for i = 1, #GRADIENT_DIRECTION_VALUES do
                local value = GRADIENT_DIRECTION_VALUES[i]
                if g[POWER_GRADIENT_DIRECTION_KEYS[value]] == true then return value end
            end
            -- No explicit power direction yet: the runtime falls back to the
            -- health direction, so report what the bar actually shows.
            local value = g.powerGradientDirection or g.gradientDirection
            return POWER_GRADIENT_DIRECTION_KEYS[value] and value or "RIGHT"
        end,
        set = function(value)
            if not POWER_GRADIENT_DIRECTION_KEYS[value] then value = "RIGHT" end
            local g = GeneralDB()
            for i = 1, #GRADIENT_DIRECTION_VALUES do
                local dir = GRADIENT_DIRECTION_VALUES[i]
                g[POWER_GRADIENT_DIRECTION_KEYS[dir]] = dir == value
            end
            g.powerGradientDirection = value
        end,
        apply = function() ApplyBarGradients("MSUF_ASSISTANT_POWER_GRADIENT_DIRECTION") end,
        combatSafe = false,
        menuControlDisposition = "standalone",
        menuControlDispositionReason = "Menu2 exposes power-gradient direction as four independent toggle actions; this Assistant enum is their atomic single-direction controller.",
        menuControlDispositionEvidence = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalBars.lua BuildDirectionPad",
        description = "Which edge the power bar gradient fades from.",
    })
end
