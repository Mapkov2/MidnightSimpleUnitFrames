local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local T = M.Theme
local W = M.Widgets

local floor = math.floor
local max = math.max
local min = math.min
local CreateFrame = _G.CreateFrame
local CreateColor = _G.CreateColor

local function DashboardTrimText(text)
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function DashboardNormalizeText(text)
    text = DashboardTrimText(text):lower()
    text = text:gsub("[\"'`]", "")
    text = text:gsub("%s+", " ")
    return text
end

local function DashboardContainsAny(text, terms)
    text = tostring(text or "")
    if type(terms) ~= "table" then return false end
    for i = 1, #terms do
        local term = terms[i]
        if term and term ~= "" and text:find(term, 1, true) then return true end
    end
    return false
end

local function DashboardLooksLikeQuestion(raw, normalized)
    raw = tostring(raw or "")
    normalized = tostring(normalized or "")
    if raw:find("?", 1, true) then return true end
    return normalized:find("^where ") ~= nil
        or normalized:find("^how ") ~= nil
        or normalized:find("^why ") ~= nil
        or normalized:find("^what ") ~= nil
        or normalized:find("^which ") ~= nil
        or normalized:find("^can i ") ~= nil
        or normalized:find("^do i ") ~= nil
        or normalized:find("^is ") ~= nil
        or normalized:find("^are ") ~= nil
        or normalized:find("^does ") ~= nil
        or normalized:find("^tell me ") ~= nil
        or normalized:find("^explain ") ~= nil
        or normalized:find("^help with ") ~= nil
end

local DASHBOARD_COLOR_ALIASES = {
    gray = "grey",
    teal = "turquoise",
    aqua = "cyan",
    violet = "purple",
}

local DASHBOARD_FALLBACK_COLORS = {
    white = { 1.0, 1.0, 1.0 },
    black = { 0.0, 0.0, 0.0 },
    red = { 1.0, 0.0, 0.0 },
    green = { 0.0, 1.0, 0.0 },
    blue = { 0.0, 0.0, 1.0 },
    yellow = { 1.0, 1.0, 0.0 },
    cyan = { 0.0, 1.0, 1.0 },
    magenta = { 1.0, 0.0, 1.0 },
    orange = { 1.0, 0.5, 0.0 },
    purple = { 0.6, 0.0, 0.8 },
    pink = { 1.0, 0.6, 0.8 },
    turquoise = { 0.0, 0.9, 0.8 },
    grey = { 0.5, 0.5, 0.5 },
    brown = { 0.6, 0.3, 0.1 },
    gold = { 1.0, 0.85, 0.1 },
}

local function DashboardClamp01(value)
    value = tonumber(value) or 0
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function DashboardColorFromName(name)
    name = DASHBOARD_COLOR_ALIASES[tostring(name or ""):lower()] or tostring(name or ""):lower()
    local palette = (type(MSUF) == "table" and MSUF.MSUF_FONT_COLORS) or _G.MSUF_FONT_COLORS or DASHBOARD_FALLBACK_COLORS
    local color = palette and palette[name]
    if type(color) == "table" then
        return DashboardClamp01(color[1] or color.r or 1), DashboardClamp01(color[2] or color.g or 1), DashboardClamp01(color[3] or color.b or 1), name
    end
    color = DASHBOARD_FALLBACK_COLORS[name]
    if type(color) == "table" then
        return color[1], color[2], color[3], name
    end
end

local function DashboardExtractCommandColor(query)
    local raw = tostring(query or "")
    local hex = raw:match("#(%x%x%x%x%x%x)") or raw:match("0x(%x%x%x%x%x%x)")
    if hex then
        local r = tonumber(hex:sub(1, 2), 16) or 255
        local g = tonumber(hex:sub(3, 4), 16) or 255
        local b = tonumber(hex:sub(5, 6), 16) or 255
        return r / 255, g / 255, b / 255, "#" .. hex:upper()
    end

    local rr, gg, bb = raw:match("(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
    if rr and gg and bb then
        local r = tonumber(rr) or 255
        local g = tonumber(gg) or 255
        local b = tonumber(bb) or 255
        if r > 1 or g > 1 or b > 1 then
            r, g, b = r / 255, g / 255, b / 255
        end
        return DashboardClamp01(r), DashboardClamp01(g), DashboardClamp01(b), M.Format("%d,%d,%d", tonumber(rr) or 255, tonumber(gg) or 255, tonumber(bb) or 255)
    end

    local normalized = DashboardNormalizeText(raw)
    for word in normalized:gmatch("%S+") do
        local r, g, b, label = DashboardColorFromName(word)
        if r then return r, g, b, label end
    end
end

local function DashboardCallGlobal(name, ...)
    local fn = _G[name]
    if type(fn) == "function" then return pcall(fn, ...) end
end

local function DashboardApplyVisuals(reason)
    local api = type(MSUF) == "table" and MSUF._colorsAPI
    if api and type(api.PushVisualUpdates) == "function" then pcall(api.PushVisualUpdates) end
    if M.RequestGeneralApply then M.RequestGeneralApply(reason or "MSUF2_COMMAND", { preview = true, applyAll = false }) end
    DashboardCallGlobal("MSUF_UpdateAllFonts_Immediate")
    DashboardCallGlobal("MSUF_RefreshAllFrames")
    DashboardCallGlobal("MSUF_UFPreview_RequestRefresh", reason or "MSUF2_COMMAND")
end

local function DashboardSetGlobalFontColor(r, g, b)
    local api = type(MSUF) == "table" and MSUF._colorsAPI
    if api and type(api.SetGlobalFontColor) == "function" then
        pcall(api.SetGlobalFontColor, r, g, b)
    else
        local gen = M.GetGeneralDB and M.GetGeneralDB()
        if type(gen) == "table" then
            gen.useCustomFontColor = true
            gen.fontColorCustomR, gen.fontColorCustomG, gen.fontColorCustomB = r, g, b
        end
    end
    DashboardApplyVisuals("MSUF2_COMMAND_FONT_COLOR")
end

local function DashboardResetGlobalFontColor()
    local api = type(MSUF) == "table" and MSUF._colorsAPI
    if api and type(api.ResetGlobalFontToPalette) == "function" then
        pcall(api.ResetGlobalFontToPalette)
    else
        local gen = M.GetGeneralDB and M.GetGeneralDB()
        if type(gen) == "table" then
            gen.useCustomFontColor = false
            gen.fontColorCustomR, gen.fontColorCustomG, gen.fontColorCustomB = nil, nil, nil
        end
    end
    DashboardApplyVisuals("MSUF2_COMMAND_FONT_COLOR_RESET")
end

local function DashboardSetBarMode(mode)
    local gen = M.GetGeneralDB and M.GetGeneralDB()
    if type(gen) ~= "table" then return false end
    mode = (mode == "class" or mode == "unified" or mode == "gradient") and mode or "dark"
    gen.barMode = mode
    gen.darkMode = (mode == "dark")
    gen.useClassColors = (mode == "class")
    DashboardApplyVisuals("MSUF2_COMMAND_BAR_MODE")
    return true
end

local function GetBundledChangelog()
    local data = (type(MSUF) == "table" and MSUF.MSUF_Changelog) or _G.MSUF_Changelog
    if type(data) ~= "table" or type(data.entries) ~= "table" or type(data.entries[1]) ~= "table" then
        return nil
    end
    return data
end

local function BuildDashboardChangelog(parent, cardWidth, opts)
    opts = opts or {}
    local data = GetBundledChangelog()
    local sectionHeader = opts.sectionHeader == true
    local left, right = sectionHeader and 0 or 14, sectionHeader and 0 or 14
    local bodyLeft = opts.bodyLeft or (sectionHeader and 16 or left)
    local top = opts.top or -130
    local headerH = sectionHeader and 42 or 48
    local contentW = max(120, (cardWidth or 420) - left - right)
    local scrollW = max(80, (cardWidth or 420) - bodyLeft - 44)

    local function RawFont(parentFrame, template, text, color, bump)
        local fs = parentFrame:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
        if T.StyleFontString then
            T.StyleFontString(fs, color or T.colors.muted, bump or 0)
        elseif color and fs.SetTextColor then
            fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
        end
        fs:SetText(tostring(text or ""))
        return fs
    end

    if not sectionHeader then
        local line = parent:CreateTexture(nil, "BORDER")
        line:SetPoint("TOPLEFT", parent, "TOPLEFT", left, top + 4)
        line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -right, top + 4)
        line:SetHeight(1)
        line:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.38)
    end

    local header = CreateFrame("Button", nil, parent)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", left, top)
    if sectionHeader then
        header:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -right, top)
        header:SetHeight(headerH)
    else
        header:SetSize(contentW, headerH)
    end

    local headerBg = header:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints()
    headerBg:SetColorTexture(0, 0, 0, 0)

    local headerEdge = header:CreateTexture(nil, "BORDER")
    headerEdge:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    headerEdge:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    headerEdge:SetHeight(1)
    headerEdge:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.44)

    local hover = header:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.025)

    local arrow = header:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(10, 10)
    if sectionHeader then
        arrow:SetPoint("LEFT", header, "LEFT", 16, 0)
    else
        arrow:SetPoint("TOPRIGHT", header, "TOPRIGHT", -54, -9)
    end
    arrow:SetTexture(T.media.collapseArrow)

    local title = T.Font(header, "GameFontNormal", M.Tr(opts.title or "Changelog"), T.colors.text)
    if sectionHeader then
        title:SetPoint("LEFT", arrow, "RIGHT", 8, 0)
        title:SetPoint("RIGHT", header, "RIGHT", -94, 0)
    else
        title:SetPoint("TOPLEFT", header, "TOPLEFT", 0, -3)
        title:SetPoint("RIGHT", header, "RIGHT", -92, 0)
    end
    title:SetJustifyH("LEFT")

    local current = data and (data.currentVersion or (data.entries[1] and data.entries[1].version)) or nil
    local range = data and (data.rangeLabel or current or "") or M.Tr("No release notes bundled with this build.")
    local subtitle = RawFont(header, "GameFontDisableSmall", range, T.colors.dim, 0)
    if sectionHeader then
        subtitle:SetPoint("RIGHT", header, "RIGHT", -72, 0)
        subtitle:SetWidth(max(80, min(210, contentW - 190)))
        subtitle:SetJustifyH("RIGHT")
        subtitle:Hide()
    else
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
        subtitle:SetPoint("RIGHT", header, "RIGHT", -8, 0)
        subtitle:SetJustifyH("LEFT")
    end

    local hint = T.Font(header, "GameFontDisableSmall", "", T.colors.dim)
    if sectionHeader then
        hint:SetPoint("RIGHT", header, "RIGHT", -16, 0)
    else
        hint:SetPoint("TOPRIGHT", header, "TOPRIGHT", -8, -5)
    end
    hint:SetJustifyH("RIGHT")

    local summary = RawFont(parent, "GameFontHighlightSmall", "", T.colors.muted, 0)
    summary:SetPoint("TOPLEFT", parent, "TOPLEFT", bodyLeft + 10, top - headerH - 8)
    summary:SetWidth(max(80, (cardWidth or contentW) - bodyLeft - 28))
    summary:SetJustifyH("LEFT")
    if summary.SetWordWrap then summary:SetWordWrap(true) end

    if not data then
        header:EnableMouse(false)
        hint:SetText("")
        summary:SetText(M.Tr("No release notes bundled with this build."))
        if arrow.SetVertexColor then arrow:SetVertexColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], 0.55) end
        return
    end

    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", bodyLeft + 2, top - headerH - 12)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -34, opts.bottom or 70)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(scrollW, 1)
    scroll:SetScrollChild(child)

    local y = -2
    local function AddText(text, fontObject, color, indent, gap, translate)
        local rawText = tostring(text or "")
        if translate and type(M.Tr) == "function" then
            rawText = M.Tr(rawText)
        end
        local fs = RawFont(child, fontObject or "GameFontHighlightSmall", rawText, color or T.colors.muted, 0)
        indent = indent or 0
        fs:SetPoint("TOPLEFT", child, "TOPLEFT", indent, y)
        fs:SetWidth(max(40, scrollW - indent - 2))
        fs:SetJustifyH("LEFT")
        if fs.SetWordWrap then fs:SetWordWrap(true) end
        if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
        fs:SetText(rawText)
        local h = (fs.GetStringHeight and fs:GetStringHeight()) or 0
        if h < 10 then h = 12 end
        y = y - h - (gap or 4)
        return fs
    end

    local function AddBullet(text, dotColor, textColor)
        dotColor = dotColor or T.colors.accent
        textColor = textColor or T.colors.muted
        local dot = child:CreateTexture(nil, "ARTWORK")
        dot:SetSize(3, 3)
        dot:SetPoint("TOPLEFT", child, "TOPLEFT", 8, y - 6)
        dot:SetColorTexture(dotColor[1], dotColor[2], dotColor[3], 0.88)
        return AddText(text, "GameFontHighlightSmall", textColor, 18, 5, true)
    end

    local entries = data.entries
    local maxEntries = min(#entries, 4)
    for entryIndex = 1, maxEntries do
        local entry = entries[entryIndex]
        if type(entry) == "table" then
            local version = tostring(entry.version or "")
            local date = tostring(entry.date or "")
            local heading = (date ~= "" and (version .. " - " .. date)) or version
            AddText(heading, "GameFontNormalSmall", T.colors.accent, 0, 8)

            local sections = entry.sections
            if type(sections) == "table" then
                for sectionIndex = 1, #sections do
                    local section = sections[sectionIndex]
                    if type(section) == "table" and type(section.bullets) == "table" and #section.bullets > 0 then
                        if sectionIndex > 1 then y = y - 3 end
                        local sectionTitle = tostring(section.title or "")
                        local isHighlights = sectionTitle == "Highlights"
                        AddText(sectionTitle, "GameFontNormalSmall", isHighlights and T.colors.accent or T.colors.accent2, 0, 4, true)
                        for bulletIndex = 1, #section.bullets do
                            AddBullet(
                                tostring(section.bullets[bulletIndex] or ""),
                                isHighlights and T.colors.accent2 or nil,
                                isHighlights and T.colors.text or nil
                            )
                        end
                    end
                end
            end
        end
    end

    child:SetHeight(max(1, math.abs(y) + 8))
    if T.StyleScrollFrame then T.StyleScrollFrame(scroll, parent) end

    local latest = entries[1]
    local sectionCount = 0
    if latest and type(latest.sections) == "table" then sectionCount = #latest.sections end
    local currentLabel = current or "Latest build"
    summary:SetText(M.Format(M.Tr("%s  -  %d sections. Click to view the bundled changelog."), currentLabel, sectionCount))

    local open = M.dashboardChangelogOpen == true
    local function PaintHeader(isOpen)
        if T.ApplyCollapseVisual then T.ApplyCollapseVisual(arrow, nil, isOpen) end
        if headerBg.SetColorTexture then
            headerBg:SetColorTexture(0, 0, 0, 0)
        end
        if headerEdge.SetColorTexture then
            headerEdge:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], isOpen and 0.58 or 0.34)
        end
        hint:SetText(isOpen and M.Tr("Hide") or M.Tr("View"))
    end
    local function RefreshOpenState()
        M.dashboardChangelogOpen = open
        M.PersistMenuStateValue("dashboardChangelogOpen", open)
        scroll:SetShown(open)
        summary:SetShown((not open) and not opts.hideSummaryWhenClosed)
        PaintHeader(open)
        if open then
            if scroll._msuf2RefreshScrollBar then scroll:_msuf2RefreshScrollBar() end
        elseif scroll._msuf2ScrollBar then
            scroll._msuf2ScrollBar:Hide()
        end
    end

    header:SetScript("OnClick", function()
        open = not open
        RefreshOpenState()
        if type(opts.onToggle) == "function" then opts.onToggle(open) end
    end)
    header:SetScript("OnEnter", function()
        if headerBg.SetColorTexture then headerBg:SetColorTexture(1, 1, 1, 0.025) end
    end)
    header:SetScript("OnLeave", function()
        PaintHeader(open)
    end)
    RefreshOpenState()
end

local function BuildDashboardUX(ctx)
    local root = ctx.wrapper
    local width = ctx.width or 760
    local x0, y0, gap = 12, -12, 16
    local layoutW = max(1, width - x0)
    local sideBySide = layoutW >= 760
    local sideW = sideBySide and min(330, max(300, math.floor(layoutW * 0.31))) or layoutW
    local mainW = sideBySide and (layoutW - sideW - gap) or layoutW
    local sideX = sideBySide and (x0 + mainW + gap) or x0

    local function Card(parent, title, x, y, w, h, bg, border)
        local card = T.Panel(parent or root, nil, bg or T.colors.panel2, border or T.colors.cardBorder or T.colors.borderSoft)
        card:SetPoint("TOPLEFT", parent or root, "TOPLEFT", x, y)
        card:SetSize(w, h)
        if title and title ~= "" then
            local label = T.Font(card, "GameFontNormal", M.Tr(title), T.colors.text)
            label:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -14)
            card._msuf2Title = label
        end
        return card
    end

    local function SetDashboardGradient(texture, orientation, from, to)
        if not texture then return end
        from = from or { 1, 1, 1, 0 }
        to = to or { 1, 1, 1, 1 }
        local fromA = from[4] or 1
        local toA = to[4] or 1
        local media = T and T.media
        local horizontal = (orientation or "HORIZONTAL") == "HORIZONTAL"
        local path
        local color

        if horizontal then
            path = (toA >= fromA) and (media and media.gradHRev) or (media and media.gradH)
            color = (toA >= fromA) and to or from
        else
            path = (fromA >= toA) and (media and media.gradV) or (media and media.gradVRev)
            color = (fromA >= toA) and from or to
        end

        if path and path ~= "" then
            texture:SetTexture(path)
            texture:SetTexCoord(0, 1, 0, 1)
            if texture.SetVertexColor then
                texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
            end
        elseif texture.SetGradientAlpha then
            texture:SetTexture("Interface\\Buttons\\WHITE8X8")
            texture:SetGradientAlpha(orientation or "HORIZONTAL", from[1], from[2], from[3], fromA, to[1], to[2], to[3], toA)
        elseif texture.SetGradient and CreateColor then
            texture:SetTexture("Interface\\Buttons\\WHITE8X8")
            texture:SetGradient(orientation or "HORIZONTAL", CreateColor(from[1], from[2], from[3], fromA), CreateColor(to[1], to[2], to[3], toA))
        elseif texture.SetColorTexture then
            texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
        end
    end

    local function ApplyDashboardHeroGradient(card, w, h)
        if not (card and card.CreateTexture) or card._msuf2DashboardHeroGradient then return end
        card._msuf2DashboardHeroGradient = true

        local wash = card:CreateTexture(nil, "BACKGROUND", nil, 1)
        wash:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -2)
        wash:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -2, 2)
        SetDashboardGradient(wash, "HORIZONTAL", { 0.020, 0.026, 0.064, 0.00 }, { 0.030, 0.210, 0.285, 0.16 })

        local top = card:CreateTexture(nil, "BACKGROUND", nil, 2)
        top:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -2)
        top:SetPoint("TOPRIGHT", card, "TOPRIGHT", -2, -2)
        top:SetHeight(max(54, min(96, floor((h or 190) * 0.42))))
        SetDashboardGradient(top, "VERTICAL", { 0.080, 0.320, 0.430, 0.08 }, { 0.020, 0.030, 0.070, 0.00 })

        local focus = card:CreateTexture(nil, "BACKGROUND", nil, 3)
        focus:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -2)
        focus:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -2, 2)
        SetDashboardGradient(focus, "HORIZONTAL", { 0.080, 0.420, 0.560, 0.00 }, { 0.080, 0.420, 0.560, 0.05 })
    end

    local function Button(parent, text, x, y, w, h, onClick, skin)
        local btn = T.Button(parent, M.Tr(text or ""), w, h or 24)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        T.CenterButtonLabel(btn)
        if skin == "primary" and T.SkinPrimaryButton then T.SkinPrimaryButton(btn) end
        if skin == "danger" and T.SkinDangerButton then T.SkinDangerButton(btn) end
        if onClick then btn:SetScript("OnClick", onClick) end
        return btn
    end

    local function Kicker(parent, text, x, y, color)
        local fs = T.Font(parent, "GameFontDisableSmall", string.upper(M.Tr(text or "")), color or T.colors.accent)
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 16, y or -14)
        return fs
    end

    local function Pill(parent, text, x, y, w, color)
        local pill = T.Panel(parent, nil, { 0.055, 0.070, 0.135, 0.92 }, { 0.160, 0.220, 0.430, 0.70 })
        pill:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        pill:SetSize(w or 82, 20)
        local label = T.Font(pill, "GameFontDisableSmall", M.Tr(text or ""), color or T.colors.muted)
        label:SetPoint("CENTER", pill, "CENTER", 0, 0)
        label:SetJustifyH("CENTER")
        pill._msuf2Label = label
        return pill
    end

    local function AddTooltip(frame, title, text)
        return M.AddTooltip and M.AddTooltip(frame, title, text, {
            hook = true,
            titleAsLine = true,
            bodyColor = { 0.85, 0.85, 0.85 },
        }) or frame
    end

    local function MakeDashboardActionCard(card, title, tooltip, onClick, showArrow)
        if not (card and card.CreateTexture and card.HookScript) then return card end
        card:EnableMouse(true)

        local hover = card:CreateTexture(nil, "BORDER", nil, 4)
        hover:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -2)
        hover:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -2, 2)
        hover:SetColorTexture(0.240, 0.780, 0.940, 0.055)
        hover:Hide()
        card._msuf2DashboardActionHover = hover

        if showArrow then
            local arrow = T.Font(card, "GameFontNormal", ">", T.colors.dim)
            arrow:SetPoint("TOPRIGHT", card, "TOPRIGHT", -16, -18)
            arrow:SetJustifyH("RIGHT")
            card._msuf2DashboardActionArrow = arrow
        end

        card:HookScript("OnEnter", function(self)
            if self._msuf2DashboardActionHover then self._msuf2DashboardActionHover:Show() end
            local arrow = self._msuf2DashboardActionArrow
            if arrow and arrow.SetTextColor then
                arrow:SetTextColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 1)
            end
        end)
        card:HookScript("OnLeave", function(self)
            if self._msuf2DashboardActionHover then self._msuf2DashboardActionHover:Hide() end
            local arrow = self._msuf2DashboardActionArrow
            if arrow and arrow.SetTextColor then
                arrow:SetTextColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], T.colors.dim[4] or 1)
            end
        end)
        if onClick then card:SetScript("OnMouseUp", onClick) end
        AddTooltip(card, title, tooltip)
        return card
    end

    local function Select(pageKey)
        if M.SelectPage then M.SelectPage(pageKey) end
    end

    local function IsDashboardEditModeActive()
        return M.IsMSUFEditModeActive(true)
    end

    local function IsDashboardEditModeCombatLocked()
        return M.IsEditModeCombatLocked(true)
    end

    local function RefreshDashboardEditModeButtonSafe()
        if type(M.RefreshDashboardEditModeButton) == "function" then
            M.RefreshDashboardEditModeButton()
        end
    end

    local function RefreshMenuFramePrioritySafe()
        local fn = M.RefreshMenuFramePriority
        if type(fn) == "function" then fn() end
    end

    local function ToggleEditMode()
        local active = IsDashboardEditModeActive()
        if (not active) and IsDashboardEditModeCombatLocked() then
            if M.BlockCombatAction then M.BlockCombatAction() end
            RefreshDashboardEditModeButtonSafe()
            if M.frame and M.frame.RefreshStatus then M.frame:RefreshStatus() end
            return
        end
        if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
            _G.MSUF_SetMSUFEditModeDirect(not active)
        end
        RefreshMenuFramePrioritySafe()
        if C_Timer and C_Timer.After then C_Timer.After(0, RefreshMenuFramePrioritySafe) end
        RefreshDashboardEditModeButtonSafe()
        if M.frame and M.frame.RefreshStatus then M.frame:RefreshStatus() end
    end

    local function StartNewAssistantTask()
        local A = MSUF and MSUF.Assistant
        if not A then return end

        if A.Workflow and type(A.Workflow.CancelActiveWorkflow) == "function" then
            pcall(A.Workflow.CancelActiveWorkflow)
        end
        if type(A.CloseLargeTextPanel) == "function" then
            pcall(A.CloseLargeTextPanel)
        else
            A.largeTextPanel = nil
        end
        if type(A.ClearHistory) == "function" then
            A.ClearHistory()
        end

        local ui = A.dashboardUI
        if ui and ui.input then
            ui.input:SetText("")
            if ui.input.ClearFocus then ui.input:ClearFocus() end
            if ui.input._msufAssistantPlaceholder and ui.input._msufAssistantPlaceholder.SetShown then
                ui.input._msufAssistantPlaceholder:SetShown(true)
            end
        end
        if type(A.RequestRefreshUI) == "function" then
            A.RequestRefreshUI("assistant.new_task")
        elseif type(A.RefreshUI) == "function" then
            A.RefreshUI()
        end
    end

    local function CopyWagoLink()
        if type(_G.MSUF_ShowCopyLink) == "function" then
            _G.MSUF_ShowCopyLink("Wago MSUF Profiles", "https://wago.io/search/imports/wow/msuf")
        end
    end

    local function ExportBackup()
        local fn = _G.MSUF_ExportSelectionToString
        if type(fn) == "function" then
            local ok, value = pcall(fn, "all")
            if ok and type(value) == "string" and value ~= "" and type(_G.MSUF_ShowCopyLink) == "function" then
                _G.MSUF_ShowCopyLink("MSUF Profile Backup", value)
                return
            end
        end
        Select("profiles")
    end

    local function DashboardGlobalState()
        _G.MSUF_GlobalDB = _G.MSUF_GlobalDB or {}
        local gdb = _G.MSUF_GlobalDB
        gdb.global = (type(gdb.global) == "table") and gdb.global or {}
        gdb.global.dashboard = (type(gdb.global.dashboard) == "table") and gdb.global.dashboard or {}
        return gdb.global.dashboard
    end

    local function ActiveProfileKey()
        local key = tostring(_G.MSUF_ActiveProfile or "Default")
        if key == "" then key = "Default" end
        return key
    end

    local function WagoBackupConfirmed()
        local dash = DashboardGlobalState()
        local byProfile = dash.wagoProfileBackupConfirmed
        return type(byProfile) == "table" and byProfile[ActiveProfileKey()] == true
    end

    local function SetWagoBackupConfirmed(confirmed)
        local dash = DashboardGlobalState()
        dash.wagoProfileBackupConfirmed = (type(dash.wagoProfileBackupConfirmed) == "table") and dash.wagoProfileBackupConfirmed or {}
        local byProfile = dash.wagoProfileBackupConfirmed
        if confirmed == true then
            byProfile[ActiveProfileKey()] = true
        else
            byProfile[ActiveProfileKey()] = nil
        end
    end

    local function RefreshDashboard()
        if M.InvalidatePage then M.InvalidatePage("home") end
        if M.SelectPage then M.SelectPage("home") end
    end

    local function ConfirmWagoBackup()
        if WagoBackupConfirmed() then return end

        local function accept()
            SetWagoBackupConfirmed(true)
            RefreshDashboard()
        end

        if _G.StaticPopupDialogs and _G.StaticPopup_Show then
            local popup = _G.StaticPopupDialogs.MSUF2_WAGO_PROFILE_BACKUP_CONFIRM or {
                text = "%s",
                button1 = _G.YES or "Yes",
                button2 = _G.NO or "No",
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
                OnAccept = accept,
            }
            popup.button1 = _G.YES or "Yes"
            popup.button2 = _G.NO or "No"
            popup.OnAccept = accept
            _G.StaticPopupDialogs.MSUF2_WAGO_PROFILE_BACKUP_CONFIRM = popup
            _G.StaticPopup_Show("MSUF2_WAGO_PROFILE_BACKUP_CONFIRM", M.Tr("Have you backed up this MSUF profile before using the Wago MSUF page?"))
            return
        end

        accept()
    end

    local function Percent(value, fallback)
        return math.floor(((tonumber(value) or fallback or 1) * 100) + 0.5)
    end

    local function Clamp(v, minV, maxV)
        v = tonumber(v) or minV
        if v < minV then return minV end
        if v > maxV then return maxV end
        return v
    end

    local function SnapPct(value, minPct, maxPct, stepPct)
        stepPct = stepPct or 1
        local pct = math.floor((tonumber(value) or 100) / stepPct + 0.5) * stepPct
        return Clamp(pct, minPct or 25, maxPct or 150)
    end

    local function SetSliderValueSafe(slider, value)
        if not (slider and slider.SetValue) then return end
        slider._msuf2Refreshing = true
        slider:SetValue(value)
        if slider.editBox and slider._msuf2FormatValue then slider.editBox:SetText(slider._msuf2FormatValue(value)) end
        if slider._msuf2UpdateFill then slider:_msuf2UpdateFill() end
        slider._msuf2Refreshing = nil
    end

    local function HideSliderValueBox(slider)
        if slider and slider.editBox then slider.editBox:Hide() end
        if slider and slider._msuf2StepButtons then
            for i = 1, #slider._msuf2StepButtons do
                slider._msuf2StepButtons[i]:Hide()
            end
        end
        if slider and slider._msuf2Title and slider._msuf2Title.SetFontObject then
            slider._msuf2Title:SetFontObject("GameFontHighlight")
        end
    end

    local function EnablePercentWheel(slider, minPct, maxPct, stepPct)
        if not slider then return end
        slider:EnableMouseWheel(true)
        slider:SetScript("OnMouseWheel", function(self, delta)
            if not delta then return end
            local value = tonumber((self.GetValue and self:GetValue()) or 100) or 100
            value = value + ((delta > 0) and stepPct or -stepPct)
            self:SetValue(SnapPct(value, minPct, maxPct, stepPct))
        end)
    end

    local function PixelScale()
        if type(_G.MSUF_GetPixelPerfectScale) == "function" then
            local ok, v = pcall(_G.MSUF_GetPixelPerfectScale)
            if ok and tonumber(v) then return Clamp(v, 0.3, 1.5) end
        end
        if type(GetPhysicalScreenSize) == "function" then
            local _, h = GetPhysicalScreenSize()
            h = tonumber(h)
            if h and h > 0 then return Clamp(768 / h, 0.3, 1.5) end
        end
        return 1
    end

    local function GlobalState()
        local g = M.GetGeneralDB()
        g.UIScale = (type(g.UIScale) == "table") and g.UIScale or { Enabled = false, Scale = 1 }
        local ui = g.UIScale
        ui.Enabled = ui.Enabled == true
        ui.Scale = Clamp(ui.Scale, 0.3, 1.5)
        return g, ui
    end

    local function HasMovedFramesInEditMode()
        local g = M.GetGeneralDB and M.GetGeneralDB()
        if type(g) == "table" and g.hasMovedFramesInEditMode == true then return true end
        local st = rawget(_G, "MSUF_EditState")
        if type(st) == "table" and st.hasMovedFramesInEditMode == true then return true end

        local db = M.EnsureDB and M.EnsureDB() or _G.MSUF_DB
        if type(db) ~= "table" then return false end
        local defaults = {
            player = { -256, -180 },
            target = { 320, -180 },
            focus = { -260, -300 },
            targettarget = { 220, -300 },
            pet = { -275, -250 },
            boss = { 360, 230 },
            gf_party = { -400, 0 },
            gf_raid = { -500, 0 },
            gf_mythicraid = { -500, 0 },
        }
        for key, def in pairs(defaults) do
            local conf = db[key]
            if type(conf) == "table" then
                local x, y = tonumber(conf.offsetX), tonumber(conf.offsetY)
                if x and y and (math.abs(x - def[1]) > 0.5 or math.abs(y - def[2]) > 0.5) then
                    if type(g) == "table" then g.hasMovedFramesInEditMode = true end
                    return true
                end
            end
        end
        return false
    end

    local function CapturedCommand(label, source, fn)
        if type(M.CaptureHistory) == "function" then
            return M.CaptureHistory(label, source, fn)
        end
        if M.BlockCombatAction and M.BlockCombatAction() then return false end
        if type(fn) == "function" then return fn() end
        return false
    end

    local function CommandResult(kind, title, body)
        return {
            kind = kind or "info",
            title = title or "",
            body = body or "",
        }
    end

    local function ShortCommandLabel(text, limit)
        text = DashboardTrimText(text)
        limit = tonumber(limit) or 36
        if #text <= limit then return text end
        return text:sub(1, max(1, limit - 3)) .. "..."
    end

    local function CommandSearchResults(query)
        local api = M.Search
        if api and type(api.SearchPages) == "function" then
            local ok, results = pcall(api.SearchPages, query)
            if ok and type(results) == "table" then return results end
        end
        return {}
    end

    local function OpenCommandSearchResults(query)
        local api = M.Search
        if api and type(api.OpenResults) == "function" then
            api.OpenResults(query)
        elseif M.SearchBridge and type(M.SearchBridge.OpenSearchResults) == "function" then
            M.SearchBridge.OpenSearchResults(query)
        elseif M.SelectPage then
            M.searchQuery = query
            M.SelectPage("search")
        end
    end

    local function OpenCommandSearchRecord(rec, query)
        if type(rec) ~= "table" then
            OpenCommandSearchResults(query)
            return
        end
        if rec.noOpen then
            OpenCommandSearchResults(query)
            return
        end
        local fallback = rec.anchorFallback or rec.label or rec.title
        local api = M.Search
        if api and type(api.OpenTarget) == "function" then
            api.OpenTarget(rec.key, query, fallback, rec.anchor, rec.route)
        elseif M.SearchBridge and type(M.SearchBridge.OpenSearchTarget) == "function" then
            M.SearchBridge.OpenSearchTarget(rec.key, query, fallback, rec.anchor)
        else
            OpenCommandSearchResults(query)
        end
    end

    local function RunMSUFSlashCommand(message)
        local slash = _G.SlashCmdList and _G.SlashCmdList["MIDNIGHTSUF"]
        if type(slash) ~= "function" then return false end
        local ok = pcall(slash, message or "")
        return ok and true or false
    end

    local function ResetPageQuery(raw, normalized)
        local text = normalized or DashboardNormalizeText(raw)
        text = text:gsub("^msuf%s+", "")
        text = text:gsub("^please%s+", "")
        text = text:gsub("^reset%s+", "")
        text = text:gsub("^restore%s+", "")
        text = text:gsub("^default%s+", "")
        text = text:gsub("^defaults%s+", "")
        text = text:gsub("%s+to%s+defaults?$", "")
        text = text:gsub("%s+back%s+to%s+defaults?$", "")
        text = text:gsub("%s+settings?$", "")
        return DashboardTrimText(text)
    end

    local function FindResetPageCommandTarget(raw, normalized)
        if not (normalized:find("reset", 1, true)
            or normalized:find("restore", 1, true)
            or normalized:find("default", 1, true))
        then
            return nil
        end
        if DashboardContainsAny(normalized, {
            "reset positions", "reset frame positions", "reset all positions", "reset movers", "reset mover",
            "frames offscreen", "frame offscreen", "off screen", "offscreen",
        }) then
            return nil
        end

        local query = ResetPageQuery(raw, normalized)
        if query == "" then return nil end
        local results = CommandSearchResults(query)
        for i = 1, #results do
            local key = results[i] and results[i].key
            if type(key) == "string" and M.PageHasReset and M.PageHasReset(key) then
                local info = M.GetPageResetInfo and M.GetPageResetInfo(key)
                return key, (info and info.label) or results[i].title or results[i].label or key
            end
        end
        return nil
    end

    local function BuildPageResetCommand(raw, normalized)
        local pageKey, label = FindResetPageCommandTarget(raw, normalized)
        if not pageKey then return nil end
        label = tostring(label or pageKey)
        return {
            label = "Reset " .. label,
            ready = true,
            summary = M.Format("Opens the confirmation to reset %s to defaults.", label),
            execute = function()
                local ok
                if M.ShowPageResetConfirm then
                    ok = M.ShowPageResetConfirm(pageKey)
                elseif M.ResetPageToDefaults then
                    ok = M.ResetPageToDefaults(pageKey)
                end
                if ok == false or ok == nil then
                    return CommandResult("error", "Reset unavailable", M.Format("MSUF could not reset %s right now.", label))
                end
                return CommandResult("ok", "Reset " .. label, M.Format("Confirmation opened for %s.", label))
            end,
        }
    end

    local function BuildOpenSearchCommand(raw, normalized)
        if not (normalized:find("^open ")
            or normalized:find("^go to ")
            or normalized:find("^take me to ")
            or normalized:find("^find ")
            or normalized:find("^search ")
            or normalized:find("^show me ")
            or normalized:find("^help with ")
            or normalized:find("^explain ")
            or normalized:find("^tell me about "))
        then
            return nil
        end
        local query = normalized
        query = query:gsub("^open%s+", "")
        query = query:gsub("^go%s+to%s+", "")
        query = query:gsub("^take%s+me%s+to%s+", "")
        query = query:gsub("^find%s+", "")
        query = query:gsub("^search%s+for%s+", "")
        query = query:gsub("^search%s+", "")
        query = query:gsub("^show%s+me%s+", "")
        query = query:gsub("^help%s+with%s+", "")
        query = query:gsub("^explain%s+", "")
        query = query:gsub("^tell%s+me%s+about%s+", "")
        query = query:gsub("%s+settings?$", "")
        query = DashboardTrimText(query)
        if query == "" then return nil end
        local results = CommandSearchResults(query)
        local rec = results and results[1]
        if not rec then return nil end
        local label = tostring(rec.label or rec.title or query)
        return {
            label = "Open " .. label,
            ready = true,
            summary = M.Format("Opens the best MSUF match for %s.", query),
            execute = function()
                OpenCommandSearchRecord(rec, query)
                return CommandResult("ok", "Open " .. label, M.Format("Opened %s.", label))
            end,
        }
    end

    local COMMAND_ACTION_KINDS = {
        toggle = true,
        slider = true,
        dropdown = true,
        segment = true,
        color = true,
        textinput = true,
        button = true,
    }

    local function CommandTextNorm(text)
        text = DashboardNormalizeText(text):gsub("[^%w%s#%.%-]", " ")
        text = text:gsub("%s+", " ")
        return DashboardTrimText(text)
    end

    local function CommandAddQuery(queries, seen, text)
        text = CommandTextNorm(text)
        if text == "" or #text < 2 or seen[text] then return end
        seen[text] = true
        queries[#queries + 1] = text
    end

    local function CommandContainsWord(text, word)
        text = " " .. CommandTextNorm(text) .. " "
        return text:find(" " .. tostring(word or "") .. " ", 1, true) ~= nil
    end

    local function CommandContainsAnyWord(text, words)
        if type(words) ~= "table" then return false end
        for i = 1, #words do
            if CommandContainsWord(text, words[i]) then return true end
        end
        return false
    end

    local function CommandCleanSubject(normalized)
        local text = tostring(normalized or "")
        text = text:gsub("^turn%s+(.+)%s+on$", "%1")
        text = text:gsub("^turn%s+(.+)%s+off$", "%1")
        local prefixes = {
            "^msuf%s+", "^please%s+", "^can you%s+", "^could you%s+",
            "^i want%s+", "^i need%s+", "^move%s+", "^resize%s+",
            "^make%s+", "^set%s+", "^change%s+", "^adjust%s+",
            "^put%s+", "^switch%s+", "^swap%s+", "^pick%s+",
            "^increase%s+", "^decrease%s+", "^raise%s+", "^lower%s+",
            "^hide%s+", "^show%s+", "^enable%s+", "^disable%s+",
            "^turn%s+on%s+", "^turn%s+off%s+",
            "^run%s+", "^execute%s+", "^do%s+", "^add%s+", "^remove%s+",
            "^help%s+with%s+", "^explain%s+", "^tell%s+me%s+about%s+", "^tell%s+me%s+",
            "^show%s+me%s+", "^open%s+", "^go%s+to%s+", "^find%s+", "^search%s+for%s+",
            "^what%s+options%s+does%s+", "^what%s+choices%s+does%s+",
            "^what%s+values%s+can%s+", "^what%s+values%s+does%s+",
            "^which%s+options%s+for%s+", "^which%s+choices%s+for%s+", "^which%s+values%s+for%s+",
            "^which%s+", "^can%s+i%s+set%s+",
            "^what%s+is%s+", "^what%s+are%s+", "^what's%s+",
            "^show%s+current%s+", "^current%s+", "^is%s+",
        }
        for i = 1, #prefixes do text = text:gsub(prefixes[i], "") end
        text = text:gsub("^all%s+of%s+", "")
        text = text:gsub("^all%s+", "")
        text = text:gsub("^every%s+", "")
        text = text:gsub("^each%s+", "")
        text = text:gsub("%s+by%s+%-?%d+%.?%d*%%?$", "")
        text = text:gsub("%s+%-?%d+%.?%d*%%?$", "")
        local trailing = {
            "left", "right", "up", "down", "higher", "lower", "bigger",
            "smaller", "larger", "wider", "narrower", "taller", "shorter",
            "more", "less", "increase", "decrease", "on", "off", "enabled",
            "disabled", "true", "false", "yes", "no",
        }
        for i = 1, #trailing do text = text:gsub("%s+" .. trailing[i] .. "$", "") end
        text = text:gsub("%s+unit%s+frames?$", "")
        text = text:gsub("%s+frames?$", "")
        text = text:gsub("%s+options?$", "")
        text = text:gsub("%s+choices?$", "")
        text = text:gsub("%s+values?$", "")
        text = text:gsub("%s+range$", "")
        text = text:gsub("%s+have$", "")
        text = text:gsub("%s+be$", "")
        text = text:gsub("^the%s+", "")
        return CommandTextNorm(text)
    end

    local function CommandColorSubject(subject)
        subject = CommandTextNorm(subject)
        if subject == "" then return subject end
        subject = subject:gsub("#%x%x%x%x%x%x", "")
        subject = subject:gsub("%d+%s*,%s*%d+%s*,%s*%d+", "")
        for name in pairs(DASHBOARD_FALLBACK_COLORS) do
            subject = (" " .. subject .. " "):gsub("%s+" .. name .. "%s+", " ")
        end
        for alias in pairs(DASHBOARD_COLOR_ALIASES) do
            subject = (" " .. subject .. " "):gsub("%s+" .. alias .. "%s+", " ")
        end
        return CommandTextNorm(subject)
    end

    local function CommandAddNaturalIntentQueries(queries, seen, normalized)
        local subject = CommandCleanSubject(normalized)
        if subject == "" then return end

        if DashboardContainsAny(normalized, { "hide ", "show ", "enable ", "disable ", "turn on ", "turn off " }) then
            CommandAddQuery(queries, seen, subject)
            CommandAddQuery(queries, seen, subject .. " enabled")
            CommandAddQuery(queries, seen, subject .. " visibility")
            CommandAddQuery(queries, seen, subject .. " visible")
            CommandAddQuery(queries, seen, "show " .. subject)
            CommandAddQuery(queries, seen, "enable " .. subject)
        end

        if CommandContainsAnyWord(normalized, { "left", "right" }) then
            CommandAddQuery(queries, seen, subject .. " x offset")
            CommandAddQuery(queries, seen, subject .. " horizontal offset")
            CommandAddQuery(queries, seen, subject .. " position x")
        end
        if CommandContainsAnyWord(normalized, { "up", "down" }) then
            CommandAddQuery(queries, seen, subject .. " y offset")
            CommandAddQuery(queries, seen, subject .. " vertical offset")
            CommandAddQuery(queries, seen, subject .. " position y")
        end
        if DashboardContainsAny(normalized, { "wider", "narrower" }) then
            CommandAddQuery(queries, seen, subject .. " width")
            CommandAddQuery(queries, seen, subject .. " frame width")
        end
        if DashboardContainsAny(normalized, { "taller", "shorter" }) then
            CommandAddQuery(queries, seen, subject .. " height")
            CommandAddQuery(queries, seen, subject .. " frame height")
        end
        if DashboardContainsAny(normalized, { "bigger", "smaller", "larger", "resize" }) then
            CommandAddQuery(queries, seen, subject .. " width")
            CommandAddQuery(queries, seen, subject .. " height")
            CommandAddQuery(queries, seen, subject .. " scale")
            CommandAddQuery(queries, seen, subject .. " size")
            CommandAddQuery(queries, seen, subject .. " icon size")
            CommandAddQuery(queries, seen, subject .. " text size")
        end
        if DashboardContainsAny(normalized, { "size", "scale", "font size", "text size", "icon size" }) then
            CommandAddQuery(queries, seen, subject .. " size")
            CommandAddQuery(queries, seen, subject .. " scale")
            CommandAddQuery(queries, seen, subject .. " text size")
            CommandAddQuery(queries, seen, subject .. " font size")
            CommandAddQuery(queries, seen, subject .. " icon size")
        end
        if DashboardContainsAny(normalized, { "opacity", "transparent", "transparency", "alpha", "fade", "faded" }) then
            CommandAddQuery(queries, seen, subject .. " alpha")
            CommandAddQuery(queries, seen, subject .. " opacity")
            CommandAddQuery(queries, seen, subject .. " fade")
            CommandAddQuery(queries, seen, subject .. " in combat alpha")
            CommandAddQuery(queries, seen, subject .. " out of combat alpha")
        end
        if DashboardContainsAny(normalized, { "thicker", "thinner", "thickness", "border size", "outline size" }) then
            CommandAddQuery(queries, seen, subject .. " border size")
            CommandAddQuery(queries, seen, subject .. " outline size")
            CommandAddQuery(queries, seen, subject .. " thickness")
        end
        if DashboardContainsAny(normalized, { "spacing", "space", "gap", "padding" }) then
            CommandAddQuery(queries, seen, subject .. " spacing")
            CommandAddQuery(queries, seen, subject .. " gap")
            CommandAddQuery(queries, seen, subject .. " padding")
        end

        if DashboardExtractCommandColor(normalized) then
            local colorSubject = CommandColorSubject(subject)
            if colorSubject ~= "" then
                CommandAddQuery(queries, seen, colorSubject .. " color")
                CommandAddQuery(queries, seen, colorSubject .. " colour")
                CommandAddQuery(queries, seen, colorSubject .. " text color")
                CommandAddQuery(queries, seen, colorSubject .. " bar color")
                CommandAddQuery(queries, seen, colorSubject .. " border color")
            end
        end
    end

    local function CommandAddAliasQueries(queries, seen, text)
        local base = CommandTextNorm(text)
        if base == "" then return end
        local aliases = {
            { "hp", "health" },
            { "hp bar", "health bar" },
            { "healthbar", "health bar" },
            { "mp", "power" },
            { "mana", "power" },
            { "powerbar", "power bar" },
            { "cast", "castbar" },
            { "casts", "castbars" },
            { "cast bar", "castbar" },
            { "tot", "target of target" },
            { "targettarget", "target of target" },
            { "focus target", "focus target" },
            { "focustarget", "focus target" },
            { "party frames", "group frames" },
            { "party frame", "group frame" },
            { "raid frames", "group frames" },
            { "raid frame", "group frame" },
            { "mythic raid", "mythicraid" },
            { "boss frames", "boss frame" },
        }

        for i = 1, #aliases do
            local from, to = aliases[i][1], aliases[i][2]
            local pattern = "%s+" .. from:gsub("%s+", "%%s+") .. "%s+"
            local padded = " " .. base .. " "
            local replaced = padded:gsub(pattern, " " .. to .. " ")
            if replaced ~= padded then CommandAddQuery(queries, seen, replaced) end
        end
    end

    local function CommandSearchQueries(raw, normalized)
        local queries, seen = {}, {}
        local stripped = normalized or CommandTextNorm(raw)
        CommandAddNaturalIntentQueries(queries, seen, stripped)
        CommandAddAliasQueries(queries, seen, stripped)
        stripped = stripped:gsub("^turn%s+(.+)%s+on$", "%1")
        stripped = stripped:gsub("^turn%s+(.+)%s+off$", "%1")
        stripped = stripped:gsub("^msuf%s+", "")
        stripped = stripped:gsub("^please%s+", "")
        stripped = stripped:gsub("^can you%s+", "")
        stripped = stripped:gsub("^could you%s+", "")
        stripped = stripped:gsub("^i want%s+", "")
        stripped = stripped:gsub("^i need%s+", "")
        stripped = stripped:gsub("^turn%s+on%s+", "")
        stripped = stripped:gsub("^turn%s+off%s+", "")
        stripped = stripped:gsub("^set%s+", "")
        stripped = stripped:gsub("^change%s+", "")
        stripped = stripped:gsub("^adjust%s+", "")
        stripped = stripped:gsub("^put%s+", "")
        stripped = stripped:gsub("^switch%s+", "")
        stripped = stripped:gsub("^swap%s+", "")
        stripped = stripped:gsub("^pick%s+", "")
        stripped = stripped:gsub("^make%s+", "")
        stripped = stripped:gsub("^enable%s+", "")
        stripped = stripped:gsub("^disable%s+", "")
        stripped = stripped:gsub("^show%s+me%s+", "")
        stripped = stripped:gsub("^show%s+", "")
        stripped = stripped:gsub("^hide%s+", "")
        stripped = stripped:gsub("^use%s+", "")
        stripped = stripped:gsub("^select%s+", "")
        stripped = stripped:gsub("^choose%s+", "")
        stripped = stripped:gsub("^open%s+", "")
        stripped = stripped:gsub("^go%s+to%s+", "")
        stripped = stripped:gsub("^find%s+", "")
        stripped = stripped:gsub("^search%s+for%s+", "")
        stripped = stripped:gsub("^start%s+", "")
        stripped = stripped:gsub("^stop%s+", "")
        stripped = stripped:gsub("^move%s+", "")
        stripped = stripped:gsub("^resize%s+", "")
        stripped = stripped:gsub("^increase%s+", "")
        stripped = stripped:gsub("^decrease%s+", "")
        stripped = stripped:gsub("^raise%s+", "")
        stripped = stripped:gsub("^lower%s+", "")
        stripped = stripped:gsub("^reset%s+", "")
        stripped = stripped:gsub("^restore%s+", "")
        stripped = stripped:gsub("^apply%s+", "")
        stripped = stripped:gsub("^copy%s+", "")
        stripped = stripped:gsub("^export%s+", "")
        stripped = stripped:gsub("^import%s+", "")
        stripped = stripped:gsub("^browse%s+", "")
        stripped = stripped:gsub("^preview%s+", "")
        stripped = stripped:gsub("^press%s+", "")
        stripped = stripped:gsub("^click%s+", "")
        stripped = stripped:gsub("^run%s+", "")
        stripped = stripped:gsub("^execute%s+", "")
        stripped = stripped:gsub("^do%s+", "")
        stripped = stripped:gsub("^add%s+", "")
        stripped = stripped:gsub("^remove%s+", "")
        stripped = stripped:gsub("^help%s+with%s+", "")
        stripped = stripped:gsub("^explain%s+", "")
        stripped = stripped:gsub("^tell%s+me%s+about%s+", "")
        stripped = stripped:gsub("^tell%s+me%s+", "")
        stripped = stripped:gsub("^all%s+of%s+", "")
        stripped = stripped:gsub("^all%s+", "")
        stripped = stripped:gsub("^every%s+", "")
        stripped = stripped:gsub("^each%s+", "")
        stripped = stripped:gsub("^the%s+", "")
        stripped = stripped:gsub("^what%s+options%s+does%s+", "")
        stripped = stripped:gsub("^what%s+choices%s+does%s+", "")
        stripped = stripped:gsub("^what%s+values%s+can%s+", "")
        stripped = stripped:gsub("^what%s+values%s+does%s+", "")
        stripped = stripped:gsub("^which%s+options%s+for%s+", "")
        stripped = stripped:gsub("^which%s+choices%s+for%s+", "")
        stripped = stripped:gsub("^which%s+values%s+for%s+", "")
        stripped = stripped:gsub("^which%s+", "")
        stripped = stripped:gsub("^can%s+i%s+set%s+", "")
        stripped = stripped:gsub("^what%s+is%s+", "")
        stripped = stripped:gsub("^what%s+are%s+", "")
        stripped = stripped:gsub("^what's%s+", "")
        stripped = stripped:gsub("^show%s+current%s+", "")
        stripped = stripped:gsub("^current%s+", "")
        stripped = stripped:gsub("^status%s+of%s+", "")
        stripped = stripped:gsub("^is%s+", "")
        stripped = stripped:gsub("%s+from%s+.+$", "")
        stripped = stripped:gsub("%s+equal%s+to%s+.+$", "")
        stripped = stripped:gsub("%s+equals%s+.+$", "")
        stripped = stripped:gsub("%s+to%s+.+$", "")
        stripped = stripped:gsub("%s+as%s+.+$", "")
        stripped = stripped:gsub("%s+into%s+.+$", "")
        stripped = stripped:gsub("%s+called%s+.+$", "")
        stripped = stripped:gsub("%s+named%s+.+$", "")
        stripped = stripped:gsub("%s+to%s+defaults?$", "")
        stripped = stripped:gsub("%s+back%s+to%s+defaults?$", "")
        stripped = stripped:gsub("%s+options?$", "")
        stripped = stripped:gsub("%s+choices?$", "")
        stripped = stripped:gsub("%s+values?$", "")
        stripped = stripped:gsub("%s+range$", "")
        stripped = stripped:gsub("%s+have$", "")
        stripped = stripped:gsub("%s+be$", "")
        stripped = stripped:gsub("%s*=%s*.+$", "")
        stripped = stripped:gsub("%s+by%s+%-?%d+%.?%d*%%?$", "")
        stripped = stripped:gsub("%s+%-?%d+%.?%d*%%?$", "")
        local trailingValues = { "on", "off", "true", "false" }
        for i = 1, #trailingValues do
            stripped = stripped:gsub("%s+" .. trailingValues[i] .. "$", "")
        end
        local trailingRelative = { "up", "down", "left", "right", "higher", "lower", "bigger", "smaller", "larger", "wider", "narrower", "taller", "shorter", "more", "less", "increase", "decrease" }
        for i = 1, #trailingRelative do
            stripped = stripped:gsub("%s+" .. trailingRelative[i] .. "$", "")
        end
        CommandAddAliasQueries(queries, seen, stripped)
        CommandAddQuery(queries, seen, stripped)
        CommandAddQuery(queries, seen, raw)
        CommandAddQuery(queries, seen, normalized)
        return queries
    end

    local function CommandWantsSettingChange(normalized)
        if DashboardLooksLikeQuestion("", normalized) then return false end
        if DashboardContainsAny(normalized, {
            "set ", "change ", "adjust ", "make ", "enable ", "disable ",
            "turn on ", "turn off ", "show ", "hide ", "use ", "select ",
            "choose ", "put ", "switch ", "swap ", "pick ", "increase", "decrease", "bigger", "smaller", "larger",
            "higher", "lower", "more ", "less ", "start ", "stop ", "toggle ",
            "reset ", "restore ", "apply ", "copy ", "export ", "import ",
            "browse ", "preview ", "press ", "click ", "delete ", "duplicate ",
            "clear ", "empty ", "blank ", "run ", "execute ", "do ", "add ", "remove ",
            "move ", "resize ", "wider", "narrower", "taller", "shorter",
        }) then
            return true
        end
        return normalized:find("^set ") or normalized:find("^change ") or normalized:find("^enable ")
            or normalized:find("^disable ") or normalized:find("^show ") or normalized:find("^hide ")
            or normalized:find("^reset ") or normalized:find("^restore ") or normalized:find("^apply ")
            or normalized:find("^copy ") or normalized:find("^export ") or normalized:find("^import ")
            or normalized:find("^press ") or normalized:find("^click ")
    end

    local function CommandStrongSettingChange(normalized)
        if DashboardContainsAny(normalized, {
            "set ", "change ", "adjust ", "make ", "enable ", "disable ",
            "turn on ", "turn off ", "hide ", "use ", "select ", "choose ",
            "put ", "switch ", "swap ", "pick ",
            "increase", "decrease", "bigger", "smaller", "larger", "higher",
            "lower", "start ", "stop ", "reset ", "restore ", "apply ",
            "copy ", "export ", "import ", "browse ", "preview ", "press ",
            "click ", "delete ", "duplicate ", "clear ", "empty ", "blank ", "toggle ", "move ", "resize ",
            "run ", "execute ", "do ", "add ", "remove ", "wider", "narrower", "taller", "shorter",
        }) then
            return true
        end
        return normalized:find("^set ") or normalized:find("^change ") or normalized:find("^enable ")
            or normalized:find("^disable ") or normalized:find("^hide ")
            or normalized:find("^reset ") or normalized:find("^restore ") or normalized:find("^apply ")
            or normalized:find("^copy ") or normalized:find("^export ") or normalized:find("^import ")
            or normalized:find("^press ") or normalized:find("^click ")
    end

    local function CommandRecordAction(rec)
        local action = type(rec) == "table" and rec.command or nil
        if type(action) ~= "table" or not COMMAND_ACTION_KINDS[action.kind or ""] then return nil end
        if type(action.set) ~= "function" then return nil end
        return action
    end

    local function CommandBuildPage(key)
        if type(key) ~= "string" or key == "" or key == "search" then return false end
        if M.cache and M.cache[key] and M.cache[key].wrapper then return false end
        if type(M.BuildPageEntry) ~= "function" then return false end
        local ok = pcall(M.BuildPageEntry, key, true)
        return ok and true or false
    end

    local function CommandBuildResultPages(results, limit)
        if type(results) ~= "table" then return 0 end
        local built, seen = 0, {}
        limit = tonumber(limit) or 8
        for i = 1, #results do
            local key = results[i] and results[i].key
            if type(key) == "string" and key ~= "" and not seen[key] then
                seen[key] = true
                if CommandBuildPage(key) then built = built + 1 end
                if built >= limit then break end
            end
        end
        return built
    end

    local function CommandBuildAllPages()
        local built = 0
        local order = M.pageOrder or {}
        for i = 1, #order do
            if CommandBuildPage(order[i]) then built = built + 1 end
        end
        return built
    end

    local function FindActionableCommandRecord(raw, normalized, allowBuild)
        local queries = CommandSearchQueries(raw, normalized)
        local firstResults
        local function SearchForAction()
            for q = 1, #queries do
                local results = CommandSearchResults(queries[q])
                if not firstResults and #results > 0 then firstResults = results end
                for i = 1, #results do
                    if CommandRecordAction(results[i]) then
                        return results[i], results, queries[q]
                    end
                end
            end
        end

        local rec, results, usedQuery = SearchForAction()
        if rec or not allowBuild then return rec, results or firstResults, usedQuery end

        local built = CommandBuildResultPages(firstResults, 10)
        if built > 0 then
            rec, results, usedQuery = SearchForAction()
            if rec then return rec, results, usedQuery end
        end

        if CommandBuildAllPages() > 0 then
            rec, results, usedQuery = SearchForAction()
            if rec then return rec, results, usedQuery end
        end

        return nil, results or firstResults, usedQuery
    end

    local function FindActionableCommandRecords(raw, normalized, allowBuild, limit)
        local queries = CommandSearchQueries(raw, normalized)
        local records, seen = {}, {}
        local firstResults
        limit = tonumber(limit) or 24

        local function AddResults(results)
            if type(results) ~= "table" then return end
            if not firstResults and #results > 0 then firstResults = results end
            for i = 1, #results do
                local rec = results[i]
                local action = CommandRecordAction(rec)
                if action then
                    local key = table.concat({
                        tostring(rec.key or ""),
                        tostring(rec.label or ""),
                        tostring(rec.hint or ""),
                        tostring(rec.kind or ""),
                        tostring(action),
                    }, "\031")
                    if not seen[key] then
                        seen[key] = true
                        records[#records + 1] = rec
                        if #records >= limit then return end
                    end
                end
            end
        end

        local function SearchAllQueries()
            for q = 1, #queries do
                AddResults(CommandSearchResults(queries[q]))
                if #records >= limit then return end
            end
        end

        SearchAllQueries()
        if allowBuild and #records < limit then
            CommandBuildResultPages(firstResults, 12)
            CommandBuildAllPages()
            SearchAllQueries()
        end
        return records, firstResults
    end

    local function CommandActionLabel(rec, action)
        if action and type(action.labelFn) == "function" then
            local ok, label = pcall(action.labelFn)
            if ok and label and label ~= "" then return tostring(label) end
        end
        return tostring((rec and rec.label) or (action and action.label) or "MSUF setting")
    end

    local function CommandActionSource(rec, action, label)
        if action and type(action.sourceFn) == "function" then
            local ok, source = pcall(action.sourceFn, label)
            if ok and source and source ~= "" then return tostring(source) end
        end
        return "dashboard:command:" .. tostring((rec and rec.key) or "setting") .. ":" .. tostring(label or "option")
    end

    local function CommandReadValue(action)
        if type(action) ~= "table" or type(action.get) ~= "function" then return nil end
        local ok, a, b, c = pcall(action.get)
        if ok then return a, b, c end
    end

    local function CommandValueText(raw)
        raw = DashboardTrimText(raw)
        local value = raw:match("[Tt][Oo]%s+(.+)$")
            or raw:match("[Aa][Ss]%s+(.+)$")
            or raw:match("[Ii][Nn][Tt][Oo]%s+(.+)$")
            or raw:match("[Ee][Qq][Uu][Aa][Ll]%s+[Tt][Oo]%s+(.+)$")
            or raw:match("[Ee][Qq][Uu][Aa][Ll][Ss]%s+(.+)$")
            or raw:match("[Cc][Aa][Ll][Ll][Ee][Dd]%s+(.+)$")
            or raw:match("[Nn][Aa][Mm][Ee][Dd]%s+(.+)$")
            or raw:match("=%s*(.+)$")
        if value then
            value = DashboardTrimText(value):gsub("^[\"'`]+", ""):gsub("[\"'`]+$", "")
            return value ~= "" and value or nil
        end
        local quoted = raw:match("\"([^\"]+)\"") or raw:match("'([^']+)'") or raw:match("`([^`]+)`")
        if quoted then return quoted end
        return nil
    end

    local function CommandBoolIntent(normalized)
        if DashboardContainsAny(normalized, { "turn off", "disable", "hide", "stop ", " off", " false" })
            or normalized:find("off$") or normalized:find("false$") or normalized:find("disabled$")
            or normalized:find(" no$") or normalized == "no" then
            return false, "off"
        end
        if DashboardContainsAny(normalized, { "turn on", "enable", "show", "start ", " on", " true" })
            or normalized:find("on$") or normalized:find("true$") or normalized:find("enabled$")
            or normalized:find(" yes$") or normalized == "yes" then
            return true, "on"
        end
        return nil
    end

    local function CommandClampSlider(value, action)
        value = tonumber(value)
        if not value then return nil end
        local minValue = tonumber(action.min)
        local maxValue = tonumber(action.max)
        if minValue and value < minValue then value = minValue end
        if maxValue and value > maxValue then value = maxValue end
        local step = tonumber(action.step)
        if step and step > 0 and minValue then
            value = minValue + (floor(((value - minValue) / step) + 0.5) * step)
            if minValue and value < minValue then value = minValue end
            if maxValue and value > maxValue then value = maxValue end
        end
        return value
    end

    local function CommandWordNumber(raw, normalized, action)
        normalized = " " .. CommandTextNorm(normalized or raw) .. " "
        local minValue = tonumber(action and action.min)
        local maxValue = tonumber(action and action.max)
        if normalized:find(" zero ", 1, true) or normalized:find(" none ", 1, true) then
            return CommandClampSlider(0, action)
        end
        if normalized:find(" half ", 1, true) or normalized:find(" halfway ", 1, true) then
            if minValue and maxValue then return CommandClampSlider(minValue + ((maxValue - minValue) / 2), action) end
            if maxValue then return CommandClampSlider(maxValue / 2, action) end
            return CommandClampSlider(0.5, action)
        end
        if normalized:find(" full ", 1, true)
            or normalized:find(" highest ", 1, true)
            or normalized:find(" largest ", 1, true)
            or normalized:find(" maxed ", 1, true)
            or normalized:find(" max out ", 1, true)
        then
            return CommandClampSlider(maxValue, action)
        end
        if normalized:find(" lowest ", 1, true)
            or normalized:find(" smallest ", 1, true)
        then
            return CommandClampSlider(minValue, action)
        end
        return nil
    end

    local function CommandRelativeDirection(normalized)
        if DashboardContainsAny(normalized, {
            "increase", "bigger", "larger", "higher", "raise", "more",
            "wider", "taller",
        }) or CommandContainsAnyWord(normalized, { "right", "up" }) then
            return 1
        end
        if DashboardContainsAny(normalized, {
            "decrease", "smaller", "lower", "less",
            "narrower", "shorter",
        }) or CommandContainsAnyWord(normalized, { "left", "down" }) then
            return -1
        end
        return nil
    end

    local function CommandExtractNumber(raw, normalized, action)
        local minValue = tonumber(action.min)
        local maxValue = tonumber(action.max)
        if normalized:find("minimum", 1, true) or normalized:find(" min", 1, true) then return minValue end
        if normalized:find("maximum", 1, true) or normalized:find(" max", 1, true) then return maxValue end

        local relDir = CommandRelativeDirection(normalized)
        local current = tonumber(CommandReadValue(action)) or 0
        local byValue = tonumber(raw:match("[Bb][Yy]%s+([%-]?%d+%.?%d*)"))
        if byValue and relDir then
            return CommandClampSlider(current + (byValue * relDir), action)
        end

        local value, isPercent, directValue
        local pct = raw:match("([%-]?%d+%.?%d*)%s*%%")
        if pct then
            value = tonumber(pct)
            isPercent = true
        else
            directValue = tonumber(raw:match("[Tt][Oo]%s+([%-]?%d+%.?%d*)"))
                or tonumber(raw:match("=%s*([%-]?%d+%.?%d*)"))
            value = directValue or byValue
            if not value then
                for number in raw:gmatch("[%-]?%d+%.?%d*") do
                    value = tonumber(number)
                end
            end
        end

        if value and relDir and not directValue and not isPercent then
            return CommandClampSlider(current + (value * relDir), action)
        end
        if value and isPercent and maxValue and (maxValue <= 1.0001 or (maxValue <= 5 and value > maxValue)) then
            value = value / 100
        end

        if value then return CommandClampSlider(value, action) end
        local wordValue = CommandWordNumber(raw, normalized, action)
        if wordValue ~= nil then return wordValue end

        local step = tonumber(action.step)
        if not step or step <= 0 then
            local span = (minValue and maxValue) and math.abs(maxValue - minValue) or nil
            step = (span and span > 0) and (span / 20) or 1
        end
        if relDir then return CommandClampSlider(current + (step * relDir), action) end
        return nil
    end

    local function CommandFormatNumber(value)
        value = tonumber(value)
        if not value then return "" end
        if math.abs(value - floor(value + 0.5)) < 0.0001 then return tostring(floor(value + 0.5)) end
        return string.format("%.2f", value)
    end

    local function CommandValues(action)
        local values
        if action and type(action.getValues) == "function" then
            local ok, resolved = pcall(action.getValues)
            if ok then values = resolved end
        end
        if values == nil then values = action and action.values end
        if type(values) == "function" then
            local ok, resolved = pcall(values)
            if ok then values = resolved end
        end
        return type(values) == "table" and values or {}
    end

    local function CommandItemValue(item)
        if type(item) ~= "table" then return item end
        if item.value ~= nil then return item.value end
        if item.id ~= nil then return item.id end
        if item.key ~= nil then return item.key end
        if item.text ~= nil then return item.text end
        if item.label ~= nil then return item.label end
        return nil
    end

    local function CommandItemLabel(item)
        if type(item) ~= "table" then return tostring(item or "") end
        local text = item.text or item.label or item.name or item.title
        if text ~= nil then return tostring(text) end
        local value = CommandItemValue(item)
        return tostring(value or "")
    end

    local function CommandMatchChoice(action, raw, normalized)
        local target = CommandTextNorm(CommandValueText(raw) or "")
        local queryNorm = CommandTextNorm(normalized)
        local bestValue, bestLabel, bestScore
        local values = CommandValues(action)
        for i = 1, #values do
            local item = values[i]
            local value = CommandItemValue(item)
            local label = CommandItemLabel(item)
            local labelNorm = CommandTextNorm(label)
            local valueNorm = CommandTextNorm(value)
            local score = 0
            local function ScoreTerm(term)
                if term == "" or #term < 2 then return end
                if target ~= "" then
                    if target == term then score = max(score, 1000 + #term) end
                    if target:find(term, 1, true) then score = max(score, 760 + #term) end
                    if term:find(target, 1, true) then score = max(score, 680 + #term) end
                end
                if queryNorm:find(term, 1, true) then score = max(score, 420 + #term) end
            end
            ScoreTerm(labelNorm)
            ScoreTerm(valueNorm)
            if score > 0 and (not bestScore or score > bestScore) then
                bestScore, bestValue, bestLabel = score, value, label
            end
        end
        return bestValue, bestLabel
    end

    local function CommandMatchRelativeChoice(action, normalized)
        local norm = " " .. CommandTextNorm(normalized) .. " "
        local mode
        if norm:find(" next ", 1, true) or norm:find(" forward ", 1, true) or norm:find(" advance ", 1, true) then
            mode = "next"
        elseif norm:find(" previous ", 1, true) or norm:find(" prev ", 1, true) or norm:find(" back ", 1, true) then
            mode = "previous"
        elseif norm:find(" first ", 1, true) then
            mode = "first"
        elseif norm:find(" last ", 1, true) then
            mode = "last"
        end
        if not mode then return nil end

        local values = CommandValues(action)
        if #values == 0 then return nil end
        local index = 1
        if mode == "last" then
            index = #values
        elseif mode == "next" or mode == "previous" then
            local current = CommandReadValue(action)
            local currentIndex
            for i = 1, #values do
                if CommandItemValue(values[i]) == current then
                    currentIndex = i
                    break
                end
            end
            currentIndex = currentIndex or 1
            if mode == "next" then
                index = currentIndex + 1
                if index > #values then index = 1 end
            else
                index = currentIndex - 1
                if index < 1 then index = #values end
            end
        end
        local item = values[index]
        return CommandItemValue(item), CommandItemLabel(item)
    end

    local function CommandChoiceSummary(action)
        local values = CommandValues(action)
        local out = {}
        for i = 1, #values do
            local label = CommandItemLabel(values[i])
            if label ~= "" then out[#out + 1] = label end
            if #out >= 5 then break end
        end
        if #out == 0 then return "Add the value to use." end
        return "Use one of: " .. table.concat(out, ", ") .. "."
    end

    local function CommandChoiceOptions(action, limit)
        local values = CommandValues(action)
        local out = {}
        limit = tonumber(limit) or 5
        for i = 1, #values do
            local item = values[i]
            local label = CommandItemLabel(item)
            local value = CommandItemValue(item)
            if label ~= "" and value ~= nil then
                out[#out + 1] = { label = label, value = value }
                if #out >= limit then break end
            end
        end
        return out
    end

    local function CommandChoiceLabelForValue(action, value)
        local values = CommandValues(action)
        for i = 1, #values do
            local item = values[i]
            if CommandItemValue(item) == value then
                local label = CommandItemLabel(item)
                if label ~= "" then return label end
            end
        end
        return tostring(value or "")
    end

    local function CommandCurrentValueText(action)
        if type(action) ~= "table" then return nil end
        local kind = action.kind
        if kind == "toggle" then
            return (CommandReadValue(action) and true or false) and "on" or "off"
        end
        if kind == "slider" then
            return CommandFormatNumber(CommandReadValue(action))
        end
        if kind == "dropdown" or kind == "segment" then
            local value = CommandReadValue(action)
            return CommandChoiceLabelForValue(action, value)
        end
        if kind == "color" then
            local r, g, b = CommandReadValue(action)
            r = floor(DashboardClamp01(r or 1) * 255 + 0.5)
            g = floor(DashboardClamp01(g or 1) * 255 + 0.5)
            b = floor(DashboardClamp01(b or 1) * 255 + 0.5)
            return string.format("#%02X%02X%02X", r, g, b)
        end
        if kind == "textinput" then
            local value = CommandReadValue(action)
            value = tostring(value or "")
            return value ~= "" and value or M.Tr("blank")
        end
        return nil
    end

    local function CommandSuggestionResult(suggestion, query)
        if type(suggestion) ~= "table" then return nil end
        if type(suggestion.execute) == "function" then return suggestion.execute() end
        return CommandResult("error", "Command unavailable", "MSUF could not run that suggestion.")
    end

    local function CommandApplySetting(rec, action, label, value, summaryValue, setter)
        local source = CommandActionSource(rec, action, label)
        local ok = CapturedCommand("Command: " .. label, source, function()
            local result = setter()
            if result == false then return false end
            if type(action.refresh) == "function" then action.refresh() end
            return true
        end)
        if ok == false then
            return CommandResult("error", "Command blocked", "Leave combat, then run this command again.")
        elseif ok == nil then
            return CommandResult("error", "Command failed", "MSUF could not apply that setting.")
        end
        return CommandResult("ok", "Updated " .. label, tostring(label) .. " is now " .. tostring(summaryValue or value) .. ".")
    end

    local function BuildActionCommand(rec, raw, normalized)
        local action = CommandRecordAction(rec)
        if not action then return nil end
        local label = CommandActionLabel(rec, action)
        local kind = action.kind

        if kind == "toggle" then
            local desired, desiredLabel = CommandBoolIntent(normalized)
            if desired == nil then
                desired = not (CommandReadValue(action) and true or false)
                desiredLabel = desired and "on" or "off"
            end
            return {
                label = "Set " .. label,
                ready = true,
                summary = M.Format("Sets %s %s.", label, desiredLabel),
                execute = function()
                    return CommandApplySetting(rec, action, label, desired, desiredLabel, function()
                        action.set(desired)
                    end)
                end,
            }
        end

        if kind == "slider" then
            local value = CommandExtractNumber(raw, normalized, action)
            if value == nil then
                local suggestions = {}
                local current = tonumber(CommandReadValue(action)) or 0
                local step = tonumber(action.step)
                if not step or step <= 0 then
                    local minValue = tonumber(action.min)
                    local maxValue = tonumber(action.max)
                    local span = (minValue and maxValue) and math.abs(maxValue - minValue) or nil
                    step = (span and span > 0) and (span / 20) or 1
                end
                local function AddSliderSuggestion(text, nextValue)
                    nextValue = CommandClampSlider(nextValue, action)
                    if nextValue == nil then return end
                    local display = CommandFormatNumber(nextValue)
                    suggestions[#suggestions + 1] = {
                        text = text .. " -> " .. display,
                        execute = function()
                            return CommandApplySetting(rec, action, label, nextValue, display, function()
                                action.set(nextValue)
                            end)
                        end,
                    }
                end
                AddSliderSuggestion("Decrease", current - step)
                AddSliderSuggestion("Increase", current + step)
                if tonumber(action.min) ~= nil then AddSliderSuggestion("Minimum", tonumber(action.min)) end
                if tonumber(action.max) ~= nil then AddSliderSuggestion("Maximum", tonumber(action.max)) end
                return {
                    label = "Set " .. label,
                    ready = false,
                    summary = "Add a number, or use increase/decrease for this slider.",
                    suggestions = suggestions,
                }
            end
            local display = CommandFormatNumber(value)
            return {
                label = "Set " .. label,
                ready = true,
                summary = M.Format("Sets %s to %s.", label, display),
                execute = function()
                    return CommandApplySetting(rec, action, label, value, display, function()
                        action.set(value)
                    end)
                end,
            }
        end

        if kind == "dropdown" or kind == "segment" then
            local value, valueLabel = CommandMatchChoice(action, raw, normalized)
            if value == nil then
                value, valueLabel = CommandMatchRelativeChoice(action, normalized)
            end
            if value == nil then
                local suggestions = {}
                local options = CommandChoiceOptions(action, 5)
                for i = 1, #options do
                    local option = options[i]
                    suggestions[#suggestions + 1] = {
                        text = option.label,
                        execute = function()
                            return CommandApplySetting(rec, action, label, option.value, option.label, function()
                                action.set(option.value)
                            end)
                        end,
                    }
                end
                return {
                    label = "Set " .. label,
                    ready = false,
                    summary = CommandChoiceSummary(action),
                    suggestions = suggestions,
                }
            end
            return {
                label = "Set " .. label,
                ready = true,
                summary = M.Format("Sets %s to %s.", label, valueLabel or tostring(value)),
                execute = function()
                    return CommandApplySetting(rec, action, label, value, valueLabel or tostring(value), function()
                        action.set(value)
                    end)
                end,
            }
        end

        if kind == "color" then
            local r, g, b, colorLabel = DashboardExtractCommandColor(raw)
            if not r then
                local suggestions = {}
                local colors = { "blue", "gold", "white", "red", "green" }
                for i = 1, #colors do
                    local name = colors[i]
                    local sr, sg, sb, sLabel = DashboardColorFromName(name)
                    if sr then
                        suggestions[#suggestions + 1] = {
                            text = name,
                            execute = function()
                                return CommandApplySetting(rec, action, label, sLabel or name, sLabel or name, function()
                                    action.set(sr, sg, sb)
                                end)
                            end,
                        }
                    end
                end
                return {
                    label = "Set " .. label,
                    ready = false,
                    summary = "Add a color name like blue, gold, turquoise, an RGB value, or a hex value like #38c7f0.",
                    suggestions = suggestions,
                }
            end
            return {
                label = "Set " .. label,
                ready = true,
                summary = M.Format("Sets %s to %s.", label, colorLabel or "the requested color"),
                execute = function()
                    return CommandApplySetting(rec, action, label, colorLabel or "color", colorLabel or "the requested color", function()
                        action.set(r, g, b)
                    end)
                end,
            }
        end

        if kind == "textinput" then
            local value = CommandValueText(raw)
            if value == nil and DashboardContainsAny(normalized, {
                "clear ", "empty ", "blank ", "erase ", "remove text", "delete text",
            }) then
                value = ""
            end
            if not value then
                return {
                    label = "Set " .. label,
                    ready = false,
                    summary = "Add the text after to, as, or =.",
                }
            end
            return {
                label = "Set " .. label,
                ready = true,
                summary = M.Format("Sets %s.", label),
                execute = function()
                    return CommandApplySetting(rec, action, label, value, value == "" and M.Tr("blank") or "updated", function()
                        action.set(value)
                    end)
                end,
            }
        end

        if kind == "button" then
            return {
                label = label,
                ready = true,
                summary = M.Format("Runs %s.", label),
                execute = function()
                    local ok = CapturedCommand("Command: " .. label, CommandActionSource(rec, action, label), function()
                        local result = action.set()
                        if result == false then return false end
                        if type(action.refresh) == "function" then action.refresh() end
                        return true
                    end)
                    if ok == false then
                        return CommandResult("error", "Command unavailable", M.Format("MSUF could not run %s right now.", label))
                    elseif ok == nil then
                        return CommandResult("error", "Command failed", M.Format("MSUF could not run %s.", label))
                    end
                    return CommandResult("ok", label, M.Format("Ran %s.", label))
                end,
            }
        end
    end

    local function CommandBulkRequested(normalized)
        normalized = " " .. CommandTextNorm(normalized) .. " "
        return normalized:find(" all ", 1, true)
            or normalized:find(" every ", 1, true)
            or normalized:find(" each ", 1, true)
            or normalized:find(" everything ", 1, true)
    end

    local function CommandCanBulkAction(rec, action, raw, normalized)
        if not action or action.kind == "button" or action.kind == "textinput" then return false end
        if action.kind == "toggle" then
            return CommandBoolIntent(normalized) ~= nil
                or normalized:find("^toggle%s+") ~= nil
                or normalized:find(" toggle ", 1, true) ~= nil
        end
        if action.kind == "slider" then
            return CommandExtractNumber(raw, normalized, action) ~= nil
        end
        if action.kind == "dropdown" or action.kind == "segment" then
            local value = CommandMatchChoice(action, raw, normalized)
            if value == nil then value = CommandMatchRelativeChoice(action, normalized) end
            return value ~= nil
        end
        if action.kind == "color" then
            local r = DashboardExtractCommandColor(raw)
            return r ~= nil
        end
        return false
    end

    local function BuildBulkDashboardCommand(raw, normalized, allowBuild)
        if not (CommandBulkRequested(normalized) and CommandWantsSettingChange(normalized)) then return nil end
        local subject = CommandCleanSubject(normalized)
        local genericSubjects = {
            settings = true,
            setting = true,
            options = true,
            option = true,
            controls = true,
            control = true,
            menu = true,
            menus = true,
            pages = true,
            page = true,
            msuf = true,
        }
        if subject == "" or genericSubjects[subject] then return nil end
        local records = FindActionableCommandRecords(raw, normalized, allowBuild, 32)
        if type(records) ~= "table" or #records < 2 then return nil end

        local commands, labels = {}, {}
        for i = 1, #records do
            local rec = records[i]
            local action = CommandRecordAction(rec)
            if CommandCanBulkAction(rec, action, raw, normalized) then
                local command = BuildActionCommand(rec, raw, normalized)
                if command and command.ready and type(command.execute) == "function" and not command.readonly then
                    commands[#commands + 1] = command
                    labels[#labels + 1] = command.label or CommandActionLabel(rec, action)
                    if #commands >= 16 then break end
                end
            end
        end
        if #commands < 2 then return nil end

        local preview = {}
        for i = 1, min(#labels, 5) do preview[#preview + 1] = labels[i] end
        local body = M.Format("Applies to %d matching settings", #commands)
        if #preview > 0 then body = body .. ": " .. table.concat(preview, ", ") end
        if #commands > #preview then body = body .. ", ..." end
        body = body .. "."

        return {
            label = M.Format("Run %d Matching Changes", #commands),
            ready = true,
            summary = body,
            execute = function()
                local applied = {}
                for i = 1, #commands do
                    local result = commands[i].execute()
                    if type(result) == "table" and result.kind == "error" then return result end
                    applied[#applied + 1] = commands[i].label or ("Command " .. tostring(i))
                end
                return CommandResult("ok", M.Format("Updated %d Settings", #applied), table.concat(applied, ", "))
            end,
        }
    end

    local function BuildQuestionAnswerCommand(raw, normalized, allowBuild)
        if not (normalized:find("^what%s+is%s+")
            or normalized:find("^what%s+are%s+")
            or normalized:find("^what's%s+")
            or normalized:find("^what%s+can%s+")
            or normalized:find("^which%s+")
            or normalized:find("^can%s+i%s+set%s+")
            or normalized:find("^is ")
            or normalized:find("^current ")
            or normalized:find("^status ")
            or normalized:find("current", 1, true)
            or normalized:find(" options", 1, true)
            or normalized:find(" choices", 1, true)
            or normalized:find(" values", 1, true)
            or normalized:find(" range", 1, true)
            or normalized:find(" minimum", 1, true)
            or normalized:find(" maximum", 1, true))
        then
            return nil
        end
        local rec = FindActionableCommandRecord(raw, normalized, allowBuild)
        local action = CommandRecordAction(rec)
        if not action or action.kind == "button" then return nil end
        local label = CommandActionLabel(rec, action)
        local kind = action.kind
        local wantsChoices = normalized:find("option", 1, true)
            or normalized:find("choice", 1, true)
            or normalized:find("choices", 1, true)
            or normalized:find("values", 1, true)
            or normalized:find("allowed", 1, true)
            or normalized:find("can i set", 1, true)
            or normalized:find("can this be", 1, true)
            or normalized:find("^which%s+")
        local wantsRange = normalized:find("range", 1, true)
            or normalized:find("minimum", 1, true)
            or normalized:find("maximum", 1, true)
            or normalized:find(" min ", 1, true)
            or normalized:find(" max ", 1, true)
            or normalized:find("how high", 1, true)
            or normalized:find("how low", 1, true)

        if wantsChoices or wantsRange then
            local body
            if kind == "dropdown" or kind == "segment" then
                body = CommandChoiceSummary(action)
            elseif kind == "slider" then
                local minValue = tonumber(action.min)
                local maxValue = tonumber(action.max)
                local step = tonumber(action.step)
                if minValue ~= nil and maxValue ~= nil then
                    body = M.Format("%s can be from %s to %s.", label, CommandFormatNumber(minValue), CommandFormatNumber(maxValue))
                    if step and step > 0 then body = body .. " " .. M.Format("Step: %s.", CommandFormatNumber(step)) end
                elseif minValue ~= nil then
                    body = M.Format("%s has a minimum of %s.", label, CommandFormatNumber(minValue))
                elseif maxValue ~= nil then
                    body = M.Format("%s has a maximum of %s.", label, CommandFormatNumber(maxValue))
                else
                    body = M.Format("%s accepts a number.", label)
                end
            elseif kind == "toggle" then
                body = M.Format("%s can be on or off.", label)
            elseif kind == "color" then
                body = M.Format("%s accepts color names, RGB values, or hex colors like #38c7f0.", label)
            elseif kind == "textinput" then
                body = M.Format("%s accepts text.", label)
            end
            if body then
                return {
                    label = label,
                    ready = true,
                    readonly = true,
                    summary = body,
                    open = function()
                        OpenCommandSearchRecord(rec, raw)
                    end,
                    execute = function()
                        return CommandResult("info", label, body)
                    end,
                }
            end
        end

        local valueText = CommandCurrentValueText(action)
        if not valueText then return nil end
        return {
            label = "Current " .. label,
            ready = true,
            readonly = true,
            summary = M.Format("%s is currently %s.", label, valueText),
            open = function()
                OpenCommandSearchRecord(rec, raw)
            end,
            execute = function()
                return CommandResult("info", "Current " .. label, M.Format("%s is currently %s.", label, valueText))
            end,
        }
    end

    local function BuildSearchQuestionAnswerCommand(raw, normalized, allowBuild)
        if not DashboardLooksLikeQuestion(raw, normalized) then return nil end

        local query = normalized
        query = query:gsub("^where%s+do%s+i%s+change%s+", "")
        query = query:gsub("^where%s+can%s+i%s+change%s+", "")
        query = query:gsub("^where%s+is%s+", "")
        query = query:gsub("^where%s+are%s+", "")
        query = query:gsub("^how%s+do%s+i%s+change%s+", "")
        query = query:gsub("^how%s+can%s+i%s+change%s+", "")
        query = query:gsub("^how%s+do%s+i%s+set%s+", "")
        query = query:gsub("^how%s+can%s+i%s+set%s+", "")
        query = query:gsub("^how%s+do%s+i%s+use%s+", "")
        query = query:gsub("^what%s+does%s+", "")
        query = query:gsub("^what%s+is%s+", "")
        query = query:gsub("^what%s+are%s+", "")
        query = query:gsub("^what's%s+", "")
        query = query:gsub("^why%s+is%s+", "")
        query = query:gsub("^why%s+are%s+", "")
        query = query:gsub("^why%s+does%s+", "")
        query = query:gsub("^tell%s+me%s+about%s+", "")
        query = query:gsub("^tell%s+me%s+", "")
        query = query:gsub("^explain%s+", "")
        query = query:gsub("^help%s+with%s+", "")
        query = query:gsub("^can%s+i%s+change%s+", "")
        query = query:gsub("^can%s+i%s+set%s+", "")
        query = query:gsub("^can%s+i%s+use%s+", "")
        query = query:gsub("^does%s+msuf%s+have%s+", "")
        query = query:gsub("^do%s+i%s+have%s+", "")
        query = query:gsub("^are%s+there%s+", "")
        query = query:gsub("%s+do$", "")
        query = query:gsub("%s+mean$", "")
        query = query:gsub("%s+for$", "")
        query = query:gsub("%s+settings?$", "")
        query = query:gsub("%?$", "")
        query = DashboardTrimText(query)
        if query == "" then query = raw end

        local results = CommandSearchResults(query)
        if allowBuild and type(results) == "table" then
            CommandBuildResultPages(results, 12)
            if #results == 0 then CommandBuildAllPages() end
            results = CommandSearchResults(query)
        end
        local rec = results and results[1]
        if not rec then return nil end

        local label = tostring(rec.label or rec.title or query)
        local location = tostring(rec.hint or rec.title or rec.group or "")
        local answer = tostring(rec.answer or "")
        local body
        if answer ~= "" then
            body = answer
        elseif location ~= "" then
            body = M.Format("%s is in %s.", label, location)
        else
            body = M.Format("MSUF found %s.", label)
        end

        return {
            label = label,
            ready = true,
            readonly = true,
            summary = body,
            open = function()
                OpenCommandSearchRecord(rec, query)
            end,
            execute = function()
                return CommandResult("info", label, body)
            end,
        }
    end

    local function BuildGenericDashboardCommand(raw, normalized, allowBuild)
        if not CommandWantsSettingChange(normalized) then return nil end
        local bulk = BuildBulkDashboardCommand(raw, normalized, allowBuild)
        if bulk then return bulk end
        local rec, results = FindActionableCommandRecord(raw, normalized, allowBuild)
        if not rec then
            local top = type(results) == "table" and results[1] or nil
            if top then
                local label = tostring(top.label or top.title or raw)
                return {
                    label = "Open " .. label,
                    ready = true,
                    summary = M.Format("MSUF found %s, but it is not a direct command yet. Opens the best match.", label),
                    execute = function()
                        OpenCommandSearchRecord(top, raw)
                        return CommandResult("ok", "Open " .. label, M.Format("Opened %s.", label))
                    end,
                }
            end
            if allowBuild and CommandStrongSettingChange(normalized) then
                return {
                    label = "No matching command",
                    ready = false,
                    summary = "MSUF could not match that to a setting it can change yet. Try using the exact setting name.",
                }
            end
            return nil
        end
        return BuildActionCommand(rec, raw, normalized)
    end

    local function CommandLeadingVerb(normalized)
        local verbs = {
            "turn on", "turn off", "set", "change", "adjust", "make",
            "enable", "disable", "show", "hide", "move", "resize",
            "increase", "decrease", "raise", "lower", "apply", "copy",
            "export", "import", "open", "reset", "restore", "toggle",
            "clear", "empty", "blank", "run", "execute", "do", "add", "remove",
        }
        for i = 1, #verbs do
            local verb = verbs[i]
            if normalized == verb or normalized:find("^" .. verb .. "%s+") then return verb end
        end
        return nil
    end

    local function BuildDashboardCommand(query, allowBuild, nested)
        local raw = DashboardTrimText(query)
        local normalized = DashboardNormalizeText(raw):gsub("^msuf[%s,:-]+", "")
        if normalized == "" then return nil end

        if not nested and not DashboardLooksLikeQuestion(raw, normalized) then
            local splitText = normalized:gsub("%s+and%s+then%s+", " then ")
            splitText = splitText:gsub("%s+then%s+", "\031")
            splitText = splitText:gsub("%s+and%s+", "\031")
            if splitText:find("\031", 1, true) then
                local parts = {}
                for part in splitText:gmatch("[^\031]+") do
                    part = DashboardTrimText(part)
                    if part ~= "" then parts[#parts + 1] = part end
                end
                if #parts > 1 then
                    local commands, labels = {}, {}
                    local leadingVerb = CommandLeadingVerb(normalized)
                    local failed = false
                    for i = 1, #parts do
                        local command = BuildDashboardCommand(parts[i], allowBuild, true)
                        if (not command) and i > 1 and leadingVerb and not CommandWantsSettingChange(parts[i]) then
                            command = BuildDashboardCommand(leadingVerb .. " " .. parts[i], allowBuild, true)
                        end
                        if not (command and command.ready and type(command.execute) == "function" and not command.readonly) then
                            failed = true
                            break
                        end
                        commands[#commands + 1] = command
                        labels[#labels + 1] = command.label or ("Command " .. tostring(i))
                    end
                    if not failed and #commands > 1 then
                        return {
                            label = M.Format("Run %d Commands", #commands),
                            ready = true,
                            summary = "Runs: " .. table.concat(labels, ", ") .. ".",
                            execute = function()
                                local applied = {}
                                for i = 1, #commands do
                                    local result = commands[i].execute()
                                    if type(result) == "table" and result.kind == "error" then return result end
                                    applied[#applied + 1] = commands[i].label or ("Command " .. tostring(i))
                                end
                                return CommandResult("ok", M.Format("Ran %d Commands", #applied), table.concat(applied, ", "))
                            end,
                        }
                    end
                end
            end
        end

        local valueQuestion = BuildQuestionAnswerCommand(raw, normalized, allowBuild == true)
        if valueQuestion then return valueQuestion end
        if normalized == "commands"
            or normalized == "help commands"
            or normalized:find("what can", 1, true)
            or normalized:find("what do", 1, true)
            or normalized:find("command examples", 1, true)
            or normalized:find("what settings can", 1, true)
        then
            local body = "Try commands like: start edit mode; hide player portrait; move player left by 20; make target wider; change main font color to blue; reset fonts; open aura filters; what is player width; make dark mode and font blue."
            return {
                label = "MSUF Command Help",
                ready = true,
                readonly = true,
                summary = body,
                execute = function()
                    return CommandResult("info", "MSUF Command Help", body)
                end,
            }
        end
        local searchQuestion = BuildSearchQuestionAnswerCommand(raw, normalized, allowBuild == true)
        if searchQuestion then return searchQuestion end
        if DashboardLooksLikeQuestion(raw, normalized) then
            return nil
        end

        if normalized == "undo" or normalized:find("^undo ", 1, false) then
            return {
                label = "Undo",
                ready = true,
                summary = "Reverts the last MSUF menu change.",
                execute = function()
                    local ok = M.Undo and M.Undo()
                    if not ok then return CommandResult("error", "Nothing to undo", "There is no MSUF menu change to undo.") end
                    return CommandResult("ok", "Undo", "The last MSUF menu change was reverted.")
                end,
            }
        end

        if normalized == "redo" or normalized:find("^redo ", 1, false) then
            return {
                label = "Redo",
                ready = true,
                summary = "Reapplies the last undone MSUF menu change.",
                execute = function()
                    local ok = M.Redo and M.Redo()
                    if not ok then return CommandResult("error", "Nothing to redo", "There is no MSUF menu change to redo.") end
                    return CommandResult("ok", "Redo", "The last undone MSUF menu change was reapplied.")
                end,
            }
        end

        local wantsEdit = normalized:find("edit mode", 1, true)
            or normalized:find("move frames", 1, true)
            or normalized:find("drag frames", 1, true)
            or normalized:find("position frames", 1, true)
        if wantsEdit then
            local wantsOff = DashboardContainsAny(normalized, {
                "stop edit mode", "exit edit mode", "disable edit mode", "turn off edit mode", "edit mode off",
            })
            local wantsToggle = normalized:find("toggle edit mode", 1, true)
            local mode = wantsToggle and "toggle" or (wantsOff and "off" or "on")
            local label = mode == "off" and "Stop Edit Mode" or (mode == "toggle" and "Toggle Edit Mode" or "Start Edit Mode")
            return {
                label = label,
                ready = true,
                summary = mode == "off" and "Turns off MSUF Edit Mode." or "Starts MSUF Edit Mode so frames can be moved directly in-game.",
                execute = function()
                    local active = IsDashboardEditModeActive()
                    local wantOn = (mode == "toggle") and not active or mode == "on"
                    if active == wantOn then
                        return CommandResult("ok", label, wantOn and "MSUF Edit Mode is already on." or "MSUF Edit Mode is already off.")
                    end
                    if wantOn and IsDashboardEditModeCombatLocked() then
                        if M.BlockCombatAction then M.BlockCombatAction() end
                        return CommandResult("error", "Command blocked", "Leave combat, then run the edit mode command again.")
                    end
                    ToggleEditMode()
                    return CommandResult("ok", label, wantOn and "MSUF Edit Mode is on. Drag frames to move them." or "MSUF Edit Mode is off.")
                end,
            }
        end

        if (normalized:find("reset", 1, true) or normalized:find("restore", 1, true))
            and DashboardContainsAny(normalized, {
                "reset positions", "reset frame positions", "reset all positions", "reset movers", "reset mover",
                "frame positions", "frames offscreen", "frame offscreen", "off screen", "offscreen",
            })
        then
            return {
                label = "Reset Frame Positions",
                ready = true,
                summary = "Runs the MSUF frame position and visibility reset.",
                execute = function()
                    if not RunMSUFSlashCommand("reset") then
                        return CommandResult("error", "Reset unavailable", "MSUF could not run the position reset command.")
                    end
                    return CommandResult("ok", "Reset Frame Positions", "MSUF frame positions and visibility were reset to defaults.")
                end,
            }
        end

        if normalized:find("fullreset", 1, true)
            or normalized:find("factory reset", 1, true)
            or normalized:find("reset all settings", 1, true)
            or normalized:find("reset all profiles", 1, true)
        then
            return {
                label = "Factory Reset All",
                ready = true,
                summary = "Stages the shared MSUF full factory reset flow.",
                execute = function()
                    if not (M.StageFactoryReset and M.StageFactoryReset()) then
                        return CommandResult("error", "Factory reset unavailable", "MSUF could not run the factory reset command.")
                    end
                    return CommandResult("ok", "Factory Reset All", "Factory reset was staged through the shared MSUF reset flow.")
                end,
            }
        end

        if normalized == "help"
            or normalized:find("print help", 1, true)
            or normalized:find("show help", 1, true)
            or normalized:find("slash commands", 1, true)
        then
            return {
                label = "Print Help",
                ready = true,
                summary = "Prints MSUF slash command help to chat.",
                execute = function()
                    if not RunMSUFSlashCommand("help") then
                        return CommandResult("error", "Help unavailable", "MSUF could not print help right now.")
                    end
                    return CommandResult("ok", "Print Help", "MSUF help was printed to chat.")
                end,
            }
        end

        if normalized:find("discord", 1, true)
            and (DashboardContainsAny(normalized, { "copy", "open", "join", "support", "link" }) or normalized == "discord")
        then
            return {
                label = "Copy Discord Link",
                ready = true,
                summary = "Opens the MSUF Discord invite copy popup.",
                execute = function()
                    if type(_G.MSUF_ShowCopyLink) ~= "function" then
                        return CommandResult("error", "Discord link unavailable", "MSUF could not open the Discord link popup.")
                    end
                    _G.MSUF_ShowCopyLink("Discord", "https://discord.gg/2Gf9b2Wprz")
                    return CommandResult("ok", "Copy Discord Link", "The Discord invite is ready to copy.")
                end,
            }
        end

        local wantsClassMode = normalized:find("class color mode", 1, true)
            or normalized:find("class colour mode", 1, true)
            or normalized:find("class colors", 1, true)
            or normalized:find("class colours", 1, true)
        local wantsDarkMode = normalized:find("dark mode", 1, true)
            or normalized:find("darkmode", 1, true)
            or normalized:find("dark bars", 1, true)
            or (normalized:find("everything", 1, true) and normalized:find("dark", 1, true))
        if wantsDarkMode or wantsClassMode then
            local turnDarkOff = wantsDarkMode and DashboardContainsAny(normalized, {
                "turn off", "disable", "stop", "off",
            })
            local mode = (wantsClassMode or turnDarkOff) and "class" or "dark"
            local label = mode == "dark" and "Apply Dark Mode" or "Apply Class Color Mode"
            return {
                label = label,
                ready = true,
                summary = mode == "dark" and "Sets Global Style > Colors > Bar mode to Dark Mode." or "Sets Global Style > Colors > Bar mode to Class Color Mode.",
                execute = function()
                    local ok = CapturedCommand(label, "dashboard:command:barMode", function()
                        return DashboardSetBarMode(mode)
                    end)
                    if ok == false then
                        return CommandResult("error", "Command blocked", "Leave combat, then run this command again.")
                    end
                    return CommandResult("ok", label, mode == "dark" and "Dark Mode is applied to MSUF bars." or "Class Color Mode is applied to MSUF bars.")
                end,
            }
        end

        local hasFontSubject = normalized:find("font", 1, true)
            or normalized:find("text color", 1, true)
            or normalized:find("text colour", 1, true)
            or normalized:find("main text", 1, true)
        local hasColorIntent = normalized:find("color", 1, true) or normalized:find("colour", 1, true)
        local r, g, b, colorLabel = DashboardExtractCommandColor(raw)
        if hasFontSubject and (hasColorIntent or r) then
            local reset = DashboardContainsAny(normalized, {
                "reset", "default", "palette", "clear custom",
            })
            if reset then
                return {
                    label = "Reset Main Font Color",
                    ready = true,
                    summary = "Returns the main font color to the selected MSUF font palette.",
                    execute = function()
                        local ok = CapturedCommand("Command: Reset Font Color", "dashboard:command:fontColor:reset", function()
                            DashboardResetGlobalFontColor()
                            return true
                        end)
                        if ok == false then return CommandResult("error", "Command blocked", "Leave combat, then run this command again.") end
                        return CommandResult("ok", "Reset Main Font Color", "The main font color now follows the MSUF font palette.")
                    end,
                }
            end
            if not r then
                return {
                    label = "Set Main Font Color",
                    ready = false,
                    summary = "Add a color name like blue, gold, turquoise, or a hex value like #38c7f0.",
                }
            end
            return {
                label = M.Format("Set Main Font %s", colorLabel or "Color"),
                ready = true,
                summary = "Changes the global MSUF font color and refreshes visible frame text.",
                execute = function()
                    local ok = CapturedCommand("Command: Font Color", "dashboard:command:fontColor", function()
                        DashboardSetGlobalFontColor(r, g, b)
                        return true
                    end)
                    if ok == false then return CommandResult("error", "Command blocked", "Leave combat, then run this command again.") end
                    return CommandResult("ok", "Set Main Font Color", M.Format("Main font color changed to %s.", colorLabel or "the requested color"))
                end,
            }
        end

        if normalized:find("profile", 1, true) and DashboardContainsAny(normalized, { "import", "open", "manage", "switch" }) then
            return {
                label = "Open Profiles",
                ready = true,
                summary = "Opens Profiles for import, export, backup, and profile switching.",
                execute = function()
                    Select("profiles")
                    return CommandResult("ok", "Open Profiles", "Profiles is open.")
                end,
            }
        end

        if normalized:find("wago", 1, true) then
            return {
                label = "Open Wago Profiles",
                ready = true,
                summary = "Copies the Wago MSUF profiles link.",
                execute = function()
                    CopyWagoLink()
                    return CommandResult("ok", "Open Wago Profiles", "The Wago MSUF profile link is ready to copy.")
                end,
            }
        end

        if normalized:find("backup", 1, true) and normalized:find("profile", 1, true) then
            return {
                label = "Export Profile Backup",
                ready = true,
                summary = "Exports a full backup string for the active profile.",
                execute = function()
                    ExportBackup()
                    return CommandResult("ok", "Export Profile Backup", "The active profile backup is ready to copy.")
                end,
            }
        end

        local resetPage = BuildPageResetCommand(raw, normalized)
        if resetPage then return resetPage end

        local openSearch = BuildOpenSearchCommand(raw, normalized)
        if openSearch then return openSearch end

        return BuildGenericDashboardCommand(raw, normalized, allowBuild == true)
    end

    local function BuildCommandCenter(parent, cardW, cardH)
        Kicker(parent, "MSUF Command", 22, -24)
        local title = T.Font(parent, "GameFontNormalLarge", M.Tr("Tell MSUF what to do."), T.colors.text)
        title:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, -52)
        title:SetWidth(cardW - 44)
        title:SetJustifyH("LEFT")
        W.Text(parent, "Type a command like start edit mode, make everything dark mode, or change main font color to blue.", 22, -82, cardW - 44, T.colors.muted)

        local compact = cardW < 560
        local inputY = compact and -118 or -116
        local runW = 68
        local inputW = compact and (cardW - 44) or (cardW - 44 - runW - 10)
        local input = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        input:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, inputY)
        input:SetSize(inputW, 30)
        input:SetAutoFocus(false)
        input:SetMaxLetters(120)
        input:SetTextInsets(10, 10, 0, 0)
        input:EnableMouse(true)
        if T.SkinEditBox then T.SkinEditBox(input) end
        if T.CreateSuperellipseLayers then
            local fill, edge = T.CreateSuperellipseLayers(input, "_msuf2DashboardCommand", 2, "BACKGROUND", "BORDER")
            input._msuf2RoundedEditFill = fill
            input._msuf2RoundedEditEdge = edge
            input._msuf2RoundedEditColor = { 0.010, 0.014, 0.028, 0.98 }
            if input._msuf2PaintEditBox then input:_msuf2PaintEditBox(false) end
        end

        local placeholder = input.Instructions
        if not (placeholder and placeholder.SetText and placeholder.SetPoint) then
            placeholder = input:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        elseif placeholder.ClearAllPoints then
            placeholder:ClearAllPoints()
        end
        placeholder:SetPoint("LEFT", input, "LEFT", 10, 0)
        placeholder:SetPoint("RIGHT", input, "RIGHT", -10, 0)
        placeholder:SetJustifyH("LEFT")
        if placeholder.SetWordWrap then placeholder:SetWordWrap(false) end
        T.StyleFontString(placeholder, T.colors.dim, 0)
        placeholder:SetText(M.Tr("Ask MSUF to change a setting or find one"))
        input._msuf2CommandPlaceholder = placeholder

        local run = Button(parent, "Run", compact and 22 or (22 + inputW + 10), compact and (inputY - 36) or inputY, compact and (cardW - 44) or runW, 30, nil, "primary")

        local statusY = compact and (inputY - 72) or (inputY - 48)
        local status = T.Font(parent, "GameFontNormal", "", T.colors.text)
        status:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, statusY)
        status:SetWidth(cardW - 44)
        status:SetJustifyH("LEFT")
        local detail = W.Text(parent, "", 22, statusY - 24, cardW - 44, T.colors.muted)
        if detail.SetWordWrap then detail:SetWordWrap(true) end

        local buttons = {}
        local resultTop = statusY - 58
        local columns = cardW >= 620 and 2 or 1
        local btnGap = 10
        local btnW = columns == 2 and floor((cardW - 44 - btnGap) / 2) or (cardW - 44)
        local buttonCount = compact and 3 or 6
        for i = 1, buttonCount do
            local btn = T.Button(parent, "", btnW, 24)
            local col = (i - 1) % columns
            local row = floor((i - 1) / columns)
            btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 22 + (col * (btnW + btnGap)), resultTop - (row * 32))
            T.CenterButtonLabel(btn)
            btn:Hide()
            buttons[i] = btn
        end

        local function SetStatus(kind, titleText, bodyText)
            local color = T.colors.muted
            if kind == "ok" then color = T.colors.ok
            elseif kind == "error" then color = T.colors.danger
            elseif kind == "action" then color = T.colors.accent
            elseif kind == "search" then color = T.colors.accent2
            end
            status:SetText(M.Tr(titleText or ""))
            if status.SetTextColor then status:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
            detail:SetText(M.Tr(bodyText or ""))
        end

        local function SetButton(index, text, onClick, primary)
            local btn = buttons[index]
            if not btn then return end
            if btn._msuf2Label then btn._msuf2Label:SetText(M.Tr(text or "")) end
            btn._msuf2Primary = primary and true or nil
            btn._msuf2Danger = nil
            btn._msuf2Success = nil
            if btn.SetActive then btn:SetActive(false) end
            btn:SetScript("OnClick", onClick)
            btn:Show()
        end

        local function HideButtons()
            for i = 1, #buttons do buttons[i]:Hide() end
        end

        local function PaintCommandState(query, result)
            HideButtons()
            query = DashboardTrimText(query)
            M.dashboardCommandQuery = query
            if input._msuf2CommandPlaceholder then input._msuf2CommandPlaceholder:SetShown(query == "") end

            if type(result) == "table" then
                SetStatus(result.kind, result.title, result.body)
                return
            end

            if query == "" then
                SetStatus("info", "Type a command", "MSUF runs known commands directly. Unknown requests become search results.")
                local examples = {
                    { "Start edit mode", "start edit mode" },
                    { "Dark mode", "make everything dark mode" },
                    { "Blue font", "change main font color to blue" },
                    { "Hide portraits", "hide player portrait" },
                    { "Bigger width", "increase player width" },
                    { "Find auras", "where do I change auras" },
                }
                for i = 1, #examples do
                    local label, prompt = examples[i][1], examples[i][2]
                    SetButton(i, label, function()
                        input:SetText(prompt)
                        input:ClearFocus()
                        if run and run._msuf2RunDashboardCommand then run:_msuf2RunDashboardCommand() end
                    end, i <= 2)
                end
                return
            end

            local command = BuildDashboardCommand(query, false)
            if command then
                if command.readonly then
                    SetStatus("search", command.label, command.summary)
                    if type(command.open) == "function" then
                        SetButton(1, "Open setting", function()
                            input:ClearFocus()
                            command.open()
                        end, true)
                    end
                    return
                end
                if command.ready then
                    SetStatus("action", command.label, command.summary .. " Press Enter or Run to apply.")
                    SetButton(1, "Run: " .. command.label, function()
                        input:ClearFocus()
                        local applied = command.execute()
                        M.dashboardCommandLastResult = applied
                        PaintCommandState(query, applied)
                    end, true)
                else
                    SetStatus("error", command.label, command.summary)
                    if type(command.suggestions) == "table" then
                        local visible = min(#command.suggestions, #buttons)
                        for i = 1, visible do
                            local suggestion = command.suggestions[i]
                            SetButton(i, suggestion.text or suggestion.label or ("Option " .. i), function()
                                input:ClearFocus()
                                local applied = CommandSuggestionResult(suggestion, query)
                                M.dashboardCommandLastResult = applied
                                PaintCommandState(query, applied)
                            end, i == 1)
                        end
                    end
                end
                return
            end

            local results = CommandSearchResults(query)
            if #results == 0 then
                SetStatus("search", "No direct command yet", "Press Enter to search all MSUF settings, or try a command like start edit mode.")
                SetButton(1, "Search all settings", function()
                    input:ClearFocus()
                    OpenCommandSearchResults(query)
                end, true)
                return
            end

            local top = results[1]
            local normalizedQuery = DashboardNormalizeText(query)
            if top and top.answer and top.answer ~= "" and DashboardLooksLikeQuestion(query, normalizedQuery) then
                SetStatus("search", top.label or "MSUF answer", top.answer)
            else
                SetStatus("search", M.Format("Search results for \"%s\"", query), "Press Enter to open the best match, or click a result.")
            end
            local visible = min(#results, #buttons)
            for i = 1, visible do
                local rec = results[i]
                local prefix = rec.hint ~= "" and rec.hint or rec.group
                local text = prefix ~= "" and (ShortCommandLabel(prefix, 30) .. " > " .. ShortCommandLabel(rec.label, 34)) or ShortCommandLabel(rec.label, 54)
                SetButton(i, text, function()
                    input:ClearFocus()
                    OpenCommandSearchRecord(rec, query)
                end, i == 1)
            end
        end

        function run:_msuf2RunDashboardCommand()
            local query = DashboardTrimText(input:GetText() or "")
            if query == "" then
                PaintCommandState("", nil)
                input:SetFocus()
                return
            end

            local command = BuildDashboardCommand(query, true)
            if command then
                if command.readonly then
                    local result = command.execute and command.execute() or CommandResult("info", command.label, command.summary)
                    M.dashboardCommandLastResult = result
                    PaintCommandState(query, result)
                    return
                end
                if command.ready then
                    local result = command.execute()
                    M.dashboardCommandLastResult = result
                    PaintCommandState(query, result)
                else
                    M.dashboardCommandLastResult = nil
                    PaintCommandState(query, nil)
                end
                return
            end

            local results = CommandSearchResults(query)
            if results[1] then
                OpenCommandSearchRecord(results[1], query)
            else
                OpenCommandSearchResults(query)
            end
        end

        run:SetScript("OnClick", function(self)
            input:ClearFocus()
            self:_msuf2RunDashboardCommand()
        end)
        input:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            run:_msuf2RunDashboardCommand()
        end)
        input:SetScript("OnEscapePressed", function(self)
            self:SetText("")
            self:ClearFocus()
            M.dashboardCommandLastResult = nil
            PaintCommandState("", nil)
        end)
        input:SetScript("OnTextChanged", function(self)
            local query = DashboardTrimText(self:GetText() or "")
            M.dashboardCommandLastResult = nil
            PaintCommandState(query, nil)
        end)
        input:HookScript("OnEditFocusGained", function(self)
            if self.HighlightText then self:HighlightText() end
            if self._msuf2CommandPlaceholder then self._msuf2CommandPlaceholder:SetShown(DashboardTrimText(self:GetText() or "") == "") end
        end)
        input:HookScript("OnEditFocusLost", function(self)
            if self.HighlightText then self:HighlightText(0, 0) end
            if self._msuf2CommandPlaceholder then self._msuf2CommandPlaceholder:SetShown(DashboardTrimText(self:GetText() or "") == "") end
        end)

        input:SetText(M.dashboardCommandQuery or "")
        PaintCommandState(input:GetText() or "", M.dashboardCommandLastResult)
        return input
    end

    M.dashboardEditModeButton = nil

    local compactHeader = layoutW < 640
    local tinyHeader = layoutW < 430
    local headerH = tinyHeader and 128 or (compactHeader and 104 or 86)
    local header = Card(root, "Dashboard", x0, y0, layoutW, headerH, { 0.030, 0.036, 0.058, 0.94 }, { 0.100, 0.140, 0.220, 0.82 })

    local editW = 150
    local taskW = 96
    local headerTextW = compactHeader and (layoutW - 32) or max(180, layoutW - editW - taskW - 76)
    W.Text(header, "Ask MSUF, review setup, and open recovery tools when needed.", 16, -42, headerTextW, T.colors.muted)

    if tinyHeader then
        local available = max(160, layoutW - 32)
        local smallTaskW = min(taskW, floor((available - 10) * 0.40))
        local smallEditW = min(editW, available - smallTaskW - 10)
        Button(header, "New Task", 16, -82, smallTaskW, 26, StartNewAssistantTask)
        M.dashboardEditModeButton = Button(header, "MSUF Edit Mode", 16 + smallTaskW + 10, -82, smallEditW, 26, ToggleEditMode, "primary")
    else
        local actionY = compactHeader and -66 or -26
        local actionX = layoutW - editW - 16
        M.dashboardEditModeButton = Button(header, "MSUF Edit Mode", actionX, actionY, editW, 28, ToggleEditMode, "primary")
        Button(header, "New Task", actionX - taskW - 12, actionY, taskW, 28, StartNewAssistantTask)
    end
    RefreshDashboardEditModeButtonSafe()
    if type(M.AddRefresher) == "function" then
        M.AddRefresher(ctx, RefreshDashboardEditModeButtonSafe)
    end

    local mainTop = y0 - headerH - 16
    local tinyHero = mainW < 390
    local heroH = tinyHero and 398 or (mainW < 560 and 382 or 360)
    local hero = Card(root, "", x0, mainTop, mainW, heroH, { 0.024, 0.050, 0.090, 0.90 }, { 0.085, 0.230, 0.340, 0.70 })
    ApplyDashboardHeroGradient(hero, mainW, heroH)
    if MSUF and MSUF.Assistant and type(MSUF.Assistant.BuildDashboardCard) == "function" then
        MSUF.Assistant.BuildDashboardCard(hero, mainW, heroH)
    else
        BuildCommandCenter(hero, mainW, heroH)
    end

    local featureBlockBottom = mainTop - heroH
    local sideTop = sideBySide and mainTop or (featureBlockBottom - 16)
    local checklistTop = sideTop
    local checklistH = 236
    local checklist = Card(root, "Setup checklist", sideX, checklistTop, sideW, checklistH)
    W.Text(checklist, "Useful for first-run orientation.", 16, -38, sideW - 32, T.colors.muted)
    local function Row(i, title, body, state, color, onClick, iconText)
        local row = Card(checklist, "", 16, -60 - ((i - 1) * 42), sideW - 32, 36, { 0.080, 0.095, 0.170, 0.72 }, T.colors.borderSoft)
        Pill(row, iconText or (i < 3 and "OK" or "!"), 10, -14, 28, color or T.colors.ok)
        local label = T.Font(row, "GameFontNormal", M.Tr(title), T.colors.text)
        label:SetPoint("TOPLEFT", row, "TOPLEFT", 48, -6)
        W.Text(row, body, 48, -22, sideW - 132, T.colors.muted)
        Pill(row, state, sideW - 86, -9, 54, color or T.colors.ok)
        MakeDashboardActionCard(row, title, body, onClick, false)
    end
    local movedFrames = HasMovedFramesInEditMode()
    Row(1, "Profile ready", "Active profile is loaded.", "done", T.colors.ok, function() Select("profiles") end)
    Row(2, "Pages available", "Use pages to tune frames.", "done", T.colors.ok, function() Select("uf_player") end)
    Row(3, "Move frames", "Recommended before detail tuning.", movedFrames and "done" or "start", movedFrames and T.colors.ok or T.colors.accent2, ToggleEditMode, movedFrames and "OK" or "!")
    local wagoBackupConfirmed = WagoBackupConfirmed()
    Row(4, "Wago backup", "Confirm backup before using the Wago MSUF page.", wagoBackupConfirmed and "done" or "start", wagoBackupConfirmed and T.colors.ok or T.colors.accent2, ConfirmWagoBackup, wagoBackupConfirmed and "OK" or "!")

    local function DashboardDisclosure(parent, title, open, stateKey, width, fillPills)
        local head = CreateFrame("Button", nil, parent)
        head:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        head:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
        head:SetHeight(42)
        local hover = head:CreateTexture(nil, "BACKGROUND")
        hover:SetAllPoints()
        hover:SetColorTexture(0, 0, 0, 0)
        local arrow = head:CreateTexture(nil, "OVERLAY")
        arrow:SetTexture(T.media.collapseArrow)
        arrow:SetSize(10, 10)
        arrow:SetPoint("LEFT", head, "LEFT", 16, 0)
        if T.ApplyCollapseVisual then T.ApplyCollapseVisual(arrow, nil, open) end
        local label = T.Font(head, "GameFontNormal", M.Tr(title), T.colors.text)
        label:SetPoint("LEFT", arrow, "RIGHT", 8, 0)
        if type(fillPills) == "function" then fillPills(head, width) end
        head:SetScript("OnClick", function()
            M.PersistMenuStateValue(stateKey, not open)
            M.InvalidatePage("home")
            M.SelectPage("home")
        end)
        head:SetScript("OnEnter", function()
            if hover.SetColorTexture then hover:SetColorTexture(1, 1, 1, 0.025) end
        end)
        head:SetScript("OnLeave", function()
            if hover.SetColorTexture then hover:SetColorTexture(0, 0, 0, 0) end
        end)
        return head
    end

    local sideBottom = checklistTop - checklistH
    local recoveryTop = sideBySide and (featureBlockBottom - 16) or (sideBottom - 16)
    local recoveryW = sideBySide and mainW or layoutW
    local recoveryOpen = M.dashboardRecoveryOpen == true
    local recoveryWrap = recoveryW < 620
    local recoveryNarrow = recoveryW < 520
    local recoveryH = recoveryOpen and (recoveryNarrow and 184 or (recoveryWrap and 154 or 122)) or 42
    local recovery = Card(root, "", x0, recoveryTop, recoveryW, recoveryH, { 0.030, 0.040, 0.078, 0.86 }, T.colors.borderSoft)
    local g = M.GetGeneralDB and M.GetGeneralDB() or {}
    DashboardDisclosure(recovery, "Display & recovery", recoveryOpen, "dashboardRecoveryOpen", recoveryW, function(head)
        if recoveryW >= 520 then Pill(head, "Factory reset hidden", recoveryW - 124, -11, 110, T.colors.accent2) end
    end)

    if recoveryOpen then
        W.Text(recovery, "Reset tools, Wago access, and recovery shortcuts live here.", 16, -60, recoveryW - 32, T.colors.muted)
        local resetPositions = Button(recovery, "Reset Positions", 16, -94, 118, 22, function()
            if not RunMSUFSlashCommand("reset") and M.ShowStatusFeedback then
                M.ShowStatusFeedback("Reset unavailable", "danger", 1.4)
            end
        end, "primary")
        AddTooltip(resetPositions, "Reset Positions", "Runs /msuf reset for frame positions and visibility.")

        local wagoX, helpX, discordX = 146, 270, 368
        local helpY, factoryY = -94, (recoveryWrap and -126 or -94)
        if recoveryNarrow then
            helpX, helpY, discordX, factoryY = 16, -126, 114, -158
        end
        Button(recovery, "Wago Profiles", wagoX, -94, 112, 22, CopyWagoLink)
        Button(recovery, "Print Help", helpX, helpY, 86, 22, function()
            if _G.SlashCmdList and type(_G.SlashCmdList["MIDNIGHTSUF"]) == "function" then pcall(_G.SlashCmdList["MIDNIGHTSUF"], "help") end
        end)
        Button(recovery, "Discord", discordX, helpY, 80, 22, function()
            if type(_G.MSUF_ShowCopyLink) == "function" then _G.MSUF_ShowCopyLink("Discord", "https://discord.gg/2Gf9b2Wprz") end
        end)
        Button(recovery, "Factory Reset All", recoveryWrap and 16 or (recoveryW - 152), factoryY, 136, 22, function()
            if M.StageFactoryReset then M.StageFactoryReset() end
        end, "danger")
        if recoveryWrap then
            local textX = recoveryNarrow and 160 or 160
            local textY = recoveryNarrow and -160 or -128
            W.Text(recovery, "Factory reset affects every MSUF setting.", textX, textY, recoveryW - textX - 16, T.colors.muted)
        end
    end

    local scalingTop = recoveryTop - recoveryH - 10
    local scalingOpen = M.dashboardScalingOpen == true
    local scalingColumns = (recoveryW >= 960) and 3 or ((recoveryW >= 680) and 2 or 1)
    local scalingH = scalingOpen and ((scalingColumns == 3) and 250 or ((scalingColumns == 2) and 382 or 548)) or 42
    local scaling = Card(root, "", x0, scalingTop, recoveryW, scalingH, { 0.030, 0.040, 0.078, 0.86 }, T.colors.borderSoft)
    DashboardDisclosure(scaling, "Scaling", scalingOpen, "dashboardScalingOpen", recoveryW, function(scaleHead)
        if recoveryW < 520 then return end
        local _, ui = GlobalState()
        local uiValue = ui.Enabled and M.Format("%d%%", Percent(ui.Scale, 1)) or M.Tr("Off")
        Pill(scaleHead, M.Format("UI %s", uiValue), recoveryW - 250, -11, 64)
        Pill(scaleHead, M.Format("Menu %d%%", Percent(g.slashMenuScale, 1)), recoveryW - 180, -11, 76)
        Pill(scaleHead, M.Format("Frames %d%%", Percent(g.msufUiScale, 1)), recoveryW - 98, -11, 84)
    end)

    if scalingOpen then
        W.Text(scaling, "Use sliders for exact scale changes. Apply commits the selected value; Revert returns to the active value.", 16, -60, recoveryW - 32, T.colors.muted)

        local pendingGlobalEnabled, pendingGlobalScale, pendingMsufScale, pendingMenuScale
        local colGap = 24
        local colW = (scalingColumns == 3) and math.floor((recoveryW - 32 - (colGap * 2)) / 3)
            or ((scalingColumns == 2) and math.floor((recoveryW - 32 - colGap) / 2) or (recoveryW - 32))
        local globalX, globalTop = 16, -94
        local msufX = (scalingColumns == 3) and (16 + colW + colGap) or ((scalingColumns == 2) and (16 + colW + colGap) or 16)
        local msufTop = (scalingColumns == 3 or scalingColumns == 2) and -94 or -242
        local menuX = (scalingColumns == 3) and (16 + ((colW + colGap) * 2)) or 16
        local menuTop = (scalingColumns == 3) and -94 or ((scalingColumns == 2) and -242 or -390)

        local function AppliedGlobalScale()
            local _, ui = GlobalState()
            return ui.Enabled, Clamp(ui.Scale, 0.3, 1.5)
        end
        local function SelectedGlobalScale()
            local enabled, appliedScale = AppliedGlobalScale()
            local selectedEnabled = (pendingGlobalEnabled ~= nil) and pendingGlobalEnabled or enabled
            local selectedScale = Clamp(pendingGlobalScale or appliedScale, 0.3, 1.5)
            return selectedEnabled, selectedScale, enabled, appliedScale
        end

        local function AppliedMsufScale()
            local dbScale = M.GetGeneralDB()
            return Clamp(tonumber(dbScale.msufUiScale) or 1, 0.25, 1.5)
        end
        local function PendingMsufScale()
            return Clamp(pendingMsufScale or AppliedMsufScale(), 0.25, 1.5)
        end
        local function AppliedMenuScale()
            local dbScale = M.GetGeneralDB()
            return Clamp(tonumber(dbScale.slashMenuScale) or 1, 0.25, 1.5)
        end
        local function PendingMenuScale()
            return Clamp(pendingMenuScale or AppliedMenuScale(), 0.25, 1.5)
        end

        local function BuildSimpleScaleColumn(opts)
            W.Text(scaling, opts.help, opts.x, opts.top - 20, colW, T.colors.muted)
            local status = W.Text(scaling, "", opts.x, opts.top - 40, colW, T.colors.muted)
            local slider = W.Slider(scaling, opts.label, opts.minPct, opts.maxPct, opts.stepPct, colW)
            HideSliderValueBox(slider)
            slider:ClearAllPoints()
            slider:SetPoint("TOPLEFT", scaling, "TOPLEFT", opts.x, opts.top - 64)
            if slider._msuf2SetLayoutWidth then slider:_msuf2SetLayoutWidth(colW) end
            if slider._msuf2Title then
                slider._msuf2Title:ClearAllPoints()
                slider._msuf2Title:SetPoint("TOPLEFT", scaling, "TOPLEFT", opts.x, opts.top)
                slider._msuf2Title:SetWidth(colW)
            end
            EnablePercentWheel(slider, opts.minPct, opts.maxPct, opts.stepPct)

            local apply, revert
            local function Refresh()
                local applied = opts.applied()
                local pending = opts.pending()
                local changed = math.abs(applied - pending) > 0.001
                status:SetText(M.Format(M.Tr("Applied: %d%%  Selected: %d%%"), Percent(applied, 1), Percent(pending, 1)))
                SetSliderValueSafe(slider, SnapPct(pending * 100, opts.minPct, opts.maxPct, opts.stepPct))
                if apply then
                    if changed then apply:Enable() else apply:Disable() end
                    if apply.SetActive then apply:SetActive(changed) end
                end
                if revert then
                    if changed then revert:Enable() else revert:Disable() end
                end
            end
            slider:HookScript("OnValueChanged", function(self, value)
                if self._msuf2Refreshing then return end
                local pct = SnapPct(value, opts.minPct, opts.maxPct, opts.stepPct)
                if pct ~= value then SetSliderValueSafe(self, pct) end
                opts.set(Clamp(pct / 100, opts.minPct / 100, opts.maxPct / 100))
                Refresh()
            end)
            apply = Button(scaling, "Apply", opts.x, opts.top - 100, 72, 20, function()
                opts.apply(opts.pending())
                Refresh()
            end, "primary")
            revert = Button(scaling, "Revert", opts.x + 82, opts.top - 100, 72, 20, function()
                opts.clear()
                Refresh()
            end)
            return Refresh
        end

        W.Text(scaling, "Changes the global WoW UI scale through MSUF presets.", globalX, globalTop - 20, colW, T.colors.muted)
        local globalStatus = W.Text(scaling, "", globalX, globalTop - 40, colW, T.colors.muted)
        local globalScale = W.Slider(scaling, "Global UI Scale", 30, 150, 1, colW)
        HideSliderValueBox(globalScale)
        globalScale:ClearAllPoints()
        globalScale:SetPoint("TOPLEFT", scaling, "TOPLEFT", globalX, globalTop - 64)
        if globalScale._msuf2SetLayoutWidth then globalScale:_msuf2SetLayoutWidth(colW) end
        if globalScale._msuf2Title then
            globalScale._msuf2Title:ClearAllPoints()
            globalScale._msuf2Title:SetPoint("TOPLEFT", scaling, "TOPLEFT", globalX, globalTop)
            globalScale._msuf2Title:SetWidth(colW)
        end
        EnablePercentWheel(globalScale, 30, 150, 1)

        local globalApply, globalRevert
        local function RefreshGlobalScale()
            local selectedEnabled, selectedScale, appliedEnabled, appliedScale = SelectedGlobalScale()
            local applied = appliedEnabled and (Percent(appliedScale, 1) .. "%") or M.Tr("Off")
            local selected = selectedEnabled and (Percent(selectedScale, 1) .. "%") or M.Tr("Off")
            local changed = (selectedEnabled ~= appliedEnabled) or math.abs(selectedScale - appliedScale) > 0.001
            globalStatus:SetText(M.Format(M.Tr("Applied: %s   Selected: %s"), applied, selected))
            SetSliderValueSafe(globalScale, SnapPct(selectedScale * 100, 30, 150, 1))
            if globalApply then
                if changed then globalApply:Enable() else globalApply:Disable() end
                if globalApply.SetActive then globalApply:SetActive(changed) end
            end
            if globalRevert then
                if changed then globalRevert:Enable() else globalRevert:Disable() end
            end
        end
        globalScale:HookScript("OnValueChanged", function(self, value)
            if self._msuf2Refreshing then return end
            local pct = SnapPct(value, 30, 150, 1)
            if pct ~= value then SetSliderValueSafe(self, pct) end
            pendingGlobalEnabled = true
            pendingGlobalScale = Clamp(pct / 100, 0.3, 1.5)
            RefreshGlobalScale()
        end)
        local function ApplyGlobalScale(enabled, value, preset)
            local dbScale, ui = GlobalState()
            ui.Enabled = enabled == true
            ui.Scale = Clamp(value or ui.Scale, 0.3, 1.5)
            dbScale.globalUiScalePreset = preset or (ui.Enabled and "custom" or "auto")
            dbScale.globalUiScaleValue = ui.Enabled and ui.Scale or nil
            pendingGlobalEnabled, pendingGlobalScale = nil, nil
            if ui.Enabled and type(_G.MSUF_SetGlobalUiScale) == "function" then
                pcall(_G.MSUF_SetGlobalUiScale, ui.Scale, true)
            elseif (not ui.Enabled) and type(_G.MSUF_ResetGlobalUiScale) == "function" then
                pcall(_G.MSUF_ResetGlobalUiScale, true)
            end
            if M.RequestGeneralApply then M.RequestGeneralApply("MSUF2_DASH_GLOBAL_SCALE", { preview = true, applyAll = false }) end
            RefreshGlobalScale()
        end
        Button(scaling, "1080p", globalX, globalTop - 100, 52, 20, function() ApplyGlobalScale(true, 768 / 1080, "1080p") end)
        Button(scaling, "1440p", globalX + 60, globalTop - 100, 52, 20, function() ApplyGlobalScale(true, 768 / 1440, "1440p") end)
        Button(scaling, "4K", globalX + 120, globalTop - 100, 42, 20, function() ApplyGlobalScale(true, 768 / 2160, "4k") end)
        Button(scaling, "Pixel", globalX + 170, globalTop - 100, 52, 20, function() ApplyGlobalScale(true, PixelScale(), "pixel") end)
        globalApply = Button(scaling, "Apply", globalX, globalTop - 126, 72, 20, function()
            local selectedEnabled, selectedScale = SelectedGlobalScale()
            ApplyGlobalScale(selectedEnabled, selectedScale, selectedEnabled and "custom" or "auto")
        end, "primary")
        globalRevert = Button(scaling, "Revert", globalX + 82, globalTop - 126, 72, 20, function()
            pendingGlobalEnabled, pendingGlobalScale = nil, nil
            RefreshGlobalScale()
        end)
        Button(scaling, "Off", globalX + 164, globalTop - 126, 52, 20, function()
            pendingGlobalEnabled = false
            RefreshGlobalScale()
        end)

        local RefreshMsufScale = BuildSimpleScaleColumn({
            x = msufX, top = msufTop, label = "MSUF Frame Scale", help = "Changes the actual MSUF unit frames in-game.",
            minPct = 25, maxPct = 150, stepPct = 5,
            applied = AppliedMsufScale,
            pending = PendingMsufScale,
            set = function(value) pendingMsufScale = value end,
            clear = function() pendingMsufScale = nil end,
            apply = function(scaleValue)
                local dbScale = M.GetGeneralDB()
                dbScale.msufUiScale = scaleValue
                pendingMsufScale = nil
                if type(_G.MSUF_ApplyMsufScale) == "function" then pcall(_G.MSUF_ApplyMsufScale, scaleValue) end
                if M.RequestGeneralApply then M.RequestGeneralApply("MSUF2_DASH_MSUF_SCALE", { preview = true, applyAll = false }) end
                local UF = MSUF and MSUF.UF
                if UF and UF.Apply then UF.Apply(nil) end
            end,
        })
        local RefreshMenuScale = BuildSimpleScaleColumn({
            x = menuX, top = menuTop, label = "MSUF Menu Scale", help = "Changes only this configuration menu window.",
            minPct = 25, maxPct = 150, stepPct = 5,
            applied = AppliedMenuScale,
            pending = PendingMenuScale,
            set = function(value) pendingMenuScale = value end,
            clear = function() pendingMenuScale = nil end,
            apply = function(scaleValue)
                local dbScale = M.GetGeneralDB()
                dbScale.slashMenuScale = scaleValue
                pendingMenuScale = nil
                if M.frame and M.frame.SetScale then M.frame:SetScale((M.GetEffectiveMenuScale and M.GetEffectiveMenuScale(scaleValue)) or scaleValue) end
            end,
        })

        RefreshGlobalScale()
        RefreshMsufScale()
        RefreshMenuScale()
        M.AddRefresher(ctx, RefreshGlobalScale)
        M.AddRefresher(ctx, RefreshMsufScale)
        M.AddRefresher(ctx, RefreshMenuScale)
    end

    local changelogTop = scalingTop - scalingH - 10
    local changelogOpen = M.dashboardChangelogOpen == true
    local changelogH = changelogOpen and 360 or 42
    local changelog = Card(root, "", x0, changelogTop, recoveryW, changelogH, { 0.030, 0.040, 0.078, 0.86 }, T.colors.borderSoft)
    BuildDashboardChangelog(changelog, recoveryW, {
        title = "Changelog",
        sectionHeader = true,
        top = 0,
        bottom = 18,
        hideSummaryWhenClosed = true,
        onToggle = function()
            M.InvalidatePage("home")
            M.SelectPage("home")
        end,
    })

    local supportTop = changelogTop - changelogH - 10
    local supportCompact = recoveryW < 560
    local supportH = supportCompact and 116 or 78
    local support = Card(root, "", x0, supportTop, recoveryW, supportH, { 0.030, 0.040, 0.078, 0.86 }, T.colors.borderSoft)
    local supportTitle = T.Font(support, "GameFontNormal", M.Tr("How to support MSUF"), T.colors.text)
    supportTitle:SetPoint("TOPLEFT", support, "TOPLEFT", 16, -16)
    local supportTextW = max(160, recoveryW - (supportCompact and 32 or 230))
    local supportDesc = W.Text(support, "If MSUF helps your UI, support links are one click away.", 16, -42, supportTextW, T.colors.muted)
    if supportDesc.SetWordWrap then supportDesc:SetWordWrap(true) end
    if supportDesc.SetNonSpaceWrap then supportDesc:SetNonSpaceWrap(true) end

    local aboutVer
    if _G.C_AddOns and type(_G.C_AddOns.GetAddOnMetadata) == "function" then
        aboutVer = _G.C_AddOns.GetAddOnMetadata("MidnightSimpleUnitFrames", "Version")
    end
    local aboutText = M.Tr("by Mapko with the help from R41z0r")
    if type(aboutVer) == "string" and aboutVer ~= "" then
        local displayVersion = aboutVer:match("^%d") and ("v" .. aboutVer) or aboutVer
        aboutText = M.Format(M.Tr("%s  -  by Mapko with the help from R41z0r"), displayVersion)
    end
    local supportDescH = (supportDesc.GetStringHeight and supportDesc:GetStringHeight()) or 0
    if supportDescH < 12 then supportDescH = 12 end
    local aboutY = -42 - supportDescH - 5
    local supportAbout = W.Text(support, aboutText, 16, aboutY, supportTextW, T.colors.muted)
    if supportAbout.SetWordWrap then supportAbout:SetWordWrap(true) end
    if supportAbout.SetNonSpaceWrap then supportAbout:SetNonSpaceWrap(true) end

    local supportAboutH = (supportAbout.GetStringHeight and supportAbout:GetStringHeight()) or 0
    if supportAboutH < 12 then supportAboutH = 12 end
    local supportTextBottom = math.abs(aboutY - supportAboutH)
    if supportCompact then
        supportH = max(supportH, floor(supportTextBottom + 24 + 24))
    else
        supportH = max(supportH, floor(supportTextBottom + 14))
    end
    support:SetHeight(supportH)

    local iconDir = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\"
    local supportLinks = {
        { texture = "Patreon.png", title = "Patreon", tooltip = "Click to copy the Patreon support link.", url = "https://www.patreon.com/cw/MidnightSimpleUnitframes" },
        { texture = "PayPal.png", title = "PayPal", tooltip = "Click to copy the PayPal support link.", url = "https://www.paypal.com/ncp/payment/H3N2P87S53KBQ" },
        { texture = "Ko-Fi.png", title = "Ko-fi", tooltip = "Click to copy the Ko-fi link.", url = "https://ko-fi.com/midnightsimpleunitframes#linkModal" },
        { texture = "GitHub.png", title = "GitHub", tooltip = "Click to copy the GitHub repository link.", url = "https://github.com/Mapkov2/MidnightSimpleUnitFrames" },
    }
    local iconRow = CreateFrame("Frame", nil, support)
    iconRow:SetSize(160, 24)
    if supportCompact then
        iconRow:SetPoint("BOTTOMLEFT", support, "BOTTOMLEFT", 16, 12)
    else
        iconRow:SetPoint("RIGHT", support, "RIGHT", -16, 0)
    end
    local previous
    for i = 1, #supportLinks do
        local data = supportLinks[i]
        local btn = CreateFrame("Button", nil, iconRow)
        btn:SetSize(24, 24)
        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture(iconDir .. data.texture)
        local hover = btn:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.10)
        btn:SetScript("OnClick", function()
            if type(_G.MSUF_ShowCopyLink) == "function" then
                _G.MSUF_ShowCopyLink(data.title, data.url)
            end
        end)
        AddTooltip(btn, data.title, data.tooltip)
        if type(M.RegisterSearchWidget) == "function" then
            M.RegisterSearchWidget(btn, {
                label = data.title,
                kind = "button",
                anchor = supportTitle,
                keywords = { data.tooltip, "How to support MSUF", "support links", data.url },
                help = data.tooltip,
            })
        end
        if previous then
            btn:SetPoint("LEFT", previous, "RIGHT", 10, 0)
        else
            btn:SetPoint("LEFT", iconRow, "LEFT", 0, 0)
        end
        previous = btn
    end

    local bottom = supportTop - supportH
    if sideBySide then bottom = min(bottom, sideBottom) end
    ctx:SetContentHeight(math.abs(bottom) + 42)
end

M.RegisterPage("home", { title = "MSUF Menu", build = BuildDashboardUX, version = 6 })
