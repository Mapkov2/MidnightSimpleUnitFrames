--- Group preview rounded-frame and outline helpers.
---
--- This isolates the mask/outline subsystem from the native group preview
--- renderer, keeping the renderer focused on layout and composition.
local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local Rounded = M.GroupPreviewRounded or {}
M.GroupPreviewRounded = Rounded
function Rounded.Install(deps)
    deps = deps or {}
    local PreviewHelpers = deps.PreviewHelpers or {}
    local Specs = deps.Specs or {}
    local WHITE8X8 = deps.WHITE8X8 or "Interface\\Buttons\\WHITE8X8"
    local GF_PREVIEW_ROUNDED_MASK = deps.ROUNDED_MASK
    local GF_PREVIEW_ROUNDED_EDGE = deps.ROUNDED_EDGE
    local GF_PREVIEW_ROUNDED_STRENGTH = 3
    local ReadBarsBool = deps.ReadBarsBool or function(_, default) return default == true end
    local Round = deps.Round or function(value) return math.floor((tonumber(value) or 0) + 0.5) end
    local HealPredAnchorMode = deps.HealPredAnchorMode or function() return 3 end
local function RoundedEnabled()
    return ReadBarsBool("roundedFramesEnabled", false)
        and ReadBarsBool("roundedGroupFrames", true)
end
local function RoundedPowerEnabled()
    return ReadBarsBool("roundedFramesEnabled", false)
        and ReadBarsBool("roundedPowerBars", true)
end
local function SnapOff(region)
    if PreviewHelpers.SnapOff then PreviewHelpers.SnapOff(region) end
end
local BaseEdgeColor
local GF_PREVIEW_OUTLINE_KEYS = Specs.OUTLINE_KEYS or { "top", "bottom", "left", "right" }
local GF_PREVIEW_OUTLINE_OPTS = {
    keys = GF_PREVIEW_OUTLINE_KEYS,
    linesKey = "_lines",
    texture = WHITE8X8,
    snapOff = SnapOff,
}
local function SetOutlineShown(mock, shown)
    local frame = mock and mock._outlineFrame
    if frame then
        if shown then frame:Show() else frame:Hide() end
    end
    if PreviewHelpers.SetEdgeLinesShown then PreviewHelpers.SetEdgeLinesShown(frame, shown, GF_PREVIEW_OUTLINE_OPTS) end
end
local function LayoutOutline(mock, edge)
    edge = Round(edge)
    if not mock or edge <= 0 then
        SetOutlineShown(mock, false)
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
    GF_PREVIEW_OUTLINE_OPTS.color = function() return BaseEdgeColor(mock) end
    if PreviewHelpers.LayoutEdgeLines then PreviewHelpers.LayoutEdgeLines(frame, edge, GF_PREVIEW_OUTLINE_OPTS) end
    SetOutlineShown(mock, true)
end
local function EnsureRoundedMask(mock, key, anchor, tex)
    if not PreviewHelpers.EnsureRoundedMask then return nil end
    return PreviewHelpers.EnsureRoundedMask(mock, key, anchor, tex, "_msufGFRoundedPreviewMasks", GF_PREVIEW_ROUNDED_MASK, SnapOff)
end
local function SetMask(mock, tex, mask)
    if PreviewHelpers.SetMask then PreviewHelpers.SetMask(mock, tex, mask, "_msufGFRoundedPreviewMasked") end
end
local function ClearRoundedMasks(mock)
    if PreviewHelpers.ClearMasks then PreviewHelpers.ClearMasks(mock, "_msufGFRoundedPreviewMasked") end
end
local GF_PREVIEW_GRADIENT_DIRECTIONS = { "left", "right", "up", "down" }
local function ApplyGradientMasks(mock, grads, key, anchor, enabled)
    if type(grads) ~= "table" then return end
    for i = 1, #GF_PREVIEW_GRADIENT_DIRECTIONS do
        local tex = grads[GF_PREVIEW_GRADIENT_DIRECTIONS[i]]
        if tex then
            local mask = enabled and EnsureRoundedMask(mock, key, anchor, tex) or nil
            SetMask(mock, tex, mask)
        end
    end
end
local function StatusBarTexture(bar)
    return bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture() or nil
end
function BaseEdgeColor(mock)
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
    snapOff = SnapOff,
    baseEdgeColor = function(mock) return BaseEdgeColor(mock) end,
}
local GF_PREVIEW_POWER_ROUNDED_OPTS = {
    bgKey = "_msufGFRoundedPreviewBg",
    edgeKey = "_msufGFRoundedPreviewEdge",
    stackKey = "_msufGFRoundedPreviewEdgeStack",
    countKey = "_msufGFRoundedPreviewEdgeCount",
    whiteTexture = WHITE8X8,
    edgeTexture = GF_PREVIEW_ROUNDED_EDGE,
    edgeLayer = "OVERLAY",
    edgeSubLevel = 6,
    snapOff = SnapOff,
    baseEdgeColor = function(mock)
        if mock and mock._msufGFPreviewPowerBorderR ~= nil then
            return mock._msufGFPreviewPowerBorderR, mock._msufGFPreviewPowerBorderG,
                mock._msufGFPreviewPowerBorderB, mock._msufGFPreviewPowerBorderA
        end
        return BaseEdgeColor(mock)
    end,
}
local function UpdateRoundedMedia(mock)
    if type(PreviewHelpers.ResolveRoundedMedia) == "function" then
        GF_PREVIEW_ROUNDED_MASK, GF_PREVIEW_ROUNDED_EDGE, GF_PREVIEW_ROUNDED_STRENGTH = PreviewHelpers.ResolveRoundedMedia()
    end
    mock._msufPreviewRoundedMediaStrength = GF_PREVIEW_ROUNDED_STRENGTH
    GF_PREVIEW_ROUNDED_OPTS.edgeTexture = GF_PREVIEW_ROUNDED_EDGE
    GF_PREVIEW_ROUNDED_OPTS.mediaStrength = GF_PREVIEW_ROUNDED_STRENGTH
    GF_PREVIEW_POWER_ROUNDED_OPTS.edgeTexture = GF_PREVIEW_ROUNDED_EDGE
    GF_PREVIEW_POWER_ROUNDED_OPTS.mediaStrength = GF_PREVIEW_ROUNDED_STRENGTH
end
local function EnsureRoundedVisuals(mock)
    return PreviewHelpers.EnsureRoundedVisuals and PreviewHelpers.EnsureRoundedVisuals(mock, GF_PREVIEW_ROUNDED_OPTS)
end
local function SetRoundedEdgeStackShown(mock, shown)
    if PreviewHelpers.SetRoundedEdgeStackShown then PreviewHelpers.SetRoundedEdgeStackShown(mock, shown, GF_PREVIEW_ROUNDED_OPTS) end
end
local function ApplyRoundedEdgeStack(mock, edgeSize)
    return PreviewHelpers.ApplyRoundedEdgeStack and PreviewHelpers.ApplyRoundedEdgeStack(mock, edgeSize, GF_PREVIEW_ROUNDED_OPTS)
end
local function SetPowerRoundedEdgeShown(power, shown)
    if PreviewHelpers.SetRoundedEdgeStackShown then
        PreviewHelpers.SetRoundedEdgeStackShown(power, shown, GF_PREVIEW_POWER_ROUNDED_OPTS)
    end
    if power and power._msufGFRoundedPreviewBg then power._msufGFRoundedPreviewBg:Hide() end
end
local function ApplyPowerBorder(mock, powerOn, thickness, embedded, roundedPower)
    if not mock then return end
    local host = mock._msufGFPreviewPowerBorder
    local edge = Round(thickness)
    if edge < 0 then edge = 0 elseif edge > 8 then edge = 8 end
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
            line:SetTexture(WHITE8X8)
            host.edges[i] = line
        end
        mock._msufGFPreviewPowerBorder = host
    end
    -- Elements_Power parents this rectangular border surface to the power bar
    -- and keeps it two details above that bar. The preview host is mock-owned,
    -- so explicitly follow the bar when a detached Layer moves it far above
    -- the frame body.
    if host.SetFrameLevel and mock._power and mock._power.GetFrameLevel then
        host:SetFrameLevel((mock._power:GetFrameLevel() or 0) + 2)
    end
    if roundedPower and not embedded then
        host:Hide()
        return
    end
    local top, bottom, left, right = host.edges[1], host.edges[2], host.edges[3], host.edges[4]
    for i = 1, 4 do host.edges[i]:Hide() end
    host:ClearAllPoints()
    host:SetAllPoints(mock._power)
    local r = mock._msufGFPreviewPowerBorderR
    local g = mock._msufGFPreviewPowerBorderG
    local b = mock._msufGFPreviewPowerBorderB
    local a = mock._msufGFPreviewPowerBorderA
    if r == nil then r, g, b, a = BaseEdgeColor(mock) end
    for i = 1, 4 do host.edges[i]:SetVertexColor(r or 0, g or 0, b or 0, a == nil and 1 or a) end
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
local function ApplyRounded(mock, conf, powerOn, edgeSize, powerEmbed, powerDetached, powerEdgeSize)
    if not mock then return false end
    local enabled = RoundedEnabled()
    if enabled then UpdateRoundedMedia(mock) end
    if not enabled or not EnsureRoundedVisuals(mock) then
        mock._msufGFRoundedPreviewActive = nil
        ClearRoundedMasks(mock)
        if mock._roundedBg then mock._roundedBg:Hide() end
        SetRoundedEdgeStackShown(mock, false)
        SetPowerRoundedEdgeShown(mock._power, false)
        ApplyPowerBorder(mock, powerOn, powerEdgeSize, powerEmbed ~= false and powerDetached ~= true, false)
        return false
    end
    mock._msufGFRoundedPreviewActive = true
    local healthTex = StatusBarTexture(mock._health)
    local dispelOverlay = mock._msufGFPreviewDispelOverlayRegion
    local tempMaxHealthTex = StatusBarTexture(mock._tempMaxHealth)
    local healPredTex = StatusBarTexture(mock._healPred)
    local absorbTex = StatusBarTexture(mock._absorb)
    local healAbsorbTex = StatusBarTexture(mock._healAbsorb)
    local powerTex = StatusBarTexture(mock._power)
    local roundPower = powerOn and RoundedPowerEnabled()
    local sharedBody = roundPower and powerEmbed ~= false and powerDetached ~= true
    ApplyPowerBorder(mock, powerOn, powerEdgeSize, sharedBody, roundPower)
    local healthAnchor = sharedBody and mock or mock._health
    local powerAnchor = sharedBody and mock or mock._power
    local bodyMask = EnsureRoundedMask(mock, "body", mock, mock._roundedBg)
    local healthBgMask = EnsureRoundedMask(mock, "health", healthAnchor, mock._healthBg)
    local healthTexMask = EnsureRoundedMask(mock, "health", healthAnchor, healthTex)
    local dispelOverlayMask = dispelOverlay and dispelOverlay:IsShown()
        and EnsureRoundedMask(mock, "dispelOverlay", healthAnchor, dispelOverlay) or nil
    local tempMaxHealthBgMask = EnsureRoundedMask(mock, "tempMaxHealthBg", sharedBody and mock or mock._tempMaxHealth, mock._tempMaxHealthBg)
    local tempMaxHealthMask = EnsureRoundedMask(mock, "tempMaxHealth", sharedBody and mock or mock._tempMaxHealth, tempMaxHealthTex)
    local healPredMask = EnsureRoundedMask(mock, "healPred", sharedBody and mock or mock._healPred, healPredTex)
    local absorbMask = EnsureRoundedMask(mock, "absorb", sharedBody and mock or mock._absorb, absorbTex)
    local healAbsorbMask = EnsureRoundedMask(mock, "healAbsorb", sharedBody and mock or mock._healAbsorb, healAbsorbTex)
    local healPredMode = HealPredAnchorMode(conf)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    local absorbMode = tonumber((conf and conf.hlOverride and conf.absorbAnchorMode ~= nil and conf.absorbAnchorMode) or (gen and gen.absorbAnchorMode)) or 2
    if absorbMode < 1 or absorbMode > 5 then absorbMode = 2 end
    local powerBgMask = roundPower and EnsureRoundedMask(mock, "power", powerAnchor, mock._powerBg) or nil
    local powerTexMask = roundPower and EnsureRoundedMask(mock, "power", powerAnchor, powerTex) or nil
    if not (bodyMask and healthBgMask and healthTexMask) then
        mock._msufGFRoundedPreviewActive = nil
        ClearRoundedMasks(mock)
        if mock._roundedBg then mock._roundedBg:Hide() end
        SetRoundedEdgeStackShown(mock, false)
        ApplyPowerBorder(mock, powerOn, powerEdgeSize, powerEmbed ~= false and powerDetached ~= true, false)
        return false
    end
    SetMask(mock, mock._roundedBg, bodyMask)
    SetMask(mock, mock._healthBg, healthBgMask)
    SetMask(mock, healthTex, healthTexMask)
    ApplyGradientMasks(mock, mock._msufGFPreviewHealthGradients,
        "healthGradient", healthAnchor, true)
    SetMask(mock, dispelOverlay, dispelOverlayMask)
    SetMask(mock, mock._tempMaxHealthBg, tempMaxHealthBgMask)
    SetMask(mock, tempMaxHealthTex, tempMaxHealthMask)
    SetMask(mock, healPredTex, healPredMode == 4 and nil or healPredMask)
    SetMask(mock, absorbTex, absorbMode == 4 and nil or absorbMask)
    SetMask(mock, healAbsorbTex, healAbsorbMask)
    SetMask(mock, mock._powerBg, powerBgMask)
    SetMask(mock, powerTex, powerTexMask)
    ApplyGradientMasks(mock, mock._msufGFPreviewPowerGradients,
        "powerGradient", powerAnchor, roundPower)
    if roundPower and not sharedBody and PreviewHelpers.EnsureRoundedVisuals
        and PreviewHelpers.EnsureRoundedVisuals(mock._power, GF_PREVIEW_POWER_ROUNDED_OPTS) then
        local powerEdge = Round(powerEdgeSize)
        if powerEdge < 0 then powerEdge = 0 elseif powerEdge > 8 then powerEdge = 8 end
        if powerEdge > 0 and PreviewHelpers.ApplyRoundedEdgeStack then
            PreviewHelpers.ApplyRoundedEdgeStack(mock._power, powerEdge, GF_PREVIEW_POWER_ROUNDED_OPTS)
        else
            SetPowerRoundedEdgeShown(mock._power, false)
        end
        if mock._power.SetBackdropBorderColor then mock._power:SetBackdropBorderColor(0, 0, 0, 0) end
        if mock._power._msufGFRoundedPreviewBg then mock._power._msufGFRoundedPreviewBg:Hide() end
    else
        SetPowerRoundedEdgeShown(mock._power, false)
    end
    mock._roundedBg:ClearAllPoints()
    mock._roundedBg:SetAllPoints(mock)
    mock._roundedBg:SetColorTexture(conf.bgR or 0.08, conf.bgG or 0.08, conf.bgB or 0.09, conf.bgA or 0.88)
    mock._roundedBg:Show()
    edgeSize = Round(edgeSize)
    if edgeSize > 0 then
        ApplyRoundedEdgeStack(mock, edgeSize)
    else
        SetRoundedEdgeStackShown(mock, false)
    end
    if mock.SetBackdropColor then mock:SetBackdropColor(0, 0, 0, 0) end
    if mock.SetBackdropBorderColor then mock:SetBackdropBorderColor(0, 0, 0, 0) end
    return true
end
    return { SetOutlineShown = SetOutlineShown, LayoutOutline = LayoutOutline, BaseEdgeColor = BaseEdgeColor, ApplyRounded = ApplyRounded }
end
