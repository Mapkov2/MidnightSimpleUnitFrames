local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
--- Shell/Menu2/MSUF_Menu2_Widgets_PreviewDock.lua
--- Previews docked to a page: the sticky page header slot, the fixed preview
--- section with its expander, and pinned previews that follow their body.
---
--- Split from MSUF_Menu2_Widgets.lua; loads last of the widget files.

local _, MSUF = ...
local M = MSUF.MSUF2
local T = M.Theme
local W = M.Widgets
local C_Timer = M.MenuTimer or _G.C_Timer
local max = math.max
local min = math.min
local RegisterSearchObject = W.RegisterSearchObject

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
    -- logical children of their page for exact search routing.
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

-- Start with a compact reference so settings remain in view. An explicit
-- Expand action carries across pages for the rest of the UI session.
function M.SetFixedPreviewExpandedPreference(expanded)
    M._msuf2FixedPreviewExpandedPreference = expanded ~= false
end
function M.ShouldExpandFixedPreview()
    return M._msuf2FixedPreviewExpandedPreference == true
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

    local toolbar = PixelLayoutRegion(CreateFrame("Frame", nil, section))
    toolbar:SetPoint("TOPLEFT", section, "TOPLEFT", 0, 0)
    toolbar:SetPoint("TOPRIGHT", section, "TOPRIGHT", 0, 0)
    toolbar:SetHeight(32)
    toolbar._msuf2FixedPreviewToolbar = true
    if toolbar.SetFrameLevel and section.GetFrameLevel then toolbar:SetFrameLevel(section:GetFrameLevel() + 1) end
    if section.title then
        section.title:ClearAllPoints()
        section.title:SetPoint("LEFT", toolbar, "LEFT", 16, 0)
    end
    local divider = PixelLayoutRegion(toolbar:CreateTexture(nil, "ARTWORK"))
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
    local button = T.Button(toolbar, "Expand", tonumber(opts.buttonWidth) or 88, 20, { history = false })
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
            button:SetText("Compact Preview")
        else
            button:SetSize(88, 20)
            button:SetText("Expand")
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
-- Each queued check is its MenuTimer task: the menu runtime cancels pending
-- tasks on hide and in combat, and a cancelled task no longer counts as queued.
local function QueuePinnedPreviewSync(box)
    if not box then return end
    local function DispatchCurrent()
        local current = box._msuf2PinnedPreviewRecord
        if current and type(current.update) == "function" then current.update() end
    end
    local immediate = box._msuf2PinnedPreviewImmediateSyncQueued
    if not (immediate and immediate.active) then
        box._msuf2PinnedPreviewImmediateSyncQueued = C_Timer.After(0, function()
            box._msuf2PinnedPreviewImmediateSyncQueued = nil
            DispatchCurrent()
        end)
    end
    local settled = box._msuf2PinnedPreviewSettledSyncQueued
    if not (settled and settled.active) then
        box._msuf2PinnedPreviewSettledSyncQueued = C_Timer.After(0.05, function()
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
