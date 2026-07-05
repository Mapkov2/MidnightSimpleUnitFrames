--- Menu2 window control buttons.
---
--- Draws the custom minimize/maximize/restore controls used by the slash menu
--- shell and minimized bar. The shell decides what each button does; this file
--- owns only the visual treatment and icon state.
local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local T = M.Theme
local max = math.max
local min = math.min
local pi = math.pi
local function ColorOr(name, fallback)
    return (T and T.colors and T.colors[name]) or fallback
end
local function SetGlyphColor(line, r, g, b, a)
    if line and line.SetVertexColor then line:SetVertexColor(r, g, b, a or 1) end
end
local function PaintWindowControlButton(btn, hover, down)
    if not btn then return end
    local fill = btn._msuf2ControlFill
    local edge = btn._msuf2ControlEdge
    local lip = btn._msuf2ControlLip
    local shade = btn._msuf2ControlShade
    local alpha = (btn.IsEnabled and not btn:IsEnabled()) and 0.42 or 1
    local kind = btn._msuf2ControlKind
    local shadow = ColorOr("coreShadow", { 0.006, 0.016, 0.032, 1 })
    local surface = ColorOr("coreSurface", { 0.014, 0.038, 0.072, 1 })
    local raised = ColorOr("coreRaised", { 0.026, 0.070, 0.110, 1 })
    local glow = ColorOr("coreGlow", ColorOr("accent", { 0.090, 0.360, 0.540, 1 }))
    local danger = ColorOr("danger", { 0.880, 0.280, 0.280, 1 })
    local close = kind == "close"
    local base
    if close and down then
        base = { 0.160, 0.036, 0.052, 0.62 * alpha }
    elseif close and hover then
        base = { 0.120, 0.028, 0.044, 0.54 * alpha }
    elseif down then
        base = { shadow[1], shadow[2], shadow[3], 0.62 * alpha }
    elseif hover then
        base = { raised[1], raised[2], raised[3], 0.54 * alpha }
    else
        base = { surface[1], surface[2], surface[3], 0.38 * alpha }
    end
    if fill then
        if T.SetFillGradient then
            T.SetFillGradient(fill, base, hover and 0.16 or 0.08, down and -0.28 or -0.20)
        elseif fill.SetVertexColor then
            fill:SetVertexColor(base[1], base[2], base[3], base[4] or 1)
        end
    end
    if edge and edge.SetVertexColor then
        if close and (hover or down) then
            edge:SetVertexColor(danger[1], danger[2], danger[3], (down and 0.58 or 0.44) * alpha)
        elseif hover or down then
            edge:SetVertexColor(glow[1], glow[2], glow[3], (down and 0.44 or 0.34) * alpha)
        else
            local rim = ColorOr("borderSoft", { 0.043, 0.096, 0.150, 0.36 })
            edge:SetVertexColor(rim[1], rim[2], rim[3], 0.28 * alpha)
        end
    end
    if lip and lip.SetVertexColor then
        lip:SetVertexColor(glow[1], glow[2], glow[3], (hover and 0.070 or 0.025) * alpha)
    end
    if shade and shade.SetVertexColor then
        shade:SetVertexColor(0, 0, 0, (down and 0.12 or 0.060) * alpha)
    end
    local active = hover or down
    local r, g, b
    if close then
        r, g, b = active and 1.00 or 0.92, active and 0.66 or 0.74, active and 0.70 or 0.82
    else
        r, g, b = active and min(glow[1] * 1.35, 1) or 0.56, active and min(glow[2] * 1.26, 1) or 0.68, active and min(glow[3] * 1.18, 1) or 0.86
    end
    local lineAlpha = (hover or down) and alpha or (0.78 * alpha)
    if btn._msuf2ControlLines then
        for i = 1, #btn._msuf2ControlLines do
            local line = btn._msuf2ControlLines[i]
            if line._msuf2ControlShadow then
                SetGlyphColor(line, 0.002, 0.006, 0.014, 0.72 * alpha)
            else
                SetGlyphColor(line, r, g, b, (line._msuf2ControlAlpha or lineAlpha))
            end
        end
    end
    if btn._msuf2ControlText then btn._msuf2ControlText:SetTextColor(r, g, b, lineAlpha) end
    if btn._msuf2ControlTextShadow then btn._msuf2ControlTextShadow:SetTextColor(0.015, 0.020, 0.045, 0.72 * alpha) end
end
local function SetWindowControlIcon(btn, kind)
    if not btn then return end
    btn._msuf2ControlKind = kind
    btn._msuf2ControlLines = btn._msuf2ControlLines or {}
    for i = 1, #btn._msuf2ControlLines do
        btn._msuf2ControlLines[i]:Hide()
    end
    if btn._msuf2ControlText then btn._msuf2ControlText:Hide() end
    if btn._msuf2ControlTextShadow then btn._msuf2ControlTextShadow:Hide() end
    local function Line(index, w, h, x, y, shadow, customAlpha, rotation)
        local line = btn._msuf2ControlLines[index]
        if not line then
            line = btn:CreateTexture(nil, "ARTWORK")
            line:SetTexture("Interface\\Buttons\\WHITE8X8")
            if line.SetSnapToPixelGrid then line:SetSnapToPixelGrid(true) end
            if line.SetTexelSnappingBias then line:SetTexelSnappingBias(0) end
            btn._msuf2ControlLines[index] = line
        end
        line:ClearAllPoints()
        line:SetSize(w, h)
        line:SetPoint("CENTER", btn, "CENTER", x, y)
        if line.SetRotation then line:SetRotation(rotation or 0) end
        line._msuf2ControlShadow = shadow and true or nil
        line._msuf2ControlAlpha = customAlpha
        line:Show()
        return line
    end
    if kind == "minimize" then
        Line(1, 11, 2, 1, -1, true)
        Line(2, 11, 2, 0, 0)
    elseif kind == "close" then
        Line(1, 12, 2, 1, 0, true, nil, pi * 0.25)
        Line(2, 12, 2, 1, 0, true, nil, -pi * 0.25)
        Line(3, 12, 2, 0, 0, false, nil, pi * 0.25)
        Line(4, 12, 2, 0, 0, false, nil, -pi * 0.25)
    elseif kind == "restore" then
        Line(1, 8, 2, -1, 4, true)
        Line(2, 2, 7, 4, 1, true)
        Line(3, 8, 2, -2, 3)
        Line(4, 2, 7, 3, 0)
        Line(5, 9, 2, 1, 0)
        Line(6, 9, 2, 1, -5)
        Line(7, 2, 8, -4, -2)
        Line(8, 2, 8, 6, -2)
    else
        Line(1, 12, 2, 1, 5, true)
        Line(2, 12, 2, 1, -5, true)
        Line(3, 2, 12, -4, 0, true)
        Line(4, 2, 12, 6, 0, true)
        Line(5, 12, 2, 0, 5)
        Line(6, 12, 2, 0, -5)
        Line(7, 2, 12, -5, 0)
        Line(8, 2, 12, 5, 0)
    end
    PaintWindowControlButton(btn, btn._msuf2ControlHover, btn._msuf2ControlDown)
end
local function CreateWindowControlButton(parent, kind, tooltipTitle, tooltipText)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(24, 24)
    if btn.RegisterForClicks then btn:RegisterForClicks("AnyUp") end
    local fill, edge = T.CreateSuperellipseLayers(btn, "_msuf2Control", 2, "BACKGROUND", "BORDER")
    btn._msuf2ControlFill = fill
    btn._msuf2ControlEdge = edge
    local lip = btn:CreateTexture(nil, "ARTWORK", nil, 0)
    lip:SetPoint("TOPLEFT", btn, "TOPLEFT", 6, -5)
    lip:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -6, -5)
    lip:SetHeight(1)
    lip:SetTexture("Interface\\Buttons\\WHITE8X8")
    if lip.SetBlendMode then lip:SetBlendMode("ADD") end
    btn._msuf2ControlLip = lip
    local shade = btn:CreateTexture(nil, "BORDER", nil, 1)
    shade:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 6, 4)
    shade:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -6, 4)
    shade:SetHeight(2)
    shade:SetTexture("Interface\\Buttons\\WHITE8X8")
    btn._msuf2ControlShade = shade
    btn.SetWindowControlIcon = SetWindowControlIcon
    btn:SetScript("OnEnter", function(self)
        self._msuf2ControlHover = true
        PaintWindowControlButton(self, true, self._msuf2ControlDown)
    end)
    btn:SetScript("OnLeave", function(self)
        self._msuf2ControlHover = nil
        self._msuf2ControlDown = nil
        PaintWindowControlButton(self, false, false)
    end)
    btn:SetScript("OnMouseDown", function(self)
        self._msuf2ControlDown = true
        PaintWindowControlButton(self, self._msuf2ControlHover, true)
    end)
    btn:SetScript("OnMouseUp", function(self)
        self._msuf2ControlDown = nil
        PaintWindowControlButton(self, self._msuf2ControlHover, false)
    end)
    btn:SetScript("OnEnable", function(self)
        PaintWindowControlButton(self, self._msuf2ControlHover, self._msuf2ControlDown)
    end)
    btn:SetScript("OnDisable", function(self)
        PaintWindowControlButton(self, false, false)
    end)
    if M.AttachHistoryTooltip then M.AttachHistoryTooltip(btn, tooltipTitle, tooltipText) end
    SetWindowControlIcon(btn, kind)
    return btn
end
local function RefreshWindowControls(frame)
    frame = frame or M.frame
    if not frame then return end
    local baseLevel = (frame.GetFrameLevel and frame:GetFrameLevel()) or 0
    local controlLevel = baseLevel + 140
    if frame.closeButton and frame.closeButton.SetFrameLevel then frame.closeButton:SetFrameLevel(controlLevel) end
    if frame.maximizeButton and frame.maximizeButton.SetFrameLevel then frame.maximizeButton:SetFrameLevel(controlLevel) end
    if frame.minimizeButton and frame.minimizeButton.SetFrameLevel then frame.minimizeButton:SetFrameLevel(controlLevel) end
    if frame.maximizeButton and frame.maximizeButton.SetWindowControlIcon then frame.maximizeButton:SetWindowControlIcon(frame._msuf2WindowState == "maximized" and "restore" or "maximize") end
end
M.CreateWindowControlButton = CreateWindowControlButton
M.RefreshWindowControls = RefreshWindowControls
