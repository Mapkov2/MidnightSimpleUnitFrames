local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
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
    glassShell = { 0.040, 0.050, 0.095, 0.940 },
    glassRail = { 0.040, 0.052, 0.100, 0.740 },
    glassHost = { 0.045, 0.056, 0.105, 0.660 },
    glassStatus = { 0.048, 0.060, 0.115, 0.560 },
    glassPopup = { 0.010, 0.014, 0.026, 0.940 },
}

T.fontBump = T.fontBump or 1

T.navIconGrid = {
    home = { 0, 0 },
    uf_player = { 1, 0 }, uf_target = { 3, 0 }, uf_targettarget = { 2, 0 }, uf_focustarget = { 2, 0 },
    uf_focus = { 2, 0 }, uf_boss = { 6, 2 }, uf_pet = { 6, 0 },
    opt_bars = { 7, 0 }, opt_fonts = { 0, 1 }, auras3 = { 3, 1 },
    opt_castbar = { 2, 1 }, opt_misc = { 4, 2 }, opt_colors = { 4, 1 },
    classpower = { 0, 2 }, gameplay = { 7, 1 },
    groupframes = { 1, 2 }, gf_layout = { 2, 2 }, gf_bars = { 3, 2 }, gf_auras = { 3, 1 }, gf_indicators = { 6, 1 },
    modules = { 4, 2 }, profiles = { 5, 2 },
}

T.navIconColors = {
    home = { 0.30, 0.60, 1.00 },
    uf_player = { 0.40, 0.78, 0.98 }, uf_target = { 0.40, 0.78, 0.98 }, uf_targettarget = { 0.40, 0.78, 0.98 }, uf_focustarget = { 0.40, 0.78, 0.98 },
    uf_focus = { 0.40, 0.78, 0.98 }, uf_boss = { 0.40, 0.78, 0.98 }, uf_pet = { 0.40, 0.78, 0.98 },
    opt_bars = { 0.88, 0.74, 0.36 }, opt_fonts = { 0.88, 0.74, 0.36 }, auras3 = { 0.88, 0.74, 0.36 },
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
    if type(MSUF.GetEffectiveLocale) == "function" then return MSUF.GetEffectiveLocale() end
    return MSUF.LOCALE or ((type(GetLocale) == "function" and GetLocale()) or "enUS")
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
    if type(MSUF.Translate) == "function" then
        local translated = MSUF.Translate(text)
        TrackLocaleKey(text, translated ~= text)
        return translated
    end
    local locale = MSUF.L or _G.MSUF_L
    if type(locale) == "table" then
        local direct = rawget(locale, text)
        if direct ~= nil then
            TrackLocaleKey(text, true)
            return direct
        end
    end
    if type(MSUF.TR) == "function" then
        local translated = MSUF.TR(text)
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
    return (type(GetLocale) == "function" and GetLocale()) or MSUF.CLIENT_LOCALE or "enUS"
end

local function IsSupportedLocale(locale)
    local supported = MSUF.SUPPORTED_LOCALES
    return type(locale) == "string" and type(supported) == "table" and supported[locale] == true
end

function M.GetLocaleDropdownValues()
    local names = MSUF.LOCALE_NAMES or {}
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
    if type(MSUF.SetLocale) == "function" then
        return MSUF.SetLocale(locale), selected
    end
    MSUF.LOCALE = locale
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

local GLASS_VARIANTS = {
    shell = {
        tint = { 0.026, 0.034, 0.068, 0.22 },
        wash = { 0.080, 0.120, 0.220, 0.090 },
        depth = { 0.015, 0.020, 0.050, 0.16 },
        grain = { 0.070, 0.085, 0.145, 0.060 },
        top = { 0.270, 0.720, 1.000, 0.24 },
        bottom = { 0.000, 0.000, 0.000, 0.30 },
    },
    rail = {
        tint = { 0.018, 0.026, 0.056, 0.18 },
        wash = { 0.070, 0.100, 0.210, 0.085 },
        grain = { 0.060, 0.070, 0.130, 0.055 },
        top = { 0.260, 0.650, 1.000, 0.18 },
        bottom = { 0.000, 0.000, 0.000, 0.24 },
    },
    host = {
        tint = { 0.020, 0.030, 0.065, 0.160 },
        wash = { 0.070, 0.110, 0.220, 0.075 },
        depth = { 0.020, 0.018, 0.060, 0.120 },
        grain = { 0.070, 0.065, 0.130, 0.045 },
        top = { 0.260, 0.720, 1.000, 0.16 },
        bottom = { 0.000, 0.000, 0.000, 0.26 },
    },
    status = {
        tint = { 0.020, 0.030, 0.060, 0.20 },
        wash = { 0.080, 0.120, 0.230, 0.080 },
        top = { 0.300, 0.800, 1.000, 0.24 },
        bottom = { 0.000, 0.000, 0.000, 0.20 },
    },
    popup = {
        tint = { 0.010, 0.014, 0.026, 0.22 },
        wash = { 0.060, 0.110, 0.220, 0.100 },
        grain = { 0.070, 0.080, 0.130, 0.060 },
        top = { 0.300, 0.820, 1.000, 0.26 },
        bottom = { 0.000, 0.000, 0.000, 0.28 },
    },
    card = {
        tint = { 0.014, 0.020, 0.040, 0.120 },
        wash = { 0.045, 0.080, 0.160, 0.045 },
        top = { 0.250, 0.640, 0.920, 0.12 },
        bottom = { 0.000, 0.000, 0.000, 0.16 },
    },
}

T.motion = T.motion or {}
local function DefaultMotion(key, value)
    if T.motion[key] == nil then T.motion[key] = value end
end
DefaultMotion("fast", 0.085)
DefaultMotion("standard", 0.120)
DefaultMotion("soft", 0.160)
DefaultMotion("dropdownIn", 0.105)
DefaultMotion("dropdownOut", 0.085)
DefaultMotion("popupIn", 0.120)
DefaultMotion("popupOut", 0.100)
DefaultMotion("focusIn", 0.135)
DefaultMotion("focusOut", 0.110)
DefaultMotion("accordionIn", 0.120)
DefaultMotion("accordionOut", 0.095)
DefaultMotion("contentIn", 0.105)
DefaultMotion("contentOut", 0.085)
DefaultMotion("controlFocusIn", 0.085)
DefaultMotion("controlFocusOut", 0.080)
DefaultMotion("controlFeedback", 0.145)

T.dropdownMotion = T.dropdownMotion or {}
if T.dropdownMotion.listFadeIn == nil then T.dropdownMotion.listFadeIn = T.motion.dropdownIn end
if T.dropdownMotion.listFadeOut == nil then T.dropdownMotion.listFadeOut = T.motion.dropdownOut end
if T.dropdownMotion.focusFadeIn == nil then T.dropdownMotion.focusFadeIn = T.motion.focusIn end
if T.dropdownMotion.focusFadeOut == nil then T.dropdownMotion.focusFadeOut = T.motion.focusOut end

T.motionProfiles = T.motionProfiles or {}
local function DefaultMotionProfile(key, spec)
    if T.motionProfiles[key] == nil then T.motionProfiles[key] = spec end
end
DefaultMotionProfile("dropdownIn", { type = "alpha", fromAlpha = 0, toAlpha = 1, duration = "dropdownIn", smoothing = "OUT" })
DefaultMotionProfile("dropdownOut", { type = "alpha", fromCurrent = true, toAlpha = 0, duration = "dropdownOut", smoothing = "IN" })
DefaultMotionProfile("popupIn", { type = "alpha", fromAlpha = 0, toAlpha = 1, duration = "popupIn", smoothing = "OUT" })
DefaultMotionProfile("popupOut", { type = "alpha", fromCurrent = true, toAlpha = 0, duration = "popupOut", smoothing = "IN" })
DefaultMotionProfile("focusIn", { type = "alpha", fromCurrent = true, toAlpha = 1, duration = "focusIn", smoothing = "OUT" })
DefaultMotionProfile("focusOut", { type = "alpha", fromCurrent = true, toAlpha = 0, duration = "focusOut", smoothing = "IN" })
DefaultMotionProfile("accordionIn", { type = "alpha", fromAlpha = 0, toAlpha = 1, duration = "accordionIn", smoothing = "OUT" })
DefaultMotionProfile("accordionOut", { type = "alpha", fromCurrent = true, toAlpha = 0, duration = "accordionOut", smoothing = "IN" })
DefaultMotionProfile("contentIn", { type = "alpha", fromAlpha = 0, toAlpha = 1, duration = "contentIn", smoothing = "OUT" })
DefaultMotionProfile("contentOut", { type = "alpha", fromCurrent = true, toAlpha = 0, duration = "contentOut", smoothing = "IN" })
DefaultMotionProfile("controlFocusIn", { type = "alpha", fromCurrent = true, toAlpha = 1, duration = "controlFocusIn", smoothing = "OUT" })
DefaultMotionProfile("controlFocusOut", { type = "alpha", fromCurrent = true, toAlpha = 0, duration = "controlFocusOut", smoothing = "IN" })
DefaultMotionProfile("controlFeedback", { type = "alpha", fromCurrent = true, toAlpha = 0, duration = "controlFeedback", smoothing = "OUT" })

T.materials = T.materials or {}
local function DefaultMaterial(key, spec)
    if T.materials[key] == nil then T.materials[key] = spec end
end
DefaultMaterial("shell", { bg = T.colors.glassShell, border = T.colors.border, glass = "shell" })
DefaultMaterial("rail", { bg = T.colors.glassRail, border = T.colors.borderSoft, glass = "rail" })
DefaultMaterial("host", { bg = T.colors.glassHost, border = T.colors.borderSoft, glass = "host" })
DefaultMaterial("status", { bg = T.colors.glassStatus, border = T.colors.borderSoft, glass = "status" })
DefaultMaterial("card", { bg = T.colors.panel2, border = T.colors.cardBorder or T.colors.borderSoft, glass = "card" })
DefaultMaterial("popup", { bg = T.colors.glassPopup, border = { 0.140, 0.220, 0.600, 0.88 }, glass = "popup" })
DefaultMaterial("focus", { veil = "dropdown" })

-- WoW addon frames cannot blur what is already behind them, so dropdown focus uses
-- a shared neutral veil instead of page-specific fake blur layers.
T.focusVeils = T.focusVeils or {}
T.focusVeils.dropdown = T.focusVeils.dropdown or {
    { key = "_msuf2FocusDim", layer = "BACKGROUND", subLevel = 0, color = { 0.000, 0.000, 0.000, 0.180 } },
    { key = "_msuf2FocusHaze", layer = "BACKGROUND", subLevel = 1, color = { 0.010, 0.014, 0.026, 0.055 } },
    { key = "_msuf2FocusSmearA", layer = "BORDER", subLevel = 0, texture = "bgSmooth", points = { -5, 5, 5, -5 }, color = { 0.018, 0.026, 0.052, 0.040 }, blend = "BLEND" },
    { key = "_msuf2FocusSmearB", layer = "BORDER", subLevel = 1, texture = "bgSmooth", points = { 4, -4, -4, 4 }, texCoord = { 0, 0, 1, 0, 0, 1, 1, 1 }, color = { 0.014, 0.022, 0.046, 0.032 }, blend = "BLEND" },
    { key = "_msuf2FocusWash", layer = "BORDER", subLevel = 2, texture = "bgSmooth", color = { 0.024, 0.034, 0.068, 0.050 }, blend = "BLEND" },
    { key = "_msuf2FocusGrain", layer = "BORDER", subLevel = 3, texture = "bgCharcoal", color = { 0.035, 0.040, 0.070, 0.070 }, blend = "BLEND" },
}

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
        tex = frame:CreateTexture(nil, spec.layer or "BORDER", nil, spec.subLevel or 0)
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
        if T.media and T.media[texture] then texture = T.media[texture] end
        tex:SetTexture(texture)
        if spec.color and tex.SetVertexColor then
            tex:SetVertexColor(spec.color[1], spec.color[2], spec.color[3], spec.color[4] or 1)
        end
    else
        ColorTexture(tex, spec.color)
    end

    local tc = spec.texCoord
    if tc and tex.SetTexCoord then
        tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4], tc[5], tc[6], tc[7], tc[8])
    end
    if tex.SetBlendMode then tex:SetBlendMode(spec.blend or "BLEND") end
    if tex.Show then tex:Show() end
end

function T.ApplyFocusVeil(frame, variant)
    local veil = T.focusVeils and T.focusVeils[variant or "dropdown"]
    if type(veil) ~= "table" then return frame end
    for i = 1, #veil do
        ApplyFocusVeilLayer(frame, veil[i])
    end
    return frame
end

function T.MotionDuration(name, fallback)
    if type(name) == "number" then return name end
    local profile = type(name) == "string" and T.motionProfiles and T.motionProfiles[name] or nil
    local key = profile and profile.duration or name
    local value = key and T.motion and T.motion[key]
    return tonumber(value) or tonumber(fallback) or T.motion.standard or 0.120
end

function T.PlayAlpha(frame, fromAlpha, toAlpha, duration, onFinished, smoothing)
    if not (frame and frame.SetAlpha and frame.CreateAnimationGroup) then
        if frame and frame.SetAlpha then frame:SetAlpha(toAlpha or 1) end
        if type(onFinished) == "function" then onFinished(frame) end
        return
    end

    local group = frame._msuf2AlphaFade
    local anim = frame._msuf2AlphaFadeAnim
    if not group then
        group = frame:CreateAnimationGroup()
        anim = group:CreateAnimation("Alpha")
        frame._msuf2AlphaFade = group
        frame._msuf2AlphaFadeAnim = anim
    elseif group.Stop then
        group:SetScript("OnFinished", nil)
        group:Stop()
    end

    if anim.SetFromAlpha then anim:SetFromAlpha(fromAlpha or 0) end
    if anim.SetToAlpha then anim:SetToAlpha(toAlpha or 1) end
    if anim.SetDuration then anim:SetDuration(tonumber(duration) or T.motion.standard or 0.12) end
    if anim.SetSmoothing then pcall(anim.SetSmoothing, anim, smoothing or ((toAlpha or 1) > (fromAlpha or 0) and "OUT" or "IN")) end
    group:SetScript("OnFinished", function()
        if frame.SetAlpha then frame:SetAlpha(toAlpha or 1) end
        if type(onFinished) == "function" then onFinished(frame) end
    end)
    frame:SetAlpha(fromAlpha or 0)
    if frame.Show then frame:Show() end
    group:Play()
end

function T.PlayMotion(frame, motion, opts)
    opts = opts or {}
    local profile = type(motion) == "table" and motion or (T.motionProfiles and T.motionProfiles[motion])
    if type(profile) ~= "table" or (profile.type and profile.type ~= "alpha") then
        local toAlpha = opts.toAlpha
        if toAlpha == nil then toAlpha = 1 end
        return T.PlayAlpha(frame, opts.fromAlpha or 0, toAlpha, opts.duration or T.MotionDuration(motion), opts.onFinished, opts.smoothing)
    end

    local fromAlpha = opts.fromAlpha
    if fromAlpha == nil then
        if profile.fromCurrent and frame and frame.GetAlpha then
            fromAlpha = frame:GetAlpha()
        else
            fromAlpha = profile.fromAlpha
        end
    end
    if fromAlpha == nil then fromAlpha = 0 end

    local toAlpha = opts.toAlpha
    if toAlpha == nil then toAlpha = profile.toAlpha end
    if toAlpha == nil then toAlpha = 1 end

    local duration = opts.duration or T.MotionDuration(profile.duration or motion)
    local smoothing = opts.smoothing or profile.smoothing
    return T.PlayAlpha(frame, fromAlpha, toAlpha, duration, opts.onFinished, smoothing)
end

local function IsDescendantOf(frame, ancestor)
    local current = frame
    while current do
        if current == ancestor then return true end
        current = current.GetParent and current:GetParent()
    end
    return false
end

local function FocusVeilRoot(owner, opts)
    opts = opts or {}
    if opts.root then return opts.root end
    local frame = M.frame
    if not (frame and frame.IsShown and frame:IsShown()) then return nil end
    local host = frame.host or frame._msufMirrorHost
    if host and owner and IsDescendantOf(owner, host) then return host end
    return frame.content or frame
end

local function EnsureFocusVeilFrame()
    if M._focusVeilFrame then return M._focusVeilFrame end
    local overlay = CreateFrame("Frame", "MSUF2FocusVeil", _G.UIParent)
    overlay:SetFrameStrata("TOOLTIP")
    overlay:SetToplevel(false)
    overlay:EnableMouse(false)
    overlay:Hide()
    M._focusVeilFrame = overlay
    return overlay
end

function M.ShowFocusVeil(owner, variant, opts)
    opts = opts or {}
    variant = variant or "dropdown"
    local root = FocusVeilRoot(owner, opts)
    if not root then
        if M.HideFocusVeil then M.HideFocusVeil(variant, { animated = true }) end
        return nil
    end

    local overlay = EnsureFocusVeilFrame()
    if T.ApplyMaterial and variant == "dropdown" then
        T.ApplyMaterial(overlay, "focus")
    elseif T.ApplyFocusVeil then
        T.ApplyFocusVeil(overlay, variant)
    end
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
    if overlay.SetFrameLevel then
        local ref = opts.referenceFrame
        local refLevel = ref and ref.GetFrameLevel and ref:GetFrameLevel()
        overlay:SetFrameLevel(math.max(0, (opts.frameLevel or (refLevel and refLevel - 1) or 119)))
    end

    local state = M._focusVeilState or {}
    M._focusVeilState = state
    state.owner = owner
    state.variant = variant
    state.hiding = nil
    overlay._msuf2FocusToken = (overlay._msuf2FocusToken or 0) + 1

    local fromAlpha = (overlay.IsShown and overlay:IsShown() and overlay.GetAlpha and overlay:GetAlpha()) or 0
    T.PlayMotion(overlay, "focusIn", { fromAlpha = fromAlpha, duration = opts.duration })
    return overlay
end

function M.HideFocusVeil(variant, opts)
    opts = opts or {}
    local overlay = M._focusVeilFrame
    if not overlay then return end
    local state = M._focusVeilState or {}
    M._focusVeilState = state
    if variant and state.variant and variant ~= state.variant and not opts.force then return end

    if opts.animated == false then
        state.hiding = nil
        state.owner = nil
        state.variant = nil
        overlay:Hide()
        overlay:SetAlpha(1)
        return
    end
    if state.hiding then return end
    if overlay.IsShown and not overlay:IsShown() then
        state.hiding = nil
        overlay:SetAlpha(1)
        return
    end

    state.hiding = true
    overlay._msuf2FocusToken = (overlay._msuf2FocusToken or 0) + 1
    local closeToken = overlay._msuf2FocusToken
    local fromAlpha = (overlay.GetAlpha and overlay:GetAlpha()) or 1
    T.PlayMotion(overlay, "focusOut", { fromAlpha = fromAlpha, duration = opts.duration, onFinished = function(self)
        if self._msuf2FocusToken ~= closeToken then return end
        state.hiding = nil
        state.owner = nil
        state.variant = nil
        self:Hide()
        self:SetAlpha(1)
    end })
end

local function GlassTexture(frame, key, layer, subLevel)
    if not (frame and frame.CreateTexture) then return nil end
    local tex = frame[key]
    if not tex then
        tex = frame:CreateTexture(nil, layer or "BACKGROUND", nil, subLevel or 0)
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

function T.ApplyGlass(frame, variant)
    if not (frame and frame.CreateTexture) then return frame end
    local spec = GLASS_VARIANTS[variant or "card"] or GLASS_VARIANTS.card
    if frame._msuf2GlassVariant == variant and frame._msuf2GlassApplied then return frame end
    frame._msuf2GlassVariant = variant
    frame._msuf2GlassApplied = true

    local tint = GlassTexture(frame, "_msuf2GlassTint", "BORDER", 0)
    PlaceGlassFill(tint, frame, 2)
    ColorTexture(tint, spec.tint)
    if tint and tint.Show then tint:Show() end

    local wash = GlassTexture(frame, "_msuf2GlassWash", "BORDER", 1)
    if spec.wash then
        PlaceGlassFill(wash, frame, 3)
        wash:SetTexture(T.media.bgSmooth or "Interface\\Buttons\\WHITE8X8")
        if wash.SetVertexColor then wash:SetVertexColor(spec.wash[1], spec.wash[2], spec.wash[3], spec.wash[4] or 1) end
        if wash.SetBlendMode then wash:SetBlendMode("ADD") end
        if wash.Show then wash:Show() end
    elseif wash.Hide then
        wash:Hide()
    end

    local depth = GlassTexture(frame, "_msuf2GlassDepth", "BORDER", 2)
    if spec.depth then
        PlaceGlassFill(depth, frame, 3)
        depth:SetTexture(T.media.bgSmooth or "Interface\\Buttons\\WHITE8X8")
        depth:SetTexCoord(0, 0, 1, 0, 0, 1, 1, 1)
        if depth.SetVertexColor then depth:SetVertexColor(spec.depth[1], spec.depth[2], spec.depth[3], spec.depth[4] or 1) end
        if depth.SetBlendMode then depth:SetBlendMode("BLEND") end
        if depth.Show then depth:Show() end
    elseif depth.Hide then
        depth:Hide()
    end

    local grain = GlassTexture(frame, "_msuf2GlassGrain", "BORDER", 3)
    if spec.grain then
        PlaceGlassFill(grain, frame, 2)
        grain:SetTexture(T.media.bgCharcoal or "Interface\\Buttons\\WHITE8X8")
        if grain.SetVertexColor then grain:SetVertexColor(spec.grain[1], spec.grain[2], spec.grain[3], spec.grain[4] or 1) end
        if grain.SetBlendMode then grain:SetBlendMode("BLEND") end
        if grain.Show then grain:Show() end
    elseif grain.Hide then
        grain:Hide()
    end

    local top = GlassTexture(frame, "_msuf2GlassTopLine", "ARTWORK", 0)
    PlaceGlassLine(top, frame, "TOP", 1)
    ColorTexture(top, spec.top)
    if top and top.Show then top:Show() end

    local bottom = GlassTexture(frame, "_msuf2GlassBottomLine", "ARTWORK", 0)
    PlaceGlassLine(bottom, frame, "BOTTOM", 1)
    ColorTexture(bottom, spec.bottom)
    if bottom and bottom.Show then bottom:Show() end

    return frame
end

function T.ApplyMaterial(frame, material)
    if not frame then return frame end
    local spec = type(material) == "table" and material or (T.materials and T.materials[material or "card"])
    if type(spec) ~= "table" then return frame end
    if spec.bg or spec.border then
        T.ApplyBackdrop(frame, spec.bg or T.colors.panel, spec.border or T.colors.borderSoft)
    end
    if spec.glass and T.ApplyGlass then T.ApplyGlass(frame, spec.glass) end
    if spec.veil and T.ApplyFocusVeil then T.ApplyFocusVeil(frame, spec.veil) end
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

    if T.ApplyMaterial then
        T.ApplyMaterial(frame, "shell")
        if host and host ~= frame then T.ApplyMaterial(host, "host") end
        if nav then T.ApplyMaterial(nav, "rail") end
    elseif T.ApplyGlass then
        T.ApplyGlass(frame, "shell")
        if host and host ~= frame then T.ApplyGlass(host, "host") end
        if nav then T.ApplyGlass(nav, "rail") end
    end

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
    local active = enabled and slider._msuf2SliderActive and true or false
    local alpha = enabled and 1 or 0.45
    local accent = T.colors.accent
    local edge = T.colors.border or T.colors.borderSoft

    if slider._msufTrack then
        SetSliderTextureColor(slider._msufTrack, active and 0.045 or 0.035, active and 0.058 or 0.043, active and 0.098 or 0.078, 0.98 * alpha)
        if slider._msufTrack.Show then slider._msufTrack:Show() end
    end
    if slider._msufTrackTop then
        SetSliderTextureColor(slider._msufTrackTop, edge[1], edge[2], edge[3], (active and 1.00 or hovered and 0.88 or 0.58) * alpha)
        slider._msufTrackTop:Show()
    end
    if slider._msufTrackBottom then
        SetSliderTextureColor(slider._msufTrackBottom, edge[1], edge[2], edge[3], (active and 0.54 or 0.34) * alpha)
        slider._msufTrackBottom:Show()
    end
    if slider._msufFill then
        SetSliderTextureColor(slider._msufFill, accent[1], accent[2], accent[3], (active and 1.00 or hovered and 0.92 or 0.76) * alpha)
        if slider._msufFill.Show then slider._msufFill:Show() end
    end
    if slider._msufFillGlow then
        SetSliderTextureColor(slider._msufFillGlow, accent[1], accent[2], accent[3], (active and 0.28 or hovered and 0.16 or 0.08) * alpha)
        slider._msufFillGlow:Show()
    end

    local thumb = slider.GetThumbTexture and slider:GetThumbTexture()
    if thumb then
        thumb:SetTexture(T.media.sliderThumb or "Interface\\Buttons\\WHITE8X8")
        thumb:SetTexCoord(0, 1, 0, 1)
        thumb:SetSize(active and 20 or (hovered and 19 or 18), active and 20 or (hovered and 19 or 18))
        if thumb.SetVertexColor then
            local mul = active and 1.12 or hovered and 1.06 or 1
            thumb:SetVertexColor(math.min(accent[1] * mul, 1), math.min(accent[2] * mul, 1), math.min(accent[3] * mul, 1), alpha)
        end
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
        slider:HookScript("OnMouseDown", function(self)
            self._msuf2SliderActive = true
            T.StyleSlider(self)
        end)
        slider:HookScript("OnMouseUp", function(self)
            self._msuf2SliderActive = nil
            T.StyleSlider(self)
        end)
        slider:HookScript("OnDisable", function(self)
            self._msuf2SliderActive = nil
            self._msuf2SliderHovered = nil
            T.StyleSlider(self)
        end)
        slider:HookScript("OnEnable", function(self)
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
    local UI = MSUF and MSUF.UI
    local styleText = (_G and _G.MSUF_StyleToggleText) or (MSUF and MSUF.MSUF_StyleToggleText) or (UI and UI.StyleToggleText)
    if type(styleText) == "function" then pcall(styleText, checkButton) end

    local function HideQuietCheckboxTexture(texture)
        if not texture then return end
        if texture.SetAlpha then texture:SetAlpha(0) end
        if texture.Hide then texture:Hide() end
    end

    local function HideQuietCheckboxNative()
        if not checkButton._msuf2QuietCheckBox then return end
        HideQuietCheckboxTexture(checkButton.GetNormalTexture and checkButton:GetNormalTexture())
        HideQuietCheckboxTexture(checkButton.GetPushedTexture and checkButton:GetPushedTexture())
        HideQuietCheckboxTexture(checkButton.GetHighlightTexture and checkButton:GetHighlightTexture())
        HideQuietCheckboxTexture(checkButton.GetDisabledTexture and checkButton:GetDisabledTexture())
    end

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
        local oldStyle = (_G and _G.MSUF_StyleCheckmark) or (MSUF and MSUF.MSUF_StyleCheckmark) or (UI and UI.StyleCheckmark)
        if type(oldStyle) == "function" then
            pcall(oldStyle, checkButton)
        end
        HideQuietCheckboxNative()

        local check = checkButton.GetCheckedTexture and checkButton:GetCheckedTexture()
        if not check and checkButton.GetName and checkButton:GetName() then check = _G[checkButton:GetName() .. "Check"] end
        if check and check.SetTexture then
            local h = (checkButton.GetHeight and checkButton:GetHeight()) or 24
            local sz = checkButton._msuf2QuietCheckBox and 14 or math.floor(h * 0.8 + 0.5)
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
    HideQuietCheckboxNative()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            local UI2 = MSUF and MSUF.UI
            local laterText = (_G and _G.MSUF_StyleToggleText) or (MSUF and MSUF.MSUF_StyleToggleText) or (UI2 and UI2.StyleToggleText)
            if type(laterText) == "function" then pcall(laterText, checkButton) end
            ApplyCheckTexture()
            HideQuietCheckboxNative()
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
