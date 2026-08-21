-- Assistant UnitFrame transparency and range setting registry.
-- Keeps alpha/range controls outside the main UnitFrame registry loop.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.UnitframesRegistry = A.UnitframesRegistry or {}

local RANGE_FADE_UNITS = { target = true, targettarget = true, focus = true, focustarget = true, pet = true, boss = true }

function A.UnitframesRegistry.RegisterTransparencyAndRangeSettings(ctx, unit)
    if type(ctx) ~= "table" or type(unit) ~= "string" then return end

    local MakeAliases = ctx.MakeAliases
    local RegisterUnitNumberSetting = ctx.RegisterUnitNumberSetting
    local RegisterUnitBooleanSetting = ctx.RegisterUnitBooleanSetting
    local RegisterUnitEnum = ctx.RegisterUnitEnum
    local RANGE_LAYER_VALUES = ctx.RANGE_LAYER_VALUES or {}

    if type(MakeAliases) ~= "function" then return end
    if type(RegisterUnitNumberSetting) ~= "function" or type(RegisterUnitBooleanSetting) ~= "function" then return end
    if type(RegisterUnitEnum) ~= "function" then return end

    RegisterUnitNumberSetting(unit, "hpBarAlpha", "hpBarAlpha", "HP Bar Opacity", 1, 0, 1,
        MakeAliases(unit, "hp bar opacity", "health bar opacity", "hp opacity", "hp alpha", "bar opacity"), {
        category = "Transparency",
        alpha = true,
        step = 0.05,
        percent = true,
    })
    RegisterUnitNumberSetting(unit, "powerBarAlpha", "powerBarAlpha", "Power Bar Opacity", 1, 0, 1,
        MakeAliases(unit, "power bar opacity", "power opacity", "power alpha", "mana bar opacity", "mana opacity"), {
        category = "Transparency",
        alpha = true,
        power = true,
        step = 0.05,
        percent = true,
    })
    RegisterUnitNumberSetting(unit, "powerBarBgAlpha", "powerBarBgAlpha", "Resource Bar Background Opacity", 0.85, 0, 1,
        MakeAliases(unit,
            "resource bar background opacity", "resource background opacity", "power bar background opacity",
            "power background opacity", "mana bar background opacity", "mana background opacity"
        ), {
        category = "Transparency",
        power = true,
        step = 0.05,
        percent = true,
    })
    RegisterUnitNumberSetting(unit, "hpBgAlpha", "hpBgAlpha", "Background Opacity", 0.85, 0, 1,
        MakeAliases(unit,
            "background opacity", "backdrop opacity", "background alpha", "bg opacity",
            "hp track opacity", "health track opacity", "track opacity", "bar background opacity"
        ), {
        category = "Transparency",
        step = 0.05,
        percent = true,
    })
    RegisterUnitBooleanSetting(unit, "alphaExcludeTextPortrait", "alphaExcludeTextPortrait",
        "Keep Text & Portrait Visible", false,
        MakeAliases(unit,
            "keep text visible", "keep text portrait visible", "keep text and portrait visible",
            "exclude text from opacity", "keep portrait visible", "exclude portrait from opacity"
        ), { category = "Transparency", alpha = true })
    RegisterUnitBooleanSetting(unit, "oocFadeEnabled", "oocFadeEnabled",
        "Fade Frame Out of Combat", false,
        MakeAliases(unit,
            "fade out of combat", "out of combat fade", "ooc fade", "fade frame out of combat",
            "fade when out of combat"
        ), { category = "Transparency", alpha = true })
    RegisterUnitNumberSetting(unit, "oocFadeAlpha", "oocFadeAlpha", "Out of Combat Opacity", 0.5, 0, 1,
        MakeAliases(unit,
            "out of combat opacity", "out of combat alpha", "ooc opacity", "ooc alpha",
            "out of combat frame opacity"
        ), { category = "Transparency", alpha = true, step = 0.05, percent = true })

    if RANGE_FADE_UNITS[unit] then
        RegisterUnitNumberSetting(unit, "rangeFadeAlpha", "rangeFadeAlpha", "Range Fade Opacity",
            0.4, 0, 1, MakeAliases(unit, "range fade opacity", "range fade alpha"),
            { category = "Range", alpha = true, step = 0.05, percent = true })
        RegisterUnitEnum(unit, "rangeFadeLayerMode", "rangeFadeLayerMode", "Range Fade Affects", "frame",
            RANGE_LAYER_VALUES,
            MakeAliases(unit, "range fade affects", "range fade layer", "range fade mode"), {
            category = "Range",
            alpha = true,
            valueAliases = {
                frame = "frame",
                whole = "frame",
                ["whole frame"] = "frame",
                hp = "health",
                health = "health",
                ["hp only"] = "health",
                ["health only"] = "health",
            },
        })
    end
end
