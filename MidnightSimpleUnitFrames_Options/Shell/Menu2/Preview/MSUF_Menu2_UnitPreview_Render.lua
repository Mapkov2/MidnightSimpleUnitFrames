--- Unit preview render/composition.
---
--- The view file builds frames and wires controls; this module owns the hot
--- refresh path that composes the live preview visuals.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local Render = MSUF.UFPreviewRender or {}
MSUF.UFPreviewRender = Render
local MenuState = MSUF.MSUF2 or _G.MSUF2 or {}
local Pick, PickFallbackTable = MenuState.Pick, MenuState.PickFallbackTable
local F = MenuState.Fallbacks or {}
local PreviewHelpers = MenuState.PreviewHelpers or {}
local CPPreview = MenuState.ClassPowerPreview or {}
local CastbarPreview = MSUF.UFPreviewCastbar or {}
local Layers = MSUF.UF and MSUF.UF.Layers or {}
-- Mirrors the live relief renderer. FULL overlays cache their resolved anchor
-- extents before this runs, avoiding stale configured portraitWidth/Height.
local PREVIEW_RING_OPENING_INFLATE = 0.0952380952
local PREVIEW_RING_REFERENCE_THICKNESS = 2
local function ScalePreviewOutline(value, scale)
    value = math.floor((tonumber(value) or 0) + 0.5)
    if value <= 0 then return 0 end
    scale = tonumber(scale) or 1
    if scale <= 0 then scale = 1 end
    return math.max(1, math.floor((value * scale) + 0.5))
end
Render.ScalePreviewOutline = ScalePreviewOutline
local function PreviewPortraitRingInflation(portrait, thickness)
    local pw = tonumber(portrait and portrait._msufPreviewLayoutWidth)
        or (portrait and portrait.GetWidth and tonumber(portrait:GetWidth())) or 36
    local ph = tonumber(portrait and portrait._msufPreviewLayoutHeight)
        or (portrait and portrait.GetHeight and tonumber(portrait:GetHeight())) or 36
    if pw <= 0 then pw = 36 end
    if ph <= 0 then ph = 36 end
    local scale = PREVIEW_RING_OPENING_INFLATE
        * ((tonumber(thickness) or PREVIEW_RING_REFERENCE_THICKNESS) / PREVIEW_RING_REFERENCE_THICKNESS)
    return math.floor(math.max(1, pw * scale) + 0.5),
        math.floor(math.max(1, ph * scale) + 0.5)
end
Render.PreviewPortraitRingInflation = PreviewPortraitRingInflation

local function CachePreviewFullPortraitExtents(portrait, anchor, fallbackWidth, fallbackHeight, x, y, healthBottom)
    local width = anchor and anchor.GetWidth and tonumber(anchor:GetWidth()) or 0
    local height = anchor and anchor.GetHeight and tonumber(anchor:GetHeight()) or 0
    if width <= 0 then width = tonumber(fallbackWidth) or 1 end
    if height <= 0 then height = tonumber(fallbackHeight) or 1 end
    healthBottom = tonumber(healthBottom) or 0
    if healthBottom > 0 then height = math.max(0, height - healthBottom) end
    width = math.max(1, width - (2 * x))
    height = math.max(1, height - (2 * y))
    if portrait._msufPreviewLayoutWidth ~= width then portrait._msufPreviewLayoutWidth = width end
    if portrait._msufPreviewLayoutHeight ~= height then portrait._msufPreviewLayoutHeight = height end
end
Render.CachePreviewFullPortraitExtents = CachePreviewFullPortraitExtents

local function ResolvePreviewBodyOffsets(centerX, centerY, scale, manualZoom, frozenX, frozenY)
    if frozenX ~= nil and frozenY ~= nil then return frozenX, frozenY end
    -- Fit mode centers the complete configured footprint. At a manual zoom,
    -- keep the unit body as the stable focal point instead: valid auxiliary
    -- layouts can sit hundreds of pixels away and must not exile the body from
    -- the canvas. Explicit canvas pan is applied separately below.
    if manualZoom ~= nil then return 0, 0 end
    scale = tonumber(scale) or 1
    return -math.floor(((tonumber(centerX) or 0) * scale) + 0.5),
        -math.floor(((tonumber(centerY) or 0) * scale) + 0.5)
end
Render.ResolvePreviewBodyOffsets = ResolvePreviewBodyOffsets

--- Keep unit text in the same coordinate system as the live frame. Runtime
--- applies the configured font size first and scales the owning unit frame;
--- multiplying the font size in Preview is not equivalent because WoW rounds
--- and hints fonts at the requested size. It also made the 7px readability
--- floor change TOP/BOTTOM anchored text centers at small runtime/Fit scales.
local function ConfigureRuntimeScaledTextFrame(frame, reference, width, height, renderScale)
    if not (frame and reference and frame.ClearAllPoints and frame.SetPoint
        and frame.SetSize and frame.SetScale)
    then
        return false
    end
    width, height = tonumber(width) or 1, tonumber(height) or 1
    renderScale = tonumber(renderScale) or 1
    if width <= 0 then width = 1 end
    if height <= 0 then height = 1 end
    if renderScale <= 0 then renderScale = 1 end
    frame:ClearAllPoints()
    frame:SetSize(width, height)
    frame:SetScale(renderScale)
    frame:SetPoint("CENTER", reference, "CENTER", 0, 0)
    return true
end
Render.ConfigureRuntimeScaledTextFrame = ConfigureRuntimeScaledTextFrame

local function RuntimeTextCoordinate(value)
    return tonumber(value) or 0
end

local function ApplyRuntimePreviewFont(runtimeSpec, fallback, fs, size, role)
    local setFont = MSUF.UFText and MSUF.UFText.SetFont
    if runtimeSpec and type(setFont) == "function" then
        setFont(fs, runtimeSpec, size, role)
    elseif type(fallback) == "function" then
        fallback(fs, size)
    end
end

local function NameRelativeFontRole(anchor)
    return (anchor == "NAMERIGHT" or anchor == "NAMELEFT") and "name" or nil
end

local function PlaceRuntimePreviewName(fs, parent, runtimeText, conf, baselineOffset, resolveNameAnchor)
    local anchor = (runtimeText and runtimeText.nameAnchor) or conf.nameTextAnchor or "TOPLEFT"
    local x = tonumber(runtimeText and runtimeText.nameX)
    local y = tonumber(runtimeText and runtimeText.nameY)
    if x == nil then x = tonumber(conf.nameOffsetX) or 4 end
    if y == nil then y = (tonumber(conf.nameOffsetY) or -4) + (tonumber(baselineOffset) or 0) end
    local point, relativePoint, offsetX, justify = resolveNameAnchor(anchor, x)
    fs:SetPoint(point, parent, relativePoint, offsetX, y)
    fs:SetJustifyH(justify)
end

local function CastbarPreviewDetailPrefix(unitKey)
    if unitKey == "player" then return "castbarPlayer" end
    if unitKey == "target" then return "castbarTarget" end
    if unitKey == "focus" then return "castbarFocus" end
    if unitKey == "boss" then return "bossCast" end
    return nil
end
local function NormalizeCastbarPreviewIconPos(value)
    value = tostring(value or "LEFT"):upper():gsub("%s+", "_"):gsub("-", "_")
    if value == "INSIDELEFT" then value = "INSIDE_LEFT" end
    if value == "INSIDERIGHT" then value = "INSIDE_RIGHT" end
    if value == "RIGHT" or value == "INSIDE_LEFT" or value == "INSIDE_RIGHT" then return value end
    return "LEFT"
end
local function ApplyCastbarPreviewIconZoom(icon, zoom)
    local texture = icon and (icon.texture or icon.Texture or icon.Icon)
    if not (texture and texture.SetTexCoord) then return end
    zoom = tonumber(zoom) or 100
    if zoom < 100 then zoom = 100 elseif zoom > 200 then zoom = 200 end
    local visible = 100 / zoom
    local inset = (1 - visible) * 0.5
    texture:SetTexCoord(inset, 1 - inset, inset, 1 - inset)
end
-- UnitPreview_Castbar loads immediately before this file and owns the text
-- contract shared with the page-local castbar preview.
local NormalizeCastbarPreviewTextPos = CastbarPreview.NormalizeTextPosition
local CastbarPreviewJustifyForPosition = CastbarPreview.JustifyForTextPosition
local NormalizeCastbarPreviewJustify = CastbarPreview.NormalizeTextJustify
local PREVIEW_CLASS_POWER_SHAPES = CPPreview.CLASS_SHAPES
local PREVIEW_POWER_SHAPES = CPPreview.POWER_SHAPES
local UNIT_CP_ROUNDED_OPTS = {
    bgKey = "_msufUnitCPRoundedBg",
    edgeKey = "_msufUnitCPRoundedEdge",
    stackKey = "_msufUnitCPRoundedEdgeStack",
    countKey = "_msufUnitCPRoundedEdgeCount",
    maskStoreKey = "_msufUnitCPRoundedMasks",
    maskedKey = "_msufUnitCPRoundedMasked",
    whiteTexture = "Interface\\Buttons\\WHITE8X8",
    edgeLayer = "OVERLAY",
    edgeSubLevel = 6,
    maxEdgeSize = 8,
    snapOff = PreviewHelpers.SnapOff,
    baseEdgeColor = function() return 0, 0, 0, 1 end,
}
local NormalizePreviewClassPowerShape = CPPreview.NormalizeClassShape
local function NormalizePreviewClassPowerShapeAlign(value)
    value = tostring(value or "CENTER"):upper()
    if value == "LEFT" or value == "RIGHT" then return value end
    return "CENTER"
end
local function PreviewClassPowerSegmentCount(spec, limit)
    local count = math.floor(tonumber(spec and spec.segments) or 5)
    if count < 1 then count = 1 end
    limit = tonumber(limit) or 10
    if count > limit then count = limit end
    return count
end
local function PreviewClassPowerAutoFitWidth(segCount, height, gap)
    segCount = math.floor(tonumber(segCount) or 1)
    if segCount < 1 then segCount = 1 elseif segCount > 10 then segCount = 10 end
    height = math.floor(tonumber(height) or 1)
    if height < 1 then height = 1 end
    gap = math.floor(tonumber(gap) or 0)
    if gap < 0 then gap = 0 elseif gap > 8 then gap = 8 end
    return (segCount * height) + ((segCount - 1) * gap)
end
local function PreviewClassPowerWidth(bars, frameW, cpH, segCount)
    bars = bars or {}
    local shape = NormalizePreviewClassPowerShape(bars.classPowerShape)
    if PREVIEW_CLASS_POWER_SHAPES[shape] and bars.classPowerWidthMode == "auto_pips" then
        local w = PreviewClassPowerAutoFitWidth(segCount, cpH, bars.classPowerGap)
        if w < 1 then w = 1 elseif w > 800 then w = 800 end
        return w
    end
    local w = (bars.classPowerWidthMode == "custom") and (tonumber(bars.classPowerWidth) or (frameW - 4)) or (frameW - 4)
    if w < 30 then w = frameW - 4 elseif w > 800 then w = 800 end
    return w
end
local function PreviewClassTextLevel(owner, bars)
    local layer = math.floor((tonumber(bars and bars.classPowerTextLayer) or 5) + 0.5)
    if layer < 0 then layer = 0 elseif layer > 30 then layer = 30 end
    if Layers.TextLevel then return Layers.TextLevel(owner, layer, 5) end
    if Layers.ElementLevel then return Layers.ElementLevel(layer, 5, 8) end
    return 100 + layer * 32 + 8
end
local function PreviewSecondaryClassTimerHeight(runtimePower, conf)
    local height = tonumber(runtimePower and runtimePower.height)
        or tonumber(conf and conf.powerBarHeight) or 3
    if height < 1 then height = 1 elseif height > 30 then height = 30 end
    return height
end
local function EnsurePreviewSecondaryClassTimer(mock, whiteTexture)
    local classPower = mock and mock.classPower
    if not classPower then return nil end
    local frame = classPower._msufSecondaryTimer
    if frame then return frame end
    frame = CreateFrame("Frame", nil, classPower)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints(frame)
    frame.bg:SetTexture(whiteTexture)
    frame.fill = frame:CreateTexture(nil, "ARTWORK")
    frame.fill:SetTexture(whiteTexture)
    frame.textOwner = CreateFrame("Frame", nil, frame)
    frame.textOwner:SetAllPoints(frame)
    if frame.textOwner.EnableMouse then frame.textOwner:EnableMouse(false) end
    frame.text = frame.textOwner:CreateFontString(nil, "OVERLAY")
    frame.text:SetJustifyH("CENTER")
    if frame.text.SetJustifyV then frame.text:SetJustifyV("MIDDLE") end
    frame:Hide()
    classPower._msufSecondaryTimer = frame
    return frame
end
local function HidePreviewSecondaryClassTimer(mock)
    local frame = mock and mock.classPower and mock.classPower._msufSecondaryTimer
    if not frame then return end
    frame:Hide()
    frame.fill:Hide()
    frame.text:Hide()
end
local function RenderPreviewSecondaryClassTimer(mock, spec, rawHeight, cpW, bars, renderState,
    animState, scaleFn, whiteTexture, applyFont, setTexture, fr, fg, fb, cp)
    local timer = EnsurePreviewSecondaryClassTimer(mock, whiteTexture)
    local timerH = math.max(1, scaleFn(rawHeight))
    local timerW = math.max(1, scaleFn(cpW))
    timer:SetSize(timerW, timerH)
    timer:ClearAllPoints()
    timer:SetPoint("TOPLEFT", mock.classPower, "BOTTOMLEFT", 0, -math.max(1, scaleFn(2)))
    if timer.SetFrameLevel and mock.classPower.GetFrameLevel then
        timer:SetFrameLevel((mock.classPower:GetFrameLevel() or 0) + 1)
    end
    if timer.textOwner and timer.textOwner.SetFrameLevel then
        timer.textOwner:SetFrameLevel(PreviewClassTextLevel(timer.textOwner, bars))
    end

    local animatedValue = animState and renderState.CPPreview.AnimatedValue
        and renderState.CPPreview.AnimatedValue(spec, animState.elapsed) or nil
    local fraction = tonumber(animatedValue)
    if fraction == nil then fraction = tonumber(spec.value) or 0.6 end
    if fraction < 0 then fraction = 0 elseif fraction > 1 then fraction = 1 end

    local r, g, b = renderState.CPPreview.ResolveBaseColor(spec, bars, 0.40, 0.80, 0.60)
    local bgR, bgG, bgB = renderState.CPPreview.ColorOverride(
        "classPowerBgColorOverrides", spec.token)
    local texture = CPPreview.ResolveTexture
        and CPPreview.ResolveTexture(bars.classPowerTexture, whiteTexture) or whiteTexture
    local bgTexture = CPPreview.ResolveTexture
        and CPPreview.ResolveTexture(bars.classPowerBgTexture, texture) or texture
    setTexture(timer.bg, bgTexture)
    timer.bg:SetVertexColor(bgR or 0, bgG or 0, bgB or 0, cp.bgAlpha)
    setTexture(timer.fill, texture)
    timer.fill:SetTexCoord(0, 1, 0, 1)
    timer.fill:SetVertexColor(r, g, b, cp.filledAlpha)
    timer.fill:ClearAllPoints()
    timer.fill:SetPoint("TOPLEFT", timer, "TOPLEFT", 0, 0)
    timer.fill:SetPoint("BOTTOMLEFT", timer, "BOTTOMLEFT", 0, 0)
    timer.fill:SetWidth(math.max(1, math.floor(timerW * fraction + 0.5)))
    if fraction > 0 then timer.fill:Show() else timer.fill:Hide() end

    if spec.nativeDurationText == true or bars.classPowerShowText == true then
        local textSize = scaleFn(tonumber(bars.classPowerFontSize) or 16)
        if textSize < 7 then textSize = 7 end
        applyFont(timer.text, textSize)
        if animatedValue ~= nil and renderState.CPPreview.TextForValue then
            timer.text:SetText(renderState.CPPreview.TextForValue(spec, animatedValue))
        else
            timer.text:SetText(spec.previewText or "12.0")
        end
        local textR, textG, textB = renderState.CPPreview.ResolveTextColor(fr or 1, fg or 1, fb or 1)
        timer.text:SetTextColor(textR, textG, textB, cp.runeTextAlpha)
        timer.text:ClearAllPoints()
        timer.text:SetPoint("CENTER", timer, "CENTER",
            scaleFn(tonumber(bars.classPowerTextOffsetX) or 0),
            scaleFn(tonumber(bars.classPowerTextOffsetY) or 0))
        timer.text:Show()
    else
        timer.text:Hide()
    end
    timer:Show()
    return timer
end
local ResolvePreviewPowerShape = CPPreview.ResolvePowerShape
local function PreviewShapeOutlineAlpha(value)
    value = tonumber(value) or 0
    if value <= 0 then return 0 end
    if value >= 8 then return 1 end
    return 0.49 + (value * 0.065)
end
local function NormalizeCastbarPreviewTruncate(value)
    value = tostring(value or "AUTO"):upper()
    if value == "CLIP" or value == "NONE" then return value end
    return "AUTO"
end
local function CopyPreviewAnimationData(box, data, hpFrac, powerFrac)
    local copy = box and box._previewAnimationData
    if not copy then
        copy = {}
        if box then box._previewAnimationData = copy end
    else
        for k in pairs(copy) do copy[k] = nil end
    end
    for k, v in pairs(data or {}) do copy[k] = v end
    copy.hp = hpFrac
    copy.power = powerFrac
    -- Live snapshots carry exact current values; while the combat animation
    -- drives the fractions, value texts must follow the animated fraction on
    -- the live max scale instead of freezing on the sampled current value.
    copy.hpCur = nil
    copy.powerCur = nil
    return copy
end
local function ResolvePreviewPowerColor(renderState, data, power)
    local mode = power and power.mode
    if mode == "dark" or mode == "unified" or mode == "static" then
        return power.r or 0.1, power.g or 0.35, power.b or 0.95
    elseif mode == "class" then
        return renderState.ClassColor(data.class)
    end
    return renderState.PowerColor(data.powerToken)
end

local function ResolvePreviewHealthTextColor(renderState, runtimeText, conf, general, data, fr, fg, fb)
    local mode = general.colorHealthTextByHealth
    if conf.fontOverride == true and conf.colorHealthTextByHealth ~= nil then mode = conf.colorHealthTextByHealth end
    local byHealth = runtimeText and runtimeText.healthColorByHealth == true
        or (not runtimeText and (mode == true or mode == "HEALTH"))
    local byClass = runtimeText and runtimeText.healthColorByClass == true
        or (not runtimeText and mode == "CLASS")
    if byClass then return renderState.ClassColor(data.class) end
    if not byHealth then return fr, fg, fb end
    local pct = tonumber(data.hp) or 1
    if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
    if pct <= 0.5 then return 1, pct * 2, 0 end
    return (1 - pct) * 2, 1, 0
end
local function PreviewLiveFrame(key)
    local uf = MSUF and MSUF.UF
    local unit = key == "boss" and "boss1" or key
    local frame = uf and type(uf.GetFrame) == "function" and uf.GetFrame(unit) or nil
    if not frame then frame = uf and uf.frames and uf.frames[unit] or nil end
    return frame
end
local function PreviewLiveStatusText(key)
    local frame = PreviewLiveFrame(key)
    local value = frame and frame._msufStatusTextValue
    if value == "DEAD" or value == "GHOST" or value == "OFFLINE" or value == "AFK" or value == "DND" then
        return value
    end
    return nil
end
local function PreviewLivePowerBar(key)
    local frame = PreviewLiveFrame(key)
    return frame and (frame.targetPowerBar or frame.powerBar or frame.Power) or nil
end
local function UnitPreviewAnimationState(box, index, key)
    if not (box and box._animationEnabled == true) then return nil end
    local previewAnimation = MSUF and MSUF.PreviewAnimation
    local buildState = previewAnimation and previewAnimation.BuildFrameState or _G.MSUF_BuildPreviewAnimationFrameState
    if type(buildState) ~= "function" then return nil end
    local scratch = box._previewAnimationState
    if not scratch then
        scratch = {}
        box._previewAnimationState = scratch
    end
    return buildState(box, index, key, scratch, box._animationElapsed)
end
local function ShortenCastbarPreviewSpellName(key, text)
    local shorten = _G.MSUF_ShortenCastbarSpellName
    if type(shorten) ~= "function" then return text end
    return shorten({ unit = key == "boss" and "boss1" or key }, text)
end
local function HideCastbarPreviewIconBorder(icon)
    local border = icon and icon._msufCastbarPreviewBorder
    if border then
        for _, key in ipairs({ "top", "bottom", "left", "right" }) do
            if border[key] then border[key]:Hide() end
        end
    end
    if icon and icon.SetBackdrop then icon:SetBackdrop(nil) end
    if icon then
        icon._msufCastbarPreviewBorderEdge = nil
        icon._msufCastbarPreviewBorderR = nil
        icon._msufCastbarPreviewBorderG = nil
        icon._msufCastbarPreviewBorderB = nil
        icon._msufCastbarPreviewBorderA = nil
    end
end
local function ApplyCastbarPreviewIconBorder(icon, style, thickness, g)
    if not (icon and icon.SetBackdropBorderColor) then return end
    style = tostring(style or "NONE"):upper()
    thickness = tonumber(thickness) or 0
    if thickness < 0 then thickness = 0 elseif thickness > 8 then thickness = 8 end
    local texture = icon.texture or icon.Texture or icon.Icon
    if texture and texture.ClearAllPoints and texture.SetAllPoints then
        texture:ClearAllPoints()
        texture:SetAllPoints(icon)
    end
    if style == "NONE" or thickness <= 0 then
        HideCastbarPreviewIconBorder(icon)
        return
    end
    local legacy = icon._msufCastbarPreviewBorder
    if legacy then
        for _, key in ipairs({ "top", "bottom", "left", "right" }) do
            if legacy[key] then legacy[key]:Hide() end
        end
    end
    local r, green, b, a = 0, 0, 0, 0.95
    if style == "DARK" then
        r, green, b, a = 0, 0, 0, 0.95
    elseif style == "CASTBAR" then
        r, green, b, a = g.castbarBorderR or 0, g.castbarBorderG or 0, g.castbarBorderB or 0, g.castbarBorderA or 1
    end
    if icon._msufCastbarPreviewBorderEdge ~= thickness then
        icon:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = thickness,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        if icon.SetBackdropColor then icon:SetBackdropColor(0, 0, 0, 0) end
        icon._msufCastbarPreviewBorderEdge = thickness
    end
    if icon._msufCastbarPreviewBorderR ~= r or icon._msufCastbarPreviewBorderG ~= green
        or icon._msufCastbarPreviewBorderB ~= b or icon._msufCastbarPreviewBorderA ~= a
    then
        icon:SetBackdropBorderColor(r, green, b, a)
        icon._msufCastbarPreviewBorderR = r
        icon._msufCastbarPreviewBorderG = green
        icon._msufCastbarPreviewBorderB = b
        icon._msufCastbarPreviewBorderA = a
    end
end
local AnchorCastbarPreviewText = CastbarPreview.AnchorText
local function ResolvePreviewTextSlotSize(runtimeText, conf, runtimeKey, dbKey, fallback)
    local value = tonumber(runtimeText and runtimeText[runtimeKey]) or tonumber(conf and conf[dbKey])
    return value and value > 0 and value or fallback
end
local function RuntimeHealthPhysicalSlotValue(runtimeText, physicalSide, prefix, suffix)
    if not runtimeText then return nil end
    local side = physicalSide
    if runtimeText.healthReverse == true then
        side = physicalSide == "Left" and "Right" or physicalSide == "Right" and "Left" or physicalSide
    end
    return runtimeText[(prefix or "health") .. side .. (suffix or "")]
end
local PREVIEW_DIRECT_TEXT_POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
local function PreviewDirectTextPoint(value, fallback)
    value = type(value) == "string" and value:upper() or nil
    if value == "NAMELEFT" then return "LEFT" end
    if value == "NAMERIGHT" then return "RIGHT" end
    if value and PREVIEW_DIRECT_TEXT_POINTS[value] then return value end
    return fallback or "CENTER"
end
local function PlaceDirectPreviewText(fs, parent, text, prefix, fallbackPoint, fallbackRelPoint, fallbackX, fallbackY, fallbackJustify, S)
    if not fs then return end
    local point = PreviewDirectTextPoint(text and text[prefix .. "Point"], fallbackPoint)
    local relPoint = PreviewDirectTextPoint(text and text[prefix .. "RelativePoint"], fallbackRelPoint or point)
    local x = tonumber(text and text[prefix .. "X"])
    local y = tonumber(text and text[prefix .. "Y"])
    if x == nil then x = fallbackX or 0 end
    if y == nil then y = fallbackY or 0 end
    local justify = fallbackJustify or "CENTER"
    if point:find("LEFT", 1, true) then
        justify = "LEFT"
    elseif point:find("RIGHT", 1, true) then
        justify = "RIGHT"
    end
    fs:ClearAllPoints()
    fs:SetPoint(point, parent, relPoint, S(x), S(y))
    fs:SetJustifyH(justify)
end
Render.PlaceDirectPreviewText = PlaceDirectPreviewText
local function SetTextColorSet(r, g, b, a, ...)
    for i = 1, select("#", ...) do select(i, ...):SetTextColor(r, g, b, a) end
end
local function SetPreviewTextColor(fs, color, fallbackAlpha)
    if not (fs and type(color) == "table") then return false end
    local r = tonumber(color.r or color[1])
    local g = tonumber(color.g or color[2])
    local b = tonumber(color.b or color[3])
    if r == nil or g == nil or b == nil then return false end
    local a = tonumber(color.a or color[4]) or tonumber(fallbackAlpha) or 1
    fs:SetTextColor(r, g, b, a)
    return true
end
local function SetLeftSpan(region, parent, x, y) region:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y or 0); region:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x or 0, y or 0) end
local function SetRightSpan(region, parent, x, y) region:SetPoint("TOPRIGHT", parent, "TOPRIGHT", x or 0, y or 0); region:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", x or 0, y or 0) end
local function SetBottomSpan(region, parent, leftX, rightX, y) region:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", leftX or 0, y or 0); region:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", rightX or 0, y or 0) end
local function PointCoord(point, w, h)
    point = tostring(point or "CENTER"):upper()
    local x = (point:find("RIGHT", 1, true) and w) or (point:find("LEFT", 1, true) and 0) or (w * 0.5)
    local y = (point:find("TOP", 1, true) and h) or (point:find("BOTTOM", 1, true) and 0) or (h * 0.5)
    return x, y
end
local function ExpandRect(minX, maxX, minY, maxY, left, bottom, right, top)
    if not (left and bottom and right and top) then return minX, maxX, minY, maxY end
    return math.min(minX, left), math.max(maxX, right), math.min(minY, bottom), math.max(maxY, top)
end
local function ExpandAnchoredRect(minX, maxX, minY, maxY, point, relPoint, x, y, rw, rh, targetW, targetH)
    rw, rh = tonumber(rw) or 1, tonumber(rh) or 1
    local tx, ty = PointCoord(relPoint or point, tonumber(targetW) or 0, tonumber(targetH) or 0)
    local px, py = PointCoord(point, rw, rh)
    local left = tx + (tonumber(x) or 0) - px
    local bottom = ty + (tonumber(y) or 0) - py
    return ExpandRect(minX, maxX, minY, maxY, left, bottom, left + rw, bottom + rh)
end
local function ExpandDirectPreviewTextRect(minX, maxX, minY, maxY, text, prefix, fallbackPoint, fallbackRelPoint, fallbackX, fallbackY, rw, rh, targetW, targetH)
    local point = PreviewDirectTextPoint(text and text[prefix .. "Point"], fallbackPoint)
    local relPoint = PreviewDirectTextPoint(text and text[prefix .. "RelativePoint"], fallbackRelPoint or point)
    local x = tonumber(text and text[prefix .. "X"])
    local y = tonumber(text and text[prefix .. "Y"])
    if x == nil then x = fallbackX or 0 end
    if y == nil then y = fallbackY or 0 end
    return ExpandAnchoredRect(minX, maxX, minY, maxY, point, relPoint, x, y, rw, rh, targetW, targetH)
end
local function ExpandRuntimeAnchorRect(minX, maxX, minY, maxY, anchor, x, y, rw, rh, targetW, targetH)
    anchor = tostring(anchor or "CENTER"):upper()
    local point, relPoint = anchor, anchor
    if anchor == "NAMERIGHT" then
        point, relPoint = "LEFT", "RIGHT"
    elseif anchor == "NAMELEFT" then
        point, relPoint = "RIGHT", "LEFT"
    end
    return ExpandAnchoredRect(minX, maxX, minY, maxY, point, relPoint, x, y, rw, rh, targetW, targetH)
end
local function ApproxTextWidth(text, size, fallbackChars)
    local chars = type(text) == "string" and #text or tonumber(fallbackChars) or 8
    local width = (tonumber(size) or 12) * 0.58 * math.max(chars, 1)
    if width < 18 then width = 18 elseif width > 520 then width = 520 end
    return width
end
local function PreviewLayerWanted(box, layerKey)
    local visibility = box and box.layerVisibility
    return not (visibility and visibility[layerKey] == false)
end
local function PreviewPowerTextShown(runtimeSpec, conf)
    if runtimeSpec then return runtimeSpec.showPowerText ~= false end
    if conf and conf.showPowerText ~= nil then return conf.showPowerText ~= false end
    if conf and conf.showPower ~= nil then return conf.showPower ~= false end
    return true
end
local function NumberOrOne(value) return tonumber(value) or 1 end
local function CastbarNumFallback(_, _, fallback) return tonumber(fallback) or 0 end
local function CastbarTimeFallback(value) return tostring(value or "") end
local function ResolveNameAnchorFallback(_, x) return "TOPLEFT", "TOPLEFT", x or 0, "LEFT" end
local function EnsureCastbarPreviewRoundedSurface(cast)
    local surface = cast and cast._msufCastbarRoundedSurface
    if surface then return surface end
    if not (cast and type(_G.CreateFrame) == "function") then return nil end
    surface = CreateFrame("Frame", nil, cast)
    if surface.EnableMouse then surface:EnableMouse(false) end
    cast._msufCastbarRoundedSurface = surface
    return surface
end
local function LayoutCastbarPreviewSurface(cast)
    local surface = EnsureCastbarPreviewRoundedSurface(cast)
    if not surface then return cast end
    local left = tonumber(cast._msufCastbarRoundedSurfaceLeft) or 0
    local right = tonumber(cast._msufCastbarRoundedSurfaceRight) or 0
    local top = tonumber(cast._msufCastbarRoundedSurfaceTop) or 0
    local bottom = tonumber(cast._msufCastbarRoundedSurfaceBottom) or 0
    surface:ClearAllPoints()
    surface:SetPoint("TOPLEFT", cast, "TOPLEFT", left, -top)
    surface:SetPoint("BOTTOMRIGHT", cast, "BOTTOMRIGHT", -right, bottom)
    surface:Show()
    return surface
end
local function SetCastbarPreviewRoundedShown(cast, shown)
    local edge = cast and cast._msufCastbarRoundedEdge
    if edge then edge:Hide() end
    local stack = cast and cast._msufCastbarRoundedEdgeStack
    if type(stack) == "table" then
        for i = 1, #stack do if stack[i] then stack[i]:Hide() end end
    end
    local bg = cast and cast._msufCastbarRoundedBg
    if bg then if shown then bg:Show() else bg:Hide() end end
end
local function ApplyCastbarPreviewRounded(cast, g, edgeSize, bgR, bgG, bgB, bgA)
    local bars = _G.MSUF_DB and _G.MSUF_DB.bars
    local enabled = bars and bars.roundedFramesEnabled == true and bars.roundedCastbars == true
    local surface = LayoutCastbarPreviewSurface(cast)
    local bg = cast._msufCastbarRoundedBg
    if not bg then
        bg = cast:CreateTexture(nil, "BACKGROUND")
        if PreviewHelpers.SnapOff then PreviewHelpers.SnapOff(bg) end
        cast._msufCastbarRoundedBg = bg
    end
    bg:ClearAllPoints()
    bg:SetAllPoints(surface)
    bg:SetColorTexture(bgR or 0.10, bgG or 0.10, bgB or 0.10, bgA or 0.85)
    cast.statusBar = surface
    cast.backgroundBar = bg
    cast._msufIsPreview = true
    surface._msufCastbarPreviewOwner = cast
    if not surface.GetStatusBarTexture then
        surface.GetStatusBarTexture = function(self)
            local owner = self and self._msufCastbarPreviewOwner
            return owner and owner.fill or nil
        end
    end
    -- Clear artifacts produced by the retired Menu2-only rounded simulation.
    if PreviewHelpers.ClearMasks then
        PreviewHelpers.ClearMasks(cast, "_msufCastbarRoundedMasked")
    end
    SetCastbarPreviewRoundedShown(cast, false)
    local render = _G.MSUF_RoundedCastbar_RenderPreview
    if not enabled then
        if type(render) == "function" then render(cast, 0, 0, 0, 0, 0) end
        return false
    end
    if type(render) ~= "function"
        or render(cast, edgeSize, tonumber(g.castbarBorderR) or 0,
            tonumber(g.castbarBorderG) or 0, tonumber(g.castbarBorderB) or 0,
            tonumber(g.castbarBorderA) or 1) ~= true then
        return false
    end
    bg:Show()
    cast:SetBackdropColor(0, 0, 0, 0)
    cast:SetBackdropBorderColor(0, 0, 0, 0)
    return true
end
local UNIT_RENDER_FALLBACKS = {
    RuntimeSpecForPreviewKey = F.Nil, RuntimeAppliedPortraitSizeForPreviewKey = F.Nil, RuntimeVisualScaleForPreviewKey = F.One, RuntimeCastbarVisualScaleForPreviewKey = F.One, ClampPreviewZoom = NumberOrOne, ResolveDefaultPreviewZoomLock = F.Noop, UpdatePreviewZoomControls = F.Noop,
    ApplyPreviewRounded = F.Noop, ApplyPreviewFrameBorder = F.Noop, PreviewRoundedOutlineThickness = F.One, ApplyPreviewBoundsGuide = F.Noop,
    CastbarShowIcon = F.True, CastbarShowText = F.TruePair, ReadCastbarNum = CastbarNumFallback, FormatCastbarPreviewTime = CastbarTimeFallback,
    ClassColor = F.WhiteRGB, GradientPreviewColor = F.HealthRGB, HealthColor = F.HealthRGB, DarkMatchHPColor = F.HealthRGB, HealthBackgroundColor = F.DarkRGBA, PowerBackgroundColor = F.DarkRGBA, PowerColor = F.PowerRGB, FontColor = F.WhiteRGB,
    PreviewResolveHealPredAnchorMode = F.Right, PreviewResolveAbsorbAnchorMode = F.Right, PreviewHealPredictionEnabled = F.False, PreviewAbsorbBarEnabled = F.False,
    PreviewNameColor = F.WhiteRGB, PreviewToTInlineColor = F.WhiteRGB, NormalizeHpMode = F.Identity, NormalizePowerMode = F.Identity,
    TextScopeGet = F.Nil, TextScopeHasSlots = F.False, TextScopeSlotGet = F.Nil, FormatMode = F.Empty, ShortenPreviewName = F.Identity, ToTInlineSeparator = F.Identity,
    ResolveNameAnchor = ResolveNameAnchorFallback, LayoutUnitPreviewOverlay = F.Noop, PositionFromAnchor = F.Noop, PositionRuntimeLayoutIconPreview = F.Noop,
    PositionStatusCornerPreview = F.Noop, PositionSameAnchorPreview = F.Noop, PositionLevelPreview = F.Noop, ResolveStatusPreviewAnchor = F.Center,
    SetPreviewIconTexture = F.Noop, NormalizeStatusPreviewId = F.Identity, ApplyPreviewTextFocus = F.Noop,
}

--- Castbar preview detail layout mirrors the live CastbarVisuals rules without
--- subscribing to spellcast events. Keep all data reads profile/local here.
local CASTBAR_TEXT_HANDLE_OPTS = { fitText = true }
local function ApplyCastbarPreviewDetails(box, mock, canvas, g, key, castBarH, scw, S, max, min, floor, fr, fg, fb, TR, ApplyPreviewFont, CastbarShowIcon, CastbarShowText, ReadCastbarNum, FormatCastbarPreviewTime, UnitPreviewText, PlaceHandle, animState)
    local detailPrefix = CastbarPreviewDetailPrefix(key)
    local showIcon = CastbarShowIcon(key, g)
    mock.cast.icon:SetShown(showIcon)
    local iconX = ReadCastbarNum(g, key, "IconOffsetX", "bossCastIconOffsetX", 0)
    local iconY = ReadCastbarNum(g, key, "IconOffsetY", "bossCastIconOffsetY", 0)
    local iconSize = ReadCastbarNum(g, key, "IconSize", "bossCastIconSize", castBarH)
    if iconSize < 6 then iconSize = 6 elseif iconSize > 128 then iconSize = 128 end
    local sIcon = max(6, S(iconSize))
    local iconZoom = ReadCastbarNum(g, key, "IconZoom", "bossCastIconZoom", 100)
    local iconPosition = NormalizeCastbarPreviewIconPos(CastbarPreview.ReadString(g, key, "IconPosition", "bossCastIconPosition", "LEFT"))
    local iconSpacing = max(0, min(40, ReadCastbarNum(g, key, "IconSpacing", "bossCastIconSpacing", 1)))
    local iconBorderThickness = max(0, min(8, ReadCastbarNum(g, key, "IconBorderThickness", "bossCastIconBorderThickness", 0)))
    local iconBorderStyle = CastbarPreview.ReadString(g, key, "IconBorderStyle", "bossCastIconBorderStyle", "NONE")
    if showIcon then
        ApplyCastbarPreviewIconBorder(mock.cast.icon, iconBorderStyle, iconBorderThickness, g)
        ApplyCastbarPreviewIconZoom(mock.cast.icon, iconZoom)
        mock.cast.icon:SetSize(sIcon, sIcon)
        mock.cast.icon:ClearAllPoints()
        if iconPosition == "RIGHT" then
            mock.cast.icon:SetPoint("RIGHT", mock.cast, "RIGHT", S(iconX), S(iconY))
        elseif iconPosition == "INSIDE_RIGHT" then
            mock.cast.icon:SetPoint("RIGHT", mock.cast, "RIGHT", S(iconX - iconSpacing), S(iconY))
        elseif iconPosition == "INSIDE_LEFT" then
            mock.cast.icon:SetPoint("LEFT", mock.cast, "LEFT", S(iconX + iconSpacing), S(iconY))
        else
            mock.cast.icon:SetPoint("LEFT", mock.cast, "LEFT", S(iconX), S(iconY))
        end
        box.handleCastbarIcon:SetSize(max(18, sIcon + 8), max(18, sIcon + 8))
        PlaceHandle(box.handleCastbarIcon, mock.cast.icon)
    else
        HideCastbarPreviewIconBorder(mock.cast.icon)
        box.handleCastbarIcon:Hide()
    end
    local outlineThickness = max(0, min(12, floor((tonumber(g.castbarOutlineThickness) or 1) + 0.5)))
    local frameInset = outlineThickness > 0 and max(1, S(outlineThickness)) or 0
    local externalLeft = showIcon and iconPosition == "LEFT" and (sIcon + S(iconSpacing)) or 0
    local externalRight = showIcon and iconPosition == "RIGHT" and (sIcon + S(iconSpacing)) or 0
    mock.cast._msufCastbarRoundedSurfaceLeft = externalLeft + frameInset
    mock.cast._msufCastbarRoundedSurfaceRight = externalRight + frameInset
    mock.cast._msufCastbarRoundedSurfaceTop = frameInset
    mock.cast._msufCastbarRoundedSurfaceBottom = frameInset
    local surface = LayoutCastbarPreviewSurface(mock.cast)
    mock.cast.fill:ClearAllPoints()
    mock.cast.fill:SetPoint("TOPLEFT", surface, "TOPLEFT", 0, 0)
    mock.cast.fill:SetPoint("BOTTOMLEFT", surface, "BOTTOMLEFT", 0, 0)
    local timeReserve = max(S(2), min(S(60), floor(scw * 0.34 + 0.5)))
    local fillMaxW = max(S(2), scw - externalLeft - externalRight - (frameInset * 2))
    local castPct = animState and tonumber(animState.castPct) or 0.70
    if castPct < 0 then castPct = 0 elseif castPct > 1 then castPct = 1 end
    mock.cast.fill:SetWidth(max(S(2), floor(fillMaxW * castPct + 0.5)))
    local showText = CastbarShowText(key, g)
    mock.cast.text:SetShown(showText)
    if showText then
        local tr, tg, tb = fr, fg, fb
        if type(_G.MSUF_GetCastbarTextColor) == "function" then tr, tg, tb = _G.MSUF_GetCastbarTextColor() end
        tr = g[(detailPrefix or "") .. "SpellNameColorR"] or tr
        tg = g[(detailPrefix or "") .. "SpellNameColorG"] or tg
        tb = g[(detailPrefix or "") .. "SpellNameColorB"] or tb
        mock.cast.text:SetTextColor(tr, tg, tb, 1)
        local textSize = ReadCastbarNum(g, key, "SpellNameFontSize", "bossCastSpellNameFontSize", g.castbarSpellNameFontSize or g.fontSize or 14)
        if not textSize or textSize <= 0 then textSize = g.fontSize or 14 end
        ApplyPreviewFont(mock.cast.text, max(7, S(textSize)))
        local textX = ReadCastbarNum(g, key, "TextOffsetX", "bossCastTextOffsetX", 0)
        local textY = ReadCastbarNum(g, key, "TextOffsetY", "bossCastTextOffsetY", 0)
        local textPosition = NormalizeCastbarPreviewTextPos(CastbarPreview.ReadString(g, key, "SpellNamePosition", "bossCastSpellNamePosition", "LEFT"), "LEFT")
        AnchorCastbarPreviewText(mock.cast.text, surface, textPosition, textX, textY, CastbarPreviewJustifyForPosition(textPosition), S)
        local textMaxWidth = ReadCastbarNum(g, key, "SpellNameMaxWidth", "bossCastSpellNameMaxWidth", 0)
        local truncate = NormalizeCastbarPreviewTruncate(CastbarPreview.ReadString(g, key, "SpellNameTruncate", "bossCastSpellNameTruncate", "AUTO"))
        local spellName = ShortenCastbarPreviewSpellName(key, TR(key == "boss" and "Celestial Ruin" or "Arcane Surge"))
        mock.cast.text:SetText(spellName)
        if truncate == "NONE" then
            local naturalWidth = (mock.cast.text.GetStringWidth and mock.cast.text:GetStringWidth()) or scw
            mock.cast.text:SetWidth(max(20, scw, naturalWidth + 10))
        elseif truncate == "CLIP" and textMaxWidth and textMaxWidth > 0 then
            mock.cast.text:SetWidth(textMaxWidth)
        else
            mock.cast.text:SetWidth(max(20, scw - timeReserve - 10))
        end
        box.handleCastbarText:SetSize(max(34, mock.cast.text:GetStringWidth() + 10), max(18, mock.cast.text:GetStringHeight() + 6))
        if not UnitPreviewText.PlaceHandleAroundRegions(box.handleCastbarText, canvas,
            { mock.cast.text }, 3, CASTBAR_TEXT_HANDLE_OPTS)
        then
            PlaceHandle(box.handleCastbarText, mock.cast.text)
        end
    else
        box.handleCastbarText:Hide()
    end
    local showTargetName = (key == "target" and g.castbarTargetShowTargetName == true)
        or (key == "focus" and g.castbarFocusShowTargetName == true)
        or (key == "boss" and g.showBossCastTargetName == true)
    mock.cast.target:SetShown(showTargetName)
    if showTargetName then
        local targetSize = ReadCastbarNum(g, key, "TargetNameFontSize", "bossCastTargetNameFontSize", 10)
        if not targetSize or targetSize <= 0 then targetSize = 10 end
        ApplyPreviewFont(mock.cast.target, max(7, S(targetSize)))
        local targetR, targetG, targetB = CastbarPreview.ResolveTargetTextPreviewColor(key, 1, 0.82, 0.20)
        mock.cast.target:SetTextColor(targetR, targetG, targetB, 1)
        mock.cast.target:SetText(TR("Cleave Training Dummy"))
        local targetX = ReadCastbarNum(g, key, "TargetNameOffsetX", "bossCastTargetNameOffsetX", 0)
        local targetY = ReadCastbarNum(g, key, "TargetNameOffsetY", "bossCastTargetNameOffsetY", 1)
        local targetPosition = NormalizeCastbarPreviewTextPos(CastbarPreview.ReadString(g, key, "TargetNamePosition", "bossCastTargetNamePosition", "BELOW"), "BELOW")
        local targetJustify = NormalizeCastbarPreviewJustify(CastbarPreview.ReadString(g, key, "TargetNameAlign", "bossCastTargetNameAlign", "RIGHT"), "RIGHT")
        -- Runtime sizes and anchors this rect against frame.statusBar, whose
        -- width excludes external icons and the castbar outline. `surface` is
        -- the Unit Preview equivalent; using mock.cast shifts LEFT/CENTER text.
        mock.cast.target:SetWidth(max(20, fillMaxW - S(4)))
        AnchorCastbarPreviewText(mock.cast.target, surface, targetPosition, targetX, targetY, targetJustify, S)
        box.handleCastbarTarget:SetSize(max(48, mock.cast.target:GetStringWidth() + 10), max(18, mock.cast.target:GetStringHeight() + 6))
        if not UnitPreviewText.PlaceHandleAroundRegions(box.handleCastbarTarget, canvas,
            { mock.cast.target }, 3, CASTBAR_TEXT_HANDLE_OPTS)
        then
            PlaceHandle(box.handleCastbarTarget, mock.cast.target)
        end
    else
        mock.cast.target:SetText("")
        box.handleCastbarTarget:Hide()
    end
    local showTime = key == "boss" and g.showBossCastTime ~= false
        or (key == "target" and g.showTargetCastTime ~= false)
        or (key == "focus" and g.showFocusCastTime ~= false)
        or (key == "player" and g.showPlayerCastTime ~= false)
    mock.cast.time:SetShown(showTime)
    local castDuration = animState and tonumber(animState.castDuration) or 2.0
    local castCurrent = animState and (castDuration - (tonumber(animState.castRemaining) or 0)) or 1.4
    mock.cast.time:SetText(FormatCastbarPreviewTime(g, key, castCurrent, castDuration))
    if showTime then
        local timeX = ReadCastbarNum(g, key, "TimeOffsetX", "bossCastTimeOffsetX", g.castbarPlayerTimeOffsetX or -2)
        local timeY = ReadCastbarNum(g, key, "TimeOffsetY", "bossCastTimeOffsetY", g.castbarPlayerTimeOffsetY or 0)
        if key == "boss" then
            timeX = -2 + (tonumber(g.bossCastTimeOffsetX) or 0)
            timeY = tonumber(g.bossCastTimeOffsetY) or 0
        end
        local timeSize = ReadCastbarNum(g, key, "TimeFontSize", "bossCastTimeFontSize", g.castbarTimeFontSize or g.fontSize or 14)
        if not timeSize or timeSize <= 0 then timeSize = g.fontSize or 14 end
        ApplyPreviewFont(mock.cast.time, max(7, S(timeSize)))
        local tr, tg, tb = g[(detailPrefix or "") .. "TimeColorR"], g[(detailPrefix or "") .. "TimeColorG"], g[(detailPrefix or "") .. "TimeColorB"]
        if tr or tg or tb then mock.cast.time:SetTextColor(tr or fr, tg or fg, tb or fb, 1) else mock.cast.time:SetTextColor(fr, fg, fb, 1) end
        local timePosition = NormalizeCastbarPreviewTextPos(CastbarPreview.ReadString(g, key, "TimePosition", "bossCastTimePosition", "RIGHT"), "RIGHT")
        AnchorCastbarPreviewText(mock.cast.time, surface, timePosition, timeX, timeY, CastbarPreviewJustifyForPosition(timePosition), S)
        box.handleCastbarTime:SetSize(max(28, mock.cast.time:GetStringWidth() + 10), max(18, mock.cast.time:GetStringHeight() + 6))
        if not UnitPreviewText.PlaceHandleAroundRegions(box.handleCastbarTime, canvas,
            { mock.cast.time }, 3, CASTBAR_TEXT_HANDLE_OPTS)
        then
            PlaceHandle(box.handleCastbarTime, mock.cast.time)
        end
    else
        box.handleCastbarTime:Hide()
    end
end

--- Install render helpers onto the shared unit-preview object. View owns frame
--- construction; this module owns repeated visual composition.
function Render.Install(Preview, deps)
    if type(Preview) ~= "table" then return end
    deps = deps or Preview.RefreshDeps or {}
    Preview.RefreshDeps = deps
    local renderState = PickFallbackTable(deps, UNIT_RENDER_FALLBACKS, [[
        RuntimeSpecForPreviewKey RuntimeAppliedPortraitSizeForPreviewKey RuntimeVisualScaleForPreviewKey RuntimeCastbarVisualScaleForPreviewKey ClampPreviewZoom ResolveDefaultPreviewZoomLock UpdatePreviewZoomControls
        ApplyPreviewRounded ApplyPreviewFrameBorder PreviewRoundedOutlineThickness ApplyPreviewBoundsGuide CastbarShowIcon CastbarShowText ReadCastbarNum FormatCastbarPreviewTime
        ClassColor GradientPreviewColor HealthColor DarkMatchHPColor HealthBackgroundColor PowerBackgroundColor PowerColor FontColor PreviewResolveHealPredAnchorMode PreviewResolveAbsorbAnchorMode PreviewHealPredictionEnabled PreviewAbsorbBarEnabled
        PreviewNameColor PreviewToTInlineColor NormalizeHpMode NormalizePowerMode TextScopeGet TextScopeHasSlots TextScopeSlotGet FormatMode ShortenPreviewName ToTInlineSeparator ResolveNameAnchor
        LayoutUnitPreviewOverlay PositionFromAnchor PositionRuntimeLayoutIconPreview PositionStatusCornerPreview PositionSameAnchorPreview PositionLevelPreview ResolveStatusPreviewAnchor SetPreviewIconTexture NormalizeStatusPreviewId
    ]])
    renderState.GradientPreviewColor = Preview.Model and Preview.Model.GradientPreviewColor
        or renderState.GradientPreviewColor
    renderState.ZOOM_MIN = tonumber(deps.ZOOM_MIN) or 0.35
    --- Mock body clamp = the shared legal size range every conf.width/height
    --- writer enforces (State/MSUF_Defaults.lua exports it; the EM2 popup
    --- clamps writes against the same table). Clamping the mock any narrower
    --- makes the preview lie about tall/narrow frames — and every
    --- frame-relative offset (status icons, drag targets) with it.
    renderState.ClampUnitPreviewSize = function(w, h)
        local b = _G.MSUF_UnitFrameSizeBounds
        local minW = tonumber(b and b.minW) or 40
        local maxW = tonumber(b and b.maxW) or 800
        local minH = tonumber(b and b.minH) or 8
        local maxH = tonumber(b and b.maxH) or 200
        if w < minW then w = minW elseif w > maxW then w = maxW end
        if h < minH then h = minH elseif h > maxH then h = maxH end
        return w, h
    end
    renderState.UnitPreviewPortraitTexture = deps.UnitPreviewPortraitTexture
    renderState.ClassPortraitVisual = deps.ClassPortraitVisual
    renderState.PreviewStatus = MSUF.UFPreviewStatus or {}
    renderState.STATUS_RUNTIME_KEYS = {
        raidmarker = "raidMarker", leader = "leader", assist = "assist", level = "level",
        raceText = "race", classText = "classText",
        elite = "elite", statusText = "statusDeadText", statusGhostText = "statusGhostText",
        statusAFKText = "statusAFKText", statusDNDText = "statusDNDText",
        statusCombat = "combat", statusResting = "resting",
        statusIncomingRes = "incomingRes", statusPvp = "pvp",
    }
    renderState.ApplyPreviewTextFocus = deps.ApplyPreviewTextFocus or UNIT_RENDER_FALLBACKS.ApplyPreviewTextFocus
    local PowerColor = renderState.PowerColor
    local SharedCPPreview = MenuState.ClassPowerPreview or {}
    local function FallbackBase(_, _, r, g, b) return r or 1, g or 1, b or 1 end
    local function FallbackColor(_, r, g, b) return r or 1, g or 1, b or 1 end
    local function FallbackText(r, g, b) return r or 1, g or 1, b or 1 end
    local function FallbackFill(spec, index) return spec and index <= math.floor(tonumber(spec.value) or 0) and 1 or 0 end
    local function FallbackCombo(_, _, r, g, b) return r, g, b end
    local CPPreview = {
        BuildRuneOrder = SharedCPPreview.BuildRuneOrder or F.Nil,
        ColorOverride = SharedCPPreview.ColorOverride or F.Nil,
        FillForSegment = SharedCPPreview.FillForSegment or FallbackFill,
        FormatSeconds = SharedCPPreview.FormatSeconds or F.Empty,
        IsCharged = SharedCPPreview.IsCharged or F.False,
        IsFull = SharedCPPreview.IsFull or F.False,
        ResolveComboColor = SharedCPPreview.ResolveComboColor or FallbackCombo,
        ResolveSlotColor = SharedCPPreview.ResolveSlotColor or function(_, _, _, r, g, b) return r, g, b end,
        ResolveFullColor = SharedCPPreview.ResolveFullColor or function(_, _, r, g, b) return false, r, g, b end,
        ResolveBaseColor = function(spec, bars, fallbackR, fallbackG, fallbackB)
            return (SharedCPPreview.ResolveBaseColor or FallbackBase)(spec, bars, fallbackR, fallbackG, fallbackB, PowerColor)
        end,
        ResolveColor = function(token, fallbackR, fallbackG, fallbackB)
            return (SharedCPPreview.ResolveColor or FallbackColor)(token, fallbackR, fallbackG, fallbackB, PowerColor)
        end,
        ResolveTextColor = function(fallbackR, fallbackG, fallbackB)
            return (SharedCPPreview.ResolveTextColor or FallbackText)(fallbackR, fallbackG, fallbackB, PowerColor)
        end,
        AnimatedValue = SharedCPPreview.AnimatedValue,
        TextForValue = SharedCPPreview.TextForValue,
    }
    local fallbackFont = deps.FONT or _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    if type(deps.ApplyPreviewFont) ~= "function" then
        deps.ApplyPreviewFont = function(fs, size)
            if not (fs and fs.SetFont) then return end
            size = tonumber(size) or 12
            local fontPath, fontFlags, _, _, _, _, useShadow
            local gfs = _G.MSUF_GetGlobalFontSettings
            if type(gfs) == "function" then
                local path, flags, _, _, _, _, shadow = gfs()
                fontPath, fontFlags, useShadow = path, flags, shadow
            end
            if type(fontPath) ~= "string" or fontPath == "" then
                local getPath = _G.MSUF_GetFontPath
                if type(getPath) == "function" then fontPath = getPath() end
            end
            if fontFlags == nil then
                local getFlags = _G.MSUF_GetFontFlags
                fontFlags = (type(getFlags) == "function") and getFlags() or "OUTLINE"
            end
            if fontFlags == nil then fontFlags = "OUTLINE" end
            local db = _G.MSUF_DB
            local general = db and db.general
            local fontKey = general and general.fontKey
            if type(fontPath) ~= "string" or fontPath == "" then
                local pathForKey = _G.MSUF_ResolveFontKeyPath or _G.MSUF_GetFontPathForKey or (MSUF and MSUF.MSUF_GetFontPathForKey)
                if type(pathForKey) == "function" and fontKey then fontPath = pathForKey(fontKey, size, fontFlags) end
            end
            if type(fontPath) ~= "string" or fontPath == "" then fontPath = fallbackFont end
            local resolveSafe = _G.MSUF_ResolveSafeFontPath
            if type(resolveSafe) == "function" then fontPath = resolveSafe(fontPath, size, fontFlags, fontKey) end
            local ok = pcall(fs.SetFont, fs, fontPath, size, fontFlags)
            if not ok then
                pcall(fs.SetFont, fs, fallbackFont, size, fontFlags)
            end
            if fs.SetShadowOffset then
                if useShadow == nil then useShadow = not (general and general.textBackdrop == false) end
                if useShadow then
                    local shadowAlpha, shadowX, shadowY = _G.MSUF_ResolveFontShadowMetrics(
                        general and general.fontShadowOpacity, general and general.fontShadowDistance,
                        general and general.fontShadowStrength)
                    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, shadowAlpha) end
                    fs:SetShadowOffset(shadowX, shadowY)
                else
                    fs:SetShadowOffset(0, 0)
                end
            end
        end
    end
    -- Portrait rectangle in preview frame space (origin = frame bottom-left).
    -- Mirrors ResolvePortraitAnchor in the live element so the preview bounding
    -- box and the mock frame agree with what the unit frame actually renders.
    local PREVIEW_PORTRAIT_X = { TOPLEFT = 0, LEFT = 0, BOTTOMLEFT = 0, TOPRIGHT = 1, RIGHT = 1, BOTTOMRIGHT = 1 }
    local PREVIEW_PORTRAIT_Y = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, BOTTOMLEFT = 0, BOTTOM = 0, BOTTOMRIGHT = 0 }
    local function PreviewPortraitRect(placement, point, relPoint, overlayAlign, frameW, frameH, pw, ph, ox, oy, healthBottom)
        -- Live ATTACHED/OVERLAY portraits anchor to frame.Health, whose bottom
        -- is raised by an embedded power bar. DETACHED intentionally anchors
        -- to the unit frame and therefore ignores this inset.
        healthBottom = tonumber(healthBottom) or 0
        if healthBottom < 0 then healthBottom = 0 end
        if healthBottom > frameH then healthBottom = frameH end
        local healthH = frameH - healthBottom
        if placement == "OVERLAY" then
            if overlayAlign == "FULL" then
                return ox, healthBottom + oy, frameW - ox * 2, healthH - oy * 2
            end
            local left = ox
            if overlayAlign == "CENTER" then
                left = (frameW - pw) * 0.5 + ox
            elseif overlayAlign == "RIGHT" then
                left = frameW - pw + ox
            end
            return left, healthBottom + (healthH - ph) * 0.5 + oy, pw, ph
        end
        if placement == "DETACHED" then
            local relX = (PREVIEW_PORTRAIT_X[relPoint] or 0.5) * frameW
            local relY = (PREVIEW_PORTRAIT_Y[relPoint] or 0.5) * frameH
            local ownX = (PREVIEW_PORTRAIT_X[point] or 0.5) * pw
            local ownY = (PREVIEW_PORTRAIT_Y[point] or 0.5) * ph
            return relX + ox - ownX, relY + oy - ownY, pw, ph
        end
        -- ATTACHED: hug the outer edge of the bar area.
        local left = point == "LEFT" and (frameW + ox) or (ox - pw)
        return left, healthBottom + (healthH - ph) * 0.5 + oy, pw, ph
    end
    renderState.PreviewPortraitRect = PreviewPortraitRect
    -- Mirrors the live element's relief renderer: the same greyscale ring art,
    -- the same pre-baked 90 degree tex-coord rotations, tinted by the same
    -- border colour. Kept in this file rather than reaching into the engine so
    -- the preview keeps working when the engine has not compiled a spec yet.
    local PREVIEW_RING_ART_BASE = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Borders\\msuf_portrait_ring_"
    local PREVIEW_RING_ROTATION = {
        UP    = { 0, 0, 0, 1, 1, 0, 1, 1 },
        RIGHT = { 0, 1, 1, 1, 0, 0, 1, 0 },
        DOWN  = { 1, 1, 1, 0, 0, 1, 0, 0 },
        LEFT  = { 1, 0, 0, 0, 1, 1, 0, 1 },
    }
    local PREVIEW_RING_SHAPES = { SQUARE = "square", CIRCLE = "circle", ROUNDED = "rounded", DIAMOND = "diamond" }
    -- Mirrors the live element's BLIZZARD dressing: the stock circular mask
    -- atlas, the clean left half of the gold ring drawn straight plus
    -- mirrored (the shipped art opens into the bar housing on the right), and
    -- the corner embellishment -- same measured element fractions as the live
    -- element (uiunitframe element 198x71, portrait rect 7,4.5 size 60, ring
    -- circle 36,34.25 clip radius 34). Duplicated here like the relief ring
    -- above so the preview works before the engine has compiled a spec.
    local PREVIEW_BLIZZ = {
        maskAtlas = "UI-HUD-UnitFrame-Player-Portrait-Mask",
        frameAtlas = "UI-HUD-UnitFrame-Player-PortraitOn",
        cornerAtlas = "UI-HUD-UnitFrame-Player-PortraitOn-CornerEmbellishment",
        u0 = 2 / 198, u1 = 36 / 198, v0 = 0.25 / 71, v1 = 68.25 / 71,
        left = (2 - 7) / 60, axis = (36 - 7) / 60, right = (70 - 67) / 60,
        top = (0.25 - 4.5) / 60, bottom = (68.25 - 64.5) / 60,
        cornerOffset = 34.5 / 60, cornerSize = 23 / 60,
        circleMask = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\circle_mask.tga",
    }
    -- One mask texture per preview portrait covers every masked shape: the
    -- Blizzard shape sets the stock mask atlas, the geometric shapes set the
    -- same mask files the live element uses, SQUARE detaches the mask.
    local PREVIEW_SHAPE_MASKS = {
        CIRCLE = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\circle_mask.tga",
        ROUNDED = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\rounded_mask.tga",
        DIAMOND = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\diamond_mask.tga",
    }
    local PREVIEW_SOFT_EDGE_MASKS = { SQUARE = {}, CIRCLE = {}, ROUNDED = {}, DIAMOND = {} }
    do
        local root = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\"
        for level = 1, 15 do
            local suffix = (level < 10 and "0" or "") .. tostring(level) .. ".png"
            PREVIEW_SOFT_EDGE_MASKS.SQUARE[level] = root .. "texture_layer_edge_softness_" .. suffix
            PREVIEW_SOFT_EDGE_MASKS.CIRCLE[level] = root .. "portrait_edge_softness_circle_" .. suffix
            PREVIEW_SOFT_EDGE_MASKS.ROUNDED[level] = root .. "portrait_edge_softness_rounded_" .. suffix
            PREVIEW_SOFT_EDGE_MASKS.DIAMOND[level] = root .. "portrait_edge_softness_diamond_" .. suffix
        end
    end
    local function ApplyPreviewPortraitShapeMask(portrait, shape, edgeSoftnessLevel)
        local wantAtlas = shape == "BLIZZARD"
        local softMasks = PREVIEW_SOFT_EDGE_MASKS[shape]
        local file = softMasks and softMasks[edgeSoftnessLevel] or PREVIEW_SHAPE_MASKS[shape]
        local mask = portrait._msufPreviewShapeMask
        if not (wantAtlas or file) then
            if mask and portrait._msufPreviewShapeMasked then
                portrait._msufPreviewShapeMasked = nil
                portrait._msufPreviewShapeMaskKey = nil
                if portrait.tex and portrait.tex.RemoveMaskTexture then portrait.tex:RemoveMaskTexture(mask) end
                if portrait.bg and portrait.bg.RemoveMaskTexture then portrait.bg:RemoveMaskTexture(mask) end
            end
            return
        end
        if not mask then
            if not (portrait.CreateMaskTexture and portrait.tex and portrait.tex.AddMaskTexture) then return end
            mask = portrait:CreateMaskTexture()
            mask:SetAllPoints(portrait)
            portrait._msufPreviewShapeMask = mask
        end
        if not portrait._msufPreviewShapeMasked then
            portrait._msufPreviewShapeMasked = true
            portrait.tex:AddMaskTexture(mask)
            if portrait.bg and portrait.bg.AddMaskTexture then portrait.bg:AddMaskTexture(mask) end
        end
        local key = wantAtlas and "BLIZZARD" or file
        if portrait._msufPreviewShapeMaskKey ~= key then
            portrait._msufPreviewShapeMaskKey = key
            local GetAtlasInfo = _G.C_Texture and _G.C_Texture.GetAtlasInfo
            if wantAtlas and GetAtlasInfo and GetAtlasInfo(PREVIEW_BLIZZ.maskAtlas) then
                mask:SetAtlas(PREVIEW_BLIZZ.maskAtlas)
            else
                mask:SetTexture(wantAtlas and PREVIEW_BLIZZ.circleMask or file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            end
        end
    end
    renderState.ApplyPreviewPortraitShapeMask = ApplyPreviewPortraitShapeMask
    -- Mirrors the live element's solid ring renderer for shaped silhouettes:
    -- an inflated quad below the art, clipped by the same mask shape at the
    -- inflated size, tinted by the border colour.
    local function LayoutPreviewPortraitShapeRing(portrait, shape, thickness, r, g, b, a)
        local file = PREVIEW_SHAPE_MASKS[shape]
        local ring = portrait._msufPreviewShapeRing
        if not file then
            if ring then ring:Hide() end
            return false
        end
        if not ring then
            if not (portrait.CreateTexture and portrait.CreateMaskTexture) then return false end
            ring = portrait:CreateTexture(nil, "BACKGROUND", nil, -2)
            ring:SetTexture("Interface\\Buttons\\WHITE8x8")
            local mask = portrait:CreateMaskTexture()
            ring:AddMaskTexture(mask)
            portrait._msufPreviewShapeRing = ring
            portrait._msufPreviewShapeRingMask = mask
        end
        thickness = math.max(1, math.floor((tonumber(thickness) or 1) + 0.5))
        local key = shape .. "|" .. thickness
        if portrait._msufPreviewShapeRingKey ~= key then
            portrait._msufPreviewShapeRingKey = key
            local mask = portrait._msufPreviewShapeRingMask
            ring:ClearAllPoints()
            ring:SetPoint("TOPLEFT", portrait, "TOPLEFT", -thickness, thickness)
            ring:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", thickness, -thickness)
            if mask then
                mask:ClearAllPoints()
                mask:SetPoint("TOPLEFT", portrait, "TOPLEFT", -thickness, thickness)
                mask:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", thickness, -thickness)
                mask:SetTexture(file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            end
        end
        ring:SetVertexColor(r, g, b, a or 1)
        ring:Show()
        return true
    end
    local function LayoutPreviewBlizzardPortrait(portrait, active, pw, ph)
        local ring = portrait._msufPreviewBlizzRing
        if not active then
            if ring then ring:Hide() end
            if portrait._msufPreviewBlizzMirror then portrait._msufPreviewBlizzMirror:Hide() end
            if portrait._msufPreviewBlizzCorner then portrait._msufPreviewBlizzCorner:Hide() end
            return
        end
        local GetAtlasInfo = _G.C_Texture and _G.C_Texture.GetAtlasInfo
        local info = GetAtlasInfo and GetAtlasInfo(PREVIEW_BLIZZ.frameAtlas)
        local file = info and (info.file or info.filename)
        if not file then
            if ring then ring:Hide() end
            if portrait._msufPreviewBlizzMirror then portrait._msufPreviewBlizzMirror:Hide() end
            if portrait._msufPreviewBlizzCorner then portrait._msufPreviewBlizzCorner:Hide() end
            return
        end
        if not ring then
            if not portrait.CreateTexture then return end
            ring = portrait:CreateTexture(nil, "OVERLAY", nil, 2)
            local mirror = portrait:CreateTexture(nil, "OVERLAY", nil, 2)
            if portrait.CreateMaskTexture and ring.AddMaskTexture then
                local clip = portrait:CreateMaskTexture()
                clip:SetTexture(PREVIEW_BLIZZ.circleMask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                ring:AddMaskTexture(clip)
                mirror:AddMaskTexture(clip)
                portrait._msufPreviewBlizzClip = clip
            end
            portrait._msufPreviewBlizzRing = ring
            portrait._msufPreviewBlizzMirror = mirror
        end
        local mirror = portrait._msufPreviewBlizzMirror
        local l0 = tonumber(info.leftTexCoord) or 0
        local t0 = tonumber(info.topTexCoord) or 0
        local du = (tonumber(info.rightTexCoord) or 1) - l0
        local dv = (tonumber(info.bottomTexCoord) or 1) - t0
        local cl = l0 + PREVIEW_BLIZZ.u0 * du
        local cr = l0 + PREVIEW_BLIZZ.u1 * du
        local ct = t0 + PREVIEW_BLIZZ.v0 * dv
        local cb = t0 + PREVIEW_BLIZZ.v1 * dv
        ring:SetTexture(file)
        ring:SetTexCoord(cl, cr, ct, cb)
        if mirror then
            mirror:SetTexture(file)
            mirror:SetTexCoord(cr, cl, ct, cb)
        end
        local key = pw .. "|" .. ph
        if portrait._msufPreviewBlizzKey ~= key then
            portrait._msufPreviewBlizzKey = key
            ring:ClearAllPoints()
            ring:SetPoint("TOPLEFT", portrait, "TOPLEFT", PREVIEW_BLIZZ.left * pw, -PREVIEW_BLIZZ.top * ph)
            ring:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMLEFT", PREVIEW_BLIZZ.axis * pw, -PREVIEW_BLIZZ.bottom * ph)
            if mirror then
                mirror:ClearAllPoints()
                mirror:SetPoint("TOPLEFT", portrait, "TOPLEFT", PREVIEW_BLIZZ.axis * pw, -PREVIEW_BLIZZ.top * ph)
                mirror:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", PREVIEW_BLIZZ.right * pw, -PREVIEW_BLIZZ.bottom * ph)
            end
            local clip = portrait._msufPreviewBlizzClip
            if clip then
                clip:ClearAllPoints()
                clip:SetPoint("TOPLEFT", portrait, "TOPLEFT", PREVIEW_BLIZZ.left * pw, -PREVIEW_BLIZZ.top * ph)
                clip:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", PREVIEW_BLIZZ.right * pw, -PREVIEW_BLIZZ.bottom * ph)
            end
        end
        ring:Show()
        if mirror then mirror:Show() end
        local corner = portrait._msufPreviewBlizzCorner
        if not corner and GetAtlasInfo(PREVIEW_BLIZZ.cornerAtlas) then
            corner = portrait:CreateTexture(nil, "OVERLAY", nil, 3)
            corner:SetAtlas(PREVIEW_BLIZZ.cornerAtlas)
            portrait._msufPreviewBlizzCorner = corner
        end
        if corner then
            if portrait._msufPreviewBlizzCornerKey ~= key then
                portrait._msufPreviewBlizzCornerKey = key
                corner:ClearAllPoints()
                corner:SetPoint("TOPLEFT", portrait, "TOPLEFT", PREVIEW_BLIZZ.cornerOffset * pw, -PREVIEW_BLIZZ.cornerOffset * ph)
                corner:SetSize(PREVIEW_BLIZZ.cornerSize * pw, PREVIEW_BLIZZ.cornerSize * ph)
            end
            corner:Show()
        end
    end
    renderState.LayoutPreviewBlizzardPortrait = LayoutPreviewBlizzardPortrait
    local function LayoutPreviewPortraitArtBorder(portrait, thickness, r, g, b, a)
        local art = portrait._msufPreviewArtBorder
        if not art then
            if not portrait.CreateTexture then return false end
            art = portrait:CreateTexture(nil, "OVERLAY", nil, 2)
            portrait._msufPreviewArtBorder = art
        end
        local shape = PREVIEW_RING_SHAPES[portrait._msufPreviewBorderShape or "SQUARE"] or "square"
        local direction = portrait._msufPreviewBorderDirection or "UP"
        -- Same derivation as the live element: the ring art's opening is a fixed
        -- fraction of the texture, so the inflation comes from the portrait size
        -- rather than from a raw pixel thickness.
        -- Per axis, like the live element: a non-square portrait stretches the
        -- mask and the ring quad identically only if each axis is inflated from
        -- its own extent.
        local ix, iy = PreviewPortraitRingInflation(portrait, thickness)
        local key = shape .. "|" .. ix .. "|" .. iy .. "|" .. direction
        if portrait._msufPreviewArtKey ~= key then
            art:ClearAllPoints()
            art:SetPoint("TOPLEFT", portrait, "TOPLEFT", -ix, iy)
            art:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", ix, -iy)
            art:SetTexture(PREVIEW_RING_ART_BASE .. shape .. ".tga")
            local rotation = PREVIEW_RING_ROTATION[direction] or PREVIEW_RING_ROTATION.UP
            art:SetTexCoord(rotation[1], rotation[2], rotation[3], rotation[4],
                rotation[5], rotation[6], rotation[7], rotation[8])
            portrait._msufPreviewArtKey = key
        end
        art:SetVertexColor(r, g, b, a or 1)
        art:Show()
        return true
    end
    local function LayoutPreviewPortraitBorder(portrait, thickness, fill, r, g, b, a)
        local border = portrait and portrait.border
        if not border then return end
        if not r then
            if PreviewHelpers.SetEdgeLinesShown then PreviewHelpers.SetEdgeLinesShown(border, false, border._msufPreviewEdgeOpts) end
            border:Hide()
            if portrait._msufPreviewArtBorder then portrait._msufPreviewArtBorder:Hide() end
            if portrait._msufPreviewShapeRing then portrait._msufPreviewShapeRing:Hide() end
            return
        end
        if portrait._msufPreviewBorderArt == "RELIEF"
            and LayoutPreviewPortraitArtBorder(portrait, thickness, r, g, b, a) then
            if PreviewHelpers.SetEdgeLinesShown then PreviewHelpers.SetEdgeLinesShown(border, false, border._msufPreviewEdgeOpts) end
            border:Hide()
            if portrait._msufPreviewShapeRing then portrait._msufPreviewShapeRing:Hide() end
            return
        end
        if portrait._msufPreviewArtBorder then portrait._msufPreviewArtBorder:Hide() end
        -- Shaped silhouettes replace the straight edge renderer with the same
        -- shape-following ring the live element draws.
        local ringShape = portrait._msufPreviewBorderShape or "SQUARE"
        if LayoutPreviewPortraitShapeRing(portrait, ringShape, thickness, r, g, b, a) then
            if PreviewHelpers.SetEdgeLinesShown then PreviewHelpers.SetEdgeLinesShown(border, false, border._msufPreviewEdgeOpts) end
            border:Hide()
            return
        end
        if portrait._msufPreviewShapeRing then portrait._msufPreviewShapeRing:Hide() end
        thickness = math.floor((tonumber(thickness) or 1) + 0.5)
        if thickness < 1 then thickness = 1 end
        if thickness > 30 then thickness = 30 end
        local key = thickness .. "|" .. (fill and "1" or "0")
        if portrait._previewBorderKey ~= key then
            border:ClearAllPoints()
            if fill then
                border:SetAllPoints(portrait)
            else
                border:SetPoint("TOPLEFT", portrait, "TOPLEFT", -thickness, thickness)
                border:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", thickness, -thickness)
            end
            portrait._previewBorderKey = key
        end
        border._msufPreviewEdgeR, border._msufPreviewEdgeG, border._msufPreviewEdgeB, border._msufPreviewEdgeA = r, g, b, a or 1
        border._msufPreviewEdgeOpts = border._msufPreviewEdgeOpts or {
            linesKey = "edges",
            maxEdgeSize = 30,
            color = function(frame)
                return frame._msufPreviewEdgeR or 1, frame._msufPreviewEdgeG or 1, frame._msufPreviewEdgeB or 1, frame._msufPreviewEdgeA or 1
            end,
        }
        if PreviewHelpers.LayoutEdgeLines then PreviewHelpers.LayoutEdgeLines(border, thickness, border._msufPreviewEdgeOpts) end
        border:Show()
    end
    renderState.CPPreview = CPPreview
    renderState.LayoutPreviewPortraitBorder = LayoutPreviewPortraitBorder
    deps._RenderState = renderState

local function RenderTempMaxHealth(mock, runtimeSpec, conf, general, key, hpReverse, hpAreaW, setTexture)
    local cfg = runtimeSpec and runtimeSpec.tempMaxHealth
    local shown = cfg and cfg.enabled == true
    if not cfg then
        local enabled = general and general.tempMaxHealthEnabled
        if conf and conf.hlOverride == true and conf.tempMaxHealthEnabled ~= nil then enabled = conf.tempMaxHealthEnabled end
        shown = enabled == true
        if _G.MSUF_ShouldShowAbsorbTextureTest
            and _G.MSUF_ShouldShowAbsorbTextureTest(nil, key, "tempMaxHealth") then
            shown = true
        end
    end
    if not shown then
        mock.tempMaxHealthBg:Hide()
        mock.tempMaxHealth:Hide()
        return
    end

    local texture = cfg and cfg.texture
        or (type(_G.MSUF_ResolveStatusbarTextureKey) == "function"
            and _G.MSUF_ResolveStatusbarTextureKey((conf and conf.tempMaxHealthTexture)
                or (general and general.tempMaxHealthTexture) or "Solid"))
        or "Interface\\Buttons\\WHITE8X8"
    setTexture(mock.tempMaxHealth, texture)
    mock.tempMaxHealth:SetVertexColor(
        tonumber(cfg and cfg.r) or tonumber(general and general.tempMaxHealthColorR) or 0.70,
        tonumber(cfg and cfg.g) or tonumber(general and general.tempMaxHealthColorG) or 0.10,
        tonumber(cfg and cfg.b) or tonumber(general and general.tempMaxHealthColorB) or 0.10,
        tonumber(cfg and cfg.a) or tonumber(general and general.tempMaxHealthOpacity) or 1)
    mock.tempMaxHealthBg:SetColorTexture(0, 0, 0,
        tonumber(cfg and cfg.backgroundAlpha) or tonumber(general and general.tempMaxHealthBackgroundOpacity) or 0.65)
    mock.tempMaxHealth:ClearAllPoints()
    mock.tempMaxHealthBg:ClearAllPoints()
    if hpReverse then
        mock.tempMaxHealth:SetPoint("TOPLEFT", mock.healthBar, "TOPLEFT", 0, 0)
        mock.tempMaxHealth:SetPoint("BOTTOMLEFT", mock.healthBar, "BOTTOMLEFT", 0, 0)
        mock.tempMaxHealthBg:SetPoint("TOPLEFT", mock.healthBar, "TOPLEFT", 0, 0)
        mock.tempMaxHealthBg:SetPoint("BOTTOMLEFT", mock.healthBar, "BOTTOMLEFT", 0, 0)
    else
        mock.tempMaxHealth:SetPoint("TOPRIGHT", mock.healthBar, "TOPRIGHT", 0, 0)
        mock.tempMaxHealth:SetPoint("BOTTOMRIGHT", mock.healthBar, "BOTTOMRIGHT", 0, 0)
        mock.tempMaxHealthBg:SetPoint("TOPRIGHT", mock.healthBar, "TOPRIGHT", 0, 0)
        mock.tempMaxHealthBg:SetPoint("BOTTOMRIGHT", mock.healthBar, "BOTTOMRIGHT", 0, 0)
    end
    local lossWidth = math.max(1, hpAreaW * 0.20)
    mock.tempMaxHealth:SetWidth(lossWidth)
    mock.tempMaxHealthBg:SetWidth(lossWidth)
    mock.tempMaxHealthBg:Show()
    mock.tempMaxHealth:Show()
end

local TEXLAYER_PREVIEW_POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
local TEXLAYER_PREVIEW_GRADIENT_DIRS = {
    right = "GradientDirRight",
    left = "GradientDirLeft",
    up = "GradientDirUp",
    down = "GradientDirDown",
}
local TEXLAYER_PREVIEW_PREFIXES = { "texLayer", "texLayer2", "texLayer3" }
local function PreviewTextureLayerConfigured(conf)
    if type(conf) ~= "table" then return false end
    for slot = 1, #TEXLAYER_PREVIEW_PREFIXES do
        if conf[TEXLAYER_PREVIEW_PREFIXES[slot] .. "Enabled"] == true then return true end
    end
    return false
end
local function TextureLayerPreviewData(conf, unitKey, data)
    if type(conf) ~= "table" or type(data) ~= "table" then return data end
    local slots = MenuState.unitTexLayerSlot
    local slot = slots and tonumber(slots[unitKey]) or 1
    if not slot or slot < 1 or slot > #TEXLAYER_PREVIEW_PREFIXES then slot = 1 end
    local prefix = TEXLAYER_PREVIEW_PREFIXES[slot]
    if conf[prefix .. "Enabled"] ~= true
        or (conf[prefix .. "HealthCondition"] ~= "BELOW"
            and conf[prefix .. "HealthLowAlphaEnabled"] ~= true) then
        return data
    end
    local threshold = tonumber(conf[prefix .. "HealthThreshold"]) or 0.35
    if threshold < 0.01 then threshold = 0.01 elseif threshold > 1 then threshold = 1 end
    local previewHP = math.max(0.01, threshold * 0.5)
    local copy = {}
    for key, value in pairs(data) do copy[key] = value end
    copy.hp = previewHP
    if tonumber(copy.hpMax) then copy.hpCur = math.floor((copy.hpMax * previewHP) + 0.5) end
    return copy
end
--- Decorative texture layers as their own preview layer (3 slots). Geometry is
--- scaled for the viewport, while visibility, strata, parent-alpha behavior and
--- texture resolution are delegated to the same runtime helpers used by live
--- frames. Kept out of Preview.Refresh, which sits at the 200-local limit.
local function RenderTextureLayerSlotPreview(box, mock, conf, slot, wanted, scaleFn, sw, baseLevel, setTexture, placeHandle, classR, classG, classB, healthR, healthG, healthB, healthPct)
    local prefix = TEXLAYER_PREVIEW_PREFIXES[slot]
    local holder = mock and mock.texLayers and mock.texLayers[slot]
    if not holder then return end
    local handle = box and box.texLayerHandles and box.texLayerHandles[slot]
    local textureRuntime = MSUF and MSUF.TextureLayer
    local runtimeVisible = conf and (not (textureRuntime and type(textureRuntime.LayerVisible) == "function")
        or textureRuntime.LayerVisible(conf, prefix) == true)
    local threshold = tonumber(conf and conf[prefix .. "HealthThreshold"]) or 0.35
    if threshold < 0.01 then threshold = 0.01 elseif threshold > 1 then threshold = 1 end
    local healthVisible = not conf or conf[prefix .. "HealthCondition"] ~= "BELOW"
        or (tonumber(healthPct) or 1) < threshold
    if not (wanted and conf and conf[prefix .. "Enabled"] == true and runtimeVisible and healthVisible) then
        if textureRuntime and type(textureRuntime.ApplySoftEdgeMask) == "function" then
            textureRuntime.ApplySoftEdgeMask(holder, {}, 0)
        end
        holder:Hide()
        if handle then handle:Hide() end
        return
    end
    if textureRuntime and type(textureRuntime.ApplyLayerStrata) == "function" then
        textureRuntime.ApplyLayerStrata(mock, holder, conf[prefix .. "Strata"])
    end
    if holder.SetFrameLevel then
        local level = tonumber(conf[prefix .. "Level"]) or 1
        if level < 0 then level = 0 elseif level > 30 then level = 30 end
        local resolvedLevel = Layers.ElementLevel and Layers.ElementLevel(level, 1, 0)
            or ((baseLevel or 0) + level)
        holder:SetFrameLevel(resolvedLevel)
    end
    if holder.SetIgnoreParentAlpha then
        holder:SetIgnoreParentAlpha(conf[prefix .. "FollowFrameAlpha"] == false)
    end
    -- Anchor target: the mock body or one of its element regions.
    local anchorMode = conf[prefix .. "AnchorTarget"]
    local target = mock
    if anchorMode == "HEALTH" then
        target = mock.healthBar or mock.hpBG or mock
    elseif anchorMode == "POWER" then
        target = (mock.powerBG and mock.powerBG.IsShown and mock.powerBG:IsShown() and mock.powerBG) or mock
    elseif anchorMode == "PORTRAIT" then
        target = (mock.portrait and mock.portrait.IsShown and mock.portrait:IsShown() and mock.portrait) or mock
    end
    local point = conf[prefix .. "Anchor"]
    if not TEXLAYER_PREVIEW_POINTS[point] then point = "TOP" end
    holder:ClearAllPoints()
    holder:SetPoint(point, target, point, scaleFn(tonumber(conf[prefix .. "OffsetX"]) or 0), scaleFn(tonumber(conf[prefix .. "OffsetY"]) or 0))
    local width = tonumber(conf[prefix .. "Width"]) or 0
    if width > 0 then
        width = scaleFn(width)
    else
        width = (target.GetWidth and target:GetWidth()) or sw
        if not width or width < 1 then width = sw end
    end
    local rawHeight = tonumber(conf[prefix .. "Height"])
    if rawHeight == nil then rawHeight = 16 end
    local height
    if rawHeight <= 0 then
        height = (target.GetHeight and target:GetHeight()) or (mock.GetHeight and mock:GetHeight()) or scaleFn(16)
    else
        height = scaleFn(rawHeight)
    end
    holder:SetSize(math.max(1, width), math.max(1, height))
    local clipWanted = conf[prefix .. "RoundedClip"] == true
        and _G.MSUF_RoundedUF_Active == true
        and type(_G.MSUF_RoundedUF_OnDispelOverlayChanged) == "function"
    local tex = holder.tex
    if tex and tex._msufTextureLayerRoundedClip == true and not clipWanted then
        tex:Hide()
        tex = holder:CreateTexture(nil, "ARTWORK", nil, 0)
        tex:SetAllPoints(holder)
        holder.tex = tex
    end
    local path = textureRuntime and type(textureRuntime.ResolveLayerTexture) == "function"
        and textureRuntime.ResolveLayerTexture(conf, prefix) or conf[prefix .. "CustomTexturePath"]
    if type(path) ~= "string" or path == "" then path = nil end
    if not path then
        local texKey = conf[prefix .. "Texture"]
        if type(texKey) == "string" and texKey ~= "" and type(_G.MSUF_ResolveStatusbarTextureKey) == "function" then path = _G.MSUF_ResolveStatusbarTextureKey(texKey) end
    end
    if type(path) ~= "string" or path == "" then
        path = (type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture()) or "Interface\\Buttons\\WHITE8x8"
    end
    setTexture(tex, path)
    if textureRuntime and type(textureRuntime.ApplyColorTreatment) == "function" then
        textureRuntime.ApplyColorTreatment(tex, conf, prefix)
    elseif tex.SetDesaturated then
        tex:SetDesaturated(conf[prefix .. "ColorTreatment"] == "MONOCHROME")
    end
    if tex.SetBlendMode then
        tex:SetBlendMode(conf[prefix .. "BlendMode"] == "ADD" and "ADD" or "BLEND")
    end
    -- Crop/mirroring runs after setTexture so the explicit region wins over
    -- the shared SetTex inset. Runtime owns the resolver to keep both views
    -- pixel-identical.
    if tex.SetTexCoord then
        if textureRuntime and type(textureRuntime.ResolveTexCoords) == "function" then
            tex:SetTexCoord(textureRuntime.ResolveTexCoords(conf, prefix))
        else
            local mirrorH = conf[prefix .. "MirrorH"] == true
            local mirrorV = conf[prefix .. "MirrorV"] == true
            tex:SetTexCoord(mirrorH and 1 or 0, mirrorH and 0 or 1, mirrorV and 1 or 0, mirrorV and 0 or 1)
        end
    end
    local r = tonumber(conf[prefix .. "ColorR"]) or 1
    local g = tonumber(conf[prefix .. "ColorG"]) or 1
    local b = tonumber(conf[prefix .. "ColorB"]) or 1
    if conf[prefix .. "ColorMode"] == "CLASS" and classR then
        r, g, b = classR, classG or 1, classB or 1
    elseif conf[prefix .. "ColorMode"] == "HEALTH" and healthR then
        local aboveMode = conf[prefix .. "HealthAboveMode"]
        if (tonumber(healthPct) or 1) < threshold or (aboveMode ~= "CLASS" and aboveMode ~= "CUSTOM") then
            r, g, b = healthR, healthG or 1, healthB or 1
        elseif aboveMode == "CLASS" and classR then
            r, g, b = classR, classG or 1, classB or 1
        end
    end
    local CreateColor = _G.CreateColor
    if tex.SetGradient and CreateColor then
        local solid = CreateColor(r, g, b, 1)
        tex:SetGradient("HORIZONTAL", solid, solid)
    elseif tex.SetVertexColor then
        tex:SetVertexColor(r, g, b, 1)
    end
    if clipWanted then
        _G.MSUF_RoundedUF_OnDispelOverlayChanged(mock, tex)
        tex._msufTextureLayerRoundedClip = true
    end
    local featherTextures = { tex }
    -- Bars-style multi-direction gradient: one overlay per active edge, exactly
    -- mirroring UnitFrames/Effects/MSUF_UF_TextureLayer.lua.
    local gradientOn = conf[prefix .. "GradientEnabled"] == true
    local r2 = tonumber(conf[prefix .. "Gradient2R"]) or 0
    local g2 = tonumber(conf[prefix .. "Gradient2G"]) or 0
    local b2 = tonumber(conf[prefix .. "Gradient2B"]) or 0
    for direction, dirSuffix in pairs(TEXLAYER_PREVIEW_GRADIENT_DIRS) do
        local active = gradientOn
        if active then
            local value = conf[prefix .. dirSuffix]
            active = direction == "right" and value ~= false or value == true
        end
        local grads = holder.grads
        local overlay = grads and grads[direction]
        if not active then
            if overlay then overlay:Hide() end
        else
            if not grads then
                grads = {}
                holder.grads = grads
            end
            if overlay and overlay._msufTextureLayerRoundedClip == true and not clipWanted then
                overlay:Hide()
                overlay = nil
            end
            if not overlay then
                overlay = holder:CreateTexture(nil, "ARTWORK", nil, 1)
                overlay:SetAllPoints(holder)
                overlay:SetTexture("Interface\\Buttons\\WHITE8x8")
                if overlay.SetBlendMode then overlay:SetBlendMode("BLEND") end
                grads[direction] = overlay
            end
            if clipWanted then
                _G.MSUF_RoundedUF_OnDispelOverlayChanged(mock, overlay)
                overlay._msufTextureLayerRoundedClip = true
            end
            local orientation = (direction == "up" or direction == "down") and "VERTICAL" or "HORIZONTAL"
            local minA, maxA = 0, 1
            if direction == "left" or direction == "down" then minA, maxA = 1, 0 end
            if overlay.SetGradient and CreateColor then
                overlay:SetGradient(orientation, CreateColor(r2, g2, b2, minA), CreateColor(r2, g2, b2, maxA))
            elseif overlay.SetVertexColor then
                overlay:SetVertexColor(r2, g2, b2, 0.5)
            end
            featherTextures[#featherTextures + 1] = overlay
            overlay:Show()
        end
    end
    if textureRuntime and type(textureRuntime.ApplySoftEdgeMask) == "function" then
        textureRuntime.ApplySoftEdgeMask(holder, featherTextures, conf[prefix .. "EdgeSoftness"])
    end
    local alpha = tonumber(conf[prefix .. "Alpha"]) or 1
    if alpha < 0 then alpha = 0 elseif alpha > 1 then alpha = 1 end
    if conf[prefix .. "HealthLowAlphaEnabled"] == true
        and (tonumber(healthPct) or 1) < threshold then
        alpha = tonumber(conf[prefix .. "HealthLowAlpha"]) or 1
        if alpha < 0 then alpha = 0 elseif alpha > 1 then alpha = 1 end
    end
    holder:SetAlpha(alpha)
    holder:Show()
    if handle then
        handle:SetSize(math.max(18, width + 8), math.max(18, height + 8))
        if placeHandle then placeHandle(handle, holder) end
    end
end

local function RenderTextureLayerPreview(box, mock, conf, wanted, scaleFn, sw, baseLevel, setTexture, placeHandle, renderState, data, health)
    local classR, classG, classB = renderState.ClassColor(data.class)
    local gradientColor = renderState.GradientPreviewColor or UNIT_RENDER_FALLBACKS.GradientPreviewColor
    local healthR, healthG, healthB = gradientColor(data.hp, health)
    for slot = 1, #TEXLAYER_PREVIEW_PREFIXES do
        RenderTextureLayerSlotPreview(box, mock, conf, slot, wanted, scaleFn, sw, baseLevel, setTexture, placeHandle,
            classR, classG, classB, healthR, healthG, healthB, data.hp)
    end
end

--- Hot refresh for the unit preview. It composes current DB/model values into
--- mock regions and handle positions, but never mutates live unit frames.
function Preview.Refresh(box, reason)
    box = box or Preview.active
    if not box or not box:IsShown() then return end
    local D = Preview.RefreshDeps
    local R = D._RenderState or {}
    local PreviewInCombat = D.PreviewInCombat
    if PreviewInCombat() then return end
    local TR, PortraitStyleGet, max, min, abs, floor, format, TEX_W8, ApplyPreviewFont, CastbarEnabled, ReadCastbarSize, CastbarOffsetFields, CastbarDetached, CanDetachPowerBarKey, ClampPreviewLayer, SetTex, ReadPowerBarHeight, PlaceHandle, UnitPreviewText, UnitPreviewTextMovesTogether, SetShownSafe, ApplyPreviewLayerVisibility, ApplyPreviewTransparency, RefreshHandleSelectionVisuals, Auras = Pick(D, [[TR PortraitStyleGet max min abs floor format TEX_W8 ApplyPreviewFont CastbarEnabled ReadCastbarSize CastbarOffsetFields CastbarDetached CanDetachPowerBarKey ClampPreviewLayer SetTex ReadPowerBarHeight PlaceHandle UnitPreviewText UnitPreviewTextMovesTogether SetShownSafe ApplyPreviewLayerVisibility ApplyPreviewTransparency RefreshHandleSelectionVisuals Auras]])
    local panel = box._msufPanel
    local UNIT_DATA = D.UNIT_DATA or {}
    local UNIT_LABELS = D.UNIT_LABELS or {}
    local key = D.CurrentPanelKey(panel)
    local conf, g = D.UnitDB(key)
    --- Guides are setting-backed, unlike the other ephemeral preview layers.
    --- Re-read them on every visible preview refresh so a factory reset or
    --- profile switch cannot leave the already-built layer rail stale.
    if type(box.layerVisibility) == "table" then
        box.layerVisibility.guides = g.unitPreviewGuidesEnabled ~= false
    end
    -- Live snapshot first so the preview mirrors the real frame's current
    -- state (exact name/class/HP/power); stylized mock only as fallback.
    local data = (D.LiveUnitData and D.LiveUnitData(key)) or UNIT_DATA[key] or UNIT_DATA.player or {}
    local runtimeSpec = R.RuntimeSpecForPreviewKey(key)
    local runtimePower = runtimeSpec and runtimeSpec.power
    local runtimeStatus = runtimeSpec and runtimeSpec.status
    box._previewStatusText = R.PreviewStatus.StatusTextPreviewText
        and R.PreviewStatus.StatusTextPreviewText((runtimeStatus and runtimeStatus.statusText) or g, PreviewLiveStatusText(key))
    local runtimeText = runtimeSpec and runtimeSpec.text
    local runtimeClassPower = runtimeSpec and runtimeSpec.classPower
    box.key = key
    if D.SyncLiveStateDriver then D.SyncLiveStateDriver(box, key) end
    local skipControlRefresh = (reason == "OPTIONS_APPLY_DB" or reason == "UNIT_MENU_ENTER" or reason == "UNIT_MENU_REENTER")
        or reason == "UNIT_PREVIEW_DRAG"
        or reason == "UNIT_PREVIEW_ANIMATE"
        or reason == "UNIT_PREVIEW_ANIMATE_TOGGLE"
        or reason == "UNIT_PREVIEW_COMBAT_ANIMATE"
        or reason == "UNIT_PREVIEW_ZOOM"
        or reason == "UNIT_PREVIEW_ZOOM_STEP"
        or reason == "UNIT_PREVIEW_ZOOM_FIT"
        or reason == "UNIT_PREVIEW_ZOOM_1TO1"
        or reason == "MENU_TEXT_FOCUS"
        or reason == "MENU_TEXT_CLEAR_FOCUS"
    if panel and panel._msufRefreshUnitTextControls and not skipControlRefresh and not box._refreshingControls then
        box._refreshingControls = true
        panel._msufRefreshUnitTextControls()
        if panel._msufRefreshUnitPortraitControls then panel._msufRefreshUnitPortraitControls() end
        if panel._msufRefreshUnitPowerControls then panel._msufRefreshUnitPowerControls() end
        box._refreshingControls = nil
    end
    if box.title then box.title:SetText(TR("Unit Frame Preview") .. " - " .. TR(UNIT_LABELS[key] or key)) end
    local canvas = box.canvas
    local cw = canvas:GetWidth() or 600
    local ch = canvas:GetHeight() or 180
    if cw <= 1 then cw = 600 end
    if ch <= 1 then ch = 180 end
    local w = tonumber(runtimeSpec and runtimeSpec.width) or tonumber(conf.width or conf.frameWidth) or (key == "boss" and 180 or (key == "focus" and 180 or 275))
    local h = tonumber(runtimeSpec and runtimeSpec.height) or tonumber(conf.height or conf.frameHeight) or (key == "boss" and 30 or (key == "focus" and 30 or 40))
    w, h = R.ClampUnitPreviewSize(w, h)
    local mode = (runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.side) or conf.portraitMode
    local hasPortrait
    if runtimeSpec and runtimeSpec.portrait then
        hasPortrait = runtimeSpec.portrait.enabled == true
    else
        hasPortrait = (mode == "LEFT" or mode == "RIGHT")
    end
    box._runtimeDefensivePortraitPositionOnly = not hasPortrait
        and Auras and Auras.WantsDefensivePortraitAnchor
        and Auras.WantsDefensivePortraitAnchor(key, runtimeSpec) == true
        or false
    if (hasPortrait or box._runtimeDefensivePortraitPositionOnly) and mode ~= "RIGHT" then mode = "LEFT" end
    local pSize = (hasPortrait or box._runtimeDefensivePortraitPositionOnly)
        and (tonumber(runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.size)
            or tonumber(PortraitStyleGet(key, "portraitSizeOverride", 0)) or 0)
        or 0
    if pSize <= 0 then pSize = max(22, h - 4) end
    -- Placement/geometry mirrors of the live spec. Parked on the box because
    -- Refresh already sits at the Lua 5.1 ceiling of 200 locals per function.
    box._runtimePortraitPlacement = (runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.placement)
        or PortraitStyleGet(key, "portraitPlacement", "ATTACHED") or "ATTACHED"
    box._runtimePortraitPoint = (runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.point)
        or PortraitStyleGet(key, "portraitDetachedPoint", "RIGHT") or "RIGHT"
    box._runtimePortraitRelPoint = (runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.relPoint)
        or PortraitStyleGet(key, "portraitDetachedTo", "LEFT") or "LEFT"
    box._runtimePortraitOverlayAlign = (runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.overlayAlign)
        or PortraitStyleGet(key, "portraitOverlayAlign", "LEFT") or "LEFT"
    box._runtimePortraitAlpha = tonumber(runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.alpha)
        or ((tonumber(PortraitStyleGet(key, "portraitAlpha", 100)) or 100) / 100)
    box._runtimePortraitW = tonumber(runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.width)
        or (tonumber(PortraitStyleGet(key, "portraitWidth", 0)) or 0)
    box._runtimePortraitH = tonumber(runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.height)
        or (tonumber(PortraitStyleGet(key, "portraitHeight", 0)) or 0)
    if box._runtimePortraitW <= 0 then box._runtimePortraitW = pSize end
    if box._runtimePortraitH <= 0 then box._runtimePortraitH = pSize end
    -- Auto size (Size override = 0) is resolved by the live Portrait element.
    -- Edit Mode displays that applied holder, so consume the same final geometry
    -- instead of letting Menu2 maintain a second approximation of the auto path.
    local runtimeSizeMode = runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.sizeMode
    if runtimeSizeMode == "SEPARATE"
        or (tonumber(PortraitStyleGet(key, "portraitSizeOverride", 0)) or 0) <= 0
    then
        box._runtimeAppliedPortraitW, box._runtimeAppliedPortraitH = R.RuntimeAppliedPortraitSizeForPreviewKey(key)
        if tonumber(box._runtimeAppliedPortraitW) and box._runtimeAppliedPortraitW > 0 then
            box._runtimePortraitW = box._runtimeAppliedPortraitW
        end
        if tonumber(box._runtimeAppliedPortraitH) and box._runtimeAppliedPortraitH > 0 then
            box._runtimePortraitH = box._runtimeAppliedPortraitH
        end
    else
        box._runtimeAppliedPortraitW, box._runtimeAppliedPortraitH = nil, nil
    end
    box._runtimePortraitBorderStyle = (runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.border and runtimeSpec.portrait.border.style) or PortraitStyleGet(key, "portraitBorderStyle", "NONE") or "NONE"
    box._runtimePortraitBorderThickness = 0
    box._runtimePortraitBorderFill = false
    if hasPortrait and box._runtimePortraitBorderStyle ~= "NONE" then
        box._runtimePortraitBorderThickness = max(1, tonumber(runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.border and runtimeSpec.portrait.border.thickness) or tonumber(PortraitStyleGet(key, "portraitBorderThickness", 2)) or 2)
        box._runtimePortraitBorderFill = (runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.border and runtimeSpec.portrait.border.fill == true) or (not (runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.border) and PortraitStyleGet(key, "portraitFillBorder", false) == true)
    end
    local castEnabled = runtimeSpec and runtimeSpec.castbar and runtimeSpec.castbar.enabled == true
    if not (runtimeSpec and runtimeSpec.castbar) then castEnabled = CastbarEnabled(key, g) end
    if box._msuf2ColorPainterForceCastbar == true then castEnabled = true end
    local castW, castBarH = ReadCastbarSize(key, g, w, key == "boss" and 12 or 18)
    local castXKey, castYKey, castDefX, castDefY = CastbarOffsetFields(key)
    local castOffsetX = castXKey and tonumber(g[castXKey]) or nil
    local castOffsetY = castYKey and tonumber(g[castYKey]) or nil
    if castOffsetX == nil then castOffsetX = tonumber(castDefX) or 0 end
    if castOffsetY == nil then castOffsetY = tonumber(castDefY) or 0 end
    local castDetached = castEnabled and CastbarDetached(key, g)
    local castPreviewVisible = castEnabled and PreviewLayerWanted(box, "castbar")
    -- Kept on the box instead of in locals: Refresh already sits at the Lua 5.1
    -- ceiling of 200 locals per function, so two more would fail to compile.
    box._detachedCastProjectedX, box._detachedCastProjectedY = nil, nil
    if castDetached and type(R.DetachedCastbarOffsetForPreviewKey) == "function" then
        box._detachedCastProjectedX, box._detachedCastProjectedY = R.DetachedCastbarOffsetForPreviewKey(key)
        if tonumber(box._detachedCastProjectedX) and tonumber(box._detachedCastProjectedY) then
            castOffsetX, castOffsetY = box._detachedCastProjectedX, box._detachedCastProjectedY
        end
    end
    box._bossBorderInset = 0
    if key == "boss"
        and runtimeSpec and runtimeSpec.border
        and runtimeSpec.border.enabled == true
    then
        box._bossBorderInset = max(1, floor((tonumber(runtimeSpec.border.thickness) or 1) + 0.5))
    end
    box._bossCastbarGap = 3
    local bars = _G.MSUF_DB and _G.MSUF_DB.bars or {}
    local classPowerPreviewSpec
    if key == "player" then
        classPowerPreviewSpec = MSUF.MSUF2 or _G.MSUF2 or MenuState
        if classPowerPreviewSpec.activeKey == "classpower" and type(classPowerPreviewSpec.GetClassPowerPreviewSpec) == "function" then
            classPowerPreviewSpec = classPowerPreviewSpec.GetClassPowerPreviewSpec()
        else
            classPowerPreviewSpec = nil
        end
    end
    if classPowerPreviewSpec then
        local previewClass = type(MenuState.GetClassPowerPreviewClassToken) == "function" and MenuState.GetClassPowerPreviewClassToken() or nil
        previewClass = previewClass or classPowerPreviewSpec.classToken or classPowerPreviewSpec.class
        if previewClass and data.class ~= previewClass then
            local copy = {}
            for k, v in pairs(data) do copy[k] = v end
            copy.class = tostring(previewClass):upper()
            data = copy
        end
    end
    local powerAllowed = runtimePower and runtimePower.enabled == true
    if runtimePower == nil then powerAllowed = D.ReadPowerBarEnabled(conf, key) end
    local detachedPower = CanDetachPowerBarKey(key) and powerAllowed and ((runtimePower and runtimePower.detached == true) or (runtimePower == nil and conf.powerBarDetached == true))
    box._runtimePowerEmbedded = powerAllowed and not detachedPower and (
        (runtimePower and runtimePower.embed ~= false)
        or (runtimePower == nil and conf.embedPowerBarIntoHealth == true)
        or (runtimePower == nil and conf.embedPowerBarIntoHealth == nil and bars.embedPowerBarIntoHealth ~= false)
    ) or false
    box._runtimePowerAttached = powerAllowed and not detachedPower and box._runtimePowerEmbedded ~= true
    box._runtimeHealthPowerInset = box._runtimePowerEmbedded == true
        and max(0, tonumber(runtimePower and runtimePower.height) or tonumber(ReadPowerBarHeight(conf)) or 0)
        or 0
    local classPowerOn = key == "player" and runtimeClassPower and runtimeClassPower.enabled == true or false
    if key == "player" and runtimeClassPower == nil then classPowerOn = bars.showClassPower ~= false end
    if key == "player" and classPowerPreviewSpec then classPowerOn = bars.showClassPower ~= false and classPowerPreviewSpec.enabled ~= false and classPowerPreviewSpec.mode ~= "none" end
    local powerFrac = tonumber(data.power) or 1
    if not detachedPower and key ~= "player" and data.live ~= true then powerFrac = 1 end
    if powerFrac < 0 then powerFrac = 0 elseif powerFrac > 1 then powerFrac = 1 end
    local animState = UnitPreviewAnimationState(box, 1, key)
    local animHp = animState and tonumber(animState.hpPct)
    local animPower = animState and tonumber(animState.powerPct)
    if animHp then
        if animHp < 0 then animHp = 0 elseif animHp > 1 then animHp = 1 end
        if animPower == nil then animPower = powerFrac end
        if animPower < 0 then animPower = 0 elseif animPower > 1 then animPower = 1 end
        powerFrac = animPower
        data = CopyPreviewAnimationData(box, data, animHp, powerFrac)
    end
    data = TextureLayerPreviewData(conf, key, data)
    local cpH = classPowerOn and (tonumber(bars.classPowerHeight) or 4) or 0
    if cpH < 2 then cpH = 2 elseif cpH > 30 then cpH = 30 end
    local classPowerSegCount = PreviewClassPowerSegmentCount(classPowerPreviewSpec, 10)
    box._runtimeClassPowerW = classPowerOn and PreviewClassPowerWidth(bars, w, cpH, classPowerSegCount) or 0
    box._runtimeClassPowerSecondarySpec = classPowerPreviewSpec and classPowerPreviewSpec.secondaryTimer
    box._runtimeClassPowerSecondaryOn = classPowerOn
        and type(box._runtimeClassPowerSecondarySpec) == "table"
        and bars.showEbonMight ~= false
    box._runtimeClassPowerSecondaryH = box._runtimeClassPowerSecondaryOn
        and PreviewSecondaryClassTimerHeight(runtimePower, conf) or 0
    box._runtimeAugCompositePreview = box._runtimeClassPowerSecondaryOn == true
        and classPowerPreviewSpec and classPowerPreviewSpec.key == "evoker_augmentation_ebon" or false
    if box._runtimeAugCompositePreview == true then
        -- Runtime keeps the ordinary Player Power StatusBar as an invisible
        -- geometry carrier even when the user disabled its Mana surface.  The
        -- composite must therefore keep following detached/embed settings;
        -- only the ordinary Power visuals and events disappear.
        detachedPower = CanDetachPowerBarKey(key) and (
            (runtimePower and runtimePower.detached == true)
            or (runtimePower == nil and conf.powerBarDetached == true)
        )
        box._runtimePowerEmbedded = not detachedPower and (
            (runtimePower and runtimePower.embed ~= false)
            or (runtimePower == nil and conf.embedPowerBarIntoHealth == true)
            or (runtimePower == nil and conf.embedPowerBarIntoHealth == nil and bars.embedPowerBarIntoHealth ~= false)
        ) or false
        box._runtimePowerAttached = not detachedPower and box._runtimePowerEmbedded ~= true
        box._runtimeHealthPowerInset = box._runtimePowerEmbedded == true
            and (cpH + 2 + box._runtimeClassPowerSecondaryH) or 0
    end
    box._runtimeDetachedPowerSyncClass = key == "player" and ((runtimePower and runtimePower.detachedSyncClass == true) or (runtimePower == nil and conf.detachedPowerBarSyncClassPower ~= false)) or false
    box._runtimeDetachedPowerX = tonumber(runtimePower and runtimePower.detachedX) or tonumber(conf.detachedPowerBarOffsetX) or 0
    box._runtimeDetachedPowerY = tonumber(runtimePower and runtimePower.detachedY) or tonumber(conf.detachedPowerBarOffsetY) or -4
    box._runtimeDetachedPowerAnchorMode = tostring((runtimePower and runtimePower.detachedAnchorMode)
        or conf.detachedPowerBarAnchorMode or "CENTER"):upper()
    if box._runtimeAugCompositePreview == true then
        -- LayoutDetached rounds configured offsets before anchoring the live
        -- carrier; keep imported fractional profile values equally stable.
        box._runtimeDetachedPowerX = floor(box._runtimeDetachedPowerX + 0.5)
        box._runtimeDetachedPowerY = floor(box._runtimeDetachedPowerY + 0.5)
    end
    box._runtimeDetachedPowerAnchorClass = key == "player" and ((runtimePower and runtimePower.detachedAnchorClass == true) or (runtimePower == nil and conf.detachedPowerBarAnchorToClassPower == true))
    box._runtimeDetachedPowerTextOnBar = (runtimePower and runtimePower.textOnDetached == true) or (runtimePower == nil and conf.detachedPowerBarTextOnBar == true)
    box._runtimeDetachedPowerShape = key == "player"
        and ResolvePreviewPowerShape((runtimePower and runtimePower.shape) or conf.detachedPowerBarShape or "FOLLOW_CLASS", bars.classPowerShape)
        or "BAR"
    local resolveDetachedPowerWidth = CPPreview.ResolveDetachedPowerWidth
    if detachedPower and type(resolveDetachedPowerWidth) == "function" then
        local liveFrame, livePower
        if box._runtimeAugCompositePreview ~= true then
            liveFrame = PreviewLiveFrame(key)
            livePower = runtimePower
        end
        box._runtimeDetachedPowerW = resolveDetachedPowerWidth({
            -- The live replacement resolver deliberately avoids ClassPower as
            -- both width and anchor input: ClassPower itself consumes this
            -- carrier.  Avoid the preview helper's live/class shortcuts too.
            liveFrame = liveFrame,
            livePower = livePower,
            shape = box._runtimeAugCompositePreview == true and "BAR" or box._runtimeDetachedPowerShape,
            orbSize = (runtimePower and runtimePower.orbSize) or conf.detachedPowerOrbSize,
            syncClass = box._runtimeAugCompositePreview ~= true and box._runtimeDetachedPowerSyncClass,
            classWidth = box._runtimeAugCompositePreview ~= true and classPowerOn and box._runtimeClassPowerW or nil,
            classFallbackWidth = box._runtimeAugCompositePreview ~= true
                and ((runtimePower and runtimePower.detachedClassWidth) or (w - 4)) or nil,
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
    if box._runtimeAugCompositePreview == true then
        box._runtimeClassPowerW = detachedPower and box._runtimeDetachedPowerW or w
    end
    local detachedH = detachedPower and (box._runtimeAugCompositePreview == true
        and (cpH + 2 + box._runtimeClassPowerSecondaryH)
        or (tonumber(runtimePower and runtimePower.detachedHeight) or tonumber(conf.detachedPowerBarHeight) or 6)) or 0
    if detachedH < 2 then detachedH = 2 elseif detachedH > 80 then detachedH = 80 end
    if detachedPower and box._runtimeAugCompositePreview ~= true and box._runtimeDetachedPowerShape == "ORB" then
        local orbSize = tonumber(runtimePower and runtimePower.orbSize) or tonumber(conf.detachedPowerOrbSize) or 54
        if orbSize < 20 then orbSize = 20 elseif orbSize > 160 then orbSize = 160 end
        box._runtimeDetachedPowerW = orbSize
        detachedH = orbSize
    end
    local detachedPowerManagedByClassPreview = detachedPower and box._runtimeAugCompositePreview ~= true
        and key == "player" and box._runtimeDetachedPowerAnchorClass == true
    local detachedPowerInUnitPreview = detachedPower and not detachedPowerManagedByClassPreview
    local wideW = w
    if classPowerOn and PreviewLayerWanted(box, "classPower") then wideW = max(wideW, box._runtimeClassPowerW or w) end
    if detachedPowerInUnitPreview and box._runtimeAugCompositePreview ~= true
        and PreviewLayerWanted(box, "power") then
        wideW = max(wideW, box._runtimeDetachedPowerW)
    end
    local minX, maxX, minY, maxY = 0, w, 0, h
    box._statusFootprintVisible = nil
    do
        local rawBaseTextSize = tonumber(g.fontSize) or 14
        local rawNameSize = tonumber(runtimeSpec and runtimeSpec.nameFontSize) or tonumber(conf.nameFontSize) or tonumber(g.nameFontSize) or rawBaseTextSize
        local rawHPSize = tonumber(runtimeSpec and runtimeSpec.healthFontSize) or tonumber(conf.hpFontSize) or tonumber(g.hpFontSize) or rawBaseTextSize
        local rawPowerSize = tonumber(runtimeSpec and runtimeSpec.powerFontSize) or tonumber(conf.powerFontSize) or tonumber(g.powerFontSize) or rawBaseTextSize
        local rawBaseline = tonumber(conf.fontOverride == true and conf.fontBaselineOffset) or tonumber(g.fontBaselineOffset) or 0
        if rawBaseline < -4 then rawBaseline = -4 elseif rawBaseline > 4 then rawBaseline = 4 end
        if PreviewLayerWanted(box, "nameText") and conf.showName ~= false and (not runtimeSpec or runtimeSpec.showName ~= false) then
            local label = R.ShortenPreviewName(data.name, key, conf)
            if runtimeText and runtimeText.directLayout == true then
                minX, maxX, minY, maxY = ExpandDirectPreviewTextRect(minX, maxX, minY, maxY, runtimeText, "directName", "CENTER", "CENTER", 0, 0, ApproxTextWidth(label, rawNameSize, 14), rawNameSize + 6, w, h)
            else
                local npt, nrel, nx = R.ResolveNameAnchor(conf.nameTextAnchor or "TOPLEFT", tonumber(conf.nameOffsetX) or 4)
                minX, maxX, minY, maxY = ExpandAnchoredRect(minX, maxX, minY, maxY, npt, nrel, nx, (tonumber(conf.nameOffsetY) or -4) + rawBaseline, ApproxTextWidth(label, rawNameSize, 14), rawNameSize + 6, w, h)
            end
        end
        local function NumField(primary, alias, generalPrimary, generalAlias, fallback)
            local v = conf[primary]
            if v == nil and alias then v = conf[alias] end
            if v == nil and generalPrimary then v = g[generalPrimary] end
            if v == nil and generalAlias then v = g[generalAlias] end
            return tonumber(v) or fallback or 0
        end
        local function TextOffsets(prefix, fallbackY, mirrorSlots)
            local baseX = NumField(prefix .. "OffsetX", prefix .. "TextOffsetX", prefix .. "OffsetX", prefix .. "TextOffsetX", -4)
            local baseY = NumField(prefix .. "OffsetY", prefix .. "TextOffsetY", prefix .. "OffsetY", prefix .. "TextOffsetY", fallbackY) + rawBaseline
            local function Slot(side, axis)
                return NumField(prefix .. "Text" .. side .. "Offset" .. axis, prefix .. side .. "Offset" .. axis, prefix .. "Text" .. side .. "Offset" .. axis, prefix .. side .. "Offset" .. axis, 0)
            end
            -- Reverse order renders the configured Right slot on the physical
            -- left side (and vice versa); its offsets follow the content.
            local leftSide = mirrorSlots and "Right" or "Left"
            local rightSide = mirrorSlots and "Left" or "Right"
            return {
                leftX = baseX + Slot(leftSide, "X"),
                leftY = baseY + Slot(leftSide, "Y"),
                centerX = baseX + Slot("Center", "X"),
                centerY = baseY + Slot("Center", "Y"),
                rightX = baseX + Slot(rightSide, "X"),
                rightY = baseY + Slot(rightSide, "Y"),
            }
        end
        local hpTextVisible = PreviewLayerWanted(box, "hpText") and conf.showHP ~= false and (not runtimeSpec or runtimeSpec.showHealthText ~= false)
        if hpTextVisible then
            local hpRev = R.TextScopeGet(key, "hpTextReverse", false) == true
            local leftSizeRuntimeKey = hpRev and "healthRightFontSize" or "healthLeftFontSize"
            local leftSizeDbKey = hpRev and "hpTextRightFontSize" or "hpTextLeftFontSize"
            local rightSizeRuntimeKey = hpRev and "healthLeftFontSize" or "healthRightFontSize"
            local rightSizeDbKey = hpRev and "hpTextLeftFontSize" or "hpTextRightFontSize"
            local o = TextOffsets("hp", -4, hpRev)
            if runtimeText and runtimeText.directLayout == true then
                minX, maxX, minY, maxY = ExpandDirectPreviewTextRect(minX, maxX, minY, maxY, runtimeText, hpRev and "directHealthRight" or "directHealthLeft", "LEFT", "LEFT", 4, 0, ApproxTextWidth("410K - 41%", ResolvePreviewTextSlotSize(runtimeText, conf, leftSizeRuntimeKey, leftSizeDbKey, rawHPSize), 10), ResolvePreviewTextSlotSize(runtimeText, conf, leftSizeRuntimeKey, leftSizeDbKey, rawHPSize) + 6, w, h)
                minX, maxX, minY, maxY = ExpandDirectPreviewTextRect(minX, maxX, minY, maxY, runtimeText, "directHealthCenter", "CENTER", "CENTER", 0, 0, ApproxTextWidth("410K - 41%", ResolvePreviewTextSlotSize(runtimeText, conf, "healthCenterFontSize", "hpTextCenterFontSize", rawHPSize), 10), ResolvePreviewTextSlotSize(runtimeText, conf, "healthCenterFontSize", "hpTextCenterFontSize", rawHPSize) + 6, w, h)
                minX, maxX, minY, maxY = ExpandDirectPreviewTextRect(minX, maxX, minY, maxY, runtimeText, hpRev and "directHealthLeft" or "directHealthRight", "RIGHT", "RIGHT", -4, 0, ApproxTextWidth("410K - 41%", ResolvePreviewTextSlotSize(runtimeText, conf, rightSizeRuntimeKey, rightSizeDbKey, rawHPSize), 10), ResolvePreviewTextSlotSize(runtimeText, conf, rightSizeRuntimeKey, rightSizeDbKey, rawHPSize) + 6, w, h)
            else
                minX, maxX, minY, maxY = ExpandAnchoredRect(minX, maxX, minY, maxY, "LEFT", "LEFT", 4 + o.leftX, o.leftY, ApproxTextWidth("410K - 41%", ResolvePreviewTextSlotSize(runtimeText, conf, leftSizeRuntimeKey, leftSizeDbKey, rawHPSize), 10), ResolvePreviewTextSlotSize(runtimeText, conf, leftSizeRuntimeKey, leftSizeDbKey, rawHPSize) + 6, w, h)
                minX, maxX, minY, maxY = ExpandAnchoredRect(minX, maxX, minY, maxY, "CENTER", "CENTER", o.centerX, o.centerY, ApproxTextWidth("410K - 41%", ResolvePreviewTextSlotSize(runtimeText, conf, "healthCenterFontSize", "hpTextCenterFontSize", rawHPSize), 10), ResolvePreviewTextSlotSize(runtimeText, conf, "healthCenterFontSize", "hpTextCenterFontSize", rawHPSize) + 6, w, h)
                minX, maxX, minY, maxY = ExpandAnchoredRect(minX, maxX, minY, maxY, "RIGHT", "RIGHT", -4 + o.rightX, o.rightY, ApproxTextWidth("410K - 41%", ResolvePreviewTextSlotSize(runtimeText, conf, rightSizeRuntimeKey, rightSizeDbKey, rawHPSize), 10), ResolvePreviewTextSlotSize(runtimeText, conf, rightSizeRuntimeKey, rightSizeDbKey, rawHPSize) + 6, w, h)
            end
        end
        local powerTextVisible = box._runtimeAugCompositePreview ~= true
            and PreviewLayerWanted(box, "powerText") and PreviewPowerTextShown(runtimeSpec, conf)
        if powerTextVisible then
            local o = TextOffsets("power", 4)
            if runtimeText and runtimeText.directLayout == true and not (detachedPowerInUnitPreview and box._runtimeDetachedPowerTextOnBar) then
                minX, maxX, minY, maxY = ExpandDirectPreviewTextRect(minX, maxX, minY, maxY, runtimeText, "directPowerLeft", "LEFT", "LEFT", 4, 0, ApproxTextWidth("240K", ResolvePreviewTextSlotSize(runtimeText, conf, "powerLeftFontSize", "powerTextLeftFontSize", rawPowerSize), 6), ResolvePreviewTextSlotSize(runtimeText, conf, "powerLeftFontSize", "powerTextLeftFontSize", rawPowerSize) + 6, w, h)
                minX, maxX, minY, maxY = ExpandDirectPreviewTextRect(minX, maxX, minY, maxY, runtimeText, "directPowerCenter", "CENTER", "CENTER", 0, 0, ApproxTextWidth("240K", ResolvePreviewTextSlotSize(runtimeText, conf, "powerCenterFontSize", "powerTextCenterFontSize", rawPowerSize), 6), ResolvePreviewTextSlotSize(runtimeText, conf, "powerCenterFontSize", "powerTextCenterFontSize", rawPowerSize) + 6, w, h)
                minX, maxX, minY, maxY = ExpandDirectPreviewTextRect(minX, maxX, minY, maxY, runtimeText, "directPowerRight", "RIGHT", "RIGHT", -4, 0, ApproxTextWidth("240K", ResolvePreviewTextSlotSize(runtimeText, conf, "powerRightFontSize", "powerTextRightFontSize", rawPowerSize), 6), ResolvePreviewTextSlotSize(runtimeText, conf, "powerRightFontSize", "powerTextRightFontSize", rawPowerSize) + 6, w, h)
            else
                minX, maxX, minY, maxY = ExpandAnchoredRect(minX, maxX, minY, maxY, "BOTTOMLEFT", "BOTTOMLEFT", 4 + o.leftX, o.leftY, ApproxTextWidth("240K", ResolvePreviewTextSlotSize(runtimeText, conf, "powerLeftFontSize", "powerTextLeftFontSize", rawPowerSize), 6), ResolvePreviewTextSlotSize(runtimeText, conf, "powerLeftFontSize", "powerTextLeftFontSize", rawPowerSize) + 6, w, h)
                minX, maxX, minY, maxY = ExpandAnchoredRect(minX, maxX, minY, maxY, "BOTTOM", "BOTTOM", o.centerX, o.centerY, ApproxTextWidth("240K", ResolvePreviewTextSlotSize(runtimeText, conf, "powerCenterFontSize", "powerTextCenterFontSize", rawPowerSize), 6), ResolvePreviewTextSlotSize(runtimeText, conf, "powerCenterFontSize", "powerTextCenterFontSize", rawPowerSize) + 6, w, h)
                minX, maxX, minY, maxY = ExpandAnchoredRect(minX, maxX, minY, maxY, "BOTTOMRIGHT", "BOTTOMRIGHT", -4 + o.rightX, o.rightY, ApproxTextWidth("240K", ResolvePreviewTextSlotSize(runtimeText, conf, "powerRightFontSize", "powerTextRightFontSize", rawPowerSize), 6), ResolvePreviewTextSlotSize(runtimeText, conf, "powerRightFontSize", "powerTextRightFontSize", rawPowerSize) + 6, w, h)
            end
        end
        if PreviewLayerWanted(box, "status") then
            for i = 1, #(D.STATUS_PREVIEW or {}) do
                local spec = D.STATUS_PREVIEW[i]
                local statusCfg = runtimeStatus and runtimeStatus[R.STATUS_RUNTIME_KEYS[spec.id]]
                local show
                if statusCfg then
                    show = statusCfg.enabled == true
                    if not show and spec.id == "statusPvp" and statusCfg.contextDisabled == true then show = true end
                else
                    local showVal = conf[spec.show]
                    if showVal == nil then showVal = g[spec.show] end
                    show = (showVal == nil) and (spec.defaultShow ~= false) or (showVal ~= false)
                end
                if spec.allowed and not spec.allowed(key) then show = false end
                if Preview.GetStatusPreviewMode() ~= "all" then
                    local selected = R.NormalizeStatusPreviewId(Preview.selectedStatusId)
                    if selected == "" then selected = "raidmarker" end
                    show = show and (spec.id == selected)
                end
                if show then
                    box._statusFootprintVisible = true
                    local isIdentityText = R.PreviewStatus.IsIdentityText and R.PreviewStatus.IsIdentityText(spec)
                    local rawSize = tonumber(statusCfg and statusCfg.size) or tonumber(conf[spec.size]) or tonumber(g[spec.size])
                    if rawSize == nil then
                        if isIdentityText then
                            rawSize = rawNameSize
                        elseif R.PreviewStatus.IsStatusTextState and R.PreviewStatus.IsStatusTextState(spec) then
                            rawSize = rawNameSize + 2
                        else
                            rawSize = spec.defaultSize
                        end
                    end
                    local rw, rh = rawSize, rawSize
                    if isIdentityText then
                        local previewText = R.PreviewStatus.IdentityPreviewText and R.PreviewStatus.IdentityPreviewText(spec, data) or spec.text
                        rw, rh = ApproxTextWidth(previewText, rawSize, 2), rawSize + 4
                    elseif R.PreviewStatus.IsStatusTextState and R.PreviewStatus.IsStatusTextState(spec) then
                        rw, rh = ApproxTextWidth(box._previewStatusText or "DEAD", rawSize, 4), rawSize + 4
                    end
                    local anchor = (statusCfg and statusCfg.anchor) or conf[spec.anchor] or R.ResolveStatusPreviewAnchor(spec, conf, g)
                    local sx = tonumber(statusCfg and statusCfg.x) or tonumber(conf[spec.x]) or tonumber(g[spec.x]) or spec.defaultX or 0
                    local sy = tonumber(statusCfg and statusCfg.y) or tonumber(conf[spec.y]) or tonumber(g[spec.y]) or spec.defaultY or 0
                    minX, maxX, minY, maxY = ExpandRuntimeAnchorRect(minX, maxX, minY, maxY, anchor, sx, sy, rw, rh, w, h)
                end
            end
        end
    end
    if (hasPortrait and PreviewLayerWanted(box, "portrait"))
        or (box._runtimeDefensivePortraitPositionOnly and PreviewLayerWanted(box, "auras")) then
        local poX = tonumber(runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.x) or tonumber(PortraitStyleGet(key, "portraitOffsetX", 0)) or 0
        local poY = tonumber(runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.y) or tonumber(PortraitStyleGet(key, "portraitOffsetY", 0)) or 0
        local left, bottom, pw, ph = R.PreviewPortraitRect(
            box._runtimePortraitPlacement,
            box._runtimePortraitPlacement == "ATTACHED" and (mode == "RIGHT" and "LEFT" or "RIGHT") or box._runtimePortraitPoint,
            box._runtimePortraitRelPoint, box._runtimePortraitOverlayAlign,
            w, h, box._runtimePortraitW, box._runtimePortraitH, poX, poY,
            box._runtimeHealthPowerInset)
        local grow = hasPortrait and (box._runtimePortraitBorderFill and 0 or box._runtimePortraitBorderThickness) or 0
        minX, maxX = min(minX, left - grow), max(maxX, left + pw + grow)
        minY, maxY = min(minY, bottom - grow), max(maxY, bottom + ph + grow)
    end
    if classPowerOn and PreviewLayerWanted(box, "classPower") then
        local cpW = box._runtimeClassPowerW or PreviewClassPowerWidth(bars, w, cpH, classPowerSegCount)
        local cx, cy
        if box._runtimeAugCompositePreview == true then
            if detachedPower then
                cx = box._runtimeDetachedPowerAnchorMode == "LEGACY_TOPLEFT"
                    and box._runtimeDetachedPowerX
                    or ((w - cpW) * 0.5 + box._runtimeDetachedPowerX)
                cy = box._runtimeDetachedPowerY - cpH
            elseif box._runtimePowerEmbedded == true then
                cx, cy = 0, 2 + box._runtimeClassPowerSecondaryH
            else
                cx, cy = 0, -1 - cpH
            end
        else
            cx = 2 + (tonumber(bars.classPowerOffsetX) or 0)
            cy = h + 4 + (tonumber(bars.classPowerOffsetY) or 0)
        end
        minX, maxX = min(minX, cx), max(maxX, cx + cpW)
        minY, maxY = min(minY, cy), max(maxY, cy + cpH)
        if box._runtimeClassPowerSecondaryOn == true then
            minY = min(minY, cy - 2 - box._runtimeClassPowerSecondaryH)
        end
    end
    if detachedPowerInUnitPreview and box._runtimeAugCompositePreview ~= true
        and PreviewLayerWanted(box, "power") then
        local dW = box._runtimeDetachedPowerW
        local dx = box._runtimeDetachedPowerX
        local dy = box._runtimeDetachedPowerY
        local dLeft = box._runtimeDetachedPowerAnchorMode == "LEGACY_TOPLEFT" and dx or ((w - dW) * 0.5 + dx)
        local dBottom = -detachedH + dy
        if box._runtimeDetachedPowerAnchorClass and classPowerOn then
            local cpW = box._runtimeClassPowerW or PreviewClassPowerWidth(bars, w, cpH, classPowerSegCount)
            local cx = 2 + (tonumber(bars.classPowerOffsetX) or 0)
            local cy = h + 4 + (tonumber(bars.classPowerOffsetY) or 0)
            dLeft = cx + (cpW - dW) * 0.5 + dx
            dBottom = cy - detachedH + dy
        end
        minX, maxX = min(minX, dLeft), max(maxX, dLeft + dW)
        minY, maxY = min(minY, dBottom), max(maxY, dBottom + detachedH)
    end
    if box._runtimePowerAttached == true and box._runtimeAugCompositePreview ~= true
        and PreviewLayerWanted(box, "power") then
        minY = min(minY, -((tonumber(runtimePower and runtimePower.height) or ReadPowerBarHeight(conf)) + 1))
    end
    if castEnabled and PreviewLayerWanted(box, "castbar") then
        local cLeft, cBottom
        if castDetached then
            cLeft = (w - castW) * 0.5 + castOffsetX
            cBottom = (h - castBarH) * 0.5 + castOffsetY
        elseif key == "player" then
            cLeft = (w - castW) * 0.5 + castOffsetX
            cBottom = h + castOffsetY
        elseif key == "boss" then
            cLeft = castOffsetX - box._bossBorderInset
            cBottom = castOffsetY - box._bossBorderInset - box._bossCastbarGap - castBarH
                + (box._runtimePowerEmbedded == true and (tonumber(runtimePower and runtimePower.height) or ReadPowerBarHeight(conf)) or 0)
        else
            cLeft = castOffsetX
            cBottom = h + castOffsetY
        end
        if castPreviewVisible then
            wideW = max(wideW, castW)
            local showTargetName = (key == "target" and g.castbarTargetShowTargetName == true)
                or (key == "focus" and g.castbarFocusShowTargetName == true)
                or (key == "boss" and g.showBossCastTargetName == true)
            local targetPadX = showTargetName and (abs(R.ReadCastbarNum(g, key, "TargetNameOffsetX", "bossCastTargetNameOffsetX", 0) or 0) + 96) or 0
            local targetPadY = showTargetName and (abs(R.ReadCastbarNum(g, key, "TargetNameOffsetY", "bossCastTargetNameOffsetY", 1) or 1) + 24) or 0
            local detailPadX = max(
                abs(R.ReadCastbarNum(g, key, "IconOffsetX", "bossCastIconOffsetX", 0) or 0) + abs(R.ReadCastbarNum(g, key, "IconSize", "bossCastIconSize", castBarH) or castBarH),
                abs(R.ReadCastbarNum(g, key, "TextOffsetX", "bossCastTextOffsetX", 0) or 0) + 80,
                abs(R.ReadCastbarNum(g, key, "TimeOffsetX", "bossCastTimeOffsetX", 0) or 0) + 46,
                targetPadX
            )
            local detailPadY = max(
                abs(R.ReadCastbarNum(g, key, "IconOffsetY", "bossCastIconOffsetY", 0) or 0) + abs(R.ReadCastbarNum(g, key, "IconSize", "bossCastIconSize", castBarH) or castBarH),
                abs(R.ReadCastbarNum(g, key, "TextOffsetY", "bossCastTextOffsetY", 0) or 0) + 24,
                abs(R.ReadCastbarNum(g, key, "TimeOffsetY", "bossCastTimeOffsetY", 0) or 0) + 24,
                targetPadY
            )
            minX, maxX = min(minX, cLeft - detailPadX), max(maxX, cLeft + castW + detailPadX)
            minY, maxY = min(minY, cBottom - detailPadY), max(maxY, cBottom + castBarH + detailPadY)
        end
    end
    local auraPreviewState = Auras and Auras.BuildState
        and Auras.BuildState(key, w, h, runtimeSpec, box._msuf2ColorPainterForceAuras == true)
    local auraFootprintState = Auras and Auras.HasVisibleLayer
        and Auras.HasVisibleLayer(auraPreviewState, box.layerVisibility) and auraPreviewState or nil
    if auraFootprintState and Auras.ExpandFootprint then minX, maxX, minY, maxY = Auras.ExpandFootprint(auraFootprintState, minX, maxX, minY, maxY, box.layerVisibility) end
    if Auras and type(Auras.DispelPreview) == "table" and type(Auras.DispelPreview.Availability) == "function" then
        box._previewDispelOverlayAvailable, box._previewDispelSymbolAvailable =
            Auras.DispelPreview.Availability(key, runtimeSpec)
    else
        box._previewDispelOverlayAvailable, box._previewDispelSymbolAvailable = false, false
    end
    if Auras and type(Auras.ExpandDispelFootprint) == "function" then
        minX, maxX, minY, maxY = Auras.ExpandDispelFootprint(runtimeSpec, w, h,
            minX, maxX, minY, maxY,
            box._previewDispelSymbolAvailable and PreviewLayerWanted(box, "dispelSymbol"))
    end
    if (classPowerOn and PreviewLayerWanted(box, "classPower")) or (detachedPowerInUnitPreview and PreviewLayerWanted(box, "power"))
        or castPreviewVisible or auraFootprintState or box._statusFootprintVisible
        or (box._previewDispelSymbolAvailable and PreviewLayerWanted(box, "dispelSymbol")) then
        minX, maxX = minX - 18, maxX + 18
        minY, maxY = minY - 18, maxY + 18
    end
    local centerX = ((minX + maxX) * 0.5) - (w * 0.5)
    local centerY = ((minY + maxY) * 0.5) - (h * 0.5)
    local runtimeScale = R.RuntimeVisualScaleForPreviewKey(key, canvas)
    box._mockCastRuntimeScale = R.RuntimeCastbarVisualScaleForPreviewKey(key, canvas)
    box._mockCastFrameScale = runtimeScale > 0 and (box._mockCastRuntimeScale / runtimeScale) or 1
    local autoScale = min(1.0, (cw - 60) / max(max(wideW, maxX - minX) * runtimeScale, 1), (ch - 42) / max(max(h, maxY - minY) * runtimeScale, 1))
    -- Fit mode must fit the complete configured footprint. Manual zoom keeps
    -- its usability floor, but forcing that same floor here clips status icons
    -- with large offsets instead of showing the true layout.
    if autoScale < 0.05 then autoScale = 0.05 end
    R.ResolveDefaultPreviewZoomLock(box, autoScale)
    local manualZoom = tonumber(box._manualZoom)
    local frozenScale = tonumber(box._dragFrozenScale)
    local previewScale = manualZoom and R.ClampPreviewZoom(manualZoom) or (frozenScale and R.ClampPreviewZoom(frozenScale) or autoScale)
    local scale = runtimeScale * previewScale
    box._mockRuntimeScale = runtimeScale
    box._mockAutoScale = autoScale
    box._mockScale = previewScale
    box._mockEffectiveScale = scale
    R.UpdatePreviewZoomControls(box)
    local function S(v) return floor((tonumber(v) or 0) * scale + 0.5) end
    local function StatusAnchorOffsets(spec, statusCfg)
        return (statusCfg and statusCfg.anchor) or conf[spec.anchor] or R.ResolveStatusPreviewAnchor(spec, conf, g),
            S(tonumber(statusCfg and statusCfg.x) or tonumber(conf[spec.x]) or tonumber(g[spec.x]) or spec.defaultX or 0),
            S(tonumber(statusCfg and statusCfg.y) or tonumber(conf[spec.y]) or tonumber(g[spec.y]) or spec.defaultY or 0)
    end
    -- Portrait size now comes from box._runtimePortraitW/H (independent axes), so
    -- the scaled square is no longer derived here.
    local sw, sh = S(w), S(h)
    local mockOffsetX, mockOffsetY = ResolvePreviewBodyOffsets(
        centerX,
        centerY,
        scale,
        manualZoom,
        tonumber(box._dragFrozenBaseOffsetX),
        tonumber(box._dragFrozenBaseOffsetY)
    )
    local panX, panY = tonumber(box._zoomPanX) or 0, tonumber(box._zoomPanY) or 0
    box._mockBaseOffsetX, box._mockBaseOffsetY = mockOffsetX, mockOffsetY
    box._detachedCastPreview = nil
    box._detachedCastBaseOffsetX, box._detachedCastBaseOffsetY = nil, nil
    local mock = box.mock
    local baseLevel = (canvas.GetFrameLevel and canvas:GetFrameLevel() or 0) + 2
    if mock.SetFrameLevel then mock:SetFrameLevel(baseLevel + 4) end
    -- Mirror the live hierarchy: the unit frame owns a health StatusBar one
    -- level above it; text/status and portrait levels are based on that bar.
    baseLevel = (mock.GetFrameLevel and mock:GetFrameLevel()) or (baseLevel + 4)
    if mock.healthBar and mock.healthBar.SetFrameLevel then mock.healthBar:SetFrameLevel(baseLevel + 1) end
    local ElementLevel = Layers.ElementLevel or function(layer, fallback, detail) return baseLevel + ClampPreviewLayer(layer, fallback) + (detail or 0) end
    if mock.classPower and mock.classPower.SetFrameLevel then mock.classPower:SetFrameLevel(ElementLevel(bars.classPowerFrameLevelOffset, 5, 0)) end
    if mock.classPower and mock.classPower.textOwner and mock.classPower.textOwner.SetFrameLevel then
        mock.classPower.textOwner:SetFrameLevel(PreviewClassTextLevel(mock.classPower.textOwner, bars))
    end
    if mock.detachedPower and mock.detachedPower.SetFrameLevel then mock.detachedPower:SetFrameLevel(ElementLevel(runtimePower and runtimePower.detachedLevel or conf.detachedPowerBarFrameLevelOffset, Layers.POWER_DETACHED_DEFAULT or 6, 0)) end
    local textBase = 0
    -- Portrait rides the shared 0..30 layer scale from the frame, so layer 0
    -- previews behind the bars exactly like the live element does.
    if mock.portrait and mock.portrait.SetFrameLevel then mock.portrait:SetFrameLevel(ElementLevel(runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.levelOffset or conf.portraitLevelOffset, (Layers.HEALTH_OFFSET or 1) + (Layers.PORTRAIT_OFFSET or 6), 0)) end
    if type(_G.MSUF_GetCastbarFrameLevelOffset) == "function" then
        box._runtimeCastbarLayer = _G.MSUF_GetCastbarFrameLevelOffset(key, g)
    else
        box._runtimeCastbarLayer = R.ReadCastbarNum(g, key, "FrameLevelOffset", "bossCastFrameLevelOffset", 6)
    end
    box._runtimeCastbarLayer = ClampPreviewLayer(box._runtimeCastbarLayer, 6)
    if mock.cast and mock.cast.SetFrameLevel then mock.cast:SetFrameLevel(ElementLevel(box._runtimeCastbarLayer, 6, 0)) end
    if mock.cast and mock.cast.icon and mock.cast.icon.SetFrameLevel then mock.cast.icon:SetFrameLevel(ElementLevel(box._runtimeCastbarLayer, 6, 7)) end
    if mock.textFrame and mock.textFrame.SetFrameLevel then mock.textFrame:SetFrameLevel(textBase) end
    if mock.nameLayer and mock.nameLayer.SetFrameLevel then mock.nameLayer:SetFrameLevel(ElementLevel(runtimeText and runtimeText.nameLayer or conf.nameTextLayer or g.nameTextLayer, 5, 8)) end
    if mock.raidGroupLayer and mock.raidGroupLayer.SetFrameLevel then mock.raidGroupLayer:SetFrameLevel(ElementLevel(runtimeStatus and runtimeStatus.raidGroup and runtimeStatus.raidGroup.layer or conf.raidGroupNameLayer or conf.nameTextLayer or g.raidGroupNameLayer or g.nameTextLayer, 5, 8)) end
    if mock.hpLayer and mock.hpLayer.SetFrameLevel then mock.hpLayer:SetFrameLevel(ElementLevel(runtimeText and runtimeText.healthLayer or conf.hpTextLayer or conf.textLayer or g.hpTextLayer or g.textLayer, 5, 8)) end
    if mock.powerLayer and mock.powerLayer.SetFrameLevel then mock.powerLayer:SetFrameLevel(ElementLevel(runtimeText and runtimeText.powerLayer or conf.powerTextLayer or g.powerTextLayer, 2, 8)) end
    if mock.bounds and mock.bounds.SetFrameLevel then mock.bounds:SetFrameLevel(ElementLevel(30, 30, 31) + 16) end
    mock.healthBar:SetStatusBarTexture((runtimeSpec and runtimeSpec.health and runtimeSpec.health.texture) or (runtimeSpec and runtimeSpec.texture) or (type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture()) or TEX_W8)
    SetTex(mock.power, (runtimePower and runtimePower.texture) or (runtimeSpec and runtimeSpec.texture) or (type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture()) or TEX_W8)
    SetTex(mock.hpBG, (runtimeSpec and runtimeSpec.health and runtimeSpec.health.backgroundTexture) or (runtimeSpec and runtimeSpec.backgroundTexture) or (type(_G.MSUF_GetBarBackgroundTexture) == "function" and _G.MSUF_GetBarBackgroundTexture()) or TEX_W8)
    SetTex(mock.powerBG, (runtimePower and runtimePower.backgroundTexture) or (runtimeSpec and runtimeSpec.backgroundTexture) or (type(_G.MSUF_GetBarBackgroundTexture) == "function" and _G.MSUF_GetBarBackgroundTexture()) or TEX_W8)
    local detachedPowerTexture = (runtimePower and runtimePower.texture) or (runtimeSpec and runtimeSpec.texture) or (type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture()) or TEX_W8
    local detachedPowerBgTexture = (runtimePower and runtimePower.backgroundTexture) or (runtimeSpec and runtimeSpec.backgroundTexture) or (type(_G.MSUF_GetBarBackgroundTexture) == "function" and _G.MSUF_GetBarBackgroundTexture()) or detachedPowerTexture
    SetTex(mock.detachedPower.fill, detachedPowerTexture)
    SetTex(mock.cast.fill, type(_G.MSUF_GetCastbarTexture) == "function" and _G.MSUF_GetCastbarTexture() or TEX_W8)
    mock:SetSize(sw, sh)
    ConfigureRuntimeScaledTextFrame(mock.textFrame, mock, w, h, scale)
    if mock.sizeTag then mock.sizeTag:SetText(format("%d x %d", w, h)) end
    mock:ClearAllPoints()
    mock:SetPoint("CENTER", canvas, "CENTER", mockOffsetX + panX, mockOffsetY + panY)
    local powerEnabled = runtimePower and runtimePower.enabled == true
    if runtimePower == nil then powerEnabled = D.ReadPowerBarEnabled(conf, key) end
    local powerOn = powerEnabled and not detachedPower and box._runtimeAugCompositePreview ~= true
    local powerH = powerOn and S((runtimePower and runtimePower.height) or ReadPowerBarHeight(conf)) or 0
    if powerOn and powerH < 2 then powerH = 2 end
    mock.healthBar:ClearAllPoints()
    mock.healthBar:SetPoint("TOPLEFT", mock, "TOPLEFT", 0, 0)
    mock.healthBar:SetPoint("BOTTOMRIGHT", mock, "BOTTOMRIGHT", 0, S(box._runtimeHealthPowerInset))
    mock.hpBG:ClearAllPoints()
    mock.hpBG:SetAllPoints(mock)
    local hpReverse = (runtimeSpec and runtimeSpec.health and runtimeSpec.health.reverse == true) or (not (runtimeSpec and runtimeSpec.health) and conf.reverseFillBars == true)
    local hpAreaW = max(1, sw)
    local hpFrac = max(0, min(1, tonumber(data.hp) or 0.6))
    -- Vertical fill (health.vertical / conf.verticalFillBars) grows the health
    -- texture along the frame height. Prediction and temp-max overlays are
    -- horizontal-only in this thumbnail, so they are hidden when vertical rather
    -- than mixing fill axes. The axis test is inlined (no new locals) because
    -- this Refresh function sits at Lua's 200 active-local limit.
    if (runtimeSpec and runtimeSpec.health and runtimeSpec.health.vertical == true) or (not (runtimeSpec and runtimeSpec.health) and conf.verticalFillBars == true) then
        if mock.healthBar.SetOrientation then mock.healthBar:SetOrientation("VERTICAL") end
        mock.tempMaxHealthBg:Hide()
        mock.tempMaxHealth:Hide()
    else
        if mock.healthBar.SetOrientation then mock.healthBar:SetOrientation("HORIZONTAL") end
        RenderTempMaxHealth(mock, runtimeSpec, conf, g, key, hpReverse, hpAreaW, SetTex)
    end
    if mock.healthBar.SetReverseFill then mock.healthBar:SetReverseFill(hpReverse) end
    if mock.healthBar.SetMinMaxValues then mock.healthBar:SetMinMaxValues(0, 1) end
    mock.healthBar:SetValue(hpFrac)
    -- Query after SetValue, exactly like Group Preview: the client owns this
    -- fill region and may bind it lazily when the StatusBar is initialized.
    mock.hp = mock.healthBar:GetStatusBarTexture()
    mock.healthFill = mock.hp
    if mock.hp and mock.hp.SetDrawLayer then mock.hp:SetDrawLayer("ARTWORK", 0) end
    local healPredMode = tonumber(runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.healAnchorMode) or R.PreviewResolveHealPredAnchorMode(conf, g)
    local absorbMode = tonumber(runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.absorbAnchorMode) or R.PreviewResolveAbsorbAnchorMode(conf, g)
    local healPredShown = runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.heal == true
    if not (runtimeSpec and runtimeSpec.prediction) then healPredShown = R.PreviewHealPredictionEnabled(conf, g) end
    local absorbShown = runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.absorb == true
    if not (runtimeSpec and runtimeSpec.prediction) then absorbShown = R.PreviewAbsorbBarEnabled(conf, g, key) end
    local healAbsorbShown = runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.healAbsorb == true
    if not (runtimeSpec and runtimeSpec.prediction) then
        local enabled = g and g.healAbsorbEnabled
        if conf and conf.hlOverride == true and conf.healAbsorbEnabled ~= nil then enabled = conf.healAbsorbEnabled end
        healAbsorbShown = enabled ~= false
        if _G.MSUF_ShouldShowAbsorbTextureTest and _G.MSUF_ShouldShowAbsorbTextureTest(nil, key, "healAbsorb") then
            healAbsorbShown = true
        end
    end
    -- Overlays are horizontal-only in this thumbnail; omit them on a vertical
    -- health bar so the preview never shows mismatched fill axes. Inline the
    -- axis test to avoid a new local (Refresh is at the 200 active-local limit).
    if (runtimeSpec and runtimeSpec.health and runtimeSpec.health.vertical == true) or (not (runtimeSpec and runtimeSpec.health) and conf.verticalFillBars == true) then
        healPredShown = false
        absorbShown = false
        healAbsorbShown = false
    end
    local healPredFrac = ((healPredMode == 3) and min(0.14, max(0.02, 1 - hpFrac))) or 0.14
    if healPredShown then
        local r = tonumber(runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.healR) or tonumber(g and g.healPredictionColorR) or 0
        local gg = tonumber(runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.healG) or tonumber(g and g.healPredictionColorG) or 1
        local b = tonumber(runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.healB) or tonumber(g and g.healPredictionColorB) or 0
        local a = tonumber(runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.healA) or tonumber(g and g.healPredictionColorA) or 0.45
        mock.healPred:SetVertexColor(r, gg, b, a)
        R.LayoutUnitPreviewOverlay(mock.healPred, mock.healthBar, mock.hp, healPredMode, healPredFrac, hpReverse, nil, hpAreaW)
    else
        mock.healPred:Hide()
    end
    if absorbShown then
        local r = tonumber(runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.absorbR) or tonumber(g and g.absorbBarColorR) or 1
        local gg = tonumber(runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.absorbG) or tonumber(g and g.absorbBarColorG) or 1
        local b = tonumber(runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.absorbB) or tonumber(g and g.absorbBarColorB) or 1
        local a = tonumber(runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.absorbA) or tonumber(g and g.absorbBarOpacity) or tonumber(g and g.absorbBarColorA) or 0.75
        mock.absorb:SetVertexColor(r, gg, b, a)
        local absorbAnchor = nil
        if healPredShown and mock.healPred:IsShown() and (healPredMode == 3 or healPredMode == 4) and (absorbMode == 3 or absorbMode == 4) then absorbAnchor = mock.healPred end
        R.LayoutUnitPreviewOverlay(mock.absorb, mock.healthBar, mock.hp, absorbMode, 0.10, hpReverse, absorbAnchor, hpAreaW)
    else
        mock.absorb:Hide()
    end
    if healAbsorbShown then
        local r = tonumber(runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.healAbsorbR) or tonumber(g and g.healAbsorbBarColorR) or 0.7
        local gg = tonumber(runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.healAbsorbG) or tonumber(g and g.healAbsorbBarColorG) or 0
        local b = tonumber(runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.healAbsorbB) or tonumber(g and g.healAbsorbBarColorB) or 0
        local a = tonumber(runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.healAbsorbA) or tonumber(g and g.healAbsorbBarOpacity) or tonumber(g and g.healAbsorbBarColorA) or 1
        mock.healAbsorb:ClearAllPoints()
        if hpReverse then
            mock.healAbsorb:SetPoint("TOPLEFT", mock.hp, "TOPLEFT", 0, 0)
            mock.healAbsorb:SetPoint("BOTTOMLEFT", mock.hp, "BOTTOMLEFT", 0, 0)
        else
            mock.healAbsorb:SetPoint("TOPRIGHT", mock.hp, "TOPRIGHT", 0, 0)
            mock.healAbsorb:SetPoint("BOTTOMRIGHT", mock.hp, "BOTTOMRIGHT", 0, 0)
        end
        mock.healAbsorb:SetWidth(max(1, min(mock.hp:GetWidth() or hpAreaW, hpAreaW * 0.07)))
        mock.healAbsorb:SetVertexColor(r, gg, b, a)
        mock.healAbsorb:Show()
    else
        mock.healAbsorb:Hide()
    end
    local hr, hg, hb
    if runtimeSpec and runtimeSpec.health
        and (runtimeSpec.health.mode == "dark" or runtimeSpec.health.mode == "unified" or runtimeSpec.health.mode == "custom") then
        hr, hg, hb = runtimeSpec.health.r, runtimeSpec.health.g, runtimeSpec.health.b
    end
    if not hr then hr, hg, hb = R.HealthColor(key, data) end
    local hbr, hbg, hbb, hba
    local healthBg = runtimeSpec and runtimeSpec.health and runtimeSpec.health.background
    if healthBg then
        hbr, hbg, hbb, hba = healthBg.r or hr, healthBg.g or hg, healthBg.b or hb, healthBg.a or 0.85
        if runtimeSpec.health.backgroundClassColor == true then
            hbr, hbg, hbb = R.ClassColor((data.isPlayer and data.class)
                or ((D.LiveUnitData and D.LiveUnitData("player") or {}).class)
                or (UNIT_DATA.player and UNIT_DATA.player.class))
        elseif runtimeSpec.health.backgroundMatchHealth == true then
            hbr, hbg, hbb = R.DarkMatchHPColor(hr, hg, hb)
        end
    else
        hbr, hbg, hbb, hba = R.HealthBackgroundColor(hr, hg, hb, data, conf)
    end
    -- Alpha follows the current menu value immediately. The compiled spec
    -- still owns the live texture/RGB mode, but may lag one debounced apply
    -- while a slider is being edited.
    hba = select(4, R.HealthBackgroundColor(hr, hg, hb, data, conf))
    -- Match the live background owner: color and configured opacity are one
    -- vertex-color operation, while the region alpha remains neutral.
    mock.hpBG:SetVertexColor(hbr, hbg, hbb, hba)
    mock.hpBG:SetAlpha(1)
    mock.healthBar:SetStatusBarColor(hr, hg, hb, 1)
    local healthFillAlpha = max(0, min(1, tonumber(conf and conf.hpBarAlpha)
        or tonumber(runtimeSpec and runtimeSpec.alpha and runtimeSpec.alpha.hpAlpha) or 1))
    if box._msuf2RangeFadePreviewLayerMode == "health" then
        healthFillAlpha = healthFillAlpha * max(0, min(1,
            tonumber(box._msuf2RangeFadePreviewAlpha) or 1))
    end
    mock.hp:SetAlpha(healthFillAlpha)
    if MSUF.UFBarTextCommon and MSUF.UFBarTextCommon.ApplyBarGradient then
        MSUF.UFBarTextCommon.ApplyBarGradient(mock, mock.healthBar,
            runtimeSpec and runtimeSpec.health and runtimeSpec.health.barGradient,
            "_msufPreviewHealthGradients")
    end
    RenderTextureLayerPreview(box, mock, conf, PreviewLayerWanted(box, "texLayer"), S, sw, baseLevel, SetTex, PlaceHandle,
        R, data, runtimeSpec and runtimeSpec.health)
    if powerOn then
        mock.powerBG:Show(); mock.power:Show()
        mock.powerBG:ClearAllPoints()
        if box._runtimePowerEmbedded == true then
            SetBottomSpan(mock.powerBG, mock)
        else
            mock.powerBG:SetPoint("TOPLEFT", mock, "BOTTOMLEFT", 0, -max(1, S(1)))
            mock.powerBG:SetPoint("TOPRIGHT", mock, "BOTTOMRIGHT", 0, -max(1, S(1)))
        end
        mock.powerBG:SetHeight(powerH)
        local pr, pg, pb = ResolvePreviewPowerColor(R, data, runtimePower)
        local pbr, pbg, pbb, pba
        local powerBg = runtimePower and runtimePower.background
        if powerBg then
            pbr, pbg, pbb, pba = powerBg.r or pr, powerBg.g or pg, powerBg.b or pb, powerBg.a or 0.85
        else
            pbr, pbg, pbb, pba = R.PowerBackgroundColor(pr, pg, pb, hr, hg, hb, conf)
        end
        pba = select(4, R.PowerBackgroundColor(pr, pg, pb, hr, hg, hb, conf))
        mock.powerBG:SetVertexColor(pbr, pbg, pbb, pba)
        mock.power:ClearAllPoints()
        SetLeftSpan(mock.power, mock.powerBG)
        mock.power:SetWidth(max(1, sw * powerFrac))
        mock.power:SetVertexColor(pr, pg, pb, 1)
    else
        mock.powerBG:Hide(); mock.power:Hide()
    end
    if MSUF.UFBarTextCommon and MSUF.UFBarTextCommon.ApplyBarGradientToTarget then
        MSUF.UFBarTextCommon.ApplyBarGradientToTarget(mock, mock, mock.power,
            powerOn and PreviewLayerWanted(box, "power")
                and runtimePower and runtimePower.barGradient or nil,
            "_msufPreviewPowerGradients")
    end
    local fr, fg, fb = R.FontColor()
    local pr, pg, pb = ResolvePreviewPowerColor(R, data, runtimePower)
    if classPowerOn then
        mock.classPower:Show()
        local cpW = box._runtimeClassPowerW or PreviewClassPowerWidth(bars, w, cpH, classPowerSegCount)
        mock.classPower:SetSize(S(cpW), max(2, S(cpH)))
        mock.classPower:ClearAllPoints()
        if box._runtimeAugCompositePreview == true then
            if detachedPower then
                if box._runtimeDetachedPowerAnchorMode == "LEGACY_TOPLEFT" then
                    mock.classPower:SetPoint("TOPLEFT", mock, "BOTTOMLEFT",
                        S(box._runtimeDetachedPowerX), S(box._runtimeDetachedPowerY))
                else
                    mock.classPower:SetPoint("TOP", mock, "BOTTOM",
                        S(box._runtimeDetachedPowerX), S(box._runtimeDetachedPowerY))
                end
            elseif box._runtimePowerEmbedded == true then
                mock.classPower:SetPoint("TOPLEFT", mock, "BOTTOMLEFT", 0,
                    S(cpH + 2 + box._runtimeClassPowerSecondaryH))
            else
                mock.classPower:SetPoint("TOPLEFT", mock, "BOTTOMLEFT", 0, S(-1))
            end
        else
            mock.classPower:SetPoint("BOTTOMLEFT", mock, "TOPLEFT",
                S(2 + (tonumber(bars.classPowerOffsetX) or 0)),
                S(4 + (tonumber(bars.classPowerOffsetY) or 0)))
        end
        local cp = box._msufClassPowerPreviewScratch
        if not cp then cp = {}; box._msufClassPowerPreviewScratch = cp end
        cp.preview = classPowerPreviewSpec
        cp.token = cp.preview and cp.preview.token
        cp.isRune = cp.preview and cp.preview.mode == "rune"
        cp.r, cp.g, cp.b = pr, pg, pb
        cp.animatedValue = animState and R.CPPreview.AnimatedValue and R.CPPreview.AnimatedValue(cp.preview, animState.elapsed) or nil
        if cp.token then cp.r, cp.g, cp.b = R.CPPreview.ResolveBaseColor(cp.preview, bars, pr, pg, pb) end
        cp.isFull = R.CPPreview.IsFull(cp.preview, cp.animatedValue)
        local _, fullR, fullG, fullB = R.CPPreview.ResolveFullColor(bars, cp.token, cp.r, cp.g, cp.b)
        cp.fullR, cp.fullG, cp.fullB = fullR, fullG, fullB
        cp.filledAlpha = tonumber(bars.classPowerFilledAlpha) or 0.95
        if cp.filledAlpha < 0 then cp.filledAlpha = 0 elseif cp.filledAlpha > 1 then cp.filledAlpha = 1 end
        cp.emptyAlpha = tonumber(bars.classPowerEmptyAlpha) or 0.28
        if cp.emptyAlpha < 0 then cp.emptyAlpha = 0 elseif cp.emptyAlpha > 1 then cp.emptyAlpha = 1 end
        cp.bgAlpha = tonumber(bars.classPowerBgAlpha) or 0.30
        if cp.bgAlpha < 0 then cp.bgAlpha = 0 elseif cp.bgAlpha > 1 then cp.bgAlpha = 1 end
        cp.shape = NormalizePreviewClassPowerShape(bars.classPowerShape)
        cp.shapeInfo = PREVIEW_CLASS_POWER_SHAPES[cp.shape]
        cp.rounded = cp.shapeInfo == nil and bars.roundedFramesEnabled == true
            and bars.roundedClassResources == true
        if mock.classPower.SetBackdropColor then
            cp.bgr, cp.bgg, cp.bgb = R.CPPreview.ColorOverride("classPowerBgColorOverrides", cp.token)
            mock.classPower:SetBackdropColor(cp.bgr or 0, cp.bgg or 0, cp.bgb or 0,
                (cp.shapeInfo or cp.rounded) and 0 or cp.bgAlpha)
            mock.classPower:SetBackdropBorderColor(0, 0, 0, (cp.shapeInfo or cp.rounded) and 0 or 1)
        end
        cp.segCount = floor(tonumber(cp.preview and cp.preview.segments) or 5)
        if cp.segCount < 1 then cp.segCount = 1 end
        if mock.classPower.segments and cp.segCount > #mock.classPower.segments then cp.segCount = #mock.classPower.segments end
        local previewW = S(cpW)
        local rawGap = cp.shapeInfo and (tonumber(bars.classPowerGap) or 0) or ((tonumber(bars.classPowerTickWidth) or 1) + (tonumber(bars.classPowerGap) or 0))
        local gap = max(0, S(rawGap))
        if cp.segCount > 1 then
            local maxGap = floor((previewW - cp.segCount) / (cp.segCount - 1))
            if maxGap < 0 then maxGap = 0 end
            if gap > maxGap then gap = maxGap end
        end
        local segSpace = previewW - (cp.segCount - 1) * gap
        if segSpace < cp.segCount then segSpace = cp.segCount end
        local slot = nil
        local startX = 0
        if cp.shapeInfo then
            slot = max(1, S(cpH))
            local maxSlot = floor((previewW - (cp.segCount - 1) * gap) / cp.segCount)
            if maxSlot < 1 then maxSlot = 1 end
            if slot > maxSlot then slot = maxSlot end
            segSpace = slot * cp.segCount
            local rowW = segSpace + (cp.segCount - 1) * gap
            local align = NormalizePreviewClassPowerShapeAlign(bars.classPowerShapeAlign)
            if align == "LEFT" then
                startX = 0
            elseif align == "RIGHT" then
                startX = floor(previewW - rowW + 0.5)
            else
                startX = floor((previewW - rowW) * 0.5 + 0.5)
            end
            if startX < 0 then startX = 0 end
            cp.rightInset = floor(previewW - rowW - startX + 0.5)
            if cp.rightInset < 0 then cp.rightInset = 0 end
        else
            cp.rightInset = 0
        end
        local xPos, prevBoundary = 0, 0
        cp.runeOrder = cp.isRune and R.CPPreview.BuildRuneOrder(cp, bars, cp.preview) or nil
        cp.runeShowTime = bars.runeShowTime ~= false
        if bars.runeShowTime == nil and bars.runeShowTimeText ~= nil then cp.runeShowTime = bars.runeShowTimeText == true end
        cp.runeTextSize = max(6, S((tonumber(bars.classPowerFontSize) or 16) - 2))
        cp.runeTextOffsetX = S(tonumber(bars.classPowerTextOffsetX) or 0)
        cp.runeTextOffsetY = S(tonumber(bars.classPowerTextOffsetY) or 0)
        cp.runeTextAlpha = tonumber(g.fontTextAlpha) or 1
        if cp.runeTextAlpha < 0.7 then cp.runeTextAlpha = 0.7 elseif cp.runeTextAlpha > 1 then cp.runeTextAlpha = 1 end
        for i = 1, #mock.classPower.segments do
            local seg = mock.classPower.segments[i]
            local segBg = mock.classPower.segmentBgs and mock.classPower.segmentBgs[i]
            local segEdge = mock.classPower.segmentEdges and mock.classPower.segmentEdges[i]
            local runeText = mock.classPower.runeTexts and mock.classPower.runeTexts[i]
            if i <= cp.segCount then
                local boundary, segW
                if cp.shapeInfo then
                    boundary = i * slot
                    segW = slot
                else
                    boundary = floor((segSpace * i) / cp.segCount)
                    segW = boundary - prevBoundary
                    if segW < 1 then segW = 1 end
                end
                seg:Show()
                seg:ClearAllPoints()
                cp.rune = cp.runeOrder and cp.runeOrder[i] or nil
                cp.fill = cp.rune and ((cp.rune.elapsed or 0) / (cp.rune.total or 1)) or R.CPPreview.FillForSegment(cp.preview, i, cp.animatedValue)
                cp.drawW = segW
                cp.mode = cp.preview and cp.preview.mode
                if (cp.mode == "continuous" or cp.mode == "timer_bar" or cp.mode == "stagger" or cp.mode == "aura_single" or cp.mode == "fractional") and cp.fill > 0 and cp.fill < 1 then
                    cp.drawW = max(1, floor(segW * cp.fill + 0.5))
                elseif cp.rune and cp.fill > 0 and cp.fill < 1 then
                    cp.drawW = max(1, floor(segW * cp.fill + 0.5))
                end
                local visualW = cp.shapeInfo and segW or cp.drawW
                seg:SetWidth(visualW)
                seg:SetHeight(max(2, S(cpH)))
                local anchorX = startX + xPos
                if bars.classPowerFillReverse == true then
                    anchorX = (cp.rightInset or 0) + xPos
                    SetRightSpan(seg, mock.classPower, -anchorX)
                else
                    SetLeftSpan(seg, mock.classPower, anchorX)
                end
                if segBg then
                    if cp.shapeInfo then
                        segBg:SetTexture(cp.shapeInfo.bg)
                        segBg:SetVertexColor(cp.bgr or 0, cp.bgg or 0, cp.bgb or 0, cp.bgAlpha)
                        segBg:ClearAllPoints()
                        if bars.classPowerFillReverse == true then
                            SetRightSpan(segBg, mock.classPower, -anchorX)
                        else
                            SetLeftSpan(segBg, mock.classPower, anchorX)
                        end
                        segBg:SetSize(segW, max(2, S(cpH)))
                        segBg:Show()
                    else
                        segBg:Hide()
                    end
                end
                if segEdge then segEdge:Hide() end
                cp.sr, cp.sg, cp.sb = cp.r, cp.g, cp.b
                cp.charged = R.CPPreview.IsCharged(cp.preview, bars, i)
                if cp.isFull then
                    cp.sr, cp.sg, cp.sb = cp.fullR, cp.fullG, cp.fullB
                elseif cp.charged then
                    cp.sr, cp.sg, cp.sb = R.CPPreview.ResolveColor("CHARGED", 0.60, 0.20, 0.80)
                else
                    cp.sr, cp.sg, cp.sb = R.CPPreview.ResolveSlotColor(bars, cp.token, i, cp.r, cp.g, cp.b)
                end
                if cp.preview and cp.preview.threshold and cp.fill > 0 and i > cp.preview.threshold then cp.sr, cp.sg, cp.sb = R.CPPreview.ResolveColor(cp.preview.thresholdToken, cp.sr, cp.sg, cp.sb) end
                cp.alpha = cp.fill > 0 and cp.filledAlpha or cp.emptyAlpha
                if cp.charged and cp.fill <= 0 then cp.alpha = max(cp.alpha, 0.55) end
                if cp.shapeInfo then
                    seg:SetTexture(cp.shapeInfo.fill)
                    if cp.fill > 0 and cp.fill < 1 then
                        seg:SetWidth(max(1, floor(segW * cp.fill + 0.5)))
                        if bars.classPowerFillReverse == true then
                            seg:SetTexCoord(1 - cp.fill, 1, 0, 1)
                        else
                            seg:SetTexCoord(0, cp.fill, 0, 1)
                        end
                    else
                        seg:SetTexCoord(0, 1, 0, 1)
                    end
                    seg:SetVertexColor(cp.sr, cp.sg, cp.sb, cp.fill > 0 and cp.alpha or 0)
                else
                    seg:SetTexCoord(0, 1, 0, 1)
                    seg:SetColorTexture(cp.sr, cp.sg, cp.sb, cp.alpha)
                end
                if runeText then
                    if cp.rune and cp.runeShowTime and not cp.rune.ready then
                        cp.runeText = R.CPPreview.FormatSeconds(cp.rune.remaining)
                        if cp.runeText ~= "" then
                            ApplyPreviewFont(runeText, cp.runeTextSize)
                            cp.tr, cp.tg, cp.tb = R.CPPreview.ResolveTextColor(fr or 1, fg or 1, fb or 1)
                            runeText:SetText(cp.runeText)
                            runeText:SetTextColor(cp.tr, cp.tg, cp.tb, cp.runeTextAlpha)
                            runeText:ClearAllPoints()
                            if bars.classPowerFillReverse == true then
                                runeText:SetPoint("CENTER", mock.classPower, "TOPRIGHT",
                                    -(anchorX + floor(segW * 0.5 + 0.5)) + cp.runeTextOffsetX,
                                    -floor(max(2, S(cpH)) * 0.5 + 0.5) + cp.runeTextOffsetY)
                            else
                                runeText:SetPoint("CENTER", mock.classPower, "TOPLEFT",
                                    anchorX + floor(segW * 0.5 + 0.5) + cp.runeTextOffsetX,
                                    -floor(max(2, S(cpH)) * 0.5 + 0.5) + cp.runeTextOffsetY)
                            end
                            runeText:Show()
                        else
                            runeText:SetText("")
                            runeText:Hide()
                        end
                    else
                        runeText:SetText("")
                        runeText:Hide()
                    end
                end
                xPos = xPos + segW + gap
                prevBoundary = boundary
            else
                seg:Hide()
                if segBg then segBg:Hide() end
                if segEdge then segEdge:Hide() end
                if runeText then runeText:Hide() end
            end
        end
        if PreviewHelpers.ApplyRoundedClassPowerSurface then
            local roundedApplied = PreviewHelpers.ApplyRoundedClassPowerSurface(mock.classPower, cp.rounded,
                mock.classPower.segments, nil, cp.segCount,
                ScalePreviewOutline(bars.classPowerOutline or 1, scale), UNIT_CP_ROUNDED_OPTS,
                cp.bgr or 0, cp.bgg or 0, cp.bgb or 0, cp.bgAlpha)
            if cp.rounded and not roundedApplied and mock.classPower.SetBackdropColor then
                mock.classPower:SetBackdropColor(cp.bgr or 0, cp.bgg or 0, cp.bgb or 0, cp.bgAlpha)
                mock.classPower:SetBackdropBorderColor(0, 0, 0, 1)
            end
        end
        local classTextOn = bars.classPowerShowText == true
            or (cp.preview and cp.preview.nativeDurationText == true)
        if classTextOn then
            local cpTextSize = S(tonumber(bars.classPowerFontSize) or 16)
            if cpTextSize < 7 then cpTextSize = 7 end
            ApplyPreviewFont(mock.classPower.text, cpTextSize)
            if cp.animatedValue ~= nil and R.CPPreview.TextForValue then
                mock.classPower.text:SetText(R.CPPreview.TextForValue(cp.preview, cp.animatedValue))
            else
                mock.classPower.text:SetText((cp.preview and cp.preview.previewText) or "3")
            end
            cp.tr, cp.tg, cp.tb = R.CPPreview.ResolveTextColor(fr or 1, fg or 1, fb or 1)
            mock.classPower.text:SetTextColor(cp.tr, cp.tg, cp.tb, cp.runeTextAlpha)
            mock.classPower.text:ClearAllPoints()
            mock.classPower.text:SetPoint("CENTER", mock.classPower, "CENTER", S(tonumber(bars.classPowerTextOffsetX) or 0), S(tonumber(bars.classPowerTextOffsetY) or 0))
            mock.classPower.text:Show()
            box.handleClassPowerText:SetSize(max(26, mock.classPower.text:GetStringWidth() + 10), max(18, mock.classPower.text:GetStringHeight() + 6))
            if not UnitPreviewText.PlaceHandleAroundRegions(box.handleClassPowerText, canvas, { mock.classPower.text }, 3) then PlaceHandle(box.handleClassPowerText, mock.classPower.text) end
        else
            mock.classPower.text:Hide()
            box.handleClassPowerText:Hide()
        end
        if box._runtimeClassPowerSecondaryOn == true then
            RenderPreviewSecondaryClassTimer(mock, box._runtimeClassPowerSecondarySpec,
                box._runtimeClassPowerSecondaryH, cpW, bars, R, animState, S,
                TEX_W8, ApplyPreviewFont, SetTex, fr, fg, fb, cp)
        else
            HidePreviewSecondaryClassTimer(mock)
        end
        box.handleClassPower:SetSize(max(36, S(cpW)), max(18, max(2, S(cpH)) + 8))
        PlaceHandle(box.handleClassPower, mock.classPower)
    else
        if PreviewHelpers.ApplyRoundedClassPowerSurface then
            PreviewHelpers.ApplyRoundedClassPowerSurface(mock.classPower, false,
                mock.classPower.segments, nil, 0, 0, UNIT_CP_ROUNDED_OPTS)
        end
        mock.classPower:Hide()
        for i = 1, #mock.classPower.segments do mock.classPower.segments[i]:Hide() end
        if mock.classPower.text then mock.classPower.text:Hide() end
        HidePreviewSecondaryClassTimer(mock)
        box.handleClassPower:Hide()
        box.handleClassPowerText:Hide()
    end
    box._runtimePowerOutline = 0
    local detachedPlayerOutline = detachedPower and key == "player"
        and ((runtimePower and runtimePower.detachedOutline) or bars.detachedPowerBarOutline)
        or nil
    if detachedPlayerOutline ~= nil then
        box._runtimePowerOutline = tonumber(detachedPlayerOutline) or 1
    elseif runtimePower ~= nil then
        if runtimePower.borderEnabled == true then box._runtimePowerOutline = tonumber(runtimePower.borderThickness) or 1 end
    elseif conf.powerBarBorderEnabled ~= nil then
        if conf.powerBarBorderEnabled == true then box._runtimePowerOutline = tonumber(conf.powerBarBorderThickness) or 1 end
    elseif bars.powerBarBorderEnabled == true then
        box._runtimePowerOutline = tonumber(bars.powerBarBorderThickness or bars.powerBarBorderSize) or 1
    end
    box._runtimePowerOutline = floor(box._runtimePowerOutline + 0.5)
    if box._runtimePowerOutline < 0 then box._runtimePowerOutline = 0 elseif box._runtimePowerOutline > 8 then box._runtimePowerOutline = 8 end
    -- Preview geometry is drawn at an explicit Fit/manual zoom instead of by
    -- scaling the live frame. Rectangular/rounded edge widths therefore need
    -- the same geometry scale as the detached bar itself. Keep the raw value
    -- separately: shaped edge textures use it as strength/alpha, not pixels.
    box._previewPowerOutline = ScalePreviewOutline(box._runtimePowerOutline, scale)
    mock._msufPreviewPowerBorderR = tonumber(runtimePower and runtimePower.borderR)
        or tonumber(conf.barOutlineColorR) or tonumber(g.barBorderR) or 0
    mock._msufPreviewPowerBorderG = tonumber(runtimePower and runtimePower.borderG)
        or tonumber(conf.barOutlineColorG) or tonumber(g.barBorderG) or 0
    mock._msufPreviewPowerBorderB = tonumber(runtimePower and runtimePower.borderB)
        or tonumber(conf.barOutlineColorB) or tonumber(g.barBorderB) or 0
    mock._msufPreviewPowerBorderA = tonumber(runtimePower and runtimePower.borderA)
        or tonumber(conf.barOutlineColorA) or tonumber(g.barBorderA) or 1
    box._runtimeDetachedRoundedPower = nil
    if detachedPowerInUnitPreview and box._runtimeAugCompositePreview ~= true then
        mock.detachedPower:Show()
        local dW = box._runtimeDetachedPowerW
        if dW < 20 then dW = 20 elseif dW > 800 then dW = 800 end
        mock.detachedPower:SetSize(S(dW), max(2, S(detachedH)))
        mock.detachedPower:ClearAllPoints()
        local dx = S(box._runtimeDetachedPowerX)
        local dy = S(box._runtimeDetachedPowerY)
        if box._runtimeDetachedPowerAnchorClass and classPowerOn and mock.classPower:IsShown() then
            mock.detachedPower:SetPoint("TOP", mock.classPower, "BOTTOM", dx, dy)
        elseif box._runtimeDetachedPowerAnchorMode == "LEGACY_TOPLEFT" then
            mock.detachedPower:SetPoint("TOPLEFT", mock, "BOTTOMLEFT", dx, dy)
        else
            mock.detachedPower:SetPoint("TOP", mock, "BOTTOM", dx, dy)
        end
        local powerShapeInfo = PREVIEW_POWER_SHAPES[box._runtimeDetachedPowerShape or "BAR"]
        box._runtimeDetachedRoundedPower = powerShapeInfo == nil and true or nil
        if mock.detachedPower.SetBackdropColor then
            if mock.detachedPower.SetBackdrop then mock.detachedPower:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = max(1, box._previewPowerOutline) }) end
            mock.detachedPower:SetBackdropColor(0, 0, 0, 0)
            mock.detachedPower:SetBackdropBorderColor(0, 0, 0, (not powerShapeInfo and box._runtimePowerOutline > 0) and 1 or 0)
        end
        mock.detachedPower.fill:ClearAllPoints()
        if powerShapeInfo then
            if mock.detachedPower.bg then
                mock.detachedPower.bg:SetTexture(powerShapeInfo.bg)
                mock.detachedPower.bg:SetVertexColor(pr, pg, pb, 0.28)
                mock.detachedPower.bg:ClearAllPoints()
                mock.detachedPower.bg:SetAllPoints(mock.detachedPower)
                mock.detachedPower.bg:Show()
            end
            mock.detachedPower.fill:SetTexture(powerShapeInfo.fill)
            mock.detachedPower.fill:SetVertexColor(pr, pg, pb, powerFrac > 0 and 1 or 0)
            if powerShapeInfo.axis == "VERTICAL" then
                local shapeW = S(dW)
                local shapeH = max(2, S(detachedH))
                if powerFrac > 0 and powerFrac < 1 then
                    mock.detachedPower.fill:SetTexCoord(0, 1, 1 - powerFrac, 1)
                    mock.detachedPower.fill:SetHeight(max(1, floor(shapeH * powerFrac + 0.5)))
                else
                    mock.detachedPower.fill:SetTexCoord(0, 1, 0, 1)
                    mock.detachedPower.fill:SetHeight(shapeH)
                end
                mock.detachedPower.fill:SetWidth(shapeW)
                SetBottomSpan(mock.detachedPower.fill, mock.detachedPower)
            else
                if powerFrac > 0 and powerFrac < 1 then
                    mock.detachedPower.fill:SetTexCoord(0, powerFrac, 0, 1)
                    mock.detachedPower.fill:SetWidth(max(1, floor(S(dW) * powerFrac + 0.5)))
                else
                    mock.detachedPower.fill:SetTexCoord(0, 1, 0, 1)
                    mock.detachedPower.fill:SetWidth(S(dW))
                end
                SetLeftSpan(mock.detachedPower.fill, mock.detachedPower)
            end
            if mock.detachedPower.edge then
                if box._runtimePowerOutline > 0 then
                    mock.detachedPower.edge:ClearAllPoints()
                    mock.detachedPower.edge:SetAllPoints(mock.detachedPower)
                    mock.detachedPower.edge:SetTexture(powerShapeInfo.edge)
                    mock.detachedPower.edge:SetVertexColor(0, 0, 0, PreviewShapeOutlineAlpha(box._runtimePowerOutline))
                    mock.detachedPower.edge:Show()
                else
                    mock.detachedPower.edge:Hide()
                end
            end
        else
            if mock.detachedPower.bg then
                local powerBg = runtimePower and runtimePower.background
                local pbr, pbg, pbb, pba
                if powerBg then
                    pbr, pbg, pbb, pba = powerBg.r or pr, powerBg.g or pg, powerBg.b or pb, powerBg.a or 0.85
                else
                    pbr, pbg, pbb, pba = R.PowerBackgroundColor(pr, pg, pb, hr, hg, hb, conf)
                end
                pba = select(4, R.PowerBackgroundColor(pr, pg, pb, hr, hg, hb, conf))
                SetTex(mock.detachedPower.bg, detachedPowerBgTexture)
                mock.detachedPower.bg:SetVertexColor(pbr, pbg, pbb, pba)
                mock.detachedPower.bg:ClearAllPoints()
                mock.detachedPower.bg:SetAllPoints(mock.detachedPower)
                mock.detachedPower.bg:Show()
            end
            if mock.detachedPower.edge then mock.detachedPower.edge:Hide() end
            SetTex(mock.detachedPower.fill, detachedPowerTexture)
            mock.detachedPower.fill:SetTexCoord(0, 1, 0, 1)
            mock.detachedPower.fill:SetVertexColor(pr, pg, pb, 1)
            mock.detachedPower.fill:SetWidth(max(1, S(dW) * powerFrac))
            SetLeftSpan(mock.detachedPower.fill, mock.detachedPower)
        end
        box.handleDetachedPower:SetSize(max(36, S(dW)), max(18, S(detachedH) + 8))
        PlaceHandle(box.handleDetachedPower, mock.detachedPower)
    else
        mock.detachedPower:Hide()
        box.handleDetachedPower:Hide()
    end
    if MSUF.UFBarTextCommon and MSUF.UFBarTextCommon.ApplyBarGradientToTarget then
        MSUF.UFBarTextCommon.ApplyBarGradientToTarget(mock, mock.detachedPower, mock.detachedPower.fill,
            detachedPowerInUnitPreview and box._runtimeAugCompositePreview ~= true
                and PreviewLayerWanted(box, "power")
                and box._runtimeDetachedRoundedPower == true
                and runtimePower and runtimePower.barGradient or nil,
            "_msufPreviewDetachedPowerGradients")
    end
    if Auras and type(Auras.LayoutDispelLayers) == "function" then
        Auras.LayoutDispelLayers(box, mock, runtimeSpec, S, baseLevel,
            box._previewDispelOverlayAvailable, box._previewDispelSymbolAvailable, w, h)
    end
    R.ApplyPreviewRounded(box, key, powerOn, R.PreviewRoundedOutlineThickness(key, conf, scale),
        box._runtimePowerEmbedded == true, box._previewPowerOutline,
        box._runtimeDetachedRoundedPower == true, box._previewPowerOutline)
    if R.ApplyPreviewFrameBorder then
        R.ApplyPreviewFrameBorder(box, mock._msufPreviewRoundedActive == true and nil or (runtimeSpec and runtimeSpec.border), scale)
    end
    if R.ApplyPreviewBoundsGuide then
        local guideEdge = 1
        if mock._msufPreviewRoundedActive == true then
            guideEdge = R.PreviewRoundedOutlineThickness(key, conf, scale)
        elseif runtimeSpec and runtimeSpec.border and runtimeSpec.border.enabled == true then
            guideEdge = floor(((tonumber(runtimeSpec.border.thickness) or 1) * scale) + 0.5)
        end
        R.ApplyPreviewBoundsGuide(box, guideEdge)
    end
    local fr, fg, fb = R.FontColor()
    local baseTextSize = tonumber(g.fontSize) or 14
    local nameRawSize = tonumber(runtimeSpec and runtimeSpec.nameFontSize) or tonumber(conf.nameFontSize) or tonumber(g.nameFontSize) or baseTextSize
    local hpSize = tonumber(runtimeSpec and runtimeSpec.healthFontSize) or tonumber(conf.hpFontSize) or tonumber(g.hpFontSize) or baseTextSize
    local pwrSize = tonumber(runtimeSpec and runtimeSpec.powerFontSize) or tonumber(conf.powerFontSize) or tonumber(g.powerFontSize) or baseTextSize
    box._fontPreviewTextAlpha = tonumber(runtimeSpec and runtimeSpec.textColor and runtimeSpec.textColor.a)
        or tonumber(conf.fontOverride == true and conf.fontTextAlpha)
        or tonumber(g.fontTextAlpha)
        or 1
    if box._fontPreviewTextAlpha < 0.7 then box._fontPreviewTextAlpha = 0.7 elseif box._fontPreviewTextAlpha > 1 then box._fontPreviewTextAlpha = 1 end
    box._fontPreviewBaselineOffset = tonumber(conf.fontOverride == true and conf.fontBaselineOffset) or tonumber(g.fontBaselineOffset) or 0
    if box._fontPreviewBaselineOffset < -4 then box._fontPreviewBaselineOffset = -4 elseif box._fontPreviewBaselineOffset > 4 then box._fontPreviewBaselineOffset = 4 end
    ApplyRuntimePreviewFont(runtimeSpec, ApplyPreviewFont, mock.nameText, nameRawSize, "name")
    ApplyRuntimePreviewFont(runtimeSpec, ApplyPreviewFont, mock.raidGroupNameText, nameRawSize, "name")
    ApplyRuntimePreviewFont(runtimeSpec, ApplyPreviewFont, mock.totInlineSep, nameRawSize, "name")
    ApplyRuntimePreviewFont(runtimeSpec, ApplyPreviewFont, mock.totInlineText, nameRawSize, "name")
    -- Reverse order renders the configured Right slot on the physical left
    -- FontString (and vice versa); size and offsets follow the content, so
    -- swap the per-slot keys the physical sides read from.
    local hpRev = runtimeText and runtimeText.healthReverse == true
        or (not runtimeText and R.TextScopeGet(key, "hpTextReverse", false) == true)
    ApplyRuntimePreviewFont(runtimeSpec, ApplyPreviewFont, mock.hpTextLeft, ResolvePreviewTextSlotSize(runtimeText, conf, hpRev and "healthRightFontSize" or "healthLeftFontSize", hpRev and "hpTextRightFontSize" or "hpTextLeftFontSize", hpSize), "health")
    ApplyRuntimePreviewFont(runtimeSpec, ApplyPreviewFont, mock.hpTextCenter, ResolvePreviewTextSlotSize(runtimeText, conf, "healthCenterFontSize", "hpTextCenterFontSize", hpSize), "health")
    ApplyRuntimePreviewFont(runtimeSpec, ApplyPreviewFont, mock.hpText, ResolvePreviewTextSlotSize(runtimeText, conf, hpRev and "healthLeftFontSize" or "healthRightFontSize", hpRev and "hpTextLeftFontSize" or "hpTextRightFontSize", hpSize), "health")
    ApplyRuntimePreviewFont(runtimeSpec, ApplyPreviewFont, mock.hpTextPct, ResolvePreviewTextSlotSize(runtimeText, conf, hpRev and "healthLeftFontSize" or "healthRightFontSize", hpRev and "hpTextLeftFontSize" or "hpTextRightFontSize", hpSize), "health")
    ApplyRuntimePreviewFont(runtimeSpec, ApplyPreviewFont, mock.powerTextLeft, ResolvePreviewTextSlotSize(runtimeText, conf, "powerLeftFontSize", "powerTextLeftFontSize", pwrSize), "power")
    ApplyRuntimePreviewFont(runtimeSpec, ApplyPreviewFont, mock.powerTextCenter, ResolvePreviewTextSlotSize(runtimeText, conf, "powerCenterFontSize", "powerTextCenterFontSize", pwrSize), "power")
    ApplyRuntimePreviewFont(runtimeSpec, ApplyPreviewFont, mock.powerText, ResolvePreviewTextSlotSize(runtimeText, conf, "powerRightFontSize", "powerTextRightFontSize", pwrSize), "power")
    ApplyRuntimePreviewFont(runtimeSpec, ApplyPreviewFont, mock.powerTextPct, ResolvePreviewTextSlotSize(runtimeText, conf, "powerRightFontSize", "powerTextRightFontSize", pwrSize), "power")
    box._previewNameR, box._previewNameG, box._previewNameB = R.PreviewNameColor(key, data, fr, fg, fb)
    SetTextColorSet(box._previewNameR, box._previewNameG, box._previewNameB, box._fontPreviewTextAlpha, mock.nameText)
    SetTextColorSet(fr, fg, fb, box._fontPreviewTextAlpha, mock.raidGroupNameText)
    if runtimeText and runtimeText.directLayout == true then
        SetPreviewTextColor(mock.nameText, runtimeText.nameColor, box._fontPreviewTextAlpha)
    end
    mock.totInlineSep:SetTextColor(0.72, 0.76, 0.84, box._fontPreviewTextAlpha)
    mock.totInlineText:SetTextColor(fr, fg, fb, box._fontPreviewTextAlpha)
    local hpTextR, hpTextG, hpTextB = ResolvePreviewHealthTextColor(R, runtimeText, conf, g, data, fr, fg, fb)
    SetTextColorSet(hpTextR, hpTextG, hpTextB, box._fontPreviewTextAlpha, mock.hpTextLeft, mock.hpTextCenter, mock.hpText, mock.hpTextPct)
    if runtimeText and runtimeText.directLayout == true and runtimeText.healthColorByHealth ~= true and runtimeText.healthColorByClass ~= true then
        SetPreviewTextColor(mock.hpTextLeft, RuntimeHealthPhysicalSlotValue(runtimeText, "Left", "directHealth", "Color"), box._fontPreviewTextAlpha)
        SetPreviewTextColor(mock.hpTextCenter, runtimeText.directHealthCenterColor, box._fontPreviewTextAlpha)
        SetPreviewTextColor(mock.hpText, RuntimeHealthPhysicalSlotValue(runtimeText, "Right", "directHealth", "Color"), box._fontPreviewTextAlpha)
    end
    if (runtimeText and runtimeText.powerColorByType == true) or (not runtimeText and g.colorPowerTextByType == true) then
        local prt, pgt, pbt = R.PowerColor(data.powerToken)
        SetTextColorSet(prt, pgt, pbt, box._fontPreviewTextAlpha, mock.powerTextLeft, mock.powerTextCenter, mock.powerText, mock.powerTextPct)
    else
        SetTextColorSet(fr, fg, fb, box._fontPreviewTextAlpha, mock.powerTextLeft, mock.powerTextCenter, mock.powerText, mock.powerTextPct)
    end
    if runtimeText and runtimeText.directLayout == true and runtimeText.powerColorByType ~= true then
        SetPreviewTextColor(mock.powerTextLeft, runtimeText.directPowerLeftColor, box._fontPreviewTextAlpha)
        SetPreviewTextColor(mock.powerTextCenter, runtimeText.directPowerCenterColor, box._fontPreviewTextAlpha)
        SetPreviewTextColor(mock.powerText, runtimeText.directPowerRightColor, box._fontPreviewTextAlpha)
    end
    mock.nameText:SetText(R.ShortenPreviewName(data.name, key, conf))
    mock.raidGroupNameText:SetText(D.PreviewRaidGroupNameText(conf))
    -- Live snapshots carry the frame's exact values; the stylized pair only
    -- backs mock data. Animated refreshes strip hpCur/powerCur so texts follow
    -- the combat-preview fraction on the live max scale.
    local hpMax, pMax = tonumber(data.hpMax) or 1000000, tonumber(data.powerMax) or 240000
    local hpCur, pCur = tonumber(data.hpCur) or floor(hpMax * data.hp + 0.5), tonumber(data.powerCur) or floor(pMax * powerFrac + 0.5)
    local hpSlots = R.TextScopeHasSlots(key, "textLeft", "textCenter", "textRight")
    local hpLeftMode, hpCenterMode, hpRightMode
    if runtimeText then
        hpLeftMode = runtimeText.healthLeft or "NONE"
        hpCenterMode = runtimeText.healthCenter or "NONE"
        hpRightMode = runtimeText.healthRight or "CURPERCENT"
    elseif hpSlots then
        hpLeftMode = R.TextScopeSlotGet(key, "textLeft", "NONE", R.NormalizeHpMode)
        hpCenterMode = R.TextScopeSlotGet(key, "textCenter", "NONE", R.NormalizeHpMode)
        hpRightMode = R.TextScopeSlotGet(key, "textRight", "CURPERCENT", R.NormalizeHpMode)
    else
        hpLeftMode, hpCenterMode, hpRightMode = "NONE", "NONE", R.NormalizeHpMode(R.TextScopeGet(key, "hpTextMode", "CURPERCENT"))
    end
    local function TextSlotHidePercentSymbol(field)
        local value
        if runtimeText then
            if field == "hpTextLeftHidePercentSymbol" then value = runtimeText.healthLeftHidePercentSymbol
            elseif field == "hpTextCenterHidePercentSymbol" then value = runtimeText.healthCenterHidePercentSymbol
            elseif field == "hpTextRightHidePercentSymbol" then value = runtimeText.healthRightHidePercentSymbol
            elseif field == "powerTextLeftHidePercentSymbol" then value = runtimeText.powerLeftHidePercentSymbol
            elseif field == "powerTextCenterHidePercentSymbol" then value = runtimeText.powerCenterHidePercentSymbol
            elseif field == "powerTextRightHidePercentSymbol" then value = runtimeText.powerRightHidePercentSymbol
            end
        else
            value = R.TextScopeGet(key, field, nil)
        end
        if value ~= nil then return value == true end
        return (runtimeText and runtimeText.hidePercentSymbol == true)
            or (not runtimeText and R.TextScopeGet(key, "hidePercentSymbol", false) == true)
    end
    local hpLeftHidePercent = TextSlotHidePercentSymbol("hpTextLeftHidePercentSymbol")
    local hpCenterHidePercent = TextSlotHidePercentSymbol("hpTextCenterHidePercentSymbol")
    local hpRightHidePercent = TextSlotHidePercentSymbol("hpTextRightHidePercentSymbol")
    if (runtimeText and runtimeText.healthReverse == true) or (not runtimeText and R.TextScopeGet(key, "hpTextReverse", false) == true) then
        local rev = {
            CURPERCENT = "PERCENTCUR", PERCENTCUR = "CURPERCENT", CURMAX = "MAXCUR", MAXCUR = "CURMAX",
            CURMAXPERCENT = "PERCENTMAXCUR", PERCENTMAXCUR = "CURMAXPERCENT",
            MAXPERCENT = "PERCENTMAX", PERCENTMAX = "MAXPERCENT", PERCENTCURMAX = "CURMAXPERCENT",
            CURPERCENTABSORB = "PERCENTCURABSORB", PERCENTCURABSORB = "CURPERCENTABSORB",
            CURMAXABSORB = "MAXCURABSORB", MAXCURABSORB = "CURMAXABSORB",
            CURMAXPERCENTABSORB = "PERCENTMAXCURABSORB", PERCENTMAXCURABSORB = "CURMAXPERCENTABSORB",
            MAXPERCENTABSORB = "PERCENTMAXABSORB", PERCENTMAXABSORB = "MAXPERCENTABSORB",
            PERCENTCURMAXABSORB = "CURMAXPERCENTABSORB",
        }
        hpLeftMode, hpRightMode = hpRightMode, hpLeftMode
        hpLeftMode = rev[hpLeftMode] or hpLeftMode
        hpCenterMode = rev[hpCenterMode] or hpCenterMode
        hpRightMode = rev[hpRightMode] or hpRightMode
        hpLeftHidePercent, hpRightHidePercent = hpRightHidePercent, hpLeftHidePercent
    end
    local hpPercentDecimals = runtimeText and tonumber(runtimeText.healthPercentDecimals) and runtimeText.healthPercentDecimals > 0
        or (not runtimeText and (R.TextScopeGet(key, "healthTextDecimals", false) == true or R.TextScopeGet(key, "hpTextDecimals", false) == true))
    local hpPctValue = hpPercentDecimals and format("%.1f", floor(data.hp * 1000 + 0.5) / 10)
        or floor(data.hp * 100 + 0.5)
    local hpSepRaw = runtimeText and runtimeText.healthDelimiter or R.TextScopeGet(key, "hpTextSeparator", "")
    mock.hpTextLeft:SetText(R.FormatMode(hpLeftMode, hpCur, hpMax, hpPctValue, hpSepRaw, false, hpLeftHidePercent,
        (runtimeText and runtimeText.healthShortNumbers == true) or (not runtimeText and R.TextScopeGet(key, "hpFullValueShort", R.TextScopeGet(key, "useShortNumbers", true)) == true),
        RuntimeHealthPhysicalSlotValue(runtimeText, "Left", "health", "AbsorbIcon") == true or (not runtimeText and R.TextScopeGet(key, R.TextScopeGet(key, "hpTextReverse", false) == true and "hpTextRightAbsorbIcon" or "hpTextLeftAbsorbIcon", R.TextScopeGet(key, "hpAbsorbIcon", false)) == true), data.absorb))
    mock.hpTextCenter:SetText(R.FormatMode(hpCenterMode, hpCur, hpMax, hpPctValue, hpSepRaw, false, hpCenterHidePercent,
        (runtimeText and runtimeText.healthShortNumbers == true) or (not runtimeText and R.TextScopeGet(key, "hpFullValueShort", R.TextScopeGet(key, "useShortNumbers", true)) == true),
        runtimeText and runtimeText.healthCenterAbsorbIcon == true or (not runtimeText and R.TextScopeGet(key, "hpTextCenterAbsorbIcon", R.TextScopeGet(key, "hpAbsorbIcon", false)) == true), data.absorb))
    mock.hpText:SetText(R.FormatMode(hpRightMode, hpCur, hpMax, hpPctValue, hpSepRaw, false, hpRightHidePercent,
        (runtimeText and runtimeText.healthShortNumbers == true) or (not runtimeText and R.TextScopeGet(key, "hpFullValueShort", R.TextScopeGet(key, "useShortNumbers", true)) == true),
        RuntimeHealthPhysicalSlotValue(runtimeText, "Right", "health", "AbsorbIcon") == true or (not runtimeText and R.TextScopeGet(key, R.TextScopeGet(key, "hpTextReverse", false) == true and "hpTextLeftAbsorbIcon" or "hpTextRightAbsorbIcon", R.TextScopeGet(key, "hpAbsorbIcon", false)) == true), data.absorb))
    mock.hpTextPct:SetText("")
    local powerSlots = R.TextScopeHasSlots(key, "powerTextLeft", "powerTextCenter", "powerTextRight")
    local powerLeftMode, powerCenterMode, powerRightMode
    if runtimeText then
        powerLeftMode = runtimeText.powerLeft or "NONE"
        powerCenterMode = runtimeText.powerCenter or "NONE"
        powerRightMode = runtimeText.powerRight or "CURPERCENT"
    elseif powerSlots then
        powerLeftMode = R.TextScopeSlotGet(key, "powerTextLeft", "NONE", R.NormalizePowerMode)
        powerCenterMode = R.TextScopeSlotGet(key, "powerTextCenter", "NONE", R.NormalizePowerMode)
        powerRightMode = R.TextScopeSlotGet(key, "powerTextRight", "CURPERCENT", R.NormalizePowerMode)
    else
        powerLeftMode, powerCenterMode, powerRightMode = "NONE", "NONE", R.NormalizePowerMode(R.TextScopeGet(key, "powerTextMode", "CURPERCENT"))
    end
    local powerPctValue = floor(powerFrac * 100 + 0.5)
    local powerSepRaw = runtimeText and runtimeText.powerDelimiter or R.TextScopeGet(key, "powerTextSeparator", R.TextScopeGet(key, "hpTextSeparator", ""))
    mock.powerTextLeft:SetText(R.FormatMode(powerLeftMode, pCur, pMax, powerPctValue, powerSepRaw, true, TextSlotHidePercentSymbol("powerTextLeftHidePercentSymbol"), (runtimeText and runtimeText.shortNumbers == true) or (not runtimeText and R.TextScopeGet(key, "useShortNumbers", true) == true)))
    mock.powerTextCenter:SetText(R.FormatMode(powerCenterMode, pCur, pMax, powerPctValue, powerSepRaw, true, TextSlotHidePercentSymbol("powerTextCenterHidePercentSymbol"), (runtimeText and runtimeText.shortNumbers == true) or (not runtimeText and R.TextScopeGet(key, "useShortNumbers", true) == true)))
    mock.powerText:SetText(R.FormatMode(powerRightMode, pCur, pMax, powerPctValue, powerSepRaw, true, TextSlotHidePercentSymbol("powerTextRightHidePercentSymbol"), (runtimeText and runtimeText.shortNumbers == true) or (not runtimeText and R.TextScopeGet(key, "useShortNumbers", true) == true)))
    mock.powerTextPct:SetText("")
    local showNamePreview = conf.showName ~= false
    if runtimeSpec then showNamePreview = runtimeSpec.showName ~= false end
    local hpTextOn = conf.showHP ~= false
    if runtimeSpec then hpTextOn = runtimeSpec.showHealthText ~= false end
    local powerTextOn = PreviewPowerTextShown(runtimeSpec, conf)
    if box._runtimeAugCompositePreview == true then powerTextOn = false end
    if detachedPowerManagedByClassPreview and box._runtimeDetachedPowerTextOnBar then powerTextOn = false end
    mock.nameText:SetShown(showNamePreview)
    local raidGroupCfg = runtimeStatus and runtimeStatus.raidGroup
    local raidGroupAnchor = (raidGroupCfg and raidGroupCfg.anchor) or D.NormalizeRaidGroupNameAnchor(conf.raidGroupNameAnchor)
    if not showNamePreview and (raidGroupAnchor == "NAMERIGHT" or raidGroupAnchor == "NAMELEFT") then raidGroupAnchor = "CENTER" end
    local showRaidGroupName = (runtimeStatus and runtimeStatus.raidGroup and runtimeStatus.raidGroup.enabled == true)
        or (not runtimeStatus and conf.showRaidGroupInName == true and D.PreviewRaidGroupNameAllowed(key))
    mock.raidGroupNameText:SetShown(showRaidGroupName)
    mock.totInlineSep:Hide()
    mock.totInlineText:Hide()
    mock.hpTextLeft:SetShown(hpTextOn and hpLeftMode ~= "NONE")
    mock.hpTextCenter:SetShown(hpTextOn and hpCenterMode ~= "NONE")
    mock.hpText:SetShown(hpTextOn and hpRightMode ~= "NONE")
    mock.hpTextPct:SetShown(false)
    mock.powerTextLeft:SetShown(powerTextOn and powerLeftMode ~= "NONE")
    mock.powerTextCenter:SetShown(powerTextOn and powerCenterMode ~= "NONE")
    mock.powerText:SetShown(powerTextOn and powerRightMode ~= "NONE")
    mock.powerTextPct:SetShown(false)
    mock.nameText:ClearAllPoints()
    if runtimeText and runtimeText.directLayout == true then
        PlaceDirectPreviewText(mock.nameText, mock.textFrame, runtimeText, "directName", "CENTER", "CENTER", 0, 0, "CENTER", RuntimeTextCoordinate)
    else
        PlaceRuntimePreviewName(mock.nameText, mock.textFrame, runtimeText, conf, box._fontPreviewBaselineOffset, R.ResolveNameAnchor)
    end
    mock.raidGroupNameText:ClearAllPoints()
    local raidGroupX = tonumber(raidGroupCfg and raidGroupCfg.x) or tonumber(conf.raidGroupNameOffsetX) or 3
    local raidGroupY = tonumber(raidGroupCfg and raidGroupCfg.y) or tonumber(conf.raidGroupNameOffsetY) or 0
    if raidGroupAnchor == "NAMERIGHT" then
        mock.raidGroupNameText:SetPoint("LEFT", mock.nameText, "RIGHT", raidGroupX, raidGroupY)
    elseif raidGroupAnchor == "NAMELEFT" then
        mock.raidGroupNameText:SetPoint("RIGHT", mock.nameText, "LEFT", raidGroupX, raidGroupY)
    else
        mock.raidGroupNameText:SetPoint(raidGroupAnchor, mock.textFrame, raidGroupAnchor, raidGroupX, raidGroupY)
    end
    mock.raidGroupNameText:SetJustifyH("LEFT")
    do
        local totConf = (_G.MSUF_DB and _G.MSUF_DB.targettarget) or {}
        local showInline = key == "target" and conf.showName ~= false and totConf.showToTInTargetName == true
        if showInline then
            local sep = R.ToTInlineSeparator(totConf.totInlineSeparator, totConf.totInlineCustomSeparator)
            local totData = (D.LiveUnitData and D.LiveUnitData("targettarget")) or UNIT_DATA.targettarget or { name = "Target" }
            local tr, tg, tb = R.PreviewNameColor("target", data, fr, fg, fb)
            local ir, ig, ib = R.PreviewToTInlineColor(totConf.totInlineColorMode, totData, tr, tg, tb, fr, fg, fb)
            mock.totInlineSep:SetText(sep ~= "" and sep or " ")
            mock.totInlineText:SetText(R.ShortenPreviewName(totData.name, "targettarget", conf))
            mock.totInlineText:SetTextColor(ir, ig, ib, box._fontPreviewTextAlpha)
            local inlineAnchor = (showRaidGroupName and raidGroupAnchor == "NAMERIGHT") and mock.raidGroupNameText or mock.nameText
            mock.totInlineSep:ClearAllPoints()
            mock.totInlineSep:SetPoint("LEFT", inlineAnchor, "RIGHT", 4, 0)
            mock.totInlineText:ClearAllPoints()
            mock.totInlineText:SetPoint("LEFT", mock.totInlineSep, "RIGHT", 4, 0)
            mock.totInlineSep:Show()
            mock.totInlineText:Show()
        end
    end
    local function PlacePreviewSlot(fs, parent, point, relPoint, x, y, justify)
        if not fs then return end
        fs:ClearAllPoints()
        fs:SetPoint(point, parent, relPoint, x, y)
        fs:SetJustifyH(justify)
    end
    local function NumField(primary, alias, generalPrimary, generalAlias, fallback)
        local v = conf[primary]
        if v == nil and alias then v = conf[alias] end
        if v == nil and generalPrimary then v = g[generalPrimary] end
        if v == nil and generalAlias then v = g[generalAlias] end
        return tonumber(v) or fallback or 0
    end
    local function TextOffsets(prefix, fallbackY, mirrorSlots)
        local runtimePrefix = prefix == "hp" and "health" or "power"
        local leftSide = mirrorSlots and "Right" or "Left"
        local rightSide = mirrorSlots and "Left" or "Right"
        if runtimeText then
            local leftX = tonumber(runtimeText[runtimePrefix .. leftSide .. "X"])
            local leftY = tonumber(runtimeText[runtimePrefix .. leftSide .. "Y"])
            local centerX = tonumber(runtimeText[runtimePrefix .. "CenterX"])
            local centerY = tonumber(runtimeText[runtimePrefix .. "CenterY"])
            local rightX = tonumber(runtimeText[runtimePrefix .. rightSide .. "X"])
            local rightY = tonumber(runtimeText[runtimePrefix .. rightSide .. "Y"])
            if leftX ~= nil and leftY ~= nil and centerX ~= nil and centerY ~= nil and rightX ~= nil and rightY ~= nil then
                return {
                    leftX = leftX, leftY = leftY,
                    centerX = centerX, centerY = centerY,
                    rightX = rightX, rightY = rightY,
                }
            end
        end
        local baseX = NumField(prefix .. "OffsetX", prefix .. "TextOffsetX", prefix .. "OffsetX", prefix .. "TextOffsetX", -4)
        local baseY = NumField(prefix .. "OffsetY", prefix .. "TextOffsetY", prefix .. "OffsetY", prefix .. "TextOffsetY", fallbackY) + box._fontPreviewBaselineOffset
        local function Slot(side, axis)
            return NumField(prefix .. "Text" .. side .. "Offset" .. axis, prefix .. side .. "Offset" .. axis, prefix .. "Text" .. side .. "Offset" .. axis, prefix .. side .. "Offset" .. axis, 0)
        end
        -- Reverse order: the mirrored physical sides read the other slot's offsets.
        return {
            leftX = baseX + Slot(leftSide, "X"),
            leftY = baseY + Slot(leftSide, "Y"),
            centerX = baseX + Slot("Center", "X"),
            centerY = baseY + Slot("Center", "Y"),
            rightX = baseX + Slot(rightSide, "X"),
            rightY = baseY + Slot(rightSide, "Y"),
        }
    end
    local function PlaceTextSet(left, center, right, pct, parent, lPoint, lRel, cPoint, cRel, rPoint, rRel, offsets, coordinate)
        coordinate = coordinate or RuntimeTextCoordinate
        PlacePreviewSlot(left, parent, lPoint, lRel, coordinate(4 + offsets.leftX), coordinate(offsets.leftY), "LEFT")
        PlacePreviewSlot(center, parent, cPoint, cRel, coordinate(offsets.centerX), coordinate(offsets.centerY), "CENTER")
        PlacePreviewSlot(right, parent, rPoint, rRel, coordinate(-4 + offsets.rightX), coordinate(offsets.rightY), "RIGHT")
        PlacePreviewSlot(pct, parent, rPoint, rRel, coordinate(-4 + offsets.rightX), coordinate(offsets.rightY), "RIGHT")
    end
    local hpOffsets = TextOffsets("hp", -4, hpRev)
    local powerOffsets = TextOffsets("power", 4)
    if runtimeText and runtimeText.directLayout == true then
        PlaceDirectPreviewText(mock.hpTextLeft, mock.textFrame, runtimeText, hpRev and "directHealthRight" or "directHealthLeft", "LEFT", "LEFT", 4, 0, "LEFT", RuntimeTextCoordinate)
        PlaceDirectPreviewText(mock.hpTextCenter, mock.textFrame, runtimeText, "directHealthCenter", "CENTER", "CENTER", 0, 0, "CENTER", RuntimeTextCoordinate)
        PlaceDirectPreviewText(mock.hpText, mock.textFrame, runtimeText, hpRev and "directHealthLeft" or "directHealthRight", "RIGHT", "RIGHT", -4, 0, "RIGHT", RuntimeTextCoordinate)
    else
        PlaceTextSet(mock.hpTextLeft, mock.hpTextCenter, mock.hpText, mock.hpTextPct, mock.textFrame, "TOPLEFT", "TOPLEFT", "TOP", "TOP", "TOPRIGHT", "TOPRIGHT", hpOffsets)
    end
    if detachedPowerInUnitPreview and box._runtimeDetachedPowerTextOnBar and mock.detachedPower:IsShown() then
        -- The FontStrings inherit the runtime scale from textFrame. Keep their
        -- offsets raw even though the detached bar geometry is canvas-scaled;
        -- scaling the offsets here would apply the preview scale twice.
        PlaceTextSet(mock.powerTextLeft, mock.powerTextCenter, mock.powerText, mock.powerTextPct, mock.detachedPower, "LEFT", "LEFT", "CENTER", "CENTER", "RIGHT", "RIGHT", powerOffsets)
    elseif runtimeText and runtimeText.directLayout == true then
        PlaceDirectPreviewText(mock.powerTextLeft, mock.textFrame, runtimeText, "directPowerLeft", "LEFT", "LEFT", 4, 0, "LEFT", RuntimeTextCoordinate)
        PlaceDirectPreviewText(mock.powerTextCenter, mock.textFrame, runtimeText, "directPowerCenter", "CENTER", "CENTER", 0, 0, "CENTER", RuntimeTextCoordinate)
        PlaceDirectPreviewText(mock.powerText, mock.textFrame, runtimeText, "directPowerRight", "RIGHT", "RIGHT", -4, 0, "RIGHT", RuntimeTextCoordinate)
    else
        PlaceTextSet(mock.powerTextLeft, mock.powerTextCenter, mock.powerText, mock.powerTextPct, mock.textFrame, "BOTTOMLEFT", "BOTTOMLEFT", "BOTTOM", "BOTTOM", "BOTTOMRIGHT", "BOTTOMRIGHT", powerOffsets)
    end
    if hasPortrait or box._runtimeDefensivePortraitPositionOnly then
        mock.portrait:Show()
        mock.portrait:SetSize(S(box._runtimePortraitW), S(box._runtimePortraitH))
        mock.portrait:SetAlpha(box._runtimePortraitAlpha or 1)
        mock.portrait:ClearAllPoints()
        if mock.portrait.border and mock.portrait.border.SetFrameLevel and mock.portrait.GetFrameLevel then mock.portrait.border:SetFrameLevel((mock.portrait:GetFrameLevel() or 1) + 1) end
        local ox = S(tonumber(runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.x) or tonumber(PortraitStyleGet(key, "portraitOffsetX", 0)) or 0)
        local oy = S(tonumber(runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.y) or tonumber(PortraitStyleGet(key, "portraitOffsetY", 0)) or 0)
        if box._runtimePortraitPlacement == "DETACHED" then
            mock.portrait:SetPoint(box._runtimePortraitPoint, mock, box._runtimePortraitRelPoint, ox, oy)
        elseif box._runtimePortraitPlacement == "OVERLAY" then
            if box._runtimePortraitOverlayAlign == "FULL" then
                mock.portrait:SetPoint("TOPLEFT", mock, "TOPLEFT", ox, -oy)
                mock.portrait:SetPoint("BOTTOMRIGHT", mock, "BOTTOMRIGHT", -ox,
                    S(box._runtimeHealthPowerInset) + oy)
            else
                mock.portrait:SetPoint(box._runtimePortraitOverlayAlign, mock, box._runtimePortraitOverlayAlign,
                    ox, oy + S(box._runtimeHealthPowerInset) * 0.5)
            end
        elseif mode == "RIGHT" then
            mock.portrait:SetPoint("LEFT", mock, "RIGHT", ox,
                oy + S(box._runtimeHealthPowerInset) * 0.5)
        else
            mock.portrait:SetPoint("RIGHT", mock, "LEFT", ox,
                oy + S(box._runtimeHealthPowerInset) * 0.5)
        end
        if hasPortrait then
        mock.portrait.tex:Show()
        local cr, cg, cb = R.ClassColor(data.class)
        local renderMode = (runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.render) or PortraitStyleGet(key, "portraitRender", "2D")
        local previewShape = (runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.shape)
            or PortraitStyleGet(key, "portraitShape", "SQUARE")
        if renderMode == "CLASS" then
            local visual = R.ClassPortraitVisual(data.class, (runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.classStyle) or PortraitStyleGet(key, "portraitClassStyle", "BLIZZARD"))
            if visual and visual.atlas and mock.portrait.tex.SetAtlas then
                mock.portrait.tex:SetAtlas(visual.atlas)
            else
                mock.portrait.tex:SetTexture(visual and visual.texture or "Interface\\ICONS\\INV_Misc_QuestionMark")
                if mock.portrait.tex.SetTexCoord then
                    mock.portrait.tex:SetTexCoord(
                        (visual and visual.left) or 0,
                        (visual and visual.right) or 1,
                        (visual and visual.top) or 0,
                        (visual and visual.bottom) or 1
                    )
                end
            end
            if mock.portrait.tex.SetVertexColor then mock.portrait.tex:SetVertexColor(1, 1, 1, 1) end
            mock.portrait.initial:Hide()
        else
            -- Mirror the live unit's actual portrait when the unit exists;
            -- SetPortraitTexture is a plain texture API (no protected state).
            if data.liveUnit and type(_G.SetPortraitTexture) == "function" then
                -- Same third argument as the live element: the BLIZZARD shape
                -- uses the stock unmasked bust render.
                _G.SetPortraitTexture(mock.portrait.tex, data.liveUnit, (previewShape == "BLIZZARD") or nil)
            else
                mock.portrait.tex:SetTexture(R.UnitPreviewPortraitTexture(key, data))
            end
            if mock.portrait.tex.SetVertexColor then mock.portrait.tex:SetVertexColor(1, 1, 1, 1) end
            if mock.portrait.tex.SetTexCoord then
                local pSpec = runtimeSpec and runtimeSpec.portrait
                local l, r, t, b = pSpec and pSpec.texL, pSpec and pSpec.texR, pSpec and pSpec.texT, pSpec and pSpec.texB
                if l == nil or r == nil or t == nil or b == nil then
                    local zoom = tonumber(PortraitStyleGet(key, "portraitZoom", 100)) or 100
                    if zoom > 1 and zoom <= 2 then zoom = zoom * 100 end
                    if zoom < 100 then zoom = 100 elseif zoom > 200 then zoom = 200 end
                    local span = (previewShape == "BLIZZARD" and 1 or 0.84) * (100 / zoom)
                    local inset = (1 - span) * 0.5
                    l, r, t, b = inset, 1 - inset, inset, 1 - inset
                end
                mock.portrait.tex:SetTexCoord(l, r, t, b)
            end
            mock.portrait.initial:Hide()
        end
        local portraitBg = runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.bg
        if (portraitBg and portraitBg.enabled == true) or (not (runtimeSpec and runtimeSpec.portrait) and PortraitStyleGet(key, "portraitBgEnabled", false) == true) then
            if mock.portrait.bg then
                mock.portrait.bg:SetVertexColor(
                    (portraitBg and portraitBg.r) or g.portraitBgColorR or 0.05,
                    (portraitBg and portraitBg.g) or g.portraitBgColorG or 0.05,
                    (portraitBg and portraitBg.b) or g.portraitBgColorB or 0.05,
                    (portraitBg and portraitBg.a) or g.portraitBgColorA or 0.85
                )
                mock.portrait.bg:Show()
            end
            mock.portrait:SetBackdropColor(0, 0, 0, 0)
        else
            if mock.portrait.bg then mock.portrait.bg:Hide() end
            mock.portrait:SetBackdropColor(0, 0, 0, 0)
        end
        local portraitBorder = runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.border
        mock.portrait._msufPreviewBorderArt = (portraitBorder and portraitBorder.art)
            or PortraitStyleGet(key, "portraitBorderArt", "FLAT")
        mock.portrait._msufPreviewBorderDirection = (portraitBorder and portraitBorder.direction)
            or PortraitStyleGet(key, "portraitBorderDirection", "UP")
        mock.portrait._msufPreviewBorderShape = previewShape
        if mock.portrait._msufPreviewBorderArt == "RELIEF"
            and box._runtimePortraitPlacement == "OVERLAY"
            and box._runtimePortraitOverlayAlign == "FULL"
        then
            CachePreviewFullPortraitExtents(mock.portrait, mock, S(w), S(h), ox, oy,
                S(box._runtimeHealthPowerInset))
        else
            if mock.portrait._msufPreviewLayoutWidth ~= nil then mock.portrait._msufPreviewLayoutWidth = nil end
            if mock.portrait._msufPreviewLayoutHeight ~= nil then mock.portrait._msufPreviewLayoutHeight = nil end
        end
        local bStyle = box._runtimePortraitBorderStyle or (portraitBorder and portraitBorder.style) or PortraitStyleGet(key, "portraitBorderStyle", "NONE")
        local edgeSoftnessLevel = tonumber(runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.edgeSoftnessLevel)
        if edgeSoftnessLevel == nil then
            edgeSoftnessLevel = floor(((tonumber(PortraitStyleGet(key, "portraitEdgeSoftness", 0)) or 0) / 2) + 0.5)
            if edgeSoftnessLevel < 0 then edgeSoftnessLevel = 0 elseif edgeSoftnessLevel > 15 then edgeSoftnessLevel = 15 end
            if previewShape == "BLIZZARD" or bStyle ~= "NONE" then edgeSoftnessLevel = 0 end
        end
        R.ApplyPreviewPortraitShapeMask(mock.portrait, previewShape, edgeSoftnessLevel)
        R.LayoutPreviewBlizzardPortrait(mock.portrait, previewShape == "BLIZZARD",
            S(box._runtimePortraitW), S(box._runtimePortraitH))
        -- The Blizzard ring shape parks every MSUF border renderer, exactly
        -- like the live element.
        if previewShape == "BLIZZARD" or bStyle == "NONE" then
            R.LayoutPreviewPortraitBorder(mock.portrait, 0, false)
        elseif bStyle == "CUSTOM" or bStyle == "SOLID" then
            R.LayoutPreviewPortraitBorder(
                mock.portrait,
                S(box._runtimePortraitBorderThickness),
                box._runtimePortraitBorderFill,
                (portraitBorder and portraitBorder.r) or g.portraitBorderColorR or 1,
                (portraitBorder and portraitBorder.g) or g.portraitBorderColorG or 1,
                (portraitBorder and portraitBorder.b) or g.portraitBorderColorB or 1,
                (portraitBorder and portraitBorder.a) or g.portraitBorderColorA or 1
            )
        elseif bStyle == "CLASS_COLOR" then
            R.LayoutPreviewPortraitBorder(mock.portrait, S(box._runtimePortraitBorderThickness), box._runtimePortraitBorderFill, cr, cg, cb, 1)
        elseif bStyle == "REACTION" then
            local hostile = (key == "target" or key == "boss" or key == "focus" or key == "focustarget")
            R.LayoutPreviewPortraitBorder(mock.portrait, S(box._runtimePortraitBorderThickness), box._runtimePortraitBorderFill, hostile and 1 or 0.1, hostile and 0.2 or 0.85, 0.1, 1)
        else
            R.LayoutPreviewPortraitBorder(mock.portrait, S(box._runtimePortraitBorderThickness), box._runtimePortraitBorderFill, 1, 1, 1, 1)
        end
        box.handlePortrait:SetSize(
            max(18, S(box._runtimePortraitW) + ((box._runtimePortraitBorderFill and 0 or S(box._runtimePortraitBorderThickness)) * 2)),
            max(18, S(box._runtimePortraitH) + ((box._runtimePortraitBorderFill and 0 or S(box._runtimePortraitBorderThickness)) * 2)))
        PlaceHandle(box.handlePortrait, mock.portrait)
        else
            mock.portrait.tex:Hide()
            mock.portrait.initial:Hide()
            if mock.portrait.bg then mock.portrait.bg:Hide() end
            mock.portrait:SetBackdropColor(0, 0, 0, 0)
            R.LayoutPreviewPortraitBorder(mock.portrait, 0, false)
            R.LayoutPreviewBlizzardPortrait(mock.portrait, false)
            box.handlePortrait:Hide()
        end
    else
        mock.portrait:Hide()
        R.LayoutPreviewPortraitBorder(mock.portrait, 0, false)
        R.LayoutPreviewBlizzardPortrait(mock.portrait, false)
        box.handlePortrait:Hide()
    end
    if castPreviewVisible then
        mock.cast:Show()
        -- The live castbar is not a child of the scaled unit frame. Preserve
        -- that independent frame geometry inside Menu2 instead of stretching
        -- the castbar with the unit-frame preview.
        if mock.cast.SetScale then mock.cast:SetScale(box._mockCastFrameScale or 1) end
        local castOutline = max(0, min(12, floor((tonumber(g.castbarOutlineThickness) or 1) + 0.5)))
        local castEdge = castOutline > 0 and max(1, S(castOutline)) or 0
        if mock.cast._msufCastbarBackdropEdge ~= castEdge then
            if castEdge > 0 then
                mock.cast:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8X8",
                    edgeFile = "Interface\\Buttons\\WHITE8X8",
                    edgeSize = castEdge,
                    insets = { left = 0, right = 0, top = 0, bottom = 0 },
                })
            else
                mock.cast:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
            end
            mock.cast._msufCastbarBackdropEdge = castEdge
        end
        local castBgR, castBgG, castBgB, castBgA = 0.10, 0.10, 0.10, 0.85
        if type(_G.MSUF_GetCastbarBackgroundColor) == "function" then
            castBgR, castBgG, castBgB, castBgA = _G.MSUF_GetCastbarBackgroundColor()
        end
        mock.cast:SetBackdropColor(castBgR or 0.10, castBgG or 0.10, castBgB or 0.10, castBgA or 0.85)
        if castEdge > 0 then
            mock.cast:SetBackdropBorderColor(g.castbarBorderR or 0, g.castbarBorderG or 0, g.castbarBorderB or 0, g.castbarBorderA or 1)
        else
            mock.cast:SetBackdropBorderColor(0, 0, 0, 0)
        end
        local scw, sch = max(20, S(castW)), max(6, S(castBarH))
        mock.cast:SetSize(scw, sch)
        if mock.cast.sizeTag then
            mock.cast.sizeTag:SetText(format("%d x %d", floor(castW + 0.5), floor(castBarH + 0.5)))
            mock.cast.sizeTag:Show()
        end
        mock.cast:ClearAllPoints()
        if castDetached then
            box._detachedCastPreview = true
            box._detachedCastBaseOffsetX, box._detachedCastBaseOffsetY = S(castOffsetX), S(castOffsetY)
            mock.cast:SetPoint("CENTER", mock, "CENTER", box._detachedCastBaseOffsetX, box._detachedCastBaseOffsetY)
        elseif key == "player" then
            mock.cast:SetPoint("BOTTOM", mock, "TOP", S(castOffsetX), S(castOffsetY))
        elseif key == "boss" then
            mock.cast:SetPoint("TOPLEFT", mock, "BOTTOMLEFT",
                S(castOffsetX - box._bossBorderInset),
                S(castOffsetY - box._bossBorderInset - box._bossCastbarGap)
                    + (box._runtimePowerEmbedded == true and powerH or 0))
        else
            mock.cast:SetPoint("BOTTOMLEFT", mock, "TOPLEFT", S(castOffsetX), S(castOffsetY))
        end
        local cr, cg, cb = 0.0, 0.9, 0.8
        if type(_G.MSUF_GetInterruptibleCastColor) == "function" then cr, cg, cb = _G.MSUF_GetInterruptibleCastColor() end
        mock.cast.fill:SetVertexColor(cr or 0.0, cg or 0.9, cb or 0.8, 1)
        ApplyCastbarPreviewDetails(box, mock, canvas, g, key, castBarH, scw, S, max, min, floor, fr, fg, fb, TR, ApplyPreviewFont, R.CastbarShowIcon, R.CastbarShowText, R.ReadCastbarNum, R.FormatCastbarPreviewTime, UnitPreviewText, PlaceHandle, animState)
        ApplyCastbarPreviewRounded(mock.cast, g, castEdge, castBgR, castBgG, castBgB, castBgA)
        box.handleCastbar:SetSize(
            max(36, scw * (box._mockCastFrameScale or 1)),
            max(18, (sch + 8) * (box._mockCastFrameScale or 1)))
        PlaceHandle(box.handleCastbar, mock.cast)
    else
        mock.cast:Hide()
        if mock.cast.sizeTag then mock.cast.sizeTag:Hide() end
        box.handleCastbar:Hide()
        box.handleCastbarIcon:Hide()
        box.handleCastbarText:Hide()
        box.handleCastbarTarget:Hide()
        box.handleCastbarTime:Hide()
    end
    if Auras and Auras.Layout then Auras.Layout(box, mock, auraPreviewState, S, baseLevel) end
    local statusLayerAvailable = false
    for i = 1, #D.STATUS_PREVIEW do
        local spec = D.STATUS_PREVIEW[i]
        local icon = mock.icons[spec.id]
        local handle = box.statusHandles[spec.id]
        local statusCfg = runtimeStatus and runtimeStatus[R.STATUS_RUNTIME_KEYS[spec.id]]
        local show
        if statusCfg then
            show = statusCfg.enabled == true
            if not show and spec.id == "statusPvp" and statusCfg.contextDisabled == true then show = true end
        else
            local showVal = conf[spec.show]
            if showVal == nil then showVal = g[spec.show] end
            show = (showVal == nil) and (spec.defaultShow ~= false) or (showVal ~= false)
        end
        if spec.allowed and not spec.allowed(key) then show = false end
        if Preview.GetStatusPreviewMode() ~= "all" then
            local selected = R.NormalizeStatusPreviewId(Preview.selectedStatusId)
            if selected == "" then selected = "raidmarker" end
            show = show and (spec.id == selected)
        end
        icon:SetShown(show)
        if show then
            statusLayerAvailable = true
            local isIdentityText = R.PreviewStatus.IsIdentityText and R.PreviewStatus.IsIdentityText(spec)
            local rawSize = tonumber(statusCfg and statusCfg.size) or tonumber(conf[spec.size]) or tonumber(g[spec.size])
            if rawSize == nil then
                if isIdentityText then
                    rawSize = nameRawSize
                elseif R.PreviewStatus.IsStatusTextState and R.PreviewStatus.IsStatusTextState(spec) then
                    rawSize = nameRawSize + 2
                else
                    rawSize = spec.defaultSize
                end
            end
            local sz = S(rawSize)
            if isIdentityText then
                if sz < 7 then sz = 7 end
            elseif sz < 10 then
                sz = 10
            end
            if icon.SetFrameLevel then
                local rawLayer = tonumber(statusCfg and statusCfg.layer) or (spec.layer and (tonumber(conf[spec.layer]) or tonumber(g[spec.layer]))) or spec.defaultLayer
                icon:SetFrameLevel((Layers.ElementLevel and Layers.ElementLevel(rawLayer, spec.defaultLayer or 7, 8))
                    or ((canvas.GetFrameLevel and canvas:GetFrameLevel() or 0) + ClampPreviewLayer(rawLayer, spec.defaultLayer or 7)))
            end
            if isIdentityText and icon.txt then
                -- Runtime status text uses the compiled unit font/shadow before
                -- applying the indicator color. Preserve that ownership here so
                -- glyph metrics (and therefore NAMELEFT/NAMERIGHT placement)
                -- remain identical when a unit-specific font is configured.
                ApplyRuntimePreviewFont(runtimeSpec, ApplyPreviewFont, icon.txt, max(7, sz),
                    NameRelativeFontRole(StatusAnchorOffsets(spec, statusCfg)))
            end
            R.SetPreviewIconTexture(icon, spec, conf, g, key, data, statusCfg, box._previewStatusText)
            if spec.id == "statusCombat" and icon.SetAlpha then
                icon:SetAlpha(animState and (0.55 + ((tonumber(animState.pulse) or 0) * 0.45)) or 1)
            elseif icon.SetAlpha then
                icon:SetAlpha(1)
            end
            if isIdentityText then
                local anchor, x, y = StatusAnchorOffsets(spec, statusCfg)
                if icon.txt then
                    icon.txt:ClearAllPoints()
                    icon.txt:SetPoint("LEFT", icon, "LEFT", 0, 0)
                    icon.txt:SetJustifyH("LEFT")
                end
                local textW = icon.txt and icon.txt.GetStringWidth and icon.txt:GetStringWidth() or sz
                local textH = icon.txt and icon.txt.GetStringHeight and icon.txt:GetStringHeight() or sz
                icon:SetSize(max(1, floor((tonumber(textW) or sz) + 0.5)), max(1, floor((tonumber(textH) or sz) + 0.5)))
                R.PositionLevelPreview(icon, anchor, x, y, mock, S(6))
            elseif R.PreviewStatus.IsStatusTextState and R.PreviewStatus.IsStatusTextState(spec) then
                local anchor, x, y = StatusAnchorOffsets(spec, statusCfg)
                if icon.txt then
                    ApplyPreviewFont(icon.txt, max(7, sz))
                    icon.txt:ClearAllPoints()
                    icon.txt:SetPoint("CENTER")
                    icon.txt:SetJustifyH("CENTER")
                end
                local textW = icon.txt and icon.txt.GetStringWidth and icon.txt:GetStringWidth() or sz
                local textH = icon.txt and icon.txt.GetStringHeight and icon.txt:GetStringHeight() or sz
                icon:SetSize(max(1, floor((tonumber(textW) or sz) + 0.5)), max(1, floor((tonumber(textH) or sz) + 0.5)))
                R.PositionSameAnchorPreview(icon, anchor, x, y, mock)
            else
                icon:SetSize(sz, sz)
                if icon.txt then
                    ApplyPreviewFont(icon.txt, max(7, floor(sz * 0.52 + 0.5)))
                    icon.txt:ClearAllPoints()
                    icon.txt:SetPoint("CENTER")
                    icon.txt:SetJustifyH("CENTER")
                end
                local anchor, x, y = StatusAnchorOffsets(spec, statusCfg)
                if spec.id == "raidmarker" then
                    R.PositionRuntimeLayoutIconPreview(icon, anchor, x, y, mock, true)
                elseif spec.id == "leader" or spec.id == "assist" or spec.id == "elite" then
                    R.PositionRuntimeLayoutIconPreview(icon, anchor, x, y, mock, false)
                elseif spec.id == "statusCombat" or spec.id == "statusResting" or spec.id == "statusIncomingRes" or spec.id == "statusPvp" then
                    R.PositionStatusCornerPreview(icon, anchor, x, y, mock, S(2))
                else
                    R.PositionFromAnchor(icon, anchor, x, y, mock, sz)
                end
            end
            handle:SetSize(max(18, icon:GetWidth() + 8), max(18, icon:GetHeight() + 8))
            PlaceHandle(handle, icon)
        else
            handle:Hide()
        end
    end
    if showRaidGroupName then statusLayerAvailable = true end
    box.layerAvailable = {
        guides = true,
        nameText = showNamePreview,
        hpText = hpTextOn,
        powerText = powerTextOn,
        portrait = hasPortrait,
        power = powerEnabled == true and box._runtimeAugCompositePreview ~= true,
        classPower = classPowerOn,
        castbar = castEnabled,
        buff = auraPreviewState ~= nil and auraPreviewState.buff ~= nil,
        debuff = auraPreviewState ~= nil and auraPreviewState.debuff ~= nil,
        auras = auraPreviewState ~= nil and (auraPreviewState.custom1 ~= nil
            or auraPreviewState.custom2 ~= nil or auraPreviewState.custom3 ~= nil or auraPreviewState.custom4 ~= nil
            or auraPreviewState.defensivePortrait ~= nil or auraPreviewState.targetDotPortrait ~= nil),
        dispelOverlay = box._previewDispelOverlayAvailable == true,
        dispelSymbol = box._previewDispelSymbolAvailable == true,
        status = statusLayerAvailable,
        texLayer = PreviewTextureLayerConfigured(conf),
        bounds = true,
    }
    for i = 1, #(box.layerButtons or {}) do
        local button = box.layerButtons[i]
        if button.key == "classPower" and button.SetShown then button:SetShown(key == "player") end
        if button.refresh then button:refresh() end
    end
    if box.LayoutLayerRail then box:LayoutLayerRail((box.GetWidth and box:GetWidth() or 0) - 24) end
    local nameHandleW = mock.nameText:GetStringWidth() + 10
    if mock.totInlineSep and mock.totInlineSep:IsShown() then nameHandleW = nameHandleW + mock.totInlineSep:GetStringWidth() + mock.totInlineText:GetStringWidth() + S(8) end
    box.handleName:SetSize(max(46, nameHandleW), max(18, mock.nameText:GetStringHeight() + 6))
    if not UnitPreviewText.PlaceHandleAroundRegions(box.handleName, canvas, { mock.nameText, mock.totInlineSep, mock.totInlineText }, 3, { coordinateScale = scale, fitText = true, useScaledRect = true }) then PlaceHandle(box.handleName, mock.nameText) end
    local function PlaceTextSlotHandle(handle, region)
        if not handle then return end
        if not (region and region.IsShown and region:IsShown()) then
            handle:Hide()
            return
        end
        local w = (region.GetStringWidth and region:GetStringWidth()) or region:GetWidth() or 36
        local h = (region.GetStringHeight and region:GetStringHeight()) or region:GetHeight() or 12
        handle:SetSize(max(26, w + 10), max(18, h + 6))
        if not UnitPreviewText.PlaceHandleAroundRegions(handle, canvas, { region }, 3, { coordinateScale = scale, fitText = true, useScaledRect = true }) then PlaceHandle(handle, region) end
    end
    PlaceTextSlotHandle(box.handleRaidGroupName, mock.raidGroupNameText)
    local function PlaceValueTextHandles(kind, mainHandle, leftHandle, centerHandle, rightHandle, leftRegion, centerRegion, rightRegion)
        if UnitPreviewTextMovesTogether(key, kind) then
            SetShownSafe(leftHandle, false)
            SetShownSafe(centerHandle, false)
            SetShownSafe(rightHandle, false)
            if UnitPreviewText.PlaceHandleAroundRegions(mainHandle, canvas, { leftRegion, centerRegion, rightRegion }, 3, { coordinateScale = scale, fitText = true, useScaledRect = true }) then return end
            if not ((leftRegion and leftRegion:IsShown()) or (centerRegion and centerRegion:IsShown()) or (rightRegion and rightRegion:IsShown())) then
                mainHandle:Hide()
                return
            end
            mainHandle:SetSize(max(46, rightRegion:GetStringWidth() + 10), max(18, rightRegion:GetStringHeight() + 6))
            PlaceHandle(mainHandle, rightRegion)
            return
        end
        if mainHandle then mainHandle:Hide() end
        PlaceTextSlotHandle(leftHandle, leftRegion)
        PlaceTextSlotHandle(centerHandle, centerRegion)
        PlaceTextSlotHandle(rightHandle, rightRegion)
    end
    -- Under reverse order the configured left slot renders on the physical
    -- right FontString (and vice versa); pair each slot handle with the
    -- FontString that actually shows its content so drags edit visible text.
    if R.TextScopeGet(key, "hpTextReverse", false) == true then
        PlaceValueTextHandles("hp", box.handleHP, box.handleHPLeft, box.handleHPCenter, box.handleHPRight, mock.hpText, mock.hpTextCenter, mock.hpTextLeft)
    else
        PlaceValueTextHandles("hp", box.handleHP, box.handleHPLeft, box.handleHPCenter, box.handleHPRight, mock.hpTextLeft, mock.hpTextCenter, mock.hpText)
    end
    PlaceValueTextHandles("power", box.handlePower, box.handlePowerLeft, box.handlePowerCenter, box.handlePowerRight, mock.powerTextLeft, mock.powerTextCenter, mock.powerText)
    R.ApplyPreviewTextFocus(box, canvas, mock)
    ApplyPreviewLayerVisibility(box)
    ApplyPreviewTransparency(box, conf, runtimeSpec)
    RefreshHandleSelectionVisuals(box)
end
end
