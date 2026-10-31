-- Isolated Lua 5.1 decoder probe: full GC before load and after decode; no fuzzy/UI.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local measure = arg[3] == "--measure"
local M = { Search = {}, pages = {}, navItems = {}, Tr = function(s) return s end }
local ns = { MSUF2 = M, Translate = function(s) return s end }
local locale = arg[4] or "enUS"
if locale ~= "enUS" then
    local translations = {}
    ns.RegisterLocale = function() return translations end
    ns.RegisterLocaleLoader = function(_, load) load() end
    _G.MSUF_NS = ns
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Locales/" .. locale .. ".lua"))()
    M.Tr = function(s) return translations[s] or s end
    ns.Translate = M.Tr
end
M.Search.Text = { NormalizeSearchText = function(s) return s:lower():gsub("%s+", " ") end,
    SearchEffectiveLocale = function() return locale end }
function InCombatLockdown() return false end
function UnitAffectingCombat() return false end
function debugprofilestop() return os.clock() * 1000 end
local base = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/"
collectgarbage("collect")
local before = collectgarbage("count")
local suffix = flavor == "Mainline" and "" or "_Classic"
assert(loadfile(base .. "MSUF_Menu2_Search_StaticIndex_Data" .. suffix .. ".lua"))("Options", ns)
assert(loadfile(base .. "MSUF_Menu2_Search_StaticIndex.lua"))("Options", ns)
collectgarbage("collect")
local loaded = collectgarbage("count")
local index = M.Search.StaticIndex
if not measure then
    local resolve = M.Search.ResolveExactPreparation
    local k, v, setting = resolve("scope=party=foo|scope=raid=bar", "foo")
    assert(k == "scope" and v == "party" and setting == "foo", "exact preparation changed")
    k, v, setting = resolve("scope=all=*|view=a=foo|view=b=bar", nil)
    assert(k == "scope" and v == "all" and setting == nil, "ambiguous wildcard alias changed")
    k, v = resolve("scope=a=*|scope=b=*", nil)
    assert(k == nil and v == nil, "ambiguous preparation guessed a view")
    k, v, setting = resolve({ scope = { party = false, raid = true } }, "foo")
    assert(k == "scope" and v == "raid" and setting == nil, "boolean preparation changed")
end
-- os.clock() is wall time on Windows (MSVC clock), so one OS preemption can
-- inflate a single slice. A slow slice is re-measured on a fresh decode up to
-- twice; the 4 ms budget below is unchanged and applies to the best attempt.
local function MeasureDecode()
    local start, slices, maximum = debugprofilestop(), 0, 0
    repeat
        local at = debugprofilestop()
        local done = index.Advance(at + 2)
        maximum = math.max(maximum, debugprofilestop() - at)
        slices = slices + 1
        if done then break end
        assert(slices < 10000, "decode never completed")
    until false
    return debugprofilestop() - start, slices, maximum
end
local elapsed, slices, maximum = MeasureDecode()
for _ = 1, 2 do
    if measure or maximum < 4 then break end
    index.ClearCache()
    collectgarbage("collect")
    elapsed, slices, maximum = MeasureDecode()
end
collectgarbage("collect")
local resident = collectgarbage("count") - before
local count = #index.GetRecords()
local first = index.GetRecords()[1]
assert(count == M.Search.StaticIndexRecordCount and first.label and first.haystack, "lost static rows")
assert(first.controlId == nil and first.settingKey == nil, "target fields leaked onto public search rows")
local function ValidateControlIds()
    for _, row in ipairs(index.GetRecords()) do
        local encoded = row.searchIdentity:match("^id\031[^\031]+\031([^\031]+)$")
        local expected = encoded and encoded:gsub("%%(%x%x)", function(pair) return string.char(tonumber(pair, 16)) end)
        assert(index.TargetField(row, "controlId") == expected, "lazy ID validation changed an indexed control")
    end
end
if not measure then ValidateControlIds() end
first = nil
index.ClearCache()
collectgarbage("collect")
local closed = collectgarbage("count") - before
print(string.format("static %s: rows=%d loaded=%.3f MiB decoded=%.3f MiB closed=%.3f MiB decode=%.2f ms slices=%d max=%.3f ms",
    flavor .. "/" .. locale, count, (loaded-before)/1024, resident/1024, closed/1024, elapsed, slices, maximum))
if not measure then
    assert(index.HEAP_BUDGET_KIB and resident <= index.HEAP_BUDGET_KIB, "static heap budget exceeded")
    assert(not index.IsDecoded() and #index.GetRecords() == 0, "close retained decoded rows")
    assert(maximum < 4, "static decode exceeded 4 ms")
    local at = debugprofilestop()
    assert(index.Advance() == false, "bare Advance synchronously decoded everything")
    assert(debugprofilestop() - at < 4, "bare Advance exceeded its frame budget")
    assert(index.Advance(debugprofilestop() + 0.01) == false, "reopen synchronously decoded everything")
    while not index.Advance(debugprofilestop() + 2) do end
    assert(#index.GetRecords() == count, "closed index did not rebuild")
end
