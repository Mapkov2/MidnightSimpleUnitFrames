local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
--- Shell/Menu2/MSUF_Menu2_Widgets_Gates.lua
--- Control visibility and enable gates, disabled-reason tooltips, and the
--- placement helpers pages use to put a control at fixed coordinates
--- (W.MoveWidget, W.LabelAt, W.DividerAt, W.Button).
---
--- Split from MSUF_Menu2_Widgets.lua; loads after the controls.

local _, MSUF = ...
local M = MSUF.MSUF2
local T = M.Theme
local W = M.Widgets
local Shared = W._Shared
local floor = math.floor
local max = math.max
local min = math.min
local Tr = M.TranslateText
local SetSearchText = Shared.SetSearchText
local RegisterSearchObject = W.RegisterSearchObject
local NextRow = W.NextRow
local HideSliderTemplateParts = Shared.HideSliderTemplateParts
local AttachBoundColorToContextCard = Shared.AttachBoundColorToContextCard

function W.SetControlShown(control, shown)
    if not control then return end
    shown = shown and true or false
    if control.SetShown then control:SetShown(shown) elseif shown then control:Show() else control:Hide() end
    if control._msuf2Title then control._msuf2Title:SetShown(shown) end
    if control._msuf2Label and not control._msuf2Label._msuf2AlwaysHidden then control._msuf2Label:SetShown(shown) end
    if control._msuf2LabelHit then control._msuf2LabelHit:SetShown(shown) end
    if not shown and control._msuf2RefreshToggleFeedback then
        control._msuf2ToggleHovered = nil
        control._msuf2TogglePressed = nil
        control:_msuf2RefreshToggleFeedback()
    end
    if control._msuf2ToggleRowHover then
        if not shown then control._msuf2ToggleRowHover:SetAlpha(0) end
        control._msuf2ToggleRowHover:SetShown(shown)
    end
    if control.editBox then control.editBox:SetShown(shown) end
    if control._msuf2StepButtons then
        for i = 1, #control._msuf2StepButtons do
            control._msuf2StepButtons[i]:SetShown(shown)
        end
    end
    if control._msuf2LayerShortcutButton then
        control._msuf2LayerShortcutButton:SetShown(shown)
    end
    if shown and control._msuf2SetLayoutWidth then control:_msuf2SetLayoutWidth(control._msuf2RowWidth or control._msuf2RequestedWidth) end
end
local function SetEnabledState(frame, enabled)
    if not frame then return end
    -- A control wired with a disabled reason keeps the mouse while disabled:
    -- the reason tooltip is how the user learns what unlocks it. Its click
    -- handlers stay inert because the control itself is disabled.
    local mouseEnabled = (enabled or frame._msuf2DisabledReasonWired == true) and not frame._msuf2UseProxyMouse
    if frame._msuf2EnabledStateApplied == enabled
        and frame._msuf2MouseEnabledStateApplied == mouseEnabled
        and (not frame.IsEnabled or ((frame:IsEnabled() and true or false) == enabled))
    then
        return
    end
    frame._msuf2EnabledStateApplied = enabled
    frame._msuf2MouseEnabledStateApplied = mouseEnabled
    -- Theme buttons repaint their custom fill, edge, and label in SetEnabled.
    -- Calling only the native Enable/Disable methods changes interaction state
    -- but leaves an active segment painted blue while its parent is disabled.
    if frame.SetEnabled then
        frame:SetEnabled(enabled)
    elseif frame.Enable and frame.Disable then
        if enabled then frame:Enable() else frame:Disable() end
    end
    if frame.EnableMouse then frame:EnableMouse(mouseEnabled) end
end
local function SetTextEnabledColor(fontString, enabled)
    if not (fontString and fontString.SetTextColor) then return end
    local c = enabled and T.colors.text or (T.colors.disabled or T.colors.dim)
    local r, g, b, a = c[1], c[2], c[3], c[4] or 1
    if fontString._msuf2EnabledColorState == enabled
        and fontString._msuf2TextColorR == r
        and fontString._msuf2TextColorG == g
        and fontString._msuf2TextColorB == b
        and fontString._msuf2TextColorA == a
    then
        return
    end
    fontString._msuf2EnabledColorState = enabled
    fontString._msuf2TextColorR, fontString._msuf2TextColorG, fontString._msuf2TextColorB, fontString._msuf2TextColorA = r, g, b, a
    fontString:SetTextColor(r, g, b, a)
end
local function HasDisableGate(control)
    local gates = control and control._msuf2DisableGates
    if type(gates) ~= "table" then return false end
    for _, disabled in pairs(gates) do
        if disabled then return true end
    end
    return false
end
local function ApplyEnabledVisuals(control, enabled)
    SetEnabledState(control, enabled)
    if control._msuf2DisabledReasonProxy then control._msuf2DisabledReasonProxy:SetShown(not enabled) end
    if control.SetAlpha and control._msuf2EnabledAlphaState ~= enabled then
        control._msuf2EnabledAlphaState = enabled
        -- Labels already receive the disabled text token. Fading their parent
        -- again made gated settings unreadable, especially inside segments.
        control:SetAlpha(1)
    end
    SetTextEnabledColor(control._msuf2Title, enabled)
    SetTextEnabledColor(control._msuf2Label, enabled)
    if control._msuf2RefreshSwitchVisual then control:_msuf2RefreshSwitchVisual() end
    if control._msuf2RefreshToggleFeedback then control:_msuf2RefreshToggleFeedback() end
    local labelMouseEnabled = enabled or control._msuf2KeepLabelHitMouseWhenDisabled == true
        or control._msuf2DisabledReasonWired == true
    if control._msuf2LabelHit and control._msuf2LabelHit.EnableMouse and control._msuf2LabelHit._msuf2MouseEnabledStateApplied ~= labelMouseEnabled then
        control._msuf2LabelHit._msuf2MouseEnabledStateApplied = labelMouseEnabled
        control._msuf2LabelHit:EnableMouse(labelMouseEnabled)
    end
    local edit = control.editBox or control.__MSUF_valueBox
    if edit then
        SetEnabledState(edit, enabled)
        if edit.SetAlpha and edit._msuf2EnabledAlphaState ~= enabled then
            edit._msuf2EnabledAlphaState = enabled
            edit:SetAlpha(enabled and 1 or 0.85)
        end
    end
    if control._msuf2StepButtons then
        for i = 1, #control._msuf2StepButtons do
            local btn = control._msuf2StepButtons[i]
            SetEnabledState(btn, enabled)
            if btn.SetAlpha and btn._msuf2EnabledAlphaState ~= enabled then
                btn._msuf2EnabledAlphaState = enabled
                btn:SetAlpha(enabled and 1 or 0.85)
            end
        end
    end
    if control.buttons then
        for i = 1, #control.buttons do
            local btn = control.buttons[i]
            SetEnabledState(btn, enabled)
            if btn.SetAlpha and btn._msuf2EnabledAlphaState ~= enabled then
                btn._msuf2EnabledAlphaState = enabled
                btn:SetAlpha(enabled and 1 or 0.85)
            end
        end
    end
end
local function ApplyControlEnabled(control)
    if not control then return end
    local enabled = (control._msuf2DesiredEnabled ~= false) and not HasDisableGate(control)
    if control._msuf2AppliedEnabled == enabled then return end
    control._msuf2AppliedEnabled = enabled
    if control._msuf2ControlKind == "slider" then
        HideSliderTemplateParts(control)
        if T.StyleSlider then T.StyleSlider(control) end
        if control._msuf2UpdateFill then control:_msuf2UpdateFill() end
    end
    ApplyEnabledVisuals(control, enabled)
    if control._msuf2Chevron and control._msuf2Chevron.SetVertexColor then
        local c = enabled and T.colors.muted or (T.colors.disabled or T.colors.dim)
        control._msuf2Chevron:SetVertexColor(c[1], c[2], c[3], enabled and 0.95 or 0.55)
    end
end

--- Shared by all Menu2 pages so disabled dependent options do not drift visually.
--- Enable gates keep disabled controls visible but inert, which preserves page
--- layout and lets tooltips/explanatory text still be attached by callers.
function W.SetControlEnabled(control, enabled)
    if not control then return end
    control._msuf2DesiredEnabled = enabled and true or false
    ApplyControlEnabled(control)
end
function W.SetControlGateEnabled(control, gateKey, enabled)
    if not control then return end
    gateKey = tostring(gateKey or "default")
    control._msuf2DisableGates = control._msuf2DisableGates or {}
    local disabled = not (enabled and true or false)
    if control._msuf2DisableGates[gateKey] == disabled then return end
    control._msuf2DisableGates[gateKey] = disabled
    if control._msuf2DesiredEnabled == nil then
        local current = true
        if control.IsEnabled then current = control:IsEnabled() and true or false end
        control._msuf2DesiredEnabled = current
    end
    local gateReasons = W._msuf2GateReasons
    if disabled and gateReasons and gateReasons[gateKey] ~= nil then W.WireDisabledReason(control) end
    ApplyControlEnabled(control)
end
function W.ClearControlGate(control, gateKey, deferApply)
    local gates = control and control._msuf2DisableGates
    if type(gates) ~= "table" then return false end
    gateKey = tostring(gateKey or "default")
    if gates[gateKey] == nil then return false end
    gates[gateKey] = nil
    if deferApply ~= true then ApplyControlEnabled(control) end
    return true
end
function W.SetControlsEnabled(controls, enabled)
    for i = 1, #(controls or {}) do
        W.SetControlEnabled(controls[i], enabled)
    end
end
--- Disabled reasons: a control that a toggle or gate greys out says why on
--- hover. The reason is a string or a function(control) returning one (nil
--- when it does not apply) and is only shown while the control is disabled.
--- A gate (W.SetControlGateEnabled) blocks it: while a gate holds the control
--- only that gate's registered reason can show, so a frame-level lock never
--- points at a toggle the user cannot reach. Wiring happens once per control
--- at build time; hovering resolves the text, nothing runs per frame.
function W.WireDisabledReason(control)
    if not control or control._msuf2DisabledReasonWired or control._msuf2DisabledReasonProxy then return end
    -- A disabled input must not take focus. A hover-only cover explains why,
    -- and disappears as soon as editing is enabled again.
    if control.GetObjectType and control:GetObjectType() == "EditBox" then
        local proxy = PixelLayoutRegion(CreateFrame("Frame", nil, control))
        proxy:SetAllPoints(control)
        proxy:SetFrameLevel(control:GetFrameLevel() + 2)
        proxy:EnableMouse(true)
        proxy._msuf2ReasonOwner = control
        if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(proxy, control) end
        proxy:SetScript("OnEnter", W.ShowDisabledReason)
        proxy:SetScript("OnLeave", W.HideDisabledReason)
        proxy:SetScript("OnHide", W.HideDisabledReason)
        proxy:SetShown(control._msuf2AppliedEnabled == false)
        control._msuf2DisabledReasonProxy = proxy
        return
    end
    control._msuf2DisabledReasonWired = true
    -- Disabled buttons swallow OnEnter/OnLeave unless asked to keep them.
    if control.SetMotionScriptsWhileDisabled then control:SetMotionScriptsWhileDisabled(true) end
    if control.HookScript then
        control:HookScript("OnEnter", W.ShowDisabledReason)
        control:HookScript("OnLeave", W.HideDisabledReason)
    end
    local hit = control._msuf2LabelHit
    if hit and hit ~= control and hit.HookScript then
        hit._msuf2ReasonOwner = control
        hit:HookScript("OnEnter", W.ShowDisabledReason)
        hit:HookScript("OnLeave", W.HideDisabledReason)
    end
    -- An already disabled control regains the mouse for its reason tooltip.
    if control._msuf2AppliedEnabled == false then
        control._msuf2AppliedEnabled = nil
        ApplyControlEnabled(control)
    end
end
function W.SetControlDisabledReason(control, reason)
    if not control then return end
    if reason == "" then reason = nil end
    control._msuf2DisabledReason = reason
    if reason ~= nil then W.WireDisabledReason(control) end
end
function W.SetControlsDisabledReason(controls, reason)
    if type(controls) ~= "table" then return end
    if controls.GetObjectType then return W.SetControlDisabledReason(controls, reason) end
    for _, control in pairs(controls) do
        if type(control) == "table" then W.SetControlDisabledReason(control, reason) end
    end
end
--- Reason for every control a named gate disables (for example the whole page
--- of a turned-off frame). Register before the gate is applied.
function W.SetGateDisabledReason(gateKey, reason)
    if gateKey == nil then return end
    local reasons = W._msuf2GateReasons
    if not reasons then
        reasons = {}
        W._msuf2GateReasons = reasons
    end
    if reason == "" then reason = nil end
    reasons[tostring(gateKey)] = reason
end
function W.DisabledReasonText(control)
    if not control or control._msuf2AppliedEnabled ~= false then return nil end
    local reason
    if HasDisableGate(control) then
        local reasons = W._msuf2GateReasons
        if not reasons then return nil end
        for key, disabled in pairs(control._msuf2DisableGates) do
            if disabled and reasons[key] ~= nil then
                reason = reasons[key]
                break
            end
        end
    else
        reason = control._msuf2DisabledReason
    end
    if type(reason) == "function" then reason = reason(control) end
    if type(reason) ~= "string" or reason == "" then return nil end
    return reason
end
function W.ShowDisabledReason(self)
    -- A page tooltip on this frame appends the reason itself (M.AddTooltip).
    if not self or self._msuf2TooltipTarget then return end
    local control = self._msuf2ReasonOwner or self
    local text = W.DisabledReasonText(control)
    local tip = _G.GameTooltip
    if not (text and tip) then return end
    if not (tip.IsOwned and tip:IsOwned(self) and tip:IsShown()) then
        tip:SetOwner(self, "ANCHOR_RIGHT")
        local title = control._msuf2Title or control._msuf2Label
        local titleText = title and title.GetText and title:GetText()
        if titleText and titleText ~= "" then tip:SetText(titleText, 1, 1, 1) end
    end
    tip:AddLine(text, 1, 0.82, 0.35, true)
    tip:Show()
end
function W.HideDisabledReason(self)
    if not self or self._msuf2TooltipTarget then return end
    local tip = _G.GameTooltip
    if tip and tip.IsOwned and tip:IsOwned(self) then tip:Hide() end
end
--- Standard wording for a dependent control: 'Turn on "<label>" to change
--- this.' `isOn` (optional) returns true while the toggle is on; then the
--- reason does not apply and the caller's other gates speak instead.
function W.TurnOnReason(label, isOn)
    return function()
        if isOn and isOn() then return nil end
        return M.Format("Turn on \"%s\" to change this.", Tr(label or ""))
    end
end
function W.TurnOffReason(label, isOff)
    return function()
        if isOff and isOff() then return nil end
        return M.Format("Turn off \"%s\" to change this.", Tr(label or ""))
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
        local minWidth = widget._msuf2MinRowWidth or 48
        widget:_msuf2SetLayoutWidth(max(minWidth, min(requested, available)))
        return
    end
    local currentW = widget.GetWidth and widget:GetWidth()
    if currentW and currentW > available then
        widget:SetWidth(max(72, available))
        if widget._msuf2Title and widget._msuf2Title.SetWidth then widget._msuf2Title:SetWidth(max(72, available)) end
    end
end

--- Shared positioning helper for widgets that can be placed in normal page flow
--- or moved into card/preview surfaces.
function W.MoveWidget(widget, parent, x, y, width, titleJustify)
    if not (widget and widget.ClearAllPoints) then return widget end
    parent = parent or widget:GetParent()
    x = x or 0
    y = y or 0
    local kind = widget._msuf2ControlKind
    if kind == "slider" then titleJustify = "LEFT" end
    widget._msuf2ContextLayoutParent = parent
    widget._msuf2ContextLayoutX = x
    widget._msuf2ContextLayoutY = y
    width = tonumber(width)
    if width then
        if kind == "slider" and widget._msuf2SetLayoutWidth then
            widget._msuf2RequestedWidth = width
            widget:_msuf2SetLayoutWidth(width)
        elseif kind == "dropdown" or kind == "textinput" or kind == "segment" then
            widget:SetSize(width, widget:GetHeight() or 22)
            if widget._msuf2Title and widget._msuf2Title.SetWidth then widget._msuf2Title:SetWidth(width) end
        elseif kind == "toggle" and widget._msuf2Label and widget._msuf2Label.SetWidth then
            widget._msuf2Label:SetWidth(max(20, width))
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
    if kind == "slider" or kind == "dropdown" or kind == "textinput" or kind == "segment" then
        widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 24)
    elseif kind == "color" then
        if widget._msuf2Title then widget._msuf2Title:SetWidth(100) end
        widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 108, y + 2)
    else
        widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    end
    if kind == "color" and widget._msuf2ContextColorBound then AttachBoundColorToContextCard(widget) end
    if kind == "toggle" and widget._msuf2UpdateToggleProxyBounds then widget:_msuf2UpdateToggleProxyBounds() end
    return widget
end
function W.LabelAt(parent, text, x, y, width, template, color)
    local fs = T.Font(parent, template or "GameFontNormalSmall", text or "", color or T.colors.text)
    SetSearchText(fs, text)
    RegisterSearchObject(fs, text, "text")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y or 0)
    fs:SetWidth(width or 180)
    fs:SetJustifyH("LEFT")
    return fs
end
function W.DividerAt(parent, y, leftPad, rightPad)
    local line = PixelLayoutRegion(parent:CreateTexture(nil, "ARTWORK"))
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", leftPad or 12, y or 0)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(rightPad or 12), y or 0)
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.06)
    return line
end
function W.Button(section, label, width)
    local x, y = NextRow(section, 32)
    local btn = T.Button(section, label or "", width or 160, 24)
    btn._msuf2ControlKind = "button"
    RegisterSearchObject(btn, label, "button")
    btn:SetPoint("TOPLEFT", x, y)
    return btn
end
