local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
--- Unit preview render/composition.
---
--- The view file builds frames and wires controls; this module owns the hot
--- refresh path that composes the live preview visuals.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
-- Vanilla, TBC and Mists load this file too; their differences are client
-- facts read once here. A harness without MSUF.Client renders as Mainline.
-- Classic draws a gold ring where the stock portrait atlas is missing (every
-- client stamps texture layers after the portrait); Era's legacy PlayerFrame has no modern
-- HUD portrait atlases at all; boss pieces need boss units (SupportsUnit).
local Render = MSUF.UFPreviewRender or {}
MSUF.UFPreviewRender = Render
local MenuState = MSUF.MSUF2 or _G.MSUF2 or {}
local EnsureDB = MenuState.EnsureDB
local PickFallbackTable = MenuState.PickFallbackTable
local Fallbacks = MenuState.Fallbacks or {}
local PreviewHelpers = MenuState.PreviewHelpers or {}
local CPPreview = MenuState.ClassPowerPreview or {}
local CastbarPreview = MSUF.UFPreviewCastbar or {}
local Layers = MSUF.UF and MSUF.UF.Layers or {}
local function ScaleCastbarOutline(value, scale)
    value = math.floor((tonumber(value) or 0) + 0.5)
    if value <= 0 then return 0 end
    scale = tonumber(scale) or 1
    if scale <= 0 then scale = 1 end
    return math.max(1, math.floor((value * scale) + 0.5))
end



-- Preview scale and resolved FULL extents are inputs to the runtime painter.


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

local function CastbarPreviewDetailPrefix(unitKey)
    if unitKey == "player" then return "castbarPlayer" end
    if unitKey == "target" then return "castbarTarget" end
    if unitKey == "focus" then return "castbarFocus" end
    if unitKey == "boss" then return "bossCast" end
    return nil
end
local NormalizeCastbarPreviewIconPos = _G.MSUF_NormalizeCastbarIconPosition
local function ApplyCastbarPreviewIconZoom(icon, zoom)
    MSUF.Castbars.Visuals.ApplyIconZoom(icon and (icon.texture or icon.Texture or icon.Icon), zoom)
end
-- UnitPreview_Castbar loads immediately before this file and owns the text
-- contract shared with the page-local castbar preview.
local NormalizeCastbarPreviewTextPos = CastbarPreview.NormalizeTextPosition
local CastbarPreviewJustifyForPosition = CastbarPreview.JustifyForTextPosition
local NormalizeCastbarPreviewJustify = CastbarPreview.NormalizeTextJustify
local PREVIEW_CLASS_POWER_SHAPES = CPPreview.CLASS_SHAPES
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
local NormalizePreviewClassPowerShapeAlign = _G.MSUF_UF_NormalizeShapeAlign
-- The container width is the live class resource layout's rule (player frame
-- width, custom width, pip auto-fit, Cooldown Manager viewer), shared with the
-- Class Resources page preview; only the canvas clamp is this preview's own.
local function PreviewClassPowerWidth(bars, frameW, cpH, segCount)
    local w = tonumber(CPPreview.ContainerWidth(bars, frameW, cpH, segCount)) or frameW
    if w < 1 then w = 1 elseif w > 800 then w = 800 end
    return w
end
local function PreviewClassTextLevel(owner, bars)
    local layer = math.floor((tonumber(bars and bars.classPowerTextLayer) or 5) + 0.5)
    if layer < 0 then layer = 0 elseif layer > 30 then layer = 30 end
    if Layers.TextLevel then return Layers.TextLevel(owner, layer, 5) end
    if Layers.ElementLevel then return Layers.ElementLevel(layer, 5, 8) end
    return 100 + layer * 32 + 8
end
local function EnsurePreviewSecondaryClassTimer(mock, whiteTexture)
    local classPower = mock and mock.classPower
    if not classPower then return nil end
    local frame = classPower._msufSecondaryTimer
    if frame then return frame end
    frame = PixelLayoutRegion(CreateFrame("Frame", nil, classPower))
    frame.bg = PixelLayoutRegion(frame:CreateTexture(nil, "BACKGROUND"))
    frame.bg:SetAllPoints(frame)
    frame.bg:SetTexture(whiteTexture)
    frame.fill = PixelLayoutRegion(frame:CreateTexture(nil, "ARTWORK"))
    frame.fill:SetTexture(whiteTexture)
    frame.textOwner = PixelLayoutRegion(CreateFrame("Frame", nil, frame))
    frame.textOwner:SetAllPoints(frame)
    if frame.textOwner.EnableMouse then frame.textOwner:EnableMouse(false) end
    frame.text = PixelLayoutRegion(frame.textOwner:CreateFontString(nil, "OVERLAY"))
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
-- Blizzard's BackdropTemplateMixin:SetBackdrop skips a table it already holds
-- (HasBackdropInfo compares identity): one constant table per outline size.
local ResolvePreviewPowerShape = CPPreview.ResolvePowerShape
local NormalizeCastbarPreviewTruncate = _G.MSUF_NormalizeCastbarTruncate
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

--- The fourth return is true when the colour follows the health value, so the
--- animation tick knows to repaint it. The ramp is the live one: the gradient
--- stops of the compiled health spec, interpolated by the engine's own rule.
-- Reused argument of Portrait.BorderColor, which reads only the style.
local function PreviewLiveFrame(key)
    local uf = MSUF and MSUF.UF
    local unit = (key == "boss" and "boss1") or (key == "arena" and "arena1") or key
    local frame = uf and type(uf.GetFrame) == "function" and uf.GetFrame(unit) or nil
    if not frame then frame = uf and uf.frames and uf.frames[unit] or nil end
    return frame
end
--- Whether a status indicator shows in the preview: the compiled runtime
--- switch when there is one (PvP also previews while only its context is
--- off), otherwise the stored or default switch. Units the indicator does
--- not support never show it; outside "all" mode only the selected one does.
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
    return shorten({ unit = (key == "boss" and "boss1") or (key == "arena" and "arena1") or key }, text)
end
local function HideCastbarPreviewIconBorder(icon)
    if icon then MSUF.Castbars.Visuals.PaintIconBorder(icon, icon, "NONE", 0, nil, 0, true) end
end
local function ApplyCastbarPreviewIconBorder(icon, style, thickness, g)
    if not (icon and icon.SetBackdropBorderColor) then return end
    local texture = icon.texture or icon.Texture or icon.Icon
    if texture and texture.ClearAllPoints and texture.SetAllPoints then
        texture:ClearAllPoints()
        texture:SetAllPoints(icon)
    end
    thickness = math.max(0, math.min(8, tonumber(thickness) or 0))
    MSUF.Castbars.Visuals.PaintIconBorder(icon, icon, style, thickness, g, thickness, true)
end
local AnchorCastbarPreviewText = CastbarPreview.AnchorText
local function SetLeftSpan(region, parent, x, y)
    region:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y or 0)
    region:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x or 0, y or 0)
end
local function SetRightSpan(region, parent, x, y)
    region:SetPoint("TOPRIGHT", parent, "TOPRIGHT", x or 0, y or 0)
    region:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", x or 0, y or 0)
end
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
local function PreviewLayerWanted(box, layerKey)
    local visibility = box and box.layerVisibility
    return not (visibility and visibility[layerKey] == false)
end
local function NumberOrOne(value) return tonumber(value) or 1 end
local function CastbarNumFallback(_, _, fallback) return tonumber(fallback) or 0 end
local function CastbarTimeFallback(value) return tostring(value or "") end
local function EnsureCastbarPreviewRoundedSurface(cast)
    local surface = cast and cast._msufCastbarRoundedSurface
    if surface then return surface end
    if not (cast and type(_G.CreateFrame) == "function") then return nil end
    surface = PixelLayoutRegion(CreateFrame("Frame", nil, cast))
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
    local bars = EnsureDB().bars
    local enabled = bars and ((bars.slantedBarsEnabled ~= false and bars.slantedCastbars == true)
        or (bars.roundedFramesEnabled == true and bars.roundedCastbars == true))
    local surface = LayoutCastbarPreviewSurface(cast)
    local bg = cast._msufCastbarRoundedBg
    if not bg then
        bg = PixelLayoutRegion(cast:CreateTexture(nil, "BACKGROUND"))
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
    RuntimeAppliedPortraitSizeForPreviewKey = Fallbacks.Nil, RuntimeVisualScaleForPreviewKey = Fallbacks.One, RuntimeCastbarVisualScaleForPreviewKey = Fallbacks.One, ClampPreviewZoom = NumberOrOne, ResolveDefaultPreviewZoomLock = Fallbacks.Noop, UpdatePreviewZoomControls = Fallbacks.Noop,
    CastbarShowIcon = Fallbacks.True, CastbarShowText = Fallbacks.TruePair, ReadCastbarNum = CastbarNumFallback, FormatCastbarPreviewTime = CastbarTimeFallback,
    GradientPreviewColor = Fallbacks.HealthRGB, PowerColor = Fallbacks.PowerRGB, FontColor = Fallbacks.WhiteRGB,
    TextScopeGet = Fallbacks.Nil, ApplyPreviewTextFocus = Fallbacks.Noop,
}

--- Castbar preview detail layout mirrors the live CastbarVisuals rules without
--- subscribing to spellcast events. Keep all data reads profile/local here.
local CASTBAR_TEXT_HANDLE_OPTS = { fitText = true }
-- Configuration-only samples: these regions never query a cast, cooldown or
-- network latency, and never install a timer or live event listener. They
-- follow the live player castbar: the latency text uses the player castbar's
-- time text font, and channel ticks sit centred on their offset like
-- Castbars/MSUF_CastbarChannelTicks.lua (five markers at i / 6 without an
-- active channel, clamped to 2..98%, custom positions in percent, mirrored by
-- a right-to-left fill, OVERLAY sublevel 7).
local CHANNEL_SAMPLE_TICKS = 5
local NO_CASTBAR_SAMPLE_CONFIG = {}
local function CastbarSampleTexture(samples, surface, name)
    local region = samples[name]
    if not region then
        region = PixelLayoutRegion(surface:CreateTexture(nil, "OVERLAY"))
        samples[name] = region
    end
    region:ClearAllPoints()
    return region
end
local function ApplyCastbarFeatureSamples(mock, canvas, surface, g, key, width, height, S, ApplyFont, TR, timeFontSize)
    local samples = mock.cast._featureSamples
    if not samples then
        samples = {ticks={}}
        mock.cast._featureSamples = samples
    end
    if key == "player" and g.castbarShowLatencyText == true then
        local text = samples.latency
        if not text then text = PixelLayoutRegion(surface:CreateFontString(nil, "OVERLAY")); samples.latency = text end
        ApplyFont(text, timeFontSize)
        text:ClearAllPoints()
        text:SetPoint("TOPRIGHT", surface, "BOTTOMRIGHT", 0, -S(2))
        text:SetTextColor(1, 1, 1)
        text:SetText("50 ms")
        text:Show()
    elseif samples.latency then samples.latency:Hide() end
    local channel = key == "player" and g.castbarShowChannelTicks == true
    local player = _G.MSUF_DB and _G.MSUF_DB.player
    local cfg = player and player.castbar or NO_CASTBAR_SAMPLE_CONFIG
    local custom = cfg.channelTickUseCustom == true
    local count = 0
    if channel then
        count = CHANNEL_SAMPLE_TICKS
        if custom then count = math.floor((tonumber(cfg.channelTickCount) or CHANNEL_SAMPLE_TICKS) + 0.5) end
        count = math.max(0, math.min(10, count))
    end
    local positions = custom and type(cfg.channelTickPosPct) == "table" and cfg.channelTickPosPct or nil
    local final, finalPosition = count, -1
    if positions then
        for i = 1, count do
            local position = math.max(0, math.min(100, tonumber(positions[i]) or (i / (count + 1) * 100)))
            if position >= finalPosition then final, finalPosition = i, position end
        end
    end
    local reverse = count > 0 and type(_G.MSUF_GetCastbarReverseFillForFrame) == "function"
        and _G.MSUF_GetCastbarReverseFillForFrame(nil, true) == true
    for i = 1, math.max(count, #samples.ticks) do
        local marker = samples.ticks[i]
        if i <= count then
            if not marker then
                marker = PixelLayoutRegion(surface:CreateTexture(nil, "OVERLAY", nil, 7))
                samples.ticks[i] = marker
            end
            local percent = positions and type(positions[i]) == "number" and positions[i] or nil
            local fraction = percent and math.max(0, math.min(100, percent)) / 100
                or math.max(0.02, math.min(0.98, i / (count + 1)))
            local accent = g.castbarAccentLastTick == true and i == final
            marker:ClearAllPoints()
            if reverse then
                marker:SetPoint("TOP", surface, "TOPRIGHT", -width * fraction, 0)
                marker:SetPoint("BOTTOM", surface, "BOTTOMRIGHT", -width * fraction, 0)
            else
                marker:SetPoint("TOP", surface, "TOPLEFT", width * fraction, 0)
                marker:SetPoint("BOTTOM", surface, "BOTTOMLEFT", width * fraction, 0)
            end
            marker:SetWidth(math.max(1, S(accent and 3 or 2)))
            marker:SetColorTexture(1, accent and .72 or 1, accent and .2 or 1, 1)
            marker:Show()
        elseif marker then marker:Hide() end
    end
    mock.cast._msufPreviewChannelSample = channel
    if channel and mock.cast.text:IsShown() then mock.cast.text:SetText(TR("Channel")) end
    local kick = key == "target" and g.kickReadyShowTarget == true
        or key == "focus" and (g.kickReadyShowFocus == true or g.enableFocusKickIcon == true)
        or key == "boss" and g.kickReadyShowBoss == true
        or key == "arena" and g.kickReadyShowArena == true
    local color = type(g.kickReadyColor) == "table" and g.kickReadyColor or NO_CASTBAR_SAMPLE_CONFIG
    local r, green, blue, alpha = tonumber(color[1] or color["1"]) or 0, tonumber(color[2] or color["2"]) or 1, tonumber(color[3] or color["3"]) or 0, 1
    if kick and g.kickReadyTimeMarker == true then
        local marker = CastbarSampleTexture(samples, surface, "kickMarker")
        marker:SetPoint("TOPLEFT", surface, "TOPLEFT", width * .4, 0)
        marker:SetSize(math.max(1, S(2)), height)
        marker:SetColorTexture(r, green, blue, alpha)
        marker:Show()
    elseif samples.kickMarker then samples.kickMarker:Hide() end
    if kick and g.kickReadyTimeSegment == true then
        local segment = CastbarSampleTexture(samples, surface, "kickSegment")
        segment:SetPoint("TOPLEFT", surface, "TOPLEFT", width * .4, 0)
        segment:SetSize(width * .6, height)
        segment:SetColorTexture(r, green, blue, .25 * alpha)
        segment:Show()
    elseif samples.kickSegment then samples.kickSegment:Hide() end
    -- A separate representative strip retains the ordinary cast details. The
    -- detached sample uses configured dimensions/opacity and bounded canvas
    -- coordinates, so distant screen offsets cannot clip the entire sample.
    if key == "player" and g.showGCDBar == true then
        local gcd = samples.gcd
        if not gcd then
            gcd = PixelLayoutRegion(CreateFrame("Frame", nil, canvas))
            gcd.bar = PixelLayoutRegion(CreateFrame("StatusBar", nil, gcd))
            gcd.bar:SetAllPoints()
            gcd.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8"); gcd.bar:SetStatusBarColor(.2, .75, 1, 1)
            local bg = PixelLayoutRegion(gcd.bar:CreateTexture(nil, "BACKGROUND")); bg:SetAllPoints(); bg:SetColorTexture(.05, .05, .05, .8)
            gcd.text = PixelLayoutRegion(gcd.bar:CreateFontString(nil, "OVERLAY")); gcd.text:SetPoint("LEFT", 3, 0)
            gcd.time = PixelLayoutRegion(gcd.bar:CreateFontString(nil, "OVERLAY")); gcd.time:SetPoint("RIGHT", -3, 0)
            gcd.icon = PixelLayoutRegion(gcd.bar:CreateTexture(nil, "ARTWORK")); gcd.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark"); gcd.icon:SetTexCoord(.07,.93,.07,.93)
            samples.gcd = gcd
        end
        local detached = g.gcdBarDetached == true
        local w = detached and S(math.max(40, math.min(600, tonumber(g.gcdBarWidth) or 180))) or width
        local h = detached and S(math.max(4, math.min(50, tonumber(g.gcdBarHeight) or 12))) or height
        local cw, ch = canvas:GetWidth(), canvas:GetHeight()
        h = math.min(h, math.max(4, ch - S(16)))
        local minX = g.showGCDBarSpell ~= false and math.max(S(12), h + S(2)) or S(12)
        w = math.min(w, math.max(20, cw - minX - S(12)))
        gcd:SetSize(w, h)
        gcd:SetAlpha(detached and ((tonumber(g.gcdBarOpacity) or 100) / 100) or 1)
        gcd:ClearAllPoints()
        local x = detached and (cw * .5 + S(tonumber(g.gcdBarX) or 0) - w * .5) or S(12)
        local y = detached and (ch * .5 + S(tonumber(g.gcdBarY) or -180) - h * .5) or S(8)
        gcd:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", math.max(minX, math.min(cw - w - S(12), x)), math.max(S(8), math.min(ch - h - S(8), y)))
        gcd.bar:SetMinMaxValues(0, 1)
        gcd.bar:SetValue(.65)
        ApplyFont(gcd.text, math.max(7, math.min(S(12), h - S(2))))
        ApplyFont(gcd.time, math.max(7, math.min(S(12), h - S(2))))
        gcd.text:SetText("GCD")
        gcd.time:SetText("0.8")
        gcd.text:SetShown(g.showGCDBarSpell ~= false)
        gcd.time:SetShown(g.showGCDBarTime ~= false)
        gcd.icon:ClearAllPoints()
        gcd.icon:SetPoint("TOPRIGHT", gcd, "TOPLEFT", -S(2), 0)
        gcd.icon:SetSize(h, h)
        gcd.icon:SetShown(g.showGCDBarSpell ~= false)
        gcd:Show()
    elseif samples.gcd then samples.gcd:Hide() end
end

--- Cast progress: the fill width and the time text. The full refresh and the
--- animation tick share it; the fill's maximum width is kept on the castbar.
local function ApplyCastbarPreviewProgress(cast, g, key, S, animState, FormatCastbarPreviewTime)
    local fillMaxW = cast._msufPreviewFillMaxW
    if not fillMaxW then return end
    local castPct = animState and tonumber(animState.castPct) or 0.70
    if castPct < 0 then castPct = 0 elseif castPct > 1 then castPct = 1 end
    cast.fill:SetWidth(math.max(S(2), math.floor(fillMaxW * castPct + 0.5)))
    local castDuration = animState and tonumber(animState.castDuration) or 2.0
    local castCurrent = animState and (castDuration - (tonumber(animState.castRemaining) or 0)) or 1.4
    cast.time:SetText(FormatCastbarPreviewTime(g, key, castCurrent, castDuration))
end
-- One-region lists for the handle placer, kept on the region itself.
local function RegionList(region)
    local list = region._msufPreviewRegionList
    if not list then
        list = { region }
        region._msufPreviewRegionList = list
    end
    return list
end
--- The time text's handle around the text as it reads now: the refresh and
--- the animation tick (the cast time counts) share it.
local function PlaceCastbarTimeHandle(box, mock, canvas, UnitPreviewText, PlaceHandle)
    local time = mock.cast.time
    box.handleCastbarTime:SetSize(math.max(28, time:GetStringWidth() + 10), math.max(18, time:GetStringHeight() + 6))
    if not UnitPreviewText.PlaceHandleAroundRegions(box.handleCastbarTime, canvas,
        RegionList(time), 3, CASTBAR_TEXT_HANDLE_OPTS)
    then
        PlaceHandle(box.handleCastbarTime, time)
    end
end
local function ApplyCastbarPreviewDetails(box, mock, canvas, g, key, castBarH, scw, S, max, min, floor, fr, fg, fb, TR, ApplyPreviewFont, CastbarShowIcon,
    CastbarShowText, ReadCastbarNum, FormatCastbarPreviewTime, UnitPreviewText, PlaceHandle, animState)
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
    mock.cast._msufPreviewFillMaxW = fillMaxW
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
        local spellName = ShortenCastbarPreviewSpellName(key, TR((key == "boss" and "Celestial Ruin") or (key == "arena" and "Greater Pyroblast") or "Arcane Surge"))
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
            RegionList(mock.cast.text), 3, CASTBAR_TEXT_HANDLE_OPTS)
        then
            PlaceHandle(box.handleCastbarText, mock.cast.text)
        end
    else
        box.handleCastbarText:Hide()
    end
    local showTargetName = (key == "target" and g.castbarTargetShowTargetName == true)
        or (key == "focus" and g.castbarFocusShowTargetName == true)
        or (key == "boss" and g.showBossCastTargetName == true)
        or (key == "arena" and g.showArenaCastTargetName == true)
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
        local targetPosition = NormalizeCastbarPreviewTextPos(CastbarPreview.ReadString(g, key, "TargetNamePosition",
            "bossCastTargetNamePosition", "BELOW"), "BELOW")
        local targetJustify = NormalizeCastbarPreviewJustify(CastbarPreview.ReadString(g, key, "TargetNameAlign", "bossCastTargetNameAlign", "RIGHT"), "RIGHT")
        -- Runtime sizes and anchors this rect against frame.statusBar, whose
        -- width excludes external icons and the castbar outline. `surface` is
        -- the Unit Preview equivalent; using mock.cast shifts LEFT/CENTER text.
        mock.cast.target:SetWidth(max(20, fillMaxW - S(4)))
        AnchorCastbarPreviewText(mock.cast.target, surface, targetPosition, targetX, targetY, targetJustify, S)
        box.handleCastbarTarget:SetSize(max(48, mock.cast.target:GetStringWidth() + 10), max(18, mock.cast.target:GetStringHeight() + 6))
        if not UnitPreviewText.PlaceHandleAroundRegions(box.handleCastbarTarget, canvas,
            RegionList(mock.cast.target), 3, CASTBAR_TEXT_HANDLE_OPTS)
        then
            PlaceHandle(box.handleCastbarTarget, mock.cast.target)
        end
    else
        mock.cast.target:SetText("")
        box.handleCastbarTarget:Hide()
    end
    local showTime = key == "boss" and g.showBossCastTime ~= false
        or (key == "arena" and g.showArenaCastTime ~= false)
        or (key == "target" and g.showTargetCastTime ~= false)
        or (key == "focus" and g.showFocusCastTime ~= false)
        or (key == "player" and g.showPlayerCastTime ~= false)
    mock.cast.time:SetShown(showTime)
    -- The live castbar sizes its time text whether or not it is shown (only
    -- the alpha follows the toggle), and the latency text copies that font.
    local timeSize = ReadCastbarNum(g, key, "TimeFontSize", "bossCastTimeFontSize", g.castbarTimeFontSize or g.fontSize or 14)
    if not timeSize or timeSize <= 0 then timeSize = g.fontSize or 14 end
    ApplyPreviewFont(mock.cast.time, max(7, S(timeSize)))
    ApplyCastbarPreviewProgress(mock.cast, g, key, S, animState, FormatCastbarPreviewTime)
    if showTime then
        local timeX, timeY = CastbarPreview.TimeOffsets(g, key)
        local tr, tg, tb = g[(detailPrefix or "") .. "TimeColorR"], g[(detailPrefix or "") .. "TimeColorG"], g[(detailPrefix or "") .. "TimeColorB"]
        if tr or tg or tb then mock.cast.time:SetTextColor(tr or fr, tg or fg, tb or fb, 1) else mock.cast.time:SetTextColor(fr, fg, fb, 1) end
        local timePosition = NormalizeCastbarPreviewTextPos(CastbarPreview.ReadString(g, key, "TimePosition", "bossCastTimePosition", "RIGHT"), "RIGHT")
        AnchorCastbarPreviewText(mock.cast.time, surface, timePosition, timeX, timeY, CastbarPreviewJustifyForPosition(timePosition), S)
        PlaceCastbarTimeHandle(box, mock, canvas, UnitPreviewText, PlaceHandle)
    else
        box.handleCastbarTime:Hide()
    end
    mock.cast._msufTimeHandleShown = showTime
    ApplyCastbarFeatureSamples(mock, canvas, surface, g, key, fillMaxW, math.max(1, castBarH - frameInset * 2), S, ApplyPreviewFont, TR,
        max(7, S(timeSize)))
end

local function AnimatedPreviewData(st, data, powerFrac)
    local box = st.box
    local animState = UnitPreviewAnimationState(box, 1, st.key)
    local animHp = animState and tonumber(animState.hpPct)
    local animPower = animState and tonumber(animState.powerPct)
    if animHp then
        if animHp < 0 then animHp = 0 elseif animHp > 1 then animHp = 1 end
        if animPower == nil then animPower = powerFrac end
        if animPower < 0 then animPower = 0 elseif animPower > 1 then animPower = 1 end
        powerFrac = animPower
        data = CopyPreviewAnimationData(box, data, animHp, powerFrac)
    end
    return data, powerFrac, animState
end
local BODY_ALIASES = {
    healthBar = "hpBar", hpBar = "hpBar", hpBG = "hpBarBG", healthBackgroundBar = "healthBackgroundBar",
    powerBG = "powerBarBG", nameText = "nameText", totInlineSep = "totInlineSep", totInlineText = "totInlineText",
    hpTextLeft = "hpTextLeft", hpTextCenter = "hpTextCenter", hpText = "hpText", hpTextPct = "hpTextPct",
    powerTextLeft = "powerTextLeft", powerTextCenter = "powerTextCenter", powerText = "powerText", powerTextPct = "powerTextPct",
    raidGroupNameText = "raidGroupNameText", portrait = "MSUFPortraitHolder", detachedPower = "targetPowerBar",
    healPred = "incomingHealBar", absorb = "absorbBar", healAbsorb = "healAbsorbBar",
}
local STATUS_REGIONS = {
    raidmarker = "raidTargetIcon", leader = "leaderIcon", assist = "assistIcon", elite = "eliteIcon",
    bossNumber = "bossNumberText", statusAFKTimer = "statusAFKTimerText",
    level = "levelText", raceText = "raceText", classText = "classStatusText", statusCombat = "combatStateIndicatorIcon",
    statusResting = "restingIndicatorIcon", statusIncomingRes = "incomingResIndicatorIcon", statusPvp = "pvpIndicatorIcon",
    statusText = "_msufScene_statusText", statusGhostText = "_msufScene_statusGhostText", statusAFKText = "_msufScene_statusAFKText", statusDNDText = "_msufScene_statusDNDText",
    statusPetHappiness = "petHappinessIndicatorHolder", statusThreat = "threatIndicatorHolder", statusPetXP = "petXPBar", stance = "stanceIndicatorText",
}
local function AliasScene(mock, frame)
    mock._body = frame
    for alias, field in pairs(BODY_ALIASES) do mock[alias] = frame[field] end
    mock.texLayers = frame._msufTexLayers
    mock.bg = frame.hpBarBG
    if mock.portrait then mock.portrait.tex = frame.portrait end
    if mock.detachedPower then
        mock.detachedPower.bg = frame.powerBarBG
        mock.detachedPower.fill = frame.targetPowerBar:GetStatusBarTexture()
        mock.detachedPower.edge = frame.targetPowerBar._msufDetachedShapeEdge
    end
    mock.hp = frame.hpBar and frame.hpBar:GetStatusBarTexture()
    mock.power = frame.targetPowerBar and frame.targetPowerBar:GetStatusBarTexture()
    -- Legacy interaction keys without a live region share one hidden sentinel, never a second painted text.
    local sentinel = mock._emptyText
    if not sentinel then
        sentinel = PixelLayoutRegion(mock:CreateFontString(nil, "OVERLAY"))
        sentinel:Hide()
        mock._emptyText = sentinel
    end
    for _, key in pairs({ "nameText", "totInlineSep", "totInlineText", "hpTextLeft", "hpTextCenter", "hpText", "hpTextPct",
        "powerTextLeft", "powerTextCenter", "powerText", "powerTextPct", "raidGroupNameText" }) do
        mock[key] = mock[key] or sentinel
    end
    for key, field in pairs(STATUS_REGIONS) do
        local region = frame[field]
        mock.icons[key] = region
        if region and region.GetObjectType and region:GetObjectType() == "FontString" then region.txt = region end
    end
    if frame.threatIndicatorHolder then
        frame.threatIndicatorHolder.txt, frame.threatIndicatorHolder.plate = frame.threatIndicatorText, frame.threatIndicatorPlate
    end
    if frame.petHappinessIndicatorHolder then frame.petHappinessIndicatorHolder.tex = frame.petHappinessIndicatorIcon end
    mock._msufBossTargetIndicator = frame._msufBossTargetIndicator
end

local Stage = {}

--- Resolves deps, the previewed unit, its config, live or mock data and the
--- runtime specs, then refreshes the bound menu controls and the title.
function Stage.ResolveInputs(st)
    local Deps, RenderState, box, reason = st.D, st.R, st.box, st.reason
    local TR, PortraitStyleGet, max, min, abs, floor, format, TEX_W8 = Deps.TR, Deps.PortraitStyleGet, Deps.max, Deps.min, Deps.abs, Deps.floor, Deps.format, Deps.TEX_W8
    local ApplyPreviewFont, CastbarEnabled, ReadCastbarSize = Deps.ApplyPreviewFont, Deps.CastbarEnabled, Deps.ReadCastbarSize
    local CastbarOffsetFields, CastbarDetached, CanDetachPowerBarKey = Deps.CastbarOffsetFields, Deps.CastbarDetached, Deps.CanDetachPowerBarKey
    local ClampPreviewLayer, SetTex, ReadPowerBarHeight, PlaceHandle = Deps.ClampPreviewLayer, Deps.SetTex, Deps.ReadPowerBarHeight, Deps.PlaceHandle
    local UnitPreviewText, UnitPreviewTextMovesTogether, SetShownSafe = Deps.UnitPreviewText, Deps.UnitPreviewTextMovesTogether, Deps.SetShownSafe
    local ApplyPreviewLayerVisibility, ApplyPreviewTransparency = Deps.ApplyPreviewLayerVisibility, Deps.ApplyPreviewTransparency
    local RefreshHandleSelectionVisuals, Auras = Deps.RefreshHandleSelectionVisuals, Deps.Auras
    local panel = box._msufPanel
    local UNIT_DATA = Deps.UNIT_DATA or {}
    local UNIT_LABELS = Deps.UNIT_LABELS or {}
    local key = Deps.CurrentPanelKey(panel)
    local conf, g = Deps.UnitDB(key)
    --- Guides are setting-backed, unlike the other ephemeral preview layers.
    --- Re-read them on every visible preview refresh so a factory reset or
    --- profile switch cannot leave the already-built layer rail stale.
    if type(box.layerVisibility) == "table" then
        box.layerVisibility.guides = g.unitPreviewGuidesEnabled == true
    end
    -- Live snapshot first so the preview mirrors the real frame's current
    -- state (exact name/class/HP/power); stylized mock only as fallback.
    box._playerManaSourcePreviewActive = key == "player"
        and PreviewHelpers.PlayerManaSourceActive
        and PreviewHelpers.PlayerManaSourceActive(conf) or false
    local data = (Deps.LiveUnitData and Deps.LiveUnitData(key, box._playerManaSourcePreviewActive))
        or UNIT_DATA[key] or UNIT_DATA.player or {}
    local root = box._unitSceneRoot
    if not root then
        root = MSUF.GF.NewPreviewScene(box.mock)
        box._unitSceneRoot = root
    end
    root:Activate()
    local scene = root:Unit(key)
    if not scene then return false end
    if box._unitScene and box._unitScene ~= scene then box._unitScene:Hide() end
    box._unitScene = scene
    local sample = box._unitSample or {}
    box._unitSample = sample
    for field in pairs(sample) do sample[field] = nil end
    for field, value in pairs(data) do sample[field] = value end
    sample.player = data.isPlayer == true
    sample.reaction = data.reactionKind
    sample.level = data.level == "??" and -1 or tonumber(data.level)
    sample.absorb = data.absorb and data.absorb > 0
        and data.absorb / (data.hpMax or MSUF.UF.UnitScene.HEALTH_MAX)
        or MSUF.UF.UnitScene.SAMPLES[key].absorb or 0
    sample.powerType = data.powerType or MSUF.UFPreview.Model.POWER_TYPES[data.powerToken]
    if key == "target" and Deps.LiveUnitData then
        local inline = Deps.LiveUnitData("targettarget")
        if inline then sample.inline = inline.name end
    end
    sample.statusSelection = MSUF.UFPreview.GetStatusPreviewMode() == "all" and "all"
        or MSUF.UFPreview.selectedStatusId or "raidmarker"
    if key ~= "boss" and (sample.statusSelection == "elite" or sample.statusSelection == "all")
        and sample.classification ~= "elite" and sample.classification ~= "rareelite"
        and sample.classification ~= "rare" and sample.classification ~= "worldboss" then
        sample.classification = "elite"
    end
    local stance = MSUF.UFStance
    sample.stance = key == "player" and stance and stance.PreviewText and stance.PreviewText() or nil
    sample.leader, sample.assist, sample.combat, sample.resting, sample.incomingRes = true, true, true, true, true
    sample.frameEffect, sample.frameEffectLayer, sample.auraStyleKey = Auras.SampleEffect(key)
    sample.auraForceStandard = box._msuf2ColorPainterForceAuras == true
    sample.bossTargetPreview = true
    sample.raidTarget, sample.raidGroup, sample.pvp = 8, 2, "Alliance"
    root:SetClock(box._animationEnabled == true and box._animationElapsed or nil, true)
    scene.auraSampleCount = 4
    scene.level = (box.canvas:GetFrameLevel() or 0) + 6
    scene:Frame():SetFrameLevel(scene.level)
    local spec = scene:Compile()
    if data.live and spec.portrait and spec.portrait.enabled and spec.portrait.render ~= "CLASS" then
        local snapshot = box._portraitSnapshot
        if not snapshot then
            snapshot = PixelLayoutRegion(box.mock:CreateTexture(nil, "ARTWORK"))
            snapshot:Hide()
            box._portraitSnapshot = snapshot
        end
        if type(_G.SetPortraitTexture) == "function" then
            snapshot:SetTexture(nil)
            _G.SetPortraitTexture(snapshot, data.liveUnit)
            local art = snapshot:GetTexture()
            if _G.issecretvalue(art) ~= true and (type(art) == "number" or type(art) == "string") then sample.portraitTexture = art end
        end
    end
    scene:SetSample(sample, true)
    scene:Show()
    AliasScene(box.mock, scene:Frame())
    local runtimeSpec = scene:Frame().MSUFSpec
    local runtimePower = runtimeSpec and runtimeSpec.power
    local runtimeStatus = runtimeSpec and runtimeSpec.status
    local runtimeText = runtimeSpec and runtimeSpec.text
    local runtimeClassPower = runtimeSpec and runtimeSpec.classPower
    box.key = key
    if Deps.SyncLiveStateDriver then Deps.SyncLiveStateDriver(box, key) end
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
    st.ApplyPreviewFont, st.ApplyPreviewLayerVisibility, st.ApplyPreviewTransparency, st.Auras, st.CanDetachPowerBarKey, st.CastbarDetached, st.CastbarEnabled, st.CastbarOffsetFields = ApplyPreviewFont, ApplyPreviewLayerVisibility, ApplyPreviewTransparency, Auras, CanDetachPowerBarKey, CastbarDetached, CastbarEnabled, CastbarOffsetFields
    st.ClampPreviewLayer, st.PlaceHandle, st.PortraitStyleGet, st.ReadCastbarSize, st.ReadPowerBarHeight, st.RefreshHandleSelectionVisuals, st.SetShownSafe, st.SetTex = ClampPreviewLayer, PlaceHandle, PortraitStyleGet, ReadCastbarSize, ReadPowerBarHeight, RefreshHandleSelectionVisuals, SetShownSafe, SetTex
    st.TEX_W8, st.TR, st.UNIT_DATA, st.UnitPreviewText, st.UnitPreviewTextMovesTogether, st.abs, st.conf, st.data = TEX_W8, TR, UNIT_DATA, UnitPreviewText, UnitPreviewTextMovesTogether, abs, conf, data
    st.floor, st.format, st.g, st.key, st.max, st.min, st.runtimeClassPower, st.runtimePower = floor, format, g, key, max, min, runtimeClassPower, runtimePower
    st.runtimeSpec, st.runtimeStatus, st.runtimeText = runtimeSpec, runtimeStatus, runtimeText
    return true
end

--- Canvas size, frame size, portrait side/placement/size/border and castbar
--- size/offsets, plus the boss border inset.
function Stage.ResolveFrameGeometry(st)
    local Auras, CastbarDetached, CastbarEnabled, CastbarOffsetFields, PortraitStyleGet, RenderState, ReadCastbarSize, box = st.Auras, st.CastbarDetached, st.CastbarEnabled, st.CastbarOffsetFields, st.PortraitStyleGet, st.R, st.ReadCastbarSize, st.box
    local conf, floor, g, key, max, runtimeSpec = st.conf, st.floor, st.g, st.key, st.max, st.runtimeSpec
    local canvas = box.canvas
    local cw = canvas:GetWidth() or 600
    local ch = canvas:GetHeight() or 180
    if cw <= 1 then cw = 600 end
    if ch <= 1 then ch = 180 end
    local w = tonumber(runtimeSpec and runtimeSpec.width) or tonumber(conf.width or conf.frameWidth) or ((key == "boss" or key == "arena") and 180 or (key == "focus" and 180 or 275))
    local h = tonumber(runtimeSpec and runtimeSpec.height) or tonumber(conf.height or conf.frameHeight) or ((key == "boss" or key == "arena") and 30 or (key == "focus" and 30 or 40))
    w, h = RenderState.ClampUnitPreviewSize(w, h)
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
    -- Placement/geometry mirrors of the live spec. Parked on the box because the
    -- later stages (portrait, power bar, overlays) read them from there.
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
        box._runtimeAppliedPortraitW, box._runtimeAppliedPortraitH = RenderState.RuntimeAppliedPortraitSizeForPreviewKey(key)
        if tonumber(box._runtimeAppliedPortraitW) and box._runtimeAppliedPortraitW > 0 then
            box._runtimePortraitW = box._runtimeAppliedPortraitW
        end
        if tonumber(box._runtimeAppliedPortraitH) and box._runtimeAppliedPortraitH > 0 then
            box._runtimePortraitH = box._runtimeAppliedPortraitH
        end
    else
        box._runtimeAppliedPortraitW, box._runtimeAppliedPortraitH = nil, nil
    end
    box._runtimePortraitBorderStyle = (runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.border and runtimeSpec.portrait.border.style)
        or PortraitStyleGet(key, "portraitBorderStyle", "NONE") or "NONE"
    box._runtimePortraitBorderThickness = 0
    box._runtimePortraitBorderFill = false
    if hasPortrait and box._runtimePortraitBorderStyle ~= "NONE" then
        box._runtimePortraitBorderThickness = max(1, tonumber(runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.border
            and runtimeSpec.portrait.border.thickness) or tonumber(PortraitStyleGet(key, "portraitBorderThickness", 2)) or 2)
        box._runtimePortraitBorderFill = (runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.border and runtimeSpec.portrait.border.fill == true)
            or (not (runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.border) and PortraitStyleGet(key, "portraitFillBorder", false) == true)
    end
    local castEnabled = runtimeSpec and runtimeSpec.castbar and runtimeSpec.castbar.enabled == true
    if not (runtimeSpec and runtimeSpec.castbar) then castEnabled = CastbarEnabled(key, g) end
    if box._msuf2ColorPainterForceCastbar == true then castEnabled = true end
    local castW, castBarH = ReadCastbarSize(key, g, w, (key == "boss" or key == "arena") and 12 or 18)
    local castXKey, castYKey, castDefX, castDefY = CastbarOffsetFields(key)
    local castOffsetX = castXKey and tonumber(g[castXKey]) or nil
    local castOffsetY = castYKey and tonumber(g[castYKey]) or nil
    if castOffsetX == nil then castOffsetX = tonumber(castDefX) or 0 end
    if castOffsetY == nil then castOffsetY = tonumber(castDefY) or 0 end
    local castDetached = castEnabled and CastbarDetached(key, g)
    local castPreviewVisible = castEnabled and PreviewLayerWanted(box, "castbar")
    -- Projected position of a detached castbar, from the live layout.
    box._detachedCastProjectedX, box._detachedCastProjectedY = nil, nil
    if castDetached and type(RenderState.DetachedCastbarOffsetForPreviewKey) == "function" then
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
        box._bossBorderInset = max(1, floor((tonumber(runtimeSpec.border.thickness) or 1) + 0.5))
    end
    box._bossCastbarGap = 3
    st.canvas, st.castBarH, st.castDetached, st.castEnabled, st.castOffsetX, st.castOffsetY, st.castPreviewVisible, st.castW = canvas, castBarH, castDetached, castEnabled, castOffsetX, castOffsetY, castPreviewVisible, castW
    st.ch, st.cw, st.h, st.hasPortrait, st.mode, st.w = ch, cw, h, hasPortrait, mode, w
end

--- Class power preview spec, embedded/attached/detached power bar geometry,
--- combat animation state and the detached bar width/height.
function Stage.ResolvePowerGeometry(st)
    local CanDetachPowerBarKey, Deps, ReadPowerBarHeight, box, conf, data, floor, key = st.CanDetachPowerBarKey, st.D, st.ReadPowerBarHeight, st.box, st.conf, st.data, st.floor, st.key
    local max, runtimeClassPower, runtimePower, w = st.max, st.runtimeClassPower, st.runtimePower, st.w
    local bars = EnsureDB().bars or {}
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
            local copy = box._msufPreviewClassData or {}
            box._msufPreviewClassData = copy
            for k in pairs(copy) do copy[k] = nil end
            for k, v in pairs(data) do copy[k] = v end
            copy.class = tostring(previewClass):upper()
            data = copy
        end
    end
    local powerAllowed = runtimePower and runtimePower.enabled == true
    if runtimePower == nil then powerAllowed = Deps.ReadPowerBarEnabled(conf, key) end
    local detachedPower = CanDetachPowerBarKey(key) and powerAllowed and ((runtimePower and runtimePower.detached == true)
        or (runtimePower == nil and conf.powerBarDetached == true))
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
    if key == "player" and classPowerPreviewSpec then classPowerOn = bars.showClassPower ~= false and classPowerPreviewSpec.enabled ~= false
        and classPowerPreviewSpec.mode ~= "none" end
    local powerFrac = tonumber(data.power) or 1
    if not detachedPower and key ~= "player" and data.live ~= true then powerFrac = 1 end
    if powerFrac < 0 then powerFrac = 0 elseif powerFrac > 1 then powerFrac = 1 end
    -- The animation tick rebuilds the animated data from these two.
    st.baseData, st.basePowerFrac = data, powerFrac
    local animState
    data, powerFrac, animState = AnimatedPreviewData(st, data, powerFrac)
    local displayPowerToken = box._playerManaSourcePreviewActive and "MANA" or data.powerToken
    local cpH = classPowerOn and (tonumber(bars.classPowerHeight) or 4) or 0
    if cpH < 2 then cpH = 2 elseif cpH > 30 then cpH = 30 end
    local classPowerSegCount = CPPreview.SegmentCount(classPowerPreviewSpec)
    box._runtimeClassPowerW = classPowerOn and PreviewClassPowerWidth(bars, w, cpH, classPowerSegCount) or 0
    -- Augmentation no longer builds a composite surface: Ebon Might is rendered
    -- by the ordinary Player Power bar and Essence stays an ordinary Class
    -- Resource, so there is no second class row and no shared geometry. Only the
    -- power bar's *content* changes, which the render pass reads from
    -- _runtimePowerEbonMight below.
    box._runtimeClassPowerSecondarySpec = classPowerPreviewSpec and classPowerPreviewSpec.secondaryTimer
    box._runtimeClassPowerSecondaryOn = false
    box._runtimeClassPowerSecondaryH = 0
    box._runtimeAugCompositePreview = false
    box._runtimePowerEbonMight = key == "player"
        and classPowerOn
        and type(box._runtimeClassPowerSecondarySpec) == "table"
        and not box._playerManaSourcePreviewActive
        and bars.showEbonMight ~= false
        and classPowerPreviewSpec and classPowerPreviewSpec.key == "evoker_augmentation_ebon" or false
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
    box._runtimeDetachedPowerTextOnBar = (runtimePower and runtimePower.textOnDetached == true)
        or (runtimePower == nil and conf.detachedPowerBarTextOnBar == true)
    box._runtimeDetachedPowerShape = key == "player"
        and ResolvePreviewPowerShape((runtimePower and runtimePower.shape) or conf.detachedPowerBarShape or "FOLLOW_CLASS", bars.classPowerShape)
        or "BAR"
    local resolveDetachedPowerWidth = st.R.CPPreview.ResolveDetachedPowerWidth
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
    st.animState, st.bars, st.classPowerOn, st.classPowerPreviewSpec, st.classPowerSegCount, st.cpH, st.data, st.detachedH = animState, bars, classPowerOn, classPowerPreviewSpec, classPowerSegCount, cpH, data, detachedH
    st.detachedPower, st.detachedPowerInUnitPreview, st.detachedPowerManagedByClassPreview, st.displayPowerToken, st.powerFrac, st.wideW = detachedPower, detachedPowerInUnitPreview, detachedPowerManagedByClassPreview, displayPowerToken, powerFrac, wideW
end

--- Footprint pass one: name, health/power text slots, status indicators and
--- the boss target marker expand the fit rectangle.
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
        if region and region:IsShown() then
            local x, y, w, h = RegionRect(region, body)
            minX, maxX, minY, maxY = ExpandRect(minX, maxX, minY, maxY, x, y, x + w, y + h)
        end
    end
    for _, hosts in pairs({ body._msufGFFrameAuraPreviewHosts or {}, body._msufTexLayers or {} }) do
        for _, host in pairs(hosts) do
            if host:IsShown() then
                local x, y, w, h = RegionRect(host, body)
                minX, maxX, minY, maxY = ExpandRect(minX, maxX, minY, maxY, x, y, x + w, y + h)
            end
        end
    end
    local marker = body._msufBossTargetIndicator
    if marker and marker:IsShown() then
        local x, y, w, h = RegionRect(marker, body)
        minX, maxX, minY, maxY = ExpandRect(minX, maxX, minY, maxY, x, y, x + w, y + h)
    end
    st.minX, st.maxX, st.minY, st.maxY = minX, maxX, minY, maxY
end

function Stage.MeasureLayerFootprint(st)
    local Auras, PortraitStyleGet, RenderState, ReadPowerBarHeight, abs, bars, box, castBarH = st.Auras, st.PortraitStyleGet, st.R, st.ReadPowerBarHeight, st.abs, st.bars, st.box, st.castBarH
    local castDetached, castEnabled, castOffsetX, castOffsetY, castPreviewVisible, castW, classPowerOn, classPowerSegCount = st.castDetached, st.castEnabled, st.castOffsetX, st.castOffsetY, st.castPreviewVisible, st.castW, st.classPowerOn, st.classPowerSegCount
    local conf, cpH, detachedH, detachedPower, detachedPowerInUnitPreview, g, h, hasPortrait = st.conf, st.cpH, st.detachedH, st.detachedPower, st.detachedPowerInUnitPreview, st.g, st.h, st.hasPortrait
    local key, max, maxX, maxY, min, minX, minY, mode = st.key, st.max, st.maxX, st.maxY, st.min, st.minX, st.minY, st.mode
    local runtimePower, runtimeSpec, w, wideW = st.runtimePower, st.runtimeSpec, st.w, st.wideW
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
            cx = CPPreview.ContainerInsetX(bars) + (tonumber(bars.classPowerOffsetX) or 0)
            cy = h - 2 - cpH + (tonumber(bars.classPowerOffsetY) or 0)
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
            local cx = CPPreview.ContainerInsetX(bars) + (tonumber(bars.classPowerOffsetX) or 0)
            local cy = h - 2 - cpH + (tonumber(bars.classPowerOffsetY) or 0)
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
        elseif key == "boss" or key == "arena" then
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
                or (key == "arena" and g.showArenaCastTargetName == true)
            local targetPadX = showTargetName and (abs(RenderState.ReadCastbarNum(g, key, "TargetNameOffsetX", "bossCastTargetNameOffsetX", 0) or 0) + 96) or 0
            local targetPadY = showTargetName and (abs(RenderState.ReadCastbarNum(g, key, "TargetNameOffsetY", "bossCastTargetNameOffsetY", 1) or 1) + 24) or 0
            local detailPadX = max(
                abs(RenderState.ReadCastbarNum(g, key, "IconOffsetX", "bossCastIconOffsetX", 0)
                    or 0) + abs(RenderState.ReadCastbarNum(g, key, "IconSize", "bossCastIconSize", castBarH) or castBarH),
                abs(RenderState.ReadCastbarNum(g, key, "TextOffsetX", "bossCastTextOffsetX", 0) or 0) + 80,
                abs(RenderState.ReadCastbarNum(g, key, "TimeOffsetX", "bossCastTimeOffsetX", 0) or 0) + 46,
                targetPadX
            )
            local detailPadY = max(
                abs(RenderState.ReadCastbarNum(g, key, "IconOffsetY", "bossCastIconOffsetY", 0)
                    or 0) + abs(RenderState.ReadCastbarNum(g, key, "IconSize", "bossCastIconSize", castBarH) or castBarH),
                abs(RenderState.ReadCastbarNum(g, key, "TextOffsetY", "bossCastTextOffsetY", 0) or 0) + 24,
                abs(RenderState.ReadCastbarNum(g, key, "TimeOffsetY", "bossCastTimeOffsetY", 0) or 0) + 24,
                targetPadY
            )
            minX, maxX = min(minX, cLeft - detailPadX), max(maxX, cLeft + castW + detailPadX)
            minY, maxY = min(minY, cBottom - detailPadY), max(maxY, cBottom + castBarH + detailPadY)
        end
    end
    local arenaTrinket = MenuState.ArenaTrinketPreview
    if key == "arena" and arenaTrinket and PreviewLayerWanted(box, "trinket") then
        minX, maxX, minY, maxY = arenaTrinket.Footprint(minX, maxX, minY, maxY, w, h, ExpandAnchoredRect)
    end
    local auraPreviewState = st.box.mock._body._msufSceneAuraLanes
    local auraFootprintState = false
    for kind, lane in pairs(auraPreviewState or {}) do
        local layer = (kind == "buff" or kind == "debuff") and kind or "auras"
        if lane.enabled and lane.max > 0 and PreviewLayerWanted(box, layer) then auraFootprintState = true end
    end
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
    st.auraPreviewState, st.maxX, st.maxY, st.minX, st.minY, st.wideW = auraPreviewState, maxX, maxY, minX, minY, wideW
end

--- Fit/manual zoom, the S() scaler, frame levels, bar textures and the mock
--- body placement on the canvas.
function Stage.ResolveScaleAndLevels(st)
    local ClampPreviewLayer, RenderState, SetTex, TEX_W8, bars, box, canvas, ch = st.ClampPreviewLayer, st.R, st.SetTex, st.TEX_W8, st.bars, st.box, st.canvas, st.ch
    local conf, cw, floor, format, g, h, key, max = st.conf, st.cw, st.floor, st.format, st.g, st.h, st.key, st.max
    local maxX, maxY, min, minX, minY, runtimePower, runtimeSpec, runtimeStatus = st.maxX, st.maxY, st.min, st.minX, st.minY, st.runtimePower, st.runtimeSpec, st.runtimeStatus
    local runtimeText, w, wideW = st.runtimeText, st.w, st.wideW
    local centerX = ((minX + maxX) * 0.5) - (w * 0.5)
    local centerY = ((minY + maxY) * 0.5) - (h * 0.5)
    local runtimeScale = RenderState.RuntimeVisualScaleForPreviewKey(key, canvas)
    box._mockCastRuntimeScale = RenderState.RuntimeCastbarVisualScaleForPreviewKey(key, canvas)
    box._mockCastFrameScale = runtimeScale > 0 and (box._mockCastRuntimeScale / runtimeScale) or 1
    local autoScale = min(1.0, (cw - 60) / max(max(wideW, maxX - minX) * runtimeScale, 1), (ch - 42) / max(max(h, maxY - minY) * runtimeScale, 1))
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
    if mock.sizeTag then mock.sizeTag:SetText(format("%d x %d", w, h)) end
    if mock.bounds then mock.bounds:SetFrameLevel(Layers.ElementLevel(30, 30, 31) + 16) end
    local castLayer = RenderState.ReadCastbarNum(g, key, "FrameLevelOffset", "bossCastFrameLevelOffset", 6)
    mock.cast:SetFrameLevel(Layers.ElementLevel(castLayer, 6, 0) + baseLevel + 4)
    mock.cast.icon:SetFrameLevel(Layers.ElementLevel(castLayer, 6, 7) + baseLevel + 4)
    mock.classPower:SetFrameLevel(Layers.ElementLevel(bars.classPowerFrameLevelOffset, 5, 0) + baseLevel + 4)
    mock.classPower.textOwner:SetFrameLevel(PreviewClassTextLevel(mock.classPower.textOwner, bars))
    st.fr, st.fg, st.fb = RenderState.FontColor()
    st.pr, st.pg, st.pb = RenderState.PowerColor(st.displayPowerToken)
    st.powerH = S(runtimePower and runtimePower.height or 0)
    st.powerEnabled = runtimePower and runtimePower.enabled == true
    st.S, st.baseLevel, st.centerX, st.centerY, st.detachedPowerBgTexture, st.detachedPowerTexture, st.mock = S, baseLevel, centerX, centerY, nil, nil, mock
    MSUF.UFPreviewCore.ApplyBoundsGuide(box, st.runtimeSpec.border and st.runtimeSpec.border.thickness or 1)
    st.scale, st.sw = scale, sw
end

--- colours and the background fill. RenderHealth lays the bar out first and
--- passes fullRefresh: it has just written the fill, the following heal
--- prediction and the heal absorb width, so only the animation tick rewrites
--- those here.
function Stage.RenderClassPowerSegments(st)
    local ApplyPreviewFont, RenderState, S, bars, cpH, fb, fg, floor = st.ApplyPreviewFont, st.R, st.S, st.bars, st.cpH, st.fb, st.fg, st.floor
    local fr, g, max, mock = st.fr, st.g, st.max, st.mock
    local cp, gap, segSpace, slot, startX = st.cp, st.gap, st.segSpace, st.slot, st.startX
        local xPos, prevBoundary = 0, 0
        cp.runeOrder = cp.isRune and RenderState.CPPreview.BuildRuneOrder(cp, bars, cp.preview) or nil
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
                cp.fill = cp.rune and ((cp.rune.elapsed or 0) / (cp.rune.total or 1)) or RenderState.CPPreview.FillForSegment(cp.preview, i, cp.animatedValue)
                cp.drawW = segW
                cp.mode = cp.preview and cp.preview.mode
                if (cp.mode == "continuous" or cp.mode == "timer_bar" or cp.mode == "stagger" or cp.mode == "aura_single" or cp.mode == "fractional")
                    and cp.fill > 0 and cp.fill < 1 then
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
                cp.charged = RenderState.CPPreview.IsCharged(cp.preview, bars, i)
                if cp.charged then
                    cp.sr, cp.sg, cp.sb = RenderState.CPPreview.ResolveColor("CHARGED", 0.60, 0.20, 0.80)
                elseif cp.isFull then
                    cp.sr, cp.sg, cp.sb = cp.fullR, cp.fullG, cp.fullB
                else
                    cp.sr, cp.sg, cp.sb = RenderState.CPPreview.ResolveSlotColor(bars, cp.token, i, cp.r, cp.g, cp.b)
                end
                if cp.preview and cp.preview.threshold and cp.fill > 0
                    and i > cp.preview.threshold then cp.sr, cp.sg, cp.sb = RenderState.CPPreview.ResolveColor(cp.preview.thresholdToken,
                    cp.sr, cp.sg, cp.sb) end
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
                        cp.runeText = RenderState.CPPreview.FormatSeconds(cp.rune.remaining)
                        if cp.runeText ~= "" then
                            ApplyPreviewFont(runeText, cp.runeTextSize)
                            cp.tr, cp.tg, cp.tb = RenderState.CPPreview.ResolveTextColor(fr or 1, fg or 1, fb or 1)
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
end

-- Region lists and placement options reused by every text handle placement,
-- so neither a repaint nor an animation tick allocates them.
local PLAIN_HANDLE_OPTIONS = {}
local VALUE_TEXT_HANDLE_FIELDS = {
    hp = { "hpLeft", "hpCenter", "hpRight" },
    power = { "powerLeft", "powerCenter", "powerRight" },
}
local function HandleRegionList(box, field, a, b, c)
    return PreviewHelpers.CachedRegionList(box, "_msufTextHandleRegionLists", field, a, b, c)
end
local function TextHandleOptions(box, scale)
    local opts = box._msufTextHandleOptions
    if not opts then
        opts = { fitText = true, useScaledRect = true }
        box._msufTextHandleOptions = opts
    end
    opts.coordinateScale = scale
    return opts
end
local function PlaceTextSlotHandle(st, handle, region, field)
    if not handle then return end
    if not (region and region.IsShown and region:IsShown()) then
        handle:Hide()
        return
    end
    local max, box = st.max, st.box
    local w = (region.GetStringWidth and region:GetStringWidth()) or region:GetWidth() or 36
    local h = (region.GetStringHeight and region:GetStringHeight()) or region:GetHeight() or 12
    handle:SetSize(max(26, w + 10), max(18, h + 6))
    if not st.UnitPreviewText.PlaceHandleAroundRegions(handle, st.canvas, HandleRegionList(box, field, region), 3,
        TextHandleOptions(box, st.scale)) then st.PlaceHandle(handle, region) end
end
local function PlaceValueTextHandles(st, kind, together, mainHandle, leftHandle, centerHandle, rightHandle, leftRegion, centerRegion, rightRegion)
    local box = st.box
    if together then
        st.SetShownSafe(leftHandle, false)
        st.SetShownSafe(centerHandle, false)
        st.SetShownSafe(rightHandle, false)
        if st.UnitPreviewText.PlaceHandleAroundRegions(mainHandle, st.canvas, HandleRegionList(box, kind, leftRegion, centerRegion, rightRegion), 3,
            TextHandleOptions(box, st.scale)) then return end
        if not ((leftRegion and leftRegion:IsShown()) or (centerRegion and centerRegion:IsShown()) or (rightRegion and rightRegion:IsShown())) then
            mainHandle:Hide()
            return
        end
        local max = st.max
        mainHandle:SetSize(max(46, rightRegion:GetStringWidth() + 10), max(18, rightRegion:GetStringHeight() + 6))
        st.PlaceHandle(mainHandle, rightRegion)
        return
    end
    if mainHandle then mainHandle:Hide() end
    local fields = VALUE_TEXT_HANDLE_FIELDS[kind]
    PlaceTextSlotHandle(st, leftHandle, leftRegion, fields[1])
    PlaceTextSlotHandle(st, centerHandle, centerRegion, fields[2])
    PlaceTextSlotHandle(st, rightHandle, rightRegion, fields[3])
end
--- Value text handles around the texts as they read now: the full refresh
--- resolves reverse order and moves-together once, the animation tick refits
--- the handles after the values changed width.
function Stage.PlaceValueTextHandles(st)
    local box, mock = st.box, st.mock
    -- Under reverse order the configured left slot renders on the physical
    -- right FontString (and vice versa); pair each slot handle with the
    -- FontString that actually shows its content so drags edit visible text.
    if st.hpHandlesReversed then
        PlaceValueTextHandles(st, "hp", st.hpTextMovesTogether, box.handleHP, box.handleHPLeft, box.handleHPCenter, box.handleHPRight, mock.hpText,
            mock.hpTextCenter, mock.hpTextLeft)
    else
        PlaceValueTextHandles(st, "hp", st.hpTextMovesTogether, box.handleHP, box.handleHPLeft, box.handleHPCenter, box.handleHPRight, mock.hpTextLeft,
            mock.hpTextCenter, mock.hpText)
    end
    PlaceValueTextHandles(st, "power", st.powerTextMovesTogether, box.handlePower, box.handlePowerLeft, box.handlePowerCenter, box.handlePowerRight,
        mock.powerTextLeft, mock.powerTextCenter, mock.powerText)
end
function Stage.PlaceClassPowerTextHandle(st)
    local box, max, text = st.box, st.max, st.mock.classPower.text
    box.handleClassPowerText:SetSize(max(26, text:GetStringWidth() + 10), max(18, text:GetStringHeight() + 6))
    if not st.UnitPreviewText.PlaceHandleAroundRegions(box.handleClassPowerText, st.canvas, HandleRegionList(box, "classPowerText", text), 3,
        PLAIN_HANDLE_OPTIONS) then st.PlaceHandle(box.handleClassPowerText, text) end
end
--- Animation tick for the class resource: the animated value drives the
--- segment fills and the resource text; runes stay static in this preview.
function Stage.AnimateClassPower(st)
    local cp, RenderState = st.classPowerOn and st.cp, st.R
    if not (cp and cp.preview) or cp.isRune then return end
    local animState = st.animState
    cp.animatedValue = animState and RenderState.CPPreview.AnimatedValue and RenderState.CPPreview.AnimatedValue(cp.preview, animState.elapsed) or nil
    cp.isFull = cp.fullEnabled == true and RenderState.CPPreview.IsFull(cp.preview, cp.animatedValue)
    Stage.RenderClassPowerSegments(st)
    local text = st.mock.classPower.text
    if cp.textOn and cp.animatedValue ~= nil and (RenderState.CPPreview.ConfiguredTextForValue or RenderState.CPPreview.TextForValue) then
        text:SetText(RenderState.CPPreview.ConfiguredTextForValue
            and RenderState.CPPreview.ConfiguredTextForValue(st.bars, cp.preview, cp.animatedValue)
            or RenderState.CPPreview.TextForValue(cp.preview, cp.animatedValue))
        Stage.PlaceClassPowerTextHandle(st)
    end
end
--- Power backgrounds can follow the health colour (match health), so the
--- animation tick repaints them when that colour moves.
function Stage.RenderClassPower(st)
    local ApplyPreviewFont, PlaceHandle, RenderState, S, SetTex, TEX_W8, UnitPreviewText, animState = st.ApplyPreviewFont, st.PlaceHandle, st.R, st.S, st.SetTex, st.TEX_W8, st.UnitPreviewText, st.animState
    local bars, box, canvas, classPowerOn, classPowerPreviewSpec, classPowerSegCount, cpH, detachedPower = st.bars, st.box, st.canvas, st.classPowerOn, st.classPowerPreviewSpec, st.classPowerSegCount, st.cpH, st.detachedPower
    local fb, fg, floor, fr, g, max, mock, pb = st.fb, st.fg, st.floor, st.fr, st.g, st.max, st.mock, st.pb
    local pg, pr, scale, w = st.pg, st.pr, st.scale, st.w
    if classPowerOn then
        mock.classPower:Show()
        local cpW = box._runtimeClassPowerW or PreviewClassPowerWidth(bars, w, cpH, classPowerSegCount)
        mock.classPower:SetSize(S(cpW), max(2, S(cpH)))
        mock.classPower:ClearAllPoints()
        if box._runtimeAugCompositePreview == true then
            if detachedPower then
                if box._runtimeDetachedPowerAnchorMode == "LEGACY_TOPLEFT" then
                    mock.classPower:SetPoint("TOPLEFT", mock._body, "BOTTOMLEFT",
                        S(box._runtimeDetachedPowerX), S(box._runtimeDetachedPowerY))
                else
                    mock.classPower:SetPoint("TOP", mock._body, "BOTTOM",
                        S(box._runtimeDetachedPowerX), S(box._runtimeDetachedPowerY))
                end
            elseif box._runtimePowerEmbedded == true then
                mock.classPower:SetPoint("TOPLEFT", mock._body, "BOTTOMLEFT", 0,
                    S(cpH + 2 + box._runtimeClassPowerSecondaryH))
            else
                mock.classPower:SetPoint("TOPLEFT", mock._body, "BOTTOMLEFT", 0, S(-1))
            end
        else
            -- Same anchor as the live container (ClassPower Layout.Position).
            mock.classPower:SetPoint("TOPLEFT", mock._body, "TOPLEFT",
                S(CPPreview.ContainerInsetX(bars) + (tonumber(bars.classPowerOffsetX) or 0)),
                S((tonumber(bars.classPowerOffsetY) or 0) - 2))
        end
        local cp = box._msufClassPowerPreviewScratch
        if not cp then cp = {}; box._msufClassPowerPreviewScratch = cp end
        cp.preview = classPowerPreviewSpec
        cp.token = cp.preview and cp.preview.token
        cp.isRune = cp.preview and cp.preview.mode == "rune"
        cp.r, cp.g, cp.b = pr, pg, pb
        cp.animatedValue = animState and RenderState.CPPreview.AnimatedValue and RenderState.CPPreview.AnimatedValue(cp.preview, animState.elapsed) or nil
        if cp.token then cp.r, cp.g, cp.b = RenderState.CPPreview.ResolveBaseColor(cp.preview, bars, pr, pg, pb) end
        local fullEnabled, fullR, fullG, fullB = RenderState.CPPreview.ResolveFullColor(bars, cp.token, cp.r, cp.g, cp.b)
        cp.fullEnabled = fullEnabled == true
        cp.isFull = fullEnabled == true and RenderState.CPPreview.IsFull(cp.preview, cp.animatedValue)
        cp.fullR, cp.fullG, cp.fullB = fullR, fullG, fullB
        cp.filledAlpha = tonumber(bars.classPowerFilledAlpha) or 0.95
        if cp.filledAlpha < 0 then cp.filledAlpha = 0 elseif cp.filledAlpha > 1 then cp.filledAlpha = 1 end
        cp.emptyAlpha = tonumber(bars.classPowerEmptyAlpha) or 0.28
        if cp.emptyAlpha < 0 then cp.emptyAlpha = 0 elseif cp.emptyAlpha > 1 then cp.emptyAlpha = 1 end
        cp.bgAlpha = tonumber(bars.classPowerBgAlpha) or 0.30
        if cp.bgAlpha < 0 then cp.bgAlpha = 0 elseif cp.bgAlpha > 1 then cp.bgAlpha = 1 end
        cp.shape = NormalizePreviewClassPowerShape(bars.classPowerShape)
        cp.shapeInfo = PREVIEW_CLASS_POWER_SHAPES[cp.shape]
        cp.style = bars.slantedBarsEnabled ~= false and bars.slantedClassResources == true
            and "SLANTED" or "ROUNDED"
        cp.rounded = cp.shapeInfo == nil and (cp.style == "SLANTED"
            or (bars.roundedFramesEnabled == true and bars.roundedClassResources == true))
        UNIT_CP_ROUNDED_OPTS.style = cp.style
        if mock.classPower.SetBackdropColor then
            cp.bgr, cp.bgg, cp.bgb = RenderState.CPPreview.ColorOverride("classPowerBgColorOverrides", cp.token)
            mock.classPower:SetBackdropColor(cp.bgr or 0, cp.bgg or 0, cp.bgb or 0,
                (cp.shapeInfo or cp.rounded) and 0 or cp.bgAlpha)
            mock.classPower:SetBackdropBorderColor(0, 0, 0, (cp.shapeInfo or cp.rounded) and 0 or 1)
        end
        cp.segCount = CPPreview.SegmentCount(cp.preview)
        mock.classPower:EnsureSegmentSlots(cp.segCount)
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
        st.cp, st.slot, st.segSpace, st.gap, st.startX = cp, slot, segSpace, gap, startX
        Stage.RenderClassPowerSegments(st)
        --- Devourer's fragment separators. Its Soul Fragment maximum cannot be
        --- one pip per fragment, so the live bar notches the boundaries into a
        --- single continuous fill; mirror the same geometry here.
        local notches = mock.classPower.notches
        local shownNotches = 0
        if notches then
            local fragments = cp.shapeInfo and 0 or floor(tonumber(cp.preview and cp.preview.fragments) or 0)
            --- Separator keeps its literal width inside the space the fragments
            --- do not need and Pip gap spends the rest of it in proportion,
            --- exactly as on the live bar.
            local notchSep = tonumber(bars.classPowerTickWidth) or 1
            if notchSep < 0 then notchSep = 0 elseif notchSep > 4 then notchSep = 4 end
            local notchGap = tonumber(bars.classPowerGap) or 0
            if notchGap < 0 then notchGap = 0 elseif notchGap > 8 then notchGap = 8 end
            local notchW = 0
            if fragments >= 2 and previewW > fragments and (notchSep + notchGap) > 0 then
                local maxNotchW = floor((previewW - fragments) / (fragments - 1))
                if maxNotchW >= 1 then
                    local base = max(1, S(notchSep))
                    if base > maxNotchW then base = maxNotchW end
                    notchW = base + floor(((notchGap * (maxNotchW - base)) / 8) + 0.5)
                    if notchW > maxNotchW then notchW = maxNotchW end
                end
            end
            if fragments >= 2 and fragments <= 64 and notchW >= 1 then
                local reverse = bars.classPowerFillReverse == true
                local limit = previewW - notchW
                local notchH = max(1, S(cpH))
                for i = 1, fragments - 1 do
                    local notch = notches[i]
                    if not notch then
                        notch = PixelLayoutRegion(mock.classPower:CreateTexture(nil, "OVERLAY", nil, 6))
                        notch:SetTexture(TEX_W8)
                        notches[i] = notch
                    end
                    local nx = floor(((previewW * i) / fragments) - (notchW * 0.5) + 0.5)
                    if nx < 0 then nx = 0 elseif nx > limit then nx = limit end
                    if reverse then nx = limit - nx end
                    notch:ClearAllPoints()
                    notch:SetVertexColor(0, 0, 0, 1)
                    notch:SetSize(notchW, notchH)
                    notch:SetPoint("TOPLEFT", mock.classPower, "TOPLEFT", nx, 0)
                    notch:Show()
                    shownNotches = i
                end
            end
            for i = shownNotches + 1, #notches do notches[i]:Hide() end
        end
        if PreviewHelpers.ApplyRoundedClassPowerSurface then
            local roundedApplied = PreviewHelpers.ApplyRoundedClassPowerSurface(mock.classPower, cp.rounded,
                mock.classPower.segments, nil, cp.segCount,
                ScaleCastbarOutline(bars.classPowerOutline or 1, scale), UNIT_CP_ROUNDED_OPTS,
                cp.bgr or 0, cp.bgg or 0, cp.bgb or 0, cp.bgAlpha)
            if cp.rounded and not roundedApplied and mock.classPower.SetBackdropColor then
                mock.classPower:SetBackdropColor(cp.bgr or 0, cp.bgg or 0, cp.bgb or 0, cp.bgAlpha)
                mock.classPower:SetBackdropBorderColor(0, 0, 0, 1)
            end
        end
        local classTextOn = bars.classPowerShowText == true
            or (cp.preview and cp.preview.nativeDurationText == true)
        cp.textOn = classTextOn
        if classTextOn then
            local cpTextSize = S(tonumber(bars.classPowerFontSize) or 16)
            if cpTextSize < 7 then cpTextSize = 7 end
            ApplyPreviewFont(mock.classPower.text, cpTextSize)
            if cp.animatedValue ~= nil and (RenderState.CPPreview.ConfiguredTextForValue or RenderState.CPPreview.TextForValue) then
                mock.classPower.text:SetText(RenderState.CPPreview.ConfiguredTextForValue
                    and RenderState.CPPreview.ConfiguredTextForValue(bars, cp.preview, cp.animatedValue)
                    or RenderState.CPPreview.TextForValue(cp.preview, cp.animatedValue))
            else
                mock.classPower.text:SetText((cp.preview and cp.preview.previewText) or "3")
            end
            cp.tr, cp.tg, cp.tb = RenderState.CPPreview.ResolveTextColor(fr or 1, fg or 1, fb or 1)
            mock.classPower.text:SetTextColor(cp.tr, cp.tg, cp.tb, cp.runeTextAlpha)
            mock.classPower.text:ClearAllPoints()
            mock.classPower.text:SetPoint("CENTER", mock.classPower, "CENTER", S(tonumber(bars.classPowerTextOffsetX) or 0), S(tonumber(bars.classPowerTextOffsetY) or 0))
            mock.classPower.text:Show()
            Stage.PlaceClassPowerTextHandle(st)
        else
            mock.classPower.text:Hide()
            box.handleClassPowerText:Hide()
        end
        if box._runtimeClassPowerSecondaryOn == true then
            RenderPreviewSecondaryClassTimer(mock, box._runtimeClassPowerSecondarySpec,
                box._runtimeClassPowerSecondaryH, cpW, bars, RenderState, animState, S,
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
        if mock.classPower.notches then
            for i = 1, #mock.classPower.notches do mock.classPower.notches[i]:Hide() end
        end
        if mock.classPower.text then mock.classPower.text:Hide() end
        HidePreviewSecondaryClassTimer(mock)
        box.handleClassPower:Hide()
        box.handleClassPowerText:Hide()
    end
end

--- Power values: the embedded/attached bar's fill and the detached bar's fill.
--- The full refresh lays both bars out first; the animation tick repaints only
--- this.
function Stage.RenderCastbar(st)
    local ApplyPreviewFont, PlaceHandle, RenderState, S, TR, UnitPreviewText, animState, box = st.ApplyPreviewFont, st.PlaceHandle, st.R, st.S, st.TR, st.UnitPreviewText, st.animState, st.box
    local canvas, castBarH, castDetached, castOffsetX, castOffsetY, castPreviewVisible, castW, fb = st.canvas, st.castBarH, st.castDetached, st.castOffsetX, st.castOffsetY, st.castPreviewVisible, st.castW, st.fb
    local fg, floor, format, fr, g, key, max, min = st.fg, st.floor, st.format, st.fr, st.g, st.key, st.max, st.min
    local mock, powerH = st.mock, st.powerH
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
                PixelLayoutRegion(mock.cast, "SetBackdrop", {
                    bgFile = "Interface\\Buttons\\WHITE8X8",
                    edgeFile = "Interface\\Buttons\\WHITE8X8",
                    edgeSize = castEdge,
                    insets = { left = 0, right = 0, top = 0, bottom = 0 },
                })
            else
                PixelLayoutRegion(mock.cast, "SetBackdrop", { bgFile = "Interface\\Buttons\\WHITE8X8" })
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
            mock.cast:SetPoint("CENTER", mock._body, "CENTER", box._detachedCastBaseOffsetX, box._detachedCastBaseOffsetY)
        elseif key == "player" then
            mock.cast:SetPoint("BOTTOM", mock._body, "TOP", S(castOffsetX), S(castOffsetY))
        elseif key == "boss" or key == "arena" then
            mock.cast:SetPoint("TOPLEFT", mock._body, "BOTTOMLEFT",
                S(castOffsetX - box._bossBorderInset),
                S(castOffsetY - box._bossBorderInset - box._bossCastbarGap)
                    + (box._runtimePowerEmbedded == true and powerH or 0))
        else
            mock.cast:SetPoint("BOTTOMLEFT", mock._body, "TOPLEFT", S(castOffsetX), S(castOffsetY))
        end
        -- The live castbars tint through MSUF_ResolveCastbarColors: the custom RGB,
        -- else the palette choice. The preview asks the same function, so the two
        -- cannot drift and no colour is kept here.
        local resolveCastbarColors = _G.MSUF_ResolveCastbarColors
        if type(resolveCastbarColors) == "function" then
            local cr, cg, cb = resolveCastbarColors()
            mock.cast.fill:SetVertexColor(cr, cg, cb, 1)
        end
        ApplyCastbarPreviewDetails(box, mock, canvas, g, key, castBarH, scw, S, max, min, floor, fr, fg, fb, TR, ApplyPreviewFont, RenderState.CastbarShowIcon,
            RenderState.CastbarShowText, RenderState.ReadCastbarNum, RenderState.FormatCastbarPreviewTime, UnitPreviewText, PlaceHandle, animState)
        mock.cast.configKey = key
        ApplyCastbarPreviewRounded(mock.cast, g, castEdge, castBgR, castBgG, castBgB, castBgA)
        box.handleCastbar:SetSize(
            max(36, scw * (box._mockCastFrameScale or 1)),
            max(18, (sch + 8) * (box._mockCastFrameScale or 1)))
        PlaceHandle(box.handleCastbar, mock.cast)
    else
        mock.cast:Hide()
        if mock.cast._featureSamples and mock.cast._featureSamples.gcd then mock.cast._featureSamples.gcd:Hide() end
        if mock.cast.sizeTag then mock.cast.sizeTag:Hide() end
        box.handleCastbar:Hide()
        box.handleCastbarIcon:Hide()
        box.handleCastbarText:Hide()
        box.handleCastbarTarget:Hide()
        box.handleCastbarTime:Hide()
    end
end

--- Aura lanes, the boss target marker and every status indicator icon/text
--- with its handle.
function Stage.RenderSceneHandles(st, Preview)
    local box, mock = st.box, st.mock
    local body = mock._body
    st.hpTextOn = body.hpText and body.hpText:IsShown()
    st.powerTextOn = body.powerText and body.powerText:IsShown()
    st.showNamePreview = body.nameText and body.nameText:IsShown()
    st.statusLayerAvailable = false
    local auras = body._msufGFFrameAuraPreviewHosts or {}
    local handles = { buff = box.handleAuraBuffs, debuff = box.handleAuraDebuffs,
        custom1 = box.handleAuraCustom1, custom2 = box.handleAuraCustom2, custom3 = box.handleAuraCustom3, custom4 = box.handleAuraCustom4 }
    for key, handle in pairs(handles) do
        local host = auras[key]
        if key == "custom4" then
            local portrait = auras.defensivePortrait
            if not (portrait and portrait:IsShown()) then portrait = auras.targetDotPortrait end
            if portrait and portrait:IsShown() then host = portrait end
        end
        handle._msufAuraDragVisual = host
        if host and host:IsShown() then
            handle:SetSize(st.max(18, host:GetWidth() * st.scale + 8), st.max(18, host:GetHeight() * st.scale + 8))
            st.PlaceHandle(handle, host)
            handle:Show()
        else handle:Hide() end
    end
    local symbol = body._msufSceneDispelSymbol
    if box.handleDispelSymbol then
        box.handleDispelSymbol._msufAuraDragVisual = symbol
        if symbol and symbol:IsShown() then
            box.handleDispelSymbol:SetSize(st.max(18, symbol:GetWidth() * st.scale + 6), st.max(18, symbol:GetHeight() * st.scale + 6))
            st.PlaceHandle(box.handleDispelSymbol, symbol)
            box.handleDispelSymbol:Show()
        else box.handleDispelSymbol:Hide() end
    end
    st.box._previewDispelOverlayAvailable = body._msufSceneDispelOverlay and body._msufSceneDispelOverlay:IsShown()
    st.box._previewDispelSymbolAvailable = symbol and symbol:IsShown()
    for i, handle in pairs(box.texLayerHandles) do
        local holder = mock.texLayers and mock.texLayers[i]
        if holder and holder:IsShown() then
            handle:SetSize(st.max(18, holder:GetWidth() * st.scale + 6), st.max(18, holder:GetHeight() * st.scale + 6))
            st.PlaceHandle(handle, holder)
            handle:Show()
        else handle:Hide() end
    end
    for _, spec in pairs(st.D.STATUS_PREVIEW) do
        local region, handle = mock.icons[spec.id], box.statusHandles[spec.id]
        if region and region:IsShown() then
            st.statusLayerAvailable = true
            handle:SetSize(st.max(18, region:GetWidth() * st.scale + 6), st.max(18, region:GetHeight() * st.scale + 6))
            st.PlaceHandle(handle, region)
            handle:Show()
        else handle:Hide() end
    end
    if box.handleBossTarget then
        local marker = body._msufBossTargetIndicator
        if marker and marker:IsShown() then
            box.handleBossTarget:SetSize(marker:GetWidth() * st.scale + 8, marker:GetHeight() * st.scale + 8)
            st.PlaceHandle(box.handleBossTarget, marker)
            box.handleBossTarget:Show()
        else box.handleBossTarget:Hide() end
    end
    if mock.portrait and mock.portrait:IsShown() then
        box.handlePortrait:SetSize(mock.portrait:GetWidth() * st.scale + 6, mock.portrait:GetHeight() * st.scale + 6)
        st.PlaceHandle(box.handlePortrait, mock.portrait)
        box.handlePortrait:Show()
    else box.handlePortrait:Hide() end
    if st.detachedPower and mock.detachedPower then
        box.handleDetachedPower:SetSize(mock.detachedPower:GetWidth() * st.scale + 6, mock.detachedPower:GetHeight() * st.scale + 6)
        st.PlaceHandle(box.handleDetachedPower, mock.detachedPower)
        box.handleDetachedPower:Show()
    else box.handleDetachedPower:Hide() end
end

function Stage.RenderArenaTrinket(st)
    local painter, box = MenuState.ArenaTrinketPreview, st.box
    st.trinketAvailable = false
    if not painter then return end
    local available, icon = painter.Paint(st.mock, st.key, PreviewLayerWanted(box, "trinket"), st.S)
    st.trinketAvailable = available == true
    local handle = box.handleArenaTrinket
    if not handle then return end
    if icon then
        handle:SetSize(st.max(18, icon:GetWidth() + 8), st.max(18, icon:GetHeight() + 8))
        st.PlaceHandle(handle, icon)
    else
        handle:Hide()
    end
end

--- Layer availability for the layer rail, text handles, text focus, layer
--- visibility, transparency and handle selection visuals.
function Stage.FinalizeLayersAndHandles(st)
    local ApplyPreviewLayerVisibility, ApplyPreviewTransparency, PlaceHandle, RenderState, RefreshHandleSelectionVisuals, S, SetShownSafe, UnitPreviewText = st.ApplyPreviewLayerVisibility, st.ApplyPreviewTransparency, st.PlaceHandle, st.R, st.RefreshHandleSelectionVisuals, st.S, st.SetShownSafe, st.UnitPreviewText
    local UnitPreviewTextMovesTogether, auraPreviewState, box, canvas, castEnabled, classPowerOn, conf, h = st.UnitPreviewTextMovesTogether, st.auraPreviewState, st.box, st.canvas, st.castEnabled, st.classPowerOn, st.conf, st.h
    local hasPortrait, hpTextOn, key, max, mock, powerEnabled, powerTextOn, runtimeSpec = st.hasPortrait, st.hpTextOn, st.key, st.max, st.mock, st.powerEnabled, st.powerTextOn, st.runtimeSpec
    local scale, showNamePreview, statusLayerAvailable, w = st.scale, st.showNamePreview, st.statusLayerAvailable, st.w
    local available = box.layerAvailable or {}
    box.layerAvailable = available
    available.guides = true
    available.nameText = showNamePreview
    available.hpText = hpTextOn
    available.powerText = powerTextOn
    available.portrait = hasPortrait
    available.power = powerEnabled == true and box._runtimeAugCompositePreview ~= true
    available.classPower = classPowerOn
    available.castbar = castEnabled
    local function AuraAvailable(kind)
        local lane = auraPreviewState and auraPreviewState[kind]
        return lane and lane.enabled == true and lane.max > 0 or false
    end
    available.buff, available.debuff = AuraAvailable("buff"), AuraAvailable("debuff")
    available.auras = AuraAvailable("custom1") or AuraAvailable("custom2") or AuraAvailable("custom3")
        or AuraAvailable("custom4") or AuraAvailable("defensivePortrait") or AuraAvailable("targetDotPortrait")
    available.dispelOverlay = box._previewDispelOverlayAvailable == true
    available.dispelSymbol = box._previewDispelSymbolAvailable == true
    available.status = statusLayerAvailable
    available.trinket = st.trinketAvailable == true
    available.texLayer = conf.texLayerEnabled == true or conf.texLayer2Enabled == true or conf.texLayer3Enabled == true
    available.bounds = true
    for i = 1, #(box.layerButtons or {}) do
        local button = box.layerButtons[i]
        if button.key == "classPower" and button.SetShown then button:SetShown(key == "player") end
        if button.key == "trinket" and button.SetShown then button:SetShown(key == "arena") end
        if button.refresh then button:refresh() end
    end
    if box.LayoutLayerRail then box:LayoutLayerRail((box.GetWidth and box:GetWidth() or 0) - 24) end
    local nameHandleW = mock.nameText:GetStringWidth() + 10
    if mock.totInlineSep
        and mock.totInlineSep:IsShown() then nameHandleW = nameHandleW + mock.totInlineSep:GetStringWidth() + mock.totInlineText:GetStringWidth() + S(8) end
    box.handleName:SetSize(max(46, nameHandleW), max(18, mock.nameText:GetStringHeight() + 6))
    if not UnitPreviewText.PlaceHandleAroundRegions(box.handleName, canvas, HandleRegionList(box, "name", mock.nameText, mock.totInlineSep, mock.totInlineText),
        3, TextHandleOptions(box, scale)) then PlaceHandle(box.handleName, mock.nameText) end
    PlaceTextSlotHandle(st, box.handleRaidGroupName, mock.raidGroupNameText, "raidGroupName")
    st.hpHandlesReversed = RenderState.TextScopeGet(key, "hpTextReverse", false) == true
    st.hpTextMovesTogether = UnitPreviewTextMovesTogether(key, "hp")
    st.powerTextMovesTogether = UnitPreviewTextMovesTogether(key, "power")
    Stage.PlaceValueTextHandles(st)
    RenderState.ApplyPreviewTextFocus(box, canvas, mock)
    ApplyPreviewLayerVisibility(box)
    RefreshHandleSelectionVisuals(box)
end


--- Install render helpers onto the shared unit-preview object. View owns frame
--- construction; this module owns repeated visual composition.
-- Render.Install fills the shared render state in these stages, in order;
-- s carries the preview object, its deps, the render state and the values a
-- later stage reads.
local InstallStage = {}
function InstallStage.ClassPowerColors(s)
    local renderState = s.renderState
    local PowerColor = renderState.PowerColor
    local SharedCPPreview = MenuState.ClassPowerPreview or {}
    local function FallbackBase(_, _, r, g, b) return r or 1, g or 1, b or 1 end
    local function FallbackColor(_, r, g, b) return r or 1, g or 1, b or 1 end
    local function FallbackText(r, g, b) return r or 1, g or 1, b or 1 end
    local function FallbackFill(spec, index) return spec and index <= math.floor(tonumber(spec.value) or 0) and 1 or 0 end
    local function FallbackCombo(_, _, r, g, b) return r, g, b end
    local CPPreview = {
        BuildRuneOrder = SharedCPPreview.BuildRuneOrder or Fallbacks.Nil,
        ColorOverride = SharedCPPreview.ColorOverride or Fallbacks.Nil,
        FillForSegment = SharedCPPreview.FillForSegment or FallbackFill,
        FormatSeconds = SharedCPPreview.FormatSeconds or Fallbacks.Empty,
        IsCharged = SharedCPPreview.IsCharged or Fallbacks.False,
        IsFull = SharedCPPreview.IsFull or Fallbacks.False,
        ResolveComboColor = SharedCPPreview.ResolveComboColor or FallbackCombo,
        ResolveSlotColor = SharedCPPreview.ResolveSlotColor,
        ResolveFullColor = SharedCPPreview.ResolveFullColor,
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
        ConfiguredTextForValue = SharedCPPreview.ConfiguredTextForValue,
    }
    s.CPPreview = CPPreview
end
function InstallStage.PreviewFont(s)
    local deps = s.deps
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
            local db = EnsureDB()
            local general = db and db.general
            local fontKey = general and general.fontKey
            if type(fontPath) ~= "string" or fontPath == "" then
                local pathForKey = _G.MSUF_ResolveFontKeyPath or _G.MSUF_GetFontPathForKey or (MSUF and MSUF.MSUF_GetFontPathForKey)
                if type(pathForKey) == "function" and fontKey then fontPath = pathForKey(fontKey, size, fontFlags) end
            end
            if type(fontPath) ~= "string" or fontPath == "" then fontPath = fallbackFont end
            local resolveSafe = _G.MSUF_ResolveSafeFontPath
            if type(resolveSafe) == "function" then fontPath = resolveSafe(fontPath, size, fontFlags, fontKey) end
            if not _G.MSUF_SetFontChecked(fs, fontPath, size, fontFlags) then
                _G.MSUF_SetFontChecked(fs, fallbackFont, size, fontFlags)
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
end
function InstallStage.Refreshers(s)
    local Preview = s.Preview

--- Hot refresh for the unit preview. It composes current DB/model values into
--- mock regions and handle positions, but never mutates live unit frames. The
--- per-refresh state table is the box's scene: refilled, never reallocated,
--- and kept for the animation tick.
function Preview.Refresh(box, reason)
    box = box or Preview.active
    if not box or not box:IsShown() then return end
    local Deps = Preview.RefreshDeps
    local RenderState = Deps._RenderState or {}
    local PreviewInCombat = Deps.PreviewInCombat
    if PreviewInCombat() then return end
    local st = box._msufPreviewScene
    if st then
        for field in pairs(st) do st[field] = nil end
    else
        st = {}
        box._msufPreviewScene = st
    end
    st.box, st.reason, st.D, st.R = box, reason, Deps, RenderState
    st.complete = nil
    if Stage.ResolveInputs(st) == false then return end
    Stage.ResolveFrameGeometry(st)
    Stage.ResolvePowerGeometry(st)
    Stage.MeasureTextFootprint(st, Preview)
    Stage.MeasureLayerFootprint(st)
    Stage.ResolveScaleAndLevels(st)
    Stage.RenderClassPower(st)
    Stage.RenderCastbar(st)
    Stage.RenderSceneHandles(st, Preview)
    Stage.RenderArenaTrinket(st)
    Stage.FinalizeLayersAndHandles(st)
    st.complete = true
end

--- Animation tick: fills, value texts, cast progress and aura timers and
--- swipes follow the animation clock on the scene the last full refresh built. Geometry, textures, fonts, handles and layer state
--- stay as that refresh placed them, so a tick reads no settings and creates
--- nothing. Returns false when there is no complete scene to animate; the
--- caller then runs a full refresh.
function Preview.RefreshAnimation(box)
    box = box or Preview.active
    local st = box and box._msufPreviewScene
    if not (st and st.complete == true and st.box == box and box._animationEnabled == true) then return false end
    if not (box.IsShown and box:IsShown()) or st.key ~= box.key then return false end
    if st.D.PreviewInCombat() then return true end
    local data, powerFrac, animState = AnimatedPreviewData(st, st.baseData, st.basePowerFrac)
    if not animState  then return false end
    st.data, st.powerFrac, st.animState = data, powerFrac, animState
    local mock = st.mock
    box._unitSceneRoot:SetClock(box._animationElapsed)
    Stage.AnimateClassPower(st)
    Stage.PlaceValueTextHandles(st)
    if box._msufMenuTextFocus then st.R.ApplyPreviewTextFocus(box, st.canvas, mock) end
    if st.castPreviewVisible then
        ApplyCastbarPreviewProgress(mock.cast, st.g, st.key, st.S, animState, st.R.FormatCastbarPreviewTime)
        if mock.cast._msufTimeHandleShown then PlaceCastbarTimeHandle(box, mock, st.canvas, st.UnitPreviewText, st.PlaceHandle) end
    end
    return true
end
end
function Render.Install(Preview, deps)
    if type(Preview) ~= "table" then return end
    deps = deps or Preview.RefreshDeps or {}
    Preview.RefreshDeps = deps
    local renderState = PickFallbackTable(deps, UNIT_RENDER_FALLBACKS, [[
        RuntimeAppliedPortraitSizeForPreviewKey DetachedCastbarOffsetForPreviewKey RuntimeVisualScaleForPreviewKey RuntimeCastbarVisualScaleForPreviewKey ClampPreviewZoom ResolveDefaultPreviewZoomLock UpdatePreviewZoomControls
        CastbarShowIcon CastbarShowText ReadCastbarNum FormatCastbarPreviewTime
        GradientPreviewColor PowerColor FontColor TextScopeGet ]])
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
    renderState.STATUS_RUNTIME_KEYS = {
        raidmarker = "raidMarker", leader = "leader", assist = "assist", level = "level",
        raceText = "race", classText = "classText",
        elite = "elite", statusText = "statusDeadText", statusGhostText = "statusGhostText",
        statusAFKText = "statusAFKText", statusDNDText = "statusDNDText",
        statusCombat = "combat", statusResting = "resting",
        statusIncomingRes = "incomingRes", statusPvp = "pvp",
        statusPetHappiness = "petHappiness", statusThreat = "threat",
        statusPetXP = "petXP",
    }
    renderState.ApplyPreviewTextFocus = deps.ApplyPreviewTextFocus or UNIT_RENDER_FALLBACKS.ApplyPreviewTextFocus
    local s = { Preview = Preview, deps = deps, renderState = renderState }
    InstallStage.ClassPowerColors(s)
    InstallStage.PreviewFont(s)
    renderState.CPPreview = s.CPPreview
    deps._RenderState = renderState
    InstallStage.Refreshers(s)
end
