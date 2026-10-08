local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
--- Shell/Menu2/MSUF_Menu2_Widgets_Controls.lua
--- Input controls: toggles and switches, the section switch, the scope
--- override bar, sliders with their layer-overview shortcut, segments, segment
--- tabs and the text input.
---
--- Split from MSUF_Menu2_Widgets.lua; loads after the context colors.

local _, MSUF = ...
local M = MSUF.MSUF2
local T = M.Theme
local W = M.Widgets
local Shared = W._Shared
local floor = math.floor
local max = math.max
local min = math.min
local Tr = M.TranslateText
local ThemeColor = Shared.ThemeColor
local SetSearchText = Shared.SetSearchText
local SetSearchTitle = Shared.SetSearchTitle
local RegisterSearchObject = W.RegisterSearchObject
local NextRow = W.NextRow
local LAYER_SHORTCUT_DOTS = Shared.LAYER_SHORTCUT_DOTS
local AddThreeDotShortcutTextures = Shared.AddThreeDotShortcutTextures

local SLIDER_TEMPLATE_KEEP_KEYS, SLIDER_TEMPLATE_SUFFIXES = M.WordList "_msufTrack _msufTrackTop _msufTrackBottom _msufFill _msufFillGlow _msuf2Thumb _msufPeelTrack _msufPeelTrackFill", M.WordList "Left Middle Right Text Low High"
local IsTextureRegion = T.IsTextureRegion
local function HideSliderTemplateParts(slider)
    if not slider then return end
    local thumb = slider.GetThumbTexture and slider:GetThumbTexture()
    local keep = {}
    if thumb then keep[thumb] = true end
    for i = 1, #SLIDER_TEMPLATE_KEEP_KEYS do
        local region = slider[SLIDER_TEMPLATE_KEEP_KEYS[i]]
        if region then keep[region] = true end
    end
    local regions = { slider:GetRegions() }
    for i = 1, #regions do
        local region = regions[i]
        if IsTextureRegion(region) and not keep[region] then
            if region.SetAlpha then region:SetAlpha(0) end
            if region.Hide then region:Hide() end
        end
    end
    local name = slider.GetName and slider:GetName()
    for _, suffix in ipairs(SLIDER_TEMPLATE_SUFFIXES) do
        local region = (name and _G[name .. suffix]) or slider[suffix]
        if region then
            if region.SetText then region:SetText("") end
            if region.SetAlpha then region:SetAlpha(0) end
            if region.Hide then region:Hide() end
        end
    end
end
Shared.HideSliderTemplateParts = HideSliderTemplateParts
local function PlayWidgetMotion(region, motion, opts)
    if T.PlayMotion then
        T.PlayMotion(region, motion, opts)
        return
    end
    opts = opts or {}
    if region and region.SetAlpha then region:SetAlpha(opts.toAlpha or 0) end
end
local function ClickCheckButton(button, mouseButton)
    if not button then return end
    if button.IsEnabled and not button:IsEnabled() then return end
    T.CommitFocusedInput()
    local nextValue
    if button.SetChecked and button.GetChecked then
        nextValue = not (button:GetChecked() and true or false)
        button:SetChecked(nextValue)
    end
    local click = button.GetScript and button:GetScript("OnClick")
    if type(click) == "function" then click(button, mouseButton or "LeftButton", false) end
    if button._msuf2RefreshToggleFeedback then button:_msuf2RefreshToggleFeedback(button._msuf2ToggleHovered, button._msuf2TogglePressed) end
    if button._msuf2RefreshSwitchVisual then button:_msuf2RefreshSwitchVisual(button._msuf2SwitchHovered) end
    return nextValue
end
local function GetCheckTexture(button, getter, suffix)
    local check = button and button[getter] and button[getter](button)
    if (not check) and button and suffix and button.GetName and button:GetName() then check = _G[button:GetName() .. suffix] end
    return check
end
local function SyncCheckedTexture(button, checked, enabled, alpha)
    local check = GetCheckTexture(button, "GetCheckedTexture", "Check")
    local disabledCheck = GetCheckTexture(button, "GetDisabledCheckedTexture", "DisabledCheck")
    if not (check or disabledCheck) then return end
    checked = checked and true or false
    alpha = alpha or (enabled and 0.96 or 0.42)
    local function apply(texture)
        if not texture then return end
        if texture.SetVertexColor then texture:SetVertexColor(1, 1, 1, checked and alpha or 0) end
        if texture.SetAlpha then texture:SetAlpha(checked and alpha or 0) end
        if checked then
            if texture.Show then texture:Show() end
        elseif texture.Hide then
            texture:Hide()
        end
    end
    apply(check)
    apply(disabledCheck)
end
local function UpdateToggleProxyBounds(button)
    if not button then return end
    local label = button._msuf2Label
    local textWidth = 0
    if label and label.GetStringWidth then textWidth = tonumber(label:GetStringWidth()) or 0 end
    if textWidth <= 0 and label and label.GetText then
        local text = tostring(label:GetText() or "")
        textWidth = #text * 7
    end
    local labelWidth = label and label.GetWidth and tonumber(label:GetWidth()) or nil
    if labelWidth and labelWidth > 0 then textWidth = textWidth > 0 and min(textWidth, labelWidth) or labelWidth end
    textWidth = max(0, textWidth)
    local baseWidth = tonumber(button._msuf2ProxyBaseWidth) or 40
    local hitWidth = max(36, floor(baseWidth + textWidth + 0.5))
    local rowHover = button._msuf2ToggleRowHover
    if rowHover then
        rowHover:ClearAllPoints()
        rowHover:SetPoint("LEFT", button, "LEFT", -4, 0)
        rowHover:SetSize(hitWidth, 28)
        if rowHover.SetTexCoord then rowHover:SetTexCoord(0, 1, 0, 1) end
    end
    local labelHit = button._msuf2LabelHit
    if labelHit then
        labelHit:ClearAllPoints()
        labelHit:SetPoint("LEFT", button, "LEFT", -4, 0)
        labelHit:SetSize(hitWidth, 28)
    end
end
local function UseControlTexture(tex, texture)
    if not tex then return tex end
    tex:SetTexture(texture)
    tex:SetTexCoord(0, 1, 0, 1)
    PixelLayoutRegion(tex, true)
    if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
    if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
    return tex
end
local function ControlTexture(parent, key, layer, subLevel, texture)
    -- Excluded art from creation on: the plain wrapper would switch native
    -- rounding on only for UseControlTexture to switch it off again.
    local tex = UseControlTexture(PixelLayoutRegion(parent:CreateTexture(nil, layer, nil, subLevel), true), texture)
    if key then parent[key] = tex end
    return tex
end
local function HideNativeCheckTexture(texture)
    if not texture then return end
    if texture.SetAlpha then texture:SetAlpha(0) end
    if texture.Hide then texture:Hide() end
end
local NATIVE_CHECK_TEXTURE_GETTERS = { "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }
local function SuppressNativeCheckChrome(self)
    for i = 1, #NATIVE_CHECK_TEXTURE_GETTERS do
        local getter = NATIVE_CHECK_TEXTURE_GETTERS[i]
        HideNativeCheckTexture(self[getter] and self[getter](self))
    end
end
--- Toggle visuals are custom-built to avoid Blizzard template art leaking into
--- Menu2 styling. State changes are still driven by CheckButton semantics.
local function RefreshToggleControl(button, hover, down)
    local refresh = button and button._msuf2RefreshToggleFeedback
    if refresh then refresh(button, hover, down) end
end
local TOGGLE_CONTROL_HOOKS = {
    OnShow = function(self)
        if T.StyleCheckmark then T.StyleCheckmark(self) end
        if self._msuf2SuppressNativeCheckChrome then self:_msuf2SuppressNativeCheckChrome() end
        if self._msuf2UpdateToggleProxyBounds then self:_msuf2UpdateToggleProxyBounds() end
        RefreshToggleControl(self)
    end,
    OnEnter = function(self) self._msuf2ToggleHovered = true; RefreshToggleControl(self, true, self._msuf2TogglePressed) end,
    OnLeave = function(self) self._msuf2ToggleHovered = nil; self._msuf2TogglePressed = nil; RefreshToggleControl(self) end,
    OnMouseDown = function(self) T.CommitFocusedInput(); self._msuf2TogglePressed = true; RefreshToggleControl(self, self._msuf2ToggleHovered, true) end,
    OnMouseUp = function(self) self._msuf2TogglePressed = nil; RefreshToggleControl(self, self._msuf2ToggleHovered) end,
    OnClick = function(self) RefreshToggleControl(self, self._msuf2ToggleHovered) end,
    OnEnable = function(self) RefreshToggleControl(self, self._msuf2ToggleHovered) end,
    OnDisable = function(self) RefreshToggleControl(self) end,
}
local function LabelOwner(self, key, requireEnabled)
    local btn = self and self[key]
    return (btn and not (requireEnabled and btn.IsEnabled and not btn:IsEnabled())) and btn or nil
end
local TOGGLE_LABEL_HOOKS = {
    OnClick = function(self)
        local btn = LabelOwner(self, "_msuf2ToggleOwner", true)
        if not btn then return end
        ClickCheckButton(btn, "LeftButton")
        RefreshToggleControl(btn, true)
    end,
    OnEnter = function(self)
        local btn = LabelOwner(self, "_msuf2ToggleOwner")
        if not btn then return end
        btn._msuf2ToggleHovered = true
        RefreshToggleControl(btn, true)
    end,
    OnMouseDown = function(self)
        local btn = LabelOwner(self, "_msuf2ToggleOwner", true)
        if not btn then return end
        btn._msuf2TogglePressed = true
        RefreshToggleControl(btn, true, true)
    end,
    OnMouseUp = function(self)
        local btn = LabelOwner(self, "_msuf2ToggleOwner")
        if not btn then return end
        btn._msuf2TogglePressed = nil
        RefreshToggleControl(btn, btn._msuf2ToggleHovered)
    end,
    OnLeave = function(self)
        local btn = LabelOwner(self, "_msuf2ToggleOwner")
        if not btn then return end
        btn._msuf2ToggleHovered = nil
        btn._msuf2TogglePressed = nil
        RefreshToggleControl(btn)
    end,
}
local SWITCH_BG_ON = { 0.020, 0.090, 0.135, 0.96 }
local SWITCH_BG_OFF = { 0.014, 0.022, 0.048, 0.96 }
local SWITCH_EDGE_ON = { 0.160, 0.560, 0.760, 0.86 }
local SWITCH_EDGE_OFF = { 0.095, 0.145, 0.255, 0.82 }
local SWITCH_KNOB_ON = { 0.380, 0.760, 0.900, 1.00 }
local SWITCH_KNOB_OFF = { 0.680, 0.760, 0.940, 1.00 }
-- The literal ON family above is the tuned midnight-cyan look. With a custom
-- menu accent active, derive the ON family from the (already swapped) accent
-- token instead so switches follow the accent like every token-driven control.
local SWITCH_ACCENT_BG_ON = { 0, 0, 0, 0.96 }
local SWITCH_ACCENT_EDGE_ON = { 0, 0, 0, 0.86 }
local SWITCH_ACCENT_KNOB_ON = { 0, 0, 0, 1.00 }
local function SwitchOnColors()
    if not (T.MenuAccentActive and T.MenuAccentActive()) then
        return SWITCH_BG_ON, SWITCH_EDGE_ON, SWITCH_KNOB_ON
    end
    local a = T.colors.accent or SWITCH_EDGE_ON
    SWITCH_ACCENT_BG_ON[1], SWITCH_ACCENT_BG_ON[2], SWITCH_ACCENT_BG_ON[3] =
        a[1] * 0.16, a[2] * 0.16, a[3] * 0.16
    SWITCH_ACCENT_EDGE_ON[1], SWITCH_ACCENT_EDGE_ON[2], SWITCH_ACCENT_EDGE_ON[3] =
        a[1] * 0.78, a[2] * 0.78, a[3] * 0.78
    SWITCH_ACCENT_KNOB_ON[1], SWITCH_ACCENT_KNOB_ON[2], SWITCH_ACCENT_KNOB_ON[3] =
        min(a[1] + (1 - a[1]) * 0.35, 1), min(a[2] + (1 - a[2]) * 0.35, 1), min(a[3] + (1 - a[3]) * 0.35, 1)
    return SWITCH_ACCENT_BG_ON, SWITCH_ACCENT_EDGE_ON, SWITCH_ACCENT_KNOB_ON
end
local function PlaySwitchFeedback(button)
    if not (button and button._msuf2SwitchFlash) then return end
    local checked = button.GetChecked and button:GetChecked()
    local c = checked and T.colors.accent or (T.colors.borderSoft or T.colors.border)
    local alpha = checked and 0.28 or 0.18
    button._msuf2SwitchFlash:SetVertexColor(c[1], c[2], c[3], alpha)
    button._msuf2SwitchFlash:SetAlpha(alpha)
    PlayWidgetMotion(button._msuf2SwitchFlash, "controlFeedback", { fromAlpha = alpha, toAlpha = 0 })
end
local switchOffRehueChecked
local function RefreshSwitchVisual(button, hover)
    if not button then return end
    if MSUF.MenuSkin then MSUF.MenuSkin.TrackPaint(button, RefreshSwitchVisual, hover) end
    if not switchOffRehueChecked then
        switchOffRehueChecked = true
        if T.MenuAccentRehueLiteral then
            T.MenuAccentRehueLiteral(SWITCH_BG_OFF)
            T.MenuAccentRehueLiteral(SWITCH_EDGE_OFF)
            T.MenuAccentRehueLiteral(SWITCH_KNOB_OFF)
        end
    end
    hover = hover or button._msuf2SwitchHovered
    local pressed = button._msuf2SwitchPressed and true or false
    local checked = button.GetChecked and button:GetChecked()
    local enabled = not button.IsEnabled or button:IsEnabled()
    local onBg, onEdge, onKnob = SwitchOnColors()
    local bg = checked and onBg or SWITCH_BG_OFF
    local br = checked and onEdge or SWITCH_EDGE_OFF
    local kb = checked and onKnob or SWITCH_KNOB_OFF
    if MSUF.MenuSkin and MSUF.MenuSkin.IsActive() then
        bg = checked and T.colors.checkActive or T.colors.checkInactive
        br = checked and T.colors.checkActiveEdge or T.colors.checkInactiveEdge
        kb = checked and T.colors.title or T.colors.muted
    end
    local mul = enabled and (pressed and 1.10 or hover and 1.08 or 1) or 1
    local alpha = enabled and 1 or 0.58
    if button._msuf2SwitchFill then button._msuf2SwitchFill:SetVertexColor(min(bg[1] * mul, 1), min(bg[2] * mul, 1), min(bg[3] * mul, 1), bg[4] * alpha) end
    if button._msuf2SwitchEdge then button._msuf2SwitchEdge:SetVertexColor(min(br[1] * mul, 1), min(br[2] * mul, 1), min(br[3] * mul, 1), br[4] * alpha) end
    local knob = button._msuf2SwitchKnob
    if knob then
        local size = button._msuf2SwitchKnobSize or 18
        local pad = button._msuf2SwitchKnobPad or 2
        knob:ClearAllPoints()
        UseControlTexture(knob, button._msuf2SwitchKnobTexture or "Interface\\Buttons\\WHITE8X8")
        knob:SetSize(size, size)
        knob:SetPoint(checked and "RIGHT" or "LEFT", button, checked and "RIGHT" or "LEFT", checked and -pad or pad, 0)
        knob:SetVertexColor(kb[1], kb[2], kb[3], kb[4] * alpha)
        if knob.SetAlpha then knob:SetAlpha(alpha) end
    end
    if button._msuf2Label and button._msuf2Label.SetTextColor then
        local tx = enabled and (hover and T.colors.title or T.colors.text) or (T.colors.disabled or T.colors.dim)
        button._msuf2Label:SetTextColor(tx[1], tx[2], tx[3], tx[4] or 1)
    end
    button._msuf2SwitchPaintedChecked = checked and true or false
end
local function SetSwitchChecked(button, value)
    local checked = value and true or false
    local before = button.GetChecked and button:GetChecked()
    if button._msuf2RawSetChecked then button._msuf2RawSetChecked(button, checked) end
    if before ~= checked then PlaySwitchFeedback(button) end
    RefreshSwitchVisual(button)
end
local SWITCH_CONTROL_HOOKS = {
    OnEnter = function(self) self._msuf2SwitchHovered = true; RefreshSwitchVisual(self, true) end,
    OnLeave = function(self) self._msuf2SwitchHovered = nil; self._msuf2SwitchPressed = nil; RefreshSwitchVisual(self) end,
    OnMouseDown = function(self) T.CommitFocusedInput(); self._msuf2SwitchPressed = true; RefreshSwitchVisual(self) end,
    OnMouseUp = function(self) self._msuf2SwitchPressed = nil; RefreshSwitchVisual(self) end,
    OnClick = RefreshSwitchVisual,
    OnEnable = RefreshSwitchVisual,
    OnDisable = function(self) self._msuf2SwitchHovered = nil; self._msuf2SwitchPressed = nil; RefreshSwitchVisual(self) end,
}
local SWITCH_LABEL_HOOKS = {
    OnClick = function(self)
        local btn = LabelOwner(self, "_msuf2SwitchOwner", true)
        if not btn then return end
        ClickCheckButton(btn, "LeftButton")
    end,
    OnEnter = function(self)
        local btn = LabelOwner(self, "_msuf2SwitchOwner")
        if not btn then return end
        btn._msuf2SwitchHovered = true
        RefreshSwitchVisual(btn, true)
        if btn.LockHighlight then btn:LockHighlight() end
    end,
    OnMouseDown = function(self)
        local btn = LabelOwner(self, "_msuf2SwitchOwner", true)
        if not btn then return end
        btn._msuf2SwitchPressed = true
        RefreshSwitchVisual(btn, true)
    end,
    OnMouseUp = function(self)
        local btn = LabelOwner(self, "_msuf2SwitchOwner")
        if not btn then return end
        btn._msuf2SwitchPressed = nil
        RefreshSwitchVisual(btn, btn._msuf2SwitchHovered)
    end,
    OnLeave = function(self)
        local btn = LabelOwner(self, "_msuf2SwitchOwner")
        if not btn then return end
        btn._msuf2SwitchHovered = nil
        btn._msuf2SwitchPressed = nil
        RefreshSwitchVisual(btn)
        if btn.UnlockHighlight then btn:UnlockHighlight() end
    end,
}
local function CreateToggle(section, label, x, y, labelWidth)
    local btn = PixelLayoutRegion(CreateFrame("CheckButton", nil, section, "UICheckButtonTemplate"))
    btn._msuf2ControlKind = "toggle"
    btn._msuf2QuietCheckBox = true
    btn:SetPoint("TOPLEFT", x, y)
    btn:SetSize(28, 28)
    btn._msuf2Label = T.Font(section, "GameFontHighlightSmall", label or "", T.colors.text, "control")
    SetSearchText(btn._msuf2Label, label)
    btn._msuf2Label:SetPoint("LEFT", btn, "RIGHT", 8, 0)
    btn._msuf2Label:SetJustifyH("LEFT")
    if not labelWidth and section and section._msuf2Width then labelWidth = max(40, (section._msuf2Width or 0) - (x or 0) - 50) end
    if labelWidth then btn._msuf2Label:SetWidth(labelWidth) end
    btn.text = btn._msuf2Label
    if T.StyleCheckmark then T.StyleCheckmark(btn) end
    btn._msuf2SuppressNativeCheckChrome = SuppressNativeCheckChrome
    btn:_msuf2SuppressNativeCheckChrome()
    local checkFillTexture = (T.media and T.media.checkBoxFill) or "Interface\\Buttons\\WHITE8X8"
    local checkEdgeTexture = (T.media and T.media.checkBoxEdge) or checkFillTexture
    local boxEdge = ControlTexture(btn, "_msuf2ToggleEdge", "BACKGROUND", -3, checkEdgeTexture)
    boxEdge:SetSize(23, 23)
    boxEdge:SetPoint("CENTER", btn, "CENTER", 0, 0)
    local boxFill = ControlTexture(btn, "_msuf2ToggleFill", "BACKGROUND", -2, checkFillTexture)
    boxFill:SetSize(21, 21)
    boxFill:SetPoint("CENTER", btn, "CENTER", 0, 0)
    local hoverFill = ControlTexture(btn, "_msuf2ToggleHoverFill", "BACKGROUND", -1, checkFillTexture)
    hoverFill:SetAllPoints(boxFill)
    hoverFill:SetVertexColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 1)
    hoverFill:SetAlpha(0)
    hoverFill:Show()
    local rowHover = PixelLayoutRegion(section:CreateTexture(nil, "BORDER", nil, 1))
    rowHover:SetTexture((T.media and T.media.superellipse) or "Interface\\Buttons\\WHITE8X8")
    if rowHover.SetTexCoord then rowHover:SetTexCoord(0, 1, 0, 1) end
    rowHover:SetVertexColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 1)
    rowHover:SetAlpha(0)
    rowHover:Show()
    btn._msuf2ToggleRowHover = rowHover
    btn._msuf2UpdateToggleProxyBounds = UpdateToggleProxyBounds
    local function SetToggleHoverVisual(self, show, down)
        local tex = self._msuf2ToggleHoverFill
        local rowTex = self._msuf2ToggleRowHover
        if not tex and not rowTex then return end
        local enabled = not (self.IsEnabled and not self:IsEnabled())
        if not enabled then show = false end
        local target = show and (down and 0.160 or 0.110) or 0
        local rowTarget = show and (down and 0.075 or 0.050) or 0
        local c = T.colors.checkActiveEdge or T.colors.accent
        if tex then
            if tex.SetTexture then tex:SetTexture(checkFillTexture) end
            if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
            if tex.SetVertexColor then tex:SetVertexColor(c[1], c[2], c[3], 1) end
            tex:SetAlpha(target)
            if tex.Show then tex:Show() end
        end
        if rowTex then
            if rowTex.SetTexture then rowTex:SetTexture((T.media and T.media.superellipse) or "Interface\\Buttons\\WHITE8X8") end
            if rowTex.SetTexCoord then rowTex:SetTexCoord(0, 1, 0, 1) end
            if rowTex.SetVertexColor then rowTex:SetVertexColor(c[1], c[2], c[3], 1) end
            rowTex:SetAlpha(rowTarget)
            if rowTex.Show then rowTex:Show() end
        end
    end
    local function RefreshToggleFeedback(self, hover, down)
        hover = hover and true or false
        down = down and true or false
        local enabled = not (self.IsEnabled and not self:IsEnabled())
        local checked = (self.GetChecked and self:GetChecked()) and true or false
        local active = T.colors.checkActive or ThemeColor("coreSurface", { 0.014, 0.038, 0.072, 1.00 })
        local inactive = T.colors.checkInactive or ThemeColor("coreShadow", { 0.006, 0.016, 0.032, 1.00 })
        local bg = checked and active or inactive
        local br = checked
            and (T.colors.checkActiveEdge or { min(active[1] + 0.20, 1), min(active[2] + 0.31, 1), min(active[3] + 0.48, 1), 0.90 })
            or (T.colors.checkInactiveEdge or ThemeColor("coreRim", { 0.043, 0.096, 0.150, 1.00 }))
        local bgMul = enabled and (down and 1.14 or hover and 1.08 or 1) or 1
        local borderAlpha = enabled
            and (checked and (down and 1.00 or hover and 0.96 or 0.88) or (down and 0.90 or hover and 0.80 or 0.68))
            or 0.30
        local alpha = enabled and 1 or 0.58
        local tx = enabled and (hover and T.colors.title or T.colors.text) or (T.colors.disabled or T.colors.dim)
        local visualKey = tostring(enabled) .. "\030" .. tostring(checked) .. "\030" .. tostring(hover) .. "\030" .. tostring(down)
            .. "\030" .. tostring(bg[1]) .. "\030" .. tostring(bg[2]) .. "\030" .. tostring(bg[3]) .. "\030" .. tostring(bg[4])
            .. "\030" .. tostring(br[1]) .. "\030" .. tostring(br[2]) .. "\030" .. tostring(br[3]) .. "\030" .. tostring(br[4])
            .. "\030" .. tostring(tx and tx[1]) .. "\030" .. tostring(tx and tx[2]) .. "\030" .. tostring(tx and tx[3]) .. "\030" .. tostring(tx and tx[4])
        if self._msuf2ToggleVisualKey == visualKey then return end
        self._msuf2ToggleVisualKey = visualKey
        if self._msuf2ToggleFill then
            local bgAlpha = checked and 0.98 or (down and 0.92 or hover and 0.86 or 0.80)
            self._msuf2ToggleFill:SetVertexColor(min(bg[1] * bgMul, 1), min(bg[2] * bgMul, 1), min(bg[3] * bgMul, 1), bgAlpha * alpha)
        end
        if self._msuf2ToggleEdge then self._msuf2ToggleEdge:SetVertexColor(br[1], br[2], br[3], borderAlpha * alpha) end
        local check = self.GetCheckedTexture and self:GetCheckedTexture()
        if check and check.SetVertexColor then check:SetVertexColor(1.000, 1.000, 1.000, enabled and 0.96 or 0.42) end
        SyncCheckedTexture(self, checked, enabled)
        SetToggleHoverVisual(self, hover and enabled, down and enabled)
        if self._msuf2Label and self._msuf2Label.SetTextColor then
            local r, g, b, a = tx[1], tx[2], tx[3], tx[4] or 1
            self._msuf2Label._msuf2TextColorR, self._msuf2Label._msuf2TextColorG = r, g
            self._msuf2Label._msuf2TextColorB, self._msuf2Label._msuf2TextColorA = b, a
            self._msuf2Label:SetTextColor(r, g, b, a)
        end
    end
    btn._msuf2RefreshToggleFeedback = RefreshToggleFeedback
    local rawSetChecked = btn.SetChecked
    btn.SetChecked = function(self, value)
        rawSetChecked(self, value and true or false)
        SyncCheckedTexture(self, value, not (self.IsEnabled and not self:IsEnabled()))
        RefreshToggleFeedback(self, self._msuf2ToggleHovered, self._msuf2TogglePressed)
    end
    for script, handler in pairs(TOGGLE_CONTROL_HOOKS) do btn:HookScript(script, handler) end
    local labelHit = PixelLayoutRegion(CreateFrame("Button", nil, section))
    labelHit:EnableMouse(true)
    if labelHit.RegisterForClicks then labelHit:RegisterForClicks("LeftButtonUp") end
    labelHit:SetFrameLevel(btn:GetFrameLevel() + 2)
    labelHit._msuf2ToggleOwner = btn
    for script, handler in pairs(TOGGLE_LABEL_HOOKS) do labelHit:SetScript(script, handler) end
    if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(labelHit, btn)
    else labelHit._msuf2ControlPartOf = btn end
    btn._msuf2LabelHit = labelHit
    btn._msuf2UseProxyMouse = true
    if btn.EnableMouse then btn:EnableMouse(false) end
    btn:SetChecked(false)
    SyncCheckedTexture(btn, false, true)
    UpdateToggleProxyBounds(btn)
    RegisterSearchObject(btn, label, "toggle", { anchor = btn._msuf2Label })
    return btn
end
function W.Toggle(section, label)
    local x, y = NextRow(section, 32)
    return CreateToggle(section, label, x, y)
end
function W.ToggleAt(section, label, x, y, labelWidth)
    return CreateToggle(section, label, x or 16, y or -40, labelWidth)
end
-- literal: the label is a name the user typed and is shown as given, never looked up.
function W.SwitchAt(section, label, x, y, labelWidth, labelSide, literal)
    local switchW, switchH = 36, 20
    local knobSize = 16
    local knobPad = 2
    local switchTrackTexture = (T.media and T.media.switchTrack) or (T.media and T.media.superellipse) or "Interface\\Buttons\\WHITE8X8"
    local switchKnobTexture = (T.media and T.media.switchKnob) or (T.media and T.media.sliderThumb) or (T.media and T.media.superellipse)
        or "Interface\\Buttons\\WHITE8X8"
    local btn = PixelLayoutRegion(CreateFrame("CheckButton", nil, section))
    btn._msuf2ControlKind = "toggle"
    btn:SetPoint("TOPLEFT", x or 16, y or -40)
    btn:SetSize(switchW, switchH)
    if btn.RegisterForClicks then btn:RegisterForClicks("LeftButtonUp") end
    if btn.EnableMouse then btn:EnableMouse(true) end
    if btn.SetHitRectInsets then btn:SetHitRectInsets(-2, -2, -3, -3) end
    local edge = ControlTexture(btn, "_msuf2SwitchEdge", "BACKGROUND", 0, switchTrackTexture)
    edge:SetAllPoints(btn)
    local fill = ControlTexture(btn, "_msuf2SwitchFill", "BACKGROUND", 1, switchTrackTexture)
    fill:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    local flash = ControlTexture(btn, "_msuf2SwitchFlash", "ARTWORK", 2, switchTrackTexture)
    flash:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    flash:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    flash:SetVertexColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0)
    flash:SetAlpha(0)
    local knob = ControlTexture(btn, "_msuf2SwitchKnob", "OVERLAY", nil, switchKnobTexture)
    knob:SetSize(knobSize, knobSize)
    btn._msuf2SwitchKnobSize = knobSize
    btn._msuf2SwitchKnobPad = knobPad
    btn._msuf2SwitchKnobTexture = switchKnobTexture
    btn._msuf2ProxyBaseWidth = switchW + 12
    btn._msuf2UpdateToggleProxyBounds = UpdateToggleProxyBounds
    local side = labelSide or "RIGHT"
    local labelFS = T.Font(section, "GameFontHighlightSmall", not literal and label or "", T.colors.text, "control")
    if literal then T.SetTranslatedText(labelFS, label or "") end
    SetSearchText(labelFS, label)
    labelFS:SetJustifyH(side == "LEFT" and "RIGHT" or "LEFT")
    if not labelWidth and section and section._msuf2Width then labelWidth = max(40, (section._msuf2Width or 0) - (x or 0) - switchW - 30) end
    if labelWidth then labelFS:SetWidth(max(20, labelWidth - (side == "RIGHT" and 22 or 0))) end
    if side == "LEFT" then
        labelFS:SetPoint("RIGHT", btn, "LEFT", -8, 0)
    else
        labelFS:SetPoint("LEFT", btn, "RIGHT", 8, 0)
    end
    if side == "HIDDEN" then labelFS:Hide() end
    btn._msuf2Label = labelFS
    btn._msuf2LiteralSearchLabel = literal or nil
    btn.text = labelFS
    btn._msuf2RefreshSwitchVisual = RefreshSwitchVisual
    btn._msuf2RawSetChecked = btn.SetChecked
    btn.SetChecked = SetSwitchChecked
    for script, handler in pairs(SWITCH_CONTROL_HOOKS) do btn:HookScript(script, handler) end
    if side ~= "HIDDEN" then
        local labelHit = PixelLayoutRegion(CreateFrame("Button", nil, section))
        labelHit:EnableMouse(true)
        if labelHit.RegisterForClicks then labelHit:RegisterForClicks("LeftButtonUp") end
        labelHit:SetFrameLevel(btn:GetFrameLevel() + 2)
        labelHit._msuf2SwitchOwner = btn
        for script, handler in pairs(SWITCH_LABEL_HOOKS) do labelHit:SetScript(script, handler) end
        if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(labelHit, btn)
        else labelHit._msuf2ControlPartOf = btn end
        btn._msuf2LabelHit = labelHit
        btn._msuf2UseProxyMouse = true
        if btn.EnableMouse then btn:EnableMouse(false) end
    end
    btn:SetChecked(false)
    UpdateToggleProxyBounds(btn)
    RegisterSearchObject(btn, label, "toggle", { anchor = side ~= "HIDDEN" and labelFS or btn })
    return btn
end
-- A section's master switch belongs to its always-visible header. Reuse the
-- same widget when lazy content builds, preserving the exact binding identity.
function W.SectionSwitch(section, label, displayLabel)
    local entry = section and section._msuf2CollapsibleEntry
    if not (entry and entry.header) then return W.SwitchAt(section, label, 16, -16) end
    if entry.featureSwitch then return entry.featureSwitch end
    local button = W.SwitchAt(entry.header, label, 0, 0, 0, "HIDDEN")
    button:ClearAllPoints()
    button:SetPoint("RIGHT", entry.header, "RIGHT", -14, 0)
    button:SetFrameLevel(entry.header:GetFrameLevel() + 3)
    local state = T.Font(entry.header, "GameFontHighlightSmall", displayLabel or "Enable", T.colors.text, "caption")
    state:SetPoint("RIGHT", button, "LEFT", -8, 0)
    local setChecked = button.SetChecked
    button.SetChecked = function(self, checked)
        checked = checked and true or false
        -- Native clicks can change GetChecked before the binding repaints.
        -- Skip settled scope refreshes only when the visual also agrees.
        if (self:GetChecked() and true or false) ~= checked or self._msuf2SwitchPaintedChecked ~= checked then
            setChecked(self, checked)
        end
    end
    button:SetChecked(false)
    entry.featureSwitch = button
    entry._msuf2FeatureSwitchLabel = state
    entry._msuf2FeatureSwitchReserve = 112
    if entry._msuf2RefreshLayout then entry._msuf2RefreshLayout() end
    if M.AddTooltip then M.AddTooltip(button, label, nil, { hook = true }) end
    return button
end
local function ScopeButtonWidth(item)
    if item and item.width then return item.width end
    local value = item and item.value
    local text = tostring(Tr((item and (item.text or item.label)) or value or ""))
    if value == "shared" then return 72 end
    if value == "targettarget" then return 58 end
    if value == "focustarget" then return 92 end
    if text:match("^Boss [1-5]$") then return 74 end
    return math.max(54, math.min(96, 28 + (#text * 7)))
end
local function MeasureScopeOverrideLayout(values, opts)
    opts = opts or {}
    values = values or opts.values or {}
    local centerY = opts.centerY or -28
    local labelX = opts.labelX or 14
    local labelW = opts.labelWidth or 64
    local gap = opts.gap or 8
    local buttonH = opts.buttonHeight or 24
    local rowStep = opts.rowStep or (buttonH + 6)
    local sectionW = opts.width or (opts.ctx and opts.ctx.width) or 720
    local maxRight = opts.maxRight or (sectionW - 14)
    local startX = opts.startX or (labelX + labelW + 8)
    local x, y = startX, centerY
    local rows = 1
    for i = 1, #values do
        local width = ScopeButtonWidth(values[i])
        if x > startX and x + width > maxRight then
            x = startX
            y = y - rowStep
            rows = rows + 1
        end
        x = x + width + gap
    end
    return {
        rows = rows,
        bottomY = y - math.floor(buttonH * 0.5 + 0.5),
        centerY = centerY,
        lastRowCenterY = y,
        rowStep = rowStep,
        buttonHeight = buttonH,
        sectionWidth = sectionW,
        maxRight = maxRight,
        startX = startX,
    }
end
function W.MeasureScopeOverrideBar(values, opts)
    if type(values) == "table" and values.values and opts == nil then
        opts = values
        values = opts.values
    end
    return MeasureScopeOverrideLayout(values, opts)
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
    local rowStep = opts.rowStep or (buttonH + 6)
    local metrics = MeasureScopeOverrideLayout(values, {
        centerY = centerY,
        labelX = labelX,
        labelWidth = labelW,
        gap = gap,
        buttonHeight = buttonH,
        rowStep = rowStep,
        width = sectionW,
        maxRight = maxRight,
        startX = startX,
    })
    local label = T.Font(section, opts.labelFont or "GameFontHighlightSmall", opts.label or "Editing:", opts.labelColor or T.colors.text, "control")
    SetSearchText(label, opts.label or "Editing:")
    RegisterSearchObject(label, opts.label or "Editing:", "text")
    label:SetPoint("LEFT", section, "TOPLEFT", labelX, centerY)
    label:SetWidth(labelW)
    label:SetJustifyH("LEFT")
    local bar = PixelLayoutRegion(CreateFrame("Frame", nil, section))
    SetSearchTitle(bar, opts.label or "Editing:")
    RegisterSearchObject(bar, opts.label or "Editing:", "segment", { values = values })
    bar:SetPoint("TOPLEFT", section, "TOPLEFT", 0, 0)
    bar:SetSize(sectionW, math.abs(metrics.bottomY) + 6)
    bar.buttons = {}
    bar.values = values
    bar.label = label
    bar._msuf2Rows = metrics.rows
    bar._msuf2BottomY = metrics.bottomY
    bar._msuf2LastRowCenterY = metrics.lastRowCenterY
    local x, y = startX, centerY
    for i = 1, #values do
        local item = values[i]
        local width = ScopeButtonWidth(item)
        if x > startX and x + width > maxRight then
            x = startX
            y = y - rowStep
        end
        local btn = T.Button(section, item.text or item.label or item.value or "", width, buttonH, { history = false })
        btn._msuf2SegmentChoice = true
        -- The logical ScopeOverrideBar owns search/catalog identity and values.
        -- Child buttons are implementation details; registering both creates
        -- duplicate/unknown controls for one selection.
        if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(btn, bar)
        else btn._msuf2ControlPartOf = bar end
        btn:SetPoint("LEFT", section, "TOPLEFT", x, y)
        btn._msuf2Value = item.value
        btn._msuf2BaseWidth = width
        T.CenterButtonLabel(btn)
        if btn.RefreshVisual then btn:RefreshVisual() end
        -- A scope switch the page stores in the profile stays undoable; a
        -- click on the scope already shown records nothing.
        btn:SetScript("OnClick", function(self)
            if bar:SetValue(item.value) then
                M.CheckpointHistory(self:GetText() or "Scope", "button:" .. tostring(self))
            end
        end)
        -- Scope bars that know per-scope overrides mark a departing scope with
        -- a " *" text cue (not color alone) and say so on hover.
        if type(opts.hasOverride) == "function" and item.value ~= "shared" then
            btn._msuf2ScopeText = Tr(item.text or item.label or item.value or "")
            if M.AddTooltip then M.AddTooltip(btn, item.text or item.label or item.value, W.ScopeOverrideTooltipBody, { hook = true }) end
        end
        bar.buttons[i] = btn
        x = x + width + gap
    end
    function bar:GetValue()
        if type(opts.getValue) == "function" then return opts.getValue() end
        return opts.value
    end
    function bar:SetValue(value)
        local current = self:GetValue()
        if current == value then
            self:Refresh()
            return false
        end
        if type(opts.setValue) == "function" then opts.setValue(value) end
        if type(opts.onChange) == "function" then opts.onChange(value) end
        self:Refresh()
        return self:GetValue() == value
    end
    function bar:GetLayoutMetrics()
        return metrics
    end
    function bar:Refresh()
        local value = self:GetValue()
        for i = 1, #self.buttons do
            local btn = self.buttons[i]
            local active = btn._msuf2Value == value
            local override = false
            if type(opts.hasOverride) == "function" then override = opts.hasOverride(btn._msuf2Value) and true or false end
            local nextOverride = (not active) and override or false
            if btn._msuf2Active ~= active or btn._msuf2Override ~= nextOverride then
                btn._msuf2Override = nextOverride
                btn:SetActive(active)
            end
            if btn._msuf2ScopeText and btn._msuf2ScopeOverride ~= override then
                btn._msuf2ScopeOverride = override
                if btn._msuf2Label then T.SetTranslatedText(btn._msuf2Label, override and (btn._msuf2ScopeText .. " *") or btn._msuf2ScopeText) end
            end
        end
    end
    M.TrackRefresh(ctx, function() bar:Refresh() end)
    return bar
end
function W.ScopeOverrideTooltipBody(button)
    return button and button._msuf2ScopeOverride and "Has its own settings" or "Follows shared settings"
end

local function IsNumericLayerControl(label, minValue, maxValue)
    if tonumber(minValue) ~= 0 or tonumber(maxValue) ~= 30 then return false end
    local text = tostring(label or ""):lower()
    if text:find("layer", 1, true) then return true end
    local translatedLayer = tostring(Tr("Layer") or ""):lower()
    if translatedLayer ~= "" and text:find(translatedLayer, 1, true) then return true end
    local frameLevel = tostring(Tr("Frame level") or ""):lower()
    local frameLayer = tostring(Tr("Frame layer") or ""):lower()
    return text == "frame level" or text == "frame layer"
        or (frameLevel ~= "" and text == frameLevel)
        or (frameLayer ~= "" and text == frameLayer)
end

local LAYER_OVERVIEW_SHORTCUT_TEXT = "|cffffffff•|r|cffffffff•|r|cffffffff•|r"
local function AttachLayerOverviewButton(section, slider, title, label, minValue, maxValue)
    if not (section and slider and title and IsNumericLayerControl(label, minValue, maxValue)) then return nil end
    local shortcut = T.Button(section, LAYER_OVERVIEW_SHORTCUT_TEXT, 34, 20, { noSearch = true })
    shortcut:SetPoint("TOPRIGHT", title, "TOPRIGHT", 0, 2)
    shortcut:SetAlpha(0.58)
    shortcut._msuf2SkipHistoryCheckpoint = true
    shortcut._msuf2LayerOverviewButton = true
    AddThreeDotShortcutTextures(shortcut, LAYER_SHORTCUT_DOTS)
    if shortcut.SetFrameLevel and slider.GetFrameLevel then shortcut:SetFrameLevel(slider:GetFrameLevel() + 4) end
    if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(shortcut, slider)
    else shortcut._msuf2ControlPartOf = slider end
    if shortcut.HookScript then
        shortcut:HookScript("OnEnter", function(self) self:SetAlpha(0.96) end)
        shortcut:HookScript("OnLeave", function(self) self:SetAlpha(0.58) end)
    end
    shortcut:SetScript("OnClick", function(self)
        local show = M.ShowLayerOverview or _G.MSUF_ShowLayerOverview
        if type(show) == "function" then show(self) end
    end)
    if shortcut.HookScript then
        shortcut:HookScript("OnHide", function(self)
            local hide = M.HideLayerOverviewForAnchor or _G.MSUF_HideLayerOverviewForAnchor
            if type(hide) == "function" then hide(self) end
        end)
    end
    if type(M.AddTooltip) == "function" then
        M.AddTooltip(shortcut, "Layer overview", "Shows every configurable MSUF layer on the unified 0-30 scale.", { hook = true, owner = "ANCHOR_RIGHT" })
    end
    slider._msuf2LayerShortcutButton = shortcut
    return shortcut
end

--- Slider wraps Blizzard's slider template but hides native art and stamps
--- callbacks so profile writes only happen when the effective value changes.
local function ParseSliderInput(slider, text)
    if type(slider._msuf2ValueParser) == "function" then
        local parsed = tonumber(slider._msuf2ValueParser(text, slider))
        if parsed ~= nil then return parsed end
    end
    local normalized = text:match("^%s*([+-]?%d+,%d+)%s*$")
    return tonumber(normalized and normalized:gsub(",", ".") or text)
end
function W.Slider(section, label, minVal, maxVal, step, width)
    local x, y = NextRow(section, 48)
    local valueGap = 8
    local buttonGap = 4
    local stepButtonW = 20
    local editW = 52
    local minTrackW = 96
    local compactMinTrackW = 48
    local sliderH = 24
    local valueClusterW = valueGap + stepButtonW + buttonGap + editW + buttonGap + stepButtonW
    local compactValueClusterW = valueGap + editW
    width = width or 280
    if section and section._msuf2Width then
        local available = section._msuf2Width - x - 14
        if available > 0 and width > available then width = max(72, available) end
    end
    local title = T.Font(section, "GameFontHighlightSmall", label or "", T.colors.text, "control")
    SetSearchText(title, label)
    title:SetPoint("TOPLEFT", x, y)
    title:SetWidth(width)
    title:SetJustifyH("LEFT")
    -- Unnamed: a template-free Slider has no named parts, and a name per slider
    -- would leave one permanent global behind for every slider ever built.
    local slider = PixelLayoutRegion(CreateFrame("Slider", nil, section))
    slider._msuf2Title = title
    slider._msuf2ControlKind = "slider"
    RegisterSearchObject(slider, label, "slider", { anchor = title })
    slider:SetPoint("TOPLEFT", x, y - 24)
    slider:SetSize(max(compactMinTrackW, width - valueClusterW), sliderH)
    if slider.EnableMouse then slider:EnableMouse(true) end
    slider:SetMinMaxValues(minVal or 0, maxVal or 1)
    slider:SetValueStep(step or 1)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    -- Steps-per-page 0 disables the engine's own track-click jump; the press is
    -- handled entirely by the cursor-follow drag below.
    if slider.SetStepsPerPage then slider:SetStepsPerPage(0) end
    slider._msuf2CursorDrag = true
    slider._msuf2Step = step or 1
    slider._msuf2RequestedWidth = width
    slider._msuf2MinRowWidth = compactMinTrackW
    HideSliderTemplateParts(slider)
    if T.StyleSlider then T.StyleSlider(slider) end
    local function StepButton(text)
        local btn = T.Button(section, text, 20, 24, { noSearch = true, history = false })
        SetSearchText(btn, text)
        if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(btn, slider)
        else btn._msuf2ControlPartOf = slider end
        return T.CenterButtonLabel(btn)
    end
    local minus = StepButton("-")
    local edit = PixelLayoutRegion(CreateFrame("EditBox", nil, section, "InputBoxTemplate"))
    edit:SetSize(editW, 24)
    edit:SetAutoFocus(false)
    edit:SetJustifyH("CENTER")
    edit:SetNumeric(false)
    T.SkinEditBox(edit)
    if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(edit, slider)
    else edit._msuf2ControlPartOf = slider end
    slider.editBox = edit
    edit._msuf2CommitOnPointer = true
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
        fill:SetWidth(max(1, max(1, slider:GetWidth() - 2) * pct))
        if slider._msuf2UpdateThumb then slider:_msuf2UpdateThumb() end
    end
    slider._msuf2UpdateFill = UpdateFill
    function slider:_msuf2SetLayoutWidth(totalWidth)
        totalWidth = tonumber(totalWidth) or width or 280
        self._msuf2RowWidth = totalWidth
        local tiny = totalWidth < (compactMinTrackW + compactValueClusterW)
        local compact = tiny or totalWidth < (minTrackW + valueClusterW)
        local clusterW = tiny and 0 or (compact and compactValueClusterW or valueClusterW)
        local trackMin = compact and compactMinTrackW or minTrackW
        local trackW = max(trackMin, floor(totalWidth - clusterW + 0.5))
        if title then
            title:SetWidth(max(trackW, floor(totalWidth + 0.5)))
            if title.SetJustifyH then title:SetJustifyH(self._msuf2TitleJustify or "LEFT") end
        end
        self:SetSize(trackW, sliderH)
        minus:ClearAllPoints()
        if compact then
            minus:Hide()
        else
            minus:Show()
            minus:SetPoint("LEFT", self, "RIGHT", valueGap, 0)
        end
        edit:ClearAllPoints()
        if tiny then
            edit:Hide()
        else
            edit:Show()
            edit:SetPoint("LEFT", compact and self or minus, "RIGHT", compact and valueGap or buttonGap, 0)
        end
        plus:ClearAllPoints()
        if compact then
            plus:Hide()
        else
            plus:Show()
            plus:SetPoint("LEFT", edit, "RIGHT", buttonGap, 0)
        end
        UpdateFill()
    end
    slider:_msuf2SetLayoutWidth(width)
    local function FormatValue(value)
        if type(slider._msuf2ValueFormatter) == "function" then
            local text = slider._msuf2ValueFormatter(value, slider)
            if text ~= nil then return tostring(text) end
        end
        local st = step or 1
        if st < 1 then return string.format("%.2f", value) end
        return tostring(floor(value + 0.5))
    end
    slider._msuf2FormatValue = FormatValue
    function slider:SetValueFormatter(fn)
        self._msuf2ValueFormatter = (type(fn) == "function") and fn or nil
        if not self._msuf2Editing then edit:SetText(FormatValue(self:GetValue())) end
    end
    function slider:SetValueParser(fn)
        self._msuf2ValueParser = (type(fn) == "function") and fn or nil
    end
    function slider:SetValueBoxWidth(boxWidth)
        boxWidth = max(40, floor((tonumber(boxWidth) or editW) + 0.5))
        if editW == boxWidth then return end
        editW = boxWidth
        valueClusterW = valueGap + stepButtonW + buttonGap + editW + buttonGap + stepButtonW
        compactValueClusterW = valueGap + editW
        edit:SetWidth(editW)
        self:_msuf2SetLayoutWidth(self._msuf2RowWidth or width)
    end
    function slider:SetInteractionCallbacks(onStart, onStop)
        self._msuf2InteractionStart = type(onStart) == "function" and onStart or nil
        self._msuf2InteractionStop = type(onStop) == "function" and onStop or nil
    end
    slider:HookScript("OnValueChanged", function(self, value)
        UpdateFill()
        if not self._msuf2Editing then edit:SetText(FormatValue(value)) end
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
    local function CommitEdit(self)
        local text = self:GetText()
        if text == self._msuf2EditStartText or (slider.IsEnabled and not slider:IsEnabled()) then return end
        if self._msuf2EditStartValue ~= nil and slider:GetValue() ~= self._msuf2EditStartValue then return end
        local v = ParseSliderInput(slider, text)
        if v ~= nil then slider:SetValue(v) end
        self._msuf2EditStartText = text
    end
    edit:SetScript("OnEnterPressed", function(self)
        CommitEdit(self)
        self:ClearFocus()
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self._msuf2CancelCommit = true
        self:SetText(FormatValue(slider:GetValue()))
        self:ClearFocus()
        self._msuf2CancelCommit = nil
    end)
    edit:SetScript("OnEditFocusGained", function(self)
        slider._msuf2Editing = true
        self._msuf2EditStartText = self:GetText()
        self._msuf2EditStartValue = slider:GetValue()
        if self.HighlightText then self:HighlightText() end
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        if slider._msuf2Editing and not self._msuf2CancelCommit then CommitEdit(self) end
        slider._msuf2Editing = nil
        self._msuf2EditStartText = nil
        self._msuf2EditStartValue = nil
        self:SetText(FormatValue(slider:GetValue()))
        if self.HighlightText then self:HighlightText(0, 0) end
    end)
    local function ClampToSlider(value)
        local minV, maxV = slider:GetMinMaxValues()
        if value < minV then value = minV elseif value > maxV then value = maxV end
        local st = tonumber(slider._msuf2Step) or 1
        if st > 0 then value = minV + (floor(((value - minV) / st) + 0.5) * st) end
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
    local function SliderValueFromCursor()
        if not (GetCursorPosition and slider.GetLeft and slider.GetWidth and slider.GetMinMaxValues) then return nil end
        local left = slider:GetLeft()
        local width = slider:GetWidth()
        if not left or not width or width <= 0 then return nil end
        local cursorX = GetCursorPosition()
        local scale = (slider.GetEffectiveScale and slider:GetEffectiveScale()) or 1
        if not scale or scale == 0 then scale = 1 end
        local pct = ((cursorX / scale) - left) / width
        if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
        local minV, maxV = slider:GetMinMaxValues()
        minV = tonumber(minV) or 0
        maxV = tonumber(maxV) or minV
        return ClampToSlider(minV + ((maxV - minV) * pct))
    end
    local function SetValueFromCursor()
        if slider.IsEnabled and not slider:IsEnabled() then return end
        local value = SliderValueFromCursor()
        if value ~= nil and value ~= tonumber(slider:GetValue()) then
            slider:SetValue(value)
            if slider._msuf2UpdateFill then slider:_msuf2UpdateFill() end
        end
    end
    local function StopSliderInteraction()
        local wasActive = slider._msuf2SliderActive == true
        slider:SetScript("OnUpdate", nil)
        slider._msuf2SliderActive = nil
        if type(slider._msuf2CommitSliderHistory) == "function" then slider:_msuf2CommitSliderHistory() end
        if wasActive and type(slider._msuf2InteractionStop) == "function" then
            slider:_msuf2InteractionStop(slider:GetValue())
        end
        if T.StyleSlider then T.StyleSlider(slider) end
    end
    -- The styled thumb is only a texture, so the engine never runs its own
    -- thumb drag: the press must keep following the cursor until release
    -- instead of jumping once on the down-click.
    local function FollowCursorWhileHeld()
        if not slider._msuf2SliderActive then
            slider:SetScript("OnUpdate", nil)
            return
        end
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            StopSliderInteraction()
            return
        end
        SetValueFromCursor()
    end
    slider:SetScript("OnMouseDown", function(_, button)
        if button and button ~= "LeftButton" then return end
        if slider.IsEnabled and not slider:IsEnabled() then return end
        T.CommitFocusedInput()
        if type(slider._msuf2BeginSliderHistory) == "function" then slider:_msuf2BeginSliderHistory() end
        slider._msuf2SliderActive = true
        if type(slider._msuf2InteractionStart) == "function" then
            slider:_msuf2InteractionStart(slider:GetValue())
        end
        SetValueFromCursor()
        slider:SetScript("OnUpdate", FollowCursorWhileHeld)
    end)
    slider:SetScript("OnMouseUp", function(_, button)
        if button and button ~= "LeftButton" then return end
        StopSliderInteraction()
    end)
    slider:HookScript("OnHide", StopSliderInteraction)
    slider:EnableMouseWheel(true)
    if slider.SetPropagateMouseWheel then slider:SetPropagateMouseWheel(true) end
    slider:SetScript("OnMouseWheel", function(self, delta)
        if not delta or delta == 0 then return end
        if IsShiftKeyDown and IsShiftKeyDown() then
            if self.SetPropagateMouseWheel then self:SetPropagateMouseWheel(false) end
            StepBy(delta > 0 and 1 or -1)
        elseif self.SetPropagateMouseWheel then
            self:SetPropagateMouseWheel(true)
        else
            local scroll = M.scrollFrame
            local handler = scroll and scroll.GetScript and scroll:GetScript("OnMouseWheel")
            if type(handler) == "function" then handler(scroll, delta) end
        end
    end)
    minus:SetScript("OnClick", function() StepBy(-1) end)
    plus:SetScript("OnClick", function() StepBy(1) end)
    AttachLayerOverviewButton(section, slider, title, label, minVal, maxVal)
    return slider
end
function W.Segment(section, label, values, width)
    local x, y = NextRow(section, 48)
    local title = T.Font(section, "GameFontHighlightSmall", label or "", T.colors.text, "control")
    SetSearchText(title, label)
    title:SetPoint("TOPLEFT", x, y)
    local holder = PixelLayoutRegion(CreateFrame("Frame", nil, section))
    RegisterSearchObject(holder, label, "segment", { anchor = title, values = values })
    holder:SetPoint("TOPLEFT", x, y - 24)
    holder:SetSize(width or 360, 24)
    holder._msuf2ControlKind = "segment"
    holder._msuf2Title = title
    holder.buttons = {}
    holder.values = values or {}
    local count = #holder.values
    local gap = 8
    local bw = count > 0 and math.floor(((width or 360) - gap * (count - 1)) / count) or 80
    for i = 1, count do
        local item = holder.values[i]
        local btn = T.Button(holder, item.text or tostring(item.value), bw, 24, { history = false })
        -- A Segment is one logical control. Its option buttons are visual
        -- parts and must not become duplicate catalog records.
        if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(btn, holder)
        else btn._msuf2ControlPartOf = holder end
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

--- Shared page-tab binder for cold Menu2 UI state; no combat/runtime path.
function W.SegmentTabs(ctx, parent, opts)
    opts = opts or {}
    local frames, allowed = opts.frames or {}, opts.allowed
    if not allowed then
        allowed = {}
        local values = opts.values or {}
        for i = 1, #values do allowed[values[i].value] = true end
    end
    local defaultTab = opts.defaultTab or opts.default or "main"
    local segment
    local function CurrentTab()
        local tab = opts.get and opts.get() or (opts.stateKey and M[opts.stateKey]) or defaultTab
        return allowed[tab] and tab or defaultTab
    end
    local function RefreshTabs()
        local tab = CurrentTab()
        for key, frame in pairs(frames) do
            if frame and frame.SetShown then frame:SetShown(key == tab) end
        end
        if segment and segment.SetValue then segment:SetValue(tab) end
        if opts.afterRefresh then opts.afterRefresh(tab) end
    end
    local function SetTab(tab)
        tab = allowed[tab] and tab or defaultTab
        if opts.set then opts.set(tab)
        elseif opts.stateKey then
            M.SetMenuStateValue(opts.stateKey, tab)
        end
        RefreshTabs()
        if opts.afterSet then opts.afterSet(tab) end
    end
    segment = W.Segment(parent, opts.label, opts.values, opts.width)
    W.MoveWidget(segment, parent, opts.x or 0, opts.y or 0, opts.width, opts.titleJustify or "LEFT")
    M.BindSegment(ctx, segment, CurrentTab, SetTab)
    M.TrackRefresh(ctx, RefreshTabs)
    return segment, RefreshTabs, CurrentTab, SetTab
end
local function TextInputEscape(self)
    self._msuf2SkipBlurCommit = true
    if self._msuf2EditStartText ~= nil then self:SetText(self._msuf2EditStartText) end
    self:ClearFocus()
    self._msuf2SkipBlurCommit = nil
end
local function TextInputEnter(self)
    self._msuf2SkipBlurCommit = true
    if self._msuf2OnCommit then self._msuf2OnCommit(self:GetText() or "") end
    self:ClearFocus()
    self._msuf2SkipBlurCommit = nil
end
local function TextInputBlur(self)
    if self._msuf2CommitOnBlur and not self._msuf2SkipBlurCommit and self._msuf2OnCommit
        and self:GetText() ~= self._msuf2EditStartText then
        self._msuf2OnCommit(self:GetText() or "")
    end
    self._msuf2EditStartText = nil
end
local function TextInputSetOnValueCommitted(self, fn) self._msuf2OnCommit = fn end

--- Text inputs commit on Enter or focus loss; callers attach the actual profile
--- write through SetOnValueCommitted.
function W.TextInput(section, label, width)
    local x, y = NextRow(section, 48)
    width = width or 260
    local title = T.Font(section, "GameFontHighlightSmall", label or "", T.colors.text, "control")
    SetSearchText(title, label)
    title:SetPoint("TOPLEFT", x, y)
    local edit = PixelLayoutRegion(CreateFrame("EditBox", nil, section, "InputBoxTemplate"))
    edit._msuf2Title = title
    edit._msuf2ControlKind = "textinput"
    RegisterSearchObject(edit, label, "textinput", { anchor = title })
    edit:SetPoint("TOPLEFT", x, y - 24)
    edit:SetSize(width, 24)
    edit:SetAutoFocus(false)
    edit:SetJustifyH("LEFT")
    edit:SetMaxLetters(200000)
    T.SkinEditBox(edit)
    edit.SetOnValueCommitted = TextInputSetOnValueCommitted
    edit:SetScript("OnEscapePressed", TextInputEscape)
    edit:SetScript("OnEnterPressed", TextInputEnter)
    edit:SetScript("OnEditFocusGained", function(self) self._msuf2EditStartText = self:GetText() end)
    edit:SetScript("OnEditFocusLost", TextInputBlur)
    return edit
end
