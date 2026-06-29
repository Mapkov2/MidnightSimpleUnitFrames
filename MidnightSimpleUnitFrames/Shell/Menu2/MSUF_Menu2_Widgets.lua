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
local T = M.Theme
local W = M.Widgets or {}
M.Widgets = W
local floor = math.floor
local max = math.max
local min = math.min
local sliderSerial = 0
local Tr = M.TranslateText or function(text) return text end
local EM2Util = (_G.MSUF_EM2 and _G.MSUF_EM2.Util) or {}
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
    local relayout
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
            relayout = relayout or collapsible.builder
            changed = true
        end
    end
    if changed and relayout and relayout.RelayoutCollapsibles then relayout:RelayoutCollapsibles() end
    return changed and true or false
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
        local c = T.colors.accent or { 0.18, 0.72, 0.90, 1 }
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
    entry._msuf2MotionSerial = (entry._msuf2MotionSerial or 0) + 1
    if entry._msuf2MotionActive then entry._msuf2MotionActive = nil end
    entry.open = true
    entry._msuf2Closing = nil
    if opts.persist == true then
        entry._msuf2AutoOpened = nil
        if M.accordionState and entry.stateKey then M.accordionState[entry.stateKey] = true end
    else
        entry._msuf2AutoOpened = true
    end
    if entry.body then
        entry.body:Show()
        if entry.body.SetAlpha then entry.body:SetAlpha(1) end
    end
    if entry.builder and entry.builder.RelayoutCollapsibles then entry.builder:RelayoutCollapsibles() end
    local function FinishFocus()
        ScrollToCollapsibleEntry(entry)
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
function W.PageBuilder(ctx)
    if type(M.EnsurePersistentMenuState) == "function" then M.EnsurePersistentMenuState() end
    local b = {
        ctx = ctx,
        parent = ctx.wrapper,
        x = 12,
        y = -12,
        width = ctx.width or 720,
        collapsibles = {},
        layoutEntries = {},
    }
    function b:RelayoutCollapsibles()
        if not self._collapsibleStartY then return end
        local y = self._collapsibleStartY
        local entries = (#self.layoutEntries > 0) and self.layoutEntries or self.collapsibles
        for i = 1, #entries do
            local entry = entries[i]
            if entry.kind == "section" then
                local section = entry.frame
                if section then
                    section:ClearAllPoints()
                    section:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, y)
                    y = y - ((section.GetHeight and section:GetHeight()) or entry.height or 120) - (entry.gap or 12)
                end
            elseif entry.kind == "spacer" then
                y = y - (entry.height or 10)
            else
                local open = entry.open and true or false
                entry.outer:ClearAllPoints()
                entry.outer:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, y)
                entry.outer:SetHeight(entry.headerHeight + (open and entry.contentHeight or 0))
                entry.body:SetShown(open)
                if entry.body.SetAlpha and not entry._msuf2MotionActive then entry.body:SetAlpha(1) end
                T.ApplyCollapseVisual(entry.arrow, entry.hint, open)
                if entry._msuf2RefreshHeaderTone then entry._msuf2RefreshHeaderTone(false) end
                if entry._msuf2RefreshState then entry._msuf2RefreshState(entry) end
                y = y - entry.outer:GetHeight() - 8
            end
        end
        self.y = y
        if ctx.SetContentHeight then ctx:SetContentHeight(math.abs(y) + 42) end
    end
    function b:Section(title, height)
        local section = T.Panel(self.parent, nil, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft)
        T.ApplySurface(section, "card")
        SetSearchTitle(section, title)
        RegisterSearchObject(section, title, "section")
        section:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, self.y)
        section:SetSize(self.width, height or 120)
        section._msuf2CursorY = -38
        section._msuf2ContentX = 14
        section._msuf2Width = self.width
        local fs = T.Font(section, "GameFontNormal", Tr(title or ""), T.colors.text)
        SetSearchText(fs, title)
        fs:SetPoint("TOPLEFT", 14, -12)
        section.title = fs
        self.y = self.y - (height or 120) - 12
        if ctx.SetContentHeight then ctx:SetContentHeight(math.abs(self.y) + 28) end
        if self._collapsibleStartY then
            self.layoutEntries[#self.layoutEntries + 1] = {
                kind = "section",
                frame = section,
                height = height or 120,
                gap = 12,
            }
        end
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
        headerBg:SetColorTexture(0.040, 0.050, 0.088, 0.34)
        local headerHover = header:CreateTexture(nil, "HIGHLIGHT")
        headerHover:SetAllPoints()
        headerHover:SetColorTexture(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.045)
        local arrow = header:CreateTexture(nil, "OVERLAY")
        arrow:SetSize(10, 10)
        arrow:SetPoint("LEFT", header, "LEFT", 12, 0)
        arrow:SetTexture(T.media.collapseArrow)
        local label = T.Font(header, "GameFontNormal", Tr(title or ""), T.colors.text)
        SetSearchText(label, title)
        label:SetJustifyH("LEFT")
        local hint = T.Font(header, "GameFontDisableSmall", "", T.colors.dim)
        hint:SetJustifyH("RIGHT")
        local contentW = math.min(self.width, M.formContentMaxWidth or 980)
        local body = CreateFrame("Frame", nil, outer)
        SetSearchTitle(body, title)
        body:SetPoint("TOPLEFT", outer, "TOPLEFT", 0, -headerH)
        body:SetSize(contentW, height or 120)
        body._msuf2CursorY = -38
        body._msuf2ContentX = 14
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
        }
        RefreshCollapseHintSuppression(entry)
        local function RefreshHeaderLayout()
            local headerW = (header.GetWidth and header:GetWidth()) or self.width or 240
            local reserve = math.max(120, math.min(136, math.floor(headerW * 0.38 + 0.5)))
            if not entry._msuf2ManualHintLayout then
                local badges = entry._msuf2Badges
                if badges and #badges > 0 then
                    local availableBadges = {}
                    local availableW = headerW - 12 - 28 - (headerW < 520 and 96 or 136)
                    local totalW = 0
                    for i = 1, #badges do
                        local badge = badges[i]
                        if badge and badge._msuf2BadgeWantedShown ~= false then
                            local bw = (badge.GetWidth and badge:GetWidth()) or 0
                            if bw > 0 then
                                totalW = totalW + bw + (#availableBadges > 0 and 6 or 0)
                                availableBadges[#availableBadges + 1] = badge
                            end
                        end
                    end
                    availableW = max(0, availableW)
                    while #availableBadges > 1 and totalW > availableW do
                        local badge = availableBadges[#availableBadges]
                        totalW = totalW - ((badge.GetWidth and badge:GetWidth()) or 0) - (#availableBadges > 1 and 6 or 0)
                        availableBadges[#availableBadges] = nil
                    end
                    if #availableBadges == 1 and totalW > availableW then availableBadges[1] = nil end
                    local right = -12
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
                        right = right - bw - 6
                    end
                    if #availableBadges > 0 then
                        if hint.Hide then hint:Hide() end
                        label:ClearAllPoints()
                        label:SetPoint("LEFT", arrow, "RIGHT", 6, 0)
                        label:SetPoint("RIGHT", header, "RIGHT", right - 8, 0)
                        label:SetJustifyH("LEFT")
                        return
                    end
                end
                if hint.Show then hint:Show() end
                hint:ClearAllPoints()
                hint:SetPoint("TOPRIGHT", header, "TOPRIGHT", -12, -1)
                hint:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -12, 1)
                hint:SetPoint("LEFT", header, "RIGHT", -(12 + reserve), 0)
                hint:SetJustifyH("RIGHT")
                label:ClearAllPoints()
                label:SetPoint("LEFT", arrow, "RIGHT", 6, 0)
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
        end
        self.collapsibles[#self.collapsibles + 1] = entry
        local function RefreshHeaderTone(hover)
            if not headerBg.SetColorTexture then return end
            if entry.open then
                headerBg:SetColorTexture(0.048, 0.060, 0.105, hover and 0.48 or 0.40)
            elseif hover then
                headerBg:SetColorTexture(0.050, 0.064, 0.110, 0.42)
            else
                headerBg:SetColorTexture(0.040, 0.050, 0.088, 0.34)
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
                entry.open = true
                entry._msuf2MotionActive = true
                if body.SetAlpha then body:SetAlpha(0) end
                self:RelayoutCollapsibles()
                if T.PlayMotion then
                    T.PlayMotion(body, "accordionIn", { fromAlpha = 0, onFinished = function()
                        if entry._msuf2MotionSerial ~= motionSerial then return end
                        entry._msuf2MotionActive = nil
                        if body.SetAlpha then body:SetAlpha(1) end
                    end })
                else
                    entry._msuf2MotionActive = nil
                    if body.SetAlpha then body:SetAlpha(1) end
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
        self.y = self.y - outer:GetHeight() - 8
        RefreshHeaderLayout()
        RefreshHeaderTone(false)
        self.layoutEntries[#self.layoutEntries + 1] = entry
        self:RelayoutCollapsibles()
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
        local fs = T.Font(section, "GameFontNormalLarge", Tr(title or ""), T.colors.text)
        SetSearchText(fs, title)
        fs:SetPoint("TOPLEFT", 14, -12)
        section.title = fs
        if subtitle and subtitle ~= "" then
            local sub = T.Font(section, "GameFontDisableSmall", Tr(subtitle), T.colors.muted)
            SetSearchText(sub, subtitle)
            sub:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -6)
            sub:SetWidth(self.width - 28)
            sub:SetJustifyH("LEFT")
        end
        self.y = self.y - (height or 78) - 12
        if ctx.SetContentHeight then ctx:SetContentHeight(math.abs(self.y) + 28) end
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
        if ctx.SetContentHeight then ctx:SetContentHeight(math.abs(self.y) + 28) end
        if self._collapsibleStartY then
            self.layoutEntries[#self.layoutEntries + 1] = {
                kind = "spacer",
                height = height or 10,
            }
        end
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
        M.BindBoolWidget(ctx, widget, row.get, row.set)
        return widget
    elseif kind == "color" then
        widget = W.Color(card, CardResolve(row.label))
        W.MoveWidget(widget, card, x, y)
        M.BindColor(ctx, widget, row.get, row.set)
        return widget
    elseif kind == "slider" then
        widget = W.Slider(card, CardResolve(row.label), row.min or 0, row.max or 100, row.step or 1, row.width or width)
        if row.format and widget.SetValueFormatter then widget:SetValueFormatter(row.format) end
        M.BindNumberWidget(ctx, widget, row.get, row.set, row.default, {
            step = row.step or 1, roundStep = row.roundStep ~= false,
        })
    elseif kind == "segment" then
        widget = W.Segment(card, CardResolve(row.label), CardResolve(row.values), row.width or width)
        M.BindSegment(ctx, widget, row.get, row.set)
    elseif kind == "dropdown" then
        widget = W.Dropdown(card, CardResolve(row.label), CardResolve(row.values), row.width or width)
        M.BindDropdownWidget(ctx, widget, row.get, row.set)
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
---   rows = { { kind, label, get, set, values?/min/max/step?, width?, id?, gate?, height? }, ... },
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
local TOP_ACTION_BUTTON_STYLE = TopButtonStyle({ 0.018, 0.028, 0.058, 0.95 }, { 0.082, 0.125, 0.245, 0.66 }, { 0.82, 0.90, 1.00, 1 }, { 0.026, 0.040, 0.078, 0.97 }, { 0.125, 0.220, 0.430, 0.80 })
local TOP_DANGER_BUTTON_STYLE = TopButtonStyle({ 0.070, 0.026, 0.034, 0.94 }, { 0.340, 0.090, 0.110, 0.82 }, { 1.00, 0.82, 0.82, 1 }, { 0.090, 0.035, 0.045, 0.96 }, { 0.420, 0.120, 0.140, 0.90 })
local TOP_SUCCESS_BUTTON_STYLE = TopButtonStyle({ 0.018, 0.145, 0.090, 0.94 }, { 0.055, 0.440, 0.270, 0.82 }, { 0.780, 1.000, 0.875, 1 }, { 0.026, 0.185, 0.115, 0.96 }, { 0.075, 0.560, 0.345, 0.90 })
local TOP_ROLE_STYLES = { primary = TOP_ACTION_BUTTON_STYLE, destructive = TOP_DANGER_BUTTON_STYLE, danger = TOP_DANGER_BUTTON_STYLE, reset = TOP_DANGER_BUTTON_STYLE, delete = TOP_DANGER_BUTTON_STYLE, success = TOP_SUCCESS_BUTTON_STYLE, confirm = TOP_SUCCESS_BUTTON_STYLE }
local function ApplyTopActionButtonVisual(btn, hover)
    local bg = btn._msuf2TopActive and btn._msuf2TopActiveBg or (hover and btn._msuf2TopHoverBg or btn._msuf2TopBg)
    local br = btn._msuf2TopActive and btn._msuf2TopActiveBorder or (hover and btn._msuf2TopHoverBorder or btn._msuf2TopBorder)
    local tx = btn._msuf2TopActive and btn._msuf2TopActiveText or btn._msuf2TopText
    local mul = hover and 1.06 or 1
    if btn._msuf2Fill then
        local fill = { min(bg[1] * mul, 1), min(bg[2] * mul, 1), min(bg[3] * mul, 1), bg[4] or 1 }
        if T.SetFillGradient then T.SetFillGradient(btn._msuf2Fill, fill, 0.12, -0.18) else btn._msuf2Fill:SetVertexColor(fill[1], fill[2], fill[3], fill[4]) end
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
        local c = s.stripeColor or { 0.22, 0.78, 0.94, 1 }
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
function W.CreatePageResetButton(ctx, parent, anchor, opts)
    opts = opts or {}
    local key = ctx and ctx.key
    if not (M.PageHasReset and M.PageHasReset(key)) then return nil end
    local label = opts.text or "Reset All"
    local btn = StyleTopDangerButton(T.Button(parent, label, opts.width or 88, opts.height or 24))
    btn._msuf2SkipHistoryCheckpoint = true
    if anchor then
        btn:SetPoint("RIGHT", anchor, "LEFT", -(opts.gap or 8), opts.offsetY or 0)
    else
        btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", opts.x or -14, opts.y or -14)
    end
    btn:SetScript("OnClick", function()
        if M.ShowPageResetConfirm then M.ShowPageResetConfirm(key) end
    end)
    RegisterSearchObject(btn, label, "button")
    return btn
end
function W.GlobalStyleHeader(ctx, builder, title, subtitle, height)
    if not (builder and builder.Header) then return nil end
    local head = builder:Header(title, subtitle, height or 72)
    local edit = StyleTopActionButton(T.Button(head, "MSUF Edit Mode", 128, 24))
    RegisterSearchObject(edit, "MSUF Edit Mode", "button")
    edit:SetPoint("TOPRIGHT", head, "TOPRIGHT", -14, -14)
    W.CreatePageResetButton(ctx, head, edit, { width = 88 })
    M.WireEditModeButton(ctx, edit, {
        afterClick = function()
            if M.frame and M.frame.RefreshStatus then M.frame:RefreshStatus() end
            if M.RequestRefresh then M.RequestRefresh(nil, "edit-mode-header") elseif M.Refresh then M.Refresh() end
        end,
    })
    return head, edit
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
        bg = { 0.060, 0.090, 0.210, 0.92 },
        border = { 0.160, 0.260, 0.560, 0.78 },
        text = { 0.760, 0.840, 1.000, 1 },
    },
    accent = {
        bg = { 0.018, 0.170, 0.280, 0.94 },
        border = { 0.100, 0.530, 0.780, 0.86 },
        text = { 0.680, 0.920, 1.000, 1 },
    },
    muted = {
        bg = { 0.045, 0.055, 0.090, 0.90 },
        border = { 0.110, 0.140, 0.230, 0.72 },
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
local function NextRow(section, height)
    local y = section._msuf2CursorY or -38
    section._msuf2CursorY = y - (height or 28)
    return section._msuf2ContentX or 14, y
end
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
local function SyncCheckedTexture(button, checked, enabled, alpha)
    local check = button and button.GetCheckedTexture and button:GetCheckedTexture()
    if (not check) and button and button.GetName and button:GetName() then check = _G[button:GetName() .. "Check"] end
    if not check then return end
    checked = checked and true or false
    alpha = alpha or (enabled and 0.96 or 0.42)
    if check.SetVertexColor then check:SetVertexColor(1, 1, 1, checked and alpha or 0) end
    if check.SetAlpha then check:SetAlpha(checked and alpha or 0) end
    if checked then
        if check.Show then check:Show() end
    elseif check.Hide then
        check:Hide()
    end
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
    local mul = enabled and (pressed and 1.14 or hover and 1.08 or 1) or 1
    local alpha = enabled and 1 or 0.45
    if button._msuf2SwitchFill then button._msuf2SwitchFill:SetVertexColor(min(bg[1] * mul, 1), min(bg[2] * mul, 1), min(bg[3] * mul, 1), bg[4] * alpha) end
    if button._msuf2SwitchEdge then button._msuf2SwitchEdge:SetVertexColor(min(br[1] * mul, 1), min(br[2] * mul, 1), min(br[3] * mul, 1), br[4] * alpha) end
    local knob = button._msuf2SwitchKnob
    if knob then
        local size = button._msuf2SwitchKnobSize or 18
        local pad = button._msuf2SwitchKnobPad or 2
        knob:ClearAllPoints()
        UseControlTexture(knob, button._msuf2SwitchKnobTexture or "Interface\\Buttons\\WHITE8X8")
        knob:SetSize(pressed and (size + 1) or size, pressed and (size + 1) or size)
        knob:SetPoint(checked and "RIGHT" or "LEFT", button, checked and "RIGHT" or "LEFT", checked and -pad or pad, 0)
        knob:SetVertexColor(kb[1], kb[2], kb[3], kb[4] * alpha)
        if knob.SetAlpha then knob:SetAlpha(alpha) end
    end
    if button._msuf2Label and button._msuf2Label.SetTextColor then
        local tx = enabled and (hover and T.colors.title or T.colors.text) or T.colors.dim
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
    btn._msuf2Label = T.Font(section, "GameFontHighlightSmall", Tr(label or ""), T.colors.text)
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
    rowHover:SetTexture("Interface\\Buttons\\WHITE8X8")
    rowHover:SetColorTexture(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 1)
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
            rowTex:SetColorTexture(c[1], c[2], c[3], 1)
            rowTex:SetAlpha(rowTarget)
            if rowTex.Show then rowTex:Show() end
        end
    end
    local function RefreshToggleFeedback(self, hover, down)
        local enabled = not (self.IsEnabled and not self:IsEnabled())
        local checked = (self.GetChecked and self:GetChecked()) and true or false
        local active = T.colors.checkActive or { 0.055, 0.145, 0.350, 1.00 }
        local inactive = T.colors.checkInactive or { 0.018, 0.030, 0.068, 1.00 }
        local bg = checked and active or inactive
        local br = checked
            and (T.colors.checkActiveEdge or { min(active[1] + 0.20, 1), min(active[2] + 0.31, 1), min(active[3] + 0.48, 1), 0.90 })
            or (T.colors.checkInactiveEdge or { 0.135, 0.210, 0.400, 1.00 })
        local bgMul = enabled and (down and 1.14 or hover and 1.08 or 1) or 1
        local borderAlpha = enabled
            and (checked and (down and 0.96 or hover and 0.88 or 0.76) or (down and 0.78 or hover and 0.64 or 0.50))
            or 0.30
        local alpha = enabled and 1 or 0.45
        if self._msuf2ToggleFill then
            local bgAlpha = checked and 0.96 or (down and 0.86 or hover and 0.78 or 0.70)
            self._msuf2ToggleFill:SetVertexColor(min(bg[1] * bgMul, 1), min(bg[2] * bgMul, 1), min(bg[3] * bgMul, 1), bgAlpha * alpha)
        end
        if self._msuf2ToggleEdge then self._msuf2ToggleEdge:SetVertexColor(br[1], br[2], br[3], borderAlpha * alpha) end
        local check = self.GetCheckedTexture and self:GetCheckedTexture()
        if check and check.SetVertexColor then check:SetVertexColor(1.000, 1.000, 1.000, enabled and 0.96 or 0.42) end
        SyncCheckedTexture(self, checked, enabled)
        SetToggleHoverVisual(self, hover and enabled, down and enabled)
        if self._msuf2Label and self._msuf2Label.SetTextColor then
            local tx = enabled and (hover and T.colors.title or T.colors.text) or T.colors.dim
            self._msuf2Label:SetTextColor(tx[1], tx[2], tx[3], tx[4] or 1)
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
    local fs = T.Font(parent, "GameFontHighlightSmall", Tr(text or ""), color or T.colors.muted)
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
    local cardBg = { 0.018, 0.026, 0.052, 0.86 }
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
    local heading = T.Font(card, "GameFontNormal", Tr(title or ""), T.colors.text)
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
    local cardBg = bg or { 0.018, 0.026, 0.052, 0.86 }
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
    local x, y = NextRow(section, 30)
    return CreateToggle(section, label, x, y)
end
function W.ToggleAt(section, label, x, y, labelWidth)
    return CreateToggle(section, label, x or 14, y or -38, labelWidth)
end
function W.SwitchAt(section, label, x, y, labelWidth, labelSide)
    local switchW, switchH = 44, 22
    local knobSize = 18
    local knobPad = 2
    local switchTrackTexture = (T.media and T.media.switchTrack) or (T.media and T.media.superellipse) or "Interface\\Buttons\\WHITE8X8"
    local switchKnobTexture = (T.media and T.media.switchKnob) or (T.media and T.media.sliderThumb) or (T.media and T.media.superellipse) or "Interface\\Buttons\\WHITE8X8"
    local btn = CreateFrame("CheckButton", nil, section)
    btn._msuf2ControlKind = "toggle"
    btn:SetPoint("TOPLEFT", x or 14, y or -38)
    btn:SetSize(switchW, switchH)
    if btn.RegisterForClicks then btn:RegisterForClicks("LeftButtonUp") end
    if btn.EnableMouse then btn:EnableMouse(true) end
    if btn.SetHitRectInsets then btn:SetHitRectInsets(-2, -2, -4, -4) end
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
    btn._msuf2ProxyBaseWidth = switchW + 14
    btn._msuf2UpdateToggleProxyBounds = UpdateToggleProxyBounds
    local side = labelSide or "RIGHT"
    local labelFS = T.Font(section, "GameFontHighlightSmall", Tr(label or ""), T.colors.text)
    SetSearchText(labelFS, label)
    labelFS:SetJustifyH(side == "LEFT" and "RIGHT" or "LEFT")
    if not labelWidth and section and section._msuf2Width then labelWidth = max(40, (section._msuf2Width or 0) - (x or 0) - switchW - 34) end
    if labelWidth then labelFS:SetWidth(max(20, labelWidth - (side == "RIGHT" and 22 or 0))) end
    if side == "LEFT" then
        labelFS:SetPoint("RIGHT", btn, "LEFT", -9, 0)
    else
        labelFS:SetPoint("LEFT", btn, "RIGHT", 9, 0)
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
    local label = T.Font(section, opts.labelFont or "GameFontHighlightSmall", Tr(opts.label or "Editing:"), opts.labelColor or T.colors.text)
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
        RegisterSearchObject(btn, item.text or item.label or item.value or "", "button")
        btn:SetPoint("LEFT", section, "TOPLEFT", x, y)
        btn._msuf2Value = item.value
        btn._msuf2BaseWidth = width
        T.CenterButtonLabel(btn)
        btn:SetScript("OnClick", function()
            if type(opts.setValue) == "function" then opts.setValue(item.value) end
            if type(opts.onChange) == "function" then opts.onChange(item.value) end
            if bar.Refresh then bar:Refresh() end
        end)
        bar.buttons[i] = btn
        x = x + width + gap
    end
    function bar:GetValue()
        if type(opts.getValue) == "function" then return opts.getValue() end
        return opts.value
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
    if shown and control._msuf2SetLayoutWidth then control:_msuf2SetLayoutWidth(control._msuf2RowWidth or control._msuf2RequestedWidth) end
end
local function SetEnabledState(frame, enabled)
    if not frame then return end
    if frame.Enable and frame.Disable then
        if enabled then frame:Enable() else frame:Disable() end
    elseif frame.SetEnabled then
        frame:SetEnabled(enabled)
    end
    if frame.EnableMouse then frame:EnableMouse(enabled and not frame._msuf2UseProxyMouse) end
end
local function SetTextEnabledColor(fontString, enabled)
    if not (fontString and fontString.SetTextColor) then return end
    local c = enabled and T.colors.text or T.colors.dim
    fontString:SetTextColor(c[1], c[2], c[3], c[4] or 1)
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
    if control.SetAlpha then control:SetAlpha(enabled and 1 or 0.45) end
    SetTextEnabledColor(control._msuf2Title, enabled)
    SetTextEnabledColor(control._msuf2Label, enabled)
    if control._msuf2RefreshSwitchVisual then control:_msuf2RefreshSwitchVisual() end
    if control._msuf2RefreshToggleFeedback then control:_msuf2RefreshToggleFeedback() end
    if control._msuf2LabelHit and control._msuf2LabelHit.EnableMouse then control._msuf2LabelHit:EnableMouse(enabled) end
    local edit = control.editBox or control.__MSUF_valueBox
    if edit then
        SetEnabledState(edit, enabled)
        if edit.SetAlpha then edit:SetAlpha(enabled and 1 or 0.45) end
    end
    if control._msuf2StepButtons then
        for i = 1, #control._msuf2StepButtons do
            local btn = control._msuf2StepButtons[i]
            SetEnabledState(btn, enabled)
            if btn.SetAlpha then btn:SetAlpha(enabled and 1 or 0.45) end
        end
    end
    if control.buttons then
        for i = 1, #control.buttons do
            local btn = control.buttons[i]
            SetEnabledState(btn, enabled)
            if btn.SetAlpha then btn:SetAlpha(enabled and 1 or 0.45) end
        end
    end
end
local function ApplyControlEnabled(control)
    if not control then return end
    local enabled = (control._msuf2DesiredEnabled ~= false) and not HasDisableGate(control)
    if control._msuf2AppliedEnabled == enabled then
        if control._msuf2ControlKind == "slider" and control._msuf2UpdateFill then control:_msuf2UpdateFill() end
        return
    end
    control._msuf2AppliedEnabled = enabled
    if control._msuf2ControlKind == "slider" then
        HideSliderTemplateParts(control)
        if T.StyleSlider then T.StyleSlider(control) end
        if control._msuf2UpdateFill then control:_msuf2UpdateFill() end
    end
    ApplyEnabledVisuals(control, enabled)
    if control._msuf2Chevron and control._msuf2Chevron.SetVertexColor then
        local c = enabled and T.colors.muted or T.colors.dim
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
    control._msuf2DisableGates[gateKey] = not (enabled and true or false)
    if control._msuf2DesiredEnabled == nil then
        local current = true
        if control.IsEnabled then current = control:IsEnabled() and true or false end
        control._msuf2DesiredEnabled = current
    end
    ApplyControlEnabled(control)
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
        widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 22)
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
    local x, y = NextRow(section, 30)
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
            return
        end
        local offset = (self.GetVerticalScroll and self:GetVerticalScroll()) or 0
        local h = (self.GetHeight and self:GetHeight()) or 0
        if offset == self._msuf2PinnedPreviewLastOffset and h == self._msuf2PinnedPreviewLastHeight then return end
        self._msuf2PinnedPreviewLastOffset = offset
        self._msuf2PinnedPreviewLastHeight = h
        if M.RefreshPinnedPreviews then M.RefreshPinnedPreviews(self) end
    end
    scroll:HookScript("OnVerticalScroll", RefreshIfPinned)
    scroll:HookScript("OnShow", RefreshIfPinned)
    scroll:HookScript("OnSizeChanged", RefreshIfPinned)
end
function M.RefreshPinnedPreviews(scroll)
    local list = M._pinnedPreviews
    if type(list) ~= "table" or #list == 0 then return end
    for i = 1, #list do
        local r = list[i]
        if r and r.update and (not scroll or r.scroll == scroll) then r.update() end
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
            if record and type(record.restore) == "function" then record.restore() end
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
    local originalParent = box:GetParent()
    local point, relTo, relPoint, xOfs, yOfs = box:GetPoint(1)
    local scrollParent = scroll:GetParent()
    local originalFrameLevel = (box.GetFrameLevel and box:GetFrameLevel()) or 1
    local pinned = false
    local record
    local pinBtn = box._msuf2PinButton
    if not pinBtn then
        pinBtn = T.Button(box, Tr("Pinned"), opts.buttonWidth or 86, 22)
        pinBtn._msuf2SearchText = "Pin Preview"
        pinBtn._msuf2ControlKind = "button"
        RegisterSearchObject(pinBtn, "Pin Preview", "button")
        box._msuf2PinButton = pinBtn
    else
        pinBtn:SetParent(box)
        pinBtn:ClearAllPoints()
        pinBtn:SetSize(opts.buttonWidth or 86, 22)
    end
    pinBtn:SetPoint("TOPRIGHT", box, "TOPRIGHT", -10, -6)
    local hint = opts.hint or box.hint or box._hint
    if hint and hint.SetPoint then
        hint:ClearAllPoints()
        hint:SetPoint("LEFT", opts.title or box.title or box._title, "RIGHT", 12, 0)
        hint:SetPoint("RIGHT", pinBtn, "LEFT", -10, 0)
        hint:SetJustifyH("LEFT")
    end
    local placeholder = body.CreateFontString and body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall") or nil
    if placeholder then
        placeholder:SetPoint("CENTER", body, "CENTER", 0, 0)
        placeholder:SetText(Tr("\226\134\145 Preview pinned at top"))
        placeholder:SetTextColor(0.38, 0.44, 0.58, 0.55)
        placeholder:Hide()
    end
    local function PinEnabled()
        return M.previewPinState[stateKey] ~= false
    end
    local function RefreshButton()
        local enabled = PinEnabled()
        local text = enabled and "Pinned" or "Pin Preview"
        if pinBtn._msuf2PinButtonText ~= text then
            pinBtn._msuf2PinButtonText = text
            pinBtn:SetText(text)
        end
        if pinBtn._msuf2PinButtonActive ~= enabled then
            pinBtn._msuf2PinButtonActive = enabled
            if pinBtn.SetActive then pinBtn:SetActive(enabled) end
        end
    end
    local function Restore()
        if box._msuf2PinnedPreviewRecord and box._msuf2PinnedPreviewRecord ~= record then return end
        if not pinned then return end
        pinned = false
        box._msuf2PinnedFloating = nil
        if placeholder then placeholder:Hide() end
        if scroll._msuf2PinnedPreviewActiveRecord == record then scroll._msuf2PinnedPreviewActiveRecord = nil end
        box:SetParent(originalParent)
        box:ClearAllPoints()
        box:SetPoint(point or "TOPLEFT", relTo or body, relPoint or "TOPLEFT", xOfs or 0, yOfs or 0)
        if box.SetFrameLevel then box:SetFrameLevel(originalFrameLevel) end
    end
    local function BodyVisible()
        --- IsVisible checks the full ancestor chain; IsShown only checks the frame itself
        if pageKey and M.activeKey and M.activeKey ~= pageKey then return false end
        if M.frame and M.frame.IsShown and not M.frame:IsShown() then return false end
        if pageWrapper and pageWrapper.IsShown and not pageWrapper:IsShown() then return false end
        if pageWrapper and pageWrapper.IsVisible and not pageWrapper:IsVisible() then return false end
        return (not body.IsVisible or body:IsVisible())
            and (not scroll.IsShown or scroll:IsShown())
    end
    local function ShouldPin()
        if not PinEnabled() or not BodyVisible() then return false end
        local offset = (scroll.GetVerticalScroll and scroll:GetVerticalScroll()) or 0
        local activateAt = opts.activateAfter or 64
        if offset <= (pinned and math.floor(activateAt * 0.45) or activateAt) then return false end
        local scrollTop = scroll.GetTop and scroll:GetTop()
        local bodyTop = body.GetTop and body:GetTop()
        if not (scrollTop and bodyTop) then return false end
        if bodyTop <= (scrollTop + (opts.threshold or 6)) then return false end
        return true
    end
    local function ApplyPinnedState()
        if box._msuf2PinnedPreviewRecord and box._msuf2PinnedPreviewRecord ~= record then return end
        if not BodyVisible() then
            Restore()
            if pageKey and box.Hide then box:Hide() end
            RefreshButton()
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
                box:SetPoint("TOPLEFT", scroll, "TOPLEFT", opts.left or 14, opts.top or -8)
                box:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -(opts.right or 14), opts.top or -8)
                if box.SetFrameLevel then box:SetFrameLevel(level) end
                if placeholder then placeholder:Show() end
            end
        else
            Restore()
        end
        RefreshButton()
    end
    pinBtn:SetScript("OnClick", function()
        M.previewPinState[stateKey] = not PinEnabled()
        if not PinEnabled() then
            pinned = true  --- force Restore() to run fully even if state drifted
            Restore()
        end
        ApplyPinnedState()
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
            if r.restore then r.restore() end
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
        box:HookScript("OnSizeChanged", ApplyPinnedState)
    end
    C_Timer.After(0, ApplyPinnedState)
    RefreshButton()
    return record
end

--- Slider wraps Blizzard's slider template but hides native art and stamps
--- callbacks so profile writes only happen when the effective value changes.
function W.Slider(section, label, minVal, maxVal, step, width)
    local x, y = NextRow(section, 48)
    local valueGap = 8
    local buttonGap = 2
    local stepButtonW = 18
    local editW = 52
    local minTrackW = 96
    local compactMinTrackW = 48
    local sliderH = 22
    local valueClusterW = valueGap + stepButtonW + buttonGap + editW + buttonGap + stepButtonW
    local compactValueClusterW = valueGap + editW
    width = width or 280
    if section and section._msuf2Width then
        local available = section._msuf2Width - x - 14
        if available > 0 and width > available then width = max(72, available) end
    end
    local title = T.Font(section, "GameFontHighlightSmall", Tr(label or ""), T.colors.text)
    SetSearchText(title, label)
    title:SetPoint("TOPLEFT", x, y)
    title:SetWidth(width)
    title:SetJustifyH("LEFT")
    sliderSerial = sliderSerial + 1
    local slider = CreateFrame("Slider", "MSUF2NativeSlider" .. sliderSerial, section)
    slider._msuf2Title = title
    slider._msuf2ControlKind = "slider"
    RegisterSearchObject(slider, label, "slider", { anchor = title })
    slider:SetPoint("TOPLEFT", x, y - 22)
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
        local btn = T.Button(section, text, 18, 20)
        SetSearchText(btn, text)
        return T.CenterButtonLabel(btn)
    end
    local minus = StepButton("-")
    local edit = CreateFrame("EditBox", nil, section, "InputBoxTemplate")
    edit:SetSize(52, 20)
    edit:SetAutoFocus(false)
    edit:SetJustifyH("CENTER")
    edit:SetNumeric(false)
    T.SkinEditBox(edit)
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
    slider:SetScript("OnMouseWheel", function(_, delta)
        if not delta or delta == 0 then return end
        StepBy(delta > 0 and 1 or -1)
    end)
    minus:SetScript("OnClick", function() StepBy(-1) end)
    plus:SetScript("OnClick", function() StepBy(1) end)
    return slider
end
function W.Segment(section, label, values, width)
    local x, y = NextRow(section, 48)
    local title = T.Font(section, "GameFontHighlightSmall", label or "", T.colors.text)
    SetSearchText(title, label)
    title:SetPoint("TOPLEFT", x, y)
    local holder = CreateFrame("Frame", nil, section)
    RegisterSearchObject(holder, label, "segment", { anchor = title, values = values })
    holder:SetPoint("TOPLEFT", x, y - 22)
    holder:SetSize(width or 360, 22)
    holder._msuf2ControlKind = "segment"
    holder._msuf2Title = title
    holder.buttons = {}
    holder.values = values or {}
    local count = #holder.values
    local gap = 6
    local bw = count > 0 and math.floor(((width or 360) - gap * (count - 1)) / count) or 80
    for i = 1, count do
        local item = holder.values[i]
        local btn = T.Button(holder, item.text or tostring(item.value), bw, 22)
        RegisterSearchObject(btn, item.text or item.label or item.value or "", "button")
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
    local x, y = NextRow(section, 50)
    width = width or 260
    local title = T.Font(section, "GameFontHighlightSmall", Tr(label or ""), T.colors.text)
    SetSearchText(title, label)
    title:SetPoint("TOPLEFT", x, y)
    local edit = CreateFrame("EditBox", nil, section, "InputBoxTemplate")
    edit._msuf2Title = title
    edit._msuf2ControlKind = "textinput"
    RegisterSearchObject(edit, label, "textinput", { anchor = title })
    edit:SetPoint("TOPLEFT", x, y - 22)
    edit:SetSize(width, 22)
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
    self._msuf2Swatch:SetVertexColor(self._msuf2R, self._msuf2G, self._msuf2B, 1)
end
local function ColorGetRGB(self) return self._msuf2R or 1, self._msuf2G or 1, self._msuf2B or 1 end
local function ColorSetOnColorChanged(self, fn) self._msuf2OnColorChanged = fn end
local function ColorApply(btn, r, g, b)
    btn:SetRGB(r, g, b)
    if btn._msuf2OnColorChanged then btn._msuf2OnColorChanged(r, g, b) end
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
    ColorApply(btn, r, g, b)
end
local colorPickerHideHooked = false
local function EnsureColorPickerHideHook()
    if colorPickerHideHooked or not (ColorPickerFrame and ColorPickerFrame.HookScript) then return end
    colorPickerHideHooked = true
    ColorPickerFrame:HookScript("OnHide", function(self)
        local btn = self and self._msuf2ColorOwner
        if btn and type(btn._msuf2CommitColorInteraction) == "function" then
            btn:_msuf2CommitColorInteraction()
        end
    end)
end
local function ColorButtonOnClick(self)
    if not ColorPickerFrame then return end
    local r, g, b = self:GetRGB()
    local picker = ColorPickerFrame
    EnsureColorPickerHideHook()
    if picker._msuf2ColorOwner and picker._msuf2ColorOwner ~= self and type(picker._msuf2ColorOwner._msuf2CommitColorInteraction) == "function" then
        picker._msuf2ColorOwner:_msuf2CommitColorInteraction()
    end
    picker._msuf2ColorOwner = self
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
end

--- Color buttons use Blizzard's shared ColorPickerFrame but keep previous RGB
--- values on the button so cancel can restore the UI state.
function W.Color(section, label)
    local x, y = NextRow(section, 34)
    local title = T.Font(section, "GameFontHighlightSmall", Tr(label or ""), T.colors.text)
    SetSearchText(title, label)
    title:SetPoint("TOPLEFT", x, y)
    title:SetWidth(230)
    local btn = CreateFrame("Button", nil, section)
    btn._msuf2Title = title
    btn._msuf2ControlKind = "color"
    RegisterSearchObject(btn, label, "color", { anchor = title })
    btn:SetPoint("TOPLEFT", x + 250, y + 2)
    btn:SetSize(44, 18)
    btn._msuf2Swatch, btn._msuf2Edge = T.CreateSuperellipseLayers(btn, "_msuf2Color", 1, "ARTWORK", "ARTWORK")
    btn._msuf2Edge:SetVertexColor(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.75)
    btn.SetRGB = ColorSetRGB
    btn.GetRGB = ColorGetRGB
    btn.SetOnColorChanged = ColorSetOnColorChanged
    btn:SetRGB(1, 1, 1)
    btn:SetScript("OnClick", ColorButtonOnClick)
    return btn
end
