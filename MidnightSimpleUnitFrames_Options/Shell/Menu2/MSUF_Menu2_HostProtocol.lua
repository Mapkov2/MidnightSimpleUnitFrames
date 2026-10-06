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
--   M.ReserveSectionActions(entry, button, width)   a header "..." button
--   M.RefreshSectionLayout(entry)                   re-runs the header layout
--   M.SetSectionPopupGetter(button, fn)             the "..." popup, once built
--
--   Navigation:
--   M.AddNavIcon(pageKey, { icon = cell, hdIcon = cell|nil, accent = bool })
--       -> added. cell = { column, row } of the navigation atlas; hdIcon is
--       used by the HD atlas (version 2 and newer). The color is the accent
--       (home) or the neutral (gameplay) icon color. A key that already has an
--       icon or a color keeps it.
--
-- Every function is cold menu code: one field access, nothing allocated.
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
function M.ReserveSectionActions(entry, button, width)
    entry._msuf2SectionActions = button
    entry._msuf2ActionReserve = width
    if not entry._msuf2UXSummary then
        entry._msuf2ColorSwatchReserve = (entry._msuf2ColorSwatchReserve or 0) + width
    end
end

function M.RefreshSectionLayout(entry)
    local refresh = entry._msuf2RefreshLayout
    if refresh then refresh() end
end

function M.SetSectionPopupGetter(button, getPopup)
    button._msuf2GetSectionPopup = getPopup
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
