-- One live graph: translated index, warmed fuzzy records and every built page coexist.
local root, flavor, locale = assert(arg[1]), arg[2] or "Mainline", arg[3] or "enUS"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local baseline
local mw = MenuWorld.Open(root, flavor, { locale = locale, beforeOptions = function()
    collectgarbage("collect")
    baseline = collectgarbage("count")
end })
local M = mw.M
local function Drain()
    for _ = 1, 50 do
        if #mw.world.widgets.timers == 0 then return end
        mw:RunTimers(1000)
    end
    error("combined heap: menu did not settle")
end
local pages = {}
for key in pairs(M.pages) do pages[#pages + 1] = key end
table.sort(pages)
for _, key in ipairs(pages) do
    assert(mw:Select(key), "combined heap: failed page " .. key)
    local entry = assert(M.cache[key])
    for _ = 1, 3 do
        for _, section in pairs(entry.sections or {}) do
            local disclosure = section._msuf2CollapsibleEntry
            if disclosure then disclosure.SetOpenImmediate(true) end
        end
        Drain()
    end
    assert(not entry._msuf2BuildIncomplete, "combined heap: incomplete page " .. key)
end
collectgarbage("collect")
local built = collectgarbage("count") - baseline
local peak, fuzzyObserved = built, false
-- Observe query completion before Pump releases its monotonically growing
-- distance cache. One collection per query measures live residents without
-- making collection on every slice dominate the release check.
local function Upvalue(fn, wanted)
    for i = 1, 60 do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value, i end
    end
    error("combined heap: missing observation seam " .. wanted)
end
local build = Upvalue(M.Search._CoreAPI.WhenIndexReady, "SearchIndexBuild")
local search, slot = Upvalue(build.Pump, "SearchPages")
-- A local keeps the injected pump alive: Lua 5.1's lua_setupvalue puts its GC
-- write barrier on the closure, not on the upvalue cell, so an otherwise
-- unreferenced replacement can be collected while installed.
local function MeasuredSearchPages(...)
    local result = search(...)
    if result then
        local request = M.Search._RenderContext.SEARCH_STATE.request
        local cache = request and request.job and request.job.fuzzy
        if cache and next(cache) ~= nil then
            fuzzyObserved = true
            collectgarbage("collect")
            peak = math.max(peak, collectgarbage("count") - baseline)
        end
    end
    return result
end
debug.setupvalue(build.Pump, slot, MeasuredSearchPages)
for _, query in ipairs({ "castbar", "cstbr", "helth", "player power", "auras", "thret", "portrait" }) do
    M.Search._CoreAPI.OpenSearchResults(query)
    Drain()
end
local records = assert(M.Search._RenderContext.SEARCH_STATE.records)
local tokens = 0
for _, row in ipairs(records) do if row.tokens and #row.tokens > 0 then tokens = tokens + 1 end end
assert(#pages > 20 and #records > 3000 and tokens > 3000, "combined heap did not warm pages/index/fuzzy together")
local recordCount = #records
assert(M.Search.StaticIndex.IsDecoded(), "combined heap did not retain decoded index")
collectgarbage("collect")
local combined = math.max(peak, collectgarbage("count") - baseline)
assert(fuzzyObserved, "combined heap never observed active fuzzy-distance caches")
-- Offline widget tables are retained like native WoW frames, whose GPU/native
-- bytes are outside this Lua heap model. Fixed KiB ceilings cover both families.
-- Measured 2026-10-24, HEAD 03146e6c7 plus concurrent H lanes, enUS/deDE:
-- Mainline peak 269972 / closed 251216 KiB; Vanilla 189727 / 176404 KiB.
-- Fixed family budgets allow about 8-11% growth, rather than a relative limit
-- that would silently grow along with the implementation under test.
local budgets = { Mainline = { 288 * 1024, 272 * 1024 }, Vanilla = { 200 * 1024, 188 * 1024 } }
local family = assert(budgets[flavor], "combined heap: unsupported index family")
local OPEN_KIB, CLOSED_KIB = family[1], family[2]
records = nil
debug.setupvalue(build.Pump, slot, search)
M.HideSlashMenuAndMinibar(M.frame)
Drain()
collectgarbage("collect")
local closed = collectgarbage("count") - baseline
assert(not M.Search.StaticIndex.IsDecoded() and M.Search._RenderContext.SEARCH_STATE.records == nil,
    "combined heap: close retained index or fuzzy records")
print(string.format("combined heap %s/%s: %d pages, %d records, %d tokenized; built=%.1f combined=%.1f/%d closed=%.1f/%d KiB",
    flavor, locale, #pages, recordCount, tokens, built, combined, OPEN_KIB, closed, CLOSED_KIB))
assert(combined <= OPEN_KIB, "combined search/page heap budget exceeded: " .. combined)
assert(closed <= CLOSED_KIB, "closed page heap budget exceeded: " .. closed)
print("PASS combined search/page budgets " .. flavor .. "/" .. locale)
