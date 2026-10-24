-- Rejection must be atomic through both normalizers, binding, switching and logout.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local C = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local function Copy(value) return assert(loadstring("return " .. H.Literal(value)))() end
local source = C.NewWorld(root, flavor, "Tester-Realm")
C.Login(source, {})
local seed = { profiles = { Default = Copy(source.env.MSUF_DB) } }
assert(source.core.DefaultsSchema.Persist(seed))
local sparse = seed.profiles.Default
assert(sparse._msufSparseDefaultsV3)
for _, kind in ipairs({ "v2-mask", "v3-mask", "missing-owner", "orphan-v3", "newer-owner", "scalar-owner" }) do
    local profile = Copy(sparse)
    profile.bars.bossCastbarOffsetY, profile.general.fontSlug = 0, true
    if kind == "v2-mask" then profile._msufSparseDefaultsV2 = "invalid"
    elseif kind == "v3-mask" then profile._msufSparseDefaultsV3 = "invalid"
    elseif kind == "missing-owner" then profile.player = nil
    elseif kind == "orphan-v3" then profile._msufSparseDefaultsV2 = nil
    elseif kind == "scalar-owner" then profile.player = false
    else profile._msufDefaultsRevision = 19 end
    local before = H.Literal(profile)
    local working, _, status = source.core.ProfileNormalize.TranslateProfileToCurrent(profile)
    assert(H.Literal(profile) == before, kind .. ": translator changed rejected bytes")
    assert(status == "rejected" and working ~= profile, kind .. ": no detached working copy")
    local repaired = source.core.PublicGlobals.MSUF_NormalizeProfileDefaults(profile, true)
    assert(repaired == working and H.Literal(profile) == before, kind .. ": defaults changed rejected bytes")
    assert(type(working.player) == "table", kind .. ": unsafe working owner")
    assert(working.bars.bossCastbarOffsetY == 0 and working.general.fontSlug == true, kind .. ": explicit values changed")
    local world = C.NewWorld(root, flavor, "Tester-Realm")
    local original = Copy(profile)
    C.Login(world, { MSUF_GlobalDB = { profiles = { Default = original, Inactive = Copy(profile) } } })
    local env, ns = world.env, world.core
    assert(H.Literal(env.MSUF_GlobalDB.profiles.Default) == before, kind .. ": login mutated stored profile")
    assert(H.Literal(env.MSUF_GlobalDB.profiles.Inactive) == before, kind .. ": login mutated inactive profile")
    assert(env.MSUF_DB ~= original and env.MSUF_DB.general ~= original.general, kind .. ": runtime aliases stored data")
    assert(env.MSUF_DB.bars.bossCastbarOffsetY == 0 and env.MSUF_DB.general.fontSlug == true, kind .. ": login lost explicit values")
    local backups = assert(env.MSUF_GlobalDB._rejectedProfileBackups, kind .. ": missing quarantine")
    assert(H.Literal(backups.Default.data) == before, kind .. ": quarantine changed bytes")
    local backupBytes = H.Literal(backups)
    env.MSUF_DB.bars.bossCastbarOffsetY = 123
    assert(ns.PublicGlobals.MSUF_SwitchProfile("Inactive"))
    assert(ns.PublicGlobals.MSUF_SwitchProfile("Default"))
    assert(env.MSUF_DB.bars.bossCastbarOffsetY == 123, kind .. ": session copy was lost")
    assert(ns.PublicGlobals.MSUF_CopyProfile("Default", "Copy"))
    assert(H.Literal(env.MSUF_GlobalDB.profiles.Copy) == before, kind .. ": copied rejection normalized in place")
    ns.PublicGlobals.MSUF_InitProfiles()
    backupBytes = H.Literal(backups)
    world:FireEvent("PLAYER_LOGOUT")
    assert(H.Literal(env.MSUF_GlobalDB.profiles.Default) == before, kind .. ": logout changed original")
    assert(H.Literal(backups) == backupBytes, kind .. ": backup mutated")
    local reloaded = C.NewWorld(root, flavor, "Tester-Realm")
    C.Login(reloaded, { MSUF_GlobalDB = Copy(env.MSUF_GlobalDB) })
    assert(H.Literal(reloaded.env.MSUF_GlobalDB.profiles.Default) == before, kind .. ": reload changed original")
    assert(H.Literal(reloaded.env.MSUF_GlobalDB._rejectedProfileBackups) == backupBytes, kind .. ": reload duplicated quarantine")
end
-- Wrong-type owners need safe runtime shapes without editing stored input.
for _, owner in ipairs({ "general", "bars", "player" }) do
    local profile = Copy(sparse)
    profile[owner] = false
    local before = H.Literal(profile)
    local working = source.core.PublicGlobals.MSUF_NormalizeProfileDefaults(profile, true)
    assert(type(working[owner]) == "table" and H.Literal(profile) == before, "unsafe recovery owner: " .. owner)
end
-- Untrusted malformed storage envelopes are rejected transactionally on import.
local world = C.NewWorld(root, flavor, "Tester-Realm")
local bad = Copy(sparse)
bad.bars.bossCastbarOffsetY, bad.general.fontSlug, bad._msufSparseDefaultsV3 = 0, true, "invalid"
C.Login(world, { MSUF_GlobalDB = { profiles = { Default = Copy(source.env.MSUF_DB), Bad = bad } } })
local env, ns = world.env, world.core
local rawBytes, before = H.Literal(bad), H.Literal(env.MSUF_GlobalDB)
local function Wire(payload)
    return H.Literal({ addon = "MSUF", fmt = 2, schema = 600, kind = "all", payload = payload })
end
assert(not ns.PublicGlobals.MSUF_ImportFromString(Wire(bad)), "active malformed import accepted")
assert(not ns.PublicGlobals.MSUF_ImportExternal(Wire(bad), "Bad"), "external malformed import accepted")
assert(H.Literal(env.MSUF_GlobalDB) == before, "rejected import changed account data")
local ok, wire = ns.PublicGlobals.MSUF_ExportExternal("Bad")
assert(ok, "quarantined inactive export failed")
local decoded = assert(ns.PublicGlobals.MSUF_TryDecodeCompactString(wire))
local payload = decoded.msuf6 and decoded.msuf6.payload or decoded.payload
assert(payload._msufSparseDefaultsV2 == nil and payload._msufSparseDefaultsV3 == nil, "export retained rejected masks")
assert(payload.bars.bossCastbarOffsetY == 0 and payload.general.fontSlug == true, "export ignored working copy")
assert(H.Literal(bad) == rawBytes, "export changed stored rejection")
local valid = Copy(source.env.MSUF_DB)
valid.bars.bossCastbarOffsetY = 71
assert(ns.PublicGlobals.MSUF_ImportExternal(Wire(valid), "Bad"), "replacement import failed")
assert(env.MSUF_GlobalDB.profiles.Bad ~= bad and H.Literal(bad) == rawBytes, "replacement mutated rejected original")
assert(ns.PublicGlobals.MSUF_SwitchProfile("Bad"))
assert(env.MSUF_DB.bars.bossCastbarOffsetY == 71, "replacement bound stale recovery copy")
env.MSUF_GlobalDB.profiles.ActiveBad = Copy(bad)
assert(ns.PublicGlobals.MSUF_SwitchProfile("ActiveBad"))
local active = env.MSUF_DB
assert(ns.PublicGlobals.MSUF_ImportExternal(Wire(valid), "ActiveBad"))
assert(not ns.DefaultsSchema.IsQuarantinedProfile(active), "successful active import kept stale quarantine flag")
assert(env.MSUF_DB.bars.bossCastbarOffsetY == 71, "active replacement lost imported value")
local schema = source.core.DefaultsSchema
local changed, status = schema.RestorePersistence({})
assert(changed == false and status == "not-sparse", "ordinary profile indistinguishable from rejection")
changed, status = schema.RestorePersistence(Copy(sparse))
assert(changed == true and status == "restored", "successful reconstruction indistinguishable from rejection")
print("PASS profile_decoder_quarantine_smoke " .. flavor)
