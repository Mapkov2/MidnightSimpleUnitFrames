-- Shared aura icon assets, shape normalization and the shape painters both
-- aura backends use; no client rendering policy.
local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
local addonName, MSUF = ...
local type, select = type, select
local math_floor, math_max, math_min = math.floor, math.max, math.min
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

--- Vanilla and TBC keep the pre-Dragonflight HUD art, so the Blizzard portrait
--- mask atlas may not exist there. SetAtlas raises on an unknown atlas name;
--- probe once per name and fall back to the shape's own circle media.
local atlasKnown = {}
function Shape.AtlasKnown(name)
    if type(name) ~= "string" or name == "" then return false end
    local known = atlasKnown[name]
    if known == nil then
        local api = _G.C_Texture
        if api and type(api.GetAtlasInfo) == "function" then
            known = api.GetAtlasInfo(name) ~= nil
        else
            -- No probe API (test harness / very old client): keep the
            -- pre-guard behavior and let SetAtlas decide.
            known = true
        end
        atlasKnown[name] = known
    end
    return known
end

--- The shape mask on `owner`, created once and repointed to the shape's media.
function Shape.EnsureMask(owner, shape)
    local media = Shape.MEDIA[shape]
    if not (owner and media and owner.CreateMaskTexture) then return nil end
    local mask = owner._msufA3AuraShapeMask
    if not mask then
        mask = owner:CreateMaskTexture(nil, "BACKGROUND")
        owner._msufA3AuraShapeMask = mask
    end
    if media.maskAtlas and mask.SetAtlas and Shape.AtlasKnown(media.maskAtlas) then
        mask:SetAtlas(media.maskAtlas)
    else
        mask:SetTexture(media.mask or media.swipe)
    end
    mask:ClearAllPoints()
    mask:SetAllPoints(owner)
    mask:Show()
    return mask
end

--- The cooldown swipe in the shape's media, and its regions under `mask`.
function Shape.ApplyCooldownShape(cooldown, shape, mask)
    if not cooldown then return end
    local media = Shape.MEDIA[shape]
    if cooldown.SetSwipeTexture then
        cooldown:SetSwipeTexture(media and (media.swipe or media.mask) or "Interface\\Buttons\\WHITE8X8")
    end
    if not (cooldown.GetNumRegions and cooldown.GetRegions) then return end
    for index = 1, cooldown:GetNumRegions() do
        local region = select(index, cooldown:GetRegions())
        if mask then Shape.ApplyMask(region, mask) else Shape.ClearMask(region) end
    end
end

function A3.AuraShapeBorderPath(shape)
    local media = Shape.MEDIA[Shape.Normalize(shape)]
    return media and media.border or nil
end

--- Points `texture` at the shape's border ring (`useBorder`) or its filled
--- silhouette. Returns false for a shape without media.
function Shape.SetTexture(texture, shape, useBorder)
    local media = Shape.MEDIA[shape]
    if not (texture and media) then return false end
    if useBorder == true then
        texture:SetTexture(media.border)
    elseif media.maskAtlas and texture.SetAtlas and Shape.AtlasKnown(media.maskAtlas) then
        texture:SetAtlas(media.maskAtlas)
    else
        texture:SetTexture(media.swipe or media.mask)
    end
    if texture.SetDesaturated then texture:SetDesaturated(media.desaturate == true) end
    if texture.SetTexCoord then texture:SetTexCoord(0, 1, 0, 1) end
    return true
end

--- A shaped icon's border: up to eight stacked shape rings on `button`, inside
--- the icon on ARTWORK(7) for an inner style, else outside on BORDER(-1). Both
--- icon-style painters draw it (ApplyIconStyleBorder in
--- Auras3/Runtime/MSUF_Auras3_Runtime_ButtonVisuals.lua and the Classic one in
--- Game/Classic/Auras/MSUF_Auras3_Visuals.lua).
function Shape.ApplyBorderRings(button, style, shape)
    local rings = button._msufA3ShapedStyleBorders
    if not (style and style.borderEnabled) then
        for i = 1, rings and #rings or 0 do rings[i]:Hide() end
        return
    end
    rings = rings or {}
    button._msufA3ShapedStyleBorders = rings
    local media = Shape.MEDIA[shape]
    local inner = style.borderPlacement == "inner" and not (media and media.borderOuterOnly)
    local count = math_max(1, math_min(8, math_floor((style.borderThickness or 1) + 0.5)))
    for i = 1, count do
        local ring = rings[i]
        if not ring then
            ring = PixelLayoutRegion(button:CreateTexture(nil, inner and "ARTWORK" or "BORDER", nil, inner and 7 or -1))
            rings[i] = ring
        elseif ring.SetDrawLayer then
            ring:SetDrawLayer(inner and "ARTWORK" or "BORDER", inner and 7 or -1)
        end
        if not Shape.SetTexture(ring, shape, true) then ring:Hide(); return end
        local inset = inner and (i - 1) or -i
        ring:ClearAllPoints()
        ring:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
        ring:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
        ring:SetVertexColor(style.borderR, style.borderG, style.borderB, style.borderA)
        ring:Show()
    end
    for i = count + 1, #rings do rings[i]:Hide() end
end
