-- Every decoded field must remain identical to the legacy inline encoding.
local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local Rows = assert(loadfile(root .. "/tools/tests/search_static_rows.lua"))()
local suffix = flavor == "Mainline" and "" or "_Classic"
local base = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/"
local _, inline, data = Rows.Load(root, base .. "MSUF_Menu2_Search_StaticIndex_Data" .. suffix .. ".lua")
assert(data.StaticIndexContextBlob, "context dictionary missing")
local M = { Search = data, pages = {}, navItems = {}, Tr = function(s) return s end }
local ns = { MSUF2 = M, Translate = function(s) return s end }
M.Search.Text = { NormalizeSearchText = function(s) return s:lower():gsub("%s+", " ") end,
    SearchEffectiveLocale = function() return "enUS" end }
function InCombatLockdown() return false end
function UnitAffectingCombat() return false end
function debugprofilestop() return os.clock() * 1000 end
local function Decode()
    M.Search.StaticIndex = nil
    assert(loadfile(root .. "/" .. base .. "MSUF_Menu2_Search_StaticIndex.lua"))("Options", ns)
    local index = M.Search.StaticIndex
    while not index.Advance(debugprofilestop() + 2) do end
    return index
end
local fields = { "key", "label", "kind", "hint", "labelNorm", "hintNorm", "haystack", "searchIdentity",
    "settingKey", "actionKey", "sectionId", "prepareKinds", "prepareContracts", "prepareKind", "prepareValue", "controlId" }
local function Signature(index, row)
    local values = {}
    for i, field in ipairs(fields) do
        values[i] = tostring(row[field] or index.TargetField(row, field) or "")
    end
    return table.concat(values, "\031")
end
local first, expected = Decode(), {}
for i, row in ipairs(first.GetRecords()) do expected[i] = Signature(first, row) end
local encoded, dictionary = data.StaticIndexBlob, data.StaticIndexContextBlob
data.StaticIndexBlob, data.StaticIndexContextBlob = inline, nil
local second = Decode()
assert(#second.GetRecords() == #expected, "context encoding changed row count")
for i, row in ipairs(second.GetRecords()) do assert(Signature(second, row) == expected[i], "context roundtrip changed row " .. i) end
for _, bad in ipairs({ "@0", "@999999", "@broken" }) do
    data.StaticIndexContextBlob = dictionary
    data.StaticIndexBlob = encoded:gsub("[^\t]+", bad, 1)
    assert(not pcall(Decode), "invalid context reference accepted: " .. bad)
end
local firstLine, tail = encoded:match("^([^\n]+)(.*)$")
for _, mutation in ipairs({ { 8, "@0:broken" }, { 8, "@bad:broken" }, { 12, "@0|@1" }, { 12, "@1,,2|@1" } }) do
    local columns = {}
    for value in (firstLine .. "\t"):gmatch("(.-)\t") do columns[#columns + 1] = value end
    columns[mutation[1]] = mutation[2]
    data.StaticIndexBlob = table.concat(columns, "\t") .. tail
    assert(not pcall(Decode), "invalid identity/text reference accepted")
end
print("search_static_context_smoke " .. flavor .. ": " .. #expected .. " rows preserve every field; invalid references rejected")
