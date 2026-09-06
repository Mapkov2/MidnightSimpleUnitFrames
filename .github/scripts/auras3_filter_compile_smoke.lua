-- Candidate-filter semantics and ownership checks, with optional differential
-- comparison against a frozen source tree: lua this.lua <root> <baseline-root>.
-- The allocator/operation sample is plain Lua 5.1 work, not an in-game CPU claim.
local root = arg and arg[1] or "."
local baselineRoot = arg and arg[2]
local relative = "/MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_ConfigValues.lua"
local checks = 0

local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end

local function Same(actual, expected)
    if type(actual) ~= type(expected) then return false end
    if type(actual) ~= "table" then return actual == expected end
    for key, value in pairs(actual) do
        if not Same(value, expected[key]) then return false end
    end
    for key in pairs(expected) do
        if actual[key] == nil then return false end
    end
    return true
end

local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, child in pairs(value) do out[key] = Copy(child) end
    return out
end

local function Load(sourceRoot)
    local counters = { strings = 0, sorts = 0, aliases = 0 }
    local tableAPI = setmetatable({
        sort = function(...) counters.sorts = counters.sorts + 1; return table.sort(...) end,
    }, { __index = table })
    local environment = setmetatable({
        table = tableAPI,
        tostring = function(value) counters.strings = counters.strings + 1; return tostring(value) end,
    }, { __index = _G })
    local namespace = {}
    local chunk = assert(loadfile(sourceRoot .. relative))
    setfenv(chunk, environment)("MidnightSimpleUnitFrames", namespace)
    local state = { AuraSpellIDAliases = { [123] = { 789 }, [456] = { 654, 456 } } }
    local function AddAliases(out, id)
        counters.aliases = counters.aliases + 1
        if not (id and id > 0) then return end
        out[id] = true
        for _, alias in ipairs(state.AuraSpellIDAliases[id] or {}) do out[alias] = true end
    end
    state.AddAuraSpellIDAndAliases = AddAliases
    local dependencies = {
        Shape = {}, MAX_CONFIGURABLE_DEBUFF_DURATION = 3600,
        MAX_FINITE_AURA_DURATION = 2147483647,
        Round = function(value) return math.floor(value + 0.5) end,
        ClampNumber = function(value, fallback, minimum, maximum)
            value = tonumber(value) or fallback
            return math.max(minimum, math.min(maximum, value))
        end,
    }
    -- Support both frozen explicit-field wiring and the role-based bootstrap.
    dependencies.Platform, dependencies.Schema = dependencies, dependencies
    dependencies.Appearance, dependencies.Signatures = dependencies, dependencies
    local api = namespace.Auras3RuntimeFactories.ConfigValues(
        "MidnightSimpleUnitFrames", namespace, state, {}, function() end, dependencies)
    return { api = api, state = state, counters = counters, addAliases = AddAliases }
end

local candidate = Load(root)
local baseline = baselineRoot and Load(baselineRoot)
local function Compare(method, ...)
    local value, signature = candidate.api[method](...)
    if baseline then
        local expected, expectedSignature = baseline.api[method](...)
        Check(Same(value, expected) and signature == expectedSignature, method .. " differs from baseline")
    end
    return value, signature
end

-- Tokens, list values, mixed maps and nested legacy records remain accepted.
local mixed = {
    [123] = true, [456] = false, [1] = "#456", [2] = { spellId = 777 },
    [3] = { id = 888, enabled = false }, [4] = { "spell:999" },
    ["spell:111"] = {}, ["ignored"] = true, [9.5] = true,
}
local original = Copy(mixed)
local filters, signature = Compare("CandidateFiltersFromSpellIDs", mixed)
Check(Same(filters, { excludeSpellIDs = {
    [123] = true, [789] = true, [456] = true, [654] = true,
    [777] = true, [999] = true, [111] = true,
} }), "mixed saved spell forms changed")
Check(signature == "excludeSpellIDs:111,123,456,654,777,789,999", "signature ordering changed")
Check(Same(mixed, original), "compiling modified the saved map")
Check(Compare("CandidateFiltersFromSpellIDs", {}) == nil, "empty map must have no filter")
Check(Compare("CandidateFiltersFromSpellIDs", false) == nil, "non-table must have no filter")

-- Numeric fast-path edges must preserve the old tostring/pattern contract,
-- including fractional values rounded by tostring and scientific notation.
local numericCases = {
    0, -1, 1, 1.5, 1.000000000000001, 123456, 2147483647, 4294967295,
    9999999999999, 99999999999999, 100000000000000, 100000000000001,
    math.huge, -math.huge, -1 / math.huge,
}
for _, value in ipairs(numericCases) do
    Compare("CandidateFiltersFromSpellIDs", { [value] = true })
    Compare("CandidateFiltersFromSpellIDs", { value })
    Compare("CandidateFiltersFromSpellIDs", { { spellID = value } }, "includeSpellIDs")
end
-- Large deterministic sets exercise both maps and records without depending on
-- random generator versions. Baseline comparison guards every resulting ID.
for fixture = 1, 240 do
    local source = {}
    for index = 1, 40 do
        local id = (fixture * 7919 + index * 104729) % 2000000
        local form = (fixture + index) % 6
        if form == 0 then source[id] = true
        elseif form == 1 then source["spell:" .. id] = true
        elseif form == 2 then source[index] = "#" .. id
        elseif form == 3 then source[index] = { spellID = id }
        elseif form == 4 then source[index] = { id = id, enabled = index % 3 ~= 0 }
        else source[id] = false end
    end
    Compare("CandidateFiltersFromSpellIDs", source)
    Compare("CandidateFiltersFromIncludeAndExcludeSpellIDs", mixed, source)
end

-- Fresh lane options AND mutable ID hashes are required: auto-blacklisting and
-- alias learning extend these after compilation. Changes cannot leak to siblings.
local source, blacklist = { [123] = true }, { [456] = true }
local first = Compare("CandidateFiltersFromIncludeAndExcludeSpellIDs", source, blacklist)
local second = Compare("CandidateFiltersFromIncludeAndExcludeSpellIDs", source, blacklist)
Check(first ~= second and first.includeSpellIDs ~= second.includeSpellIDs
    and first.excludeSpellIDs ~= second.excludeSpellIDs, "mutable lane tables were shared")
first.includeSpellIDs[9999], first.excludeSpellIDs[9998] = true, true
candidate.api.AddMaxDurationCandidateFilter(first, nil, 25, false)
candidate.api.AddNonPlayerCandidateFilter(first, nil, true)
Check(second.includeSpellIDs[9999] == nil and second.excludeSpellIDs[9998] == nil
    and second.maxDuration == nil and second.isFromPlayerOrPlayerPet == nil, "lane mutation leaked")
Compare("CandidateFiltersFromIncludeAndExcludeSpellIDs", source, blacklist)

-- Both saved-map edits and learned aliases are visible on the very next compile,
-- even when table identities and runtime generation remain unchanged.
source[123], source[456] = nil, { spellID = 777 }
blacklist[456] = false
Compare("CandidateFiltersFromIncludeAndExcludeSpellIDs", source, blacklist)
source[123] = true
candidate.state.AuraSpellIDAliases[123][2] = 1001
if baseline then baseline.state.AuraSpellIDAliases[123][2] = 1001 end
local learned = Compare("CandidateFiltersFromSpellIDs", source, "includeSpellIDs")
Check(learned.includeSpellIDs[1001] == true, "new alias was hidden by stale normalization")
candidate.state.AddAuraSpellIDAndAliases = nil
if baseline then baseline.state.AddAuraSpellIDAndAliases = nil end
Compare("CandidateFiltersFromSpellIDs", { [0] = true, [123] = true })
Compare("CandidateFiltersFromSpellIDs", { -1 / math.huge, 0 / 0 })
candidate.state.AddAuraSpellIDAndAliases = candidate.addAliases
if baseline then baseline.state.AddAuraSpellIDAndAliases = baseline.addAliases end

-- Only the existing versioned catalog contract permits shared include hashes.
for _, catalog in ipairs({ {}, { [123] = true } }) do
    local staticA = Compare("CandidateFiltersFromIncludeAndExcludeSpellIDs", catalog, mixed, "catalog:1")
    local staticB = Compare("CandidateFiltersFromIncludeAndExcludeSpellIDs", catalog, mixed, "catalog:1")
    Check(staticA.includeSpellIDs == catalog and staticB.includeSpellIDs == catalog,
        "versioned include catalog stopped sharing")
    Check(staticA ~= staticB and staticA.excludeSpellIDs ~= staticB.excludeSpellIDs,
        "catalog sharing leaked to mutable lane options")
end
Compare("CandidateFiltersFromIncludeAndExcludeSpellIDs", nil, mixed)
Compare("CandidateFiltersFromIncludeAndExcludeSpellIDs", mixed, nil)
Compare("CandidateFiltersFromIncludeAndExcludeSpellIDs", nil, nil)
Compare("CandidateFiltersFromBlacklist", { spells = mixed, maxDuration = 25 })
Compare("CandidateFiltersFromBlacklist", { spells = {}, hidePermanent = true })
Compare("CandidateFiltersFromBlacklistHash", mixed)

if baseline then
    local included, excluded = {}, {}
    for id = 10000, 10031 do included[id], excluded[id + 100] = true, true end
    local iterations = 1000
    local function Sample(owner)
        owner.api.CandidateFiltersFromIncludeAndExcludeSpellIDs(included, excluded)
        for key in pairs(owner.counters) do owner.counters[key] = 0 end
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, iterations do
            owner.api.CandidateFiltersFromIncludeAndExcludeSpellIDs(included, excluded)
        end
        local allocated = collectgarbage("count") - before
        collectgarbage("restart")
        collectgarbage("collect")
        return allocated
    end
    local oldKB, newKB = Sample(baseline), Sample(candidate)
    Check(candidate.counters.strings == baseline.counters.strings / 2,
        "numeric maps no longer halve tostring work")
    Check(candidate.counters.sorts == baseline.counters.sorts
        and candidate.counters.aliases == baseline.counters.aliases,
        "normalization omitted alias expansion or deterministic sorting")
    Check(newKB < oldKB, "combined filters did not reduce Lua allocations")
    print(string.format("FILTER WORK (%d compiles, 32 include + 32 exclude IDs): tostring %d -> %d; "
        .. "sorts %d -> %d; Lua allocation %.2f -> %.2f KiB", iterations,
        baseline.counters.strings, candidate.counters.strings,
        baseline.counters.sorts, candidate.counters.sorts, oldKB, newKB))
end
print("PASS Auras3 filter compile: " .. checks .. " semantic, ownership and bounded work checks")
