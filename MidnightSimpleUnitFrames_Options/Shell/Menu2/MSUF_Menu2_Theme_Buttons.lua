local _, MSUF = ...
local M = MSUF.MSUF2
local T = M.Theme
local FILE = "Shell/Menu2/MSUF_Menu2_Theme_Buttons.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
local MenuSkin, Tr = MSUF.MenuSkin, M.Tr
local ApplyTextureGradient, SetFillGradient = T.ApplyTextureGradient, T.SetFillGradient
local SmoothTexture, ShadeColorInto = T._Surface.SmoothTexture, T._Surface.ShadeColorInto

local NAV_ICON_SIZE, NAV_ICON_LEFT, NAV_ICON_GAP = 20, 10, 8
local function LayoutNavButtonLabel(btn, isChild, hasIcon)
    if not (btn and btn._msuf2Label) then return end
    btn._msuf2Label:ClearAllPoints()
    btn._msuf2Label:SetPoint("LEFT", btn, "LEFT", hasIcon and (NAV_ICON_LEFT + NAV_ICON_SIZE + NAV_ICON_GAP) or 12, 0)
    btn._msuf2Label:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    btn._msuf2Label:SetJustifyH("LEFT")
end
local function PaintNavIcon(btn, r, g, b, a)
    local icon = btn and btn._msuf2NavIcon
    if icon then icon:SetVertexColor(r, g, b, a) end
end
function T.SetNavIconVisible(btn, visible)
    if not btn then return end
    visible = visible and true or false
    btn._msuf2NavIconVisible = visible
    if btn._msuf2NavIcon then
        if btn._msuf2NavIcon.SetShown then
            btn._msuf2NavIcon:SetShown(visible)
        elseif visible then
            btn._msuf2NavIcon:Show()
        else
            btn._msuf2NavIcon:Hide()
        end
    end
    LayoutNavButtonLabel(btn, btn._msuf2NavIconIsChild, visible and btn._msuf2NavIcon ~= nil)
    if btn.RefreshVisual then btn:RefreshVisual() end
end
function T.AttachNavIcon(btn, navKey, isChild, visible)
    if not (btn and btn.CreateTexture and navKey) then return end
    btn._msuf2NavIconKey = navKey
    btn._msuf2NavIconIsChild = isChild and true or false
    local grid = T.navIconGrid[navKey]
    local color = T.navIconColors[navKey]
    if not (grid and color) then
        LayoutNavButtonLabel(btn, isChild, false)
        return
    end
    local icon = btn._msuf2NavIcon
    if not icon then
        icon = PixelLayoutRegion(btn:CreateTexture(nil, "ARTWORK", nil, 3), true)
        SmoothTexture(icon)
        icon:SetTexture(T.media.navIcons)
        btn._msuf2NavIcon = icon
    end
    icon:ClearAllPoints()
    icon:SetSize(NAV_ICON_SIZE, NAV_ICON_SIZE)
    icon:SetPoint("LEFT", btn, "LEFT", NAV_ICON_LEFT, 0)
    local col, row = grid[1], grid[2]
    if icon.SetTexCoord then icon:SetTexCoord(col / 8, (col + 1) / 8, row / 8, (row + 1) / 8) end
    btn._msuf2NavIconColor = color
    if not btn._msuf2NavStripe then
        local stripe = PixelLayoutRegion(btn:CreateTexture(nil, "ARTWORK", nil, 6))
        stripe:SetTexture("Interface\\Buttons\\WHITE8X8")
        stripe:SetWidth(3)
        stripe:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -4)
        stripe:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 4)
        stripe:SetColorTexture(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 1.00)
        stripe:Hide()
        btn._msuf2NavStripe = stripe
    end
    T.SetNavIconVisible(btn, visible ~= false)
end
function T.CenterButtonLabel(btn)
    if btn and btn._msuf2Label then
        btn._msuf2Label:ClearAllPoints()
        btn._msuf2Label:SetPoint("CENTER", btn, "CENTER", 0, 0)
        btn._msuf2Label:SetJustifyH("CENTER")
    end
    return btn
end
local function SetLabelColor(label, color, alpha)
    label:SetTextColor(color[1], color[2], color[3], alpha or color[4] or 1)
end
local function PaintButtonParts(fill, edge, label, bg, br, tx, top, bottom, textAlpha)
    SetFillGradient(fill, bg, top, bottom)
    edge:SetVertexColor(br[1], br[2], br[3], br[4] or 1)
    SetLabelColor(label, tx, textAlpha)
end
local function PaintStoredNavIcon(btn, alpha)
    if btn._msuf2NavIcon and btn._msuf2NavIconColor then
        local ic = btn._msuf2NavIconColor
        PaintNavIcon(btn, ic[1], ic[2], ic[3], alpha)
    end
end
local NAV_PILL_TEX = {
    idle = "navPillIdle",
    hover = "navPillHover",
    active = "navPillActive",
}
-- Nav media is authored at its live 24 px height with 12 px circular caps.
-- Preserve those caps and stretch only the flat center so localized visual
-- widths cannot turn the active/hover silhouette into an ellipse.
local NAV_PILL_SLICE_MARGIN = 12
local NAV_PILL_SLICE_MODE = Enum and Enum.UITextureSliceMode
    and Enum.UITextureSliceMode.Stretched
local function ConfigureNavPillSlice(tex)
    if not tex then return end
    if tex.SetTextureSliceMargins then
        tex:SetTextureSliceMargins(NAV_PILL_SLICE_MARGIN, 0, NAV_PILL_SLICE_MARGIN, 0)
    end
    if NAV_PILL_SLICE_MODE ~= nil and tex.SetTextureSliceMode then
        tex:SetTextureSliceMode(NAV_PILL_SLICE_MODE)
    end
end
local function LayoutNavPillTexture(btn, tex)
    if not (btn and tex) then return end
    local h = (btn.GetHeight and btn:GetHeight()) or 20
    local buttonW = (btn.GetWidth and btn:GetWidth()) or 120
    local w = tonumber(btn._msuf2NavPillVisualWidth)
    if not w or w <= 0 then w = buttonW end
    if buttonW and buttonW > 0 and w > buttonW then w = buttonW end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    tex:SetSize(w, h)
end
-- Nav pill art layers: field, draw layer, sub level, blend mode.
local NAV_PILL_LAYERS = {
    { "texture", "BORDER", 7, "BLEND" }, { "glow", "ARTWORK", 1, "ADD" },
    { "hoverWash", "ARTWORK", 0, "ADD" }, { "sheen", "ARTWORK", 2, "ADD" },
}
local function LayoutNavPillArt(btn, art)
    if not art then return end
    for i = 1, #NAV_PILL_LAYERS do LayoutNavPillTexture(btn, art[NAV_PILL_LAYERS[i][1]]) end
end
local function EnsureNavPillArt(btn)
    if not (btn and btn.CreateTexture) then return nil end
    if btn._msuf2NavPillArt then return btn._msuf2NavPillArt end
    local art = {}
    for i = 1, #NAV_PILL_LAYERS do
        local spec = NAV_PILL_LAYERS[i]
        local tex = PixelLayoutRegion(btn:CreateTexture(nil, spec[2], nil, spec[3]))
        if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
        if tex.SetBlendMode then tex:SetBlendMode(spec[4]) end
        ConfigureNavPillSlice(tex)
        tex:Hide()
        art[spec[1]] = tex
    end
    LayoutNavPillArt(btn, art)
    btn._msuf2NavPillArt = art
    return art
end
local function StopNavPillGlowPulse(art)
    if not art then return end
    local group = art._pulse
    if group and group.Stop then group:Stop() end
    if art.glow and art.glow.SetAlpha then art.glow:SetAlpha(1) end
    if art.sheen and art.sheen.SetAlpha then art.sheen:SetAlpha(1) end
end
local function HideNavPillArt(btn)
    local art = btn and btn._msuf2NavPillArt
    if not art then return end
    StopNavPillGlowPulse(art)
    for i = 1, #NAV_PILL_LAYERS do
        local part = art[NAV_PILL_LAYERS[i][1]]
        if part then part:Hide() end
    end
    if art.L then art.L:Hide() end
    if art.M then art.M:Hide() end
    if art.R then art.R:Hide() end
end
-- Swaps a layer's media when the path changed, then tints it with the nav accent.
local function PaintNavPillLayer(art, key, pathKey, path, orientation, blue, fromAlpha, toAlpha, desaturate)
    local part = art[key]
    if art[pathKey] ~= path then
        art[pathKey] = path
        part:SetTexture(path)
        if desaturate and part.SetDesaturated then part:SetDesaturated(true) end
        part._msuf2TextureMode = nil
        if part.SetTexCoord then part:SetTexCoord(0, 1, 0, 1) end
    end
    ApplyTextureGradient(part, orientation,
        { blue[1], blue[2], blue[3], fromAlpha }, { blue[1], blue[2], blue[3], toAlpha }, true)
    part:Show()
end
local function PaintNavPillGlowArt(art, path, state)
    if not art then return end
    local active = state == "active"
    local hover = state == "hover"
    if T.staticMaterials or not (active or hover) then
        StopNavPillGlowPulse(art)
        if art.hoverWash then art.hoverWash:Hide() end
        if art.glow then art.glow:Hide() end
        if art.sheen then art.sheen:Hide() end
        return
    end
    local c = T.colors or {}
    local blue = hover and (c.navPillEdgeHover or c.coreGlow)
        or c.navPillEdgeActive or c.coreHot or c.accent or { 0.060, 0.250, 0.390, 1 }
    if art.hoverWash then
        if hover then
            PaintNavPillLayer(art, "hoverWash", "hoverWashPath", path, "VERTICAL", blue, 0.165, 0.045)
        else
            art.hoverWash:Hide()
        end
    end
    -- The bitmap's bright rim supplies the outline: the glow layer removes its baked
    -- blue before tinting so the accent is not multiplied twice.
    if art.glow then
        PaintNavPillLayer(art, "glow", "glowPath", path, "VERTICAL", blue,
            active and 0.72 or 0.38, active and 0.56 or 0.28, true)
    end
    if art.sheen then
        PaintNavPillLayer(art, "sheen", "sheenPath", path, "HORIZONTAL", blue, 0.000, active and 0.090 or 0.040)
    end
    -- Page selection is a direct state change. Keep the active treatment
    -- static so navigation never reads as an in-progress transition.
    StopNavPillGlowPulse(art)
end
local function SetNavPillArt(btn, state, baseColor, topAmount, bottomAmount, alphaMul)
    if state == "active" and btn._msuf2SelectionMotion then
        HideNavPillArt(btn)
        return true
    end
    -- Midnight owns the authored blue paint. Non-midnight themes use the
    -- compact procedural renderer for active and hover so both states can carry
    -- their class/preset accent without multiplying against baked blue pixels.
    if T.MenuAccentActive() then return false end
    local media = T.media or {}
    local path = media[NAV_PILL_TEX[state or "idle"] or ""]
    if not path then return false end
    local art = EnsureNavPillArt(btn)
    if not art then return false end
    LayoutNavPillArt(btn, art)
    if art.path ~= path then
        art.path = path
        if art.texture then
            art.texture:SetTexture(path)
            art.texture._msuf2TextureMode = nil
            if art.texture.SetTexCoord then art.texture:SetTexCoord(0, 1, 0, 1) end
        end
    end
    if art.texture then
        local base = baseColor or T.colors.navPillBase or T.colors.pillBase
        local top = art._topColor or {}
        local bottom = art._bottomColor or {}
        art._topColor = top
        art._bottomColor = bottom
        if state == "hover" or state == "active" then
            -- Preserve the bitmap's authored dark-blue paint. Multiplying it by
            -- dark interaction tokens also crushed the authored outline. Keep
            -- both selected and hovered rims readable with a neutral tint.
            top[1], top[2], top[3], top[4] = 1.00, 1.00, 1.00, 0.98
            bottom[1], bottom[2], bottom[3], bottom[4] = 0.76, 0.84, 1.00, 0.92
        else
            ShadeColorInto(top, base, topAmount or 0.22, alphaMul)
            ShadeColorInto(bottom, base, bottomAmount or -0.18, alphaMul)
        end
        ApplyTextureGradient(art.texture, "VERTICAL", top, bottom, true)
        art.texture:Show()
        PaintNavPillGlowArt(art, path, state)
    end
    return true
end
local function SetSuperellipsePartsShown(parts, shown)
    if not parts then return end
    if shown then
        parts.L:Show()
        parts.M:Show()
        parts.R:Show()
    else
        parts.L:Hide()
        parts.M:Hide()
        parts.R:Hide()
    end
end
local function SetSuperellipsePartsBlend(parts, blend)
    if not parts then return end
    blend = blend or "BLEND"
    if parts.L.SetBlendMode then parts.L:SetBlendMode(blend) end
    if parts.M.SetBlendMode then parts.M:SetBlendMode(blend) end
    if parts.R.SetBlendMode then parts.R:SetBlendMode(blend) end
end
local function EnsureNavActiveFX(btn)
    if not (btn and btn.CreateTexture) then return nil end
    if btn._msuf2NavActiveFX then return btn._msuf2NavActiveFX end
    local glowFill, glowEdge = T.CreateSuperellipseLayers(btn, "_msuf2NavActiveGlow", 0, "ARTWORK", "OVERLAY")
    local sheenFill, sheenEdge = T.CreateSuperellipseLayers(btn, "_msuf2NavActiveSheen", 4, "ARTWORK", "ARTWORK")
    SetSuperellipsePartsBlend(glowFill, "ADD")
    SetSuperellipsePartsBlend(sheenFill, "ADD")
    local fx = {
        glowFill = glowFill,
        glowEdge = glowEdge,
        sheenFill = sheenFill,
        sheenEdge = sheenEdge,
    }
    SetSuperellipsePartsShown(glowFill, false)
    SetSuperellipsePartsShown(glowEdge, false)
    SetSuperellipsePartsShown(sheenFill, false)
    SetSuperellipsePartsShown(sheenEdge, false)
    btn._msuf2NavActiveFX = fx
    return fx
end
local function SetNavActiveFX(btn, active, hover)
    if T.staticMaterials or not active then
        local fx = btn and btn._msuf2NavActiveFX
        if not fx then return end
        SetSuperellipsePartsShown(fx.glowFill, false)
        SetSuperellipsePartsShown(fx.glowEdge, false)
        SetSuperellipsePartsShown(fx.sheenFill, false)
        SetSuperellipsePartsShown(fx.sheenEdge, false)
        return
    end
    local fx = btn and (btn._msuf2NavActiveFX or EnsureNavActiveFX(btn))
    if not fx then return end
    local c = T.colors
    local blue = c.coreBlue or c.accent
    local glow = c.coreGlow or c.accent
    local hot = c.coreHot or glow
    if fx.glowFill then T.SetFillGradient(fx.glowFill, { blue[1], blue[2], blue[3], hover and 0.30 or 0.23 }, 0.34, -0.18) end
    if fx.glowEdge then fx.glowEdge:SetVertexColor(glow[1], glow[2], glow[3], hover and 0.76 or 0.56) end
    if fx.sheenFill then T.SetFillGradient(fx.sheenFill, { hot[1], hot[2], hot[3], hover and 0.18 or 0.115 }, 0.42, -0.55) end
    SetSuperellipsePartsShown(fx.glowFill, true)
    SetSuperellipsePartsShown(fx.glowEdge, true)
    SetSuperellipsePartsShown(fx.sheenFill, true)
    SetSuperellipsePartsShown(fx.sheenEdge, false)
end
-- Role buttons (danger/primary/success) paint their fill and edge, then return the
-- resting label color.
local ROLE_PAINT = {
    danger = function(c, lit, fill, edge)
        local d = c.danger
        if lit then
            SetFillGradient(fill, { 0.180, 0.040, 0.065, 0.97 }, 0.18, -0.18)
            edge:SetVertexColor(d[1], d[2], d[3], 0.95)
        else
            SetFillGradient(fill, { 0.140, 0.030, 0.050, 0.94 }, 0.14, -0.20)
            edge:SetVertexColor(d[1], d[2], d[3], 0.82)
        end
        return c.text[1], c.text[2], c.text[3]
    end,
    primary = function(c, lit, fill, edge)
        local blue, glow = c.coreBlue, c.coreGlow
        SetFillGradient(fill, { blue[1], blue[2], blue[3], lit and 0.64 or 0.56 }, lit and 0.08 or 0.07, lit and -0.28 or -0.30)
        edge:SetVertexColor(glow[1], glow[2], glow[3], lit and 0.46 or 0.38)
        return 1, 1, 1
    end,
    success = function(_, lit, fill, edge)
        if lit then
            SetFillGradient(fill, { 0.060, 0.380, 0.180, 0.98 }, 0.18, -0.18)
            edge:SetVertexColor(0.220, 0.860, 0.420, 0.90)
        else
            SetFillGradient(fill, { 0.040, 0.280, 0.130, 0.95 }, 0.14, -0.20)
            edge:SetVertexColor(0.140, 0.660, 0.310, 0.82)
        end
        return 0.92, 1.00, 0.94
    end,
}
local function SetSkinnedSelectionCue(btn, active)
    local cue = btn._msuf2SkinnedSelectionCue
    if not active or btn._msuf2SelectionMotion or btn._msuf2MotionSurface then
        if cue then
            cue.wash:Hide()
            cue.line:Hide()
        end
        return
    end
    if not cue then
        local wash = PixelLayoutRegion(btn:CreateTexture(nil, "ARTWORK", nil, 7))
        wash:SetTexture("Interface\\Buttons\\WHITE8X8")
        wash:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
        wash:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
        local line = PixelLayoutRegion(btn:CreateTexture(nil, "OVERLAY", nil, 2))
        line:SetTexture("Interface\\Buttons\\WHITE8X8")
        line:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -5)
        line:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 2, 5)
        line:SetWidth(3)
        cue = { wash = wash, line = line }
        btn._msuf2SkinnedSelectionCue = cue
    end
    local accent = T.colors.accent
    cue.wash:SetColorTexture(accent[1], accent[2], accent[3], 0.22)
    cue.line:SetColorTexture(accent[1], accent[2], accent[3], 0.94)
    cue.wash:Show()
    cue.line:SetShown(not btn._msuf2SelectionMotion)
end
local function PaintSelectedButton(btn, fill, edge, textOnlyHover)
    local c, moving = T.colors, btn._msuf2SelectionMotion
    local bg = moving and (btn._msuf2SolidPill and c.pillBaseSolid or c.pillBase) or c.pillActive
    local br, tx = moving and c.pillEdge or c.pillEdgeActive, c.pillTextActive
    if textOnlyHover then tx = c.navHeaderHover or tx end
    if btn._msuf2NavStripe then btn._msuf2NavStripe:SetShown(not moving) end
    PaintButtonParts(fill, edge, btn._msuf2Label, bg, br, tx, moving and 0.12 or 0.16, moving and -0.20 or -0.15, moving and 0.95 or 1)
    PaintStoredNavIcon(btn, 1.00)
end
local function ButtonVisual(btn, active, hover)
    if MenuSkin.Button(btn, active, hover, ButtonVisual) then
        HideNavPillArt(btn)
        SetNavActiveFX(btn, false)
        if btn._msuf2NavStripe then btn._msuf2NavStripe:Hide() end
        SetSkinnedSelectionCue(btn,
            active and (btn._msuf2NavItem or btn._msuf2SegmentChoice))
        return
    end
    SetSkinnedSelectionCue(btn, false)
    local c = T.colors
    local fill = btn._msuf2Fill
    local edge = btn._msuf2Edge
    local enabled = not (btn.IsEnabled and not btn:IsEnabled())
    -- Opt-in text-only hover (Edit Mode toolbar): the label is the entire hover
    -- affordance and the pill stays at its resting paint, whatever the state.
    -- Declared up here because the role branches below return early -- a primary
    -- or danger skinned button would otherwise never reach the generic painter.
    -- Living in the painter rather than an OnEnter hook keeps it through the
    -- SetActive and RefreshVisual repaints that fire while the cursor is on it.
    local textOnlyHover = hover and btn._msuf2HoverTextAccent
    local roleLit = (active and not btn._msuf2SelectionMotion) or (hover and not textOnlyHover)
    if not enabled then
        HideNavPillArt(btn)
        SetNavActiveFX(btn, false)
        SetFillGradient(fill, { c.coreShadow[1], c.coreShadow[2], c.coreShadow[3], 0.55 }, 0.08, -0.14)
        edge:SetVertexColor(c.coreRim[1], c.coreRim[2], c.coreRim[3], 0.45)
        btn._msuf2Label:SetTextColor(0.50, 0.52, 0.58, 0.95)
        return
    end
    if btn._msuf2NavHeader then
        HideNavPillArt(btn)
        SetNavActiveFX(btn, false)
        SetSuperellipsePartsShown(fill, false)
        SetSuperellipsePartsShown(edge, false)
        local tx = hover and (c.navHeaderHover or c.navHeaderText) or c.navHeaderText
        SetLabelColor(btn._msuf2Label, tx)
        return
    end
    local rolePaint = btn._msuf2Danger and ROLE_PAINT.danger or btn._msuf2Primary and ROLE_PAINT.primary
        or btn._msuf2Success and ROLE_PAINT.success
    if rolePaint then
        HideNavPillArt(btn)
        SetNavActiveFX(btn, false)
        local label = btn._msuf2Label
        local tr, tg, tb = rolePaint(c, roleLit, fill, edge)
        if textOnlyHover then
            SetLabelColor(label, c.navHeaderHover)
        else
            label:SetTextColor(tr, tg, tb, 1)
        end
        return
    end
    if btn._msuf2NavItem then
        SetSuperellipsePartsShown(fill, false)
        SetSuperellipsePartsShown(edge, false)
        if active then
            local bg = hover and c.navPillHover or c.navPillActive
            local br = hover and c.navPillEdgeHover or c.navPillEdgeActive
            local tx = hover and (c.navHeaderHover or c.navTextActive) or c.navTextActive
            if btn._msuf2NavStripe then btn._msuf2NavStripe:SetShown(not btn._msuf2SelectionMotion) end
            if SetNavPillArt(btn, "active", bg, hover and 0.20 or 0.17, -0.20) then
                SetNavActiveFX(btn, false)
                SetLabelColor(btn._msuf2Label, tx)
            else
                SetSuperellipsePartsShown(fill, true)
                SetSuperellipsePartsShown(edge, true)
                if fill and fill.Layout then fill.Layout() end
                PaintButtonParts(fill, edge, btn._msuf2Label, bg, br, tx, 0.24, -0.18)
                SetNavActiveFX(btn, not hover, false)
            end
            PaintNavIcon(btn, 0.82, 0.92, 1.00, 0.96)
        elseif hover then
            local bg, br, tx = c.navPillHover, c.navPillEdgeHover, c.navHeaderHover or c.navText
            SetNavActiveFX(btn, false)
            if btn._msuf2NavStripe then btn._msuf2NavStripe:Hide() end
            if SetNavPillArt(btn, "hover", bg, 0.14, -0.22) then
                SetLabelColor(btn._msuf2Label, c.navHeaderHover or tx, 1)
            else
                SetSuperellipsePartsShown(fill, true)
                SetSuperellipsePartsShown(edge, true)
                if fill and fill.Layout then fill.Layout() end
                PaintButtonParts(fill, edge, btn._msuf2Label, bg, br, tx, 0.14, -0.18, 1)
            end
            PaintStoredNavIcon(btn, 0.88)
        else
            local tx = c.navText
            SetNavActiveFX(btn, false)
            if btn._msuf2NavStripe then btn._msuf2NavStripe:Hide() end
            HideNavPillArt(btn)
            SetLabelColor(btn._msuf2Label, tx)
            PaintNavIcon(btn, tx[1], tx[2], tx[3], tx[4] or 1)
        end
        return
    end
    HideNavPillArt(btn)
    SetNavActiveFX(btn, false)
    if active then
        PaintSelectedButton(btn, fill, edge, textOnlyHover)
    elseif hover and not textOnlyHover then
        if btn._msuf2NavStripe then btn._msuf2NavStripe:Hide() end
        local bg, br = c.pillHover, c.pillEdgeHover
        PaintButtonParts(fill, edge, btn._msuf2Label, bg, br, c.text, 0.14, -0.18, 1)
        PaintStoredNavIcon(btn, 0.85)
    else
        if btn._msuf2NavStripe then btn._msuf2NavStripe:Hide() end
        local bg, br = c.pillBase, c.pillEdge
        local tx = textOnlyHover and (c.navHeaderHover or c.text) or c.pillText
        if btn._msuf2SolidPill then bg = c.pillBaseSolid end
        PaintButtonParts(fill, edge, btn._msuf2Label, bg, br, tx, 0.12, -0.20, 0.95)
        PaintStoredNavIcon(btn, 0.50)
    end
    if (not active) and btn._msuf2Override and edge then
        edge:SetVertexColor(0.96, 0.78, 0.24, 0.92)
        btn._msuf2Label:SetTextColor(c.accent[1], c.accent[2], c.accent[3], 1)
    end
end
-- translated = true marks text the caller translated already (a selected
-- dropdown entry, a composed status label); it is shown as is.
local function ButtonSetText(self, value, translated)
    local raw = value or ""
    local text = translated == true and raw or Tr(raw)
    if self._msuf2RawText == raw and self._msuf2Label and self._msuf2Label:GetText() == text then return end
    self._msuf2RawText = raw
    self._msuf2SearchText = raw
    if self._msuf2Label then self._msuf2Label._msuf2SearchText = raw end
    T.SetTranslatedText(self._msuf2Label, text)
    if value and value ~= "" then
        -- Dropdown buttons display the selected value, but selected text is not
        -- always the semantic control name. Opt-in controls keep one stable
        -- search label while their visible value continues to change normally.
        local searchLabel = self._msuf2StableSearchLabel or value
        local previous = type(self._msuf2SearchMeta) == "table" and self._msuf2SearchMeta or nil
        local meta = { label = searchLabel, kind = "button", anchor = self._msuf2Label }
        if previous then
            for key, item in pairs(previous) do meta[key] = item end
            meta.label, meta.kind, meta.anchor = searchLabel, previous.kind or "button", previous.anchor or self._msuf2Label
        end
        M.RegisterSearchWidget(self, meta)
    end
end
local function ButtonGetText(self)
    return self._msuf2Label:GetText()
end
local function ButtonSetActive(self, active)
    active = active and true or false
    if self._msuf2Active ~= active then self._msuf2Active = active end
    ButtonVisual(self, self._msuf2Active, self._msuf2Hover)
end
local function ButtonRefreshVisual(self)
    ButtonVisual(self, self._msuf2Active, self._msuf2Hover)
end
local function ButtonSetEnabled(self, enabled)
    enabled = enabled and true or false
    if self._msuf2Enabled ~= enabled then
        self._msuf2Enabled = enabled
        if enabled then
            if self.Enable then self:Enable() end
        else
            if self.Disable then self:Disable() end
        end
    end
    ButtonVisual(self, self._msuf2Active, self._msuf2Hover)
end
-- Finalize the old field before a button changes the active page, bar or scope.
-- Search boxes and inputs that require an explicit Enter are left alone.
function T.CommitFocusedInput()
    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if focus and (focus._msuf2CommitOnPointer == true
        or (focus._msuf2ControlKind == "textinput" and focus._msuf2CommitOnBlur == true)) then
        focus:ClearFocus()
    end
end
local function ButtonClickProxy(self, ...)
    if not self._msuf2AllowCombatClick then
        local blocked = M.BlockCombatAction() and true or false
        if blocked then return end
    end
    local handler = self._msuf2OnClickHandler
    T.CommitFocusedInput()
    if handler then return handler(self, ...) end
end
local function ButtonSetScript(self, scriptType, handler)
    local rawSetScript = self._msuf2RawSetScript
    if scriptType == "OnClick" then
        self._msuf2OnClickHandler = type(handler) == "function" and handler or nil
        return rawSetScript(self, scriptType, self._msuf2OnClickHandler and ButtonClickProxy or handler)
    end
    return rawSetScript(self, scriptType, handler)
end
local BUTTON_STYLE_HOOKS = {
    OnMouseDown = T.CommitFocusedInput,
    OnEnter = function(self)
        self._msuf2Hover = true
        ButtonVisual(self, self._msuf2Active, true)
    end,
    OnLeave = function(self)
        self._msuf2Hover = nil
        ButtonVisual(self, self._msuf2Active, false)
    end,
    OnEnable = ButtonRefreshVisual,
    OnDisable = ButtonRefreshVisual,
}
-- The click checkpoint snapshots the whole profile, so it is opt-in
-- (_msuf2HistoryCheckpoint, set from T.Button's opts.history).
local function ButtonHistoryCheckpoint(self)
    if self._msuf2HistoryCheckpoint ~= true or self._msuf2SkipHistoryCheckpoint then return end
    local checkpoint = M.CheckpointHistory
    local label = self._msuf2HistoryLabel
        or (self.GetText and self:GetText())
        or "MSUF2 button"
    if label == "" then label = "MSUF2 button" end
    checkpoint(label, self._msuf2HistorySource or ("button:" .. tostring(self)))
end
-- A button without an explicit opts.history opts in only as page content:
-- a page handler may write settings without recording history itself. Core
-- widgets that record history (sliders, segments, dropdowns, scope bars) or
-- write nothing pass history = false; chrome outside the page scroll child
-- opts in explicitly where it writes the profile.
local function IsPageContent(parent)
    local scrollChild = M.scrollChild
    local frame = parent
    while frame and scrollChild do
        if frame == scrollChild then return true end
        frame = frame.GetParent and frame:GetParent() or nil
    end
    return false
end
function T.Button(parent, text, width, height, opts)
    local btn = PixelLayoutRegion(CreateFrame("Button", nil, parent))
    local history = opts and opts.history
    if history == nil then history = IsPageContent(parent) end
    btn._msuf2HistoryCheckpoint = history == true
    btn:SetSize(width or 120, height or 24)
    if btn.SetHitRectInsets then btn:SetHitRectInsets(-2, -2, -2, -2) end
    local fill, edge = T.CreateSuperellipseLayers(btn, "_msuf2Btn", 2, "BACKGROUND", "BORDER")
    btn._msuf2Fill = fill
    btn._msuf2Edge = edge
    local label = T.Font(btn, "GameFontHighlightSmall", text or "", T.colors.muted)
    label:SetPoint("LEFT", 12, 0)
    label:SetPoint("RIGHT", -12, 0)
    label:SetJustifyH("LEFT")
    btn._msuf2Label = label
    btn._msuf2SearchText = text or ""
    label._msuf2SearchText = text or ""
    -- noSearch is for component buttons (slider +/- steppers) that would be
    -- registered here only to be unregistered by MarkRuntimeControlComponent
    -- moments later.
    if text and text ~= ""
        and not (opts and opts.noSearch) then
        M.RegisterSearchWidget(btn, { label = text, kind = "button", anchor = label })
    end
    btn._msuf2RawSetScript = btn.SetScript
    btn.SetScript = ButtonSetScript
    btn.SetText, btn.GetText = ButtonSetText, ButtonGetText
    btn.SetActive, btn.RefreshVisual, btn.SetEnabled = ButtonSetActive, ButtonRefreshVisual, ButtonSetEnabled
    for script, handler in pairs(BUTTON_STYLE_HOOKS) do btn:SetScript(script, handler) end
    btn:HookScript("OnClick", ButtonHistoryCheckpoint)
    ButtonVisual(btn, false, false)
    return btn
end
function T.SkinDangerButton(btn) return T.ApplyButtonRole(btn, "danger") end
function T.SkinPrimaryButton(btn) return T.ApplyButtonRole(btn, "primary") end
function T.SkinSuccessButton(btn) return T.ApplyButtonRole(btn, "success") end
local BUTTON_ROLE_VARIANTS = { primary = "primary", destructive = "danger", danger = "danger", delete = "danger", reset = "danger",
    success = "success", confirm = "success" }
function T.ApplyButtonRole(btn, role)
    if not btn then return btn end
    role = tostring(role or "normal")
    local variant = BUTTON_ROLE_VARIANTS[role]
    btn._msuf2Primary = (variant == "primary") or nil
    btn._msuf2Danger = (variant == "danger") or nil
    btn._msuf2Success = (variant == "success") or nil
    btn._msuf2Role = role
    if btn.RefreshVisual then btn:RefreshVisual() elseif btn.SetActive then btn:SetActive(btn._msuf2Active) end
    return btn
end
function T.RoleButton(parent, text, role, width, height)
    return T.ApplyButtonRole(T.Button(parent, text, width, height), role)
end
-- T.Button pins its label to LEFT +12 / RIGHT -12, so any label wider than width-24 is silently
-- clipped. Hardcoded button widths therefore only ever fit the English string; every other locale
-- loses characters. This measures the translated label and resizes to it.
local BUTTON_LABEL_INSET = 24
function T.MeasureButtonWidth(btn, minWidth, maxWidth)
    if not btn then return tonumber(minWidth) or 0 end
    local label = btn._msuf2Label
    local width
    if label and label.GetStringWidth then
        local measured = label:GetStringWidth()
        if type(measured) == "number" and measured > 0 then
            width = measured + BUTTON_LABEL_INSET + 1
        end
    end
    if not width then
        -- GetStringWidth answers 0 before the font is realized; fall back to the current width so
        -- callers never collapse a button to nothing.
        width = (btn.GetWidth and tonumber(btn:GetWidth())) or tonumber(minWidth) or 0
    end
    width = math.floor(width + 0.5)
    if minWidth and width < minWidth then width = minWidth end
    if maxWidth and width > maxWidth then width = maxWidth end
    return width
end
function T.FitButtonWidth(btn, minWidth, maxWidth)
    if not btn then return btn end
    btn:SetWidth(T.MeasureButtonWidth(btn, minWidth, maxWidth))
    return btn
end
local function CloseButtonVisual(btn, hover, down)
    if not btn then return end
    if MenuSkin.WindowAction(btn, "close", CloseButtonVisual, hover, down) then return end
    local fill = btn._msuf2CloseFill
    local edge = btn._msuf2CloseEdge
    local lineA = btn._msuf2CloseLineA
    local lineB = btn._msuf2CloseLineB
    local label = btn._msuf2CloseFallback
    local alpha = (btn.IsEnabled and not btn:IsEnabled()) and 0.42 or 1
    if fill and fill.SetVertexColor then
        if down then
            SetFillGradient(fill, { 0.310, 0.050, 0.070, 0.98 * alpha }, 0.16, -0.18)
        elseif hover then
            SetFillGradient(fill, { 0.230, 0.045, 0.065, 0.96 * alpha }, 0.14, -0.18)
        else
            SetFillGradient(fill, { T.colors.coreShadow[1], T.colors.coreShadow[2], T.colors.coreShadow[3], 0.92 * alpha }, 0.10, -0.20)
        end
    end
    if edge and edge.SetVertexColor then
        if hover or down then
            edge:SetVertexColor(T.colors.danger[1], T.colors.danger[2], T.colors.danger[3], 0.96 * alpha)
        else
            edge:SetVertexColor(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.78 * alpha)
        end
    end
    local lr, lg, lb = 1.00, hover and 0.88 or 0.72, hover and 0.86 or 0.78
    if lineA and lineA.SetVertexColor then lineA:SetVertexColor(lr, lg, lb, alpha) end
    if lineB and lineB.SetVertexColor then lineB:SetVertexColor(lr, lg, lb, alpha) end
    if label and label.SetTextColor then label:SetTextColor(lr, lg, lb, alpha) end
end
local CLOSE_BUTTON_HOOKS = {
    OnEnter = function(self)
        self._msuf2CloseHover = true
        CloseButtonVisual(self, true, self._msuf2CloseDown)
    end,
    OnLeave = function(self)
        self._msuf2CloseHover = nil
        self._msuf2CloseDown = nil
        CloseButtonVisual(self, false, false)
    end,
    OnMouseDown = function(self)
        self._msuf2CloseDown = true
        CloseButtonVisual(self, self._msuf2CloseHover, true)
    end,
    OnMouseUp = function(self)
        self._msuf2CloseDown = nil
        CloseButtonVisual(self, self._msuf2CloseHover, false)
    end,
    OnEnable = function(self) CloseButtonVisual(self, self._msuf2CloseHover, self._msuf2CloseDown) end,
    OnDisable = function(self) CloseButtonVisual(self, false, false) end,
}
local function SetupCloseButtonLine(line, parent)
    line:SetTexture("Interface\\Buttons\\WHITE8X8")
    line:SetSize(12, 2)
    line:SetPoint("CENTER", parent, "CENTER", 0, 0)
end
function T.CloseButton(parent)
    local btn = PixelLayoutRegion(CreateFrame("Button", nil, parent))
    btn:SetSize(24, 24)
    local fill, edge = T.CreateSuperellipseLayers(btn, "_msuf2Close", 2, "BACKGROUND", "BORDER")
    btn._msuf2CloseFill = fill
    btn._msuf2CloseEdge = edge
    local lineA, lineB = PixelLayoutRegion(btn:CreateTexture(nil, "ARTWORK")), PixelLayoutRegion(btn:CreateTexture(nil, "ARTWORK"))
    SetupCloseButtonLine(lineA, btn)
    SetupCloseButtonLine(lineB, btn)
    if lineA.SetRotation and lineB.SetRotation then
        lineA:SetRotation(math.pi * 0.25)
        lineB:SetRotation(-math.pi * 0.25)
    else
        lineA:Hide()
        lineB:Hide()
        local fallback = T.Font(btn, "GameFontHighlightSmall", "x", T.colors.danger)
        fallback:SetPoint("CENTER", btn, "CENTER", 0, 0)
        btn._msuf2CloseFallback = fallback
    end
    btn._msuf2CloseLineA = lineA
    btn._msuf2CloseLineB = lineB
    for script, handler in pairs(CLOSE_BUTTON_HOOKS) do btn:SetScript(script, handler) end
    CloseButtonVisual(btn, false, false)
    return btn
end
