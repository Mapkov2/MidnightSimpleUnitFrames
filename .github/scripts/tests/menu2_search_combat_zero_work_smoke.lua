-- Search must do literally nothing while the player is in combat.
--
-- The query itself was already gated, but the paths around it were not: reading the
-- record set drained deferred UI sections and rebuilt/decoded the index, and the
-- results-page refresh invalidated and rebuilt the search page. This smoke pins the
-- gates, and deliberately repeats every check out of combat so a permanently broken
-- gate cannot pass by returning nothing all the time.
local repoRoot = ...
repoRoot = tostring(repoRoot or "."):gsub("[/\\]+$", "")

local SEARCH_DIR = repoRoot .. "/MidnightSimpleUnitFrames/Shell/Menu2/Search/"

local inCombat = false
local counts = { pump = 0, invalidate = 0, select = 0, timer = 0 }

_G.InCombatLockdown = function() return inCombat end
_G.UnitAffectingCombat = function() return inCombat end
_G.GetLocale = function() return "enUS" end
_G.C_Timer = {
    After = function(_, callback)
        counts.timer = counts.timer + 1
        if type(callback) == "function" then callback() end
    end,
}

local function PickValues(source, names, defaultEmpty)
    local values, count = {}, 0
    source = source or {}
    for name in tostring(names or ""):gmatch("%S+") do
        count = count + 1
        local value = source[name]
        if defaultEmpty then value = value or {} end
        values[count] = value
    end
    return unpack(values, 1, count)
end

local M
M = {
    SearchData = {},
    navItems = {},
    pages = {},
    cache = {},
    Theme = {},
    Widgets = {},
    activeKey = "search",
    Pick = function(source, names) return PickValues(source, names) end,
    PickDefaults = function(source, names) return PickValues(source, names, true) end,
    KeySetFromWords = function(text)
        local out = {}
        for key in tostring(text or ""):gmatch("%S+") do out[key] = true end
        return out
    end,
    Tr = function(text) return text end,
    InvalidatePage = function() counts.invalidate = counts.invalidate + 1 end,
    SelectPage = function() counts.select = counts.select + 1 end,
    UnitPage = {
        PumpBackgroundSections = function() counts.pump = counts.pump + 1 end,
    },
}
local MSUF = { LOCALE = "enUS", MSUF2 = M }

for _, file in ipairs({
    "MSUF_Menu2_Search_Data.lua",
    "MSUF_Menu2_Search_Keywords.lua",
    "MSUF_Menu2_Search_QueryAliases.lua",
    "MSUF_Menu2_Search_Text.lua",
    "MSUF_Menu2_Search_StaticIndex_Data.lua",
    "MSUF_Menu2_Search_StaticIndex.lua",
    "MSUF_Menu2_Search_IndexQuery.lua",
}) do
    local path = SEARCH_DIR .. file
    local chunk, err = loadfile(path)
    assert(chunk, path .. ": " .. tostring(err))
    local ok, result = pcall(chunk, "MidnightSimpleUnitFrames", MSUF)
    assert(ok, path .. ": " .. tostring(result))
end

local Search = assert(M.Search, "search namespace missing")
local API = assert(Search._CoreAPI, "search core API missing")
local SearchPages = assert(API.SearchPages, "SearchPages missing")
local StaticIndex = assert(Search.StaticIndex, "static index module missing")

local function Reset()
    counts.pump, counts.invalidate, counts.select, counts.timer = 0, 0, 0, 0
end

-- ---------------------------------------------------------------- in combat
inCombat = true
Reset()

local results = SearchPages("health bar width")
assert(type(results) == "table" and #results == 0,
    "search returned results while in combat")
assert(not StaticIndex.IsDecoded(),
    "combat decoded the static index; that is the one expensive step this module has")
assert(counts.pump == 0, "combat drained deferred UI sections through the search path")

API.RefreshSearchResultsPage()
assert(counts.invalidate == 0 and counts.select == 0,
    "combat rebuilt the search results page")

API.MarkSearchIndexDirty()
assert(type(SearchPages("aura size")) == "table" and #SearchPages("aura size") == 0,
    "a dirty index still produced combat results")
assert(not StaticIndex.IsDecoded(), "a dirty index decoded the blob in combat")
assert(counts.pump == 0, "a dirty index drained deferred sections in combat")

if type(API.ScheduleSearchInputQuery) == "function" then
    API.ScheduleSearchInputQuery(nil, "health", false)
    assert(counts.timer == 0, "combat scheduled a debounce timer for a search query")
end

-- ------------------------------------------------------------ out of combat
-- Without this half, a gate that always returned nothing would still pass.
inCombat = false
Reset()

API.MarkSearchIndexDirty()
local live = SearchPages("health bar width")
assert(type(live) == "table" and #live > 0,
    "search found nothing out of combat; the combat gate is swallowing real queries")
assert(StaticIndex.IsDecoded(),
    "the static index never decoded out of combat, so coverage is not actually loaded")
assert(counts.pump > 0, "deferred section draining no longer happens outside combat")

-- A control that only the baked index knows about: no page was ever built here, so
-- finding it proves the static coverage really reaches the query engine.
local unvisited = SearchPages("Status indicator size")
assert(#unvisited > 0 and unvisited[1].key:find("^uf_"), string.format(
    "a control from an unbuilt page is unreachable (%d results)", #unvisited))

-- The engine must never build pages to answer a query. That path existed as the
-- background indexer and is gone; nothing may reintroduce it.
local indexQuery = (function()
    local handle = assert(io.open(SEARCH_DIR .. "MSUF_Menu2_Search_IndexQuery.lua", "rb"))
    local text = handle:read("*a") or ""
    handle:close()
    return (text:gsub("\r\n", "\n"))
end)()
assert(not indexQuery:find("BuildPageEntry", 1, true),
    "the search index builds menu pages again; that is unbounded work off a keystroke")
assert(not indexQuery:find("RegisterEvent", 1, true) and not indexQuery:find("OnUpdate", 1, true),
    "the search index registered an event or an OnUpdate; it must stay pull-only")

io.write(string.format("menu2_search_combat_zero_work_smoke: ok (%d results out of combat)\n", #live))
