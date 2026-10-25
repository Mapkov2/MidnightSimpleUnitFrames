-- One-time oracle capture. Input MUST be the historical ce4767d34 archive;
-- never run this against the current addon or regenerate fixtures during checks.
local historical, output = assert(arg[1]), assert(arg[2])
local ns = { Util = { IsSecret = function() return false end } }
for _, name in ipairs({ "Schema", "StorageData", "StorageCommon", "StorageV3", "Storage", "Recovery" }) do
    assert(loadfile(historical .. "/MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_" .. name .. ".lua"))("test", ns)
end
local data, schema = ns.DefaultsStorageData, ns.DefaultsSchema
data.Load()
local function Literal(value)
    if type(value) == "number" then return string.format("%.17g", value) end
    if type(value) == "boolean" then return value and "true" or "false" end
    if type(value) == "string" then return string.format("%q", value) end
    local keys, values = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do values[#values + 1] = "[" .. Literal(key) .. "]=" .. Literal(value[key]) end
    return "{" .. table.concat(values, ",") .. "}"
end
local function Copy(value) return assert(loadstring("return " .. Literal(value)))() end
local function Slots(version)
    local fields = data["sparseV" .. version .. "Fields"]
    local slots, singles = {}, {}
    for _, owner in ipairs(data["sparseV" .. version .. "Owners"]) do
        local ids = owner.fields
        if version == 3 then
            ids = {}
            for _, run in ipairs(owner.runs) do
                for _, id in ipairs(data.sparseV3Runs[run]) do ids[#ids + 1] = id end
            end
        end
        for j, id in ipairs(ids) do
            local path = Copy(owner.path)
            path[#path + 1] = fields[id][1]
            slots[#slots + 1] = { path = path, value = Copy(fields[id][2]) }
            if j == 1 or j == #ids then singles[#singles + 1] = #slots end
        end
    end
    return slots, singles
end
local slots2, single2 = Slots(2)
local slots3, single3 = Slots(3)
local result = { commit = "ce4767d344bdafc01685ef5299bca2e26735539d", cases = {}, bits = { #slots2, #slots3 } }
local function Mask(size, selected)
    local nibbles = {}
    for i = 1, math.ceil(size / 4) do nibbles[i] = 0 end
    for _, slot in ipairs(selected) do
        local index = math.floor((slot - 1) / 4) + 1
        nibbles[index] = nibbles[index] + 2 ^ ((slot - 1) % 4)
    end
    local pieces = {}
    for i, value in ipairs(nibbles) do pieces[i] = ("0123456789abcdef"):sub(value + 1, value + 1) end
    return table.concat(pieces)
end
local function Case(version, selected, id)
    local slots = version == 2 and slots2 or slots3
    local encoded = { _msufDefaultsRevision = 17.5, unknown = { false, 0, "", [12345] = "spell" } }
    local v3Paths = {}
    local function Owner(path)
        local node = encoded
        for j = 1, #path - 1 do
            local key = path[j]
            node[key] = node[key] or {}
            node = node[key]
        end
    end
    for _, slot in ipairs(selected) do
        Owner(slots[slot].path)
        if version == 3 then v3Paths[#v3Paths + 1] = Copy(slots[slot].path) end
    end
    if version == 3 then
        Owner(slots2[1].path)
        encoded._msufSparseDefaultsV2 = Mask(#slots2, { 1 })
        encoded._msufSparseDefaultsV3 = Mask(#slots3, selected)
    else encoded._msufSparseDefaultsV2 = Mask(#slots2, selected) end
    local decoded = Copy(encoded)
    assert(schema.RestorePersistence(decoded), "historical decoder rejected " .. id)
    result.cases[#result.cases + 1] = { id = id, version = version, encoded = encoded, expected = decoded, v3Paths = v3Paths }
end
for version = 2, 3 do
    local slots, singles = version == 2 and slots2 or slots3, version == 2 and single2 or single3
    -- First/last bit of every historical owner; these exercise nibble boundaries,
    -- deep/list owners, false/zero/empty/table values and the tail bit.
    for _, slot in ipairs(singles) do Case(version, { slot }, "V" .. version .. "-single-" .. slot) end
    -- Binary masks give EVERY historical position a unique selection signature.
    -- Unlike residue stripes, this detects swaps between any two interior bits.
    local bit = 0
    while 2 ^ bit <= #slots do
        local selected = {}
        for slot = 1, #slots do
            if math.floor(slot / 2 ^ bit) % 2 == 1 then selected[#selected + 1] = slot end
        end
        Case(version, selected, "V" .. version .. "-mixed-binary-" .. bit)
        bit = bit + 1
    end
end
local file = assert(io.open(output, "wb"))
file:write("-- Frozen encoded profiles and decoded expectations from ce4767d344bdafc01685ef5299bca2e26735539d.\r\nreturn {\r\n")
file:write("commit=", Literal(result.commit), ", bits=", Literal(result.bits), ", cases={\r\n")
for _, case in ipairs(result.cases) do file:write(Literal(case), ",\r\n") end
file:write("}}\r\n")
file:close()
print("Frozen " .. #result.cases .. " cases, " .. #slots2 .. " V2 / " .. #slots3 .. " V3 bits")
