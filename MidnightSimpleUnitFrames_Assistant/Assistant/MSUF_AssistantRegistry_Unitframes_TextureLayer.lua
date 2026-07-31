-- Assistant UnitFrame decorative texture layer setting registry (3 slots).
-- Keeps the texture-layer controls outside the main UnitFrame registry loop.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.UnitframesRegistry = A.UnitframesRegistry or {}

-- Same call-time resolution as the power textures: the shared texture-name
-- normalizer lives in the Global Bars data module, which loads later.
local function NormalizeTextureKeyForAssistant(value)
    local Data = A.GlobalBarRegistry and A.GlobalBarRegistry.Data
    local normalize = Data and Data.NormalizeTextureKeyForAssistant
    if type(normalize) == "function" then return normalize(value) end
    return value
end

local SLOTS = {
    { prefix = "texLayer", label = "Texture Layer", alias = "texture layer" },
    { prefix = "texLayer2", label = "Texture Layer 2", alias = "texture layer 2" },
    { prefix = "texLayer3", label = "Texture Layer 3", alias = "texture layer 3" },
}
local STRATA_VALUES = { "AUTO", "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "TOOLTIP" }
local ANCHOR_VALUES = {
    "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}
local ANCHOR_TARGET_VALUES = { "FRAME", "HEALTH", "POWER", "PORTRAIT" }
local COLOR_MODE_VALUES = { "CUSTOM", "CLASS" }
local BLEND_VALUES = { "BLEND", "ADD" }
local VISIBILITY_VALUES = { "ALWAYS", "COMBAT", "OOC" }

local STRATA_ALIASES = {
    auto = "AUTO", ["frame default"] = "AUTO", default = "AUTO",
    background = "BACKGROUND", low = "LOW", medium = "MEDIUM",
    high = "HIGH", dialog = "DIALOG", tooltip = "TOOLTIP",
}
local ANCHOR_ALIASES = {
    ["top left"] = "TOPLEFT", top = "TOP", ["top right"] = "TOPRIGHT",
    left = "LEFT", center = "CENTER", middle = "CENTER", right = "RIGHT",
    ["bottom left"] = "BOTTOMLEFT", bottom = "BOTTOM", ["bottom right"] = "BOTTOMRIGHT",
}
local ANCHOR_TARGET_ALIASES = {
    frame = "FRAME", ["whole frame"] = "FRAME",
    health = "HEALTH", ["health bar"] = "HEALTH", hp = "HEALTH",
    power = "POWER", ["power bar"] = "POWER", mana = "POWER",
    portrait = "PORTRAIT",
}
local COLOR_MODE_ALIASES = {
    custom = "CUSTOM", ["custom color"] = "CUSTOM",
    class = "CLASS", ["class color"] = "CLASS",
}
local BLEND_ALIASES = {
    normal = "BLEND", blend = "BLEND",
    add = "ADD", additive = "ADD", glow = "ADD",
}
local VISIBILITY_ALIASES = {
    always = "ALWAYS", ["always visible"] = "ALWAYS",
    combat = "COMBAT", ["in combat"] = "COMBAT", ["in combat only"] = "COMBAT",
    ooc = "OOC", ["out of combat"] = "OOC", ["out of combat only"] = "OOC",
}

function A.UnitframesRegistry.RegisterTextureLayerSettings(ctx, unit)
    if type(ctx) ~= "table" or type(unit) ~= "string" then return end

    local MakeAliases = ctx.MakeAliases
    local RegisterUnitNumberSetting = ctx.RegisterUnitNumberSetting
    local RegisterUnitBooleanSetting = ctx.RegisterUnitBooleanSetting
    local RegisterUnitEnum = ctx.RegisterUnitEnum
    local RegisterUnitString = ctx.RegisterUnitString

    if type(MakeAliases) ~= "function" then return end
    if type(RegisterUnitNumberSetting) ~= "function" or type(RegisterUnitBooleanSetting) ~= "function" then return end
    if type(RegisterUnitEnum) ~= "function" then return end

    for i = 1, #SLOTS do
        local slot = SLOTS[i]
        local p, label, alias = slot.prefix, slot.label, slot.alias
        local category = label

        RegisterUnitBooleanSetting(unit, p .. "Enabled", p .. "Enabled", label, false,
            MakeAliases(unit, alias, "enable " .. alias, alias .. " enabled"), {
            category = category,
        })
        if type(RegisterUnitString) == "function" then
            RegisterUnitString(unit, p .. "Texture", p .. "Texture", label .. " Texture", "",
                MakeAliases(unit, alias .. " texture", alias .. " art"), {
                category = category,
                mediaType = "statusbar",
                normalizeValue = NormalizeTextureKeyForAssistant,
                description = "SharedMedia art for this decorative texture layer. Leave empty to follow the shared bar texture.",
            })
            RegisterUnitString(unit, p .. "CustomTexturePath", p .. "CustomTexturePath", label .. " Custom Path", "",
                MakeAliases(unit, alias .. " custom path", alias .. " custom texture path"), {
                category = category,
                description = "Optional Interface\\... file path that overrides the SharedMedia texture choice.",
            })
        end
        RegisterUnitNumberSetting(unit, p .. "Alpha", p .. "Alpha", label .. " Opacity", 1, 0, 1,
            MakeAliases(unit, alias .. " opacity", alias .. " alpha"), {
            category = category,
            step = 0.05,
            percent = true,
        })
        RegisterUnitBooleanSetting(unit, p .. "FollowFrameAlpha", p .. "FollowFrameAlpha",
            label .. " Follows Frame Transparency", true,
            MakeAliases(unit, alias .. " follows frame transparency", alias .. " follow fade"), {
            category = category,
        })
        RegisterUnitEnum(unit, p .. "Strata", p .. "Strata", label .. " Strata", "AUTO",
            STRATA_VALUES,
            MakeAliases(unit, alias .. " strata", alias .. " frame strata"), {
            category = category,
            valueAliases = STRATA_ALIASES,
        })
        RegisterUnitNumberSetting(unit, p .. "Level", p .. "Level", label .. " Level", 1, 0, 30,
            MakeAliases(unit, alias .. " level", alias .. " layer"), {
            category = category,
            step = 1,
        })
        RegisterUnitEnum(unit, p .. "AnchorTarget", p .. "AnchorTarget", label .. " Anchor Target", "FRAME",
            ANCHOR_TARGET_VALUES,
            MakeAliases(unit, alias .. " anchor target", alias .. " anchored to", alias .. " attach to"), {
            category = category,
            valueAliases = ANCHOR_TARGET_ALIASES,
        })
        RegisterUnitEnum(unit, p .. "Anchor", p .. "Anchor", label .. " Anchor", "TOP",
            ANCHOR_VALUES,
            MakeAliases(unit, alias .. " anchor", alias .. " position"), {
            category = category,
            valueAliases = ANCHOR_ALIASES,
        })
        RegisterUnitNumberSetting(unit, p .. "OffsetX", p .. "OffsetX", label .. " Offset X", 0, -200, 200,
            MakeAliases(unit, alias .. " offset x", alias .. " x offset"), {
            category = category,
            step = 1,
        })
        RegisterUnitNumberSetting(unit, p .. "OffsetY", p .. "OffsetY", label .. " Offset Y", 0, -200, 200,
            MakeAliases(unit, alias .. " offset y", alias .. " y offset"), {
            category = category,
            step = 1,
        })
        RegisterUnitNumberSetting(unit, p .. "Width", p .. "Width", label .. " Width", 0, 0, 600,
            MakeAliases(unit, alias .. " width"), {
            category = category,
            step = 1,
            description = "Width of the decorative texture layer. 0 keeps the anchor target's width.",
        })
        RegisterUnitNumberSetting(unit, p .. "Height", p .. "Height", label .. " Height", 16, 1, 120,
            MakeAliases(unit, alias .. " height"), {
            category = category,
            step = 1,
        })
        RegisterUnitEnum(unit, p .. "ColorMode", p .. "ColorMode", label .. " Color Mode", "CUSTOM",
            COLOR_MODE_VALUES,
            MakeAliases(unit, alias .. " color mode"), {
            category = category,
            valueAliases = COLOR_MODE_ALIASES,
        })
        RegisterUnitBooleanSetting(unit, p .. "GradientEnabled", p .. "GradientEnabled",
            label .. " Gradient", false,
            MakeAliases(unit, alias .. " gradient", alias .. " gradient enabled"), {
            category = category,
        })
        RegisterUnitBooleanSetting(unit, p .. "GradientDirRight", p .. "GradientDirRight",
            label .. " Gradient Right", true,
            MakeAliases(unit, alias .. " gradient right"), { category = category })
        RegisterUnitBooleanSetting(unit, p .. "GradientDirLeft", p .. "GradientDirLeft",
            label .. " Gradient Left", false,
            MakeAliases(unit, alias .. " gradient left"), { category = category })
        RegisterUnitBooleanSetting(unit, p .. "GradientDirUp", p .. "GradientDirUp",
            label .. " Gradient Up", false,
            MakeAliases(unit, alias .. " gradient up"), { category = category })
        RegisterUnitBooleanSetting(unit, p .. "GradientDirDown", p .. "GradientDirDown",
            label .. " Gradient Down", false,
            MakeAliases(unit, alias .. " gradient down"), { category = category })
        RegisterUnitEnum(unit, p .. "BlendMode", p .. "BlendMode", label .. " Blend Mode", "BLEND",
            BLEND_VALUES,
            MakeAliases(unit, alias .. " blend mode", alias .. " additive glow"), {
            category = category,
            valueAliases = BLEND_ALIASES,
        })
        RegisterUnitBooleanSetting(unit, p .. "MirrorH", p .. "MirrorH",
            label .. " Mirror Horizontally", false,
            MakeAliases(unit, alias .. " mirror horizontally", alias .. " flip horizontally"), {
            category = category,
        })
        RegisterUnitBooleanSetting(unit, p .. "MirrorV", p .. "MirrorV",
            label .. " Mirror Vertically", false,
            MakeAliases(unit, alias .. " mirror vertically", alias .. " flip vertically"), {
            category = category,
        })
        RegisterUnitEnum(unit, p .. "Visibility", p .. "Visibility", label .. " Visibility", "ALWAYS",
            VISIBILITY_VALUES,
            MakeAliases(unit, alias .. " visibility", "show " .. alias), {
            category = category,
            valueAliases = VISIBILITY_ALIASES,
        })
        RegisterUnitBooleanSetting(unit, p .. "RoundedClip", p .. "RoundedClip",
            label .. " Rounded Clipping", false,
            MakeAliases(unit, alias .. " rounded clipping", alias .. " clip to rounded frame"), {
            category = category,
        })
    end
end
