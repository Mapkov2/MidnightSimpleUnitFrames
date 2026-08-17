--- Auras3/MSUF_Auras3_UnitFrames.lua
--- WoW 12.1 native AuraContainer/AuraButton runtime.
---
--- MSUF 6.0 is 12.1-only for aura display work. This file intentionally does
--- not inspect or transform aura payload data itself. Blizzard's native
--- AuraContainer owns tracking, filtering, and assignment; MSUF only builds the
--- visual containers, initializeFrame customization, layout, and refresh surface.
local addonName, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}

local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end
ExportPublic("MSUF_Auras3", A3)
local SpellIndicatorsRuntime = A3.SpellIndicators or {}
A3.SpellIndicators = SpellIndicatorsRuntime

local UF = MSUF.UF
if not (UF and UF.RegisterElement) then return end
if A3.__unitFrameBackendLoaded then return end
A3.__unitFrameBackendLoaded = true

local type, tostring, tonumber, pairs, next = type, tostring, tonumber, pairs, next
local table_concat, table_sort = table.concat, table.sort
local math_floor, math_min, math_max = math.floor, math.min, math.max
local FrameLayers = UF.Layers or {}
local DISPEL_OVERLAY_EFFECT_OFFSET = tonumber(FrameLayers.DISPEL_OVERLAY_EFFECT_OFFSET) or 12
local AURA_ICON_BASE_OFFSET = tonumber(FrameLayers.AURA_ICON_BASE_OFFSET) or 64
local UNIT_AURA_BASE_OFFSET = tonumber(FrameLayers.UNIT_AURA_BASE_OFFSET) or 10
local CreateFrame = _G.CreateFrame
local C_AddOns = _G.C_AddOns
local C_Timer = _G.C_Timer
local issecretvalue = _G.issecretvalue or function(_) return false end
local STANDARD_TEXT_FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local ClampNumber, Clamp01

local EMPTY_EVENTS = {}
local AURA_CONTAINER_ADDON = "Blizzard_AuraContainer"
local MAX_CONFIGURABLE_DEBUFF_DURATION = 180
-- Blizzard's native maxDuration candidate filter also rejects duration == 0.
-- Use a practically unreachable finite ceiling so this behaves as an
-- "exclude permanent" rule without dropping normal long-duration auras.
local MAX_FINITE_AURA_DURATION = 2147483647
local MSUF_AURA_SENSOR_EDGE_TEXTURE = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\Masks\\msuf_frame_edge_thin_256x64.tga"
-- Aura icon shape module. The unit-frame chunk sits close to the Lua
-- 200-local ceiling, so every shape constant and helper lives on one
-- table instead of costing a main-chunk local each.
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
-- One namespace rather than a few dozen main-chunk locals: this file runs close
-- to the Lua 5.1 200-local ceiling (see the static-check budget).
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
local IDENTITY_AURA_REFRESH_REASONS = {
    MSUF_UNIT_IDENTITY_AURAS = true,
    MSUF_UNIT_IDENTITY_SOFT_AURAS = true,
    MSUF_GF_UNIT_IDENTITY = true,
}
local COLD_APPLY_REASONS = {
    MSUF_ELEMENT_REFRESH = true,
}

local NormalizeAuraSortMethod, AuraSortEnums, AuraSortSignature

local MANAGED_UNITS = {
    player = true, target = true, focus = true,
    boss1 = true, boss2 = true, boss3 = true, boss4 = true, boss5 = true,
}

-- The menu exposes one Boss filter scope, while layout remains frame-local for
-- boss1..boss5. Keep boss1 as the persisted token/blacklist rule owner so an
-- older profile with absent or stale siblings cannot compile different filters.
local BOSS_FILTER_SCOPE_OWNER = {
    boss1 = "boss1", boss2 = "boss1", boss3 = "boss1", boss4 = "boss1", boss5 = "boss1",
}

local UNIT_FLAG = {
    player = "showPlayer",
    target = "showTarget",
    focus = "showFocus",
    boss1 = "showBoss",
    boss2 = "showBoss",
    boss3 = "showBoss",
    boss4 = "showBoss",
    boss5 = "showBoss",
}

local DEFAULT_SHARED = {
    showBuffs = true,
    showDebuffs = true,
    showTooltip = true,
    buffShowTooltip = true,
    debuffShowTooltip = true,
    showCooldownSwipe = true,
    cooldownSwipeReverse = false,
    sortMethod = "DEFAULT",
    sortReverse = false,
    showDurationBar = false,
    durationBarHeight = 2,
    durationBarDisplay = "BAR_ONLY",
    durationBarPosition = "BOTTOM",
    durationBarDirection = "REMAINING",
    showCooldownText = true,
    showStackCount = true,
    debuffTypeBorderMode = "OFF",
    useDebuffTypeBorders = false,
    iconSize = 26,
    iconZoom = 100,
    spacing = 2,
    perRow = 12,
    maxBuffs = 12,
    maxDebuffs = 12,
    growth = "RIGHT",
    rowWrap = "DOWN",
    buffGroupOffsetX = 0,
    buffGroupOffsetY = 36,
    debuffGroupOffsetX = 0,
    debuffGroupOffsetY = 6,
    buffGroupIconSize = 26,
    debuffGroupIconSize = 26,
    buffAnchor = "BOTTOMRIGHT",
    debuffAnchor = "TOPLEFT",
    buffLayer = 5,
    debuffLayer = 6,
    stackCountAnchor = "TOPRIGHT",
    cooldownTextAnchor = "CENTER",
    stackTextSize = 14,
    stackTextOffsetX = -1,
    stackTextOffsetY = 1,
    cooldownTextSize = 14,
    cooldownTextOffsetX = 0,
    cooldownTextOffsetY = 0,
    cooldownDecimalSeconds = 3,
    showWeaponEnchants = false,
    stylePadding = 0,
    styleBorderEnabled = false,
    styleBorderStyle = "SOLID",
    styleBorderThickness = 1,
    styleBorderColor = { 0, 0, 0, 1 },
    styleShadowEnabled = false,
    styleShadowSize = 4,
    styleShadowColor = { 0, 0, 0, 0.8 },
    buffFrameEffectType = "none",
    buffFrameEffectColor = { 0.69, 0.50, 0.88, 0.80 },
    buffFrameEffectPriority = 5,
    buffFrameEffectThickness = 2,
    buffFrameEffectLayer = 0,
    buffFrameEffectStrata = "AUTO",
    debuffFrameEffectType = "none",
    debuffFrameEffectColor = { 0.69, 0.50, 0.88, 0.80 },
    debuffFrameEffectPriority = 5,
    debuffFrameEffectThickness = 2,
    debuffFrameEffectLayer = 0,
    debuffFrameEffectStrata = "AUTO",
}

local LANE_SPECS = {
    buff = {
        rootKey = "Buffs",
        filter = "HELPFUL",
        filterKey = "buffs",
        showKey = "showBuffs",
        maxKey = "maxBuffs",
        xKey = "buffGroupOffsetX",
        yKey = "buffGroupOffsetY",
        sizeKey = "buffGroupIconSize",
        paddingKey = "buffStylePadding",
        iconZoomKey = "buffIconZoom",
        iconShapeKey = "buffIconShape",
        anchorKey = "buffAnchor",
        layerKey = "buffLayer",
        strataKey = "buffStrata",
        perRowKey = "buffPerRow",
        spacingKey = "buffSpacing",
        growthKey = "buffGrowthX",
        wrapKey = "buffGrowthY",
        showTextKey = "buffShowCooldownText",
        swipeKey = "buffShowCooldownSwipe",
        swipeReverseKey = "buffCooldownSwipeReverse",
        sortMethodKey = "buffSortMethod",
        sortReverseKey = "buffSortReverse",
        showDurationBarKey = "buffShowDurationBar",
        durationBarHeightKey = "buffDurationBarHeight",
        durationBarDisplayKey = "buffDurationBarDisplay",
        durationBarPositionKey = "buffDurationBarPosition",
        durationBarDirectionKey = "buffDurationBarDirection",
        tooltipKey = "buffShowTooltip",
        showStackKey = "buffShowStackCount",
        stackAnchorKey = "buffStackCountAnchor",
        stackSizeKey = "buffStackTextSize",
        stackXKey = "buffStackTextOffsetX",
        stackYKey = "buffStackTextOffsetY",
        cooldownSizeKey = "buffCooldownTextSize",
        cooldownAnchorKey = "buffCooldownTextAnchor",
        cooldownXKey = "buffCooldownTextOffsetX",
        cooldownYKey = "buffCooldownTextOffsetY",
        cooldownDecimalKey = "buffCooldownDecimalSeconds",
        defaultAnchor = "BOTTOMRIGHT",
        defaultLayer = 5,
    },
    debuff = {
        rootKey = "Debuffs",
        filter = "HARMFUL",
        filterKey = "debuffs",
        showKey = "showDebuffs",
        maxKey = "maxDebuffs",
        xKey = "debuffGroupOffsetX",
        yKey = "debuffGroupOffsetY",
        sizeKey = "debuffGroupIconSize",
        paddingKey = "debuffStylePadding",
        iconZoomKey = "debuffIconZoom",
        iconShapeKey = "debuffIconShape",
        anchorKey = "debuffAnchor",
        layerKey = "debuffLayer",
        strataKey = "debuffStrata",
        perRowKey = "debuffPerRow",
        spacingKey = "debuffSpacing",
        growthKey = "debuffGrowthX",
        wrapKey = "debuffGrowthY",
        showTextKey = "debuffShowCooldownText",
        swipeKey = "debuffShowCooldownSwipe",
        swipeReverseKey = "debuffCooldownSwipeReverse",
        sortMethodKey = "debuffSortMethod",
        sortReverseKey = "debuffSortReverse",
        showDurationBarKey = "debuffShowDurationBar",
        durationBarHeightKey = "debuffDurationBarHeight",
        durationBarDisplayKey = "debuffDurationBarDisplay",
        durationBarPositionKey = "debuffDurationBarPosition",
        durationBarDirectionKey = "debuffDurationBarDirection",
        tooltipKey = "debuffShowTooltip",
        showStackKey = "debuffShowStackCount",
        stackAnchorKey = "debuffStackCountAnchor",
        stackSizeKey = "debuffStackTextSize",
        stackXKey = "debuffStackTextOffsetX",
        stackYKey = "debuffStackTextOffsetY",
        cooldownSizeKey = "debuffCooldownTextSize",
        cooldownAnchorKey = "debuffCooldownTextAnchor",
        cooldownXKey = "debuffCooldownTextOffsetX",
        cooldownYKey = "debuffCooldownTextOffsetY",
        cooldownDecimalKey = "debuffCooldownDecimalSeconds",
        defaultAnchor = "TOPLEFT",
        defaultLayer = 6,
    },
}

-- Cold-path consumers derive ownership/routing from the compiler schema.
-- Export the exact table so menu and runtime cannot drift on new lane keys.
A3.UnitLaneSpecs = LANE_SPECS

local STYLE_LAYOUT_KEYS = {
    iconZoom = true,
    buffIconZoom = true,
    debuffIconZoom = true,
    stylePadding = true,
    stackTextSize = true,
    stackTextOffsetX = true,
    stackTextOffsetY = true,
    cooldownTextSize = true,
    cooldownTextOffsetX = true,
    cooldownTextOffsetY = true,
    durationBarHeight = true,
    buffStackTextSize = true,
    buffStackTextOffsetX = true,
    buffStackTextOffsetY = true,
    buffCooldownTextSize = true,
    buffCooldownTextOffsetX = true,
    buffCooldownTextOffsetY = true,
    buffDurationBarHeight = true,
    debuffStackTextSize = true,
    debuffStackTextOffsetX = true,
    debuffStackTextOffsetY = true,
    debuffCooldownTextSize = true,
    debuffCooldownTextOffsetX = true,
    debuffCooldownTextOffsetY = true,
    debuffDurationBarHeight = true,
}

local STYLE_SHARED_LAYOUT_KEYS = {
    -- Keep this set identical to the Menu Model. Basic per-unit layout values
    -- (visibility, counts, wrapping, and growth) must remain active even while
    -- the unit inherits shared styling.
    showTooltip = true,
    showCooldownSwipe = true,
    cooldownSwipeReverse = true,
    sortMethod = true,
    sortReverse = true,
    showDurationBar = true,
    durationBarDisplay = true,
    durationBarPosition = true,
    durationBarDirection = true,
    showCooldownText = true,
    showStackCount = true,
    debuffTypeBorderMode = true,
    dispelBorderMode = true,
    useDebuffTypeBorders = true,
    buffShowCooldownSwipe = true,
    buffCooldownSwipeReverse = true,
    buffSortMethod = true,
    buffSortReverse = true,
    buffShowDurationBar = true,
    buffDurationBarDisplay = true,
    buffDurationBarPosition = true,
    buffDurationBarDirection = true,
    buffShowTooltip = true,
    buffShowCooldownText = true,
    buffShowStackCount = true,
    buffShowStealable = true,
    buffStealableStyle = true,
    buffStackCountAnchor = true,
    buffCooldownTextAnchor = true,
    debuffShowCooldownSwipe = true,
    debuffCooldownSwipeReverse = true,
    debuffSortMethod = true,
    debuffSortReverse = true,
    debuffShowDurationBar = true,
    debuffDurationBarDisplay = true,
    debuffDurationBarPosition = true,
    debuffDurationBarDirection = true,
    debuffShowTooltip = true,
    debuffShowCooldownText = true,
    debuffShowStackCount = true,
    debuffStackCountAnchor = true,
    debuffCooldownTextAnchor = true,
    stackCountAnchor = true,
    cooldownTextAnchor = true,
    cooldownDecimalSeconds = true,
    buffCooldownDecimalSeconds = true,
    debuffCooldownDecimalSeconds = true,
    buffFrameEffectType = true,
    buffFrameEffectColor = true,
    buffFrameEffectPriority = true,
    buffFrameEffectThickness = true,
    buffFrameEffectLayer = true,
    buffFrameEffectStrata = true,
    debuffFrameEffectType = true,
    debuffFrameEffectColor = true,
    debuffFrameEffectPriority = true,
    debuffFrameEffectThickness = true,
    debuffFrameEffectLayer = true,
    debuffFrameEffectStrata = true,
}

-- Derive every lane-prefixed Style key from the compiler schema. Keeping the
-- field ownership in one place prevents a newly split lane setting from being
-- read from layout while Menu2 writes it to layoutShared (or vice versa).
local LANE_LAYOUT_FIELDS = {
    "xKey", "yKey", "sizeKey", "anchorKey", "layerKey", "strataKey", "spacingKey",
}
local LANE_SHARED_LAYOUT_FIELDS = {
    "showKey", "maxKey", "perRowKey", "growthKey", "wrapKey",
}
local STYLE_LANE_LAYOUT_FIELDS = {
    "iconZoomKey", "paddingKey", "durationBarHeightKey",
    "stackSizeKey", "stackXKey", "stackYKey",
    "cooldownSizeKey", "cooldownXKey", "cooldownYKey",
}
local STYLE_LANE_SHARED_FIELDS = {
    "showTextKey", "swipeKey", "swipeReverseKey",
    "sortMethodKey", "sortReverseKey", "showDurationBarKey",
    "durationBarDisplayKey", "durationBarPositionKey", "durationBarDirectionKey",
    "tooltipKey", "showStackKey", "stackAnchorKey", "cooldownAnchorKey",
    "cooldownDecimalKey",
}
for _, spec in pairs(LANE_SPECS) do
    for _, field in ipairs(STYLE_LANE_LAYOUT_FIELDS) do
        local key = spec[field]
        if key then STYLE_LAYOUT_KEYS[key] = true end
    end
    for _, field in ipairs(STYLE_LANE_SHARED_FIELDS) do
        local key = spec[field]
        if key then STYLE_SHARED_LAYOUT_KEYS[key] = true end
    end
end
for key in pairs(STYLE_LAYOUT_KEYS) do
    assert(STYLE_SHARED_LAYOUT_KEYS[key] ~= true,
        "MSUF Auras3 style key has conflicting layout ownership: " .. tostring(key))
end

-- Every setting field in LANE_SPECS must declare exactly one persistence
-- owner. This is a cold load-time contract: a future field cannot silently be
-- compiled from one table while Menu2 routes writes to another.
local LANE_FIELD_OWNERS = {}
local function RegisterLaneFieldOwners(fields, owner)
    for _, field in ipairs(fields) do
        assert(LANE_FIELD_OWNERS[field] == nil,
            "MSUF Auras3 lane field has conflicting ownership: " .. tostring(field))
        LANE_FIELD_OWNERS[field] = owner
    end
end
RegisterLaneFieldOwners(LANE_LAYOUT_FIELDS, "layout")
RegisterLaneFieldOwners(LANE_SHARED_LAYOUT_FIELDS, "layoutShared")
RegisterLaneFieldOwners(STYLE_LANE_LAYOUT_FIELDS, "styleLayout")
RegisterLaneFieldOwners(STYLE_LANE_SHARED_FIELDS, "styleLayoutShared")
local LANE_NON_SCOPED_FIELDS = {
    rootKey = true,
    filterKey = true,
    iconShapeKey = true,
}
for kind, spec in pairs(LANE_SPECS) do
    for field in pairs(spec) do
        if tostring(field):match("Key$") then
            assert(LANE_FIELD_OWNERS[field] ~= nil or LANE_NON_SCOPED_FIELDS[field] == true,
                "MSUF Auras3 lane field has no declared owner: " .. tostring(kind) .. "." .. tostring(field))
        end
    end
end

-- Menu and runtime must classify style participation from the same tables.
-- The Menu Model loads after this compiler and reuses these exact references;
-- keeping a second production copy previously let ownership drift silently.
A3.UnitStyleLayoutKeys = STYLE_LAYOUT_KEYS
A3.UnitStyleSharedLayoutKeys = STYLE_SHARED_LAYOUT_KEYS
A3.UnitLaneLayoutFields = LANE_LAYOUT_FIELDS
A3.UnitLaneSharedLayoutFields = LANE_SHARED_LAYOUT_FIELDS

local GROUP_LANE_SPECS = {
    buff = {
        rootKey = "Buffs", filter = "HELPFUL",
        showKey = "showBuffs", maxKey = "maxBuffs", sizeKey = "buffIconSize",
        iconZoomKey = "buffIconZoom",
        iconShapeKey = "buffIconShape",
        spacingKey = "buffSpacing", perRowKey = "buffPerRow", growthXKey = "buffGrowthX",
        growthYKey = "buffGrowthY", anchorKey = "buffAnchor", xKey = "buffOffsetX",
        yKey = "buffOffsetY", layerKey = "buffLayer", filterKey = "buffFilter",
        strataKey = "buffStrata",
        alphaKey = "buffAlpha",
        blacklistHashKey = "buffBlacklistHash",
        hidePermanentKey = "buffHidePermanent",
        maxDurationKey = "buffMaxDuration",
        showTextKey = "buffShowCooldown", showStackKey = "buffShowStacks", swipeKey = "buffShowCooldownSwipe",
        swipeReverseKey = "buffCooldownSwipeReverse", tooltipKey = "buffShowTooltip",
        sortMethodKey = "buffSortMethod", sortReverseKey = "buffSortReverse",
        showDurationBarKey = "buffShowDurationBar", durationBarHeightKey = "buffDurationBarHeight",
        durationBarDisplayKey = "buffDurationBarDisplay",
        durationBarPositionKey = "buffDurationBarPosition", durationBarDirectionKey = "buffDurationBarDirection",
        cooldownSizeKey = "buffCooldownSize", stackSizeKey = "buffStackSize",
        cooldownAnchorKey = "buffCooldownAnchor", cooldownXKey = "buffCooldownX",
        cooldownYKey = "buffCooldownY", stackAnchorKey = "buffStackAnchor",
        cooldownDecimalKey = "buffCooldownDecimalSeconds",
        stackXKey = "buffStackX", stackYKey = "buffStackY",
        defaultSize = 22, defaultMax = 4, defaultPerRow = 4, defaultAnchor = "BOTTOMRIGHT",
        defaultLayer = 5,
    },
    trackedBuff = {
        rootKey = "TrackedBuffs", filter = "HELPFUL",
        showKey = "showTrackedBuffs", maxKey = "maxTrackedBuffs", sizeKey = "trackedBuffIconSize",
        iconZoomKey = "trackedBuffIconZoom",
        iconShapeKey = "trackedBuffIconShape",
        spacingKey = "trackedBuffSpacing", perRowKey = "trackedBuffPerRow", growthXKey = "trackedBuffGrowthX",
        growthYKey = "trackedBuffGrowthY", anchorKey = "trackedBuffAnchor", xKey = "trackedBuffOffsetX",
        yKey = "trackedBuffOffsetY", layerKey = "trackedBuffLayer", filterKey = "trackedBuffFilter",
        strataKey = "trackedBuffStrata",
        alphaKey = "trackedBuffAlpha",
        blacklistHashKey = "trackedBuffBlacklistHash", includeHashKey = "trackedBuffIncludeHash",
        hidePermanentKey = "trackedBuffHidePermanent",
        maxDurationKey = "trackedBuffMaxDuration",
        showTextKey = "trackedBuffShowCooldown", showStackKey = "trackedBuffShowStacks", swipeKey = "trackedBuffShowCooldownSwipe",
        swipeReverseKey = "trackedBuffCooldownSwipeReverse", tooltipKey = "trackedBuffShowTooltip",
        sortMethodKey = "trackedBuffSortMethod", sortReverseKey = "trackedBuffSortReverse",
        showDurationBarKey = "trackedBuffShowDurationBar", durationBarHeightKey = "trackedBuffDurationBarHeight",
        durationBarDisplayKey = "trackedBuffDurationBarDisplay",
        durationBarPositionKey = "trackedBuffDurationBarPosition", durationBarDirectionKey = "trackedBuffDurationBarDirection",
        cooldownSizeKey = "trackedBuffCooldownSize", stackSizeKey = "trackedBuffStackSize",
        cooldownAnchorKey = "trackedBuffCooldownAnchor", cooldownXKey = "trackedBuffCooldownX",
        cooldownYKey = "trackedBuffCooldownY", stackAnchorKey = "trackedBuffStackAnchor",
        cooldownDecimalKey = "trackedBuffCooldownDecimalSeconds",
        stackXKey = "trackedBuffStackX", stackYKey = "trackedBuffStackY",
        defaultSize = 22, defaultMax = 4, defaultPerRow = 4, defaultAnchor = "TOPLEFT",
        defaultLayer = 9,
    },
    debuff = {
        rootKey = "Debuffs", filter = "HARMFUL",
        showKey = "showDebuffs", maxKey = "maxDebuffs", sizeKey = "debuffIconSize",
        iconZoomKey = "debuffIconZoom",
        iconShapeKey = "debuffIconShape",
        spacingKey = "debuffSpacing", perRowKey = "debuffPerRow", growthXKey = "debuffGrowthX",
        growthYKey = "debuffGrowthY", anchorKey = "debuffAnchor", xKey = "debuffOffsetX",
        yKey = "debuffOffsetY", layerKey = "debuffLayer", filterKey = "debuffFilter",
        strataKey = "debuffStrata",
        alphaKey = "debuffAlpha",
        blacklistHashKey = "debuffBlacklistHash",
        hidePermanentKey = "debuffHidePermanent",
        maxDurationKey = "debuffMaxDuration",
        nonPlayerKey = "debuffNonPlayer",
        showTextKey = "debuffShowCooldown", showStackKey = "debuffShowStacks", swipeKey = "debuffShowCooldownSwipe",
        swipeReverseKey = "debuffCooldownSwipeReverse", tooltipKey = "debuffShowTooltip",
        sortMethodKey = "debuffSortMethod", sortReverseKey = "debuffSortReverse",
        showDurationBarKey = "debuffShowDurationBar", durationBarHeightKey = "debuffDurationBarHeight",
        durationBarDisplayKey = "debuffDurationBarDisplay",
        durationBarPositionKey = "debuffDurationBarPosition", durationBarDirectionKey = "debuffDurationBarDirection",
        cooldownSizeKey = "debuffCooldownSize", stackSizeKey = "debuffStackSize",
        cooldownAnchorKey = "debuffCooldownAnchor", cooldownXKey = "debuffCooldownX",
        cooldownYKey = "debuffCooldownY", stackAnchorKey = "debuffStackAnchor",
        cooldownDecimalKey = "debuffCooldownDecimalSeconds",
        stackXKey = "debuffStackX", stackYKey = "debuffStackY",
        defaultSize = 20, defaultMax = 3, defaultPerRow = 3, defaultAnchor = "TOPLEFT",
        defaultLayer = 6,
    },
    external = {
        -- EXTERNAL_DEFENSIVE already means a defensive received from another
        -- player. Match Blizzard's 12.1 ExternalDefensivesFrame exactly; adding
        -- !PLAYER needlessly makes the query depend on caster identity and can
        -- suppress valid externals such as Ironbark on restricted group units.
        rootKey = "Externals", filter = "HELPFUL|EXTERNAL_DEFENSIVE",
        showKey = "showExternals", maxKey = "maxExternals", sizeKey = "externalIconSize",
        iconZoomKey = "externalIconZoom",
        iconShapeKey = "externalIconShape",
        spacingKey = "externalSpacing", perRowKey = "externalPerRow", growthXKey = "externalGrowthX",
        growthYKey = "externalGrowthY", anchorKey = "externalAnchor", xKey = "externalOffsetX",
        yKey = "externalOffsetY", layerKey = "externalLayer", filterKey = "externalFilter",
        strataKey = "externalStrata",
        alphaKey = "externalAlpha",
        blacklistHashKey = "externalBlacklistHash",
        hidePermanentKey = "externalHidePermanent",
        maxDurationKey = "externalMaxDuration",
        showTextKey = "externalShowCooldown", showStackKey = "externalShowStacks", swipeKey = "externalShowCooldownSwipe",
        swipeReverseKey = "externalCooldownSwipeReverse", tooltipKey = "externalShowTooltip",
        sortMethodKey = "externalSortMethod", sortReverseKey = "externalSortReverse",
        showDurationBarKey = "externalShowDurationBar", durationBarHeightKey = "externalDurationBarHeight",
        durationBarDisplayKey = "externalDurationBarDisplay",
        durationBarPositionKey = "externalDurationBarPosition", durationBarDirectionKey = "externalDurationBarDirection",
        cooldownSizeKey = "externalCooldownSize", stackSizeKey = "externalStackSize",
        cooldownAnchorKey = "externalCooldownAnchor", cooldownXKey = "externalCooldownX",
        cooldownYKey = "externalCooldownY", stackAnchorKey = "externalStackAnchor",
        cooldownDecimalKey = "externalCooldownDecimalSeconds",
        stackXKey = "externalStackX", stackYKey = "externalStackY",
        defaultSize = 28, defaultMax = 2, defaultPerRow = 2, defaultAnchor = "CENTER",
        defaultLayer = 7,
    },
}

local function InCombat()
    return type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() == true
end

-- NOTE: Inbound AuraContainer/AuraButton methods (SetEnabled, SetUnit,
-- AddAuraGroup/AddAuraSlot, SetIcon, ...)
-- are secure delegates. Call them directly from our code. Wrapping them does
-- not fix forbidden table access and makes PTR stack traces harder to reason
-- about.
--
-- 12.1 native containers own AuraButton creation and anchoring. MSUF does not create
-- AuraButton objects directly; all lane/sensor buttons are created by
-- AddAuraGroup/AddAuraSlot and customized in initializeFrame.

local function IsAddOnLoaded(addonName)
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        return C_AddOns.IsAddOnLoaded(addonName) == true
    end
    if type(_G.IsAddOnLoaded) == "function" then
        return _G.IsAddOnLoaded(addonName) == true
    end
    return false
end

local function EnsureBlizzardAuraContainerLoaded()
    if IsAddOnLoaded(AURA_CONTAINER_ADDON) then
        A3.nativeAuraRuntimeLoadError = nil
        return true
    end

    local loadAddOn = C_AddOns and C_AddOns.LoadAddOn or _G.LoadAddOn
    if type(loadAddOn) ~= "function" then
        A3.nativeAuraRuntimeLoadError = "LoadAddOn API is unavailable"
        return false
    end

    local loaded, reason = loadAddOn(AURA_CONTAINER_ADDON)
    if loaded == true or IsAddOnLoaded(AURA_CONTAINER_ADDON) then
        A3.nativeAuraRuntimeLoadError = nil
        return true
    end

    A3.nativeAuraRuntimeLoadError = tostring(reason or loaded or "not loaded")
    return false
end

-- PTR 7 allows creating aura containers (and their batched AuraButtons)
-- during combat, so aura cold paths no longer wait for PLAYER_REGEN. The one
-- remaining hard blocker is demand-loading Blizzard_AuraContainer itself:
-- LoadAddOn is refused in combat. Addons never unload, so after the first
-- successful check this collapses to a single upvalue read -- combat identity
-- refreshes pay zero C calls here.
local _auraContainerLoadedOnce = false
local function AuraRuntimeCombatBlocked()
    if _auraContainerLoadedOnce then return false end
    if IsAddOnLoaded(AURA_CONTAINER_ADDON) then
        _auraContainerLoadedOnce = true
        return false
    end
    return InCombat()
end

-- PTR 7 global aura tooltip skinning: when the user runs MSUF's own unit-info
-- tooltips, restyle the shared AuraButtonTooltip to the same dark look so
-- aura hovers match; GAME-provider users keep Blizzard's default style.
-- SetTooltipBackdrop/ResetTooltipStyle are secure delegates: call directly.
local function ApplyAuraTooltipStyle()
    local inbound = _G.AuraContainerInbound
    if not (inbound and type(inbound.SetTooltipBackdrop) == "function") then return end
    local general = _G.MSUF_DB and _G.MSUF_DB.general
    local wantMSUF = (general and general.unitTooltipProvider) == "MSUF"
    local applied = A3._auraTooltipStyleApplied
    if wantMSUF then
        if applied == "MSUF" then return end
        local createColor = _G.CreateColor
        inbound.SetTooltipBackdrop({
            backdropInfo = {
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            },
            centerColor = createColor and createColor(0, 0, 0, 0.9) or nil,
        })
        A3._auraTooltipStyleApplied = "MSUF"
    elseif applied == "MSUF" and type(inbound.ResetTooltipStyle) == "function" then
        inbound.ResetTooltipStyle()
        A3._auraTooltipStyleApplied = "DEFAULT"
    end
end

local function Round(value)
    value = tonumber(value) or 0
    return math_floor(value + 0.5)
end

ClampNumber = function(value, fallback, minValue, maxValue)
    value = tonumber(value)
    if value == nil then value = tonumber(fallback) or 0 end
    if minValue and value < minValue then value = minValue end
    if maxValue and value > maxValue then value = maxValue end
    return value
end

Clamp01 = function(value, fallback)
    return ClampNumber(value, fallback or 1, 0, 1)
end

local function NormalizeFrameStrata(value, fallback)
    local normalize = _G.MSUF_NormalizeFrameStrata
    if type(normalize) == "function" then return normalize(value, fallback or "AUTO") end
    if issecretvalue(value) == true then return fallback or "AUTO" end
    if value == nil or value == "" then return fallback or "AUTO" end
    value = tostring(value):upper()
    if value == "AUTO" then return "AUTO" end
    local rank = _G.MSUF_FRAME_STRATA_RANK
    return rank and rank[value] and value or (fallback or "AUTO")
end

local function ReadParentFrameStrata(parentFrame)
    local strata
    if parentFrame and parentFrame.GetFrameStrata then strata = parentFrame:GetFrameStrata() end
    if issecretvalue(strata) == true then return nil end
    return strata
end

local function ResolveFrameStrata(parentFrame, value)
    -- Legacy per-element strata cannot bypass the universal 0..30 order.
    return ReadParentFrameStrata(parentFrame)
end

local function SyncFrameStrata(frame, strata)
    if not (frame and frame.SetFrameStrata) then return false end
    if issecretvalue(strata) == true then return false end
    if strata == nil or strata == "" then return false end
    local cachedStrata = frame._msufA3FrameStrata
    if issecretvalue(cachedStrata) ~= true and cachedStrata == strata then return false end
    frame._msufA3FrameStrata = strata
    local currentStrata
    if frame.GetFrameStrata then currentStrata = frame:GetFrameStrata() end
    if issecretvalue(currentStrata) == true or currentStrata ~= strata then
        frame:SetFrameStrata(strata)
        return true
    end
    return false
end

local function ReadRaw(primary, secondary, key)
    if type(primary) == "table" and primary[key] ~= nil then return primary[key] end
    if type(secondary) == "table" and secondary[key] ~= nil then return secondary[key] end
    return nil
end

local function ReadBool(primary, secondary, key, fallback)
    local value = ReadRaw(primary, secondary, key)
    if value == nil then return fallback == true end
    return value == true
end

local function NormalizeDebuffTypeBorderMode(value, fallback)
    if value == true then return "SYMBOL" end
    if value == false then return "OFF" end
    value = tostring(value or ""):upper()
    if value == "BORDER" or value == "COLOR" or value == "ON" then return "BORDER" end
    if value == "SYMBOL" or value == "BORDER_SYMBOL" or value == "BORDER_SYMBOLS"
        or value == "BORDER+SYMBOL" or value == "ICON" or value == "WITH_SYMBOL" then
        return "SYMBOL"
    end
    if value == "OFF" or value == "NONE" or value == "DISABLED" then return "OFF" end
    return fallback or "OFF"
end

local function ReadDebuffTypeBorderMode(primary, secondary)
    local mode
    if type(primary) == "table" then
        mode = primary.debuffTypeBorderMode
        if mode == nil then mode = primary.dispelBorderMode end
        if mode == nil and primary.useDebuffTypeBorders ~= nil then
            return primary.useDebuffTypeBorders == true and "SYMBOL" or "OFF"
        end
        if mode ~= nil and NormalizeDebuffTypeBorderMode(mode, "OFF") == "OFF" and primary.useDebuffTypeBorders == true then
            return "SYMBOL"
        end
    end
    if mode == nil and type(secondary) == "table" then
        mode = secondary.debuffTypeBorderMode
        if mode == nil then mode = secondary.dispelBorderMode end
        if mode == nil and secondary.useDebuffTypeBorders ~= nil then
            return secondary.useDebuffTypeBorders == true and "SYMBOL" or "OFF"
        end
        if mode ~= nil and NormalizeDebuffTypeBorderMode(mode, "OFF") == "OFF" and secondary.useDebuffTypeBorders == true then
            return "SYMBOL"
        end
    end
    return NormalizeDebuffTypeBorderMode(mode, "OFF")
end

local function ReadGroupDebuffTypeBorderMode(source)
    local mode = source and (source.debuffDispelBorderMode or source.debuffTypeBorderMode or source.dispelBorderMode)
    if mode == nil and source then
        if source.debuffShowDispelSymbol ~= nil then return source.debuffShowDispelSymbol == true and "SYMBOL" or "BORDER" end
        if source.debuffShowDispelBorder ~= nil then return source.debuffShowDispelBorder == true and "SYMBOL" or "OFF" end
        if type(source.blizzard) == "table" and source.blizzard.dispelBorder == true then return "SYMBOL" end
    end
    if source and NormalizeDebuffTypeBorderMode(mode, "OFF") == "OFF" and source.debuffShowDispelBorder == true then
        return "SYMBOL"
    end
    return NormalizeDebuffTypeBorderMode(mode, "OFF")
end

local function GetAuraBorderOptions(showIcon, preserveAsset)
    -- Border/BorderWithIcon let Blizzard supply its dispel border atlas, which
    -- is the intended art for the lane debuff-type border feature.
    local styles = _G.Enum and _G.Enum.CustomAuraButtonDispelTypeTextureStyle
    AURA_BORDER_OPTIONS.style = styles and (preserveAsset == true and styles.PreserveAsset
        or (showIcon == true and styles.BorderWithIcon or styles.Border)) or nil
    return A3.ApplyHarmfulDispelColorOptions(AURA_BORDER_OPTIONS)
end

local function ReadNumber(primary, secondary, key, fallback, minValue, maxValue)
    return ClampNumber(ReadRaw(primary, secondary, key), fallback, minValue, maxValue)
end

local function ReadAnchor(primary, secondary, key, fallback)
    local value = ReadRaw(primary, secondary, key)
    if value == "TOPLEFT" or value == "TOP" or value == "TOPRIGHT"
        or value == "LEFT" or value == "CENTER" or value == "RIGHT"
        or value == "BOTTOMLEFT" or value == "BOTTOM" or value == "BOTTOMRIGHT" then
        return value
    end
    return fallback or "CENTER"
end

-- Read Style values through the same ownership map exported to Menu_Model.
-- layout-owned values fall back only to the root Shared table; layoutShared-
-- owned values never consult layout. This makes stale/misplaced keys inert and
-- keeps a fresh runtime compile identical to the setting the menu displays.
local function ReadUnitStyleRaw(layout, laneLayout, rootShared, key)
    if STYLE_SHARED_LAYOUT_KEYS[key] then
        return ReadRaw(laneLayout, nil, key)
    end
    return ReadRaw(layout, nil, key)
end

local function ReadUnitStyleBool(layout, laneLayout, rootShared, key, fallback)
    local value = ReadUnitStyleRaw(layout, laneLayout, rootShared, key)
    if value == nil then return fallback == true end
    return value == true
end

local function ReadUnitStyleNumber(layout, laneLayout, rootShared, key, fallback, minValue, maxValue)
    return ClampNumber(ReadUnitStyleRaw(layout, laneLayout, rootShared, key), fallback, minValue, maxValue)
end

local function ReadUnitStyleAnchor(layout, laneLayout, rootShared, key, fallback)
    local value = ReadUnitStyleRaw(layout, laneLayout, rootShared, key)
    if value == "TOPLEFT" or value == "TOP" or value == "TOPRIGHT"
        or value == "LEFT" or value == "CENTER" or value == "RIGHT"
        or value == "BOTTOMLEFT" or value == "BOTTOM" or value == "BOTTOMRIGHT" then
        return value
    end
    return fallback or "CENTER"
end

-- Buff and Debuff Style values are strict lane owners. Generic and root
-- Shared keys are legacy migration inputs only and never participate here.
local function ReadUnitLaneStyleRaw(layout, laneLayout, rootShared, laneKey, genericKey)
    local laneLayoutOwned = STYLE_SHARED_LAYOUT_KEYS[laneKey] == true
    local localOwner = laneLayoutOwned and laneLayout or layout
    return ReadRaw(localOwner, nil, laneKey)
end

local function ReadUnitLaneStyleBool(layout, laneLayout, rootShared, laneKey, genericKey, fallback)
    local value = ReadUnitLaneStyleRaw(layout, laneLayout, rootShared, laneKey, genericKey)
    if value == nil then return fallback == true end
    return value == true
end

local function ReadUnitLaneStyleNumber(layout, laneLayout, rootShared, laneKey, genericKey, fallback, minValue, maxValue)
    return ClampNumber(ReadUnitLaneStyleRaw(layout, laneLayout, rootShared, laneKey, genericKey),
        fallback, minValue, maxValue)
end

local function ReadUnitLaneStyleAnchor(layout, laneLayout, rootShared, laneKey, genericKey, fallback)
    local value = ReadUnitLaneStyleRaw(layout, laneLayout, rootShared, laneKey, genericKey)
    if value == "TOPLEFT" or value == "TOP" or value == "TOPRIGHT"
        or value == "LEFT" or value == "CENTER" or value == "RIGHT"
        or value == "BOTTOMLEFT" or value == "BOTTOM" or value == "BOTTOMRIGHT" then
        return value
    end
    return fallback or "CENTER"
end

local function NormalizeDurationBarPosition(value, fallback)
    value = tostring(value or fallback or "BOTTOM"):upper()
    if value == "TOP" then return "TOP" end
    return "BOTTOM"
end

local function NormalizeDurationBarDirection(value, fallback)
    value = tostring(value or fallback or "REMAINING"):upper()
    if value == "ELAPSED" or value == "ELAPSED_TIME" then return "ELAPSED" end
    return "REMAINING"
end

local function NormalizeDurationBarDisplay(value, fallback)
    value = tostring(value or fallback or "BAR_ONLY"):upper()
    if value == "ICON" or value == "ICONS" or value == "ICON_BAR" or value == "ICON+BAR" or value == "OVERLAY" then return "OVERLAY" end
    return "BAR_ONLY"
end

local function ReadDurationBarPosition(primary, secondary, key, fallback)
    return NormalizeDurationBarPosition(ReadRaw(primary, secondary, key), fallback)
end

local function ReadDurationBarDirection(primary, secondary, key, fallback)
    return NormalizeDurationBarDirection(ReadRaw(primary, secondary, key), fallback)
end

local function ReadDurationBarDisplay(primary, secondary, key, fallback)
    return NormalizeDurationBarDisplay(ReadRaw(primary, secondary, key), fallback)
end

local function EnsureDB()
    if A3.EnsureDB then
        local auras, shared = A3.EnsureDB()
        if type(auras) == "table" then
            auras.shared = type(auras.shared) == "table" and auras.shared or {}
            return auras, auras.shared
        end
    end
    local db = _G.MSUF_DB
    if type(db) ~= "table" then return {}, {} end
    db.auras3 = type(db.auras3) == "table" and db.auras3 or {}
    db.auras3.shared = type(db.auras3.shared) == "table" and db.auras3.shared or {}
    return db.auras3, db.auras3.shared
end

function Shape.SharedValue(shared, kind)
    local appearanceShapes = type(shared) == "table" and shared.appearanceIconShapes or nil
    if type(appearanceShapes) == "table" and appearanceShapes[kind] ~= nil then
        return appearanceShapes[kind]
    end
    return kind == "playerDefensives" and "FOLLOW_PORTRAIT" or "RECTANGLE"
end

local function NormalizeRuntimeUnit(unit)
    unit = tostring(unit or "")
    if unit == "boss" then return "boss1" end
    if MANAGED_UNITS[unit] then return unit end
    return nil
end

local function IsGroupFrame(frame)
    if not frame then return false end
    if frame._msufIsGroupFrame or frame._msufGFKind then return true end
    local unit = frame.MSUFUnitKey
    return type(unit) == "string" and (unit:match("^party%d+$") or unit:match("^raid%d+$")) and true or false
end

local function UnitAuraIconsEnabled(auras, unit)
    if not (type(auras) == "table" and auras.enabled == true) then return false end
    local flag = UNIT_FLAG[NormalizeRuntimeUnit(unit)]
    return flag and auras[flag] == true or false
end

local function EffectiveUnitTables(auras, unit)
    local perUnit = type(auras.perUnit) == "table" and auras.perUnit or nil
    local unitCfg = perUnit and perUnit[unit] or nil
    local filterCfg = perUnit and perUnit[BOSS_FILTER_SCOPE_OWNER[unit] or unit] or nil
    local layout = unitCfg and type(unitCfg.layout) == "table" and unitCfg.layout or {}
    local layoutShared = unitCfg and type(unitCfg.layoutShared) == "table" and unitCfg.layoutShared or {}
    local filters = filterCfg and type(filterCfg.filters) == "table" and filterCfg.filters or {}
    return layout, layoutShared, filters
end

local function EffectiveUnitBlacklist(auras, unit)
    if type(auras) ~= "table" then return nil end
    local perUnit = type(auras.perUnit) == "table" and auras.perUnit or nil
    local unitCfg = perUnit and perUnit[BOSS_FILTER_SCOPE_OWNER[unit] or unit] or nil
    return unitCfg and type(unitCfg.blacklist) == "table" and unitCfg.blacklist or nil
end

local function AuraSpellIDFromKey(value)
    value = tostring(value or "")
    local id = tonumber(value:match("spell:(%d+)") or value:match("#(%d+)") or value:match("^(%d+)$"))
    return id and math_floor(id + 0.5) or nil
end

local function CandidateFiltersFromSpellIDs(spellIDs, fieldName)
    fieldName = fieldName or "excludeSpellIDs"
    if type(spellIDs) ~= "table" then return nil, nil end
    local out
    for key, enabled in pairs(spellIDs) do
        local spellID
        if enabled == true or enabled == nil then
            spellID = AuraSpellIDFromKey(key)
        elseif enabled ~= false then
            local valueType = type(enabled)
            if valueType == "number" or valueType == "string" then
                spellID = AuraSpellIDFromKey(enabled) or AuraSpellIDFromKey(key)
            elseif valueType == "table" and enabled.enabled ~= false then
                spellID = AuraSpellIDFromKey(enabled.spellID or enabled.spellId or enabled.id or enabled[1]) or AuraSpellIDFromKey(key)
            end
        end
        if spellID then
            if not out then out = {} end
            if type(A3.AddAuraSpellIDAndAliases) == "function" then
                A3.AddAuraSpellIDAndAliases(out, spellID)
            else
                out[spellID] = true
            end
        end
    end
    if not out then return nil, nil end
    local parts, count = {}, 0
    for spellID in pairs(out) do
        count = count + 1
        parts[count] = tostring(spellID)
    end
    if count == 0 then return nil, nil end
    table_sort(parts)
    return { [fieldName] = out }, fieldName .. ":" .. table_concat(parts, ",")
end

local function CandidateFiltersFromExcludeSpellIDs(spellIDs)
    return CandidateFiltersFromSpellIDs(spellIDs, "excludeSpellIDs")
end

local function CandidateFiltersFromIncludeAndExcludeSpellIDs(includeSpellIDs, excludeSpellIDs)
    local includeFilters, includeSignature = CandidateFiltersFromSpellIDs(includeSpellIDs, "includeSpellIDs")
    local excludeFilters, excludeSignature = CandidateFiltersFromSpellIDs(excludeSpellIDs, "excludeSpellIDs")
    if not includeFilters then return excludeFilters, excludeSignature end
    if excludeFilters then
        includeFilters.excludeSpellIDs = excludeFilters.excludeSpellIDs
        includeSignature = includeSignature .. ";" .. excludeSignature
    end
    return includeFilters, includeSignature
end

local function AddMaxDurationCandidateFilter(candidateFilters, candidateFilterSignature, maxDuration, hidePermanent)
    maxDuration = Round(ClampNumber(maxDuration, 0, 0, MAX_CONFIGURABLE_DEBUFF_DURATION))
    if maxDuration <= 0 then
        if hidePermanent ~= true then return candidateFilters, candidateFilterSignature end
        maxDuration = MAX_FINITE_AURA_DURATION
    end
    candidateFilters = candidateFilters or {}
    candidateFilters.maxDuration = maxDuration
    local part = "maxDuration:" .. tostring(maxDuration)
    candidateFilterSignature = candidateFilterSignature and (candidateFilterSignature .. ";" .. part) or part
    return candidateFilters, candidateFilterSignature
end

local function ApplyAuraIconZoom(texture, lane)
    if not (texture and texture.SetTexCoord) then return end
    local zoom = ClampNumber(lane and lane.iconZoom, 100, 100, 200)
    if texture._msufA3IconZoomKey == zoom then return end
    texture._msufA3IconZoomKey = zoom
    local visible = 100 / zoom
    local inset = (1 - visible) * 0.5
    texture:SetTexCoord(inset, 1 - inset, inset, 1 - inset)
end

local function AuraIconBaseOffset(parentFrame)
    -- Unit frames use the SAME element base as texts and status icons
    -- (frame + 10 + layer, see UF.Layers.UNIT_AURA_BASE_OFFSET), so the
    -- Layers popover's 0..30 values form one comparable scale: aura layer 7
    -- renders above a text at layer 5 and below one at layer 9. The old base
    -- of 0 shifted auras a full band below every text/status element, which
    -- made the aura layer slider look dead against them. Group frames keep
    -- the fixed foreground band (base 64) where icons never sink under
    -- effects.
    if parentFrame and parentFrame.MSUFSpec and parentFrame.MSUFSpec.scope == "group" then
        return AURA_ICON_BASE_OFFSET
    end
    return UNIT_AURA_BASE_OFFSET
end

local function AddHidePermanentCandidateFilter(candidateFilters, candidateFilterSignature, hidePermanent)
    return AddMaxDurationCandidateFilter(candidateFilters, candidateFilterSignature, nil, hidePermanent)
end

local function CandidateFiltersFromBlacklist(blacklist)
    local spells = type(blacklist) == "table" and blacklist.spells or nil
    local candidateFilters, candidateFilterSignature = CandidateFiltersFromExcludeSpellIDs(spells)
    return AddMaxDurationCandidateFilter(candidateFilters, candidateFilterSignature,
        type(blacklist) == "table" and blacklist.maxDuration,
        type(blacklist) == "table" and blacklist.hidePermanent == true)
end

local function CandidateFiltersFromBlacklistHash(hash)
    return CandidateFiltersFromExcludeSpellIDs(hash)
end

local function GrowthParts(growth, rowWrap)
    growth = tostring(growth or "RIGHT")
    rowWrap = tostring(rowWrap or "DOWN")
    if growth == "LEFTUP" then return "LEFT", "UP", -1, 1, false end
    if growth == "LEFTDOWN" then return "LEFT", "DOWN", -1, -1, false end
    if growth == "RIGHTUP" then return "RIGHT", "UP", 1, 1, false end
    if growth == "RIGHTDOWN" then return "RIGHT", "DOWN", 1, -1, false end
    if growth == "LEFT" then return "LEFT", rowWrap, -1, rowWrap == "UP" and 1 or -1, false end
    -- PTR 5-safe vertical growth: Blizzard's native flow remains row-major,
    -- but a one-icon row width makes every following aura start a new row.
    -- This preserves true single-column UP/DOWN without touching initialized
    -- AuraButtons. Multi-column column-major wrapping is intentionally absent.
    if growth == "UP" then return "RIGHT", "UP", 1, 1, true end
    if growth == "DOWN" then return "RIGHT", "DOWN", 1, -1, true end
    return "RIGHT", rowWrap, 1, rowWrap == "UP" and 1 or -1, false
end

local function GroupGrowthParts(growthX, growthY)
    growthX = tostring(growthX or "RIGHT")
    growthY = tostring(growthY or "DOWN")
    if growthX == "UP" or growthX == "DOWN" then
        return "RIGHT", growthX, 1, growthX == "UP" and 1 or -1, true
    end
    local xSign = growthX == "LEFT" and -1 or 1
    local ySign = growthY == "UP" and 1 or -1
    return growthX == "LEFT" and "LEFT" or "RIGHT", growthY == "UP" and "UP" or "DOWN", xSign, ySign, false
end

local function ButtonAnchor(xSign, ySign)
    if xSign < 0 then
        return ySign > 0 and "BOTTOMRIGHT" or "TOPRIGHT"
    end
    return ySign > 0 and "BOTTOMLEFT" or "TOPLEFT"
end

local VALID_NATIVE_FILTER_TOKENS = {
    HELPFUL = true,
    HARMFUL = true,
    PLAYER = true,
    RAID = true,
    CANCELABLE = true,
    MAW = true,
    INCLUDE_NAME_PLATE_ONLY = true,
    EXTERNAL_DEFENSIVE = true,
    CROWD_CONTROL = true,
    RAID_IN_COMBAT = true,
    RAID_PLAYER_DISPELLABLE = true,
    BIG_DEFENSIVE = true,
    IMPORTANT = true,
    DISPELLABLE = true,
}

local LEGACY_NATIVE_FILTER_TOKENS = {
    ALL = false,
    NOT_CANCELABLE = "!CANCELABLE",
}

local function AddNativeFilterToken(out, seen, token, baseToken)
    token = tostring(token or ""):upper():gsub("^%s+", ""):gsub("%s+$", "")
    local negated = token:sub(1, 1) == "!"
    if negated then
        token = token:sub(2):gsub("^%s+", ""):gsub("%s+$", "")
    end
    local legacy = LEGACY_NATIVE_FILTER_TOKENS[token]
    if legacy ~= nil then
        if legacy == false then return end
        token = legacy
        negated = token:sub(1, 1) == "!"
        if negated then
            token = token:sub(2):gsub("^%s+", ""):gsub("%s+$", "")
        end
    end
    if token == "" or not VALID_NATIVE_FILTER_TOKENS[token] then return end
    if negated and (token == "HELPFUL" or token == "HARMFUL") then return end
    if (token == "HELPFUL" or token == "HARMFUL") and token ~= baseToken then return end
    if negated then token = "!" .. token end
    if seen[token] then return end
    seen[token] = true
    out[#out + 1] = token
end

local function NormalizeNativeFilterString(filter, fallback)
    fallback = tostring(fallback or "")
    filter = tostring(filter or "")
    local baseToken = (fallback:find("HARMFUL", 1, true) or filter:find("HARMFUL", 1, true)) and "HARMFUL" or "HELPFUL"
    local out, seen = {}, {}
    AddNativeFilterToken(out, seen, baseToken, baseToken)
    for token in fallback:gmatch("[^|]+") do AddNativeFilterToken(out, seen, token, baseToken) end
    for token in filter:gmatch("[^|]+") do AddNativeFilterToken(out, seen, token, baseToken) end
    return table_concat(out, "|")
end

local function GridShape(maxCount, perRow, verticalGrowth)
    maxCount = Round(maxCount)
    perRow = math_max(Round(perRow), 1)
    if maxCount <= 0 then return 1, 1 end
    if verticalGrowth then return 1, maxCount end
    local major = math_min(perRow, maxCount)
    local minor = math_floor((maxCount + perRow - 1) / perRow)
    return major, minor
end

local LaneTrackingSignature, LaneStructuralSignature, LaneLayoutSignature
local SensorStructuralSignature, SensorLayoutSignature

-- Appearance icon style (static border + soft shadow) is global per Aura
-- product: Buff, Debuff, Player Defensives, or Dots on Target. Compiled once
-- per product/runtime generation and stamped by reference onto each lane.
local APPEARANCE_KIND = {
    buff = true, debuff = true, playerDefensives = true, targetDots = true,
}
local function NormalizeAppearanceKind(kind)
    return APPEARANCE_KIND[kind] and kind or "buff"
end

local _iconStyleCompiled, _iconStyleCompiledGen = {}, nil
local function SharedIconStyle(kind)
    kind = NormalizeAppearanceKind(kind)
    local gen = A3._runtimeConfigGen or 1
    if _iconStyleCompiledGen ~= gen then
        _iconStyleCompiled, _iconStyleCompiledGen = {}, gen
    elseif _iconStyleCompiled[kind] then
        return _iconStyleCompiled[kind]
    end
    local _, shared = EnsureDB()
    local styles = type(shared.appearanceIconStyles) == "table" and shared.appearanceIconStyles or nil
    local source = type(styles) == "table" and styles[kind] or nil
    source = type(source) == "table" and source or nil
    local function Read(key, fallback)
        if source and source[key] ~= nil then return source[key] end
        return fallback
    end
    local bc = Read("styleBorderColor", DEFAULT_SHARED.styleBorderColor)
    local sc = Read("styleShadowColor", DEFAULT_SHARED.styleShadowColor)
    bc = type(bc) == "table" and bc or DEFAULT_SHARED.styleBorderColor
    sc = type(sc) == "table" and sc or DEFAULT_SHARED.styleShadowColor
    local BorderStyles = MSUF.BorderStyles
    local borderStyle = BorderStyles and BorderStyles.Normalize(Read("styleBorderStyle", "SOLID")) or "SOLID"
    local style = {
        borderEnabled = Read("styleBorderEnabled", false) == true,
        borderStyle = borderStyle,
        -- nil for SOLID (and for a style whose media went missing), which keeps
        -- the flat single-quad ring as the fallback everywhere downstream.
        borderTexture = BorderStyles and BorderStyles.Resolve(borderStyle) or nil,
        borderThickness = Round(ClampNumber(Read("styleBorderThickness", DEFAULT_SHARED.styleBorderThickness), DEFAULT_SHARED.styleBorderThickness, 1, 8)),
        borderR = Clamp01(bc[1] or bc.r, 0),
        borderG = Clamp01(bc[2] or bc.g, 0),
        borderB = Clamp01(bc[3] or bc.b, 0),
        borderA = Clamp01(bc[4] or bc.a, 1),
        shadowEnabled = Read("styleShadowEnabled", false) == true,
        shadowSize = Round(ClampNumber(Read("styleShadowSize", DEFAULT_SHARED.styleShadowSize), DEFAULT_SHARED.styleShadowSize, 1, 16)),
        shadowR = Clamp01(sc[1] or sc.r, 0),
        shadowG = Clamp01(sc[2] or sc.g, 0),
        shadowB = Clamp01(sc[3] or sc.b, 0),
        shadowA = Clamp01(sc[4] or sc.a, 0.8),
    }
    style.borderEdge = style.borderTexture and BorderStyles.EdgeSize(borderStyle, style.borderThickness) or nil
    -- "inner" styles shade the icon from on top; "outer" ones frame it from
    -- behind. The renderer needs this before it creates the textures.
    style.borderPlacement = style.borderTexture and BorderStyles.Placement(borderStyle) or nil
    style.signature = table_concat({
        style.borderEnabled and "B" or "b", style.borderStyle, tostring(style.borderPlacement),
        tostring(style.borderTexture), style.borderThickness,
        style.borderR, style.borderG, style.borderB, style.borderA,
        style.shadowEnabled and "S" or "s", style.shadowSize,
        style.shadowR, style.shadowG, style.shadowB, style.shadowA,
    }, ":")
    _iconStyleCompiled[kind] = style
    return style
end

local function AddNonPlayerCandidateFilter(candidateFilters, candidateFilterSignature, enabled)
    if enabled ~= true then return candidateFilters, candidateFilterSignature end
    candidateFilters = candidateFilters or {}
    candidateFilters.isFromPlayerOrPlayerPet = false
    local part = "isFromPlayerOrPlayerPet:false"
    candidateFilterSignature = candidateFilterSignature and (candidateFilterSignature .. ";" .. part) or part
    return candidateFilters, candidateFilterSignature
end

local function RemoveNativeFilterToken(filter, removeToken, fallback)
    removeToken = tostring(removeToken or ""):upper()
    local kept = {}
    for token in tostring(filter or ""):gmatch("[^|]+") do
        local normalized = token:upper():gsub("^%s+", ""):gsub("%s+$", "")
        if normalized ~= removeToken then kept[#kept + 1] = token end
    end
    return NormalizeNativeFilterString(table_concat(kept, "|"), fallback)
end

local function ConfigureCuratedBigDefensiveLane(lane)
    if not (lane and tostring(lane.nativeFilter or ""):find("BIG_DEFENSIVE", 1, true)) then return lane end
    local getHash = A3.GetBigDefensiveSpellIDHash
    if type(getHash) ~= "function" then return lane end
    local spellIDs, spellIDSignature = getHash()
    if type(spellIDs) ~= "table" or not next(spellIDs) then return lane end

    local candidateFilters = {}
    for key, value in pairs(type(lane.candidateFilters) == "table" and lane.candidateFilters or {}) do
        candidateFilters[key] = value
    end
    candidateFilters.includeSpellIDs = spellIDs
    lane._msufA3BigDefensiveFilter = RemoveNativeFilterToken(lane.nativeFilter, "BIG_DEFENSIVE", "HELPFUL")
    lane._msufA3BigDefensiveCandidateFilters = candidateFilters
    lane._msufA3BigDefensiveCandidateSignature = lane.candidateFilterSignature
        and (lane.candidateFilterSignature .. ";" .. spellIDSignature) or spellIDSignature
    return lane
end

local function UnitSupportsCuratedBigDefensive(unit)
    unit = tostring(unit or "")
    if unit == "player" or unit:match("^party%d+$") or unit:match("^raid%d+$") then return true end
    if unit ~= "target" and unit ~= "focus" then return false end
    local unitCanAssist = _G.UnitCanAssist
    if type(unitCanAssist) ~= "function" then return false end
    local canAssist = unitCanAssist("player", unit)
    if issecretvalue(canAssist) == true then return false end
    return canAssist == true
end

local function EffectiveLaneFilters(lane)
    if lane and lane._msufA3BigDefensiveFilter and UnitSupportsCuratedBigDefensive(lane.unit) then
        return lane._msufA3BigDefensiveFilter,
            lane._msufA3BigDefensiveCandidateFilters,
            lane._msufA3BigDefensiveCandidateSignature
    end
    return lane and lane.nativeFilter,
        lane and lane.candidateFilters,
        lane and lane.candidateFilterSignature
end
A3._EffectiveBigDefensiveLaneFilters = EffectiveLaneFilters

local function FinalizeLane(lane, appearanceKind)
    if lane then
        ConfigureCuratedBigDefensiveLane(lane)
        lane.appearanceKind = NormalizeAppearanceKind(appearanceKind or lane.appearanceKind or lane.kind)
        lane.iconStyle = SharedIconStyle(lane.appearanceKind)
        -- Aura visibility is lane-local. The global Unitframe tooltip mode
        -- (Always/OOC/Modifier/Never) owns unit/group-frame mouseover only;
        -- native AuraButtons reuse just the compatible cursor placement and
        -- the shared Blizzard/MSUF look applied by ApplyAuraTooltipStyle().
        local general = _G.MSUF_DB and _G.MSUF_DB.general
        lane.auraTooltipAnchor = (general and general.unitTooltipAnchor == "CURSOR")
            and "ANCHOR_CURSOR" or "ANCHOR_BOTTOMRIGHT"
        lane._msufA3TrackingSignature = LaneTrackingSignature(lane)
        lane._msufA3StructuralSignature = LaneStructuralSignature(lane)
        lane._msufA3LayoutSignature = LaneLayoutSignature(lane)
    end
    return lane
end

local function NativeFilter(baseFilter, filters)
    filters = type(filters) == "table" and filters or nil
    local filter = tostring(baseFilter or "")
    local helpful = filter:find("HELPFUL", 1, true) ~= nil
    local harmful = filter:find("HARMFUL", 1, true) ~= nil
    if filters and filters.enabled ~= false then
        local playerScoped = filters.onlyMine == true
        if filters.exclusive == "raid" then filter = filter .. "|RAID" end
        if filters.raid == true then filter = filter .. "|RAID" end
        if filters.includeNameplateOnly == true then filter = filter .. "|INCLUDE_NAME_PLATE_ONLY" end
        if filters.cancelable == true and helpful then filter = filter .. "|CANCELABLE" end
        if filters.notCancelable == true and helpful then filter = filter .. "|!CANCELABLE" end
        if filters.raidInCombat == true then filter = filter .. "|RAID_IN_COMBAT" end
        if filters.includeDispellable == true then filter = filter .. "|RAID_PLAYER_DISPELLABLE" end
        if filters.dispellable == true then filter = filter .. "|RAID_PLAYER_DISPELLABLE" end
        if filters.dispellableAny == true then filter = filter .. "|DISPELLABLE" end
        if filters.onlyImportant == true then filter = filter .. "|IMPORTANT" end
        if filters.crowdControl == true and harmful then filter = filter .. "|CROWD_CONTROL" end
        if filters.externalDefensive == true and helpful then filter = filter .. "|EXTERNAL_DEFENSIVE" end
        if filters.bigDefensive == true and helpful then filter = filter .. "|BIG_DEFENSIVE" end
        if playerScoped then filter = filter .. "|PLAYER" end
    end
    local normalized = NormalizeNativeFilterString(filter, baseFilter)
    -- Cold-path safety net: MSUF's token whitelist normalizes user input, but
    -- Blizzard's validator is the final authority. A token Blizzard rejects
    -- would hard-assert inside AddAuraGroup and kill the lane, so fall back to
    -- the plain base filter instead and surface the reason.
    local auraUtil = _G.AuraUtil
    if auraUtil and type(auraUtil.IsValidFilterString) == "function"
        and auraUtil.IsValidFilterString(normalized) ~= true then
        A3.nativeAuraRuntimeError = "invalid native filter: " .. tostring(normalized)
        return NormalizeNativeFilterString(baseFilter, baseFilter)
    end
    return normalized
end

local function NormalizeDispelSensorTrigger(value, fallback)
    value = tostring(value or fallback or "BY_ME"):upper()
    if value == "BORDER" or value == "INHERIT" or value == "SAME" then return "BORDER" end
    if value == "BY_RAID" or value == "RAID" or value == "GROUP" or value == "BY_GROUP" then return "BY_RAID" end
    if value == "DISPEL_TYPE" or value == "TYPE" or value == "ANY_DISPEL_TYPE" then return "DISPEL_TYPE" end
    -- True any-debuff highlighting is not representable without reading aura
    -- payloads. Migrate the old UI value to PTR 5's exact type-only filter.
    if value == "ANY_DEBUFF" or value == "DEBUFF" or value == "ANY" or value == "ALL_DEBUFFS" then return "DISPEL_TYPE" end
    if value == "PLAYER_CAST" or value == "CAST_BY_ME" or value == "MY_DEBUFF" then return "PLAYER_CAST" end
    return "BY_ME"
end

local function DispelSensorNativeFilter(trigger)
    trigger = NormalizeDispelSensorTrigger(trigger, "BY_ME")
    if trigger == "DISPEL_TYPE" then
        return "HARMFUL|DISPELLABLE", 3
    end
    if trigger == "BY_RAID" then
        return "HARMFUL|RAID_PLAYER_DISPELLABLE", 1
    end
    if trigger == "PLAYER_CAST" then
        return "HARMFUL|PLAYER", 3
    end
    return "HARMFUL|RAID", 1
end

local function NormalizeDispelOverlayStyle(value)
    value = tostring(value or "FULL"):upper()
    if value == "TOP" or value == "BOTTOM" or value == "LEFT" or value == "RIGHT" then return value end
    return "FULL"
end

function DS.Style(value)
    value = tostring(value or "BLIZZARD"):upper()
    if DS.folders[value] then return value end
    -- Pre-multi-set profiles stored a single "MSUF" set; that art is now Letters.
    if value == "MSUF" or value == "CUSTOM" then return "MSUF_LETTERS" end
    if value == "BLIZZARD_RING" or value == "RING" then return "BLIZZARD_RING" end
    if value == "BLIZZARD_BORDER" or value == "BORDER" then return "BLIZZARD_BORDER" end
    return "BLIZZARD"
end

--- ALL (the default) shows one symbol per dispel type that is actually present,
--- so two debuffs of different types read as two symbols. It costs one aura slot
--- per type -- see DS.Slots -- but only once the symbol itself is switched on,
--- which is off by default. TOP is the one-slot fallback that shows only the
--- highest-priority matching debuff.
function DS.Mode(value)
    value = tostring(value or "ALL"):upper()
    if value == "TOP" or value == "HIGHEST" or value == "PRIORITY" then return "TOP" end
    return "ALL"
end

function DS.Growth(value)
    value = tostring(value or "RIGHT"):upper()
    if value == "LEFT" or value == "UP" or value == "DOWN" then return value end
    return "RIGHT"
end

--- Resolve the row direction against its anchor.
---
--- A right-edge anchor growing RIGHT (or a left anchor growing LEFT, a top
--- anchor growing UP, a bottom anchor growing DOWN) marches the row straight off
--- the frame: symbol 1 lands on the corner and the rest sit outside, over the
--- world or -- in a raid -- on top of the neighbouring frame. That reads as "only
--- one symbol shows". Outward choices are mirrored so the row always runs ALONG
--- the frame from its anchored corner. Perpendicular choices and CENTER anchors
--- pass through untouched, so "TOPRIGHT + Down" still stacks downwards.
function DS.ResolveGrowth(growth, anchor)
    growth = DS.Growth(growth)
    anchor = tostring(anchor or "TOPRIGHT"):upper()
    if growth == "RIGHT" and anchor:find("RIGHT", 1, true) then return "LEFT" end
    if growth == "LEFT" and anchor:find("LEFT", 1, true) then return "RIGHT" end
    if growth == "UP" and anchor:find("TOP", 1, true) then return "DOWN" end
    if growth == "DOWN" and anchor:find("BOTTOM", 1, true) then return "UP" end
    return growth
end

--- ALL mode: one slot per dispel type, each narrowed by an includeDispelTypes
--- candidate filter. Blizzard evaluates those against the secret dispelName
--- inside its own partition (Blizzard_AuraContainerUtil.lua), and unlike
--- spellID filters they are not gated by CanApplyIdentityCandidateFilters, so
--- this works on friendly units too. Slot i sits at step i-1 along `growth`,
--- which means a missing type leaves a hole rather than reshuffling the row --
--- deliberate: a symbol that keeps its place is readable at a glance.
function DS.Slots(symbol, size, spacing)
    local growth = DS.ResolveGrowth(symbol and symbol.growth, symbol and symbol.anchor)
    local slots, parts = {}, {}
    local step = size + spacing
    for i = 1, #DS.types do
        local dispelType = DS.types[i]
        local offset = (i - 1) * step
        local x, y = 0, 0
        -- Guard the first slot explicitly: negating zero yields "-0", which would
        -- put a pointless variant into the layout signature.
        if offset ~= 0 then
            if growth == "LEFT" then x = -offset
            elseif growth == "UP" then y = offset
            elseif growth == "DOWN" then y = -offset
            else x = offset end
        end
        slots[i] = {
            key = dispelType,
            dispelType = dispelType,
            x = x,
            y = y,
            -- Shared immutable filter table; see DS.filters.
            candidateFilters = DS.filters[dispelType],
            candidateFilterSignature = dispelType,
        }
        parts[i] = dispelType .. ":" .. tostring(x) .. ":" .. tostring(y)
    end
    return slots, table_concat(parts, "|"), growth
end

local function CompileCornerDispelSlots(corner)
    if not (type(corner) == "table" and corner.enabled == true and corner.needsDispel == true and type(corner.dispelSlots) == "table") then
        return nil, nil
    end
    local source = corner.dispelSlots
    local slots, parts = {}, {}
    for i = 1, #source do
        local slot = source[i]
        if type(slot) == "table" then
            local key = tostring(slot.key or i)
            local anchor = ReadAnchor(slot, nil, "anchor", "TOPLEFT")
            local x = Round(ClampNumber(slot.x, 0, -128, 128))
            local y = Round(ClampNumber(slot.y, 0, -128, 128))
            local out = { key = key, anchor = anchor, x = x, y = y }
            slots[#slots + 1] = out
            parts[#parts + 1] = key .. ":" .. anchor .. ":" .. tostring(x) .. ":" .. tostring(y)
        end
    end
    if #slots == 0 then return nil, nil end
    return slots, table_concat(parts, "|")
end

local function CompileDispelSensor(unit, frameSpec, groupMode, visual)
    if not (type(unit) == "string" and unit ~= "" and type(frameSpec) == "table") then return nil end
    local border = frameSpec.border
    local group = frameSpec.group
    local overlay = groupMode and group or frameSpec.dispelOverlay
    local corner = groupMode and frameSpec.cornerIndicators or nil
    -- The symbol sensor is the one dispel visual that is NOT group-only: both
    -- unit frames and group frames compile it from a dispelSymbol table.
    local symbol = frameSpec.dispelSymbol
    local cornerSlots, cornerSignature = nil, nil
    if visual == "corner" then
        cornerSlots, cornerSignature = CompileCornerDispelSlots(corner)
    end
    local borderOn = border and border.dispel == true
    local purgeOn = not groupMode and border and border.purge == true
        and (unit == "target" or unit == "focus")
    local overlayOn = overlay and ((groupMode and overlay.dispelOverlayEnabled == true) or (not groupMode and overlay.enabled == true))
    local symbolOn = type(symbol) == "table" and symbol.enabled == true
    if visual == "border" and not borderOn then return nil end
    if visual == "purge" and not purgeOn then return nil end
    if visual == "overlay" and not overlayOn then return nil end
    if visual == "corner" and not cornerSlots then return nil end
    if visual == "symbol" and not symbolOn then return nil end

    local borderTrigger = NormalizeDispelSensorTrigger(border and border.dispelTrigger, "BY_ME")
    local trigger = borderTrigger
    if visual == "overlay" then
        trigger = NormalizeDispelSensorTrigger(groupMode and overlay.dispelOverlayTrigger or overlay.trigger, "BORDER")
        if trigger == "BORDER" then trigger = borderTrigger end
    elseif visual == "corner" then
        trigger = "BY_ME"
    elseif visual == "symbol" then
        trigger = NormalizeDispelSensorTrigger(symbol.trigger, "BORDER")
        if trigger == "BORDER" then trigger = borderTrigger end
    end

    local symbolMode, symbolStyle, symbolSlots, symbolSignature, symbolGrowth
    local symbolSize, symbolSpacing, symbolAnchor, symbolX, symbolY
    if visual == "symbol" then
        symbolMode = DS.Mode(symbol.mode)
        symbolStyle = DS.Style(symbol.style)
        symbolSize = Round(ClampNumber(symbol.size, 14, 4, 64))
        symbolSpacing = Round(ClampNumber(symbol.spacing, 2, 0, 32))
        symbolAnchor = ReadAnchor(symbol, nil, "anchor", "TOPRIGHT")
        symbolX = Round(ClampNumber(symbol.x, 0, -256, 256))
        symbolY = Round(ClampNumber(symbol.y, 0, -256, 256))
        if symbolMode == "ALL" then
            symbolSlots, symbolSignature, symbolGrowth = DS.Slots(symbol, symbolSize, symbolSpacing)
        else
            symbolGrowth = DS.ResolveGrowth(symbol.growth, symbol.anchor)
        end
    end

    local nativeFilter, maxCount = DispelSensorNativeFilter(trigger)
    if visual == "purge" then nativeFilter, maxCount = "HELPFUL", 1 end
    if visual == "symbol" then
        -- TOP mode is one slot showing the top-priority matching debuff. ALL
        -- mode is one slot PER dispel type, each carrying its own
        -- includeDispelTypes candidate filter -- the only way to have several
        -- types visible at once, because a single slot always resolves to a
        -- single aura.
        maxCount = symbolSlots and #symbolSlots or 1
    elseif visual ~= "corner" and maxCount > 1 then
        -- AuraSlots do not de-duplicate across identical filters: every copy
        -- selects the same top aura. One slot therefore drives the same fixed
        -- border/overlay without duplicate native slot-manager work.
        maxCount = 1
    end
    local overlayOnHealth = visual == "overlay" and ((groupMode and overlay.dispelOverlayOnHealth ~= false) or (not groupMode and overlay.onHealth ~= false))
    local target = visual == "overlay" and (overlayOnHealth and "healthFill" or "healthBar") or "frame"
    local cornerCount = cornerSlots and #cornerSlots or nil
    local strata
    if visual == "overlay" then
        strata = groupMode and overlay.dispelOverlayStrata or overlay.strata
    elseif visual == "corner" then
        strata = corner and corner.strata
    elseif visual == "symbol" then
        strata = symbol.strata
    else
        strata = border and border.strata
    end
    local kind = "dispelBorder"
    local rootKey = "DispelBorderSensor"
    if visual == "purge" then
        kind, rootKey = "purgeBorder", "PurgeBorderSensor"
    elseif visual == "corner" then
        kind, rootKey = "dispelCorner", "DispelCornerSensor"
    elseif visual == "overlay" then
        kind, rootKey = "dispelOverlay", "DispelOverlaySensor"
    elseif visual == "symbol" then
        kind, rootKey = "dispelSymbol", "DispelSymbolSensor"
    end
    local priorityDetail = 14
    local priorityOrder = border and border.prioEnabled == true and border.prioOrder
        or A3.DEFAULT_NATIVE_HIGHLIGHT_PRIORITY
    local priorityKey = visual == "purge" and "purge" or (visual == "border" and "dispel" or nil)
    if priorityKey and type(priorityOrder) == "table" then
        for index = 1, #priorityOrder do
            if priorityOrder[index] == priorityKey then priorityDetail = 17 - index; break end
        end
    end
    return {
        sensor = true,
        kind = kind,
        rootKey = rootKey,
        unit = unit,
        enabled = true,
        nativeFilter = nativeFilter,
        candidateFilters = visual == "purge" and { isStealable = true } or nil,
        candidateFilterSignature = visual == "purge" and "isStealable:true" or nil,
        -- Corner sensors consolidate onto ONE AuraSlot whose button carries a
        -- texture per corner (PTR 7 multiple dispel textures). Identical
        -- filters always select the same top aura, so N corner slots were N
        -- copies of the same native slot manager doing identical work.
        -- filterCount still records the region count for signatures.
        max = cornerSlots and 1 or maxCount,
        filterCount = cornerCount or (symbolSlots and #symbolSlots) or nil,
        filterMax = cornerCount and 1 or maxCount,
        visual = visual,
        target = target,
        style = visual == "overlay" and NormalizeDispelOverlayStyle(groupMode and overlay.dispelOverlayStyle or overlay.style)
            or (visual == "symbol" and symbolStyle)
            or "FULL",
        alpha = visual == "corner" and Clamp01(corner and corner.alpha, 1)
            or (visual == "overlay" and Clamp01(groupMode and overlay.dispelOverlayAlpha or overlay.alpha, 0.35))
            or (visual == "symbol" and Clamp01(symbol.alpha, 1))
            or 1,
        thickness = ClampNumber(border and border.highlightThickness, 3, 1, 32),
        r = visual == "purge" and Clamp01(border and border.purgeR, 1) or nil,
        g = visual == "purge" and Clamp01(border and border.purgeG, 0.85) or nil,
        b = visual == "purge" and Clamp01(border and border.purgeB, 0) or nil,
        size = cornerSlots and ClampNumber(corner and corner.size, 8, 1, 64) or symbolSize or nil,
        slots = cornerSlots or symbolSlots,
        slotSignature = cornerSignature or symbolSignature,
        mode = symbolMode,
        growth = symbolGrowth,
        spacing = symbolSpacing,
        anchor = symbolAnchor,
        x = symbolX,
        y = symbolY,
        layer = visual == "corner" and (30 + ClampNumber(corner and corner.layer, 7, 0, 30))
            or (visual == "symbol" and (30 + ClampNumber(symbol.layer, 8, 0, 30)))
            or (visual == "overlay" and ClampNumber(groupMode and overlay.dispelOverlayLayer or overlay.layer, 0, 0, 30) or 45),
        detail = priorityDetail,
        strata = NormalizeFrameStrata(strata, "AUTO"),
        trigger = trigger,
    }
end

local function CompileUnitLane(unit, laneLayout, layout, filtersRoot, kind, candidateFilters, candidateFilterSignature, portraitShape, rootShared)
    local spec = LANE_SPECS[kind]
    local filters = type(filtersRoot) == "table" and type(filtersRoot[spec.filterKey]) == "table" and filtersRoot[spec.filterKey] or nil
    local filtersEnabled = type(filters) ~= "table" or filters.enabled ~= false
    candidateFilters, candidateFilterSignature = AddHidePermanentCandidateFilter(
        candidateFilters, candidateFilterSignature,
        kind == "buff" and type(filtersRoot) == "table"
            and (filtersRoot.hidePermanent == true or (filters and filters.hidePermanent == true)))
    candidateFilters, candidateFilterSignature = AddNonPlayerCandidateFilter(
        candidateFilters, candidateFilterSignature,
        kind == "debuff" and filtersEnabled and filters and filters.nonPlayer == true)
    local sizeDefault = ReadRaw(layout, nil, spec.sizeKey) or DEFAULT_SHARED.iconSize
    local size = ClampNumber(sizeDefault, DEFAULT_SHARED.iconSize, 1, 128)
    local zoomDefault = ReadUnitLaneStyleRaw(layout, laneLayout, rootShared,
        spec.iconZoomKey, "iconZoom") or DEFAULT_SHARED.iconZoom
    local iconShapeSource = Shape.SharedValue(rootShared, kind)
    local iconShape, requestedIconShape = Shape.Resolve(iconShapeSource, portraitShape)
    local spacing = ReadNumber(layout, nil, spec.spacingKey, DEFAULT_SHARED.spacing, 0, 64)
    local perRow = ReadNumber(laneLayout, nil, spec.perRowKey, DEFAULT_SHARED.perRow, 1, 40)
    local maxCount = ReadNumber(laneLayout, nil, spec.maxKey, DEFAULT_SHARED[spec.maxKey] or 12, 0, 80)
    local enabled = ReadBool(laneLayout, nil, spec.showKey, true) and maxCount > 0
    local growth = ReadRaw(laneLayout, nil, spec.growthKey) or DEFAULT_SHARED.growth
    local rowWrap = ReadRaw(laneLayout, nil, spec.wrapKey) or DEFAULT_SHARED.rowWrap
    local growthX, growthY, xSign, ySign, verticalGrowth = GrowthParts(growth, rowWrap)
    local cols, rows = GridShape(maxCount, perRow, verticalGrowth)
    local lanePadding = Round(ClampNumber(ReadUnitLaneStyleRaw(layout, laneLayout, rootShared,
        spec.paddingKey, nil), 0, 0, 16))
    local debuffTypeBorderMode = kind == "debuff" and ReadDebuffTypeBorderMode(laneLayout, nil) or "OFF"
    local cooldownAnchor = ReadUnitStyleAnchor(layout, laneLayout, rootShared,
        "cooldownTextAnchor", DEFAULT_SHARED.cooldownTextAnchor)
    local rawStrata = ReadRaw(layout, nil, spec.strataKey)
    if issecretvalue(rawStrata) == true then rawStrata = nil end
    return FinalizeLane({
        kind = kind,
        appearanceKind = kind,
        rootKey = spec.rootKey,
        unit = unit,
        enabled = enabled == true,
        -- Each lane owns its own filter gate. Hide Permanent remains an
        -- independent candidate filter, matching the Menu2 contract.
        nativeFilter = NativeFilter(spec.filter, filtersEnabled and filters or nil),
        candidateFilters = candidateFilters,
        candidateFilterSignature = candidateFilterSignature,
        max = Round(maxCount),
        size = size,
        iconZoom = ClampNumber(zoomDefault, DEFAULT_SHARED.iconZoom, 100, 200),
        iconShape = iconShape,
        requestedIconShape = requestedIconShape,
        spacing = spacing,
        step = size + spacing,
        perRow = Round(perRow),
        cols = cols,
        rows = rows,
        padding = lanePadding,
        weaponEnchants = kind == "buff" and unit == "player"
            and ReadBool(rootShared, nil, "showWeaponEnchants", false),
        width = math_max(1, cols * size + math_max(cols - 1, 0) * spacing + 2 * lanePadding),
        height = math_max(1, rows * size + math_max(rows - 1, 0) * spacing + 2 * lanePadding),
        x = Round(ReadNumber(layout, nil, spec.xKey, DEFAULT_SHARED[spec.xKey] or 0, -4096, 4096)),
        y = Round(ReadNumber(layout, nil, spec.yKey, DEFAULT_SHARED[spec.yKey] or 0, -4096, 4096)),
        anchor = ReadAnchor(layout, nil, spec.anchorKey, spec.defaultAnchor),
        layer = Round(ReadNumber(layout, nil, spec.layerKey, spec.defaultLayer, 0, 30)),
        strata = NormalizeFrameStrata(rawStrata, "AUTO"),
        alpha = 1,
        growthX = growthX,
        growthY = growthY,
        xSign = xSign,
        ySign = ySign,
        verticalGrowth = verticalGrowth == true,
        initialAnchor = ButtonAnchor(xSign, ySign),
        showCooldownText = ReadUnitLaneStyleBool(layout, laneLayout, rootShared,
            spec.showTextKey, "showCooldownText", true),
        showCooldownSwipe = ReadUnitLaneStyleBool(layout, laneLayout, rootShared,
            spec.swipeKey, "showCooldownSwipe", true),
        cooldownSwipeReverse = ReadUnitLaneStyleBool(layout, laneLayout, rootShared,
            spec.swipeReverseKey, "cooldownSwipeReverse", false),
        -- Native sorting belongs to this exact Aura container. Unlike the
        -- other Style fields, it must not fall back to a generic unit-wide key.
        sortMethod = NormalizeAuraSortMethod(ReadUnitLaneStyleRaw(layout, laneLayout, rootShared,
            spec.sortMethodKey, nil)),
        sortReverse = ReadUnitLaneStyleBool(layout, laneLayout, rootShared,
            spec.sortReverseKey, nil, false),
        -- Duration-bar visibility belongs to the local lane-layout owner.
        showDurationBar = ReadUnitLaneStyleBool(layout, laneLayout, rootShared,
            spec.showDurationBarKey, "showDurationBar", false),
        durationBarHeight = ReadUnitLaneStyleNumber(layout, laneLayout, rootShared,
            spec.durationBarHeightKey, "durationBarHeight", DEFAULT_SHARED.durationBarHeight, 1, 16),
        durationBarDisplay = NormalizeDurationBarDisplay(
            ReadUnitLaneStyleRaw(layout, laneLayout, rootShared, spec.durationBarDisplayKey, "durationBarDisplay"),
            DEFAULT_SHARED.durationBarDisplay),
        durationBarPosition = NormalizeDurationBarPosition(
            ReadUnitLaneStyleRaw(layout, laneLayout, rootShared, spec.durationBarPositionKey, "durationBarPosition"),
            DEFAULT_SHARED.durationBarPosition),
        durationBarDirection = NormalizeDurationBarDirection(
            ReadUnitLaneStyleRaw(layout, laneLayout, rootShared, spec.durationBarDirectionKey, "durationBarDirection"),
            DEFAULT_SHARED.durationBarDirection),
        showStacks = ReadUnitLaneStyleBool(layout, laneLayout, rootShared,
            spec.showStackKey, "showStackCount", true),
        showTooltip = ReadUnitLaneStyleBool(layout, laneLayout, rootShared,
            spec.tooltipKey, "showTooltip", DEFAULT_SHARED.showTooltip),
        showAuraBorder = debuffTypeBorderMode ~= "OFF",
        showAuraSymbol = debuffTypeBorderMode == "SYMBOL",
        showStealableMarker = kind == "buff" and ReadUnitStyleBool(layout, laneLayout, rootShared, "buffShowStealable", false),
        stealableStyle = kind == "buff" and A3.NormalizeStealableStyle(
            ReadUnitStyleRaw(layout, laneLayout, rootShared, "buffStealableStyle")) or nil,
        cooldownSize = ReadUnitLaneStyleNumber(layout, laneLayout, rootShared,
            spec.cooldownSizeKey, "cooldownTextSize", DEFAULT_SHARED.cooldownTextSize, 6, 40),
        cooldownAnchor = ReadUnitLaneStyleAnchor(layout, laneLayout, rootShared,
            spec.cooldownAnchorKey, "cooldownTextAnchor", cooldownAnchor),
        cooldownX = ReadUnitLaneStyleNumber(layout, laneLayout, rootShared,
            spec.cooldownXKey, "cooldownTextOffsetX", DEFAULT_SHARED.cooldownTextOffsetX, -2000, 2000),
        cooldownY = ReadUnitLaneStyleNumber(layout, laneLayout, rootShared,
            spec.cooldownYKey, "cooldownTextOffsetY", DEFAULT_SHARED.cooldownTextOffsetY, -2000, 2000),
        cooldownDecimalSeconds = ReadUnitLaneStyleNumber(layout, laneLayout, rootShared,
            spec.cooldownDecimalKey, "cooldownDecimalSeconds", DEFAULT_SHARED.cooldownDecimalSeconds, 0, 30),
        stackAnchor = ReadUnitLaneStyleAnchor(layout, laneLayout, rootShared,
            spec.stackAnchorKey, "stackCountAnchor", DEFAULT_SHARED.stackCountAnchor),
        stackSize = ReadUnitLaneStyleNumber(layout, laneLayout, rootShared,
            spec.stackSizeKey, "stackTextSize", DEFAULT_SHARED.stackTextSize, 6, 40),
        stackX = ReadUnitLaneStyleNumber(layout, laneLayout, rootShared,
            spec.stackXKey, "stackTextOffsetX", DEFAULT_SHARED.stackTextOffsetX, -2000, 2000),
        stackY = ReadUnitLaneStyleNumber(layout, laneLayout, rootShared,
            spec.stackYKey, "stackTextOffsetY", DEFAULT_SHARED.stackTextOffsetY, -2000, 2000),
    })
end

local function CompileGroupLane(unit, source, kind, groupKind, portraitShape, shared)
    local spec = GROUP_LANE_SPECS[kind]
    if not (spec and type(source) == "table") then return nil end
    local candidateFilters, candidateFilterSignature
    if spec.includeHashKey then
        candidateFilters, candidateFilterSignature = CandidateFiltersFromIncludeAndExcludeSpellIDs(source[spec.includeHashKey], source[spec.blacklistHashKey])
    else
        candidateFilters, candidateFilterSignature = CandidateFiltersFromBlacklistHash(source[spec.blacklistHashKey])
    end
    candidateFilters, candidateFilterSignature = AddMaxDurationCandidateFilter(
        candidateFilters, candidateFilterSignature,
        spec.maxDurationKey and source[spec.maxDurationKey], source[spec.hidePermanentKey] == true)
    candidateFilters, candidateFilterSignature = AddNonPlayerCandidateFilter(
        candidateFilters, candidateFilterSignature,
        spec.nonPlayerKey and source[spec.nonPlayerKey] == true)
    local size = ClampNumber(source[spec.sizeKey] or source.iconSize, spec.defaultSize, 1, 256)
    local sharedLane = kind == "debuff" and "debuff" or "buff"
    local iconShapeSource = Shape.SharedValue(shared, sharedLane)
    local iconShape, requestedIconShape = Shape.Resolve(iconShapeSource, portraitShape)
    local spacing = ClampNumber(source[spec.spacingKey] or source.spacing, 1, 0, 64)
    local perRow = ClampNumber(source[spec.perRowKey] or source.perRow, spec.defaultPerRow, 1, 40)
    local maxCount = ClampNumber(source[spec.maxKey], spec.defaultMax, 0, 80)
    local enabled = source.enabled ~= false and source[spec.showKey] == true and maxCount > 0
    local growthX, growthY, xSign, ySign, verticalGrowth = GroupGrowthParts(source[spec.growthXKey], source[spec.growthYKey])
    local cols, rows = GridShape(maxCount, perRow, verticalGrowth)
    local debuffTypeBorderMode = kind == "debuff" and ReadGroupDebuffTypeBorderMode(source) or "OFF"
    local cooldownSwipeReverse = source[spec.swipeReverseKey]
    if cooldownSwipeReverse == nil then cooldownSwipeReverse = source.cooldownSwipeReverse end
    local showTooltip = source[spec.tooltipKey]
    if showTooltip == nil then showTooltip = source.showTooltip end
    local rawStrata = source[spec.strataKey]
    if issecretvalue(rawStrata) == true then rawStrata = nil end
    if rawStrata == nil then rawStrata = source.strata end
    local nativeFilter = NormalizeNativeFilterString(source[spec.filterKey], spec.filter)
    -- Blizzard applies exact spell-ID candidate filters only while the unit's
    -- current identity supports that aura polarity: HELPFUL while assistable,
    -- HARMFUL while non-assistable. Compile the access mode once so rare
    -- identity events never inspect saved settings. The standard group debuff
    -- blacklist is intentionally neutral: hiding that entire lane whenever a
    -- friendly unit is assistable would be worse than Blizzard's exclude-only
    -- 12.1 limitation. A future HARMFUL include-ID lane is handled correctly.
    local hasIncludeIDs = candidateFilters and candidateFilters.includeSpellIDs ~= nil
    local hasExactIDs = hasIncludeIDs
        or candidateFilters and candidateFilters.excludeSpellIDs ~= nil
    local identityCandidateMode
    if kind == "trackedBuff" or kind == "external" then
        identityCandidateMode = "assist"
    elseif hasIncludeIDs and nativeFilter:find("HARMFUL", 1, true) ~= nil then
        identityCandidateMode = "hostile"
    elseif kind == "buff" and (hasExactIDs
        or nativeFilter:find("EXTERNAL_DEFENSIVE", 1, true) ~= nil
        or nativeFilter:find("BIG_DEFENSIVE", 1, true) ~= nil) then
        identityCandidateMode = "assist"
    end
    return FinalizeLane({
        kind = kind,
        appearanceKind = sharedLane,
        rootKey = spec.rootKey,
        unit = unit,
        enabled = enabled == true,
        nativeFilter = nativeFilter,
        candidateFilters = candidateFilters,
        candidateFilterSignature = candidateFilterSignature,
        identityCandidateMode = identityCandidateMode,
        groupAccessGate = identityCandidateMode ~= nil,
        max = Round(maxCount),
        size = size,
        iconZoom = ClampNumber(source[spec.iconZoomKey] or source.iconZoom, 100, 100, 200),
        iconShape = iconShape,
        requestedIconShape = requestedIconShape,
        spacing = spacing,
        step = size + spacing,
        perRow = Round(perRow),
        cols = cols,
        rows = rows,
        width = math_max(1, cols * size + math_max(cols - 1, 0) * spacing),
        height = math_max(1, rows * size + math_max(rows - 1, 0) * spacing),
        x = Round(ClampNumber(source[spec.xKey], 0, -4096, 4096)),
        y = Round(ClampNumber(source[spec.yKey], 0, -4096, 4096)),
        anchor = ReadAnchor(source, nil, spec.anchorKey, spec.defaultAnchor),
        layer = Round(ClampNumber(source[spec.layerKey], spec.defaultLayer, 0, 30)),
        strata = NormalizeFrameStrata(rawStrata, "AUTO"),
        alpha = Clamp01(source[spec.alphaKey], 1),
        growthX = growthX,
        growthY = growthY,
        xSign = xSign,
        ySign = ySign,
        verticalGrowth = verticalGrowth == true,
        initialAnchor = ButtonAnchor(xSign, ySign),
        showCooldownText = source[spec.showTextKey] ~= false,
        showCooldownSwipe = source[spec.swipeKey] ~= false,
        cooldownSwipeReverse = cooldownSwipeReverse == true,
        sortMethod = NormalizeAuraSortMethod(source[spec.sortMethodKey]),
        sortReverse = source[spec.sortReverseKey] == true,
        showDurationBar = source[spec.showDurationBarKey] == true or source.showDurationBar == true,
        durationBarHeight = ClampNumber(source[spec.durationBarHeightKey] or source.durationBarHeight, DEFAULT_SHARED.durationBarHeight, 1, 16),
        durationBarDisplay = NormalizeDurationBarDisplay(source[spec.durationBarDisplayKey] or source.durationBarDisplay, DEFAULT_SHARED.durationBarDisplay),
        durationBarPosition = NormalizeDurationBarPosition(source[spec.durationBarPositionKey] or source.durationBarPosition, DEFAULT_SHARED.durationBarPosition),
        durationBarDirection = NormalizeDurationBarDirection(source[spec.durationBarDirectionKey] or source.durationBarDirection, DEFAULT_SHARED.durationBarDirection),
        showStacks = source[spec.showStackKey] ~= false,
        showTooltip = showTooltip ~= false,
        showAuraBorder = debuffTypeBorderMode ~= "OFF",
        showAuraSymbol = debuffTypeBorderMode == "SYMBOL",
        cooldownSize = ClampNumber(source[spec.cooldownSizeKey] or source.cooldownSize, DEFAULT_SHARED.cooldownTextSize, 6, 40),
        cooldownAnchor = ReadAnchor(source, nil, spec.cooldownAnchorKey, "CENTER"),
        cooldownX = ClampNumber(source[spec.cooldownXKey] or source.cooldownX, 0, -2000, 2000),
        cooldownY = ClampNumber(source[spec.cooldownYKey] or source.cooldownY, 0, -2000, 2000),
        cooldownDecimalSeconds = ClampNumber(source[spec.cooldownDecimalKey] or source.cooldownDecimalSeconds, DEFAULT_SHARED.cooldownDecimalSeconds, 0, 30),
        stackAnchor = ReadAnchor(source, nil, spec.stackAnchorKey, "BOTTOMRIGHT"),
        stackSize = ClampNumber(source[spec.stackSizeKey] or source.stackSize, DEFAULT_SHARED.stackTextSize, 6, 40),
        stackX = ClampNumber(source[spec.stackXKey] or source.stackX, 0, -2000, 2000),
        stackY = ClampNumber(source[spec.stackYKey] or source.stackY, 0, -2000, 2000),
    }, sharedLane)
end

local function InvalidateUnitRuntimeConfig(unit)
    unit = NormalizeRuntimeUnit(unit)
    if not unit then return nil end
    local runtimeCache = A3._runtimeConfigCache
    if runtimeCache then runtimeCache[unit] = nil end
    local frame = (A3._runtimeFrames and A3._runtimeFrames[unit])
        or (UF and UF.GetFrame and UF.GetFrame(unit))
        or (UF and UF.frames and UF.frames[unit])
        or _G["MSUF_" .. unit]
    if frame then
        if frame.MSUFSpec then frame.MSUFSpec._msufA3UnitAuraConfigCache = nil end
        if frame.Auras then frame.Auras.needFullUpdate = true end
    end
    return unit
end

--- Menu writes land in the Auras3 saved model without touching UF.Config, so
--- neither _runtimeConfigGen nor UF.Config.serial moves. Callers that refresh
--- a unit through the UF element path must drop this cache first or both the
--- live lane and the menu preview keep reading the pre-write layout.
function A3.InvalidateUnitRuntimeConfig(unit)
    if unit == "boss" then
        for i = 1, 5 do InvalidateUnitRuntimeConfig("boss" .. i) end
        return "boss"
    end
    return InvalidateUnitRuntimeConfig(unit)
end

local function EmptyUnitFrameConfig(unit)
    return {
        unit = unit,
        enabled = false,
        lanes = {},
        sensors = {},
        group = false,
        _msufA3ConfigGen = A3._runtimeConfigGen or 1,
        _msufA3VisualGen = A3._nativeVisualGen or 0,
    }
end

local function UnitCustomDisplayScope(unit)
    if type(unit) == "string" and unit:match("^boss%d+$") then return "boss" end
    return unit
end

local function EffectiveUnitCustomDisplays(auras, unit)
    local root = type(auras) == "table" and auras.customDisplays or nil
    if type(root) ~= "table" then return nil end
    local scope = UnitCustomDisplayScope(unit)
    local record = type(root.perUnit) == "table" and root.perUnit[scope] or nil
    if type(record) == "table" and record.override == true and type(record.items) == "table" then return record.items end
    return nil
end

local function EffectiveUnitCustomContainers(auras, unit)
    local root = type(auras) == "table" and auras.customContainers or nil
    local scope = UnitCustomDisplayScope(unit)
    local record = type(root) == "table" and type(root.perUnit) == "table" and root.perUnit[scope] or nil
    return type(record) == "table" and type(record.items) == "table" and record.items or nil
end

local function CustomSpellIDHash(value)
    local out, count = {}, 0
    if type(value) == "string" then
        for token in value:gmatch("%d+") do
            local spellID = tonumber(token)
            if spellID and spellID > 0 and out[spellID] ~= true then
                out[spellID] = true
                count = count + 1
            end
        end
    elseif type(value) == "table" then
        for key, enabled in pairs(value) do
            local raw = (type(enabled) == "number" or type(enabled) == "string") and enabled or key
            local spellID = tonumber(type(raw) == "number" and raw or tostring(raw):match("%d+"))
            if enabled ~= false and spellID and spellID > 0 and out[spellID] ~= true then
                out[spellID] = true
                count = count + 1
            end
        end
    end
    return count > 0 and out or nil
end

function A3._CustomPrioritySpellIDs(value, allowed)
    if type(allowed) ~= "table" then return nil end
    local ordered, seen = {}, {}
    local function Add(raw)
        local spellID = tonumber(type(raw) == "number" and raw or tostring(raw or ""):match("%d+"))
        if spellID then spellID = math_floor(spellID + 0.5) end
        if spellID and spellID > 0 and allowed[spellID] == true and not seen[spellID] then
            seen[spellID] = true
            ordered[#ordered + 1] = spellID
        end
    end
    if type(value) == "string" then
        for token in value:gmatch("%d+") do Add(token) end
    elseif type(value) == "table" then
        for i = 1, #value do Add(value[i]) end
        for key, child in pairs(value) do
            if type(key) ~= "number" or key < 1 or key > #value or key % 1 ~= 0 then
                Add((type(child) == "number" or type(child) == "string") and child or key)
            end
        end
    end
    local missing = {}
    for spellID in pairs(allowed) do
        if not seen[spellID] then missing[#missing + 1] = spellID end
    end
    table_sort(missing)
    for i = 1, #missing do ordered[#ordered + 1] = missing[i] end
    return #ordered > 0 and ordered or nil
end

A3._PlayerDefensiveTrackedSpellIDHash = function(entry)
    if type(entry) ~= "table" then return nil end
    local disabled = CustomSpellIDHash(entry.disabledPredefinedSpellIDs)
    local combined, count = {}, 0
    for spellID in pairs(A3._PlayerDefensiveSpellIDHash()) do
        if not (disabled and disabled[spellID] == true) then
            combined[spellID] = true
            count = count + 1
        end
    end
    local custom = CustomSpellIDHash(entry.spellIDs or entry.includeSpellIDs)
    for spellID in pairs(custom or {}) do
        if combined[spellID] ~= true then
            combined[spellID] = true
            count = count + 1
        end
    end
    return count > 0 and combined or nil
end

A3._AddPlayerDefensiveAutoBlacklist = function(candidateFilters, candidateFilterSignature, entry, tracked)
    if type(entry) ~= "table" or entry.autoBlacklistPlayerBuffs == false
        or entry.enabled ~= true
    then
        return candidateFilters, candidateFilterSignature
    end
    tracked = tracked or A3._PlayerDefensiveTrackedSpellIDHash(entry)
    if not tracked then return candidateFilters, candidateFilterSignature end
    candidateFilters = candidateFilters or {}
    local excluded = candidateFilters.excludeSpellIDs
    if type(excluded) ~= "table" then
        excluded = {}
        candidateFilters.excludeSpellIDs = excluded
    end
    local expanded = {}
    for spellID in pairs(tracked) do
        if type(A3.AddAuraSpellIDAndAliases) == "function" then
            A3.AddAuraSpellIDAndAliases(expanded, spellID)
        else
            expanded[spellID] = true
        end
    end
    local parts, count = {}, 0
    for spellID in pairs(expanded) do
        excluded[spellID] = true
        count = count + 1
        parts[count] = tostring(spellID)
    end
    table_sort(parts)
    local autoSignature = "autoPlayerDefensives:" .. table_concat(parts, ",")
    candidateFilterSignature = candidateFilterSignature
        and (candidateFilterSignature .. ";" .. autoSignature) or autoSignature
    return candidateFilters, candidateFilterSignature
end

A3._AddTargetDotAutoBlacklist = function(candidateFilters, candidateFilterSignature, entry, tracked)
    if type(entry) ~= "table" or entry.autoBlacklistDebuffs == false
        or entry.enabled ~= true or type(tracked) ~= "table"
    then
        return candidateFilters, candidateFilterSignature
    end
    local parts, count = {}, 0
    for spellID in pairs(tracked) do
        count = count + 1
        parts[count] = tostring(spellID)
    end
    if count == 0 then return candidateFilters, candidateFilterSignature end
    candidateFilters = candidateFilters or {}
    local excluded = candidateFilters.excludeSpellIDs
    if type(excluded) ~= "table" then
        excluded = {}
        candidateFilters.excludeSpellIDs = excluded
    end
    for spellID in pairs(tracked) do
        excluded[spellID] = true
    end
    table_sort(parts)
    local autoSignature = "autoTargetDots:" .. table_concat(parts, ",")
    candidateFilterSignature = candidateFilterSignature
        and (candidateFilterSignature .. ";" .. autoSignature) or autoSignature
    return candidateFilters, candidateFilterSignature
end

local function TargetDotSpellIDHash()
    local cached = A3._targetDotRuntimeLookup
    if cached then return cached end
    cached = {}
    for _, spells in pairs(A3.TargetDotData or {}) do
        for i = 1, #spells do
            local spellID = tonumber(spells[i][1])
            if spellID then cached[spellID] = true end
        end
    end
    A3._targetDotRuntimeLookup = cached
    return cached
end

local function ManagedLaneFrameLevel(parentFrame, lane)
    local parentLevel = parentFrame and parentFrame.GetFrameLevel and (parentFrame:GetFrameLevel() or 0) or 0
    if lane and lane.portraitOverlay == true then
        -- Portrait auras are a replacement surface owned by the portrait
        -- holder, not an independent unit-frame overlay. Keep the proven
        -- parent-relative birth order: container/host on the holder plane,
        -- native AuraButton one level above it, then cooldown text above the
        -- button. Encoding the lane's universal layer here can put the sealed
        -- native icon below the portrait while the separately levelled text
        -- remains visible.
        return parentLevel
    end
    if FrameLayers.ElementLevel then
        return FrameLayers.ElementLevel(lane and lane.layer, 1, 0)
    end
    return parentLevel + AuraIconBaseOffset(parentFrame) + (lane and lane.layer or 1)
end

local function ResolveLaneParentFrame(parentFrame, lane)
    if lane and lane.anchorTarget == "portrait" and parentFrame then
        if lane.portraitPositionWhenDisabled == true then
            local portrait = parentFrame.MSUFSpec and parentFrame.MSUFSpec.portrait
            if portrait and portrait.enabled ~= true then
                local element = UF and UF.elements and UF.elements.Portrait
                if element and type(element.AcquirePositionAnchor) == "function" then
                    element.AcquirePositionAnchor(parentFrame, portrait)
                end
            end
        end
        return parentFrame.MSUFPortraitHolder or parentFrame
    end
    return parentFrame
end

A3._PlayerDefensiveSpellIDHash = function()
    local playerClass
    if type(UnitClass) == "function" then
        local _
        _, playerClass = UnitClass("player")
    end
    if type(playerClass) ~= "string" or playerClass == "" then playerClass = "__ALL" end
    A3._playerDefensiveRuntimeLookup = A3._playerDefensiveRuntimeLookup or {}
    local cached = A3._playerDefensiveRuntimeLookup[playerClass]
    if cached then return cached end
    cached = {}
    if playerClass == "__ALL" then
        for _, spells in pairs(A3.PlayerDefensiveData or {}) do
            for i = 1, #spells do
                local spellID = tonumber(spells[i][1])
                if spellID then cached[spellID] = true end
            end
        end
    else
        local spells = A3.PlayerDefensiveData and A3.PlayerDefensiveData[playerClass]
        for i = 1, type(spells) == "table" and #spells or 0 do
            local spellID = tonumber(spells[i][1])
            if spellID then cached[spellID] = true end
        end
    end
    A3._playerDefensiveRuntimeLookup[playerClass] = cached
    return cached
end

local function CompileUnitCustomDisplays(auras, unit)
    local source = EffectiveUnitCustomDisplays(auras, unit)
    if type(source) ~= "table" then return nil end
    local items = {}
    for i = 1, #source do
        local entry = source[i]
        if type(entry) == "table" and entry.enabled ~= false then
            local includeSpellIDs = CustomSpellIDHash(entry.spellIDs or entry.includeSpellIDs)
            if includeSpellIDs then
                local helpful = tostring(entry.auraType or "BUFF"):upper() ~= "DEBUFF"
                items[#items + 1] = {
                    key = "ufcustom:" .. tostring(entry.id or i),
                    display = entry.name or ("Custom Aura " .. tostring(i)),
                    enabled = true,
                    includeSpellIDs = includeSpellIDs,
                    nativeFilter = helpful and (entry.onlyOwn == true and "HELPFUL|PLAYER" or "HELPFUL")
                        or (entry.onlyOwn == true and "HARMFUL|PLAYER" or "HARMFUL"),
                    onlyOwn = entry.onlyOwn == true,
                    placed = type(entry.placed) == "table" and entry.placed or nil,
                    frame = type(entry.frame) == "table" and entry.frame or nil,
                    layer = entry.layer,
                    strata = entry.strata,
                    icon = entry.icon,
                    color = entry.color or (type(entry.frame) == "table" and entry.frame.color or nil),
                }
            end
        end
    end
    if #items == 0 then return nil end
    return SpellIndicatorsRuntime.CompileSlots(unit, {
        enabled = true,
        items = items,
        layer = 9,
        strata = "AUTO",
    })
end

-- Kept on A3 rather than as a main-chunk local: this chunk runs against the
-- Lua 200-local ceiling (see the local budget in msuf_static_checks).
function A3._CompilePortraitAuraLane(lane, frameSpec, entry, kind, rootKey, scope, exactPortraitRect)
    local portrait = frameSpec and frameSpec.portrait
    local usePortraitPosition = entry and entry.portraitPositionWhenDisabled == true
    if not (lane and portrait and (portrait.enabled == true or usePortraitPosition)) then return nil end
    -- Preserve the proven portrait geometry while retaining the custom lane's
    -- complete Aura Style contract. Portrait mode changes placement only; it
    -- must not silently discard opacity, text, swipe, stacks or duration bars.
    local portraitWidth = ClampNumber(portrait.width, portrait.size or 24, 8, 128)
    local portraitHeight = ClampNumber(portrait.height, portrait.size or 24, 8, 128)
    local size = math_min(portraitWidth, portraitHeight)
    local buttonWidth = exactPortraitRect == true and portraitWidth or size
    local buttonHeight = exactPortraitRect == true and portraitHeight or size
    local spacing = 0
    local maxCount = Round(ClampNumber(entry and entry.portraitMaxIcons, 1, 1, 8))
    local verticalGrowth = lane.verticalGrowth == true
    local perRow = verticalGrowth and 1 or math_max(1, Round(ClampNumber(lane.perRow, 4, 1, 40)))
    local cols, rows = GridShape(maxCount, perRow, verticalGrowth)
    local xSign = tonumber(lane.xSign) or 1
    local ySign = tonumber(lane.ySign) or -1
    local initialAnchor = ButtonAnchor(xSign, ySign)
    local insetX = (portraitWidth - buttonWidth) * 0.5
    local insetY = (portraitHeight - buttonHeight) * 0.5
    local anchorX = initialAnchor:find("RIGHT", 1, true) and -insetX or insetX
    local anchorY = initialAnchor:find("BOTTOM", 1, true) and insetY or -insetY
    local out = {}
    for key, value in pairs(lane) do
        if tostring(key):find("^_msufA3") == nil then out[key] = value end
    end
    out.kind = kind
    out.rootKey = rootKey
    out.anchorTarget = "portrait"
    out.portraitOverlay = true
    out.portraitLevelOffset = portrait.levelOffset
    out.portraitPositionWhenDisabled = usePortraitPosition
    out.enabled = maxCount > 0
    out.max = maxCount
    out.size = size
    out.buttonWidth = buttonWidth
    out.buttonHeight = buttonHeight
    out.spacing = spacing
    out.step = size + spacing
    out.stepX = buttonWidth + spacing
    out.stepY = buttonHeight + spacing
    out.perRow = perRow
    out.cols = cols
    out.rows = rows
    out.padding = 0
    out.width = math_max(1, cols * buttonWidth + math_max(cols - 1, 0) * spacing)
    out.height = math_max(1, rows * buttonHeight + math_max(rows - 1, 0) * spacing)
    -- The standalone bar's saved Edit Mode offsets must NOT leak in here: a
    -- previously dragged bar would push the "portrait" icon out of the
    -- portrait entirely. Icon 1 sits exactly inside the portrait; moving the
    -- portrait itself is the one way to move it.
    out.x = anchorX
    out.y = anchorY
    out.anchor = initialAnchor
    out.layer = 0
    out.strata = "AUTO"
    out.alpha = lane.alpha
    out.growthX = lane.growthX
    out.growthY = lane.growthY
    out.xSign = xSign
    out.ySign = ySign
    out.verticalGrowth = verticalGrowth
    out.initialAnchor = initialAnchor
    out.showCooldownText = lane.showCooldownText == true
        and entry and entry.portraitCooldownText ~= false or false
    -- The AuraButton itself is the portrait replacement. Keep Blizzard's
    -- native duration swipe on that same button so icon, swipe, and duration
    -- text can never split into separate visual owners.
    out.showCooldownSwipe = lane.showCooldownSwipe == true
    out.showDurationBar = lane.showDurationBar == true
    out.showStacks = lane.showStacks == true
    if exactPortraitRect == true then
        -- Portrait presentation is an exact replacement surface: dimensions
        -- and mask always follow this UnitFrame's compiled portrait, regardless
        -- of the normal DoT lane's standalone icon-shape choice.
        out.iconShape, out.requestedIconShape = Shape.Resolve(Shape.FOLLOW_PORTRAIT, portrait.shape)
    end
    return FinalizeLane(out, lane.appearanceKind)
end

A3._CompilePlayerDefensivePortraitLane = function(lane, frameSpec, entry)
    return A3._CompilePortraitAuraLane(
        lane, frameSpec, entry, "defensivePortrait", "DefensivePortrait", "player", false)
end

A3._CompileTargetDotPortraitLane = function(lane, frameSpec, entry, unit)
    if unit ~= "target" and unit ~= "focus" and not tostring(unit or ""):match("^boss%d+$") then return nil end
    return A3._CompilePortraitAuraLane(
        lane, frameSpec, entry, "targetDotPortrait", "TargetDotPortrait", unit, true)
end

--- Upgrade the former shared Custom-4 presentation into the owning frame once.
--- Afterwards Player Defensives and Target DoTs use the same frame-local Style
--- contract as every other Aura container. This is cached config work only.
A3._specialCustomStylePlacedKeys = A3._specialCustomStylePlacedKeys or {
    iconZoom = true, iconShape = true, showTooltip = true, alpha = true,
    debuffTypeBorderMode = true,
    showStacks = true, stackSize = true, stackAnchor = true, stackX = true, stackY = true,
    showCooldown = true, showCooldownSwipe = true, cooldownSwipeReverse = true,
    cooldownSize = true, cooldownAnchor = true, cooldownX = true, cooldownY = true,
    cooldownDecimalSeconds = true,
    showDurationBar = true, durationBarHeight = true, durationBarDisplay = true,
    durationBarPosition = true, durationBarDirection = true,
    pandemicEnabled = true, pandemicStyle = true, pandemicColor = true,
    pandemicThickness = true, pandemicPadding = true,
    pandemicBorderAlpha = true, pandemicTintAlpha = true,
    pandemicBlend = true,
}
local function CopySpecialStyleValue(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, child in pairs(value) do out[key] = CopySpecialStyleValue(child) end
    return out
end
A3._ResolveSpecialCustomStyle = function(auras, unit, index, entry)
    local placed = type(entry) == "table" and type(entry.placed) == "table" and entry.placed or {}
    local frame = type(entry) == "table" and type(entry.frame) == "table" and entry.frame or nil
    if index ~= 4 or type(entry) ~= "table" or entry._msufA3LocalStyleFromShared_v1 == true then
        return placed, frame
    end
    local shared = type(auras) == "table" and type(auras.shared) == "table" and auras.shared or nil
    local styles = shared and type(shared.specialStyles) == "table" and shared.specialStyles or nil
    local key = unit == "player" and "playerDefensives" or "targetDots"
    local record = styles and type(styles[key]) == "table" and styles[key] or nil
    local stylePlaced = record and type(record.placed) == "table" and record.placed or nil
    if stylePlaced then
        entry.placed = placed
        for name in pairs(A3._specialCustomStylePlacedKeys) do
            if stylePlaced[name] ~= nil then placed[name] = CopySpecialStyleValue(stylePlaced[name]) end
        end
    end
    if record and type(record.frame) == "table" then
        entry.frame = CopySpecialStyleValue(record.frame)
        frame = entry.frame
    end
    entry._msufA3LocalStyleFromShared_v1 = true
    return placed, frame
end

local function CompileUnitCustomLane(unit, entry, index, lanePadding, frameSpec, shared, auras)
    if type(entry) ~= "table" then return nil, nil end
    local playerDefensives = unit == "player" and (index == 4 or entry.playerDefensives == true)
    -- `enabled` is the Core feature's master switch. Portrait mode is only a
    -- presentation choice and cannot keep a disabled feature alive.
    if entry.enabled ~= true then return nil, nil end
    local nameAliasSpellIDs = CustomSpellIDHash(entry.spellIDs or entry.includeSpellIDs)
    local includeSpellIDs = nameAliasSpellIDs
    local targetDots = not playerDefensives and (index == 4 or entry.targetDots == true)
    -- Target DoT portrait presentation belongs exclusively to the reserved
    -- index-4 lane. Custom 1-3 must remain normal custom containers even if a
    -- stale/imported record happens to carry the targetDots marker.
    local portraitRequested = (playerDefensives or (targetDots and index == 4))
        and entry.portraitIcon == true
    if playerDefensives then
        includeSpellIDs = A3._PlayerDefensiveTrackedSpellIDHash(entry)
    end
    if targetDots and includeSpellIDs then
        local allowed, customAllowed, count = TargetDotSpellIDHash(), CustomSpellIDHash(entry.customSpellIDs), 0
        for spellID in pairs(includeSpellIDs) do
            if allowed[spellID] ~= true and not (customAllowed and customAllowed[spellID] == true) then
                includeSpellIDs[spellID] = nil
            else
                count = count + 1
            end
        end
        if count == 0 then includeSpellIDs = nil end
    end
    if not includeSpellIDs then return nil, nil end
    local candidateFilters, candidateFilterSignature = CandidateFiltersFromSpellIDs(includeSpellIDs, "includeSpellIDs")
    local layoutPlaced = type(entry.placed) == "table" and entry.placed or {}
    local placed, styleFrame = A3._ResolveSpecialCustomStyle(auras, unit, index, entry)
    -- Player Defensive Buffs combines a curated class list with custom IDs and
    -- therefore keeps ordinary AuraKit sorting. Every exact-ID custom lane,
    -- including Dots on target, can use the same native one-group-per-spell
    -- priority path without inspecting aura payloads in Lua.
    local customPriority = not playerDefensives
        and tostring(placed.sortMethod or ""):upper() == "CUSTOM_PRIORITY"
    local customPrioritySpellIDs = customPriority
        and A3._CustomPrioritySpellIDs(entry.prioritySpellIDs, includeSpellIDs) or nil
    lanePadding = ClampNumber((type(placed) == "table" and placed.stylePadding)
        or layoutPlaced.stylePadding, 0, 0, 16)
    local filters = type(entry.filters) == "table" and entry.filters or { enabled = true, onlyMine = entry.onlyOwn == true }
    local sourceUnit = unit
    local helpful = not targetDots and tostring(entry.auraType or "BUFF"):upper() ~= "DEBUFF"
    candidateFilters, candidateFilterSignature = AddMaxDurationCandidateFilter(
        candidateFilters, candidateFilterSignature,
        filters.maxDuration, filters.hidePermanent == true)
    local size = ClampNumber(layoutPlaced.size, 24, 1, 128)
    local spacing = ClampNumber(layoutPlaced.spacing, 2, 0, 64)
    local perRow = ClampNumber(layoutPlaced.perRow, 4, 1, 40)
    local maxCount = ClampNumber(layoutPlaced.max, 8, 0, 40)
    local growthX, growthY, xSign, ySign, verticalGrowth = GrowthParts(layoutPlaced.growth or "LEFTDOWN", "DOWN")
    local cols, rows = GridShape(maxCount, perRow, verticalGrowth)
    local appearanceKind = playerDefensives and "playerDefensives"
        or targetDots and "targetDots" or (helpful and "buff" or "debuff")
    local iconShapeSource = Shape.SharedValue(shared, appearanceKind)
    local iconShape, requestedIconShape = Shape.Resolve(
        iconShapeSource, frameSpec and frameSpec.portrait and frameSpec.portrait.shape)
    lanePadding = Round(ClampNumber(lanePadding, 0, 0, 16))
    local pandemicVisualEnabled = targetDots == true and placed.pandemicEnabled == true
    local pandemicFrameEffect
    if targetDots == true and type(styleFrame) == "table" and styleFrame.onlyInPandemicWindow == true then
        local normalizeFrameEffect = SpellIndicatorsRuntime.NormalizeFrameEffect
        pandemicFrameEffect = type(normalizeFrameEffect) == "function"
            and normalizeFrameEffect(styleFrame) or styleFrame
    end
    local lane = FinalizeLane({
        kind = "custom" .. tostring(index),
        appearanceKind = appearanceKind,
        rootKey = "CustomAuras" .. tostring(index),
        unit = sourceUnit,
        enabled = maxCount > 0,
        nativeFilter = targetDots and "HARMFUL|PLAYER"
            or (playerDefensives and "HELPFUL" or NativeFilter(helpful and "HELPFUL" or "HARMFUL", filters)),
        candidateFilters = candidateFilters,
        candidateFilterSignature = candidateFilterSignature,
        -- Exact spell-ID filters are valid only for the current unit polarity.
        -- Compile this once; the live identity route never reads settings.
        identityCandidateMode = helpful and "assist" or "hostile",
        -- WeakAuras' traditional non-exact Aura trigger resolves numeric input
        -- to a spell name. Keep the original user IDs so the opt-in UNIT_AURA
        -- resolver can learn the visible auraData.spellId without scanning
        -- disabled or ordinary Aura lanes.
        nameAliasSpellIDs = nameAliasSpellIDs,
        max = Round(maxCount),
        size = size,
        iconZoom = ClampNumber(placed.iconZoom, 100, 100, 200),
        iconShape = iconShape,
        requestedIconShape = requestedIconShape,
        spacing = spacing,
        step = size + spacing,
        perRow = Round(perRow),
        cols = cols,
        rows = rows,
        padding = lanePadding,
        width = math_max(1, cols * size + math_max(cols - 1, 0) * spacing + 2 * lanePadding),
        height = math_max(1, rows * size + math_max(rows - 1, 0) * spacing + 2 * lanePadding),
        x = Round(ClampNumber(layoutPlaced.x, 0, -4096, 4096)),
        y = Round(ClampNumber(layoutPlaced.y, 0, -4096, 4096)),
        anchor = ReadAnchor(layoutPlaced, nil, "anchor", "TOPRIGHT"),
        layer = Round(ClampNumber(entry.layer, 9, 0, 30)),
        strata = NormalizeFrameStrata(entry.strata, "AUTO"),
        alpha = Clamp01(placed.alpha, 1),
        growthX = growthX,
        growthY = growthY,
        xSign = xSign,
        ySign = ySign,
        verticalGrowth = verticalGrowth == true,
        initialAnchor = ButtonAnchor(xSign, ySign),
        showCooldownText = placed.showCooldown ~= false,
        showCooldownSwipe = placed.showCooldownSwipe ~= false,
        cooldownSwipeReverse = placed.cooldownSwipeReverse == true,
        -- CUSTOM_PRIORITY is an MSUF-owned ordered-group mode, not a Blizzard
        -- AuraContainerSortMethod enum. Each one-frame AuraGroup is natively
        -- filtered to one configured Spell ID and assigned a layoutIndex, so
        -- Blizzard can compact active custom auras in priority order without
        -- exposing their restricted payload or visibility to addon Lua.
        sortMethod = customPriority and "DEFAULT" or NormalizeAuraSortMethod(placed.sortMethod),
        sortReverse = customPriority and false or placed.sortReverse == true,
        customPriority = customPriority == true,
        customPrioritySpellIDs = customPrioritySpellIDs,
        customPrioritySignature = customPrioritySpellIDs and table_concat(customPrioritySpellIDs, ",") or nil,
        showDurationBar = placed.showDurationBar == true,
        durationBarHeight = ClampNumber(placed.durationBarHeight, DEFAULT_SHARED.durationBarHeight, 1, 16),
        durationBarDisplay = NormalizeDurationBarDisplay(placed.durationBarDisplay, DEFAULT_SHARED.durationBarDisplay),
        durationBarPosition = NormalizeDurationBarPosition(placed.durationBarPosition, DEFAULT_SHARED.durationBarPosition),
        durationBarDirection = NormalizeDurationBarDirection(placed.durationBarDirection, DEFAULT_SHARED.durationBarDirection),
        showStacks = placed.showStacks ~= false,
        showTooltip = placed.showTooltip ~= false,
        showAuraBorder = not helpful and NormalizeDebuffTypeBorderMode(placed.debuffTypeBorderMode, "OFF") ~= "OFF",
        showAuraSymbol = not helpful and NormalizeDebuffTypeBorderMode(placed.debuffTypeBorderMode, "OFF") == "SYMBOL",
        cooldownSize = ClampNumber(placed.cooldownSize, DEFAULT_SHARED.cooldownTextSize, 6, 40),
        cooldownAnchor = ReadAnchor(placed, nil, "cooldownAnchor", "CENTER"),
        cooldownX = ClampNumber(placed.cooldownX, 0, -2000, 2000),
        cooldownY = ClampNumber(placed.cooldownY, 0, -2000, 2000),
        cooldownDecimalSeconds = ClampNumber(placed.cooldownDecimalSeconds, DEFAULT_SHARED.cooldownDecimalSeconds, 0, 30),
        stackAnchor = ReadAnchor(placed, nil, "stackAnchor", "BOTTOMRIGHT"),
        stackSize = ClampNumber(placed.stackSize, DEFAULT_SHARED.stackTextSize, 6, 40),
        stackX = ClampNumber(placed.stackX, 0, -2000, 2000),
        stackY = ClampNumber(placed.stackY, 0, -2000, 2000),
        targetDots = targetDots == true,
        pandemicEnabled = pandemicVisualEnabled or pandemicFrameEffect ~= nil,
        pandemicVisualEnabled = pandemicVisualEnabled,
        pandemicFrameEffect = pandemicFrameEffect,
        pandemicStyle = A3.NormalizePandemicStyle(placed.pandemicStyle),
        pandemicColor = type(placed.pandemicColor) == "table" and placed.pandemicColor or A3.DEFAULT_PANDEMIC_COLOR,
        pandemicThickness = ClampNumber(placed.pandemicThickness, 2, 1, 12),
        pandemicPadding = ClampNumber(placed.pandemicPadding, 1, -8, 16),
        pandemicBorderAlpha = Clamp01(placed.pandemicBorderAlpha, 1),
        pandemicTintAlpha = Clamp01(placed.pandemicTintAlpha, 0.22),
        pandemicBlend = tostring(placed.pandemicBlend or "ADD"):upper() == "BLEND" and "BLEND" or "ADD",
    })
    local portraitLane
    if portraitRequested then
        if playerDefensives then
            portraitLane = A3._CompilePlayerDefensivePortraitLane(lane, frameSpec, entry)
        elseif targetDots then
            portraitLane = A3._CompileTargetDotPortraitLane(lane, frameSpec, entry, unit)
        end
    end
    -- If the visible portrait is disabled and its position-only option is also
    -- off, fall back to the normal bar instead of silently losing tracked auras.
    local barEnabled = portraitLane == nil
    local effect
    -- Unconditional Full-Frame effects remain independent aura sensors in portrait mode.
    -- Pandemic-only effects live on every visible DoT AuraButton and need no duplicate sensor.
    if pandemicFrameEffect == nil and type(styleFrame) == "table" and styleFrame.type and styleFrame.type ~= "none" then
        effect = {
            key = "ufcustom_effect:" .. tostring(index),
            display = entry.name or ("Custom " .. tostring(index)),
            enabled = true,
            includeSpellIDs = includeSpellIDs,
            hidePermanent = filters.hidePermanent == true,
            nativeFilter = lane.nativeFilter,
            placed = { type = "none", anchor = layoutPlaced.anchor or "TOPRIGHT", x = 0, y = 0, size = 1 },
            frame = styleFrame,
            layer = entry.layer or 9,
            strata = entry.strata or "AUTO",
            color = styleFrame.color,
            unit = sourceUnit,
        }
    end
    return barEnabled and lane or nil, effect, portraitLane
end

local function CompileUnitCustomContainers(auras, unit, frameSpec)
    local source = EffectiveUnitCustomContainers(auras, unit)
    if type(source) ~= "table" then return nil, nil end
    -- Custom containers carry their own spacing in the per-container record;
    -- there is no Unit-wide or Shared lane-padding fallback.
    local lanes, effectItems, targetDotEffectItems = {}, {}, {}
    for i = 1, 4 do
        local lane, effect, portraitLane = CompileUnitCustomLane(unit, source[i], i, nil, frameSpec, auras.shared, auras)
        if lane then lanes["custom" .. tostring(i)] = lane end
        if portraitLane then lanes[portraitLane.kind] = portraitLane end
        if effect then
            local bucket = i == 4 and unit ~= "player" and targetDotEffectItems or effectItems
            bucket[#bucket + 1] = effect
        end
    end
    local effects, targetDotEffects
    if #effectItems > 0 then
        effects = SpellIndicatorsRuntime.CompileSlots(unit, { enabled = true, items = effectItems, layer = 9, strata = "AUTO", rootKey = "SpellIndicators" })
    end
    if #targetDotEffectItems > 0 then
        targetDotEffects = SpellIndicatorsRuntime.CompileSlots(
            targetDotEffectItems[1].unit or unit,
            { enabled = true, items = targetDotEffectItems, layer = 9, strata = "AUTO", rootKey = "TargetDotEffects" })
    end
    return lanes, effects, targetDotEffects
end
A3._CompileUnitCustomContainers = CompileUnitCustomContainers

local function CompileUnitLaneEffects(unit, laneLayout, buff, debuff)
    local items = {}
    local function Add(kind, lane)
        if not (lane and lane.enabled == true) then return end
        local prefix = kind == "buff" and "buff" or "debuff"
        local effectType = tostring(ReadRaw(laneLayout, nil, prefix .. "FrameEffectType") or "none"):lower()
        if effectType == "none" or effectType == "" then return end
        local color = ReadRaw(laneLayout, nil, prefix .. "FrameEffectColor")
        items[#items + 1] = {
            key = "uflane_effect:" .. kind,
            display = kind == "buff" and "Buffs" or "Debuffs",
            enabled = true,
            allowAnyAura = true,
            candidateFilters = lane.candidateFilters,
            candidateFilterSignature = lane.candidateFilterSignature,
            nativeFilter = lane.nativeFilter,
            placed = { type = "none", anchor = "CENTER", x = 0, y = 0, size = 1 },
            frame = {
                type = effectType,
                color = type(color) == "table" and color or { 0.69, 0.50, 0.88, 0.80 },
                priority = ReadNumber(laneLayout, nil, prefix .. "FrameEffectPriority", 5, 1, 10),
                thickness = ReadNumber(laneLayout, nil, prefix .. "FrameEffectThickness", 2, 1, 16),
                layer = ReadNumber(laneLayout, nil, prefix .. "FrameEffectLayer", 0, 0, 30),
                strata = ReadRaw(laneLayout, nil, prefix .. "FrameEffectStrata") or "AUTO",
            },
            layer = 9,
            strata = "AUTO",
        }
    end
    Add("buff", buff)
    Add("debuff", debuff)
    if #items == 0 then return nil end
    return SpellIndicatorsRuntime.CompileSlots(unit, {
        enabled = true, items = items, layer = 9, strata = "AUTO", rootKey = "LaneEffects",
    })
end

local function BuildUnitFrameConfig(unit, frameSpec)
    unit = NormalizeRuntimeUnit(unit)
    if not unit then return nil end
    local auras = EnsureDB()
    local iconsEnabled = UnitAuraIconsEnabled(auras, unit)
    local customLanes, customEffects, targetDotEffects = CompileUnitCustomContainers(auras, unit, frameSpec)
    local hasCustomContainers = false
    if customLanes then
        for _, lane in pairs(customLanes) do
            if lane and lane.enabled == true then hasCustomContainers = true; break end
        end
    end
    local legacyCustomDisplays = not EffectiveUnitCustomContainers(auras, unit) and CompileUnitCustomDisplays(auras, unit) or nil
    local dispelBorder = iconsEnabled and CompileDispelSensor(unit, frameSpec, false, "border") or nil
    -- Purge is a standalone one-slot native sensor. It must keep working when
    -- the ordinary visible aura lanes are disabled.
    local purgeBorder = CompileDispelSensor(unit, frameSpec, false, "purge")
    local dispelOverlay = iconsEnabled and CompileDispelSensor(unit, frameSpec, false, "overlay") or nil
    local dispelSymbol = iconsEnabled and CompileDispelSensor(unit, frameSpec, false, "symbol") or nil
    local buff, debuff, laneEffects
    if iconsEnabled then
        local layout, laneLayout, filtersRoot = EffectiveUnitTables(auras, unit)
        local blacklist = EffectiveUnitBlacklist(auras, unit)
        local buffBlacklist = type(blacklist) == "table" and type(blacklist.buffs) == "table" and blacklist.buffs or blacklist
        local debuffBlacklist = type(blacklist) == "table" and type(blacklist.debuffs) == "table" and blacklist.debuffs or blacklist
        local buffCandidates, buffCandidateSignature = CandidateFiltersFromBlacklist(buffBlacklist)
        local debuffCandidates, debuffCandidateSignature = CandidateFiltersFromBlacklist(debuffBlacklist)
        if unit == "player" then
            local customContainers = EffectiveUnitCustomContainers(auras, unit)
            local defensiveLane = customLanes and (customLanes.custom4 or customLanes.defensivePortrait)
            local tracked = defensiveLane and defensiveLane.candidateFilters
                and defensiveLane.candidateFilters.includeSpellIDs
            buffCandidates, buffCandidateSignature = A3._AddPlayerDefensiveAutoBlacklist(
                buffCandidates, buffCandidateSignature,
                type(customContainers) == "table" and customContainers[4] or nil, tracked)
        elseif unit == "target" or unit == "focus" or tostring(unit):match("^boss%d+$") then
            -- Each UnitFrame resolves its own saved Target/Focus/Boss scope.
            -- Reuse the already compiled player-owned DoT IDs; no extra aura
            -- query or runtime filtering is introduced by this convenience.
            local customContainers = EffectiveUnitCustomContainers(auras, unit)
            local targetDotLane = customLanes and (customLanes.custom4 or customLanes.targetDotPortrait)
            local tracked = targetDotLane and targetDotLane.candidateFilters
                and targetDotLane.candidateFilters.includeSpellIDs
            debuffCandidates, debuffCandidateSignature = A3._AddTargetDotAutoBlacklist(
                debuffCandidates, debuffCandidateSignature,
                type(customContainers) == "table" and customContainers[4] or nil, tracked)
        end
        local portraitShape = frameSpec and frameSpec.portrait and frameSpec.portrait.shape
        buff = CompileUnitLane(unit, laneLayout, layout, filtersRoot, "buff", buffCandidates, buffCandidateSignature, portraitShape, auras.shared)
        debuff = CompileUnitLane(unit, laneLayout, layout, filtersRoot, "debuff", debuffCandidates, debuffCandidateSignature, portraitShape, auras.shared)
        laneEffects = CompileUnitLaneEffects(unit, laneLayout, buff, debuff)
    end
    local spellIndicators = customEffects or legacyCustomDisplays
    local spellIndicatorsAssist, spellIndicatorsHostile
    spellIndicators, spellIndicatorsAssist, spellIndicatorsHostile =
        SpellIndicatorsRuntime.PartitionUnitRoot(spellIndicators)
    local laneEffectsAssist, laneEffectsHostile
    laneEffects, laneEffectsAssist, laneEffectsHostile =
        SpellIndicatorsRuntime.PartitionUnitRoot(laneEffects)
    local targetDotEffectsAssist, targetDotEffectsHostile
    targetDotEffects, targetDotEffectsAssist, targetDotEffectsHostile =
        SpellIndicatorsRuntime.PartitionUnitRoot(targetDotEffects)
    local hasNativeAuraWork = (buff and buff.enabled == true) or (debuff and debuff.enabled == true)
        or (dispelBorder and dispelBorder.enabled == true) or (purgeBorder and purgeBorder.enabled == true)
        or (dispelOverlay and dispelOverlay.enabled == true) or (dispelSymbol and dispelSymbol.enabled == true)
    if not hasNativeAuraWork and not hasCustomContainers
        and not customEffects and not targetDotEffects and not laneEffects and not legacyCustomDisplays then
        -- The Aura owner may deliberately stay enabled with every icon cap at
        -- 0 so Dispel can be turned on later.  That idle state must still
        -- compile to the empty config: no native container and no event owner.
        return EmptyUnitFrameConfig(unit)
    end
    local lanes = { buff = buff, debuff = debuff }
    if customLanes then
        for key, lane in pairs(customLanes) do lanes[key] = lane end
    end
    return {
        unit = unit,
        enabled = (buff and buff.enabled == true) or (debuff and debuff.enabled == true)
            or (dispelBorder and dispelBorder.enabled == true) or (dispelOverlay and dispelOverlay.enabled == true)
            or (purgeBorder and purgeBorder.enabled == true)
            or (dispelSymbol and dispelSymbol.enabled == true)
            or hasCustomContainers or (customEffects and customEffects.enabled == true)
            or (targetDotEffects and targetDotEffects.enabled == true) or (laneEffects and laneEffects.enabled == true)
            or (legacyCustomDisplays and legacyCustomDisplays.enabled == true),
        lanes = lanes,
        sensors = { dispelBorder = dispelBorder, purgeBorder = purgeBorder,
            dispelOverlay = dispelOverlay, dispelSymbol = dispelSymbol },
        spellIndicators = spellIndicators,
        spellIndicatorsAssist = spellIndicatorsAssist,
        spellIndicatorsHostile = spellIndicatorsHostile,
        laneEffects = laneEffects,
        laneEffectsAssist = laneEffectsAssist,
        laneEffectsHostile = laneEffectsHostile,
        targetDotEffects = targetDotEffects,
        targetDotEffectsAssist = targetDotEffectsAssist,
        targetDotEffectsHostile = targetDotEffectsHostile,
        group = false,
        _msufA3ConfigGen = A3._runtimeConfigGen or 1,
        _msufA3VisualGen = A3._nativeVisualGen or 0,
    }
end

function A3.ResolveUnitFrameConfig(unit, frameSpec)
    unit = NormalizeRuntimeUnit(unit)
    if not unit then return nil end
    local gen = A3._runtimeConfigGen or 1
    local visualGen = A3._nativeVisualGen or 0
    if frameSpec ~= nil then
        -- Frame-spec configs also consume UnitFrame border/overlay settings.
        -- Cache them on the compiled spec so runtime events do not re-walk DB
        -- and do not accidentally push ApplyConfig/AddAuraGroup into hot paths.
        local specSerial = (UF and UF.Config and UF.Config.serial) or 0
        local cached = frameSpec._msufA3UnitAuraConfigCache
        if cached
            and cached.unit == unit
            and cached.gen == gen
            and cached.visualGen == visualGen
            and cached.specSerial == specSerial
        then
            return cached.config
        end
        local cfg = BuildUnitFrameConfig(unit, frameSpec)
        frameSpec._msufA3UnitAuraConfigCache = {
            unit = unit,
            gen = gen,
            visualGen = visualGen,
            specSerial = specSerial,
            config = cfg,
        }
        return cfg
    end
    A3._runtimeConfigCache = A3._runtimeConfigCache or {}
    local cached = A3._runtimeConfigCache[unit]
    if cached and cached.gen == gen and cached.visualGen == visualGen then return cached.config end
    local cfg = BuildUnitFrameConfig(unit, nil)
    A3._runtimeConfigCache[unit] = { gen = gen, visualGen = visualGen, config = cfg }
    return cfg
end

--- Cold-path diagnostics for Assistant/support surfaces.  Blizzard owns the
--- native AuraSlot assignment and may keep its visibility secret, so this API
--- reports the effective configured owners without querying AuraButton state.
--- It creates no frame, event, timer, or OnUpdate.
function A3.GetUnitFrameEffectDiagnostics(unit, frame)
    unit = NormalizeRuntimeUnit(unit or (frame and frame.MSUFUnitKey))
    if not unit then return nil end

    frame = frame
        or (A3._runtimeFrames and A3._runtimeFrames[unit])
        or (UF and UF.GetFrame and UF.GetFrame(unit))
        or (UF and UF.frames and UF.frames[unit])
        or _G["MSUF_" .. unit]
    local root = frame and frame.Auras
    local appliedConfig = root and type(root._msufA3Config) == "table" and root._msufA3Config or nil
    local cfg = appliedConfig or A3.ResolveUnitFrameConfig(unit, frame and frame.MSUFSpec)
    local installed = root ~= nil and root._msufA3Applied == true and appliedConfig == cfg

    local auras = EnsureDB()
    local _, effectiveShared = EffectiveUnitTables(auras, unit)
    local localShared = effectiveShared
    local laneEffectRoots = cfg and {
        cfg.laneEffects, cfg.laneEffectsAssist, cfg.laneEffectsHostile,
    } or nil

    local function CopyColor(color)
        color = type(color) == "table" and color or nil
        return {
            tonumber(color and color[1]) or 0.69,
            tonumber(color and color[2]) or 0.50,
            tonumber(color and color[3]) or 0.88,
            tonumber(color and color[4]) or 0.80,
        }
    end

    local function FindLaneSlot(kind)
        if not laneEffectRoots then return nil end
        local itemKey = "uflane_effect:" .. kind
        for rootIndex = 1, 3 do
            local laneRoot = laneEffectRoots[rootIndex]
            local laneSlots = laneRoot and laneRoot.enabled == true
                and type(laneRoot.slots) == "table" and laneRoot.slots or nil
            for i = 1, #(laneSlots or {}) do
                local slot = laneSlots[i]
                if type(slot) == "table" and slot.itemKey == itemKey then return slot end
            end
        end
        return nil
    end

    local function LaneSnapshot(kind)
        local prefix = kind == "buff" and "buff" or "debuff"
        local keyPrefix = prefix .. "FrameEffect"
        local slot = FindLaneSlot(kind)
        local effect = slot and type(slot.frameEffect) == "table" and slot.frameEffect or nil
        local configuredType = tostring(ReadRaw(effectiveShared, nil, keyPrefix .. "Type") or "none"):lower()
        local color = effect and effect.color or ReadRaw(effectiveShared, nil, keyPrefix .. "Color")
        local function FieldSource(suffix)
            return localShared and localShared[keyPrefix .. suffix] ~= nil and "unit" or "default"
        end
        return {
            ownerKind = "lane",
            lane = kind,
            display = kind == "buff" and "Buffs" or "Debuffs",
            configuredType = configuredType,
            renderedType = effect and tostring(effect.type or configuredType):lower() or nil,
            armed = slot ~= nil,
            installed = installed and slot ~= nil,
            visibility = "native-opaque",
            color = CopyColor(color),
            priority = tonumber(effect and effect.priority)
                or ReadNumber(effectiveShared, nil, keyPrefix .. "Priority", 5, 1, 10),
            thickness = tonumber(effect and effect.thickness)
                or ReadNumber(effectiveShared, nil, keyPrefix .. "Thickness", 2, 1, 16),
            layer = tonumber(effect and effect.layer)
                or ReadNumber(effectiveShared, nil, keyPrefix .. "Layer", 0, 0, 30),
            strata = tostring((effect and effect.strata)
                or ReadRaw(effectiveShared, nil, keyPrefix .. "Strata") or "AUTO"),
            nativeFilter = slot and slot.nativeFilter or nil,
            candidateFilterSignature = slot and slot.candidateFilterSignature or nil,
            source = FieldSource("Type"),
            colorSource = FieldSource("Color"),
            thicknessSource = FieldSource("Thickness"),
            prioritySource = FieldSource("Priority"),
            layerSource = FieldSource("Layer"),
            strataSource = FieldSource("Strata"),
        }
    end

    local snapshot = {
        unit = unit,
        applied = installed,
        configSource = appliedConfig and "applied" or "resolved",
        visibility = "native-opaque",
        lanes = {
            buff = LaneSnapshot("buff"),
            debuff = LaneSnapshot("debuff"),
        },
        custom = {},
    }

    -- Custom Aura and Target-DoT Full-Frame effects share the same renderer.
    -- Expose their compiled owners too, while still leaving visibility opaque.
    for _, rootKey in ipairs({
        "spellIndicators", "spellIndicatorsAssist", "spellIndicatorsHostile",
        "targetDotEffects", "targetDotEffectsAssist", "targetDotEffectsHostile",
    }) do
        local effectRoot = cfg and cfg[rootKey]
        local slots = effectRoot and effectRoot.enabled == true and type(effectRoot.slots) == "table" and effectRoot.slots or nil
        for i = 1, #(slots or {}) do
            local slot = slots[i]
            local effect = type(slot) == "table" and type(slot.frameEffect) == "table" and slot.frameEffect or nil
            if effect and tostring(effect.type or "none"):lower() ~= "none" then
                snapshot.custom[#snapshot.custom + 1] = {
                    ownerKind = rootKey:find("targetDotEffects", 1, true) and "targetDots" or "custom",
                    itemKey = slot.itemKey,
                    display = slot.display,
                    configuredType = tostring(effect.type):lower(),
                    renderedType = tostring(effect.type):lower(),
                    armed = true,
                    installed = installed,
                    visibility = "native-opaque",
                    color = CopyColor(effect.color),
                    priority = tonumber(effect.priority) or 5,
                    thickness = tonumber(effect.thickness) or 2,
                    layer = tonumber(effect.layer) or 0,
                    strata = tostring(effect.strata or "AUTO"),
                    nativeFilter = slot.nativeFilter,
                    candidateFilterSignature = slot.candidateFilterSignature,
                }
            end
        end
    end
    return snapshot
end

local function AppendSpellIndicatorItems(out, source)
    local items = type(source) == "table" and source.enabled == true and type(source.items) == "table" and source.items or nil
    if not items then return false end
    local did = false
    for i = 1, #items do
        if type(items[i]) == "table" and items[i].enabled ~= false then
            out[#out + 1] = items[i]
            did = true
        end
    end
    return did
end

local function AppendCornerCustomItems(out, corner)
    local slots = type(corner) == "table" and corner.enabled == true and type(corner.customSlots) == "table" and corner.customSlots or nil
    if not slots then return false end
    local did = false
    for i = 1, #slots do
        if type(slots[i]) == "table" and slots[i].enabled ~= false then
            out[#out + 1] = slots[i]
            did = true
        end
    end
    return did
end

local function BuildGroupSpellIndicatorSource(spellSource, cornerSource)
    local items = {}
    local hasSpells = AppendSpellIndicatorItems(items, spellSource)
    local hasCorners = AppendCornerCustomItems(items, cornerSource)
    if not hasSpells and not hasCorners then return nil end
    if hasCorners ~= true and type(spellSource) == "table" and spellSource.enabled == true then return spellSource end
    return {
        enabled = true,
        items = items,
        layer = type(spellSource) == "table" and spellSource.layer or (type(cornerSource) == "table" and cornerSource.layer or 9),
        iconZoom = type(spellSource) == "table" and spellSource.iconZoom or 100,
        strata = type(spellSource) == "table" and spellSource.strata or "AUTO",
    }
end

local function CompileGroupSpellIndicatorStyle(spellSource, groupKind, portraitShape)
    local raw = type(spellSource) == "table" and type(spellSource.style) == "table" and spellSource.style or nil
    raw = raw or {}
    local _, shared = EnsureDB()
    local iconShape, requestedIconShape = Shape.Resolve(Shape.SharedValue(shared, "buff"), portraitShape)
    return {
        -- Spell Icons use the shared Buff Appearance theme. Every other field
        -- below belongs only to this Group scope's Spell Icon Style.
        iconStyle = SharedIconStyle("buff"),
        iconShape = iconShape,
        requestedIconShape = requestedIconShape,
        alpha = Clamp01(raw.alpha, 1),
        showTooltip = raw.showTooltip ~= false,
        showCooldownText = raw.showCooldownText ~= false,
        showCooldownSwipe = raw.showCooldownSwipe ~= false,
        cooldownSwipeReverse = raw.cooldownSwipeReverse == true,
        cooldownSize = ClampNumber(raw.cooldownSize, 8, 6, 40),
        cooldownAnchor = raw.cooldownAnchor or "CENTER",
        cooldownX = ClampNumber(raw.cooldownX, 0, -2000, 2000),
        cooldownY = ClampNumber(raw.cooldownY, 0, -2000, 2000),
        cooldownDecimalSeconds = ClampNumber(raw.cooldownDecimalSeconds, 3, 0, 30),
        showDurationBar = raw.showDurationBar == true,
        durationBarHeight = ClampNumber(raw.durationBarHeight, 2, 1, 16),
        durationBarDisplay = NormalizeDurationBarDisplay(raw.durationBarDisplay, "BAR_ONLY"),
        durationBarPosition = NormalizeDurationBarPosition(raw.durationBarPosition, "BOTTOM"),
        durationBarDirection = NormalizeDurationBarDirection(raw.durationBarDirection, "REMAINING"),
        showStacks = raw.showStacks ~= false,
        stackSize = ClampNumber(raw.stackSize, 10, 6, 40),
        stackAnchor = raw.stackAnchor or "BOTTOMRIGHT",
        stackX = ClampNumber(raw.stackX, 0, -2000, 2000),
        stackY = ClampNumber(raw.stackY, 0, -2000, 2000),
    }
end

local function ResolveGroupFrameConfig(frame, unit)
    if not frame then return nil end
    unit = unit or frame.MSUFUnitKey
    local spec = frame.MSUFSpec
    local source = spec and (spec.auras or (spec.group and spec.group.auras))
    local spellSource = spec and spec.spellIndicators
    local cornerSource = spec and spec.cornerIndicators
    -- ReplaceTableContents keeps table identity across a visual-domain refresh,
    -- so identity alone cannot detect a symbol edit. The group config compiler
    -- stamps a signature when it reads the settings; this path only compares it,
    -- because it runs per frame per identity event.
    local symbolSignature = (spec and spec.dispelSymbol and spec.dispelSymbol.signature) or "-"
    local groupAssistGate = IsGroupFrame(frame) and frame._msufGFIsPreviewFrame ~= true
    -- The group kind doubles as the aura scope key for the shared icon style
    -- opt-out; party/raid/mythicraid can each be excluded independently.
    local groupKind = frame._msufGFKind
    local gen = A3._runtimeConfigGen or 1
    local visualGen = A3._nativeVisualGen or 0
    local cached = frame._msufA3NativeGroupConfig
    if cached and frame._msufA3NativeGroupSpec == spec
        and frame._msufA3NativeGroupSource == source and frame._msufA3NativeGroupSpellSource == spellSource
        and frame._msufA3NativeGroupCornerSource == cornerSource and frame._msufA3NativeGroupUnit == unit
        and frame._msufA3NativeGroupSymbolSignature == symbolSignature
        and frame._msufA3NativeGroupGen == gen and frame._msufA3NativeGroupVisualGen == visualGen
        and cached.groupAssistGate == groupAssistGate then
        return cached
    end
    -- Compiled group specs are immutable for their revision. Preview frames all
    -- use the same spec and the synthetic player unit, so compiling aura lanes,
    -- dispel sensors, and spell-indicator slots once per frame only duplicates
    -- tables without changing the result. Share that cold-path config on the spec;
    -- live frames with distinct unit tokens still receive distinct entries.
    local sharedCache = spec and spec._msufA3NativeGroupConfigCache
    local sharedKey = tostring(unit) .. "\031" .. tostring(groupKind) .. (groupAssistGate and "\031group" or "\031shared")
    local shared = sharedCache and sharedCache[sharedKey]
    if shared and shared.source == source and shared.spellSource == spellSource
        and shared.cornerSource == cornerSource and shared.symbolSignature == symbolSignature
        and shared.gen == gen and shared.visualGen == visualGen
    then
        cached = shared.config
        frame._msufA3NativeGroupSpec = spec
        frame._msufA3NativeGroupSource = source
        frame._msufA3NativeGroupSpellSource = spellSource
        frame._msufA3NativeGroupCornerSource = cornerSource
        frame._msufA3NativeGroupSymbolSignature = symbolSignature
        frame._msufA3NativeGroupUnit = unit
        frame._msufA3NativeGroupGen = gen
        frame._msufA3NativeGroupVisualGen = visualGen
        frame._msufA3NativeGroupConfig = cached
        return cached
    end
    local cfg = {
        unit = unit,
        enabled = false,
        lanes = {},
        sensors = {},
        group = true,
        groupAssistGate = groupAssistGate,
        _msufA3ConfigGen = gen,
        _msufA3VisualGen = visualGen,
        _msufA3Source = source,
    }
    local portraitShape = spec and spec.portrait and spec.portrait.shape
    local _, sharedAuraStyle = EnsureDB()
    local buff = type(source) == "table" and CompileGroupLane(unit, source, "buff", groupKind, portraitShape, sharedAuraStyle) or nil
    local combinedSpellSource = BuildGroupSpellIndicatorSource(spellSource, cornerSource)
    local spellIndicatorStyle = CompileGroupSpellIndicatorStyle(spellSource, groupKind, portraitShape)
    local spellIndicatorRoot = type(unit) == "string" and unit ~= ""
        and SpellIndicatorsRuntime.CompileSlots(unit, combinedSpellSource, spellIndicatorStyle) or nil
    cfg.spellIndicators = spellIndicatorRoot
    cfg.enabled = spellIndicatorRoot and spellIndicatorRoot.enabled == true or false
    if type(source) == "table" and type(unit) == "string" and unit ~= "" and source.enabled ~= false then
        local trackedBuff = CompileGroupLane(unit, source, "trackedBuff", groupKind, portraitShape, sharedAuraStyle)
        local debuff = CompileGroupLane(unit, source, "debuff", groupKind, portraitShape, sharedAuraStyle)
        local external = CompileGroupLane(unit, source, "external", groupKind, portraitShape, sharedAuraStyle)
        cfg.lanes.buff = buff
        cfg.lanes.trackedBuff = trackedBuff
        cfg.lanes.debuff = debuff
        cfg.lanes.external = external
        cfg.enabled = cfg.enabled == true
            or (buff and buff.enabled == true)
            or (trackedBuff and trackedBuff.enabled == true)
            or (debuff and debuff.enabled == true)
            or (external and external.enabled == true)

        local dispelBorder = CompileDispelSensor(unit, spec, true, "border")
        local dispelOverlay = CompileDispelSensor(unit, spec, true, "overlay")
        local dispelCorner = CompileDispelSensor(unit, spec, true, "corner")
        local dispelSymbol = CompileDispelSensor(unit, spec, true, "symbol")
        cfg.sensors.dispelBorder = dispelBorder
        cfg.sensors.dispelOverlay = dispelOverlay
        cfg.sensors.dispelCorner = dispelCorner
        cfg.sensors.dispelSymbol = dispelSymbol
        cfg.enabled = cfg.enabled == true
            or (dispelBorder and dispelBorder.enabled == true)
            or (dispelOverlay and dispelOverlay.enabled == true)
            or (dispelCorner and dispelCorner.enabled == true)
            or (dispelSymbol and dispelSymbol.enabled == true)
    end
    frame._msufA3NativeGroupSpec = spec
    frame._msufA3NativeGroupSource = source
    frame._msufA3NativeGroupSpellSource = spellSource
    frame._msufA3NativeGroupCornerSource = cornerSource
    frame._msufA3NativeGroupSymbolSignature = symbolSignature
    frame._msufA3NativeGroupUnit = unit
    frame._msufA3NativeGroupGen = gen
    frame._msufA3NativeGroupVisualGen = visualGen
    frame._msufA3NativeGroupConfig = cfg
    if spec then
        sharedCache = sharedCache or {}
        spec._msufA3NativeGroupConfigCache = sharedCache
        sharedCache[sharedKey] = {
            source = source,
            spellSource = spellSource,
            cornerSource = cornerSource,
            symbolSignature = symbolSignature,
            gen = gen,
            visualGen = visualGen,
            config = cfg,
        }
    end
    return cfg
end

local AURA_SORT_METHOD_FIELDS = {
    DEFAULT = "Default",
    BIG_DEFENSIVE = "BigDefensive",
    UNIT_FRAME_DEBUFF = "UnitFrameDebuff",
    IMPORTANT_FIRST = "ImportantOnly",
    EXPIRATION = "Expiration",
    EXPIRATION_ONLY = "ExpirationOnly",
    NAME = "Name",
    NAME_ONLY = "NameOnly",
    INSTANCE_ID = "AuraInstanceIDOnly",
}

local AURA_SORT_METHOD_FALLBACKS = {
    DEFAULT = 0,
    BIG_DEFENSIVE = 1,
    UNIT_FRAME_DEBUFF = 2,
    IMPORTANT_FIRST = 3,
    EXPIRATION = 4,
    EXPIRATION_ONLY = 5,
    NAME = 6,
    NAME_ONLY = 7,
    INSTANCE_ID = 8,
}

NormalizeAuraSortMethod = function(value)
    value = tostring(value or DEFAULT_SHARED.sortMethod):upper():gsub("[%s%-]+", "_")
    if value == "BIGDEFENSIVE" then value = "BIG_DEFENSIVE" end
    if value == "UNITFRAMEDEBUFF" then value = "UNIT_FRAME_DEBUFF" end
    if value == "IMPORTANTONLY" or value == "IMPORTANT" then value = "IMPORTANT_FIRST" end
    if value == "EXPIRATIONONLY" then value = "EXPIRATION_ONLY" end
    if value == "NAMEONLY" then value = "NAME_ONLY" end
    -- PTR 7: aura-instance-ID-only sort (stable arrival order, no payload reads).
    if value == "INSTANCEID" or value == "AURA_INSTANCE_ID" or value == "AURAINSTANCEID"
        or value == "INSTANCE_ID_ONLY" or value == "ARRIVAL" then
        value = "INSTANCE_ID"
    end
    return AURA_SORT_METHOD_FIELDS[value] and value or DEFAULT_SHARED.sortMethod
end

AuraSortEnums = function(lane)
    local methodKey = NormalizeAuraSortMethod(lane and lane.sortMethod)
    local methodEnums = _G.AuraContainerSortMethod
    local directionEnums = _G.AuraContainerSortDirection
    local method = methodEnums and methodEnums[AURA_SORT_METHOD_FIELDS[methodKey]] or AURA_SORT_METHOD_FALLBACKS[methodKey]
    local reverse = lane and lane.sortReverse == true
    local direction = directionEnums and directionEnums[reverse and "Reverse" or "Normal"] or (reverse and 1 or 0)
    return method, direction
end

AuraSortSignature = function(lane)
    return NormalizeAuraSortMethod(lane and lane.sortMethod) .. ":" .. (lane and lane.sortReverse == true and "R" or "N")
end

local function FrameAuraConfig(frame, unit)
    if IsGroupFrame(frame) then
        return ResolveGroupFrameConfig(frame, unit or frame.MSUFUnitKey)
    end
    return A3.ResolveUnitFrameConfig(unit or (frame and frame.MSUFUnitKey), frame and frame.MSUFSpec)
end

--- Cold-path preview bridge. Menu mocks and synthetic Edit Mode rows consume
--- the exact finalized runtime lanes/slots instead of reimplementing their
--- geometry. Preview entry points are combat-guarded by their owners; this
--- function only resolves/caches immutable configuration and creates no frame,
--- event, timer, or OnUpdate.
function A3.ResolveAuraPreviewConfig(frame, unit, frameSpec)
    if (_G.InCombatLockdown and _G.InCombatLockdown()) or _G.MSUF_InCombat == true then return nil end
    if frameSpec ~= nil and frame and frameSpec ~= frame.MSUFSpec and IsGroupFrame(frame) then
        local proxy = frame._msufA3AuraPreviewConfigProxy
        if not proxy then
            proxy = {}
            frame._msufA3AuraPreviewConfigProxy = proxy
        end
        proxy._msufIsGroupFrame = true
        proxy._msufGFIsPreviewFrame = true
        proxy._msufGFKind = frame._msufGFKind
        proxy.MSUFUnitKey = unit or frame.MSUFUnitKey
        proxy.MSUFSpec = frameSpec
        return ResolveGroupFrameConfig(proxy, proxy.MSUFUnitKey)
    end
    return FrameAuraConfig(frame, unit or (frame and frame.MSUFUnitKey))
end

function A3.BuildAuraLaneMetrics(configOrUnit, kind)
    local rawKind = tostring(kind or "buff"):lower()
    local customIndex = rawKind:match("^custom(%d)$")
    if customIndex then
        customIndex = math_min(4, math_max(1, tonumber(customIndex) or 1))
        kind = "custom" .. tostring(customIndex)
    else
        kind = (rawKind == "debuff" or rawKind == "debuffs") and "debuff" or "buff"
    end
    local cfg = type(configOrUnit) == "table" and configOrUnit or A3.ResolveUnitFrameConfig(configOrUnit)
    local lane = cfg and cfg.lanes and cfg.lanes[kind]
    if not lane then return nil end
    local debuffBorderMode = lane.showAuraSymbol == true and "SYMBOL"
        or lane.showAuraBorder == true and "BORDER" or "OFF"
    return {
        enabled = lane.enabled == true,
        num = lane.max,
        size = lane.size,
        spacing = lane.spacing,
        step = lane.step,
        perRow = lane.perRow,
        cols = lane.cols,
        rows = lane.rows,
        width = lane.width,
        height = lane.height,
        alpha = lane.alpha,
        iconZoom = lane.iconZoom,
        iconShape = lane.iconShape,
        requestedIconShape = lane.requestedIconShape,
        growth = lane.growthX,
        rowWrap = lane.growthY,
        growthX = lane.xSign,
        growthY = lane.ySign,
        xSign = lane.xSign,
        ySign = lane.ySign,
        verticalGrowth = lane.verticalGrowth == true,
        initialAnchor = lane.initialAnchor,
        x = lane.x,
        y = lane.y,
        anchor = lane.anchor,
        layer = lane.layer,
        padding = lane.padding,
        iconStyle = lane.iconStyle,
        -- Edit Mode is a preview renderer for this already-compiled runtime
        -- lane. Hand it the finalized Style values instead of making it
        -- reinterpret layout/layoutShared ownership a second time.
        textConfig = {
            showStackCount = lane.showStacks == true,
            showCooldownText = lane.showCooldownText == true,
            showCooldownSwipe = lane.showCooldownSwipe == true,
            cooldownSwipeReverse = lane.cooldownSwipeReverse == true,
            stackSize = lane.stackSize,
            stackX = lane.stackX,
            stackY = lane.stackY,
            cooldownSize = lane.cooldownSize,
            cooldownX = lane.cooldownX,
            cooldownY = lane.cooldownY,
            cooldownDecimalSeconds = lane.cooldownDecimalSeconds,
            showDurationBar = lane.showDurationBar == true,
            durationBarHeight = lane.durationBarHeight,
            durationBarDisplay = lane.durationBarDisplay,
            durationBarPosition = lane.durationBarPosition,
            durationBarDirection = lane.durationBarDirection,
            stackAnchor = lane.stackAnchor,
            cooldownAnchor = lane.cooldownAnchor,
            debuffBorderMode = debuffBorderMode,
        },
    }
end

--- Compiled shared Appearance style for preview surfaces.
function A3.IconStylePreviewForKind(kind)
    return SharedIconStyle(kind)
end

function A3.UnitFrameAuraEnabled(unit)
    local cfg = A3.ResolveUnitFrameConfig(unit)
    return cfg and cfg.enabled == true or false
end

local function ApplyFont(fs, size)
    if not fs then return end
    local readFont = _G.MSUF_GetGlobalFontSettings
    local gen = A3._nativeVisualGen or 0
    if A3._auraFontCacheGen ~= gen or A3._auraFontCacheReader ~= readFont then
        A3._auraFontCacheGen, A3._auraFontCacheReader = gen, readFont
        A3._auraFontPath, A3._auraFontFlags, A3._auraFontR, A3._auraFontG, A3._auraFontB, A3._auraFontShadow = nil, nil, nil, nil, nil, nil
        if type(readFont) == "function" then
            local unusedSize
            A3._auraFontPath, A3._auraFontFlags, A3._auraFontR, A3._auraFontG, A3._auraFontB, unusedSize, A3._auraFontShadow = readFont()
        end
    end
    local fontPath, fontFlags = A3._auraFontPath, A3._auraFontFlags
    local r, g, b, useShadow = A3._auraFontR, A3._auraFontG, A3._auraFontB, A3._auraFontShadow
    fontPath = fontPath or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    fontFlags = fontFlags or "OUTLINE"
    size = ClampNumber(size, 12, 6, 40)
    local general = _G.MSUF_DB and _G.MSUF_DB.general
    local applyResolved = _G.MSUF_ApplyResolvedFont
    if type(applyResolved) == "function" then
        applyResolved(fs, fontPath, size, fontFlags, general and general.fontKey)
    else
        -- Current clients require a valid FontAsset and may raise before a
        -- boolean result is returned. Keep the load-order fallback just as
        -- defensive as the central font service so stale SharedMedia paths can
        -- never escape through profile/runtime apply.
        local called, applied = pcall(fs.SetFont, fs, fontPath, size, fontFlags)
        local ready = called and applied ~= false
        local matches = _G.MSUF_FontApplicationMatches
        if ready and type(matches) == "function" then ready = matches(fs, fontPath, size) == true end
        if not ready then
            if fontPath ~= STANDARD_TEXT_FONT and STANDARD_TEXT_FONT then
                pcall(fs.SetFont, fs, STANDARD_TEXT_FONT, size, fontFlags)
            end
            if type(_G.MSUF_MarkFontApplyFailed) == "function" then _G.MSUF_MarkFontApplyFailed() end
        end
    end
    fs:SetTextColor(r or 1, g or 1, b or 1, 1)
    if useShadow then fs:SetShadowOffset(1, -1) else fs:SetShadowOffset(0, 0) end
end

-- Aura timer text format/color: a C-side NumericRuleFormatter plus a
-- DurationTextBinding template, both evaluated by Blizzard against the secret
-- aura duration object. MSUF only builds/caches them when style config
-- changes; there is no addon timer or OnUpdate work per aura.
local _durationFormatterCache

local function NumericRuleFormatRounding(name, fallback)
    local enum = _G.Enum and _G.Enum.NumericRuleFormatRounding
    if enum and enum[name] ~= nil then return enum[name] end
    local numericRuleFormatter = _G.NumericRuleFormatter and _G.NumericRuleFormatter.Rounding
    if numericRuleFormatter and numericRuleFormatter[name] ~= nil then return numericRuleFormatter[name] end
    return fallback
end

local function ColorEscape(r, g, b)
    return string.format("|cff%02x%02x%02x", Round(Clamp01(r, 1) * 255), Round(Clamp01(g, 1) * 255), Round(Clamp01(b, 1) * 255))
end

local function EscapeFormatLiteral(text)
    return tostring(text or ""):gsub("%%", "%%%%")
end

local function LocalizedTimeSuffix(key, fallback)
    local suffix
    if type(MSUF.Translate) == "function" then
        suffix = MSUF.Translate(key)
        if suffix == key then suffix = nil end
    end
    if suffix == nil or suffix == "" then suffix = fallback end
    return tostring(suffix)
end

-- The binding template carries the render fallbacks the formatter cannot:
-- Blizzard's ApplyDurationText only forwards the secret aura duration and
-- disables the binding when it is zero, so without SetZeroDurationText /
-- SetExpiredText a recycled pool button keeps the previous aura's countdown on
-- permanent auras (flasks, food, raid buffs, poisons). The update interval
-- caps C-side text work at the finest rendered granularity.
local function BuildAuraDurationBinding(formatter, updateInterval)
    local durationUtil = _G.C_DurationUtil
    local createBinding = durationUtil and durationUtil.CreateDurationTextBinding
    if type(createBinding) ~= "function" then return nil end
    local binding = createBinding()
    if not binding then return nil end
    if not (type(binding.SetFormatter) == "function"
        and type(binding.SetZeroDurationText) == "function"
        and type(binding.SetExpiredText) == "function"
        and type(binding.SetUpdateInterval) == "function"
        and type(binding.SetEnabled) == "function")
    then
        return nil
    end
    binding:SetFormatter(formatter)
    binding:SetZeroDurationText("")
    binding:SetExpiredText("")
    binding:SetUpdateInterval(updateInterval)
    binding:SetEnabled(true)
    return binding
end

local function BuildAuraDurationStyle(lane)
    -- Compiled lanes are replaced on config/locale invalidation. Cache the
    -- resolved style record there so pool growth does not rebuild formatter
    -- and binding for every newly initialized AuraButton.
    local cached = type(lane) == "table" and lane._msufA3DurationStyle
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end

    local general = (_G.MSUF_DB and _G.MSUF_DB.general) or nil
    if not general then return nil end
    local buckets = general.aurasCooldownTextUseBuckets == true
    local decimalSec = ClampNumber(lane and lane.cooldownDecimalSeconds, DEFAULT_SHARED.cooldownDecimalSeconds, 0, 30)

    local stringUtil = _G.C_StringUtil
    local createFormatter = stringUtil and stringUtil.CreateNumericRuleFormatter
    if type(createFormatter) ~= "function" then
        if type(lane) == "table" then lane._msufA3DurationStyle = false end
        return nil
    end

    -- Safe color falls back to the configured global font color when the user has
    -- not picked one, matching the menu's Safe swatch behavior.
    local safe = general.aurasCooldownTextSafeColor
    local sr, sg, sb
    if type(safe) == "table" then
        sr, sg, sb = safe[1] or safe.r, safe[2] or safe.g, safe[3] or safe.b
    elseif type(_G.MSUF_GetConfiguredFontColor) == "function" then
        sr, sg, sb = _G.MSUF_GetConfiguredFontColor()
    end
    sr, sg, sb = Clamp01(sr, 1), Clamp01(sg, 1), Clamp01(sb, 1)

    local warn = general.aurasCooldownTextWarningColor
    local wr, wg, wb = 1, 0.85, 0.20
    if type(warn) == "table" then wr, wg, wb = warn[1] or warn.r or wr, warn[2] or warn.g or wg, warn[3] or warn.b or wb end

    local urgent = general.aurasCooldownTextUrgentColor
    local ur, ug, ub = 1, 0.55, 0.10
    if type(urgent) == "table" then ur, ug, ub = urgent[1] or urgent.r or ur, urgent[2] or urgent.g or ug, urgent[3] or urgent.b or ub end

    -- Three boundaries in seconds, ascending: Urgent < Warning < Safe. A breakpoint's
    -- threshold is the minimum input value it applies to; the highest threshold
    -- <= remaining seconds wins. Above the Safe boundary we emit no color escape so
    -- the text keeps its base font color (the fontstring's own SetTextColor).
    local urgentSec = ClampNumber(general.aurasCooldownTextUrgentSeconds, 5, 0, 600)
    local warningSec = ClampNumber(general.aurasCooldownTextWarningSeconds, 15, 0, 600)
    local safeSec = ClampNumber(general.aurasCooldownTextSafeSeconds, 60, 0, 600)
    if warningSec < urgentSec then warningSec = urgentSec end
    if safeSec < warningSec then safeSec = warningSec end

    local minuteSuffix = LocalizedTimeSuffix("MSUF_AURA_TIMER_MINUTE_SUFFIX", "M")
    local hourSuffix = LocalizedTimeSuffix("MSUF_AURA_TIMER_HOUR_SUFFIX", "H")
    local daySuffix = LocalizedTimeSuffix("MSUF_AURA_TIMER_DAY_SUFFIX", "D")
    local updateInterval = decimalSec > 0 and 0.1 or 0.25
    local sig = table_concat({
        "unit-suffix-binding", buckets and 1 or 0, decimalSec, minuteSuffix, hourSuffix, daySuffix,
        sr, sg, sb, wr, wg, wb, ur, ug, ub, urgentSec, warningSec, safeSec,
    }, "\030")
    _durationFormatterCache = _durationFormatterCache or {}
    local shared = _durationFormatterCache[sig]
    if shared then
        if type(lane) == "table" then lane._msufA3DurationStyle = shared end
        return shared
    end

    local roundingDown = NumericRuleFormatRounding("Down", 2)
    local thresholds, seen = {}, {}
    local function AddThreshold(value)
        value = ClampNumber(value, 0, 0, 600)
        if seen[value] then return end
        seen[value] = true
        thresholds[#thresholds + 1] = value
    end
    AddThreshold(0)
    if decimalSec > 0 then AddThreshold(decimalSec) end
    AddThreshold(60)
    if buckets then
        AddThreshold(urgentSec)
        AddThreshold(warningSec)
        AddThreshold(safeSec)
    end
    -- Unit promotion on Blizzard's own 1 + 1.5x max-interval curve
    -- (Blizzard_AuraContainerShared's DefaultAuraDurationFormatter): minutes
    -- run through "90M", hours through "36H", then days. Config thresholds cap
    -- at 600 s, so they can never collide with these.
    thresholds[#thresholds + 1] = 5401
    thresholds[#thresholds + 1] = 129601
    table_sort(thresholds)

    local function ColorPrefix(threshold)
        if not buckets then return "" end
        if safeSec > warningSec and threshold >= safeSec then return "" end
        if threshold >= warningSec then return ColorEscape(sr, sg, sb) end
        if threshold >= urgentSec then return ColorEscape(wr, wg, wb) end
        return ColorEscape(ur, ug, ub)
    end
    local function UnitBreakpoint(threshold, div, suffix, colorPrefix)
        local colorSuffix = colorPrefix ~= "" and "|r" or ""
        return {
            threshold = threshold,
            step = 1,
            rounding = roundingDown,
            min = 1,
            format = colorPrefix .. "%.0f" .. EscapeFormatLiteral(suffix) .. colorSuffix,
            components = {
                { div = div, step = 1, rounding = roundingDown },
            },
        }
    end
    local function BreakpointAt(threshold)
        -- Hour and day lanes sit far above every bucket boundary; they always
        -- render in the base font color.
        if threshold >= 129601 then return UnitBreakpoint(threshold, 86400, daySuffix, "") end
        if threshold >= 5401 then return UnitBreakpoint(threshold, 3600, hourSuffix, "") end
        local colorPrefix = ColorPrefix(threshold)
        if threshold >= 60 then return UnitBreakpoint(threshold, 60, minuteSuffix, colorPrefix) end
        local colorSuffix = colorPrefix ~= "" and "|r" or ""
        local decimalBreakpoint = threshold < decimalSec
        return {
            threshold = threshold,
            step = decimalBreakpoint and 0.1 or 1,
            rounding = roundingDown,
            -- Blizzard's native duration binding defaults missing minima to 1.
            -- Decimal aura timers must be allowed below one second.
            min = decimalBreakpoint and 0.1 or 1,
            format = colorPrefix .. (decimalBreakpoint and "%.1f" or "%.0f") .. colorSuffix,
        }
    end

    local formatter = createFormatter()
    for i = 1, #thresholds do
        formatter:AddBreakpoint(BreakpointAt(thresholds[i]))
    end

    local style = {
        formatter = formatter,
        binding = BuildAuraDurationBinding(formatter, updateInterval),
        updateInterval = updateInterval,
    }
    _durationFormatterCache[sig] = style
    if type(lane) == "table" then lane._msufA3DurationStyle = style end
    return style
end

-- Keep the native container backend in its own lexical factory. The compiler
-- and public orchestration below retain direct local aliases to the handful of
-- hot entry points they use, while the backend's implementation locals no
-- longer consume the main chunk's hard 200-local budget.
local NativeRuntime = (function()
local RefreshAppliedNativeRoot
local EnsureNativeAuraRefreshDriver
local ApplyLane
local RecreateGroupSlots

-- Blizzard securecopies native AuraButton options on every setter call, so
-- these cold-path tables are safe to reuse and avoid per-button Lua garbage.
-- Only the duration-text table is temporarily mutated for its formatter and
-- binding; the blank zero/expired fallbacks ride along statically for client
-- generations that read them as plain options.
local _durationTextOptions = { zeroDurationText = "", expiredText = "" }
local _durationBarOptions = {}
local _applicationCountOptions = {}
local _auraSymbolOptions = { showWhenHarmful = true, showWhenHelpful = false }
local RegisterNativeContainer
local ConfigureContainer
local SyncDispelSensorGeometry

local function PlaceStackText(fs, owner, lane)
    if not (fs and owner and lane) then return end
    fs:ClearAllPoints()
    local anchor = lane.stackAnchor or "TOPRIGHT"
    local x, y = lane.stackX or -1, lane.stackY or 1
    if anchor == "TOPLEFT" or anchor == "LEFT" then
        fs:SetPoint(anchor, owner, anchor, x, y)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV(anchor == "LEFT" and "MIDDLE" or "TOP")
    elseif anchor == "BOTTOMLEFT" then
        fs:SetPoint(anchor, owner, anchor, x, y)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("BOTTOM")
    elseif anchor == "BOTTOMRIGHT" then
        fs:SetPoint(anchor, owner, anchor, x, y)
        fs:SetJustifyH("RIGHT")
        fs:SetJustifyV("BOTTOM")
    elseif anchor == "CENTER" or anchor == "TOP" or anchor == "BOTTOM" then
        fs:SetPoint(anchor, owner, anchor, x, y)
        fs:SetJustifyH("CENTER")
        fs:SetJustifyV(anchor == "TOP" and "TOP" or (anchor == "BOTTOM" and "BOTTOM" or "MIDDLE"))
    elseif anchor == "RIGHT" then
        fs:SetPoint(anchor, owner, anchor, x, y)
        fs:SetJustifyH("RIGHT")
        fs:SetJustifyV("MIDDLE")
    else
        fs:SetPoint("TOPRIGHT", owner, "TOPRIGHT", x, y)
        fs:SetJustifyH("RIGHT")
        fs:SetJustifyV("TOP")
    end
end

local function PlaceCooldownText(fs, owner, lane)
    if not (fs and owner and lane) then return end
    fs:ClearAllPoints()
    local anchor = lane.cooldownAnchor or "CENTER"
    local x, y = lane.cooldownX or 0, lane.cooldownY or 0
    fs:SetPoint(anchor, owner, anchor, x, y)
    if anchor == "TOPLEFT" or anchor == "LEFT" or anchor == "BOTTOMLEFT" then
        fs:SetJustifyH("LEFT")
    elseif anchor == "TOPRIGHT" or anchor == "RIGHT" or anchor == "BOTTOMRIGHT" then
        fs:SetJustifyH("RIGHT")
    else
        fs:SetJustifyH("CENTER")
    end
    if anchor == "TOPLEFT" or anchor == "TOP" or anchor == "TOPRIGHT" then
        fs:SetJustifyV("TOP")
    elseif anchor == "BOTTOMLEFT" or anchor == "BOTTOM" or anchor == "BOTTOMRIGHT" then
        fs:SetJustifyV("BOTTOM")
    else
        fs:SetJustifyV("MIDDLE")
    end
end

local NATIVE_AURA_CONTAINER_METHODS = {
    "SetUnit",
    "SetEnabled",
    "AddAuraGroup",
    "SetAuraGroupFilterString",
    "SetAuraGroupLayout",
    "SetAuraGroupMaxFrameCount",
    "SetAuraGroupCandidateFilters",
    "SetAuraGroupSortMethod",
    "AddAuraSlot",
    "SetAuraSlotFilterString",
    "SetAuraSlotCandidateFilters",
    "SetAuraSlotSortMethod",
    "AddItemEnchantment",
    -- PTR 7 flow layout API (replaced SetAuraLayout{AnchorPoint,GrowthDirection,RowWidth}).
    "SetFlowLayoutAnchorPoint",
    "SetFlowLayoutGrowthDirection",
    "SetFlowLayoutMaximumLineSize",
}

local NATIVE_AURA_BUTTON_METHODS = {
    "SetIcon",
    "ClearIcon",
    "SetDurationCooldown",
    "ClearDurationCooldown",
    "SetDurationBar",
    "ClearDurationBar",
    "SetDurationText",
    "ClearDurationText",
    "SetApplicationCount",
    "ClearApplicationCount",
    -- PTR 7 names; the SetAuraBorder/SetAuraSymbol aliases are deprecated and
    -- flagged for removal after 12.1.
    "AddDispelTypeTexture",
    "ClearDispelTypeTextures",
    "SetDispelTypeText",
    "ClearDispelTypeText",
    "SetMouseClickEnabled",
    "SetMouseMotionEnabled",
    "SetCancelAuraButtons",
}

local function ValidateNativeAuraContainerContract(container)
    if not container then return false end
    for i = 1, #NATIVE_AURA_CONTAINER_METHODS do
        local methodName = NATIVE_AURA_CONTAINER_METHODS[i]
        if type(container[methodName]) ~= "function" then
            A3.nativeAuraRuntimeAvailable = false
            A3.nativeAuraRuntimeError = "native AuraContainer missing " .. methodName
            return false
        end
    end
    return true
end

local function ValidateNativeAuraButtonContract(button)
    if not button then
        A3.nativeAuraRuntimeAvailable = false
        A3.nativeAuraRuntimeError = "native AuraButton missing"
        error(A3.nativeAuraRuntimeError, 3)
    end
    for i = 1, #NATIVE_AURA_BUTTON_METHODS do
        local methodName = NATIVE_AURA_BUTTON_METHODS[i]
        if type(button[methodName]) ~= "function" then
            A3.nativeAuraRuntimeAvailable = false
            A3.nativeAuraRuntimeError = "native AuraButton missing " .. methodName
            error(A3.nativeAuraRuntimeError, 3)
        end
    end
    return true
end

local function ConfigureNativeAuraContainer(container, unit)
    container:SetUnit(unit)
    container:SetEnabled(true)
end

local function EnsureRoot(frame)
    if not frame then return nil end
    local root = frame.Auras
    if root and root._msufA3NativeRoot == true then return root end
    root = CreateFrame("Frame", nil, frame)
    root._msufA3NativeRoot = true
    root:SetAllPoints(frame)
    root:SetScript("OnShow", function(self)
        -- Child AuraContainers already run UpdateAllAuras from their secure
        -- OnShow; avoid a second forced full parse here.
        if RefreshAppliedNativeRoot then RefreshAppliedNativeRoot(self, false) end
        -- Hidden secure-header children register their native owners only now.
        -- Seed after registration so a newly visible group frame cannot spend
        -- one frame fail-open while waiting for an unrelated identity event.
        if type(A3._SeedGroupAuraAssistGate) == "function" then
            A3._SeedGroupAuraAssistGate(self:GetParent(), self.unit)
        end
        if type(A3._SeedGroupAuraPresenceGate) == "function" then
            A3._SeedGroupAuraPresenceGate(self:GetParent(), self.unit)
        end
    end)
    root:Hide()
    frame.Auras = root
    return root
end

local function ConfigGen(cfg)
    return cfg and cfg._msufA3ConfigGen or (A3._runtimeConfigGen or 1)
end

local function VisualGen(cfg)
    return cfg and cfg._msufA3VisualGen or (A3._nativeVisualGen or 0)
end

local function ReasonRequiresAuraApply(reason)
    if reason == nil then return true end
    if IDENTITY_AURA_REFRESH_REASONS[reason] == true then return true end
    if COLD_APPLY_REASONS[reason] == true then return true end
    reason = tostring(reason or "")
    return reason:find("^AURAS3_", 1, false) ~= nil
        or reason:find("^MSUF2_", 1, false) ~= nil
        or reason:find("^MSUF_ASSISTANT_", 1, false) ~= nil
end

local function RootAppliedConfigIsCurrent(root, frame, cfg, reason)
    if not (root and root._msufA3NativeRoot == true and root._msufA3Applied == true) then return false end
    if root.needFullUpdate == true then return false end
    if ReasonRequiresAuraApply(reason) and not (reason == nil and cfg and root._msufA3Config == cfg) then return false end
    if cfg and root._msufA3Config ~= cfg then return false end
    if root._msufA3ConfigGen ~= (cfg and ConfigGen(cfg) or (A3._runtimeConfigGen or 1)) then return false end
    if root._msufA3VisualGen ~= (cfg and VisualGen(cfg) or (A3._nativeVisualGen or 0)) then return false end
    if root._msufA3AppliedUnit ~= (cfg and cfg.unit or (frame and frame.MSUFUnitKey)) then return false end
    if root._msufA3FrameSpec ~= (frame and frame.MSUFSpec) then return false end
    return true
end

local function FrameAppliedConfigIsCurrent(frame, reason, cfg)
    if not frame then return false end
    if cfg == nil then cfg = FrameAuraConfig(frame, frame.MSUFUnitKey) end
    return RootAppliedConfigIsCurrent(frame.Auras, frame, cfg, reason)
end

LaneTrackingSignature = function(lane)
    -- initialAnchor, layer, and strata are tracking-level on purpose: the
    -- container is anchored once and born at its final level/strata as a child
    -- of the MSUF-owned host (it is sealed after AddAuraGroup), so growth,
    -- layer, or strata changes must recreate the container rather than mutate
    -- a live sealed one. Recreate is the only path PTR 7 guarantees.
    return tostring(lane.unit) .. "\030" .. tostring(lane.kind) .. "\030" .. tostring(lane.nativeFilter)
        .. "\030" .. tostring(lane.max) .. "\030" .. tostring(lane.candidateFilterSignature)
        .. "\030" .. tostring(lane.initialAnchor)
        .. "\030" .. tostring(lane.layer) .. "\030" .. tostring(lane.strata)
        .. "\030" .. tostring(lane.weaponEnchants)
end

LaneStructuralSignature = function(lane)
    -- PTR 5 applies access restrictions immediately after initializeFrame.
    -- Any option that changes a button must therefore create a fresh native
    -- container so all setup remains inside that callback.
    -- The public 12.1 group-filter setter reparses native assignments in place.
    -- Button visuals and item-enchantment slots still belong to container
    -- creation and remain structural.
    return tostring(lane.kind) .. "\030" .. tostring(lane.identityCandidateMode)
        .. "\030" .. tostring(LaneLayoutSignature(lane))
        .. "\030" .. tostring(lane.weaponEnchants)
        .. "\030" .. tostring(lane.customPriority)
        .. "\030" .. tostring(lane.customPrioritySignature)
        .. "\030" .. tostring(lane.customPriority and lane.candidateFilterSignature or nil)
end

LaneLayoutSignature = function(lane)
    return tostring(lane.size) .. "\030" .. tostring(lane.iconZoom) .. "\030" .. tostring(lane.spacing)
        .. "\030" .. tostring(lane.iconShape) .. "\030" .. tostring(lane.requestedIconShape)
        .. "\030" .. tostring(lane.buttonWidth) .. "\030" .. tostring(lane.buttonHeight)
        .. "\030" .. tostring(lane.step) .. "\030" .. tostring(lane.stepX) .. "\030" .. tostring(lane.stepY)
        .. "\030" .. tostring(lane.perRow)
        .. "\030" .. tostring(lane.cols) .. "\030" .. tostring(lane.rows)
        .. "\030" .. tostring(lane.width) .. "\030" .. tostring(lane.height)
        .. "\030" .. tostring(lane.anchor) .. "\030" .. tostring(lane.x)
        .. "\030" .. tostring(lane.y) .. "\030" .. tostring(lane.layer)
        .. "\030" .. tostring(lane.strata)
        .. "\030" .. tostring(lane.xSign) .. "\030" .. tostring(lane.ySign)
        .. "\030" .. tostring(lane.verticalGrowth) .. "\030" .. tostring(lane.initialAnchor)
        .. "\030" .. tostring(lane.showCooldownText) .. "\030" .. tostring(lane.showCooldownSwipe)
        .. "\030" .. tostring(lane.cooldownSwipeReverse) .. "\030" .. tostring(lane.cooldownSize)
        .. "\030" .. tostring(lane.cooldownAnchor) .. "\030" .. tostring(lane.cooldownX)
        .. "\030" .. tostring(lane.cooldownY) .. "\030" .. tostring(lane.cooldownDecimalSeconds)
        .. "\030" .. tostring(lane.showDurationBar) .. "\030" .. tostring(lane.durationBarHeight)
        .. "\030" .. tostring(lane.durationBarDisplay) .. "\030" .. tostring(lane.durationBarPosition)
        .. "\030" .. tostring(lane.durationBarDirection)
        .. "\030" .. tostring(lane.showStacks) .. "\030" .. tostring(lane.stackAnchor)
        .. "\030" .. tostring(lane.stackSize) .. "\030" .. tostring(lane.stackX)
        .. "\030" .. tostring(lane.stackY) .. "\030" .. tostring(lane.showTooltip)
        .. "\030" .. tostring(lane.auraTooltipAnchor)
        .. "\030" .. tostring(lane.showAuraBorder) .. "\030" .. tostring(lane.showAuraSymbol)
        .. "\030" .. tostring(lane.showStealableMarker) .. "\030" .. tostring(lane.stealableStyle)
        .. "\030" .. tostring(lane.pandemicEnabled) .. "\030" .. tostring(lane.pandemicVisualEnabled)
        .. "\030" .. tostring(lane.pandemicStyle)
        .. "\030" .. tostring(lane.pandemicColor and (lane.pandemicColor[1] or lane.pandemicColor.r))
        .. "\030" .. tostring(lane.pandemicColor and (lane.pandemicColor[2] or lane.pandemicColor.g))
        .. "\030" .. tostring(lane.pandemicColor and (lane.pandemicColor[3] or lane.pandemicColor.b))
        .. "\030" .. tostring(lane.pandemicThickness) .. "\030" .. tostring(lane.pandemicPadding)
        .. "\030" .. tostring(lane.pandemicBorderAlpha) .. "\030" .. tostring(lane.pandemicTintAlpha)
        .. "\030" .. tostring(lane.pandemicBlend)
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.type)
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.priority)
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.thickness)
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.layer)
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.tintAlpha)
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.strata)
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.color and lane.pandemicFrameEffect.color[1])
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.color and lane.pandemicFrameEffect.color[2])
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.color and lane.pandemicFrameEffect.color[3])
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.color and lane.pandemicFrameEffect.color[4])
        .. "\030" .. tostring(lane.alpha)
        .. "\030" .. tostring(lane.padding)
        .. "\030" .. tostring(lane.portraitPositionWhenDisabled)
        .. "\030" .. tostring(lane.portraitLevelOffset)
        .. "\030" .. tostring(lane.iconStyle and lane.iconStyle.signature)
        .. "\030" .. tostring(A3._nativeVisualGen or 0)
end

SensorStructuralSignature = function(sensor)
    return tostring(sensor.kind) .. "\030" .. tostring(sensor.max)
        .. "\030" .. tostring(sensor.filterCount) .. "\030" .. tostring(sensor.filterMax)
        .. "\030" .. tostring(SensorLayoutSignature(sensor))
end

SensorLayoutSignature = function(sensor)
    return tostring(sensor.visual) .. "\030" .. tostring(sensor.target)
        .. "\030" .. tostring(sensor.style) .. "\030" .. tostring(sensor.alpha)
        .. "\030" .. tostring(sensor.thickness) .. "\030" .. tostring(sensor.layer) .. "\030" .. tostring(sensor.strata)
        .. "\030" .. tostring(sensor.detail) .. "\030" .. tostring(sensor.candidateFilterSignature)
        .. "\030" .. tostring(sensor.r) .. "\030" .. tostring(sensor.g) .. "\030" .. tostring(sensor.b)
        .. "\030" .. tostring(sensor.size) .. "\030" .. tostring(sensor.slotSignature)
        .. "\030" .. tostring(sensor.mode) .. "\030" .. tostring(sensor.growth)
        .. "\030" .. tostring(sensor.spacing) .. "\030" .. tostring(sensor.anchor)
        .. "\030" .. tostring(sensor.x) .. "\030" .. tostring(sensor.y)
        .. "\030" .. tostring(sensor.trigger) .. "\030" .. tostring(A3._nativeVisualGen or 0)
end

local DISPEL_SENSOR_ORDER = { "dispelBorder", "purgeBorder", "dispelOverlay", "dispelCorner", "dispelSymbol" }
A3._normalAuraLaneOrder = {
    "buff", "trackedBuff", "debuff", "external",
    "custom1", "custom2", "custom3", "custom4", "defensivePortrait", "targetDotPortrait",
}
local NORMAL_LANE_ROOT_KEYS = {
    "Buffs", "TrackedBuffs", "Debuffs", "Externals",
    "CustomAuras1", "CustomAuras2", "CustomAuras3", "CustomAuras4", "DefensivePortrait", "TargetDotPortrait",
}
local EFFECT_ROOT_FIELDS = {
    "spellIndicators", "spellIndicatorsAssist", "spellIndicatorsHostile",
    "laneEffects", "laneEffectsAssist", "laneEffectsHostile",
    "targetDotEffects", "targetDotEffectsAssist", "targetDotEffectsHostile",
}
local EFFECT_ROOT_KEYS = {
    "SpellIndicators", "SpellIndicatorsAssist", "SpellIndicatorsHostile",
    "LaneEffects", "LaneEffectsAssist", "LaneEffectsHostile",
    "TargetDotEffects", "TargetDotEffectsAssist", "TargetDotEffectsHostile",
}

local function BuildDispelSensorRootConfig(sensors)
    if type(sensors) ~= "table" then return nil end
    local list, structuralParts, layoutParts, unit, maxCount, layer
    for i = 1, #DISPEL_SENSOR_ORDER do
        local sensor = sensors[DISPEL_SENSOR_ORDER[i]]
        if sensor and sensor.enabled == true then
            if not list then
                list, structuralParts, layoutParts = {}, {}, {}
                unit = sensor.unit
                maxCount = 0
                layer = 0
            end
            list[#list + 1] = sensor
            structuralParts[#structuralParts + 1] = sensor._msufA3StructuralSignature or SensorStructuralSignature(sensor)
            layoutParts[#layoutParts + 1] = sensor._msufA3LayoutSignature or SensorLayoutSignature(sensor)
            maxCount = maxCount + math_max(1, sensor.max or 1)
            layer = math_max(layer, sensor.layer or 0)
        end
    end
    if not list then return nil end
    return {
        sensor = true,
        sensorRoot = true,
        kind = "dispelSensors",
        rootKey = "DispelSensor",
        unit = unit,
        enabled = true,
        sensors = list,
        max = maxCount,
        layer = layer,
        _msufA3StructuralSignature = table_concat(structuralParts, "\029"),
        _msufA3LayoutSignature = table_concat(layoutParts, "\029"),
    }
end

local function GetDispelSensorRootConfig(cfg)
    if not cfg then return nil end
    local cached = cfg.sensorRoot
    if cached ~= nil then
        return cached ~= false and cached or nil
    end
    cached = BuildDispelSensorRootConfig(cfg.sensors)
    cfg.sensorRoot = cached or false
    return cached
end

local function LayoutButton(button, lane, index)
    local n = index - 1
    local perRow = math_max(lane.perRow or 1, 1)
    local major = n % perRow
    local minor = math_floor(n / perRow)
    local col, row
    if lane.verticalGrowth then
        col, row = 0, n
    else
        col, row = major, minor
    end
    local x = col * (lane.stepX or lane.step or lane.buttonWidth or lane.size or 1) * (lane.xSign or 1)
    local y = row * (lane.stepY or lane.step or lane.buttonHeight or lane.size or 1) * (lane.ySign or -1)
    button:ClearAllPoints()
    local parent = button:GetParent()
    button:SetPoint(lane.initialAnchor or "TOPLEFT", parent, lane.initialAnchor or "TOPLEFT", x, y)
    button:SetSize(lane.buttonWidth or lane.size, lane.buttonHeight or lane.size)
end

local function LayoutAuraBorder(button, border, lane, useNativeAtlas)
    local size = tonumber(lane and lane.size) or DEFAULT_SHARED.iconSize
    local width = tonumber(lane and (lane.buttonWidth or lane.size)) or DEFAULT_SHARED.iconSize
    local height = tonumber(lane and (lane.buttonHeight or lane.size)) or DEFAULT_SHARED.iconSize
    local shapedPad = math_max(1, math_floor((size / 24) + 0.5))
    local padX = useNativeAtlas == true and A3.NativeAuraDispelBorderPadding(width) or shapedPad
    local padY = useNativeAtlas == true and A3.NativeAuraDispelBorderPadding(height) or shapedPad
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", button, "TOPLEFT", -padX, padY)
    border:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", padX, -padY)
end

-- Shared icon style rendering. Both the border and the shadow are edge bands
-- straddling the icon rect, drawn as eight plain textures by
-- MSUF.BorderStyles -- no BackdropTemplate child frame, so the aura button
-- keeps its draw layers and cannot pick up frame protection from a child.
local ICON_SHADOW_TEXTURE = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames")
    .. "\\Media\\Borders\\msuf_aura_border_shadow.tga"

--- Soft drop shadow behind the icon. `shadowSize` is the visible extent in
--- pixels, so the band is twice that: its inner half hides behind the icon and
--- the whole falloff lands outside.
local function SetAuraShapeTexture(texture, shape, useBorder)
    local media = Shape.MEDIA[shape]
    if not (texture and media) then return false end
    if useBorder == true then
        texture:SetTexture(media.border)
    elseif media.maskAtlas and texture.SetAtlas then
        texture:SetAtlas(media.maskAtlas)
    else
        texture:SetTexture(media.swipe or media.mask)
    end
    if texture.SetDesaturated then texture:SetDesaturated(media.desaturate == true) end
    if texture.SetTexCoord then texture:SetTexCoord(0, 1, 0, 1) end
    return true
end

local function ApplyIconStyleShadow(button, style, size, shape)
    local pieces = button._msufA3StyleShadow
    local shaped = shape and shape ~= Shape.RECTANGLE
    local shapedShadow = button._msufA3ShapedStyleShadow
    if shaped then
        if pieces then MSUF.BorderStyles.Hide(pieces) end
        if not (style and style.shadowEnabled) then
            if shapedShadow then shapedShadow:Hide() end
            return
        end
        if not shapedShadow then
            shapedShadow = button:CreateTexture(nil, "BACKGROUND", nil, -7)
            button._msufA3ShapedStyleShadow = shapedShadow
        end
        if not SetAuraShapeTexture(shapedShadow, shape, false) then shapedShadow:Hide(); return end
        local extent = (style.shadowSize or 0) + (style.borderEnabled and style.borderThickness or 0)
        shapedShadow:ClearAllPoints()
        shapedShadow:SetPoint("TOPLEFT", button, "TOPLEFT", -extent, extent)
        shapedShadow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", extent, -extent)
        shapedShadow:SetVertexColor(style.shadowR, style.shadowG, style.shadowB, style.shadowA)
        shapedShadow:Show()
        return
    end
    if shapedShadow then shapedShadow:Hide() end
    if not (style and style.shadowEnabled) then
        if pieces then MSUF.BorderStyles.Hide(pieces) end
        return
    end
    local BorderStyles = MSUF.BorderStyles
    if not BorderStyles then return end
    if not pieces then
        pieces = BorderStyles.Create(button, "BACKGROUND", -7, ICON_SHADOW_TEXTURE)
        button._msufA3StyleShadow = pieces
    end
    -- The shadow starts outside the border ring when both are on, so a thick
    -- ring never eats the halo.
    local base = (style.borderEnabled and style.borderThickness or 0)
    local extent = style.shadowSize + base
    BorderStyles.Apply(pieces, button, extent * 2, size, size,
        style.shadowR, style.shadowG, style.shadowB, style.shadowA)
end

--- Largest inner band we allow, as a share of the icon. An "inner" style shades
--- the artwork itself, so an unclamped thickness would black the icon out.
--- 0.3 matches the reach of the classic Masque shadow skins, whose dark band
--- covers a little under a third of the icon.
local ICON_INNER_BAND_MAX = 0.3

--- Border ring. SOLID keeps the original single stretched quad (one texture,
--- pixel-crisp at any thickness); every other style is an edgeFile band.
---
--- Outer styles frame the icon: the band straddles its edge and draws behind
--- it at BORDER(-1). Inner styles (Shadow) shade the icon instead: the band
--- sits wholly inside and draws on top at ARTWORK(7), above the icon but still
--- below the OVERLAY dispel border.
local function ApplyIconStyleBorder(button, style, size, shape)
    local flat = button._msufA3StyleBorder
    local pieces = button._msufA3StyleBorderPieces
    local shaped = shape and shape ~= Shape.RECTANGLE
    local shapedBorders = button._msufA3ShapedStyleBorders
    if shaped then
        if flat then flat:Hide() end
        if pieces then MSUF.BorderStyles.Hide(pieces) end
        if not (style and style.borderEnabled) then
            for i = 1, #(shapedBorders or {}) do shapedBorders[i]:Hide() end
            return
        end
        shapedBorders = shapedBorders or {}
        button._msufA3ShapedStyleBorders = shapedBorders
        local media = Shape.MEDIA[shape]
        local inner = style.borderPlacement == "inner" and not (media and media.borderOuterOnly)
        local count = math_max(1, math_min(8, math_floor((style.borderThickness or 1) + 0.5)))
        for i = 1, count do
            local border = shapedBorders[i]
            if not border then
                border = button:CreateTexture(nil, inner and "ARTWORK" or "BORDER", nil, inner and 7 or -1)
                shapedBorders[i] = border
            elseif border.SetDrawLayer then
                border:SetDrawLayer(inner and "ARTWORK" or "BORDER", inner and 7 or -1)
            end
            if not SetAuraShapeTexture(border, shape, true) then border:Hide(); return end
            local inset = inner and (i - 1) or -i
            border:ClearAllPoints()
            border:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
            border:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
            border:SetVertexColor(style.borderR, style.borderG, style.borderB, style.borderA)
            border:Show()
        end
        for i = count + 1, #shapedBorders do shapedBorders[i]:Hide() end
        return
    end
    for i = 1, #(shapedBorders or {}) do shapedBorders[i]:Hide() end
    if not (style and style.borderEnabled) then
        if flat then flat:Hide() end
        if pieces then MSUF.BorderStyles.Hide(pieces) end
        return
    end
    local texture = style.borderTexture
    if texture and MSUF.BorderStyles then
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
            MSUF.BorderStyles.Hide(pieces)
            pieces = nil
        end
        if not pieces then
            pieces = MSUF.BorderStyles.Create(button, inner and "ARTWORK" or "BORDER", inner and 7 or -1, texture)
            button._msufA3StyleBorderPieces = pieces
            button._msufA3StyleBorderInner = inner
        else
            MSUF.BorderStyles.SetTexture(pieces, texture)
        end
        MSUF.BorderStyles.Apply(pieces, button, edge, size, size,
            style.borderR, style.borderG, style.borderB, style.borderA, inset)
        return
    end
    if pieces then MSUF.BorderStyles.Hide(pieces) end
    if not flat then
        flat = button:CreateTexture(nil, "BORDER", nil, -1)
        flat:SetTexture("Interface\\Buttons\\WHITE8X8")
        button._msufA3StyleBorder = flat
    end
    local inset = style.borderThickness
    flat:ClearAllPoints()
    flat:SetPoint("TOPLEFT", button, "TOPLEFT", -inset, inset)
    flat:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", inset, -inset)
    flat:SetVertexColor(style.borderR, style.borderG, style.borderB, style.borderA)
    flat:Show()
end

--- Stamps the shared icon style onto a preview dummy with the same renderer
--- real buttons use in initializeFrame, so edit-mode lanes and menu mocks stay
--- pixel-identical to the runtime. Cold path only; passing nil (opted-out
--- scope, bar-only lane) hides any pieces a previous stamp created.
function A3.ApplyIconStylePreview(button, style, size, shape)
    if not button then return end
    shape = Shape.Normalize(shape)
    ApplyIconStyleShadow(button, style, size, shape)
    ApplyIconStyleBorder(button, style, size, shape)
end

function A3.ApplyAuraDispelPreview(border, icon, size, mode, shape, dispelType, useOverride)
    shape = Shape.Normalize(shape)
    dispelType = DS.defaultColors[dispelType] and dispelType or A3.GetDispelColorPreviewType()
    if not (border and icon and mode ~= nil and mode ~= "OFF") then return false end
    local pad = math_max(1, math_floor(((tonumber(size) or 24) / 24) + 0.5))
    if shape == Shape.RECTANGLE then
        local atlas = (mode == "SYMBOL" and DS.rings or DS.borders)[dispelType]
        if not (atlas and border.SetAtlas) then return false end
        pad = A3.NativeAuraDispelBorderPadding(size)
        border:SetAtlas(atlas, _G.TextureKitConstants and _G.TextureKitConstants.IgnoreAtlasSize)
    else
        local path = A3.AuraShapeBorderPath(shape)
        if not path then return false end
        border:SetTexture(path)
        if border.SetTexCoord then border:SetTexCoord(0, 1, 0, 1) end
    end
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
    border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
    A3.SetDispelVertexColor(border, dispelType, useOverride, 1)
    border:Show()
    return true
end

local function LayoutDurationBar(button, bar, lane)
    if not (button and bar and lane) then return end
    local height = ClampNumber(lane.durationBarHeight, DEFAULT_SHARED.durationBarHeight, 1, math_max(1, lane.size or DEFAULT_SHARED.iconSize))
    local inset = math_max(1, math_floor(((lane.size or DEFAULT_SHARED.iconSize) / 32) + 0.5))
    bar:ClearAllPoints()
    bar:SetHeight(height)
    if lane.durationBarPosition == "TOP" then
        bar:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
        bar:SetPoint("TOPRIGHT", button, "TOPRIGHT", -inset, -inset)
    else
        bar:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", inset, inset)
        bar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
    end
end

local function ResolveDurationBarOptions(lane)
    local enum = _G.Enum
    local interpolation = enum and enum.StatusBarInterpolation
    local direction = enum and enum.StatusBarTimerDirection
    if lane and lane.durationBarSmooth == true and interpolation and interpolation.ExponentialEaseOut ~= nil then
        _durationBarOptions.interpolation = interpolation.ExponentialEaseOut
    else
        _durationBarOptions.interpolation = interpolation and interpolation.Immediate or nil
    end
    if lane and lane.durationBarDirection == "ELAPSED" then
        _durationBarOptions.direction = direction and direction.ElapsedTime or nil
    else
        _durationBarOptions.direction = direction and direction.RemainingTime or nil
    end
    return _durationBarOptions
end

local function ApplyDurationBarColor(bar)
    if not bar then return end
    local r, g, b
    if type(A3.GetDurationBarColor) == "function" then
        r, g, b = A3.GetDurationBarColor()
    else
        local general = (_G.MSUF_DB and _G.MSUF_DB.general) or nil
        local color = general and general.aurasCooldownTextSafeColor
        if type(color) == "table" then
            r, g, b = color[1] or color.r, color[2] or color.g, color[3] or color.b
        elseif type(_G.MSUF_GetConfiguredFontColor) == "function" then
            r, g, b = _G.MSUF_GetConfiguredFontColor()
        end
    end
    if bar.SetStatusBarColor then bar:SetStatusBarColor(Clamp01(r, 1), Clamp01(g, 1), Clamp01(b, 1), 0.95) end
end

-- One CustomAuraContainer owns every compatible group-frame display for a unit:
-- fixed Spell/Dispel AuraSlots, every one-icon lane as another AuraSlot, and at
-- most one flowing AuraGroup. Live group frames are the only exception: their
-- identity-dependent helpful displays must fail closed while UnitCanAssist is
-- false, while ordinary token-only Buffs/Debuffs must remain visible. Keep
-- those two gate classes in separate native owners.
local function BuildGroupAuraOwner(cfg, assistMode, includeFixed, rootKey, spellRootOverride)
    local sensorRoot = includeFixed and assistMode == nil and GetDispelSensorRootConfig(cfg) or nil
    local spellRoot = spellRootOverride
    if spellRoot == nil and includeFixed and cfg.groupAssistGate ~= true then
        spellRoot = SpellIndicatorsRuntime.RootConfig(cfg)
    end
    local slotLanes, flowLane, ownedLaneKeys, signatureParts
    local lanes = cfg.lanes
    local order = A3._normalAuraLaneOrder
    for i = 1, #order do
        local lane = lanes and lanes[order[i]]
        local laneAssistMode = cfg.groupAssistGate == true and lane and lane.groupAccessGate == true
            and lane.identityCandidateMode or nil
        if lane and lane.enabled == true and laneAssistMode == assistMode then
            if lane.max == 1 then
                slotLanes = slotLanes or {}
                slotLanes[#slotLanes + 1] = lane
                ownedLaneKeys = ownedLaneKeys or {}
                ownedLaneKeys[lane.rootKey] = true
            elseif not flowLane then
                flowLane = lane
                ownedLaneKeys = ownedLaneKeys or {}
                ownedLaneKeys[lane.rootKey] = true
            end
        end
    end
    if not sensorRoot and not spellRoot and not slotLanes and not flowLane then return nil end

    signatureParts = {
        "identity:" .. tostring(assistMode or "neutral"),
        tostring(sensorRoot and sensorRoot._msufA3StructuralSignature or "-"),
        tostring(spellRoot and spellRoot._msufA3StructuralSignature or "-"),
        flowLane and ("flow:" .. tostring(flowLane.rootKey) .. ":"
            .. tostring(flowLane._msufA3StructuralSignature)) or "-",
    }
    if slotLanes then
        for i = 1, #slotLanes do
            local lane = slotLanes[i]
            signatureParts[#signatureParts + 1] = "slot:" .. tostring(lane.rootKey) .. ":"
                .. tostring(lane._msufA3StructuralSignature)
        end
    end
    return {
        kind = "groupAuraOwner",
        rootKey = rootKey,
        unit = (spellRoot or sensorRoot or flowLane or (slotLanes and slotLanes[1])).unit,
        sensorRoot = sensorRoot,
        spellIndicatorRoot = spellRoot,
        slotLanes = slotLanes,
        flowLane = flowLane,
        ownedLaneKeys = ownedLaneKeys,
        identityCandidateMode = assistMode,
        assistGated = assistMode ~= nil,
        _msufA3StructuralSignature = table_concat(signatureParts, "\028"),
    }
end

local function GetGroupSlotsRootConfig(cfg)
    if not (cfg and cfg.group == true) then return nil end
    local cached = cfg.groupSlotsRoot
    if cached ~= nil then return cached ~= false and cached or nil end

    local primary, secondary, tertiary
    if cfg.groupAssistGate == true then
        local spellRoot = SpellIndicatorsRuntime.RootConfig(cfg)
        local helpfulSpellRoot = SpellIndicatorsRuntime.PartitionRoot(
            spellRoot, "assist", "GroupSpellAssist")
        local hostileSpellRoot = SpellIndicatorsRuntime.PartitionRoot(
            spellRoot, "hostile", "GroupSpellHostile")
        local neutralSpellRoot = SpellIndicatorsRuntime.PartitionRoot(
            spellRoot, "neutral", "GroupSpellNeutral")
        primary = BuildGroupAuraOwner(cfg, nil, true, "GroupSlots", neutralSpellRoot)
        secondary = BuildGroupAuraOwner(cfg, "assist", false, "GroupAuraAssist", helpfulSpellRoot)
        tertiary = BuildGroupAuraOwner(cfg, "hostile", false, "GroupAuraHostile", hostileSpellRoot)
        if not primary then primary = BuildGroupAuraOwner(cfg, nil, true, "GroupSlots", false) end
        if not primary then
            primary = secondary or tertiary
            if primary == secondary then secondary = nil else tertiary = nil end
            if primary then primary.rootKey = "GroupSlots" end
        end
    else
        primary = BuildGroupAuraOwner(cfg, nil, true, "GroupSlots")
    end
    if not primary then
        cfg.groupSlotsRoot = false
        return nil
    end
    primary.secondaryRoot = secondary
    primary.tertiaryRoot = tertiary
    if secondary or tertiary then
        primary.allOwnedLaneKeys = {}
        for key in pairs(primary.ownedLaneKeys or {}) do primary.allOwnedLaneKeys[key] = true end
        for key in pairs(secondary and secondary.ownedLaneKeys or {}) do primary.allOwnedLaneKeys[key] = true end
        for key in pairs(tertiary and tertiary.ownedLaneKeys or {}) do primary.allOwnedLaneKeys[key] = true end
    else
        primary.allOwnedLaneKeys = primary.ownedLaneKeys
    end
    cfg.groupSlotsRoot = primary
    return primary
end

A3._GetGroupSlotsRootConfig = GetGroupSlotsRootConfig

local function EnsureAuraTextOverlay(button, lane)
    if not button then return nil end
    local visualOwner = button._msufA3SpellIndicatorVisualHost or button
    local overlay = button._msufA3TextOverlay
    if not overlay or (overlay.GetParent and overlay:GetParent() ~= visualOwner) then
        if overlay then overlay:Hide() end
        overlay = CreateFrame("Frame", nil, visualOwner)
        overlay._msufA3TextOverlay = true
        if overlay.EnableMouse then overlay:EnableMouse(false) end
        button._msufA3TextOverlay = overlay
    end
    -- Inbound duration regions must remain descendants of the native
    -- AuraButton (Blizzard_AuraContainerUtil validates this before applying
    -- secret aspects). For portrait mode the child frame is nevertheless
    -- levelled against the final portrait holder, so a later portrait frame
    -- level cannot strand text/swipe underneath its border. Retain the proven
    -- full-holder surface for the first portrait icon; appended icons use
    -- button-local surfaces so their swipes/text cannot overlap each other.
    local anchor = visualOwner
    local level = visualOwner.GetFrameLevel and (visualOwner:GetFrameLevel() or 0) or 0
    if lane and lane.portraitOverlay == true then
        overlay._msufA3PortraitDurationSurface = true
        local holder = button._msufA3ParentFrame
        if holder and holder.GetFrameLevel then
            level = math_max(level, holder:GetFrameLevel() or 0)
        end
        if button._msufA3LaneIndex == 1 then anchor = holder or button end
    end
    overlay:ClearAllPoints()
    overlay:SetAllPoints(anchor)
    if overlay.SetFrameLevel then
        overlay:SetFrameLevel(level + (FrameLayers.AURA_TEXT_LEVEL_OFFSET or 8))
    end
    overlay:Show()
    return overlay
end

function A3._AuraCooldownAnchorAndLevel(button, lane)
    local anchor = button and (button._msufA3SpellIndicatorVisualHost or button)
    local level = anchor and anchor.GetFrameLevel and (anchor:GetFrameLevel() or 0) or 0
    if lane and lane.portraitOverlay == true then
        local holder = button and button._msufA3ParentFrame
        if holder and holder.GetFrameLevel then
            level = math_max(level, holder:GetFrameLevel() or 0)
        end
        if button and button._msufA3LaneIndex == 1 then anchor = holder or button end
    end
    return anchor, level + (FrameLayers.AURA_COOLDOWN_LEVEL_OFFSET or 4)
end

-- Container-level layout application on the PTR 7 (12.1) flow layout API
-- (SetFlowLayout{AnchorPoint,GrowthDirection,MaximumLineSize}; the pre-PTR7
-- SetAuraLayout* setters no longer exist and their fallback has been removed).
-- AnchorUtil.FlowDirection values are the same +/-1 signs MSUF already
-- computes (Right/Up = 1, Left/Down = -1), so growth maps 1:1. Vertical lanes
-- pass a one-icon maximumLineSize, which is the native way to force a column:
-- every icon wraps to a new line and lines stack along the vertical growth
-- direction. Only ever called from the signature-guarded geometry cold path.
local function ApplyContainerFlowLayout(container, anchorPoint, xSign, ySign, lineSize, padding)
    local flowDir = _G.AnchorUtil and _G.AnchorUtil.FlowDirection
    container:SetFlowLayoutAnchorPoint(anchorPoint)
    container:SetFlowLayoutGrowthDirection(
        flowDir and (xSign >= 0 and flowDir.Right or flowDir.Left) or xSign,
        flowDir and (ySign >= 0 and flowDir.Up or flowDir.Down) or ySign)
    container:SetFlowLayoutMaximumLineSize(lineSize)
    if type(container.SetFlowLayoutPadding) == "function" then
        padding = padding or 0
        container:SetFlowLayoutPadding(padding, padding, padding, padding)
    end
end

local function SyncContainerGeometry(container, lane, parentFrame, forceGeometry, preserveAlpha)
    if not (container and lane) then return false end
    parentFrame = ResolveLaneParentFrame(parentFrame, lane)
    forceGeometry = forceGeometry == true or container._msufA3ForceManagedAuraGeometry == true
    parentFrame = parentFrame or container._msufA3ParentFrame or container:GetParent()
    container._msufA3NativeLaneConfig = lane
    container._msufA3ParentFrame = parentFrame
    local layoutHost = container._msufA3LayoutHost
    -- Geometry depends only on the lane's layout signature (size/spacing/anchor/
    -- offsets/level/strata/growth/visual gen) and the parent frame. Content-only
    -- refreshes -- swaps, identity, UNIT_AURA -- reuse the same lane, so skip the
    -- container resize + per-button re-layout when nothing geometric changed. A
    -- changed icon count or filter alters the tracking signature instead, which
    -- recreates the container, so a stale skip here is not possible. Everything
    -- below this guard is cold: the combat swap path pays exactly these
    -- compares and zero widget calls.
    local sig = lane._msufA3LayoutSignature
    if forceGeometry ~= true
        and sig ~= nil and container._msufA3GeomSig == sig and container._msufA3GeomParent == parentFrame then
        return true
    end
    container._msufA3GeomSig = sig
    container._msufA3GeomParent = parentFrame
    local resolvedStrata
    if parentFrame then
        resolvedStrata = ResolveFrameStrata(parentFrame, lane.strata)
        -- Strata is written on BOTH the host and the container: the intrinsic
        -- may carry an explicit strata of its own (explicit strata breaks
        -- parent inheritance entirely), so relying on host inheritance parked
        -- the whole chain on the wrong strata and every LOW element covered
        -- the icons regardless of frame levels. Container writes stick on
        -- PTR 7 (probe-verified) and land pre-seal on fresh containers.
        -- lane.strata is part of the layout signature, so this cold block
        -- re-runs exactly when it can change.
        if layoutHost then
            SyncFrameStrata(layoutHost, resolvedStrata)
        end
        SyncFrameStrata(container, resolvedStrata)
    end
    -- 12.1 moved anchor/growth/wrapping to container-level setters, and PTR 7
    -- renamed them again (SetAuraLayout* -> SetFlowLayout*). ApplyContainerFlowLayout
    -- feature-detects and applies whichever the live client exposes. Keeping this
    -- in the signature-guarded cold path stops Blizzard's ApplyLayout from
    -- restoring its TOPLEFT/right/down defaults after aura assignment churn.
    -- A one-icon native row/line is the secret-safe vertical layout primitive;
    -- horizontal lanes retain their configured full row width.
    local initialAnchor = lane.initialAnchor or "TOPLEFT"
    -- maximumLineSize measures CONTENT extent; the host box (lane.width/height)
    -- already includes 2*padding, so strip it back out for the line limit.
    ApplyContainerFlowLayout(container, initialAnchor,
        lane.xSign or 1, lane.ySign or -1,
        lane.verticalGrowth == true and (lane.buttonWidth or lane.size or 1)
            or ((lane.width or lane.size or 1) - 2 * (lane.padding or 0)),
        lane.padding)
    container.createdButtons = lane.max
    container:SetSize(lane.buttonWidth or lane.size or 1, lane.buttonHeight or lane.size or 1)
    if parentFrame and layoutHost then
        -- A portrait lane can be born before the Portrait element created its
        -- holder (parent then fell back to the unit frame). Snap the host over
        -- when the resolved parent changes; the geom-parent guard above
        -- re-runs this block exactly then.
        if lane.portraitOverlay == true and layoutHost.GetParent
            and layoutHost:GetParent() ~= parentFrame and layoutHost.SetParent then
            layoutHost:SetParent(parentFrame)
        end
        layoutHost:ClearAllPoints()
        layoutHost:SetPoint(lane.anchor, parentFrame, lane.anchor, lane.x, lane.y)
        layoutHost:SetSize(lane.width, lane.height)
        -- Anchor the sealed container to its host once; growth-direction
        -- changes alter the tracking signature and recreate the container, so
        -- this never needs to re-anchor a live (sealed) container.
        if container._msufA3HostAnchor ~= initialAnchor then
            container:ClearAllPoints()
            container:SetPoint(initialAnchor, layoutHost, initialAnchor, 0, 0)
            container._msufA3HostAnchor = initialAnchor
        end
    elseif parentFrame then
        container:ClearAllPoints()
        container:SetPoint(lane.anchor, parentFrame, lane.anchor, lane.x, lane.y)
    end
    if preserveAlpha ~= true then container:SetAlpha(lane.alpha or 1) end
    if parentFrame then
        local level = ManagedLaneFrameLevel(parentFrame, lane)
        if layoutHost and layoutHost.SetFrameLevel then
            layoutHost:SetFrameLevel(level)
        end
        -- For flowing AuraGroup lanes the CONTAINER is the layering authority:
        -- its level and strata are written on every geometry sync (writes stick
        -- on PTR 7; fresh containers take them pre-seal). Flow AuraButtons spawn
        -- at container level + 1 and follow; fixed AuraSlots instead use their
        -- own initializeFrame contract below because they share this owner.
        if container.SetFrameLevel then
            container:SetFrameLevel(level)
        end
    end
    container._msufA3ButtonFrameStrata = resolvedStrata
    if forceGeometry == true then container._msufA3ForceManagedAuraGeometry = nil end
    return true
end

local function PrepareAuraButton(button, lane, index)
    ValidateNativeAuraButtonContract(button)
    button._msufA3NativeButton = true
    button._msufA3LaneKind = lane.kind
    button._msufA3LaneIndex = index
    LayoutButton(button, lane, index)
    button:SetAlpha(1)
    -- Runtime AuraButtons are click-through except for the normal Player Buff
    -- lane, whose native RightButtonUp cancellation must remain usable. On
    -- 12.1 SetCancelAuraButtons only registers click tokens; it does not enable
    -- the separate click gate, so this explicit true is required. All of this
    -- runs only from Blizzard's frame-creation initializeFrame callback.
    local cancelablePlayerBuff = lane.unit == "player" and lane.kind == "buff"
    button:SetMouseClickEnabled(cancelablePlayerBuff)
    if cancelablePlayerBuff then
        button:SetCancelAuraButtons("RightButtonUp")
    end
    -- One native AuraSlot owns the secret assignment. Spell Indicator icon
    -- art lives on an independently levelled child, so its user Layer remains
    -- independent from a full-frame effect without a second aura assignment.
    local visualOwner = button
    if lane.kind == "spellIndicator" and lane.frameEffect and lane.visual ~= "none" then
        visualOwner = button._msufA3SpellIndicatorVisualHost
        if not visualOwner then
            visualOwner = CreateFrame("Frame", nil, button)
            visualOwner:EnableMouse(false)
            button._msufA3SpellIndicatorVisualHost = visualOwner
        end
        visualOwner:ClearAllPoints()
        visualOwner:SetAllPoints(button)
        if visualOwner.SetFrameLevel then
            visualOwner:SetFrameLevel(FrameLayers.ElementLevel and FrameLayers.ElementLevel(lane.layer, 9, 1)
                or ((button:GetFrameLevel() or 0) + 1))
        end
        visualOwner:Show()
    end
    -- Normal aura lanes retain the reference-addon model: their AuraButton
    -- inherits the container's strata and remains the sole visual owner. The
    -- Spell Indicator exception above is established only in initializeFrame;
    -- later secret-backed assignment never needs another hierarchy mutation.
    local spellIndicatorBar = lane.kind == "spellIndicator" and lane.visual == "bar"
    local barOnly = spellIndicatorBar
        or (lane.showDurationBar == true and lane.durationBarDisplay == "BAR_ONLY")
    local icon = button.Icon
    if barOnly then
        button:ClearIcon()
        if icon then
            icon:SetAlpha(0)
            icon:Hide()
        end
    else
        if not icon then
            -- The portrait itself is ARTWORK sublevel 0. Use the same sublevel
            -- contract as the proven cast-icon overlay; normal aura lanes keep
            -- their existing layer order.
            icon = visualOwner:CreateTexture(nil, "ARTWORK", nil, lane.portraitOverlay == true and 1 or 0)
            button.Icon = icon
        elseif lane.portraitOverlay == true and icon.SetDrawLayer then
            icon:SetDrawLayer("ARTWORK", 1)
        end
        icon:ClearAllPoints()
        icon:SetAllPoints(visualOwner)
        ApplyAuraIconZoom(icon, lane)
        icon:SetAlpha(1)
        icon:Show()
        button:SetIcon(icon)
        -- Preserve the original portrait mask on icon 1. Reusing that
        -- screen-space mask on appended icons would clip them to the portrait.
        if lane.portraitOverlay == true and index == 1 then
            local holder = button._msufA3ParentFrame
            local mask = holder and holder.mask
            if mask and icon.AddMaskTexture then icon:AddMaskTexture(mask) end
        end
    end

    -- Native cooldown swipe. Blizzard's ApplyDurationCooldown drives this from
    -- the (secret) aura duration C-side, so there is no addon timer cost.
    --
    -- Use CooldownFrameTemplate for the actual swipe art, then immediately opt
    -- out of countdown numbers, bling, and edge drawing. Created once per button
    -- and reused.
    if lane.showCooldownSwipe == true and not barOnly then
        local cooldownAnchor, cooldownLevel = A3._AuraCooldownAnchorAndLevel(button, lane)
        local cooldown = button._msufA3Cooldown
        if not cooldown then
            local cd = CreateFrame("Cooldown", nil, visualOwner, "CooldownFrameTemplate")
            if type(cd.SetDrawSwipe) == "function" then cd:SetDrawSwipe(true) end
            if type(cd.SetSwipeColor) == "function" then cd:SetSwipeColor(0, 0, 0, 0.58) end
            if type(cd.SetHideCountdownNumbers) == "function" then cd:SetHideCountdownNumbers(true) end
            if type(cd.SetDrawBling) == "function" then cd:SetDrawBling(false) end
            if type(cd.SetDrawEdge) == "function" then cd:SetDrawEdge(false) end
            button._msufA3Cooldown = cd
            cooldown = cd
        end
        if cooldown then
            cooldown:ClearAllPoints()
            cooldown:SetAllPoints(cooldownAnchor or button)
            if type(cooldown.SetDrawSwipe) == "function" then cooldown:SetDrawSwipe(true) end
            if type(cooldown.SetSwipeColor) == "function" then cooldown:SetSwipeColor(0, 0, 0, 0.58) end
            if type(cooldown.SetReverse) == "function" then cooldown:SetReverse(lane.cooldownSwipeReverse == true) end
            if type(cooldown.SetFrameLevel) == "function" then
                cooldown:SetFrameLevel(cooldownLevel)
            end
            cooldown:Show()
            button:SetDurationCooldown(cooldown)
        end
    else
        button:ClearDurationCooldown()
        if button._msufA3Cooldown then button._msufA3Cooldown:Hide() end
    end

    -- Masking is stamped once in AuraContainer's initializeFrame callback.
    -- Rectangular/default auras take the no-allocation branch and keep the
    -- exact pre-shape icon, swipe, and border renderer.
    local iconShape = not barOnly and (lane.iconShape or Shape.RECTANGLE) or Shape.RECTANGLE
    A3.ApplyAuraIconShape(visualOwner, iconShape, button._msufA3Cooldown, icon)

    if lane.showDurationBar == true then
        local bar = button._msufA3DurationBar
        if not bar then
            bar = CreateFrame("StatusBar", nil, visualOwner)
            bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(0)
            button._msufA3DurationBar = bar
        end
        if type(bar.SetFrameLevel) == "function" then
            bar:SetFrameLevel((visualOwner:GetFrameLevel() or 0)
                + (FrameLayers.AURA_DURATION_BAR_LEVEL_OFFSET or 2))
        end
        if spellIndicatorBar then
            -- Same proven path as the native Ebon Might bar: the StatusBar is
            -- a descendant of the CustomAuraButton and fills the complete
            -- configured Spell Indicator rectangle. Blizzard's
            -- ApplyDurationBar calls SetTimerDuration(auraDuration, ...) C-side.
            bar:ClearAllPoints()
            bar:SetAllPoints(visualOwner)
            local color = lane.color or {}
            bar:SetStatusBarColor(
                Clamp01(color[1], 0.69),
                Clamp01(color[2], 0.50),
                Clamp01(color[3], 0.88),
                Clamp01(color[4], 1))
        else
            LayoutDurationBar(visualOwner, bar, lane)
            ApplyDurationBarColor(bar)
        end
        if type(bar.SetReverseFill) == "function" then
            bar:SetReverseFill(spellIndicatorBar and lane.durationBarReverseFill == true or false)
        end
        -- Finish every script-side mutation before handing the StatusBar to
        -- Blizzard, which adds secret BarValue ownership during this call.
        bar:Show()
        button:SetDurationBar(bar, ResolveDurationBarOptions(lane))
    else
        button:ClearDurationBar()
        if button._msufA3DurationBar then button._msufA3DurationBar:Hide() end
    end

    local textOverlay
    if lane.showCooldownText == true or lane.showStacks == true then
        textOverlay = EnsureAuraTextOverlay(button, lane) or button
    end

    if lane.showCooldownText == true then
        local duration = button.Text or button.DurationText
        if not duration then
            duration = textOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            button.Text = duration
        elseif duration.GetParent and duration:GetParent() ~= textOverlay then
            -- PTR 7 seals configured display elements with
            -- ForbiddenAspect.ChangeParent; SetParent would hard-error inside
            -- initializeFrame and kill the lane. Retire the stray element and
            -- rebuild on the overlay instead.
            duration:Hide()
            duration = textOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            button.Text = duration
        end
        duration:Hide()
        ApplyFont(duration, lane.cooldownSize)
        if type(duration.SetDrawLayer) == "function" then
            duration:SetDrawLayer("OVERLAY", FrameLayers.AURA_COOLDOWN_TEXT_DRAW_SUBLEVEL or 7)
        end
        PlaceCooldownText(duration, textOverlay, lane)
        duration:Show()
        -- Hand Blizzard a C-side formatter plus a duration-text binding
        -- template so the text renders from the secret duration object with no
        -- addon cost. Long durations promote to hours/days on Blizzard's own
        -- curve, and the binding's blank zero/expired fallbacks keep recycled
        -- pool buttons from showing the previous aura's stale countdown on
        -- permanent auras (flasks, food, raid buffs).
        -- PTR 7 duration-text options: the formatter rides `textFormatter` and
        -- the template rides `binding`; the pre-PTR7 scalar keys stay set too
        -- so a client on the older contract reads the same style. Smooth
        -- C-side color curves stay OUT until DurationTextBindingColorOptions
        -- is source-verified: no pcall probing in initializeFrame, ever.
        local style = BuildAuraDurationStyle(lane)
        if style then
            _durationTextOptions.textFormatter = style.formatter
            _durationTextOptions.formatter = style.formatter
            _durationTextOptions.binding = style.binding
            _durationTextOptions.updateInterval = style.updateInterval
            button:SetDurationText(duration, _durationTextOptions)
            _durationTextOptions.textFormatter = nil
            _durationTextOptions.formatter = nil
            _durationTextOptions.binding = nil
            _durationTextOptions.updateInterval = nil
        else
            button:SetDurationText(duration, _durationTextOptions)
        end
    else
        button:ClearDurationText()
        local duration = button.Text or button.DurationText
        if duration then duration:Hide() end
    end

    if lane.showStacks == true then
        local count = button._msufA3ApplicationCount or button.Count or button.ApplicationCount
        if not count then
            count = textOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            button._msufA3ApplicationCount = count
        elseif count.GetParent and count:GetParent() ~= textOverlay then
            -- Same ChangeParent seal as the duration text above.
            count:Hide()
            count = textOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            button._msufA3ApplicationCount = count
        end
        button.Count = count
        count:Hide()
        ApplyFont(count, lane.stackSize)
        if type(count.SetDrawLayer) == "function" then
            count:SetDrawLayer("OVERLAY", FrameLayers.AURA_STACK_DRAW_SUBLEVEL or 6)
        end
        PlaceStackText(count, textOverlay, lane)
        count:Show()
        button:SetApplicationCount(count, _applicationCountOptions)
    else
        button:ClearApplicationCount()
        local count = button._msufA3ApplicationCount or button.Count or button.ApplicationCount
        if count then count:Hide() end
    end

    local auraBorderBound = false
    if lane.showAuraBorder == true and not barOnly then
        local border = button._msufA3AuraBorder or button.AuraBorder or button.Border
        if not border then
            border = visualOwner:CreateTexture(nil, "OVERLAY")
        end
        local shapedDispel = iconShape ~= Shape.RECTANGLE and A3.AuraShapeBorderPath(iconShape) or nil
        LayoutAuraBorder(visualOwner, border, lane, shapedDispel == nil)
        if shapedDispel then
            border:SetTexture(shapedDispel)
            if border.SetTexCoord then border:SetTexCoord(0, 1, 0, 1) end
        end
        button._msufA3AuraBorder = border
        button:ClearDispelTypeTextures()
        button:AddDispelTypeTexture(border, GetAuraBorderOptions(lane.showAuraSymbol, shapedDispel ~= nil))
        auraBorderBound = true
    else
        button:ClearDispelTypeTextures()
        if button._msufA3AuraBorder and button._msufA3AuraBorder.Hide then button._msufA3AuraBorder:Hide() end
    end

    -- PTR 8 stealable filtering stays entirely inside Blizzard's native
    -- AuraButton. The helpful button receives one display texture and no MSUF
    -- aura-data reads, events, polling, or per-frame work.
    if lane.showStealableMarker == true and not barOnly then
        local marker = button._msufA3StealableMarker
        if not marker then
            marker = visualOwner:CreateTexture(nil, "OVERLAY", nil, 5)
            button._msufA3StealableMarker = marker
        end
        marker:ClearAllPoints()
        if lane.stealableStyle == "ICON" then
            local markerSize = math_max(7, math_floor((lane.size or 24) * 0.42 + 0.5))
            marker:SetSize(markerSize, markerSize)
            marker:SetPoint("TOPLEFT", visualOwner, "TOPLEFT", 1, -1)
        else
            LayoutAuraBorder(visualOwner, marker, lane, true)
        end
        button:AddDispelTypeTexture(marker, A3.GetStealableTextureOptions(lane.stealableStyle))
    elseif button._msufA3StealableMarker then
        button._msufA3StealableMarker:Hide()
    end

    if lane.showAuraSymbol == true and auraBorderBound == true and not barOnly then
        local symbol = button._msufA3AuraSymbol or button.AuraSymbol or button.Symbol
        if not symbol then
            symbol = visualOwner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        end
        button._msufA3AuraSymbol = symbol
        button.Symbol = symbol
        symbol:ClearAllPoints()
        symbol:SetPoint("BOTTOMRIGHT", visualOwner, "BOTTOMRIGHT", -1, 1)
        symbol:SetJustifyH("RIGHT")
        symbol:SetJustifyV("BOTTOM")
        ApplyFont(symbol, math_min(lane.stackSize or DEFAULT_SHARED.stackTextSize, 14))
        button:SetDispelTypeText(symbol, _auraSymbolOptions)
    else
        button:ClearDispelTypeText()
        if button._msufA3AuraSymbol and button._msufA3AuraSymbol.Hide then button._msufA3AuraSymbol:Hide() end
    end

    -- Shared icon style: border ring + soft drop shadow. All regions are
    -- button-owned textures created once here (initializeFrame); layer stack:
    -- BACKGROUND(-7) shadow < BORDER(-1) ring < ARTWORK icon < OVERLAY dispel
    -- border, so the dispel-type border overdraws the static ring for typed
    -- debuffs. Scopes that opted out arrive with ICON_STYLE_OFF and take the
    -- hide branches below.
    local style
    if not barOnly then style = lane.iconStyle end
    local size = lane.size or 0
    ApplyIconStyleShadow(visualOwner, style, size, iconShape)
    ApplyIconStyleBorder(visualOwner, style, size, iconShape)

    -- AddPandemicRegion controls only the host's secret Shown aspect. Every
    -- child texture is static and was configured above/below once at creation.
    A3.BindPandemicRegion(button, lane)

    -- PTR 7 aura tooltips are native. Their lane switch is the complete
    -- visibility authority; global Unitframe visibility modes never override
    -- it. Only the compatible cursor placement and tooltip look are shared.
    local wantTooltip = lane.showTooltip ~= false
    button:SetMouseMotionEnabled(wantTooltip)
    if wantTooltip and type(button.SetTooltipAnchorPoint) == "function" then
        button:SetTooltipAnchorPoint(lane.auraTooltipAnchor or "ANCHOR_BOTTOMRIGHT")
        if type(button.SetHideTooltipInCombat) == "function" then
            button:SetHideTooltipInCombat(false)
        end
    end
    button._msufA3LaneLayoutSignature = lane._msufA3LayoutSignature
end

local function DispelSensorTarget(parentFrame, sensor)
    if sensor and sensor.visual == "overlay" and parentFrame then
        local hp = parentFrame.hpBar or parentFrame.Health or parentFrame.health
        if not hp then return nil end
        if sensor.target == "healthFill" then
            return hp.GetStatusBarTexture and hp:GetStatusBarTexture() or nil
        end
        return hp
    end
    return parentFrame
end

local function DispelSensorButtonTarget(parentFrame, sensor)
    if sensor and sensor.visual == "overlay" then
        return parentFrame and (parentFrame.hpBar or parentFrame.Health or parentFrame.health)
    end
    return parentFrame
end

local function DispelSensorFrameLevel(parentFrame, sensor, target)
    local parentLevel = (parentFrame and parentFrame.GetFrameLevel and parentFrame:GetFrameLevel()) or 0
    if sensor and sensor.visual == "overlay" then
        local targetParent = target and target.GetParent and target:GetParent()
        local targetLevel = target and target.GetFrameLevel and target:GetFrameLevel()
            or (targetParent and targetParent.GetFrameLevel and targetParent:GetFrameLevel())
            or parentLevel
        -- Geometry follows the health target, but AUTO/equal-strata ordering is
        -- based on the unit frame so Dispel deterministically wins the shared
        -- health-effect band above every Spell Indicator priority.
        if FrameLayers.ElementLevel then return FrameLayers.ElementLevel(sensor.layer, 0, 12) end
        return math_max(targetLevel + 1, parentLevel + DISPEL_OVERLAY_EFFECT_OFFSET + (sensor.layer or 0))
    end
    if sensor and (sensor.visual == "corner" or sensor.visual == "symbol") then
        if FrameLayers.ElementLevel then return FrameLayers.ElementLevel(sensor.layer, 14, 8) end
        return parentLevel + AuraIconBaseOffset(parentFrame) + (sensor.layer or 14)
    end
    if FrameLayers.ElementLevel then
        return FrameLayers.ElementLevel(sensor and sensor.layer, 14, sensor and sensor.detail or 8)
    end
    return parentLevel + (sensor and sensor.layer or 14)
end

--- Where symbol slot `index` sits relative to the unit frame. TOP mode has a
--- single slot at the configured offset; ALL mode steps each type along the
--- growth axis. Shared by the live button and the menu preview so a dragged
--- position can never mean two different things.
function DS.SlotOffset(sensor, index)
    local x = tonumber(sensor and sensor.x) or 0
    local y = tonumber(sensor and sensor.y) or 0
    local slot = sensor and sensor.slots and sensor.slots[index or 1]
    if slot then
        x = x + (tonumber(slot.x) or 0)
        y = y + (tonumber(slot.y) or 0)
    end
    return x, y
end

function DS.LayoutButton(button, sensor, parentFrame, index)
    local size = ClampNumber(sensor.size, 14, 4, 64)
    local anchor = sensor.anchor or "TOPRIGHT"
    local x, y = DS.SlotOffset(sensor, index)
    button:ClearAllPoints()
    button:SetSize(size, size)
    button:SetPoint(anchor, parentFrame, anchor, x, y)
    SyncFrameStrata(button, ResolveFrameStrata(parentFrame, sensor.strata))
    if button.SetFrameLevel then button:SetFrameLevel(DispelSensorFrameLevel(parentFrame, sensor, parentFrame)) end
    return true
end

local function LayoutDispelSensorButton(button, sensor, parentFrame, index)
    if not (button and sensor and parentFrame) then return false end
    if sensor.visual == "symbol" then
        -- Symbols are the one sensor visual with their own rect: they are a
        -- placed indicator, not a wash over the health bar.
        return DS.LayoutButton(button, sensor, parentFrame, index)
    end
    -- The AuraButton owns native assignment/visibility, but its stable geometry
    -- is the health-bar rectangle. The visible region is anchored separately to
    -- the current fill when requested, avoiding a whole-unit-frame fallback.
    local target = DispelSensorButtonTarget(parentFrame, sensor)
    if not target then return false end
    button:ClearAllPoints()
    -- Corner buttons cover the whole target like border/overlay: the single
    -- consolidated button hosts one region per corner, each anchored to the
    -- button rect (== target rect), so per-corner button geometry is gone.
    button:SetAllPoints(target)
    SyncFrameStrata(button, ResolveFrameStrata(parentFrame, sensor.strata))
    if button.SetFrameLevel then button:SetFrameLevel(DispelSensorFrameLevel(parentFrame, sensor, target)) end
    return true
end

local function LayoutDispelSensorOverlay(region, button, sensor, visualTarget)
    if not (region and button and sensor) then return false end
    local style = sensor.style or "FULL"
    local thickness = ClampNumber(sensor.thickness, 3, 1, 32)
    region:ClearAllPoints()
    if sensor.visual == "border" then
        local pad = math_min(2, math_max(0, math_floor((thickness * 0.5) + 0.5)))
        region:SetPoint("TOPLEFT", button, "TOPLEFT", -pad, pad)
        region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", pad, -pad)
        return true
    end
    local target = visualTarget
    if not target then return false end
    if style == "TOP" then
        region:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
        region:SetPoint("TOPRIGHT", target, "TOPRIGHT", 0, 0)
        region:SetHeight(thickness)
    elseif style == "BOTTOM" then
        region:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", 0, 0)
        region:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
        region:SetHeight(thickness)
    elseif style == "LEFT" then
        region:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
        region:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", 0, 0)
        region:SetWidth(thickness)
    elseif style == "RIGHT" then
        region:SetPoint("TOPRIGHT", target, "TOPRIGHT", 0, 0)
        region:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
        region:SetWidth(thickness)
    else
        region:SetAllPoints(target)
    end
    return true
end

-- MSUF supplies its own sensor art (WHITE8X8 fill / msuf edge texture) and only
-- wants Blizzard to apply the dispel-type color. On PTR 7 that is
-- PreserveAsset; Border/BorderWithIcon would replace the texture with the
-- stock dispel border atlas and reset its vertex color, destroying the
-- overlay/corner visuals.
local function GetSensorOverlayOptions()
    local styles = _G.Enum and _G.Enum.CustomAuraButtonDispelTypeTextureStyle
    AURA_SENSOR_OVERLAY_OPTIONS.style = styles and styles.PreserveAsset or nil
    return A3.ApplyHarmfulDispelColorOptions(AURA_SENSOR_OVERLAY_OPTIONS)
end

local function GetSensorBorderOptions()
    local styles = _G.Enum and _G.Enum.CustomAuraButtonDispelTypeTextureStyle
    AURA_SENSOR_BORDER_OPTIONS.style = styles and styles.PreserveAsset or nil
    return A3.ApplyHarmfulDispelColorOptions(AURA_SENSOR_BORDER_OPTIONS)
end

--- Symbol sensors let Blizzard pick the artwork, because only Blizzard may look
--- at the aura's dispel type. AddDispelTypeTexture securecopies the options
--- table at bind time, so reusing this one table across buttons is safe.
function DS.Options(style)
    local styles = _G.Enum and _G.Enum.CustomAuraButtonDispelTypeTextureStyle
    local assets = DS.AssetMap(style)
    if assets then
        DS.options.style = styles and styles.CustomAsset or nil
        DS.options.customDispelAssetMap = assets
    else
        DS.options.style = styles
            and (style == "BLIZZARD_RING" and styles.BorderWithIcon
                or style == "BLIZZARD_BORDER" and styles.Border
                or styles.Icon)
            or nil
        DS.options.customDispelAssetMap = nil
    end
    -- Custom MSUF symbols switch overridden types to neutral-alpha companions,
    -- so Blizzard's vertex color replaces their color instead of multiplying
    -- the already-colored art into near-black. Stock Blizzard atlases remain
    -- untouched because they have no tint-neutral asset counterpart.
    DS.options.customDispelColorMap = assets and A3.GetCustomDispelColorMap() or nil
    return DS.options
end

-- Rounded frames are optional and loaded outside Auras3. Keep weak references
-- to the native overlay textures on their owning unit frame so a later rounded
-- enable/apply can discover them without walking AuraButtons. Registration is
-- initialize/preview-only; aura events never cross this bridge.
local function RegisterRoundedDispelOverlayRegion(parentFrame, region)
    if not (parentFrame and region) then return end
    local key = IsGroupFrame(parentFrame) and "_msufGFDispelOverlays" or "_msufUFDispelOverlays"
    local regions = parentFrame[key]
    if type(regions) ~= "table" then
        regions = setmetatable({}, { __mode = "k" })
        parentFrame[key] = regions
    end
    regions[region] = true
    local callback = _G.MSUF_RoundedUF_OnDispelOverlayChanged
    if type(callback) == "function" then
        callback(parentFrame, region)
    end
end

local function PrepareDispelSensorButton(button, sensor, parentFrame, index)
    if not (button and sensor and parentFrame) then return false end
    ValidateNativeAuraButtonContract(button)
    button._msufA3NativeButton = true
    button._msufA3DispelSensor = sensor.visual
    if button.EnableMouse then button:EnableMouse(false) end
    button:SetMouseMotionEnabled(false)
    if not LayoutDispelSensorButton(button, sensor, parentFrame, index) then return false end
    -- Reset reused native buttons before a visual-specific alpha is applied.
    -- The overlay deliberately owns alpha on the button below: Blizzard's
    -- PreserveAsset path recolors its texture with SetVertexColor(..., 1) on
    -- every aura update, which otherwise erases the configured opacity.
    button:SetAlpha(1)

    local icon = button.Icon
    if not icon then
        icon = button:CreateTexture(nil, "ARTWORK")
        button.Icon = icon
    end
    icon:ClearAllPoints()
    icon:SetAllPoints(button)
    icon:SetAlpha(0)
    button:SetIcon(icon)
    button:ClearApplicationCount()
    button:ClearDurationCooldown()
    button:ClearDurationText()
    button:ClearDurationBar()
    button:ClearDispelTypeText()

    button:ClearDispelTypeTextures()
    if sensor.visual == "symbol" then
        -- One texture filling the button rect. Blizzard swaps its atlas/asset
        -- per dispel type and hides it when the slot holds no typed debuff, so
        -- MSUF never needs to know which type is up.
        local region = button._msufA3DispelSymbolRegion
        if not region then
            region = button:CreateTexture(nil, "OVERLAY")
            button._msufA3DispelSymbolRegion = region
        end
        region:ClearAllPoints()
        region:SetAllPoints(button)
        region:SetAlpha(Clamp01(sensor.alpha, 1))
        button:AddDispelTypeTexture(region, DS.Options(sensor.style))
        return true
    end
    if sensor.visual == "corner" then
        -- PTR 7 multiple dispel textures: the single consolidated corner
        -- button carries one colored region per corner slot. The button covers
        -- the target rect, so each region anchors to the button at its
        -- configured corner offset.
        local slots = sensor.slots
        if not (type(slots) == "table" and #slots > 0) then return false end
        local regions = button._msufA3DispelSensorRegions
        if not regions then
            regions = {}
            button._msufA3DispelSensorRegions = regions
        end
        local size = ClampNumber(sensor.size, 8, 1, 64)
        local alpha = Clamp01(sensor.alpha, 1)
        for i = 1, #slots do
            local slot = slots[i]
            local region = regions[i]
            if not region then
                region = button:CreateTexture(nil, "OVERLAY")
                regions[i] = region
            end
            region:ClearAllPoints()
            region:SetSize(size, size)
            region:SetPoint(slot.anchor or "TOPLEFT", button, slot.anchor or "TOPLEFT", slot.x or 0, slot.y or 0)
            region:SetTexture("Interface\\Buttons\\WHITE8X8")
            region:SetAlpha(alpha)
            button:AddDispelTypeTexture(region, GetSensorOverlayOptions())
        end
        for i = #slots + 1, #regions do regions[i]:Hide() end
        return true
    end
    local region = button._msufA3DispelSensorRegion
    if not region then
        region = button:CreateTexture(nil, "OVERLAY")
        button._msufA3DispelSensorRegion = region
    end
    local visualTarget = DispelSensorTarget(parentFrame, sensor)
    if not LayoutDispelSensorOverlay(region, button, sensor, visualTarget) then
        region:Hide()
        return false
    end
    if sensor.visual == "overlay" then
        region:SetTexture("Interface\\Buttons\\WHITE8X8")
        region:SetAlpha(1)
        button:SetAlpha(Clamp01(sensor.alpha, 0.35))
        button:AddDispelTypeTexture(region, GetSensorOverlayOptions())
        RegisterRoundedDispelOverlayRegion(parentFrame, region)
    elseif sensor.visual == "purge" then
        region:SetTexture(MSUF_AURA_SENSOR_EDGE_TEXTURE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        region:SetAlpha(1)
        button:AddDispelTypeTexture(region, A3.GetPurgeSensorTextureOptions(sensor))
    else
        region:SetTexture(MSUF_AURA_SENSOR_EDGE_TEXTURE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        region:SetAlpha(0.82)
        button:AddDispelTypeTexture(region, GetSensorBorderOptions())
    end
    return true
end

--- Dispel-overlay preview (menu-driven, cold path only).
---
--- The live overlay belongs to Blizzard: MSUF only hands a texture to
--- AddDispelTypeTexture above, and the native container owns both the button's
--- visibility and the dispel-type vertex color. Nothing can force that on
--- without a real dispellable debuff on the unit, so the preview has to be a
--- separate MSUF-owned frame.
---
--- It is laid out by the SAME two helpers as the live sensor button and fed the
--- same compiled sensor, so style, thickness, alpha, target rect, strata and
--- frame level cannot drift from the real thing. Only Show and the flat color
--- are ours -- a live tint is colored by the aura's dispel type, which has no
--- meaning when there is no aura.
A3._DISPEL_OVERLAY_PREVIEW_FIELD = "_msufA3DispelOverlayPreview"

A3._NormalizeDispelOverlayPreviewScope = function(scope)
    scope = tostring(scope or "shared"):lower()
    if scope == "" or scope == "all" or scope == "global" then return "shared" end
    if scope == "gf_party" then return "party" end
    if scope == "gf_raid" then return "raid" end
    if scope == "gf_mythicraid" then return "mythicraid" end
    return scope
end

--- Scope match mirrors the border test modes: "shared" paints every frame, a
--- group kind paints that kind, anything else matches a unit token.
A3._DispelOverlayPreviewApplies = function(frame)
    if not frame then return false end
    local wanted = A3._NormalizeDispelOverlayPreviewScope(_G.MSUF_DispelOverlayPreviewScope)
    if wanted == "shared" then return true end
    local groupKind = frame._msufGFKind
    if groupKind == nil then
        local spec = frame.MSUFSpec
        groupKind = spec and spec.groupKind or nil
    end
    if groupKind then
        if wanted == "raid" then return groupKind == "raid" or groupKind == "mythicraid" end
        return groupKind == wanted
    end
    return frame.MSUFUnitKey == wanted or frame.configKey == wanted
end

A3._HideDispelOverlayPreview = function(frame)
    local host = frame and frame[A3._DISPEL_OVERLAY_PREVIEW_FIELD]
    if host and host:IsShown() then host:Hide() end
    return false
end

--- Cold path only: reached from the menu toggle, from the aura apply, and from
--- the group preview build. Never from an event route.
A3._ApplyDispelOverlayPreview = function(frame)
    if _G.MSUF_DispelOverlayPreviewMode ~= true then return A3._HideDispelOverlayPreview(frame) end
    if not (frame and frame.MSUFSpec) then return A3._HideDispelOverlayPreview(frame) end
    if not A3._DispelOverlayPreviewApplies(frame) then return A3._HideDispelOverlayPreview(frame) end
    -- Compiling straight off the frame spec keeps this independent of the
    -- native aura container, so group preview rows past the first one (which
    -- deliberately own no container) still preview the overlay.
    local sensor = CompileDispelSensor(frame.MSUFUnitKey, frame.MSUFSpec, IsGroupFrame(frame), "overlay")
    if not (sensor and sensor.enabled == true) then return A3._HideDispelOverlayPreview(frame) end
    local host = frame[A3._DISPEL_OVERLAY_PREVIEW_FIELD]
    if not host then
        -- The preview can only be switched on out of combat, so first creation
        -- always lands there. A spec apply that arrives mid-combat re-stamps an
        -- existing host but never parents a fresh frame onto a secure header.
        if _G.InCombatLockdown and _G.InCombatLockdown() then return false end
        host = CreateFrame("Frame", nil, frame)
        host:SetMouseMotionEnabled(false)
        host.Region = host:CreateTexture(nil, "OVERLAY")
        frame[A3._DISPEL_OVERLAY_PREVIEW_FIELD] = host
    end
    if not LayoutDispelSensorButton(host, sensor, frame, 1) then
        return A3._HideDispelOverlayPreview(frame)
    end
    local region = host.Region
    if not LayoutDispelSensorOverlay(region, host, sensor, DispelSensorTarget(frame, sensor)) then
        return A3._HideDispelOverlayPreview(frame)
    end
    RegisterRoundedDispelOverlayRegion(frame, region)
    A3.SetDispelColorTexture(region, A3.GetDispelColorPreviewType(), true, 1)
    region:SetAlpha(Clamp01(sensor.alpha, 0.35))
    region:Show()
    host:Show()
    return true
end

A3._ForEachDispelOverlayPreviewFrame = function(fn)
    if UF and type(UF.ForEachFrame) == "function" then UF.ForEachFrame(fn) end
    local gf = MSUF and MSUF.GF
    if not gf then return end
    if type(gf.ForEachFrame) == "function" then gf.ForEachFrame(fn, true) end
    -- Group preview rows live outside GF.frameList; walk them explicitly so the
    -- menu preview covers the rows the user is actually looking at.
    local previews = gf._previewFrames
    if type(previews) ~= "table" then return end
    for _, frames in pairs(previews) do
        if type(frames) == "table" then
            for _, frame in pairs(frames) do
                if type(frame) == "table" then fn(frame) end
            end
        end
    end
end

A3.RefreshDispelOverlayPreview = function()
    A3._ForEachDispelOverlayPreviewFrame(A3._ApplyDispelOverlayPreview)
    return true
end

--- Menu-facing setter, mirroring the border test-mode contract: one flag plus
--- one scope, cleared by the menu when its page hides. Combat never turns a
--- preview on.
A3.SetDispelOverlayPreview = function(active, scope)
    active = active == true
    if active and _G.InCombatLockdown and _G.InCombatLockdown() then active = false end
    ExportPublic("MSUF_DispelOverlayPreviewMode", active)
    ExportPublic("MSUF_DispelOverlayPreviewScope",
        active and A3._NormalizeDispelOverlayPreviewScope(scope) or nil)
    A3.RefreshDispelOverlayPreview()
    return active
end

ExportPublic("MSUF_SetDispelOverlayPreview", A3.SetDispelOverlayPreview)
ExportPublic("MSUF_RefreshDispelOverlayPreview", A3.RefreshDispelOverlayPreview)
ExportPublic("MSUF_ApplyDispelOverlayPreviewToFrame", A3._ApplyDispelOverlayPreview)

--- Dispel-symbol preview (menu-driven, cold path only).
---
--- Same contract as the overlay preview above and for the same reason: the live
--- symbol is a native AuraButton texture whose visibility and artwork Blizzard
--- owns, so nothing short of a real debuff turns it on. The preview is an
--- MSUF-owned frame that borrows the live geometry helper
--- (DS.LayoutButton) and the same compiled sensor, so size, anchor,
--- offsets, growth, strata and frame level cannot drift. Only Show and the
--- stand-in artwork are ours -- and the artwork is read from the SAME per-type
--- atlas/asset tables the live options hand to Blizzard.
---
--- It is also the drag surface: the user positions the indicator here and the
--- menu writes the resulting offset back through A3.DispelSymbolPreviewMoveHandler.
A3._DISPEL_SYMBOL_PREVIEW_FIELD = "_msufA3DispelSymbolPreview"

--- Group frames are deliberately excluded: their symbol is previewed inside the
--- menu's group preview as its own "Dispel" layer, like every other group
--- element, so painting a second stand-in onto the live raid frames would be a
--- duplicate the user cannot turn off from that layer strip. Unit frames keep
--- the on-frame preview because their Dispel Symbol card lives on Global Style >
--- Bars, which hosts no frame preview of its own.
A3._DispelSymbolPreviewApplies = function(frame)
    if not frame then return false end
    if IsGroupFrame(frame) or frame._msufGFKind ~= nil then return false end
    local spec = frame.MSUFSpec
    if spec and (spec.scope == "group" or spec.groupKind ~= nil) then return false end
    local wanted = A3._NormalizeDispelOverlayPreviewScope(_G.MSUF_DispelSymbolPreviewScope)
    if wanted == "shared" then return true end
    return frame.MSUFUnitKey == wanted or frame.configKey == wanted
end

A3._HideDispelSymbolPreview = function(frame)
    local host = frame and frame[A3._DISPEL_SYMBOL_PREVIEW_FIELD]
    if host and host:IsShown() then host:Hide() end
    return false
end

--- Stand-in artwork for one dispel type, taken from the very tables the live
--- path passes to Blizzard so the preview cannot show art the runtime wouldn't.
function DS.PreviewArt(texture, style, dispelType)
    texture:SetTexCoord(0, 1, 0, 1)
    local assets = DS.AssetMap(style)
    if assets then
        local asset = assets[dispelType]
        texture:SetTexture(asset and asset.asset or nil)
        if A3.HasDispelTypeColorOverride(dispelType) then
            A3.SetDispelVertexColor(texture, dispelType, true, 1)
        else
            texture:SetVertexColor(1, 1, 1, 1)
        end
        return
    end
    local atlas = (style == "BLIZZARD_RING" and DS.rings
        or style == "BLIZZARD_BORDER" and DS.borders
        or DS.icons)[dispelType]
    if atlas and texture.SetAtlas then
        texture:SetAtlas(atlas, _G.TextureKitConstants and _G.TextureKitConstants.IgnoreAtlasSize)
    else
        texture:SetTexture(nil)
    end
    texture:SetVertexColor(1, 1, 1, 1)
end

--- Turn the host's current on-screen rect back into the offset pair that
--- reproduces it from `anchor`. Host and parent share a scale (host is parented
--- to the frame), so raw edge coordinates are directly comparable.
function DS.AnchorOffset(host, parent, anchor)
    local hl, hr, ht, hb = host:GetLeft(), host:GetRight(), host:GetTop(), host:GetBottom()
    local pl, pr, pt, pb = parent:GetLeft(), parent:GetRight(), parent:GetTop(), parent:GetBottom()
    if not (hl and hr and ht and hb and pl and pr and pt and pb) then return nil, nil end
    anchor = tostring(anchor or "TOPRIGHT")
    local x
    if anchor:find("LEFT", 1, true) then
        x = hl - pl
    elseif anchor:find("RIGHT", 1, true) then
        x = hr - pr
    else
        x = ((hl + hr) * 0.5) - ((pl + pr) * 0.5)
    end
    local y
    if anchor:find("TOP", 1, true) then
        y = ht - pt
    elseif anchor:find("BOTTOM", 1, true) then
        y = hb - pb
    else
        y = ((ht + hb) * 0.5) - ((pt + pb) * 0.5)
    end
    return Round(x), Round(y)
end

A3.DispelSymbolPreviewMoveHandler = nil

function DS.OnDragStart(host)
    if _G.InCombatLockdown and _G.InCombatLockdown() then return end
    host:StartMoving()
end

function DS.OnDragStop(host)
    host:StopMovingOrSizing()
    local frame = host._msufA3PreviewParent
    local sensor = host._msufA3PreviewSensor
    local handler = A3.DispelSymbolPreviewMoveHandler
    if not (frame and sensor) then return end
    local x, y = DS.AnchorOffset(host, frame, sensor.anchor)
    if x == nil then return end
    -- The dragged tile is slot `index`; the stored offset is the base, so take
    -- that slot's own step back out. Dragging any symbol therefore moves the
    -- whole set and keeps the growth spacing intact.
    local slot = sensor.slots and sensor.slots[host._msufA3PreviewSlotIndex or 1]
    if slot then
        x = x - (tonumber(slot.x) or 0)
        y = y - (tonumber(slot.y) or 0)
    end
    if type(handler) == "function" then
        handler(_G.MSUF_DispelSymbolPreviewScope, x, y, frame)
    end
    A3.RefreshDispelSymbolPreview()
end

function DS.PreviewTile(host, index)
    local tiles = host._msufA3PreviewTiles
    if not tiles then
        tiles = {}
        host._msufA3PreviewTiles = tiles
    end
    local tile = tiles[index]
    if not tile then
        tile = CreateFrame("Frame", nil, host)
        tile.Texture = tile:CreateTexture(nil, "OVERLAY")
        tile.Texture:SetAllPoints(tile)
        tiles[index] = tile
    end
    return tile
end

--- Cold path only: menu toggle, spec apply, group preview build.
A3._ApplyDispelSymbolPreview = function(frame)
    if _G.MSUF_DispelSymbolPreviewMode ~= true then return A3._HideDispelSymbolPreview(frame) end
    if not (frame and frame.MSUFSpec) then return A3._HideDispelSymbolPreview(frame) end
    if not A3._DispelSymbolPreviewApplies(frame) then return A3._HideDispelSymbolPreview(frame) end
    local sensor = CompileDispelSensor(frame.MSUFUnitKey, frame.MSUFSpec, IsGroupFrame(frame), "symbol")
    if not (sensor and sensor.enabled == true) then return A3._HideDispelSymbolPreview(frame) end
    local host = frame[A3._DISPEL_SYMBOL_PREVIEW_FIELD]
    if not host then
        -- Previews only switch on out of combat, so first creation always lands
        -- there. A spec apply arriving mid-combat re-stamps an existing host but
        -- never parents a fresh frame onto a secure header.
        if _G.InCombatLockdown and _G.InCombatLockdown() then return false end
        host = CreateFrame("Frame", nil, frame)
        host:SetClampedToScreen(false)
        host:SetMovable(true)
        host:EnableMouse(true)
        host:RegisterForDrag("LeftButton")
        host:SetScript("OnDragStart", DS.OnDragStart)
        host:SetScript("OnDragStop", DS.OnDragStop)
        frame[A3._DISPEL_SYMBOL_PREVIEW_FIELD] = host
    end
    host._msufA3PreviewParent = frame
    host._msufA3PreviewSensor = sensor
    -- The host IS the first symbol's rect, laid out by the live helper. Extra
    -- ALL-mode tiles hang off it at their compiled step, so what the user drags
    -- is exactly what the runtime will draw.
    host._msufA3PreviewSlotIndex = 1
    if not DS.LayoutButton(host, sensor, frame, 1) then
        return A3._HideDispelSymbolPreview(frame)
    end
    local style = sensor.style or "BLIZZARD"
    local alpha = Clamp01(sensor.alpha, 1)
    local size = ClampNumber(sensor.size, 14, 4, 64)
    local slots = sensor.slots
    local count = slots and #slots or 1
    -- Tiles hang off the host, which already sits at slot 1, so every tile is
    -- placed relative to that one origin.
    local baseX, baseY = DS.SlotOffset(sensor, 1)
    for i = 1, count do
        local tile = DS.PreviewTile(host, i)
        local slotX, slotY = DS.SlotOffset(sensor, i)
        tile:ClearAllPoints()
        tile:SetSize(size, size)
        tile:SetPoint("TOPLEFT", host, "TOPLEFT", slotX - baseX, slotY - baseY)
        tile:SetAlpha(alpha)
        DS.PreviewArt(tile.Texture, style,
            (slots and slots[i] and slots[i].dispelType) or "Magic")
        tile:Show()
    end
    local tiles = host._msufA3PreviewTiles
    if tiles then
        for i = count + 1, #tiles do tiles[i]:Hide() end
    end
    host:Show()
    return true
end

A3.RefreshDispelSymbolPreview = function()
    A3._ForEachDispelOverlayPreviewFrame(A3._ApplyDispelSymbolPreview)
    return true
end

--- Menu-facing setter, mirroring the overlay preview contract: one flag plus one
--- scope, cleared by the menu when its page hides. Combat never turns it on.
A3.SetDispelSymbolPreview = function(active, scope)
    active = active == true
    if active and _G.InCombatLockdown and _G.InCombatLockdown() then active = false end
    ExportPublic("MSUF_DispelSymbolPreviewMode", active)
    ExportPublic("MSUF_DispelSymbolPreviewScope",
        active and A3._NormalizeDispelOverlayPreviewScope(scope) or nil)
    A3.RefreshDispelSymbolPreview()
    return active
end

A3.SetDispelSymbolPreviewMoveHandler = function(handler)
    A3.DispelSymbolPreviewMoveHandler = type(handler) == "function" and handler or nil
    return true
end

ExportPublic("MSUF_SetDispelSymbolPreview", A3.SetDispelSymbolPreview)
ExportPublic("MSUF_RefreshDispelSymbolPreview", A3.RefreshDispelSymbolPreview)
ExportPublic("MSUF_ApplyDispelSymbolPreviewToFrame", A3._ApplyDispelSymbolPreview)
ExportPublic("MSUF_SetDispelSymbolPreviewMoveHandler", A3.SetDispelSymbolPreviewMoveHandler)

local function ManagedAuraKey(config)
    return "msuf_" .. tostring(config and config.kind or "auras")
end

local function BuildManagedAuraGroupOptions(container, lane)
    local nextIndex = 0
    local sortMethod, sortDirection = AuraSortEnums(lane)
    local _, candidateFilters = EffectiveLaneFilters(lane)
    return {
        maxFrameCount = lane.max,
        candidateFilters = candidateFilters,
        sortMethod = sortMethod,
        sortDirection = sortDirection,
        initializeFrame = function(button)
            nextIndex = nextIndex + 1
            button._msufA3ManagedAuraButton = true
            button._msufA3ParentFrame = container._msufA3ParentFrame
            -- No MSUF-side button bookkeeping: 12.1 exposes
            -- GetAuraGroupFrame/GetAuraGroupFrameCount for enumeration.
            PrepareAuraButton(button, lane, nextIndex)
            -- A mixed owner stays at alpha 1 so fixed slots retain their own
            -- opacity and group range can gate the owner. Carry flow opacity on
            -- its buttons instead of multiplying every sibling AuraSlot.
            if container._msufA3GroupSlotsRoot == true then button:SetAlpha(lane.alpha or 1) end
        end,
    }
end

local function ManagedAuraGroupLayoutOptions(lane)
    local size = lane.size or DEFAULT_SHARED.iconSize
    local spacing = lane.spacing or DEFAULT_SHARED.spacing
    return {
        -- Blizzard 12.1.0 validates these per-group field names in
        -- Blizzard_CustomAuraContainer.lua. frameWidth/frameHeight (old) and
        -- elementSpacingX/elementSpacingY (pre-PTR7) are ignored; PTR 7 reads
        -- elementWidth/elementHeight plus elementSpacing (X) and lineSpacing (Y).
        elementWidth = lane.buttonWidth or size,
        elementHeight = lane.buttonHeight or size,
        elementSpacing = spacing,
        lineSpacing = spacing,
    }
end

local function ApplyManagedAuraGroupLayout(container, groupKey, lane)
    container:SetAuraGroupLayout(groupKey, ManagedAuraGroupLayoutOptions(lane))
    A3.nativeAuraRuntimeLayoutError = nil
    return true
end

local function CreateNativeAuraContainer(root, parentOverride)
    ApplyAuraTooltipStyle()
    local container = CreateFrame("AuraContainer", nil, parentOverride or root, "CustomAuraContainerTemplate")
    if not container then
        A3.nativeAuraRuntimeAvailable = false
        A3.nativeAuraRuntimeError = "CustomAuraContainerTemplate is unavailable"
        return nil
    end
    if not ValidateNativeAuraContainerContract(container) then
        if container.Hide then container:Hide() end
        return nil
    end
    -- Event registrations on CustomAuraContainerTemplate are intrinsic and
    -- carry Blizzard's forbidden EventRegistrations aspect. Leave the static
    -- AURA_DATA_PROVIDER_SWITCH subscription entirely Blizzard-owned; addon
    -- calls to RegisterEvent/UnregisterEvent on this object taint execution.
    container._msufA3Root = root
    return container
end

local function PriorityAuraCandidateFilters(container, lane, spellID)
    local cache = container._msufA3PriorityCandidateFilters
    if not cache then
        cache = {}
        container._msufA3PriorityCandidateFilters = cache
    end
    local key = tonumber(spellID) or 0
    local filters = cache[key]
    if filters then return filters end
    filters = {}
    for name, value in pairs(type(lane.candidateFilters) == "table" and lane.candidateFilters or {}) do
        if name ~= "includeSpellIDs" then filters[name] = value end
    end
    local included = {}
    if key > 0 then
        if type(A3.AddAuraSpellIDAndAliases) == "function" then
            A3.AddAuraSpellIDAndAliases(included, key)
        else
            included[key] = true
        end
    end
    filters.includeSpellIDs = included
    cache[key] = filters
    return filters
end

local function PriorityAuraGroupKey(lane, index)
    return ManagedAuraKey(lane) .. "_priority_" .. tostring(index)
end

local function BuildManagedPriorityAuraGroupOptions(container, lane, index, spellID)
    local sortMethod, sortDirection = AuraSortEnums(lane)
    return {
        maxFrameCount = 1,
        candidateFilters = PriorityAuraCandidateFilters(container, lane, spellID),
        sortMethod = sortMethod,
        sortDirection = sortDirection,
        initializeFrame = function(button)
            button._msufA3ManagedAuraButton = true
            button._msufA3ParentFrame = container._msufA3ParentFrame
            container[index] = button
            PrepareAuraButton(button, lane, index)
        end,
    }
end

local function ManagedPriorityAuraGroupLayoutOptions(lane, index)
    local size = lane.size or DEFAULT_SHARED.iconSize
    local spacing = lane.spacing or DEFAULT_SHARED.spacing
    return {
        -- Each priority entry owns one native AuraGroup. Empty groups contribute
        -- no spacing, while non-empty groups are packed by Blizzard in ascending
        -- layoutIndex order. elementSpacing must stay zero here: the distance
        -- between these one-frame groups is owned by groupSpacing.
        elementWidth = lane.buttonWidth or size,
        elementHeight = lane.buttonHeight or size,
        elementSpacing = 0,
        lineSpacing = spacing,
        groupSpacing = spacing,
        groupLineSpacing = spacing,
        layoutIndex = index,
    }
end

local function CreateManagedPriorityNativeLane(container, lane, parentFrame)
    if not container then return nil end
    A3.nativeAuraRuntimeAvailable = true
    ConfigureContainer(container, lane, parentFrame)
    container._msufA3ManagedAuraGroups = true
    container._msufA3PriorityAuraGroups = true
    container._msufA3PriorityGroupKeys = {}
    ConfigureNativeAuraContainer(container, lane.unit)

    local priority = lane.customPrioritySpellIDs or {}
    local groupCount = math_min(lane.max or 0, #priority)
    for i = 1, groupCount do
        local groupKey = PriorityAuraGroupKey(lane, i)
        container._msufA3PriorityGroupKeys[i] = groupKey
        container:AddAuraGroup(groupKey, lane.nativeFilter,
            BuildManagedPriorityAuraGroupOptions(container, lane, i, priority[i]))
        container:SetAuraGroupLayout(groupKey, ManagedPriorityAuraGroupLayoutOptions(lane, i))
    end
    container.createdButtons = groupCount
    container._msufA3MaxFrameCount = groupCount
    if not RegisterNativeContainer(container) then
        if container.Hide then container:Hide() end
        return nil
    end
    container:Show()
    A3.nativeAuraRuntimeError = nil
    return container
end

local function CreateManagedNativeLane(container, lane, parentFrame)
    if not container then return nil end
    A3.nativeAuraRuntimeAvailable = true
    ConfigureContainer(container, lane, parentFrame)
    container._msufA3ManagedAuraGroups = true
    container._msufA3ManagedGroupKey = ManagedAuraKey(lane)
    container.createdButtons = lane.max or 0
    ConfigureNativeAuraContainer(container, lane.unit)

    local nativeFilter, _, candidateFilterSignature = EffectiveLaneFilters(lane)
    container:AddAuraGroup(container._msufA3ManagedGroupKey, nativeFilter, BuildManagedAuraGroupOptions(container, lane))
    container._msufA3FilterString = nativeFilter
    container._msufA3CandidateFilterSignature = candidateFilterSignature
    container._msufA3SortSignature = AuraSortSignature(lane)
    -- PTR 7 item enchantments: temporary weapon enchants render as native
    -- buttons inside the player buff flow. The frames are CustomAuraButtons,
    -- so the normal initializeFrame styling pipeline applies unchanged.
    -- weaponEnchants is part of the structural signature -> toggling recreates.
    if lane.weaponEnchants == true and type(container.AddItemEnchantment) == "function" then
        local slots = _G.AuraContainerItemEnchantmentSlot
        local enchantOptions = {
            initializeFrame = function(button)
                button._msufA3ManagedAuraButton = true
                button._msufA3ParentFrame = container._msufA3ParentFrame
                PrepareAuraButton(button, lane, 1)
            end,
        }
        container:AddItemEnchantment(slots and slots.MainHand or 0, enchantOptions)
        container:AddItemEnchantment(slots and slots.OffHand or 1, enchantOptions)
        if type(container.SetItemEnchantmentLayout) == "function" then
            local placement = _G.CustomAuraContainerItemEnchantmentPlacement
            container:SetItemEnchantmentLayout({
                placement = placement and placement.BeforeAuraGroups or 0,
                elementSpacing = lane.spacing or 0,
                lineSpacing = lane.spacing or 0,
            })
        end
    end
    if not ApplyManagedAuraGroupLayout(container, container._msufA3ManagedGroupKey, lane) then
        if container.Hide then container:Hide() end
        return nil
    end
    if not RegisterNativeContainer(container) then
        if container.Hide then container:Hide() end
        return nil
    end
    container:Show()
    A3.nativeAuraRuntimeError = nil
    return container
end

local function BuildManagedAuraSlotOptions(container, sensor, parentFrame, buttonIndex, sensorIndex)
    return {
        maxFrameCount = 1,
        initializeFrame = function(button)
            button._msufA3ManagedAuraButton = true
            container[buttonIndex] = button
            PrepareDispelSensorButton(button, sensor, parentFrame, sensorIndex or buttonIndex)
        end,
    }
end

local function GroupLaneSlotKey(lane)
    return ManagedAuraKey(lane)
end

local function BuildGroupLaneSlotOptions(container, lane, parentFrame, buttonIndex)
    local sortMethod, sortDirection = AuraSortEnums(lane)
    local _, candidateFilters = EffectiveLaneFilters(lane)
    return {
        candidateFilters = candidateFilters,
        sortMethod = sortMethod,
        sortDirection = sortDirection,
        initializeFrame = function(button)
            button._msufA3ManagedAuraButton = true
            button._msufA3ParentFrame = parentFrame
            container[buttonIndex] = button
            -- AuraSlots share one native container with Spell/Dispel slots and
            -- an optional flowing AuraGroup, so the container cannot represent
            -- several independently configured lane Layers. Give this button
            -- the same final level/strata it would receive in a standalone
            -- flowing lane while initializeFrame is still allowed to mutate it.
            -- The sealed update path deliberately never touches it again.
            if button.SetFrameLevel then
                button:SetFrameLevel(ManagedLaneFrameLevel(parentFrame, lane) + 1)
            end
            SyncFrameStrata(button, ResolveFrameStrata(parentFrame, lane.strata))
            PrepareAuraButton(button, lane, 1)
            -- One icon fills the old fixed-size lane host exactly, so anchoring
            -- that icon by the configured outer anchor preserves its position.
            button:ClearAllPoints()
            button:SetPoint(lane.anchor, parentFrame, lane.anchor, lane.x, lane.y)
            button:SetAlpha(lane.alpha or 1)
        end,
    }
end

local function UpdateAuraGroupEffectiveFilters(container, lane)
    if not (container and lane and container._msufA3ManagedGroupKey) then return false end
    local groupKey = container._msufA3ManagedGroupKey
    local nativeFilter, candidateFilters, candidateSignature = EffectiveLaneFilters(lane)
    local oldFilter = container._msufA3FilterString
    local oldCandidateSignature = container._msufA3CandidateFilterSignature
    local filterChanged = oldFilter ~= nativeFilter
    local candidatesChanged = oldCandidateSignature ~= candidateSignature
    if not filterChanged and not candidatesChanged then return false end

    -- Moving from BIG_DEFENSIVE to HELPFUL broadens the native pass. Install
    -- the exact-ID gate first; moving back narrows the native pass first. This
    -- keeps both halves of a target/focus identity transition fail-closed even
    -- though Blizzard refreshes after each setter.
    local broadening = filterChanged
        and tostring(oldFilter or ""):find("BIG_DEFENSIVE", 1, true) ~= nil
        and tostring(nativeFilter or ""):find("BIG_DEFENSIVE", 1, true) == nil
    if broadening and candidatesChanged then
        container:SetAuraGroupCandidateFilters(groupKey, candidateFilters)
        container._msufA3CandidateFilterSignature = candidateSignature
    end
    if filterChanged then
        container:SetAuraGroupFilterString(groupKey, nativeFilter)
        container._msufA3FilterString = nativeFilter
    end
    if candidatesChanged and not broadening then
        container:SetAuraGroupCandidateFilters(groupKey, candidateFilters)
        container._msufA3CandidateFilterSignature = candidateSignature
    end
    return true
end

local function UpdateAuraSlotEffectiveFilters(container, lane)
    if not (container and lane) then return false end
    local slotKey = GroupLaneSlotKey(lane)
    local filters = container._msufA3LaneSlotFilterStrings
    local candidates = container._msufA3LaneSlotCandidateSignatures
    local nativeFilter, candidateFilters, candidateSignature = EffectiveLaneFilters(lane)
    local oldFilter = filters[slotKey]
    local oldCandidateSignature = candidates[slotKey]
    local filterChanged = oldFilter ~= nativeFilter
    local candidatesChanged = oldCandidateSignature ~= candidateSignature
    if not filterChanged and not candidatesChanged then return false end
    local broadening = filterChanged
        and tostring(oldFilter or ""):find("BIG_DEFENSIVE", 1, true) ~= nil
        and tostring(nativeFilter or ""):find("BIG_DEFENSIVE", 1, true) == nil
    if broadening and candidatesChanged then
        container:SetAuraSlotCandidateFilters(slotKey, candidateFilters)
        candidates[slotKey] = candidateSignature
    end
    if filterChanged then
        container:SetAuraSlotFilterString(slotKey, nativeFilter)
        filters[slotKey] = nativeFilter
    end
    if candidatesChanged and not broadening then
        container:SetAuraSlotCandidateFilters(slotKey, candidateFilters)
        candidates[slotKey] = candidateSignature
    end
    return true
end

local function UpdateGroupLaneSlot(container, lane)
    if not (container and lane) then return false end
    local slotKey = GroupLaneSlotKey(lane)
    local sorts = container._msufA3LaneSlotSortSignatures
    UpdateAuraSlotEffectiveFilters(container, lane)
    local sortSignature = AuraSortSignature(lane)
    if sorts[slotKey] ~= sortSignature then
        local sortMethod, sortDirection = AuraSortEnums(lane)
        container:SetAuraSlotSortMethod(slotKey, sortMethod, sortDirection)
        sorts[slotKey] = sortSignature
    end
    return true
end

local function UpdateGroupFlowLane(container, lane)
    if not (container and lane and container._msufA3ManagedGroupKey) then return false end
    local groupKey = container._msufA3ManagedGroupKey
    local refresh = false
    UpdateAuraGroupEffectiveFilters(container, lane)
    if container._msufA3MaxFrameCount ~= lane.max then
        container:SetAuraGroupMaxFrameCount(groupKey, lane.max)
        container._msufA3MaxFrameCount = lane.max
        refresh = true
    end
    local sortSignature = AuraSortSignature(lane)
    if container._msufA3SortSignature ~= sortSignature then
        local sortMethod, sortDirection = AuraSortEnums(lane)
        container:SetAuraGroupSortMethod(groupKey, sortMethod, sortDirection)
        container._msufA3SortSignature = sortSignature
    end
    if refresh == true and A3._NativeContainerVisible(container)
        and type(container.UpdateAllAuras) == "function" then
        container:UpdateAllAuras()
    end
    container.createdButtons = (container._msufA3FixedButtonCount or 0) + (lane.max or 0)
    return true
end

local function CreateManagedDispelSensor(container, sensor, parentFrame)
    if not container then return nil end
    A3.nativeAuraRuntimeAvailable = true
    container._msufA3ManagedAuraSlots = true
    container._msufA3NativeLane = sensor.kind
    container._msufA3NativeRegistered = nil
    container._msufA3NativeRegistrationPending = nil
    container.unit = sensor.unit
    container.createdButtons = sensor.max or 1
    container._msufA3SensorSlotFilterStrings = {}
    ConfigureNativeAuraContainer(container, sensor.unit)
    SyncDispelSensorGeometry(container, sensor, parentFrame)

    for i = 1, container.createdButtons do
        local slotKey = ManagedAuraKey(sensor) .. "_" .. tostring(i)
        container:AddAuraSlot(slotKey, sensor.nativeFilter, BuildManagedAuraSlotOptions(container, sensor, parentFrame, i, i))
        container._msufA3SensorSlotFilterStrings[slotKey] = sensor.nativeFilter
    end
    if not RegisterNativeContainer(container) then
        if container.Hide then container:Hide() end
        return nil
    end
    container:Show()
    A3.nativeAuraRuntimeError = nil
    return container
end

--- Symbol sensors in ALL mode narrow each slot to one dispel type; the PTR 8
--- Purge sensor narrows its single helpful slot to isStealable=true. Returns
--- the signature so the update path can skip a redundant native call.
function DS.SlotCandidateFilters(sensor, sensorIndex)
    local slot = sensor and sensor.visual == "symbol" and sensor.slots and sensor.slots[sensorIndex]
    if not slot then
        return sensor and sensor.candidateFilters, sensor and sensor.candidateFilterSignature
    end
    return slot.candidateFilters, slot.candidateFilterSignature
end

local function AddDispelSensorSlots(container, sensor, parentFrame, firstButtonIndex)
    local buttonIndex = firstButtonIndex or 0
    local count = math_max(1, sensor and sensor.max or 1)
    for sensorIndex = 1, count do
        buttonIndex = buttonIndex + 1
        local slotKey = ManagedAuraKey(sensor) .. "_" .. tostring(sensorIndex)
        container._msufA3SensorButtonSlots[buttonIndex] = {
            sensor = sensor,
            sensorIndex = sensorIndex,
            slotKey = slotKey,
        }
        container:AddAuraSlot(slotKey, sensor.nativeFilter, BuildManagedAuraSlotOptions(container, sensor, parentFrame, buttonIndex, sensorIndex))
        container._msufA3SensorSlotFilterStrings = container._msufA3SensorSlotFilterStrings or {}
        container._msufA3SensorSlotFilterStrings[slotKey] = sensor.nativeFilter
        local candidateFilters, candidateSignature = DS.SlotCandidateFilters(sensor, sensorIndex)
        if candidateFilters then
            container:SetAuraSlotCandidateFilters(slotKey, candidateFilters)
        end
        container._msufA3SensorSlotCandidateSignatures = container._msufA3SensorSlotCandidateSignatures or {}
        container._msufA3SensorSlotCandidateSignatures[slotKey] = candidateSignature
    end
    container._msufA3SensorButtonStart = container._msufA3SensorButtonStart or ((firstButtonIndex or 0) + 1)
    container._msufA3SensorButtonEnd = buttonIndex
    return buttonIndex
end

local function SyncDispelSensorRootGeometry(container, sensorRoot, parentFrame, forceGeometry)
    if not (container and sensorRoot and sensorRoot.sensorRoot == true) then return false end
    forceGeometry = forceGeometry == true or container._msufA3ForceManagedAuraGeometry == true
    parentFrame = parentFrame or container._msufA3ParentFrame or container:GetParent()
    if not parentFrame then return false end
    container._msufA3NativeLaneConfig = sensorRoot
    container._msufA3ParentFrame = parentFrame
    local sig = sensorRoot._msufA3LayoutSignature
    if forceGeometry ~= true
        and sig ~= nil
        and container._msufA3GeomSig == sig
        and container._msufA3GeomParent == parentFrame
    then
        return true
    end
    container._msufA3GeomSig = sig
    container._msufA3GeomParent = parentFrame
    local root = container:GetParent()
    if root then container:SetAllPoints(root) end
    if parentFrame and container.SetFrameLevel then
        -- The container owns native assignment only. Keep it at the health
        -- base so each AuraButton's explicit effect level remains authoritative
        -- and is not inherited above text/status overlays.
        container:SetFrameLevel((parentFrame:GetFrameLevel() or 0) + 1)
        SyncFrameStrata(container, ReadParentFrameStrata(parentFrame))
    end
    -- AuraButton setup is callback-only on PTR 5. Layout changes are part of
    -- the structural signature and replace this container instead.
    if forceGeometry == true then container._msufA3ForceManagedAuraGeometry = nil end
    return true
end

local function CreateManagedDispelSensorRoot(container, sensorRoot, parentFrame)
    if not container then return nil end
    A3.nativeAuraRuntimeAvailable = true
    container._msufA3ManagedAuraSlots = true
    container._msufA3NativeLane = sensorRoot.kind
    container._msufA3NativeRegistered = nil
    container._msufA3NativeRegistrationPending = nil
    container._msufA3SensorButtonSlots = {}
    container._msufA3SensorSlotFilterStrings = {}
    container.unit = sensorRoot.unit
    container.createdButtons = sensorRoot.max or 1
    ConfigureNativeAuraContainer(container, sensorRoot.unit)
    SyncDispelSensorRootGeometry(container, sensorRoot, parentFrame)

    local buttonIndex = 0
    local sensors = sensorRoot.sensors or {}
    for i = 1, #sensors do
        buttonIndex = AddDispelSensorSlots(container, sensors[i], parentFrame, buttonIndex)
    end
    container.createdButtons = buttonIndex
    if not RegisterNativeContainer(container) then
        if container.Hide then container:Hide() end
        return nil
    end
    container:Show()
    A3.nativeAuraRuntimeError = nil
    return container
end

local function UpdateDispelSensorRootSlots(container, sensorRoot, firstButtonIndex)
    local slots = container and container._msufA3SensorButtonSlots
    local sensors = sensorRoot and sensorRoot.sensors
    if not (slots and type(sensors) == "table") then return false end
    container._msufA3SensorSlotFilterStrings = container._msufA3SensorSlotFilterStrings or {}
    container._msufA3SensorSlotCandidateSignatures = container._msufA3SensorSlotCandidateSignatures or {}
    local oldEnd = container._msufA3SensorButtonEnd or 0
    local buttonIndex = firstButtonIndex or 0
    local first = buttonIndex + 1
    for i = 1, #sensors do
        local sensor = sensors[i]
        local count = math_max(1, sensor and sensor.max or 1)
        for sensorIndex = 1, count do
            buttonIndex = buttonIndex + 1
            if not slots[buttonIndex] then slots[buttonIndex] = {} end
            local slotKey = ManagedAuraKey(sensor) .. "_" .. tostring(sensorIndex)
            slots[buttonIndex].sensor = sensor
            slots[buttonIndex].sensorIndex = sensorIndex
            slots[buttonIndex].slotKey = slotKey
            if container._msufA3SensorSlotFilterStrings[slotKey] ~= sensor.nativeFilter then
                container:SetAuraSlotFilterString(slotKey, sensor.nativeFilter)
                container._msufA3SensorSlotFilterStrings[slotKey] = sensor.nativeFilter
            end
            local candidateFilters, candidateSignature = DS.SlotCandidateFilters(sensor, sensorIndex)
            if container._msufA3SensorSlotCandidateSignatures[slotKey] ~= candidateSignature then
                container:SetAuraSlotCandidateFilters(slotKey, candidateFilters)
                container._msufA3SensorSlotCandidateSignatures[slotKey] = candidateSignature
            end
        end
    end
    for i = buttonIndex + 1, oldEnd do
        slots[i] = nil
    end
    container._msufA3SensorButtonStart = first
    container._msufA3SensorButtonEnd = buttonIndex
    return true
end

SyncDispelSensorGeometry = function(container, sensor, parentFrame, forceGeometry)
    if not (container and sensor) then return false end
    forceGeometry = forceGeometry == true or container._msufA3ForceManagedAuraGeometry == true
    parentFrame = parentFrame or container._msufA3ParentFrame or container:GetParent()
    if not parentFrame then return false end
    container._msufA3NativeLaneConfig = sensor
    container._msufA3ParentFrame = parentFrame
    local target = DispelSensorTarget(parentFrame, sensor)
    local sig = sensor._msufA3LayoutSignature or SensorLayoutSignature(sensor)
    if forceGeometry ~= true
        and sig ~= nil
        and container._msufA3GeomSig == sig
        and container._msufA3GeomParent == parentFrame
        and container._msufA3GeomTarget == target
    then
        return true
    end
    container._msufA3GeomSig = sig
    container._msufA3GeomParent = parentFrame
    container._msufA3GeomTarget = target
    local root = container:GetParent()
    if root then container:SetAllPoints(root) end
    if parentFrame and container.SetFrameLevel then
        container:SetFrameLevel((parentFrame:GetFrameLevel() or 0) + 1)
        SyncFrameStrata(container, ReadParentFrameStrata(parentFrame))
    end
    -- Do not touch already initialized AuraButtons here; they may be forbidden
    -- while aura data is secret.
    if forceGeometry == true then container._msufA3ForceManagedAuraGeometry = nil end
    return true
end

local function CreateNativeDispelSensor(root, sensor, parentFrame)
    if not EnsureBlizzardAuraContainerLoaded() then
        A3.nativeAuraRuntimeAvailable = false
        A3.nativeAuraRuntimeError = AURA_CONTAINER_ADDON .. " is not loaded: " .. tostring(A3.nativeAuraRuntimeLoadError or "unknown")
        return nil
    end
    local container = CreateNativeAuraContainer(root)
    if not container then return nil end
    return CreateManagedDispelSensor(container, sensor, parentFrame)
end

local function CreateNativeDispelSensorRoot(root, sensorRoot, parentFrame)
    if not EnsureBlizzardAuraContainerLoaded() then
        A3.nativeAuraRuntimeAvailable = false
        A3.nativeAuraRuntimeError = AURA_CONTAINER_ADDON .. " is not loaded: " .. tostring(A3.nativeAuraRuntimeLoadError or "unknown")
        return nil
    end
    local container = CreateNativeAuraContainer(root)
    if not container then return nil end
    return CreateManagedDispelSensorRoot(container, sensorRoot, parentFrame)
end

local function SyncGroupSlotsGeometry(container, groupSlots, parentFrame, forceGeometry)
    parentFrame = parentFrame or container._msufA3ParentFrame or container:GetParent()
    if not parentFrame then return false end
    local ok = true
    local sensorRoot = groupSlots.sensorRoot
    local spellRoot = groupSlots.spellIndicatorRoot
    local flowLane = groupSlots.flowLane
    -- Fixed AuraSlot buttons receive their final geometry in initializeFrame.
    -- Without a flow group, retain the existing full-root container geometry.
    -- With a flow group, its fixed host must win after Spell Indicator sync
    -- temporarily restores the slot-only full-root geometry.
    if sensorRoot and not flowLane then
        ok = SyncDispelSensorRootGeometry(container, sensorRoot, parentFrame, forceGeometry) and ok
    end
    if spellRoot then
        ok = SpellIndicatorsRuntime.SyncGeometry(container, spellRoot, parentFrame, forceGeometry) and ok
    end
    if flowLane then
        if spellRoot then container._msufA3GeomSig = nil end
        ok = SyncContainerGeometry(container, flowLane, parentFrame, forceGeometry, true) and ok
    elseif not sensorRoot and not spellRoot
        and (forceGeometry == true or container._msufA3LaneSlotParent ~= parentFrame) then
        local root = container:GetParent()
        if root then container:SetAllPoints(root) end
        if container.SetFrameLevel then container:SetFrameLevel((parentFrame:GetFrameLevel() or 0) + 1) end
        SyncFrameStrata(container, ReadParentFrameStrata(parentFrame))
        container._msufA3LaneSlotParent = parentFrame
    end
    container._msufA3NativeLaneConfig = groupSlots
    container._msufA3ParentFrame = parentFrame
    if container._msufA3FixedButtonCount ~= nil then
        container.createdButtons = container._msufA3FixedButtonCount
            + (flowLane and flowLane.max or 0)
    end
    return ok
end

local function CreateManagedGroupSlots(container, groupSlots, parentFrame)
    if not container then return nil end
    A3.nativeAuraRuntimeAvailable = true
    container._msufA3ManagedAuraSlots = true
    container._msufA3GroupSlotsRoot = true
    container._msufA3NativeLane = groupSlots.kind
    container._msufA3NativeRegistered = nil
    container._msufA3NativeRegistrationPending = nil
    container._msufA3SensorButtonSlots = {}
    container._msufA3LaneSlotFilterStrings = {}
    container._msufA3LaneSlotCandidateSignatures = {}
    container._msufA3LaneSlotSortSignatures = {}
    container._msufA3GroupRootKey = groupSlots.rootKey or "GroupSlots"
    container.unit = groupSlots.unit
    ConfigureNativeAuraContainer(container, groupSlots.unit)
    container:SetAlpha(1)
    local flowLane = groupSlots.flowLane
    if flowLane then
        local root = container._msufA3Root or container:GetParent()
        local host = CreateFrame("Frame", nil, root)
        if not host then return nil end
        container._msufA3LayoutHost = host
    end
    if not SyncGroupSlotsGeometry(container, groupSlots, parentFrame) then return nil end

    local buttonIndex = 0
    local spellRoot = groupSlots.spellIndicatorRoot
    if spellRoot then
        buttonIndex = SpellIndicatorsRuntime.AttachSlots(container, spellRoot)
    end
    local sensorRoot = groupSlots.sensorRoot
    local sensors = sensorRoot and sensorRoot.sensors or nil
    if sensors then
        for i = 1, #sensors do
            buttonIndex = AddDispelSensorSlots(container, sensors[i], parentFrame, buttonIndex)
        end
    end
    local slotLanes = groupSlots.slotLanes
    if slotLanes then
        for i = 1, #slotLanes do
            local lane = slotLanes[i]
            local slotKey = GroupLaneSlotKey(lane)
            local nativeFilter, _, candidateFilterSignature = EffectiveLaneFilters(lane)
            buttonIndex = buttonIndex + 1
            container:AddAuraSlot(slotKey, nativeFilter,
                BuildGroupLaneSlotOptions(container, lane, parentFrame, buttonIndex))
            container._msufA3LaneSlotFilterStrings[slotKey] = nativeFilter
            container._msufA3LaneSlotCandidateSignatures[slotKey] = candidateFilterSignature
            container._msufA3LaneSlotSortSignatures[slotKey] = AuraSortSignature(lane)
        end
    end
    container._msufA3FixedButtonCount = buttonIndex
    if flowLane then
        local nativeFilter, _, candidateFilterSignature = EffectiveLaneFilters(flowLane)
        container._msufA3ManagedAuraGroups = true
        container._msufA3ManagedGroupKey = ManagedAuraKey(flowLane)
        container:AddAuraGroup(container._msufA3ManagedGroupKey, nativeFilter,
            BuildManagedAuraGroupOptions(container, flowLane))
        container._msufA3FilterString = nativeFilter
        container._msufA3MaxFrameCount = flowLane.max
        container._msufA3CandidateFilterSignature = candidateFilterSignature
        container._msufA3SortSignature = AuraSortSignature(flowLane)
        if not ApplyManagedAuraGroupLayout(container, container._msufA3ManagedGroupKey, flowLane) then
            if container.Hide then container:Hide() end
            return nil
        end
        buttonIndex = buttonIndex + (flowLane.max or 0)
    end
    container.createdButtons = buttonIndex
    container._msufA3NativeLaneConfig = groupSlots
    if not RegisterNativeContainer(container) then
        if container.Hide then container:Hide() end
        return nil
    end
    container:Show()
    A3.nativeAuraRuntimeError = nil
    return container
end

local function HeaderGroupSlotsContainer(root, parentFrame)
    local container = parentFrame and parentFrame.AuraContainer
    if not container or container._msufA3HeaderContainerConsumed == true then return nil end
    if not ValidateNativeAuraContainerContract(container) then return nil end
    container._msufA3HeaderContainerConsumed = true
    container._msufA3Root = root
    return container
end

local function RememberGroupOwner(parentFrame, rootKey, container)
    if not (parentFrame and rootKey and container) then return end
    local owners = parentFrame._msufA3GroupOwners
    if not owners then
        owners = {}
        parentFrame._msufA3GroupOwners = owners
    end
    owners[rootKey] = container
end

local function CreateNativeGroupSlots(root, groupSlots, parentFrame)
    if not EnsureBlizzardAuraContainerLoaded() then
        A3.nativeAuraRuntimeAvailable = false
        A3.nativeAuraRuntimeError = AURA_CONTAINER_ADDON .. " is not loaded: " .. tostring(A3.nativeAuraRuntimeLoadError or "unknown")
        return nil
    end
    -- SecureGroupHeader births one container with each party/raid child. Adopt
    -- it once for the fixed-slot owner; structural replacements deliberately
    -- fall back to a fresh container because AuraSlot definitions are immutable.
    local container = groupSlots.rootKey == "GroupSlots" and HeaderGroupSlotsContainer(root, parentFrame)
        or CreateNativeAuraContainer(root)
    if not container then return nil end
    return CreateManagedGroupSlots(container, groupSlots, parentFrame)
end

-- World transitions are the only path that deliberately distrusts cached
-- desired geometry. Keep the dispatch here so every managed Auras3 container
-- gets one cache-bypassing repair without adding live GetPoint work to normal
-- UNIT_AURA updates.
A3._ManagedAuraContainerSupportsGeometryRepair = function(container)
    if not container then return false end
    if container._msufA3SpellIndicatorRoot == true then
        return true
    end
    return type(container._msufA3NativeLaneConfig) == "table"
end

A3._SyncManagedAuraContainerGeometry = function(container, forceGeometry)
    if not A3._ManagedAuraContainerSupportsGeometryRepair(container) then return false end
    forceGeometry = forceGeometry == true
        or container._msufA3ForceManagedAuraGeometry == true
        or container._msufA3ForceSpellIndicatorGeometry == true
    local lane = container._msufA3NativeLaneConfig
    local parentFrame = container._msufA3ParentFrame
    local ok
    if container._msufA3GroupSlotsRoot == true then
        ok = SyncGroupSlotsGeometry(container, lane, parentFrame, forceGeometry)
    elseif container._msufA3SpellIndicatorRoot == true then
        -- This boolean sync API cannot hand a replacement back to callers
        -- holding the old container. Keep a native-button repair pending here;
        -- the direct identity pass recreates it after leaving the set iterator.
        ok = SpellIndicatorsRuntime.SyncGeometry(container, lane, parentFrame, forceGeometry)
    elseif lane and lane.sensorRoot == true then
        ok = SyncDispelSensorRootGeometry(container, lane, parentFrame, forceGeometry)
    elseif lane and lane.sensor == true then
        ok = SyncDispelSensorGeometry(container, lane, parentFrame, forceGeometry)
    else
        ok = SyncContainerGeometry(container, lane, parentFrame, forceGeometry)
    end
    if ok == true and forceGeometry == true then
        container._msufA3ForceManagedAuraGeometry = nil
        if container._msufA3SpellIndicatorRoot ~= true and container._msufA3GroupSlotsRoot ~= true then
            container._msufA3ForceSpellIndicatorGeometry = nil
        end
    end
    return ok == true
end

ConfigureContainer = function(container, lane, parentFrame)
    container._msufA3NativeLane = lane.kind
    container._msufA3NativeRegistered = nil
    container._msufA3NativeRegistrationPending = nil
    container.unit = lane.unit
    SyncContainerGeometry(container, lane, parentFrame)
end

A3._NativeContainerVisible = function(container)
    if not container then return false end
    -- Native AuraContainers are Frames: IsVisible already includes both their
    -- own shown state and inherited parent visibility. Fall back to IsShown
    -- only for lightweight test/compatibility objects without IsVisible.
    if type(container.IsVisible) == "function" then
        return container:IsVisible() == true
    end
    if type(container.IsShown) == "function" then
        return container:IsShown() == true
    end
    return true
end

-- UnitCanAssist is a normal non-secret boolean in the 12.1 API contract. Keep
-- the write on the native boolean sink so every affected owner receives one
-- direct alpha update without inspecting any restricted aura data.
local function SetAssistAlpha(region, value, trueAlpha)
    if not region then return false end
    if region.SetAlphaFromBoolean then
        region:SetAlphaFromBoolean(value, trueAlpha, 0)
    elseif region.SetAlpha then
        region:SetAlpha(value and trueAlpha or 0)
    else
        return false
    end
    return true
end

local function IsLiveGroupAuraFrame(frame)
    return frame and frame._msufGFIsPreviewFrame ~= true and IsGroupFrame(frame) or false
end

local function ApplyGroupLaneAccessGate(root, lanes, laneKey, rootKey, canAssist, ready)
    local lane = lanes and lanes[laneKey]
    if not (lane and lane.groupAccessGate == true) then return false end
    local known = issecretvalue(canAssist) ~= true and type(canAssist) == "boolean"
    local parentFrame = root and root.GetParent and root:GetParent()
    local present = not parentFrame or parentFrame._msufA3GroupAuraPresenceVisible ~= false
    local visible = present and ready ~= false and known and (lane.identityCandidateMode == "hostile"
        and canAssist == false or lane.identityCandidateMode ~= "hostile" and canAssist == true)
    return SetAssistAlpha(root[rootKey], visible, lane.alpha or 1)
end

local function NeedsGroupAuraAssistGate(cfg)
    if not (cfg and cfg.group == true and cfg.enabled == true) then return false end
    local groupSlots = GetGroupSlotsRootConfig(cfg)
    if groupSlots and (groupSlots.assistGated == true
        or groupSlots.secondaryRoot and groupSlots.secondaryRoot.assistGated == true
        or groupSlots.tertiaryRoot and groupSlots.tertiaryRoot.assistGated == true) then
        return true
    end
    local lanes = cfg.lanes
    return lanes and (
        lanes.buff and lanes.buff.enabled == true and lanes.buff.groupAccessGate == true
        or lanes.debuff and lanes.debuff.enabled == true and lanes.debuff.groupAccessGate == true
        or lanes.trackedBuff and lanes.trackedBuff.enabled == true and lanes.trackedBuff.groupAccessGate == true
        or lanes.external and lanes.external.enabled == true and lanes.external.groupAccessGate == true)
        or false
end
A3._NeedsGroupAuraAssistGate = NeedsGroupAuraAssistGate

-- Exact-ID owners are polarity-aware: helpful filters are valid only while
-- assistable, harmful filters only while non-assistable. Ordinary token-only
-- Buff/Debuff and Dispel flows remain under incremental UNIT_AURA ownership.
local function ApplyGroupAuraAssistGate(frame, canAssist, ready)
    local root = frame.Auras
    if not (root and root._msufA3NativeRoot == true) then return false end
    local known = issecretvalue(canAssist) ~= true and type(canAssist) == "boolean"
    ready = ready ~= false and known
    frame._msufA3GroupAuraAssistReady = ready
    if known then
        frame._msufA3GroupAuraCanAssist = canAssist
    else
        frame._msufA3GroupAuraCanAssist = nil
    end
    local present = frame._msufA3GroupAuraPresenceVisible ~= false

    local cfg = root._msufA3Config
    local groupSlots = GetGroupSlotsRootConfig(cfg)
    local any = false
    local owners = groupSlots and {
        groupSlots,
        groupSlots.secondaryRoot,
        groupSlots.tertiaryRoot,
    } or {}
    for index = 1, 3 do
        local owner = owners[index]
        if owner and owner.assistGated == true then
            local visible = present and ready and (owner.identityCandidateMode == "hostile"
                and canAssist == false or owner.identityCandidateMode ~= "hostile" and canAssist == true)
            any = SetAssistAlpha(root[owner.rootKey or "GroupSlots"], visible, 1) or any
        end
    end

    local lanes = cfg and cfg.lanes
    any = ApplyGroupLaneAccessGate(root, lanes, "buff", "Buffs", canAssist, ready) or any
    any = ApplyGroupLaneAccessGate(root, lanes, "debuff", "Debuffs", canAssist, ready) or any
    any = ApplyGroupLaneAccessGate(root, lanes, "trackedBuff", "TrackedBuffs", canAssist, ready) or any
    any = ApplyGroupLaneAccessGate(root, lanes, "external", "Externals", canAssist, ready) or any

    any = SpellIndicatorsRuntime.ApplyGroupAssistGate(frame, canAssist, ready) or any
    return any
end

A3._SeedGroupAuraAssistGate = function(frame, fallbackUnit)
    if not IsLiveGroupAuraFrame(frame) then return false end
    local root = frame.Auras
    if not NeedsGroupAuraAssistGate(root and root._msufA3Config) then return false end
    -- Secure-header retirement/rebinding can briefly clear MSUFUnitKey while
    -- the native container is still present in the direct-identity registry.
    -- That registry key is the authoritative fallback for this cold check.
    local unit = frame.MSUFUnitKey
    if issecretvalue(unit) == true or type(unit) ~= "string" or unit == "" then
        unit = fallbackUnit
    end
    if issecretvalue(unit) == true or type(unit) ~= "string" or unit == "" then return false end
    if unit ~= "player" and not (A3._IsGroupUnitToken and A3._IsGroupUnitToken(unit)) then
        return false
    end
    if type(A3._UpdateGroupAuraAssistState) == "function" then
        return A3._UpdateGroupAuraAssistState(unit, false, true)
    end
    local unitCanAssist = _G.UnitCanAssist
    if type(unitCanAssist) ~= "function" then return ApplyGroupAuraAssistGate(frame, nil, false) end
    local canAssist = unitCanAssist("player", unit)
    local known = issecretvalue(canAssist) ~= true and type(canAssist) == "boolean"
    if not known then canAssist = nil end
    return ApplyGroupAuraAssistGate(frame, canAssist, known)
end

A3._directIdentityRefreshUnits = A3._directIdentityRefreshUnits or {
    player = true,
    target = true,
    focus = true,
    boss1 = true,
    boss2 = true,
    boss3 = true,
    boss4 = true,
    boss5 = true,
}

A3._directIdentityRefreshAllEvents = A3._directIdentityRefreshAllEvents or {
    PLAYER_ENTERING_WORLD = true,
    ZONE_CHANGED_NEW_AREA = true,
    ENTERED_DIFFERENT_INSTANCE_FROM_PARTY = true,
}

A3._directIdentityEventUnits = A3._directIdentityEventUnits or {
    PLAYER_TARGET_CHANGED = { "target" },
    PLAYER_FOCUS_CHANGED = { "focus" },
    INSTANCE_ENCOUNTER_ENGAGE_UNIT = { "boss1", "boss2", "boss3", "boss4", "boss5" },
}

A3._HasDirectIdentityRefreshContainers = function()
    local byUnit = A3._directIdentityAuraContainers
    if not byUnit then return false end
    for unit, containers in pairs(byUnit) do
        if containers and next(containers) then return true end
        byUnit[unit] = nil
    end
    return false
end

A3._IsGroupUnitToken = function(unit)
    return type(unit) == "string" and (unit:match("^party%d+$") ~= nil or unit:match("^raid%d+$") ~= nil)
end

A3._DirectIdentityRefreshUnitEligible = function(unit)
    if A3._directIdentityRefreshUnits[unit] == true then return true end
    return A3._IsGroupUnitToken(unit)
end

local function NativeFilterOwnsHelpfulAuras(nativeFilter)
    return type(nativeFilter) == "string"
        and nativeFilter:find("HELPFUL", 1, true) ~= nil
end

local function GroupSlotsOwnHelpfulAuras(groupSlots)
    if not groupSlots then return false end
    local flowLane = groupSlots.flowLane
    if flowLane and NativeFilterOwnsHelpfulAuras(flowLane.nativeFilter) then
        return true
    end
    local slotLanes = groupSlots.slotLanes
    for i = 1, #(slotLanes or {}) do
        local lane = slotLanes[i]
        if lane and NativeFilterOwnsHelpfulAuras(lane.nativeFilter) then
            return true
        end
    end
    return false
end

local function ContainerOwnsHelpfulAuras(container, lane)
    if container and container._msufA3GroupSlotsRoot == true then
        return GroupSlotsOwnHelpfulAuras(lane)
    end
    return lane and NativeFilterOwnsHelpfulAuras(lane.nativeFilter)
end

-- Identity-sensitive group owners are deliberately discoverable from their
-- cold compiled descriptors. Lifecycle events therefore route by unit and scan
-- only that unit's tiny native-owner set; no frame-local event or roster walk is
-- needed for a normal per-unit edge.
A3._ContainerOwnsGroupAuraAssistGate = function(container)
    local parentFrame = container and container._msufA3ParentFrame
    if not IsLiveGroupAuraFrame(parentFrame) then return false end
    local config = container._msufA3NativeLaneConfig
    if type(config) ~= "table" then return false end
    if container._msufA3GroupSlotsRoot == true then
        return config.assistGated == true
    end
    return config.groupAccessGate == true
end

A3._GroupAuraAssistOwnerVisible = function(container, canAssist)
    if issecretvalue(canAssist) == true or type(canAssist) ~= "boolean" then return false end
    local config = container and container._msufA3NativeLaneConfig
    if type(config) ~= "table" then return false end
    if config.identityCandidateMode == "hostile" then return canAssist ~= true end
    return canAssist == true
end

A3._GroupAuraAssistUnitHasOwners = function(unit)
    local counts = A3._groupAuraAssistOwnerCounts
    return counts ~= nil and (counts[unit] or 0) > 0
end

A3._HasGroupAuraAssistOwners = function()
    local byUnit = A3._directIdentityAuraContainers
    if not byUnit then
        A3._groupAuraAssistOwnerCount = 0
        return false
    end
    return (A3._groupAuraAssistOwnerCount or 0) > 0
end

A3._ApplyGroupAuraAssistStateToUnit = function(unit, canAssist)
    local byUnit = A3._directIdentityAuraContainers
    local containers = byUnit and byUnit[unit]
    if not containers then return false end
    local parents, any = {}, false
    for container in pairs(containers) do
        if A3._ContainerOwnsGroupAuraAssistGate(container) then
            local parentFrame = container._msufA3ParentFrame
            if parentFrame and parents[parentFrame] ~= true then
                parents[parentFrame] = true
                any = ApplyGroupAuraAssistGate(parentFrame, canAssist, true) or any
            end
        end
    end
    return any
end


A3._HideGroupAuraAssistOwners = function(unit, canAssist)
    local byUnit = A3._directIdentityAuraContainers
    local containers = byUnit and byUnit[unit]
    if not containers then return false end
    local parents, any = {}, false
    for container in pairs(containers) do
        if A3._ContainerOwnsGroupAuraAssistGate(container) then
            local parentFrame = container._msufA3ParentFrame
            if parentFrame and parents[parentFrame] ~= true then
                parents[parentFrame] = true
                any = ApplyGroupAuraAssistGate(parentFrame, canAssist, false) or any
            end
        end
    end
    return any
end

A3._ReadGroupAuraAssistIdentity = function(unit, readGUID)
    local unitCanAssist = _G.UnitCanAssist
    if type(unitCanAssist) ~= "function" then return nil, false, nil, false end
    local canAssist = unitCanAssist("player", unit)
    local assistKnown = issecretvalue(canAssist) ~= true and type(canAssist) == "boolean"
    if not assistKnown then canAssist = nil end

    if readGUID ~= true then return canAssist, assistKnown, nil, false end
    local unitGUID = _G.UnitGUID
    if type(unitGUID) ~= "function" then return canAssist, assistKnown, nil, false end
    local guid = unitGUID(unit)
    if issecretvalue(guid) == true or (guid ~= nil and type(guid) ~= "string") then
        return canAssist, assistKnown, nil, false
    end
    return canAssist, assistKnown, guid, true
end

-- Unit-frame exact-ID owners use the same Blizzard identity contract as Group
-- owners, but they deliberately stay out of the Group roster/flag lifecycle.
-- Their only live inputs are the already-owned target/focus/boss identity
-- events and the existing UNIT_FACTION route.
A3._ContainerOwnsUnitAuraIdentityGate = function(container)
    if not container or IsLiveGroupAuraFrame(container._msufA3ParentFrame) then return false end
    local config = container._msufA3NativeLaneConfig
    if type(config) ~= "table" then return false end
    return config.identityCandidateMode == "assist"
        or config.identityCandidateMode == "hostile"
end

A3._UnitAuraIdentityOwnerVisible = function(container, canAssist)
    if issecretvalue(canAssist) == true or type(canAssist) ~= "boolean" then return false end
    local config = container and container._msufA3NativeLaneConfig
    if type(config) ~= "table" then return false end
    if config.identityCandidateMode == "hostile" then return canAssist ~= true end
    return config.identityCandidateMode == "assist" and canAssist == true
end

A3._UnitAuraIdentityUnitHasOwners = function(unit)
    local owners = A3._unitAuraIdentityOwnersByUnit
    local set = owners and owners[unit]
    return set ~= nil and next(set) ~= nil
end

A3._SetUnitAuraIdentityOwnerReady = function(container, canAssist, ready)
    if not A3._ContainerOwnsUnitAuraIdentityGate(container) then return false end
    local config = container._msufA3NativeLaneConfig
    local visible = ready == true and A3._UnitAuraIdentityOwnerVisible(container, canAssist)
    local any = SetAssistAlpha(container, visible, tonumber(config.alpha) or 1)
    if container._msufA3SpellIndicatorRoot == true then
        any = SpellIndicatorsRuntime.ApplyUnitIdentityGate(
            container, canAssist, ready) or any
    end
    return any
end

A3._ApplyUnitAuraIdentityStateToUnit = function(unit, canAssist, ready)
    local owners = A3._unitAuraIdentityOwnersByUnit
    local set = owners and owners[unit]
    if not set then return false end
    local any = false
    for container in pairs(set) do
        any = A3._SetUnitAuraIdentityOwnerReady(container, canAssist, ready) or any
    end
    return any
end

A3._EnsureUnitAuraIdentityState = function(unit)
    local states = A3._unitAuraIdentityState
    if not states then
        states = {}
        A3._unitAuraIdentityState = states
    end
    local state = states[unit]
    if not state then
        state = { revision = 0 }
        states[unit] = state
    end
    return state
end

A3._RefreshUnitAuraIdentityState = function(unit)
    if not A3._UnitAuraIdentityUnitHasOwners(unit) then return nil end
    local state = A3._EnsureUnitAuraIdentityState(unit)
    local canAssist, assistKnown = A3._ReadGroupAuraAssistIdentity(unit, false)
    state.revision = (state.revision or 0) + 1
    state.initialized = true
    state.assistKnown = assistKnown == true
    if assistKnown == true then state.canAssist = canAssist else state.canAssist = nil end
    return state
end

A3._FlushUnitAuraIdentityReveal = function()
    A3._unitAuraIdentityRevealPending = nil
    local units = A3._unitAuraIdentityRevealUnits
    local states = A3._unitAuraIdentityState
    if not (units and states) then return false end
    local any = false
    for unit, revision in pairs(units) do
        units[unit] = nil
        local state = states[unit]
        if state and state.revision == revision and state.assistKnown == true then
            any = A3._ApplyUnitAuraIdentityStateToUnit(unit, state.canAssist, true) or any
        end
    end
    return any
end

A3._ScheduleUnitAuraIdentityReveal = function(unit, revision)
    local units = A3._unitAuraIdentityRevealUnits
    if not units then
        units = {}
        A3._unitAuraIdentityRevealUnits = units
    end
    units[unit] = revision
    if A3._unitAuraIdentityRevealPending == true then return true end
    A3._unitAuraIdentityRevealPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, A3._FlushUnitAuraIdentityReveal)
    else
        A3._FlushUnitAuraIdentityReveal()
    end
    return true
end

A3._SeedUnitAuraIdentityOwner = function(container, unit)
    if not A3._ContainerOwnsUnitAuraIdentityGate(container) then return false end
    local state = A3._EnsureUnitAuraIdentityState(unit)
    if state.initialized ~= true then
        local canAssist, assistKnown = A3._ReadGroupAuraAssistIdentity(unit, false)
        state.revision = (state.revision or 0) + 1
        state.initialized = true
        state.assistKnown = assistKnown == true
        if assistKnown == true then state.canAssist = canAssist else state.canAssist = nil end
    end
    A3._SetUnitAuraIdentityOwnerReady(container, state.canAssist, false)
    if state.assistKnown == true then
        A3._ScheduleUnitAuraIdentityReveal(unit, state.revision)
    end
    return true
end

A3._RefreshGroupAuraAssistOwners = function(unit, canAssist)
    local byUnit = A3._directIdentityAuraContainers
    local containers = byUnit and byUnit[unit]
    if not containers then return false end
    local any = false
    for container in pairs(containers) do
        if A3._ContainerOwnsGroupAuraAssistGate(container)
            and A3._GroupAuraAssistOwnerVisible(container, canAssist) then
            local update = container and container.UpdateAllAuras
            if type(update) == "function" then
                -- Alpha zero does not make a Frame non-visible. Marking a
                -- temporarily hidden owner dirty is still safe: Blizzard's
                -- RunWhenVisibleOnce processes it on the next visible frame.
                update(container)
                any = true
            end
        end
    end
    return any
end

A3._FlushGroupAuraAssistReveal = function()
    A3._groupAuraAssistRevealPending = nil
    local units = A3._groupAuraAssistRevealUnits
    A3._groupAuraAssistRevealUnits = nil
    local states = A3._groupAuraAssistState
    if not (units and states) then return false end
    local any = false
    for unit, revision in pairs(units) do
        local state = states[unit]
        if state and state.revision == revision
            and state.assistKnown == true and state.dirty == true then
            state.dirty = false
            any = A3._ApplyGroupAuraAssistStateToUnit(unit, state.canAssist) or any
        end
    end
    return any
end

A3._ScheduleGroupAuraAssistReveal = function(unit, revision)
    local units = A3._groupAuraAssistRevealUnits
    if not units then
        units = {}
        A3._groupAuraAssistRevealUnits = units
    end
    units[unit] = revision
    if A3._groupAuraAssistRevealPending == true then return true end
    A3._groupAuraAssistRevealPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, A3._FlushGroupAuraAssistReveal)
    else
        A3._FlushGroupAuraAssistReveal()
    end
    return true
end

A3._FlushScheduledGroupAuraAssistRefresh = function()
    A3._groupAuraAssistRefreshPending = nil
    if A3._directIdentityRefreshPending == true
        and A3._directIdentityRefreshSkipLiveGroup ~= true then
        -- A portal/world job already covers every group identity owner. Let the
        -- wider job win regardless of callback order: an all-owner pass adopts
        -- the satisfied parse, while a group-presence pass queues one fresh
        -- eligible-polarity repair after it invalidates native assignments.
        A3._groupAuraAssistRefreshUnits = nil
        return false
    end
    local units = A3._groupAuraAssistRefreshUnits
    A3._groupAuraAssistRefreshUnits = nil
    local states = A3._groupAuraAssistState
    if not (units and states) then return false end
    local any = false
    for unit, revision in pairs(units) do
        local state = states[unit]
        if state and state.revision == revision
            and state.assistKnown == true and state.dirty == true then
            any = A3._RefreshGroupAuraAssistOwners(unit, state.canAssist) or any
            A3._ScheduleGroupAuraAssistReveal(unit, revision)
        end
    end
    return any
end

A3._ScheduleGroupAuraAssistRefresh = function(unit, revision)
    local units = A3._groupAuraAssistRefreshUnits
    if not units then
        units = {}
        A3._groupAuraAssistRefreshUnits = units
    end
    units[unit] = revision
    if A3._groupAuraAssistRefreshPending == true then return true end
    A3._groupAuraAssistRefreshPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, A3._FlushScheduledGroupAuraAssistRefresh)
    else
        A3._FlushScheduledGroupAuraAssistRefresh()
    end
    return true
end

-- State transitions are fail-closed. Both polarity owners stay hidden while
-- UnitCanAssist is unavailable/secret. A known edge keeps both hidden, reparses
-- only the newly eligible owner, then reveals it on the following one-shot tick.
A3._UpdateGroupAuraAssistState = function(unit, checkIdentity, forceApply, forceRefresh, reparseSatisfied)
    if issecretvalue(unit) == true or type(unit) ~= "string" or unit == "" then return false end
    if not A3._GroupAuraAssistUnitHasOwners(unit) then
        local states = A3._groupAuraAssistState
        if states then states[unit] = nil end
        return false
    end

    local states = A3._groupAuraAssistState
    if not states then
        states = {}
        A3._groupAuraAssistState = states
    end
    local state = states[unit]
    local hadState = state ~= nil and state.initialized == true
    local canAssist, assistKnown, guid, guidKnown = A3._ReadGroupAuraAssistIdentity(
        unit, checkIdentity == true or hadState ~= true)
    if not state then
        state = { revision = 0 }
        states[unit] = state
    end
    local previous = state.canAssist
    local previousKnown = state.assistKnown == true
    local identityChanged = checkIdentity == true and hadState == true
        and (guidKnown ~= true or state.guidKnown ~= true or state.guid ~= guid)
    if guidKnown == true then
        state.guid = guid
        state.guidKnown = true
    end
    state.initialized = true
    if assistKnown then state.canAssist = canAssist else state.canAssist = nil end
    state.assistKnown = assistKnown == true

    local needsRefresh = hadState ~= true or previousKnown ~= (assistKnown == true)
        or assistKnown == true and previous ~= canAssist
        or identityChanged or forceRefresh == true
    if reparseSatisfied == true then
        -- The direct identity path has already reparsed every owner for this
        -- unit. Adopt that parse into the state machine instead of scheduling
        -- the eligible polarity a second time. Bumping the revision also makes
        -- any older queued refresh/reveal a harmless no-op.
        state.revision = (state.revision or 0) + 1
        state.dirty = nil
        if assistKnown ~= true then
            A3._HideGroupAuraAssistOwners(unit, nil)
        else
            A3._ApplyGroupAuraAssistStateToUnit(unit, canAssist)
        end
        return true
    end
    if assistKnown ~= true then
        if needsRefresh or forceApply == true then
            state.revision = (state.revision or 0) + 1
            state.dirty = nil
            A3._HideGroupAuraAssistOwners(unit, nil)
        end
        return true
    end
    if needsRefresh then
        state.revision = (state.revision or 0) + 1
        state.dirty = true
        -- Both polarity owners stay fail-closed until the newly eligible owner
        -- has reparsed. Passing ready=false hides HELPFUL and HARMFUL custom
        -- owners together without touching neutral aura flows.
        A3._HideGroupAuraAssistOwners(unit, canAssist)
        A3._ScheduleGroupAuraAssistRefresh(unit, state.revision)
    elseif state.dirty == true then
        if forceApply == true then A3._HideGroupAuraAssistOwners(unit, canAssist) end
        A3._ScheduleGroupAuraAssistRefresh(unit, state.revision)
    elseif forceApply == true then
        A3._ApplyGroupAuraAssistStateToUnit(unit, canAssist)
    end
    return true
end

A3._UpdateAllGroupAuraAssistStates = function(checkIdentity, forceRefresh)
    local counts = A3._groupAuraAssistOwnerCounts
    if not counts then return false end
    local any = false
    for unit, count in pairs(counts) do
        if count > 0 then
            any = A3._UpdateGroupAuraAssistState(unit, checkIdentity, false, forceRefresh) or any
        end
    end
    return any
end

A3._FlushScheduledGroupAuraAssistRefreshAll = function()
    A3._groupAuraAssistRefreshAllPending = nil
    local checkIdentity = A3._groupAuraAssistRefreshAllCheckIdentity == true
    local forceRefresh = A3._groupAuraAssistRefreshAllForce == true
    A3._groupAuraAssistRefreshAllCheckIdentity = nil
    A3._groupAuraAssistRefreshAllForce = nil
    return A3._UpdateAllGroupAuraAssistStates(checkIdentity, forceRefresh)
end

A3._ScheduleGroupAuraAssistRefreshAll = function(checkIdentity, forceRefresh)
    if not A3._HasGroupAuraAssistOwners() then return false end
    if checkIdentity == true then A3._groupAuraAssistRefreshAllCheckIdentity = true end
    if forceRefresh == true then A3._groupAuraAssistRefreshAllForce = true end
    if A3._groupAuraAssistRefreshAllPending == true then return true end
    A3._groupAuraAssistRefreshAllPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, A3._FlushScheduledGroupAuraAssistRefreshAll)
    else
        A3._FlushScheduledGroupAuraAssistRefreshAll()
    end
    return true
end

-- Group Aura presence is deliberately independent from geometric range and
-- from identity-filter permission.  Unknown state remains visible; only hard,
-- distance-independent negatives hide the output.  Native AuraContainers stay
-- shown and enabled so Blizzard can continue delivering incremental UNIT_AURA
-- updates while another party member is in a different instance.
A3._ReadGroupAuraPresenceMapID = function(unit)
    local unitPosition = _G.UnitPosition
    if type(unitPosition) ~= "function" then return nil, false end
    local _, _, _, mapID = unitPosition(unit)
    if issecretvalue(mapID) == true or type(mapID) ~= "number" or mapID <= 0 then
        return nil, false
    end
    return mapID, true
end

A3._ApplyGroupAuraPresenceFrame = function(frame, present, unit, revision)
    if not IsLiveGroupAuraFrame(frame) or type(present) ~= "boolean" then return false end
    frame._msufA3GroupAuraPresenceVisible = present
    frame._msufA3GroupAuraPresenceUnit = unit
    frame._msufA3GroupAuraPresenceRevision = revision
    local root = frame.Auras
    local any = false
    if root and root._msufA3NativeRoot == true and root.SetAlphaFromBoolean then
        root:SetAlphaFromBoolean(present, 1, 0)
        any = true
    elseif root and root._msufA3NativeRoot == true and root.SetAlpha then
        root:SetAlpha(present and 1 or 0)
        any = true
    end
    any = SpellIndicatorsRuntime.ApplyGroupPresenceGate(frame, present) or any
    return any
end

A3._ApplyGroupAuraPresenceContainer = function(container, present, assistState)
    if not container or type(present) ~= "boolean" then return false end
    local outputVisible = present
    if outputVisible and A3._ContainerOwnsGroupAuraAssistGate(container) then
        outputVisible = assistState ~= nil and assistState.assistKnown == true
            and assistState.dirty ~= true
            and A3._GroupAuraAssistOwnerVisible(container, assistState.canAssist)
    end
    local config = container._msufA3NativeLaneConfig
    local trueAlpha = container._msufA3GroupSlotsRoot == true
        and 1 or type(config) == "table" and (config.alpha or 1) or 1
    return SetAssistAlpha(container, outputVisible == true, trueAlpha)
end

A3._ApplyGroupAuraPresenceStateToUnit = function(unit, present, revision)
    local byUnit = A3._directIdentityAuraContainers
    local containers = byUnit and byUnit[unit]
    if not containers or type(present) ~= "boolean" then return false end
    local assistState = A3._groupAuraAssistState and A3._groupAuraAssistState[unit]
    local parents, any = {}, false
    for container in pairs(containers) do
        local parentFrame = container and container._msufA3ParentFrame
        if IsLiveGroupAuraFrame(parentFrame) then
            if parents[parentFrame] ~= true then
                parents[parentFrame] = true
                any = A3._ApplyGroupAuraPresenceFrame(
                    parentFrame, present, unit, revision) or any
            end
            any = A3._ApplyGroupAuraPresenceContainer(
                container, present, assistState) or any
        end
    end
    return any
end

A3._GroupAuraPresenceUnitHasOwners = function(unit)
    local counts = A3._directIdentityGroupOwnerCounts
    return counts ~= nil and (counts[unit] or 0) > 0
end

A3._EnsureGroupAuraPresenceState = function(unit, allowUnregistered)
    if issecretvalue(unit) == true or type(unit) ~= "string" or unit == "" then return nil end
    if unit ~= "player" and not A3._IsGroupUnitToken(unit) then return nil end
    if allowUnregistered ~= true and not A3._GroupAuraPresenceUnitHasOwners(unit) then
        local states = A3._groupAuraPresenceState
        if states then states[unit] = nil end
        return nil
    end
    local states = A3._groupAuraPresenceState
    if not states then
        states = {}
        A3._groupAuraPresenceState = states
    end
    local state = states[unit]
    if not state then
        state = { revision = 0 }
        states[unit] = state
    end
    return state
end

local function GroupAuraPresenceDerivedValue(state)
    return not (state.awaitingFullPresence == true or state.disabled == true
        or state.mapMismatch == true or state.phaseAbsent == true
        or state.otherParty == true or state.offline == true)
end

A3._CommitGroupAuraPresenceState = function(unit, state, forceApply)
    if not state then return false end
    local hadState = state.initialized == true
    local previous = state.present ~= false
    local present = unit == "player" or GroupAuraPresenceDerivedValue(state)
    state.initialized = true
    state.present = present
    local changed = hadState ~= true or previous ~= present
    if changed then state.revision = (state.revision or 0) + 1 end
    if changed or forceApply == true then
        return A3._ApplyGroupAuraPresenceStateToUnit(unit, present, state.revision)
    end
    return true
end

-- Token generations must remain live in combat so a reused raidN/partyN slot
-- can never inherit the previous member's absence latches.  This path reads no
-- map, phase, other-party, or connection state.
A3._UpdateGroupAuraPresenceIdentityState = function(unit, forceApply, allowUnregistered)
    local state = A3._EnsureGroupAuraPresenceState(unit, allowUnregistered)
    if not state then return false end
    if unit == "player" then
        state.guid = nil
        state.guidKnown = true
        state.awaitingFullPresence = nil
        return A3._CommitGroupAuraPresenceState(unit, state, forceApply)
    end
    local unitGUID = _G.UnitGUID
    if type(unitGUID) ~= "function" then return A3._CommitGroupAuraPresenceState(unit, state, forceApply) end
    local guid = unitGUID(unit)
    if issecretvalue(guid) == true or type(guid) ~= "string" then
        return A3._CommitGroupAuraPresenceState(unit, state, forceApply)
    end
    local hadIdentity = state.guidKnown == true
    local identityChanged = state.initialized == true
        and (hadIdentity ~= true or state.guid ~= guid)
    state.guid = guid
    state.guidKnown = true
    if identityChanged then
        state.disabled = nil
        state.mapMismatch = nil
        state.phaseAbsent = nil
        state.otherParty = nil
        state.offline = nil
        -- A readable new token generation must never inherit absence from the
        -- prior member. Unknown remains visible by policy; cold map/instance
        -- validation is merged separately and runs only OOC.
        state.awaitingFullPresence = nil
    end
    return A3._CommitGroupAuraPresenceState(unit, state, forceApply)
end

A3._UpdateAllGroupAuraPresenceIdentityStates = function()
    local any = false
    for unit, count in pairs(A3._directIdentityGroupOwnerCounts or {}) do
        if count > 0 then
            any = A3._UpdateGroupAuraPresenceIdentityState(unit, false) or any
        end
    end
    return any
end

-- Phase and connection are combat-relevant hard states.  Their narrow readers
-- intentionally do not consult UnitPosition or UnitInOtherParty; those 6.07
-- presence checks are owned exclusively by the OOC full reconciliation below.
A3._UpdateGroupAuraPresencePhaseState = function(unit, forceApply, allowUnregistered)
    local state = A3._EnsureGroupAuraPresenceState(unit, allowUnregistered)
    if not state then return false end
    if unit == "player" then return A3._CommitGroupAuraPresenceState(unit, state, forceApply) end
    local unitPhaseReason = _G.UnitPhaseReason
    local phaseReason = type(unitPhaseReason) == "function" and unitPhaseReason(unit) or nil
    if issecretvalue(phaseReason) ~= true then
        state.phaseAbsent = phaseReason ~= nil or nil
    end
    return A3._CommitGroupAuraPresenceState(unit, state, forceApply)
end

A3._UpdateAllGroupAuraPresencePhaseStates = function()
    local any = false
    for unit, count in pairs(A3._directIdentityGroupOwnerCounts or {}) do
        if count > 0 then
            any = A3._UpdateGroupAuraPresencePhaseState(unit, false) or any
        end
    end
    return any
end

A3._UpdateGroupAuraPresenceConnectionState = function(
    unit, connectedPayload, forceApply, allowUnregistered)
    local state = A3._EnsureGroupAuraPresenceState(unit, allowUnregistered)
    if not state then return false end
    if unit == "player" then return A3._CommitGroupAuraPresenceState(unit, state, forceApply) end
    local connected = connectedPayload
    if issecretvalue(connected) == true or type(connected) ~= "boolean" then
        local unitIsConnected = _G.UnitIsConnected
        connected = type(unitIsConnected) == "function" and unitIsConnected(unit) or nil
    end
    if issecretvalue(connected) ~= true and type(connected) == "boolean" then
        state.offline = connected == false or nil
    end
    return A3._CommitGroupAuraPresenceState(unit, state, forceApply)
end

A3._UpdateGroupAuraPresenceState = function(
    unit, checkIdentity, forceApply, playerMapID, playerMapKnown, allowUnregistered)
    local state = A3._EnsureGroupAuraPresenceState(unit, allowUnregistered)
    if not state then return false end
    -- Full presence is a cold OOC operation.  Seed/rebind/world callbacks can
    -- reach this function during combat; retain/apply the cached gate, update
    -- only token identity, and merge one post-combat reconciliation request.
    if InCombat() then
        local needsInitialFullPresence = state.initialized ~= true
        if checkIdentity == true or needsInitialFullPresence then
            A3._UpdateGroupAuraPresenceIdentityState(unit, false, allowUnregistered)
            state = A3._groupAuraPresenceState and A3._groupAuraPresenceState[unit] or state
        end
        if forceApply == true then
            A3._ApplyGroupAuraPresenceStateToUnit(unit, state.present ~= false, state.revision or 0)
        end
        if type(A3._ScheduleGroupAuraPresenceRefreshAll) == "function" then
            A3._ScheduleGroupAuraPresenceRefreshAll(checkIdentity, false)
        end
        return true
    end

    if checkIdentity == true or state.initialized ~= true then
        A3._UpdateGroupAuraPresenceIdentityState(unit, false, allowUnregistered)
        state = A3._groupAuraPresenceState and A3._groupAuraPresenceState[unit] or state
    end
    if unit == "player" then
        state.mapMismatch = nil
        state.phaseAbsent = nil
        state.otherParty = nil
        state.offline = nil
        state.disabled = nil
        state.awaitingFullPresence = nil
    else
        if playerMapKnown == nil then
            playerMapID, playerMapKnown = A3._ReadGroupAuraPresenceMapID("player")
        end
        local unitMapID, unitMapKnown = A3._ReadGroupAuraPresenceMapID(unit)
        state.mapMismatch = playerMapKnown == true and unitMapKnown == true
            and playerMapID ~= unitMapID or nil

        local unitPhaseReason = _G.UnitPhaseReason
        local phaseReason = type(unitPhaseReason) == "function" and unitPhaseReason(unit) or nil
        state.phaseAbsent = issecretvalue(phaseReason) ~= true and phaseReason ~= nil or nil

        -- Blizzard checks this before its other party-frame not-present
        -- reasons. It is the dedicated signal for a member that is currently
        -- inside a different instance group, including same-map copies where
        -- mapID and phase alone cannot distinguish presence.
        local unitInOtherParty = _G.UnitInOtherParty
        local inOtherParty = type(unitInOtherParty) == "function"
            and unitInOtherParty(unit) or nil
        state.otherParty = issecretvalue(inOtherParty) ~= true
            and type(inOtherParty) == "boolean" and inOtherParty == true or nil

        local unitIsConnected = _G.UnitIsConnected
        local connected = type(unitIsConnected) == "function" and unitIsConnected(unit) or nil
        state.offline = issecretvalue(connected) ~= true
            and type(connected) == "boolean" and connected == false or nil
        state.awaitingFullPresence = nil
    end
    return A3._CommitGroupAuraPresenceState(unit, state, forceApply)
end

A3._SetGroupAuraPresenceDisabled = function(unit, disabled, deferReveal)
    if issecretvalue(unit) == true or not A3._IsGroupUnitToken(unit)
        or (not A3._GroupAuraPresenceUnitHasOwners(unit)
            and (A3._directIdentityGroupOwnerCount or 0) <= 0) then return false end
    -- PARTY_MEMBER_DISABLE can precede the secure child's final registration.
    -- Keep one bounded token hint without invoking the cold presence reader;
    -- the later owner seed consumes this state immediately.
    local state = A3._EnsureGroupAuraPresenceState(unit, true)
    if not state then return false end
    state.memberEventRevision = (state.memberEventRevision or 0) + 1
    local wasDisabled = state.disabled == true
    state.disabled = disabled == true or nil
    state.initialized = true
    if disabled == true then
        state.awaitingFullPresence = nil
    elseif deferReveal == true and (wasDisabled or state.present == false) then
        -- ENABLE is an invalidation, not proof that the unit has returned to
        -- this instance. Keep the previous fail-closed output until the
        -- coalesced reader has refreshed map, phase and connection state.
        state.awaitingFullPresence = true
        A3._CommitGroupAuraPresenceState(unit, state, false)
        return true
    end
    A3._CommitGroupAuraPresenceState(unit, state, false)
    -- A valid directional hint may precede the owner's secure-header
    -- registration, so retaining state counts as success without an alpha sink.
    return true
end

A3._InvalidateSingleGroupAuraPresenceDisabled = function()
    local states = A3._groupAuraPresenceState
    if not states then return false end
    local candidate
    for unit, state in pairs(states) do
        if state and state.disabled == true and A3._GroupAuraPresenceUnitHasOwners(unit) then
            if candidate ~= nil then
                -- A restricted ENABLE payload cannot identify which of several
                -- absent members returned. Keep all fail-closed rather than
                -- revealing an unrelated same-map instance member.
                return false
            end
            candidate = unit
        end
    end
    if candidate == nil then return false end
    states[candidate].disabled = nil
    return true
end

A3._CaptureSingleGroupAuraPresenceDisabled = function()
    local states = A3._groupAuraPresenceState
    local candidate, revision, candidateState
    for unit, state in pairs(states or {}) do
        if state and state.disabled == true and A3._GroupAuraPresenceUnitHasOwners(unit) then
            if candidate ~= nil then
                candidate = nil
                break
            end
            candidate = unit
            candidateState = state
            revision = state.memberEventRevision or 0
        end
    end
    A3._groupAuraPresenceRefreshAllEnableCandidate = candidate
    A3._groupAuraPresenceRefreshAllEnableCandidateRevision = candidate and revision or nil
    A3._groupAuraPresenceRefreshAllEnableCandidateState = candidate and candidateState or nil
    return candidate ~= nil
end

A3._InvalidateCapturedGroupAuraPresenceDisabled = function()
    local unit = A3._groupAuraPresenceRefreshAllEnableCandidate
    local revision = A3._groupAuraPresenceRefreshAllEnableCandidateRevision
    local capturedState = A3._groupAuraPresenceRefreshAllEnableCandidateState
    A3._groupAuraPresenceRefreshAllEnableCandidate = nil
    A3._groupAuraPresenceRefreshAllEnableCandidateRevision = nil
    A3._groupAuraPresenceRefreshAllEnableCandidateState = nil
    local state = unit and A3._groupAuraPresenceState
        and A3._groupAuraPresenceState[unit]
    if not state or state ~= capturedState or state.disabled ~= true
        or (state.memberEventRevision or 0) ~= revision then
        return false
    end
    state.disabled = nil
    return true
end

A3._FlushScheduledGroupAuraPresenceRefreshAll = function()
    A3._groupAuraPresenceRefreshAllTimerPending = nil
    if A3._groupAuraPresenceRefreshAllPending ~= true then return false end
    -- A timer queued just before the pull must not leak cold map/instance reads
    -- into combat. Keep the merged request intact for PLAYER_REGEN_ENABLED.
    if InCombat() then return false end
    A3._groupAuraPresenceRefreshAllPending = nil
    local checkIdentity = A3._groupAuraPresenceRefreshAllCheckIdentity == true
    local checkAssist = A3._groupAuraPresenceRefreshAllCheckAssist == true
    local invalidateSingleDisabled =
        A3._groupAuraPresenceRefreshAllEnableCandidate ~= nil
    A3._groupAuraPresenceRefreshAllCheckIdentity = nil
    A3._groupAuraPresenceRefreshAllCheckAssist = nil
    if invalidateSingleDisabled then
        A3._InvalidateCapturedGroupAuraPresenceDisabled()
    end
    local playerMapID, playerMapKnown = A3._ReadGroupAuraPresenceMapID("player")
    local any = false
    for unit, count in pairs(A3._directIdentityGroupOwnerCounts or {}) do
        if count > 0 then
            any = A3._UpdateGroupAuraPresenceState(
                unit, checkIdentity, false, playerMapID, playerMapKnown) or any
        end
    end
    if checkAssist then
        any = A3._UpdateAllGroupAuraAssistStates(checkIdentity, false) or any
    end
    return any
end

A3._QueueGroupAuraPresenceRefreshAllFlush = function()
    if A3._groupAuraPresenceRefreshAllPending ~= true
        or A3._groupAuraPresenceRefreshAllTimerPending == true
        or InCombat() then return false end
    A3._groupAuraPresenceRefreshAllTimerPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, A3._FlushScheduledGroupAuraPresenceRefreshAll)
    else
        A3._FlushScheduledGroupAuraPresenceRefreshAll()
    end
    return true
end

A3._ScheduleGroupAuraPresenceRefreshAll = function(checkIdentity, checkAssist)
    if (A3._directIdentityGroupOwnerCount or 0) <= 0 then return false end
    if checkIdentity == true then A3._groupAuraPresenceRefreshAllCheckIdentity = true end
    if checkAssist == true then A3._groupAuraPresenceRefreshAllCheckAssist = true end
    A3._groupAuraPresenceRefreshAllPending = true
    A3._QueueGroupAuraPresenceRefreshAllFlush()
    return true
end

A3._SeedGroupAuraPresenceGate = function(frame, fallbackUnit, cachedOnly)
    if not IsLiveGroupAuraFrame(frame) then return false end
    local unit = frame.MSUFUnitKey
    if issecretvalue(unit) == true or type(unit) ~= "string" or unit == "" then
        unit = fallbackUnit
    end
    if issecretvalue(unit) == true or type(unit) ~= "string" or unit == "" then return false end
    if unit ~= "player" and not A3._IsGroupUnitToken(unit) then return false end
    local state = A3._groupAuraPresenceState and A3._groupAuraPresenceState[unit]
    if cachedOnly ~= true or not (state and state.initialized == true) then
        A3._UpdateGroupAuraPresenceState(unit, true, false, nil, nil, true)
        state = A3._groupAuraPresenceState and A3._groupAuraPresenceState[unit]
    end
    local present = not state or state.present ~= false
    local revision = state and state.revision or 0
    local any = A3._ApplyGroupAuraPresenceFrame(frame, present, unit, revision)
    -- The primary SecureGroupHeader AuraContainer can be a direct child of the
    -- member frame instead of frame.Auras. Re-apply the cached state to every
    -- registered owner after config/rebind so that container cannot bypass the
    -- root gate during its first visible frame.
    if A3._GroupAuraPresenceUnitHasOwners(unit) then
        any = A3._ApplyGroupAuraPresenceStateToUnit(unit, present, revision) or any
    end
    return any
end

local function SyncCuratedBigDefensiveContainer(container)
    local config = container and container._msufA3NativeLaneConfig
    if not config then return false end
    local changed = false
    if container._msufA3GroupSlotsRoot == true then
        local slotLanes = config.slotLanes
        for i = 1, #(slotLanes or {}) do
            local lane = slotLanes[i]
            if lane and lane._msufA3BigDefensiveFilter then
                changed = UpdateAuraSlotEffectiveFilters(container, lane) or changed
            end
        end
        local flowLane = config.flowLane
        if flowLane and flowLane._msufA3BigDefensiveFilter then
            changed = UpdateAuraGroupEffectiveFilters(container, flowLane) or changed
        end
    elseif config._msufA3BigDefensiveFilter then
        changed = UpdateAuraGroupEffectiveFilters(container, config)
    end
    return changed
end
A3._SyncCuratedBigDefensiveContainer = SyncCuratedBigDefensiveContainer

-- Presence transitions never invalidate native aura ownership.  They only
-- recompute the plain per-unit output gate; the still-enabled containers keep
-- their incremental UNIT_AURA stream while absent.
A3._DirectGroupPresenceRefreshUnit = function(unit)
    return A3._UpdateGroupAuraPresenceState(unit, false, false)
end

A3._DirectIdentityRefreshUnitBase = function(
    unit, forceSpellIndicatorGeometry, recreateHelpfulAuras, skipLiveGroup)
    local byUnit = A3._directIdentityAuraContainers
    local containers = byUnit and byUnit[unit]
    if not containers then return false end
    -- Only Party/Raid registry units (plus the Party self-frame shared under
    -- "player") can own an assist-gated group aura parent. Target, focus and
    -- boss identity refreshes must not inspect group state.
    local seedGroupAssist = skipLiveGroup ~= true
        and (unit == "player" or A3._directIdentityRefreshUnits[unit] ~= true)

    if forceSpellIndicatorGeometry ~= true then
        -- Target/focus swaps use this direct route. Keep the exceptional
        -- world-transition recreation machinery out of the steady path while
        -- still consuming any one-shot geometry marker left by a hidden frame.
        local any = false
        for container in pairs(containers) do
            if skipLiveGroup ~= true
                or not IsLiveGroupAuraFrame(container and container._msufA3ParentFrame) then
                local filterChanged = SyncCuratedBigDefensiveContainer(container)
                local update = container and container.UpdateAllAuras
                if type(update) == "function" then
                    if not filterChanged and A3._NativeContainerVisible(container) then update(container) end
                    if container._msufA3ForceManagedAuraGeometry == true
                        or container._msufA3ForceSpellIndicatorGeometry == true then
                        A3._SyncManagedAuraContainerGeometry(container, true)
                    end
                    any = true
                end
            end
        end
        if seedGroupAssist then
            A3._UpdateGroupAuraAssistState(unit, false, true, false, true)
        end
        return any
    end

    local any, spellRecreates, helpfulRecreates = false, nil, nil
    for container in pairs(containers) do
        local liveGroup = IsLiveGroupAuraFrame(container and container._msufA3ParentFrame)
        if skipLiveGroup == true and liveGroup then
            -- Geometry is addon-owned and can be repaired without touching the
            -- native Aura cache, assignment, enabled state, or shown state.
            any = A3._SyncManagedAuraContainerGeometry(container, true) or any
        else
            local lane = container and container._msufA3NativeLaneConfig
            local deferSpellRecreate = container and container._msufA3SpellIndicatorRoot == true
            local recreateHelpfulContainer = recreateHelpfulAuras == true
                and not deferSpellRecreate
                and ContainerOwnsHelpfulAuras(container, lane)
            if deferSpellRecreate then
                spellRecreates = spellRecreates or {}
                spellRecreates[#spellRecreates + 1] = container
                any = true
            elseif recreateHelpfulContainer then
                helpfulRecreates = helpfulRecreates or {}
                helpfulRecreates[#helpfulRecreates + 1] = container
                any = true
            else
                local filterChanged = SyncCuratedBigDefensiveContainer(container)
                if container and A3._ManagedAuraContainerSupportsGeometryRepair(container) then
                    -- Hidden containers cannot be repaired in this pass. Keep the
                    -- request on the container so its next visible/config sync consumes
                    -- it instead of trusting stale desired-geometry metadata.
                    if container._msufA3SpellIndicatorRoot == true then
                        container._msufA3ForceSpellIndicatorGeometry = true
                    else
                        container._msufA3ForceManagedAuraGeometry = true
                    end
                end
                if container and type(container.UpdateAllAuras) == "function" then
                    if not filterChanged and A3._NativeContainerVisible(container) then
                        container:UpdateAllAuras()
                    end
                    -- Zone/world transitions can desync a reused container while cache looks current.
                    -- Keep the normal cached fast path by applying geometry repair only once here.
                    if container._msufA3ForceManagedAuraGeometry == true
                        or container._msufA3ForceSpellIndicatorGeometry == true then
                        A3._SyncManagedAuraContainerGeometry(container, true)
                    end
                    any = true
                end
            end
        end
    end
    -- A full UpdateAllAuras parse can retain the existing frame for the same
    -- aura instance without reassigning its stable duration object. If that
    -- object captured the early-login near-zero state, long-lived buffs keep
    -- rendering 0.1 even though their tooltip already has the correct expiry.
    -- Recreate every registered owner that contains a HELPFUL lane on
    -- PLAYER_ENTERING_WORLD so pre-existing buffs on player, target, focus,
    -- boss and group units all receive fresh duration assignments. Mixed
    -- group owners are recreated as one native container; harmful-only owners
    -- are left alone. This stays entirely off UNIT_AURA and identity hotpaths.
    if helpfulRecreates then
        for i = 1, #helpfulRecreates do
            local container = helpfulRecreates[i]
            local root = container and container._msufA3Root
            local lane = container and container._msufA3NativeLaneConfig
            local parentFrame = container and container._msufA3ParentFrame
            if container and container._msufA3GroupSlotsRoot == true then
                any = RecreateGroupSlots(container) ~= nil or any
            elseif root and lane then
                any = ApplyLane(root, lane, parentFrame, true) ~= nil or any
            end
        end
    end
    -- Recreating unregisters the old container and registers a replacement in
    -- the same per-unit set. Do it after iteration so the set is never mutated
    -- under pairs(). This is the safe PTR path for forbidden native buttons.
    if spellRecreates then
        for i = 1, #spellRecreates do
            any = SpellIndicatorsRuntime.Recreate(spellRecreates[i]) ~= nil or any
        end
    end
    if seedGroupAssist then
        -- PLAYER_ENTERING_WORLD may replace helpful containers instead of
        -- reparsing the registered instance in place. Let an already-dirty
        -- assist revision finish normally in that exceptional recreation pass;
        -- all in-place direct refreshes can adopt the satisfied parse.
        A3._UpdateGroupAuraAssistState(
            unit, false, true, false, recreateHelpfulAuras ~= true)
    end
    return any
end

-- The player token can simultaneously own a standalone ClassPower candidate
-- slot and the Party self-frame. Player disposition/taxi events must refresh
-- the former without bypassing the latter's assist-gated state machine.
A3._DirectIdentityRefreshNonGroupUnitBase = function(unit)
    local byUnit = A3._directIdentityAuraContainers
    local containers = byUnit and byUnit[unit]
    if not containers then return false end
    local any = false
    for container in pairs(containers) do
        if not IsLiveGroupAuraFrame(container and container._msufA3ParentFrame) then
            local filterChanged = SyncCuratedBigDefensiveContainer(container)
            local update = container and container.UpdateAllAuras
            if type(update) == "function" then
                if not filterChanged and A3._NativeContainerVisible(container) then update(container) end
                if container._msufA3ForceManagedAuraGeometry == true
                    or container._msufA3ForceSpellIndicatorGeometry == true then
                    A3._SyncManagedAuraContainerGeometry(container, true)
                end
                any = true
            end
        end
    end
    return any
end

-- Selected only while at least one ordinary Unit-frame exact-ID owner exists.
-- The normal identity pass keeps gating, the existing native rebuild, and
-- geometry repair in the same per-unit owner loop. No UNIT_AURA branch, second
-- refresh, polling callback, or per-event table allocation is introduced.
A3._DirectIdentityRefreshUnitWithUnitAuraGate = function(
    unit, forceSpellIndicatorGeometry, recreateHelpfulAuras, skipLiveGroup)
    if not A3._UnitAuraIdentityUnitHasOwners(unit) then
        return A3._DirectIdentityRefreshUnitBase(
            unit, forceSpellIndicatorGeometry, recreateHelpfulAuras, skipLiveGroup)
    end
    if forceSpellIndicatorGeometry == true then
        -- World/login geometry repair is cold. Keep exact owners fail-closed
        -- across replacement, then seed the final registered instances once.
        A3._ApplyUnitAuraIdentityStateToUnit(unit, nil, false)
        local any = A3._DirectIdentityRefreshUnitBase(
            unit, forceSpellIndicatorGeometry, recreateHelpfulAuras, skipLiveGroup)
        local state = A3._RefreshUnitAuraIdentityState(unit)
        if state and state.assistKnown == true then
            A3._ScheduleUnitAuraIdentityReveal(unit, state.revision)
        end
        return any
    end

    local byUnit = A3._directIdentityAuraContainers
    local containers = byUnit and byUnit[unit]
    if not containers then return false end
    local state = A3._RefreshUnitAuraIdentityState(unit)
    local canAssist = state and state.canAssist
    local assistKnown = state and state.assistKnown == true
    local seedGroupAssist = skipLiveGroup ~= true
        and (unit == "player" or A3._directIdentityRefreshUnits[unit] ~= true)
    local any = false
    for container in pairs(containers) do
        if skipLiveGroup ~= true
            or not IsLiveGroupAuraFrame(container and container._msufA3ParentFrame) then
            local identityGated = A3._ContainerOwnsUnitAuraIdentityGate(container)
            local identityEligible = true
            if identityGated then
                A3._SetUnitAuraIdentityOwnerReady(container, canAssist, false)
                identityEligible = assistKnown
                    and A3._UnitAuraIdentityOwnerVisible(container, canAssist)
            end
            local filterChanged = SyncCuratedBigDefensiveContainer(container)
            local update = container and container.UpdateAllAuras
            if type(update) == "function" then
                if identityEligible and not filterChanged
                    and A3._NativeContainerVisible(container) then
                    update(container)
                end
                if container._msufA3ForceManagedAuraGeometry == true
                    or container._msufA3ForceSpellIndicatorGeometry == true then
                    A3._SyncManagedAuraContainerGeometry(container, true)
                end
                any = true
            end
        end
    end
    if state and state.assistKnown == true then
        A3._ScheduleUnitAuraIdentityReveal(unit, state.revision)
    end
    if seedGroupAssist then
        A3._UpdateGroupAuraAssistState(unit, false, true, false, true)
    end
    return any
end

A3._DirectIdentityRefreshNonGroupUnitWithUnitAuraGate = function(unit)
    if not A3._UnitAuraIdentityUnitHasOwners(unit) then
        return A3._DirectIdentityRefreshNonGroupUnitBase(unit)
    end
    local byUnit = A3._directIdentityAuraContainers
    local containers = byUnit and byUnit[unit]
    if not containers then return false end
    local state = A3._RefreshUnitAuraIdentityState(unit)
    local canAssist = state and state.canAssist
    local assistKnown = state and state.assistKnown == true
    local any = false
    for container in pairs(containers) do
        if not IsLiveGroupAuraFrame(container and container._msufA3ParentFrame) then
            local identityGated = A3._ContainerOwnsUnitAuraIdentityGate(container)
            local identityEligible = true
            if identityGated then
                A3._SetUnitAuraIdentityOwnerReady(container, canAssist, false)
                identityEligible = assistKnown
                    and A3._UnitAuraIdentityOwnerVisible(container, canAssist)
            end
            local filterChanged = SyncCuratedBigDefensiveContainer(container)
            local update = container and container.UpdateAllAuras
            if type(update) == "function" then
                if identityEligible and not filterChanged
                    and A3._NativeContainerVisible(container) then
                    update(container)
                end
                if container._msufA3ForceManagedAuraGeometry == true
                    or container._msufA3ForceSpellIndicatorGeometry == true then
                    A3._SyncManagedAuraContainerGeometry(container, true)
                end
                any = true
            end
        end
    end
    if state and state.assistKnown == true then
        A3._ScheduleUnitAuraIdentityReveal(unit, state.revision)
    end
    return any
end

A3._DirectIdentityRefreshUnit = A3._DirectIdentityRefreshUnitBase
A3._DirectIdentityRefreshNonGroupUnit = A3._DirectIdentityRefreshNonGroupUnitBase
A3._SyncUnitAuraIdentityRefreshRoute = function()
    local active = (A3._unitAuraIdentityOwnerCount or 0) > 0
    A3._DirectIdentityRefreshUnit = active
        and A3._DirectIdentityRefreshUnitWithUnitAuraGate
        or A3._DirectIdentityRefreshUnitBase
    A3._DirectIdentityRefreshNonGroupUnit = active
        and A3._DirectIdentityRefreshNonGroupUnitWithUnitAuraGate
        or A3._DirectIdentityRefreshNonGroupUnitBase
    return active
end

A3._DirectIdentityRefreshAll = function(
    groupOnly, forceSpellIndicatorGeometry, recreateHelpfulAuras, skipLiveGroup)
    local byUnit = A3._directIdentityAuraContainers
    if not byUnit then return false end
    -- A recreation can temporarily remove and then re-add a unit key while
    -- swapping its final registered owner. Snapshot the unit tokens first so
    -- mutating the registry cannot make pairs() skip another unit family.
    local units = {}
    for unit in pairs(byUnit) do
        units[#units + 1] = unit
    end
    local any = false
    for i = 1, #units do
        if groupOnly == true then
            any = A3._DirectGroupPresenceRefreshUnit(units[i]) or any
        else
            any = A3._DirectIdentityRefreshUnit(
                units[i], forceSpellIndicatorGeometry, recreateHelpfulAuras, skipLiveGroup) or any
        end
    end
    return any
end

A3._FlushScheduledDirectIdentityRefreshAll = function()
    A3._directIdentityRefreshTimerPending = nil
    if A3._directIdentityRefreshPending ~= true then return false end
    if InCombat() then return false end
    local groupOnly = A3._directIdentityRefreshGroupOnly == true
    local forceSpellIndicatorGeometry = A3._directIdentityRefreshForceSpellIndicatorGeometry == true
    local recreateHelpfulAuras = A3._directIdentityRefreshRecreateHelpfulAuras == true
    local skipLiveGroup = A3._directIdentityRefreshSkipLiveGroup == true
    A3._directIdentityRefreshPending = nil
    A3._directIdentityRefreshGroupOnly = nil
    A3._directIdentityRefreshForceSpellIndicatorGeometry = nil
    A3._directIdentityRefreshRecreateHelpfulAuras = nil
    A3._directIdentityRefreshSkipLiveGroup = nil
    if not A3._HasDirectIdentityRefreshContainers() then return false end
    A3._DirectIdentityRefreshAll(
        groupOnly, forceSpellIndicatorGeometry, recreateHelpfulAuras, skipLiveGroup)
end

A3._QueueDirectIdentityRefreshAllFlush = function()
    if A3._directIdentityRefreshPending ~= true
        or A3._directIdentityRefreshTimerPending == true
        or InCombat() then return false end
    A3._directIdentityRefreshTimerPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, A3._FlushScheduledDirectIdentityRefreshAll)
    else
        A3._FlushScheduledDirectIdentityRefreshAll()
    end
    return true
end

-- Presence and world/geometry work can be invalidated by the same transition
-- while combat is active. Resume both cold queues through one next-frame job so
-- a portal+zone+world burst never allocates two post-combat timers.
A3._FlushDeferredDirectIdentityColdWork = function()
    A3._directIdentityColdResumeTimerPending = nil
    if InCombat() then return false end
    local any = A3._FlushScheduledGroupAuraPresenceRefreshAll()
    any = A3._FlushScheduledDirectIdentityRefreshAll() or any
    return any
end

A3._QueueDeferredDirectIdentityColdWork = function()
    if A3._directIdentityColdResumeTimerPending == true
        or (A3._groupAuraPresenceRefreshAllPending ~= true
            and A3._directIdentityRefreshPending ~= true) then return false end
    A3._directIdentityColdResumeTimerPending = true
    -- Reserve both constituent queues for this shared callback. Any OOC event
    -- arriving before it runs only merges flags instead of allocating another
    -- one-shot timer.
    A3._groupAuraPresenceRefreshAllTimerPending = true
    A3._directIdentityRefreshTimerPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, A3._FlushDeferredDirectIdentityColdWork)
    else
        A3._FlushDeferredDirectIdentityColdWork()
    end
    return true
end

A3._ScheduleDirectIdentityRefreshAll = function(
    groupOnly, forceSpellIndicatorGeometry, skipLiveGroup)
    if not A3._HasDirectIdentityRefreshContainers() then return false end
    if A3._directIdentityRefreshPending == true then
        if groupOnly ~= true then A3._directIdentityRefreshGroupOnly = nil end
        if forceSpellIndicatorGeometry == true then
            A3._directIdentityRefreshForceSpellIndicatorGeometry = true
        end
        if skipLiveGroup ~= true then A3._directIdentityRefreshSkipLiveGroup = nil end
        A3._QueueDirectIdentityRefreshAllFlush()
        return true
    end
    A3._directIdentityRefreshPending = true
    A3._directIdentityRefreshGroupOnly = groupOnly == true
    A3._directIdentityRefreshForceSpellIndicatorGeometry = forceSpellIndicatorGeometry == true
    A3._directIdentityRefreshSkipLiveGroup = skipLiveGroup == true
    A3._QueueDirectIdentityRefreshAllFlush()
    return true
end

-- Non-group identity owners retain the existing burst coalescer. Group owners
-- take the narrower UnitCanAssist state path above, so player events can refresh
-- standalone candidate slots without touching Party self-frame containers.
A3._FlushScheduledDirectIdentityEventRefresh = function()
    A3._directIdentityEventRefreshPending = nil
    local units = A3._directIdentityEventRefreshUnits
    if not units then return false end
    local any = false
    for unit, mode in pairs(units) do
        units[unit] = nil
        if mode == "nonGroup" then
            any = A3._DirectIdentityRefreshNonGroupUnit(unit) or any
        else
            any = A3._DirectIdentityRefreshUnit(unit) or any
        end
    end
    return any
end

A3._ScheduleDirectIdentityEventRefresh = function(unit, nonGroupOnly)
    if type(unit) ~= "string" or unit == "" then return false end
    local containers = A3._directIdentityAuraContainers
    containers = containers and containers[unit]
    if not (containers and next(containers)) then return false end
    local units = A3._directIdentityEventRefreshUnits
    if not units then
        units = {}
        A3._directIdentityEventRefreshUnits = units
    end
    local requestedMode = nonGroupOnly == true and "nonGroup" or "all"
    if units[unit] ~= "all" then units[unit] = requestedMode end
    if A3._directIdentityEventRefreshPending == true then return true end
    A3._directIdentityEventRefreshPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, A3._FlushScheduledDirectIdentityEventRefresh)
    else
        A3._FlushScheduledDirectIdentityEventRefresh()
    end
    return true
end

-- UNIT_FLAGS covers many unrelated player states. For the missing flightpath
-- lifecycle, only the taxi landing edge matters: parsing while UnitOnTaxi is
-- true can still use the transient reaction, while the false edge is the first
-- useful point to restore the configured candidate-filter assignments. Cache
-- this cold state so ordinary player flag churn never schedules an aura parse.
A3._UpdateDirectIdentityPlayerTaxiState = function()
    local unitOnTaxi = _G.UnitOnTaxi
    if type(unitOnTaxi) ~= "function" then return nil, nil end
    local onTaxi = unitOnTaxi("player")
    if issecretvalue(onTaxi) == true or onTaxi == nil then return nil, nil end
    local current = onTaxi == true
    local previous = A3._directIdentityPlayerOnTaxi
    A3._directIdentityPlayerOnTaxi = current
    return previous, current
end

-- The shared driver is active exactly while at least one eligible native
-- container exists. Its event set follows the active unit families so a
-- group-only runtime never receives target/focus/boss identity callbacks.
local directIdentityRefreshEventFrame
local directIdentityRefreshRegisteredEvents = {}

-- Unit identity events can be noisy across every visible world unit. Keep the
-- group-token variants outside the shared global driver: stable four-token
-- RegisterUnitEvent shards match
-- Blizzard's 12.1 MAX_UNIT_TOKENS_IN_EVENT contract. A roster change only
-- rebuilds the affected cold topology; movement and foreign-unit flags never
-- enter Lua. A real flag edge on a registered raid token costs one cached
-- UnitCanAssist comparison and no aura rebuild when the value is unchanged.
A3._groupAuraAssistShardEvents = A3._groupAuraAssistShardEvents or {
    "UNIT_FLAGS", "UNIT_PHASE", "UNIT_CTR_OPTIONS", "UNIT_CONNECTION",
    "UNIT_OTHER_PARTY_CHANGED",
}
A3._GroupAuraAssistFlagBucket = function(unit)
    if issecretvalue(unit) == true or type(unit) ~= "string" then return nil end
    local partyIndex = tonumber(unit:match("^party(%d+)$"))
    if partyIndex and partyIndex >= 1 and partyIndex <= 4 then return 1 end
    local raidIndex = tonumber(unit:match("^raid(%d+)$"))
    if raidIndex and raidIndex >= 1 and raidIndex <= 40 then
        return 2 + math_floor((raidIndex - 1) / 4)
    end
    return nil
end

A3._ClearGroupAuraAssistFlagShards = function()
    local shards = A3._groupAuraAssistFlagShards
    if not shards then return false end
    for _, shard in pairs(shards) do
        shard:UnregisterAllEvents()
        shard._msufA3Units = nil
        shard._msufA3UnitSet = nil
        shard._msufA3AssistUnits = nil
        shard._msufA3AssistUnitSet = nil
        shard._msufA3Signature = nil
    end
    return true
end

A3._SyncGroupAuraAssistFlagShards = function()
    local desired = {}
    for unit, count in pairs(A3._directIdentityGroupOwnerCounts or {}) do
        if count > 0 then
            local bucket = A3._GroupAuraAssistFlagBucket(unit)
            if bucket then
                local record = desired[bucket]
                if not record then
                    record = { units = {}, assistUnits = {} }
                    desired[bucket] = record
                end
                record.units[#record.units + 1] = unit
            end
        end
    end
    for unit, count in pairs(A3._groupAuraAssistOwnerCounts or {}) do
        if count > 0 then
            local bucket = A3._GroupAuraAssistFlagBucket(unit)
            local record = bucket and desired[bucket]
            if record then record.assistUnits[#record.assistUnits + 1] = unit end
        end
    end

    local shards = A3._groupAuraAssistFlagShards
    if not shards then
        if next(desired) == nil then return false end
        shards = {}
        A3._groupAuraAssistFlagShards = shards
    end
    for bucket, record in pairs(desired) do
        local units, assistUnits = record.units, record.assistUnits
        table_sort(units)
        table_sort(assistUnits)
        local signature = table_concat(units, "\030") .. "\029"
            .. table_concat(assistUnits, "\030")
        local shard = shards[bucket]
        if not shard then
            shard = CreateFrame("Frame")
            shard:SetScript("OnEvent", function(self, event, unit, arg2)
                local knownUnit = issecretvalue(unit) ~= true and type(unit) == "string" and unit ~= ""
                if knownUnit then
                    if event ~= "UNIT_FLAGS"
                        and self._msufA3UnitSet and self._msufA3UnitSet[unit] then
                        if InCombat() then
                            if event == "UNIT_PHASE" or event == "UNIT_CTR_OPTIONS" then
                                A3._UpdateGroupAuraPresencePhaseState(unit, false)
                            elseif event == "UNIT_CONNECTION" then
                                A3._UpdateGroupAuraPresenceConnectionState(unit, arg2, false)
                            end
                            -- Map-ID, UnitInOtherParty and the composite scan
                            -- are deliberately cold and resume after combat.
                            A3._ScheduleGroupAuraPresenceRefreshAll(false, false)
                        else
                            A3._UpdateGroupAuraPresenceState(unit, false, false)
                        end
                    end
                    if self._msufA3AssistUnitSet and self._msufA3AssistUnitSet[unit] then
                        A3._UpdateGroupAuraAssistState(unit, false, false, false)
                    end
                    return
                end
                -- Restricted payload fallback stays bounded to this shard's at
                -- most four registered tokens and reads the transient edge now.
                local shardUnits = event == "UNIT_FLAGS"
                    and (self._msufA3AssistUnits or {}) or (self._msufA3Units or {})
                for i = 1, #shardUnits do
                    local shardUnit = shardUnits[i]
                    if event ~= "UNIT_FLAGS" then
                        if InCombat() then
                            if event == "UNIT_PHASE" or event == "UNIT_CTR_OPTIONS" then
                                A3._UpdateGroupAuraPresencePhaseState(shardUnit, false)
                            elseif event == "UNIT_CONNECTION" then
                                -- A restricted payload cannot safely be shared
                                -- across the shard. Fall back to one bounded
                                -- UnitIsConnected read per registered token.
                                A3._UpdateGroupAuraPresenceConnectionState(shardUnit, nil, false)
                            end
                        else
                            A3._UpdateGroupAuraPresenceState(shardUnit, false, false)
                        end
                    end
                    if self._msufA3AssistUnitSet and self._msufA3AssistUnitSet[shardUnit] then
                        A3._UpdateGroupAuraAssistState(shardUnit, false, false, false)
                    end
                end
                if event ~= "UNIT_FLAGS" and InCombat() then
                    A3._ScheduleGroupAuraPresenceRefreshAll(false, false)
                end
            end)
            shards[bucket] = shard
        end
        if shard._msufA3Signature ~= signature then
            shard:UnregisterAllEvents()
            shard._msufA3Units = units
            shard._msufA3UnitSet = {}
            for i = 1, #units do shard._msufA3UnitSet[units[i]] = true end
            shard._msufA3AssistUnits = assistUnits
            shard._msufA3AssistUnitSet = {}
            for i = 1, #assistUnits do
                shard._msufA3AssistUnitSet[assistUnits[i]] = true
            end
            shard._msufA3Signature = signature
            for eventIndex = 1, #A3._groupAuraAssistShardEvents do
                local event = A3._groupAuraAssistShardEvents[eventIndex]
                local eventUnits = event == "UNIT_FLAGS" and assistUnits or units
                if #eventUnits > 0 then
                    local registered = shard:RegisterUnitEvent(event, eventUnits)
                    if registered == false then
                        shard:UnregisterEvent(event)
                        local unpackUnits = _G.unpack or table.unpack
                        registered = unpackUnits and shard:RegisterUnitEvent(
                            event, unpackUnits(eventUnits, 1, #eventUnits)) or false
                        if registered == false then
                            -- Last-resort correctness fallback for a client rejecting
                            -- both documented forms. Foreign plain payloads are ignored.
                            shard:RegisterEvent(event)
                        end
                    end
                end
            end
        end
    end
    for bucket, shard in pairs(shards) do
        if desired[bucket] == nil then
            shard:UnregisterAllEvents()
            shard._msufA3Units = nil
            shard._msufA3UnitSet = nil
            shard._msufA3AssistUnits = nil
            shard._msufA3AssistUnitSet = nil
            shard._msufA3Signature = nil
        end
    end
    return next(desired) ~= nil
end

local function DirectIdentityBossUnit(unit)
    return unit == "boss1" or unit == "boss2" or unit == "boss3"
        or unit == "boss4" or unit == "boss5"
end

local function SetDirectIdentityRefreshEvent(frame, event, enabled, unit)
    local desiredMode = enabled == true and (unit and ("unit:" .. unit) or "global") or nil
    local currentMode = directIdentityRefreshRegisteredEvents[event]
    if currentMode == desiredMode then return end
    if currentMode ~= nil then
        frame:UnregisterEvent(event)
        directIdentityRefreshRegisteredEvents[event] = nil
    end
    if desiredMode ~= nil then
        if unit and type(frame.RegisterUnitEvent) == "function" then
            local registered = frame:RegisterUnitEvent(event, unit)
            if registered == false then
                frame:RegisterEvent(event)
                desiredMode = "global"
            end
        else
            frame:RegisterEvent(event)
        end
        directIdentityRefreshRegisteredEvents[event] = desiredMode
    end
end

local function SyncDirectIdentityRefreshEvents(frame)
    local byUnit = A3._directIdentityAuraContainers
    local hasAny, hasGroup, hasPlayer, hasTarget, hasFocus, hasBoss = false, false, false, false, false, false
    local hasGroupAssist = A3._HasGroupAuraAssistOwners()
    hasGroup = (A3._directIdentityGroupOwnerCount or 0) > 0
    if byUnit then
        for unit, containers in pairs(byUnit) do
            if containers and next(containers) then
                hasAny = true
                if not A3._IsGroupUnitToken(unit) then
                    if unit == "player" then
                        hasPlayer = true
                    elseif unit == "target" then
                        hasTarget = true
                    elseif unit == "focus" then
                        hasFocus = true
                    elseif DirectIdentityBossUnit(unit) then
                        hasBoss = true
                    end
                end
            else
                byUnit[unit] = nil
            end
        end
    end
    if not hasAny then return false end

    SetDirectIdentityRefreshEvent(frame, "PLAYER_ENTERING_WORLD", true)
    SetDirectIdentityRefreshEvent(frame, "ZONE_CHANGED_NEW_AREA", true)
    -- Cold Presence/world work can be queued by a transition that happens
    -- while combat lockdown is active. Keep one stable OOC resume callback;
    -- no combat-start callback or event-registration churn is introduced.
    SetDirectIdentityRefreshEvent(frame, "PLAYER_REGEN_ENABLED", hasAny)
    SetDirectIdentityRefreshEvent(frame, "ENTERED_DIFFERENT_INSTANCE_FROM_PARTY", hasGroup)
    SetDirectIdentityRefreshEvent(frame, "UNIT_FACTION", true)
    SetDirectIdentityRefreshEvent(frame, "GROUP_ROSTER_UPDATE", hasGroup)
    -- Group-token payloads stay in the four-token shards. A player-side
    -- phase/connection edge can change the relative presence of every member,
    -- so keep one filtered rare-event observer while live Group owners exist.
    SetDirectIdentityRefreshEvent(frame, "UNIT_PHASE", hasGroup, "player")
    SetDirectIdentityRefreshEvent(frame, "UNIT_CTR_OPTIONS", hasGroup, "player")
    SetDirectIdentityRefreshEvent(frame, "UNIT_CONNECTION", hasGroup, "player")
    SetDirectIdentityRefreshEvent(frame, "UNIT_OTHER_PARTY_CHANGED", hasGroup, "player")
    SetDirectIdentityRefreshEvent(frame, "PARTY_MEMBER_ENABLE", hasGroup)
    SetDirectIdentityRefreshEvent(frame, "PARTY_MEMBER_DISABLE", hasGroup)
    SetDirectIdentityRefreshEvent(frame, "PLAYER_CONTROL_LOST", hasPlayer or hasGroupAssist)
    if hasGroup then
        A3._SyncGroupAuraAssistFlagShards()
    else
        A3._ClearGroupAuraAssistFlagShards()
    end
    local playerOnTaxi
    if hasPlayer or hasGroupAssist then
        _, playerOnTaxi = A3._UpdateDirectIdentityPlayerTaxiState()
    end
    -- Group-unit flags are handled by the four-token shards above. The shared
    -- driver binds only the player observer, and only while a taxi transition
    -- is active/unknown, then removes it immediately on the landing edge.
    SetDirectIdentityRefreshEvent(frame, "UNIT_FLAGS",
        (hasPlayer or hasGroupAssist) and playerOnTaxi ~= false, "player")
    SetDirectIdentityRefreshEvent(frame, "PLAYER_TARGET_CHANGED", hasTarget)
    SetDirectIdentityRefreshEvent(frame, "PLAYER_FOCUS_CHANGED", hasFocus)
    SetDirectIdentityRefreshEvent(frame, "INSTANCE_ENCOUNTER_ENGAGE_UNIT", hasBoss)
    return true
end

local function DirectIdentityRefreshEventsAlreadyCover(unit)
    if directIdentityRefreshRegisteredEvents.PLAYER_ENTERING_WORLD == nil
        or directIdentityRefreshRegisteredEvents.ZONE_CHANGED_NEW_AREA == nil
        or directIdentityRefreshRegisteredEvents.PLAYER_REGEN_ENABLED == nil
        or directIdentityRefreshRegisteredEvents.UNIT_FACTION == nil then
        return false
    end
    if (A3._directIdentityGroupOwnerCount or 0) > 0
        and directIdentityRefreshRegisteredEvents.ENTERED_DIFFERENT_INSTANCE_FROM_PARTY == nil then
        return false
    end
    if (A3._directIdentityGroupOwnerCount or 0) > 0
        and directIdentityRefreshRegisteredEvents.GROUP_ROSTER_UPDATE == nil then
        return false
    end
    if (A3._directIdentityGroupOwnerCount or 0) > 0
        and (directIdentityRefreshRegisteredEvents.PARTY_MEMBER_ENABLE == nil
            or directIdentityRefreshRegisteredEvents.PARTY_MEMBER_DISABLE == nil) then
        return false
    end
    if unit == "player" then
        return directIdentityRefreshRegisteredEvents.PLAYER_CONTROL_LOST ~= nil
    end
    if unit == "target" then
        return directIdentityRefreshRegisteredEvents.PLAYER_TARGET_CHANGED ~= nil
    end
    if unit == "focus" then
        return directIdentityRefreshRegisteredEvents.PLAYER_FOCUS_CHANGED ~= nil
    end
    if DirectIdentityBossUnit(unit) then
        return directIdentityRefreshRegisteredEvents.INSTANCE_ENCOUNTER_ENGAGE_UNIT ~= nil
    end
    return true
end

A3._EnsureDirectIdentityRefreshFrame = function()
    if directIdentityRefreshEventFrame then return directIdentityRefreshEventFrame end
    local frame = A3._directIdentityAuraFrame
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", function(_, event, unit, arg2)
            if event == "PLAYER_REGEN_ENABLED" then
                if InCombat() then return end
                -- Drain every already-merged cold request through one shared
                -- next-frame job. Presence runs before the identity/geometry
                -- repair so composed output has its final OOC state first.
                A3._QueueDeferredDirectIdentityColdWork()
                return
            end
            if event == "PLAYER_CONTROL_LOST" then
                local _, isOnTaxi = A3._UpdateDirectIdentityPlayerTaxiState()
                local hasGroupAssist = A3._HasGroupAuraAssistOwners()
                if hasGroupAssist then
                    SyncDirectIdentityRefreshEvents(frame)
                else
                    SetDirectIdentityRefreshEvent(frame, "UNIT_FLAGS", isOnTaxi ~= false, "player")
                end
                -- Capture a transient false state as early as possible. This is
                -- a direct rare-event scan, not a recurring flight/combat loop.
                if hasGroupAssist then A3._UpdateAllGroupAuraAssistStates(false, false) end
                return
            end
            if A3._directIdentityRefreshAllEvents[event] == true then
                if event == "ENTERED_DIFFERENT_INSTANCE_FROM_PARTY" then
                    -- Payloadless portal notification: reconcile the hard
                    -- presence reasons once, but never invalidate native Aura
                    -- ownership. Identity filters are refreshed only if their
                    -- actual UnitCanAssist value changed.
                    A3._ScheduleGroupAuraPresenceRefreshAll(true, true)
                    return
                end
                local initialOrReload = event == "PLAYER_ENTERING_WORLD"
                    and (unit == true or arg2 == true)
                A3._ScheduleGroupAuraPresenceRefreshAll(true, true)
                if initialOrReload then
                    A3._directIdentityRefreshRecreateHelpfulAuras = true
                end
                -- Login/reload retains the pre-existing duration repair. Normal
                -- zone/instance transitions repair addon-owned geometry but
                -- explicitly skip every live Group AuraContainer.
                A3._ScheduleDirectIdentityRefreshAll(false, true, not initialOrReload)
                return
            end
            if event == "GROUP_ROSTER_UPDATE" then
                -- Roster bursts can reuse the same unit token with a different
                -- GUID while UnitCanAssist remains true. Keep the 6.06 assist
                -- identity path combat-live, but defer the new 6.07 map/other-
                -- instance reconciliation until OOC.
                if InCombat() then
                    A3._UpdateAllGroupAuraPresenceIdentityStates()
                    A3._ScheduleGroupAuraPresenceRefreshAll(true, false)
                    A3._ScheduleGroupAuraAssistRefreshAll(true, false)
                else
                    A3._ScheduleGroupAuraPresenceRefreshAll(true, true)
                end
                return
            end
            local groupAssistEvent = event == "UNIT_FACTION" or event == "UNIT_PHASE"
                or event == "UNIT_CTR_OPTIONS"
                or event == "UNIT_CONNECTION" or event == "UNIT_FLAGS"
                or event == "UNIT_OTHER_PARTY_CHANGED"
                or event == "PARTY_MEMBER_ENABLE" or event == "PARTY_MEMBER_DISABLE"
            if groupAssistEvent then
                local hasGroupAssist = A3._HasGroupAuraAssistOwners()
                local partyPresenceEvent = event == "PARTY_MEMBER_ENABLE"
                    or event == "PARTY_MEMBER_DISABLE"
                if partyPresenceEvent then
                    local knownGroupUnit = issecretvalue(unit) ~= true
                        and A3._IsGroupUnitToken(unit)
                    if knownGroupUnit then
                        A3._SetGroupAuraPresenceDisabled(
                            unit, event == "PARTY_MEMBER_DISABLE",
                            event == "PARTY_MEMBER_ENABLE")
                    elseif event == "PARTY_MEMBER_ENABLE" then
                        if InCombat() then
                            -- The restricted payload cannot identify the member.
                            -- Defer the bounded one-candidate latch release to the
                            -- same OOC group reconciliation as the broad scan.
                            A3._CaptureSingleGroupAuraPresenceDisabled()
                        else
                            A3._InvalidateSingleGroupAuraPresenceDisabled()
                        end
                    end
                    -- The payload is a useful directional hint, but Blizzard's
                    -- own PartyFrame treats these events group-wide. Reconcile
                    -- once without reparsing, disabling, or hiding a container.
                    A3._ScheduleGroupAuraPresenceRefreshAll(false)
                    if hasGroupAssist then
                        A3._UpdateAllGroupAuraAssistStates(false, false)
                    end
                    return
                end
                if issecretvalue(unit) == true or type(unit) ~= "string" or unit == "" then
                    -- The payload itself may be restricted even though the
                    -- registered party/raid tokens are ordinary strings. Read
                    -- those states now: deferring two cinematic flag events to
                    -- one final-value scan could otherwise miss the transient
                    -- false edge that makes the native filter stale.
                    if hasGroupAssist then A3._UpdateAllGroupAuraAssistStates(false, false) end
                    A3._ScheduleGroupAuraPresenceRefreshAll(false)
                    return
                end
                local taxiLanding, refreshNonGroup = false, event == "UNIT_FACTION"
                if event == "UNIT_FLAGS" and unit == "player" then
                    local wasOnTaxi, isOnTaxi = A3._UpdateDirectIdentityPlayerTaxiState()
                    taxiLanding = wasOnTaxi == true and isOnTaxi == false
                    refreshNonGroup = wasOnTaxi == nil or isOnTaxi == nil or taxiLanding
                    if isOnTaxi == false then
                        SetDirectIdentityRefreshEvent(frame, "UNIT_FLAGS", false)
                    end
                end

                if hasGroupAssist then
                    if unit == "player" then
                        -- A player disposition edge changes the observer side of
                        -- UnitCanAssist("player", raidN), so evaluate each active
                        -- assist-gated token once. Taxi landing forces one repair
                        -- even if a short false interval escaped the final cache.
                        if event ~= "UNIT_FLAGS" or refreshNonGroup then
                            A3._UpdateAllGroupAuraAssistStates(false, taxiLanding)
                        end
                    elseif A3._IsGroupUnitToken(unit) then
                        A3._UpdateGroupAuraAssistState(unit, false, false, false)
                    end
                end

                if event ~= "UNIT_FACTION" and event ~= "UNIT_FLAGS" then
                    if InCombat() then
                        if event == "UNIT_PHASE" or event == "UNIT_CTR_OPTIONS" then
                            if unit == "player" then
                                A3._UpdateAllGroupAuraPresencePhaseStates()
                            elseif A3._IsGroupUnitToken(unit) then
                                A3._UpdateGroupAuraPresencePhaseState(unit, false)
                            end
                        elseif event == "UNIT_CONNECTION" and A3._IsGroupUnitToken(unit) then
                            A3._UpdateGroupAuraPresenceConnectionState(unit, arg2, false)
                        end
                        A3._ScheduleGroupAuraPresenceRefreshAll(false, false)
                    elseif unit == "player" then
                        A3._ScheduleGroupAuraPresenceRefreshAll(false)
                    elseif A3._IsGroupUnitToken(unit) then
                        A3._UpdateGroupAuraPresenceState(unit, false, false)
                    end
                end

                if refreshNonGroup and (unit == "player" or not A3._IsGroupUnitToken(unit)) then
                    A3._ScheduleDirectIdentityEventRefresh(unit, unit == "player")
                end
                return
            end
            local units = A3._directIdentityEventUnits[event]
            if not units then return end
            for i = 1, #units do
                A3._DirectIdentityRefreshUnit(units[i])
            end
        end)
        A3._directIdentityAuraFrame = frame
    end
    directIdentityRefreshEventFrame = frame
    return frame
end

A3._RegisterUnitAuraIdentityOwner = function(container, unit)
    local owners = A3._unitAuraIdentityOwnersByUnit
    if not owners then
        owners = {}
        A3._unitAuraIdentityOwnersByUnit = owners
    end
    local set = owners[unit]
    if not set then
        set = {}
        owners[unit] = set
    end
    if set[container] == true then return false end
    set[container] = true
    A3._unitAuraIdentityOwnerCount = (A3._unitAuraIdentityOwnerCount or 0) + 1
    A3._EnsureUnitAuraIdentityState(unit)
    A3._SyncUnitAuraIdentityRefreshRoute()
    return true
end

A3._UnregisterUnitAuraIdentityOwner = function(container, unit)
    local owners = A3._unitAuraIdentityOwnersByUnit
    local set = owners and owners[unit]
    if not (set and set[container] == true) then return false end
    set[container] = nil
    A3._unitAuraIdentityOwnerCount = math_max(0, (A3._unitAuraIdentityOwnerCount or 0) - 1)
    if not next(set) then
        owners[unit] = nil
        local states = A3._unitAuraIdentityState
        if states then states[unit] = nil end
        local revealUnits = A3._unitAuraIdentityRevealUnits
        if revealUnits then revealUnits[unit] = nil end
    end
    A3._SyncUnitAuraIdentityRefreshRoute()
    return true
end

A3._RegisterDirectIdentityRefreshContainer = function(container)
    local unit = container and container.unit
    if not container or container._msufA3SkipDirectIdentityRefresh == true
        or not A3._DirectIdentityRefreshUnitEligible(unit) then
        A3._UnregisterDirectIdentityRefreshContainer(container)
        return false
    end
    if not A3._directIdentityAuraContainers then
        A3._directIdentityAuraContainers = {}
        A3._groupAuraAssistOwnerCount = 0
        A3._directIdentityGroupOwnerCount = 0
        A3._directIdentityGroupOwnerCounts = {}
    end
    A3._groupAuraAssistOwnerCounts = A3._groupAuraAssistOwnerCounts or {}
    A3._directIdentityGroupOwnerCounts = A3._directIdentityGroupOwnerCounts or {}
    local oldUnit = container._msufA3DirectIdentityUnit
    local oldAssistGated = container._msufA3DirectIdentityAssistGated == true
    local oldGroupOwner = container._msufA3DirectIdentityGroupOwner == true
    local oldUnitIdentityGated = container._msufA3DirectIdentityUnitGated == true
    local unitIdentityGated = A3._ContainerOwnsUnitAuraIdentityGate(container)
    local topologyChanged = false
    local ownerCounts = A3._groupAuraAssistOwnerCounts
    local groupCounts = A3._directIdentityGroupOwnerCounts
    local oldUnitAssistCountBefore = oldUnit and (ownerCounts[oldUnit] or 0) or 0
    local newUnitAssistCountBefore = ownerCounts[unit] or 0
    local totalAssistCountBefore = A3._groupAuraAssistOwnerCount or 0
    local totalGroupCountBefore = A3._directIdentityGroupOwnerCount or 0
    local oldUnitGroupCountBefore = oldUnit and (groupCounts[oldUnit] or 0) or 0
    local newUnitGroupCountBefore = groupCounts[unit] or 0
    if oldUnit and oldUnit ~= unit then
        local oldSet = A3._directIdentityAuraContainers[oldUnit]
        if oldSet then
            oldSet[container] = nil
            if not next(oldSet) then
                A3._directIdentityAuraContainers[oldUnit] = nil
                topologyChanged = true
            end
        end
    end
    local set = A3._directIdentityAuraContainers[unit]
    if not set then
        set = {}
        A3._directIdentityAuraContainers[unit] = set
        topologyChanged = true
    end
    set[container] = true
    container._msufA3DirectIdentityUnit = unit
    if oldUnitIdentityGated and (oldUnit ~= unit or not unitIdentityGated) then
        A3._UnregisterUnitAuraIdentityOwner(container, oldUnit)
    end
    if unitIdentityGated and (not oldUnitIdentityGated or oldUnit ~= unit) then
        A3._RegisterUnitAuraIdentityOwner(container, unit)
    end
    local assistGated = A3._ContainerOwnsGroupAuraAssistGate(container)
    local groupOwner = IsLiveGroupAuraFrame(container._msufA3ParentFrame)
    container._msufA3DirectIdentityUnitGated = unitIdentityGated == true
    container._msufA3DirectIdentityAssistGated = assistGated == true
    container._msufA3DirectIdentityGroupOwner = groupOwner == true
    if oldAssistGated and (oldUnit ~= unit or not assistGated) then
        ownerCounts[oldUnit] = math_max(0, (ownerCounts[oldUnit] or 0) - 1)
        if ownerCounts[oldUnit] == 0 then ownerCounts[oldUnit] = nil end
        A3._groupAuraAssistOwnerCount = math_max(0, (A3._groupAuraAssistOwnerCount or 0) - 1)
    end
    if assistGated and (not oldAssistGated or oldUnit ~= unit) then
        ownerCounts[unit] = (ownerCounts[unit] or 0) + 1
        A3._groupAuraAssistOwnerCount = (A3._groupAuraAssistOwnerCount or 0) + 1
    end
    if oldGroupOwner and (oldUnit ~= unit or not groupOwner) then
        groupCounts[oldUnit] = math_max(0, (groupCounts[oldUnit] or 0) - 1)
        if groupCounts[oldUnit] == 0 then groupCounts[oldUnit] = nil end
        A3._directIdentityGroupOwnerCount = math_max(
            0, (A3._directIdentityGroupOwnerCount or 0) - 1)
    end
    if groupOwner and (not oldGroupOwner or oldUnit ~= unit) then
        groupCounts[unit] = (groupCounts[unit] or 0) + 1
        A3._directIdentityGroupOwnerCount = (A3._directIdentityGroupOwnerCount or 0) + 1
    end
    local assistUnitTopologyChanged = oldUnit ~= nil
        and ((oldUnitAssistCountBefore == 0) ~= ((ownerCounts[oldUnit] or 0) == 0))
        or ((newUnitAssistCountBefore == 0) ~= ((ownerCounts[unit] or 0) == 0))
    local assistGlobalTopologyChanged = (totalAssistCountBefore == 0)
        ~= ((A3._groupAuraAssistOwnerCount or 0) == 0)
    local groupGlobalTopologyChanged = (totalGroupCountBefore == 0)
        ~= ((A3._directIdentityGroupOwnerCount or 0) == 0)
    local groupUnitTopologyChanged = oldUnit ~= nil
        and ((oldUnitGroupCountBefore == 0) ~= ((groupCounts[oldUnit] or 0) == 0))
        or ((newUnitGroupCountBefore == 0) ~= ((groupCounts[unit] or 0) == 0))
    if oldUnit and oldUnit ~= unit and oldAssistGated
        and not A3._GroupAuraAssistUnitHasOwners(oldUnit) then
        local states = A3._groupAuraAssistState
        if states then states[oldUnit] = nil end
    end
    if oldUnit == unit and oldAssistGated and not assistGated
        and not A3._GroupAuraAssistUnitHasOwners(unit) then
        local states = A3._groupAuraAssistState
        if states then states[unit] = nil end
    end
    if oldUnit and oldUnit ~= unit and not A3._GroupAuraPresenceUnitHasOwners(oldUnit) then
        local states = A3._groupAuraPresenceState
        if states then states[oldUnit] = nil end
    end
    if oldUnit == unit and oldGroupOwner and not groupOwner
        and not A3._GroupAuraPresenceUnitHasOwners(unit) then
        local states = A3._groupAuraPresenceState
        if states then states[unit] = nil end
    end
    local frame = A3._EnsureDirectIdentityRefreshFrame()
    -- A visible boss frame commonly registers three native lanes, and five
    -- bosses can appear in the same callback. The first lane establishes the
    -- shared boss event; rescanning every per-unit container and repeating all
    -- five RegisterEvent state checks for the other fourteen lanes is pure
    -- lifecycle overhead. Additions can take this O(1) coverage gate. Rebinds
    -- that removed a unit family still use the authoritative topology scan so
    -- no obsolete target/focus/boss subscription can survive.
    if topologyChanged or assistUnitTopologyChanged or assistGlobalTopologyChanged
        or groupGlobalTopologyChanged or groupUnitTopologyChanged
        or (assistGated and directIdentityRefreshRegisteredEvents.GROUP_ROSTER_UPDATE == nil)
        or not DirectIdentityRefreshEventsAlreadyCover(unit) then
        SyncDirectIdentityRefreshEvents(frame)
    end
    if groupOwner then
        local presenceState = A3._groupAuraPresenceState
            and A3._groupAuraPresenceState[unit]
        if presenceState and presenceState.initialized == true then
            A3._ApplyGroupAuraPresenceFrame(container._msufA3ParentFrame,
                presenceState.present ~= false, unit, presenceState.revision or 0)
            A3._ApplyGroupAuraPresenceContainer(container,
                presenceState.present ~= false,
                A3._groupAuraAssistState and A3._groupAuraAssistState[unit])
        end
    end
    if unitIdentityGated then A3._SeedUnitAuraIdentityOwner(container, unit) end
    return true
end

A3._UnregisterDirectIdentityRefreshContainer = function(container)
    local unit = container and container._msufA3DirectIdentityUnit
    if not unit then return end
    local wasAssistGated = container._msufA3DirectIdentityAssistGated == true
    local wasGroupOwner = container._msufA3DirectIdentityGroupOwner == true
    local wasUnitIdentityGated = container._msufA3DirectIdentityUnitGated == true
    local unitAssistCountBefore = A3._groupAuraAssistOwnerCounts
        and (A3._groupAuraAssistOwnerCounts[unit] or 0) or 0
    local totalAssistCountBefore = A3._groupAuraAssistOwnerCount or 0
    local totalGroupCountBefore = A3._directIdentityGroupOwnerCount or 0
    local unitGroupCountBefore = A3._directIdentityGroupOwnerCounts
        and (A3._directIdentityGroupOwnerCounts[unit] or 0) or 0
    local topologyChanged = false
    local byUnit = A3._directIdentityAuraContainers
    local set = byUnit and byUnit[unit]
    if set then
        set[container] = nil
        if not next(set) then
            byUnit[unit] = nil
            topologyChanged = true
            if unit == "player" then A3._directIdentityPlayerOnTaxi = nil end
        end
    end
    container._msufA3DirectIdentityUnit = nil
    container._msufA3DirectIdentityAssistGated = nil
    container._msufA3DirectIdentityGroupOwner = nil
    container._msufA3DirectIdentityUnitGated = nil
    if wasUnitIdentityGated then A3._UnregisterUnitAuraIdentityOwner(container, unit) end
    if wasAssistGated then
        local ownerCounts = A3._groupAuraAssistOwnerCounts
        if ownerCounts then
            ownerCounts[unit] = math_max(0, (ownerCounts[unit] or 0) - 1)
            if ownerCounts[unit] == 0 then ownerCounts[unit] = nil end
        end
        A3._groupAuraAssistOwnerCount = math_max(0, (A3._groupAuraAssistOwnerCount or 0) - 1)
    end
    if wasGroupOwner then
        local groupCounts = A3._directIdentityGroupOwnerCounts
        if groupCounts then
            groupCounts[unit] = math_max(0, (groupCounts[unit] or 0) - 1)
            if groupCounts[unit] == 0 then groupCounts[unit] = nil end
        end
        A3._directIdentityGroupOwnerCount = math_max(
            0, (A3._directIdentityGroupOwnerCount or 0) - 1)
    end
    local assistUnitTopologyChanged = wasAssistGated and unitAssistCountBefore == 1
    local assistGlobalTopologyChanged = wasAssistGated and totalAssistCountBefore == 1
    local groupGlobalTopologyChanged = wasGroupOwner and totalGroupCountBefore == 1
    local groupUnitTopologyChanged = wasGroupOwner and unitGroupCountBefore == 1
    if wasAssistGated and not A3._GroupAuraAssistUnitHasOwners(unit) then
        local states = A3._groupAuraAssistState
        if states then states[unit] = nil end
        local refreshUnits = A3._groupAuraAssistRefreshUnits
        if refreshUnits then refreshUnits[unit] = nil end
        local revealUnits = A3._groupAuraAssistRevealUnits
        if revealUnits then revealUnits[unit] = nil end
    end
    if wasGroupOwner and not A3._GroupAuraPresenceUnitHasOwners(unit) then
        local states = A3._groupAuraPresenceState
        if states then states[unit] = nil end
    end
    if not A3._HasDirectIdentityRefreshContainers() then
        A3._directIdentityRefreshPending = nil
        A3._directIdentityRefreshTimerPending = nil
        A3._directIdentityColdResumeTimerPending = nil
        A3._directIdentityRefreshGroupOnly = nil
        A3._directIdentityRefreshForceSpellIndicatorGeometry = nil
        A3._directIdentityRefreshRecreateHelpfulAuras = nil
        A3._directIdentityRefreshSkipLiveGroup = nil
        A3._groupAuraAssistState = nil
        A3._groupAuraAssistOwnerCount = 0
        A3._groupAuraAssistOwnerCounts = nil
        A3._directIdentityGroupOwnerCount = 0
        A3._directIdentityGroupOwnerCounts = nil
        A3._groupAuraPresenceState = nil
        A3._groupAuraPresenceRefreshAllPending = nil
        A3._groupAuraPresenceRefreshAllTimerPending = nil
        A3._groupAuraPresenceRefreshAllCheckIdentity = nil
        A3._groupAuraPresenceRefreshAllCheckAssist = nil
        A3._groupAuraPresenceRefreshAllEnableCandidate = nil
        A3._groupAuraPresenceRefreshAllEnableCandidateRevision = nil
        A3._groupAuraPresenceRefreshAllEnableCandidateState = nil
        A3._groupAuraAssistRefreshUnits = nil
        A3._groupAuraAssistRefreshPending = nil
        A3._groupAuraAssistRevealUnits = nil
        A3._groupAuraAssistRevealPending = nil
        A3._groupAuraAssistRefreshAllPending = nil
        A3._groupAuraAssistRefreshAllCheckIdentity = nil
        A3._groupAuraAssistRefreshAllForce = nil
        A3._unitAuraIdentityOwnersByUnit = nil
        A3._unitAuraIdentityOwnerCount = 0
        A3._unitAuraIdentityState = nil
        A3._unitAuraIdentityRevealUnits = nil
        A3._SyncUnitAuraIdentityRefreshRoute()
        local frame = A3._directIdentityAuraFrame
        if frame then frame:UnregisterAllEvents() end
        A3._ClearGroupAuraAssistFlagShards()
        directIdentityRefreshRegisteredEvents = {}
        directIdentityRefreshEventFrame = nil
    elseif topologyChanged or assistUnitTopologyChanged or assistGlobalTopologyChanged
        or groupGlobalTopologyChanged or groupUnitTopologyChanged then
        SyncDirectIdentityRefreshEvents(directIdentityRefreshEventFrame)
    end
end

RegisterNativeContainer = function(container, forceRefresh)
    if not container then return false end
    if forceRefresh ~= true and container._msufA3NativeRegistered == true then
        -- Reuse paths apply geometry after rebinding, which restores the lane's
        -- configured alpha. Re-seed only registered exact-ID Unit owners here
        -- so that cold layout/config work cannot expose the wrong polarity.
        if container._msufA3DirectIdentityUnitGated == true then
            A3._SeedUnitAuraIdentityOwner(container, container.unit)
        end
        if A3.AuraNameResolver then A3.AuraNameResolver.SyncContainer(container) end
        return true
    end
    if not A3._NativeContainerVisible(container) then
        container._msufA3NativeRegistrationPending = true
        return true
    end

    -- Enable the container so Blizzard registers it for UNIT_AURA on this unit
    -- (ShouldRegisterForEvents = IsVisible() and IsEnabled()). Without this the
    -- container never self-updates: a hidden->shown transition reparses via
    -- OnShow, but a same-token target swap or an aura expiring/refreshing does
    -- not, so content goes stale. Enabling routes all steady-state updates
    -- through the container's cheap incremental delta path (added/updated/
    -- removed) instead of an MSUF forced reparse. SetEnabled is a secure
    -- delegate (safe to call directly) and is idempotent.
    container:SetEnabled(true)
    A3._RegisterDirectIdentityRefreshContainer(container)
    container._msufA3NativeRegistered = true
    container._msufA3NativeRegistrationPending = nil
    if A3.AuraNameResolver then A3.AuraNameResolver.SyncContainer(container) end
    return true
end

A3._UnregisterNativeContainer = function(container)
    if not container then return true end
    if A3.AuraNameResolver then A3.AuraNameResolver.UnregisterContainer(container) end
    A3._UnregisterDirectIdentityRefreshContainer(container)
    container:SetEnabled(false)
    container._msufA3NativeRegistered = nil
    container._msufA3NativeRegistrationPending = nil
    return true
end

A3._RebindNativeContainerUnit = function(container, unit)
    if not (container and type(unit) == "string" and unit ~= "") then return false end
    local changed = container.unit ~= unit or (type(container.GetUnit) == "function" and container:GetUnit() ~= unit)
    container.unit = unit
    if changed and type(container.SetUnit) == "function" then
        container:SetUnit(unit)
    end
    A3._RegisterDirectIdentityRefreshContainer(container)
    return changed
end

A3._CreateNativeLane = function(root, lane, parentFrame)
    if not EnsureBlizzardAuraContainerLoaded() then
        A3.nativeAuraRuntimeAvailable = false
        A3.nativeAuraRuntimeError = AURA_CONTAINER_ADDON .. " is not loaded: " .. tostring(A3.nativeAuraRuntimeLoadError or "unknown")
        return nil
    end

    -- Blizzard sizes AuraContainers to their current visible contents. Keep the
    -- user-selected MSUF anchor on a fixed addon-owned host so that native
    -- layout can remain completely unwrapped without shifting right/bottom
    -- anchored lanes as aura counts change.
    parentFrame = ResolveLaneParentFrame(parentFrame, lane)
    local host = CreateFrame("Frame", nil,
        lane and lane.portraitOverlay == true and parentFrame or root)
    if not host then return nil end
    -- Birth-order levels: the host receives its final strata/level BEFORE the
    -- container (and later its batch-created AuraButtons) are born as its
    -- children. Children spawn at parent level + 1, so the whole chain starts
    -- at the correct absolute level without ever needing a SetFrameLevel call
    -- on the sealed intrinsic objects. Layer/strata changes recreate the lane
    -- (tracking signature), which re-runs this birth ordering.
    if parentFrame then
        local hostStrata = ResolveFrameStrata(parentFrame, lane and lane.strata)
        if hostStrata then SyncFrameStrata(host, hostStrata) end
        if host.SetFrameLevel and parentFrame.GetFrameLevel then
            host:SetFrameLevel(ManagedLaneFrameLevel(parentFrame, lane))
        end
    end
    local container = CreateNativeAuraContainer(root, host)
    if not container then
        if host.Hide then host:Hide() end
        return nil
    end
    container._msufA3LayoutHost = host
    container._msufA3HostParented = true
    if lane and lane.customPriority == true then
        return CreateManagedPriorityNativeLane(container, lane, parentFrame)
    end
    return CreateManagedNativeLane(container, lane, parentFrame)
end

A3._HideLane = function(lane)
    if lane then
        A3._UnregisterNativeContainer(lane)
        lane:Hide()
        if lane._msufA3LayoutHost and lane._msufA3LayoutHost.Hide then
            lane._msufA3LayoutHost:Hide()
        end
        local config = lane._msufA3NativeLaneConfig
        local holder = config and config.portraitOverlay == true and lane._msufA3ParentFrame
        if config and config.portraitPositionWhenDisabled == true then
            local frame = holder and holder.GetParent and holder:GetParent()
            local element = UF and UF.elements and UF.elements.Portrait
            if frame and element and type(element.ReleasePositionAnchor) == "function" then
                element.ReleasePositionAnchor(frame)
            end
        end
    end
end

A3._NormalLaneForRootKey = function(lanes, rootKey)
    if type(lanes) ~= "table" or rootKey == nil then return nil end
    local order = A3._normalAuraLaneOrder
    for i = 1, #order do
        local lane = lanes[order[i]]
        if lane and lane.rootKey == rootKey then return lane end
    end
end

local function GroupSlotsOwnsLane(groupSlots, lane)
    if not (groupSlots and lane) then return false end
    local owned = groupSlots.allOwnedLaneKeys or groupSlots.ownedLaneKeys
    return owned and owned[lane.rootKey] == true or false
end

A3._HideNormalLaneContainers = function(root, lanes, groupSlots)
    if not root then return end
    for i = 1, #NORMAL_LANE_ROOT_KEYS do
        local key = NORMAL_LANE_ROOT_KEYS[i]
        local lane = A3._NormalLaneForRootKey(lanes, key)
        if GroupSlotsOwnsLane(groupSlots, lane) or not (lane and lane.enabled == true) then
            A3._HideLane(root[key])
            root[key] = nil
        end
    end
end

A3._ApplyNormalLaneContainers = function(root, lanes, parentFrame, forceRecreate, groupSlots)
    A3._HideNormalLaneContainers(root, lanes, groupSlots)
    if type(lanes) ~= "table" then return true, false end
    local ok, any = true, false
    local order = A3._normalAuraLaneOrder
    for i = 1, #order do
        local lane = lanes[order[i]]
        if lane and lane.enabled == true and not GroupSlotsOwnsLane(groupSlots, lane) then
            any = true
            if not ApplyLane(root, lane, parentFrame, forceRecreate) then ok = false end
        end
    end
    return ok, any
end

ApplyLane = function(root, lane, parentFrame, forceRecreate)
    if not (root and lane and lane.enabled) then return nil end
    local key = lane.rootKey
    local trackingSignature = lane._msufA3TrackingSignature or LaneTrackingSignature(lane)
    local structuralSignature = lane._msufA3StructuralSignature or LaneStructuralSignature(lane)
    local layoutSignature = lane._msufA3LayoutSignature or LaneLayoutSignature(lane)
    local nativeFilter, _, candidateFilterSignature = EffectiveLaneFilters(lane)
    local current = root[key]
    if forceRecreate ~= true and current and current._msufA3StructuralSignature == structuralSignature then
        A3._RebindNativeContainerUnit(current, lane.unit)
        if current._msufA3PriorityAuraGroups == true then
            SyncContainerGeometry(current, lane, parentFrame)
            current:Show()
            if not RegisterNativeContainer(current) then return nil end
            current._msufA3TrackingSignature = trackingSignature
            current._msufA3StructuralSignature = structuralSignature
            current._msufA3LayoutSignature = layoutSignature
            return current
        end
        local refresh = false
        local layoutChanged = current._msufA3LayoutSignature ~= layoutSignature
        UpdateAuraGroupEffectiveFilters(current, lane)
        if current._msufA3MaxFrameCount ~= lane.max then
            current:SetAuraGroupMaxFrameCount(current._msufA3ManagedGroupKey, lane.max)
            current._msufA3MaxFrameCount = lane.max
            refresh = true
        end
        local sortSignature = AuraSortSignature(lane)
        if current._msufA3SortSignature ~= sortSignature then
            local sortMethod, sortDirection = AuraSortEnums(lane)
            current:SetAuraGroupSortMethod(current._msufA3ManagedGroupKey, sortMethod, sortDirection)
            current._msufA3SortSignature = sortSignature
        end
        if layoutChanged then
            ApplyManagedAuraGroupLayout(current, current._msufA3ManagedGroupKey, lane)
        end
        SyncContainerGeometry(current, lane, parentFrame)
        current:Show()
        if not RegisterNativeContainer(current) then return nil end
        if refresh == true and A3._NativeContainerVisible(current) and type(current.UpdateAllAuras) == "function" then
            current:UpdateAllAuras()
        end
        current._msufA3TrackingSignature = trackingSignature
        current._msufA3StructuralSignature = structuralSignature
        current._msufA3LayoutSignature = layoutSignature
        return current
    end
    A3._HideLane(current)
    root[key] = nil
    current = A3._CreateNativeLane(root, lane, parentFrame)
    if current then
        current._msufA3TrackingSignature = trackingSignature
        current._msufA3StructuralSignature = structuralSignature
        current._msufA3LayoutSignature = layoutSignature
        current._msufA3MaxFrameCount = lane.max
        current._msufA3FilterString = nativeFilter
        current._msufA3CandidateFilterSignature = candidateFilterSignature
        root[key] = current
    end
    return current
end

local function ApplyDispelSensor(root, sensor, parentFrame, forceRecreate)
    if not (root and sensor and sensor.enabled) then return nil end
    local key = sensor.rootKey
    local structuralSignature = sensor._msufA3StructuralSignature or SensorStructuralSignature(sensor)
    local layoutSignature = sensor._msufA3LayoutSignature or SensorLayoutSignature(sensor)
    local current = root[key]
    if forceRecreate ~= true and current and current._msufA3StructuralSignature == structuralSignature then
        A3._RebindNativeContainerUnit(current, sensor.unit)
        local filters = current._msufA3SensorSlotFilterStrings or {}
        current._msufA3SensorSlotFilterStrings = filters
        for i = 1, math_max(1, sensor.max or 1) do
            local slotKey = ManagedAuraKey(sensor) .. "_" .. tostring(i)
            if filters[slotKey] ~= sensor.nativeFilter then
                current:SetAuraSlotFilterString(slotKey, sensor.nativeFilter)
                filters[slotKey] = sensor.nativeFilter
            end
        end
        SyncDispelSensorGeometry(current, sensor, parentFrame)
        current:Show()
        if not RegisterNativeContainer(current) then return nil end
        current._msufA3StructuralSignature = structuralSignature
        current._msufA3LayoutSignature = layoutSignature
        return current
    end
    A3._HideLane(current)
    root[key] = nil
    current = CreateNativeDispelSensor(root, sensor, parentFrame)
    if current then
        current._msufA3StructuralSignature = structuralSignature
        current._msufA3LayoutSignature = layoutSignature
        sensor._msufA3StructuralSignature = structuralSignature
        sensor._msufA3LayoutSignature = layoutSignature
        root[key] = current
    end
    return current
end

local function ApplyDispelSensorRoot(root, sensorRoot, parentFrame, forceRecreate)
    if not (root and sensorRoot and sensorRoot.enabled == true and sensorRoot.sensorRoot == true) then return nil end
    local key = sensorRoot.rootKey or "DispelSensor"
    local structuralSignature = sensorRoot._msufA3StructuralSignature
    local layoutSignature = sensorRoot._msufA3LayoutSignature
    local current = root[key]
    if forceRecreate ~= true and current and current._msufA3StructuralSignature == structuralSignature then
        A3._RebindNativeContainerUnit(current, sensorRoot.unit)
        UpdateDispelSensorRootSlots(current, sensorRoot)
        SyncDispelSensorRootGeometry(current, sensorRoot, parentFrame)
        current:Show()
        if not RegisterNativeContainer(current) then return nil end
        current._msufA3StructuralSignature = structuralSignature
        current._msufA3LayoutSignature = layoutSignature
        return current
    end
    A3._HideLane(current)
    root[key] = nil
    current = CreateNativeDispelSensorRoot(root, sensorRoot, parentFrame)
    if current then
        current._msufA3StructuralSignature = structuralSignature
        current._msufA3LayoutSignature = layoutSignature
        root[key] = current
    end
    return current
end

local function HideGroupSlots(root, parentFrame, groupSlots, rootKeyOverride)
    local rootKey = rootKeyOverride or (groupSlots and groupSlots.rootKey) or "GroupSlots"
    local current = root[rootKey]
    if current and current._msufA3SpellIndicatorRoot == true then
        local currentConfig = current._msufA3NativeLaneConfig
        SpellIndicatorsRuntime.HideRootMissing(
            parentFrame, currentConfig and currentConfig.spellIndicatorRoot, current)
        SpellIndicatorsRuntime.ReleaseContainerEffects(current, parentFrame)
    end
    A3._HideLane(current)
    root[rootKey] = nil
end

local function ApplyGroupSlots(root, groupSlots, parentFrame, forceRecreate)
    if not (root and groupSlots) then return nil end
    local rootKey = groupSlots.rootKey or "GroupSlots"
    local structuralSignature = groupSlots._msufA3StructuralSignature
    local current = root[rootKey]
    local parked = parentFrame and parentFrame._msufA3GroupOwners
        and parentFrame._msufA3GroupOwners[rootKey]
    if not current and parked and parked._msufA3StructuralSignature == structuralSignature then
        current = parked
        current._msufA3Root = root
        root[rootKey] = current
    end
    local headerContainer = parentFrame and parentFrame.AuraContainer
    if rootKey == "GroupSlots"
        and not current
        and headerContainer
        and headerContainer._msufA3GroupSlotsRoot == true
        and headerContainer._msufA3StructuralSignature == structuralSignature then
        current = headerContainer
        current._msufA3Root = root
        root[rootKey] = current
    end
    if forceRecreate ~= true and current and current._msufA3StructuralSignature == structuralSignature then
        A3._RebindNativeContainerUnit(current, groupSlots.unit)
        local spellRoot = groupSlots.spellIndicatorRoot
        if spellRoot then SpellIndicatorsRuntime.UpdateSlots(current, spellRoot) end
        local sensorRoot = groupSlots.sensorRoot
        if sensorRoot then
            UpdateDispelSensorRootSlots(current, sensorRoot, spellRoot and #spellRoot.slots or 0)
        end
        local slotLanes = groupSlots.slotLanes
        if slotLanes then
            for i = 1, #slotLanes do UpdateGroupLaneSlot(current, slotLanes[i]) end
        end
        if groupSlots.flowLane then UpdateGroupFlowLane(current, groupSlots.flowLane) end
        SyncGroupSlotsGeometry(current, groupSlots, parentFrame)
        if current._msufA3LayoutHost then current._msufA3LayoutHost:Show() end
        current:Show()
        if not RegisterNativeContainer(current) then return nil end
        RememberGroupOwner(parentFrame, rootKey, current)
        current._msufA3StructuralSignature = structuralSignature
        return current
    end
    HideGroupSlots(root, parentFrame, groupSlots)
    current = CreateNativeGroupSlots(root, groupSlots, parentFrame)
    if current then
        current._msufA3StructuralSignature = structuralSignature
        root[rootKey] = current
        RememberGroupOwner(parentFrame, rootKey, current)
    end
    return current
end

RecreateGroupSlots = function(container)
    if not (container and container._msufA3GroupSlotsRoot == true) then return nil end
    local groupSlots = container._msufA3NativeLaneConfig
    local parentFrame = container._msufA3ParentFrame
    local root = container._msufA3Root or container:GetParent()
    if not (root and groupSlots and parentFrame) then return nil end
    local replacement = ApplyGroupSlots(root, groupSlots, parentFrame, true)
    if replacement then
        replacement._msufA3ForceManagedAuraGeometry = nil
        replacement._msufA3ForceSpellIndicatorGeometry = nil
    end
    return replacement
end

A3._ApplyGroupSlots = ApplyGroupSlots

SpellIndicatorsRuntime.Install({
    addonName = AURA_CONTAINER_ADDON,
    EnsureLoaded = EnsureBlizzardAuraContainerLoaded,
    CreateContainer = CreateNativeAuraContainer,
    ConfigureContainer = ConfigureNativeAuraContainer,
    RegisterContainer = RegisterNativeContainer,
    RebindUnit = A3._RebindNativeContainerUnit,
    IsVisible = A3._NativeContainerVisible,
    HideContainer = A3._HideLane,
    RecreateGroupSlots = RecreateGroupSlots,
    SetAssistAlpha = SetAssistAlpha,
    ValidateAuraButton = ValidateNativeAuraButtonContract,
    PrepareAuraButton = PrepareAuraButton,
})

local function RefreshNativeContainer(container, forceRefresh, lane, parentFrame)
    lane = lane or (container and container._msufA3NativeLaneConfig)
    if container then
        container._msufA3NativeLaneConfig = lane or container._msufA3NativeLaneConfig
        container._msufA3ParentFrame = parentFrame or container._msufA3ParentFrame
    end
    local forceGeometry = container and (container._msufA3ForceManagedAuraGeometry == true
        or container._msufA3ForceSpellIndicatorGeometry == true)
    if not A3._SyncManagedAuraContainerGeometry(container, forceGeometry) then return false end
    if not RegisterNativeContainer(container, forceRefresh == true) then return false end
    if not A3._NativeContainerVisible(container) then return true end
    if forceRefresh == true and type(container.UpdateAllAuras) == "function" then
        container:UpdateAllAuras()
    end
    return true
end

RefreshAppliedNativeRoot = function(root, forceRefresh)
    if not (root and root._msufA3NativeRoot == true and root._msufA3Applied == true) then return false end
    local cfg = root._msufA3Config
    local lanes = cfg and cfg.lanes or nil
    if not lanes then return false end

    local ok, any = true, false
    local parentFrame = root:GetParent()
    local group = cfg.group == true
    local groupSlots = group and GetGroupSlotsRootConfig(cfg)
    local order = A3._normalAuraLaneOrder
    for i = 1, #order do
        local lane = lanes[order[i]]
        if lane and lane.enabled == true and not GroupSlotsOwnsLane(groupSlots, lane) then
            any = true
            ok = RefreshNativeContainer(root[lane.rootKey], forceRefresh, lane, parentFrame) and ok
        end
    end
    if group then
        if groupSlots then
            any = true
            ok = RefreshNativeContainer(root[groupSlots.rootKey or "GroupSlots"], forceRefresh, groupSlots, parentFrame) and ok
            local secondary = groupSlots.secondaryRoot
            if secondary then
                ok = RefreshNativeContainer(root[secondary.rootKey], forceRefresh, secondary, parentFrame) and ok
            end
            local tertiary = groupSlots.tertiaryRoot
            if tertiary then
                ok = RefreshNativeContainer(root[tertiary.rootKey], forceRefresh, tertiary, parentFrame) and ok
            end
        end
    else
        local sensorRoot = GetDispelSensorRootConfig(cfg)
        if sensorRoot then
            any = true
            ok = RefreshNativeContainer(root.DispelSensor, forceRefresh, sensorRoot, parentFrame) and ok
        end
    end
    for i = group and 4 or 1, #EFFECT_ROOT_FIELDS do
        local spellIndicatorRoot = cfg[EFFECT_ROOT_FIELDS[i]]
        if SpellIndicatorsRuntime.IsRoot(spellIndicatorRoot) then
            any = true
            ok = RefreshNativeContainer(root[spellIndicatorRoot.rootKey], forceRefresh, spellIndicatorRoot, parentFrame) and ok
        end
    end
    if ok and any then A3.nativeAuraRuntimeError = nil end
    return ok and any
end

A3._RefreshAppliedNativeAuras = function(frame, forceRefresh)
    return RefreshAppliedNativeRoot(frame and frame.Auras, forceRefresh)
end

EnsureNativeAuraRefreshDriver = function()
    if A3._nativeAuraRefreshDriver then return A3._nativeAuraRefreshDriver end
    A3._nativeAuraRefreshDriver = true
    return true
end

local function HideState(frame)
    local root = frame and frame.Auras
    if not (root and root._msufA3NativeRoot) then return end
    A3._HideLane(root.Buffs)
    A3._HideLane(root.TrackedBuffs)
    A3._HideLane(root.Debuffs)
    A3._HideLane(root.Externals)
    A3._HideLane(root.CustomAuras1)
    A3._HideLane(root.CustomAuras2)
    A3._HideLane(root.CustomAuras3)
    A3._HideLane(root.CustomAuras4)
    A3._HideLane(root.DefensivePortrait)
    A3._HideLane(root.TargetDotPortrait)
    A3._HideLane(root.GroupSlots)
    A3._HideLane(root.GroupAuraFlow)
    A3._HideLane(root.GroupAuraAssist)
    A3._HideLane(root.GroupAuraHostile)
    A3._HideLane(root.DispelSensor)
    A3._HideLane(root.DispelBorderSensor)
    A3._HideLane(root.DispelOverlaySensor)
    A3._HideLane(root.DispelCornerSensor)
    A3._HideLane(root.SpellIndicators)
    A3._HideLane(root.SpellIndicatorsAssist)
    A3._HideLane(root.SpellIndicatorsHostile)
    A3._HideLane(root.LaneEffects)
    A3._HideLane(root.LaneEffectsAssist)
    A3._HideLane(root.LaneEffectsHostile)
    A3._HideLane(root.TargetDotEffects)
    A3._HideLane(root.TargetDotEffectsAssist)
    A3._HideLane(root.TargetDotEffectsHostile)
    SpellIndicatorsRuntime.HideAll(frame)
    root._msufA3Config = nil
    root._msufA3Applied = nil
    root._msufA3ConfigGen = nil
    root._msufA3VisualGen = nil
    root._msufA3AppliedUnit = nil
    root._msufA3FrameSpec = nil
    root:Hide()
    local unit = frame and frame.MSUFUnitKey
    if unit and A3._runtimeFrames and A3._runtimeFrames[unit] == frame then
        A3._runtimeFrames[unit] = nil
    end
    if unit and A3._unitFrameOwners and A3._unitFrameOwners[unit] == frame then
        A3._unitFrameOwners[unit] = nil
    end
    root.Buffs = nil
    root.TrackedBuffs = nil
    root.Debuffs = nil
    root.Externals = nil
    root.CustomAuras1 = nil
    root.CustomAuras2 = nil
    root.CustomAuras3 = nil
    root.CustomAuras4 = nil
    root.DefensivePortrait = nil
    root.TargetDotPortrait = nil
    root.GroupSlots = nil
    root.GroupAuraFlow = nil
    root.GroupAuraAssist = nil
    root.GroupAuraHostile = nil
    root.DispelSensor = nil
    root.DispelBorderSensor = nil
    root.DispelOverlaySensor = nil
    root.DispelCornerSensor = nil
    root.SpellIndicators = nil
    root.SpellIndicatorsAssist = nil
    root.SpellIndicatorsHostile = nil
    root.LaneEffects = nil
    root.LaneEffectsAssist = nil
    root.LaneEffectsHostile = nil
    root.TargetDotEffects = nil
    root.TargetDotEffectsAssist = nil
    root.TargetDotEffectsHostile = nil
    if frame then frame._msufA3UnitAuraOwner = nil end
end

local function ApplyConfig(frame, cfg, reason)
    if not (frame and cfg and cfg.enabled) then
        HideState(frame)
        return false
    end
    local root = EnsureRoot(frame)
    if not root then return false end
    A3._SeedGroupAuraPresenceGate(frame, cfg.unit, false)
    if RootAppliedConfigIsCurrent(root, frame, cfg, reason) then
        RefreshAppliedNativeRoot(root, false)
        A3._SeedGroupAuraAssistGate(frame)
        A3._SeedGroupAuraPresenceGate(frame, cfg.unit, true)
        return true
    end
    root.unit = cfg.unit or frame.MSUFUnitKey
    root:SetAllPoints(frame)
    root:Show()
    local lanes = cfg.lanes or {}
    local group = cfg.group == true
    local groupSlots = group and GetGroupSlotsRootConfig(cfg)
    local sensorRoot = not group and GetDispelSensorRootConfig(cfg) or nil
    local forceRecreate = false
    local ok = true
    local lanesOk = true
    lanesOk = A3._ApplyNormalLaneContainers(root, lanes, frame, forceRecreate, groupSlots)
    ok = lanesOk and ok
    local firstEffectRoot = group and 4 or 1
    local anyEffectRoot = false
    if group then
        if groupSlots then
            if not ApplyGroupSlots(root, groupSlots, frame, forceRecreate) then ok = false end
            local secondary = groupSlots.secondaryRoot
            if secondary then
                if not ApplyGroupSlots(root, secondary, frame, forceRecreate) then ok = false end
            end
            local tertiary = groupSlots.tertiaryRoot
            if tertiary and not ApplyGroupSlots(root, tertiary, frame, forceRecreate) then ok = false end
            if not secondary then HideGroupSlots(root, frame, nil, "GroupAuraAssist") end
            if not tertiary then HideGroupSlots(root, frame, nil, "GroupAuraHostile") end
            HideGroupSlots(root, frame, nil, "GroupAuraFlow")
        else
            HideGroupSlots(root, frame)
            HideGroupSlots(root, frame, nil, "GroupAuraFlow")
            HideGroupSlots(root, frame, nil, "GroupAuraAssist")
            HideGroupSlots(root, frame, nil, "GroupAuraHostile")
        end
        anyEffectRoot = groupSlots and (groupSlots.spellIndicatorRoot ~= nil
            or groupSlots.secondaryRoot and groupSlots.secondaryRoot.spellIndicatorRoot ~= nil
            or groupSlots.tertiaryRoot and groupSlots.tertiaryRoot.spellIndicatorRoot ~= nil) or false
    else
        if sensorRoot and sensorRoot.enabled and not ApplyDispelSensorRoot(root, sensorRoot, frame, forceRecreate) then ok = false end
        if not (sensorRoot and sensorRoot.enabled) then A3._HideLane(root.DispelSensor) end
    end
    for i = firstEffectRoot, #EFFECT_ROOT_FIELDS do
        local spellIndicatorRoot = cfg[EFFECT_ROOT_FIELDS[i]]
        local active = SpellIndicatorsRuntime.IsRoot(spellIndicatorRoot)
        local key = active and spellIndicatorRoot.rootKey or EFFECT_ROOT_KEYS[i]
        if active then
            anyEffectRoot = true
            if not SpellIndicatorsRuntime.Apply(root, spellIndicatorRoot, frame, forceRecreate) then ok = false end
        else
            A3._HideLane(root[key])
            root[key] = nil
        end
    end
    if not anyEffectRoot then SpellIndicatorsRuntime.HideAll(frame) end
    A3._HideLane(root.DispelBorderSensor)
    A3._HideLane(root.DispelOverlaySensor)
    A3._HideLane(root.DispelCornerSensor)
    root._msufA3Config = cfg
    root._msufA3Applied = ok == true
    root._msufA3ConfigGen = ConfigGen(cfg)
    root._msufA3VisualGen = VisualGen(cfg)
    root._msufA3AppliedUnit = cfg.unit or frame.MSUFUnitKey
    root._msufA3FrameSpec = frame.MSUFSpec
    root.needFullUpdate = nil
    root:Show()
    A3._SeedGroupAuraAssistGate(frame)
    A3._SeedGroupAuraPresenceGate(frame, cfg.unit, true)
    return ok == true
end

local function RootCanReuseContainersForConfig(root, cfg)
    if not (root and root._msufA3NativeRoot == true and root._msufA3Applied == true and cfg and cfg.enabled == true) then
        return false
    end
    local lanes = cfg.lanes or {}
    local group = cfg.group == true
    local groupSlots = group and GetGroupSlotsRootConfig(cfg)
    for i = 1, #NORMAL_LANE_ROOT_KEYS do
        local key = NORMAL_LANE_ROOT_KEYS[i]
        local lane = A3._NormalLaneForRootKey(lanes, key)
        local current = root[key]
        if lane and lane.enabled == true and not GroupSlotsOwnsLane(groupSlots, lane) then
            if not (current and current._msufA3StructuralSignature == (lane._msufA3StructuralSignature or LaneStructuralSignature(lane))) then
                return false
            end
        elseif current and current.IsShown and current:IsShown() == true then
            return false
        end
    end
    if group then
        local current = root[groupSlots and (groupSlots.rootKey or "GroupSlots") or "GroupSlots"]
        if groupSlots then
            if not (current and current._msufA3StructuralSignature == groupSlots._msufA3StructuralSignature) then return false end
        elseif current and current.IsShown and current:IsShown() == true then
            return false
        end
        for _, pair in ipairs({
            { groupSlots and groupSlots.secondaryRoot, "GroupAuraAssist" },
            { groupSlots and groupSlots.tertiaryRoot, "GroupAuraHostile" },
        }) do
            local owner, key = pair[1], pair[2]
            local current = root[key]
            if owner then
                if not (current and current._msufA3StructuralSignature == owner._msufA3StructuralSignature) then
                    return false
                end
            elseif current and current.IsShown and current:IsShown() == true then
                return false
            end
        end
    else
        local sensorRoot = GetDispelSensorRootConfig(cfg)
        if sensorRoot then
            local current = root.DispelSensor
            if not (current and current._msufA3StructuralSignature == sensorRoot._msufA3StructuralSignature) then return false end
        elseif root.DispelSensor and root.DispelSensor.IsShown and root.DispelSensor:IsShown() == true then
            return false
        end
    end
    for i = group and 4 or 1, #EFFECT_ROOT_FIELDS do
        local spellIndicatorRoot = cfg[EFFECT_ROOT_FIELDS[i]]
        local active = SpellIndicatorsRuntime.IsRoot(spellIndicatorRoot)
        local key = active and spellIndicatorRoot.rootKey or EFFECT_ROOT_KEYS[i]
        local current = root[key]
        if active then
            if not (current and current._msufA3StructuralSignature == spellIndicatorRoot._msufA3StructuralSignature) then return false end
        elseif current and current.IsShown and current:IsShown() == true then
            return false
        end
    end
    return true
end

local function CreateClassPowerAuraSensor(parent, key, spellIDs, initializeFrame)
    if not (parent and type(spellIDs) == "table" and type(initializeFrame) == "function") then return nil end
    if not EnsureBlizzardAuraContainerLoaded() then return nil end

    local container = CreateNativeAuraContainer(parent)
    if not container then return nil end
    -- This standalone slot receives its geometry from a caller-owned
    -- initializeFrame callback and deliberately has no managed lane descriptor.
    -- The shared identity registry may therefore reparse its candidate filters
    -- on UNIT_FACTION/player UNIT_FLAGS, while geometry ownership remains with
    -- the caller instead of the generic world/zone repair path.
    container.unit = "player"
    ConfigureNativeAuraContainer(container, "player")
    container:AddAuraSlot(tostring(key or "msuf_classpower"), "HELPFUL", {
        maxFrameCount = 1,
        candidateFilters = { includeSpellIDs = spellIDs },
        initializeFrame = initializeFrame,
    })
    if not RegisterNativeContainer(container) then
        container:Hide()
        return nil
    end
    container:Show()
    return container
end

return {
    ApplyConfig = ApplyConfig,
    HideState = HideState,
    EnsureRoot = EnsureRoot,
    EnsureRefreshDriver = EnsureNativeAuraRefreshDriver,
    RootConfigIsCurrent = RootAppliedConfigIsCurrent,
    FrameConfigIsCurrent = FrameAppliedConfigIsCurrent,
    CanReuseContainers = RootCanReuseContainersForConfig,
    ReasonRequiresApply = ReasonRequiresAuraApply,
    ApplyGroupAssistGate = ApplyGroupAuraAssistGate,
    CreateClassPowerAuraSensor = CreateClassPowerAuraSensor,
}
end)()

-- Direct local aliases keep public/runtime calls on the same fast upvalue path
-- as before the lexical split; the table is only the one-time factory boundary.
local ApplyConfig = NativeRuntime.ApplyConfig
local HideState = NativeRuntime.HideState
local EnsureRoot = NativeRuntime.EnsureRoot
local EnsureNativeAuraRefreshDriver = NativeRuntime.EnsureRefreshDriver
local RootAppliedConfigIsCurrent = NativeRuntime.RootConfigIsCurrent
local FrameAppliedConfigIsCurrent = NativeRuntime.FrameConfigIsCurrent
local RootCanReuseContainersForConfig = NativeRuntime.CanReuseContainers
local ReasonRequiresAuraApply = NativeRuntime.ReasonRequiresApply
local ApplyGroupAuraAssistGate = NativeRuntime.ApplyGroupAssistGate

function A3.SetUnitFrameOwner(unit, frame, owns)
    if not unit then return end
    A3._unitFrameOwners = A3._unitFrameOwners or {}
    if owns and frame then
        A3._unitFrameOwners[unit] = frame
    elseif A3._unitFrameOwners[unit] == frame or frame == nil then
        A3._unitFrameOwners[unit] = nil
    end
end

function A3.EnableFrame(frame)
    if not (frame and frame.MSUFUnitKey and MANAGED_UNITS[frame.MSUFUnitKey]) then return false end
    if EnsureNativeAuraRefreshDriver then EnsureNativeAuraRefreshDriver() end
    local cfg = A3.ResolveUnitFrameConfig(frame.MSUFUnitKey, frame.MSUFSpec)
    if not (cfg and cfg.enabled) then
        HideState(frame)
        A3.SetUnitFrameOwner(frame.MSUFUnitKey, frame, false)
        return false
    end
    A3._runtimeFrames = A3._runtimeFrames or {}
    A3._runtimeFrames[frame.MSUFUnitKey] = frame
    A3.SetUnitFrameOwner(frame.MSUFUnitKey, frame, true)
    return ApplyConfig(frame, cfg)
end

function A3.DisableFrame(frame)
    if not frame then return true end
    HideState(frame)
    A3._HideDispelOverlayPreview(frame)
    local unit = frame.MSUFUnitKey
    if unit and A3._runtimeFrames and A3._runtimeFrames[unit] == frame then
        A3._runtimeFrames[unit] = nil
    end
    if unit then A3.SetUnitFrameOwner(unit, frame, false) end
    frame._msufA3UnitAuraOwner = nil
    return true
end

function A3.RenderFrame(frame, reason)
    if not frame then return false end
    local cfg
    local cfgReady = false

    if IDENTITY_AURA_REFRESH_REASONS[reason] == true then
        -- Group identity stays synchronous so roster builds settle in one pass,
        -- but never forces filter reconstruction: keep geometry/registration
        -- current and let the container's UNIT_AURA own aura content.
        if not cfgReady then cfg = FrameAuraConfig(frame, frame.MSUFUnitKey) end
        cfgReady = true
        if not (cfg and cfg.enabled == true) then
            HideState(frame)
            return false
        end
        if RootAppliedConfigIsCurrent(frame.Auras, frame, cfg, nil)
            and A3._RefreshAppliedNativeAuras(frame, false) then
            return true
        end
        if AuraRuntimeCombatBlocked() then return false end
    end
    if not cfgReady then cfg = FrameAuraConfig(frame, frame.MSUFUnitKey) end
    if FrameAppliedConfigIsCurrent(frame, reason, cfg) then
        A3._RefreshAppliedNativeAuras(frame, false)
        return true
    end
    return ApplyConfig(frame, cfg, reason)
end

A3.RenderUnitChangedFrame = function(frame, oldUnit, newUnit)
    if not frame then return false end
    if type(newUnit) == "string" and newUnit ~= "" then
        frame.MSUFUnitKey = newUnit
        frame.unitKey = newUnit
    end
    local cfg = FrameAuraConfig(frame, frame.MSUFUnitKey)
    if not (cfg and cfg.enabled == true) then
        HideState(frame)
        return false
    end
    local root = frame.Auras
    -- PTR 7: recreate is combat-legal; only the unloaded-addon case still bails.
    if AuraRuntimeCombatBlocked() and not RootCanReuseContainersForConfig(root, cfg) then
        return false
    end
    return ApplyConfig(frame, cfg, "MSUF_UNIT_CHANGED_AURAS")
end

A3.OnFrameUnitChanged = A3.RenderUnitChangedFrame

A3.ForceUpdateFrame = A3.RenderFrame
A3.RenderCachedFrame = A3.RenderFrame

function A3.RuntimeOwnsUnit(unit)
    unit = NormalizeRuntimeUnit(unit)
    return unit and A3._runtimeFrames and A3._runtimeFrames[unit] ~= nil or false
end

function A3._EnsureDeferredAuraRuntimeDriver()
    if A3._deferredAuraRuntimeFrame then return A3._deferredAuraRuntimeFrame end
    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(self, event)
        if event ~= "PLAYER_REGEN_ENABLED" or InCombat() then return end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if type(A3._FlushDeferredAuraRuntime) == "function" then A3._FlushDeferredAuraRuntime() end
    end)
    A3._deferredAuraRuntimeFrame = frame
    return frame
end

function A3._QueueDeferredAuraRuntime(scope, reason, visuals)
    scope = tostring(scope or "shared"):lower()
    reason = reason or A3._deferredAuraRuntimeReason or "AURAS3_DEFERRED"
    A3._deferredAuraRuntime = true
    A3._deferredAuraRuntimeReason = reason
    if visuals == true then A3._deferredAuraRuntimeVisuals = true end
    if scope == "" or scope == "shared" or scope == "global" or scope == "all" or scope == "*" then
        A3._deferredAuraRuntimeAll = true
        A3._deferredAuraRuntimeScopes = nil
    elseif A3._deferredAuraRuntimeAll ~= true then
        A3._deferredAuraRuntimeScopes = A3._deferredAuraRuntimeScopes or {}
        A3._deferredAuraRuntimeScopes[scope] = true
    end
    local frame = A3._EnsureDeferredAuraRuntimeDriver()
    if frame then frame:RegisterEvent("PLAYER_REGEN_ENABLED") end
    return false
end

function A3._AuraPreviewGroupKind(scope)
    local key = tostring(scope or ""):lower()
    if key == "party" or key == "gf_party" or key:match("^party%d+$") then return "party", true end
    if key == "raid" or key == "gf_raid" or key:match("^raid%d+$") then return "raid", true end
    if key == "mythicraid" or key == "gf_mythicraid" then return "mythicraid", true end
    if key == "" or key == "shared" or key == "global" or key == "all" or key == "*"
        or key == "group" or key == "groups" then
        return nil, true
    end
    return nil, false
end

function A3._NotifyAuraColdpathPreview(reason, scope)
    if AuraRuntimeCombatBlocked() then return A3._QueueDeferredAuraRuntime(scope or "shared", reason or "AURAS3_PREVIEW") end
    local did = false
    reason = reason or "AURAS3_PREVIEW"
    if type(_G.MSUF_UFPreview_RequestRefresh) == "function" then
        _G.MSUF_UFPreview_RequestRefresh(reason)
        did = true
    end
    local gf = A3._GroupAPI and A3._GroupAPI() or nil
    local kind, touchesGroup = A3._AuraPreviewGroupKind(scope)
    if touchesGroup and gf and type(gf.RefreshPreviewLayout) == "function" then
        gf.RefreshPreviewLayout(kind)
        did = true
    elseif touchesGroup and type(_G.MSUF_GF_RefreshPreviewLayout) == "function" then
        _G.MSUF_GF_RefreshPreviewLayout()
        did = true
    end
    return did
end

A3._ApplyRuntimeUnit = function(runtimeUnit)
    if AuraRuntimeCombatBlocked() then return A3._QueueDeferredAuraRuntime(runtimeUnit, "AURAS3_RUNTIME_UNIT") end
    local frame = (A3._runtimeFrames and A3._runtimeFrames[runtimeUnit])
        or (UF.GetFrame and UF.GetFrame(runtimeUnit))
        or (UF.frames and UF.frames[runtimeUnit])
        or _G["MSUF_" .. runtimeUnit]
    if not frame then return false end
    if UF.ApplyElementToFrame then
        UF.ApplyElementToFrame(frame, "Auras", frame.MSUFSpec, nil)
    else
        A3.EnableFrame(frame)
    end
    return true
end

function A3._GroupAPI()
    local ns = MSUF or _G.MSUF_NS or _G.MSUF
    return ns and ns.GF or nil
end

function A3._ApplyGroupAuraFrame(frame, unit, kind)
    if not (frame and type(unit) == "string" and unit ~= "") then return false end
    if AuraRuntimeCombatBlocked() then return A3._QueueDeferredAuraRuntime(unit, "AURAS3_GROUP_FRAME") end
    if EnsureNativeAuraRefreshDriver then EnsureNativeAuraRefreshDriver() end
    frame._msufIsGroupFrame = true
    if kind then frame._msufGFKind = kind end
    if UF.ApplyElementToFrame then
        UF.ApplyElementToFrame(frame, "Auras", frame.MSUFSpec, nil)
    else
        A3.RenderFrame(frame)
    end
    return true
end

function A3._RequestGroupKindNow(kind)
    local gf = A3._GroupAPI()
    if not gf then return false end
    if AuraRuntimeCombatBlocked() then return A3._QueueDeferredAuraRuntime(kind or "group", "AURAS3_GROUP_KIND") end
    if type(gf.RefreshVisuals) == "function" then
        return gf.RefreshVisuals(kind, gf.DIRTY_AURAS) == true
    end
    local didWork = false
    if type(gf.ForEachFrame) == "function" then
        didWork = gf.ForEachFrame(function(frame, frameUnit, frameKind)
            if kind == nil or frameKind == kind then
                return A3._ApplyGroupAuraFrame(frame, frameUnit, frameKind)
            end
            return false
        end, true) == true
    end
    if not didWork and type(gf.RefreshVisuals) == "function" then
        gf.RefreshVisuals(kind, gf.DIRTY_AURAS)
        return true
    end
    return didWork
end

local function ApplyRequestedGroupUnitFrame(frame, unit, gf)
    if type(gf.MarkDirty) == "function" then
        return gf.MarkDirty(frame, gf.DIRTY_AURAS) == true
    end
    return A3._ApplyGroupAuraFrame(frame, unit, frame._msufGFKind) == true
end

function A3._RequestGroupUnitNow(unit)
    local gf = A3._GroupAPI()
    if not (gf and type(unit) == "string" and unit ~= "") then return false end
    if AuraRuntimeCombatBlocked() then return A3._QueueDeferredAuraRuntime(unit, "AURAS3_GROUP_UNIT") end
    if type(gf.ForEachFrameForUnit) == "function" then
        return gf.ForEachFrameForUnit(unit, ApplyRequestedGroupUnitFrame, gf)
    end
    local frame = type(gf.FrameForUnit) == "function" and gf.FrameForUnit(unit) or nil
    if frame and type(gf.MarkDirty) == "function" then
        return gf.MarkDirty(frame, gf.DIRTY_AURAS) == true
    end
    return frame and A3._ApplyGroupAuraFrame(frame, unit, frame._msufGFKind) or false
end

A3._RequestUnitNow = function(unit)
    unit = tostring(unit or "")
    if unit == "" or unit == "*" then
        local didWork = A3._ApplyRuntimeUnit("player")
        didWork = A3._ApplyRuntimeUnit("target") or didWork
        didWork = A3._ApplyRuntimeUnit("focus") or didWork
        for i = 1, 5 do didWork = A3._ApplyRuntimeUnit("boss" .. i) or didWork end
        didWork = A3._RequestGroupKindNow(nil) or didWork
        return didWork
    end
    if unit == "boss" then
        local didWork = false
        for i = 1, 5 do didWork = A3._ApplyRuntimeUnit("boss" .. i) or didWork end
        return didWork
    end
    if unit == "group" or unit == "groups" then return A3._RequestGroupKindNow(nil) end
    if unit == "party" or unit == "gf_party" then return A3._RequestGroupKindNow("party") end
    if unit == "raid" or unit == "gf_raid" then
        local didWork = A3._RequestGroupKindNow("raid")
        return A3._RequestGroupKindNow("mythicraid") or didWork
    end
    if unit == "mythicraid" or unit == "gf_mythicraid" then return A3._RequestGroupKindNow("mythicraid") end
    if unit:match("^party%d+$") or unit:match("^raid%d+$") then return A3._RequestGroupUnitNow(unit) end
    unit = NormalizeRuntimeUnit(unit)
    return unit and A3._ApplyRuntimeUnit(unit) or false
end

function A3.RequestUnit(unit)
    if AuraRuntimeCombatBlocked() then return A3._QueueDeferredAuraRuntime(unit, "AURAS3_REQUEST_UNIT") end
    return A3._RequestUnitNow(unit)
end

A3._DoRefreshAll = function()
    ApplyAuraTooltipStyle()
    A3.BumpRuntimeConfig()
    A3._runtimeConfigCache = nil
    A3._RequestUnitNow("*")
    return true
end

A3._FlushCoalescedRefreshAll = function()
    local pending = A3._refreshAllPending == true
    A3._refreshAllPending = nil
    A3._refreshAllCoalescing = nil
    if pending then
        return A3._DoRefreshAll()
    end
    return true
end

function A3._FlushDeferredAuraRuntime()
    if InCombat() or A3._deferredAuraRuntime ~= true then return false end
    local all = A3._deferredAuraRuntimeAll == true
    local scopes = A3._deferredAuraRuntimeScopes
    local visuals = A3._deferredAuraRuntimeVisuals == true
    local reason = A3._deferredAuraRuntimeReason or "AURAS3_DEFERRED"
    A3._deferredAuraRuntime = nil
    A3._deferredAuraRuntimeAll = nil
    A3._deferredAuraRuntimeScopes = nil
    A3._deferredAuraRuntimeVisuals = nil
    A3._deferredAuraRuntimeReason = nil
    if visuals then A3._nativeVisualGen = (A3._nativeVisualGen or 0) + 1 end
    local previewScope = all and "shared" or nil
    if all or not scopes then
        A3.RefreshAll()
    else
        for scope in pairs(scopes) do
            if previewScope == nil then previewScope = scope end
            local _, touchesGroup = A3._AuraPreviewGroupKind(scope)
            if touchesGroup then previewScope = scope end
            A3.RefreshUnit(scope)
        end
    end
    A3._NotifyAuraColdpathPreview(reason, previewScope)
    return true
end

function A3.RefreshAll()
    if AuraRuntimeCombatBlocked() then return A3._QueueDeferredAuraRuntime("shared", "AURAS3_REFRESH_ALL") end
    if A3._refreshAllCoalescing == true then
        A3._refreshAllPending = true
        return true
    end
    A3._refreshAllCoalescing = true
    A3._DoRefreshAll()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, A3._FlushCoalescedRefreshAll)
    else
        A3._refreshAllCoalescing = nil
    end
    return true
end

A3._requestApplyScopeKeys = A3._requestApplyScopeKeys or {
    player = true, target = true, focus = true, boss = true,
    party = true, raid = true, mythicraid = true,
    gf_party = true, gf_raid = true, gf_mythicraid = true,
    group = true, groups = true,
    shared = true, global = true, all = true, ["*"] = true,
}

A3._LooksLikeApplyScope = function(value)
    value = tostring(value or ""):lower()
    if value == "" then return false end
    if A3._requestApplyScopeKeys[value] then return true end
    return value:match("^boss%d+$") ~= nil
        or value:match("^party%d+$") ~= nil
        or value:match("^raid%d+$") ~= nil
end

function A3.RequestApply(scopeOrReason, reason)
    if A3._LooksLikeApplyScope(scopeOrReason) then
        return A3.RequestScope(scopeOrReason, reason or "AURAS3_REQUEST_APPLY")
    end
    return A3.RefreshAll()
end

function A3.RequestScope(scope, reason)
    scope = tostring(scope or "shared"):lower()
    if AuraRuntimeCombatBlocked() then return A3._QueueDeferredAuraRuntime(scope, reason or "AURAS3_SCOPE_APPLY") end
    if scope == "" or scope == "shared" or scope == "global" or scope == "all" or scope == "*" then
        return A3.RefreshAll()
    end
    local result = A3.RefreshUnit(scope)
    A3._NotifyAuraColdpathPreview(reason or "AURAS3_SCOPE_APPLY", scope)
    return result
end

if type(MSUF.RegisterLocaleCallback) == "function" then
    MSUF.RegisterLocaleCallback("MSUF_Auras3_DurationFormatter", function()
        _durationFormatterCache = nil
        if type(A3.RequestApply) == "function" then A3.RequestApply() end
    end)
end

function A3.RefreshUnit(unit)
    if AuraRuntimeCombatBlocked() then return A3._QueueDeferredAuraRuntime(unit, "AURAS3_REFRESH_UNIT") end
    if unit == "boss" then
        for i = 1, 5 do InvalidateUnitRuntimeConfig("boss" .. i) end
        return A3.RequestUnit("boss")
    end
    local runtimeUnit = InvalidateUnitRuntimeConfig(unit)
    if runtimeUnit then return A3.RequestUnit(runtimeUnit) end
    A3.BumpRuntimeConfig()
    A3._runtimeConfigCache = nil
    return A3.RequestUnit(unit)
end

function A3.ApplyFontsFromGlobal(scope, reason)
    if AuraRuntimeCombatBlocked() then return A3._QueueDeferredAuraRuntime(scope or "shared", reason or "AURAS3_FONT_VISUALS", true) end
    A3._nativeVisualGen = (A3._nativeVisualGen or 0) + 1
    if scope ~= nil then
        return A3.RequestScope(scope, reason or "AURAS3_FONT_VISUALS")
    end
    return A3.RefreshAll()
end

--- Narrow ClassPower bridge for secret player auras. AuraContainer retains
--- ownership of UNIT_AURA parsing and binds protected values directly to its
--- regions; callers only configure the frame once.
A3.CreateClassPowerAuraSensor = NativeRuntime.CreateClassPowerAuraSensor

-- AuraContainer owns UNIT_AURA and per-aura churn. Do not add an MSUF UNIT_AURA
-- scanner here; target/focus identity refresh is handled by the coalesced
-- container refresh path above.
local AurasElement = {
    events = EMPTY_EVENTS,
    unitlessEvents = EMPTY_EVENTS,
}

function AurasElement.GetEvents()
    return EMPTY_EVENTS
end

function AurasElement.SelectEventUpdate()
    return nil
end

function AurasElement.IsEnabled(frame)
    if IsGroupFrame(frame) and frame._msufGFIsPreviewFrame == true then
        return false
    end
    local cfg = FrameAuraConfig(frame, frame and frame.MSUFUnitKey)
    return cfg and cfg.enabled == true or false
end

function AurasElement.Create(frame)
    EnsureRoot(frame)
end

function AurasElement.Apply(frame)
    return frame ~= nil
end

function AurasElement.Enable(frame)
    if IsGroupFrame(frame) then
        -- Edit Mode uses pooled addon-owned stand-ins compiled from the same
        -- lane geometry. Never attach a native player AuraContainer to a
        -- synthetic row: it would show the player's current auras instead of
        -- deterministic dummy data and allocate AuraButtons in batches.
        if frame._msufGFIsPreviewFrame == true then
            frame._msufA3GroupRuntime = nil
            HideState(frame)
            return false
        end
        frame._msufA3GroupRuntime = true
        local cfg = ResolveGroupFrameConfig(frame, frame and frame.MSUFUnitKey)
        if not (cfg and cfg.enabled) then
            HideState(frame)
            return false
        end
        return ApplyConfig(frame, cfg)
    end
    return A3.EnableFrame(frame)
end

function AurasElement.Disable(frame)
    return A3.DisableFrame(frame)
end

function AurasElement.Update(frame, event)
    if event ~= nil and not ReasonRequiresAuraApply(event) then
        local root = frame and frame.Auras
        if root and root._msufA3NativeRoot == true and root._msufA3Applied == true then
            A3._RefreshAppliedNativeAuras(frame, false)
            return true
        end
        return false
    end
    return A3.RenderFrame(frame, event)
end

UF.RegisterElement("Auras", AurasElement)

A3.frontendOnly = false
A3.backendEnabled = true
A3.unitFrameAuras = true
A3.nativeAuraBackend = true
A3.RefreshRuntime = A3.RefreshAll
MSUF.AuraBackendEnabled = true
MSUF.AuraCore = MSUF.AuraCore or _G.MSUF_AuraCore or {}
MSUF.AuraCore.Auras3 = A3
