-- Search must do literally nothing while the player is in combat.
--
-- The query itself was already gated, but the paths around it were not: reading the
-- record set drained deferred UI sections and rebuilt/decoded the index, and the
-- results-page refresh invalidated and rebuilt the search page. This smoke pins the
-- gates, and deliberately repeats every check out of combat so a permanently broken
-- gate cannot pass by returning nothing all the time.
local repoRoot = ...
repoRoot = tostring(repoRoot or "."):gsub("[/\\]+$", "")

local SEARCH_DIR = repoRoot .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/"

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
    -- The production catalog returns the same stable explicit ID declared by
    -- the widget. This narrow stub is enough to exercise live/static coverage.
    RegisterRuntimeControl = function(_, meta) return meta and meta.controlId end,
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

-- A partially built page may register one of many equally labelled controls.
-- Only that exact route may replace its static row; the remaining Size/X Offset
-- controls must stay searchable until their own widgets exist.
local function StaticSetting(settingKey)
    for _, rec in ipairs(StaticIndex.GetRecords()) do
        if rec.exactTarget and rec.exactTarget.settingKey == settingKey then return rec end
    end
end

local function ControlId(rec)
    local prefix = "id\031" .. tostring(rec.key) .. "\031"
    assert(type(rec.searchIdentity) == "string"
        and rec.searchIdentity:sub(1, #prefix) == prefix,
        "static control lost its stable catalog identity")
    return rec.searchIdentity:sub(#prefix + 1)
        :gsub("%%2E", ".")
        :gsub("%%1F", "\031")
        :gsub("%%25", "%%")
end

local sizeStatic = assert(StaticSetting("target.nameFontSize"),
    "target name Size route missing from static index")
local offsetStatic = assert(StaticSetting("target.nameOffsetX"),
    "target name X Offset route missing from static index")
local sizeWidget, offsetWidget = {}, {}
local expectedSizeRoutes, expectedOffsetRoutes = 0, 0
for _, rec in ipairs(StaticIndex.GetRecords()) do
    if rec.key == "uf_target" and rec.labelNorm == "size" then
        expectedSizeRoutes = expectedSizeRoutes + 1
    elseif rec.key == "uf_target" and rec.labelNorm == "x offset" then
        expectedOffsetRoutes = expectedOffsetRoutes + 1
    end
end
assert(expectedSizeRoutes > 2 and expectedOffsetRoutes > 2,
    "fixture no longer contains multiple target Size/X Offset routes")
M.RegisterSearchWidget(sizeWidget, {
    pageKey = "uf_target", label = "Size", kind = "slider",
    controlId = ControlId(sizeStatic), settingKey = "target.nameFontSize",
    controlPath = "unit-workspace/unit/portrait/text/name/size",
    classification = "setting",
})
M.RegisterSearchWidget(offsetWidget, {
    pageKey = "uf_target", label = "X Offset", kind = "slider",
    controlId = ControlId(offsetStatic), settingKey = "target.nameOffsetX",
    controlPath = "unit-workspace/unit/portrait/text/name/x-offset",
    classification = "setting",
})

local function HasResult(results, predicate)
    for i = 1, #results do
        if predicate(results[i]) then return true end
    end
    return false
end

local auraSize = SearchPages("target buff layout size")
assert(HasResult(auraSize, function(rec)
    return rec.key == "uf_target" and rec.static == true
        and rec.labelNorm == "size" and tostring(rec.hintNorm):find("buff", 1, true)
end), "registering target Name Size hid the distinct target Buff Size route")

local powerOffset = SearchPages("target power position x offset")
assert(HasResult(powerOffset, function(rec)
    return rec.static == true and rec.exactTarget
        and rec.exactTarget.settingKey == "target.powerOffsetX"
end), "registering target Name X Offset hid the distinct target Power X Offset route")

local merged = assert(API.GetSearchRecords, "GetSearchRecords test hook missing")()
local sizeRoutes, offsetRoutes, liveSizeRoute, liveOffsetRoute = 0, 0, false, false
for _, rec in ipairs(merged) do
    if rec.key == "uf_target" and rec.labelNorm == "size" then
        sizeRoutes = sizeRoutes + 1
        if rec.searchIdentity == sizeStatic.searchIdentity and rec.static ~= true then liveSizeRoute = true end
        assert(not (rec.static == true and rec.searchIdentity == sizeStatic.searchIdentity),
            "the static Name Size route survived beside its exact live replacement")
    elseif rec.key == "uf_target" and rec.labelNorm == "x offset" then
        offsetRoutes = offsetRoutes + 1
        if rec.searchIdentity == offsetStatic.searchIdentity and rec.static ~= true then liveOffsetRoute = true end
        assert(not (rec.static == true and rec.searchIdentity == offsetStatic.searchIdentity),
            "the static Name X Offset route survived beside its exact live replacement")
    end
end
assert(sizeRoutes == expectedSizeRoutes and offsetRoutes == expectedOffsetRoutes,
    string.format("partial page changed route counts: Size %d/%d, X Offset %d/%d",
        sizeRoutes, expectedSizeRoutes, offsetRoutes, expectedOffsetRoutes))
assert(liveSizeRoute and liveOffsetRoute,
    "the exact live Size/X Offset routes did not replace their static records")

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
