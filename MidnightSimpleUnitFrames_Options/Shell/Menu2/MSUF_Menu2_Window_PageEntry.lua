--- Menu2/MSUF_Menu2_Window_PageEntry.lua
--- Cold-path page entry construction support: the page context object, the
--- secondary tab/rail navigation, the placeholder page and the normal/maximized
--- layout-variant cache used while a page is built.
---
--- Split from MSUF_Menu2_Window.lua; it loads before the window shell and reads
--- the live content metrics through M.GetContentMetrics at call time.
local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local T = M.Theme
local W = M.Widgets
local function SetFrameHeightIfChanged(frame, height)
    if not (frame and frame.SetHeight) then return end
    local _, CONTENT_H = M.GetContentMetrics()
    height = tonumber(height) or CONTENT_H
    if frame._msuf2LastMenuHeight == height then return end
    frame:SetHeight(height)
    frame._msuf2LastMenuHeight = height
end
local function ApplyContextContentHeight(entry, wrapper, height)
    if type(entry) ~= "table" then return end
    local _, CONTENT_H = M.GetContentMetrics()
    height = math.max(CONTENT_H, tonumber(height) or CONTENT_H)
    entry.height = height
    SetFrameHeightIfChanged(wrapper, height)
    if not entry.hiddenBuild and M.scrollChild then
        SetFrameHeightIfChanged(M.scrollChild, height)
        if M.scrollFrame then
            M.scrollFrame._msuf2MaxScroll = nil
            M.scrollFrame._msuf2SmoothScrollTarget = nil
            if M.scrollFrame._msuf2RefreshScrollBar then M.scrollFrame:_msuf2RefreshScrollBar() end
        end
    end
end
local function CreateContext(key, wrapper, entry)
    wrapper._msuf2PageEntry = entry
    local CONTENT_W = M.GetContentMetrics()
    local ctx = {
        key = key,
        wrapper = wrapper,
        entry = entry,
        refreshers = entry.refreshers,
        width = CONTENT_W - 32,
        fullWidth = CONTENT_W - 32,
        hiddenBuild = entry.hiddenBuild == true,
    }
    function ctx:SetContentHeight(height)
        local _, CONTENT_H = M.GetContentMetrics()
        height = math.max(CONTENT_H, tonumber(height) or CONTENT_H)
        if ctx._msuf2DeferContentHeight then
            entry.height = height
            entry._msuf2PendingContentHeight = height
            return
        end
        ApplyContextContentHeight(entry, wrapper, height)
    end
    function ctx:AddRefresher(fn)
        M.AddRefresher(ctx, fn)
    end
    return ctx
end
--- Secondary page navigation (a tab strip, or a side rail on wide windows) is
--- wired up but parked: this table is the only source of groups and it is
--- empty, so BuildSecondaryPageNav below returns immediately for every page and
--- the builders under it never run. Populating this table is all that is needed
--- to bring the feature back; leave the builders in place until that decision
--- is made either way.
local SECONDARY_NAV_GROUPS = {
}
local SECONDARY_NAV_BY_KEY = {}
for _, group in pairs(SECONDARY_NAV_GROUPS) do
    for i = 1, #(group.tabs or {}) do
        local tab = group.tabs[i]
        if tab and tab.key then SECONDARY_NAV_BY_KEY[tab.key] = group end
    end
end
local SECONDARY_NAV_RAIL_W = 132
local SECONDARY_NAV_GAP = 12
local SECONDARY_NAV_MIN_RAIL_WIDTH = 680
local SECONDARY_NAV_TAB_PAD_X = 16
local SECONDARY_NAV_TAB_PAD_Y = 4
local function SecondaryNavButton(parent, label, width, active)
    local style = {
        bg = { 0.022, 0.032, 0.064, 0.94 },
        border = { 0.090, 0.135, 0.250, 0.58 },
        textColor = { 0.78, 0.87, 0.98, 1 },
        hoverBg = { 0.032, 0.046, 0.086, 0.96 },
        hoverBorder = { 0.120, 0.215, 0.405, 0.72 },
        activeBg = { 0.040, 0.100, 0.240, 0.98 },
        activeBorder = { 0.200, 0.430, 0.850, 0.94 },
        activeTextColor = { 0.94, 0.98, 1.00, 1 },
    }
    return W.TopButton(parent, M.Tr(label), width, 24, style, active)
end
local function BuildSecondaryTabs(ctx, key, group)
    if not (ctx and ctx.wrapper and group and group.tabs) then return end
    ctx._msuf2TopInset = 44
    local bar = CreateFrame("Frame", nil, ctx.wrapper)
    bar:SetPoint("TOPLEFT", ctx.wrapper, "TOPLEFT", 12, -12)
    bar:SetSize(ctx.width or 720, 36)
    local x = SECONDARY_NAV_TAB_PAD_X
    for i = 1, #group.tabs do
        local tab = group.tabs[i]
        local w = tonumber(tab.width) or 72
        local btn = SecondaryNavButton(bar, tab.label, w, key == tab.key)
        btn._msuf2SkipHistoryCheckpoint = true
        btn:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -SECONDARY_NAV_TAB_PAD_Y)
        btn:SetScript("OnClick", function() M.SelectPage(tab.key) end)
        if M.RegisterMenuChromeControl then
            M.RegisterMenuChromeControl(btn, "secondary-navigation." .. tostring(tab.key), tab.label, "navigation",
                { navigationKey = tab.key })
        end
        x = x + w + 8
    end
    ctx._msuf2SecondaryNav = bar
end
local function BuildSecondaryRail(ctx, key, group)
    if not (ctx and ctx.wrapper and group and group.tabs) then return end
    local fullW = tonumber(ctx.fullWidth or ctx.width) or 720
    if fullW < SECONDARY_NAV_MIN_RAIL_WIDTH then
        BuildSecondaryTabs(ctx, key, group)
        return
    end
    local _, CONTENT_H = M.GetContentMetrics()
    ctx._msuf2ContentX = 12 + SECONDARY_NAV_RAIL_W + SECONDARY_NAV_GAP
    ctx.width = math.max(360, fullW - SECONDARY_NAV_RAIL_W - SECONDARY_NAV_GAP)
    local rail = T.Panel(ctx.wrapper, nil, T.colors.panel2, T.colors.borderSoft or T.colors.border)
    T.ApplySurface(rail, "rail")
    rail:SetPoint("TOPLEFT", ctx.wrapper, "TOPLEFT", 12, -12)
    rail:SetSize(SECONDARY_NAV_RAIL_W, math.max(260, math.min(CONTENT_H - 24, 520)))
    local title = T.Font(rail, "GameFontNormalSmall", M.Tr(group.title or ""), T.colors.accent)
    title:SetPoint("TOPLEFT", rail, "TOPLEFT", 12, -12)
    title:SetPoint("TOPRIGHT", rail, "TOPRIGHT", -12, -12)
    title:SetJustifyH("LEFT")
    local y = -40
    for i = 1, #group.tabs do
        local tab = group.tabs[i]
        local btn = SecondaryNavButton(rail, tab.label, SECONDARY_NAV_RAIL_W - 24, key == tab.key)
        btn._msuf2SkipHistoryCheckpoint = true
        btn:SetPoint("TOPLEFT", rail, "TOPLEFT", 12, y)
        btn:SetScript("OnClick", function() M.SelectPage(tab.key) end)
        if M.RegisterMenuChromeControl then
            M.RegisterMenuChromeControl(btn, "secondary-navigation." .. tostring(tab.key), tab.label, "navigation",
                { navigationKey = tab.key })
        end
        y = y - 32
    end
    ctx._msuf2SecondaryNav = rail
end
local function BuildSecondaryPageNav(ctx, key)
    local group = SECONDARY_NAV_BY_KEY[key]
    if not group then return end
    if group.mode == "rail" then
        BuildSecondaryRail(ctx, key, group)
    else
        BuildSecondaryTabs(ctx, key, group)
    end
end
local function BuildPlaceholderPage(ctx, requestedKey)
    local b = W.PageBuilder(ctx)
    local sec = b:Section("Native page missing", 130)
    W.Text(sec, "This native page is not implemented yet.", 16, -40, ctx.width - 32, T.colors.muted)
    W.Text(sec, M.Format("Requested page: %s", tostring(requestedKey or "unknown")), 16, -68, ctx.width - 32, T.colors.dim)
    ctx:SetContentHeight(210)
end
local function CurrentPageLayoutSlot()
    return M.frame and M.frame._msuf2WindowState == "maximized" and "maximized" or "normal"
end
local function PageEntryMatchesLayout(entry, slot)
    local CONTENT_W, CONTENT_H = M.GetContentMetrics()
    return type(entry) == "table"
        and entry.layoutSlot == slot
        and entry.layoutWidth == CONTENT_W
        and entry.layoutHeight == CONTENT_H
end
local function RestorePageEntryRegistrations(entry)
    if type(entry) ~= "table" or type(entry.searchWidgets) ~= "table"
        or type(M.RegisterSearchWidget) ~= "function"
    then
        return
    end
    for i = 1, #entry.searchWidgets do
        local widget = entry.searchWidgets[i]
        local meta = widget and widget._msuf2SearchMeta
        if widget and type(meta) == "table" then M.RegisterSearchWidget(widget, meta) end
    end
end
local function RememberPageLayoutVariant(key, entry)
    if type(entry) ~= "table" then return end
    local variants = M._msuf2PageLayoutVariants[key]
    if type(variants) ~= "table" then
        variants = {}
        M._msuf2PageLayoutVariants[key] = variants
    end
    local previous = variants[entry.layoutSlot]
    if previous and previous ~= entry and previous.wrapper then
        previous._msuf2Invalidated = true
        M.DisposePageHeader(previous)
        previous.wrapper:Hide()
        previous.wrapper:SetParent(nil)
    end
    variants[entry.layoutSlot] = entry
end
M.AssignNamedValues(M, [[
    SetFrameHeightIfChanged CreateContext BuildSecondaryPageNav BuildPlaceholderPage
    CurrentPageLayoutSlot PageEntryMatchesLayout RestorePageEntryRegistrations RememberPageLayoutVariant
]], SetFrameHeightIfChanged, CreateContext, BuildSecondaryPageNav, BuildPlaceholderPage,
    CurrentPageLayoutSlot, PageEntryMatchesLayout, RestorePageEntryRegistrations, RememberPageLayoutVariant)

function M.DisposePageHeader(entry)
    local records = type(entry) == "table" and entry.pageHeaders or nil
    if type(records) ~= "table" or #records == 0 then return end
    local active = M.scrollFrame and M.scrollFrame._msuf2StickyPageHeaders
    if type(active) == "table" then
        for i = 1, #active do
            if active[i] and active[i].entry == entry then
                M.SetActivePageHeader(nil)
                break
            end
        end
    end
    for i = #records, 1, -1 do
        local record = records[i]
        if record and record.Dispose then record:Dispose() end
    end
end
