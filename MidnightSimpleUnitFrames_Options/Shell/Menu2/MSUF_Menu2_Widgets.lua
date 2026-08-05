--- Shell/Menu2/MSUF_Menu2_Widgets.lua
--- Shared Menu2 widget factory.
---
--- Pages should compose controls through this module instead of constructing
--- raw frames ad hoc. Widgets also register search metadata, edit-mode preview
--- focus hooks, collapse state, pinned previews, and enable gates, so adding a
--- new control here keeps cross-page behavior consistent.

local addonName, MSUF = ...
MSUF = MSUF or {}
addonName = (type(MSUF.AddonName) == "string" and MSUF.AddonName ~= "" and MSUF.AddonName)
    or "MidnightSimpleUnitFrames"
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
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
local sliderSerial = 0
local Tr = M.TranslateText or function(text) return text end
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
    local middle = header:CreateTexture(nil, layer, nil, subLevel)
    middle:SetTexture(WHITE8)
    middle:SetPoint("TOPLEFT", header, "TOPLEFT", radius, 0)
    middle:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -radius, 0)
    regions.middle = middle
    regions[#regions + 1] = middle
    local function Side(pointA, pointB, sideKey)
        local tex = header:CreateTexture(nil, layer, nil, subLevel)
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
        local tex = header:CreateTexture(nil, layer, nil, subLevel)
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
local function AccordionOpenHighlightSetColors(self, fromColor, toColor)
    local fr, fg, fb, fa = fromColor[1], fromColor[2], fromColor[3], fromColor[4] or 1
    local tr, tg, tb, ta = toColor[1], toColor[2], toColor[3], toColor[4] or 1
    if self._msuf2FromR == fr and self._msuf2FromG == fg and self._msuf2FromB == fb and self._msuf2FromA == fa
        and self._msuf2ToR == tr and self._msuf2ToG == tg and self._msuf2ToB == tb and self._msuf2ToA == ta then
        return
    end
    self._msuf2FromR, self._msuf2FromG, self._msuf2FromB, self._msuf2FromA = fr, fg, fb, fa
    self._msuf2ToR, self._msuf2ToG, self._msuf2ToB, self._msuf2ToA = tr, tg, tb, ta
    if T.ApplyTextureGradient then
        T.ApplyTextureGradient(self.middle, "HORIZONTAL", fromColor, toColor, false)
    else
        self.middle:SetColorTexture(tr, tg, tb, ta)
    end
    SetAccordionHighlightSide(self.leftCorners, self.left, fromColor)
    SetAccordionHighlightSide(self.rightCorners, self.right, toColor)
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
local UNIT_FOCUS_KEYS = M.KeySetFromWords "player target targettarget focustarget focus pet boss"
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
        local clearUnit = _G.MSUF_UFPreview_ClearFocus
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
local function MenuFocusRequestMatches(pageKey, sectionId)
    local req = _G.MSUF_EM2_MenuFocusRequest
    if type(req) ~= "table" or not req.sectionId then return nil end
    if req.explicit ~= true then return nil end
    if req.consumed == true then return nil end
    if tostring(req.sectionId) ~= tostring(sectionId or "") then return nil end
    if req.pageKey and tostring(req.pageKey) ~= tostring(pageKey or "") then return nil end
    return req
end
local function ConsumeMenuFocusRequest(req)
    if type(req) == "table" and _G.MSUF_EM2_MenuFocusRequest == req then req.consumed = true end
end
local function MenuStateTable(field)
    if type(M.GetPersistentMenuStateTable) == "function" then
        M[field] = M.GetPersistentMenuStateTable(field)
    else
        M[field] = M[field] or {}
    end
    return M[field]
end
local function GetCollapseHintClickState() return MenuStateTable("collapseHintClickState") end
local function RefreshCollapseHintSuppression(entry)
    local hint = entry and entry.hint
    if not hint then return end
    local counts = GetCollapseHintClickState()
    local count = tonumber(counts and counts.total) or 0
    hint._msuf2SuppressCollapseHint = count >= (tonumber(T.collapseHintClickHideThreshold) or 8)
end
local function CloseAutoFocusedSections(pageKey)
    local entry = M.cache and M.cache[pageKey]
    local sections = entry and entry.sections
    if type(sections) ~= "table" then return false end
    local changed
    local relayout = {}
    for _, section in pairs(sections) do
        local collapsible = section and section._msuf2CollapsibleEntry
        if collapsible and collapsible._msuf2AutoOpened == true then
            collapsible._msuf2AutoOpened = nil
            collapsible._msuf2Closing = nil
            collapsible._msuf2MotionActive = nil
            collapsible.open = false
            if M.accordionState and collapsible.stateKey then M.accordionState[collapsible.stateKey] = nil end
            if collapsible.body then
                if collapsible.body.SetAlpha then collapsible.body:SetAlpha(1) end
                if collapsible.body.Hide then collapsible.body:Hide() end
            end
            if collapsible._msuf2RefreshHeaderTone then collapsible._msuf2RefreshHeaderTone(false) end
            if T.ApplyCollapseVisual then T.ApplyCollapseVisual(collapsible.arrow, collapsible.hint, false) end
            if collapsible.builder then relayout[collapsible.builder] = true end
            changed = true
        end
    end
    if changed then
        for builder in pairs(relayout) do
            if builder.RelayoutCollapsibles then builder:RelayoutCollapsibles() end
        end
    end
    return changed and true or false
end
local function NotifyCollapsibleSectionState(entry, open)
    if not entry then return end
    open = open and true or false
    if entry._msuf2LastNotifiedOpen == open then return end
    entry._msuf2LastNotifiedOpen = open
    local fn = M.OnCollapsibleSectionStateChanged
    if type(fn) == "function" then fn(entry.pageKey, entry.sectionId, open, entry) end
end
local SECTION_FOCUS_GAP = 12
local function EffectiveFrameScale(frame, fallback)
    local scale = frame and frame.GetEffectiveScale and tonumber(frame:GetEffectiveScale())
    if not scale or scale <= 0 then return fallback or 1 end
    return scale
end
local function ScrollToCollapsibleEntry(entry)
    local outer = entry and entry.outer
    local scroll = M.scrollFrame
    local child = M.scrollChild
    if not (outer and scroll and child and outer.GetTop and child.GetTop and scroll.SetVerticalScroll) then return false end
    local childTop = child:GetTop()
    local outerTop = outer:GetTop()
    if not (childTop and outerTop) then return false end
    local scrollScale = EffectiveFrameScale(scroll, 1)
    local childScale = EffectiveFrameScale(child, scrollScale)
    local outerScale = EffectiveFrameScale(outer, scrollScale)
    local contentOffset = ((childTop * childScale) - (outerTop * outerScale)) / scrollScale
    scroll:SetVerticalScroll(max(0, floor(contentOffset + 0.5) - SECTION_FOCUS_GAP))
    if scroll._msuf2RefreshScrollBar then scroll:_msuf2RefreshScrollBar() end
    return true
end
local function FlashCollapsibleHeader(entry)
    local header = entry and entry.header
    if not header then return end
    if not entry._msuf2FocusFlash then
        local flash = CreateFrame("Frame", nil, header)
        flash:SetAllPoints(header)
        flash:EnableMouse(false)
        local c = T.colors.accent or ThemeColor("coreBlue", { 0.060, 0.250, 0.390, 1.00 })
        local flashFill = CreateAccordionRoundedRegions(flash, "ARTWORK", 0)
        flashFill:SetColorTexture(c[1], c[2], c[3], 0.18)
        flash._msuf2RoundedFill = flashFill
        flash:SetAlpha(0)
        flash:Hide()
        entry._msuf2FocusFlash = flash
    end
    local flash = entry._msuf2FocusFlash
    entry._msuf2FocusToken = (entry._msuf2FocusToken or 0) + 1
    local token = entry._msuf2FocusToken
    flash:SetAlpha(0.72)
    flash:Show()
    local function FadeOut()
        if entry._msuf2FocusToken ~= token then return end
        if T.PlayMotion then
            T.PlayMotion(flash, "controlFocusOut", {
                fromAlpha = flash.GetAlpha and flash:GetAlpha() or 0.72,
                toAlpha = 0,
                duration = 0.18,
                onFinished = function()
                    if entry._msuf2FocusToken ~= token then return end
                    flash:Hide()
                    flash:SetAlpha(0)
                end,
            })
        else
            flash:Hide()
            flash:SetAlpha(0)
        end
    end
    C_Timer.After(0.14, FadeOut)
end

--- Used by search/edit-mode deep links. Opens the section, scrolls it into view,
--- and flashes the header without permanently changing accordion state unless
--- the caller asks to persist.
function W.FocusCollapsibleSection(section, opts)
    local entry = section and section._msuf2CollapsibleEntry
    if not entry then return false end
    opts = opts or {}
    -- Pages that show only one section group at a time (e.g. the Colors
    -- categories) install this to reveal the group the target lives in.
    if type(entry._msuf2EnsureVisible) == "function" then entry._msuf2EnsureVisible(entry) end
    local chain, cursor = {}, entry
    while cursor do
        table.insert(chain, 1, cursor)
        cursor = cursor.ancestorEntry
    end
    for i = 1, #chain do
        local current = chain[i]
        local wasOpen = current.open == true
        current._msuf2MotionSerial = (current._msuf2MotionSerial or 0) + 1
        current._msuf2MotionActive = nil
        current.open = true
        current._msuf2Closing = nil
        if opts.persist == true then
            current._msuf2AutoOpened = nil
            if M.accordionState and current.stateKey then M.accordionState[current.stateKey] = true end
        elseif not wasOpen or current._msuf2AutoOpened == true then
            current._msuf2AutoOpened = true
        end
        if current.body then
            current.body:Show()
            if current.body.SetAlpha then current.body:SetAlpha(1) end
        end
        if current.builder and current.builder.RelayoutCollapsibles then current.builder:RelayoutCollapsibles() end
    end
    local function FinishFocus()
        if opts.scroll ~= false then ScrollToCollapsibleEntry(entry) end
        if opts.flash ~= false then FlashCollapsibleHeader(entry) end
    end
    C_Timer.After(0, FinishFocus)
    return true
end
function M.FocusRequestedSection(pageKey, opts)
    local req = _G.MSUF_EM2_MenuFocusRequest
    if type(req) ~= "table" or not req.sectionId then
        CloseAutoFocusedSections(pageKey or M.activeKey)
        return false
    end
    if req.consumed == true then return false end
    if req.explicit ~= true then
        CloseAutoFocusedSections(pageKey or req.pageKey or M.activeKey)
        return false
    end
    pageKey = pageKey or req.pageKey or M.activeKey
    if req.pageKey and tostring(req.pageKey) ~= tostring(pageKey or "") then
        CloseAutoFocusedSections(pageKey)
        return false
    end
    local entry = M.cache and M.cache[pageKey]
    local sections = entry and entry.sections
    local section = sections and sections[tostring(req.sectionId)]
    if not section and entry and type(entry._msuf2ResolveMissingSection) == "function" then
        -- Lazily built section groups (Colors categories) can materialize the
        -- requested section on demand before the focus attempt gives up.
        section = entry._msuf2ResolveMissingSection(tostring(req.sectionId))
    end
    if not section then
        CloseAutoFocusedSections(pageKey)
        return false
    end
    ExportPublic("MSUF_EM2_MenuFocusSection", section)
    local focusOpts = opts
    if req.persistSection == true then
        -- Keep request-owned options isolated: callers may reuse their table
        -- for temporary search/edit-mode focus, which must remain transient.
        focusOpts = {}
        for key, value in pairs(opts or {}) do focusOpts[key] = value end
        focusOpts.persist = true
    end
    local focused = W.FocusCollapsibleSection(section, focusOpts)
    if focused then ConsumeMenuFocusRequest(req) end
    return focused
end
function M.CloseAutoFocusedSections(pageKey)
    return CloseAutoFocusedSections(pageKey or M.activeKey)
end
local SLIDER_TEMPLATE_KEEP_KEYS, SLIDER_TEMPLATE_SUFFIXES = M.WordList "_msufTrack _msufTrackTop _msufTrackBottom _msufFill _msufFillGlow _msuf2Thumb _msufPeelTrack _msufPeelTrackFill", M.WordList "Left Middle Right Text Low High"
local function IsTextureRegion(region)
    if not region then return false end
    if region.IsObjectType then return region:IsObjectType("Texture") and true or false end
    return region.GetObjectType and region:GetObjectType() == "Texture"
end
local function HideSliderTemplateParts(slider)
    if not slider then return end
    local thumb = slider.GetThumbTexture and slider:GetThumbTexture()
    local keep = {}
    if thumb then keep[thumb] = true end
    for i = 1, #SLIDER_TEMPLATE_KEEP_KEYS do
        local region = slider[SLIDER_TEMPLATE_KEEP_KEYS[i]]
        if region then keep[region] = true end
    end
    local regions = { slider:GetRegions() }
    for i = 1, #regions do
        local region = regions[i]
        if IsTextureRegion(region) and not keep[region] then
            if region.SetAlpha then region:SetAlpha(0) end
            if region.Hide then region:Hide() end
        end
    end
    local name = slider.GetName and slider:GetName()
    for _, suffix in ipairs(SLIDER_TEMPLATE_SUFFIXES) do
        local region = (name and _G[name .. suffix]) or slider[suffix]
        if region then
            if region.SetText then region:SetText("") end
            if region.SetAlpha then region:SetAlpha(0) end
            if region.Hide then region:Hide() end
        end
    end
end

--- Page layout builder used by most Menu2 pages. It owns vertical flow,
--- collapsible section state, search metadata registration, and content height.
local function NextGuidedTourOrder(ctx)
    local entry = ctx and ctx.entry
    if type(entry) ~= "table" then return nil end
    entry._msuf2GuidedTourOrder = (tonumber(entry._msuf2GuidedTourOrder) or 0) + 1
    return entry._msuf2GuidedTourOrder
end

local function RegisterGuidedTourRegion(ctx, frame, title, stableId)
    local pageEntry = ctx and ctx.entry
    if type(pageEntry) ~= "table" or not frame then return nil end
    local order = NextGuidedTourOrder(ctx)
    if not order then return nil end
    local region = {
        id = tostring(stableId or "") ~= "" and tostring(stableId) or ("region_" .. tostring(order)),
        pageKey = tostring(ctx.key or ""),
        label = tostring(title or "") ~= "" and tostring(title) or "Scope and overrides",
        body = frame,
        outer = frame,
        guidedOrder = order,
        kind = "region",
    }
    pageEntry.guidedRegions = pageEntry.guidedRegions or {}
    pageEntry.guidedRegions[region.id] = region
    pageEntry._msuf2GuidedSortedSections = nil
    frame._msuf2GuidedRegion = region
    return region
end

function W.RegisterGuidedRegion(ctx, frame, title, stableId)
    if frame and frame._msuf2GuidedRegion then
        local region = frame._msuf2GuidedRegion
        local changed = false
        if tostring(title or "") ~= "" and region.label ~= tostring(title) then
            region.label = tostring(title)
            changed = true
        end
        stableId = tostring(stableId or "")
        if stableId ~= "" and region.id ~= stableId then
            local regions = ctx and ctx.entry and ctx.entry.guidedRegions
            if type(regions) == "table" then
                for key, value in pairs(regions) do
                    if value == region then regions[key] = nil end
                end
                region.id = stableId
                regions[stableId] = region
                changed = true
            end
        end
        if changed and ctx and ctx.entry then ctx.entry._msuf2GuidedSortedSections = nil end
        return region
    end
    return RegisterGuidedTourRegion(ctx, frame, title, stableId)
end

function W.PageBuilder(ctx, opts)
    if type(M.EnsurePersistentMenuState) == "function" then M.EnsurePersistentMenuState() end
    opts = type(opts) == "table" and opts or {}
    local contentX = tonumber(opts.contentX) or tonumber(ctx and ctx._msuf2ContentX) or 12
    local topInset = tonumber(opts.topInset) or tonumber(ctx and ctx._msuf2TopInset) or 0
    local function UpdateContentHeight(height)
        if type(opts.onContentHeight) == "function" then
            opts.onContentHeight(height)
        elseif ctx.SetContentHeight then
            ctx:SetContentHeight(height)
        end
    end
    local b = {
        ctx = ctx,
        parent = opts.parent or ctx.wrapper,
        x = contentX,
        y = -12 - topInset,
        width = tonumber(opts.width) or ctx.width or 720,
        ancestorEntry = opts.ancestorEntry,
        collapsibles = {},
        layoutEntries = {},
    }
    if type(ctx) == "table" then
        ctx._msuf2PageBuilders = ctx._msuf2PageBuilders or {}
        ctx._msuf2PageBuilders[#ctx._msuf2PageBuilders + 1] = b
    end
    function b:RequestRelayoutCollapsibles()
        if ctx and ctx._msuf2Building then
            self._msuf2RelayoutPending = true
            return
        end
        return self:RelayoutCollapsibles()
    end
    function b:RelayoutCollapsibles(opts)
        opts = type(opts) == "table" and opts or nil
        self._msuf2RelayoutPending = nil
        if not self._collapsibleStartY then return false end
        local y = self._collapsibleStartY
        local layoutChanged = false
        local entries = (#self.layoutEntries > 0) and self.layoutEntries or self.collapsibles
        for i = 1, #entries do
            local entry = entries[i]
            if entry.kind == "section" then
                local section = entry.frame
                if section then
                    local h = (section.GetHeight and section:GetHeight()) or entry.height or 120
                    local key = tostring(self.parent) .. "\030" .. tostring(self.x) .. "\030" .. tostring(y) .. "\030" .. tostring(h)
                    if section._msuf2RelayoutKey ~= key then
                        section._msuf2RelayoutKey = key
                        section:ClearAllPoints()
                        section:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, y)
                        layoutChanged = true
                    end
                    y = y - h - (entry.gap or 12)
                end
            elseif entry.kind == "spacer" then
                y = y - (entry.height or 10)
            else
                local open = entry.open and true or false
                local openChanged = entry._msuf2RelayoutOpen ~= open
                entry._msuf2RelayoutOpen = open
                local outerH = entry.headerHeight + (open and entry.contentHeight or 0)
                local key = tostring(self.parent) .. "\030" .. tostring(self.x) .. "\030" .. tostring(y)
                    .. "\030" .. tostring(outerH) .. "\030" .. tostring(open)
                if entry._msuf2RelayoutKey ~= key then
                    entry._msuf2RelayoutKey = key
                    entry.outer:ClearAllPoints()
                    entry.outer:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, y)
                    entry.outer:SetHeight(outerH)
                    layoutChanged = true
                end
                if entry.body._msuf2ShownState ~= open then
                    entry.body._msuf2ShownState = open
                    entry.body:SetShown(open)
                    if entry.bodySurface then entry.bodySurface:SetShown(open) end
                    layoutChanged = true
                end
                if openChanged or (opts and opts.refreshVisuals) then
                    if entry.body.SetAlpha and not entry._msuf2MotionActive then entry.body:SetAlpha(1) end
                    T.ApplyCollapseVisual(entry.arrow, entry.hint, open)
                    if entry._msuf2RefreshHeaderTone then entry._msuf2RefreshHeaderTone(false) end
                    if entry._msuf2RefreshColorSwatchVisibility then entry._msuf2RefreshColorSwatchVisibility() end
                    NotifyCollapsibleSectionState(entry, open)
                end
                local refreshState = entry._msuf2RefreshState
                local refreshUntracked = opts and opts.refreshUntrackedState
                local trackedState = refreshState and entry._msuf2TrackedRefreshState == refreshState
                if refreshState
                    and not (opts and opts.skipStateRefresh)
                    and (openChanged or (refreshUntracked and not trackedState) or (opts and opts.forceStateRefresh))
                then
                    refreshState(entry)
                end
                y = y - entry.outer:GetHeight() - 8
            end
        end
        if self.y ~= y then
            self.y = y
            layoutChanged = true
        end
        local contentHeight = math.abs(y) + 42
        if self._msuf2LastContentHeight ~= contentHeight then
            self._msuf2LastContentHeight = contentHeight
            UpdateContentHeight(contentHeight)
            layoutChanged = true
        end
        if layoutChanged then QueueDockedPreviewOwnershipRefresh(M.scrollFrame) end
        return layoutChanged
    end
    function b:Section(title, height)
        local section = T.Panel(self.parent, nil, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft)
        T.ApplySurface(section, "card")
        SetSearchTitle(section, title)
        RegisterSearchObject(section, title, "section")
        section:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, self.y)
        section:SetSize(self.width, height or 120)
        section._msuf2CursorY = -40
        section._msuf2ContentX = 16
        section._msuf2Width = self.width
        section._msuf2ContextColorHost = true
        section._msuf2ContextColorHostTitle = title
        local fs = T.Font(section, "GameFontNormal", Tr(title or ""), T.colors.text, "section")
        SetSearchText(fs, title)
        fs:SetPoint("TOPLEFT", 16, -12)
        section.title = fs
        self.y = self.y - (height or 120) - 12
        UpdateContentHeight(math.abs(self.y) + 28)
        if self._collapsibleStartY then
            self.layoutEntries[#self.layoutEntries + 1] = {
                kind = "section",
                frame = section,
                height = height or 120,
                gap = 12,
            }
        end
        W.RegisterGuidedRegion(ctx, section, title)
        return section
    end
    function b:CollapsibleSection(id, title, height, defaultOpen)
        M.accordionState = MenuStateTable("accordionState")
        local collapseHintClickState = GetCollapseHintClickState()
        local sectionId = tostring(id or title or "section")
        local openHighlightEnabled = sectionId:lower():find("preview", 1, true) == nil
        local stateKey = tostring(ctx.key or "page") .. ":" .. sectionId
        local saved = M.accordionState[stateKey]
        local open = (saved == nil) and (defaultOpen and true or false) or (saved and true or false)
        local headerH = 28
        if not self._collapsibleStartY then self._collapsibleStartY = self.y end
        -- The wrapper must stay visually empty. A full card surface here sits
        -- underneath the header and fills its transparent rounded corners.
        local outer = CreateFrame("Frame", nil, self.parent)
        outer._msuf2NoPanelNeon = true
        SetSearchTitle(outer, title)
        RegisterSearchObject(outer, title, "section")
        outer:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, self.y)
        outer:SetSize(self.width, headerH + (open and (height or 120) or 0))
        local bodySurface = T.Panel(outer, nil, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft)
        T.ApplySurface(bodySurface, "card")
        bodySurface:SetPoint("TOPLEFT", outer, "TOPLEFT", 0, -(headerH + ACCORDION_OPEN_CORNER_SIZE))
        -- Match the header's scrollbar clearance. Extending the open surface to
        -- the full wrapper width puts its right border underneath the viewport
        -- edge, where it is visibly clipped while scrolling.
        bodySurface:SetPoint("BOTTOMRIGHT", outer, "BOTTOMRIGHT", -ACCORDION_HEADER_RIGHT_INSET, 0)
        bodySurface:SetShown(open)
        PlaceBackdropFrameBehindControls(bodySurface, outer)
        local header = CreateFrame("Button", nil, outer)
        SetSearchTitle(header, title)
        header:SetPoint("TOPLEFT", outer, "TOPLEFT", 0, 0)
        header:SetPoint("TOPRIGHT", outer, "TOPRIGHT", -ACCORDION_HEADER_RIGHT_INSET, 0)
        header:SetHeight(headerH)
        local headerBg = CreateAccordionRoundedRegions(header, "BACKGROUND", 0)
        local headerSurface = ThemeColor("coreSurface", { 0.014, 0.038, 0.072, 1.00 })
        headerBg:SetColorTexture(headerSurface[1], headerSurface[2], headerSurface[3], 0.34)
        local headerOpenHighlight
        local headerActiveFrom, headerActiveTo
        if openHighlightEnabled then
            local headerActiveBlue = ThemeColor("coreGlow", { 0.231, 0.510, 0.965, 1.00 })
            local headerActiveDeep = ThemeColor("coreBlue", { 0.141, 0.365, 0.741, 1.00 })
            headerActiveFrom = { headerActiveBlue[1], headerActiveBlue[2], headerActiveBlue[3], 0.62 }
            headerActiveTo = { headerActiveDeep[1], headerActiveDeep[2], headerActiveDeep[3], 0.56 }
            headerOpenHighlight = CreateAccordionOpenHighlight(header, headerActiveFrom, headerActiveTo)
        end
        local arrow = header:CreateTexture(nil, "OVERLAY")
        arrow:SetSize(10, 10)
        arrow:SetPoint("LEFT", header, "LEFT", 12, 0)
        arrow:SetTexture(T.media.collapseArrow)
        -- Keep the selected face for accordion titles. Expressway's automatic
        -- Regular -> SemiBold face switch can cold-start blank until a relayout.
        local label = T.Font(header, "GameFontNormal", Tr(title or ""), T.colors.text, "accordion")
        SetSearchText(label, title)
        label:SetJustifyH("LEFT")
        local hint = T.Font(header, "GameFontDisableSmall", "", T.colors.dim)
        hint:SetJustifyH("RIGHT")
        local contentW = math.min(self.width, M.formContentMaxWidth or 980)
        local body = CreateFrame("Frame", nil, outer)
        SetSearchTitle(body, title)
        body:SetPoint("TOPLEFT", outer, "TOPLEFT", 0, -headerH)
        body:SetSize(contentW, height or 120)
        body._msuf2CursorY = -40
        body._msuf2ContentX = 16
        body._msuf2Width = contentW
        body._msuf2ContextColorHost = true
        body._msuf2ContextColorHostTitle = title
        local entry = {
            outer = outer,
            header = header,
            headerBg = headerBg,
            headerOpenHighlight = headerOpenHighlight,
            body = body,
            bodySurface = bodySurface,
            arrow = arrow,
            label = label,
            hint = hint,
            open = open,
            builder = self,
            pageKey = tostring(ctx.key or ""),
            sectionId = sectionId,
            headerHeight = headerH,
            contentHeight = height or 120,
            stateKey = stateKey,
            openHighlightEnabled = openHighlightEnabled,
            guidedOrder = NextGuidedTourOrder(ctx),
            ancestorEntry = self.ancestorEntry,
        }
        RefreshCollapseHintSuppression(entry)
        local function RefreshHeaderLayout()
            local headerW = (header.GetWidth and header:GetWidth()) or self.width or 240
            local reserve = math.max(120, math.min(136, math.floor(headerW * 0.38 + 0.5)))
            local swatchReserve = tonumber(entry._msuf2ColorSwatchReserve) or 0
            if not entry._msuf2ManualHintLayout then
                local badges = entry._msuf2Badges
                if badges and #badges > 0 then
                    local availableBadges = {}
                    local availableW = headerW - 12 - 28 - (headerW < 520 and 96 or 136) - swatchReserve
                    local totalW = 0
                    for i = 1, #badges do
                        local badge = badges[i]
                        if badge and badge._msuf2BadgeWantedShown ~= false then
                            local bw = (badge.GetWidth and badge:GetWidth()) or 0
                            if bw > 0 then
                                totalW = totalW + bw + (#availableBadges > 0 and 8 or 0)
                                availableBadges[#availableBadges + 1] = badge
                            end
                        end
                    end
                    availableW = max(0, availableW)
                    while #availableBadges > 1 and totalW > availableW do
                        local badge = availableBadges[#availableBadges]
                        totalW = totalW - ((badge.GetWidth and badge:GetWidth()) or 0) - (#availableBadges > 1 and 8 or 0)
                        availableBadges[#availableBadges] = nil
                    end
                    if #availableBadges == 1 and totalW > availableW then availableBadges[1] = nil end
                    local right = -12 - swatchReserve
                    for i = #badges, 1, -1 do
                        local badge = badges[i]
                        if badge then badge:SetShown(false) end
                    end
                    for i = #availableBadges, 1, -1 do
                        local badge = availableBadges[i]
                        local bw = (badge.GetWidth and badge:GetWidth()) or 0
                        badge:ClearAllPoints()
                        badge:SetPoint("RIGHT", header, "RIGHT", right, 0)
                        badge:SetShown(true)
                        right = right - bw - 8
                    end
                    if #availableBadges > 0 then
                        if hint.Hide then hint:Hide() end
                        label:ClearAllPoints()
                        label:SetPoint("LEFT", arrow, "RIGHT", 8, 0)
                        label:SetPoint("RIGHT", header, "RIGHT", right - 8, 0)
                        label:SetJustifyH("LEFT")
                        return
                    end
                end
                if hint.Show then hint:Show() end
                hint:ClearAllPoints()
                hint:SetPoint("TOPRIGHT", header, "TOPRIGHT", -(12 + swatchReserve), -1)
                hint:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -(12 + swatchReserve), 1)
                hint:SetPoint("LEFT", header, "RIGHT", -(12 + reserve + swatchReserve), 0)
                hint:SetJustifyH("RIGHT")
                label:ClearAllPoints()
                label:SetPoint("LEFT", arrow, "RIGHT", 8, 0)
                label:SetPoint("RIGHT", hint, "LEFT", -8, 0)
                label:SetJustifyH("LEFT")
            end
        end
        entry._msuf2RefreshLayout = RefreshHeaderLayout
        outer._msuf2CollapsibleEntry = entry
        body._msuf2CollapsibleEntry = entry
        body._msuf2SectionId = sectionId
        body._msuf2PageKey = tostring(ctx.key or "")
        if ctx.entry then
            ctx.entry.sections = ctx.entry.sections or {}
            ctx.entry.sections[sectionId] = body
            ctx.entry._msuf2GuidedSortedSections = nil
        end
        self.collapsibles[#self.collapsibles + 1] = entry
        local function SetHeaderSolid(color, alpha)
            headerBg._msuf2TextureMode = "solid"
            headerBg:SetColorTexture(color[1], color[2], color[3], alpha)
        end
        local headerHoverColor = { 0, 0, 0, 1 }
        local function RefreshHeaderTone(hover)
            -- SavedVariables may apply the selected accent after Options code
            -- has loaded. Resolve live tokens on every interaction transition
            -- instead of repainting a header from a stale Midnight snapshot.
            local liveSurface = ThemeColor("coreSurface", { 0.014, 0.038, 0.072, 1.00 })
            local liveRaised = ThemeColor("coreRaised", { 0.026, 0.070, 0.110, 1.00 })
            if headerOpenHighlight and headerOpenHighlight.SetColors then
                local activeBlue = ThemeColor("coreGlow", { 0.231, 0.510, 0.965, 1.00 })
                local activeDeep = ThemeColor("coreBlue", { 0.141, 0.365, 0.741, 1.00 })
                headerActiveFrom[1], headerActiveFrom[2], headerActiveFrom[3] = activeBlue[1], activeBlue[2], activeBlue[3]
                headerActiveTo[1], headerActiveTo[2], headerActiveTo[3] = activeDeep[1], activeDeep[2], activeDeep[3]
                headerOpenHighlight:SetColors(headerActiveFrom, headerActiveTo)
            end
            local active = entry.open == true and entry.openHighlightEnabled == true
            if entry._msuf2OpenHighlightShown ~= active then
                entry._msuf2OpenHighlightShown = active
                if headerOpenHighlight then headerOpenHighlight:SetShown(active) end
                headerBg:SetAlpha(active and 0 or 1)
            end
            if active then
                arrow:SetVertexColor(1, 1, 1, 0.98)
            elseif T.ApplyCollapseVisual then
                T.ApplyCollapseVisual(arrow, nil, entry.open)
            end
            local base = entry._msuf2HeaderBaseColor or liveSurface
            local baseAlpha = entry._msuf2HeaderBaseAlpha or (entry.open and 0.40 or 0.34)
            if hover and entry._msuf2HeaderBaseColor then
                headerHoverColor[1] = min((base[1] or 0) * 1.16, 1)
                headerHoverColor[2] = min((base[2] or 0) * 1.16, 1)
                headerHoverColor[3] = min((base[3] or 0) * 1.16, 1)
                SetHeaderSolid(headerHoverColor, max(baseAlpha, 0.42))
            elseif entry.open then
                SetHeaderSolid(base, hover and 0.48 or baseAlpha)
            elseif hover then
                SetHeaderSolid(liveRaised, 0.42)
            else
                SetHeaderSolid(base, baseAlpha)
            end
        end
        entry._msuf2RefreshHeaderTone = RefreshHeaderTone
        entry.kind = "collapsible"
        header:SetScript("OnClick", function()
            if entry._msuf2MotionActive then return end
            local nextOpen = not entry.open
            M.accordionState[stateKey] = nextOpen
            local threshold = tonumber(T.collapseHintClickHideThreshold) or 8
            collapseHintClickState.total = math.min((tonumber(collapseHintClickState.total) or 0) + 1, threshold)
            RefreshCollapseHintSuppression(entry)
            entry._msuf2MotionSerial = (entry._msuf2MotionSerial or 0) + 1
            local motionSerial = entry._msuf2MotionSerial
            if nextOpen then
                local function SettleOpenedLayout()
                    if entry._msuf2MotionSerial ~= motionSerial or not entry.open or entry._msuf2Closing then return end
                    -- Large nested sections (notably the Aura workspace) can
                    -- finish their child geometry only after becoming visible.
                    -- Reflow the root once that geometry has settled so the
                    -- ScrollFrame receives the expanded height immediately.
                    if type(entry._msuf2SettleContentLayout) == "function" then
                        entry._msuf2SettleContentLayout()
                    end
                    self:RelayoutCollapsibles()
                end
                entry.open = true
                RefreshHeaderTone(false)
                entry._msuf2MotionActive = true
                if body.SetAlpha then body:SetAlpha(0) end
                self:RelayoutCollapsibles()
                if C_Timer and C_Timer.After then C_Timer.After(0, SettleOpenedLayout) end
                if T.PlayMotion then
                    T.PlayMotion(body, "accordionIn", { fromAlpha = 0, onFinished = function()
                        if entry._msuf2MotionSerial ~= motionSerial then return end
                        entry._msuf2MotionActive = nil
                        if body.SetAlpha then body:SetAlpha(1) end
                        SettleOpenedLayout()
                    end })
                else
                    entry._msuf2MotionActive = nil
                    if body.SetAlpha then body:SetAlpha(1) end
                    SettleOpenedLayout()
                end
                return
            end
            entry._msuf2MotionActive = true
            entry._msuf2Closing = true
            T.ApplyCollapseVisual(entry.arrow, entry.hint, false)
            if entry._msuf2RefreshState then entry._msuf2RefreshState(entry) end
            if body.Show then body:Show() end
            if T.PlayMotion then
                T.PlayMotion(body, "accordionOut", { fromAlpha = body.GetAlpha and body:GetAlpha() or 1, onFinished = function()
                    if entry._msuf2MotionSerial ~= motionSerial then return end
                    entry.open = false
                    entry._msuf2MotionActive = nil
                    entry._msuf2Closing = nil
                    if body.SetAlpha then body:SetAlpha(1) end
                    self:RelayoutCollapsibles()
                end })
            else
                entry.open = false
                entry._msuf2MotionActive = nil
                entry._msuf2Closing = nil
                if body.SetAlpha then body:SetAlpha(1) end
                self:RelayoutCollapsibles()
            end
        end)
        header:HookScript("OnEnter", function() RefreshHeaderTone(true) end)
        header:HookScript("OnLeave", function() RefreshHeaderTone(false) end)
        header:HookScript("OnSizeChanged", RefreshHeaderLayout)
        if type(M.RegisterSearchWidget) == "function" then
            local pageToken = tostring(ctx.key or "page"):lower():gsub("[^%w_]+", "."):gsub("^%.*", ""):gsub("%.*$", "")
            local sectionToken = sectionId:lower():gsub("[^%w_]+", "."):gsub("^%.*", ""):gsub("%.*$", "")
            if pageToken == "" then pageToken = "page" end
            if sectionToken == "" then sectionToken = "section" end
            local identity = pageToken .. ".section." .. sectionToken .. ".expanded"
            local function SetSectionOpenImmediate(value)
                local wanted = value == true or value == 1
                    or type(value) == "string" and (value:lower() == "true" or value:lower() == "on" or value == "1")
                if entry.open == wanted and not entry._msuf2MotionActive then return true end
                entry._msuf2MotionSerial = (entry._msuf2MotionSerial or 0) + 1
                entry._msuf2MotionActive = nil
                entry._msuf2Closing = nil
                entry.open = wanted
                RefreshHeaderTone(false)
                M.accordionState[stateKey] = wanted
                if body.SetAlpha then body:SetAlpha(1) end
                self:RelayoutCollapsibles()
                if wanted and type(entry._msuf2SettleContentLayout) == "function" then
                    entry._msuf2SettleContentLayout()
                    self:RelayoutCollapsibles()
                end
                return entry.open == wanted
            end
            entry.SetOpenImmediate = SetSectionOpenImmediate
            M.RegisterSearchWidget(header, {
                controlId = "menu2." .. identity,
                identityKey = identity,
                controlPath = identity:gsub("%.", "/"),
                pageKey = pageToken,
                label = tostring(title or sectionId) .. " section",
                kind = "toggle",
                classification = "ephemeral",
                ephemeral = true,
                help = "Expands or collapses this options section.",
                command = {
                    kind = "toggle",
                    historyMode = "none",
                    get = function() return entry.open == true end,
                    set = SetSectionOpenImmediate,
                },
            })
        end
        self.y = self.y - outer:GetHeight() - 8
        RefreshHeaderLayout()
        RefreshHeaderTone(false)
        self.layoutEntries[#self.layoutEntries + 1] = entry
        self:RequestRelayoutCollapsibles()
        local focusReq = MenuFocusRequestMatches(ctx.key, sectionId)
        if focusReq then
            ExportPublic("MSUF_EM2_MenuFocusSection", body)
            if W.FocusCollapsibleSection(body, {
                flash = true,
                persist = focusReq.persistSection == true,
            }) then ConsumeMenuFocusRequest(focusReq) end
        end
        return body
    end
    function b:Header(title, subtitle, height)
        local section = T.Panel(self.parent, nil, T.colors.panel2, T.colors.border)
        SetSearchTitle(section, title)
        RegisterSearchObject(section, title, "section")
        section:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, self.y)
        section:SetSize(self.width, height or 78)
        local fs = T.Font(section, "GameFontNormalLarge", Tr(title or ""), T.colors.text, "heading")
        SetSearchText(fs, title)
        fs:SetPoint("TOPLEFT", 16, -12)
        section.title = fs
        if subtitle and subtitle ~= "" then
            local sub = T.Font(section, "GameFontDisableSmall", Tr(subtitle), T.colors.muted)
            SetSearchText(sub, subtitle)
            sub:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -8)
            sub:SetWidth(self.width - 28)
            sub:SetJustifyH("LEFT")
            section.subtitle = sub
        end
        self.y = self.y - (height or 78) - 12
        UpdateContentHeight(math.abs(self.y) + 28)
        if self._collapsibleStartY then
            self.layoutEntries[#self.layoutEntries + 1] = {
                kind = "section",
                frame = section,
                height = height or 78,
                gap = 12,
            }
        end
        return section
    end
    function b:GlobalStyleHeader(title, subtitle, height)
        return W.GlobalStyleHeader(ctx, self, title, subtitle, height)
    end
    function b:Spacer(height)
        self.y = self.y - (height or 10)
        UpdateContentHeight(math.abs(self.y) + 28)
        if self._collapsibleStartY then
            self.layoutEntries[#self.layoutEntries + 1] = {
                kind = "spacer",
                height = height or 10,
            }
        end
    end
    --- Auto-height: derives a section's height from its content cursor instead of a
    --- hand-declared constant. Call after the section content is built. Works for
    --- plain b:Section frames and collapsible bodies. Only acts when the content
    --- actually advanced the cursor (W.Toggle/W.Slider/W.NextRow flow); sections
    --- placed purely with explicit y offsets keep their declared height.
    function b:FinishSection(section, bottomPad)
        if not section then return nil end
        local cursor = tonumber(section._msuf2CursorY)
        if not cursor or cursor >= -38 then return nil end
        local height = math.max(48, -cursor + (tonumber(bottomPad) or 14))
        local entry = section._msuf2CollapsibleEntry
        if entry then
            entry.contentHeight = height
            if entry.body and entry.body.SetHeight then entry.body:SetHeight(height) end
            if entry.outer and entry.outer.SetHeight then
                entry.outer:SetHeight(entry.headerHeight + (entry.open and height or 0))
            end
            local owner = entry.builder or self
            if owner.RequestRelayoutCollapsibles then
                owner:RequestRelayoutCollapsibles()
            elseif owner.RelayoutCollapsibles then
                owner:RelayoutCollapsibles()
            end
            return height
        end
        local old = (section.GetHeight and section:GetHeight()) or 0
        if section.SetHeight then section:SetHeight(height) end
        if self._collapsibleStartY then
            for i = #self.layoutEntries, 1, -1 do
                local layoutEntry = self.layoutEntries[i]
                if layoutEntry.kind == "section" and layoutEntry.frame == section then
                    layoutEntry.height = height
                    break
                end
            end
            self:RequestRelayoutCollapsibles()
        else
            self.y = self.y - (height - old)
            if ctx.SetContentHeight then ctx:SetContentHeight(math.abs(self.y) + 28) end
        end
        return height
    end
    --- Declarative card layout. Renders one ControlCard whose controls auto-flow
    --- top-to-bottom using the SAME widget constructors and binders that hand-written
    --- pages use, so output is pixel-identical to a manually placed card. The point is
    --- to delete the repeated PlaceDropdown/PlaceSlider/MoveWidget choreography and the
    --- hand-computed -48/-112/-174 row offsets that came with it.
    ---
    --- spec = {
    ---   title, subtitle, x, y, width, height?,  -- height auto-computed when omitted
    ---   rows = { <controlSpec>, ... },
    --- }
    --- Returns { card = <frame>, controls = <id -> widget>, gate = <fn or nil> }.
    function b:Card(spec)
        return W.BuildCard(self.ctx, self.parent, spec)
    end
    return b
end

--- Height each auto-flowing widget kind consumes inside a card/section, matching the
--- NextRow() advances in the individual W.* constructors. Kept here so card height can be
--- pre-computed without first creating the widgets.
local CARD_ROW_HEIGHT = {
    toggle = 30, switch = 30, button = 30,
    slider = 48, dropdown = 48, segment = 48, textinput = 50,
    color = 34, text = 24, divider = 14, spacer = 0,
}

--- Resolve a per-row value that may be a literal or a function (values lists are often
--- runtime-built, e.g. SharedMedia font lists).
local function CardResolve(v)
    if type(v) == "function" then return v() end
    return v
end

--- Title-justify each widget kind expects from MoveWidget, matching the hand-written
--- PlaceDropdown ("LEFT") / PlaceSlider ("CENTER") conventions so converted cards keep
--- their exact label alignment.
local CARD_MOVE_JUSTIFY = { slider = "CENTER", dropdown = "LEFT", segment = "LEFT", textinput = "LEFT" }

--- Create + bind one control row, placing it at (x, y) inside the card via the SAME
--- MoveWidget call the hand-written pages use. Returns the widget, or nil for
--- non-interactive rows (text/divider/spacer handled by the caller).
local function BuildCardControl(ctx, card, row, x, y, width)
    local kind = row.kind or row.type
    local widget
    if kind == "toggle" then
        widget = W.ToggleAt(card, CardResolve(row.label), x, y, width)
        M.BindBoolWidget(ctx, widget, row.get, row.set, row)
        return widget
    elseif kind == "color" then
        widget = W.Color(card, CardResolve(row.label))
        W.MoveWidget(widget, card, x, y)
        M.BindColor(ctx, widget, row.get, row.set, row)
        return widget
    elseif kind == "slider" then
        widget = W.Slider(card, CardResolve(row.label), row.min or 0, row.max or 100, row.step or 1, row.width or width)
        if row.format and widget.SetValueFormatter then widget:SetValueFormatter(row.format) end
        local metadata = {}
        for key, value in pairs(row) do metadata[key] = value end
        metadata.step = row.step or 1
        metadata.roundStep = row.roundStep ~= false
        M.BindNumberWidget(ctx, widget, row.get, row.set, row.default, metadata)
    elseif kind == "segment" then
        widget = W.Segment(card, CardResolve(row.label), CardResolve(row.values), row.width or width)
        M.BindSegment(ctx, widget, row.get, row.set, row)
    elseif kind == "dropdown" then
        widget = W.Dropdown(card, CardResolve(row.label), CardResolve(row.values), row.width or width)
        M.BindDropdownWidget(ctx, widget, row.get, row.set, row)
    else
        return nil
    end
    W.MoveWidget(widget, card, x, y, row.width or width, CARD_MOVE_JUSTIFY[kind])
    return widget
end

--- Standalone card builder (also reachable as b:Card on a PageBuilder).
---
--- Each interactive row is placed explicitly at a cursor that starts at `firstRowY`
--- (default -52, matching ControlCard's own first-control line) and advances by the
--- row's height plus `rowGap` (default 6). Pin `firstRowY`/`rowGap`/per-row `height`
--- to reproduce an existing card's exact spacing, so a conversion stays pixel-identical.
---
--- spec = {
---   title, subtitle, x, y, width, height?, firstRowY?, rowGap?, contentX?,
---   rows = { { kind, label, get, set, values?/min/max/step?, width?, id?, controlId?, settingKey?, gate?, height? }, ... },
--- }
--- Returns { card = <frame>, controls = <id -> widget>, gate = <fn or nil> }.
function W.BuildCard(ctx, parent, spec)
    if not (parent and type(spec) == "table") then return nil end
    local rows = spec.rows or {}
    local width = spec.width or (parent._msuf2Width and (parent._msuf2Width - 32)) or 360
    local contentX = spec.contentX or 16
    local controlW = max(48, width - 32)
    local rowGap = spec.rowGap or 6
    -- Pre-compute card height from the row kinds unless the caller pinned one.
    local height = spec.height
    if not height then
        height = (spec.subtitle and spec.subtitle ~= "") and 64 or 52 -- title (+ subtitle) block
        for i = 1, #rows do
            local k = rows[i].kind or rows[i].type
            height = height + (rows[i].height or CARD_ROW_HEIGHT[k] or 30) + rowGap
        end
        height = height + 6 -- bottom padding
    end
    local card = W.ControlCard(parent, spec.title, spec.subtitle, spec.x or 0, spec.y or 0, width, height)
    if not card then return nil end
    local y = spec.firstRowY or ((spec.subtitle and spec.subtitle ~= "") and -64 or -52)
    local controls = {}
    local gated
    for i = 1, #rows do
        local row = rows[i]
        local kind = row.kind or row.type
        local rowHeight = row.height or CARD_ROW_HEIGHT[kind] or 30
        if kind == "spacer" then
            -- no widget; only advances the cursor
        elseif kind == "text" then
            local fs = W.LabelAt(card, CardResolve(row.text) or "", contentX, y, controlW, row.template, row.color)
            if row.id then controls[row.id] = fs end
        elseif kind == "divider" then
            W.DividerAt(card, y - 6)
        else
            local widget = BuildCardControl(ctx, card, row, contentX, y, controlW)
            if widget then
                if row.id then controls[row.id] = widget end
                if row.gate then
                    widget._msuf2GateFn = row.gate
                    gated = gated or {}
                    gated[#gated + 1] = widget
                end
            end
        end
        y = y - rowHeight - rowGap
    end
    -- Single shared gate refresher: any row.gate returning false disables its control.
    local gate
    if gated then
        gate = function()
            for i = 1, #gated do
                local w = gated[i]
                W.SetControlEnabled(w, w._msuf2GateFn() and true or false)
            end
        end
        if M.TrackRefresh then M.TrackRefresh(ctx, gate) end
    end
    return { card = card, controls = controls, gate = gate }
end

--- Uniform multi-column settings rows inside an EXISTING section or card (the
--- "Zeilen-Grid" building block): fixed cell metrics, cells flow left-to-right
--- then top-to-bottom, optional per-row reset-to-default action. Uses the same
--- row specs, constructors and binders as W.BuildCard, so converted sections
--- keep their control behavior and Assistant metadata unchanged.
---
--- spec = {
---   x?, y?, width?, columns? (default 2), colGap?, rowGap?,
---   rows = { { <BuildCardControl row fields> , reset? = function } , ... },
--- }
--- A row's `reset` writes its default through the row's own apply path; the
--- glyph next to the control stays dim until hovered.
--- Returns { controls = <id -> widget>, list = { widgets... },
---           resets = { buttons... }, bottomY = <next free y> }.
function W.SettingsRows(ctx, parent, spec)
    if not (parent and type(spec) == "table") then return nil end
    local rows = spec.rows or {}
    local width = spec.width or ((parent._msuf2Width or 400) - 32)
    local columns = max(1, spec.columns or 2)
    local colGap = spec.colGap or 18
    local rowGap = spec.rowGap or 6
    local x0 = spec.x or 16
    local colW = floor((width - colGap * (columns - 1)) / columns)
    local y = spec.y or -34
    local controls, list, resets = {}, {}, {}
    local col, rowH = 0, 0
    for i = 1, #rows do
        local row = rows[i]
        local kind = row.kind or row.type
        local cellH = row.height or CARD_ROW_HEIGHT[kind] or 30
        local x = x0 + col * (colW + colGap)
        local hasReset = type(row.reset) == "function"
        local widget = BuildCardControl(ctx, parent, row, x, y, colW - (hasReset and 22 or 0))
        if widget then
            if row.id then controls[row.id] = widget end
            list[#list + 1] = widget
            if hasReset then
                local resetBtn = CreateFrame("Button", nil, parent)
                resetBtn:SetSize(18, 18)
                resetBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", x + colW - 17, y - (kind == "slider" and 20 or 4))
                local glyph = T.Font(resetBtn, "GameFontDisableSmall", "\226\134\186", T.colors.muted)
                glyph:SetPoint("CENTER", resetBtn, "CENTER", 0, 0)
                resetBtn:SetAlpha(0.35)
                resetBtn:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
                resetBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.35) end)
                resetBtn:SetScript("OnClick", function()
                    row.reset()
                    if M.RequestRefresh then M.RequestRefresh(ctx, "settings-row-reset") end
                end)
                if M.AddTooltip then
                    M.AddTooltip(resetBtn, Tr(CardResolve(row.label) or "Setting"), Tr("Reset this value to its default."), { hook = true })
                end
                resets[#resets + 1] = resetBtn
            end
        end
        rowH = max(rowH, cellH)
        col = col + 1
        if col >= columns then
            col = 0
            y = y - rowH - rowGap
            rowH = 0
        end
    end
    if col > 0 then y = y - rowH - rowGap end
    return { controls = controls, list = list, resets = resets, bottomY = y }
end
local function TopButtonStyle(bg, border, textColor, hoverBg, hoverBorder)
    return {
        bg = bg, border = border, textColor = textColor,
        hoverBg = hoverBg, hoverBorder = hoverBorder,
        activeBg = bg, activeBorder = border, activeTextColor = textColor,
    }
end
local TOP_ACTION_BUTTON_STYLE = TopButtonStyle(
    { 0.006, 0.016, 0.032, 0.82 },
    { 0.043, 0.096, 0.150, 0.46 },
    { 0.82, 0.90, 1.00, 0.96 },
    { 0.014, 0.038, 0.072, 0.86 },
    { 0.060, 0.250, 0.390, 0.42 })
local TOP_DANGER_BUTTON_STYLE = TopButtonStyle({ 0.070, 0.026, 0.034, 0.94 }, { 0.340, 0.090, 0.110, 0.82 }, { 1.00, 0.82, 0.82, 1 }, { 0.090, 0.035, 0.045, 0.96 }, { 0.420, 0.120, 0.140, 0.90 })
local TOP_SUCCESS_BUTTON_STYLE = TopButtonStyle({ 0.018, 0.145, 0.090, 0.94 }, { 0.055, 0.440, 0.270, 0.82 }, { 0.780, 1.000, 0.875, 1 }, { 0.026, 0.185, 0.115, 0.96 }, { 0.075, 0.560, 0.345, 0.90 })
local TOP_ROLE_STYLES = { primary = TOP_ACTION_BUTTON_STYLE, destructive = TOP_DANGER_BUTTON_STYLE, danger = TOP_DANGER_BUTTON_STYLE, reset = TOP_DANGER_BUTTON_STYLE, delete = TOP_DANGER_BUTTON_STYLE, success = TOP_SUCCESS_BUTTON_STYLE, confirm = TOP_SUCCESS_BUTTON_STYLE }
-- Options may load before PLAYER_LOGIN, while the saved Menu2 accent is applied
-- at PLAYER_LOGIN. Do not retain the Midnight copies created during file load:
-- resolve the live token tables whenever a top button is constructed. Mutating
-- this shared style also keeps custom styles' missing-field fallbacks current.
local function RefreshTopActionButtonStyle()
    local style = TOP_ACTION_BUTTON_STYLE
    style.bg = WithAlpha(ThemeColor("coreShadow", { 0.006, 0.016, 0.032, 1.00 }), 0.82)
    style.border = WithAlpha(ThemeColor("coreRim", { 0.043, 0.096, 0.150, 1.00 }), 0.46)
    style.textColor = WithAlpha(ThemeColor("pillText", { 0.82, 0.90, 1.00, 1.00 }), 0.96)
    style.hoverBg = WithAlpha(ThemeColor("coreSurface", { 0.014, 0.038, 0.072, 1.00 }), 0.86)
    style.hoverBorder = WithAlpha(ThemeColor("coreBlue", { 0.060, 0.250, 0.390, 1.00 }), 0.42)
    style.activeBg = style.bg
    style.activeBorder = style.border
    style.activeTextColor = style.textColor
    return style
end
local function ApplyTopActionButtonVisual(btn, hover)
    local bg = btn._msuf2TopActive and btn._msuf2TopActiveBg or (hover and btn._msuf2TopHoverBg or btn._msuf2TopBg)
    local br = btn._msuf2TopActive and btn._msuf2TopActiveBorder or (hover and btn._msuf2TopHoverBorder or btn._msuf2TopBorder)
    local tx = btn._msuf2TopActive and btn._msuf2TopActiveText or btn._msuf2TopText
    local mul = hover and 1.03 or 1
    if btn._msuf2Fill then
        local fill = { min(bg[1] * mul, 1), min(bg[2] * mul, 1), min(bg[3] * mul, 1), bg[4] or 1 }
        if T.SetFillGradient then T.SetFillGradient(btn._msuf2Fill, fill, 0.07, -0.26) else btn._msuf2Fill:SetVertexColor(fill[1], fill[2], fill[3], fill[4]) end
    end
    if btn._msuf2Edge then btn._msuf2Edge:SetVertexColor(min(br[1] * mul, 1), min(br[2] * mul, 1), min(br[3] * mul, 1), br[4] or 1) end
    if btn._msuf2Label then btn._msuf2Label:SetTextColor(tx[1], tx[2], tx[3], tx[4] or 1) end
    if btn._msuf2TopStripe then btn._msuf2TopStripe:SetShown(btn._msuf2TopActive and true or false) end
end
local TOP_BUTTON_HOOKS = { OnEnter = function(self) ApplyTopActionButtonVisual(self, true) end, OnLeave = function(self) ApplyTopActionButtonVisual(self) end, OnEnable = function(self) ApplyTopActionButtonVisual(self) end, OnDisable = function(self) ApplyTopActionButtonVisual(self) end }
local function StyleTopButton(btn, style)
    local defaults = RefreshTopActionButtonStyle()
    local s = style or defaults
    btn._msuf2TopActive = false
    btn._msuf2TopBg = s.bg or defaults.bg
    btn._msuf2TopBorder = s.border or defaults.border
    btn._msuf2TopText = s.textColor or defaults.textColor
    btn._msuf2TopHoverBg = s.hoverBg or s.bg or defaults.hoverBg or defaults.bg
    btn._msuf2TopHoverBorder = s.hoverBorder or s.border or defaults.hoverBorder or defaults.border
    btn._msuf2TopActiveBg = s.activeBg or s.bg or defaults.activeBg or defaults.bg
    btn._msuf2TopActiveBorder = s.activeBorder or s.border or defaults.activeBorder or defaults.border
    btn._msuf2TopActiveText = s.activeTextColor or s.textColor or defaults.activeTextColor or defaults.textColor
    if btn._msuf2Label then
        T.CenterButtonLabel(btn)
        if btn._msuf2Label.SetShadowColor then btn._msuf2Label:SetShadowColor(0, 0, 0, 0.55) end
        if btn._msuf2Label.SetShadowOffset then btn._msuf2Label:SetShadowOffset(1, -1) end
    end
    if s.stripe == true and not btn._msuf2TopStripe then
        local stripe = btn:CreateTexture(nil, "ARTWORK", nil, 6)
        local c = s.stripeColor or ThemeColor("coreBlue", { 0.060, 0.250, 0.390, 1.00 })
        stripe:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        stripe:SetWidth(s.stripeWidth or 3)
        stripe:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -5)
        stripe:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 2, 5)
        stripe:Hide()
        btn._msuf2TopStripe = stripe
    end
    btn.SetActive = function(self, active)
        self._msuf2TopActive = active and true or false
        ApplyTopActionButtonVisual(self)
    end
    btn.SetEnabled = function(self, enabled)
        if enabled then
            if self.Enable then self:Enable() end
        else
            if self.Disable then self:Disable() end
        end
        ApplyTopActionButtonVisual(self)
    end
    for script, handler in pairs(TOP_BUTTON_HOOKS) do btn:SetScript(script, handler) end
    ApplyTopActionButtonVisual(btn)
    return btn
end
local function StyleTopActionButton(btn)
    return StyleTopButton(btn, TOP_ACTION_BUTTON_STYLE)
end
local function StyleTopDangerButton(btn)
    return StyleTopButton(btn, TOP_DANGER_BUTTON_STYLE)
end
local function StyleTopSuccessButton(btn)
    return StyleTopButton(btn, TOP_SUCCESS_BUTTON_STYLE)
end
M.AssignNamedValues(W, "StyleTopActionButton StyleTopDangerButton StyleTopSuccessButton",
    StyleTopActionButton, StyleTopDangerButton, StyleTopSuccessButton)
function W.RoleButton(parent, label, role, width, height)
    local btn = (T.RoleButton and T.RoleButton(parent, label, role, width, height)) or T.Button(parent, label, width, height)
    role = tostring(role or "normal")
    return StyleTopButton(btn, TOP_ROLE_STYLES[role] or TOP_ACTION_BUTTON_STYLE)
end
function W.TopButton(parent, label, width, height, style, active)
    local btn = StyleTopButton(T.Button(parent, label, width, height), style)
    if active ~= nil and btn.SetActive then btn:SetActive(active) end
    return btn
end
function W.GlobalStyleHeader(ctx, builder, title, subtitle, height)
    return nil, nil
end
function W.SetCollapsibleToggleText(section, openText, closedText)
    local entry = section and section._msuf2CollapsibleEntry
    if not (entry and entry.label and entry.label.SetText) then return nil end
    local function Refresh()
        entry.label:SetText(Tr(entry.open and (openText or "") or (closedText or openText or "")))
    end
    if entry.header and entry.header.HookScript and not entry._msuf2DynamicTitleHooked then
        entry._msuf2DynamicTitleHooked = true
        entry.header:HookScript("OnClick", Refresh)
    end
    Refresh()
    return Refresh
end
local COLLAPSIBLE_BADGE_STYLES = {
    ok = {
        bg = { 0.018, 0.230, 0.145, 0.94 },
        border = { 0.050, 0.690, 0.430, 0.88 },
        text = { 0.640, 1.000, 0.820, 1 },
    },
    info = {
        bg = WithAlpha(ThemeColor("coreSurface", { 0.014, 0.038, 0.072, 1.00 }), 0.92),
        border = WithAlpha(ThemeColor("coreRim", { 0.043, 0.096, 0.150, 1.00 }), 0.78),
        text = { 0.760, 0.840, 1.000, 1 },
    },
    accent = {
        bg = WithAlpha(ThemeColor("coreRaised", { 0.026, 0.070, 0.110, 1.00 }), 0.94),
        border = WithAlpha(ThemeColor("coreBlue", { 0.060, 0.250, 0.390, 1.00 }), 0.72),
        text = { 0.680, 0.920, 1.000, 1 },
    },
    muted = {
        bg = WithAlpha(ThemeColor("coreShadow", { 0.006, 0.016, 0.032, 1.00 }), 0.90),
        border = WithAlpha(ThemeColor("coreRim", { 0.043, 0.096, 0.150, 1.00 }), 0.72),
        text = { 0.680, 0.730, 0.860, 1 },
    },
}
local function CollapsibleBadgeWidth(text)
    text = tostring(Tr(text or ""))
    return max(48, min(176, floor(22 + (#text * 6.2) + 0.5)))
end
-- The badge styles copy token colors at file load, before the menu accent
-- override runs; re-sync the accent border from the live token and pull the
-- remaining copies through the accent re-hue on first use.
local badgeStylesRehued
local function RefreshBadgeAccentBorder()
    local live = ThemeColor("coreBlue", nil)
    local accentBorder = COLLAPSIBLE_BADGE_STYLES.accent and COLLAPSIBLE_BADGE_STYLES.accent.border
    if live and accentBorder then
        accentBorder[1], accentBorder[2], accentBorder[3] = live[1], live[2], live[3]
    end
    if not badgeStylesRehued and T.MenuAccentRehueLiteral then
        badgeStylesRehued = true
        for _, style in pairs(COLLAPSIBLE_BADGE_STYLES) do
            T.MenuAccentRehueLiteral(style.bg)
            T.MenuAccentRehueLiteral(style.text)
            if style.border ~= accentBorder then T.MenuAccentRehueLiteral(style.border) end
        end
    end
end
function W.SetCollapsibleBadges(section, specs)
    RefreshBadgeAccentBorder()
    local entry = section and section._msuf2CollapsibleEntry
    local header = entry and entry.header
    if not header then return end
    entry._msuf2Badges = entry._msuf2Badges or {}
    specs = specs or {}
    local showAllWhenClosed = section._msuf2CollapsibleBadgesShowWhenClosed == true
        or entry._msuf2CollapsibleBadgesShowWhenClosed == true
        or section._msuf2CollapsibleBadgesOnlyWhenOpen == false
        or entry._msuf2CollapsibleBadgesOnlyWhenOpen == false
    local badgesOpen = entry.open == true and entry._msuf2Closing ~= true
    for i = 1, #specs do
        local spec = specs[i] or {}
        local badge = entry._msuf2Badges[i]
        if not badge then
            badge = CreateFrame("Frame", nil, header)
            badge:SetSize(54, 20)
            badge:SetFrameLevel((header.GetFrameLevel and header:GetFrameLevel() or 1) + 2)
            local fill, edge = T.CreateSuperellipseLayers(badge, "_msuf2HeaderBadge", 1, "ARTWORK", "OVERLAY")
            badge._msuf2Fill = fill
            badge._msuf2Edge = edge
            badge.text = T.Font(badge, "GameFontDisableSmall", "", T.colors.text)
            badge.text:SetPoint("CENTER", badge, "CENTER", 0, 0)
            badge.text:SetJustifyH("CENTER")
            entry._msuf2Badges[i] = badge
        end
        local text = Tr(spec.text or "")
        local style = COLLAPSIBLE_BADGE_STYLES[spec.kind or spec.style or "info"] or COLLAPSIBLE_BADGE_STYLES.info
        badge:SetSize(tonumber(spec.width) or CollapsibleBadgeWidth(text), tonumber(spec.height) or 20)
        if badge.text then
            badge.text:SetText(text)
            local c = style.text
            badge.text:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        end
        if badge._msuf2Fill then
            local c = style.bg
            if T.SetFillGradient then
                T.SetFillGradient(badge._msuf2Fill, c, 0.12, -0.18)
            else
                badge._msuf2Fill:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
            end
        end
        if badge._msuf2Edge then
            local c = style.border
            badge._msuf2Edge:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
        end
        local shown = text ~= ""
        if shown then
            local allowCollapsed = showAllWhenClosed
                or spec.showWhenClosed == true
                or spec.showCollapsed == true
                or spec.important == true
                or spec.alwaysShow == true
            if not badgesOpen and not allowCollapsed then shown = false end
            if spec.onlyWhenOpen == true and not badgesOpen then shown = false end
        end
        badge._msuf2BadgeWantedShown = shown and true or false
        if badge.text and badge.text.SetWidth then badge.text:SetWidth(max(20, (badge.GetWidth and badge:GetWidth() or 54) - 10)) end
        if badge.text and badge.text.SetMaxLines then badge.text:SetMaxLines(1) end
        if badge.text and badge.text.SetWordWrap then badge.text:SetWordWrap(false) end
        badge:SetShown(shown)
    end
    for i = #specs + 1, #entry._msuf2Badges do
        local badge = entry._msuf2Badges[i]
        if badge then
            badge._msuf2BadgeWantedShown = false
            badge:SetShown(false)
        end
    end
    if entry._msuf2RefreshLayout then entry._msuf2RefreshLayout() end
end

-- A deliberately quiet, card-local entry point for related colors. Target
-- resolution and virtual picker owners are both click-only: constructing or
-- idling Menu2 adds no refresh loop, event, timer, or gameplay work.
local CONTEXT_COLOR_SHORTCUT_TEXT = "|cffff625f•|r|cff61d683•|r|cff5aa7ff•|r"
local THREE_DOT_SHORTCUT_TEXTURE = (T.media and T.media.switchKnob)
    or ("Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\msuf_switch_knob.tga")
local COLOR_SHORTCUT_DOTS = {
    { 1.000, 0.384, 0.373 },
    { 0.380, 0.839, 0.514 },
    { 0.353, 0.655, 1.000 },
}
local LAYER_SHORTCUT_DOTS = {
    { 1, 1, 1 },
    { 1, 1, 1 },
    { 1, 1, 1 },
}

local function AddThreeDotShortcutTextures(shortcut, colors)
    if not (shortcut and shortcut.CreateTexture and type(colors) == "table") then return end
    if shortcut._msuf2Label and shortcut._msuf2Label.Hide then
        shortcut._msuf2Label:Hide()
        -- The dots are textures from here on; the button's own bullet label is
        -- decoration that must never come back. SetControlShown re-shows
        -- _msuf2Label for ordinary controls, which would paint the coloured
        -- bullets on top of - and offset from - the textures.
        shortcut._msuf2Label._msuf2AlwaysHidden = true
    end
    local dots = {}
    for i = 1, 3 do
        local color = colors[i] or LAYER_SHORTCUT_DOTS[i]
        local dot = shortcut:CreateTexture(nil, "ARTWORK", nil, 4)
        dot:SetTexture(THREE_DOT_SHORTCUT_TEXTURE)
        dot:SetSize(5, 5)
        dot:SetPoint("CENTER", shortcut, "CENTER", (i - 2) * 7, 0)
        dot:SetVertexColor(color[1], color[2], color[3], 1)
        dots[i] = dot
    end
    shortcut._msuf2ThreeDotTextures = dots
end

local function ResolveContextColorOption(value, fallback)
    if type(value) == "function" then value = value() end
    if value == nil or value == "" then return fallback end
    return value
end

local function ContextColorShortcutContext(card)
    local parent = card
    for _ = 1, 12 do
        if not parent then break end
        local entry = parent._msuf2CollapsibleEntry
        if entry and entry.builder and entry.builder.ctx then return entry.builder.ctx end
        parent = parent.GetParent and parent:GetParent()
    end
    return nil
end

local function TrackContextColorShortcutVisibility(card, shortcut)
    if not (card and shortcut) or shortcut._msuf2ContextColorVisibilityTracked == true then return end
    local refresh = function()
        if shortcut and shortcut._msuf2RefreshContextColorVisibility then shortcut:_msuf2RefreshContextColorVisibility() end
    end
    local ctx = ContextColorShortcutContext(card)
    if ctx and type(M.TrackRefresh) == "function" then
        shortcut._msuf2ContextColorVisibilityTracked = true
        local deferred = ctx._msuf2Building == true
            or (ctx.entry and ctx.entry._msuf2Building == true)
            or ctx.hiddenBuild == true
            or (ctx.entry and ctx.entry.hiddenBuild == true)
        M.TrackRefresh(ctx, refresh)
        if deferred then refresh() end
    else
        refresh()
    end
end

local function ContextColorVirtualOwner(spec, opts)
    if type(spec) ~= "table" then return nil end
    if type(spec.GetRGB) == "function" and type(spec.SetRGB) == "function" then return spec end
    local getRGB = spec.getRGB or spec.get
    local setRGB = spec.setRGB or spec.set
    if type(getRGB) ~= "function" or type(setRGB) ~= "function" then return nil end

    local owner = {
        _msuf2ColorLabel = spec.label or "Color",
        _msuf2ColorHasOpacity = spec.hasOpacity == true,
    }
    function owner:GetRGB()
        local r, g, b = getRGB()
        return tonumber(r) or tonumber(spec.defaultR) or 1,
            tonumber(g) or tonumber(spec.defaultG) or 1,
            tonumber(b) or tonumber(spec.defaultB) or 1
    end
    function owner:SetRGB(r, g, b)
        self._msuf2R, self._msuf2G, self._msuf2B = tonumber(r) or 1, tonumber(g) or 1, tonumber(b) or 1
    end
    function owner:IsEnabled()
        return type(spec.isEnabled) ~= "function" or spec.isEnabled() ~= false
    end
    owner._msuf2OnColorChanged = function(r, g, b, alpha)
        if M.BlockCombatAction and M.BlockCombatAction() then return end
        setRGB(r, g, b, alpha)
    end
    if spec.hasOpacity == true and type(spec.getOpacity) == "function" then
        owner._msuf2GetColorOpacity = function() return spec.getOpacity() end
    end
    if type(spec.captureState) == "function" and type(spec.restoreState) == "function" then
        owner._msuf2CaptureColorState = function() return spec.captureState() end
        owner._msuf2RestoreColorState = function(_, state) spec.restoreState(state) end
    end
    function owner:_msuf2BeginColorInteraction()
        if type(M.BeginHistoryTransaction) ~= "function" then return end
        local label = spec.historyLabel or opts.historyLabel or ((spec.label or "Color") .. " color")
        local source = opts.historySource or "menu:context-color-shortcut"
        self._msuf2ContextColorHistoryActive = M.BeginHistoryTransaction(label, source) == true
    end
    function owner:_msuf2CommitColorInteraction()
        if not self._msuf2ContextColorHistoryActive then return end
        self._msuf2ContextColorHistoryActive = nil
        if type(M.CommitHistoryTransaction) == "function" then M.CommitHistoryTransaction() end
    end
    return owner
end

function W.OpenContextColors(card, opts, resolvedTargets, onFinish)
    opts = opts or {}
    local targets = resolvedTargets or ResolveContextColorOption(opts.getTargets or opts.targets, {})
    if type(targets) ~= "table" then return false end
    local owners, maxTargets = {}, math.max(1, tonumber(opts.maxTargets) or 4)
    -- Never hide a setting silently. Curated contextual mappings stay at four
    -- unless the card's subject genuinely is a list -- group resource colors
    -- are one per power type -- in which case it states its own bound. An
    -- oversized mapping that never asked for the room must be fixed at its
    -- source instead of opening an incomplete picker.
    if #targets > maxTargets then return false end
    for i = 1, #targets do
        local owner = ContextColorVirtualOwner(targets[i], opts)
        if owner and (owner._msuf2ContextColorAllowDisabled == true
            or not owner.IsEnabled or owner:IsEnabled())
        then
            owners[#owners + 1] = owner
        end
    end
    if #owners == 0 or type(W.OpenColorContextPicker) ~= "function" then return false end
    local fallbackTitle = card and card._msuf2ControlCardTitle or "Colors"
    local title = ResolveContextColorOption(opts.title, fallbackTitle)
    local note = ResolveContextColorOption(opts.note, nil)
    local scopeTag = ResolveContextColorOption(opts.scopeTag, nil)
    W.OpenColorContextPicker(title, owners, note, owners[1], onFinish, scopeTag)
    return true
end

local function ContextColorShortcutsSuppressed(card)
    local frame = card
    for _ = 1, 16 do
        if not frame then break end
        if frame._msuf2SuppressContextColorShortcuts == true then return true end
        frame = frame.GetParent and frame:GetParent()
    end
    return false
end

function W.AttachContextColorShortcut(card, opts)
    if not card then return nil end
    -- The canonical Colors page already exposes the color controls directly.
    -- Its contextual shortcut would only reopen the same picker and add noise.
    if ContextColorShortcutsSuppressed(card) then return nil end
    opts = opts or {}
    if card._msuf2ContextColorShortcut then
        local existing = card._msuf2ContextColorShortcut
        existing._msuf2ContextColorOptions = opts
        if opts.isRelevant ~= nil then TrackContextColorShortcutVisibility(card, existing) end
        if existing._msuf2RefreshContextColorVisibility then existing:_msuf2RefreshContextColorVisibility() end
        return existing
    end

    local shortcut = T.Button(card, CONTEXT_COLOR_SHORTCUT_TEXT, 34, 20, { noSearch = true })
    shortcut._msuf2SkipHistoryCheckpoint = true
    shortcut._msuf2ContextColorOptions = opts
    shortcut:ClearAllPoints()
    shortcut:SetPoint("TOPRIGHT", card, "TOPRIGHT", tonumber(opts.offsetX) or -12, tonumber(opts.offsetY) or -10)
    shortcut:SetFrameLevel((card.GetFrameLevel and card:GetFrameLevel() or 1) + 3)
    shortcut:SetAlpha(0.58)
    AddThreeDotShortcutTextures(shortcut, COLOR_SHORTCUT_DOTS)
    shortcut:HookScript("OnEnter", function(self) self:SetAlpha(0.96) end)
    shortcut:HookScript("OnLeave", function(self) self:SetAlpha(0.58) end)
    function shortcut:_msuf2RefreshContextColorVisibility()
        local options = self._msuf2ContextColorOptions or {}
        local relevant = ResolveContextColorOption(options.isRelevant, true) ~= false
        if self.SetShown then self:SetShown(relevant)
        elseif relevant and self.Show then self:Show()
        elseif not relevant and self.Hide then self:Hide() end
        return relevant
    end
    shortcut:SetScript("OnClick", function(self)
        if M.BlockCombatAction and M.BlockCombatAction() then return end
        if self._msuf2RefreshContextColorVisibility and not self:_msuf2RefreshContextColorVisibility() then return end
        local options = self._msuf2ContextColorOptions or {}
        if options.textSettings and type(W.OpenTextQuickSettings) == "function" then
            W.OpenTextQuickSettings(self, options)
            return
        end
        W.OpenContextColors(card, options)
    end)
    if M.AddTooltip then
        local tooltipTitle = opts.tooltipTitle or (opts.textSettings and "Text quick settings" or "Colors")
        local tooltipText = opts.tooltipText
            or (opts.textSettings and "Open the fonts and colors used in this area." or "Open the colors used in this area.")
        M.AddTooltip(shortcut, tooltipTitle, tooltipText, { hook = true })
    end
    if card.title and card.title.SetWidth then
        card.title:SetWidth(max(24, (tonumber(card._msuf2Width) or 360) - 70))
    end
    card._msuf2ContextColorShortcut = shortcut
    if opts.isRelevant ~= nil then TrackContextColorShortcutVisibility(card, shortcut) end
    return shortcut
end

-- Cross-page color references stay declarative at their feature card.  The
-- canonical resolver lives with Advanced Colors and is deliberately invoked
-- only by the shortcut click, so unopened popups and normal gameplay never
-- pay for target construction or color reads.
function W.AttachContextColorReferences(card, references, opts)
    if not card then return nil end
    opts = opts or {}
    local options = {}
    for key, value in pairs(opts) do options[key] = value end
    if options.isRelevant == nil then
        options.isRelevant = function()
            local resolvedReferences = ResolveContextColorOption(options.references or references, {})
            local count = type(resolvedReferences) == "table" and #resolvedReferences or 0
            local maxTargets = math.max(1, tonumber(options.maxTargets) or 4)
            return count > 0 and count <= maxTargets
        end
    end
    options.getTargets = function()
        local resolver = M.ResolveContextColorReferences
        if type(resolver) ~= "function" then return {} end
        local resolvedReferences = ResolveContextColorOption(options.references or references, {})
        local resolvedContext = ResolveContextColorOption(options.context, {})
        return resolver(resolvedReferences, resolvedContext)
    end
    options.references = nil
    local shortcut = W.AttachContextColorShortcut(card, options)
    -- An explicit semantic mapping owns this card. A later generic BindColor
    -- must not replace its curated 1-4 target set merely because controls are
    -- laid out after the card shortcut was attached.
    if shortcut then shortcut._msuf2BoundColorShortcut = nil end
    return shortcut
end

local function PositionedContextColorCard(parent, x, y)
    local cards = parent and parent._msuf2ControlCards
    x, y = tonumber(x), tonumber(y)
    if type(cards) ~= "table" or x == nil or y == nil then return nil end
    local best, bestArea
    for i = 1, #cards do
        local card = cards[i]
        local left = tonumber(card and card._msuf2ContextColorLeft)
        local top = tonumber(card and card._msuf2ContextColorTop)
        local width = tonumber(card and card._msuf2ContextColorWidth)
        local height = tonumber(card and card._msuf2ContextColorHeight)
        if left and top and width and height
            and x >= left and x <= left + width
            and y <= top and y >= top - height
        then
            local area = width * height
            if not bestArea or area < bestArea then best, bestArea = card, area end
        end
    end
    return best
end

local function AttachBoundColorToContextCard(colorControl)
    local card = colorControl and colorControl._msuf2ContextColorCardOverride
    local parent = colorControl and colorControl.GetParent and colorControl:GetParent()
    local nearestHost
    if not card then
        for _ = 1, 12 do
            if not parent then break end
            if parent._msuf2ControlCard then card = parent; break end
            if not nearestHost and parent._msuf2ContextColorHost then nearestHost = parent end
            parent = parent.GetParent and parent:GetParent()
        end
    end
    if not card then
        local layoutParent = colorControl and colorControl._msuf2ContextLayoutParent
        card = PositionedContextColorCard(layoutParent,
            colorControl and colorControl._msuf2ContextLayoutX,
            colorControl and colorControl._msuf2ContextLayoutY)
    end
    -- Cards with sibling controls are resolved after W.MoveWidget records the
    -- final position. Until then, do not attach the color to the outer body.
    if not card and nearestHost and type(nearestHost._msuf2ControlCards) == "table"
        and #nearestHost._msuf2ControlCards > 0
        and not (colorControl and colorControl._msuf2ContextLayoutParent)
    then
        return false
    end
    card = card or nearestHost
    if not card then return false end
    local existingShortcut = card._msuf2ContextColorShortcut
    if existingShortcut and existingShortcut._msuf2BoundColorShortcut ~= true then return false end
    card._msuf2ContextColorOwners = card._msuf2ContextColorOwners or {}
    card._msuf2ContextColorOwnerKeys = card._msuf2ContextColorOwnerKeys or {}
    local command = colorControl._msuf2CommandAction
    local settingKey = command and tostring(command.settingKey or "") or ""
    local identity = settingKey ~= "" and ("setting:" .. settingKey) or colorControl
    if not card._msuf2ContextColorOwnerKeys[identity] then
        card._msuf2ContextColorOwnerKeys[identity] = true
        card._msuf2ContextColorOwners[#card._msuf2ContextColorOwners + 1] = colorControl
    end
    if #card._msuf2ContextColorOwners > 4 then
        card._msuf2ContextColorOverflow = true
        if existingShortcut and existingShortcut.Hide then existingShortcut:Hide() end
        return true
    end
    local shortcut = W.AttachContextColorShortcut(card, {
        title = function()
            return card._msuf2ControlCardTitle or card._msuf2ContextColorHostTitle or "Colors"
        end,
        getTargets = function() return card._msuf2ContextColorOwners end,
        isRelevant = function()
            local owners = card._msuf2ContextColorOwners or {}
            if card._msuf2ContextColorOverflow == true or #owners == 0 or #owners > 4 then return false end
            for i = 1, #owners do
                local owner = owners[i]
                if owner and (owner._msuf2ContextColorAllowDisabled == true
                    or not owner.IsEnabled or owner:IsEnabled())
                then
                    return true
                end
            end
            return false
        end,
        historySource = "menu:card-colors",
        maxTargets = 4,
    })
    if shortcut then
        shortcut._msuf2BoundColorShortcut = true
        if colorControl.HookScript and not colorControl._msuf2ContextShortcutEnableHooks then
            colorControl._msuf2ContextShortcutEnableHooks = true
            colorControl:HookScript("OnEnable", function()
                if shortcut._msuf2RefreshContextColorVisibility then shortcut:_msuf2RefreshContextColorVisibility() end
            end)
            colorControl:HookScript("OnDisable", function()
                if shortcut._msuf2RefreshContextColorVisibility then shortcut:_msuf2RefreshContextColorVisibility() end
            end)
        end
    end
    return true
end

--- Mirrors existing bound color controls into compact, clickable accordion-header
--- swatches. The header buttons proxy the original control, so color history,
--- picker behavior, setting metadata, and runtime apply paths stay single-sourced.
function W.SetCollapsibleColorSwatches(ctx, section, specs)
    local entry = section and section._msuf2CollapsibleEntry
    local header = entry and entry.header
    if not header then return end
    specs = specs or {}
    entry._msuf2ColorSwatches = entry._msuf2ColorSwatches or {}
    local count = #specs
    local measuredW = header.GetWidth and header:GetWidth()
    local headerW = (tonumber(measuredW) or 0) > 0 and measuredW or (entry.builder and entry.builder.width) or 720
    local baseWidth = count > 12 and 16 or (count > 8 and 20 or (count > 5 and 24 or 32))
    local gap = count > 8 and 3 or 5
    local maxReserve = max(80, headerW - 220)
    local visibleLimit = max(1, floor((maxReserve + gap) / (baseWidth + gap)))
    local renderCount = min(count, visibleLimit)
    local right = -12
    local visibleCount = 0
    for i = 1, renderCount do
        local spec = specs[i] or {}
        local control = spec.control or spec[1]
        local swatch = entry._msuf2ColorSwatches[i]
        if not swatch then
            swatch = CreateFrame("Button", nil, header)
            swatch:SetSize(32, 18)
            swatch:SetFrameLevel((header.GetFrameLevel and header:GetFrameLevel() or 1) + 3)
            swatch._msuf2Fill, swatch._msuf2Edge = T.CreateSuperellipseLayers(swatch, "_msuf2HeaderColor", 1, "ARTWORK", "OVERLAY")
            local hover = swatch:CreateTexture(nil, "HIGHLIGHT")
            hover:SetAllPoints()
            hover:SetColorTexture(1, 1, 1, 0.10)
            entry._msuf2ColorSwatches[i] = swatch
        end
        swatch._msuf2ColorControl = control
        swatch._msuf2ColorPreviewAvailable = control and true or false
        swatch:SetSize(tonumber(spec.width) or baseWidth, tonumber(spec.height) or (baseWidth < 24 and 14 or 18))
        swatch:ClearAllPoints()
        swatch:SetPoint("RIGHT", header, "RIGHT", right, 0)
        right = right - swatch:GetWidth() - gap
        visibleCount = visibleCount + 1
        if M.MarkRuntimeControlComponent and control then
            M.MarkRuntimeControlComponent(swatch, control)
        elseif control then
            swatch._msuf2ControlPartOf = control
        end
        local function RefreshSwatch(r, g, b)
            if not control then swatch:Hide(); return end
            if type(r) ~= "number" then r, g, b = nil, nil, nil end
            if r == nil and control.GetRGB then r, g, b = control:GetRGB() end
            r, g, b = tonumber(r) or 1, tonumber(g) or 1, tonumber(b) or 1
            if swatch._msuf2Fill.SetColorTexture then swatch._msuf2Fill:SetColorTexture(r, g, b, 1)
            else swatch._msuf2Fill:SetVertexColor(r, g, b, 1) end
            local enabled = not control.IsEnabled or control:IsEnabled()
            if enabled then swatch:Enable() else swatch:Disable() end
            -- A header swatch previews the stored color, even while its setting is
            -- conditionally inactive. Dimming the whole button falsifies that color.
            swatch:SetAlpha(1)
            swatch._msuf2Edge:SetVertexColor(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], enabled and 0.90 or 0.48)
            swatch:SetShown(entry.open ~= true and swatch._msuf2ColorPreviewAvailable == true)
        end
        swatch._msuf2RefreshColor = RefreshSwatch
        swatch:SetScript("OnClick", function(self)
            local target = self._msuf2ColorControl
            if not target or (target.IsEnabled and not target:IsEnabled()) then return end
            if target.Click then target:Click("LeftButton")
            else
                local click = target.GetScript and target:GetScript("OnClick")
                if type(click) == "function" then click(target, "LeftButton") end
            end
        end)
        if M.AddTooltip and not swatch._msuf2ColorTooltipInstalled then
            swatch._msuf2ColorTooltipInstalled = true
            M.AddTooltip(swatch, spec.label or spec.text or "Color", spec.help or "Click to edit this color.", { hook = true })
        end
        if control and swatch._msuf2MirrorControl ~= control then
            swatch._msuf2MirrorControl = control
            control._msuf2ColorMirrors = control._msuf2ColorMirrors or {}
            control._msuf2ColorMirrors[#control._msuf2ColorMirrors + 1] = RefreshSwatch
            if control.HookScript then
                control:HookScript("OnEnable", RefreshSwatch)
                control:HookScript("OnDisable", RefreshSwatch)
            end
        end
        RefreshSwatch()
    end
    for i = renderCount + 1, #entry._msuf2ColorSwatches do
        local swatch = entry._msuf2ColorSwatches[i]
        swatch._msuf2ColorPreviewAvailable = false
        swatch:Hide()
    end
    entry._msuf2ClosedColorSwatchReserve = visibleCount > 0 and math.abs(right + 12) or 0
    entry._msuf2RefreshColorSwatchVisibility = function()
        local showPreviews = entry.open ~= true
        entry._msuf2ColorSwatchReserve = showPreviews and entry._msuf2ClosedColorSwatchReserve or 0
        for i = 1, #(entry._msuf2ColorSwatches or {}) do
            local swatch = entry._msuf2ColorSwatches[i]
            if swatch then
                swatch:SetShown(showPreviews and swatch._msuf2ColorPreviewAvailable == true)
            end
        end
        if entry._msuf2RefreshLayout then entry._msuf2RefreshLayout() end
    end
    if M.TrackRefresh and not entry._msuf2ColorSwatchRefreshTracked then
        entry._msuf2ColorSwatchRefreshTracked = true
        M.TrackRefresh(ctx, function()
            for i = 1, #(entry._msuf2ColorSwatches or {}) do
                local swatch = entry._msuf2ColorSwatches[i]
                if swatch and swatch._msuf2ColorPreviewAvailable and swatch._msuf2RefreshColor then swatch._msuf2RefreshColor() end
            end
        end)
    end
    entry._msuf2RefreshColorSwatchVisibility()
end

--- Register every bound color for its nearest visible content surface and for
--- picker grouping. Accordion headers intentionally stay clean: the only
--- automatic entry point is the quiet RGB shortcut inside the opened card.
--- This is cold Menu2 construction only; it adds no gameplay/combat work.
function W.AttachBoundColorToCollapsible(ctx, colorControl)
    if not colorControl then return false end
    colorControl._msuf2ContextColorBound = true
    local contextAttached = AttachBoundColorToContextCard(colorControl)
    if colorControl._msuf2CollapsibleColorContextAttached then return contextAttached end
    local parent = colorControl.GetParent and colorControl:GetParent()
    local section, entry
    for _ = 1, 12 do
        if not parent then break end
        entry = parent._msuf2CollapsibleEntry
        if entry then section = entry.body or parent; break end
        parent = parent.GetParent and parent:GetParent()
    end
    if not (section and entry) then return contextAttached end
    colorControl._msuf2CollapsibleColorContextAttached = true
    local contextEntry = entry
    while contextEntry.ancestorEntry do contextEntry = contextEntry.ancestorEntry end
    contextEntry._msuf2ColorContextOwners = contextEntry._msuf2ColorContextOwners or {}
    contextEntry._msuf2ColorContextOwners[#contextEntry._msuf2ColorContextOwners + 1] = colorControl
    colorControl._msuf2ColorContextOwners = contextEntry._msuf2ColorContextOwners
    AttachBoundColorToContextCard(colorControl)
    return true
end
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
local function PlayWidgetMotion(region, motion, opts)
    if T.PlayMotion then
        T.PlayMotion(region, motion, opts)
        return
    end
    opts = opts or {}
    if region and region.SetAlpha then region:SetAlpha(opts.toAlpha or 0) end
end
local function ClickCheckButton(button, mouseButton)
    if not button then return end
    if button.IsEnabled and not button:IsEnabled() then return end
    local nextValue
    if button.SetChecked and button.GetChecked then
        nextValue = not (button:GetChecked() and true or false)
        button:SetChecked(nextValue)
    end
    local click = button.GetScript and button:GetScript("OnClick")
    if type(click) == "function" then click(button, mouseButton or "LeftButton", false) end
    if button._msuf2RefreshToggleFeedback then button:_msuf2RefreshToggleFeedback(button._msuf2ToggleHovered, button._msuf2TogglePressed) end
    if button._msuf2RefreshSwitchVisual then button:_msuf2RefreshSwitchVisual(button._msuf2SwitchHovered) end
    return nextValue
end
local function GetCheckTexture(button, getter, suffix)
    local check = button and button[getter] and button[getter](button)
    if (not check) and button and suffix and button.GetName and button:GetName() then check = _G[button:GetName() .. suffix] end
    return check
end
local function SyncCheckedTexture(button, checked, enabled, alpha)
    local check = GetCheckTexture(button, "GetCheckedTexture", "Check")
    local disabledCheck = GetCheckTexture(button, "GetDisabledCheckedTexture", "DisabledCheck")
    if not (check or disabledCheck) then return end
    checked = checked and true or false
    alpha = alpha or (enabled and 0.96 or 0.42)
    local function apply(texture)
        if not texture then return end
        if texture.SetVertexColor then texture:SetVertexColor(1, 1, 1, checked and alpha or 0) end
        if texture.SetAlpha then texture:SetAlpha(checked and alpha or 0) end
        if checked then
            if texture.Show then texture:Show() end
        elseif texture.Hide then
            texture:Hide()
        end
    end
    apply(check)
    apply(disabledCheck)
end
local function UpdateToggleProxyBounds(button)
    if not button then return end
    local label = button._msuf2Label
    local textWidth = 0
    if label and label.GetStringWidth then textWidth = tonumber(label:GetStringWidth()) or 0 end
    if textWidth <= 0 and label and label.GetText then
        local text = tostring(label:GetText() or "")
        textWidth = #text * 7
    end
    local labelWidth = label and label.GetWidth and tonumber(label:GetWidth()) or nil
    if labelWidth and labelWidth > 0 then textWidth = textWidth > 0 and min(textWidth, labelWidth) or labelWidth end
    textWidth = max(0, textWidth)
    local baseWidth = tonumber(button._msuf2ProxyBaseWidth) or 40
    local hitWidth = max(36, floor(baseWidth + textWidth + 0.5))
    local rowHover = button._msuf2ToggleRowHover
    if rowHover then
        rowHover:ClearAllPoints()
        rowHover:SetPoint("LEFT", button, "LEFT", -4, 0)
        rowHover:SetSize(hitWidth, 28)
        if rowHover.SetTexCoord then rowHover:SetTexCoord(0, 1, 0, 1) end
    end
    local labelHit = button._msuf2LabelHit
    if labelHit then
        labelHit:ClearAllPoints()
        labelHit:SetPoint("LEFT", button, "LEFT", -4, 0)
        labelHit:SetSize(hitWidth, 28)
    end
end
local function UseControlTexture(tex, texture)
    if not tex then return tex end
    tex:SetTexture(texture)
    tex:SetTexCoord(0, 1, 0, 1)
    if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
    if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
    return tex
end
local function ControlTexture(parent, key, layer, subLevel, texture)
    local tex = UseControlTexture(parent:CreateTexture(nil, layer, nil, subLevel), texture)
    if key then parent[key] = tex end
    return tex
end
local function HideNativeCheckTexture(texture)
    if not texture then return end
    if texture.SetAlpha then texture:SetAlpha(0) end
    if texture.Hide then texture:Hide() end
end
local NATIVE_CHECK_TEXTURE_GETTERS = { "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }
local function SuppressNativeCheckChrome(self)
    for i = 1, #NATIVE_CHECK_TEXTURE_GETTERS do
        local getter = NATIVE_CHECK_TEXTURE_GETTERS[i]
        HideNativeCheckTexture(self[getter] and self[getter](self))
    end
end
local function ApplyControlCardChrome(card)
    if not (card and card.CreateTexture) or card._msuf2ControlCardChrome then return end
    card._msuf2ControlCardChrome = true
    local top = card:CreateTexture(nil, "ARTWORK", nil, 4)
    top:SetTexture("Interface\\Buttons\\WHITE8X8")
    top:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -2)
    top:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -2)
    top:SetHeight(1)
    top:SetColorTexture(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.050)
    card._msuf2CardTopLine = top
    local depth = card:CreateTexture(nil, "BORDER", nil, 4)
    depth:SetTexture("Interface\\Buttons\\WHITE8X8")
    depth:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 8, 2)
    depth:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -8, 2)
    depth:SetHeight(1)
    depth:SetColorTexture(0, 0, 0, 0.14)
    card._msuf2CardDepthLine = depth
end

--- Toggle visuals are custom-built to avoid Blizzard template art leaking into
--- Menu2 styling. State changes are still driven by CheckButton semantics.
local function RefreshToggleControl(button, hover, down)
    local refresh = button and button._msuf2RefreshToggleFeedback
    if refresh then refresh(button, hover, down) end
end
local TOGGLE_CONTROL_HOOKS = {
    OnShow = function(self)
        if T.StyleCheckmark then T.StyleCheckmark(self) end
        if self._msuf2SuppressNativeCheckChrome then self:_msuf2SuppressNativeCheckChrome() end
        if self._msuf2UpdateToggleProxyBounds then self:_msuf2UpdateToggleProxyBounds() end
        RefreshToggleControl(self)
    end,
    OnEnter = function(self) self._msuf2ToggleHovered = true; RefreshToggleControl(self, true, self._msuf2TogglePressed) end,
    OnLeave = function(self) self._msuf2ToggleHovered = nil; self._msuf2TogglePressed = nil; RefreshToggleControl(self) end,
    OnMouseDown = function(self) self._msuf2TogglePressed = true; RefreshToggleControl(self, self._msuf2ToggleHovered, true) end,
    OnMouseUp = function(self) self._msuf2TogglePressed = nil; RefreshToggleControl(self, self._msuf2ToggleHovered) end,
    OnClick = function(self) RefreshToggleControl(self, self._msuf2ToggleHovered) end,
    OnEnable = function(self) RefreshToggleControl(self, self._msuf2ToggleHovered) end,
    OnDisable = function(self) RefreshToggleControl(self) end,
}
local function LabelOwner(self, key, requireEnabled)
    local btn = self and self[key]
    return (btn and not (requireEnabled and btn.IsEnabled and not btn:IsEnabled())) and btn or nil
end
local TOGGLE_LABEL_HOOKS = {
    OnClick = function(self)
        local btn = LabelOwner(self, "_msuf2ToggleOwner", true)
        if not btn then return end
        ClickCheckButton(btn, "LeftButton")
        RefreshToggleControl(btn, true)
    end,
    OnEnter = function(self)
        local btn = LabelOwner(self, "_msuf2ToggleOwner")
        if not btn then return end
        btn._msuf2ToggleHovered = true
        RefreshToggleControl(btn, true)
    end,
    OnMouseDown = function(self)
        local btn = LabelOwner(self, "_msuf2ToggleOwner", true)
        if not btn then return end
        btn._msuf2TogglePressed = true
        RefreshToggleControl(btn, true, true)
    end,
    OnMouseUp = function(self)
        local btn = LabelOwner(self, "_msuf2ToggleOwner")
        if not btn then return end
        btn._msuf2TogglePressed = nil
        RefreshToggleControl(btn, btn._msuf2ToggleHovered)
    end,
    OnLeave = function(self)
        local btn = LabelOwner(self, "_msuf2ToggleOwner")
        if not btn then return end
        btn._msuf2ToggleHovered = nil
        btn._msuf2TogglePressed = nil
        RefreshToggleControl(btn)
    end,
}
local SWITCH_BG_ON = { 0.020, 0.090, 0.135, 0.96 }
local SWITCH_BG_OFF = { 0.014, 0.022, 0.048, 0.96 }
local SWITCH_EDGE_ON = { 0.160, 0.560, 0.760, 0.86 }
local SWITCH_EDGE_OFF = { 0.095, 0.145, 0.255, 0.82 }
local SWITCH_KNOB_ON = { 0.380, 0.760, 0.900, 1.00 }
local SWITCH_KNOB_OFF = { 0.680, 0.760, 0.940, 1.00 }
-- The literal ON family above is the tuned midnight-cyan look. With a custom
-- menu accent active, derive the ON family from the (already swapped) accent
-- token instead so switches follow the accent like every token-driven control.
local SWITCH_ACCENT_BG_ON = { 0, 0, 0, 0.96 }
local SWITCH_ACCENT_EDGE_ON = { 0, 0, 0, 0.86 }
local SWITCH_ACCENT_KNOB_ON = { 0, 0, 0, 1.00 }
local function SwitchOnColors()
    if not (T.MenuAccentActive and T.MenuAccentActive()) then
        return SWITCH_BG_ON, SWITCH_EDGE_ON, SWITCH_KNOB_ON
    end
    local a = T.colors.accent or SWITCH_EDGE_ON
    SWITCH_ACCENT_BG_ON[1], SWITCH_ACCENT_BG_ON[2], SWITCH_ACCENT_BG_ON[3] =
        a[1] * 0.16, a[2] * 0.16, a[3] * 0.16
    SWITCH_ACCENT_EDGE_ON[1], SWITCH_ACCENT_EDGE_ON[2], SWITCH_ACCENT_EDGE_ON[3] =
        a[1] * 0.78, a[2] * 0.78, a[3] * 0.78
    SWITCH_ACCENT_KNOB_ON[1], SWITCH_ACCENT_KNOB_ON[2], SWITCH_ACCENT_KNOB_ON[3] =
        min(a[1] + (1 - a[1]) * 0.35, 1), min(a[2] + (1 - a[2]) * 0.35, 1), min(a[3] + (1 - a[3]) * 0.35, 1)
    return SWITCH_ACCENT_BG_ON, SWITCH_ACCENT_EDGE_ON, SWITCH_ACCENT_KNOB_ON
end
local function PlaySwitchFeedback(button)
    if not (button and button._msuf2SwitchFlash) then return end
    local checked = button.GetChecked and button:GetChecked()
    local c = checked and T.colors.accent or (T.colors.borderSoft or T.colors.border)
    local alpha = checked and 0.28 or 0.18
    button._msuf2SwitchFlash:SetVertexColor(c[1], c[2], c[3], alpha)
    button._msuf2SwitchFlash:SetAlpha(alpha)
    PlayWidgetMotion(button._msuf2SwitchFlash, "controlFeedback", { fromAlpha = alpha, toAlpha = 0 })
end
local switchOffRehueChecked
local function RefreshSwitchVisual(button, hover)
    if not button then return end
    if not switchOffRehueChecked then
        switchOffRehueChecked = true
        if T.MenuAccentRehueLiteral then
            T.MenuAccentRehueLiteral(SWITCH_BG_OFF)
            T.MenuAccentRehueLiteral(SWITCH_EDGE_OFF)
            T.MenuAccentRehueLiteral(SWITCH_KNOB_OFF)
        end
    end
    hover = hover or button._msuf2SwitchHovered
    local pressed = button._msuf2SwitchPressed and true or false
    local checked = button.GetChecked and button:GetChecked()
    local enabled = not button.IsEnabled or button:IsEnabled()
    local onBg, onEdge, onKnob = SwitchOnColors()
    local bg = checked and onBg or SWITCH_BG_OFF
    local br = checked and onEdge or SWITCH_EDGE_OFF
    local kb = checked and onKnob or SWITCH_KNOB_OFF
    local mul = enabled and (pressed and 1.10 or hover and 1.08 or 1) or 1
    local alpha = enabled and 1 or 0.58
    if button._msuf2SwitchFill then button._msuf2SwitchFill:SetVertexColor(min(bg[1] * mul, 1), min(bg[2] * mul, 1), min(bg[3] * mul, 1), bg[4] * alpha) end
    if button._msuf2SwitchEdge then button._msuf2SwitchEdge:SetVertexColor(min(br[1] * mul, 1), min(br[2] * mul, 1), min(br[3] * mul, 1), br[4] * alpha) end
    local knob = button._msuf2SwitchKnob
    if knob then
        local size = button._msuf2SwitchKnobSize or 18
        local pad = button._msuf2SwitchKnobPad or 2
        knob:ClearAllPoints()
        UseControlTexture(knob, button._msuf2SwitchKnobTexture or "Interface\\Buttons\\WHITE8X8")
        knob:SetSize(size, size)
        knob:SetPoint(checked and "RIGHT" or "LEFT", button, checked and "RIGHT" or "LEFT", checked and -pad or pad, 0)
        knob:SetVertexColor(kb[1], kb[2], kb[3], kb[4] * alpha)
        if knob.SetAlpha then knob:SetAlpha(alpha) end
    end
    if button._msuf2Label and button._msuf2Label.SetTextColor then
        local tx = enabled and (hover and T.colors.title or T.colors.text) or (T.colors.disabled or T.colors.dim)
        button._msuf2Label:SetTextColor(tx[1], tx[2], tx[3], tx[4] or 1)
    end
end
local function SetSwitchChecked(button, value)
    local checked = value and true or false
    local before = button.GetChecked and button:GetChecked()
    if button._msuf2RawSetChecked then button._msuf2RawSetChecked(button, checked) end
    if before ~= checked then PlaySwitchFeedback(button) end
    RefreshSwitchVisual(button)
end
local SWITCH_CONTROL_HOOKS = {
    OnEnter = function(self) self._msuf2SwitchHovered = true; RefreshSwitchVisual(self, true) end,
    OnLeave = function(self) self._msuf2SwitchHovered = nil; self._msuf2SwitchPressed = nil; RefreshSwitchVisual(self) end,
    OnMouseDown = function(self) self._msuf2SwitchPressed = true; RefreshSwitchVisual(self) end,
    OnMouseUp = function(self) self._msuf2SwitchPressed = nil; RefreshSwitchVisual(self) end,
    OnClick = RefreshSwitchVisual,
    OnEnable = RefreshSwitchVisual,
    OnDisable = function(self) self._msuf2SwitchHovered = nil; self._msuf2SwitchPressed = nil; RefreshSwitchVisual(self) end,
}
local SWITCH_LABEL_HOOKS = {
    OnClick = function(self)
        local btn = LabelOwner(self, "_msuf2SwitchOwner", true)
        if not btn then return end
        ClickCheckButton(btn, "LeftButton")
    end,
    OnEnter = function(self)
        local btn = LabelOwner(self, "_msuf2SwitchOwner")
        if not btn then return end
        btn._msuf2SwitchHovered = true
        RefreshSwitchVisual(btn, true)
        if btn.LockHighlight then btn:LockHighlight() end
    end,
    OnMouseDown = function(self)
        local btn = LabelOwner(self, "_msuf2SwitchOwner", true)
        if not btn then return end
        btn._msuf2SwitchPressed = true
        RefreshSwitchVisual(btn, true)
    end,
    OnMouseUp = function(self)
        local btn = LabelOwner(self, "_msuf2SwitchOwner")
        if not btn then return end
        btn._msuf2SwitchPressed = nil
        RefreshSwitchVisual(btn, btn._msuf2SwitchHovered)
    end,
    OnLeave = function(self)
        local btn = LabelOwner(self, "_msuf2SwitchOwner")
        if not btn then return end
        btn._msuf2SwitchHovered = nil
        btn._msuf2SwitchPressed = nil
        RefreshSwitchVisual(btn)
        if btn.UnlockHighlight then btn:UnlockHighlight() end
    end,
}
local function CreateToggle(section, label, x, y, labelWidth)
    local btn = CreateFrame("CheckButton", nil, section, "UICheckButtonTemplate")
    btn._msuf2ControlKind = "toggle"
    btn._msuf2QuietCheckBox = true
    btn:SetPoint("TOPLEFT", x, y)
    btn:SetSize(28, 28)
    btn._msuf2Label = T.Font(section, "GameFontHighlightSmall", Tr(label or ""), T.colors.text, "control")
    SetSearchText(btn._msuf2Label, label)
    btn._msuf2Label:SetPoint("LEFT", btn, "RIGHT", 8, 0)
    btn._msuf2Label:SetJustifyH("LEFT")
    if not labelWidth and section and section._msuf2Width then labelWidth = max(40, (section._msuf2Width or 0) - (x or 0) - 50) end
    if labelWidth then btn._msuf2Label:SetWidth(labelWidth) end
    btn.text = btn._msuf2Label
    if T.StyleCheckmark then T.StyleCheckmark(btn) end
    btn._msuf2SuppressNativeCheckChrome = SuppressNativeCheckChrome
    btn:_msuf2SuppressNativeCheckChrome()
    local checkFillTexture = (T.media and T.media.checkBoxFill) or "Interface\\Buttons\\WHITE8X8"
    local checkEdgeTexture = (T.media and T.media.checkBoxEdge) or checkFillTexture
    local boxEdge = ControlTexture(btn, "_msuf2ToggleEdge", "BACKGROUND", -3, checkEdgeTexture)
    boxEdge:SetSize(23, 23)
    boxEdge:SetPoint("CENTER", btn, "CENTER", 0, 0)
    local boxFill = ControlTexture(btn, "_msuf2ToggleFill", "BACKGROUND", -2, checkFillTexture)
    boxFill:SetSize(21, 21)
    boxFill:SetPoint("CENTER", btn, "CENTER", 0, 0)
    local hoverFill = ControlTexture(btn, "_msuf2ToggleHoverFill", "BACKGROUND", -1, checkFillTexture)
    hoverFill:SetAllPoints(boxFill)
    hoverFill:SetVertexColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 1)
    hoverFill:SetAlpha(0)
    hoverFill:Show()
    local rowHover = section:CreateTexture(nil, "BORDER", nil, 1)
    rowHover:SetTexture((T.media and T.media.superellipse) or "Interface\\Buttons\\WHITE8X8")
    if rowHover.SetTexCoord then rowHover:SetTexCoord(0, 1, 0, 1) end
    rowHover:SetVertexColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 1)
    rowHover:SetAlpha(0)
    rowHover:Show()
    btn._msuf2ToggleRowHover = rowHover
    btn._msuf2UpdateToggleProxyBounds = UpdateToggleProxyBounds
    local function SetToggleHoverVisual(self, show, down)
        local tex = self._msuf2ToggleHoverFill
        local rowTex = self._msuf2ToggleRowHover
        if not tex and not rowTex then return end
        local enabled = not (self.IsEnabled and not self:IsEnabled())
        if not enabled then show = false end
        local target = show and (down and 0.160 or 0.110) or 0
        local rowTarget = show and (down and 0.075 or 0.050) or 0
        local c = T.colors.checkActiveEdge or T.colors.accent
        if tex then
            if tex.SetTexture then tex:SetTexture(checkFillTexture) end
            if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
            if tex.SetVertexColor then tex:SetVertexColor(c[1], c[2], c[3], 1) end
            tex:SetAlpha(target)
            if tex.Show then tex:Show() end
        end
        if rowTex then
            if rowTex.SetTexture then rowTex:SetTexture((T.media and T.media.superellipse) or "Interface\\Buttons\\WHITE8X8") end
            if rowTex.SetTexCoord then rowTex:SetTexCoord(0, 1, 0, 1) end
            if rowTex.SetVertexColor then rowTex:SetVertexColor(c[1], c[2], c[3], 1) end
            rowTex:SetAlpha(rowTarget)
            if rowTex.Show then rowTex:Show() end
        end
    end
    local function RefreshToggleFeedback(self, hover, down)
        hover = hover and true or false
        down = down and true or false
        local enabled = not (self.IsEnabled and not self:IsEnabled())
        local checked = (self.GetChecked and self:GetChecked()) and true or false
        local active = T.colors.checkActive or ThemeColor("coreSurface", { 0.014, 0.038, 0.072, 1.00 })
        local inactive = T.colors.checkInactive or ThemeColor("coreShadow", { 0.006, 0.016, 0.032, 1.00 })
        local bg = checked and active or inactive
        local br = checked
            and (T.colors.checkActiveEdge or { min(active[1] + 0.20, 1), min(active[2] + 0.31, 1), min(active[3] + 0.48, 1), 0.90 })
            or (T.colors.checkInactiveEdge or ThemeColor("coreRim", { 0.043, 0.096, 0.150, 1.00 }))
        local bgMul = enabled and (down and 1.14 or hover and 1.08 or 1) or 1
        local borderAlpha = enabled
            and (checked and (down and 1.00 or hover and 0.96 or 0.88) or (down and 0.90 or hover and 0.80 or 0.68))
            or 0.30
        local alpha = enabled and 1 or 0.58
        local tx = enabled and (hover and T.colors.title or T.colors.text) or (T.colors.disabled or T.colors.dim)
        local visualKey = tostring(enabled) .. "\030" .. tostring(checked) .. "\030" .. tostring(hover) .. "\030" .. tostring(down)
            .. "\030" .. tostring(bg[1]) .. "\030" .. tostring(bg[2]) .. "\030" .. tostring(bg[3]) .. "\030" .. tostring(bg[4])
            .. "\030" .. tostring(br[1]) .. "\030" .. tostring(br[2]) .. "\030" .. tostring(br[3]) .. "\030" .. tostring(br[4])
            .. "\030" .. tostring(tx and tx[1]) .. "\030" .. tostring(tx and tx[2]) .. "\030" .. tostring(tx and tx[3]) .. "\030" .. tostring(tx and tx[4])
        if self._msuf2ToggleVisualKey == visualKey then return end
        self._msuf2ToggleVisualKey = visualKey
        if self._msuf2ToggleFill then
            local bgAlpha = checked and 0.98 or (down and 0.92 or hover and 0.86 or 0.80)
            self._msuf2ToggleFill:SetVertexColor(min(bg[1] * bgMul, 1), min(bg[2] * bgMul, 1), min(bg[3] * bgMul, 1), bgAlpha * alpha)
        end
        if self._msuf2ToggleEdge then self._msuf2ToggleEdge:SetVertexColor(br[1], br[2], br[3], borderAlpha * alpha) end
        local check = self.GetCheckedTexture and self:GetCheckedTexture()
        if check and check.SetVertexColor then check:SetVertexColor(1.000, 1.000, 1.000, enabled and 0.96 or 0.42) end
        SyncCheckedTexture(self, checked, enabled)
        SetToggleHoverVisual(self, hover and enabled, down and enabled)
        if self._msuf2Label and self._msuf2Label.SetTextColor then
            local r, g, b, a = tx[1], tx[2], tx[3], tx[4] or 1
            self._msuf2Label._msuf2TextColorR, self._msuf2Label._msuf2TextColorG = r, g
            self._msuf2Label._msuf2TextColorB, self._msuf2Label._msuf2TextColorA = b, a
            self._msuf2Label:SetTextColor(r, g, b, a)
        end
    end
    btn._msuf2RefreshToggleFeedback = RefreshToggleFeedback
    local rawSetChecked = btn.SetChecked
    btn.SetChecked = function(self, value)
        rawSetChecked(self, value and true or false)
        SyncCheckedTexture(self, value, not (self.IsEnabled and not self:IsEnabled()))
        RefreshToggleFeedback(self, self._msuf2ToggleHovered, self._msuf2TogglePressed)
    end
    for script, handler in pairs(TOGGLE_CONTROL_HOOKS) do btn:HookScript(script, handler) end
    local labelHit = CreateFrame("Button", nil, section)
    labelHit:EnableMouse(true)
    if labelHit.RegisterForClicks then labelHit:RegisterForClicks("LeftButtonUp") end
    labelHit:SetFrameLevel(btn:GetFrameLevel() + 2)
    labelHit._msuf2ToggleOwner = btn
    for script, handler in pairs(TOGGLE_LABEL_HOOKS) do labelHit:SetScript(script, handler) end
    if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(labelHit, btn)
    else labelHit._msuf2ControlPartOf = btn end
    btn._msuf2LabelHit = labelHit
    btn._msuf2UseProxyMouse = true
    if btn.EnableMouse then btn:EnableMouse(false) end
    btn:SetChecked(false)
    SyncCheckedTexture(btn, false, true)
    UpdateToggleProxyBounds(btn)
    RegisterSearchObject(btn, label, "toggle", { anchor = btn._msuf2Label })
    return btn
end
function W.Text(parent, text, x, y, width, color)
    local fs = T.Font(parent, "GameFontHighlightSmall", Tr(text or ""), color or T.colors.muted, "supporting")
    SetSearchText(fs, text)
    RegisterSearchObject(fs, text, "text")
    fs:SetPoint("TOPLEFT", x or 0, y or 0)
    fs:SetWidth(width or 300)
    fs:SetJustifyH("LEFT")
    return fs
end
function W.ControlCard(parent, title, subtitle, x, y, width, height)
    if not parent then return nil end
    width = width or 360
    height = height or 120
    local cardBase = ThemeColor("coreShadow", { 0.006, 0.016, 0.032, 1.00 })
    local cardBg = { cardBase[1], cardBase[2], cardBase[3], 0.86 }
    local cardBorder = T.colors.cardBorder or T.colors.borderSoft
    local card = T.Panel(parent, nil, cardBg, cardBorder)
    T.ApplySurface(card, { bg = cardBg, border = cardBorder, glass = "card" })
    ApplyControlCardChrome(card)
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
    local heading = T.Font(card, "GameFontNormal", Tr(title or ""), T.colors.text, "card")
    SetSearchText(heading, title)
    heading:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -16)
    heading:SetWidth(max(24, width - 32))
    heading:SetJustifyH("LEFT")
    card.title = heading
    if subtitle and subtitle ~= "" then
        local sub = T.Font(card, "GameFontDisableSmall", Tr(subtitle), T.colors.muted)
        SetSearchText(sub, subtitle)
        sub:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -40)
        sub:SetWidth(max(24, width - 32))
        sub:SetJustifyH("LEFT")
        if sub.SetWordWrap then sub:SetWordWrap(true) end
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
    T.ApplySurface(card, { bg = cardBg, border = cardBorder, glass = "card" })
    ApplyControlCardChrome(card)
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
    if type(T.ApplySurface) == "function" then T.ApplySurface(well, "card") end
    if well.EnableMouse then well:EnableMouse(false) end
    local image = well:CreateTexture(nil, "ARTWORK", nil, 2)
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
function W.Toggle(section, label)
    local x, y = NextRow(section, 32)
    return CreateToggle(section, label, x, y)
end
function W.ToggleAt(section, label, x, y, labelWidth)
    return CreateToggle(section, label, x or 16, y or -40, labelWidth)
end
function W.SwitchAt(section, label, x, y, labelWidth, labelSide)
    local switchW, switchH = 36, 20
    local knobSize = 16
    local knobPad = 2
    local switchTrackTexture = (T.media and T.media.switchTrack) or (T.media and T.media.superellipse) or "Interface\\Buttons\\WHITE8X8"
    local switchKnobTexture = (T.media and T.media.switchKnob) or (T.media and T.media.sliderThumb) or (T.media and T.media.superellipse) or "Interface\\Buttons\\WHITE8X8"
    local btn = CreateFrame("CheckButton", nil, section)
    btn._msuf2ControlKind = "toggle"
    btn:SetPoint("TOPLEFT", x or 16, y or -40)
    btn:SetSize(switchW, switchH)
    if btn.RegisterForClicks then btn:RegisterForClicks("LeftButtonUp") end
    if btn.EnableMouse then btn:EnableMouse(true) end
    if btn.SetHitRectInsets then btn:SetHitRectInsets(-2, -2, -3, -3) end
    local edge = ControlTexture(btn, "_msuf2SwitchEdge", "BACKGROUND", 0, switchTrackTexture)
    edge:SetAllPoints(btn)
    local fill = ControlTexture(btn, "_msuf2SwitchFill", "BACKGROUND", 1, switchTrackTexture)
    fill:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    local flash = ControlTexture(btn, "_msuf2SwitchFlash", "ARTWORK", 2, switchTrackTexture)
    flash:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    flash:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    flash:SetVertexColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0)
    flash:SetAlpha(0)
    local knob = ControlTexture(btn, "_msuf2SwitchKnob", "OVERLAY", nil, switchKnobTexture)
    knob:SetSize(knobSize, knobSize)
    btn._msuf2SwitchKnobSize = knobSize
    btn._msuf2SwitchKnobPad = knobPad
    btn._msuf2SwitchKnobTexture = switchKnobTexture
    btn._msuf2ProxyBaseWidth = switchW + 12
    btn._msuf2UpdateToggleProxyBounds = UpdateToggleProxyBounds
    local side = labelSide or "RIGHT"
    local labelFS = T.Font(section, "GameFontHighlightSmall", Tr(label or ""), T.colors.text, "control")
    SetSearchText(labelFS, label)
    labelFS:SetJustifyH(side == "LEFT" and "RIGHT" or "LEFT")
    if not labelWidth and section and section._msuf2Width then labelWidth = max(40, (section._msuf2Width or 0) - (x or 0) - switchW - 30) end
    if labelWidth then labelFS:SetWidth(max(20, labelWidth - (side == "RIGHT" and 22 or 0))) end
    if side == "LEFT" then
        labelFS:SetPoint("RIGHT", btn, "LEFT", -8, 0)
    else
        labelFS:SetPoint("LEFT", btn, "RIGHT", 8, 0)
    end
    if side == "HIDDEN" then labelFS:Hide() end
    btn._msuf2Label = labelFS
    btn.text = labelFS
    btn._msuf2RefreshSwitchVisual = RefreshSwitchVisual
    btn._msuf2RawSetChecked = btn.SetChecked
    btn.SetChecked = SetSwitchChecked
    for script, handler in pairs(SWITCH_CONTROL_HOOKS) do btn:HookScript(script, handler) end
    if side ~= "HIDDEN" then
        local labelHit = CreateFrame("Button", nil, section)
        labelHit:EnableMouse(true)
        if labelHit.RegisterForClicks then labelHit:RegisterForClicks("LeftButtonUp") end
        labelHit:SetFrameLevel(btn:GetFrameLevel() + 2)
        labelHit._msuf2SwitchOwner = btn
        for script, handler in pairs(SWITCH_LABEL_HOOKS) do labelHit:SetScript(script, handler) end
        if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(labelHit, btn)
        else labelHit._msuf2ControlPartOf = btn end
        btn._msuf2LabelHit = labelHit
        btn._msuf2UseProxyMouse = true
        if btn.EnableMouse then btn:EnableMouse(false) end
    end
    btn:SetChecked(false)
    UpdateToggleProxyBounds(btn)
    RegisterSearchObject(btn, label, "toggle", { anchor = side ~= "HIDDEN" and labelFS or btn })
    return btn
end
local function ScopeButtonWidth(item)
    if item and item.width then return item.width end
    local value = item and item.value
    local text = tostring(Tr((item and (item.text or item.label)) or value or ""))
    if value == "shared" then return 72 end
    if value == "targettarget" then return 58 end
    if value == "focustarget" then return 92 end
    if text:match("^Boss [1-5]$") then return 74 end
    return math.max(54, math.min(96, 28 + (#text * 7)))
end
local function MeasureScopeOverrideLayout(values, opts)
    opts = opts or {}
    values = values or opts.values or {}
    local centerY = opts.centerY or -28
    local labelX = opts.labelX or 14
    local labelW = opts.labelWidth or 64
    local gap = opts.gap or 8
    local buttonH = opts.buttonHeight or 24
    local rowStep = opts.rowStep or (buttonH + 6)
    local sectionW = opts.width or (opts.ctx and opts.ctx.width) or 720
    local maxRight = opts.maxRight or (sectionW - 14)
    local startX = opts.startX or (labelX + labelW + 8)
    local x, y = startX, centerY
    local rows = 1
    for i = 1, #values do
        local width = ScopeButtonWidth(values[i])
        if x > startX and x + width > maxRight then
            x = startX
            y = y - rowStep
            rows = rows + 1
        end
        x = x + width + gap
    end
    return {
        rows = rows,
        bottomY = y - math.floor(buttonH * 0.5 + 0.5),
        centerY = centerY,
        lastRowCenterY = y,
        rowStep = rowStep,
        buttonHeight = buttonH,
        sectionWidth = sectionW,
        maxRight = maxRight,
        startX = startX,
    }
end
function W.MeasureScopeOverrideBar(values, opts)
    if type(values) == "table" and values.values and opts == nil then
        opts = values
        values = opts.values
    end
    return MeasureScopeOverrideLayout(values, opts)
end
function W.ScopeOverrideBar(ctx, section, opts)
    opts = opts or {}
    local values = opts.values or {}
    local centerY = opts.centerY or -28
    local labelX = opts.labelX or 14
    local labelW = opts.labelWidth or 64
    local gap = opts.gap or 8
    local buttonH = opts.buttonHeight or 24
    local sectionW = opts.width or section._msuf2Width or (ctx and ctx.width) or (section.GetWidth and section:GetWidth()) or 720
    local maxRight = opts.maxRight or (sectionW - 14)
    local startX = opts.startX or (labelX + labelW + 8)
    local rowStep = opts.rowStep or (buttonH + 6)
    local metrics = MeasureScopeOverrideLayout(values, {
        centerY = centerY,
        labelX = labelX,
        labelWidth = labelW,
        gap = gap,
        buttonHeight = buttonH,
        rowStep = rowStep,
        width = sectionW,
        maxRight = maxRight,
        startX = startX,
    })
    local label = T.Font(section, opts.labelFont or "GameFontHighlightSmall", Tr(opts.label or "Editing:"), opts.labelColor or T.colors.text, "control")
    SetSearchText(label, opts.label or "Editing:")
    RegisterSearchObject(label, opts.label or "Editing:", "text")
    label:SetPoint("LEFT", section, "TOPLEFT", labelX, centerY)
    label:SetWidth(labelW)
    label:SetJustifyH("LEFT")
    local bar = CreateFrame("Frame", nil, section)
    SetSearchTitle(bar, opts.label or "Editing:")
    RegisterSearchObject(bar, opts.label or "Editing:", "segment", { values = values })
    bar:SetPoint("TOPLEFT", section, "TOPLEFT", 0, 0)
    bar:SetSize(sectionW, math.abs(metrics.bottomY) + 6)
    bar.buttons = {}
    bar.values = values
    bar.label = label
    bar._msuf2Rows = metrics.rows
    bar._msuf2BottomY = metrics.bottomY
    bar._msuf2LastRowCenterY = metrics.lastRowCenterY
    local x, y = startX, centerY
    for i = 1, #values do
        local item = values[i]
        local width = ScopeButtonWidth(item)
        if x > startX and x + width > maxRight then
            x = startX
            y = y - rowStep
        end
        local btn = T.Button(section, Tr(item.text or item.label or item.value or ""), width, buttonH)
        -- The logical ScopeOverrideBar owns search/catalog identity and values.
        -- Child buttons are implementation details; registering both creates
        -- duplicate/unknown controls for one selection.
        if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(btn, bar)
        else btn._msuf2ControlPartOf = bar end
        btn:SetPoint("LEFT", section, "TOPLEFT", x, y)
        btn._msuf2Value = item.value
        btn._msuf2BaseWidth = width
        T.CenterButtonLabel(btn)
        if btn.RefreshVisual then btn:RefreshVisual() end
        btn:SetScript("OnClick", function() bar:SetValue(item.value) end)
        bar.buttons[i] = btn
        x = x + width + gap
    end
    function bar:GetValue()
        if type(opts.getValue) == "function" then return opts.getValue() end
        return opts.value
    end
    function bar:SetValue(value)
        local current = self:GetValue()
        if current == value then self:Refresh(); return false end
        if type(opts.setValue) == "function" then opts.setValue(value) end
        if type(opts.onChange) == "function" then opts.onChange(value) end
        self:Refresh()
        return self:GetValue() == value
    end
    function bar:GetLayoutMetrics()
        return metrics
    end
    function bar:Refresh()
        local value = self:GetValue()
        for i = 1, #self.buttons do
            local btn = self.buttons[i]
            local active = btn._msuf2Value == value
            local override = false
            if type(opts.hasOverride) == "function" then override = opts.hasOverride(btn._msuf2Value) and true or false end
            local nextOverride = (not active) and override or false
            if btn._msuf2Active ~= active or btn._msuf2Override ~= nextOverride then
                btn._msuf2Override = nextOverride
                btn:SetActive(active)
            end
        end
    end
    M.TrackRefresh(ctx, function() bar:Refresh() end)
    return bar
end
function W.SetControlShown(control, shown)
    if not control then return end
    shown = shown and true or false
    if control.SetShown then control:SetShown(shown) elseif shown then control:Show() else control:Hide() end
    if control._msuf2Title then control._msuf2Title:SetShown(shown) end
    if control._msuf2Label and not control._msuf2Label._msuf2AlwaysHidden then control._msuf2Label:SetShown(shown) end
    if control._msuf2LabelHit then control._msuf2LabelHit:SetShown(shown) end
    if not shown and control._msuf2RefreshToggleFeedback then
        control._msuf2ToggleHovered = nil
        control._msuf2TogglePressed = nil
        control:_msuf2RefreshToggleFeedback()
    end
    if control._msuf2ToggleRowHover then
        if not shown then control._msuf2ToggleRowHover:SetAlpha(0) end
        control._msuf2ToggleRowHover:SetShown(shown)
    end
    if control.editBox then control.editBox:SetShown(shown) end
    if control._msuf2StepButtons then
        for i = 1, #control._msuf2StepButtons do
            control._msuf2StepButtons[i]:SetShown(shown)
        end
    end
    if control._msuf2LayerShortcutButton then
        control._msuf2LayerShortcutButton:SetShown(shown)
    end
    if shown and control._msuf2SetLayoutWidth then control:_msuf2SetLayoutWidth(control._msuf2RowWidth or control._msuf2RequestedWidth) end
end
local function SetEnabledState(frame, enabled)
    if not frame then return end
    local mouseEnabled = enabled and not frame._msuf2UseProxyMouse
    if frame._msuf2EnabledStateApplied == enabled
        and frame._msuf2MouseEnabledStateApplied == mouseEnabled
        and (not frame.IsEnabled or ((frame:IsEnabled() and true or false) == enabled))
    then
        return
    end
    frame._msuf2EnabledStateApplied = enabled
    frame._msuf2MouseEnabledStateApplied = mouseEnabled
    -- Theme buttons repaint their custom fill, edge, and label in SetEnabled.
    -- Calling only the native Enable/Disable methods changes interaction state
    -- but leaves an active segment painted blue while its parent is disabled.
    if frame.SetEnabled then
        frame:SetEnabled(enabled)
    elseif frame.Enable and frame.Disable then
        if enabled then frame:Enable() else frame:Disable() end
    end
    if frame.EnableMouse then frame:EnableMouse(mouseEnabled) end
end
local function SetTextEnabledColor(fontString, enabled)
    if not (fontString and fontString.SetTextColor) then return end
    local c = enabled and T.colors.text or (T.colors.disabled or T.colors.dim)
    local r, g, b, a = c[1], c[2], c[3], c[4] or 1
    if fontString._msuf2EnabledColorState == enabled
        and fontString._msuf2TextColorR == r
        and fontString._msuf2TextColorG == g
        and fontString._msuf2TextColorB == b
        and fontString._msuf2TextColorA == a
    then
        return
    end
    fontString._msuf2EnabledColorState = enabled
    fontString._msuf2TextColorR, fontString._msuf2TextColorG, fontString._msuf2TextColorB, fontString._msuf2TextColorA = r, g, b, a
    fontString:SetTextColor(r, g, b, a)
end
local function HasDisableGate(control)
    local gates = control and control._msuf2DisableGates
    if type(gates) ~= "table" then return false end
    for _, disabled in pairs(gates) do
        if disabled then return true end
    end
    return false
end
local function ApplyEnabledVisuals(control, enabled)
    SetEnabledState(control, enabled)
    if control.SetAlpha and control._msuf2EnabledAlphaState ~= enabled then
        control._msuf2EnabledAlphaState = enabled
        control:SetAlpha(enabled and 1 or 0.60)
    end
    SetTextEnabledColor(control._msuf2Title, enabled)
    SetTextEnabledColor(control._msuf2Label, enabled)
    if control._msuf2RefreshSwitchVisual then control:_msuf2RefreshSwitchVisual() end
    if control._msuf2RefreshToggleFeedback then control:_msuf2RefreshToggleFeedback() end
    if control._msuf2LabelHit and control._msuf2LabelHit.EnableMouse and control._msuf2LabelHit._msuf2MouseEnabledStateApplied ~= enabled then
        control._msuf2LabelHit._msuf2MouseEnabledStateApplied = enabled
        control._msuf2LabelHit:EnableMouse(enabled)
    end
    local edit = control.editBox or control.__MSUF_valueBox
    if edit then
        SetEnabledState(edit, enabled)
        if edit.SetAlpha and edit._msuf2EnabledAlphaState ~= enabled then
            edit._msuf2EnabledAlphaState = enabled
            edit:SetAlpha(enabled and 1 or 0.60)
        end
    end
    if control._msuf2StepButtons then
        for i = 1, #control._msuf2StepButtons do
            local btn = control._msuf2StepButtons[i]
            SetEnabledState(btn, enabled)
            if btn.SetAlpha and btn._msuf2EnabledAlphaState ~= enabled then
                btn._msuf2EnabledAlphaState = enabled
                btn:SetAlpha(enabled and 1 or 0.60)
            end
        end
    end
    if control.buttons then
        for i = 1, #control.buttons do
            local btn = control.buttons[i]
            SetEnabledState(btn, enabled)
            if btn.SetAlpha and btn._msuf2EnabledAlphaState ~= enabled then
                btn._msuf2EnabledAlphaState = enabled
                btn:SetAlpha(enabled and 1 or 0.60)
            end
        end
    end
end
local function ApplyControlEnabled(control)
    if not control then return end
    local enabled = (control._msuf2DesiredEnabled ~= false) and not HasDisableGate(control)
    if control._msuf2AppliedEnabled == enabled then return end
    control._msuf2AppliedEnabled = enabled
    if control._msuf2ControlKind == "slider" then
        HideSliderTemplateParts(control)
        if T.StyleSlider then T.StyleSlider(control) end
        if control._msuf2UpdateFill then control:_msuf2UpdateFill() end
    end
    ApplyEnabledVisuals(control, enabled)
    if control._msuf2Chevron and control._msuf2Chevron.SetVertexColor then
        local c = enabled and T.colors.muted or (T.colors.disabled or T.colors.dim)
        control._msuf2Chevron:SetVertexColor(c[1], c[2], c[3], enabled and 0.95 or 0.55)
    end
end

--- Shared by all Menu2 pages so disabled dependent options do not drift visually.
--- Enable gates keep disabled controls visible but inert, which preserves page
--- layout and lets tooltips/explanatory text still be attached by callers.
function W.SetControlEnabled(control, enabled)
    if not control then return end
    control._msuf2DesiredEnabled = enabled and true or false
    ApplyControlEnabled(control)
end
function W.SetControlGateEnabled(control, gateKey, enabled)
    if not control then return end
    gateKey = tostring(gateKey or "default")
    control._msuf2DisableGates = control._msuf2DisableGates or {}
    local disabled = not (enabled and true or false)
    if control._msuf2DisableGates[gateKey] == disabled then return end
    control._msuf2DisableGates[gateKey] = disabled
    if control._msuf2DesiredEnabled == nil then
        local current = true
        if control.IsEnabled then current = control:IsEnabled() and true or false end
        control._msuf2DesiredEnabled = current
    end
    ApplyControlEnabled(control)
end
function W.ClearControlGate(control, gateKey, deferApply)
    local gates = control and control._msuf2DisableGates
    if type(gates) ~= "table" then return false end
    gateKey = tostring(gateKey or "default")
    if gates[gateKey] == nil then return false end
    gates[gateKey] = nil
    if deferApply ~= true then ApplyControlEnabled(control) end
    return true
end
function W.SetControlsEnabled(controls, enabled)
    for i = 1, #(controls or {}) do
        W.SetControlEnabled(controls[i], enabled)
    end
end
local function ClampPlacedControlWidth(widget, parent, x)
    if not (widget and parent and parent._msuf2Width) then return end
    local kind = widget._msuf2ControlKind
    if kind ~= "slider" and kind ~= "dropdown" and kind ~= "textinput" then return end
    local available = floor((parent._msuf2Width or 0) - (x or 0) - 18)
    if available <= 0 then return end
    if kind == "slider" and widget._msuf2SetLayoutWidth then
        local requested = widget._msuf2RequestedWidth or widget._msuf2RowWidth or 280
        local minWidth = widget._msuf2MinRowWidth or 48
        widget:_msuf2SetLayoutWidth(max(minWidth, min(requested, available)))
        return
    end
    local currentW = widget.GetWidth and widget:GetWidth()
    if currentW and currentW > available then
        widget:SetWidth(max(72, available))
        if widget._msuf2Title and widget._msuf2Title.SetWidth then widget._msuf2Title:SetWidth(max(72, available)) end
    end
end

--- Shared positioning helper for widgets that can be placed in normal page flow
--- or moved into card/preview surfaces.
function W.MoveWidget(widget, parent, x, y, width, titleJustify)
    if not (widget and widget.ClearAllPoints) then return widget end
    parent = parent or widget:GetParent()
    x = x or 0
    y = y or 0
    local kind = widget._msuf2ControlKind
    widget._msuf2ContextLayoutParent = parent
    widget._msuf2ContextLayoutX = x
    widget._msuf2ContextLayoutY = y
    width = tonumber(width)
    if width then
        if kind == "slider" and widget._msuf2SetLayoutWidth then
            widget._msuf2RequestedWidth = width
            widget:_msuf2SetLayoutWidth(width)
        elseif kind == "dropdown" or kind == "textinput" or kind == "segment" then
            widget:SetSize(width, widget:GetHeight() or 22)
            if widget._msuf2Title and widget._msuf2Title.SetWidth then widget._msuf2Title:SetWidth(width) end
        elseif kind == "toggle" and widget._msuf2Label and widget._msuf2Label.SetWidth then
            widget._msuf2Label:SetWidth(max(20, width))
        end
    end
    if titleJustify and widget._msuf2Title and widget._msuf2Title.SetJustifyH then
        widget._msuf2TitleJustify = titleJustify
        widget._msuf2Title:SetJustifyH(titleJustify)
    end
    ClampPlacedControlWidth(widget, parent, x)
    if widget._msuf2Title then
        widget._msuf2Title:ClearAllPoints()
        widget._msuf2Title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    end
    widget:ClearAllPoints()
    if kind == "slider" or kind == "dropdown" or kind == "textinput" or kind == "segment" then
        widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 24)
    elseif kind == "color" then
        if widget._msuf2Title then widget._msuf2Title:SetWidth(100) end
        widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 108, y + 2)
    else
        widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    end
    if kind == "color" and widget._msuf2ContextColorBound then AttachBoundColorToContextCard(widget) end
    if kind == "toggle" and widget._msuf2UpdateToggleProxyBounds then widget:_msuf2UpdateToggleProxyBounds() end
    return widget
end
function W.LabelAt(parent, text, x, y, width, template, color)
    local fs = T.Font(parent, template or "GameFontNormalSmall", Tr(text or ""), color or T.colors.text)
    SetSearchText(fs, text)
    RegisterSearchObject(fs, text, "text")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y or 0)
    fs:SetWidth(width or 180)
    fs:SetJustifyH("LEFT")
    return fs
end
function W.DividerAt(parent, y, leftPad, rightPad)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", leftPad or 12, y or 0)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(rightPad or 12), y or 0)
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.06)
    return line
end
function W.Button(section, label, width)
    local x, y = NextRow(section, 32)
    local btn = T.Button(section, Tr(label or ""), width or 160, 24)
    btn._msuf2ControlKind = "button"
    RegisterSearchObject(btn, label, "button")
    btn:SetPoint("TOPLEFT", x, y)
    return btn
end

--- Register a page-owned editing/navigation panel for the fixed header slot.
---
--- Registration is intentionally passive: page selection in Window.lua owns
--- activation synchronously.  Inactive panels stay with their page wrapper,
--- so cache invalidation cannot strand the panel (and its surface textures)
--- under the shared window header host.
---
--- A page may register more than one panel.  They stack in registration order,
--- so a page that builds its navigation strip before its preview gets the strip
--- on top and the preview directly beneath it, both above the scrolling body.
function W.AttachStickyPageHeader(section, opts)
    if not section then return nil end
    opts = opts or {}
    local ctx = opts.ctx
    local entry = ctx and ctx.entry
    if type(entry) ~= "table" then return nil end
    local existing = section._msuf2StickyPageHeaderRecord
    if existing and not existing.disposed and existing.entry == entry then return existing end
    entry.pageHeaders = entry.pageHeaders or {}

    local originalParent = (section.GetParent and section:GetParent()) or opts.wrapper
    local point, relativeTo, relativePoint, originalX, originalY
    if section.GetPoint then
        point, relativeTo, relativePoint, originalX, originalY = section:GetPoint(1)
    end
    point = point or "TOPLEFT"
    relativeTo = relativeTo or originalParent
    relativePoint = relativePoint or point
    originalX, originalY = tonumber(originalX) or 0, tonumber(originalY) or 0
    local originalWidth = tonumber(section.GetWidth and section:GetWidth()) or 0
    local originalHeight = tonumber(section.GetHeight and section:GetHeight()) or 0
    local originalFrameLevel = (section.GetFrameLevel and section:GetFrameLevel()) or 1
    local originalPageOwnerWrapper = section._msuf2PageOwnerWrapper
    local originalGuidedNoScroll = section._msuf2GuidedNoScroll
    local headerX = tonumber(opts.left) or originalX
    local headerY = tonumber(opts.top)
    if headerY == nil then headerY = originalY end
    local headerTopInset = max(0, -headerY)
    local stickyGap = max(0, tonumber(opts.gap) or 0)

    if section.EnableMouse then section:EnableMouse(true) end
    -- Fixed panels are physically reparented to the shared host but remain
    -- logical children of their page for exact Search/Assistant routing.
    section._msuf2PageOwnerWrapper = opts.wrapper or (ctx and ctx.wrapper) or originalParent
    section._msuf2GuidedNoScroll = true
    local builder = opts.builder
    if builder and not section._msuf2PageHeaderFlowReleased then
        local flowGap = max(0, tonumber(opts.flowGap) or 12)
        local sectionHeight = originalHeight
        -- The original first panel starts at PageBuilder's -12 inset.  That
        -- inset now belongs to the fixed header, so release it from the new
        -- ScrollFrame flow as well; otherwise top padding is counted twice.
        builder.y = (tonumber(builder.y) or 0) + sectionHeight + flowGap + headerTopInset
        section._msuf2PageHeaderFlowReleased = true
        if ctx and ctx.SetContentHeight then
            ctx:SetContentHeight(math.abs(builder.y) + 28)
        end
    end

    local record = {
        entry = entry,
        section = section,
        pageKey = opts.pageKey or entry.key,
        originalParent = originalParent,
        originalPoint = point,
        originalRelativeTo = relativeTo,
        originalRelativePoint = relativePoint,
        originalX = originalX,
        originalY = originalY,
        originalWidth = originalWidth,
        originalHeight = originalHeight,
        originalFrameLevel = originalFrameLevel,
        headerX = headerX,
        headerY = headerY,
        headerTopInset = headerTopInset,
        stickyGap = stickyGap,
        hostHeight = max(0, headerTopInset + originalHeight + stickyGap),
        -- The page's own "make my docked content real and visible" entry point.
        -- Run by M.RunStickyHeaderActivation after the page wrapper is shown -
        -- never during Activate, whose geometry pass can precede wrapper:Show().
        onActivate = opts.onActivate,
        heightResolver = opts.heightResolver,
    }

    function record:ResolveHeight()
        local resolved
        if type(self.heightResolver) == "function" then resolved = tonumber(self.heightResolver(self)) end
        if not resolved or resolved <= 0 then
            resolved = tonumber(section.GetHeight and section:GetHeight()) or self.originalHeight
        end
        if not resolved or resolved <= 0 then resolved = self.originalHeight end
        return max(0, tonumber(resolved) or 0)
    end

    function record:Registered()
        local list = self.entry and self.entry.pageHeaders
        if type(list) ~= "table" then return false end
        for i = 1, #list do
            if list[i] == self then return true end
        end
        return false
    end

    --- `stackOffset` is the height already consumed by the panels registered
    --- above this one, so a page's panels tile downwards from the host's top.
    ---
    --- Activate is pure geometry: parent, anchor, size, level. Waking the
    --- content inside the panel is NOT done here - a docked panel no longer
    --- lives under the page wrapper, so page selection runs the registered
    --- `onActivate` callback through M.RunStickyHeaderActivation strictly
    --- AFTER the wrapper is shown, when the page's visibility gates pass.
    function record:Activate(headerHost, stackOffset)
        if self.disposed or not headerHost or not self:Registered() then return false end
        stackOffset = tonumber(stackOffset) or 0
        local activeHeight = self:ResolveHeight()
        self.hostHeight = max(0, headerTopInset + activeHeight + stickyGap)
        self.stackOffset = stackOffset
        self._activating = true
        -- Re-anchoring a panel that already lives in the slot (a height change
        -- underneath it) must not flicker it through a hide/show cycle.
        local alreadyHosted = section.GetParent and section:GetParent() == headerHost
        if not alreadyHosted then
            if section.Hide then section:Hide() end
            section:SetParent(headerHost)
        end
        section:ClearAllPoints()
        -- Preserve the PageBuilder geometry exactly.  Deriving a new width
        -- from the host's right edge made the right margin differ from the
        -- original page and let child rows protrude past rounded corners.
        section:SetPoint(point, headerHost, relativePoint, headerX, headerY - stackOffset)
        if section.SetSize and self.originalWidth > 0 and activeHeight > 0 then
            section:SetSize(self.originalWidth, activeHeight)
        end
        if section.SetFrameLevel then
            local baseLevel = (headerHost.GetFrameLevel and headerHost:GetFrameLevel()) or originalFrameLevel
            section:SetFrameLevel(baseLevel + (opts.frameLevelOffset or 2))
        end
        if section.Show and not (section.IsShown and section:IsShown()) then section:Show() end
        self.active = true
        self._activating = nil
        return true
    end

    function record:Deactivate()
        if self.disposed then return end
        -- Clear ownership before restoring the page-local geometry. SetSize can
        -- synchronously fire OnSizeChanged; that callback must never re-host a
        -- panel while it is being deactivated.
        self._deactivating = true
        self.active = nil
        if section.Hide then section:Hide() end
        if originalParent and section.SetParent then section:SetParent(originalParent) end
        section:ClearAllPoints()
        section:SetPoint(point, relativeTo, relativePoint, originalX, originalY)
        if section.SetSize and originalWidth > 0 and originalHeight > 0 then
            section:SetSize(originalWidth, originalHeight)
        end
        if section.SetFrameLevel then section:SetFrameLevel(originalFrameLevel) end
        self._deactivating = nil
    end

    function record:Dispose()
        if self.disposed then return end
        local expander = self.previewExpander
        if expander and type(expander.Dispose) == "function" then
            expander:Dispose("FIXED_HEADER_DISPOSE")
        end
        self.previewExpander = nil
        self:Deactivate()
        self.disposed = true
        if section._msuf2StickyPageHeaderRecord == self then
            section._msuf2StickyPageHeaderRecord = nil
        end
        section._msuf2PageOwnerWrapper = originalPageOwnerWrapper
        section._msuf2GuidedNoScroll = originalGuidedNoScroll
        local list = entry.pageHeaders
        if type(list) == "table" then
            for i = #list, 1, -1 do
                if list[i] == self then table.remove(list, i) end
            end
        end
        if entry.pageHeader == self then entry.pageHeader = list and list[1] or nil end
    end

    entry.pageHeaders[#entry.pageHeaders + 1] = record
    entry.pageHeader = entry.pageHeaders[1]
    section._msuf2StickyPageHeaderRecord = record
    -- Panels whose own height changes while docked (a collapsible preview, a
    -- compact/expanded canvas) have to re-drive the host: the slot reserves
    -- exactly as much room as the panel currently needs.
    if opts.dynamicHeight and section.HookScript and not section._msuf2StickyHeaderSizeHooked then
        section._msuf2StickyHeaderSizeHooked = true
        section:HookScript("OnSizeChanged", function()
            local current = section._msuf2StickyPageHeaderRecord
            local active = current and current.active and not current.disposed
                and not current._activating and not current._deactivating
            if active and type(M.RelayoutPageHeaderHost) == "function" then M.RelayoutPageHeaderHost() end
        end)
    end
    -- A freshly built page wrapper is hidden until SelectPage commits it.
    -- Keep the registered panel hidden as well; the central activation path
    -- shows it only after the page becomes active.
    if section.Hide then section:Hide() end
    return record
end

-- Page-level previews use a dedicated, non-collapsible shell. Compact height is
-- bounded consistently; an explicit Expand action may grow this same fixed
-- slot, which makes the settings ScrollFrame start farther down like an
-- accordion without moving the preview into scrolling content.
local FIXED_PREVIEW_MAX_HEIGHT = 180
W.FIXED_PREVIEW_MAX_HEIGHT = FIXED_PREVIEW_MAX_HEIGHT

-- Full/Max is the presentation default for a fresh session and after resets.
-- This remains deliberately profile-independent: only an explicit Compact
-- action overrides it for the current UI session.
function M.SetFixedPreviewExpandedPreference(expanded)
    M._msuf2FixedPreviewExpandedPreference = expanded ~= false
end
function M.ShouldExpandFixedPreview()
    return M._msuf2FixedPreviewExpandedPreference ~= false
end

function W.FixedPreviewSection(ctx, builder, spec)
    if type(ctx) ~= "table" or type(builder) ~= "table" or type(builder.Section) ~= "function" then return nil end
    spec = type(spec) == "table" and spec or {}
    local fixedHeight = max(1, min(FIXED_PREVIEW_MAX_HEIGHT, tonumber(spec.height) or 180))
    local title = spec.title or "Preview"
    local section = builder:Section(title, fixedHeight)
    section._msuf2FixedPagePreview = true
    section._msuf2FixedPreviewHeight = fixedHeight
    section._msuf2FixedPreviewCompactHeight = fixedHeight

    local toolbar = CreateFrame("Frame", nil, section)
    toolbar:SetPoint("TOPLEFT", section, "TOPLEFT", 0, 0)
    toolbar:SetPoint("TOPRIGHT", section, "TOPRIGHT", 0, 0)
    toolbar:SetHeight(32)
    toolbar._msuf2FixedPreviewToolbar = true
    if toolbar.SetFrameLevel and section.GetFrameLevel then toolbar:SetFrameLevel(section:GetFrameLevel() + 1) end
    if section.title then
        section.title:ClearAllPoints()
        section.title:SetPoint("LEFT", toolbar, "LEFT", 16, 0)
    end
    local divider = toolbar:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("BOTTOMLEFT", toolbar, "BOTTOMLEFT", 12, 0)
    divider:SetPoint("BOTTOMRIGHT", toolbar, "BOTTOMRIGHT", -12, 0)
    divider:SetHeight(1)
    divider:SetColorTexture(1, 1, 1, 0.06)
    toolbar.divider = divider

    local record = W.AttachStickyPageHeader(section, {
        pageKey = spec.pageKey or ctx.key,
        wrapper = spec.wrapper or ctx.wrapper,
        builder = builder,
        ctx = ctx,
        left = spec.left,
        top = spec.top,
        gap = spec.gap == nil and 8 or spec.gap,
        flowGap = spec.flowGap or 12,
        frameLevelOffset = spec.frameLevelOffset,
        dynamicHeight = true,
        heightResolver = function()
            return tonumber(section._msuf2FixedPreviewActiveHeight) or fixedHeight
        end,
        onActivate = spec.onActivate,
    })
    if record then
        record.previewBody = section
        record.isFixedPreview = true
        record.fixedHeight = fixedHeight
        section._msuf2FixedPagePreviewRecord = record
    end
    return section, toolbar, record
end

--- Add compact/full behavior to a fixed preview slot. The same renderer grows
--- inside the Section, then RelayoutPageHeaderHost moves the settings viewport
--- below it. Nothing overlays the ScrollFrame or duplicates preview controls.
function W.AttachFixedPreviewExpander(section, toolbar, previewBox, opts)
    if not (section and toolbar and previewBox) then return nil end
    opts = type(opts) == "table" and opts or {}
    local existing = section._msuf2FixedPreviewExpanderRecord
    if existing and not existing.disposed then
        if existing.box == previewBox then
            previewBox._msuf2FixedPreviewExpanderRecord = existing
            previewBox._msuf2CompactExpandButton = existing.button
            return existing
        end
        if type(existing.Dispose) == "function" then existing:Dispose("FIXED_PREVIEW_RENDERER_REPLACED") end
    end

    local fixedHeaderRecord = section._msuf2FixedPagePreviewRecord
    local horizontalInset = max(0, tonumber(opts.horizontalInset) or 14)
    local compactSectionHeight = max(1, tonumber(fixedHeaderRecord and fixedHeaderRecord.fixedHeight)
        or tonumber(section._msuf2FixedPreviewCompactHeight)
        or tonumber(section.GetHeight and section:GetHeight()) or 180)
    local compactHeight = max(1, tonumber(opts.compactHeight)
        or tonumber(previewBox.GetHeight and previewBox:GetHeight()) or 132)
    local compactTop = tonumber(opts.compactTop) or -40
    local expandedHeight = max(1, tonumber(opts.expandedHeight) or 358)
    local expandedTop = tonumber(opts.expandedTop) or compactTop
    local expandedSectionHeight = max(compactSectionHeight,
        tonumber(opts.expandedSectionHeight) or (math.abs(expandedTop) + expandedHeight + 8))
    local pageKey = opts.pageKey
    local pageWrapper = opts.wrapper
    local button = T.Button(toolbar, Tr("Expand"), tonumber(opts.buttonWidth) or 88, 20)
    if T.CenterButtonLabel then T.CenterButtonLabel(button) end
    if T.SkinPrimaryButton then T.SkinPrimaryButton(button) end
    button:SetPoint("RIGHT", toolbar, "RIGHT", -12, 0)
    button._msuf2ControlKind = "button"
    RegisterSearchObject(button, "Expand Preview", "button")
    if M.AddTooltip then
        M.AddTooltip(button, "Preview size",
            "Toggle between the compact reference preview and the full-height canvas.", { hook = true })
    end

    local record = {
        section = section,
        toolbar = toolbar,
        box = previewBox,
        button = button,
        pageKey = pageKey,
        pageWrapper = pageWrapper,
        fixedHeaderRecord = fixedHeaderRecord,
        compactHeight = compactHeight,
        compactSectionHeight = compactSectionHeight,
        preferredExpandedHeight = expandedHeight,
        preferredExpandedSectionHeight = expandedSectionHeight,
    }
    local function OwnsPreviewBox()
        return previewBox._msuf2FixedPreviewExpanderRecord == record
    end

    local function PageOwned()
        if pageKey and M.activeKey and M.activeKey ~= pageKey then return false end
        if M.frame and M.frame.IsShown and not M.frame:IsShown() then return false end
        if pageWrapper and pageWrapper.IsShown and not pageWrapper:IsShown() then return false end
        if section.IsShown and not section:IsShown() then return false end
        return true
    end
    local function RefreshButton()
        if record.expanded then
            button:SetSize(130, 20)
            button:SetText(Tr("Compact Preview"))
        else
            button:SetSize(88, 20)
            button:SetText(Tr("Expand"))
        end
    end
    local function RefreshPreview(reason)
        if type(opts.refreshPreview) == "function" then
            opts.refreshPreview(previewBox, reason)
        elseif previewBox.RequestRefresh then
            previewBox:RequestRefresh(reason)
        elseif previewBox.Refresh then
            previewBox:Refresh(reason)
        end
    end
    local function SetCompactToolbarVisible(visible)
        local layersButton = previewBox._msuf2LayersButton
        if not visible and layersButton and layersButton.Hide then
            record.compactLayersWasShown = layersButton.IsShown and layersButton:IsShown() or false
            layersButton:Hide()
        elseif visible and record.compactLayersWasShown and layersButton and layersButton.Show then
            record.compactLayersWasShown = nil
            layersButton:Show()
        elseif visible then
            record.compactLayersWasShown = nil
        end
    end
    local function RelayoutHeader()
        local header = fixedHeaderRecord
        if header and header.active and not header.disposed
            and not header._activating and not header._deactivating
            and type(M.RelayoutPageHeaderHost) == "function"
        then
            M.RelayoutPageHeaderHost()
        end
    end
    local function PreferredExpansionBudget()
        local host = M.frame and M.frame.host
        local status = M.frame and M.frame.status
        local list = M.scrollFrame and M.scrollFrame._msuf2StickyPageHeaders
        local hostHeight = tonumber(host and host.GetHeight and host:GetHeight()) or 0
        local statusHeight = tonumber(status and status.GetHeight and status:GetHeight()) or 0
        -- Missing/settling geometry must never speculatively collapse an
        -- explicitly expanded preview. The resize commit can ask again once
        -- the final frame size has been applied.
        if not (fixedHeaderRecord and fixedHeaderRecord.active and hostHeight > statusHeight
            and type(list) == "table")
        then
            return nil, nil
        end
        local otherHeight = 0
        for i = 1, #list do
            local candidate = list[i]
            if candidate and candidate ~= fixedHeaderRecord and candidate.active and not candidate.disposed then
                otherHeight = otherHeight + max(0, tonumber(candidate.hostHeight) or 0)
            end
        end
        local chromeHeight = max(0, tonumber(fixedHeaderRecord.headerTopInset) or 0)
            + max(0, tonumber(fixedHeaderRecord.stickyGap) or 0)
        local requiredHeight = otherHeight + chromeHeight + expandedSectionHeight
        local availableSpan
        if type(M.GetPageHeaderAvailableHeight) == "function" then
            availableSpan = tonumber(M.GetPageHeaderAvailableHeight())
        end
        if not availableSpan then availableSpan = hostHeight - statusHeight end
        return requiredHeight, availableSpan - 16
    end
    function record:CanFitPreferredExpansion()
        if self.disposed then return false end
        local requiredHeight, availableHeight = PreferredExpansionBudget()
        if not requiredHeight then return true end
        return requiredHeight <= availableHeight + 0.5
    end
    function record:GetPreferredExpansionShortfall()
        if self.disposed then return 0 end
        local requiredHeight, availableHeight = PreferredExpansionBudget()
        if not requiredHeight then return 0 end
        return max(0, requiredHeight - availableHeight)
    end
    function record:Relayout(reason)
        if self.disposed or not self.expanded or not OwnsPreviewBox() then return false end
        local activeBoxHeight, activeSectionHeight = expandedHeight, expandedSectionHeight
        previewBox._msuf2PinnedFloating = true
        previewBox:ClearAllPoints()
        previewBox:SetPoint("TOPLEFT", section, "TOPLEFT", horizontalInset, expandedTop)
        previewBox:SetPoint("TOPRIGHT", section, "TOPRIGHT", -horizontalInset, expandedTop)
        previewBox:SetHeight(activeBoxHeight)
        if previewBox.SetFrameLevel and section.GetFrameLevel then
            previewBox:SetFrameLevel((section:GetFrameLevel() or 1) + 2)
        end
        if previewBox.ApplyCompactPreviewPresentation then previewBox:ApplyCompactPreviewPresentation(false) end
        previewBox:Show()
        self.sectionWidth = tonumber(section.GetWidth and section:GetWidth()) or self.sectionWidth
        section._msuf2FixedPreviewActiveHeight = activeSectionHeight
        if section.SetHeight then section:SetHeight(activeSectionHeight) end
        RelayoutHeader()
        local activeWidth = tonumber(previewBox.GetWidth and previewBox:GetWidth()) or 0
        if self.activeHeight ~= activeBoxHeight or self.activeSectionHeight ~= activeSectionHeight
            or self.activeWidth ~= activeWidth
        then
            self.activeHeight = activeBoxHeight
            self.activeSectionHeight = activeSectionHeight
            self.activeWidth = activeWidth
            RefreshPreview(reason or "FIXED_PREVIEW_EXPAND_LAYOUT")
        end
        return true
    end
    function record:Open(reason, openOptions)
        if self.disposed or self.expanded or not OwnsPreviewBox() or not PageOwned() then return false end
        openOptions = type(openOptions) == "table" and openOptions or nil
        local active = M._msuf2ActiveFixedPreviewExpander
        if active and active ~= self and type(active.Close) == "function" then
            active:Close("OTHER_FIXED_PREVIEW")
        end
        self.expanded = true
        M._msuf2ActiveFixedPreviewExpander = self
        SetCompactToolbarVisible(false)
        RefreshButton()
        if openOptions and openOptions.preserveExpandedZoom == true then
            previewBox._msuf2PreserveExpandedZoomOnNextExpand = true
        end
        local laidOut = self:Relayout(reason or "FIXED_PREVIEW_EXPAND")
        previewBox._msuf2PreserveExpandedZoomOnNextExpand = nil
        if not laidOut then
            self:Close("FIXED_PREVIEW_EXPAND_FAILED")
            return false
        end
        if reason == "FIXED_PREVIEW_BUTTON" or reason == "FIXED_PREVIEW_COMMAND" then
            M.SetFixedPreviewExpandedPreference(true)
        end
        if type(opts.onStateChanged) == "function" then opts.onStateChanged(true, previewBox) end
        if type(M.EnsureFixedPreviewExpansionRoom) == "function" then
            M.EnsureFixedPreviewExpansionRoom(self)
        end
        return true
    end
    function record:Close(reason)
        local wasExpanded = self.expanded == true
        local ownsPreviewBox = OwnsPreviewBox()
        if reason == "FIXED_PREVIEW_BUTTON" or reason == "FIXED_PREVIEW_COMMAND" then
            if type(M.ClearPendingFixedPreviewExpansion) == "function" then
                M.ClearPendingFixedPreviewExpansion(pageKey)
            end
            M.SetFixedPreviewExpandedPreference(false)
        end
        self.expanded = nil
        self.activeHeight = nil
        self.activeSectionHeight = nil
        self.activeWidth = nil
        if M._msuf2ActiveFixedPreviewExpander == self then M._msuf2ActiveFixedPreviewExpander = nil end
        -- Unit and Group previews reuse one renderer across cached pages. Once
        -- another page owns that renderer, this stale controller may only drop
        -- its own state; touching Section geometry here can compact the new
        -- owner's already-expanded fixed header during cache disposal.
        if not ownsPreviewBox then return wasExpanded end
        if wasExpanded and ownsPreviewBox and type(opts.onStateChanged) == "function" then
            opts.onStateChanged(false, previewBox)
        end
        if ownsPreviewBox then
            previewBox._msuf2PinnedFloating = nil
            previewBox:ClearAllPoints()
            previewBox:SetPoint("TOPLEFT", section, "TOPLEFT", horizontalInset, compactTop)
            previewBox:SetPoint("TOPRIGHT", section, "TOPRIGHT", -horizontalInset, compactTop)
            if previewBox.SetHeight then previewBox:SetHeight(compactHeight) end
            if previewBox.ApplyCompactPreviewPresentation then previewBox:ApplyCompactPreviewPresentation(true) end
        end
        section._msuf2FixedPreviewActiveHeight = nil
        if section.SetHeight then section:SetHeight(compactSectionHeight) end
        if ownsPreviewBox then
            if previewBox.Show and PageOwned() then previewBox:Show() end
            SetCompactToolbarVisible(true)
        end
        RefreshButton()
        RelayoutHeader()
        if wasExpanded and ownsPreviewBox then RefreshPreview(reason or "FIXED_PREVIEW_COMPACT") end
        return wasExpanded
    end
    function record:Toggle()
        if self.expanded then return self:Close("FIXED_PREVIEW_BUTTON") end
        return self:Open("FIXED_PREVIEW_BUTTON")
    end
    function record:Dispose(reason)
        if self.disposed then return end
        self:Close(reason or "FIXED_PREVIEW_EXPANDER_DISPOSE")
        self.disposed = true
        button:Hide()
        if fixedHeaderRecord and fixedHeaderRecord.previewExpander == self then fixedHeaderRecord.previewExpander = nil end
        if section._msuf2FixedPreviewExpanderRecord == self then section._msuf2FixedPreviewExpanderRecord = nil end
        if previewBox._msuf2FixedPreviewExpanderRecord == self then
            previewBox._msuf2FixedPreviewExpanderRecord = nil
        end
    end

    button:SetScript("OnClick", function() record:Toggle() end)
    button._msuf2CommandAction = {
        kind = "toggle",
        historyMode = "none",
        get = function() return record.expanded == true end,
        set = function(value)
            if value then return record:Open("FIXED_PREVIEW_COMMAND") end
            record:Close("FIXED_PREVIEW_COMMAND")
            return record.expanded ~= true
        end,
    }
    if section.HookScript then
        section:HookScript("OnHide", function()
            if not record.disposed then record:Close("FIXED_PREVIEW_SECTION_HIDE") end
        end)
        section:HookScript("OnSizeChanged", function(self)
            if record.disposed or not record.expanded then return end
            local width = tonumber(self.GetWidth and self:GetWidth()) or 0
            if width > 0 and width ~= record.sectionWidth then
                record.sectionWidth = width
                record:Relayout("FIXED_PREVIEW_SECTION_WIDTH")
            end
        end)
    end
    section._msuf2FixedPreviewExpanderRecord = record
    previewBox._msuf2FixedPreviewExpanderRecord = record
    previewBox._msuf2CompactExpandButton = button
    if fixedHeaderRecord then fixedHeaderRecord.previewExpander = record end
    local window = M.frame
    if window and window.HookScript and not window._msuf2FixedPreviewExpanderSizeHooked then
        window._msuf2FixedPreviewExpanderSizeHooked = true
        window:HookScript("OnSizeChanged", function()
            -- The shell's maximize/minimize driver changes size every render
            -- frame. Its final rebuild owns the one responsive preview commit;
            -- avoid repainting the full renderer against transient geometry.
            if window._msuf2WindowLayoutAnim then return end
            local active = M._msuf2ActiveFixedPreviewExpander
            if active and active.expanded and not active.disposed and type(active.Relayout) == "function" then
                active:Relayout("FIXED_PREVIEW_WINDOW_SIZE")
            end
        end)
    end
    RefreshButton()
    return record
end

function M.CloseFixedPreviewExpander(reason)
    local record = M._msuf2ActiveFixedPreviewExpander
    if not record or type(record.Close) ~= "function" then return false end
    return record:Close(reason or "FIXED_PREVIEW_CLOSE")
end

function M.RefreshPinnedPreviews(scroll)
    local list = M._dockedPreviews
    if type(list) ~= "table" or #list == 0 then return end
    for i = 1, #list do
        local r = list[i]
        if r and r.update and (not scroll or r.scroll == scroll) then r.update() end
    end
end
--- Window hiding is a suspension, not an ownership change: Menu2 keeps its
--- page cache and can reopen the same page instance. Stop rendering the docked
--- previews but retain the live record and hooks, so reopen does not attach
--- another generation of callbacks.
function M.SuspendPinnedPreviews(reason)
    M._msuf2DockedPreviewResumeSerial = (M._msuf2DockedPreviewResumeSerial or 0) + 1
    M.CloseFixedPreviewExpander(reason or "SUSPEND_PINNED_PREVIEWS")
    local list = M._dockedPreviews
    if type(list) ~= "table" then return end
    for i = 1, #list do
        local record = list[i]
        local box = record and record.box
        if record and type(record.restore) == "function" then record.restore(true) end
        if box and box.Hide then box:Hide() end
    end
end
function M.ResumePinnedPreviews(reason)
    local list = M._dockedPreviews
    if type(list) ~= "table" or #list == 0 then return end
    M._msuf2DockedPreviewResumeSerial = (M._msuf2DockedPreviewResumeSerial or 0) + 1
    local serial = M._msuf2DockedPreviewResumeSerial
    local function RefreshAfterShow()
        if M._msuf2DockedPreviewResumeSerial ~= serial then return end
        if M.frame and M.frame.IsShown and not M.frame:IsShown() then return end
        M.RefreshPinnedPreviews()
    end
    RefreshAfterShow()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, RefreshAfterShow)
        C_Timer.After(0.05, RefreshAfterShow)
    end
end
function M.ReleasePinnedPreviews(reason, keepKey, releaseKey)
    local activeExpander = M._msuf2ActiveFixedPreviewExpander
    if activeExpander then
        local activePageKey = activeExpander.pageKey
        local releaseExpander
        if releaseKey ~= nil then
            releaseExpander = activePageKey == releaseKey
        elseif keepKey ~= nil then
            releaseExpander = activePageKey ~= keepKey
        else
            releaseExpander = true
        end
        if releaseExpander and type(activeExpander.Close) == "function" then
            activeExpander:Close(reason or "RELEASE_PINNED_PREVIEWS")
        end
    end
    local list = M._dockedPreviews
    if type(list) ~= "table" then return end
    local writeIndex = 1
    for readIndex = 1, #list do
        local record = list[readIndex]
        local pageKey = record and record.pageKey
        local release
        if releaseKey ~= nil then
            release = pageKey == releaseKey
        elseif keepKey ~= nil then
            release = pageKey ~= keepKey
        else
            release = true
        end
        if release then
            local box = record and record.box
            if record and type(record.restore) == "function" then record.restore("DETACH") end
            if box then
                if box._msuf2PinnedPreviewRecord == record then box._msuf2PinnedPreviewRecord = nil end
                if box._msuf2PinnedPreviewPageKey == pageKey then box._msuf2PinnedPreviewPageKey = nil end
                if box._msuf2PinnedPreviewWrapper == (record and record.pageWrapper) then box._msuf2PinnedPreviewWrapper = nil end
                box._msuf2PinnedFloating = nil
                if box.Hide then box:Hide() end
            end
        else
            list[writeIndex] = record
            writeIndex = writeIndex + 1
        end
    end
    for i = writeIndex, #list do list[i] = nil end
end

-- Cached pages and shared preview boxes may hand ownership back and forth many
-- times during one Menu2 session. Install at most one OnShow hook per host and
-- dispatch through a replaceable record set; otherwise every hand-off leaves a
-- permanent closure on the cached body/wrapper.
local function BindPinnedPreviewShowDispatcher(host, record)
    if not (host and host.HookScript and record) then return nil end
    local dispatcher = host._msuf2PinnedPreviewShowDispatcher
    if not dispatcher then
        dispatcher = { records = {} }
        host._msuf2PinnedPreviewShowDispatcher = dispatcher
        host:HookScript("OnShow", function(self)
            local current = self._msuf2PinnedPreviewShowDispatcher
            local records = current and current.records
            if not records then return end
            for candidate in pairs(records) do
                if candidate and type(candidate.update) == "function" then candidate.update() end
            end
        end)
    end
    dispatcher.records[record] = true
    return dispatcher
end

local function UnbindPinnedPreviewShowDispatchers(record)
    local dispatchers = record and record.showDispatchers
    if type(dispatchers) ~= "table" then return end
    for i = 1, #dispatchers do
        local dispatcher = dispatchers[i]
        if dispatcher and dispatcher.records then dispatcher.records[record] = nil end
    end
    record.showDispatchers = nil
end

-- Coalesce the two ownership-settling checks per shared box. The callbacks
-- always resolve the current record, so an older page can never repaint after
-- a rapid page switch and navigation does not accumulate timer generations.
local function QueuePinnedPreviewSync(box)
    if not box then return end
    local function DispatchCurrent()
        local current = box._msuf2PinnedPreviewRecord
        if current and type(current.update) == "function" then current.update() end
    end
    if not (C_Timer and C_Timer.After) then
        DispatchCurrent()
        return
    end
    if not box._msuf2PinnedPreviewImmediateSyncQueued then
        box._msuf2PinnedPreviewImmediateSyncQueued = true
        C_Timer.After(0, function()
            box._msuf2PinnedPreviewImmediateSyncQueued = nil
            DispatchCurrent()
        end)
    end
    if not box._msuf2PinnedPreviewSettledSyncQueued then
        box._msuf2PinnedPreviewSettledSyncQueued = true
        C_Timer.After(0.05, function()
            box._msuf2PinnedPreviewSettledSyncQueued = nil
            DispatchCurrent()
        end)
    end
end

--- Bind a preview panel to the page that currently owns it.
---
--- The box itself no longer changes layout ownership: its section is registered
--- through W.FixedPreviewSection and the ScrollFrame begins beneath that
--- fixed panel. What remains here is ownership
--- bookkeeping for the preview boxes that are shared across cached pages -
--- which page may show the box, and when it has to let go of it.
function W.AttachPinnedPreview(body, box, opts)
    if not (body and box) then return nil end
    opts = opts or {}
    local scroll = M.scrollFrame
    if not scroll then return nil end
    local pageKey = opts.pageKey or box._msufGFNativePreviewPageKey
    local pageWrapper = opts.wrapper or box._msufGFNativePreviewWrapper
    local record

    -- The title line keeps the full panel width now that no pin button sits in
    -- the top-right corner of the preview card.
    local hint = opts.hint or box.hint or box._hint
    local title = opts.title or box.title or box._title
    if hint and hint.SetPoint then
        hint:ClearAllPoints()
        if title then
            hint:SetPoint("LEFT", title, "RIGHT", 12, 0)
        else
            hint:SetPoint("LEFT", box, "LEFT", 14, 0)
        end
        hint:SetPoint("RIGHT", box, "RIGHT", -12, 0)
        hint:SetJustifyH("LEFT")
    end

    local function Owned()
        if pageKey and M.activeKey and M.activeKey ~= pageKey then return false end
        if M.frame and M.frame.IsShown and not M.frame:IsShown() then return false end
        if pageWrapper and pageWrapper.IsShown and not pageWrapper:IsShown() then return false end
        if body.IsShown and not body:IsShown() then return false end
        return true
    end
    local function Sync()
        if box._msuf2PinnedPreviewRecord ~= record then return end
        if not Owned() then
            if pageKey and box.Hide then box:Hide() end
            return
        end
        if box.Show then box:Show() end
    end
    --- Ownership hand-off. The box stays parented to its docked section, so
    --- releasing is a bookkeeping step; callers decide whether to hide it.
    local function Release(force)
        if not force and box._msuf2PinnedPreviewRecord ~= record then return end
        if force == "DETACH" then UnbindPinnedPreviewShowDispatchers(record) end
        box._msuf2PinnedFloating = nil
    end

    box._msuf2PinnedPreviewPageKey = pageKey
    box._msuf2PinnedPreviewWrapper = pageWrapper
    box._msuf2PinnedFloating = nil
    record = { scroll = scroll, update = Sync, restore = Release, box = box, stateKey = opts.stateKey, pageKey = pageKey, pageWrapper = pageWrapper }
    M._dockedPreviews = M._dockedPreviews or {}
    for i = #M._dockedPreviews, 1, -1 do
        local r = M._dockedPreviews[i]
        if r and r.box == box then  --- same box = this exact page was rebuilt, replace its record
            if r.restore then r.restore("DETACH") end
            table.remove(M._dockedPreviews, i)
        end
    end
    box._msuf2PinnedPreviewRecord = record
    M._dockedPreviews[#M._dockedPreviews + 1] = record
    record.showDispatchers = {}
    local bodyDispatcher = BindPinnedPreviewShowDispatcher(body, record)
    if bodyDispatcher then record.showDispatchers[#record.showDispatchers + 1] = bodyDispatcher end
    -- The docked panel is outside the page wrapper, so the wrapper's own show is
    -- the only event left that marks "this page is the visible one now".
    local wrapperDispatcher = BindPinnedPreviewShowDispatcher(pageWrapper, record)
    if wrapperDispatcher and wrapperDispatcher ~= bodyDispatcher then
        record.showDispatchers[#record.showDispatchers + 1] = wrapperDispatcher
    end
    -- Page selection sets the active key after the build, and restored scroll
    -- positions settle a frame later; re-check once geometry and ownership are
    -- final rather than trusting the first pass.
    QueuePinnedPreviewSync(box)
    return record
end

local function IsNumericLayerControl(label, minValue, maxValue)
    if tonumber(minValue) ~= 0 or tonumber(maxValue) ~= 30 then return false end
    local text = tostring(label or ""):lower()
    if text:find("layer", 1, true) then return true end
    local translatedLayer = tostring(Tr("Layer") or ""):lower()
    if translatedLayer ~= "" and text:find(translatedLayer, 1, true) then return true end
    local frameLevel = tostring(Tr("Frame level") or ""):lower()
    local frameLayer = tostring(Tr("Frame layer") or ""):lower()
    return text == "frame level" or text == "frame layer"
        or (frameLevel ~= "" and text == frameLevel)
        or (frameLayer ~= "" and text == frameLayer)
end

local LAYER_OVERVIEW_SHORTCUT_TEXT = "|cffffffff•|r|cffffffff•|r|cffffffff•|r"
local function AttachLayerOverviewButton(section, slider, title, label, minValue, maxValue)
    if not (section and slider and title and IsNumericLayerControl(label, minValue, maxValue)) then return nil end
    local shortcut = T.Button(section, LAYER_OVERVIEW_SHORTCUT_TEXT, 34, 20, { noSearch = true })
    shortcut:SetPoint("TOPRIGHT", title, "TOPRIGHT", 0, 2)
    shortcut:SetAlpha(0.58)
    shortcut._msuf2SkipHistoryCheckpoint = true
    shortcut._msuf2LayerOverviewButton = true
    AddThreeDotShortcutTextures(shortcut, LAYER_SHORTCUT_DOTS)
    if shortcut.SetFrameLevel and slider.GetFrameLevel then shortcut:SetFrameLevel(slider:GetFrameLevel() + 4) end
    if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(shortcut, slider)
    else shortcut._msuf2ControlPartOf = slider end
    if shortcut.HookScript then
        shortcut:HookScript("OnEnter", function(self) self:SetAlpha(0.96) end)
        shortcut:HookScript("OnLeave", function(self) self:SetAlpha(0.58) end)
    end
    shortcut:SetScript("OnClick", function(self)
        local show = M.ShowLayerOverview or _G.MSUF_ShowLayerOverview
        if type(show) == "function" then show(self) end
    end)
    if shortcut.HookScript then
        shortcut:HookScript("OnHide", function(self)
            local hide = M.HideLayerOverviewForAnchor or _G.MSUF_HideLayerOverviewForAnchor
            if type(hide) == "function" then hide(self) end
        end)
    end
    if type(M.AddTooltip) == "function" then
        M.AddTooltip(shortcut, "Layer overview", "Shows every configurable MSUF layer on the unified 0-30 scale.", { hook = true, owner = "ANCHOR_RIGHT" })
    end
    slider._msuf2LayerShortcutButton = shortcut
    return shortcut
end

--- Slider wraps Blizzard's slider template but hides native art and stamps
--- callbacks so profile writes only happen when the effective value changes.
function W.Slider(section, label, minVal, maxVal, step, width)
    local x, y = NextRow(section, 48)
    local valueGap = 8
    local buttonGap = 4
    local stepButtonW = 20
    local editW = 52
    local minTrackW = 96
    local compactMinTrackW = 48
    local sliderH = 24
    local valueClusterW = valueGap + stepButtonW + buttonGap + editW + buttonGap + stepButtonW
    local compactValueClusterW = valueGap + editW
    width = width or 280
    if section and section._msuf2Width then
        local available = section._msuf2Width - x - 14
        if available > 0 and width > available then width = max(72, available) end
    end
    local title = T.Font(section, "GameFontHighlightSmall", Tr(label or ""), T.colors.text, "control")
    SetSearchText(title, label)
    title:SetPoint("TOPLEFT", x, y)
    title:SetWidth(width)
    title:SetJustifyH("LEFT")
    sliderSerial = sliderSerial + 1
    local slider = CreateFrame("Slider", "MSUF2NativeSlider" .. sliderSerial, section)
    slider._msuf2Title = title
    slider._msuf2ControlKind = "slider"
    RegisterSearchObject(slider, label, "slider", { anchor = title })
    slider:SetPoint("TOPLEFT", x, y - 24)
    slider:SetSize(max(compactMinTrackW, width - valueClusterW), sliderH)
    if slider.EnableMouse then slider:EnableMouse(true) end
    slider:SetMinMaxValues(minVal or 0, maxVal or 1)
    slider:SetValueStep(step or 1)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    -- Steps-per-page 0 disables the engine's own track-click jump; the press is
    -- handled entirely by the cursor-follow drag below.
    if slider.SetStepsPerPage then slider:SetStepsPerPage(0) end
    slider._msuf2CursorDrag = true
    slider._msuf2Step = step or 1
    slider._msuf2RequestedWidth = width
    slider._msuf2MinRowWidth = compactMinTrackW
    HideSliderTemplateParts(slider)
    if T.StyleSlider then T.StyleSlider(slider) end
    local function StepButton(text)
        local btn = T.Button(section, text, 20, 24, { noSearch = true })
        SetSearchText(btn, text)
        if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(btn, slider)
        else btn._msuf2ControlPartOf = slider end
        return T.CenterButtonLabel(btn)
    end
    local minus = StepButton("-")
    local edit = CreateFrame("EditBox", nil, section, "InputBoxTemplate")
    edit:SetSize(52, 24)
    edit:SetAutoFocus(false)
    edit:SetJustifyH("CENTER")
    edit:SetNumeric(false)
    T.SkinEditBox(edit)
    if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(edit, slider)
    else edit._msuf2ControlPartOf = slider end
    slider.editBox = edit
    local plus = StepButton("+")
    slider.minusButton = minus
    slider.plusButton = plus
    slider._msuf2StepButtons = { minus, plus }
    local function UpdateFill()
        local fill = slider._msufFill
        if not fill then return end
        local minV, maxV = slider:GetMinMaxValues()
        local span = maxV - minV
        local pct = span > 0 and ((slider:GetValue() - minV) / span) or 0
        if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
        fill:SetWidth(max(1, max(1, slider:GetWidth() - 2) * pct))
        if slider._msuf2UpdateThumb then slider:_msuf2UpdateThumb() end
    end
    slider._msuf2UpdateFill = UpdateFill
    function slider:_msuf2SetLayoutWidth(totalWidth)
        totalWidth = tonumber(totalWidth) or width or 280
        self._msuf2RowWidth = totalWidth
        local tiny = totalWidth < (compactMinTrackW + compactValueClusterW)
        local compact = tiny or totalWidth < (minTrackW + valueClusterW)
        local clusterW = tiny and 0 or (compact and compactValueClusterW or valueClusterW)
        local trackMin = compact and compactMinTrackW or minTrackW
        local trackW = max(trackMin, floor(totalWidth - clusterW + 0.5))
        if title then
            title:SetWidth(max(trackW, floor(totalWidth + 0.5)))
            if title.SetJustifyH then title:SetJustifyH(self._msuf2TitleJustify or "LEFT") end
        end
        self:SetSize(trackW, sliderH)
        minus:ClearAllPoints()
        if compact then
            minus:Hide()
        else
            minus:Show()
            minus:SetPoint("LEFT", self, "RIGHT", valueGap, 0)
        end
        edit:ClearAllPoints()
        if tiny then
            edit:Hide()
        else
            edit:Show()
            edit:SetPoint("LEFT", compact and self or minus, "RIGHT", compact and valueGap or buttonGap, 0)
        end
        plus:ClearAllPoints()
        if compact then
            plus:Hide()
        else
            plus:Show()
            plus:SetPoint("LEFT", edit, "RIGHT", buttonGap, 0)
        end
        UpdateFill()
    end
    slider:_msuf2SetLayoutWidth(width)
    local function FormatValue(value)
        if type(slider._msuf2ValueFormatter) == "function" then
            local text = slider._msuf2ValueFormatter(value, slider)
            if text ~= nil then return tostring(text) end
        end
        local st = step or 1
        if st < 1 then return string.format("%.2f", value) end
        return tostring(floor(value + 0.5))
    end
    slider._msuf2FormatValue = FormatValue
    function slider:SetValueFormatter(fn)
        self._msuf2ValueFormatter = (type(fn) == "function") and fn or nil
        if not self._msuf2Editing then edit:SetText(FormatValue(self:GetValue())) end
    end
    function slider:SetValueParser(fn)
        self._msuf2ValueParser = (type(fn) == "function") and fn or nil
    end
    function slider:SetInteractionCallbacks(onStart, onStop)
        self._msuf2InteractionStart = type(onStart) == "function" and onStart or nil
        self._msuf2InteractionStop = type(onStop) == "function" and onStop or nil
    end
    slider:HookScript("OnValueChanged", function(self, value)
        UpdateFill()
        if not self._msuf2Editing then edit:SetText(FormatValue(value)) end
    end)
    slider:HookScript("OnShow", function(self)
        HideSliderTemplateParts(self)
        if T.StyleSlider then T.StyleSlider(self) end
        if self._msuf2SetLayoutWidth then
            self:_msuf2SetLayoutWidth(self._msuf2RowWidth or width)
        else
            UpdateFill()
        end
    end)
    edit:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        local v
        if type(slider._msuf2ValueParser) == "function" then
            v = tonumber(slider._msuf2ValueParser(text, slider))
        end
        if v == nil then v = tonumber(text) end
        if v ~= nil then slider:SetValue(v) end
        self:ClearFocus()
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:SetText(FormatValue(slider:GetValue()))
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusGained", function() slider._msuf2Editing = true end)
    edit:SetScript("OnEditFocusLost", function(self)
        slider._msuf2Editing = nil
        self:SetText(FormatValue(slider:GetValue()))
    end)
    local function ClampToSlider(value)
        local minV, maxV = slider:GetMinMaxValues()
        if value < minV then value = minV elseif value > maxV then value = maxV end
        local st = tonumber(slider._msuf2Step) or 1
        if st > 0 then value = minV + (floor(((value - minV) / st) + 0.5) * st) end
        if value < minV then value = minV elseif value > maxV then value = maxV end
        return value
    end
    local function StepMultiplier()
        if IsControlKeyDown and IsControlKeyDown() then return 10 end
        if IsShiftKeyDown and IsShiftKeyDown() then return 5 end
        return 1
    end
    local function StepBy(direction)
        if slider.IsEnabled and not slider:IsEnabled() then return end
        local amount = (tonumber(slider._msuf2Step) or 1) * StepMultiplier() * direction
        slider:SetValue(ClampToSlider((tonumber(slider:GetValue()) or 0) + amount))
    end
    local function SliderValueFromCursor()
        if not (GetCursorPosition and slider.GetLeft and slider.GetWidth and slider.GetMinMaxValues) then return nil end
        local left = slider:GetLeft()
        local width = slider:GetWidth()
        if not left or not width or width <= 0 then return nil end
        local cursorX = GetCursorPosition()
        local scale = (slider.GetEffectiveScale and slider:GetEffectiveScale()) or 1
        if not scale or scale == 0 then scale = 1 end
        local pct = ((cursorX / scale) - left) / width
        if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
        local minV, maxV = slider:GetMinMaxValues()
        minV = tonumber(minV) or 0
        maxV = tonumber(maxV) or minV
        return ClampToSlider(minV + ((maxV - minV) * pct))
    end
    local function SetValueFromCursor()
        if slider.IsEnabled and not slider:IsEnabled() then return end
        local value = SliderValueFromCursor()
        if value ~= nil and value ~= tonumber(slider:GetValue()) then
            slider:SetValue(value)
            if slider._msuf2UpdateFill then slider:_msuf2UpdateFill() end
        end
    end
    local function StopSliderInteraction()
        local wasActive = slider._msuf2SliderActive == true
        slider:SetScript("OnUpdate", nil)
        slider._msuf2SliderActive = nil
        if type(slider._msuf2CommitSliderHistory) == "function" then slider:_msuf2CommitSliderHistory() end
        if wasActive and type(slider._msuf2InteractionStop) == "function" then
            slider:_msuf2InteractionStop(slider:GetValue())
        end
        if T.StyleSlider then T.StyleSlider(slider) end
    end
    -- The styled thumb is only a texture, so the engine never runs its own
    -- thumb drag: the press must keep following the cursor until release
    -- instead of jumping once on the down-click.
    local function FollowCursorWhileHeld()
        if not slider._msuf2SliderActive then
            slider:SetScript("OnUpdate", nil)
            return
        end
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            StopSliderInteraction()
            return
        end
        SetValueFromCursor()
    end
    slider:SetScript("OnMouseDown", function(_, button)
        if button and button ~= "LeftButton" then return end
        if slider.IsEnabled and not slider:IsEnabled() then return end
        if type(slider._msuf2BeginSliderHistory) == "function" then slider:_msuf2BeginSliderHistory() end
        slider._msuf2SliderActive = true
        if type(slider._msuf2InteractionStart) == "function" then
            slider:_msuf2InteractionStart(slider:GetValue())
        end
        SetValueFromCursor()
        slider:SetScript("OnUpdate", FollowCursorWhileHeld)
    end)
    slider:SetScript("OnMouseUp", function(_, button)
        if button and button ~= "LeftButton" then return end
        StopSliderInteraction()
    end)
    slider:HookScript("OnHide", StopSliderInteraction)
    slider:EnableMouseWheel(true)
    if slider.SetPropagateMouseWheel then slider:SetPropagateMouseWheel(true) end
    slider:SetScript("OnMouseWheel", function(self, delta)
        if not delta or delta == 0 then return end
        if IsShiftKeyDown and IsShiftKeyDown() then
            if self.SetPropagateMouseWheel then self:SetPropagateMouseWheel(false) end
            StepBy(delta > 0 and 1 or -1)
        elseif self.SetPropagateMouseWheel then
            self:SetPropagateMouseWheel(true)
        else
            local scroll = M.scrollFrame
            local handler = scroll and scroll.GetScript and scroll:GetScript("OnMouseWheel")
            if type(handler) == "function" then handler(scroll, delta) end
        end
    end)
    minus:SetScript("OnClick", function() StepBy(-1) end)
    plus:SetScript("OnClick", function() StepBy(1) end)
    AttachLayerOverviewButton(section, slider, title, label, minVal, maxVal)
    return slider
end
function W.Segment(section, label, values, width)
    local x, y = NextRow(section, 48)
    local title = T.Font(section, "GameFontHighlightSmall", label or "", T.colors.text, "control")
    SetSearchText(title, label)
    title:SetPoint("TOPLEFT", x, y)
    local holder = CreateFrame("Frame", nil, section)
    RegisterSearchObject(holder, label, "segment", { anchor = title, values = values })
    holder:SetPoint("TOPLEFT", x, y - 24)
    holder:SetSize(width or 360, 24)
    holder._msuf2ControlKind = "segment"
    holder._msuf2Title = title
    holder.buttons = {}
    holder.values = values or {}
    local count = #holder.values
    local gap = 8
    local bw = count > 0 and math.floor(((width or 360) - gap * (count - 1)) / count) or 80
    for i = 1, count do
        local item = holder.values[i]
        local btn = T.Button(holder, item.text or tostring(item.value), bw, 24)
        -- A Segment is one logical control. Its option buttons are visual
        -- parts and must not become duplicate catalog records.
        if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(btn, holder)
        else btn._msuf2ControlPartOf = holder end
        btn:SetPoint("LEFT", holder, "LEFT", (i - 1) * (bw + gap), 0)
        btn._msuf2Value = item.value
        holder.buttons[i] = btn
    end
    function holder:SetValue(value)
        self.value = value
        for i = 1, #self.buttons do
            local btn = self.buttons[i]
            btn:SetActive(btn._msuf2Value == value)
        end
    end
    function holder:GetValue()
        return self.value
    end
    return holder
end

--- Shared page-tab binder for cold Menu2 UI state; no combat/runtime path.
function W.SegmentTabs(ctx, parent, opts)
    opts = opts or {}
    local frames, allowed = opts.frames or {}, opts.allowed
    if not allowed then
        allowed = {}
        local values = opts.values or {}
        for i = 1, #values do allowed[values[i].value] = true end
    end
    local defaultTab = opts.defaultTab or opts.default or "main"
    local segment
    local function CurrentTab() local tab = opts.get and opts.get() or (opts.stateKey and M[opts.stateKey]) or defaultTab; return allowed[tab] and tab or defaultTab end
    local function RefreshTabs()
        local tab = CurrentTab()
        for key, frame in pairs(frames) do
            if frame and frame.SetShown then frame:SetShown(key == tab) end
        end
        if segment and segment.SetValue then segment:SetValue(tab) end
        if opts.afterRefresh then opts.afterRefresh(tab) end
    end
    local function SetTab(tab)
        tab = allowed[tab] and tab or defaultTab
        if opts.set then opts.set(tab)
        elseif opts.stateKey then
            M.SetMenuStateValue(opts.stateKey, tab)
        end
        RefreshTabs()
        if opts.afterSet then opts.afterSet(tab) end
    end
    segment = W.Segment(parent, opts.label, opts.values, opts.width)
    W.MoveWidget(segment, parent, opts.x or 0, opts.y or 0, opts.width, opts.titleJustify or "LEFT")
    M.BindSegment(ctx, segment, CurrentTab, SetTab)
    M.TrackRefresh(ctx, RefreshTabs)
    return segment, RefreshTabs, CurrentTab, SetTab
end
local function TextInputEscape(self) self:ClearFocus() end
local function TextInputEnter(self)
    if self._msuf2OnCommit then self._msuf2OnCommit(self:GetText() or "") end
    self:ClearFocus()
end
local function TextInputBlur(self)
    if self._msuf2CommitOnBlur and self._msuf2OnCommit then self._msuf2OnCommit(self:GetText() or "") end
end
local function TextInputSetOnValueCommitted(self, fn) self._msuf2OnCommit = fn end

--- Text inputs commit on Enter or focus loss; callers attach the actual profile
--- write through SetOnValueCommitted.
function W.TextInput(section, label, width)
    local x, y = NextRow(section, 48)
    width = width or 260
    local title = T.Font(section, "GameFontHighlightSmall", Tr(label or ""), T.colors.text, "control")
    SetSearchText(title, label)
    title:SetPoint("TOPLEFT", x, y)
    local edit = CreateFrame("EditBox", nil, section, "InputBoxTemplate")
    edit._msuf2Title = title
    edit._msuf2ControlKind = "textinput"
    RegisterSearchObject(edit, label, "textinput", { anchor = title })
    edit:SetPoint("TOPLEFT", x, y - 24)
    edit:SetSize(width, 24)
    edit:SetAutoFocus(false)
    edit:SetJustifyH("LEFT")
    edit:SetMaxLetters(200000)
    T.SkinEditBox(edit)
    edit.SetOnValueCommitted = TextInputSetOnValueCommitted
    edit:SetScript("OnEscapePressed", TextInputEscape)
    edit:SetScript("OnEnterPressed", TextInputEnter)
    edit:SetScript("OnEditFocusLost", TextInputBlur)
    return edit
end
local function ColorSetRGB(self, r, g, b)
    self._msuf2R = tonumber(r) or 1
    self._msuf2G = tonumber(g) or 1
    self._msuf2B = tonumber(b) or 1
    if self._msuf2Swatch.SetColorTexture then
        self._msuf2Swatch:SetColorTexture(self._msuf2R, self._msuf2G, self._msuf2B, 1)
    else
        self._msuf2Swatch:SetVertexColor(self._msuf2R, self._msuf2G, self._msuf2B, 1)
    end
    local mirrors = self._msuf2ColorMirrors
    for i = 1, #(mirrors or {}) do mirrors[i](self._msuf2R, self._msuf2G, self._msuf2B) end
end
local function ColorGetRGB(self) return self._msuf2R or 1, self._msuf2G or 1, self._msuf2B or 1 end
local function ColorSetOnColorChanged(self, fn) self._msuf2OnColorChanged = fn end
local colorPickerPlus
local function ClampColor(value)
    value = tonumber(value) or 0
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end
local function ColorByte(value) return floor(ClampColor(value) * 255 + 0.5) end
local function ColorHex(r, g, b)
    return string.format("#%02X%02X%02X", ColorByte(r), ColorByte(g), ColorByte(b))
end
local function HexColor(value)
    local hex = tostring(value or ""):match("^%s*#?(%x%x%x%x%x%x)%s*$")
    if not hex then return nil end
    return (tonumber(hex:sub(1, 2), 16) or 255) / 255,
           (tonumber(hex:sub(3, 4), 16) or 255) / 255,
           (tonumber(hex:sub(5, 6), 16) or 255) / 255
end
local function ColorPickerPlusStore()
    local db = type(M.EnsureDB) == "function" and M.EnsureDB() or _G.MSUF_DB
    if type(db) ~= "table" then return nil end
    db.menu2ColorPicker = type(db.menu2ColorPicker) == "table" and db.menu2ColorPicker or {}
    local store = db.menu2ColorPicker
    store.saved = type(store.saved) == "table" and store.saved or {}
    return store
end
local function AddRecentColor(hex)
    local store = ColorPickerPlusStore()
    if not store or not hex then return end
    store.recent = type(store.recent) == "table" and store.recent or {}
    for i = #store.recent, 1, -1 do
        if store.recent[i] == hex then table.remove(store.recent, i) end
    end
    table.insert(store.recent, 1, hex)
    while #store.recent > 9 do table.remove(store.recent) end
end
local function PickerPlusApply(r, g, b)
    local picker = _G.ColorPickerFrame
    if not picker then return end
    picker:SetColorRGB(ClampColor(r), ClampColor(g), ClampColor(b))
    if picker._msuf2ColorOwner then
        local nr, ng, nb = picker:GetColorRGB()
        picker._msuf2ColorOwner:SetRGB(nr, ng, nb)
        if picker._msuf2ColorOwner._msuf2OnColorChanged then
            picker._msuf2ColorOwner._msuf2OnColorChanged(nr, ng, nb)
        end
    end
    if colorPickerPlus and colorPickerPlus.Refresh then colorPickerPlus:Refresh() end
end
local function PickerPlusInput(parent, width, numeric)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetSize(width, 22)
    edit:SetAutoFocus(false)
    edit:SetJustifyH("CENTER")
    edit:SetMaxLetters(numeric and 3 or 7)
    if edit.SetNumeric then edit:SetNumeric(numeric and true or false) end
    if T and T.SkinEditBox then T.SkinEditBox(edit) end
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); if colorPickerPlus then colorPickerPlus:Refresh() end end)
    edit:SetScript("OnEnterPressed", function(self)
        if type(self._msuf2Commit) == "function" then self:_msuf2Commit() end
        self:ClearFocus()
    end)
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput and type(self._msuf2LiveCommit) == "function" then self:_msuf2LiveCommit() end
    end)
    return edit
end
local function PickerPlusSwatch(parent, size, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local edge = btn:CreateTexture(nil, "BACKGROUND")
    edge:SetPoint("TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(0.32, 0.42, 0.58, 0.9)
    local fill = btn:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetColorTexture(1, 1, 1, 1)
    btn._msuf2Fill = fill
    btn:SetScript("OnClick", onClick)
    return btn
end
local function EnsureColorPickerPlus()
    if colorPickerPlus or not _G.ColorPickerFrame then return colorPickerPlus end
    local picker = _G.ColorPickerFrame
    local panel = (T and T.Panel and T.Panel(picker, nil, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft))
        or CreateFrame("Frame", nil, picker, "BackdropTemplate")
    colorPickerPlus = panel
    panel:SetSize(344, 482)
    panel:SetPoint("TOPLEFT", picker, "TOPRIGHT", 8, 0)
    if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
    panel:SetFrameStrata(picker:GetFrameStrata())
    panel:SetFrameLevel((picker:GetFrameLevel() or 1) + 20)
    if T and T.ApplySurface then T.ApplySurface(panel, "popup") end

    local title = T.Font(panel, "GameFontNormalLarge", Tr("Precision color editor"), T.colors.text, "heading")
    title:SetPoint("TOPLEFT", 16, -14)
    local target = T.Font(panel, "GameFontHighlightSmall", "", T.colors.muted, "supporting")
    target:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    target:SetWidth(310)
    target:SetJustifyH("LEFT")
    panel._msuf2Target = target

    local original = panel:CreateTexture(nil, "ARTWORK")
    original:SetPoint("TOPLEFT", 16, -62)
    original:SetSize(151, 34)
    local current = panel:CreateTexture(nil, "ARTWORK")
    current:SetPoint("TOPRIGHT", -16, -62)
    current:SetSize(151, 34)
    panel._msuf2Original, panel._msuf2Current = original, current
    local oldLabel = T.Font(panel, "GameFontDisableSmall", Tr("Original"), T.colors.dim)
    oldLabel:SetPoint("BOTTOMLEFT", original, "TOPLEFT", 0, 2)
    local newLabel = T.Font(panel, "GameFontDisableSmall", Tr("Current"), T.colors.dim)
    newLabel:SetPoint("BOTTOMRIGHT", current, "TOPRIGHT", 0, 2)

    local rgbLabel = T.Font(panel, "GameFontNormalSmall", "RGB", T.colors.muted)
    rgbLabel:SetPoint("TOPLEFT", 16, -108)
    local fields = {}
    for i, label in ipairs({ "R", "G", "B" }) do
        local field = PickerPlusInput(panel, 58, true)
        field:SetPoint("TOPLEFT", 52 + (i - 1) * 66, -104)
        local fs = T.Font(panel, "GameFontDisableSmall", label, T.colors.dim)
        fs:SetPoint("RIGHT", field, "LEFT", -3, 0)
        fields[i] = field
        field._msuf2Commit = function()
            local pickerFrame = _G.ColorPickerFrame
            if not pickerFrame then return end
            local r, g, b = pickerFrame:GetColorRGB()
            local values = { ColorByte(r), ColorByte(g), ColorByte(b) }
            values[i] = min(255, max(0, tonumber(field:GetText()) or values[i]))
            PickerPlusApply(values[1] / 255, values[2] / 255, values[3] / 255)
        end
        field._msuf2LiveCommit = function()
            if tonumber(field:GetText()) then field:_msuf2Commit() end
        end
    end
    panel._msuf2RGB = fields
    local hexLabel = T.Font(panel, "GameFontNormalSmall", "HEX", T.colors.muted)
    hexLabel:SetPoint("TOPLEFT", 16, -140)
    local hex = PickerPlusInput(panel, 118, false)
    hex:SetPoint("TOPLEFT", 52, -136)
    hex._msuf2Commit = function(self)
        local r, g, b = HexColor(self:GetText())
        if r then PickerPlusApply(r, g, b) elseif colorPickerPlus then colorPickerPlus:Refresh() end
    end
    hex._msuf2LiveCommit = function(self)
        local r, g, b = HexColor(self:GetText())
        if r then PickerPlusApply(r, g, b) end
    end
    panel._msuf2Hex = hex
    local copy = T.Button(panel, Tr("Copy"), 68, 22)
    copy:SetPoint("LEFT", hex, "RIGHT", 8, 0)
    copy:SetScript("OnClick", function()
        hex:SetFocus()
        hex:HighlightText()
    end)
    local save = T.Button(panel, Tr("Save"), 68, 22)
    save:SetPoint("LEFT", copy, "RIGHT", 6, 0)
    save:SetScript("OnClick", function()
        local store = ColorPickerPlusStore()
        local pickerFrame = _G.ColorPickerFrame
        if not (store and pickerFrame) then return end
        local r, g, b = pickerFrame:GetColorRGB()
        local value = ColorHex(r, g, b)
        for i = 1, #store.saved do if store.saved[i] == value then return end end
        if #store.saved < 27 then store.saved[#store.saved + 1] = value end
        panel:RefreshPalettes()
    end)

    local recentTitle = T.Font(panel, "GameFontNormalSmall", Tr("Recent"), T.colors.text)
    recentTitle:SetPoint("TOPLEFT", 16, -176)
    local savedTitle = T.Font(panel, "GameFontNormalSmall", Tr("Saved colors"), T.colors.text)
    savedTitle:SetPoint("TOPLEFT", 16, -230)
    local savedHint = T.Font(panel, "GameFontDisableSmall", Tr("Right-click a saved color to remove it."), T.colors.dim)
    savedHint:SetPoint("TOPRIGHT", -16, -230)
    panel._msuf2RecentButtons, panel._msuf2SavedButtons = {}, {}
    for i = 1, 9 do
        local btn = PickerPlusSwatch(panel, 24, function(self)
            local r, g, b = HexColor(self._msuf2Hex)
            if r then PickerPlusApply(r, g, b) end
        end)
        btn:SetPoint("TOPLEFT", 16 + (i - 1) * 34, -194)
        panel._msuf2RecentButtons[i] = btn
    end
    for i = 1, 27 do
        local col, row = (i - 1) % 9, floor((i - 1) / 9)
        local btn = PickerPlusSwatch(panel, 24, function(self, button)
            local store = ColorPickerPlusStore()
            if button == "RightButton" and store then
                table.remove(store.saved, self._msuf2Index)
                panel:RefreshPalettes()
                return
            end
            local r, g, b = HexColor(self._msuf2Hex)
            if r then PickerPlusApply(r, g, b) end
        end)
        btn._msuf2Index = i
        btn:SetPoint("TOPLEFT", 16 + col * 34, -250 - row * 31)
        panel._msuf2SavedButtons[i] = btn
    end

    local classTitle = T.Font(panel, "GameFontNormalSmall", Tr("Class colors"), T.colors.text)
    classTitle:SetPoint("TOPLEFT", 16, -354)
    panel._msuf2ClassButtons = {}
    local tokens = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER" }
    for i = 1, #tokens do
        local col, row = (i - 1) % 7, floor((i - 1) / 7)
        local token = tokens[i]
        local btn = PickerPlusSwatch(panel, 28, function(self)
            local c = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[self._msuf2Token]
            if c then PickerPlusApply(c.r, c.g, c.b) end
        end)
        btn._msuf2Token = token
        btn:SetPoint("TOPLEFT", 16 + col * 44, -374 - row * 34)
        if M.AddTooltip then M.AddTooltip(btn, token:gsub("DEATHKNIGHT", "Death Knight"):gsub("DEMONHUNTER", "Demon Hunter"), Tr("Apply this class color.")) end
        panel._msuf2ClassButtons[i] = btn
    end
    local note = T.Font(panel, "GameFontDisableSmall", Tr("Opacity remains beside the setting when that element supports it."), T.colors.dim)
    note:SetPoint("BOTTOMLEFT", 16, 14)
    note:SetWidth(312)

    function panel:RefreshPalettes()
        local store = ColorPickerPlusStore() or {}
        local function RefreshButtons(buttons, values)
            values = type(values) == "table" and values or {}
            for i = 1, #buttons do
                local btn, value = buttons[i], values[i]
                btn._msuf2Hex = value
                btn:SetShown(value ~= nil)
                if value then
                    local r, g, b = HexColor(value)
                    btn._msuf2Fill:SetColorTexture(r or 1, g or 1, b or 1, 1)
                end
            end
        end
        RefreshButtons(self._msuf2RecentButtons, store.recent)
        RefreshButtons(self._msuf2SavedButtons, store.saved)
        for i = 1, #self._msuf2ClassButtons do
            local btn = self._msuf2ClassButtons[i]
            local c = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[btn._msuf2Token]
            btn._msuf2Fill:SetColorTexture(c and c.r or 1, c and c.g or 1, c and c.b or 1, 1)
        end
    end
    function panel:Refresh()
        local pickerFrame = _G.ColorPickerFrame
        local owner = pickerFrame and pickerFrame._msuf2ColorOwner
        if not (pickerFrame and owner) then return end
        local r, g, b = pickerFrame:GetColorRGB()
        self._msuf2Current:SetColorTexture(r, g, b, 1)
        self._msuf2Original:SetColorTexture(owner._msuf2PrevR or r, owner._msuf2PrevG or g, owner._msuf2PrevB or b, 1)
        self._msuf2Target:SetText(Tr(owner._msuf2ColorLabel or owner._msuf2SearchText or "Selected color"))
        if not self._msuf2Hex:HasFocus() then self._msuf2Hex:SetText(ColorHex(r, g, b)) end
        local bytes = { ColorByte(r), ColorByte(g), ColorByte(b) }
        for i = 1, 3 do if not self._msuf2RGB[i]:HasFocus() then self._msuf2RGB[i]:SetText(bytes[i]) end end
        self:RefreshPalettes()
    end
    function panel:LayoutBesidePicker()
        local pickerFrame = _G.ColorPickerFrame
        if not pickerFrame then return end
        local uiW = _G.UIParent and _G.UIParent.GetWidth and _G.UIParent:GetWidth()
        local pickerRight = pickerFrame.GetRight and pickerFrame:GetRight()
        self:ClearAllPoints()
        if uiW and pickerRight and pickerRight + 352 > uiW then
            self:SetPoint("TOPRIGHT", pickerFrame, "TOPLEFT", -8, 0)
        else
            self:SetPoint("TOPLEFT", pickerFrame, "TOPRIGHT", 8, 0)
        end
    end
    panel:Hide()
    return panel
end
local function ColorApply(btn, r, g, b)
    btn:SetRGB(r, g, b)
    if btn._msuf2OnColorChanged then btn._msuf2OnColorChanged(r, g, b) end
    if colorPickerPlus and colorPickerPlus:IsShown() then colorPickerPlus:Refresh() end
end
local function ColorPickerCommit()
    local picker, btn = ColorPickerFrame, ColorPickerFrame and ColorPickerFrame._msuf2ColorOwner
    if not (picker and btn) then return end
    local r, g, b = picker:GetColorRGB()
    ColorApply(btn, r, g, b)
end
local function ColorPickerCancel(prev)
    local btn = ColorPickerFrame and ColorPickerFrame._msuf2ColorOwner
    if not btn then return end
    local r, g, b = btn._msuf2PrevR or 1, btn._msuf2PrevG or 1, btn._msuf2PrevB or 1
    if type(prev) == "table" then r, g, b = prev.r or r, prev.g or g, prev.b or b end
    if ColorPickerFrame then ColorPickerFrame._msuf2ColorCancelled = true end
    ColorApply(btn, r, g, b)
end
local colorPickerHideHooked = false
local function EnsureColorPickerHideHook()
    if colorPickerHideHooked or not (ColorPickerFrame and ColorPickerFrame.HookScript) then return end
    colorPickerHideHooked = true
    ColorPickerFrame:HookScript("OnHide", function(self)
        local btn = self and self._msuf2ColorOwner
        if btn and not self._msuf2ColorCancelled then
            local r, g, b = btn:GetRGB()
            AddRecentColor(ColorHex(r, g, b))
        end
        self._msuf2ColorCancelled = nil
        if colorPickerPlus then colorPickerPlus:Hide() end
        if btn and type(btn._msuf2CommitColorInteraction) == "function" then
            btn:_msuf2CommitColorInteraction()
        end
    end)
end
function W.CloseMenuOwnedColorPicker()
    if colorPickerPlus and colorPickerPlus.Hide then colorPickerPlus:Hide() end
    local picker = _G.ColorPickerFrame
    if not (picker and picker._msuf2ColorOwner) then return false end
    if picker.Hide then picker:Hide() end
    picker._msuf2ColorOwner = nil
    return true
end
local function ColorButtonOnClick(self)
    if W and type(W.OpenColorContextPicker) == "function" then
        W.OpenColorContextPicker(
            self._msuf2ColorContextTitle or self._msuf2ColorLabel,
            self._msuf2ColorContextOwners or { self },
            self._msuf2ColorContextNote,
            self
        )
        return
    end
    if not ColorPickerFrame then return end
    local r, g, b = self:GetRGB()
    local picker = ColorPickerFrame
    EnsureColorPickerHideHook()
    if picker._msuf2ColorOwner and picker._msuf2ColorOwner ~= self and type(picker._msuf2ColorOwner._msuf2CommitColorInteraction) == "function" then
        picker._msuf2ColorOwner:_msuf2CommitColorInteraction()
    end
    picker._msuf2ColorOwner = self
    picker._msuf2ColorCancelled = nil
    if type(self._msuf2BeginColorInteraction) == "function" then self:_msuf2BeginColorInteraction() end
    self._msuf2PrevR, self._msuf2PrevG, self._msuf2PrevB = r, g, b
    if picker.SetupColorPickerAndShow then
        picker:SetupColorPickerAndShow({
            r = r, g = g, b = b, opacity = 1, hasOpacity = false,
            swatchFunc = ColorPickerCommit,
            cancelFunc = ColorPickerCancel,
            previousValues = { r = r, g = g, b = b, opacity = 1 },
        })
    else
        picker.func, picker.cancelFunc = ColorPickerCommit, ColorPickerCancel
        picker:SetColorRGB(r, g, b)
        picker:Show()
    end
    local plus = EnsureColorPickerPlus()
    if plus then plus:LayoutBesidePicker(); plus:Show(); plus:Refresh() end
end

--- Color buttons use Blizzard's shared ColorPickerFrame but keep previous RGB
--- values on the button so cancel can restore the UI state.
function W.Color(section, label)
    local x, y = NextRow(section, 32)
    local title = T.Font(section, "GameFontHighlightSmall", Tr(label or ""), T.colors.text, "control")
    SetSearchText(title, label)
    title:SetPoint("TOPLEFT", x, y)
    title:SetWidth(230)
    local btn = CreateFrame("Button", nil, section)
    btn._msuf2Title = title
    btn._msuf2ColorLabel = label
    btn._msuf2ControlKind = "color"
    RegisterSearchObject(btn, label, "color", { anchor = title })
    btn:SetPoint("TOPLEFT", x + 250, y + 2)
    btn:SetSize(44, 20)
    btn._msuf2Swatch, btn._msuf2Edge = T.CreateSuperellipseLayers(btn, "_msuf2Color", 1, "ARTWORK", "ARTWORK")
    btn._msuf2Edge:SetVertexColor(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.75)
    btn.SetRGB = ColorSetRGB
    btn.GetRGB = ColorGetRGB
    btn.SetOnColorChanged = ColorSetOnColorChanged
    btn:SetRGB(1, 1, 1)
    btn:SetScript("OnClick", ColorButtonOnClick)
    return btn
end
