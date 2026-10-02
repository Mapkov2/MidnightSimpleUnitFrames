-- search_results_repaint_smoke.lua <repoRoot> <flavor>
--
-- WoW never frees a frame. The search results page used to be invalidated and
-- built again for every query, which left the previous page's whole frame tree
-- behind (review R7 P2, about 170 frames and regions per query). The page is
-- now built once and repainted in place:
--   1. after the pools are warm, any number of queries (results, details,
--      too short, no match) creates no frame and no region, and the page keeps
--      its cached entry;
--   2. every repaint shows the current query: header subtitle, status line,
--      one visible row per result (up to the visible maximum), hidden spare
--      rows, the overflow line and the examples section placed under the
--      resized results section;
--   3. a pooled row opens the record it shows now, not an earlier one;
--   4. showing the page again after the query was cleared elsewhere (history
--      back) repaints it, and example availability follows the gate.
--
-- Boots the real core and Options graph of one client (menu_core_world.lua).
-- Plain Lua 5.1, repo root and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local function Check(condition, message)
    if not condition then error("search_results_repaint_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

local mw = MenuWorld.Open(root, flavor, { page = "home" })
local M, env = mw.M, mw.env
local widgets = mw.world.widgets
local function Settle() widgets:RunTimers() end
local function WidgetCount()
    local total = #widgets.frames
    for i = 1, #widgets.frames do total = total + #(widgets.frames[i].regions or {}) end
    return total
end

local opened = {}
local routing = Check(M.Search and M.Search._RoutingAPI, "search routing did not load")
routing.OpenSearchTarget = function(pageKey, query, fallback, anchor, route)
    opened[#opened + 1] = { pageKey = pageKey, query = query, fallback = fallback, anchor = anchor, route = route }
    return true
end

local function Query(text)
    Check(M.SearchBridge.RunSearchQuery(text), "the query '" .. text .. "' did not run")
    Settle()
    Check(M.activeKey == "search", "the query '" .. text .. "' did not show the search page")
    return Check(M.cache.search, "the search page is not cached")
end
local function View(entry) return Check(entry._msuf2SearchView, "the search page has no repaint view") end

local function TopY(region)
    local _, relativeTo, _, x, y = region:GetPoint(1)
    return y, x, relativeTo
end
local function Shown(region) return region ~= nil and region.shown ~= false end
local function Visible(region)
    while region do
        if region.shown == false then return false end
        region = region.parent
    end
    return true
end

-- The visible state the page must show for the current query.
local function CheckPainted(entry, query)
    local view = View(entry)
    local results = M.searchResults or {}
    local visible = math.min(#results, 12)
    local ready = #query >= 2
    local subtitle = view.header.subtitle
    local wanted = query ~= "" and M.Format("Results for \"%s\"", query) or M.Tr("Search enabled features in your own words.")
    Check(subtitle:GetText() == wanted, "the header shows '" .. tostring(subtitle:GetText()) .. "' for '" .. query .. "'")
    local status = view.status:GetText()
    if query == "" then
        Check(status == M.Tr("Start typing to search available settings and help."), "the empty page status is wrong")
    elseif not ready then
        Check(status == M.Format("Type at least %d characters to search.", 2), "the short-query status is wrong")
    elseif #results == 0 then
        Check(status == M.Format("No exact setting found for \"%s\".", query), "the no-match status is wrong")
        Check(Shown(view.statusDetail), "the no-match hint is hidden")
    else
        Check(status == M.Format("Best %d match(es). Open one to view its setting or help.", visible),
            "the result status is wrong for '" .. query .. "'")
    end
    local rowsShown = (ready and #results > 0) and visible or 0
    for i, row in ipairs(view.rows) do
        if i <= rowsShown then
            local rec = results[i]
            Check(Shown(row.button), "row " .. i .. " is hidden for '" .. query .. "'")
            Check(row.rec == rec, "row " .. i .. " holds a stale record for '" .. query .. "'")
            local label = tostring(row.button:GetText() or "")
            local short = M.Search.ShortLabel(rec.label, 38)
            Check(label:find(short, 1, true) ~= nil, "row " .. i .. " shows '" .. label .. "', not '" .. tostring(short) .. "'")
            local detail = rec.answer ~= nil and rec.answer ~= ""
            Check(Shown(row.answer) == detail, "row " .. i .. " detail visibility is wrong")
        else
            Check(not Shown(row.button), "spare row " .. i .. " is still visible for '" .. query .. "'")
            Check(not Shown(row.answer) and not Shown(row.target), "spare row " .. i .. " still shows its detail")
        end
    end
    Check(#view.rows >= rowsShown, "fewer pooled rows than results")
    Check(Shown(view.more) == (rowsShown > 0 and #results > 12), "the overflow line visibility is wrong")
    -- The examples section sits one gap under the resized results section.
    local resultsY = TopY(view.results)
    local examplesY = TopY(view.examples)
    Check(examplesY == resultsY - view.results:GetHeight() - 12,
        "the examples section is not placed under the resized results section")
    return view
end

---------------------------------------------------------------------------
-- Pick queries for every page state
---------------------------------------------------------------------------
local entry = Query("health")
local view = CheckPainted(entry, "health")
Check(#view.rows > 0, "'health' found no results")
local manyQuery, detailQuery
for _, candidate in ipairs({ "castbar", "health", "font", "color", "aura", "text" }) do
    Query(candidate)
    if #M.searchResults > 12 then manyQuery = manyQuery or candidate end
end
for _, candidate in ipairs({ "how do i move frames", "how do i change the font", "reset profile", "what is msuf" }) do
    Query(candidate)
    for _, rec in ipairs(M.searchResults) do
        if rec.answer ~= nil and rec.answer ~= "" then detailQuery = detailQuery or candidate end
    end
end
Check(manyQuery, "no query returned more than the visible maximum")
Check(detailQuery, "no query returned a result with a detail answer")
local QUERIES = { "health", manyQuery, detailQuery, "h", "zzqxjv", "castbar" }

-- Warm the pools once with every state.
for _, text in ipairs(QUERIES) do CheckPainted(Query(text), text) end
entry = M.cache.search

---------------------------------------------------------------------------
-- 1 and 2. Queries repaint in place and create nothing
---------------------------------------------------------------------------
local first = WidgetCount()
local CYCLES = 3
for cycle = 1, CYCLES do
    for _, text in ipairs(QUERIES) do
        local before = WidgetCount()
        local shown = Query(text)
        Check(shown == entry, "the query '" .. text .. "' rebuilt the search page in cycle " .. cycle)
        Check(WidgetCount() == before, "the query '" .. text .. "' created " .. (WidgetCount() - before) .. " widgets")
        CheckPainted(shown, text)
    end
end
Check(WidgetCount() == first, CYCLES .. " query cycles created " .. (WidgetCount() - first) .. " widgets")

---------------------------------------------------------------------------
-- 3. A pooled row opens the record it shows now
---------------------------------------------------------------------------
Query("health")
local healthKey = M.searchResults[1].key
Query(detailQuery)
local rec = M.searchResults[1]
local row = View(entry).rows[1]
opened = {}
row.button:GetScript("OnClick")(row.button, "LeftButton")
if rec.noOpen then
    Check(#opened == 0, "an informational result opened a page")
else
    Check(#opened == 1 and opened[1].pageKey == rec.key and opened[1].query == detailQuery,
        "the pooled row opened " .. tostring(opened[1] and opened[1].pageKey) .. " instead of " .. tostring(rec.key)
            .. " (the earlier query's first row was " .. tostring(healthKey) .. ")")
end

---------------------------------------------------------------------------
-- 4. Showing the page again repaints it; example availability follows the gate
---------------------------------------------------------------------------
MenuWorld.FireVisibilityScripts(entry.wrapper)
Check(M.SelectPage("opt_misc"), "could not leave the search page")
Settle()
Check(not Visible(entry.wrapper), "the search page stayed visible on another page")
M.searchQuery, M.searchResults, M.searchResultsQuery = "", {}, ""
Check(M.SelectPage("search"), "could not return to the search page")
Settle()
Check(M.cache.search == entry, "returning to the search page rebuilt it")
CheckPainted(entry, "")

local available = false
M.RegisterSearchAvailability("search-repaint-smoke", function(page)
    if page == "suite_bags" then return available end
end)
M.RegisterPage("suite_bags", { title = "Bags", build = function() end })
M.Search.MarkIndexDirty()
local function ExampleShown(label)
    for _, button in pairs(View(entry).exampleButtons) do
        if Shown(button) and button:GetText() == label then return true end
    end
    return false
end
Query("health")
Check(not ExampleShown("Bags"), "an unavailable example is shown")
local beforeExamples = WidgetCount()
available = true
M.Search.MarkIndexDirty()
Query("castbar")
Check(ExampleShown("Bags"), "an available example is not shown after a repaint")
local created = WidgetCount() - beforeExamples
available = false
M.Search.MarkIndexDirty()
Query("health")
Check(not ExampleShown("Bags"), "an example that became unavailable is still shown")
available = true
M.Search.MarkIndexDirty()
local beforeAgain = WidgetCount()
Query("castbar")
Check(ExampleShown("Bags") and WidgetCount() == beforeAgain, "showing a pooled example again created widgets")

print(string.format("search_results_repaint_smoke %s: ok (%d queries x%d flat at %d widgets; rows, status, header,"
    .. " overflow and examples repaint in place; pooled example +%d once)", flavor, #QUERIES, CYCLES, first, created))
