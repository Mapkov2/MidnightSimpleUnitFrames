-- search_provider_hook_smoke.lua <repoRoot> [replacement IndexQuery source]
--
-- Menu2 search knows only the pages MSUF ships: live widgets of built pages and the
-- generated static index. An optional companion addon (the MSUF Suite) owns further
-- pages, so the search layer offers a generic runtime hook for it,
-- M.RegisterSearchProvider(name, collect), in MSUF_Menu2_Search_IndexQuery.lua.
--
-- This boots the real Mainline core and Options graph (client_world.lua), registers
-- test providers on a test page and pins the hook's contract:
--   * no provider, no work: the index build never collects, nothing runs per query;
--   * lazy: collect() runs on the first search, once, and again only after a new
--     registration or a menu language change; never at registration, never in combat;
--   * rows are validated: malformed rows are skipped and counted, never raised;
--   * records have the static-record shape: breadcrumb "<nav group> > <page> > <section>",
--     exact target (setting key + accordion route), FAQ rows ranked as FAQ;
--   * page rows add keywords, answer and breadcrumb to the page's own record, and a
--     query naming a page still ranks the page above that page's provider controls;
--   * a live widget for the same setting on the same page replaces the provider row;
--   * a provider that raises is skipped afterwards, so search keeps working.
--
-- Plain Lua 5.1, repo root as arg 1. Arg 2 (mutation checks only) loads another file
-- in place of MSUF_Menu2_Search_IndexQuery.lua.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local replacement = arg[2]
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"),
    "search_provider_hook_smoke: tools/tests/client_world.lua is missing")()

local function Check(condition, message)
    if not condition then error("search_provider_hook_smoke: " .. message, 2) end
    return condition
end

local INDEX_QUERY = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_IndexQuery.lua"

---------------------------------------------------------------------------
-- 1. Source contract: the provider block stays off the per-query path
---------------------------------------------------------------------------
local handle = assert(io.open(replacement or (root .. "/" .. INDEX_QUERY), "rb"))
local source = handle:read("*a"):gsub("\r\n", "\n")
handle:close()
local searchPages = Check(source:match("\nfunction SearchPages%(query%)\n(.-)\nend\n"),
    "MSUF_Menu2_Search_IndexQuery.lua lost SearchPages")
Check(not searchPages:find("SearchProviders", 1, true) and not searchPages:find("SEARCH_STATE.provider", 1, true),
    "SearchPages (runs per query) must not touch search providers")
local build = Check(source:match("\nlocal function BuildSearchRecords%(%)\n(.-)\nend\n"),
    "MSUF_Menu2_Search_IndexQuery.lua lost BuildSearchRecords")
Check(build:find("next(SEARCH_STATE.providers) ~= nil and SearchProviders.Collect(", 1, true),
    "the index build must collect providers only while one is registered")
Check(not source:find("pcall", 1, true), "no pcall/xpcall in addon code")

---------------------------------------------------------------------------
-- 2. Boot one client with its real search layer
---------------------------------------------------------------------------
local world = World.New(root, "Mainline")
if replacement then
    local LoadFile = world.LoadFile
    function world:LoadFile(path, ...)
        if path:gsub("\\", "/"):sub(-#INDEX_QUERY) == INDEX_QUERY then path = replacement end
        return LoadFile(self, path, ...)
    end
end
world:Boot()
local failure = world:FirstFailure()
Check(failure == nil, "Mainline did not boot: " .. tostring(failure and failure.file) .. " "
    .. tostring(failure and failure.message))
local main = world.core
local M = Check(main.MSUF2, "Menu2 did not load")
local api = Check(M.Search and M.Search._CoreAPI, "the search core API did not load")
local combat = false
world.env.InCombatLockdown = function() return combat end
world.env.UnitAffectingCombat = function() return false end

Check(type(M.RegisterSearchProvider) == "function", "M.RegisterSearchProvider is missing")
Check(type(api.GetSearchProviderCache) == "function", "the search core API lost GetSearchProviderCache")
Check(M.RegisterSearchProvider(nil, function() end) == false and M.RegisterSearchProvider("", function() end) == false
    and M.RegisterSearchProvider("x", "not a function") == false, "RegisterSearchProvider accepted a bad argument")

-- No provider: searches work and nothing is collected.
local before = api.SearchPages("castbar")
Check(#before > 0, "baseline search found nothing")
api.MarkSearchIndexDirty()
api.SearchPages("minimap")
Check(api.GetSearchProviderCache() == nil, "the index build collected providers although none is registered")

---------------------------------------------------------------------------
-- 3. A test page in the navigation, and a provider for it
---------------------------------------------------------------------------
local PAGE = "zz_provider_lab"
M.RegisterPage(PAGE, { title = "Provider Lab", build = function() end, version = 1 })
local groupId, groupTitle
for _, item in ipairs(M.navItems) do
    if item.title and item.id then groupId, groupTitle = item.id, item.title; break end
end
Check(groupId ~= nil, "the navigation has no group title")
table.insert(M.navItems, { key = PAGE, label = "Provider Lab", group = groupId })
local GROUP = M.Tr(groupTitle)

local calls = 0
local function LabRows()
    calls = calls + 1
    return {
        { pageKey = PAGE, kind = "page", keywords = { "qzxlabword", "gadget bench" },
          help = "The lab answer.", hint = "Companion > " .. GROUP .. " > Provider Lab" },
        { pageKey = PAGE, kind = "slider", label = "Provider Lab size", section = "Frame",
          settingKey = "labsuite.lab.size", sectionId = "zz_provider_lab_frame", keywords = "qzxsize" },
        { pageKey = PAGE, kind = "toggle", label = "Frobnicate the glow", section = "Glow",
          settingKey = "labsuite.lab.glow", keywords = { "qzxglow" }, help = "Adds a soft glow." },
        { pageKey = PAGE, kind = "section", label = "Glow" },
        { pageKey = PAGE, kind = "color", label = "Lab glow color", section = "Glow", anchorText = "Glow" },
        { pageKey = PAGE, kind = "faq", label = "Where is the qzxfaq lab?", help = "Open the Provider Lab page.",
          keywords = "qzxfaq|lab question" },
        -- Malformed: every one of these is skipped and counted.
        "not a table",
        { kind = "toggle", label = "No page" },
        { pageKey = "zz_no_such_page", kind = "toggle", label = "Unknown page" },
        { pageKey = PAGE, kind = "wobble", label = "Unknown kind" },
        { pageKey = PAGE, kind = "toggle", label = 42 },
        { pageKey = PAGE, kind = "toggle", label = string.rep("x", 400) },
        { pageKey = "search", kind = "toggle", label = "Search page" },
        -- Wrong optional fields are ignored, the row stays.
        { pageKey = PAGE, kind = "dropdown", label = "Lab mode", keywords = 42, help = {}, settingKey = false },
    }
end
local VALID, MALFORMED = 7, 7

Check(M.RegisterSearchProvider("lab", LabRows) == true, "RegisterSearchProvider refused a valid provider")
Check(calls == 0, "the provider was called at registration")

local function Find(results, predicate)
    for index, rec in ipairs(results) do
        if predicate(rec) then return rec, index end
    end
end

-- Combat: no search work at all, so no collection either.
combat = true
Check(#api.SearchPages("qzxsize") == 0 and calls == 0, "a search in combat collected the provider")
combat = false

---------------------------------------------------------------------------
-- 4. First search: one collection, validated rows, static-record shape
---------------------------------------------------------------------------
local results = api.SearchPages("qzxsize")
Check(calls == 1, "the first search must call the provider exactly once, called " .. calls)
local cache = Check(api.GetSearchProviderCache(), "no provider cache after the first search")
Check(cache.rows == VALID and cache.skipped == MALFORMED, "rows " .. tostring(cache.rows) .. "/"
    .. tostring(cache.skipped) .. ", expected " .. VALID .. " valid and " .. MALFORMED .. " skipped")

local size = Check(results[1], "the provider control was not found")
Check(size.key == PAGE and size.label == "Provider Lab size" and size.kind == "slider" and size.provided,
    "the provider control is not the first result for its keyword")
Check(size.hint == GROUP .. " > Provider Lab > Frame", "breadcrumb is '" .. tostring(size.hint) .. "'")
Check(size.labelNorm == "provider lab size" and size.titleNorm == "" and size.tokenLimit == 36
    and size.searchIdentity:find("^provided\031"), "the provider record is not shaped like a static record")
Check(size.exactTarget and size.exactTarget.pageKey == PAGE and size.exactTarget.settingKey == "labsuite.lab.size"
    and size.exactTarget.sectionId == "zz_provider_lab_frame", "the exact target lost its setting or section")
Check(size.route and size.route.accordion and size.route.accordion[PAGE .. ":zz_provider_lab_frame"] == true,
    "opening the result does not open its accordion")

local glow = Check(api.SearchPages("frobnicate the glow")[1], "the toggle was not found by its label")
Check(glow.label == "Frobnicate the glow" and glow.answer == "Adds a soft glow." and glow.route == nil,
    "the toggle lost its answer or gained a route without a section id")
Check(api.SearchPages("soft glow")[1] == glow, "help text is not searchable")
local color = Check(Find(api.SearchPages("lab glow color"), function(rec) return rec.kind == "color" end),
    "the color row was not found")
Check(color.exactTarget == nil and color.anchorFallback == "Glow", "a row without a setting must anchor on its text")
local mode = Check(Find(api.SearchPages("lab mode"), function(rec) return rec.label == "Lab mode" end),
    "a row with ignored optional fields was dropped")
Check(mode.exactTarget == nil and mode.answer == nil, "ignored optional fields leaked into the record")
local faq = Check(api.SearchPages("qzxfaq")[1], "the provider FAQ was not found")
Check(faq.kind == "faq" and faq.faq and faq.key == PAGE and faq.answer == "Open the Provider Lab page.",
    "the provider FAQ is not an FAQ record for its page")

-- Page rows decorate the page's own record.
local page = Check(api.SearchPages("qzxlabword")[1], "the page keyword does not find the page")
Check(page.kind == "page" and page.key == PAGE and page.answer == "The lab answer."
    and page.hint == "Companion > " .. GROUP .. " > Provider Lab", "the page row did not decorate the page record")
local pages = 0
for _, rec in ipairs(api.SearchPages("provider lab")) do
    if rec.kind == "page" and rec.key == PAGE then pages = pages + 1 end
end
Check(pages == 1, "the page row must decorate the page record, not add a second one (" .. pages .. ")")

-- A query naming the page ranks the page above its own provider controls.
local named = api.SearchPages("provider lab")
Check(named[1] and named[1].kind == "page" and named[1].key == PAGE,
    "'provider lab' ranks " .. tostring(named[1] and named[1].label) .. " above the Provider Lab page")
Check(Find(named, function(rec) return rec.label == "Provider Lab size" end),
    "the page's control is missing from a page-name query")

-- Rebuilds and repeated searches reuse the cache.
for _ = 1, 3 do
    api.MarkSearchIndexDirty()
    api.SearchPages("qzxglow")
end
Check(calls == 1 and api.GetSearchProviderCache() == cache, "an index rebuild called the provider again")

---------------------------------------------------------------------------
-- 5. A live widget for the same setting replaces the provider row
---------------------------------------------------------------------------
local widget = world.env.CreateFrame("Frame")
M.RegisterSearchWidget(widget, { pageKey = PAGE, kind = "slider", label = "Provider Lab size",
    settingKey = "labsuite.lab.size" })
local sizes = {}
for _, rec in ipairs(api.SearchPages("provider lab size")) do
    if rec.label == "Provider Lab size" then sizes[#sizes + 1] = rec end
end
Check(#sizes == 1 and not sizes[1].provided,
    "a built page shows the provider row next to its live control (" .. #sizes .. " results)")
M.UnregisterSearchWidget(widget)
Check(Find(api.SearchPages("qzxsize"), function(rec) return rec.provided and rec.label == "Provider Lab size" end),
    "the provider row did not return after the live control went away")
Check(calls == 1, "live registrations must not re-collect providers")

---------------------------------------------------------------------------
-- 6. Menu language change: collected again, once
---------------------------------------------------------------------------
local locale = main.LOCALE
main.LOCALE = (locale == "deDE") and "frFR" or "deDE"
api.SearchPages("qzxglow")
api.SearchPages("qzxsize")
Check(calls == 2, "a menu language change must collect the provider once more, calls " .. calls)
main.LOCALE = locale
api.SearchPages("qzxglow")
Check(calls == 3, "switching the language back must collect again, calls " .. calls)

---------------------------------------------------------------------------
-- 7. A provider that raises is skipped afterwards; search keeps working
---------------------------------------------------------------------------
local raised = 0
M.RegisterSearchProvider("broken", function()
    raised = raised + 1
    error("provider failure")
end)
local ok = pcall(api.SearchPages, "qzxglow")
Check(not ok and raised == 1, "the raising provider was not called on the next search")
local after = api.SearchPages("qzxglow")
Check(raised == 1, "a provider that raised was called again before it registered anew")
Check(Find(after, function(rec) return rec.label == "Frobnicate the glow" end),
    "a raising provider took the other providers' rows with it")
Check(#api.SearchPages("castbar") == #before, "a raising provider changed the built-in results")
M.RegisterSearchProvider("broken", nil)

---------------------------------------------------------------------------
-- 8. Removing the provider removes its rows and its page words
---------------------------------------------------------------------------
Check(M.RegisterSearchProvider("lab", nil) == true, "a provider could not be removed")
Check(Find(api.SearchPages("qzxglow"), function(rec) return rec.provided end) == nil,
    "provider rows outlived their provider")
Check(#api.SearchPages("qzxlabword") == 0, "page words outlived their provider")
local finalCache = api.GetSearchProviderCache()
Check(finalCache == nil or (#finalCache.records == 0 and next(finalCache.pages) == nil),
    "the provider cache kept rows of a removed provider")

print("search_provider_hook_smoke: ok (" .. VALID .. " rows, " .. MALFORMED .. " malformed skipped; lazy, "
    .. "cached across rebuilds, recollected on language change; live control wins; raising provider isolated)")
