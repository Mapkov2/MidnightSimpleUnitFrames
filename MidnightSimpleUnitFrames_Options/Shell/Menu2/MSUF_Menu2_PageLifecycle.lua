--- Owns page construction, cache disposal and deferred visibility/preview work.
--- Window owns geometry; live metrics are read only when a page is built.
local _, MSUF = ...
local M = MSUF.MSUF2
local T = M.Theme
local C_Timer = M.MenuTimer
local ALIASES = M.ALIASES
local EnsurePersistentMenuState = M.EnsurePersistentMenuState
local SearchBridge = M.SearchBridge
local ClearSearchRegistryPage = SearchBridge.ClearSearchRegistryPage
local MarkSearchIndexDirty = SearchBridge.MarkSearchIndexDirty
local BumpSearchInputSerial = SearchBridge.BumpSearchInputSerial
local CancelSearchBackgroundIndex = SearchBridge.CancelSearchBackgroundIndex
M.pages = M.pages or {}
M.pageOrder = M.pageOrder or {}
M.cache = M.cache or {}
M._msuf2PageLayoutVariants = M._msuf2PageLayoutVariants or {}

local function ApplyScrollMetrics()
    local CONTENT_W, CONTENT_H = M.GetContentMetrics()
    if not M.scrollChild then return end
    local height = CONTENT_H
    local entry = M.activeKey and M.cache and M.cache[M.activeKey]
    if entry and tonumber(entry.height) then height = math.max(height, entry.height) end
    M.scrollChild:SetSize(CONTENT_W - 12, height)
    if entry and entry.wrapper then entry.wrapper:SetSize(CONTENT_W - 12, height) end
    if M.scrollFrame and M.scrollFrame._msuf2RefreshScrollBar then M.scrollFrame:_msuf2RefreshScrollBar() end
end
local VISIBLE_SETTLE_RELAYOUT = { refreshUntrackedState = true }
local function QueueVisiblePageLayoutSettle(key, entry)
    if type(entry) ~= "table" then return end
    local queued = entry._msuf2VisibleLayoutSettleQueued
    if queued and queued.active then return end
    local function Settle()
        entry._msuf2VisibleLayoutSettleQueued = nil
        if M.activeKey ~= key or not M.cache or M.cache[key] ~= entry then return end
        if not (M.frame and M.frame.IsShown and M.frame:IsShown()) then return end
        if not (entry.wrapper and entry.wrapper.IsShown and entry.wrapper:IsShown()) then return end

        -- A fresh WoW client can accept the first custom semibold SetFont call
        -- before its glyph metrics are renderable. Reapply this page's fonts
        -- once after visibility and fall back immediately when the requested
        -- face still cannot render text. Cached pages pay this cost only once.
        if not entry._msuf2VisibleFontSettled and T and type(T.RefreshMenuFonts) == "function" then
            -- This is the one-shot visibility retry for freshly created font
            -- strings, not a font-setting change. Preserve the resolved-path
            -- cache populated while the page was built.
            if type(T.RefreshMenuFontStrings) == "function" and type(entry.fontStrings) == "table" then
                T.RefreshMenuFontStrings(entry.fontStrings, true, true)
            else
                T.RefreshMenuFonts(entry.wrapper, true, true)
            end
            entry._msuf2VisibleFontSettled = true
        end

        -- A cached/new page can become visible in the same layout turn in
        -- which its accordion headers were created. If their anchored width
        -- resolved before OnSizeChanged was hooked, the first label layout can
        -- retain a zero-width span until an unrelated menu scale/resize event.
        -- Refresh once after visibility has settled; this is cold-path work and
        -- installs no recurring handler.
        local builders = {}
        local seenBuilders = {}
        for _, body in pairs(entry.sections or {}) do
            local section = body and body._msuf2CollapsibleEntry
            if section then
                if type(section._msuf2RefreshLayout) == "function" then
                    section._msuf2RefreshLayout()
                end
                local builder = section.builder
                if builder and not seenBuilders[builder] then
                    seenBuilders[builder] = true
                    builders[#builders + 1] = builder
                end
            end
        end
        for i = 1, #builders do
            local builder = builders[i]
            if type(builder.RelayoutCollapsibles) == "function" then
                builder:RelayoutCollapsibles(VISIBLE_SETTLE_RELAYOUT)
            end
        end
        ApplyScrollMetrics()
    end
    entry._msuf2VisibleLayoutSettleQueued = C_Timer.After(0, Settle)
end
local fixedPreviewRestoreSerial = 0
local fixedPreviewExpandIntentSerial = 0
local fixedPreviewRebuildExpandPageKey
local function ActiveFixedPreviewIsExpanded(pageKey)
    local expander = M._msuf2ActiveFixedPreviewExpander
    return expander and expander.expanded == true and not expander.disposed
        and (not pageKey or not expander.pageKey or expander.pageKey == pageKey)
end
function M.RememberFixedPreviewExpansionForRebuild(pageKey)
    if not ActiveFixedPreviewIsExpanded(pageKey) then return false end
    fixedPreviewRebuildExpandPageKey = pageKey or M.activeKey
    return fixedPreviewRebuildExpandPageKey ~= nil
end
function M.ConsumeFixedPreviewExpansionForSelection(pageKey)
    local restore = ActiveFixedPreviewIsExpanded()
        or fixedPreviewRebuildExpandPageKey == pageKey
        or (type(M.ShouldExpandFixedPreview) == "function" and M.ShouldExpandFixedPreview())
    fixedPreviewRebuildExpandPageKey = nil
    return restore == true
end
local function FixedPreviewExpanderForEntry(entry)
    local records = type(entry) == "table" and entry.pageHeaders or nil
    if type(records) ~= "table" then return nil end
    for i = 1, #records do
        local expander = records[i] and records[i].previewExpander
        if expander and not expander.disposed and type(expander.Open) == "function" then return expander end
    end
    return nil
end
local function RestoreExpandedFixedPreview(key, entry, serial, options)
    options = type(options) == "table" and options or {}
    local pendingIntent = options.pendingIntent
    local resolved = false
    local function TryRestore()
        if resolved or serial ~= fixedPreviewRestoreSerial or M.activeKey ~= key
            or not (M.cache and M.cache[key] == entry)
        then
            resolved = true
            return
        end
        local frame = M.frame
        if pendingIntent and not (frame and frame._msuf2PendingFixedPreviewExpand == pendingIntent) then
            resolved = true
            return
        end
        local expander = FixedPreviewExpanderForEntry(entry)
        if not expander then return end
        -- Responsive headers can wrap differently after the new page variant
        -- is built. A resize-grip shrink therefore decides against the NEW
        -- stack, never against stale pre-rebuild geometry.
        if options.autoCompactIfNoFit == true
            and type(expander.CanFitPreferredExpansion) == "function"
            and expander:CanFitPreferredExpansion() == false
        then
            resolved = true
            return
        end
        if pendingIntent then
            -- Consume only when the current page actually has an expander to
            -- satisfy the request. Until here, deferred Unit construction keeps
            -- the exact same intent alive across the bounded retry window.
            frame._msuf2PendingFixedPreviewExpand = nil
        end
        if expander.expanded == true then
            resolved = true
            if options.ensureRoom == true and type(M.EnsureFixedPreviewExpansionRoom) == "function" then
                M.EnsureFixedPreviewExpansionRoom(expander)
            end
        elseif expander:Open(options.reason or "WINDOW_LAYOUT_RESTORE", { preserveExpandedZoom = true }) then
            resolved = true
        elseif pendingIntent and not frame._msuf2PendingFixedPreviewExpand
            and pendingIntent.serial == fixedPreviewExpandIntentSerial
            and M.activeKey == key and M.cache and M.cache[key] == entry
        then
            -- A temporarily hidden/not-yet-owned renderer can reject Open even
            -- after it exists. Restore the same intent for the remaining retry;
            -- never overwrite a newer user action.
            frame._msuf2PendingFixedPreviewExpand = pendingIntent
        end
    end
    TryRestore()
    if resolved or not (C_Timer and C_Timer.After) then return end
    -- Unit previews create their shared renderer on the first visible frame;
    -- Group and Class previews normally restore synchronously. These bounded
    -- retries cover that one deferred construction without adding a ticker.
    C_Timer.After(0, TryRestore)
    C_Timer.After(0.05, TryRestore)
end
function M.ClearPendingFixedPreviewExpansion(pageKey)
    local frame = M.frame
    local pending = frame and frame._msuf2PendingFixedPreviewExpand
    if pending and pageKey and pending.pageKey ~= pageKey then return false end
    -- Also invalidate already-scheduled Unit construction retries. This closes
    -- the A -> B -> A and hide -> show windows where activeKey/cache identity can
    -- otherwise become true again before a 0.05-second retry fires.
    fixedPreviewRestoreSerial = fixedPreviewRestoreSerial + 1
    fixedPreviewExpandIntentSerial = fixedPreviewExpandIntentSerial + 1
    if frame then frame._msuf2PendingFixedPreviewExpand = nil end
    return pending ~= nil
end
function M.ResolvePendingFixedPreviewExpansion(frame)
    frame = frame or M.frame
    local pending = frame and frame._msuf2PendingFixedPreviewExpand
    if not pending then return false end
    -- Replacement animations inherit the intent. Only the newest settled
    -- layout may decide whether the full canvas needs more window height.
    if frame._msuf2WindowLayoutAnim then return false end
    local key = pending.pageKey
    local entry = key and M.cache and M.cache[key]
    if pending.serial ~= fixedPreviewExpandIntentSerial or M.activeKey ~= key
        or not entry or (frame.IsShown and not frame:IsShown())
    then
        frame._msuf2PendingFixedPreviewExpand = nil
        return false
    end
    fixedPreviewRestoreSerial = fixedPreviewRestoreSerial + 1
    RestoreExpandedFixedPreview(key, entry, fixedPreviewRestoreSerial, {
        reason = "DEFERRED_EXPLICIT_EXPAND",
        ensureRoom = true,
        pendingIntent = pending,
    })
    return true
end
function M.RegisterPage(key, spec)
    if type(key) ~= "string" or type(spec) ~= "table" then return end
    if not M.pages[key] then M.pageOrder[#M.pageOrder + 1] = key end
    M.pages[key] = spec
end
local BUILD_LAYOUT_ONLY_RELAYOUT = { skipStateRefresh = true }
local function BuildPageEntry(key, hidden)
    local CONTENT_W, CONTENT_H = M.GetContentMetrics()
    if not M.scrollChild then return nil end
    key = ALIASES[key or ""] or key or "home"
    local spec = M.pages[key]
    local specVersion = spec and spec.version
    local layoutVersion = M._msuf2LayoutVersion or 0
    local layoutSlot = M.CurrentPageLayoutSlot()
    local cached = M.cache and M.cache[key]
    if cached and (cached._msuf2BuildIncomplete or (specVersion and cached.version ~= specVersion)) then
        M.InvalidatePage(key)
        cached = nil
    end
    local registryCleared = false
    if cached and not M.PageEntryMatchesLayout(cached, layoutSlot) then
        if cached.wrapper and cached.wrapper.Hide then cached.wrapper:Hide() end
        ClearSearchRegistryPage(key)
        registryCleared = true
        M.cache[key] = nil
        local variants = M._msuf2PageLayoutVariants[key]
        local variant = type(variants) == "table" and variants[layoutSlot] or nil
        if M.PageEntryMatchesLayout(variant, layoutSlot)
            and (not specVersion or variant.version == specVersion)
            and variant._msuf2Invalidated ~= true
        then
            cached = variant
            cached.layoutVersion = layoutVersion
            M.cache[key] = cached
            M.RestorePageEntryRegistrations(cached)
        else
            cached = nil
        end
    end
    if cached and cached.hiddenBuild == true and not hidden then
        M.DisposePageHeader(cached)
        if cached.wrapper and cached.wrapper.Hide then cached.wrapper:Hide() end
        if cached.wrapper and cached.wrapper.SetParent then cached.wrapper:SetParent(nil) end
        local variants = M._msuf2PageLayoutVariants[key]
        if type(variants) == "table" and variants[cached.layoutSlot] == cached then
            variants[cached.layoutSlot] = nil
        end
        M.cache[key] = nil
        cached = nil
    end
    if cached then return cached end
    if not registryCleared then ClearSearchRegistryPage(key) end
    local wrapper = CreateFrame("Frame", nil, M.scrollChild)
    wrapper:SetPoint("TOPLEFT", M.scrollChild, "TOPLEFT", 0, 0)
    wrapper:SetSize(CONTENT_W - 12, CONTENT_H)
    -- Building is always passive. SelectPage commits the entry, activates its
    -- optional fixed header, and only then reveals the completed wrapper.
    if wrapper.Hide then wrapper:Hide() end
    local entry = {
        key = key,
        _msuf2BuildIncomplete = true,
        wrapper = wrapper,
        refreshers = {},
        fontStrings = {},
        searchWidgets = {},
        height = CONTENT_H,
        version = specVersion,
        layoutVersion = layoutVersion,
        layoutSlot = layoutSlot,
        layoutWidth = CONTENT_W,
        layoutHeight = CONTENT_H,
        hiddenBuild = hidden and true or false,
    }
    M.cache[key] = entry
    M.RememberPageLayoutVariant(key, entry)
    local ctx = M.CreateContext(key, wrapper, entry)
    M.BuildSecondaryPageNav(ctx, key)
    if spec and type(spec.build) == "function" then
        entry._msuf2PendingContentHeight = nil
        entry._msuf2Building = true
        ctx._msuf2Building = true
        ctx._msuf2DeferContentHeight = true
        local result = spec.build(ctx)
        ctx._msuf2Building = nil
        entry._msuf2Building = nil
        local builders = ctx._msuf2PageBuilders
        if type(builders) == "table" then
            local nestedLayoutChanged = false
            for i = 1, #builders do
                local builder = builders[i]
                if builder and builder._msuf2RelayoutPending and builder.RelayoutCollapsibles then
                    builder._msuf2RelayoutPending = nil
                    local changed = builder:RelayoutCollapsibles(BUILD_LAYOUT_ONLY_RELAYOUT)
                    if changed and builder.parent ~= ctx.wrapper then nestedLayoutChanged = true end
                end
            end
            -- Nested builders can resize their owning collapsible while they
            -- relayout. Reflow the page-level builder once more afterwards so
            -- its final cursor, not an earlier nested height, owns the page.
            if nestedLayoutChanged then
                for i = 1, #builders do
                    local builder = builders[i]
                    if builder and builder.parent == ctx.wrapper and builder.RelayoutCollapsibles then
                        builder:RelayoutCollapsibles(BUILD_LAYOUT_ONLY_RELAYOUT)
                    end
                end
            end
        end
        local finalHeight = tonumber(result) or entry._msuf2PendingContentHeight or entry.height or CONTENT_H
        ctx._msuf2DeferContentHeight = nil
        entry._msuf2PendingContentHeight = nil
        ctx:SetContentHeight(finalHeight)
    else
        entry._msuf2PendingContentHeight = nil
        ctx._msuf2DeferContentHeight = true
        M.BuildPlaceholderPage(ctx, key)
        local finalHeight = entry._msuf2PendingContentHeight or entry.height or CONTENT_H
        ctx._msuf2DeferContentHeight = nil
        entry._msuf2PendingContentHeight = nil
        ctx:SetContentHeight(finalHeight)
    end
    if hidden and wrapper.Hide then wrapper:Hide() end
    entry._msuf2BuildIncomplete = nil
    return entry
end
-- Cold-path public entry point used by Search and Assistant V2. Callers must
-- invoke it only after an explicit menu interaction; it intentionally creates
-- and caches the requested page's real controls so RuntimeControlCatalog stays
-- the single executable source of truth.
M.BuildPageEntry = BuildPageEntry
function M.SelectPage(key)
    local CONTENT_W, CONTENT_H = M.GetContentMetrics()
    if M.BlockCombatAction and M.BlockCombatAction() then return false end
    EnsurePersistentMenuState()
    key = ALIASES[key or ""] or key or "home"
    -- Unknown slash/deep-link targets must never hide the current page and
    -- leave an empty content area. Removed legacy pages and typos safely land
    -- on the Dashboard instead.
    if not (M.pages and M.pages[key]) then key = "home" end
    local restoreExpandedFixedPreview = M.ConsumeFixedPreviewExpansionForSelection(key)
    if M.activeKey and key ~= M.activeKey then M.ClearPendingFixedPreviewExpansion() end
    local hasPendingFocus = false
    do
        local req = _G.MSUF_EM2_MenuFocusRequest
        hasPendingFocus = type(req) == "table"
            and req.explicit == true
            and req.consumed ~= true
            and (not req.pageKey or tostring(req.pageKey) == tostring(key))
        if not hasPendingFocus and type(M.CloseAutoFocusedSections) == "function" then M.CloseAutoFocusedSections(key) end
    end
    if key ~= "search" and M.activeKey == "search" then
        BumpSearchInputSerial()
        CancelSearchBackgroundIndex()
        M.searchResultsPending = nil
    end
    local spec = M.pages[key]
    local cached = M.cache[key]
    local specVersion = spec and spec.version
    if cached and (cached._msuf2BuildIncomplete or (specVersion and cached.version ~= specVersion)) then
        M.InvalidatePage(key)
        cached = nil
        if M.activeKey == key then M.activeKey = nil end
    end
    if key == M.activeKey and cached then
        M.sessionLastPage = key
        M.RememberPrimaryNavPage(key)
        M.SetActivePageHeader(cached)
        M.ReleasePinnedPreviews("SELECT_CACHED", key)
        M.ReleaseGFNativePreviews("SELECT_CACHED", key)
        cached.wrapper:Show()
        M.RunEntryRefreshers(cached)
        QueueVisiblePageLayoutSettle(key, cached)
        M.ResumeClassPowerPreview("SELECT_CACHED", key)
        M.ResumeGFNativePreviews("SELECT_CACHED", key)
        M.RunStickyHeaderActivation()
        M.RequestBossPagePreviewForKey(key)
        M.RequestGFPagePreviewForKey(key)
        if hasPendingFocus and type(M.FocusRequestedSection) == "function" then M.FocusRequestedSection(key, { flash = true }) end
        if M.RefreshToolbarPageReset then M.RefreshToolbarPageReset() end
        M.GuidedTourOnPageSelected(key)
        M.RefreshLayerOverviewContext()
        return true
    end
    local previousKey = M.activeKey
    local previous = previousKey and M.cache and M.cache[previousKey]
    M.ReleasePinnedPreviews("SELECT_PAGE", key)
    M.ReleaseGFNativePreviews("SELECT_PAGE", key)
    -- Clear the shared slot before touching either wrapper. Pages without an
    -- Editing/Page header therefore return to the original direct scroll
    -- anchor synchronously instead of inheriting stale chrome.
    M.SetActivePageHeader(nil, true)
    if previous and previous.wrapper and previous.wrapper.Hide then
        previous.wrapper:Hide()
    else
        M.HideAllCachedPages()
    end
    local entry = BuildPageEntry(key, false)
    if not entry then
        fixedPreviewRebuildExpandPageKey = nil
        M.SetActivePageHeader(nil)
        return false
    end
    entry.hiddenBuild = false
    M.activeKey = key
    M.SetActivePageHeader(entry)
    M.RefreshLayerOverviewContext()
    M.RecordPageNavigation(previousKey, key)
    M.RefreshPageHistoryNav()
    M.sessionLastPage = key
    if M.frame then M.frame._msufCurrentKey = key end
    if M.scrollChild then M.SetFrameHeightIfChanged(M.scrollChild, entry.height or CONTENT_H) end
    if M.scrollFrame then
        -- Every rebuild lands the reader at the top. That is right for a page
        -- switch or a fresh result list; callers that only regrew a card on the
        -- current page use M.RebuildPageKeepingScroll below instead.
        if M.scrollFrame.SetVerticalScroll then
            M.scrollFrame:SetVerticalScroll(0)
        elseif M.scrollFrame._msuf2RefreshScrollBar then
            M.scrollFrame:_msuf2RefreshScrollBar()
        end
    end
    entry.wrapper:Show()
    -- The wrapper is visible and activeKey committed: this is the earliest
    -- moment the docked panels' page-ownership gates pass, so wake their
    -- content now. Anything earlier sees a hidden wrapper and builds nothing.
    M.RunStickyHeaderActivation()
    M.RememberPrimaryNavPage(key)
    M.RunEntryRefreshers(entry)
    QueueVisiblePageLayoutSettle(key, entry)
    M.ResumeClassPowerPreview("SELECT_PAGE", key)
    M.ResumeGFNativePreviews("SELECT_PAGE", key)
    M.SetTitle(key)
    M.UpdateNav(key)
    if M.RefreshToolbarPageReset then M.RefreshToolbarPageReset() end
    M.RequestBossPagePreviewForKey(key)
    M.RequestGFPagePreviewForKey(key)
    if hasPendingFocus and type(M.FocusRequestedSection) == "function" then M.FocusRequestedSection(key, { flash = true }) end
    M.GuidedTourOnPageSelected(key)
    -- A spec-version invalidation may have occurred inside this SelectPage.
    -- The local restore decision already owns that transition, so do not leave
    -- a second one-shot intent behind for an unrelated later navigation.
    fixedPreviewRebuildExpandPageKey = nil
    if restoreExpandedFixedPreview then
        fixedPreviewRestoreSerial = fixedPreviewRestoreSerial + 1
        RestoreExpandedFixedPreview(key, entry, fixedPreviewRestoreSerial, {
            reason = "PAGE_STATE_RESTORE",
        })
    end
    return true
end
function M.InvalidatePage(key)
    if key then
        M.RememberFixedPreviewExpansionForRebuild(key)
        if key ~= "search" then MarkSearchIndexDirty() end
        M.ReleasePinnedPreviews("INVALIDATE_PAGE", nil, key)
        M.ReleaseGFNativePreviews("INVALIDATE_PAGE", nil)
        ClearSearchRegistryPage(key)
        if key == "home" then M.dashboardEditModeButton = nil end
        local entries, seen = {}, {}
        local entry = M.cache[key]
        if entry then entries[#entries + 1] = entry; seen[entry] = true end
        local variants = M._msuf2PageLayoutVariants[key]
        if type(variants) == "table" then
            for _, variant in pairs(variants) do
                if variant and not seen[variant] then
                    entries[#entries + 1] = variant
                    seen[variant] = true
                end
            end
        end
        -- Invalidated wrappers are released (hidden and unparented), never
        -- pooled: the next SelectPage builds the page from scratch. Known
        -- limitation. Invalidation is cold and user-driven only -- an undo/redo
        -- restore, a page reset, a page spec version bump, a search re-index,
        -- guided-tour transitions, a layout-variant switch or a preview
        -- texture-slot change -- so a pool would mostly hold frames whose
        -- registrations and refreshers must be reconciled before reuse.
        for i = 1, #entries do
            local invalidated = entries[i]
            invalidated._msuf2Invalidated = true
            M.DisposePageHeader(invalidated)
            if invalidated.wrapper then
                invalidated.wrapper:Hide()
                invalidated.wrapper:SetParent(nil)
            end
        end
        M.cache[key] = nil
        M._msuf2PageLayoutVariants[key] = nil
    else
        MarkSearchIndexDirty()
        local keys = {}
        for k in pairs(M.cache) do keys[k] = true end
        for k in pairs(M._msuf2PageLayoutVariants) do keys[k] = true end
        for k in pairs(keys) do M.InvalidatePage(k) end
    end
end

function M.RestoreFixedPreview(key, entry, options)
    fixedPreviewRestoreSerial = fixedPreviewRestoreSerial + 1
    RestoreExpandedFixedPreview(key, entry, fixedPreviewRestoreSerial, options)
end

function M.QueueFixedPreviewExpansion(key)
    fixedPreviewExpandIntentSerial = fixedPreviewExpandIntentSerial + 1
    M.frame._msuf2PendingFixedPreviewExpand = {
        serial = fixedPreviewExpandIntentSerial,
        pageKey = key,
    }
end

M.ApplyScrollMetrics = ApplyScrollMetrics
M.QueueVisiblePageLayoutSettle = QueueVisiblePageLayoutSettle
