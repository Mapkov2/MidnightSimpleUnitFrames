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

-- The shape stamp. A never-shaped RECTANGLE icon is left alone on Mainline
-- (native AuraButtons keep Blizzard's swipe) and always takes the flat swipe
-- on Classic; once shaped, both clear the mask and restore the flat swipe.
local function NewCooldown()
    local cooldown = setmetatable({ regions = {} }, Region)
    function cooldown:SetSwipeTexture(path) self.swipe = path; self.swipeWrites = (self.swipeWrites or 0) + 1 end
    function cooldown:GetNumRegions() return #self.regions end
    function cooldown:GetRegions() return unpack(self.regions) end
    return cooldown
end
local FLAT = "Interface\\Buttons\\WHITE8X8"
local nativeOwner, nativeCooldown, nativeIcon = NewButton(), NewCooldown(), setmetatable({}, Region)
assert(Shape.ApplyIconShape(nativeOwner, "square", nativeCooldown, true, nativeIcon) == "RECTANGLE"
    and nativeCooldown.swipeWrites == nil and nativeOwner._msufA3AuraShapeMask == nil
    and nativeOwner._msufA3IconShape == "RECTANGLE", "Mainline touched a never-shaped rectangular icon")
local classicOwner, classicCooldown = NewButton(), NewCooldown()
Shape.ApplyIconShape(classicOwner, "RECTANGLE", classicCooldown, false, setmetatable({}, Region))
assert(classicCooldown.swipe == FLAT and classicCooldown.swipeWrites == 1 and classicOwner._msufA3AuraShapeMask == nil,
    "Classic did not stamp the flat swipe on a rectangular icon")
Shape.ApplyIconShape(nativeOwner, "CIRCLE", nativeCooldown, true, nativeIcon)
local circleMask = assert(nativeOwner._msufA3AuraShapeMask, "a CIRCLE stamp made no mask")
assert(nativeIcon.mask == circleMask and nativeCooldown.swipe == Shape.MEDIA.CIRCLE.mask and circleMask.shown,
    "the CIRCLE stamp did not mask the icon and shape the swipe")
Shape.ApplyIconShape(nativeOwner, "RECTANGLE", nativeCooldown, true, nativeIcon)
assert(nativeIcon.mask == nil and circleMask.shown == false and nativeCooldown.swipe == FLAT
    and nativeOwner._msufA3IconShape == "RECTANGLE", "a shaped icon did not return to the flat rectangle")

-- The icon style painters: a shaped shadow is one silhouette outside the
-- border, a rectangular one an edge band; the border is the flat quad when
-- the style has no band texture.
local applied = {}
namespace.BorderStyles = {
    Create = function(_, layer, sublevel, texture) return { layer = layer, sublevel = sublevel, texture = texture } end,
    Hide = function(pieces) pieces.hidden = true end,
    SetTexture = function(pieces, texture) pieces.texture = texture end,
    Apply = function(pieces, _, edge) pieces.hidden = false; pieces.edge = edge; applied[#applied + 1] = pieces end,
}
local styled = NewButton()
local iconStyle = { shadowEnabled = true, shadowSize = 4, borderEnabled = true, borderThickness = 2,
    shadowR = 0, shadowG = 0, shadowB = 0, shadowA = 0.8, borderR = 1, borderG = 1, borderB = 1, borderA = 1 }
A3.ApplyIconStylePreview(styled, iconStyle, 24, "round")
local shapedShadow = assert(styled._msufA3ShapedStyleShadow, "no shaped shadow")
assert(shapedShadow.shown and shapedShadow.layer == "BACKGROUND" and shapedShadow.sublevel == -7
    and shapedShadow.points.TOPLEFT[1] == -6 and shapedShadow.texture == Shape.MEDIA.CIRCLE.mask,
    "the shaped shadow is not the silhouette 6 px out on BACKGROUND(-7)")
assert(#styled._msufA3ShapedStyleBorders == 2, "the shaped border did not draw two rings")
A3.ApplyIconStylePreview(styled, iconStyle, 24, "RECTANGLE")
local band = assert(styled._msufA3StyleShadow, "no rectangular shadow band")
assert(shapedShadow.shown == false and band.edge == 12 and band.layer == "BACKGROUND" and band.sublevel == -7
    and band.texture == Shape.MEDIA_ROOT .. "\\Media\\Borders\\msuf_aura_border_shadow.tga",
    "the rectangular shadow is not a 12 px band behind the icon")
local flat = assert(styled._msufA3StyleBorder, "no flat border quad")
assert(flat.shown and flat.points.TOPLEFT[1] == -2 and styled._msufA3ShapedStyleBorders[1].shown == false,
    "the flat border is not 2 px outside, or a shaped ring stayed shown")
A3.ApplyIconStylePreview(styled, nil, 24, "RECTANGLE")
assert(band.hidden and flat.shown == false, "a cleared style left the shadow or border shown")

-- 2. No backend defines its own copy again, and each backend's stamp names
-- its rectangle choice.
local COPIES = {
    "function Shape%.EnsureMask", "function Shape%.ApplyCooldown", "function A3%.AuraShapeBorderPath",
    "local function SetShapeTexture", "local function SetAuraShapeTexture", "local function AtlasKnown",
    "function A3%.ApplyIconStylePreview", "local function ApplyIconStyleShadow", "local function ApplyIconStyleBorder",
    "local function ApplyShadow", "local function ApplyBorder", "ICON_INNER_BAND_MAX", "Shape%.ApplyCooldownShape%(",
}
local STAMPS = {
    ["MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_Appearance.lua"] = "ApplyIconShape(owner, shape, cooldown, true, ...)",
    ["MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_Visuals.lua"] = "ApplyIconShape(owner, shape, cooldown, false, ...)",
}
for path, call in pairs(STAMPS) do
    local handle = assert(io.open(root .. "/" .. path, "rb"))
    local source = handle:read("*a")
    handle:close()
    assert(source:find(call, 1, true), path .. " no longer stamps through Shape.ApplyIconShape: " .. call)
end
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
