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
local PORTRAIT_SHAPE_VALUES = UnitframeData.PORTRAIT_SHAPE_VALUES_UNIT or UnitframeData.PORTRAIT_SHAPE_VALUES or {}
local PORTRAIT_SIZE_MODE_VALUES = { "UNIFORM", "SEPARATE" }
local PORTRAIT_BORDER_VALUES = UnitframeData.PORTRAIT_BORDER_VALUES or {}
local PORTRAIT_PLACEMENT_VALUES = UnitframeData.PORTRAIT_PLACEMENT_VALUES or {}
local PORTRAIT_ANCHOR_POINT_VALUES = UnitframeData.PORTRAIT_ANCHOR_POINT_VALUES or {}
local PORTRAIT_OVERLAY_ALIGN_VALUES = UnitframeData.PORTRAIT_OVERLAY_ALIGN_VALUES or {}
local PORTRAIT_BORDER_ART_VALUES = UnitframeData.PORTRAIT_BORDER_ART_VALUES or {}
local PORTRAIT_BORDER_DIRECTION_VALUES = UnitframeData.PORTRAIT_BORDER_DIRECTION_VALUES or {}
-- Anchor points are spoken in many shapes ("top left", "upper-left", "topleft").
-- One shared alias table keeps both anchor dropdowns talking the same language.
local PORTRAIT_ANCHOR_POINT_ALIASES = {
    ["top left"] = "TOPLEFT", ["upper left"] = "TOPLEFT", topleft = "TOPLEFT",
    top = "TOP", ["top center"] = "TOP", ["top middle"] = "TOP",
    ["top right"] = "TOPRIGHT", ["upper right"] = "TOPRIGHT", topright = "TOPRIGHT",
    left = "LEFT", ["middle left"] = "LEFT",
    center = "CENTER", middle = "CENTER", centre = "CENTER", mitte = "CENTER",
    right = "RIGHT", ["middle right"] = "RIGHT",
    ["bottom left"] = "BOTTOMLEFT", ["lower left"] = "BOTTOMLEFT", bottomleft = "BOTTOMLEFT",
    bottom = "BOTTOM", ["bottom center"] = "BOTTOM", ["bottom middle"] = "BOTTOM",
    ["bottom right"] = "BOTTOMRIGHT", ["lower right"] = "BOTTOMRIGHT", bottomright = "BOTTOMRIGHT",
}

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
            blizzard = "BLIZZARD",
            ["blizzard ring"] = "BLIZZARD",
            ["blizzard-ring"] = "BLIZZARD",
            ["gold ring"] = "BLIZZARD",
            goldring = "BLIZZARD",
        },
    })
    RegisterUnitEnum(unit, "portraitSizeMode", "portraitSizeMode", "Portrait Size Mode", "UNIFORM",
        PORTRAIT_SIZE_MODE_VALUES,
        MakeAliases(unit, "portrait size mode", "uniform portrait size", "separate portrait width and height"), {
        category = "Portrait",
        description = "Uniform uses one size for both axes; Width & Height applies the two axis overrides independently.",
        valueAliases = {
            uniform = "UNIFORM", square = "UNIFORM", linked = "UNIFORM", locked = "UNIFORM",
            separate = "SEPARATE", independent = "SEPARATE", custom = "SEPARATE",
            ["width and height"] = "SEPARATE", ["width & height"] = "SEPARATE",
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
    RegisterUnitNumberSetting(unit, "portraitEdgeSoftness", "portraitEdgeSoftness", "Portrait Edge Softness",
        0, 0, 30,
        MakeAliases(unit, "portrait edge softness", "soft portrait edge", "portrait feather", "borderless portrait fade"),
        { category = "Portrait", step = 2,
            description = "Softens the portrait silhouette when its border is disabled, from 0 to 30 percent." })
    RegisterUnitNumberSetting(unit, "portraitBorderThickness", "portraitBorderThickness", "Portrait Border Thickness",
        2, 1, 12,
        MakeAliases(unit, "portrait border thickness", "portrait border size", "portrait border thicker", "portrait border thinner"),
        { category = "Portrait" })
    RegisterUnitBooleanSetting(unit, "portraitFillBorder", "portraitFillBorder", "Portrait Fill Border Gap", false,
        MakeAliases(unit, "portrait fill border", "fill portrait border gap"), { category = "Portrait" })
    RegisterUnitBooleanSetting(unit, "portraitBgEnabled", "portraitBgEnabled", "Portrait Background", false,
        MakeAliases(unit, "portrait background", "portrait bg"), { category = "Portrait" })
    RegisterUnitEnum(unit, "portraitPlacement", "portraitPlacement", "Portrait Placement", "ATTACHED",
        PORTRAIT_PLACEMENT_VALUES,
        MakeAliases(unit, "portrait placement", "detach portrait", "detached portrait", "portrait overlay"), {
        category = "Portrait",
        description = "Attached hugs the bar edge, Detached anchors the portrait freely to the frame, Overlay puts it on top of the bar.",
        valueAliases = {
            attached = "ATTACHED",
            attach = "ATTACHED",
            default = "ATTACHED",
            ["attached to bar"] = "ATTACHED",
            detached = "DETACHED",
            detach = "DETACHED",
            free = "DETACHED",
            floating = "DETACHED",
            overlay = "OVERLAY",
            inside = "OVERLAY",
            ["on bar"] = "OVERLAY",
            ["overlay on bar"] = "OVERLAY",
        },
    })
    RegisterUnitEnum(unit, "portraitDetachedPoint", "portraitDetachedPoint", "Portrait Anchor Point", "RIGHT",
        PORTRAIT_ANCHOR_POINT_VALUES,
        MakeAliases(unit, "portrait anchor point", "detached portrait anchor"), {
        category = "Portrait",
        description = "Which point of the detached portrait is pinned to the frame.",
        valueAliases = PORTRAIT_ANCHOR_POINT_ALIASES,
    })
    RegisterUnitEnum(unit, "portraitDetachedTo", "portraitDetachedTo", "Portrait Attach To Frame Point", "LEFT",
        PORTRAIT_ANCHOR_POINT_VALUES,
        MakeAliases(unit, "portrait attach to", "detached portrait frame point"), {
        category = "Portrait",
        description = "Which point of the unit frame the detached portrait is pinned to.",
        valueAliases = PORTRAIT_ANCHOR_POINT_ALIASES,
    })
    RegisterUnitEnum(unit, "portraitOverlayAlign", "portraitOverlayAlign", "Portrait Overlay Alignment", "LEFT",
        PORTRAIT_OVERLAY_ALIGN_VALUES,
        MakeAliases(unit, "portrait overlay alignment", "portrait overlay align"), {
        category = "Portrait",
        valueAliases = {
            left = "LEFT",
            center = "CENTER",
            centre = "CENTER",
            middle = "CENTER",
            right = "RIGHT",
            full = "FULL",
            fill = "FULL",
            ["fill bar"] = "FULL",
            stretch = "FULL",
        },
    })
    RegisterUnitNumberSetting(unit, "portraitWidth", "portraitWidth", "Portrait Width Override",
        0, 0, 256, MakeAliases(unit, "portrait width", "portrait width override"), { category = "Portrait" })
    RegisterUnitNumberSetting(unit, "portraitHeight", "portraitHeight", "Portrait Height Override",
        0, 0, 256, MakeAliases(unit, "portrait height", "portrait height override"), { category = "Portrait" })
    RegisterUnitNumberSetting(unit, "portraitPanX", "portraitPanX", "Portrait Zoom Center X",
        0, -100, 100, MakeAliases(unit, "portrait zoom center x", "portrait pan x"), { category = "Portrait" })
    RegisterUnitNumberSetting(unit, "portraitPanY", "portraitPanY", "Portrait Zoom Center Y",
        0, -100, 100, MakeAliases(unit, "portrait zoom center y", "portrait pan y"), { category = "Portrait" })
    RegisterUnitNumberSetting(unit, "portraitLevelOffset", "portraitLevelOffset", "Portrait Layer",
        7, 0, 30, MakeAliases(unit, "portrait layer", "portrait layer offset", "portrait frame level"), { category = "Portrait" })
    RegisterUnitNumberSetting(unit, "portraitAlpha", "portraitAlpha", "Portrait Opacity",
        100, 0, 100, MakeAliases(unit, "portrait opacity", "portrait alpha", "portrait transparency"), { category = "Portrait" })
    RegisterUnitEnum(unit, "portraitBorderArt", "portraitBorderArt", "Portrait Border Art", "FLAT",
        PORTRAIT_BORDER_ART_VALUES,
        MakeAliases(unit, "portrait border art", "portrait relief border", "blizzard portrait border"), {
        category = "Portrait",
        description = "Flat draws the plain edges or ring, Relief swaps in the beveled ring art tinted by the border color.",
        valueAliases = {
            flat = "FLAT",
            plain = "FLAT",
            simple = "FLAT",
            solid = "FLAT",
            relief = "RELIEF",
            beveled = "RELIEF",
            bevel = "RELIEF",
            blizzard = "RELIEF",
            ["blizzard style"] = "RELIEF",
            ["3d"] = "RELIEF",
        },
    })
    RegisterUnitEnum(unit, "portraitBorderDirection", "portraitBorderDirection", "Portrait Border Direction", "UP",
        PORTRAIT_BORDER_DIRECTION_VALUES,
        MakeAliases(unit, "portrait border direction", "portrait border rotation"), {
        category = "Portrait",
        description = "Rotates the relief border art in 90 degree steps; the lit edge follows the chosen direction.",
        valueAliases = {
            up = "UP", top = "UP", oben = "UP",
            right = "RIGHT", rechts = "RIGHT",
            down = "DOWN", bottom = "DOWN", unten = "DOWN",
            left = "LEFT", links = "LEFT",
        },
    })
end
