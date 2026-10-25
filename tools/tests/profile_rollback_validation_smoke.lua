-- Empty/damaged rollback contents must fail at login and cannot authorize compaction.
local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local C = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local function Copy(v) return assert(loadstring("return " .. H.Literal(v)))() end
local seed = C.NewWorld(root, flavor, "Tester-Realm")
C.Login(seed, {})
local full = Copy(seed.env.MSUF_DB)
for _, damage in ipairs({ "empty-pool", "empty-profile", "scalar-profile", "missing-general", "scalar-owner",
    "sparse", "cycle", "function", "empty-name", "bad-char", "oversize", "truncated", "bad-geometry" }) do
    local backup = { version = 1, source = "full", profiles = { Default = Copy(full) }, char = {} }
    if damage == "empty-pool" then backup.profiles = {}
    elseif damage == "empty-profile" then backup.profiles.Default = {}
    elseif damage == "scalar-profile" then backup.profiles.Default = false
    elseif damage == "missing-general" then backup.profiles.Default.general = nil
    elseif damage == "scalar-owner" then backup.profiles.Default.player = false
    elseif damage == "sparse" then backup.profiles.Default._msufSparseDefaultsV3 = "invalid"
    elseif damage == "cycle" then backup.profiles.Default.future = backup
    elseif damage == "function" then backup.profiles.Default.future = function() end
    elseif damage == "empty-name" then backup.profiles[""] = backup.profiles.Default; backup.profiles.Default = nil
    elseif damage == "bad-char" then backup.char["Tester-Realm"] = false
    elseif damage == "truncated" then backup.profiles.Default = { general = { foo = true }, player = { foo = true } }
    elseif damage == "bad-geometry" then backup.profiles.Default.target.width = false
    elseif damage == "oversize" then backup.profiles.Default.future = string.rep("x", 3 * 1024 * 1024) end
    local account = { profiles = { Default = Copy(full) }, _pre70ProfileBackup = backup }
    local w = C.NewWorld(root, flavor, "Tester-Realm")
    C.Login(w, { MSUF_GlobalDB = account })
    local schema = w.core.DefaultsSchema
    assert(not schema.HasRollbackBackup(account), damage .. ": damaged backup was accepted")
    assert(not schema.CaptureRollbackBackup(account), damage .. ": invalid backup was silently replaced")
    assert(not schema.RestoreRollbackBackup(account), damage .. ": invalid backup was restored")
    local before = H.Literal(account.profiles)
    assert(not schema.Persist(account), damage .. ": damaged backup enabled sparse saving")
    assert(H.Literal(account.profiles) == before, damage .. ": refusal edited live profiles")
end
-- Historical snapshots retain raw pre-normalization values and remain usable.
local historical = 0
for _, entry in ipairs(C.Manifest(root)) do
    local relevant = false
    for _, client in ipairs(entry.clients) do if client == flavor then relevant = true end end
    if relevant and entry.kind == "sv" then
        local saved = C.LoadSavedVariablesFixture(root, entry.file)
        local original = saved.MSUF_GlobalDB and saved.MSUF_GlobalDB.profiles
        if type(original) ~= "table" or next(original) == nil then original = { Default = saved.MSUF_DB } end
        local expected = H.Literal(original)
        local w = C.NewWorld(root, flavor, entry.login or "Tester-Realm")
        C.Login(w, saved)
        local backup = w.env.MSUF_GlobalDB._pre70ProfileBackup
        assert(w.core.DefaultsSchema.HasRollbackBackup(w.env.MSUF_GlobalDB), entry.id .. ": historical snapshot rejected")
        assert(H.Literal(backup.profiles) == expected, entry.id .. ": historical snapshot changed raw data")
        historical = historical + 1
    end
end
-- Secret values are rejected by the shared tree guard before scalar comparisons.
local Secrets = assert(loadfile(root .. "/tools/tests/classpower_secrets.lua"))()
local oldIsSecret = seed.core.Util.IsSecret
seed.core.Util.IsSecret = Secrets.IsSecret
local stop = Secrets.Watch({ root .. "/MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_Recovery.lua" }, { strict = true })
for _, field in ipairs({ "revision", "fontKey", "width", "marker" }) do
    local profile = Copy(full)
    local secret = Secrets.New(field == "fontKey" and "string" or "number")
    if field == "revision" then profile._msufDefaultsRevision = secret
    elseif field == "fontKey" then profile.general.fontKey = secret
    elseif field == "width" then profile.target.width = secret
    else profile._msufSparseDefaultsV3 = secret end
    assert(not seed.core.DefaultsSchema.HasRollbackBackup({ _pre70ProfileBackup = {
        version = 1, source = "full", profiles = { Default = profile }, char = {} } }), "secret snapshot accepted")
end
local violations = stop()
seed.core.Util.IsSecret = oldIsSecret
assert(#violations == 0, table.concat(violations, "\n"))
-- Newly captured full and already-sparse/reconstructed snapshots stay usable.
local schema, account = seed.core.DefaultsSchema, seed.env.MSUF_GlobalDB
assert(schema.HasRollbackBackup(account), "valid full snapshot rejected")
assert(schema.Persist(account))
account._pre70ProfileBackup = nil
assert(schema.CaptureRollbackBackup(account), "reconstructed snapshot rejected")
assert(account._pre70ProfileBackup.source == "reconstructed" and schema.HasRollbackBackup(account))
account._pre70ProfileBackup.profiles = {}
assert(not schema.HasRollbackBackup(account), "post-login corruption escaped validation")
print("PASS profile_rollback_validation_smoke " .. flavor .. " historical=" .. historical)
