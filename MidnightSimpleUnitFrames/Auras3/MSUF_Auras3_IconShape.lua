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
--- the icon on ARTWORK(7) for an inner style, else outside on BORDER(-1).
--- Shape.ApplyIconBorder draws it for a shaped icon.
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

--- Stamps `shape` on an aura icon: the shape mask on `owner` over every texture
--- in `...`, the cooldown swipe in the shape's media, and
--- owner._msufA3IconShape. Returns the normalized shape. Cold path only.
---
--- The two backends differ only on a RECTANGLE icon that was never shaped,
--- which `leaveUnshapedRectangle` selects:
--- * Mainline passes true (A3.ApplyAuraIconShape in
---   Auras3/Runtime/MSUF_Auras3_Runtime_Appearance.lua): a native AuraButton
---   keeps the swipe and regions Blizzard created, and no mask is made.
--- * Classic passes false (Game/Classic/Auras/MSUF_Auras3_Visuals.lua): its own
---   buttons always take the flat WHITE8X8 swipe, which replaces the colour
---   swipe of Classic's CooldownFrameTemplate (0, 0, 0, 0.8 in
---   Blizzard_FrameXMLUtil/Classic/Cooldown.xml), so skipping it would change
---   how dark an unshaped Classic swipe draws.
function Shape.ApplyIconShape(owner, shape, cooldown, leaveUnshapedRectangle, ...)
    if not owner then return Shape.RECTANGLE end
    shape = Shape.Normalize(shape)
    if leaveUnshapedRectangle and shape == Shape.RECTANGLE then
        local previousShape = owner._msufA3IconShape
        if previousShape == nil or previousShape == Shape.RECTANGLE then
            owner._msufA3IconShape = Shape.RECTANGLE
            return Shape.RECTANGLE
        end
    end
    local mask = shape ~= Shape.RECTANGLE and Shape.EnsureMask(owner, shape) or nil
    if not mask and owner._msufA3AuraShapeMask then owner._msufA3AuraShapeMask:Hide() end
    for index = 1, select("#", ...) do
        local texture = select(index, ...)
        if mask then Shape.ApplyMask(texture, mask) else Shape.ClearMask(texture) end
    end
    Shape.ApplyCooldownShape(cooldown, shape, mask)
    owner._msufA3IconShape = shape
    return shape
end

-- Shared icon style: the border and the shadow are edge bands straddling the
-- icon rect, drawn as eight plain textures by MSUF.BorderStyles. No
-- BackdropTemplate child frame, so the aura button keeps its draw layers and
-- cannot pick up frame protection from a child. Live Mainline buttons draw it
-- in initializeFrame (Runtime_ButtonVisuals PrepareStage.ApplyIconStyle),
-- Classic buttons in their layout pass, and both backends' previews through
-- A3.ApplyIconStylePreview.
local ICON_SHADOW_TEXTURE = Shape.MEDIA_ROOT .. "\\Media\\Borders\\msuf_aura_border_shadow.tga"

--- Soft drop shadow behind the icon. `shadowSize` is the visible extent in
--- pixels, so the band is twice that: its inner half hides behind the icon and
--- the whole falloff lands outside. A shaped icon gets one silhouette texture
--- instead. The shadow starts outside the border ring when both are on, so a
--- thick ring never eats the halo.
function Shape.ApplyIconShadow(button, style, size, shape)
    local BorderStyles = MSUF.BorderStyles
    local pieces = button._msufA3StyleShadow
    local shapedShadow = button._msufA3ShapedStyleShadow
    if shape and shape ~= Shape.RECTANGLE then
        if pieces and BorderStyles then BorderStyles.Hide(pieces) end
        if not (style and style.shadowEnabled) then
            if shapedShadow then shapedShadow:Hide() end
            return
        end
        if not shapedShadow then
            shapedShadow = PixelLayoutRegion(button:CreateTexture(nil, "BACKGROUND", nil, -7))
            button._msufA3ShapedStyleShadow = shapedShadow
        end
        if not Shape.SetTexture(shapedShadow, shape, false) then
            shapedShadow:Hide()
            return
        end
        local extent = (style.shadowSize or 0) + (style.borderEnabled and style.borderThickness or 0)
        shapedShadow:ClearAllPoints()
        shapedShadow:SetPoint("TOPLEFT", button, "TOPLEFT", -extent, extent)
        shapedShadow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", extent, -extent)
        shapedShadow:SetVertexColor(style.shadowR, style.shadowG, style.shadowB, style.shadowA)
        shapedShadow:Show()
        return
    end
    if shapedShadow then shapedShadow:Hide() end
    if not (style and style.shadowEnabled and BorderStyles) then
        if pieces and BorderStyles then BorderStyles.Hide(pieces) end
        return
    end
    if not pieces then
        pieces = BorderStyles.Create(button, "BACKGROUND", -7, ICON_SHADOW_TEXTURE)
        button._msufA3StyleShadow = pieces
    end
    local extent = style.shadowSize + (style.borderEnabled and style.borderThickness or 0)
    BorderStyles.Apply(pieces, button, extent * 2, size, size,
        style.shadowR, style.shadowG, style.shadowB, style.shadowA)
end

--- Largest inner band we allow, as a share of the icon. An "inner" style shades
--- the artwork itself, so an unclamped thickness would black the icon out.
--- 0.3 matches the reach of the classic Masque shadow skins, whose dark band
--- covers a little under a third of the icon.
local ICON_INNER_BAND_MAX = 0.3

--- Border ring. SOLID keeps the original single stretched quad (one texture,
--- pixel-crisp at any thickness); every other style is an edgeFile band; a
--- shaped icon draws Shape.ApplyBorderRings.
---
--- Outer styles frame the icon: the band straddles its edge and draws behind
--- it at BORDER(-1). Inner styles (Shadow) shade the icon instead: the band
--- sits wholly inside and draws on top at ARTWORK(7), above the icon but still
--- below the OVERLAY dispel border.
function Shape.ApplyIconBorder(button, style, size, shape)
    local BorderStyles = MSUF.BorderStyles
    local flat = button._msufA3StyleBorder
    local pieces = button._msufA3StyleBorderPieces
    if shape and shape ~= Shape.RECTANGLE then
        if flat then flat:Hide() end
        if pieces and BorderStyles then BorderStyles.Hide(pieces) end
        return Shape.ApplyBorderRings(button, style, shape)
    end
    local rings = button._msufA3ShapedStyleBorders
    for i = 1, rings and #rings or 0 do rings[i]:Hide() end
    if not (style and style.borderEnabled) then
        if flat then flat:Hide() end
        if pieces and BorderStyles then BorderStyles.Hide(pieces) end
        return
    end
    local texture = style.borderTexture
    if texture and BorderStyles then
        if flat then flat:Hide() end
        local inner = style.borderPlacement == "inner"
        local edge = style.borderEdge or 8
        local inset = 0
        if inner then
            edge = math_max(1, math_min(edge, math_floor(size * ICON_INNER_BAND_MAX)))
            inset = edge * 0.5
        end
        -- The draw layer is baked into the textures, so a placement change has
        -- to rebuild them rather than just re-anchor.
        if pieces and button._msufA3StyleBorderInner ~= inner then
            BorderStyles.Hide(pieces)
            pieces = nil
        end
        if not pieces then
            pieces = BorderStyles.Create(button, inner and "ARTWORK" or "BORDER", inner and 7 or -1, texture)
            button._msufA3StyleBorderPieces = pieces
            button._msufA3StyleBorderInner = inner
        else
            BorderStyles.SetTexture(pieces, texture)
        end
        BorderStyles.Apply(pieces, button, edge, size, size,
            style.borderR, style.borderG, style.borderB, style.borderA, inset)
        return
    end
    if pieces and BorderStyles then BorderStyles.Hide(pieces) end
    if not flat then
        flat = PixelLayoutRegion(button:CreateTexture(nil, "BORDER", nil, -1))
        flat:SetTexture("Interface\\Buttons\\WHITE8X8")
        button._msufA3StyleBorder = flat
    end
    local extent = style.borderThickness
    flat:ClearAllPoints()
    flat:SetPoint("TOPLEFT", button, "TOPLEFT", -extent, extent)
    flat:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", extent, -extent)
    flat:SetVertexColor(style.borderR, style.borderG, style.borderB, style.borderA)
    flat:Show()
end

--- Stamps the shared icon style onto a button or a preview dummy with the same
--- painters live buttons use, so Edit Mode lanes and menu mocks stay
--- pixel-identical to the runtime on both backends. Cold path only; passing nil
--- (opted-out scope, bar-only lane) hides any pieces a previous stamp created.
function A3.ApplyIconStylePreview(button, style, size, shape)
    if not button then return end
    shape = Shape.Normalize(shape)
    Shape.ApplyIconShadow(button, style, size, shape)
    Shape.ApplyIconBorder(button, style, size, shape)
end
