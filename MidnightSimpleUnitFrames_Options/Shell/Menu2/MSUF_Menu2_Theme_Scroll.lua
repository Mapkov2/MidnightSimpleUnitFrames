local _, MSUF = ...
local M = MSUF.MSUF2
local T = M.Theme
local FILE = "Shell/Menu2/MSUF_Menu2_Theme_Scroll.lua"
local PixelLayoutLeaf = MSUF.Require("PreparePixelLayoutLeaf", FILE, MSUF.Util)
local canaccessvalue, issecretvalue = canaccessvalue, issecretvalue
local ApplyTextureGradient = T.ApplyTextureGradient

local function AccessibleNumber(value, fallback)
    fallback = tonumber(fallback) or 0
    if type(canaccessvalue) == "function" and canaccessvalue(value) ~= true then return fallback end
    if type(issecretvalue) == "function" and issecretvalue(value) == true then return fallback end
    return tonumber(value) or fallback
end
M.AccessibleNumber = AccessibleNumber
local function PixelBarTexture(texture)
    if not texture then return texture end
    texture:SetTexture("Interface\\Buttons\\WHITE8X8")
    if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(true) end
    if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
    return texture
end
-- Styled ScrollFrame machinery. Each helper takes the ScrollFrame; the bar, its
-- parts and the original SetVerticalScroll hang off the frame (scroll._msuf2ScrollBar,
-- bar._msuf2Track/_msuf2TrackEdge/_msuf2Thumb, scroll._msuf2RawSetVerticalScroll).
local Scroll = { SPEED = 14, MAX_ELAPSED = 0.050, EPSILON = 0.45 }
function Scroll.Clamp(value, maxValue)
    value = AccessibleNumber(value, 0)
    maxValue = AccessibleNumber(maxValue, 0)
    if value < 0 then return 0 end
    if value > maxValue then return maxValue end
    return value
end
-- The smooth-scroll frame, the drag and the refresh hooks run often, so the
-- current offset and the maximum are read inline there instead of through a
-- helper; each update makes the same calls as the closure-based original.
function Scroll.CurrentMax(scroll)
    local maxScroll = scroll._msuf2MaxScroll
    if maxScroll == nil then
        local child = scroll.GetScrollChild and scroll:GetScrollChild()
        local childH = (child and child.GetHeight and child:GetHeight()) or 0
        local frameH = (scroll.GetHeight and scroll:GetHeight()) or 0
        maxScroll = math.max(0, childH - frameH)
    end
    return maxScroll
end
function Scroll.PaintTrack(track, alpha)
    local surface, shadow = T.colors.coreSurface, T.colors.coreShadow
    ApplyTextureGradient(track, "VERTICAL",
        { surface[1], surface[2], surface[3], alpha }, { shadow[1], shadow[2], shadow[3], alpha }, true)
end
function Scroll.PaintBar(bar, hover)
    local alpha = (bar.IsShown and bar:IsShown()) and 1 or 0
    local surface, shadow = T.colors.coreSurface, T.colors.coreShadow
    local trackAlpha = (hover and 0.98 or 0.82) * alpha
    ApplyTextureGradient(bar._msuf2Track, "VERTICAL",
        { surface[1], surface[2], surface[3], trackAlpha }, { shadow[1], shadow[2], shadow[3], trackAlpha }, true)
    local soft = T.colors.borderSoft
    bar._msuf2TrackEdge:SetColorTexture(soft[1], soft[2], soft[3], (hover and 0.62 or 0.38) * alpha)
    local thumb = bar._msuf2Thumb
    if thumb.SetColorTexture then
        local c = hover and bar._msuf2ThumbHover or bar._msuf2ThumbBase
        local a = (hover and 0.90 or 0.68) * alpha
        ApplyTextureGradient(thumb, "VERTICAL",
            { math.min(c[1] * 1.22, 1), math.min(c[2] * 1.18, 1), math.min(c[3] * 1.12, 1), a },
            { c[1] * 0.72, c[2] * 0.78, c[3] * 0.86, a }, true)
    end
end
function Scroll.UpdateThumb(bar, offset, maxScroll)
    local thumb = bar._msuf2Thumb
    maxScroll = math.max(0, AccessibleNumber(maxScroll, 0))
    offset = Scroll.Clamp(offset, maxScroll)
    local barH = (bar.GetHeight and bar:GetHeight()) or 0
    local thumbH = (thumb.GetHeight and thumb:GetHeight()) or 0
    local travel = math.max(0, barH - thumbH)
    local y = maxScroll > 0 and -(offset / maxScroll) * travel or 0
    if thumb._msuf2LastY ~= y then
        thumb._msuf2LastY = y
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", bar, "TOP", 0, y)
    end
end
function Scroll.SetRaw(scroll, offset, current, maxScroll)
    local bar = scroll._msuf2ScrollBar
    local rawSet = scroll._msuf2RawSetVerticalScroll
    if maxScroll == nil then maxScroll = Scroll.CurrentMax(scroll) end
    offset = Scroll.Clamp(offset, maxScroll)
    if current == nil then current = (scroll.GetVerticalScroll and scroll:GetVerticalScroll()) or 0 end
    current = AccessibleNumber(current, 0)
    if rawSet and math.abs(offset - current) > 0.01 then rawSet(scroll, offset) end
    bar._msuf2LastScrollValue = offset
    Scroll.UpdateThumb(bar, offset, maxScroll)
    return offset
end
function Scroll.StopSmooth(scroll)
    scroll._msuf2SmoothScrollTarget = nil
    local driver = scroll._msuf2SmoothScrollDriver
    if driver then driver:Hide() end
end
function Scroll.SmoothOnUpdate(driver, elapsed)
    local scroll = driver._msuf2ScrollOwner
    local target = scroll._msuf2SmoothScrollTarget
    if target == nil then
        Scroll.StopSmooth(scroll)
        return
    end
    local maxScroll = Scroll.CurrentMax(scroll)
    target = Scroll.Clamp(target, maxScroll)
    scroll._msuf2SmoothScrollTarget = target
    local current = AccessibleNumber((scroll.GetVerticalScroll and scroll:GetVerticalScroll()) or 0, 0)
    local delta = target - current
    if (T.ReducedMotionEnabled(true)) or math.abs(delta) <= Scroll.EPSILON then
        Scroll.SetRaw(scroll, target, current, maxScroll)
        Scroll.StopSmooth(scroll)
        return
    end
    elapsed = tonumber(elapsed) or 0
    if elapsed > Scroll.MAX_ELAPSED then elapsed = Scroll.MAX_ELAPSED end
    local blend = math.min(1, elapsed * Scroll.SPEED)
    if blend <= 0 then return end
    Scroll.SetRaw(scroll, current + delta * blend, current, maxScroll)
end
function Scroll.EnsureDriver(scroll)
    local driver = scroll._msuf2SmoothScrollDriver
    if driver then return driver end
    driver = PixelLayoutLeaf(CreateFrame("Frame", nil, scroll))
    driver:Hide()
    driver._msuf2ScrollOwner = scroll
    driver:SetScript("OnUpdate", Scroll.SmoothOnUpdate)
    scroll._msuf2SmoothScrollDriver = driver
    return driver
end
function Scroll.SmoothTo(scroll, offset)
    local maxScroll = Scroll.CurrentMax(scroll)
    local target = Scroll.Clamp(offset, maxScroll)
    if T.ReducedMotionEnabled(true) then
        Scroll.SetRaw(scroll, target, nil, maxScroll)
        Scroll.StopSmooth(scroll)
        return
    end
    local current = AccessibleNumber((scroll.GetVerticalScroll and scroll:GetVerticalScroll()) or 0, 0)
    if math.abs(target - current) <= Scroll.EPSILON then
        Scroll.SetRaw(scroll, target, current, maxScroll)
        Scroll.StopSmooth(scroll)
        return
    end
    scroll._msuf2SmoothScrollTarget = target
    Scroll.EnsureDriver(scroll):Show()
end
function Scroll.Refresh(scroll)
    local bar = scroll._msuf2ScrollBar
    local thumb = bar._msuf2Thumb
    local rawSet = scroll._msuf2RawSetVerticalScroll
    if scroll.IsShown and not scroll:IsShown() then
        Scroll.StopSmooth(scroll)
        if bar.Hide and bar:IsShown() then bar:Hide() end
        return
    end
    local child = scroll.GetScrollChild and scroll:GetScrollChild()
    local childH = (child and child.GetHeight and child:GetHeight()) or 0
    local frameH = (scroll.GetHeight and scroll:GetHeight()) or 0
    local maxScroll = math.max(0, childH - frameH)
    scroll._msuf2MaxScroll = maxScroll
    if scroll._msuf2SmoothScrollTarget ~= nil then scroll._msuf2SmoothScrollTarget = Scroll.Clamp(scroll._msuf2SmoothScrollTarget, maxScroll) end
    if maxScroll <= 1 or frameH <= 0 then
        Scroll.StopSmooth(scroll)
        local current = AccessibleNumber(scroll:GetVerticalScroll() or 0, 0)
        if rawSet and current ~= 0 then rawSet(scroll, 0) end
        bar._msuf2LastScrollValue = 0
        Scroll.UpdateThumb(bar, 0, 0)
        if bar.Hide and bar:IsShown() then bar:Hide() end
        return
    end
    if bar.Show and not bar:IsShown() then bar:Show() end
    bar._msuf2LastMaxScroll = maxScroll
    local visibleRatio = frameH / math.max(childH, 1)
    local barH = (bar.GetHeight and bar:GetHeight()) or frameH
    local thumbH = math.floor(math.max(34, math.min(barH, barH * visibleRatio)) + 0.5)
    if thumb.SetHeight and thumb._msuf2LastHeight ~= thumbH then
        thumb._msuf2LastHeight = thumbH
        thumb:SetHeight(thumbH)
        thumb._msuf2LastY = nil
    end
    local current = AccessibleNumber(scroll:GetVerticalScroll() or 0, 0)
    local offset = Scroll.Clamp(current, maxScroll)
    if offset ~= current and rawSet then rawSet(scroll, offset) end
    bar._msuf2LastScrollValue = offset
    Scroll.UpdateThumb(bar, offset, maxScroll)
    Scroll.PaintBar(bar, bar._msuf2Hover)
end
function Scroll.SetVerticalScroll(self, offset)
    Scroll.StopSmooth(self)
    local maxScroll = self._msuf2MaxScroll
    if maxScroll == nil then
        local child = self.GetScrollChild and self:GetScrollChild()
        local childH = (child and child.GetHeight and child:GetHeight()) or 0
        local frameH = (self.GetHeight and self:GetHeight()) or 0
        maxScroll = math.max(0, childH - frameH)
    end
    local clamped = Scroll.Clamp(offset, maxScroll)
    local current = AccessibleNumber((self.GetVerticalScroll and self:GetVerticalScroll()) or 0, 0)
    if math.abs(clamped - current) > 0.01 then self._msuf2RawSetVerticalScroll(self, clamped) end
    if self._msuf2RefreshScrollBar then self:_msuf2RefreshScrollBar() end
end
-- The wheel step of one styled ScrollFrame, built once when it is styled, so
-- the wheel forwarder and the OnMouseWheel scripts reach it in a single hop.
function Scroll.WheelStepper(scroll)
    return function(delta)
        if not delta or delta == 0 then return end
        local step = 64
        if IsShiftKeyDown and IsShiftKeyDown() then step = 180 end
        if IsControlKeyDown and IsControlKeyDown() then step = math.max(step, (scroll.GetHeight and scroll:GetHeight()) or step) end
        local current = AccessibleNumber(scroll:GetVerticalScroll() or 0, 0)
        Scroll.SmoothTo(scroll, (scroll._msuf2SmoothScrollTarget or current) - delta * step)
    end
end
function Scroll.CursorY(bar)
    if type(GetCursorPosition) ~= "function" then return nil end
    local _, y = GetCursorPosition()
    local scale = (bar.GetEffectiveScale and bar:GetEffectiveScale()) or 1
    scale = AccessibleNumber(scale, 1)
    if scale <= 0 then scale = 1 end
    return AccessibleNumber(y, 0) / scale
end
function Scroll.StopDrag(bar)
    bar._msuf2DragStartY = nil
    bar._msuf2DragStartOffset = nil
    bar:SetScript("OnUpdate", nil)
end
function Scroll.Drag(bar)
    if type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then
        Scroll.StopDrag(bar)
        return
    end
    local startY = bar._msuf2DragStartY
    local cursorY = Scroll.CursorY(bar)
    if startY == nil or cursorY == nil then return end
    local scroll = bar._msuf2ScrollOwner
    local maxScroll = Scroll.CurrentMax(scroll)
    local thumb = bar._msuf2Thumb
    local barH = (bar.GetHeight and bar:GetHeight()) or 0
    local thumbH = (thumb.GetHeight and thumb:GetHeight()) or 0
    local travel = math.max(1, barH - thumbH)
    local startOffset = Scroll.Clamp(bar._msuf2DragStartOffset, maxScroll)
    Scroll.SetRaw(scroll, startOffset - (cursorY - startY) * (maxScroll / travel), nil, maxScroll)
end
function Scroll.BarMouseDown(bar, button)
    if button and button ~= "LeftButton" then return end
    local scroll = bar._msuf2ScrollOwner
    Scroll.StopSmooth(scroll)
    bar._msuf2DragStartY = Scroll.CursorY(bar)
    bar._msuf2DragStartOffset = AccessibleNumber((scroll.GetVerticalScroll and scroll:GetVerticalScroll()) or 0, 0)
    if bar._msuf2DragStartY ~= nil then bar:SetScript("OnUpdate", Scroll.Drag) end
end
function Scroll.BarEnter(bar)
    bar._msuf2Hover = true
    Scroll.PaintBar(bar, true)
end
function Scroll.BarLeave(bar)
    bar._msuf2Hover = nil
    Scroll.PaintBar(bar, false)
end
function Scroll.BarShow(bar)
    Scroll.PaintBar(bar, bar._msuf2Hover)
end
function Scroll.OnHide(scroll)
    local bar = scroll._msuf2ScrollBar
    Scroll.StopSmooth(scroll)
    Scroll.StopDrag(bar)
    if bar.Hide then bar:Hide() end
end
function T.StyleScrollFrame(scroll, anchor)
    if not scroll or scroll._msuf2ScrollStyled then return scroll and scroll._msuf2ScrollBar end
    scroll._msuf2ScrollStyled = true
    local parent = anchor or (scroll.GetParent and scroll:GetParent()) or scroll
    local bar = PixelLayoutLeaf(CreateFrame("Frame", nil, parent))
    -- Keep a generous mouse target while the visible rail stays compact.
    bar:SetWidth(14)
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 5, -8)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 5, 8)
    if bar.EnableMouse then bar:EnableMouse(true) end
    if bar.SetFrameLevel and scroll.GetFrameLevel then bar:SetFrameLevel(scroll:GetFrameLevel() + 8) end
    local track = PixelBarTexture(PixelLayoutLeaf(bar:CreateTexture(nil, "BACKGROUND")))
    track:SetPoint("TOP", bar, "TOP", 0, 0)
    track:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    track:SetWidth(2)
    Scroll.PaintTrack(track, 0.82)
    bar._msuf2Track = track
    local trackEdge = PixelBarTexture(PixelLayoutLeaf(bar:CreateTexture(nil, "BORDER")))
    trackEdge:SetPoint("TOPLEFT", track, "TOPRIGHT", 1, 0)
    trackEdge:SetPoint("BOTTOMLEFT", track, "BOTTOMRIGHT", 1, 0)
    trackEdge:SetWidth(1)
    trackEdge:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.38)
    bar._msuf2TrackEdge = trackEdge
    local thumbBase = T.colors.coreRim
    local thumb = PixelBarTexture(PixelLayoutLeaf(bar:CreateTexture(nil, "OVERLAY")))
    thumb:SetSize(5, 42)
    ApplyTextureGradient(thumb, "VERTICAL",
        { thumbBase[1] * 1.22, thumbBase[2] * 1.18, thumbBase[3] * 1.12, 0.72 },
        { thumbBase[1] * 0.72, thumbBase[2] * 0.78, thumbBase[3] * 0.86, 0.72 }, true)
    bar._msuf2Thumb = thumb
    bar._msuf2ThumbBase, bar._msuf2ThumbHover = thumbBase, T.colors.coreRaised
    bar._msuf2ScrollOwner = scroll
    scroll._msuf2ScrollBar = bar
    scroll._msuf2RawSetVerticalScroll = scroll.SetVerticalScroll
    scroll._msuf2RefreshScrollBar = Scroll.Refresh
    scroll.SetVerticalScroll = Scroll.SetVerticalScroll
    -- Fixed page headers are siblings of this ScrollFrame. Expose the exact
    -- styled wheel path so their chrome and interactive preview shells can
    -- forward ordinary wheel input without depending on frame propagation.
    local scrollBy = Scroll.WheelStepper(scroll)
    scroll._msuf2ScrollByWheel = scrollBy
    local onWheel = function(_, delta) scrollBy(delta) end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", onWheel)
    local wheelChild = scroll.GetScrollChild and scroll:GetScrollChild()
    if wheelChild and wheelChild.EnableMouseWheel then
        wheelChild:EnableMouseWheel(true)
        wheelChild:SetScript("OnMouseWheel", onWheel)
    end
    bar:EnableMouseWheel(true)
    bar:SetScript("OnMouseWheel", onWheel)
    bar:SetScript("OnEnter", Scroll.BarEnter)
    bar:SetScript("OnLeave", Scroll.BarLeave)
    bar:SetScript("OnMouseDown", Scroll.BarMouseDown)
    bar:SetScript("OnMouseUp", Scroll.StopDrag)
    scroll:HookScript("OnScrollRangeChanged", Scroll.Refresh)
    scroll:HookScript("OnSizeChanged", Scroll.Refresh)
    scroll:HookScript("OnHide", Scroll.OnHide)
    scroll:HookScript("OnShow", Scroll.Refresh)
    if bar.HookScript then
        bar:HookScript("OnHide", Scroll.StopDrag)
        bar:HookScript("OnShow", Scroll.BarShow)
    end
    Scroll.Refresh(scroll)
    return bar
end

T.PixelBarTexture = PixelBarTexture
