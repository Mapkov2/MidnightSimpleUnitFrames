-- A 6.5x Forever character with a surname keeps its profile on the first 7.0 login.
-- 6.5x stored the binding as "Name-Realm"; 7.0 keys "Name Surname-Realm".
local root, flavor = assert(arg[1]), arg[2] or "Forever"
local C = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local function Copy(value) return assert(loadstring("return " .. H.Literal(value)))() end
local fixture = C.LoadSavedVariablesFixture(root, "tools/fixtures/profiles/sv/sv_forever_beta_rev17.lua")
local historical = assert(fixture.MSUF_GlobalDB.profiles.Profile01)
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function Profile(width)
    local profile = Copy(historical)
    profile.player.width = width
    return profile
end
local function Surname(surname)
    return function(world)
        world.env.UnitName = function() return "Mapko", surname end
        world.env.Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }
    end
end
local function Login(saved, surname)
    local world = C.NewWorld(root, flavor, "Mapko-Realm", Surname(surname))
    C.Login(world, saved, true)
    Check(world.core.Lifecycle.Bound, "login failed to bind")
    local errors = C.UnexpectedErrors({ world = world, flavor = flavor }, {})
    Check(#errors == 0, table.concat(errors, "; "))
    return world, world.env
end
local account = {
    profiles = { Default = Profile(275), Main = Profile(333), Healer = Profile(301) },
    char = { ["Mapko-Realm"] = { activeProfile = "Main", specProfileMapVersion = 1, specAutoSwitch = true,
        specProfileMap = { [65] = "Healer" } } },
}
local original = H.Literal(account)
-- The 6.5x SavedVariables file also stores the active profile standalone.
local world, env = Login({ MSUF_GlobalDB = Copy(account), MSUF_DB = Profile(333) }, "Main")
local key = "Mapko Main-Realm"
Check(env.MSUF_ActiveProfile == "Main", "first 7.0 login lost the 6.5x profile: " .. tostring(env.MSUF_ActiveProfile))
Check(env.MSUF_DB == env.MSUF_GlobalDB.profiles.Main, "bound profile is not the stored Main profile")
Check(env.MSUF_DB.player.width == 333, "bound profile lost its settings")
Check(env.MSUF_GlobalDB.profiles.Default.player.width == 275 and env.MSUF_GlobalDB.profiles.Healer.player.width == 301,
    "startup replaced another profile")
local binding = env.MSUF_GlobalDB.char[key]
Check(type(binding) == "table" and binding.specAutoSwitch == true and binding.specProfileMap[65] == "Healer",
    "spec routing did not follow the profile")
local legacy = env.MSUF_GlobalDB.char["Mapko-Realm"]
Check(binding ~= legacy and binding.specProfileMap ~= legacy.specProfileMap, "new binding shares the 6.5x table")
Check(legacy.activeProfile == "Main", "6.5x binding changed")
Check(H.Literal(env.MSUF_GlobalDB._pre70ProfileBackup.char) == H.Literal(account.char), "safety copy holds adopted data")
-- Own choices win from now on; the 6.5x entry is left for 6.5x and its other characters.
Check(env.MSUF_SwitchProfile("Default"), "switch failed")
world:FireEvent("PLAYER_LOGOUT")
local saved = { MSUF_GlobalDB = Copy(env.MSUF_GlobalDB) }
world, env = Login(saved, "Main")
Check(env.MSUF_ActiveProfile == "Default", "own 7.0 choice was replaced by the 6.5x binding")
Check(env.MSUF_GlobalDB.char["Mapko-Realm"].activeProfile == "Main", "6.5x binding was rewritten")
-- Another surname that shared the 6.5x key starts where 6.5x left it.
world, env = Login({ MSUF_GlobalDB = Copy(account) }, "Alt")
Check(env.MSUF_ActiveProfile == "Main", "same-name character lost the shared 6.5x profile")
-- A restored pre-7.0 safety copy contains only the 6.5x key again.
world, env = Login({ MSUF_GlobalDB = Copy(account) }, "Main")
Check(env.MSUF_SwitchProfile("Default"), "switch failed")
Check(world.core.RestorePre70ProfileBackup(), "restore failed")
Check(env.MSUF_ActiveProfile == "Main", "restored safety copy lost the 6.5x profile")
-- Characters without a surname keep the unchanged key.
world, env = Login({ MSUF_GlobalDB = Copy(account) }, nil)
Check(env.MSUF_ActiveProfile == "Main", "surname-less character lost its binding")
Check(env.MSUF_GlobalDB.char["Mapko Main-Realm"] == nil, "surname-less login created a full-name binding")
Check(H.Literal(account) == original, "test input changed")
print("PASS forever_surname_upgrade_binding_smoke " .. flavor .. ": " .. checks .. " checks")
