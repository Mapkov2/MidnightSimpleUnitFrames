-- Assistant global color value helpers.
-- Loaded before the color settings core; consumed by the color helper context.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

function A.GlobalRegistry.BuildColorValueHelpers(ctx)
    if type(ctx) ~= "table" then return nil end

    local MSUFRef = ctx.MSUF or MSUF
    local ColorData = ctx.ColorData or {}
    local COLOR_ALIASES = ColorData.COLOR_ALIASES or {}
    local FALLBACK_COLORS = ColorData.FALLBACK_COLORS or {}

    local function Clamp01(value)
        value = tonumber(value) or 0
        if value < 0 then return 0 end
        if value > 1 then return 1 end
        return value
    end

    local function ColorFromName(name)
        name = tostring(name or ""):lower()
        name = COLOR_ALIASES[name] or name
        local palette = (MSUFRef and MSUFRef.MSUF_FONT_COLORS) or _G.MSUF_FONT_COLORS or FALLBACK_COLORS
        local color = palette and palette[name]
        if type(color) == "table" then
            return Clamp01(color[1] or color.r or 1), Clamp01(color[2] or color.g or 1), Clamp01(color[3] or color.b or 1), name
        end
        color = FALLBACK_COLORS[name]
        if type(color) == "table" then return color[1], color[2], color[3], name end
        return nil
    end
    A.ColorFromName = A.ColorFromName or ColorFromName

    local function HexToColor(hex)
        hex = tostring(hex or ""):match("^#?(%x%x%x%x%x%x)$")
        if not hex then return nil end
        local r = tonumber(hex:sub(1, 2), 16) or 255
        local g = tonumber(hex:sub(3, 4), 16) or 255
        local b = tonumber(hex:sub(5, 6), 16) or 255
        return r / 255, g / 255, b / 255, "#" .. hex:upper()
    end
    A.HexToColor = A.HexToColor or HexToColor

    local function ColorValue(r, g, b, label)
        return {
            r = Clamp01(r),
            g = Clamp01(g),
            b = Clamp01(b),
            label = label,
        }
    end

    local function ColorComponents(value, dr, dg, db)
        if type(value) == "table" then
            return Clamp01(value.r or value[1] or dr), Clamp01(value.g or value[2] or dg), Clamp01(value.b or value[3] or db)
        end
        if type(value) == "string" then
            local r, g, b = ColorFromName(value)
            if r then return r, g, b end
        end
        return Clamp01(dr), Clamp01(dg), Clamp01(db)
    end

    local function ColorSame(a, b)
        if type(a) ~= "table" or type(b) ~= "table" then return a == b end
        local ar, ag, ab = ColorComponents(a, 0, 0, 0)
        local br, bg, bb = ColorComponents(b, 0, 0, 0)
        return math.abs(ar - br) < 0.0005 and math.abs(ag - bg) < 0.0005 and math.abs(ab - bb) < 0.0005
    end

    return {
        Clamp01 = Clamp01,
        ColorComponents = ColorComponents,
        ColorFromName = ColorFromName,
        ColorSame = ColorSame,
        ColorValue = ColorValue,
        HexToColor = HexToColor,
    }
end
