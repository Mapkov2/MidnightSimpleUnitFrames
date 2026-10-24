local _, MSUF = ...
local M = MSUF.MSUF2
local H = M.PreviewHelpers
local FILE = "Shell/Menu2/MSUF_Menu2_Preview_ZoomPan.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
local Fallbacks, floor, min = M.Fallbacks, math.floor, math.min
local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local shared = H._Shared
local FlatBackdrop, SetShownText = shared.FlatBackdrop, shared.SetShownText
local PillPalette, PaintPillLayers = shared.PillPalette, shared.PaintPillLayers

function H.SwitchCompactZoomMode(box, compact, defaultCompactZoom)
    if not box then return false end
    compact = compact == true
    local active = box._msuf2CompactZoomMode
    if active == compact then return false end

    -- Expanding the same preview in place must not replace the scale the user
    -- was just looking at with an older Full/Fit state.  Capture the rendered
    -- Compact scale before the larger canvas changes its auto-fit geometry.
    -- Pan remains mode-local because the two canvases have different bounds.
    local compactZoomToCarry, compactZoomCarriedDefault
    if active == true and compact == false and box._msuf2PreserveExpandedZoomOnNextExpand ~= true then
        compactZoomToCarry = tonumber(box._manualZoom)
            or tonumber(box._mockScale)
            or tonumber(box._mockAutoScale)
        -- A carried Fit scale or default lock was not the user's choice.
        compactZoomCarriedDefault = box._manualZoom == nil or box._msuf2ZoomLockIsDefault == true or nil
    end

    local function Store(prefix)
        box[prefix .. "ManualZoom"] = tonumber(box._manualZoom)
        box[prefix .. "PanX"] = tonumber(box._zoomPanX) or 0
        box[prefix .. "PanY"] = tonumber(box._zoomPanY) or 0
        box[prefix .. "DefaultLockPending"] = box._msuf2ZoomLockDefaultPending == true or nil
        box[prefix .. "LockIsDefault"] = box._msuf2ZoomLockIsDefault == true or nil
        box[prefix .. "DefaultDropped"] = box._msuf2ZoomLockDefaultDropped == true or nil
        box[prefix .. "Initialized"] = true
    end
    local function Restore(prefix, fallbackZoom)
        if box[prefix .. "Initialized"] then
            box._manualZoom = box[prefix .. "ManualZoom"]
            box._zoomPanX = tonumber(box[prefix .. "PanX"]) or 0
            box._zoomPanY = tonumber(box[prefix .. "PanY"]) or 0
            box._msuf2ZoomLockDefaultPending = box[prefix .. "DefaultLockPending"] == true or nil
            box._msuf2ZoomLockIsDefault = box[prefix .. "LockIsDefault"] == true or nil
            box._msuf2ZoomLockDefaultDropped = box[prefix .. "DefaultDropped"] == true or nil
            return
        end
        box._manualZoom = tonumber(fallbackZoom)
        box._zoomPanX, box._zoomPanY = 0, 0
        box._msuf2ZoomLockDefaultPending = box._manualZoom == nil
            and box._msuf2ZoomLockDefaultEnabled == true or nil
        -- The mode's fallback zoom is a default, not a user lock.
        box._msuf2ZoomLockIsDefault = box._manualZoom ~= nil or nil
        box._msuf2ZoomLockDefaultDropped = nil
        box[prefix .. "Initialized"] = true
        box[prefix .. "ManualZoom"] = box._manualZoom
        box[prefix .. "PanX"], box[prefix .. "PanY"] = 0, 0
        box[prefix .. "DefaultLockPending"] = box._msuf2ZoomLockDefaultPending
        box[prefix .. "LockIsDefault"] = box._msuf2ZoomLockIsDefault
        box[prefix .. "DefaultDropped"] = nil
    end

    if active == nil then
        -- Before the first compact transition, the preview owns its normal
        -- expanded zoom state.  Preserve that Fit/manual choice verbatim.
        Store("_msuf2ExpandedZoom")
    else
        Store(active and "_msuf2CompactZoom" or "_msuf2ExpandedZoom")
    end
    Restore(compact and "_msuf2CompactZoom" or "_msuf2ExpandedZoom", compact and defaultCompactZoom or nil)
    if compactZoomToCarry then
        box._manualZoom = compactZoomToCarry
        box._msuf2ZoomLockDefaultPending = nil
        box._msuf2ZoomLockIsDefault = compactZoomCarriedDefault
        box._msuf2ZoomLockDefaultDropped = nil
    end
    box._msuf2CompactZoomMode = compact
    return true
end

--- Region-union handles are deliberately placed in the stationary Preview
--- canvas so their hit size is independent of the rendered element's scale.
--- When the mock is panned without a full render refresh, move only those
--- absolute canvas anchors by the same delta. Handles anchored directly to the
--- mock already follow it and must not be shifted a second time.
function H.ShiftPreviewPanFollowers(box, dx, dy)
    if not box then return 0 end
    dx, dy = tonumber(dx) or 0, tonumber(dy) or 0
    if dx == 0 and dy == 0 then return 0 end
    local stationaryCanvas, stationaryStage = box.canvas, box._stage
    local shifted, seen = 0, {}
    local function Shift(frame)
        if not (frame and frame._msufPreviewPanFollower == true and frame.GetPoint
            and frame.ClearAllPoints and frame.SetPoint) or seen[frame]
        then
            return
        end
        seen[frame] = true
        local count = (frame.GetNumPoints and frame:GetNumPoints()) or 1
        local points, changed = {}, false
        for i = 1, count do
            local point, relativeTo, relativePoint, x, y = frame:GetPoint(i)
            if point then
                local followsStationarySurface = relativeTo == stationaryCanvas or relativeTo == stationaryStage
                if followsStationarySurface then
                    x, y = (tonumber(x) or 0) + dx, (tonumber(y) or 0) + dy
                    changed = true
                end
                points[#points + 1] = { point, relativeTo, relativePoint, x or 0, y or 0 }
            end
        end
        if not changed then return end
        frame:ClearAllPoints()
        for i = 1, #points do frame:SetPoint(unpack(points[i])) end
        shifted = shifted + 1
    end
    for i = 1, #(box.handles or {}) do Shift(box.handles[i]) end
    Shift(box._msufMenuTextFocusFrame)
    return shifted
end

-- The zoom/pan API is installed by three small installers sharing one context:
-- ctx.opts (the caller's options), ctx.deps (late-bound by ZoomPan.Configure),
-- ctx.TR (translation through the current deps), the zoom limits and the step list.
local function ZoomPanPathValue(object, path)
    if not object or not path then return nil end
    if type(path) ~= "table" then return object[path] end
    local value = object
    for i = 1, #path do
        value = value and value[path[i]]
    end
    return value
end
local function ZoomPanRound(value)
    return floor((tonumber(value) or 0) + 0.5)
end
local function ExactPanNumber(value)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge or math.abs(value) > 100000 then return nil end
    return ZoomPanRound(value)
end
local function SameOffset(left, right)
    return math.abs((tonumber(left) or 0) - (tonumber(right) or 0)) < 0.01
end

-- Limits, clamping, the readout of the zoom state and the canvas pan.
local function InstallZoomState(ZoomPan, ctx)
    local opts = ctx.opts
    local minZoom, maxZoom = ctx.minZoom, ctx.maxZoom
    ZoomPan.MIN = minZoom
    ZoomPan.MAX = maxZoom
    function ZoomPan.Configure(nextDeps)
        if opts.configureTableOnly then
            if type(nextDeps) == "table" then ctx.deps = nextDeps end
        else
            ctx.deps = nextDeps or ctx.deps or {}
        end
    end
    function ZoomPan.Clamp(value)
        value = tonumber(value) or 1
        if value < minZoom then return minZoom end
        if value > maxZoom then return maxZoom end
        return floor(value * 100 + 0.5) / 100
    end
    function ZoomPan.ResolveDefaultLock(box, fallbackScale)
        if not box or box._msuf2ZoomLockDefaultPending ~= true then return false end
        local initialScale = tonumber(box._manualZoom) or tonumber(fallbackScale)
            or tonumber(box._mockScale) or tonumber(box._mockAutoScale)
        if not initialScale then return false end
        box._manualZoom = ZoomPan.Clamp(initialScale)
        box._msuf2ZoomLockDefaultPending = nil
        -- Remember that this lock is the preview's default, not a user choice:
        -- a layout change may refit a default lock but must keep a user's.
        box._msuf2ZoomLockIsDefault = true
        box._msuf2ZoomLockDefaultDropped = nil
        return true
    end
    function ZoomPan.UpdateControls(box)
        if not box then return end
        local zoom = box._manualZoom
        local scale = tonumber(box._mockScale) or tonumber(zoom) or tonumber(box._mockAutoScale) or 1
        local readout = box[opts.readoutField or "zoomReadout"]
        if readout then
            local pct = floor(scale * 100 + 0.5)
            ctx.deps.T.SetTranslatedText(readout, zoom and string.format("%d%%", pct) or string.format(ctx.TR("Fit %d%%"), pct))
        end
        local fitText = ZoomPanPathValue(box, opts.fitButtonTextPath or { "zoomFitButton", "fs" })
        if fitText then fitText:SetTextColor(zoom and 0.72 or 0.25, zoom and 0.78 or 0.95, zoom and 0.90 or 1.00, 1) end
        -- Previews that opted into the zoom lock mirror the same state on it.
        if box.RefreshZoomLock then box.RefreshZoomLock() end
    end
    -- Canvas pan: apply, read back, set and nudge with exact readback.
    function ZoomPan.ApplyPan(box, panX, panY)
        panX = panX or tonumber(box and box._zoomPanX) or 0
        panY = panY or tonumber(box and box._zoomPanY) or 0
        if opts.panMode == "topLeft" then
            if not (box and box._stage and box._mock and box._mock.GetPoint) then return false end
            local x = (tonumber(box._mockBaseOffsetX) or 0) + panX
            local y = (tonumber(box._mockBaseOffsetY) or 0) + panY
            local oldPoint, oldRelative, oldRelativePoint, oldX, oldY = box._mock:GetPoint(1)
            box._mock:ClearAllPoints()
            box._mock:SetPoint("TOPLEFT", box._stage, "TOPLEFT", x, y)
            if oldPoint == "TOPLEFT" and oldRelative == box._stage and oldRelativePoint == "TOPLEFT" then
                H.ShiftPreviewPanFollowers(box, x - (tonumber(oldX) or 0), y - (tonumber(oldY) or 0))
            end
            local point, relative, relativePoint, actualX, actualY = box._mock:GetPoint(1)
            return point == "TOPLEFT" and relative == box._stage and relativePoint == "TOPLEFT"
                and SameOffset(actualX, x) and SameOffset(actualY, y)
        end
        if not (box and box.canvas and box.mock and box.mock.GetPoint) then return false end
        local expectedX = (tonumber(box._mockBaseOffsetX) or 0) + panX
        local expectedY = (tonumber(box._mockBaseOffsetY) or 0) + panY
        local oldPoint, oldRelative, oldRelativePoint, oldX, oldY = box.mock:GetPoint(1)
        box.mock:ClearAllPoints()
        box.mock:SetPoint("CENTER", box.canvas, "CENTER", expectedX, expectedY)
        if oldPoint == "CENTER" and oldRelative == box.canvas and oldRelativePoint == "CENTER" then
            H.ShiftPreviewPanFollowers(box, expectedX - (tonumber(oldX) or 0), expectedY - (tonumber(oldY) or 0))
        end
        if box._detachedCastPreview and box.mock.cast and box.mock.cast:IsShown() then
            box.mock.cast:ClearAllPoints()
            box.mock.cast:SetPoint("CENTER", box.canvas, "CENTER",
                (tonumber(box._detachedCastBaseOffsetX) or 0) + panX, (tonumber(box._detachedCastBaseOffsetY) or 0) + panY)
        end
        local point, relative, relativePoint, actualX, actualY = box.mock:GetPoint(1)
        return point == "CENTER" and relative == box.canvas and relativePoint == "CENTER"
            and SameOffset(actualX, expectedX) and SameOffset(actualY, expectedY)
    end
    function ZoomPan.GetPan(box)
        if not box then return nil end
        return tonumber(box._zoomPanX) or 0, tonumber(box._zoomPanY) or 0
    end
    function ZoomPan.SetPan(box, x, y)
        if not box then return false, "preview-unavailable" end
        x, y = ExactPanNumber(x), ExactPanNumber(y)
        if x == nil or y == nil then return false, "invalid-pan" end
        local beforeX, beforeY = ZoomPan.GetPan(box)
        if beforeX == x and beforeY == y then return true, beforeX, beforeY, x, y end
        if ZoomPan.ApplyPan(box, x, y) ~= true then
            assert(ZoomPan.ApplyPan(box, beforeX, beforeY) == true, "preview pan rollback failed")
            return false, "pan-readback-mismatch"
        end
        box._zoomPanX, box._zoomPanY = x, y
        return true, beforeX, beforeY, x, y
    end
    function ZoomPan.NudgePan(box, dx, dy)
        dx, dy = ExactPanNumber(dx), ExactPanNumber(dy)
        if dx == nil or dy == nil then return false, "invalid-delta" end
        local beforeX, beforeY = ZoomPan.GetPan(box)
        if beforeX == nil or beforeY == nil then return false, "preview-unavailable" end
        return ZoomPan.SetPan(box, beforeX + dx, beforeY + dy)
    end
end

-- Explicit zoom changes (Fit / 1:1 / lock and the +/- steps) and the canvas drag gesture.
local function InstallZoomActions(ZoomPan, ctx)
    local opts, steps = ctx.opts, ctx.steps
    function ZoomPan.SetZoom(box, zoom, reason)
        if not box then return end
        -- Any explicit Fit/1:1/step/lock action supersedes the one-shot default.
        box._msuf2ZoomLockDefaultPending = nil
        box._msuf2ZoomLockIsDefault, box._msuf2ZoomLockDefaultDropped = nil, nil
        if zoom == nil or zoom == "fit" then
            box._manualZoom = nil
            box._zoomPanX, box._zoomPanY = 0, 0
        else
            box._manualZoom = ZoomPan.Clamp(zoom)
        end
        ZoomPan.UpdateControls(box)
        reason = reason or opts.defaultReason or "UNIT_PREVIEW_ZOOM"
        if type(opts.refresh) == "function" then
            opts.refresh(box, reason, ctx.deps)
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
    -- The canvas drag gesture: its slots live on the surface under the caller's pan prefix.
    local function PanKey(name)
        return tostring(opts.panPrefix or "_msufPreview") .. name
    end
    local PAN_PANNING, PAN_BOX = PanKey("Panning"), PanKey("PanBox")
    local PAN_CURSOR_X, PAN_CURSOR_Y = PanKey("PanCursorX"), PanKey("PanCursorY")
    local PAN_START_X, PAN_START_Y = PanKey("PanStartX"), PanKey("PanStartY")
    local PAN_BUTTON = PanKey("PanButton")
    function ZoomPan.Stop(surface)
        if not surface then return end
        local box = surface[PAN_BOX]
        -- Capture the completed gesture before the pan slots are cleared so a
        -- preview can count real moves (button held AND position changed) and
        -- retire its own onboarding hint.
        local button = surface[PAN_BUTTON]
        local startX, startY = surface[PAN_START_X], surface[PAN_START_Y]
        surface[PAN_PANNING], surface[PAN_BOX], surface[PAN_BUTTON] = nil, nil, nil
        surface[PAN_CURSOR_X], surface[PAN_CURSOR_Y] = nil, nil
        surface[PAN_START_X], surface[PAN_START_Y] = nil, nil
        surface:SetScript("OnUpdate", nil)
        if box and button then
            local moved = (tonumber(box._zoomPanX) or 0) ~= (tonumber(startX) or 0)
                or (tonumber(box._zoomPanY) or 0) ~= (tonumber(startY) or 0)
            -- A dragged canvas is the user's position: the lock keeps it.
            if moved then box._msuf2ZoomLockIsDefault, box._msuf2ZoomLockDefaultDropped = nil, nil end
            if moved and type(box.OnPreviewCanvasMoved) == "function" then box.OnPreviewCanvasMoved(box, button) end
        end
        local update = ctx.deps[opts.updateHintKey or "UpdateHandleHint"]
        if box and type(update) == "function" then update(box, box._selectedHandle) end
    end
    function ZoomPan.Start(surface, box, button, allowPlainLeft)
        if not (surface and box) then return false end
        if surface[PAN_PANNING] then return true end
        local ctrlLeft = button == "LeftButton" and IsControlKeyDown and IsControlKeyDown()
        local backgroundLeft = allowPlainLeft == true and button == "LeftButton"
        if not (backgroundLeft or ctrlLeft or button == "RightButton" or button == "MiddleButton") then return false end
        if not box._manualZoom then
            box._manualZoom = ZoomPan.Clamp(box._mockScale or box._mockAutoScale or 1)
            box._msuf2ZoomLockIsDefault, box._msuf2ZoomLockDefaultDropped = nil, nil
            ZoomPan.UpdateControls(box)
        end
        local cx, cy = GetCursorPosition()
        local uiScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        if uiScale <= 0 then uiScale = 1 end
        surface[PAN_PANNING], surface[PAN_BOX] = true, box
        surface[PAN_BUTTON] = button
        surface[PAN_CURSOR_X], surface[PAN_CURSOR_Y] = (cx or 0) / uiScale, (cy or 0) / uiScale
        surface[PAN_START_X], surface[PAN_START_Y] = tonumber(box._zoomPanX) or 0, tonumber(box._zoomPanY) or 0
        local hint = box[opts.hintField or "hint"]
        if hint then SetShownText(hint, ctx.TR("moving preview canvas - release mouse to stop - Fit recenters")) end
        surface:SetScript("OnUpdate", function(self)
            if not self[PAN_PANNING] then return end
            if IsMouseButtonDown and self[PAN_BUTTON] and not IsMouseButtonDown(self[PAN_BUTTON]) then
                ZoomPan.Stop(self)
                return
            end
            local mx, my = GetCursorPosition()
            local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
            if scale <= 0 then scale = 1 end
            local nextX = ZoomPanRound((self[PAN_START_X] or 0) + ((mx or 0) / scale - (self[PAN_CURSOR_X] or 0)))
            local nextY = ZoomPanRound((self[PAN_START_Y] or 0) + ((my or 0) / scale - (self[PAN_CURSOR_Y] or 0)))
            if box._zoomPanX ~= nextX or box._zoomPanY ~= nextY then
                box._zoomPanX, box._zoomPanY = nextX, nextY
                ZoomPan.ApplyPan(box)
            end
        end)
        return true
    end
end

-- The zoom bar's small buttons (+, -, Fit, 1:1, ?).
local function InstallZoomButton(ZoomPan, ctx)
    local opts = ctx.opts
    function ZoomPan.CreateButton(parent, text, width, tooltip, onClick)
        local T = ctx.deps.T
        local template = (opts.themeButton and T and T.Template and T.Template()) or (opts.buttonTemplate or "BackdropTemplate")
        local btn = PixelLayoutRegion(CreateFrame("Button", nil, parent, template))
        local tex = ctx.deps[opts.buttonTextureKey or "TEX_W8"] or WHITE8X8
        btn:SetSize(width or 24, opts.buttonHeight or 20)
        if btn.SetHitRectInsets then btn:SetHitRectInsets(-2, -2, -2, -2) end
        local useSuperellipse = opts.themeButton and T and T.CreateSuperellipseLayers
        if useSuperellipse then
            local fill, edge = T.CreateSuperellipseLayers(btn, "_msuf2PreviewZoom", 2, "BACKGROUND", "BORDER")
            btn._msuf2PreviewZoomFill = fill
            btn._msuf2PreviewZoomEdge = edge
        elseif btn.SetBackdrop then
            FlatBackdrop(btn, { 0.025, 0.030, 0.045, 0.88 }, { 0.12, 0.16, 0.24, 0.92 }, tex)
        end
        local fontField = opts.buttonFontField or "fs"
        if opts.themeButton and T and T.Font then
            btn[fontField] = T.Font(btn, "GameFontDisableSmall", text, { 0.78, 0.84, 0.96, 1 })
        elseif not opts.themeButton then
            btn[fontField] = PixelLayoutRegion(btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"))
            btn[fontField]:SetText(text)
            btn[fontField]:SetTextColor(0.78, 0.84, 0.96, 1)
            if T and T.StyleFontString then T.StyleFontString(btn[fontField], { 0.78, 0.84, 0.96, 1 }, 0) end
        end
        if btn[fontField] then btn[fontField]:SetPoint("CENTER") end
        btn:SetScript("OnClick", onClick)
        local bgIdle, bgHover, bgDown, brIdle, brHover, brDown = PillPalette(T)
        local bgScratch = { 0, 0, 0, 1 }
        local function ApplyButtonVisual(self, hover, down)
            if useSuperellipse then
                local alpha = (self.IsEnabled and not self:IsEnabled()) and 0.42 or 1
                local bg = down and bgDown or (hover and bgHover or bgIdle)
                local br = down and brDown or (hover and brHover or brIdle)
                PaintPillLayers(T, self._msuf2PreviewZoomFill, self._msuf2PreviewZoomEdge, bg, br, alpha, hover, bgScratch)
                if self[fontField] and self[fontField].SetTextColor then
                    self[fontField]:SetTextColor(hover and 0.88 or 0.78, hover and 0.94 or 0.84, 1.00, alpha)
                end
                return
            end
            local bg = hover and bgHover or bgIdle
            local br = hover and brHover or brIdle
            if self.SetBackdropColor then self:SetBackdropColor(bg[1], bg[2], bg[3], hover and 0.98 or 0.88) end
            if self.SetBackdropBorderColor then self:SetBackdropBorderColor(br[1], br[2], br[3], hover and 1 or 0.92) end
        end
        btn:SetScript("OnMouseDown", function(self)
            self._msuf2PreviewZoomDown = true
            ApplyButtonVisual(self, self._msuf2PreviewZoomHover, true)
        end)
        btn:SetScript("OnMouseUp", function(self)
            self._msuf2PreviewZoomDown = nil
            ApplyButtonVisual(self, self._msuf2PreviewZoomHover, false)
        end)
        btn:SetScript("OnEnter", function(self)
            self._msuf2PreviewZoomHover = true
            ApplyButtonVisual(self, true, self._msuf2PreviewZoomDown)
            if GameTooltip and tooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(ctx.TR(tooltip), 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function(self)
            self._msuf2PreviewZoomHover = nil
            self._msuf2PreviewZoomDown = nil
            ApplyButtonVisual(self, false, false)
            if GameTooltip then GameTooltip:Hide() end
        end)
        btn:SetScript("OnEnable", function(self) ApplyButtonVisual(self, self._msuf2PreviewZoomHover, self._msuf2PreviewZoomDown) end)
        btn:SetScript("OnDisable", function(self) ApplyButtonVisual(self, false, false) end)
        ApplyButtonVisual(btn, false, false)
        return btn
    end
end

function H.InstallZoomPan(ZoomPan, opts)
    if type(ZoomPan) ~= "table" then return end
    opts = opts or {}
    local ctx = {
        opts = opts,
        deps = {},
        minZoom = tonumber(opts.minZoom) or 0.35,
        maxZoom = tonumber(opts.maxZoom) or 4.0,
        steps = opts.steps or { 0.35, 0.50, 0.75, 1.00, 1.25, 1.50, 2.00, 3.00, 4.00 },
    }
    function ctx.TR(text)
        local fn = ctx.deps.TR
        return (type(fn) == "function" and fn(text)) or text
    end
    InstallZoomState(ZoomPan, ctx)
    InstallZoomActions(ZoomPan, ctx)
    InstallZoomButton(ZoomPan, ctx)
end

-- Interactive preview children (handles, zoom buttons, drag catchers) sit
-- above the canvas and can become the wheel target themselves. Bind them to
-- the same semantic route so Ctrl+wheel still zooms while an ordinary wheel
-- tick always reaches the page ScrollFrame exactly once.
function H.BindPreviewWheel(frame, box, wheelHandler)
    if not (frame and frame.EnableMouseWheel and frame.SetScript) then return false end
    wheelHandler = wheelHandler or (box and box._msuf2PreviewZoomWheel)
    if type(wheelHandler) ~= "function" then return false end
    frame:EnableMouseWheel(true)
    if frame.SetPropagateMouseWheel then frame:SetPropagateMouseWheel(false) end
    frame:SetScript("OnMouseWheel", wheelHandler)
    return true
end

function H.BuildZoomBar(box, surface, opts)
    if not (box and surface) then return nil end
    opts = opts or {}
    local tr = opts.Tr or Fallbacks.Identity
    local tex = opts.texture or "Interface\\Buttons\\WHITE8X8"
    local template = opts.template or "BackdropTemplate"
    local stepZoom = opts.StepZoom or Fallbacks.Noop
    local setZoom = opts.SetZoom or Fallbacks.Noop
    local panEnabled = type(opts.StartPan) == "function"
    local startPan = opts.StartPan or Fallbacks.False
    local stopPan = opts.StopPan or Fallbacks.Noop
    local buttonH = tonumber(opts.buttonHeight) or 20
    local createButton = opts.CreateZoomButton
    local prefix = opts.fieldPrefix or ""
    local zoomBar = PixelLayoutRegion(CreateFrame("Frame", nil, surface, template))
    zoomBar:SetSize(opts.width or (opts.lockButton and 226 or 200), opts.height or 24)
    zoomBar:SetPoint("TOPRIGHT", surface, "TOPRIGHT", -8, -8)
    if opts.flatChrome ~= false and (opts.T or opts.flatChrome == true) then
        FlatBackdrop(zoomBar, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, tex)
    else
        FlatBackdrop(zoomBar, { 0.015, 0.018, 0.030, 0.86 }, { 0.10, 0.14, 0.22, 0.92 }, tex)
    end
    if zoomBar.SetFrameLevel then zoomBar:SetFrameLevel((surface.GetFrameLevel and surface:GetFrameLevel() or 0) + 80) end
    zoomBar:EnableMouse(true)
    zoomBar:EnableMouseWheel(true)
    if surface.SetPropagateMouseWheel then surface:SetPropagateMouseWheel(false) end
    if zoomBar.SetPropagateMouseWheel then zoomBar:SetPropagateMouseWheel(false) end
    box[prefix .. "zoomBar"] = zoomBar
    local function AddZoomButton(field, text, width, tooltip, onClick, relativeTo, offset)
        local btn = createButton(zoomBar, text, width, tooltip, onClick)
        if relativeTo then
            btn:SetPoint("LEFT", relativeTo, "RIGHT", offset or 3, 0)
        else
            btn:SetPoint("LEFT", zoomBar, "LEFT", offset or 3, 0)
        end
        box[prefix .. field] = btn
        return btn
    end
    zoomBar:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tr("Preview zoom"), 1, 1, 1)
            GameTooltip:AddLine(tr("Use the buttons or Ctrl + mouse wheel to zoom."), 0.82, 0.82, 0.82, true)
            if panEnabled then
                GameTooltip:AddLine(tr("Drag empty preview space to move the canvas. Fit recenters it."), 0.55, 0.68, 0.86, true)
            else
                GameTooltip:AddLine(tr("Fit shows the complete preview; 1:1 shows its configured pixel size."), 0.55, 0.68, 0.86, true)
            end
            GameTooltip:AddLine(tr("Use ? for all preview controls."), 0.50, 0.78, 0.92, true)
            GameTooltip:Show()
        end
    end)
    zoomBar:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    local zoomOut = AddZoomButton("zoomOutButton", "-", 20, "Zoom out", function() stepZoom(box, -1) end)
    local T = opts.T
    local readout
    if opts.themeReadout and T and T.Font then
        readout = T.Font(zoomBar, "GameFontDisableSmall", "", { 0.72, 0.78, 0.90, 1 })
    else
        readout = PixelLayoutRegion(zoomBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"))
        readout:SetTextColor(0.72, 0.78, 0.90, 1)
        if T and T.StyleFontString then T.StyleFontString(readout, { 0.72, 0.78, 0.90, 1 }, 0) end
    end
    readout:SetPoint("LEFT", zoomOut, "RIGHT", 3, 0)
    readout:SetSize(54, buttonH)
    readout:SetJustifyH("CENTER")
    box[prefix .. "zoomReadout"] = readout
    local zoomIn = AddZoomButton("zoomInButton", "+", 20, "Zoom in", function() stepZoom(box, 1) end, readout)
    local fitButton = AddZoomButton("zoomFitButton", "Fit", 30, "Fit preview", function() setZoom(box, nil, opts.fitReason) end, zoomIn)
    local oneButton = AddZoomButton("zoomOneButton", "1:1", 32, "Pixel preview", function() setZoom(box, 1, opts.oneReason) end, fitButton)
    local helpButton = AddZoomButton("zoomHelpButton", "?", 20, "Preview controls", function(self)
        H.ShowPreviewControlsHelp(self, {
            M = opts.M or M, T = opts.T, W = opts.W, Tr = tr,
            title = opts.helpTitle, lines = opts.helpLines,
        })
    end, oneButton)
    if opts.lockButton then
        local lock = H.EnsureZoomLockButton(box, zoomBar, {
            T = opts.T, Tr = tr, SetZoom = setZoom, buttonHeight = buttonH,
            lockReason = opts.lockReason, unlockReason = opts.unlockReason,
            defaultLocked = opts.defaultLocked,
        })
        if lock then lock:SetPoint("LEFT", helpButton, "RIGHT", 3, 0) end
    end
    local function ZoomWheel(self, delta)
        local dir = (delta or 0) > 0 and 1 or -1
        -- Route the event explicitly. Toggling propagation from inside the
        -- wheel handler is timing-dependent in WoW and could swallow the first
        -- normal wheel tick after preview zooming.
        if self.SetPropagateMouseWheel then self:SetPropagateMouseWheel(false) end
        if IsControlKeyDown and IsControlKeyDown() then
            stepZoom(box, dir)
        else
            local menu = opts.M or M
            local forward = menu and menu.ForwardMenuScrollWheel
            if type(forward) == "function" then
                forward(delta)
            else
                local main = menu and menu.scrollFrame
                local handler = main and main.GetScript and main:GetScript("OnMouseWheel")
                if type(handler) == "function" then handler(main, delta) end
            end
        end
    end
    box._msuf2PreviewZoomWheel = ZoomWheel
    if opts.wheelField then box[opts.wheelField] = ZoomWheel end
    local wheelTargets = { surface, zoomBar, zoomOut, fitButton, oneButton, zoomIn, helpButton, box[prefix .. "zoomLockButton"] }
    for i = 1, 8 do H.BindPreviewWheel(wheelTargets[i], box, ZoomWheel) end
    local backgroundButton = H.EnsurePreviewBackgroundButton(box, zoomBar, opts)
    H.BindPreviewWheel(backgroundButton, box, ZoomWheel)
    if panEnabled then
        if surface.RegisterForDrag then surface:RegisterForDrag("LeftButton") end
        surface:SetScript("OnMouseDown", function(self, button) startPan(self, box, button, true) end)
        surface:SetScript("OnMouseUp", stopPan)
        surface:SetScript("OnDragStart", function(self, button) startPan(self, box, button, true) end)
        surface:SetScript("OnDragStop", stopPan)
        surface:SetScript("OnHide", stopPan)
    end
    return zoomBar, ZoomWheel
end

-- One logical zoom setting owns the +/-/Fit/1:1 button cluster.  The buttons
-- remain available as explicit actions, while this command supplies natural
-- relative changes ("zoom in", "more", "less") with exact readback.
function H.BuildZoomCommand(box, zoomPan, reason)
    if not (box and type(zoomPan) == "table" and type(zoomPan.SetZoom) == "function") then return nil end
    local minZoom = tonumber(zoomPan.MIN) or 0.35
    local maxZoom = tonumber(zoomPan.MAX) or 4.0
    return {
        kind = "slider",
        historyMode = "none",
        min = floor(minZoom * 100 + 0.5),
        max = floor(maxZoom * 100 + 0.5),
        step = 25,
        percentIsValue = true,
        get = function()
            local scale = tonumber(box._manualZoom) or tonumber(box._mockScale)
                or tonumber(box._mockAutoScale) or 1
            return floor(scale * 100 + 0.5)
        end,
        set = function(value)
            value = tonumber(value)
            if not value then return false end
            zoomPan.SetZoom(box, value / 100, reason or "SEARCH_PREVIEW_ZOOM")
            local scale = tonumber(box._manualZoom) or tonumber(box._mockScale)
                or tonumber(box._mockAutoScale) or 1
            return floor(scale * 100 + 0.5) == floor(value + 0.5)
        end,
    }
end
function H.BuildPanCommand(box, zoomPan, nudge, metadata)
    if not (box and type(zoomPan) == "table" and type(zoomPan.GetPan) == "function") then return nil end
    metadata = type(metadata) == "table" and metadata or {}
    local function ParseDelta(value)
        if type(value) == "table" then
            return tonumber(value.dx or value.x or value[1]), tonumber(value.dy or value.y or value[2])
        end
        if type(value) == "string" then
            local x, y = value:match("^%s*([%+%-]?%d+%.?%d*)%s*[,;/ ]%s*([%+%-]?%d+%.?%d*)%s*$")
            return tonumber(x), tonumber(y)
        end
        return nil
    end
    local command = {
        kind = "button",
        historyMode = "none",
        skipNavigation = true,
        previewSurface = metadata.previewSurface,
        previewUnitKey = metadata.previewUnitKey,
        interaction = "preview.canvas.pan",
        get = function()
            local x, y = zoomPan.GetPan(box)
            return { x = x, y = y }
        end,
        set = function(value)
            local dx, dy = ParseDelta(value)
            if dx == nil or dy == nil then return false end
            if type(nudge) == "function" then return nudge(dx, dy) end
            if type(zoomPan.NudgePan) ~= "function" then return false end
            return zoomPan.NudgePan(box, dx, dy)
        end,
    }
    return command
end
