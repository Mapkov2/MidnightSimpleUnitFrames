local _, MSUF = ...
local M = MSUF.MSUF2
local T = M.Theme
local FILE = "Shell/Menu2/MSUF_Menu2_Theme_Widgets.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
local PixelLayoutLeaf = MSUF.Require("PreparePixelLayoutLeaf", FILE, MSUF.Util)
local WL, MenuSkin, Tr = M.WordList, MSUF.MenuSkin, M.Tr
local Template, ShadeColor = T.Template, T.ShadeColor
local ApplyTextureGradient, SetFillGradient = T.ApplyTextureGradient, T.SetFillGradient
local surface = T._Surface
local SetTextureColorCached, ShadeColorInto = surface.SetTextureColorCached, surface.ShadeColorInto
local DynamicGradientFromColor = surface.DynamicGradientFromColor

local function CollapseHintLearned()
    local state = M.collapseHintClickState
    if type(state) ~= "table" then state = M.GetPersistentMenuStateTable("collapseHintClickState") end
    return (tonumber(state and state.total) or 0) >= (tonumber(T.collapseHintClickHideThreshold) or 8)
end
function T.ApplyCollapseRotation(chevron, open, immediate)
    local widgets = M.Widgets
    if widgets and widgets.AnimateDisclosure then
        widgets.AnimateDisclosure(chevron, open, immediate)
    elseif chevron.SetRotation then
        chevron:SetRotation(open and (math.pi * 0.5) or 0)
    end
end
function T.ApplyCollapseVisual(chevron, hint, open, immediate)
    open = open and true or false
    if chevron then
        T.ApplyCollapseRotation(chevron, open, immediate)
        local c = open and T.colors.accent or T.colors.accent2
        local a = open and 0.96 or 0.90
        local chevronKey = tostring(open) .. "\030" .. tostring(c[1]) .. "\030" .. tostring(c[2]) .. "\030" .. tostring(c[3]) .. "\030" .. tostring(a)
        if chevron._msuf2CollapseVisualKey ~= chevronKey then
            chevron._msuf2CollapseVisualKey = chevronKey
            if chevron.SetVertexColor then chevron:SetVertexColor(c[1], c[2], c[3], a) end
        end
    end
    if hint and hint.SetText then
        local learned = CollapseHintLearned()
        local text = (open or hint._msuf2SuppressCollapseHint or learned) and "" or Tr("click to expand")
        local c = T.colors.dim
        local hintKey = text .. "\030" .. tostring(c[1]) .. "\030" .. tostring(c[2]) .. "\030" .. tostring(c[3]) .. "\030" .. "0.74"
        if hint._msuf2CollapseVisualKey ~= hintKey then
            hint._msuf2CollapseVisualKey = hintKey
            T.SetTranslatedText(hint, text)
            if hint.SetTextColor then hint:SetTextColor(c[1], c[2], c[3], 0.74) end
        end
    end
end
-- Fades out and hides a native art region (nil is ignored).
local function HideNativeArt(region)
    if not region then return end
    if region.SetAlpha then region:SetAlpha(0) end
    if region.Hide then region:Hide() end
end
local function IsTextureRegion(region)
    if not region then return false end
    if region.IsObjectType then return region:IsObjectType("Texture") and true or false end
    return region.GetObjectType and region:GetObjectType() == "Texture"
end
-- Blizzard templates name their parts <frameName><suffix>; the name is known only at run time.
local function NamedPart(frame, suffix)
    local name = frame.GetName and frame:GetName()
    return name and _G[name .. suffix] or nil
end
local SLIDER_STYLED_TEXTURE_KEYS = { "_msufTrack", "_msufTrackTop", "_msufTrackBottom", "_msufFill", "_msufFillGlow", "_msuf2Thumb",
    "_msufPeelTrack", "_msufPeelTrackFill" }
local SLIDER_NATIVE_SUFFIXES = WL "Left Middle Right Text Low High"
local function HideNativeSliderParts(slider)
    if not slider then return end
    if slider._msuf2NativeSliderPartsHidden then return end
    local thumb = slider.GetThumbTexture and slider:GetThumbTexture()
    local keep = {}
    local function Keep(region)
        if region then keep[region] = true end
    end
    Keep(thumb)
    for i = 1, #SLIDER_STYLED_TEXTURE_KEYS do Keep(slider[SLIDER_STYLED_TEXTURE_KEYS[i]]) end
    if slider.GetRegions then
        local regions = { slider:GetRegions() }
        for i = 1, #regions do
            local region = regions[i]
            if IsTextureRegion(region) and not keep[region] then HideNativeArt(region) end
        end
    end
    for _, suffix in ipairs(SLIDER_NATIVE_SUFFIXES) do HideNativeArt(NamedPart(slider, suffix)) end
    slider._msuf2NativeSliderPartsHidden = true
end
-- Scratch colors for StyleSlider's gradients (ApplyTextureGradient copies the
-- components into the texture's cache fields and keeps no reference) and the
-- visual-state signature compared against the last paint.
local SLIDER_SCRATCH = { base = { 0, 0, 0, 1 }, from = { 0, 0, 0, 1 }, to = { 0, 0, 0, 1 }, signature = {} }
local function SliderTexture(slider, key, layer, subLevel, height)
    local tex = PixelLayoutLeaf(slider:CreateTexture(nil, layer, nil, subLevel))
    tex:SetHeight(height)
    slider[key] = tex
    return tex
end
local function SliderValuePercent(slider)
    if not (slider and slider.GetMinMaxValues and slider.GetValue) then return 0 end
    local minV, maxV = slider:GetMinMaxValues()
    local span = (tonumber(maxV) or 0) - (tonumber(minV) or 0)
    if span <= 0 then return 0 end
    local pct = ((tonumber(slider:GetValue()) or 0) - (tonumber(minV) or 0)) / span
    if pct < 0 then return 0 end
    if pct > 1 then return 1 end
    return pct
end
-- Cursor-drag sliders own the whole press; collapse the native thumb so the
-- engine's thumb-grab drag can't fight the cursor-follow OnUpdate.
local function CollapseNativeThumb(slider, nativeThumb)
    local hit = slider._msuf2CursorDrag and 1 or 18
    if nativeThumb.SetSize then nativeThumb:SetSize(hit, hit) end
    if nativeThumb.SetAlpha then nativeThumb:SetAlpha(0.001) end
    if nativeThumb.Show then nativeThumb:Show() end
end
local function UpdateSliderThumb(slider)
    local thumb = slider and slider._msuf2Thumb
    if not thumb then return end
    local nativeThumb = slider.GetThumbTexture and slider:GetThumbTexture()
    if nativeThumb and nativeThumb ~= thumb then
        -- CollapseNativeThumb inline: this runs on every value change.
        local hit = slider._msuf2CursorDrag and 1 or 18
        if nativeThumb.SetSize then nativeThumb:SetSize(hit, hit) end
        if nativeThumb.SetAlpha then nativeThumb:SetAlpha(0.001) end
        if nativeThumb.Show then nativeThumb:Show() end
    end
    local width = (slider.GetWidth and slider:GetWidth()) or 0
    local travel = math.max(1, width - 2)
    local x = 1 + travel * SliderValuePercent(slider)
    thumb:ClearAllPoints()
    thumb:SetPoint("CENTER", slider, "LEFT", x, 0)
    if thumb.Show then thumb:Show() end
end
local SLIDER_STYLE_HOOKS = {
    OnEnter = function(self)
        self._msuf2SliderHovered = true
        T.StyleSlider(self)
    end,
    OnLeave = function(self)
        self._msuf2SliderHovered = nil
        T.StyleSlider(self)
    end,
    OnMouseDown = function(self)
        self._msuf2SliderActive = true
        T.StyleSlider(self)
    end,
    OnMouseUp = function(self)
        self._msuf2SliderActive = nil
        T.StyleSlider(self)
    end,
    OnDisable = function(self)
        self._msuf2SliderActive = nil
        self._msuf2SliderHovered = nil
        T.StyleSlider(self)
    end,
    OnEnable = function(self) T.StyleSlider(self) end,
    OnValueChanged = function(self) if self._msuf2UpdateThumb then self:_msuf2UpdateThumb() end end,
    OnSizeChanged = function(self)
        if self._msuf2UpdateFill then self:_msuf2UpdateFill() end
        if self._msuf2UpdateThumb then self:_msuf2UpdateThumb() end
    end,
}
function T.StyleSlider(slider)
    MenuSkin.TrackPaint(slider, T.StyleSlider)
    if not slider then return end
    slider.__msufPeelSliderSkinned = true
    slider._msuf2SliderStyled = true
    if slider.SetOrientation then slider:SetOrientation("HORIZONTAL") end
    if slider.SetThumbTexture and slider.GetThumbTexture and not slider:GetThumbTexture() then PixelLayoutRegion(slider, "SetThumbTexture", T.media.sliderThumb
        or "Interface\\Buttons\\WHITE8X8") end
    HideNativeSliderParts(slider)
    if not slider._msufTrack and slider.CreateTexture then
        local track = SliderTexture(slider, "_msufTrack", "BACKGROUND", 1, 8)
        track:SetPoint("LEFT", slider, "LEFT", 0, 0)
        track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
        local top = SliderTexture(slider, "_msufTrackTop", "BORDER", 1, 1)
        top:SetPoint("LEFT", track, "LEFT", 0, 0)
        top:SetPoint("RIGHT", track, "RIGHT", 0, 0)
        top:SetPoint("TOP", track, "TOP", 0, 0)
        local bottom = SliderTexture(slider, "_msufTrackBottom", "BORDER", 1, 1)
        bottom:SetPoint("LEFT", track, "LEFT", 0, 0)
        bottom:SetPoint("RIGHT", track, "RIGHT", 0, 0)
        bottom:SetPoint("BOTTOM", track, "BOTTOM", 0, 0)
        local fill = SliderTexture(slider, "_msufFill", "ARTWORK", 1, 4)
        fill:SetPoint("LEFT", slider, "LEFT", 1, 0)
        local glow = SliderTexture(slider, "_msufFillGlow", "OVERLAY", 1, 8)
        glow:SetPoint("LEFT", fill, "LEFT", 0, 0)
        glow:SetPoint("RIGHT", fill, "RIGHT", 0, 0)
    end
    if not slider._msuf2Thumb and slider.CreateTexture then
        local thumb = PixelLayoutLeaf(slider:CreateTexture(nil, "OVERLAY", nil, 4))
        slider._msuf2Thumb = thumb
    end
    slider._msuf2UpdateThumb = UpdateSliderThumb
    if slider.HookScript and not slider._msuf2SliderStyleHooks then
        slider._msuf2SliderStyleHooks = true
        for script, handler in pairs(SLIDER_STYLE_HOOKS) do slider:HookScript(script, handler) end
    end
    local enabled = not (slider.IsEnabled and not slider:IsEnabled())
    local hovered = slider._msuf2SliderHovered and true or false
    local active = enabled and slider._msuf2SliderActive and true or false
    local alpha = enabled and 1 or 0.58
    local accent = T.colors.accent
    local edge = T.colors.border or T.colors.borderSoft
    local thumbMedia = T.media.sliderThumb or "Interface\\Buttons\\WHITE8X8"
    -- The visual state is skipped when it matches the last paint. Setting
    -- _msuf2SliderVisualReady to nil (the skin does) forces a repaint.
    local signature = SLIDER_SCRATCH.signature
    signature[1], signature[2], signature[3] = enabled, hovered, active
    signature[4], signature[5], signature[6] = accent[1], accent[2], accent[3]
    signature[7], signature[8], signature[9], signature[10] = edge[1], edge[2], edge[3], thumbMedia
    local painted = slider._msuf2SliderVisual
    local unchanged = painted ~= nil and slider._msuf2SliderVisualReady
    for i = 1, unchanged and 10 or 0 do
        if painted[i] ~= signature[i] then unchanged = false end
    end
    if unchanged then
        UpdateSliderThumb(slider)
        return
    end
    painted = painted or {}
    slider._msuf2SliderVisual = painted
    for i = 1, 10 do painted[i] = signature[i] end
    slider._msuf2SliderVisualReady = true
    if slider._msufTrack then
        local surface = T.colors.coreSurface or { 0.014, 0.038, 0.072, 1 }
        local trackBase = SLIDER_SCRATCH.base
        trackBase[1] = surface[1] * (active and 1.45 or hovered and 1.30 or 1.18)
        trackBase[2] = surface[2] * (active and 1.42 or hovered and 1.28 or 1.16)
        trackBase[3] = surface[3] * (active and 1.36 or hovered and 1.22 or 1.12)
        trackBase[4] = 0.98 * alpha
        -- The gradient replaces the whole texture, so no flat color goes first:
        -- it would also flip the texture cache between flat and gradient and
        -- repaint both on every hover change.
        ApplyTextureGradient(slider._msufTrack, "VERTICAL", ShadeColorInto(SLIDER_SCRATCH.from, trackBase, 0.10, 1),
            ShadeColorInto(SLIDER_SCRATCH.to, trackBase, -0.18, 1), false)
        if slider._msufTrack.Show then slider._msufTrack:Show() end
    end
    if slider._msufTrackTop then
        SetTextureColorCached(slider._msufTrackTop, edge[1], edge[2], edge[3], (active and 1.00 or hovered and 0.94 or 0.74) * alpha)
        slider._msufTrackTop:Show()
    end
    if slider._msufTrackBottom then
        SetTextureColorCached(slider._msufTrackBottom, edge[1], edge[2], edge[3], (active and 0.62 or hovered and 0.46 or 0.40) * alpha)
        slider._msufTrackBottom:Show()
    end
    if slider._msufFill then
        local fillAlpha = (active and 1.00 or hovered and 0.96 or 0.86) * alpha
        local from, to = SLIDER_SCRATCH.from, SLIDER_SCRATCH.to
        from[1], from[2], from[3], from[4] = math.min(accent[1] * 1.24, 1), math.min(accent[2] * 1.14, 1),
            math.min(accent[3] * 1.10, 1), fillAlpha
        to[1], to[2], to[3], to[4] = accent[1] * 0.72, accent[2] * 0.82, accent[3] * 0.90, fillAlpha * 0.88
        ApplyTextureGradient(slider._msufFill, "HORIZONTAL", from, to, false)
        if slider._msufFill.Show then slider._msufFill:Show() end
    end
    if slider._msufFillGlow then
        SetTextureColorCached(slider._msufFillGlow, accent[1], accent[2], accent[3], (active and 0.30 or hovered and 0.20 or 0.12) * alpha)
        slider._msufFillGlow:Show()
    end
    local nativeThumb = slider.GetThumbTexture and slider:GetThumbTexture()
    if nativeThumb then CollapseNativeThumb(slider, nativeThumb) end
    local thumb = slider._msuf2Thumb
    if thumb then
        thumb:SetTexture(thumbMedia)
        thumb:SetTexCoord(0, 1, 0, 1)
        thumb:SetSize(active and 20 or (hovered and 19 or 18), active and 20 or (hovered and 19 or 18))
        if thumb.SetVertexColor then
            local mul = active and 1.12 or hovered and 1.06 or 1
            thumb:SetVertexColor(math.min(accent[1] * mul, 1), math.min(accent[2] * mul, 1), math.min(accent[3] * mul, 1), alpha)
        end
        if thumb.SetAlpha then thumb:SetAlpha(alpha) end
        UpdateSliderThumb(slider)
    end
end
local CHECKBOX_NATIVE_GETTERS = WL "GetNormalTexture GetPushedTexture GetHighlightTexture GetDisabledTexture"
function T.StyleCheckmark(checkButton)
    if not checkButton then return end
    MenuSkin.TrackPaint(checkButton, T.StyleCheckmark)
    local function HideQuietCheckboxNative()
        if not checkButton._msuf2QuietCheckBox then return end
        for _, getter in ipairs(CHECKBOX_NATIVE_GETTERS) do
            local get = checkButton[getter]
            HideNativeArt(get and get(checkButton))
        end
    end
    if not checkButton._msuf2NativeCheckStyled then
        checkButton._msuf2NativeCheckStyled = true
        if checkButton.SetHitRectInsets then checkButton:SetHitRectInsets(0, 0, 0, 0) end
        local buttonSize = checkButton._msuf2QuietCheckBox and 28 or 24
        checkButton:SetSize(buttonSize, buttonSize)
        if checkButton.text then
            checkButton.text:ClearAllPoints()
            checkButton.text:SetPoint("LEFT", checkButton, "RIGHT", checkButton._msuf2QuietCheckBox and 8 or 4, 0)
            checkButton.text:SetJustifyH("LEFT")
        end
    end
    local function ApplyCheckTexture()
        HideQuietCheckboxNative()
        local tick = (checkButton._msuf2QuietCheckBox and T.media.checkTickMedium) or T.media.checkTick
        if checkButton.SetCheckedTexture then checkButton:SetCheckedTexture(tick) end
        if checkButton.SetDisabledCheckedTexture then checkButton:SetDisabledCheckedTexture(tick) end
        local check = checkButton.GetCheckedTexture and checkButton:GetCheckedTexture()
        if not check then check = NamedPart(checkButton, "Check") end
        local disabledCheck = checkButton.GetDisabledCheckedTexture and checkButton:GetDisabledCheckedTexture()
        if not disabledCheck then disabledCheck = NamedPart(checkButton, "DisabledCheck") end
        local function StyleTexture(texture)
            if not (texture and texture.SetTexture) then return end
            local h = (checkButton.GetHeight and checkButton:GetHeight()) or 24
            local sz = checkButton._msuf2QuietCheckBox and 15 or math.floor(h * 0.8 + 0.5)
            if sz < 11 then sz = 11 end
            texture:SetTexture(tick)
            texture:SetTexCoord(0, 1, 0, 1)
            if texture.SetBlendMode then texture:SetBlendMode("BLEND") end
            if texture.ClearAllPoints then
                texture:ClearAllPoints()
                texture:SetPoint("CENTER", checkButton, "CENTER", 0, 0)
            end
            if texture.SetSize then texture:SetSize(sz, sz) end
            local checked = checkButton.GetChecked and checkButton:GetChecked()
            if texture.SetVertexColor then texture:SetVertexColor(1, 1, 1, checked and 1 or 0) end
            if texture.SetAlpha then texture:SetAlpha(checked and 1 or 0) end
            if checked then
                if texture.Show then texture:Show() end
            elseif texture.Hide then
                texture:Hide()
            end
        end
        StyleTexture(check)
        StyleTexture(disabledCheck)
    end
    ApplyCheckTexture()
    HideQuietCheckboxNative()
end
function T.Panel(parent, name, bg, border)
    local f = PixelLayoutRegion(CreateFrame("Frame", name, parent, Template()))
    T.ApplyBackdrop(f, bg or T.colors.panel, border or T.colors.borderSoft)
    T.ApplyGradient(f, DynamicGradientFromColor(bg or T.colors.panel), { key = "_msuf2MaterialGradient" })
    return f
end
-- Top, bottom, left and right edge lines: both anchor points, size setter and thickness.
local RECT_EDGE_SPECS = { { "TOPLEFT", "TOPRIGHT", "SetHeight", 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", "SetHeight", 1 },
    { "TOPLEFT", "BOTTOMLEFT", "SetWidth", 1 }, { "TOPRIGHT", "BOTTOMRIGHT", "SetWidth", 1 } }
local EDIT_BOX_NATIVE_SUFFIXES = WL "Left Right Middle Mid"
local function HideNativeEditBoxArt(editBox)
    for _, suffix in ipairs(EDIT_BOX_NATIVE_SUFFIXES) do
        HideNativeArt(editBox[suffix] or NamedPart(editBox, suffix))
    end
end
function T.SkinEditBox(editBox)
    if not editBox or editBox._msuf2EditSkinned then return editBox end
    editBox._msuf2EditSkinned = true
    HideNativeEditBoxArt(editBox)
    local fontString = editBox.GetFontString and editBox:GetFontString() or nil
    if editBox.GetRegions then
        local regions = { editBox:GetRegions() }
        for i = 1, #regions do
            local region = regions[i]
            if IsTextureRegion(region) and region ~= fontString then HideNativeArt(region) end
        end
    end
    local shadow = T.colors.coreShadow or { 0.006, 0.016, 0.032 }
    local rim = T.colors.borderSoft or T.colors.coreRim or { 0.070, 0.260, 0.390 }
    T.ApplyBackdrop(editBox, { shadow[1], shadow[2], shadow[3], 0.760 }, { rim[1], rim[2], rim[3], 0.56 })
    if editBox.CreateTexture then
        local bg = PixelLayoutLeaf(editBox:CreateTexture(nil, "BACKGROUND", nil, -6))
        bg:SetPoint("TOPLEFT", editBox, "TOPLEFT", 0, 0)
        bg:SetPoint("BOTTOMRIGHT", editBox, "BOTTOMRIGHT", 0, 0)
        editBox._msuf2EditBg = bg
        local edges = {}
        for i = 1, #RECT_EDGE_SPECS do
            local spec = RECT_EDGE_SPECS[i]
            local edge = PixelLayoutLeaf(editBox:CreateTexture(nil, "OVERLAY", nil, 1))
            edge:SetPoint(spec[1], editBox, spec[1], 0, 0)
            edge:SetPoint(spec[2], editBox, spec[2], 0, 0)
            edge[spec[3]](edge, spec[4])
            edges[i] = edge
        end
        editBox._msuf2EditEdges = edges
    end
    local function PaintEditBox(self, focused)
        HideNativeEditBoxArt(self)
        if MenuSkin.Surface(self, "input", PaintEditBox, focused, nil, 7) then return end
        local enabled = not (self.IsEnabled and not self:IsEnabled())
        local alpha = enabled and 1 or 0.60
        local roundedFill = self._msuf2RoundedEditFill
        local roundedEdge = self._msuf2RoundedEditEdge
        local base = T.colors.coreShadow or { 0.006, 0.016, 0.032 }
        local c = focused and T.colors.accent or T.colors.borderSoft
        local a = (focused and 0.98 or 0.88) * alpha
        local edges = self._msuf2EditEdges
        if roundedFill and roundedEdge then
            local bg = self._msuf2RoundedEditColor or { base[1], base[2], base[3], 0.98 }
            SetFillGradient(roundedFill, { bg[1] or 0.018, bg[2] or 0.024, bg[3] or 0.050, (bg[4] or 0.98) * alpha }, 0.10, -0.16)
            roundedEdge:SetVertexColor(c[1], c[2], c[3], a)
            if self.SetBackdropColor then self:SetBackdropColor(0, 0, 0, 0) end
            if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0, 0, 0, 0) end
            if self._msuf2EditBg and self._msuf2EditBg.Hide then self._msuf2EditBg:Hide() end
            if edges then
                for i = 1, #edges do
                    if edges[i].Hide then edges[i]:Hide() end
                end
            end
            return
        end
        if self._msuf2EditBg then
            local bg = { base[1], base[2], base[3], 0.98 * alpha }
            ApplyTextureGradient(self._msuf2EditBg, "VERTICAL", ShadeColor(bg, 0.10, 1), ShadeColor(bg, -0.16, 1), false)
        end
        if edges then
            for i = 1, #edges do
                edges[i]:SetColorTexture(c[1], c[2], c[3], a)
            end
        end
    end
    editBox._msuf2PaintEditBox = PaintEditBox
    local fs = fontString
    T.StyleFontString(fs, T.colors.text, 1)
    local function OnFocusChange(self, focused)
        PaintEditBox(self, focused)
        if self.SetBackdropBorderColor and not self._msuf2RoundedEditFill and not MenuSkin.Owns(self) then
            local border = focused and T.colors.accent or T.colors.borderSoft
            self:SetBackdropBorderColor(border[1], border[2], border[3], focused and 0.95 or border[4] or 1)
        end
    end
    editBox:HookScript("OnEditFocusGained", function(self) OnFocusChange(self, true) end)
    editBox:HookScript("OnEditFocusLost", function(self) OnFocusChange(self, false) end)
    editBox:HookScript("OnEnable", function(self) PaintEditBox(self, self.HasFocus and self:HasFocus()) end)
    editBox:HookScript("OnDisable", function(self) PaintEditBox(self, false) end)
    editBox:HookScript("OnShow", function(self) PaintEditBox(self, self.HasFocus and self:HasFocus()) end)
    PaintEditBox(editBox, false)
    return editBox
end
-- Release-highlight sentences are links, so they use an intentionally distinct
-- yellow treatment instead of the general blue interaction palette. The hover
-- outline follows the button's measured multiline height.
function T.StyleFeatureLink(button, label)
    if not (button and label and button.CreateTexture) then return nil end
    local base = T.colors.accent2 or T.colors.warning or { 0.95, 0.72, 0.18, 1 }
    local hot = { 1.00, 0.84, 0.30, 1 }
    local fill = PixelLayoutLeaf(button:CreateTexture(nil, "BACKGROUND"))
    fill:SetPoint("TOPLEFT", button, "TOPLEFT", -5, 3)
    fill:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 5, -3)
    fill:SetColorTexture(base[1], base[2], base[3], 0.09)

    local edges = {}
    for index = 1, 4 do
        local edge = PixelLayoutLeaf(button:CreateTexture(nil, "OVERLAY", nil, 7))
        edge:SetColorTexture(base[1], base[2], base[3], 0.96)
        edges[index] = edge
    end
    -- Top, bottom, left and right edges, each outset 5 wide and 3 high.
    for index = 1, 4 do
        local spec = RECT_EDGE_SPECS[index]
        local edge, first, second = edges[index], spec[1], spec[2]
        edge:SetPoint(first, button, first, first:find("LEFT") and -5 or 5, first:find("TOP") and 3 or -3)
        edge:SetPoint(second, button, second, second:find("LEFT") and -5 or 5, second:find("TOP") and 3 or -3)
        edge[spec[3]](edge, spec[4])
    end

    local function Paint(hovered)
        local color = hovered and hot or base
        label:SetTextColor(color[1], color[2], color[3], color[4] or 1)
        if hovered then
            fill:Show()
            for index = 1, #edges do edges[index]:Show() end
        else
            fill:Hide()
            for index = 1, #edges do edges[index]:Hide() end
        end
    end
    button._msuf2ChangelogLinkOutline = edges
    button._msuf2PaintFeatureLink = Paint
    Paint(false)
    return Paint
end

T.IsTextureRegion = IsTextureRegion
