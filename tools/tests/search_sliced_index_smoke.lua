-- search_sliced_index_smoke.lua <repoRoot> [flavor]
--
-- The first search query builds the whole record set (live widgets, the static
-- index, provider rows, FAQ). On the debounced input path that build runs as a
-- resumable job, one slice per frame on the menu's own task registry
-- (SearchIndexBuild in MSUF_Menu2_Search_IndexQuery.lua), so it never lands in
-- one frame. This pins:
--   * a cold query on the input path takes several slices, shows the pending
--     state meanwhile and ends with the records and results of a synchronous
--     build (same records, same order, same ranked results);
--   * a synchronous reader in the middle finishes the same job, identical;
--   * an index invalidation between slices restarts the job, identical;
--   * typing on while it builds keeps the job and answers only the latest query;
--   * combat runs nothing: the pending slice is refused, quiescing drops the job,
--     and no menu task is left behind;
--   * the build uses no coroutine and no pcall.
--
-- Plain Lua 5.1, repo root as arg 1, flavor as arg 2 (default Mainline).

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"

local function Check(condition, message)
    if not condition then error("search_sliced_index_smoke (" .. flavor .. "): " .. message, 2) end
    return condition
end

local INDEX_QUERY = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_IndexQuery.lua"
local handle = assert(io.open(INDEX_QUERY, "rb"))
local source = handle:read("*a"):gsub("\r\n", "\n")
handle:close()
Check(not source:find("coroutine", 1, true) and not source:find("pcall", 1, true),
    "the search index build must not use coroutines or pcall")
Check(source:find("\nlocal C_Timer = M.MenuTimer", 1, true), "search must schedule through the menu task registry")
Check(source:find("        if not SearchIndexBuild.Advance() then\n            sliceQueued = true\n            C_Timer.After(0, RunLatest)\n", 1, true)
    and source:find("\n    C_Timer.After(0, RunLatest)\n    C_Timer.After(SEARCH_INPUT_DEBOUNCE_SEC, function()\n", 1, true),
    "the input path no longer advances the index build one slice per frame from the keystroke on")

local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "home" })
local M, env, world = mw.M, mw.env, mw.world
local combat = false
env.InCombatLockdown = function() return combat end
env.UnitAffectingCombat = function() return combat end
env.StaticPopup_Show = function() return nil end
-- Each clock read advances a quarter millisecond, so a slice covers a few dozen units.
local clock = 0
env.debugprofilestop = function() clock = clock + 0.25; return clock end

local built = 0
for _, key in ipairs(M.pageOrder) do
    if key ~= "search" and built < 6 then
        M.SelectPage(key)
        world.widgets:RunTimers()
        built = built + 1
    end
end
M.SelectPage("home")
world.widgets:RunTimers()

local api = M.Search._CoreAPI
local SS = M.Search._RenderContext.SEARCH_STATE

local function RecordsSignature(records)
    local out = {}
    for i, rec in ipairs(records) do
        out[i] = table.concat({ tostring(rec.key), tostring(rec.kind), tostring(rec.label), tostring(rec.hint),
            tostring(rec.labelNorm), tostring(rec.hintNorm), tostring(rec.haystack), tostring(rec.searchIdentity),
            tostring(rec.order), tostring(rec.controlId), tostring(rec.answer), tostring(rec.priority) }, "\031")
    end
    return table.concat(out, "\n")
end
local function ResultsSignature(rows)
    local out = {}
    for i, row in ipairs(rows) do
        out[i] = tostring(row.key) .. ":" .. tostring(row.kind) .. ":" .. tostring(row.label) .. ":" .. tostring(row.score)
    end
    return table.concat(out, ";")
end
local function Invalidate()
    api.ClearSearchLocaleCaches()
    api.MarkSearchIndexDirty()
end
local function Box(text) return { GetText = function() return text end } end
local function Schedule(query, onDone)
    api.ScheduleSearchInputQuery(Box(query), query, false, onDone)
end
local function RunOne() return world.widgets:RunTimers(1) end

---------------------------------------------------------------------------
-- 1. Cold query on the input path: sliced, pending meanwhile, then complete
---------------------------------------------------------------------------
Check(SS.records == nil, "the index was built before the first query")
local completed
Schedule("castbar", function(query) completed = query end)
Check(M.searchResultsPending == true, "the input path did not show the pending state")
-- The first slice is queued for the next frame, ahead of the debounce, so the
-- index builds while the player is still typing.
Check(#world.widgets.timers == 2 and world.widgets.timers[1].delay == 0 and world.widgets.timers[2].delay > 0,
    "the keystroke did not queue an index slice ahead of the debounce")
local slices = 0
while #world.widgets.timers > 0 do
    RunOne()
    slices = slices + 1
    if #world.widgets.timers > 0 then
        Check(M.searchResultsPending == true and completed == nil, "results were shown before the index was complete")
    end
    Check(slices < 100000, "the sliced build never finished")
end
Check(completed == "castbar" and not M.searchResultsPending, "the sliced query did not complete")
Check(slices > 4, "the cold index build was not sliced (" .. slices .. " timer callbacks)")
Check(M.MenuRuntime:PendingTaskCount() == 0, "a menu task was left behind after the build")
local slicedRecords = RecordsSignature(api.GetSearchRecords())
local slicedResults = ResultsSignature(M.searchResults)
local slicedTokens = 0
for _, rec in ipairs(api.GetSearchRecords()) do if rec.tokens then slicedTokens = slicedTokens + 1 end end
Check(slicedTokens == #api.GetSearchRecords(), "the sliced build left records without fuzzy tokens")

Invalidate()
local reference = RecordsSignature(api.GetSearchRecords())
Check(#reference > 0 and reference == slicedRecords, "the sliced build differs from a synchronous build")
Check(ResultsSignature(api.SearchPages("castbar")) == slicedResults, "the sliced query ranked differently")
local fontReference = ResultsSignature(api.SearchPages("font"))

---------------------------------------------------------------------------
-- 2. A synchronous reader in the middle finishes the same job
---------------------------------------------------------------------------
Invalidate()
Schedule("font")
RunOne(); RunOne(); RunOne()
local job = SS.indexQueue
Check(job and job.phase >= 1 and SS.recordsDirty, "the build did not stop between slices")
Check(ResultsSignature(api.SearchPages("font")) == fontReference, "a synchronous query mid-build ranked differently")
Check(RecordsSignature(api.GetSearchRecords()) == reference, "finishing the sliced job synchronously differs")
local finished = SS.records
world.widgets:RunTimers()
Check(SS.records == finished, "the input path rebuilt an index the synchronous reader had finished")

---------------------------------------------------------------------------
-- 3. An invalidation between slices restarts the job
---------------------------------------------------------------------------
Invalidate()
Schedule("castbar")
RunOne(); RunOne(); RunOne()
job = SS.indexQueue
Check(job ~= nil, "no job between slices")
api.MarkSearchIndexDirty()
world.widgets:RunTimers()
Check(SS.indexQueue ~= job, "the job resumed after the index was invalidated")
Check(RecordsSignature(api.GetSearchRecords()) == reference, "the restarted build differs")

---------------------------------------------------------------------------
-- 4. Typing on keeps the job and answers the latest query only
---------------------------------------------------------------------------
Invalidate()
local answered = {}
Schedule("cast", function(query) answered[#answered + 1] = query end)
RunOne(); RunOne(); RunOne()
job = SS.indexQueue
Schedule("castbar", function(query) answered[#answered + 1] = query end)
RunOne()
Check(SS.indexQueue == job, "a new keystroke discarded the build in progress")
world.widgets:RunTimers()
Check(#answered == 1 and answered[1] == "castbar", "a stale keystroke was answered")
Check(ResultsSignature(M.searchResults) == slicedResults, "the latest query ranked differently")
Check(RecordsSignature(api.GetSearchRecords()) == reference, "the build continued across keystrokes differs")

---------------------------------------------------------------------------
-- 5. Combat runs nothing; quiescing drops the job
---------------------------------------------------------------------------
Invalidate()
Schedule("castbar")
RunOne(); RunOne(); RunOne()
job = SS.indexQueue
local phase, index = job.phase, job.index
combat = true
world.widgets:RunTimers()
Check(job.phase == phase and job.index == index and SS.recordsDirty, "a build slice ran in combat")
M.frame:Hide()
world.widgets:RunTimers()
Check(SS.indexQueue == nil and not M.searchResultsPending, "quiescing the menu kept the build job")
Check(M.MenuRuntime:PendingTaskCount() == 0, "a menu task survived the combat quiesce")
combat = false
Check(M.Open("home") ~= false, "the menu did not reopen")
world.widgets:RunTimers()
completed = nil
Schedule("castbar", function(query) completed = query end)
world.widgets:RunTimers()
Check(completed == "castbar" and RecordsSignature(api.GetSearchRecords()) == reference,
    "the build after combat differs")

print(string.format("search_sliced_index_smoke (%s): ok (%d records, cold build in %d slices)",
    flavor, #api.GetSearchRecords(), slices))
