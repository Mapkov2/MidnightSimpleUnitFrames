-- One independent, non-growing account snapshot before migration or sparse persistence.
local root, flavor = assert(arg[1]), assert(arg[2])
local C = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local function Serial(value) return assert(loadstring("return " .. H.Literal(value)))() end
local function Load(saved, character)
    local w = C.NewWorld(root, flavor, character or "Tester-Realm")
    C.Login(w, Serial(saved or {}))
    return w, w.env, w.core
end
local maxBytes, cases = 0, 0
for _, entry in ipairs(C.Manifest(root)) do
    local relevant = false
    for _, client in ipairs(entry.clients) do if client == flavor then relevant = true end end
    if entry.kind == "sv" and relevant then
        local saved = C.LoadSavedVariablesFixture(root, entry.file)
        local input = saved.MSUF_GlobalDB and saved.MSUF_GlobalDB.profiles
        if type(input) ~= "table" or next(input) == nil then input = { Default = saved.MSUF_DB } end
        local expected = H.Literal(input)
        local w, env, ns = Load(saved, entry.login)
        local backup = assert(env.MSUF_GlobalDB._pre70ProfileBackup, "pre-7.0 safety copy missing")
        assert(H.Literal(backup.profiles) == expected, entry.id .. ": safety copy changed pre-login data")
        local backupBytes = H.Literal(backup)
        maxBytes = math.max(maxBytes, #backupBytes)
        local active = env.MSUF_DB
        active.general.rollbackLiveEdit = "after backup"
        env.MSUF_GlobalDB.profiles.Later = C.Copy(active)
        w:FireEvent("PLAYER_LOGOUT")
        assert(H.Literal(backup) == backupBytes, "logout edited/expanded safety copy")
        local disk = Serial(env.MSUF_GlobalDB)
        w, env, ns = Load({ MSUF_GlobalDB = disk }, entry.login)
        assert(H.Literal(env.MSUF_GlobalDB._pre70ProfileBackup) == backupBytes, "reload replaced safety copy")
        local before = H.Literal(env.MSUF_GlobalDB.profiles)
        ns.SlashCommands.Dispatch("restorebackup")
        assert(H.Literal(env.MSUF_GlobalDB.profiles) == before, "restore ran without confirmation")
        ns.SlashCommands.Dispatch("restorebackup cancel")
        ns.SlashCommands.Dispatch("restorebackup confirm")
        assert(H.Literal(env.MSUF_GlobalDB.profiles) == before, "cancelled request was confirmed")
        ns.SlashCommands.Dispatch("restorebackup")
        ns.SlashCommands.Dispatch("restorebackup confirm")
        assert(env.MSUF_GlobalDB.profiles.Later == nil, "restore left later profiles in account")
        assert(env.MSUF_DB == env.MSUF_GlobalDB.profiles[env.MSUF_ActiveProfile], "restore did not rebind runtime")
        assert(H.Literal(env.MSUF_GlobalDB._pre70ProfileBackup) == backupBytes, "restore edited safety copy")
        -- Direct restore gives the original bytes before ordinary login migrations run.
        assert(ns.DefaultsSchema.RestoreRollbackBackup(env.MSUF_GlobalDB))
        assert(H.Literal(env.MSUF_GlobalDB.profiles) == expected, "explicit restore changed raw original values")
        assert(env.MSUF_GlobalDB.profiles ~= env.MSUF_GlobalDB._pre70ProfileBackup.profiles, "restore aliased safety copy")
        cases = cases + 1
    end
end
local w, env, ns = Load()
local backup = assert(env.MSUF_GlobalDB._pre70ProfileBackup)
assert(backup.profiles.Default and backup.profiles.Default._msufDefaultsRevision == 17, "fresh account snapshot not full")
local text = H.Literal(backup)
ns.SlashCommands.Dispatch("restorebackup")
env.InCombatLockdown = function() return true end
ns.SlashCommands.Dispatch("restorebackup confirm")
assert(H.Literal(env.MSUF_GlobalDB._pre70ProfileBackup) == text, "combat edited backup")
env.InCombatLockdown = function() return false end
w:FireEvent("PLAYER_LOGOUT")
-- Existing sparse accounts can retain only the full data the current loader can reconstruct.
local disk = Serial(env.MSUF_GlobalDB)
disk._pre70ProfileBackup = nil
w, env, ns = Load({ MSUF_GlobalDB = disk })
backup = assert(env.MSUF_GlobalDB._pre70ProfileBackup)
assert(backup.source == "reconstructed", "already-sparse snapshot provenance missing")
assert(backup.profiles.Default._msufSparseDefaultsV3 == nil and backup.profiles.Default._msufDefaultsRevision == 17)
-- Oversize/cyclic inputs cannot create a partial snapshot or later replace
-- it with an already-migrated copy in the same session.
local oversize = { profiles = { Large = C.Copy(env.MSUF_DB) } }
oversize.profiles.Large.text = string.rep("x", 3 * 1024 * 1024)
assert(not ns.DefaultsSchema.CaptureRollbackBackup(oversize), "snapshot size bound was ignored")
assert(oversize._pre70ProfileBackup == nil, "oversize input left a partial snapshot")
oversize.profiles.Large.text = "later edit"
assert(not ns.DefaultsSchema.CaptureRollbackBackup(oversize), "failed original capture was replaced with later data")
local cyclic = { profiles = {} }
cyclic.profiles.One = cyclic
assert(not ns.DefaultsSchema.CaptureRollbackBackup(cyclic), "cyclic snapshot accepted")
env.MSUF_GlobalDB = oversize
assert(not ns.DefaultsSchema.Persist(oversize), "live account compacted without a complete safety copy")
assert(oversize.profiles.Large._msufSparseDefaultsV3 == nil and oversize.profiles.Large._msufDefaultsRevision == 17,
    "missing-backup refusal changed the full live profile")
print("profile_rollback_backup_smoke: " .. flavor .. " " .. cases .. " pre-login corpus snapshots unchanged; max literal bytes " .. maxBytes)
