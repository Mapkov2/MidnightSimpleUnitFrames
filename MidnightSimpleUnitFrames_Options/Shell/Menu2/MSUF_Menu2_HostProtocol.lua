-- Menu2 host API v2: the widget, section and navigation protocol another addon
-- (the MSUF Suite) uses on Menu2's own widgets. Menu2 keeps per-widget state
-- in private fields; these functions are the documented way in, so a renamed
-- field changes here and nowhere else. v1 (page-reset providers,
-- MSUF_Menu2_PageResetProviders.lua) is unchanged.
--
--   M.HOST_API_VERSION = 2
--
--   Controls (any Menu2 widget or plain frame the menu treats as one):
--   M.SkipHistoryCheckpoint(widget) -> widget    clicks take no undo snapshot
--   M.AllowCombatClick(widget) -> widget         stays clickable in combat
--   M.SetSearchTargetPrepare(widget, fn|nil) -> widget
--   M.GetSearchTargetPrepare(widget) -> fn|nil   exact search runs fn before
--                                                it reveals the widget
--   M.SetCommandAction(widget, action) -> widget the command catalog's action
--   M.GetControlTitle(widget) -> fontString|nil  a dropdown/segment title
--   M.GetControlLabel(widget) -> fontString|nil  a button/switch label
--   M.GetControlSearchMeta(widget) -> table|nil  registered search metadata
--   M.GetRawSetText(fontString) -> fn|nil        the untranslated SetText
--   M.ReleaseColorShortcut(shortcut)             later bound swatches may not
--                                                replace the shortcut's list
--
--   Sections (a collapsible body or any frame built like one):
--   M.GetSectionEntry(frame) -> entry|nil        its collapsible header entry
--   M.SetSectionEntry(frame, entry)
--   M.GetSectionWidth(frame) -> number|nil
--   M.SetSectionWidth(frame, width)
--   M.GetSectionCursor(frame) -> y|nil           the auto-height cursor
--   M.SetSectionCursor(frame, y)
--   M.MarkContextColorHost(frame)                the "::: colors" shortcut host
--   M.SetFixedPreviewHeight(frame, height|nil)   a docked preview's height
--   M.SetBuilderInsets(ctx, contentX, topInset) -> ctx
--
--   Section entries (the header record of a collapsible section):
--   M.SetSectionEnsureVisible(entry, fn|nil) / M.GetSectionEnsureVisible(entry)
--   M.SetSectionRefreshState(entry, fn|nil) / M.GetSectionRefreshState(entry)
--   M.SetMissingSectionResolver(entry, fn|nil) / M.GetMissingSectionResolver(entry)
--   M.ReserveSectionActions(entry, button, width[, revealOnInteraction])
--   M.RefreshSectionLayout(entry)                   re-runs the header layout
--   M.SetSectionPopupGetter(button, fn[, popup])    pass popup when first built
--
--   Navigation:
--   M.AddNavIcon(pageKey, { icon = cell, hdIcon = cell|nil, accent = bool })
--       -> added. cell = { column, row } of the navigation atlas; hdIcon is
--       used by the HD atlas (version 2 and newer). The color is the accent
--       (home) or the neutral (gameplay) icon color. A key that already has an
--       icon or a color keeps it.
--
-- Widget accessors below are cold menu code and allocate nothing.
local _, MSUF = ...
local M = MSUF.MSUF2
local T = M.Theme
local rawget, tonumber, type = rawget, tonumber, type
M.HOST_API_VERSION = 2

------------------------------------------------------------------ controls
function M.SkipHistoryCheckpoint(widget)
    widget._msuf2SkipHistoryCheckpoint = true
    return widget
end

function M.AllowCombatClick(widget)
    widget._msuf2AllowCombatClick = true
    return widget
end

function M.SetSearchTargetPrepare(widget, prepare)
    widget._msuf2PrepareExactSearchTarget = prepare
    return widget
end

function M.GetSearchTargetPrepare(widget)
    return widget._msuf2PrepareExactSearchTarget
end

function M.SetCommandAction(widget, action)
    widget._msuf2CommandAction = action
    return widget
end

function M.GetControlTitle(widget)
    return widget._msuf2Title
end

-- Raw: a widget's label is its own field, never a method of its frame type.
function M.GetControlLabel(widget)
    return rawget(widget, "_msuf2Label")
end

function M.GetControlSearchMeta(widget)
    return widget._msuf2SearchMeta
end

function M.GetRawSetText(fontString)
    return fontString._msuf2RawSetText
end

function M.ReleaseColorShortcut(shortcut)
    shortcut._msuf2BoundColorShortcut = nil
end

------------------------------------------------------------------ sections
function M.GetSectionEntry(frame)
    return frame._msuf2CollapsibleEntry
end

function M.SetSectionEntry(frame, entry)
    frame._msuf2CollapsibleEntry = entry
end

function M.GetSectionWidth(frame)
    return frame._msuf2Width
end

function M.SetSectionWidth(frame, width)
    frame._msuf2Width = width
end

function M.GetSectionCursor(frame)
    return frame._msuf2CursorY
end

function M.SetSectionCursor(frame, y)
    frame._msuf2CursorY = y
end

function M.MarkContextColorHost(frame)
    frame._msuf2ContextColorHost = true
end

function M.SetFixedPreviewHeight(frame, height)
    frame._msuf2FixedPreviewActiveHeight = height
end

function M.SetBuilderInsets(ctx, contentX, topInset)
    ctx._msuf2ContentX, ctx._msuf2TopInset = contentX, topInset
    return ctx
end

------------------------------------------------------------------ section entries
function M.SetSectionEnsureVisible(entry, ensure)
    entry._msuf2EnsureVisible = ensure
end

function M.GetSectionEnsureVisible(entry)
    return entry._msuf2EnsureVisible
end

function M.SetSectionRefreshState(entry, refresh)
    entry._msuf2RefreshState = refresh
end

function M.GetSectionRefreshState(entry)
    return entry._msuf2RefreshState
end

function M.SetMissingSectionResolver(entry, resolve)
    entry._msuf2ResolveMissingSection = resolve
end

function M.GetMissingSectionResolver(entry)
    return entry._msuf2ResolveMissingSection
end

-- The header layout (RefreshCollapsibleHeaderLayout) keeps width px right of
-- the feature switch for the button. A header without a summary row places
-- the switch by the color swatch reserve alone, so the button joins that.
function M.ReserveSectionActions(entry, button, width, revealOnInteraction)
    entry._msuf2SectionActions = button
    entry._msuf2ActionReserve = width
    if not entry._msuf2UXSummary then
        entry._msuf2ColorSwatchReserve = (entry._msuf2ColorSwatchReserve or 0) + width
    end
    if revealOnInteraction then M.Widgets.AttachSectionActionVisibility(entry, button) end
end

function M.RefreshSectionLayout(entry)
    local refresh = entry._msuf2RefreshLayout
    if refresh then refresh() end
end

function M.SetSectionPopupGetter(button, getPopup, popup)
    button._msuf2GetSectionPopup = getPopup
    local refresh = button._msuf2RefreshSectionAction
    if popup and refresh then
        popup:HookScript("OnShow", refresh)
        popup:HookScript("OnHide", refresh)
        refresh()
    end
end

------------------------------------------------------------------ navigation
function M.AddNavIcon(pageKey, spec)
    local grid, colors = T.navIconGrid, T.navIconColors
    if type(grid) ~= "table" or type(colors) ~= "table" or type(spec) ~= "table" then return false end
    local neutral = colors.gameplay or colors.profiles
    local accent = colors.home or neutral
    local icon = (tonumber(T.navIconAtlasVersion) or 0) >= 2 and spec.hdIcon or spec.icon
    local added = false
    if icon and grid[pageKey] == nil then
        grid[pageKey] = icon
        added = true
    end
    if colors[pageKey] == nil then
        colors[pageKey] = spec.accent and accent or neutral
        added = true
    end
    return added
end

------------------------------------------------------------------ page extensions
-- Additive host API v2 capability. Page owners opt in by calling
-- BuildPageExtensions(key, ctx, builder) before setting their final height.
-- RegisterPageExtension(key, id, provider) keeps registration order; replacing
-- an id replaces its callbacks, never the host page. No provider means no work.
-- Required: build(ctx, builder). Optional: canReset(key), warning(key),
-- prepare(key), reset(key), finish(key). Prepare/reset return true on success.
-- canReset describes availability, not whether the current values are defaults.
-- Reset steps join the host's single undo entry; finish runs after that entry.
local extensions = {}
local extensionCallbacks = { "build", "canReset", "warning", "prepare", "reset", "finish" }
local RunExtensionStep = MSUF.RunHostAPIStep
local ExtensionPlayerInCombat = MSUF.HostAPIPlayerInCombat

local function SnapshotExtension(key, id, provider)
    if type(key) ~= "string" or key == "" or type(id) ~= "string" or id == "" or type(provider) ~= "table" then
        error("MSUF RegisterPageExtension: expected (pageKey, id, provider)", 3)
    end
    local copy = { id = id }
    for i = 1, #extensionCallbacks do
        local name = extensionCallbacks[i]
        local callback = provider[name]
        if (name == "build" or callback ~= nil) and type(callback) ~= "function" then
            error("MSUF RegisterPageExtension: " .. name .. " must be a function", 3)
        end
        copy[name] = callback
    end
    return copy
end

local function SameExtension(a, b)
    if not a then return false end
    for i = 1, #extensionCallbacks do
        local name = extensionCallbacks[i]
        if a[name] ~= b[name] then return false end
    end
    return true
end

local function RefreshExtendedPage(key)
    local page = M.pages and M.pages[key]
    if page then page.version = (tonumber(page.version) or 0) + 1 end
    if M.SearchBridge then M.SearchBridge.MarkSearchIndexDirty() end
    -- A version change retires all cached layouts on the next selection.
    -- Registration during combat must not touch even a cached preview frame.
    if not ExtensionPlayerInCombat() and M.activeKey == key and M.RebuildPageKeepingScroll then
        M.RebuildPageKeepingScroll(key)
    end
    if M.RefreshToolbarPageReset then M.RefreshToolbarPageReset() end
end

function M.RegisterPageExtension(key, id, provider)
    local record = SnapshotExtension(key, id, provider)
    local page = extensions[key]
    if not page then
        page = { records = {}, slots = {} }
        extensions[key] = page
    end
    local slot = page.slots[id]
    if slot and SameExtension(page.records[slot], record) then return true end
    slot = slot or (#page.records + 1)
    page.records[slot], page.slots[id] = record, slot
    RefreshExtendedPage(key)
    return true
end

function M.HasPageExtension(key, id)
    local page = extensions[key]
    return page ~= nil and (id == nil or page.slots[id] ~= nil)
end

function M.BuildPageExtensions(key, ctx, builder)
    local page = extensions[key]
    if not page then return false end
    for i = 1, #page.records do
        RunExtensionStep("page extension build", page.records[i].build, ctx, builder)
    end
    return true
end

local function ExtensionCanReset(record, key)
    if not record.reset then return false end
    if not record.canReset then return true end
    local ran, allowed = RunExtensionStep("page extension canReset", record.canReset, key)
    return ran and allowed == true
end

function M.AppendPageExtensionResetWarning(key, warning)
    local page = extensions[key]
    if not page then return warning end
    for i = 1, #page.records do
        local record = page.records[i]
        if record.warning and ExtensionCanReset(record, key) then
            local ran, extra = RunExtensionStep("page extension warning", record.warning, key)
            if ran and type(extra) == "string" and extra ~= "" then warning = warning .. "\n\n" .. extra end
        end
    end
    return warning
end

local function PrepareExtensionReset(key)
    local selected = {}
    local records = extensions[key].records
    for i = 1, #records do
        local record = records[i]
        if ExtensionCanReset(record, key) then selected[#selected + 1] = record end
    end
    local prepared = false
    for i = 1, #selected do
        local record = selected[i]
        if record.prepare then
            local ran, result = RunExtensionStep("page extension prepare", record.prepare, key)
            if not ran or result ~= true then return nil end
            prepared = true
        end
    end
    if prepared then M.SyncExternalHistoryState() end
    return selected
end

-- Called by the host reset dispatcher after its normal combat and scope checks.
-- Returning false from a history callback discards its snapshot, so a partially
-- failed reset records every change first and reports failure after committing.
function M.ResetExtendedPage(key, resetHost, label)
    if ExtensionPlayerInCombat() then
        M.ShowConfigCombatLockMessage()
        return false
    end
    local selected = PrepareExtensionReset(key)
    if not selected then return false end
    local succeeded, attempted = true, false
    local result = M.RunWithHistory(label, "page:reset:" .. key, function()
        if resetHost(key) == false then return false end
        attempted = true
        for i = 1, #selected do
            local ran, reset = RunExtensionStep("page extension reset", selected[i].reset, key)
            if not ran or reset ~= true then succeeded = false end
        end
        return true
    end)
    if attempted then
        for i = 1, #selected do
            local finish = selected[i].finish
            if finish then RunExtensionStep("page extension finish", finish, key) end
        end
    end
    return result == true and succeeded
end
