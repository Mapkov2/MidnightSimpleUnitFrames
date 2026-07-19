-- Standalone regression for the allocation-free canonical color-key path.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local lowerCalls = 0
local realLower = string.lower
string.lower = function(value)
    lowerCalls = lowerCalls + 1
    return realLower(value)
end

local createColorCalls = 0
_G.CreateColor = function(r, g, b, a)
    createColorCalls = createColorCalls + 1
    return {
        r = r,
        g = g,
        b = b,
        a = a,
        GetRGB = function(self) return self.r, self.g, self.b end,
    }
end

local addon = {}
local fontRegistryChunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Runtime/MSUF_FontRegistry.lua"))
fontRegistryChunk("MidnightSimpleUnitFrames", addon)
lowerCalls = 0
createColorCalls = 0

local rawR, rawG, rawB = _G.MSUF_GetColorRGBFromKey("red")
Check(rawR == 1 and rawG == 0 and rawB == 0, "raw color-key channels changed")
Check(createColorCalls == 0, "numeric color-key lookup allocated a ColorObject")

local red = _G.MSUF_GetColorFromKey("red")
Check(red ~= nil, "canonical key did not resolve")
Check(lowerCalls == 0, "canonical key must not call string.lower")
Check(_G.MSUF_GetColorFromKey("red") == red, "canonical key did not reuse its color object")
Check(lowerCalls == 0, "cached canonical key must stay on the exact-key path")

Check(_G.MSUF_GetColorFromKey("RED") == red, "mixed-case compatibility changed")
Check(lowerCalls == 1, "mixed-case key must use exactly one normalization fallback")

print("Font color key smoke passed (canonical fast path + mixed-case fallback)")
