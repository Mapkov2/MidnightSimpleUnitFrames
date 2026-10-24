-- Newer persisted profiles retain their original bytes before either normalizer writes.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local C = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local function Serial(value) return assert(loadstring("return " .. H.Literal(value)))() end
local source = C.NewWorld(root, flavor, "Tester-Realm")
C.Login(source, {})
local store = { profiles = { Default = Serial(source.env.MSUF_DB) } }
assert(source.core.DefaultsSchema.Persist(store))
local newer = store.profiles.Default
assert(type(newer._msufSparseDefaultsV2) == "string" and type(newer._msufSparseDefaultsV3) == "string")
newer._msufDefaultsRevision = 18
newer.general.barBgFillMode = "future-value"
newer.future = { [0] = false, nested = { empty = {}, zero = 0, text = "future\nbytes" }, list = { 1, false, "" } }
local original = H.Literal(newer)
store.profiles.Inactive = Serial(newer)
local world = C.NewWorld(root, flavor, "Tester-Realm")
C.Login(world, { MSUF_GlobalDB = store })
local env, ns = world.env, world.core
local backups = assert(env.MSUF_GlobalDB._newerRevisionBackups, "newer revision has no backup")
local function NoticeCount()
    local count = 0
    for _, text in ipairs(world.prints) do
        if text:find("newer MSUF revision", 1, true) then count = count + 1 end
    end
    return count
end
local entries = 0
for name, backup in pairs(backups) do
    entries = entries + 1
    assert(name == "Default" or name == "Inactive", "unexpected profile backup")
    assert(backup.revision == 18 and H.Literal(backup.data) == original, "backup differs from untouched revision 18")
    assert(backup.data ~= env.MSUF_GlobalDB.profiles[name], "backup aliases the working profile")
    assert(backup.data.general ~= env.MSUF_GlobalDB.profiles[name].general, "backup aliases a working owner")
end
assert(entries == 2 and NoticeCount() == 2, "backup/notice must be once per stored profile")
assert(env.MSUF_DB._msufDefaultsRevision == 17, "working profile no longer follows existing normalization")
local first, bytes = backups.Default, H.Literal(backups)
ns.ProfileMigrations.PrepareBinding(env.MSUF_DB)
ns.PublicGlobals.MSUF_InitProfiles()
assert(backups.Default == first and H.Literal(backups) == bytes, "second bind changed or added a backup")
assert(NoticeCount() == 2, "second bind repeated the notice")
-- The backup is SavedVariables data, so a later loader can restore it verbatim.
world:FireEvent("PLAYER_LOGOUT")
assert(H.Literal(backups) == bytes, "logout compaction changed the original backup")
local persisted = Serial(env.MSUF_GlobalDB)
assert(H.Literal(persisted._newerRevisionBackups.Default.data) == original, "serialized backup cannot be restored")
local reloaded = C.NewWorld(root, flavor, "Tester-Realm")
C.Login(reloaded, { MSUF_GlobalDB = persisted })
assert(H.Literal(reloaded.env.MSUF_GlobalDB._newerRevisionBackups) == bytes, "reload overwrote the backup")
for _, text in ipairs(reloaded.prints) do
    assert(not text:find("newer MSUF revision", 1, true), "existing backup repeated its notice")
end
-- The legacy standalone SavedVariable is copied before it joins the named
-- pool. It needs the same protection, under the resolved startup profile name.
for _, mode in ipairs({ "standalone", "empty-pool", "missing-active" }) do
    local standalone = C.NewWorld(root, flavor, "Tester-Realm")
    local saved = { MSUF_DB = Serial(first.data) }
    if mode == "empty-pool" then saved.MSUF_GlobalDB = { profiles = {} } end
    if mode == "missing-active" then
        saved.MSUF_DB = nil
        saved.MSUF_GlobalDB = { profiles = { Donor = Serial(first.data) },
            char = { ["Tester-Realm"] = { activeProfile = "Missing" } } }
    end
    C.Login(standalone, saved)
    local account = standalone.env.MSUF_GlobalDB
    local profileName = mode == "missing-active" and "Missing" or "Default"
    local backup = account._newerRevisionBackups and account._newerRevisionBackups[profileName]
    assert(backup and backup.revision == 18 and H.Literal(backup.data) == original,
        mode .. " newer profile has no untouched backup")
    standalone:FireEvent("PLAYER_LOGOUT")
    assert(standalone.env.MSUF_DB == nil and H.Literal(backup.data) == original,
        mode .. " backup did not survive terminal logout")
end
-- Ordinary revisions do not create backup storage or chat notices.
for _, revision in ipairs({ 16, 17 }) do
    local ordinary = Serial(source.env.MSUF_DB)
    ordinary._msufDefaultsRevision = revision
    local normal = C.NewWorld(root, flavor, "Tester-Realm")
    C.Login(normal, { MSUF_GlobalDB = { profiles = { Default = ordinary } } })
    assert(normal.env.MSUF_GlobalDB._newerRevisionBackups == nil, "ordinary revision created backup state")
    assert(normal.env.MSUF_DB._msufDefaultsRevision == 17, "ordinary normalization changed")
end
-- Revision rejection remains secret-safe before the backup decision.
local Secrets = assert(loadfile(root .. "/tools/tests/classpower_secrets.lua"))()
local secret = Secrets.New("number")
ns.Util.IsSecret = Secrets.IsSecret
local stop = Secrets.Watch({ root .. "/MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_Schema.lua" }, { strict = true })
assert(ns.DefaultsSchema.RestorePersistence({ _msufDefaultsRevision = secret }) == false)
local violations = stop()
assert(#violations == 0, table.concat(violations, "\n"))
print("PASS profile_newer_revision_backup_smoke " .. flavor)
