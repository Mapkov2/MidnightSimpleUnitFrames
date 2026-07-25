-- Contract for the baked Menu2 search index.
--
-- Search records used to exist only for pages the player had already opened, so a
-- setting on an unvisited page was unreachable. The generated static index closes
-- that gap without building any page. This smoke pins the parts that would fail
-- silently: a stale or malformed blob still loads, it just stops matching.
local repoRoot = ...
repoRoot = tostring(repoRoot or "."):gsub("[/\\]+$", "")

local function Read(relative)
    local path = repoRoot .. "/" .. relative
    local handle = assert(io.open(path, "rb"), "missing file: " .. path)
    local text = handle:read("*a") or ""
    handle:close()
    -- The editor saves CRLF; every pattern below is written against LF.
    return (text:gsub("\r\n", "\n"))
end

local SEARCH_DIR = "MidnightSimpleUnitFrames/Shell/Menu2/Search/"

local MSUF = { MSUF2 = {} }
local M = MSUF.MSUF2

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
M.Pick = function(source, names) return PickValues(source, names) end
M.PickDefaults = function(source, names) return PickValues(source, names, true) end
M.KeySetFromWords = function(text)
    local out = {}
    for key in tostring(text or ""):gmatch("%S+") do out[key] = true end
    return out
end
M.Tr = function(text) return text end

local function LoadSearchFile(name)
    local path = repoRoot .. "/" .. SEARCH_DIR .. name
    local chunk, err = loadfile(path)
    assert(chunk, path .. ": " .. tostring(err))
    local ok, result = pcall(chunk, "MidnightSimpleUnitFrames", MSUF)
    assert(ok, path .. ": " .. tostring(result))
end

for _, file in ipairs({
    "MSUF_Menu2_Search_Data.lua",
    "MSUF_Menu2_Search_Text.lua",
    "MSUF_Menu2_Search_StaticIndex_Data.lua",
    "MSUF_Menu2_Search_StaticIndex.lua",
}) do
    LoadSearchFile(file)
end

local Search = assert(M.Search, "search namespace missing")
local Normalize = assert(Search.Text and Search.Text.NormalizeSearchText,
    "NormalizeSearchText missing")
local blob = Search.StaticIndexBlob
assert(type(blob) == "string" and blob ~= "", "static index blob is missing or empty")

-- A regression that empties the generated file must fail here, not degrade search
-- back to visited-pages-only coverage.
local MINIMUM_RECORDS = 2000
local declared = tonumber(Search.StaticIndexRecordCount)
assert(declared and declared >= MINIMUM_RECORDS, string.format(
    "static index declares %s records; expected at least %d",
    tostring(Search.StaticIndexRecordCount), MINIMUM_RECORDS))

local lines, pages = 0, {}
for line in blob:gmatch("[^\n]+") do
    lines = lines + 1
    local fields = {}
    for field in (line .. "\t"):gmatch("([^\t]*)\t") do fields[#fields + 1] = field end
    assert(#fields == 8, string.format(
        "row %d has %d fields, expected 8: %s", lines, #fields, line:sub(1, 90)))
    local pageKey, label, kind, _, _, _, labelNorm, haystack = unpack(fields)
    assert(pageKey ~= "", "row " .. lines .. " has no page key")
    assert(pageKey ~= "search", "row " .. lines .. " indexes the search page itself")
    assert(label ~= "", "row " .. lines .. " has no label")
    assert(kind ~= "", "row " .. lines .. " has no control kind")
    -- Baked normalization has to match the runtime normalizer exactly, or the
    -- terms a query produces can never match the terms in the blob.
    assert(labelNorm == Normalize(label), string.format(
        "row %d label normalization drifted: baked '%s' vs runtime '%s'",
        lines, labelNorm, Normalize(label)))
    assert(haystack ~= "" and haystack == Normalize(haystack), string.format(
        "row %d haystack is not normalized: %s", lines, haystack:sub(1, 60)))
    pages[pageKey] = true
end
assert(lines == declared, string.format(
    "static index declares %d records but the blob holds %d rows", declared, lines))

-- Coverage is only real if the index spans the whole menu, not one lucky page.
local pageCount = 0
for _ in pairs(pages) do pageCount = pageCount + 1 end
assert(pageCount >= 20, "static index only covers " .. pageCount .. " pages")
for _, required in ipairs({
    "uf_player", "uf_target", "uf_focus", "uf_boss", "uf_pet",
    "gf_layout", "gf_auras", "opt_bars", "opt_castbar", "opt_colors",
    "opt_fonts", "classpower", "gameplay", "auras3_styling", "home",
}) do
    assert(pages[required], "static index has no rows for page " .. required)
end

local StaticIndex = assert(Search.StaticIndex, "static index runtime module missing")
local records = StaticIndex.GetRecords()
assert(#records == declared, string.format(
    "decode produced %d records, expected %d", #records, declared))
assert(Search.StaticIndexBlob == nil,
    "decoded blob was not released; it would stay resident for the whole session")
assert(StaticIndex.GetRecords() == records, "decode is not cached")

local sample = records[1]
for _, field in ipairs({ "key", "label", "kind", "labelNorm", "haystack", "hintNorm",
    "titleNorm", "groupNorm", "tokenLimit" }) do
    assert(sample[field] ~= nil, "decoded record is missing field " .. field)
end

-- Load order: the data file has to be bound before the decoder, and both before the
-- index that consumes them.
local xml = Read(SEARCH_DIR .. "MSUF_Menu2_Search.xml")
local dataAt = assert(xml:find("MSUF_Menu2_Search_StaticIndex_Data.lua", 1, true),
    "static index data file is not loaded by the search XML")
local moduleAt = assert(xml:find('"MSUF_Menu2_Search_StaticIndex.lua"', 1, true),
    "static index module is not loaded by the search XML")
local indexAt = assert(xml:find("MSUF_Menu2_Search_IndexQuery.lua", 1, true),
    "search index file missing from the search XML")
assert(dataAt < moduleAt and moduleAt < indexAt,
    "static index files are not loaded before the search index")

local indexQuery = Read(SEARCH_DIR .. "MSUF_Menu2_Search_IndexQuery.lua")
assert(indexQuery:find("AddStaticIndexSearchRecords(records, covered)", 1, true),
    "the search index no longer merges the static records")
assert(indexQuery:find('covered[tostring(rec.key or "") .. "\\031" .. tostring(rec.labelNorm or "")] = true', 1, true),
    "live widget records no longer suppress their static duplicate")
-- The Assistant registry layer normalized ~5k records on every single rebuild and is
-- superseded by the baked index. Reintroducing it silently restores a 1.3s rebuild.
assert(not indexQuery:find("AddAssistantRegistrySearchRecords", 1, true),
    "the uncached Assistant registry index layer is back")

-- A query made only of soft stop words used to collapse to zero clauses, so real
-- control labels like "Enable" and "Visible" returned nothing at all.
assert(indexQuery:find("if #clauses == 0 and normalized ~= \"\" then clauses = Collect(true) end", 1, true),
    "soft stop word queries no longer fall back to a permissive clause pass")

io.write(string.format("menu2_search_static_index_smoke: ok (%d records, %d pages)\n",
    lines, pageCount))
