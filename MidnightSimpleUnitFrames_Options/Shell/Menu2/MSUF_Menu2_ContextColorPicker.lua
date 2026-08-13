local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local W = M.Widgets or {}
local T = M.Theme
local abs, floor, max, min = math.abs, math.floor, math.max, math.min
local Tr = M.TranslateText or M.Tr or function(text) return text end

local InvokePickerCallback = M.InvokeBoundary or pcall

-- Menu-only, progressive color editor. The compact view exposes the common
-- path; contextual targets and the large palettes stay one deliberate click
-- away. No runtime unit-frame hooks are installed.
local picker
local SIMPLE_WIDTH, SIMPLE_HEIGHT = 330, 330
local ADVANCED_WIDTH, ADVANCED_HEIGHT = 610, 420
local PICKER_PAD, PICKER_GAP = 16, 10
local LEFT_CARD_WIDTH = 216
local PICKER_REFERENCE_SCALE = 0.915
local ACTION_SIDE_PAD, ACTION_GAP = 8, 10
local SIMPLE_MORE_WIDTH, SIMPLE_CANCEL_WIDTH, SIMPLE_DONE_WIDTH = 102, 72, 88
local ADVANCED_MORE_WIDTH, ADVANCED_CANCEL_WIDTH, ADVANCED_DONE_WIDTH = 110, 98, 94

local function Clamp01(value)
    value = tonumber(value) or 0
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end
local function Byte(value) return floor(Clamp01(value) * 255 + 0.5) end
local function ToHex(r, g, b) return string.format("#%02X%02X%02X", Byte(r), Byte(g), Byte(b)) end
local function Byte01(value) return floor(value * 255 + 0.5) end
local function FromHex(value)
    local hex = tostring(value or ""):match("^%s*#?(%x%x%x%x%x%x)%s*$")
    if not hex then return nil end
    return (tonumber(hex:sub(1, 2), 16) or 255) / 255,
        (tonumber(hex:sub(3, 4), 16) or 255) / 255,
        (tonumber(hex:sub(5, 6), 16) or 255) / 255
end
local function HSV(h, s, v)
    h, s, v = (tonumber(h) or 0) % 1, Clamp01(s), Clamp01(v)
    local sector = floor(h * 6)
    local f = h * 6 - sector
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    sector = sector % 6
    if sector == 0 then return v, t, p end
    if sector == 1 then return q, v, p end
    if sector == 2 then return p, v, t end
    if sector == 3 then return p, q, v end
    if sector == 4 then return t, p, v end
    return v, p, q
end

local function Store()
    local db = type(M.EnsureDB) == "function" and M.EnsureDB() or _G.MSUF_DB
    if type(db) ~= "table" then return nil end
    db.menu2ColorPicker = type(db.menu2ColorPicker) == "table" and db.menu2ColorPicker or {}
    local store = db.menu2ColorPicker
    store.recent = type(store.recent) == "table" and store.recent or {}
    store.saved = type(store.saved) == "table" and store.saved or {}
    return store
end
local function AddRecent(hex)
    local store = Store()
    if not (store and hex) then return end
    for i = #store.recent, 1, -1 do if store.recent[i] == hex then table.remove(store.recent, i) end end
    table.insert(store.recent, 1, hex)
    while #store.recent > 9 do table.remove(store.recent) end
end

local function ApplyPickerPriority(panel, blocker)
    if not panel then return end
    if M.ApplyPopupFramePriority then
        M.ApplyPopupFramePriority(panel)
    end
    local strata = panel.GetFrameStrata and panel:GetFrameStrata() or "DIALOG"
    local level = panel.GetFrameLevel and panel:GetFrameLevel() or (M.MENU_POPUP_FRAME_LEVEL or 120)
    if blocker then
        if blocker.SetFrameStrata then blocker:SetFrameStrata(strata) end
        if blocker.SetFrameLevel then blocker:SetFrameLevel(max(0, level - 1)) end
        if blocker.SetToplevel then blocker:SetToplevel(false) end
    end
    if panel.contextList and panel.contextList.SetFrameLevel then
        panel.contextList:SetFrameLevel(level + 40)
    end
end

local function Font(parent, template, text, color)
    return T.Font(parent, template, Tr(text or ""), color or T.colors.text)
end
local function MenuFontStamp()
    local db = _G.MSUF_DB
    local general = type(db) == "table" and db.general or nil
    return tostring(type(general) == "table" and general.menuFontKey or "")
        .. "\030" .. tostring(tonumber(_G.MSUF_FontApplyEpoch) or 0)
end
local function RefreshPickerFonts(panel)
    if not (panel and type(T.RefreshMenuFonts) == "function") then return end
    local stamp = MenuFontStamp()
    if panel._msuf2MenuFontStamp == stamp then return end
    T.RefreshMenuFonts(panel, true)
    panel._msuf2MenuFontStamp = stamp
end
local function PickerInfoOwnsTooltip(button)
    local tooltip = _G.GameTooltip
    if not tooltip then return false end
    return not tooltip.GetOwner or tooltip:GetOwner() == button
end
local function ShowPickerInfo(button)
    local tooltip = _G.GameTooltip
    if not (button and tooltip) then return end
    local title = button._msuf2PickerInfoTitle or Tr("Color context")
    local text = button._msuf2PickerInfoText or ""
    tooltip:SetOwner(button, "ANCHOR_RIGHT")
    tooltip:SetText(title, 1, 1, 1)
    if text ~= "" then tooltip:AddLine(text, 0.80, 0.86, 1.00, true) end
    tooltip:Show()
end
local function HidePickerInfo(button)
    if button then button._msuf2PickerInfoPinned = nil end
    if PickerInfoOwnsTooltip(button) then _G.GameTooltip:Hide() end
end
local function RaisePickerInfo(panel)
    local button = panel and panel.infoButton
    if not (button and button.SetFrameLevel) then return end
    local close = panel.closeButton or panel.close
    local level = close and close.GetFrameLevel and close:GetFrameLevel()
        or ((panel.GetFrameLevel and panel:GetFrameLevel() or 0) + 16)
    button:SetFrameLevel(level + 1)
end
local function AddFlatButtonIcon(button, kind)
    local icon = CreateFrame("Frame", nil, button)
    icon:SetSize(12, 12); icon:SetPoint("LEFT", 5, 0)
    local function Line(x, y, width, height)
        local line = icon:CreateTexture(nil, "ARTWORK")
        line:SetPoint("TOPLEFT", icon, "TOPLEFT", x, -y); line:SetSize(width, height)
        line:SetColorTexture(T.colors.muted[1], T.colors.muted[2], T.colors.muted[3], 0.94)
    end
    local function Outline(x, y, width, height)
        Line(x, y, width, 1); Line(x, y + height - 1, width, 1)
        Line(x, y, 1, height); Line(x + width - 1, y, 1, height)
    end
    if kind == "copy" then
        Outline(1, 1, 7, 7); Outline(4, 4, 7, 7)
    else
        Outline(1, 1, 10, 10); Line(3, 1, 6, 4); Line(3, 7, 6, 4)
    end
    if button._msuf2Label then
        button._msuf2Label:ClearAllPoints()
        button._msuf2Label:SetPoint("LEFT", icon, "RIGHT", 3, 0)
        button._msuf2Label:SetPoint("RIGHT", -4, 0)
    end
    button._msuf2FlatIcon = icon
end
local function BrightSurface(frame, r, g, b, a)
    local wash = frame:CreateTexture(nil, "BORDER", nil, -8)
    wash:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -5)
    wash:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5)
    wash:SetColorTexture(r, g, b, a or 0.94)
    return wash
end
local TRUE_COLOR_KEYS = { "L", "M", "R" }
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local function SetTrueColor(self, r, g, b, a)
    a = a or 1
    self.L:SetColorTexture(r, g, b, a)
    self.M:SetColorTexture(r, g, b, a)
    self.R:SetColorTexture(r, g, b, a)
end
local function LayoutTrueColorParts(parts, frame, inset)
    local width = (frame.GetWidth and frame:GetWidth()) or 40
    local height = (frame.GetHeight and frame:GetHeight()) or 20
    local innerW = max(1, width - inset * 2)
    local innerH = max(1, height - inset * 2)
    local cap = min(floor(innerH * 0.5 + 0.5), floor(innerW * 0.5))
    local function Place(region, key)
        region:ClearAllPoints()
        if key == "L" then
            region:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
            region:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset)
            region:SetWidth(cap)
        elseif key == "R" then
            region:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
            region:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
            region:SetWidth(cap)
        else
            region:SetPoint("TOPLEFT", parts.L, "TOPRIGHT", 0, 0)
            region:SetPoint("BOTTOMRIGHT", parts.R, "BOTTOMLEFT", 0, 0)
        end
    end
    Place(parts.L, "L"); Place(parts.R, "R"); Place(parts.M, "M")
    if parts.masks then
        local maskSize = innerH
        parts.masks.L:ClearAllPoints(); parts.masks.L:SetSize(maskSize, maskSize)
        parts.masks.L:SetPoint("LEFT", parts.L, "LEFT", 0, 0)
        parts.masks.R:ClearAllPoints(); parts.masks.R:SetSize(maskSize, maskSize)
        parts.masks.R:SetPoint("RIGHT", parts.R, "RIGHT", 0, 0)
    end
end
local function CreateTrueColorParts(frame, key, inset, layer, subLevel)
    local parts, masks = {}, {}
    local canMask = frame.CreateMaskTexture ~= nil
    for i = 1, #TRUE_COLOR_KEYS do
        local partKey = TRUE_COLOR_KEYS[i]
        local texture = frame:CreateTexture(nil, layer, nil, subLevel or 0)
        texture:SetColorTexture(1, 1, 1, 1)
        parts[partKey] = texture
        if canMask and partKey ~= "M" then
            local mask = frame:CreateMaskTexture(nil, layer, nil, subLevel or 0)
            mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            texture:AddMaskTexture(mask)
            masks[partKey] = mask
        end
    end
    parts.masks = canMask and masks or nil
    parts.SetColorTexture, parts.SetVertexColor = SetTrueColor, SetTrueColor
    local function Layout() LayoutTrueColorParts(parts, frame, inset or 0) end
    Layout()
    if frame.HookScript then frame:HookScript("OnSizeChanged", Layout) end
    frame[key] = parts
    return parts
end
local function CreateTrueColorPill(frame, key, inset)
    local edge = CreateTrueColorParts(frame, key .. "Edge", 0, "BACKGROUND", 0)
    local fill = CreateTrueColorParts(frame, key .. "Fill", inset or 1, "ARTWORK", 0)
    return fill, edge
end
W.CreateTrueColorPill = CreateTrueColorPill
local function Input(parent, width, numeric)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetSize(width, 22)
    edit:SetAutoFocus(false)
    edit:SetJustifyH("CENTER")
    edit:SetMaxLetters(numeric and 3 or 7)
    if edit.SetNumeric then edit:SetNumeric(numeric and true or false) end
    if numeric and edit.SetTextInsets then edit:SetTextInsets(3, 12, 0, 0) end
    if T.SkinEditBox then T.SkinEditBox(edit) end
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); if picker then picker:Refresh() end end)
    edit:SetScript("OnEnterPressed", function(self)
        if type(self._commit) == "function" then self:_commit() end
        self:ClearFocus()
    end)
    if numeric then
        local function Step(delta)
            local value = min(255, max(0, (tonumber(edit:GetText()) or 0) + delta))
            edit:SetText(value)
            if type(edit._commit) == "function" then edit:_commit() end
        end
        local up = CreateFrame("Button", nil, edit)
        up:SetSize(10, 10); up:SetPoint("TOPRIGHT", -2, -1)
        local upText = Font(up, "GameFontDisableSmall", "^", T.colors.dim); upText:SetPoint("CENTER", 0, -1)
        up:SetScript("OnClick", function() Step(1) end)
        local down = CreateFrame("Button", nil, edit)
        down:SetSize(10, 10); down:SetPoint("BOTTOMRIGHT", -2, 1)
        local downText = Font(down, "GameFontDisableSmall", "v", T.colors.dim); downText:SetPoint("CENTER", 0, 1)
        down:SetScript("OnClick", function() Step(-1) end)
        edit.stepUp, edit.stepDown = up, down
    end
    return edit
end
local function ColorChip(parent, width, height)
    local chip = CreateFrame("Frame", nil, parent)
    chip:SetSize(width, height)
    local fill, edge = CreateTrueColorPill(chip, "_msuf2ColorChip", 1)
    if fill then
        fill:SetColorTexture(1, 1, 1, 1)
        edge:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.88)
        function chip:SetColorTexture(r, g, b, a) fill:SetColorTexture(r, g, b, a or 1) end
    else
        fill = chip:CreateTexture(nil, "ARTWORK")
        fill:SetAllPoints(); fill:SetColorTexture(1, 1, 1, 1)
        function chip:SetColorTexture(r, g, b, a) fill:SetColorTexture(r, g, b, a or 1) end
    end
    function chip:SetActive(active)
        if not edge then return end
        local color = active and (T.colors.coreHot or T.colors.accent) or T.colors.borderSoft
        edge:SetColorTexture(color[1], color[2], color[3], active and 1 or 0.88)
    end
    chip.fill, chip.edge = fill, edge
    return chip
end
local function ColorField(parent, width, height)
    local field = CreateFrame("Frame", nil, parent)
    field:SetSize(width, height)
    local fill, edge = T.CreateSuperellipseLayers and T.CreateSuperellipseLayers(field, "_msuf2PickerField", 2, "ARTWORK", "BORDER")
    if not (fill and edge) then
        edge = field:CreateTexture(nil, "BORDER")
        edge:SetAllPoints(); edge:SetColorTexture(1, 1, 1, 1)
        fill = field:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT", 1, -1); fill:SetPoint("BOTTOMRIGHT", -1, 1)
        fill:SetColorTexture(1, 1, 1, 1)
    end
    local function LowRadius()
        if fill.L then fill.L:SetWidth(4); fill.R:SetWidth(4) end
        if edge.L then edge.L:SetWidth(5); edge.R:SetWidth(5) end
    end
    LowRadius(); field:HookScript("OnSizeChanged", LowRadius)
    function field:SetColorTexture(r, g, b, a)
        if fill.SetVertexColor then fill:SetVertexColor(r, g, b, a or 1) else fill:SetColorTexture(r, g, b, a or 1) end
    end
    function field:SetActive(active)
        if not edge.SetVertexColor then return end
        local color = active and (T.colors.coreHot or T.colors.accent) or T.colors.borderSoft
        edge:SetVertexColor(color[1], color[2], color[3], active and 1 or (color[4] or 0.88))
    end
    field.fill, field.edge = fill, edge
    return field
end
local function RefreshSwatchVisual(button, hover)
    local edge = button and button.edge
    if not edge then return end
    local selected = button._msuf2PickerSelected == true
    local color = (selected and (T.colors.coreHot or T.colors.accent))
        or (hover and T.colors.accent) or T.colors.borderSoft
    edge:SetColorTexture(color[1], color[2], color[3], selected and 1 or (hover and 0.94 or 0.76))
end
local function CreateCircularSwatchParts(button)
    local edge = button:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints(); edge:SetColorTexture(1, 1, 1, 1)
    local fill = button:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 2, -2); fill:SetPoint("BOTTOMRIGHT", -2, 2)
    fill:SetColorTexture(1, 1, 1, 1)
    if button.CreateMaskTexture then
        local edgeMask = button:CreateMaskTexture(nil, "ARTWORK")
        edgeMask:SetAllPoints(edge); edgeMask:SetAtlas("CircleMask")
        edge:AddMaskTexture(edgeMask)
        local fillMask = button:CreateMaskTexture(nil, "ARTWORK")
        fillMask:SetAllPoints(fill); fillMask:SetAtlas("CircleMask")
        fill:AddMaskTexture(fillMask)
    end
    return fill, edge
end
local function Swatch(parent, size, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local fill, edge = CreateCircularSwatchParts(button)
    edge:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.76)
    button:HookScript("OnEnter", function(self) RefreshSwatchVisual(self, true) end)
    button:HookScript("OnLeave", function(self) RefreshSwatchVisual(self, false) end)
    button.fill, button.edge = fill, edge
    function button:SetSelected(selected)
        self._msuf2PickerSelected = selected == true
        RefreshSwatchVisual(self, false)
    end
    button:SetScript("OnClick", onClick)
    return button
end

local function OpacityDisplay(parent, width)
    local frame = CreateFrame("Slider", nil, parent)
    frame:SetSize(width, 20)
    -- Bare CreateFrame sliders start mouse-disabled, so the thumb cannot be
    -- dragged until mouse input is enabled explicitly (same as W.Slider).
    if frame.EnableMouse then frame:EnableMouse(true) end
    frame:SetOrientation("HORIZONTAL")
    frame:SetMinMaxValues(0, 1)
    frame:SetValueStep(0.01)
    if frame.SetObeyStepOnDrag then frame:SetObeyStepOnDrag(true) end
    if T.ApplyBackdrop then T.ApplyBackdrop(frame, T.colors.coreShadow, T.colors.borderSoft) end
    local innerWidth, innerHeight = width - 2, 18
    local atlasInfo = _G.C_Texture and _G.C_Texture.GetAtlasInfo
        and _G.C_Texture.GetAtlasInfo("colorpicker-checkerboard")
    local checkerScale = 0.75
    local checkerWidth = ((atlasInfo and tonumber(atlasInfo.width)) or 32) * checkerScale
    local checkerHeight = ((atlasInfo and tonumber(atlasInfo.height)) or 32) * checkerScale
    checkerWidth = max(1, checkerWidth)
    local checkerCount = max(1, math.ceil(innerWidth / checkerWidth) + 1)
    local checkerHost = CreateFrame("Frame", nil, frame)
    checkerHost:SetPoint("TOPLEFT", 1, -1); checkerHost:SetSize(innerWidth, innerHeight)
    if checkerHost.SetClipsChildren then checkerHost:SetClipsChildren(true) end
    for i = 1, checkerCount do
        local checker = checkerHost:CreateTexture(nil, "BACKGROUND")
        checker:SetAtlas("colorpicker-checkerboard", true)
        checker:SetSize(checkerWidth, checkerHeight)
        checker:SetPoint("LEFT", checkerHost, "LEFT", (i - 1) * checkerWidth, 0)
    end
    local shade = frame:CreateTexture(nil, "ARTWORK")
    shade:SetPoint("TOPLEFT", 1, -1); shade:SetPoint("BOTTOMRIGHT", -1, 1)
    shade:SetColorTexture(1, 1, 1, 1)
    if shade.SetGradient and _G.CreateColor then
        shade:SetGradient("HORIZONTAL", _G.CreateColor(0.02, 0.04, 0.07, 0), _G.CreateColor(0.02, 0.04, 0.07, 0.96))
    else
        shade:SetColorTexture(0.02, 0.04, 0.07, 0.56)
    end
    local thumb = frame:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(6, 24)
    thumb:SetColorTexture(T.colors.text[1], T.colors.text[2], T.colors.text[3], 1)
    frame:SetThumbTexture(thumb)
    frame:SetValue(1)
    frame.checkerHost, frame.shade, frame.thumb = checkerHost, shade, thumb
    return frame
end
local function OwnerOpacity(owner)
    if not (owner and owner._msuf2ColorHasOpacity == true
        and type(owner._msuf2GetColorOpacity) == "function") then return nil end
    local alpha = owner:_msuf2GetColorOpacity()
    if type(alpha) ~= "number" then return nil end
    return Clamp01(alpha)
end
local function OwnerState(owner)
    if not (owner and type(owner._msuf2CaptureColorState) == "function") then return nil end
    return owner:_msuf2CaptureColorState()
end
local function ApplyOwner(owner, r, g, b, alpha, preclamped)
    if not owner then return end
    if not preclamped then
        r, g, b = Clamp01(r), Clamp01(g), Clamp01(b)
        if alpha ~= nil then alpha = Clamp01(alpha) end
    end
    owner:SetRGB(r, g, b)
    if type(owner._msuf2OnColorChanged) == "function" then owner._msuf2OnColorChanged(r, g, b, alpha) end
end

local function PickerMenuScale()
    local menu = M.frame
    if menu and menu.GetScale then
        local scale = tonumber(menu:GetScale())
        if scale and scale > 0 then return scale * PICKER_REFERENCE_SCALE end
    end
    local general = M.GetGeneralDB and M.GetGeneralDB()
    if type(general) == "table" and type(M.GetEffectiveMenuScale) == "function" then
        local scale = tonumber(M.GetEffectiveMenuScale(general.slashMenuScale))
        if scale and scale > 0 then return scale * PICKER_REFERENCE_SCALE end
    end
    return PICKER_REFERENCE_SCALE
end

local function EnsurePicker()
    if picker then return picker end
    local parent = _G.UIParent or M.frame
    if not parent then return nil end

    local blocker = CreateFrame("Button", nil, parent)
    blocker:SetAllPoints(parent); blocker:EnableMouse(true)
    blocker:SetScript("OnClick", function() if picker then picker:Finish(true) end end); blocker:Hide()

    local panel = T.Panel(parent, nil, T.colors.glassShell or T.colors.bg, T.colors.cardBorder or T.colors.borderSoft)
    picker = panel
    panel:SetSize(SIMPLE_WIDTH, SIMPLE_HEIGHT); panel:SetScale(PickerMenuScale()); panel:SetClampedToScreen(true)
    panel:SetMovable(true); panel:EnableMouse(true); panel:EnableKeyboard(true)
    if panel.SetPropagateKeyboardInput then panel:SetPropagateKeyboardInput(true) end
    if T.ApplySurface then T.ApplySurface(panel, "popup") end
    if T.ApplyBackdrop then T.ApplyBackdrop(panel, T.colors.glassShell or T.colors.bg, T.colors.border) end
    panel._msuf2PickerBrightSurface = BrightSurface(panel,
        T.colors.coreShadow[1], T.colors.coreShadow[2], T.colors.coreShadow[3], 0.93)
    panel.blocker = blocker
    ApplyPickerPriority(panel, blocker)

    local close
    if M.CreateWindowControlButton then
        close = M.CreateWindowControlButton(panel, "close")
        close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
        close:SetScript("OnClick", function() panel:Finish(true) end)
        panel.closeButton, panel.close = close, close
        if M.AddTooltip then
            M.AddTooltip(close, "Close", "Cancel changes and close the MSUF Color Picker.")
        end
        if M.RefreshWindowControls then M.RefreshWindowControls(panel) end
    else
        close = T.CloseButton and T.CloseButton(panel)
        if close then
            close:SetPoint("TOPRIGHT", -10, -10)
            close:SetScript("OnClick", function() panel:Finish(true) end)
            panel.closeButton, panel.close = close, close
        end
    end

    local drag = CreateFrame("Button", nil, panel)
    drag:SetPoint("TOPLEFT", 1, -1); drag:SetPoint("TOPRIGHT", -1, -1); drag:SetHeight(44)
    drag:RegisterForDrag("LeftButton"); drag:RegisterForClicks("LeftButtonUp")
    drag:SetScript("OnDragStart", function() panel:SetContextListShown(false); panel:StartMoving() end)
    drag:SetScript("OnDragStop", function() panel:StopMovingOrSizing(); panel:SavePosition() end)
    drag:SetScript("OnDoubleClick", function() panel:ResetPosition() end)
    if M.AddTooltip then M.AddTooltip(drag, "Move color picker", "Drag to move. Double-click to center it again.") end

    local info = T.Button(panel, "i", 18, 18, { noSearch = true })
    info._msuf2SkipHistoryCheckpoint = true
    if T.CenterButtonLabel then T.CenterButtonLabel(info) end
    if close then
        info:SetPoint("RIGHT", close, "LEFT", -6, 0)
    else
        info:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -38, -11)
    end
    info:RegisterForClicks("LeftButtonUp")
    info:SetScript("OnClick", function(self)
        self._msuf2PickerInfoPinned = not self._msuf2PickerInfoPinned
        if self._msuf2PickerInfoPinned then ShowPickerInfo(self) else HidePickerInfo(self) end
    end)
    info:HookScript("OnEnter", function(self) ShowPickerInfo(self) end)
    info:HookScript("OnLeave", function(self)
        if not self._msuf2PickerInfoPinned and PickerInfoOwnsTooltip(self) then _G.GameTooltip:Hide() end
    end)
    panel.infoButton = info
    RaisePickerInfo(panel)

    local title = Font(panel, "GameFontNormalLarge", "MSUF Color Picker", T.colors.title or T.colors.text)
    title:SetPoint("TOPLEFT", PICKER_PAD, -10)
    title:SetPoint("RIGHT", info, "LEFT", -8, 0)
    title:SetJustifyH("LEFT")
    if title.SetWordWrap then title:SetWordWrap(false) end
    if title.SetNonSpaceWrap then title:SetNonSpaceWrap(false) end
    panel.title = title
    local moveHint = Font(panel, "GameFontDisableSmall", "drag to move", T.colors.dim)
    moveHint:SetPoint("TOPRIGHT", close or panel,
        close and "TOPLEFT" or "TOPRIGHT", close and -10 or -16, close and -1 or -16)
    moveHint:Hide()

    local selector = T.Button(panel, "", SIMPLE_WIDTH - PICKER_PAD * 2, 32)
    selector._msuf2SkipHistoryCheckpoint = true
    selector._msuf2ControlKind = "dropdown"
    selector:SetPoint("TOPLEFT", PICKER_PAD, -46)
    local editingLabel = Font(selector, "GameFontHighlightSmall", "Editing", T.colors.text)
    editingLabel:SetPoint("LEFT", 12, 0)
    local separator = selector:CreateTexture(nil, "ARTWORK")
    separator:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.72)
    separator:SetPoint("TOPLEFT", 58, -7); separator:SetPoint("BOTTOMLEFT", 58, 7); separator:SetWidth(1)
    local selectorColor = ColorChip(selector, 14, 14); selectorColor:SetPoint("LEFT", 68, 0)
    local selectorLabel = selector._msuf2Label; selectorLabel:ClearAllPoints(); selectorLabel:SetPoint("LEFT", selectorColor, "RIGHT", 10, 0); selectorLabel:SetPoint("RIGHT", -28, 0); selectorLabel:SetJustifyH("LEFT")
    local selectorArrow = selector:CreateTexture(nil, "OVERLAY")
    selectorArrow:SetTexture(T.media.dropdownChevron)
    selectorArrow:SetPoint("RIGHT", selector, "RIGHT", -10, 0); selectorArrow:SetSize(12, 12)
    selectorArrow:SetVertexColor(T.colors.muted[1], T.colors.muted[2], T.colors.muted[3], 0.95)
    selector.color, selector.label, selector.arrow = selectorColor, selectorLabel, selectorArrow
    selector.editingLabel, selector.separator = editingLabel, separator
    selector:SetScript("OnClick", function() panel:SetContextListShown(true) end)
    panel.selector = selector

    local original = ColorField(panel, 144, 22); original:SetPoint("TOPLEFT", PICKER_PAD, -101)
    local current = ColorField(panel, 144, 22); current:SetPoint("TOPRIGHT", -PICKER_PAD, -101)
    original:SetActive(false); current:SetActive(true)
    panel.original, panel.current = original, current
    local originalLabel = Font(panel, "GameFontDisableSmall", "Original", T.colors.dim); originalLabel:SetPoint("BOTTOMLEFT", original, "TOPLEFT", 0, 2)
    local currentLabel = Font(panel, "GameFontDisableSmall", "Current", T.colors.dim); currentLabel:SetPoint("BOTTOMLEFT", current, "TOPLEFT", 0, 2)

    local wheelCard = T.Panel(panel, nil, T.colors.coreSurface, T.colors.cardBorder or T.colors.borderSoft)
    wheelCard:SetPoint("TOPLEFT", PICKER_PAD, -133); wheelCard:SetSize(SIMPLE_WIDTH - PICKER_PAD * 2, 138)
    if T.ApplySurface then T.ApplySurface(wheelCard, "card") end
    if T.ApplyBackdrop then T.ApplyBackdrop(wheelCard, T.colors.coreSurface, T.colors.cardBorder or T.colors.borderSoft) end
    wheelCard._msuf2PickerBrightSurface = BrightSurface(wheelCard,
        T.colors.coreSurface[1], T.colors.coreSurface[2], T.colors.coreSurface[3], 0.92)
    local wheelTitle = Font(wheelCard, "GameFontNormalSmall", "Color & Brightness", T.colors.text)
    wheelTitle:SetPoint("TOPLEFT", 10, -8)

    -- Use Blizzard's native ColorSelect engine. This is the same wheel/value
    -- interaction as ColorPickerFrame, embedded in the MSUF surface so the
    -- target selector, live preview and palettes remain one compact workflow.
    local colorSelect = CreateFrame("ColorSelect", nil, wheelCard)
    -- Blizzard declares its own ColorSelect with enableMouse="true"; the native
    -- wheel/value dragging is frame mouse input, so without this the wheel and
    -- the brightness bar render correctly but never respond to clicks.
    colorSelect:EnableMouse(true)
    colorSelect:SetPoint("TOPLEFT", 80, -27); colorSelect:SetSize(150, 112)
    local wheel = colorSelect:CreateTexture(nil, "ARTWORK")
    wheel:SetPoint("TOPLEFT", 0, -4); wheel:SetSize(102, 102)
    colorSelect:SetColorWheelTexture(wheel)
    colorSelect:SetColorWheelThumbTexture("Interface\\Buttons\\UI-ColorPicker-Buttons")
    local wheelThumb = colorSelect:GetColorWheelThumbTexture()
    wheelThumb:SetSize(10, 10); wheelThumb:SetTexCoord(0, 0.15625, 0, 0.625)
    local value = colorSelect:CreateTexture(nil, "ARTWORK")
    value:SetPoint("LEFT", wheel, "RIGHT", 10, 0); value:SetSize(25, 102)
    colorSelect:SetColorValueTexture(value)
    colorSelect:SetColorValueThumbTexture("Interface\\Buttons\\UI-ColorPicker-Buttons")
    local valueThumb = colorSelect:GetColorValueThumbTexture()
    valueThumb:SetSize(35, 11); valueThumb:SetTexCoord(0.25, 1.0, 0, 0.875); valueThumb:SetAlpha(0.001)
    local valueHandle = CreateFrame("Frame", nil, colorSelect, "BackdropTemplate")
    valueHandle:SetSize(31, 6); valueHandle:SetPoint("CENTER", valueThumb, "CENTER", 0, 0)
    if T.ApplyBackdrop then T.ApplyBackdrop(valueHandle, T.colors.coreShadow, T.colors.text) end
    local valueUp = Font(colorSelect, "GameFontHighlightSmall", "^", T.colors.dim)
    valueUp:SetPoint("BOTTOM", value, "TOP", 0, 3)
    local valueDown = Font(colorSelect, "GameFontHighlightSmall", "v", T.colors.dim)
    valueDown:SetPoint("TOP", value, "BOTTOM", 0, -3)
    colorSelect:SetScript("OnColorSelect", function(_, r, g, b)
        if not panel._syncingColorSelect then panel:Apply(r, g, b, true) end
    end)
    panel.colorSelect, panel.wheelCard = colorSelect, wheelCard
    panel.colorWheel, panel.colorValue = wheel, value
    panel.colorWheelThumb, panel.colorValueThumb = wheelThumb, valueThumb
    panel.colorValueHandle, panel.colorValueUp, panel.colorValueDown = valueHandle, valueUp, valueDown

    local opacityLabel = Font(wheelCard, "GameFontNormalSmall", "Opacity", T.colors.muted)
    local opacity = OpacityDisplay(wheelCard, 160)
    local opacityValue = Font(wheelCard, "GameFontHighlightSmall", "100%", T.colors.text)
    opacityLabel:Hide(); opacity:Hide(); opacityValue:Hide()
    panel.opacityLabel, panel.opacity, panel.opacityValue = opacityLabel, opacity, opacityValue
    opacity:SetScript("OnValueChanged", function(_, value)
        if not panel._syncingOpacity then panel:ApplyOpacity(value) end
    end)
    if M.AddTooltip then M.AddTooltip(opacity, "Opacity", "Adjusts the alpha channel of this color.") end

    local compactHexTitle = Font(wheelCard, "GameFontNormalSmall", "HEX", T.colors.muted)
    local compactHex = Input(wheelCard, 64, false); panel.compactHexTitle, panel.compactHex = compactHexTitle, compactHex
    compactHex:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    compactHex:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    compactHex:SetScript("OnEditFocusLost", function(self) self:SetText(panel._readoutHex or "") end)
    compactHex:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self:SetText(panel._readoutHex or ""); self:HighlightText() end
    end)
    if M.AddTooltip then M.AddTooltip(compactHex, "HEX color", "Click to select the value, then press Ctrl+C to copy it.") end

    local advancedCard = T.Panel(panel, nil, T.colors.coreSurface, T.colors.cardBorder or T.colors.borderSoft)
    advancedCard:SetPoint("TOPLEFT", PICKER_PAD + LEFT_CARD_WIDTH + PICKER_GAP, -133)
    advancedCard:SetSize(ADVANCED_WIDTH - PICKER_PAD * 2 - LEFT_CARD_WIDTH - PICKER_GAP, 227)
    if T.ApplySurface then T.ApplySurface(advancedCard, "card") end
    if T.ApplyBackdrop then T.ApplyBackdrop(advancedCard, T.colors.coreSurface, T.colors.cardBorder or T.colors.borderSoft) end
    advancedCard._msuf2PickerBrightSurface = BrightSurface(advancedCard,
        T.colors.coreSurface[1], T.colors.coreSurface[2], T.colors.coreSurface[3], 0.92)
    advancedCard:Hide(); panel.advancedCard = advancedCard

    local paletteTitle = Font(advancedCard, "GameFontNormalSmall", "Palette", T.colors.text)
    paletteTitle:SetPoint("TOPLEFT", 12, -10); panel.paletteTitle = paletteTitle
    panel.paletteLookups = { quick = {}, class = {}, recent = {}, saved = {} }
    panel.paletteTabs = {}
    local tabSpecs = { { "quick", "Quick" }, { "class", "Class" }, { "recent", "Recent" }, { "saved", "Saved" } }
    for i = 1, #tabSpecs do
        local spec = tabSpecs[i]
        local tab = T.Button(advancedCard, Tr(spec[2]), 78, 20)
        if tab._msuf2Label then tab._msuf2Label:SetJustifyH("CENTER") end
        tab._msuf2SkipHistoryCheckpoint = true
        tab._msuf2PaletteKey = spec[1]
        tab:SetScript("OnClick", function(self) panel:SetPaletteTab(self._msuf2PaletteKey) end)
        panel.paletteTabs[i] = tab
    end

    panel.spectrum = {}
    local tones = { { 0.96, 1.00 }, { 0.78, 0.90 }, { 0.56, 0.70 }, { 0.28, 0.56 } }
    for row = 1, 4 do
        for col = 1, 10 do
            local r, g, b = HSV((col - 1) / 10, tones[row][1], tones[row][2])
            local swatch = Swatch(advancedCard, 24, function(self) panel:Apply(self.r, self.g, self.b) end)
            swatch.r, swatch.g, swatch.b, swatch.toneRow = r, g, b, row
            swatch.fill:SetColorTexture(r, g, b, 1); panel.spectrum[#panel.spectrum + 1] = swatch
            panel.paletteLookups.quick[ToHex(r, g, b)] = swatch
        end
    end

    local rgbTitle = Font(advancedCard, "GameFontNormalSmall", "RGB", T.colors.muted); panel.rgbTitle = rgbTitle
    panel.rgb, panel.rgbLabels = {}, {}
    for i, channel in ipairs({ "R", "G", "B" }) do
        local input = Input(advancedCard, 40, true)
        local label = Font(advancedCard, "GameFontDisableSmall", channel, T.colors.dim); panel.rgbLabels[i] = label
        input._commit = function(self)
            if not panel.owner then return end
            local r, g, b = panel.owner:GetRGB(); local values = { Byte(r), Byte(g), Byte(b) }
            values[i] = min(255, max(0, tonumber(self:GetText()) or values[i]))
            panel:Apply(values[1] / 255, values[2] / 255, values[3] / 255)
        end
        panel.rgb[i] = input
    end
    local hexTitle = Font(advancedCard, "GameFontNormalSmall", "HEX", T.colors.muted); panel.hexTitle = hexTitle
    local hex = Input(advancedCard, 64, false); panel.hex = hex
    hex._commit = function(self)
        local r, g, b = FromHex(self:GetText())
        if r then panel:Apply(r, g, b) else panel:Refresh() end
    end
    local copy = T.Button(advancedCard, Tr("Copy"), 54, 22); panel.copy = copy
    if copy._msuf2Label then
        copy._msuf2Label:ClearAllPoints(); copy._msuf2Label:SetPoint("LEFT", 4, 0); copy._msuf2Label:SetPoint("RIGHT", -4, 0)
        copy._msuf2Label:SetJustifyH("CENTER")
    end
    AddFlatButtonIcon(copy, "copy")
    copy:SetScript("OnClick", function() hex:SetFocus(); hex:HighlightText() end)
    local save = T.Button(advancedCard, Tr("Save"), 54, 22); panel.save = save
    if save._msuf2Label then
        save._msuf2Label:ClearAllPoints(); save._msuf2Label:SetPoint("LEFT", 4, 0); save._msuf2Label:SetPoint("RIGHT", -4, 0)
        save._msuf2Label:SetJustifyH("CENTER")
    end
    AddFlatButtonIcon(save, "save")
    save:SetScript("OnClick", function()
        if not panel.owner then return end
        local store = Store(); if not store then return end
        local r, g, b = panel.owner:GetRGB(); local value = ToHex(r, g, b)
        for i = 1, #store.saved do if store.saved[i] == value then return end end
        if #store.saved < 27 then store.saved[#store.saved + 1] = value end
        panel:RefreshPalettes()
    end)

    panel.recent = {}
    for i = 1, 9 do
        panel.recent[i] = Swatch(advancedCard, 24, function(self)
            local r, g, b = FromHex(self.hex); if r then panel:Apply(r, g, b) end
        end)
    end

    local savedHint = Font(advancedCard, "GameFontDisableSmall", "Right-click a saved color to remove it.", T.colors.dim)
    panel.savedHint = savedHint
    panel.saved = {}
    for i = 1, 27 do
        local swatch = Swatch(advancedCard, 24, function(self, button)
            local store = Store()
            if button == "RightButton" and store then table.remove(store.saved, self.index); panel:RefreshPalettes(); return end
            local r, g, b = FromHex(self.hex); if r then panel:Apply(r, g, b) end
        end)
        swatch.index = i; panel.saved[i] = swatch
    end

    panel.classes = {}
    local tokens = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER" }
    for i = 1, #tokens do
        local swatch = Swatch(advancedCard, 24, function(self)
            local color = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[self.token]
            if color then panel:Apply(color.r, color.g, color.b) end
        end)
        swatch.token = tokens[i]; panel.classes[i] = swatch
        if M.AddTooltip then M.AddTooltip(swatch, tokens[i], Tr("Apply this class color.")) end
    end

    local emptyHint = Font(advancedCard, "GameFontDisableSmall", "No colors here yet.", T.colors.dim)
    emptyHint:SetJustifyH("CENTER"); panel.emptyHint = emptyHint

    local actionBar = T.Panel(panel, nil, T.colors.glassStatus or T.colors.header, T.colors.borderSoft)
    actionBar:SetPoint("BOTTOMLEFT", PICKER_PAD, 8); actionBar:SetPoint("BOTTOMRIGHT", -PICKER_PAD, 8); actionBar:SetHeight(42)
    if T.ApplySurface then T.ApplySurface(actionBar, "status") end
    panel.actionBar = actionBar
    local more = T.Button(actionBar, Tr("Advanced"), 110, 26); panel.more = more
    if more._msuf2Label then more._msuf2Label:SetJustifyH("CENTER") end
    more._msuf2SkipHistoryCheckpoint = true
    more:SetScript("OnClick", function() panel:SetAdvanced(not panel.advanced) end)
    if M.AddTooltip then
        M.AddTooltip(more, "Advanced color tools", "Quick colors, precise RGB and HEX values, recent colors, saved colors, and class colors.")
    end
    local cancel = T.Button(actionBar, Tr("Cancel"), 98, 26); panel.cancel = cancel
    if cancel._msuf2Label then cancel._msuf2Label:SetJustifyH("CENTER") end
    cancel:SetScript("OnClick", function() panel:Finish(true) end)
    local done = T.Button(actionBar, Tr("Apply Color"), 94, 26); panel.done = done
    if done._msuf2Label then done._msuf2Label:SetJustifyH("CENTER") end
    if T.ApplyButtonRole then T.ApplyButtonRole(done, "primary") end
    done:SetScript("OnClick", function() panel:Finish(false) end)

    function panel:SavePosition()
        local store = Store(); if not store then return end
        local cx, cy = self:GetCenter(); local px, py = parent:GetCenter()
        if cx and cy and px and py then store.x, store.y = floor(cx - px + 0.5), floor(cy - py + 0.5) end
    end
    function panel:ResetPosition()
        local store = Store(); if store then store.x, store.y = nil, nil end
        self:ClearAllPoints(); self:SetPoint("CENTER", parent, "CENTER", 0, 0)
    end
    function panel:RestorePosition()
        local store = Store() or {}
        self:ClearAllPoints(); self:SetPoint("CENTER", parent, "CENTER", tonumber(store.x) or 0, tonumber(store.y) or 0)
    end
    function panel:ClampPosition()
        local cx, cy = self:GetCenter()
        local px, py = parent:GetCenter()
        local parentWidth, parentHeight = parent:GetWidth(), parent:GetHeight()
        if not (cx and cy and px and py and parentWidth and parentHeight) then return end
        local margin = 12
        local limitX = max(0, (parentWidth - self:GetWidth()) * 0.5 - margin)
        local limitY = max(0, (parentHeight - self:GetHeight()) * 0.5 - margin)
        local currentX, currentY = cx - px, cy - py
        local x = min(limitX, max(-limitX, currentX))
        local y = min(limitY, max(-limitY, currentY))
        if abs(x - currentX) < 0.01 and abs(y - currentY) < 0.01 then return end
        self:ClearAllPoints(); self:SetPoint("CENTER", parent, "CENTER", x, y)
        local store = Store()
        if store then store.x, store.y = floor(x + 0.5), floor(y + 0.5) end
    end

    function panel:SetContextListShown(shown)
        if shown ~= true then
            self._ownerDropdownOpen = nil
            if W.CloseDropdown then W.CloseDropdown({ immediate = true }) end
            return
        end
        local values = self._ownerDropdownValues or {}
        self._ownerDropdownValues = values
        local owners = self.owners or {}
        for i = 1, #owners do
            local owner = owners[i]
            local item = values[i] or {}
            local color = item.color or {}
            local r, g, b = owner:GetRGB()
            color[1], color[2], color[3], color[4] = r, g, b, 1
            item.value = owner
            item.text = owner._msuf2ColorLabel or owner._msuf2SearchText or "Color"
            item.color = color
            values[i] = item
        end
        for i = #owners + 1, #values do values[i] = nil end
        if #values == 0 or type(W.OpenDropdown) ~= "function" then return end
        local opened = W.OpenDropdown(self.selector, values, self.owner, function(owner)
            self._ownerDropdownOpen = nil
            self:SetOwner(owner)
        end)
        self._ownerDropdownOpen = opened and true or nil
    end

    function panel:Layout()
        local advanced = self.advanced == true
        if self._layoutAdvanced == advanced then self:ClampPosition(); return end
        self._layoutAdvanced = advanced
        local width = advanced and ADVANCED_WIDTH or SIMPLE_WIDTH
        local height = advanced and ADVANCED_HEIGHT or SIMPLE_HEIGHT
        local previewWidth = (width - PICKER_PAD * 2 - PICKER_GAP) * 0.5
        local selectorWidth = width - PICKER_PAD * 2
        self:SetSize(width, height)
        self.selector:SetWidth(selectorWidth)
        self.original:SetWidth(previewWidth); self.current:SetWidth(previewWidth)

        self.wheelCard:ClearAllPoints(); self.wheelCard:SetPoint("TOPLEFT", PICKER_PAD, -133)
        self.wheelCard:SetSize(advanced and LEFT_CARD_WIDTH or selectorWidth, advanced and 227 or 138)
        self.colorSelect:ClearAllPoints()
        local wheelSize = advanced and 126 or 102
        self.colorSelect:SetPoint("TOPLEFT", advanced and 28 or 80, advanced and -30 or -27)
        self.colorSelect:SetSize(advanced and 170 or 150, wheelSize + 10)
        self.colorWheel:SetSize(wheelSize, wheelSize)
        self.colorValue:ClearAllPoints(); self.colorValue:SetPoint("LEFT", self.colorWheel, "RIGHT", 10, 0)
        self.colorValue:SetSize(25, wheelSize)
        self.colorValueThumb:SetSize(35, 11)
        self.advancedCard:SetShown(advanced)
        self.compactHex:ClearAllPoints(); self.compactHex:SetPoint("TOPRIGHT", self.wheelCard, "TOPRIGHT", -6, -55)
        self.compactHexTitle:ClearAllPoints(); self.compactHexTitle:SetPoint("BOTTOMLEFT", self.compactHex, "TOPLEFT", 0, 3)
        self.compactHexTitle:SetShown(not advanced); self.compactHex:SetShown(not advanced)
        if not self._advancedChildLayout then
            self._advancedChildLayout = true
            self.opacityLabel:SetPoint("TOPLEFT", 12, -171)
            self.opacity:SetPoint("TOPLEFT", 12, -190)
            self.opacityValue:SetPoint("LEFT", self.opacity, "RIGHT", 8, 0)
            for i = 1, #self.paletteTabs do
                self.paletteTabs[i]:SetPoint("TOPLEFT", 12 + (i - 1) * 82, -35)
            end
            for i = 1, #self.spectrum do
                local swatch = self.spectrum[i]; local slot = i - 1
                local col, row = slot % 10, floor(slot / 10)
                swatch:SetPoint("TOPLEFT", 12 + col * 33, -67 - row * 28)
            end
            for i = 1, #self.classes do
                local slot = i - 1; local col, row = slot % 8, floor(slot / 8)
                self.classes[i]:SetPoint("TOPLEFT", 12 + col * 40, -69 - row * 32)
            end
            for i = 1, #self.recent do self.recent[i]:SetPoint("TOPLEFT", 12 + (i - 1) * 36, -69) end
            for i = 1, #self.saved do
                local slot = i - 1; local col, row = slot % 9, floor(slot / 9)
                self.saved[i]:SetPoint("TOPLEFT", 12 + col * 36, -69 - row * 32)
            end
            self.emptyHint:SetPoint("TOPLEFT", 12, -90); self.emptyHint:SetWidth(328)
            self.savedHint:SetPoint("TOPRIGHT", -12, -169)
            local inputY = -193
            self.rgbTitle:Hide()
            for i = 1, 3 do
                self.rgb[i]:SetPoint("TOPLEFT", 12 + (i - 1) * 46, inputY)
                self.rgbLabels[i]:SetPoint("BOTTOMLEFT", self.rgb[i], "TOPLEFT", 0, 3)
            end
            self.hex:SetPoint("TOPLEFT", 150, inputY)
            self.hexTitle:SetPoint("BOTTOMLEFT", self.hex, "TOPLEFT", 0, 3)
            self.copy:SetPoint("LEFT", self.hex, "RIGHT", 6, 0)
            self.save:SetPoint("LEFT", self.copy, "RIGHT", 6, 0)
        end
        local showOpacity = advanced and self.owner and self.owner._msuf2ColorHasOpacity == true
        self.opacityLabel:SetShown(showOpacity); self.opacity:SetShown(showOpacity); self.opacityValue:SetShown(showOpacity)
        for i = 1, 3 do self.rgb[i]:SetShown(advanced); self.rgbLabels[i]:SetShown(advanced) end
        self.hexTitle:SetShown(advanced); self.hex:SetShown(advanced); self.copy:SetShown(advanced); self.save:SetShown(advanced)
        self.more:SetSize(advanced and ADVANCED_MORE_WIDTH or SIMPLE_MORE_WIDTH, 26)
        self.more:SetText(Tr(advanced and "Back to controls" or "More Options"))
        self.cancel:SetSize(advanced and ADVANCED_CANCEL_WIDTH or SIMPLE_CANCEL_WIDTH, 26)
        self.done:SetSize(advanced and ADVANCED_DONE_WIDTH or SIMPLE_DONE_WIDTH, 26)
        self.more:ClearAllPoints(); self.more:SetPoint("LEFT", ACTION_SIDE_PAD, 0)
        self.done:ClearAllPoints(); self.done:SetPoint("RIGHT", -ACTION_SIDE_PAD, 0)
        self.cancel:ClearAllPoints(); self.cancel:SetPoint("RIGHT", self.done, "LEFT", -ACTION_GAP, 0)
        self:ClampPosition()
    end

    function panel:SetAdvanced(advanced)
        self.advanced = advanced == true
        self._msuf2WindowState = self.advanced and "maximized" or "windowed"
        self:SetContextListShown(false); self:Layout()
        if self.advanced and self._palettesDirty then self:RefreshPalettes() else self:RefreshSelectedSwatch() end
        if M.RefreshWindowControls then M.RefreshWindowControls(self) end
    end
    function panel:SetPaletteTab(key)
        if key ~= "quick" and key ~= "class" and key ~= "recent" and key ~= "saved" then key = "quick" end
        self.paletteTab = key
        self:RefreshPalettes()
    end
    function panel:RefreshSelectedSwatch(r, g, b, hexValue)
        if not r and self.owner then r, g, b = self.owner:GetRGB() end
        local lookup = self.paletteLookups and self.paletteLookups[self.paletteTab or "quick"]
        local nextSwatch = r and lookup and lookup[hexValue or ToHex(r, g, b)] or nil
        if nextSwatch == self._selectedSwatch then return end
        if self._selectedSwatch and self._selectedSwatch.SetSelected then self._selectedSwatch:SetSelected(false) end
        self._selectedSwatch = nextSwatch
        if nextSwatch and nextSwatch.SetSelected then nextSwatch:SetSelected(true) end
    end
    function panel:RefreshPalettes()
        local store = Store() or {}
        local tab = self.paletteTab or "quick"
        local lookups = self.paletteLookups
        local function ClearLookup(lookup) for key in pairs(lookup) do lookup[key] = nil end end
        ClearLookup(lookups.class); ClearLookup(lookups.recent); ClearLookup(lookups.saved)
        local function Fill(buttons, values, visible, lookup)
            for i = 1, #buttons do
                local button, value = buttons[i], values and values[i]; button.hex = value
                button:SetShown(visible and value ~= nil)
                if value then
                    local vr, vg, vb = FromHex(value)
                    button.fill:SetColorTexture(vr or 1, vg or 1, vb or 1, 1)
                    lookup[value] = button
                end
            end
        end
        for i = 1, #self.spectrum do self.spectrum[i]:SetShown(tab == "quick") end
        for i = 1, #self.classes do
            local button = self.classes[i]; local color = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[button.token]
            button.fill:SetColorTexture(color and color.r or 1, color and color.g or 1, color and color.b or 1, 1)
            button:SetShown(tab == "class")
            if color then lookups.class[ToHex(color.r, color.g, color.b)] = button end
        end
        Fill(self.recent, store.recent, tab == "recent", lookups.recent)
        Fill(self.saved, store.saved, tab == "saved", lookups.saved)
        self.savedHint:SetShown(tab == "saved" and #store.saved > 0)
        local empty = (tab == "recent" and #store.recent == 0) or (tab == "saved" and #store.saved == 0)
        self.emptyHint:SetShown(empty)
        for i = 1, #self.paletteTabs do
            local button = self.paletteTabs[i]
            if button.SetActive then button:SetActive(button._msuf2PaletteKey == tab) end
        end
        self._palettesDirty = nil
        self:RefreshSelectedSwatch()
    end
    function panel:RefreshColorReadout(syncColorSelect, r, g, b)
        if not self.owner then return end
        if not r then r, g, b = self.owner:GetRGB() end
        self.current:SetColorTexture(r, g, b, 1)
        self.selector.color:SetColorTexture(r, g, b, 1)
        local byteR, byteG, byteB = Byte01(r), Byte01(g), Byte01(b)
        if byteR ~= self._readoutR or byteG ~= self._readoutG or byteB ~= self._readoutB then
            self._readoutR, self._readoutG, self._readoutB = byteR, byteG, byteB
            local hexValue = string.format("#%02X%02X%02X", byteR, byteG, byteB)
            self._readoutHex = hexValue
            self.compactHex:SetText(hexValue)
            if not self.hex:HasFocus() then self.hex:SetText(hexValue) end
            if not self.rgb[1]:HasFocus() then self.rgb[1]:SetText(byteR) end
            if not self.rgb[2]:HasFocus() then self.rgb[2]:SetText(byteG) end
            if not self.rgb[3]:HasFocus() then self.rgb[3]:SetText(byteB) end
            self:RefreshSelectedSwatch(r, g, b, hexValue)
        end
        if syncColorSelect and self.colorSelect then
            self._syncingColorSelect = true
            self.colorSelect:SetColorRGB(r, g, b)
            self._syncingColorSelect = nil
        end
    end
    function panel:RefreshOpacity(alpha)
        alpha = alpha == nil and OwnerOpacity(self.owner) or Clamp01(alpha)
        local hasOpacity = type(alpha) == "number"
        if hasOpacity then
            self._syncingOpacity = true
            self.opacity:SetValue(alpha)
            self._syncingOpacity = nil
            self.opacityValue:SetText(string.format("%d%%", floor(alpha * 100 + 0.5)))
        end
        local showOpacity = self.advanced and hasOpacity
        self.opacityLabel:SetShown(showOpacity)
        self.opacity:SetShown(showOpacity)
        self.opacityValue:SetShown(showOpacity)
    end
    function panel:Refresh()
        if not self.owner then return end
        local r, g, b = self.owner:GetRGB(); local originalValue = self.originals and self.originals[self.owner]
        self.original:SetColorTexture(originalValue and originalValue[1] or r, originalValue and originalValue[2] or g, originalValue and originalValue[3] or b, 1)
        self.selector.label:SetText(Tr(self.owner._msuf2ColorLabel or self.owner._msuf2SearchText or "Color"))
        self._readoutHex, self._readoutR, self._readoutG, self._readoutB = nil, nil, nil, nil
        self:RefreshColorReadout(true)
        self:RefreshOpacity()
        if self.advanced then self:RefreshPalettes() else self:RefreshSelectedSwatch(r, g, b, self._readoutHex) end
    end
    function panel:SetOwner(owner) if owner then self.owner = owner; self:Refresh() end end
    function panel:NotifyLiveChange(owner)
        local callback = self._msuf2OnLiveChange
        if type(callback) == "function" then InvokePickerCallback(callback, owner or self.owner) end
    end
    function panel:Apply(r, g, b, fromColorSelect)
        if not self.owner then return end
        r, g, b = Clamp01(r), Clamp01(g), Clamp01(b)
        local currentR, currentG, currentB = self.owner:GetRGB()
        if abs(r - currentR) < 0.000001 and abs(g - currentG) < 0.000001 and abs(b - currentB) < 0.000001 then return end
        if not self.historyOwner then
            self.historyOwner = self.owner
            if type(self.owner._msuf2BeginColorInteraction) == "function" then self.owner:_msuf2BeginColorInteraction() end
        end
        self.touched[self.owner] = true
        ApplyOwner(self.owner, r, g, b, nil, true)
        self:NotifyLiveChange(self.owner)
        self:RefreshColorReadout(fromColorSelect ~= true, r, g, b)
    end
    function panel:ApplyOpacity(alpha)
        if not self.owner or self.owner._msuf2ColorHasOpacity ~= true then return end
        alpha = Clamp01(alpha)
        local current = OwnerOpacity(self.owner)
        if current == nil or abs(alpha - current) < 0.000001 then
            self:RefreshOpacity(current)
            return
        end
        if not self.historyOwner then
            self.historyOwner = self.owner
            if type(self.owner._msuf2BeginColorInteraction) == "function" then self.owner:_msuf2BeginColorInteraction() end
        end
        self.touched[self.owner] = true
        local r, g, b = self.owner:GetRGB()
        ApplyOwner(self.owner, r, g, b, alpha, true)
        self:NotifyLiveChange(self.owner)
        self:RefreshOpacity(alpha)
    end
    function panel:Finish(cancelled)
        if self.finishing then return end
        self.finishing = true
        local onFinish = self._msuf2OnFinish
        self._msuf2OnFinish = nil
        if cancelled then
            for owner in pairs(self.touched or {}) do
                local value = self.originals and self.originals[owner]
                if value then
                    if value[5] ~= nil and type(owner._msuf2RestoreColorState) == "function" then owner:_msuf2RestoreColorState(value[5])
                    else ApplyOwner(owner, value[1], value[2], value[3], value[4]) end
                    self:NotifyLiveChange(owner)
                end
            end
        else
            for owner in pairs(self.touched or {}) do local r, g, b = owner:GetRGB(); AddRecent(ToHex(r, g, b)) end
            self._palettesDirty = true
        end
        if self.historyOwner and type(self.historyOwner._msuf2CommitColorInteraction) == "function" then self.historyOwner:_msuf2CommitColorInteraction() end
        self:SetContextListShown(false)
        HidePickerInfo(self.infoButton)
        self._ownerDropdownValues = nil
        self._msuf2OnLiveChange = nil
        self.owner, self.owners, self.originals, self.touched, self.historyOwner = nil, nil, nil, nil, nil
        self:Hide(); self.finishing = nil
        if type(onFinish) == "function" then InvokePickerCallback(onFinish, cancelled == true) end
    end
    function panel:Open(contextTitle, owners, contextNote, initialOwner, onFinish, scopeTag, onLiveChange)
        if self:IsShown() then
            self._msuf2OnFinish = nil
            self:Finish(false)
        end
        self:SetScale(PickerMenuScale())
        self.owners, self.originals, self.touched = {}, {}, {}
        for i = 1, #(owners or {}) do
            local owner = owners[i]
            if owner and owner.GetRGB and owner.SetRGB then
                self.owners[#self.owners + 1] = owner
                local r, g, b = owner:GetRGB(); self.originals[owner] = { r, g, b, OwnerOpacity(owner), OwnerState(owner) }
            end
        end
        if #self.owners == 0 then return end
        self._msuf2OnFinish = type(onFinish) == "function" and onFinish or nil
        self._msuf2OnLiveChange = type(onLiveChange) == "function" and onLiveChange or nil
        local visibleScope = Tr(scopeTag or "")
        self.title:SetText(Tr("MSUF Color Picker") .. (visibleScope ~= "" and (" · " .. visibleScope) or ""))
        local context = Tr(contextTitle or "Colors")
        local detail = Tr(contextNote or "Choose a target, then paint it.")
        self.infoButton._msuf2PickerInfoTitle = context
        self.infoButton._msuf2PickerInfoText = detail
        self.infoButton:SetShown(context ~= "" or detail ~= "")
        HidePickerInfo(self.infoButton)
        RefreshPickerFonts(self)
        local selected = self.owners[1]
        for i = 1, #self.owners do if self.owners[i] == initialOwner then selected = initialOwner; break end end
        self.owner = selected
        self.advanced = false
        self.paletteTab = "quick"
        self._palettesDirty = true
        self._msuf2WindowState = "windowed"
        self:RestorePosition(); self:SetContextListShown(false); self:Layout(); self:Refresh()
        ApplyPickerPriority(self, self.blocker)
        if M.RefreshWindowControls then M.RefreshWindowControls(self) end
        RaisePickerInfo(self)
        self.blocker:Show(); self:Show(); self:ClampPosition()
    end

    panel:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            if self._ownerDropdownOpen then self:SetContextListShown(false) else self:Finish(true) end
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
        elseif self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
    end)
    panel:HookScript("OnHide", function(self)
        HidePickerInfo(self.infoButton)
        if self.blocker then self.blocker:Hide() end
    end)
    if M.frame and M.frame.HookScript and not M.frame._msuf2ContextColorPickerHideHooked then
        M.frame._msuf2ContextColorPickerHideHooked = true
        M.frame:HookScript("OnHide", function() if picker and picker:IsShown() then picker:Finish(false) end end)
    end
    panel:Hide()
    return panel
end

function W.OpenColorContextPicker(contextTitle, owners, contextNote, initialOwner, onFinish, scopeTag, onLiveChange)
    local panel = EnsurePicker()
    if panel then panel:Open(contextTitle, owners, contextNote, initialOwner, onFinish, scopeTag, onLiveChange) end
    return panel
end
M.OpenColorContextPicker = W.OpenColorContextPicker
