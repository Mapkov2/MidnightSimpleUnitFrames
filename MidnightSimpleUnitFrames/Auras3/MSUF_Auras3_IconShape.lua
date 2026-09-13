-- Shared aura icon assets and shape normalization; no client rendering policy.
local addonName, MSUF = ...
local A3 = assert(MSUF.MSUF_Auras3)
local Shape = {}
A3.IconShape = Shape
Shape.MEDIA_ROOT = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames")
Shape.RECTANGLE = "RECTANGLE"
Shape.FOLLOW_PORTRAIT = "FOLLOW_PORTRAIT"
Shape.MEDIA = {
    CIRCLE = {
        mask = Shape.MEDIA_ROOT .. "\\Media\\Masks\\circle_mask.tga",
        border = Shape.MEDIA_ROOT .. "\\Media\\Borders\\circle_ring_thin.tga",
    },
    ROUNDED = {
        mask = Shape.MEDIA_ROOT .. "\\Media\\Masks\\rounded_mask.tga",
        border = Shape.MEDIA_ROOT .. "\\Media\\Borders\\msuf_portrait_ring_rounded.tga",
    },
    DIAMOND = {
        mask = Shape.MEDIA_ROOT .. "\\Media\\Masks\\diamond_mask.tga",
        border = Shape.MEDIA_ROOT .. "\\Media\\Borders\\diamond_ring_thin.tga",
    },
    HEXAGON = {
        mask = "Interface\\AddOns\\Blizzard_SharedTalentUI\\talents-hexagon-mask.png",
        border = Shape.MEDIA_ROOT .. "\\Media\\ClassPower\\pip_hex_edge.tga",
    },
    STAR = {
        mask = Shape.MEDIA_ROOT .. "\\Media\\Icons\\Shapes\\raid_star.tga",
        -- The filled silhouette sits behind the masked icon and therefore
        -- becomes a clean outline at the configured outward pixel offsets.
        border = Shape.MEDIA_ROOT .. "\\Media\\Icons\\Shapes\\raid_star.tga",
        borderOuterOnly = true,
        desaturate = true,
    },
    BLIZZARD = {
        maskAtlas = "UI-HUD-UnitFrame-Player-Portrait-Mask",
        swipe = Shape.MEDIA_ROOT .. "\\Media\\Masks\\circle_mask.tga",
        border = Shape.MEDIA_ROOT .. "\\Media\\Borders\\circle_ring_thin.tga",
    },
}
Shape.VALID = {
    RECTANGLE = true, FOLLOW_PORTRAIT = true,
    CIRCLE = true, ROUNDED = true, DIAMOND = true, HEXAGON = true, STAR = true, BLIZZARD = true,
}

function Shape.Normalize(value, fallback)
    value = type(value) == "string" and value:upper() or nil
    if value == "SQUARE" or value == "DEFAULT" or value == "NONE" then value = Shape.RECTANGLE end
    if value == "ROUND" then value = "CIRCLE" end
    if value == "HEX" then value = "HEXAGON" end
    if value == "FOLLOW" or value == "PORTRAIT" or value == "FOLLOWPORTRAIT" then value = Shape.FOLLOW_PORTRAIT end
    if Shape.VALID[value] then return value end
    fallback = type(fallback) == "string" and fallback:upper() or Shape.RECTANGLE
    if fallback == "SQUARE" or fallback == "DEFAULT" or fallback == "NONE" then fallback = Shape.RECTANGLE end
    return Shape.VALID[fallback] and fallback or Shape.RECTANGLE
end

function Shape.Resolve(value, portraitShape)
    local requested = Shape.Normalize(value)
    if requested ~= Shape.FOLLOW_PORTRAIT then return requested, requested end
    portraitShape = type(portraitShape) == "string" and portraitShape:upper() or Shape.RECTANGLE
    if portraitShape == "SQUARE" then portraitShape = Shape.RECTANGLE end
    if not Shape.MEDIA[portraitShape] then portraitShape = Shape.RECTANGLE end
    return portraitShape, requested
end

A3.NormalizeAuraIconShape = Shape.Normalize
A3.ResolveAuraIconShape = Shape.Resolve
A3.AURA_ICON_SHAPE_RECTANGLE = Shape.RECTANGLE
A3.AURA_ICON_SHAPE_FOLLOW_PORTRAIT = Shape.FOLLOW_PORTRAIT

function Shape.ClearMask(region)
    if not region then return end
    local mask = region._msufA3AuraShapeMask
    if mask and region.RemoveMaskTexture then region:RemoveMaskTexture(mask) end
    region._msufA3AuraShapeMask = nil
end

function Shape.ApplyMask(region, mask)
    if not (region and region.AddMaskTexture) then return end
    if region._msufA3AuraShapeMask == mask then return end
    Shape.ClearMask(region)
    if mask then
        region:AddMaskTexture(mask)
        region._msufA3AuraShapeMask = mask
    end
end
