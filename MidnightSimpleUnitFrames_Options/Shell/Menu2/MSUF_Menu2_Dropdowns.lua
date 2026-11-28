local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local FILE = "Shell/Menu2/MSUF_Menu2_Dropdowns.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
local IS_FOREVER = MSUF.Client.IsForever == true
local T = M.Theme
local W = M.Widgets or {}
M.Widgets = W

-- Menu2 dropdown implementation.
-- Owns the shared popup frame, searchable row rendering, and search registration for dropdown
-- controls. Page modules should create dropdowns here rather than duplicating popup logic.
local floor = math.floor
local max = math.max
local min = math.min
local SetFontChecked = MSUF.Require("MSUF_SetFontChecked", FILE)
local SetIconTexture = MSUF.Require("MSUF_SetIconTexture", FILE)
local ResolveStatusbarTextureKey = MSUF.Optional("MSUF_ResolveStatusbarTextureKey")
local ResolveSafeFontPath = MSUF.Require("MSUF_ResolveSafeFontPath", FILE)
local ResolveFontKeyPath = MSUF.Require("MSUF_ResolveFontKeyPath", FILE)
local Tr = M.TranslateText

local function SetSearchText(object, text)
    if object and text ~= nil then object._msuf2SearchText = text end
    return object
end
local RegisterSearchObject = W.RegisterSearchObject
local function NextRow(section, height)
    local x = section._msuf2ContentX or 14
    local y = section._msuf2CursorY or -38
    section._msuf2CursorY = y - (height or 46)
    return x, y
end
local dropdownFrame, dropdownScroll, dropdownChild, dropdownOwner, dropdownSlider
local dropdownClosing, dropdownClosingOwner
local dropdownRows = {}
local dropdownSearch
-- Forever's Gamepad UI: the open list takes the pad from the menu window
-- (Game/Forever/PadNavigation.lua) and starts on the chosen row; B closes it
-- through SmartNavigationCloseHandler and the window gets its selection back.
local function ShowForeverDropdown(selectedRow)
    local navigation = IS_FOREVER and MSUF.PadNavigation
    if not (navigation and dropdownFrame) then return end
    navigation.Attach(dropdownFrame)
    navigation.Activate(dropdownFrame, selectedRow)
end
-- One popup instance is reused for all dropdowns. This keeps strata/focus behavior predictable
-- and avoids leaking row frames as pages are rebuilt.
-- Field and choice text use the "control" type role, the same size as checkbox
-- labels. Keep the two-unit gap at the end of the reserved 48-unit row.
local DROPDOWN_FIELD_H = 26
local DROPDOWN_FIELD_OFFSET = 20
local DROPDOWN_FIELD_TEXT_LEFT = 12
local DROPDOWN_FIELD_TEXT_RIGHT = -32
local DROPDOWN_CHEVRON_RIGHT = -10
local DROPDOWN_ROW_H = 26
local DROPDOWN_SEARCH_H = 36
local DROPDOWN_ICON_SIZE = 20
local DROPDOWN_ICON_LEFT = 12
local DROPDOWN_ICON_TEXT_LEFT = 40
local DROPDOWN_SWATCH_TEXT_LEFT = 36
local DROPDOWN_TEXTURE_PREVIEW_W = 72
local DROPDOWN_TEXTURE_PREVIEW_H = 12
local DROPDOWN_TEXTURE_TEXT_LEFT = 94
W.DROPDOWN_FIELD_H = DROPDOWN_FIELD_H
W.DROPDOWN_FIELD_OFFSET = DROPDOWN_FIELD_OFFSET
local DROPDOWN_BAR_PREVIEW_W = 132
local DROPDOWN_BAR_PREVIEW_H = 8
local DROPDOWN_BAR_PREVIEW_RIGHT = 24
local DROPDOWN_BAR_PREVIEW_LABEL_GAP = 22
local DROPDOWN_BAR_PREVIEW_ROW_H = 38
local DROPDOWN_ABSORB_EDGE_TEXTURE = "Interface\\RaidFrame\\Shield-Overshield"
local DROPDOWN_SCROLLBAR_W = 12
local DROPDOWN_POSITION_INTERVAL = 0.10
local DROPDOWN_SMOOTH_SCROLL_SPEED = 14
local DROPDOWN_SMOOTH_SCROLL_MAX_ELAPSED = 0.050
local DROPDOWN_SMOOTH_SCROLL_EPSILON = 0.45
local dropdownActiveRowHeight = DROPDOWN_ROW_H
local CloseDropdown, HideDropdownItemTooltip, FocusDropdownRow, DropdownKeyDown
local IsDescendantOf
local PixelBarTexture = T.PixelBarTexture
local function PaintDropdownScrollbar(hover)
    local bar = dropdownSlider
    if not bar then return end
    local shown = bar.IsShown and bar:IsShown()
    local alpha = shown and 1 or 0
    local track = bar._msuf2Track
    local edge = bar._msuf2TrackEdge
    local thumb = bar._msuf2Thumb
    local soft = T.colors.borderSoft or T.colors.border or { 0.12, 0.14, 0.26 }
    local thumbBase = bar._msuf2ThumbBase or T.colors.coreRim or { 0.043, 0.096, 0.150 }
    local thumbHover = bar._msuf2ThumbHover or T.colors.coreRaised or { 0.026, 0.070, 0.110 }
    if track then
        local a = (hover and 0.98 or 0.82) * alpha
        if T.ApplyTextureGradient then
            local top = T.colors.coreSurface or { 0.014, 0.038, 0.072 }
            local bottom = T.colors.coreShadow or { 0.006, 0.016, 0.032 }
            T.ApplyTextureGradient(track, "VERTICAL", { top[1], top[2], top[3], a }, { bottom[1], bottom[2], bottom[3], a }, true)
        elseif track.SetColorTexture then
            local c = T.colors.coreShadow or { 0.006, 0.016, 0.032 }
            track:SetColorTexture(c[1], c[2], c[3], a)
        end
    end
    if edge and edge.SetColorTexture then edge:SetColorTexture(soft[1], soft[2], soft[3], (hover and 0.62 or 0.38) * alpha) end
    if thumb then
        local c = hover and thumbHover or thumbBase
        local a = (hover and 0.90 or 0.68) * alpha
        if T.ApplyTextureGradient then
            T.ApplyTextureGradient(thumb, "VERTICAL", { min(c[1] * 1.22, 1), min(c[2] * 1.18, 1), min(c[3] * 1.12, 1), a },
                { c[1] * 0.72, c[2] * 0.78, c[3] * 0.86, a }, true)
        elseif thumb.SetColorTexture then
            thumb:SetColorTexture(c[1], c[2], c[3], a)
        end
    end
end
local function SetDropdownOwnerMouseWheel(owner, enabled)
    if owner and owner._msuf2DropdownWheelManaged and owner.EnableMouseWheel then owner:EnableMouseWheel(enabled and true or false) end
end
local function IsDropdownClosingFor(owner)
    return dropdownClosing
        and owner ~= nil
        and dropdownClosingOwner == owner
        and dropdownFrame
        and dropdownFrame.IsShown
        and dropdownFrame:IsShown()
end
local function PlayMotion(frame, motion, opts)
    if T.PlayMotion then
        T.PlayMotion(frame, motion, opts)
    else
        opts = opts or {}
        local toAlpha = opts.toAlpha
        if toAlpha == nil then toAlpha = (motion == "dropdownOut") and 0 or 1 end
        if frame and frame.SetAlpha then frame:SetAlpha(toAlpha) end
        if type(opts.onFinished) == "function" then opts.onFinished(frame) end
    end
end
local function ShowDropdownFocus(owner)
    if M.ShowFocusVeil then M.ShowFocusVeil(owner, "dropdown", { referenceFrame = dropdownFrame }) end
end
local function HideDropdownFocus(animated)
    if M.HideFocusVeil then M.HideFocusVeil("dropdown", { animated = animated ~= false }) end
end
local function DropdownMaxScroll()
    if not (dropdownScroll and dropdownChild) then return 0 end
    return math.max(0, (dropdownChild:GetHeight() or 0) - (dropdownScroll:GetHeight() or 0))
end
local function ClampDropdownScroll(value)
    local maxScroll = DropdownMaxScroll()
    value = tonumber(value) or 0
    if value < 0 then value = 0 elseif value > maxScroll then value = maxScroll end
    return value, maxScroll
end
local function ApplyDropdownScroll(value)
    if not dropdownScroll then return end
    local maxScroll
    value, maxScroll = ClampDropdownScroll(value)
    dropdownScroll:SetVerticalScroll(value)
    if dropdownSlider then
        dropdownSlider._msuf2Refreshing = true
        dropdownSlider:SetMinMaxValues(0, maxScroll)
        dropdownSlider:SetValue(value)
        dropdownSlider._msuf2Refreshing = nil
    end
    return value
end
local function StopDropdownSmoothScroll()
    if dropdownScroll then dropdownScroll._msuf2SmoothScrollTarget = nil end
    local driver = dropdownFrame and dropdownFrame._msuf2SmoothScrollDriver
    if driver then driver:Hide() end
end
local function DropdownSmoothScrollOnUpdate(_, elapsed)
    if not (dropdownFrame and dropdownFrame.IsShown and dropdownFrame:IsShown() and dropdownScroll) then
        StopDropdownSmoothScroll()
        return
    end
    local target = dropdownScroll._msuf2SmoothScrollTarget
    if target == nil then
        StopDropdownSmoothScroll()
        return
    end
    target = ClampDropdownScroll(target)
    dropdownScroll._msuf2SmoothScrollTarget = target
    local current = (dropdownScroll.GetVerticalScroll and dropdownScroll:GetVerticalScroll()) or 0
    local delta = target - current
    if (T.ReducedMotionEnabled and T.ReducedMotionEnabled(true)) or math.abs(delta) <= DROPDOWN_SMOOTH_SCROLL_EPSILON then
        ApplyDropdownScroll(target)
        StopDropdownSmoothScroll()
        return
    end
    elapsed = tonumber(elapsed) or 0
    if elapsed > DROPDOWN_SMOOTH_SCROLL_MAX_ELAPSED then elapsed = DROPDOWN_SMOOTH_SCROLL_MAX_ELAPSED end
    local blend = min(1, elapsed * DROPDOWN_SMOOTH_SCROLL_SPEED)
    if blend <= 0 then return end
    ApplyDropdownScroll(current + delta * blend)
end
local function EnsureDropdownSmoothScrollDriver()
    if not dropdownFrame then return nil end
    local driver = dropdownFrame._msuf2SmoothScrollDriver
    if driver then return driver end
    driver = PixelLayoutRegion(CreateFrame("Frame", nil, dropdownFrame))
    driver:Hide()
    driver:SetScript("OnUpdate", DropdownSmoothScrollOnUpdate)
    dropdownFrame._msuf2SmoothScrollDriver = driver
    return driver
end
local function SmoothDropdownScrollTo(value)
    if not dropdownScroll then return end
    local target = ClampDropdownScroll(value)
    if T.ReducedMotionEnabled and T.ReducedMotionEnabled(true) then
        ApplyDropdownScroll(target)
        StopDropdownSmoothScroll()
        return
    end
    local current = (dropdownScroll.GetVerticalScroll and dropdownScroll:GetVerticalScroll()) or 0
    if math.abs(target - current) <= DROPDOWN_SMOOTH_SCROLL_EPSILON then
        ApplyDropdownScroll(target)
        StopDropdownSmoothScroll()
        return
    end
    dropdownScroll._msuf2SmoothScrollTarget = target
    local driver = EnsureDropdownSmoothScrollDriver()
    if driver then driver:Show() end
end
local function DropdownWheel(delta)
    if not (dropdownScroll and delta and delta ~= 0) then return end
    local current = dropdownScroll._msuf2SmoothScrollTarget or (dropdownScroll:GetVerticalScroll() or 0)
    SmoothDropdownScrollTo(current - (delta or 0) * dropdownActiveRowHeight * 3)
end
local function SetDropdownScroll(value)
    if not dropdownScroll then return end
    StopDropdownSmoothScroll()
    ApplyDropdownScroll(value)
end
IsDescendantOf = function(frame, ancestor)
    local current = frame
    while current do
        if current == ancestor then return true end
        current = current.GetParent and current:GetParent()
    end
    return false
end
local function Rect(frame)
    if not frame then return nil end
    local left = frame.GetLeft and frame:GetLeft()
    local right = frame.GetRight and frame:GetRight()
    local top = frame.GetTop and frame:GetTop()
    local bottom = frame.GetBottom and frame:GetBottom()
    if not (left and right and top and bottom) then return nil end
    return left, right, top, bottom
end
local function DropdownBounds(owner)
    local clampFrame = owner and owner._msuf2DropdownClampFrame
    local left, right, top, bottom = Rect(clampFrame)
    if left then return left, right, top, bottom end
    return Rect(UIParent)
end
local function DropdownOwnerVisible(owner)
    if not owner then return false end
    if owner.IsVisible and not owner:IsVisible() then return false end
    local left, right, top, bottom = Rect(owner)
    if not left then return false end
    local scroll = M.scrollFrame
    local child = M.scrollChild
    if scroll and child and IsDescendantOf(owner, child) then
        local sLeft, sRight, sTop, sBottom = Rect(scroll)
        if not sLeft then return false end
        if right < sLeft or left > sRight or top < sBottom or bottom > sTop then return false end
    end
    return true
end
local function DropdownAvailableSpace(owner)
    local ownerTop = owner and owner.GetTop and owner:GetTop()
    local ownerBottom = owner and owner.GetBottom and owner:GetBottom()
    local _, _, boundaryTop, boundaryBottom = DropdownBounds(owner)
    if not (ownerTop and ownerBottom and boundaryTop and boundaryBottom) then return nil, nil end
    return max(0, ownerBottom - boundaryBottom - 10), max(0, boundaryTop - ownerTop - 10)
end
local function DropdownVisibleRows(owner, rowCount, preferred, rowHeight, chromeHeight)
    preferred = min(rowCount or 0, preferred or 12)
    rowHeight = tonumber(rowHeight) or DROPDOWN_ROW_H
    local below, above = DropdownAvailableSpace(owner)
    if not below then return preferred, false end
    local preferredH = preferred * rowHeight + chromeHeight
    local openAbove = below < preferredH and above > below
    local maxSpace = openAbove and above or below
    local fit = floor((maxSpace - chromeHeight) / rowHeight)
    return max(1, min(preferred, fit)), openAbove
end
local function DropdownAnchorCoord(v)
    return floor((tonumber(v) or 0) + 0.5)
end
local function PositionDropdown(owner)
    if not (dropdownFrame and owner and dropdownFrame:IsShown()) then return false end
    if not DropdownOwnerVisible(owner) then
        CloseDropdown()
        return false
    end
    local frameH = dropdownFrame:GetHeight() or 0
    local frameW = dropdownFrame:GetWidth() or 0
    local ownerLeft = owner.GetLeft and owner:GetLeft()
    local ownerRight = owner.GetRight and owner:GetRight()
    local ownerTop = owner.GetTop and owner:GetTop()
    local ownerBottom = owner.GetBottom and owner:GetBottom()
    local boundaryLeft, boundaryRight, boundaryTop, boundaryBottom = DropdownBounds(owner)
    boundaryBottom = boundaryBottom or 0
    local openAbove = owner._msuf2DropdownOpenAbove
    if openAbove == nil then openAbove = ownerBottom and ownerBottom - frameH - 2 < boundaryBottom + 8 end
    local anchorRight = ownerLeft and boundaryRight and ownerLeft + frameW > boundaryRight - 8
    local point, relPoint, xOff, yOff
    if openAbove and anchorRight then
        point, relPoint, xOff, yOff = "BOTTOMRIGHT", "TOPRIGHT", 0, 2
    elseif openAbove then
        point, relPoint, xOff, yOff = "BOTTOMLEFT", "TOPLEFT", 0, 2
    elseif anchorRight then
        point, relPoint, xOff, yOff = "TOPRIGHT", "BOTTOMRIGHT", 0, -2
    else
        point, relPoint, xOff, yOff = "TOPLEFT", "BOTTOMLEFT", 0, -2
    end
    -- SetClampedToScreen protects the physical screen. These offsets also keep
    -- specialized dropdowns inside their owning options window.
    if ownerLeft and ownerRight and boundaryLeft and boundaryRight then
        local expectedLeft = anchorRight and (ownerRight - frameW) or ownerLeft
        local expectedRight = expectedLeft + frameW
        if expectedLeft < boundaryLeft + 8 then
            xOff = xOff + (boundaryLeft + 8 - expectedLeft)
        elseif expectedRight > boundaryRight - 8 then
            xOff = xOff - (expectedRight - (boundaryRight - 8))
        end
    end
    local anchorKey = point .. ":" .. relPoint .. ":" ..
        DropdownAnchorCoord(ownerLeft) .. ":" .. DropdownAnchorCoord(ownerRight) .. ":" ..
        DropdownAnchorCoord(ownerTop) .. ":" .. DropdownAnchorCoord(ownerBottom) .. ":" ..
        DropdownAnchorCoord(frameW) .. ":" .. DropdownAnchorCoord(frameH) .. ":" ..
        DropdownAnchorCoord(boundaryLeft) .. ":" .. DropdownAnchorCoord(boundaryRight) .. ":" ..
        DropdownAnchorCoord(boundaryTop) .. ":" .. DropdownAnchorCoord(boundaryBottom) .. ":" ..
        DropdownAnchorCoord(xOff)
    if dropdownFrame._msuf2AnchorKey ~= anchorKey then
        dropdownFrame._msuf2AnchorKey = anchorKey
        dropdownFrame:ClearAllPoints()
        dropdownFrame:SetPoint(point, owner, relPoint, xOff, yOff)
    end
    return true
end
-- Ends the closing state and hides the popup (when it exists) without animation.
local function FinishDropdownClose(frame)
    dropdownClosing = nil
    dropdownClosingOwner = nil
    if frame then
        frame._msuf2AnchorKey = nil
        frame:Hide()
        frame:SetAlpha(1)
    end
end
local function ResetDropdownSearch(hide)
    if not (dropdownSearch and dropdownSearch:IsShown()) then return end
    if dropdownSearch._msuf2Values then
        dropdownSearch._msuf2Values = nil
        dropdownFrame:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        dropdownSearch:ClearFocus()
        dropdownSearch:EnableMouse(false)
    end
    if hide then
        dropdownSearch:Hide()
        dropdownSearch._msuf2Empty:Hide()
        dropdownSearch:SetText("")
    end
end
function CloseDropdown(opts)
    local immediate = opts == true or (type(opts) == "table" and opts.immediate == true)
    if dropdownClosing and not dropdownOwner and not immediate then return end
    if HideDropdownItemTooltip then HideDropdownItemTooltip() end
    if FocusDropdownRow then FocusDropdownRow(nil) end
    local owner = dropdownOwner or dropdownClosingOwner
    dropdownClosing = true
    dropdownClosingOwner = owner
    dropdownOwner = nil
    ResetDropdownSearch(immediate)
    HideDropdownFocus(not immediate)
    if immediate and dropdownFrame then
        dropdownFrame._msuf2CloseToken = (dropdownFrame._msuf2CloseToken or 0) + 1
        if T.StopMotion then T.StopMotion(dropdownFrame) end
        FinishDropdownClose(dropdownFrame)
    elseif dropdownFrame and dropdownFrame:IsShown() then
        if dropdownFrame.EnableMouse then dropdownFrame:EnableMouse(false) end
        dropdownFrame._msuf2CloseToken = (dropdownFrame._msuf2CloseToken or 0) + 1
        local closeToken = dropdownFrame._msuf2CloseToken
        PlayMotion(dropdownFrame, "dropdownOut", { fromAlpha = dropdownFrame.GetAlpha and dropdownFrame:GetAlpha() or 1, onFinished = function(self)
            if dropdownOwner or self._msuf2CloseToken ~= closeToken then return end
            if self.EnableMouse then self:EnableMouse(true) end
            FinishDropdownClose(self)
        end })
    else
        FinishDropdownClose(dropdownFrame)
    end
    if owner then
        SetDropdownOwnerMouseWheel(owner, false)
        owner._msuf2DropdownListSelect = nil
        owner._msuf2DropdownListValue = nil
        owner._msuf2DropdownOpenAbove = nil
    end
end
W.CloseDropdown = CloseDropdown
local function EnsureDropdownFrame()
    if dropdownFrame then return dropdownFrame end
    dropdownFrame = PixelLayoutRegion(CreateFrame("Frame", "MSUF2NativeDropdownList", UIParent, T.Template and T.Template() or nil))
    dropdownFrame:SetFrameStrata("TOOLTIP")
    if dropdownFrame.SetFrameLevel then dropdownFrame:SetFrameLevel((M.MENU_POPUP_FRAME_LEVEL or 120) + 20) end
    dropdownFrame:SetToplevel(true)
    dropdownFrame:EnableMouse(true)
    dropdownFrame:EnableKeyboard(true)
    if dropdownFrame.SetPropagateKeyboardInput then dropdownFrame:SetPropagateKeyboardInput(true) end
    dropdownFrame:SetScript("OnKeyDown", function(self, key) DropdownKeyDown(self, key) end)
    if dropdownFrame.SetClampedToScreen then dropdownFrame:SetClampedToScreen(true) end
    if T.ApplyMaterial then
        T.ApplyMaterial(dropdownFrame, "popup")
    else
        T.ApplyBackdrop(dropdownFrame, T.colors.glassPopup or { 0.006, 0.016, 0.032, 0.985 }, T.colors.borderSoft or { 0.026, 0.070, 0.110, 0.88 })
        if T.ApplyGlass then T.ApplyGlass(dropdownFrame, "popup") end
    end
    dropdownFrame:Hide()
    dropdownScroll = PixelLayoutRegion(CreateFrame("ScrollFrame", "MSUF2NativeDropdownScroll", dropdownFrame))
    dropdownScroll:SetPoint("TOPLEFT", dropdownFrame, "TOPLEFT", 2, -2)
    dropdownScroll:SetPoint("BOTTOMRIGHT", dropdownFrame, "BOTTOMRIGHT", -20, 2)
    dropdownScroll:EnableMouseWheel(true)
    dropdownScroll:SetScript("OnMouseWheel", function(_, delta) DropdownWheel(delta) end)
    -- The Forever gamepad navigation glides the list with this, like the wheel.
    dropdownScroll._msuf2ScrollTo = SmoothDropdownScrollTo
    dropdownChild = PixelLayoutRegion(CreateFrame("Frame", nil, dropdownScroll))
    dropdownScroll:SetScrollChild(dropdownChild)
    dropdownSlider = PixelLayoutRegion(CreateFrame("Slider", nil, dropdownFrame))
    dropdownSlider:SetOrientation("VERTICAL")
    dropdownSlider:SetWidth(DROPDOWN_SCROLLBAR_W)
    dropdownSlider:SetMinMaxValues(0, 1)
    dropdownSlider:SetValueStep(1)
    if dropdownSlider.SetObeyStepOnDrag then dropdownSlider:SetObeyStepOnDrag(false) end
    if dropdownSlider.EnableMouse then dropdownSlider:EnableMouse(true) end
    dropdownSlider:SetPoint("TOPRIGHT", dropdownFrame, "TOPRIGHT", -8, -8)
    dropdownSlider:SetPoint("BOTTOMRIGHT", dropdownFrame, "BOTTOMRIGHT", -8, 8)
    local track = PixelBarTexture(PixelLayoutRegion(dropdownSlider:CreateTexture(nil, "BACKGROUND")))
    track:SetPoint("TOP", dropdownSlider, "TOP", 0, 0)
    track:SetPoint("BOTTOM", dropdownSlider, "BOTTOM", 0, 0)
    track:SetWidth(2)
    dropdownSlider._msuf2Track = track
    local trackEdge = PixelBarTexture(PixelLayoutRegion(dropdownSlider:CreateTexture(nil, "BORDER")))
    trackEdge:SetPoint("TOPLEFT", track, "TOPRIGHT", 1, 0)
    trackEdge:SetPoint("BOTTOMLEFT", track, "BOTTOMRIGHT", 1, 0)
    trackEdge:SetWidth(1)
    dropdownSlider._msuf2TrackEdge = trackEdge
    local thumb = PixelBarTexture(PixelLayoutRegion(dropdownSlider:CreateTexture(nil, "OVERLAY")))
    thumb:SetSize(4, 36)
    PixelLayoutRegion(dropdownSlider, "SetThumbTexture", thumb)
    dropdownSlider._msuf2Thumb = thumb
    dropdownSlider._msuf2ThumbBase = T.colors.coreRim or { 0.043, 0.096, 0.150 }
    dropdownSlider._msuf2ThumbHover = T.colors.coreRaised or { 0.026, 0.070, 0.110 }
    dropdownSlider:SetScript("OnValueChanged", function(self, value)
        if self._msuf2Refreshing then return end
        StopDropdownSmoothScroll()
        if dropdownScroll then
            local nextValue = ClampDropdownScroll(value or 0)
            dropdownScroll:SetVerticalScroll(nextValue)
        end
        PaintDropdownScrollbar(self._msuf2Hover)
    end)
    dropdownSlider:SetScript("OnEnter", function(self)
        self._msuf2Hover = true
        PaintDropdownScrollbar(true)
    end)
    dropdownSlider:SetScript("OnLeave", function(self)
        self._msuf2Hover = nil
        PaintDropdownScrollbar(false)
    end)
    dropdownSlider:EnableMouseWheel(true)
    dropdownSlider:SetScript("OnMouseWheel", function(_, delta) DropdownWheel(delta) end)
    dropdownSlider:Hide()
    PaintDropdownScrollbar(false)
    dropdownFrame:EnableMouseWheel(true)
    dropdownFrame:SetScript("OnMouseWheel", function(_, delta) DropdownWheel(delta) end)
    dropdownFrame:SetScript("OnHide", function()
        StopDropdownSmoothScroll()
        HideDropdownFocus(true)
        SetDropdownOwnerMouseWheel(dropdownOwner or dropdownClosingOwner, false)
        dropdownOwner = nil
        ResetDropdownSearch(true)
        dropdownClosing = nil
        dropdownClosingOwner = nil
        if dropdownFrame.EnableMouse then dropdownFrame:EnableMouse(true) end
        if dropdownFrame.SetAlpha then dropdownFrame:SetAlpha(1) end
    end)
    if IS_FOREVER then
        dropdownFrame.SmartNavigationCloseHandler = function()
            CloseDropdown(true)
            return true
        end
    end
    dropdownFrame:SetScript("OnUpdate", function(self, elapsed)
        if not dropdownOwner then return end
        self._msuf2PositionElapsed = (self._msuf2PositionElapsed or 0) + (elapsed or 0)
        if self._msuf2PositionElapsed < DROPDOWN_POSITION_INTERVAL then return end
        self._msuf2PositionElapsed = 0
        PositionDropdown(dropdownOwner)
    end)
    return dropdownFrame
end
local function RefreshDropdownMenuFonts()
    if not (dropdownFrame) then return end
    local db = MSUF_DB
    local general = type(db) == "table" and db.general or nil
    local stamp = tostring(type(general) == "table" and general.menuFontKey or "")
        .. "\030" .. tostring(tonumber(MSUF_FontApplyEpoch) or 0)
    if dropdownFrame._msuf2MenuFontStamp == stamp then return end
    T.RefreshMenuFonts(dropdownFrame, true)
    dropdownFrame._msuf2MenuFontStamp = stamp
end
local function DropdownItemValue(item)
    if type(item) ~= "table" then return item end
    if item.value ~= nil then return item.value end
    if item.key ~= nil then return item.key end
    if item[2] ~= nil then return item[2] end
    return item[1]
end
local function DropdownItemText(item)
    if type(item) ~= "table" then return Tr(tostring(item or "")) end
    if item.translate == false then return tostring(item.text or item.label or DropdownItemValue(item) or "") end
    if item.text ~= nil then return Tr(item.text) end
    if item.label ~= nil then return Tr(item.label) end
    if item[1] ~= nil and item[2] ~= nil then return Tr(tostring(item[1])) end
    return Tr(tostring(DropdownItemValue(item) or ""))
end
local function DropdownItemTooltipField(item, key, fallbackKey)
    if type(item) ~= "table" then return nil end
    local value = item[key]
    if value == nil and fallbackKey then value = item[fallbackKey] end
    if type(value) == "function" then
        local resolved = value(item)
        value = resolved or nil
    end
    if value == nil or value == "" then return nil end
    return Tr(tostring(value))
end
HideDropdownItemTooltip = function(owner)
    if not GameTooltip then return end
    if not owner or not GameTooltip.IsOwned or GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end
-- Long translated labels end in an ellipsis; the tooltip then carries the full text.
local function TruncatedText(fs)
    if not (fs and fs.IsTruncated and fs:IsShown() and fs:IsTruncated()) then return nil end
    local text = fs:GetText()
    if text == nil or text == "" then return nil end
    return text
end
local function ShowDropdownItemTooltip(owner)
    local item = owner and owner._msuf2Item
    local body = DropdownItemTooltipField(item, "tooltip", "description")
    if not GameTooltip or not (body or TruncatedText(owner and owner._msuf2Text)) then return end
    local title = body and DropdownItemTooltipField(item, "tooltipTitle") or DropdownItemText(item)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1, 1, true)
    if body then GameTooltip:AddLine(body, 0.80, 0.86, 1.00, true) end
    GameTooltip:Show()
end
--- Full title and selected-value text of a dropdown field whose label had to be
--- cut short (nil when it fits). Page tooltips on the field append the value.
function W.DropdownOverflowText(owner)
    if not (owner and owner._msuf2ControlKind == "dropdown") then return nil, nil end
    return TruncatedText(owner._msuf2Title), TruncatedText(owner._msuf2Label)
end
local function DropdownItemIcon(item)
    if type(item) ~= "table" then return nil end
    if item.previewKind == "statusbar" or item.statusbarPreview == true then return nil end
    if item.icon or item.texture then return item.icon or item.texture end
    return (type(item.swatch) == "string") and item.swatch or nil
end
local function DropdownItemStatusbarTexture(item)
    if type(item) ~= "table" then return nil end
    if item.previewKind ~= "statusbar" and item.statusbarPreview ~= true then return nil end
    local texture = item.texturePreview or item.statusbarTexture or item.texture
    if type(texture) == "string" and texture ~= "" then return texture end
    local value = DropdownItemValue(item)
    if type(value) == "string" and value ~= "" and ResolveStatusbarTextureKey then
        return ResolveStatusbarTextureKey(value)
    end
    return nil
end
local function DropdownItemBarPreview(item)
    if type(item) ~= "table" or item.previewKind ~= "barOverlay" then return nil end
    local preview = item.barPreview or item.overlayPreview or item.preview
    if type(preview) == "function" then
        local resolved = preview(item)
        preview = resolved or nil
    end
    return type(preview) == "table" and preview or nil
end
local function DropdownColorTuple(color)
    if type(color) == "function" then
        local resolved = color()
        color = resolved or nil
    end
    if type(color) ~= "table" then return nil end
    local r = color.r or color[1]
    local g = color.g or color[2]
    local b = color.b or color[3]
    local a = color.a or color[4] or 1
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b, a end
    return nil
end
local function DropdownItemSwatch(item)
    if type(item) ~= "table" then return nil end
    return DropdownColorTuple(item.swatchColor or item.color or item.colorPreview or item.swatch)
end
local function DropdownItemHeader(item)
    return type(item) == "table" and (item.header == true or item.categoryHeader == true)
end
local function DropdownItemDisabled(item)
    if type(item) ~= "table" then return false end
    if DropdownItemHeader(item) then return true end
    local disabled = item.disabled
    if type(disabled) == "function" then
        local resolved = disabled(item)
        disabled = resolved ~= false
    end
    if disabled ~= nil then return disabled and true or false end
    local enabled = item.enabled
    if type(enabled) == "function" then
        local resolved = enabled(item)
        enabled = resolved or false
    end
    return enabled == false
end
local function StoreDropdownDefaultFont(fs)
    if not (fs and fs.GetFont) then return end
    local font, size, flags = fs:GetFont()
    if font and size then fs._msuf2DropdownDefaultFont = { font, size, flags or "" } end
end
local function RestoreDropdownDefaultFont(fs)
    local d = fs and fs._msuf2DropdownDefaultFont
    if d and fs.SetFont then
        SetFontChecked(fs, d[1], d[2], d[3] or "")
    elseif fs and fs.SetFontObject then
        fs:SetFontObject(GameFontHighlight)
    end
end
local function ApplyDropdownItemFont(fs, item)
    if not fs then return end
    if type(item) ~= "table" then
        RestoreDropdownDefaultFont(fs)
        return
    end
    local d = fs._msuf2DropdownDefaultFont
    -- Font previews can use third-party faces with unusually tall glyphs.
    local size = max(8, ((d and d[2]) or T.FontSize("control")) - 1)
    local fontKey = item.fontKey or item.fontPreviewKey
    local fontPath = item.fontPath or item.font
    if (type(fontPath) ~= "string" or fontPath == "") and type(fontKey) == "string" and fontKey ~= "" then
        fontPath = ResolveFontKeyPath(fontKey)
    end
    local fontObject = item.fontObject or item.fontPreviewObject
    if fontObject and fs.SetFontObject then
        fs:SetFontObject(fontObject)
        return
    end
    if type(fontPath) == "string" and fontPath ~= "" and fs.SetFont then
        fontPath = ResolveSafeFontPath(fontPath, size, "", fontKey)
        if SetFontChecked(fs, fontPath, size, "") then return end
    end
    RestoreDropdownDefaultFont(fs)
end
local function DropdownItemHasFontPreview(item)
    return type(item) == "table" and (
        item.fontKey ~= nil
        or item.fontPreviewKey ~= nil
        or item.fontPath ~= nil
        or item.font ~= nil
        or item.fontObject ~= nil
        or item.fontPreviewObject ~= nil
    )
end
local function SetDropdownIconTexture(texture, icon)
    SetIconTexture(texture, icon, "")
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetVertexColor(1, 1, 1, 1)
    texture:Show()
end
local function HideDropdownBarPreview(frame)
    local preview = frame and frame._msuf2BarPreview
    if not preview then return end
    for i = 1, #preview do preview[i].host:Hide() end
end

local DEFAULT_OVERLAY_COLOR = { 1, 1, 1, .82 }
local function ConfigureBarPreview(spec, lane)
    local config = lane.config
    spec.width, spec.height = lane.width, DROPDOWN_BAR_PREVIEW_H
    spec.health.reverse, spec.health.vertical, spec.health.topInset = lane.reverse, false, 0
    spec.health.texture, spec.health.backgroundTexture = config.healthTexture, config.backgroundTexture
    spec.power.enabled = false
    spec.border = nil
    local p, c = spec.prediction, config.overlayColor or DEFAULT_OVERLAY_COLOR
    p.enabled, p.test = true, false
    p.heal, p.absorb, p.healAbsorb = config.category == "heal", config.category == "absorb", config.category == "negative"
    p.healAnchorMode, p.absorbAnchorMode, p.healAbsorbAnchorMode = config.mode, config.mode, config.mode
    p.texture, p.absorbTexture, p.healAbsorbTexture = config.overlayTexture, config.overlayTexture, config.overlayTexture
    p.healHeight, p.absorbHeight, p.healAbsorbHeight = 0, 0, 0
    p.healOffsetY, p.absorbOffsetY, p.healAbsorbOffsetY = 0, 0, 0
    p.healR, p.healG, p.healB, p.healA = c[1], c[2], c[3], c[4]
    p.absorbR, p.absorbG, p.absorbB, p.absorbA = c[1], c[2], c[3], c[4]
    p.healAbsorbR, p.healAbsorbG, p.healAbsorbB, p.healAbsorbA = c[1], c[2], c[3], c[4]
    p.fullHealthAbsorbStripe = config.showAbsorbEdgeGlow == true
end

local function PaintDropdownBarPreviewLane(frame, index, config, sample, width, reverse, y)
    local preview = frame._msuf2BarPreview
    local lane = preview[index]
    if not lane then
        local host = PixelLayoutRegion(CreateFrame("Frame", nil, frame))
        host:Hide()
        lane = { host = host }
        lane.surface = M.PreviewHelpers.NewRuntimeUnitSurface(host, "player", nil,
            function(spec) ConfigureBarPreview(spec, lane) end, true)
        lane.surface.fit = false
        preview[index] = lane
    end
    local host = lane.host
    if lane.y ~= y then
        lane.y = y
        host:ClearAllPoints()
        host:SetPoint("RIGHT", frame, "RIGHT", -DROPDOWN_BAR_PREVIEW_RIGHT, y)
    end
    if lane.width ~= width then
        lane.width = width
        host:SetSize(width, DROPDOWN_BAR_PREVIEW_H)
    end
    lane.config, lane.reverse, lane.surface.sample = config, reverse, sample
    if host:IsShown() then
        lane.surface:Refresh()
    else
        host:Show()
    end
end

local function PaintDropdownBarPreview(frame, config, width)
    if not frame._msuf2BarPreview then frame._msuf2BarPreview = {} end
    local amount = tonumber(config.overlayFraction) or .2
    local sample = { hp = tonumber(config.healthFraction) or .68, reducedMax = 0,
        incoming = config.category == "heal" and amount or 0,
        absorb = config.category == "absorb" and amount or 0,
        healAbsorb = config.category == "negative" and amount or 0 }
    local dualDirection = config.dualDirection == true and frame:GetHeight() >= 30
    PaintDropdownBarPreviewLane(frame, 1, config, sample, width, false, dualDirection and 7 or 0)
    if dualDirection then
        PaintDropdownBarPreviewLane(frame, 2, config, sample, width, true, -7)
    elseif frame._msuf2BarPreview[2] then
        frame._msuf2BarPreview[2].host:Hide()
    end
end
-- Plain choices need no art. A pooled row or field creates each preview
-- region only when it first displays that kind of value.
local function EnsureDropdownChoiceArt(frame, kind, width, height)
    local preview = frame[kind]
    local borderKey = kind .. "Border"
    if preview then return preview, frame[borderKey] end
    local border = PixelLayoutRegion(frame:CreateTexture(nil, "ARTWORK"))
    border:SetPoint("LEFT", frame, "LEFT", frame._msuf2ChoiceBorderLeft, 0)
    local padding = kind == "_msuf2Swatch" and 4 or 2
    border:SetSize(width + padding, height + padding)
    border:SetColorTexture(0, 0, 0, frame._msuf2ChoiceBorderAlpha)
    frame[borderKey] = border
    preview = PixelLayoutRegion(frame:CreateTexture(nil, "OVERLAY"))
    preview:SetPoint("CENTER", border, "CENTER", 0, 0)
    preview:SetSize(width, height)
    frame[kind] = preview
    return preview, border
end
local function EnsureDropdownIcon(frame)
    local texture = frame._msuf2Icon
    if not texture then
        texture = PixelLayoutRegion(frame:CreateTexture(nil, "ARTWORK"))
        texture:SetPoint("LEFT", frame, "LEFT", DROPDOWN_ICON_LEFT, 0)
        texture:SetSize(DROPDOWN_ICON_SIZE, DROPDOWN_ICON_SIZE)
        frame._msuf2Icon = texture
    end
    return texture
end
local function HideDropdownChoiceArt(frame, except)
    local previous = frame._msuf2ChoiceArt
    if not previous or previous == except then return end
    frame[previous]:Hide()
    local border = frame[previous .. "Border"]
    if border then border:Hide() end
end
local function PaintDropdownChoice(frame, label, icon, sr, sg, sb, sa, rightInset, statusbarTexture, barPreview)
    local left = frame._msuf2CompactValueInsets and 6 or DROPDOWN_FIELD_TEXT_LEFT
    local art
    if barPreview then
        local inset = DROPDOWN_BAR_PREVIEW_RIGHT + DROPDOWN_BAR_PREVIEW_LABEL_GAP
        local textWidth = label.GetUnboundedStringWidth and label:GetUnboundedStringWidth() or label:GetStringWidth()
        local available = floor(frame:GetWidth() - left - inset - textWidth)
        local width = min(DROPDOWN_BAR_PREVIEW_W, available)
        if width >= 48 then
            PaintDropdownBarPreview(frame, barPreview, width)
            rightInset = min(rightInset or -8, -inset - width)
        else
            HideDropdownBarPreview(frame)
        end
    else
        if frame._msuf2BarPreview then HideDropdownBarPreview(frame) end
        if statusbarTexture then
            art = "_msuf2TexturePreview"
            local texture, border = EnsureDropdownChoiceArt(frame, art, DROPDOWN_TEXTURE_PREVIEW_W, DROPDOWN_TEXTURE_PREVIEW_H)
            texture:SetTexture(statusbarTexture)
            texture:SetVertexColor(1, 1, 1, 1)
            texture:Show()
            border:Show()
            left = DROPDOWN_TEXTURE_TEXT_LEFT
        elseif icon then
            art = "_msuf2Icon"
            SetDropdownIconTexture(EnsureDropdownIcon(frame), icon)
            left = DROPDOWN_ICON_TEXT_LEFT
        elseif sr then
            art = "_msuf2Swatch"
            local swatch, border = EnsureDropdownChoiceArt(frame, art, 12, 12)
            swatch:SetColorTexture(sr, sg, sb, sa or 1)
            swatch:Show()
            border:Show()
            left = DROPDOWN_SWATCH_TEXT_LEFT
        end
    end
    HideDropdownChoiceArt(frame, art)
    frame._msuf2ChoiceArt = art
    label:ClearAllPoints()
    label:SetPoint("LEFT", frame, "LEFT", left, 0)
    label:SetPoint("RIGHT", frame, "RIGHT", rightInset or -8, 0)
end
-- Keyboard focus is separate from the saved selection. Moving through a list
-- never writes a setting; Enter uses the same guarded action as a mouse click.
FocusDropdownRow = function(index, scroll)
    local previous = dropdownFrame and dropdownRows[dropdownFrame._msuf2KeyboardIndex or 0]
    if previous then previous._msuf2KeyboardCue:Hide() end
    if not dropdownFrame then return end
    local row = index and dropdownRows[index]
    if not row or row._msuf2DropdownDisabled or not row:IsShown() then index, row = nil, nil end
    dropdownFrame._msuf2KeyboardIndex = index
    if not row then return end
    row._msuf2KeyboardCue:Show()
    if scroll then
        local top = (index - 1) * dropdownActiveRowHeight
        local offset = dropdownScroll:GetVerticalScroll() or 0
        local visible = dropdownFrame._msuf2ListHeight
        if top < offset then SetDropdownScroll(top)
        elseif top + dropdownActiveRowHeight > offset + visible then
            SetDropdownScroll(top + dropdownActiveRowHeight - visible)
        end
        HideDropdownItemTooltip()
        ShowDropdownItemTooltip(row)
    end
end
local function ActivateDropdownRow()
    local row = dropdownRows[dropdownFrame._msuf2KeyboardIndex or 0]
    if row then row:GetScript("OnClick")(row) end
end
local function MoveDropdownSelection(self, key)
    local count = self._msuf2RowCount or 0
    local step = (key == "UP" or key == "END") and -1 or 1
    local index = self._msuf2KeyboardIndex or (step == 1 and 0 or count + 1)
    if key == "HOME" then index = 0 elseif key == "END" then index = count + 1 end
    index = index + step
    while index >= 1 and index <= count do
        local row = dropdownRows[index]
        if row and not row._msuf2DropdownDisabled then
            FocusDropdownRow(index, true)
            return
        end
        index = index + step
    end
end
DropdownKeyDown = function(self, key)
    local handled = dropdownOwner and (key == "ESCAPE" or key == "UP" or key == "DOWN"
        or key == "HOME" or key == "END" or key == "ENTER" or key == "SPACE")
    if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(not handled) end
    if not handled then return end
    if key == "ESCAPE" then
        CloseDropdown(true)
    elseif key == "ENTER" or key == "SPACE" then
        ActivateDropdownRow()
    else
        MoveDropdownSelection(self, key)
    end
end
-- Rows and the owning button hand their wheel input to the list's own handler.
local function ForwardDropdownWheel(_, delta)
    if not dropdownScroll then return end
    local handler = dropdownScroll:GetScript("OnMouseWheel")
    if handler then handler(dropdownScroll, delta) end
end
-- Combat refuses every dropdown action centrally; the open list closes instead.
local function CloseIfCombatBlocked()
    if not (M.BlockCombatAction and M.BlockCombatAction()) then return false end
    CloseDropdown()
    return true
end
local function DropdownRow(index)
    local row = dropdownRows[index]
    if row then return row end
    row = PixelLayoutRegion(CreateFrame("Button", nil, dropdownChild))
    row:SetHeight(DROPDOWN_ROW_H)
    row._msuf2Index = index
    local cue = PixelLayoutRegion(row:CreateTexture(nil, "BORDER"))
    cue:SetAllPoints()
    cue:SetColorTexture(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.18)
    cue:Hide()
    row._msuf2KeyboardCue = cue
    row:EnableMouse(true)
    row:RegisterForClicks("AnyUp")
    local hover = PixelLayoutRegion(row:CreateTexture(nil, "HIGHLIGHT"))
    hover:SetAllPoints()
    if T.ApplyTextureGradient then
        T.ApplyTextureGradient(hover, "HORIZONTAL",
            { T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.18 },
            { T.colors.accent[1] * 0.55, T.colors.accent[2] * 0.60, T.colors.accent[3] * 0.75, 0.08 },
            false)
    else
        hover:SetColorTexture(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.18)
    end
    local selected = PixelLayoutRegion(row:CreateTexture(nil, "OVERLAY"))
    selected:SetPoint("LEFT", row, "LEFT", 2, 0)
    selected:SetSize(2, DROPDOWN_ROW_H - 4)
    selected:SetColorTexture(T.colors.accent2[1], T.colors.accent2[2], T.colors.accent2[3], 0.95)
    selected:Hide()
    row._msuf2Selected = selected
    row._msuf2ChoiceBorderLeft, row._msuf2ChoiceBorderAlpha = 10, 0.85
    local text = T.Font(row, "GameFontHighlight", "", T.colors.text, "control")
    text:SetPoint("LEFT", row, "LEFT", 12, 0)
    text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    text:SetJustifyH("LEFT")
    if text.SetWordWrap then text:SetWordWrap(false) end
    if text.SetNonSpaceWrap then text:SetNonSpaceWrap(false) end
    StoreDropdownDefaultFont(text)
    row._msuf2Text = text
    row:SetScript("OnEnter", function(self)
        FocusDropdownRow(self._msuf2Index)
        ShowDropdownItemTooltip(self)
    end)
    row:SetScript("OnLeave", function(self) HideDropdownItemTooltip(self) end)
    row:SetScript("OnClick", function(self)
        local owner = self._msuf2Owner
        if not dropdownOwner or owner ~= dropdownOwner or self._msuf2DropdownDisabled or CloseIfCombatBlocked() then return end
        local value = self._msuf2Value
        if owner then
            if owner._msuf2DropdownListSelect then
                owner._msuf2DropdownListSelect(value, self._msuf2Item)
            else
                owner:SetValue(value)
                if owner._msuf2OnValueChanged then owner._msuf2OnValueChanged(value) end
            end
        end
        HideDropdownItemTooltip(self)
        CloseDropdown()
        if owner and owner._msuf2OnOptionSelected then
            owner._msuf2OnOptionSelected(value)
        end
    end)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", ForwardDropdownWheel)
    dropdownRows[index] = row
    return row
end
local function RefreshDropdownScrollbar(count)
    local visibleHeight = dropdownFrame._msuf2ListHeight
    local totalHeight = count * dropdownActiveRowHeight
    dropdownChild:SetHeight(max(1, totalHeight))
    dropdownSlider:SetShown(totalHeight > visibleHeight)
    local visibleRatio = visibleHeight / max(1, totalHeight)
    local thumb = dropdownSlider._msuf2Thumb
    if thumb then thumb:SetHeight(floor(max(34, min(visibleHeight - 12, visibleHeight * visibleRatio)) + 0.5)) end
    PaintDropdownScrollbar(dropdownSlider._msuf2Hover)
end

local function PaintDropdownRows(owner, valuesTable)
    local selectedIndex, firstEnabled
    local selectedValue = owner._msuf2DropdownListValue
    if selectedValue == nil then selectedValue = owner.value end
    local rowHeight, rowWidth = dropdownActiveRowHeight, dropdownChild:GetWidth()
    dropdownFrame._msuf2RowCount = #valuesTable
    for i = 1, #valuesTable do
        local item = valuesTable[i]
        local row = DropdownRow(i)
        local value = DropdownItemValue(item)
        local icon = DropdownItemIcon(item)
        local statusbarTexture = DropdownItemStatusbarTexture(item)
        local barPreview = DropdownItemBarPreview(item)
        local isHeader = DropdownItemHeader(item)
        local disabled = DropdownItemDisabled(item)
        row._msuf2Owner = owner
        row._msuf2Value = value
        row._msuf2Item = item
        row._msuf2DropdownDisabled = disabled
        row._msuf2KeyboardCue:Hide()
        row:SetHeight(rowHeight)
        row._msuf2Selected:SetHeight(rowHeight - 4)
        if row.SetAlpha then row:SetAlpha(isHeader and 1 or (disabled and 0.62 or 1)) end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", dropdownChild, "TOPLEFT", 0, -((i - 1) * rowHeight))
        row:SetWidth(rowWidth)
        T.SetDangerButtonSurface(row, not disabled and type(item) == "table" and item.destructive == true)
        row._msuf2Selected:SetShown((not isHeader) and value == selectedValue)
        if (not isHeader) and value == selectedValue then selectedIndex = i end
        if not disabled and not firstEnabled then firstEnabled = i end
        RestoreDropdownDefaultFont(row._msuf2Text)
        -- DropdownItemText already translated the entry (or kept it raw).
        T.SetTranslatedText(row._msuf2Text, DropdownItemText(item))
        if row._msuf2Text.SetTextColor then
            local c = isHeader and (T.colors.accent2 or T.colors.accent or T.colors.text)
                or (disabled and (T.colors.disabled or T.colors.dim or T.colors.muted) or T.colors.text)
            row._msuf2Text:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        end
        if DropdownItemHasFontPreview(item) then ApplyDropdownItemFont(row._msuf2Text, item) end
        local sr, sg, sb, sa = DropdownItemSwatch(item)
        -- A header row never shows a bar preview, texture, swatch or icon.
        if isHeader then barPreview, statusbarTexture, sr, icon = nil, nil, nil, nil end
        PaintDropdownChoice(row, row._msuf2Text, icon, sr, sg, sb, sa, -6, statusbarTexture, barPreview)
        row:Show()
    end
    for i = #valuesTable + 1, #dropdownRows do
        dropdownRows[i]:Hide()
    end
    return selectedIndex, firstEnabled
end

local function ScrollToDropdownRow(index)
    local offset = (index or 1) * dropdownActiveRowHeight - dropdownFrame._msuf2ListHeight
    SetDropdownScroll(max(0, offset))
    FocusDropdownRow(index)
end

local function FilterDropdownItems(values, query)
    local normalize = M.Search.Text.NormalizeSearchText
    local words = {}
    for word in normalize(query):gmatch("%S+") do words[#words + 1] = word end
    if #words == 0 then return values end
    local matches = {}
    for _, item in ipairs(values) do
        if not DropdownItemHeader(item) then
            local text = DropdownItemText(item)
            local label = normalize(text)
            local alias = type(item) == "table" and (item.searchText or item.text)
            if alias and alias ~= text then label = label .. " " .. normalize(alias) end
            local matched = true
            for i = 1, #words do
                if not label:find(words[i], 1, true) then
                    matched = false
                    break
                end
            end
            if matched then matches[#matches + 1] = item end
        end
    end
    return matches
end

local function DropdownSearchChanged(self)
    local query = self:GetText() or ""
    self._msuf2Placeholder:SetShown(query == "")
    self._msuf2Clear:SetShown(query ~= "")
    local values = self._msuf2Values
    local owner = dropdownOwner
    if not (owner and values) or self._msuf2Query == query then return end
    self._msuf2Query = query
    local matches = FilterDropdownItems(values, query)
    local empty = self._msuf2Empty
    if #matches == 0 then
        T.SetTranslatedText(empty, M.Format("No results for \"%s\".", (query:gsub("|", "||"))))
    end
    empty:SetShown(#matches == 0)
    HideDropdownItemTooltip()
    FocusDropdownRow(nil)
    local selectedIndex, firstEnabled = PaintDropdownRows(owner, matches)
    RefreshDropdownScrollbar(#matches)
    local index = firstEnabled
    if matches == values and selectedIndex and not dropdownRows[selectedIndex]._msuf2DropdownDisabled then index = selectedIndex end
    ScrollToDropdownRow(index)
end

local function EnsureDropdownSearch()
    if dropdownSearch then return dropdownSearch end
    local search = PixelLayoutRegion(CreateFrame("EditBox", nil, dropdownFrame, "InputBoxScriptTemplate"))
    dropdownSearch = search
    dropdownFrame._msuf2SearchBox = search
    search:SetPoint("TOPLEFT", dropdownFrame, "TOPLEFT", 8, -5)
    search:SetPoint("TOPRIGHT", dropdownFrame, "TOPRIGHT", -8, -5)
    search:SetHeight(26)
    search:SetFontObject(GameFontHighlightSmall)
    search:SetAutoFocus(false)
    search:SetAltArrowKeyMode(false)
    search:SetMaxLetters(80)
    search:SetTextInsets(8, 26, 0, 0)
    search:EnableMouse(true)
    search:EnableMouseWheel(true)
    search:SetScript("OnMouseWheel", ForwardDropdownWheel)
    T.SkinEditBox(search)
    T.StyleFontString(search, T.colors.text, 0, "control")

    local placeholder = T.Font(search, "GameFontDisableSmall", "Search", T.colors.searchPlaceholder or T.colors.muted, "control")
    placeholder:SetPoint("LEFT", search, "LEFT", 8, 0)
    placeholder:SetPoint("RIGHT", search, "RIGHT", -26, 0)
    placeholder:SetJustifyH("LEFT")
    placeholder:SetWordWrap(false)
    search._msuf2Placeholder = placeholder

    local clear = T.Button(search, "", 20, 20, { history = false })
    clear:SetPoint("RIGHT", search, "RIGHT", -3, 0)
    clear:SetText("×", true)
    clear:SetScript("OnClick", function()
        if not search._msuf2Values then return end
        search:SetText("")
        search:SetFocus()
    end)
    clear:Hide()
    search._msuf2Clear = clear

    local empty = T.Font(dropdownScroll, "GameFontDisableSmall", "", T.colors.muted, "control")
    empty:SetPoint("TOPLEFT", dropdownScroll, "TOPLEFT", 12, -5)
    empty:SetPoint("TOPRIGHT", dropdownScroll, "TOPRIGHT", -8, -5)
    empty:SetJustifyH("LEFT")
    empty:SetWordWrap(false)
    empty:Hide()
    search._msuf2Empty = empty

    -- Route arrow and enter through the list while the edit box owns typing.
    search:HookScript("OnEditFocusGained", function() dropdownFrame:EnableKeyboard(false) end)
    search:HookScript("OnEditFocusLost", function() dropdownFrame:EnableKeyboard(true) end)
    search:SetScript("OnTextChanged", DropdownSearchChanged)
    search:SetScript("OnArrowPressed", function(_, key)
        if key == "UP" or key == "DOWN" then MoveDropdownSelection(dropdownFrame, key) end
    end)
    search:SetScript("OnEnterPressed", ActivateDropdownRow)
    search:SetScript("OnEscapePressed", function() CloseDropdown(true) end)
    dropdownFrame:SetScript("OnEvent", function(self)
        if dropdownOwner and not (self:IsMouseOver() or dropdownOwner:IsMouseOver()) then CloseDropdown(true) end
    end)
    return search
end

local function OpenDropdown(owner, valuesTable)
    EnsureDropdownFrame()
    valuesTable = (type(valuesTable) == "table") and valuesTable or {}
    if #valuesTable == 0 then return end
    dropdownClosing = nil
    dropdownClosingOwner = nil
    dropdownFrame._msuf2CloseToken = (dropdownFrame._msuf2CloseToken or 0) + 1
    -- The popup is parented to UIParent, while its owner is inside the scaled
    -- options window. Match their coordinate spaces before measuring edges.
    local menu = M.frame
    if menu and menu.GetScale and dropdownFrame.SetScale then
        dropdownFrame:SetScale(menu:GetScale())
    end
    local hasIcons, hasStatusbarPreviews, hasBarPreviews = false, false, false
    for i = 1, #valuesTable do
        if DropdownItemBarPreview(valuesTable[i]) then
            hasBarPreviews = true
        elseif DropdownItemStatusbarTexture(valuesTable[i]) then
            hasStatusbarPreviews = true
        elseif DropdownItemIcon(valuesTable[i]) then
            hasIcons = true
        end
    end
    local ownerWidth = (owner.GetWidth and owner:GetWidth()) or 240
    local rowHeight = hasBarPreviews and DROPDOWN_BAR_PREVIEW_ROW_H or DROPDOWN_ROW_H
    dropdownActiveRowHeight = rowHeight
    local preferredWidth = tonumber(owner._msuf2DropdownPreferredWidth)
    local rowWidth = math.max(ownerWidth, preferredWidth
        or (hasBarPreviews and 430 or (hasStatusbarPreviews and 360 or (hasIcons and 300 or 180))))
    ResetDropdownSearch(true)
    local search = owner._msuf2DropdownSearchable and EnsureDropdownSearch()
    local headerHeight = search and DROPDOWN_SEARCH_H or 0
    local chromeHeight = headerHeight + 4
    local visible, openAbove = DropdownVisibleRows(owner, #valuesTable,
        (hasIcons or hasStatusbarPreviews or hasBarPreviews) and 12 or 14, rowHeight, chromeHeight)
    owner._msuf2DropdownOpenAbove = openAbove
    local listHeight = visible * rowHeight
    local needsScroll = #valuesTable > visible
    local listGutter = needsScroll and 20 or 4
    local boundaryLeft, boundaryRight = DropdownBounds(owner)
    if boundaryLeft then
        rowWidth = min(rowWidth, max(1, floor(boundaryRight - boundaryLeft - 16 - listGutter)))
    end
    dropdownFrame._msuf2ListHeight = listHeight
    dropdownFrame:SetSize(rowWidth + listGutter, listHeight + chromeHeight)
    dropdownChild:SetWidth(rowWidth)
    dropdownScroll:ClearAllPoints()
    dropdownScroll:SetPoint("TOPLEFT", dropdownFrame, "TOPLEFT", 2, -2 - headerHeight)
    dropdownScroll:SetPoint("BOTTOMRIGHT", dropdownFrame, "BOTTOMRIGHT", needsScroll and -16 or -2, 2)
    dropdownSlider:SetPoint("TOPRIGHT", dropdownFrame, "TOPRIGHT", -8, -8 - headerHeight)
    RefreshDropdownScrollbar(#valuesTable)
    RefreshDropdownMenuFonts()
    local selectedIndex, firstEnabled = PaintDropdownRows(owner, valuesTable)
    local index = selectedIndex or (search and firstEnabled) or 1
    if search then
        if dropdownRows[index]._msuf2DropdownDisabled then index = firstEnabled end
        search._msuf2Query = ""
        search._msuf2Placeholder:Show()
        search._msuf2Clear:Hide()
        search._msuf2Values = valuesTable
        search:EnableMouse(true)
        search:Show()
    end
    dropdownOwner = owner
    dropdownFrame:EnableKeyboard(true)
    if dropdownFrame.SetPropagateKeyboardInput then dropdownFrame:SetPropagateKeyboardInput(true) end
    SetDropdownOwnerMouseWheel(owner, true)
    ShowDropdownFocus(owner)
    if dropdownFrame.EnableMouse then dropdownFrame:EnableMouse(true) end
    dropdownFrame:SetAlpha(0)
    dropdownFrame:Show()
    dropdownFrame._msuf2AnchorKey = nil
    if not PositionDropdown(owner) then
        CloseDropdown(true)
        return
    end
    ScrollToDropdownRow(index)
    PlayMotion(dropdownFrame, "dropdownIn", { fromAlpha = 0 })
    ShowForeverDropdown(index and dropdownRows[index])
    if search then
        dropdownFrame:RegisterEvent("GLOBAL_MOUSE_DOWN")
        if not (IS_FOREVER and MSUF.PadNavigation and MSUF.PadNavigation.IsGamepadUI()) then search:SetFocus() end
    end
end
function W.OpenDropdown(owner, values, currentValue, onSelect)
    if not owner or CloseIfCombatBlocked() then return false end
    if dropdownOwner == owner and dropdownFrame and dropdownFrame:IsShown() then
        CloseDropdown()
        return false
    end
    CloseDropdown()
    owner._msuf2DropdownListValue = currentValue
    owner._msuf2DropdownListSelect = function(value, item)
        if type(onSelect) == "function" then onSelect(value, item) end
    end
    OpenDropdown(owner, values)
    return true
end
local function ResolveDropdownValues(owner)
    local valuesTable = owner.values
    local dynamic = type(valuesTable) == "function"
    if dynamic then
        local resolved = valuesTable()
        valuesTable = resolved or nil
    end
    if type(valuesTable) ~= "table" then valuesTable = {} end
    return valuesTable, dynamic
end
local function FindDropdownItem(owner, value)
    local valuesTable, dynamic = ResolveDropdownValues(owner)
    for i = 1, #valuesTable do
        local item = valuesTable[i]
        if DropdownItemValue(item) == value then return item, dynamic end
    end
    return nil, dynamic
end
function W.Dropdown(section, label, values, width, opts)
    local x, y = NextRow(section, 48)
    local title = T.Font(section, "GameFontHighlightSmall", label or "", T.colors.text, "control")
    SetSearchText(title, label)
    title:SetPoint("TOPLEFT", x, y)
    -- The title starts at the field's left edge. A label wider than the field
    -- is cut with an ellipsis instead of wrapping onto the field below it.
    title:SetJustifyH("LEFT")
    if title.SetWordWrap then title:SetWordWrap(false) end
    local btn = T.Button(section, "", width or 240, DROPDOWN_FIELD_H, { history = false })
    RegisterSearchObject(btn, label, "dropdown", { anchor = title, values = values })
    btn._msuf2Title = title
    btn._msuf2ControlKind = "dropdown"
    btn._msuf2DropdownWheelManaged = true
    btn._msuf2DropdownSearchable = opts and opts.searchable
    btn:SetPoint("TOPLEFT", x, y - DROPDOWN_FIELD_OFFSET)
    btn.values = values or {}
    T.ApplyMenuFont(btn._msuf2Label, 0, "control")
    btn._msuf2Label:ClearAllPoints()
    btn._msuf2Label:SetPoint("LEFT", btn, "LEFT", DROPDOWN_FIELD_TEXT_LEFT, 0)
    btn._msuf2Label:SetPoint("RIGHT", btn, "RIGHT", DROPDOWN_FIELD_TEXT_RIGHT, 0)
    btn._msuf2Label:SetJustifyH("LEFT")
    if btn._msuf2Label.SetWordWrap then btn._msuf2Label:SetWordWrap(false) end
    StoreDropdownDefaultFont(btn._msuf2Label)
    btn._msuf2Chevron = PixelLayoutRegion(btn:CreateTexture(nil, "OVERLAY"))
    btn._msuf2Chevron:SetTexture(T.media.dropdownChevron)
    btn._msuf2Chevron:SetPoint("RIGHT", btn, "RIGHT", DROPDOWN_CHEVRON_RIGHT, 0)
    btn._msuf2Chevron:SetSize(12, 12)
    btn._msuf2Chevron:SetVertexColor(T.colors.muted[1], T.colors.muted[2], T.colors.muted[3], 0.95)
    btn._msuf2ChoiceBorderLeft, btn._msuf2ChoiceBorderAlpha = 9, 0.90
    function btn:SetValues(nextValues)
        self.values = nextValues or {}
        if type(M.RegisterSearchWidget) == "function" then
            local meta = self._msuf2SearchMeta or { label = self._msuf2SearchText,
                kind = "dropdown", anchor = self._msuf2Title }
            meta.values = self.values
            M.RegisterSearchWidget(self, meta)
        end
        self:SetValue(self.value)
    end
    function btn:SetValue(value)
        self.value = value
        local selectedItem, dynamic = FindDropdownItem(self, value)
        local icon = DropdownItemIcon(selectedItem)
        local statusbarTexture = DropdownItemStatusbarTexture(selectedItem)
        local barPreview = DropdownItemBarPreview(selectedItem)
        local sr, sg, sb, sa = DropdownItemSwatch(selectedItem)
        RestoreDropdownDefaultFont(self._msuf2Label)
        if selectedItem then
            self:SetText(DropdownItemText(selectedItem), true)
        else
            local item = FindDropdownItem(self, value)
            self:SetText(item and DropdownItemText(item) or tostring(value or ""))
        end
        if DropdownItemHasFontPreview(selectedItem) then ApplyDropdownItemFont(self._msuf2Label, selectedItem) end
        local rightInset = self._msuf2CompactValueInsets and -24 or DROPDOWN_FIELD_TEXT_RIGHT
        PaintDropdownChoice(self, self._msuf2Label, icon, sr, sg, sb, sa, rightInset, statusbarTexture, barPreview)
        local meta = self._msuf2SearchMeta
        if meta and dynamic then M.RegisterSearchWidget(self, meta) end
    end
    function btn:UseCompactValueInsets()
        self._msuf2CompactValueInsets = true
        self._msuf2Chevron:SetPoint("RIGHT", self, "RIGHT", -8, 0)
        if self.value ~= nil then self:SetValue(self.value) end
    end
    function btn:GetValue()
        return self.value
    end
    function btn:RefreshPreview()
        self:SetValue(self.value)
    end
    function btn:SetOnValueChanged(fn)
        self._msuf2OnValueChanged = fn
    end
    -- Row activation includes picking the current value.
    function btn:SetOnOptionSelected(fn)
        self._msuf2OnOptionSelected = fn
    end
    btn:EnableMouseWheel(false)
    btn:SetScript("OnClick", function(self)
        if CloseIfCombatBlocked() or IsDropdownClosingFor(self) then return end
        if dropdownOwner == self and dropdownFrame and dropdownFrame:IsShown() then
            CloseDropdown()
            return
        end
        CloseDropdown()
        self._msuf2DropdownListSelect = nil
        self._msuf2DropdownListValue = nil
        OpenDropdown(self, ResolveDropdownValues(self))
    end)
    btn:HookScript("OnHide", function(self)
        if dropdownOwner == self then CloseDropdown({ immediate = true }) end
    end)
    -- A field without a page tooltip shows its cut-short title or value here;
    -- M.AddTooltip owners (_msuf2TooltipTarget) append the value themselves.
    -- A disabled reason hooked later is added to this same tooltip.
    btn:HookScript("OnEnter", function(self)
        if self._msuf2TooltipTarget or dropdownOwner == self or not GameTooltip then return end
        local titleText, valueText = W.DropdownOverflowText(self)
        if not (titleText or valueText) then return end
        local heading = titleText or (self._msuf2Title and self._msuf2Title:GetText())
        if heading == nil or heading == "" then heading, valueText = valueText, nil end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(heading, 1, 1, 1, 1, true)
        if valueText then GameTooltip:AddLine(valueText, 0.80, 0.86, 1.00, true) end
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function(self)
        if not self._msuf2TooltipTarget then HideDropdownItemTooltip(self) end
    end)
    btn:SetScript("OnMouseWheel", function(self, delta)
        if dropdownOwner ~= self or not (dropdownFrame and dropdownFrame:IsShown()) then return end
        -- ForwardDropdownWheel inline: one hop less per wheel step.
        if not dropdownScroll then return end
        local handler = dropdownScroll:GetScript("OnMouseWheel")
        if handler then handler(dropdownScroll, delta) end
    end)
    return btn
end
