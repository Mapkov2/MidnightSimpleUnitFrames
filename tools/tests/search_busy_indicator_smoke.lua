-- Real first-open navigation input: pending feedback precedes all search work.
local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { open = false, clientScriptBindings = true })
local M, env = mw.M, mw.env
local palettes, create = {}, M.CreateNavSearchPalette
M.CreateNavSearchPalette = function(...)
    local palette = create(...)
    palettes[#palettes + 1] = palette
    return palette
end
assert(M.Open("home") ~= false)
mw:RunTimers()
MenuWorld.FireVisibilityScripts(M.frame)
local box = M.nav.searchBox
local palette
for _, item in ipairs(palettes) do if item.searchBox == box then palette = item end end
assert(palette, "navigation suggestions were not created")
local clock = 0
env.debugprofilestop = function() clock = clock + 0.05; return clock end
local function Type(text)
    box:SetText(text)
    MenuWorld.FireScript(box, "OnTextChanged", true)
end
local function Drain()
    for _ = 1, 40 do
        if #mw.world.widgets.timers == 0 then return end
        mw:RunTimers(1000)
    end
    error("search did not finish")
end
local function Busy(indicator, expected, label)
    assert(indicator, label .. ": missing visible loading indicator")
    assert(indicator:IsShown() == expected, label .. ": wrong indicator visibility")
    assert(indicator.animation:IsPlaying() == expected, label .. ": wrong animation state")
end

Type("castbar")
local spinner = palette.busyIndicator
Busy(spinner, true, "cold keystroke before timers")
assert(M.searchResultsPending and not M.Search.StaticIndex.IsDecoded(), "test warmed the index before feedback")
assert(palette.status:IsShown() and palette.status:GetText() == M.Tr("Searching settings..."), "pending label missing")
assert(spinner.animation.looping == "REPEAT", "loading animation must repeat")
local rotation = spinner.animation.animations[1]
assert(rotation.degrees == -360 and rotation.duration == 1, "loading circle must rotate continuously")
assert(M.Theme._menuAnimationGroups[spinner.animation], "animation must participate in menu shutdown")
assert(spinner:GetScript("OnUpdate") == nil, "loading indicator must not poll in Lua")
Type("font")
assert(palette.busyIndicator == spinner, "typing allocated another indicator")
Busy(spinner, true, "replacement query")
Drain()
assert(#M.searchResults > 0 and M.searchResultsQuery == "font", "latest query did not produce results")
Busy(spinner, false, "results ready")
Type("zzzxqvvzzz")
Drain()
assert(#M.searchResults == 0, "no-result fixture unexpectedly matched")
Busy(spinner, false, "no matches")
Type("castbar")
MenuWorld.FireScript(box, "OnEscapePressed")
Busy(spinner, false, "escape")
Drain()
Busy(spinner, false, "cancelled callbacks")
Type("castbar")
Type("")
Busy(spinner, false, "empty query")
Drain()

env.MSUF_DB.general.reduceMotion = true
Type("castbar")
assert(spinner:IsShown() and not spinner.animation:IsPlaying(), "reduced motion must keep a static busy indication")
env.MSUF_DB.general.reduceMotion = nil
Type("font")
Busy(spinner, true, "motion restored")
M.HideSlashMenuAndMinibar(M.frame)
Busy(spinner, false, "closed menu")
Drain()
assert(M.MenuRuntime:PendingTaskCount() == 0, "closed menu retained search tasks")
assert(M.Open("home") ~= false)
Drain()
Type("castbar")
Busy(spinner, true, "reopened navigation")
M.MenuRuntime:Quiesce("combat", "PLAYER_REGEN_DISABLED")
Busy(spinner, false, "combat quiesce")
Drain()
M.IsConfigCombatLocked("PLAYER_REGEN_ENABLED")
M.MenuRuntime:Resume("test")

-- Example/Enter results use the same indicator, with enough space for text.
M.Search._CoreAPI.OpenSearchResults("castbar")
local view = assert(M.cache.search._msuf2SearchView)
Busy(view.busyIndicator, true, "full results pending")
local fullSpinner = view.busyIndicator
Drain()
Busy(fullSpinner, false, "full results ready")
Type("font")
Busy(spinner, true, "navigation over full page")
Busy(fullSpinner, true, "full page follows navigation")
palette:Hide()
Busy(spinner, false, "navigation click-off")
Busy(fullSpinner, false, "full page click-off")
assert(not view.status:IsShown(), "cancelled query still claims to be searching")
Drain()
M.Search._CoreAPI.OpenSearchResults("castbar")
Drain()
assert(view.rows[1].button:IsShown(), "indicator displaced actual search results")
M.Search._CoreAPI.OpenSearchResults("font")
Busy(fullSpinner, true, "repeated full-page search")
assert(view.busyIndicator == fullSpinner, "full page allocated a repeated indicator")
Type("")
Busy(fullSpinner, false, "full page cleared query")
Drain()
M.Search._CoreAPI.OpenSearchResults("castbar")
Busy(fullSpinner, true, "full page restarted")
Type("x")
Busy(fullSpinner, false, "full page short query")
Drain()
M.Search._CoreAPI.OpenSearchResults("font")
Busy(fullSpinner, true, "full page before close")
M.HideSlashMenuAndMinibar(M.frame)
Busy(fullSpinner, false, "full page closed")
Drain()
assert(M.MenuRuntime:PendingTaskCount() == 0, "spinner left a timer after close")
-- The real debounced path and direct reads share three recent exact queries.
assert(M.Open("home") ~= false)
Drain()
local api = M.Search._CoreAPI
local function Query(text)
    Type(text)
    Drain()
    assert(M.searchResultsQuery == text and not M.searchResultsPending, "query did not settle")
    return M.searchResults
end
local first, second, third = Query("castbar"), Query("font"), Query("minimap")
assert(Query("castbar") == first and Query("minimap") == third, "the last three queries were not reused")
assert(Query("Castbar") ~= first, "a differently spelled query reused the result list")
assert(Query("castbar") == first, "a cache hit did not renew recency")
assert(Query("font") ~= second, "the fourth-most-recent query remained cached")

local textureRows = api.SearchPages("texture")
local bars
for _, row in ipairs(textureRows) do if row.key == "opt_bars" then bars = row break end end
assert(bars, "texture query fixture lost its Bars result")
local originalPage, score = M.activeKey, bars.score
M.activeKey = "opt_bars"
assert(api.SearchPages("texture") ~= textureRows and bars.score == score + 120, "origin page did not change ranking")
M.activeKey = originalPage
assert(api.SearchPages("texture") == textureRows and bars.score == score, "cache reused another page's rank metadata")

-- A synchronous cache hit can arrive while the debounce job is between scan and sort.
api.MarkSearchIndexDirty()
api.GetSearchRecords()
Drain()
M.activeKey = "opt_bars"
local boosted = api.SearchPages("texture")
M.activeKey = originalPage
api.ScheduleSearchInputQuery(nil, "texture", false)
local state = M.Search._RenderContext.SEARCH_STATE
for _ = 1, 1000 do
    mw:RunTimers(1)
    if state.request and state.request.job and state.request.job.sortReady then break end
end
assert(state.request and state.request.job and state.request.job.sortReady, "fixture did not pause before sort")
M.activeKey = "opt_bars"
assert(api.SearchPages("texture") == boosted, "interleaving fixture missed the cache")
M.activeKey = originalPage
Drain()
local settled = false
for _, row in ipairs(M.searchResults) do
    if row.key == bars.key and row.label == bars.label and row.score == score then settled = true break end
end
assert(settled, "a synchronous cache hit changed the suspended query ranking")

local font = Query("font")
M.InvalidateSearchLexicon()
assert(Query("font") ~= font, "a lexicon change reused cached results")
local empty = Query("zzzxqvvzzz")
assert(#empty == 0 and Query("zzzxqvvzzz") == empty, "a completed empty query did not reuse its result list")
M.RegisterSearchProvider("search-cache-test", function()
    return { { pageKey = "opt_bars", kind = "toggle", label = "zzzxqvvzzz" } }
end)
local fresh = Query("zzzxqvvzzz")
assert(fresh ~= empty and fresh[1] and fresh[1].key == "opt_bars", "an index change did not invalidate the cached query")
M.RegisterSearchProvider("search-cache-test", nil)
M.HideSlashMenuAndMinibar(M.frame)
Drain()
print("search_busy_indicator_smoke " .. flavor .. ": pending/results/cancel/close/combat/reduced-motion passed")
