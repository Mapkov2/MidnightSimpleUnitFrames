--- EditMode/MSUF_EditMode_Logo.lua - MSUF logo wake intro with one ring draw.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local EM2 = _G.MSUF_EM2
if type(EM2) ~= "table" then return end

local Intro = {}
EM2.LogoIntro = Intro

local MEDIA = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\"
local LOGO_TEXTURE = MEDIA .. "MSUF_EditModeIcon.png"
local W8 = "Interface\\Buttons\\WHITE8X8"

local sin, cos, pi = math.sin, math.cos, math.pi
local min, max = math.min, math.max

local frame, overlay, logoHost, logo, logoGlow, ringHost, headLine, headGlow
local ringSegments = {}
local playing = false
local elapsed = 0

local LOGO_SIZE = 152
local RING_RADIUS = 66
local RING_SEGMENTS = 88
local RING_SEGMENT_W = 6.4
local RING_SEGMENT_H = 2.0
local FADE_IN_DUR = 0.38
local WAKE_START = 0.28
local WAKE_DUR = 0.84
local RING_START = 0.42
local RING_DUR = 1.62
local HOLD_DUR = 0.34
local FADE_OUT_DUR = 0.46
local TOTAL_DUR = RING_START + RING_DUR + HOLD_DUR + FADE_OUT_DUR

local function Clamp01(v)
    return max(0, min(1, v or 0))
end

local function EaseOutCubic(t)
    t = 1 - Clamp01(t)
    return 1 - t * t * t
end

local function EaseInOutSine(t)
    return 0.5 - 0.5 * cos(Clamp01(t) * pi)
end

local function Pulse(startTime, duration)
    local t = Clamp01((elapsed - startTime) / duration)
    if t <= 0 or t >= 1 then return 0 end
    return sin(t * pi)
end

local function HideNow()
    playing = false
    elapsed = 0
    if frame then
        frame:SetScript("OnUpdate", nil)
        frame:SetAlpha(0)
        frame:Hide()
    end
end

local function SetSegmentAlpha(index, alpha)
    local tex = ringSegments[index]
    if tex then tex:SetAlpha(alpha or 0) end
end

local function ResetVisuals()
    if not frame then return end
    elapsed = 0
    frame:SetAlpha(1)
    overlay:SetAlpha(0)
    logoHost:SetAlpha(0)
    logoHost:SetScale(0.992)
    if logo then
        logo:SetAlpha(1)
        logo:SetVertexColor(1, 1, 1, 1)
    end
    if logoGlow then
        logoGlow:SetAlpha(0)
        logoGlow:SetScale(1)
    end
    for i = 1, #ringSegments do
        SetSegmentAlpha(i, 0)
    end
    if headLine then headLine:SetAlpha(0) end
    if headGlow then headGlow:SetAlpha(0) end
end

local function EnsureIntroFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "MSUF_EM2_LogoIntro", UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(860)
    frame:SetAllPoints(UIParent)
    frame:EnableMouse(false)
    frame:SetAlpha(0)
    frame:Hide()

    overlay = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    overlay:SetTexture(W8)
    overlay:SetAllPoints(UIParent)
    overlay:SetColorTexture(0.00, 0.00, 0.00, 0.07)
    overlay:SetAlpha(0)

    logoHost = CreateFrame("Frame", nil, frame)
    logoHost:SetSize(LOGO_SIZE, LOGO_SIZE)
    logoHost:SetPoint("CENTER", UIParent, "CENTER", 0, 18)
    logoHost:EnableMouse(false)
    logoHost:SetAlpha(0)
    logoHost:SetScale(1)

    logo = logoHost:CreateTexture(nil, "ARTWORK", nil, 0)
    logo:SetTexture(LOGO_TEXTURE)
    logo:SetAllPoints(logoHost)
    logo:SetAlpha(1)
    if logo.SetSnapToPixelGrid then
        logo:SetSnapToPixelGrid(false)
        logo:SetTexelSnappingBias(0)
    end

    logoGlow = logoHost:CreateTexture(nil, "ARTWORK", nil, 1)
    logoGlow:SetTexture(LOGO_TEXTURE)
    logoGlow:SetAllPoints(logoHost)
    logoGlow:SetBlendMode("ADD")
    logoGlow:SetVertexColor(0.22, 0.78, 1.00, 1)
    logoGlow:SetAlpha(0)
    if logoGlow.SetSnapToPixelGrid then
        logoGlow:SetSnapToPixelGrid(false)
        logoGlow:SetTexelSnappingBias(0)
    end

    ringHost = CreateFrame("Frame", nil, logoHost)
    ringHost:SetAllPoints(logoHost)
    ringHost:EnableMouse(false)

    for i = 1, RING_SEGMENTS do
        local tex = ringHost:CreateTexture(nil, "OVERLAY", nil, 1)
        tex:SetTexture(W8)
        tex:SetSize(RING_SEGMENT_W, RING_SEGMENT_H)
        tex:SetColorTexture(0.44, 0.86, 1.00, 1)
        tex:SetBlendMode("ADD")
        tex:SetAlpha(0)

        local progress = (i - 1) / RING_SEGMENTS
        local angle = (pi * 0.5) - progress * pi * 2
        local x = cos(angle) * RING_RADIUS
        local y = sin(angle) * RING_RADIUS
        tex:SetPoint("CENTER", logoHost, "CENTER", x, y)
        if tex.SetRotation then
            tex:SetRotation(angle - pi * 0.5)
        end
        if tex.SetSnapToPixelGrid then
            tex:SetSnapToPixelGrid(false)
            tex:SetTexelSnappingBias(0)
        end
        ringSegments[i] = tex
    end

    headGlow = ringHost:CreateTexture(nil, "OVERLAY", nil, 2)
    headGlow:SetTexture(W8)
    headGlow:SetSize(16, 5)
    headGlow:SetColorTexture(0.28, 0.76, 1.00, 1)
    headGlow:SetBlendMode("ADD")
    headGlow:SetAlpha(0)

    headLine = ringHost:CreateTexture(nil, "OVERLAY", nil, 3)
    headLine:SetTexture(W8)
    headLine:SetSize(11, 3)
    headLine:SetColorTexture(0.90, 0.98, 1.00, 1)
    headLine:SetBlendMode("ADD")
    headLine:SetAlpha(0)

    return frame
end

local function PlaceRingHead(progress, fade)
    progress = Clamp01(progress)
    local angle = (pi * 0.5) - progress * pi * 2
    local x = cos(angle) * RING_RADIUS
    local y = sin(angle) * RING_RADIUS

    headGlow:ClearAllPoints()
    headGlow:SetPoint("CENTER", logoHost, "CENTER", x, y)
    headLine:ClearAllPoints()
    headLine:SetPoint("CENTER", logoHost, "CENTER", x, y)
    if headGlow.SetRotation then headGlow:SetRotation(angle - pi * 0.5) end
    if headLine.SetRotation then headLine:SetRotation(angle - pi * 0.5) end
    headGlow:SetAlpha(0.42 * fade)
    headLine:SetAlpha(0.86 * fade)
end

local function UpdateRing(progress, fade)
    progress = Clamp01(progress)
    if progress <= 0 then
        for i = 1, RING_SEGMENTS do
            SetSegmentAlpha(i, 0)
        end
        headGlow:SetAlpha(0)
        headLine:SetAlpha(0)
        return
    end

    local eased = EaseInOutSine(progress)
    local head = eased * RING_SEGMENTS
    local closed = progress >= 1
    local closeT = Clamp01((elapsed - (RING_START + RING_DUR)) / HOLD_DUR)
    local finishPulse = sin(closeT * pi)

    for i = 1, RING_SEGMENTS do
        local idx = i - 1
        local alpha = 0
        if closed then
            alpha = 0.34 + 0.14 * finishPulse
        elseif idx <= head then
            local distance = head - idx
            alpha = 0.18
            if distance <= 9 then
                alpha = alpha + (1 - distance / 9) * 0.58
            elseif distance <= 18 then
                alpha = alpha + (1 - (distance - 9) / 9) * 0.12
            end
        end
        SetSegmentAlpha(i, alpha * fade)
    end

    if progress > 0 and progress < 1 then
        PlaceRingHead(eased, fade)
    else
        headGlow:SetAlpha(0)
        headLine:SetAlpha(0)
    end
end

local function OnUpdate(self, dt)
    elapsed = elapsed + (dt or 0)

    local fadeIn = EaseOutCubic(elapsed / FADE_IN_DUR)
    local fadeOut = 1
    local fadeOutStart = TOTAL_DUR - FADE_OUT_DUR
    if elapsed >= fadeOutStart then
        fadeOut = 1 - Clamp01((elapsed - fadeOutStart) / FADE_OUT_DUR)
    end

    local alpha = fadeIn * fadeOut
    self:SetAlpha(alpha)
    overlay:SetAlpha(alpha)
    logoHost:SetAlpha(alpha)
    logoHost:SetScale(0.990 + 0.010 * fadeIn)

    local wake = Pulse(WAKE_START, WAKE_DUR)
    if logoGlow then
        logoGlow:SetAlpha(0.34 * wake * alpha)
        logoGlow:SetScale(1.000 + 0.018 * wake)
    end
    if logo then
        local base = 0.82 + 0.18 * fadeIn
        local boost = 0.08 * wake
        local c = min(1, base + boost)
        logo:SetVertexColor(c, c, 1, 1)
    end

    local ringProgress = Clamp01((elapsed - RING_START) / RING_DUR)
    UpdateRing(ringProgress, alpha)

    if elapsed >= TOTAL_DUR then
        HideNow()
    end
end

function Intro.Stop()
    HideNow()
end

function Intro.Play()
    if InCombatLockdown and InCombatLockdown() then return false end
    EnsureIntroFrame()
    ResetVisuals()
    playing = true
    frame:Show()
    frame:SetScript("OnUpdate", OnUpdate)
    return true
end

ExportPublic("MSUF_PlayEditModeLogoIntro", function()
    return Intro.Play()
end)

ExportPublic("MSUF_StopEditModeLogoIntro", function()
    return Intro.Stop()
end)
