-- Declaration authority, including a deliberately disagreeing legacy source.
local root = assert(arg[1])
local profile = { player = { amount = 9 }, general = { amount = 4 }, gf_party = { amount = 1 }, gf_raid = { amount = 2 } }
local scope = "party"
local M = { Widgets = {}, GroupPage = { CurrentScope = function() return scope end } }
function M.EnsureDB() return profile end
function M.DeepCopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = M.DeepCopy(item) end
    return out
end
local namespace = { MSUF2 = M, CPBuilders = { ExtraAuraDefaults = {} } }
local schemaPath = arg[2] or (root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_ControlSchema.lua")
assert(loadfile(schemaPath))("Options", namespace)
local S = M.ControlSchema
assert(S.Setter, "schema-derived setter missing (red baseline)")
local spec = { id = "contract.amount", kind = "slider", setting = "general.amount", range = { 1, 5, 1 },
    write = { source = function() return profile.player end, numberDefault = 1, round = true, clamp = true } }
local set = S.Setter(spec)
set(20)
assert(profile.general.amount == 5 and profile.player.amount == 9, "legacy source redirected the declared write")
spec.range[2] = 3
set(20)
assert(profile.general.amount == 3, "value bounds drifted from the declaration")
spec.setting = "player.amount"
set(2)
assert(profile.player.amount == 2 and profile.general.amount == 3, "setter retained an old physical target")
local entry = { _msuf2SchemaResetTargets = { { spec = spec, root = "general", key = "amount" } } }
S.ResetSection(entry, { "amount" }, profile.general, { amount = 4 }, { player = { amount = 7 } })
assert(profile.player.amount == 7 and profile.general.amount == 3, "section reset did not follow the declared target")
spec.setting = S.GroupKeys("amount")
spec.scope = "group"
set(1)
scope = "raid"
set(3)
assert(profile.gf_party.amount == 1 and profile.gf_raid.amount == 3, "group family captured the build-time scope")
local resolver = { keys = { "gf_party.amount", "gf_raid.amount" }, resolve = function() return "gf_raid.amount" end }
spec.setting, spec.settingPath = resolver, "gf_party.amount"
assert(S.ResolvePath(spec) == "gf_raid.amount", "stale primary metadata overrode the family resolver")
spec.setting, spec.settingPath = "general.amount", nil
spec.write = { source = function() return profile.general end, fallback = false }
set = S.Setter(spec)
set(nil)
assert(profile.general.amount == false, "false reset/default value was lost")
spec.write.fallback = 0
set(nil)
assert(profile.general.amount == 0, "zero default value was lost")
spec.setting = S.Record({ "gf_{scope}.style.amount" })
spec.setting.resolve = function() return "gf_raid.style.amount" end
spec.write = { source = function() profile.gf_raid.style = profile.gf_raid.style or {}; return profile.gf_raid.style end }
set = S.Setter(spec)
set(8)
assert(profile.gf_raid.style.amount == 8, "record-path accessor missed its nested field")
-- A section may restore a complete record to false/nil. Nested targets already
-- bound in that section must not index that scalar, or replace caller defaults
-- with a different factory subtree.
spec.setting = "gf_raid.spellIndicators.style.showTooltip"
local nested = { _msuf2SchemaResetTargets = { { spec = spec, root = "gf_raid", key = "spellIndicators", nested = true } } }
for index = 1, 3 do
    local value
    if index == 1 then value = false
    elseif index == 3 then value = { style = { showTooltip = false, other = 9 } } end
    local defaults = { spellIndicators = value }
    profile.gf_raid.spellIndicators = M.DeepCopy(value)
    S.ResetSection(nested, { "spellIndicators" }, profile.gf_raid, defaults,
        { gf_raid = { spellIndicators = { style = { showTooltip = true, other = 42 } } } }, true)
    local actual = profile.gf_raid.spellIndicators
    if index < 3 then assert(actual == value, "nested reset changed a false/nil ancestor")
    else assert(actual.style.showTooltip == false and actual.style.other == 9, "nested reset ignored caller-specific defaults") end
end
print("PASS schema setter authority: full paths, dynamic families, bounds, false/zero and reset destination")

-- Comparator optimization must preserve every failure and avoid success-path diagnostics.
local parityFile = assert(io.open(arg[3] or (root .. "/tools/tests/menu_schema_setter_parity.lua"), "rb"))
local paritySource = parityFile:read("*a"):gsub("\r\n", "\n")
parityFile:close()
local equalSource = assert(paritySource:match("(local function Equal%b().-\nend)\nlocal policies"))
local compare = assert(loadstring(equalSource .. "\nreturn Equal"))()
local function FrozenEqual(a, b, path)
    path = path or ""
    if type(a) ~= type(b) then return false, path .. " types" end
    if type(a) ~= "table" then return a == b, path .. " values " .. tostring(a) .. " / " .. tostring(b) end
    for key, value in pairs(a) do
        local ok, why = FrozenEqual(value, b[key], path .. "." .. tostring(key))
        if not ok then return false, why end
    end
    for key in pairs(b) do if a[key] == nil then return false, path .. "." .. tostring(key) .. " extra" end end
    return true
end
local function Compare(a, b)
    local expected, reason = FrozenEqual(a, b, "root")
    local actual, why = compare(a, b, "root")
    assert(actual == expected and (actual or reason == why), "parity comparison changed equality/failure diagnostics")
end
for _, value in ipairs({ false, 0, 1, "", "value", function() end }) do
    Compare(value, value)
    Compare(value, nil)
    Compare(nil, value)
    Compare({ nested = { value, extra = true } }, { nested = { value } })
    Compare({ nested = { value } }, { nested = { value, extra = true } })
    Compare({ nested = { value } }, { nested = { value } })
end
Compare(nil, nil)
Compare({ amount = { selected = false } }, { amount = { selected = 0 } })
local sample = {}
for i = 1, 40 do sample[i] = { enabled = true, width = i, selected = "player", nested = { alpha = .5 } } end
local other = M.DeepCopy(sample)
local function Budget(fn)
    local instructions, native = 0, 0
    debug.sethook(function(event)
        if event == "count" then instructions = instructions + 1
        elseif debug.getinfo(2, "S").what == "C" then native = native + 1 end
    end, "c", 1)
    local same = fn(sample, other)
    debug.sethook()
    assert(same, "comparator budget fixture differs")
    return instructions, native
end
local oldInstructions, oldNative = Budget(FrozenEqual)
local newInstructions, newNative = Budget(compare)
assert(newInstructions < oldInstructions and newNative < oldNative, "successful comparisons still eagerly construct failure diagnostics")
print(("PASS parity comparator: equivalent failures; VM %d -> %d; native %d -> %d")
    :format(oldInstructions, newInstructions, oldNative, newNative))

local copySource = assert(paritySource:match("(local function Copy%b().-\nend)\nlocal function Replace"))
local copy = assert(loadstring(copySource .. "\nreturn Copy"))()
local function FrozenCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, item in pairs(value) do out[key] = FrozenCopy(item, seen) end
    return out
end
local shared = { enabled = false, number = 0 }
local graph = { first = shared, second = shared }
graph.self = graph
local cloned = copy(graph)
assert(cloned ~= graph and cloned.self == cloned and cloned.first == cloned.second and cloned.first ~= shared,
    "snapshot copy lost cycles, shared references or isolation")
shared.number = 7
assert(cloned.first.number == 0 and cloned.first.enabled == false, "snapshot follows later source mutation")
assert(compare(copy(sample), FrozenCopy(sample)), "snapshot copy changed full values")
local oldCopyInstructions, oldCopyNative = Budget(function(value) return FrozenCopy(value) end)
local newCopyInstructions, newCopyNative = Budget(function(value) return copy(value) end)
assert(newCopyInstructions < oldCopyInstructions and newCopyNative <= oldCopyNative, "snapshot still calls Lua recursively for primitive fields")
print(("PASS parity snapshot: cycles/aliases/values; VM %d -> %d; native %d -> %d")
    :format(oldCopyInstructions, newCopyInstructions, oldCopyNative, newCopyNative))

-- The restore still traverses in source-key order and retains existing table
-- identities. Skip only identical scalar assignments in the plain profile tree.
local restoreSource = assert(paritySource:match("(local function Replace%b().-\nend)\nlocal function Equal"))
local restore = assert(loadstring(restoreSource .. "\nreturn Replace"))()
local function FrozenReplace(dst, src)
    for key in pairs(dst) do if src[key] == nil then dst[key] = nil end end
    for key, value in pairs(src) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then dst[key] = {} end
            FrozenReplace(dst[key], value)
        else dst[key] = value end
    end
end
for _, source in ipairs({ {}, { enabled = false, zero = 0, text = "" },
    { nested = { 1, false, other = {} } }, { nested = false }, { nested = {} } }) do
    local initial = { enabled = true, stale = 4, nested = { old = 1 } }
    local expected, actual = copy(initial), copy(initial)
    local identity = actual.nested
    FrozenReplace(expected, source)
    restore(actual, source)
    assert(compare(expected, actual), "restore changed nil/false/zero/record/list values")
    if type(source.nested) == "table" then assert(actual.nested == identity, "restore replaced an existing table") end
end
local function RestoreBudget(fn)
    local target = copy(sample)
    return Budget(function(_, source) fn(target, source); return true end)
end
local oldRestoreVM, oldRestoreNative = RestoreBudget(FrozenReplace)
local newRestoreVM, newRestoreNative = RestoreBudget(restore)
assert(newRestoreVM < oldRestoreVM and newRestoreNative < oldRestoreNative,
    "profile restore still calls native type/writes for unchanged scalar leaves")
print(("PASS parity restore: values/identities; VM %d -> %d; native %d -> %d")
    :format(oldRestoreVM, newRestoreVM, oldRestoreNative, newRestoreNative))

-- History emits independent leaf paths through pairs; only that unordered set is canonicalized.
local historySource = assert(paritySource:match("(local function HistoryPathLess%b().-)local function History%(%)"))
local orderHistory = assert(loadstring(historySource .. "\nreturn OrderHistory"))()
local function HistoryFixture()
    return { { label = "first", source = "control", bytes = 42, diff = {
        { path = { "profileDB", "player", "loadCondActive" }, before = false, after = true },
        { path = { "profileDB", "player", "loadCondHideOutOfCombatNoTarget" }, after = true },
    } }, { label = "second", source = "reset", bytes = 21, diff = {
        { path = { "profileDB", "target", "width" }, before = 0, after = 10 },
    } } }
end
local expected = orderHistory(HistoryFixture())
local reordered = HistoryFixture()
reordered[1].diff[1], reordered[1].diff[2] = reordered[1].diff[2], reordered[1].diff[1]
assert(compare(expected, orderHistory(reordered)), "unordered independent history paths failed parity")
for _, mutate in ipairs({
    function(x) table.remove(x[1].diff) end,
    function(x) x[1].diff[1].path[3] = "other" end,
    function(x) x[1].diff[1].before = 0 end,
    function(x) x[1].diff[1].after = false end,
    function(x) x[1].bytes = 41 end,
    function(x) x[1].label = "other" end,
    function(x) x[1].source = "other" end,
    function(x) x[1], x[2] = x[2], x[1] end,
}) do
    local changed = HistoryFixture()
    mutate(changed)
    assert(not compare(expected, orderHistory(changed)), "history normalization concealed changed evidence")
end
for _, path in ipairs({ { "profileDB", "player", "loadCondActive" }, { "profileDB", "player" },
    { "profileDB", "player", "loadCondActive", "nested" } }) do
    local overlapping = HistoryFixture()
    overlapping[1].diff[2].path = path
    assert(not pcall(orderHistory, overlapping), "overlapping/duplicate history paths accepted")
end
local typed = { { diff = { { path = { "1" } }, { path = { 1 } }, { path = { true } }, { path = { false } } } } }
orderHistory(typed)
assert(typed[1].diff[1].path[1] == false and typed[1].diff[2].path[1] == true
    and typed[1].diff[3].path[1] == 1 and typed[1].diff[4].path[1] == "1", "history path types collapsed")
print("PASS parity history: independent path order only; missing/value/metadata/step/overlap mutations rejected")
