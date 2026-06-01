local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local H = M.PreviewHelpers or {}
M.PreviewHelpers = H

function H.InstallZoomPan(ZoomPan, opts)
    if type(ZoomPan) ~= "table" then return end
    opts = opts or {}

    local floor = math.floor
    local minZoom = tonumber(opts.minZoom) or 0.35
    local maxZoom = tonumber(opts.maxZoom) or 4.0
    local steps = opts.steps or { 0.35, 0.50, 0.75, 1.00, 1.25, 1.50, 2.00, 3.00, 4.00 }
    local deps = {}
    local white = "Interface\\Buttons\\WHITE8X8"

    local function PathValue(object, path)
        if not object or not path then return nil end
        if type(path) ~= "table" then return object[path] end
        local value = object
        for i = 1, #path do
            value = value and value[path[i]]
        end
        return value
    end

    local function TR(text)
        local fn = deps.TR
        return (type(fn) == "function" and fn(text)) or text
    end

    local function Round(value)
        return floor((tonumber(value) or 0) + 0.5)
    end

    local function PanKey(name)
        return tostring(opts.panPrefix or "_msufPreview") .. name
    end

    ZoomPan.MIN = minZoom
    ZoomPan.MAX = maxZoom

    function ZoomPan.Configure(nextDeps)
        if opts.configureTableOnly then
            if type(nextDeps) == "table" then deps = nextDeps end
        else
            deps = nextDeps or deps or {}
        end
    end

    function ZoomPan.Clamp(value)
        value = tonumber(value) or 1
        if value < minZoom then return minZoom end
        if value > maxZoom then return maxZoom end
        return floor(value * 100 + 0.5) / 100
    end

    function ZoomPan.UpdateControls(box)
        if not box then return end
        local zoom = box._manualZoom
        local scale = tonumber(box._mockScale) or tonumber(zoom) or tonumber(box._mockAutoScale) or 1
        local readout = box[opts.readoutField or "zoomReadout"]
        if readout then
            local pct = floor(scale * 100 + 0.5)
            readout:SetText(zoom and string.format("%d%%", pct) or string.format(opts.translateFitText and TR("Fit %d%%") or "Fit %d%%", pct))
        end
        local fitText = PathValue(box, opts.fitButtonTextPath or { "zoomFitButton", "fs" })
        if fitText then
            fitText:SetTextColor(zoom and 0.72 or 0.25, zoom and 0.78 or 0.95, zoom and 0.90 or 1.00, 1)
        end
    end

    function ZoomPan.ApplyPan(box)
        if opts.panMode == "topLeft" then
            if not (box and box._stage and box._mock) then return end
            local x = (tonumber(box._mockBaseOffsetX) or 0) + (tonumber(box._zoomPanX) or 0)
            local y = (tonumber(box._mockBaseOffsetY) or 0) + (tonumber(box._zoomPanY) or 0)
            box._mock:ClearAllPoints()
            box._mock:SetPoint("TOPLEFT", box._stage, "TOPLEFT", x, y)
            return
        end

        if not (box and box.canvas and box.mock) then return end
        local panX, panY = tonumber(box._zoomPanX) or 0, tonumber(box._zoomPanY) or 0
        box.mock:ClearAllPoints()
        box.mock:SetPoint("CENTER", box.canvas, "CENTER", (tonumber(box._mockBaseOffsetX) or 0) + panX, (tonumber(box._mockBaseOffsetY) or 0) + panY)
        if box._detachedCastPreview and box.mock.cast and box.mock.cast:IsShown() then
            box.mock.cast:ClearAllPoints()
            box.mock.cast:SetPoint("CENTER", box.canvas, "CENTER", (tonumber(box._detachedCastBaseOffsetX) or 0) + panX, (tonumber(box._detachedCastBaseOffsetY) or 0) + panY)
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
        reason = reason or opts.defaultReason or "UNIT_PREVIEW_ZOOM"
        if type(opts.refresh) == "function" then
            opts.refresh(box, reason, deps)
        elseif box.Refresh then
            box:Refresh(reason)
        end
    end

    function ZoomPan.Step(box, direction)
        if not box then return end
        local current = ZoomPan.Clamp(box._manualZoom or box._mockScale or box._mockAutoScale or 1)
        local nextZoom = current
        if (tonumber(direction) or 0) > 0 then
            for i = 1, #steps do
                if steps[i] > current + 0.001 then
                    nextZoom = steps[i]
                    break
                end
            end
        else
            for i = #steps, 1, -1 do
                if steps[i] < current - 0.001 then
                    nextZoom = steps[i]
                    break
                end
            end
        end
        ZoomPan.SetZoom(box, nextZoom, opts.stepReason or "UNIT_PREVIEW_ZOOM_STEP")
    end

    function ZoomPan.Stop(surface)
        if not surface then return end
        local box = surface[PanKey("PanBox")]
        surface[PanKey("Panning")] = nil
        surface[PanKey("PanBox")] = nil
        surface[PanKey("PanCursorX")] = nil
        surface[PanKey("PanCursorY")] = nil
        surface[PanKey("PanStartX")] = nil
        surface[PanKey("PanStartY")] = nil
        surface:SetScript("OnUpdate", nil)
        local update = deps[opts.updateHintKey or "UpdateHandleHint"]
        if box and type(update) == "function" then update(box, box._selectedHandle) end
    end

    function ZoomPan.Start(surface, box, button)
        if not (surface and box) then return false end
        local ctrlLeft = button == "LeftButton" and IsControlKeyDown and IsControlKeyDown()
        if not (ctrlLeft or button == "RightButton" or button == "MiddleButton") then return false end
        if not box._manualZoom then
            box._manualZoom = ZoomPan.Clamp(box._mockScale or box._mockAutoScale or 1)
            ZoomPan.UpdateControls(box)
        end
        local cx, cy = GetCursorPosition()
        local uiScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        if uiScale <= 0 then uiScale = 1 end
        surface[PanKey("Panning")] = true
        surface[PanKey("PanBox")] = box
        surface[PanKey("PanCursorX")] = (cx or 0) / uiScale
        surface[PanKey("PanCursorY")] = (cy or 0) / uiScale
        surface[PanKey("PanStartX")] = tonumber(box._zoomPanX) or 0
        surface[PanKey("PanStartY")] = tonumber(box._zoomPanY) or 0
        local hint = box[opts.hintField or "hint"]
        if hint then hint:SetText(TR("moving preview canvas - release mouse to stop - Fit recenters")) end
        surface:SetScript("OnUpdate", function(self)
            if not self[PanKey("Panning")] then return end
            local mx, my = GetCursorPosition()
            local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
            if scale <= 0 then scale = 1 end
            local nextX = Round((self[PanKey("PanStartX")] or 0) + ((mx or 0) / scale - (self[PanKey("PanCursorX")] or 0)))
            local nextY = Round((self[PanKey("PanStartY")] or 0) + ((my or 0) / scale - (self[PanKey("PanCursorY")] or 0)))
            if box._zoomPanX ~= nextX or box._zoomPanY ~= nextY then
                box._zoomPanX, box._zoomPanY = nextX, nextY
                ZoomPan.ApplyPan(box)
            end
        end)
        return true
    end

    function ZoomPan.CreateButton(parent, text, width, tooltip, onClick)
        local T = deps.T
        local template = opts.themeButton and (T and T.Template and T.Template() or nil) or (opts.buttonTemplate or "BackdropTemplate")
        local btn = CreateFrame("Button", nil, parent, template)
        local tex = deps[opts.buttonTextureKey or "TEX_W8"] or white
        btn:SetSize(width or 24, 18)
        btn:SetBackdrop({ bgFile = tex, edgeFile = tex, edgeSize = 1 })
        btn:SetBackdropColor(0.025, 0.030, 0.045, 0.88)
        btn:SetBackdropBorderColor(0.12, 0.16, 0.24, 0.92)
        local fontField = opts.buttonFontField or "fs"
        if opts.themeButton and T and T.Font then
            btn[fontField] = T.Font(btn, "GameFontDisableSmall", text, { 0.78, 0.84, 0.96, 1 })
        elseif not opts.themeButton then
            btn[fontField] = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            btn[fontField]:SetText(text)
            btn[fontField]:SetTextColor(0.78, 0.84, 0.96, 1)
        end
        if btn[fontField] then btn[fontField]:SetPoint("CENTER") end
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
end

function H.BuildZoomBar(box, surface, opts)
    if not (box and surface) then return nil end
    opts = opts or {}
    local tr = opts.Tr or function(text) return text end
    local tex = opts.texture or "Interface\\Buttons\\WHITE8X8"
    local template = opts.template or "BackdropTemplate"
    local stepZoom = opts.StepZoom or function() end
    local setZoom = opts.SetZoom or function() end
    local startPan = opts.StartPan or function() return false end
    local stopPan = opts.StopPan or function() end
    local createButton = opts.CreateZoomButton or function(parent, text, width, tooltip, onClick)
        local btn = CreateFrame("Button", nil, parent, template)
        btn:SetSize(width or 24, 18)
        btn:SetBackdrop({ bgFile = tex, edgeFile = tex, edgeSize = 1 })
        btn:SetText(text)
        btn:SetScript("OnClick", onClick)
        return btn
    end
    local prefix = opts.fieldPrefix or ""

    local zoomBar = CreateFrame("Frame", nil, surface, template)
    zoomBar:SetSize(opts.width or 160, opts.height or 22)
    zoomBar:SetPoint("TOPRIGHT", surface, "TOPRIGHT", -8, -6)
    zoomBar:SetBackdrop({ bgFile = tex, edgeFile = tex, edgeSize = 1 })
    zoomBar:SetBackdropColor(0.015, 0.018, 0.030, 0.86)
    zoomBar:SetBackdropBorderColor(0.10, 0.14, 0.22, 0.92)
    if zoomBar.SetFrameLevel then zoomBar:SetFrameLevel((surface.GetFrameLevel and surface:GetFrameLevel() or 0) + 80) end
    zoomBar:EnableMouse(true)
    zoomBar:EnableMouseWheel(true)
    if zoomBar.SetPropagateMouseWheel then zoomBar:SetPropagateMouseWheel(false) end
    box[prefix .. "zoomBar"] = zoomBar
    zoomBar:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tr("Preview zoom"), 1, 1, 1)
            GameTooltip:AddLine(tr("Use the buttons or Ctrl + mouse wheel to zoom."), 0.82, 0.82, 0.82, true)
            GameTooltip:AddLine(tr("Ctrl + left-drag moves the preview canvas. Fit recenters it."), 0.55, 0.68, 0.86, true)
            GameTooltip:Show()
        end
    end)
    zoomBar:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    local zoomOut = createButton(zoomBar, "-", 18, "Zoom out", function() stepZoom(box, -1) end)
    zoomOut:SetPoint("LEFT", zoomBar, "LEFT", 3, 0)
    box[prefix .. "zoomOutButton"] = zoomOut

    local T = opts.T
    local readout
    if opts.themeReadout and T and T.Font then
        readout = T.Font(zoomBar, "GameFontDisableSmall", "", { 0.72, 0.78, 0.90, 1 })
    else
        readout = zoomBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        readout:SetTextColor(0.72, 0.78, 0.90, 1)
    end
    readout:SetPoint("LEFT", zoomOut, "RIGHT", 3, 0)
    readout:SetSize(54, 18)
    readout:SetJustifyH("CENTER")
    box[prefix .. "zoomReadout"] = readout

    local fitButton = createButton(zoomBar, "Fit", 28, "Fit preview", function() setZoom(box, nil, opts.fitReason) end)
    fitButton:SetPoint("LEFT", readout, "RIGHT", 3, 0)
    box[prefix .. "zoomFitButton"] = fitButton

    local oneButton = createButton(zoomBar, "1:1", 30, "Pixel preview", function() setZoom(box, 1, opts.oneReason) end)
    oneButton:SetPoint("LEFT", fitButton, "RIGHT", 3, 0)
    box[prefix .. "zoomOneButton"] = oneButton

    local zoomIn = createButton(zoomBar, "+", 18, "Zoom in", function() stepZoom(box, 1) end)
    zoomIn:SetPoint("LEFT", oneButton, "RIGHT", 3, 0)
    box[prefix .. "zoomInButton"] = zoomIn

    local function ZoomWheel(self, delta)
        local dir = (delta or 0) > 0 and 1 or -1
        if IsControlKeyDown and IsControlKeyDown() then
            if self.SetPropagateMouseWheel then self:SetPropagateMouseWheel(false) end
            stepZoom(box, dir)
        elseif self.SetPropagateMouseWheel then
            self:SetPropagateMouseWheel(true)
        end
    end
    if opts.wheelField then box[opts.wheelField] = ZoomWheel end
    surface:SetScript("OnMouseWheel", ZoomWheel)
    zoomBar:SetScript("OnMouseWheel", function(_, delta) stepZoom(box, (delta or 0) > 0 and 1 or -1) end)
    surface:SetScript("OnMouseDown", function(self, button) startPan(self, box, button) end)
    surface:SetScript("OnMouseUp", stopPan)
    surface:SetScript("OnHide", stopPan)
    return zoomBar, ZoomWheel
end

local TEXT_FOCUS_SIDES = { "top", "bottom", "left", "right" }

function H.NormalizeTextFocusKind(kind)
    if kind == "name" or kind == "hp" or kind == "power" then return kind end
    return nil
end

function H.NormalizeTextFocusSlot(slot)
    if slot == "left" or slot == "center" or slot == "right" then return slot end
    return nil
end

function H.TextFocusColor(kind, colors)
    colors = colors or {}
    if kind == "hp" then return colors.hp or { 0.28, 0.86, 0.45 } end
    if kind == "power" then return colors.power or { 0.95, 0.72, 0.18 } end
    return colors.name or { 0.30, 0.66, 1.00 }
end

function H.EnsureTextFocusFrame(box, parent)
    if not (box and parent) then return nil end
    local f = box._msufMenuTextFocusFrame
    if not f then
        f = CreateFrame("Frame", nil, parent)
        f:EnableMouse(false)
        f.fill = f:CreateTexture(nil, "BACKGROUND")
        f.fill:SetAllPoints()
        f.lines = {}
        for i = 1, #TEXT_FOCUS_SIDES do
            local side = TEXT_FOCUS_SIDES[i]
            f.lines[side] = f:CreateTexture(nil, "OVERLAY")
        end
        f.lines.top:SetPoint("TOPLEFT")
        f.lines.top:SetPoint("TOPRIGHT")
        f.lines.bottom:SetPoint("BOTTOMLEFT")
        f.lines.bottom:SetPoint("BOTTOMRIGHT")
        f.lines.left:SetPoint("TOPLEFT")
        f.lines.left:SetPoint("BOTTOMLEFT")
        f.lines.right:SetPoint("TOPRIGHT")
        f.lines.right:SetPoint("BOTTOMRIGHT")
        box._msufMenuTextFocusFrame = f
    elseif f.SetParent then
        f:SetParent(parent)
    end
    if f.SetFrameLevel and parent.GetFrameLevel then
        f:SetFrameLevel((parent:GetFrameLevel() or 0) + 85)
    end
    return f
end

function H.PaintTextFocusFrame(frame, color, active)
    if not (frame and color) then return end
    local lineAlpha = active and 0.92 or 0.74
    local fillAlpha = active and 0.10 or 0.065
    local thickness = active and 2 or 1
    if frame.fill then frame.fill:SetColorTexture(color[1], color[2], color[3], fillAlpha) end
    if frame.lines then
        frame.lines.top:SetHeight(thickness)
        frame.lines.bottom:SetHeight(thickness)
        frame.lines.left:SetWidth(thickness)
        frame.lines.right:SetWidth(thickness)
        for _, line in pairs(frame.lines) do
            if line then line:SetColorTexture(color[1], color[2], color[3], lineAlpha) end
        end
    end
end

function H.PlaceHandleAroundRegions(handle, parent, regions, pad, opts)
    if not (handle and parent and parent.GetLeft and regions) then return false end
    opts = opts or {}
    pad = tonumber(pad) or 3
    local min, max = math.min, math.max
    local left, right, top, bottom
    for i = 1, #regions do
        local region = regions[i]
        if region and region.IsShown and region:IsShown() and region.GetLeft then
            local l, r, t, b = region:GetLeft(), region:GetRight(), region:GetTop(), region:GetBottom()
            if l and r and t and b then
                if opts.fitText then
                    local regionW = r - l
                    if region.GetStringWidth and regionW > 0 then
                        local textW = tonumber(region:GetStringWidth()) or 0
                        if textW > 0 and textW < regionW then
                            local justify = (region.GetJustifyH and region:GetJustifyH()) or region._msufPreviewJustifyH or "LEFT"
                            if justify == "RIGHT" then
                                l = r - textW
                            elseif justify == "CENTER" then
                                local cx = (l + r) * 0.5
                                l, r = cx - (textW * 0.5), cx + (textW * 0.5)
                            else
                                r = l + textW
                            end
                        end
                    end
                    local regionH = t - b
                    if region.GetStringHeight and regionH > 0 then
                        local textH = tonumber(region:GetStringHeight()) or 0
                        if textH > 0 and textH < regionH then
                            local cy = (t + b) * 0.5
                            t, b = cy + (textH * 0.5), cy - (textH * 0.5)
                        end
                    end
                end
                left = left and min(left, l) or l
                right = right and max(right, r) or r
                top = top and max(top, t) or t
                bottom = bottom and min(bottom, b) or b
            end
        end
    end
    local pLeft, pBottom = parent:GetLeft(), parent:GetBottom()
    if not (left and right and top and bottom and pLeft and pBottom) then return false end
    handle:ClearAllPoints()
    handle:SetSize(max(18, right - left + pad * 2), max(18, top - bottom + pad * 2))
    handle:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", left - pLeft - pad, bottom - pBottom - pad)
    handle:Show()
    return true
end

function H.ApplyTextFocus(box, parent, mock, opts)
    opts = opts or {}
    local focus = box and box._msufMenuTextFocus
    local frame = box and box._msufMenuTextFocusFrame
    if not (focus and parent and mock) then
        if frame and frame.Hide then frame:Hide() end
        return
    end
    local regions = opts.Regions and opts.Regions(mock, focus.kind, focus.slot)
    if not regions then
        if frame and frame.Hide then frame:Hide() end
        return
    end
    frame = H.EnsureTextFocusFrame(box, parent)
    if not frame then return end
    local color = (opts.Color and opts.Color(focus.kind)) or H.TextFocusColor(focus.kind, opts.colors)
    H.PaintTextFocusFrame(frame, color, focus.active == true)
    if not (opts.Place and opts.Place(frame, parent, regions, focus.active and 5 or 4)) then
        frame:Hide()
    end
end

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
        local snap = snapOff or H.SnapOff
        snap(mask)
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

local EDGE_LINE_KEYS = { "top", "bottom", "left", "right" }

function H.SetEdgeLinesShown(frame, shown, opts)
    local lines = frame and frame[(opts and opts.linesKey) or "_lines"]
    if type(lines) ~= "table" then return end
    local keys = (opts and opts.keys) or EDGE_LINE_KEYS
    for i = 1, #keys do
        local line = lines[keys[i]]
        if line then
            if shown then line:Show() else line:Hide() end
        end
    end
end

function H.LayoutEdgeLines(frame, edge, opts)
    if not (frame and frame.CreateTexture) then return false end
    opts = opts or {}
    edge = H.ClampEdgeSize(edge, 1, opts.maxEdgeSize or 30)
    if edge <= 0 then H.SetEdgeLinesShown(frame, false, opts); return false end
    local linesKey = opts.linesKey or "_lines"
    local keys = opts.keys or EDGE_LINE_KEYS
    frame[linesKey] = frame[linesKey] or {}
    local lines = frame[linesKey]
    local texture = opts.texture or "Interface\\Buttons\\WHITE8X8"
    local snap = opts.snapOff or H.SnapOff
    for i = 1, #keys do
        local key = keys[i]
        if not lines[key] then
            lines[key] = frame:CreateTexture(nil, opts.layer or "OVERLAY")
            lines[key]:SetTexture(texture)
            snap(lines[key])
        end
    end
    local r, g, b, a = 0, 0, 0, 1
    if type(opts.color) == "function" then r, g, b, a = opts.color(frame) end
    local top, bottom, left, right = lines.top, lines.bottom, lines.left, lines.right
    top:SetVertexColor(r or 0, g or 0, b or 0, a or 1)
    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    top:SetHeight(edge)
    bottom:SetVertexColor(r or 0, g or 0, b or 0, a or 1)
    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(edge)
    left:SetVertexColor(r or 0, g or 0, b or 0, a or 1)
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    left:SetWidth(edge)
    right:SetVertexColor(r or 0, g or 0, b or 0, a or 1)
    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(edge)
    H.SetEdgeLinesShown(frame, true, opts)
    return true
end

function H.ClampEdgeSize(value, fallback, maxValue)
    local n = tonumber(value)
    if n == nil then n = tonumber(fallback) or 0 end
    n = math.floor(n + 0.5)
    if n < 0 then n = 0 end
    maxValue = tonumber(maxValue) or 8
    if n > maxValue then n = maxValue end
    return n
end

function H.EnsureRoundedVisuals(mock, opts)
    if not (mock and mock.CreateTexture) then return false end
    opts = opts or {}
    local bgKey = opts.bgKey or "roundedBg"
    local edgeKey = opts.edgeKey or "roundedEdge"
    local snap = opts.snapOff or H.SnapOff
    if not mock[bgKey] then
        mock[bgKey] = mock:CreateTexture(nil, opts.bgLayer or "BACKGROUND", nil, opts.bgSubLevel)
        mock[bgKey]:SetTexture(opts.whiteTexture or "Interface\\Buttons\\WHITE8X8")
        snap(mock[bgKey])
    end
    if not mock[edgeKey] then
        mock[edgeKey] = mock:CreateTexture(nil, opts.edgeLayer or "OVERLAY", nil, opts.edgeSubLevel)
        snap(mock[edgeKey])
    end
    mock[edgeKey]:SetTexture(opts.edgeTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    return true
end

function H.ForEachRoundedEdge(mock, opts, fn)
    if not (mock and type(fn) == "function") then return end
    opts = opts or {}
    local edge = mock[opts.edgeKey or "roundedEdge"]
    if edge then fn(edge, 1) end
    local stack = mock[opts.stackKey or "_msufPreviewRoundedEdgeStack"]
    if type(stack) ~= "table" then return end
    for i = 2, #stack do
        if stack[i] then fn(stack[i], i) end
    end
end

function H.SetRoundedEdgeStackShown(mock, shown, opts)
    opts = opts or {}
    local count = shown and H.ClampEdgeSize(mock and mock[opts.countKey or "_msufPreviewRoundedEdgeCount"], 1, opts.maxEdgeSize or 8) or 0
    H.ForEachRoundedEdge(mock, opts, function(edge, i)
        if edge.SetShown then
            edge:SetShown(i <= count)
        elseif i <= count then
            edge:Show()
        else
            edge:Hide()
        end
    end)
end

function H.SetRoundedEdgeStackAlpha(mock, alpha, opts)
    local clamp = opts and opts.clamp01
    alpha = type(clamp) == "function" and clamp(alpha, 1) or math.max(0, math.min(1, tonumber(alpha) or 1))
    H.ForEachRoundedEdge(mock, opts, function(edge)
        if edge and edge.SetAlpha then edge:SetAlpha(alpha) end
    end)
end

function H.ApplyRoundedEdgeStack(mock, edgeSize, opts)
    if not mock then return false end
    opts = opts or {}
    local count = H.ClampEdgeSize(edgeSize, 0, opts.maxEdgeSize or 8)
    local stackKey = opts.stackKey or "_msufPreviewRoundedEdgeStack"
    local countKey = opts.countKey or "_msufPreviewRoundedEdgeCount"
    local edgeKey = opts.edgeKey or "roundedEdge"
    mock[countKey] = count
    if count <= 0 then
        H.SetRoundedEdgeStackShown(mock, false, opts)
        return false
    end
    mock[stackKey] = mock[stackKey] or {}
    mock[stackKey][1] = mock[edgeKey]
    local snap = opts.snapOff or H.SnapOff
    local edgeTexture = opts.edgeTexture
    local r, g, b, a
    if type(opts.baseEdgeColor) == "function" then
        r, g, b, a = opts.baseEdgeColor(mock)
    else
        r, g, b, a = H.BaseEdgeColor()
    end
    for i = 1, count do
        local edge = (i == 1) and mock[edgeKey] or mock[stackKey][i]
        if not edge then
            edge = mock:CreateTexture(nil, opts.edgeLayer or "OVERLAY", nil, opts.edgeSubLevel)
            snap(edge)
            mock[stackKey][i] = edge
        end
        edge:SetTexture(edgeTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        edge:ClearAllPoints()
        edge:SetPoint("TOPLEFT", mock, "TOPLEFT", -i, i)
        edge:SetPoint("BOTTOMRIGHT", mock, "BOTTOMRIGHT", i, -i)
        edge:SetVertexColor(r, g, b, a)
        edge:Show()
    end
    H.SetRoundedEdgeStackShown(mock, true, opts)
    return true
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
