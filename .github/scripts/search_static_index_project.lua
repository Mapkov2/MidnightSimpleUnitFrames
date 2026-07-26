-- Generates the compact, pre-normalized Menu2 search index that ships with the core
-- addon (Shell/Menu2/Search/MSUF_Menu2_Search_StaticIndex_Data.lua).
--
-- Why this exists: search records were only ever created by RegisterSearchWidget while
-- a page was being built, so a setting on a page the player never opened could not be
-- found at all. Baking the inventory gives complete coverage without constructing a
-- single frame and without normalizing any text at runtime.
--
-- Two sources are merged, because neither is complete on its own:
--   1. RuntimeControlCatalog after the real crosswalk harness builds every page. This
--      is the only source that contains the lazily-built unit-page sections.
--   2. The committed Assistant control schema, which additionally covers the finite
--      Aura workspace state matrix and every class/spec context. The crosswalk runs
--      in a single context and cannot see those.
--
-- Determinism: rows are sorted by their encoded identity, so regenerating without a
-- content change produces a byte-identical file and -Check can gate drift.
--
--   lua .github/scripts/search_static_index_project.lua            -> writes the generated file
--   lua .github/scripts/search_static_index_project.lua --stdout   -> prints it instead
_G = _G or _ENV
loadstring = loadstring or load
unpack = unpack or table.unpack

local OUTPUT_PATH = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_StaticIndex_Data.lua"
local SCHEMA_PATH = "MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantControlSchema_Data.lua"
local HARNESS_PATH = "tools/assistant_v1_catalog_crosswalk.lua"
-- The crosswalk continues into Graphify-backed release gates that need an ignored
-- local build artifact. Everything this generator needs is already in place by then.
local HARNESS_CUT = "\nlocal function HasExecutableSettingContract"

-- Only these classifications are things a player can change or run. "ephemeral" and
-- "navigation" controls are menu plumbing and stay out of the index.
local INDEXED_CLASSIFICATIONS = { setting = true, action = true }

-- Path segments that carry no search meaning and only make hints noisy.
local HINT_NOISE = {
    ["unit-workspace"] = true, ["group-workspace"] = true, ["workspace"] = true,
    ["lane"] = true, ["root"] = true, ["page"] = true, ["section"] = true,
}

local function Fail(message)
    io.stderr:write("search_static_index_project: " .. tostring(message) .. "\n")
    os.exit(1)
end

local function Read(path)
    local handle, err = io.open(path, "rb")
    if not handle then Fail(path .. ": " .. tostring(err)) end
    local text = handle:read("*a") or ""
    handle:close()
    return text
end

local function Titleize(segment)
    segment = tostring(segment or ""):gsub("[-_]", " ")
    return (segment:gsub("(%a)([%w]*)", function(first, rest) return first:upper() .. rest end))
end

-- "auras/unit-workspace/lane/buff/filters/hide-permanent" -> "Buff > Filters"
local function HintFromControlPath(controlPath, pageKey)
    local segments = {}
    for segment in tostring(controlPath or ""):gmatch("[^/]+") do
        segments[#segments + 1] = segment
    end
    -- The last segment is the control itself, and the page is shown separately.
    table.remove(segments)
    local kept = {}
    for i = 1, #segments do
        local segment = segments[i]
        if not HINT_NOISE[segment] and segment ~= pageKey then kept[#kept + 1] = segment end
    end
    while #kept > 2 do table.remove(kept, 1) end
    for i = 1, #kept do kept[i] = Titleize(kept[i]) end
    return table.concat(kept, " > ")
end

local function LoadSchemaRecords()
    local MSUF = { Assistant = {} }
    local chunk, err = loadfile(SCHEMA_PATH)
    if not chunk then Fail(SCHEMA_PATH .. ": " .. tostring(err)) end
    local ok, result = pcall(chunk, "MidnightSimpleUnitFrames_Assistant", MSUF)
    if not ok then Fail(SCHEMA_PATH .. ": " .. tostring(result)) end
    local data = MSUF.Assistant.ControlSchemaData
    if type(data) ~= "table" or type(data.records) ~= "table" or type(data.columns) ~= "table" then
        Fail("control schema data did not expose records/columns")
    end
    local col = {}
    for index, name in ipairs(data.columns) do col[name] = index end
    for _, required in ipairs({ "controlId", "pageKey", "controlPath", "classification", "kind",
        "settingKey", "actionKey", "label" }) do
        if not col[required] then Fail("control schema is missing column " .. required) end
    end
    local out = {}
    for _, record in ipairs(data.records) do
        out[#out + 1] = {
            controlId = record[col.controlId],
            pageKey = record[col.pageKey],
            label = record[col.label],
            kind = record[col.kind],
            settingKey = record[col.settingKey],
            actionKey = record[col.actionKey],
            controlPath = record[col.controlPath],
            classification = record[col.classification],
        }
    end
    return out
end

--- Exact runtime control IDs are the preferred identity: they are the catalog's
--- stable semantic route and survive localization or repeated display labels.
--- Older/unreviewed records retain deterministic fallbacks, ordered from the
--- strongest route metadata to display geometry. The separators are never emitted
--- by catalog IDs/paths and remain inside one TSV field.
local function SearchIdentityComponent(value)
    local text = tostring(value or "")
    text = text:gsub("%%", "%%25")
    text = text:gsub("\031", "%%1F")
    text = text:gsub("%.", "%%2E")
    return text
end

local function CatalogSearchIdentity(kind, pageKey, ...)
    local parts = { kind, SearchIdentityComponent(pageKey) }
    for i = 1, select("#", ...) do
        parts[#parts + 1] = SearchIdentityComponent(select(i, ...))
    end
    return table.concat(parts, "\031")
end

local function SearchRouteIdentity(record, pageKey, labelNorm, kind, hint)
    local controlId = tostring(record.controlId or "")
    if controlId ~= "" then
        return CatalogSearchIdentity("id", pageKey, controlId)
    end
    local controlPath = tostring(record.controlPath or "")
    if controlPath ~= "" then
        return CatalogSearchIdentity("path", pageKey, controlPath)
    end
    local settingKey = tostring(record.settingKey or "")
    if settingKey ~= "" then
        return CatalogSearchIdentity("setting", pageKey, settingKey)
    end
    local actionKey = tostring(record.actionKey or "")
    if actionKey ~= "" then
        return CatalogSearchIdentity("action", pageKey, actionKey, labelNorm, hint)
    end
    return CatalogSearchIdentity("display", pageKey, kind, labelNorm, hint)
end

--- Called from inside the crosswalk harness, where every page has been built with the
--- real product builders and the real search text utilities are loaded.
local function Emit(M, Catalog)
    local Normalize = M.Search and M.Search.Text and M.Search.Text.NormalizeSearchText
    if type(Normalize) ~= "function" then Fail("NormalizeSearchText did not load") end

    local sources = {}
    for _, record in ipairs(Catalog.GetRecords()) do sources[#sources + 1] = record end
    for _, record in ipairs(LoadSchemaRecords()) do sources[#sources + 1] = record end

    local rows, seen = {}, {}
    for _, record in ipairs(sources) do
        if INDEXED_CLASSIFICATIONS[tostring(record.classification or "")] then
            local pageKey = tostring(record.pageKey or "")
            local label = tostring(record.label or "")
            if pageKey ~= "" and pageKey ~= "search" and label ~= "" then
                local controlPath = tostring(record.controlPath or "")
                local settingKey = tostring(record.settingKey or "")
                local actionKey = tostring(record.actionKey or "")
                local kind = tostring(record.kind or "control")
                local hint = HintFromControlPath(controlPath, pageKey)
                local labelNorm = Normalize(label)
                if labelNorm ~= "" then
                    local identity = SearchRouteIdentity(record, pageKey, labelNorm, kind, hint)
                    if not seen[identity] then
                        seen[identity] = true
                        rows[#rows + 1] = {
                            pageKey, label, kind, settingKey, actionKey, hint, labelNorm, identity,
                            Normalize(table.concat({
                                label, hint, controlPath, pageKey, kind, settingKey, actionKey,
                            }, " ")),
                        }
                    end
                end
            end
        end
    end

    table.sort(rows, function(a, b)
        for i = 1, 8 do
            if a[i] ~= b[i] then return a[i] < b[i] end
        end
        return false
    end)

    local lines = {}
    for index = 1, #rows do
        local row = rows[index]
        for field = 1, #row do
            if row[field]:find("[\t\n\r]") then
                Fail("field " .. field .. " of '" .. row[2] .. "' contains a separator character")
            end
        end
        lines[index] = table.concat(row, "\t")
    end
    local blob = table.concat(lines, "\n")
    if blob:find("]==]", 1, true) then Fail("blob would terminate its own long string") end

    local text = table.concat({
        "-- Generated by .github/scripts/search_static_index_project.lua. Do not edit by hand.\n",
        "--\n",
        "-- Complete Menu2 control inventory for search. One string constant, so login\n",
        "-- pays only the parse of a literal; it is split into records the first time a\n",
        "-- player actually uses search (see MSUF_Menu2_Search_StaticIndex.lua).\n",
        "-- Columns: pageKey, label, kind, settingKey, actionKey, hint, labelNorm, searchIdentity, haystack\n",
        "local _, MSUF = ...\n",
        "MSUF = MSUF or _G.MSUF_NS or {}\n",
        "local M = MSUF.MSUF2 or {}\n",
        "MSUF.MSUF2 = M\n",
        "local Search = M.Search or {}\n",
        "M.Search = Search\n",
        "Search.StaticIndexRecordCount = " .. tostring(#rows) .. "\n",
        "Search.StaticIndexBlob = [==[\n",
        blob,
        "\n]==]\n",
    })

    local toStdout = false
    for i = 1, #(arg or {}) do
        if arg[i] == "--stdout" then toStdout = true end
    end
    if toStdout then
        io.write(text)
        return
    end
    local handle, err = io.open(OUTPUT_PATH, "wb")
    if not handle then Fail(OUTPUT_PATH .. ": " .. tostring(err)) end
    handle:write(text)
    handle:close()
    io.stderr:write(string.format("search static index: %d records, %.0f KB -> %s\n",
        #rows, #text / 1024, OUTPUT_PATH))
end

_G.__MSUF_EmitSearchStaticIndex = Emit

local harness = Read(HARNESS_PATH)
local cut = harness:find(HARNESS_CUT, 1, true)
if not cut then Fail(HARNESS_PATH .. ": bootstrap boundary marker moved") end
local chunk, err = loadstring(
    harness:sub(1, cut) .. "\n__MSUF_EmitSearchStaticIndex(M, Catalog)\n", "@" .. HARNESS_PATH)
if not chunk then Fail(HARNESS_PATH .. ": " .. tostring(err)) end
local ok, result = pcall(chunk)
if not ok then Fail("harness failed: " .. tostring(result)) end
