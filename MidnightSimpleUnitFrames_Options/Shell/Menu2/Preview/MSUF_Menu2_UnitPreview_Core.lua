--- Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Core.lua
--- Cold-path shared helpers for the MSUF2 unit frame preview.
local addonName, addonNS = ...
local MSUF = addonNS or (_G.MSUF_NS) or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local floor = math.floor
local issecretvalue = _G.issecretvalue or function(_) return false end
local TEX_W8 = "Interface\\Buttons\\WHITE8X8"
local MEDIA = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\"
local MASK_MEDIA = MEDIA .. "Masks\\"
local previewRoundedMask = MASK_MEDIA .. "rounded_clean_mask_s3.png"
local previewRoundedEdge = MASK_MEDIA .. "rounded_clean_edge_s3.png"
local previewRoundedStrength = 3
local Preview = MSUF.UFPreview or {}
MSUF.UFPreview = Preview
ExportPublic("MSUF_UFPreview", Preview)
local PreviewModel = Preview.Model or {}
local UnitDB = PreviewModel.UnitDB
local Clamp01 = PreviewModel.Clamp01
local PreviewResolveHealPredAnchorMode = PreviewModel.PreviewResolveHealPredAnchorMode
local PreviewResolveAbsorbAnchorMode = PreviewModel.PreviewResolveAbsorbAnchorMode
local PreviewHelpers = (MSUF.MSUF2 and MSUF.MSUF2.PreviewHelpers) or {}
local Layers = MSUF.UF and MSUF.UF.Layers or {}
local Core = MSUF.UFPreviewCore or {}
MSUF.UFPreviewCore = Core
function Core.MenuTheme()
    local m = MSUF and MSUF.MSUF2
    return m and m.Theme
end
function Core.ApplyBackdrop(frame, bg, border, fallback)
    local T = Core.MenuTheme()
    if T and type(T.ApplyBackdrop) == "function" then
        T.ApplyBackdrop(frame, bg, border)
        return
    end
    if not (frame and frame.SetBackdrop) then return end
    fallback = fallback or {}
    frame:SetBackdrop(fallback.backdrop or {
        bgFile = TEX_W8,
        edgeFile = TEX_W8,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    local b = bg or fallback.bg or { 0.035, 0.043, 0.058, 0.96 }
    local e = border or fallback.border or { 0.19, 0.25, 0.34, 0.95 }
    frame:SetBackdropColor(b[1], b[2], b[3], b[4] or 1)
    frame:SetBackdropBorderColor(e[1], e[2], e[3], e[4] or 1)
end
function Core.RoundOffset(v)
    v = tonumber(v) or 0
    if v >= 0 then return floor(v + 0.5) end
    return -floor((-v) + 0.5)
end
function Core.ClampLayer(v, fallback)
    v = floor((tonumber(v) or fallback or 0) + 0.5)
    if v < 0 then return 0 end
    if v > 30 then return 30 end
    return v
end
function Core.PlaceHandle(handle, target, pad)
    if not handle or not target or not target.GetCenter then return end
    handle:ClearAllPoints()
    handle:SetPoint("CENTER", target, "CENTER", pad or 0, 0)
    handle:SetShown(target:IsShown())
end
function Core.InteractionFrameLevel(parent, extra)
    local parentLevel = parent and parent.GetFrameLevel and tonumber(parent:GetFrameLevel()) or 0
    local level = parentLevel + 30
    if Layers.ElementLevel then
        local absoluteTop = tonumber(Layers.ElementLevel(30, 30, Layers.ELEMENT_DETAIL_MAX or 31))
        if absoluteTop then
            absoluteTop = absoluteTop
                + (tonumber(parent and parent._msufPreviewElementLevelBias) or 0)
            -- Share the interaction plane already used by Aura handles: one
            -- complete level slot above every configurable visual layer.
            absoluteTop = absoluteTop + (tonumber(Layers.ELEMENT_LEVEL_STRIDE) or 32)
            if absoluteTop > level then level = absoluteTop end
        end
    end
    return floor(level + (tonumber(extra) or 0) + 0.5)
end
function Core.SetShownSafe(region, shown)
    if region and region.SetShown then region:SetShown(shown and true or false) end
end
local function ReadPreviewBarsBool(key, default)
    local bars = _G.MSUF_DB and _G.MSUF_DB.bars
    local value = bars and bars[key]
    if value == nil then return default and true or false end
    return value and true or false
end
local function ClampPreviewEdgeSize(value, fallback, maxValue)
    local n = tonumber(value)
    if n == nil then n = tonumber(fallback) or 0 end
    n = floor(n + 0.5)
    if n < 0 then n = 0 end
    maxValue = tonumber(maxValue) or 8
    if n > maxValue then n = maxValue end
    return n
end
function Core.RoundedOutlineThickness(key, conf, scale)
    local bars = _G.MSUF_DB and _G.MSUF_DB.bars
    local raw
    if conf and conf.hlOverride and conf.barOutlineThickness ~= nil then
        raw = conf.barOutlineThickness
    else
        raw = bars and bars.barOutlineThickness
    end
    local t = ClampPreviewEdgeSize(raw, 1, 8)
    if t > 0 and scale then
        t = floor(t * scale + 0.5)
        if t < 1 then t = 1 end
    end
    return t
end
local function PreviewRoundedUnitFramesEnabled()
    return ReadPreviewBarsBool("roundedFramesEnabled", false)
        and ReadPreviewBarsBool("roundedUnitFrames", true)
end
local function PreviewRoundedPowerBarsEnabled()
    return ReadPreviewBarsBool("roundedFramesEnabled", false)
        and ReadPreviewBarsBool("roundedPowerBars", true)
end
local function PreviewSnapOff(region)
    if PreviewHelpers.SnapOff then PreviewHelpers.SnapOff(region) end
end
local function EnsurePreviewRoundedMask(mock, key, anchor, tex)
    if not PreviewHelpers.EnsureRoundedMask then return nil end
    return PreviewHelpers.EnsureRoundedMask(mock, key, anchor, tex, "_msufPreviewRoundedMasks", previewRoundedMask, PreviewSnapOff)
end
local function PreviewSetMask(mock, tex, mask)
    if PreviewHelpers.SetMask then PreviewHelpers.SetMask(mock, tex, mask, "_msufPreviewRoundedMasked") end
end
local function ClearPreviewRoundedMasks(mock)
    if PreviewHelpers.ClearMasks then PreviewHelpers.ClearMasks(mock, "_msufPreviewRoundedMasked") end
end
local PREVIEW_GRADIENT_DIRECTIONS = { "left", "right", "up", "down" }
local function ApplyPreviewGradientMasks(mock, grads, key, anchor, enabled)
    if type(grads) ~= "table" then return end
    for i = 1, #PREVIEW_GRADIENT_DIRECTIONS do
        local tex = grads[PREVIEW_GRADIENT_DIRECTIONS[i]]
        if tex then
            local mask = enabled and EnsurePreviewRoundedMask(mock, key, anchor, tex) or nil
            PreviewSetMask(mock, tex, mask)
        end
    end
end
function Core.BaseEdgeColor()
    if PreviewHelpers.BaseEdgeColor then return PreviewHelpers.BaseEdgeColor() end
    return 0, 0, 0, 1
end
local FRAME_BORDER_KEYS = { "top", "bottom", "left", "right" }
local FRAME_BORDER_OPTS = {
    keys = FRAME_BORDER_KEYS,
    linesKey = "_edges",
    texture = TEX_W8,
    snapOff = PreviewSnapOff,
}
local function EnsureFrameBorderOverlay(mock, border)
    if not (mock and mock.CreateTexture) then return nil end
    local overlay = mock._msufPreviewFrameBorder
    if not overlay then
        overlay = CreateFrame("Frame", nil, mock, "BackdropTemplate")
        overlay:EnableMouse(false)
        overlay:SetAllPoints(mock)
        overlay._edges = {}
        if overlay.SetBackdrop then
            overlay:SetBackdrop({ edgeFile = TEX_W8, edgeSize = 1 })
            overlay:SetBackdropBorderColor(0, 0, 0, 0)
        end
        mock._msufPreviewFrameBorder = overlay
    end
    if overlay.SetFrameLevel and mock.GetFrameLevel then
        local layer = floor((tonumber(border and border.layer) or 0) + 0.5)
        if layer < 0 then layer = 0 elseif layer > 30 then layer = 30 end
        if Layers.ElementLevel then
            overlay:SetFrameLevel(Layers.ElementLevel(layer, 0, 8)
                + (tonumber(mock._msufPreviewElementLevelBias) or 0))
        elseif mock._msufPreviewGroupScope == true and Layers.GroupBorderLevel then
            overlay:SetFrameLevel(Layers.GroupBorderLevel(mock:GetFrameLevel() or 0, layer))
        else
            overlay:SetFrameLevel((mock:GetFrameLevel() or 0) + (Layers.FRAME_BORDER_NORMAL_OFFSET or Layers.PREVIEW_FRAME_BORDER_OFFSET or 35) + layer)
        end
    end
    -- A profile's absolute runtime strata cannot be copied into the options
    -- canvas: migrated 5.x profiles commonly use BACKGROUND, which places the
    -- outline behind the preview card. Keep the configured relative layer
    -- above, but render on the mock's local strata so UF and GF outlines stay
    -- visible independently of the optional Bounds guide.
    if overlay.SetFrameStrata and mock.GetFrameStrata then
        local strata = mock:GetFrameStrata()
        if issecretvalue(strata) ~= true and strata then
            local currentStrata = overlay.GetFrameStrata and overlay:GetFrameStrata() or nil
            if issecretvalue(currentStrata) == true or currentStrata ~= strata then overlay:SetFrameStrata(strata) end
        end
    end
    return overlay
end
local function SetFrameBorderShown(mock, shown)
    local overlay = mock and mock._msufPreviewFrameBorder
    if overlay then Core.SetShownSafe(overlay, shown) end
    if not shown then
        if PreviewHelpers.SetEdgeLinesShown then PreviewHelpers.SetEdgeLinesShown(overlay, false, FRAME_BORDER_OPTS) end
        if overlay and overlay.SetBackdropBorderColor then overlay:SetBackdropBorderColor(0, 0, 0, 0) end
    end
end

local function ApplyTrueOutlineFrameBorder(mock, overlay, border, thickness)
    local texture = border and border.texture
    local styles = MSUF.BorderStyles or _G.MSUF_BorderStyles
    local trueOutlineMode = styles and styles.FRAME_BORDER or "border"
    if not border or border.textureMode ~= trueOutlineMode
        or type(texture) ~= "string" or texture == ""
        or not (overlay.SetBackdrop and overlay.SetBackdropBorderColor) then
        if overlay.SetBackdropBorderColor then overlay:SetBackdropBorderColor(0, 0, 0, 0) end
        return false
    end
    local edgeSize = type(styles.EdgeSize) == "function"
        and styles.EdgeSize(border.textureKey, thickness) or thickness
    local r, g, b, a = border.r, border.g, border.b, border.a
    if r == nil then r, g, b, a = Core.BaseEdgeColor() end
    overlay:SetBackdrop({ edgeFile = texture, edgeSize = edgeSize })
    overlay:SetBackdropBorderColor(r or 0, g or 0, b or 0, a == nil and 1 or a)
    if PreviewHelpers.SetEdgeLinesShown then PreviewHelpers.SetEdgeLinesShown(overlay, false, FRAME_BORDER_OPTS) end
    return true
end
function Core.ApplyFrameBorder(box, border, scale)
    local mock = box and box.mock
    if not mock then return end
    mock._msufPreviewFrameBorderConfigured = type(border) == "table"
    local thickness = border and border.enabled == true and tonumber(border.thickness) or 0
    if not thickness or thickness <= 0 then
        mock._msufPreviewFrameBorderEnabled = nil
        SetFrameBorderShown(mock, false)
        return
    end
    thickness = floor((thickness * (tonumber(scale) or 1)) + 0.5)
    if thickness < 1 then thickness = 1 elseif thickness > 30 then thickness = 30 end
    local overlay = EnsureFrameBorderOverlay(mock, border)
    if not overlay then return end
    overlay:ClearAllPoints()
    if border.textureMode == "border" then
        overlay:SetAllPoints(mock)
    else
        overlay:SetPoint("TOPLEFT", mock, "TOPLEFT", -thickness, thickness)
        overlay:SetPoint("BOTTOMRIGHT", mock, "BOTTOMRIGHT", thickness, -thickness)
    end
    if not ApplyTrueOutlineFrameBorder(mock, overlay, border, thickness) then
        local styles = MSUF.BorderStyles or _G.MSUF_BorderStyles
        local textureMode = styles and styles.FRAME_TEXTURE or "texture"
        local usesTexture = border.textureMode == textureMode
        FRAME_BORDER_OPTS.color = function()
            local r, g, b, a = border.r, border.g, border.b, border.a
            if r == nil then r, g, b, a = Core.BaseEdgeColor() end
            if usesTexture then return 1, 1, 1, a == nil and 1 or a end
            return r or 0, g or 0, b or 0, a == nil and 1 or a
        end
        FRAME_BORDER_OPTS.texture = usesTexture and border.texture or TEX_W8
        if PreviewHelpers.LayoutEdgeLines then PreviewHelpers.LayoutEdgeLines(overlay, thickness, FRAME_BORDER_OPTS) end
        if PreviewHelpers.SetEdgeLinesShown then PreviewHelpers.SetEdgeLinesShown(overlay, true, FRAME_BORDER_OPTS) end
    end
    mock._msufPreviewFrameBorderEnabled = true
    SetFrameBorderShown(mock, true)
end
local BOUNDS_GUIDE_KEYS = { "top", "bottom", "left", "right" }
-- The bounds guide marks a measurement, not a problem. Red is reserved for
-- destructive actions and error states elsewhere in Menu2, so the guide uses
-- the same cyan the rest of the preview chrome speaks in.
local BOUNDS_GUIDE_OPTS = {
    keys = BOUNDS_GUIDE_KEYS,
    linesKey = "_msufGuideLines",
    texture = TEX_W8,
    snapOff = PreviewSnapOff,
    color = function() return 0.25, 0.75, 0.88, 0.92 end,
}
function Core.ApplyBoundsGuide(box, edgeSize)
    local mock = box and box.mock
    local bounds = mock and mock.bounds
    if not bounds then return end
    edgeSize = floor((tonumber(edgeSize) or 1) + 0.5)
    if edgeSize < 1 then edgeSize = 1 elseif edgeSize > 30 then edgeSize = 30 end
    if bounds.SetBackdropColor then bounds:SetBackdropColor(0, 0, 0, 0) end
    if bounds.SetBackdropBorderColor then bounds:SetBackdropBorderColor(0, 0, 0, 0) end
    bounds:ClearAllPoints()
    bounds:SetPoint("TOPLEFT", mock, "TOPLEFT", -edgeSize, edgeSize)
    bounds:SetPoint("BOTTOMRIGHT", mock, "BOTTOMRIGHT", edgeSize, -edgeSize)
    if PreviewHelpers.LayoutEdgeLines then PreviewHelpers.LayoutEdgeLines(bounds, edgeSize, BOUNDS_GUIDE_OPTS) end
end
local PREVIEW_ROUNDED_OPTS = {
    -- Reuse the legitimate health background as the helper's existing
    -- background region. This prevents EnsureRoundedVisuals from allocating a
    -- second full-frame "body" texture just to draw the rounded edge.
    bgKey = "hpBG",
    edgeKey = "roundedEdge",
    stackKey = "_msufPreviewRoundedEdgeStack",
    countKey = "_msufPreviewRoundedEdgeCount",
    whiteTexture = TEX_W8,
    edgeTexture = previewRoundedEdge,
    snapOff = PreviewSnapOff,
    clamp01 = Clamp01,
    baseEdgeColor = function() return Core.BaseEdgeColor() end,
}
local function PreviewPowerEdgeColor(mock)
    if mock and mock._msufPreviewPowerBorderR ~= nil then
        return mock._msufPreviewPowerBorderR, mock._msufPreviewPowerBorderG,
            mock._msufPreviewPowerBorderB, mock._msufPreviewPowerBorderA
    end
    return Core.BaseEdgeColor()
end
local DETACHED_POWER_ROUNDED_OPTS = {
    bgKey = "_msufPreviewRoundedBg",
    edgeKey = "_msufPreviewRoundedEdge",
    stackKey = "_msufPreviewRoundedEdgeStack",
    countKey = "_msufPreviewRoundedEdgeCount",
    whiteTexture = TEX_W8,
    edgeTexture = previewRoundedEdge,
    edgeLayer = "OVERLAY",
    edgeSubLevel = 6,
    snapOff = PreviewSnapOff,
    clamp01 = Clamp01,
    baseEdgeColor = PreviewPowerEdgeColor,
}
local INLINE_POWER_ROUNDED_OPTS = {
    bgKey = "_msufPreviewRoundedBg",
    edgeKey = "_msufPreviewRoundedEdge",
    stackKey = "_msufPreviewRoundedEdgeStack",
    countKey = "_msufPreviewRoundedEdgeCount",
    whiteTexture = TEX_W8,
    edgeTexture = previewRoundedEdge,
    edgeLayer = "OVERLAY",
    edgeSubLevel = 6,
    snapOff = PreviewSnapOff,
    baseEdgeColor = PreviewPowerEdgeColor,
}
local function UpdatePreviewRoundedMedia(mock)
    if type(PreviewHelpers.ResolveRoundedMedia) == "function" then
        previewRoundedMask, previewRoundedEdge, previewRoundedStrength = PreviewHelpers.ResolveRoundedMedia()
    end
    mock._msufPreviewRoundedMediaStrength = previewRoundedStrength
    PREVIEW_ROUNDED_OPTS.edgeTexture = previewRoundedEdge
    PREVIEW_ROUNDED_OPTS.mediaStrength = previewRoundedStrength
    DETACHED_POWER_ROUNDED_OPTS.edgeTexture = previewRoundedEdge
    DETACHED_POWER_ROUNDED_OPTS.mediaStrength = previewRoundedStrength
    INLINE_POWER_ROUNDED_OPTS.edgeTexture = previewRoundedEdge
    INLINE_POWER_ROUNDED_OPTS.mediaStrength = previewRoundedStrength
end
local function EnsurePreviewRoundedVisuals(mock)
    return PreviewHelpers.EnsureRoundedVisuals and PreviewHelpers.EnsureRoundedVisuals(mock, PREVIEW_ROUNDED_OPTS)
end
local function PreviewSetRoundedEdgeStackShown(mock, shown)
    if PreviewHelpers.SetRoundedEdgeStackShown then PreviewHelpers.SetRoundedEdgeStackShown(mock, shown, PREVIEW_ROUNDED_OPTS) end
end
local function PreviewSetRoundedEdgeStackAlpha(mock, alpha)
    if PreviewHelpers.SetRoundedEdgeStackAlpha then PreviewHelpers.SetRoundedEdgeStackAlpha(mock, alpha, PREVIEW_ROUNDED_OPTS) end
end
local function PreviewApplyRoundedEdgeStack(mock, edgeSize)
    return PreviewHelpers.ApplyRoundedEdgeStack and PreviewHelpers.ApplyRoundedEdgeStack(mock, edgeSize, PREVIEW_ROUNDED_OPTS)
end
local function SetDetachedRoundedShown(detached, shown)
    if PreviewHelpers.SetRoundedEdgeStackShown then
        PreviewHelpers.SetRoundedEdgeStackShown(detached, shown, DETACHED_POWER_ROUNDED_OPTS)
    end
    if detached and detached._msufPreviewRoundedBg then detached._msufPreviewRoundedBg:Hide() end
end
local function SetInlinePowerRoundedShown(host, shown)
    if PreviewHelpers.SetRoundedEdgeStackShown then
        PreviewHelpers.SetRoundedEdgeStackShown(host, shown, INLINE_POWER_ROUNDED_OPTS)
    end
    if host and host._msufPreviewRoundedBg then host._msufPreviewRoundedBg:Hide() end
end
local function EnsureInlinePowerHost(mock)
    local host = mock and mock._msufPreviewInlinePowerRoundedHost
    if host then return host end
    if not (mock and type(_G.CreateFrame) == "function") then return nil end
    host = CreateFrame("Frame", nil, mock)
    if host.EnableMouse then host:EnableMouse(false) end
    if host.SetFrameLevel and mock.GetFrameLevel then host:SetFrameLevel(mock:GetFrameLevel() + 3) end
    mock._msufPreviewInlinePowerRoundedHost = host
    return host
end
local function ApplyPowerBorder(mock, powerOn, thickness, embedded, roundedPower)
    if not mock then return end
    local host = mock._msufPreviewPowerBorder
    local edge = ClampPreviewEdgeSize(thickness, 0, 8)
    if not powerOn or edge <= 0 then
        if host then host:Hide() end
        return
    end
    if not host then
        if type(_G.CreateFrame) ~= "function" then return end
        host = CreateFrame("Frame", nil, mock)
        if host.EnableMouse then host:EnableMouse(false) end
        host.edges = {}
        for i = 1, 4 do
            local line = host:CreateTexture(nil, "OVERLAY", nil, 6)
            line:SetTexture(TEX_W8)
            host.edges[i] = line
        end
        mock._msufPreviewPowerBorder = host
    end
    if host.SetFrameLevel and mock.GetFrameLevel then host:SetFrameLevel(mock:GetFrameLevel() + 4) end
    local top, bottom, left, right = host.edges[1], host.edges[2], host.edges[3], host.edges[4]
    for i = 1, 4 do host.edges[i]:Hide() end
    if roundedPower and not embedded then
        host:Hide()
        return
    end
    host:ClearAllPoints()
    host:SetAllPoints(mock.powerBG)
    local r, g, b, a = PreviewPowerEdgeColor(mock)
    for i = 1, 4 do host.edges[i]:SetVertexColor(r, g, b, a) end
    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
    top:SetHeight(edge)
    top:Show()
    if not roundedPower then
        bottom:ClearAllPoints()
        bottom:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
        bottom:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
        bottom:SetHeight(edge)
        left:ClearAllPoints()
        left:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        left:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
        left:SetWidth(edge)
        right:ClearAllPoints()
        right:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
        right:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
        right:SetWidth(edge)
        bottom:Show()
        left:Show()
        right:Show()
    end
    host:Show()
end
function Core.ApplyRounded(box, key, powerOn, outlineThickness, powerEmbedded, powerEdgeSize, detachedRounded, detachedEdgeSize)
    if not (box and box.mock) then return end
    local mock = box.mock
    local rounded = PreviewRoundedUnitFramesEnabled()
    if rounded then UpdatePreviewRoundedMedia(mock) end
    if not rounded or not EnsurePreviewRoundedVisuals(mock) then
        mock._msufPreviewRoundedActive = nil
        mock._msufPreviewRoundedEdgeEnabled = nil
        ClearPreviewRoundedMasks(mock)
        PreviewSetRoundedEdgeStackShown(mock, false)
        SetInlinePowerRoundedShown(mock._msufPreviewInlinePowerRoundedHost, false)
        SetDetachedRoundedShown(mock.detachedPower, false)
        ApplyPowerBorder(mock, powerOn, powerEdgeSize, powerEmbedded ~= false, false)
        return
    end
    mock._msufPreviewRoundedActive = true
    local roundedPower = powerOn and PreviewRoundedPowerBarsEnabled()
    local sharedPowerBody = roundedPower and powerEmbedded ~= false
    ApplyPowerBorder(mock, powerOn, powerEdgeSize, sharedPowerBody, roundedPower)
    local healthBgAnchor = mock
    local healthAnchor = sharedPowerBody and mock or (mock.healthBar or mock.hpBG)
    local hpBgMask = EnsurePreviewRoundedMask(mock, "healthBg", healthBgAnchor, mock.hpBG)
    local hpMask = EnsurePreviewRoundedMask(mock, "health", healthAnchor, mock.hp)
    local tempMaxBgMask = EnsurePreviewRoundedMask(mock, "tempMaxHealthBg", healthAnchor, mock.tempMaxHealthBg)
    local tempMaxMask = EnsurePreviewRoundedMask(mock, "tempMaxHealth", healthAnchor, mock.tempMaxHealth)
    local healPredMask = EnsurePreviewRoundedMask(mock, "healPred", healthAnchor, mock.healPred)
    local absorbMask = EnsurePreviewRoundedMask(mock, "absorb", healthAnchor, mock.absorb)
    local healAbsorbMask = EnsurePreviewRoundedMask(mock, "healAbsorb", healthAnchor, mock.healAbsorb)
    local conf, g = UnitDB(key)
    local healPredMode = PreviewResolveHealPredAnchorMode(conf, g)
    local absorbMode = PreviewResolveAbsorbAnchorMode(conf, g)
    PreviewSetMask(mock, mock.hpBG, hpBgMask)
    PreviewSetMask(mock, mock.hp, hpMask)
    ApplyPreviewGradientMasks(mock, mock._msufPreviewHealthGradients,
        "healthGradient", healthAnchor, true)
    PreviewSetMask(mock, mock.tempMaxHealthBg, tempMaxBgMask)
    PreviewSetMask(mock, mock.tempMaxHealth, tempMaxMask)
    PreviewSetMask(mock, mock.healPred, healPredMode == 4 and nil or healPredMask)
    PreviewSetMask(mock, mock.absorb, absorbMode == 4 and nil or absorbMask)
    PreviewSetMask(mock, mock.healAbsorb, healAbsorbMask)
    local dispelOverlay = mock._msufPreviewDispelOverlayRegion
    local dispelOverlayMask = dispelOverlay and dispelOverlay:IsShown()
        and EnsurePreviewRoundedMask(mock, "dispelOverlay", healthAnchor, dispelOverlay) or nil
    PreviewSetMask(mock, dispelOverlay, dispelOverlayMask)
    local powerAnchor = sharedPowerBody and mock or mock.powerBG
    local powerBgMask = roundedPower and EnsurePreviewRoundedMask(mock, "power", powerAnchor, mock.powerBG) or nil
    local powerMask = roundedPower and EnsurePreviewRoundedMask(mock, "power", powerAnchor, mock.power) or nil
    PreviewSetMask(mock, mock.powerBG, powerBgMask)
    PreviewSetMask(mock, mock.power, powerMask)
    ApplyPreviewGradientMasks(mock, mock._msufPreviewPowerGradients,
        "powerGradient", powerAnchor, roundedPower)
    local inlinePowerHost = mock._msufPreviewInlinePowerRoundedHost
    if roundedPower and not sharedPowerBody then
        inlinePowerHost = EnsureInlinePowerHost(mock)
        if inlinePowerHost then
            inlinePowerHost:ClearAllPoints()
            inlinePowerHost:SetAllPoints(mock.powerBG)
            inlinePowerHost:Show()
        end
        if inlinePowerHost and PreviewHelpers.EnsureRoundedVisuals
            and PreviewHelpers.EnsureRoundedVisuals(inlinePowerHost, INLINE_POWER_ROUNDED_OPTS) then
            local edge = ClampPreviewEdgeSize(powerEdgeSize, 1, 8)
            if edge > 0 and PreviewHelpers.ApplyRoundedEdgeStack then
                PreviewHelpers.ApplyRoundedEdgeStack(inlinePowerHost, edge, INLINE_POWER_ROUNDED_OPTS)
            else
                SetInlinePowerRoundedShown(inlinePowerHost, false)
            end
            if inlinePowerHost._msufPreviewRoundedBg then inlinePowerHost._msufPreviewRoundedBg:Hide() end
        else
            SetInlinePowerRoundedShown(inlinePowerHost, false)
        end
    else
        SetInlinePowerRoundedShown(inlinePowerHost, false)
        if inlinePowerHost then inlinePowerHost:Hide() end
    end
    local detached = mock.detachedPower
    local detachedActive = detachedRounded == true and PreviewRoundedPowerBarsEnabled()
        and detached and (not detached.IsShown or detached:IsShown())
    if detachedActive and PreviewHelpers.EnsureRoundedVisuals
        and PreviewHelpers.EnsureRoundedVisuals(detached, DETACHED_POWER_ROUNDED_OPTS) then
        local detachedBgMask = EnsurePreviewRoundedMask(mock, "detachedPowerBg", detached, detached.bg)
        local detachedFillMask = EnsurePreviewRoundedMask(mock, "detachedPowerFill", detached, detached.fill)
        PreviewSetMask(mock, detached.bg, detachedBgMask)
        PreviewSetMask(mock, detached.fill, detachedFillMask)
        ApplyPreviewGradientMasks(mock, mock._msufPreviewDetachedPowerGradients,
            "detachedPowerGradient", detached, true)
        local edge = ClampPreviewEdgeSize(detachedEdgeSize, 1, 8)
        if edge > 0 and PreviewHelpers.ApplyRoundedEdgeStack then
            PreviewHelpers.ApplyRoundedEdgeStack(detached, edge, DETACHED_POWER_ROUNDED_OPTS)
        else
            SetDetachedRoundedShown(detached, false)
        end
        if detached.SetBackdropBorderColor then detached:SetBackdropBorderColor(0, 0, 0, 0) end
        if detached._msufPreviewRoundedBg then detached._msufPreviewRoundedBg:Hide() end
    else
        if detached then
            PreviewSetMask(mock, detached.bg, nil)
            PreviewSetMask(mock, detached.fill, nil)
        end
        ApplyPreviewGradientMasks(mock, mock._msufPreviewDetachedPowerGradients,
            "detachedPowerGradient", detached, false)
        SetDetachedRoundedShown(detached, false)
    end
    local edgeSize = ClampPreviewEdgeSize(outlineThickness, 1, 30)
    mock._msufPreviewRoundedEdgeEnabled = edgeSize > 0
    if edgeSize > 0 then
        PreviewApplyRoundedEdgeStack(mock, edgeSize)
    else
        PreviewSetRoundedEdgeStackShown(mock, false)
    end
    if mock.SetBackdropColor then mock:SetBackdropColor(0, 0, 0, 0) end
    if mock.SetBackdropBorderColor then mock:SetBackdropBorderColor(0, 0, 0, 0) end
end
function Core.ApplyLayerVisibility(box)
    if not box or not box.mock then return end
    local v = box.layerVisibility or {}
    local available = box.layerAvailable or {}
    local function LayerOn(key)
        return available[key] ~= false and v[key] ~= false
    end
    local mock = box.mock
    local powerOn = LayerOn("power")
    local nameOn = LayerOn("nameText")
    local hpTextOn = LayerOn("hpText")
    local powerTextOn = LayerOn("powerText")
    local portraitOn = LayerOn("portrait")
    local classOn = LayerOn("classPower")
    local castOn = LayerOn("castbar")
    local statusOn = LayerOn("status")
    local guidesOn = LayerOn("guides")
    local boundsOn = LayerOn("bounds")
    local roundedActive = mock._msufPreviewRoundedActive == true
    if roundedActive then
        if mock.SetBackdropBorderColor then mock:SetBackdropBorderColor(0, 0, 0, 0) end
        PreviewSetRoundedEdgeStackShown(mock, mock._msufPreviewRoundedEdgeEnabled ~= false)
        SetFrameBorderShown(mock, false)
    elseif mock._msufPreviewFrameBorderEnabled == true then
        if mock.SetBackdropBorderColor then mock:SetBackdropBorderColor(0, 0, 0, 0) end
        PreviewSetRoundedEdgeStackShown(mock, false)
        SetFrameBorderShown(mock, true)
    elseif mock._msufPreviewFrameBorderConfigured == true then
        if mock.SetBackdropBorderColor then mock:SetBackdropBorderColor(0, 0, 0, 0) end
        PreviewSetRoundedEdgeStackShown(mock, false)
        SetFrameBorderShown(mock, false)
    else
        if mock.SetBackdropBorderColor then
            local r, g, b = Core.BaseEdgeColor()
            mock:SetBackdropBorderColor(r, g, b, 1)
        end
        PreviewSetRoundedEdgeStackShown(mock, false)
        SetFrameBorderShown(mock, false)
    end
    Core.SetShownSafe(mock.hpBG, true)
    Core.SetShownSafe(mock.hp, true)
    if not powerOn then
        Core.SetShownSafe(mock.powerBG, false)
        Core.SetShownSafe(mock.power, false)
        Core.SetShownSafe(mock.detachedPower, false)
        Core.SetShownSafe(box.handleDetachedPower, false)
    end
    if not classOn then
        Core.SetShownSafe(mock.classPower, false)
        Core.SetShownSafe(box.handleClassPower, false)
        Core.SetShownSafe(box.handleClassPowerText, false)
    end
    if mock.classPower and mock.classPower.segments and (not classOn or not mock.classPower:IsShown()) then
        for i = 1, #mock.classPower.segments do Core.SetShownSafe(mock.classPower.segments[i], false) end
    end
    if mock.classPower and mock.classPower.text and (not classOn or not mock.classPower:IsShown()) then Core.SetShownSafe(mock.classPower.text, false) end
    if not nameOn then
        Core.SetShownSafe(mock.nameText, false)
        Core.SetShownSafe(mock.totInlineSep, false)
        Core.SetShownSafe(mock.totInlineText, false)
        Core.SetShownSafe(box.handleName, false)
    end
    if not hpTextOn then
        Core.SetShownSafe(mock.hpTextLeft, false)
        Core.SetShownSafe(mock.hpTextCenter, false)
        Core.SetShownSafe(mock.hpText, false)
        Core.SetShownSafe(mock.hpTextPct, false)
        Core.SetShownSafe(box.handleHP, false)
        Core.SetShownSafe(box.handleHPLeft, false)
        Core.SetShownSafe(box.handleHPCenter, false)
        Core.SetShownSafe(box.handleHPRight, false)
    end
    if not powerTextOn then
        Core.SetShownSafe(mock.powerTextLeft, false)
        Core.SetShownSafe(mock.powerTextCenter, false)
        Core.SetShownSafe(mock.powerText, false)
        Core.SetShownSafe(mock.powerTextPct, false)
        Core.SetShownSafe(box.handlePower, false)
        Core.SetShownSafe(box.handlePowerLeft, false)
        Core.SetShownSafe(box.handlePowerCenter, false)
        Core.SetShownSafe(box.handlePowerRight, false)
    end
    if not portraitOn and not (box._runtimeDefensivePortraitPositionOnly == true and LayerOn("auras")) then
        Core.SetShownSafe(mock.portrait, false)
        Core.SetShownSafe(box.handlePortrait, false)
    end
    if not castOn then
        Core.SetShownSafe(mock.cast, false)
        Core.SetShownSafe(box.handleCastbar, false)
        Core.SetShownSafe(box.handleCastbarIcon, false)
        Core.SetShownSafe(box.handleCastbarText, false)
        Core.SetShownSafe(box.handleCastbarTime, false)
    end
    if mock.cast and mock.cast.sizeTag then Core.SetShownSafe(mock.cast.sizeTag, guidesOn and castOn and mock.cast:IsShown()) end
    local Auras = MSUF.UFPreviewAuras
    if Auras and type(Auras.ApplyLayerVisibility) == "function" then
        Auras.ApplyLayerVisibility(box)
    end
    if Auras and type(Auras.ApplyDispelLayerVisibility) == "function" then
        Auras.ApplyDispelLayerVisibility(box)
    end
    if not statusOn then
        for _, icon in pairs(mock.icons or {}) do Core.SetShownSafe(icon, false) end
        Core.SetShownSafe(mock.raidGroupNameText, false)
        for _, handle in pairs(box.statusHandles or {}) do Core.SetShownSafe(handle, false) end
    end
    if not LayerOn("texLayer") then
        for i = 1, #(mock.texLayers or {}) do Core.SetShownSafe(mock.texLayers[i], false) end
        for i = 1, #(box.texLayerHandles or {}) do Core.SetShownSafe(box.texLayerHandles[i], false) end
    end
    Core.SetShownSafe(mock.bounds, boundsOn)
end
function Core.InCombat()
    -- Blizzard's live lockdown state is authoritative for preview deferral.
    -- MSUF_InCombat is runtime-owned and can briefly remain latched after combat;
    -- consulting it first would strand the preview waiting for an event that has
    -- already fired. Keep it only as a fallback for non-client/test environments.
    local inCombatLockdown = _G.InCombatLockdown
    if type(inCombatLockdown) == "function" then
        return inCombatLockdown() == true
    end
    return _G.MSUF_InCombat == true
end

-- The background textures already carry their final compiled alpha from the
-- render pass. Foreground text, portrait, cast, and icons follow the HP value
-- unless the "keep text + portrait visible" toggle is on.
local function PreviewAlphaState(conf, runtimeSpec)
    local runtimeAlpha = runtimeSpec and runtimeSpec.alpha
    local runtimePower = runtimeSpec and runtimeSpec.power
    -- The menu DB is the just-edited source of truth. Runtime specs are a
    -- fallback only: their apply is deliberately debounced and can still be
    -- one transaction behind the preview refresh.
    local hp = Clamp01(conf and conf.hpBarAlpha, runtimeAlpha and runtimeAlpha.hpAlpha or 1)
    local power = Clamp01(conf and conf.powerBarAlpha, runtimePower and runtimePower.alpha or 1)
    local excludeTextPortrait
    if conf and conf.alphaExcludeTextPortrait ~= nil then
        excludeTextPortrait = conf.alphaExcludeTextPortrait == true
    else
        excludeTextPortrait = runtimeAlpha and runtimeAlpha.excludeTextPortrait == true
    end
    local fg = excludeTextPortrait and 1 or hp
    return {
        flat = false,
        frame = 1,
        fg = fg,
        hp = hp,
        power = power,
        text = fg,
        portrait = fg,
        preserveHPColor = false,
    }
end
function Core.SetRegionAlpha(region, alpha)
    if region and region.SetAlpha then region:SetAlpha(Clamp01(alpha, 1)) end
end
function Core.SetFrameBackdropAlpha(frame, bgAlpha, borderAlpha)
    if not frame or not frame.SetBackdropColor then return end
    frame:SetBackdropColor(0, 0, 0, Clamp01(bgAlpha, 1))
    if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(0, 0, 0, Clamp01(borderAlpha, 1)) end
end
function Core.ApplyPreviewTransparency(box, conf, runtimeSpec)
    if not box or not box.mock then return end
    local mock = box.mock
    local alpha = PreviewAlphaState(conf, runtimeSpec)
    local rangeAlpha = tonumber(box._msuf2RangeFadePreviewAlpha)
    if rangeAlpha ~= nil then rangeAlpha = Clamp01(rangeAlpha, 1) end
    local rangeHealthOnly = rangeAlpha ~= nil and box._msuf2RangeFadePreviewLayerMode == "health"
    local wholeFrameMul = rangeAlpha ~= nil and not rangeHealthOnly and rangeAlpha or 1
    local healthMul = rangeHealthOnly and rangeAlpha or 1
    if mock.SetAlpha then mock:SetAlpha(wholeFrameMul) end
    -- hpBG is the only full-frame surface, exactly like the live frame. The
    -- plain preview root cannot stack a black alpha plate underneath it.
    if mock.SetBackdropColor then mock:SetBackdropColor(0, 0, 0, 0) end
    if mock._msufPreviewRoundedActive == true then
        PreviewSetRoundedEdgeStackAlpha(mock, (mock._msufPreviewRoundedEdgeEnabled ~= false) and 1 or 0)
    end
    -- Render owns health media and opacity. Dependent overlays/text/portrait
    -- and power remain independently composited, matching the live element.
    Core.SetRegionAlpha(mock.healPred, (alpha.flat and alpha.frame or alpha.hp) * healthMul)
    Core.SetRegionAlpha(mock.absorb, (alpha.flat and alpha.frame or alpha.hp) * healthMul)
    Core.SetRegionAlpha(mock.healAbsorb, (alpha.flat and alpha.frame or alpha.hp) * healthMul)
    Core.SetRegionAlpha(mock.powerBG, alpha.flat and alpha.frame or 1)
    Core.SetRegionAlpha(mock.power, alpha.flat and alpha.frame or alpha.power)
    Core.SetRegionAlpha(mock.classPower, alpha.flat and alpha.frame or alpha.power)
    Core.SetRegionAlpha(mock.detachedPower, alpha.flat and alpha.frame or alpha.power)
    if mock.detachedPower and mock.detachedPower.fill then Core.SetRegionAlpha(mock.detachedPower.fill, 1) end
    Core.SetRegionAlpha(mock.portrait, alpha.flat and alpha.frame or alpha.portrait)
    Core.SetRegionAlpha(mock.textFrame, alpha.flat and alpha.frame or alpha.text)
    Core.SetRegionAlpha(mock.cast, alpha.flat and alpha.frame or alpha.fg)
    for _, icon in pairs(mock.icons or {}) do
        Core.SetRegionAlpha(icon, (alpha.flat and alpha.frame or alpha.fg) * wholeFrameMul)
    end
    for i = 1, #(box.handles or {}) do
        Core.SetRegionAlpha(box.handles[i], wholeFrameMul)
    end
end
Preview.SetRegionAlpha = Core.SetRegionAlpha
Preview.SetFrameBackdropAlpha = Core.SetFrameBackdropAlpha
Preview.ApplyPreviewTransparency = Core.ApplyPreviewTransparency
