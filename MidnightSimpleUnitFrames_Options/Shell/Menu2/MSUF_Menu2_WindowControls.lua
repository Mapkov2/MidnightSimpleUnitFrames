--- Menu2 window control buttons.
---
--- The main shell uses one authored segmented-control texture and a separate
--- four-cell glyph atlas. Runtime work is limited to swapping atlas coordinates
--- on direct hover/state changes; there are no timers or animation drivers.
local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local T = M.Theme
local max = math.max
local min = math.min
local CONTROL_HEIGHT = 24
local SEGMENT_WIDTH = 30
-- Window chrome only needs to sit above its own shell/header. Keeping this
-- relative offset below the normal popup level prevents the cached main-menu
-- controls from punching through modal Menu2 surfaces such as the color picker.
local WINDOW_CONTROL_LEVEL_OFFSET = 16
local GROUP_ATLAS_RIGHT = 0.75 -- authored control occupies 96px of a 128px atlas
local GROUP_ATLAS_ROWS = {
    [1] = { 0.25, 0.50 }, -- minimize hover
    [2] = { 0.50, 0.75 }, -- maximize/restore hover
    [3] = { 0.75, 1.00 }, -- close hover
}
local ICON_ATLAS_CELLS = {
    minimize = { 0.00, 0.25 },
    maximize = { 0.25, 0.50 },
    restore = { 0.50, 0.75 },
    close = { 0.75, 1.00 },
}

local function ColorOr(name, fallback)
    return (T and T.colors and T.colors[name]) or fallback
end

local function MenuAccentActive()
    return T and type(T.MenuAccentActive) == "function" and T.MenuAccentActive()
end

local function TintAtlasTexture(texture, color, enabled)
    if not texture then return end
    if texture.SetDesaturated then texture:SetDesaturated(enabled and true or false) end
    if not texture.SetVertexColor then return end
    if not enabled then
        texture:SetVertexColor(1, 1, 1, 1)
        return
    end
    color = color or { 1, 1, 1, 1 }
    local peak = max(color[1] or 0, color[2] or 0, color[3] or 0)
    if peak <= 0.001 then peak = 1 end
    texture:SetVertexColor((color[1] or 0) / peak, (color[2] or 0) / peak,
        (color[3] or 0) / peak, 1)
end

local function PrepareAtlasTexture(texture, path)
    texture:SetTexture(path)
    if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
    if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
end

local function SetIconAtlasCell(texture, kind)
    local cell = ICON_ATLAS_CELLS[kind] or ICON_ATLAS_CELLS.maximize
    texture:SetTexCoord(cell[1], cell[2], 0, 1)
end

local function PaintGroupHover(btn, hover, down)
    local group = btn and btn._msuf2ControlGroup
    local overlay = group and group._msuf2ControlGroupHover
    if not overlay then return end
    if not (hover or down) then
        if group._msuf2ControlHoverOwner == btn then
            group._msuf2ControlHoverOwner = nil
            overlay:Hide()
        end
        return
    end
    local row = GROUP_ATLAS_ROWS[btn._msuf2ControlSegmentIndex or 1]
    group._msuf2ControlHoverOwner = btn
    overlay:SetTexCoord(0, GROUP_ATLAS_RIGHT, row[1], row[2])
    local useAccent = MenuAccentActive() and btn._msuf2ControlKind ~= "close"
    local accent = down
        and ColorOr("coreHot", ColorOr("coreGlow", { 0.357, 0.608, 1.000, 1 }))
        or ColorOr("coreGlow", { 0.231, 0.510, 0.965, 1 })
    TintAtlasTexture(overlay, accent, useAccent)
    overlay:SetAlpha(down and 0.78 or 1)
    overlay:Show()
end

local function PaintStandaloneSurface(btn, hover, down, close, alpha)
    local fill = btn._msuf2ControlFill
    local edge = btn._msuf2ControlEdge
    local shadow = ColorOr("coreShadow", { 0.006, 0.016, 0.032, 1 })
    local surface = ColorOr("coreSurface", { 0.014, 0.038, 0.072, 1 })
    local raised = ColorOr("coreRaised", { 0.026, 0.070, 0.110, 1 })
    local glow = ColorOr("coreGlow", { 0.090, 0.360, 0.540, 1 })
    local danger = ColorOr("danger", { 0.880, 0.280, 0.280, 1 })
    local accentActive = MenuAccentActive()
    local base
    if close and not accentActive and down then
        base = { 0.160, 0.036, 0.052, 0.62 * alpha }
    elseif close and not accentActive and hover then
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
        else
            fill:SetVertexColor(base[1], base[2], base[3], base[4] or 1)
        end
    end
    if edge then
        if close and not accentActive and (hover or down) then
            edge:SetVertexColor(danger[1], danger[2], danger[3], (down and 0.58 or 0.44) * alpha)
        elseif hover or down then
            edge:SetVertexColor(glow[1], glow[2], glow[3], (down and 0.44 or 0.34) * alpha)
        else
            local rim = ColorOr("borderSoft", { 0.043, 0.096, 0.150, 0.36 })
            edge:SetVertexColor(rim[1], rim[2], rim[3], 0.28 * alpha)
        end
    end
end

local function PaintWindowControlButton(btn, hover, down)
    if not btn then return end
    local alpha = (btn.IsEnabled and not btn:IsEnabled()) and 0.42 or 1
    local close = btn._msuf2ControlKind == "close"
    if btn._msuf2ControlGroup then
        PaintGroupHover(btn, hover, down)
    else
        PaintStandaloneSurface(btn, hover, down, close, alpha)
    end

    local active = hover or down
    local r, g, b
    if MenuAccentActive() and not close then
        -- The monochrome glyph atlas lets minimize/maximize follow the accent.
        -- Close remains on the danger semantic, just like the Midnight path.
        local accent = active
            and ColorOr("coreHot", ColorOr("coreGlow", { 0.357, 0.608, 1.000, 1 }))
            or ColorOr("coreGlow", { 0.231, 0.510, 0.965, 1 })
        r, g, b = accent[1], accent[2], accent[3]
    elseif close then
        r, g, b = active and 1.00 or 0.90, active and 0.74 or 0.62, active and 0.80 or 0.68
    else
        local glow = ColorOr("coreHot", ColorOr("coreGlow", { 0.357, 0.608, 1.000, 1 }))
        r = active and min(glow[1] * 1.20, 1) or 0.84
        g = active and min(glow[2] * 1.12, 1) or 0.89
        b = active and glow[3] or 1.00
    end
    if btn._msuf2ControlIcon then btn._msuf2ControlIcon:SetVertexColor(r, g, b, active and alpha or 0.92 * alpha) end
    if btn._msuf2ControlIconShadow then btn._msuf2ControlIconShadow:SetVertexColor(0.002, 0.008, 0.018, 0.82 * alpha) end
end

local function SetWindowControlIcon(btn, kind)
    if not btn then return end
    btn._msuf2ControlKind = kind
    if not btn._msuf2ControlIcon then
        local path = T and T.media and T.media.windowControlIcons
        local shadow = btn:CreateTexture(nil, "ARTWORK", nil, 0)
        shadow:SetSize(12, 12)
        shadow:SetPoint("CENTER", btn, "CENTER", 0.75, -0.75)
        PrepareAtlasTexture(shadow, path)
        btn._msuf2ControlIconShadow = shadow
        local icon = btn:CreateTexture(nil, "ARTWORK", nil, 1)
        icon:SetSize(12, 12)
        icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
        PrepareAtlasTexture(icon, path)
        btn._msuf2ControlIcon = icon
    end
    SetIconAtlasCell(btn._msuf2ControlIconShadow, kind)
    SetIconAtlasCell(btn._msuf2ControlIcon, kind)
    PaintWindowControlButton(btn, btn._msuf2ControlHover, btn._msuf2ControlDown)
end

local function CreateWindowControlGroup(parent, segmentCount)
    segmentCount = max(1, tonumber(segmentCount) or 3)
    local group = CreateFrame("Frame", nil, parent)
    group:SetSize(SEGMENT_WIDTH * segmentCount, CONTROL_HEIGHT)
    group._msuf2WindowControlGroup = true
    group._msuf2ControlSegmentCount = segmentCount
    local base = group:CreateTexture(nil, "BACKGROUND", nil, 0)
    base:SetPoint("TOPLEFT", group, "TOPLEFT", -3, -1)
    base:SetPoint("BOTTOMRIGHT", group, "BOTTOMRIGHT", 3, 1)
    PrepareAtlasTexture(base, T.media.windowControls)
    base:SetTexCoord(0, GROUP_ATLAS_RIGHT, 0, 0.25)
    local tintSurfaces = T and type(T.MenuAccentSurfacesTinted) == "function"
        and T.MenuAccentSurfacesTinted()
    TintAtlasTexture(base, ColorOr("coreSurface", { 0.035, 0.067, 0.114, 1 }), tintSurfaces)
    group._msuf2ControlGroupBase = base
    local hover = group:CreateTexture(nil, "BORDER", nil, 1)
    hover:SetPoint("TOPLEFT", group, "TOPLEFT", -3, -1)
    hover:SetPoint("BOTTOMRIGHT", group, "BOTTOMRIGHT", 3, 1)
    PrepareAtlasTexture(hover, T.media.windowControls)
    hover:Hide()
    group._msuf2ControlGroupHover = hover
    return group
end

local function CreateWindowControlButton(parent, kind, tooltipTitle, tooltipText, segmentIndex)
    local btn = CreateFrame("Button", nil, parent)
    local grouped = parent and parent._msuf2WindowControlGroup
    btn:SetSize(grouped and SEGMENT_WIDTH or CONTROL_HEIGHT, CONTROL_HEIGHT)
    if btn.RegisterForClicks then btn:RegisterForClicks("AnyUp") end
    if grouped then
        local count = parent._msuf2ControlSegmentCount or 3
        btn._msuf2ControlGroup = parent
        btn._msuf2ControlSegmentIndex = min(count, max(1, tonumber(segmentIndex) or 1))
    else
        local fill, edge = T.CreateSuperellipseLayers(btn, "_msuf2Control", 2, "BACKGROUND", "BORDER")
        btn._msuf2ControlFill = fill
        btn._msuf2ControlEdge = edge
    end
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
    SetWindowControlIcon(btn, kind)
    return btn
end

local function RefreshWindowControls(frame)
    frame = frame or M.frame
    if not frame then return end
    local baseLevel = (frame.GetFrameLevel and frame:GetFrameLevel()) or 0
    local controlLevel = baseLevel + WINDOW_CONTROL_LEVEL_OFFSET
    if frame.windowControls and frame.windowControls.SetFrameLevel then frame.windowControls:SetFrameLevel(controlLevel) end
    local buttonLevel = frame.windowControls and (controlLevel + 1) or controlLevel
    if frame.closeButton and frame.closeButton.SetFrameLevel then frame.closeButton:SetFrameLevel(buttonLevel) end
    if frame.maximizeButton and frame.maximizeButton.SetFrameLevel then frame.maximizeButton:SetFrameLevel(buttonLevel) end
    if frame.minimizeButton and frame.minimizeButton.SetFrameLevel then frame.minimizeButton:SetFrameLevel(buttonLevel) end
    if frame.maximizeButton and frame.maximizeButton.SetWindowControlIcon then
        frame.maximizeButton:SetWindowControlIcon(frame._msuf2WindowState == "maximized" and "restore" or "maximize")
    end
end

M.CreateWindowControlButton = CreateWindowControlButton
M.CreateWindowControlGroup = CreateWindowControlGroup
M.RefreshWindowControls = RefreshWindowControls
