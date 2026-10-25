-- Window: Lifecycle responsibility.
local addonName, MSUF = ...
local M = MSUF.MSUF2
local Parts = M.WindowParts
local ApplyMenuFramePriority = Parts.ApplyMenuFramePriority
local ApplyMenuFrameScale = Parts.ApplyMenuFrameScale
local BuildWindowChrome = Parts.BuildWindowChrome
local BuildWindowShell = Parts.BuildWindowShell
local BuildWindowToolbar = Parts.BuildWindowToolbar
local CONTENT_H = Parts.CONTENT_H
local CONTENT_W = Parts.CONTENT_W
local EffectiveMenuScale = Parts.EffectiveMenuScale
local EnsurePersistentMenuState = Parts.EnsurePersistentMenuState
local HideSlashMenuAndMinibar = Parts.HideSlashMenuAndMinibar
local IS_FOREVER = Parts.IS_FOREVER
local InstallWindowInteractions = Parts.InstallWindowInteractions
local InstallWindowLifecycle = Parts.InstallWindowLifecycle
local InstallWindowStatusRuntime = Parts.InstallWindowStatusRuntime
local MaximizeSlashMenuWindow = Parts.MaximizeSlashMenuWindow
local MinimizeSlashMenuWindow = Parts.MinimizeSlashMenuWindow
local PixelLayoutRegion = Parts.PixelLayoutRegion
local RaiseForeverPadCursor = Parts.RaiseForeverPadCursor
local RefreshDashboardEditModeButton = Parts.RefreshDashboardEditModeButton
local RestoreMinimizedSlashMenu = Parts.RestoreMinimizedSlashMenu
local RestoreSlashMenuWindow = Parts.RestoreSlashMenuWindow
local T = Parts.T
local max = Parts.max

local function ForwardMenuScrollWheel(delta)
    if not delta or delta == 0 then return false end
    local scroll = M.scrollFrame
    if not scroll then return false end
    local scrollBy = scroll._msuf2ScrollByWheel
    if type(scrollBy) == "function" then
        scrollBy(delta)
        return true
    end
    local handler = scroll.GetScript and scroll:GetScript("OnMouseWheel")
    if type(handler) ~= "function" then return false end
    handler(scroll, delta)
    return true
end
M.ForwardMenuScrollWheel = ForwardMenuScrollWheel

--- LayoutPageHeaderHost's native half. Every page switch lays the slot out,
--- mostly with nothing changed, and re-anchoring the ScrollFrame invalidates
--- the whole page tree. Only this function anchors the two frames, so the same
--- geometry whose anchors still point where it left them writes nothing.
local function AnchorPageHeaderHost(pageHeaderHost, scroll, topOwner, layoutHost, stackHeight, clipped)
    if pageHeaderHost._msuf2LaidOwner == topOwner and pageHeaderHost._msuf2LaidHost == layoutHost
        and pageHeaderHost._msuf2LaidHeight == stackHeight and pageHeaderHost._msuf2LaidClipped == clipped
    then
        local _, hostAnchor = pageHeaderHost:GetPoint(1)
        local _, scrollAnchor = scroll:GetPoint(1)
        if hostAnchor == topOwner and scrollAnchor == (stackHeight > 0 and pageHeaderHost or topOwner) then return end
    end
    pageHeaderHost._msuf2LaidOwner, pageHeaderHost._msuf2LaidHost = topOwner, layoutHost
    pageHeaderHost._msuf2LaidHeight, pageHeaderHost._msuf2LaidClipped = stackHeight, clipped
    pageHeaderHost:ClearAllPoints()
    pageHeaderHost:SetPoint("TOPLEFT", topOwner, "BOTTOMLEFT", 0, 0)
    -- The fixed panel keeps the PageBuilder width (content - 32) with
    -- equal 12 px side insets.  The ScrollFrame remains 16 px narrower
    -- on the right to reserve its scrollbar gutter.
    pageHeaderHost:SetPoint("TOPRIGHT", topOwner, "BOTTOMRIGHT", -8, 0)
    scroll:ClearAllPoints()
    if stackHeight > 0 then
        pageHeaderHost:SetHeight(stackHeight)
        -- On a window too short for the full stack, clip its overflow rather
        -- than painting over the settings body or outside the window.
        if pageHeaderHost.SetClipsChildren then pageHeaderHost:SetClipsChildren(clipped and true or false) end
        pageHeaderHost:Show()
        scroll:SetPoint("TOPLEFT", pageHeaderHost, "BOTTOMLEFT", 0, 0)
    else
        pageHeaderHost:SetHeight(0)
        pageHeaderHost:Hide()
        -- Plain pages bypass the optional slot completely. A hidden
        -- zero-height intermediary previously left several menus blank
        -- until a later layout pass repaired their mixed anchors.
        scroll:SetPoint("TOPLEFT", topOwner, "BOTTOMLEFT", 0, 0)
    end
    scroll:SetPoint("BOTTOMRIGHT", layoutHost, "BOTTOMRIGHT", -24, 0)
end

local function InstallStickyHeaderActivation(scroll, pageHeaderHost, LayoutPageHeaderHost, RefreshPinnedHeaderGeometry)
    --- Geometry only. Content wake-up runs separately (RunStickyHeaderActivation)
    --- once the page wrapper is shown, because a docked panel's page-visibility
    --- gates would reject any work started while the wrapper is still hidden.
    local function ActivateStickyHeaderStack(entry)
        local records = type(entry) == "table" and entry.pageHeaders or nil
        local active = scroll._msuf2StickyPageHeaders or {}
        for i = #active, 1, -1 do active[i] = nil end
        if type(records) ~= "table" then return active end
        local stackOffset = 0
        for i = 1, #records do
            local record = records[i]
            if record and not record.disposed and record.entry == entry and record.Activate then
                if record:Activate(pageHeaderHost, stackOffset) then
                    stackOffset = stackOffset + max(0, tonumber(record.hostHeight) or 0)
                    active[#active + 1] = record
                end
            end
        end
        return active
    end
    --- The post-show half of page selection for docked panels. They live outside
    --- the page wrapper, so wrapper:Show() cannot reach them; SelectPage calls
    --- this after the wrapper is visible so every page-ownership gate inside the
    --- callbacks (activeKey, wrapper shown) evaluates against the final state.
    function M.RunStickyHeaderActivation()
        local list = scroll._msuf2StickyPageHeaders
        if type(list) ~= "table" then return 0 end
        local ran = 0
        for i = 1, #list do
            local record = list[i]
            if record and record.active and not record.disposed and type(record.onActivate) == "function" then
                record.onActivate(record)
                ran = ran + 1
            end
        end
        M.ResolvePendingFixedPreviewExpansion(M.frame)
        return ran
    end
    function M.SetActivePageHeader(entry, deferLayout)
        local previous = scroll._msuf2StickyPageHeaders
        if type(previous) == "table" then
            for i = 1, #previous do
                local record = previous[i]
                if record and record.Deactivate and (type(entry) ~= "table" or record.entry ~= entry) then
                    record:Deactivate()
                end
            end
        end
        scroll._msuf2StickyPageHeaders = ActivateStickyHeaderStack(entry)
        -- Retained for the single-panel readers that predate the stack.
        scroll._msuf2StickyPageHeader = scroll._msuf2StickyPageHeaders[1]
        if not deferLayout then
            LayoutPageHeaderHost()
            RefreshPinnedHeaderGeometry()
        end
        return scroll._msuf2StickyPageHeader ~= nil
    end
    --- Re-drive the slot after a docked panel changed its own height, without
    --- re-parenting anything: only the stack offsets and the host height move.
    function M.RelayoutPageHeaderHost()
        local list = scroll._msuf2StickyPageHeaders
        if type(list) ~= "table" or #list == 0 then return false end
        local stackOffset = 0
        for i = 1, #list do
            local record = list[i]
            if record and record.active and not record.disposed and record.Activate then
                record:Activate(pageHeaderHost, stackOffset)
                stackOffset = stackOffset + max(0, tonumber(record.hostHeight) or 0)
            end
        end
        LayoutPageHeaderHost()
        RefreshPinnedHeaderGeometry()
        return true
    end

end

local function BuildWindowScrollHost(state)
    local CONTENT_W, CONTENT_H = M.GetContentMetrics()
    local f = state.frame
    local host, status = f.host, f.status
    local pageHeaderHost = PixelLayoutRegion(CreateFrame("Frame", nil, host))
    pageHeaderHost:SetHeight(0)
    pageHeaderHost:Hide()
    -- Structural only: the page panel already owns its rounded glass surface,
    -- so the host paints no background of its own. Clipping is normally off
    -- (it cuts the panels' overscanned nine-slice corners) and turns on only
    -- while the stack overflows a too-short window - see LayoutPageHeaderHost.
    f.pageHeaderHost = pageHeaderHost
    M.pageHeaderHost = pageHeaderHost
    local scroll = PixelLayoutRegion(CreateFrame("ScrollFrame", nil, host))
    f.scrollFrame = scroll
    M.scrollFrame = scroll
    local activeTopOwner, activeLayoutHost = status, host
    local function RefreshPinnedHeaderGeometry()
        if scroll._msuf2RefreshScrollBar then scroll:_msuf2RefreshScrollBar() end
        M.RefreshPinnedPreviews(scroll)
    end
    --- Compact fixed chrome keeps a useful settings viewport. An explicitly
    --- expanded preview behaves like an accordion and may consume nearly all
    --- of it: the ScrollFrame still begins below the complete preview instead
    --- of letting the preview overlay or clip against the settings body.
    local STICKY_HEADER_MIN_BODY_REVEAL = 120
    local STICKY_HEADER_EXPANDED_BODY_REVEAL = 16
    local function ReadFrameCoordinate(frame, getter)
        if not (frame and type(frame[getter]) == "function") then return nil end
        local value = frame[getter](frame)
        if type(canaccessvalue) == "function" and canaccessvalue(value) ~= true then return nil end
        if type(issecretvalue) == "function" and issecretvalue(value) == true then return nil end
        return tonumber(value)
    end
    local function HeaderAvailableHeight(topOwner, layoutHost)
        topOwner = topOwner or activeTopOwner or status
        layoutHost = layoutHost or activeLayoutHost or host
        local ownerBottom = ReadFrameCoordinate(topOwner, "GetBottom")
        local hostBottom = ReadFrameCoordinate(layoutHost, "GetBottom")
        if ownerBottom and hostBottom and ownerBottom > hostBottom then return ownerBottom - hostBottom end
        -- Construction-test and first-layout fallback. Guided chrome is
        -- anchored below status, while the normal top owner is status itself.
        local available = (tonumber(layoutHost and layoutHost.GetHeight and layoutHost:GetHeight()) or 0)
            - (tonumber(topOwner and topOwner.GetHeight and topOwner:GetHeight()) or 0)
        if topOwner ~= status then
            available = available - (tonumber(status and status.GetHeight and status:GetHeight()) or 0)
        end
        return max(0, available)
    end
    function M.GetPageHeaderAvailableHeight()
        return HeaderAvailableHeight(activeTopOwner, activeLayoutHost)
    end
    local function StickyHeaderStackHeight(topOwner, layoutHost)
        local list = scroll._msuf2StickyPageHeaders
        if type(list) ~= "table" or #list == 0 then return 0 end
        local total = 0
        for i = 1, #list do
            local record = list[i]
            if record and record.active then total = total + max(0, tonumber(record.hostHeight) or 0) end
        end
        if total <= 0 then return 0 end
        local available = HeaderAvailableHeight(topOwner, layoutHost)
        local minimumReveal = STICKY_HEADER_MIN_BODY_REVEAL
        for i = 1, #list do
            local record = list[i]
            if record and record.active and record.previewExpander
                and record.previewExpander.expanded == true
            then
                minimumReveal = STICKY_HEADER_EXPANDED_BODY_REVEAL
                break
            end
        end
        local limit = available - minimumReveal
        if limit > 0 and total > limit then return limit, true end
        return total, false
    end
    local function LayoutPageHeaderHost(topOwner, layoutHost)
        if topOwner then activeTopOwner = topOwner end
        if layoutHost then activeLayoutHost = layoutHost end
        topOwner = activeTopOwner or status
        layoutHost = activeLayoutHost or host
        local stackHeight, clipped = StickyHeaderStackHeight(topOwner, layoutHost)
        AnchorPageHeaderHost(pageHeaderHost, scroll, topOwner, layoutHost, stackHeight, clipped)
        scroll._msuf2TourAnchorOwner = topOwner
        scroll._msuf2TourAnchorHost = layoutHost
        scroll._msuf2MaxScroll = nil
        scroll._msuf2SmoothScrollTarget = nil
    end
    M.LayoutPageHeaderHost = LayoutPageHeaderHost
    InstallStickyHeaderActivation(scroll, pageHeaderHost, LayoutPageHeaderHost, RefreshPinnedHeaderGeometry)

    LayoutPageHeaderHost(status, host)
    local child = PixelLayoutRegion(CreateFrame("Frame", nil, scroll))
    child:SetSize(CONTENT_W - 12, CONTENT_H)
    scroll:SetScrollChild(child)
    M.scrollChild = child
    T.StyleScrollFrame(scroll, host)
    pageHeaderHost:EnableMouseWheel(true)
    if pageHeaderHost.SetPropagateMouseWheel then pageHeaderHost:SetPropagateMouseWheel(false) end
    pageHeaderHost:SetScript("OnMouseWheel", function(_, delta)
        ForwardMenuScrollWheel(delta)
    end)
    M.InstallGuidedTourChrome(f, status, host, scroll)
end

local function BuildWindow()
    if M.frame then return M.frame end
    T.ApplyMenuAccent()
    local state = BuildWindowShell()
    InstallWindowInteractions(state)
    BuildWindowChrome(state)
    BuildWindowToolbar(state)
    InstallWindowStatusRuntime(state)
    InstallWindowLifecycle(state)
    BuildWindowScrollHost(state)
    local f = state.frame
    M.frame = f
    return f
end
M.Assign(M, {
    RefreshDashboardEditModeButton = RefreshDashboardEditModeButton,
    GetEffectiveMenuScale = EffectiveMenuScale, ApplyMenuFrameScale = ApplyMenuFrameScale,
    HideSlashMenuAndMinibar = HideSlashMenuAndMinibar,
})
for name, windowAction in pairs({
    MinimizeSlashMenuWindow = MinimizeSlashMenuWindow, MaximizeSlashMenuWindow = MaximizeSlashMenuWindow,
    RestoreSlashMenuWindow = RestoreSlashMenuWindow, RestoreMinimizedSlashMenu = RestoreMinimizedSlashMenu,
}) do
    M[name] = function(frame) return windowAction(frame or M.frame) end
end
function M.Open(pageKey)
    if M.BlockCombatAction and M.BlockCombatAction() then return false end
    EnsurePersistentMenuState()
    M.ApplyLocaleSelection()
    local f = BuildWindow()
    if M.minimizedBar and M.minimizedBar.Hide then M.minimizedBar:Hide() end
    f._msuf2Minimized = nil
    ApplyMenuFrameScale(f)
    ApplyMenuFramePriority(f)
    -- Cached pages can outlive external model changes while the window is
    -- hidden, including specialization-driven profile switches. Advance the
    -- shared snapshot revision once per explicit open so SelectPage refreshes
    -- the visible page from the current MSUF_DB instead of reusing stale UI.
    M.MarkMenuDataDirty("menu-open")
    f:Show()
    -- An unqualified open resumes an active guided setup before considering the
    -- one-time welcome. Explicit deep links always keep their requested page.
    if pageKey == nil then
        local guided = MSUF and MSUF.GuidedTour6
        if guided and type(guided.IsActive) == "function" and guided:IsActive() then
            local current = type(M.GetGuidedTourCurrentPage) == "function" and M.GetGuidedTourCurrentPage() or nil
            pageKey = current or "guided_setup"
        else
            local firstLoad = MSUF and MSUF.FirstLoad6
            if firstLoad and type(firstLoad.ShouldShowDashboard) == "function" and firstLoad:ShouldShowDashboard() then
                pageKey = "home"
            end
        end
    end
    M.SelectPage(pageKey or M.sessionLastPage or "home")
    RaiseForeverPadCursor()
    return true
end
function M.Toggle(pageKey)
    if M.BlockCombatAction and M.BlockCombatAction() then
        HideSlashMenuAndMinibar(M.frame)
        return false
    end
    local f = BuildWindow()
    if M.minimizedBar and M.minimizedBar.IsShown and M.minimizedBar:IsShown() then
        M.Open(pageKey or M.activeKey)
        return
    end
    if f:IsShown() and (not pageKey or pageKey == M.activeKey) then
        HideSlashMenuAndMinibar(f)
    else
        M.Open(pageKey)
    end
    return true
end

if IS_FOREVER then
    -- LB/RB press the status strip's Back/Forward page buttons, so the pad
    -- walks the same page history as the mouse.
    local function PressHistoryButton(button)
        if button and button:IsVisible() and button:IsEnabled() then button:Click() end
    end
    -- View jumps between the navigation rail and the page; each page keeps the
    -- spot the pad last left in it.
    local pageSpots = {}
    local function RememberPageSpot(navigation)
        local content = M.scrollFrame
        if M.activeKey and content and navigation.IsSelectionIn(content) then
            pageSpots[M.activeKey] = navigation.GetSelection()
        end
    end
    local function JumpNavigationContent()
        local navigation = MSUF.PadNavigation
        local content = M.scrollFrame
        if not (navigation and content) then return end
        if navigation.IsSelectionIn(content) then
            RememberPageSpot(navigation)
            local button = M.navButtons and M.activeKey and M.navButtons[M.activeKey]
            if not (button and navigation.SelectControl(button)) and M.navButtons then
                for _, other in pairs(M.navButtons) do
                    if navigation.SelectControl(other) then return end
                end
            end
        else
            navigation.SelectFirstIn(content, M.activeKey and pageSpots[M.activeKey])
        end
    end
    local padActions = {
        PADLSHOULDER = function() PressHistoryButton(M.pageHistoryBackButton) end,
        PADRSHOULDER = function() PressHistoryButton(M.pageHistoryForwardButton) end,
        PADBACK = JumpNavigationContent,
    }
    -- Y where nothing moves opens the navigation search with the keyboard; LT
    -- held with LB/RB undoes/redoes through the menu's history.
    local padOptions = {
        hints = { "PADLSHOULDER/PADRSHOULDER", "Previous / next page", "PADBACK", "Navigation / content" },
        searchField = function() return M.nav and M.nav.searchBox end,
        undo = function() return M.Undo() == true end,
        redo = function() return M.Redo() == true end,
    }
    -- The window takes the pad again after every page change, so a press that
    -- rebuilt the page keeps a visible selection. B and Start close the menu.
    local function ShowForeverPadNavigation()
        local navigation = MSUF.PadNavigation
        local frame = M.frame
        if not (navigation and frame and frame:IsShown()) then return end
        navigation.Attach(frame, HideSlashMenuAndMinibar, padActions, padOptions)
        navigation.Activate(frame)
    end
    -- The Suite's embedded Skinning pages call this after building a page.
    M.ResumeForeverPadNavigation = ShowForeverPadNavigation
    local SelectPage = M.SelectPage
    function M.SelectPage(...)
        local navigation = MSUF.PadNavigation
        if navigation then RememberPageSpot(navigation) end
        local selected = SelectPage(...)
        ShowForeverPadNavigation()
        return selected
    end
end

-- Explicit load-time exports for the following responsibility modules.
