-- Decode frozen historical envelopes; never derive bit expectations from today's dictionary.
local root, mutation = assert(arg[1]), arg[2]
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local fixture = assert(loadfile(root .. "/tools/fixtures/sparse-historical/profiles.lua"))()
assert(fixture.commit == "ce4767d344bdafc01685ef5299bca2e26735539d")
assert(fixture.bits[1] == 3595 and fixture.bits[2] == 6622 and #fixture.cases == 606)
-- Verify the frozen masks themselves distinguish all positions, independently
-- of both the current dictionary and the capture generator.
for version = 2, 3 do
    local mixed, signatures = {}, {}
    for _, case in ipairs(fixture.cases) do
        if case.version == version and case.id:find("mixed", 1, true) then mixed[#mixed + 1] = case end
    end
    assert(#mixed == (version == 2 and 12 or 13), "incomplete frozen binary mask set")
    for slot = 1, fixture.bits[version - 1] do
        local signature = {}
        for _, case in ipairs(mixed) do
            local mask = case.encoded["_msufSparseDefaultsV" .. version]
            local nibble = tonumber(mask:sub(math.floor((slot - 1) / 4) + 1, math.floor((slot - 1) / 4) + 1), 16)
            signature[#signature + 1] = tostring(math.floor(nibble / 2 ^ ((slot - 1) % 4)) % 2)
        end
        local key = table.concat(signature)
        assert(key:find("1", 1, true) and not signatures[key], "frozen masks do not distinguish slot " .. slot)
        signatures[key] = true
    end
end
local ns = { Util = { IsSecret = function() return false end } }
for _, name in ipairs({ "Schema", "StorageData", "StorageCommon", "StorageV3", "Storage", "Recovery" }) do
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_" .. name .. ".lua"))("test", ns)
end
local data = ns.DefaultsStorageData
data.Load()
local function Copy(value) return assert(loadstring("return " .. H.Literal(value)))() end
local function Assign(profile, path, value)
    local node = profile
    for i = 1, #path - 1 do node = assert(node[path[i]], "missing frozen owner") end
    node[path[#path]] = type(value) == "table" and Copy(value) or value
end
local function CurrentDefaults()
    -- V3 deliberately inherits changed default VALUES. Only the path->value
    -- lookup is current; every expected bit->path and every V2 value is frozen.
    -- Matching by physical path prevents a reordered wire dictionary from
    -- teaching the expected result the same wrong bit positions.
    local defaults = {}
    for _, owner in ipairs(data.sparseV3Owners) do
        for _, run in ipairs(owner.runs) do
            for _, id in ipairs(data.sparseV3Runs[run]) do
                local field, path = data.sparseV3Fields[id], Copy(owner.path)
                path[#path + 1] = field[1]
                defaults[H.Literal(path)] = field[2]
            end
        end
    end
    return defaults
end
local defaults = CurrentDefaults()
if mutation == "--mutate-v2" then
    data.sparseV2Fields[1], data.sparseV2Fields[2] = data.sparseV2Fields[2], data.sparseV2Fields[1]
elseif mutation == "--mutate-v3" then
    data.sparseV3Fields[1], data.sparseV3Fields[2] = data.sparseV3Fields[2], data.sparseV3Fields[1]
elseif mutation == "--mutate-v2-interior" then
    local fields = data.sparseV2Owners[1].fields
    fields[2], fields[5] = fields[5], fields[2]
elseif mutation == "--mutate-v3-interior" then
    local run = data.sparseV3Runs[1]
    run[2], run[5] = run[5], run[2]
elseif mutation == "--allowed-v3-default" then
    -- An intentional inherited default change must not break the path oracle.
    data.sparseV3Fields[2][2] = 19
    defaults = CurrentDefaults()
end
local singles, mixed = 0, 0
for _, case in ipairs(fixture.cases) do
    local decoded, expected = Copy(case.encoded), Copy(case.expected)
    for _, path in ipairs(case.v3Paths) do
        local value = defaults[H.Literal(path)]
        assert(value ~= nil, case.id .. ": historical V3 path disappeared: " .. H.Literal(path))
        Assign(expected, path, value)
    end
    assert(ns.DefaultsSchema.RestorePersistence(decoded), case.id .. ": historical envelope rejected")
    assert(H.Literal(decoded) == H.Literal(expected), case.id .. ": historical bit meaning changed")
    if case.id:find("single", 1, true) then singles = singles + 1 else mixed = mixed + 1 end
end
print("PASS sparse historical oracle: " .. singles .. " single-bit / " .. mixed
    .. " mixed masks; all 3595 V2 / 6622 V3 positions; V3 default values may evolve")
