local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local H = M.PreviewHelpers or {}
M.PreviewHelpers = H

function H.SnapOff(region)
    if region and region.SetSnapToPixelGrid then
        region:SetSnapToPixelGrid(false)
        if region.SetTexelSnappingBias then region:SetTexelSnappingBias(0) end
    end
end

function H.MaskOwner(mock, tex, anchor)
    local owner = tex and tex.GetParent and tex:GetParent() or nil
    if owner and owner.CreateMaskTexture then return owner end
    if anchor and anchor.CreateMaskTexture then return anchor end
    return mock
end

function H.EnsureRoundedMask(mock, key, anchor, tex, maskStoreKey, maskTexture, snapOff)
    if not (mock and anchor) then return nil end
    local owner = H.MaskOwner(mock, tex, anchor)
    if not (owner and owner.CreateMaskTexture) then return nil end

    maskStoreKey = maskStoreKey or "_msufPreviewRoundedMasks"
    mock[maskStoreKey] = mock[maskStoreKey] or {}
    local store = mock[maskStoreKey]
    local bucket = store[key]
    if type(bucket) ~= "table" or bucket.SetTexture then
        bucket = {}
        store[key] = bucket
    end

    local ownerKey = tex or owner
    local mask = bucket[ownerKey]
    if not mask then
        mask = owner:CreateMaskTexture(nil, "ARTWORK")
        local snapOffFn = snapOff or H.SnapOff
        snapOffFn(mask)
        bucket[ownerKey] = mask
    end
    mask:ClearAllPoints()
    mask:SetTexture(maskTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(anchor)
    return mask
end

function H.SetMask(mock, tex, mask, maskedStoreKey)
    if not (mock and tex and tex.AddMaskTexture) then return end
    maskedStoreKey = maskedStoreKey or "_msufPreviewRoundedMasked"
    mock[maskedStoreKey] = mock[maskedStoreKey] or {}
    local store = mock[maskedStoreKey]
    local old = store[tex]
    if old == mask then return end
    if old and tex.RemoveMaskTexture then pcall(tex.RemoveMaskTexture, tex, old) end
    store[tex] = nil
    if mask then
        local ok = pcall(tex.AddMaskTexture, tex, mask)
        if ok then store[tex] = mask end
    end
end

function H.ClearMasks(mock, maskedStoreKey)
    local store = mock and mock[maskedStoreKey or "_msufPreviewRoundedMasked"]
    if store then
        for tex, mask in pairs(store) do
            if tex and tex.RemoveMaskTexture and mask then pcall(tex.RemoveMaskTexture, tex, mask) end
        end
    end
    if mock then mock[maskedStoreKey or "_msufPreviewRoundedMasked"] = nil end
end

function H.BaseEdgeColor()
    local fn = _G.MSUF_GetBarOutlineColor
    if type(fn) == "function" then
        local ok, r, g, b = pcall(fn)
        if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b, 1
        end
    end

    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen then
        return tonumber(gen.barOutlineColorR) or 0,
               tonumber(gen.barOutlineColorG) or 0,
               tonumber(gen.barOutlineColorB) or 0,
               1
    end
    return 0, 0, 0, 1
end

local ZOOM_STEPS = { 0.35, 0.50, 0.75, 1.00, 1.25, 1.50, 2.00, 3.00, 4.00 }

local function ClampZoom(value)
    value = tonumber(value) or 1
    if value < ZOOM_STEPS[1] then return ZOOM_STEPS[1] end
    if value > ZOOM_STEPS[#ZOOM_STEPS] then return ZOOM_STEPS[#ZOOM_STEPS] end
    return math.floor(value * 100 + 0.5) / 100
end

local function UpdateZoomControls(box)
    if not box then return end
    local scale = tonumber(box._mockScale) or tonumber(box._mockAutoScale) or 1
    if box._previewZoomReadout then
        local pct = math.floor(scale * 100 + 0.5)
        box._previewZoomReadout:SetText(box._manualZoom and (pct .. "%") or ("Fit " .. pct .. "%"))
    end
    local fitText = box._previewZoomFit and box._previewZoomFit._text
    if fitText then
        if box._manualZoom then
            fitText:SetTextColor(0.72, 0.78, 0.90, 1)
        else
            fitText:SetTextColor(0.25, 0.95, 1.00, 1)
        end
    end
end
H.UpdateZoomControls = UpdateZoomControls
H.ClampZoom = ClampZoom

local function ApplyPan(box, mode)
    if mode == "TOPLEFT" then
        if not (box and box._stage and box._mock) then return end
        box._mock:ClearAllPoints()
        box._mock:SetPoint("TOPLEFT", box._stage, "TOPLEFT",
            (tonumber(box._mockBaseOffsetX) or 0) + (tonumber(box._zoomPanX) or 0),
            (tonumber(box._mockBaseOffsetY) or 0) + (tonumber(box._zoomPanY) or 0))
        return
    end
    if not (box and box.canvas and box.mock) then return end
    local panX, panY = tonumber(box._zoomPanX) or 0, tonumber(box._zoomPanY) or 0
    box.mock:ClearAllPoints()
    box.mock:SetPoint("CENTER", box.canvas, "CENTER",
        (tonumber(box._mockBaseOffsetX) or 0) + panX,
        (tonumber(box._mockBaseOffsetY) or 0) + panY)
    if box._detachedCastPreview and box.mock.cast and box.mock.cast:IsShown() then
        box.mock.cast:ClearAllPoints()
        box.mock.cast:SetPoint("CENTER", box.canvas, "CENTER",
            (tonumber(box._detachedCastBaseOffsetX) or 0) + panX,
            (tonumber(box._detachedCastBaseOffsetY) or 0) + panY)
    end
end

local function StopPan(surface)
    if not surface then return end
    surface._msufPreviewPanning = nil
    surface._msufPreviewPanBox = nil
    surface:SetScript("OnUpdate", nil)
end
H.StopZoomPan = StopPan

local function MakeZoomButton(parent, text, width, tooltip, onClick)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, 20)
    button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    button:SetBackdropColor(0.025, 0.035, 0.055, 0.94)
    button:SetBackdropBorderColor(0.10, 0.18, 0.28, 0.94)
    button._text = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    button._text:SetPoint("CENTER")
    button._text:SetText(text)
    button._text:SetTextColor(0.72, 0.78, 0.90, 1)
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.045, 0.075, 0.115, 0.98)
        self:SetBackdropBorderColor(0.14, 0.38, 0.58, 0.95)
        if tooltip and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
            GameTooltip:SetText(tooltip, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.025, 0.035, 0.055, 0.94)
        self:SetBackdropBorderColor(0.10, 0.18, 0.28, 0.94)
        if GameTooltip then GameTooltip:Hide() end
    end)
    return button
end

function H.ShowPreviewHandleContext(handle, opts)
    opts = opts or {}
    local openSettings = opts.openSettings
    if not handle or type(openSettings) ~= "function" then return nil end

    local popup = H._previewHandleContextPopup
    if not popup then
        popup = CreateFrame("Frame", "MSUF2PreviewHandleContextMenu", UIParent, "BackdropTemplate")
        popup:SetSize(176, 76)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetClampedToScreen(true)
        popup:EnableMouse(true)
        popup:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        popup:SetBackdropColor(0.014, 0.024, 0.050, 0.985)
        popup:SetBackdropBorderColor(0.10, 0.22, 0.44, 0.90)

        local title = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        title:SetPoint("TOPLEFT", popup, "TOPLEFT", 12, -8)
        title:SetPoint("RIGHT", popup, "RIGHT", -12, 0)
        title:SetJustifyH("LEFT")
        title:SetTextColor(0.72, 0.78, 0.90, 1)
        popup._title = title

        local function MakeContextButton(label, y)
            local button = MakeZoomButton(popup, label, 152, nil, function(self)
                local owner = self:GetParent()
                if self == owner._open then
                    local selected, callback = owner._handle, owner._openSettings
                    owner:Hide()
                    if type(callback) == "function" then callback(selected, "context") end
                else
                    owner:Hide()
                end
            end)
            button:SetHeight(24)
            button:SetPoint("TOPLEFT", popup, "TOPLEFT", 12, y)
            return button
        end

        popup._open = MakeContextButton("Open Settings", -28)
        popup._keep = MakeContextButton("Keep Selected", -52)
        popup:SetScript("OnHide", function(self)
            self._handle = nil
            self._openSettings = nil
        end)
        H._previewHandleContextPopup = popup
    end

    local tr = opts.Tr or opts.TR or M.Tr
    local title = opts.title or handle._previewText or handle._key or "Preview Element"
    if type(tr) == "function" then title = tr(title) end
    popup._title:SetText(tostring(title or ""))
    local openLabel, keepLabel = "Open Settings", "Keep Selected"
    if type(tr) == "function" then
        openLabel, keepLabel = tr(openLabel), tr(keepLabel)
    end
    popup._open._text:SetText(openLabel)
    popup._keep._text:SetText(keepLabel)
    popup._handle = handle
    popup._openSettings = openSettings
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", handle, "BOTTOMRIGHT", 8, -2)
    popup:Show()
    return popup
end

function H.BuildZoomBar(box, surface, opts)
    if not (box and surface) then return nil end
    opts = opts or {}
    local refresh = opts.refresh
    local mode = opts.anchorMode == "TOPLEFT" and "TOPLEFT" or "CENTER"
    local function Refresh(reason)
        if type(refresh) == "function" then refresh(box, reason) end
    end
    local function SetZoom(value, reason)
        if value == nil then
            box._manualZoom = nil
            box._zoomPanX, box._zoomPanY = 0, 0
        else
            box._manualZoom = ClampZoom(value)
        end
        UpdateZoomControls(box)
        Refresh(reason)
    end
    local function Step(direction)
        local current = ClampZoom(box._manualZoom or box._mockScale or box._mockAutoScale or 1)
        local nextZoom = current
        if direction > 0 then
            for i = 1, #ZOOM_STEPS do
                if ZOOM_STEPS[i] > current + 0.001 then nextZoom = ZOOM_STEPS[i]; break end
            end
        else
            for i = #ZOOM_STEPS, 1, -1 do
                if ZOOM_STEPS[i] < current - 0.001 then nextZoom = ZOOM_STEPS[i]; break end
            end
        end
        SetZoom(nextZoom, "PREVIEW_ZOOM_STEP")
    end

    local bar = CreateFrame("Frame", nil, surface)
    bar:SetSize(200, 24)
    bar:SetPoint("TOPRIGHT", surface, "TOPRIGHT", -8, -8)
    if bar.SetFrameLevel and surface.GetFrameLevel then bar:SetFrameLevel((surface:GetFrameLevel() or 0) + 80) end

    local minus = MakeZoomButton(bar, "-", 20, "Zoom out", function() Step(-1) end)
    minus:SetPoint("LEFT", bar, "LEFT", 0, 0)
    local readout = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    readout:SetSize(54, 20)
    readout:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    readout:SetJustifyH("CENTER")
    readout:SetTextColor(0.82, 0.87, 0.96, 1)
    local fit = MakeZoomButton(bar, "Fit", 30, "Fit and recenter preview", function() SetZoom(nil, "PREVIEW_ZOOM_FIT") end)
    fit:SetPoint("LEFT", readout, "RIGHT", 4, 0)
    local one = MakeZoomButton(bar, "1:1", 32, "Show preview at 100%", function() SetZoom(1, "PREVIEW_ZOOM_1_TO_1") end)
    one:SetPoint("LEFT", fit, "RIGHT", 4, 0)
    local plus = MakeZoomButton(bar, "+", 20, "Zoom in", function() Step(1) end)
    plus:SetPoint("LEFT", one, "RIGHT", 4, 0)
    local help = MakeZoomButton(bar, "?", 20, "Ctrl + mouse wheel: zoom\nCtrl + left-drag: pan\nFit: recenter\n1:1: exact 100%", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
            GameTooltip:SetText("Preview controls", 1, 1, 1)
            GameTooltip:AddLine("Ctrl + mouse wheel: zoom", 0.82, 0.86, 0.94)
            GameTooltip:AddLine("Ctrl + left-drag: pan", 0.82, 0.86, 0.94)
            GameTooltip:AddLine("Fit: fit and recenter", 0.82, 0.86, 0.94)
            GameTooltip:AddLine("1:1: exact 100%", 0.82, 0.86, 0.94)
            GameTooltip:Show()
        end
    end)
    help:SetPoint("LEFT", plus, "RIGHT", 4, 0)

    box._previewZoomReadout = readout
    box._previewZoomFit = fit
    box._previewZoomBar = bar
    box._applyPreviewPan = function(self) ApplyPan(self, mode) end
    box._stopPreviewPan = function() StopPan(surface) end

    surface:EnableMouse(true)
    surface:EnableMouseWheel(true)
    surface:RegisterForDrag("LeftButton")
    local function ZoomWheel(_, delta)
        if IsControlKeyDown and IsControlKeyDown() then
            Step(delta > 0 and 1 or -1)
            return
        end
        local scroll = M.scrollFrame
        local wheel = scroll and scroll.GetScript and scroll:GetScript("OnMouseWheel")
        if wheel then wheel(scroll, delta) end
    end
    surface:SetScript("OnMouseWheel", ZoomWheel)
    bar:EnableMouseWheel(true)
    bar:SetScript("OnMouseWheel", ZoomWheel)
    local function StartPan(self, button)
        if button ~= "LeftButton" or not (IsControlKeyDown and IsControlKeyDown()) then return end
        if self._msufPreviewPanning then return true end
        if not box._manualZoom then
            box._manualZoom = ClampZoom(box._mockScale or box._mockAutoScale or 1)
            UpdateZoomControls(box)
        end
        local cx, cy = GetCursorPosition()
        local uiScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        if uiScale <= 0 then uiScale = 1 end
        self._msufPreviewPanning = true
        self._msufPreviewPanBox = box
        self._msufPreviewCursorX, self._msufPreviewCursorY = (cx or 0) / uiScale, (cy or 0) / uiScale
        self._msufPreviewStartX, self._msufPreviewStartY = tonumber(box._zoomPanX) or 0, tonumber(box._zoomPanY) or 0
        self:SetScript("OnUpdate", function(panSurface)
            if not panSurface._msufPreviewPanning then return end
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then StopPan(panSurface); return end
            local mx, my = GetCursorPosition()
            local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
            if scale <= 0 then scale = 1 end
            box._zoomPanX = math.floor((panSurface._msufPreviewStartX or 0) + ((mx or 0) / scale - (panSurface._msufPreviewCursorX or 0)) + 0.5)
            box._zoomPanY = math.floor((panSurface._msufPreviewStartY or 0) + ((my or 0) / scale - (panSurface._msufPreviewCursorY or 0)) + 0.5)
            ApplyPan(box, mode)
        end)
        return true
    end
    box._startPreviewPan = function(button) return StartPan(surface, button) end
    surface:SetScript("OnMouseDown", StartPan)
    surface:SetScript("OnDragStart", StartPan)
    surface:SetScript("OnMouseUp", StopPan)
    surface:SetScript("OnDragStop", StopPan)
    surface:HookScript("OnHide", StopPan)
    UpdateZoomControls(box)
    return bar
end
