local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local W = M.Widgets or {}
local T = M.Theme
local floor, max, min = math.floor, math.max, math.min
local Tr = M.TranslateText or M.Tr or function(text) return text end

-- Menu-only, progressive color editor. The compact view exposes the common
-- path; contextual targets and the large palettes stay one deliberate click
-- away. No runtime unit-frame hooks are installed.
local picker
local SIMPLE_WIDTH, SIMPLE_HEIGHT = 420, 424
local ADVANCED_WIDTH, ADVANCED_HEIGHT = 680, 548

local function Clamp01(value)
    value = tonumber(value) or 0
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end
local function Byte(value) return floor(Clamp01(value) * 255 + 0.5) end
local function ToHex(r, g, b) return string.format("#%02X%02X%02X", Byte(r), Byte(g), Byte(b)) end
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
    if T.SkinEditBox then T.SkinEditBox(edit) end
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); if picker then picker:Refresh() end end)
    edit:SetScript("OnEnterPressed", function(self)
        if type(self._commit) == "function" then self:_commit() end
        self:ClearFocus()
    end)
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
    chip.fill, chip.edge = fill, edge
    return chip
end
local function Swatch(parent, size, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local fill, edge = CreateTrueColorPill(button, "_msuf2PickerSwatch", 1)
    if fill then
        fill:SetColorTexture(1, 1, 1, 1)
        edge:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.88)
        button:HookScript("OnEnter", function() edge:SetColorTexture(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 1) end)
        button:HookScript("OnLeave", function() edge:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.88) end)
    else
        fill = button:CreateTexture(nil, "ARTWORK"); fill:SetAllPoints(); fill:SetColorTexture(1, 1, 1, 1)
    end
    button.fill = fill
    button:SetScript("OnClick", onClick)
    return button
end
local function ApplyOwner(owner, r, g, b)
    if not owner then return end
    r, g, b = Clamp01(r), Clamp01(g), Clamp01(b)
    owner:SetRGB(r, g, b)
    if type(owner._msuf2OnColorChanged) == "function" then owner._msuf2OnColorChanged(r, g, b) end
end

local function ContextRow(parent, index, scroll)
    local row = T.Button(parent, "", 478, 27)
    row._msuf2SkipHistoryCheckpoint = true
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * 30)
    local color = ColorChip(row, 17, 17)
    color:SetPoint("LEFT", 9, 0); row.color = color
    local label = row._msuf2Label
    label:ClearAllPoints(); label:SetPoint("LEFT", color, "RIGHT", 8, 0); label:SetPoint("RIGHT", -12, 0); label:SetJustifyH("LEFT"); row.label = label
    row:SetScript("OnClick", function(self)
        if not picker then return end
        picker:SetOwner(self.owner)
        picker:SetContextListShown(false)
    end)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta)
        local handler = scroll and scroll.GetScript and scroll:GetScript("OnMouseWheel")
        if type(handler) == "function" then handler(scroll, delta) end
    end)
    return row
end

local function EnsurePicker()
    if picker then return picker end
    local parent = _G.UIParent or M.frame
    if not parent then return nil end

    local blocker = CreateFrame("Button", nil, parent)
    blocker:SetAllPoints(parent); blocker:EnableMouse(true)
    local dim = blocker:CreateTexture(nil, "BACKGROUND"); dim:SetAllPoints(); dim:SetColorTexture(0, 0, 0, 0.12)
    blocker:SetScript("OnClick", function() if picker then picker:Finish(true) end end); blocker:Hide()

    local panel = T.Panel(parent, nil, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft)
    picker = panel
    panel:SetSize(SIMPLE_WIDTH, SIMPLE_HEIGHT); panel:SetClampedToScreen(true)
    panel:SetMovable(true); panel:EnableMouse(true); panel:EnableKeyboard(true)
    if panel.SetPropagateKeyboardInput then panel:SetPropagateKeyboardInput(true) end
    if T.ApplySurface then T.ApplySurface(panel, "popup") end
    if T.ApplyBackdrop then
        T.ApplyBackdrop(panel, { 0.045, 0.085, 0.140, 0.99 }, { 0.12, 0.44, 0.72, 0.96 })
    end
    panel._msuf2PickerBrightSurface = BrightSurface(panel, 0.040, 0.080, 0.130, 0.94)
    panel.blocker = blocker
    ApplyPickerPriority(panel, blocker)

    local close = T.CloseButton and T.CloseButton(panel)
    if close then
        close:SetPoint("TOPRIGHT", -10, -10)
        close:SetScript("OnClick", function() panel:Finish(true) end)
        panel.close = close
    end

    local drag = CreateFrame("Button", nil, panel)
    drag:SetPoint("TOPLEFT", 1, -1); drag:SetPoint("TOPRIGHT", -1, -1); drag:SetHeight(54)
    drag:RegisterForDrag("LeftButton"); drag:RegisterForClicks("LeftButtonUp")
    drag:SetScript("OnDragStart", function() panel:SetContextListShown(false); panel:StartMoving() end)
    drag:SetScript("OnDragStop", function() panel:StopMovingOrSizing(); panel:SavePosition() end)
    drag:SetScript("OnDoubleClick", function() panel:ResetPosition() end)
    if M.AddTooltip then M.AddTooltip(drag, "Move color picker", "Drag to move. Double-click to center it again.") end

    local title = Font(panel, "GameFontNormalLarge", "Color Painter", T.colors.text)
    title:SetPoint("TOPLEFT", 16, -13); panel.title = title
    local note = Font(panel, "GameFontDisableSmall", "", T.colors.muted)
    note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3); note:SetWidth(SIMPLE_WIDTH - 50); note:SetJustifyH("LEFT"); panel.note = note
    local moveHint = Font(panel, "GameFontDisableSmall", "drag to move", T.colors.dim)
    moveHint:SetPoint("TOPRIGHT", close or panel, close and "TOPLEFT" or "TOPRIGHT", close and -8 or -16, close and 0 or -16)

    local selector = T.Button(panel, "", SIMPLE_WIDTH - 32, 34)
    selector._msuf2SkipHistoryCheckpoint = true
    selector:SetPoint("TOPLEFT", 16, -66); selector:SetSize(SIMPLE_WIDTH - 32, 34)
    local selectorColor = ColorChip(selector, 20, 20); selectorColor:SetPoint("LEFT", 10, 0)
    local selectorLabel = selector._msuf2Label; selectorLabel:ClearAllPoints(); selectorLabel:SetPoint("LEFT", selectorColor, "RIGHT", 9, 0); selectorLabel:SetPoint("RIGHT", -34, 0); selectorLabel:SetJustifyH("LEFT")
    local selectorArrow = Font(selector, "GameFontNormal", "v", T.colors.muted); selectorArrow:SetPoint("RIGHT", -12, 0)
    selector.color, selector.label, selector.arrow = selectorColor, selectorLabel, selectorArrow
    selector:SetScript("OnClick", function() panel:SetContextListShown(not panel.contextList:IsShown()) end)
    panel.selector = selector

    local contextList = T.Panel(panel, nil, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft)
    contextList:SetPoint("TOPLEFT", selector, "BOTTOMLEFT", 0, -4); contextList:SetWidth(SIMPLE_WIDTH - 32)
    contextList:SetFrameLevel(panel:GetFrameLevel() + 40)
    if T.ApplySurface then T.ApplySurface(contextList, "popup") end
    if T.ApplyBackdrop then
        T.ApplyBackdrop(contextList, { 0.045, 0.085, 0.140, 0.995 }, { 0.12, 0.44, 0.72, 0.98 })
    end
    contextList._msuf2PickerBrightSurface = BrightSurface(contextList, 0.040, 0.080, 0.130, 0.97)
    local contextScroll = CreateFrame("ScrollFrame", nil, contextList)
    contextScroll:SetPoint("TOPLEFT", 10, -8); contextScroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local contextChild = CreateFrame("Frame", nil, contextScroll)
    contextChild:SetWidth(478); contextChild:SetHeight(1); contextScroll:SetScrollChild(contextChild)
    contextList.scroll, contextList.child = contextScroll, contextChild
    if T.StyleScrollFrame then contextList.scrollBar = T.StyleScrollFrame(contextScroll, contextList) end
    contextList:Hide(); panel.contextList = contextList
    panel.rows = {}
    for i = 1, 14 do panel.rows[i] = ContextRow(contextChild, i, contextScroll) end

    local original = ColorChip(panel, 186, 30); original:SetPoint("TOPLEFT", 16, -126)
    local current = ColorChip(panel, 186, 30); current:SetPoint("TOPRIGHT", -16, -126)
    panel.original, panel.current = original, current
    local originalLabel = Font(panel, "GameFontDisableSmall", "Original", T.colors.dim); originalLabel:SetPoint("BOTTOMLEFT", original, "TOPLEFT", 0, 2)
    local currentLabel = Font(panel, "GameFontDisableSmall", "Current", T.colors.dim); currentLabel:SetPoint("BOTTOMLEFT", current, "TOPLEFT", 0, 2)

    local wheelCard = T.Panel(panel, nil, { 0.065, 0.120, 0.190, 0.99 }, T.colors.cardBorder or T.colors.borderSoft)
    wheelCard:SetPoint("TOPLEFT", 16, -174); wheelCard:SetSize(SIMPLE_WIDTH - 32, 196)
    if T.ApplySurface then T.ApplySurface(wheelCard, "card") end
    if T.ApplyBackdrop then T.ApplyBackdrop(wheelCard, { 0.065, 0.120, 0.190, 0.99 }, { 0.12, 0.40, 0.66, 0.94 }) end
    wheelCard._msuf2PickerBrightSurface = BrightSurface(wheelCard, 0.060, 0.115, 0.185, 0.96)
    local wheelTitle = Font(wheelCard, "GameFontNormalSmall", "Color & brightness", T.colors.text)
    wheelTitle:SetPoint("TOPLEFT", 12, -10)

    -- Use Blizzard's native ColorSelect engine. This is the same wheel/value
    -- interaction as ColorPickerFrame, embedded in the MSUF surface so the
    -- target selector, live preview and palettes remain one compact workflow.
    local colorSelect = CreateFrame("ColorSelect", nil, wheelCard)
    colorSelect:SetPoint("TOPLEFT", 97, -34); colorSelect:SetSize(194, 142)
    local wheel = colorSelect:CreateTexture(nil, "ARTWORK")
    wheel:SetPoint("TOPLEFT", 0, -7); wheel:SetSize(128, 128)
    colorSelect:SetColorWheelTexture(wheel)
    colorSelect:SetColorWheelThumbTexture("Interface\\Buttons\\UI-ColorPicker-Buttons")
    local wheelThumb = colorSelect:GetColorWheelThumbTexture()
    wheelThumb:SetSize(10, 10); wheelThumb:SetTexCoord(0, 0.15625, 0, 0.625)
    local value = colorSelect:CreateTexture(nil, "ARTWORK")
    value:SetPoint("LEFT", wheel, "RIGHT", 24, 0); value:SetSize(32, 128)
    colorSelect:SetColorValueTexture(value)
    colorSelect:SetColorValueThumbTexture("Interface\\Buttons\\UI-ColorPicker-Buttons")
    local valueThumb = colorSelect:GetColorValueThumbTexture()
    valueThumb:SetSize(48, 14); valueThumb:SetTexCoord(0.25, 1.0, 0, 0.875)
    colorSelect:SetScript("OnColorSelect", function(_, r, g, b)
        if not panel._syncingColorSelect then panel:Apply(r, g, b) end
    end)
    panel.colorSelect, panel.wheelCard = colorSelect, wheelCard

    local advancedCard = T.Panel(panel, nil, { 0.055, 0.105, 0.170, 0.99 }, T.colors.cardBorder or T.colors.borderSoft)
    advancedCard:SetPoint("TOPLEFT", 280, -174); advancedCard:SetSize(384, 310)
    if T.ApplySurface then T.ApplySurface(advancedCard, "card") end
    if T.ApplyBackdrop then T.ApplyBackdrop(advancedCard, { 0.055, 0.105, 0.170, 0.99 }, { 0.12, 0.40, 0.66, 0.94 }) end
    advancedCard._msuf2PickerBrightSurface = BrightSurface(advancedCard, 0.050, 0.100, 0.165, 0.96)
    advancedCard:Hide(); panel.advancedCard = advancedCard

    local spectrumTitle = Font(advancedCard, "GameFontNormalSmall", "Quick colors", T.colors.text); panel.spectrumTitle = spectrumTitle
    panel.spectrum = {}
    local tones = { { 0.92, 1.00 }, { 0.70, 0.88 }, { 0.48, 0.62 } }
    for row = 1, 3 do
        for col = 1, 12 do
            local r, g, b = HSV((col - 1) / 12, tones[row][1], tones[row][2])
            local swatch = Swatch(advancedCard, 25, function(self) panel:Apply(self.r, self.g, self.b) end)
            swatch.r, swatch.g, swatch.b, swatch.toneRow = r, g, b, row
            swatch.fill:SetColorTexture(r, g, b, 1); panel.spectrum[#panel.spectrum + 1] = swatch
        end
    end

    local rgbTitle = Font(advancedCard, "GameFontNormalSmall", "RGB", T.colors.muted); panel.rgbTitle = rgbTitle
    panel.rgb, panel.rgbLabels = {}, {}
    for i, channel in ipairs({ "R", "G", "B" }) do
        local input = Input(advancedCard, 58, true)
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
    local hex = Input(advancedCard, 112, false); panel.hex = hex
    hex._commit = function(self)
        local r, g, b = FromHex(self:GetText())
        if r then panel:Apply(r, g, b) else panel:Refresh() end
    end
    local copy = T.Button(advancedCard, Tr("Copy"), 64, 22); panel.copy = copy
    copy:SetScript("OnClick", function() hex:SetFocus(); hex:HighlightText() end)
    local save = T.Button(advancedCard, Tr("Save"), 64, 22); panel.save = save
    save:SetScript("OnClick", function()
        if not panel.owner then return end
        local store = Store(); if not store then return end
        local r, g, b = panel.owner:GetRGB(); local value = ToHex(r, g, b)
        for i = 1, #store.saved do if store.saved[i] == value then return end end
        if #store.saved < 27 then store.saved[#store.saved + 1] = value end
        panel:RefreshPalettes()
    end)

    local recentTitle = Font(advancedCard, "GameFontNormalSmall", "Recent", T.colors.text); panel.recentTitle = recentTitle
    panel.recent = {}
    for i = 1, 9 do
        panel.recent[i] = Swatch(advancedCard, 23, function(self)
            local r, g, b = FromHex(self.hex); if r then panel:Apply(r, g, b) end
        end)
    end

    local savedTitle = Font(advancedCard, "GameFontNormalSmall", "Saved colors", T.colors.text); panel.savedTitle = savedTitle
    local savedHint = Font(advancedCard, "GameFontDisableSmall", "right-click to remove", T.colors.dim); panel.savedHint = savedHint
    panel.saved = {}
    for i = 1, 27 do
        local swatch = Swatch(advancedCard, 23, function(self, button)
            local store = Store()
            if button == "RightButton" and store then table.remove(store.saved, self.index); panel:RefreshPalettes(); return end
            local r, g, b = FromHex(self.hex); if r then panel:Apply(r, g, b) end
        end)
        swatch.index = i; panel.saved[i] = swatch
    end

    local classTitle = Font(wheelCard, "GameFontNormalSmall", "Class colors", T.colors.text); panel.classTitle = classTitle
    panel.classes = {}
    local tokens = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER" }
    for i = 1, #tokens do
        local swatch = Swatch(wheelCard, 25, function(self)
            local color = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[self.token]
            if color then panel:Apply(color.r, color.g, color.b) end
        end)
        swatch.token = tokens[i]; panel.classes[i] = swatch
        if M.AddTooltip then M.AddTooltip(swatch, tokens[i], Tr("Apply this class color.")) end
    end

    local more = T.Button(panel, Tr("More colors"), 112, 24); panel.more = more
    more._msuf2SkipHistoryCheckpoint = true
    more:SetScript("OnClick", function() panel:SetAdvanced(not panel.advanced) end)
    if M.AddTooltip then
        M.AddTooltip(more, "Advanced color tools", "Quick colors, precise RGB and HEX values, recent colors, saved colors, and class colors.")
    end
    local cancel = T.Button(panel, Tr("Cancel"), 92, 24); panel.cancel = cancel
    cancel:SetScript("OnClick", function() panel:Finish(true) end)
    local done = T.Button(panel, Tr("Done"), 92, 24); panel.done = done
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

    function panel:SetContextListShown(shown)
        shown = shown == true and #(self.owners or {}) > 1
        self.contextList:SetShown(shown)
        self.selector.arrow:SetText(shown and "^" or "v")
        if shown then
            local ownerCount = min(#self.owners, #self.rows)
            local visibleRows = min(ownerCount, 7)
            self.contextList:SetHeight(16 + visibleRows * 30)
            self.contextList.child:SetHeight(max(1, ownerCount * 30))
            self.contextList.scroll._msuf2MaxScroll = max(0, ownerCount * 30 - visibleRows * 30)
            self.contextList.scroll:SetVerticalScroll(0)
            if self.contextList.scroll._msuf2RefreshScrollBar then self.contextList.scroll:_msuf2RefreshScrollBar() end
            self:RefreshRows()
        else
            self:Layout()
        end
    end

    function panel:Layout()
        local advanced = self.advanced == true
        local width = advanced and ADVANCED_WIDTH or SIMPLE_WIDTH
        local height = advanced and ADVANCED_HEIGHT or SIMPLE_HEIGHT
        local previewWidth = (width - 48) * 0.5
        local selectorWidth = width - 32
        local contextContentWidth = width - 82
        self:SetSize(width, height)
        self.note:SetWidth(width - 50)
        self.selector:SetWidth(selectorWidth)
        self.contextList:SetWidth(selectorWidth)
        self.contextList.child:SetWidth(contextContentWidth)
        for i = 1, #self.rows do self.rows[i]:SetWidth(contextContentWidth) end
        self.original:SetWidth(previewWidth); self.current:SetWidth(previewWidth)

        self.wheelCard:ClearAllPoints(); self.wheelCard:SetPoint("TOPLEFT", 16, -174)
        self.wheelCard:SetSize(advanced and 248 or width - 32, advanced and 310 or 196)
        self.colorSelect:ClearAllPoints()
        self.colorSelect:SetPoint("TOPLEFT", advanced and 27 or 97, -34)
        self.advancedCard:SetShown(advanced)

        self.spectrumTitle:ClearAllPoints(); self.spectrumTitle:SetPoint("TOPLEFT", 16, -14)
        self.spectrumTitle:SetText(Tr("Quick colors")); self.spectrumTitle:SetShown(advanced)
        for i = 1, #self.spectrum do
            local swatch = self.spectrum[i]; local slot = i - 1
            local col, row = slot % 12, floor(slot / 12)
            swatch:ClearAllPoints(); swatch:SetPoint("TOPLEFT", 16 + col * 29, -36 - row * 26)
            swatch:SetShown(advanced)
        end
        local rgbY, hexY, recentY = -120, -154, -188
        self.rgbTitle:ClearAllPoints(); self.rgbTitle:SetPoint("TOPLEFT", 16, rgbY)
        for i = 1, 3 do
            self.rgb[i]:ClearAllPoints(); self.rgb[i]:SetPoint("TOPLEFT", 54 + (i - 1) * 76, rgbY + 4)
            self.rgbLabels[i]:ClearAllPoints(); self.rgbLabels[i]:SetPoint("RIGHT", self.rgb[i], "LEFT", -3, 0)
            self.rgb[i]:SetShown(advanced); self.rgbLabels[i]:SetShown(advanced)
        end
        self.rgbTitle:SetShown(advanced)
        self.hexTitle:ClearAllPoints(); self.hexTitle:SetPoint("TOPLEFT", 16, hexY)
        self.hex:ClearAllPoints(); self.hex:SetPoint("TOPLEFT", 54, hexY + 4)
        self.copy:ClearAllPoints(); self.copy:SetPoint("LEFT", self.hex, "RIGHT", 8, 0)
        self.save:ClearAllPoints(); self.save:SetPoint("LEFT", self.copy, "RIGHT", 6, 0)
        self.hexTitle:SetShown(advanced); self.hex:SetShown(advanced); self.copy:SetShown(advanced); self.save:SetShown(advanced)
        self.recentTitle:ClearAllPoints(); self.recentTitle:SetPoint("TOPLEFT", 16, recentY); self.recentTitle:SetShown(advanced)
        for i = 1, #self.recent do
            self.recent[i]:ClearAllPoints(); self.recent[i]:SetPoint("TOPLEFT", 16 + (i - 1) * 31, recentY - 20)
            self.recent[i]:SetShown(advanced and self.recent[i].hex ~= nil)
        end

        self.savedTitle:SetShown(advanced); self.savedHint:SetShown(advanced); self.classTitle:SetShown(advanced)
        self.savedTitle:ClearAllPoints(); self.savedTitle:SetPoint("TOPLEFT", 16, -240)
        self.savedHint:ClearAllPoints(); self.savedHint:SetPoint("TOPRIGHT", -16, -240)
        for i = 1, #self.saved do
            local col, row = (i - 1) % 14, floor((i - 1) / 14)
            self.saved[i]:ClearAllPoints(); self.saved[i]:SetPoint("TOPLEFT", 16 + col * 26, -260 - row * 25)
            self.saved[i]:SetShown(advanced and self.saved[i].hex ~= nil)
        end
        self.classTitle:ClearAllPoints(); self.classTitle:SetPoint("TOPLEFT", 12, -192)
        for i = 1, #self.classes do
            local col, row = (i - 1) % 7, floor((i - 1) / 7)
            self.classes[i]:ClearAllPoints(); self.classes[i]:SetPoint("TOPLEFT", 12 + col * 32, -214 - row * 32)
            self.classes[i]:SetShown(advanced)
        end
        self.more:SetSize(132, 24); self.more:SetText(Tr(advanced and "Back to controls" or "Advanced"))
        self.more:ClearAllPoints(); self.more:SetPoint("BOTTOMLEFT", 16, 14)
        self.cancel:ClearAllPoints(); self.cancel:SetPoint("BOTTOMRIGHT", -112, 14)
        self.done:ClearAllPoints(); self.done:SetPoint("BOTTOMRIGHT", -14, 14)
    end

    function panel:SetAdvanced(advanced)
        self.advanced = advanced == true
        self:SetContextListShown(false); self:Layout(); self:RefreshPalettes()
    end
    function panel:RefreshRows()
        for i = 1, #self.rows do
            local row, owner = self.rows[i], self.owners and self.owners[i]
            row.owner = owner; row:SetShown(owner ~= nil)
            if owner then
                local r, g, b = owner:GetRGB(); row.color:SetColorTexture(r, g, b, 1)
                row.label:SetText(Tr(owner._msuf2ColorLabel or owner._msuf2SearchText or "Color"))
                local active = owner == self.owner
                if row.SetActive then row:SetActive(active) end
            end
        end
    end
    function panel:RefreshPalettes()
        local store = Store() or {}
        local function Fill(buttons, values)
            for i = 1, #buttons do
                local button, value = buttons[i], values and values[i]; button.hex = value
                button:SetShown(self.advanced and value ~= nil)
                if value then local r, g, b = FromHex(value); button.fill:SetColorTexture(r or 1, g or 1, b or 1, 1) end
            end
        end
        Fill(self.recent, store.recent); Fill(self.saved, store.saved)
        for i = 1, #self.classes do
            local button = self.classes[i]; local color = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[button.token]
            button.fill:SetColorTexture(color and color.r or 1, color and color.g or 1, color and color.b or 1, 1); button:SetShown(self.advanced)
        end
    end
    function panel:Refresh()
        if not self.owner then return end
        local r, g, b = self.owner:GetRGB(); local originalValue = self.originals and self.originals[self.owner]
        self.current:SetColorTexture(r, g, b, 1)
        self.original:SetColorTexture(originalValue and originalValue[1] or r, originalValue and originalValue[2] or g, originalValue and originalValue[3] or b, 1)
        self.selector.color:SetColorTexture(r, g, b, 1)
        self.selector.label:SetText(Tr("Editing") .. "  -  " .. Tr(self.owner._msuf2ColorLabel or self.owner._msuf2SearchText or "Color"))
        if not self.hex:HasFocus() then self.hex:SetText(ToHex(r, g, b)) end
        local bytes = { Byte(r), Byte(g), Byte(b) }
        for i = 1, 3 do if not self.rgb[i]:HasFocus() then self.rgb[i]:SetText(bytes[i]) end end
        if self.colorSelect then
            self._syncingColorSelect = true
            self.colorSelect:SetColorRGB(r, g, b)
            self._syncingColorSelect = nil
        end
        self:RefreshRows(); self:RefreshPalettes()
    end
    function panel:SetOwner(owner) if owner then self.owner = owner; self:Refresh() end end
    function panel:Apply(r, g, b)
        if not self.owner then return end
        if not self.historyOwner then
            self.historyOwner = self.owner
            if type(self.owner._msuf2BeginColorInteraction) == "function" then self.owner:_msuf2BeginColorInteraction() end
        end
        self.touched[self.owner] = true; ApplyOwner(self.owner, r, g, b); self:Refresh()
    end
    function panel:Finish(cancelled)
        if self.finishing then return end
        self.finishing = true
        if cancelled then
            for owner in pairs(self.touched or {}) do local value = self.originals and self.originals[owner]; if value then ApplyOwner(owner, value[1], value[2], value[3]) end end
        else
            for owner in pairs(self.touched or {}) do local r, g, b = owner:GetRGB(); AddRecent(ToHex(r, g, b)) end
        end
        if self.historyOwner and type(self.historyOwner._msuf2CommitColorInteraction) == "function" then self.historyOwner:_msuf2CommitColorInteraction() end
        self.owner, self.owners, self.originals, self.touched, self.historyOwner = nil, nil, nil, nil, nil
        self.contextList:Hide(); self:Hide(); self.finishing = nil
    end
    function panel:Open(contextTitle, owners, contextNote, initialOwner)
        if self:IsShown() then self:Finish(false) end
        self.owners, self.originals, self.touched = {}, {}, {}
        for i = 1, #(owners or {}) do
            local owner = owners[i]
            if owner and owner.GetRGB and owner.SetRGB then
                self.owners[#self.owners + 1] = owner
                local r, g, b = owner:GetRGB(); self.originals[owner] = { r, g, b }
            end
        end
        if #self.owners == 0 then return end
        self.title:SetText(Tr("MSUF Color Picker"))
        local context = Tr(contextTitle or "Colors")
        local detail = Tr(contextNote or "Choose a target, then paint it.")
        self.note:SetText(context .. "  -  " .. detail)
        local selected = self.owners[1]
        for i = 1, #self.owners do if self.owners[i] == initialOwner then selected = initialOwner; break end end
        self.owner = selected
        self.advanced = false
        self:RestorePosition(); self:SetContextListShown(false); self:Layout(); self:Refresh()
        ApplyPickerPriority(self, self.blocker)
        self.blocker:Show(); self:Show()
    end

    panel:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            if self.contextList:IsShown() then self:SetContextListShown(false) else self:Finish(true) end
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
        elseif self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
    end)
    panel:HookScript("OnHide", function(self) if self.blocker then self.blocker:Hide() end end)
    if M.frame and M.frame.HookScript and not M.frame._msuf2ContextColorPickerHideHooked then
        M.frame._msuf2ContextColorPickerHideHooked = true
        M.frame:HookScript("OnHide", function() if picker and picker:IsShown() then picker:Finish(false) end end)
    end
    panel:Hide()
    return panel
end

function W.OpenColorContextPicker(contextTitle, owners, contextNote, initialOwner)
    local panel = EnsurePicker()
    if panel then panel:Open(contextTitle, owners, contextNote, initialOwner) end
    return panel
end
M.OpenColorContextPicker = W.OpenColorContextPicker
