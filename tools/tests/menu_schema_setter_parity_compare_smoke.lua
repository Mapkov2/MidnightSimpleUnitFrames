-- The sparse comparison must reject the same mutations as full-profile equality.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local Capture, Restore, Matches, Snapshot = assert(loadfile(root .. "/tools/tests/menu_schema_setter_parity_compare.lua"))()
local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = Copy(item) end
    return out
end
local function Replace(dst, src)
    for key in pairs(dst) do if src[key] == nil then dst[key] = nil end end
    for key, value in pairs(src) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then dst[key] = {} end
            Replace(dst[key], value)
        else dst[key] = value end
    end
end
local baseline = { edited = 1, untouched = { nested = { value = 2 }, kept = false } }
local frozen = Copy(baseline)
frozen.edited = 3
local expected = Capture(baseline, frozen)
assert(expected.untouched == nil, "unchanged subtree allocated a delta")
local mutations = {
    { "added key", function(value) value.untouched.extra = true end },
    { "removed key", function(value) value.untouched.kept = nil end },
    { "nested value", function(value) value.untouched.nested.value = 9 end },
    { "table to scalar", function(value) value.untouched.nested = false end },
    { "scalar to table", function(value) value.untouched.kept = {} end },
    { "empty table", function(value) value.untouched.extra = {} end },
    { "removed table", function(value) value.untouched.nested = nil end },
    { "emptied table", function(value) value.untouched.nested = {} end },
}
for _, mutation in ipairs(mutations) do
    local derived = Copy(frozen)
    mutation[2](derived)
    local ok = pcall(function()
        assert(Matches(baseline, expected, derived, Equal), "derived profile differs")
    end)
    assert(not ok, "accepted wrong derived write: " .. mutation[1])
end
-- Cross-check all pairs against an independent full-tree oracle, including
-- false/zero, key types, additions/removals, empty records and type changes.
local records = {
    {}, { x = false }, { x = 0 }, { x = 1 }, { x = "1" }, { x = {} },
    { x = { y = 1 } }, { x = { y = false } }, { x = { y = {} } },
    { x = { y = 1, z = 2 } }, { x = { [1] = true, [false] = "bool" } },
    { x = { y = { z = 1 } }, extra = {} }, { [1] = 0, [true] = false },
    { x = { removed = false }, extra = true }, { x = function() end },
}
local nan = 0 / 0
local withNaN = { nested = { value = nan } }
local nanBaseline = Copy(withNaN)
assert(not Equal(Capture(nanBaseline, withNaN), Capture(nanBaseline, Copy(withNaN))), "NaN leaf was treated as equal")
assert(not Matches(nanBaseline, Capture(nanBaseline, withNaN), Copy(withNaN), Equal), "direct comparison accepted NaN")
local checks = 0
local restores = 0
for _, record in ipairs(records) do
    local before = Copy(record)
    for _, left in ipairs(records) do
        local delta = Capture(before, left)
        assert(Equal(Snapshot(before, left), left), "persistent/full snapshot differs")
        assert(Equal(before, record), "persistent snapshot mutated its baseline")
        for _, right in ipairs(records) do
            assert(Equal(left, right) == Equal(delta, Capture(before, right)), "sparse/full comparison differs")
            assert(Equal(left, right) == Matches(before, delta, right, Equal), "direct/full comparison differs")
            checks = checks + 1
        end
        local actual = Copy(left)
        Restore(actual, before, Capture(before, actual), Replace)
        assert(Equal(before, actual), "sparse restore differs from full Replace")
        restores = restores + 1
    end
end
-- Captures own changed descendants: later mutations must not rewrite the oracle.
local actual = Copy(frozen)
actual.untouched.nested.value = 4
local delta = Capture(baseline, actual)
actual.untouched.nested.value = 5
assert(delta.untouched.nested.value == 4, "captured delta aliases the live profile")
local snapshot = Snapshot(baseline, actual)
actual.untouched.nested.value = 7
assert(snapshot.untouched.nested.value == 5, "persistent snapshot aliases a live record")
assert(Snapshot(baseline, Copy(baseline)) == baseline, "unchanged snapshot allocated a record")
assert(Equal(expected, Capture(baseline, frozen)), "unchanged equivalent replay failed")
local actual = Copy(frozen)
actual.untouched.nested.value = 8
local owner, nested = actual.untouched, actual.untouched.nested
Restore(actual, baseline, Capture(baseline, actual), Replace)
assert(actual.untouched == owner and actual.untouched.nested == nested, "restore replaced a surviving table")
print(("PASS setter parity comparison: %d oracle pairs, %d restores, %d rejected derived mutations")
    :format(checks, restores, #mutations))
