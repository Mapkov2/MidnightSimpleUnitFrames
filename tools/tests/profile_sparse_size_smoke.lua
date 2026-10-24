-- C11: exact extended storage, malformed inputs, rollback and byte accounting.
-- Standalone diagnostic; release contracts and the frozen gate remain unchanged.
local root = assert(arg[1])
local C = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local S = assert(loadfile(root .. "/tools/fixtures/defaults/schema.lua"))()
local function Serial(value) return assert(loadstring("return " .. H.Literal(value)))() end
local function Read(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return text
end
local path = root .. "/MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_Schema.lua"
local pieces = {}
local directory = root .. "/MidnightSimpleUnitFrames/State/Defaults/"
for _, name in ipairs({ "Schema", "StorageData", "StorageCommon", "StorageV3", "Storage", "Recovery" }) do
    -- Each shipped shard retains its own chunk scope; mutation probes still
    -- inspect and edit the exact source body across the complete codec.
    pieces[#pieces + 1] = "do local function Part(...)\n" .. Read(directory .. "MSUF_Defaults_" .. name .. ".lua")
        .. "\nend Part(...) end\n"
end
local source = table.concat(pieces)
local function Codec(text, secretCheck)
    local ns = { Util = { IsSecret = secretCheck or function() return false end } }
    assert(loadstring(text))(nil, ns)
    return ns.DefaultsSchema
end
local schema = Codec(source)
local baseline = arg[2] and Codec(Read(arg[2])) or nil
local function Same(a, b, context) assert(H.Literal(a) == H.Literal(b), context) end
local function Base()
    local p = Serial(S.factoryContexts.clients.Mainline.expectedRuntime)
    p.arena.absorbBarOffsetY, p.arena.alphaExcludePredictionBars = 0, false
    return p
end
local p = Base()
local before = Serial(p)
local owner = p.arena
assert(schema.Persist({ profiles = { One = p } }))
assert(p.arena.absorbBarOffsetY == nil, "default zero retained")
assert(p.arena.alphaExcludePredictionBars == nil, "default false retained")
local encoded = Serial(p)
assert(type(p._msufSparseDefaultsV3) == "string", "V3 presence absent")
assert(schema.RestorePersistence(p))
assert(p.arena == owner, "existing owner identity replaced")
Same(p, before, "new elisions did not roundtrip exactly")
if baseline then
    local old = Serial(before)
    assert(baseline.Persist({ profiles = { One = old } }))
    assert(schema.RestorePersistence(old))
    Same(old, before, "previous V2 failed to restore")
    old = Serial(before)
    assert(baseline.Persist({ profiles = { One = old } }))
    old.general.alias = old.auras3.customDisplays.shared.items
    local aliased = Serial(old)
    assert(baseline.RestorePersistence(aliased))
    assert(schema.RestorePersistence(old), "V3-only owner alias blocked old V2")
    Same(old, aliased, "old V2 alias restoration differs")
end
-- A presence slot means inherit the current default, including a true -> false change.
local frozen = assert(source:match("local sparseV2Fields = (%b{})"))
local fields = assert(loadstring("return " .. frozen))()
local inheritedId
for id, field in ipairs(fields) do
    if field[1] == "previewDragHintAnimationEnabled" then inheritedId = id end
end
assert(inheritedId, "inheritance field missing")
local prefix, data, suffix = source:match("^(.-)(%-%- BEGIN SPARSE V3 INHERITED DEFAULTS.-%-%- END SPARSE V3 INHERITED DEFAULTS)(.*)$")
local changedData, count = data:gsub("sparseV2Fields%[" .. inheritedId .. "%]", '{ "previewDragHintAnimationEnabled", false }')
assert(count == 1, "inheritance mutation did not select one V3 default")
local changed = prefix .. changedData .. suffix
local inheriting = Codec(changed)
local inherited = Serial(encoded)
assert(inheriting.RestorePersistence(inherited))
assert(inherited.general.previewDragHintAnimationEnabled == false, "old default did not follow new default")
local explicit = Serial(encoded)
explicit.general.previewDragHintAnimationEnabled = true
assert(inheriting.RestorePersistence(explicit) and explicit.general.previewDragHintAnimationEnabled == true,
    "inherited default overwrote an explicit stored value")
-- The real verification branch must roll back every captured field and format stamp.
local failing = Codec((source:gsub("function sparseV3.Same%(%)", "function sparseV3.Same()\n if true then return false end", 1)))
local rollback = Base()
local rollbackOwner = rollback.arena
local rollbackBefore = Serial(rollback)
assert(select(2, failing.Persist({ profiles = { One = rollback } })) == 0, "fault did not trigger rollback")
Same(rollback, rollbackBefore, "rollback changed fields")
assert(rollback.arena == rollbackOwner, "rollback replaced an owner")
local mask = encoded._msufSparseDefaultsV3
for _, bad in ipairs({ false, 0, "", {}, "future", string.rep("0", #mask), string.rep("g", #mask), mask .. "0", mask:sub(1, -2) .. "f" }) do
    local broken = Serial(encoded)
    broken._msufSparseDefaultsV3 = bad
    local snapshot = Serial(broken)
    assert(not schema.RestorePersistence(broken), "invalid V3 accepted")
    Same(broken, snapshot, "malformed V3 partially restored")
end
for _, edit in ipairs({
    function(t) t.player = nil end,
    function(t) t._msufSparseDefaultsV2 = nil end,
    function(t) t._msufDefaultsRevision = 18 end,
    function(t) t._msufDefaultsRevision = 18; t._msufSparseDefaultsV2 = nil end,
    function(t) t.auras3 = t.player end,
}) do
    local broken = Serial(encoded)
    edit(broken)
    local snapshot = Serial(broken)
    assert(not schema.RestorePersistence(broken), "invalid owner/stamp accepted")
    Same(broken, snapshot, "invalid owner/stamp partially restored")
end
for _, stamp in ipairs({ 16, 17 }) do
    local stale = Serial(encoded)
    stale._msufDefaultsRevision = stamp
    assert(schema.RestorePersistence(stale))
    assert(stale._msufSparseDefaultsV2 == nil and stale._msufSparseDefaultsV3 == nil,
        "downgraded profile kept a stale mask")
    assert(stale.arena.absorbBarOffsetY == nil, "stale mask invented defaults")
end
local unknown = Base()
unknown.general.userSpellRecords = { [12345] = { enabled = true, size = 20 }, [0] = "zero", false, 0, "" }
unknown.player[1] = "unexpected list"
local unknownBefore = Serial(unknown)
assert(schema.Persist({ profiles = { One = unknown } }))
Same(unknown.player, unknownBefore.player, "unexpected list compacted")
Same(unknown.general.userSpellRecords, unknownBefore.general.userSpellRecords, "unknown records compacted")
assert(schema.RestorePersistence(unknown))
Same(unknown, unknownBefore, "list/unknown records changed")
-- Secrets must be rejected before a marker/value can enter any comparison.
local secret = {}
local secretCodec = Codec(source, function(value) return value == secret end)
for _, key in ipairs({ "_msufSparseDefaultsV2", "_msufSparseDefaultsV3", "_msufDefaultsRevision" }) do
    local broken = Serial(encoded)
    broken[key] = secret
    local text = H.Literal(broken)
    assert(not secretCodec.RestorePersistence(broken), "secret format stamp accepted")
    assert(broken[key] == secret and H.Literal(broken) == text, "secret rejection changed fields")
end
local unsafe = Base()
unsafe.general.secretSetting = secret
local unsafeBefore = H.Literal(unsafe)
assert(select(2, secretCodec.Persist({ profiles = { One = unsafe } })) == 0, "secret root compacted")
assert(H.Literal(unsafe) == unsafeBefore, "secret fallback changed fields")
-- Only generated numeric paths are eligible; an empty removed leaf is restored
-- as its original table during terminal verification, and as a new table at login.
local frozenFields = assert(source:match("local sparseV2Fields = (%b{})"))
local data = assert(source:match("%-%- BEGIN SPARSE V3 INHERITED DEFAULTS.-%-%- END SPARSE V3 INHERITED DEFAULTS"))
local fields, owners, runs = assert(loadstring("local sparseV2Fields = " .. frozenFields .. "\n" .. data
    .. "\nreturn sparseV3Fields, sparseV3Owners, sparseV3Runs"))()
local numeric, empty
for _, spec in ipairs(owners) do
    spec.fields = {}
    for _, run in ipairs(spec.runs) do
        for _, id in ipairs(runs[run]) do spec.fields[#spec.fields + 1] = id end
    end
    for _, id in ipairs(spec.fields) do
        local field = fields[id]
        if type(field[1]) == "number" then numeric = { spec, field } end
        if type(field[2]) == "table" then empty = { spec, field } end
    end
end
local function Owner(profile, spec)
    local node = profile
    for _, key in ipairs(spec.path) do node = node[key] end
    return node
end
assert(numeric and empty, "numeric/empty dictionary coverage missing")
local full = Base()
local arrayOwner = Owner(full, numeric[1])
local tableOwner = Owner(full, empty[1])
local arrayBefore = arrayOwner[numeric[2][1]]
local tableBefore = tableOwner[empty[2][1]]
assert(type(tableBefore) == "table" and next(tableBefore) == nil)
assert(schema.Persist({ profiles = { One = full } }))
assert(arrayOwner[numeric[2][1]] == nil and tableOwner[empty[2][1]] == nil, "numeric/empty default retained")
assert(schema.RestorePersistence(full))
assert(arrayOwner[numeric[2][1]] == arrayBefore, "numeric slot changed")
assert(type(tableOwner[empty[2][1]]) == "table" and next(tableOwner[empty[2][1]]) == nil, "empty leaf lost")
local aliased = Base()
aliased.general.alias = Owner(aliased, empty[1])[empty[2][1]]
local aliasBefore = H.Literal(aliased)
assert(select(2, schema.Persist({ profiles = { One = aliased } })) == 0, "shared empty default was removed")
assert(H.Literal(aliased) == aliasBefore, "shared empty default fallback changed fields")

-- No steady-state allocation even while encoding and decoding full profiles repeatedly.
local store = { profiles = { One = Base() } }
local original = Serial(store.profiles.One)
local function Reset(owner, saved)
    for key, value in pairs(saved) do
        if type(value) == "table" and type(owner[key]) == "table" then Reset(owner[key], value)
        else owner[key] = value end
    end
end
local function Cycle()
    assert(schema.Persist(store))
    -- Normal login may allocate fresh empty tables. Reuse the original test
    -- owners here to isolate the terminal encoder and its internal decoder.
    Reset(store.profiles.One, original)
    store.profiles.One._msufSparseDefaultsV2 = nil
    store.profiles.One._msufSparseDefaultsV3 = nil
end
for _ = 1, 10 do Cycle() end
local minimum = math.huge
for _ = 1, 2 do
    collectgarbage("collect")
    Cycle()
    collectgarbage("stop")
    local start = collectgarbage("count")
    for _ = 1, 20 do Cycle() end
    local bytes = (collectgarbage("count") - start) * 1024
    collectgarbage("restart")
    minimum = math.min(minimum, bytes)
end
assert(minimum == 0, "extended terminal codec allocated " .. minimum .. " bytes")
print("C11 allocation bytes " .. minimum)

-- Account every literal byte: scalar payload categories plus keys and punctuation.
-- The separate associated column includes a leaf's own key/delimiters; it is a
-- conservative elision bound, not an additional component of the payload sum.
local function Breakdown(profile, defaults)
    local b = { different = 0, unknown = 0, equal = 0, retained = 0, numeric = 0, metadata = 0,
        equalMarkers = 0, equalNumeric = 0, equalAura = 0, equalNested = 0, equalScalar = 0,
        keys = 0, syntax = 0, empty = 0, differentAssociated = 0, unknownAssociated = 0, equalAssociated = 0 }
    local function Walk(value, default, retained, numeric, path, depth)
        b.syntax = b.syntax + 2
        if next(value) == nil then b.empty = b.empty + 2 end
        local count = 0
        for key, child in pairs(value) do
            count = count + 1
            local keyBytes = #H.Literal(key) + 3
            b.keys = b.keys + keyBytes
            local d
            if type(default) == "table" then d = default[key] end
            local lower = tostring(key):lower()
            local keep = retained or lower:find("migration", 1, true) or lower:find("version", 1, true)
                or lower:find("revision", 1, true) or lower:find("marker", 1, true)
                or tostring(key):sub(1, 1) == "_" or key == "positionMode"
            local num = numeric or type(key) == "number"
            local childPath = path .. "." .. tostring(key)
            if type(child) == "table" then Walk(child, d, keep, num, childPath, depth + 1)
            else
                local n = #H.Literal(child)
                if key == "_msufSparseDefaultsV2" or key == "_msufSparseDefaultsV3" or key == "_msufDefaultsRevision" then
                    b.metadata = b.metadata + n
                elseif d == nil then
                    b.unknown = b.unknown + n
                    b.unknownAssociated = b.unknownAssociated + n + keyBytes
                elseif type(child) ~= type(d) or child ~= d then
                    b.different = b.different + n
                    b.differentAssociated = b.differentAssociated + n + keyBytes
                else
                    b.equal = b.equal + n
                    b.equalAssociated = b.equalAssociated + n + keyBytes
                    local associated = n + keyBytes
                    if keep then b.equalMarkers = b.equalMarkers + associated
                    elseif childPath:lower():find("aura", 1, true) or childPath:lower():find("spell", 1, true) then
                        b.equalAura = b.equalAura + associated
                    elseif num then b.equalNumeric = b.equalNumeric + associated
                    elseif depth > 1 then b.equalNested = b.equalNested + associated
                    else b.equalScalar = b.equalScalar + associated end
                    if keep then b.retained = b.retained + n end
                    if num then b.numeric = b.numeric + n end
                end
            end
        end
        b.syntax = b.syntax + math.max(0, count - 1)
    end
    Walk(profile, defaults, false, false, "", 0)
    assert(b.different + b.unknown + b.equal + b.metadata + b.keys + b.syntax == #H.Literal(profile), "byte accounting differs")
    return b
end
local function Measure(id, mode, full, defaults)
    local store = { profiles = { One = Serial(full) } }
    local old = { profiles = { One = Serial(full) } }
    if baseline then assert(baseline.Persist(old)) end
    assert(schema.Persist(store))
    local compact = store.profiles.One
    local oldBytes = baseline and #H.Literal(old.profiles.One) or 0
    local b = Breakdown(compact, defaults)
    if baseline then
        print("C11_V2\t" .. id .. "\t" .. mode .. "\t" .. H.Literal(Breakdown(old.profiles.One, defaults)))
    end
    print("C11_BYTES\t" .. id .. "\t" .. mode .. "\t" .. #H.Literal(full) .. "\t" .. oldBytes .. "\t"
        .. #H.Literal(compact) .. "\t" .. H.Literal(b))
    if compact._msufSparseDefaultsV2 then assert(schema.RestorePersistence(compact)) end
    Same(compact, full, id .. ": fixture roundtrip differs")
end
for _, flavor in ipairs({ "Mainline", "Vanilla", "TBC", "Mists", "Forever" }) do
    local factory = S.factoryContexts.clients[flavor].expectedRuntime
    Measure("factory/" .. flavor, "factory", factory, factory)
end
for _, entry in ipairs(C.Manifest(root)) do
    if entry.kind == "sv" then
        local saved = C.LoadSavedVariablesFixture(root, entry.file)
        local flavor = entry.clients[1]
        local defaults = S.factoryContexts.clients[flavor].expectedRuntime
        for _, name in ipairs(C.SortedKeys(saved.MSUF_GlobalDB.profiles)) do
            Measure(entry.id .. "/" .. name, "raw", saved.MSUF_GlobalDB.profiles[name], defaults)
        end
        local world = C.NewWorld(root, flavor, entry.login)
        C.Login(world, saved)
        for _, name in ipairs(C.SortedKeys(world.env.MSUF_GlobalDB.profiles)) do
            assert(world.env.MSUF_SwitchProfile(name) ~= false, "fixture bind failed")
            Measure(entry.id .. "/" .. name, "login", world.env.MSUF_GlobalDB.profiles[name], defaults)
        end
    end
end
print("profile_sparse_size_smoke: exact raw/login/factory/rollback/inheritance/malformed/allocation PASS")
