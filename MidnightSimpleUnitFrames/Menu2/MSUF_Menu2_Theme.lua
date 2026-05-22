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
    switchTrack = ADDON_PATH .. "Media\\msuf_switch_track.tga",
    switchKnob = ADDON_PATH .. "Media\\msuf_switch_knob.tga",
    bgSmooth = ADDON_PATH .. "Media\\Bars\\Smoothv2.tga",
    bgCharcoal = ADDON_PATH .. "Media\\Bars\\Charcoal.tga",
    logo = ADDON_PATH .. "Media\\MSUF_MinimapIcon.tga",
    navIcons = ADDON_PATH .. "Media\\msuf_nav_icons",
    historyUndo = ADDON_PATH .. "Media\\msuf_history_undo_red.png",
    historyRedo = ADDON_PATH .. "Media\\msuf_history_redo_green.png",
}
T.media.gradH = T.media.gradH or ADDON_PATH .. "Media\\MSUF_Grad_H.tga"
T.media.gradHRev = T.media.gradHRev or ADDON_PATH .. "Media\\MSUF_Grad_H_Rev.tga"
T.media.gradV = T.media.gradV or ADDON_PATH .. "Media\\MSUF_Grad_V.tga"
T.media.gradVRev = T.media.gradVRev or ADDON_PATH .. "Media\\MSUF_Grad_V_Rev.tga"

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
    navPillBase = { 0.085, 0.115, 0.220, 0.92 },
    navPillBaseSolid = { 0.095, 0.125, 0.240, 0.94 },
    navPillHover = { 0.115, 0.155, 0.310, 0.96 },
    navPillActive = { 0.255, 0.395, 0.960, 0.99 },
    navPillEdge = { 0.160, 0.210, 0.410, 0.48 },
    navPillEdgeHover = { 0.270, 0.420, 0.880, 0.72 },
    navPillEdgeActive = { 0.430, 0.600, 1.000, 0.88 },
    navText = { 0.840, 0.900, 1.000, 0.96 },
    navTextActive = { 0.970, 0.990, 1.000, 1.00 },
    navHeaderText = { 0.680, 0.780, 1.000, 0.96 },
    navHeaderHover = { 0.780, 0.860, 1.000, 1.00 },
    navArrowOpen = { 1.000, 0.760, 0.250, 1.00 },
    navArrowClosed = { 1.000, 0.560, 0.060, 1.00 },
}

T.fontBump = T.fontBump or 1

T.navIconGrid = {
    home = { 0, 0 },
    uf_player = { 1, 0 }, uf_target = { 3, 0 }, uf_targettarget = { 2, 0 }, uf_focustarget = { 2, 0 },
    uf_focus = { 2, 0 }, uf_boss = { 6, 2 }, uf_pet = { 6, 0 },
    opt_bars = { 7, 0 }, opt_fonts = { 0, 1 }, auras2 = { 3, 1 },
    opt_castbar = { 2, 1 }, opt_misc = { 4, 2 }, opt_colors = { 4, 1 },
    classpower = { 0, 2 }, gameplay = { 7, 1 },
    groupframes = { 1, 2 }, gf_layout = { 2, 2 }, gf_bars = { 3, 2 }, gf_auras = { 3, 1 }, gf_indicators = { 6, 1 },
    modules = { 4, 2 }, profiles = { 5, 2 },
}

T.navIconColors = {
    home = { 0.30, 0.60, 1.00 },
    uf_player = { 0.40, 0.78, 0.98 }, uf_target = { 0.40, 0.78, 0.98 }, uf_targettarget = { 0.40, 0.78, 0.98 }, uf_focustarget = { 0.40, 0.78, 0.98 },
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

local ENGLISH_LOCALES = { enUS = true, enGB = true }
local LOCALE_ORDER = { "enUS", "enGB", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }

local function ActiveLocale()
    if type(ns.GetEffectiveLocale) == "function" then return ns.GetEffectiveLocale() end
    return ns.LOCALE or ((type(GetLocale) == "function" and GetLocale()) or "enUS")
end

local function TrackLocaleKey(key, translated)
    M.localeKeys = M.localeKeys or {}
    M.localeKeys[key] = true
    if ENGLISH_LOCALES[ActiveLocale()] or translated then return end
    M.missingLocaleKeys = M.missingLocaleKeys or {}
    M.missingLocaleKeys[key] = true
end

function M.GetLocaleCoverage()
    local keys, missing = M.localeKeys or {}, M.missingLocaleKeys or {}
    local total, missingTotal, missingList = 0, 0, {}
    for key in pairs(keys) do total = total + 1 end
    for key in pairs(missing) do
        missingTotal = missingTotal + 1
        missingList[#missingList + 1] = key
    end
    table.sort(missingList)
    return total, missingTotal, missingList
end

local function Tr(text)
    if type(text) ~= "string" then return text end
    if type(ns.Translate) == "function" then
        local translated = ns.Translate(text)
        TrackLocaleKey(text, translated ~= text)
        return translated
    end
    local locale = ns.L or _G.MSUF_L
    if type(locale) == "table" then
        local direct = rawget(locale, text)
        if direct ~= nil then
            TrackLocaleKey(text, true)
            return direct
        end
    end
    if type(ns.TR) == "function" then
        local translated = ns.TR(text)
        if translated ~= nil and translated ~= text then
            TrackLocaleKey(text, true)
            return translated
        end
    end
    TrackLocaleKey(text, false)
    return text
end
M.Tr = M.Tr or Tr
T.Tr = M.Tr

local function ClientLocale()
    return (type(GetLocale) == "function" and GetLocale()) or ns.CLIENT_LOCALE or "enUS"
end

local function IsSupportedLocale(locale)
    local supported = ns.SUPPORTED_LOCALES
    return type(locale) == "string" and type(supported) == "table" and supported[locale] == true
end

function M.GetLocaleDropdownValues()
    local names = ns.LOCALE_NAMES or {}
    local values = {
        { value = "auto", text = "Follow Blizzard" },
    }
    for i = 1, #LOCALE_ORDER do
        local locale = LOCALE_ORDER[i]
        values[#values + 1] = { value = locale, text = names[locale] or locale, translate = false }
    end
    return values
end

function M.GetLocaleSelection()
    local g = M.GetGeneralDB and M.GetGeneralDB()
    local selected = type(g) == "table" and g.menuLocale
    if IsSupportedLocale(selected) then return selected end
    return "auto"
end

function M.ResolveLocaleSelection(selection)
    if IsSupportedLocale(selection) then return selection end
    local locale = ClientLocale()
    if IsSupportedLocale(locale) then return locale end
    return "enUS"
end

function M.ApplyLocaleSelection(selection)
    local selected = selection or M.GetLocaleSelection()
    local locale = M.ResolveLocaleSelection(selected)
    M.missingLocaleKeys = {}
    if type(ns.SetLocale) == "function" then
        return ns.SetLocale(locale), selected
    end
    ns.LOCALE = locale
    return locale, selected
end

M.Format = M.Format or function(text, ...)
    local translated = M.Tr(text)
    if select("#", ...) == 0 then return translated end
    local ok, value = pcall(string.format, translated, ...)
    return ok and value or translated
end

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

        local bInset = math.max(0, p - 1)
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
        hint:SetText(open and "" or Tr("click to expand"))
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

local function HideNativeSliderTexture(region, keep)
    if not region or region == keep then return end
    if region.SetAlpha then region:SetAlpha(0) end
    if region.Hide then region:Hide() end
end

local function HideNativeSliderParts(slider)
    if not slider then return end
    local thumb = slider.GetThumbTexture and slider:GetThumbTexture()
    local keep = {}
    local function Keep(region)
        if region then keep[region] = true end
    end
    Keep(thumb)
    Keep(slider._msufTrack)
    Keep(slider._msufTrackTop)
    Keep(slider._msufTrackBottom)
    Keep(slider._msufFill)
    Keep(slider._msufFillGlow)
    Keep(slider._msufPeelTrack)
    Keep(slider._msufPeelTrackFill)

    if slider.GetRegions then
        local regions = { slider:GetRegions() }
        for i = 1, #regions do
            local region = regions[i]
            local isTexture = false
            if region and region.IsObjectType then isTexture = region:IsObjectType("Texture") and true or false end
            if (not isTexture) and region and region.GetObjectType then isTexture = region:GetObjectType() == "Texture" end
            if isTexture and not keep[region] then HideNativeSliderTexture(region) end
        end
    end

    local name = slider.GetName and slider:GetName()
    if name and _G then
        for _, suffix in ipairs({ "Left", "Middle", "Right", "Text", "Low", "High" }) do
            HideNativeSliderTexture(_G[name .. suffix])
        end
    end
end

local function SetSliderTextureColor(texture, r, g, b, a)
    if not texture then return end
    if texture.SetColorTexture then
        texture:SetColorTexture(r, g, b, a)
    else
        texture:SetTexture("Interface\\Buttons\\WHITE8X8")
        if texture.SetVertexColor then texture:SetVertexColor(r, g, b, a) end
    end
end

function T.StyleSlider(slider)
    if not slider then return end
    slider.__msufPeelSliderSkinned = true
    slider._msuf2SliderStyled = true

    if slider.SetOrientation then slider:SetOrientation("HORIZONTAL") end
    if slider.SetThumbTexture and slider.GetThumbTexture and not slider:GetThumbTexture() then
        slider:SetThumbTexture(T.media.sliderThumb or "Interface\\Buttons\\WHITE8X8")
    end
    HideNativeSliderParts(slider)

    if not slider._msufTrack and slider.CreateTexture then
        local track = slider:CreateTexture(nil, "BACKGROUND", nil, 1)
        track:SetPoint("LEFT", slider, "LEFT", 0, 0)
        track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
        track:SetHeight(8)
        slider._msufTrack = track

        local top = slider:CreateTexture(nil, "BORDER", nil, 1)
        top:SetPoint("LEFT", track, "LEFT", 0, 0)
        top:SetPoint("RIGHT", track, "RIGHT", 0, 0)
        top:SetPoint("TOP", track, "TOP", 0, 0)
        top:SetHeight(1)
        slider._msufTrackTop = top

        local bottom = slider:CreateTexture(nil, "BORDER", nil, 1)
        bottom:SetPoint("LEFT", track, "LEFT", 0, 0)
        bottom:SetPoint("RIGHT", track, "RIGHT", 0, 0)
        bottom:SetPoint("BOTTOM", track, "BOTTOM", 0, 0)
        bottom:SetHeight(1)
        slider._msufTrackBottom = bottom

        local fill = slider:CreateTexture(nil, "ARTWORK", nil, 1)
        fill:SetPoint("LEFT", slider, "LEFT", 1, 0)
        fill:SetHeight(4)
        slider._msufFill = fill

        local glow = slider:CreateTexture(nil, "OVERLAY", nil, 1)
        glow:SetPoint("LEFT", fill, "LEFT", 0, 0)
        glow:SetPoint("RIGHT", fill, "RIGHT", 0, 0)
        glow:SetHeight(8)
        slider._msufFillGlow = glow
    end

    local enabled = not (slider.IsEnabled and not slider:IsEnabled())
    local hovered = slider._msuf2SliderHovered and true or false
    local alpha = enabled and 1 or 0.45
    local accent = T.colors.accent
    local edge = T.colors.border or T.colors.borderSoft

    if slider._msufTrack then
        SetSliderTextureColor(slider._msufTrack, 0.035, 0.043, 0.078, 0.98 * alpha)
        if slider._msufTrack.Show then slider._msufTrack:Show() end
    end
    if slider._msufTrackTop then
        SetSliderTextureColor(slider._msufTrackTop, edge[1], edge[2], edge[3], (hovered and 0.95 or 0.70) * alpha)
        slider._msufTrackTop:Show()
    end
    if slider._msufTrackBottom then
        SetSliderTextureColor(slider._msufTrackBottom, edge[1], edge[2], edge[3], 0.40 * alpha)
        slider._msufTrackBottom:Show()
    end
    if slider._msufFill then
        SetSliderTextureColor(slider._msufFill, accent[1], accent[2], accent[3], (hovered and 0.95 or 0.78) * alpha)
        if slider._msufFill.Show then slider._msufFill:Show() end
    end
    if slider._msufFillGlow then
        SetSliderTextureColor(slider._msufFillGlow, accent[1], accent[2], accent[3], (hovered and 0.18 or 0.10) * alpha)
        slider._msufFillGlow:Show()
    end

    local thumb = slider.GetThumbTexture and slider:GetThumbTexture()
    if thumb then
        thumb:SetTexture(T.media.sliderThumb or "Interface\\Buttons\\WHITE8X8")
        thumb:SetTexCoord(0, 1, 0, 1)
        thumb:SetSize(18, 18)
        if thumb.SetVertexColor then thumb:SetVertexColor(accent[1], accent[2], accent[3], alpha) end
        if thumb.SetAlpha then thumb:SetAlpha(alpha) end
        if thumb.Show then thumb:Show() end
    end

    if slider.HookScript and not slider._msuf2SliderStyleHooks then
        slider._msuf2SliderStyleHooks = true
        slider:HookScript("OnEnter", function(self)
            self._msuf2SliderHovered = true
            T.StyleSlider(self)
        end)
        slider:HookScript("OnLeave", function(self)
            self._msuf2SliderHovered = nil
            T.StyleSlider(self)
        end)
        slider:HookScript("OnSizeChanged", function(self)
            if self._msuf2UpdateFill then self:_msuf2UpdateFill() end
        end)
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if not slider then return end
            slider.__msufPeelSliderSkinned = true
            HideNativeSliderParts(slider)
            if slider._msufTrack and slider._msufTrack.Show then slider._msufTrack:Show() end
            if slider._msufTrackTop and slider._msufTrackTop.Show then slider._msufTrackTop:Show() end
            if slider._msufTrackBottom and slider._msufTrackBottom.Show then slider._msufTrackBottom:Show() end
            if slider._msufFill and slider._msufFill.Show then slider._msufFill:Show() end
            if slider._msufFillGlow and slider._msufFillGlow.Show then slider._msufFillGlow:Show() end
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
    local fontString = editBox.GetFontString and editBox:GetFontString() or nil
    if editBox.GetRegions then
        local regions = { editBox:GetRegions() }
        for i = 1, #regions do
            local region = regions[i]
            local isTexture = false
            if region and region.IsObjectType then isTexture = region:IsObjectType("Texture") and true or false end
            if (not isTexture) and region and region.GetObjectType then isTexture = region:GetObjectType() == "Texture" end
            if isTexture and region ~= fontString then
                if region.SetAlpha then region:SetAlpha(0) end
                if region.Hide then region:Hide() end
            end
        end
    end
    T.ApplyBackdrop(editBox, { 0.020, 0.024, 0.046, 0.96 }, T.colors.borderSoft)
    if editBox.CreateTexture then
        local bg = editBox:CreateTexture(nil, "BACKGROUND", nil, -6)
        bg:SetPoint("TOPLEFT", editBox, "TOPLEFT", 0, 0)
        bg:SetPoint("BOTTOMRIGHT", editBox, "BOTTOMRIGHT", 0, 0)
        editBox._msuf2EditBg = bg

        local top = editBox:CreateTexture(nil, "OVERLAY", nil, 1)
        top:SetPoint("TOPLEFT", editBox, "TOPLEFT", 0, 0)
        top:SetPoint("TOPRIGHT", editBox, "TOPRIGHT", 0, 0)
        top:SetHeight(1)
        local bottom = editBox:CreateTexture(nil, "OVERLAY", nil, 1)
        bottom:SetPoint("BOTTOMLEFT", editBox, "BOTTOMLEFT", 0, 0)
        bottom:SetPoint("BOTTOMRIGHT", editBox, "BOTTOMRIGHT", 0, 0)
        bottom:SetHeight(1)
        local left = editBox:CreateTexture(nil, "OVERLAY", nil, 1)
        left:SetPoint("TOPLEFT", editBox, "TOPLEFT", 0, 0)
        left:SetPoint("BOTTOMLEFT", editBox, "BOTTOMLEFT", 0, 0)
        left:SetWidth(1)
        local right = editBox:CreateTexture(nil, "OVERLAY", nil, 1)
        right:SetPoint("TOPRIGHT", editBox, "TOPRIGHT", 0, 0)
        right:SetPoint("BOTTOMRIGHT", editBox, "BOTTOMRIGHT", 0, 0)
        right:SetWidth(1)
        editBox._msuf2EditEdges = { top, bottom, left, right }
    end
    local function PaintEditBox(self, focused)
        local enabled = not (self.IsEnabled and not self:IsEnabled())
        local alpha = enabled and 1 or 0.45
        local roundedFill = self._msuf2RoundedEditFill
        local roundedEdge = self._msuf2RoundedEditEdge
        if roundedFill and roundedEdge then
            local bg = self._msuf2RoundedEditColor or { 0.018, 0.024, 0.050, 0.98 }
            roundedFill:SetVertexColor(bg[1] or 0.018, bg[2] or 0.024, bg[3] or 0.050, (bg[4] or 0.98) * alpha)
            local c = focused and T.colors.accent or T.colors.borderSoft
            local a = focused and 0.95 or 0.78
            roundedEdge:SetVertexColor(c[1], c[2], c[3], a * alpha)
            if self.SetBackdropColor then self:SetBackdropColor(0, 0, 0, 0) end
            if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0, 0, 0, 0) end
            if self._msuf2EditBg and self._msuf2EditBg.Hide then self._msuf2EditBg:Hide() end
            local edges = self._msuf2EditEdges
            if edges then
                for i = 1, #edges do
                    if edges[i].Hide then edges[i]:Hide() end
                end
            end
            return
        end
        if self._msuf2EditBg then self._msuf2EditBg:SetColorTexture(0.018, 0.024, 0.050, 0.98 * alpha) end
        local c = focused and T.colors.accent or T.colors.borderSoft
        local a = focused and 0.95 or 0.78
        local edges = self._msuf2EditEdges
        if edges then
            for i = 1, #edges do
                edges[i]:SetColorTexture(c[1], c[2], c[3], a * alpha)
            end
        end
    end
    editBox._msuf2PaintEditBox = PaintEditBox
    local fs = fontString
    T.StyleFontString(fs, T.colors.text, 1)
    editBox:HookScript("OnEditFocusGained", function(self)
        PaintEditBox(self, true)
        if self.SetBackdropBorderColor and not self._msuf2RoundedEditFill then
            self:SetBackdropBorderColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.95)
        end
    end)
    editBox:HookScript("OnEditFocusLost", function(self)
        PaintEditBox(self, false)
        if self.SetBackdropBorderColor and not self._msuf2RoundedEditFill then
            self:SetBackdropBorderColor(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], T.colors.borderSoft[4] or 1)
        end
    end)
    pcall(editBox.HookScript, editBox, "OnEnable", function(self) PaintEditBox(self, self.HasFocus and self:HasFocus()) end)
    pcall(editBox.HookScript, editBox, "OnDisable", function(self) PaintEditBox(self, false) end)
    editBox:HookScript("OnShow", function(self) PaintEditBox(self, self.HasFocus and self:HasFocus()) end)
    PaintEditBox(editBox, false)
    return editBox
end

function T.Font(parent, template, text, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    local rawSetText = fs.SetText
    fs.SetText = function(self, value)
        rawSetText(self, Tr(value or ""))
    end
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
    if btn._msuf2NavHeader then
        fill:SetVertexColor(0, 0, 0, 0)
        edge:SetVertexColor(0, 0, 0, 0)
        local tx = hover and (c.navHeaderHover or c.navHeaderText) or c.navHeaderText
        btn._msuf2Label:SetTextColor(tx[1], tx[2], tx[3], tx[4] or 1)
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
    if btn._msuf2Success then
        if active or hover then
            fill:SetVertexColor(0.060, 0.380, 0.180, 0.98)
            edge:SetVertexColor(0.220, 0.860, 0.420, 0.90)
        else
            fill:SetVertexColor(0.040, 0.280, 0.130, 0.95)
            edge:SetVertexColor(0.140, 0.660, 0.310, 0.82)
        end
        btn._msuf2Label:SetTextColor(0.92, 1.00, 0.94, 1)
        return
    end
    if btn._msuf2NavItem then
        if active then
            if btn._msuf2NavStripe then btn._msuf2NavStripe:Hide() end
            local bg, br, tx = c.navPillActive, c.navPillEdgeActive, c.navTextActive
            fill:SetVertexColor(bg[1], bg[2], bg[3], bg[4] or 1)
            edge:SetVertexColor(br[1], br[2], br[3], br[4] or 1)
            btn._msuf2Label:SetTextColor(tx[1], tx[2], tx[3], tx[4] or 1)
            if btn._msuf2NavIcon then btn._msuf2NavIcon:SetVertexColor(0.96, 0.99, 1.00, 1.00) end
        elseif hover then
            if btn._msuf2NavStripe then btn._msuf2NavStripe:Hide() end
            local bg, br, tx = c.navPillHover, c.navPillEdgeHover, c.navText
            fill:SetVertexColor(bg[1], bg[2], bg[3], bg[4] or 1)
            edge:SetVertexColor(br[1], br[2], br[3], br[4] or 1)
            btn._msuf2Label:SetTextColor(tx[1], tx[2], tx[3], 1)
            if btn._msuf2NavIcon and btn._msuf2NavIconColor then
                local ic = btn._msuf2NavIconColor
                btn._msuf2NavIcon:SetVertexColor(ic[1], ic[2], ic[3], 0.88)
            end
        else
            if btn._msuf2NavStripe then btn._msuf2NavStripe:Hide() end
            local bg, br, tx = btn._msuf2SolidPill and c.navPillBaseSolid or c.navPillBase, c.navPillEdge, c.navText
            fill:SetVertexColor(bg[1], bg[2], bg[3], bg[4] or 1)
            edge:SetVertexColor(br[1], br[2], br[3], br[4] or 1)
            btn._msuf2Label:SetTextColor(tx[1], tx[2], tx[3], tx[4] or 1)
            if btn._msuf2NavIcon and btn._msuf2NavIconColor then
                local ic = btn._msuf2NavIconColor
                btn._msuf2NavIcon:SetVertexColor(ic[1], ic[2], ic[3], 0.64)
            end
        end
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
        btn._msuf2Label:SetTextColor(c.accent[1], c.accent[2], c.accent[3], 1)
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
    btn._msuf2SearchText = text or ""
    label._msuf2SearchText = text or ""
    if M and type(M.RegisterSearchWidget) == "function" and text and text ~= "" then
        M.RegisterSearchWidget(btn, { label = text, kind = "button", anchor = label })
    end

    local rawSetScript = btn.SetScript
    btn.SetScript = function(self, scriptType, handler)
        if scriptType == "OnClick" and type(handler) == "function" then
            local wrapped = function(...)
                if not self._msuf2AllowCombatClick then
                    local blocked = false
                    if M and type(M.BlockCombatAction) == "function" then
                        blocked = M.BlockCombatAction() and true or false
                    elseif type(_G.MSUF_BlockConfigCombatLocked) == "function" then
                        blocked = _G.MSUF_BlockConfigCombatLocked() and true or false
                    elseif (_G.InCombatLockdown and _G.InCombatLockdown())
                        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))
                    then
                        blocked = true
                        if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then
                            _G.MSUF_ShowConfigCombatLockMessage()
                        end
                    end
                    if blocked then return end
                end
                return handler(...)
            end
            return rawSetScript(self, scriptType, wrapped)
        end
        return rawSetScript(self, scriptType, handler)
    end

    btn.SetText = function(self, value)
        local raw = value or ""
        local text = Tr(raw)
        if self._msuf2RawText == raw and self._msuf2Label and self._msuf2Label:GetText() == text then
            return
        end
        self._msuf2RawText = raw
        self._msuf2SearchText = raw
        if self._msuf2Label then self._msuf2Label._msuf2SearchText = raw end
        self._msuf2Label:SetText(text)
        if M and type(M.RegisterSearchWidget) == "function" and value and value ~= "" then
            M.RegisterSearchWidget(self, { label = value, kind = "button", anchor = self._msuf2Label })
        end
    end
    btn.GetText = function(self)
        return self._msuf2Label:GetText()
    end
    btn.SetActive = function(self, active)
        active = active and true or false
        if self._msuf2Active ~= active then
            self._msuf2Active = active
        end
        ButtonVisual(self, self._msuf2Active, self._msuf2Hover)
    end
    btn.RefreshVisual = function(self)
        ButtonVisual(self, self._msuf2Active, self._msuf2Hover)
    end
    btn.SetEnabled = function(self, enabled)
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
    btn:HookScript("OnClick", function(self)
        if self._msuf2SkipHistoryCheckpoint then return end
        local checkpoint = M and M.CheckpointHistory
        if type(checkpoint) ~= "function" then return end
        local label = self._msuf2HistoryLabel
            or (self.GetText and self:GetText())
            or "MSUF2 button"
        if label == "" then label = "MSUF2 button" end
        checkpoint(label, self._msuf2HistorySource or ("button:" .. tostring(self)))
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

function T.SkinSuccessButton(btn)
    if not btn then return btn end
    btn._msuf2Success = true
    btn:SetActive(false)
    return btn
end

local function CloseButtonVisual(btn, hover, down)
    if not btn then return end
    local fill = btn._msuf2CloseFill
    local edge = btn._msuf2CloseEdge
    local lineA = btn._msuf2CloseLineA
    local lineB = btn._msuf2CloseLineB
    local label = btn._msuf2CloseFallback
    local alpha = (btn.IsEnabled and not btn:IsEnabled()) and 0.42 or 1

    if fill and fill.SetVertexColor then
        if down then
            fill:SetVertexColor(0.310, 0.050, 0.070, 0.98 * alpha)
        elseif hover then
            fill:SetVertexColor(0.230, 0.045, 0.065, 0.96 * alpha)
        else
            fill:SetVertexColor(0.075, 0.080, 0.125, 0.92 * alpha)
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

function T.CloseButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(24, 24)

    local fill, edge = T.CreateSuperellipseLayers(btn, "_msuf2Close", 2, "BACKGROUND", "BORDER")
    btn._msuf2CloseFill = fill
    btn._msuf2CloseEdge = edge

    local lineA = btn:CreateTexture(nil, "ARTWORK")
    lineA:SetTexture("Interface\\Buttons\\WHITE8X8")
    lineA:SetSize(12, 2)
    lineA:SetPoint("CENTER", btn, "CENTER", 0, 0)
    local lineB = btn:CreateTexture(nil, "ARTWORK")
    lineB:SetTexture("Interface\\Buttons\\WHITE8X8")
    lineB:SetSize(12, 2)
    lineB:SetPoint("CENTER", btn, "CENTER", 0, 0)
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

    btn:SetScript("OnEnter", function(self)
        self._msuf2CloseHover = true
        CloseButtonVisual(self, true, self._msuf2CloseDown)
    end)
    btn:SetScript("OnLeave", function(self)
        self._msuf2CloseHover = nil
        self._msuf2CloseDown = nil
        CloseButtonVisual(self, false, false)
    end)
    btn:SetScript("OnMouseDown", function(self)
        self._msuf2CloseDown = true
        CloseButtonVisual(self, self._msuf2CloseHover, true)
    end)
    btn:SetScript("OnMouseUp", function(self)
        self._msuf2CloseDown = nil
        CloseButtonVisual(self, self._msuf2CloseHover, false)
    end)
    btn:SetScript("OnEnable", function(self)
        CloseButtonVisual(self, self._msuf2CloseHover, self._msuf2CloseDown)
    end)
    btn:SetScript("OnDisable", function(self)
        CloseButtonVisual(self, false, false)
    end)

    CloseButtonVisual(btn, false, false)
    return btn
end

local function ClampScrollValue(value, maxValue)
    value = tonumber(value) or 0
    maxValue = tonumber(maxValue) or 0
    if value < 0 then return 0 end
    if value > maxValue then return maxValue end
    return value
end

local function PixelBarTexture(texture)
    if not texture then return texture end
    texture:SetTexture("Interface\\Buttons\\WHITE8X8")
    if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(true) end
    if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
    return texture
end

function T.StyleScrollFrame(scroll, anchor)
    if not scroll or scroll._msuf2ScrollStyled then return scroll and scroll._msuf2ScrollBar end
    scroll._msuf2ScrollStyled = true

    local parent = anchor or (scroll.GetParent and scroll:GetParent()) or scroll
    local bar = CreateFrame("Slider", nil, parent)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(10)
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, -8)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 8)
    bar:SetMinMaxValues(0, 1)
    bar:SetValueStep(1)
    if bar.SetObeyStepOnDrag then bar:SetObeyStepOnDrag(false) end
    if bar.EnableMouse then bar:EnableMouse(true) end
    if bar.SetFrameLevel and scroll.GetFrameLevel then bar:SetFrameLevel(scroll:GetFrameLevel() + 8) end

    local track = PixelBarTexture(bar:CreateTexture(nil, "BACKGROUND"))
    track:SetPoint("TOP", bar, "TOP", 0, 0)
    track:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    track:SetWidth(2)
    track:SetColorTexture(0.025, 0.030, 0.060, 0.82)
    bar._msuf2Track = track

    local trackEdge = PixelBarTexture(bar:CreateTexture(nil, "BORDER"))
    trackEdge:SetPoint("TOPLEFT", track, "TOPRIGHT", 1, 0)
    trackEdge:SetPoint("BOTTOMLEFT", track, "BOTTOMRIGHT", 1, 0)
    trackEdge:SetWidth(1)
    trackEdge:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.38)
    bar._msuf2TrackEdge = trackEdge

    local thumbBase = { 0.240, 0.300, 0.430 }
    local thumbHover = { 0.320, 0.420, 0.560 }

    local thumb = PixelBarTexture(bar:CreateTexture(nil, "OVERLAY"))
    thumb:SetSize(5, 42)
    thumb:SetColorTexture(thumbBase[1], thumbBase[2], thumbBase[3], 0.72)
    bar:SetThumbTexture(thumb)
    bar._msuf2Thumb = thumb

    local function Paint(hover)
        local shown = bar.IsShown and bar:IsShown()
        local alpha = shown and 1 or 0
        if track then track:SetColorTexture(0.025, 0.030, 0.060, (hover and 0.98 or 0.82) * alpha) end
        if trackEdge then trackEdge:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], (hover and 0.62 or 0.38) * alpha) end
        if thumb and thumb.SetColorTexture then
            local c = hover and thumbHover or thumbBase
            thumb:SetColorTexture(c[1], c[2], c[3], (hover and 0.90 or 0.68) * alpha)
        end
    end

    local rawSetVerticalScroll = scroll.SetVerticalScroll
    local function Refresh()
        local child = scroll.GetScrollChild and scroll:GetScrollChild()
        local childH = (child and child.GetHeight and child:GetHeight()) or 0
        local frameH = (scroll.GetHeight and scroll:GetHeight()) or 0
        local maxScroll = math.max(0, childH - frameH)
        scroll._msuf2MaxScroll = maxScroll

        if maxScroll <= 1 or frameH <= 0 then
            if rawSetVerticalScroll and (scroll:GetVerticalScroll() or 0) ~= 0 then
                rawSetVerticalScroll(scroll, 0)
            end
            bar._msuf2Refreshing = true
            bar:SetValue(0)
            bar._msuf2Refreshing = nil
            bar:Hide()
            return
        end

        bar:Show()
        bar:SetMinMaxValues(0, maxScroll)
        local visibleRatio = frameH / math.max(childH, 1)
        local thumbH = math.floor(math.max(34, math.min(frameH, frameH * visibleRatio)) + 0.5)
        if thumb and thumb.SetHeight then thumb:SetHeight(thumbH) end

        local offset = ClampScrollValue(scroll:GetVerticalScroll() or 0, maxScroll)
        if offset ~= (scroll:GetVerticalScroll() or 0) and rawSetVerticalScroll then
            rawSetVerticalScroll(scroll, offset)
        end
        bar._msuf2Refreshing = true
        bar:SetValue(offset)
        bar._msuf2Refreshing = nil
        Paint(bar._msuf2Hover)
    end

    scroll._msuf2RefreshScrollBar = Refresh
    scroll.SetVerticalScroll = function(self, offset)
        local maxScroll = self._msuf2MaxScroll
        if maxScroll == nil then
            local child = self.GetScrollChild and self:GetScrollChild()
            local childH = (child and child.GetHeight and child:GetHeight()) or 0
            local frameH = (self.GetHeight and self:GetHeight()) or 0
            maxScroll = math.max(0, childH - frameH)
        end
        rawSetVerticalScroll(self, ClampScrollValue(offset, maxScroll))
        if self._msuf2RefreshScrollBar then self:_msuf2RefreshScrollBar() end
    end

    local function ScrollBy(delta)
        if not delta or delta == 0 then return end
        local step = 64
        if IsShiftKeyDown and IsShiftKeyDown() then step = 180 end
        if IsControlKeyDown and IsControlKeyDown() then step = math.max(step, (scroll.GetHeight and scroll:GetHeight()) or step) end
        scroll:SetVerticalScroll((scroll:GetVerticalScroll() or 0) - delta * step)
    end

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta) ScrollBy(delta) end)
    local wheelChild = scroll.GetScrollChild and scroll:GetScrollChild()
    if wheelChild and wheelChild.EnableMouseWheel then
        wheelChild:EnableMouseWheel(true)
        wheelChild:SetScript("OnMouseWheel", function(_, delta) ScrollBy(delta) end)
    end
    bar:EnableMouseWheel(true)
    bar:SetScript("OnMouseWheel", function(_, delta) ScrollBy(delta) end)
    bar:SetScript("OnEnter", function(self)
        self._msuf2Hover = true
        Paint(true)
    end)
    bar:SetScript("OnLeave", function(self)
        self._msuf2Hover = nil
        Paint(false)
    end)
    bar:SetScript("OnValueChanged", function(self, value)
        if self._msuf2Refreshing then return end
        local maxScroll = scroll._msuf2MaxScroll or 0
        if rawSetVerticalScroll then rawSetVerticalScroll(scroll, ClampScrollValue(value, maxScroll)) end
        Refresh()
    end)
    scroll:HookScript("OnScrollRangeChanged", Refresh)
    scroll:HookScript("OnSizeChanged", Refresh)
    if bar.HookScript then bar:HookScript("OnShow", function() Paint(bar._msuf2Hover) end) end

    Refresh()
    scroll._msuf2ScrollBar = bar
    return bar
end
