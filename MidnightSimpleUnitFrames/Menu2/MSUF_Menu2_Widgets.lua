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
local sliderSerial = 0

local function HideSliderTemplateParts(slider)
    if not slider then return end
    local thumb = slider.GetThumbTexture and slider:GetThumbTexture()
    local regions = { slider:GetRegions() }
    for i = 1, #regions do
        local region = regions[i]
        local isTexture = false
        if region and region.IsObjectType then isTexture = region:IsObjectType("Texture") and true or false end
        if (not isTexture) and region and region.GetObjectType then isTexture = (region:GetObjectType() == "Texture") end
        if isTexture and region ~= thumb and region ~= slider._msufTrack and region ~= slider._msufFill then
            if region.SetAlpha then region:SetAlpha(0) end
            if region.Hide then region:Hide() end
        end
    end

    local name = slider.GetName and slider:GetName()
    for _, suffix in ipairs({ "Text", "Low", "High" }) do
        local region = (name and _G[name .. suffix]) or slider[suffix]
        if region then
            if region.SetText then region:SetText("") end
            if region.SetAlpha then region:SetAlpha(0) end
            if region.Hide then region:Hide() end
        end
    end
end

function W.PageBuilder(ctx)
    local b = {
        ctx = ctx,
        parent = ctx.wrapper,
        x = 12,
        y = -12,
        width = ctx.width or 720,
        collapsibles = {},
    }

    function b:RelayoutCollapsibles()
        if not self._collapsibleStartY then return end
        local y = self._collapsibleStartY
        for i = 1, #self.collapsibles do
            local entry = self.collapsibles[i]
            local open = entry.open and true or false
            entry.outer:ClearAllPoints()
            entry.outer:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, y)
            entry.outer:SetHeight(entry.headerHeight + (open and entry.contentHeight or 0))
            entry.body:SetShown(open)
            T.ApplyCollapseVisual(entry.arrow, entry.hint, open)
            y = y - entry.outer:GetHeight() - 8
        end
        self.y = y
        if ctx.SetContentHeight then ctx:SetContentHeight(math.abs(y) + 42) end
    end

    function b:Section(title, height)
        local section = T.Panel(self.parent, nil, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft)
        section:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, self.y)
        section:SetSize(self.width, height or 120)
        section._msuf2CursorY = -38
        section._msuf2ContentX = 14
        section._msuf2Width = self.width

        local fs = T.Font(section, "GameFontNormal", title or "", T.colors.text)
        fs:SetPoint("TOPLEFT", 14, -12)
        section.title = fs

        self.y = self.y - (height or 120) - 12
        if ctx.SetContentHeight then ctx:SetContentHeight(math.abs(self.y) + 28) end
        return section
    end

    function b:CollapsibleSection(id, title, height, defaultOpen)
        M.accordionState = M.accordionState or {}
        local stateKey = tostring(ctx.key or "page") .. ":" .. tostring(id or title or "section")
        local saved = M.accordionState[stateKey]
        local open = (saved == nil) and (defaultOpen and true or false) or (saved and true or false)
        local headerH = 28

        if not self._collapsibleStartY then self._collapsibleStartY = self.y end

        local outer = T.Panel(self.parent, nil, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft)
        outer:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, self.y)
        outer:SetSize(self.width, headerH + (open and (height or 120) or 0))

        local header = CreateFrame("Button", nil, outer)
        header:SetPoint("TOPLEFT", outer, "TOPLEFT", 0, 0)
        header:SetPoint("TOPRIGHT", outer, "TOPRIGHT", 0, 0)
        header:SetHeight(headerH)
        local headerBg = header:CreateTexture(nil, "BACKGROUND")
        headerBg:SetAllPoints()
        headerBg:SetColorTexture(0.060, 0.070, 0.130, 0.48)
        local headerHover = header:CreateTexture(nil, "HIGHLIGHT")
        headerHover:SetAllPoints()
        headerHover:SetColorTexture(1, 1, 1, 0.03)

        local arrow = header:CreateTexture(nil, "OVERLAY")
        arrow:SetSize(10, 10)
        arrow:SetPoint("LEFT", header, "LEFT", 12, 0)
        arrow:SetTexture(T.media.collapseArrow)

        local label = T.Font(header, "GameFontNormal", title or "", T.colors.text)
        label:SetPoint("LEFT", arrow, "RIGHT", 6, 0)
        label:SetPoint("RIGHT", header, "RIGHT", -140, 0)
        label:SetJustifyH("LEFT")

        local hint = T.Font(header, "GameFontDisableSmall", "", T.colors.dim)
        hint:SetPoint("RIGHT", header, "RIGHT", -12, 0)
        hint:SetJustifyH("RIGHT")

        local body = CreateFrame("Frame", nil, outer)
        body:SetPoint("TOPLEFT", outer, "TOPLEFT", 0, -headerH)
        body:SetSize(self.width, height or 120)
        body._msuf2CursorY = -38
        body._msuf2ContentX = 14
        body._msuf2Width = self.width

        local entry = {
            outer = outer,
            header = header,
            body = body,
            arrow = arrow,
            label = label,
            hint = hint,
            open = open,
            headerHeight = headerH,
            contentHeight = height or 120,
            stateKey = stateKey,
        }
        outer._msuf2CollapsibleEntry = entry
        body._msuf2CollapsibleEntry = entry
        self.collapsibles[#self.collapsibles + 1] = entry
        header:SetScript("OnClick", function()
            entry.open = not entry.open
            M.accordionState[stateKey] = entry.open
            self:RelayoutCollapsibles()
        end)

        self.y = self.y - outer:GetHeight() - 8
        self:RelayoutCollapsibles()
        return body
    end

    function b:Header(title, subtitle, height)
        local section = T.Panel(self.parent, nil, T.colors.panel2, T.colors.border)
        section:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, self.y)
        section:SetSize(self.width, height or 78)
        local fs = T.Font(section, "GameFontNormalLarge", title or "", T.colors.text)
        fs:SetPoint("TOPLEFT", 14, -12)
        if subtitle and subtitle ~= "" then
            local sub = T.Font(section, "GameFontDisableSmall", subtitle, T.colors.muted)
            sub:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -6)
            sub:SetWidth(self.width - 28)
            sub:SetJustifyH("LEFT")
        end
        self.y = self.y - (height or 78) - 12
        if ctx.SetContentHeight then ctx:SetContentHeight(math.abs(self.y) + 28) end
        return section
    end

    function b:Spacer(height)
        self.y = self.y - (height or 10)
        if ctx.SetContentHeight then ctx:SetContentHeight(math.abs(self.y) + 28) end
    end

    return b
end

function W.SetCollapsibleToggleText(section, openText, closedText)
    local entry = section and section._msuf2CollapsibleEntry
    if not (entry and entry.label and entry.label.SetText) then return nil end

    local function Refresh()
        entry.label:SetText(entry.open and (openText or "") or (closedText or openText or ""))
    end

    if entry.header and entry.header.HookScript and not entry._msuf2DynamicTitleHooked then
        entry._msuf2DynamicTitleHooked = true
        entry.header:HookScript("OnClick", Refresh)
    end
    Refresh()
    return Refresh
end

local function NextRow(section, height)
    local y = section._msuf2CursorY or -38
    section._msuf2CursorY = y - (height or 28)
    return section._msuf2ContentX or 14, y
end

local function CreateToggle(section, label, x, y, labelWidth)
    local btn = CreateFrame("CheckButton", nil, section, "UICheckButtonTemplate")
    btn:SetPoint("TOPLEFT", x, y)
    btn:SetSize(24, 24)

    btn._msuf2Label = T.Font(section, "GameFontHighlightSmall", label or "", T.colors.text)
    btn._msuf2Label:SetPoint("LEFT", btn, "RIGHT", 6, 0)
    btn._msuf2Label:SetJustifyH("LEFT")
    if labelWidth then btn._msuf2Label:SetWidth(labelWidth) end
    btn.text = btn._msuf2Label
    if T.StyleCheckmark then T.StyleCheckmark(btn) end
    btn:HookScript("OnShow", function(self)
        if T.StyleCheckmark then T.StyleCheckmark(self) end
    end)

    local labelHit = CreateFrame("Button", nil, section)
    labelHit:SetFrameLevel(btn:GetFrameLevel() + 2)
    labelHit:SetPoint("TOPLEFT", btn._msuf2Label, "TOPLEFT", -2, 2)
    labelHit:SetPoint("BOTTOMRIGHT", btn._msuf2Label, "BOTTOMRIGHT", 2, -2)
    labelHit:SetScript("OnClick", function()
        if btn.IsEnabled and not btn:IsEnabled() then return end
        if btn.Click then btn:Click() end
    end)
    labelHit:SetScript("OnEnter", function()
        if btn.LockHighlight then btn:LockHighlight() end
    end)
    labelHit:SetScript("OnLeave", function()
        if btn.UnlockHighlight then btn:UnlockHighlight() end
    end)
    btn._msuf2LabelHit = labelHit
    btn:SetChecked(false)
    return btn
end

function W.Text(parent, text, x, y, width, color)
    local fs = T.Font(parent, "GameFontHighlightSmall", text or "", color or T.colors.muted)
    fs:SetPoint("TOPLEFT", x or 0, y or 0)
    fs:SetWidth(width or 300)
    fs:SetJustifyH("LEFT")
    return fs
end

function W.Toggle(section, label)
    local x, y = NextRow(section, 30)
    return CreateToggle(section, label, x, y)
end

function W.ToggleAt(section, label, x, y, labelWidth)
    return CreateToggle(section, label, x or 14, y or -38, labelWidth)
end

local function ScopeButtonWidth(item)
    if item and item.width then return item.width end
    local value = item and item.value
    local text = tostring((item and (item.text or item.label)) or value or "")
    if value == "shared" then return 72 end
    if value == "targettarget" then return 58 end
    if text == "Boss 1" or text == "Boss 2" or text == "Boss 3" or text == "Boss 4" or text == "Boss 5" then return 74 end
    return math.max(54, math.min(96, 28 + (#text * 7)))
end

function W.ScopeOverrideBar(ctx, section, opts)
    opts = opts or {}
    local values = opts.values or {}
    local centerY = opts.centerY or -28
    local labelX = opts.labelX or 14
    local labelW = opts.labelWidth or 64
    local gap = opts.gap or 8
    local buttonH = opts.buttonHeight or 24
    local sectionW = opts.width or section._msuf2Width or (ctx and ctx.width) or (section.GetWidth and section:GetWidth()) or 720
    local maxRight = opts.maxRight or (sectionW - 14)
    local startX = opts.startX or (labelX + labelW + 8)

    local label = T.Font(section, opts.labelFont or "GameFontHighlightSmall", opts.label or "Editing:", opts.labelColor or T.colors.text)
    label:SetPoint("LEFT", section, "TOPLEFT", labelX, centerY)
    label:SetWidth(labelW)
    label:SetJustifyH("LEFT")

    local bar = CreateFrame("Frame", nil, section)
    bar:SetPoint("TOPLEFT", section, "TOPLEFT", 0, 0)
    bar:SetSize(sectionW, math.abs(centerY) + buttonH)
    bar.buttons = {}
    bar.values = values
    bar.label = label

    local x, y = startX, centerY
    for i = 1, #values do
        local item = values[i]
        local width = ScopeButtonWidth(item)
        if x > startX and x + width > maxRight then
            x = startX
            y = y - (buttonH + 6)
        end
        local btn = T.Button(section, item.text or item.label or item.value or "", width, buttonH)
        btn:SetPoint("LEFT", section, "TOPLEFT", x, y)
        btn._msuf2Value = item.value
        btn._msuf2BaseWidth = width
        if btn._msuf2Label then
            btn._msuf2Label:ClearAllPoints()
            btn._msuf2Label:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn._msuf2Label:SetJustifyH("CENTER")
        end
        btn:SetScript("OnClick", function()
            if type(opts.setValue) == "function" then opts.setValue(item.value) end
            if type(opts.onChange) == "function" then opts.onChange(item.value) end
            if bar.Refresh then bar:Refresh() end
        end)
        bar.buttons[i] = btn
        x = x + width + gap
    end

    function bar:GetValue()
        if type(opts.getValue) == "function" then return opts.getValue() end
        return opts.value
    end
    function bar:Refresh()
        local value = self:GetValue()
        for i = 1, #self.buttons do
            local btn = self.buttons[i]
            local active = btn._msuf2Value == value
            local override = false
            if type(opts.hasOverride) == "function" then override = opts.hasOverride(btn._msuf2Value) and true or false end
            btn._msuf2Override = (not active) and override or false
            btn:SetActive(active)
        end
    end

    if ctx and M.AddRefresher then M.AddRefresher(ctx, function() bar:Refresh() end) end
    bar:Refresh()
    return bar
end

function W.SetControlShown(control, shown)
    if not control then return end
    shown = shown and true or false
    if control.SetShown then control:SetShown(shown) elseif shown then control:Show() else control:Hide() end
    if control._msuf2Title then control._msuf2Title:SetShown(shown) end
    if control._msuf2Label then control._msuf2Label:SetShown(shown) end
    if control._msuf2LabelHit then control._msuf2LabelHit:SetShown(shown) end
    if control.editBox then control.editBox:SetShown(shown) end
    if control._msuf2StepButtons then
        for i = 1, #control._msuf2StepButtons do
            control._msuf2StepButtons[i]:SetShown(shown)
        end
    end
end

local function SetEnabledState(frame, enabled)
    if not frame then return end
    if frame.Enable and frame.Disable then
        if enabled then frame:Enable() else frame:Disable() end
    elseif frame.SetEnabled then
        frame:SetEnabled(enabled)
    end
    if frame.EnableMouse then frame:EnableMouse(enabled) end
end

local function SetTextEnabledColor(fontString, enabled)
    if not (fontString and fontString.SetTextColor) then return end
    local c = enabled and T.colors.text or T.colors.dim
    fontString:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

-- Shared by all Menu2 pages so disabled dependent options do not drift visually.
function W.SetControlEnabled(control, enabled)
    if not control then return end
    enabled = enabled and true or false

    SetEnabledState(control, enabled)
    if control.SetAlpha then control:SetAlpha(enabled and 1 or 0.45) end
    SetTextEnabledColor(control._msuf2Title, enabled)
    SetTextEnabledColor(control._msuf2Label, enabled)

    if control._msuf2LabelHit and control._msuf2LabelHit.EnableMouse then
        control._msuf2LabelHit:EnableMouse(enabled)
    end
    if control._msuf2Chevron and control._msuf2Chevron.SetVertexColor then
        local c = enabled and T.colors.muted or T.colors.dim
        control._msuf2Chevron:SetVertexColor(c[1], c[2], c[3], enabled and 0.95 or 0.55)
    end

    local edit = control.editBox or control.__MSUF_valueBox
    if edit then
        SetEnabledState(edit, enabled)
        if edit.SetAlpha then edit:SetAlpha(enabled and 1 or 0.45) end
    end
    if control._msuf2StepButtons then
        for i = 1, #control._msuf2StepButtons do
            local btn = control._msuf2StepButtons[i]
            SetEnabledState(btn, enabled)
            if btn.SetAlpha then btn:SetAlpha(enabled and 1 or 0.45) end
        end
    end
    if control.buttons then
        for i = 1, #control.buttons do
            local btn = control.buttons[i]
            SetEnabledState(btn, enabled)
            if btn.SetAlpha then btn:SetAlpha(enabled and 1 or 0.45) end
        end
    end
end

function W.SetControlsEnabled(controls, enabled)
    for i = 1, #(controls or {}) do
        W.SetControlEnabled(controls[i], enabled)
    end
end

local function ClampPlacedControlWidth(widget, parent, x)
    if not (widget and parent and parent._msuf2Width) then return end
    local kind = widget._msuf2ControlKind
    if kind ~= "slider" and kind ~= "dropdown" and kind ~= "textinput" then return end

    local available = floor((parent._msuf2Width or 0) - (x or 0) - 18)
    if available <= 0 then return end

    if kind == "slider" and widget._msuf2SetLayoutWidth then
        local requested = widget._msuf2RequestedWidth or widget._msuf2RowWidth or 280
        local minWidth = widget._msuf2MinRowWidth or 160
        widget:_msuf2SetLayoutWidth(min(requested, max(minWidth, available)))
        return
    end

    local currentW = widget.GetWidth and widget:GetWidth()
    if currentW and currentW > available then
        widget:SetWidth(max(72, available))
        if widget._msuf2Title and widget._msuf2Title.SetWidth then
            widget._msuf2Title:SetWidth(max(72, available))
        end
    end
end

function W.MoveWidget(widget, parent, x, y, width, titleJustify)
    if not (widget and widget.ClearAllPoints) then return widget end
    parent = parent or widget:GetParent()
    x = x or 0
    y = y or 0

    local kind = widget._msuf2ControlKind
    width = tonumber(width)
    if width then
        if kind == "slider" and widget._msuf2SetLayoutWidth then
            widget._msuf2RequestedWidth = width
            widget:_msuf2SetLayoutWidth(width)
        elseif kind == "dropdown" or kind == "textinput" then
            widget:SetSize(width, widget:GetHeight() or 22)
            if widget._msuf2Title and widget._msuf2Title.SetWidth then widget._msuf2Title:SetWidth(width) end
        end
    end
    if titleJustify and widget._msuf2Title and widget._msuf2Title.SetJustifyH then
        widget._msuf2TitleJustify = titleJustify
        widget._msuf2Title:SetJustifyH(titleJustify)
    end

    ClampPlacedControlWidth(widget, parent, x)
    if widget._msuf2Title then
        widget._msuf2Title:ClearAllPoints()
        widget._msuf2Title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    end

    widget:ClearAllPoints()
    if kind == "slider" or kind == "dropdown" or kind == "textinput" then
        widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 22)
    elseif kind == "color" then
        if widget._msuf2Title then widget._msuf2Title:SetWidth(100) end
        widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 108, y + 2)
    else
        widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    end
    return widget
end

function W.LabelAt(parent, text, x, y, width, template, color)
    local fs = T.Font(parent, template or "GameFontNormalSmall", text or "", color or T.colors.text)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y or 0)
    fs:SetWidth(width or 180)
    fs:SetJustifyH("LEFT")
    return fs
end

function W.DividerAt(parent, y, leftPad, rightPad)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", leftPad or 12, y or 0)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(rightPad or 12), y or 0)
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.06)
    return line
end

function W.Button(section, label, width)
    local x, y = NextRow(section, 30)
    local btn = T.Button(section, label, width or 160, 24)
    btn:SetPoint("TOPLEFT", x, y)
    return btn
end

function W.Slider(section, label, minVal, maxVal, step, width)
    local x, y = NextRow(section, 48)
    local valueGap = 8
    local buttonGap = 2
    local stepButtonW = 18
    local editW = 52
    local minTrackW = 96
    local valueClusterW = valueGap + stepButtonW + buttonGap + editW + buttonGap + stepButtonW
    width = width or 280
    if section and section._msuf2Width then
        local available = section._msuf2Width - x - 14
        local maxSliderW = max(minTrackW + valueClusterW, available)
        if width > maxSliderW then width = maxSliderW end
    end
    local title = T.Font(section, "GameFontHighlightSmall", label or "", T.colors.text)
    title:SetPoint("TOPLEFT", x, y)
    title:SetWidth(width)
    title:SetJustifyH("LEFT")

    sliderSerial = sliderSerial + 1
    local slider = CreateFrame("Slider", "MSUF2NativeSlider" .. sliderSerial, section, "OptionsSliderTemplate")
    slider._msuf2Title = title
    slider._msuf2ControlKind = "slider"
    slider:SetPoint("TOPLEFT", x, y - 22)
    slider:SetSize(max(minTrackW, width - valueClusterW), 16)
    slider:SetMinMaxValues(minVal or 0, maxVal or 1)
    slider:SetValueStep(step or 1)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    if slider.SetStepsPerPage then slider:SetStepsPerPage(1) end
    slider._msuf2Step = step or 1
    slider._msuf2RequestedWidth = width
    slider._msuf2MinRowWidth = minTrackW + valueClusterW
    HideSliderTemplateParts(slider)
    if T.StyleSlider then T.StyleSlider(slider) end

    local function StepButton(text)
        local btn = T.Button(section, text, 18, 20)
        btn._msuf2Label:ClearAllPoints()
        btn._msuf2Label:SetPoint("CENTER", btn, "CENTER", 0, 0)
        btn._msuf2Label:SetJustifyH("CENTER")
        return btn
    end

    local minus = StepButton("-")

    local edit = CreateFrame("EditBox", nil, section, "InputBoxTemplate")
    edit:SetSize(52, 20)
    edit:SetAutoFocus(false)
    edit:SetJustifyH("CENTER")
    edit:SetNumeric(false)
    T.SkinEditBox(edit)
    slider.editBox = edit

    local plus = StepButton("+")
    slider.minusButton = minus
    slider.plusButton = plus
    slider._msuf2StepButtons = { minus, plus }

    local function UpdateFill()
        local fill = slider._msufFill
        if not fill then return end
        local minV, maxV = slider:GetMinMaxValues()
        local span = maxV - minV
        local pct = span > 0 and ((slider:GetValue() - minV) / span) or 0
        if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
        fill:SetWidth(max(1, slider:GetWidth() * pct))
    end
    slider._msuf2UpdateFill = UpdateFill

    function slider:_msuf2SetLayoutWidth(totalWidth)
        totalWidth = tonumber(totalWidth) or width or 280
        self._msuf2RowWidth = totalWidth
        local trackW = max(minTrackW, floor(totalWidth - valueClusterW + 0.5))
        if title then
            title:SetWidth(trackW)
            if title.SetJustifyH then title:SetJustifyH(self._msuf2TitleJustify or "LEFT") end
        end
        self:SetSize(trackW, 16)
        minus:ClearAllPoints()
        minus:SetPoint("LEFT", self, "RIGHT", valueGap, 0)
        edit:ClearAllPoints()
        edit:SetPoint("LEFT", minus, "RIGHT", buttonGap, 0)
        plus:ClearAllPoints()
        plus:SetPoint("LEFT", edit, "RIGHT", buttonGap, 0)
        UpdateFill()
    end
    slider:_msuf2SetLayoutWidth(width)

    local function FormatValue(value)
        local st = step or 1
        if st < 1 then
            return string.format("%.2f", value)
        end
        return tostring(floor(value + 0.5))
    end
    slider._msuf2FormatValue = FormatValue

    slider:HookScript("OnValueChanged", function(self, value)
        UpdateFill()
        if not self._msuf2Editing then
            edit:SetText(FormatValue(value))
        end
    end)
    slider:HookScript("OnShow", function(self)
        HideSliderTemplateParts(self)
        if T.StyleSlider then T.StyleSlider(self) end
        if self._msuf2SetLayoutWidth then
            self:_msuf2SetLayoutWidth(self._msuf2RowWidth or width)
        else
            UpdateFill()
        end
    end)
    edit:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        if v ~= nil then slider:SetValue(v) end
        self:ClearFocus()
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:SetText(FormatValue(slider:GetValue()))
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusGained", function() slider._msuf2Editing = true end)
    edit:SetScript("OnEditFocusLost", function(self)
        slider._msuf2Editing = nil
        self:SetText(FormatValue(slider:GetValue()))
    end)

    local function ClampToSlider(value)
        local minV, maxV = slider:GetMinMaxValues()
        if value < minV then value = minV elseif value > maxV then value = maxV end
        local st = tonumber(slider._msuf2Step) or 1
        if st > 0 then value = floor((value / st) + 0.5) * st end
        if value < minV then value = minV elseif value > maxV then value = maxV end
        return value
    end

    local function StepMultiplier()
        if IsControlKeyDown and IsControlKeyDown() then return 10 end
        if IsShiftKeyDown and IsShiftKeyDown() then return 5 end
        return 1
    end

    local function StepBy(direction)
        if slider.IsEnabled and not slider:IsEnabled() then return end
        local amount = (tonumber(slider._msuf2Step) or 1) * StepMultiplier() * direction
        slider:SetValue(ClampToSlider((tonumber(slider:GetValue()) or 0) + amount))
    end

    minus:SetScript("OnClick", function() StepBy(-1) end)
    plus:SetScript("OnClick", function() StepBy(1) end)

    return slider
end

function W.Segment(section, label, values, width)
    local x, y = NextRow(section, 48)
    local title = T.Font(section, "GameFontHighlightSmall", label or "", T.colors.text)
    title:SetPoint("TOPLEFT", x, y)

    local holder = CreateFrame("Frame", nil, section)
    holder:SetPoint("TOPLEFT", x, y - 22)
    holder:SetSize(width or 360, 22)
    holder.buttons = {}
    holder.values = values or {}

    local count = #holder.values
    local gap = 6
    local bw = count > 0 and math.floor(((width or 360) - gap * (count - 1)) / count) or 80
    for i = 1, count do
        local item = holder.values[i]
        local btn = T.Button(holder, item.text or tostring(item.value), bw, 22)
        btn:SetPoint("LEFT", holder, "LEFT", (i - 1) * (bw + gap), 0)
        btn._msuf2Value = item.value
        holder.buttons[i] = btn
    end

    function holder:SetValue(value)
        self.value = value
        for i = 1, #self.buttons do
            local btn = self.buttons[i]
            btn:SetActive(btn._msuf2Value == value)
        end
    end
    function holder:GetValue()
        return self.value
    end
    return holder
end

local dropdownFrame, dropdownScroll, dropdownChild, dropdownOwner, dropdownSlider
local dropdownRows = {}
local DROPDOWN_ROW_H = 22
local CloseDropdown

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
    dropdownScroll:SetPoint("BOTTOMRIGHT", dropdownFrame, "BOTTOMRIGHT", -22, 2)
    dropdownScroll:EnableMouseWheel(true)
    dropdownScroll:SetScript("OnMouseWheel", function(self, delta)
        local nextScroll = (self:GetVerticalScroll() or 0) - (delta or 0) * DROPDOWN_ROW_H * 3
        SetDropdownScroll(nextScroll)
    end)

    dropdownChild = CreateFrame("Frame", nil, dropdownScroll)
    dropdownScroll:SetScrollChild(dropdownChild)

    dropdownSlider = CreateFrame("Slider", nil, dropdownFrame)
    dropdownSlider:SetOrientation("VERTICAL")
    dropdownSlider:SetWidth(14)
    dropdownSlider:SetMinMaxValues(0, 1)
    dropdownSlider:SetValueStep(1)
    if dropdownSlider.SetObeyStepOnDrag then dropdownSlider:SetObeyStepOnDrag(false) end
    dropdownSlider:SetPoint("TOPRIGHT", dropdownFrame, "TOPRIGHT", -5, -6)
    dropdownSlider:SetPoint("BOTTOMRIGHT", dropdownFrame, "BOTTOMRIGHT", -5, 6)
    local track = dropdownSlider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("TOP", dropdownSlider, "TOP", 0, 0)
    track:SetPoint("BOTTOM", dropdownSlider, "BOTTOM", 0, 0)
    track:SetWidth(4)
    track:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.75)
    local thumb = dropdownSlider:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(T.media and T.media.superellipse or "Interface\\Buttons\\WHITE8X8")
    thumb:SetSize(12, 34)
    thumb:SetVertexColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.95)
    dropdownSlider:SetThumbTexture(thumb)
    dropdownSlider:SetScript("OnValueChanged", function(self, value)
        if self._msuf2Refreshing then return end
        if dropdownScroll then dropdownScroll:SetVerticalScroll(value or 0) end
    end)
    dropdownSlider:Hide()

    dropdownFrame:EnableMouseWheel(true)
    dropdownFrame:SetScript("OnMouseWheel", function(_, delta)
        if dropdownScroll then
            SetDropdownScroll((dropdownScroll:GetVerticalScroll() or 0) - (delta or 0) * DROPDOWN_ROW_H * 3)
        end
    end)

    dropdownFrame:SetScript("OnHide", function()
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
    if type(item) ~= "table" then return tostring(item or "") end
    if item.text ~= nil then return item.text end
    if item.label ~= nil then return item.label end
    if item[1] ~= nil and item[2] ~= nil then return tostring(item[1]) end
    return tostring(DropdownItemValue(item) or "")
end

local function DropdownItemIcon(item)
    if type(item) ~= "table" then return nil end
    return item.icon or item.texture or item.swatch
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

    local text = T.Font(row, "GameFontHighlight", "", T.colors.text)
    text:SetPoint("LEFT", row, "LEFT", 10, 0)
    text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    text:SetJustifyH("LEFT")
    row._msuf2Text = text

    row:SetScript("OnClick", function(self)
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

    dropdownFrame:SetSize(rowWidth + (needsScroll and 22 or 4), listHeight)
    dropdownChild:SetSize(rowWidth, totalHeight)
    dropdownScroll:ClearAllPoints()
    dropdownScroll:SetPoint("TOPLEFT", dropdownFrame, "TOPLEFT", 2, -2)
    dropdownScroll:SetPoint("BOTTOMRIGHT", dropdownFrame, "BOTTOMRIGHT", needsScroll and -20 or -2, 2)
    if dropdownSlider then
        dropdownSlider:SetShown(needsScroll)
        dropdownSlider:SetMinMaxValues(0, math.max(0, totalHeight - (listHeight - 4)))
    end

    local selectedIndex = 1
    for i = 1, #valuesTable do
        local item = valuesTable[i]
        local row = DropdownRow(i)
        local value = DropdownItemValue(item)
        local icon = DropdownItemIcon(item)
        local selectedValue = owner._msuf2DropdownListValue
        if selectedValue == nil then selectedValue = owner.value end
        row._msuf2Owner = owner
        row._msuf2Value = value
        row._msuf2Item = item
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", dropdownChild, "TOPLEFT", 0, -((i - 1) * DROPDOWN_ROW_H))
        row:SetWidth(rowWidth)
        row._msuf2Selected:SetShown(value == selectedValue)
        if value == selectedValue then selectedIndex = i end
        row._msuf2Text:SetText(DropdownItemText(item))
        if icon then
            row._msuf2Icon:SetTexture(icon)
            row._msuf2Icon:SetVertexColor(1, 1, 1, 1)
            row._msuf2Icon:Show()
            row._msuf2Text:ClearAllPoints()
            row._msuf2Text:SetPoint("LEFT", row, "LEFT", 100, 0)
            row._msuf2Text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        else
            row._msuf2Icon:Hide()
            row._msuf2Text:ClearAllPoints()
            row._msuf2Text:SetPoint("LEFT", row, "LEFT", 10, 0)
            row._msuf2Text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        end
        row:Show()
    end
    for i = #valuesTable + 1, #dropdownRows do
        dropdownRows[i]:Hide()
    end

    dropdownOwner = owner
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
    local title = T.Font(section, "GameFontHighlightSmall", label or "", T.colors.text)
    title:SetPoint("TOPLEFT", x, y)

    local btn = T.Button(section, "", width or 240, 22)
    btn._msuf2Title = title
    btn._msuf2ControlKind = "dropdown"
    btn:SetPoint("TOPLEFT", x, y - 22)
    btn.values = values or {}
    btn._msuf2Label:ClearAllPoints()
    btn._msuf2Label:SetPoint("LEFT", btn, "LEFT", 10, 0)
    btn._msuf2Label:SetPoint("RIGHT", btn, "RIGHT", -26, 0)
    btn._msuf2Label:SetJustifyH("LEFT")
    btn._msuf2Chevron = btn:CreateTexture(nil, "OVERLAY")
    btn._msuf2Chevron:SetTexture(T.media.dropdownChevron)
    btn._msuf2Chevron:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    btn._msuf2Chevron:SetSize(10, 10)
    btn._msuf2Chevron:SetVertexColor(T.colors.muted[1], T.colors.muted[2], T.colors.muted[3], 0.95)

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
        self:SetValue(self.value)
    end
    function btn:SetValue(value)
        self.value = value
        self:SetText(TextFor(value))
    end
    function btn:GetValue()
        return self.value
    end
    function btn:SetOnValueChanged(fn)
        self._msuf2OnValueChanged = fn
    end

    btn:EnableMouseWheel(true)
    btn:SetScript("OnClick", function(self)
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
        local nextIndex = 1
        local valuesTable = ResolveValues(self)
        if #valuesTable == 0 then return end
        for i = 1, #valuesTable do
            if DropdownItemValue(valuesTable[i]) == self.value then
                nextIndex = ((i - 1 + ((delta or 0) < 0 and 1 or -1)) % #valuesTable) + 1
                break
            end
        end
        local item = valuesTable[nextIndex]
        if item then
            local value = DropdownItemValue(item)
            self:SetValue(value)
            if self._msuf2OnValueChanged then self._msuf2OnValueChanged(value) end
        end
    end)

    return btn
end

function W.StatCard(parent, label, value, x, y, width)
    local card = T.Panel(parent, nil, T.colors.panel2, T.colors.borderSoft)
    card:SetPoint("TOPLEFT", x or 0, y or 0)
    card:SetSize(width or 170, 56)
    local l = T.Font(card, "GameFontDisableSmall", label or "", T.colors.muted)
    l:SetPoint("TOPLEFT", 12, -10)
    local v = T.Font(card, "GameFontNormal", value or "", T.colors.text)
    v:SetPoint("TOPLEFT", 12, -30)
    card.valueText = v
    return card
end

function W.Divider(parent, x, y, width)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", x or 0, y or 0)
    line:SetSize(width or 400, 1)
    line:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.70)
    return line
end

function W.TextInput(section, label, width)
    local x, y = NextRow(section, 50)
    width = width or 260
    local title = T.Font(section, "GameFontHighlightSmall", label or "", T.colors.text)
    title:SetPoint("TOPLEFT", x, y)

    local edit = CreateFrame("EditBox", nil, section, "InputBoxTemplate")
    edit._msuf2Title = title
    edit._msuf2ControlKind = "textinput"
    edit:SetPoint("TOPLEFT", x, y - 22)
    edit:SetSize(width, 22)
    edit:SetAutoFocus(false)
    edit:SetJustifyH("LEFT")
    edit:SetMaxLetters(200000)
    T.SkinEditBox(edit)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    function edit:SetOnValueCommitted(fn)
        self._msuf2OnCommit = fn
    end
    edit:SetScript("OnEnterPressed", function(self)
        if self._msuf2OnCommit then self._msuf2OnCommit(self:GetText() or "") end
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        if self._msuf2CommitOnBlur and self._msuf2OnCommit then
            self._msuf2OnCommit(self:GetText() or "")
        end
    end)
    return edit
end

function W.Color(section, label)
    local x, y = NextRow(section, 34)
    local title = T.Font(section, "GameFontHighlightSmall", label or "", T.colors.text)
    title:SetPoint("TOPLEFT", x, y)
    title:SetWidth(230)

    local btn = CreateFrame("Button", nil, section)
    btn._msuf2Title = title
    btn._msuf2ControlKind = "color"
    btn:SetPoint("TOPLEFT", x + 250, y + 2)
    btn:SetSize(44, 18)
    btn._msuf2Swatch, btn._msuf2Edge = T.CreateSuperellipseLayers(btn, "_msuf2Color", 1, "ARTWORK", "OVERLAY")
    btn._msuf2Edge:SetVertexColor(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.75)

    function btn:SetRGB(r, g, b)
        self._msuf2R = tonumber(r) or 1
        self._msuf2G = tonumber(g) or 1
        self._msuf2B = tonumber(b) or 1
        self._msuf2Swatch:SetVertexColor(self._msuf2R, self._msuf2G, self._msuf2B, 1)
    end
    function btn:GetRGB()
        return self._msuf2R or 1, self._msuf2G or 1, self._msuf2B or 1
    end
    function btn:SetOnColorChanged(fn)
        self._msuf2OnColorChanged = fn
    end
    btn:SetRGB(1, 1, 1)
    btn:SetScript("OnClick", function(self)
        if not ColorPickerFrame then return end
        local r, g, b = self:GetRGB()
        local function Commit()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            self:SetRGB(nr, ng, nb)
            if self._msuf2OnColorChanged then self._msuf2OnColorChanged(nr, ng, nb) end
        end
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = r, g = g, b = b, opacity = 1, hasOpacity = false,
                swatchFunc = Commit,
                cancelFunc = function(prev)
                    if type(prev) == "table" then
                        local pr, pg, pb = prev.r or r, prev.g or g, prev.b or b
                        self:SetRGB(pr, pg, pb)
                        if self._msuf2OnColorChanged then self._msuf2OnColorChanged(pr, pg, pb) end
                    end
                end,
                previousValues = { r = r, g = g, b = b, opacity = 1 },
            })
        else
            ColorPickerFrame.func = Commit
            ColorPickerFrame.cancelFunc = function()
                self:SetRGB(r, g, b)
                if self._msuf2OnColorChanged then self._msuf2OnColorChanged(r, g, b) end
            end
            ColorPickerFrame:SetColorRGB(r, g, b)
            ColorPickerFrame:Show()
        end
    end)
    return btn
end
