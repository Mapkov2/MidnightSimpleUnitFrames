-- Suite-owned frames share MSUF's 0..30 slots without touching legacy Auto.
local MSUF = { UF = {} }
assert(loadfile("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Layers.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
local layers = assert(MSUF.UF.Layers)
local surface = { level = 7, writes = 0 }
function surface:GetFrameLevel() return self.level end
function surface:SetFrameLevel(level) self.level = level; self.writes = self.writes + 1 end

assert(layers.ApplyOwnedSurface(surface, -1) == false and surface.writes == 0)
assert(layers.ApplyOwnedSurface(surface, 5) == true)
assert(surface.level == layers.ElementLevel(5, 0, 0))
assert(layers.ApplyOwnedSurface(surface, 5) == false and surface.writes == 1)
assert(layers.ApplyOwnedSurface(surface, 8) == true)
assert(surface.level == layers.ElementLevel(8, 0, 0))
assert(layers.ApplyOwnedSurface(surface, -1) == true and surface.level == 7)
assert(layers.ApplyOwnedSurface(surface, -1) == false and surface.writes == 3)
print("classic_suite_owned_layer_smoke: ok")
