local root = assert(arg[1])
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local faqBuilds = 0
local mw = MenuWorld.Open(root, arg[2] or "Mainline", { page = "home", beforeOptions = function(world)
    local load = world.LoadFile
    function world:LoadFile(path, addon, ns)
        if path:match("MSUF_Menu2_Search_Catalog.lua$") then
            local data = self.core.MSUF2.SearchData
            local build = data.BuildFAQ
            data.BuildFAQ = function(...)
                faqBuilds = faqBuilds + 1
                return build(...)
            end
        end
        return load(self, path, addon, ns)
    end
end })
local M, env = mw.M, mw.env
local api = M.Search._CoreAPI
assert(faqBuilds == 0, "Home eagerly built the FAQ catalog")
assert(next(M.SearchData.QUERY_ALIASES) == nil, "Home eagerly expanded search aliases")
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
assert(faqBuilds == 0 and next(M.SearchData.QUERY_ALIASES) == nil, "empty search built its catalogs")
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
assert(faqBuilds == 1, "first search did not build the FAQ exactly once")
local faq = api.GetFAQRecords()
assert(#faq == 15 and api.GetFAQRecords() == faq, "FAQ catalog content/count or reuse changed")
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
-- Compare the bounded palette to the original sorted scan, including the
-- six optional dropdown slots, pinned targets, score ties and support floors.
local function CheckSelection()
    local finalize
    for i = 1, 100 do
        local name, value = debug.getupvalue(api.SearchPages, i)
        if name == "CurateSearchResults" then finalize = value break end
        if not name then break end
    end
    assert(finalize, "palette finalizer not found")
    local function Check(rows, support)
        local ranked, top = {}, 0
        for i, row in ipairs(rows) do
            ranked[i] = row
            if not row.exactQueryHit then top = math.max(top, row.score) end
        end
        table.sort(ranked, function(a, b)
            if a.score ~= b.score then return a.score > b.score end
            if a.hint ~= b.hint then return a.hint < b.hint end
            return a.order < b.order
        end)
        local floor = math.max(40, top >= 600 and top * (support and .70 or .42) or top >= 300 and top * .30 or 0)
        local expected = {}
        for _, r in ipairs(ranked) do
            if r.exactQueryHit or r.score >= floor or (r.queryClauseCount > 1 and r.missedClauses == 0 and r.kind == "toggle")
                or (#expected < 6 and r.choiceLabels) then
                expected[#expected + 1] = r
                if #expected == 24 then break end
            end
        end
        local actual, job, turns = nil, {}, 0
        while not actual do
            actual = finalize(rows, support, "quartz", job, -1)
            turns = turns + 1
            assert(turns < 400, "palette finalizer did not advance")
        end
        assert(#actual == #expected)
        for i, r in ipairs(expected) do assert(actual[i] == r, "palette order changed at " .. i) end
        if #rows > 48 then assert(turns > 2, "large palette was not interrupted") end
    end
    for _, count in ipairs({ 3, 6, 24, 48, 49, 127, 1021 }) do
        local rows = {}
        for i = 1, count do
            -- Only two unconditional high scores. A tied group of lower-scored
            -- choices competes with fully matched controls for the first six.
            local choice = i % 5 == 0
            rows[i] = { order = i, hint = tostring(i % 4), label = "row " .. i,
                score = i <= 2 and 800 or i % 5 * 55 + 1, exactQueryHit = i == 1,
                kind = choice and "dropdown" or (i % 7 == 0 and "toggle" or "faq"),
                queryClauseCount = 2, matchedClauses = choice and 1 or 2, missedClauses = choice and 1 or 0,
                choiceLabels = choice and { "Quartz" } or nil }
        end
        Check(rows, false)
        Check(rows, true)
    end
end
CheckSelection()

-- A cooperative snapshot may yield before producing rows, or produce several
-- batches. A change visible only through contextChanged must restart a scored
-- query before its old snapshot reaches the palette.
local begins, polls, generation, observed = 0, 0, 1, 1
local function BeginProbe()
    begins = begins + 1
    local step, captured = 0, generation
    return function(due)
        assert(type(due) == "function")
        step = step + 1
        if step == 1 then return nil, false end
        local key = "cooperative." .. captured .. "." .. step
        return {{ pageKey = "opt_bars", label = "Quarzprobe " .. captured .. " " .. step,
            kind = "toggle", settingKey = key }}, step == 3
    end
end
local function PollProbe()
    polls = polls + 1
    if generation ~= observed then observed = generation return true end
end
M.RegisterSearchProvider("slice-probe", function() error("cooperative provider collected synchronously") end, PollProbe, BeginProbe)
api.OpenSearchResults("quarzprobe")
for i = 1, 10000 do
    mw:RunTimers(1)
    if state.request and state.request.job and state.request.job.index > 1 then break end
end
assert(state.request and state.request.job and state.request.job.index > 1, "probe did not enter scoring")
generation = 2
Drain()
local function CheckBatch(rows, expected)
    local found = {}
    for _, row in ipairs(rows) do
        local key = row.exactTarget and row.exactTarget.settingKey
        if key and key:find("^cooperative%.") then found[key] = true end
    end
    assert(found["cooperative." .. expected .. ".2"] and found["cooperative." .. expected .. ".3"])
    for key in pairs(found) do assert(key:find("cooperative." .. expected .. ".", 1, true) == 1, "stale batch published") end
end
CheckBatch(M.searchResults, 2)
assert(begins == 2 and polls < 20, "provider polled repeatedly during scoring: " .. polls)
generation = 3
assert(#api.SearchPages("quarzprobe") == 0, "cached direct search ignored a provider change")
Drain()
CheckBatch(api.SearchPages("quarzprobe"), 3)
M.RegisterSearchProvider("slice-probe", nil)

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

-- Companion dictionaries keep cold writes and deletions while the source is pending.
do
local mw = MenuWorld.Open(root, arg[2] or "Mainline", { page = "home" })
local M, data = mw.M, mw.M.SearchData
local aliases = data.QUERY_ALIASES
-- A cold deletion must not be resurrected, including a set followed by delete.
aliases.castbar = {'cold replacement'}
aliases.castbar = nil
aliases.counterspell = nil
aliases['cold custom alias'] = {'crosshair'}
do
    local clock = 0
    mw.env.debugprofilestop = function() clock=clock+0.05; return clock end
    assert(not data.EnsureQueryAliases(0.10), 'alias build ignored its slice deadline')
    -- Writes while a source build is pending keep precedence as well.
    aliases.evoker = {'cold custom term'}
    local complete = false
    for i=1,5000 do
        if data.EnsureQueryAliases(clock+1) then complete = true; break end
    end
    assert(complete, 'alias source did not finish within bounded slices')
end
assert(rawget(aliases,'castbar') == nil, 'cold set/delete resurrected castbar')
assert(rawget(aliases,'counterspell') == nil, 'cold deletion resurrected counterspell')
assert(aliases.evoker[1] == 'cold custom term' and #aliases.evoker == 1, 'cold overwrite was merged with defaults')
assert(aliases['cold custom alias'][1] == 'crosshair', 'cold extension alias lost')
assert(rawget(aliases, 'pummel') and #rawget(aliases, 'pummel') > 0, 'untouched aliases were not initialized')
local serial=M.Search._RenderContext.SEARCH_STATE.dirtySerial
aliases['warm custom alias']={'font'}
assert(M.Search._RenderContext.SEARCH_STATE.dirtySerial > serial, 'warm source mutation no longer invalidates')
print('PASS cold source writes/deletes, sliced preparation, partial-build overrides, warm invalidation ' .. (arg[2] or 'Mainline'))
end
