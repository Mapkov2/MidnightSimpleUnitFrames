-- Source inventory reader shared by tests that inspect the serialized columns.
local R = {}
local CONTEXT_COLUMNS = { 1, 2, 3, 6, 7, 9, 10, 11 }
function R.Load(root, relative)
    local ns = { MSUF2 = { Search = {} } }
    assert(loadfile(root .. "/" .. relative))("Options", ns)
    local data = ns.MSUF2.Search
    local context, rows = {}, {}
    for value in (data.StaticIndexContextBlob or ""):gmatch("[^\n]+") do context[#context + 1] = value end
    for line in data.StaticIndexBlob:gmatch("[^\n]+") do
        local columns = {}
        for value in (line .. "\t"):gmatch("(.-)\t") do columns[#columns + 1] = value end
        assert(#columns == 12, "search row must have twelve fields")
        if data.StaticIndexContextBlob then
            for _, column in ipairs(CONTEXT_COLUMNS) do
                if columns[column] ~= "" then
                    local id = tonumber(columns[column]:match("^@(%d+)$"))
                    columns[column] = assert(id and context[id], "invalid search context reference")
                end
            end
            local prefix, suffix = columns[8]:match("^@(%d+):(.*)$")
            columns[8] = assert(prefix and context[tonumber(prefix)], "invalid search identity prefix") .. suffix
            local encoded, metadata = columns[12]:match("^@([%d,]+)|(.*)$")
            assert(encoded and encoded:sub(1, 1) ~= "," and encoded:sub(-1) ~= ","
                and not encoded:find(",,", 1, true), "invalid search identity reference")
            local words = {}
            for token in encoded:gmatch("%d+") do
                words[#words + 1] = assert(context[tonumber(token)], "invalid search text token")
            end
            columns[12] = table.concat(words, " ") .. "|" .. metadata
        end
        rows[#rows + 1] = columns
    end
    local lines = {}
    for i, row in ipairs(rows) do lines[i] = table.concat(row, "\t") end
    return rows, "\n" .. table.concat(lines, "\n") .. "\n", data
end
return R
