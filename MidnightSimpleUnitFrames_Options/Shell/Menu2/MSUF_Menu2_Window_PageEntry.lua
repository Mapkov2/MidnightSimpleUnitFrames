--- Menu2/MSUF_Menu2_Window_PageEntry.lua
--- Cold-path page entry construction support: the page context object, the
--- secondary tab/rail navigation, the placeholder page and the normal/maximized
--- layout-variant cache (window slot plus the page's declared view state) used
--- while a page is built.
---
--- Split from MSUF_Menu2_Window.lua; it loads before the window shell and reads
--- the live content metrics through M.GetContentMetrics at call time.
local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Shell/Menu2/MSUF_Menu2_Window_PageEntry.lua")
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
    entry.context = ctx
    function ctx:SetContentHeight(height)
        entry.contentHeight = tonumber(height)
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
    function ctx:AddResizeCallback(fn)
        entry.resizeCallbacks = entry.resizeCallbacks or {}
        entry.resizeCallbacks[#entry.resizeCallbacks + 1] = fn
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
local function SecondaryNavButton(parent, label, width, value)
    local c = T.colors
    local style = { bg = c.pillBase, border = c.pillEdge, textColor = c.pillText,
        hoverBg = c.pillHover, hoverBorder = c.pillEdgeHover, activeBg = c.pillActive,
        activeBorder = c.pillEdgeActive, activeTextColor = c.pillTextActive }
    local button = W.TopButton(parent, M.Tr(label), width, 24, style)
    button._msuf2Value = value
    return button
end
local function SecondaryNavClick(button)
    W.BeginSelectionMotion(button, button._msuf2Value)
    M.SelectPage(button._msuf2Value)
end
local function FinishSecondaryMotion(owner, buttons, key, vertical)
    owner.buttons = buttons
    W.AttachSelectionMotion(owner, buttons, vertical, "secondary-navigation")
    for i = 1, #buttons do buttons[i]:SetActive(buttons[i]._msuf2Value == key) end
end
local function AddSecondaryNavButton(owner, buttons, tab, width, y, x)
    local btn = SecondaryNavButton(owner, tab.label, width, tab.key)
    btn._msuf2SkipHistoryCheckpoint = true
    btn:SetPoint("TOPLEFT", owner, "TOPLEFT", x, y)
    btn:SetScript("OnClick", SecondaryNavClick)
    buttons[#buttons + 1] = btn
    if M.RegisterMenuChromeControl then
        M.RegisterMenuChromeControl(btn, "secondary-navigation." .. tostring(tab.key), tab.label, "navigation",
            { navigationKey = tab.key })
    end
end
local function BuildSecondaryTabs(ctx, key, group)
    if not (ctx and ctx.wrapper and group and group.tabs) then return end
    ctx._msuf2TopInset = 44
    local bar = PixelLayoutRegion(CreateFrame("Frame", nil, ctx.wrapper))
    bar:SetPoint("TOPLEFT", ctx.wrapper, "TOPLEFT", 12, -12)
    bar:SetSize(ctx.width or 720, 36)
    local x, buttons = SECONDARY_NAV_TAB_PAD_X, {}
    for i = 1, #group.tabs do
        local tab = group.tabs[i]
        local w = tonumber(tab.width) or 72
        AddSecondaryNavButton(bar, buttons, tab, w, -SECONDARY_NAV_TAB_PAD_Y, x)
        x = x + w + 8
    end
    FinishSecondaryMotion(bar, buttons, key, false)
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
    local title = T.Font(rail, "GameFontNormalSmall", group.title or "", T.colors.accent)
    title:SetPoint("TOPLEFT", rail, "TOPLEFT", 12, -12)
    title:SetPoint("TOPRIGHT", rail, "TOPRIGHT", -12, -12)
    title:SetJustifyH("LEFT")
    local y, buttons = -40, {}
    for i = 1, #group.tabs do
        AddSecondaryNavButton(rail, buttons, group.tabs[i], SECONDARY_NAV_RAIL_W - 24, y, 12)
        y = y - 32
    end
    FinishSecondaryMotion(rail, buttons, key, true)
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
-- A page whose spec declares variantKey(key) caches one entry per view state
-- (the Dashboard's open disclosures, for example) next to the window slot, so
-- switching back to a view it already built shows that entry again instead of
-- building a new frame tree. The composite slot strings are memoized: a page
-- selection allocates nothing for them.
local VARIANT_SLOTS = { normal = {}, maximized = {} }
-- Only discrete changes in page structure need another tree. Size commits
-- within a structure reflow its existing native frames instead of retiring them.
local function ResponsiveLayoutClass(key)
    local width = M.GetContentMetrics()
    if key == "home" then
        local cardWidth = width - 44
        return (width < 744 and "intro-small" or "intro-large")
            .. (cardWidth < 520 and "/plain" or "/pill")
            .. (cardWidth < 590 and "/wrapped" or "/row")
            .. (cardWidth < 680 and "/one" or cardWidth < 960 and "/two" or "/three")
    elseif key == "classpower" then
        return width < 712 and "compact" or "columns"
    elseif key == "gameplay" then
        return width < 652 and "compact" or "columns"
    elseif key == "swingtimers" then
        return width < 692 and "compact" or "columns"
    elseif key == "gf_bars" or key:match("^uf_") then
        return width < 832 and "compact" or "columns"
    end
    return "fixed"
end
local function CurrentPageLayoutSlot(key)
    local slot = M.frame and M.frame._msuf2WindowState == "maximized" and "maximized" or "normal"
    slot = slot .. ":" .. ResponsiveLayoutClass(key or "")
    if not VARIANT_SLOTS[slot] then VARIANT_SLOTS[slot] = {} end
    local spec = key and M.pages and M.pages[key]
    local variantKey = spec and spec.variantKey
    if not variantKey then return slot end
    local variant = variantKey(key)
    if variant == nil or variant == "" then return slot end
    local bySlot = VARIANT_SLOTS[slot]
    local composite = bySlot[variant]
    if not composite then
        composite = slot .. "|" .. tostring(variant)
        bySlot[variant] = composite
    end
    return composite
end
-- Native anchors resize the decoration, headers and preview hosts. Explicit
-- full-width surfaces/text follow the same gutter; compact controls keep their
-- requested width and are clamped again by MoveWidget below. This runs only
-- at a committed selection/resize, never on the window animation's ticks.
local ResizePageSurface
local function ResizeGridItem(parent, item, oldWidth, width, grid)
    local kind = item:GetObjectType()
    if kind == "Texture" then return end
    local point, relative, relativePoint, x, y = item:GetPoint()
    if relative ~= parent or point ~= relativePoint or (point ~= "TOPLEFT" and point ~= "LEFT") then return end
    local basis = grid.owner and grid.owner.width or width
    local previous = grid.basis or oldWidth
    local inset = grid.inset or 32
    local oldColumn = math.floor((previous - inset - grid.gap * (grid.count - 1)) / grid.count)
    local column = math.floor((basis - inset - grid.gap * (grid.count - 1)) / grid.count)
    local index = math.max(0, math.min(grid.count - 1,
        math.floor((x - (grid.left or 16)) / (oldColumn + grid.gap) + 0.2)))
    local itemWidth = item._msuf2RequestedWidth or item._msuf2RowWidth or item:GetWidth()
    if itemWidth >= oldWidth - 64 then return end
    local newX = x + index * (column - oldColumn)
    item:ClearAllPoints()
    item:SetPoint(point, parent, relativePoint, newX, y)
    if item._msuf2ContextLayoutParent == parent then item._msuf2ContextLayoutX = newX end
    if itemWidth >= oldColumn - 64 then
        local newWidth = math.max(1, itemWidth + column - oldColumn)
        if kind == "FontString" then
            item:SetWidth(newWidth)
        else
            item._msuf2RequestedWidth = newWidth
            if item._msuf2SetLayoutWidth then
                item:_msuf2SetLayoutWidth(newWidth)
                if item._msuf2HideValueBox then
                    if item.editBox then item.editBox:Hide() end
                    for _, button in ipairs(item._msuf2StepButtons or {}) do button:Hide() end
                end
            elseif item._msuf2ControlKind == "toggle" then
                if item._msuf2Label then item._msuf2Label:SetWidth(newWidth) end
            else
                ResizePageSurface(item, newWidth)
            end
        end
    end
end
ResizePageSurface = function(frame, width)
    local oldWidth = frame:GetWidth()
    local delta = width - oldWidth
    local ownGrid = frame._msuf2ResizeGrid
    if delta == 0 and not (ownGrid and ownGrid.owner and ownGrid.basis ~= ownGrid.owner.width) then return end
    local children = { frame:GetChildren() }
    local grid = frame._msuf2ResizeGrid
    if grid then
        for i = 1, #children do ResizeGridItem(frame, children[i], oldWidth, width, grid) end
    end
    for i = 1, #children do
        local child = children[i]
        local childWidth = child:GetWidth()
        local accordion = child._msuf2CollapsibleEntry
        local column = child._msuf2ResizeColumn
        if accordion and accordion.body == child then
            ResizePageSurface(child, math.min(width, M.formContentMaxWidth or 980))
        elseif column then
            local columnWidth = math.max(column.min or 1,
                math.floor((width - column.left - column.right - column.gap * (column.count - 1)) / column.count))
            ResizePageSurface(child, columnWidth)
            child:ClearAllPoints()
            child:SetPoint("TOPLEFT", frame, "TOPLEFT", column.left + (column.index - 1) * (columnWidth + column.gap), column.y)
            child._msuf2ContextColorLeft = column.left + (column.index - 1) * (columnWidth + column.gap)
            child._msuf2ContextColorWidth = columnWidth
        elseif childWidth >= oldWidth - 64 then
            ResizePageSurface(child, math.max(1, childWidth + delta))
        end
    end
    local regions = { frame:GetRegions() }
    if grid then
        for i = 1, #regions do ResizeGridItem(frame, regions[i], oldWidth, width, grid) end
    end
    for i = 1, #regions do
        local region = regions[i]
        if region:GetObjectType() == "FontString" and region:GetWidth() >= oldWidth - 64 then
            region:SetWidth(math.max(1, region:GetWidth() + delta))
        end
    end
    if grid then grid.basis = grid.owner and grid.owner.width or width end
    if frame._msuf2Width then frame._msuf2Width = width end
    frame:SetWidth(width)
end
local function ResizePageControl(widget)
    local parent = widget._msuf2ContextLayoutParent
    if parent then
        W.MoveWidget(widget, parent, widget._msuf2ContextLayoutX, widget._msuf2ContextLayoutY,
            widget._msuf2RequestedWidth)
        if widget._msuf2HideValueBox then
            if widget.editBox then widget.editBox:Hide() end
            for _, button in ipairs(widget._msuf2StepButtons or {}) do button:Hide() end
        end
    end
end
local function ResizePageEntry(entry, width, height)
    local ctx = entry.context
    if not ctx then return end
    -- Lazy sub-builders may have appeared since this area was selected.
    for _, area in pairs(entry.pageAreas or {}) do
        for i = #ctx._msuf2PageBuilders, 1, -1 do
            if ctx._msuf2PageBuilders[i].ctx._msuf2PageArea == area then table.remove(ctx._msuf2PageBuilders, i) end
        end
        for _, builder in ipairs(area.active.ctx._msuf2PageBuilders) do
            ctx._msuf2PageBuilders[#ctx._msuf2PageBuilders + 1] = builder
        end
    end
    local builders = ctx._msuf2PageBuilders or {}
    for i = 1, #builders do
        local builder = builders[i]
        builder._msuf2ResizeWidthOffset = builder.parent:GetWidth() - builder.width
    end
    ctx.width, ctx.fullWidth = width - 32, width - 32
    if ctx.resizeWidthOwner then ctx.resizeWidthOwner.width = ctx.width end
    ResizePageSurface(entry.wrapper, width - 12)
    for i = #builders, 1, -1 do
        local builder = builders[i]
        builder.width = math.max(1, builder.parent:GetWidth() - builder._msuf2ResizeWidthOffset)
        if builder.ctx ~= ctx then builder.ctx.width = builder.width end
        builder._msuf2LastContentHeight = nil
        builder:RelayoutCollapsibles()
    end
    for i = 1, #(entry.searchWidgets or {}) do
        ResizePageControl(entry.searchWidgets[i])
    end
    for i = 1, #(entry.resizeCallbacks or {}) do entry.resizeCallbacks[i]() end
    entry.layoutWidth, entry.layoutHeight = width, height
    ApplyContextContentHeight(entry, entry.wrapper, entry.contentHeight or entry.height)
end
local function PageStorageSlot(key, slot)
    if key:match("^uf_") then return slot:match("^[^|]+") end
    return slot
end
local function PageEntryMatchesLayout(entry, slot)
    if type(entry) ~= "table" then return false end
    if PageStorageSlot(entry.key, entry.layoutSlot) ~= PageStorageSlot(entry.key, slot) then return false end
    local width, height = M.GetContentMetrics()
    if entry.layoutWidth ~= width or entry.layoutHeight ~= height then ResizePageEntry(entry, width, height) end
    return true
end
local function RehydratePageAccordion(entry)
    for _, section in pairs(entry.sections or {}) do
        local collapsible = section._msuf2CollapsibleEntry
        if collapsible then
            local saved = M.accordionState[collapsible.stateKey]
            local wanted = saved == nil and collapsible.defaultOpen or saved == true
            collapsible._msuf2AutoOpened = nil
            if collapsible.open ~= wanted then collapsible.SetOpenImmediate(wanted) end
        end
    end
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
        if widget and type(meta) == "table" then
            M.RuntimeControlCatalog.RestoreWidget(widget)
            M.RegisterSearchWidget(widget, meta)
        end
    end
end
local PAGE_AREA_RELAYOUT = { skipStateRefresh = true }
-- Unit selection axes own independent subtrees: at most 34 aura views and
-- three texture slots per structural layout. Never retain their cross product.
local function BelongsToArea(frame, host)
    while frame do
        if frame == host then return true end
        frame = frame:GetParent()
    end
    return false
end
local function ParkPageArea(area)
    local view, entry = area.active, area.ctx.entry
    if not view then return end
    view.host:Hide()
    for _, builder in ipairs(view.ctx._msuf2PageBuilders) do
        builder._msuf2ResizeWidthOffset = builder.parent:GetWidth() - builder.width
    end
    view.searchWidgets, view.sections, view.guidedRegions = {}, {}, {}
    for id, region in pairs(entry.guidedRegions or {}) do
        if BelongsToArea(region.body or region.outer, view.host) then
            view.guidedRegions[id], entry.guidedRegions[id] = region, nil
        end
    end
    for i = #entry.searchWidgets, 1, -1 do
        local widget = entry.searchWidgets[i]
        if BelongsToArea(widget, view.host) then
            table.insert(view.searchWidgets, 1, widget)
            table.remove(entry.searchWidgets, i)
        end
    end
    for id, body in pairs(entry.sections or {}) do
        if BelongsToArea(body, view.host) then
            view.sections[id], entry.sections[id] = body, nil
        end
    end
    local builders = area.ctx._msuf2PageBuilders
    for i = #builders, 1, -1 do
        if builders[i].ctx._msuf2PageArea == area then table.remove(builders, i) end
    end
end
local function SettlePageArea(area, view)
    local builders = view.ctx._msuf2PageBuilders
    for i = #builders, 1, -1 do
        local builder = builders[i]
        local offset = builder._msuf2ResizeWidthOffset
        if offset then builder.width = builder.parent:GetWidth() - offset end
        builder.ctx.width = builder.width
        builder:RelayoutCollapsibles(PAGE_AREA_RELAYOUT)
    end
    for i = 1, #builders do
        local builder = builders[i]
        builder._msuf2ResizeWidthOffset = builder.parent:GetWidth() - builder.width
        area.ctx._msuf2PageBuilders[#area.ctx._msuf2PageBuilders + 1] = builder
    end
end
local function PageAreaGuideLess(a, b)
    return a._msuf2PageAreaGuideOrder < b._msuf2PageAreaGuideOrder
end
local function RefreshPageAreaGuides(area)
    local entry, host, guides = area.ctx.entry, area.active.host, {}
    for _, body in pairs(entry.sections or {}) do
        if BelongsToArea(body, host) then guides[#guides + 1] = body._msuf2CollapsibleEntry end
    end
    for _, region in pairs(entry.guidedRegions or {}) do
        if BelongsToArea(region.body or region.outer, host) then guides[#guides + 1] = region end
    end
    for i = 1, #guides do
        local guide = guides[i]
        guide._msuf2PageAreaGuideOrder = guide._msuf2PageAreaGuideOrder or guide.guidedOrder
    end
    table.sort(guides, PageAreaGuideLess)
    -- Keep every subview between the shared steps surrounding its area.
    -- The registration counter remains integral, so generated region IDs stay unique.
    for i = 1, #guides do guides[i].guidedOrder = area.guidedBase + i / (#guides + 1) end
    entry._msuf2GuidedSortedSections = nil
end
local function SelectPageArea(area)
    local selected = area.select(area.unit)
    if area.selected == selected then return false end
    ParkPageArea(area)
    local entry, view = area.ctx.entry, area.views[selected]
    if not view then
        -- select is normalized by the owning control; these fixed counts bound
        -- retained native trees without eviction (WoW never frees frames).
        assert(area.count < area.limit, "page area exceeded its finite view budget")
        area.count = area.count + 1
        local host = PixelLayoutRegion(CreateFrame("Frame", nil, area.anchor))
        host:SetPoint("TOPLEFT", area.anchor, "TOPLEFT", 0, 0)
        host:SetSize(area.builder.width, 1)
        view = { host = host, searchWidgets = {}, sections = {}, guidedRegions = {}, resizeCallbacks = {} }
        area.views[selected] = view
        local ctx = setmetatable({
            wrapper = host, refreshers = {}, _msuf2RefresherKeys = {}, _msuf2RefresherFns = {},
            _msuf2PageBuilders = {}, _msuf2PageArea = area, _msuf2Building = true,
        }, { __index = area.ctx })
        view.ctx = ctx
        function ctx:AddResizeCallback(fn)
            view.resizeCallbacks[#view.resizeCallbacks + 1] = fn
        end
        local builder
        builder = W.PageBuilder(ctx, { parent = host, width = area.builder.width, contentX = 0,
            onContentHeight = function(height)
                local size = math.max(1, height - 42)
                host:SetHeight(size)
                if area.active == view then
                    area.anchor:SetHeight(size)
                    if not ctx._msuf2Building then area.builder:RequestRelayoutCollapsibles() end
                end
            end,
        })
        builder.y = 0
        area.active, area.selected = view, selected
        local incomplete = entry._msuf2BuildIncomplete
        entry._msuf2BuildIncomplete = true
        area.build(ctx, builder, area.unit)
        if entry._msuf2SectionUXOptions then M.UnitSectionsShared.AttachSectionUX(ctx, entry._msuf2SectionUXOptions) end
        ctx._msuf2Building = nil
        entry._msuf2BuildIncomplete = incomplete
        SettlePageArea(area, view)
    else
        area.active, area.selected = view, selected
        for i = 1, #view.searchWidgets do entry.searchWidgets[#entry.searchWidgets + 1] = view.searchWidgets[i] end
        for id, body in pairs(view.sections) do entry.sections[id] = body end
        for id, region in pairs(view.guidedRegions) do entry.guidedRegions[id] = region end
        SettlePageArea(area, view)
        for i = 1, #view.resizeCallbacks do view.resizeCallbacks[i]() end
        for i = 1, #view.searchWidgets do ResizePageControl(view.searchWidgets[i]) end
    end
    RefreshPageAreaGuides(area)
    area.anchor:SetHeight(view.host:GetHeight())
    view.host:Show()
    return true
end
function M.BuildPageArea(ctx, builder, id, unit, select, limit, build)
    local anchor = PixelLayoutRegion(CreateFrame("Frame", nil, builder.parent))
    anchor:SetSize(builder.width, 1)
    anchor:SetPoint("TOPLEFT", builder.parent, "TOPLEFT", builder.x, builder.y)
    local area = { ctx = ctx, builder = builder, anchor = anchor, unit = unit,
        select = select, limit = limit, build = build, views = {}, count = 0,
        guidedBase = tonumber(ctx.entry._msuf2GuidedTourOrder) or 0 }
    ctx.entry.pageAreas = ctx.entry.pageAreas or {}
    ctx.entry.pageAreas[id] = area
    ctx:AddResizeCallback(function()
        local callbacks = area.active.resizeCallbacks
        for i = 1, #callbacks do callbacks[i]() end
    end)
    if not builder._collapsibleStartY then builder._collapsibleStartY = builder.y end
    builder.layoutEntries[#builder.layoutEntries + 1] = { kind = "section", frame = anchor, gap = 0 }
    SelectPageArea(area)
    builder.y = builder.y - anchor:GetHeight()
    M.AddRefresher(ctx, function()
        local refreshers = area.active.ctx.refreshers
        for i = 1, #refreshers do refreshers[i]() end
        RefreshPageAreaGuides(area)
    end)
end
function M.RefreshPageAreas(entry)
    local changed = false
    for _, area in pairs(entry.pageAreas or {}) do
        if SelectPageArea(area) then changed = true end
    end
    if not changed then return false end
    M.SearchBridge.ClearSearchRegistryPage(entry.key)
    RestorePageEntryRegistrations(entry)
    RehydratePageAccordion(entry)
    for _, area in pairs(entry.pageAreas) do
        area.builder:RelayoutCollapsibles()
        RefreshPageAreaGuides(area)
    end
    entry._msuf2RefreshRevision = nil
    return true
end
local function RememberPageLayoutVariant(key, entry)
    if type(entry) ~= "table" then return end
    local variants = M._msuf2PageLayoutVariants[key]
    if type(variants) ~= "table" then
        variants = {}
        M._msuf2PageLayoutVariants[key] = variants
    end
    local storageSlot = PageStorageSlot(key, entry.layoutSlot)
    local previous = variants[storageSlot]
    if previous and previous ~= entry and previous.wrapper then
        previous._msuf2Invalidated = true
        M.DisposePageHeader(previous)
        previous.wrapper:Hide()
        previous.wrapper:SetParent(nil)
    end
    variants[storageSlot] = entry
end
M.Assign(M, {
    SetFrameHeightIfChanged = SetFrameHeightIfChanged, CreateContext = CreateContext,
    ResizePageSurface = ResizePageSurface,
    BuildSecondaryPageNav = BuildSecondaryPageNav, BuildPlaceholderPage = BuildPlaceholderPage,
    PageStorageSlot = PageStorageSlot,
    CurrentPageLayoutSlot = CurrentPageLayoutSlot, PageEntryMatchesLayout = PageEntryMatchesLayout,
    RehydratePageAccordion = RehydratePageAccordion,
    RestorePageEntryRegistrations = RestorePageEntryRegistrations, RememberPageLayoutVariant = RememberPageLayoutVariant,
})

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
