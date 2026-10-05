local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
--- Shell/Menu2/MSUF_Menu2_Widgets_PageBuilder.lua
--- W.PageBuilder and everything private to it: menu focus requests, scrolling
--- to and flashing a focused section, collapsible sections and their header
--- layout, the per-build layout and section methods, nested aura builders and
--- the uniform settings rows (W.SettingsRows).
---
--- Split from MSUF_Menu2_Widgets.lua; loads right after it.

local _, MSUF = ...
local M = MSUF.MSUF2
local T = M.Theme
local W = M.Widgets
local Shared = W._Shared
local ExportPublic = MSUF.ExportPublic
local C_Timer = M.MenuTimer or _G.C_Timer
local floor = math.floor
local max = math.max
local min = math.min
local Tr = M.TranslateText
local ACCORDION_OPEN_CORNER_SIZE = Shared.ACCORDION_OPEN_CORNER_SIZE
local ACCORDION_HEADER_RIGHT_INSET = Shared.ACCORDION_HEADER_RIGHT_INSET
local ThemeColor = Shared.ThemeColor
local CreateAccordionRoundedRegions = W.CreateAccordionRoundedRegions
local CreateAccordionOpenHighlight = W.CreateAccordionOpenHighlight
local SetSearchText = Shared.SetSearchText
local SetSearchTitle = Shared.SetSearchTitle
local PlaceBackdropFrameBehindControls = Shared.PlaceBackdropFrameBehindControls
local RegisterSearchObject = W.RegisterSearchObject
local QueueDockedPreviewOwnershipRefresh = Shared.QueueDockedPreviewOwnershipRefresh

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
-- Every collapsible section reads two state tables while it builds and
-- refreshes. Once the persisted per-character state holds the bound table
-- there is nothing to resolve; only the first read (or a rebound table) runs
-- the full EnsurePersistentMenuState pass.
local function MenuStateTable(field)
    local bound = M[field]
    local state = M._persistentMenuState
    if bound ~= nil and state and state[field] == bound then return bound end
    M[field] = M.GetPersistentMenuStateTable(field)
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
-- Everything private to W.PageBuilder lives here: the per-build method
-- installers, the shared collapsible-header layout pass and the state notifier.
local PageBuilderStages = {}
function PageBuilderStages.NotifyCollapsibleSectionState(entry, open)
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
        local flash = PixelLayoutRegion(CreateFrame("Frame", nil, header))
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

--- Header layout for one collapsible entry: the UX summary, the badge row, or
--- the hint. Shared by every accordion instead of one closure body per section;
--- the section's wrapper hands in the regions it captured at creation.
function PageBuilderStages.RefreshCollapsibleHeaderLayout(entry, header, hint, label, arrow, builder)
    local headerW = (header.GetWidth and header:GetWidth()) or builder.width or 240
    local reserve = math.max(120, math.min(136, math.floor(headerW * 0.38 + 0.5)))
    local swatchReserve = (tonumber(entry._msuf2ColorSwatchReserve) or 0)
        + (tonumber(entry._msuf2FeatureSwitchReserve) or 0)
    if entry._msuf2UXSummary then
        local actions = tonumber(entry._msuf2ActionReserve) or 0
        if entry.featureSwitch then
            entry.featureSwitch:ClearAllPoints()
            entry.featureSwitch:SetPoint("RIGHT", header, "RIGHT", -14 - actions - (tonumber(entry._msuf2ColorSwatchReserve) or 0), 0)
        end
        if entry._msuf2SectionActions then
            entry._msuf2SectionActions:ClearAllPoints()
            entry._msuf2SectionActions:SetPoint("RIGHT", header, "RIGHT", -10 - (tonumber(entry._msuf2ColorSwatchReserve) or 0), 0)
        end
        local right = 16 + swatchReserve + actions
        local custom = entry._msuf2CustomBadge
        if custom then
            -- The Custom marker sits left of the switch and actions; a narrow
            -- header drops it before the title loses its last 150px.
            local customW = (custom.GetWidth and custom:GetWidth()) or 0
            if entry._msuf2CustomBadgeWanted == true and headerW - right - customW - 8 >= 150 then
                custom:ClearAllPoints()
                custom:SetPoint("RIGHT", header, "RIGHT", -right, 0)
                custom:Show()
                right = right + customW + 8
            else
                custom:Hide()
            end
        end
        local left = math.max(180, math.min(330, math.floor(headerW * 0.34)))
        local room = headerW - left - right
        local summary = entry._msuf2UXSummary
        summary:ClearAllPoints()
        summary:SetPoint("LEFT", header, "LEFT", left, 0)
        summary:SetWidth(math.max(1, room))
        local showSummary = not entry.open and room >= 110 and (summary:GetText() or "") ~= ""
        summary:SetShown(showSummary)
        hint:Hide()
        for _, badge in ipairs(entry._msuf2Badges or {}) do badge:Hide() end
        label:ClearAllPoints()
        label:SetPoint("LEFT", arrow, "RIGHT", 8, 0)
        label:SetPoint("RIGHT", header, "LEFT", showSummary and (left - 16) or math.max(80, headerW - right), 0)
        return
    end
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
--- The builder's vertical-flow and relayout methods; installed once per build.
function PageBuilderStages.InstallLayoutMethods(b, ctx, UpdateContentHeight)
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
                    -- Compared field by field: a relayout runs on every
                    -- disclosure and settle and must not build key strings.
                    if section._msuf2RelayoutParent ~= self.parent or section._msuf2RelayoutX ~= self.x
                        or section._msuf2RelayoutY ~= y or section._msuf2RelayoutH ~= h
                    then
                        section._msuf2RelayoutParent, section._msuf2RelayoutX = self.parent, self.x
                        section._msuf2RelayoutY, section._msuf2RelayoutH = y, h
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
                if entry._msuf2RelayoutParent ~= self.parent or entry._msuf2RelayoutX ~= self.x
                    or entry._msuf2RelayoutY ~= y or entry._msuf2RelayoutH ~= outerH or openChanged
                then
                    entry._msuf2RelayoutParent, entry._msuf2RelayoutX = self.parent, self.x
                    entry._msuf2RelayoutY, entry._msuf2RelayoutH = y, outerH
                    entry.outer:ClearAllPoints()
                    entry.outer:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, y)
                    entry.outer:SetHeight(outerH)
                    layoutChanged = true
                end
                if entry.body._msuf2ShownState ~= open then
                    entry.body._msuf2ShownState = open
                    if open and not entry.bodySurface then
                        entry.bodySurface = PageBuilderStages.CreateBodySurface(entry.outer, entry.headerHeight, false)
                    end
                    entry.body:SetShown(open)
                    if entry.bodySurface then entry.bodySurface:SetShown(open) end
                    layoutChanged = true
                end
                if openChanged or (opts and opts.refreshVisuals) then
                    if entry.body.SetAlpha and not entry._msuf2MotionActive then entry.body:SetAlpha(1) end
                    T.ApplyCollapseVisual(entry.arrow, entry.hint, open)
                    if entry._msuf2RefreshHeaderTone then entry._msuf2RefreshHeaderTone(false) end
                    if entry._msuf2RefreshColorSwatchVisibility then entry._msuf2RefreshColorSwatchVisibility() end
                    PageBuilderStages.NotifyCollapsibleSectionState(entry, open)
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
    --- opts.translated marks a title the caller composed from translated parts
    --- (M.Format with a translated argument); it is shown as it is.
    function b:Section(title, height, opts)
        local translated = opts ~= nil and opts.translated == true
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
        local fs = T.Font(section, "GameFontNormal", translated and "" or (title or ""), T.colors.text, "section")
        if translated then T.SetTranslatedText(fs, title or "") end
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
end
--- Closed-accordion decoration on demand. A section that builds closed gets
--- neither its body card nor its open highlight until it first opens; both are
--- hidden while closed and most sections never open in a session. A theme
--- change rebuilds every cached page and the highlight is repainted from the
--- live tokens on every tone refresh, so a late copy matches the eager one.
function PageBuilderStages.CreateBodySurface(outer, headerH, shown)
    local bodySurface = T.Panel(outer, nil, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft)
    T.ApplySurface(bodySurface, "card")
    bodySurface:SetPoint("TOPLEFT", outer, "TOPLEFT", 0, -(headerH + ACCORDION_OPEN_CORNER_SIZE))
    -- Match the header's scrollbar clearance. Extending the open surface to
    -- the full wrapper width puts its right border underneath the viewport
    -- edge, where it is visibly clipped while scrolling.
    bodySurface:SetPoint("BOTTOMRIGHT", outer, "BOTTOMRIGHT", -ACCORDION_HEADER_RIGHT_INSET, 0)
    bodySurface:SetShown(shown)
    PlaceBackdropFrameBehindControls(bodySurface, outer)
    return bodySurface
end
--- Repaints the open highlight from the live accent tokens (SavedVariables may
--- apply the accent after Options loaded); create = true builds it first.
function PageBuilderStages.PaintOpenHighlight(entry, create)
    local highlight = entry.headerOpenHighlight
    local from, to = entry._msuf2HeaderActiveFrom, entry._msuf2HeaderActiveTo
    if not (from and to and (create or (highlight and highlight.SetColors))) then return highlight end
    local activeBlue = ThemeColor("coreGlow", { 0.231, 0.510, 0.965, 1.00 })
    local activeDeep = ThemeColor("coreBlue", { 0.141, 0.365, 0.741, 1.00 })
    from[1], from[2], from[3] = activeBlue[1], activeBlue[2], activeBlue[3]
    to[1], to[2], to[3] = activeDeep[1], activeDeep[2], activeDeep[3]
    if highlight then
        highlight:SetColors(from, to)
    else
        highlight = CreateAccordionOpenHighlight(entry.header, from, to)
        entry.headerOpenHighlight = highlight
    end
    return highlight
end
--- The accordion builder; installed once per build.
function PageBuilderStages.InstallCollapsibleSection(b, ctx)
    function b:CollapsibleSection(id, title, height, defaultOpen)
        M.accordionState = MenuStateTable("accordionState")
        local collapseHintClickState = GetCollapseHintClickState()
        local sectionId = tostring(id or title or "section")
        local openHighlightEnabled = true
        local stateKey = tostring(ctx.key or "page") .. ":" .. sectionId
        local saved = M.accordionState[stateKey]
        local open = (saved == nil) and (defaultOpen and true or false) or (saved and true or false)
        local headerH = 32
        if not self._collapsibleStartY then self._collapsibleStartY = self.y end
        -- The wrapper must stay visually empty. A full card surface here sits
        -- underneath the header and fills its transparent rounded corners.
        local outer = PixelLayoutRegion(CreateFrame("Frame", nil, self.parent))
        outer._msuf2NoPanelNeon = true
        SetSearchTitle(outer, title)
        RegisterSearchObject(outer, title, "section")
        outer:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, self.y)
        outer:SetSize(self.width, headerH + (open and (height or 120) or 0))
        local bodySurface = open and PageBuilderStages.CreateBodySurface(outer, headerH, true) or nil
        local header = PixelLayoutRegion(CreateFrame("Button", nil, outer))
        SetSearchTitle(header, title)
        header:SetPoint("TOPLEFT", outer, "TOPLEFT", 0, 0)
        header:SetPoint("TOPRIGHT", outer, "TOPRIGHT", -ACCORDION_HEADER_RIGHT_INSET, 0)
        header:SetHeight(headerH)
        local headerBg = CreateAccordionRoundedRegions(header, "BACKGROUND", 0)
        local headerSurface = ThemeColor("coreSurface", T.colors.panel2)
        headerBg:SetColorTexture(headerSurface[1], headerSurface[2], headerSurface[3], 0.58)
        local headerOpenHighlight
        local headerActiveFrom, headerActiveTo
        if openHighlightEnabled then
            local headerActiveBlue = ThemeColor("coreGlow", { 0.231, 0.510, 0.965, 1.00 })
            local headerActiveDeep = ThemeColor("coreBlue", { 0.141, 0.365, 0.741, 1.00 })
            headerActiveFrom = { headerActiveBlue[1], headerActiveBlue[2], headerActiveBlue[3], 0.62 }
            headerActiveTo = { headerActiveDeep[1], headerActiveDeep[2], headerActiveDeep[3], 0.56 }
            if open then headerOpenHighlight = CreateAccordionOpenHighlight(header, headerActiveFrom, headerActiveTo) end
        end
        local arrow = PixelLayoutRegion(header:CreateTexture(nil, "OVERLAY"))
        arrow:SetSize(10, 10)
        arrow:SetPoint("LEFT", header, "LEFT", 12, 0)
        arrow:SetTexture(T.media.collapseArrow)
        -- Keep the selected face for accordion titles. Expressway's automatic
        -- Regular -> SemiBold face switch can cold-start blank until a relayout.
        local label = T.Font(header, "GameFontNormal", title or "", T.colors.text, "accordion")
        SetSearchText(label, title)
        label:SetJustifyH("LEFT")
        local hint = T.Font(header, "GameFontDisableSmall", "", T.colors.dim)
        hint:SetJustifyH("RIGHT")
        local contentW = math.min(self.width, M.formContentMaxWidth or 980)
        local body = PixelLayoutRegion(CreateFrame("Frame", nil, outer))
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
            _msuf2HeaderActiveFrom = headerActiveFrom,
            _msuf2HeaderActiveTo = headerActiveTo,
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
            PageBuilderStages.RefreshCollapsibleHeaderLayout(entry, header, hint, label, arrow, self)
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
        local PaintHeaderBorder = W.CreateAccordionBorder(header)
        local headerHoverColor = { 0, 0, 0, 1 }
        local function RefreshHeaderTone(hover)
            PaintHeaderBorder(entry.open, hover)
            -- SavedVariables may apply the selected accent after Options code
            -- has loaded. Resolve live tokens on every interaction transition
            -- instead of repainting a header from a stale Midnight snapshot.
            local liveSurface = ThemeColor("coreSurface", T.colors.panel2)
            local liveRaised = ThemeColor("coreRaised", { 0.026, 0.070, 0.110, 1.00 })
            local active = entry.open == true and entry.openHighlightEnabled == true
            local headerOpenHighlight = PageBuilderStages.PaintOpenHighlight(entry, active)
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
            local baseAlpha = entry._msuf2HeaderBaseAlpha or (entry.open and 0.64 or 0.58)
            if hover and entry._msuf2HeaderBaseColor then
                headerHoverColor[1] = min((base[1] or 0) * 1.16, 1)
                headerHoverColor[2] = min((base[2] or 0) * 1.16, 1)
                headerHoverColor[3] = min((base[3] or 0) * 1.16, 1)
                SetHeaderSolid(headerHoverColor, max(baseAlpha, 0.42))
            elseif entry.open then
                SetHeaderSolid(hover and liveRaised or base, baseAlpha)
            elseif hover then
                SetHeaderSolid(liveRaised, 0.78)
            else
                SetHeaderSolid(base, baseAlpha)
            end
        end
        entry._msuf2RefreshHeaderTone = RefreshHeaderTone
        entry.kind = "collapsible"
        local function SetSectionOpenImmediate(value)
            local wanted = value == true or value == 1
                or type(value) == "string" and (value:lower() == "true" or value:lower() == "on" or value == "1")
            if entry.open == wanted and not entry._msuf2MotionActive then return true end
            entry._msuf2MotionSerial = (entry._msuf2MotionSerial or 0) + 1
            if T.StopMotion then T.StopMotion(body) end
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
        header:SetScript("OnClick", function()
            local featureSwitch = entry.featureSwitch
            if featureSwitch
                and ((featureSwitch.IsMouseOver and featureSwitch:IsMouseOver())
                    or (entry._msuf2FeatureSwitchLabel and entry._msuf2FeatureSwitchLabel.IsMouseOver
                        and entry._msuf2FeatureSwitchLabel:IsMouseOver()))
            then
                if featureSwitch.IsEnabled and featureSwitch:IsEnabled() then
                    featureSwitch:Click("LeftButton")
                end
                return
            end
            local nextOpen = not entry.open
            local threshold = tonumber(T.collapseHintClickHideThreshold) or 8
            collapseHintClickState.total = math.min((tonumber(collapseHintClickState.total) or 0) + 1, threshold)
            RefreshCollapseHintSuppression(entry)
            SetSectionOpenImmediate(nextOpen)
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
            M.RegisterSearchWidget(header, {
                controlId = "menu2." .. identity,
                identityKey = identity,
                controlPath = identity:gsub("%.", "/"),
                pageKey = pageToken,
                label = M.Format("%s section", M.TranslateText(tostring(title or sectionId))),
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
end
--- Lazy accordion content. b:LazyCollapsibleSection builds a closed section's
--- content when it first opens instead of during the page build. Open sections,
--- hidden (search index) builds, opts.eager and M.EagerSections build at once,
--- exactly like a CollapsibleSection followed by its content. A closed section
--- arms three triggers and nothing else (no timer, no queue, no event): its
--- chained state refresher, a body OnShow hook and entry._msuf2EnsureContent
--- (W.EnsureSectionContent). A trigger under the configuration combat lock
--- builds nothing and stays armed for the next show or refresh.
local NO_LAZY_OPTS = {}
local LazySection = {}
--- The owning builder's panel (a facade tab or hand panel) is not selected.
function LazySection.ParentHidden(entry)
    local parent = entry.builder and entry.builder.parent
    return parent ~= nil and parent.IsShown ~= nil and not parent:IsShown()
end
function LazySection.Wanted(lazy)
    local entry = lazy.entry
    return entry.open and not (lazy.deferWhileHidden and LazySection.ParentHidden(entry)) and true or false
end
function LazySection.RunContent(lazy)
    lazy.build(lazy.body, lazy.entry)
    if lazy.onBuilt then lazy.onBuilt(lazy.body) end
end
--- Builders inside the new content queued their relayout while it was built.
--- Settle them first, so the owner lays out once with their final heights.
function LazySection.SettleNested(ctx, owner)
    local builders = ctx._msuf2PageBuilders
    if not builders then return end
    for i = 1, #builders do
        local nested = builders[i]
        if nested ~= owner and nested._msuf2RelayoutPending then nested:RelayoutCollapsibles() end
    end
end
--- Hands the section back the refresher it had before the lazy one wrapped it.
function LazySection.Disarm(lazy)
    local entry = lazy.entry
    if entry._msuf2RefreshState ~= lazy.refresh then return end
    entry._msuf2RefreshState = lazy.previous
    if lazy.tracked then entry._msuf2TrackedRefreshState = lazy.previous end
end
--- Builds the content once; true when it is built. A replaced page entry, a
--- build already running and the combat lock build nothing.
function LazySection.Build(lazy)
    if lazy.built then return lazy.ok end
    if lazy.building then return false end
    local combatLocked = M.IsConfigCombatLocked
    if combatLocked and combatLocked() then return false end
    local ctx = lazy.ctx
    local page = ctx.entry
    if page and M.cache and M.cache[ctx.key] ~= page then return false end
    lazy.building = true
    local wasBuilding, pageBuilding = ctx._msuf2Building, page and page._msuf2Building
    local wasIncomplete = page and page._msuf2BuildIncomplete
    -- An enclosing build runs the refreshers, the gates and the relayout itself.
    local enclosed = wasBuilding or pageBuilding
    ctx._msuf2Building = true
    if page then page._msuf2Building, page._msuf2BuildIncomplete = true, true end
    local refreshers = ctx.refreshers or (page and page.refreshers)
    local first = refreshers and #refreshers or 0
    -- Kernel/MSUF_Boundary.lua: a raising build is reported and leaves no
    -- building state behind. The page stays incomplete, so its next selection
    -- rebuilds it, as after a raise in the page build itself.
    local runStep = MSUF.RunHostAPIStep
    local ok = true
    if runStep then ok = runStep("Menu2 section content", LazySection.RunContent, lazy) else LazySection.RunContent(lazy) end
    local owner = lazy.entry.builder
    if not enclosed then LazySection.SettleNested(ctx, owner) end
    if not ok then wasIncomplete = true end
    ctx._msuf2Building = wasBuilding
    if page then page._msuf2Building, page._msuf2BuildIncomplete = pageBuilding, wasIncomplete end
    lazy.building, lazy.built, lazy.ok = false, true, ok and true or false
    LazySection.Disarm(lazy)
    if enclosed then return lazy.ok end
    if refreshers then
        for i = first + 1, #refreshers do
            local refresh = refreshers[i]
            if refresh then refresh() end
        end
    end
    local gate, gates = page and page._msuf2FrameGate, M.ControlGates
    if gate and gates and gates.ApplySections then gates.ApplySections(ctx, gate.key, gate.enabled, gate.opts) end
    if owner and owner.RelayoutCollapsibles then owner:RelayoutCollapsibles() end
    return lazy.ok
end
function LazySection.Arm(ctx, body, entry, build, opts)
    local previous = entry._msuf2RefreshState
    local lazy = {
        ctx = ctx, body = body, entry = entry, build = build, onBuilt = opts.onBuilt,
        deferWhileHidden = opts.deferWhileHidden, previous = previous,
        tracked = previous ~= nil and entry._msuf2TrackedRefreshState == previous,
    }
    lazy.refresh = function(state)
        if not lazy.built and LazySection.Wanted(lazy) then LazySection.Build(lazy) end
        if previous then return previous(state) end
    end
    entry._msuf2RefreshState = lazy.refresh
    if lazy.tracked then entry._msuf2TrackedRefreshState = lazy.refresh end
    entry._msuf2EnsureContent = function() return LazySection.Build(lazy) end
    if body.HookScript then
        body:HookScript("OnShow", function()
            if not lazy.built and LazySection.Wanted(lazy) then LazySection.Build(lazy) end
        end)
    end
end
--- Builds a lazy section's content now (exact search, page resolvers). Takes
--- the body (or outer) or its collapsible entry. True when the content exists:
--- built now, built before, or never lazy.
function W.EnsureSectionContent(section)
    if section == nil then return false end
    local entry = section._msuf2CollapsibleEntry or section
    local ensure = entry._msuf2EnsureContent
    if ensure then return ensure() end
    return true
end
--- The lazy accordion builder; installed once per build.
---   body = b:LazyCollapsibleSection(id, title, height, defaultOpen, build, opts)
---   build(body, entry)       the content; ends with FinishSection as usual
---   opts.shell(body, entry)  runs now: everything a closed header shows
---   opts.eager               true, or fn(ctx) returning true: build now
---   opts.deferWhileHidden    open, but the owning builder's panel is hidden:
---                            build on its first show
---   opts.onBuilt(body)       post-processing that needs the content widgets
function PageBuilderStages.InstallLazySection(b, ctx)
    function b:LazyCollapsibleSection(id, title, height, defaultOpen, build, opts)
        opts = opts or NO_LAZY_OPTS
        local page = ctx.entry
        local before = page and page._msuf2GuidedTourOrder or 0
        -- Through self: builder facades route the shell to their tab builder,
        -- and lazy proxies hand back the body they are filling right now.
        local body = self:CollapsibleSection(id, title, height, defaultOpen)
        local entry = body and body._msuf2CollapsibleEntry
        if opts.shell then opts.shell(body, entry) end
        local eager = opts.eager
        if eager and eager ~= true then eager = eager(ctx) end
        -- A body this call did not create belongs to a build already running.
        local created = entry and (entry.guidedOrder == nil or entry.guidedOrder > before)
        if eager or not created or M.EagerSections or ctx.hiddenBuild or (page and page.hiddenBuild)
            or (entry.open and not (opts.deferWhileHidden and LazySection.ParentHidden(entry)))
        then
            build(body, entry)
            if opts.onBuilt then opts.onBuilt(body) end
        else
            LazySection.Arm(ctx, body, entry, build, opts)
        end
        return body
    end
end
--- Headers, spacers, auto-height and declarative cards; installed once per build.
function PageBuilderStages.InstallSectionMethods(b, ctx, UpdateContentHeight)
    function b:Header(title, subtitle, height)
        local section = T.Panel(self.parent, nil, T.colors.panel2, T.colors.border)
        SetSearchTitle(section, title)
        RegisterSearchObject(section, title, "section")
        section:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, self.y)
        section:SetSize(self.width, height or 78)
        local fs = T.Font(section, "GameFontNormalLarge", title or "", T.colors.text, "heading")
        SetSearchText(fs, title)
        fs:SetPoint("TOPLEFT", 16, -12)
        section.title = fs
        if subtitle and subtitle ~= "" then
            local sub = W.Description(section, subtitle, 16, -38, self.width - 32, title)
            sub:ClearAllPoints()
            sub:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -8)
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
end
function W.PageBuilder(ctx, opts)
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
    PageBuilderStages.InstallLayoutMethods(b, ctx, UpdateContentHeight)
    PageBuilderStages.InstallCollapsibleSection(b, ctx)
    PageBuilderStages.InstallLazySection(b, ctx)
    PageBuilderStages.InstallSectionMethods(b, ctx, UpdateContentHeight)
    return b
end

--- Height each auto-flowing widget kind consumes inside a settings row, matching the
--- NextRow() advances in the individual W.* constructors.
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

--- Keep field labels aligned to the same reading edge across every control kind.
local CARD_MOVE_JUSTIFY = { slider = "LEFT", dropdown = "LEFT", segment = "LEFT", textinput = "LEFT" }

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
        if row.valueBoxWidth and widget.SetValueBoxWidth then widget:SetValueBoxWidth(row.valueBoxWidth) end
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

--- Uniform multi-column settings rows inside an EXISTING section or card (the
--- "Zeilen-Grid" building block): fixed cell metrics, cells flow left-to-right
--- then top-to-bottom, optional per-row reset-to-default action. Uses the same
--- row specs, constructors and binders as hand-placed controls, so converted sections
--- keep their control behavior and Search metadata unchanged.
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
                local resetBtn = PixelLayoutRegion(CreateFrame("Button", nil, parent))
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

-- Nested aura sections share height ownership and deferred parent relayout.
local function CreateNestedAuraBuilder(ctx, parentBuilder, body)
    local entry = body and body._msuf2CollapsibleEntry
    if not (entry and W.PageBuilder) then return parentBuilder end
    local bodyWidth = body._msuf2Width or parentBuilder.width or 720
    local nestedCtx = setmetatable({
        wrapper = body,
        width = max(320, bodyWidth - 24),
        key = ctx and ctx.key,
        entry = ctx and ctx.entry,
        _msuf2ContentX = 12,
        _msuf2TopInset = 0,
    }, { __index = ctx })
    function nestedCtx:SetContentHeight(height)
        height = max(80, math.ceil(tonumber(height) or 80))
        if entry.contentHeight == height then return end
        entry.contentHeight = height
        body:SetHeight(height)
        if parentBuilder.RequestRelayoutCollapsibles then parentBuilder:RequestRelayoutCollapsibles() end
    end
    local nestedBuilder = W.PageBuilder(nestedCtx)
    entry._msuf2SettleContentLayout = function()
        if nestedBuilder.RelayoutCollapsibles then nestedBuilder:RelayoutCollapsibles() end
        nestedCtx:SetContentHeight(math.abs(nestedBuilder.y) + 42)
    end
    return nestedBuilder
end
W.CreateNestedAuraBuilder = CreateNestedAuraBuilder
