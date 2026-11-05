-- The optimized fixture serializer must emit the original exact Lua bytes.
local root = assert(arg[1])
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local function Original(value)
    local kind = type(value)
    if kind == "number" then return string.format("%.17g", value) end
    if kind == "boolean" then return value and "true" or "false" end
    if kind == "string" then return string.format("%q", value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, key in ipairs(keys) do
        local name = type(key) == "string" and string.format("[%q]", key) or "[" .. Original(key) .. "]"
        parts[#parts + 1] = name .. "=" .. Original(value[key])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end
local values = { false, true, 0, -0, 1, -1, 1 / 3, 1e-250, 1e250, "", "a\0b", "quotes\"\\\n", "UTF8: \195\164", {} }
local keys = { "a", "A", "10", "2", "true", "quotes\"\\\n", "a\0b", 0, -1, 1, 10, 2, true, false }
local checked = 0
local function Check(value)
    assert(H.Literal(value) == Original(value), "fixture serialization bytes changed at case " .. checked)
    checked = checked + 1
end
for _, value in ipairs(values) do Check(value) end
for i, key in ipairs(keys) do
    for j, value in ipairs(values) do
        local tree = { [key] = value, nested = { z = value, a = { [key] = value } } }
        Check(tree)
        tree.changed, tree.nested.extra = values[(j % #values) + 1], values[(i % #values) + 1]
        Check(tree)
        tree.changed, tree[key] = nil, nil
        Check(tree)
    end
end
for width = 1, #keys do
    local mixed, repeated = {}, {}
    for i = 1, width do mixed[keys[i]] = values[((width + i) % #values) + 1] end
    for i = 1, 8 do repeated[i] = mixed end
    Check(mixed); Check(repeated)
    mixed[keys[width]] = "updated"
    Check(repeated)
end
-- Lua forwards every return value from a final argument expression. The public
-- serializer historically ignores them; they must never seed its private cache.
local forwarded = { nested = { key = "current" } }
local expected = Original(forwarded)
for _, extra in ipairs({ true, false, 7, "extra", { key = "poison" } }) do
    assert(H.Literal(forwarded, extra) == expected, "extra public argument changed serialization")
    checked = checked + 1
end
local function MultiReturn() return forwarded, true, "projection status" end
assert(H.Literal(MultiReturn()) == expected, "forwarded return values became serializer options")
checked = checked + 1
-- Real persisted factory values, including all nested settings and numeric maps.
local C = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
for _, flavor in ipairs({ "Mainline", "Vanilla", "TBC", "Mists", "Forever" }) do
    local world = C.NewWorld(root, flavor, "Literal-Realm")
    C.Login(world, {})
    Check(world.env.MSUF_DB)
end
print("PASS profile literal: " .. checked .. " exact-byte oracle cases including mutations and real profiles")
