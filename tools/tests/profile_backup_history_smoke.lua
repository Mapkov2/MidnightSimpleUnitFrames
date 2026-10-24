-- Every distinct newer revision/content gets an immutable bounded recovery entry.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local C = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local function Copy(value) return assert(loadstring("return " .. H.Literal(value)))() end
local world = C.NewWorld(root, flavor, "Tester-Realm")
C.Login(world, {})
local schema, account = world.core.DefaultsSchema, world.env.MSUF_GlobalDB
local originals, snapshots = {}, {}
for index, revision in ipairs({ 18, 19, 19, 20 }) do
    local profile = Copy(world.env.MSUF_DB)
    profile._msufDefaultsRevision = revision
    profile.future = { version = index, zero = 0, flag = false, text = "future\nbytes", list = { 1, true, {} } }
    originals[index] = H.Literal(profile)
    account.profiles.Future = profile
    schema.RestorePersistence(profile)
    local bucket = assert(account._newerRevisionBackups.Future)
    assert(type(bucket.entries) == "table" and type(bucket.order) == "table", "no versioned history")
    local key = bucket.order[#bucket.order]
    local entry = assert(bucket.entries[key])
    snapshots[index] = { key = key, entry = entry }
    assert(entry.revision == revision and H.Literal(entry.data) == originals[index], "snapshot lost original bytes")
    assert(type(entry.hash) == "string" and key:find(entry.hash, 1, true), "key lacks content hash")
    assert(key:find(tostring(bucket.identity), 1, true), "key lacks profile identity")
    local bytes = H.Literal(bucket)
    schema.RestorePersistence(profile)
    assert(H.Literal(bucket) == bytes, "duplicate bind changed immutable history")
    assert(#bucket.order == math.min(index, 3), "history is not bounded to three entries")
end
local bucket = account._newerRevisionBackups.Future
assert(bucket.entries[snapshots[1].key] == nil, "oldest snapshot not evicted")
for index = 2, 4 do
    local entry = assert(bucket.entries[snapshots[index].key])
    assert(entry == snapshots[index].entry and H.Literal(entry.data) == originals[index], "later revision overwrote a snapshot")
end
local bytes = H.Literal(bucket)
local restored = assert(schema.RestoreProfileBackup("Future", snapshots[2].key))
assert(restored == account.profiles.Future and H.Literal(restored) == originals[2], "restore did not recover exact bytes")
assert(restored ~= snapshots[2].entry.data and restored.future ~= snapshots[2].entry.data.future, "restore aliases backup")
restored.future.version = 99
assert(H.Literal(bucket) == bytes, "editing restored profile mutated history")
assert(not schema.RestoreProfileBackup("Future", "unknown"), "unknown backup key accepted")
-- Upgrade the previous one-entry layout without losing its original snapshot.
account._newerRevisionBackups.Legacy = { revision = 18, data = Copy(snapshots[2].entry.data) }
account.profiles.Legacy = Copy(snapshots[4].entry.data)
schema.RestorePersistence(account.profiles.Legacy)
assert(#account._newerRevisionBackups.Legacy.order == 2, "legacy backup was not retained on upgrade")
local identity = bucket.identity
assert(world.core.PublicGlobals.MSUF_RenameProfile("Future", "Renamed"))
assert(account._newerRevisionBackups.Renamed == bucket and bucket.identity == identity, "rename lost profile identity/history")
assert(account._newerRevisionBackups.Future == nil, "rename left stale named history")
assert(world.core.PublicGlobals.MSUF_DeleteProfile("Renamed"))
assert(world.core.PublicGlobals.MSUF_CreateProfile("Renamed"))
account.profiles.Renamed._msufDefaultsRevision = 21
schema.RestorePersistence(account.profiles.Renamed)
assert(account._newerRevisionBackups.Renamed.identity ~= identity, "recreated profile reused deleted identity")
local archived = assert(schema.RestoreProfileBackup("Recovered", snapshots[2].key))
assert(H.Literal(archived) == originals[2], "deleted profile history cannot be restored")
account.profiles.LegacyRestore = Copy(world.env.MSUF_DB)
account._newerRevisionBackups.LegacyRestore = { revision = 18, data = Copy(snapshots[2].entry.data) }
assert(H.Literal(assert(schema.RestoreProfileBackup("LegacyRestore"))) == originals[2], "legacy snapshot cannot be restored before upgrade")
-- A pre-upgrade backup can outlive the already-normalized revision-17 profile.
account.profiles.Old = Copy(world.env.MSUF_DB)
account._newerRevisionBackups.Old = { revision = 18, data = Copy(snapshots[2].entry.data) }
assert(world.core.PublicGlobals.MSUF_DeleteProfile("Old"), "cannot delete a profile with a legacy backup")
local archivedLegacy
for _, saved in pairs(account._profileRecoveryArchive._newerRevisionBackups) do
    if saved.revision == 18 and H.Literal(saved.data) == originals[2] then archivedLegacy = saved end
end
assert(archivedLegacy and #archivedLegacy.order == 1, "legacy backup vanished during deletion")
assert(schema.RestoreProfileBackup("RecoveredLegacy", archivedLegacy.order[1]), "legacy archived snapshot cannot be restored")
print("PASS profile_backup_history_smoke " .. flavor)
