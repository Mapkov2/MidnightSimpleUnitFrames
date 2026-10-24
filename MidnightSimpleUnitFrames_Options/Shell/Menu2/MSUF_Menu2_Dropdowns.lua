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
local DROPDOWN_ROW_H = 24
local DROPDOWN_ICON_SIZE = 20
local DROPDOWN_ICON_LEFT = 12
local DROPDOWN_ICON_TEXT_LEFT = 36
local DROPDOWN_TEXTURE_PREVIEW_W = 72
local DROPDOWN_TEXTURE_PREVIEW_H = 12
local DROPDOWN_TEXTURE_TEXT_LEFT = 92
local DROPDOWN_BAR_PREVIEW_W = 132
local DROPDOWN_BAR_PREVIEW_H = 8
local DROPDOWN_BAR_PREVIEW_RIGHT = 24
local DROPDOWN_BAR_PREVIEW_TEXT_RIGHT = -(DROPDOWN_BAR_PREVIEW_W + DROPDOWN_BAR_PREVIEW_RIGHT + 42)
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
local function DropdownVisibleRows(owner, rowCount, preferred, rowHeight)
    preferred = min(rowCount or 0, preferred or 12)
    rowHeight = tonumber(rowHeight) or DROPDOWN_ROW_H
    local below, above = DropdownAvailableSpace(owner)
    if not below then return preferred, false end
    local preferredH = preferred * rowHeight + 4
    local openAbove = below < preferredH and above > below
    local maxSpace = openAbove and above or below
    local fit = floor((maxSpace - 4) / rowHeight)
    if fit > 0 then preferred = min(preferred, max(3, fit)) end
    return max(1, preferred), openAbove
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
function CloseDropdown(opts)
    local immediate = opts == true or (type(opts) == "table" and opts.immediate == true)
    if dropdownClosing and not dropdownOwner and not immediate then return end
    if HideDropdownItemTooltip then HideDropdownItemTooltip() end
    if FocusDropdownRow then FocusDropdownRow(nil) end
    local owner = dropdownOwner or dropdownClosingOwner
    dropdownClosing = true
    dropdownClosingOwner = owner
    dropdownOwner = nil
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
local function ShowDropdownItemTooltip(owner)
    local item = owner and owner._msuf2Item
    local body = DropdownItemTooltipField(item, "tooltip", "description")
    if not body or not GameTooltip then return end
    local title = DropdownItemTooltipField(item, "tooltipTitle") or DropdownItemText(item)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    GameTooltip:AddLine(body, 0.80, 0.86, 1.00, true)
    GameTooltip:Show()
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
    -- SharedMedia fonts use very different ascender/descender metrics. A one-pixel
    -- inset keeps the font-name preview inside both the 24 px rows and 22 px field.
    local size = max(8, ((d and d[2]) or 14) - 1)
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
local function HideBarPreviewLane(lane)
    if not lane then return end
    lane.host:Hide()
    lane.surface.root:Deactivate()
end

local function HideDropdownBarPreview(frame)
    local preview = frame and frame._msuf2BarPreview
    if not preview then return end
    for i = 1, #preview do HideBarPreviewLane(preview[i]) end
end
local function AddDropdownBarPreviewLane(frame)
    local host = PixelLayoutRegion(CreateFrame("Frame", nil, frame))
    host:SetSize(DROPDOWN_BAR_PREVIEW_W, DROPDOWN_BAR_PREVIEW_H)
    local surface = M.PreviewHelpers.NewRuntimeUnitSurface(host, "player", { hp = .68 })
    surface.fit = false
    return { host = host, surface = surface }
end
local function AddDropdownBarPreviewAssets(frame)
    local preview = frame._msuf2BarPreview
    if not preview then
        preview = { AddDropdownBarPreviewLane(frame), AddDropdownBarPreviewLane(frame) }
        frame._msuf2BarPreview = preview
    end
    return preview
end
local function PaintDropdownBarPreviewLane(frame, lane, config, reverse, y)
    local host = lane.host
    host:ClearAllPoints()
    host:SetPoint("RIGHT", frame, "RIGHT", -DROPDOWN_BAR_PREVIEW_RIGHT, y or 0)
    host:Show()
    lane.surface.configure = function(spec)
        spec.width, spec.height = DROPDOWN_BAR_PREVIEW_W, DROPDOWN_BAR_PREVIEW_H
        spec.health.reverse, spec.health.topInset = reverse, 0
        spec.health.texture, spec.health.backgroundTexture = config.healthTexture, config.backgroundTexture
        spec.power.enabled = false
        local p, c = spec.prediction, config.overlayColor or { 1, 1, 1, .82 }
        p.enabled, p.test = true, false
        p.heal, p.absorb, p.healAbsorb = config.category == "heal", config.category == "absorb", config.category == "negative"
        p.healAnchorMode, p.absorbAnchorMode, p.healAbsorbAnchorMode = config.mode, config.mode, config.mode
        p.texture, p.absorbTexture, p.healAbsorbTexture = config.overlayTexture, config.overlayTexture, config.overlayTexture
        p.healR, p.healG, p.healB, p.healA = c[1], c[2], c[3], c[4]
        p.absorbR, p.absorbG, p.absorbB, p.absorbA = c[1], c[2], c[3], c[4]
        p.healAbsorbR, p.healAbsorbG, p.healAbsorbB, p.healAbsorbA = c[1], c[2], c[3], c[4]
        p.fullHealthAbsorbStripe = config.showAbsorbEdgeGlow == true
    end
    local amount = tonumber(config.overlayFraction) or .2
    local sample = { hp = tonumber(config.healthFraction) or .68,
        incoming = config.category == "heal" and amount or 0,
        absorb = config.category == "absorb" and amount or 0,
        healAbsorb = config.category == "negative" and amount or 0 }
    local rendered = lane.surface:Refresh(sample)
    if rendered then
        lane.surface.scene:SetLayerFilter({ nameText = false, hpText = false, power = false, powerText = false,
            portrait = false, status = false, auras = false, dispelOverlay = false, dispelSymbol = false, texLayer = false })
    end
end

local function PaintDropdownBarPreview(frame, config)
    if not (frame and type(config) == "table") then
        HideDropdownBarPreview(frame)
        return
    end
    local preview = AddDropdownBarPreviewAssets(frame)
    local frameHeight = frame.GetHeight and frame:GetHeight() or 0
    local dualDirection = config.dualDirection == true and frameHeight >= 30
    PaintDropdownBarPreviewLane(frame, preview[1], config, false, dualDirection and 7 or 0)
    if dualDirection then
        PaintDropdownBarPreviewLane(frame, preview[2], config, true, -7)
    else
        HideBarPreviewLane(preview[2])
    end
end
-- The leading-edge parts of a choice row or field (icon, swatch with its border,
-- texture preview with its border); each kind of choice hides the others. Every
-- dropdown repaint runs this, so the hides are written out instead of looped.
local function PaintDropdownChoice(frame, label, icon, sr, sg, sb, sa, rightInset, statusbarTexture, barPreview)
    local left = 12
    if barPreview then
        if frame._msuf2Icon then frame._msuf2Icon:Hide() end
        if frame._msuf2Swatch then frame._msuf2Swatch:Hide() end
        if frame._msuf2SwatchBorder then frame._msuf2SwatchBorder:Hide() end
        if frame._msuf2TexturePreview then frame._msuf2TexturePreview:Hide() end
        if frame._msuf2TexturePreviewBorder then frame._msuf2TexturePreviewBorder:Hide() end
        PaintDropdownBarPreview(frame, barPreview)
        rightInset = min(rightInset or -8, DROPDOWN_BAR_PREVIEW_TEXT_RIGHT)
    else
        HideDropdownBarPreview(frame)
        if statusbarTexture and frame._msuf2TexturePreview then
            if frame._msuf2Icon then frame._msuf2Icon:Hide() end
            if frame._msuf2Swatch then frame._msuf2Swatch:Hide() end
            if frame._msuf2SwatchBorder then frame._msuf2SwatchBorder:Hide() end
            if frame._msuf2TexturePreviewBorder then frame._msuf2TexturePreviewBorder:Show() end
            frame._msuf2TexturePreview:SetTexture(statusbarTexture)
            frame._msuf2TexturePreview:SetVertexColor(1, 1, 1, 1)
            frame._msuf2TexturePreview:Show()
            left = DROPDOWN_TEXTURE_TEXT_LEFT
        elseif icon then
            if frame._msuf2TexturePreview then frame._msuf2TexturePreview:Hide() end
            if frame._msuf2TexturePreviewBorder then frame._msuf2TexturePreviewBorder:Hide() end
            if frame._msuf2Swatch then frame._msuf2Swatch:Hide() end
            if frame._msuf2SwatchBorder then frame._msuf2SwatchBorder:Hide() end
            SetDropdownIconTexture(frame._msuf2Icon, icon)
            left = DROPDOWN_ICON_TEXT_LEFT
        elseif sr then
            if frame._msuf2TexturePreview then frame._msuf2TexturePreview:Hide() end
            if frame._msuf2TexturePreviewBorder then frame._msuf2TexturePreviewBorder:Hide() end
            if frame._msuf2Icon then frame._msuf2Icon:Hide() end
            frame._msuf2Swatch:SetColorTexture(sr, sg, sb, sa or 1)
            frame._msuf2Swatch:Show()
            frame._msuf2SwatchBorder:Show()
            left = 34
        else
            if frame._msuf2TexturePreview then frame._msuf2TexturePreview:Hide() end
            if frame._msuf2TexturePreviewBorder then frame._msuf2TexturePreviewBorder:Hide() end
            if frame._msuf2Icon then frame._msuf2Icon:Hide() end
            if frame._msuf2Swatch then frame._msuf2Swatch:Hide() end
            if frame._msuf2SwatchBorder then frame._msuf2SwatchBorder:Hide() end
        end
    end
    label:ClearAllPoints()
    label:SetPoint("LEFT", frame, "LEFT", left, 0)
    label:SetPoint("RIGHT", frame, "RIGHT", rightInset or -8, 0)
end
local function AddDropdownChoiceAssets(frame, borderLeft, borderAlpha)
    local swatchBorder = PixelLayoutRegion(frame:CreateTexture(nil, "ARTWORK"))
    swatchBorder:SetPoint("LEFT", frame, "LEFT", borderLeft or 12, 0)
    swatchBorder:SetSize(16, 16)
    swatchBorder:SetColorTexture(0, 0, 0, borderAlpha or 0.85)
    swatchBorder:Hide()
    frame._msuf2SwatchBorder = swatchBorder
    local swatch = PixelLayoutRegion(frame:CreateTexture(nil, "OVERLAY"))
    swatch:SetPoint("CENTER", swatchBorder, "CENTER", 0, 0)
    swatch:SetSize(12, 12)
    swatch:Hide()
    frame._msuf2Swatch = swatch
    local icon = PixelLayoutRegion(frame:CreateTexture(nil, "ARTWORK"))
    icon:SetPoint("LEFT", frame, "LEFT", DROPDOWN_ICON_LEFT, 0)
    icon:SetSize(DROPDOWN_ICON_SIZE, DROPDOWN_ICON_SIZE)
    icon:Hide()
    frame._msuf2Icon = icon
    local texturePreviewBorder = PixelLayoutRegion(frame:CreateTexture(nil, "ARTWORK"))
    texturePreviewBorder:SetPoint("LEFT", frame, "LEFT", borderLeft or 12, 0)
    texturePreviewBorder:SetSize(DROPDOWN_TEXTURE_PREVIEW_W + 2, DROPDOWN_TEXTURE_PREVIEW_H + 2)
    texturePreviewBorder:SetColorTexture(0, 0, 0, borderAlpha or 0.85)
    texturePreviewBorder:Hide()
    frame._msuf2TexturePreviewBorder = texturePreviewBorder
    local texturePreview = PixelLayoutRegion(frame:CreateTexture(nil, "OVERLAY"))
    texturePreview:SetPoint("CENTER", texturePreviewBorder, "CENTER", 0, 0)
    texturePreview:SetSize(DROPDOWN_TEXTURE_PREVIEW_W, DROPDOWN_TEXTURE_PREVIEW_H)
    texturePreview:Hide()
    frame._msuf2TexturePreview = texturePreview
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
        local visible = dropdownFrame:GetHeight() - 4
        if top < offset then SetDropdownScroll(top)
        elseif top + dropdownActiveRowHeight > offset + visible then
            SetDropdownScroll(top + dropdownActiveRowHeight - visible)
        end
        HideDropdownItemTooltip()
        ShowDropdownItemTooltip(row)
    end
end
DropdownKeyDown = function(self, key)
    local handled = dropdownOwner and (key == "ESCAPE" or key == "UP" or key == "DOWN"
        or key == "HOME" or key == "END" or key == "ENTER" or key == "SPACE")
    if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(not handled) end
    if not handled then return end
    if key == "ESCAPE" then
        CloseDropdown({ immediate = true })
        return
    end
    if key == "ENTER" or key == "SPACE" then
        local row = dropdownRows[self._msuf2KeyboardIndex or 0]
        if row then row:GetScript("OnClick")(row) end
        return
    end
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
    AddDropdownChoiceAssets(row, 10, 0.85)
    local text = T.Font(row, "GameFontHighlight", "", T.colors.text)
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
        if self._msuf2DropdownDisabled or CloseIfCombatBlocked() then return end
        local owner = self._msuf2Owner
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
    end)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", ForwardDropdownWheel)
    dropdownRows[index] = row
    return row
end
local function OpenDropdown(owner, valuesTable)
    EnsureDropdownFrame()
    RefreshDropdownMenuFonts()
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
    local visible, openAbove = DropdownVisibleRows(owner, #valuesTable,
        (hasIcons or hasStatusbarPreviews or hasBarPreviews) and 12 or 14, rowHeight)
    owner._msuf2DropdownOpenAbove = openAbove
    local listHeight = visible * rowHeight + 4
    local totalHeight = #valuesTable * rowHeight
    local needsScroll = #valuesTable > visible
    dropdownFrame:SetSize(rowWidth + (needsScroll and 20 or 4), listHeight)
    dropdownChild:SetSize(rowWidth, totalHeight)
    dropdownScroll:ClearAllPoints()
    dropdownScroll:SetPoint("TOPLEFT", dropdownFrame, "TOPLEFT", 2, -2)
    dropdownScroll:SetPoint("BOTTOMRIGHT", dropdownFrame, "BOTTOMRIGHT", needsScroll and -16 or -2, 2)
    if dropdownSlider then
        dropdownSlider:SetShown(needsScroll)
        dropdownSlider:SetMinMaxValues(0, math.max(0, totalHeight - (listHeight - 4)))
        local visibleRatio = (listHeight - 4) / math.max(totalHeight, 1)
        local thumbH = floor(max(34, min(listHeight - 16, (listHeight - 4) * visibleRatio)) + 0.5)
        local thumb = dropdownSlider._msuf2Thumb
        if thumb and thumb.SetHeight then thumb:SetHeight(thumbH) end
        PaintDropdownScrollbar(dropdownSlider._msuf2Hover)
    end
    local selectedIndex = 1
    dropdownFrame._msuf2RowCount = #valuesTable
    for i = 1, #valuesTable do
        local item = valuesTable[i]
        local row = DropdownRow(i)
        local value = DropdownItemValue(item)
        local icon = DropdownItemIcon(item)
        local statusbarTexture = DropdownItemStatusbarTexture(item)
        local barPreview = DropdownItemBarPreview(item)
        local selectedValue = owner._msuf2DropdownListValue
        local isHeader = DropdownItemHeader(item)
        local disabled = DropdownItemDisabled(item)
        if selectedValue == nil then selectedValue = owner.value end
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
        row._msuf2Selected:SetShown((not isHeader) and value == selectedValue)
        if (not isHeader) and value == selectedValue then selectedIndex = i end
        RestoreDropdownDefaultFont(row._msuf2Text)
        -- DropdownItemText already translated the entry (or kept it raw).
        T.SetTranslatedText(row._msuf2Text, DropdownItemText(item))
        if row._msuf2Text.SetTextColor then
            local c = isHeader and (T.colors.accent2 or T.colors.accent or T.colors.text) or (disabled and (T.colors.dim or T.colors.muted) or T.colors.text)
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
    dropdownOwner = owner
    if dropdownFrame.SetPropagateKeyboardInput then dropdownFrame:SetPropagateKeyboardInput(true) end
    SetDropdownOwnerMouseWheel(owner, true)
    ShowDropdownFocus(owner)
    if dropdownFrame.EnableMouse then dropdownFrame:EnableMouse(true) end
    dropdownFrame:SetAlpha(0)
    dropdownFrame:Show()
    dropdownFrame._msuf2AnchorKey = nil
    PositionDropdown(owner)
    SetDropdownScroll((selectedIndex > visible) and ((selectedIndex - visible) * rowHeight) or 0)
    FocusDropdownRow(selectedIndex)
    PlayMotion(dropdownFrame, "dropdownIn", { fromAlpha = 0 })
    ShowForeverDropdown(dropdownRows[selectedIndex])
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
    if type(valuesTable) == "function" then
        local resolved = valuesTable()
        valuesTable = resolved or nil
    end
    if type(valuesTable) ~= "table" then valuesTable = {} end
    return valuesTable
end
local function FindDropdownItem(owner, value)
    local valuesTable = ResolveDropdownValues(owner)
    for i = 1, #valuesTable do
        local item = valuesTable[i]
        if DropdownItemValue(item) == value then return item end
    end
end
function W.Dropdown(section, label, values, width)
    local x, y = NextRow(section, 48)
    local title = T.Font(section, "GameFontHighlightSmall", label or "", T.colors.text, "control")
    SetSearchText(title, label)
    title:SetPoint("TOPLEFT", x, y)
    local btn = T.Button(section, "", width or 240, 22, { history = false })
    RegisterSearchObject(btn, label, "dropdown", { anchor = title, values = values })
    btn._msuf2Title = title
    btn._msuf2ControlKind = "dropdown"
    btn._msuf2DropdownWheelManaged = true
    btn:SetPoint("TOPLEFT", x, y - 24)
    btn.values = values or {}
    btn._msuf2Label:ClearAllPoints()
    btn._msuf2Label:SetPoint("LEFT", btn, "LEFT", 12, 0)
    btn._msuf2Label:SetPoint("RIGHT", btn, "RIGHT", -28, 0)
    btn._msuf2Label:SetJustifyH("LEFT")
    StoreDropdownDefaultFont(btn._msuf2Label)
    btn._msuf2Chevron = PixelLayoutRegion(btn:CreateTexture(nil, "OVERLAY"))
    btn._msuf2Chevron:SetTexture(T.media.dropdownChevron)
    btn._msuf2Chevron:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    btn._msuf2Chevron:SetSize(12, 12)
    btn._msuf2Chevron:SetVertexColor(T.colors.muted[1], T.colors.muted[2], T.colors.muted[3], 0.95)
    AddDropdownChoiceAssets(btn, 9, 0.90)
    function btn:SetValues(nextValues)
        self.values = nextValues or {}
        if type(M.RegisterSearchWidget) == "function" then
            M.RegisterSearchWidget(self, {
                label = self._msuf2SearchText,
                kind = "dropdown",
                anchor = self._msuf2Title,
                values = self.values,
            })
        end
        self:SetValue(self.value)
    end
    function btn:SetValue(value)
        self.value = value
        local selectedItem = FindDropdownItem(self, value)
        local icon = DropdownItemIcon(selectedItem)
        local statusbarTexture = DropdownItemStatusbarTexture(selectedItem)
        local barPreview = DropdownItemBarPreview(selectedItem)
        local sr, sg, sb, sa = DropdownItemSwatch(selectedItem)
        PaintDropdownChoice(self, self._msuf2Label, icon, sr, sg, sb, sa, -26, statusbarTexture, barPreview)
        RestoreDropdownDefaultFont(self._msuf2Label)
        if selectedItem then
            self:SetText(DropdownItemText(selectedItem), true)
        else
            local item = FindDropdownItem(self, value)
            self:SetText(item and DropdownItemText(item) or tostring(value or ""))
        end
        if DropdownItemHasFontPreview(selectedItem) then ApplyDropdownItemFont(self._msuf2Label, selectedItem) end
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
    btn:SetScript("OnMouseWheel", function(self, delta)
        if dropdownOwner ~= self or not (dropdownFrame and dropdownFrame:IsShown()) then return end
        -- ForwardDropdownWheel inline: one hop less per wheel step.
        if not dropdownScroll then return end
        local handler = dropdownScroll:GetScript("OnMouseWheel")
        if handler then handler(dropdownScroll, delta) end
    end)
    return btn
end
