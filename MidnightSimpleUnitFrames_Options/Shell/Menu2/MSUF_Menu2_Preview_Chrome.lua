local _, MSUF = ...
local M = MSUF.MSUF2
local H = M.PreviewHelpers
local FILE = "Shell/Menu2/MSUF_Menu2_Preview_Chrome.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
local Fallbacks, min = M.Fallbacks, math.min
local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local shared = H._Shared
local FlatBackdrop, ThemedFont = shared.FlatBackdrop, shared.ThemedFont
local CreatePreviewPopup, PopupButton = shared.CreatePreviewPopup, shared.PopupButton
local RegisterPopupDismiss, SetShownText = shared.RegisterPopupDismiss, shared.SetShownText

-- The idle / hover / active fills and borders of the preview pill buttons, from the
-- theme's core colors; the zoom bar buttons use the active pair for their pressed state.
local function PillPalette(T)
    local tc = T and T.colors
    local shadow = tc and tc.coreShadow or { 0.006, 0.016, 0.032 }
    local surface = tc and tc.coreSurface or { 0.014, 0.038, 0.072 }
    local raised = tc and tc.coreRaised or { 0.026, 0.070, 0.110 }
    local rim = tc and tc.coreRim or { 0.043, 0.096, 0.150 }
    local blue = tc and tc.coreBlue or { 0.095, 0.360, 0.560 }
    return { shadow[1], shadow[2], shadow[3], 0.92 }, { surface[1], surface[2], surface[3], 0.98 },
        { raised[1], raised[2], raised[3], 0.98 },
        { rim[1], rim[2], rim[3], 0.72 }, { blue[1], blue[2], blue[3], 0.58 }, { blue[1], blue[2], blue[3], 0.70 }
end
-- Paints a pill's superellipse layers: the fill (a gradient when the theme has one) and the
-- edge, brightened on hover; alpha is the enabled-state multiplier and scratch is reused.
local function PaintPillLayers(T, fill, edge, bg, br, alpha, hover, scratch)
    if fill then
        if T.SetFillGradient then
            scratch[1], scratch[2], scratch[3], scratch[4] = bg[1], bg[2], bg[3], (bg[4] or 1) * alpha
            T.SetFillGradient(fill, scratch, 0.12, -0.18)
        else
            fill:SetVertexColor(bg[1], bg[2], bg[3], (bg[4] or 1) * alpha)
        end
    end
    if edge then
        local boost = hover and 1.08 or 1
        edge:SetVertexColor(min(br[1] * boost, 1), min(br[2] * boost, 1), min(br[3] * boost, 1), (br[4] or 1) * alpha)
    end
end
function H.StylePreviewPillButton(btn, T, opts)
    if not btn then return btn end
    opts = opts or {}
    if btn.SetHitRectInsets then btn:SetHitRectInsets(-2, -2, -2, -2) end
    local fontField = opts.fontField or "fs"
    local useSuperellipse = T and T.CreateSuperellipseLayers
    if useSuperellipse and not btn._msuf2PreviewPillFill then
        local fill, edge = T.CreateSuperellipseLayers(btn, "_msuf2PreviewPill", 2, "BACKGROUND", "BORDER")
        btn._msuf2PreviewPillFill = fill
        btn._msuf2PreviewPillEdge = edge
        if btn.SetBackdropColor then btn:SetBackdropColor(0, 0, 0, 0) end
        if btn.SetBackdropBorderColor then btn:SetBackdropBorderColor(0, 0, 0, 0) end
    end
    local bgIdle, bgHover, bgActive, brIdle, brHover, brActive = PillPalette(T)
    local bgDown = { bgActive[1], bgActive[2], bgActive[3], 1.00 }
    local bgScratch = { 0, 0, 0, 1 }
    function btn:MSUF2RefreshPreviewPill(active, hover, down)
        active = active == true
        if hover == nil then hover = self._msuf2PreviewPillHover == true end
        if down == nil then down = self._msuf2PreviewPillDown == true end
        self._msuf2PreviewPillActive = active
        local alpha = (self.IsEnabled and not self:IsEnabled()) and 0.42 or 1
        local bg = down and bgDown or (active and bgActive or (hover and bgHover or bgIdle))
        local br = active and brActive or (hover and brHover or brIdle)
        if useSuperellipse and self._msuf2PreviewPillFill then
            PaintPillLayers(T, self._msuf2PreviewPillFill, self._msuf2PreviewPillEdge, bg, br, alpha, hover, bgScratch)
        elseif self.SetBackdropColor then
            self:SetBackdropColor(bg[1], bg[2], bg[3], (bg[4] or 1) * alpha)
            self:SetBackdropBorderColor(br[1], br[2], br[3], (br[4] or 1) * alpha)
        end
        if self[fontField] and self[fontField].SetTextColor then
            self[fontField]:SetTextColor(active and 0.06 or (hover and 0.88 or 0.78), active and 0.95 or (hover and 0.94 or 0.84), active
                and 1.00 or 0.96, alpha)
        end
    end
    btn:SetScript("OnEnter", function(self)
        self._msuf2PreviewPillHover = true
        self:MSUF2RefreshPreviewPill(self._msuf2PreviewPillActive, true, self._msuf2PreviewPillDown)
    end)
    btn:SetScript("OnLeave", function(self)
        self._msuf2PreviewPillHover = nil
        self._msuf2PreviewPillDown = nil
        self:MSUF2RefreshPreviewPill(self._msuf2PreviewPillActive, false, false)
    end)
    btn:SetScript("OnMouseDown", function(self)
        self._msuf2PreviewPillDown = true
        self:MSUF2RefreshPreviewPill(self._msuf2PreviewPillActive, self._msuf2PreviewPillHover, true)
    end)
    btn:SetScript("OnMouseUp", function(self)
        self._msuf2PreviewPillDown = nil
        self:MSUF2RefreshPreviewPill(self._msuf2PreviewPillActive, self._msuf2PreviewPillHover, false)
    end)
    btn:SetScript("OnEnable", function(self) self:MSUF2RefreshPreviewPill(self._msuf2PreviewPillActive) end)
    btn:SetScript("OnDisable", function(self) self:MSUF2RefreshPreviewPill(false, false, false) end)
    btn:MSUF2RefreshPreviewPill(false, false, false)
    return btn
end
function H.ShowPreviewHandleContext(handle, opts)
    opts = opts or {}
    if not handle then return end
    local M2 = opts.M or M
    local T = opts.T or (M2.Theme)
    local W = opts.W or (M2.Widgets)
    local tr = opts.Tr or opts.TR or (M2.Tr) or Fallbacks.Identity
    local openSettings = opts.openSettings
    if type(openSettings) ~= "function" then return end
    local popup = H._previewHandleContextPopup
    if not popup then
        popup = CreatePreviewPopup(M2, "MSUF2PreviewHandleContextMenu", 176, 76)
        local title = ThemedFont(popup, T, "GameFontDisableSmall", "muted", { 0.72, 0.78, 0.90, 1 })
        title:SetPoint("TOPLEFT", popup, "TOPLEFT", 12, -8)
        title:SetPoint("RIGHT", popup, "RIGHT", -12, 0)
        title:SetJustifyH("LEFT")
        popup._title = title
        local function MakeButton(label, y)
            local btn = PopupButton(W, T, popup, tr, label, 152)
            btn:SetPoint("TOPLEFT", popup, "TOPLEFT", 12, y)
            return btn
        end
        popup._open = MakeButton("Open Settings", -28)
        popup._keep = MakeButton("Keep Selected", -52)
        popup._keep:SetScript("OnClick", function(self)
            local p = self:GetParent()
            if p then p:Hide() end
        end)
        do
            M2.RegisterMenuChromeControl(popup._open, "preview-context.open-settings",
                "Open selected preview element settings", "action", {
                    historyMode = "none",
                    help = "Opens the exact options section for the selected preview element.",
                    command = {
                        kind = "button",
                        historyMode = "none",
                        canExecute = function()
                            return popup.IsShown and popup:IsShown()
                                and popup._handle ~= nil and type(popup._openSettings) == "function"
                        end,
                        set = function()
                            if not (popup.IsShown and popup:IsShown()) then return false end
                            local h, fn = popup._handle, popup._openSettings
                            if h == nil or type(fn) ~= "function" then return false end
                            popup:Hide()
                            return fn(h, "search") ~= false
                        end,
                    },
                })
        end
        RegisterPopupDismiss(M2, popup._keep, popup, "preview-context.keep-selected", "Keep preview element selected",
            "Closes the preview quick-actions popup without changing the current selection.")
        H._previewHandleContextPopup = popup
    end
    popup._handle = handle
    popup._openSettings = openSettings
    if popup._title and popup._title.SetText then SetShownText(popup._title, tr(opts.title
        or (handle._label or handle._previewText or handle._key or "Preview Element"))) end
    popup._open:SetScript("OnClick", function(self)
        local p = self:GetParent()
        local h = p and p._handle
        local fn = p and p._openSettings
        if p then p:Hide() end
        if type(fn) == "function" then fn(h, "context") end
    end)
    M2.ApplyPopupFramePriority(popup)
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", handle, "BOTTOMRIGHT", 8, -2)
    popup:Show()
    return popup
end
local SETTINGS_ICON_RECTS = {
    { 10, 1, "CENTER", 0, 4, 0.70 }, { 10, 1, "CENTER", 0, 0, 0.70 }, { 10, 1, "CENTER", 0, -4, 0.70 },
    { 3, 3, "CENTER", -3, 4, 1.00 }, { 3, 3, "CENTER", 3, 0, 1.00 }, { 3, 3, "CENTER", -1, -4, 1.00 },
}
-- One flat white rectangle of a glyph drawn from rects, placed at (x, y) from the point.
local function AddFlatRect(button, width, height, point, x, y)
    local tex = PixelLayoutRegion(button:CreateTexture(nil, "ARTWORK", nil, 6))
    tex:SetTexture(WHITE8X8)
    tex:SetSize(width, height)
    tex:SetPoint(point, button, point, x, y)
    return tex
end
local function CreatePreviewSettingsIcon(button)
    if not (button and button.CreateTexture) or button._msuf2PreviewSettingsParts then return end
    local parts = {}
    for i = 1, #SETTINGS_ICON_RECTS do
        local r = SETTINGS_ICON_RECTS[i]
        parts[i] = AddFlatRect(button, r[1], r[2], r[3], r[4], r[5])
    end
    button._msuf2PreviewSettingsParts = parts
end

local function PaintPreviewSettingsIcon(button, hover)
    local parts = button and button._msuf2PreviewSettingsParts
    local mul = hover and 1.16 or 1
    if parts then
        for i = 1, #parts do
            local alpha = SETTINGS_ICON_RECTS[i][6] or 1
            parts[i]:SetVertexColor(min(0.76 * mul, 1), min(0.94 * mul, 1), 1, hover and 1 or alpha)
        end
    end
end

function H.EnsurePreviewHandleGear(handle, opts)
    opts = opts or {}
    if not handle then return nil end
    local T = opts.T or (M.Theme)
    local tr = opts.Tr or opts.TR or (M.Tr) or Fallbacks.Identity
    local gear = handle._msuf2SettingsGear
    if not gear then
        local template = T and T.Template and T.Template() or "BackdropTemplate"
        gear = PixelLayoutRegion(CreateFrame("Button", nil, handle, template))
        gear:SetSize(18, 18)
        gear:SetPoint("BOTTOMLEFT", handle, "TOPRIGHT", -8, -8)
        if gear.SetHitRectInsets then gear:SetHitRectInsets(-2, -2, -2, -2) end
        if T and T.CreateSuperellipseLayers then
            local fill, edge = T.CreateSuperellipseLayers(gear, "_msuf2PreviewGear", 2, "BACKGROUND", "BORDER")
            gear._fill, gear._edge = fill, edge
        elseif gear.SetBackdrop then
            FlatBackdrop(gear)
        end
        CreatePreviewSettingsIcon(gear)
        local bg, br = { 0.010, 0.022, 0.040, 0.96 }, { 0.160, 0.560, 0.720, 0.92 }
        local function Paint(self, hover)
            local mul = hover and 1.10 or 1
            if self._fill then
                if T and T.SetFillGradient then T.SetFillGradient(self._fill, bg, 0.12, -0.18) else self._fill:SetVertexColor(bg[1], bg[2], bg[3], bg[4]) end
            elseif self.SetBackdropColor then
                self:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
            end
            if self._edge then
                self._edge:SetVertexColor(min(br[1] * mul, 1), min(br[2] * mul, 1), min(br[3] * mul, 1), br[4])
            elseif self.SetBackdropBorderColor then
                self:SetBackdropBorderColor(br[1], br[2], br[3], br[4])
            end
            PaintPreviewSettingsIcon(self, hover)
        end
        gear:SetScript("OnEnter", function(self)
            Paint(self, true)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(tr("Open Settings"), 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        gear:SetScript("OnLeave", function(self)
            Paint(self, false)
            if GameTooltip then GameTooltip:Hide() end
        end)
        gear:SetScript("OnClick", function(self)
            local h = self._handle
            local fn = self._openSettings
            if type(fn) == "function" then fn(h, "gear") end
        end)
        Paint(gear, false)
        gear:Hide()
        handle._msuf2SettingsGear = gear
    end
    gear._handle = handle
    gear._openSettings = opts.openSettings
    gear:SetShown(opts.shown == true)
    return gear
end
-- Zoom lock glyph, drawn from flat rects like the handle gear so it cannot fall
-- back to a missing texture. "Locked" means the preview keeps the zoom the user
-- dialled in instead of refitting whenever the footprint changes.
local LOCK_ICON_RECTS = {
    body = { 10, 7, 0, -3 },
    postLeft = { 2, 5, -3, 2 },
    postRight = { 2, 5, 3, 2 },
    bow = { 8, 2, 0, 4 },
}
local function CreateZoomLockIcon(button)
    if not (button and button.CreateTexture) or button._msuf2ZoomLockParts then return end
    local parts = {}
    for name, r in pairs(LOCK_ICON_RECTS) do
        parts[name] = AddFlatRect(button, r[1], r[2], "CENTER", r[3], r[4])
    end
    button._msuf2ZoomLockParts = parts
end
local function PaintZoomLockIcon(button, locked, hover)
    local parts = button and button._msuf2ZoomLockParts
    if not parts then return end
    local r, g, b = 0.55, 0.62, 0.74
    if locked then r, g, b = 0.30, 0.86, 1.00 end
    if hover then r, g, b = min(r * 1.25, 1), min(g * 1.25, 1), min(b * 1.25, 1) end
    for _, tex in pairs(parts) do tex:SetVertexColor(r, g, b, locked and 1 or 0.82) end
    -- An open shackle reads as "unlocked" at a glance; the closed one is the
    -- only state in which the zoom survives a layer toggle.
    parts.postRight:SetShown(locked)
    parts.bow:ClearAllPoints()
    parts.bow:SetPoint("CENTER", button, "CENTER", locked and 0 or 2, locked and 4 or 5)
end

--- Opt-in zoom lock: pins the current scale so layer toggles stop refitting the
--- canvas. A default lock is resolved only after the renderer has produced its
--- first real Fit scale; it is preview-local and never reads or writes a profile.
function H.EnsureZoomLockButton(box, zoomBar, opts)
    if not (box and zoomBar) then return nil end
    opts = opts or {}
    local tr = opts.Tr or opts.TR or (M.Tr) or Fallbacks.Identity
    local T = opts.T or (M.Theme)
    local btn = box.zoomLockButton
    if not btn then
        btn = PixelLayoutRegion(CreateFrame("Button", nil, zoomBar, (T and T.Template and T.Template()) or "BackdropTemplate"))
        btn:SetSize(20, opts.buttonHeight or 20)
        CreateZoomLockIcon(btn)
        H.StylePreviewPillButton(btn, T, {})
        box.zoomLockButton = btn
    end
    if box._msuf2ZoomLockDefaultInitialized ~= true then
        box._msuf2ZoomLockDefaultInitialized = true
        box._msuf2ZoomLockDefaultEnabled = opts.defaultLocked == true or nil
        box._msuf2ZoomLockDefaultPending = box._msuf2ZoomLockDefaultEnabled
    end
    local function Locked()
        return box._manualZoom ~= nil or box._msuf2ZoomLockDefaultPending == true
    end
    local function Refresh()
        local locked = Locked()
        PaintZoomLockIcon(btn, locked, btn._msuf2PreviewPillHover == true)
        if btn.MSUF2RefreshPreviewPill then btn:MSUF2RefreshPreviewPill(locked) end
    end
    box.RefreshZoomLock = Refresh
    local function SetLocked(locked)
        local setZoom = opts.SetZoom
        if type(setZoom) ~= "function" then return false end
        -- An explicit click owns the state from here on. In particular, an
        -- early Unlock must cancel a not-yet-resolved default lock.
        box._msuf2ZoomLockDefaultPending = nil
        box._msuf2ZoomLockIsDefault, box._msuf2ZoomLockDefaultDropped = nil, nil
        if locked then
            local scale = tonumber(box._manualZoom) or tonumber(box._mockScale) or tonumber(box._mockAutoScale) or 1
            setZoom(box, scale, opts.lockReason or "PREVIEW_ZOOM_LOCK")
        else
            setZoom(box, nil, opts.unlockReason or "PREVIEW_ZOOM_UNLOCK")
        end
        Refresh()
        return Locked() == (locked == true)
    end
    btn:SetScript("OnClick", function() SetLocked(not Locked()) end)
    -- The pill styling owns OnEnter/OnLeave through SetScript, so the tooltip
    -- chains behind it. Hook exactly once; a second Ensure call would otherwise
    -- stack duplicate tooltip handlers.
    if not btn._msuf2ZoomLockHooked then
        btn._msuf2ZoomLockHooked = true
        btn:HookScript("OnEnter", function(self)
            if box.RefreshZoomLock then box.RefreshZoomLock() end
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(tr("Lock zoom"), 1, 1, 1)
                GameTooltip:AddLine(tr("Locked: the preview keeps this zoom and position when you toggle layers."), 0.82, 0.82, 0.82, true)
                GameTooltip:AddLine(tr("Unlocked: the preview refits itself whenever the frame footprint changes."), 0.55, 0.68, 0.86, true)
                GameTooltip:Show()
            end
        end)
        btn:HookScript("OnLeave", function()
            if box.RefreshZoomLock then box.RefreshZoomLock() end
            if GameTooltip then GameTooltip:Hide() end
        end)
    end
    btn._msuf2CommandAction = {
        kind = "toggle",
        historyMode = "none",
        get = Locked,
        set = SetLocked,
    }
    Refresh()
    return btn
end
-- Right-click drag moves the preview canvas; empty-space left drag and the
-- middle-button gesture now share the same path. The hint counts real moves
-- (not bare clicks) and retires itself after three; the tally is persisted.
local PREVIEW_CHROME_FALLBACK = {
    outerBg = { 0.035, 0.067, 0.114, 0.54 },
    outerBorder = { 0.086, 0.149, 0.227, 0.46 },
    canvasBg = { 0.020, 0.039, 0.071, 0.92 },
    canvasBorder = { 0.086, 0.149, 0.227, 0.38 },
    canvasTop = { 0.020, 0.039, 0.071, 0.96 },
    canvasBottom = { 0.027, 0.063, 0.106, 0.90 },
    sidebarBg = { 0.020, 0.039, 0.071, 0.56 },
    sidebarBorder = { 0.086, 0.149, 0.227, 0.32 },
    title = { 0.231, 0.510, 0.965, 1.00 },
    layerHeader = { 0.659, 0.706, 0.780, 0.82 },
    rowBase = { 0.035, 0.067, 0.114, 1.00 },
    rowHover = { 0.055, 0.098, 0.161, 1.00 },
}
local function PreviewChromeColor(source, fallback, alpha)
    source = type(source) == "table" and source or fallback
    return { source[1] or fallback[1], source[2] or fallback[2], source[3] or fallback[3], alpha }
end
function H.PreviewChromePalette(theme)
    local colors = (theme and theme.colors) or {}
    return {
        outerBg = PreviewChromeColor(colors.panel, PREVIEW_CHROME_FALLBACK.outerBg, 0.54),
        outerBorder = PreviewChromeColor(colors.borderSoft, PREVIEW_CHROME_FALLBACK.outerBorder, 0.46),
        canvasBg = PreviewChromeColor(colors.coreShadow, PREVIEW_CHROME_FALLBACK.canvasBg, 0.92),
        canvasBorder = PreviewChromeColor(colors.borderSoft, PREVIEW_CHROME_FALLBACK.canvasBorder, 0.38),
        canvasTop = PreviewChromeColor(colors.coreShadow, PREVIEW_CHROME_FALLBACK.canvasTop, 0.96),
        canvasBottom = PreviewChromeColor(colors.coreInk, PREVIEW_CHROME_FALLBACK.canvasBottom, 0.90),
        sidebarBg = PreviewChromeColor(colors.coreShadow, PREVIEW_CHROME_FALLBACK.sidebarBg, 0.56),
        sidebarBorder = PreviewChromeColor(colors.borderSoft, PREVIEW_CHROME_FALLBACK.sidebarBorder, 0.32),
        -- One controlled blue accent anchors the preview header while the
        -- surrounding card, canvas, and tools remain deliberately quiet.
        title = PreviewChromeColor(colors.accent or colors.coreGlow, PREVIEW_CHROME_FALLBACK.title, 1.00),
        layerHeader = PreviewChromeColor(colors.muted, PREVIEW_CHROME_FALLBACK.layerHeader, 0.82),
        rowBase = PreviewChromeColor(colors.coreSurface or colors.panel, PREVIEW_CHROME_FALLBACK.rowBase, 1.00),
        rowHover = PreviewChromeColor(colors.coreRaised or colors.panel2, PREVIEW_CHROME_FALLBACK.rowHover, 1.00),
    }
end
function H.ApplyPreviewChrome(frame, role, theme, fallback)
    if not frame then return H.PreviewChromePalette(theme) end
    role = role or "outer"
    local palette = H.PreviewChromePalette(theme)
    local bg = role == "canvas" and palette.canvasBg or (role == "sidebar" and palette.sidebarBg or palette.outerBg)
    local border = role == "canvas" and palette.canvasBorder or (role == "sidebar" and palette.sidebarBorder or palette.outerBorder)
    if theme and type(theme.ApplyBackdrop) == "function" then
        theme.ApplyBackdrop(frame, bg, border)
    elseif type(fallback) == "function" then
        fallback(frame, bg, border)
    end
    if role == "outer" and theme and type(theme.ApplyGradient) == "function" then
        theme.ApplyGradient(frame, "card", { key = "_msuf2PreviewCardGradient", alpha = 0.34 })
    elseif role == "canvas" and frame.CreateTexture then
        local gradient = frame._msuf2PreviewCanvasGradient
        if not gradient then
            gradient = PixelLayoutRegion(frame:CreateTexture(nil, "BACKGROUND", nil, -7))
            gradient:SetAllPoints(frame)
            gradient:SetTexture("Interface\\Buttons\\WHITE8X8")
            frame._msuf2PreviewCanvasGradient = gradient
        end
        H.ApplyPreviewBackground(frame, palette, theme)
    end
    return palette
end
--- The rectangular power bar border of a unit or group preview: a mouse-free
--- host frame on the mock with four edge textures, kept in mock[field].
function H.EnsurePinnedHeader(box)
    local shade = box._msuf2PinnedHeaderShade
    if not shade and box.CreateTexture then
        shade = PixelLayoutRegion(box:CreateTexture(nil, "BORDER", nil, -1))
        shade:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1)
        shade:SetPoint("TOPRIGHT", box, "TOPRIGHT", -1, -1)
        shade:SetHeight(29)
        shade:SetTexture("Interface\\Buttons\\WHITE8X8")
        box._msuf2PinnedHeaderShade = shade
    end
    local line = box._msuf2PinnedHeaderLine
    if not line and box.CreateTexture then
        line = PixelLayoutRegion(box:CreateTexture(nil, "BORDER", nil, 0))
        line:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -29)
        line:SetPoint("TOPRIGHT", box, "TOPRIGHT", -10, -29)
        line:SetHeight(1)
        line:SetTexture("Interface\\Buttons\\WHITE8X8")
        box._msuf2PinnedHeaderLine = line
    end
    return shade, line
end

--- Shows the pinned header in the theme's shadow and soft border colours,
--- or hides it when the preview is not pinned.
function H.PaintPinnedHeader(shade, line, colors, pinned)
    if shade then
        local bg = colors.coreShadow or { 0.006, 0.016, 0.032, 1 }
        shade:SetColorTexture(bg[1], bg[2], bg[3], pinned and 0.92 or 0)
        shade:SetShown(pinned)
    end
    if line then
        local border = colors.borderSoft or colors.border or { 0.070, 0.260, 0.390, 1 }
        line:SetColorTexture(border[1], border[2], border[3], pinned and 0.52 or 0)
        line:SetShown(pinned)
    end
end


H._Shared.PillPalette = PillPalette
H._Shared.PaintPillLayers = PaintPillLayers
H._Shared.PREVIEW_CHROME_FALLBACK = PREVIEW_CHROME_FALLBACK
