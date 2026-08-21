local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local T = M.Theme or {}
M.Theme = T
local WL = M.WordList
local SharedUI = (type(MSUF) == "table" and MSUF.UI) or _G.MSUF_UI

local InvokeThemeBoundary = M.InvokeBoundary or pcall

T.fontSizes = (SharedUI and SharedUI.fontSizes) or T.fontSizes or {
    micro = 9, caption = 11, supporting = 11, body = 13, control = 13,
    card = 13, accordion = 15, section = 15, heading = 17, hero = 21,
}
function T.FontSize(role, fallback)
    if SharedUI and type(SharedUI.FontSize) == "function" then return SharedUI.FontSize(role, fallback) end
    return T.fontSizes[role] or tonumber(fallback) or T.fontSizes.body
end
function T.NormalizeFontSize(size)
    if SharedUI and type(SharedUI.NormalizeFontSize) == "function" then return SharedUI.NormalizeFontSize(size) end
    local order, value = { 9, 11, 13, 15, 17, 21 }, tonumber(size) or T.fontSizes.body
    local best, distance = order[1], math.huge
    for i = 1, #order do
        local nextDistance = math.abs(value - order[i])
        if nextDistance < distance or (nextDistance == distance and order[i] > best) then
            best, distance = order[i], nextDistance
        end
    end
    return best
end
T.spacing = (SharedUI and SharedUI.spacing) or T.spacing or {
    hairline = 1, optical = 2, xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32,
}
function T.Space(role, fallback)
    if SharedUI and type(SharedUI.Space) == "function" then return SharedUI.Space(role, fallback) end
    local value = type(role) == "string" and T.spacing[role] or tonumber(role)
    return tonumber(value) or tonumber(fallback) or T.spacing.sm
end

-- Menu2 theme and widget styling layer.
-- Owns reusable visual primitives, locale-aware labels, and skin helpers for the options UI.
-- Page modules should call this layer instead of restyling frames ad hoc.
local GLASS_VARIANTS = T.glassVariants or {}
T.collapseHintClickHideThreshold = T.collapseHintClickHideThreshold or 8
local function Template()
    return _G.BackdropTemplateMixin and "BackdropTemplate" or nil
end
local ENGLISH_LOCALES = { enUS = true, enGB = true }
local LOCALE_ORDER = { "enUS", "enGB", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }
local function ActiveLocale()
    if type(MSUF.GetEffectiveLocale) == "function" then return MSUF.GetEffectiveLocale() end
    return MSUF.LOCALE or ((type(GetLocale) == "function" and GetLocale()) or "enUS")
end
-- The effective locale is immutable for the session (MSUF.SetLocale requires a
-- reload), so the English check is resolved once instead of per tracked key.
local activeLocaleIsEnglish
local function TrackLocaleKey(key, translated)
    -- Locale coverage is collected while UI text is resolved. This gives diagnostics a cheap
    -- way to list missing translations without a separate scan of every page file.
    M.localeKeys = M.localeKeys or {}
    M.localeKeys[key] = true
    if activeLocaleIsEnglish == nil then
        activeLocaleIsEnglish = ENGLISH_LOCALES[ActiveLocale()] == true
    end
    if activeLocaleIsEnglish or translated then return end
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
function M.ShowLocaleReloadRequired()
    if not (_G.StaticPopupDialogs and _G.StaticPopup_Show and M.InstallStaticPopup) then
        if _G.print then
            _G.print(M.Tr("|cffffd700MSUF:|r Menu language saved. Reload the UI to apply it."))
        end
        return false
    end
    M.InstallStaticPopup("MSUF2_LOCALE_RELOAD_REQUIRED", {
        text = M.Tr("Menu language was changed. MSUF loads only one language per session, so a UI reload is required to apply it.\n\nReload now?"),
        button1 = _G.RELOADUI or _G.RELOAD or M.Tr("Reload"),
        button2 = _G.CANCEL or M.Tr("Not now"),
        OnAccept = function()
            if type(_G.ReloadUI) == "function" then _G.ReloadUI() end
        end,
    })
    _G.StaticPopup_Show("MSUF2_LOCALE_RELOAD_REQUIRED")
    return true
end
function M.ApplyLocaleSelection(selection)
    local selected = selection or M.GetLocaleSelection()
    local locale = M.ResolveLocaleSelection(selected)
    local active, reloadRequired = MSUF.LOCALE, locale ~= MSUF.LOCALE
    if type(MSUF.SetLocale) == "function" then
        active, reloadRequired = MSUF.SetLocale(locale)
    end
    if selection ~= nil then
        if reloadRequired then
            M.ShowLocaleReloadRequired()
        elseif type(_G.StaticPopup_Hide) == "function" then
            _G.StaticPopup_Hide("MSUF2_LOCALE_RELOAD_REQUIRED")
        end
    end
    return active or MSUF.LOCALE, selected, reloadRequired
end
M.Format = M.Format or function(text, ...)
    local translated = M.Tr(text)
    if select("#", ...) == 0 then return translated end
    return string.format(translated, ...)
end
local WHITE8 = "Interface\\Buttons\\WHITE8X8"
local function SetColor(tex, c)
    if tex and c then tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
end
local function SmoothTexture(tex)
    if not tex then return end
    if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
    if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
end
local DEFAULT_PANEL_COLOR = { 0.04, 0.05, 0.08, 1 }
local gradientColorCache = {}
local function GradientColor(r, g, b, a)
    local byG = gradientColorCache[r]
    if not byG then byG = {}; gradientColorCache[r] = byG end
    local byB = byG[g]
    if not byB then byB = {}; byG[g] = byB end
    local byA = byB[b]
    if not byA then byA = {}; byB[b] = byA end
    local color = byA[a]
    if not color then
        color = _G.CreateColor(r, g, b, a)
        byA[a] = color
    end
    return color
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
    if tex.SetGradientAlpha then
        tex._msuf2TextureMode = "gradient"
        tex._msuf2GradientOrientation = orientation
        tex._msuf2GradientFR, tex._msuf2GradientFG, tex._msuf2GradientFB, tex._msuf2GradientFA = fr, fg, fb, fa
        tex._msuf2GradientTR, tex._msuf2GradientTG, tex._msuf2GradientTB, tex._msuf2GradientTA = tr, tg, tb, ta
        tex:SetGradientAlpha(orientation, fr, fg, fb, fa, tr, tg, tb, ta)
        return true
    end
    if tex.SetGradient and _G.CreateColor then
        tex._msuf2TextureMode = "gradient"
        tex._msuf2GradientOrientation = orientation
        tex._msuf2GradientFR, tex._msuf2GradientFG, tex._msuf2GradientFB, tex._msuf2GradientFA = fr, fg, fb, fa
        tex._msuf2GradientTR, tex._msuf2GradientTG, tex._msuf2GradientTB, tex._msuf2GradientTA = tr, tg, tb, ta
        tex:SetGradient(orientation, GradientColor(fr, fg, fb, fa), GradientColor(tr, tg, tb, ta))
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
M.AssignNamedValues(T, "Tr Template SetColor ShadeColor ApplyTextureGradient SetFillGradient",
    M.Tr, Template, SetColor, ShadeColor, ApplyTextureGradient, SetFillGradient)
local NO_MENU_FONT = {}
local menuFontCache = {}
local function MenuGeneralDB()
    if type(M.GetGeneralDB) == "function" then return M.GetGeneralDB() end
    local ensureDB = _G.MSUF_EnsureDB
    if type(ensureDB) == "function" then ensureDB() end
    local db = _G.MSUF_DB
    if type(db) ~= "table" then return nil end
    db.general = type(db.general) == "table" and db.general or {}
    return db.general
end
local function ResolveMenuFontPath(size, flags, role)
    local g = MenuGeneralDB()
    local key = type(g) == "table" and g.menuFontKey or nil
    if type(key) ~= "string" or key == "" then return nil end
    size = tonumber(size) or 14
    flags = flags or ""
    local cacheKey = key .. "|" .. tostring(size) .. "|" .. tostring(flags) .. "|" .. tostring(role or "")
    local cached = menuFontCache[cacheKey]
    if cached ~= nil then return cached ~= NO_MENU_FONT and cached or nil end
    local path = key
    if not (path:find("\\", 1, true) or path:find("/", 1, true)) then
        local getPath = _G.MSUF_ResolveFontKeyPath or _G.MSUF_GetFontPathForKey or (MSUF and MSUF.MSUF_GetFontPathForKey)
        if type(getPath) == "function" then path = getPath(key, size, flags) or path end
    end
    local resolveSafe = _G.MSUF_ResolveSafeFontPath
    if type(resolveSafe) == "function" then path = resolveSafe(path, size, flags, key) end
    if SharedUI and type(SharedUI.ResolveRoleFontPath) == "function" then
        path = SharedUI.ResolveRoleFontPath(path, role)
    end
    if type(path) ~= "string" or path == "" then path = nil end
    menuFontCache[cacheKey] = path or NO_MENU_FONT
    return path
end
function T.ClearMenuFontCache()
    menuFontCache = {}
end
local function NormalizeAppliedFontPath(path)
    if type(path) ~= "string" then return nil end
    return path:gsub("/", "\\"):lower()
end
local function FontPathMatches(expected, actual)
    if expected == actual then return true end
    local matches = _G.MSUF_FontPathMatches or _G.MSUF_FontPathEquals
    if type(matches) == "function" then
        local ok, same = InvokeThemeBoundary(matches, expected, actual)
        if ok and same == true then return true end
    end
    expected, actual = NormalizeAppliedFontPath(expected), NormalizeAppliedFontPath(actual)
    return expected ~= nil and actual ~= nil and expected == actual
end
local function FontHasRenderableText(fs)
    if not (fs and fs.GetText and fs.GetStringWidth) then return true end
    local text = fs:GetText()
    if type(text) ~= "string" or not text:find("%S") then return true end
    local width = fs:GetStringWidth()
    return type(width) ~= "number" or width > 0
end
local function FontApplicationMatches(fs, expectedFont, expectedSize, expectedFlags)
    local actualFont, actualSize, actualFlags = fs:GetFont()
    if not FontPathMatches(expectedFont, actualFont) then return false end
    if type(actualSize) == "number" and math.abs(actualSize - expectedSize) > 0.01 then return false end
    if tostring(actualFlags or "") ~= tostring(expectedFlags or "") then return false end
    return FontHasRenderableText(fs)
end
local function TryApplyStyledFont(fs, font, size, flags)
    if type(font) ~= "string" or font == "" then return false end
    local ok, applied = pcall(fs.SetFont, fs, font, size, flags)
    return ok and applied ~= false and FontApplicationMatches(fs, font, size, flags)
end
local function ApplyStyledFont(fs, force)
    if not (fs and fs.GetFont and fs.SetFont) then return false end
    local font, size, flags = fs:GetFont()
    if font and size and not fs._msuf2FontOriginal then fs._msuf2FontOriginal = { font = font, size = size, flags = flags } end
    local orig = fs._msuf2FontOriginal
    if not orig then return false end
    local role = fs._msuf2FontRole
    local bump = tonumber(fs._msuf2FontBump) or T.fontBump or 0
    local nextSize = role and T.FontSize(role)
        or T.NormalizeFontSize((tonumber(orig.size) or tonumber(size) or T.FontSize("body")) + bump)
    local nextFlags = orig.flags or flags or ""
    local menuFont = ResolveMenuFontPath(nextSize, nextFlags, role)
    local nextFont = menuFont or orig.font or font
    local fontKey = tostring(nextFont or "") .. "\030" .. tostring(nextSize or "") .. "\030" .. tostring(nextFlags or "")
    if not force and fs._msuf2AppliedFontKey == fontKey and FontApplicationMatches(fs, nextFont, nextSize, nextFlags) then
        return true
    end
    local applied = TryApplyStyledFont(fs, nextFont, nextSize, nextFlags)
    if not applied and nextFont ~= orig.font and orig.font then
        applied = TryApplyStyledFont(fs, orig.font, nextSize, nextFlags)
        if applied then fontKey = tostring(orig.font or "") .. "\030" .. tostring(nextSize or "") .. "\030" .. tostring(nextFlags or "") end
    end
    if applied and fs._msuf2DropdownDefaultFont then
        local appliedFont, appliedSize, appliedFlags = fs:GetFont()
        if appliedFont and appliedSize then
            fs._msuf2DropdownDefaultFont = { appliedFont, appliedSize, appliedFlags or "" }
        end
    end
    fs._msuf2AppliedFontKey = applied and fontKey or nil
    return applied
end
local function RegisterPageFontString(fs)
    local entry = M._msuf2FontCollectionEntry
    if type(entry) ~= "table" or fs._msuf2FontCollectionEntry == entry then return end
    local fontStrings = entry.fontStrings
    if type(fontStrings) ~= "table" then
        fontStrings = {}
        entry.fontStrings = fontStrings
    end
    fontStrings[#fontStrings + 1] = fs
    fs._msuf2FontCollectionEntry = entry
end
--- Apply only the font selected under Misc > MSUF menu font. This deliberately
--- leaves text color and shadow ownership with the caller so stateful surfaces
--- such as preview-layer chips keep their existing active/off/disabled paint.
function T.ApplyMenuFont(fs, bump, role)
    if not fs then return fs end
    RegisterPageFontString(fs)
    if role ~= nil then fs._msuf2FontRole = role end
    if fs.GetFont and fs.SetFont then
        fs._msuf2FontBump = tonumber(bump) or T.fontBump or 0
        ApplyStyledFont(fs)
    end
    return fs
end
function T.StyleFontString(fs, color, bump, role)
    if not fs then return fs end
    RegisterPageFontString(fs)
    if role ~= nil then fs._msuf2FontRole = role end
    local c = color or T.colors.text
    local cr, cg, cb, ca = c[1], c[2], c[3], c[4] or 1
    if fs.SetTextColor
        and (fs._msuf2TextColorR ~= cr
            or fs._msuf2TextColorG ~= cg
            or fs._msuf2TextColorB ~= cb
            or fs._msuf2TextColorA ~= ca)
    then
        fs._msuf2TextColorR, fs._msuf2TextColorG, fs._msuf2TextColorB, fs._msuf2TextColorA = cr, cg, cb, ca
        fs:SetTextColor(cr, cg, cb, ca)
    end
    if fs.SetShadowColor and fs._msuf2ShadowColorKey ~= "0:0:0:0.35" then
        fs._msuf2ShadowColorKey = "0:0:0:0.35"
        fs:SetShadowColor(0, 0, 0, 0.35)
    end
    if fs.SetShadowOffset and fs._msuf2ShadowOffsetKey ~= "1:-1" then
        fs._msuf2ShadowOffsetKey = "1:-1"
        fs:SetShadowOffset(1, -1)
    end
    if fs.GetFont and fs.SetFont then
        fs._msuf2FontBump = tonumber(bump) or T.fontBump or 0
        ApplyStyledFont(fs)
    end
    return fs
end
local function RefreshMenuFonts(root, seen, force)
    if not root or seen[root] then return end
    seen[root] = true
    if root._msuf2FontOriginal then ApplyStyledFont(root, force) end
    if root.GetRegions then
        local regions = { root:GetRegions() }
        for i = 1, #regions do
            local region = regions[i]
            if region and region._msuf2FontOriginal then ApplyStyledFont(region, force) end
        end
    end
    if root.GetChildren then
        local children = { root:GetChildren() }
        for i = 1, #children do RefreshMenuFonts(children[i], seen, force) end
    end
end
function T.RefreshMenuFonts(root, force, preserveCache)
    if preserveCache ~= true then T.ClearMenuFontCache() end
    local seen = {}
    if root then
        RefreshMenuFonts(root, seen, force == true)
        return
    end
    RefreshMenuFonts(M.frame, seen, force == true)
    RefreshMenuFonts(M.minimizedBar, seen, force == true)
end
function T.RefreshMenuFontStrings(fontStrings, force, preserveCache)
    if preserveCache ~= true then T.ClearMenuFontCache() end
    if type(fontStrings) ~= "table" then return false end
    for i = 1, #fontStrings do
        local fs = fontStrings[i]
        if fs and fs._msuf2FontOriginal then ApplyStyledFont(fs, force == true) end
    end
    return true
end
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
    local left = frame:CreateTexture(nil, layer, nil, subLevel)
    left:SetTexture(T.media.superellipse)
    left:SetTexCoord(0.00, 0.25, 0, 1)
    SmoothTexture(left)
    local middle = frame:CreateTexture(nil, layer, nil, subLevel)
    middle:SetTexture(T.media.superellipse)
    middle:SetTexCoord(0.25, 0.75, 0, 1)
    SmoothTexture(middle)
    local right = frame:CreateTexture(nil, layer, nil, subLevel)
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
    local h = (frame.GetHeight and frame:GetHeight()) or 22
    local fill = CreateSuperellipseParts(frame, fillLayer, 0)
    local border = CreateSuperellipseParts(frame, borderLayer, -1)
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
        -- Authored Midnight nav art uses compact corners rather than stadium
        -- caps. Accent-colored procedural nav states must keep that silhouette.
        if frame._msuf2NavItem then nextCapW = math.min(nextCapW, 6) end
        LayoutSuperellipseParts(fill, frame, p, nextCapW, rightPad)
        local bInset = math.max(0, p - 1)
        local borderInnerW = math.max(1, w - bInset * 2)
        local borderInnerH = math.max(1, h2 - bInset * 2)
        local borderCapW = math.min(math.floor(borderInnerH * 0.5 + 0.5), math.floor(borderInnerW * 0.5))
        if frame._msuf2NavItem then borderCapW = math.min(borderCapW, 6) end
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
    if frame.SetBackdrop then
        if frame._msuf2BackdropInfoApplied ~= BACKDROP_INFO then
            frame:SetBackdrop(BACKDROP_INFO)
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
            local tex = frame:CreateTexture(nil, "BACKGROUND")
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
    local veil = T.focusVeils and T.focusVeils[variant or "dropdown"]
    if type(veil) ~= "table" then return frame end
    for i = 1, #veil do
        ApplyFocusVeilLayer(frame, veil[i])
    end
    return frame
end
local function ClampMotionDuration(value, fallback)
    if T.ReducedMotionEnabled and T.ReducedMotionEnabled() then return 0.001 end
    value = tonumber(value) or tonumber(fallback) or T.motion.standard or 0.105
    local policy = T.motionPolicy or {}
    local minDur = tonumber(policy.min) or 0.045
    local maxDur = tonumber(policy.max) or 0.160
    if value < minDur then return minDur end
    if value > maxDur then return maxDur end
    return value
end
function T.ReducedMotionEnabled()
    if T.reduceMotion == true or T.reducedMotion == true then return true end
    local db = _G.MSUF_DB
    local general = type(db) == "table" and db.general or nil
    return type(general) == "table" and (general.reduceMotion == true or general.reducedMotion == true) or false
end
function T.MotionDuration(name, fallback)
    if type(name) == "number" then return ClampMotionDuration(name, fallback) end
    local profile = type(name) == "string" and T.motionProfiles and T.motionProfiles[name] or nil
    local key = profile and profile.duration or name
    local value = key and T.motion and T.motion[key]
    return ClampMotionDuration(value, fallback)
end
local menuAnimationGroups = T._menuAnimationGroups
if type(menuAnimationGroups) ~= "table" then
    menuAnimationGroups = setmetatable({}, { __mode = "k" })
    T._menuAnimationGroups = menuAnimationGroups
end
function T.TrackMenuAnimationGroup(group)
    if group then menuAnimationGroups[group] = true end
    return group
end
function T.StopAllMenuAnimations()
    local stopped = 0
    for group in pairs(menuAnimationGroups) do
        if group and type(group.Stop) == "function" then
            group:Stop()
            stopped = stopped + 1
        end
    end
    return stopped
end
local function StopAlphaMotion(frame)
    if not frame then return end
    local fade = frame._msuf2AlphaFade
    if fade and fade.Stop then
        if fade.SetScript then fade:SetScript("OnFinished", nil) end
        fade:Stop()
    end
    local scale = frame._msuf2AlphaScale
    if scale and scale.Stop then
        if scale.SetScript then scale:SetScript("OnFinished", nil) end
        scale:Stop()
    end
end
T.StopMotion = StopAlphaMotion
function T.PlayAlpha(frame, fromAlpha, toAlpha, duration, onFinished, smoothing)
    if not (frame and frame.SetAlpha and frame.CreateAnimationGroup) then
        if frame and frame.SetAlpha then frame:SetAlpha(toAlpha or 1) end
        if type(onFinished) == "function" then onFinished(frame) end
        return
    end
    if frame._msuf2AlphaScale and frame._msuf2AlphaScale.Stop then
        frame._msuf2AlphaScale:SetScript("OnFinished", nil)
        frame._msuf2AlphaScale:Stop()
    end
    local group = frame._msuf2AlphaFade
    local anim = frame._msuf2AlphaFadeAnim
    if not group then
        group = frame:CreateAnimationGroup()
        T.TrackMenuAnimationGroup(group)
        anim = group:CreateAnimation("Alpha")
        frame._msuf2AlphaFade = group
        frame._msuf2AlphaFadeAnim = anim
    elseif group.Stop then
        group:SetScript("OnFinished", nil)
        group:Stop()
    end
    if anim.SetFromAlpha then anim:SetFromAlpha(fromAlpha or 0) end
    if anim.SetToAlpha then anim:SetToAlpha(toAlpha or 1) end
    if anim.SetDuration then anim:SetDuration(ClampMotionDuration(duration, T.motion.standard)) end
    if anim.SetSmoothing then anim:SetSmoothing(smoothing or ((toAlpha or 1) > (fromAlpha or 0) and "OUT" or "IN")) end
    group:SetScript("OnFinished", function()
        if frame.SetAlpha then frame:SetAlpha(toAlpha or 1) end
        if type(onFinished) == "function" then onFinished(frame) end
    end)
    frame:SetAlpha(fromAlpha or 0)
    if frame.Show then frame:Show() end
    group:Play()
end
function T.PlayAlphaScale(frame, fromAlpha, toAlpha, duration, scaleFrom, scaleTo, onFinished, smoothing, origin)
    if not (frame and frame.SetAlpha and frame.CreateAnimationGroup) then
        if frame and frame.SetAlpha then frame:SetAlpha(toAlpha or 1) end
        if type(onFinished) == "function" then onFinished(frame) end
        return
    end
    if frame._msuf2AlphaFade and frame._msuf2AlphaFade.Stop then
        frame._msuf2AlphaFade:SetScript("OnFinished", nil)
        frame._msuf2AlphaFade:Stop()
    end
    if frame._msuf2AlphaScale and frame._msuf2AlphaScale.Stop then
        frame._msuf2AlphaScale:SetScript("OnFinished", nil)
        frame._msuf2AlphaScale:Stop()
    end
    local group = frame:CreateAnimationGroup()
    T.TrackMenuAnimationGroup(group)
    local alpha = group:CreateAnimation("Alpha")
    local scale = group:CreateAnimation("Scale")
    local dur = ClampMotionDuration(duration, T.motion.standard)
    local ok = alpha and scale
    if ok and alpha.SetFromAlpha then alpha:SetFromAlpha(fromAlpha or 0) end
    if ok and alpha.SetToAlpha then alpha:SetToAlpha(toAlpha or 1) end
    if ok and alpha.SetDuration then alpha:SetDuration(dur) end
    if ok and alpha.SetOrder then alpha:SetOrder(1) end
    if ok and alpha.SetSmoothing then alpha:SetSmoothing(smoothing or ((toAlpha or 1) > (fromAlpha or 0) and "OUT" or "IN")) end
    if ok and scale.SetScaleFrom and scale.SetScaleTo then
        scale:SetScaleFrom(scaleFrom or 1, scaleFrom or 1)
        scale:SetScaleTo(scaleTo or 1, scaleTo or 1)
    else
        ok = false
    end
    if ok and scale.SetDuration then scale:SetDuration(dur) end
    if ok and scale.SetOrder then scale:SetOrder(1) end
    if ok and scale.SetSmoothing then scale:SetSmoothing(smoothing or "OUT") end
    if ok and scale.SetOrigin then scale:SetOrigin(origin or "CENTER", 0, 0) end
    if not ok then
        if group.Stop then group:Stop() end
        return T.PlayAlpha(frame, fromAlpha, toAlpha, dur, onFinished, smoothing)
    end
    frame._msuf2AlphaScale = group
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
    local scaleFrom = opts.scaleFrom
    if scaleFrom == nil then scaleFrom = profile.scaleFrom end
    local scaleTo = opts.scaleTo
    if scaleTo == nil then scaleTo = profile.scaleTo end
    if scaleFrom ~= nil and scaleTo ~= nil then return T.PlayAlphaScale(frame, fromAlpha, toAlpha, duration, scaleFrom, scaleTo, opts.onFinished, smoothing, opts.scaleOrigin or profile.scaleOrigin) end
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
function M.ResetFocusVeil(variant, opts)
    opts = opts or {}
    local overlay = M._focusVeilFrame
    if not overlay then
        M._focusVeilState = nil
        return false
    end
    local state = M._focusVeilState
    if variant and state and state.variant and variant ~= state.variant and not opts.force then return false end
    overlay._msuf2FocusToken = (overlay._msuf2FocusToken or 0) + 1
    StopAlphaMotion(overlay)
    M._focusVeilState = nil
    overlay:Hide()
    overlay:ClearAllPoints()
    overlay:SetAlpha(1)
    return true
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
        return M.ResetFocusVeil(variant, opts)
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
        if texCoord and tex.SetTexCoord then tex:SetTexCoord(texCoord[1], texCoord[2], texCoord[3], texCoord[4], texCoord[5], texCoord[6], texCoord[7], texCoord[8]) end
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
        local tex = frame:CreateTexture(nil, "BACKGROUND", nil, 7)
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
        art.TL:ClearAllPoints(); art.T:ClearAllPoints(); art.TR:ClearAllPoints()
        art.L:ClearAllPoints(); art.C:ClearAllPoints(); art.R:ClearAllPoints()
        art.BL:ClearAllPoints(); art.B:ClearAllPoints(); art.BR:ClearAllPoints()
        art.TL:SetPoint("TOPLEFT", frame, "TOPLEFT", -os, os); art.TL:SetSize(c, c)
        art.TR:SetPoint("TOPRIGHT", frame, "TOPRIGHT", os, os); art.TR:SetSize(c, c)
        art.BL:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -os, -os); art.BL:SetSize(c, c)
        art.BR:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", os, -os); art.BR:SetSize(c, c)
        art.T:SetPoint("TOPLEFT", art.TL, "TOPRIGHT", 0, 0); art.T:SetPoint("BOTTOMRIGHT", art.TR, "BOTTOMLEFT", 0, 0)
        art.B:SetPoint("TOPLEFT", art.BL, "TOPRIGHT", 0, 0); art.B:SetPoint("BOTTOMRIGHT", art.BR, "BOTTOMLEFT", 0, 0)
        art.L:SetPoint("TOPLEFT", art.TL, "BOTTOMLEFT", 0, 0); art.L:SetPoint("BOTTOMRIGHT", art.BL, "TOPRIGHT", 0, 0)
        art.R:SetPoint("TOPLEFT", art.TR, "BOTTOMLEFT", 0, 0); art.R:SetPoint("BOTTOMRIGHT", art.BR, "TOPRIGHT", 0, 0)
        art.C:SetPoint("TOPLEFT", art.TL, "BOTTOMRIGHT", 0, 0); art.C:SetPoint("BOTTOMRIGHT", art.BR, "TOPLEFT", 0, 0)
    end
    art.Layout = Layout
    Layout()
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
    local path = mediaKey and T.media and T.media[mediaKey]
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
    local tinted = T.MenuAccentSurfacesTinted and T.MenuAccentSurfacesTinted()
    for i = 1, #PANEL_SLICES do
        local tex = art[PANEL_SLICES[i][1]]
        if tex then
            ConfigurePanelAssetColor(tex, tinted)
            tex:Show()
        end
    end
    if frame.SetBackdropColor then frame:SetBackdropColor(0, 0, 0, 0.001) end
    if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(0, 0, 0, 0.001) end
    frame._msuf2PanelAssetApplied = true
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
    local top = frame:CreateTexture(nil, "BORDER", nil, -8)
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -5)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -7, -5)
    if top.SetBlendMode then top:SetBlendMode("ADD") end
    local bottom = frame:CreateTexture(nil, "BORDER", nil, -8)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 6, 5)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 5)
    local leftGlint = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    leftGlint:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -4)
    leftGlint:SetHeight(2)
    leftGlint:SetTexture((T.media and T.media.gradH) or WHITE8)
    if leftGlint.SetTexCoord then leftGlint:SetTexCoord(0, 1, 0, 1) end
    if leftGlint.SetBlendMode then leftGlint:SetBlendMode("ADD") end
    local rightGlint = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    rightGlint:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -4)
    rightGlint:SetHeight(2)
    rightGlint:SetTexture((T.media and T.media.gradHRev) or WHITE8)
    if rightGlint.SetTexCoord then rightGlint:SetTexCoord(0, 1, 0, 1) end
    if rightGlint.SetBlendMode then rightGlint:SetBlendMode("ADD") end
    local cornerGlow = frame:CreateTexture(nil, "ARTWORK", nil, 0)
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
    if fadeIn.SetFromAlpha then fadeIn:SetFromAlpha(fromAlpha or 0.12) end
    if fadeIn.SetToAlpha then fadeIn:SetToAlpha(toAlpha or 0.78) end
    if fadeIn.SetDuration then fadeIn:SetDuration(1.10) end
    if fadeIn.SetSmoothing then fadeIn:SetSmoothing("OUT") end
    if fadeIn.SetOrder then fadeIn:SetOrder(1) end
    local fadeOut = group:CreateAnimation("Alpha")
    if fadeOut.SetFromAlpha then fadeOut:SetFromAlpha(toAlpha or 0.78) end
    if fadeOut.SetToAlpha then fadeOut:SetToAlpha(fromAlpha or 0.12) end
    if fadeOut.SetDuration then fadeOut:SetDuration(1.20) end
    if fadeOut.SetSmoothing then fadeOut:SetSmoothing("IN") end
    if fadeOut.SetOrder then fadeOut:SetOrder(2) end
    if delay and delay > 0 then
        if travel.SetStartDelay then travel:SetStartDelay(delay) end
        if fadeIn.SetStartDelay then fadeIn:SetStartDelay(delay) end
    end
    return group
end
local function StartPanelNeonPulse(depth, strong, frameWidth, glintWidth)
    if not (depth and depth.leftGlint and depth.leftGlint.CreateAnimationGroup) then return end
    if T.ReducedMotionEnabled and T.ReducedMotionEnabled() then
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
    local animateNeon = not (T.ReducedMotionEnabled and T.ReducedMotionEnabled())
    if depth.leftGlint then
        depth.leftGlint:ClearAllPoints()
        depth.leftGlint:SetPoint("TOPLEFT", frame, "TOPLEFT", animateNeon and -glintW or 12, -4)
        depth.leftGlint:SetWidth(glintW)
        depth.leftGlint:SetTexture((T.media and T.media.gradH) or WHITE8)
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
        flash = frame:CreateTexture(nil, "OVERLAY", nil, 6)
        flash:SetTexture((T.media and T.media.superellipse) or WHITE8)
        flash:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
        flash:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
        if flash.SetBlendMode then flash:SetBlendMode("ADD") end
        frame._msuf2NeonFlash = flash
    end
    flash:SetVertexColor(color[1], color[2], color[3], opts.alpha or 0.26)
    flash:SetAlpha(opts.alpha or 0.26)
    flash:Show()
    if flash._msuf2FlashGroup and flash._msuf2FlashGroup.Stop then flash._msuf2FlashGroup:Stop() end
    if T.ReducedMotionEnabled and T.ReducedMotionEnabled() then
        flash:SetAlpha(0)
        flash:Hide()
        return frame
    end
    if flash.CreateAnimationGroup then
        local group = flash:CreateAnimationGroup()
        T.TrackMenuAnimationGroup(group)
        local fade = group:CreateAnimation("Alpha")
        if fade.SetFromAlpha then fade:SetFromAlpha(opts.alpha or 0.26) end
        if fade.SetToAlpha then fade:SetToAlpha(0) end
        if fade.SetDuration then fade:SetDuration(opts.duration or 0.70) end
        if fade.SetSmoothing then fade:SetSmoothing("OUT") end
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
    if T.ApplyGradient and T.gradients and T.gradients[variant or "card"] then T.ApplyGradient(frame, variant or "card", { key = "_msuf2MaterialGradient" }) end
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
        top = frame:CreateTexture(nil, "ARTWORK", nil, -2)
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
        bottom = frame:CreateTexture(nil, "BORDER", nil, 5)
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
        lip = frame:CreateTexture(nil, "ARTWORK", nil, 4)
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
    return T.gradients and T.gradients[token or "card"] or nil
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
    opts = opts or {}
    local spec = ResolveGradientSpec(token) or DynamicGradientFromColor(T.colors.panel2)
    local key = opts.key or spec.key or "_msuf2MaterialGradient"
    local tex = frame[key]
    if not tex then
        tex = frame:CreateTexture(nil, opts.layer or spec.layer or "BACKGROUND", nil, opts.subLevel or spec.subLevel or 1)
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
    local spec = type(material) == "table" and material or (T.materials and T.materials[material or "card"])
    if type(spec) ~= "table" then return frame end
    if spec.bg or spec.border then T.ApplyBackdrop(frame, spec.bg or T.colors.panel, spec.border or T.colors.borderSoft) end
    if spec.gradient and T.ApplyGradient then
        T.ApplyGradient(frame, spec.gradient, { key = "_msuf2MaterialGradient" })
    elseif frame._msuf2MaterialGradient and frame._msuf2MaterialGradient.Hide then
        frame._msuf2MaterialGradient:Hide()
    end
    if spec.glass and T.ApplyGlass then T.ApplyGlass(frame, spec.glass) end
    if spec.plastic ~= false and T.ApplyPlasticDepth then T.ApplyPlasticDepth(frame, spec.glass or material) end
    if spec.veil and T.ApplyFocusVeil then T.ApplyFocusVeil(frame, spec.veil) end
    return frame
end
function T.ApplySurface(frame, material, glass)
    if T.ApplyMaterial then return T.ApplyMaterial(frame, material) end
    return T.ApplyGlass and T.ApplyGlass(frame, glass or (type(material) == "table" and material.glass) or material) or frame
end
local function CollapseHintLearned()
    local state = M.collapseHintClickState
    if type(state) ~= "table" and type(M.GetPersistentMenuStateTable) == "function" then state = M.GetPersistentMenuStateTable("collapseHintClickState") end
    return (tonumber(state and state.total) or 0) >= (tonumber(T.collapseHintClickHideThreshold) or 8)
end
function T.ApplyCollapseVisual(chevron, hint, open)
    open = open and true or false
    if chevron then
        local c = open and T.colors.accent or T.colors.accent2
        local a = open and 0.86 or 0.74
        local chevronKey = tostring(open) .. "\030" .. tostring(c[1]) .. "\030" .. tostring(c[2]) .. "\030" .. tostring(c[3]) .. "\030" .. tostring(a)
        if chevron._msuf2CollapseVisualKey ~= chevronKey then
            chevron._msuf2CollapseVisualKey = chevronKey
            if chevron.SetRotation then chevron:SetRotation(open and (math.pi * 0.5) or 0) end
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
            hint:SetText(text)
            if hint.SetTextColor then hint:SetTextColor(c[1], c[2], c[3], 0.74) end
        end
    end
end
local function CreateAtmosphereTexture(parent, layer, subLevel, texture, color, inset, texCoord)
    local tex = parent:CreateTexture(nil, layer, nil, subLevel)
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
    local logo = host:CreateTexture(nil, "BORDER", nil, 0)
    logo:SetTexture(T.media.logo)
    logo:SetSize(120, 120)
    logo:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -12, 12)
    logo:SetVertexColor(0.22, 0.28, 0.42, 0.024)
    if logo.SetBlendMode then logo:SetBlendMode("ADD") end
    if nav then CreateAtmosphereTexture(nav, "BORDER", 1, T.media.bgSmooth, { 0.06, 0.08, 0.18, 0.085 }, 3, { 0, 0, 1, 0, 0, 1, 1, 1 }) end
end
local function LayoutNavButtonLabel(btn, isChild, hasIcon)
    if not (btn and btn._msuf2Label) then return end
    btn._msuf2Label:ClearAllPoints()
    btn._msuf2Label:SetPoint("LEFT", btn, "LEFT", hasIcon and 28 or 12, 0)
    btn._msuf2Label:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    btn._msuf2Label:SetJustifyH("LEFT")
end
local NAV_ICON_SIZE = 17
local NAV_GLYPH_PATHS = {
    -- Layered droplet from the selected Colors concept.
    opt_colors = {
        { { 0, 7 }, { -2, 4 }, { -5, 0 }, { -5, -3 }, { -3, -6 }, { 0, -7 }, { 3, -6 }, { 5, -3 }, { 5, 0 }, { 2, 4 }, { 0, 7 } },
        { { -2, -3 }, { -1, -4 }, { 1, -4 }, { 3, -2 } },
    },
    -- Three compact resource pips from the selected Class Resources concept.
    classpower = {
        { { -5, 6 }, { -6.5, 5 }, { -6.5, -5 }, { -5, -6 }, { -3.5, -5 }, { -3.5, 5 }, { -5, 6 } },
        { { 0, 6 }, { -1.5, 5 }, { -1.5, -5 }, { 0, -6 }, { 1.5, -5 }, { 1.5, 5 }, { 0, 6 } },
        { { 5, 6 }, { 3.5, 5 }, { 3.5, -5 }, { 5, -6 }, { 6.5, -5 }, { 6.5, 5 }, { 5, 6 } },
        { { -5, -2 }, { -5, -4 } },
        { { 0, -1 }, { 0, -4 } },
        { { 5, 0 }, { 5, -4 } },
    },
    -- Crosshair and sword from the selected Gameplay concept.
    gameplay = {
        { { -2, 6 }, { 1, 5 }, { 2, 2 }, { 1, -1 }, { -2, -2 }, { -5, -1 }, { -6, 2 }, { -5, 5 }, { -2, 6 } },
        { { -2, 8 }, { -2, 5 } },
        { { -2, -2 }, { -2, -5 } },
        { { -8, 2 }, { -5, 2 } },
        { { 1, 2 }, { 4, 2 } },
        { { 0, -6 }, { 6, 0 } },
        { { 4.5, 1.5 }, { 6, 0 }, { 4.5, -1.5 } },
        { { 0, -3.5 }, { 2.5, -6 } },
        { { -1, -7 }, { 1, -5 } },
    },
}
local NAV_GLYPH_TEXT = { opt_fonts = "Aa" }
local function AddNavGlyphPath(holder, parts, points)
    if not (holder and holder.CreateLine and type(points) == "table") then return end
    for i = 2, #points do
        local from, to = points[i - 1], points[i]
        local line = holder:CreateLine(nil, "ARTWORK", nil, 3)
        line:SetThickness(1.25)
        line:SetStartPoint("CENTER", holder, from[1], from[2])
        line:SetEndPoint("CENTER", holder, to[1], to[2])
        line:SetColorTexture(1, 1, 1, 1)
        parts[#parts + 1] = { region = line, kind = "line" }
    end
end
local function CreateProceduralNavIcon(btn, navKey)
    local paths, text = NAV_GLYPH_PATHS[navKey], NAV_GLYPH_TEXT[navKey]
    if not (paths or text) then return nil end
    local holder = CreateFrame("Frame", nil, btn)
    holder:SetSize(NAV_ICON_SIZE, NAV_ICON_SIZE)
    holder._msuf2GlyphParts = {}
    if paths then
        for i = 1, #paths do AddNavGlyphPath(holder, holder._msuf2GlyphParts, paths[i]) end
    end
    if text then
        local label = holder:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        local font, _, flags = label:GetFont()
        label:SetFont(font, T.FontSize("micro"), flags or "")
        label:SetPoint("CENTER", holder, "CENTER", 0, -0.5)
        label:SetJustifyH("CENTER")
        label:SetText(text)
        holder._msuf2GlyphParts[#holder._msuf2GlyphParts + 1] = { region = label, kind = "font" }
    end
    if navKey == "gameplay" then
        local dot = holder:CreateTexture(nil, "ARTWORK", nil, 4)
        dot:SetSize(1.75, 1.75)
        dot:SetPoint("CENTER", holder, "CENTER", -2, 2)
        dot:SetColorTexture(1, 1, 1, 1)
        holder._msuf2GlyphParts[#holder._msuf2GlyphParts + 1] = { region = dot, kind = "texture" }
    end
    return holder
end
local function PaintNavIcon(btn, r, g, b, a)
    local icon = btn and btn._msuf2NavIcon
    if not icon then return end
    local parts = icon._msuf2GlyphParts
    if type(parts) == "table" then
        for i = 1, #parts do
            local part = parts[i]
            if part.kind == "font" and part.region.SetTextColor then
                part.region:SetTextColor(r, g, b, a)
            elseif part.region.SetColorTexture then
                part.region:SetColorTexture(r, g, b, a)
            end
        end
    elseif icon.SetVertexColor then
        icon:SetVertexColor(r, g, b, a)
    end
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
    local grid = T.navIconGrid and T.navIconGrid[navKey]
    local color = T.navIconColors and T.navIconColors[navKey]
    if not (grid and color) then
        LayoutNavButtonLabel(btn, isChild, false)
        return
    end
    local icon = btn._msuf2NavIcon
    if not icon then
        icon = CreateProceduralNavIcon(btn, navKey)
        if not icon then
            icon = btn:CreateTexture(nil, "ARTWORK", nil, 3)
            icon:SetTexture(T.media.navIcons)
        end
        icon:SetSize(NAV_ICON_SIZE, NAV_ICON_SIZE)
        icon:SetPoint("LEFT", btn, "LEFT", isChild and 8 or 12, 0)
        btn._msuf2NavIcon = icon
    else
        icon:ClearAllPoints()
        icon:SetSize(NAV_ICON_SIZE, NAV_ICON_SIZE)
        icon:SetPoint("LEFT", btn, "LEFT", isChild and 8 or 12, 0)
    end
    local col, row = grid[1], grid[2]
    if icon.SetTexCoord then icon:SetTexCoord(col / 8, (col + 1) / 8, row / 8, (row + 1) / 8) end
    btn._msuf2NavIconColor = color
    if not btn._msuf2NavStripe then
        local stripe = btn:CreateTexture(nil, "ARTWORK", nil, 6)
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
local function HideNativeSliderTexture(region, keep)
    if not region or region == keep then return end
    if region.SetAlpha then region:SetAlpha(0) end
    if region.Hide then region:Hide() end
end
local function IsTextureRegion(region)
    if not region then return false end
    if region.IsObjectType then return region:IsObjectType("Texture") and true or false end
    return region.GetObjectType and region:GetObjectType() == "Texture"
end
local SLIDER_STYLED_TEXTURE_KEYS = { "_msufTrack", "_msufTrackTop", "_msufTrackBottom", "_msufFill", "_msufFillGlow", "_msuf2Thumb", "_msufPeelTrack", "_msufPeelTrackFill" }
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
            if IsTextureRegion(region) and not keep[region] then HideNativeSliderTexture(region) end
        end
    end
    local name = slider.GetName and slider:GetName()
    if name and _G then
        for _, suffix in ipairs(SLIDER_NATIVE_SUFFIXES) do
            HideNativeSliderTexture(_G[name .. suffix])
        end
    end
    slider._msuf2NativeSliderPartsHidden = true
end
local function SetSliderTextureColor(texture, r, g, b, a)
    SetTextureColorCached(texture, r, g, b, a)
end
local function SliderTexture(slider, key, layer, subLevel, height)
    local tex = slider:CreateTexture(nil, layer, nil, subLevel)
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
local function UpdateSliderThumb(slider)
    local thumb = slider and slider._msuf2Thumb
    if not thumb then return end
    local nativeThumb = slider.GetThumbTexture and slider:GetThumbTexture()
    if nativeThumb and nativeThumb ~= thumb then
        -- Cursor-drag sliders own the whole press; collapse the native thumb so
        -- the engine's thumb-grab drag can't fight the cursor-follow OnUpdate.
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
    OnEnter = function(self) self._msuf2SliderHovered = true; T.StyleSlider(self) end,
    OnLeave = function(self) self._msuf2SliderHovered = nil; T.StyleSlider(self) end,
    OnMouseDown = function(self) self._msuf2SliderActive = true; T.StyleSlider(self) end,
    OnMouseUp = function(self) self._msuf2SliderActive = nil; T.StyleSlider(self) end,
    OnDisable = function(self) self._msuf2SliderActive = nil; self._msuf2SliderHovered = nil; T.StyleSlider(self) end,
    OnEnable = function(self) T.StyleSlider(self) end,
    OnValueChanged = function(self) if self._msuf2UpdateThumb then self:_msuf2UpdateThumb() end end,
    OnSizeChanged = function(self) if self._msuf2UpdateFill then self:_msuf2UpdateFill() end; if self._msuf2UpdateThumb then self:_msuf2UpdateThumb() end end,
}
function T.StyleSlider(slider)
    if not slider then return end
    slider.__msufPeelSliderSkinned = true
    slider._msuf2SliderStyled = true
    if slider.SetOrientation then slider:SetOrientation("HORIZONTAL") end
    if slider.SetThumbTexture and slider.GetThumbTexture and not slider:GetThumbTexture() then slider:SetThumbTexture(T.media.sliderThumb or "Interface\\Buttons\\WHITE8X8") end
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
        local thumb = slider:CreateTexture(nil, "OVERLAY", nil, 4)
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
    if slider._msuf2SliderVisualReady
        and slider._msuf2SliderVisualEnabled == enabled
        and slider._msuf2SliderVisualHovered == hovered
        and slider._msuf2SliderVisualActive == active
        and slider._msuf2SliderVisualAccentR == accent[1]
        and slider._msuf2SliderVisualAccentG == accent[2]
        and slider._msuf2SliderVisualAccentB == accent[3]
        and slider._msuf2SliderVisualEdgeR == edge[1]
        and slider._msuf2SliderVisualEdgeG == edge[2]
        and slider._msuf2SliderVisualEdgeB == edge[3]
        and slider._msuf2SliderVisualThumbMedia == thumbMedia
    then
        UpdateSliderThumb(slider)
        return
    end
    slider._msuf2SliderVisualReady = true
    slider._msuf2SliderVisualEnabled = enabled
    slider._msuf2SliderVisualHovered = hovered
    slider._msuf2SliderVisualActive = active
    slider._msuf2SliderVisualAccentR, slider._msuf2SliderVisualAccentG, slider._msuf2SliderVisualAccentB = accent[1], accent[2], accent[3]
    slider._msuf2SliderVisualEdgeR, slider._msuf2SliderVisualEdgeG, slider._msuf2SliderVisualEdgeB = edge[1], edge[2], edge[3]
    slider._msuf2SliderVisualThumbMedia = thumbMedia
    if slider._msufTrack then
        local surface = T.colors.coreSurface or { 0.014, 0.038, 0.072, 1 }
        local trackBase = {
            surface[1] * (active and 1.45 or hovered and 1.30 or 1.18),
            surface[2] * (active and 1.42 or hovered and 1.28 or 1.16),
            surface[3] * (active and 1.36 or hovered and 1.22 or 1.12),
            0.98 * alpha,
        }
        SetSliderTextureColor(slider._msufTrack, trackBase[1], trackBase[2], trackBase[3], trackBase[4])
        ApplyTextureGradient(slider._msufTrack, "VERTICAL", ShadeColor(trackBase, 0.10, 1), ShadeColor(trackBase, -0.18, 1), false)
        if slider._msufTrack.Show then slider._msufTrack:Show() end
    end
    if slider._msufTrackTop then
        SetSliderTextureColor(slider._msufTrackTop, edge[1], edge[2], edge[3], (active and 1.00 or hovered and 0.94 or 0.74) * alpha)
        slider._msufTrackTop:Show()
    end
    if slider._msufTrackBottom then
        SetSliderTextureColor(slider._msufTrackBottom, edge[1], edge[2], edge[3], (active and 0.62 or hovered and 0.46 or 0.40) * alpha)
        slider._msufTrackBottom:Show()
    end
    if slider._msufFill then
        local fillAlpha = (active and 1.00 or hovered and 0.96 or 0.86) * alpha
        SetSliderTextureColor(slider._msufFill, accent[1], accent[2], accent[3], fillAlpha)
        ApplyTextureGradient(slider._msufFill, "HORIZONTAL",
            { math.min(accent[1] * 1.24, 1), math.min(accent[2] * 1.14, 1), math.min(accent[3] * 1.10, 1), fillAlpha },
            { accent[1] * 0.72, accent[2] * 0.82, accent[3] * 0.90, fillAlpha * 0.88 },
            false)
        if slider._msufFill.Show then slider._msufFill:Show() end
    end
    if slider._msufFillGlow then
        SetSliderTextureColor(slider._msufFillGlow, accent[1], accent[2], accent[3], (active and 0.30 or hovered and 0.20 or 0.12) * alpha)
        slider._msufFillGlow:Show()
    end
    local nativeThumb = slider.GetThumbTexture and slider:GetThumbTexture()
    if nativeThumb then
        local hit = slider._msuf2CursorDrag and 1 or 18
        if nativeThumb.SetSize then nativeThumb:SetSize(hit, hit) end
        if nativeThumb.SetAlpha then nativeThumb:SetAlpha(0.001) end
        if nativeThumb.Show then nativeThumb:Show() end
    end
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
function T.StyleCheckmark(checkButton)
    if not checkButton then return end
    local UI = MSUF and MSUF.UI
    local styleText = (_G and _G.MSUF_StyleToggleText) or (MSUF and MSUF.MSUF_StyleToggleText) or (UI and UI.StyleToggleText)
    if type(styleText) == "function" then styleText(checkButton) end
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
        local buttonSize = checkButton._msuf2QuietCheckBox and 28 or 24
        checkButton:SetSize(buttonSize, buttonSize)
        if checkButton.text then
            checkButton.text:ClearAllPoints()
            checkButton.text:SetPoint("LEFT", checkButton, "RIGHT", checkButton._msuf2QuietCheckBox and 8 or 4, 0)
            checkButton.text:SetJustifyH("LEFT")
        end
    end
    local function ApplyCheckTexture()
        local oldStyle = (_G and _G.MSUF_StyleCheckmark) or (MSUF and MSUF.MSUF_StyleCheckmark) or (UI and UI.StyleCheckmark)
        if type(oldStyle) == "function" then oldStyle(checkButton) end
        HideQuietCheckboxNative()
        local tick = (checkButton._msuf2QuietCheckBox and T.media.checkTickMedium) or T.media.checkTick
        if checkButton.SetCheckedTexture then checkButton:SetCheckedTexture(tick) end
        if checkButton.SetDisabledCheckedTexture then checkButton:SetDisabledCheckedTexture(tick) end
        local check = checkButton.GetCheckedTexture and checkButton:GetCheckedTexture()
        if not check and checkButton.GetName and checkButton:GetName() then check = _G[checkButton:GetName() .. "Check"] end
        local disabledCheck = checkButton.GetDisabledCheckedTexture and checkButton:GetDisabledCheckedTexture()
        if not disabledCheck and checkButton.GetName and checkButton:GetName() then disabledCheck = _G[checkButton:GetName() .. "DisabledCheck"] end
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
    local f = CreateFrame("Frame", name, parent, Template())
    T.ApplyBackdrop(f, bg or T.colors.panel, border or T.colors.borderSoft)
    if T.ApplyGradient then T.ApplyGradient(f, DynamicGradientFromColor(bg or T.colors.panel), { key = "_msuf2MaterialGradient" }) end
    return f
end
local EDIT_BOX_EDGE_SPECS = { { "TOPLEFT", "TOPRIGHT", "SetHeight", 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", "SetHeight", 1 }, { "TOPLEFT", "BOTTOMLEFT", "SetWidth", 1 }, { "TOPRIGHT", "BOTTOMRIGHT", "SetWidth", 1 } }
local EDIT_BOX_NATIVE_SUFFIXES = WL "Left Right Middle Mid"
function T.SkinEditBox(editBox)
    if not editBox or editBox._msuf2EditSkinned then return editBox end
    editBox._msuf2EditSkinned = true
    local name = editBox.GetName and editBox:GetName() or nil
    if name then
        for _, suffix in ipairs(EDIT_BOX_NATIVE_SUFFIXES) do
            local tex = _G[name .. suffix]
            if tex and tex.SetAlpha then tex:SetAlpha(0) end
        end
    end
    local fontString = editBox.GetFontString and editBox:GetFontString() or nil
    if editBox.GetRegions then
        local regions = { editBox:GetRegions() }
        for i = 1, #regions do
            local region = regions[i]
            if IsTextureRegion(region) and region ~= fontString then
                if region.SetAlpha then region:SetAlpha(0) end
                if region.Hide then region:Hide() end
            end
        end
    end
    local shadow = T.colors.coreShadow or { 0.006, 0.016, 0.032 }
    local rim = T.colors.borderSoft or T.colors.coreRim or { 0.070, 0.260, 0.390 }
    T.ApplyBackdrop(editBox, { shadow[1], shadow[2], shadow[3], 0.760 }, { rim[1], rim[2], rim[3], 0.56 })
    if editBox.CreateTexture then
        local bg = editBox:CreateTexture(nil, "BACKGROUND", nil, -6)
        bg:SetPoint("TOPLEFT", editBox, "TOPLEFT", 0, 0)
        bg:SetPoint("BOTTOMRIGHT", editBox, "BOTTOMRIGHT", 0, 0)
        editBox._msuf2EditBg = bg
        local edges = {}
        for i = 1, #EDIT_BOX_EDGE_SPECS do
            local spec = EDIT_BOX_EDGE_SPECS[i]
            local edge = editBox:CreateTexture(nil, "OVERLAY", nil, 1)
            edge:SetPoint(spec[1], editBox, spec[1], 0, 0)
            edge:SetPoint(spec[2], editBox, spec[2], 0, 0)
            edge[spec[3]](edge, spec[4])
            edges[i] = edge
        end
        editBox._msuf2EditEdges = edges
    end
    local function PaintEditBox(self, focused)
        local enabled = not (self.IsEnabled and not self:IsEnabled())
        local alpha = enabled and 1 or 0.60
        local roundedFill = self._msuf2RoundedEditFill
        local roundedEdge = self._msuf2RoundedEditEdge
        if roundedFill and roundedEdge then
            local c = T.colors.coreShadow or { 0.006, 0.016, 0.032 }
            local bg = self._msuf2RoundedEditColor or { c[1], c[2], c[3], 0.98 }
            SetFillGradient(roundedFill, { bg[1] or 0.018, bg[2] or 0.024, bg[3] or 0.050, (bg[4] or 0.98) * alpha }, 0.10, -0.16)
            local c = focused and T.colors.accent or T.colors.borderSoft
            local a = focused and 0.98 or 0.88
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
        if self._msuf2EditBg then
            local c = T.colors.coreShadow or { 0.006, 0.016, 0.032 }
            local bg = { c[1], c[2], c[3], 0.98 * alpha }
            ApplyTextureGradient(self._msuf2EditBg, "VERTICAL", ShadeColor(bg, 0.10, 1), ShadeColor(bg, -0.16, 1), false)
        end
        local c = focused and T.colors.accent or T.colors.borderSoft
        local a = focused and 0.98 or 0.88
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
        if self.SetBackdropBorderColor and not self._msuf2RoundedEditFill then self:SetBackdropBorderColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.95) end
    end)
    editBox:HookScript("OnEditFocusLost", function(self)
        PaintEditBox(self, false)
        if self.SetBackdropBorderColor and not self._msuf2RoundedEditFill then self:SetBackdropBorderColor(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], T.colors.borderSoft[4] or 1) end
    end)
    editBox:HookScript("OnEnable", function(self) PaintEditBox(self, self.HasFocus and self:HasFocus()) end)
    editBox:HookScript("OnDisable", function(self) PaintEditBox(self, false) end)
    editBox:HookScript("OnShow", function(self) PaintEditBox(self, self.HasFocus and self:HasFocus()) end)
    PaintEditBox(editBox, false)
    return editBox
end
local function FontSetText(self, value) return self._msuf2RawSetText(self, Tr(value or "")) end
function T.Font(parent, template, text, color, role)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs._msuf2FontRole = role
    fs._msuf2RawSetText = fs.SetText
    fs.SetText = FontSetText
    fs:SetText(text or "")
    return T.StyleFontString(fs, color or T.colors.text, 1, role)
end

-- Release-highlight sentences are links, so they use an intentionally distinct
-- yellow treatment instead of the general blue interaction palette. The hover
-- outline follows the button's measured multiline height.
function T.StyleFeatureLink(button, label)
    if not (button and label and button.CreateTexture) then return nil end
    local base = T.colors.accent2 or T.colors.warning or { 0.95, 0.72, 0.18, 1 }
    local hot = { 1.00, 0.84, 0.30, 1 }
    local fill = button:CreateTexture(nil, "BACKGROUND")
    fill:SetPoint("TOPLEFT", button, "TOPLEFT", -5, 3)
    fill:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 5, -3)
    fill:SetColorTexture(base[1], base[2], base[3], 0.09)

    local edges = {}
    for index = 1, 4 do
        local edge = button:CreateTexture(nil, "OVERLAY", nil, 7)
        edge:SetColorTexture(base[1], base[2], base[3], 0.96)
        edges[index] = edge
    end
    edges[1]:SetPoint("TOPLEFT", button, "TOPLEFT", -5, 3)
    edges[1]:SetPoint("TOPRIGHT", button, "TOPRIGHT", 5, 3)
    edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -5, -3)
    edges[2]:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 5, -3)
    edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT", button, "TOPLEFT", -5, 3)
    edges[3]:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -5, -3)
    edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT", button, "TOPRIGHT", 5, 3)
    edges[4]:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 5, -3)
    edges[4]:SetWidth(1)

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
local NAV_PILL_SLICE_MODE = _G.Enum and _G.Enum.UITextureSliceMode
    and _G.Enum.UITextureSliceMode.Stretched
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
local function LayoutNavPillArt(btn, art)
    if not art then return end
    LayoutNavPillTexture(btn, art.texture)
    LayoutNavPillTexture(btn, art.hoverWash)
    LayoutNavPillTexture(btn, art.glow)
    LayoutNavPillTexture(btn, art.sheen)
end
local function EnsureNavPillArt(btn)
    if not (btn and btn.CreateTexture) then return nil end
    if btn._msuf2NavPillArt then return btn._msuf2NavPillArt end
    local tex = btn:CreateTexture(nil, "BORDER", nil, 7)
    if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
    if tex.SetBlendMode then tex:SetBlendMode("BLEND") end
    ConfigureNavPillSlice(tex)
    tex:Hide()
    local glow = btn:CreateTexture(nil, "ARTWORK", nil, 1)
    if glow.SetTexCoord then glow:SetTexCoord(0, 1, 0, 1) end
    if glow.SetBlendMode then glow:SetBlendMode("ADD") end
    ConfigureNavPillSlice(glow)
    glow:Hide()
    local hoverWash = btn:CreateTexture(nil, "ARTWORK", nil, 0)
    if hoverWash.SetTexCoord then hoverWash:SetTexCoord(0, 1, 0, 1) end
    if hoverWash.SetBlendMode then hoverWash:SetBlendMode("ADD") end
    ConfigureNavPillSlice(hoverWash)
    hoverWash:Hide()
    local sheen = btn:CreateTexture(nil, "ARTWORK", nil, 2)
    if sheen.SetTexCoord then sheen:SetTexCoord(0, 1, 0, 1) end
    if sheen.SetBlendMode then sheen:SetBlendMode("ADD") end
    ConfigureNavPillSlice(sheen)
    sheen:Hide()
    local art = { texture = tex, hoverWash = hoverWash, glow = glow, sheen = sheen }
    LayoutNavPillArt(btn, art)
    btn._msuf2NavPillArt = art
    return art
end
local StopNavPillGlowPulse
local function HideNavPillArt(btn)
    local art = btn and btn._msuf2NavPillArt
    if not art then return end
    StopNavPillGlowPulse(art)
    if art.texture then art.texture:Hide() end
    if art.hoverWash then art.hoverWash:Hide() end
    if art.glow then art.glow:Hide() end
    if art.sheen then art.sheen:Hide() end
    if art.L then art.L:Hide() end
    if art.M then art.M:Hide() end
    if art.R then art.R:Hide() end
end
StopNavPillGlowPulse = function(art)
    if not art then return end
    local group = art._pulse
    if group and group.Stop then group:Stop() end
    if art.glow and art.glow.SetAlpha then art.glow:SetAlpha(1) end
    if art.sheen and art.sheen.SetAlpha then art.sheen:SetAlpha(1) end
end
local function StartNavPillGlowPulse(art)
    if not (art and art.glow and art.glow.CreateAnimationGroup) then return end
    if T.ReducedMotionEnabled and T.ReducedMotionEnabled() then
        StopNavPillGlowPulse(art)
        return
    end
    if not art._pulse then
        local group = art.glow:CreateAnimationGroup()
        T.TrackMenuAnimationGroup(group)
        if group.SetLooping then group:SetLooping("REPEAT") end
        local fadeIn = group:CreateAnimation("Alpha")
        if fadeIn.SetFromAlpha then fadeIn:SetFromAlpha(0.78) end
        if fadeIn.SetToAlpha then fadeIn:SetToAlpha(1.00) end
        if fadeIn.SetDuration then fadeIn:SetDuration(1.45) end
        if fadeIn.SetSmoothing then fadeIn:SetSmoothing("IN_OUT") end
        if fadeIn.SetOrder then fadeIn:SetOrder(1) end
        local fadeOut = group:CreateAnimation("Alpha")
        if fadeOut.SetFromAlpha then fadeOut:SetFromAlpha(1.00) end
        if fadeOut.SetToAlpha then fadeOut:SetToAlpha(0.80) end
        if fadeOut.SetDuration then fadeOut:SetDuration(1.85) end
        if fadeOut.SetSmoothing then fadeOut:SetSmoothing("IN_OUT") end
        if fadeOut.SetOrder then fadeOut:SetOrder(2) end
        art._pulse = group
    end
    if art._pulse and art._pulse.Play and (not art._pulse.IsPlaying or not art._pulse:IsPlaying()) then art._pulse:Play() end
end
local function PaintNavPillGlowArt(art, path, state)
    if not art then return end
    local active = state == "active"
    local hover = state == "hover"
    if not (active or hover) then
        StopNavPillGlowPulse(art)
        if art.hoverWash then art.hoverWash:Hide() end
        if art.glow then art.glow:Hide() end
        if art.sheen then art.sheen:Hide() end
        return
    end
    local c = T.colors or {}
    local blue = hover and (c.navPillEdgeHover or c.coreGlow)
        or c.coreBlue or c.accent or { 0.060, 0.250, 0.390, 1 }
    if art.hoverWash then
        if hover then
            if art.hoverWashPath ~= path then
                art.hoverWashPath = path
                art.hoverWash:SetTexture(path)
                art.hoverWash._msuf2TextureMode = nil
                if art.hoverWash.SetTexCoord then art.hoverWash:SetTexCoord(0, 1, 0, 1) end
            end
            ApplyTextureGradient(art.hoverWash, "VERTICAL",
                { blue[1], blue[2], blue[3], 0.165 },
                { blue[1], blue[2], blue[3], 0.045 },
                true)
            art.hoverWash:Show()
        else
            art.hoverWash:Hide()
        end
    end
    if art.glow then
        if art.glowPath ~= path then
            art.glowPath = path
            art.glow:SetTexture(path)
            art.glow._msuf2TextureMode = nil
            if art.glow.SetTexCoord then art.glow:SetTexCoord(0, 1, 0, 1) end
        end
        ApplyTextureGradient(art.glow, "VERTICAL",
            { blue[1], blue[2], blue[3], active and 0.120 or 0.055 },
            { blue[1], blue[2], blue[3], active and 0.024 or 0.010 },
            true)
        art.glow:Show()
    end
    if art.sheen then
        if art.sheenPath ~= path then
            art.sheenPath = path
            art.sheen:SetTexture(path)
            art.sheen._msuf2TextureMode = nil
            if art.sheen.SetTexCoord then art.sheen:SetTexCoord(0, 1, 0, 1) end
        end
        ApplyTextureGradient(art.sheen, "HORIZONTAL",
            { blue[1], blue[2], blue[3], 0.000 },
            { blue[1], blue[2], blue[3], active and 0.090 or 0.040 },
            true)
        art.sheen:Show()
    end
    if active then
        StartNavPillGlowPulse(art)
    else
        StopNavPillGlowPulse(art)
    end
end
local function SetNavPillArt(btn, state, baseColor, topAmount, bottomAmount, alphaMul)
    -- Midnight owns the authored blue paint. Non-midnight themes use the
    -- compact procedural renderer for active and hover so both states can carry
    -- their class/preset accent without multiplying against baked blue pixels.
    if T.MenuAccentActive and T.MenuAccentActive() then return false end
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
        if state == "hover" then
            -- Preserve the bitmap's authored dark-blue paint. Multiplying it by
            -- the already-dark hover token made the fill disappear; a near-
            -- neutral tint keeps it visible without the bright stadium result.
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
    if not (btn and btn.CreateTexture and T.CreateSuperellipseLayers) then return nil end
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
    if not active then
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
local function ButtonVisual(btn, active, hover)
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
    local roleLit = active or (hover and not textOnlyHover)
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
    if btn._msuf2Danger then
        HideNavPillArt(btn)
        SetNavActiveFX(btn, false)
        if roleLit then
            SetFillGradient(fill, { 0.180, 0.040, 0.065, 0.97 }, 0.18, -0.18)
            edge:SetVertexColor(c.danger[1], c.danger[2], c.danger[3], 0.95)
        else
            SetFillGradient(fill, { 0.140, 0.030, 0.050, 0.94 }, 0.14, -0.20)
            edge:SetVertexColor(c.danger[1], c.danger[2], c.danger[3], 0.82)
        end
        if textOnlyHover then
            SetLabelColor(btn._msuf2Label, c.navHeaderHover)
        else
            btn._msuf2Label:SetTextColor(c.text[1], c.text[2], c.text[3], 1)
        end
        return
    end
    if btn._msuf2Primary then
        HideNavPillArt(btn)
        SetNavActiveFX(btn, false)
        if roleLit then
            SetFillGradient(fill, { c.coreBlue[1], c.coreBlue[2], c.coreBlue[3], 0.64 }, 0.08, -0.28)
            edge:SetVertexColor(c.coreGlow[1], c.coreGlow[2], c.coreGlow[3], 0.46)
        else
            SetFillGradient(fill, { c.coreBlue[1], c.coreBlue[2], c.coreBlue[3], 0.56 }, 0.07, -0.30)
            edge:SetVertexColor(c.coreGlow[1], c.coreGlow[2], c.coreGlow[3], 0.38)
        end
        if textOnlyHover then
            SetLabelColor(btn._msuf2Label, c.navHeaderHover)
        else
            btn._msuf2Label:SetTextColor(1, 1, 1, 1)
        end
        return
    end
    if btn._msuf2Success then
        HideNavPillArt(btn)
        SetNavActiveFX(btn, false)
        if roleLit then
            SetFillGradient(fill, { 0.060, 0.380, 0.180, 0.98 }, 0.18, -0.18)
            edge:SetVertexColor(0.220, 0.860, 0.420, 0.90)
        else
            SetFillGradient(fill, { 0.040, 0.280, 0.130, 0.95 }, 0.14, -0.20)
            edge:SetVertexColor(0.140, 0.660, 0.310, 0.82)
        end
        if textOnlyHover then
            SetLabelColor(btn._msuf2Label, c.navHeaderHover)
        else
            btn._msuf2Label:SetTextColor(0.92, 1.00, 0.94, 1)
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
            if btn._msuf2NavStripe then btn._msuf2NavStripe:Hide() end
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
        if btn._msuf2NavStripe then btn._msuf2NavStripe:Show() end
        local bg, br, tx = c.pillActive, c.pillEdgeActive, c.pillTextActive
        if textOnlyHover then tx = c.navHeaderHover or tx end
        PaintButtonParts(fill, edge, btn._msuf2Label, bg, br, tx, 0.16, -0.15)
        PaintStoredNavIcon(btn, 1.00)
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
local function ButtonSetText(self, value)
    local raw = value or ""
    local text = Tr(raw)
    if self._msuf2RawText == raw and self._msuf2Label and self._msuf2Label:GetText() == text then return end
    self._msuf2RawText = raw
    self._msuf2SearchText = raw
    if self._msuf2Label then self._msuf2Label._msuf2SearchText = raw end
    self._msuf2Label:SetText(text)
    if M and type(M.RegisterSearchWidget) == "function" and value and value ~= "" then
        local previous = type(self._msuf2SearchMeta) == "table" and self._msuf2SearchMeta or nil
        local meta = { label = value, kind = "button", anchor = self._msuf2Label }
        if previous then
            for key, item in pairs(previous) do meta[key] = item end
            meta.label, meta.kind, meta.anchor = value, previous.kind or "button", previous.anchor or self._msuf2Label
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
local function ButtonClickProxy(self, ...)
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
            if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then _G.MSUF_ShowConfigCombatLockMessage() end
        end
        if blocked then return end
    end
    local handler = self._msuf2OnClickHandler
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
    OnEnter = function(self) self._msuf2Hover = true; ButtonVisual(self, self._msuf2Active, true) end,
    OnLeave = function(self) self._msuf2Hover = nil; ButtonVisual(self, self._msuf2Active, false) end,
    OnEnable = ButtonRefreshVisual,
    OnDisable = ButtonRefreshVisual,
}
local function ButtonHistoryCheckpoint(self)
    if self._msuf2SkipHistoryCheckpoint then return end
    local checkpoint = M and M.CheckpointHistory
    if type(checkpoint) ~= "function" then return end
    local label = self._msuf2HistoryLabel
        or (self.GetText and self:GetText())
        or "MSUF2 button"
    if label == "" then label = "MSUF2 button" end
    checkpoint(label, self._msuf2HistorySource or ("button:" .. tostring(self)))
end
function T.Button(parent, text, width, height, opts)
    local btn = CreateFrame("Button", nil, parent)
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
    if M and type(M.RegisterSearchWidget) == "function" and text and text ~= ""
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
local BUTTON_ROLE_VARIANTS = { primary = "primary", destructive = "danger", danger = "danger", delete = "danger", reset = "danger", success = "success", confirm = "success" }
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
    OnEnter = function(self) self._msuf2CloseHover = true; CloseButtonVisual(self, true, self._msuf2CloseDown) end,
    OnLeave = function(self) self._msuf2CloseHover = nil; self._msuf2CloseDown = nil; CloseButtonVisual(self, false, false) end,
    OnMouseDown = function(self) self._msuf2CloseDown = true; CloseButtonVisual(self, self._msuf2CloseHover, true) end,
    OnMouseUp = function(self) self._msuf2CloseDown = nil; CloseButtonVisual(self, self._msuf2CloseHover, false) end,
    OnEnable = function(self) CloseButtonVisual(self, self._msuf2CloseHover, self._msuf2CloseDown) end,
    OnDisable = function(self) CloseButtonVisual(self, false, false) end,
}
local function SetupCloseButtonLine(line, parent)
    line:SetTexture("Interface\\Buttons\\WHITE8X8")
    line:SetSize(12, 2)
    line:SetPoint("CENTER", parent, "CENTER", 0, 0)
end
function T.CloseButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(24, 24)
    local fill, edge = T.CreateSuperellipseLayers(btn, "_msuf2Close", 2, "BACKGROUND", "BORDER")
    btn._msuf2CloseFill = fill
    btn._msuf2CloseEdge = edge
    local lineA, lineB = btn:CreateTexture(nil, "ARTWORK"), btn:CreateTexture(nil, "ARTWORK")
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
local function AccessibleNumber(value, fallback)
    fallback = tonumber(fallback) or 0
    local canaccessvalue = _G.canaccessvalue
    if type(canaccessvalue) == "function" and canaccessvalue(value) ~= true then return fallback end
    local issecretvalue = _G.issecretvalue
    if type(issecretvalue) == "function" and issecretvalue(value) == true then return fallback end
    return tonumber(value) or fallback
end
M.AccessibleNumber = AccessibleNumber
local function ClampScrollValue(value, maxValue)
    value = AccessibleNumber(value, 0)
    maxValue = AccessibleNumber(maxValue, 0)
    if value < 0 then return 0 end
    if value > maxValue then return maxValue end
    return value
end
local SMOOTH_SCROLL_SPEED = 14
local SMOOTH_SCROLL_MAX_ELAPSED = 0.050
local SMOOTH_SCROLL_EPSILON = 0.45
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
    local bar = CreateFrame("Frame", nil, parent)
    -- Keep a generous mouse target while the visible rail stays compact.
    bar:SetWidth(14)
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 5, -8)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 5, 8)
    if bar.EnableMouse then bar:EnableMouse(true) end
    if bar.SetFrameLevel and scroll.GetFrameLevel then bar:SetFrameLevel(scroll:GetFrameLevel() + 8) end
    local track = PixelBarTexture(bar:CreateTexture(nil, "BACKGROUND"))
    track:SetPoint("TOP", bar, "TOP", 0, 0)
    track:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    track:SetWidth(2)
    ApplyTextureGradient(track, "VERTICAL",
        { T.colors.coreSurface[1], T.colors.coreSurface[2], T.colors.coreSurface[3], 0.82 },
        { T.colors.coreShadow[1], T.colors.coreShadow[2], T.colors.coreShadow[3], 0.82 },
        true)
    bar._msuf2Track = track
    local trackEdge = PixelBarTexture(bar:CreateTexture(nil, "BORDER"))
    trackEdge:SetPoint("TOPLEFT", track, "TOPRIGHT", 1, 0)
    trackEdge:SetPoint("BOTTOMLEFT", track, "BOTTOMRIGHT", 1, 0)
    trackEdge:SetWidth(1)
    trackEdge:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.38)
    bar._msuf2TrackEdge = trackEdge
    local thumbBase = T.colors.coreRim
    local thumbHover = T.colors.coreRaised
    local thumb = PixelBarTexture(bar:CreateTexture(nil, "OVERLAY"))
    thumb:SetSize(5, 42)
    ApplyTextureGradient(thumb, "VERTICAL", { thumbBase[1] * 1.22, thumbBase[2] * 1.18, thumbBase[3] * 1.12, 0.72 }, { thumbBase[1] * 0.72, thumbBase[2] * 0.78, thumbBase[3] * 0.86, 0.72 }, true)
    bar._msuf2Thumb = thumb
    local function Paint(hover)
        local shown = bar.IsShown and bar:IsShown()
        local alpha = shown and 1 or 0
        if track then
            local a = (hover and 0.98 or 0.82) * alpha
            ApplyTextureGradient(track, "VERTICAL",
                { T.colors.coreSurface[1], T.colors.coreSurface[2], T.colors.coreSurface[3], a },
                { T.colors.coreShadow[1], T.colors.coreShadow[2], T.colors.coreShadow[3], a },
                true)
        end
        if trackEdge then trackEdge:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], (hover and 0.62 or 0.38) * alpha) end
        if thumb and thumb.SetColorTexture then
            local c = hover and thumbHover or thumbBase
            local a = (hover and 0.90 or 0.68) * alpha
            ApplyTextureGradient(thumb, "VERTICAL", { math.min(c[1] * 1.22, 1), math.min(c[2] * 1.18, 1), math.min(c[3] * 1.12, 1), a }, { c[1] * 0.72, c[2] * 0.78, c[3] * 0.86, a }, true)
        end
    end
    local rawSetVerticalScroll = scroll.SetVerticalScroll
    local function UpdateThumbPosition(offset, maxScroll)
        maxScroll = math.max(0, AccessibleNumber(maxScroll, 0))
        offset = ClampScrollValue(offset, maxScroll)
        local barH = (bar.GetHeight and bar:GetHeight()) or 0
        local thumbH = (thumb.GetHeight and thumb:GetHeight()) or 0
        local travel = math.max(0, barH - thumbH)
        local y = maxScroll > 0 and -(offset / maxScroll) * travel or 0
        if thumb._msuf2LastY ~= y then
            thumb._msuf2LastY = y
            thumb:ClearAllPoints()
            thumb:SetPoint("TOP", bar, "TOP", 0, y)
        end
    end
    local function CurrentMaxScroll()
        local maxScroll = scroll._msuf2MaxScroll
        if maxScroll == nil then
            local child = scroll.GetScrollChild and scroll:GetScrollChild()
            local childH = (child and child.GetHeight and child:GetHeight()) or 0
            local frameH = (scroll.GetHeight and scroll:GetHeight()) or 0
            maxScroll = math.max(0, childH - frameH)
        end
        return maxScroll
    end
    local function SetRawScroll(offset, current, maxScroll)
        if maxScroll == nil then maxScroll = CurrentMaxScroll() end
        offset = ClampScrollValue(offset, maxScroll)
        if current == nil then current = (scroll.GetVerticalScroll and scroll:GetVerticalScroll()) or 0 end
        current = AccessibleNumber(current, 0)
        if rawSetVerticalScroll and math.abs(offset - current) > 0.01 then rawSetVerticalScroll(scroll, offset) end
        if bar then
            bar._msuf2LastScrollValue = offset
            UpdateThumbPosition(offset, maxScroll)
        end
        return offset
    end
    local function StopSmoothScroll()
        scroll._msuf2SmoothScrollTarget = nil
        local driver = scroll._msuf2SmoothScrollDriver
        if driver then driver:Hide() end
    end
    local function SmoothScrollOnUpdate(_, elapsed)
        local target = scroll._msuf2SmoothScrollTarget
        if target == nil then
            StopSmoothScroll()
            return
        end
        local maxScroll = CurrentMaxScroll()
        target = ClampScrollValue(target, maxScroll)
        scroll._msuf2SmoothScrollTarget = target
        local current = AccessibleNumber((scroll.GetVerticalScroll and scroll:GetVerticalScroll()) or 0, 0)
        local delta = target - current
        if (T.ReducedMotionEnabled and T.ReducedMotionEnabled()) or math.abs(delta) <= SMOOTH_SCROLL_EPSILON then
            SetRawScroll(target, current, maxScroll)
            StopSmoothScroll()
            return
        end
        elapsed = tonumber(elapsed) or 0
        if elapsed > SMOOTH_SCROLL_MAX_ELAPSED then elapsed = SMOOTH_SCROLL_MAX_ELAPSED end
        local blend = math.min(1, elapsed * SMOOTH_SCROLL_SPEED)
        if blend <= 0 then return end
        SetRawScroll(current + delta * blend, current, maxScroll)
    end
    local function EnsureSmoothScrollDriver()
        local driver = scroll._msuf2SmoothScrollDriver
        if driver then return driver end
        driver = CreateFrame("Frame", nil, scroll)
        driver:Hide()
        driver:SetScript("OnUpdate", SmoothScrollOnUpdate)
        scroll._msuf2SmoothScrollDriver = driver
        return driver
    end
    local function SmoothScrollTo(offset)
        local maxScroll = CurrentMaxScroll()
        local target = ClampScrollValue(offset, maxScroll)
        if T.ReducedMotionEnabled and T.ReducedMotionEnabled() then
            SetRawScroll(target, nil, maxScroll)
            StopSmoothScroll()
            return
        end
        local current = AccessibleNumber((scroll.GetVerticalScroll and scroll:GetVerticalScroll()) or 0, 0)
        if math.abs(target - current) <= SMOOTH_SCROLL_EPSILON then
            SetRawScroll(target, current, maxScroll)
            StopSmoothScroll()
            return
        end
        scroll._msuf2SmoothScrollTarget = target
        EnsureSmoothScrollDriver():Show()
    end
    local function Refresh()
        if scroll.IsShown and not scroll:IsShown() then
            StopSmoothScroll()
            if bar.Hide and bar:IsShown() then bar:Hide() end
            return
        end
        local child = scroll.GetScrollChild and scroll:GetScrollChild()
        local childH = (child and child.GetHeight and child:GetHeight()) or 0
        local frameH = (scroll.GetHeight and scroll:GetHeight()) or 0
        local maxScroll = math.max(0, childH - frameH)
        scroll._msuf2MaxScroll = maxScroll
        if scroll._msuf2SmoothScrollTarget ~= nil then scroll._msuf2SmoothScrollTarget = ClampScrollValue(scroll._msuf2SmoothScrollTarget, maxScroll) end
        if maxScroll <= 1 or frameH <= 0 then
            StopSmoothScroll()
            local current = AccessibleNumber(scroll:GetVerticalScroll() or 0, 0)
            if rawSetVerticalScroll and current ~= 0 then rawSetVerticalScroll(scroll, 0) end
            bar._msuf2LastScrollValue = 0
            UpdateThumbPosition(0, 0)
            if bar.Hide and bar:IsShown() then bar:Hide() end
            return
        end
        if bar.Show and not bar:IsShown() then bar:Show() end
        bar._msuf2LastMaxScroll = maxScroll
        local visibleRatio = frameH / math.max(childH, 1)
        local barH = (bar.GetHeight and bar:GetHeight()) or frameH
        local thumbH = math.floor(math.max(34, math.min(barH, barH * visibleRatio)) + 0.5)
        if thumb and thumb.SetHeight and thumb._msuf2LastHeight ~= thumbH then
            thumb._msuf2LastHeight = thumbH
            thumb:SetHeight(thumbH)
            thumb._msuf2LastY = nil
        end
        local current = AccessibleNumber(scroll:GetVerticalScroll() or 0, 0)
        local offset = ClampScrollValue(current, maxScroll)
        if offset ~= current and rawSetVerticalScroll then rawSetVerticalScroll(scroll, offset) end
        bar._msuf2LastScrollValue = offset
        UpdateThumbPosition(offset, maxScroll)
        Paint(bar._msuf2Hover)
    end
    scroll._msuf2RefreshScrollBar = Refresh
    scroll.SetVerticalScroll = function(self, offset)
        StopSmoothScroll()
        local maxScroll = self._msuf2MaxScroll
        if maxScroll == nil then
            local child = self.GetScrollChild and self:GetScrollChild()
            local childH = (child and child.GetHeight and child:GetHeight()) or 0
            local frameH = (self.GetHeight and self:GetHeight()) or 0
            maxScroll = math.max(0, childH - frameH)
        end
        local clamped = ClampScrollValue(offset, maxScroll)
        local current = AccessibleNumber((self.GetVerticalScroll and self:GetVerticalScroll()) or 0, 0)
        if math.abs(clamped - current) > 0.01 then rawSetVerticalScroll(self, clamped) end
        if self._msuf2RefreshScrollBar then self:_msuf2RefreshScrollBar() end
    end
    local function ScrollBy(delta)
        if not delta or delta == 0 then return end
        local step = 64
        if IsShiftKeyDown and IsShiftKeyDown() then step = 180 end
        if IsControlKeyDown and IsControlKeyDown() then step = math.max(step, (scroll.GetHeight and scroll:GetHeight()) or step) end
        local current = AccessibleNumber(scroll:GetVerticalScroll() or 0, 0)
        SmoothScrollTo((scroll._msuf2SmoothScrollTarget or current) - delta * step)
    end
    -- Fixed page headers are siblings of this ScrollFrame. Expose the exact
    -- styled wheel path so their chrome and interactive preview shells can
    -- forward ordinary wheel input without depending on frame propagation.
    scroll._msuf2ScrollByWheel = ScrollBy
    local function CursorYInBarSpace()
        if type(GetCursorPosition) ~= "function" then return nil end
        local _, y = GetCursorPosition()
        local scale = (bar.GetEffectiveScale and bar:GetEffectiveScale()) or 1
        scale = AccessibleNumber(scale, 1)
        if scale <= 0 then scale = 1 end
        return AccessibleNumber(y, 0) / scale
    end
    local function StopBarDrag()
        bar._msuf2DragStartY = nil
        bar._msuf2DragStartOffset = nil
        bar:SetScript("OnUpdate", nil)
    end
    local function DragBar()
        if type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then
            StopBarDrag()
            return
        end
        local startY = bar._msuf2DragStartY
        local cursorY = CursorYInBarSpace()
        if startY == nil or cursorY == nil then return end
        local maxScroll = CurrentMaxScroll()
        local barH = (bar.GetHeight and bar:GetHeight()) or 0
        local thumbH = (thumb.GetHeight and thumb:GetHeight()) or 0
        local travel = math.max(1, barH - thumbH)
        local startOffset = ClampScrollValue(bar._msuf2DragStartOffset, maxScroll)
        local target = startOffset - (cursorY - startY) * (maxScroll / travel)
        SetRawScroll(target, nil, maxScroll)
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
    bar:SetScript("OnMouseDown", function(_, button)
        if button and button ~= "LeftButton" then return end
        StopSmoothScroll()
        bar._msuf2DragStartY = CursorYInBarSpace()
        bar._msuf2DragStartOffset = AccessibleNumber((scroll.GetVerticalScroll and scroll:GetVerticalScroll()) or 0, 0)
        if bar._msuf2DragStartY ~= nil then bar:SetScript("OnUpdate", DragBar) end
    end)
    bar:SetScript("OnMouseUp", StopBarDrag)
    scroll:HookScript("OnScrollRangeChanged", Refresh)
    scroll:HookScript("OnSizeChanged", Refresh)
    scroll:HookScript("OnHide", function()
        StopSmoothScroll()
        StopBarDrag()
        if bar.Hide then bar:Hide() end
    end)
    scroll:HookScript("OnShow", Refresh)
    if bar.HookScript then
        bar:HookScript("OnHide", StopBarDrag)
        bar:HookScript("OnShow", function() Paint(bar._msuf2Hover) end)
    end
    Refresh()
    scroll._msuf2ScrollBar = bar
    return bar
end
if MSUF and MSUF.UI and MSUF.UI.BindMenu2Theme then
    MSUF.UI.BindMenu2Theme(T)
    M.UI = MSUF.UI
end

-- Apply the saved menu accent as soon as SavedVariables are readable so every
-- themed consumer (window shell, popups, edit-mode chrome) bakes the same
-- accent family. BuildWindow keeps a guarded second call as a fallback.
do
    local function ApplySavedAccent()
        if type(T.ApplyMenuAccent) == "function" then T.ApplyMenuAccent() end
    end
    if type(_G.IsLoggedIn) == "function" and _G.IsLoggedIn() then
        ApplySavedAccent()
    else
        local accentInit = _G.CreateFrame("Frame")
        accentInit:RegisterEvent("PLAYER_LOGIN")
        accentInit:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            ApplySavedAccent()
        end)
    end
end
