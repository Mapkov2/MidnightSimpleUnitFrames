local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
--- Shell/Menu2/MSUF_Menu2_Widgets.lua
--- Shared Menu2 widget factory: the primitives every widget file uses.
---
--- Pages should compose controls through this module instead of constructing
--- raw frames ad hoc. Widgets also register search metadata, edit-mode preview
--- focus hooks, collapse state, pinned previews, and enable gates, so adding a
--- new control here keeps cross-page behavior consistent.
---
--- The factory is split by cohesion and loads in this order (MSUF_Menu2.xml):
---   MSUF_Menu2_Widgets.lua               accordion paint, search registration,
---                                        preview focus, cursor rows, text and cards
---   MSUF_Menu2_Widgets_PageBuilder.lua   W.PageBuilder, collapsible sections,
---                                        section focus, settings rows
---   MSUF_Menu2_Widgets_Buttons.lua       top/role buttons and section badges
---   MSUF_Menu2_Widgets_ContextColors.lua card-local color shortcuts
---   MSUF_Menu2_Widgets_Controls.lua      toggles, switches, scope bar, slider,
---                                        segments and text input
---   MSUF_Menu2_Widgets_Gates.lua         enable gates, disabled reasons, placement
---   MSUF_Menu2_Widgets_PreviewDock.lua   sticky headers, fixed and pinned previews
--- Helpers the files share live in the private W._Shared table; everything
--- pages call stays on W.

local addonName, MSUF = ...
MSUF = MSUF or {}
addonName = (type(MSUF.AddonName) == "string" and MSUF.AddonName ~= "" and MSUF.AddonName)
    or "MidnightSimpleUnitFrames"
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local C_Timer = M.MenuTimer or _G.C_Timer
local T = M.Theme
local W = M.Widgets or {}
M.Widgets = W
W.spacing = T and T.spacing or W.spacing
W.Space = T and T.Space or W.Space
local floor = math.floor
local max = math.max
local min = math.min
local WHITE8 = "Interface\\Buttons\\WHITE8x8"
local ACCORDION_OPEN_CORNER = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\Masks\\rounded_mask.tga"
local ACCORDION_OPEN_CORNER_SIZE = 4
local ACCORDION_OPEN_CORNER_UV = 17 / 128
-- PageBuilder accordions extend eight units past the ScrollFrame viewport:
-- builder x=12 + ctx width=(CONTENT_W-32), viewport right=(CONTENT_W-28).
-- Keep only the header cap inside the viewport; body layout remains unchanged.
local ACCORDION_HEADER_RIGHT_INSET = 8
local Tr = M.TranslateText
local EM2Util = (_G.MSUF_EM2 and _G.MSUF_EM2.Util) or {}
local function ThemeColor(name, fallback)
    local c = T and T.colors and T.colors[name]
    return c or fallback
end
local function AccordionRegionsSetShown(self, shown)
    for i = 1, #self do self[i]:SetShown(shown) end
end
local function AccordionRegionsSetAlpha(self, alpha)
    for i = 1, #self do self[i]:SetAlpha(alpha) end
end
local function AccordionRegionsSetColorTexture(self, r, g, b, a)
    for i = 1, #self do self[i]:SetVertexColor(r, g, b, a or 1) end
end
local function CreateAccordionRoundedRegions(header, layer, subLevel)
    local radius = ACCORDION_OPEN_CORNER_SIZE
    local uv = ACCORDION_OPEN_CORNER_UV
    local regions = {
        SetShown = AccordionRegionsSetShown,
        SetAlpha = AccordionRegionsSetAlpha,
        SetColorTexture = AccordionRegionsSetColorTexture,
    }
    local middle = PixelLayoutRegion(header:CreateTexture(nil, layer, nil, subLevel))
    middle:SetTexture(WHITE8)
    middle:SetPoint("TOPLEFT", header, "TOPLEFT", radius, 0)
    middle:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -radius, 0)
    regions.middle = middle
    regions[#regions + 1] = middle
    local function Side(pointA, pointB, sideKey)
        local tex = PixelLayoutRegion(header:CreateTexture(nil, layer, nil, subLevel))
        tex:SetTexture(WHITE8)
        tex:SetPoint(pointA, header, pointA, 0, pointA:find("^TOP") and -radius or radius)
        tex:SetPoint(pointB, header, pointB, 0, pointB:find("^TOP") and -radius or radius)
        tex:SetWidth(radius)
        regions[sideKey] = tex
        regions[#regions + 1] = tex
    end
    Side("TOPLEFT", "BOTTOMLEFT", "left")
    Side("TOPRIGHT", "BOTTOMRIGHT", "right")
    local function Corner(point, u1, u2, v1, v2, sideKey)
        local tex = PixelLayoutRegion(header:CreateTexture(nil, layer, nil, subLevel))
        tex:SetTexture(ACCORDION_OPEN_CORNER, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        tex:SetTexCoord(u1, u2, v1, v2)
        tex:SetSize(radius, radius)
        tex:SetPoint(point, header, point, 0, 0)
        local bucket = regions[sideKey .. "Corners"]
        if not bucket then bucket = {}; regions[sideKey .. "Corners"] = bucket end
        bucket[#bucket + 1] = tex
        regions[#regions + 1] = tex
    end
    -- Preserve the original left cap exactly. The asset's native right crop is
    -- its byte-identical horizontal mirror and avoids transformed UV sampling.
    Corner("TOPLEFT", 0, uv, 0, uv, "left")
    Corner("TOPRIGHT", 1 - uv, 1, 0, uv, "right")
    Corner("BOTTOMLEFT", 0, uv, 1 - uv, 1, "left")
    Corner("BOTTOMRIGHT", 1 - uv, 1, 1 - uv, 1, "right")
    return regions
end
local function SetAccordionHighlightSide(regions, side, color)
    side:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    for i = 1, #regions do regions[i]:SetVertexColor(color[1], color[2], color[3], color[4] or 1) end
end
local function AccordionLinearize(value)
    if value <= 0.03928 then return value / 12.92 end
    return ((value + 0.055) / 1.055) ^ 2.4
end
local function AccordionLuminance(r, g, b)
    return 0.2126 * AccordionLinearize(r) + 0.7152 * AccordionLinearize(g)
        + 0.0722 * AccordionLinearize(b)
end
local function AccordionContrastAt(r, g, b, alpha, tone, backdrop, textLuminance)
    local opacity = 1 - alpha
    local surfaceLuminance = AccordionLuminance(
        r * tone * alpha + backdrop[1] * opacity,
        g * tone * alpha + backdrop[2] * opacity,
        b * tone * alpha + backdrop[3] * opacity)
    local light, dark = max(textLuminance, surfaceLuminance), min(textLuminance, surfaceLuminance)
    return (light + 0.05) / (dark + 0.05)
end
-- Keep the authored blue gradient, but deepen pale accent colors until the
-- near-white title remains readable on the translucent open header.
local function AccordionReadableTone(r, g, b, alpha, backdrop, textLuminance)
    if AccordionContrastAt(r, g, b, alpha, 1, backdrop, textLuminance) >= 5.5 then return 1 end
    local low, high = 0, 1
    for _ = 1, 8 do
        local middle = (low + high) * 0.5
        if AccordionContrastAt(r, g, b, alpha, middle, backdrop, textLuminance) >= 5.5 then
            low = middle
        else
            high = middle
        end
    end
    return low
end
local function AccordionOpenHighlightSetColors(self, fromColor, toColor)
    local fr, fg, fb, fa = fromColor[1], fromColor[2], fromColor[3], fromColor[4] or 1
    local tr, tg, tb, ta = toColor[1], toColor[2], toColor[3], toColor[4] or 1
    local backdrop = ThemeColor("panel2", { 0.055, 0.098, 0.161, 1 })
    local title = ThemeColor("text", { 0.933, 0.957, 1, 1 })
    local textLuminance = AccordionLuminance(title[1], title[2], title[3])
    local fromTone = AccordionReadableTone(fr, fg, fb, fa, backdrop, textLuminance)
    local toTone = AccordionReadableTone(tr, tg, tb, ta, backdrop, textLuminance)
    fr, fg, fb = fr * fromTone, fg * fromTone, fb * fromTone
    tr, tg, tb = tr * toTone, tg * toTone, tb * toTone
    if self._msuf2FromR == fr and self._msuf2FromG == fg and self._msuf2FromB == fb and self._msuf2FromA == fa
        and self._msuf2ToR == tr and self._msuf2ToG == tg and self._msuf2ToB == tb and self._msuf2ToA == ta then
        return
    end
    self._msuf2FromR, self._msuf2FromG, self._msuf2FromB, self._msuf2FromA = fr, fg, fb, fa
    self._msuf2ToR, self._msuf2ToG, self._msuf2ToB, self._msuf2ToA = tr, tg, tb, ta
    local safeFrom = self._msuf2SafeFromColor or {}
    local safeTo = self._msuf2SafeToColor or {}
    self._msuf2SafeFromColor, self._msuf2SafeToColor = safeFrom, safeTo
    safeFrom[1], safeFrom[2], safeFrom[3], safeFrom[4] = fr, fg, fb, fa
    safeTo[1], safeTo[2], safeTo[3], safeTo[4] = tr, tg, tb, ta
    if T.ApplyTextureGradient then
        T.ApplyTextureGradient(self.middle, "HORIZONTAL", safeFrom, safeTo, false)
    else
        self.middle:SetColorTexture(tr, tg, tb, ta)
    end
    SetAccordionHighlightSide(self.leftCorners, self.left, safeFrom)
    SetAccordionHighlightSide(self.rightCorners, self.right, safeTo)
end
local function CreateAccordionOpenHighlight(header, fromColor, toColor)
    local regions = CreateAccordionRoundedRegions(header, "BACKGROUND", 1)
    regions.SetColors = AccordionOpenHighlightSetColors
    regions:SetColors(fromColor, toColor)
    regions:SetShown(false)
    return regions
end
W.CreateAccordionRoundedRegions = CreateAccordionRoundedRegions
W.CreateAccordionOpenHighlight = CreateAccordionOpenHighlight
-- Every accordion uses the same border independently of page-specific content.
-- The owner calls this only on open/hover/theme transitions, never on a ticker.
function W.CreateAccordionBorder(header)
    local edges = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = PixelLayoutRegion(header:CreateTexture(nil, "BORDER"))
        if side == "TOP" or side == "BOTTOM" then
            edge:SetHeight(1)
            edge:SetPoint(side .. "LEFT", header, side .. "LEFT", 4, 0)
            edge:SetPoint(side .. "RIGHT", header, side .. "RIGHT", -4, 0)
        else
            edge:SetWidth(1)
            edge:SetPoint("TOP" .. side, header, "TOP" .. side, 0, -4)
            edge:SetPoint("BOTTOM" .. side, header, "BOTTOM" .. side, 0, 4)
        end
        edges[#edges + 1] = edge
    end
    header._msuf2AccordionBorder = edges
    return function(open, hover)
        local active = open or hover
        local c = active and T.colors.accent or T.colors.borderSoft
        for i, edge in ipairs(edges) do
            local alpha = active and 0.75 or 0.55
            if T.quietSections then
                -- One quiet baseline; only the active section gets a gold marker.
                alpha = i == 2 and (hover and 0.30 or 0.16) or (i == 3 and active and 0.65 or 0)
            end
            edge:SetColorTexture(c[1], c[2], c[3], alpha)
        end
    end
end
function W.SetCollapsibleHeaderBaseTone(target, color, alpha)
    local entry = target and (target._msuf2CollapsibleEntry or target)
    if not entry then return end
    entry._msuf2HeaderBaseColor = type(color) == "table" and color or nil
    entry._msuf2HeaderBaseAlpha = color and tonumber(alpha) or nil
    if entry._msuf2RefreshHeaderTone then entry._msuf2RefreshHeaderTone(false) end
end
local function WithAlpha(color, alpha)
    return { color[1], color[2], color[3], alpha }
end
local function SetSearchText(object, text)
    if object and text ~= nil then object._msuf2SearchText = text end
    return object
end
local function SetSearchTitle(object, text)
    if object and text ~= nil then object._msuf2SearchTitle = text end
    return object
end
local function PlaceBackdropFrameBehindControls(frame, parent)
    if not (frame and frame.SetFrameLevel) then return end
    local parentLevel = 0
    if parent and parent.GetFrameLevel then parentLevel = tonumber(parent:GetFrameLevel()) or 0 end
    frame:SetFrameLevel(max(0, parentLevel))
end
local function RegisterSearchObject(object, label, kind, opts)
    SetSearchText(object, label)
    if object and type(M.RegisterSearchWidget) == "function" then
        opts = opts or {}
        opts.label = opts.label or label
        opts.kind = opts.kind or kind
        M.RegisterSearchWidget(object, opts)
    end
    return object
end
local function QueueDockedPreviewOwnershipRefresh(scroll)
    scroll = scroll or M.scrollFrame
    local list = M._dockedPreviews
    if not scroll or type(list) ~= "table" or #list == 0 then return end
    if M.RefreshPinnedPreviews then M.RefreshPinnedPreviews(scroll) end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if M.RefreshPinnedPreviews then M.RefreshPinnedPreviews(scroll) end
        end)
    end
end
local function ResolveFocusValue(value)
    if type(value) == "function" then return value() end
    return value
end
local UNIT_FOCUS_KEYS = M.KeySetFromWords "player target targettarget focustarget focus pet pettarget boss arena"
local GROUP_FOCUS_KIND = {
    gf_party = "party",
    gf_raid = "raid",
    gf_mythicraid = "mythicraid",
    party = "party",
    raid = "raid",
    mythicraid = "mythicraid",
}
local NormalizeFocusKey = EM2Util.NormalizeFocusKey
local NormalizeFocusComponent = EM2Util.NormalizeFocusComponent
local NormalizeFocusSlot = EM2Util.NormalizeFocusSlot

--- Bridge hover/selection in menu controls to the live unit/group preview focus
--- system. The preview modules own rendering; widgets only send focus intent.
function W.SetPreviewFocus(key, component, slot, active)
    key = NormalizeFocusKey(ResolveFocusValue(key))
    component = NormalizeFocusComponent(ResolveFocusValue(component))
    slot = NormalizeFocusSlot(ResolveFocusValue(slot))
    local textComponent = (component == "name" or component == "hp" or component == "power")
    local didFocus = false
    if (not key) or (not component) then
        local clearUnit = _G.MSUF_UFPreview_ClearTextFocus
        if type(clearUnit) == "function" then didFocus = clearUnit() or didFocus end
        if type(M.FocusGFPreviewTextSlot) == "function" then didFocus = M.FocusGFPreviewTextSlot(nil, nil, false) or didFocus end
        return didFocus
    end
    if textComponent and UNIT_FOCUS_KEYS[key] then
        local fn = _G.MSUF_UFPreview_FocusTextSlot
        if type(fn) == "function" then didFocus = fn(key, component, slot, active == true) or didFocus end
    end
    if textComponent and GROUP_FOCUS_KIND[key] and type(M.FocusGFPreviewTextSlot) == "function" then didFocus = M.FocusGFPreviewTextSlot(component, slot, active == true) or didFocus end
    return didFocus
end
function W.AttachEditFocus(widget, key, component, slot, opts)
    if not (widget and widget.HookScript) then return widget end
    opts = opts or {}
    widget:HookScript("OnEnter", function()
        W.SetPreviewFocus(key, component, slot, false)
        local fn = _G.MSUF_EM2_SetFocusHover
        if type(fn) == "function" then fn(ResolveFocusValue(key), ResolveFocusValue(component), ResolveFocusValue(slot), { source = opts.source or "menu2" }) end
    end)
    widget:HookScript("OnLeave", function()
        W.SetPreviewFocus(nil, nil, nil, false)
        local fn = _G.MSUF_EM2_ClearFocusHover
        if type(fn) == "function" then fn() end
    end)
    if opts.selectOnDown ~= false then
        widget:HookScript("OnMouseDown", function()
            W.SetPreviewFocus(key, component, slot, true)
            local fn = _G.MSUF_EM2_SetFocusSelection
            if type(fn) == "function" then fn(ResolveFocusValue(key), ResolveFocusValue(component), ResolveFocusValue(slot), { source = opts.source or "menu2" }) end
        end)
    end
    return widget
end
local UNIT_EDIT_FOCUS_OPTS, GROUP_EDIT_FOCUS_OPTS = { source = "menu2-unit" }, { source = "menu2-group" }
function W.AttachUnitEditFocus(widget, unit, component, slot) return W.AttachEditFocus(widget, unit, component, slot, UNIT_EDIT_FOCUS_OPTS) end
function W.AttachGroupEditFocus(widget, key, component, slot) return W.AttachEditFocus(widget, key, component, slot, GROUP_EDIT_FOCUS_OPTS) end
-- Private hand-off to the other widget files (see the file header). They load
-- right after this file and read these once at load.
local Shared = {
    ACCORDION_OPEN_CORNER_SIZE = ACCORDION_OPEN_CORNER_SIZE,
    ACCORDION_HEADER_RIGHT_INSET = ACCORDION_HEADER_RIGHT_INSET,
    ThemeColor = ThemeColor,
    WithAlpha = WithAlpha,
    SetSearchText = SetSearchText,
    SetSearchTitle = SetSearchTitle,
    PlaceBackdropFrameBehindControls = PlaceBackdropFrameBehindControls,
    QueueDockedPreviewOwnershipRefresh = QueueDockedPreviewOwnershipRefresh,
}
W._Shared = Shared
local function NextRow(section, height)
    local y = section._msuf2CursorY or -40
    section._msuf2CursorY = y - (height or 28)
    return section._msuf2ContentX or 16, y
end
--- Public cursor advance for pages that mix flowed rows with manually placed
--- blocks (e.g. a row of side-by-side ControlCards): reserve the block's height
--- once instead of hand-summing offsets, then let b:FinishSection derive the
--- section height from the cursor.
W.NextRow = NextRow
function W.Text(parent, text, x, y, width, color)
    local fs = T.Font(parent, "GameFontHighlightSmall", text or "", color or T.colors.muted, "supporting")
    SetSearchText(fs, text)
    RegisterSearchObject(fs, text, "text")
    fs:SetPoint("TOPLEFT", x or 0, y or 0)
    fs:SetWidth(width or 300)
    fs:SetJustifyH("LEFT")
    return fs
end
-- Long supporting copy has a visible help button. Warnings and instructions
-- keep their full text through W.Text.
W.DescriptionDetails = true
function W.Description(parent, text, x, y, width, title, details)
    local fs = W.Text(parent, text, x, y, max(24, (width or 300) - 30))
    fs:SetWordWrap(true)
    fs:SetMaxLines(2)
    if M.AddTooltip and text and text ~= "" then
        local help = PixelLayoutRegion(CreateFrame("Button", nil, parent))
        help:SetSize(24, 24)
        local glyph = T.Font(help, "GameFontHighlight", "?", T.colors.text, "body")
        glyph:SetPoint("CENTER", help, "CENTER", 0, 0)
        help:SetPoint("TOPLEFT", fs, "TOPRIGHT", 6, 4)
        help._msuf2SkipHistoryCheckpoint = true
        M.AddTooltip(help, title or "Help", details or text)
        help:SetScript("OnClick", function(self)
            local show = self:GetScript("OnEnter")
            if show then show(self) end
        end)
        local function RefreshHelp()
            help:SetShown(details ~= nil or not fs.IsTruncated or fs:IsTruncated())
        end
        parent:HookScript("OnShow", RefreshHelp)
        parent:HookScript("OnSizeChanged", RefreshHelp)
        RefreshHelp()
        fs._msuf2HelpTarget = help
    end
    return fs
end

function W.SetCollapsibleSummary(section, text)
    local entry = section and section._msuf2CollapsibleEntry
    if not (entry and entry.header) then return end
    local summary = entry._msuf2UXSummary
    if not summary then
        summary = T.Font(entry.header, "GameFontHighlightSmall", "", T.colors.muted, "supporting")
        summary:SetJustifyH("LEFT")
        summary:SetWordWrap(false)
        summary:SetMaxLines(1)
        entry._msuf2UXSummary = summary
    end
    summary:SetText(text or "")
    if entry._msuf2RefreshLayout then entry._msuf2RefreshLayout() end
end
function W.ControlCard(parent, title, subtitle, x, y, width, height)
    if not parent then return nil end
    width = width or 360
    height = height or 120
    local cardBase = ThemeColor("coreShadow", { 0.006, 0.016, 0.032, 1.00 })
    local cardBg = { cardBase[1], cardBase[2], cardBase[3], 0.86 }
    local cardBorder = T.colors.cardBorder or T.colors.borderSoft
    local card = T.Panel(parent, nil, cardBg, cardBorder)
    T.ApplySurface(card, { bg = cardBg, border = cardBorder, plastic = false })
    SetSearchTitle(card, title)
    RegisterSearchObject(card, title, "section")
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y or 0)
    card:SetSize(width, height)
    PlaceBackdropFrameBehindControls(card, parent)
    card._msuf2Width = width
    card._msuf2ContentX = 16
    card._msuf2CursorY = -52
    card._msuf2ControlCard = true
    card._msuf2ControlCardTitle = title
    card._msuf2ContextColorLeft = tonumber(x) or 0
    card._msuf2ContextColorTop = tonumber(y) or 0
    card._msuf2ContextColorWidth = width
    card._msuf2ContextColorHeight = height
    parent._msuf2ControlCards = parent._msuf2ControlCards or {}
    parent._msuf2ControlCards[#parent._msuf2ControlCards + 1] = card
    if card.EnableMouse then card:EnableMouse(false) end
    local heading = T.Font(card, "GameFontNormal", title or "", T.colors.text, "card")
    SetSearchText(heading, title)
    heading:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -16)
    heading:SetWidth(max(24, width - 32))
    heading:SetJustifyH("LEFT")
    card.title = heading
    if subtitle and subtitle ~= "" then
        local sub = W.Description(card, subtitle, 16, -40, max(24, width - 32), title)
        card.subtitle = sub
    end
    return card
end
function W.ControlCardBackdrop(parent, x, y, width, height, bg, border)
    if not parent then return nil end
    width = max(24, floor((tonumber(width) or 360) + 0.5))
    height = max(24, floor((tonumber(height) or 120) + 0.5))
    x = floor((tonumber(x) or 0) + 0.5)
    y = floor((tonumber(y) or 0) + 0.5)
    local cardBase = ThemeColor("coreShadow", { 0.006, 0.016, 0.032, 1.00 })
    local cardBg = bg or { cardBase[1], cardBase[2], cardBase[3], 0.86 }
    local cardBorder = border or T.colors.cardBorder or T.colors.borderSoft
    local card = T.Panel(parent, nil, cardBg, cardBorder)
    T.ApplySurface(card, { bg = cardBg, border = cardBorder, plastic = false })
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    card:SetSize(width, height)
    PlaceBackdropFrameBehindControls(card, parent)
    card._msuf2Width = width
    card._msuf2DecorativeBackdrop = true
    if card.EnableMouse then card:EnableMouse(false) end
    if card.SetHitRectInsets then card:SetHitRectInsets(0, 0, 0, 0) end
    return card
end
-- Screenshot preview used by the onboarding tours. The art is plain, so the
-- well only has to letterbox it at `spec.aspect` (2:1 by default) into the
-- width the caller has left, and match the rim of the card it sits in.
-- Returns the well plus the height it consumed so callers can size the card.
function W.PreviewImage(parent, spec, x, y, width)
    if not (parent and type(spec) == "table" and type(spec.texture) == "string" and spec.texture ~= "") then
        return nil, 0
    end
    local frameWidth = max(80, floor((tonumber(width) or 200) + 0.5))
    local aspect = tonumber(spec.aspect) or 2
    if aspect <= 0 then aspect = 2 end
    local frameHeight = max(40, floor(frameWidth / aspect + 0.5))
    local well = T.Panel(parent, nil, T.colors.coreShadow or T.colors.bg, T.colors.pillEdge or T.colors.borderSoft)
    well:SetPoint("TOPLEFT", parent, "TOPLEFT", floor((tonumber(x) or 0) + 0.5), floor((tonumber(y) or 0) + 0.5))
    well:SetSize(frameWidth, frameHeight)
    T.ApplySurface(well, "card")
    if well.EnableMouse then well:EnableMouse(false) end
    local image = PixelLayoutRegion(well:CreateTexture(nil, "ARTWORK", nil, 2))
    image:SetPoint("TOPLEFT", well, "TOPLEFT", 3, -3)
    image:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -3, 3)
    image:SetTexture(spec.texture)
    local coords = spec.texCoord
    if type(coords) == "table" and #coords >= 4 then
        image:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    end
    well.image = image
    return well, frameHeight
end
-- W.Color and W.ParseHexColor: MSUF_Menu2_ColorPicker.lua, loaded next.

local function SetTileVisual(btn, active, hover)
    if not btn then return end
    if btn.SetBackdropColor then
        if active then
            btn:SetBackdropColor(0.100, 0.180, 0.300, hover and 0.98 or 0.92)
            btn:SetBackdropBorderColor(0.260, 0.620, 1.000, 1.00)
        elseif hover then
            btn:SetBackdropColor(0.115, 0.135, 0.185, 0.95)
            btn:SetBackdropBorderColor(0.380, 0.450, 0.620, 0.95)
        else
            btn:SetBackdropColor(0.045, 0.052, 0.076, 0.92)
            btn:SetBackdropBorderColor(0.190, 0.220, 0.310, 0.85)
        end
    end
    if btn._label then
        if active then
            btn._label:SetTextColor(0.95, 1.00, 1.00, 1)
        else
            btn._label:SetTextColor(0.74, 0.80, 0.90, 0.95)
        end
    end
end
W.SetTileVisual = SetTileVisual

-- Growth and layout tiles (unit Boss layout, group Growth) mark the first
-- frame of their mini preview with a "1" badge and the growth direction with
-- an arrow. Both are built on first use and reused on every repaint.
function W.EnsureTileFirstBadge(btn)
    if not btn._firstText then
        btn._firstText = PixelLayoutRegion(btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
        if btn._firstText.SetFont then btn._firstText:SetFont(_G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", T.FontSize("micro"), "OUTLINE") end
        btn._firstText:SetText("1")
        btn._firstText:SetTextColor(0, 0, 0, 1)
    end
    return btn._firstText
end
function W.PaintTileDirectionArrow(btn, info, labelH)
    if not btn._arrow then
        btn._arrow = PixelLayoutRegion(btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
        if btn._arrow.SetFont then btn._arrow:SetFont(_G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", T.FontSize("caption"), "OUTLINE") end
        btn._arrow:SetTextColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.95)
    end
    btn._arrow:SetText(info.arrow)
    btn._arrow:ClearAllPoints()
    if info.dy == -1 then
        btn._arrow:SetPoint("BOTTOM", btn, "BOTTOM", 0, labelH + 1)
    elseif info.dy == 1 then
        btn._arrow:SetPoint("TOP", btn, "TOP", 0, -4)
    elseif info.dx == 1 then
        btn._arrow:SetPoint("RIGHT", btn, "RIGHT", -4, labelH * 0.5)
    else
        btn._arrow:SetPoint("LEFT", btn, "LEFT", 4, labelH * 0.5)
    end
    btn._arrow:Show()
end

local function ToggleBadge(label, enabled)
    return { text = label .. (enabled and " On" or " Off"), kind = enabled and "accent" or "muted", showWhenClosed = true }
end
W.ToggleBadge = ToggleBadge

local function ThemedControlCard(parent, title, subtitle, x, y, width, height)
    local card = W.ControlCard(parent, title, subtitle, x, y, width, height)
    if card and T.ApplyBackdrop then T.ApplyBackdrop(card, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft) end
    return card
end
W.ThemedControlCard = ThemedControlCard

W.RegisterSearchObject = RegisterSearchObject

local function SetTextLayout(fontString, width, justify)
    if not fontString then return fontString end
    fontString:SetWidth(math.max(1, width or 1))
    fontString:SetJustifyH(justify or "LEFT")
    if fontString.SetWordWrap then fontString:SetWordWrap(true) end
    if fontString.SetNonSpaceWrap then fontString:SetNonSpaceWrap(true) end
    return fontString
end
W.SetTextLayout = SetTextLayout
