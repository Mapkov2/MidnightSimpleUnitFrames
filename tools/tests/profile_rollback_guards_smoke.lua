-- Recovery must obey profile-edit ownership and bound reconstructed data.
local root, flavor = assert(arg[1]), assert(arg[2])
local C = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local w = C.NewWorld(root, flavor, "Tester-Realm")
C.Login(w, {})
local ns, env = w.core, w.env
assert(ns.ProfileVariants.Replace(env.MSUF_DB, { version = 1, entries = {
    { name = "Editing", conditions = { context = "raid" }, patch = { { path = { "player", "width" }, value = 321 } } },
} }))
assert(ns.ProfileVariants.BeginRecording("Editing"))
local pool, active, profile = env.MSUF_GlobalDB.profiles, env.MSUF_ActiveProfile, env.MSUF_DB
local before = H.Literal(pool)
ns.SlashCommands.Dispatch("restorebackup")
local ok, why = pcall(ns.SlashCommands.Dispatch, "restorebackup confirm")
assert(ok, "restore refusal raised an error: " .. tostring(why))
assert(env.MSUF_GlobalDB.profiles == pool and env.MSUF_DB == profile and env.MSUF_ActiveProfile == active,
    "restore replaced account/binding during variant recording")
assert(H.Literal(pool) == before and ns.ProfileVariants.IsRecording(), "restore changed the active recording")
assert(ns.ProfileVariants.CancelRecording(false))
local store = { profiles = {} }
for i = 1, 24 do store.profiles["Profile" .. i] = C.Copy(env.MSUF_DB) end
assert(select(2, ns.DefaultsSchema.Persist(store)) > 0, "reconstruction-bound fixture was not sparse")
assert(#H.Literal(store) < 1024 * 1024, "sparse fixture itself is oversize")
local sparse = H.Literal(store)
assert(not ns.DefaultsSchema.CaptureRollbackBackup(store), "expanded full snapshot exceeded its budget")
assert(store._pre70ProfileBackup == nil and H.Literal(store) == sparse, "expanded size rejection changed input")
print("profile_rollback_guards_smoke: " .. flavor .. " variant-edit ownership / expanded snapshot bound ok")
