--- Menu2/Preview/MSUF_Menu2_UnitPreview_Core.lua
--- Cold-path shared helpers for the MSUF2 unit frame preview.
local addonName, addonNS = ...
local MSUF = addonNS or (_G.MSUF_NS) or {}
_G.MSUF_NS = MSUF

local floor = math.floor
local TEX_W8 = "Interface\\Buttons\\WHITE8X8"
local MEDIA = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\"
local MASK_MEDIA = MEDIA .. "Masks\\"
local PREVIEW_ROUNDED_MASK = MASK_MEDIA .. "rounded_bar_4x.tga"
local PREVIEW_ROUNDED_EDGE = MASK_MEDIA .. "rounded_bar_edge_4x.tga"

local Preview = MSUF.UFPreview or {}
MSUF.UFPreview = Preview
_G.MSUF_UFPreview = Preview

local PreviewModel = Preview.Model or {}
local UnitDB = PreviewModel.UnitDB
local Clamp01 = PreviewModel.Clamp01
local PreviewResolveHealPredAnchorMode = PreviewModel.PreviewResolveHealPredAnchorMode
local PreviewResolveAbsorbAnchorMode = PreviewModel.PreviewResolveAbsorbAnchorMode
local PreviewHelpers = (MSUF.MSUF2 and MSUF.MSUF2.PreviewHelpers) or {}

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
    return PreviewHelpers.EnsureRoundedMask(mock, key, anchor, tex, "_msufPreviewRoundedMasks", PREVIEW_ROUNDED_MASK, PreviewSnapOff)
end

local function PreviewSetMask(mock, tex, mask)
    if PreviewHelpers.SetMask then PreviewHelpers.SetMask(mock, tex, mask, "_msufPreviewRoundedMasked") end
end

local function ClearPreviewRoundedMasks(mock)
    if PreviewHelpers.ClearMasks then PreviewHelpers.ClearMasks(mock, "_msufPreviewRoundedMasked") end
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

local function EnsureFrameBorderOverlay(mock)
    if not (mock and mock.CreateTexture) then return nil end
    local overlay = mock._msufPreviewFrameBorder
    if not overlay then
        overlay = CreateFrame("Frame", nil, mock)
        overlay:EnableMouse(false)
        overlay:SetAllPoints(mock)
        overlay._edges = {}
        mock._msufPreviewFrameBorder = overlay
    end
    if overlay.SetFrameLevel and mock.GetFrameLevel then
        overlay:SetFrameLevel((mock:GetFrameLevel() or 0) + 40)
    end
    return overlay
end

local function SetFrameBorderShown(mock, shown)
    local overlay = mock and mock._msufPreviewFrameBorder
    if overlay then
        Core.SetShownSafe(overlay, shown)
    end
    if PreviewHelpers.SetEdgeLinesShown then PreviewHelpers.SetEdgeLinesShown(overlay, shown, FRAME_BORDER_OPTS) end
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

    local overlay = EnsureFrameBorderOverlay(mock)
    if not overlay then return end
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", mock, "TOPLEFT", -thickness, thickness)
    overlay:SetPoint("BOTTOMRIGHT", mock, "BOTTOMRIGHT", thickness, -thickness)
    FRAME_BORDER_OPTS.color = function()
        local r, g, b, a = border.r, border.g, border.b, border.a
        if r == nil then r, g, b, a = Core.BaseEdgeColor() end
        return r or 0, g or 0, b or 0, a == nil and 1 or a
    end
    if PreviewHelpers.LayoutEdgeLines then PreviewHelpers.LayoutEdgeLines(overlay, thickness, FRAME_BORDER_OPTS) end
    mock._msufPreviewFrameBorderEnabled = true
    SetFrameBorderShown(mock, true)
end

local BOUNDS_GUIDE_KEYS = { "top", "bottom", "left", "right" }
local BOUNDS_GUIDE_OPTS = {
    keys = BOUNDS_GUIDE_KEYS,
    linesKey = "_msufGuideLines",
    texture = TEX_W8,
    snapOff = PreviewSnapOff,
    color = function() return 1, 0.14, 0.08, 0.95 end,
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
    bgKey = "roundedBg",
    edgeKey = "roundedEdge",
    stackKey = "_msufPreviewRoundedEdgeStack",
    countKey = "_msufPreviewRoundedEdgeCount",
    whiteTexture = TEX_W8,
    edgeTexture = PREVIEW_ROUNDED_EDGE,
    snapOff = PreviewSnapOff,
    clamp01 = Clamp01,
    baseEdgeColor = function() return Core.BaseEdgeColor() end,
}

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

function Core.ApplyRounded(box, key, powerOn, outlineThickness)
    if not (box and box.mock) then return end
    local mock = box.mock
    local rounded = PreviewRoundedUnitFramesEnabled()
    if not rounded or not EnsurePreviewRoundedVisuals(mock) then
        mock._msufPreviewRoundedActive = nil
        mock._msufPreviewRoundedEdgeEnabled = nil
        ClearPreviewRoundedMasks(mock)
        Core.SetShownSafe(mock.roundedBg, false)
        PreviewSetRoundedEdgeStackShown(mock, false)
        return
    end
    mock._msufPreviewRoundedActive = true

    local bodyMask = EnsurePreviewRoundedMask(mock, "body", mock, mock.roundedBg)
    local hpBgMask = EnsurePreviewRoundedMask(mock, "health", mock.hpBG, mock.hpBG)
    local hpMask = EnsurePreviewRoundedMask(mock, "health", mock.hpBG, mock.hp)
    local healPredMask = EnsurePreviewRoundedMask(mock, "healPred", mock.hpBG, mock.healPred)
    local absorbMask = EnsurePreviewRoundedMask(mock, "absorb", mock.hpBG, mock.absorb)
    local conf, g = UnitDB(key)
    local healPredMode = PreviewResolveHealPredAnchorMode(conf, g)
    local absorbMode = PreviewResolveAbsorbAnchorMode(conf, g)
    PreviewSetMask(mock, mock.roundedBg, bodyMask)
    PreviewSetMask(mock, mock.hpBG, hpBgMask)
    PreviewSetMask(mock, mock.hp, hpMask)
    PreviewSetMask(mock, mock.healPred, healPredMode == 4 and nil or healPredMask)
    PreviewSetMask(mock, mock.absorb, absorbMode == 4 and nil or absorbMask)

    local powerBgMask = (powerOn and PreviewRoundedPowerBarsEnabled()) and EnsurePreviewRoundedMask(mock, "power", mock.powerBG, mock.powerBG) or nil
    local powerMask = (powerOn and PreviewRoundedPowerBarsEnabled()) and EnsurePreviewRoundedMask(mock, "power", mock.powerBG, mock.power) or nil
    PreviewSetMask(mock, mock.powerBG, powerBgMask)
    PreviewSetMask(mock, mock.power, powerMask)

    mock.roundedBg:ClearAllPoints()
    mock.roundedBg:SetAllPoints(mock)
    mock.roundedBg:SetColorTexture(0, 0, 0, 0.92)
    mock.roundedBg:Show()

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
    local bodyOn = LayerOn("body")
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
    if bodyOn then
        if roundedActive then
            mock:SetBackdropColor(0, 0, 0, 0)
            mock:SetBackdropBorderColor(0, 0, 0, 0)
            Core.SetShownSafe(mock.roundedBg, true)
            PreviewSetRoundedEdgeStackShown(mock, mock._msufPreviewRoundedEdgeEnabled ~= false)
            SetFrameBorderShown(mock, false)
        elseif mock._msufPreviewFrameBorderEnabled == true then
            mock:SetBackdropColor(0, 0, 0, 0.92)
            mock:SetBackdropBorderColor(0, 0, 0, 0)
            Core.SetShownSafe(mock.roundedBg, false)
            PreviewSetRoundedEdgeStackShown(mock, false)
            SetFrameBorderShown(mock, true)
        elseif mock._msufPreviewFrameBorderConfigured == true then
            mock:SetBackdropColor(0, 0, 0, 0.92)
            mock:SetBackdropBorderColor(0, 0, 0, 0)
            Core.SetShownSafe(mock.roundedBg, false)
            PreviewSetRoundedEdgeStackShown(mock, false)
            SetFrameBorderShown(mock, false)
        else
            local r, g, b = Core.BaseEdgeColor()
            mock:SetBackdropColor(0, 0, 0, 0.92)
            mock:SetBackdropBorderColor(r, g, b, 1)
            Core.SetShownSafe(mock.roundedBg, false)
            PreviewSetRoundedEdgeStackShown(mock, false)
            SetFrameBorderShown(mock, false)
        end
    else
        mock:SetBackdropColor(0, 0, 0, 0)
        mock:SetBackdropBorderColor(0, 0, 0, 0)
        Core.SetShownSafe(mock.roundedBg, false)
        PreviewSetRoundedEdgeStackShown(mock, false)
        SetFrameBorderShown(mock, false)
    end
    Core.SetShownSafe(mock.hpBG, bodyOn)
    Core.SetShownSafe(mock.hp, bodyOn)
    if not bodyOn then
        Core.SetShownSafe(mock.healPred, false)
        Core.SetShownSafe(mock.absorb, false)
    end

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
    if mock.classPower and mock.classPower.text and (not classOn or not mock.classPower:IsShown()) then
        Core.SetShownSafe(mock.classPower.text, false)
    end
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
    if not portraitOn then
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
    if mock.cast and mock.cast.sizeTag then
        Core.SetShownSafe(mock.cast.sizeTag, guidesOn and castOn and mock.cast:IsShown())
    end
    if not LayerOn("auras") then
        local Auras = MSUF.UFPreviewAuras
        if Auras and type(Auras.Hide) == "function" then Auras.Hide(box) end
    end
    if not statusOn then
        for _, icon in pairs(mock.icons or {}) do Core.SetShownSafe(icon, false) end
        Core.SetShownSafe(mock.raidGroupNameText, false)
        for _, handle in pairs(box.statusHandles or {}) do Core.SetShownSafe(handle, false) end
    end
    Core.SetShownSafe(mock.bounds, boundsOn)
end

function Core.InCombat()
    local inCombat = _G.MSUF_InCombat
    if inCombat == nil and _G.InCombatLockdown then inCombat = _G.InCombatLockdown() end
    return inCombat == true
end

local function NormalizeAlphaLayerMode(mode)
    if mode == true or mode == 1 or mode == "background" or mode == "backdrop" or mode == "bg" then
        return "background"
    elseif mode == 2 or mode == "health" or mode == "hp" or mode == "hpbar" then
        return "health"
    end
    return "foreground"
end

local function PreviewAlphaPair(conf, mode)
    if not conf then return 1, 1 end
    local aIn = Clamp01(conf.alphaInCombat, 1)
    local aOut = Clamp01(conf.alphaOutOfCombat, 1)
    if conf.alphaExcludeTextPortrait == true then
        mode = NormalizeAlphaLayerMode(mode)
        if mode == "background" then
            aIn = Clamp01(conf.alphaBGInCombat, aIn)
            aOut = Clamp01(conf.alphaBGOutOfCombat, aOut)
        elseif mode == "health" then
            aIn = Clamp01(conf.alphaHPInCombat, Clamp01(conf.alphaFGInCombat, aIn))
            aOut = Clamp01(conf.alphaHPOutOfCombat, Clamp01(conf.alphaFGOutOfCombat, aOut))
        else
            aIn = Clamp01(conf.alphaFGInCombat, aIn)
            aOut = Clamp01(conf.alphaFGOutOfCombat, aOut)
        end
    end
    local sync = conf.alphaSyncBoth
    if sync == nil then sync = conf.alphaSync end
    if sync then aOut = aIn end
    return aIn, aOut
end

local function PreviewCurrentAlpha(conf, mode)
    local aIn, aOut = PreviewAlphaPair(conf, mode)
    return Core.InCombat() and aIn or aOut
end

local function PreviewAlphaState(conf)
    local frameAlpha = PreviewCurrentAlpha(conf, "foreground")
    if _G.MSUF_UnitEditModeActive == true and frameAlpha < 0.35 then frameAlpha = 0.35 end
    if conf and conf.alphaExcludeTextPortrait == true then
        local mode = NormalizeAlphaLayerMode(conf.alphaLayerMode)
        local fg = 1
        local power = mode == "foreground" and PreviewCurrentAlpha(conf, "foreground") or 1
        local bg = mode == "background" and PreviewCurrentAlpha(conf, "background") or 1
        local hp = mode == "health" and PreviewCurrentAlpha(conf, "health") or 1
        return {
            flat = false,
            frame = 1,
            fg = fg,
            bg = bg,
            hp = hp,
            power = power,
            text = 1,
            portrait = 1,
            preserveHPColor = mode == "health" and conf.alphaPreserveHPColor == true,
        }
    end
    return {
        flat = true,
        frame = frameAlpha,
        fg = 1,
        bg = 1,
        hp = 1,
        power = 1,
        text = 1,
        portrait = 1,
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

function Core.ApplyPreviewTransparency(box, conf)
    if not box or not box.mock then return end
    local mock = box.mock
    local alpha = PreviewAlphaState(conf)
    local v = box.layerVisibility or {}
    local available = box.layerAvailable or {}
    local bodyOn = available.body ~= false and v.body ~= false
    if mock.SetAlpha then mock:SetAlpha(1) end
    if bodyOn then
        if mock._msufPreviewRoundedActive == true then
            Core.SetFrameBackdropAlpha(mock, 0, 0)
            Core.SetRegionAlpha(mock.roundedBg, 0.92 * (alpha.flat and alpha.frame or alpha.bg))
            PreviewSetRoundedEdgeStackAlpha(mock, (mock._msufPreviewRoundedEdgeEnabled ~= false) and (alpha.flat and alpha.frame or alpha.fg) or 0)
        else
            Core.SetFrameBackdropAlpha(mock, 0.92 * (alpha.flat and alpha.frame or alpha.bg), alpha.flat and alpha.frame or alpha.fg)
        end
    else
        Core.SetFrameBackdropAlpha(mock, 0, 0)
        Core.SetRegionAlpha(mock.roundedBg, 0)
        PreviewSetRoundedEdgeStackAlpha(mock, 0)
    end
    if alpha.preserveHPColor then
        Core.SetRegionAlpha(mock.hpBG, alpha.hp)
    else
        Core.SetRegionAlpha(mock.hpBG, alpha.flat and alpha.frame or alpha.bg)
    end
    Core.SetRegionAlpha(mock.hp, alpha.flat and alpha.frame or alpha.hp)
    Core.SetRegionAlpha(mock.healPred, alpha.flat and alpha.frame or alpha.hp)
    Core.SetRegionAlpha(mock.absorb, alpha.flat and alpha.frame or alpha.hp)
    Core.SetRegionAlpha(mock.powerBG, alpha.flat and alpha.frame or alpha.bg)
    Core.SetRegionAlpha(mock.power, alpha.flat and alpha.frame or alpha.power)
    Core.SetRegionAlpha(mock.classPower, alpha.flat and alpha.frame or alpha.power)
    Core.SetRegionAlpha(mock.detachedPower, alpha.flat and alpha.frame or alpha.power)
    if mock.detachedPower and mock.detachedPower.fill then Core.SetRegionAlpha(mock.detachedPower.fill, 1) end
    Core.SetRegionAlpha(mock.portrait, alpha.flat and alpha.frame or alpha.portrait)
    Core.SetRegionAlpha(mock.textFrame, alpha.flat and alpha.frame or alpha.text)
    Core.SetRegionAlpha(mock.cast, alpha.flat and alpha.frame or alpha.fg)
    for _, icon in pairs(mock.icons or {}) do
        Core.SetRegionAlpha(icon, alpha.flat and alpha.frame or alpha.fg)
    end
end

Preview.SetRegionAlpha = Core.SetRegionAlpha
Preview.SetFrameBackdropAlpha = Core.SetFrameBackdropAlpha
Preview.ApplyPreviewTransparency = Core.ApplyPreviewTransparency
