local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
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
local STANDARD_TEXT_FONT = dependencies.Platform.STANDARD_TEXT_FONT
local ValidateNativeAuraButtonContract = dependencies.NativeContract.ValidateNativeAuraButtonContract
local Register = MSUF.RunNativeAuraRegistration or function(_, method, owner, ...) method(owner, ...) return true end

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

-- The icon style painters (shadow, border ring, shaped rings) and
-- A3.ApplyIconStylePreview are shared with the Classic backend in
-- Auras3/MSUF_Auras3_IconShape.lua.
local ApplyIconStyleShadow = Shape.ApplyIconShadow
local ApplyIconStyleBorder = Shape.ApplyIconBorder

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
        overlay = PixelLayoutRegion(CreateFrame("Frame", nil, visualOwner))
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

local function StyleFontString(fs, size)
    ApplyFont(fs, size)
    if not fs:GetFont() then fs:SetFont(STANDARD_TEXT_FONT, ClampNumber(size, 12, 6, 40), "OUTLINE") end
    return fs:GetFont() ~= nil
end

local function Bind(button, setName, clearName, region, ...)
    if region and Register(setName, button[setName], button, region, ...) then return true end
    if region then region:Hide() end
    Register(clearName, button[clearName], button)
    return false
end

local PrepareStage = {}

function PrepareStage.BindLaneIdentity(button, lane, index)
    ValidateNativeAuraButtonContract(button)
    button._msufA3NativeButton = true
    button._msufA3LaneKind = lane.kind
    button._msufA3LaneIndex = index
    LayoutButton(button, lane, index)
    button:SetAlpha(1)
end

function PrepareStage.ResolveVisualOwner(button, lane)
    local visualOwner = button
    if lane.kind == "spellIndicator" and lane.frameEffect and lane.visual ~= "none" then
        visualOwner = button._msufA3SpellIndicatorVisualHost
        if not visualOwner then
            visualOwner = PixelLayoutRegion(CreateFrame("Frame", nil, button))
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
    return visualOwner
end

function PrepareStage.PrepareIcon(button, lane, index, visualOwner)
    local spellIndicatorBar = lane.kind == "spellIndicator" and lane.visual == "bar"
    local barOnly = spellIndicatorBar
        or (lane.showDurationBar == true and lane.durationBarDisplay == "BAR_ONLY")
    local icon = button.Icon
    if barOnly then
        if icon then
            icon:SetAlpha(0)
            icon:Hide()
        end
        return barOnly, spellIndicatorBar, icon
    end
    if not icon then
        icon = PixelLayoutRegion(visualOwner:CreateTexture(nil, "ARTWORK", nil, lane.portraitOverlay == true and 1 or 0))
        button.Icon = icon
    elseif lane.portraitOverlay == true and icon.SetDrawLayer then
        icon:SetDrawLayer("ARTWORK", 1)
    end
    icon:ClearAllPoints()
    icon:SetAllPoints(visualOwner)
    ApplyAuraIconZoom(icon, lane)
    icon:SetAlpha(1)
    icon:Show()
    if lane.portraitOverlay == true and index == 1 then
        local holder = button._msufA3ParentFrame
        local mask = holder and holder.mask
        if mask and icon.AddMaskTexture then icon:AddMaskTexture(mask) end
    end
    return barOnly, spellIndicatorBar, icon
end

function PrepareStage.PrepareCooldownSwipe(button, lane, visualOwner, barOnly)
    local cooldown = button._msufA3Cooldown
    if lane.showCooldownSwipe ~= true or barOnly then
        if cooldown then cooldown:Hide() end
        return nil
    end
    local cooldownAnchor, cooldownLevel = A3._AuraCooldownAnchorAndLevel(button, lane)
    if not cooldown then
        cooldown = PixelLayoutRegion(CreateFrame("Cooldown", nil, visualOwner, "CooldownFrameTemplate"))
        button._msufA3Cooldown = cooldown
    end
    cooldown:ClearAllPoints()
    cooldown:SetAllPoints(cooldownAnchor or button)
    if cooldown.SetDrawSwipe then cooldown:SetDrawSwipe(true) end
    if cooldown.SetSwipeColor then cooldown:SetSwipeColor(0, 0, 0, 0.58) end
    if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(true) end
    if cooldown.SetDrawBling then cooldown:SetDrawBling(false) end
    if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
    if cooldown.SetReverse then cooldown:SetReverse(lane.cooldownSwipeReverse == true) end
    if cooldown.SetFrameLevel then cooldown:SetFrameLevel(cooldownLevel) end
    cooldown:Show()
    return cooldown
end

function PrepareStage.ApplyIconShape(button, lane, visualOwner, barOnly, icon)
    local iconShape = not barOnly and (lane.iconShape or Shape.RECTANGLE) or Shape.RECTANGLE
    A3.ApplyAuraIconShape(visualOwner, iconShape, button._msufA3Cooldown, icon)
    return iconShape
end

function PrepareStage.PrepareDurationBar(button, lane, visualOwner, spellIndicatorBar)
    local bar = button._msufA3DurationBar
    if lane.showDurationBar ~= true then
        if bar then bar:Hide() end
        return nil
    end
    if not bar then
        bar = PixelLayoutRegion(CreateFrame("StatusBar", nil, visualOwner))
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        button._msufA3DurationBar = bar
    end
    if bar.SetFrameLevel then
        bar:SetFrameLevel((visualOwner:GetFrameLevel() or 0) + (FrameLayers.AURA_DURATION_BAR_LEVEL_OFFSET or 2))
    end
    if spellIndicatorBar then
        bar:ClearAllPoints()
        bar:SetAllPoints(visualOwner)
        local color = lane.color or {}
        bar:SetStatusBarColor(Clamp01(color[1], 0.69), Clamp01(color[2], 0.50), Clamp01(color[3], 0.88), Clamp01(color[4], 1))
    else
        LayoutDurationBar(visualOwner, bar, lane)
        ApplyDurationBarColor(bar)
    end
    if bar.SetReverseFill then
        bar:SetReverseFill(spellIndicatorBar and lane.durationBarReverseFill == true or false)
    end
    bar:Show()
    return bar
end

function PrepareStage.ResolveTextOverlay(button, lane)
    if lane.showCooldownText == true or lane.showStacks == true then
        return EnsureAuraTextOverlay(button, lane) or button
    end
    return nil
end

function PrepareStage.PrepareCooldownText(button, lane, textOverlay)
    local duration = button.Text or button.DurationText
    if lane.showCooldownText ~= true then
        if duration then duration:Hide() end
        return nil
    end
    if not duration or (duration.GetParent and duration:GetParent() ~= textOverlay) then
        if duration then duration:Hide() end
        duration = PixelLayoutRegion(textOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormal"))
        button.Text = duration
    end
    duration:Hide()
    if not StyleFontString(duration, lane.cooldownSize) then return nil end
    if duration.SetDrawLayer then
        duration:SetDrawLayer("OVERLAY", FrameLayers.AURA_COOLDOWN_TEXT_DRAW_SUBLEVEL or 7)
    end
    PlaceCooldownText(duration, textOverlay, lane)
    duration:Show()
    return duration
end

function PrepareStage.PrepareStackText(button, lane, textOverlay)
    local count = button._msufA3ApplicationCount or button.Count or button.ApplicationCount
    if lane.showStacks ~= true then
        if count then count:Hide() end
        return nil
    end
    if not count or (count.GetParent and count:GetParent() ~= textOverlay) then
        if count then count:Hide() end
        count = PixelLayoutRegion(textOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormal"))
        button._msufA3ApplicationCount = count
    end
    button.Count = count
    count:Hide()
    if not StyleFontString(count, lane.stackSize) then return nil end
    if count.SetDrawLayer then
        count:SetDrawLayer("OVERLAY", FrameLayers.AURA_STACK_DRAW_SUBLEVEL or 6)
    end
    PlaceStackText(count, textOverlay, lane)
    count:Show()
    return count
end

function PrepareStage.PrepareAuraBorder(button, lane, visualOwner, barOnly, iconShape)
    if lane.showAuraBorder ~= true or barOnly then
        if button._msufA3AuraBorder and button._msufA3AuraBorder.Hide then button._msufA3AuraBorder:Hide() end
        return nil
    end
    local border = button._msufA3AuraBorder or button.AuraBorder or button.Border
    if not border then
        border = PixelLayoutRegion(visualOwner:CreateTexture(nil, "OVERLAY"))
    end
    local shapedDispel = iconShape ~= Shape.RECTANGLE and A3.AuraShapeBorderPath(iconShape) or nil
    LayoutAuraBorder(visualOwner, border, lane, shapedDispel == nil)
    if shapedDispel then
        border:SetTexture(shapedDispel)
        if border.SetTexCoord then border:SetTexCoord(0, 1, 0, 1) end
    end
    button._msufA3AuraBorder = border
    return border, GetAuraBorderOptions(lane.showAuraSymbol, shapedDispel ~= nil)
end

function PrepareStage.PrepareStealableMarker(button, lane, visualOwner, barOnly)
    local marker = button._msufA3StealableMarker
    if lane.showStealableMarker ~= true or barOnly then
        if marker then marker:Hide() end
        return nil
    end
    if not marker then
        marker = PixelLayoutRegion(visualOwner:CreateTexture(nil, "OVERLAY", nil, 5))
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
    return marker, A3.GetStealableTextureOptions(lane.stealableStyle)
end

function PrepareStage.PrepareAuraSymbol(button, lane, visualOwner, barOnly, border)
    if lane.showAuraSymbol ~= true or not border or barOnly then
        if button._msufA3AuraSymbol and button._msufA3AuraSymbol.Hide then button._msufA3AuraSymbol:Hide() end
        return nil
    end
    local symbol = button._msufA3AuraSymbol or button.AuraSymbol or button.Symbol
    if not symbol then
        symbol = PixelLayoutRegion(visualOwner:CreateFontString(nil, "OVERLAY", "GameFontNormal"))
    end
    button._msufA3AuraSymbol = symbol
    button.Symbol = symbol
    symbol:ClearAllPoints()
    symbol:SetPoint("BOTTOMRIGHT", visualOwner, "BOTTOMRIGHT", -1, 1)
    symbol:SetJustifyH("RIGHT")
    symbol:SetJustifyV("BOTTOM")
    if not StyleFontString(symbol, math_min(lane.stackSize or DEFAULT_SHARED.stackTextSize, 14)) then
        symbol:Hide()
        return nil
    end
    return symbol
end

function PrepareStage.ApplyIconStyle(lane, visualOwner, barOnly, iconShape)
    local style
    if not barOnly then style = lane.iconStyle end
    local size = lane.size or 0
    ApplyIconStyleShadow(visualOwner, style, size, iconShape)
    ApplyIconStyleBorder(visualOwner, style, size, iconShape)
end

function PrepareStage.BindDurationText(button, lane, duration)
    if not duration then return Bind(button, "SetDurationText", "ClearDurationText", nil) end
    local style = BuildAuraDurationStyle(lane)
    if style then
        _durationTextOptions.textFormatter = style.formatter
        _durationTextOptions.formatter = style.formatter
        _durationTextOptions.binding = style.binding
        _durationTextOptions.updateInterval = style.updateInterval
    end
    local bound = Register("SetDurationText", button.SetDurationText, button, duration, _durationTextOptions)
    _durationTextOptions.textFormatter = nil
    _durationTextOptions.formatter = nil
    _durationTextOptions.binding = nil
    _durationTextOptions.updateInterval = nil
    return bound or Bind(button, "SetDurationText", "ClearDurationText", duration, _durationTextOptions)
end

function PrepareStage.BindDispelTextures(button, regions)
    local border, marker = regions.border, regions.marker
    for _ = 1, 2 do
        Register("ClearDispelTypeTextures", button.ClearDispelTypeTextures, button)
        local failed = false
        if border and not Register("AddDispelTypeTexture", button.AddDispelTypeTexture, button, border, regions.borderOptions) then
            border:Hide()
            border, failed = nil, true
        end
        if not failed and marker
            and not Register("AddDispelTypeTexture", button.AddDispelTypeTexture, button, marker, regions.markerOptions) then
            marker:Hide()
            marker, failed = nil, true
        end
        if not failed then return border end
    end
    Register("ClearDispelTypeTextures", button.ClearDispelTypeTextures, button)
    return nil
end

function PrepareStage.BindRegions(button, lane, regions)
    local cancelable = lane.unit == "player" and lane.kind == "buff"
    Register("SetMouseClickEnabled", button.SetMouseClickEnabled, button, cancelable)
    if cancelable then Register("SetCancelAuraButtons", button.SetCancelAuraButtons, button, "RightButtonUp") end
    Bind(button, "SetIcon", "ClearIcon", regions.icon)
    Bind(button, "SetDurationCooldown", "ClearDurationCooldown", regions.cooldown)
    Bind(button, "SetDurationBar", "ClearDurationBar", regions.bar, regions.bar and ResolveDurationBarOptions(lane))
    PrepareStage.BindDurationText(button, lane, regions.duration)
    Bind(button, "SetApplicationCount", "ClearApplicationCount", regions.count, _applicationCountOptions)
    local border = PrepareStage.BindDispelTextures(button, regions)
    if regions.symbol and not border then regions.symbol:Hide() end
    Bind(button, "SetDispelTypeText", "ClearDispelTypeText", border and regions.symbol, _auraSymbolOptions)
    if not Register("BindPandemicRegion", A3.BindPandemicRegion, button, lane) and button.ClearPandemicRegions then
        Register("ClearPandemicRegions", button.ClearPandemicRegions, button)
    end
    local wantTooltip = lane.showTooltip ~= false
    Register("SetMouseMotionEnabled", button.SetMouseMotionEnabled, button, wantTooltip)
    if wantTooltip and button.SetTooltipAnchorPoint then
        Register("SetTooltipAnchorPoint", button.SetTooltipAnchorPoint, button, lane.auraTooltipAnchor or "ANCHOR_BOTTOMRIGHT")
        if button.SetHideTooltipInCombat then
            Register("SetHideTooltipInCombat", button.SetHideTooltipInCombat, button, false)
        end
    end
end

local function PrepareAuraButton(button, lane, index)
    PixelLayoutRegion(button)
    PrepareStage.BindLaneIdentity(button, lane, index)
    local visualOwner = PrepareStage.ResolveVisualOwner(button, lane)
    local regions = {}
    local barOnly, spellIndicatorBar, icon = PrepareStage.PrepareIcon(button, lane, index, visualOwner)
    if not barOnly then regions.icon = icon end
    regions.cooldown = PrepareStage.PrepareCooldownSwipe(button, lane, visualOwner, barOnly)
    local iconShape = PrepareStage.ApplyIconShape(button, lane, visualOwner, barOnly, icon)
    regions.bar = PrepareStage.PrepareDurationBar(button, lane, visualOwner, spellIndicatorBar)
    local textOverlay = PrepareStage.ResolveTextOverlay(button, lane)
    regions.duration = PrepareStage.PrepareCooldownText(button, lane, textOverlay)
    regions.count = PrepareStage.PrepareStackText(button, lane, textOverlay)
    regions.border, regions.borderOptions = PrepareStage.PrepareAuraBorder(button, lane, visualOwner, barOnly, iconShape)
    regions.marker, regions.markerOptions = PrepareStage.PrepareStealableMarker(button, lane, visualOwner, barOnly)
    regions.symbol = PrepareStage.PrepareAuraSymbol(button, lane, visualOwner, barOnly, regions.border)
    PrepareStage.ApplyIconStyle(lane, visualOwner, barOnly, iconShape)
    PrepareStage.BindRegions(button, lane, regions)
    button._msufA3LaneLayoutSignature = lane._msufA3LayoutSignature
end

return {
    PrepareAuraButton = PrepareAuraButton,
    SyncContainerGeometry = SyncContainerGeometry,
}
end
