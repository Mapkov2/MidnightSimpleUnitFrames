-- Recovery is bounded across live and deleted identities, with explicit management.
local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local C = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local w = C.NewWorld(root, flavor, "Tester-Realm")
C.Login(w, {})
local schema, store = w.core.DefaultsSchema, w.env.MSUF_GlobalDB
assert(type(schema.ListProfileRecovery) == "function", "account recovery budget/management missing")

-- SavedVariables serializes a shared recovery payload separately at each path.
local function ReloadedBucket(key, identity)
    local data = { list = { false, 0, "" }, keyed = { [0] = "zero", [12345] = { enabled = false } } }
    local bucket = { identity = identity, order = { key }, revision = 20, data = data,
        entries = { [key] = { sequence = identity, revision = 20, data = data } } }
    return assert(loadstring("return " .. H.Literal(bucket)))()
end
local function Latest(bucket)
    return bucket.entries[bucket.order[#bucket.order]].data
end
local named = ReloadedBucket("named", 1)
local archived = ReloadedBucket("archived", 2)
local differing = ReloadedBucket("different", 3)
differing.data.list[2] = false
local otherRevision = ReloadedBucket("other-revision", 4)
otherRevision.revision = 19
store._newerRevisionBackups = { Named = named, Different = differing }
store._profileRecoveryArchive = { _rejectedProfileBackups = { [2] = archived, [4] = otherRevision } }
local beforeRows, beforeBytes = schema.ListProfileRecovery()
local beforeDisk = H.Literal(store._profileRecoveryArchive)
local beforeNamed = H.Literal(store._newerRevisionBackups)
local beforeExport = assert(schema.ExportProfileRecovery("archived"))
assert(named.data ~= Latest(named) and archived.data ~= Latest(archived), "fixture already shares a payload")
schema.BeginRollbackSession(store)
assert(rawequal(named.data, Latest(named)), "startup kept duplicate named recovery data")
assert(rawequal(archived.data, Latest(archived)), "startup kept duplicate archived recovery data")
assert(differing.data ~= Latest(differing) and differing.data.list[2] == false, "startup replaced differing data")
assert(otherRevision.data ~= Latest(otherRevision), "startup replaced a differing revision")
local afterRows, afterBytes = schema.ListProfileRecovery()
assert(#afterRows == #beforeRows and beforeBytes == afterBytes, "sharing changed the recovery byte budget")
assert(H.Literal(store._profileRecoveryArchive) == beforeDisk, "sharing changed the serialized archive")
assert(H.Literal(store._newerRevisionBackups) == beforeNamed, "sharing changed the serialized named archive")
assert(schema.ExportProfileRecovery("archived") == beforeExport, "sharing changed exported bytes")
local restored = assert(schema.RestoreProfileBackup("Restored", "archived", "rejected"))
assert(restored ~= archived.data and restored.keyed ~= archived.data.keyed, "restore exposes aliased mutable data")
assert(H.Literal(restored) == H.Literal(archived.data), "shared payload cannot be restored")
store.profiles.Restored = nil
assert(schema.PurgeProfileRecovery("all") == #afterRows)

local first, last
for i = 1, 16 do
    local p = { _msufDefaultsRevision = 20, future = string.rep(string.char(64 + i), 120000), zero = 0, flag = false }
    store.profiles.Future = p
    schema.BackupNewerRevision(p)
    local bucket = assert(store._newerRevisionBackups.Future)
    first, last = first or bucket.order[1], bucket.order[1]
    schema.RenameProfileRecovery("Future")
end
local rows, bytes, limit = schema.ListProfileRecovery()
assert(limit == 2 * 1024 * 1024 and bytes <= limit, "account bytes exceed the fixed 2 MiB budget")
assert(#rows > 0 and #rows < 16, "deleted identities escaped the account budget")
assert(not schema.ExportProfileRecovery(first), "oldest entry was not evicted")
local exported = assert(schema.ExportProfileRecovery(last))
local data = assert(loadstring(exported))()
assert(data.future == string.rep("P", 120000) and data.zero == 0 and data.flag == false, "export changed original bytes")
local profiles = H.Literal(store.profiles)
assert(schema.PurgeProfileRecovery(last) == 1 and not schema.ExportProfileRecovery(last), "key purge failed")
assert(H.Literal(store.profiles) == profiles, "purge changed a live profile")
local commands = w.core.SlashCommands
local registry, captured = w.core.PublicGlobals
local ensure, show = registry.MSUF_EnsureOptionsLoaded, registry.MSUF_ShowCopyLink
registry.MSUF_EnsureOptionsLoaded = function() return true end
registry.MSUF_ShowCopyLink = function(_, text) captured = text end
local remaining = schema.ListProfileRecovery()
local key = remaining[#remaining].key
commands.Dispatch("recovery export " .. key)
assert(captured == schema.ExportProfileRecovery(key), "export command did not deliver complete copyable bytes")
registry.MSUF_EnsureOptionsLoaded, registry.MSUF_ShowCopyLink = ensure, show
assert(commands.Get("recovery"), "/msuf recovery is not registered")
assert(commands.Dispatch("recovery list") ~= false, "list command failed")
assert(commands.Dispatch("recovery purge all") ~= false, "purge command failed")
rows, bytes = schema.ListProfileRecovery()
assert(#rows == 0 and bytes <= limit, "purge retained recovery data")
-- Old saves without timestamps are migrated and bounded on login as well.
for i = 1, 12 do
    store._newerRevisionBackups = store._newerRevisionBackups or {}
    store._newerRevisionBackups["legacy" .. i] = { revision = 18, data = { future = string.rep("L", 240000) } }
end
schema.BeginRollbackSession(store)
rows, bytes = schema.ListProfileRecovery()
assert(bytes <= limit and #rows < 12, "legacy account was not bounded at login")
assert(loadstring(assert(schema.ExportProfileRecovery(rows[1].key))))()
local before = H.Literal(store)
schema.ListProfileRecovery()
assert(H.Literal(store) == before, "listing changed stable history")
schema.PurgeProfileRecovery("all")
for i = 1, 12 do
    store.profiles.Future = { _msufDefaultsRevision = 20, future = string.rep("X", limit) }
    schema.BackupNewerRevision(store.profiles.Future)
    schema.RenameProfileRecovery("Future")
end
local empty, emptyBytes = schema.ListProfileRecovery()
assert(#empty == 0 and emptyBytes < 1024, "oversized entries left empty archived buckets")
store._newerRevisionBackups = { Broken = { identity = 99,
    entries = { orphan = { data = { future = string.rep("x", limit + 100) } } }, order = {} } }
schema.BoundProfileRecovery(store)
local corruptRows, corruptBytes = schema.ListProfileRecovery()
assert(corruptBytes <= limit, "orphaned entries bypass account byte budget")
store._newerRevisionBackups = { Broken = { identity = 100, entries = { orphan = { data = { flag = false } } } } }
schema.BeginRollbackSession(store)
assert(schema.PurgeProfileRecovery("all") == 1, "unindexed history cannot be purged")
store._newerRevisionBackups = { Broken = string.rep("x", limit + 100) }
schema.BoundProfileRecovery(store)
local scalarRows, scalarBytes = schema.ListProfileRecovery()
assert(scalarBytes <= limit, "scalar recovery bucket bypassed byte budget")
store._newerRevisionBackups = { A = { identity = 1, entries = { a = { sequence = "bad", data = {} } }, order = { "a" } },
    B = { identity = 2, entries = { b = { sequence = 1, data = {} } }, order = { "b" } } }
schema.ListProfileRecovery()
schema.PurgeProfileRecovery("all")
store._profileRecoveryArchive = { unknown = string.rep("x", limit + 100) }
schema.BoundProfileRecovery(store)
local unknownRows, unknownBytes = schema.ListProfileRecovery()
assert(unknownBytes <= limit, "unrecognized archive group bypassed byte budget")
print(string.format("PASS recovery account %s: %d entries, %d / %d bytes", flavor, #rows, bytes, limit))
