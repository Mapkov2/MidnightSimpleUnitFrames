local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

local Data = M.SearchData or {}
M.SearchData = Data
local unpack = table.unpack or unpack

-- Search FAQ catalogue.
-- Stores compact help rows that expand into searchable records. FAQ answers may route users
-- to pages/anchors but should not execute settings or profile actions.
local providers = Data.FAQProviders or {}
Data.FAQProviders = providers
local FAQ_COMPACT_FIELDS = {
    l = "label",
    a = "answer",
    p = "pageKey",
    t = "target",
    x = "anchorText",
    k = "keywords",
    r = "route",
    y = "priority",
}
local FAQ_ARRAY_FIELDS = M.WordList "label answer pageKey target anchorText keywords priority route"

local function ExpandFAQStringRow(row)
    local out, index = {}, 1
    for value in (tostring(row or "") .. "\t"):gmatch("([^\t]*)\t") do
        local field = FAQ_ARRAY_FIELDS[index]
        if field and value ~= "" then out[field] = value end
        index = index + 1
    end
    if out.priority ~= nil then out.priority = tonumber(out.priority) or out.priority end
    return out
end

function Data.KeywordList(text)
    if type(text) ~= "string" then return text end
    local out = {}
    for keyword in text:gmatch("[^|]+") do out[#out + 1] = keyword end
    return out
end

function Data.RegisterFAQProvider(fn)
    if type(fn) ~= "function" then return false end
    providers[#providers + 1] = fn
    return true
end

function Data.FAQEnv(env, names)
    env = env or {}
    local values, count = {}, 0
    for name in tostring(names or ""):gmatch("%S+") do
        count = count + 1
        local value = env[name]
        if value == nil and name:sub(1, 7) == "SEARCH_" then value = Data[name:sub(8)] end
        values[count] = value
    end
    return unpack(values, 1, count)
end

function Data.ExpandFAQRows(rows)
    if type(rows) ~= "table" then return rows end
    for i = 1, #rows do
        local row = rows[i]
        if type(row) == "string" then
            row = ExpandFAQStringRow(row)
            rows[i] = row
        end
        if type(row) == "table" then
            if row[1] ~= nil then
                for index, full in ipairs(FAQ_ARRAY_FIELDS) do
                    if row[index] ~= false and row[full] == nil then row[full] = row[index] end
                    row[index] = nil
                end
            end
            for compact, full in pairs(FAQ_COMPACT_FIELDS) do
                if row[compact] ~= nil and row[full] == nil then row[full] = row[compact] end
                row[compact] = nil
            end
            if type(row.keywords) == "string" then row.keywords = Data.KeywordList(row.keywords) end
        end
    end
    return rows
end

function Data.FAQRows(...)
    local rows = {}
    for i = 1, select("#", ...) do
        local part = select(i, ...)
        if type(part) == "string" then
            for row in part:gmatch("[^\r\n]+") do
                if row:find("%S") then rows[#rows + 1] = row end
            end
        elseif type(part) == "table" then
            local isList = type(part[1]) == "table" or type(part[1]) == "string"
            if isList then
                for k = 1, #part do rows[#rows + 1] = part[k] end
            else
                rows[#rows + 1] = part
            end
        end
    end
    return Data.ExpandFAQRows(rows)
end

function Data.BuildFAQ(env)
    local out = {}
    for i = 1, #providers do
        local items = providers[i](env or {})
        if type(items) == "table" then
            for k = 1, #items do out[#out + 1] = items[k] end
        end
    end
    return out
end
