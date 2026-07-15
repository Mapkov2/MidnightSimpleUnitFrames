_G = _G or _ENV

local path = "MidnightSimpleUnitFrames/Runtime/MSUF_FontRegistry.lua"
local handle = io.open(path, "r")
if not handle then path = "Runtime/MSUF_FontRegistry.lua" else handle:close() end

local createColorCalls = 0
_G.LibStub = nil
_G.CreateColor = function(r, g, b, a)
    createColorCalls = createColorCalls + 1
    local color = { r = r, g = g, b = b, a = a }
    function color:GetRGB() return self.r, self.g, self.b end
    function color:GetRGBA() return self.r, self.g, self.b, self.a end
    return color
end

local MSUF = {}
_G.MSUF_NS = MSUF
local chunk, err = loadfile(path)
assert(chunk, err)
chunk("MidnightSimpleUnitFrames", MSUF)

local getColor = assert(_G.MSUF_GetColorFromKey, "color resolver missing")
local red = getColor("RED")
assert(red == getColor("red"), "normalized palette lookup did not reuse its color object")
assert(createColorCalls == 1, "cached palette lookup created duplicate color objects")

local fallback = { marker = true }
assert(getColor(nil, fallback) == fallback and getColor("missing", fallback) == fallback,
    "explicit fallback color identity changed")
assert(createColorCalls == 1, "fallback lookup allocated a color object")

local white = getColor(nil)
assert(white == getColor("missing"), "default white color object was not reused")
assert(createColorCalls == 2, "default color cache created duplicate objects")

_G.MSUF_FONT_COLORS.red[1] = 0.25
local changedRed = getColor("red")
assert(changedRed ~= red, "palette mutation did not invalidate the cached color object")
local r, g, b, a = changedRed:GetRGBA()
assert(r == 0.25 and g == 0 and b == 0 and a == 1, "palette mutation produced stale RGBA values")
assert(createColorCalls == 3, "palette mutation did not rebuild exactly one color object")

io.write("font_color_cache_smoke: ok\n")
