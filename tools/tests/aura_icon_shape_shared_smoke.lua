-- The icon-shape painters both aura backends use live once, in
-- Auras3/MSUF_Auras3_IconShape.lua, which every client loads before either
-- backend (re-review 2026-10-02: Classic's Visuals.lua and Retail's
-- Runtime_Appearance/Runtime_ButtonVisuals kept drifting copies of the mask,
-- the cooldown swipe, the shape textures and the shaped border rings).
-- Part 1 runs the shared painters on widget stubs; part 2 fails when a backend
-- defines its own copy again.
-- Argument: the repository root.
local root = assert(arg[1], "repository root argument missing")
root = (tostring(root):gsub("\\", "/"):gsub("/+$", ""))
local ADDON = root .. "/MidnightSimpleUnitFrames/"

local knownAtlases = { ["UI-HUD-UnitFrame-Player-Portrait-Mask"] = false }
_G.C_Texture = { GetAtlasInfo = function(name) if knownAtlases[name] then return {} end return nil end }

local Region = {}
Region.__index = Region
function Region:SetTexture(path) self.texture, self.atlas = path, nil end
function Region:SetAtlas(name) self.atlas, self.texture = name, nil end
function Region:SetDesaturated(value) self.desaturated = value end
function Region:SetTexCoord() end
function Region:SetDrawLayer(layer, sublevel) self.layer, self.sublevel = layer, sublevel end
function Region:ClearAllPoints() self.points = {} end
function Region:SetPoint(point, _, _, x, y) self.points[point] = { x, y } end
function Region:SetAllPoints() end
function Region:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
function Region:Show() self.shown = true end
function Region:Hide() self.shown = false end
function Region:AddMaskTexture(mask) self.mask = mask end
function Region:RemoveMaskTexture() self.mask = nil end
local function NewButton()
    local button = setmetatable({}, Region)
    function button:CreateTexture(_, layer, _, sublevel)
        return setmetatable({ layer = layer, sublevel = sublevel, points = {} }, Region)
    end
    function button:CreateMaskTexture() return setmetatable({ points = {} }, Region) end
    return button
end

local namespace = { MSUF_Auras3 = {} }
assert(loadfile(ADDON .. "Auras3/MSUF_Auras3_IconShape.lua"))("MidnightSimpleUnitFrames", namespace)
local A3 = namespace.MSUF_Auras3
local Shape = assert(A3.IconShape, "the shared icon shapes did not load")
for _, name in ipairs({ "AtlasKnown", "EnsureMask", "ApplyCooldownShape", "SetTexture", "ApplyBorderRings" }) do
    assert(type(Shape[name]) == "function", "IconShape exports no shared Shape." .. name)
end

-- Shaped border rings: count from the thickness, inner on ARTWORK(7) with
-- inward insets, outer on BORDER(-1) outside the icon, STAR always outer.
local style = { borderEnabled = true, borderThickness = 3, borderPlacement = "inner",
    borderR = 1, borderG = 0.5, borderB = 0, borderA = 1 }
local button = NewButton()
Shape.ApplyBorderRings(button, style, "CIRCLE")
local rings = assert(button._msufA3ShapedStyleBorders, "no shaped border rings")
assert(#rings == 3 and rings[3].shown and rings[1].layer == "ARTWORK" and rings[1].sublevel == 7,
    "inner shaped rings are not three ARTWORK(7) rings")
assert(rings[2].points.TOPLEFT[1] == 1 and rings[2].texture == Shape.MEDIA.CIRCLE.border,
    "an inner ring is not inset by its index or not the shape's ring texture")
style.borderPlacement, style.borderThickness = "outer", 1
Shape.ApplyBorderRings(button, style, "CIRCLE")
assert(rings[1].layer == "BORDER" and rings[1].sublevel == -1 and rings[1].points.TOPLEFT[1] == -1
    and rings[2].shown == false and rings[3].shown == false, "outer rings are not one BORDER(-1) ring outside")
style.borderPlacement = "inner"
local star = NewButton()
Shape.ApplyBorderRings(star, style, "STAR")
assert(star._msufA3ShapedStyleBorders[1].layer == "BORDER", "STAR rings must stay outer")
style.borderEnabled = false
Shape.ApplyBorderRings(button, style, "CIRCLE")
assert(rings[1].shown == false, "a disabled border left a shaped ring shown")

-- The Blizzard portrait mask atlas is probed first: unknown on this client, the
-- silhouette and the mask fall back to the shape's own circle media.
local silhouette = setmetatable({ points = {} }, Region)
assert(Shape.SetTexture(silhouette, "BLIZZARD", false) == true and silhouette.atlas == nil
    and silhouette.texture == Shape.MEDIA.BLIZZARD.swipe, "an unknown mask atlas was set")
local owner = NewButton()
local mask = Shape.EnsureMask(owner, "BLIZZARD")
assert(mask and mask.texture == Shape.MEDIA.BLIZZARD.swipe and mask.shown, "the mask did not fall back to the swipe")
knownAtlases["UI-HUD-UnitFrame-Player-Portrait-Mask"] = true
local probed = setmetatable({ points = {} }, Region)
Shape.SetTexture(probed, "BLIZZARD", false)
-- The probe result is cached per name for the session.
assert(probed.atlas == nil, "the atlas probe result was not cached")
assert(A3.AuraShapeBorderPath("round") == Shape.MEDIA.CIRCLE.border, "the shared border path lookup changed")

-- 2. No backend defines its own copy again.
local COPIES = {
    "function Shape%.EnsureMask", "function Shape%.ApplyCooldown", "function A3%.AuraShapeBorderPath",
    "local function SetShapeTexture", "local function SetAuraShapeTexture", "local function AtlasKnown",
}
local pipe = assert(io.popen('git -C "' .. root .. '" ls-files -- MidnightSimpleUnitFrames/Auras3 "MidnightSimpleUnitFrames/Game/*/Auras/*"'))
local failures, files = {}, 0
for path in pipe:lines() do
    if path:match("%.lua$") and not path:match("MSUF_Auras3_IconShape%.lua$") then
        files = files + 1
        local handle = assert(io.open(root .. "/" .. path, "rb"))
        local source = handle:read("*a")
        handle:close()
        for _, copy in ipairs(COPIES) do
            if source:find(copy) then failures[#failures + 1] = path .. ": " .. copy:gsub("%%", "") end
        end
    end
end
pipe:close()
assert(files > 80, "the aura file list is incomplete (" .. files .. " files)")
if #failures > 0 then error("aura shape painters copied outside IconShape.lua:\n  " .. table.concat(failures, "\n  "), 0) end
print("aura icon shape shared smoke: OK (" .. files .. " files)")
