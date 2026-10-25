local _, MSUF = ...
local M = MSUF.MSUF2
local T = M.Theme
local FILE = "Shell/Menu2/MSUF_Menu2_Theme_Fonts.lua"
local PixelLayoutLeaf = MSUF.Require("PreparePixelLayoutLeaf", FILE, MSUF.Util)
local SetFontChecked = MSUF.Require("MSUF_SetFontChecked", FILE)
local CoreFont = {
    ResolveSafe = MSUF.Require("MSUF_ResolveSafeFontPath", FILE),
    PathMatches = MSUF.Require("MSUF_FontPathEquals", FILE),
    KeyPath = MSUF.Require("MSUF_ResolveFontKeyPath", FILE),
}
local SharedUI, MenuSkin = MSUF.UI, MSUF.MenuSkin
local Tr = M.Tr

local NO_MENU_FONT = {}
local menuFontCache = {}
local styledFontCache, styledMenuFontKey = {}, nil
local function MenuGeneralDB()
    return M.GetGeneralDB()
end
local function ResolveMenuFontPath(size, flags, role)
    local g = MenuGeneralDB()
    -- No theme sets a heading font: the Classic Glass preset keeps the user's
    -- readable menu font, so headings follow menuFontKey like every role.
    local key = type(g) == "table" and g.menuFontKey or nil
    if type(key) ~= "string" or key == "" then return nil end
    size = tonumber(size) or 14
    flags = flags or ""
    local cacheKey = key .. "|" .. tostring(size) .. "|" .. tostring(flags) .. "|" .. tostring(role or "")
    local cached = menuFontCache[cacheKey]
    if cached ~= nil then return cached ~= NO_MENU_FONT and cached or nil end
    local path = key
    if not (path:find("\\", 1, true) or path:find("/", 1, true)) then
        path = CoreFont.KeyPath(key, size, flags) or path
    end
    path = CoreFont.ResolveSafe(path, size, flags, key)
    path = SharedUI.ResolveRoleFontPath(path, role == "navigation" and "card" or role)
    if type(path) ~= "string" or path == "" then path = nil end
    menuFontCache[cacheKey] = path or NO_MENU_FONT
    return path
end
function T.ClearMenuFontCache()
    menuFontCache, styledFontCache = {}, {}
end
-- FontStrings share resolved styles, while each string still verifies native
-- readback. A caller changing SetFont directly is repaired on the next apply.
local function StyledFont(font, size, role)
    local general = MenuGeneralDB()
    local key = type(general) == "table" and general.menuFontKey or nil
    if key ~= styledMenuFontKey then
        styledFontCache, styledMenuFontKey = {}, key
    end
    local fonts = styledFontCache[font]
    if not fonts then
        fonts = {}
        styledFontCache[font] = fonts
    end
    local roles = fonts[role or false]
    if not roles then
        roles = {}
        fonts[role or false] = roles
    end
    local style = roles[size]
    if not style then
        local path = ResolveMenuFontPath(size, "", role) or font
        style = { font = path, key = tostring(path or "") .. "\030" .. tostring(size or "") .. "\030" }
        roles[size] = style
    end
    return style
end
local function NormalizeAppliedFontPath(path)
    if type(path) ~= "string" then return nil end
    return path:gsub("/", "\\"):lower()
end
local function FontPathMatches(expected, actual)
    if expected == actual then return true end
    if CoreFont.PathMatches(expected, actual) == true then return true end
    expected, actual = NormalizeAppliedFontPath(expected), NormalizeAppliedFontPath(actual)
    return expected ~= nil and actual ~= nil and expected == actual
end
local function FontApplicationMatches(expectedFont, expectedSize, expectedFlags, actualFont, actualSize, actualFlags)
    if not FontPathMatches(expectedFont, actualFont) then return false end
    if type(actualSize) == "number" and math.abs(actualSize - expectedSize) > 0.01 then return false end
    if tostring(actualFlags or "") ~= tostring(expectedFlags or "") then return false end
    -- Hidden FontStrings may have zero glyph width despite a ready font tuple.
    return true
end
local function TryApplyStyledFont(fs, font, size, flags)
    if type(font) ~= "string" or font == "" then return false end
    return SetFontChecked(fs, font, size, flags) and FontApplicationMatches(font, size, flags, fs:GetFont())
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
    -- Menu text sits on its own surface; inherited outlines blur small labels.
    local nextFlags = ""
    local style = StyledFont(orig.font or font, nextSize, role)
    local nextFont, fontKey = style.font, style.key
    if not force and fs._msuf2AppliedFontKey == fontKey and FontApplicationMatches(nextFont, nextSize, nextFlags, font, size, flags) then
        return true
    end
    local applied = TryApplyStyledFont(fs, nextFont, nextSize, nextFlags)
    -- Cold font readback can lag the native request. Leave it uncached for the
    -- next layout/font refresh; never abort construction of the options window.
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
    local entry = M.FindPageEntry(fs)
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
    if T.fontRoleColors and (color == nil or color == T.colors.text) then
        color = T.fontRoleColors[role or (fs and fs._msuf2FontRole)] or color
    end
    MenuSkin.TrackText(fs, color or T.colors.text)
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
    if fs.SetShadowColor and fs._msuf2ShadowColorKey ~= "0:0:0:0" then
        fs._msuf2ShadowColorKey = "0:0:0:0"
        fs:SetShadowColor(0, 0, 0, 0)
    end
    if fs.SetShadowOffset and fs._msuf2ShadowOffsetKey ~= "0:0" then
        fs._msuf2ShadowOffsetKey = "0:0"
        fs:SetShadowOffset(0, 0)
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
local function FontSetText(self, value) return self._msuf2RawSetText(self, Tr(value or "")) end
-- Text that is translated already (composed, formatted or a locale name) goes
-- through the raw setter: a second lookup would log it as a missing key.
function T.SetTranslatedText(fs, text)
    local raw = fs._msuf2RawSetText
    if raw then return raw(fs, text) end
    return fs:SetText(text)
end
function T.Font(parent, template, text, color, role)
    local fs = PixelLayoutLeaf(parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight"))
    fs._msuf2FontRole = role
    fs._msuf2RawSetText = fs.SetText
    fs.SetText = FontSetText
    fs:SetText(text or "")
    return T.StyleFontString(fs, color or T.colors.text, 1, role)
end

