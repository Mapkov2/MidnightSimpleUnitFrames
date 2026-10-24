-- V3 inherited-default presence masks and reversible codec operations.
local _, MSUF = ...
local Parts = MSUF.DefaultsSchemaParts
local sparseV3Fields = Parts.sparseV3Fields
local sparseV3Owners = Parts.sparseV3Owners
local sparseV3Runs = Parts.sparseV3Runs
local sparseV2Bits
local sparseV2Symbols
-- Additional typed defaults with exact presence and reusable logout scratch.
local sparseV3 = {}
do
    local marker = "_msufSparseDefaultsV3"
    local before, tables, nibbles, pieces = {}, {}, {}, {}
    local absent, size = {}, 0
    for i, spec in ipairs(sparseV3Owners) do
        spec.fields = {}
        for _, run in ipairs(spec.runs) do
            for _, id in ipairs(sparseV3Runs[run]) do spec.fields[#spec.fields + 1] = id end
        end
        spec.offset = size
        tables[i] = false
        for j, id in ipairs(spec.fields) do
            local field = sparseV3Fields[id]
            before[size + j] = false
            field.bytes = #tostring(field[1]) + (type(field[2]) == "table" and 2 or #tostring(field[2])) + 4
        end
        size = size + #spec.fields
    end
    local maskSize = math.ceil(size / 4)
    for i = 1, maskSize do nibbles[i], pieces[i] = 0, "" end
    local function Bit(slot)
        local bit = sparseV2Bits[(slot - 1) % 4 + 1]
        return math.floor(nibbles[math.floor((slot - 1) / 4) + 1] / bit) % 2 == 1
    end
    function sparseV3.Resolve(profile, refs, lists)
        for i, spec in ipairs(sparseV3Owners) do
            local node = profile
            for depth = 1, #spec.path + 1 do
                if type(node) ~= "table" or (lists[node] and not spec.lists[depth]) then
                    node = nil
                    break
                end
                if refs[node] ~= 1 then return false end
                if depth <= #spec.path then node = node[spec.path[depth]] end
            end
            if node then
                for _, id in ipairs(spec.fields) do
                    local field = sparseV3Fields[id]
                    local value = node[field[1]]
                    if type(field[2]) == "table" and type(value) == "table" and refs[value] ~= 1 then return false end
                end
            end
            tables[i] = node or false
        end
        return true
    end
    function sparseV3.Release(rollback)
        for i, spec in ipairs(sparseV3Owners) do
            local owner = tables[i]
            for j, id in ipairs(spec.fields) do
                local field = sparseV3Fields[id]
                local slot = spec.offset + j
                local value = before[slot]
                if rollback and owner then
                    if value == absent then owner[field[1]] = nil else owner[field[1]] = value end
                end
                before[slot] = false
            end
            tables[i] = false
        end
    end
    function sparseV3.Capture()
        local count, bytes = 0, 0
        for i = 1, maskSize do nibbles[i] = 0 end
        for i, spec in ipairs(sparseV3Owners) do
            local owner = tables[i]
            for j, id in ipairs(spec.fields) do
                local field = sparseV3Fields[id]
                local slot, value = spec.offset + j
                if owner then value = owner[field[1]] end
                if value == nil then before[slot] = absent else before[slot] = value end
                if value == field[2] or (type(field[2]) == "table" and type(value) == "table" and next(value) == nil) then
                    local index = math.floor((slot - 1) / 4) + 1
                    nibbles[index] = nibbles[index] + sparseV2Bits[(slot - 1) % 4 + 1]
                    count = count + 1
                    bytes = bytes + field.bytes
                end
            end
        end
        return count, bytes
    end
    function sparseV3.Mask()
        for i = 1, maskSize do pieces[i] = sparseV2Symbols[nibbles[i]] end
        return table.concat(pieces)
    end
    function sparseV3.Validate(profile)
        local mask = profile[marker]
        if mask == nil then return true end
        if type(mask) ~= "string" or #mask ~= maskSize then return false end
        local nonzero = false
        for i = 1, maskSize do
            local byte, value = mask:byte(i)
            if byte >= 48 and byte <= 57 then value = byte - 48
            elseif byte >= 97 and byte <= 102 then value = byte - 87
            else return false end
            nibbles[i] = value
            if value ~= 0 then nonzero = true end
        end
        local tail = size % 4
        if not nonzero or (tail ~= 0 and nibbles[maskSize] >= 2 ^ tail) then return false end
        for i, spec in ipairs(sparseV3Owners) do
            if not tables[i] then
                for j = 1, #spec.fields do if Bit(spec.offset + j) then return false end end
            end
        end
        return true
    end
    function sparseV3.Apply(restore, prepared)
        local count = 0
        for i, spec in ipairs(sparseV3Owners) do
            local owner = tables[i]
            if owner then
                for j, id in ipairs(spec.fields) do
                    local field = sparseV3Fields[id]
                    if Bit(spec.offset + j) then
                        local key, default = field[1], field[2]
                        if restore then
                            if owner[key] == nil then
                                if type(default) ~= "table" then owner[key] = default
                                elseif prepared then owner[key] = before[spec.offset + j]
                                else owner[key] = {} end
                            end
                        elseif owner[key] == default or (type(default) == "table" and type(owner[key]) == "table"
                            and next(owner[key]) == nil) then
                            owner[key] = nil
                            count = count + 1
                        end
                    end
                end
            end
        end
        return count
    end
    function sparseV3.Same()
        for i, spec in ipairs(sparseV3Owners) do
            local owner = tables[i]
            for j, id in ipairs(spec.fields) do
                local field = sparseV3Fields[id]
                local original, value = before[spec.offset + j]
                if original == absent then original = nil end
                if owner then value = owner[field[1]] end
                if type(value) ~= type(original) or value ~= original then return false end
            end
        end
        return true
    end
    sparseV3.Marker, sparseV3.Overhead = marker, maskSize + #marker + 8
end


Parts.sparseV3 = sparseV3
function Parts.Bind2()
    sparseV2Bits = Parts.sparseV2Bits
    sparseV2Symbols = Parts.sparseV2Symbols
end
