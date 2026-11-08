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
newer._msufDefaultsRevision = 19
newer.general.barBgFillMode = "future-value"
newer.future = { [0] = false, nested = { empty = {}, zero = 0, text = "future\nbytes" }, list = { 1, false, "" } }
local original = H.Literal(newer)
store.profiles.Inactive = Serial(newer)
local world = C.NewWorld(root, flavor, "Tester-Realm")
C.Login(world, { MSUF_GlobalDB = store })
local env, ns = world.env, world.core
do
    local file = assert(io.open(root .. "/MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_Migrations.lua", "rb"))
    local defaults = file:read("*a")
    file:close()
    local revision = assert(tonumber(defaults:match("local MSUF_DEFAULTS_CURRENT_REVISION = (%d+)")))
    assert(revision ~= 18, "defaults revision 18 is reserved for the 6.5 release line")
end
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
    assert(backup.revision == 19 and H.Literal(backup.data) == original, "backup differs from untouched revision 19")
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
    assert(backup and backup.revision == 19 and H.Literal(backup.data) == original,
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
do
    -- 6.510 stamps a loaded sparse 7.0 profile as revision 18 without clearing
    -- either mask. Its edits stay authoritative when the missing leaves decode.
    local restamped = { profiles = { Default = Serial(source.env.MSUF_DB) } }
    assert(ns.DefaultsSchema.Persist(restamped))
    restamped.profiles.Default._msufDefaultsRevision = 18
    restamped.profiles.Default.player.width = 347
    restamped.profiles.Default.player.showHP = false
    restamped.profiles.Default.player.nameOffsetX = 0
    restamped.profiles.Inactive = Serial(restamped.profiles.Default)
    local expected = Serial(restamped.profiles.Default)
    expected._msufDefaultsRevision = 17.5
    assert(ns.DefaultsSchema.RestorePersistence(expected))
    local direct = Serial(restamped.profiles.Default)
    local accepted, status = ns.DefaultsSchema.RestorePersistence(direct)
    assert(accepted and status == "restored" and H.Literal(direct) == H.Literal(expected),
        "a 6.510 restamp must decode the old mask without overwriting its edits")
    for _, marker in ipairs({ "_msufSparseDefaultsV2", "_msufSparseDefaultsV3" }) do
        local broken = Serial(restamped.profiles.Default)
        broken[marker] = broken[marker]:sub(2)
        local bytes = H.Literal(broken)
        assert(not ns.DefaultsSchema.RestorePersistence(broken) and H.Literal(broken) == bytes,
            "a malformed revision-18 mask bypassed validation or partly decoded")
    end
    local back = C.NewWorld(root, flavor, "Tester-Realm")
    C.Login(back, { MSUF_GlobalDB = restamped }, true)
    assert(back.core.Lifecycle.Bound and back.env.MSUF_DB == restamped.profiles.Default,
        "return from 6.510 detached the active profile, so later edits would be lost")
    for _, profile in pairs(restamped.profiles) do
        assert(profile.player.width == 347 and profile.player.showHP == false and profile.player.nameOffsetX == 0)
        assert(profile._msufDefaultsRevision == 17 and profile._msufSparseDefaultsV2 == nil
            and profile._msufSparseDefaultsV3 == nil, "inactive 6.510 restamp did not decode")
    end
    assert(restamped._newerRevisionBackups == nil, "known 6.510 data entered future-revision recovery")
    back.env.MSUF_DB.player.width = 359
    back:FireEvent("PLAYER_LOGOUT")
    local reloaded = C.NewWorld(root, flavor, "Tester-Realm")
    C.Login(reloaded, { MSUF_GlobalDB = Serial(restamped) }, true)
    assert(reloaded.env.MSUF_DB == reloaded.env.MSUF_GlobalDB.profiles.Default
        and reloaded.env.MSUF_DB.player.width == 359, "post-return edit was lost at the next login")
    assert(reloaded.core.DefaultsSchema.PersistCompat(reloaded.env.MSUF_GlobalDB), "post-return compatibility save failed")
end

do
    local function FullRevision18()
        local profile = Serial(source.env.MSUF_DB)
        profile._msufDefaultsRevision = 18
        profile._msufStateSchema = nil
        profile._msufForeverFiveSecondDefault_v1 = true
        profile.bars.manaRegenPause = false
        profile.player.width = 341
        profile.player.portraitDragonArtwork = nil
        profile.retainedData = { enabled = false, offset = 0, list = { "keep", false } }
        return profile
    end

    local direct = FullRevision18()
    local expected = Serial(direct)
    expected._msufDefaultsRevision = 17
    local changed, status = ns.DefaultsSchema.RestorePersistence(direct)
    assert(changed and status == "restored" and H.Literal(direct) == H.Literal(expected),
        "decoding a full 6.5 revision-18 profile must only change its defaults revision")

    local active, inactive = FullRevision18(), FullRevision18()
    inactive._msufStateSchema = 700 -- Profile already seen by an earlier 7.0 login.
    local activeBytes, inactiveBytes = H.Literal(active), H.Literal(inactive)
    local history = { Other = Serial(first) }
    local historyBytes = H.Literal(history)
    local account = {
        profiles = { Default = active, Inactive = inactive },
        char = { ["Tester-Realm"] = { activeProfile = "Default", specProfileMap = { "Inactive" } } },
        _newerRevisionBackups = history,
    }
    local function CheckUserSettings(profile)
        assert(profile.player.width == 341 and profile.bars.manaRegenPause == false,
            "revision-18 upgrade overwrote user settings")
        assert(profile._msufForeverFiveSecondDefault_v1 == true, "upgrade lost the 6.5 Forever mana stamp")
        assert(profile.player.portraitDragonArtwork == false, "upgrade skipped the 7.0 portrait defaults")
        assert(H.Literal(profile.retainedData) == H.Literal(expected.retainedData),
            "revision-18 upgrade changed opaque data")
    end
    local function CheckLogin(w)
        local saved = w.env.MSUF_GlobalDB
        assert(w.core.Lifecycle.Bound and w.env.MSUF_DB == saved.profiles.Default, "7.0 login did not bind the selected profile")
        assert(saved.char["Tester-Realm"].specProfileMap[1] == "Inactive", "upgrade changed a character's profile mapping")
        for _, profile in pairs(saved.profiles) do
            assert(profile._msufDefaultsRevision == 17, "a full revision-18 profile would retry the upgrade")
            CheckUserSettings(profile)
        end
        assert(H.Literal(saved._newerRevisionBackups) == historyBytes, "upgrade changed the existing recovery history")
        local snapshot = assert(saved._pre70ProfileBackup)
        assert(H.Literal(snapshot.profiles.Default) == activeBytes and H.Literal(snapshot.profiles.Inactive) == inactiveBytes,
            "the rollback snapshot must retain the original revision-18 profiles")
    end
    local upgraded = C.NewWorld(root, flavor, "Tester-Realm")
    C.Login(upgraded, { MSUF_GlobalDB = account }, true)
    CheckLogin(upgraded)
    upgraded:FireEvent("PLAYER_LOGOUT")
    local secondLogin = C.NewWorld(root, flavor, "Tester-Realm")
    C.Login(secondLogin, { MSUF_GlobalDB = Serial(account) }, true)
    CheckLogin(secondLogin)

    local legacyOnly = C.NewWorld(root, flavor, "Tester-Realm")
    C.Login(legacyOnly, { MSUF_DB = FullRevision18() }, true)
    assert(legacyOnly.core.Lifecycle.Bound and legacyOnly.env.MSUF_DB._msufDefaultsRevision == 17)
    assert(legacyOnly.env.MSUF_GlobalDB._newerRevisionBackups == nil)
    CheckUserSettings(legacyOnly.env.MSUF_DB)

    local legacyAccount = legacyOnly.env.MSUF_GlobalDB
    local legacySchema = legacyOnly.core.DefaultsSchema
    assert(legacySchema.RestoreRollbackBackup(legacyAccount))
    assert(legacyAccount.profiles.Default._msufDefaultsRevision == 18)
    assert(legacySchema.PersistCompat(legacyAccount), "cannot write restored 6.5 data in the full compatibility format")
    assert(legacyAccount.profiles.Default._msufDefaultsRevision == 17)
    CheckUserSettings(legacyAccount.profiles.Default)

    for _, invalid in ipairs({
        function(profile) profile._msufDefaultsRevision = "18" end,
        function(profile) profile._msufProfileSchema = nil end,
        function(profile) profile._msufProfileSchema = 601 end,
        function(profile) profile._msufStateSchema = 701 end,
        function(profile) profile.player = false end,
        function(profile) profile._msufSparseDefaultsV3 = "unknown" end,
    }) do
        local profile = FullRevision18()
        invalid(profile)
        local bytes = H.Literal(profile)
        local persisted = legacyOnly.env.MSUF_GlobalDB
        persisted.profiles.Unknown = profile
        legacyOnly.core.DefaultsSchema.RestorePersistence(profile)
        local backup = assert(persisted._newerRevisionBackups and persisted._newerRevisionBackups.Unknown,
            "unknown revision-18 data bypassed recovery")
        assert(H.Literal(backup.data) == bytes, "recovery backup changed original data")
        assert(profile._msufDefaultsRevision ~= 17, "unknown revision-18 data was marked current")
    end
end

-- Revision rejection remains secret-safe before the backup decision.
local Secrets = assert(loadfile(root .. "/tools/tests/classpower_secrets.lua"))()
local secret = Secrets.New("number")
ns.Util.IsSecret = Secrets.IsSecret
local defaultsPath = root .. "/MidnightSimpleUnitFrames/State/Defaults/"
local stop = Secrets.Watch({
    defaultsPath .. "MSUF_Defaults_Schema.lua",
    defaultsPath .. "MSUF_Defaults_Storage.lua",
}, { strict = true })
assert(ns.DefaultsSchema.RestorePersistence({ _msufDefaultsRevision = secret }) == false)
for _, key in ipairs({ "_msufProfileSchema", "_msufStateSchema", "_msufSparseDefaultsV2", "_msufSparseDefaultsV3" }) do
    local profile = Serial(source.env.MSUF_DB)
    profile._msufDefaultsRevision = 18
    profile[key] = secret
    assert(ns.DefaultsSchema.RestorePersistence(profile) == false and profile._msufDefaultsRevision == 18)
end
local violations = stop()
assert(#violations == 0, table.concat(violations, "\n"))
print("PASS profile_newer_revision_backup_smoke " .. flavor)
