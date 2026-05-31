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

local function GFPreviewSetOutlineShown(mock, shown)
    local frame = mock and mock._outlineFrame
    if frame then
        if shown then frame:Show() else frame:Hide() end
    end
    local lines = frame and frame._lines
    if type(lines) ~= "table" then return end
    for i = 1, #GF_PREVIEW_OUTLINE_KEYS do
        local line = lines[GF_PREVIEW_OUTLINE_KEYS[i]]
        if line then
            if shown then line:Show() else line:Hide() end
        end
    end
end

local function GFPreviewEnsureOutlineLine(frame, key)
    if not (frame and frame.CreateTexture) then return nil end
    frame._lines = frame._lines or {}
    local line = frame._lines[key]
    if not line then
        line = frame:CreateTexture(nil, "OVERLAY")
        line:SetTexture(WHITE8X8)
        line:SetVertexColor(0, 0, 0, 1)
        GFPreviewSnapOff(line)
        frame._lines[key] = line
    end
    return line
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

    local top = GFPreviewEnsureOutlineLine(frame, "top")
    local bottom = GFPreviewEnsureOutlineLine(frame, "bottom")
    local left = GFPreviewEnsureOutlineLine(frame, "left")
    local right = GFPreviewEnsureOutlineLine(frame, "right")
    local r, g, b, a = GFPreviewBaseEdgeColor(mock)

    if top then
        top:SetVertexColor(r, g, b, a or 1)
        top:ClearAllPoints()
        top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        top:SetHeight(edge)
    end
    if bottom then
        bottom:SetVertexColor(r, g, b, a or 1)
        bottom:ClearAllPoints()
        bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        bottom:SetHeight(edge)
    end
    if left then
        left:SetVertexColor(r, g, b, a or 1)
        left:ClearAllPoints()
        left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        left:SetWidth(edge)
    end
    if right then
        right:SetVertexColor(r, g, b, a or 1)
        right:ClearAllPoints()
        right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        right:SetWidth(edge)
    end
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

local function GFPreviewEnsureRoundedVisuals(mock)
    if not (mock and mock.CreateTexture) then return false end
    if not mock._roundedBg then
        mock._roundedBg = mock:CreateTexture(nil, "BACKGROUND", nil, -7)
        mock._roundedBg:SetTexture(WHITE8X8)
        GFPreviewSnapOff(mock._roundedBg)
    end
    if not mock._roundedEdge then
        mock._roundedEdge = mock:CreateTexture(nil, "OVERLAY", nil, 6)
        GFPreviewSnapOff(mock._roundedEdge)
    end
    mock._roundedEdge:SetTexture(GF_PREVIEW_ROUNDED_EDGE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    return true
end

local function GFPreviewSetRoundedEdgeStackShown(mock, shown)
    local count = shown and GFPreviewRound(mock and mock._msufGFRoundedPreviewEdgeCount or 1) or 0
    if count < 0 then count = 0 elseif count > 8 then count = 8 end
    if mock and mock._roundedEdge then
        if count >= 1 then mock._roundedEdge:Show() else mock._roundedEdge:Hide() end
    end
    local stack = mock and mock._msufGFRoundedPreviewEdgeStack
    if type(stack) ~= "table" then return end
    for i = 2, #stack do
        local edge = stack[i]
        if edge then
            if i <= count then edge:Show() else edge:Hide() end
        end
    end
end

local function GFPreviewApplyRoundedEdgeStack(mock, edgeSize)
    local count = GFPreviewRound(edgeSize)
    if count < 0 then count = 0 elseif count > 8 then count = 8 end
    mock._msufGFRoundedPreviewEdgeCount = count
    if count <= 0 then
        GFPreviewSetRoundedEdgeStackShown(mock, false)
        return false
    end

    mock._msufGFRoundedPreviewEdgeStack = mock._msufGFRoundedPreviewEdgeStack or {}
    mock._msufGFRoundedPreviewEdgeStack[1] = mock._roundedEdge
    local r, g, b, a = GFPreviewBaseEdgeColor(mock)
    for i = 1, count do
        local edge = (i == 1) and mock._roundedEdge or mock._msufGFRoundedPreviewEdgeStack[i]
        if not edge then
            edge = mock:CreateTexture(nil, "OVERLAY", nil, 6)
            GFPreviewSnapOff(edge)
            mock._msufGFRoundedPreviewEdgeStack[i] = edge
        end
        edge:SetTexture(GF_PREVIEW_ROUNDED_EDGE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        edge:ClearAllPoints()
        edge:SetPoint("TOPLEFT", mock, "TOPLEFT", -i, i)
        edge:SetPoint("BOTTOMRIGHT", mock, "BOTTOMRIGHT", i, -i)
        edge:SetVertexColor(r, g, b, a)
        edge:Show()
    end
    GFPreviewSetRoundedEdgeStackShown(mock, true)
    return true
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
