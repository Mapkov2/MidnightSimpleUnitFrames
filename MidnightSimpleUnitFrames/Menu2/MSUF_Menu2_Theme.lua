local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local T = M.Theme or {}
M.Theme = T

local ADDON = (type(addonName) == "string" and addonName ~= "" and addonName) or "MidnightSimpleUnitFrames"
local ADDON_PATH = "Interface\\AddOns\\" .. ADDON .. "\\"
T.media = T.media or {
    superellipse = ADDON_PATH .. "Media\\superellipse.tga",
    checkTick = ADDON_PATH .. "Media\\msuf_check_tick_bold.tga",
    checkRim = ADDON_PATH .. "Media\\msuf_check_superellipse_hole.tga",
    dropdownChevron = ADDON_PATH .. "Media\\msuf_dropdown_chevron_down.tga",
    collapseArrow = "Interface\\ChatFrame\\ChatFrameExpandArrow",
    sliderThumb = ADDON_PATH .. "Media\\msuf_slider_thumb.tga",
    bgSmooth = ADDON_PATH .. "Media\\Bars\\Smoothv2.tga",
    bgCharcoal = ADDON_PATH .. "Media\\Bars\\Charcoal.tga",
    logo = ADDON_PATH .. "Media\\MSUF_MinimapIcon.tga",
    navIcons = ADDON_PATH .. "Media\\msuf_nav_icons",
}

T.colors = {
    bg = { 0.080, 0.090, 0.160, 0.980 },
    panel = { 0.080, 0.090, 0.160, 0.300 },
    panelNav = { 0.080, 0.090, 0.160, 0.400 },
    panel2 = { 0.065, 0.075, 0.140, 0.950 },
    header = { 0.080, 0.090, 0.160, 0.300 },
    border = { 0.120, 0.140, 0.280, 0.800 },
    borderSoft = { 0.120, 0.140, 0.260, 0.400 },
    cardBorder = { 0.120, 0.140, 0.260, 0.400 },
    text = { 0.840, 0.880, 1.000, 1.00 },
    title = { 0.800, 0.880, 1.000, 1.00 },
    muted = { 0.700, 0.745, 0.860, 0.92 },
    dim = { 0.570, 0.650, 0.800, 0.90 },
    accent = { 0.220, 0.780, 0.940, 1.00 },
    accent2 = { 0.965, 0.760, 0.150, 1.00 },
    danger = { 0.880, 0.280, 0.280, 1.00 },
    ok = { 0.240, 0.820, 0.460, 1.00 },
    pillBase = { 0.060, 0.070, 0.130, 0.88 },
    pillBaseSolid = { 0.060, 0.070, 0.130, 0.92 },
    pillHover = { 0.080, 0.090, 0.160, 0.95 },
    pillActive = { 0.120, 0.150, 0.320, 0.95 },
    pillEdge = { 0.150, 0.175, 0.330, 0.45 },
    pillEdgeButton = { 0.150, 0.175, 0.330, 0.60 },
    pillEdgeHover = { 0.140, 0.220, 0.600, 0.75 },
    pillEdgeActive = { 0.200, 0.340, 0.800, 0.85 },
    pillText = { 0.800, 0.880, 1.000, 0.94 },
    pillTextActive = { 0.920, 0.960, 1.000, 1.00 },
}

T.fontBump = T.fontBump or 1

T.navIconGrid = {
    home = { 0, 0 },
    uf_player = { 1, 0 }, uf_target = { 2, 0 }, uf_targettarget = { 3, 0 },
    uf_focus = { 4, 0 }, uf_boss = { 5, 0 }, uf_pet = { 6, 0 },
    opt_bars = { 7, 0 }, opt_fonts = { 0, 1 }, auras2 = { 1, 1 },
    opt_castbar = { 2, 1 }, opt_misc = { 3, 1 }, opt_colors = { 4, 1 },
    classpower = { 6, 1 }, gameplay = { 7, 1 },
    groupframes = { 0, 2 }, gf_layout = { 0, 2 }, gf_bars = { 0, 2 }, gf_auras = { 0, 2 }, gf_indicators = { 0, 2 },
    modules = { 1, 2 }, profiles = { 2, 2 },
}

T.navIconColors = {
    home = { 0.30, 0.60, 1.00 },
    uf_player = { 0.40, 0.78, 0.98 }, uf_target = { 0.40, 0.78, 0.98 }, uf_targettarget = { 0.40, 0.78, 0.98 },
    uf_focus = { 0.40, 0.78, 0.98 }, uf_boss = { 0.40, 0.78, 0.98 }, uf_pet = { 0.40, 0.78, 0.98 },
    opt_bars = { 0.88, 0.74, 0.36 }, opt_fonts = { 0.88, 0.74, 0.36 }, auras2 = { 0.88, 0.74, 0.36 },
    opt_castbar = { 0.88, 0.74, 0.36 }, opt_misc = { 0.88, 0.74, 0.36 }, opt_colors = { 0.88, 0.74, 0.36 },
    classpower = { 0.35, 0.82, 0.50 }, gameplay = { 0.72, 0.50, 0.92 },
    groupframes = { 0.45, 0.75, 0.88 }, gf_layout = { 0.45, 0.75, 0.88 }, gf_bars = { 0.45, 0.75, 0.88 },
    gf_auras = { 0.45, 0.75, 0.88 }, gf_indicators = { 0.45, 0.75, 0.88 },
    modules = { 0.40, 0.80, 0.75 }, profiles = { 0.90, 0.62, 0.30 },
}

local function Template()
    return _G.BackdropTemplateMixin and "BackdropTemplate" or nil
end
T.Template = Template

local function SetColor(tex, c)
    if tex and c then tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
end
T.SetColor = SetColor

local function SmoothTexture(tex)
    if not tex then return end
    if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
    if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
end

function T.StyleFontString(fs, color, bump)
    if not fs then return fs end
    local c = color or T.colors.text
    if fs.SetTextColor and c then fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0.70) end
    if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
    if fs.GetFont and fs.SetFont then
        local ok, font, size, flags = pcall(fs.GetFont, fs)
        if ok and font and size then
            if not fs._msuf2FontOriginal then
                fs._msuf2FontOriginal = { font = font, size = size, flags = flags }
            end
            local orig = fs._msuf2FontOriginal
            local nextSize = math.max(8, (tonumber(orig.size) or size) + (tonumber(bump) or T.fontBump or 0))
            pcall(fs.SetFont, fs, orig.font or font, nextSize, orig.flags or flags or "")
        end
    end
    return fs
end

function T.CreateSuperellipseLayers(frame, key, inset, fillLayer, borderLayer)
    if not (frame and frame.CreateTexture) then return nil, nil end
    key = key or "_msuf2SE"
    if frame[key .. "Fill"] and frame[key .. "Border"] then
        return frame[key .. "Fill"], frame[key .. "Border"]
    end

    inset = inset or 1
    fillLayer = fillLayer or "BACKGROUND"
    borderLayer = borderLayer or "BORDER"

    local h = (frame.GetHeight and frame:GetHeight()) or 22
    local capW = math.max(4, math.floor(h * 0.5))

    local fill = {}
    fill.L = frame:CreateTexture(nil, fillLayer, nil, 0)
    fill.M = frame:CreateTexture(nil, fillLayer, nil, 0)
    fill.R = frame:CreateTexture(nil, fillLayer, nil, 0)
    fill.L:SetTexture(T.media.superellipse)
    fill.M:SetTexture(T.media.superellipse)
    fill.R:SetTexture(T.media.superellipse)
    SmoothTexture(fill.L)
    SmoothTexture(fill.M)
    SmoothTexture(fill.R)
    fill.L:SetTexCoord(0.00, 0.25, 0, 1)
    fill.M:SetTexCoord(0.25, 0.75, 0, 1)
    fill.R:SetTexCoord(0.75, 1.00, 0, 1)
    fill.L:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    fill.L:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset)
    fill.L:SetWidth(capW)
    fill.R:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
    fill.R:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    fill.R:SetWidth(capW)
    fill.M:SetPoint("TOPLEFT", fill.L, "TOPRIGHT")
    fill.M:SetPoint("BOTTOMRIGHT", fill.R, "BOTTOMLEFT")
    fill._parts = { fill.L, fill.M, fill.R }
    fill.SetVertexColor = function(self, r, g, b, a)
        for i = 1, #self._parts do
            self._parts[i]:SetVertexColor(r, g, b, a or 1)
        end
    end

    local border = {}
    border.L = frame:CreateTexture(nil, borderLayer, nil, -1)
    border.M = frame:CreateTexture(nil, borderLayer, nil, -1)
    border.R = frame:CreateTexture(nil, borderLayer, nil, -1)
    border.L:SetTexture(T.media.superellipse)
    border.M:SetTexture(T.media.superellipse)
    border.R:SetTexture(T.media.superellipse)
    SmoothTexture(border.L)
    SmoothTexture(border.M)
    SmoothTexture(border.R)
    border.L:SetTexCoord(0.00, 0.25, 0, 1)
    border.M:SetTexCoord(0.25, 0.75, 0, 1)
    border.R:SetTexCoord(0.75, 1.00, 0, 1)
    local function Layout()
        local w = (frame.GetWidth and frame:GetWidth()) or 120
        local h2 = (frame.GetHeight and frame:GetHeight()) or h
        local p = tonumber(inset) or 1
        local innerW = math.max(1, w - p * 2)
        local innerH = math.max(1, h2 - p * 2)
        local nextCapW = math.min(math.floor(innerH * 0.5 + 0.5), math.floor(innerW * 0.5))
        fill.L:ClearAllPoints()
        fill.M:ClearAllPoints()
        fill.R:ClearAllPoints()
        fill.L:SetPoint("TOPLEFT", frame, "TOPLEFT", p, -p)
        fill.L:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", p, p)
        fill.L:SetWidth(nextCapW)
        fill.R:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -p, -p)
        fill.R:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -p, p)
        fill.R:SetWidth(nextCapW)
        fill.M:SetPoint("TOPLEFT", fill.L, "TOPRIGHT", 0, 0)
        fill.M:SetPoint("BOTTOMRIGHT", fill.R, "BOTTOMLEFT", 0, 0)

        local bInset = math.max(1, p - 1)
        local borderInnerW = math.max(1, w - bInset * 2)
        local borderInnerH = math.max(1, h2 - bInset * 2)
        local borderCapW = math.min(math.floor(borderInnerH * 0.5 + 0.5), math.floor(borderInnerW * 0.5))
        border.L:ClearAllPoints()
        border.M:ClearAllPoints()
        border.R:ClearAllPoints()
        border.L:SetPoint("TOPLEFT", frame, "TOPLEFT", bInset, -bInset)
        border.L:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", bInset, bInset)
        border.L:SetWidth(borderCapW)
        border.R:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -bInset, -bInset)
        border.R:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -bInset, bInset)
        border.R:SetWidth(borderCapW)
        border.M:SetPoint("TOPLEFT", border.L, "TOPRIGHT", 0, 0)
        border.M:SetPoint("BOTTOMRIGHT", border.R, "BOTTOMLEFT", 0, 0)
    end
    Layout()
    if frame.HookScript and not frame[key .. "LayoutHooked"] then
        frame[key .. "LayoutHooked"] = true
        frame:HookScript("OnSizeChanged", Layout)
    end
    border._parts = { border.L, border.M, border.R }
    border.SetVertexColor = function(self, r, g, b, a)
        for i = 1, #self._parts do
            self._parts[i]:SetVertexColor(r, g, b, a or 1)
        end
    end

    frame[key .. "Fill"] = fill
    frame[key .. "Border"] = border
    return fill, border
end

function T.ApplyBackdrop(frame, bg, border)
    if not frame then return frame end
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        local b = bg or T.colors.panel
        local e = border or T.colors.borderSoft
        frame:SetBackdropColor(b[1], b[2], b[3], b[4] or 1)
        frame:SetBackdropBorderColor(e[1], e[2], e[3], e[4] or 1)
    else
        if not frame._msuf2Bg then
            local tex = frame:CreateTexture(nil, "BACKGROUND")
            tex:SetAllPoints()
            frame._msuf2Bg = tex
        end
        SetColor(frame._msuf2Bg, bg or T.colors.panel)
    end
    return frame
end

function T.ApplyCollapseVisual(chevron, hint, open)
    if chevron then
        if chevron.SetRotation then chevron:SetRotation(open and (math.pi * 0.5) or 0) end
        if chevron.SetVertexColor then
            if open then
                chevron:SetVertexColor(1.00, 0.55, 0.12, 1)
            else
                chevron:SetVertexColor(1.00, 0.82, 0.00, 1)
            end
        end
    end
    if hint and hint.SetText then
        hint:SetText(open and "" or "click to expand")
        if hint.SetTextColor then hint:SetTextColor(0.45, 0.52, 0.65, 1) end
    end
end

function T.ApplyMenuAtmosphere(frame, host, nav)
    if not frame or frame._msuf2AtmosphereApplied then return end
    frame._msuf2AtmosphereApplied = true
    host = host or frame

    local wash = host:CreateTexture(nil, "BACKGROUND", nil, 1)
    wash:SetTexture(T.media.bgSmooth)
    wash:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    wash:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    wash:SetVertexColor(0.14, 0.08, 0.30, 0.10)

    local depth = host:CreateTexture(nil, "BACKGROUND", nil, 2)
    depth:SetTexture(T.media.bgSmooth)
    depth:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    depth:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    depth:SetTexCoord(0, 0, 1, 0, 0, 1, 1, 1)
    depth:SetVertexColor(0.08, 0.06, 0.20, 0.10)

    local grain = host:CreateTexture(nil, "BACKGROUND", nil, 3)
    grain:SetTexture(T.media.bgCharcoal)
    grain:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    grain:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    grain:SetVertexColor(0.10, 0.08, 0.20, 0.08)

    local logo = host:CreateTexture(nil, "BORDER", nil, 0)
    logo:SetTexture(T.media.logo)
    logo:SetSize(120, 120)
    logo:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -12, 12)
    logo:SetVertexColor(0.30, 0.22, 0.55, 0.035)
    if logo.SetBlendMode then logo:SetBlendMode("ADD") end

    if nav then
        local navWash = nav:CreateTexture(nil, "BORDER", nil, 1)
        navWash:SetTexture(T.media.bgSmooth)
        navWash:SetPoint("TOPLEFT", nav, "TOPLEFT", 3, -3)
        navWash:SetPoint("BOTTOMRIGHT", nav, "BOTTOMRIGHT", -3, 3)
        navWash:SetTexCoord(0, 0, 1, 0, 0, 1, 1, 1)
        navWash:SetVertexColor(0.10, 0.06, 0.24, 0.12)
    end
end

function T.AttachNavIcon(btn, navKey, isChild)
    if not (btn and btn.CreateTexture and navKey) then return end
    local grid = T.navIconGrid and T.navIconGrid[navKey]
    local color = T.navIconColors and T.navIconColors[navKey]
    if not (grid and color) then return end
    local icon = btn:CreateTexture(nil, "ARTWORK", nil, 3)
    icon:SetSize(14, 14)
    icon:SetTexture(T.media.navIcons)
    local col, row = grid[1], grid[2]
    icon:SetTexCoord(col / 8, (col + 1) / 8, row / 8, (row + 1) / 8)
    icon:SetVertexColor(color[1], color[2], color[3], 0.50)
    icon:SetPoint("LEFT", btn, "LEFT", isChild and 8 or 10, 0)
    btn._msuf2NavIcon = icon
    btn._msuf2NavIconColor = color
    local stripe = btn:CreateTexture(nil, "ARTWORK", nil, 6)
    stripe:SetTexture("Interface\\Buttons\\WHITE8X8")
    stripe:SetWidth(3)
    stripe:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -4)
    stripe:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 4)
    stripe:SetColorTexture(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 1.00)
    stripe:Hide()
    btn._msuf2NavStripe = stripe
    if btn._msuf2Label then
        btn._msuf2Label:ClearAllPoints()
        btn._msuf2Label:SetPoint("LEFT", btn, "LEFT", isChild and 24 or 26, 0)
        btn._msuf2Label:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
        btn._msuf2Label:SetJustifyH("LEFT")
    end
end

function T.StyleSlider(slider)
    if not slider then return end
    local UI = ns and ns.UI
    local style = (_G and _G.MSUF_StyleSlider) or (ns and ns.MSUF_StyleSlider) or (UI and UI.StyleSlider)
    if type(style) == "function" then
        pcall(style, slider)
        return
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            local UI2 = ns and ns.UI
            local later = (_G and _G.MSUF_StyleSlider) or (ns and ns.MSUF_StyleSlider) or (UI2 and UI2.StyleSlider)
            if type(later) == "function" then pcall(later, slider) end
        end)
    end
end

function T.StyleCheckmark(checkButton)
    if not checkButton then return end
    local UI = ns and ns.UI
    local styleText = (_G and _G.MSUF_StyleToggleText) or (ns and ns.MSUF_StyleToggleText) or (UI and UI.StyleToggleText)
    if type(styleText) == "function" then pcall(styleText, checkButton) end

    if not checkButton._msuf2NativeCheckStyled then
        checkButton._msuf2NativeCheckStyled = true
        if checkButton.SetHitRectInsets then checkButton:SetHitRectInsets(0, 0, 0, 0) end
        checkButton:SetSize(24, 24)
        if checkButton.text then
            checkButton.text:ClearAllPoints()
            checkButton.text:SetPoint("LEFT", checkButton, "RIGHT", 4, 0)
            checkButton.text:SetJustifyH("LEFT")
        end
    end

    local function ApplyCheckTexture()
        local oldStyle = (_G and _G.MSUF_StyleCheckmark) or (ns and ns.MSUF_StyleCheckmark) or (UI and UI.StyleCheckmark)
        if type(oldStyle) == "function" then
            pcall(oldStyle, checkButton)
        end

        local check = checkButton.GetCheckedTexture and checkButton:GetCheckedTexture()
        if not check and checkButton.GetName and checkButton:GetName() then check = _G[checkButton:GetName() .. "Check"] end
        if check and check.SetTexture then
            local h = (checkButton.GetHeight and checkButton:GetHeight()) or 24
            local sz = math.floor(h * 0.8 + 0.5)
            if sz < 12 then sz = 12 end
            check:SetTexture(T.media.checkTick)
            check:SetTexCoord(0, 1, 0, 1)
            if check.SetBlendMode then check:SetBlendMode("BLEND") end
            if check.ClearAllPoints then
                check:ClearAllPoints()
                check:SetPoint("CENTER", checkButton, "CENTER", 0, 0)
            end
            if check.SetSize then check:SetSize(sz, sz) end
            if check.SetAlpha then check:SetAlpha(1) end
            if check.Show and checkButton.GetChecked and checkButton:GetChecked() then check:Show() end
        end
    end

    ApplyCheckTexture()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            local UI2 = ns and ns.UI
            local laterText = (_G and _G.MSUF_StyleToggleText) or (ns and ns.MSUF_StyleToggleText) or (UI2 and UI2.StyleToggleText)
            if type(laterText) == "function" then pcall(laterText, checkButton) end
            ApplyCheckTexture()
        end)
    end
end

function T.Panel(parent, name, bg, border)
    local f = CreateFrame("Frame", name, parent, Template())
    T.ApplyBackdrop(f, bg or T.colors.panel, border or T.colors.borderSoft)
    return f
end

function T.SkinEditBox(editBox)
    if not editBox or editBox._msuf2EditSkinned then return editBox end
    editBox._msuf2EditSkinned = true
    local name = editBox.GetName and editBox:GetName() or nil
    if name then
        for _, suffix in ipairs({ "Left", "Right", "Middle", "Mid" }) do
            local tex = _G[name .. suffix]
            if tex and tex.SetAlpha then tex:SetAlpha(0) end
        end
    end
    T.ApplyBackdrop(editBox, { 0.020, 0.024, 0.046, 0.96 }, T.colors.borderSoft)
    local fs = editBox.GetFontString and editBox:GetFontString() or nil
    T.StyleFontString(fs, T.colors.text, 1)
    editBox:HookScript("OnEditFocusGained", function(self)
        if self.SetBackdropBorderColor then
            self:SetBackdropBorderColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.95)
        end
    end)
    editBox:HookScript("OnEditFocusLost", function(self)
        if self.SetBackdropBorderColor then
            self:SetBackdropBorderColor(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], T.colors.borderSoft[4] or 1)
        end
    end)
    return editBox
end

function T.Font(parent, template, text, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetText(text or "")
    return T.StyleFontString(fs, color or T.colors.text, 1)
end

function T.StripButtonTextures(btn)
    if not btn then return end
    if btn.Left and btn.Left.Hide then btn.Left:Hide() end
    if btn.Middle and btn.Middle.Hide then btn.Middle:Hide() end
    if btn.Right and btn.Right.Hide then btn.Right:Hide() end
    if btn.GetNormalTexture and btn.SetNormalTexture then
        local tex = btn:GetNormalTexture()
        if tex and tex.SetAlpha then tex:SetAlpha(0) end
        pcall(btn.SetNormalTexture, btn, nil)
    end
    if btn.GetPushedTexture and btn.SetPushedTexture then
        local tex = btn:GetPushedTexture()
        if tex and tex.SetAlpha then tex:SetAlpha(0) end
        pcall(btn.SetPushedTexture, btn, nil)
    end
    if btn.GetHighlightTexture and btn.SetHighlightTexture then
        local tex = btn:GetHighlightTexture()
        if tex and tex.SetAlpha then tex:SetAlpha(0) end
        pcall(btn.SetHighlightTexture, btn, nil)
    end
    if btn.GetDisabledTexture and btn.SetDisabledTexture then
        local tex = btn:GetDisabledTexture()
        if tex and tex.SetAlpha then tex:SetAlpha(0) end
        pcall(btn.SetDisabledTexture, btn, nil)
    end
end

local function ButtonVisual(btn, active, hover)
    local c = T.colors
    local fill = btn._msuf2Fill
    local edge = btn._msuf2Edge
    local enabled = not (btn.IsEnabled and not btn:IsEnabled())
    if not enabled then
        fill:SetVertexColor(0.075, 0.080, 0.105, 0.55)
        edge:SetVertexColor(0.180, 0.210, 0.300, 0.45)
        btn._msuf2Label:SetTextColor(0.50, 0.52, 0.58, 0.95)
        return
    end
    if btn._msuf2Danger then
        if active or hover then
            fill:SetVertexColor(0.180, 0.040, 0.065, 0.97)
            edge:SetVertexColor(c.danger[1], c.danger[2], c.danger[3], 0.95)
        else
            fill:SetVertexColor(0.140, 0.030, 0.050, 0.94)
            edge:SetVertexColor(c.danger[1], c.danger[2], c.danger[3], 0.82)
        end
        btn._msuf2Label:SetTextColor(c.text[1], c.text[2], c.text[3], 1)
        return
    end
    if btn._msuf2Primary then
        if active or hover then
            fill:SetVertexColor(0.200, 0.640, 0.820, 0.99)
            edge:SetVertexColor(0.260, 0.830, 1.000, 0.90)
        else
            fill:SetVertexColor(0.160, 0.560, 0.720, 0.97)
            edge:SetVertexColor(0.220, 0.720, 0.940, 0.85)
        end
        btn._msuf2Label:SetTextColor(1, 1, 1, 1)
        return
    end
    if active then
        if btn._msuf2NavStripe then btn._msuf2NavStripe:Show() end
        local bg, br, tx = c.pillActive, c.pillEdgeActive, c.pillTextActive
        fill:SetVertexColor(bg[1], bg[2], bg[3], bg[4] or 1)
        edge:SetVertexColor(br[1], br[2], br[3], br[4] or 1)
        btn._msuf2Label:SetTextColor(tx[1], tx[2], tx[3], tx[4] or 1)
        if btn._msuf2NavIcon and btn._msuf2NavIconColor then
            local ic = btn._msuf2NavIconColor
            btn._msuf2NavIcon:SetVertexColor(ic[1], ic[2], ic[3], 1.00)
        end
    elseif hover then
        if btn._msuf2NavStripe then btn._msuf2NavStripe:Hide() end
        local bg, br = c.pillHover, c.pillEdgeHover
        fill:SetVertexColor(bg[1], bg[2], bg[3], bg[4] or 1)
        edge:SetVertexColor(br[1], br[2], br[3], br[4] or 1)
        btn._msuf2Label:SetTextColor(c.text[1], c.text[2], c.text[3], 1)
        if btn._msuf2NavIcon and btn._msuf2NavIconColor then
            local ic = btn._msuf2NavIconColor
            btn._msuf2NavIcon:SetVertexColor(ic[1], ic[2], ic[3], 0.85)
        end
    else
        if btn._msuf2NavStripe then btn._msuf2NavStripe:Hide() end
        local bg, br, tx = c.pillBase, c.pillEdge, c.pillText
        if btn._msuf2SolidPill then bg = c.pillBaseSolid end
        fill:SetVertexColor(bg[1], bg[2], bg[3], bg[4] or 1)
        edge:SetVertexColor(br[1], br[2], br[3], br[4] or 1)
        btn._msuf2Label:SetTextColor(tx[1], tx[2], tx[3], 0.95)
        if btn._msuf2NavIcon and btn._msuf2NavIconColor then
            local ic = btn._msuf2NavIconColor
            btn._msuf2NavIcon:SetVertexColor(ic[1], ic[2], ic[3], 0.50)
        end
    end
    if (not active) and btn._msuf2Override and edge then
        edge:SetVertexColor(0.96, 0.78, 0.24, 0.92)
        btn._msuf2Label:SetTextColor(1.00, 0.92, 0.72, 1)
    end
end

function T.Button(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 120, height or 24)

    local fill, edge = T.CreateSuperellipseLayers(btn, "_msuf2Btn", 2, "BACKGROUND", "BORDER")
    btn._msuf2Fill = fill
    btn._msuf2Edge = edge

    local label = T.Font(btn, "GameFontHighlightSmall", text or "", T.colors.muted)
    label:SetPoint("LEFT", 10, 0)
    label:SetPoint("RIGHT", -10, 0)
    label:SetJustifyH("LEFT")
    btn._msuf2Label = label

    btn.SetText = function(self, value)
        self._msuf2Label:SetText(value or "")
    end
    btn.GetText = function(self)
        return self._msuf2Label:GetText()
    end
    btn.SetActive = function(self, active)
        self._msuf2Active = active and true or false
        ButtonVisual(self, self._msuf2Active, self._msuf2Hover)
    end
    btn.SetEnabled = function(self, enabled)
        if enabled then
            if self.Enable then self:Enable() end
        else
            if self.Disable then self:Disable() end
        end
        ButtonVisual(self, self._msuf2Active, self._msuf2Hover)
    end

    btn:SetScript("OnEnter", function(self)
        self._msuf2Hover = true
        ButtonVisual(self, self._msuf2Active, true)
    end)
    btn:SetScript("OnLeave", function(self)
        self._msuf2Hover = nil
        ButtonVisual(self, self._msuf2Active, false)
    end)
    btn:SetScript("OnEnable", function(self)
        ButtonVisual(self, self._msuf2Active, self._msuf2Hover)
    end)
    btn:SetScript("OnDisable", function(self)
        ButtonVisual(self, self._msuf2Active, self._msuf2Hover)
    end)
    ButtonVisual(btn, false, false)
    return btn
end

function T.SkinDangerButton(btn)
    if not btn then return btn end
    btn._msuf2Danger = true
    btn:SetActive(false)
    return btn
end

function T.SkinPrimaryButton(btn)
    if not btn then return btn end
    btn._msuf2Primary = true
    btn:SetActive(false)
    return btn
end

function T.CloseButton(parent)
    local btn = CreateFrame("Button", nil, parent, "UIPanelCloseButton")
    return btn
end
