--- Shell/Menu2/MSUF_Menu2_Widgets.lua
--- Shared Menu2 widget factory.
---
--- Pages should compose controls through this module instead of constructing
--- raw frames ad hoc. Widgets also register search metadata, edit-mode preview
--- focus hooks, collapse state, pinned previews, and enable gates, so adding a
--- new control here keeps cross-page behavior consistent.

local addonName, MSUF = ...
MSUF = MSUF or {}
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
local sliderSerial = 0
local Tr = M.TranslateText or function(text) return text end
local EM2Util = (_G.MSUF_EM2 and _G.MSUF_EM2.Util) or {}
local function ThemeColor(name, fallback)
    local c = T and T.colors and T.colors[name]
    return c or fallback
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
local function QueuePinnedPreviewGeometryRefresh(scroll)
    scroll = scroll or M.scrollFrame
    local list = M._pinnedPreviews
    if not scroll or type(list) ~= "table" or #list == 0 then return end
    scroll._msuf2PinnedPreviewLastOffset = nil
    scroll._msuf2PinnedPreviewLastHeight = nil
    scroll._msuf2PinnedPreviewLastChildHeight = nil
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
local function ScrollToCollapsibleEntry(entry)
    local outer = entry and entry.outer
    local scroll = M.scrollFrame
    local child = M.scrollChild
    if not (outer and scroll and child and outer.GetTop and child.GetTop and scroll.SetVerticalScroll) then return false end
    local childTop = child:GetTop()
    local outerTop = outer:GetTop()
    if not (childTop and outerTop) then return false end
    scroll:SetVerticalScroll(max(0, floor((childTop - outerTop) + 0.5) - 12))
    if scroll._msuf2RefreshScrollBar then scroll:_msuf2RefreshScrollBar() end
    return true
end
local function FlashCollapsibleHeader(entry)
    local header = entry and entry.header
    if not header then return end
    if not entry._msuf2FocusFlash then
        local flash = header:CreateTexture(nil, "OVERLAY")
        flash:SetAllPoints()
        local c = T.colors.accent or ThemeColor("coreBlue", { 0.060, 0.250, 0.390, 1.00 })
        flash:SetColorTexture(c[1], c[2], c[3], 0.18)
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
    if not section then
        CloseAutoFocusedSections(pageKey)
        return false
    end
    ExportPublic("MSUF_EM2_MenuFocusSection", section)
    local focused = W.FocusCollapsibleSection(section, opts)
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
    function b:RelayoutCollapsibles()
        self._msuf2RelayoutPending = nil
        if not self._collapsibleStartY then return end
        local y = self._collapsibleStartY
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
                    end
                    y = y - h - (entry.gap or 12)
                end
            elseif entry.kind == "spacer" then
                y = y - (entry.height or 10)
            else
                local open = entry.open and true or false
                local outerH = entry.headerHeight + (open and entry.contentHeight or 0)
                local key = tostring(self.parent) .. "\030" .. tostring(self.x) .. "\030" .. tostring(y)
                    .. "\030" .. tostring(outerH) .. "\030" .. tostring(open)
                if entry._msuf2RelayoutKey ~= key then
                    entry._msuf2RelayoutKey = key
                    entry.outer:ClearAllPoints()
                    entry.outer:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, y)
                    entry.outer:SetHeight(outerH)
                end
                if entry.body._msuf2ShownState ~= open then
                    entry.body._msuf2ShownState = open
                    entry.body:SetShown(open)
                end
                if entry.body.SetAlpha and not entry._msuf2MotionActive then entry.body:SetAlpha(1) end
                T.ApplyCollapseVisual(entry.arrow, entry.hint, open)
                if entry._msuf2RefreshHeaderTone then entry._msuf2RefreshHeaderTone(false) end
                if entry._msuf2RefreshState then entry._msuf2RefreshState(entry) end
                if entry._msuf2RefreshColorSwatchVisibility then entry._msuf2RefreshColorSwatchVisibility() end
                NotifyCollapsibleSectionState(entry, open)
                y = y - entry.outer:GetHeight() - 8
            end
        end
        self.y = y
        UpdateContentHeight(math.abs(y) + 42)
        QueuePinnedPreviewGeometryRefresh(M.scrollFrame)
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
        local stateKey = tostring(ctx.key or "page") .. ":" .. sectionId
        local saved = M.accordionState[stateKey]
        local open = (saved == nil) and (defaultOpen and true or false) or (saved and true or false)
        local headerH = 28
        if not self._collapsibleStartY then self._collapsibleStartY = self.y end
        local outer = T.Panel(self.parent, nil, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft)
        outer._msuf2NoPanelNeon = true
        T.ApplySurface(outer, "card")
        SetSearchTitle(outer, title)
        RegisterSearchObject(outer, title, "section")
        outer:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, self.y)
        outer:SetSize(self.width, headerH + (open and (height or 120) or 0))
        local header = CreateFrame("Button", nil, outer)
        SetSearchTitle(header, title)
        header:SetPoint("TOPLEFT", outer, "TOPLEFT", 0, 0)
        header:SetPoint("TOPRIGHT", outer, "TOPRIGHT", 0, 0)
        header:SetHeight(headerH)
        local headerBg = header:CreateTexture(nil, "BACKGROUND")
        headerBg:SetAllPoints()
        local headerSurface = ThemeColor("coreSurface", { 0.014, 0.038, 0.072, 1.00 })
        local headerRaised = ThemeColor("coreRaised", { 0.026, 0.070, 0.110, 1.00 })
        headerBg:SetColorTexture(headerSurface[1], headerSurface[2], headerSurface[3], 0.34)
        local headerHover = header:CreateTexture(nil, "HIGHLIGHT")
        headerHover:SetAllPoints()
        headerHover:SetColorTexture(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.045)
        local arrow = header:CreateTexture(nil, "OVERLAY")
        arrow:SetSize(10, 10)
        arrow:SetPoint("LEFT", header, "LEFT", 12, 0)
        arrow:SetTexture(T.media.collapseArrow)
        local label = T.Font(header, "GameFontNormal", Tr(title or ""), T.colors.text, "section")
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
        local entry = {
            outer = outer,
            header = header,
            headerBg = headerBg,
            headerHover = headerHover,
            body = body,
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
        local function RefreshHeaderTone(hover)
            if not headerBg.SetColorTexture then return end
            if entry.open then
                headerBg:SetColorTexture(headerSurface[1], headerSurface[2], headerSurface[3], hover and 0.48 or 0.40)
            elseif hover then
                headerBg:SetColorTexture(headerRaised[1], headerRaised[2], headerRaised[3], 0.42)
            else
                headerBg:SetColorTexture(headerSurface[1], headerSurface[2], headerSurface[3], 0.34)
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
            if W.FocusCollapsibleSection(body, { flash = true }) then ConsumeMenuFocusRequest(focusReq) end
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
local function TopButtonStyle(bg, border, textColor, hoverBg, hoverBorder)
    return {
        bg = bg, border = border, textColor = textColor,
        hoverBg = hoverBg, hoverBorder = hoverBorder,
        activeBg = bg, activeBorder = border, activeTextColor = textColor,
    }
end
local TOP_CORE_SHADOW = ThemeColor("coreShadow", { 0.006, 0.016, 0.032, 1.00 })
local TOP_CORE_SURFACE = ThemeColor("coreSurface", { 0.014, 0.038, 0.072, 1.00 })
local TOP_CORE_RIM = ThemeColor("coreRim", { 0.043, 0.096, 0.150, 1.00 })
local TOP_CORE_BLUE = ThemeColor("coreBlue", { 0.060, 0.250, 0.390, 1.00 })
local TOP_ACTION_BUTTON_STYLE = TopButtonStyle(WithAlpha(TOP_CORE_SHADOW, 0.82), WithAlpha(TOP_CORE_RIM, 0.46), { 0.82, 0.90, 1.00, 0.96 }, WithAlpha(TOP_CORE_SURFACE, 0.86), WithAlpha(TOP_CORE_BLUE, 0.42))
local TOP_DANGER_BUTTON_STYLE = TopButtonStyle({ 0.070, 0.026, 0.034, 0.94 }, { 0.340, 0.090, 0.110, 0.82 }, { 1.00, 0.82, 0.82, 1 }, { 0.090, 0.035, 0.045, 0.96 }, { 0.420, 0.120, 0.140, 0.90 })
local TOP_SUCCESS_BUTTON_STYLE = TopButtonStyle({ 0.018, 0.145, 0.090, 0.94 }, { 0.055, 0.440, 0.270, 0.82 }, { 0.780, 1.000, 0.875, 1 }, { 0.026, 0.185, 0.115, 0.96 }, { 0.075, 0.560, 0.345, 0.90 })
local TOP_ROLE_STYLES = { primary = TOP_ACTION_BUTTON_STYLE, destructive = TOP_DANGER_BUTTON_STYLE, danger = TOP_DANGER_BUTTON_STYLE, reset = TOP_DANGER_BUTTON_STYLE, delete = TOP_DANGER_BUTTON_STYLE, success = TOP_SUCCESS_BUTTON_STYLE, confirm = TOP_SUCCESS_BUTTON_STYLE }
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
    local s = style or TOP_ACTION_BUTTON_STYLE
    local defaults = TOP_ACTION_BUTTON_STYLE
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
function W.SetCollapsibleBadges(section, specs)
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

--- Automatically place every bound color control on its nearest accordion header.
--- This is cold Menu2 construction only; it adds no gameplay or combat runtime work.
function W.AttachBoundColorToCollapsible(ctx, colorControl)
    if not colorControl or colorControl._msuf2HeaderColorAttached then return false end
    local parent = colorControl.GetParent and colorControl:GetParent()
    local section, entry
    for _ = 1, 12 do
        if not parent then break end
        entry = parent._msuf2CollapsibleEntry
        if entry then section = entry.body or parent; break end
        parent = parent.GetParent and parent:GetParent()
    end
    if not (section and entry) then return false end
    colorControl._msuf2HeaderColorAttached = true
    entry._msuf2BoundHeaderColors = entry._msuf2BoundHeaderColors or {}
    entry._msuf2BoundHeaderColors[#entry._msuf2BoundHeaderColors + 1] = {
        control = colorControl,
        label = colorControl._msuf2ColorLabel or "Color",
    }
    local contextEntry = entry
    while contextEntry.ancestorEntry do contextEntry = contextEntry.ancestorEntry end
    contextEntry._msuf2ColorContextOwners = contextEntry._msuf2ColorContextOwners or {}
    contextEntry._msuf2ColorContextOwners[#contextEntry._msuf2ColorContextOwners + 1] = colorControl
    colorControl._msuf2ColorContextOwners = contextEntry._msuf2ColorContextOwners
    W.SetCollapsibleColorSwatches(ctx, section, entry._msuf2BoundHeaderColors)
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
local function PlaySwitchFeedback(button)
    if not (button and button._msuf2SwitchFlash) then return end
    local checked = button.GetChecked and button:GetChecked()
    local c = checked and T.colors.accent or (T.colors.borderSoft or T.colors.border)
    local alpha = checked and 0.28 or 0.18
    button._msuf2SwitchFlash:SetVertexColor(c[1], c[2], c[3], alpha)
    button._msuf2SwitchFlash:SetAlpha(alpha)
    PlayWidgetMotion(button._msuf2SwitchFlash, "controlFeedback", { fromAlpha = alpha, toAlpha = 0 })
end
local function RefreshSwitchVisual(button, hover)
    if not button then return end
    hover = hover or button._msuf2SwitchHovered
    local pressed = button._msuf2SwitchPressed and true or false
    local checked = button.GetChecked and button:GetChecked()
    local enabled = not button.IsEnabled or button:IsEnabled()
    local bg = checked and SWITCH_BG_ON or SWITCH_BG_OFF
    local br = checked and SWITCH_EDGE_ON or SWITCH_EDGE_OFF
    local kb = checked and SWITCH_KNOB_ON or SWITCH_KNOB_OFF
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
            btn._msuf2Override = (not active) and override or false
            btn:SetActive(active)
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
    if control._msuf2Label then control._msuf2Label:SetShown(shown) end
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
    if control._msuf2LayerInfoButton then
        control._msuf2LayerInfoButton:SetShown(shown)
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
    if frame.Enable and frame.Disable then
        if enabled then frame:Enable() else frame:Disable() end
    elseif frame.SetEnabled then
        frame:SetEnabled(enabled)
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
local function InstallPinnedPreviewUpdater(scroll)
    if not scroll or scroll._msuf2PinnedPreviewUpdater then return end
    scroll._msuf2PinnedPreviewUpdater = true
    local function RefreshIfPinned(self)
        local list = M._pinnedPreviews
        if type(list) ~= "table" or #list == 0 then
            self._msuf2PinnedPreviewLastOffset = nil
            self._msuf2PinnedPreviewLastHeight = nil
            self._msuf2PinnedPreviewLastChildHeight = nil
            return
        end
        local offset = (self.GetVerticalScroll and self:GetVerticalScroll()) or 0
        local h = (self.GetHeight and self:GetHeight()) or 0
        local child = M.scrollChild
        local childH = (child and child.GetHeight and child:GetHeight()) or 0
        if offset == self._msuf2PinnedPreviewLastOffset
            and h == self._msuf2PinnedPreviewLastHeight
            and childH == self._msuf2PinnedPreviewLastChildHeight
        then
            return
        end
        self._msuf2PinnedPreviewLastOffset = offset
        self._msuf2PinnedPreviewLastHeight = h
        self._msuf2PinnedPreviewLastChildHeight = childH
        if M.RefreshPinnedPreviews then M.RefreshPinnedPreviews(self) end
    end
    scroll:HookScript("OnVerticalScroll", RefreshIfPinned)
    scroll:HookScript("OnShow", RefreshIfPinned)
    scroll:HookScript("OnSizeChanged", RefreshIfPinned)
    local child = M.scrollChild
    if child and child.HookScript and not child._msuf2PinnedPreviewChildUpdater then
        child._msuf2PinnedPreviewChildUpdater = true
        child:HookScript("OnSizeChanged", function()
            QueuePinnedPreviewGeometryRefresh(scroll)
        end)
    end
end

function M.RefreshPinnedPreviews(scroll)
    local list = M._pinnedPreviews
    if type(list) ~= "table" or #list == 0 then return end
    for i = 1, #list do
        local r = list[i]
        if r and r.update and (not scroll or r.scroll == scroll) then r.update() end
    end
end
--- Window hiding is a suspension, not an ownership change: Menu2 keeps its
--- page cache and can reopen the same page instance. Restore floating previews
--- to their page slot and stop rendering them, but retain the live record and
--- hooks so reopen does not attach another generation of callbacks.
function M.SuspendPinnedPreviews(reason)
    M._msuf2PinnedPreviewResumeSerial = (M._msuf2PinnedPreviewResumeSerial or 0) + 1
    local list = M._pinnedPreviews
    if type(list) ~= "table" then return end
    for i = 1, #list do
        local record = list[i]
        local box = record and record.box
        -- Window hide is an ownership boundary.  Force the floating branch back
        -- into its page even if a queued layout pass already changed the local
        -- `pinned` flag; visual state (not that flag) is the final authority here.
        if record and type(record.restore) == "function" then record.restore(true) end
        if record and record.scroll and record.scroll._msuf2PinnedPreviewActiveRecord == record then
            record.scroll._msuf2PinnedPreviewActiveRecord = nil
        end
        if box then
            box._msuf2PinnedFloating = nil
            if box.Hide then box:Hide() end
        end
    end
end
function M.ResumePinnedPreviews(reason)
    local list = M._pinnedPreviews
    if type(list) ~= "table" or #list == 0 then return end
    M._msuf2PinnedPreviewResumeSerial = (M._msuf2PinnedPreviewResumeSerial or 0) + 1
    local serial = M._msuf2PinnedPreviewResumeSerial
    for i = 1, #list do
        local scroll = list[i] and list[i].scroll
        if scroll then
            scroll._msuf2PinnedPreviewLastOffset = nil
            scroll._msuf2PinnedPreviewLastHeight = nil
            scroll._msuf2PinnedPreviewLastChildHeight = nil
        end
    end
    local function RefreshAfterShow()
        if M._msuf2PinnedPreviewResumeSerial ~= serial then return end
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
    local list = M._pinnedPreviews
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
            if record and type(record.restore) == "function" then record.restore(true) end
            if record and record.scroll and record.scroll._msuf2PinnedPreviewActiveRecord == record then record.scroll._msuf2PinnedPreviewActiveRecord = nil end
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

--- Pinned previews are owned by their page body but coordinated globally so a
--- page rebuild can release stale preview frames and keep only the active one.
function W.AttachPinnedPreview(body, box, opts)
    if not (body and box) then return nil end
    opts = opts or {}
    local scroll = M.scrollFrame
    if not scroll then return nil end
    local buildKey = M._msuf2SearchBuildKey
    local buildEntry = buildKey and M.cache and M.cache[buildKey]
    if buildEntry and buildEntry.hiddenBuild and buildEntry.wrapper and buildEntry.wrapper.HookScript then
        local wrapper = buildEntry.wrapper
        wrapper._msuf2DeferredPinnedPreviews = wrapper._msuf2DeferredPinnedPreviews or {}
        wrapper._msuf2DeferredPinnedPreviews[#wrapper._msuf2DeferredPinnedPreviews + 1] = { body = body, box = box, opts = opts }
        if not wrapper._msuf2DeferredPinnedPreviewHook then
            wrapper._msuf2DeferredPinnedPreviewHook = true
            wrapper:HookScript("OnShow", function(self)
                local pending = self._msuf2DeferredPinnedPreviews
                if type(pending) ~= "table" or #pending == 0 then return end
                self._msuf2DeferredPinnedPreviews = nil
                for i = 1, #pending do
                    local item = pending[i]
                    if item and item.body and item.box then W.AttachPinnedPreview(item.body, item.box, item.opts) end
                end
            end)
        end
        return nil
    end
    M.previewPinState = MenuStateTable("previewPinState")
    local stateKey = tostring(opts.stateKey or box._msuf2PinStateKey or "preview")
    local pageKey = opts.pageKey or box._msufGFNativePreviewPageKey
    local pageWrapper = opts.wrapper or box._msufGFNativePreviewWrapper
    local scrollParent = scroll:GetParent()
    local originalParent = opts.restoreParent or body or box:GetParent()
    local point, relTo, relPoint, xOfs, yOfs = box:GetPoint(1)
    if type(opts.restorePoint) == "table" then
        point = opts.restorePoint[1] or point
        relTo = opts.restorePoint[2] or originalParent
        relPoint = opts.restorePoint[3] or relPoint
        xOfs = opts.restorePoint[4] or xOfs
        yOfs = opts.restorePoint[5] or yOfs
    end
    if relTo == scroll or relTo == scrollParent then relTo = originalParent end
    local originalAnchor = relTo or originalParent or body
    local originalFrameLevel = (box.GetFrameLevel and box:GetFrameLevel()) or 1
    local originalWidth = tonumber(opts.restoreWidth) or (box.GetWidth and box:GetWidth())
    local originalHeight = tonumber(opts.restoreHeight) or (box.GetHeight and box:GetHeight())
    local pinnedHeight = tonumber(opts.pinnedHeight)
    local pinned = false
    local restoring = false
    local applyingPinnedState = false
    local pinnedStateRefreshQueued = false
    local record
    local ApplyPinnedState
    local function QueuePinnedStateRefresh()
        if pinnedStateRefreshQueued then return end
        pinnedStateRefreshQueued = true
        local function RunQueuedRefresh()
            pinnedStateRefreshQueued = false
            if box._msuf2PinnedPreviewRecord == record and type(ApplyPinnedState) == "function" then
                ApplyPinnedState()
            end
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, RunQueuedRefresh)
        elseif not applyingPinnedState then
            RunQueuedRefresh()
        end
    end
    local function EnsureRestoreSlot()
        if not originalParent then return nil end
        local slot = box._msuf2PinnedPreviewRestoreSlot
        if not slot then
            slot = CreateFrame("Frame", nil, originalParent)
            if slot.EnableMouse then slot:EnableMouse(false) end
            box._msuf2PinnedPreviewRestoreSlot = slot
        elseif slot.SetParent then
            slot:SetParent(originalParent)
        end
        if slot.SetFrameLevel then slot:SetFrameLevel(max(0, originalFrameLevel - 1)) end
        slot:ClearAllPoints()
        slot:SetPoint(point or "TOPLEFT", relTo or originalParent, relPoint or "TOPLEFT", xOfs or 0, yOfs or 0)
        slot:SetSize(max(1, originalWidth or (box.GetWidth and box:GetWidth()) or 1), max(1, originalHeight or (box.GetHeight and box:GetHeight()) or 1))
        if slot.SetAlpha then slot:SetAlpha(0) end
        slot:Show()
        return slot
    end
    local function AnchorBoxToRestoreSlot()
        local slot = EnsureRestoreSlot()
        if not slot then return false end
        box:SetParent(originalParent)
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, 0)
        box:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 0, 0)
        if box.SetFrameLevel then box:SetFrameLevel(originalFrameLevel) end
        return true
    end
    EnsureRestoreSlot()
    local pinBtn = box._msuf2PinButton
    if not pinBtn then
        pinBtn = T.Button(box, Tr("Pinned"), opts.buttonWidth or 86, opts.buttonHeight or 22)
        if opts.centerButton and T.CenterButtonLabel then T.CenterButtonLabel(pinBtn) end
        pinBtn._msuf2SearchText = "Pin Preview"
        pinBtn._msuf2ControlKind = "button"
        RegisterSearchObject(pinBtn, "Pin Preview", "button")
        box._msuf2PinButton = pinBtn
    else
        pinBtn:SetParent(box)
        pinBtn:ClearAllPoints()
        pinBtn:SetSize(opts.buttonWidth or 86, opts.buttonHeight or 22)
        if opts.centerButton and T.CenterButtonLabel then T.CenterButtonLabel(pinBtn) end
    end
    pinBtn:SetPoint("TOPRIGHT", box, "TOPRIGHT", -12, -8)
    local hint = opts.hint or box.hint or box._hint
    if hint and hint.SetPoint then
        hint:ClearAllPoints()
        hint:SetPoint("LEFT", opts.title or box.title or box._title, "RIGHT", 12, 0)
        hint:SetPoint("RIGHT", pinBtn, "LEFT", -12, 0)
        hint:SetJustifyH("LEFT")
    end
    local placeholder = body.CreateFontString and body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall") or nil
    if placeholder then
        placeholder:SetPoint("CENTER", body, "CENTER", 0, 0)
        placeholder:SetText(Tr("\226\134\145 Preview pinned at top"))
        local placeholderColor = ThemeColor("dim", { 0.043, 0.096, 0.150, 0.86 })
        placeholder:SetTextColor(placeholderColor[1], placeholderColor[2], placeholderColor[3], 0.55)
        if T.StyleFontString then T.StyleFontString(placeholder, { placeholderColor[1], placeholderColor[2], placeholderColor[3], 0.55 }, 0) end
        placeholder:Hide()
    end
    local function PinEnabled()
        return M.previewPinState[stateKey] ~= false
    end
    local function RefreshButton()
        local guidedLayout = type(M.GuidedTourOwnsPreviewLayout) == "function"
            and M.GuidedTourOwnsPreviewLayout() == true
        if guidedLayout then
            if pinBtn.Hide then pinBtn:Hide() end
            return
        end
        if pinBtn.Show then pinBtn:Show() end
        local enabled = PinEnabled()
        local text = enabled and "Pinned" or "Pin Preview"
        if pinBtn._msuf2PinButtonText ~= text then
            pinBtn._msuf2PinButtonText = text
            pinBtn:SetText(text)
        end
        if pinBtn._msuf2PinButtonActive ~= enabled then
            pinBtn._msuf2PinButtonActive = enabled
            -- The label already communicates the pin state.  Inline previews
            -- can opt out of the strong active-blue treatment so the actual
            -- preview remains the visual focus of the card.
            if pinBtn.SetActive then pinBtn:SetActive(opts.quietButton == true and false or enabled) end
        end
        if pinBtn.SetEnabled then pinBtn:SetEnabled(true) end
    end
    local function EnsurePinnedScrim()
        if record and record.scrim then return record.scrim end
        local scrim = box._msuf2PinnedPreviewScrim
        if not scrim then
            -- The pinned background belongs to the preview's render tree.  A
            -- separately levelled sibling can sit above children that use fixed
            -- frame levels after the box is floated to its overlay parent.
            scrim = box:CreateTexture(nil, "BACKGROUND", nil, -8)
            box._msuf2PinnedPreviewScrim = scrim
        end
        scrim:Hide()
        if record then record.scrim = scrim end
        return scrim
    end
    local function LayoutPinnedScrim(level)
        if not (record and record.scrim) then return end
        local scrim = record.scrim
        local bg = ThemeColor("coreShadow", { 0.006, 0.016, 0.032, 1 })
        scrim:ClearAllPoints()
        scrim:SetPoint("TOPLEFT", box, "TOPLEFT", -2, 2)
        scrim:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 2, -2)
        if scrim.SetColorTexture then scrim:SetColorTexture(bg[1], bg[2], bg[3], opts.scrimAlpha or 0.94) end
        scrim._msuf2PinnedPreviewOwnerRecord = record
        scrim:Show()
    end
    local function ApplyPinnedPresentation(active, level)
        if active then
            EnsurePinnedScrim()
            if pinnedHeight and box.SetHeight then box:SetHeight(pinnedHeight) end
            if type(box.ApplyPinnedPreviewPresentation) == "function" then box:ApplyPinnedPreviewPresentation(true, opts) end
            LayoutPinnedScrim(level)
        else
            if record and record.scrim then record.scrim:Hide() end
            if originalWidth and originalHeight and box.SetSize then box:SetSize(originalWidth, originalHeight) end
            if type(box.ApplyPinnedPreviewPresentation) == "function" then box:ApplyPinnedPreviewPresentation(false, opts) end
        end
    end
    local function ClearActivePinnedRecord()
        local active = scroll and scroll._msuf2PinnedPreviewActiveRecord
        if active and (active == record or active.box == box) then
            if active.scrim and active.scrim.Hide then active.scrim:Hide() end
            scroll._msuf2PinnedPreviewActiveRecord = nil
        end
    end
    local function Restore(force)
        if box._msuf2PinnedPreviewRecord ~= record then return end
        local wasFloating = pinned or box._msuf2PinnedFloating == true
        restoring = true
        pinned = false
        box._msuf2PinnedFloating = nil
        if placeholder then placeholder:Hide() end
        ClearActivePinnedRecord()
        -- The background region is shared by successive records for this box.
        -- Always reconcile it before considering an early return so logical and
        -- visual ownership cannot diverge across a queued pin pass.
        local scrim = (record and record.scrim) or box._msuf2PinnedPreviewScrim
        if scrim then
            scrim:Hide()
            scrim._msuf2PinnedPreviewOwnerRecord = nil
        end
        ApplyPinnedPresentation(false)
        if not force and not wasFloating then
            restoring = false
            return
        end
        if not AnchorBoxToRestoreSlot() then
            box:SetParent(originalParent)
            box:ClearAllPoints()
            box:SetPoint(point or "TOPLEFT", relTo or body, relPoint or "TOPLEFT", xOfs or 0, yOfs or 0)
            if box.SetFrameLevel then box:SetFrameLevel(originalFrameLevel) end
        end
        if box.RequestRefresh then box:RequestRefresh("PINNED_PREVIEW_RESTORE") end
        restoring = false
    end
    local function BodyOwned()
        if pageKey and M.activeKey and M.activeKey ~= pageKey then return false end
        if M.frame and M.frame.IsShown and not M.frame:IsShown() then return false end
        if pageWrapper and pageWrapper.IsShown and not pageWrapper:IsShown() then return false end
        if body.IsShown and not body:IsShown() then return false end
        if scroll.IsShown and not scroll:IsShown() then return false end
        return true
    end
    local function BodyVisible()
        if not BodyOwned() then return false end
        --- Effective visibility is only needed once final scroll geometry is used.
        if pageWrapper and pageWrapper.IsVisible and not pageWrapper:IsVisible() then return false end
        return not body.IsVisible or body:IsVisible()
    end
    local function OriginalSlotTop()
        local slot = EnsureRestoreSlot()
        if slot and slot.GetTop then return slot:GetTop() end
        local anchor = originalAnchor or body
        local anchorTop = anchor and anchor.GetTop and anchor:GetTop()
        if not anchorTop then return nil end
        return anchorTop + (tonumber(yOfs) or 0)
    end
    local function ShouldPin()
        local guidedLayout = type(M.GuidedTourOwnsPreviewLayout) == "function"
            and M.GuidedTourOwnsPreviewLayout() == true
        if guidedLayout or not PinEnabled() or not BodyVisible() then return false end
        local offset = (scroll.GetVerticalScroll and scroll:GetVerticalScroll()) or 0
        local activateAt = opts.activateAfter or 64
        if offset <= (pinned and math.floor(activateAt * 0.45) or activateAt) then return false end
        local scrollTop = scroll.GetTop and scroll:GetTop()
        local slotTop = OriginalSlotTop()
        if not (scrollTop and slotTop) then return false end
        if slotTop <= (scrollTop + (opts.threshold or 6)) then return false end
        return true
    end
    ApplyPinnedState = function()
        if applyingPinnedState then
            QueuePinnedStateRefresh()
            return
        end
        if restoring then return end
        if box._msuf2PinnedPreviewRecord ~= record then return end
        applyingPinnedState = true
        if not BodyOwned() then
            Restore()
            if pageKey and box.Hide then box:Hide() end
            RefreshButton()
            applyingPinnedState = false
            return
        end
        -- IsVisible updates one frame after Show/ancestor changes. While the
        -- page still owns the preview, keep its render lifecycle intact and
        -- wait for settled geometry before deciding whether it should float.
        if not BodyVisible() then
            RefreshButton()
            applyingPinnedState = false
            return
        end
        if box.Show then box:Show() end
        if ShouldPin() then
            local active = scroll._msuf2PinnedPreviewActiveRecord
            if active and active ~= record and active.restore then active.restore() end
            if not pinned then
                pinned = true
                box._msuf2PinnedFloating = true
                scroll._msuf2PinnedPreviewActiveRecord = record
                --- Float as a pure overlay - scroll frame is never moved
                local level = ((scrollParent and scrollParent.GetFrameLevel and scrollParent:GetFrameLevel()) or 1)
                    + (opts.frameLevelOffset or 80)
                box:SetParent(scrollParent or scroll)
                box:ClearAllPoints()
                box:SetPoint("TOPLEFT", scroll, "TOPLEFT", opts.left or 16, opts.top or -8)
                box:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -(opts.right or 16), opts.top or -8)
                if box.SetFrameLevel then box:SetFrameLevel(level) end
                ApplyPinnedPresentation(true, level)
                if box.RequestRefresh then box:RequestRefresh("PINNED_PREVIEW_LAYOUT") end
                if placeholder then
                    placeholder:SetText(Tr("\226\134\145 Preview pinned at top"))
                    placeholder:Show()
                end
            end
            if pinned then LayoutPinnedScrim((box.GetFrameLevel and box:GetFrameLevel()) or originalFrameLevel) end
        else
            Restore()
        end
        RefreshButton()
        applyingPinnedState = false
    end
    local function SetPinEnabled(enabled)
        enabled = enabled == true
        if PinEnabled() == enabled then
            RefreshButton()
            return true
        end
        M.previewPinState[stateKey] = enabled
        if not enabled then Restore(true) end
        ApplyPinnedState()
        RefreshButton()
        return PinEnabled() == enabled
    end
    pinBtn._msuf2CommandAction = {
        kind = "toggle",
        historyMode = "none",
        get = function() return PinEnabled() end,
        set = SetPinEnabled,
    }
    pinBtn:SetScript("OnClick", function()
        return SetPinEnabled(not PinEnabled())
    end)
    pinBtn:SetScript("OnEnter", function(self)
        self._msuf2Hover = true
        if self.RefreshVisual then self:RefreshVisual() end
    end)
    pinBtn:SetScript("OnLeave", function(self)
        self._msuf2Hover = nil
        if self.RefreshVisual then self:RefreshVisual() end
    end)
    M.AddTooltip(pinBtn, "Pin Preview", "Keeps this preview visible while you edit lower options.", { hook = true })
    box._msuf2PinnedPreviewPageKey = pageKey
    box._msuf2PinnedPreviewWrapper = pageWrapper
    record = { scroll = scroll, update = ApplyPinnedState, restore = Restore, box = box, stateKey = stateKey, pageKey = pageKey, pageWrapper = pageWrapper }
    M._pinnedPreviews = M._pinnedPreviews or {}
    for i = #M._pinnedPreviews, 1, -1 do
        local r = M._pinnedPreviews[i]
        if r and r.box == box then  --- same box = this exact page was rebuilt, replace its record
            if r.restore then r.restore(true) end
            table.remove(M._pinnedPreviews, i)
        end
    end
    box._msuf2PinnedPreviewRecord = record
    M._pinnedPreviews[#M._pinnedPreviews + 1] = record
    scroll._msuf2PinnedPreviewLastOffset = nil
    scroll._msuf2PinnedPreviewLastHeight = nil
    InstallPinnedPreviewUpdater(scroll)
    if body.HookScript then
        body:HookScript("OnShow", ApplyPinnedState)
        body:HookScript("OnHide", Restore)
    end
    if box.HookScript then
        box:HookScript("OnHide", Restore)
        box:HookScript("OnSizeChanged", QueuePinnedStateRefresh)
    end
    C_Timer.After(0, ApplyPinnedState)
    -- Restored scroll positions can be applied one frame after the page body.
    -- Re-evaluate once geometry is final even when no wheel event fires.
    C_Timer.After(0.05, function()
        if box._msuf2PinnedPreviewRecord == record then ApplyPinnedState() end
    end)
    RefreshButton()
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

local function AttachLayerOverviewButton(section, slider, title, label, minValue, maxValue)
    if not (section and slider and title and IsNumericLayerControl(label, minValue, maxValue)) then return nil end
    local info = W.RoleButton(section, "I", "success", 18, 18)
    info:SetPoint("TOPRIGHT", title, "TOPRIGHT", 0, 2)
    info._msuf2SkipHistoryCheckpoint = true
    info._msuf2LayerOverviewButton = true
    if info.SetFrameLevel and slider.GetFrameLevel then info:SetFrameLevel(slider:GetFrameLevel() + 4) end
    if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(info, slider)
    else info._msuf2ControlPartOf = slider end
    info:SetScript("OnClick", function(self)
        local show = M.ShowLayerOverview or _G.MSUF_ShowLayerOverview
        if type(show) == "function" then show(self) end
    end)
    if info.HookScript then
        info:HookScript("OnHide", function(self)
            local hide = M.HideLayerOverviewForAnchor or _G.MSUF_HideLayerOverviewForAnchor
            if type(hide) == "function" then hide(self) end
        end)
    end
    if type(M.AddTooltip) == "function" then
        M.AddTooltip(info, "Layer overview", "Shows every configurable MSUF layer on the unified 0-30 scale.", { hook = true, owner = "ANCHOR_RIGHT" })
    end
    slider._msuf2LayerInfoButton = info
    return info
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
    if slider.SetStepsPerPage then slider:SetStepsPerPage(1) end
    slider._msuf2Step = step or 1
    slider._msuf2RequestedWidth = width
    slider._msuf2MinRowWidth = compactMinTrackW
    HideSliderTemplateParts(slider)
    if T.StyleSlider then T.StyleSlider(slider) end
    local function StepButton(text)
        local btn = T.Button(section, text, 20, 24)
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
        if value ~= nil then
            slider:SetValue(value)
            if slider._msuf2UpdateFill then slider:_msuf2UpdateFill() end
        end
    end
    local function StopSliderInteraction()
        slider._msuf2SliderActive = nil
        if type(slider._msuf2CommitSliderHistory) == "function" then slider:_msuf2CommitSliderHistory() end
        if T.StyleSlider then T.StyleSlider(slider) end
    end
    slider:SetScript("OnMouseDown", function(_, button)
        if button and button ~= "LeftButton" then return end
        if slider.IsEnabled and not slider:IsEnabled() then return end
        if type(slider._msuf2BeginSliderHistory) == "function" then slider:_msuf2BeginSliderHistory() end
        slider._msuf2SliderActive = true
        SetValueFromCursor()
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
