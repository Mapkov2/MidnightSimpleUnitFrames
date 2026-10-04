-- menu_lazy_accordion_smoke.lua <repoRoot> [flavor]
--
-- b:LazyCollapsibleSection and W.EnsureSectionContent on the real Menu2 page
-- builder, booted with one client's core and Options graph and the menu open.
-- Show fires OnShow down the visible parent chain, as in the client.
--   * a cold page frame keeps closed lazy sections shell-only (the shell
--     callback runs, the content does not);
--   * open sections, opts.eager and a proxy that hands back a body it is
--     filling build synchronously inside the page build;
--   * the body OnShow (a header click) builds the content once: the build
--     flags are set during it and restored after it, only the new refreshers
--     run, once, FinishSection's relayout stays pending until one relayout
--     afterwards, and the section gets its previous (tracked) refresher back;
--   * the chained state refresher builds an open section whose body never
--     showed;
--   * under the configuration combat lock no trigger builds or creates a
--     frame, and every trigger stays armed for the next out-of-combat show;
--   * W.EnsureSectionContent builds once and is idempotent; a replaced page
--     entry never builds;
--   * hidden (search index) builds and M.EagerSections build every section;
--   * an exact search route builds the target section and resolves its
--     control; a route-opened section builds inside the page build;
--   * a facade routes the shell to its tab builder; deferWhileHidden waits for
--     the tab to show;
--   * a raising build is reported and leaves no building state behind;
--   * the lazy stage arms no timer, ticker, OnUpdate or event.
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_lazy_accordion_smoke (" .. flavor .. "): " .. message, 2) end
    return condition
end

-- The lazy stage itself: no timer, ticker, OnUpdate or event, ever.
do
    local handle = assert(io.open(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Widgets_PageBuilder.lua", "rb"))
    local source = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    local first = Check(source:find("local LazySection = {}", 1, true), "the lazy stage is missing")
    local last = Check(source:find("function PageBuilderStages.InstallSectionMethods", first, true), "the lazy stage has no end")
    local stage = source:sub(first, last)
    for _, banned in ipairs({ "C_Timer", "NewTicker", "OnUpdate", "RegisterEvent", "MenuTimer", "QueueTask" }) do
        Check(not stage:find(banned, 1, true), "the lazy stage uses " .. banned)
    end
end

local mw = MenuWorld.Open(root, flavor, { page = "home" })
local M, env = mw.M, mw.env
local W = M.Widgets
local widgets = mw.world.widgets
Check(type(W.EnsureSectionContent) == "function", "W.EnsureSectionContent is missing")

-- Client visibility: a frame is visible when it and every parent are shown,
-- and OnShow runs for each shown frame that becomes visible.
local Methods = widgets.Methods
local function Visible(frame)
    while frame do
        if not frame.shown then return false end
        frame = frame.parent
    end
    return true
end
local function FireShown(frame)
    local onShow = frame.scripts and frame.scripts.OnShow
    if onShow then onShow(frame) end
    for _, child in ipairs(frame.children or {}) do
        if child.shown then FireShown(child) end
    end
end
function Methods:Show()
    if self.shown then return end
    self.shown = true
    if Visible(self) then FireShown(self) end
end
function Methods:Hide() self.shown = false end
function Methods:SetShown(shown) if shown then self:Show() else self:Hide() end end
function Methods:IsVisible() return Visible(self) end

local errors = {}
env.geterrorhandler = function() return function(message) errors[#errors + 1] = tostring(message) end end

local KEY = "zz_lazy_lab"
local lab = { calls = {}, flags = {}, pending = {}, refreshed = {}, bodies = {} }
local function Count(name) return lab.calls[name] or 0 end
local function Bump(name) lab.calls[name] = Count(name) + 1 end
local function ResetCounts()
    lab.calls, lab.flags, lab.pending, lab.refreshed = {}, {}, {}, {}
end

-- Content: rows plain frames tall, one refresher, FinishSection at the end.
local function Content(name, rows, extra)
    return function(body, entry)
        Bump(name)
        if lab.fail == name then error("lazy lab build raised") end
        local ctx = lab.ctx
        lab.flags[name] = {
            ctx = ctx._msuf2Building, page = ctx.entry._msuf2Building, incomplete = ctx.entry._msuf2BuildIncomplete,
        }
        for _ = 1, rows do
            local row = env.CreateFrame("Frame", nil, body)
            row:SetPoint("TOPLEFT", body, "TOPLEFT", 16, body._msuf2CursorY)
            body._msuf2CursorY = body._msuf2CursorY - 30
        end
        if extra then extra(body) end
        M.AddRefresher(ctx, function() lab.refreshed[name] = (lab.refreshed[name] or 0) + 1 end)
        lab.builder:FinishSection(body)
        lab.pending[name] = entry.builder._msuf2RelayoutPending == true
    end
end

local function BuildLab(ctx)
    lab.ctx = ctx
    local b = W.PageBuilder(ctx)
    lab.builder = b
    local bodies = {}
    lab.bodies = bodies
    bodies.closed_a = b:LazyCollapsibleSection("closed_a", "Closed A", 120, false, Content("closed_a", 4), {
        shell = function(body, entry)
            Bump("shell_a")
            lab.shellEntry = entry
            lab.shellRefresh = M.TrackCollapsibleRefresh(ctx, body, function() Bump("shell_refresh_a") end)
        end,
        onBuilt = function(body)
            Bump("on_built_a")
            lab.onBuiltBody = body
            lab.onBuiltBuilding = ctx._msuf2Building
        end,
    })
    bodies.after_a = b:CollapsibleSection("after_a", "After A", 60, false)
    bodies.open_b = b:LazyCollapsibleSection("open_b", "Open B", 120, true, Content("open_b", 2))
    bodies.eager_fn = b:LazyCollapsibleSection("eager_fn", "Eager", 80, false, Content("eager_fn", 1), {
        eager = function(eagerCtx) lab.eagerCtx = eagerCtx; return true end,
    })
    for _, id in ipairs({ "closed_c", "closed_d", "closed_e", "closed_f", "fail_k", "route_open" }) do
        bodies[id] = b:LazyCollapsibleSection(id, id, 80, false, Content(id, 2))
    end
    bodies.route_g = b:LazyCollapsibleSection("route_g", "Route G", 80, false, Content("route_g", 1, function(body)
        local proof = env.CreateFrame("Button", nil, body)
        M.RegisterSearchWidget(proof, {
            controlId = "menu2.zz_lazy_lab.route_proof", pageKey = KEY, label = "Lazy route proof",
            kind = "toggle", classification = "setting", settingKey = "general.lazyRouteProof",
        })
        lab.routeProof = proof
    end))
    -- Content with a nested builder: its relayout settles after the build.
    bodies.nested_n = b:LazyCollapsibleSection("nested_n", "Nested N", 80, false, function(body)
        Bump("nested_n")
        local nested = W.CreateNestedAuraBuilder(ctx, b, body)
        lab.nestedBuilder = nested
        nested:CollapsibleSection("nested_inner", "Nested inner", 60, true)
        lab.nestedPending = nested._msuf2RelayoutPending == true
    end)
    -- A proxy hands back the body it is filling right now: build at once.
    local existing = b:CollapsibleSection("proxy_body", "Proxy body", 80, false)
    lab.proxyExisting = existing
    local proxy = setmetatable({}, { __index = b })
    function proxy:CollapsibleSection() return existing end
    bodies.proxy = proxy:LazyCollapsibleSection("proxy_body", "Proxy body", 80, false, Content("proxy", 1))
    -- A facade routes sections to a tab builder whose panel is not selected.
    local panel = env.CreateFrame("Frame", nil, ctx.wrapper)
    panel:SetSize(600, 80)
    panel:Hide()
    local child = setmetatable({ wrapper = panel, width = 600, _msuf2ContentX = 0, _msuf2TopInset = 0 }, { __index = ctx })
    function child:SetContentHeight(height) panel:SetHeight(height) end
    local tab = W.PageBuilder(child)
    lab.tabPanel, lab.tabBuilder = panel, tab
    local facade = setmetatable({}, { __index = b })
    function facade:CollapsibleSection(id, title, height, open) return tab:CollapsibleSection(id, title, height, open) end
    bodies.tab_defer = facade:LazyCollapsibleSection("tab_defer", "Tab defer", 80, true, Content("tab_defer", 2),
        { deferWhileHidden = true })
    bodies.tab_open = facade:LazyCollapsibleSection("tab_open", "Tab open", 80, true, Content("tab_open", 2))
end
M.RegisterPage(KEY, { title = "Lazy lab", build = BuildLab })

local function ClearAccordion()
    local state = M.GetPersistentMenuStateTable("accordionState")
    for _, target in ipairs({ state, M.accordionState or {} }) do
        for key in pairs(target) do
            if tostring(key):find("^zz_lazy_lab:") then target[key] = nil end
        end
    end
end
local function Entry(id) return lab.bodies[id]._msuf2CollapsibleEntry end
local function Page() return M.cache[KEY] end

---------------------------------------------------------------------------
-- Cold page frame: closed sections are shells, open ones built in the build.
---------------------------------------------------------------------------
ClearAccordion()
Check(mw:Select(KEY) ~= false and M.activeKey == KEY, "the lab page did not open")
local page = Check(Page(), "the lab page has no entry")
local entryA = Entry("closed_a")
Check(Count("shell_a") == 1 and lab.shellEntry == entryA, "the shell callback did not run once with the entry")
Check(Count("closed_a") == 0 and #lab.bodies.closed_a.children == 0, "a closed section built its content on the cold frame")
Check(type(entryA._msuf2EnsureContent) == "function", "a closed section exposes no _msuf2EnsureContent")
Check(not lab.bodies.closed_a:IsShown(), "a closed lazy body is shown after the page build")
for _, id in ipairs({ "closed_c", "closed_d", "closed_e", "closed_f", "route_g", "fail_k", "route_open", "tab_defer" }) do
    Check(Count(id) == 0, id .. " built during the cold page build")
end
Check(Count("open_b") == 1 and lab.flags.open_b.ctx == true and lab.flags.open_b.incomplete == true,
    "an open section did not build synchronously inside the page build")
Check(lab.bodies.open_b._msuf2CollapsibleEntry._msuf2EnsureContent == nil, "a synchronously built section kept a lazy trigger")
Check(Count("eager_fn") == 1 and lab.eagerCtx == lab.ctx, "opts.eager(ctx) did not build at once")
Check(Count("proxy") == 1 and lab.bodies.proxy == lab.proxyExisting, "a proxy body was not filled at once")
Check(Count("tab_open") == 1, "an open section in a hidden tab without deferWhileHidden did not build at once")
local tabEntry = Entry("tab_defer")
Check(tabEntry.builder == lab.tabBuilder and lab.bodies.tab_defer:GetParent():GetParent() == lab.tabPanel,
    "the facade did not route the shell to its tab builder")
for _, collapsible in ipairs(lab.builder.collapsibles) do
    Check(collapsible ~= tabEntry, "the facade section landed in the page builder too")
end
Check(W.EnsureSectionContent(nil) == false, "EnsureSectionContent(nil) did not answer false")
Check(W.EnsureSectionContent(lab.bodies.after_a) == true and W.EnsureSectionContent(lab.bodies.open_b) == true,
    "a plain or already built section did not answer true")
local catalog = M.RuntimeControlCatalog
Check(catalog.ResolveExactTarget(KEY, { controlId = "menu2.zz_lazy_lab.route_proof" }) == nil,
    "the route proof control exists before its section built")

---------------------------------------------------------------------------
-- Header click: OnShow builds once, flags, refresher tail, one relayout.
---------------------------------------------------------------------------
local refreshers = page.refreshers
local shellRefreshBefore = Count("shell_refresh_a")
Check(shellRefreshBefore >= 1, "the page refreshers did not run the shell refresher")
Check(entryA._msuf2RefreshState ~= lab.shellRefresh and entryA._msuf2TrackedRefreshState == entryA._msuf2RefreshState,
    "the lazy refresher did not wrap the tracked shell refresher as tracked")
local refresherCount = #refreshers
local afterEntry = Entry("after_a")
local afterY = afterEntry._msuf2RelayoutY
entryA.header:Click()
Check(entryA.open == true and lab.bodies.closed_a:IsVisible(), "the header click did not open the section")
Check(Count("closed_a") == 1 and Count("on_built_a") == 1 and lab.onBuiltBody == lab.bodies.closed_a,
    "the header click did not build the content and onBuilt once")
local flags = lab.flags.closed_a
Check(flags.ctx == true and flags.page == true and flags.incomplete == true, "the build ran without the build flags")
Check(lab.onBuiltBuilding == true, "onBuilt ran outside the build window")
Check(lab.ctx._msuf2Building == nil and page._msuf2Building == nil and page._msuf2BuildIncomplete == nil,
    "the build flags were not restored")
Check(lab.pending.closed_a == true, "FinishSection relayout ran inside the build instead of staying pending")
Check(entryA.builder._msuf2RelayoutPending == nil, "the pending relayout was not settled after the build")
Check(lab.refreshed.closed_a == 1 and #refreshers == refresherCount + 1, "the new refresher did not run exactly once")
Check(Count("shell_refresh_a") == shellRefreshBefore + 1, "the state refresh on open did not reach the shell refresher once")
Check(entryA._msuf2RefreshState == lab.shellRefresh and entryA._msuf2TrackedRefreshState == lab.shellRefresh,
    "the section did not get its tracked shell refresher back")
Check(entryA.contentHeight == 174 and entryA.outer:GetHeight() == 32 + 174, "the opened section does not have its content height")
Check(afterEntry._msuf2RelayoutY == afterY - 174, "the next section did not move below the grown section")
entryA.header:Click()
entryA.header:Click()
Check(Count("closed_a") == 1 and lab.refreshed.closed_a == 1, "reopening rebuilt the content or re-ran its refreshers")

---------------------------------------------------------------------------
-- Chained refresher: an open section whose body never showed.
---------------------------------------------------------------------------
local entryC = Entry("closed_c")
local lazyRefreshC = entryC._msuf2RefreshState
entryC.open = true
lazyRefreshC(entryC)
Check(Count("closed_c") == 1 and lab.refreshed.closed_c == 1, "the state refresher did not build an open section")
Check(entryC._msuf2RefreshState == nil, "the section without a refresher of its own kept the lazy one")
lazyRefreshC(entryC)
Check(Count("closed_c") == 1, "a second state refresh rebuilt the content")
entryC.open = false

---------------------------------------------------------------------------
-- Combat lock: nothing builds, no frame is created, every trigger stays armed.
---------------------------------------------------------------------------
local entryD, bodyD = Entry("closed_d"), lab.bodies.closed_d
local frames = mw:Frames()
widgets:SetCombat(true)
Check(M.IsConfigCombatLocked(), "the harness combat lock is not active")
Check(W.EnsureSectionContent(bodyD) == false, "EnsureSectionContent built under the combat lock")
entryD.open = true
bodyD:Show()
entryD._msuf2RefreshState(entryD)
Check(Count("closed_d") == 0 and mw:Frames() == frames, "a trigger built under the combat lock")
widgets:SetCombat(false)
bodyD:Hide()
bodyD:Show()
Check(Count("closed_d") == 1, "the OnShow trigger was consumed under the combat lock")
entryD.open = false
bodyD:Hide()

---------------------------------------------------------------------------
-- EnsureSectionContent: once, idempotent, by body or entry.
---------------------------------------------------------------------------
local entryE = Entry("closed_e")
Check(W.EnsureSectionContent(lab.bodies.closed_e) == true and Count("closed_e") == 1, "EnsureSectionContent did not build")
Check(W.EnsureSectionContent(entryE) == true and entryE._msuf2EnsureContent() == true and Count("closed_e") == 1,
    "EnsureSectionContent is not idempotent")
Check(not lab.bodies.closed_e:IsShown() and entryE.open == false, "EnsureSectionContent opened the section")

local entryN = Entry("nested_n")
Check(W.EnsureSectionContent(entryN) == true and Count("nested_n") == 1, "the nested content did not build")
Check(lab.nestedPending == true and lab.nestedBuilder._msuf2RelayoutPending == nil,
    "the nested builder's relayout did not stay pending during the build and settle after it")
Check(entryN.contentHeight == 154, "the nested builder's height did not reach its section: " .. tostring(entryN.contentHeight))

---------------------------------------------------------------------------
-- Exact search route: the hook builds the target section.
---------------------------------------------------------------------------
local selected, anchored, exact = M.Search.OpenTarget(KEY, "lazy route proof", "lazy route proof", nil, {},
    { sectionId = "route_g", controlId = "menu2.zz_lazy_lab.route_proof" })
Check(selected and anchored and exact and Count("route_g") == 1, "the exact route did not build its section and resolve the control")
mw:RunTimers()
Check(Entry("route_g").open == true and Count("route_g") == 1, "the route did not open its section, or built it twice")

---------------------------------------------------------------------------
-- A raising build is reported and leaves no building state behind.
---------------------------------------------------------------------------
lab.fail = "fail_k"
local entryK = Entry("fail_k")
Check(W.EnsureSectionContent(lab.bodies.fail_k) == false and Count("fail_k") == 1, "a raising build answered true")
Check(#errors == 1 and errors[1]:find("Menu2 section content", 1, true), "the raising build was not reported once")
Check(lab.ctx._msuf2Building == nil and page._msuf2Building == nil, "a raising build left the build flags set")
Check(page._msuf2BuildIncomplete == true, "a raising build did not mark the page for a rebuild")
Check(W.EnsureSectionContent(entryK) == false and Count("fail_k") == 1, "a raising build ran again")
lab.fail = nil

---------------------------------------------------------------------------
-- A replaced page entry never builds into its old frames.
---------------------------------------------------------------------------
local staleF = lab.bodies.closed_f
mw:Select("home")
M.InvalidatePage(KEY)
Check(Page() ~= page, "the lab page entry was not replaced")
Check(W.EnsureSectionContent(staleF) == false and Count("closed_f") == 0, "a stale page entry built its section")

---------------------------------------------------------------------------
-- Facade tab: deferWhileHidden builds on the tab's first show.
---------------------------------------------------------------------------
ClearAccordion()
ResetCounts()
mw:Select(KEY)
Check(Count("tab_defer") == 0 and Count("tab_open") == 1, "the rebuilt page built the deferred tab section")
lab.tabPanel:Show()
Check(Count("tab_defer") == 1 and lab.refreshed.tab_defer == 1, "showing the tab did not build the deferred section once")

---------------------------------------------------------------------------
-- Hidden (search index) builds and M.EagerSections build everything.
---------------------------------------------------------------------------
local ALL = { "closed_a", "open_b", "eager_fn", "closed_c", "closed_d", "closed_e", "closed_f", "fail_k", "route_open",
    "route_g", "proxy", "tab_defer", "tab_open", "nested_n" }
mw:Select("home")
M.InvalidatePage(KEY)
ResetCounts()
Check(M.BuildPageEntry(KEY, true) ~= nil, "the hidden build failed")
for _, id in ipairs(ALL) do Check(Count(id) == 1, id .. " was not built by the hidden build") end
M.InvalidatePage(KEY)
ResetCounts()
M.EagerSections = true
mw:Select(KEY)
M.EagerSections = nil
for _, id in ipairs(ALL) do Check(Count(id) == 1, id .. " was not built with M.EagerSections") end

---------------------------------------------------------------------------
-- A route-opened section builds inside the page build.
---------------------------------------------------------------------------
mw:Select("home")
M.InvalidatePage(KEY)
ClearAccordion()
ResetCounts()
M.Search.ApplyRoute(KEY, { accordion = { [KEY .. ":route_open"] = true } })
mw:Select(KEY)
Check(Count("route_open") == 1 and lab.flags.route_open.incomplete == true, "the route-opened section did not build in the page build")
Check(Count("closed_c") == 0, "a route rebuild built a closed section")
ClearAccordion()

print("menu_lazy_accordion_smoke: ok (" .. flavor .. "; shells on the cold frame, synchronous open/eager/proxy/hidden builds,"
    .. " OnShow, refresher and EnsureContent triggers build once, combat lock stays armed, route hook, facade tab, raise recovery)")
