local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
--- Group preview rounded-frame and outline helpers.
---
--- This isolates the mask/outline subsystem from the native group preview
--- renderer, keeping the renderer focused on layout and composition. It loads
--- before the native renderer, which reads its exports (Rounded.*) at load.
local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local EnsureDB = M.EnsureDB
local Rounded = M.GroupPreviewRounded or {}
M.GroupPreviewRounded = Rounded
local floor = math.floor
local PreviewHelpers = M.PreviewHelpers or {}
local Specs = M.GroupPreviewSpecs or {}
local WHITE8X8 = Specs.WHITE8X8 or "Interface\\Buttons\\WHITE8X8"
local maskRoot = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\Masks\\"
local GF_PREVIEW_ROUNDED_MASK = Specs.ROUNDED_MASK or (maskRoot .. "rounded_clean_mask_s3.png")
local GF_PREVIEW_ROUNDED_EDGE = Specs.ROUNDED_EDGE or (maskRoot .. "rounded_clean_edge_s3.png")
local GF_PREVIEW_ROUNDED_STRENGTH = 3
local ReadBarsBool = PreviewHelpers.ReadPreviewBarsBool
local function Round(value)
    return floor((tonumber(value) or 0) + 0.5)
end
local function NormalizeAnchorMode(value, fallback)
    local mode = tonumber(value) or fallback or 3
    if mode < 1 or mode > 5 then mode = fallback or 3 end
    return mode
end
local function HealPredAnchorMode(conf)
    if conf and conf.hlOverride == true and conf.healPredAnchorMode ~= nil then return NormalizeAnchorMode(conf.healPredAnchorMode, 3) end
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    return NormalizeAnchorMode(gen and gen.healPredAnchorMode, 3)
end
local function FrameStyle(conf)
    local explicit = conf and conf.frameBarShape
    if explicit == "SLANTED" and ReadBarsBool("slantedBarsEnabled", true)
        and ReadBarsBool("slantedGroupFrames", true) then return "SLANTED" end
    if explicit == "ROUNDED" or explicit == "SQUARE" then return explicit end
    if ReadBarsBool("roundedFramesEnabled", false)
        and ReadBarsBool("roundedGroupFrames", true) then return "ROUNDED" end
    return "SQUARE"
end
local function RoundedPowerEnabled(conf)
    local style = FrameStyle(conf)
    if style == "SQUARE" then return false end
    if style == "SLANTED" then return ReadBarsBool("slantedPowerBars", true) end
    if conf and conf.frameBarShape == "ROUNDED" then return true end
    return ReadBarsBool("roundedPowerBars", true)
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
        frame = PixelLayoutRegion(CreateFrame("Frame", nil, mock))
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
    -- Stage.RenderChrome stores the compiled border spec; its outline style
    -- follows the rounded or slanted shape like the live frame.
    outlineStyle = function(mock) return mock and mock._msufPreviewOutlineStyle end,
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
local function UpdateRoundedMedia(mock, style)
    if type(PreviewHelpers.ResolveFrameBarMedia) == "function" then
        GF_PREVIEW_ROUNDED_MASK, GF_PREVIEW_ROUNDED_EDGE, GF_PREVIEW_ROUNDED_STRENGTH = PreviewHelpers.ResolveFrameBarMedia(style)
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
    host = host or PreviewHelpers.EnsurePowerBorderHost(mock, "_msufGFPreviewPowerBorder")
    if not host then return end
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
    for i = 1, 4 do host.edges[i]:Hide() end
    host:ClearAllPoints()
    host:SetAllPoints(mock._power)
    local r = mock._msufGFPreviewPowerBorderR
    local g = mock._msufGFPreviewPowerBorderG
    local b = mock._msufGFPreviewPowerBorderB
    local a = mock._msufGFPreviewPowerBorderA
    if r == nil then r, g, b, a = BaseEdgeColor(mock) end
    for i = 1, 4 do host.edges[i]:SetVertexColor(r or 0, g or 0, b or 0, a == nil and 1 or a) end
    PreviewHelpers.LayoutPowerBorderEdges(host, edge, roundedPower)
end
local function ApplyRounded(mock, conf, powerOn, edgeSize, powerEmbed, powerDetached, powerEdgeSize)
    if not mock then return false end
    local style = FrameStyle(conf)
    local enabled = style ~= "SQUARE"
    if enabled then UpdateRoundedMedia(mock, style) end
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
    local roundPower = powerOn and RoundedPowerEnabled(conf)
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
    local gen = EnsureDB().general
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
    local selectedValue2
    if not (healPredMode == 4) then selectedValue2 = healPredMask end
    SetMask(mock, healPredTex, selectedValue2)
    local selectedValue1
    if not (absorbMode == 4) then selectedValue1 = absorbMask end
    SetMask(mock, absorbTex, selectedValue1)
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
    -- The live core Group frame has no second body-color plate beneath the
    -- Health background. Keep the helper plate transparent in missing-only
    -- mode so it cannot bleed through a translucent foreground fill.
    mock._roundedBg:SetColorTexture(conf.bgR or 0.08, conf.bgG or 0.08, conf.bgB or 0.09,
        (gen and gen.barBgFillMode == "missing") and 0 or (conf.bgA or 0.88))
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
Rounded.SetOutlineShown, Rounded.LayoutOutline = SetOutlineShown, LayoutOutline
Rounded.BaseEdgeColor, Rounded.ApplyRounded = BaseEdgeColor, ApplyRounded
Rounded.Round, Rounded.HealPredAnchorMode = Round, HealPredAnchorMode
