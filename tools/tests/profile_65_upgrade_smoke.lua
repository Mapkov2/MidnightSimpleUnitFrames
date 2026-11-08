-- Older complete profiles keep explicit mana choices through upgrade/import.
local root, flavor = assert(arg[1]), assert(arg[2])
local C = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local function Copy(value) return assert(loadstring("return " .. H.Literal(value)))() end
local fixture = C.LoadSavedVariablesFixture(root, "tools/fixtures/profiles/sv/sv_forever_beta_rev17.lua")
local historical = fixture.MSUF_GlobalDB.profiles.Profile01
assert(historical and historical._msufProfileSchema == 600 and historical._msufDefaultsRevision == 17,
    "upgrade fixture must remain an actual pre-7.0 full profile")
local cases = {
    { "AbsentOff", false, false },
    { "StampedOff", false, false, true },
    { "FalseStampOff", false, false, false },
    { "AbsentOn", true, true },
    { "Missing" },
    { "StampedMissing", nil, nil, true },
    { "MixedMissing", false, nil, false },
    { "Mixed", true, false, true },
}
local function Profile(row)
    local profile = Copy(historical)
    profile.bars.manaRegenPause, profile.bars.manaGainPulse = row[2], row[3]
    profile._msufForeverFiveSecondDefault_v1, profile._msufForeverManaTickDefault_v1 = row[4], row[4]
    profile.player.width, profile.player.nameOffsetX = 341, 0
    profile.player.showHP, profile.player.portraitEnabled = false, false
    profile.general.barBgOpacity = 0
    profile.retainedData = { enabled = false, zero = 0, empty = {}, text = "" }
    return profile
end
local function Load(saved)
    local world = C.NewWorld(root, flavor, "Upgrade-Realm")
    C.Login(world, saved or {})
    assert(world.core.Lifecycle.Bound, "login failed to bind")
    local errors = C.UnexpectedErrors({ world = world, flavor = flavor }, {})
    assert(#errors == 0, table.concat(errors, "; "))
    return world
end
local function Check(profile, row, stage)
    local function SameChoice(value, expected)
        if expected ~= nil then return value == expected end
        if flavor == "Forever" then return value == true end
        return value == nil or value == false
    end
    assert(SameChoice(profile.bars.manaRegenPause, row[2]), stage .. ": changed saved five-second-rule choice " .. row[1])
    assert(SameChoice(profile.bars.manaGainPulse, row[3]), stage .. ": changed saved mana-tick choice " .. row[1])
    assert(profile.player.width == 341 and profile.player.nameOffsetX == 0
        and profile.player.showHP == false and profile.player.portraitEnabled == false
        and profile.general.barBgOpacity == 0, stage .. ": changed other explicit settings")
    if flavor == "Forever" then
        assert(profile._msufForeverFiveSecondDefault_v1 == true and profile._msufForeverManaTickDefault_v1 == true,
            stage .. ": missing settled migration stamps")
    end
end
local account = {
    profiles = {},
    char = { ["Upgrade-Realm"] = { activeProfile = "AbsentOff", specProfileMapVersion = 1,
        specProfileMap = { [1484] = "AbsentOff", [251] = "StampedOff" } },
        ["Other-Realm"] = { activeProfile = "Mixed", specProfileMapVersion = 1 } },
}
for _, row in ipairs(cases) do account.profiles[row[1]] = Profile(row) end
local original, bindings = H.Literal(account.profiles), H.Literal(account.char)
local world = Load({ MSUF_GlobalDB = Copy(account) })
local backup = assert(world.env.MSUF_GlobalDB._pre70ProfileBackup)
assert(H.Literal(backup.profiles) == original, "safety backup changed original old profiles")
local backupBytes = H.Literal(backup)
for pass = 1, 2 do
    assert(world.env.MSUF_ActiveProfile == "AbsentOff", "reload changed selected profile")
    assert(H.Literal(world.env.MSUF_GlobalDB.char) == bindings, "reload changed character/spec mapping")
    for _, row in ipairs(cases) do
        Check(world.env.MSUF_GlobalDB.profiles[row[1]], row, "inactive upgrade")
        assert(world.env.MSUF_SwitchProfile(row[1]))
        Check(world.env.MSUF_DB, row, "profile switch")
        assert(H.Literal(world.env.MSUF_DB.retainedData) == H.Literal(account.profiles[row[1]].retainedData),
            "upgrade changed extension data")
    end
    assert(world.env.MSUF_SwitchProfile("AbsentOff"))
    if pass == 1 then
        world:FireEvent("PLAYER_LOGOUT")
        world = Load({ MSUF_GlobalDB = Copy(world.env.MSUF_GlobalDB) })
        assert(H.Literal(world.env.MSUF_GlobalDB._pre70ProfileBackup) == backupBytes, "reload replaced safety copy")
    end
end
local imported = Load()
for index, row in ipairs(cases) do
    local text = H.Literal({ addon = "MSUF", fmt = 2, schema = 600, kind = "all", payload = Profile(row) })
    local ok, why = imported.core.PublicGlobals.MSUF_ImportFromString(text)
    assert(ok, "old full import failed: " .. tostring(why))
    Check(imported.env.MSUF_DB, row, "import into current")
    ok, why = imported.core.PublicGlobals.MSUF_ImportIntoNewProfile("Imported " .. index, text)
    assert(ok, "old full new-profile import failed: " .. tostring(why))
    Check(imported.env.MSUF_DB, row, "import into new")
end
local standalone = Load({ MSUF_DB = Profile(cases[1]) })
Check(standalone.env.MSUF_DB, cases[1], "standalone SavedVariable")
for _, checked in ipairs({ world, imported, standalone }) do
    local errors = C.UnexpectedErrors({ world = checked, flavor = flavor }, {})
    assert(#errors == 0, table.concat(errors, "; "))
end
local fresh = Load()
if flavor == "Forever" then
    assert(fresh.env.MSUF_DB.bars.manaRegenPause == true and fresh.env.MSUF_DB.bars.manaGainPulse == true,
        "fresh Forever login lost its current mana defaults")
    assert(fresh.env.MSUF_CreateProfile("Created"))
    assert(fresh.env.MSUF_GlobalDB.profiles.Created.bars.manaRegenPause == true
        and fresh.env.MSUF_GlobalDB.profiles.Created.bars.manaGainPulse == true,
        "new Forever factory profile lost its current mana defaults")
end
print("PASS profile_65_upgrade_smoke " .. flavor .. ": 8 historical states, active/inactive, import, switch, reload and fresh defaults")
