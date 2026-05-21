local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local T = M.Theme
local W = M.Widgets or {}
M.Widgets = W

local floor = math.floor
local max = math.max
local min = math.min
local MSUF_SetIconTexture = _G.MSUF_SetIconTexture

local function Tr(text)
    if type(text) ~= "string" then return text end
    local fn = M.Tr or ns.TR
    if type(fn) == "function" then
        local translated = fn(text)
        if translated ~= nil then return translated end
    end
    local locale = ns.L or _G.MSUF_L
    if type(locale) == "table" and locale[text] ~= nil then return locale[text] end
    return text
end

local function SetSearchText(object, text)
    if object and text ~= nil then object._msuf2SearchText = text end
    return object
end

local function RegisterSearchObject(object, label, kind, opts)
    SetSearchText(object, label)
    if object and type(M.RegisterSearchWidget) == "function" then
        opts = opts or {}
        opts.label = opts.label or label
        opts.kind = opts.kind or kind
        M.RegisterSearchWidget(object, opts)
    end
    return object
end

local function NextRow(section, height)
    local x = section._msuf2ContentX or 14
    local y = section._msuf2CursorY or -38
    section._msuf2CursorY = y - (height or 46)
    return x, y
end

local dropdownFrame, dropdownScroll, dropdownChild, dropdownOwner, dropdownSlider
local dropdownRows = {}
local DROPDOWN_ROW_H = 22
local DROPDOWN_SCROLLBAR_W = 10
local CloseDropdown

local function PixelBarTexture(texture)
    if not texture then return texture end
    texture:SetTexture("Interface\\Buttons\\WHITE8X8")
    if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(true) end
    if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
    return texture
end

local function PaintDropdownScrollbar(hover)
    local bar = dropdownSlider
    if not bar then return end

    local shown = bar.IsShown and bar:IsShown()
    local alpha = shown and 1 or 0
    local track = bar._msuf2Track
    local edge = bar._msuf2TrackEdge
    local thumb = bar._msuf2Thumb
    local soft = T.colors.borderSoft or T.colors.border or { 0.12, 0.14, 0.26 }
    local thumbBase = bar._msuf2ThumbBase or { 0.240, 0.300, 0.430 }
    local thumbHover = bar._msuf2ThumbHover or { 0.320, 0.420, 0.560 }

    if track and track.SetColorTexture then
        track:SetColorTexture(0.025, 0.030, 0.060, (hover and 0.98 or 0.82) * alpha)
    end
    if edge and edge.SetColorTexture then
        edge:SetColorTexture(soft[1], soft[2], soft[3], (hover and 0.62 or 0.38) * alpha)
    end
    if thumb and thumb.SetColorTexture then
        local c = hover and thumbHover or thumbBase
        thumb:SetColorTexture(c[1], c[2], c[3], (hover and 0.90 or 0.68) * alpha)
    end
end

local function SetDropdownOwnerMouseWheel(owner, enabled)
    if owner and owner._msuf2DropdownWheelManaged and owner.EnableMouseWheel then
        owner:EnableMouseWheel(enabled and true or false)
    end
end

local function DropdownMaxScroll()
    if not (dropdownScroll and dropdownChild) then return 0 end
    return math.max(0, (dropdownChild:GetHeight() or 0) - (dropdownScroll:GetHeight() or 0))
end

local function SetDropdownScroll(value)
    if not dropdownScroll then return end
    local maxScroll = DropdownMaxScroll()
    value = tonumber(value) or 0
    if value < 0 then value = 0 elseif value > maxScroll then value = maxScroll end
    dropdownScroll:SetVerticalScroll(value)
    if dropdownSlider then
        dropdownSlider._msuf2Refreshing = true
        dropdownSlider:SetMinMaxValues(0, maxScroll)
        dropdownSlider:SetValue(value)
        dropdownSlider._msuf2Refreshing = nil
    end
end

local function IsDescendantOf(frame, ancestor)
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
    local screenTop = _G.UIParent and _G.UIParent.GetTop and _G.UIParent:GetTop()
    local screenBottom = _G.UIParent and _G.UIParent.GetBottom and _G.UIParent:GetBottom()
    if not (ownerTop and ownerBottom and screenTop and screenBottom) then return nil, nil end
    return max(0, ownerBottom - screenBottom - 10), max(0, screenTop - ownerTop - 10)
end

local function DropdownVisibleRows(owner, rowCount, preferred)
    preferred = min(rowCount or 0, preferred or 12)
    local below, above = DropdownAvailableSpace(owner)
    if not below then return preferred, false end

    local preferredH = preferred * DROPDOWN_ROW_H + 4
    local openAbove = below < preferredH and above > below
    local maxSpace = openAbove and above or below
    local fit = floor((maxSpace - 4) / DROPDOWN_ROW_H)
    if fit > 0 then
        preferred = min(preferred, max(3, fit))
    end
    return max(1, preferred), openAbove
end

local function PositionDropdown(owner)
    if not (dropdownFrame and owner and dropdownFrame:IsShown()) then return false end
    if not DropdownOwnerVisible(owner) then
        CloseDropdown()
        return false
    end

    dropdownFrame:ClearAllPoints()
    local frameH = dropdownFrame:GetHeight() or 0
    local frameW = dropdownFrame:GetWidth() or 0
    local ownerBottom = owner.GetBottom and owner:GetBottom()
    local screenBottom = _G.UIParent and _G.UIParent.GetBottom and _G.UIParent:GetBottom() or 0
    local openAbove = owner._msuf2DropdownOpenAbove
    if openAbove == nil then
        openAbove = ownerBottom and ownerBottom - frameH - 2 < screenBottom + 8
    end

    local ownerLeft = owner.GetLeft and owner:GetLeft()
    local screenRight = _G.UIParent and _G.UIParent.GetRight and _G.UIParent:GetRight()
    local anchorRight = ownerLeft and screenRight and ownerLeft + frameW > screenRight - 8
    if openAbove and anchorRight then
        dropdownFrame:SetPoint("BOTTOMRIGHT", owner, "TOPRIGHT", 0, 2)
    elseif openAbove then
        dropdownFrame:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 2)
    elseif anchorRight then
        dropdownFrame:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -2)
    else
        dropdownFrame:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    end
    return true
end

function CloseDropdown()
    local owner = dropdownOwner
    if dropdownFrame then dropdownFrame:Hide() end
    if owner then
        SetDropdownOwnerMouseWheel(owner, false)
        owner._msuf2DropdownListSelect = nil
        owner._msuf2DropdownListValue = nil
        owner._msuf2DropdownOpenAbove = nil
    end
    dropdownOwner = nil
end
W.CloseDropdown = CloseDropdown

local function EnsureDropdownFrame()
    if dropdownFrame then return dropdownFrame end
    local parent = _G.UIParent
    dropdownFrame = CreateFrame("Frame", "MSUF2NativeDropdownList", parent, T.Template and T.Template() or nil)
    dropdownFrame:SetFrameStrata("TOOLTIP")
    dropdownFrame:SetToplevel(true)
    dropdownFrame:EnableMouse(true)
    if dropdownFrame.SetClampedToScreen then dropdownFrame:SetClampedToScreen(true) end
    T.ApplyBackdrop(dropdownFrame, { 0.010, 0.010, 0.018, 0.985 }, { 0.140, 0.220, 0.600, 0.88 })
    dropdownFrame:Hide()

    dropdownScroll = CreateFrame("ScrollFrame", "MSUF2NativeDropdownScroll", dropdownFrame)
    dropdownScroll:SetPoint("TOPLEFT", dropdownFrame, "TOPLEFT", 2, -2)
    dropdownScroll:SetPoint("BOTTOMRIGHT", dropdownFrame, "BOTTOMRIGHT", -18, 2)
    dropdownScroll:EnableMouseWheel(true)
    dropdownScroll:SetScript("OnMouseWheel", function(self, delta)
        local nextScroll = (self:GetVerticalScroll() or 0) - (delta or 0) * DROPDOWN_ROW_H * 3
        SetDropdownScroll(nextScroll)
    end)

    dropdownChild = CreateFrame("Frame", nil, dropdownScroll)
    dropdownScroll:SetScrollChild(dropdownChild)

    dropdownSlider = CreateFrame("Slider", nil, dropdownFrame)
    dropdownSlider:SetOrientation("VERTICAL")
    dropdownSlider:SetWidth(DROPDOWN_SCROLLBAR_W)
    dropdownSlider:SetMinMaxValues(0, 1)
    dropdownSlider:SetValueStep(1)
    if dropdownSlider.SetObeyStepOnDrag then dropdownSlider:SetObeyStepOnDrag(false) end
    if dropdownSlider.EnableMouse then dropdownSlider:EnableMouse(true) end
    dropdownSlider:SetPoint("TOPRIGHT", dropdownFrame, "TOPRIGHT", -6, -8)
    dropdownSlider:SetPoint("BOTTOMRIGHT", dropdownFrame, "BOTTOMRIGHT", -6, 8)
    local track = PixelBarTexture(dropdownSlider:CreateTexture(nil, "BACKGROUND"))
    track:SetPoint("TOP", dropdownSlider, "TOP", 0, 0)
    track:SetPoint("BOTTOM", dropdownSlider, "BOTTOM", 0, 0)
    track:SetWidth(2)
    dropdownSlider._msuf2Track = track
    local trackEdge = PixelBarTexture(dropdownSlider:CreateTexture(nil, "BORDER"))
    trackEdge:SetPoint("TOPLEFT", track, "TOPRIGHT", 1, 0)
    trackEdge:SetPoint("BOTTOMLEFT", track, "BOTTOMRIGHT", 1, 0)
    trackEdge:SetWidth(1)
    dropdownSlider._msuf2TrackEdge = trackEdge
    local thumb = PixelBarTexture(dropdownSlider:CreateTexture(nil, "OVERLAY"))
    thumb:SetSize(5, 34)
    dropdownSlider:SetThumbTexture(thumb)
    dropdownSlider._msuf2Thumb = thumb
    dropdownSlider._msuf2ThumbBase = { 0.240, 0.300, 0.430 }
    dropdownSlider._msuf2ThumbHover = { 0.320, 0.420, 0.560 }
    dropdownSlider:SetScript("OnValueChanged", function(self, value)
        if self._msuf2Refreshing then return end
        if dropdownScroll then dropdownScroll:SetVerticalScroll(value or 0) end
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
    dropdownSlider:SetScript("OnMouseWheel", function(_, delta)
        if dropdownScroll then
            SetDropdownScroll((dropdownScroll:GetVerticalScroll() or 0) - (delta or 0) * DROPDOWN_ROW_H * 3)
        end
    end)
    dropdownSlider:Hide()
    PaintDropdownScrollbar(false)

    dropdownFrame:EnableMouseWheel(true)
    dropdownFrame:SetScript("OnMouseWheel", function(_, delta)
        if dropdownScroll then
            SetDropdownScroll((dropdownScroll:GetVerticalScroll() or 0) - (delta or 0) * DROPDOWN_ROW_H * 3)
        end
    end)

    dropdownFrame:SetScript("OnHide", function()
        SetDropdownOwnerMouseWheel(dropdownOwner, false)
        dropdownOwner = nil
    end)
    dropdownFrame:SetScript("OnUpdate", function()
        if dropdownOwner then PositionDropdown(dropdownOwner) end
    end)
    return dropdownFrame
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

local function DropdownItemIcon(item)
    if type(item) ~= "table" then return nil end
    if item.icon or item.texture then return item.icon or item.texture end
    return (type(item.swatch) == "string") and item.swatch or nil
end

local function DropdownColorTuple(color)
    if type(color) == "function" then color = color() end
    if type(color) ~= "table" then return nil end
    local r = color.r or color[1]
    local g = color.g or color[2]
    local b = color.b or color[3]
    local a = color.a or color[4] or 1
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
        return r, g, b, a
    end
    return nil
end

local function DropdownItemSwatch(item)
    if type(item) ~= "table" then return nil end
    return DropdownColorTuple(item.swatchColor or item.color or item.colorPreview or item.swatch)
end

local function DropdownItemDisabled(item)
    if type(item) ~= "table" then return false end
    local disabled = item.disabled
    if type(disabled) == "function" then disabled = disabled(item) end
    if disabled ~= nil then return disabled and true or false end
    local enabled = item.enabled
    if type(enabled) == "function" then enabled = enabled(item) end
    return enabled == false
end

local function StoreDropdownDefaultFont(fs)
    if not (fs and fs.GetFont) then return end
    local ok, font, size, flags = pcall(fs.GetFont, fs)
    if ok and font and size then
        fs._msuf2DropdownDefaultFont = { font, size, flags or "" }
    end
end

local function RestoreDropdownDefaultFont(fs)
    local d = fs and fs._msuf2DropdownDefaultFont
    if d and fs.SetFont then
        pcall(fs.SetFont, fs, d[1], d[2], d[3] or "")
    elseif fs and fs.SetFontObject then
        pcall(fs.SetFontObject, fs, GameFontHighlight)
    end
end

local function ApplyDropdownItemFont(fs, item)
    if not fs then return end
    if type(item) ~= "table" then
        RestoreDropdownDefaultFont(fs)
        return
    end
    local d = fs._msuf2DropdownDefaultFont
    local size = (d and d[2]) or 14
    local fontKey = item.fontKey or item.fontPreviewKey
    local fontPath = item.fontPath or item.font
    if (type(fontPath) ~= "string" or fontPath == "") and type(fontKey) == "string" and fontKey ~= "" then
        local getPath = _G.MSUF_ResolveFontKeyPath or _G.MSUF_GetFontPathForKey or (ns and ns.MSUF_GetFontPathForKey)
        if type(getPath) == "function" then
            fontPath = getPath(fontKey)
        end
    end
    local safeSetFont = _G.MSUF_SetFontSafe or (ns and ns.Util and ns.Util.SetFontSafe)
    if type(safeSetFont) == "function" and type(fontPath) == "string" and fontPath ~= "" then
        local ok = safeSetFont(fs, fontPath, size, "", fontKey)
        if ok then return end
    end
    local fontObject = item.fontObject or item.fontPreviewObject
    if fontObject and fs.SetFontObject then
        local ok = pcall(fs.SetFontObject, fs, fontObject)
        if ok then return end
    end
    if type(fontPath) == "string" and fontPath ~= "" and fs.SetFont then
        local ok = pcall(fs.SetFont, fs, fontPath, size, "")
        if ok then return end
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

local function DropdownRow(index)
    local row = dropdownRows[index]
    if row then return row end
    row = CreateFrame("Button", nil, dropdownChild)
    row:SetHeight(DROPDOWN_ROW_H)
    row:EnableMouse(true)
    row:RegisterForClicks("AnyUp")

    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.18)

    local selected = row:CreateTexture(nil, "OVERLAY")
    selected:SetPoint("LEFT", row, "LEFT", 2, 0)
    selected:SetSize(2, DROPDOWN_ROW_H - 5)
    selected:SetColorTexture(T.colors.accent2[1], T.colors.accent2[2], T.colors.accent2[3], 0.95)
    selected:Hide()
    row._msuf2Selected = selected

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("LEFT", row, "LEFT", 10, 0)
    icon:SetSize(80, 12)
    icon:Hide()
    row._msuf2Icon = icon

    local swatchBorder = row:CreateTexture(nil, "ARTWORK")
    swatchBorder:SetPoint("LEFT", row, "LEFT", 10, 0)
    swatchBorder:SetSize(16, 16)
    swatchBorder:SetColorTexture(0, 0, 0, 0.85)
    swatchBorder:Hide()
    row._msuf2SwatchBorder = swatchBorder

    local swatch = row:CreateTexture(nil, "OVERLAY")
    swatch:SetPoint("CENTER", swatchBorder, "CENTER", 0, 0)
    swatch:SetSize(12, 12)
    swatch:Hide()
    row._msuf2Swatch = swatch

    local text = T.Font(row, "GameFontHighlight", "", T.colors.text)
    text:SetPoint("LEFT", row, "LEFT", 10, 0)
    text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    text:SetJustifyH("LEFT")
    StoreDropdownDefaultFont(text)
    row._msuf2Text = text

    local fontPreview = T.Font(row, "GameFontHighlightSmall", "AaBbCc", T.colors.muted)
    fontPreview:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    fontPreview:SetWidth(76)
    fontPreview:SetJustifyH("RIGHT")
    StoreDropdownDefaultFont(fontPreview)
    fontPreview:Hide()
    row._msuf2FontPreview = fontPreview

    row:SetScript("OnClick", function(self)
        if self._msuf2DropdownDisabled then return end
        if M.BlockCombatAction and M.BlockCombatAction() then
            CloseDropdown()
            return
        end
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
        CloseDropdown()
    end)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta)
        if dropdownScroll then
            local handler = dropdownScroll:GetScript("OnMouseWheel")
            if handler then handler(dropdownScroll, delta) end
        end
    end)

    dropdownRows[index] = row
    return row
end

local function OpenDropdown(owner, valuesTable)
    EnsureDropdownFrame()
    valuesTable = (type(valuesTable) == "table") and valuesTable or {}
    if #valuesTable == 0 then return end

    local hasIcons = false
    for i = 1, #valuesTable do
        if DropdownItemIcon(valuesTable[i]) then
            hasIcons = true
            break
        end
    end

    local ownerWidth = (owner.GetWidth and owner:GetWidth()) or 240
    local rowWidth = math.max(ownerWidth, hasIcons and 300 or 180)
    local visible, openAbove = DropdownVisibleRows(owner, #valuesTable, hasIcons and 12 or 14)
    owner._msuf2DropdownOpenAbove = openAbove
    local listHeight = visible * DROPDOWN_ROW_H + 4
    local totalHeight = #valuesTable * DROPDOWN_ROW_H
    local needsScroll = #valuesTable > visible

    dropdownFrame:SetSize(rowWidth + (needsScroll and 18 or 4), listHeight)
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
    for i = 1, #valuesTable do
        local item = valuesTable[i]
        local row = DropdownRow(i)
        local value = DropdownItemValue(item)
        local icon = DropdownItemIcon(item)
        local selectedValue = owner._msuf2DropdownListValue
        local disabled = DropdownItemDisabled(item)
        if selectedValue == nil then selectedValue = owner.value end
        row._msuf2Owner = owner
        row._msuf2Value = value
        row._msuf2Item = item
        row._msuf2DropdownDisabled = disabled
        if row.SetAlpha then row:SetAlpha(disabled and 0.45 or 1) end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", dropdownChild, "TOPLEFT", 0, -((i - 1) * DROPDOWN_ROW_H))
        row:SetWidth(rowWidth)
        row._msuf2Selected:SetShown(value == selectedValue)
        if value == selectedValue then selectedIndex = i end
        RestoreDropdownDefaultFont(row._msuf2Text)
        row._msuf2Text:SetText(DropdownItemText(item))
        if row._msuf2Text.SetTextColor then
            local c = disabled and (T.colors.dim or T.colors.muted) or T.colors.text
            row._msuf2Text:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        end
        local showFontPreview = DropdownItemHasFontPreview(item)
        row._msuf2FontPreview:SetShown(showFontPreview)
        if showFontPreview then
            row._msuf2FontPreview:SetText("AaBbCc")
            ApplyDropdownItemFont(row._msuf2FontPreview, item)
        else
            RestoreDropdownDefaultFont(row._msuf2FontPreview)
        end
        local rightInset = showFontPreview and -88 or -6
        local sr, sg, sb, sa = DropdownItemSwatch(item)
        if icon then
            if type(MSUF_SetIconTexture) == "function" then
                MSUF_SetIconTexture(row._msuf2Icon, icon, "")
            else
                row._msuf2Icon:SetTexture(icon)
            end
            row._msuf2Icon:SetTexCoord(0, 1, 0, 1)
            row._msuf2Icon:SetVertexColor(1, 1, 1, 1)
            row._msuf2Icon:Show()
            row._msuf2Swatch:Hide()
            row._msuf2SwatchBorder:Hide()
            row._msuf2Text:ClearAllPoints()
            row._msuf2Text:SetPoint("LEFT", row, "LEFT", 100, 0)
            row._msuf2Text:SetPoint("RIGHT", row, "RIGHT", rightInset, 0)
        elseif sr then
            row._msuf2Icon:Hide()
            row._msuf2Swatch:SetColorTexture(sr, sg, sb, sa or 1)
            row._msuf2Swatch:Show()
            row._msuf2SwatchBorder:Show()
            row._msuf2Text:ClearAllPoints()
            row._msuf2Text:SetPoint("LEFT", row, "LEFT", 34, 0)
            row._msuf2Text:SetPoint("RIGHT", row, "RIGHT", rightInset, 0)
        else
            row._msuf2Icon:Hide()
            row._msuf2Swatch:Hide()
            row._msuf2SwatchBorder:Hide()
            row._msuf2Text:ClearAllPoints()
            row._msuf2Text:SetPoint("LEFT", row, "LEFT", 10, 0)
            row._msuf2Text:SetPoint("RIGHT", row, "RIGHT", rightInset, 0)
        end
        row:Show()
    end
    for i = #valuesTable + 1, #dropdownRows do
        dropdownRows[i]:Hide()
    end

    dropdownOwner = owner
    SetDropdownOwnerMouseWheel(owner, true)
    dropdownFrame:Show()
    PositionDropdown(owner)
    SetDropdownScroll((selectedIndex > visible) and ((selectedIndex - visible) * DROPDOWN_ROW_H) or 0)
end

function W.OpenDropdownList(owner, values, onSelect, selectedValue)
    if not owner then return end
    if dropdownOwner == owner and dropdownFrame and dropdownFrame:IsShown() then
        CloseDropdown()
        return
    end
    CloseDropdown()
    owner._msuf2DropdownListSelect = onSelect
    owner._msuf2DropdownListValue = selectedValue
    OpenDropdown(owner, values)
end

function W.Dropdown(section, label, values, width)
    local x, y = NextRow(section, 48)
    local title = T.Font(section, "GameFontHighlightSmall", Tr(label or ""), T.colors.text)
    SetSearchText(title, label)
    title:SetPoint("TOPLEFT", x, y)

    local btn = T.Button(section, "", width or 240, 22)
    RegisterSearchObject(btn, label, "dropdown", { anchor = title, values = values })
    btn._msuf2Title = title
    btn._msuf2ControlKind = "dropdown"
    btn._msuf2DropdownWheelManaged = true
    btn:SetPoint("TOPLEFT", x, y - 22)
    btn.values = values or {}
    btn._msuf2Label:ClearAllPoints()
    btn._msuf2Label:SetPoint("LEFT", btn, "LEFT", 10, 0)
    btn._msuf2Label:SetPoint("RIGHT", btn, "RIGHT", -26, 0)
    btn._msuf2Label:SetJustifyH("LEFT")
    StoreDropdownDefaultFont(btn._msuf2Label)
    btn._msuf2Chevron = btn:CreateTexture(nil, "OVERLAY")
    btn._msuf2Chevron:SetTexture(T.media.dropdownChevron)
    btn._msuf2Chevron:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    btn._msuf2Chevron:SetSize(10, 10)
    btn._msuf2Chevron:SetVertexColor(T.colors.muted[1], T.colors.muted[2], T.colors.muted[3], 0.95)
    btn._msuf2SwatchBorder = btn:CreateTexture(nil, "ARTWORK")
    btn._msuf2SwatchBorder:SetPoint("LEFT", btn, "LEFT", 9, 0)
    btn._msuf2SwatchBorder:SetSize(16, 16)
    btn._msuf2SwatchBorder:SetColorTexture(0, 0, 0, 0.90)
    btn._msuf2SwatchBorder:Hide()
    btn._msuf2Swatch = btn:CreateTexture(nil, "OVERLAY")
    btn._msuf2Swatch:SetPoint("CENTER", btn._msuf2SwatchBorder, "CENTER", 0, 0)
    btn._msuf2Swatch:SetSize(12, 12)
    btn._msuf2Swatch:Hide()
    btn._msuf2Icon = btn:CreateTexture(nil, "ARTWORK")
    btn._msuf2Icon:SetPoint("LEFT", btn, "LEFT", 10, 0)
    btn._msuf2Icon:SetSize(80, 12)
    btn._msuf2Icon:Hide()

    local function ResolveValues(self)
        local valuesTable = self.values
        if type(valuesTable) == "function" then valuesTable = valuesTable() end
        if type(valuesTable) ~= "table" then valuesTable = {} end
        return valuesTable
    end
    local function TextFor(value)
        local valuesTable = ResolveValues(btn)
        for i = 1, #valuesTable do
            local item = valuesTable[i]
            if DropdownItemValue(item) == value then return DropdownItemText(item) end
        end
        return tostring(value or "")
    end

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
        local selectedItem
        local valuesTable = ResolveValues(self)
        for i = 1, #valuesTable do
            local item = valuesTable[i]
            if DropdownItemValue(item) == value then
                selectedItem = item
                break
            end
        end
        local icon = DropdownItemIcon(selectedItem)
        local sr, sg, sb, sa = DropdownItemSwatch(selectedItem)
        if icon then
            if type(MSUF_SetIconTexture) == "function" then
                MSUF_SetIconTexture(self._msuf2Icon, icon, "")
            else
                self._msuf2Icon:SetTexture(icon)
            end
            self._msuf2Icon:SetTexCoord(0, 1, 0, 1)
            self._msuf2Icon:SetVertexColor(1, 1, 1, 1)
            self._msuf2Icon:Show()
            self._msuf2Swatch:Hide()
            self._msuf2SwatchBorder:Hide()
            self._msuf2Label:ClearAllPoints()
            self._msuf2Label:SetPoint("LEFT", self, "LEFT", 100, 0)
            self._msuf2Label:SetPoint("RIGHT", self, "RIGHT", -26, 0)
        elseif sr then
            self._msuf2Icon:Hide()
            self._msuf2Swatch:SetColorTexture(sr, sg, sb, sa or 1)
            self._msuf2Swatch:Show()
            self._msuf2SwatchBorder:Show()
            self._msuf2Label:ClearAllPoints()
            self._msuf2Label:SetPoint("LEFT", self, "LEFT", 34, 0)
            self._msuf2Label:SetPoint("RIGHT", self, "RIGHT", -26, 0)
        else
            self._msuf2Icon:Hide()
            self._msuf2Swatch:Hide()
            self._msuf2SwatchBorder:Hide()
            self._msuf2Label:ClearAllPoints()
            self._msuf2Label:SetPoint("LEFT", self, "LEFT", 10, 0)
            self._msuf2Label:SetPoint("RIGHT", self, "RIGHT", -26, 0)
        end
        RestoreDropdownDefaultFont(self._msuf2Label)
        self:SetText(selectedItem and DropdownItemText(selectedItem) or TextFor(value))
    end
    function btn:GetValue()
        return self.value
    end
    function btn:SetOnValueChanged(fn)
        self._msuf2OnValueChanged = fn
    end

    btn:EnableMouseWheel(false)
    btn:SetScript("OnClick", function(self)
        if M.BlockCombatAction and M.BlockCombatAction() then
            CloseDropdown()
            return
        end
        if dropdownOwner == self and dropdownFrame and dropdownFrame:IsShown() then
            CloseDropdown()
            return
        end
        CloseDropdown()
        self._msuf2DropdownListSelect = nil
        self._msuf2DropdownListValue = nil
        OpenDropdown(self, ResolveValues(self))
    end)

    btn:HookScript("OnHide", function(self)
        if dropdownOwner == self then CloseDropdown() end
    end)

    btn:SetScript("OnMouseWheel", function(self, delta)
        if dropdownOwner ~= self or not (dropdownFrame and dropdownFrame:IsShown()) then return end
        if dropdownScroll then
            local handler = dropdownScroll:GetScript("OnMouseWheel")
            if handler then handler(dropdownScroll, delta) end
        end
    end)

    return btn
end
