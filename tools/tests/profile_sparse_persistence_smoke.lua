-- Actual logout, serialized reload, identities and conservative full retention.
local root, flavor = assert(arg[1]), assert(arg[2])
local C = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local function Serial(value) return assert(loadstring("return " .. H.Literal(value)))() end
local function World(saved)
    local w = C.NewWorld(root, flavor, "Tester-Realm")
    C.Login(w, saved or {})
    return w, w.env, w.core
end
local w = C.NewWorld(root, flavor, "Tester-Realm")
assert(w.core.DefaultsStorageData.sparseV3Owners == nil,
    "sparse codec expanded its logout dictionaries at file load")
local early = w.env.CreateFrame("Frame")
local earlyAlias, earlyDefault
-- This consumer registers before the lifecycle's terminal native handlers.
early:RegisterEvent("PLAYER_LOGOUT")
early:SetScript("OnEvent", function()
    earlyAlias = w.env.MSUF_DB
    earlyDefault = earlyAlias.general.previewDragHintAnimationEnabled
end)
C.Login(w, {})
local env, ns = w.env, w.core
local profile, general, target = env.MSUF_DB, env.MSUF_DB.general, env.MSUF_DB.target
assert(profile == env.MSUF_GlobalDB.profiles[env.MSUF_ActiveProfile], "active identity differs")
assert(getmetatable(profile) == nil and getmetatable(general) == nil, "runtime needs proxy tables")
local pool = env.MSUF_GlobalDB.profiles
local factoryTemplate = Serial(profile)
-- Every explicit override is retained, including non-boolean historical values.
local values = { false, 0, "", {}, { false, 0, "" } }
local markerBudget = assert(loadfile(root .. "/tools/tests/profile_sparse_preview_marker.lua"))()(root, flavor, C, H)
for index, value in ipairs(values) do
    local copy = C.Copy(profile)
    copy.general.showGameMenuButton = C.Copy(value)
    copy.general.previewDragHintAnimationEnabled = C.Copy(value)
    copy.player.width = C.Copy(value)
    copy.general.unknownSparseTestValue = { false, 0, "", {}, [0] = "zero" }
    copy.general.castbarShowPushback = nil
    pool["Override" .. index] = copy
end
profile.general.showGameMenuButton = false
local guarded = C.Copy(factoryTemplate)
guarded.npcColors.legacySentinel = "keep"
guarded.general.castbarShowPushback = nil
pool.LegacySentinel = guarded
local before = Serial(env.MSUF_GlobalDB)
local bytes = #H.Literal(before.profiles)
assert(ns.ProfileVariants.Replace(profile, { version = 1, entries = {
    { name = "Menu", patch = { { path = { "general", "showGameMenuButton" }, value = true } } },
} }))
assert(profile.general.showGameMenuButton == true, "variant did not materialize")
local reference = Serial(env.MSUF_GlobalDB)
reference.profiles[env.MSUF_ActiveProfile].general.showGameMenuButton = false
bytes = #H.Literal(reference.profiles)
local observer = env.CreateFrame("Frame")
local seen
observer:RegisterEvent("PLAYER_LOGOUT")
observer:SetScript("OnEvent", function()
    seen = env.MSUF_GlobalDB.profiles[env.MSUF_ActiveProfile] == profile
end)
w:FireEvent("PLAYER_LOGOUT")
assert(env.MSUF_GlobalDB._pre70SparseValidated == nil,
    "session safety preflight leaked into SavedVariables")
assert(rawget(env, "MSUF_DB") == nil, "duplicate public SavedVariable survived")
assert(earlyAlias == profile and earlyDefault == true, "pruning ran before earlier logout consumers")
assert(seen and pool[env.MSUF_ActiveProfile] == profile, "terminal snapshot replaced stored profile")
assert(profile.general == general and profile.target == target, "nested identity changed")
assert(general.showGameMenuButton == false and general.previewDragHintAnimationEnabled == nil, "variant base/omission differs")
assert(#H.Literal(env.MSUF_GlobalDB.profiles) < bytes, "terminal serialization did not shrink")
for index, value in ipairs(values) do
    local copy = pool["Override" .. index]
    assert(H.Literal(copy.general.showGameMenuButton) == H.Literal(value), "explicit override removed")
    assert(H.Literal(copy.general.previewDragHintAnimationEnabled) == H.Literal(value), "second override removed")
    assert(H.Literal(copy.player.width) == H.Literal(value), "typed numeric-field override removed")
    assert(copy.general.castbarShowPushback == nil, "nil-sensitive field filled")
    assert(copy.general.unknownSparseTestValue[0] == "zero", "unknown data removed")
end
assert(pool.LegacySentinel.npcColors.legacySentinel == "keep", "a custom sentinel entered factory pruning")
assert(pool.LegacySentinel.general.castbarShowPushback == nil, "factory pruning filled an intentional absence")
-- Decode the actual stored mask before migrations can conceal any changed field.
local decoded = Serial(env.MSUF_GlobalDB)
for _, stored in pairs(decoded.profiles) do
    assert(stored._msufDefaultsRevision == 17.5 and type(stored._msufSparseDefaultsV2) == "string", "V2 stamps missing")
    assert(ns.DefaultsSchema.RestorePersistence(stored), "V2 restore refused a saved profile")
end
assert(H.Literal(decoded) == H.Literal(reference), "exact pre-migration V2 roundtrip differs")
local _, reloaded = World({ MSUF_GlobalDB = Serial(env.MSUF_GlobalDB) })
local _, control = World({ MSUF_GlobalDB = reference })
assert(H.Literal(reloaded.MSUF_GlobalDB) == H.Literal(control.MSUF_GlobalDB), "serialized current reload differs")
assert(reloaded.MSUF_DB == reloaded.MSUF_GlobalDB.profiles[reloaded.MSUF_ActiveProfile], "reloaded identity differs")
-- Unknown data and absent leaves survive broader, presence-masked factory elision.
local factoryStore = { profiles = { Default = Serial(factoryTemplate) } }
assert(ns.DefaultsSchema.Persist(factoryStore))
assert(factoryStore.profiles.Default.npcColors ~= nil, "factory pruning forced destination repair")
local sparseTemplate = Serial(factoryStore.profiles.Default)
assert(sparseTemplate._msufDefaultsRevision == 17.5 and type(sparseTemplate._msufSparseDefaultsV2) == "string")
local cold = C.NewWorld(root, flavor, "Tester-Realm")
assert(cold.core.DefaultsStorageData.sparseV3Owners == nil, "cold codec was already initialized")
local coldProfile = Serial(sparseTemplate)
assert(cold.core.DefaultsSchema.RestorePersistence(coldProfile), "first sparse restore did not initialize the codec")
assert(H.Literal(coldProfile) == H.Literal(factoryTemplate), "cold sparse restore changed wire values")
local coldOwners = assert(cold.core.DefaultsStorageData.sparseV3Owners)
assert(cold.core.DefaultsSchema.Persist({ profiles = { Default = coldProfile } }))
assert(cold.core.DefaultsStorageData.sparseV3Owners == coldOwners, "warm persistence rebuilt its dictionaries")
local unchanged = H.Literal(factoryStore)
local repeated, count = ns.DefaultsSchema.Persist(factoryStore)
assert(repeated and count == 0 and H.Literal(factoryStore) == unchanged, "sparse persistence is not idempotent")
assert(ns.DefaultsSchema.RestorePersistence(factoryStore.profiles.Default))
assert(H.Literal(factoryStore.profiles.Default) == H.Literal(factoryTemplate), "factory V2 roundtrip differs")
-- An ineligible profile stays full while independent valid profiles may compact.
local full = Serial(before)
full.profiles.Malformed = { general = "wrong" }
local saved = H.Literal(full)
local accepted, removed = ns.DefaultsSchema.Persist(full)
assert(accepted and removed > 0, "independent valid profiles did not compact")
assert(H.Literal(full.profiles.Malformed) == H.Literal({ general = "wrong" }), "malformed profile changed")
for _, stored in pairs(full.profiles) do
    if stored._msufSparseDefaultsV2 ~= nil then assert(ns.DefaultsSchema.RestorePersistence(stored)) end
end
assert(H.Literal(full) == saved, "per-profile fallback changed the full store")
local secret = {}
local realSecret = ns.Util.IsSecret
ns.Util.IsSecret = function(value) return value == secret end
full.profiles.Malformed = nil
full.profiles.Default.general.showGameMenuButton = secret
local unknown = full.profiles.Default.general.previewDragHintAnimationEnabled
local secretSnapshot = H.Literal(full)
local accepted, removed = ns.DefaultsSchema.Persist(full)
assert(accepted and removed == 0, "secret settings entered sparse persistence")
assert(H.Literal(full) == secretSnapshot, "secret rejection changed the store")
assert(full.profiles.Default.general.previewDragHintAnimationEnabled == unknown, "secret failure partly pruned")
ns.Util.IsSecret = realSecret
local trap = setmetatable({}, { __index = function() error("metatable invoked") end })
assert(not ns.DefaultsSchema.Persist(trap), "metatable store was accepted")
-- Aliases of every edited ancestor keep the complete profile untouched.
local function Fallback(label, edit)
    local store = { profiles = { One = Serial(factoryTemplate) } }
    edit(store, store.profiles.One)
    local text = H.Literal(store)
    local ok, count = ns.DefaultsSchema.Persist(store)
    assert(ok and count == 0 and H.Literal(store) == text, label .. " failed full fallback")
end
Fallback("profiles alias", function(s) s.backup = s.profiles end)
Fallback("profile alias", function(s, p) s.profiles.Two = p end)
Fallback("owner alias", function(s, p) s.backup = p.general end)
Fallback("ancestor alias", function(s, p) s.backup = p.auras3 end)
Fallback("old full revision", function(s, p) p._msufDefaultsRevision = 15 end)
Fallback("unknown metadata", function(s, p) p._msufSparseDefaultsV2 = "future" end)

local listed = Serial(factoryTemplate)
listed.player[1] = { height = 20, enabled = true }
listed.general.userSettings = { fontSize = 12, enabled = true, spells = { [12345] = { size = 20 } } }
listed.auras3[1] = "list ancestor"
listed.general.fontSize = nil
local listedBefore = H.Literal(listed)
local playerBefore, auraBefore = H.Literal(listed.player), H.Literal(listed.auras3)
assert(select(2, ns.DefaultsSchema.Persist({ profiles = { One = listed } })) > 0)
assert(H.Literal(listed.player) == playerBefore and H.Literal(listed.auras3) == auraBefore, "list subtree elided")
assert(listed.general.fontSize == nil, "absent default materialized during persistence")
assert(ns.DefaultsSchema.RestorePersistence(listed))
assert(H.Literal(listed) == listedBefore, "list/user/spell/absence roundtrip changed a value")

-- V1 numeric and string representations retain the frozen dictionary and typed overrides.
local legacyResults = {}
for _, stamp in ipairs({ 17.5, "MSUF_SPARSE_DEFAULTS_1" }) do
    local old = { _msufDefaultsRevision = stamp, general = { fontSize = 0, fontOutline = "", showGameMenuButton = false },
        gf_party = {}, gf_raid = {}, gf_mythicraid = {}, unknown = { false, 0, "", [12345] = true } }
    assert(ns.DefaultsSchema.RestorePersistence(old), "legacy V1 representation refused")
    assert(old._msufDefaultsRevision == 17 and old._msufSparseDefaultsV2 == nil, "legacy V1 stamp not consumed")
    assert(old.general.previewDragHintAnimationEnabled == true and old.gf_party.showHPText == true, "legacy defaults missing")
    assert(old.general.showGameMenuButton == false and old.general.fontSize == 0 and old.general.fontOutline == "")
    assert(H.Literal(old.unknown) == H.Literal({ false, 0, "", [12345] = true }), "legacy unknown changed")
    assert(old.player == nil and old.auras3 == nil, "V1 expanded into the V2 dictionary")
    legacyResults[#legacyResults + 1] = H.Literal(old)
end
assert(legacyResults[1] == legacyResults[2], "V1 numeric/string results differ")

local mask = sparseTemplate._msufSparseDefaultsV2
for _, bad in ipairs({ false, 0, "", "future", {}, string.rep("0", #mask), string.rep("g", #mask), mask:sub(1, -2) .. "f" }) do
    local broken = Serial(sparseTemplate)
    broken._msufSparseDefaultsV2 = bad
    local text = H.Literal(broken)
    assert(not ns.DefaultsSchema.RestorePersistence(broken), "invalid V2 metadata accepted")
    assert(H.Literal(broken) == text, "invalid V2 metadata changed values or fell back to V1")
end
for _, edit in ipairs({ function(p) p.general = nil end, function(p) p._msufDefaultsRevision = 18 end }) do
    local broken = Serial(sparseTemplate)
    edit(broken)
    local text = H.Literal(broken)
    assert(not ns.DefaultsSchema.RestorePersistence(broken) and H.Literal(broken) == text, "invalid V2 owner/revision changed")
end
local overrides = Serial(sparseTemplate)
overrides.general.previewDragHintAnimationEnabled = false
overrides.general.fontSize = 0
overrides.general.fontOutline = ""
assert(ns.DefaultsSchema.RestorePersistence(overrides))
assert(overrides.general.previewDragHintAnimationEnabled == false and overrides.general.fontSize == 0
    and overrides.general.fontOutline == "", "V2 restore overwrote explicit typed values")
print("profile_sparse_persistence_smoke: " .. flavor .. " FUNCTIONAL_PASS V2/V1/typed/list/alias/roundtrip")

local function PersistenceBudget()
-- The terminal passes allocate no tables, including when defaults are removed.
local measured = Serial(before)
local owner = measured.profiles.Default.general
for _ = 1, 100 do
    owner.showGameMenuButton, owner.previewDragHintAnimationEnabled = true, true
    assert(ns.DefaultsSchema.Persist(measured))
end
local minimum = math.huge
for _ = 1, 2 do
    collectgarbage("collect")
    -- A full collect turns the cleared keys of the reused walk scratch into dead
    -- keys; the first walk after it re-seats them once. Measure the steady state.
    ns.DefaultsSchema.Persist(measured)
    collectgarbage("stop")
    local memory = collectgarbage("count")
    for _ = 1, 100 do
        owner.showGameMenuButton, owner.previewDragHintAnimationEnabled = true, true
        ns.DefaultsSchema.Persist(measured)
    end
    local allocated = (collectgarbage("count") - memory) * 1024
    collectgarbage("restart")
    if allocated < minimum then minimum = allocated end
end
assert(minimum == 0, "terminal persistence allocated " .. minimum .. " bytes")
print("profile_sparse_persistence_smoke: allocation bytes " .. minimum)
end
-- Run both original zero-allocation contracts even if one is red; never waive either.
local budgetFailures = {}
for _, check in ipairs({ PersistenceBudget, markerBudget }) do
    local ok, why = pcall(check)
    if not ok then budgetFailures[#budgetFailures + 1] = tostring(why) end
end
assert(#budgetFailures == 0, table.concat(budgetFailures, "\n"))
print("profile_sparse_persistence_smoke: " .. flavor .. " ok")
