-- Run the Classic-owned accordion color setter with a pale menu accent.
local root = assert(arg[1], "Classic repository root required")
local path = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Widgets.lua"
local file = assert(io.open(path, "rb"))
local source = file:read("*a")
file:close()
local first = assert(source:find("local function SetAccordionHighlightSide", 1, true))
local last = assert(source:find("local function CreateAccordionOpenHighlight", first, true))
local theme = {
    colors = {
        panel2 = { 0.055, 0.098, 0.161, 0.90 },
        text = { 0.933, 0.957, 1, 1 },
    },
}
local gradientCalls = 0
theme.ApplyTextureGradient = function(_, _, from, to)
    gradientCalls = gradientCalls + 1
    assert(type(from) == "table" and type(to) == "table", "gradient colors missing")
end
local chunk = assert(loadstring("local T, ThemeColor, max, min = ...\n"
    .. source:sub(first, last - 1)
    .. "\nreturn AccordionOpenHighlightSetColors"))
local setColors = chunk(theme, function(name, fallback)
    return theme.colors[name] or fallback
end, math.max, math.min)
local function NewHighlight(from, to)
    local side = { SetVertexColor = function() end }
    local highlight = { middle = {}, left = side, right = side, leftCorners = {}, rightCorners = {} }
    setColors(highlight, from, to)
    return highlight
end
local blue = NewHighlight({ 0.231, 0.510, 0.965, 0.62 }, { 0.141, 0.365, 0.741, 0.56 })
assert(blue._msuf2FromR == 0.231 and blue._msuf2FromG == 0.510 and blue._msuf2FromB == 0.965
    and blue._msuf2ToR == 0.141 and blue._msuf2ToG == 0.365 and blue._msuf2ToB == 0.741,
    "readable Midnight blue was changed")
local paleFrom, paleTo = { 0.94, 0.94, 0.94, 0.62 }, { 0.82, 0.82, 0.82, 0.56 }
local pale = NewHighlight(paleFrom, paleTo)
assert(pale._msuf2FromR < paleFrom[1] and pale._msuf2ToR < paleTo[1],
    "pale accent was not darkened at both ends")
assert(paleFrom[1] == 0.94 and paleTo[1] == 0.82,
    "the shared menu accent was mutated")
local function Luminance(r, g, b)
    local function Linearize(value)
        return value <= 0.03928 and value / 12.92 or ((value + 0.055) / 1.055) ^ 2.4
    end
    return 0.2126 * Linearize(r) + 0.7152 * Linearize(g) + 0.0722 * Linearize(b)
end
local titleL = Luminance(0.933, 0.957, 1)
for _, color in ipairs({ pale._msuf2SafeFromColor, pale._msuf2SafeToColor }) do
    local alpha = color[4]
    local surfaceL = Luminance(
        color[1] * alpha + 0.055 * (1 - alpha),
        color[2] * alpha + 0.098 * (1 - alpha),
        color[3] * alpha + 0.161 * (1 - alpha))
    assert((titleL + 0.05) / (surfaceL + 0.05) >= 5.5,
        "pale header does not clear the contrast target")
end
local before = gradientCalls
setColors(pale, paleFrom, paleTo)
assert(gradientCalls == before, "unchanged accordion repainted its gradient")
print("menu2_accordion_contrast_smoke: blue preserved, pale header readable, refresh cached")
