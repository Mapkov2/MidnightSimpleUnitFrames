-- Refused newer-profile backups keep stored bytes and bind one detached session copy.
local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local C = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local function Copy(v) return assert(loadstring("return " .. H.Literal(v)))() end
local seed = C.NewWorld(root, flavor, "Tester-Realm")
C.Login(seed, {})
for _, mode in ipairs({ "pool", "standalone", "empty-pool", "missing-active" }) do
    local profile = Copy(seed.env.MSUF_DB)
    profile._msufDefaultsRevision = 19
    profile.general.barBgFillMode = "future-value"
    profile.future = string.rep("X", 1100000)
    local original = H.Literal(profile)
    local saved = { MSUF_GlobalDB = { profiles = { Default = profile } } }
    if mode == "standalone" then saved = { MSUF_DB = profile }
    elseif mode == "empty-pool" then saved = { MSUF_DB = profile, MSUF_GlobalDB = { profiles = {} } }
    elseif mode == "missing-active" then
        saved = { MSUF_GlobalDB = { profiles = { Donor = profile },
            char = { ["Tester-Realm"] = { activeProfile = "Missing" } } } }
    end
    local world = C.NewWorld(root, flavor, "Tester-Realm")
    C.Login(world, saved)
    local env, ns = world.env, world.core
    local name = mode == "missing-active" and "Missing" or "Default"
    local stored = assert(env.MSUF_GlobalDB.profiles[name])
    assert(H.Literal(stored) == original and H.Literal(profile) == original, mode .. ": original was normalized without backup")
    assert(env.MSUF_DB ~= stored and env.MSUF_DB.general ~= stored.general, mode .. ": runtime aliases original")
    assert(ns.DefaultsSchema.IsQuarantinedProfile(stored) and ns.DefaultsSchema.IsQuarantinedProfile(env.MSUF_DB))
    assert(env.MSUF_DB._msufDefaultsRevision == 17, "session copy lacks usable defaults")
    local notices = #world.prints
    local sawNotice = false
    for _, text in ipairs(world.prints) do
        if text:find("session copy", 1, true) then sawNotice = true end
    end
    assert(sawNotice, "backup refusal was silent")
    local active = env.MSUF_DB
    active.general.sessionEdit = 123
    ns.ProfileMigrations.PrepareBinding(stored)
    ns.PublicGlobals.MSUF_InitProfiles()
    assert(env.MSUF_DB == active and env.MSUF_DB.general.sessionEdit == 123, "repeat bind lost detached session")
    assert(#world.prints == notices, "repeat bind repeated refusal notice")
    local rows = ns.DefaultsSchema.ListProfileRecovery()
    assert(#rows == 0, "oversized backup bypassed recovery bound")
    world:FireEvent("PLAYER_LOGOUT")
    assert(H.Literal(stored) == original, "logout changed quarantined original")
    assert(env.MSUF_DB == nil, "logout retained runtime alias")
    local reload = C.NewWorld(root, flavor, "Tester-Realm")
    C.Login(reload, { MSUF_GlobalDB = Copy(env.MSUF_GlobalDB) })
    assert(H.Literal(reload.env.MSUF_GlobalDB.profiles[name]) == original, "reload changed original")
end
-- An existing exact snapshot is success, not a refused duplicate.
local w = C.NewWorld(root, flavor, "Tester-Realm")
C.Login(w, {})
local p = Copy(seed.env.MSUF_DB)
p._msufDefaultsRevision = 19
p.general.barBgFillMode = "future-value"
w.env.MSUF_GlobalDB.profiles.Future = p
w.env.MSUF_GlobalDB._newerRevisionBackups = { Future = { identity = 42, order = {},
    entries = { orphan = { data = { future = string.rep("X", 2 * 1024 * 1024) } } } } }
local original = H.Literal(p)
local detached, _, status = w.core.ProfileNormalize.TranslateProfileToCurrent(p)
assert(status == "rejected", "evicted malformed bucket was counted as a retained backup")
assert(detached ~= p and H.Literal(p) == original, "detached backup bucket allowed lossy normalization")
w.env.MSUF_GlobalDB.profiles.Future = Copy(seed.env.MSUF_DB)
p = w.env.MSUF_GlobalDB.profiles.Future
p._msufDefaultsRevision = 19
assert(w.core.DefaultsSchema.BackupNewerRevision(p) ~= false)
assert(w.core.DefaultsSchema.BackupNewerRevision(p) ~= false, "duplicate backup was treated as refusal")
assert(not w.core.DefaultsSchema.IsQuarantinedProfile(p))
print("PASS profile_backup_refusal_smoke " .. flavor)
