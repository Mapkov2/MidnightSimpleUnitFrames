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
for index, value in ipairs(values) do
    local copy = C.Copy(profile)
    copy.general.showGameMenuButton = C.Copy(value)
    copy.general.previewDragHintAnimationEnabled = C.Copy(value)
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
    assert(copy.general.castbarShowPushback == nil, "nil-sensitive field filled")
    assert(copy.general.unknownSparseTestValue[0] == "zero", "unknown data removed")
end
assert(pool.LegacySentinel.npcColors.legacySentinel == "keep", "a custom sentinel entered factory pruning")
assert(pool.LegacySentinel.general.castbarShowPushback == nil, "factory pruning filled an intentional absence")
assert(pool.LegacySentinel.target.width == factoryTemplate.target.width, "non-factory defaults were pruned")
local _, reloaded = World({ MSUF_GlobalDB = Serial(env.MSUF_GlobalDB) })
local _, control = World({ MSUF_GlobalDB = reference })
assert(H.Literal(reloaded.MSUF_GlobalDB) == H.Literal(control.MSUF_GlobalDB), "serialized current reload differs")
assert(reloaded.MSUF_DB == reloaded.MSUF_GlobalDB.profiles[reloaded.MSUF_ActiveProfile], "reloaded identity differs")
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
-- Factory defaults also stay fully represented when repair is not portable.
local factoryStore = { profiles = { Default = Serial(factoryTemplate) } }
assert(ns.DefaultsSchema.Persist(factoryStore))
assert(factoryStore.profiles.Default.npcColors ~= nil, "factory pruning forced destination repair")
assert(factoryStore.profiles.Default.target.width == factoryTemplate.target.width, "uncertified factory value omitted")
-- The plan is transactional: a malformed late profile cannot partially prune an earlier one.
local full = Serial(before)
full.profiles.Malformed = { general = "wrong" }
local saved = H.Literal(full)
assert(not ns.DefaultsSchema.Persist(full), "malformed store was pruned")
assert(H.Literal(full) == saved, "a failed plan changed the store")
local secret = {}
local realSecret = ns.Util.IsSecret
ns.Util.IsSecret = function(value) return value == secret end
full.profiles.Malformed = nil
full.profiles.Default.general.showGameMenuButton = secret
local unknown = full.profiles.Default.general.previewDragHintAnimationEnabled
assert(not ns.DefaultsSchema.Persist(full), "secret settings were inspected")
assert(full.profiles.Default.general.previewDragHintAnimationEnabled == unknown, "secret failure partly pruned")
ns.Util.IsSecret = realSecret
local trap = setmetatable({}, { __index = function() error("metatable invoked") end })
assert(not ns.DefaultsSchema.Persist(trap), "metatable store was accepted")
print("profile_sparse_persistence_smoke: " .. flavor .. " ok")
