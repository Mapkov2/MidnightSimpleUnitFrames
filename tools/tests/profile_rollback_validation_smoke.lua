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
-- A serialized stamp avoids another whole-tree scan, but never authorizes the
-- account's first sparse save without a fresh content preflight.
local stamped = Copy(seed.env.MSUF_GlobalDB)
local stamp = assert(stamped._pre70ProfileBackup.validation, "snapshot validation stamp missing")
assert(stamp.generator == 1 and stamp.bytes > 0 and type(stamp.key) == "string")
for _, damage in ipairs({ "missing", "generator", "size", "key" }) do
    local account = Copy(stamped)
    local backup = account._pre70ProfileBackup
    if damage == "missing" then backup.validation = nil
    elseif damage == "generator" then backup.validation.generator = -1
    elseif damage == "size" then backup.validation.bytes = -1
    else backup.validation.key = "corrupted" end
    -- An inconsistent stamp must reach the full validator, not refresh itself
    -- from the remaining superficially valid compatibility fields.
    backup.profiles.Default.future = function() end
    assert(not seed.core.DefaultsSchema.HasRollbackBackup(account), damage .. ": stamp bypassed full validation")
end
for _, damage in ipairs({ "missing", "generator", "size", "key" }) do
    local account = Copy(stamped)
    local backup = account._pre70ProfileBackup
    if damage == "missing" then backup.validation = nil
    elseif damage == "generator" then backup.validation.generator = -1
    elseif damage == "size" then backup.validation.bytes = -1
    else backup.validation.key = "corrupted" end
    assert(seed.core.DefaultsSchema.HasRollbackBackup(account), damage .. ": valid legacy snapshot not upgraded")
    assert(backup.validation.generator == 1 and backup.validation.bytes > 0 and backup.validation.key ~= "corrupted")
end
local damaged = Copy(stamped)
damaged._pre70ProfileBackup.profiles.Hidden = { bad = true }
local oldAccount = seed.env.MSUF_GlobalDB
seed.env.MSUF_GlobalDB = damaged
local before = H.Literal(damaged.profiles)
assert(not seed.core.DefaultsSchema.Persist(damaged), "stamp authorized first sparse save with a damaged secondary profile")
assert(damaged._pre70SparseValidated == nil and H.Literal(damaged.profiles) == before)
seed.env.MSUF_GlobalDB = oldAccount
local disk = Copy(stamped)
local reload = C.NewWorld(root, flavor, "Tester-Realm")
C.Login(reload, { MSUF_GlobalDB = disk })
assert(H.Literal(disk._pre70ProfileBackup) == H.Literal(stamped._pre70ProfileBackup), "reload rewrote valid snapshot stamp")
assert(reload.core.DefaultsSchema.Persist(disk), "first sparse preflight refused a valid snapshot")
assert(disk._pre70SparseValidated == disk._pre70ProfileBackup.validation.key, "first sparse preflight was not recorded")
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
for _, field in ipairs({ "generator", "bytes", "profile", "key", "source", "legacy", "width", "bars" }) do
    local account = Copy(stamped)
    local backup = account._pre70ProfileBackup
    local secret = Secrets.New("number")
    if field == "source" or field == "legacy" then backup[field] = secret
    elseif field == "width" then backup.profiles.Default.target.width = secret
    elseif field == "bars" then backup.profiles.Default.bars = secret
    else backup.validation[field] = secret end
    assert(not seed.core.DefaultsSchema.HasRollbackBackup(account), "secret stamped snapshot accepted: " .. field)
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
