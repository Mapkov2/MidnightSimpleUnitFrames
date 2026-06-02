--- Menu2 window control buttons.
---
--- Draws the custom minimize/maximize/restore controls used by the slash menu
--- shell and minimized bar. The shell decides what each button does; this file
--- owns only the visual treatment and icon state.
local _, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local T = M.Theme

local function PaintWindowControlButton(btn, hover, down)
    if not btn then return end
    local fill = btn._msuf2ControlFill
    local edge = btn._msuf2ControlEdge
    local alpha = (btn.IsEnabled and not btn:IsEnabled()) and 0.42 or 1
    if fill and fill.SetVertexColor then
        if down then
            fill:SetVertexColor(0.050, 0.070, 0.130, 0.98 * alpha)
        elseif hover then
            fill:SetVertexColor(0.075, 0.095, 0.175, 0.96 * alpha)
        else
            fill:SetVertexColor(0.075, 0.080, 0.125, 0.92 * alpha)
        end
    end
    if edge and edge.SetVertexColor then
        if hover or down then
            edge:SetVertexColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.86 * alpha)
        else
            edge:SetVertexColor(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.70 * alpha)
        end
    end
    local active = hover or down
    local r, g, b = active and T.colors.accent[1] or 0.62, active and T.colors.accent[2] or 0.74, active and T.colors.accent[3] or 0.98
    local lineAlpha = (hover or down) and alpha or (0.88 * alpha)
    if btn._msuf2ControlLines then
        for i = 1, #btn._msuf2ControlLines do
            local line = btn._msuf2ControlLines[i]
            if line.SetVertexColor then
                if line._msuf2ControlShadow then
                    line:SetVertexColor(0.015, 0.020, 0.045, 0.72 * alpha)
                else
                    line:SetVertexColor(r, g, b, (line._msuf2ControlAlpha or lineAlpha))
                end
            end
        end
    end
    if btn._msuf2ControlText then
        btn._msuf2ControlText:SetTextColor(r, g, b, lineAlpha)
    end
    if btn._msuf2ControlTextShadow then
        btn._msuf2ControlTextShadow:SetTextColor(0.015, 0.020, 0.045, 0.72 * alpha)
    end
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

    local function Line(index, w, h, x, y, shadow, customAlpha)
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
        if line.SetRotation then line:SetRotation(0) end
        line._msuf2ControlShadow = shadow and true or nil
        line._msuf2ControlAlpha = customAlpha
        line:Show()
        return line
    end

    if kind == "minimize" then
        if not btn._msuf2ControlText then
            local shadow = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
            shadow:SetText("\226\128\147")
            shadow:SetPoint("CENTER", btn, "CENTER", 1, -3)
            btn._msuf2ControlTextShadow = shadow

            local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
            text:SetText("\226\128\147")
            text:SetPoint("CENTER", btn, "CENTER", 0, -2)
            btn._msuf2ControlText = text
        end
        btn._msuf2ControlTextShadow:Show()
        btn._msuf2ControlText:Show()
    elseif kind == "restore" then
        Line(1, 9, 2, -2, 4)
        Line(2, 2, 8, 3, 0)
        Line(3, 9, 2, 2, 1)
        Line(4, 9, 2, 2, -5)
        Line(5, 2, 8, -3, -2)
        Line(6, 2, 8, 7, -2)
    else
        Line(1, 12, 2, 0, 5)
        Line(2, 12, 2, 0, -5)
        Line(3, 2, 12, -5, 0)
        Line(4, 2, 12, 5, 0)
    end
    PaintWindowControlButton(btn, btn._msuf2ControlHover, btn._msuf2ControlDown)
end

local function CreateWindowControlButton(parent, kind, tooltipTitle, tooltipText)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(24, 24)
    local fill, edge = T.CreateSuperellipseLayers(btn, "_msuf2Control", 2, "BACKGROUND", "BORDER")
    btn._msuf2ControlFill = fill
    btn._msuf2ControlEdge = edge
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
    if frame.maximizeButton and frame.maximizeButton.SetWindowControlIcon then
        frame.maximizeButton:SetWindowControlIcon(frame._msuf2WindowState == "maximized" and "restore" or "maximize")
    end
end

M.CreateWindowControlButton = CreateWindowControlButton
M.RefreshWindowControls = RefreshWindowControls
