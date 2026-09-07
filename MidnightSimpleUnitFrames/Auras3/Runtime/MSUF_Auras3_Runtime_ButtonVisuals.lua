-- Auras3 runtime: ButtonVisuals.
-- One-time icon, text and duration-bar setup plus desired geometry. Native AuraButtons become restricted after initializeFrame; later changes use owner recreation.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.ButtonVisuals = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local SpellIndicatorsRuntime = A3.SpellIndicators
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local tonumber = tonumber
local tostring = tostring
local type = type
local ApplyAuraIconZoom = dependencies.ConfigValues.ApplyAuraIconZoom
local ApplyFont = dependencies.DurationText.ApplyFont
local BuildAuraDurationStyle = dependencies.DurationText.BuildAuraDurationStyle
local Clamp01 = dependencies.Platform.Clamp01
local ClampNumber = dependencies.Platform.ClampNumber
local CreateFrame = dependencies.Platform.CreateFrame
local DEFAULT_SHARED = dependencies.Schema.DEFAULT_SHARED
local DS = dependencies.Appearance.DS
local FrameLayers = dependencies.Platform.FrameLayers
local GetAuraBorderOptions = dependencies.ConfigValues.GetAuraBorderOptions
local ManagedLaneFrameLevel = dependencies.CustomConfig.ManagedLaneFrameLevel
local PlaceCooldownText = dependencies.DurationText.PlaceCooldownText
local PlaceStackText = dependencies.DurationText.PlaceStackText
local ResolveFrameStrata = dependencies.Platform.ResolveFrameStrata
local ResolveLaneParentFrame = dependencies.CustomConfig.ResolveLaneParentFrame
local Shape = dependencies.Appearance.Shape
local SyncFrameStrata = dependencies.Platform.SyncFrameStrata
local ValidateNativeAuraButtonContract = dependencies.NativeContract.ValidateNativeAuraButtonContract

local _durationTextOptions = { zeroDurationText = "", expiredText = "" }
local _durationBarOptions = {}
local _applicationCountOptions = {}
local _auraSymbolOptions = { showWhenHarmful = true, showWhenHelpful = false }
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
        local visualParent = parentFrame._msufHealthVisualRoot or parentFrame
        if lane.portraitOverlay == true and layoutHost.GetParent
            and layoutHost:GetParent() ~= visualParent and layoutHost.SetParent then
            layoutHost:SetParent(visualParent)
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
    -- The container level above moves every descendant with it, including the
    -- Pandemic full-frame effect surfaces bound to this lane's AuraButtons. Put
    -- them back on their configured absolute Layer.
    if parentFrame then SpellIndicatorsRuntime.RefreshFrameEffects(parentFrame) end
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

return {
    PrepareAuraButton = PrepareAuraButton,
    SyncContainerGeometry = SyncContainerGeometry,
}
end
