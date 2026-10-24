-- Serialized V3 -> opt-in full save -> pinned native 6.50 fast load.
local root, flavor = assert(arg[1]), assert(arg[2])
local C = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local function Serial(value) return assert(loadstring("return " .. H.Literal(value)))() end
local function Read(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return text
end
local legacy = Read(root .. "/tools/tests/profile_sparse_backward_migration_smoke.lua")
local function Excerpt(name)
    return assert(legacy:match("local " .. name .. " = %[%=%[(.-)%]%=%]"), name)
end
local Current650 = assert(loadstring("local MSUF_DEFAULTS_CURRENT_REVISION, MSUF_DEFAULTS_CURRENT_PROFILE_SCHEMA = 17, 600\n"
    .. Excerpt("rootsSource") .. Excerpt("guardSource") .. "\nreturn MSUF_Defaults_IsCurrentProfileDB"))()
local function Load(saved, character)
    local w = C.NewWorld(root, flavor, character or "Tester-Realm")
    C.Login(w, Serial(saved or {}))
    return w, w.env, w.core
end
local cases, profiles = 0, 0
for _, entry in ipairs(C.Manifest(root)) do
    local relevant = entry.kind == "factory"
    for _, client in ipairs(entry.clients) do if client == flavor then relevant = true end end
    if relevant then
        local saved = entry.kind == "sv" and C.LoadSavedVariablesFixture(root, entry.file) or {}
        local w, env, ns = Load(saved, entry.login)
        local pool = env.MSUF_GlobalDB.profiles
        -- Materialize the original full view just as binding each old profile does.
        for name in pairs(pool) do env.MSUF_SwitchProfile(name) end
        pool.Inactive = C.Copy(env.MSUF_DB)
        pool.Inactive.general.rollbackUnknown = { false, 0, "", [12345] = "spell" }
        pool.Inactive.general.castbarShowPushback = nil
        local full = H.Literal(pool)
        w:FireEvent("PLAYER_LOGOUT")
        assert(type(pool.Inactive._msufSparseDefaultsV3) == "string", "source was not V3 sparse")
        local sparse = Serial(env.MSUF_GlobalDB)
        w, env, ns = Load({ MSUF_GlobalDB = sparse }, entry.login)
        assert(ns.SlashCommands.Get("compatsave"), "missing /msuf compatsave")
        ns.SlashCommands.Dispatch("compatsave")
        assert(env.MSUF_GlobalDB._compatSave == "armed", "compat mode did not arm")
        w:FireEvent("PLAYER_LOGOUT")
        local disk = Serial(env.MSUF_GlobalDB)
        assert(disk._compatSave == "saved", "compat mode did not record a completed full save")
        for name, profile in pairs(disk.profiles) do
            assert(profile._msufSparseDefaultsV2 == nil and profile._msufSparseDefaultsV3 == nil, name .. ": sparse mask remained")
            assert(Current650(profile), name .. ": unchanged 6.50 would enter its heavy repair path")
            profiles = profiles + 1
        end
        -- The pinned native guard returns before migrations on this exact representation.
        assert(H.Literal(disk.profiles) == full, entry.id .. ": native 6.50 full values differ byte for byte")
        w, env, ns = Load({ MSUF_GlobalDB = disk }, entry.login)
        assert(env.MSUF_GlobalDB._compatSave == nil, "7.0 full-data login did not disarm compat mode")
        w:FireEvent("PLAYER_LOGOUT")
        assert(type(env.MSUF_GlobalDB.profiles.Inactive._msufSparseDefaultsV3) == "string", "normal sparse saving did not resume")
        cases = cases + 1
    end
end
local w, env, ns = Load()
ns.SlashCommands.Dispatch("compatsave")
ns.SlashCommands.Dispatch("compatsave off")
assert(env.MSUF_GlobalDB._compatSave == nil, "explicit off failed")
w:FireEvent("PLAYER_LOGOUT")
assert(env.MSUF_GlobalDB.profiles.Default._msufSparseDefaultsV3, "off did not resume sparse saving")
-- Armed state must survive an interrupted/unfinished save and cannot consume sparse data.
local disk = Serial(env.MSUF_GlobalDB)
disk._compatSave = "saved"
w, env, ns = Load({ MSUF_GlobalDB = disk })
assert(env.MSUF_GlobalDB._compatSave == "armed", "sparse login incorrectly disarmed compat mode")
w:FireEvent("PLAYER_LOGOUT")
assert(env.MSUF_GlobalDB._compatSave == "saved" and Current650(env.MSUF_GlobalDB.profiles.Default))
-- Unknown/corrupt data refuses compatibility without rewriting any profile.
local good = Serial(env.MSUF_GlobalDB.profiles.Default)
for _, edit in ipairs({ function(p) p.bars = nil end, function(p) p._msufProfileSchema = nil end,
    function(p) p.general.fontKey = false end, function(p) p.shortenNames = nil end }) do
    local truncated = Serial(good)
    edit(truncated)
    local store = { profiles = { Active = Serial(good), Unswitched = truncated } }
    assert(ns.DefaultsSchema.PersistCompat(store), "truncated current profile could not materialize")
    assert(Current650(store.profiles.Unswitched), "revision-17 shortcut accepted an inactive truncated profile")
    assert(H.Literal(store.profiles.Active) == H.Literal(good), "repair changed an already-full peer")
end
for _, invalid in ipairs({ 42, { _msufDefaultsRevision = 99 },
    { _msufDefaultsRevision = 17.5, _msufSparseDefaultsV2 = "broken" } }) do
    local store = { profiles = { Good = Serial(good), Invalid = invalid } }
    local before = H.Literal(store)
    assert(not ns.DefaultsSchema.PersistCompat(store), "unsafe compatibility save accepted")
    assert(H.Literal(store) == before, "compatibility rejection partially rewrote profiles")
end
-- Full compatibility saving also has a zero-allocation steady state.
local store = { profiles = { Full = good }, _compatSave = "armed" }
for _ = 1, 100 do assert(ns.DefaultsSchema.Persist(store)) end
local minimum = math.huge
for _ = 1, 2 do
    collectgarbage("collect")
    ns.DefaultsSchema.Persist(store)
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 100 do ns.DefaultsSchema.Persist(store) end
    minimum = math.min(minimum, (collectgarbage("count") - before) * 1024)
    collectgarbage("restart")
end
assert(minimum == 0, "full compatibility persistence allocated " .. minimum .. " bytes")
print("profile_rollback_compat_smoke: " .. flavor .. " full-save allocation bytes " .. minimum)
print("profile_rollback_compat_smoke: " .. flavor .. " " .. cases .. " corpus cases / " .. profiles .. " profiles byte-identical; arm/off/reload ok")
