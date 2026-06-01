--- Group preview rounded-frame and outline helpers.
---
--- This isolates the mask/outline subsystem from the native group preview
--- renderer, keeping the renderer focused on layout and composition.
local _, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local Rounded = M.GroupPreviewRounded or {}
M.GroupPreviewRounded = Rounded

function Rounded.Install(deps)
    deps = deps or {}
    local PreviewHelpers = deps.PreviewHelpers or {}
    local Specs = deps.Specs or {}
    local WHITE8X8 = deps.WHITE8X8 or "Interface\\Buttons\\WHITE8X8"
    local GF_PREVIEW_ROUNDED_MASK = deps.ROUNDED_MASK
    local GF_PREVIEW_ROUNDED_EDGE = deps.ROUNDED_EDGE
    local GFPreviewReadBarsBool = deps.ReadBarsBool or function(_, default) return default == true end
    local GFPreviewRound = deps.Round or function(value) return math.floor((tonumber(value) or 0) + 0.5) end
    local GFPreviewHealPredAnchorMode = deps.HealPredAnchorMode or function() return 3 end
local function GFPreviewRoundedEnabled()
    return GFPreviewReadBarsBool("roundedFramesEnabled", false)
        and GFPreviewReadBarsBool("roundedGroupFrames", true)
end

local function GFPreviewRoundedPowerEnabled()
    return GFPreviewReadBarsBool("roundedFramesEnabled", false)
        and GFPreviewReadBarsBool("roundedPowerBars", true)
end

local function GFPreviewSnapOff(region)
    if PreviewHelpers.SnapOff then PreviewHelpers.SnapOff(region) end
end

local GFPreviewBaseEdgeColor
local GF_PREVIEW_OUTLINE_KEYS = Specs.OUTLINE_KEYS or { "top", "bottom", "left", "right" }
local GF_PREVIEW_OUTLINE_OPTS = {
    keys = GF_PREVIEW_OUTLINE_KEYS,
    linesKey = "_lines",
    texture = WHITE8X8,
    snapOff = GFPreviewSnapOff,
}

local function GFPreviewSetOutlineShown(mock, shown)
    local frame = mock and mock._outlineFrame
    if frame then
        if shown then frame:Show() else frame:Hide() end
    end
    if PreviewHelpers.SetEdgeLinesShown then PreviewHelpers.SetEdgeLinesShown(frame, shown, GF_PREVIEW_OUTLINE_OPTS) end
end

local function GFPreviewLayoutOutline(mock, edge)
    edge = GFPreviewRound(edge)
    if not mock or edge <= 0 then
        GFPreviewSetOutlineShown(mock, false)
        return
    end

    local frame = mock._outlineFrame
    if not frame then
        frame = CreateFrame("Frame", nil, mock)
        frame:EnableMouse(false)
        mock._outlineFrame = frame
    end
    if frame.SetFrameLevel and mock.GetFrameLevel then frame:SetFrameLevel(mock:GetFrameLevel() + 4) end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", mock, "TOPLEFT", -edge, edge)
    frame:SetPoint("BOTTOMRIGHT", mock, "BOTTOMRIGHT", edge, -edge)
    GF_PREVIEW_OUTLINE_OPTS.color = function() return GFPreviewBaseEdgeColor(mock) end
    if PreviewHelpers.LayoutEdgeLines then PreviewHelpers.LayoutEdgeLines(frame, edge, GF_PREVIEW_OUTLINE_OPTS) end
    GFPreviewSetOutlineShown(mock, true)
end

local function GFPreviewEnsureRoundedMask(mock, key, anchor, tex)
    if not PreviewHelpers.EnsureRoundedMask then return nil end
    return PreviewHelpers.EnsureRoundedMask(mock, key, anchor, tex, "_msufGFRoundedPreviewMasks", GF_PREVIEW_ROUNDED_MASK, GFPreviewSnapOff)
end

local function GFPreviewSetMask(mock, tex, mask)
    if PreviewHelpers.SetMask then PreviewHelpers.SetMask(mock, tex, mask, "_msufGFRoundedPreviewMasked") end
end

local function GFPreviewClearRoundedMasks(mock)
    if PreviewHelpers.ClearMasks then PreviewHelpers.ClearMasks(mock, "_msufGFRoundedPreviewMasked") end
end

local function GFPreviewStatusBarTexture(bar)
    return bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture() or nil
end

function GFPreviewBaseEdgeColor(mock)
    if mock and mock._msufGFPreviewBorderR then
        return mock._msufGFPreviewBorderR or 0,
            mock._msufGFPreviewBorderG or 0,
            mock._msufGFPreviewBorderB or 0,
            mock._msufGFPreviewBorderA or 1
    end
    if PreviewHelpers.BaseEdgeColor then return PreviewHelpers.BaseEdgeColor() end
    return 0, 0, 0, 1
end

local GF_PREVIEW_ROUNDED_OPTS = {
    bgKey = "_roundedBg",
    edgeKey = "_roundedEdge",
    stackKey = "_msufGFRoundedPreviewEdgeStack",
    countKey = "_msufGFRoundedPreviewEdgeCount",
    whiteTexture = WHITE8X8,
    edgeTexture = GF_PREVIEW_ROUNDED_EDGE,
    bgLayer = "BACKGROUND",
    bgSubLevel = -7,
    edgeLayer = "OVERLAY",
    edgeSubLevel = 6,
    snapOff = GFPreviewSnapOff,
    baseEdgeColor = function(mock) return GFPreviewBaseEdgeColor(mock) end,
}

local function GFPreviewEnsureRoundedVisuals(mock)
    return PreviewHelpers.EnsureRoundedVisuals and PreviewHelpers.EnsureRoundedVisuals(mock, GF_PREVIEW_ROUNDED_OPTS)
end

local function GFPreviewSetRoundedEdgeStackShown(mock, shown)
    if PreviewHelpers.SetRoundedEdgeStackShown then PreviewHelpers.SetRoundedEdgeStackShown(mock, shown, GF_PREVIEW_ROUNDED_OPTS) end
end

local function GFPreviewApplyRoundedEdgeStack(mock, edgeSize)
    return PreviewHelpers.ApplyRoundedEdgeStack and PreviewHelpers.ApplyRoundedEdgeStack(mock, edgeSize, GF_PREVIEW_ROUNDED_OPTS)
end

local function GFPreviewApplyRounded(mock, conf, powerOn, edgeSize)
    if not mock then return false end
    if not GFPreviewRoundedEnabled() or not GFPreviewEnsureRoundedVisuals(mock) then
        mock._msufGFRoundedPreviewActive = nil
        GFPreviewClearRoundedMasks(mock)
        if mock._roundedBg then mock._roundedBg:Hide() end
        GFPreviewSetRoundedEdgeStackShown(mock, false)
        return false
    end

    mock._msufGFRoundedPreviewActive = true
    local healthTex = GFPreviewStatusBarTexture(mock._health)
    local healPredTex = GFPreviewStatusBarTexture(mock._healPred)
    local absorbTex = GFPreviewStatusBarTexture(mock._absorb)
    local powerTex = GFPreviewStatusBarTexture(mock._power)
    local bodyMask = GFPreviewEnsureRoundedMask(mock, "body", mock, mock._roundedBg)
    local healthBgMask = GFPreviewEnsureRoundedMask(mock, "health", mock._health, mock._healthBg)
    local healthTexMask = GFPreviewEnsureRoundedMask(mock, "health", mock._health, healthTex)
    local healPredMask = GFPreviewEnsureRoundedMask(mock, "healPred", mock._healPred, healPredTex)
    local absorbMask = GFPreviewEnsureRoundedMask(mock, "absorb", mock._absorb, absorbTex)
    local healPredMode = GFPreviewHealPredAnchorMode(conf)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    local absorbMode = tonumber((conf and conf.hlOverride and conf.absorbAnchorMode ~= nil and conf.absorbAnchorMode) or (gen and gen.absorbAnchorMode)) or 2
    if absorbMode < 1 or absorbMode > 5 then absorbMode = 2 end
    local powerBgMask = (powerOn and GFPreviewRoundedPowerEnabled()) and GFPreviewEnsureRoundedMask(mock, "power", mock._power, mock._powerBg) or nil
    local powerTexMask = (powerOn and GFPreviewRoundedPowerEnabled()) and GFPreviewEnsureRoundedMask(mock, "power", mock._power, powerTex) or nil
    if not (bodyMask and healthBgMask and healthTexMask) then
        mock._msufGFRoundedPreviewActive = nil
        GFPreviewClearRoundedMasks(mock)
        if mock._roundedBg then mock._roundedBg:Hide() end
        GFPreviewSetRoundedEdgeStackShown(mock, false)
        return false
    end

    GFPreviewSetMask(mock, mock._roundedBg, bodyMask)
    GFPreviewSetMask(mock, mock._healthBg, healthBgMask)
    GFPreviewSetMask(mock, healthTex, healthTexMask)
    GFPreviewSetMask(mock, healPredTex, healPredMode == 4 and nil or healPredMask)
    GFPreviewSetMask(mock, absorbTex, absorbMode == 4 and nil or absorbMask)
    GFPreviewSetMask(mock, mock._powerBg, powerBgMask)
    GFPreviewSetMask(mock, powerTex, powerTexMask)

    mock._roundedBg:ClearAllPoints()
    mock._roundedBg:SetAllPoints(mock)
    mock._roundedBg:SetColorTexture(conf.bgR or 0.08, conf.bgG or 0.08, conf.bgB or 0.09, conf.bgA or 0.88)
    mock._roundedBg:Show()

    edgeSize = GFPreviewRound(edgeSize)
    if edgeSize > 0 then
        GFPreviewApplyRoundedEdgeStack(mock, edgeSize)
    else
        GFPreviewSetRoundedEdgeStackShown(mock, false)
    end

    if mock.SetBackdropColor then mock:SetBackdropColor(0, 0, 0, 0) end
    if mock.SetBackdropBorderColor then mock:SetBackdropBorderColor(0, 0, 0, 0) end
    return true
end


    return {
        SetOutlineShown = GFPreviewSetOutlineShown,
        LayoutOutline = GFPreviewLayoutOutline,
        BaseEdgeColor = GFPreviewBaseEdgeColor,
        ApplyRounded = GFPreviewApplyRounded,
    }
end
