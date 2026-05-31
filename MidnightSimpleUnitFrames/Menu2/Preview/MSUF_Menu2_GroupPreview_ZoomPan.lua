--- Group frame preview zoom/pan helpers.
---
--- Kept separate from the native renderer so page construction does not carry
--- interaction mechanics in the same closure.
local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local Specs = M.GroupPreviewSpecs or {}
local ZoomPan = M.GroupPreviewZoomPan or {}
M.GroupPreviewZoomPan = ZoomPan

local floor = math.floor
local ZOOM_MIN = Specs.ZOOM_MIN or 0.35
local ZOOM_MAX = Specs.ZOOM_MAX or 4.0
local ZOOM_STEPS = Specs.ZOOM_STEPS or { 0.35, 0.50, 0.75, 1.00, 1.25, 1.50, 2.00, 3.00, 4.00 }

local deps = {}

local function TR(text)
    local fn = deps.TR
    return (type(fn) == "function" and fn(text)) or text
end

local function Round(value)
    return floor((tonumber(value) or 0) + 0.5)
end

function ZoomPan.Configure(nextDeps)
    deps = nextDeps or deps or {}
end

function ZoomPan.Clamp(value)
    value = tonumber(value) or 1
    if value < ZOOM_MIN then return ZOOM_MIN end
    if value > ZOOM_MAX then return ZOOM_MAX end
    return floor(value * 100 + 0.5) / 100
end

function ZoomPan.UpdateControls(box)
    if not box then return end
    local zoom = box._manualZoom
    local scale = tonumber(box._mockScale) or tonumber(zoom) or tonumber(box._mockAutoScale) or 1
    if box._zoomReadout then
        local pct = floor(scale * 100 + 0.5)
        if zoom then
            box._zoomReadout:SetText(string.format("%d%%", pct))
        else
            box._zoomReadout:SetText(string.format(TR("Fit %d%%"), pct))
        end
    end
    if box._zoomFitButton and box._zoomFitButton._fs then
        box._zoomFitButton._fs:SetTextColor(zoom and 0.72 or 0.25, zoom and 0.78 or 0.95, zoom and 0.90 or 1.00, 1)
    end
end

function ZoomPan.ApplyPan(box)
    if not (box and box._stage and box._mock) then return end
    local x = (tonumber(box._mockBaseOffsetX) or 0) + (tonumber(box._zoomPanX) or 0)
    local y = (tonumber(box._mockBaseOffsetY) or 0) + (tonumber(box._zoomPanY) or 0)
    box._mock:ClearAllPoints()
    box._mock:SetPoint("TOPLEFT", box._stage, "TOPLEFT", x, y)
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
    if box.Refresh then box:Refresh(reason or "GROUP_PREVIEW_ZOOM") end
end

function ZoomPan.Step(box, direction)
    if not box then return end
    local current = ZoomPan.Clamp(box._manualZoom or box._mockScale or box._mockAutoScale or 1)
    local nextZoom = current
    if (tonumber(direction) or 0) > 0 then
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
    ZoomPan.SetZoom(box, nextZoom, "GROUP_PREVIEW_ZOOM_STEP")
end

function ZoomPan.Stop(stage)
    if not stage then return end
    local box = stage._msufGFPreviewPanBox
    stage._msufGFPreviewPanning = nil
    stage._msufGFPreviewPanBox = nil
    stage._msufGFPreviewPanCursorX = nil
    stage._msufGFPreviewPanCursorY = nil
    stage._msufGFPreviewPanStartX = nil
    stage._msufGFPreviewPanStartY = nil
    stage:SetScript("OnUpdate", nil)
    if box and type(deps.UpdateHint) == "function" then
        deps.UpdateHint(box, box._selectedHandle)
    end
end

function ZoomPan.Start(stage, box, button)
    if not (stage and box) then return false end
    local ctrlLeft = button == "LeftButton" and IsControlKeyDown and IsControlKeyDown()
    if not (ctrlLeft or button == "RightButton" or button == "MiddleButton") then return false end
    if not box._manualZoom then
        box._manualZoom = ZoomPan.Clamp(box._mockScale or box._mockAutoScale or 1)
        ZoomPan.UpdateControls(box)
    end
    local cx, cy = GetCursorPosition()
    local uiScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    if uiScale <= 0 then uiScale = 1 end
    stage._msufGFPreviewPanning = true
    stage._msufGFPreviewPanBox = box
    stage._msufGFPreviewPanCursorX = (cx or 0) / uiScale
    stage._msufGFPreviewPanCursorY = (cy or 0) / uiScale
    stage._msufGFPreviewPanStartX = tonumber(box._zoomPanX) or 0
    stage._msufGFPreviewPanStartY = tonumber(box._zoomPanY) or 0
    if box._hint then box._hint:SetText(TR("moving preview canvas - release mouse to stop - Fit recenters")) end
    stage:SetScript("OnUpdate", function(self)
        if not self._msufGFPreviewPanning then return end
        local mx, my = GetCursorPosition()
        local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        if scale <= 0 then scale = 1 end
        local nextX = Round((self._msufGFPreviewPanStartX or 0) + ((mx or 0) / scale - (self._msufGFPreviewPanCursorX or 0)))
        local nextY = Round((self._msufGFPreviewPanStartY or 0) + ((my or 0) / scale - (self._msufGFPreviewPanCursorY or 0)))
        if box._zoomPanX ~= nextX or box._zoomPanY ~= nextY then
            box._zoomPanX, box._zoomPanY = nextX, nextY
            ZoomPan.ApplyPan(box)
        end
    end)
    return true
end

function ZoomPan.CreateButton(parent, text, width, tooltip, onClick)
    local T = deps.T
    local template = T and T.Template and T.Template()
    local btn = CreateFrame("Button", nil, parent, template)
    btn:SetSize(width or 24, 18)
    btn:SetBackdrop({ bgFile = deps.WHITE8X8 or "Interface\\Buttons\\WHITE8X8", edgeFile = deps.WHITE8X8 or "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    btn:SetBackdropColor(0.025, 0.030, 0.045, 0.88)
    btn:SetBackdropBorderColor(0.12, 0.16, 0.24, 0.92)
    if T and T.Font then
        btn._fs = T.Font(btn, "GameFontDisableSmall", text, { 0.78, 0.84, 0.96, 1 })
        btn._fs:SetPoint("CENTER")
    end
    btn:SetScript("OnClick", onClick)
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.05, 0.07, 0.11, 0.98)
        self:SetBackdropBorderColor(0.28, 0.42, 0.68, 1)
        if GameTooltip and tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(TR(tooltip), 1, 1, 1)
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

