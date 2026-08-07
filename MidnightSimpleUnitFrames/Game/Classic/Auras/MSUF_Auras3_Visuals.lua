--- Classic-only visual parity for the scan-based Auras3 backend.
--- Loaded exclusively by Classic-family manifests; Mainline keeps the native
--- AuraContainer visual implementation and pays no load/runtime cost here.
if not (select(2, ...) and select(2, ...).Client and select(2, ...).Client.IsClassic) then return end

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then return end

local V = A3.ClassicVisuals or {}
A3.ClassicVisuals = V

local type, tostring, tonumber, select = type, tostring, tonumber, select
local math_floor, math_max, math_min = math.floor, math.max, math.min
local CreateFrame = _G.CreateFrame
local C_UnitAuras = _G.C_UnitAuras

local function Clamp(value, fallback, minValue, maxValue)
    value = tonumber(value)
    if value == nil then value = fallback end
    if minValue and value < minValue then value = minValue end
    if maxValue and value > maxValue then value = maxValue end
    return value
end

local function Clamp01(value, fallback)
    return Clamp(value, fallback, 0, 1)
end

local Shape = A3.IconShape or {}
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
    CIRCLE = true, ROUNDED = true, DIAMOND = true,
    HEXAGON = true, STAR = true, BLIZZARD = true,
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
    if media.maskAtlas and mask.SetAtlas then mask:SetAtlas(media.maskAtlas) else mask:SetTexture(media.mask) end
    mask:ClearAllPoints()
    mask:SetAllPoints(owner)
    mask:Show()
    return mask
end

function Shape.ApplyCooldown(cooldown, shape, mask)
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

function A3.ApplyAuraIconShape(owner, shape, cooldown, ...)
    if not owner then return Shape.RECTANGLE end
    shape = Shape.Normalize(shape)
    local mask = shape ~= Shape.RECTANGLE and Shape.EnsureMask(owner, shape) or nil
    if not mask and owner._msufA3AuraShapeMask then owner._msufA3AuraShapeMask:Hide() end
    for index = 1, select("#", ...) do
        local texture = select(index, ...)
        if mask then Shape.ApplyMask(texture, mask) else Shape.ClearMask(texture) end
    end
    Shape.ApplyCooldown(cooldown, shape, mask)
    owner._msufA3IconShape = shape
    return shape
end

function A3.AuraShapeBorderPath(shape)
    local media = Shape.MEDIA[Shape.Normalize(shape)]
    return media and media.border or nil
end

A3.NormalizeAuraIconShape = Shape.Normalize
A3.ResolveAuraIconShape = Shape.Resolve
A3.AURA_ICON_SHAPE_RECTANGLE = Shape.RECTANGLE
A3.AURA_ICON_SHAPE_FOLLOW_PORTRAIT = Shape.FOLLOW_PORTRAIT

local function Read(source, fallbackSource, key, fallback)
    local value = type(source) == "table" and source[key]
    if value == nil and type(fallbackSource) == "table" then value = fallbackSource[key] end
    if value == nil then value = fallback end
    return value
end

local function Color(value, dr, dg, db, da)
    value = type(value) == "table" and value or {}
    return Clamp01(value[1] or value.r, dr), Clamp01(value[2] or value.g, dg),
        Clamp01(value[3] or value.b, db), Clamp01(value[4] or value.a, da)
end

local ICON_STYLE_OFF = {
    borderEnabled = false,
    shadowEnabled = false,
    borderStyle = "SOLID",
    borderThickness = 1,
    shadowSize = 0,
}

function V.SharedIconStyle(shared, scope)
    shared = type(shared) == "table" and shared or {}
    local normalized = tostring(scope or ""):lower()
    if normalized:match("^boss%d+$") then normalized = "boss" end
    local disabled = type(shared.styleScopeDisabled) == "table" and shared.styleScopeDisabled
    if normalized ~= "" and disabled and disabled[normalized] == true then return ICON_STYLE_OFF end
    local borderR, borderG, borderB, borderA = Color(shared.styleBorderColor, 0, 0, 0, 1)
    local shadowR, shadowG, shadowB, shadowA = Color(shared.styleShadowColor, 0, 0, 0, 0.8)
    local styles = MSUF.BorderStyles
    local key = styles and styles.Normalize(shared.styleBorderStyle) or "SOLID"
    local texture = styles and styles.Resolve(key) or nil
    return {
        borderEnabled = shared.styleBorderEnabled == true,
        borderStyle = key,
        borderTexture = texture,
        borderThickness = Clamp(shared.styleBorderThickness, 1, 1, 8),
        borderR = borderR, borderG = borderG, borderB = borderB, borderA = borderA,
        borderEdge = texture and styles and styles.EdgeSize(key, Clamp(shared.styleBorderThickness, 1, 1, 8)) or nil,
        borderPlacement = texture and styles and styles.Placement(key) or nil,
        shadowEnabled = shared.styleShadowEnabled == true,
        shadowSize = Clamp(shared.styleShadowSize, 4, 1, 16),
        shadowR = shadowR, shadowG = shadowG, shadowB = shadowB, shadowA = shadowA,
    }
end

local function Enrich(lane, layout, shared, prefix, portraitShape, scope)
    if not lane then return nil end
    local shapeValue = Read(layout, shared, prefix .. "IconShape", Read(shared, nil, "iconShape", "RECTANGLE"))
    lane.iconShape = Shape.Resolve(shapeValue, portraitShape)
    lane.iconZoom = Clamp(Read(layout, shared, prefix .. "IconZoom", Read(shared, nil, "iconZoom", 100)), 100, 100, 200)
    lane.cooldownSwipeReverse = Read(layout, shared, prefix .. "CooldownSwipeReverse", false) == true
    lane.showDurationBar = Read(layout, shared, prefix .. "ShowDurationBar", Read(shared, nil, "showDurationBar", false)) == true
    local display = tostring(Read(layout, shared, prefix .. "DurationBarDisplay", Read(shared, nil, "durationBarDisplay", "BAR_ONLY"))):upper()
    lane.durationBarDisplay = display == "OVERLAY" and "OVERLAY" or "BAR_ONLY"
    lane.durationBarHeight = Clamp(Read(layout, shared, prefix .. "DurationBarHeight", Read(shared, nil, "durationBarHeight", 2)), 2, 1, 16)
    lane.durationBarPosition = tostring(Read(layout, shared, prefix .. "DurationBarPosition", Read(shared, nil, "durationBarPosition", "BOTTOM"))):upper()
    lane.durationBarDirection = tostring(Read(layout, shared, prefix .. "DurationBarDirection", Read(shared, nil, "durationBarDirection", "REMAINING"))):upper()
    lane.iconStyle = V.SharedIconStyle(shared, scope or lane.unit)
    lane.classicVisualStyle = true
    lane.buttonWidth = lane.buttonWidth or lane.size
    lane.buttonHeight = lane.buttonHeight or lane.size
    lane.stepX = lane.stepX or lane.step
    lane.stepY = lane.stepY or lane.step
    return lane
end

function V.EnrichUnitLane(lane, layout, sharedLayout, shared, kind, frameSpec)
    local merged = {}
    for key, value in pairs(type(sharedLayout) == "table" and sharedLayout or {}) do merged[key] = value end
    for key, value in pairs(type(layout) == "table" and layout or {}) do merged[key] = value end
    local prefix = kind == "debuff" and "debuff" or "buff"
    return Enrich(lane, merged, shared, prefix, frameSpec and frameSpec.portrait and frameSpec.portrait.shape, lane.unit)
end

function V.EnrichGroupLane(lane, source, kind, frameSpec, scope)
    local prefix = kind
    local root = _G.MSUF_DB and _G.MSUF_DB.auras3
    local shared = root and root.shared or {}
    return Enrich(lane, source, shared, prefix, frameSpec and frameSpec.portrait and frameSpec.portrait.shape, scope)
end

function V.EnrichCustomLane(lane, entry, frameSpec)
    local placed = type(entry) == "table" and type(entry.placed) == "table" and entry.placed or {}
    local root = _G.MSUF_DB and _G.MSUF_DB.auras3
    local shared = root and root.shared or {}
    lane.iconShape = Shape.Resolve(placed.iconShape, frameSpec and frameSpec.portrait and frameSpec.portrait.shape)
    lane.iconZoom = Clamp(placed.iconZoom, 100, 100, 200)
    lane.cooldownSwipeReverse = placed.cooldownSwipeReverse == true
    lane.showDurationBar = placed.showDurationBar == true
    lane.durationBarDisplay = tostring(placed.durationBarDisplay or "BAR_ONLY"):upper() == "OVERLAY" and "OVERLAY" or "BAR_ONLY"
    lane.durationBarHeight = Clamp(placed.durationBarHeight, 2, 1, 16)
    lane.durationBarPosition = tostring(placed.durationBarPosition or "BOTTOM"):upper()
    lane.durationBarDirection = tostring(placed.durationBarDirection or "REMAINING"):upper()
    lane.iconStyle = V.SharedIconStyle(shared, lane.unit)
    lane.classicVisualStyle = true
    return lane
end

local SHADOW_TEXTURE = Shape.MEDIA_ROOT .. "\\Media\\Borders\\msuf_aura_border_shadow.tga"

local function SetShapeTexture(texture, shape, border)
    local media = Shape.MEDIA[shape]
    if not (texture and media) then return false end
    if border then texture:SetTexture(media.border)
    elseif media.maskAtlas and texture.SetAtlas then texture:SetAtlas(media.maskAtlas)
    else texture:SetTexture(media.swipe or media.mask) end
    if texture.SetDesaturated then texture:SetDesaturated(media.desaturate == true) end
    if texture.SetTexCoord then texture:SetTexCoord(0, 1, 0, 1) end
    return true
end

local function HidePieces(pieces)
    if MSUF.BorderStyles and pieces then MSUF.BorderStyles.Hide(pieces) end
end

local function ApplyShadow(button, style, size, shape)
    local pieces = button._msufA3StyleShadow
    local shapedTexture = button._msufA3ShapedStyleShadow
    if shape ~= Shape.RECTANGLE then
        HidePieces(pieces)
        if not (style and style.shadowEnabled) then if shapedTexture then shapedTexture:Hide() end; return end
        if not shapedTexture then
            shapedTexture = button:CreateTexture(nil, "BACKGROUND", nil, -7)
            button._msufA3ShapedStyleShadow = shapedTexture
        end
        if not SetShapeTexture(shapedTexture, shape, false) then shapedTexture:Hide(); return end
        local extent = style.shadowSize + (style.borderEnabled and style.borderThickness or 0)
        shapedTexture:ClearAllPoints()
        shapedTexture:SetPoint("TOPLEFT", button, "TOPLEFT", -extent, extent)
        shapedTexture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", extent, -extent)
        shapedTexture:SetVertexColor(style.shadowR, style.shadowG, style.shadowB, style.shadowA)
        shapedTexture:Show()
        return
    end
    if shapedTexture then shapedTexture:Hide() end
    if not (style and style.shadowEnabled and MSUF.BorderStyles) then HidePieces(pieces); return end
    if not pieces then
        pieces = MSUF.BorderStyles.Create(button, "BACKGROUND", -7, SHADOW_TEXTURE)
        button._msufA3StyleShadow = pieces
    end
    local extent = style.shadowSize + (style.borderEnabled and style.borderThickness or 0)
    MSUF.BorderStyles.Apply(pieces, button, extent * 2, size, size,
        style.shadowR, style.shadowG, style.shadowB, style.shadowA)
end

local function ApplyBorder(button, style, size, shape)
    local flat = button._msufA3StyleBorder
    local pieces = button._msufA3StyleBorderPieces
    local shaped = button._msufA3ShapedStyleBorder
    if shape ~= Shape.RECTANGLE then
        if flat then flat:Hide() end
        HidePieces(pieces)
        if not (style and style.borderEnabled) then if shaped then shaped:Hide() end; return end
        if not shaped then
            shaped = button:CreateTexture(nil, "BORDER", nil, -1)
            button._msufA3ShapedStyleBorder = shaped
        end
        if not SetShapeTexture(shaped, shape, true) then shaped:Hide(); return end
        local extent = style.borderThickness
        shaped:ClearAllPoints()
        shaped:SetPoint("TOPLEFT", button, "TOPLEFT", -extent, extent)
        shaped:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", extent, -extent)
        shaped:SetVertexColor(style.borderR, style.borderG, style.borderB, style.borderA)
        shaped:Show()
        return
    end
    if shaped then shaped:Hide() end
    if not (style and style.borderEnabled) then if flat then flat:Hide() end; HidePieces(pieces); return end
    if style.borderTexture and MSUF.BorderStyles then
        if flat then flat:Hide() end
        if not pieces then
            pieces = MSUF.BorderStyles.Create(button,
                style.borderPlacement == "inner" and "ARTWORK" or "BORDER",
                style.borderPlacement == "inner" and 7 or -1, style.borderTexture)
            button._msufA3StyleBorderPieces = pieces
        else
            MSUF.BorderStyles.SetTexture(pieces, style.borderTexture)
        end
        MSUF.BorderStyles.Apply(pieces, button, style.borderEdge or style.borderThickness,
            size, size, style.borderR, style.borderG, style.borderB, style.borderA)
        return
    end
    HidePieces(pieces)
    if not flat then
        flat = button:CreateTexture(nil, "BORDER", nil, -1)
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

function A3.ApplyIconStylePreview(button, style, size, shape)
    if not button then return end
    shape = Shape.Normalize(shape)
    ApplyShadow(button, style, size, shape)
    ApplyBorder(button, style, size, shape)
end

function A3.ApplyAuraDispelPreview(border, icon, size, mode, shape)
    shape = Shape.Normalize(shape)
    if shape == Shape.RECTANGLE then return false end
    local path = A3.AuraShapeBorderPath(shape)
    if not (border and icon and path and mode ~= nil and mode ~= "OFF") then return false end
    local pad = math_max(1, math_floor(((tonumber(size) or 24) / 24) + 0.5))
    border:SetTexture(path)
    if border.SetTexCoord then border:SetTexCoord(0, 1, 0, 1) end
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
    border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
    border:SetVertexColor(0.20, 0.60, 1.00, 1)
    border:Show()
    return true
end

function A3.IconStylePreviewForScope(scope)
    local root = _G.MSUF_DB and _G.MSUF_DB.auras3
    local shared = root and root.shared or {}
    return V.SharedIconStyle(shared, scope)
end

function V.ApplyButtonLayout(lane, button)
    local cfg = lane and lane.config
    if not (cfg and button) then return end
    local zoom = Clamp(cfg.iconZoom, 100, 100, 200)
    local inset = (1 - (100 / zoom)) * 0.5
    if button.Icon and button.Icon.SetTexCoord then button.Icon:SetTexCoord(inset, 1 - inset, inset, 1 - inset) end
    local shape = cfg.iconShape or Shape.RECTANGLE
    A3.ApplyAuraIconShape(button, shape, button.Cooldown, button.Icon)
    A3.ApplyIconStylePreview(button, cfg.iconStyle, math_min(cfg.buttonWidth or cfg.size, cfg.buttonHeight or cfg.size), shape)
    if button.Cooldown and button.Cooldown.SetReverse then button.Cooldown:SetReverse(cfg.cooldownSwipeReverse == true) end
    local barOnly = cfg.showDurationBar == true and cfg.durationBarDisplay == "BAR_ONLY"
    if button.Icon and button.Icon.SetShown then button.Icon:SetShown(not barOnly)
    elseif button.Icon then if barOnly then button.Icon:Hide() else button.Icon:Show() end end
    -- UpdateCooldown owns whether this particular aura has a live timer. Do
    -- not resurrect the Cooldown merely because the lane allows cooldowns:
    -- permanent auras intentionally leave _msufA3CooldownShown unset.
    local showCooldown = not barOnly and cfg.showCooldown == true
        and button._msufA3CooldownShown == true
    if button.Cooldown and button.Cooldown.SetShown then button.Cooldown:SetShown(showCooldown)
    elseif button.Cooldown then if showCooldown then button.Cooldown:Show() else button.Cooldown:Hide() end end
    if button.Count and button.Count.SetShown then button.Count:SetShown(not barOnly and cfg.showStacks ~= false)
    elseif button.Count then if barOnly or cfg.showStacks == false then button.Count:Hide() else button.Count:Show() end end
end

-- Classic never binds aura LuaDurationObjects: C_UnitAuras.GetAuraDuration has
-- no engine-validated consumer on any Classic branch, and on Mists/TBC the
-- bound objects produced hour-scale timers. The bar animates from plain
-- duration/expiration numbers instead, the way Blizzard's own Classic timer
-- bars do. OnUpdate only runs while the bar is shown, so permanent auras
-- (hidden bar) cost nothing.
local function DurationBarOnUpdate(bar)
    local duration = bar._msufA3ClassicBarDuration
    local expiration = bar._msufA3ClassicBarExpiration
    if not (duration and expiration) then return end
    local remaining = expiration - (_G.GetTime and _G.GetTime() or 0)
    if remaining < 0 then remaining = 0 end
    bar:SetValue(bar._msufA3ClassicBarElapsed == true and (duration - remaining) or remaining)
end

local function DurationBar(button, cfg)
    local bar = button._msufA3DurationBar
    if not bar then
        bar = CreateFrame("StatusBar", nil, button)
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        bar:SetScript("OnUpdate", DurationBarOnUpdate)
        button._msufA3DurationBar = bar
    end
    local height = Clamp(cfg.durationBarHeight, 2, 1, math_max(1, cfg.buttonHeight or cfg.size))
    local inset = math_max(1, math_floor(((cfg.buttonHeight or cfg.size or 24) / 32) + 0.5))
    bar:ClearAllPoints()
    bar:SetHeight(height)
    if cfg.durationBarPosition == "TOP" then
        bar:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
        bar:SetPoint("TOPRIGHT", button, "TOPRIGHT", -inset, -inset)
    else
        bar:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", inset, inset)
        bar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
    end
    local general = _G.MSUF_DB and _G.MSUF_DB.general
    local color = general and general.aurasCooldownTextSafeColor
    local r, g, b = Color(color, 1, 1, 1, 0.95)
    bar:SetStatusBarColor(r, g, b, 0.95)
    return bar
end

local function FrameEffectHealthBar(frame)
    return frame and (frame.hpBar or frame.Health or frame.health)
end

local function FrameEffectHealthFill(frame)
    local bar = FrameEffectHealthBar(frame)
    return bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture() or bar
end

local function HideFrameEffect(button)
    local timer = button and button._msufA3ClassicFrameEffectTimer
    if timer and timer.Cancel then timer:Cancel() end
    if button then button._msufA3ClassicFrameEffectTimer = nil end
    local root = button and button._msufA3ClassicFrameEffectRoot
    if not root then return end
    local pulse = root._msufA3ClassicPulse
    if pulse and pulse.IsPlaying and pulse:IsPlaying() then pulse:Stop() end
    if root.SetAlpha then root:SetAlpha(1) end
    if root._tint then root._tint:Hide() end
    for i = 1, type(root._edges) == "table" and #root._edges or 0 do root._edges[i]:Hide() end
    if root._name then root._name:Hide() end
    root:Hide()
end

local function EnsureFrameEffectRoot(button, frame)
    local target = FrameEffectHealthBar(frame)
    if not (button and target) then return nil end
    local root = button._msufA3ClassicFrameEffectRoot
    if not root then
        root = CreateFrame("Frame", nil, button)
        if root.EnableMouse then root:EnableMouse(false) end
        button._msufA3ClassicFrameEffectRoot = root
    end
    root:ClearAllPoints()
    root:SetAllPoints(target)
    return root, target
end

local function ApplyFrameEffectEdges(root, target, effect, kind, r, g, b, a)
    local edges = root._edges
    if not edges then
        edges = {}
        for i = 1, 4 do
            edges[i] = root:CreateTexture(nil, "OVERLAY")
            edges[i]:SetTexture("Interface\\Buttons\\WHITE8X8")
        end
        root._edges = edges
    end
    local thickness = Clamp(effect.thickness, kind == "glow" and 3 or 2, 1, 32)
    if kind == "glow" or kind == "pulse" then thickness = thickness + 2 end
    edges[1]:ClearAllPoints(); edges[1]:SetPoint("TOPLEFT", target, "TOPLEFT", -thickness, thickness)
    edges[1]:SetPoint("TOPRIGHT", target, "TOPRIGHT", thickness, thickness); edges[1]:SetHeight(thickness)
    edges[2]:ClearAllPoints(); edges[2]:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", -thickness, -thickness)
    edges[2]:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", thickness, -thickness); edges[2]:SetHeight(thickness)
    edges[3]:ClearAllPoints(); edges[3]:SetPoint("TOPLEFT", edges[1], "BOTTOMLEFT", 0, 0)
    edges[3]:SetPoint("BOTTOMLEFT", edges[2], "TOPLEFT", 0, 0); edges[3]:SetWidth(thickness)
    edges[4]:ClearAllPoints(); edges[4]:SetPoint("TOPRIGHT", edges[1], "BOTTOMRIGHT", 0, 0)
    edges[4]:SetPoint("BOTTOMRIGHT", edges[2], "TOPRIGHT", 0, 0); edges[4]:SetWidth(thickness)
    for i = 1, 4 do
        if edges[i].SetBlendMode then edges[i]:SetBlendMode(kind == "glow" and "ADD" or "BLEND") end
        edges[i]:SetVertexColor(r, g, b, kind == "glow" and math_min(1, a + 0.16) or a)
        edges[i]:Show()
    end
    if kind == "pulse" and root.CreateAnimationGroup then
        local pulse = root._msufA3ClassicPulse
        if not pulse then
            pulse = root:CreateAnimationGroup()
            local alpha = pulse:CreateAnimation("Alpha")
            alpha:SetFromAlpha(0.45); alpha:SetToAlpha(1); alpha:SetDuration(0.7)
            if alpha.SetSmoothing then alpha:SetSmoothing("IN_OUT") end
            pulse:SetLooping("BOUNCE")
            root._msufA3ClassicPulse = pulse
        end
        if pulse.IsPlaying and not pulse:IsPlaying() then pulse:Play() end
    end
end

local function ApplyFrameEffect(lane, button, data)
    local cfg = lane and lane.config
    local effect = cfg and cfg.frameEffect
    local kind = type(effect) == "table" and tostring(effect.type or "none"):lower() or "none"
    if kind ~= "healthtint" and kind ~= "border" and kind ~= "glow"
        and kind ~= "pulse" and kind ~= "namecolor" then
        HideFrameEffect(button)
        return false
    end

    if tostring(effect.timing or "active"):lower() == "expiring" then
        local expiration = tonumber(data and data.expirationTime)
        local duration = tonumber(data and data.duration)
        local threshold = Clamp(effect.expireThreshold, 5, 1, 30)
        local now = _G.GetTime and _G.GetTime() or 0
        local remaining = expiration and expiration - now or 0
        if not (duration and duration > 0 and remaining > 0) then
            HideFrameEffect(button)
            return false
        end
        if remaining > threshold then
            HideFrameEffect(button)
            local delay = remaining - threshold
            local timerAPI = _G.C_Timer
            if timerAPI and timerAPI.NewTimer then
                local auraInstanceID = button.auraInstanceID
                button._msufA3ClassicFrameEffectTimer = timerAPI.NewTimer(delay, function()
                    button._msufA3ClassicFrameEffectTimer = nil
                    if button.auraInstanceID == auraInstanceID and button._msufA3Shown == true then
                        ApplyFrameEffect(lane, button, data)
                    end
                end)
            end
            return false
        end
    end

    local frame = lane.ownerFrame
    local root, target = EnsureFrameEffectRoot(button, frame)
    if not root then HideFrameEffect(button); return false end
    HideFrameEffect(button)
    root, target = EnsureFrameEffectRoot(button, frame)
    local color = type(effect.color) == "table" and effect.color or {}
    local r, g, b, a = Color(color, 1, 1, 1, 1)
    if root.SetFrameLevel and frame and frame.GetFrameLevel then
        local priority = Clamp(effect.priority, 5, 1, 10)
        root:SetFrameLevel((frame:GetFrameLevel() or 0) + 12 - priority + Clamp(effect.layer, 0, 0, 30))
    end
    if kind == "healthtint" then
        local fill = FrameEffectHealthFill(frame)
        if not fill then return false end
        local tint = root._tint or root:CreateTexture(nil, "OVERLAY")
        root._tint = tint
        tint:SetTexture("Interface\\Buttons\\WHITE8X8")
        tint:ClearAllPoints(); tint:SetAllPoints(fill)
        tint:SetVertexColor(r, g, b, Clamp(effect.tintAlpha or effect.alpha or a, 0.20, 0, 1))
        tint:Show()
    elseif kind == "namecolor" then
        local source = frame and (frame.Name or frame.name or frame.NameText or frame.nameText or frame._nameFS)
        if not source then return false end
        local overlay = root._name or root:CreateFontString(nil, "OVERLAY")
        root._name = overlay
        if source.GetFont and overlay.SetFont then
            local path, size, flags = source:GetFont()
            if path and size then overlay:SetFont(path, size, flags or "") end
        end
        if source.GetText then overlay:SetText(source:GetText()) end
        overlay:ClearAllPoints(); overlay:SetAllPoints(source)
        overlay:SetTextColor(r, g, b, a); overlay:Show()
    else
        ApplyFrameEffectEdges(root, target, effect, kind, r, g, b, a)
    end
    root:Show()
    return true
end

local function ApplyIndicatorVisual(button, cfg)
    -- Unit/group debuff lanes store their compiled dispel-frame visual in
    -- cfg.visual, while custom spell-indicator lanes store a normalized string
    -- in the same field.  Only the string form is an icon-mode instruction;
    -- treating the dispel table as a mode hides every normal debuff icon.
    local visual = type(cfg.visual) == "string" and cfg.visual or "icon"
    if visual ~= "icon" and visual ~= "square" and visual ~= "bar"
        and visual ~= "number" and visual ~= "none" then
        visual = "icon"
    end
    local color = type(cfg.color) == "table" and cfg.color or {}
    local r, g, b, a = Color(color, 0.69, 0.50, 0.88, 1)
    local swatch = button._msufA3ClassicIndicatorSwatch
    if visual == "square" or visual == "bar" then
        if not swatch then
            swatch = button:CreateTexture(nil, "OVERLAY")
            swatch:SetTexture("Interface\\Buttons\\WHITE8X8")
            button._msufA3ClassicIndicatorSwatch = swatch
        end
        swatch:ClearAllPoints(); swatch:SetAllPoints(button)
        swatch:SetVertexColor(r, g, b, a); swatch:Show()
    elseif swatch then
        swatch:Hide()
    end
    local showIcon = visual == "icon"
    if button.Icon then button.Icon:SetShown(showIcon) end
    if visual ~= "icon" and button.Cooldown then button.Cooldown:Hide() end
    if visual == "none" and button.Count then button.Count:Hide() end

    local glow = button._msufA3ClassicIconGlow
    if showIcon and cfg.iconEffect == "glow" then
        if not glow then
            glow = button:CreateTexture(nil, "BACKGROUND")
            glow:SetTexture("Interface\\Buttons\\WHITE8X8")
            button._msufA3ClassicIconGlow = glow
        end
        glow:ClearAllPoints()
        glow:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
        glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
        glow:SetBlendMode("ADD"); glow:SetVertexColor(r, g, b, math_min(a, 0.55)); glow:Show()
    elseif glow then
        glow:Hide()
    end
    return visual
end

function V.UpdateButtonVisual(lane, button, unit, data)
    local cfg = lane and lane.config
    if not (cfg and button) then return end
    V.ApplyButtonLayout(lane, button)
    local visual = ApplyIndicatorVisual(button, cfg)
    if visual == "number" and button.Count then
        local applications = tonumber(data and data.applications) or 1
        button.Count:SetText(applications)
        button.Count:Show()
    end
    ApplyFrameEffect(lane, button, data)
    if cfg.showDurationBar == true then
        local bar = DurationBar(button, cfg)
        local rawDuration = tonumber(data and data.duration)
        local expiration = tonumber(data and data.expirationTime)
        local timed = rawDuration and expiration and rawDuration > 0 and expiration > 0
        if timed then
            bar._msufA3ClassicBarDuration = rawDuration
            bar._msufA3ClassicBarExpiration = expiration
            bar._msufA3ClassicBarElapsed = cfg.durationBarDirection == "ELAPSED"
            bar:SetMinMaxValues(0, rawDuration)
            DurationBarOnUpdate(bar)
            bar:Show()
        else
            -- Reusing a status bar after a timed aura must not retain its
            -- previous timer state for the next permanent aura.
            bar._msufA3ClassicBarDuration = nil
            bar._msufA3ClassicBarExpiration = nil
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(0)
            bar:Hide()
        end
    elseif button._msufA3DurationBar then
        button._msufA3DurationBar:Hide()
    end
end

function V.HideButtonVisual(button)
    if not button then return end
    if button._msufA3DurationBar then button._msufA3DurationBar:Hide() end
    if button._msufA3ClassicIndicatorSwatch then button._msufA3ClassicIndicatorSwatch:Hide() end
    if button._msufA3ClassicIconGlow then button._msufA3ClassicIconGlow:Hide() end
    HideFrameEffect(button)
end

V.DispelTypes = V.DispelTypes or { "Magic", "Curse", "Disease", "Poison", "Bleed" }
V.DispelAtlases = V.DispelAtlases or {
    BLIZZARD = {
        Magic = "RaidFrame-Icon-DebuffMagic", Curse = "RaidFrame-Icon-DebuffCurse",
        Disease = "RaidFrame-Icon-DebuffDisease", Poison = "RaidFrame-Icon-DebuffPoison",
        Bleed = "RaidFrame-Icon-DebuffBleed",
    },
    BLIZZARD_RING = {
        Magic = "ui-debuff-border-magic-icon", Curse = "ui-debuff-border-curse-icon",
        Disease = "ui-debuff-border-disease-icon", Poison = "ui-debuff-border-poison-icon",
        Bleed = "ui-debuff-border-bleed-icon",
    },
    BLIZZARD_BORDER = {
        Magic = "ui-debuff-border-magic-noicon", Curse = "ui-debuff-border-curse-noicon",
        Disease = "ui-debuff-border-disease-noicon", Poison = "ui-debuff-border-poison-noicon",
        Bleed = "ui-debuff-border-bleed-noicon",
    },
}
V.DispelFolders = V.DispelFolders or {
    MSUF_LETTERS = "Letters", MSUF_SHAPES = "Shapes",
    MSUF_GLYPHS = "Glyphs", MSUF_MINIMAL = "Minimal",
}

function V.SetDispelSymbolArt(texture, style, dispelType)
    if not texture then return false end
    style = tostring(style or "BLIZZARD"):upper()
    local folder = V.DispelFolders[style]
    if folder then
        texture:SetTexture(Shape.MEDIA_ROOT .. "\\Media\\Icons\\DispelTypes\\"
            .. folder .. "\\" .. tostring(dispelType):lower() .. ".tga")
        if texture.SetTexCoord then texture:SetTexCoord(0, 1, 0, 1) end
        return true
    end
    local atlas = V.DispelAtlases[style] or V.DispelAtlases.BLIZZARD
    atlas = atlas and atlas[dispelType]
    if atlas and texture.SetAtlas then
        texture:SetAtlas(atlas, _G.TextureKitConstants and _G.TextureKitConstants.IgnoreAtlasSize)
        return true
    end
    texture:SetTexture(nil)
    return false
end

function V.HideDispelSymbols(frame, preview)
    local hostKey = preview == true and "_msufA3ClassicDispelSymbolPreviewHost" or "_msufA3ClassicDispelSymbolHost"
    local activeKey = preview == true and "_msufA3ClassicDispelSymbolPreviewActive" or "_msufA3ClassicDispelSymbolsActive"
    local signatureKey = preview == true and "_msufA3ClassicDispelSymbolPreviewSignature" or "_msufA3ClassicDispelSymbolSignature"
    local host = frame and frame[hostKey]
    local changed = frame and frame[activeKey] == true or false
    if host then host:Hide() end
    if frame then
        frame[activeKey] = nil
        frame[signatureKey] = nil
    end
    return changed
end

function V.DispelPreviewAnchorOffset(host, parent, anchor)
    local hl, hr, ht, hb = host:GetLeft(), host:GetRight(), host:GetTop(), host:GetBottom()
    local pl, pr, pt, pb = parent:GetLeft(), parent:GetRight(), parent:GetTop(), parent:GetBottom()
    if not (hl and hr and ht and hb and pl and pr and pt and pb) then return nil, nil end
    anchor = tostring(anchor or "TOPRIGHT"):upper()
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
    x = x >= 0 and math_floor(x + 0.5) or -math_floor((-x) + 0.5)
    y = y >= 0 and math_floor(y + 0.5) or -math_floor((-y) + 0.5)
    return x, y
end

function V.OnDispelPreviewDragStart(host)
    if _G.InCombatLockdown and _G.InCombatLockdown() then return end
    host:StartMoving()
end

function V.OnDispelPreviewDragStop(host)
    host:StopMovingOrSizing()
    local frame = host._msufA3ClassicDispelPreviewParent
    local visual = host._msufA3ClassicDispelPreviewVisual
    local handler = A3.DispelSymbolPreviewMoveHandler
    if not (frame and visual and visual.symbol) then return end
    local x, y = V.DispelPreviewAnchorOffset(host, frame, visual.symbol.anchor)
    if x == nil then return end
    if type(handler) == "function" then
        handler(_G.MSUF_DispelSymbolPreviewScope, x, y, frame)
    end
    if type(A3.RefreshDispelSymbolPreview) == "function" then A3.RefreshDispelSymbolPreview() end
end

function V.UpdateDispelSymbols(frame, visual, present, preview)
    local hostKey = preview == true and "_msufA3ClassicDispelSymbolPreviewHost" or "_msufA3ClassicDispelSymbolHost"
    local activeKey = preview == true and "_msufA3ClassicDispelSymbolPreviewActive" or "_msufA3ClassicDispelSymbolsActive"
    local signatureKey = preview == true and "_msufA3ClassicDispelSymbolPreviewSignature" or "_msufA3ClassicDispelSymbolSignature"
    local cfg = visual and visual.symbol
    if not (frame and cfg and cfg.enabled == true and type(present) == "table") then
        return V.HideDispelSymbols(frame, preview)
    end
    local selected = {}
    for i = 1, #V.DispelTypes do
        local dispelType = V.DispelTypes[i]
        if present[dispelType] == true then
            selected[#selected + 1] = dispelType
            if cfg.mode ~= "ALL" then break end
        end
    end
    if #selected == 0 then return V.HideDispelSymbols(frame, preview) end
    local signature = table.concat(selected, ",") .. ":" .. tostring(cfg.style) .. ":"
        .. tostring(cfg.size) .. ":" .. tostring(cfg.spacing) .. ":" .. tostring(cfg.growth)
        .. ":" .. tostring(cfg.anchor) .. ":" .. tostring(cfg.x) .. ":" .. tostring(cfg.y)
        .. ":" .. tostring(cfg.alpha) .. ":" .. tostring(cfg.layer) .. ":" .. tostring(cfg.strata)
    local host = frame[hostKey]
    if not host then
        host = CreateFrame("Frame", nil, frame)
        if preview == true then
            host:SetMovable(true)
            host:EnableMouse(true)
            host:RegisterForDrag("LeftButton")
            host:SetScript("OnDragStart", V.OnDispelPreviewDragStart)
            host:SetScript("OnDragStop", V.OnDispelPreviewDragStop)
        elseif host.EnableMouse then
            host:EnableMouse(false)
        end
        host.tiles = {}
        frame[hostKey] = host
    end
    if preview == true then
        host._msufA3ClassicDispelPreviewParent = frame
        host._msufA3ClassicDispelPreviewVisual = visual
    end
    if frame[signatureKey] == signature and host:IsShown() then return false end
    local size = Clamp(cfg.size, 14, 4, 64)
    local spacing = Clamp(cfg.spacing, 2, 0, 32)
    local growth = tostring(cfg.growth or "RIGHT"):upper()
    local horizontal = growth == "RIGHT" or growth == "LEFT"
    local xSign = growth == "LEFT" and -1 or 1
    local ySign = growth == "DOWN" and -1 or 1
    host:ClearAllPoints(); host:SetPoint(cfg.anchor or "TOPRIGHT", frame, cfg.anchor or "TOPRIGHT", cfg.x or 0, cfg.y or 0)
    host:SetSize(horizontal and (#selected * size + math_max(0, #selected - 1) * spacing) or size,
        horizontal and size or (#selected * size + math_max(0, #selected - 1) * spacing))
    if host.SetAlpha then host:SetAlpha(Clamp01(cfg.alpha, 1)) end
    if host.SetFrameStrata and cfg.strata and cfg.strata ~= "AUTO" then host:SetFrameStrata(cfg.strata) end
    if host.SetFrameLevel and frame.GetFrameLevel then host:SetFrameLevel((frame:GetFrameLevel() or 0) + Clamp(cfg.layer, 8, 0, 30)) end
    for i = 1, #selected do
        local tile = host.tiles[i]
        if not tile then
            tile = host:CreateTexture(nil, "OVERLAY")
            host.tiles[i] = tile
        end
        tile:ClearAllPoints(); tile:SetSize(size, size)
        local offset = (i - 1) * (size + spacing)
        if horizontal then
            tile:SetPoint(xSign > 0 and "LEFT" or "RIGHT", host, xSign > 0 and "LEFT" or "RIGHT", offset * xSign, 0)
        else
            tile:SetPoint(ySign > 0 and "BOTTOM" or "TOP", host, ySign > 0 and "BOTTOM" or "TOP", 0, offset * ySign)
        end
        V.SetDispelSymbolArt(tile, cfg.style, selected[i])
        tile:Show()
    end
    for i = #selected + 1, #host.tiles do host.tiles[i]:Hide() end
    frame[activeKey] = true
    frame[signatureKey] = signature
    host:Show()
    return true
end

function V.UpdateDispelSymbolPreview(frame, visual, active)
    if active ~= true then return V.HideDispelSymbols(frame, true) end
    local present = {}
    for i = 1, #V.DispelTypes do present[V.DispelTypes[i]] = true end
    return V.UpdateDispelSymbols(frame, visual, present, true)
end

function V.HideDispelOverlay(frame, preview)
    local hostKey = preview == true and "_msufA3ClassicDispelOverlayPreviewHost" or "_msufA3ClassicDispelOverlayHost"
    local activeKey = preview == true and "_msufA3ClassicDispelOverlayPreviewActive" or "_msufA3ClassicDispelOverlayActive"
    local signatureKey = preview == true and "_msufA3ClassicDispelOverlayPreviewSignature" or "_msufA3ClassicDispelOverlaySignature"
    local host = frame and frame[hostKey]
    local changed = frame and frame[activeKey] == true or false
    if host then host:Hide() end
    if frame then
        frame[activeKey] = nil
        frame[signatureKey] = nil
    end
    return changed
end

--- Scan-backend equivalent of Retail's native AddDispelTypeTexture overlay.
--- It is reached only when the compiled frame visual enables the feature; the
--- disabled path owns no frame, event or API work.
function V.UpdateDispelOverlay(frame, visual, active, r, g, b, a, preview)
    if not (frame and visual and visual.overlayEnabled == true and active == true) then
        return V.HideDispelOverlay(frame, preview)
    end
    local hostKey = preview == true and "_msufA3ClassicDispelOverlayPreviewHost" or "_msufA3ClassicDispelOverlayHost"
    local activeKey = preview == true and "_msufA3ClassicDispelOverlayPreviewActive" or "_msufA3ClassicDispelOverlayActive"
    local signatureKey = preview == true and "_msufA3ClassicDispelOverlayPreviewSignature" or "_msufA3ClassicDispelOverlaySignature"
    local style = tostring(visual.overlayStyle or "FULL"):upper()
    local alpha = Clamp01(visual.overlayAlpha, 0.35) * Clamp01(a, 1)
    r, g, b = Clamp01(r, 0.25), Clamp01(g, 0.75), Clamp01(b, 1)
    local target = visual.overlayOnHealth == true and (frame.hpBar or frame.Health) or frame
    if not target then return V.HideDispelOverlay(frame, preview) end
    local signature = style .. ":" .. tostring(alpha) .. ":" .. tostring(r) .. ":"
        .. tostring(g) .. ":" .. tostring(b) .. ":" .. tostring(target)
    local host = frame[hostKey]
    if not host then
        host = CreateFrame("Frame", nil, frame)
        host:SetAllPoints(frame)
        if host.EnableMouse then host:EnableMouse(false) end
        host.region = host:CreateTexture(nil, "OVERLAY")
        frame[hostKey] = host
    end
    if frame[signatureKey] == signature and host:IsShown() then return false end
    local region = host.region
    region:ClearAllPoints()
    if style == "TOP" then
        region:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
        region:SetPoint("TOPRIGHT", target, "TOPRIGHT", 0, 0)
        region:SetHeight(3)
    elseif style == "BOTTOM" then
        region:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", 0, 0)
        region:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
        region:SetHeight(3)
    elseif style == "LEFT" then
        region:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
        region:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", 0, 0)
        region:SetWidth(3)
    elseif style == "RIGHT" then
        region:SetPoint("TOPRIGHT", target, "TOPRIGHT", 0, 0)
        region:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
        region:SetWidth(3)
    else
        region:SetAllPoints(target)
    end
    region:SetColorTexture(r, g, b, 1)
    region:SetAlpha(alpha)
    if host.SetFrameLevel and frame.GetFrameLevel then host:SetFrameLevel((frame:GetFrameLevel() or 0) + 8) end
    region:Show()
    frame[activeKey] = true
    frame[signatureKey] = signature
    host:Show()
    return true
end

function V.UpdateDispelOverlayPreview(frame, visual, active)
    return V.UpdateDispelOverlay(frame, visual, active,
        visual and visual.r, visual and visual.g, visual and visual.b, 1, true)
end
