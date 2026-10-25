-- A persisted approval never replaces the first sparse preflight of a new session.
local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local C = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local function Serial(value) return assert(loadstring("return " .. H.Literal(value)))() end
local function Login(account)
    local world = C.NewWorld(root, flavor, "Tester-Realm")
    C.Login(world, account and { MSUF_GlobalDB = account } or {})
    return world, world.core.DefaultsSchema, world.env.MSUF_GlobalDB
end
local seed, schema, account = Login()
-- Capture two complete originals before sparse saving has ever been enabled.
account.profiles.Other = Serial(seed.env.MSUF_DB)
account._pre70ProfileBackup = nil
assert(schema.CaptureRollbackBackup(account))
assert(schema.Persist(account), "initial sparse save refused")
local approved = Serial(account)
local backup = approved._pre70ProfileBackup
approved._pre70SparseValidated = backup.validation.key -- legacy disk approval
local anchor = assert(backup.validation.profile)
local other = anchor == "Other" and "Default" or "Other"
assert(backup.profiles[other], "test requires a non-anchor original")
-- Damage occurs AFTER the first sparse enable, survives serialization and reload.
backup.profiles[other].general = nil
local world, current, damaged = Login(Serial(approved))
local before = H.Literal(damaged.profiles)
local notices = #world.prints
local ok, removed = current.Persist(damaged)
assert(not ok, "previous session approval authorized sparse saving on a damaged secondary backup")
assert(not removed or removed == 0, "damaged backup permitted default removal")
assert(H.Literal(damaged.profiles) == before, "failed preflight rewrote live profiles")
assert(not current.RestoreRollbackBackup(damaged), "damaged original unexpectedly restored")
assert(#world.prints == notices + 1, "sparse refusal did not tell the user once")
assert(not current.Persist(damaged))
assert(#world.prints == notices + 1, "repeated sparse refusal repeated the notice")
-- A session result is retained only in memory: serialized old stamps cannot
-- authorize new sessions, and the new implementation writes no approval stamp.
local good = Serial(account)
good._pre70SparseValidated = nil
local validWorld, validSchema, valid = Login(good)
assert(validSchema.Persist(valid), "valid backup failed deferred preflight")
assert(valid._pre70SparseValidated == nil, "session approval leaked into SavedVariables")
-- Count full Safe walks by observing the existing secret guard, without
-- replacing validation, persistence, or any of their inner implementations.
local calls, isSecret = 0, validWorld.core.Util.IsSecret
validWorld.core.Util.IsSecret = function(value) calls = calls + 1; return isSecret(value) end
assert(validSchema.HasRollbackBackup(valid, true))
assert(calls < 100, "successful session approval walked the snapshot again")
print("PASS profile_rollback_session_validation_smoke " .. flavor)
