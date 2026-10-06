-- host_menu_protocol_smoke.lua [repoRoot]
--
-- MSUF host API v2, Menu2 half: the widget protocol (MSUF_Menu2_HostProtocol.lua),
-- loaded right after MSUF_Menu2_PageResetProviders.lua:
--   * M.HOST_API_VERSION is 2 and the v1 provider functions stay untouched;
--   * every entry point writes and reads exactly the fields the Suite wrote
--     itself before (MSUF-Suite 7adf858, the snippets below verbatim, are
--     the oracle): undo checkpoints, combat clicks, the exact search prepare
--     hook, the command action, section entries, widths, cursors, builder
--     insets, ensure-visible, refresh-state and missing-section hooks, the
--     section action reserve (with and without a summary row) and the nav
--     icons (legacy and HD atlas, keys MSUF already styles, shared colors);
--   * a control label is read raw, never from the frame type's methods;
--   * no entry point allocates.
--
-- Plain Lua 5.1. Repo root as arg 1, default ".".

local root = ((arg and arg[1]) or "."):gsub("\\", "/"):gsub("/$", "")
local MENU2 = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/"
local checks = 0

local function Check(condition, message)
    if not condition then error(message, 2) end
    checks = checks + 1
end

local function Read(path)
    local handle = assert(io.open(path, "rb"), path .. " is missing")
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return text
end

local function Load(path, ...)
    return assert(loadstring(Read(path), "@" .. path))(...)
end

local function Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

local function Show(value)
    if type(value) ~= "table" then return tostring(value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    return "{" .. table.concat(keys, ",") .. "}"
end

------------------------------------------------------------------ A. Menu2 v2
do
    local xml = Read(MENU2 .. "MSUF_Menu2.xml")
    local v1 = xml:find('<Script file="MSUF_Menu2_PageResetProviders.lua"/>', 1, true)
    local v2 = xml:find('<Script file="MSUF_Menu2_HostProtocol.lua"/>', 1, true)
    Check(v1 and v2 and v2 > v1, "MSUF_Menu2.xml must load the v2 protocol after the v1 providers")
end

local T = {}
local function Register() end
local M = { Theme = T, HOST_API_VERSION = 1, RegisterPageResetProvider = Register }
Load(MENU2 .. "MSUF_Menu2_HostProtocol.lua", "MidnightSimpleUnitFrames", { MSUF2 = M })
Check(M.HOST_API_VERSION == 2 and M.RegisterPageResetProvider == Register,
    "the v2 file must raise HOST_API_VERSION to 2 and leave the v1 functions alone")

-- The oracle: the Suite's own writes before host API v2 (MSUF-Suite 7adf858).
local Oracle = {}
function Oracle.SectionActionButton(entry, more)
    -- MSUF_Suite_Options/Menu/SectionActions.lua:26-31, 41
    more._msuf2SkipHistoryCheckpoint = true
    entry._msuf2SectionActions = more
    entry._msuf2ActionReserve = 34
    if not entry._msuf2UXSummary then
        entry._msuf2ColorSwatchReserve = (entry._msuf2ColorSwatchReserve or 0) + 34
    end
    if entry._msuf2RefreshLayout then entry._msuf2RefreshLayout() end
end
-- MSUF_Suite_Options/Menu/Register.lua:27-36 (pages = { { key, icon, accent } })
local HD_NAV_ICONS = { suite_one = { 0, 3 } }
function Oracle.AddIcons(theme, pages)
    if type(theme.navIconGrid) ~= "table" or type(theme.navIconColors) ~= "table" then return end
    local neutral = theme.navIconColors.gameplay or theme.navIconColors.profiles
    local accent = theme.navIconColors.home or neutral
    for _, page in ipairs(pages) do
        local icon = (tonumber(theme.navIconAtlasVersion) or 0) >= 2 and HD_NAV_ICONS[page.key] or page.icon
        if icon and theme.navIconGrid[page.key] == nil then theme.navIconGrid[page.key] = icon end
        if theme.navIconColors[page.key] == nil then
            theme.navIconColors[page.key] = page.accent and accent or neutral
        end
    end
end

-- Flags and hooks: the same fields as the Suite's assignments.
do
    local prepare, ensure, refresh, resolve, action = function() end, function() end, function() end,
        function() end, { kind = "toggle" }
    local host, oracle = {}, {}
    Check(M.SkipHistoryCheckpoint(host) == host and M.AllowCombatClick(host) == host
        and M.SetSearchTargetPrepare(host, prepare) == host and M.SetCommandAction(host, action) == host,
        "the control entry points must return the widget")
    oracle._msuf2SkipHistoryCheckpoint, oracle._msuf2AllowCombatClick = true, true
    oracle._msuf2PrepareExactSearchTarget, oracle._msuf2CommandAction = prepare, action
    Check(Same(host, oracle), "control fields differ from the Suite's writes: " .. Show(host))
    Check(M.GetSearchTargetPrepare(host) == prepare, "the search prepare hook did not round-trip")
    M.SetSearchTargetPrepare(host, nil)
    Check(host._msuf2PrepareExactSearchTarget == nil, "a nil prepare must clear the hook")

    local frame, entry, ctx = {}, {}, {}
    M.SetSectionEntry(frame, entry)
    M.SetSectionWidth(frame, 640)
    M.SetSectionCursor(frame, -120)
    M.MarkContextColorHost(frame)
    M.SetFixedPreviewHeight(frame, 310)
    Check(M.SetBuilderInsets(ctx, 0, 0) == ctx and ctx._msuf2ContentX == 0 and ctx._msuf2TopInset == 0,
        "builder insets differ from the Suite's context fields")
    Check(Same(frame, { _msuf2CollapsibleEntry = entry, _msuf2Width = 640, _msuf2CursorY = -120,
        _msuf2ContextColorHost = true, _msuf2FixedPreviewActiveHeight = 310 }),
        "section fields differ from the Suite's writes: " .. Show(frame))
    Check(M.GetSectionEntry(frame) == entry and M.GetSectionWidth(frame) == 640
        and M.GetSectionCursor(frame) == -120, "the section getters do not read the section fields")
    M.SetSectionEnsureVisible(entry, ensure)
    M.SetSectionRefreshState(entry, refresh)
    M.SetMissingSectionResolver(entry, resolve)
    Check(Same(entry, { _msuf2EnsureVisible = ensure, _msuf2RefreshState = refresh,
        _msuf2ResolveMissingSection = resolve }), "entry hooks differ from the Suite's writes: " .. Show(entry))
    Check(M.GetSectionEnsureVisible(entry) == ensure and M.GetSectionRefreshState(entry) == refresh
        and M.GetMissingSectionResolver(entry) == resolve, "the entry hook getters do not round-trip")

    local shortcut = { _msuf2BoundColorShortcut = true }
    M.ReleaseColorShortcut(shortcut)
    Check(shortcut._msuf2BoundColorShortcut == nil, "the color shortcut stayed bound")

    local title, meta, raw = {}, {}, function() end
    local methods = { _msuf2Label = "a method, not a label" }
    local widget = setmetatable({ _msuf2Title = title, _msuf2SearchMeta = meta }, { __index = methods })
    Check(M.GetControlTitle(widget) == title and M.GetControlSearchMeta(widget) == meta
        and M.GetRawSetText({ _msuf2RawSetText = raw }) == raw, "the control getters do not read the fields")
    Check(M.GetControlLabel(widget) == nil, "a control label must be read raw")
    local label = {}
    widget._msuf2Label = label
    Check(M.GetControlLabel(widget) == label, "the control label getter does not read the label")

    local popup = function() end
    local button = {}
    M.SetSectionPopupGetter(button, popup)
    Check(button._msuf2GetSectionPopup == popup, "the section popup getter field differs")
end

-- The section action reserve, with and without a summary row.
for _, start in ipairs({ {}, { _msuf2UXSummary = {} }, { _msuf2ColorSwatchReserve = 26 },
    { _msuf2UXSummary = {}, _msuf2ColorSwatchReserve = 26 } }) do
    local layouts = { host = 0, oracle = 0 }
    local function Entry(kind)
        local entry = {}
        for key, value in pairs(start) do entry[key] = value end
        entry._msuf2RefreshLayout = function() layouts[kind] = layouts[kind] + 1 end
        return entry
    end
    local host, oracle, button, oracleButton = Entry("host"), Entry("oracle"), {}, {}
    M.SkipHistoryCheckpoint(button)
    M.ReserveSectionActions(host, button, 34)
    M.RefreshSectionLayout(host)
    Oracle.SectionActionButton(oracle, oracleButton)
    host._msuf2RefreshLayout, oracle._msuf2RefreshLayout = nil, nil
    host._msuf2SectionActions, oracle._msuf2SectionActions = nil, nil
    Check(Same(host, oracle) and Same(button, oracleButton) and layouts.host == 1 and layouts.oracle == 1,
        "the section action reserve differs from the Suite's: " .. Show(host) .. " / " .. Show(oracle))
end
M.RefreshSectionLayout({})

-- Navigation icons: legacy and HD atlas, styled keys, missing tables.
local function Theme(version)
    local home, gameplay = { 1, 1, 1 }, { 0.5, 0.5, 0.5 }
    return { navIconAtlasVersion = version,
        navIconGrid = { home = { 0, 0 }, suite_kept = { 9, 9 } },
        navIconColors = { home = home, gameplay = gameplay, profiles = { 0, 0, 0 }, suite_kept = home } }
end
local PAGES = { { key = "suite_one", icon = { 2, 0 }, accent = true }, { key = "suite_two", icon = { 3, 0 } },
    { key = "suite_kept", icon = { 4, 0 } }, { key = "suite_none" } }
for _, version in ipairs({ false, 1, 2 }) do
    local hostTheme, oracleTheme = Theme(version or nil), Theme(version or nil)
    T.navIconGrid, T.navIconColors, T.navIconAtlasVersion =
        hostTheme.navIconGrid, hostTheme.navIconColors, hostTheme.navIconAtlasVersion
    for _, page in ipairs(PAGES) do
        M.AddNavIcon(page.key, { icon = page.icon, hdIcon = HD_NAV_ICONS[page.key], accent = page.accent })
    end
    Oracle.AddIcons(oracleTheme, PAGES)
    Check(Same(hostTheme, oracleTheme), "nav icons differ from the Suite's on atlas " .. tostring(version))
    Check(hostTheme.navIconColors.suite_one == hostTheme.navIconColors.home
        and hostTheme.navIconColors.suite_two == hostTheme.navIconColors.gameplay,
        "nav icon colors must share MSUF's color tables (theme recolors walk them)")
    Check(hostTheme.navIconGrid.suite_one == (version == 2 and HD_NAV_ICONS.suite_one or PAGES[1].icon),
        "the nav icon cell must follow the atlas version")
end
T.navIconGrid, T.navIconColors = nil, nil
Check(M.AddNavIcon("suite_one", { icon = { 1, 1 } }) == false, "nav icons need MSUF's icon tables")

-- No entry point allocates (measured twice, the lower run counts).
do
    local widget, entry, button, ctx = {}, {}, {}, {}
    local function Calls()
        for _ = 1, 1000 do
            M.SkipHistoryCheckpoint(widget)
            M.AllowCombatClick(widget)
            M.GetSearchTargetPrepare(widget)
            M.GetSectionWidth(widget)
            M.SetSectionCursor(widget, -40)
            M.ReserveSectionActions(entry, button, 34)
            M.RefreshSectionLayout(entry)
            M.SetBuilderInsets(ctx, 0, 0)
        end
    end
    Calls()
    local best
    for _ = 1, 2 do
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        Calls()
        local used = collectgarbage("count") - before
        collectgarbage("restart")
        best = best and math.min(best, used) or used
    end
    Check(best < 0.5, ("the v2 entry points allocate %.2f KB per 1000 rounds"):format(best))
end

print(("host_menu_protocol_smoke: ok (%d checks)"):format(checks))
