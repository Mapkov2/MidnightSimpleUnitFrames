-- Unit preview geometry, measured footprint and canvas placement.
-- Receives the already compiled scene; keeps all existing fit and scale rules.
local _, MSUF = ...
local MenuState = MSUF.MSUF2
local RequireFields = MenuState.PreviewContracts.RequireFields
local Layout = {}
MSUF.UFPreviewLayout = Layout
function Layout.Install(Stage, shared)
    RequireFields("UnitLayout.Stage", Stage, "")
    RequireFields("UnitLayout.Shared", shared,
        "AnimatedPreviewData PreviewLayerWanted RefillTable BodyAliases StatusRegions Empty")
    local AnimatedPreviewData, PreviewLayerWanted = shared.AnimatedPreviewData, shared.PreviewLayerWanted
    local RefillTable, BODY_ALIASES = shared.RefillTable, shared.BodyAliases
    local STATUS_REGIONS, EMPTY = shared.StatusRegions, shared.Empty
    local Render = MSUF.UFPreviewRender
    local EnsureDB = MenuState.EnsureDB
    local CPPreview = MenuState.ClassPowerPreview or {}
    local Layers = MSUF.UF and MSUF.UF.Layers or {}
    local floor, min, max = math.floor, math.min, math.max
    local Castbar = RequireFields("UnitLayout.Castbar", MSUF.UFPreviewCastbar, "ShowTargetName")
    local CastbarShowTargetName = Castbar.ShowTargetName
local function ResolvePreviewBodyOffsets(centerX, centerY, scale, manualZoom, frozenX, frozenY)
    if frozenX ~= nil and frozenY ~= nil then return frozenX, frozenY end
    -- Fit mode centers the complete configured footprint. At a manual zoom,
    -- keep the unit body as the stable focal point instead: valid auxiliary
    -- layouts can sit hundreds of pixels away and must not exile the body from
    -- the canvas. Explicit canvas pan is applied separately below.
    if manualZoom ~= nil then return 0, 0 end
    scale = tonumber(scale) or 1
    return -floor(((tonumber(centerX) or 0) * scale) + 0.5),
        -floor(((tonumber(centerY) or 0) * scale) + 0.5)
end
Render.ResolvePreviewBodyOffsets = ResolvePreviewBodyOffsets
-- The container width is the live class resource layout's rule (player frame
-- width, custom width, pip auto-fit, Cooldown Manager viewer), shared with the
-- Class Resources page preview; only the canvas clamp is this preview's own.
local function PreviewClassPowerWidth(bars, frameW, cpH, segCount)
    local w = tonumber(CPPreview.ContainerWidth(bars, frameW, cpH, segCount)) or frameW
    if w < 1 then w = 1 elseif w > 800 then w = 800 end
    return w
end
Layout.ClassPowerWidth = PreviewClassPowerWidth
local ResolvePreviewPowerShape = CPPreview.ResolvePowerShape
local function Clamp01(v)
    if v < 0 then return 0 elseif v > 1 then return 1 end
    return v
end
-- Live frames supply optional geometry; the scene owns sampled artwork.
local function PreviewLiveFrame(key)
    local uf = MSUF.UF
    local unit = (key == "boss" and "boss1") or (key == "arena" and "arena1") or key
    local frame = uf.GetFrame and uf.GetFrame(unit) or nil
    if not frame then frame = uf.frames and uf.frames[unit] or nil end
    return frame
end
local function PreviewLivePowerBar(key)
    local frame = PreviewLiveFrame(key)
    return frame and (frame.targetPowerBar or frame.powerBar or frame.Power) or nil
end
local function PointCoord(point, w, h)
    point = tostring(point or "CENTER"):upper()
    local x = (point:find("RIGHT", 1, true) and w) or (point:find("LEFT", 1, true) and 0) or (w * 0.5)
    local y = (point:find("TOP", 1, true) and h) or (point:find("BOTTOM", 1, true) and 0) or (h * 0.5)
    return x, y
end
local function ExpandRect(minX, maxX, minY, maxY, left, bottom, right, top)
    if not (left and bottom and right and top) then return minX, maxX, minY, maxY end
    return min(minX, left), max(maxX, right), min(minY, bottom), max(maxY, top)
end
local function ExpandAnchoredRect(minX, maxX, minY, maxY, point, relPoint, x, y, rw, rh, targetW, targetH)
    rw, rh = tonumber(rw) or 1, tonumber(rh) or 1
    local tx, ty = PointCoord(relPoint or point, tonumber(targetW) or 0, tonumber(targetH) or 0)
    local px, py = PointCoord(point, rw, rh)
    local left = tx + (tonumber(x) or 0) - px
    local bottom = ty + (tonumber(y) or 0) - py
    return ExpandRect(minX, maxX, minY, maxY, left, bottom, left + rw, bottom + rh)
end
-- The Class Resources page previews the picked resource; every other page shows a generic five-pip bar.
local GENERIC_CLASS_POWER_SPEC = { key = "generic", mode = "segmented", segments = 5, value = 3, specIndex = 1, class = "ROGUE" }

--- Canvas size, frame size, portrait side/placement/size/border and castbar
--- size/offsets, plus the boss border inset.
function Stage.ResolveFrameGeometry(st)
    local box, conf, g, key, runtimeSpec = st.box, st.conf, st.g, st.key, st.runtimeSpec
    local RenderState, PortraitStyleGet, max, Auras = st.R, st.PortraitStyleGet, st.max, st.Auras
    local canvas = box.canvas
    local cw = canvas:GetWidth() or 600
    local ch = canvas:GetHeight() or 180
    if cw <= 1 then cw = 600 end
    if ch <= 1 then ch = 180 end
    local w = tonumber(runtimeSpec and runtimeSpec.width) or tonumber(conf.width or conf.frameWidth)
        or ((key == "boss" or key == "arena") and 180 or (key == "focus" and 180 or 275))
    local h = tonumber(runtimeSpec and runtimeSpec.height) or tonumber(conf.height or conf.frameHeight)
        or ((key == "boss" or key == "arena") and 30 or (key == "focus" and 30 or 40))
    w, h = RenderState.ClampUnitPreviewSize(w, h)
    local pspec = runtimeSpec and runtimeSpec.portrait
    local mode = (pspec and pspec.side) or conf.portraitMode
    local hasPortrait
    if pspec then
        hasPortrait = pspec.enabled == true
    else
        hasPortrait = (mode == "LEFT" or mode == "RIGHT")
    end
    box._runtimeDefensivePortraitPositionOnly = not hasPortrait
        and Auras and Auras.WantsDefensivePortraitAnchor
        and Auras.WantsDefensivePortraitAnchor(key, runtimeSpec) == true
        or false
    local showsPortrait = hasPortrait or box._runtimeDefensivePortraitPositionOnly
    if showsPortrait and mode ~= "RIGHT" then mode = "LEFT" end
    local pSize = showsPortrait
        and (tonumber(pspec and pspec.size) or tonumber(PortraitStyleGet(key, "portraitSizeOverride", 0)) or 0)
        or 0
    if pSize <= 0 then pSize = max(22, h - 4) end
    -- Placement/geometry mirrors of the live spec. Parked on the box because the
    -- later stages (portrait, power bar, overlays) read them from there.
    box._runtimePortraitPlacement = (pspec and pspec.placement) or PortraitStyleGet(key, "portraitPlacement", "ATTACHED") or "ATTACHED"
    box._runtimePortraitPoint = (pspec and pspec.point) or PortraitStyleGet(key, "portraitDetachedPoint", "RIGHT") or "RIGHT"
    box._runtimePortraitRelPoint = (pspec and pspec.relPoint) or PortraitStyleGet(key, "portraitDetachedTo", "LEFT") or "LEFT"
    box._runtimePortraitOverlayAlign = (pspec and pspec.overlayAlign) or PortraitStyleGet(key, "portraitOverlayAlign", "LEFT") or "LEFT"
    box._runtimePortraitAlpha = tonumber(pspec and pspec.alpha) or ((tonumber(PortraitStyleGet(key, "portraitAlpha", 100)) or 100) / 100)
    box._runtimePortraitW = tonumber(pspec and pspec.width) or (tonumber(PortraitStyleGet(key, "portraitWidth", 0)) or 0)
    box._runtimePortraitH = tonumber(pspec and pspec.height) or (tonumber(PortraitStyleGet(key, "portraitHeight", 0)) or 0)
    if box._runtimePortraitW <= 0 then box._runtimePortraitW = pSize end
    if box._runtimePortraitH <= 0 then box._runtimePortraitH = pSize end
    -- Auto size (Size override = 0) is resolved by the live Portrait element.
    -- Edit Mode displays that applied holder, so consume the same final geometry
    -- instead of letting Menu2 maintain a second approximation of the auto path.
    if (pspec and pspec.sizeMode) == "SEPARATE"
        or (tonumber(PortraitStyleGet(key, "portraitSizeOverride", 0)) or 0) <= 0
    then
        local appliedW, appliedH = RenderState.RuntimeAppliedPortraitSizeForPreviewKey(key)
        box._runtimeAppliedPortraitW, box._runtimeAppliedPortraitH = appliedW, appliedH
        if tonumber(appliedW) and appliedW > 0 then box._runtimePortraitW = appliedW end
        if tonumber(appliedH) and appliedH > 0 then box._runtimePortraitH = appliedH end
    else
        box._runtimeAppliedPortraitW, box._runtimeAppliedPortraitH = nil, nil
    end
    local border = pspec and pspec.border
    box._runtimePortraitBorderStyle = (border and border.style) or PortraitStyleGet(key, "portraitBorderStyle", "NONE") or "NONE"
    box._runtimePortraitBorderThickness = 0
    box._runtimePortraitBorderFill = false
    if hasPortrait and box._runtimePortraitBorderStyle ~= "NONE" then
        box._runtimePortraitBorderThickness = max(1, tonumber(border and border.thickness)
            or tonumber(PortraitStyleGet(key, "portraitBorderThickness", 2)) or 2)
        box._runtimePortraitBorderFill = (border and border.fill == true)
            or (not border and PortraitStyleGet(key, "portraitFillBorder", false) == true)
    end
    local castbarSpec = runtimeSpec and runtimeSpec.castbar
    local castEnabled = castbarSpec and castbarSpec.enabled == true
    if not castbarSpec then castEnabled = st.CastbarEnabled(key, g) end
    if box._msuf2ColorPainterForceCastbar == true then castEnabled = true end
    local castW, castBarH = st.ReadCastbarSize(key, g, w, (key == "boss" or key == "arena") and 12 or 18)
    local castXKey, castYKey, castDefX, castDefY = st.CastbarOffsetFields(key)
    local castOffsetX = castXKey and tonumber(g[castXKey]) or nil
    local castOffsetY = castYKey and tonumber(g[castYKey]) or nil
    if castOffsetX == nil then castOffsetX = tonumber(castDefX) or 0 end
    if castOffsetY == nil then castOffsetY = tonumber(castDefY) or 0 end
    local castDetached = castEnabled and st.CastbarDetached(key, g)
    -- Projected position of a detached castbar, from the live layout.
    box._detachedCastProjectedX, box._detachedCastProjectedY = nil, nil
    if castDetached and RenderState.DetachedCastbarOffsetForPreviewKey then
        box._detachedCastProjectedX, box._detachedCastProjectedY = RenderState.DetachedCastbarOffsetForPreviewKey(key)
        if tonumber(box._detachedCastProjectedX) and tonumber(box._detachedCastProjectedY) then
            castOffsetX, castOffsetY = box._detachedCastProjectedX, box._detachedCastProjectedY
        end
    end
    box._bossBorderInset = 0
    if (key == "boss" or key == "arena")
        and runtimeSpec and runtimeSpec.border
        and runtimeSpec.border.enabled == true
    then
        box._bossBorderInset = max(1, st.floor((tonumber(runtimeSpec.border.thickness) or 1) + 0.5))
    end
    box._bossCastbarGap = 3
    st.canvas, st.cw, st.ch, st.w, st.h, st.mode, st.hasPortrait = canvas, cw, ch, w, h, mode, hasPortrait
    st.castEnabled, st.castDetached, st.castPreviewVisible = castEnabled, castDetached, castEnabled and PreviewLayerWanted(box, "castbar")
    st.castW, st.castBarH, st.castOffsetX, st.castOffsetY = castW, castBarH, castOffsetX, castOffsetY
end

--- Class power preview spec, embedded/attached/detached power bar geometry,
--- combat animation state and the detached bar width/height.
function Stage.ResolvePowerGeometry(st)
    local box, conf, key, w, max = st.box, st.conf, st.key, st.w, st.max
    local runtimePower, runtimeClassPower, data = st.runtimePower, st.runtimeClassPower, st.data
    local isPlayer = key == "player"
    local bars = EnsureDB().bars or {}
    local classPowerPreviewSpec
    if isPlayer then
        local menu = MSUF.MSUF2 or MenuState
        if menu.activeKey == "classpower" and menu.GetClassPowerPreviewSpec then
            classPowerPreviewSpec = menu.GetClassPowerPreviewSpec()
        end
    end
    if classPowerPreviewSpec then
        local getClassToken = MenuState.GetClassPowerPreviewClassToken
        local previewClass = getClassToken and getClassToken() or nil
        previewClass = previewClass or classPowerPreviewSpec.classToken or classPowerPreviewSpec.class
        if previewClass and data.class ~= previewClass then
            local copy = RefillTable(box._msufPreviewClassData or {}, data)
            box._msufPreviewClassData = copy
            copy.class = tostring(previewClass):upper()
            data = copy
        end
    end
    local powerAllowed = runtimePower and runtimePower.enabled == true
    if runtimePower == nil then powerAllowed = st.D.ReadPowerBarEnabled(conf, key) end
    local detachedPower = st.CanDetachPowerBarKey(key) and powerAllowed and ((runtimePower and runtimePower.detached == true)
        or (runtimePower == nil and conf.powerBarDetached == true))
    box._runtimePowerEmbedded = powerAllowed and not detachedPower and (
        (runtimePower and runtimePower.embed ~= false)
        or (runtimePower == nil and conf.embedPowerBarIntoHealth == true)
        or (runtimePower == nil and conf.embedPowerBarIntoHealth == nil and bars.embedPowerBarIntoHealth ~= false)
    ) or false
    box._runtimePowerAttached = powerAllowed and not detachedPower and box._runtimePowerEmbedded ~= true
    box._runtimeHealthPowerInset = box._runtimePowerEmbedded == true
        and max(0, tonumber(runtimePower and runtimePower.height) or tonumber(st.ReadPowerBarHeight(conf)) or 0)
        or 0
    local classPowerOn = isPlayer and runtimeClassPower and runtimeClassPower.enabled == true or false
    if isPlayer and runtimeClassPower == nil then classPowerOn = bars.showClassPower ~= false end
    if classPowerPreviewSpec then
        classPowerOn = bars.showClassPower ~= false and classPowerPreviewSpec.enabled ~= false
            and classPowerPreviewSpec.mode ~= "none"
    end
    local powerFrac = tonumber(data.power) or 1
    if not detachedPower and not isPlayer and data.live ~= true then powerFrac = 1 end
    powerFrac = Clamp01(powerFrac)
    -- The animation tick rebuilds the animated data from these two.
    st.baseData, st.basePowerFrac = data, powerFrac
    local animState
    data, powerFrac, animState = AnimatedPreviewData(st, data, powerFrac)
    local cpH = classPowerOn and (tonumber(bars.classPowerHeight) or 4) or 0
    if cpH < 2 then cpH = 2 elseif cpH > 30 then cpH = 30 end
    local cpSpec = classPowerPreviewSpec or GENERIC_CLASS_POWER_SPEC
    local classPowerSegCount = CPPreview.SegmentCount(cpSpec)
    box._runtimeClassPowerW = classPowerOn and PreviewClassPowerWidth(bars, w, cpH, classPowerSegCount) or 0
    -- Augmentation no longer builds a composite surface: Ebon Might is rendered
    -- by the ordinary Player Power bar and Essence stays an ordinary Class
    -- Resource, so there is no second class row and no shared geometry. Only the
    -- power bar's *content* changes, which the render pass reads from
    -- _runtimePowerEbonMight below.
    box._runtimeClassPowerSecondarySpec = classPowerPreviewSpec and classPowerPreviewSpec.secondaryTimer
    box._runtimePowerEbonMight = isPlayer
        and classPowerOn
        and type(box._runtimeClassPowerSecondarySpec) == "table"
        and not box._playerManaSourcePreviewActive
        and bars.showEbonMight ~= false
        and classPowerPreviewSpec and classPowerPreviewSpec.key == "evoker_augmentation_ebon" or false
    box._runtimeDetachedPowerSyncClass = isPlayer and ((runtimePower and runtimePower.detachedSyncClass == true)
        or (runtimePower == nil and conf.detachedPowerBarSyncClassPower ~= false)) or false
    box._runtimeDetachedPowerX = tonumber(runtimePower and runtimePower.detachedX) or tonumber(conf.detachedPowerBarOffsetX) or 0
    box._runtimeDetachedPowerY = tonumber(runtimePower and runtimePower.detachedY) or tonumber(conf.detachedPowerBarOffsetY) or -4
    box._runtimeDetachedPowerAnchorMode = tostring((runtimePower and runtimePower.detachedAnchorMode)
        or conf.detachedPowerBarAnchorMode or "CENTER"):upper()
    box._runtimeDetachedPowerAnchorClass = isPlayer and ((runtimePower and runtimePower.detachedAnchorClass == true)
        or (runtimePower == nil and conf.detachedPowerBarAnchorToClassPower == true))
    box._runtimeDetachedPowerTextOnBar = (runtimePower and runtimePower.textOnDetached == true)
        or (runtimePower == nil and conf.detachedPowerBarTextOnBar == true)
    box._runtimeDetachedPowerShape = isPlayer
        and ResolvePreviewPowerShape((runtimePower and runtimePower.shape) or conf.detachedPowerBarShape or "FOLLOW_CLASS", bars.classPowerShape)
        or "BAR"
    local resolveDetachedPowerWidth = CPPreview.ResolveDetachedPowerWidth
    if detachedPower and resolveDetachedPowerWidth then
        box._runtimeDetachedPowerW = resolveDetachedPowerWidth({
            -- The live replacement resolver deliberately avoids ClassPower as
            -- both width and anchor input: ClassPower itself consumes this
            -- carrier.  Avoid the preview helper's live/class shortcuts too.
            liveFrame = PreviewLiveFrame(key),
            livePower = runtimePower,
            shape = box._runtimeDetachedPowerShape,
            orbSize = (runtimePower and runtimePower.orbSize) or conf.detachedPowerOrbSize,
            syncClass = box._runtimeDetachedPowerSyncClass,
            classWidth = classPowerOn and box._runtimeClassPowerW or nil,
            classFallbackWidth = (runtimePower and runtimePower.detachedClassWidth) or (w - 4),
            widthFrameName = runtimePower and runtimePower.detachedWidthFrameName,
            widthMode = bars.detachedPowerBarWidthMode,
            manualWidth = (runtimePower and runtimePower.detachedWidth) or conf.detachedPowerBarWidth,
            explicitWidth = (runtimePower and runtimePower.detachedWidthExplicit) or tonumber(conf.detachedPowerBarWidth),
            frameWidth = w,
            relativeTo = PreviewLivePowerBar(key),
        })
    else
        box._runtimeDetachedPowerW = tonumber(runtimePower and runtimePower.detachedWidth) or tonumber(conf.detachedPowerBarWidth) or w
    end
    local detachedH = detachedPower
        and (tonumber(runtimePower and runtimePower.detachedHeight) or tonumber(conf.detachedPowerBarHeight) or 6) or 0
    if detachedH < 2 then detachedH = 2 elseif detachedH > 800 then detachedH = 800 end
    if detachedPower and box._runtimeDetachedPowerShape == "ORB" then
        local orbSize = tonumber(runtimePower and runtimePower.orbSize) or tonumber(conf.detachedPowerOrbSize) or 54
        if orbSize < 20 then orbSize = 20 elseif orbSize > 160 then orbSize = 160 end
        box._runtimeDetachedPowerW = orbSize
        detachedH = orbSize
    end
    local detachedPowerManagedByClassPreview = detachedPower and isPlayer and box._runtimeDetachedPowerAnchorClass == true
    local detachedPowerInUnitPreview = detachedPower and not detachedPowerManagedByClassPreview
    local wideW = w
    if classPowerOn and PreviewLayerWanted(box, "classPower") then wideW = max(wideW, box._runtimeClassPowerW or w) end
    if detachedPowerInUnitPreview and PreviewLayerWanted(box, "power") then wideW = max(wideW, box._runtimeDetachedPowerW) end
    st.cpSpec, st.cpClass = cpSpec, classPowerPreviewSpec and MenuState.GetClassPowerPreviewClassToken() or cpSpec.class
    st.animState, st.bars, st.data, st.powerFrac = animState, bars, data, powerFrac
    st.classPowerOn, st.classPowerPreviewSpec, st.classPowerSegCount, st.cpH = classPowerOn, classPowerPreviewSpec, classPowerSegCount, cpH
    st.detachedPower, st.detachedH, st.wideW = detachedPower, detachedH, wideW
    st.detachedPowerInUnitPreview, st.detachedPowerManagedByClassPreview = detachedPowerInUnitPreview, detachedPowerManagedByClassPreview
end

-- The scene has already laid out its regions. Measure the real glyphs and anchors for fit, including name-relative
-- status texts, rather than formatting a second set of mock strings.
local function RegionRect(region, frame)
    if region == frame then return 0, 0, frame:GetWidth(), frame:GetHeight() end
    local point, relative, relPoint, x, y = region:GetPoint(1)
    if not point or not relative or relative == region then return 0, 0, 0, 0 end
    local left, bottom, rw, rh = RegionRect(relative, frame)
    local px, py = PointCoord(relPoint or point, rw, rh)
    local width, height = region:GetWidth(), region:GetHeight()
    if region.GetStringWidth then width, height = region:GetStringWidth(), region:GetStringHeight() end
    local ox, oy = PointCoord(point, width, height)
    return left + px - ox + (x or 0), bottom + py - oy + (y or 0), width, height
end
-- Scene tables of host frames (aura hosts, texture layers) that expand the fit rectangle as well.
local FOOTPRINT_HOST_FIELDS = { "_msufGFFrameAuraPreviewHosts", "_msufTexLayers" }
--- Footprint pass one: name, health/power text slots, status indicators and
--- the boss target marker expand the fit rectangle. Each shown region grows it
--- by its measured rect; the test is inline because every refresh runs it.
function Stage.MeasureTextFootprint(st)
    local body = st.box.mock._body
    local minX, maxX, minY, maxY = 0, st.w, 0, st.h
    for _, field in pairs(BODY_ALIASES) do
        local region = body[field]
        if region and region.IsShown and region:IsShown() then
            local x, y, w, h = RegionRect(region, body)
            minX, maxX, minY, maxY = ExpandRect(minX, maxX, minY, maxY, x, y, x + w, y + h)
        end
    end
    for _, field in pairs(STATUS_REGIONS) do
        local region = body[field]
        if region and region.IsShown and region:IsShown() then
            local x, y, w, h = RegionRect(region, body)
            minX, maxX, minY, maxY = ExpandRect(minX, maxX, minY, maxY, x, y, x + w, y + h)
        end
    end
    for i = 1, #FOOTPRINT_HOST_FIELDS do
        for _, host in pairs(body[FOOTPRINT_HOST_FIELDS[i]] or EMPTY) do
            if host and host.IsShown and host:IsShown() then
                local x, y, w, h = RegionRect(host, body)
                minX, maxX, minY, maxY = ExpandRect(minX, maxX, minY, maxY, x, y, x + w, y + h)
            end
        end
    end
    local marker = body._msufBossTargetIndicator
    if marker and marker.IsShown and marker:IsShown() then
        local x, y, w, h = RegionRect(marker, body)
        minX, maxX, minY, maxY = ExpandRect(minX, maxX, minY, maxY, x, y, x + w, y + h)
    end
    st.minX, st.maxX, st.minY, st.maxY = minX, maxX, minY, maxY
end

-- Class resource container origin and width in unit body coordinates (the live ClassPower layout rule).
local function ClassPowerContainerRect(st)
    local bars = st.bars
    local cpW = st.box._runtimeClassPowerW or PreviewClassPowerWidth(bars, st.w, st.cpH, st.classPowerSegCount)
    return CPPreview.ContainerInsetX(bars) + (tonumber(bars.classPowerOffsetX) or 0),
        st.h - 2 - st.cpH + (tonumber(bars.classPowerOffsetY) or 0), cpW
end
local function PowerBarFootprintHeight(st)
    local runtimePower = st.runtimePower
    return tonumber(runtimePower and runtimePower.height) or st.ReadPowerBarHeight(st.conf)
end
-- |castbar setting| read the way the live castbar reads it; an unset value reads as the default.
local function CastNumAbs(st, field, bossField, default)
    return st.abs(st.R.ReadCastbarNum(st.g, st.key, field, bossField, default) or default)
end
-- The castbar slot, its icon, texts and target name expand the fit rectangle.
local function CastbarFootprint(st, minX, maxX, minY, maxY)
    local box, key, w, h = st.box, st.key, st.w, st.h
    local castW, castBarH, castOffsetX, castOffsetY = st.castW, st.castBarH, st.castOffsetX, st.castOffsetY
    local cLeft, cBottom
    if st.castDetached then
        cLeft = (w - castW) * 0.5 + castOffsetX
        cBottom = (h - castBarH) * 0.5 + castOffsetY
    elseif key == "player" then
        cLeft = (w - castW) * 0.5 + castOffsetX
        cBottom = h + castOffsetY
    elseif key == "boss" or key == "arena" then
        cLeft = castOffsetX - box._bossBorderInset
        cBottom = castOffsetY - box._bossBorderInset - box._bossCastbarGap - castBarH
            + (box._runtimePowerEmbedded == true and PowerBarFootprintHeight(st) or 0)
    else
        cLeft = castOffsetX
        cBottom = h + castOffsetY
    end
    local showTargetName = CastbarShowTargetName(key, st.g)
    local targetPadX = showTargetName and (CastNumAbs(st, "TargetNameOffsetX", "bossCastTargetNameOffsetX", 0) + 96) or 0
    local targetPadY = showTargetName and (CastNumAbs(st, "TargetNameOffsetY", "bossCastTargetNameOffsetY", 1) + 24) or 0
    local iconSize = CastNumAbs(st, "IconSize", "bossCastIconSize", castBarH)
    local detailPadX = st.max(
        CastNumAbs(st, "IconOffsetX", "bossCastIconOffsetX", 0) + iconSize,
        CastNumAbs(st, "TextOffsetX", "bossCastTextOffsetX", 0) + 80,
        CastNumAbs(st, "TimeOffsetX", "bossCastTimeOffsetX", 0) + 46,
        targetPadX
    )
    local detailPadY = st.max(
        CastNumAbs(st, "IconOffsetY", "bossCastIconOffsetY", 0) + iconSize,
        CastNumAbs(st, "TextOffsetY", "bossCastTextOffsetY", 0) + 24,
        CastNumAbs(st, "TimeOffsetY", "bossCastTimeOffsetY", 0) + 24,
        targetPadY
    )
    return st.min(minX, cLeft - detailPadX), st.max(maxX, cLeft + castW + detailPadX),
        st.min(minY, cBottom - detailPadY), st.max(maxY, cBottom + castBarH + detailPadY)
end

--- Footprint pass two: the class resource, power bars, castbar, arena trinket, aura lanes and dispel pieces expand
--- the fit rectangle; any of them being visible also widens the fit margin.
function Stage.MeasureLayerFootprint(st)
    local box, key, w, h, min, max = st.box, st.key, st.w, st.h, st.min, st.max
    local minX, maxX, minY, maxY, wideW = st.minX, st.maxX, st.minY, st.maxY, st.wideW
    local runtimeSpec, Auras = st.runtimeSpec, st.Auras
    local classPowerWanted = st.classPowerOn and PreviewLayerWanted(box, "classPower")
    local detachedWanted = st.detachedPowerInUnitPreview and PreviewLayerWanted(box, "power")
    if classPowerWanted then
        local cx, cy, cpW = ClassPowerContainerRect(st)
        minX, maxX = min(minX, cx), max(maxX, cx + cpW)
        minY, maxY = min(minY, cy), max(maxY, cy + st.cpH)
    end
    if detachedWanted then
        local dW, dx, dy, detachedH = box._runtimeDetachedPowerW, box._runtimeDetachedPowerX, box._runtimeDetachedPowerY, st.detachedH
        local dLeft = box._runtimeDetachedPowerAnchorMode == "LEGACY_TOPLEFT" and dx or ((w - dW) * 0.5 + dx)
        local dBottom = -detachedH + dy
        if box._runtimeDetachedPowerAnchorClass and st.classPowerOn then
            local cx, cy, cpW = ClassPowerContainerRect(st)
            dLeft = cx + (cpW - dW) * 0.5 + dx
            dBottom = cy - detachedH + dy
        end
        minX, maxX = min(minX, dLeft), max(maxX, dLeft + dW)
        minY, maxY = min(minY, dBottom), max(maxY, dBottom + detachedH)
    end
    if box._runtimePowerAttached == true and PreviewLayerWanted(box, "power") then
        minY = min(minY, -(PowerBarFootprintHeight(st) + 1))
    end
    if st.castPreviewVisible then
        wideW = max(wideW, st.castW)
        minX, maxX, minY, maxY = CastbarFootprint(st, minX, maxX, minY, maxY)
    end
    local arenaTrinket = MenuState.ArenaTrinketPreview
    if key == "arena" and arenaTrinket and PreviewLayerWanted(box, "trinket") then
        minX, maxX, minY, maxY = arenaTrinket.Footprint(minX, maxX, minY, maxY, w, h, ExpandAnchoredRect)
    end
    local auraPreviewState = box.mock._body._msufSceneAuraLanes
    local auraFootprintState = false
    for kind, lane in pairs(auraPreviewState or EMPTY) do
        local layer = (kind == "buff" or kind == "debuff") and kind or "auras"
        if lane.enabled and lane.max > 0 and PreviewLayerWanted(box, layer) then auraFootprintState = true end
    end
    local dispelPreview = Auras and Auras.DispelPreview
    if dispelPreview and dispelPreview.Availability then
        box._previewDispelOverlayAvailable, box._previewDispelSymbolAvailable = dispelPreview.Availability(key, runtimeSpec)
    else
        box._previewDispelOverlayAvailable, box._previewDispelSymbolAvailable = false, false
    end
    local dispelSymbolWanted = box._previewDispelSymbolAvailable and PreviewLayerWanted(box, "dispelSymbol")
    if Auras and Auras.ExpandDispelFootprint then
        minX, maxX, minY, maxY = Auras.ExpandDispelFootprint(runtimeSpec, w, h, minX, maxX, minY, maxY, dispelSymbolWanted)
    end
    if classPowerWanted or detachedWanted or st.castPreviewVisible or auraFootprintState or box._statusFootprintVisible
        or dispelSymbolWanted then
        minX, maxX = minX - 18, maxX + 18
        minY, maxY = minY - 18, maxY + 18
    end
    st.auraPreviewState, st.maxX, st.maxY, st.minX, st.minY, st.wideW = auraPreviewState, maxX, maxY, minX, minY, wideW
end

--- Fit/manual zoom, the S() scaler, frame levels, bar textures and the mock
--- body placement on the canvas.
function Stage.ResolveScaleAndLevels(st)
    local RenderState, box, canvas, bars, g, key, w, h = st.R, st.box, st.canvas, st.bars, st.g, st.key, st.w, st.h
    local floor, max, min, runtimePower = st.floor, st.max, st.min, st.runtimePower
    local maxX, maxY, minX, minY = st.maxX, st.maxY, st.minX, st.minY
    local centerX = ((minX + maxX) * 0.5) - (w * 0.5)
    local centerY = ((minY + maxY) * 0.5) - (h * 0.5)
    local runtimeScale = RenderState.RuntimeVisualScaleForPreviewKey(key, canvas)
    box._mockCastRuntimeScale = RenderState.RuntimeCastbarVisualScaleForPreviewKey(key, canvas)
    box._mockCastFrameScale = runtimeScale > 0 and (box._mockCastRuntimeScale / runtimeScale) or 1
    local autoScale = min(1.0, (st.cw - 60) / max(max(st.wideW, maxX - minX) * runtimeScale, 1), (st.ch - 42) / max(max(h, maxY - minY) * runtimeScale, 1))
    -- Fit mode must fit the complete configured footprint. Manual zoom keeps
    -- its usability floor, but forcing that same floor here clips status icons
    -- with large offsets instead of showing the true layout.
    if autoScale < 0.05 then autoScale = 0.05 end
    RenderState.ResolveDefaultPreviewZoomLock(box, autoScale)
    local manualZoom = tonumber(box._manualZoom)
    local frozenScale = tonumber(box._dragFrozenScale)
    local previewScale = manualZoom and RenderState.ClampPreviewZoom(manualZoom) or (frozenScale and RenderState.ClampPreviewZoom(frozenScale) or autoScale)
    local scale = runtimeScale * previewScale
    box._mockRuntimeScale = runtimeScale
    box._mockAutoScale = autoScale
    box._mockScale = previewScale
    box._mockEffectiveScale = scale
    RenderState.UpdatePreviewZoomControls(box)
    local function S(v) return floor((tonumber(v) or 0) * scale + 0.5) end
    -- Portrait size now comes from box._runtimePortraitW/H (independent axes), so
    -- the scaled square is no longer derived here.
    local sw, sh = S(w), S(h)
    local mockOffsetX, mockOffsetY = ResolvePreviewBodyOffsets(centerX, centerY, scale, manualZoom,
        tonumber(box._dragFrozenBaseOffsetX), tonumber(box._dragFrozenBaseOffsetY))
    local panX, panY = tonumber(box._zoomPanX) or 0, tonumber(box._zoomPanY) or 0
    box._mockBaseOffsetX, box._mockBaseOffsetY = mockOffsetX, mockOffsetY
    box._detachedCastPreview = nil
    box._detachedCastBaseOffsetX, box._detachedCastBaseOffsetY = nil, nil
    local mock = box.mock
    local baseLevel = (canvas.GetFrameLevel and canvas:GetFrameLevel() or 0) + 2
    if mock.SetFrameLevel then mock:SetFrameLevel(baseLevel + 4) end
    if canvas._msufPreviewElementLevelBias ~= baseLevel + 4 then
        canvas._msufPreviewElementLevelBias = baseLevel + 4
        for _, handle in pairs(box.handles) do
            local priority = tonumber(handle._fields and handle._fields.interactionPriority) or 0
            handle:SetFrameLevel(MSUF.UFPreviewCore.InteractionFrameLevel(canvas, priority))
            if handle._selBorder then handle._selBorder:SetFrameLevel(handle:GetFrameLevel() + 1) end
        end
    end
    local body = mock._body
    local geometryChanged = body:GetScale() ~= scale or box._sceneCanvasX ~= mockOffsetX + panX
        or box._sceneCanvasY ~= mockOffsetY + panY
    body:SetScale(scale)
    body:SetFrameLevel(baseLevel + 4)
    body:ClearAllPoints()
    body:SetPoint("CENTER", mock, "CENTER", 0, 0)
    mock:SetSize(sw, sh)
    mock:ClearAllPoints()
    mock:SetPoint("CENTER", canvas, "CENTER", mockOffsetX + panX, mockOffsetY + panY)
    if geometryChanged then
        box._sceneCanvasX, box._sceneCanvasY = mockOffsetX + panX, mockOffsetY + panY
        -- Boss/arena snapping and shaped masks consume the owner's final effective scale and position.
        box._unitScene:Refresh()
    end
    if mock.sizeTag then mock.sizeTag:SetText(st.format("%d x %d", w, h)) end
    if mock.bounds then mock.bounds:SetFrameLevel(Layers.ElementLevel(30, 30, 31) + 16) end
    local castLayer = RenderState.ReadCastbarNum(g, key, "FrameLevelOffset", "bossCastFrameLevelOffset", 6)
    mock.cast:SetFrameLevel(Layers.ElementLevel(castLayer, 6, 0) + baseLevel + 4)
    mock.classPower:SetFrameLevel(Layers.ElementLevel(bars.classPowerFrameLevelOffset, 5, 0) + baseLevel + 4)
    st.powerH = S(runtimePower and runtimePower.height or 0)
    st.powerEnabled = runtimePower and runtimePower.enabled == true
    st.S, st.baseLevel, st.centerX, st.centerY, st.mock = S, baseLevel, centerX, centerY, mock
    MSUF.UFPreviewCore.ApplyBoundsGuide(box, st.runtimeSpec.border and st.runtimeSpec.border.thickness or 1)
    st.scale, st.sw = scale, sw
end


end
