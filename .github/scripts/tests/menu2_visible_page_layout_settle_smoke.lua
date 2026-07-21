local path = "MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Window.lua"
local file = assert(io.open(path, "rb"))
local source = file:read("*a")
file:close()

local settle = assert(source:match(
    "local function QueueVisiblePageLayoutSettle%b()%s*(.-)%s*function RebuildActivePageForResize"
), "visible-page layout settle helper missing")

assert(settle:find("entry._msuf2VisibleLayoutSettleQueued", 1, true),
    "visible-page layout settle is not coalesced")
assert(settle:find("for _, body in pairs(entry.sections or {}) do", 1, true)
    and settle:find("section._msuf2RefreshLayout()", 1, true),
    "visible-page layout settle does not refresh accordion header geometry")
assert(settle:find("builder:RelayoutCollapsibles(VISIBLE_SETTLE_RELAYOUT)", 1, true)
    and settle:find("ApplyScrollMetrics()", 1, true),
    "visible-page layout settle does not finish page/scroll geometry")
assert(settle:find("C_Timer.After(0, Settle)", 1, true),
    "visible-page layout settle is not deferred until anchored widths resolve")
assert(settle:find("entry._msuf2VisibleFontSettled", 1, true)
    and settle:find("T.RefreshMenuFontStrings(entry.fontStrings, true, true)", 1, true)
    and settle:find("T.RefreshMenuFonts(entry.wrapper, true, true)", 1, true),
    "visible-page layout settle does not retry registered fonts with a recursive compatibility fallback")
assert(not settle:find("OnUpdate", 1, true),
    "visible-page layout settle added recurring runtime work")

-- The optional fixed Editing/Page panel lives between the status bar and the
-- ScrollFrame. Both top corners must share the same vertical owner; anchoring
-- one corner to host:TOP and the other to status:BOTTOM collapses blank pages
-- (Dashboard is the zero-height-header case) until another layout pass.
assert(source:find('pageHeaderHost:SetPoint("TOPLEFT", topOwner, "BOTTOMLEFT", 0, 0)', 1, true),
    "page header host left edge is not anchored below the active top owner")
assert(source:find('pageHeaderHost:SetPoint("TOPRIGHT", topOwner, "BOTTOMRIGHT", -8, 0)', 1, true),
    "page header host right edge does not share the top owner's vertical anchor")
assert(not source:find('pageHeaderHost:SetPoint("TOPRIGHT", layoutHost, "TOPRIGHT"', 1, true),
    "page header host still mixes status-bottom and host-top vertical anchors")
assert(source:find('scroll:SetPoint("TOPLEFT", pageHeaderHost, "BOTTOMLEFT", 0, 0)', 1, true),
    "ScrollFrame no longer starts below the optional page header host")
assert(source:find('scroll:SetPoint("TOPLEFT", topOwner, "BOTTOMLEFT", 0, 0)', 1, true),
    "pages without Editing chrome do not bypass the optional header host")
local headerHostBlock = assert(source:match(
    "local function BuildWindowScrollHost%b()%s*(.-)%s*local function BuildWindow%b()"
), "window scroll/header host helper missing")
assert(not headerHostBlock:find("pageHeaderHost:CreateTexture", 1, true)
    and not headerHostBlock:find("pageHeaderHost:SetClipsChildren", 1, true),
    "structural page header still adds a rectangular texture or clips rounded panel assets")
assert(headerHostBlock:find("function M.SetActivePageHeader(entry)", 1, true)
    and headerHostBlock:find("function M.DisposePageHeader(entry)", 1, true),
    "page header activation/disposal is not owned by the window lifecycle")

local buildPage = assert(source:match(
    "local function BuildPageEntry%b()%s*(.-)%s*%-%- Cold%-path public entry point"
), "BuildPageEntry helper missing")
local hideBeforeBuild = assert(buildPage:find("if wrapper.Hide then wrapper:Hide() end", 1, true),
    "new page wrapper is not hidden before build")
local specBuild = assert(buildPage:find("local result = spec.build(ctx)", 1, true),
    "page build call missing")
assert(hideBeforeBuild < specBuild, "page wrapper is hidden only after its controls are built")

local selectPage = assert(source:match(
    "function M%.SelectPage%b()%s*(.-)%s*local function CreateMinimizedBar"
), "SelectPage helper missing")
assert(selectPage:find("M.CallIf(M.SetActivePageHeader, cached)", 1, true),
    "cached page selection does not reconcile its fixed header")
local clearHeader = assert(selectPage:find("M.CallIf(M.SetActivePageHeader, nil)", 1, true),
    "page transition does not clear the previous fixed header")
local hidePrevious = assert(selectPage:find("previous.wrapper:Hide()", 1, true),
    "previous page wrapper hide missing")
local activateHeader = assert(selectPage:find("M.CallIf(M.SetActivePageHeader, entry)", 1, true),
    "new page does not activate its registered fixed header")
local showEntry = assert(selectPage:find("entry.wrapper:Show()", 1, true),
    "new page wrapper show missing")
assert(clearHeader < hidePrevious and activateHeader < showEntry,
    "page transition commits wrappers before synchronizing fixed-header ownership")
assert(source:find("M.CallIf(M.DisposePageHeader, invalidated)", 1, true),
    "page invalidation does not dispose retained header ownership")
assert(source:find("M.CallIf(M.DisposePageHeader, previous)", 1, true),
    "layout-variant replacement does not dispose retained header ownership")

local callCount = 0
for _ in source:gmatch("QueueVisiblePageLayoutSettle%(") do callCount = callCount + 1 end
assert(callCount >= 4,
    "visible-page layout settle is not wired to cached selection, new selection, and window show")

io.write("menu2_visible_page_layout_settle_smoke: ok\n")
