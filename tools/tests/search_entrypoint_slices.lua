local root = assert(arg[1])
local mw = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))().Open(root, arg[2] or "Mainline", { page = "home" })
local M, env = mw.M, mw.env
local api = M.Search._CoreAPI
local function Drain()
    for _ = 1, 30 do
        if #mw.world.widgets.timers == 0 then return end
        mw:RunTimers(1000)
    end
    error("menu timers did not drain")
end
local queries = { "castbar", "font", "player size", "target enable", "crosshair", "pet happiness", "threat", "buff", "aura blacklist", "changelog", "group size", "texture", "reminder", "GCD", "empower", "import profile", "scale", "health text", "portrait", "range alpha" }
local function Signature(rows)
    local out = {}
    for i, r in ipairs(rows) do
        local t = r.exactTarget or {}
        out[i] = table.concat({r.key, r.kind, r.label, r.hint or "", tostring(r.score), t.controlId or "", t.sectionId or "", t.prepareKind or "", t.prepareValue or ""}, "\031")
    end
    return table.concat(out, "\030")
end
local function WriteSignatures()
    local out = {}
    for i, q in ipairs(queries) do out[i] = q .. "\029" .. Signature(api.SearchPages(q)) end
    return table.concat(out, "\n")
end
if arg[3] == "--reference" then
    local h = assert(io.open(assert(arg[4]), "wb"))
    local at = os.clock()
    api.GetSearchRecords()
    Drain()
    print(string.format("cold full build %s: %.2f ms", arg[2], (os.clock()-at)*1000))
    h:write(WriteSignatures()); h:close(); return
end
local clock = 0
env.debugprofilestop = function()
    if arg[3] == "--real" then return os.clock()*1000 end
    clock = clock + 0.05
    return clock
end
M.SelectPage("search")
Drain()
assert(not M.Search.StaticIndex.IsDecoded(), "empty search opened a cold build")
M.SelectPage("home")
local at = clock
assert(#api.GetSearchRecords() == 0, "cold getter synchronously built records")
assert(clock-at < 4, "cold getter used the frame budget")
api.OpenSearchResults("castbar")
assert(M.searchResultsPending and #M.searchResults == 0, "cold open did not remain pending")
local slices, max = 0, 0
local wallMax = 0
while #mw.world.widgets.timers > 0 do
    at = clock
    local wall = os.clock()
    mw:RunTimers(1)
    wallMax = math.max(wallMax, (os.clock()-wall)*1000)
    max = math.max(max, clock-at)
    slices = slices + 1
    assert(slices < 10000, "build never finishes")
    local state = M.Search._RenderContext.SEARCH_STATE
    if state.indexQueue and state.indexQueue.phase > 8 and not state.recordsReady then
        assert(#api.GetSearchRecords() == 0, "getter exposed partially warm records")
    end
end
assert(not M.searchResultsPending and #M.searchResults > 0 and slices > 4, "cold entry point failed to finish in slices")
assert(max < 4, "a build callback exceeded 4 ms: " .. max)
if arg[3] == "--real" then assert(wallMax < 4, "real callback exceeded 4 ms: " .. wallMax) end
local expected = Signature(M.searchResults)
assert(Signature(api.SearchPages("castbar")) == expected, "query result changes after ready")
if arg[4] then
    local h = assert(io.open(arg[4], "rb")); local reference = h:read("*a"); h:close()
    assert(WriteSignatures() == reference, "ranked results differ from baseline")
end
local function MaterializedTargets()
    local count = 0
    for _, rec in ipairs(M.Search.StaticIndex.GetRecords()) do
        if rawget(rec, "exactTarget") then count = count + 1 end
    end
    return count
end
local targetsBefore = MaterializedTargets()
api.SearchPages("2d portrait")
api.SearchPages("mana preview")
assert(MaterializedTargets() == targetsBefore, "exact-setting comparisons allocated target tables")
api.MarkSearchIndexDirty()
api.RunSearchInputQuery("font", true)
assert(M.searchResultsPending, "direct input bypassed slices")
api.ScheduleSearchInputQuery(nil, "crosshair", false)
Drain()
assert(M.searchQuery == "crosshair" and #M.searchResults > 0, "latest query lost")
api.MarkSearchIndexDirty()
api.GetSearchRecords()
local task = M.Search._RenderContext.SEARCH_STATE.sliceTask
assert(task and task.active, "no build task queued")
api.CancelSearchBackgroundIndex()
assert(not task.active, "cancelled pump remains runnable")
api.OpenSearchResults("castbar")
Drain()
-- Provider changes during scoring restart the cursor and accumulated results.
local rows = { { pageKey = "home", label = "Castbar obsolete provider", kind = "toggle", keywords = { "castbar" } } }
M.RegisterSearchProvider("e3-test", function() return rows end)
api.OpenSearchResults("castbar")
local state = M.Search._RenderContext.SEARCH_STATE
for i = 1, 10000 do
    mw:RunTimers(1)
    if state.request and state.request.job and state.request.job.index > 1 then break end
end
assert(state.request and state.request.job and state.request.job.index > 1, "provider test never entered scoring")
rows = { { pageKey = "home", label = "Castbar current provider", kind = "toggle", keywords = { "castbar" } } }
M.InvalidateSearchProvider("e3-test")
Drain()
assert(Signature(M.searchResults) == Signature(api.SearchPages("castbar")), "scoring retained stale provider records")
M.RegisterSearchProvider("e3-test", nil)
api.OpenSearchResults("castbar")
Drain()
-- Readiness callbacks can invalidate controls before the first scoring slice.
api.MarkSearchIndexDirty()
api.OpenSearchResults("castbar")
local ready = 0
api.WhenIndexReady(function() ready = ready + 1; api.MarkSearchIndexDirty() end)
Drain()
assert(ready == 1 and #M.searchResults > 0 and not M.searchResultsPending, "readiness invalidation published empty results")
assert(Signature(M.searchResults) == Signature(api.SearchPages("castbar")), "readiness restart changed ranking")
-- Invalidate a partial alias build after its key snapshot, then read directly.
M.InvalidateSearchLexicon()
api.OpenSearchResults("e3 unique alias")
local lexicon
for i = 1, 20 do
    local name, value = debug.getupvalue(M.InvalidateSearchLexicon, i)
    if name == "LEXICON_SOURCES" then lexicon = value end
end
for i = 1, 10000 do
    mw:RunTimers(1)
    if lexicon.job and lexicon.job.phase == 3 and lexicon.job.index > 1 then break end
end
assert(lexicon.job and lexicon.job.phase == 3, "alias test missed the key snapshot")
M.SearchData.QUERY_ALIASES["e3 unique alias"] = { "crosshair" }
assert(#api.SearchPages("e3 unique alias") == 0, "lexicon invalidation rebuilt synchronously")
Drain()
assert(#M.searchResults > 0 and Signature(M.searchResults) == Signature(api.SearchPages("e3 unique alias")), "partial alias build retained old key snapshot")
M.SearchData.QUERY_ALIASES["e3 unique alias"] = nil
M.InvalidateSearchLexicon()
api.OpenSearchResults("castbar")
Drain()
-- Both suggestion palettes must release row records, including standalone Dashboard ones.
local static = M.Search.StaticIndex
local weak = setmetatable({ store = getmetatable(static.GetRecords()[1]) }, { __mode = "v" })
local nav = M.CreateNavSearchPalette(M.frame, M.nav.searchBox)
local dashboard = M.CreateNavSearchPalette(M.frame, M.nav.searchBox, true)
nav:Refresh("castbar", false)
dashboard:Refresh("castbar", false)
assert(nav.rows[1]._msuf2PaletteResult, "palette did not exercise a result row")
M.HideSlashMenuAndMinibar(M.frame)
Drain()
collectgarbage("collect")
assert(not M.Search.StaticIndex.IsDecoded() and M.Search._RenderContext.SEARCH_STATE.records == nil, "closed menu retains search records")
assert(M.MenuRuntime:PendingTaskCount() == 0, "closed menu has tasks")
assert(nav.rows[1]._msuf2PaletteResult == nil and dashboard.rows[1]._msuf2PaletteResult == nil, "hidden palette retains records")
assert(weak.store == nil, "closed menu retains the entire column store")
assert(M.Open("search") ~= false)
Drain()
assert(Signature(M.searchResults) == expected, "reopening changed results")
local view = M.cache.search._msuf2SearchView
assert(view.rows[1].rec and view.rows[1].button:IsShown(), "async completion did not repaint cached search widgets")
print(string.format("search entry points (%s): %d slices, maximum clock budget %.2f ms; results identical; wall callback max %.2f ms", arg[2], slices, max, wallMax))
