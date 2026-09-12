--- Menu2/MSUF_Menu2_Window_PageNavigation.lua
--- Cold-path page selection support for the options window: nav/title sync,
--- refresher runs, the browser-style page history and the keep-scroll rebuild.
---
--- Split from MSUF_Menu2_Window.lua; it loads before the window shell and only
--- touches shared M state, never window geometry.
local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local C_Timer = M.MenuTimer or _G.C_Timer
local AccessibleNumber = M.AccessibleNumber
local SearchBridge = M.SearchBridge or {}
local UpdateSearchPlaceholder = SearchBridge.UpdateSearchPlaceholder
local CurrentMenuLocaleKey = SearchBridge.CurrentMenuLocaleKey
local ALIASES = M.ALIASES or {}
local function HideAllCachedPages()
    M.ReleasePinnedPreviews("HIDE_ALL_PAGES", nil)
    M.ReleaseGFNativePreviews("HIDE_ALL_PAGES", nil)
    M.SetActivePageHeader(nil)
    for _, entry in pairs(M.cache) do
        if entry.wrapper and entry.wrapper.Hide then entry.wrapper:Hide() end
    end
end
local function SetTitle(key)
    local frame = M.frame
    if not frame then return end
    local spec = M.pages[key]
    local title = (spec and spec.title) or "MSUF"
    if frame._msuf2TitleKey ~= title then
        frame._msuf2TitleKey = title
        frame.title:SetText(M.Tr(title))
    end
    if frame.subtitle and frame._msuf2SubtitleText ~= "" then
        frame._msuf2SubtitleText = ""
        frame.subtitle:SetText("")
    end
    if frame.RefreshStatus then frame:RefreshStatus() end
end
local function UpdateNav(key)
    if not M.navButtons then return end
    local group = M.navGroupForKey and M.navGroupForKey[key]
    if group and M.navHeaderState and M.navHeaderState[group] == false then
        M.navHeaderState[group] = true
        if M.nav and M.nav._msuf2NavReflow then M.nav:_msuf2NavReflow() end
    end
    local activeNavKey = (M.navPrimaryForKey and M.navPrimaryForKey[key]) or key
    local localeKey = CurrentMenuLocaleKey()
    local labelsDirty = M._msuf2NavLocaleKey ~= localeKey
    M._msuf2NavLocaleKey = localeKey
    for pageKey, btn in pairs(M.navButtons) do
        if labelsDirty and btn._msuf2RawLabel and btn.SetText then btn:SetText(M.Tr(btn._msuf2RawLabel)) end
        local active = pageKey == activeNavKey
        if btn.SetActive and btn._msuf2Active ~= active then btn:SetActive(active) end
    end
    M._msuf2NavActiveKey = activeNavKey
    if labelsDirty and M.navHeaders then
        for _, btn in pairs(M.navHeaders) do
            if btn._msuf2RawLabel and btn.SetText then btn:SetText(string.upper(M.Tr(btn._msuf2RawLabel))) end
        end
    end
    if labelsDirty and M.navTitles then
        for _, title in pairs(M.navTitles) do
            if title._msuf2RawLabel and title.SetText then title:SetText(string.upper(M.Tr(title._msuf2RawLabel))) end
        end
    end
    if labelsDirty and M.nav and M.nav.searchBox then UpdateSearchPlaceholder(M.nav.searchBox) end
end
local function RememberPrimaryNavPage(key)
    local primary = M.navPrimaryForKey and M.navPrimaryForKey[key]
    if type(primary) ~= "string" or primary == "" then return end
    M.navLastPageForPrimary = type(M.navLastPageForPrimary) == "table" and M.navLastPageForPrimary or {}
    M.navLastPageForPrimary[primary] = key
end
function M.ResolvePrimaryNavClickTarget(primaryKey)
    primaryKey = tostring(primaryKey or "")
    local last = type(M.navLastPageForPrimary) == "table" and M.navLastPageForPrimary[primaryKey] or nil
    if type(last) == "string"
        and M.pages[last]
        and M.navPrimaryForKey
        and M.navPrimaryForKey[last] == primaryKey
    then
        return last
    end
    return primaryKey
end
local function CurrentMenuDataRevision()
    return tonumber(M._msuf2MenuDataRevision) or 0
end
function M.MarkMenuDataDirty(reason)
    M._msuf2MenuDataRevision = CurrentMenuDataRevision() + 1
    M._msuf2MenuDataDirtyReason = reason
    return M._msuf2MenuDataRevision
end
local function RunRefreshers(entry, opts)
    if not entry or not entry.refreshers then return end
    opts = opts or {}
    local revision = CurrentMenuDataRevision()
    if opts.force ~= true and entry._msuf2RefreshRevision == revision then return false end
    for i = 1, #entry.refreshers do
        local fn = entry.refreshers[i]
        if type(fn) == "function" then fn() end
    end
    entry._msuf2RefreshRevision = revision
    return true
end
local PAGE_HISTORY_LIMIT = 30
local suppressPageHistory
local function NormalizePageKey(key)
    if key == nil then return nil end
    key = ALIASES[key or ""] or key
    key = tostring(key or "")
    if key == "" then return nil end
    return key
end
local function PushPageHistory(stack, key)
    key = NormalizePageKey(key)
    stack = type(stack) == "table" and stack or {}
    -- Search is a transient surface: its result state is torn down on leave,
    -- so landing on it through Back/Forward would show an empty page. It never
    -- enters either stack; Back skips straight to the page before it.
    if not key or key == "search" then return stack end
    if stack[#stack] ~= key then stack[#stack + 1] = key end
    while #stack > PAGE_HISTORY_LIMIT do table.remove(stack, 1) end
    return stack
end
local function EnsurePageHistoryStacks()
    M.pageBackStack = type(M.pageBackStack) == "table" and M.pageBackStack or {}
    M.pageForwardStack = type(M.pageForwardStack) == "table" and M.pageForwardStack or {}
    return M.pageBackStack, M.pageForwardStack
end
local function RecordPageNavigation(fromKey, toKey)
    fromKey = NormalizePageKey(fromKey)
    toKey = NormalizePageKey(toKey)
    if not fromKey or not toKey or fromKey == toKey then return end
    M.pageBackStack = PushPageHistory(M.pageBackStack, fromKey)
    local _, forward = EnsurePageHistoryStacks()
    for key in pairs(forward) do forward[key] = nil end
end
local function OpenHistoryPage(page)
    local open = type(M.Open) == "function" and M.Open or M.SelectPage
    if type(open) ~= "function" then return false end
    suppressPageHistory = true
    local ok = open(page) ~= false
    suppressPageHistory = false
    return ok
end
function M.GetPageHistoryState()
    local back, forward = EnsurePageHistoryStacks()
    return {
        canBack = #back > 0,
        canForward = #forward > 0,
        backCount = #back,
        forwardCount = #forward,
        previousPage = back[#back],
        nextPage = forward[#forward],
    }
end
function M.GoBackPage()
    if M.BlockCombatAction and M.BlockCombatAction() then return false, "Dashboard back navigation is blocked in combat." end
    local back = EnsurePageHistoryStacks()
    local page = table.remove(back)
    if type(page) ~= "string" or page == "" then return false, "Dashboard back navigation has no previous native Menu2 page." end
    local current = M.activeKey
    if OpenHistoryPage(page) then
        M.pageForwardStack = PushPageHistory(M.pageForwardStack, current)
        M.RefreshPageHistoryNav()
        return true, "Opened previous page."
    end
    M.pageBackStack = PushPageHistory(M.pageBackStack, page)
    M.RefreshPageHistoryNav()
    return false, "Dashboard back navigation is not available right now."
end
function M.GoForwardPage()
    if M.BlockCombatAction and M.BlockCombatAction() then return false, "Dashboard forward navigation is blocked in combat." end
    local _, forward = EnsurePageHistoryStacks()
    local page = table.remove(forward)
    if type(page) ~= "string" or page == "" then return false, "Dashboard forward navigation has no next native Menu2 page." end
    local current = M.activeKey
    if OpenHistoryPage(page) then
        M.pageBackStack = PushPageHistory(M.pageBackStack, current)
        M.RefreshPageHistoryNav()
        return true, "Opened next page."
    end
    M.pageForwardStack = PushPageHistory(M.pageForwardStack, page)
    M.RefreshPageHistoryNav()
    return false, "Dashboard forward navigation is not available right now."
end
--- Chrome hook: keeps the status-strip Back/Forward buttons in sync with the
--- page history stacks. Cold path -- runs only on page navigation, and stays a
--- no-op until BuildWindowChrome has created the buttons.
function M.SetPageHistoryTourCue(enabled)
    local back, forward = M.pageHistoryBackButton, M.pageHistoryForwardButton
    if not (back and forward
        and type(back._msuf2SetTourCue) == "function"
        and type(forward._msuf2SetTourCue) == "function")
    then
        return false
    end
    M._pageHistoryTourCuePage = enabled == true and M.activeKey or nil
    local shown = M._pageHistoryTourCuePage ~= nil
    back._msuf2SetTourCue(shown)
    forward._msuf2SetTourCue(shown)
    return shown
end
function M.RefreshPageHistoryNav()
    local back, forward = M.pageHistoryBackButton, M.pageHistoryForwardButton
    if not (back and forward) then return end
    local state = M.GetPageHistoryState()
    if back.SetEnabled then back:SetEnabled(state.canBack == true) end
    if forward.SetEnabled then forward:SetEnabled(state.canForward == true) end
    local cuePage = M._pageHistoryTourCuePage
    local showTourCue = cuePage ~= nil and M.activeKey == cuePage
    if cuePage ~= nil and not showTourCue then M._pageHistoryTourCuePage = nil end
    if type(back._msuf2SetTourCue) == "function" then
        back._msuf2SetTourCue(showTourCue)
    end
    if type(forward._msuf2SetTourCue) == "function" then
        forward._msuf2SetTourCue(showTourCue)
    end
end
local pageScrollRestoreSerial = 0
local function RestorePageScroll(key, offset, serial)
    if M.activeKey ~= key or serial ~= pageScrollRestoreSerial then return end
    local scroll = M.scrollFrame
    if not (scroll and scroll.SetVerticalScroll) then return end
    -- The themed setter already clamps against its accessible cached range.
    -- Avoid GetVerticalScrollRange here: Midnight may return a secret number.
    scroll:SetVerticalScroll(AccessibleNumber(offset, 0))
    M.RefreshPinnedPreviews(scroll)
end
--- Rebuilds a page in place and keeps the reader where they were. Disclosures
--- that only grow or shrink a card need the rebuild for the new heights, but
--- SelectPage's viewport reset then throws the page back to the top.
--- Cards below the toggle settle their height after selection, so the immediate
--- restore covers the common case and the two retries cover the settled layout;
--- the serial drops stale retries once a newer rebuild has started.
--- Returns false only when nothing was rebuilt, so callers keep their fallback.
function M.RebuildPageKeepingScroll(key)
    key = key or M.activeKey
    if not (key and M.frame and M.frame.IsShown and M.frame:IsShown()) then return false end
    local scroll = M.scrollFrame
    local offset = AccessibleNumber(scroll and scroll.GetVerticalScroll and scroll:GetVerticalScroll() or 0, 0)
    pageScrollRestoreSerial = pageScrollRestoreSerial + 1
    local serial = pageScrollRestoreSerial
    M.InvalidatePage(key)
    if M.SelectPage(key) ~= false then
        RestorePageScroll(key, offset, serial)
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() RestorePageScroll(key, offset, serial) end)
            C_Timer.After(0.05, function() RestorePageScroll(key, offset, serial) end)
        end
    end
    return true
end
--- SelectPage records the transition unless Back/Forward is driving it; the
--- suppression flag stays private to this module.
function M.RecordPageNavigation(fromKey, toKey)
    if suppressPageHistory then return end
    return RecordPageNavigation(fromKey, toKey)
end
M.AssignNamedValues(M, [[
    HideAllCachedPages SetTitle UpdateNav RememberPrimaryNavPage RunEntryRefreshers
]], HideAllCachedPages, SetTitle, UpdateNav, RememberPrimaryNavPage, RunRefreshers)
