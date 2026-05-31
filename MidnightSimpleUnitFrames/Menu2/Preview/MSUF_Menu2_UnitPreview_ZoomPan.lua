--- Unit preview zoom and canvas pan helpers.

local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
_G.MSUF_NS = MSUF

local ZoomPan = MSUF.UFPreviewZoomPan or {}
MSUF.UFPreviewZoomPan = ZoomPan

local floor = math.floor
local ZOOM_MIN, ZOOM_MAX = 0.35, 4.0
local ZOOM_STEPS = { 0.35, 0.50, 0.75, 1.00, 1.25, 1.50, 2.00, 3.00, 4.00 }
local deps = {}

ZoomPan.MIN = ZOOM_MIN
ZoomPan.MAX = ZOOM_MAX

function ZoomPan.Configure(nextDeps)
    if type(nextDeps) == "table" then deps = nextDeps end
end

function ZoomPan.Clamp(v)
    v = tonumber(v) or 1
    if v < ZOOM_MIN then return ZOOM_MIN end
    if v > ZOOM_MAX then return ZOOM_MAX end
    return floor(v * 100 + 0.5) / 100
end

function ZoomPan.UpdateControls(box)
    if not box then return end
    local zoom = box._manualZoom
    local scale = tonumber(box._mockScale) or tonumber(zoom) or tonumber(box._mockAutoScale) or 1
    if box.zoomReadout then
        local pct = floor(scale * 100 + 0.5)
        if zoom then
            box.zoomReadout:SetText(string.format("%d%%", pct))
        else
            box.zoomReadout:SetText(string.format("Fit %d%%", pct))
        end
    end
    if box.zoomFitButton and box.zoomFitButton.fs then
        box.zoomFitButton.fs:SetTextColor(zoom and 0.72 or 0.25, zoom and 0.78 or 0.95, zoom and 0.90 or 1.00, 1)
    end
end

function ZoomPan.SetZoom(box, zoom, reason)
    if not box then return end
    if zoom == nil or zoom == "fit" then
        box._manualZoom = nil
        box._zoomPanX, box._zoomPanY = 0, 0
    else
        box._manualZoom = ZoomPan.Clamp(zoom)
    end
    ZoomPan.UpdateControls(box)
    local preview = deps.Preview or MSUF.UFPreview
    if preview and type(preview.Refresh) == "function" then
        preview.Refresh(box, reason or "UNIT_PREVIEW_ZOOM")
    end
end

function ZoomPan.Step(box, dir)
    if not box then return end
    local current = ZoomPan.Clamp(box._manualZoom or box._mockScale or box._mockAutoScale or 1)
    local nextZoom = current
    if (tonumber(dir) or 0) > 0 then
        for i = 1, #ZOOM_STEPS do
            if ZOOM_STEPS[i] > current + 0.001 then
                nextZoom = ZOOM_STEPS[i]
                break
            end
        end
    else
        for i = #ZOOM_STEPS, 1, -1 do
            if ZOOM_STEPS[i] < current - 0.001 then
                nextZoom = ZOOM_STEPS[i]
                break
            end
        end
    end
    ZoomPan.SetZoom(box, nextZoom, "UNIT_PREVIEW_ZOOM_STEP")
end

function ZoomPan.CreateButton(parent, text, width, tooltip, onClick)
    local tex = deps.TEX_W8 or "Interface\\Buttons\\WHITE8X8"
    local tr = deps.TR or function(v) return v end
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 24, 18)
    btn:SetBackdrop({ bgFile = tex, edgeFile = tex, edgeSize = 1 })
    btn:SetBackdropColor(0.025, 0.030, 0.045, 0.88)
    btn:SetBackdropBorderColor(0.12, 0.16, 0.24, 0.92)
    btn.fs = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    btn.fs:SetPoint("CENTER")
    btn.fs:SetText(text)
    btn.fs:SetTextColor(0.78, 0.84, 0.96, 1)
    btn:SetScript("OnClick", onClick)
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.05, 0.07, 0.11, 0.98)
        self:SetBackdropBorderColor(0.28, 0.42, 0.68, 1)
        if GameTooltip and tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tr(tooltip), 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.025, 0.030, 0.045, 0.88)
        self:SetBackdropBorderColor(0.12, 0.16, 0.24, 0.92)
        if GameTooltip then GameTooltip:Hide() end
    end)
    return btn
end

function ZoomPan.ApplyPan(box)
    if not (box and box.canvas and box.mock) then return end
    local panX, panY = tonumber(box._zoomPanX) or 0, tonumber(box._zoomPanY) or 0
    box.mock:ClearAllPoints()
    box.mock:SetPoint("CENTER", box.canvas, "CENTER", (tonumber(box._mockBaseOffsetX) or 0) + panX, (tonumber(box._mockBaseOffsetY) or 0) + panY)
    if box._detachedCastPreview and box.mock.cast and box.mock.cast:IsShown() then
        box.mock.cast:ClearAllPoints()
        box.mock.cast:SetPoint("CENTER", box.canvas, "CENTER", (tonumber(box._detachedCastBaseOffsetX) or 0) + panX, (tonumber(box._detachedCastBaseOffsetY) or 0) + panY)
    end
end

function ZoomPan.Stop(canvas)
    if not canvas then return end
    local box = canvas._msufPreviewPanBox
    canvas._msufPreviewPanning = nil
    canvas._msufPreviewPanBox = nil
    canvas._msufPreviewPanCursorX = nil
    canvas._msufPreviewPanCursorY = nil
    canvas._msufPreviewPanStartX = nil
    canvas._msufPreviewPanStartY = nil
    canvas:SetScript("OnUpdate", nil)
    if box and type(deps.UpdateHandleHint) == "function" then deps.UpdateHandleHint(box, box._selectedHandle) end
end

function ZoomPan.Start(canvas, box, button)
    if not (canvas and box) then return false end
    local ctrlLeft = button == "LeftButton" and IsControlKeyDown and IsControlKeyDown()
    if not (ctrlLeft or button == "RightButton" or button == "MiddleButton") then return false end
    if not box._manualZoom then
        box._manualZoom = ZoomPan.Clamp(box._mockScale or box._mockAutoScale or 1)
        ZoomPan.UpdateControls(box)
    end
    local cx, cy = GetCursorPosition()
    local uiScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    if uiScale <= 0 then uiScale = 1 end
    canvas._msufPreviewPanning = true
    canvas._msufPreviewPanBox = box
    canvas._msufPreviewPanCursorX = (cx or 0) / uiScale
    canvas._msufPreviewPanCursorY = (cy or 0) / uiScale
    canvas._msufPreviewPanStartX = tonumber(box._zoomPanX) or 0
    canvas._msufPreviewPanStartY = tonumber(box._zoomPanY) or 0
    if box.hint then
        local tr = deps.TR or function(v) return v end
        box.hint:SetText(tr("moving preview canvas - release mouse to stop - Fit recenters"))
    end
    canvas:SetScript("OnUpdate", function(self)
        if not self._msufPreviewPanning then return end
        local mx, my = GetCursorPosition()
        local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        if scale <= 0 then scale = 1 end
        local nextX = floor((self._msufPreviewPanStartX or 0) + ((mx or 0) / scale - (self._msufPreviewPanCursorX or 0)) + 0.5)
        local nextY = floor((self._msufPreviewPanStartY or 0) + ((my or 0) / scale - (self._msufPreviewPanCursorY or 0)) + 0.5)
        if box._zoomPanX ~= nextX or box._zoomPanY ~= nextY then
            box._zoomPanX, box._zoomPanY = nextX, nextY
            ZoomPan.ApplyPan(box)
        end
    end)
    return true
end
