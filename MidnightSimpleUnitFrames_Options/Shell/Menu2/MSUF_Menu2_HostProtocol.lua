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

-- Each accessor is one private field behind a public name. The generated
-- functions are built once at load and allocate nothing per call.
local function Getter(field)
    return function(object) return object[field] end
end
local function Setter(field)
    return function(object, value) object[field] = value end
end
-- A setter that hands the widget back so calls chain.
local function ChainSetter(field)
    return function(object, value)
        object[field] = value
        return object
    end
end
local function Flag(field, chain)
    return function(object)
        object[field] = true
        if chain then return object end
    end
end

------------------------------------------------------------------ controls
M.SkipHistoryCheckpoint = Flag("_msuf2SkipHistoryCheckpoint", true)
M.AllowCombatClick = Flag("_msuf2AllowCombatClick", true)
M.SetSearchTargetPrepare = ChainSetter("_msuf2PrepareExactSearchTarget")
M.GetSearchTargetPrepare = Getter("_msuf2PrepareExactSearchTarget")
M.SetCommandAction = ChainSetter("_msuf2CommandAction")
M.GetControlTitle = Getter("_msuf2Title")

-- Raw: a widget's label is its own field, never a method of its frame type.
function M.GetControlLabel(widget)
    return rawget(widget, "_msuf2Label")
end

M.GetControlSearchMeta = Getter("_msuf2SearchMeta")
M.GetRawSetText = Getter("_msuf2RawSetText")

function M.ReleaseColorShortcut(shortcut)
    shortcut._msuf2BoundColorShortcut = nil
end

------------------------------------------------------------------ sections
M.GetSectionEntry = Getter("_msuf2CollapsibleEntry")
M.SetSectionEntry = Setter("_msuf2CollapsibleEntry")
M.GetSectionWidth = Getter("_msuf2Width")
M.SetSectionWidth = Setter("_msuf2Width")
M.GetSectionCursor = Getter("_msuf2CursorY")
M.SetSectionCursor = Setter("_msuf2CursorY")
M.MarkContextColorHost = Flag("_msuf2ContextColorHost")
M.SetFixedPreviewHeight = Setter("_msuf2FixedPreviewActiveHeight")

function M.SetBuilderInsets(ctx, contentX, topInset)
    ctx._msuf2ContentX, ctx._msuf2TopInset = contentX, topInset
    return ctx
end

------------------------------------------------------------------ section entries
M.SetSectionEnsureVisible = Setter("_msuf2EnsureVisible")
M.GetSectionEnsureVisible = Getter("_msuf2EnsureVisible")
M.SetSectionRefreshState = Setter("_msuf2RefreshState")
M.GetSectionRefreshState = Getter("_msuf2RefreshState")
M.SetMissingSectionResolver = Setter("_msuf2ResolveMissingSection")
M.GetMissingSectionResolver = Getter("_msuf2ResolveMissingSection")

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

M.SetSectionPopupGetter = Setter("_msuf2GetSectionPopup")

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
