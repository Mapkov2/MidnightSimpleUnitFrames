-- Legacy selections settle before binding; media registration never mutates profiles.
local root = assert(arg[1], "repository root required")
local flavor = arg[2] or "Mainline"
local Corpus = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local names = {
    { "MSUF Flat", "Solid" },
    { "Midnight Charcoal", "MSUF Charcoal" },
    { "Midnight Minimalist", "MSUF Minimalist" },
    { "Midnight Slickrock", "MSUF Slickrock" },
    { "Midnight Smooth", "MSUF Smooth" },
    { "Midnight Smooth v2", "MSUF Smooth v2" },
    { "Midnight Smoother", "MSUF Smoother" },
    { "MSUF Lucent", "MSUF Lucent" },
    { "Third-party texture", "Third-party texture" },
}
local function Profile(name)
    return { _msufProfileSchema = 600, general = { barTexture = name, castbarTexture = name } }
end
local cases = 0
for _, row in ipairs(names) do
    for _, source in ipairs({ "selected", "default", "standalone" }) do
        local world = Corpus.NewWorld(root, flavor, "Tester-Realm")
        local env, ns = world.env, world.core
        local donor = Profile(row[1])
        local saved = { MSUF_DB = Profile("Third-party texture") }
        if source == "standalone" then
            saved.MSUF_DB = donor
        else
            saved.MSUF_GlobalDB = {
                profiles = { Default = source == "default" and donor or Profile("MSUF Lucent"), Chosen = donor },
                char = { ["Tester-Realm"] = { activeProfile = source == "selected" and "Chosen" or "Missing" } },
            }
        end
        local initialize = env.MSUF_InitProfiles
        local observed = false
        env.MSUF_InitProfiles = function(startup)
            assert(ns.Lifecycle.Phase == "bind", "binding ran outside its phase")
            local general = assert(startup.profile).general
            assert(general.barTexture == row[2] and general.castbarTexture == row[2], "migration reached bind too late")
            observed = true
            return initialize(startup)
        end
        Corpus.Login(world, saved)
        assert(observed, "startup bypassed the migration-to-bind boundary")
        assert(env.MSUF_DB.general.barTexture == row[2], "bound bar texture changed")
        assert(env.MSUF_DB.general.castbarTexture == row[2], "bound castbar texture changed")
        cases = cases + 1
    end
end

local world = Corpus.NewWorld(root, flavor, "Tester-Realm")
local env, ns = world.env, world.core
local registered = 0
ns.LSM = { Register = function() registered = registered + 1 end }
env.MSUF_BUNDLED_FONTS_REGISTERED = false
env.MSUF_DB = Profile("Midnight Smooth")
local scheduled = {}
env.C_Timer.After = function(_, callback) scheduled[#scheduled + 1] = callback end
env.MSUF_RegisterBundledMediaWithLSM()
assert(registered > 0, "media registration did not run")
assert(#scheduled == 0, "media registration scheduled a profile migration")
assert(env.MSUF_DB.general.barTexture == "Midnight Smooth", "media registration changed the profile")
local Literal = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))().Literal
local boundaries = 0
local function LateMedia(world)
    local runtime, namespace = world.env, world.core
    local before = Literal(runtime.MSUF_GlobalDB)
    local registrations, callbacks = 0, {}
    namespace.LSM = { Register = function() registrations = registrations + 1 end }
    runtime.MSUF_BUNDLED_FONTS_REGISTERED = false
    runtime.C_Timer.After = function(_, fn) callbacks[#callbacks + 1] = fn end
    runtime.MSUF_RegisterBundledMediaWithLSM()
    assert(registrations > 0, "late registration lost its media work")
    assert(#callbacks == 0, "late registration retained the legacy profile timer")
    assert(Literal(runtime.MSUF_GlobalDB) == before, "late registration mutated bound or inactive profiles")
end
local function CheckNames(profile, row, path)
    assert(profile.general.barTexture == row[2] and profile.general.castbarTexture == row[2],
        path .. " left legacy texture selections before apply")
end
for index, row in ipairs(names) do
    local current = Corpus.NewWorld(root, flavor, "Tester-Realm")
    Corpus.Login(current, { MSUF_GlobalDB = {
        profiles = { Default = Profile("MSUF Lucent") },
        char = { ["Tester-Realm"] = { activeProfile = "Default" } },
    } })
    local runtime = current.env
    local template = Corpus.Copy(runtime.MSUF_DB)
    for _, path in ipairs({ "switch", "stampedSwitch", "copy", "active", "new", "externalActive", "externalStored" }) do
        local donor = Corpus.Copy(template)
        donor.general.barTexture, donor.general.castbarTexture = row[1], row[1]
        if path == "switch" then donor._msufStateSchema = nil end
        local target, ok, why
        if path == "switch" or path == "stampedSwitch" then
            runtime.MSUF_GlobalDB.profiles.Legacy = donor
            ok, why = runtime.MSUF_SwitchProfile("Legacy")
            target = runtime.MSUF_DB
        elseif path == "copy" then
            runtime.MSUF_GlobalDB.profiles.Legacy = donor
            ok, why = runtime.MSUF_CopyProfile("Legacy", "Copied")
            target = runtime.MSUF_GlobalDB.profiles.Copied
        else
            local text = Literal({ addon = "MSUF", fmt = 2, schema = 600, kind = "all", payload = donor })
            if path == "active" then
                ok, why = runtime.MSUF_ImportFromString(text)
                target = runtime.MSUF_DB
            elseif path == "new" then
                ok, why = runtime.MSUF_ImportIntoNewProfile("Imported" .. index, text)
                target = runtime.MSUF_GlobalDB.profiles["Imported" .. index]
            else
                local name = path == "externalActive" and runtime.MSUF_ActiveProfile or "Stored" .. index
                ok, why = runtime.MSUF_ImportExternal(text, name)
                target = runtime.MSUF_GlobalDB.profiles[name]
            end
        end
        assert(ok, path .. " boundary failed: " .. tostring(why))
        CheckNames(assert(target, path .. " has no normalized profile"), row, path)
        LateMedia(current)
        CheckNames(target, row, path .. " late media")
        boundaries = boundaries + 1
    end
end
print("profile_texture_migration_phase_smoke: ok (" .. flavor .. ", " .. cases
    .. " startup and " .. boundaries .. " activation/copy/import cases)")
