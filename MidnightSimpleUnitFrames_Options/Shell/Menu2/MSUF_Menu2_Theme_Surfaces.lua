local _, MSUF = ...
local M = MSUF.MSUF2
local T = M.Theme
local FILE = "Shell/Menu2/MSUF_Menu2_Theme_Surfaces.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
local PixelLayoutLeaf = MSUF.Require("PreparePixelLayoutLeaf", FILE, MSUF.Util)
local MenuSkin = MSUF.MenuSkin
local GLASS_VARIANTS = T.glassVariants
local ConfigureAlphaAnim = T._ConfigureAlphaAnim
local function Template()
    return BackdropTemplateMixin and "BackdropTemplate" or nil
end

local WHITE8 = "Interface\\Buttons\\WHITE8X8"
local function SetColor(tex, c)
    if tex and c then tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
end
-- Registers tex as excluded pixel-layout art. Create it with
-- PixelLayoutRegion(tex, true): the plain wrapper would switch native rounding
-- on just so this can switch it off again.
local function SmoothTexture(tex)
    if not tex then return end
    if not tex._msufPixelLayoutExcluded or tex._msufPixelLayoutEnabled then PixelLayoutRegion(tex, true) end
    if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
    if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
end
local DEFAULT_PANEL_COLOR = { 0.04, 0.05, 0.08, 1 }
local gradientColorCache = {}
local GradientColor
do
    local function Sub(parent, key)
        local child = parent[key]
        if not child then
            child = {}
            parent[key] = child
        end
        return child
    end
    function GradientColor(r, g, b, a)
        local byA = Sub(Sub(Sub(gradientColorCache, r), g), b)
        local color = byA[a]
        if not color then
            color = CreateColor(r, g, b, a)
            byA[a] = color
        end
        return color
    end
end
local function SetTextureColorCached(tex, r, g, b, a)
    if not tex then return end
    r, g, b = r or 0, g or 0, b or 0
    if a == nil then a = 1 end
    if tex._msuf2TextureMode == "flat"
        and tex._msuf2ColorR == r
        and tex._msuf2ColorG == g
        and tex._msuf2ColorB == b
        and tex._msuf2ColorA == a
    then
        return
    end
    tex._msuf2TextureMode = "flat"
    tex._msuf2ColorR, tex._msuf2ColorG, tex._msuf2ColorB, tex._msuf2ColorA = r, g, b, a
    if tex.SetColorTexture then
        tex:SetColorTexture(r, g, b, a)
    else
        tex:SetTexture(WHITE8)
        if tex.SetVertexColor then tex:SetVertexColor(r, g, b, a) end
    end
end
local function ShadeColorComponents(c, amount, alphaMul)
    c = c or T.colors.panel2 or DEFAULT_PANEL_COLOR
    amount = tonumber(amount) or 0
    local r, g, b = c[1] or 0, c[2] or 0, c[3] or 0
    if amount >= 0 then
        r = r + (1 - r) * amount
        g = g + (1 - g) * amount
        b = b + (1 - b) * amount
    else
        local f = 1 + amount
        r, g, b = r * f, g * f, b * f
    end
    local a = (c[4] or 1) * (alphaMul or 1)
    if r < 0 then r = 0 elseif r > 1 then r = 1 end
    if g < 0 then g = 0 elseif g > 1 then g = 1 end
    if b < 0 then b = 0 elseif b > 1 then b = 1 end
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    return r, g, b, a
end
local function ShadeColorInto(out, c, amount, alphaMul)
    out = out or {}
    out[1], out[2], out[3], out[4] = ShadeColorComponents(c, amount, alphaMul)
    return out
end
local function ShadeColor(c, amount, alphaMul)
    return ShadeColorInto({}, c, amount, alphaMul)
end
local function ApplyTextureGradient(tex, orientation, fromColor, toColor, preserveTexture)
    if not tex then return false end
    fromColor = fromColor or T.colors.panel2 or DEFAULT_PANEL_COLOR
    toColor = toColor or fromColor
    orientation = orientation or "VERTICAL"
    local fr, fg, fb, fa = fromColor[1] or 0, fromColor[2] or 0, fromColor[3] or 0, fromColor[4] or 1
    local tr, tg, tb, ta = toColor[1] or 0, toColor[2] or 0, toColor[3] or 0, toColor[4] or 1
    if tex._msuf2TextureMode == "gradient"
        and tex._msuf2GradientOrientation == orientation
        and tex._msuf2GradientFR == fr
        and tex._msuf2GradientFG == fg
        and tex._msuf2GradientFB == fb
        and tex._msuf2GradientFA == fa
        and tex._msuf2GradientTR == tr
        and tex._msuf2GradientTG == tg
        and tex._msuf2GradientTB == tb
        and tex._msuf2GradientTA == ta
    then
        return true
    end
    if not preserveTexture and tex.SetTexture then
        tex:SetTexture(WHITE8)
        if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
    end
    if tex.SetGradientAlpha or (tex.SetGradient and CreateColor) then
        tex._msuf2TextureMode = "gradient"
        tex._msuf2GradientOrientation = orientation
        tex._msuf2GradientFR, tex._msuf2GradientFG, tex._msuf2GradientFB, tex._msuf2GradientFA = fr, fg, fb, fa
        tex._msuf2GradientTR, tex._msuf2GradientTG, tex._msuf2GradientTB, tex._msuf2GradientTA = tr, tg, tb, ta
        if tex.SetGradientAlpha then
            tex:SetGradientAlpha(orientation, fr, fg, fb, fa, tr, tg, tb, ta)
        else
            tex:SetGradient(orientation, GradientColor(fr, fg, fb, fa), GradientColor(tr, tg, tb, ta))
        end
        return true
    end
    if tex.SetVertexColor then
        SetTextureColorCached(tex,
            (fr + tr) * 0.5,
            (fg + tg) * 0.5,
            (fb + tb) * 0.5,
            (fa + ta) * 0.5)
    end
    return false
end
local function SetFillGradient(fill, baseColor, amountTop, amountBottom, alphaMul)
    if not fill then return end
    baseColor = baseColor or T.colors.pillBase or T.colors.panel2 or DEFAULT_PANEL_COLOR
    amountTop = amountTop or 0.16
    amountBottom = amountBottom or -0.20
    if T.controlGradientScale then
        amountTop, amountBottom = amountTop * T.controlGradientScale, amountBottom * T.controlGradientScale
    end
    alphaMul = alphaMul or 1
    local top = fill._msuf2GradientTopColor or {}
    local bottom = fill._msuf2GradientBottomColor or {}
    fill._msuf2GradientTopColor = top
    fill._msuf2GradientBottomColor = bottom
    local topR, topG, topB, topA = ShadeColorComponents(baseColor, amountTop, alphaMul)
    local bottomR, bottomG, bottomB, bottomA = ShadeColorComponents(baseColor, amountBottom, alphaMul)
    local gradientReady
    if fill.L and fill.M and fill.R then
        gradientReady = fill.L._msuf2TextureMode == "gradient"
            and fill.M._msuf2TextureMode == "gradient"
            and fill.R._msuf2TextureMode == "gradient"
    else
        gradientReady = fill._msuf2TextureMode == "gradient"
    end
    if gradientReady
        and top[1] == topR and top[2] == topG and top[3] == topB and top[4] == topA
        and bottom[1] == bottomR and bottom[2] == bottomG and bottom[3] == bottomB and bottom[4] == bottomA
    then
        return
    end
    top[1], top[2], top[3], top[4] = topR, topG, topB, topA
    bottom[1], bottom[2], bottom[3], bottom[4] = bottomR, bottomG, bottomB, bottomA
    if fill.L and fill.M and fill.R then
        ApplyTextureGradient(fill.L, "VERTICAL", top, bottom, true)
        ApplyTextureGradient(fill.M, "VERTICAL", top, bottom, true)
        ApplyTextureGradient(fill.R, "VERTICAL", top, bottom, true)
    elseif fill.SetGradientAlpha or fill.SetGradient then
        ApplyTextureGradient(fill, "VERTICAL", top, bottom, false)
    elseif fill.SetVertexColor then
        fill:SetVertexColor(baseColor[1], baseColor[2], baseColor[3], (baseColor[4] or 1) * (alphaMul or 1))
    end
end
M.Assign(T, {
    Tr = M.Tr, Template = Template, SetColor = SetColor, ShadeColor = ShadeColor,
    ApplyTextureGradient = ApplyTextureGradient, SetFillGradient = SetFillGradient,
})
local function SetSuperellipseVertexColor(self, r, g, b, a)
    a = a or 1
    self.L:SetVertexColor(r, g, b, a)
    self.M:SetVertexColor(r, g, b, a)
    self.R:SetVertexColor(r, g, b, a)
end
local function CreateSuperellipseParts(frame, layer, subLevel)
    -- The pill/superellipse skin is three textures, not a nine-slice frame. This keeps
    -- allocation cheap for dense option rows while still allowing gradient fills.
    subLevel = subLevel or 0
    -- Parts are excluded art from creation on. The plain wrapper would switch
    -- native rounding on only for SmoothTexture to switch it off again (two
    -- protected calls per part, ~12k parts per full menu build).
    local left = PixelLayoutLeaf(frame:CreateTexture(nil, layer, nil, subLevel), true)
    left:SetTexture(T.media.superellipse)
    left:SetTexCoord(0.00, 0.25, 0, 1)
    SmoothTexture(left)
    local middle = PixelLayoutLeaf(frame:CreateTexture(nil, layer, nil, subLevel), true)
    middle:SetTexture(T.media.superellipse)
    middle:SetTexCoord(0.25, 0.75, 0, 1)
    SmoothTexture(middle)
    local right = PixelLayoutLeaf(frame:CreateTexture(nil, layer, nil, subLevel), true)
    right:SetTexture(T.media.superellipse)
    right:SetTexCoord(0.75, 1.00, 0, 1)
    SmoothTexture(right)
    return { L = left, M = middle, R = right, SetVertexColor = SetSuperellipseVertexColor }
end
local function LayoutSuperellipseParts(parts, frame, inset, capW, rightPad)
    rightPad = tonumber(rightPad) or 0
    parts.L:ClearAllPoints()
    parts.M:ClearAllPoints()
    parts.R:ClearAllPoints()
    -- Caps keep their texture aspect while the middle segment stretches to absorb row width.
    parts.L:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    parts.L:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset)
    parts.L:SetWidth(capW)
    parts.R:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset - rightPad, -inset)
    parts.R:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset - rightPad, inset)
    parts.R:SetWidth(capW)
    parts.M:SetPoint("TOPLEFT", parts.L, "TOPRIGHT", 0, 0)
    parts.M:SetPoint("BOTTOMRIGHT", parts.R, "BOTTOMLEFT", 0, 0)
end
function T.CreateSuperellipseLayers(frame, key, inset, fillLayer, borderLayer)
    if not (frame and frame.CreateTexture) then return nil, nil end
    key = key or "_msuf2SE"
    if frame[key .. "Fill"] and frame[key .. "Border"] then return frame[key .. "Fill"], frame[key .. "Border"] end
    inset = inset or 1
    fillLayer = fillLayer or "BACKGROUND"
    borderLayer = borderLayer or "BORDER"
    -- The atlas edge is a solid silhouette, not a hollow mask. Keep it behind
    -- the inset fill; painting it on BORDER would cover the entire button.
    if T.classicAtlas then borderLayer = fillLayer end
    local h = (frame.GetHeight and frame:GetHeight()) or 22
    local fill = CreateSuperellipseParts(frame, fillLayer, 0)
    local border = CreateSuperellipseParts(frame, borderLayer, -1)
    local lastFillCap, lastBorderCap, lastRightPad
    local function Layout()
        local frameW = (frame.GetWidth and frame:GetWidth()) or 120
        local w = frameW
        local visualW = tonumber(frame._msuf2NavPillVisualWidth)
        if visualW and visualW > 0 and visualW < w then w = visualW end
        local rightPad = math.max(0, frameW - w)
        local h2 = (frame.GetHeight and frame:GetHeight()) or h
        local p = tonumber(inset) or 1
        local innerW = math.max(1, w - p * 2)
        local innerH = math.max(1, h2 - p * 2)
        local nextCapW = math.min(math.floor(innerH * 0.5 + 0.5), math.floor(innerW * 0.5))
        if T.controlCapWidth then nextCapW = math.min(nextCapW, T.controlCapWidth) end
        -- Authored Midnight nav art uses compact corners rather than stadium
        -- caps. Accent-colored procedural nav states must keep that silhouette.
        if frame._msuf2NavItem then nextCapW = math.min(nextCapW, 6) end
        local bInset = math.max(0, p - 1)
        local borderInnerW = math.max(1, w - bInset * 2)
        local borderInnerH = math.max(1, h2 - bInset * 2)
        local borderCapW = math.min(math.floor(borderInnerH * 0.5 + 0.5), math.floor(borderInnerW * 0.5))
        if T.controlCapWidth then borderCapW = math.min(borderCapW, T.controlCapWidth) end
        if frame._msuf2NavItem then borderCapW = math.min(borderCapW, 6) end
        -- Anchors follow the owner. Retain only changed geometry in this existing
        -- closure, without growing every fill/border table used by the painter.
        if lastFillCap == nextCapW and lastBorderCap == borderCapW and lastRightPad == rightPad then return end
        lastFillCap, lastBorderCap, lastRightPad = nextCapW, borderCapW, rightPad
        LayoutSuperellipseParts(fill, frame, p, nextCapW, rightPad)
        LayoutSuperellipseParts(border, frame, bInset, borderCapW, rightPad)
    end
    Layout()
    if frame.HookScript and not frame[key .. "LayoutHooked"] then
        frame[key .. "LayoutHooked"] = true
        frame:HookScript("OnSizeChanged", Layout)
    end
    frame[key .. "Fill"] = fill
    frame[key .. "Border"] = border
    fill.Layout = Layout
    border.Layout = Layout
    return fill, border
end
local BACKDROP_INFO = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
function T.ApplyBackdrop(frame, bg, border)
    if not frame then return frame end
    if MenuSkin.Surface(frame, "panel", T.ApplyBackdrop, bg, border, 1) then return frame end
    if frame.SetBackdrop then
        if frame._msuf2BackdropInfoApplied ~= BACKDROP_INFO then
            PixelLayoutRegion(frame, "SetBackdrop", BACKDROP_INFO)
            frame._msuf2BackdropInfoApplied = BACKDROP_INFO
        end
        local b = bg or T.colors.panel
        local e = border or T.colors.borderSoft
        local br, bgc, bb, ba = b[1], b[2], b[3], b[4] or 1
        if frame._msuf2BackdropR ~= br
            or frame._msuf2BackdropG ~= bgc
            or frame._msuf2BackdropB ~= bb
            or frame._msuf2BackdropA ~= ba
        then
            frame._msuf2BackdropR, frame._msuf2BackdropG, frame._msuf2BackdropB, frame._msuf2BackdropA = br, bgc, bb, ba
            frame:SetBackdropColor(br, bgc, bb, ba)
        end
        local er, eg, eb, ea = e[1], e[2], e[3], e[4] or 1
        if frame._msuf2BackdropBorderR ~= er
            or frame._msuf2BackdropBorderG ~= eg
            or frame._msuf2BackdropBorderB ~= eb
            or frame._msuf2BackdropBorderA ~= ea
        then
            frame._msuf2BackdropBorderR, frame._msuf2BackdropBorderG, frame._msuf2BackdropBorderB, frame._msuf2BackdropBorderA = er, eg, eb, ea
            frame:SetBackdropBorderColor(er, eg, eb, ea)
        end
    else
        if not frame._msuf2Bg then
            local tex = PixelLayoutLeaf(frame:CreateTexture(nil, "BACKGROUND"))
            tex:SetAllPoints()
            frame._msuf2Bg = tex
        end
        SetColor(frame._msuf2Bg, bg or T.colors.panel)
    end
    return frame
end
local function ColorTexture(tex, c)
    if not (tex and c) then return end
    if tex.SetColorTexture then
        tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    else
        tex:SetTexture("Interface\\Buttons\\WHITE8X8")
        if tex.SetVertexColor then tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
    end
end
local function ApplyFocusVeilLayer(frame, spec)
    if not (frame and frame.CreateTexture and type(spec) == "table" and type(spec.key) == "string") then return end
    local tex = frame[spec.key]
    if not tex then
        tex = PixelLayoutLeaf(frame:CreateTexture(nil, spec.layer or "BORDER", nil, spec.subLevel or 0))
        frame[spec.key] = tex
    end
    tex:ClearAllPoints()
    local p = spec.points
    if p then
        tex:SetPoint("TOPLEFT", frame, "TOPLEFT", p[1] or 0, p[2] or 0)
        tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", p[3] or 0, p[4] or 0)
    else
        tex:SetAllPoints()
    end
    local texture = spec.texture
    if texture then
        if T.media[texture] then texture = T.media[texture] end
        tex:SetTexture(texture)
        if spec.color and tex.SetVertexColor then tex:SetVertexColor(spec.color[1], spec.color[2], spec.color[3], spec.color[4] or 1) end
    else
        ColorTexture(tex, spec.color)
    end
    local tc = spec.texCoord
    if tc and tex.SetTexCoord then tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4], tc[5], tc[6], tc[7], tc[8]) end
    if tex.SetBlendMode then tex:SetBlendMode(spec.blend or "BLEND") end
    if tex.Show then tex:Show() end
end
function T.ApplyFocusVeil(frame, variant)
    local veil = T.focusVeils[variant or "dropdown"]
    if type(veil) ~= "table" then return frame end
    for i = 1, #veil do
        ApplyFocusVeilLayer(frame, veil[i])
    end
    return frame
end
local function GlassTexture(frame, key, layer, subLevel)
    if not (frame and frame.CreateTexture) then return nil end
    local tex = frame[key]
    if not tex then
        tex = PixelLayoutLeaf(frame:CreateTexture(nil, layer or "BACKGROUND", nil, subLevel or 0))
        frame[key] = tex
    end
    return tex
end
local function PlaceGlassFill(tex, frame, inset)
    if not tex then return end
    inset = tonumber(inset) or 0
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
end
local function PlaceGlassLine(tex, frame, point, height)
    if not tex then return end
    tex:ClearAllPoints()
    if point == "BOTTOM" then
        tex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 3, 3)
        tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
    else
        tex:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
        tex:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
    end
    tex:SetHeight(height or 1)
end
local function PlaceGlassSideLine(tex, frame, point, width)
    if not tex then return end
    tex:ClearAllPoints()
    if point == "RIGHT" then
        tex:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -4)
        tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 4)
    else
        tex:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -4)
        tex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 3, 4)
    end
    tex:SetWidth(width or 1)
end
local function PaintGlassLayer(frame, key, subLevel, color, texture, inset, blend, texCoord)
    local tex = GlassTexture(frame, key, "BORDER", subLevel)
    if color then
        PlaceGlassFill(tex, frame, inset)
        tex:SetTexture(texture or WHITE8)
        if texCoord and tex.SetTexCoord then tex:SetTexCoord(texCoord[1], texCoord[2], texCoord[3], texCoord[4], texCoord[5], texCoord[6],
            texCoord[7], texCoord[8]) end
        if tex.SetVertexColor then tex:SetVertexColor(color[1], color[2], color[3], color[4] or 1) end
        if tex.SetBlendMode then tex:SetBlendMode(blend or "BLEND") end
        if tex.Show then tex:Show() end
    elseif tex and tex.Hide then
        tex:Hide()
    end
    return tex
end
local function HideFrameTexture(frame, key)
    local tex = frame and frame[key]
    if tex and tex.Hide then tex:Hide() end
end
local GLASS_LAYER_KEYS = {
    "_msuf2GlassTint",
    "_msuf2GlassWash",
    "_msuf2GlassDepth",
    "_msuf2GlassGrain",
    "_msuf2GlassOuterGlow",
    "_msuf2GlassTopLine",
    "_msuf2GlassTopGlow",
    "_msuf2GlassBottomLine",
    "_msuf2GlassLeftLine",
    "_msuf2GlassRightLine",
}
local function HideLegacyGlassLayers(frame)
    for i = 1, #GLASS_LAYER_KEYS do HideFrameTexture(frame, GLASS_LAYER_KEYS[i]) end
end
local PANEL_ASSET_KEY = {
    shell = "panelShell",
    rail = "panelRail",
    host = "panelHost",
    status = "panelStatus",
    card = "panelCard",
    popup = "panelPopup",
}
local PANEL_SLICES = {
    { "TL", 0.000, 0.125, 0.000, 0.125 },
    { "T",  0.125, 0.875, 0.000, 0.125 },
    { "TR", 0.875, 1.000, 0.000, 0.125 },
    { "L",  0.000, 0.125, 0.125, 0.875 },
    { "C",  0.125, 0.875, 0.125, 0.875 },
    { "R",  0.875, 1.000, 0.125, 0.875 },
    { "BL", 0.000, 0.125, 0.875, 1.000 },
    { "B",  0.125, 0.875, 0.875, 1.000 },
    { "BR", 0.875, 1.000, 0.875, 1.000 },
}
local function EnsurePanelAsset(frame)
    if not (frame and frame.CreateTexture) then return nil end
    if frame._msuf2PanelAsset then return frame._msuf2PanelAsset end
    local art = {}
    for i = 1, #PANEL_SLICES do
        local spec = PANEL_SLICES[i]
        local tex = PixelLayoutLeaf(frame:CreateTexture(nil, "BACKGROUND", nil, 7))
        tex:SetTexCoord(spec[2], spec[3], spec[4], spec[5])
        if tex.SetBlendMode then tex:SetBlendMode("BLEND") end
        tex:Hide()
        art[spec[1]] = tex
    end
    local function Layout()
        local w = (frame.GetWidth and frame:GetWidth()) or 120
        local h = (frame.GetHeight and frame:GetHeight()) or 80
        local c = math.max(6, math.min(16, math.floor(math.min(w, h) * 0.34 + 0.5)))
        local os = 2
        for i = 1, #PANEL_SLICES do art[PANEL_SLICES[i][1]]:ClearAllPoints() end
        art.TL:SetPoint("TOPLEFT", frame, "TOPLEFT", -os, os)
        art.TL:SetSize(c, c)
        art.TR:SetPoint("TOPRIGHT", frame, "TOPRIGHT", os, os)
        art.TR:SetSize(c, c)
        art.BL:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -os, -os)
        art.BL:SetSize(c, c)
        art.BR:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", os, -os)
        art.BR:SetSize(c, c)
        art.T:SetPoint("TOPLEFT", art.TL, "TOPRIGHT", 0, 0)
        art.T:SetPoint("BOTTOMRIGHT", art.TR, "BOTTOMLEFT", 0, 0)
        art.B:SetPoint("TOPLEFT", art.BL, "TOPRIGHT", 0, 0)
        art.B:SetPoint("BOTTOMRIGHT", art.BR, "BOTTOMLEFT", 0, 0)
        art.L:SetPoint("TOPLEFT", art.TL, "BOTTOMLEFT", 0, 0)
        art.L:SetPoint("BOTTOMRIGHT", art.BL, "TOPRIGHT", 0, 0)
        art.R:SetPoint("TOPLEFT", art.TR, "BOTTOMLEFT", 0, 0)
        art.R:SetPoint("BOTTOMRIGHT", art.BR, "TOPRIGHT", 0, 0)
        art.C:SetPoint("TOPLEFT", art.TL, "BOTTOMRIGHT", 0, 0)
        art.C:SetPoint("BOTTOMRIGHT", art.BR, "TOPLEFT", 0, 0)
    end
    -- ApplyPanelAsset, the only caller, lays the slices out right after this.
    art.Layout = Layout
    if frame.HookScript and not frame._msuf2PanelAssetLayoutHooked then
        frame._msuf2PanelAssetLayoutHooked = true
        frame:HookScript("OnSizeChanged", Layout)
    end
    frame._msuf2PanelAsset = art
    return art
end
local function ConfigurePanelAssetColor(tex, tinted)
    if not tex then return end
    if tex.SetDesaturated then tex:SetDesaturated(tinted and true or false) end
    if not tex.SetVertexColor then return end
    if not tinted then
        tex:SetVertexColor(1, 1, 1, 1)
        return
    end
    -- The panel bitmaps carry the authored luminance/depth. Desaturating them
    -- preserves that material while this normalized token supplies only hue.
    local color = T.colors.coreSurface or T.colors.panel or { 1, 1, 1, 1 }
    local peak = math.max(color[1] or 0, color[2] or 0, color[3] or 0)
    if peak <= 0.001 then peak = 1 end
    tex:SetVertexColor((color[1] or 0) / peak, (color[2] or 0) / peak,
        (color[3] or 0) / peak, 1)
end
local function ApplyPanelAsset(frame, variant)
    local mediaKey = PANEL_ASSET_KEY[variant or "card"]
    local path = mediaKey and T.media[mediaKey]
    if not path then return false end
    local art = EnsurePanelAsset(frame)
    if not art then return false end
    if art.path ~= path then
        art.path = path
        for i = 1, #PANEL_SLICES do
            local tex = art[PANEL_SLICES[i][1]]
            if tex then tex:SetTexture(path) end
        end
    end
    if art.Layout then art.Layout() end
    local tinted = T.MenuAccentSurfacesTinted()
    for i = 1, #PANEL_SLICES do
        local tex = art[PANEL_SLICES[i][1]]
        if tex then
            ConfigurePanelAssetColor(tex, tinted)
            tex:Show()
        end
    end
    if frame.SetBackdropColor then frame:SetBackdropColor(0, 0, 0, 0.001) end
    if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(0, 0, 0, 0.001) end
    if T.classicAtlas then
        -- One alpha-bearing surface, not bitmap + gradient + fallback fill.
        -- Text and controls retain their own alpha; never fade the whole frame.
        HideFrameTexture(frame, "_msuf2MaterialGradient")
        HideFrameTexture(frame, "_msuf2Bg")
    end
    frame._msuf2PanelAssetApplied = true
    if T.ApplyMenuBackgroundOpacity then T.ApplyMenuBackgroundOpacity(frame, variant) end
    return true
end
local function HidePanelAsset(frame)
    local art = frame and frame._msuf2PanelAsset
    if not art then return end
    for i = 1, #PANEL_SLICES do
        local tex = art[PANEL_SLICES[i][1]]
        if tex and tex.Hide then tex:Hide() end
    end
    frame._msuf2PanelAssetApplied = nil
end
local function EnsurePanelAssetDepth(frame)
    if not (frame and frame.CreateTexture) then return nil end
    if frame._msuf2PanelAssetDepth then return frame._msuf2PanelAssetDepth end
    local top = PixelLayoutLeaf(frame:CreateTexture(nil, "BORDER", nil, -8))
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -5)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -7, -5)
    if top.SetBlendMode then top:SetBlendMode("ADD") end
    local bottom = PixelLayoutLeaf(frame:CreateTexture(nil, "BORDER", nil, -8))
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 6, 5)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 5)
    local function Glint(point, x, mediaKey)
        local glint = PixelLayoutLeaf(frame:CreateTexture(nil, "ARTWORK", nil, 1))
        glint:SetPoint(point, frame, point, x, -4)
        glint:SetHeight(2)
        glint:SetTexture((T.media[mediaKey]) or WHITE8)
        if glint.SetTexCoord then glint:SetTexCoord(0, 1, 0, 1) end
        if glint.SetBlendMode then glint:SetBlendMode("ADD") end
        return glint
    end
    local leftGlint, rightGlint = Glint("TOPLEFT", 12, "gradH"), Glint("TOPRIGHT", -12, "gradHRev")
    local cornerGlow = PixelLayoutLeaf(frame:CreateTexture(nil, "ARTWORK", nil, 0))
    cornerGlow:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -4)
    cornerGlow:SetSize(76, 18)
    cornerGlow:SetTexture(T.media.bgSmooth or WHITE8)
    if cornerGlow.SetBlendMode then cornerGlow:SetBlendMode("ADD") end
    frame._msuf2PanelAssetDepth = { top = top, bottom = bottom, leftGlint = leftGlint, rightGlint = rightGlint, cornerGlow = cornerGlow }
    return frame._msuf2PanelAssetDepth
end
local function StopPanelNeonPulse(depth)
    if not depth then return end
    if depth._neonPulse and depth._neonPulse.Stop then depth._neonPulse:Stop() end
    if depth._neonPulse2 and depth._neonPulse2.Stop then depth._neonPulse2:Stop() end
    if depth.leftGlint and depth.leftGlint.SetAlpha then depth.leftGlint:SetAlpha(1) end
    if depth.rightGlint and depth.rightGlint.SetAlpha then depth.rightGlint:SetAlpha(1) end
    if depth.cornerGlow and depth.cornerGlow.SetAlpha then depth.cornerGlow:SetAlpha(1) end
end
local function CreatePanelNeonSweep(tex, duration, travelX, fromAlpha, toAlpha, delay)
    if not (tex and tex.CreateAnimationGroup) then return nil end
    local group = tex:CreateAnimationGroup()
    T.TrackMenuAnimationGroup(group)
    if group.SetLooping then group:SetLooping("REPEAT") end
    local travel = group:CreateAnimation("Translation")
    if travel.SetOffset then travel:SetOffset(travelX or 0, 0) end
    if travel.SetDuration then travel:SetDuration(duration or 7.0) end
    if travel.SetSmoothing then travel:SetSmoothing("NONE") end
    if travel.SetOrder then travel:SetOrder(1) end
    local fadeIn = group:CreateAnimation("Alpha")
    ConfigureAlphaAnim(fadeIn, fromAlpha or 0.12, toAlpha or 0.78, 1.10, "OUT", 1)
    local fadeOut = group:CreateAnimation("Alpha")
    ConfigureAlphaAnim(fadeOut, toAlpha or 0.78, fromAlpha or 0.12, 1.20, "IN", 2)
    if delay and delay > 0 then
        if travel.SetStartDelay then travel:SetStartDelay(delay) end
        if fadeIn.SetStartDelay then fadeIn:SetStartDelay(delay) end
    end
    return group
end
local function StartPanelNeonPulse(depth, strong, frameWidth, glintWidth)
    if not (depth and depth.leftGlint and depth.leftGlint.CreateAnimationGroup) then return end
    if T.ReducedMotionEnabled() then
        StopPanelNeonPulse(depth)
        return
    end
    local w = math.max(1, tonumber(frameWidth) or 180)
    local glintW = math.max(24, tonumber(glintWidth) or 72)
    local duration = strong and 18.0 or 22.0
    local travelX = w + glintW + 24
    local key = tostring(strong and 1 or 0) .. ":" .. tostring(math.floor(w + 0.5)) .. ":" .. tostring(math.floor(glintW + 0.5))
    if depth._neonMotionKey ~= key then
        if depth._neonPulse and depth._neonPulse.Stop then depth._neonPulse:Stop() end
        if depth._neonPulse2 and depth._neonPulse2.Stop then depth._neonPulse2:Stop() end
        depth._neonPulse = CreatePanelNeonSweep(depth.leftGlint, duration, travelX, 0.015, strong and 0.30 or 0.22, 0)
        depth._neonPulse2 = CreatePanelNeonSweep(depth.rightGlint, duration, travelX, 0.010, strong and 0.18 or 0.13, duration * 0.56)
        depth._neonMotionKey = key
    end
    if depth._neonPulse and depth._neonPulse.Play and (not depth._neonPulse.IsPlaying or not depth._neonPulse:IsPlaying()) then depth._neonPulse:Play() end
    if depth._neonPulse2 and depth._neonPulse2.Play and (not depth._neonPulse2.IsPlaying or not depth._neonPulse2:IsPlaying()) then depth._neonPulse2:Play() end
end
local function ApplyPanelAssetDepth(frame, variant)
    -- Atlas panel artwork already contains its bevel and engraved rim.
    if T.staticMaterials then return end
    local depth = EnsurePanelAssetDepth(frame)
    if not depth then return end
    local strong = variant == "shell" or variant == "rail" or variant == "popup"
    local topH = strong and 36 or 28
    local bottomH = strong and 58 or 42
    local glow = frame._msuf2NeonColor or T.colors.coreGlow or T.colors.coreBlue or T.colors.accent
    local shadow = T.colors.coreShadow or { 0.006, 0.016, 0.032, 1 }
    if depth.top then
        depth.top:SetHeight(topH)
        ApplyTextureGradient(depth.top, "VERTICAL",
            { glow[1], glow[2], glow[3], strong and 0.016 or 0.011 },
            { glow[1], glow[2], glow[3], 0.000 },
            false)
        depth.top:Show()
    end
    if depth.bottom then
        depth.bottom:SetHeight(bottomH)
        ApplyTextureGradient(depth.bottom, "VERTICAL",
            { shadow[1], shadow[2], shadow[3], 0.000 },
            { shadow[1], shadow[2], shadow[3], strong and 0.130 or 0.095 },
            false)
        depth.bottom:Show()
    end
    if frame._msuf2NoPanelNeon or not frame._msuf2NeonEdge then
        StopPanelNeonPulse(depth)
        if depth.leftGlint and depth.leftGlint.Hide then depth.leftGlint:Hide() end
        if depth.rightGlint and depth.rightGlint.Hide then depth.rightGlint:Hide() end
        if depth.cornerGlow and depth.cornerGlow.Hide then depth.cornerGlow:Hide() end
        return
    end
    local w = (frame.GetWidth and frame:GetWidth()) or 180
    local glintW = math.max(36, math.min(strong and 118 or 86, math.floor(w * (strong and 0.115 or 0.095) + 0.5)))
    local animateNeon = not (T.ReducedMotionEnabled())
    if depth.leftGlint then
        depth.leftGlint:ClearAllPoints()
        depth.leftGlint:SetPoint("TOPLEFT", frame, "TOPLEFT", animateNeon and -glintW or 12, -4)
        depth.leftGlint:SetWidth(glintW)
        depth.leftGlint:SetTexture((T.media.gradH) or WHITE8)
        depth.leftGlint._msuf2TextureMode = nil
        depth.leftGlint:SetVertexColor(glow[1], glow[2], glow[3], strong and 0.055 or 0.036)
        if depth.leftGlint.SetAlpha then depth.leftGlint:SetAlpha(animateNeon and 0.015 or 0.62) end
        depth.leftGlint:Show()
    end
    if depth.rightGlint then
        local rightW = math.floor(glintW * 0.70 + 0.5)
        depth.rightGlint:ClearAllPoints()
        if animateNeon then
            depth.rightGlint:SetPoint("TOPLEFT", frame, "TOPLEFT", -rightW, -4)
        else
            depth.rightGlint:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -4)
        end
        depth.rightGlint:SetWidth(rightW)
        depth.rightGlint:SetTexture((T.media and (animateNeon and T.media.gradH or T.media.gradHRev)) or WHITE8)
        depth.rightGlint._msuf2TextureMode = nil
        depth.rightGlint:SetVertexColor(glow[1], glow[2], glow[3], strong and 0.040 or 0.026)
        if depth.rightGlint.SetAlpha then depth.rightGlint:SetAlpha(animateNeon and 0.010 or 0.52) end
        depth.rightGlint:Show()
    end
    if depth.cornerGlow then
        depth.cornerGlow:SetVertexColor(glow[1], glow[2], glow[3], strong and 0.026 or 0.014)
        depth.cornerGlow:Show()
    end
    StartPanelNeonPulse(depth, strong, w, glintW)
end
local function HidePanelAssetDepth(frame)
    local depth = frame and frame._msuf2PanelAssetDepth
    if not depth then return end
    StopPanelNeonPulse(depth)
    if depth.top and depth.top.Hide then depth.top:Hide() end
    if depth.bottom and depth.bottom.Hide then depth.bottom:Hide() end
    if depth.leftGlint and depth.leftGlint.Hide then depth.leftGlint:Hide() end
    if depth.rightGlint and depth.rightGlint.Hide then depth.rightGlint:Hide() end
    if depth.cornerGlow and depth.cornerGlow.Hide then depth.cornerGlow:Hide() end
end
local function NeonColor(kind, opts)
    opts = opts or {}
    if opts.color then return opts.color end
    if kind == "error" or kind == "danger" then return T.colors.danger or { 0.880, 0.280, 0.280, 1 } end
    if kind == "success" then return T.colors.ok or { 0.240, 0.820, 0.460, 1 } end
    if kind == "warning" then return T.colors.accent2 or { 0.965, 0.760, 0.150, 1 } end
    return T.colors.coreGlow or T.colors.accent or { 0.090, 0.360, 0.540, 1 }
end
function T.ApplyNeonEdge(frame, kind, opts)
    if not (frame and frame.CreateTexture) then return frame end
    opts = opts or {}
    frame._msuf2NoPanelNeon = nil
    frame._msuf2NeonEdge = true
    frame._msuf2NeonColor = NeonColor(kind, opts)
    frame._msuf2NeonKind = kind or "ambient"
    ApplyPanelAssetDepth(frame, opts.variant or frame._msuf2GlassVariant or "card")
    return frame
end
function T.PlayNeonFlash(frame, kind, opts)
    if not (frame and frame.CreateTexture) then return frame end
    opts = opts or {}
    local color = NeonColor(kind, opts)
    local flash = frame._msuf2NeonFlash
    if not flash then
        flash = PixelLayoutLeaf(frame:CreateTexture(nil, "OVERLAY", nil, 6))
        flash:SetTexture((T.media.superellipse) or WHITE8)
        flash:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
        flash:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
        if flash.SetBlendMode then flash:SetBlendMode("ADD") end
        frame._msuf2NeonFlash = flash
    end
    flash:SetVertexColor(color[1], color[2], color[3], opts.alpha or 0.26)
    flash:SetAlpha(opts.alpha or 0.26)
    flash:Show()
    if flash._msuf2FlashGroup and flash._msuf2FlashGroup.Stop then flash._msuf2FlashGroup:Stop() end
    if T.ReducedMotionEnabled() then
        flash:SetAlpha(0)
        flash:Hide()
        return frame
    end
    if flash.CreateAnimationGroup then
        local group = flash:CreateAnimationGroup()
        T.TrackMenuAnimationGroup(group)
        ConfigureAlphaAnim(group:CreateAnimation("Alpha"), opts.alpha or 0.26, 0, opts.duration or 0.70, "OUT")
        if group.SetScript then
            group:SetScript("OnFinished", function()
                if flash.SetAlpha then flash:SetAlpha(0) end
                if flash.Hide then flash:Hide() end
            end)
        end
        flash._msuf2FlashGroup = group
        group:Play()
    else
        flash:SetAlpha(0)
        flash:Hide()
    end
    return frame
end
function T.ApplyGlass(frame, variant)
    if not (frame and frame.CreateTexture) then return frame end
    if MenuSkin.Surface(frame, variant, T.ApplyGlass, variant, nil, 3) then return frame end
    if T.gradients[variant or "card"] then T.ApplyGradient(frame, variant or "card", { key = "_msuf2MaterialGradient" }) end
    local spec = GLASS_VARIANTS[variant or "card"] or GLASS_VARIANTS.card
    -- Accent selection may change hue, never renderer ownership or geometry.
    -- ApplyPanelAsset desaturates/re-hues the same authored material only when
    -- the user explicitly enables surface tinting.
    local panelAssetApplied = ApplyPanelAsset(frame, variant or "card")
    if panelAssetApplied then
        frame._msuf2GlassVariant = variant
        frame._msuf2GlassApplied = true
        HideLegacyGlassLayers(frame)
        ApplyPanelAssetDepth(frame, variant or "card")
        if T.ApplyAtlasDecoration then T.ApplyAtlasDecoration(frame, variant) end
        return frame
    end
    if frame._msuf2PanelAssetApplied then
        HidePanelAsset(frame)
        HidePanelAssetDepth(frame)
    end
    if frame._msuf2GlassVariant == variant and frame._msuf2GlassApplied then return frame end
    frame._msuf2GlassVariant = variant
    frame._msuf2GlassApplied = true
    local tint = GlassTexture(frame, "_msuf2GlassTint", "BORDER", 0)
    PlaceGlassFill(tint, frame, 2)
    ColorTexture(tint, spec.tint)
    if tint and tint.Show then tint:Show() end
    PaintGlassLayer(frame, "_msuf2GlassWash", 1, spec.wash, T.media.bgSmooth, 3, "ADD")
    PaintGlassLayer(frame, "_msuf2GlassDepth", 2, spec.depth, T.media.bgSmooth, 3, "BLEND", { 0, 0, 1, 0, 0, 1, 1, 1 })
    -- Grain, outer glow, and the top-line bloom are gone: at 0.008-0.014 alpha
    -- over a surface of nearly the same color they resolved to a sub-1/255
    -- delta, so they only ever cost draw calls. See the glassVariants note.
    HideFrameTexture(frame, "_msuf2GlassGrain")
    HideFrameTexture(frame, "_msuf2GlassOuterGlow")
    HideFrameTexture(frame, "_msuf2GlassTopGlow")
    local top = GlassTexture(frame, "_msuf2GlassTopLine", "ARTWORK", 0)
    PlaceGlassLine(top, frame, "TOP", 1)
    ColorTexture(top, spec.top)
    if top and top.Show then top:Show() end
    local bottom = GlassTexture(frame, "_msuf2GlassBottomLine", "ARTWORK", 0)
    PlaceGlassLine(bottom, frame, "BOTTOM", 1)
    ColorTexture(bottom, spec.bottom)
    if bottom and bottom.Show then bottom:Show() end
    local left = GlassTexture(frame, "_msuf2GlassLeftLine", "ARTWORK", 0)
    PlaceGlassSideLine(left, frame, "LEFT", 1)
    ColorTexture(left, spec.side or spec.top)
    if left and left.Show then left:Show() end
    local right = GlassTexture(frame, "_msuf2GlassRightLine", "ARTWORK", 0)
    PlaceGlassSideLine(right, frame, "RIGHT", 1)
    ColorTexture(right, spec.side or spec.top)
    if right and right.Show then right:Show() end
    return frame
end
function T.ApplyPlasticDepth(frame, variant)
    if not (frame and frame.CreateTexture) then return frame end
    if MenuSkin.Surface(frame, variant, T.ApplyPlasticDepth, variant, nil, 2) then return frame end
    if frame._msuf2PanelAssetApplied then
        HideFrameTexture(frame, "_msuf2PlasticTop")
        HideFrameTexture(frame, "_msuf2PlasticBottom")
        HideFrameTexture(frame, "_msuf2PlasticLip")
        return frame
    end
    variant = variant or "card"
    local strong = variant == "card" or variant == "guide" or variant == "warning"
    local topH = strong and 18 or 14
    local bottomH = strong and 22 or 16
    local top = frame._msuf2PlasticTop
    if not top then
        top = PixelLayoutLeaf(frame:CreateTexture(nil, "ARTWORK", nil, -2), true)
        frame._msuf2PlasticTop = top
        SmoothTexture(top)
    end
    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -5)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
    top:SetHeight(topH)
    local highlight = T.colors.coreBlue or T.colors.accent
    ApplyTextureGradient(top, "VERTICAL",
        { highlight[1], highlight[2], highlight[3], strong and 0.048 or 0.030 },
        { highlight[1], highlight[2], highlight[3], 0.000 },
        false)
    if top.SetBlendMode then top:SetBlendMode("ADD") end
    top:Show()
    local bottom = frame._msuf2PlasticBottom
    if not bottom then
        bottom = PixelLayoutLeaf(frame:CreateTexture(nil, "BORDER", nil, 5), true)
        frame._msuf2PlasticBottom = bottom
        SmoothTexture(bottom)
    end
    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 4)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    bottom:SetHeight(bottomH)
    ApplyTextureGradient(bottom, "VERTICAL",
        { 0.000, 0.000, 0.000, 0.000 },
        { 0.000, 0.000, 0.000, strong and 0.260 or 0.180 },
        false)
    bottom:Show()
    local lip = frame._msuf2PlasticLip
    if not lip then
        lip = PixelLayoutLeaf(frame:CreateTexture(nil, "ARTWORK", nil, 4))
        frame._msuf2PlasticLip = lip
        lip:SetTexture(WHITE8)
    end
    lip:ClearAllPoints()
    lip:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -6)
    lip:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -7, -6)
    lip:SetHeight(1)
    local lipColor = T.colors.coreBlue or T.colors.accent
    lip:SetColorTexture(lipColor[1], lipColor[2], lipColor[3], strong and 0.095 or 0.060)
    lip:Show()
    return frame
end
local function ResolveGradientSpec(token)
    if type(token) == "table" then return token end
    return T.gradients[token or "card"] or nil
end
local function DynamicGradientFromColor(color)
    color = color or T.colors.panel2
    return {
        orientation = "VERTICAL",
        from = ShadeColor(color, 0.16, 0.42),
        to = ShadeColor(color, -0.22, 0.58),
        inset = 2,
    }
end
function T.ApplyGradient(frame, token, opts)
    if not (frame and frame.CreateTexture) then return frame end
    if MenuSkin.Surface(frame, token, T.ApplyGradient, token, opts, 2) then return frame end
    opts = opts or {}
    local spec = ResolveGradientSpec(token) or DynamicGradientFromColor(T.colors.panel2)
    local key = opts.key or spec.key or "_msuf2MaterialGradient"
    local tex = frame[key]
    if not tex then
        tex = PixelLayoutLeaf(frame:CreateTexture(nil, opts.layer or spec.layer or "BACKGROUND", nil, opts.subLevel or spec.subLevel or 1), true)
        frame[key] = tex
        SmoothTexture(tex)
    end
    tex:ClearAllPoints()
    local inset = opts.inset
    if inset == nil then inset = spec.inset or 0 end
    if type(inset) == "table" then
        tex:SetPoint("TOPLEFT", frame, "TOPLEFT", inset[1] or 0, inset[2] or 0)
        tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", inset[3] or 0, inset[4] or 0)
    else
        inset = tonumber(inset) or 0
        tex:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
        tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    end
    ApplyTextureGradient(tex, spec.orientation or "VERTICAL", spec.from, spec.to, false)
    if tex.SetBlendMode then tex:SetBlendMode(spec.blend or "BLEND") end
    if tex.SetAlpha then tex:SetAlpha((spec.alpha or 1) * (opts.alpha or 1)) end
    if tex.Show then tex:Show() end
    return frame
end
function T.ApplyMaterial(frame, material)
    if not frame then return frame end
    if MenuSkin.Surface(frame, material, T.ApplyMaterial, material, nil, 5) then return frame end
    local spec = type(material) == "table" and material or (T.materials[material or "card"])
    if type(spec) ~= "table" then return frame end
    if spec.bg or spec.border then T.ApplyBackdrop(frame, spec.bg or T.colors.panel, spec.border or T.colors.borderSoft) end
    if spec.gradient then
        T.ApplyGradient(frame, spec.gradient, { key = "_msuf2MaterialGradient" })
    elseif frame._msuf2MaterialGradient and frame._msuf2MaterialGradient.Hide then
        frame._msuf2MaterialGradient:Hide()
    end
    if spec.glass then T.ApplyGlass(frame, spec.glass) end
    if spec.plastic ~= false then T.ApplyPlasticDepth(frame, spec.glass or material) end
    if spec.veil then T.ApplyFocusVeil(frame, spec.veil) end
    return frame
end
function T.ApplySurface(frame, material, glass)
    if MenuSkin.Surface(frame, glass or material, T.ApplySurface, material, glass, 6) then return frame end
    return T.ApplyMaterial(frame, material)
end
local function CreateAtmosphereTexture(parent, layer, subLevel, texture, color, inset, texCoord)
    local tex = PixelLayoutLeaf(parent:CreateTexture(nil, layer, nil, subLevel))
    tex:SetTexture(texture)
    inset = tonumber(inset) or 0
    tex:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, -inset)
    tex:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, inset)
    if texCoord then tex:SetTexCoord(texCoord[1], texCoord[2], texCoord[3], texCoord[4], texCoord[5], texCoord[6], texCoord[7], texCoord[8]) end
    tex:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    return tex
end
function T.ApplyMenuAtmosphere(frame, host, nav)
    if not frame or frame._msuf2AtmosphereApplied then return end
    frame._msuf2AtmosphereApplied = true
    host = host or frame
    T.ApplySurface(frame, "shell")
    if host and host ~= frame then T.ApplySurface(host, "host") end
    if nav then T.ApplySurface(nav, "rail") end
    CreateAtmosphereTexture(host, "BACKGROUND", 1, T.media.bgSmooth, { 0.08, 0.11, 0.20, 0.065 })
    CreateAtmosphereTexture(host, "BACKGROUND", 2, T.media.bgSmooth, { 0.04, 0.05, 0.12, 0.085 }, nil, { 0, 0, 1, 0, 0, 1, 1, 1 })
    CreateAtmosphereTexture(host, "BACKGROUND", 3, T.media.bgCharcoal, { 0.08, 0.08, 0.14, 0.055 })
    local logo = PixelLayoutLeaf(host:CreateTexture(nil, "BORDER", nil, 0))
    logo:SetTexture(T.media.logo)
    logo:SetSize(120, 120)
    logo:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -12, 12)
    logo:SetVertexColor(0.22, 0.28, 0.42, 0.024)
    if logo.SetBlendMode then logo:SetBlendMode("ADD") end
    if nav then CreateAtmosphereTexture(nav, "BORDER", 1, T.media.bgSmooth, { 0.06, 0.08, 0.18, 0.085 }, 3, { 0, 0, 1, 0, 0, 1, 1, 1 }) end
end

-- Private painting primitives, captured once by widget and button styles.
T._Surface = {
    SmoothTexture = SmoothTexture, SetTextureColorCached = SetTextureColorCached,
    ShadeColorInto = ShadeColorInto, DynamicGradientFromColor = DynamicGradientFromColor,
}
