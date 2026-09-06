-- Auras3 runtime: Appearance.
-- Icon shapes, dispel assets and color maps shared by live initialization and addon-owned previews. Native regions are styled before handoff.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.Appearance = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local SpellIndicatorsRuntime = A3.SpellIndicators
local math_floor = math.floor
local math_max = math.max
local tonumber = tonumber
local tostring = tostring
local type = type
local Clamp01 = dependencies.Platform.Clamp01
local ClampNumber = dependencies.Platform.ClampNumber
local CreateFrame = dependencies.Platform.CreateFrame

-- Icon shape ownership is shared by native initialization and previews.
-- Keep one shape/asset table so both surfaces resolve identical geometry.
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

function Shape.EnsureMask(owner, shape)
    local media = Shape.MEDIA[shape]
    if not (owner and media and owner.CreateMaskTexture) then return nil end
    local mask = owner._msufA3AuraShapeMask
    if not mask then
        mask = owner:CreateMaskTexture(nil, "BACKGROUND")
        owner._msufA3AuraShapeMask = mask
    end
    if media.maskAtlas and mask.SetAtlas then
        mask:SetAtlas(media.maskAtlas)
    else
        mask:SetTexture(media.mask)
    end
    mask:ClearAllPoints()
    mask:SetAllPoints(owner)
    mask:Show()
    return mask
end

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

--- Cold-path-only shape stamp for runtime AuraButtons and reusable previews.
--- RECTANGLE deliberately creates no mask and leaves the normal renderer alone.
function A3.ApplyAuraIconShape(owner, shape, cooldown, ...)
    if not owner then return Shape.RECTANGLE end
    shape = Shape.Normalize(shape)
    local previousShape = owner._msufA3IconShape
    if shape == Shape.RECTANGLE
        and (previousShape == nil or previousShape == Shape.RECTANGLE)
    then
        owner._msufA3IconShape = Shape.RECTANGLE
        return Shape.RECTANGLE
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

function A3.AuraShapeBorderPath(shape)
    local media = Shape.MEDIA[Shape.Normalize(shape)]
    return media and media.border or nil
end

-- Blizzard's AuraButtonArtTemplate uses a 30px icon inside a 40px debuff
-- border. SetAtlas(..., IgnoreAtlasSize) keeps our region size, so preserve
-- that native 4:3 geometry at every configured aura size: five pixels of
-- padding per side at 30px, scaled and pixel-rounded.
function A3.NativeAuraDispelBorderPadding(size)
    return math_max(1, math_floor(((tonumber(size) or 24) / 6) + 0.5))
end

-- PTR 8 pandemic presentation. Blizzard owns the secret shown state and the
-- only recurring update; MSUF creates and styles a static child once inside
-- AuraContainer.initializeFrame. No addon ticker or Lua OnUpdate is added.
function A3.NormalizePandemicStyle(value)
    value = tostring(value or "BORDER"):upper()
    if value == "BORDER" or value == "TINT" or value == "BORDER_TINT" then return value end
    if value == "GLOW" or value == "BORDER_GLOW" then return "BORDER" end
    if value == "GLOW_TINT" then return "TINT" end
    if value == "ALL" then return "BORDER_TINT" end
    return "BORDER"
end

function A3.ApplyPandemicVisual(owner, config, visible)
    if not (owner and type(config) == "table") then return nil end
    local host = owner._msufA3PandemicRegion
    if not host then
        host = CreateFrame("Frame", nil, owner)
        host:EnableMouse(false)
        host.tint = host:CreateTexture(nil, "ARTWORK", nil, 3)
        host.shapeBorder = host:CreateTexture(nil, "OVERLAY", nil, 3)
        host.edges = {}
        for index = 1, 4 do
            host.edges[index] = host:CreateTexture(nil, "OVERLAY", nil, 3)
            host.edges[index]:SetTexture("Interface\\Buttons\\WHITE8X8")
        end
        owner._msufA3PandemicRegion = host
    end

    host:ClearAllPoints()
    host:SetAllPoints(owner)
    if host.SetFrameLevel and owner.GetFrameLevel then
        host:SetFrameLevel((owner:GetFrameLevel() or 0) + 6)
    end

    local style = A3.NormalizePandemicStyle(config.pandemicStyle)
    local hasBorder = style == "BORDER" or style == "BORDER_TINT"
    local hasTint = style == "TINT" or style == "BORDER_TINT"
    local color = type(config.pandemicColor) == "table" and config.pandemicColor or nil
    local r = Clamp01(color and (color[1] or color.r), 1)
    local g = Clamp01(color and (color[2] or color.g), 0.24)
    local b = Clamp01(color and (color[3] or color.b), 0.08)
    local borderAlpha = Clamp01(config.pandemicBorderAlpha, 1)
    local tintAlpha = Clamp01(config.pandemicTintAlpha, 0.22)
    local thickness = ClampNumber(config.pandemicThickness, 2, 1, 12)
    local padding = ClampNumber(config.pandemicPadding, 1, -8, 16)
    local blend = tostring(config.pandemicBlend or "ADD"):upper() == "BLEND" and "BLEND" or "ADD"
    local shape = Shape.Normalize(config.iconShape)
    local shapedBorder = shape ~= Shape.RECTANGLE and A3.AuraShapeBorderPath(shape) or nil

    host.tint:ClearAllPoints()
    host.tint:SetAllPoints(owner)
    host.tint:SetTexture("Interface\\Buttons\\WHITE8X8")
    host.tint:SetVertexColor(r, g, b, tintAlpha)
    host.tint:SetBlendMode(blend)
    local mask = shape ~= Shape.RECTANGLE and Shape.EnsureMask(owner, shape) or nil
    if mask then Shape.ApplyMask(host.tint, mask) else Shape.ClearMask(host.tint) end
    host.tint:SetShown(hasTint)

    host.shapeBorder:ClearAllPoints()
    host.shapeBorder:SetPoint("TOPLEFT", owner, "TOPLEFT", -padding, padding)
    host.shapeBorder:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", padding, -padding)
    if shapedBorder then
        host.shapeBorder:SetTexture(shapedBorder)
        if host.shapeBorder.SetTexCoord then host.shapeBorder:SetTexCoord(0, 1, 0, 1) end
    end
    host.shapeBorder:SetVertexColor(r, g, b, borderAlpha)
    host.shapeBorder:SetBlendMode(blend)
    host.shapeBorder:SetShown(hasBorder and shapedBorder ~= nil)

    local edges = host.edges
    edges[1]:ClearAllPoints(); edges[1]:SetPoint("TOPLEFT", owner, "TOPLEFT", -padding, padding); edges[1]:SetPoint("TOPRIGHT", owner, "TOPRIGHT", padding, padding); edges[1]:SetHeight(thickness)
    edges[2]:ClearAllPoints(); edges[2]:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", -padding, -padding); edges[2]:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", padding, -padding); edges[2]:SetHeight(thickness)
    edges[3]:ClearAllPoints(); edges[3]:SetPoint("TOPLEFT", owner, "TOPLEFT", -padding, padding); edges[3]:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", -padding, -padding); edges[3]:SetWidth(thickness)
    edges[4]:ClearAllPoints(); edges[4]:SetPoint("TOPRIGHT", owner, "TOPRIGHT", padding, padding); edges[4]:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", padding, -padding); edges[4]:SetWidth(thickness)
    for index = 1, 4 do
        edges[index]:SetVertexColor(r, g, b, borderAlpha)
        edges[index]:SetBlendMode(blend)
        edges[index]:SetShown(hasBorder and shapedBorder == nil)
    end
    host:SetShown(visible == true)
    return host
end

function A3.BindPandemicRegion(button, lane)
    if not (button and lane and lane.pandemicEnabled == true
        and type(button.AddPandemicRegion) == "function")
    then
        return false
    end
    local bound = false
    if lane.pandemicVisualEnabled ~= false then
        local region = A3.ApplyPandemicVisual(button, lane, false)
        if region then
            button:AddPandemicRegion(region)
            bound = true
        end
    end
    local bindFrameEffect = SpellIndicatorsRuntime.BindPandemicFrameEffect
    if type(lane.pandemicFrameEffect) == "table" and type(bindFrameEffect) == "function" then
        bound = bindFrameEffect(button, lane.pandemicFrameEffect, button._msufA3ParentFrame) or bound
    end
    return bound
end

function A3.NormalizeStealableStyle(value)
    value = tostring(value or "BORDER_ICON"):upper()
    if value == "BORDER" or value == "BORDER_ICON" or value == "ICON" then return value end
    return "BORDER_ICON"
end

function A3.GetStealableTextureOptions(style)
    local options = A3._stealableTextureOptions or {
        showAlways = false,
        showWhenHarmful = false,
        showWhenHelpful = true,
        showWithoutDispelType = true,
    }
    A3._stealableTextureOptions = options
    local enums = _G.Enum
    local styles = enums and enums.CustomAuraButtonDispelTypeTextureStyle
    local filters = enums and enums.CustomAuraButtonDispelTypeStealableFilter
    style = A3.NormalizeStealableStyle(style)
    options.stealableFilter = filters and filters.Stealable or nil
    options.style = styles and (style == "BORDER" and styles.Border
        or style == "ICON" and styles.Icon or styles.BorderWithIcon) or nil
    return options
end

function A3.GetPurgeSensorTextureOptions(sensor)
    if sensor and sensor._textureOptions then return sensor._textureOptions end
    local enums = _G.Enum
    local styles = enums and enums.CustomAuraButtonDispelTypeTextureStyle
    local r = Clamp01(sensor and sensor.r, 1)
    local g = Clamp01(sensor and sensor.g, 0.85)
    local b = Clamp01(sensor and sensor.b, 0)
    local color = _G.CreateColor and _G.CreateColor(r, g, b, 1) or nil
    local map = color and {
        None = color, Magic = color, Curse = color,
        Disease = color, Poison = color, Bleed = color,
    } or nil
    local options = {
        -- The AuraSlot itself is already restricted to isStealable=true. PTR 8
        -- showAlways therefore avoids redundant dispel-type eligibility work
        -- while retaining the user-selected Purge color below.
        showAlways = true,
        showWhenHarmful = false,
        showWhenHelpful = true,
        showWithoutDispelType = true,
        style = styles and styles.PreserveAsset or nil,
        customDispelColorMap = map,
    }
    if sensor then sensor._textureOptions = options end
    return options
end
A3.DEFAULT_NATIVE_HIGHLIGHT_PRIORITY = A3.DEFAULT_NATIVE_HIGHLIGHT_PRIORITY
    or { "dispel", "aggro", "purge", "bossTarget" }
A3.DEFAULT_PANDEMIC_COLOR = A3.DEFAULT_PANDEMIC_COLOR or { 1, 0.24, 0.08 }

local AURA_BORDER_OPTIONS = {
    showWhenHarmful = true,
    showWhenHelpful = false,
}
-- Sensors highlight slot presence, so they must also fire for debuffs without
-- a dispel type (e.g. PLAYER_CAST trigger). PTR 7's option processor hides
-- untyped auras unless showWithoutDispelType is set; older clients ignore it.
local AURA_SENSOR_BORDER_OPTIONS = {
    showWhenHarmful = true,
    showWhenHelpful = false,
    showWithoutDispelType = true,
}
local AURA_SENSOR_OVERLAY_OPTIONS = {
    showWhenHarmful = true,
    showWhenHelpful = false,
    showWithoutDispelType = true,
}
-- Dispel-type SYMBOL sensors. Unlike border/overlay the visible art IS the
-- dispel type, so these never use PreserveAsset. Seven sets:
--   BLIZZARD         -> Icon           (stock RaidFrame-Icon-Debuff<Type>)
--   BLIZZARD_RING    -> BorderWithIcon (stock ring plus its corner symbol)
--   BLIZZARD_BORDER  -> Border         (stock ring, no symbol)
--   MSUF_LETTERS/SHAPES/GLYPHS/MINIMAL -> CustomAsset (Media/Icons/DispelTypes)
-- Blizzard resolves the secret dispelName inside its secure partition in every
-- case; MSUF only ever hands over a texture and an options table.
-- showWithoutDispelType stays FALSE here: a symbol for "no type" would be a
-- blank texture (DEBUFF_DISPLAY_INFO.None has no dispelIconAtlas).
-- The same symbol descriptor table is extended by the compiler, native
-- initializer and preview owner; do not fork its asset or layout rules.
local DS = {
    types = { "Magic", "Curse", "Disease", "Poison", "Bleed" },
    -- Used only when AuraUtil is unavailable (for example in deterministic
    -- menu smokes). Live clients resolve the current Blizzard defaults through
    -- AuraUtil.GetAuraBorderColor so leaving an override disabled remains
    -- exactly native even if Blizzard adjusts a default later.
    defaultColors = {
        Magic = { 0.20, 0.60, 1.00 },
        Curse = { 0.60, 0.00, 1.00 },
        Disease = { 0.60, 0.40, 0.00 },
        Poison = { 0.00, 0.60, 0.00 },
        Bleed = { 0.80, 0.10, 0.10 },
    },
    -- Blizzard's own per-type atlases, mirroring AuraUtil's DEBUFF_DISPLAY_INFO
    -- on 12.1. Held literally so the menu preview -- which has no aura and
    -- therefore never reaches AuraUtil -- can draw exactly the same art.
    icons = {
        Magic = "RaidFrame-Icon-DebuffMagic",
        Curse = "RaidFrame-Icon-DebuffCurse",
        Disease = "RaidFrame-Icon-DebuffDisease",
        Poison = "RaidFrame-Icon-DebuffPoison",
        Bleed = "RaidFrame-Icon-DebuffBleed",
    },
    rings = {
        Magic = "ui-debuff-border-magic-icon",
        Curse = "ui-debuff-border-curse-icon",
        Disease = "ui-debuff-border-disease-icon",
        Poison = "ui-debuff-border-poison-icon",
        Bleed = "ui-debuff-border-bleed-icon",
    },
    borders = {
        Magic = "ui-debuff-border-magic-noicon",
        Curse = "ui-debuff-border-curse-noicon",
        Disease = "ui-debuff-border-disease-noicon",
        Poison = "ui-debuff-border-poison-noicon",
        Bleed = "ui-debuff-border-bleed-noicon",
    },
    -- MSUF's own art, one folder per set.
    folders = {
        MSUF_LETTERS = "Letters",
        MSUF_SHAPES = "Shapes",
        MSUF_GLYPHS = "Glyphs",
        MSUF_MINIMAL = "Minimal",
    },
    options = {
        showWhenHarmful = true,
        showWhenHelpful = false,
        showWithoutDispelType = false,
    },
    assetCache = {},
    -- One immutable candidate-filter table per dispel type. ALL mode compiles
    -- often (every spec apply, every preview row); allocating five filter
    -- tables per compile would be pure garbage for values that never change.
    filters = {
        Magic = { includeDispelTypes = { Magic = true } },
        Curse = { includeDispelTypes = { Curse = true } },
        Disease = { includeDispelTypes = { Disease = true } },
        Poison = { includeDispelTypes = { Poison = true } },
        Bleed = { includeDispelTypes = { Bleed = true } },
    },
}
DS.mediaPath = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames")
    .. "\\Media\\Icons\\DispelTypes\\"
A3.DispelSymbol = DS

--- Effective harmful-aura color for one Blizzard dispel type. The optional
--- override is deliberately sparse: an absent entry falls straight through
--- to AuraUtil, preserving Blizzard's current color without copying it into
--- SavedVariables.
function A3.GetDispelTypeColor(dispelType, useOverride)
    dispelType = DS.defaultColors[dispelType] and dispelType or "Magic"
    if useOverride ~= false then
        local general = _G.MSUF_DB and _G.MSUF_DB.general
        local overrides = general and general.dispelTypeColorOverrides
        local color = type(overrides) == "table" and overrides[dispelType]
        if type(color) == "table" then
            local r = tonumber(color[1] or color.r)
            local g = tonumber(color[2] or color.g)
            local b = tonumber(color[3] or color.b)
            if r and g and b then return Clamp01(r, 0), Clamp01(g, 0), Clamp01(b, 0) end
        end
    end
    local auraUtil = _G.AuraUtil
    local color = auraUtil and type(auraUtil.GetAuraBorderColor) == "function"
        and auraUtil.GetAuraBorderColor(dispelType) or nil
    if color and type(color.GetRGB) == "function" then
        local r, g, b = color:GetRGB()
        if r ~= nil and g ~= nil and b ~= nil then return r, g, b end
    end
    if type(color) == "table" then
        local r = tonumber(color.r or color[1])
        local g = tonumber(color.g or color[2])
        local b = tonumber(color.b or color[3])
        if r and g and b then return r, g, b end
    end
    local fallback = DS.defaultColors[dispelType]
    return fallback[1], fallback[2], fallback[3]
end

function A3.SetDispelColorPreviewType(dispelType)
    if not DS.defaultColors[dispelType] then return false end
    A3._dispelColorPreviewType = dispelType
    return true
end

function A3.GetDispelColorPreviewType()
    return DS.defaultColors[A3._dispelColorPreviewType] and A3._dispelColorPreviewType or "Magic"
end

function A3.HasDispelTypeColorOverride(dispelType)
    local general = _G.MSUF_DB and _G.MSUF_DB.general
    local overrides = general and general.dispelTypeColorOverrides
    local color = type(overrides) == "table" and overrides[dispelType]
    return type(color) == "table"
        and tonumber(color[1] or color.r) ~= nil
        and tonumber(color[2] or color.g) ~= nil
        and tonumber(color[3] or color.b) ~= nil
end

function A3.SetDispelVertexColor(texture, dispelType, useOverride, alpha)
    if not (texture and texture.SetVertexColor) then return false end
    local r, g, b = A3.GetDispelTypeColor(dispelType, useOverride)
    texture:SetVertexColor(r, g, b, Clamp01(alpha, 1))
    return true
end

function A3.SetDispelColorTexture(texture, dispelType, useOverride, alpha)
    if not (texture and texture.SetColorTexture) then return false end
    local r, g, b = A3.GetDispelTypeColor(dispelType, useOverride)
    texture:SetColorTexture(r, g, b, Clamp01(alpha, 1))
    return true
end

--- Keep the most recently edited type first so even a one-icon preview shows
--- the change. Wider aura lanes continue through the remaining Blizzard types.
function A3.PreviewDispelTypeForIndex(index)
    local active = A3.GetDispelColorPreviewType()
    local activeIndex = 1
    for i = 1, #DS.types do
        if DS.types[i] == active then activeIndex = i break end
    end
    index = math_max(1, math_floor(tonumber(index) or 1))
    return DS.types[((activeIndex + index - 2) % #DS.types) + 1]
end

--- Blizzard secure-copies native texture options at bind time. Build and cache
--- a map containing only actual overrides; nil means the default path is
--- structurally identical to the pre-feature configuration.
function A3.GetCustomDispelColorMap()
    local general = _G.MSUF_DB and _G.MSUF_DB.general
    local overrides = general and general.dispelTypeColorOverrides
    local generation = tonumber(A3._nativeVisualGen) or 0
    if A3._customDispelColorOverrides == overrides
        and A3._customDispelColorMapGeneration == generation then
        return A3._customDispelColorMap
    end
    A3._customDispelColorOverrides = overrides
    A3._customDispelColorMapGeneration = generation
    if type(overrides) ~= "table" or type(_G.CreateColor) ~= "function" then
        A3._customDispelColorMap = nil
        return nil
    end
    local map
    for i = 1, #DS.types do
        local dispelType = DS.types[i]
        local color = overrides[dispelType]
        local r = type(color) == "table" and tonumber(color[1] or color.r) or nil
        local g = type(color) == "table" and tonumber(color[2] or color.g) or nil
        local b = type(color) == "table" and tonumber(color[3] or color.b) or nil
        if r and g and b then
            map = map or {}
            map[dispelType] = _G.CreateColor(Clamp01(r, 0), Clamp01(g, 0), Clamp01(b, 0), 1)
        end
    end
    A3._customDispelColorMap = map
    return A3._customDispelColorMap
end

function A3.ApplyHarmfulDispelColorOptions(options)
    if options then options.customDispelColorMap = A3.GetCustomDispelColorMap() end
    return options
end

--- Per-type CustomAsset map for one MSUF set, built once and memoized. Cold
--- path: reached from the sensor prepare and from the menu preview only.
function DS.AssetMap(style)
    local folder = DS.folders[style]
    if not folder then
        DS.assetCache[style] = false
        return nil
    end
    local signature = ""
    for i = 1, #DS.types do
        signature = signature .. (A3.HasDispelTypeColorOverride(DS.types[i]) and "1" or "0")
    end
    local cacheKey = style .. ":" .. signature
    local cached = DS.assetCache[cacheKey]
    if cached ~= nil then return cached or nil end
    local map = {}
    for i = 1, #DS.types do
        local dispelType = DS.types[i]
        local root = signature:sub(i, i) == "1" and (DS.mediaPath .. "Tintable\\") or DS.mediaPath
        map[dispelType] = {
            asset = root .. folder .. "\\" .. dispelType:lower() .. ".tga",
            useAtlasSize = false,
        }
    end
    DS.assetCache[cacheKey] = map
    return map
end

return {
    AURA_BORDER_OPTIONS = AURA_BORDER_OPTIONS,
    AURA_SENSOR_BORDER_OPTIONS = AURA_SENSOR_BORDER_OPTIONS,
    AURA_SENSOR_OVERLAY_OPTIONS = AURA_SENSOR_OVERLAY_OPTIONS,
    DS = DS,
    Shape = Shape,
}
end
