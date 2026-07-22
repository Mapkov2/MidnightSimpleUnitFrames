-- Assistant UnitFrame portrait setting registry.
-- Keeps portrait-specific metadata out of the main unitframe registry loop.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.UnitframesRegistry = A.UnitframesRegistry or {}

local UnitframeData = A.UnitframeRegistryData or {}
local PORTRAIT_MODE_VALUES = UnitframeData.PORTRAIT_MODE_VALUES or {}
local PORTRAIT_RENDER_VALUES = UnitframeData.PORTRAIT_RENDER_VALUES or {}
local PORTRAIT_SHAPE_VALUES = UnitframeData.PORTRAIT_SHAPE_VALUES or {}
local PORTRAIT_BORDER_VALUES = UnitframeData.PORTRAIT_BORDER_VALUES or {}

local function NormalizePortraitClassStyle(value)
    value = tostring(value or "")
    local normalized = value:upper():gsub("%s+", "_"):gsub("%-", "_")
    if normalized == "RONDO_COLOR" or normalized == "RONDO_WOW" or normalized == "BLIZZARD" then return normalized end
    if M and type(M.NormalizePortraitClassStyle) == "function" then return M.NormalizePortraitClassStyle(value) end
    local fn = _G.MSUF_NormalizePortraitClassStyleValue
    if type(fn) == "function" then return fn(value) end
    return "BLIZZARD"
end

function A.UnitframesRegistry.RegisterPortraitSettings(ctx, unit)
    if type(ctx) ~= "table" then return end
    unit = tostring(unit or "")
    if unit == "" then return end

    local UnitDB = ctx.UnitDB
    local MakeAliases = ctx.MakeAliases
    local RegisterUnitEnum = ctx.RegisterUnitEnum
    local RegisterUnitString = ctx.RegisterUnitString
    local RegisterUnitNumberSetting = ctx.RegisterUnitNumberSetting
    local RegisterUnitBooleanSetting = ctx.RegisterUnitBooleanSetting

    if type(UnitDB) ~= "function" or type(MakeAliases) ~= "function" then return end
    if type(RegisterUnitEnum) ~= "function" or type(RegisterUnitString) ~= "function" then return end
    if type(RegisterUnitNumberSetting) ~= "function" or type(RegisterUnitBooleanSetting) ~= "function" then return end

    local function NormalizePortraitMode(unitKey)
        local value = UnitDB(unitKey).portraitMode or "OFF"
        if value ~= "LEFT" and value ~= "RIGHT" then return "OFF" end
        return value
    end

    RegisterUnitEnum(unit, "portraitMode", "portraitMode", "Portrait Position", "OFF", PORTRAIT_MODE_VALUES, MakeAliases(unit, "portrait", "portrait position", "portrait side"), {
        category = "Portrait",
        valueAliases = {
            off = "OFF",
            hide = "OFF",
            hidden = "OFF",
            disabled = "OFF",
            disable = "OFF",
            aus = "OFF",
            on = "LEFT",
            enable = "LEFT",
            enabled = "LEFT",
            show = "LEFT",
            visible = "LEFT",
            an = "LEFT",
            left = "LEFT",
            right = "RIGHT",
        },
        get = NormalizePortraitMode,
        set = function(unitKey, value) UnitDB(unitKey).portraitMode = value end,
    })
    RegisterUnitEnum(unit, "portraitRender", "portraitRender", "Portrait Render", "2D",
        PORTRAIT_RENDER_VALUES,
        MakeAliases(unit, "portrait render", "portrait type", "class portrait"), {
        category = "Portrait",
        valueAliases = {
            ["2d"] = "2D",
            ["2d portrait"] = "2D",
            portrait = "2D",
            class = "CLASS",
            ["class portrait"] = "CLASS",
        },
    })
    RegisterUnitBooleanSetting(unit, "portraitCastSpellIcon", "portraitCastSpellIcon",
        "Show Cast Spell Icon In Portrait", false,
        MakeAliases(unit, "cast spell icon in portrait", "portrait cast icon", "portrait spell icon"),
        { category = "Portrait" })
    RegisterUnitEnum(unit, "portraitShape", "portraitShape", "Portrait Shape", "SQUARE", PORTRAIT_SHAPE_VALUES, MakeAliases(unit, "portrait shape"), {
        category = "Portrait",
        valueAliases = {
            square = "SQUARE",
            circle = "CIRCLE",
            round = "CIRCLE",
            rounded = "ROUNDED",
            diamond = "DIAMOND",
        },
    })
    RegisterUnitNumberSetting(unit, "portraitSizeOverride", "portraitSizeOverride", "Portrait Size Override",
        0, 0, 128, MakeAliases(unit, "portrait size", "portrait size override"), { category = "Portrait" })
    RegisterUnitNumberSetting(unit, "portraitOffsetX", "portraitOffsetX", "Portrait X Offset",
        0, -120, 120, MakeAliases(unit, "portrait x", "portrait x offset"), { category = "Portrait" })
    RegisterUnitNumberSetting(unit, "portraitOffsetY", "portraitOffsetY", "Portrait Y Offset",
        0, -120, 120, MakeAliases(unit, "portrait y", "portrait y offset"), { category = "Portrait" })
    RegisterUnitNumberSetting(unit, "portraitZoom", "portraitZoom", "Portrait Zoom",
        100, 100, 200, MakeAliases(unit, "portrait zoom", "2d portrait zoom", "portrait crop", "reinzoomen", "rauszoomen"), { category = "Portrait" })
    RegisterUnitString(unit, "portraitClassStyle", "portraitClassStyle", "Class Portrait Style", "BLIZZARD", MakeAliases(unit, "portrait class style", "class portrait style"), {
        category = "Portrait",
        normalizeValue = NormalizePortraitClassStyle,
        description = "Chooses the class portrait style from the portrait media list.",
    })
    RegisterUnitEnum(unit, "portraitBorderStyle", "portraitBorderStyle", "Portrait Border", "NONE",
        PORTRAIT_BORDER_VALUES,
        MakeAliases(unit, "portrait border", "portrait border style"), {
        category = "Portrait",
        valueAliases = {
            none = "NONE",
            off = "NONE",
            hide = "NONE",
            hidden = "NONE",
            disable = "NONE",
            disabled = "NONE",
            aus = "NONE",
            on = "SOLID",
            enable = "SOLID",
            enabled = "SOLID",
            show = "SOLID",
            visible = "SOLID",
            an = "SOLID",
            solid = "SOLID",
            class = "CLASS_COLOR",
            ["class color"] = "CLASS_COLOR",
            reaction = "REACTION",
            ["reaction color"] = "REACTION",
            custom = "CUSTOM",
            ["custom color"] = "CUSTOM",
        },
    })
    RegisterUnitNumberSetting(unit, "portraitBorderThickness", "portraitBorderThickness", "Portrait Border Thickness",
        2, 1, 12,
        MakeAliases(unit, "portrait border thickness", "portrait border size", "portrait border thicker", "portrait border thinner"),
        { category = "Portrait" })
    RegisterUnitBooleanSetting(unit, "portraitFillBorder", "portraitFillBorder", "Portrait Fill Border Gap", false,
        MakeAliases(unit, "portrait fill border", "fill portrait border gap"), { category = "Portrait" })
    RegisterUnitBooleanSetting(unit, "portraitBgEnabled", "portraitBgEnabled", "Portrait Background", false,
        MakeAliases(unit, "portrait background", "portrait bg"), { category = "Portrait" })
end
